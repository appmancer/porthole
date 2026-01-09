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
.anim_frame         SKIP 1    ; Animation frame (0/1)
.anim_dir           SKIP 1    ; Direction (0=left,1=right)

ORG &1900

CRTC_ADDR = &FE00
CRTC_DATA = &FE01

.start
    ; PROGRAM sets MODE 5, but reassert it here for safety.
    LDA #22
    JSR OSWRCH
    LDA #5
    JSR OSWRCH

    ; Disable the blinking text cursor (it writes into screen RAM).
    JSR disable_cursor

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

    ; Select room 0 and point tilemap_ptr at it.
    LDA #0
    STA current_room
    JSR set_room_tilemap
    JSR set_room_portalmap

    ; Render the current room tilemap.
    JSR render_tilemap

    ; Build material planes from the tilemap.
    JSR build_material_planes_from_tilemap

    ; Demo: auto-walk Chell left/right across the room.
    ; Start at cell (4,4): cell_y*16 + cell_x = 4*16 + 4 = 68
    LDA #68
    STA char_tile_pos

    LDA #0
    STA char_pixel_offset
    STA char_byte_offset
    STA anim_frame

    LDA #1
    STA anim_dir

    ; Draw the first frame before entering the loop.
    JSR update_screen_ptr_from_char
    JSR save_playfield_rect
    LDA anim_frame
    ASL A
    ASL A
    CLC
    ADC char_pixel_offset
    JSR render_character_sprite

.demo_loop
    JSR short_delay

    ; Erase current frame by restoring the saved background.
    JSR restore_playfield_rect

    ; Next animation frame
    LDA anim_frame
    EOR #1
    STA anim_frame

    ; Advance subpixel offset (0..3). When it wraps, step 4 pixels.
    INC char_pixel_offset
    LDA char_pixel_offset
    CMP #4
    BNE draw_next

    LDA #0
    STA char_pixel_offset

    ; Toggle 4-pixel byte offset within the tile (0/8). When it wraps, step tile.
    LDA char_byte_offset
    EOR #8
    STA char_byte_offset
    BNE draw_next

    JSR step_char_tile

.draw_next
    JSR update_screen_ptr_from_char
    JSR save_playfield_rect

    ; Sprite index = pose*4 + subpixel_offset
    LDA anim_frame
    ASL A
    ASL A
    CLC
    ADC char_pixel_offset
    JSR render_character_sprite

    JMP demo_loop

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

; Simple delay to make the demo visible.
.short_delay
    LDY #&80
.delay_outer
    ; Two inner passes to slow it down.
    LDX #&FF
.delay_inner1
    DEX
    BNE delay_inner1

    LDX #&FF
.delay_inner2
    DEX
    BNE delay_inner2

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
