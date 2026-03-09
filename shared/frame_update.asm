.frame_update_start
; Per-frame update helpers.


; If SHIFT is held and Chell is stable, run reticle-mode update.
; Output:
; - C=1 if reticle mode handled (gameplay frozen this frame)
; - C=0 if caller should run normal-mode update
.maybe_update_reticle_mode
    ; Reticle mode is held (SHIFT), but only allowed when Chell is stable.
    ; Strictly one or the other:
    ; - If Chell is moving vertically (jump/fall), reticle cannot become active.
    LDA keys_held
    AND #8
    BNE murm_shift_ok
    ; Ensure reticle deactivates immediately when SHIFT is not held.
    LDA reticle_active
    BEQ murm_shift_clear_done
    LDA #0
    STA reticle_active
    LDA #1
    STA reticle_dirty
  .murm_shift_clear_done
    CLC
    RTS


  .murm_shift_ok

    LDA char_grounded
    BNE murm_ground_ok
    CLC
    RTS
  .murm_ground_ok
    LDA char_vy
    BEQ murm_stable_ok
    CLC
    RTS
  .murm_stable_ok

    ; Reticle active while SHIFT held and Chell is stable.
    LDA #1
    STA reticle_active

    JSR poll_reticle_keys
    BCC murm_reticle_no_dirty
    LDA #1
    STA reticle_dirty
  .murm_reticle_no_dirty

    ; Portal placement while in reticle mode.
    ; Use keys_pressed edge; only place when reticle is valid (green).
    LDA reticle_state
    BEQ murm_reticle_place_done

    ; Prefer Portal A if both pressed.
    LDA keys_pressed
    AND #&40
    BEQ murm_reticle_check_place_b
    LDA #0
    JSR place_portal_from_reticle
    JMP murm_reticle_place_done

 .murm_reticle_check_place_b
    LDA keys_pressed
    AND #&80
    BEQ murm_reticle_place_done
    LDA #1
    JSR place_portal_from_reticle

 .murm_reticle_place_done
    SEC
    RTS

.murm_not_active
    CLC
    RTS


; Normal mode: handle reticle deactivation, movement, and gravity.
 .update_normal_mode
     ; If reticle was active last frame, the A/S key edges in keys_pressed
     ; belong to reticle-mode placement.  Clear them so handle_quick_shot
     ; doesn't fire a spurious quick-shot on the SHIFT-release frame.
     LDA reticle_prev_active
     BEQ unm_qs_ok
     LDA keys_pressed
      AND #&3F
     STA keys_pressed
  .unm_qs_ok

     ; Quick-shot portal firing (outside reticle mode).
    JSR handle_quick_shot

    ; Cube pickup/drop is deferred to the main loop (after portal entry)
    ; so that SPACE prioritises back-wall portal entry over cube drop.

    ; Keep the physics solidity plane up to date (tiles + standable objects).
    ; This lets Chell stand on cubes.
    JSR rebuild_solid_phys_plane

    ; If we just released SHIFT, deactivate reticle and mark it dirty so render
    ; can restore its last rectangle.
    LDA reticle_active
    BEQ unm_skip_hide
    LDA #0
    STA reticle_active

    LDA reticle_prev_active
    BEQ unm_skip_hide
    LDA #1
    STA reticle_dirty
 .unm_skip_hide

    ; Normal mode: input -> update horizontal movement/anim.
    JSR update_chell_movement
    BCC unm_skip_dirty_move
    LDA #1
    STA chell_dirty
 .unm_skip_dirty_move

    ; Physics -> update vertical position.
    JSR apply_gravity
    BCC unm_done
    LDA #1
    STA chell_dirty

 .unm_done
     ; Track a 3-state pose so any transition forces a redraw:
     ;   0 = grounded, 1 = airborne/jump, 2 = airborne/fall.
     ; Previous bug: jump and grounded were both 0, so landing from
     ; a short hop (never reaching fall threshold) was invisible.
     LDA chell_air_pose
     STA temp
 
     LDA #0                    ; assume grounded
     STA chell_air_pose
 
     LDA char_grounded
     BNE unm_pose_check        ; grounded -> stays 0
 
     LDA #1                    ; airborne: default to jump pose
     STA chell_air_pose
 
     LDA char_vy
     BMI unm_pose_check        ; rising -> keep 1 (jump)
     CMP #FALL_POSE_VY_THRESHOLD
     BCC unm_pose_check        ; slow descent -> keep 1 (jump)
     LDA #2                    ; fast descent -> fall pose
     STA chell_air_pose
 
 .unm_pose_check
     LDA chell_air_pose
     CMP temp
     BEQ unm_pose_done
     LDA #1
     STA chell_dirty
 .unm_pose_done
     RTS


; Sets dirty_flag if redraw is needed.
 .compute_dirty_flag
    ; Dirty flag for next frame.
    ; - If Chell is dirty, we must redraw Chell.
    ; - If reticle is active and (reticle_dirty or chell_dirty), redraw reticle.
    ; - If reticle just deactivated and had under saved, restore it.
    ; Note: portal_pending/objects_pending are consumed pre-vsync in
    ; pre_render_bg_patch, so they are always 0 here.  Their background
    ; work forces chell_dirty=1, which is picked up below.

    LDA #0
    STA dirty_flag

    ; Room redraw requested (room transition).
    LDA room_dirty
    BEQ df_skip_room
    LDA #1
    STA dirty_flag
 .df_skip_room

    LDA chell_dirty
    BEQ df_skip_chell
    LDA #1
    STA dirty_flag
 .df_skip_chell

     LDA reticle_active
     BEQ df_reticle_off
    LDA reticle_dirty
    ORA chell_dirty
    BEQ df_done
    LDA #1
    STA dirty_flag
    JMP df_done

 .df_reticle_off
    LDA reticle_prev_active
    BEQ df_done
    LDA reticle_has_under
    BEQ df_done
    LDA #1
    STA dirty_flag

    ; Sentry bullets on screen need render cycle to erase/redraw.
    LDA bullet_count
    BEQ df_done
    LDA #1
    STA dirty_flag

 .df_done
     RTS


; Check if Chell overlaps an acid/goo tile. If so, restart the level.
;
; char_tile_pos encodes (cell_y << 4 | cell_x), which is also the tilemap
; index for Chell's top-left tile. Chell is 2x2 tiles. If char_y_offset != 0
; she straddles a third row, so we check that too.
;
; Clobbers: A,Y
.check_acid_death
    ; Top-left tile
    LDY char_tile_pos
    LDA (tilemap_ptr),Y
    CMP #TILE_ACID
    BEQ acid_death

    ; Top-right tile (x+1)
    INY
    LDA (tilemap_ptr),Y
    CMP #TILE_ACID
    BEQ acid_death

    ; Bottom-left tile (y+1): index + 15 = (x+1) + 15 = next row, same x
    TYA
    CLC
    ADC #15
    TAY
    LDA (tilemap_ptr),Y
    CMP #TILE_ACID
    BEQ acid_death

    ; Bottom-right tile (y+1, x+1)
    INY
    LDA (tilemap_ptr),Y
    CMP #TILE_ACID
    BEQ acid_death

    ; If y_offset != 0, Chell straddles a third row.
    LDA char_y_offset
    BEQ cad_safe

    ; Third row left
    TYA
    CLC
    ADC #15
    TAY
    ; Guard: don't read past tilemap (y+2 row could be off-screen)
    CPY #0
    BEQ cad_safe         ; wrapped past 255
    LDA (tilemap_ptr),Y
    CMP #TILE_ACID
    BEQ acid_death

    ; Third row right
    INY
    BEQ cad_safe         ; wrapped past 255
    LDA (tilemap_ptr),Y
    CMP #TILE_ACID
    BEQ acid_death

  .cad_safe
    RTS

  .acid_death
    LDA #1
    STA char_dead
    STA chell_dirty
    ; Snapshot current held keys so they don't immediately trigger restart.
    LDA keys_held
    STA keys_prev
    LDA action_held
    STA action_prev
    RTS


; Check if Chell overlaps any active killzone in the current room.
; Each killzone record is 5 bytes: x0, y0, x1, y1, sentry_obj_index.
; A killzone only kills if its linked sentry is active (not carried/disabled).
;
; Uses LOS scratch ZP (safe — LOS not active during normal update).
; Clobbers: A,X,Y,los_x0,los_y0,los_x1,los_y1,los_dx,los_dy,los_err
.check_killzones
    LDA room_killzone_count
    BEQ ckz_none

    ; Copy non-ZP pointer into ZP for indirect addressing.
    LDA room_killzone_ptr
    STA temp_sprite_ptr
    LDA room_killzone_ptr+1
    STA temp_sprite_ptr+1

    ; Compute Chell pixel position.
    JSR calc_char_x           ; A = pixel_x (0..115)
    STA los_x0                ; chell_left_x
    JSR calc_char_y           ; A = pixel_y (0..248)
    STA los_y0                ; chell_top_y

    LDY #0
    LDX room_killzone_count
.ckz_loop
    ; Load killzone bounds from (temp_sprite_ptr),Y
    ; Format: x0, y0, x1, y1, sentry_obj_index (5 bytes)
    LDA (temp_sprite_ptr),Y : INY : STA los_x1   ; kz_x0
    LDA (temp_sprite_ptr),Y : INY : STA los_y1   ; kz_y0
    LDA (temp_sprite_ptr),Y : INY : STA los_dx   ; kz_x1
    LDA (temp_sprite_ptr),Y : INY : STA los_dy   ; kz_y1
    LDA (temp_sprite_ptr),Y : INY                 ; sentry_obj_index
    STY los_err                                      ; save Y

    ; Check if sentry is active: skip if carried or disabled (state != 0
    ; apart from direction bit 0).
    TAY
    LDA obj_state,Y
    AND #&FE                  ; mask out direction bit
    BNE ckz_next              ; non-zero = carried/disabled, skip

    ; AABB: Chell (x, y, x+15, y+31) vs killzone (x0, y0, x1, y1)
    ; x1/y1 are exclusive.

    ; Test 1: chell_right (x+15) >= kz_x0
    LDA los_x0
    CLC
    ADC #15
    CMP los_x1
    BCC ckz_next

    ; Test 2: chell_left < kz_x1
    LDA los_x0
    CMP los_dx
    BCS ckz_next

    ; Test 3: chell_bottom (y+31) >= kz_y0
    LDA los_y0
    CLC
    ADC #31
    CMP los_y1
    BCC ckz_next

    ; Test 4: chell_top < kz_y1
    LDA los_y0
    CMP los_dy
    BCS ckz_next

    ; --- OVERLAP: kill Chell ---
    LDA #1
    STA char_dead
    STA chell_dirty
    LDA keys_held
    STA keys_prev
    LDA action_held
    STA action_prev
    RTS

.ckz_next
    LDY los_err
    DEX
    BNE ckz_loop
.ckz_none
    RTS


; Check if Chell or any cube collides with an active sentry.
; On collision: disable the sentry (set SENTRY_STATE_DISABLED).
; Uses tile-based AABB overlap (both sides 2 tiles wide).
; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter
.check_sentry_collisions
    LDY #0
.csc_loop
    CPY #OBJ_COUNT
    BCC csc_not_done
    RTS
.csc_not_done
    LDA obj_type,Y
    CMP #OBJ_TYPE_SENTRY
    BEQ csc_is_sentry
    JMP csc_next
.csc_is_sentry
    LDA obj_state,Y
    AND #&FE              ; mask direction
    BEQ csc_active        ; zero = active
    JMP csc_next
.csc_active
    LDA obj_room,Y
    CMP current_room
    BEQ csc_in_room
    JMP csc_next
.csc_in_room

    ; --- Active sentry in current room ---
    ; Check Chell overlap (tile-based).
    ; Chell tile pos: cx = char_tile_pos AND 15, cy = char_tile_pos >> 4
    ; Chell footprint: 2 wide, 2 tall => tiles (cx..cx+1, cy..cy+1)
    ; Sentry footprint: 2 wide, 1 tall => tiles (sx..sx+1, sy)
    LDA char_tile_pos
    AND #15
    STA temp              ; chell_tx
    LDA char_tile_pos
    LSR A : LSR A : LSR A : LSR A
    STA temp_y            ; chell_ty

    ; X overlap: |cx - sx| <= 1
    LDA obj_x,Y
    SEC : SBC temp
    BPL csc_cx_abs
    EOR #&FF : CLC : ADC #1
.csc_cx_abs
    CMP #2 : BCS csc_check_cubes

    ; Y overlap: chell_ty <= sy <= chell_ty+1
    LDA obj_y,Y
    CMP temp_y : BCC csc_check_cubes
    LDA temp_y
    CLC : ADC #2
    CMP obj_y,Y : BCC csc_check_cubes
    BEQ csc_check_cubes

    ; Chell hit sentry — disable it.
    JMP csc_disable

.csc_check_cubes
    ; Check all cubes in current room vs this sentry.
    STY row_counter       ; save sentry index
    LDX #0
.csc_cube_loop
    CPX #OBJ_COUNT
    BCS csc_cube_done
    LDA obj_type,X
    CMP #OBJ_TYPE_CUBE
    BNE csc_cube_next
    LDA obj_state,X
    AND #OBJ_STATE_CARRIED
    BNE csc_cube_next
    LDA obj_room,X
    CMP current_room
    BNE csc_cube_next

    ; Cube at same y as sentry?
    LDA obj_y,X
    CMP obj_y,Y
    BNE csc_cube_next

    ; X overlap: |cube_x - sentry_x| <= 1
    LDA obj_x,X
    SEC : SBC obj_x,Y
    BPL csc_cube_abs
    EOR #&FF : CLC : ADC #1
.csc_cube_abs
    CMP #2 : BCS csc_cube_next

    ; Cube hit sentry — disable it.
    LDY row_counter
    JMP csc_disable

.csc_cube_next
    INX
    JMP csc_cube_loop
.csc_cube_done
    LDY row_counter       ; restore sentry index

.csc_next
    INY
    JMP csc_loop
.csc_done
    RTS

.csc_disable
    LDA obj_state,Y
    ORA #SENTRY_STATE_DISABLED
    STA obj_state,Y
    LDA #1
    STA objects_pending
    STA obj_dirty,Y
    JMP csc_next


; Check if Chell overlaps any fizzler region in the current room.
; On contact: clear both portals, destroy carried cube.
; Skips entirely if there's nothing to fizzle (no portals, no cube).
;
; Uses LOS scratch ZP (safe — LOS not active during normal update).
; Clobbers: A,X,Y,los_x0,los_y0,los_x1,los_y1,los_dx,los_dy,los_err
.check_fizzler_contact
    ; Clear fizzler signal for this frame.
    LDA #0
    STA fizzler_signal

    LDA room_fizzler_count
    BEQ cfz_none

    ; Early exit: anything to fizzle?
    LDA portal_a_enabled
    ORA portal_b_enabled
    BNE cfz_has_work
    LDA carried_cube_idx
    CMP #&FF
    BEQ cfz_none              ; nothing to clear → skip
.cfz_has_work

    ; Compute Chell pixel position.
    JSR calc_char_x           ; A = pixel_x (0..115)
    STA los_x0                ; chell_left_x
    JSR calc_char_y           ; A = pixel_y (0..248)
    STA los_y0                ; chell_top_y

    LDY #0
    LDX room_fizzler_count
.cfz_loop
    ; Load fizzler bounds from (room_fizzler_ptr),Y
    ; Format: x0, y0, x1, y1, channel (5 bytes per fizzler)
    LDA (room_fizzler_ptr),Y : INY : STA los_x1   ; fiz_x0
    LDA (room_fizzler_ptr),Y : INY : STA los_y1   ; fiz_y0
    LDA (room_fizzler_ptr),Y : INY : STA los_dx   ; fiz_x1
    LDA (room_fizzler_ptr),Y : INY : STA los_dy   ; fiz_y1
    INY                                             ; skip channel (read on hit)
    STY los_err                                     ; save Y (past channel)

    ; AABB: Chell (x, y, x+15, y+31) vs fizzler (x0, y0, x1, y1)
    ; x1/y1 are exclusive, so test: chell_right >= fiz_x0 AND chell_left < fiz_x1
    ;                                chell_bottom >= fiz_y0 AND chell_top < fiz_y1

    ; Test 1: chell_right (x+15) >= fiz_x0
    LDA los_x0
    CLC
    ADC #15
    CMP los_x1
    BCC cfz_next

    ; Test 2: chell_left < fiz_x1
    LDA los_x0
    CMP los_dx
    BCS cfz_next

    ; Test 3: chell_bottom (y+31) >= fiz_y0
    LDA los_y0
    CLC
    ADC #31
    CMP los_y1
    BCC cfz_next

    ; Test 4: chell_top < fiz_y1
    LDA los_y0
    CMP los_dy
    BCS cfz_next

    ; --- OVERLAP: trigger fizzler ---
    ; Read channel byte from the fizzler that matched (1 byte before saved Y).
    LDY los_err
    DEY
    LDA (room_fizzler_ptr),Y  ; channel index (0-7)
    TAY
    LDA bit_table,Y
    ORA fizzler_signal
    STA fizzler_signal

    JMP cfz_trigger

.cfz_next
    LDY los_err
    DEX
    BNE cfz_loop
.cfz_none
    RTS

.cfz_trigger
    ; Surgically erase portal visuals, clear state, retrace beams.
    JSR fizzle_clear_portals

    ; Destroy carried cube (fizzle it out of existence).
    LDA carried_cube_idx
    CMP #&FF
    BEQ cfz_no_cube

    TAY
    LDA #0
    STA obj_state,Y           ; clear all state flags
    LDA #&FF
    STA obj_room,Y            ; despawn: no room
    STA carried_cube_idx      ; no longer carrying

    LDA #1
    STA objects_pending

.cfz_no_cube
    RTS


 ; Quick-shot portal placement (outside reticle mode).
 ;
 ; - On A/S key-down, fire a projected shot (tiles only) and place portal A/B.
 ; - Direction uses aim_held (0=straight, 1=up, 2=down) and anim_dir.
 ; - Disallows back-wall placement.
 ;
 ; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter
  .handle_quick_shot
      ; Use edge-triggered keys for quick-shot.
      LDA keys_pressed
      AND #&C0
      BNE hqs_have_newpress
      JMP hqs_done
   .hqs_have_newpress

      ; Prefer A if both were pressed.
      LDA keys_pressed
      AND #&40
      BEQ hqs_try_b
      LDA #0
      JMP hqs_have_kind

   .hqs_try_b
      LDA keys_pressed
      AND #&80
      BEQ hqs_done_far
      LDA #1
      JMP hqs_have_kind

   .hqs_done_far
      JMP hqs_done

   .hqs_have_kind
      ; Keep raycast scratch stable (B2/MOS IRQs can clobber ZP).
      ; Preserve caller IRQ state (nested callers may already be SEI).
      PHP
      SEI

      ; Stash requested portal kind.
      STA portal_kind

      ; Debug palette flash disabled.

     ; Ray start (gun point), matching reticle LOS.
     JSR calc_char_x
     STA temp
      LDA anim_dir
      BNE hqs_gun_right
      ; facing left
      LDA temp
      CLC
      ADC #3
      STA los_x0
      JMP hqs_gun_x_nudge
    .hqs_gun_right
      LDA temp
      CLC
      ADC #10
      STA los_x0

   .hqs_gun_x_nudge
      ; If the gun point lands exactly on an 8px boundary, nudge it 1px
      ; toward the shot direction to reduce boundary-bias asymmetry.
      LDA los_x0
      AND #7
      BNE hqs_gun_y
      LDA anim_dir
      BNE hqs_nudge_right
      ; nudge left
      LDA los_x0
      BEQ hqs_gun_y
      DEC los_x0
      JMP hqs_gun_y
   .hqs_nudge_right
      LDA los_x0
      CMP #127
      BEQ hqs_gun_y
      INC los_x0

    .hqs_gun_y
      JSR calc_char_y
     CLC
     ADC #12
     STA los_y0

      ; While falling, always quick-shot a portal directly below Chell.
      ; This ignores aim_held and prefers the first floor surface under the column.
      LDA char_grounded
      BNE hqs_not_falling
      LDA char_vy
      BMI hqs_not_falling
      BEQ hqs_not_falling

      ; Ray target: straight down to bottom of playfield.
      ; Use center of Chell's registered tile X (avoids subpixel boundary drift).
      LDA char_tile_pos
      AND #15
      ASL A : ASL A : ASL A   ; cell_x * 8 = left pixel of tile
      CLC
      ADC #4                   ; center of tile (never on 8px boundary)
      STA los_x0

      LDA los_x0
      STA los_x1
      LDA #255
      STA los_y1

      ; Raycast to first solid tile.
      JSR shot_find_first_solid
      BCS hqs_fall_hit_ok
      JMP hqs_fail
   .hqs_fall_hit_ok

      ; Place a floor portal at/near the hit location.
      JSR hqs_try_floor_from_hit
      BCS hqs_success
      JMP hqs_fail

   .hqs_not_falling

      ; Ray target X: edge of screen.

      ; Ray target from aim_held.
      ; For angled shots, target the top/bottom edge and solve X from slope.
      ; This avoids left/right asymmetry when Chell is near a side.
      LDA aim_held
      BEQ hqs_straight

      CMP #1
      BEQ hqs_aim_up

      ; down: y1 = 255
      LDA #255
      STA los_y1
      ; dx = (y1 - y0) / 2  (slope dy:dx = 2:1)
      LDA #255
      SEC
      SBC los_y0
      LSR A
      STA col_counter
      JMP hqs_angle_have_dx

   .hqs_aim_up
      ; up: y1 = 0
      LDA #0
      STA los_y1
      ; dx = (y0 - y1) / 2 = y0/2
      LDA los_y0
      LSR A
      STA col_counter

   .hqs_angle_have_dx
      ; x1 = x0 +/- dx (clamp to 0..127)
      LDA anim_dir
      BNE hqs_angle_right
      ; left
      LDA los_x0
      SEC
      SBC col_counter
      BCS hqs_angle_x_ok
      LDA #0
      BNE hqs_angle_x_store
   .hqs_angle_right
      LDA los_x0
      CLC
      ADC col_counter
      CMP #128
      BCC hqs_angle_x_ok
      LDA #127
   .hqs_angle_x_ok
   .hqs_angle_x_store
      STA los_x1
      JMP hqs_have_y1

   .hqs_straight
      ; straight: y unchanged, target the left/right edge.
      LDA los_y0
      STA los_y1
      LDA anim_dir
      BNE hqs_x_right
      LDA #0
      STA los_x1
      JMP hqs_have_y1
   .hqs_x_right
      LDA #127
      STA los_x1

   .hqs_have_y1
       ; Raycast to first solid tile.
       JSR shot_find_first_solid
       BCS hqs_hit_ok
       JMP hqs_fail
   .hqs_hit_ok

     ; Try plausible placements at this hit location.
     ; Don't rely on hit-axis inference (diagonal shots can step X+Y together).
     LDA aim_held
     BEQ hqs_try_wall_first
     JMP hqs_try_fc_first

   .hqs_try_wall_first
     JSR hqs_try_wall_from_hit
     BCS hqs_success
     JSR hqs_try_fc_from_hit
     BCS hqs_success
     JMP hqs_fail

   .hqs_try_fc_first
     JSR hqs_try_fc_from_hit
     BCS hqs_success
     JSR hqs_try_wall_from_hit
     BCS hqs_success
     JMP hqs_fail

   .hqs_success
      PLP
      RTS

    ; Shot registered but no valid placement.
    .hqs_fail
       PLP
       RTS

   .hqs_done
      RTS

  ; Try wall candidates derived from shot_hit_tilepos.
  ; Returns: C=1 if placed
  .hqs_try_wall_from_hit
     ; Decode hit tilepos into (hit_x, hit_y).
     LDA shot_hit_tilepos
     AND #15
     STA col_counter          ; hit_x
     LDA shot_hit_tilepos
     LSR A
     LSR A
     LSR A
     LSR A
     STA row_counter          ; hit_y

      ; base cell_x = max(hit_x - 1, 0), clamped to 14.
     ; compute_reticle_state treats reticle_cell_x as the LEFT column of a
     ; 2-tile span.  Shifting back by 1 ensures a right-wall hit tile lands
     ; in the right column of that span, matching reticle-mode conventions
     ; and giving the LOS check a clear target in the open space.
     LDA col_counter
     BEQ hqs_wall_x_ok
     SEC
     SBC #1
   .hqs_wall_x_ok
     CMP #15
     BCC hqs_wall_x_clamp_ok
     LDA #14
   .hqs_wall_x_clamp_ok
     STA reticle_cell_x

     ; base y = min(hit_y, 14) (wall portals are 2 tiles tall)
     LDA row_counter
     CMP #15
     BCC hqs_wall_base_y_ok
     LDA #14
   .hqs_wall_base_y_ok
     STA temp                ; base_y

     ; Try y: base, base-1, base+1
     LDA temp
     JSR hqs_try_wall_y
     BCS hqs_wall_placed
     LDA temp
     BEQ hqs_wall_skip_m1
     SEC
     SBC #1
     JSR hqs_try_wall_y
     BCS hqs_wall_placed
   .hqs_wall_skip_m1
     LDA temp
     CMP #14
     BEQ hqs_wall_fail
     CLC
     ADC #1
     JSR hqs_try_wall_y
     BCS hqs_wall_placed

   .hqs_wall_fail
     CLC
     RTS

   .hqs_wall_placed
     SEC
     RTS

  ; Try floor/ceiling candidates derived from shot_hit_tilepos.
  ; Returns: C=1 if placed
  .hqs_try_fc_from_hit
     ; Decode hit tilepos into (hit_x, hit_y).
     LDA shot_hit_tilepos
     AND #15
     STA col_counter          ; hit_x
     LDA shot_hit_tilepos
     LSR A
     LSR A
     LSR A
     LSR A
     STA row_counter          ; hit_y

     ; base cell_y is the surface row.
     LDA row_counter
     STA reticle_cell_y

     ; base cell_x = min(hit_x, 14)
     LDA col_counter
     CMP #15
     BCC hqs_fc_base_x_ok
     LDA #14
   .hqs_fc_base_x_ok
     STA temp                ; base_x

     ; Try x: base, base-1, base+1
     LDA temp
     JSR hqs_try_fc_x
     BCS hqs_fc_placed
     LDA temp
     BEQ hqs_fc_skip_m1
     SEC
     SBC #1
     JSR hqs_try_fc_x
     BCS hqs_fc_placed
   .hqs_fc_skip_m1
     LDA temp
     CMP #14
     BEQ hqs_fc_fail
     CLC
     ADC #1
     JSR hqs_try_fc_x
     BCS hqs_fc_placed

   .hqs_fc_fail
     CLC
     RTS

   .hqs_fc_placed
      SEC
      RTS


  ; Try placing a floor portal (only) derived from shot_hit_tilepos.
  ; Returns: C=1 if placed
  .hqs_try_floor_from_hit
      ; Decode hit tilepos into (hit_x, hit_y).
      LDA shot_hit_tilepos
      AND #15
      STA col_counter          ; hit_x
      LDA shot_hit_tilepos
      LSR A
      LSR A
      LSR A
      LSR A
      STA row_counter          ; hit_y

      ; base cell_y is the surface row.
      LDA row_counter
      STA reticle_cell_y

      ; base cell_x = min(hit_x, 14)
      LDA col_counter
      CMP #15
      BCC hqs_floor_base_x_ok
      LDA #14
   .hqs_floor_base_x_ok
      STA temp                ; base_x

      ; Try x: base, base-1, base+1
      LDA temp
      JSR hqs_try_floor_x
      BCS hqs_floor_placed
      LDA temp
      BEQ hqs_floor_skip_m1
      SEC
      SBC #1
      JSR hqs_try_floor_x
      BCS hqs_floor_placed
   .hqs_floor_skip_m1
      LDA temp
      CMP #14
      BEQ hqs_floor_fail
      CLC
      ADC #1
      JSR hqs_try_floor_x
      BCS hqs_floor_placed

   .hqs_floor_fail
      CLC
      RTS

   .hqs_floor_placed
      SEC
      RTS


  ; Try placing a floor portal with candidate cell_x in A.
  ; Returns C=1 if placed.
  .hqs_try_floor_x
      STA reticle_cell_x
      JSR compute_reticle_state
      BCC hqs_try_floor_fail

      ; Only floor; disallow ceiling/back-wall.
      LDA reticle_wall_orient
      CMP #PORTAL_ORIENT_FLOOR
      BNE hqs_try_floor_fail

      LDA portal_kind
      JSR place_portal_from_reticle
      SEC
      RTS
  .hqs_try_floor_fail
      CLC
      RTS




 ; Try placing a wall portal with candidate top tile_y in A.
 ; Returns C=1 if placed.
 .hqs_try_wall_y
     STA reticle_cell_y
     JSR compute_reticle_state
     BCC hqs_try_wall_fail

     ; Disallow back-wall and floor/ceiling.
     LDA reticle_wall_orient
     CMP #PORTAL_ORIENT_FLOOR
     BCS hqs_try_wall_fail

     LDA portal_kind
     JSR place_portal_from_reticle
     SEC
     RTS
 .hqs_try_wall_fail
     CLC
     RTS


 ; Try placing a floor/ceiling portal with candidate cell_x in A.
 ; Returns C=1 if placed.
 .hqs_try_fc_x
     STA reticle_cell_x
     JSR compute_reticle_state
     BCC hqs_try_fc_fail

     ; Only floor/ceiling; disallow back-wall.
     LDA reticle_wall_orient
     CMP #PORTAL_ORIENT_FLOOR
     BCC hqs_try_fc_fail
     CMP #PORTAL_ORIENT_BACK
     BEQ hqs_try_fc_fail

     LDA portal_kind
     JSR place_portal_from_reticle
     SEC
     RTS
 .hqs_try_fc_fail
     CLC
     RTS


; Check if Chell entered an open exit object in the current room.
; Conditions: alive, grounded, SPACE pressed, overlapping an open exit.
; Returns: C=1 if entered (caller should advance level), C=0 otherwise.
; Clobbers: A,X,Y,temp,temp_y
.check_exit_entered
    ; Must be alive.
    LDA char_dead
    BNE cee_no

    ; Must have pressed SPACE this frame.
    LDA action_pressed
    BEQ cee_no

    ; Must be grounded.
    LDA char_grounded
    BEQ cee_no

    ; Precompute Chell tile coords.
    LDA char_tile_pos
    AND #15
    STA temp              ; chell_x
    LDA char_tile_pos
    LSR A : LSR A : LSR A : LSR A
    STA temp_y            ; chell_y (top)

    ; Chell feet tile_y = chell_y + 1 (2 tiles tall).
    LDA temp_y
    CLC
    ADC #1
    STA row_counter       ; chell_feet_y

    ; Scan all objects for open exits in current room.
    LDY #0
.cee_loop
    CPY #OBJ_COUNT
    BCS cee_no

    LDA obj_type,Y
    CMP #OBJ_TYPE_EXIT
    BNE cee_next

    ; Must be in current room.
    LDA obj_room,Y
    CMP current_room
    BNE cee_next

    ; Must be open (state bit0 = 1).
    LDA obj_state,Y
    AND #1
    BEQ cee_next

    ; Exit is 2 tiles wide, 2 tiles tall. Check if Chell overlaps.
    ; Y overlap: exit occupies rows obj_y..obj_y+1.
    ; Chell occupies rows chell_y..chell_y+1.
    ; Overlap if |exit_y - chell_y| <= 1.
    LDA obj_y,Y
    SEC
    SBC temp_y
    BPL cee_yabs
    EOR #&FF
    CLC
    ADC #1
.cee_yabs
    CMP #2
    BCS cee_next

    ; X overlap: both 2 tiles wide. Overlap if |exit_x - chell_x| < 2.
    LDA obj_x,Y
    SEC
    SBC temp
    BPL cee_xabs
    EOR #&FF
    CLC
    ADC #1
.cee_xabs
    CMP #2
    BCS cee_next

    ; Overlap! Consume the action press so it doesn't also trigger cube drop.
    LDA #0
    STA action_pressed
    SEC
    RTS

.cee_next
    INY
    JMP cee_loop

.cee_no
    CLC
    RTS
