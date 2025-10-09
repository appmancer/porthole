INCLUDE "oscalls.asm"

; Zero page variables for speed
ORG &70
.temp               SKIP 1    ; Temporary storage
.screen_ptr         SKIP 2    ; The current screen memory location to draw to
.sprite_ptr         SKIP 2    ; Pointer to current sprite data
.temp_y             SKIP 1    ; Temporary Y storage
.row_counter        SKIP 1    ; Row counter for loops
.col_counter        SKIP 1    ; Column counter for loops
.current_room       SKIP 1    ; Current room number (0=room1, 1=room2)
.tilemap_ptr        SKIP 2    ; Pointer to current room's tilemap data
.mask_ptr           SKIP 2    ; Pointer to current mask data
.char_tile_pos      SKIP 1    ; Single tile position, replaces char_x/char_y
.char_pixel_offset  SKIP 1    ; Pixel offset within current tile (0-7)

; total zero page bytes: 15

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
    ; Start at tile position 68 (row 4, column 4: 4*16+4 = 68)
    LDA #68             
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
