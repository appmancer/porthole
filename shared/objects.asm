.objects_start
; Static object instance lists (tile-aligned stamps).
;
; Each entry is 10 bytes:
; 0: x (cell)
; 1: y (cell)
; 2: stripe_count (1/2/4); 0 terminates table
; 3: bytes_per_stripe (16/32)
; 4: stride (usually 16/32)
; 5: flags
;    bit0 = masked
;    bit7 = enabled (0 = skip)
; 6: sprite_ptr lo
; 7: sprite_ptr hi
; 8: mask_ptr lo
; 9: mask_ptr hi

STATIC_OBJ_ENTRY_SIZE = 10
STATIC_OBJ_FLAG_MASKED = 1
STATIC_OBJ_FLAG_ENABLED = &80

; Pointer table indexed by current_room.
; Must have MAX_ROOMS entries; unused rooms point to the shared end marker.
.static_objects_room_pointers
    EQUW static_objects_room0
    EQUW static_objects_room1
    EQUW static_objects_empty
    EQUW static_objects_empty
    EQUW static_objects_empty
    EQUW static_objects_empty
    EQUW static_objects_empty
    EQUW static_objects_empty


; Room 0 objects
.static_objects_room0
    ; End
    EQUB 0,0,0


; Room 1 objects
.static_objects_room1
    ; End
    EQUB 0,0,0


; Shared end marker for rooms with no static objects.
.static_objects_empty
    EQUB 0,0,0


; Enable a static object entry by setting flags bit7.
; Input: temp_sprite_ptr points to the flags byte.
.enable_static_object
    LDY #0
    LDA (temp_sprite_ptr),Y
    ORA #STATIC_OBJ_FLAG_ENABLED
    STA (temp_sprite_ptr),Y
    RTS


; Disable a static object entry by clearing flags bit7.
; Input: temp_sprite_ptr points to the flags byte.
.disable_static_object
    LDY #0
    LDA (temp_sprite_ptr),Y
    AND #&7F
    STA (temp_sprite_ptr),Y
    RTS


; --- Sentry bullet visual effect ---
; Horizontal XOR lines across killzones, drawn after sprites, erased before restores.

; LFSR state (must be non-zero). Persists across frames for variety.
.rng_state       EQUB &A7

; Number of active bullet descriptors (0 or 2).
.bullet_count    EQUB 0

; Bullet descriptors: 2 entries x 4 bytes (addr_lo, addr_hi, cell_count, color).
.bullet_descs    SKIP 8


; 8-bit Galois LFSR. Result in A.
.rng_next
    LDA rng_state
    LSR A
    BCC rng_nf
    EOR #&B4
.rng_nf
    STA rng_state
    RTS


; Erase all active bullet lines from the screen.
; Called before sprite restore (so save-under buffers capture clean bg).
; Clobbers: A, Y, screen_ptr, col_counter, temp_y
.erase_sentry_bullets
    LDA bullet_count
    BEQ esb_done
    ; Erase bullet 0
    LDA bullet_descs+0 : STA screen_ptr
    LDA bullet_descs+1 : STA screen_ptr+1
    LDA bullet_descs+2 : STA col_counter
    LDA bullet_descs+3 : STA temp_y
    JSR xor_hline
    ; Erase bullet 1 (if present)
    LDA bullet_count : CMP #2 : BNE esb_erased
    LDA bullet_descs+4 : STA screen_ptr
    LDA bullet_descs+5 : STA screen_ptr+1
    LDA bullet_descs+6 : STA col_counter
    LDA bullet_descs+7 : STA temp_y
    JSR xor_hline
.esb_erased
    LDA #0 : STA bullet_count
.esb_done
    RTS


; Draw new bullet lines for active sentry killzones.
; Called after all sprites are drawn.
; Clobbers: A, X, Y, temp_sprite_ptr, los_*, screen_ptr, col_counter, temp_y
.draw_sentry_bullets
    LDA room_killzone_count
    BEQ dsb_done

    LDA room_killzone_ptr : STA temp_sprite_ptr
    LDA room_killzone_ptr+1 : STA temp_sprite_ptr+1

    LDY #0
    LDX room_killzone_count
.dsb_kz_loop
    ; Read killzone: x0, y0, x1, y1, sentry_idx (5 bytes)
    LDA (temp_sprite_ptr),Y : INY : STA los_x0
    LDA (temp_sprite_ptr),Y : INY : STA los_y0
    LDA (temp_sprite_ptr),Y : INY : STA los_x1
    LDA (temp_sprite_ptr),Y : INY : STA los_y1
    LDA (temp_sprite_ptr),Y : INY
    STY los_err
    TAY
    LDA obj_state,Y
    AND #&FE              ; mask direction bit
    BNE dsb_kz_next       ; skip if disabled/carried

    ; Check if Chell is in the killzone's vertical band.
    ; Chell y range: [chell_y, chell_y+31], killzone: [los_y0, los_y1)
    JSR calc_char_y
    CMP los_y1 : BCS dsb_kz_next     ; chell_top >= kz_y1: below
    CLC : ADC #31
    CMP los_y0 : BCC dsb_kz_next     ; chell_bottom < kz_y0: above

    ; Active killzone — compute cell range
    LDA los_x0 : LSR A : LSR A : LSR A
    STA los_dx            ; start_cell
    LDA los_x1 : SEC : SBC #1 : LSR A : LSR A : LSR A
    SEC : SBC los_dx : CLC : ADC #1
    STA los_dy            ; cell_count

    ; Draw 2 bullets
    LDX #0 : JSR draw_one_bullet
    LDX #4 : JSR draw_one_bullet
    LDA #2 : STA bullet_count
    RTS                   ; done after first active killzone

.dsb_kz_next
    LDY los_err
    DEX : BNE dsb_kz_loop
.dsb_done
    RTS


; Draw one bullet line and save its descriptor.
; Input: X = offset into bullet_descs (0 or 4).
;        los_dx = start cell, los_dy = cell count.
;        los_y0, los_y1 = killzone y range (game pixels).
; Clobbers: A, Y, screen_ptr, col_counter, temp_y
.draw_one_bullet
    STX los_steps

    ; Random y in [y0, y0+8)
    JSR rng_next
    AND #&07
    CLC : ADC los_y0
.dob_y_ok
    STA los_sx

    ; Screen address high byte: &58 + (y >> 3)
    LSR A : LSR A : LSR A
    CLC : ADC #&58
    STA screen_ptr+1

    ; Screen address low byte: (y AND 7) + start_cell * 16
    LDA los_sx : AND #7
    STA screen_ptr
    LDA los_dx : ASL A : ASL A : ASL A : ASL A
    CLC : ADC screen_ptr
    STA screen_ptr
    BCC dob_addr_ok
    INC screen_ptr+1
.dob_addr_ok

    ; Random color: &0F (red) or &FF (yellow)
    JSR rng_next
    AND #1
    BEQ dob_red
    LDA #&FF : BNE dob_color_ok
.dob_red
    LDA #&0F
.dob_color_ok
    STA temp_y

    ; Save bullet descriptor
    LDX los_steps
    LDA screen_ptr   : STA bullet_descs,X
    LDA screen_ptr+1 : STA bullet_descs+1,X
    LDA los_dy       : STA bullet_descs+2,X
    LDA temp_y       : STA bullet_descs+3,X

    ; Draw the line
    LDA los_dy : STA col_counter
    JSR xor_hline
    RTS
