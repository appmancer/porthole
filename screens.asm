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

    ; Look up per-level overlay data pointer.
    LDA current_level
    ASL A                       ; *2 for word index
    TAX
    LDA level_card_ptrs,X
    STA temp_sprite_ptr
    LDA level_card_ptrs+1,X
    STA temp_sprite_ptr+1

    ; Write overlay records (TEST CHAMBER header + GLaDOS quote + prompt).
    LDX temp_sprite_ptr
    LDY temp_sprite_ptr+1
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


; =====================================================================
; Per-level card overlays: pointer table + record data.
;
; Each overlay is a sequence of (row, col, len, data...) records
; terminated by &FF, written on top of the TEMPLTE background.
;
; The "00" number placeholder is patched by show_level_card afterwards.
;
; MODE 7 control codes used:
;   &8D = double-height,  &87 = white alpha,  &84 = blue alpha
;   &88 = flash on,  &89 = flash off (steady)
; =====================================================================

.level_card_ptrs
    EQUW level_card_0
    EQUW level_card_1
    EQUW level_card_2
    EQUW level_card_3
    EQUW level_card_4

; --- Level 1 card ---
.level_card_0
    ; Double-height "TEST CHAMBER 00" (rows 12-13, control codes in template).
    EQUB 12, 4, 15
    EQUS "TEST CHAMBER 00"
    EQUB 13, 4, 15
    EQUS "TEST CHAMBER 00"

    ; GLaDOS quote (rows 16-17, colour code in template).
    EQUB 16, 4, 24
    EQUS "This is the part where I"
    EQUB 17, 4, 23
    EQUS "kill you. Just kidding."

    EQUB &FF

; --- Level 2 card ---
.level_card_1
    EQUB 12, 4, 15
    EQUS "TEST CHAMBER 00"
    EQUB 13, 4, 15
    EQUS "TEST CHAMBER 00"

    EQUB 16, 4, 23
    EQUS "Impressive. Not really."
    EQUB 17, 4, 26
    EQUS "But the lie motivates you."

    EQUB &FF

; --- Level 3 card ---
.level_card_2
    EQUB 12, 4, 15
    EQUS "TEST CHAMBER 00"
    EQUB 13, 4, 15
    EQUS "TEST CHAMBER 00"

    EQUB 16, 4, 23
    EQUS "You're doing very well."
    EQUB 17, 4, 12
    EQUS "For a human."

    EQUB &FF

; --- Level 4 card ---
.level_card_3
    EQUB 12, 4, 15
    EQUS "TEST CHAMBER 00"
    EQUB 13, 4, 15
    EQUS "TEST CHAMBER 00"

    EQUB 16, 4, 30
    EQUS "The cube cannot love you back."

    EQUB &FF

; --- Level 5 card ---
.level_card_4
    EQUB 12, 4, 15
    EQUS "TEST CHAMBER 00"
    EQUB 13, 4, 15
    EQUS "TEST CHAMBER 00"

    EQUB 16, 4, 24
    EQUS "This is your final test."
    EQUB 17, 4, 9
    EQUS "Probably."

    EQUB &FF


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
    EQUB 13, 3, 26
    EQUB 134
    EQUS "in this Enrichment Center"
    EQUB 14, 3, 16
    EQUB 134
    EQUS "activity.  Bye!"

    ; Flashing prompt.
    EQUB 20, 4, 24
    EQUB 136, 135
    EQUS "Press SPACE to restart"

    EQUB &FF            ; end sentinel
