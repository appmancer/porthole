INCLUDE "oscalls.asm"

; Zero page variables for speed
ORG &70
.temp           SKIP 1    ; Temporary storage
.screen_ptr     SKIP 2    ; The current screen memory location to draw to
.sprite_ptr     SKIP 2    ; Pointer to current sprite data
.temp_y         SKIP 1    ; Temporary Y storage
.tile           SKIP 1    ; the next tile to draw
.row_counter    SKIP 1    ; Row counter for loops
.col_counter    SKIP 1    ; Column counter for loops

.tile_index     SKIP 1    ; Temporary tile index for rendering
.current_room   SKIP 1    ; Current room number (0=room1, 1=room2)
.tilemap_ptr    SKIP 2    ; Pointer to current room's tilemap data
.mask_ptr       SKIP 2    ; Pointer to current mask data
.char_x         SKIP 1    ; Character X position in tile coordinates (0-15)
.char_y         SKIP 1    ; Character Y position in tile coordinates (0-15)

; total zero page bytes: 18

ORG &5000             

.start
    ; MODE 5 is already set by the BASIC loader program
    ; Wait a moment for everything to initialize
    LDX #255
.delay_loop
    DEX
    BNE delay_loop
    
    ; Initialize current_room to 1 (room2)
    LDA #0
    STA current_room
    
    ; Clear screen first
    LDA #12
    JSR OSWRCH
    
    ; FIRST resize the screen before trying text
    ; Set horizontal displayed characters (register 1) to 32
    LDA #1
    STA &FE00
    LDA #32
    STA &FE01
    
    ; Try centering with horizontal sync position
    ; Normal MODE 5 sync is at 49, with 40 chars displayed
    ; 40 was too far right, 50 was too far left, so try 45
    LDA #2
    STA &FE00
    LDA #45     ; Try 45 - halfway between 40 and 50
    STA &FE01
    
    ; Clear screen after resize
    LDA #12
    JSR OSWRCH

    LDA #<(room1)
    STA tilemap_ptr
    LDA #>(room1)
    STA tilemap_ptr+1

    ;JSR render_tilemap
    
    ; Wait for keypress
    ;JSR OSRDCH

    LDA #<(room2)
    STA tilemap_ptr
    LDA #>(room2)
    STA tilemap_ptr+1

    JSR render_tilemap

    ; Wait for keypress
    JSR OSRDCH

    ; Initialize character position (tile coordinates)
    LDA #4              ; Start at tile column 4 (middle-left of screen)
    STA char_x
    LDA #11             ; Start at tile row 10 (lower portion of screen)
    STA char_y

    ; Draw character sprite using position coordinates
    JSR calc_char_screen_position
    
    ; Render standing character sprite (frame 0)
    LDA #0
    JSR render_character_sprite

    ; Wait for keypress, then redraw background
    JSR OSRDCH
    
    ; Redraw background at current character position
    JSR calc_char_screen_position
    JSR redraw_background_area

    ; Wait for final keypress
    JSR OSRDCH

; Convert char_x, char_y tile coordinates to screen_ptr
; Input: char_x (0-15), char_y (0-15)
; Output: screen_ptr points to top-left of character position
.calc_char_screen_position
    ; screen_ptr = &5800 + (char_y * 256) + (char_x * 16)
    ; Each tile row = 256 bytes, each tile column = 16 bytes (2 bytes × 8 pixel rows)
    
    ; Start with base screen address
    LDA #<(&5800)
    STA screen_ptr
    LDA #>(&5800)
    STA screen_ptr+1
    
    ; Add Y offset: char_y * 256 (add to high byte)
    LDA screen_ptr+1
    CLC
    ADC char_y
    STA screen_ptr+1
    
    ; Add X offset: char_x * 16
    LDA char_x
    ASL A           ; * 2
    ASL A           ; * 4
    ASL A           ; * 8
    ASL A           ; * 16
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC char_pos_no_carry
    INC screen_ptr+1
.char_pos_no_carry
    
    RTS

; Redraw a 1×4 character area with background tiles
; Input: screen_ptr points to top-left of area to redraw
.redraw_background_area
    ; Save screen_ptr
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA
    
    ; Character sprite is 1 tile wide × 4 tiles tall
    ; Need to redraw 4 tiles vertically with correct tilemap data
    
    ; First tile (char_y + 0)
    LDA char_y
    JSR get_tilemap_tile
    JSR render_large_block
    INC screen_ptr+1
    
    ; Second tile (char_y + 1)
    LDA char_y
    CLC
    ADC #1
    JSR get_tilemap_tile
    JSR render_large_block
    INC screen_ptr+1
    
    ; Third tile (char_y + 2)
    LDA char_y
    CLC
    ADC #2
    JSR get_tilemap_tile
    JSR render_large_block
    INC screen_ptr+1
    
    ; Fourth tile (char_y + 3)
    LDA char_y
    CLC
    ADC #3
    JSR get_tilemap_tile
    JSR render_large_block
    
    ; Restore screen_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    
    RTS

; Get tile from tilemap at coordinates char_x, A=tilemap_y
; Input: A = tilemap_y coordinate, char_x = x coordinate  
; Output: A = tile number
.get_tilemap_tile
    ; Calculate tilemap index: tilemap_y * 8 + (char_x / 2)
    ASL A           ; * 2
    ASL A           ; * 4
    ASL A           ; * 8 (tilemap_y * 8)
    STA tile_index  ; Store base index
    
    ; Add char_x / 2
    LDA char_x
    LSR A           ; Divide by 2
    CLC
    ADC tile_index
    TAY             ; Y now contains the tilemap byte index
    
    ; Read the tilemap byte
    LDA (tilemap_ptr), Y
    
    ; Extract the correct nibble based on char_x odd/even
    ; Note: In packed nibbles, left tile = high nibble, right tile = low nibble
    LDX char_x
    TXA
    AND #1          ; Check if char_x is odd
    BNE get_right_nibble
    
    ; char_x is even - use left nibble (high 4 bits)
    LDA (tilemap_ptr), Y
    LSR A
    LSR A
    LSR A
    LSR A
    RTS
    
.get_right_nibble
    ; char_x is odd - use right nibble (low 4 bits)
    LDA (tilemap_ptr), Y
    AND #&0F
    RTS

.end_main

INCLUDE "sprites.asm"
INCLUDE "masks.asm"
INCLUDE "tilemap.asm"
INCLUDE "render.asm"

.end

SAVE "BF6502", start, end
PUTBASIC "program.bas", "PROGRAM"
PUTBASIC "boot.txt", "!BOOT"
