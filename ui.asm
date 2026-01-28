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


; --- Palette flash debug ---
;
; If palette_flash_timer is nonzero, remap logical colour 2 (normally cyan) to
; palette_flash_phys2 for this render, then auto-restore when the timer reaches 0.
;
; Uses: VDU 19,2,<phys>,0,0,0.
; Clobbers: A
.palette_flash_update
    LDA palette_flash_timer
    BEQ pfu_maybe_restore

    ; Desired physical colour for logical 2.
    LDA palette_flash_phys2

    ; If already active with this mapping, just tick.
    CMP palette_flash_active
    BEQ pfu_tick

    ; Apply mapping.
    JSR pfu_map_log2
    LDA palette_flash_phys2
    STA palette_flash_active

 .pfu_tick
    DEC palette_flash_timer
    RTS

 .pfu_maybe_restore
    LDA palette_flash_active
    BEQ pfu_done

    ; Restore logical 2 -> physical 6 (cyan)
    LDA #6
    JSR pfu_map_log2
    LDA #0
    STA palette_flash_active

 .pfu_done
    RTS


; Map logical colour 2 to physical colour A.
; Clobbers: A
.pfu_map_log2
    PHA
    LDA #19
    JSR OSWRCH
    LDA #2
    JSR OSWRCH
    PLA
    JSR OSWRCH
    LDA #0
    JSR OSWRCH
    JSR OSWRCH
    JSR OSWRCH
    RTS


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
