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


; --- show_instructions ---
; Display the instruction/story screen. Blocks until SPACE pressed.
.show_instructions
    JSR enter_mode7

    ; Copy instruction screen data directly into MODE 7 screen RAM.
    LDX #<str_instructions
    LDY #>str_instructions
    JSR write_mode7_screen

    JSR wait_space
    JSR restore_mode5
    RTS


; --- show_level_card ---
; Display "Test Chamber XX" title card. Blocks until SPACE pressed.
; Input: current_level (0-indexed) in ZP.
.show_level_card
    JSR enter_mode7

    ; Copy level card data directly into MODE 7 screen RAM.
    LDX #<str_level_card
    LDY #>str_level_card
    JSR write_mode7_screen

    ; Overwrite the level number placeholder bytes with actual digits.
    ; The number appears twice (double-height top + bottom row).
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
    ; X = tens digit, A = units digit.
    PHA

    ; Write tens digit into both rows.
    TXA
    CLC
    ADC #ASC("0")
    STA &7C00 + 12*40 + 14     ; row 12, col 14 (top half)
    STA &7C00 + 13*40 + 14     ; row 13, col 14 (bottom half)

    ; Write units digit into both rows.
    PLA
    CLC
    ADC #ASC("0")
    STA &7C00 + 12*40 + 15     ; row 12, col 15
    STA &7C00 + 13*40 + 15     ; row 13, col 15

    JSR wait_space
    JSR restore_mode5
    RTS


; --- show_complete_screen ---
; Display "TESTING COMPLETE" screen. Blocks until SPACE pressed.
.show_complete_screen
    JSR enter_mode7

    LDX #<str_complete
    LDY #>str_complete
    JSR write_mode7_screen

    JSR wait_space
    JSR restore_mode5
    RTS


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
; Poll until SPACE is pressed using OSBYTE 129 (INKEY).
; INKEY-99 = SPACE key.
.wait_space
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

.str_instructions
    ; Title: "P O R T H O L E" in cyan.
    EQUB 3, 5, 16
    EQUB 134
    EQUS "P O R T H O L E"

    ; Story blurb in white.
    EQUB 6, 3, 25
    EQUB 135
    EQUS "Aperture Science reminds"
    EQUB 7, 3, 24
    EQUB 135
    EQUS "you that the Enrichment"
    EQUB 8, 3, 26
    EQUB 135
    EQUS "Center is not responsible"
    EQUB 9, 3, 24
    EQUB 135
    EQUS "for any consequences of"
    EQUB 10, 3, 9
    EQUB 135
    EQUS "testing."

    ; Controls in yellow.
    EQUB 13, 3, 19
    EQUB 131
    EQUS "LEFT / RIGHT  Move"
    EQUB 14, 3, 19
    EQUB 131
    EQUS "RETURN        Jump"
    EQUB 15, 3, 26
    EQUB 131
    EQUS "R             Aim reticle"
    EQUB 16, 3, 27
    EQUB 131
    EQUS "A / S         Fire portals"
    EQUB 17, 3, 27
    EQUB 131
    EQUS "SPACE         Pick up/Drop"
    EQUB 18, 3, 22
    EQUB 131
    EQUS "ESCAPE        Restart"

    ; Flashing prompt.
    EQUB 22, 5, 22
    EQUB 136, 135
    EQUS "Press SPACE to begin"

    EQUB &FF            ; end sentinel


; Level card: double-height "TEST CHAMBER" + number placeholder.
; Number digits are patched in by show_level_card after this is written.
.str_level_card
    ; Top half of "TEST CHAMBER"
    EQUB 8, 6, 14
    EQUB 141, 135
    EQUS "TEST CHAMBER"

    ; Bottom half of "TEST CHAMBER"
    EQUB 9, 6, 14
    EQUB 141, 135
    EQUS "TEST CHAMBER"

    ; Top half of level number (placeholder "00")
    EQUB 12, 13, 4
    EQUB 141, 131
    EQUS "00"                   ; patched by show_level_card

    ; Bottom half of level number (placeholder "00")
    EQUB 13, 13, 4
    EQUB 141, 131
    EQUS "00"                   ; patched by show_level_card

    ; Flashing prompt.
    EQUB 20, 4, 25
    EQUB 136, 135
    EQUS "Press SPACE to continue"

    EQUB &FF            ; end sentinel


; Completion screen: double-height "TESTING COMPLETE".
.str_complete
    ; Top half of "TESTING COMPLETE"
    EQUB 8, 4, 18
    EQUB 141, 135
    EQUS "TESTING COMPLETE"

    ; Bottom half of "TESTING COMPLETE"
    EQUB 9, 4, 18
    EQUB 141, 135
    EQUS "TESTING COMPLETE"

    ; Sub-text in cyan.
    EQUB 12, 3, 28
    EQUB 134
    EQUS "Thank you for participating"
    EQUB 13, 3, 28
    EQUB 134
    EQUS "in this Enrichment Center"
    EQUB 14, 3, 18
    EQUB 134
    EQUS "activity.  Bye!"

    ; Flashing prompt.
    EQUB 20, 4, 26
    EQUB 136, 135
    EQUS "Press SPACE to restart"

    EQUB &FF            ; end sentinel
