; lookup_tables.asm
; Performance optimization lookup tables

; Table for row_counter * 16 (0 to 15) - for cellmap rendering
; Saves 6 cycles per cell (4 ASL operations = 8 cycles vs LDA table = 2 cycles)
.times16_table
EQUB 0*16, 1*16, 2*16, 3*16, 4*16, 5*16, 6*16, 7*16
EQUB 8*16, 9*16, 10*16, 11*16, 12*16, 13*16, 14*16, 15*16

; Table for cell-row screen positions (cell_y * 512 + screen_base)
; 16 entries for 16 cell rows.
;
; Each cell row is 16 scanlines high in MODE 5.
; With a 128px-wide playfield we have 32 bytes per scanline.
; So each cell row is 32*16 = 512 bytes apart.
;
; Base address &5800 + (row * 512)
;
; With 16 rows, the playfield occupies:
;   &5800 .. &5800 + 16*512 - 1  =  &5800 .. &77FF
; Anything >= &7800 is considered "below playfield" and may be used
; as scratch screen RAM (as long as we avoid OS CLS/VDU clears after init).
.tile_row_screen_table
EQUW &5800 + (0*512), &5800 + (1*512), &5800 + (2*512), &5800 + (3*512)
EQUW &5800 + (4*512), &5800 + (5*512), &5800 + (6*512), &5800 + (7*512)
EQUW &5800 + (8*512), &5800 + (9*512), &5800 + (10*512), &5800 + (11*512)
EQUW &5800 + (12*512), &5800 + (13*512), &5800 + (14*512), &5800 + (15*512)
