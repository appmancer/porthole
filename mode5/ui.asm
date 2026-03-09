.ui_start
; ui.asm
; Small UI/OS-facing helpers (cursor/palette/input).

; Disable the text cursor by redefining it to all zeros.
; This avoids the OS blinking cursor touching screen RAM.
.disable_cursor
    LDX #0
.cursor_loop
    LDA cursor_vdu,X
    JSR OSWRCH
    INX
    CPX #10
    BNE cursor_loop
    RTS

.cursor_vdu
    EQUB 23,1,0,0,0,0,0,0,0,0


; Set MODE 5 palette mapping.
; Uses VDU 19,logical,physical,0,0,0.
.set_palette
    LDX #0
.palette_loop
    LDA palette_vdu,X
    JSR OSWRCH
    INX
    CPX #24
    BNE palette_loop
    RTS

.palette_vdu
    ; logical 0 -> physical 0 (black)
    EQUB 19,0,0,0,0,0
    ; logical 1 -> physical 1 (red)
    EQUB 19,1,1,0,0,0
    ; logical 2 -> physical 6 (cyan)
    EQUB 19,2,6,0,0,0
    ; logical 3 -> physical 3 (yellow)
    EQUB 19,3,3,0,0,0


; Wait for a single keypress (B2-friendly, debounced).
; Uses OSBYTE 129 (INKEY-256): Y=ASCII, N set if no key.
; Returns: A = ASCII of key pressed.
.wait_key
    LDX #&00
    LDY #&00

    ; Wait for a key to be down.
.wait_key_down
    LDA #129
    JSR OSBYTE
    TYA
    BMI wait_key_down

    ; Latch key value.
    TYA
    PHA

    ; Wait for key to be released (no key down).
.wait_key_up
    LDA #129
    JSR OSBYTE
    TYA
    BPL wait_key_up

    PLA
    RTS
