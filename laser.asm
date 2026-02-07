.laser_start
; laser.asm — Laser beam system.
;
; Stage 2: target signal activation. Beam tiles are pre-authored in tilemaps.
; For each target, checks if it lies on a laser's beam path (between emitter
; and wall). Lit targets OR their channel bit into sig_state.
;
; Generated tables (from tools/gen-level):
;   laser_defs:  LASER_COUNT entries of LASER_DEF_SIZE (7) bytes each
;                (room, wall_tile_x, wall_tile_y, dir, channel, emitter_x, emitter_y)
;   target_defs: TARGET_COUNT entries of TARGET_DEF_SIZE (4) bytes each
;                (room, tile_x, tile_y, channel)

; Initialize beam runtime state from generated laser/target tables.
; Called once at level load.
; Clobbers: none
.init_beams
    RTS


; Check each target against all laser beam paths.
; If a target lies strictly between a laser's wall and emitter on the same
; axis, OR its channel bit into sig_state.
;
; Called from update_signals_and_object_states between driver and consumer passes.
; Clobbers: A,X,Y,temp,temp_y
.update_beam_targets
    LDX #0                       ; target def offset
  .ubt_tgt_loop
    CPX #(TARGET_COUNT * TARGET_DEF_SIZE)
    BCS ubt_done
    ; Load target fields into local storage.
    LDA target_defs,X
    STA ubt_tgt_room
    LDA target_defs+1,X
    STA ubt_tgt_x
    LDA target_defs+2,X
    STA ubt_tgt_y
    LDA target_defs+3,X
    STA ubt_tgt_ch

    ; Save target offset.
    STX ubt_tgt_off

    ; Walk laser_defs looking for a beam that hits this target.
    LDX #0                       ; laser def offset
  .ubt_las_loop
    CPX #(LASER_COUNT * LASER_DEF_SIZE)
    BCS ubt_not_lit

    ; Room match?
    LDA laser_defs,X
    CMP ubt_tgt_room
    BNE ubt_next_las

    ; Direction: bit 1 distinguishes H (0,1) from V (2,3).
    LDA laser_defs+3,X           ; dir
    AND #2
    BNE ubt_vert

    ; --- Horizontal beam (LEFT or RIGHT) ---
    ; target_y must equal wall_y.
    LDA laser_defs+2,X           ; wall_y
    CMP ubt_tgt_y
    BNE ubt_next_las

    ; Range check: target_x strictly between wall_x and emitter_x.
    LDA laser_defs+1,X           ; wall_x
    STA temp
    LDA laser_defs+5,X           ; emitter_x
    STA temp_y
    LDA ubt_tgt_x
    JSR ubt_range
    BCS ubt_lit
    JMP ubt_next_las

  .ubt_vert
    ; --- Vertical beam (UP or DOWN) ---
    ; target_x must equal wall_x.
    LDA laser_defs+1,X           ; wall_x
    CMP ubt_tgt_x
    BNE ubt_next_las

    ; Range check: target_y strictly between wall_y and emitter_y.
    LDA laser_defs+2,X           ; wall_y
    STA temp
    LDA laser_defs+6,X           ; emitter_y
    STA temp_y
    LDA ubt_tgt_y
    JSR ubt_range
    BCS ubt_lit

  .ubt_next_las
    TXA
    CLC
    ADC #LASER_DEF_SIZE
    TAX
    JMP ubt_las_loop

  .ubt_not_lit
    ; Target not in any beam path. Move to next target.
    LDX ubt_tgt_off
    TXA
    CLC
    ADC #TARGET_DEF_SIZE
    TAX
    JMP ubt_tgt_loop

  .ubt_done
    RTS

  .ubt_lit
    ; Target IS lit — OR its channel bit into sig_state.
    LDX ubt_tgt_ch
    LDA bit_table,X
    ORA sig_state
    STA sig_state
    ; Fall through to next target.
    JMP ubt_not_lit


; Range check: is A strictly between temp and temp_y?
; Input:  A = value to test, temp = bound1, temp_y = bound2
; Output: C=1 if min(bound1,bound2) < A < max(bound1,bound2), C=0 otherwise
; Clobbers: Y (used for swap)
.ubt_range
    ; Canonicalize: ensure temp <= temp_y.
    PHA
    LDY temp
    CPY temp_y
    BCC ubt_r_ordered            ; temp < temp_y, already ordered
    BEQ ubt_r_fail_pop           ; equal — no gap, impossible to be between
    ; temp > temp_y: swap.
    LDA temp_y
    STY temp_y
    STA temp
  .ubt_r_ordered
    PLA
    ; Now temp = lo, temp_y = hi. Check lo < A < hi.
    CMP temp
    BEQ ubt_r_fail
    BCC ubt_r_fail               ; A <= lo
    CMP temp_y
    BCS ubt_r_fail               ; A >= hi
    SEC                          ; in range
    RTS
  .ubt_r_fail
    CLC
    RTS
  .ubt_r_fail_pop
    PLA
    CLC
    RTS


; Local storage for update_beam_targets (not ZP — saves ZP pressure).
.ubt_tgt_room   SKIP 1
.ubt_tgt_x      SKIP 1
.ubt_tgt_y      SKIP 1
.ubt_tgt_ch     SKIP 1
.ubt_tgt_off    SKIP 1           ; saved target def offset
