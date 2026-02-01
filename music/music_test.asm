; Standalone music test harness.
;
; Builds a small SSD that boots a BASIC loader and runs MUSICT.
; Uses MOS SOUND (OSWORD &07) for fast iteration.

INCLUDE "oscalls.asm"
INCLUDE "timing.asm"

ORG &1900

.start
    CLI
    ; MODE 7 for simple text output.
    LDA #22: JSR OSWRCH
    LDA #7:  JSR OSWRCH

    JSR print_banner
    JSR print_before_beep
    JSR test_beep
    JSR print_after_beep
    JSR setup_envelopes
    JSR music_init
    JSR print_after_init

.main_loop
    JSR music_update_time
    JMP main_loop


.print_banner
    LDX #0
.pb_loop
    LDA banner_txt, X
    BEQ pb_done
    JSR OSASCI
    INX
    BNE pb_loop
.pb_done
    JSR OSNEWL
    RTS

.print_before_beep
    LDX #0
.pbb_loop
    LDA before_beep_txt, X
    BEQ pbb_done
    JSR OSASCI
    INX
    BNE pbb_loop
.pbb_done
    JSR OSNEWL
    RTS

.before_beep_txt
    EQUS "Calling OSWORD SOUND..."
    EQUB 0

.print_after_beep
    LDX #0
.pab_loop
    LDA after_beep_txt, X
    BEQ pab_done
    JSR OSASCI
    INX
    BNE pab_loop
.pab_done
    JSR OSNEWL
    RTS

.after_beep_txt
    EQUS "OSWORD SOUND returned"
    EQUB 0

.print_after_init
    LDX #0
.pai_loop
    LDA after_init_txt, X
    BEQ pai_done
    JSR OSASCI
    INX
    BNE pai_loop
.pai_done
    JSR OSNEWL
    RTS

.after_init_txt
    EQUS "music_init returned"
    EQUB 0

; Drive music from system clock TIME (centiseconds) so note lengths and rests
; are stable regardless of emulator speed.
;
; OSWORD &01 returns a 5-byte TIME value (centiseconds) into a buffer.
; We use the low byte and tick at 5cs = 1/20s.

.music_update_time
    JSR read_time_cs
    LDA time_cs_buf

    ; delta = (cur - last) & 255
    SEC
    SBC last_time_cs
    STA delta_cs
    LDA time_cs_buf
    STA last_time_cs

    ; accum += delta
    LDA time_accum_cs
    CLC
    ADC delta_cs
    STA time_accum_cs

.mut_loop
    LDA time_accum_cs
    CMP #5
    BCC mut_done
    SEC
    SBC #5
    STA time_accum_cs
    JSR music_tick_20hz
    JMP mut_loop

.mut_done
    RTS


.read_time_cs
    LDA #1
    LDX #<time_cs_buf
    LDY #>time_cs_buf
    JSR OSWORD
    RTS

.banner_txt
    EQUS "PORTHOLE music test: Habanera"
    EQUB 0


; ZP workspace for the music test player.
; Keep it in the same "language workspace" range as the main game.
MUSIC_ZP_BASE = &70

; OSWORD &07 (SOUND) control block (8 bytes).
.sound_block
    EQUB 0,0,  0,0,  0,0,  0,0

; OSWORD &01 (TIME) buffer (5 bytes, low byte first).
.time_cs_buf
    EQUB 0,0,0,0,0

.last_time_cs
    EQUB 0
.time_accum_cs
    EQUB 0
.delta_cs
    EQUB 0


; Quick sanity check: play a single note via OSWORD &07.
; If this errors, we'll drop back to BASIC at line 20.
.test_beep
    ; Channel: internal sound, channel 1.
    LDA #&01
    STA sound_block+0
    LDA #&00
    STA sound_block+1

    ; Volume: -8.
    LDA #&F8
    STA sound_block+2
    LDA #&FF
    STA sound_block+3

    ; Pitch: middle C (101) as 8-bit pitch.
    LDA #101
    STA sound_block+4
    LDA #0
    STA sound_block+5

    ; Duration: 10 ticks (0.5s)
    LDA #10
    STA sound_block+6
    LDA #0
    STA sound_block+7

    LDA #7
    LDX #<sound_block
    LDY #>sound_block
    JSR OSWORD
    RTS


; Define two envelopes:
; - env 1: melody (gentle attack, medium decay)
; - env 2: bass (snappy attack, quick decay)
;
; We keep pitch envelope flat (0 deltas) and only shape amplitude.
.setup_envelopes
    ; Melody envelope 1
    LDA #8
    LDX #<env_melody
    LDY #>env_melody
    JSR OSWORD

    ; Bass envelope 2
    LDA #8
    LDX #<env_bass
    LDY #>env_bass
    JSR OSWORD
    RTS


; OSWORD &08 control blocks (14 bytes each).
; See OSWORD &08 docs for field meanings.

.env_melody
    EQUB 1          ; envelope number
    EQUB 3          ; step length
    EQUB 0,0,0      ; pitch change steps 1..3
    EQUB 1,10,0     ; pitch sections steps (unused)
    EQUB 6          ; amp attack delta
    EQUB -1         ; amp decay delta
    EQUB 0          ; amp sustain delta
    EQUB -2         ; amp release delta
    EQUB 15         ; attack target amp
    EQUB 10         ; decay target amp

.env_bass
    EQUB 2          ; envelope number
    EQUB 2          ; step length
    EQUB 0,0,0      ; pitch change steps 1..3
    EQUB 1,6,0      ; pitch sections steps (unused)
    EQUB 8          ; amp attack delta
    EQUB -5         ; amp decay delta
    EQUB 0          ; amp sustain delta
    EQUB -3         ; amp release delta
    EQUB 15         ; attack target amp
    EQUB 4          ; decay target amp


INCLUDE "music/player.asm"
INCLUDE "music/habanera.asm"

.end

SAVE "PROGRAM", start, end
