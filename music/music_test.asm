; Standalone music test harness.
;
; Builds a small SSD that boots a BASIC loader and runs MUSICT.
; Uses MOS SOUND (OSWORD &07) for fast iteration.

INCLUDE "shared/oscalls.asm"
INCLUDE "shared/timing.asm"

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
    EQUS "PORTHOLE music test: Gymnopedie No. 1"
    EQUB 0


; ZP workspace for the music test player.
; Keep it in the same "language workspace" range as the main game.
; Test harness has all of ZP to itself: put both blocks there.
MUSIC_ZP_BASE  = &70
MUSIC_VAR_BASE = &76

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


; Define three envelopes:
; - env 1: melody (gentle attack, long sustain)
; - env 2: bass (solid attack, medium sustain)
; - env 3: chord (sharp attack, quick decay)
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

    ; Chord envelope 3
    LDA #8
    LDX #<env_chord
    LDY #>env_chord
    JSR OSWORD
    RTS


; OSWORD &08 control blocks (14 bytes each).
; See OSWORD &08 docs for field meanings.
;
; Byte layout:
;   0: envelope number (1-16)
;   1: step length (centiseconds per step)
;   2,3,4: pitch change per step in sections 1,2,3
;   5,6,7: number of steps in pitch sections 1,2,3
;   8: amplitude attack delta per step (+)
;   9: amplitude decay delta per step (-)
;  10: amplitude sustain delta per step
;  11: amplitude release delta per step (-)
;  12: attack target amplitude (0-126, or -1..-127)
;  13: decay target amplitude

.env_melody
    EQUB 1          ; envelope number
    EQUB 4          ; step length (slower)
    EQUB 0,0,0      ; pitch change steps 1..3
    EQUB 1,20,0     ; pitch section lengths
    EQUB 15         ; amp attack delta (instant)
    EQUB -1         ; amp decay delta (gentle fade)
    EQUB 0          ; amp sustain delta
    EQUB -3         ; amp release delta
    EQUB 12         ; attack target amp
    EQUB 8          ; decay target amp (sustains longer)

.env_bass
    EQUB 2          ; envelope number
    EQUB 6          ; step length (very slow steps)
    EQUB 0,0,0      ; pitch change steps 1..3
    EQUB 1,30,0     ; pitch section lengths
    EQUB 15         ; amp attack delta (instant)
    EQUB -1         ; amp decay delta (barely fades)
    EQUB 0          ; amp sustain delta
    EQUB -1         ; amp release delta (slow release)
    EQUB 8          ; attack target amp (quieter)
    EQUB 6          ; decay target amp (sits underneath)

.env_chord
    EQUB 3          ; envelope number
    EQUB 6          ; step length (same as bass)
    EQUB 0,0,0      ; pitch change steps 1..3
    EQUB 1,30,0     ; pitch section lengths
    EQUB 15         ; amp attack delta (instant)
    EQUB -1         ; amp decay delta (barely fades)
    EQUB 0          ; amp sustain delta
    EQUB -1         ; amp release delta (slow release)
    EQUB 8          ; attack target amp (same as bass)
    EQUB 6          ; decay target amp (same as bass)


INCLUDE "music/player.asm"
INCLUDE "music/gymnopedie.asm"

.end

SAVE "MUSICT", start, end
