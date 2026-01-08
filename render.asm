; render.asm
; Routines to render a tilemap and sprites in MODE 5

; Screen memory notes:
; - Engine treats the playfield as 16x16 tiles.
; - Screen base is &5800.
; - Each tile row is treated as 512 bytes apart (see tile_row_screen_table).
; - We do not use scrolling; we flick between screens.
; - We may use screen RAM *below the playfield* as scratch (not returned to BASIC).

.render_tilemap
    ; Set up initial pointers
    LDA #<(&5800)           ; Screen starts at &5800 in MODE 5
    STA screen_ptr                 ; screen_ptr_lo 
    LDA #>(&5800)
    STA screen_ptr+1                 ; screen_ptr_hi
    
    LDA #<(sprite_data)     ; Set up sprite pointer 
    STA sprite_ptr                 ; sprite_ptr_lo
    LDA #>(sprite_data) 
    STA sprite_ptr                 ; sprite_ptr_hi
    
    ; Initialize row counter  
    LDA #0
    STA row_counter                 ; row_counter

.tilemap_row_loop
    ; Initialize column counter
    LDA #0
    STA col_counter                 ; col_counter
    
.tilemap_col_loop
    ; Calculate tilemap index: row_counter * 16 + col_counter  
    LDY row_counter                 ; row_counter as index
    LDA times16_table,Y     ; Get row_counter * 16 (2 cycles vs 8 for 4 ASLs)
    CLC
    ADC col_counter         ; + col_counter
    TAY
    
    ; Get tile value directly (8-bit format - no nibble extraction!)
    LDA (tilemap_ptr), Y            ; tilemap_ptr is in &79/&7A
    JSR render_large_block
    
    ; Move screen pointer right by 16 bytes
    LDA screen_ptr
    CLC
    ADC #16
    STA screen_ptr
    BCC tilemap_col_loop_no_carry
    INC screen_ptr+1

.tilemap_col_loop_no_carry    
    ; Next column
    INC col_counter
    LDA col_counter
    CMP #16                 ; 16 columns total
    BNE tilemap_col_loop
    
.tilemap_end_of_row
    ; Move to next screen row (add 256 bytes)
    INC screen_ptr+1

    ; Next row
    INC row_counter
    LDA row_counter
    CMP #16                 ; 16 rows total
    BEQ tilemap_done
    JMP tilemap_row_loop
    
.tilemap_done
    RTS

.render_large_block
    ; Store tile type
    STA temp
    ; Preserve screen pointer
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA
    
    ; Get sprite data pointer for this tile
    LDA temp
    ASL A                   ; × 2 for 16-bit pointer
    TAX
    LDA sprite_table,X
    STA sprite_ptr                 ; sprite_ptr_lo
    LDA sprite_table+1,X
    STA sprite_ptr+1                 ; sprite_ptr_hi

    ; Plot first half (top 8 rows)
    JSR plot_wide_sprite
    
    ; Move screen pointer down 8 rows (256 bytes)
    LDA screen_ptr+1
    CLC
    ADC #1
    STA screen_ptr+1
    
    ; Move sprite pointer to bottom half (+16 bytes)
    LDA sprite_ptr
    CLC
    ADC #16
    STA sprite_ptr
    BCC next_half
    INC sprite_ptr+1
    
.next_half
    ; Plot second half (bottom 8 rows)
    JSR plot_wide_sprite
    
    ; Restore screen pointer
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    RTS

; Masked version of render_large_block - for sprites with transparent black pixels
.render_masked_large_block
    ; Store tile type
    STA temp

    ; Preserve screen pointer
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA
    
    ; Get sprite data pointer for this tile
    LDA temp                 ; temp
    ASL A                   ; × 2 for 16-bit pointer
    TAX
    LDA sprite_table,X
    STA sprite_ptr                 ; sprite_ptr_lo
    LDA sprite_table+1,X
    STA sprite_ptr+1                 ; sprite_ptr_hi

    ; Plot first half (top 8 rows) with masking
    JSR plot_masked_wide_sprite
    
    ; Move screen pointer down 8 rows (256 bytes)
    LDA screen_ptr+1
    CLC
    ADC #1
    STA screen_ptr+1
    
    ; Move sprite pointer to bottom half (+16 bytes)
    LDA sprite_ptr
    CLC
    ADC #16
    STA sprite_ptr
    BCC next_half_masked
    INC sprite_ptr+1
    
.next_half_masked
    ; Plot second half (bottom 8 rows) with masking  
    JSR plot_masked_wide_sprite
    
    ; Restore screen pointer
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    RTS

; plots a 16-byte, double character wide sprite
.plot_wide_sprite
    ; Plot 16 bytes of sprite data consecutively
    LDY #0
.sprite_wide_row_loop
    LDA (sprite_ptr),Y             ; Get sprite row data from sprite_ptr
    STA (screen_ptr),Y             ; Plot to screen at screen_ptr
    INY
    CPY #16                 ; 16 bytes per row
    BNE sprite_wide_row_loop
    RTS

; plots a 16-byte, double character wide sprite with masking (black pixels transparent)
; MODE 5 uses interleaved bits: pixel 0=bits 0+4, pixel 1=bits 1+5, pixel 2=bits 2+6, pixel 3=bits 3+7
.plot_masked_wide_sprite
    LDY #0
.masked_sprite_byte_loop
    LDA (sprite_ptr),Y             ; Load sprite byte from sprite_ptr
    BEQ skip_sprite_byte    ; If entire byte is 0 (all black), skip it
    
    STA temp                 ; Store sprite byte in &70 (temp)
    LDA (screen_ptr),Y             ; Load current screen byte from screen_ptr
    STA temp_y                 ; Store screen byte in &75 (temp_y)
    
    ; Process pixel 0 (bits 0 and 4) - MSB bit 0 = bit 7, bit 4 = bit 3
    LDA temp
    AND #&88                ; Mask bits 7 and 3 (0 and 4 in MSB numbering)
    BEQ keep_screen_pixel0  ; If sprite pixel is black, keep screen pixel
    LDA temp_y
    AND #&77                ; Clear screen bits 7 and 3
    ORA temp                ; OR in sprite bits 7 and 3
    STA temp_y
.keep_screen_pixel0
    
    ; Process pixel 1 (bits 1 and 5) - MSB bit 1 = bit 6, bit 5 = bit 2
    LDA temp
    AND #&44                ; Mask bits 6 and 2 (1 and 5 in MSB numbering)
    BEQ keep_screen_pixel1  ; If sprite pixel is black, keep screen pixel
    LDA temp_y
    AND #&BB                ; Clear screen bits 6 and 2
    ORA temp                ; OR in sprite bits 6 and 2
    STA temp_y
.keep_screen_pixel1
    
    ; Process pixel 2 (bits 2 and 6) - MSB bit 2 = bit 5, bit 6 = bit 1
    LDA temp
    AND #&22                ; Mask bits 5 and 1 (2 and 6 in MSB numbering)
    BEQ keep_screen_pixel2  ; If sprite pixel is black, keep screen pixel
    LDA temp_y
    AND #&DD                ; Clear screen bits 5 and 1
    ORA temp                ; OR in sprite bits 5 and 1
    STA temp_y
.keep_screen_pixel2
    
    ; Process pixel 3 (bits 3 and 7) - MSB bit 3 = bit 4, bit 7 = bit 0
    LDA temp
    AND #&11                ; Mask bits 4 and 0 (3 and 7 in MSB numbering)
    BEQ keep_screen_pixel3  ; If sprite pixel is black, keep screen pixel
    LDA temp_y
    AND #&EE                ; Clear screen bits 4 and 0
    ORA temp                ; OR in sprite bits 4 and 0
    STA temp_y
.keep_screen_pixel3

    LDA temp_y
    STA (screen_ptr),Y             ; Write modified byte back to screen

.skip_sprite_byte
    INY
    CPY #16                 ; 16 bytes total
    BNE masked_sprite_byte_loop
    
    RTS; Render character sprite with mask - uses character_sprite_table and character_mask_table
.render_character_sprite
    ; preserve A
    STA temp
    ; preserve screen_ptr
    LDA screen_ptr
    PHA
    LDA screen_ptr +1
    PHA
    ; restore A
    LDA temp
    ; Input: A = character sprite index (0-based index for character_sprite_table)
    ASL A
    TAX
    LDA character_sprite_table,X
    STA sprite_ptr
    LDA character_sprite_table+1,X
    STA sprite_ptr+1
    
    ; Set up mask pointer from character_mask_table
    LDA character_mask_table,X
    STA mask_ptr
    LDA character_mask_table+1,X
    STA mask_ptr+1

    ; Plot full character sprite (32 scanlines) using Spycat-style masked blit
    JSR plot_sprite12x32_masked_striped

    ; restore screen_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    
    RTS

; Render character sprite with mask - uses character_sprite_table and character_mask_table

; plots a 16-byte sprite with separate mask data (00=transparent, 11=opaque per pixel)
; Requires: sprite_ptr = sprite data, mask_ptr = mask data, screen_ptr = screen location
.plot_sprite_with_mask
    LDY #0
.mask_sprite_byte_loop
    LDA (mask_ptr),Y        ; Load mask byte
    AND (sprite_ptr),Y      ; Keep sprite pixels where mask bits are set
    STA temp                ; Store masked sprite data
    
    LDA (mask_ptr),Y        ; Reload mask byte
    EOR #&FF                ; Invert mask (00->FF, 11->EE, etc)
    AND (screen_ptr),Y      ; Keep screen pixels where inverted mask bits are set
    ORA temp                ; Combine masked sprite + masked screen
    STA (screen_ptr),Y      ; Write result to screen
    
    INY
    CPY #16                 ; 16 bytes for one half of character sprite
    BNE mask_sprite_byte_loop
    
    RTS

; Sprite blit used by Spycat-format character sprites.
; Data: 4 stripes × 32 bytes/stripe (8 scanlines × 4 bytes/scanline).
; Screen: each stripe is 8 scanlines below the previous one.
;
; Debug version (no mask): dst = pix (hard overwrite)
; Requires: sprite_ptr = pix data, screen_ptr = top-left screen
.plot_sprite12x32_striped_copy
    ; Preserve base pointers so we can restore them.
    LDA sprite_ptr
    STA temp_sprite_ptr
    LDA sprite_ptr+1
    STA temp_sprite_ptr+1

    LDX #0
.copy_stripe_loop
    LDY #0
.copy_row_bytes
    LDA (sprite_ptr),Y
    STA (screen_ptr),Y
    INY
    CPY #32
    BNE copy_row_bytes

    ; Next stripe: move down 8 scanlines on screen.
    INC screen_ptr+1

    ; Next stripe in data (+32 bytes)
    LDA sprite_ptr
    CLC
    ADC #32
    STA sprite_ptr
    BCC copy_sprite_ptr_ok
    INC sprite_ptr+1
.copy_sprite_ptr_ok

    INX
    CPX #4
    BNE copy_stripe_loop

    ; Restore screen_ptr (advanced 4 stripes)
    LDA screen_ptr+1
    SEC
    SBC #4
    STA screen_ptr+1

    ; Restore sprite_ptr
    LDA temp_sprite_ptr
    STA sprite_ptr
    LDA temp_sprite_ptr+1
    STA sprite_ptr+1

    RTS

; Masked version (Spycat-style): dst = (dst & mask) | pix
; Requires: sprite_ptr = pix data, mask_ptr = mask data, screen_ptr = top-left screen
.plot_sprite12x32_masked_striped
    ; Preserve base pointers so we can restore them.
    LDA sprite_ptr
    STA temp_sprite_ptr
    LDA sprite_ptr+1
    STA temp_sprite_ptr+1
    LDA mask_ptr
    STA temp_mask_ptr
    LDA mask_ptr+1
    STA temp_mask_ptr+1

    LDX #0
.masked_stripe_loop
    LDY #0
.masked_row_bytes
    LDA (screen_ptr),Y
    AND (mask_ptr),Y
    ORA (sprite_ptr),Y
    STA (screen_ptr),Y

    INY
    CPY #32
    BNE masked_row_bytes

    ; Next stripe: move down 8 scanlines on screen.
    INC screen_ptr+1

    ; Next stripe in data (+32 bytes)
    LDA sprite_ptr
    CLC
    ADC #32
    STA sprite_ptr
    BCC masked_sprite_ptr_ok
    INC sprite_ptr+1
.masked_sprite_ptr_ok

    LDA mask_ptr
    CLC
    ADC #32
    STA mask_ptr
    BCC masked_mask_ptr_ok
    INC mask_ptr+1
.masked_mask_ptr_ok

    INX
    CPX #4
    BNE masked_stripe_loop

    ; Restore screen_ptr (advanced 4 stripes)
    LDA screen_ptr+1
    SEC
    SBC #4
    STA screen_ptr+1

    ; Restore sprite/mask pointers
    LDA temp_sprite_ptr
    STA sprite_ptr
    LDA temp_sprite_ptr+1
    STA sprite_ptr+1
    LDA temp_mask_ptr
    STA mask_ptr
    LDA temp_mask_ptr+1
    STA mask_ptr+1

    RTS

; Sprite pointer table lookup is now used for sprite selection.


; Redraw the tiles behind the character
; Uses char_tile_pos to determine which tiles to restore.
; Note: screen_ptr is ignored for positioning (it is recomputed from char_tile_pos).
.redraw_background_area
    CLI
    ; Save screen_ptr
    LDA screen_ptr
    PHA
    LDA screen_ptr+1
    PHA
    
    ; Character sprite is 1 tile wide × 2 tiles tall (32 scanlines).
    ; We redraw 2 tiles (current tile + tile below).
    
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
    
    ; Move down one tile row (512 bytes)
    INC screen_ptr+1
    INC screen_ptr+1
    
    ; Second tile - next tile row down (char_tile_pos + 16)
    LDY char_tile_pos
    TYA
    CLC
    ADC #16
    TAY
    JSR get_tilemap_tile
    JSR render_large_block
    
    ; Restore screen_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    
    SEI
    RTS