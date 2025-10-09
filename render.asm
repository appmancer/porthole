; render.asm
; Routines to render a tilemap and sprites in MODE 5

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

    ; Plot first character row (top half)
    JSR plot_sprite_with_mask
    ; move screen_ptr down 8 scanlines (256 bytes)
    INC screen_ptr+1
    ; move sprite_ptr to next sprite data (next 16 bytes)
    LDA sprite_ptr
    CLC
    ADC #16
    STA sprite_ptr
    BCC sprite_row2_ok
    INC sprite_ptr+1
.sprite_row2_ok
    ; move mask_ptr to next mask data (next 16 bytes)
    LDA mask_ptr
    CLC
    ADC #16
    STA mask_ptr
    BCC char_row2
    INC mask_ptr+1
.char_row2  
    ; Plot second character row
    JSR plot_sprite_with_mask
    ; move screen_ptr down 8 scanlines (256 bytes)
    INC screen_ptr+1
    ; move sprite_ptr to next sprite data (next 16 bytes)
    LDA sprite_ptr
    CLC
    ADC #16
    STA sprite_ptr
    BCC sprite_row3_ok
    INC sprite_ptr+1
.sprite_row3_ok
    ; move mask_ptr to next mask data (next 16 bytes)
    LDA mask_ptr
    CLC
    ADC #16
    STA mask_ptr
    BCC char_row3
    INC mask_ptr+1
.char_row3  
    ; Plot third character row
    JSR plot_sprite_with_mask
    ; move screen_ptr down 8 scanlines (256 bytes)
    INC screen_ptr+1
    ; move sprite_ptr to next sprite data (next 16 bytes)
    LDA sprite_ptr
    CLC
    ADC #16
    STA sprite_ptr
    BCC sprite_row4_ok
    INC sprite_ptr+1
.sprite_row4_ok
    ; move mask_ptr to next mask data (next 16 bytes)
    LDA mask_ptr
    CLC
    ADC #16
    STA mask_ptr
    BCC char_row4
    INC mask_ptr+1
.char_row4  
    ; Plot fourth character row (bottom - legs!)
    JSR plot_sprite_with_mask

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

; Sprite pointer table lookup is now used for sprite selection.


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