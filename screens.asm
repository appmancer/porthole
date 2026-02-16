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
; Display level title card on the Aperture template. Blocks until SPACE pressed.
; Input: current_level (0-indexed) in ZP.
.show_level_card
    JSR enter_mode7

    ; Load raw template screen into MODE 7 RAM at &7C00.
    LDA #&FF
    LDX #<osfile_blk_templte
    LDY #>osfile_blk_templte
    JSR OSFILE

    ; Use level card overlay pointer set by load_level parser.
    ; Points into the staging buffer (populated from the binary pack).
    LDX level_card_ptr
    LDY level_card_ptr+1
    JSR write_mode7_screen

    ; Patch level number placeholder with actual digits.
    ; current_level is 0-indexed; display as 1-indexed.
    LDA current_level
    CLC
    ADC #1
    LDX #0
.slc_tens
    CMP #10
    BCC slc_tens_done
    SBC #10
    INX
    JMP slc_tens
.slc_tens_done
    PHA

    ; Write tens digit into both double-height rows.
    TXA
    CLC
    ADC #ASC("0")
    STA &7C00 + 12*40 + 17     ; row 12, col 17 (top half)
    STA &7C00 + 13*40 + 17     ; row 13, col 17 (bottom half)

    ; Write units digit into both double-height rows.
    PLA
    CLC
    ADC #ASC("0")
    STA &7C00 + 12*40 + 18     ; row 12, col 18
    STA &7C00 + 13*40 + 18     ; row 13, col 18

    JSR wait_space
    JSR restore_mode5
    RTS


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
    JSR OSFILE

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
