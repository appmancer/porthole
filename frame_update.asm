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

    ; Debug toggle: SPACE edge while in reticle mode.
    ; (Avoids interfering with SPACE actions in normal gameplay.)
    LDA action_pressed
    BEQ murm_debug_done
    LDA debug_flags
    EOR #1
    STA debug_flags
    LDA #1
    STA chell_dirty
    STA reticle_dirty
  .murm_debug_done

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
    ; Quick-shot portal firing (outside reticle mode).
    JSR handle_quick_shot

    ; Cube pickup/drop (SPACE edge).
    JSR handle_cube_pickup_drop

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
     ; Falling pose readability: once descent is committed (vy threshold), switch
     ; to a dedicated fall pose even on frames where we don't move (paced fall).
     ; Track a tiny pose state so we can force a redraw only on transitions.
     LDA chell_air_pose
     STA temp
 
     LDA #0
     STA chell_air_pose
 
     LDA char_grounded
     BNE unm_pose_check
 
     LDA char_vy
     BMI unm_pose_check
     CMP #FALL_POSE_VY_THRESHOLD
     BCC unm_pose_check
     LDA #1
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

    ; Portal placement/stamping forces a render.
    LDA portal_pending
    BEQ df_skip_portal
    LDA #1
    STA dirty_flag
 .df_skip_portal

    ; Persistent object visual updates need a background patch + restamp.
     LDA objects_pending
     BEQ df_skip_objects
     LDA #1
     STA dirty_flag
  .df_skip_objects

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
      ; Use Chell center X (ignore facing/gun offset).
      JSR calc_char_x
      CLC
      ADC #8
      STA los_x0
      ; Avoid 8px boundary bias by nudging right.
      AND #7
      BNE hqs_fall_x_ok
      LDA los_x0
      CMP #127
      BEQ hqs_fall_x_ok
      INC los_x0
   .hqs_fall_x_ok

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

     ; base cell_x = min(hit_x, 14)
     LDA col_counter
     CMP #15
     BCC hqs_wall_x_ok
     LDA #14
   .hqs_wall_x_ok
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
