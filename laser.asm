.laser_start
; laser.asm — Laser beam system.
;
; Stage 3: Portal redirection. Pre-authored beam tiles exist in tilemaps
; for static segments (emitter→wall). When a portal sits on the wall-hit
; tile, the beam passes through and continues dynamically from the paired
; portal, stamping beam tiles into the tilemap until hitting a wall,
; target, or another portal.
;
; Generated tables (from tools/gen-level):
;   laser_defs:  LASER_COUNT entries of LASER_DEF_SIZE (7) bytes each
;                (room, wall_tile_x, wall_tile_y, dir, channel, emitter_x, emitter_y)
;   target_defs: TARGET_COUNT entries of TARGET_DEF_SIZE (4) bytes each
;                (room, tile_x, tile_y, channel)

; --- Direction tables ---
; Beam directions: LEFT=0, RIGHT=1, UP=2, DOWN=3

; Position deltas per direction.
.dir_dx_table      EQUB &FF, &01, &00, &00
.dir_dy_table      EQUB &00, &00, &FF, &01

; Entry condition: beam dir required to enter portal with given orient.
; WALL_L→LEFT(0), WALL_R→RIGHT(1), FLOOR→DOWN(3), CEIL→UP(2)
.entry_dir_table   EQUB 0, 1, 3, 2

; Exit direction: beam dir when exiting portal with given orient.
; WALL_L→RIGHT(1), WALL_R→LEFT(0), FLOOR→UP(2), CEIL→DOWN(3)
.exit_dir_table    EQUB 1, 0, 2, 3

; Maximum dynamic beam steps per laser segment.
MAX_BEAM_STEPS = 32


; Initialize beam runtime state. Called from restart_level.
; beam_tile_count is already 0 (unstamp called earlier in restart).
; Clobbers: A,X
.init_beams
    LDA #0
    LDX #TARGET_COUNT-1
  .ib_clear
    STA target_lit,X
    DEX
    BPL ib_clear
    RTS


; Restore tilemap tiles modified by dynamic beam stamps.
; If beam_do_redraw is non-zero, also redraws each tile on screen.
; Clobbers: A,X,Y,temp,temp_y,row_counter,screen_ptr,sprite_ptr
.unstamp_beam_tiles
    LDX beam_tile_count
    BEQ usbt_ret
  .usbt_loop
    DEX
    LDY beam_tile_pos,X
    LDA beam_tile_orig,X
    STA (tilemap_ptr),Y
    ; Optional incremental redraw.
    LDA beam_do_redraw
    BEQ usbt_no_redraw
    STX usbt_save_x
    ; Convert tilemap offset (y*16+x) to tile_x, tile_y.
    TYA
    AND #&0F
    TAX                        ; tile_x
    TYA
    LSR A : LSR A : LSR A : LSR A
    JSR redraw_tile_xy         ; A=tile_y, X=tile_x
    LDX usbt_save_x
  .usbt_no_redraw
    CPX #0
    BNE usbt_loop
  .usbt_ret
    LDA #0
    STA beam_tile_count
    RTS


; Retrace all laser beams. Unstamps old dynamic tiles, clears target_lit,
; then traces each laser: static segment (geometric target check) and
; dynamic segment through portals if applicable.
;
; Set beam_do_redraw before calling:
;   1 = incremental redraw (after portal placement)
;   0 = skip redraw (full room redraw will follow)
;
; Clobbers: A,X,Y,temp,temp_y,screen_ptr,sprite_ptr,row_counter
.retrace_all_beams
    JSR unstamp_beam_tiles

    ; Clear target_lit flags.
    LDX #TARGET_COUNT-1
    LDA #0
  .rab_clear_tgt
    STA target_lit,X
    DEX
    BPL rab_clear_tgt

    ; Process each laser.
    LDX #0
  .rab_laser_loop
    CPX #(LASER_COUNT * LASER_DEF_SIZE)
    BCS rab_done
    STX rab_laser_off

    ; Load laser fields into local storage.
    LDA laser_defs,X           ; room
    STA trace_room
    LDA laser_defs+1,X        ; wall_x
    STA trace_wall_x
    LDA laser_defs+2,X        ; wall_y
    STA trace_wall_y
    LDA laser_defs+3,X        ; dir
    STA trace_dir
    LDA laser_defs+5,X        ; emitter_x
    STA trace_emitter_x
    LDA laser_defs+6,X        ; emitter_y
    STA trace_emitter_y

    ; Static segment: check targets between emitter and wall.
    JSR check_static_targets

    ; Portal redirect check: does wall-hit tile have a matching portal?
    JSR check_wall_portal
    BCC rab_next_laser         ; C=0: no portal, done with this laser

    ; C=1: portal found. trace_x/y/room/dir set to exit portal start.
    JSR trace_dynamic_beam

  .rab_next_laser
    LDX rab_laser_off
    TXA
    CLC
    ADC #LASER_DEF_SIZE
    TAX
    JMP rab_laser_loop

  .rab_done
    RTS


; Check all targets against the static segment of the current laser.
; Static segment: same room, same axis, strictly between emitter and wall.
; Uses trace_room, trace_wall_x/y, trace_dir, trace_emitter_x/y.
; Clobbers: A,X,Y
.check_static_targets
    LDX #0
  .cst_loop
    CPX #(TARGET_COUNT * TARGET_DEF_SIZE)
    BCS cst_done

    ; Room match?
    LDA target_defs,X
    CMP trace_room
    BNE cst_next

    ; Direction: bit 1 distinguishes H (0,1) from V (2,3).
    LDA trace_dir
    AND #2
    BNE cst_vert

    ; Horizontal beam: target_y must equal wall_y.
    LDA target_defs+2,X
    CMP trace_wall_y
    BNE cst_next

    ; Range: target_x strictly between wall_x and emitter_x.
    LDA trace_wall_x
    STA temp
    LDA trace_emitter_x
    STA temp_y
    LDA target_defs+1,X
    JSR beam_range_check
    BCS cst_hit
    JMP cst_next

  .cst_vert
    ; Vertical beam: target_x must equal wall_x.
    LDA target_defs+1,X
    CMP trace_wall_x
    BNE cst_next

    ; Range: target_y strictly between wall_y and emitter_y.
    LDA trace_wall_y
    STA temp
    LDA trace_emitter_y
    STA temp_y
    LDA target_defs+2,X
    JSR beam_range_check
    BCS cst_hit

  .cst_next
    TXA
    CLC
    ADC #TARGET_DEF_SIZE
    TAX
    JMP cst_loop

  .cst_hit
    ; target_index = X / TARGET_DEF_SIZE (=4)
    TXA
    LSR A
    LSR A
    TAY
    LDA #1
    STA target_lit,Y
    JMP cst_next

  .cst_done
    RTS


; Check if the wall-hit tile of the current laser has a portal.
; If so, set up trace_x/y/room/dir for the exit portal.
; Returns C=1 if portal found, C=0 otherwise.
; Uses trace_wall_x, trace_wall_y, trace_room, trace_dir.
; Clobbers: A,Y
.check_wall_portal
    ; --- Check portal A ---
    LDA portal_a_enabled
    BEQ cwp_check_b
    LDA portal_a_room
    CMP trace_room
    BNE cwp_check_b
    LDA portal_a_x
    CMP trace_wall_x
    BNE cwp_check_b
    LDA portal_a_y
    CMP trace_wall_y
    BNE cwp_check_b
    ; Portal A is at wall-hit tile. Check orient is not BACK.
    LDY portal_a_orient
    CPY #PORTAL_ORIENT_BACK
    BEQ cwp_check_b
    ; Check entry direction matches beam direction.
    LDA entry_dir_table,Y
    CMP trace_dir
    BNE cwp_check_b
    ; Portal A matches! Exit from portal B.
    LDA portal_b_enabled
    BEQ cwp_fail
    LDY portal_b_orient
    CPY #PORTAL_ORIENT_BACK
    BEQ cwp_fail
    LDA portal_b_x
    STA trace_x
    LDA portal_b_y
    STA trace_y
    LDA portal_b_room
    STA trace_room
    LDA exit_dir_table,Y
    STA trace_dir
    SEC
    RTS

  .cwp_check_b
    ; --- Check portal B ---
    LDA portal_b_enabled
    BEQ cwp_fail
    LDA portal_b_room
    CMP trace_room
    BNE cwp_fail
    LDA portal_b_x
    CMP trace_wall_x
    BNE cwp_fail
    LDA portal_b_y
    CMP trace_wall_y
    BNE cwp_fail
    LDY portal_b_orient
    CPY #PORTAL_ORIENT_BACK
    BEQ cwp_fail
    LDA entry_dir_table,Y
    CMP trace_dir
    BNE cwp_fail
    ; Portal B matches! Exit from portal A.
    LDA portal_a_enabled
    BEQ cwp_fail
    LDY portal_a_orient
    CPY #PORTAL_ORIENT_BACK
    BEQ cwp_fail
    LDA portal_a_x
    STA trace_x
    LDA portal_a_y
    STA trace_y
    LDA portal_a_room
    STA trace_room
    LDA exit_dir_table,Y
    STA trace_dir
    SEC
    RTS

  .cwp_fail
    CLC
    RTS


; Trace dynamic beam segment from trace_x/y/room in trace_dir.
; Stamps beam tiles into tilemap (current room only), checks targets
; and portals for redirect.
; Clobbers: A,X,Y,temp,temp_y,sprite_ptr,screen_ptr,row_counter
.trace_dynamic_beam
    LDA #0
    STA trace_steps

    ; CEIL/FLOOR exits: the stored position is the empty space tile.
    ; Step back one so the first advance in the loop lands on it.
    ; WALL exits have horizontal dir (0 or 1) — no adjustment needed.
    LDA trace_dir
    CMP #2
    BCC tdb_no_adj             ; horizontal → WALL, skip
    TAY
    LDA trace_y
    SEC
    SBC dir_dy_table,Y
    STA trace_y
  .tdb_no_adj
    JMP tdb_loop

  .tdb_exit
    ; Trampoline for distant branches.
    JMP tdb_done

  .tdb_loop
    LDA trace_steps
    CMP #MAX_BEAM_STEPS
    BCS tdb_exit

    ; Advance position by direction delta.
    LDY trace_dir
    LDA trace_x
    CLC
    ADC dir_dx_table,Y
    STA trace_x
    LDA trace_y
    CLC
    ADC dir_dy_table,Y
    STA trace_y

    ; Bounds check (0..15 for both axes, unsigned).
    LDA trace_x
    CMP #16
    BCS tdb_exit
    LDA trace_y
    CMP #16
    BCS tdb_exit

    ; Set sprite_ptr to traced room's tilemap.
    LDA trace_room
    ASL A
    TAX
    LDA room_pointers,X
    STA sprite_ptr
    LDA room_pointers+1,X
    STA sprite_ptr+1

    ; Tile offset = trace_y * 16 + trace_x
    LDA trace_y
    ASL A
    ASL A
    ASL A
    ASL A
    ORA trace_x
    TAY
    STY trace_tile_off
    LDA (sprite_ptr),Y

    ; Solid check: bit 5 set = solid tile.
    AND #&20
    BNE tdb_exit

    ; Check against all targets.
    JSR check_trace_target
    BCC tdb_no_target
    ; Target hit — stamp active receiver tile if in current room.
    LDA trace_room
    CMP current_room
    BNE tdb_exit
    LDX beam_tile_count
    CPX #MAX_BEAM_TILES
    BCS tdb_exit
    LDY trace_tile_off
    LDA (tilemap_ptr),Y
    STA beam_tile_orig,X
    CLC
    ADC #4                     ; inactive receiver → active (+4)
    STA (tilemap_ptr),Y
    TYA
    STA beam_tile_pos,X
    INC beam_tile_count
    LDA beam_do_redraw
    BEQ tdb_done
    LDA trace_x
    TAX
    LDA trace_y
    JSR redraw_tile_xy
    JMP tdb_done
  .tdb_no_target

    ; Check against portals for redirect.
    JSR check_trace_portal
    BCS tdb_redirected

    ; Not solid, not target, not portal. Stamp beam tile if in current room.
    LDA trace_room
    CMP current_room
    BNE tdb_advance

    ; Save original tile and stamp beam tile.
    LDX beam_tile_count
    CPX #MAX_BEAM_TILES
    BCS tdb_advance            ; beam list full
    LDY trace_tile_off
    LDA (tilemap_ptr),Y
    STA beam_tile_orig,X
    TYA
    STA beam_tile_pos,X
    ; Choose beam tile: H or V based on direction.
    ; If original is perpendicular beam, use crossroads instead.
    LDA trace_dir
    AND #2
    BNE tdb_stamp_v
    LDA beam_tile_orig,X
    CMP #TILE_BEAM_V
    BEQ tdb_stamp_cross
    LDA #TILE_BEAM_H
    JMP tdb_stamp
  .tdb_stamp_v
    LDA beam_tile_orig,X
    CMP #TILE_BEAM_H
    BEQ tdb_stamp_cross
    LDA #TILE_BEAM_V
    JMP tdb_stamp
  .tdb_stamp_cross
    LDA #TILE_CROSSROADS
  .tdb_stamp
    LDY trace_tile_off
    STA (tilemap_ptr),Y
    INC beam_tile_count
    ; Incremental redraw?
    LDA beam_do_redraw
    BEQ tdb_advance
    LDA trace_x
    TAX
    LDA trace_y
    JSR redraw_tile_xy

  .tdb_advance
    INC trace_steps
    JMP tdb_loop

  .tdb_redirected
    ; Portal redirect: trace_x/y/room/dir already updated by check_trace_portal.
    INC trace_steps
    JMP tdb_loop

  .tdb_done
    RTS


; Check if (trace_x, trace_y, trace_room) matches any target.
; If match: set target_lit[i] = 1, return C=1.
; Otherwise: return C=0.
; Clobbers: A,Y (preserves X)
.check_trace_target
    STX ctt_save_x
    LDX #0
  .ctt_loop
    CPX #(TARGET_COUNT * TARGET_DEF_SIZE)
    BCS ctt_miss
    LDA target_defs,X
    CMP trace_room
    BNE ctt_next
    LDA target_defs+1,X
    CMP trace_x
    BNE ctt_next
    LDA target_defs+2,X
    CMP trace_y
    BNE ctt_next
    ; Hit! Set target_lit.
    TXA
    LSR A
    LSR A
    TAY
    LDA #1
    STA target_lit,Y
    LDX ctt_save_x
    SEC
    RTS

  .ctt_next
    TXA
    CLC
    ADC #TARGET_DEF_SIZE
    TAX
    JMP ctt_loop

  .ctt_miss
    LDX ctt_save_x
    CLC
    RTS


; Check if (trace_x, trace_y, trace_room) matches a portal with matching
; entry direction. If so, redirect: set trace_x/y/room/dir to paired
; portal exit, return C=1. Otherwise return C=0.
; Clobbers: A,Y
.check_trace_portal
    ; --- Check portal A ---
    LDA portal_a_enabled
    BEQ ctp_check_b
    LDA portal_a_room
    CMP trace_room
    BNE ctp_check_b
    LDA portal_a_x
    CMP trace_x
    BNE ctp_check_b
    LDA portal_a_y
    CMP trace_y
    BNE ctp_check_b
    LDY portal_a_orient
    CPY #PORTAL_ORIENT_BACK
    BEQ ctp_check_b
    LDA entry_dir_table,Y
    CMP trace_dir
    BNE ctp_check_b
    ; Redirect through portal B.
    LDA portal_b_enabled
    BEQ ctp_miss
    LDY portal_b_orient
    CPY #PORTAL_ORIENT_BACK
    BEQ ctp_miss
    LDA portal_b_x
    STA trace_x
    LDA portal_b_y
    STA trace_y
    LDA portal_b_room
    STA trace_room
    LDA exit_dir_table,Y
    STA trace_dir
    SEC
    RTS

  .ctp_check_b
    ; --- Check portal B ---
    LDA portal_b_enabled
    BEQ ctp_miss
    LDA portal_b_room
    CMP trace_room
    BNE ctp_miss
    LDA portal_b_x
    CMP trace_x
    BNE ctp_miss
    LDA portal_b_y
    CMP trace_y
    BNE ctp_miss
    LDY portal_b_orient
    CPY #PORTAL_ORIENT_BACK
    BEQ ctp_miss
    LDA entry_dir_table,Y
    CMP trace_dir
    BNE ctp_miss
    ; Redirect through portal A.
    LDA portal_a_enabled
    BEQ ctp_miss
    LDY portal_a_orient
    CPY #PORTAL_ORIENT_BACK
    BEQ ctp_miss
    LDA portal_a_x
    STA trace_x
    LDA portal_a_y
    STA trace_y
    LDA portal_a_room
    STA trace_room
    LDA exit_dir_table,Y
    STA trace_dir
    SEC
    RTS

  .ctp_miss
    CLC
    RTS


; Update signal state from target_lit flags.
; Called each frame from update_signals_and_object_states.
; Clobbers: A,X,Y
.update_beam_targets
    LDX #0
  .ubt_loop
    CPX #(TARGET_COUNT * TARGET_DEF_SIZE)
    BCS ubt_done
    ; target_index = X / TARGET_DEF_SIZE (=4)
    TXA
    LSR A
    LSR A
    TAY
    LDA target_lit,Y
    BEQ ubt_next
    ; Lit: OR channel bit into sig_state.
    LDA target_defs+3,X
    TAY
    LDA bit_table,Y
    ORA sig_state
    STA sig_state
  .ubt_next
    TXA
    CLC
    ADC #TARGET_DEF_SIZE
    TAX
    JMP ubt_loop
  .ubt_done
    RTS


; Range check: is A strictly between temp and temp_y?
; Input:  A = value, temp = bound1, temp_y = bound2
; Output: C=1 if min(b1,b2) < A < max(b1,b2), C=0 otherwise
; Clobbers: Y
.beam_range_check
    PHA
    LDY temp
    CPY temp_y
    BCC brc_ordered            ; temp < temp_y
    BEQ brc_fail_pop           ; equal — no gap
    ; temp > temp_y: swap.
    LDA temp_y
    STY temp_y
    STA temp
  .brc_ordered
    PLA
    CMP temp
    BEQ brc_fail
    BCC brc_fail               ; A <= lo
    CMP temp_y
    BCS brc_fail               ; A >= hi
    SEC
    RTS
  .brc_fail
    CLC
    RTS
  .brc_fail_pop
    PLA
    CLC
    RTS


; --- Local storage (not ZP) ---
.trace_room        SKIP 1
.trace_x           SKIP 1
.trace_y           SKIP 1
.trace_dir         SKIP 1
.trace_steps       SKIP 1
.trace_tile_off    SKIP 1
.trace_wall_x      SKIP 1
.trace_wall_y      SKIP 1
.trace_emitter_x   SKIP 1
.trace_emitter_y   SKIP 1
.beam_do_redraw    SKIP 1
.rab_laser_off     SKIP 1
.usbt_save_x       SKIP 1
.ctt_save_x        SKIP 1
