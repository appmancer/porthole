.reticle_start
; reticle.asm
; Reticle control + placement validity (including LOS).

; Poll reticle movement while SHIFT is held.
; Z/X/:/ move reticle over the placement grid:
; - X in 8px tile columns (reticle_cell_x = top-left of 2-tile span)
; - Y in 16px tile rows
; Output: C=1 if redraw needed.
.poll_reticle_keys
    ; Use temp_y as our local "needs redraw" flag.
    ; (temp is used inside is_portalable/is_solid, so don't use it here.)
    LDA #0
    STA temp_y

    ; Ensure reticle is active.
    LDA reticle_active
    BNE reticle_already_active
    LDA #1
    STA reticle_active
    LDA #1
    STA temp_y
.reticle_already_active

    ; Entering reticle mode: snap reticle to Chell gun position.
    LDA keys_pressed
    AND #8
    BEQ reticle_skip_snap

    ; x = calc_char_x + 8 (roughly Chell center)
    ; reticle_cell_x is the top-left 8px tile_x of a 2-tile-wide portal span.
    JSR calc_char_x
    CLC
    ADC #8
    LSR A
    LSR A
    LSR A
    CMP #15
    BCC reticle_snap_x_ok
    LDA #14
 .reticle_snap_x_ok
    STA reticle_cell_x

    ; y = calc_char_y + 16 (roughly mid-body)
    JSR calc_char_y
    CLC
    ADC #16
    LSR A
    LSR A
    LSR A
    LSR A
    CMP #16
    BCC reticle_snap_y_ok
    LDA #15
.reticle_snap_y_ok
    STA reticle_cell_y

    LDA #1
    STA temp_y

.reticle_skip_snap

    ; Chell stays idle (stop horizontal stepping)
    LDA move_held
    STA last_move_held
    LDA #0
    STA move_held

    ; Reticle movement with simple repeat.
    ; - If a direction was newly pressed, move immediately.
    ; - Otherwise, repeat while held using a cooldown.

    ; If any direction is newly pressed, bypass cooldown.
    LDA keys_pressed
    AND #(1+2+16+32)
    BEQ reticle_cd_tick
    LDA #0
    STA reticle_move_cd

 .reticle_cd_tick
    LDA reticle_move_cd
    BEQ reticle_try_move
    DEC reticle_move_cd
    JMP reticle_update_state

 .reticle_try_move
    ; Prefer left, then right, then up, then down.

    ; Left
    LDA keys_held
    AND #1
    BEQ reticle_try_right
    LDA reticle_cell_x
    BEQ reticle_try_right
    DEC reticle_cell_x
    LDA #4
    STA reticle_move_cd
    LDA #1
    STA temp_y
    JMP reticle_update_state

 .reticle_try_right
    ; Right
    LDA keys_held
    AND #2
    BEQ reticle_try_up
    LDA reticle_cell_x
    CMP #14
    BEQ reticle_try_up
    INC reticle_cell_x
    LDA #4
    STA reticle_move_cd
    LDA #1
    STA temp_y
    JMP reticle_update_state

 .reticle_try_up
    ; Up
    LDA keys_held
    AND #16
    BEQ reticle_try_down
    LDA reticle_cell_y
    BEQ reticle_try_down
    DEC reticle_cell_y
    LDA #4
    STA reticle_move_cd
    LDA #1
    STA temp_y
    JMP reticle_update_state

 .reticle_try_down
    ; Down
    LDA keys_held
    AND #32
    BEQ reticle_update_state
    LDA reticle_cell_y
    CMP #15
    BEQ reticle_update_state
    INC reticle_cell_y
    LDA #4
    STA reticle_move_cd
    LDA #1
    STA temp_y

 .reticle_update_state
    ; Recompute reticle_state at current cell.
    ; compute_reticle_state uses temp_y internally, so preserve our redraw flag.
    LDA temp_y
    PHA
    LDA reticle_state
    PHA
    JSR compute_reticle_state
    PLA
    CMP reticle_state
    BEQ reticle_restore_redraw

    ; State changed => force redraw.
    PLA
    LDA #1
    PHA

  .reticle_restore_redraw
    PLA
    STA temp_y
    JMP reticle_done


; Check back-wall portalability (2x2 empty) at current reticle_cell_y.
; Returns C=1 if tile(y,x0..x1) and tile(y+1,x0..x1) are all TILE_BACKWALL_PORTAL.
.reticle_backwall_at_y
    ; Need 2 tiles height.
    LDA reticle_cell_y
    CMP #15
    BEQ backwall_fail

    ; row y
    LDY reticle_cell_y
    LDA times16_table,Y
    CLC
    ADC col_counter
    TAY
    LDA (tilemap_ptr),Y
    CMP #TILE_BACKWALL_PORTAL
    BNE backwall_fail
    INY
    LDA (tilemap_ptr),Y
    CMP #TILE_BACKWALL_PORTAL
    BNE backwall_fail

    ; row y+1
    LDY reticle_cell_y
    INY
    LDA times16_table,Y
    CLC
    ADC col_counter
    TAY
    LDA (tilemap_ptr),Y
    CMP #TILE_BACKWALL_PORTAL
    BNE backwall_fail
    INY
    LDA (tilemap_ptr),Y
    CMP #TILE_BACKWALL_PORTAL
    BNE backwall_fail

    SEC
    RTS

 .backwall_fail
    CLC
    RTS


 ; Compute reticle_state, orient, and debug_reason for the current cell.
 ;
 ; Inputs:
 ; - reticle_cell_x (0..14): top-left of 2-tile span
 ; - reticle_cell_y (0..15)
 ;
 ; Outputs:
 ; - reticle_state: 0=blocked, 1=valid+LOS
 ; - reticle_wall_orient: 0..4
 ; - reticle_debug_reason: 0,1..5 (bit 7 set when LOS blocked)
 ; - C=1 if reticle is green, else C=0
 ;
 ; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter
 .compute_reticle_state
     ; tile_x0 = reticle_cell_x (top-left)
     LDA reticle_cell_x
     STA col_counter
     ; tile_x1 = tile_x0 + 1
     CLC
     ADC #1
     STA row_counter

     ; -------- Floor / ceiling test (2x1) --------
     ; idx0 = y*16 + tile_x0
     LDY reticle_cell_y
     LDA times16_table,Y
     CLC
     ADC col_counter
     TAY
     LDA (tilemap_ptr),Y
     STA temp

     ; idx1 = idx0 + 1
     INY
     LDA (tilemap_ptr),Y
     CMP temp
     BNE crs_try_wall

     ; Must be floor or ceiling face.
     LDA temp
     CMP #2
     BEQ crs_fc_match
     CMP #4
     BEQ crs_fc_match
     JMP crs_try_wall

   .crs_fc_match
     ; Require empty space adjacent to the surface.
     ; - floor surface at y => empty row at y-1
     ; - ceiling surface at y => empty row at y+1
     LDA temp
     CMP #4
     BEQ crs_is_ceil

     ; floor
     LDA reticle_cell_y
     BEQ crs_fc_oob
     SEC
     SBC #1
     STA temp_y
     LDA #PORTAL_ORIENT_FLOOR
     STA reticle_wall_orient
     JMP crs_fc_check_empty

    .crs_is_ceil
      LDA reticle_cell_y
      CMP #15
      BEQ crs_fc_oob
      CLC
      ADC #1
      STA temp_y
      LDA #PORTAL_ORIENT_CEIL
      STA reticle_wall_orient

      JMP crs_fc_check_empty

    .crs_fc_oob
      JMP crs_blocked

   .crs_fc_check_empty
     ; empty row = temp_y; require both tiles clear
     LDY temp_y
     LDA times16_table,Y
     CLC
     ADC col_counter
     TAY
     LDA solid_tile_plane,Y
     BNE crs_try_wall
     INY
     LDA solid_tile_plane,Y
     BNE crs_try_wall

     LDA #1
     STA reticle_debug_reason
     JMP crs_surface_los

     ; -------- Wall test (1x2) --------
   .crs_try_wall
    ; Need 2 tiles height.
    LDA reticle_cell_y
    CMP #15
    BNE crs_wall_height_ok
    JMP crs_try_backwall
 .crs_wall_height_ok

     ; Try left column: (tile_x0, y) and (tile_x0, y+1)
     LDY reticle_cell_y
     LDA times16_table,Y
     CLC
     ADC col_counter
     TAY
     LDA (tilemap_ptr),Y
     STA temp

     ; temp must be 3 (left wall) or 5 (right wall)
     CMP #3
     BEQ crs_wall_left_ok_type
     CMP #5
     BNE crs_try_wall_right
   .crs_wall_left_ok_type

     ; Compare with below tile.
     LDY reticle_cell_y
     INY
     LDA times16_table,Y
     CLC
     ADC col_counter
     TAY
     LDA (tilemap_ptr),Y
     CMP temp
     BNE crs_try_wall_right

     ; Determine orientation from tile type (3=left wall, 5=right wall).
     LDA temp
     CMP #5
     BNE crs_wall_left_is_left
     LDA #PORTAL_ORIENT_WALL_R
     BNE crs_wall_left_orient_done
   .crs_wall_left_is_left
     LDA #PORTAL_ORIENT_WALL_L
  .crs_wall_left_orient_done
      STA reticle_wall_orient

      ; Facing constraint: wall must face Chell.
      LDA reticle_wall_orient
      CMP #PORTAL_ORIENT_WALL_L
      BEQ crs_wall_left_need_right
      ; WALL_R requires facing right.
      LDA anim_dir
      BNE crs_wall_left_face_ok
      JMP crs_try_wall_right
   .crs_wall_left_need_right
      ; WALL_L requires facing left.
      LDA anim_dir
      BEQ crs_wall_left_face_ok
      JMP crs_try_wall_right
   .crs_wall_left_face_ok

     ; Adjacent empty space check for wall portals.
     ; temp_y = wall_x
     LDA col_counter
     STA temp_y
     JSR crs_check_wall_open_empty
     BCC crs_try_wall_right

     LDA #2
     STA reticle_debug_reason
     JMP crs_surface_los

   .crs_try_wall_right
     ; Try right column: (tile_x1, y) and (tile_x1, y+1)
     LDY reticle_cell_y
     LDA times16_table,Y
     CLC
     ADC row_counter
     TAY
     LDA (tilemap_ptr),Y
     STA temp

     CMP #3
     BEQ crs_wall_right_ok_type
     CMP #5
     BEQ crs_wall_right_ok_type
     JMP crs_try_backwall
   .crs_wall_right_ok_type

     LDY reticle_cell_y
     INY
     LDA times16_table,Y
     CLC
     ADC row_counter
     TAY
     LDA (tilemap_ptr),Y
     CMP temp
     BNE crs_try_backwall

     LDA temp
     CMP #5
     BNE crs_wall_right_is_left
     LDA #PORTAL_ORIENT_WALL_R
     BNE crs_wall_right_orient_done
   .crs_wall_right_is_left
     LDA #PORTAL_ORIENT_WALL_L
  .crs_wall_right_orient_done
      STA reticle_wall_orient

      ; Facing constraint: wall must face Chell.
      LDA reticle_wall_orient
      CMP #PORTAL_ORIENT_WALL_L
      BEQ crs_wall_right_need_right
      ; WALL_R requires facing right.
      LDA anim_dir
      BNE crs_wall_right_face_ok
      JMP crs_try_backwall
   .crs_wall_right_need_right
      ; WALL_L requires facing left.
      LDA anim_dir
      BEQ crs_wall_right_face_ok
      JMP crs_try_backwall
   .crs_wall_right_face_ok

     LDA row_counter
     STA temp_y
     JSR crs_check_wall_open_empty
     BCC crs_try_backwall

     LDA #3
     STA reticle_debug_reason
     JMP crs_surface_los

     ; -------- Back-wall test (2x2 empties) --------
   .crs_try_backwall
     JSR reticle_backwall_at_y
     BCC crs_blocked
     LDA #4
     STA reticle_debug_reason
     LDA #PORTAL_ORIENT_BACK
     STA reticle_wall_orient
     JMP crs_surface_los

 ; Check that the portal opening space next to a wall is empty.
 ; Inputs:
 ; - temp_y = wall_x
 ; - reticle_cell_y = top tile_y
 ; - reticle_wall_orient = PORTAL_ORIENT_WALL_L / PORTAL_ORIENT_WALL_R
 ; Output: C=1 if open space is empty (both tiles), else C=0
 ; Clobbers: A,X,Y,temp
 .crs_check_wall_open_empty
     ; open_x in X
     LDA reticle_wall_orient
     CMP #PORTAL_ORIENT_WALL_L
     BEQ crs_open_right
     ; wall-right => open to left
     LDA temp_y
     BEQ crs_open_fail
     SEC
     SBC #1
     TAX
     JMP crs_open_have_x
   .crs_open_right
     LDA temp_y
     CMP #15
     BEQ crs_open_fail
     CLC
     ADC #1
     TAX

   .crs_open_have_x
     ; Check (open_x, y) and (open_x, y+1) are not solid.
     LDY reticle_cell_y
     LDA times16_table,Y
     STA temp
     TXA
     CLC
     ADC temp
     TAY
     LDA solid_tile_plane,Y
     BNE crs_open_fail

     LDY reticle_cell_y
     INY
     LDA times16_table,Y
     STA temp
     TXA
     CLC
     ADC temp
     TAY
     LDA solid_tile_plane,Y
     BNE crs_open_fail

     SEC
     RTS
   .crs_open_fail
     CLC
     RTS

   .crs_surface_los
     ; Candidate surface match passed; now require line-of-sight.
     JSR reticle_check_los
     BCS crs_set_green

     ; LOS blocked: keep the base reason but mark it with bit 7.
     LDA reticle_debug_reason
     ORA #&80
     STA reticle_debug_reason
     LDA #0
     STA reticle_state
     CLC
     RTS

   .crs_set_green
     LDA #1
     STA reticle_state
     SEC
     RTS

   .crs_blocked
     LDA #0
     STA reticle_debug_reason
     STA reticle_wall_orient
     STA reticle_state
     CLC
     RTS

 .reticle_done
    LDA temp_y
    BEQ reticle_no_redraw
    SEC
    RTS
 .reticle_no_redraw
    CLC
    RTS


; --- Reticle line-of-sight ---
;
; Returns C=1 if Chell can see the candidate portal target, else C=0.
; Uses the solid-tile plane (solid_tile_plane) only.
 .reticle_check_los
     ; Ray start (gun position) from Chell.
     ; Use a point near the gun muzzle, biased by facing direction.
     ; (This avoids starting inside nearby solid tiles when Chell hugs walls.)
     JSR calc_char_x
    STA temp

    LDA anim_dir
    BNE los_gun_right
    ; facing left
    LDA temp
    CLC
    ADC #2
    STA los_x0
    JMP los_gun_y
  .los_gun_right
    LDA temp
    CLC
    ADC #13
    STA los_x0

  .los_gun_y
     JSR calc_char_y
     CLC
     ADC #12
     STA los_y0

    ; Compute ray target based on reticle_wall_orient.
    LDA reticle_wall_orient
    CMP #PORTAL_ORIENT_FLOOR
    BEQ reticle_los_floor
    CMP #PORTAL_ORIENT_CEIL
    BEQ reticle_los_ceil
    CMP #PORTAL_ORIENT_WALL_L
    BEQ reticle_los_wall_left
    CMP #PORTAL_ORIENT_WALL_R
    BEQ reticle_los_wall_right
    CMP #PORTAL_ORIENT_BACK
    BEQ reticle_los_backwall
    CLC
    RTS

  .reticle_los_floor
    ; target_x = reticle_cell_x*8 + 8 (centre of 2-tile span)
    LDA reticle_cell_x
    ASL A
    ASL A
    ASL A
    CLC
    ADC #8
    STA los_x1
    ; target_y = (reticle_cell_y-1)*16 + 8
    LDA reticle_cell_y
    BEQ reticle_los_fail
    SEC
    SBC #1
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC #8
    STA los_y1
    JMP reticle_los_cast

  .reticle_los_ceil
    ; target_x = reticle_cell_x*8 + 8
    LDA reticle_cell_x
    ASL A
    ASL A
    ASL A
    CLC
    ADC #8
    STA los_x1
    ; target_y = (reticle_cell_y+1)*16 + 8
    LDA reticle_cell_y
    CMP #15
    BEQ reticle_los_fail
    CLC
    ADC #1
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC #8
    STA los_y1
    JMP reticle_los_cast

  .reticle_los_wall_left
    ; target_x = (reticle_cell_x+1)*8 + 4 (open tile centre)
    LDA reticle_cell_x
    CLC
    ADC #1
    ASL A
    ASL A
    ASL A
    CLC
    ADC #4
    STA los_x1
    JMP reticle_los_wall_y

  .reticle_los_wall_right
    ; target_x = reticle_cell_x*8 + 4 (open tile centre)
    LDA reticle_cell_x
    ASL A
    ASL A
    ASL A
    CLC
    ADC #4
    STA los_x1

  .reticle_los_wall_y
    ; target_y = reticle_cell_y*16 + 16 (centre of 2-tile height)
    LDA reticle_cell_y
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC #16
    STA los_y1
    JMP reticle_los_cast

  .reticle_los_backwall
    ; target_x = reticle_cell_x*8 + 8 (centre)
    LDA reticle_cell_x
    ASL A
    ASL A
    ASL A
    CLC
    ADC #8
    STA los_x1
    ; target_y = reticle_cell_y*16 + 16
    LDA reticle_cell_y
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC #16
    STA los_y1

  .reticle_los_cast
    JSR los_line_clear
    RTS

  .reticle_los_fail
    CLC
    RTS


; Test line-of-sight from (los_x0,los_y0) to (los_x1,los_y1).
; Returns C=1 if clear, else C=0.
.los_line_clear
    ; Compute step + abs delta for X.
    LDA los_x1
    SEC
    SBC los_x0
    BCS los_dx_pos
    ; negative => sx = -1
    LDA #&FF
    STA los_sx
    LDA los_x0
    SEC
    SBC los_x1
    STA los_dx
    JMP los_dx_done
  .los_dx_pos
    LDA #1
    STA los_sx
    STA temp              ; temp=1 (used only to avoid reloading)
    LDA los_x1
    SEC
    SBC los_x0
    STA los_dx
  .los_dx_done

    ; Compute step + abs delta for Y.
    LDA los_y1
    SEC
    SBC los_y0
    BCS los_dy_pos
    ; negative => sy = -1
    LDA #&FF
    STA los_sy
    LDA los_y0
    SEC
    SBC los_y1
    STA los_dy
    JMP los_dy_done
  .los_dy_pos
    LDA #1
    STA los_sy
    LDA los_y1
    SEC
    SBC los_y0
    STA los_dy
  .los_dy_done

    ; Seed prev tile to the starting tile so we don't immediately fail when the
    ; gun point is inside/overlapping solid (e.g. hugging a wall).
    JSR los_seed_prev_tile

    ; Choose major axis.
    LDA los_dx
    CMP los_dy
    BCS los_x_major

    ; --- Y-major ---
    LDA los_dy
    STA los_steps
    LSR A
    STA los_err
  .los_y_loop
    ; Block if we enter a solid tile.
    JSR los_check_tile
    BCS los_blocked

    ; Reached target?
    LDA los_x0
    CMP los_x1
    BNE los_y_not_done
    LDA los_y0
    CMP los_y1
    BEQ los_clear
  .los_y_not_done

    LDA los_steps
    BEQ los_blocked

    ; Step Y.
    LDA los_y0
    CLC
    ADC los_sy
    STA los_y0

    ; err -= dx; if borrow, step X and err += dy
    LDA los_err
    SEC
    SBC los_dx
    STA los_err
    BCS los_y_err_ok
    LDA los_x0
    CLC
    ADC los_sx
    STA los_x0
    LDA los_err
    CLC
    ADC los_dy
    STA los_err
  .los_y_err_ok

    DEC los_steps
    JMP los_y_loop

  ; --- X-major ---
  .los_x_major
    LDA los_dx
    STA los_steps
    LSR A
    STA los_err
  .los_x_loop
    JSR los_check_tile
    BCS los_blocked

    LDA los_x0
    CMP los_x1
    BNE los_x_not_done
    LDA los_y0
    CMP los_y1
    BEQ los_clear
  .los_x_not_done

    LDA los_steps
    BEQ los_blocked

    ; Step X.
    LDA los_x0
    CLC
    ADC los_sx
    STA los_x0

    ; err -= dy; if borrow, step Y and err += dx
    LDA los_err
    SEC
    SBC los_dy
    STA los_err
    BCS los_x_err_ok
    LDA los_y0
    CLC
    ADC los_sy
    STA los_y0
    LDA los_err
    CLC
    ADC los_dx
    STA los_err
  .los_x_err_ok

    DEC los_steps
    JMP los_x_loop

  .los_clear
    SEC
    RTS

  .los_blocked
    CLC
    RTS


; Seed los_prev_tile to the tile containing the current (los_x0,los_y0), using
; the same boundary-bias logic as los_check_tile, but without testing solidity.
.los_seed_prev_tile
    ; ---- tile_x ----
    LDA los_x0
    STA temp
    AND #7
    BNE los_seed_x_ok

    LDA los_sx
    CMP #1
    BNE los_seed_x_left
    LDA temp
    CMP #127
    BEQ los_seed_x_ok
    INC temp
    JMP los_seed_x_ok
  .los_seed_x_left
    LDA temp
    BEQ los_seed_x_ok
    DEC temp

  .los_seed_x_ok
    LDA temp
    LSR A
    LSR A
    LSR A
    STA col_counter

    ; ---- tile_y ----
    LDA los_y0
    STA temp
    AND #&0F
    BNE los_seed_y_ok

    LDA los_sy
    CMP #1
    BNE los_seed_y_up
    LDA temp
    CMP #255
    BEQ los_seed_y_ok
    INC temp
    JMP los_seed_y_ok
  .los_seed_y_up
    LDA temp
    BEQ los_seed_y_ok
    DEC temp

  .los_seed_y_ok
    LDA temp
    LSR A
    LSR A
    LSR A
    LSR A
    TAY

    ; tilepos = tile_y*16 + tile_x
    LDA times16_table,Y
    CLC
    ADC col_counter
    STA los_prev_tile
    RTS


; Check whether the ray has entered a new tile, and if so, test solidity.
; Returns C=1 if blocked by a solid tile, else C=0.
.los_check_tile
    ; Convert pixel (x,y) to tile (8x16) with direction-aware boundary bias.
    ; This avoids false hits when the ray runs exactly along a tile edge.

    ; ---- tile_x ----
    LDA los_x0
    STA temp
    AND #7
    BNE los_tile_x_ok

    ; On an 8px boundary: bias toward travel direction.
    LDA los_sx
    CMP #1
    BNE los_tile_x_bias_left
    ; moving right: x++ (clamp)
    LDA temp
    CMP #127
    BEQ los_tile_x_ok
    INC temp
    JMP los_tile_x_ok
  .los_tile_x_bias_left
    ; moving left: x-- (clamp)
    LDA temp
    BEQ los_tile_x_ok
    DEC temp

  .los_tile_x_ok
    LDA temp
    LSR A
    LSR A
    LSR A
    STA col_counter

    ; ---- tile_y ----
    LDA los_y0
    STA temp
    AND #&0F
    BNE los_tile_y_ok

    ; On a 16px boundary: bias toward travel direction.
    LDA los_sy
    CMP #1
    BNE los_tile_y_bias_up
    ; moving down: y++ (clamp)
    LDA temp
    CMP #255
    BEQ los_tile_y_ok
    INC temp
    JMP los_tile_y_ok
  .los_tile_y_bias_up
    ; moving up: y-- (clamp)
    LDA temp
    BEQ los_tile_y_ok
    DEC temp

  .los_tile_y_ok
    LDA temp
    LSR A
    LSR A
    LSR A
    LSR A
    TAY

    ; tilepos = tile_y*16 + tile_x
    LDA times16_table,Y
    CLC
    ADC col_counter
    TAY

    ; Only test when we enter a new tile.
    TYA
    CMP los_prev_tile
    BEQ los_tile_ok
    STA los_prev_tile

    LDA solid_tile_plane,Y
    BEQ los_tile_ok
    SEC
    RTS

  .los_tile_ok
    CLC
    RTS


 ; Raycast from (los_x0,los_y0) to (los_x1,los_y1) and find the first solid tile.
 ;
 ; Uses solid_tile_plane only (dynamic objects never block).
 ;
 ; Outputs on hit:
 ; - shot_hit_tilepos = y*16 + x
 ; - C=1
 ;
 ; On miss: C=0
 ;
 ; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter
 .shot_find_first_solid
     ; Compute step + abs delta for X.
     LDA los_x1
     SEC
     SBC los_x0
     BCS sffs_dx_pos
     ; negative => sx = -1
     LDA #&FF
     STA los_sx
     LDA los_x0
     SEC
     SBC los_x1
     STA los_dx
     JMP sffs_dx_done
   .sffs_dx_pos
     LDA #1
     STA los_sx
     LDA los_x1
     SEC
     SBC los_x0
     STA los_dx
   .sffs_dx_done

     ; Compute step + abs delta for Y.
     LDA los_y1
     SEC
     SBC los_y0
     BCS sffs_dy_pos
     ; negative => sy = -1
     LDA #&FF
     STA los_sy
     LDA los_y0
     SEC
     SBC los_y1
     STA los_dy
     JMP sffs_dy_done
   .sffs_dy_pos
     LDA #1
     STA los_sy
     LDA los_y1
     SEC
     SBC los_y0
     STA los_dy
   .sffs_dy_done

     ; Seed prev tile to the starting tile.
     JSR los_seed_prev_tile

     ; Choose major axis.
     LDA los_dx
     CMP los_dy
     BCS sffs_x_major

     ; --- Y-major ---
     LDA los_dy
     STA los_steps
     LSR A
     STA los_err
   .sffs_y_loop
     ; Check whether we entered a solid tile.
     JSR shot_check_tile
     BCS sffs_hit

     ; Reached target?
     LDA los_x0
     CMP los_x1
     BNE sffs_y_not_done
     LDA los_y0
     CMP los_y1
     BEQ sffs_miss
   .sffs_y_not_done

     LDA los_steps
     BEQ sffs_miss

     ; Step Y.
     LDA los_y0
     CLC
     ADC los_sy
     STA los_y0

     ; err -= dx; if borrow, step X and err += dy
     LDA los_err
     SEC
     SBC los_dx
     STA los_err
     BCS sffs_y_err_ok
     LDA los_x0
     CLC
     ADC los_sx
     STA los_x0
     LDA los_err
     CLC
     ADC los_dy
     STA los_err
   .sffs_y_err_ok

     DEC los_steps
     JMP sffs_y_loop

     ; --- X-major ---
   .sffs_x_major
     LDA los_dx
     STA los_steps
     LSR A
     STA los_err
   .sffs_x_loop
     JSR shot_check_tile
     BCS sffs_hit

     LDA los_x0
     CMP los_x1
     BNE sffs_x_not_done
     LDA los_y0
     CMP los_y1
     BEQ sffs_miss
   .sffs_x_not_done

     LDA los_steps
     BEQ sffs_miss

     ; Step X.
     LDA los_x0
     CLC
     ADC los_sx
     STA los_x0

     ; err -= dy; if borrow, step Y and err += dx
     LDA los_err
     SEC
     SBC los_dy
     STA los_err
     BCS sffs_x_err_ok
     LDA los_y0
     CLC
     ADC los_sy
     STA los_y0
     LDA los_err
     CLC
     ADC los_dx
     STA los_err
   .sffs_x_err_ok

     DEC los_steps
     JMP sffs_x_loop

   .sffs_hit
     SEC
     RTS
   .sffs_miss
     CLC
     RTS


 ; Check whether the ray has entered a new tile, and if so, test solidity.
 ; Returns:
 ; - C=1 if first solid tile entered (hit recorded)
 ; - C=0 otherwise
 ;
 ; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter
 .shot_check_tile
     ; Convert pixel (x,y) to tile (8x16) with direction-aware boundary bias.
     ; (Copied from los_check_tile.)

     ; ---- tile_x ----
     LDA los_x0
     STA temp
     AND #7
     BNE sct_tile_x_ok

     ; On an 8px boundary: bias toward travel direction.
     LDA los_sx
     CMP #1
     BNE sct_tile_x_bias_left
     ; moving right: x++ (clamp)
     LDA temp
     CMP #127
     BEQ sct_tile_x_ok
     INC temp
     JMP sct_tile_x_ok
   .sct_tile_x_bias_left
     ; moving left: x-- (clamp)
     LDA temp
     BEQ sct_tile_x_ok
     DEC temp

   .sct_tile_x_ok
     LDA temp
     LSR A
     LSR A
     LSR A
     STA col_counter

     ; ---- tile_y ----
     LDA los_y0
     STA temp
     AND #&0F
     BNE sct_tile_y_ok

     ; On a 16px boundary: bias toward travel direction.
     LDA los_sy
     CMP #1
     BNE sct_tile_y_bias_up
     ; moving down: y++ (clamp)
     LDA temp
     CMP #255
     BEQ sct_tile_y_ok
     INC temp
     JMP sct_tile_y_ok
   .sct_tile_y_bias_up
     ; moving up: y-- (clamp)
     LDA temp
     BEQ sct_tile_y_ok
     DEC temp

   .sct_tile_y_ok
     LDA temp
     LSR A
     LSR A
     LSR A
     LSR A
     TAY

     ; tilepos = tile_y*16 + tile_x
     LDA times16_table,Y
     CLC
     ADC col_counter
     TAY

     ; Only test when we enter a new tile.
     TYA
     CMP los_prev_tile
     BEQ sct_tile_ok

     ; Preserve old prev tilepos for axis calculation.
     LDA los_prev_tile
     STA temp_y

     ; Update prev tile.
     TYA
     STA los_prev_tile

     ; Solid?
     LDA solid_tile_plane,Y
     BEQ sct_tile_ok

     ; Record hit.
     TYA
     STA shot_hit_tilepos

     SEC
     RTS

   .sct_tile_ok
     CLC
     RTS
