; lookup_tables.asm
; Performance optimization lookup tables

; Table for row_counter * 16 (0 to 15) - for tilemap rendering
; Saves 6 cycles per tile (4 ASL operations = 8 cycles vs LDA table = 2 cycles)
.times16_table
EQUB 0*16, 1*16, 2*16, 3*16, 4*16, 5*16, 6*16, 7*16
EQUB 8*16, 9*16, 10*16, 11*16, 12*16, 13*16, 14*16, 15*16