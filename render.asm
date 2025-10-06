; render.asm
; Routines to render a tilemap and sprites in MODE 5

.render_tilemap
    ; Set up initial pointers
    LDA #<(&5800)           ; Screen starts at &5800 in MODE 5
    STA &71                 ; screen_ptr_lo 
    LDA #>(&5800)
    STA &72                 ; screen_ptr_hi
    
    LDA #<(sprite_data)     ; Set up sprite pointer 
    STA &73                 ; sprite_ptr_lo
    LDA #>(sprite_data) 
    STA &74                 ; sprite_ptr_hi
    
    ; Initialize row counter  
    LDA #0
    STA &77                 ; row_counter

.tilemap_row_loop
    ; Initialize column counter
    LDA #0
    STA &78                 ; col_counter
    
.tilemap_col_loop
    ; Calculate tilemap index: row_counter * 16 + col_counter  
    LDA &77                 ; row_counter
    ASL A                   ; × 2
    ASL A                   ; × 4
    ASL A                   ; × 8
    ASL A                   ; × 16
    CLC
    ADC &78                 ; + col_counter
    TAY
    
    ; Get tile value directly (8-bit format - no nibble extraction!)
    LDA (&7B), Y            ; tilemap_ptr is in &7B/&7C
    JSR render_large_block
    
    ; Move screen pointer right by 16 bytes
    LDA &71
    CLC  
    ADC #16
    STA &71
    BCC tilemap_col_loop_no_carry
    INC &72
    
.tilemap_col_loop_no_carry    
    ; Next column
    INC &78
    LDA &78
    CMP #16                 ; 16 columns total
    BNE tilemap_col_loop
    
.tilemap_end_of_row
    ; Move to next screen row (add 256 bytes)
    INC &72                 ; screen_ptr_hi++
    
    ; Next row
    INC &77
    LDA &77
    CMP #16                 ; 16 rows total  
    BEQ tilemap_done
    JMP tilemap_row_loop
    
.tilemap_done
    RTS

.render_large_block
    ; Store tile type
    STA &76                 ; tile
    
    ; Preserve screen pointer  
    LDA &71
    PHA
    LDA &72
    PHA
    
    ; Get sprite data pointer for this tile
    LDA &76                 ; tile
    ASL A                   ; × 2 for 16-bit pointer
    TAX
    LDA sprite_table,X
    STA &73                 ; sprite_ptr_lo
    LDA sprite_table+1,X 
    STA &74                 ; sprite_ptr_hi
    
    ; Plot first half (top 8 rows)
    JSR plot_wide_sprite
    
    ; Move screen pointer down 8 rows (256 bytes)
    LDA &72
    CLC
    ADC #1
    STA &72
    
    ; Move sprite pointer to bottom half (+16 bytes)
    LDA &73
    CLC
    ADC #16
    STA &73
    BCC next_half
    INC &74
    
.next_half
    ; Plot second half (bottom 8 rows)
    JSR plot_wide_sprite
    
    ; Restore screen pointer
    PLA
    STA &72
    PLA  
    STA &71
    RTS

; Masked version of render_large_block - for sprites with transparent black pixels
.render_masked_large_block
    ; Store tile type
    STA &76                 ; tile
    
    ; Preserve screen pointer
    LDA &71
    PHA
    LDA &72
    PHA
    
    ; Get sprite data pointer for this tile
    LDA &76                 ; tile
    ASL A                   ; × 2 for 16-bit pointer
    TAX
    LDA sprite_table,X
    STA &73                 ; sprite_ptr_lo
    LDA sprite_table+1,X
    STA &74                 ; sprite_ptr_hi
    
    ; Plot first half (top 8 rows) with masking
    JSR plot_masked_wide_sprite
    
    ; Move screen pointer down 8 rows (256 bytes)
    LDA &72
    CLC
    ADC #1
    STA &72
    
    ; Move sprite pointer to bottom half (+16 bytes)
    LDA &73
    CLC
    ADC #16
    STA &73
    BCC next_half_masked
    INC &74
    
.next_half_masked
    ; Plot second half (bottom 8 rows) with masking  
    JSR plot_masked_wide_sprite
    
    ; Restore screen pointer
    PLA
    STA &72
    PLA
    STA &71
    RTS

; plots a 16-byte, double character wide sprite
.plot_wide_sprite
    ; Plot 16 bytes of sprite data consecutively
    LDY #0
.sprite_wide_row_loop
    LDA (&73),Y             ; Get sprite row data from sprite_ptr (&73/&74)
    STA (&71),Y             ; Plot to screen at screen_ptr (&71/&72)
    INY
    CPY #16                 ; 16 bytes per row
    BNE sprite_wide_row_loop
    RTS

; plots a 16-byte, double character wide sprite with masking (black pixels transparent)
; MODE 5 uses interleaved bits: pixel 0=bits 0+4, pixel 1=bits 1+5, pixel 2=bits 2+6, pixel 3=bits 3+7
.plot_masked_wide_sprite
    LDY #0
.masked_sprite_byte_loop
    LDA (&73),Y             ; Load sprite byte from sprite_ptr (&73/&74)
    BEQ skip_sprite_byte    ; If entire byte is 0 (all black), skip it
    
    STA &70                 ; Store sprite byte in &70 (temp)
    LDA (&71),Y             ; Load current screen byte from screen_ptr (&71/&72)
    STA &75                 ; Store screen byte in &75 (temp_y)
    
    ; Process pixel 0 (bits 0 and 4) - MSB bit 0 = bit 7, bit 4 = bit 3
    LDA &70
    AND #&88                ; Mask bits 7 and 3 (0 and 4 in MSB numbering)
    BEQ keep_screen_pixel0  ; If sprite pixel is black, keep screen pixel
    LDA &75
    AND #&77                ; Clear screen bits 7 and 3  
    ORA &70                 ; OR in sprite bits 7 and 3
    STA &75
.keep_screen_pixel0
    
    ; Process pixel 1 (bits 1 and 5) - MSB bit 1 = bit 6, bit 5 = bit 2
    LDA &70
    AND #&44                ; Mask bits 6 and 2 (1 and 5 in MSB numbering)
    BEQ keep_screen_pixel1  ; If sprite pixel is black, keep screen pixel
    LDA &75
    AND #&BB                ; Clear screen bits 6 and 2
    ORA &70                 ; OR in sprite bits 6 and 2
    STA &75
.keep_screen_pixel1
    
    ; Process pixel 2 (bits 2 and 6) - MSB bit 2 = bit 5, bit 6 = bit 1
    LDA &70
    AND #&22                ; Mask bits 5 and 1 (2 and 6 in MSB numbering)
    BEQ keep_screen_pixel2  ; If sprite pixel is black, keep screen pixel
    LDA &75
    AND #&DD                ; Clear screen bits 5 and 1
    ORA &70                 ; OR in sprite bits 5 and 1
    STA &75
.keep_screen_pixel2
    
    ; Process pixel 3 (bits 3 and 7) - MSB bit 3 = bit 4, bit 7 = bit 0
    LDA &70
    AND #&11                ; Mask bits 4 and 0 (3 and 7 in MSB numbering)
    BEQ keep_screen_pixel3  ; If sprite pixel is black, keep screen pixel
    LDA &75
    AND #&EE                ; Clear screen bits 4 and 0
    ORA &70                 ; OR in sprite bits 4 and 0
    STA &75
.keep_screen_pixel3
    
    LDA &75
    STA (&71),Y             ; Write modified byte back to screen
    
.skip_sprite_byte
    INY
    CPY #16                 ; 16 bytes total
    BNE masked_sprite_byte_loop
    
    RTS; Render character sprite with mask - uses character_sprite_table and character_mask_table
.render_character_sprite
    ; preserve A
    STA tile
    ; preserve screen_ptr
    LDA screen_ptr
    PHA
    LDA screen_ptr +1
    PHA
    ; restore A
    LDA tile
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
    
