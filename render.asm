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


; Simple sprite plotting routine for MODE 5
; plots the sprite at sprite_ptr at the location in screen_ptr
.plot_simple_sprite
    ; the sprite we want is in the accumulator
    JSR calc_sprite_data_location

    ; Plot 8 bytes of sprite data consecutively
    LDY #0
.sprite_row_loop
    LDA (sprite_ptr),Y; Get sprite row data
    STA (screen_ptr),Y  ; Plot to screen at offset Y
    INY
    CPY #8              ; 8 bytes
    BNE sprite_row_loop
    
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

; Sprite pointer table lookup is now used for sprite selection.
    
