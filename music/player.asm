; Simple 3-voice music player using OSWORD &07 (SOUND).
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

; Player state is split by addressing requirement:
;
;   MUSIC_ZP_BASE  (6 bytes) -- MUST be in zero page. These are the three voice
;                               track pointers, read via (ptr),Y.
;   MUSIC_VAR_BASE (11 bytes) -- accessed absolute, so may live anywhere.
;
; Define both before INCLUDE'ing this file. The game is short on zero page
; (only &83-&8F free), so it puts only the pointers there; music_test puts
; both blocks in ZP, which is equivalent.
;
; MUSIC_ZP_BASE layout:
;   +0  v0_ptr lo
;   +1  v0_ptr hi
;   +2  v1_ptr lo
;   +3  v1_ptr hi
;   +4  v2_ptr lo
;   +5  v2_ptr hi
;
; MUSIC_VAR_BASE layout:
;   +0  accum_20hz
;   +1  v0_wait
;   +2  v1_wait
;   +3  v2_wait
;   +4  v0_start lo
;   +5  v0_start hi
;   +6  v1_start lo
;   +7  v1_start hi
;   +8  v2_start lo
;   +9  v2_start hi
;   +10 temp_pitch

music_v0_ptr     = MUSIC_ZP_BASE + 0
music_v1_ptr     = MUSIC_ZP_BASE + 2
music_v2_ptr     = MUSIC_ZP_BASE + 4

music_accum_20hz = MUSIC_VAR_BASE + 0

music_v0_wait    = MUSIC_VAR_BASE + 1
music_v1_wait    = MUSIC_VAR_BASE + 2
music_v2_wait    = MUSIC_VAR_BASE + 3

music_v0_start   = MUSIC_VAR_BASE + 4
music_v1_start   = MUSIC_VAR_BASE + 6
music_v2_start   = MUSIC_VAR_BASE + 8

temp_pitch       = MUSIC_VAR_BASE + 10

; OSWORD &07 control block (8 bytes) in main RAM.
; The harness must provide a label `sound_block` pointing at 8 writable bytes.

; Three voices on channels 1..3.
MUSIC_CHAN0 = &0011   ; flush=1, channel=1
MUSIC_CHAN1 = &0012   ; flush=1, channel=2
MUSIC_CHAN2 = &0013   ; flush=1, channel=3

; Use envelopes (1..16) instead of fixed volumes so we can shape the sound.
MUSIC_ENV_LEAD   = 1
MUSIC_ENV_BASS   = 2
MUSIC_ENV_CHORD  = 3


; Initialize track pointers and start playing.
; The caller must define `music_track_table` — 6 bytes: lo/hi for v0, v1, v2.
.music_init
    LDA #0
    STA music_accum_20hz
    STA music_v0_wait
    STA music_v1_wait
    STA music_v2_wait

    LDA music_track_table+0
    STA music_v0_ptr
    STA music_v0_start
    LDA music_track_table+1
    STA music_v0_ptr+1
    STA music_v0_start+1

    LDA music_track_table+2
    STA music_v1_ptr
    STA music_v1_start
    LDA music_track_table+3
    STA music_v1_ptr+1
    STA music_v1_start+1

    LDA music_track_table+4
    STA music_v2_ptr
    STA music_v2_start
    LDA music_track_table+5
    STA music_v2_ptr+1
    STA music_v2_start+1

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
    JSR music_voice2_tick
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
    JMP music_voice0_tick

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
    JMP music_voice1_tick

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


.music_voice2_tick
    LDA music_v2_wait
    BEQ mv2_fetch
    DEC music_v2_wait
    RTS

.mv2_fetch
    LDY #0
    LDA (music_v2_ptr), Y
    CMP #MUSIC_EV_LOOP
    BEQ mv2_loop
    CMP #MUSIC_EV_END
    BEQ mv2_end
    STA temp_pitch
    INY
    LDA (music_v2_ptr), Y
    STA music_v2_wait
    JSR mv2_advance_2
    LDA temp_pitch
    CMP #MUSIC_EV_REST
    BEQ mv2_rest
    JSR play_note_v2
.mv2_rest
    RTS

.mv2_loop
    LDA music_v2_start
    STA music_v2_ptr
    LDA music_v2_start+1
    STA music_v2_ptr+1
    JMP music_voice2_tick

.mv2_end
    RTS

.mv2_advance_2
    CLC
    LDA music_v2_ptr
    ADC #2
    STA music_v2_ptr
    LDA music_v2_ptr+1
    ADC #0
    STA music_v2_ptr+1
    RTS


; A = pitch (0..252).

.play_note_v0
    STA temp_pitch
    LDA #<(MUSIC_CHAN0)
    STA sound_block+0
    LDA #>(MUSIC_CHAN0)
    STA sound_block+1

    LDA #<(MUSIC_ENV_LEAD)
    STA sound_block+2
    LDA #>(MUSIC_ENV_LEAD)
    STA sound_block+3

    LDA temp_pitch
    STA sound_block+4
    LDA #0
    STA sound_block+5

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

    LDA #<(MUSIC_ENV_BASS)
    STA sound_block+2
    LDA #>(MUSIC_ENV_BASS)
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


.play_note_v2
    STA temp_pitch
    LDA #<(MUSIC_CHAN2)
    STA sound_block+0
    LDA #>(MUSIC_CHAN2)
    STA sound_block+1

    LDA #<(MUSIC_ENV_CHORD)
    STA sound_block+2
    LDA #>(MUSIC_ENV_CHORD)
    STA sound_block+3

    LDA temp_pitch
    STA sound_block+4
    LDA #0
    STA sound_block+5

    LDA music_v2_wait
    STA sound_block+6
    LDA #0
    STA sound_block+7

    LDA #7
    LDX #<sound_block
    LDY #>sound_block
    JSR OSWORD
    RTS
