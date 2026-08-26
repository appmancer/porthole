.screens_start
; screens.asm
;
; MODE 7 interstitial screens: instruction screen + level title card.
; Both use MODE 7 (teletext) for zero-overhead text display.
;
; Enter MODE 7 via VDU 22,7 (clean, correct hardware setup).
; Return to MODE 5 via direct Video ULA + CRTC writes (avoids VDU 22,5
; clearing &5800-&7FFF where game code lives).
; MOS VDU workspace is saved/restored around the VDU 22,7 call so that
; VDU-based routines in .start (set_palette, disable_cursor) still work.


; --- show_start_screen ---
; Load a raw 1000-byte MODE 7 screen from disc and display it.
; Blocks until SPACE pressed.
.show_start_screen
    JSR enter_mode7

    ; OSFILE &FF — load STRTSCR directly into MODE 7 screen RAM at &7C00.
    LDA #&FF
    LDX #<osfile_blk_strtscr
    LDY #>osfile_blk_strtscr
    JSR OSFILE

    JSR wait_space
    JSR restore_mode5
    RTS


; --- show_level_card ---
; Display MODE 5 level title card: Aperture logo on the background accent colour.
; Blocks until SPACE pressed.
; Input: current_level (0-indexed) in ZP.
.show_level_card

    ; Fill shadow screen RAM with the background accent colour (handles
    ; ACCCON X=1 internally).
    JSR clear_playfield_bg


    ; Ensure CRTC R1=32 (128px wide) and R2=45 (centred) so the screen
    ; memory layout matches our 32-byte-per-row logo data.
    ; After restore_mode5, R1=40; we need our custom narrow layout.
    LDA #1  : STA CRTC_ADDR
    LDA #32 : STA CRTC_DATA
    LDA #2  : STA CRTC_ADDR
    LDA #45 : STA CRTC_DATA

    ; Ensure CRTC displays shadow RAM (D=1).
    ; Safe from above &3000 — only X bit is dangerous.
    ; LYNNE is already filled with cyan, so no garbage flash.
    LDA ACCCON
    ORA #&01
    STA ACCCON


    ; Load Aperture logo from disc directly into shadow screen RAM at &5C00
    ; (tile rows 2-5). Use the shared OSFILE block / filename area.
    LDA #'A' : STA PACK_FNAME+0
    LDA #'P' : STA PACK_FNAME+1
    LDA #'L' : STA PACK_FNAME+2
    LDA #'O' : STA PACK_FNAME+3
    LDA #'G' : STA PACK_FNAME+4
    LDA #'O' : STA PACK_FNAME+5
    LDA #13  : STA PACK_FNAME+6

    ; OSFILE control block: load to &5A00.
    LDA #<PACK_FNAME
    STA PACK_OSFILE_BLK+0
    LDA #>PACK_FNAME
    STA PACK_OSFILE_BLK+1
    LDA #&00
    STA PACK_OSFILE_BLK+2       ; load addr low = &00
    LDA #&5A
    STA PACK_OSFILE_BLK+3       ; load addr high = &5A
    LDA #0
    STA PACK_OSFILE_BLK+4
    STA PACK_OSFILE_BLK+5
    STA PACK_OSFILE_BLK+6       ; exec addr low = 0 => use supplied load addr
    STA PACK_OSFILE_BLK+7
    STA PACK_OSFILE_BLK+8
    STA PACK_OSFILE_BLK+9
    STA PACK_OSFILE_BLK+10
    STA PACK_OSFILE_BLK+11
    STA PACK_OSFILE_BLK+12
    STA PACK_OSFILE_BLK+13
    STA PACK_OSFILE_BLK+14
    STA PACK_OSFILE_BLK+15
    STA PACK_OSFILE_BLK+16
    STA PACK_OSFILE_BLK+17

    ; Load via trampoline (sets ACCCON X=1 for LYNNE write, restores X=0).
    JSR lynne_osfile

    ; Fill bottom half of screen (char rows 10-31) with yellow.
    JSR fill_yellow_from_row12

    ; Set the game palette first — on first entry the palette may still
    ; reflect MODE 7's settings (restore_mode5 doesn't set palette entries).
    ; This ensures colour 2 = cyan before we remap colour 0 to blue.
    JSR set_palette

    ; Remap colour 0 from black to blue for the card display.

    ; VDU 19,0,4,0,0,0 — logical 0 -> physical 4 (blue)
    LDA #19 : JSR OSWRCH
    LDA #0  : JSR OSWRCH
    LDA #4  : JSR OSWRCH
    LDA #0  : JSR OSWRCH
    LDA #0  : JSR OSWRCH
    LDA #0  : JSR OSWRCH

    ; --- "LABORATORIES" under the logo ---
    ; Half-width, blue on cyan, at char row 8 col 11.
    ; Row 8 = &5800 + 8*256 = &6000, col 11 = 11*8 = 88 bytes.
    LDA #<slc_laboratories
    STA sprite_ptr
    LDA #>slc_laboratories
    STA sprite_ptr+1
    LDA #<(&6000 + 88)
    STA screen_ptr
    LDA #>(&6000 + 88)
    STA screen_ptr+1
    LDA #12                     ; "LABORATORIES" = 12 chars
    STA col_counter
    LDA #&F0                    ; cyan bg
    STA row_counter
    LDA #&00                    ; colour 0 fg (blue)
    STA temp_y
    JSR draw_half_text

    ; --- Render card text from level data ---
    ; level_card_ptr points to length-prefixed strings in STAGING_BUF:
    ;   [len] [title...]  [len] [quote1...]  [len] [quote2...]
    ;
    ; Patch level number digits in the title before drawing.
    ; "TEST CHAMBER 00" — the "00" are at byte offsets 14 and 15
    ; (1 length byte + 13 chars to reach the first '0').
    LDA level_card_ptr
    STA tilemap_ptr
    LDA level_card_ptr+1
    STA tilemap_ptr+1

    LDA current_level
    CLC
    ADC #1                      ; 1-indexed
    LDX #0
.slc_tens
    CMP #10
    BCC slc_tens_done
    SBC #10
    INX
    JMP slc_tens
.slc_tens_done
    PHA                         ; save units

    ; Write tens digit.
    TXA
    CLC
    ADC #ASC("0")
    LDY #14                     ; offset: 1 (length byte) + 13
    STA (tilemap_ptr),Y

    ; Write units digit.
    PLA
    CLC
    ADC #ASC("0")
    LDY #15                     ; offset: 1 (length byte) + 14
    STA (tilemap_ptr),Y

    ; Reset read pointer to start of card data.
    LDA level_card_ptr
    STA tilemap_ptr
    LDA level_card_ptr+1
    STA tilemap_ptr+1

    ; All text is on the yellow section (char rows 10+).
    ; Set bg byte for yellow (colour 3 = &FF).
    LDA #&FF
    STA row_counter

    ; Draw title at char row 16 = &6800. Half-width, red on yellow.
    LDA #&0F                    ; colour 1 fg (red)
    STA temp_y
    LDA #<(&6800)
    STA temp_mask_ptr
    LDA #>(&6800)
    STA temp_mask_ptr+1
    JSR draw_card_line

    ; Draw quote lines in half-width, blue on yellow.
    ; Vertically centred around row 23:
    ;   2 lines -> rows 22 and 24 (&6E00, &7000)
    ;   1 line  -> row 23 (&6F00)
    ;   0 lines -> nothing
    LDA #&00                    ; colour 0 fg (blue)
    STA temp_y

    ; Peek at quote line 1 length (tilemap_ptr points at it now).
    LDY #0
    LDA (tilemap_ptr),Y
    BEQ slc_no_quotes           ; line 1 empty — skip both

    ; Line 1 exists. Peek at line 2 length to decide layout.
    ; Line 2 length is at tilemap_ptr + 1 + line1_len.
    STA DCL_LEN                 ; save line 1 length
    CLC
    ADC #1                      ; skip length byte + string
    TAY
    LDA (tilemap_ptr),Y         ; line 2 length
    BEQ slc_one_quote           ; line 2 empty — single line

    ; Two quote lines: rows 22 and 24.
    LDA #<(&6E00)
    STA temp_mask_ptr
    LDA #>(&6E00)
    STA temp_mask_ptr+1
    JSR draw_card_line

    LDA #<(&7000)
    STA temp_mask_ptr
    LDA #>(&7000)
    STA temp_mask_ptr+1
    JSR draw_card_line
    JMP slc_quotes_done

.slc_one_quote
    ; One quote line: row 23.
    LDA #<(&6F00)
    STA temp_mask_ptr
    LDA #>(&6F00)
    STA temp_mask_ptr+1
    JSR draw_card_line
    ; Skip the empty second line.
    JSR draw_card_line
    JMP slc_quotes_done

.slc_no_quotes
    ; Skip both empty lines (advance tilemap_ptr past them).
    JSR draw_card_line
    JSR draw_card_line

.slc_quotes_done

    JSR wait_space

    ; Palette restored by set_palette in .start (colour 0 -> black).
    RTS

.slc_laboratories
    EQUS "LABORATORIES"


; --- show_complete_screen ---
; Display GLaDOS typewriter monologue on the Aperture template.
; Blocks until the monologue finishes, then waits for SPACE.
; SPACE during typing skips to the end.
.show_complete_screen
    JSR enter_mode7

    ; Load Aperture template background.
    LDA #&FF
    LDX #<osfile_blk_templte
    LDY #>osfile_blk_templte
    ; Sound and disc access conflict on the BBC: the sound interrupt disturbs
    ; the timing-critical DFS transfer. OSBYTE &D2 only suppresses NEW sounds
    ; -- notes already in the MOS buffers keep playing -- so flush every
    ; channel first, then suppress across the load. (&D2: X=1 off, X=0 on.)
    JSR sfx_silence_all
    LDA #210 : LDX #1 : LDY #0 : JSR OSBYTE
    JSR OSFILE
    LDA #210 : LDX #0 : LDY #0 : JSR OSBYTE


    ; Clear &8D (double-height) codes baked into template rows 12-14.
    ; These would interfere with our own double-height header above.
    LDA #&A0                   ; space
    STA &7C00 + 12*40 + 3
    STA &7C00 + 13*40 + 3
    STA &7C00 + 14*40 + 3

    ; Debounce: wait for SPACE to be released before starting.
    JSR tw_release_space

    ; Set data pointer to typewriter script.
    LDA #<tw_script
    STA temp_sprite_ptr
    LDA #>tw_script
    STA temp_sprite_ptr+1

    ; --- Main typewriter interpreter loop ---
.tw_loop
    LDY #0
    LDA (temp_sprite_ptr),Y    ; opcode
    CMP #TW_OP_END
    BEQ tw_jmp_finished
    CMP #TW_OP_LINE
    BEQ tw_do_line
    CMP #TW_OP_PAUSE
    BEQ tw_jmp_pause
    CMP #TW_OP_DH_LINE
    BEQ tw_jmp_dh_line
    ; Unknown opcode — skip 1 byte and hope for the best.
    JSR tw_advance_1
    JMP tw_loop

    ; Trampolines for out-of-range branches.
.tw_jmp_finished
    JMP tw_finished
.tw_jmp_dh_line
    JMP tw_do_dh_line
.tw_jmp_pause
    JMP tw_do_pause

    ; --- TW_OP_LINE: row, col, attr, len, text... ---
    ; Sets screen_ptr to row/col, writes attr byte, then types len chars.
.tw_do_line
    JSR tw_advance_1           ; skip opcode
    LDY #0
    LDA (temp_sprite_ptr),Y    ; row
    TAX
    LDA mode7_row_lo,X
    STA screen_ptr
    LDA mode7_row_hi,X
    STA screen_ptr+1
    INY
    LDA (temp_sprite_ptr),Y    ; col
    CLC
    ADC screen_ptr
    STA screen_ptr
    LDA #0
    ADC screen_ptr+1
    STA screen_ptr+1
    INY
    LDA (temp_sprite_ptr),Y    ; attr (colour code)
    LDY #0
    STA (screen_ptr),Y         ; write colour attribute
    INC screen_ptr
    BNE tw_line_no_carry1
    INC screen_ptr+1
.tw_line_no_carry1
    ; Advance past row, col, attr (3 bytes).
    JSR tw_advance_3
    ; Type the text, then return to main loop.
    JSR tw_type_text
    JMP tw_loop

    ; --- TW_OP_DH_LINE: row, col, attr, len, text... ---
    ; Double-height line: writes attr then &8D (double-height),
    ; then types text on BOTH this row and the next row.
.tw_do_dh_line
    JSR tw_advance_1           ; skip opcode
    LDY #0
    LDA (temp_sprite_ptr),Y    ; row
    STA temp                   ; save row for second pass
    TAX
    LDA mode7_row_lo,X
    STA screen_ptr
    LDA mode7_row_hi,X
    STA screen_ptr+1
    INY
    LDA (temp_sprite_ptr),Y    ; col
    STA temp_y                 ; save col
    CLC
    ADC screen_ptr
    STA screen_ptr
    LDA #0
    ADC screen_ptr+1
    STA screen_ptr+1
    INY
    LDA (temp_sprite_ptr),Y    ; attr (colour code)
    STA row_counter            ; save attr
    LDY #0
    STA (screen_ptr),Y         ; write colour attribute
    INY
    LDA #&8D                   ; double-height control code
    STA (screen_ptr),Y
    ; screen_ptr now points to attr byte; advance +2 to text start.
    LDA screen_ptr
    CLC
    ADC #2
    STA screen_ptr
    BNE tw_dh_no_carry1
    INC screen_ptr+1
.tw_dh_no_carry1

    ; Advance source past row, col, attr (3 bytes).
    JSR tw_advance_3

    ; Type the text on the top row.
    ; Save temp (row) and temp_y (col) — tw_type_text clobbers temp.
    LDA temp
    PHA
    LDA temp_y
    PHA
    JSR tw_type_text
    PLA
    STA temp_y
    PLA
    STA temp

    ; Now duplicate onto the bottom row (row+1) for double-height.
    ; Re-read the text from the data (temp_sprite_ptr was advanced past it,
    ; but we saved the length). Instead, copy directly from top row to bottom.
    ; Bottom row = top row + 40 bytes in MODE 7 RAM.
    ; We need to know the start and length. Easiest: just replay from the
    ; data pointer we saved. But we already advanced it...
    ;
    ; Simpler approach: before typing the top row, also pre-fill the bottom.
    ; Actually simplest: copy the entire top row to bottom row after typing.
    ;
    ; top_start = mode7_row[row] + col
    ; bottom_start = mode7_row[row+1] + col
    ; Copy 40-col bytes.
    LDA temp                   ; row
    CLC
    ADC #1
    TAX
    LDA mode7_row_lo,X
    STA mask_ptr
    LDA mode7_row_hi,X
    STA mask_ptr+1
    LDA temp_y                 ; col
    CLC
    ADC mask_ptr
    STA mask_ptr
    LDA #0
    ADC mask_ptr+1
    STA mask_ptr+1

    ; Source: top row start = mode7_row[row] + col.
    LDA temp
    TAX
    LDA mode7_row_lo,X
    STA screen_ptr
    LDA mode7_row_hi,X
    STA screen_ptr+1
    LDA temp_y
    CLC
    ADC screen_ptr
    STA screen_ptr
    LDA #0
    ADC screen_ptr+1
    STA screen_ptr+1

    ; Copy 40-col bytes.
    LDA #40
    SEC
    SBC temp_y
    TAX                        ; count
    LDY #0
.tw_dh_copy
    LDA (screen_ptr),Y
    STA (mask_ptr),Y
    INY
    DEX
    BNE tw_dh_copy

    JMP tw_loop

    ; --- TW_OP_PAUSE: frames ---
.tw_do_pause
    JSR tw_advance_1           ; skip opcode
    LDY #0
    LDA (temp_sprite_ptr),Y    ; frame count
    STA col_counter
    JSR tw_advance_1           ; skip frame count
.tw_pause_loop
    LDA col_counter
    BNE tw_pause_wait
    JMP tw_loop                ; done pausing
.tw_pause_wait
    JSR tw_wait_frame
    BCS tw_skip_all            ; SPACE pressed — skip
    DEC col_counter
    JMP tw_pause_loop

    ; --- Type text bytes one at a time ---
    ; Data at temp_sprite_ptr: len, chars...
    ; screen_ptr: current write position in MODE 7 RAM.
.tw_type_text
    LDY #0
    LDA (temp_sprite_ptr),Y   ; len
    STA col_counter
    JSR tw_advance_1           ; skip len byte
.tw_char_loop
    LDA col_counter
    BEQ tw_char_done
    LDY #0
    LDA (temp_sprite_ptr),Y   ; next char
    LDY #0
    STA (screen_ptr),Y        ; write to screen
    ; Advance screen position.
    INC screen_ptr
    BNE tw_char_no_carry
    INC screen_ptr+1
.tw_char_no_carry
    JSR tw_advance_1           ; advance data pointer
    DEC col_counter
    ; Tick sound.
    JSR tw_tick
    ; Wait a few frames per character.
    LDA #TW_CHAR_DELAY
    STA temp
.tw_char_wait
    JSR tw_wait_frame
    BCS tw_char_skip           ; SPACE pressed
    DEC temp
    BNE tw_char_wait
    JMP tw_char_loop
.tw_char_skip
    ; SPACE pressed during text — dump remaining chars instantly.
.tw_char_dump
    LDA col_counter
    BEQ tw_char_done
    LDY #0
    LDA (temp_sprite_ptr),Y
    LDY #0
    STA (screen_ptr),Y
    INC screen_ptr
    BNE tw_dump_no_carry
    INC screen_ptr+1
.tw_dump_no_carry
    JSR tw_advance_1
    DEC col_counter
    JMP tw_char_dump
.tw_char_done
    RTS

    ; --- Skip: dump all remaining script instantly ---
.tw_skip_all
    LDY #0
    LDA (temp_sprite_ptr),Y
    CMP #TW_OP_END
    BNE tw_sa_not_end
    JMP tw_finished
.tw_sa_not_end

    CMP #TW_OP_LINE
    BNE tw_sa_not_line
    JMP tw_skip_line
.tw_sa_not_line
    CMP #TW_OP_DH_LINE
    BNE tw_sa_not_dh
    JMP tw_skip_dh_line
.tw_sa_not_dh
    CMP #TW_OP_PAUSE
    BEQ tw_skip_pause
    ; Unknown — skip 1.
    JSR tw_advance_1
    JMP tw_skip_all

.tw_skip_pause
    ; Skip opcode + 1 byte.
    JSR tw_advance_1
    JSR tw_advance_1
    JMP tw_skip_all

.tw_skip_line
    ; LINE: opcode, row, col, attr, len, text...
    JSR tw_advance_1           ; opcode
    LDY #0
    LDA (temp_sprite_ptr),Y   ; row
    TAX
    LDA mode7_row_lo,X
    STA screen_ptr
    LDA mode7_row_hi,X
    STA screen_ptr+1
    INY
    LDA (temp_sprite_ptr),Y   ; col
    CLC
    ADC screen_ptr
    STA screen_ptr
    LDA #0
    ADC screen_ptr+1
    STA screen_ptr+1
    INY
    LDA (temp_sprite_ptr),Y   ; attr
    LDY #0
    STA (screen_ptr),Y
    INC screen_ptr
    BNE tw_sl_nc
    INC screen_ptr+1
.tw_sl_nc
    JSR tw_advance_3           ; row, col, attr
    ; Dump text.
    LDY #0
    LDA (temp_sprite_ptr),Y   ; len
    STA col_counter
    JSR tw_advance_1
.tw_sl_dump
    LDA col_counter
    BEQ tw_skip_all
    LDY #0
    LDA (temp_sprite_ptr),Y
    LDY #0
    STA (screen_ptr),Y
    INC screen_ptr
    BNE tw_sl_dnc
    INC screen_ptr+1
.tw_sl_dnc
    JSR tw_advance_1
    DEC col_counter
    JMP tw_sl_dump

.tw_skip_dh_line
    ; DH_LINE: opcode, row, col, attr, len, text...
    ; Same as LINE but also copy to row+1.
    JSR tw_advance_1           ; opcode
    LDY #0
    LDA (temp_sprite_ptr),Y   ; row
    STA temp                   ; save row
    TAX
    LDA mode7_row_lo,X
    STA screen_ptr
    LDA mode7_row_hi,X
    STA screen_ptr+1
    INY
    LDA (temp_sprite_ptr),Y   ; col
    STA temp_y                 ; save col
    CLC
    ADC screen_ptr
    STA screen_ptr
    LDA #0
    ADC screen_ptr+1
    STA screen_ptr+1
    INY
    LDA (temp_sprite_ptr),Y   ; attr
    STA row_counter            ; save attr
    LDY #0
    STA (screen_ptr),Y
    INY
    LDA #&8D
    STA (screen_ptr),Y
    LDA screen_ptr
    CLC
    ADC #2
    STA screen_ptr
    BNE tw_sdh_nc1
    INC screen_ptr+1
.tw_sdh_nc1
    JSR tw_advance_3           ; row, col, attr
    ; Dump text.
    LDY #0
    LDA (temp_sprite_ptr),Y   ; len
    STA col_counter
    JSR tw_advance_1
.tw_sdh_dump
    LDA col_counter
    BEQ tw_sdh_copy_row
    LDY #0
    LDA (temp_sprite_ptr),Y
    LDY #0
    STA (screen_ptr),Y
    INC screen_ptr
    BNE tw_sdh_dnc
    INC screen_ptr+1
.tw_sdh_dnc
    JSR tw_advance_1
    DEC col_counter
    JMP tw_sdh_dump
.tw_sdh_copy_row
    ; Copy top row to bottom row (row+1).
    LDA temp
    CLC
    ADC #1
    TAX
    LDA mode7_row_lo,X
    STA mask_ptr
    LDA mode7_row_hi,X
    STA mask_ptr+1
    LDA temp_y
    CLC
    ADC mask_ptr
    STA mask_ptr
    LDA #0
    ADC mask_ptr+1
    STA mask_ptr+1
    ; Source: top row.
    LDA temp
    TAX
    LDA mode7_row_lo,X
    STA screen_ptr
    LDA mode7_row_hi,X
    STA screen_ptr+1
    LDA temp_y
    CLC
    ADC screen_ptr
    STA screen_ptr
    LDA #0
    ADC screen_ptr+1
    STA screen_ptr+1
    LDA #40
    SEC
    SBC temp_y
    TAX
    LDY #0
.tw_sdh_cpy
    LDA (screen_ptr),Y
    STA (mask_ptr),Y
    INY
    DEX
    BNE tw_sdh_cpy
    JMP tw_skip_all

.tw_finished
    ; Template already has "Press SPACE to continue" on row 23.
    JSR wait_space
    JSR restore_mode5
    RTS


; --- Typewriter helpers ---

; Advance temp_sprite_ptr by 1.
.tw_advance_1
    INC temp_sprite_ptr
    BNE tw_a1_done
    INC temp_sprite_ptr+1
.tw_a1_done
    RTS

; Advance temp_sprite_ptr by 3.
.tw_advance_3
    LDA temp_sprite_ptr
    CLC
    ADC #3
    STA temp_sprite_ptr
    BCC tw_a3_done
    INC temp_sprite_ptr+1
.tw_a3_done
    RTS

; Wait one frame (vsync). Returns C=1 if SPACE pressed, C=0 otherwise.
.tw_wait_frame
    JSR wait_vsync
    ; Check SPACE: INKEY-99.
    LDA #129
    LDX #(256-99)
    LDY #&FF
    JSR OSBYTE
    CPX #&FF
    BNE tw_wf_no_space
    SEC
    RTS
.tw_wf_no_space
    CLC
    RTS

; Wait for SPACE release (debounce helper).
.tw_release_space
    LDA #129
    LDX #(256-99)
    LDY #&FF
    JSR OSBYTE
    CPX #&FF
    BEQ tw_release_space
    RTS

; Play a short tick sound via OSWORD &07.
; Uses a brief high-pitched blip on channel 0.
.tw_tick
    LDA #7
    LDX #<tw_sound_blk
    LDY #>tw_sound_blk
    JSR OSWORD
    RTS

; OSWORD &07 SOUND block: channel, amplitude, pitch, duration.
; channel=0 (foreground), amplitude=-12 (quiet), pitch=200 (high blip), duration=1.
.tw_sound_blk
    EQUW &0000                 ; channel 0
    EQUW &FFF4                 ; amplitude -12
    EQUW 200                   ; pitch
    EQUW 1                     ; duration (1/20th sec)


; --- Typewriter opcodes ---
TW_OP_END     = 0
TW_OP_LINE    = 1              ; row, col, attr, len, text...
TW_OP_PAUSE   = 2              ; frames
TW_OP_DH_LINE = 3              ; row, col, attr, len, text... (double-height)

; Timing.
TW_CHAR_DELAY = 3              ; frames per character (~17 chars/sec at 50Hz)


; --- Typewriter script data ---
.tw_script
    ; "TESTING COMPLETE" — double-height header, centred, red.
    EQUB TW_OP_DH_LINE, 11, 11, &81
    EQUB 16
    EQUS "TESTING COMPLETE"

    EQUB TW_OP_PAUSE, 50       ; dramatic pause

    ; GLaDOS monologue in blue.
    EQUB TW_OP_LINE, 13, 4, &84
    EQUB 16
    EQUS "Congratulations."

    EQUB TW_OP_PAUSE, 40

    EQUB TW_OP_LINE, 15, 4, &84
    EQUB 32
    EQUS "The Enrichment Center is pleased"

    EQUB TW_OP_LINE, 16, 4, &84
    EQUB 33
    EQUS "to inform you that testing is now"

    EQUB TW_OP_LINE, 17, 4, &84
    EQUB 9
    EQUS "complete."

    EQUB TW_OP_PAUSE, 40

    EQUB TW_OP_LINE, 19, 4, &84
    EQUB 34
    EQUS "Cake and grief counselling will be"

    EQUB TW_OP_LINE, 20, 4, &84
    EQUB 34
    EQUS "available at the conclusion of the"

    EQUB TW_OP_LINE, 21, 4, &84
    EQUB 26
    EQUS "test. Which was a triumph."

    EQUB TW_OP_PAUSE, 60

    ; "The cake is a lie." in red, for emphasis.
    EQUB TW_OP_LINE, 22, 4, &81
    EQUB 18
    EQUS "The cake is a lie."

    EQUB TW_OP_END

; Restart prompt (flashing white).
.tw_prompt
    EQUB 23, 6, 24
    EQUB &88, &87
    EQUS "Press SPACE to restart"
    EQUB &FF


; --- enter_mode7 ---
; Save MOS VDU workspace, then VDU 22,7 for clean MODE 7 setup.
.enter_mode7
    ; Save MOS VDU workspace (&0300-&036F, 112 bytes).
    ; VDU 22,7 overwrites these — we restore them in restore_mode5.
    LDX #111
.em7_save
    LDA &0300,X
    STA mos_vdu_save,X
    DEX
    BPL em7_save

    ; VDU 22,7 — programs Video ULA, CRTC, clears &7C00, sets MOS state.
    LDA #22 : JSR OSWRCH
    LDA #7  : JSR OSWRCH

    ; VDU 23,1,0;0;0;0; — disable text cursor.
    LDA #23 : JSR OSWRCH
    LDA #1  : JSR OSWRCH
    LDA #0
    JSR OSWRCH : JSR OSWRCH : JSR OSWRCH : JSR OSWRCH
    JSR OSWRCH : JSR OSWRCH : JSR OSWRCH : JSR OSWRCH

    ; Force ACCCON to a known-good state for MODE 7:
    ;   D=0 (CRTC reads main RAM), X=0 (CPU reads/writes main RAM).
    ; During gameplay D=1 and blitters toggle X; OSWRCH calls above may
    ; restore shadow bits from the MOS VDU workspace we saved, so we
    ; clear them as the very last thing before returning.
    ; .start re-enables D=1 after every card/completion screen.
    LDA ACCCON
    AND #&FA              ; clear D (bit 0) and X (bit 2)
    STA ACCCON
    RTS


; --- restore_mode5 ---
; Restore MODE 5 hardware, then put MOS VDU workspace back to MODE 5 state.
; Caller (.start) handles cursor, palette, CRTC R1/R2 override, and shadow init.
.restore_mode5
    ; Video ULA: MODE 5 = 4-colour, low-freq clock.
    ; OSBYTE 154 updates both &FE20 and MOS shadow copy.
    LDA #154
    LDX #&C4
    JSR OSBYTE

    ; Program CRTC registers for MODE 5.
    LDX #0
.rm5_loop
    LDA mode5_crtc_table,X
    BMI rm5_done
    STA CRTC_ADDR
    LDA mode5_crtc_table+1,X
    STA CRTC_DATA
    INX : INX
    BNE rm5_loop
.rm5_done

    ; Restore MOS VDU workspace — undoes VDU 22,7's side-effects.
    ; VDU calls in .start (set_palette, disable_cursor) now work correctly.
    LDX #111
.rm5_rest
    LDA mos_vdu_save,X
    STA &0300,X
    DEX
    BPL rm5_rest
    RTS

; CRTC register/value pairs for MODE 5 (from AUG Appendix F p.472).
.mode5_crtc_table
    EQUB  0, &3F            ; R0:  horizontal total = 63
    EQUB  1, &28            ; R1:  characters per line = 40
    EQUB  2, &31            ; R2:  horizontal sync position = 49
    EQUB  3, &24            ; R3:  sync widths: hsync=4, vsync=2
    EQUB  4, &26            ; R4:  vertical total = 38
    EQUB  5, &00            ; R5:  vertical total adjust = 0
    EQUB  6, &20            ; R6:  vertical displayed = 32
    EQUB  7, &22            ; R7:  vertical sync position = 34
    EQUB  8, &01            ; R8:  interlace=0, display delay=0, cursor delay=0
    EQUB  9, &07            ; R9:  scan lines per character = 7
    EQUB 10, &20            ; R10: cursor off (bits 5-6 = 01)
    EQUB 12, &0B            ; R12: screen start high = &0B (&5800/8 = &0B00)
    EQUB 13, &00            ; R13: screen start low = &00
    EQUB &FF                ; sentinel

; Buffer for saving MOS VDU workspace (&0300-&036F).
.mos_vdu_save
    SKIP 112


; --- write_mode7_screen ---
; Write a screen template directly into MODE 7 RAM at &7C00.
; Input: X/Y = pointer to screen data (lo/hi).
; Format: sequence of (row, col, len, data...) records, terminated by &FF.
;   row: 0-24 (y position)
;   col: 0-39 (x position)
;   len: number of bytes to copy (1-40)
;   data: len bytes of MODE 7 character/attribute data
.write_mode7_screen
    STX temp_sprite_ptr
    STY temp_sprite_ptr+1

.wm7_record
    LDY #0
    LDA (temp_sprite_ptr),Y    ; row
    BMI wm7_done               ; &FF = end sentinel

    ; Compute destination: &7C00 + row*40 + col.
    ; row*40 = row*32 + row*8.
    TAX
    LDA mode7_row_lo,X
    STA screen_ptr
    LDA mode7_row_hi,X
    STA screen_ptr+1

    INY
    LDA (temp_sprite_ptr),Y    ; col
    CLC
    ADC screen_ptr
    STA screen_ptr
    LDA #0
    ADC screen_ptr+1
    STA screen_ptr+1

    INY
    LDA (temp_sprite_ptr),Y    ; len
    TAX                         ; X = byte count

    ; Advance source past header (3 bytes).
    LDA temp_sprite_ptr
    CLC
    ADC #3
    STA temp_sprite_ptr
    LDA temp_sprite_ptr+1
    ADC #0
    STA temp_sprite_ptr+1

    ; Copy X bytes from source to screen.
    LDY #0
.wm7_copy
    LDA (temp_sprite_ptr),Y
    STA (screen_ptr),Y
    INY
    DEX
    BNE wm7_copy

    ; Advance source past data.
    TYA
    CLC
    ADC temp_sprite_ptr
    STA temp_sprite_ptr
    LDA temp_sprite_ptr+1
    ADC #0
    STA temp_sprite_ptr+1

    JMP wm7_record

.wm7_done
    RTS


; --- wait_space ---
; Wait for SPACE release (debounce), then poll until SPACE is pressed.
; INKEY-99 = SPACE key.
.wait_space
.ws_release
    LDA #129
    LDX #(256-99)      ; INKEY-99 = SPACE
    LDY #&FF
    JSR OSBYTE
    CPX #&FF
    BEQ ws_release      ; still held — keep waiting
.ws_loop
    LDA #129
    LDX #(256-99)      ; INKEY-99 = SPACE
    LDY #&FF
    JSR OSBYTE
    CPX #&FF
    BNE ws_loop         ; X=&FF means key pressed
    RTS


; --- draw_card_line ---
; Read one length-prefixed string from (tilemap_ptr), centre it on the
; character row whose base address is in temp_mask_ptr, and draw it.
; Advances tilemap_ptr past the string (length byte + data bytes).
;
; Input:
;   tilemap_ptr = pointer to [len] [char0] [char1] ... in main RAM
;   temp_mask_ptr = base screen address of the character row
;
; If len=0, does nothing (skips empty line).
; Clobbers: A, X, Y, temp, screen_ptr, sprite_ptr
;
DCL_LEN = CHAR_BUF+15          ; scratch byte for string length in draw_card_line

.draw_card_line
    ; Read string length.
    LDY #0
    LDA (tilemap_ptr),Y
    BEQ dcl_empty               ; len=0 — skip

    ; Save length (must not clobber temp_y which holds fg colour).
    STA DCL_LEN

    ; sprite_ptr = tilemap_ptr + 1 (start of string data).
    CLC
    LDA tilemap_ptr
    ADC #1
    STA sprite_ptr
    LDA tilemap_ptr+1
    ADC #0
    STA sprite_ptr+1

    ; Set character count for draw_half_text.
    LDA DCL_LEN
    STA col_counter

    ; Compute centred screen address:
    ;   offset = ((32 - len) / 2) * 8  bytes from row base.
    ; (32 columns across the 128px screen.)
    LDA #32
    SEC
    SBC DCL_LEN                 ; 32 - len
    LSR A                       ; / 2 = column offset
    ; Multiply by 8: shift left 3.
    ASL A
    ASL A
    ASL A                       ; column offset * 8 = byte offset

    ; screen_ptr = temp_mask_ptr + byte offset.
    CLC
    ADC temp_mask_ptr
    STA screen_ptr
    LDA temp_mask_ptr+1
    ADC #0
    STA screen_ptr+1

    ; Draw the string.
    JSR draw_half_text

    ; Advance tilemap_ptr past length byte + string data.
    CLC
    LDA tilemap_ptr
    ADC DCL_LEN
    STA tilemap_ptr
    LDA tilemap_ptr+1
    ADC #0
    STA tilemap_ptr+1
    ; +1 for the length byte itself.
    INC tilemap_ptr
    BNE dcl_done
    INC tilemap_ptr+1
    JMP dcl_done

.dcl_empty
    ; Advance tilemap_ptr past the zero length byte.
    INC tilemap_ptr
    BNE dcl_done
    INC tilemap_ptr+1
.dcl_done
    RTS


; --- draw_half_text ---
; Render a counted string in half-width (4px) font to shadow screen RAM.
; Uses MOS ROM font via OSWORD 10, sampling bits 6,4,2,0 for each row.
;
; Foreground colour set by temp_y; background set by row_counter:
;   temp_y      = &00 for colour 0 (black/blue), &0F for colour 1 (red)
;   row_counter = &F0 for colour 2 (cyan bg), &FF for colour 3 (yellow bg)
;
; Input:
;   sprite_ptr (&73-&74) = pointer to string data
;   screen_ptr (&71-&72) = shadow screen RAM address (start of character column)
;   col_counter (&77)    = number of characters to draw
;   row_counter (&76)    = background byte pattern
;   temp_y (&75)         = foreground byte pattern (&00=colour 0, &0F=colour 1)
;
; Each character occupies 8 consecutive bytes in screen RAM (one 8-row stripe).
; Advances screen_ptr by 8 for each character drawn.
;
; Clobbers: A, X, Y, temp, screen_ptr, sprite_ptr, col_counter
;
; OSWORD 10 parameter block is placed at PACK_OSFILE_BLK (9 bytes needed,
; 18 available — safe since OSFILE load is already complete).
;
OSWORD10_BLK = &09C0               ; reuse PACK_OSFILE_BLK area (18 bytes available)

.draw_half_text

.dht_next_char
    ; Check remaining count.
    LDA col_counter
    BEQ dht_done                ; no more characters — finished

    ; Fetch next character from string.
    LDY #0
    LDA (sprite_ptr),Y

    ; Set up OSWORD 10 parameter block.
    STA OSWORD10_BLK            ; byte 0 = ASCII character code

    ; Call OSWORD 10: read character definition.
    LDA #10
    LDX #<OSWORD10_BLK
    LDY #>OSWORD10_BLK
    JSR OSWORD

    ; Convert 8 rows of 8-pixel 1bpp data to 8 MODE 5 bytes.
    ; ROM data is in OSWORD10_BLK+1..+8 (row 0 at +1).
    ; Output to CHAR_BUF (8 bytes at &09C9).
    LDY #0                      ; Y = row index (0..7)
.dht_row
    LDX OSWORD10_BLK+1,Y        ; X = 1bpp row data (bit 7 = leftmost)

    ; Sample bits 6,4,2,0 into low nybble of A.
    ; bit 6 -> bit 3, bit 4 -> bit 2, bit 2 -> bit 1, bit 0 -> bit 0
    LDA #0
    TXA
    AND #&40                    ; isolate bit 6
    BEQ dht_no_b6
    LDA #&08                    ; -> bit 3
.dht_no_b6
    STA temp

    TXA
    AND #&10                    ; isolate bit 4
    BEQ dht_no_b4
    LDA #&04                    ; -> bit 2
    ORA temp
    STA temp
.dht_no_b4

    TXA
    AND #&04                    ; isolate bit 2
    BEQ dht_no_b2
    LDA #&02                    ; -> bit 1
    ORA temp
    STA temp
.dht_no_b2

    TXA
    AND #&01                    ; isolate bit 0
    ORA temp                    ; -> bit 0

    ; A now has sampled 4 bits in lower nybble (bits 3-0).
    ; 1=fg pixel, 0=bg pixel.
    ; byte = (bg_mask_replicated & row_counter) | (fg_mask & temp_y)
    STA temp                    ; fg mask in bits 3-0
    EOR #&0F                    ; bg mask
    PHA                         ; save bg mask
    ASL A
    ASL A
    ASL A
    ASL A                       ; bg mask in bits 7-4
    STA CHAR_BUF,Y             ; stash upper nybble temporarily
    PLA                         ; bg mask in bits 3-0
    ORA CHAR_BUF,Y             ; replicate into both nybbles
    AND row_counter             ; apply bg colour
    STA CHAR_BUF,Y             ; stash bg contribution
    LDA temp                    ; fg mask
    AND temp_y                  ; apply fg colour
    ORA CHAR_BUF,Y             ; combine bg + fg

    ; Store into character buffer (main RAM, below &3000).
    STA CHAR_BUF,Y
    INY
    CPY #8
    BNE dht_row

    ; Copy 8-byte character from CHAR_BUF to shadow screen RAM.
    ; write_char_to_shadow lives below &3000 and handles ACCCON X toggling.
    JSR write_char_to_shadow

    ; Advance screen_ptr to next character column (+8 bytes).
    CLC
    LDA screen_ptr
    ADC #8
    STA screen_ptr
    LDA screen_ptr+1
    ADC #0
    STA screen_ptr+1

    ; Advance string pointer and decrement count.
    INC sprite_ptr
    BNE dht_no_carry
    INC sprite_ptr+1
.dht_no_carry
    DEC col_counter
    JMP dht_next_char

.dht_done
    RTS


; --- draw_full_text ---
; Render a counted string in full-width (8px) MOS ROM font to shadow screen RAM.
; Uses OSWORD 10, full 8 pixels per character = 2 MODE 5 bytes per row.
;
; Foreground = colour 1 (red), background from row_counter.
;
; Input:
;   sprite_ptr (&73-&74) = pointer to string data
;   screen_ptr (&71-&72) = shadow screen RAM address (start of character column)
;   col_counter (&77)    = number of characters to draw
;   row_counter (&76)    = background byte pattern (&F0=cyan, &FF=yellow)
;
; Each character occupies 16 consecutive bytes (2 columns × 8 rows).
; Advances screen_ptr by 16 for each character drawn.
;
; Clobbers: A, X, Y, temp, screen_ptr, sprite_ptr, col_counter

.draw_full_text

.dft_next_char
    LDA col_counter
    BEQ dft_done

    ; Fetch next character from string.
    LDY #0
    LDA (sprite_ptr),Y

    ; Set up OSWORD 10 parameter block.
    STA OSWORD10_BLK

    ; Call OSWORD 10: read character definition.
    LDA #10
    LDX #<OSWORD10_BLK
    LDY #>OSWORD10_BLK
    JSR OSWORD

    ; --- Left half: bits 7,6,5,4 of each row ---
    LDY #0
.dft_left_row
    LDA OSWORD10_BLK+1,Y
    ; Shift right 4 to get upper 4 bits into lower nybble.
    LSR A
    LSR A
    LSR A
    LSR A
    ; A = 4 pixel bits (1=fg, 0=bg) in bits 3-0.
    ; Colour 1 (red) = %01: upper nybble bit=0, lower nybble bit=1.
    ; byte = (bg_mask_replicated & row_counter) | fg_mask
    STA temp                    ; fg_mask in bits 3-0
    EOR #&0F                    ; bg_mask
    STA CHAR_BUF+8,Y           ; stash bg_mask temporarily
    ASL A
    ASL A
    ASL A
    ASL A
    ORA CHAR_BUF+8,Y           ; replicate bg into both nybbles
    AND row_counter             ; apply bg colour
    ORA temp                    ; add fg (colour 1: only lower nybble)
    STA CHAR_BUF,Y
    INY
    CPY #8
    BNE dft_left_row

    ; Write left column to shadow screen RAM.
    JSR write_char_to_shadow

    ; Advance screen_ptr to right column (+8 bytes).
    CLC
    LDA screen_ptr
    ADC #8
    STA screen_ptr
    LDA screen_ptr+1
    ADC #0
    STA screen_ptr+1

    ; --- Right half: bits 3,2,1,0 of each row ---
    LDY #0
.dft_right_row
    LDA OSWORD10_BLK+1,Y
    AND #&0F                    ; lower 4 bits already in place
    STA temp                    ; fg_mask
    EOR #&0F                    ; bg_mask
    STA CHAR_BUF+8,Y           ; stash
    ASL A
    ASL A
    ASL A
    ASL A
    ORA CHAR_BUF+8,Y
    AND row_counter
    ORA temp
    STA CHAR_BUF,Y
    INY
    CPY #8
    BNE dft_right_row

    ; Write right column to shadow screen RAM.
    JSR write_char_to_shadow

    ; Advance screen_ptr to next character (+8 bytes for right col already done).
    CLC
    LDA screen_ptr
    ADC #8
    STA screen_ptr
    LDA screen_ptr+1
    ADC #0
    STA screen_ptr+1

    ; Advance string pointer and decrement count.
    INC sprite_ptr
    BNE dft_no_carry
    INC sprite_ptr+1
.dft_no_carry
    DEC col_counter
    JMP dft_next_char

.dft_done
    RTS


; --- draw_full_card_line ---
; Like draw_card_line but uses draw_full_text (full-width, red).
; Full-width chars are 2 columns each, so 16 chars fit in 32 columns.
;
; Input:
;   tilemap_ptr = pointer to [len] [char0] [char1] ... in main RAM
;   temp_mask_ptr = base screen address of the character row
;   row_counter = background byte
;
; Advances tilemap_ptr past the string.
; Clobbers: A, X, Y, temp, screen_ptr, sprite_ptr, col_counter
;
.draw_full_card_line
    ; Read string length.
    LDY #0
    LDA (tilemap_ptr),Y
    BEQ dfcl_empty

    STA temp_y

    ; sprite_ptr = tilemap_ptr + 1.
    CLC
    LDA tilemap_ptr
    ADC #1
    STA sprite_ptr
    LDA tilemap_ptr+1
    ADC #0
    STA sprite_ptr+1

    ; Set character count.
    LDA temp_y
    STA col_counter

    ; Compute centred screen address.
    ; Full-width: each char = 2 columns, so max 16 chars in 32 cols.
    ; offset = ((16 - len) / 2) * 16  bytes from row base.
    LDA #16
    SEC
    SBC temp_y                  ; 16 - len
    LSR A                       ; / 2 = column pair offset
    ; Multiply by 16: shift left 4.
    ASL A
    ASL A
    ASL A
    ASL A                       ; byte offset

    CLC
    ADC temp_mask_ptr
    STA screen_ptr
    LDA temp_mask_ptr+1
    ADC #0
    STA screen_ptr+1

    JSR draw_full_text

    ; Advance tilemap_ptr past length byte + string data.
    CLC
    LDA tilemap_ptr
    ADC temp_y
    STA tilemap_ptr
    LDA tilemap_ptr+1
    ADC #0
    STA tilemap_ptr+1
    INC tilemap_ptr
    BNE dfcl_done
    INC tilemap_ptr+1
    JMP dfcl_done

.dfcl_empty
    INC tilemap_ptr
    BNE dfcl_done
    INC tilemap_ptr+1
.dfcl_done
    RTS


; --- Lookup table: MODE 7 row start addresses ---
; &7C00 + row*40 for rows 0-24.
.mode7_row_lo
    EQUB <(&7C00 +  0*40)
    EQUB <(&7C00 +  1*40)
    EQUB <(&7C00 +  2*40)
    EQUB <(&7C00 +  3*40)
    EQUB <(&7C00 +  4*40)
    EQUB <(&7C00 +  5*40)
    EQUB <(&7C00 +  6*40)
    EQUB <(&7C00 +  7*40)
    EQUB <(&7C00 +  8*40)
    EQUB <(&7C00 +  9*40)
    EQUB <(&7C00 + 10*40)
    EQUB <(&7C00 + 11*40)
    EQUB <(&7C00 + 12*40)
    EQUB <(&7C00 + 13*40)
    EQUB <(&7C00 + 14*40)
    EQUB <(&7C00 + 15*40)
    EQUB <(&7C00 + 16*40)
    EQUB <(&7C00 + 17*40)
    EQUB <(&7C00 + 18*40)
    EQUB <(&7C00 + 19*40)
    EQUB <(&7C00 + 20*40)
    EQUB <(&7C00 + 21*40)
    EQUB <(&7C00 + 22*40)
    EQUB <(&7C00 + 23*40)
    EQUB <(&7C00 + 24*40)
.mode7_row_hi
    EQUB >(&7C00 +  0*40)
    EQUB >(&7C00 +  1*40)
    EQUB >(&7C00 +  2*40)
    EQUB >(&7C00 +  3*40)
    EQUB >(&7C00 +  4*40)
    EQUB >(&7C00 +  5*40)
    EQUB >(&7C00 +  6*40)
    EQUB >(&7C00 +  7*40)
    EQUB >(&7C00 +  8*40)
    EQUB >(&7C00 +  9*40)
    EQUB >(&7C00 + 10*40)
    EQUB >(&7C00 + 11*40)
    EQUB >(&7C00 + 12*40)
    EQUB >(&7C00 + 13*40)
    EQUB >(&7C00 + 14*40)
    EQUB >(&7C00 + 15*40)
    EQUB >(&7C00 + 16*40)
    EQUB >(&7C00 + 17*40)
    EQUB >(&7C00 + 18*40)
    EQUB >(&7C00 + 19*40)
    EQUB >(&7C00 + 20*40)
    EQUB >(&7C00 + 21*40)
    EQUB >(&7C00 + 22*40)
    EQUB >(&7C00 + 23*40)
    EQUB >(&7C00 + 24*40)


; =====================================================================
; Screen data — packed records: (row, col, len, data...), &FF sentinel.
;
; MODE 7 control codes:
;   134 = cyan text,  135 = white text,  131 = yellow text
;   136 = flash on,   141 = double-height
; =====================================================================

; OSFILE control block for loading STRTSCR to &7C00.
; exec low byte = 0 => use supplied load address.
.osfile_blk_strtscr
    EQUW fname_strtscr
    EQUB &00,&7C,0,0        ; load &7C00
    EQUB 0,0,0,0            ; exec low=0 => use supplied load
    EQUB 0,0,0,0            ; start/len (ignored)
    EQUB 0,0,0,0            ; end/attrs (ignored)

.fname_strtscr
    EQUS "STRTSCR",13

; OSFILE control block for loading TEMPLTE to &7C00.
.osfile_blk_templte
    EQUW fname_templte
    EQUB &00,&7C,0,0        ; load &7C00
    EQUB 0,0,0,0            ; exec low=0 => use supplied load
    EQUB 0,0,0,0            ; start/len (ignored)
    EQUB 0,0,0,0            ; end/attrs (ignored)

.fname_templte
    EQUS "TEMPLTE",13


; Per-level card overlay data is now embedded in binary level packs
; and pointed to by level_card_ptr (set by load_level in tilemap.asm).
