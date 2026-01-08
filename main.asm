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
.mask_ptr           SKIP 2    ; Pointer to current mask data
.char_tile_pos      SKIP 1    ; Character tile position (tile_y*16 + tile_x)
.char_pixel_offset  SKIP 1    ; Pixel offset within current tile
.temp_sprite_ptr    SKIP 2    ; Temp sprite pointer for striped blit
.temp_mask_ptr      SKIP 2    ; Temp mask pointer for striped blit

ORG &1900

CRTC_ADDR = &FE00
CRTC_DATA = &FE01

.start
    ; PROGRAM sets MODE 5, but reassert it here for safety.
    LDA #22
    JSR OSWRCH
    LDA #5
    JSR OSWRCH

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

    ; Render the current room tilemap.
    JSR render_tilemap

    ; Demo: draw Spycat Chell over the room.
    ; Place at tile (4,4): &5800 + 4*512 + 4*16 = &6040
    LDA #<(&6040)
    STA screen_ptr
    LDA #>(&6040)
    STA screen_ptr+1

    ; character_sprite_table index 0 = chell_frame1
    LDA #0
    JSR render_character_sprite

.hang
    JMP hang

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

; Get tile from tilemap at specified tile position.
; Input: Y = tile position (tile_y * 16 + tile_x)
; Output: A = tile number
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
