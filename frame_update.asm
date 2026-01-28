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
    BEQ murm_not_active

    LDA char_grounded
    BEQ murm_not_active
    LDA char_vy
    BNE murm_not_active

    ; Reticle active while SHIFT held and Chell is stable.
    LDA #1
    STA reticle_active

    JSR poll_reticle_keys
    BCC murm_reticle_no_dirty
    LDA #1
    STA reticle_dirty
 .murm_reticle_no_dirty

    ; Portal placement request handling.
    ; We latch A/S key-down into portal_req and allow placement on a later
    ; green frame. To avoid "delayed shot at a new target" we snapshot the
    ; current target on the press frame (portal_req bit7 marks snapshot-pending)
    ; and cancel the request if the target changes afterward.

    LDA portal_req
    BEQ murm_reticle_req_ok

    ; temp = (reticle_cell_x<<4) | reticle_cell_y
    LDA reticle_cell_x
    ASL A
    ASL A
    ASL A
    ASL A
    ORA reticle_cell_y
    STA temp

    ; Snapshot target if requested (bit7).
    LDA portal_req
    AND #&80
    BEQ murm_reticle_req_no_snap

    LDA temp
    STA PORTAL_REQ_SNAP_POS
    LDA reticle_wall_orient
    STA PORTAL_REQ_SNAP_ORIENT

    ; Clear snapshot-pending flag.
    LDA portal_req
    AND #&7F
    STA portal_req

 .murm_reticle_req_no_snap

    ; If the target changed after the request was made, cancel it.
    LDA portal_req
    AND #3
    BEQ murm_reticle_req_ok

    LDA temp
    CMP PORTAL_REQ_SNAP_POS
    BNE murm_reticle_cancel_req
    LDA reticle_wall_orient
    CMP PORTAL_REQ_SNAP_ORIENT
    BEQ murm_reticle_req_ok

 .murm_reticle_cancel_req
    LDA #0
    STA portal_req

 .murm_reticle_req_ok

    ; Portal placement while in reticle mode.
    ; Use portal_req (latched edge) so a one-frame reticle flicker doesn't
    ; force you to re-press.
    ; Only place when the reticle is currently valid (green).
    LDA reticle_state
    BEQ murm_reticle_place_done

    ; Prefer Portal A if both pressed.
    LDA portal_req
    AND #1
    BEQ murm_reticle_check_place_b
    LDA #0
    JSR place_portal_from_reticle
    ; Consume request (requires key-up before next placement).
    LDA portal_req
    AND #&FE
    STA portal_req
    JMP murm_reticle_place_done

 .murm_reticle_check_place_b
    LDA portal_req
    AND #2
    BEQ murm_reticle_place_done
    LDA #1
    JSR place_portal_from_reticle
    ; Consume request.
    LDA portal_req
    AND #&FD
    STA portal_req

 .murm_reticle_place_done
    SEC
    RTS

.murm_not_active
    CLC
    RTS


; Normal mode: handle reticle deactivation, movement, and gravity.
.update_normal_mode
    ; Portal placement requests are only meaningful in reticle mode.
    ; Clear them when not in reticle mode so taps can't leak into gameplay.
    LDA #0
    STA portal_req

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
    JSR poll_move_keys
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
