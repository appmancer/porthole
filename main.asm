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
.chell_ptr      SKIP 2    ; Pointer to character sprite data --- IGNORE ---
.mask_ptr       SKIP 2    ; Pointer to current mask data

; total zero page bytes: 17

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

    JSR render_tilemap
    
    ; Wait for keypress
    JSR OSRDCH

    LDA #<(room2)
    STA tilemap_ptr
    LDA #>(room2)
    STA tilemap_ptr+1

    JSR render_tilemap

    ; Wait for keypress
    JSR OSRDCH

    LDA #<(&6320)
    STA chell_ptr
    LDA #>(&6320)
    STA chell_ptr+1
    ; animate the character
    .start_animation
    ; Plot 2x4 character sprite 'chell' so its bottom is at (8,13)
    ; Top-left should be at (8,10)


    LDA chell_ptr
    STA screen_ptr
    LDA chell_ptr+1
    STA screen_ptr+1

    LDA #<chell_standing
    STA sprite_ptr
    LDA #>chell_standing
    STA sprite_ptr+1

    LDA #0              ; Use character sprite index 0 (chell_standing)
    JSR render_character_sprite


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
