; Simple 2-voice music player using OSWORD &07 (SOUND).
;
; Tick input is 50Hz (VSYNC). Internally we run a precise 20Hz scheduler so
; SOUND durations can be expressed directly in 1/20th-second units.

; Event stream format (bytes):
;   pitch, duration
;   pitch 0..252: play note with that SOUND pitch (8-bit pitch)
;   pitch 253: rest (duration applies)
;   pitch 254: loop to start (duration ignored)
;   pitch 255: end/stop (duration ignored)
;
; duration: 1..255 ticks of 1/20s

MUSIC_EV_LOOP = 254
MUSIC_EV_END  = 255
MUSIC_EV_REST = 253

MUSIC_MIDDLE_C_PITCH = 101
MUSIC_PITCH_PER_SEMITONE = 4

; Player state needs ZP for (ptr),Y addressing.
; Define MUSIC_ZP_BASE before INCLUDE'ing this file.
;
; Layout (all ZP):
;   +0  accum_20hz
;   +1  v0_ptr lo
;   +2  v0_ptr hi
;   +3  v1_ptr lo
;   +4  v1_ptr hi
;   +5  v0_wait
;   +6  v1_wait
;   +7  v0_start lo
;   +8  v0_start hi
;   +9  v1_start lo
;   +10 v1_start hi
;   +11 temp_pitch

music_accum_20hz = MUSIC_ZP_BASE + 0
music_v0_ptr     = MUSIC_ZP_BASE + 1
music_v1_ptr     = MUSIC_ZP_BASE + 3

music_v0_wait    = MUSIC_ZP_BASE + 5
music_v1_wait    = MUSIC_ZP_BASE + 6

music_v0_start   = MUSIC_ZP_BASE + 7
music_v1_start   = MUSIC_ZP_BASE + 9

temp_pitch       = MUSIC_ZP_BASE + 11

; OSWORD &07 control block (8 bytes) in main RAM.
; The harness must provide a label `sound_block` pointing at 8 writable bytes.

; Two voices on channels 1..2.
MUSIC_CHAN0 = &0011   ; flush=1, channel=1
MUSIC_CHAN1 = &0012   ; flush=1, channel=2

; Use envelopes (1..16) instead of fixed volumes so we can shape the sound.
MUSIC_ENV_LEAD   = 1
MUSIC_ENV_BASS   = 2


; Initialize track pointers and start playing.
.music_init
    LDA #0
    STA music_accum_20hz
    STA music_v0_wait
    STA music_v1_wait

    LDA #<habanera_v0
    STA music_v0_ptr
    STA music_v0_start
    LDA #>habanera_v0
    STA music_v0_ptr+1
    STA music_v0_start+1

    LDA #<habanera_v1
    STA music_v1_ptr
    STA music_v1_start
    LDA #>habanera_v1
    STA music_v1_ptr+1
    STA music_v1_start+1

    RTS


; Call once per VSYNC (50Hz).
.music_update_50hz
    ; Fractional accumulator: add 20 each 1/50s frame.
    ; When >=50, consume one 1/20s tick.
    LDA music_accum_20hz
    CLC
    ADC #20
    STA music_accum_20hz

    CMP #50
    BCC mu_done

    SEC
    SBC #50
    STA music_accum_20hz
    JSR music_tick_20hz

.mu_done
    RTS


.music_tick_20hz
    JSR music_voice0_tick
    JSR music_voice1_tick
    RTS


.music_voice0_tick
    LDA music_v0_wait
    BEQ mv0_fetch
    DEC music_v0_wait
    RTS

.mv0_fetch
    LDY #0
    LDA (music_v0_ptr), Y
    CMP #MUSIC_EV_LOOP
    BEQ mv0_loop
    CMP #MUSIC_EV_END
    BEQ mv0_end
    STA temp_pitch
    INY
    LDA (music_v0_ptr), Y
    STA music_v0_wait
    JSR mv0_advance_2
    LDA temp_pitch
    CMP #MUSIC_EV_REST
    BEQ mv0_rest
    JSR play_note_v0
.mv0_rest
    RTS

.mv0_loop
    LDA music_v0_start
    STA music_v0_ptr
    LDA music_v0_start+1
    STA music_v0_ptr+1
    RTS

.mv0_end
    RTS

.mv0_advance_2
    CLC
    LDA music_v0_ptr
    ADC #2
    STA music_v0_ptr
    LDA music_v0_ptr+1
    ADC #0
    STA music_v0_ptr+1
    RTS


.music_voice1_tick
    LDA music_v1_wait
    BEQ mv1_fetch
    DEC music_v1_wait
    RTS

.mv1_fetch
    LDY #0
    LDA (music_v1_ptr), Y
    CMP #MUSIC_EV_LOOP
    BEQ mv1_loop
    CMP #MUSIC_EV_END
    BEQ mv1_end
    STA temp_pitch
    INY
    LDA (music_v1_ptr), Y
    STA music_v1_wait
    JSR mv1_advance_2
    LDA temp_pitch
    CMP #MUSIC_EV_REST
    BEQ mv1_rest
    JSR play_note_v1
.mv1_rest
    RTS

.mv1_loop
    LDA music_v1_start
    STA music_v1_ptr
    LDA music_v1_start+1
    STA music_v1_ptr+1
    RTS

.mv1_end
    RTS

.mv1_advance_2
    CLC
    LDA music_v1_ptr
    ADC #2
    STA music_v1_ptr
    LDA music_v1_ptr+1
    ADC #0
    STA music_v1_ptr+1
    RTS






; A = pitch (0..252).
; Uses music_v*_wait as the duration value already.

.play_note_v0
    STA temp_pitch
    ; sound_block[0..1] = channel
    LDA #<(MUSIC_CHAN0)
    STA sound_block+0
    LDA #>(MUSIC_CHAN0)
    STA sound_block+1

    ; sound_block[2..3] = envelope number (1..16)
    LDA #<(MUSIC_ENV_LEAD)
    STA sound_block+2
    LDA #>(MUSIC_ENV_LEAD)
    STA sound_block+3

    ; sound_block[4..5] = pitch (8-bit)
    LDA temp_pitch
    STA sound_block+4
    LDA #0
    STA sound_block+5

    ; sound_block[6..7] = duration
    LDA music_v0_wait
    STA sound_block+6
    LDA #0
    STA sound_block+7

    LDA #7
    LDX #<sound_block
    LDY #>sound_block
    JSR OSWORD
    RTS


.play_note_v1
    STA temp_pitch
    LDA #<(MUSIC_CHAN1)
    STA sound_block+0
    LDA #>(MUSIC_CHAN1)
    STA sound_block+1

    LDA #<(MUSIC_ENV_LEAD)
    STA sound_block+2
    LDA #>(MUSIC_ENV_LEAD)
    STA sound_block+3

    LDA temp_pitch
    STA sound_block+4
    LDA #0
    STA sound_block+5

    LDA music_v1_wait
    STA sound_block+6
    LDA #0
    STA sound_block+7

    LDA #7
    LDX #<sound_block
    LDY #>sound_block
    JSR OSWORD
    RTS

