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
.char_tile_pos  SKIP 1    ; Single tile position (char_y * 16 + char_x), shadows char_x/char_y

; total zero page bytes: 21

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
    STA char_y
    ; each tile is 16x16 pixels, so char_x 2 = pixel x 32
    
    ; Initialize char_tile_pos as shadow of char_x/char_y: 4*16+4 = 68
    LDA #68             ; char_y * 16 + char_x = 4 * 16 + 4 = 68
    STA char_tile_pos

    LDA #<(&6040)  ; Start in the correct tile [4,4]
    STA screen_ptr
    LDA #>(&6040)
    STA screen_ptr+1

    ; Demo pixel-aligned sprite cycling
    JSR pixel_aligned_demo

    ; Wait for final keypress
    JSR OSRDCH

; Redraw a 1×4 character area with background tiles
; Input: screen_ptr points to top-left of area to redraw
.redraw_background_area
    ; Save screen_ptr
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA
    
    ; Character sprite is 1 tile wide × 4 character rows tall
    ; Derive tile coordinates from actual input screen_ptr position
    
    ; Calculate tile_y: (screen_ptr - &5800) / 512
    ; First get offset from screen base
    LDA screen_ptr
    SEC
    SBC #<(&5800)
    STA temp           ; Low byte of offset
    LDA screen_ptr+1
    SBC #>(&5800)
    STA temp_y         ; High byte of offset
    
    ; Now divide by 512: high byte of offset = tile_y (since 512 = &200)
    LDA temp_y
    LSR A              ; Divide high byte by 2 to get tile_y
    STA temp_y         ; temp_y now contains tile_y
    
    ; Calculate tile_x: (offset within tile row) / 16
    ; Get the low 8 bits + LSB of high byte for position within 512-byte row
    LDA temp_y
    AND #1             ; Get LSB of original high byte
    BEQ calc_tile_x    ; If 0, use temp directly
    
    ; Add 256 to temp for the extra bit
    LDA temp
    CLC
    ADC #0             ; temp already has the right value
    STA temp
    LDA #1
    STA col_counter    ; Use col_counter as flag for +256
    JMP do_tile_x_calc
    
.calc_tile_x
    LDA #0
    STA col_counter    ; Clear the +256 flag

.do_tile_x_calc
    ; Now divide temp by 16 to get tile_x
    LDA temp
    LSR A              ; Divide by 2
    LSR A              ; Divide by 4
    LSR A              ; Divide by 8
    LSR A              ; Divide by 16
    
    ; Add 16 if we had the +256 flag
    LDX col_counter
    BEQ store_tile_x
    CLC
    ADC #16
    
.store_tile_x
    STA col_counter    ; Store tile_x in col_counter
    
    ; Now recalculate tile-aligned screen_ptr
    ; Start with screen base
    LDA #<(&5800)
    STA screen_ptr
    LDA #>(&5800)
    STA screen_ptr+1
    
    ; Add tile_y * 512
    LDX temp_y         ; tile_y
    BEQ add_tile_x_offset
.tile_y_loop
    INC screen_ptr+1   ; Add 256
    INC screen_ptr+1   ; Add 256 = 512 total
    DEX
    BNE tile_y_loop
    
.add_tile_x_offset
    ; Add tile_x * 16
    LDA col_counter    ; tile_x
    ASL A              ; * 2
    ASL A              ; * 4
    ASL A              ; * 8
    ASL A              ; * 16
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC first_tile
    INC screen_ptr+1
    
.first_tile
    ; First tile - calculate linear position: tile_y * 16 + tile_x
    LDA temp_y         ; tile_y
    ASL A              ; * 2
    ASL A              ; * 4
    ASL A              ; * 8  
    ASL A              ; * 16
    CLC
    ADC col_counter    ; + tile_x
    TAY                ; Y = tile position for tilemap lookup
    JSR get_tilemap_tile
    JSR render_large_block
    
    ; Move down to next tile (512 bytes = 2 character rows)
    INC screen_ptr+1
    INC screen_ptr+1
    
    ; Second tile - next tile row down (tile_y + 1)
    LDA temp_y         ; tile_y
    CLC
    ADC #1             ; tile_y + 1
    ASL A              ; * 2
    ASL A              ; * 4
    ASL A              ; * 8
    ASL A              ; * 16
    CLC
    ADC col_counter    ; + tile_x
    TAY                ; Y = tile position for tilemap lookup
    JSR get_tilemap_tile
    JSR render_large_block
    
    ; Check if current screen_ptr is 512-byte aligned
    ; First check: is low byte zero?
    LDA screen_ptr
    BNE need_third_tile     ; If low byte != 0, definitely need 3rd tile

    ; Low byte is zero, now check if high byte is even (LSB = 0)
    LDA screen_ptr+1
    AND #&01                ; Check LSB of high byte
    BEQ restore_screen_ptr  ; If even (512-byte aligned), only need 2 tiles

.need_third_tile
    ; Need third tile
    INC screen_ptr+1    ; Move down another 512 bytes
    INC screen_ptr+1
    
    ; Third tile - two tile rows down (tile_y + 2)
    LDA temp_y         ; tile_y
    CLC
    ADC #2             ; tile_y + 2
    ASL A              ; * 2
    ASL A              ; * 4
    ASL A              ; * 8
    ASL A              ; * 16
    CLC
    ADC col_counter    ; + tile_x
    TAY                ; Y = tile position for tilemap lookup
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

; Get tile from tilemap at specified tile position
; Input: Y = tile position (tilemap_y * 16 + tilemap_x)
; Output: A = tile number
.get_tilemap_tile
    ; Read tile directly using the provided tile position
    LDA (tilemap_ptr), Y
    RTS

.end_main

; Demo function to cycle through 8 frames of smooth movement
; Frames 0-3: pixel shifts 0-3 at current position
; Frames 4-7: move to next char position, pixel shifts 0-3
.pixel_aligned_demo
    ; Frame 0: sprite 0 at current position
    JSR render_character_sprite
    JSR short_delay
    JSR redraw_background_area
    
    ; Frame 1: sprite 1 (1 pixel shift) at current position
    LDA #1
    JSR render_character_sprite
    JSR short_delay
    JSR redraw_background_area
    
    ; Frame 2: sprite 2 (2 pixel shift) at current position
    LDA #2
    JSR render_character_sprite
    JSR short_delay
    JSR redraw_background_area
    
    ; Frame 3: sprite 3 (3 pixel shift) at current position
    LDA #3
    JSR render_character_sprite
    JSR short_delay
    
    JSR OSRDCH
    JSR redraw_background_area
    
    ; Frame 4: Move to next character position, sprite 0
    ; Move by 8 bytes (4 pixels) for half-character precision
    ; This gives us 1-pixel precision over 8 frames total
.end_of_cycle
    LDA screen_ptr
    CLC
    ADC #8              ; Move right by half character cell (8 bytes = 4 pixels)
    STA screen_ptr
    BCC pixel_demo_no_carry
    INC screen_ptr+1
.pixel_demo_no_carry
    LDA #0
    JSR render_character_sprite
    JSR short_delay
    JSR redraw_background_area
    
    ; Frame 5: sprite 1 (1 pixel shift) at new position
    LDA #1
    JSR render_character_sprite
    JSR short_delay
    JSR redraw_background_area
    
    ; Frame 6: sprite 2 (2 pixel shift) at new position
    LDA #2
    JSR render_character_sprite
    JSR short_delay
    JSR redraw_background_area
    
    ; Frame 7: sprite 3 (3 pixel shift) at new position
    LDA #3
    JSR render_character_sprite
    JSR short_delay
    ;JSR redraw_background_area
    
    ; Movement cycle complete - update tile position for next cycle
    INC char_tile_pos       ; Move to next tile position
    
    JMP end_of_cycle
    RTS

; Short delay routine
.short_delay
    LDY #&FF        ; Delay counter
.delay_loop_inner
    LDX #&FF        ; Inner loop
.delay_loop_very_inner
    DEX
    BNE delay_loop_very_inner
    DEY
    BNE delay_loop_inner
    RTS

INCLUDE "sprites.asm"
INCLUDE "masks.asm"
INCLUDE "tilemap.asm"
INCLUDE "render.asm"
INCLUDE "lookup_tables.asm"

.end

SAVE "BF6502", start, end
PUTBASIC "program.bas", "PROGRAM"
PUTBASIC "boot.txt", "!BOOT"
