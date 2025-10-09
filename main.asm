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
.char_pixel_offset SKIP 1 ; Pixel offset within current tile (0-7)

; total zero page bytes: 22

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
    
    ; Initialize pixel offset within tile
    LDA #0
    STA char_pixel_offset

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
    CLI
    ; Save screen_ptr
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA
    
    ; Character sprite is 1 tile wide × 4 character rows tall
    ; Use char_tile_pos directly for both tilemap lookup and screen position
    
    ; Calculate tile_y and tile_x from char_tile_pos for screen positioning only
    LDA char_tile_pos
    LSR A              ; Divide by 2
    LSR A              ; Divide by 4  
    LSR A              ; Divide by 8
    LSR A              ; Divide by 16 = tile_y
    STA temp_y         ; Store tile_y
    
    ; Calculate tile_x from char_tile_pos  
    LDA char_tile_pos
    AND #15            ; Keep only lower 4 bits = tile_x
    STA col_counter    ; Store tile_x
    
    ; Look up screen position from tile row table
    LDA temp_y         ; tile_y
    ASL A              ; * 2 for 16-bit table index
    TAY
    LDA tile_row_screen_table,Y
    STA screen_ptr
    LDA tile_row_screen_table+1,Y
    STA screen_ptr+1
    
    ; Add tile_x * 16 using lookup table
    LDY col_counter    ; tile_x
    LDA times16_table,Y
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC first_tile
    INC screen_ptr+1
    
.first_tile
    ; First tile - use char_tile_pos directly (already tile_y * 16 + tile_x)
    LDY char_tile_pos
    JSR get_tilemap_tile
    JSR render_large_block
    
    ; Move down to next tile (512 bytes = 2 character rows)
    INC screen_ptr+1
    INC screen_ptr+1
    
    ; Second tile - next tile row down (char_tile_pos + 16)
    LDY char_tile_pos
    TYA
    CLC
    ADC #16            ; Add 16 for next tile row
    TAY
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
    
    ; Third tile - two tile rows down (char_tile_pos + 32)
    LDY char_tile_pos
    TYA
    CLC
    ADC #32            ; Add 32 for two tile rows down
    TAY
    JSR get_tilemap_tile
    JSR render_large_block
    
.restore_screen_ptr
    
    ; Restore screen_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    
    SEI
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
; 8-frame pixel-aligned movement cycle
; Frames 0-3: pixel shifts 0-3 at current position
; Frames 4-7: move to next char position, pixel shifts 0-3
.pixel_aligned_demo

.animation_cycle
    ; Frame 0: sprite 0 at current position
    LDA #0
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
    
    ; Frame 4: Clean up old position, then move to next character position, sprite 0
    ; Move by 8 bytes (4 pixels) for half-character precision
    ; This gives us 1-pixel precision over 8 frames total
    ; First clean up the old position before moving
    JSR redraw_background_area
    
    ; Now move to next position (4 pixels = 8 bytes)
    LDA screen_ptr
    CLC
    ADC #8              ; Move right by half character cell (8 bytes = 4 pixels)
    STA screen_ptr
    BCC pixel_demo_no_carry
    INC screen_ptr+1
.pixel_demo_no_carry
    
    ; Count 4-frame cycles - need 2 cycles (8 frames) to complete one tile
    INC char_pixel_offset
    LDA char_pixel_offset
    CMP #2              ; Have we completed 2 cycles? (8 frames = 1 tile)
    BNE continue_animation
    
    ; Completed full tile (8 pixels), reset counter and move to next tile
    LDA #0
    STA char_pixel_offset
    INC char_tile_pos
    
.continue_animation
    JMP animation_cycle     ; Loop all 8 frames
    RTS

; Short delay routine
.short_delay
    LDY #&50     ; Delay counter
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
