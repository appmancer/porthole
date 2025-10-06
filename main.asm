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

ORG &1900             

.start
    ; MODE 5 is already set by the BASIC loader program
    ; Wait a moment for everything to initialize
    LDX #255
.delay_loop
    DEX
    BNE delay_loop
    
    ; Initialize current_room to 1 (room2)
    LDA #1
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

    ; Set tilemap_ptr based on current_room
    LDA #1
    JSR set_room_tilemap

    ; Render the current room  
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
    
    ; Character sprite is 1 tile wide × 4 character rows tall
    ; If char_y is even (aligned to tile top): spans 2 tiles
    ; If char_y is odd (not aligned): spans 3 tiles
    
    ; Calculate the first tile row that contains char_y
    LDA char_y
    LSR A               ; Divide by 2: char_y / 2 = first_tile_y
    STA temp_y          ; Store the first tile row
    
    ; Calculate screen position for start of this tile row
    ; Reset screen_ptr to tile-aligned position
    LDA #<(&5800)
    STA screen_ptr
    LDA #>(&5800)
    STA screen_ptr+1
    
    ; Add tile row offset: tile_row * 512 bytes (each tile = 2 char rows)
    LDA temp_y
    BEQ add_x_offset    ; Skip if tile row 0
.tile_offset_loop
    INC screen_ptr+1    ; Add 256 bytes  
    INC screen_ptr+1    ; Add 256 bytes = 512 total per tile row
    DEC temp_y
    BNE tile_offset_loop
    
.add_x_offset
    ; Add X offset for character column  
    LDA char_x
    ASL A               ; * 2
    ASL A               ; * 4
    ASL A               ; * 8
    ASL A               ; * 16
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC first_tile
    INC screen_ptr+1
    
.first_tile
    ; First tile - get tile from tilemap
    LDA char_y
    LSR A               ; Convert to tile coordinate
    JSR get_tilemap_tile
    JSR render_large_block
    
    ; Move down to next tile (512 bytes = 2 character rows)
    INC screen_ptr+1
    INC screen_ptr+1
    
    ; Second tile - next tile row down
    LDA char_y
    LSR A               ; Convert to tile coordinate
    CLC
    ADC #1              ; Next tile row: tile_y + 1
    JSR get_tilemap_tile
    JSR render_large_block
    
    ; Check if char_y is aligned to tile top (even)
    ; If char_y is odd, we need a third tile
    LDA char_y
    AND #&01            ; Check if odd
    BEQ restore_screen_ptr  ; If even (aligned), we're done
    
    ; Need third tile (char_y was odd)
    INC screen_ptr+1    ; Move down another 512 bytes
    INC screen_ptr+1
    
    ; Third tile
    LDA char_y
    LSR A               ; Convert to tile coordinate
    CLC
    ADC #2              ; Third tile row: tile_y + 2
    JSR get_tilemap_tile
    JSR render_large_block
    
.restore_screen_ptr
    
    ; Restore screen_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    
    RTS

; Set tilemap_ptr based on current_room variable
; Uses room_pointers table to get correct room data
.set_room_tilemap
    ; Calculate room_pointers index: current_room * 2 (16-bit pointers)
    LDA current_room
    ASL A                   ; × 2 for 16-bit pointer
    TAX
    
    ; Load room pointer from room_pointers table
    LDA room_pointers,X
    STA tilemap_ptr
    LDA room_pointers+1,X
    STA tilemap_ptr+1
    
    RTS

; Get tile from tilemap at coordinates char_x, A=tilemap_y
; Input: A = tilemap_y coordinate, char_x = x coordinate  
; Output: A = tile number
.get_tilemap_tile
    ; Calculate tilemap index: tilemap_y * 16 + char_x (8-bit format)
    ASL A           ; × 2
    ASL A           ; × 4
    ASL A           ; × 8
    ASL A           ; × 16 (tilemap_y * 16)
    STA tile_index  ; Store base index
    
    ; Add char_x (no division needed for 8-bit format)
    LDA char_x
    CLC
    ADC tile_index
    TAY             ; Y now contains the tilemap byte index
    
    ; Read tile directly (no nibble extraction needed!)
    LDA (tilemap_ptr), Y
    RTS

.end_main

INCLUDE "sprites.asm"
INCLUDE "masks.asm"
INCLUDE "tilemap.asm"
INCLUDE "render.asm"
INCLUDE "lookup_tables.asm"

.end

SAVE "BF6502", start, end
PUTBASIC "program.bas", "PROGRAM"
PUTBASIC "boot.txt", "!BOOT"
