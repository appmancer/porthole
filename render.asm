; render.asm
; Routines to render a tilemap and sprites in MODE 5


.render_tilemap
    ; Set screen_ptr to &5800 (start of screen memory in MODE 5)
    LDA #<(&5800)    ; Load low byte of screen address
    STA screen_ptr
    LDA #>(&5800)    ; Load high byte of screen address
    STA screen_ptr+1

    ; Set sprite_ptr to start of sprite data
    LDA #<(sprite_data)
    STA sprite_ptr
    LDA #>(sprite_data)
    STA sprite_ptr+1

    ; Loop through each row of the tilemap (17 rows)
    LDA #0
    STA row_counter
.tilemap_row_loop
    ; Loop through each column of the tilemap (16 columns)
    LDA #0
    STA col_counter
.tilemap_col_loop
    ; Calculate tilemap index: row_counter * 8 + col_counter
    LDA row_counter
    ASL A        ; × 2
    ASL A        ; × 4  
    ASL A        ; × 8
    CLC
    ADC col_counter
    STA tile_index
    LDY tile_index
    ; Get the high nibble (left tile)
    LDA (tilemap_ptr), Y
    AND #&F0
    LSR A
    LSR A
    LSR A
    LSR A
    JSR render_large_block  ; Render the left tile  
    ;move screen_ptr to the right tile (next sprite) by adding 16 
    LDA screen_ptr
    CLC
    ADC #16             ; And adding 16 bytes
    STA screen_ptr
    BCC tilemap_col_loop_no_carry
    INC screen_ptr+1
.tilemap_col_loop_no_carry
    ; Get the low nibble (right tile)
    LDY tile_index
    LDA (tilemap_ptr), Y
    AND #&0F
.render_right_tile
    JSR render_large_block  ; Render the right tile 
    ;move screen_ptr to the right tile (next sprite) by adding 16
    LDA screen_ptr
    CLC
    ADC #16             ; And adding 16 bytes
    STA screen_ptr
    BCC tilemap_col_loop_end
    INC screen_ptr+1
.tilemap_col_loop_end
    INC col_counter
    LDA col_counter
    CMP #8 ; 8 pairs of tiles (16 columns)
    BNE tilemap_col_loop
.tilemap_end_of_row
    ; Move down 1 character row (256 bytes) to next tilemap row
    INC screen_ptr+1
    ; Increment row counter and check if done
    INC row_counter
    LDA row_counter
    CMP #16 ; 16 rows total
    BEQ tilemap_done
    JMP tilemap_row_loop
.tilemap_done
    RTS

.render_large_block
    ; preserve A
    STA tile
    ; preserve screen_ptr
    LDA screen_ptr
    PHA
    LDA screen_ptr +1
    PHA
    ; restore A
    LDA tile
    ; Input: A = block type (0-based index for sprite table)
    ASL A
    TAX
    LDA sprite_table,X
    STA sprite_ptr
    LDA sprite_table+1,X
    STA sprite_ptr+1

    JSR plot_wide_sprite
    ; move screen_ptr down 8 rows (256 bytes)
    LDA screen_ptr+1
    CLC
    ADC #1
    STA screen_ptr+1    
    ; move sprite_ptr to next sprite (bottom half of large block)
    LDA sprite_ptr
    CLC
    ADC #16
    STA sprite_ptr
    BCC next_half
    INC sprite_ptr+1
.next_half  
    ; now plot the second row of the block
    JSR plot_wide_sprite

    ; restore screen_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    
    RTS

; Masked version of render_large_block - for sprites with transparent black pixels
.render_masked_large_block
    ; preserve A
    STA tile
    ; preserve screen_ptr
    LDA screen_ptr
    PHA
    LDA screen_ptr +1
    PHA
    ; restore A
    LDA tile
    ; Input: A = block type (0-based index for sprite table)
    ASL A
    TAX
    LDA sprite_table,X
    STA sprite_ptr
    LDA sprite_table+1,X
    STA sprite_ptr+1

    JSR plot_masked_wide_sprite
    ; move screen_ptr down 8 rows (256 bytes)
    LDA screen_ptr+1
    CLC
    ADC #1
    STA screen_ptr+1    
    ; move sprite_ptr to next sprite (bottom half of large block)
    LDA sprite_ptr
    CLC
    ADC #16
    STA sprite_ptr
    BCC next_half_masked
    INC sprite_ptr+1
.next_half_masked  
    ; now plot the second row of the block
    JSR plot_masked_wide_sprite

    ; restore screen_ptr
    PLA
    STA screen_ptr+1
    PLA
    STA screen_ptr
    
    RTS

; plots a 16-byte, double character wide sprite
.plot_wide_sprite

    ; Plot 8 bytes of sprite data consecutively
    LDY #0
.sprite_wide_row_loop
    LDA (sprite_ptr),Y; Get sprite row data
    STA (screen_ptr),Y  ; Plot to screen at offset Y
    INY
    CPY #16              ; 16 bytes
    BNE sprite_wide_row_loop
    
    RTS

; plots a 16-byte, double character wide sprite with masking (black pixels transparent)
; MODE 5 uses interleaved bits: pixel 0=bits 0+4, pixel 1=bits 1+5, pixel 2=bits 2+6, pixel 3=bits 3+7
.plot_masked_wide_sprite
    LDY #0
.masked_sprite_byte_loop
    LDA (sprite_ptr),Y      ; Load sprite byte
    BEQ skip_sprite_byte    ; If entire byte is 0 (all black), skip it
    
    STA temp                ; Store sprite byte in temp
    LDA (screen_ptr),Y      ; Load current screen byte
    STA temp_y              ; Store screen byte in temp_y
    
    ; Process pixel 0 (bits 0 and 4) - MSB bit 0 = bit 7, bit 4 = bit 3
    LDA temp
    AND #&88               ; Mask bits 7 and 3 (0 and 4 in MSB numbering)
    BEQ keep_screen_pixel0  ; If sprite pixel is black, keep screen pixel
    LDA temp_y
    AND #&77               ; Clear screen bits 7 and 3
    ORA temp               ; OR in sprite bits 7 and 3
    STA temp_y
.keep_screen_pixel0
    
    ; Process pixel 1 (bits 1 and 5) - MSB bit 1 = bit 6, bit 5 = bit 2
    LDA temp
    AND #&44               ; Mask bits 6 and 2 (1 and 5 in MSB numbering)
    BEQ keep_screen_pixel1  ; If sprite pixel is black, keep screen pixel
    LDA temp_y
    AND #&BB               ; Clear screen bits 6 and 2
    ORA temp               ; OR in sprite bits 6 and 2
    STA temp_y
.keep_screen_pixel1
    
    ; Process pixel 2 (bits 2 and 6) - MSB bit 2 = bit 5, bit 6 = bit 1
    LDA temp
    AND #&22               ; Mask bits 5 and 1 (2 and 6 in MSB numbering)
    BEQ keep_screen_pixel2  ; If sprite pixel is black, keep screen pixel
    LDA temp_y
    AND #&DD               ; Clear screen bits 5 and 1
    ORA temp               ; OR in sprite bits 5 and 1
    STA temp_y
.keep_screen_pixel2
    
    ; Process pixel 3 (bits 3 and 7) - MSB bit 3 = bit 4, bit 7 = bit 0
    LDA temp
    AND #&11               ; Mask bits 4 and 0 (3 and 7 in MSB numbering)
    BEQ keep_screen_pixel3  ; If sprite pixel is black, keep screen pixel
    LDA temp_y
    AND #&EE               ; Clear screen bits 4 and 0
    ORA temp               ; OR in sprite bits 4 and 0
    STA temp_y
.keep_screen_pixel3
    
    LDA temp_y
    STA (screen_ptr),Y      ; Write modified byte back to screen
    
.skip_sprite_byte
    INY
    CPY #16                 ; 16 bytes total
    BNE masked_sprite_byte_loop
    
    RTS

; Sprite pointer table lookup is now used for sprite selection.
    
