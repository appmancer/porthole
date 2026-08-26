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

    ; Clip killzone by cubes blocking line of fire.
    STX los_steps         ; save loop counter (los_steps restored by draw_one_bullet)
    TYA                   ; A = sentry obj index
    JSR clip_kz_by_cubes
    LDX los_steps         ; restore loop counter

    ; Check if killzone is still valid after clipping.
    LDA los_x0
    CMP los_x1
    BCS dsb_kz_next       ; fully blocked by cube(s)

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
IF ENABLE_AUDIO AND ENABLE_SFX
    LDA #SFX_SENTRY_FIRE
    STA SFX_PENDING
ENDIF
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


; Clip killzone x-range by cubes or closed barriers blocking line of fire.
;
; Input:  los_x0 = kz_x0, los_y0 = kz_y0, los_x1 = kz_x1, los_y1 = kz_y1
;         A = sentry obj index
; Output: los_x0 or los_x1 clipped to nearest blocking object.
;         If killzone is fully blocked, los_x0 >= los_x1 on return.
; Clobbers: A, X, temp, temp_y
.clip_kz_by_cubes
    TAX
    LDA obj_state,X
    AND #SENTRY_DIR_LEFT
    STA temp                  ; 0 = right-facing, 1 = left-facing

    LDX #0
.ckbc_loop
    LDA obj_type,X
    CMP #OBJ_TYPE_CUBE
    BEQ ckbc_cube
    CMP #OBJ_TYPE_BARRIER
    BEQ ckbc_barrier
    JMP ckbc_next

.ckbc_cube
    ; Cube: must be in current room and not carried.
    LDA obj_room,X
    CMP current_room
    BNE ckbc_next
    LDA obj_state,X
    AND #OBJ_STATE_CARRIED
    BNE ckbc_next
    ; Cube is 16 game px wide, 16 tall.
    LDA #16
    STA los_sx                ; obj_height
    LDA #16
    STA los_sy                ; obj_width
    JMP ckbc_overlap

.ckbc_barrier
    ; Barrier: must be in current room and closed (state bit 0 = 0).
    LDA obj_room,X
    CMP current_room
    BNE ckbc_next
    LDA obj_state,X
    AND #1
    BNE ckbc_next             ; bit 0 set = open, skip
    ; Barrier is 8 game px wide, height_tiles * 16 tall.
    LDA obj_state,X
    AND #&7E             ; bits 1-6, still shifted left by 1
    ASL A : ASL A : ASL A  ; × 8 → height_tiles × 16
    STA los_sx                ; obj_height
    LDA #8
    STA los_sy                ; obj_width
    ; fall through

.ckbc_overlap
    ; Vertical overlap: obj [obj_y*16, obj_y*16+height) vs kz [y0, y1)
    LDA obj_y,X
    ASL A : ASL A : ASL A : ASL A  ; * 16 = game pixel y
    CMP los_y1
    BCS ckbc_next             ; obj_y0 >= kz_y1: no overlap
    CLC : ADC los_sx          ; obj_y0 + height
    CMP los_y0
    BCC ckbc_next             ; obj_y1 <= kz_y0: no overlap
    BEQ ckbc_next

    ; Horizontal: obj [obj_x*8, obj_x*8+width) must overlap kz [x0, x1)
    LDA obj_x,X
    ASL A : ASL A : ASL A    ; * 8 = game pixel x
    STA temp_y                ; obj_x0
    CMP los_x1
    BCS ckbc_next             ; obj_x0 >= kz_x1: outside
    CLC : ADC los_sy          ; obj_x0 + width
    CMP los_x0
    BCC ckbc_next             ; obj_x1 <= kz_x0: outside
    BEQ ckbc_next

    ; Object overlaps killzone — clip based on sentry direction.
    LDA temp
    BNE ckbc_clip_left

    ; Right-facing: clip kz_x1 = min(kz_x1, obj_x0)
    LDA temp_y
    CMP los_x1
    BCS ckbc_next
    STA los_x1
    JMP ckbc_next

.ckbc_clip_left
    ; Left-facing: clip kz_x0 = max(kz_x0, obj_x1)
    LDA temp_y
    CLC : ADC los_sy
    CMP los_x0
    BCC ckbc_next
    BEQ ckbc_next
    STA los_x0

.ckbc_next
    INX
    CPX #OBJ_COUNT
    BEQ ckbc_done
    JMP ckbc_loop
.ckbc_done
    RTS
