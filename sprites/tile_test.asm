; Standalone tile viewer.
;
; Fills a MODE 5 screen with a tile set so you can see how it looks (and how
; it tiles) on a real Beeb. Built by ./build_tile_test.sh, which points
; tools/gen-tiles at whichever tile CSV you want to look at.
;
; The tile CSV is expected to use colour index 0 (black) and 2 (green here).

INCLUDE "shared/oscalls.asm"
INCLUDE ".tmp/test_tiles_count.asm"   ; defines TILE_COUNT

SCREEN_BASE = &5800     ; MODE 5 screen start
BAND_BYTES  = 320       ; bytes per 8-pixel-row band (40 cells * 8)
TILE_BYTES  = 16        ; bytes per tile per band (2 cells * 8)
TILE_COLS   = 20        ; 160 MODE 5 pixels / 8
TILE_ROWS   = 16        ; 256 rows / 16

; Zero page workspace (&70-&8F is free for user code).
zp_src      = &70       ; tile data, top band
zp_src2     = &72       ; tile data, bottom band
zp_dst      = &74       ; screen address, top band
zp_dst2     = &76       ; screen address, bottom band
zp_row      = &78
zp_col      = &79

ORG &1900
GUARD SCREEN_BASE

.start
    CLI

    LDA #22: JSR OSWRCH     ; MODE 5
    LDA #5:  JSR OSWRCH

    JSR hide_cursor
    JSR set_palette
    JSR draw_screen

    ; Wait for a key so the screen stays up, then drop back to MODE 7.
    JSR wait_key
    LDA #22: JSR OSWRCH
    LDA #7:  JSR OSWRCH
    RTS


; VDU 23,1,0;0;0;0; — turn the text cursor off.
.hide_cursor
    LDX #0
.hc_loop
    LDA cursor_vdu,X
    JSR OSWRCH
    INX
    CPX #10
    BNE hc_loop
    RTS

.cursor_vdu
    EQUB 23,1,0,0,0,0,0,0,0,0


.set_palette
    LDX #0
.sp_loop
    LDA palette_vdu,X
    JSR OSWRCH
    INX
    CPX #24
    BNE sp_loop
    RTS

.palette_vdu
    EQUB 19,0,0,0,0,0       ; logical 0 -> black
    EQUB 19,1,2,0,0,0       ; logical 1 -> green
    EQUB 19,2,2,0,0,0       ; logical 2 -> green
    EQUB 19,3,7,0,0,0       ; logical 3 -> white


; Fill the screen with the tile set, cycling through tiles 1..TILE_COUNT
; down each column so a multi-tile design repeats vertically.
.draw_screen
    LDA #LO(SCREEN_BASE): STA zp_dst
    LDA #HI(SCREEN_BASE): STA zp_dst+1
    LDA #0: STA zp_row

.ds_row
    ; Pick this row's tile: (row MOD TILE_COUNT) + 1, i.e. skip tile 0.
    LDA zp_row
.ds_mod
    CMP #TILE_COUNT
    BCC ds_mod_done
    SBC #TILE_COUNT
    JMP ds_mod
.ds_mod_done
    CLC
    ADC #1
    ASL A                   ; two bytes per sprite_table entry
    TAX
    LDA sprite_table,X:   STA zp_src
    LDA sprite_table+1,X: STA zp_src+1

    ; zp_src2 = zp_src + 16 (the tile's second band of cells).
    CLC
    LDA zp_src:   ADC #TILE_BYTES: STA zp_src2
    LDA zp_src+1: ADC #0:          STA zp_src2+1

    ; zp_dst2 = zp_dst + 320 (the screen band below).
    CLC
    LDA zp_dst:   ADC #LO(BAND_BYTES): STA zp_dst2
    LDA zp_dst+1: ADC #HI(BAND_BYTES): STA zp_dst2+1

    LDA #0: STA zp_col

.ds_col
    ; A tile is 2 cells wide, and cells are contiguous within a band, so
    ; each band is a single 16-byte run.
    LDY #TILE_BYTES-1
.ds_copy
    LDA (zp_src),Y
    STA (zp_dst),Y
    LDA (zp_src2),Y
    STA (zp_dst2),Y
    DEY
    BPL ds_copy

    ; Next tile column: both screen pointers advance 16 bytes.
    CLC
    LDA zp_dst:  ADC #TILE_BYTES: STA zp_dst
    LDA zp_dst+1: ADC #0:         STA zp_dst+1
    CLC
    LDA zp_dst2:  ADC #TILE_BYTES: STA zp_dst2
    LDA zp_dst2+1: ADC #0:         STA zp_dst2+1

    INC zp_col
    LDA zp_col
    CMP #TILE_COLS
    BNE ds_col

    ; zp_dst has walked one whole band; skip the band the tile bottoms used.
    CLC
    LDA zp_dst:   ADC #LO(BAND_BYTES): STA zp_dst
    LDA zp_dst+1: ADC #HI(BAND_BYTES): STA zp_dst+1

    INC zp_row
    LDA zp_row
    CMP #TILE_ROWS
    BNE ds_row
    RTS


.wait_key
    JSR OSRDCH
    RTS


INCLUDE ".tmp/generated_test_tiles.asm"

.end

SAVE "TILET", start, end
