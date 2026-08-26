.spark_start
; spark.asm — High-energy spark.
;
; The spark replaces the laser as the thing that activates a collector.
; The beam is still traced and drawn exactly as before: it is the *rail*.
; The spark travels along that rail at Chell's speed, and only when it
; physically arrives at a target does the target latch on.
;
; This reuses the laser tracer's state machine rather than duplicating it.
; `trace_room/x/y/dir` are loaded from the spark's own position, then
; `check_trace_portal` and `check_trace_target` are called verbatim --
; so portal redirection and cross-room travel come for free.
;
; Only one spark is live at a time: the current room's.  Undiscovered rooms
; do not simulate a spark, and the respawn timer does not start until the
; room has actually been shown (see spark_arm).
;
; Movement is 2px/update at the 25Hz sim rate = 50 MODE 5 px/sec, matching
; WALK_VELOCITY.  Tiles are 8px wide and 16px tall, so a horizontal tile
; takes 4 updates to cross and a vertical tile takes 8 -- constant speed
; on both axes.

SPARK_LIFE_UPDATES  = 200       ; ~8s at 25Hz before it detonates
SPARK_RESPAWN_DELAY = 50        ; ~2s between detonation and the next spark
SPARK_SPEED         = 2         ; pixels per update

; spark_step_tile outcomes.
SPARK_MOVED     = 0
SPARK_COLLECTED = 1
SPARK_BOUNCED   = 2
SPARK_LOST      = 3

; --- Runtime state (only ever one live spark) ---
.spark_active    SKIP 1         ; 0 = none in flight, 1 = flying
.spark_room      SKIP 1
.spark_tx        SKIP 1         ; tile coords
.spark_ty        SKIP 1
.spark_dir       SKIP 1         ; LEFT=0 RIGHT=1 UP=2 DOWN=3
.spark_sub       SKIP 1         ; px travelled into the current tile
.spark_life      SKIP 1         ; updates left before it detonates
.spark_timer     SKIP 1         ; updates until the next spark is emitted
.spark_armed     SKIP 1         ; 0 until the room has been drawn once

; Scratch.
.spark_extent    SKIP 1         ; tile size along the travel axis (8 or 16)
.spark_outcome   SKIP 1


; --- Reset on level start -----------------------------------------------
; Disarms the emitter until its room has been shown.  This is per LEVEL,
; not per room: once armed the emitter keeps firing even while Chell is
; elsewhere, so a spark can travel through a portal into the room she is
; actually standing in.
; Clobbers: A
.spark_level_reset
    LDA #0
    STA spark_active
    STA spark_armed
    LDA #SPARK_RESPAWN_DELAY
    STA spark_timer
    RTS


; --- Arm the emitter -----------------------------------------------------
; Called after a room has been drawn.  Only the emitter's own room arms it:
; that is what keeps undiscovered rooms quiet.  Once armed it stays armed
; for the rest of the level.
; Clobbers: A
.spark_arm
    LDA laser_defs+0            ; emitter room
    CMP #&FF
    BEQ sa_done                 ; no laser on this level
    CMP current_room
    BNE sa_done                 ; some other room was drawn
    LDA #1
    STA spark_armed
  .sa_done
    RTS


; --- Per-update tick -----------------------------------------------------
; Called from the 25Hz gameplay update.
; Clobbers: A,X,Y and the trace_* scratch.
.spark_update
    LDA spark_armed
    BNE su_armed
    RTS
  .su_armed

    LDA spark_active
    BNE su_flying

    ; Idle: count down to the next emission.
    LDA spark_timer
    BEQ su_spawn
    DEC spark_timer
    RTS
  .su_spawn
    JMP spark_spawn

  .su_flying
    ; Lifetime.
    LDA spark_life
    BEQ su_detonate
    DEC spark_life

    JSR spark_axis_extent

    ; The sprite is 8px wide and 16px tall -- exactly one tile -- so as soon
    ; as the spark leaves an aligned position it is already drawn over the
    ; next tile.  Testing that tile only when spark_sub wraps is one tile too
    ; late: decide here, while it is still aligned, whether it may enter.
    LDA spark_sub
    BNE su_advance
    JSR spark_blocked_ahead
    BCC su_advance
    ; Blocked while aligned: turn around without moving.  No sub mirroring
    ; is needed because the spark is exactly on the tile boundary.
    LDA spark_dir
    EOR #1
    STA spark_dir
    RTS

  .su_advance
    ; Advance along the travel axis.
    LDA spark_sub
    CLC
    ADC #SPARK_SPEED
    STA spark_sub
    CMP spark_extent
    BCC su_done                 ; still inside this tile

    ; Crossed into the next tile.
    SEC
    SBC spark_extent
    STA spark_sub
    JSR spark_step_tile

    LDA spark_outcome
    CMP #SPARK_COLLECTED
    BEQ su_collected
    CMP #SPARK_BOUNCED
    BEQ su_bounce
    CMP #SPARK_LOST
    BEQ su_detonate
  .su_done
    RTS

  .su_bounce
    ; Same-axis reversal: LEFT<->RIGHT, UP<->DOWN (dir bit 0 flips).
    LDA spark_dir
    EOR #1
    STA spark_dir
    ; Snap back to the tile origin.  Mirroring spark_sub was right under the
    ; old edge-relative model but would now flip the spark 2*sub across its
    ; tile.  This path is a fallback -- spark_blocked_ahead turns the spark
    ; around while aligned -- so the snap is at most 6px and rarely seen.
    LDA #0
    STA spark_sub
    RTS

  .su_collected
    ; check_trace_target has already latched target_lit for us.
IF ENABLE_AUDIO AND ENABLE_SFX
    LDA #SFX_SPARK_COLLECT
    STA SFX_PENDING
ENDIF
    LDA #0
    STA spark_active
    LDA #SPARK_RESPAWN_DELAY
    STA spark_timer
    RTS

  .su_detonate
IF ENABLE_AUDIO AND ENABLE_SFX
    LDA #SFX_SPARK_CRASH
    STA SFX_PENDING
ENDIF
    LDA #0
    STA spark_active
    LDA #SPARK_RESPAWN_DELAY
    STA spark_timer
    RTS


; --- Tile extent along the current travel axis ---------------------------
; Horizontal tiles are 8px, vertical 16px.  Result in spark_extent.
; Clobbers: A
.spark_axis_extent
    LDA spark_dir
    CMP #2
    BCC sae_horiz               ; dir 0/1 = horizontal
    LDA #16
    STA spark_extent
    RTS
  .sae_horiz
    LDA #8
    STA spark_extent
    RTS


; --- Emit a spark at the level's emitter ---------------------------------
; LASER_COUNT is 1, so there is a single emitter to consider.  It only
; emits while Chell is in its room.
; Clobbers: A
.spark_spawn
    LDA laser_defs+0            ; room
    CMP #&FF                    ; unused slot: no laser on this level
    BEQ ss_none

    ; Emit into the emitter's own room whatever room Chell is in -- the
    ; spark has to be able to travel through a portal into her room.
    STA spark_room
    LDA laser_defs+5            ; emitter_x
    STA spark_tx
    LDA laser_defs+6            ; emitter_y
    STA spark_ty
    LDA laser_defs+3            ; dir
    STA spark_dir
    LDA #0
    STA spark_sub
    LDA #SPARK_LIFE_UPDATES
    STA spark_life
    LDA #1
    STA spark_active
    RTS

  .ss_none
    ; Nothing to emit here; check again after the usual delay.
    LDA #SPARK_RESPAWN_DELAY
    STA spark_timer
    RTS


; --- Advance one tile ----------------------------------------------------
; Steps the spark one tile along spark_dir, reusing the laser tracer's
; portal and target routines.  Result in spark_outcome.
;
; Order mirrors the beam: a non-solid tile may hold a target, and a solid
; tile may hold a portal (portals sit on wall tiles).
;
; Clobbers: A,X,Y, trace_*, sprite_ptr.
.spark_step_tile
    JSR tilemap_bank_in

    ; Load the spark's position into the tracer's working state.
    LDA spark_room : STA trace_room
    LDA spark_tx   : STA trace_x
    LDA spark_ty   : STA trace_y
    LDA spark_dir  : STA trace_dir

    ; Advance one tile.
    LDY trace_dir
    LDA trace_x
    CLC
    ADC dir_dx_table,Y
    STA trace_x
    LDA trace_y
    CLC
    ADC dir_dy_table,Y
    STA trace_y

    ; Off the edge of the room?  Follow an authored edge exit if there is
    ; one, otherwise the spark is lost.
    LDA trace_x
    CMP #16
    BCC sst_x_ok
    JSR trace_cross_room_edge
    BCC sst_lost
    JMP sst_have_tile
  .sst_x_ok
    LDA trace_y
    CMP #16
    BCC sst_y_ok
    JSR trace_cross_room_edge
    BCC sst_lost
    JMP sst_have_tile
  .sst_y_ok

  .sst_have_tile
    ; Fetch the tile at (trace_x, trace_y) in trace_room.
    LDA trace_room
    ASL A
    TAX
    LDA room_pointers,X
    STA sprite_ptr
    LDA room_pointers+1,X
    STA sprite_ptr+1
    LDA trace_y
    ASL A
    ASL A
    ASL A
    ASL A
    ORA trace_x
    TAY
    LDA (sprite_ptr),Y

    AND #&20                    ; bit 5 = solid
    BNE sst_solid

    ; Open tile.  Floor and ceiling portals sit on an *empty* tile, unlike
    ; wall portals which sit on the solid wall -- so the portal check has to
    ; happen on this branch as well.  This mirrors the beam tracer, which
    ; calls check_trace_portal from tdb_no_target.  Without it a spark
    ; falling out of a ceiling portal bounces off the floor, comes back up
    ; into the portal tile, fails to recognise it, and ping-pongs forever.
    JSR check_trace_portal
    BCS sst_moved
    ; Otherwise a collector may be sitting here.  check_trace_target
    ; latches target_lit itself when it hits.
    JSR check_trace_target
    BCS sst_collected
    JMP sst_moved

  .sst_solid
    ; Solid: a portal on this wall tile redirects us, otherwise we bounce.
    JSR check_trace_portal
    BCS sst_moved               ; redirected; trace_* now holds the exit
    LDA #SPARK_BOUNCED
    STA spark_outcome
    JMP sst_out                 ; position unchanged -- caller flips dir

  .sst_moved
    LDA #SPARK_MOVED
    STA spark_outcome
    JMP sst_commit

  .sst_collected
    LDA #SPARK_COLLECTED
    STA spark_outcome
    JMP sst_commit

  .sst_lost
    LDA #SPARK_LOST
    STA spark_outcome
    JMP sst_out

  .sst_commit
    ; Write the tracer's updated position back to the spark.
    LDA trace_room : STA spark_room
    LDA trace_x    : STA spark_tx
    LDA trace_y    : STA spark_ty
    LDA trace_dir  : STA spark_dir

  .sst_out
    JSR tilemap_bank_out
    RTS


; =========================================================================
; Rendering
; =========================================================================
;
; The spark is an ordinary member of the sprite stack: drawn last, and so
; restored first (LIFO peel).  That is what lets it overlap Chell and the
; reticle without any of them having to be force-redrawn -- Chell only
; repaints when she actually moves.
;
; An earlier version erased by repainting the tiles underneath instead.
; That reads current tilemap state, so it never goes stale, but background
; repainting requires every overlapping sprite to be peeled off first --
; which meant forcing chell_dirty on every frame a spark was on screen.
; The save-under is stale only when the background changes underneath it,
; and that case is already handled: pre_render_bg_patch peels the spark and
; drops its buffer before patching, exactly as it does for the other two.

SPARK_SAVE_UNDER_BASE = &7980   ; 16x16 = 64 bytes, LYNNE scratch above screen

.spark_has_under  SKIP 1        ; 1 = SPARK_SAVE_UNDER_BASE holds live pixels
.spark_prev_ptr   SKIP 2        ; where those pixels came from
.spark_stripes    SKIP 1        ; 2, or 3 when a vertical phase straddles a band
.spark_px         SKIP 1        ; pixel position of the current stamp
.spark_py         SKIP 1


; --- Pixel position from tile position + sub-tile offset ----------------
; spark_sub is distance travelled along spark_dir into the current tile,
; so the offset is measured from whichever edge the spark entered by.
; Result in spark_px (0..127) and spark_py (0..255).
; Clobbers: A
.spark_compute_pos
    LDA spark_dir
    CMP #2
    BCS scp_vert

    ; Horizontal: y is tile-aligned, x carries the sub-tile offset.
    LDA spark_ty
    ASL A : ASL A : ASL A : ASL A
    STA spark_py
    LDA spark_tx
    ASL A : ASL A : ASL A
    STA spark_px
    LDA spark_dir
    BNE scp_right
    ; LEFT: sub measures distance moved away from the tile origin, so it
    ; subtracts.  At sub=0 the spark sits exactly on its tile, which is what
    ; makes the position continuous across a step in either direction.
    LDA spark_px
    SEC
    SBC spark_sub
    STA spark_px
    RTS
  .scp_right
    LDA spark_px
    CLC
    ADC spark_sub
    STA spark_px
    RTS

  .scp_vert
    ; Vertical: x is tile-aligned, y carries the offset.  The drawn y is
    ; exact -- pre-shifted vertical phases (obj_sparkv_y0/2/4/6) cover the
    ; sub-band positions, so no snapping is needed.
    LDA spark_tx
    ASL A : ASL A : ASL A
    STA spark_px
    LDA spark_ty
    ASL A : ASL A : ASL A : ASL A
    STA spark_py
    LDA spark_dir
    CMP #3
    BEQ scp_down
    ; UP: subtracts, for the same reason as LEFT.
    LDA spark_py
    SEC
    SBC spark_sub
    STA spark_py
    RTS
  .scp_down
    LDA spark_py
    CLC
    ADC spark_sub
    STA spark_py
    RTS


; spark_save_under / spark_restore_under live in mode5/render.asm, not here.
; They set ACCCON X=1, which maps LYNNE over &3000-&7FFF -- so they must
; execute from below &3000 or the CPU starts fetching screen memory.  This
; section sits at &66xx.

; --- Draw ---------------------------------------------------------------
; Saves the background then stamps the spark, if it is in flight and in the
; room on screen.  Must always be preceded by spark_restore_under, or the
; save would capture the spark's own pixels.
; Clobbers: A,X,Y and the stamper's scratch.
.spark_draw
    ; Early exits are far from sd_ret now, so bail directly.
    LDA spark_active
    BNE sd_active
    RTS
  .sd_active
    LDA spark_room
    CMP current_room
    BEQ sd_onscreen
    RTS
  .sd_onscreen

    JSR spark_compute_pos

    ; screen_ptr = &5800 + (py/8)*256 + (px/4)*8
    ; A memory cell is 4px wide x 8 rows = 8 bytes, and the narrowed
    ; playfield is 32 cells = 256 bytes per band.
    LDA spark_py
    LSR A : LSR A : LSR A
    CLC
    ADC #&58
    STA screen_ptr+1
    LDA spark_px
    AND #&FC
    ASL A
    STA screen_ptr

    ; A 16-row sprite covers two 8-row stripes when it sits on a band
    ; boundary, three when a vertical phase pushes it off one.
    LDA #2
    STA spark_stripes
    LDA spark_dir
    CMP #2
    BCC sd_have_stripes         ; horizontal: y is always band-aligned
    LDA spark_py
    AND #7
    BEQ sd_have_stripes
    ; A third stripe from band 30 onwards would run past &77FF into the
    ; Chell/reticle save-under buffers at &7800.  Walls should stop the
    ; spark long before that, but clip rather than corrupt them.
    LDA screen_ptr+1
    CMP #&76
    BCS sd_have_stripes
    LDA #3
    STA spark_stripes
  .sd_have_stripes

    ; Save the background before anything is stamped over it.  This has to
    ; precede the sprite selection because it borrows sprite_ptr as scratch.
    JSR spark_save_under
    LDA screen_ptr   : STA spark_prev_ptr
    LDA screen_ptr+1 : STA spark_prev_ptr+1
    LDA #1
    STA spark_has_under

    LDA spark_dir
    CMP #2
    BCS sd_vert

    ; --- Horizontal: x carries the phase, so the two frames double as the
    ; two x-phases and the spark animates as a side effect of travelling.
    LDA spark_px
    AND #3
    BEQ sd_x0
    LDA #<obj_spark_x2      : STA sprite_ptr
    LDA #>obj_spark_x2      : STA sprite_ptr+1
    LDA #<obj_spark_x2_mask : STA mask_ptr
    LDA #>obj_spark_x2_mask : STA mask_ptr+1
    JMP sd_stamp
  .sd_x0
    LDA #<obj_spark_x0      : STA sprite_ptr
    LDA #>obj_spark_x0      : STA sprite_ptr+1
    LDA #<obj_spark_x0_mask : STA mask_ptr
    LDA #>obj_spark_x0_mask : STA mask_ptr+1
    JMP sd_stamp

  .sd_vert
    ; --- Vertical: y carries the phase.  gen-sprites cycles the two source
    ; frames across the four phases, so the animation keeps running here too
    ; -- which it did not when the frame was tied to the x-phase.
    LDA spark_py
    AND #7
    LSR A
    TAX
    LDA spark_y_sprite_lo,X : STA sprite_ptr
    LDA spark_y_sprite_hi,X : STA sprite_ptr+1
    LDA spark_y_mask_lo,X   : STA mask_ptr
    LDA spark_y_mask_hi,X   : STA mask_ptr+1

  .sd_stamp
    ; Sprite data lives in the object SWRAM bank.  Page it in via &F4 (the
    ; OS's RAM copy of the current bank) as well as ROMSEL -- &FE30 does not
    ; read back reliably, so saving it by reading the register restores
    ; garbage and leaves the wrong bank mapped for everything downstream.
    PHP
    SEI
    LDA &F4
    STA saved_romsel
    LDA obj_bank
    STA &F4
    STA ROMSEL

    LDA spark_stripes
    LDX #32                     ; 32 bytes per stripe (16px wide)
    LDY #32
    JSR stamp_striped_masked

    LDA saved_romsel
    STA &F4
    STA ROMSEL
    PLP
  .sd_ret
    RTS


; Vertical phase -> pre-shifted sprite.  Indexed by (py & 7) / 2.
.spark_y_sprite_lo
    EQUB <obj_sparkv_y0, <obj_sparkv_y2, <obj_sparkv_y4, <obj_sparkv_y6
.spark_y_sprite_hi
    EQUB >obj_sparkv_y0, >obj_sparkv_y2, >obj_sparkv_y4, >obj_sparkv_y6
.spark_y_mask_lo
    EQUB <obj_sparkv_y0_mask, <obj_sparkv_y2_mask, <obj_sparkv_y4_mask, <obj_sparkv_y6_mask
.spark_y_mask_hi
    EQUB >obj_sparkv_y0_mask, >obj_sparkv_y2_mask, >obj_sparkv_y4_mask, >obj_sparkv_y6_mask


; --- Look ahead one tile ------------------------------------------------
; Is the tile one step along spark_dir enterable?
; Output: C=1 if blocked -- solid, with no portal offering a way through.
; Out-of-bounds reads as clear: spark_step_tile handles room edges, and a
; wall normally stops the spark before it gets there.
; Clobbers: A,X,Y, trace_*, sprite_ptr
.spark_blocked_ahead
    JSR tilemap_bank_in

    LDA spark_room : STA trace_room
    LDA spark_tx   : STA trace_x
    LDA spark_ty   : STA trace_y
    LDA spark_dir  : STA trace_dir

    LDY trace_dir
    LDA trace_x
    CLC
    ADC dir_dx_table,Y
    STA trace_x
    LDA trace_y
    CLC
    ADC dir_dy_table,Y
    STA trace_y

    LDA trace_x
    CMP #16
    BCS sba_clear
    LDA trace_y
    CMP #16
    BCS sba_clear

    LDA trace_room
    ASL A
    TAX
    LDA room_pointers,X   : STA sprite_ptr
    LDA room_pointers+1,X : STA sprite_ptr+1
    LDA trace_y
    ASL A : ASL A : ASL A : ASL A
    ORA trace_x
    TAY
    LDA (sprite_ptr),Y
    AND #&20                    ; bit 5 = solid
    BEQ sba_clear

    ; Solid -- but a wall portal is a way through, not a wall.  This mutates
    ; trace_*, which is fine: the real redirect happens in spark_step_tile
    ; when the spark actually crosses.
    JSR check_trace_portal
    BCS sba_clear

    ; tilemap_bank_out restores flags via PLP, so set carry after it.
    JSR tilemap_bank_out
    SEC
    RTS

  .sba_clear
    JSR tilemap_bank_out
    CLC
    RTS


; --- Contact with Chell -------------------------------------------------
; Instant death, matching the sentry killzones.  Runs alongside the spark's
; movement rather than under the frozen-time branch, so the reticle cannot
; be used to sit safely inside a spark.
; Clobbers: A, temp, los_dx, los_dy
.spark_check_chell
    LDA spark_active
    BNE scc_live
    RTS
  .scc_live
    LDA spark_room
    CMP current_room
    BEQ scc_here
    RTS
  .scc_here
    LDA char_dead
    BEQ scc_alive
    RTS
  .scc_alive

    JSR spark_compute_pos

    ; AABB: Chell (x, y, x+15, y+31) vs spark (px, py, px+8, py+16).
    ; Far edges exclusive -- same convention as check_killzones.
    JSR calc_char_x
    STA los_dx
    JSR calc_char_y
    STA los_dy

    ; chell_right >= spark_left
    LDA los_dx
    CLC
    ADC #15
    CMP spark_px
    BCC scc_miss

    ; chell_left < spark_right
    LDA spark_px
    CLC
    ADC #8
    STA temp
    LDA los_dx
    CMP temp
    BCS scc_miss

    ; chell_bottom >= spark_top
    LDA los_dy
    CLC
    ADC #31
    CMP spark_py
    BCC scc_miss

    ; chell_top < spark_bottom.  A spark low on the screen can push this
    ; past 255; the carry means its bottom edge is off-screen, so Chell's
    ; top is unconditionally above it.
    LDA spark_py
    CLC
    ADC #16
    BCS scc_hit
    STA temp
    LDA los_dy
    CMP temp
    BCS scc_miss

  .scc_hit
    LDA #1
    STA char_dead
    STA chell_dirty
    LDA keys_held
    STA keys_prev
    LDA action_held
    STA action_prev
  .scc_miss
    RTS
