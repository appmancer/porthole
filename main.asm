INCLUDE "oscalls.asm"

; Zero page variables for speed
; Keep tilemap_ptr at &79/&7A (see render.asm)
ORG &70
.temp               SKIP 1    ; Temporary storage
.screen_ptr         SKIP 2    ; Current screen memory location
.sprite_ptr         SKIP 2    ; Pointer to current sprite data
.temp_y             SKIP 1    ; Temporary Y storage
.row_counter        SKIP 1    ; Row counter for loops
.col_counter        SKIP 1    ; Column counter for loops
.current_room       SKIP 1    ; Current room number (0=room1, 1=room2)
.tilemap_ptr        SKIP 2    ; Pointer to current room's tilemap data
.portalmap_ptr      SKIP 2    ; Pointer to current room's portalable tile layer
.mask_ptr           SKIP 2    ; Pointer to current mask data
.char_tile_pos      SKIP 1    ; Character cell position (cell_y*16 + cell_x)
.char_pixel_offset  SKIP 1    ; Subpixel offset (0..3)
.char_byte_offset   SKIP 1    ; Byte offset within cell (0 or 8)
.temp_sprite_ptr    SKIP 2    ; Temp sprite pointer for striped blit
.temp_mask_ptr      SKIP 2    ; Temp mask pointer for striped blit
.chell_bank         SKIP 1    ; ROMSEL value for Chell SWRAM bank
.saved_romsel       SKIP 1    ; Saved ROMSEL around OS calls
 .anim_frame              SKIP 1    ; Animation frame (0..3)
 .anim_dir                SKIP 1    ; Direction (0=left,1=right)
 .last_anim_dir           SKIP 1    ; Previous direction for redraw
 .move_cooldown           SKIP 1    ; Frames until next move
 .anim_cooldown           SKIP 1    ; Movement counter for anim
 
 .save_under_count         SKIP 1    ; Number of active save-under slots (0..4)


.save_under_screen_low    SKIP 4    ; Saved screen_ptr low per slot
.save_under_screen_high   SKIP 4    ; Saved screen_ptr high per slot

.cube_tile_pos       SKIP 1    ; Cube cell position (cell_y*16 + cell_x)
.cube_byte_offset    SKIP 1    ; Cube byte offset within cell (0/8)
.char_sprite_index  SKIP 1    ; Stable sprite index for test harness

ORG &1900

CRTC_ADDR = &FE00
CRTC_DATA = &FE01
ROMSEL    = &FE30          ; Master paged ROM/SWRAM bank select

CHELL_SWRAM_BANK_DEFAULT = 4

.start
    ; PROGRAM sets MODE 5, but reassert it here for safety.
    LDA #22
    JSR OSWRCH
    LDA #5
    JSR OSWRCH

    ; Disable the blinking text cursor (it writes into screen RAM).
    JSR disable_cursor

    ; Remap logical colours to physical palette:
    ; 0=black, 1=red, 2=cyan, 3=yellow
    JSR set_palette


    ; Apply the game's narrower visible width (32 chars) and re-centre.
    ; CRTC R1 (horizontal displayed) = 32
    LDA #1
    STA CRTC_ADDR
    LDA #32
    STA CRTC_DATA

    ; CRTC R2 (horizontal sync position) = 45
    LDA #2
    STA CRTC_ADDR
    LDA #45
    STA CRTC_DATA

    ; Minimal overlay test harness.

    ; Select room 0 so tilemap_ptr is valid (not used yet).
    LDA #0
    STA current_room
    JSR set_room_tilemap
    JSR set_room_portalmap

    ; Load Chell sprite+mask data into sideways RAM.
    ; (Do this before enabling shadow screen so &3000 is main RAM.)
    JSR load_chell_sprites

    ; Enable shadow screen (Master).
    ; We still use MODE 5 layout at &5800, but in shadow RAM.
    JSR enable_shadow_screen

    ; Place Chell at cell (4,4): cell_y*16 + cell_x = 4*16 + 4 = 68
    LDA #68
    STA char_tile_pos

    LDA #0
    STA char_pixel_offset
    STA char_byte_offset
    STA anim_frame
    STA save_under_count

    ; Default: face right.
    LDA #1
    STA anim_dir
    STA last_anim_dir

    ; Chell sprite data lives in sideways RAM bank 4 in B2 config.
    ; (B2 Master defaults configure banks 4-7 as SWRAM.)
    LDA #CHELL_SWRAM_BANK_DEFAULT
    STA chell_bank

    ; Render background once.
    JSR render_tilemap

    ; Build collision/material plane from the tilemap.
    JSR build_material_planes_from_tilemap

    ; Init animation + movement.
    LDA #0
    STA anim_frame
    STA char_pixel_offset
    STA move_cooldown
    STA anim_cooldown
 
    ; Draw the initial sprite once (allocates save-under slot).
    JSR update_screen_ptr_from_char
    JSR save_playfield_rect
    JSR draw_character_current
 
 .main_loop
    ; Pace the loop (reduces tearing/flicker).
    JSR wait_vsync
 
    ; Update char position/animation from held keys.
    ; Returns C=1 if we need to redraw.
    JSR poll_move_keys
    BCC main_loop
 
    ; Redraw only when something changed.
    JSR restore_playfield_rect
    JSR update_screen_ptr_from_char
    JSR save_playfield_rect
    JSR draw_character_current
 
    JMP main_loop


.run_frame_seq
    EQUB 0,1,0,2
 
; Draw current body + overlay at screen_ptr.
.draw_character_current
    ; Keep ROMSEL stable during blit (B2/MOS IRQs may page ROMs).
    SEI
    LDA ROMSEL
    STA saved_romsel

    ; Ensure Chell SWRAM bank is visible for reads.
    LDA chell_bank
    STA ROMSEL

    ; Index = run_frame*4 + subpixel_offset
    ; run_frame cycles 0,1,0,2 (i.e. 1,2,1,3)
    ; Facing selects between right-facing (0..11) and left-facing (12..23).
    LDX anim_frame
    LDA run_frame_seq,X
    ASL A
    ASL A
    STA char_sprite_index

    ; If facing left, add 12-entry base.
    LDA anim_dir
    BNE facing_right
    LDA char_sprite_index
    CLC
    ADC #12
    STA char_sprite_index
.facing_right

    LDA char_sprite_index
    CLC
    ADC char_pixel_offset
    STA char_sprite_index

    LDA char_sprite_index
    JSR render_character_sprite

    LDA char_sprite_index
    JSR render_overlay_sprite

    ; Restore previous ROM selection and re-enable IRQs.
    LDA saved_romsel
    STA ROMSEL
    CLI
    RTS
 
; Poll Z/X for left/right movement (single-pixel).
; Uses OSBYTE 129 (INKEY) "scan for a particular key":
;   On entry:  Y=&FF, X=&80..&FF (negative INKEY number)
;   On exit:   XY=&FFFF if pressed, else XY=&0000
; Horizontal position is represented as:
;   char_tile_pos      = 8px steps (cell_x)
;   char_byte_offset   = 0 or 8 (4px step within a cell, MODE5 column stride)
;   char_pixel_offset  = 0..3 (1px subpixel via pre-shifted sprites)
;
; Output: C=1 if sprite needs redraw.
.poll_move_keys
    LDA #0
    STA temp                  ; redraw flag
 
    ; Prefer left if both held.
    ; Also accept cursor keys for convenience.
    LDX #&E6            ; INKEY(-26) = Left
    JSR is_key_pressed
    BCS key_left
 
    LDX #&9E            ; INKEY(-98) = 'Z'
    JSR is_key_pressed
    BCS key_left
 
    LDX #&86            ; INKEY(-122) = Right
    JSR is_key_pressed
    BCS key_right
 
    LDX #&BD            ; INKEY(-67) = 'X'
    JSR is_key_pressed
    BCS key_right
 
.no_key_held
    ; No key held: stop animation + clear timers.
    LDA #0
    STA move_cooldown
    STA anim_cooldown
    STA anim_frame

    ; Keep facing, but sync last_anim_dir.
    LDA anim_dir
    STA last_anim_dir

    CLC
    RTS
 
; Input: X = negative INKEY number (as 8-bit value)
; Output: C=1 if pressed
.is_key_pressed
    LDY #&FF
    LDA #129
    JSR OSBYTE
    CPX #&FF
    BNE key_not_pressed
    SEC
    RTS
.key_not_pressed
    CLC
    RTS
 
 .key_left
     LDA #0
     STA anim_dir
     JMP key_held
 
 .key_right
     LDA #1
     STA anim_dir
 
 .key_held
     ; If direction changed, force a redraw so we flip immediately.
     LDA anim_dir
     CMP last_anim_dir
     BEQ move_tick
     STA last_anim_dir
     LDA #1
     STA temp
 
 .move_tick
     LDA move_cooldown
     BEQ do_move
     DEC move_cooldown
     JMP return_redraw
 .do_move
     ; Throttle to 1px every other frame.
     LDA #1
     STA move_cooldown
 
     LDA anim_dir
     BEQ do_move_left
     JSR step_right_pixel
     BCC return_redraw
     JMP did_move
 .do_move_left
     JSR step_left_pixel
     BCC return_redraw
 .did_move
     ; We moved: redraw, and advance animation every 2 pixels.
     LDA #1
     STA temp
 
     INC anim_cooldown
     LDA anim_cooldown
     CMP #2
     BNE return_redraw
     LDA #0
     STA anim_cooldown
     JSR step_anim

 
.return_redraw
    LDA temp
    BEQ no_redraw
    SEC
    RTS
.no_redraw
    CLC
    RTS
 
.step_anim
    INC anim_frame
    LDA anim_frame
    AND #3
    STA anim_frame
    RTS
 
; Step left by 1 pixel.
; Output: C=1 if moved.
.step_left_pixel
    ; If at absolute left bound, do nothing.
    LDA char_tile_pos
    AND #15
    BNE can_step_left
    LDA char_byte_offset
    ORA char_pixel_offset
    BEQ step_left_blocked

 .can_step_left
     ; Collision check at new left edge.
     JSR will_collide_left
     BCS step_left_blocked
 
.step_left_do_step
     LDA char_pixel_offset

    BNE step_left_dec_sub
 
    ; Wrap subpixel 0 -> 3 and move base left by 4px.
    LDA #3
    STA char_pixel_offset
 
    LDA char_byte_offset
    BNE step_left_byte_to0
 
    ; byte_offset 0: go to previous cell and use byte_offset 8.
    LDA #8
    STA char_byte_offset
    DEC char_tile_pos
    SEC
    RTS
 
.step_left_byte_to0
    LDA #0
    STA char_byte_offset
    SEC
    RTS
 
.step_left_dec_sub
    DEC char_pixel_offset
    SEC
    RTS
 
.step_left_blocked
    CLC
    RTS

; Compute current character X (left edge) in pixels.
; Output: A = x (0..127)
.calc_char_x
    LDA char_tile_pos
    AND #15
    ASL A
    ASL A
    ASL A
    STA temp

    ; char_byte_offset is 0 or 8 (i.e. 0 or 4 pixels)
    LDA char_byte_offset
    LSR A
    CLC
    ADC temp
    ADC char_pixel_offset
    RTS

; Compute current character Y (top edge) in pixels.
; Output: A = y (0..255)
.calc_char_y
    LDA char_tile_pos
    AND #&F0
    RTS

; Check if moving left 1px would collide.
; Output: C=1 if collision.
.will_collide_left
    JSR calc_char_x
    BEQ collide_left
    SEC
    SBC #1
    TAX

    JSR calc_char_y
    STA temp_y

    LDY temp_y
    JSR is_solid
    BCS collide_left

    LDY temp_y
    TYA
    CLC
    ADC #31
    TAY
    JSR is_solid
    BCS collide_left

    CLC
    RTS
.collide_left
    SEC
    RTS

; Check if moving right 1px would collide.
; Output: C=1 if collision.
.will_collide_right
    JSR calc_char_x
    CLC
    ADC #16              ; test new right edge (x+16)
    BCS collide_right    ; overflow => beyond 255 (treat as solid)
    CMP #128
    BCS collide_right
    TAX

    JSR calc_char_y
    STA temp_y

    LDY temp_y
    JSR is_solid
    BCS collide_right

    LDY temp_y
    TYA
    CLC
    ADC #31
    TAY
    JSR is_solid
    BCS collide_right

    CLC
    RTS
.collide_right
    SEC
    RTS
  
; Step right by 1 pixel.
; Output: C=1 if moved.
.step_right_pixel

    ; Clamp/limit to max X so sprite stays on-screen.
    ; Max position is tile_x=14, byte_offset=0, pixel_offset=0 (x=112 for 16px sprite).
    LDA char_tile_pos
    AND #15
    CMP #14
    BNE can_step_right
    LDA char_byte_offset
    ORA char_pixel_offset
    BEQ step_right_blocked
 
    ; If we ever got beyond max, clamp back.
    LDA #0
    STA char_byte_offset
    STA char_pixel_offset
    CLC
    RTS
 
.can_step_right
    ; Collision check at new right edge.
    JSR will_collide_right
    BCS step_right_blocked

.step_right_do_step
    LDA char_pixel_offset
    CMP #3
    BNE step_right_inc_sub
 
    ; Wrap subpixel 3 -> 0 and move base right by 4px.
    LDA #0
    STA char_pixel_offset
 
    LDA char_byte_offset
    BEQ step_right_byte_to8
 
    ; byte_offset 8: move to next cell and clear byte_offset.
    LDA #0
    STA char_byte_offset
    INC char_tile_pos
    SEC
    RTS
 
.step_right_byte_to8
    LDA #8
    STA char_byte_offset
    SEC
    RTS
 
.step_right_inc_sub
    INC char_pixel_offset
    SEC
    RTS
 
.step_right_blocked
    CLC
    RTS
 
; Disable the text cursor by redefining it to all zeros.
; This avoids the OS blinking cursor touching screen RAM.
.disable_cursor

    LDX #0
.cursor_loop
    LDA cursor_vdu,X
    JSR OSWRCH
    INX
    CPX #10
    BNE cursor_loop
    RTS

.cursor_vdu
    EQUB 23,1,0,0,0,0,0,0,0,0

; Set MODE 5 palette mapping.
; Uses VDU 19,logical,physical,0,0,0.
.set_palette
    LDX #0
.palette_loop
    LDA palette_vdu,X
    JSR OSWRCH
    INX
    CPX #24
    BNE palette_loop
    RTS

.palette_vdu
    ; logical 0 -> physical 0 (black)
    EQUB 19,0,0,0,0,0
    ; logical 1 -> physical 1 (red)
    EQUB 19,1,1,0,0,0
    ; logical 2 -> physical 6 (cyan)
    EQUB 19,2,6,0,0,0
    ; logical 3 -> physical 3 (yellow)
    EQUB 19,3,3,0,0,0

; Wait for a single keypress (B2-friendly, debounced).
; Uses OSBYTE 129 (INKEY-256): Y=ASCII, N set if no key.
; Returns: A = ASCII of key pressed.
.wait_key
    LDX #&00
    LDY #&00

    ; Wait for a key to be down.
.wait_key_down
    LDA #129
    JSR OSBYTE
    TYA
    BMI wait_key_down

    ; Latch key value.
    TYA
    PHA

    ; Wait for key to be released (no key down).
.wait_key_up
    LDA #129
    JSR OSBYTE
    TYA
    BPL wait_key_up

    PLA
    RTS

; Enable Master shadow screen.
; Master MOS supports selecting screen memory in shadow RAM.
; OSBYTE 114 is used by the MOS for shadow screen selection.
.enable_shadow_screen
    LDA #114
    LDX #1
    LDY #0
    JSR OSBYTE
    RTS

; Load Chell sprite+mask data into sideways RAM.
;
; We cannot safely `*LOAD` straight into `&8000` because filing system ROM code
; also lives in the `&8000..&BFFF` paged ROM window.
;
; Instead:
; 1) `*LOAD` `CHDATA` into a main-RAM buffer at `&3000`.
; 2) Select the SWRAM bank and copy 16KB from `&3000..&6FFF` into `&8000..&BFFF`.
.load_chell_sprites
    ; Keep the OS/language ROM visible across OSCLI.
    LDA ROMSEL
    STA saved_romsel

    ; Step 1: load into main RAM buffer.
    LDX #<cmd_load_chelldata_to_buf
    LDY #>cmd_load_chelldata_to_buf
    JSR OSCLI

    ; Step 2: select SWRAM bank and copy 16KB into it.
    ; Keep ROMSEL stable during the copy (IRQ handlers may touch it).
    SEI

    ; Real Master: bank number alone is writable.
    ; B2: some configs require bit 7 set for SWRAM writes.
    JSR select_chell_romsel
    BCC chell_bank_selected

    ; No usable bank mapping -> fail loudly.
    CLI
    LDA saved_romsel
    STA ROMSEL
    LDX #<msg_no_swr
    LDY #>msg_no_swr
    JSR print_string_xy
.no_swr_hang
    JMP no_swr_hang

.chell_bank_selected

    ; src := &3000
    LDA #&00
    STA temp_sprite_ptr
    LDA #&30
    STA temp_sprite_ptr+1

    ; dst := &8000 (in SWRAM bank)
    LDA #&00
    STA temp_mask_ptr
    LDA #&80
    STA temp_mask_ptr+1

    LDX #&40                  ; 64 pages = 16KB
.copy_chelldata_page
    LDY #0
.copy_chelldata_byte
    LDA (temp_sprite_ptr),Y
    STA (temp_mask_ptr),Y
    INY
    BNE copy_chelldata_byte

    INC temp_sprite_ptr+1
    INC temp_mask_ptr+1
    DEX
    BNE copy_chelldata_page

    ; Quick sanity check: confirm we really wrote SWRAM.
    JSR sanity_check_chell_swrambank
    BCC chell_sprites_ok

    ; Restore ROMSEL before calling OS.
    CLI
    LDA saved_romsel
    STA ROMSEL

    LDX #<msg_swr_copy_fail
    LDY #>msg_swr_copy_fail
    JSR print_string_xy

.swr_fail_hang
    JMP swr_fail_hang

.chell_sprites_ok
    ; Restore previous ROM selection and re-enable IRQs.
    LDA saved_romsel
    STA ROMSEL
    CLI
    RTS

.cmd_load_chelldata_to_buf
    EQUS "LOAD CHDATA 3000",13


; Select a ROMSEL value for Chell SWRAM writes.
; Tries bank 4, then bank 4|&80 (B2 quirk).
;
; Output:
; - `chell_bank` set
; - ROMSEL set to `chell_bank`
; Returns: C=0 if ok, C=1 if no mapping worked.
.select_chell_romsel
    LDA #CHELL_SWRAM_BANK_DEFAULT
    JSR romsel_writable
    BCC romsel_ok

    LDA #CHELL_SWRAM_BANK_DEFAULT
    ORA #&80
    JSR romsel_writable
    BCS romsel_fail

.romsel_ok
    STA chell_bank
    STA ROMSEL
    CLC
    RTS

.romsel_fail
    SEC
    RTS

; Test whether current A (ROMSEL value) is writable at &8000.
; Returns: C=0 writable, C=1 not writable. Preserves A.
.romsel_writable
    PHA
    STA ROMSEL

    LDA &8000
    STA temp

    LDA #&A5
    STA &8000
    CMP &8000
    BNE romsel_not_writable

    LDA #&5A
    STA &8000
    CMP &8000
    BNE romsel_not_writable

    ; Restore original byte.
    LDA temp
    STA &8000

    PLA
    CLC
    RTS

.romsel_not_writable
    ; Best-effort restore.
    LDA temp
    STA &8000
    PLA
    SEC
    RTS

; Sanity check for the Chell SWRAM bank in B2.
; Preconditions:
; - `chell_bank` has been selected into ROMSEL.
; - CHDATA buffer still present at `&3000`.
;
; Returns: C=0 if ok, C=1 if failed.
.sanity_check_chell_swrambank
    ; Confirm writes stick at &8000 (restore original byte afterwards).
    LDA &8000
    STA temp

    LDA #&A5
    STA &8000
    CMP &8000
    BNE sanity_fail

    LDA #&5A
    STA &8000
    CMP &8000
    BNE sanity_fail

    ; Restore original byte.
    LDA temp
    STA &8000

    ; Confirm the first 16 bytes match the load buffer.
    LDX #0
.sanity_cmp_loop
    LDA &3000,X
    CMP &8000,X
    BNE sanity_fail
    INX
    CPX #16
    BNE sanity_cmp_loop

    CLC
    RTS

.sanity_fail
    ; Best-effort restore of first byte.
    LDA temp
    STA &8000
    SEC
    RTS

; Print NUL-terminated string at XY using OSWRCH.
.print_string_xy
    STX temp_sprite_ptr
    STY temp_sprite_ptr+1

.print_loop
    LDY #0
    LDA (temp_sprite_ptr),Y
    BEQ print_done
    JSR OSWRCH

    INC temp_sprite_ptr
    BNE print_loop
    INC temp_sprite_ptr+1
    BNE print_loop

.print_done
    RTS

.msg_no_swr
    EQUS "NO SWRAM",13,0

.msg_swr_copy_fail
    EQUS "SWRAM COPY FAIL",13,0

; Wait for vertical sync (VBlank).
; Uses OSBYTE 19 (&13): "Wait for vertical sync".
.wait_vsync
    LDA #19
    LDX #0
    LDY #0
    JSR OSBYTE
    RTS

; Simple delay to make the demo visible.
.short_delay
    LDY #&30
.delay_outer
    LDX #&FF
.delay_inner
    DEX
    BNE delay_inner

    DEY
    BNE delay_outer
    RTS

; Update screen_ptr from char_tile_pos.
.update_screen_ptr_from_char
    ; tile_y = char_tile_pos >> 4
    LDA char_tile_pos
    LSR A
    LSR A
    LSR A
    LSR A
    STA temp_y

    ; Look up screen base for this tile row
    ASL A
    TAY
    LDA tile_row_screen_table,Y
    STA screen_ptr
    LDA tile_row_screen_table+1,Y
    STA screen_ptr+1

    ; tile_x = char_tile_pos & 15
    LDA char_tile_pos
    AND #15
    TAY

    ; Add tile_x * 16
    LDA times16_table,Y
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC add_byte_offset
    INC screen_ptr+1

.add_byte_offset
    LDA char_byte_offset
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC update_screen_done
    INC screen_ptr+1
.update_screen_done
    RTS

; Update screen_ptr from cube_tile_pos.
.update_screen_ptr_from_cube
    ; tile_y = cube_tile_pos >> 4
    LDA cube_tile_pos
    LSR A
    LSR A
    LSR A
    LSR A
    STA temp_y

    ; Look up screen base for this tile row
    ASL A
    TAY
    LDA tile_row_screen_table,Y
    STA screen_ptr
    LDA tile_row_screen_table+1,Y
    STA screen_ptr+1

    ; tile_x = cube_tile_pos & 15
    LDA cube_tile_pos
    AND #15
    TAY

    ; Add tile_x * 16
    LDA times16_table,Y
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC cube_add_byte_offset
    INC screen_ptr+1

.cube_add_byte_offset
    LDA cube_byte_offset
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC cube_screen_done
    INC screen_ptr+1
.cube_screen_done
    RTS

; Update char_tile_pos based on anim_dir.
; Bounces between tile_x 0..14 (sprite is 2 tiles wide).
.step_char_tile
    LDA char_tile_pos
    AND #15
    STA temp

    LDA anim_dir
    BEQ step_left

.step_right
    LDA temp
    CMP #14
    BNE step_right_inc
    LDA #0
    STA anim_dir
    RTS
.step_right_inc
    INC char_tile_pos
    RTS

.step_left
    LDA temp
    BEQ step_left_turn
    DEC char_tile_pos
    RTS
.step_left_turn
    LDA #1
    STA anim_dir
    RTS

; Set tilemap_ptr based on current_room variable.
; Uses room_pointers table to get correct room data.
.set_room_tilemap
    LDA current_room
    ASL A                   ; ×2 for 16-bit pointer
    TAX

    LDA room_pointers,X
    STA tilemap_ptr
    LDA room_pointers+1,X
    STA tilemap_ptr+1

    RTS

; Set portalmap_ptr based on current_room variable.
; Uses portal_room_pointers table to get correct room data.
.set_room_portalmap
    LDA current_room
    ASL A                   ; ×2 for 16-bit pointer
    TAX

    LDA portal_room_pointers,X
    STA portalmap_ptr
    LDA portal_room_pointers+1,X
    STA portalmap_ptr+1

    RTS

; Get cell value from cellmap at specified cell position.
; Input: Y = cell position (cell_y * 16 + cell_x)
; Output: A = cell value
.get_tilemap_tile
    LDA (tilemap_ptr),Y
    RTS

INCLUDE "sprites.asm"
INCLUDE "masks.asm"
INCLUDE "tilemap.asm"
INCLUDE "render.asm"
INCLUDE "lookup_tables.asm"

.end

SAVE "PORTHLE", start, end
PUTBASIC "program.bas", "PROGRAM"

; Chell sprite+mask data file for sideways RAM.
; This is loaded at runtime into a sideways RAM bank mapped at &8000..&BFFF.
ORG &8000
.chelldata_start
INCLUDE "sprites/generated_chell_sprites.asm"
INCLUDE "sprites/generated_chell_masks.asm"

; Pad to full 16KB SWRAM bank.
ORG &C000
.chelldata_end
SAVE "CHDATA", chelldata_start, chelldata_end
