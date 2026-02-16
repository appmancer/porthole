.room_runtime_start
; room_runtime.asm
; Runtime helpers for room pointers and screen address calculation.

; Update screen_ptr from char_tile_pos.
.update_screen_ptr_from_char
    ; tile_y = char_tile_pos >> 4
    LDA char_tile_pos
    LSR A
    LSR A
    LSR A
    LSR A
    STA temp_y

    ; Look up screen base for this tile row
    ASL A
    TAY
    LDA tile_row_screen_table,Y
    STA screen_ptr
    LDA tile_row_screen_table+1,Y
    STA screen_ptr+1

    ; Optional +8 scanline offset (1 stripe) within the 16px cell row.
    ; (Purely derived from gameplay state; no extra visual bias.)
    LDA char_y_offset
    BEQ char_y_offset_done
    INC screen_ptr+1
.char_y_offset_done

    ; tile_x = char_tile_pos & 15
    LDA char_tile_pos
    AND #15
    TAY

    ; Add tile_x * 16
    LDA times16_table,Y
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC add_byte_offset
    INC screen_ptr+1

.add_byte_offset
    LDA char_byte_offset
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC update_screen_done
    INC screen_ptr+1
.update_screen_done
    RTS


; Update screen_ptr from reticle portal-grid cell.
;
; Note: reticle_cell_x is expressed in 8px tile columns (0..14), representing
; the top-left tile_x of a 2-tile-wide portal span. (reticle_cell_y is still a
; 16px tile row index, 0..15.)
.update_screen_ptr_from_reticle
    ; tile_y = reticle_cell_y
    LDA reticle_cell_y
    STA temp_y

    ; Look up screen base for this tile row
    ASL A
    TAY
    LDA tile_row_screen_table,Y
    STA screen_ptr
    LDA tile_row_screen_table+1,Y
    STA screen_ptr+1

    ; tile_x = reticle_cell_x
    LDY reticle_cell_x

    ; Add tile_x * 16
    LDA times16_table,Y
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC reticle_screen_done
    INC screen_ptr+1
.reticle_screen_done
    RTS


; Update screen_ptr from cube_tile_pos.
.update_screen_ptr_from_cube
    ; tile_y = cube_tile_pos >> 4
    LDA cube_tile_pos
    LSR A
    LSR A
    LSR A
    LSR A
    STA temp_y

    ; Look up screen base for this tile row
    ASL A
    TAY
    LDA tile_row_screen_table,Y
    STA screen_ptr
    LDA tile_row_screen_table+1,Y
    STA screen_ptr+1

    ; tile_x = cube_tile_pos & 15
    LDA cube_tile_pos
    AND #15
    TAY

    ; Add tile_x * 16
    LDA times16_table,Y
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC cube_add_byte_offset
    INC screen_ptr+1

.cube_add_byte_offset
    LDA cube_byte_offset
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC cube_screen_done
    INC screen_ptr+1
.cube_screen_done
    RTS


; Set tilemap_ptr based on current_room variable.
; Uses room_pointers table to get correct room data.
.set_room_tilemap
    LDA current_room
    ASL A                   ; ×2 for 16-bit pointer
    TAX

    LDA room_pointers,X
    STA tilemap_ptr
    LDA room_pointers+1,X
    STA tilemap_ptr+1

    RTS


; Set room_fizzler_count and room_fizzler_ptr from current_room.
.set_room_fizzlers
    LDA current_room
    ASL A
    TAX
    LDA fizzler_room_ptrs,X
    STA room_fizzler_ptr
    LDA fizzler_room_ptrs+1,X
    STA room_fizzler_ptr+1
    LDX current_room
    LDA fizzler_room_counts,X
    STA room_fizzler_count
    RTS


; Get cell value from cellmap at specified cell position.
; Input: Y = cell position (cell_y * 16 + cell_x)
; Output: A = cell value
.get_tilemap_tile
    LDA (tilemap_ptr),Y
    RTS
