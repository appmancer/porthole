.portal_teleport_start
; portal_teleport.asm
; Portal entry detection + teleportation (including momentum mapping).

; Our vertical velocity `char_vy` is in 8px "stripes" per frame.
; Our horizontal velocity `char_vx` is in pixels per frame.
;
; To keep small hops from turning into massive horizontal flings, we use a
; reduced scale factor when converting vy<->pixels for portal momentum.
PORTAL_VY_TO_PX_SHIFT = 1      ; 2px per vy stripe (vs 8px physical step)

; Detect Chell walking into a portal.
;
; Rule: trigger when Chell overlaps the portal rect and is moving into the face
; (dot(v, n_enter) < 0). Back-wall portals require SPACE intent.
;
; Output:
; - teleport_pending=1
; - teleport_entry_kind=0/1
;
; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter
.check_portal_entry_intent
        ; Don't re-trigger until the pending teleport is consumed.
        LDA teleport_pending
        BNE cpei_done

        ; Post-teleport cooldown (anti-ping-pong).
        ; We still allow entering the *other* portal during cooldown so things like
        ; a bouncy elevator work.
        LDA teleport_cooldown
        BEQ cpei_cd_done
        DEC teleport_cooldown
 .cpei_cd_done

        ; Fast reject:
        ; - normal portals require motion intent
        ; - back-wall portals require SPACE intent (may be stationary)
        LDA char_vx
        ORA char_vy
        ORA char_prev_vy
        BNE cpei_intent_ok
        LDA action_held
        BNE cpei_intent_ok
        ; Allow wall-portal entry when pushing into the face but blocked by collision
        ; (char_vx may have been zeroed after a blocked step).
        LDA keys_held
        AND #3
        BEQ cpei_done
  .cpei_intent_ok

        ; Cache Chell rect (approx).
        ; We bias the leading edge to better match what you see on screen:
        ; - moving right: use the "nose" point used by will_collide_right (x+10)
        ; - moving left: inset slightly to match will_collide_left (x+3)
        JSR calc_char_x
        STA screen_ptr        ; chell_left_x (raw)
        STA temp              ; chell_left_x (effective)

        ; Bias the overlap rect toward motion direction.
        ; (Don't use anim_dir here; portal momentum can move Chell without input.)
        LDA char_vx
        BEQ cpei_x_stationary
        BMI cpei_x_left
        ; Right: chell_right_x = left + 10
        LDA screen_ptr
        CLC
        ADC #10
        STA temp_y
        JMP cpei_x_done

 .cpei_x_stationary
        ; Stationary: use full body width.
        LDA screen_ptr
        STA temp
        CLC
        ADC #15
        STA temp_y
        JMP cpei_x_done

.cpei_x_left
        ; Left: chell_left_x = left + 3, chell_right_x = left + 15
        LDA screen_ptr
        CLC
        ADC #3
        STA temp
        LDA screen_ptr
        CLC
        ADC #15
        STA temp_y

.cpei_x_done

        JSR calc_char_y
        STA row_counter       ; chell_top_y
        CLC
        ADC #31
        STA col_counter       ; chell_bottom_y

        ; Prefer portal A if both overlap (shouldn't happen with non-overlap rule).
        ; Save Chell rect (temp/temp_y) — portal A's overlap check clobbers them.
        LDA temp_y
        PHA
        LDA temp
        PHA
        JSR cpei_try_portal_a
        PLA
        STA temp
        PLA
        STA temp_y
        BCS cpei_done
        JSR cpei_try_portal_b

.cpei_done
        RTS


; If teleport_pending is set, teleport Chell to the other portal.
;
; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter,screen_ptr
.maybe_teleport
        LDA teleport_pending
        BNE mt_go
        RTS

.mt_go
        ; Determine exit portal kind (other portal).
        LDA teleport_entry_kind
        EOR #1
        STA temp                ; exit_kind (0=A,1=B)

        ; Record last-exit portal kind (for anti-ping-pong/debug).
        LDA temp
        STA teleport_last_exit_kind

        ; Load exit portal into (row_counter=orient, X=tile_x, Y=tile_y, temp_y=room).
        LDA temp
        BEQ mt_exit_a
        ; Exit B
        LDA portal_b_enabled
        BNE mt_b_enabled
        JMP mt_clear
.mt_b_enabled
        LDA portal_b_room
        STA temp_y
        LDX portal_b_x
        LDY portal_b_y
        LDA portal_b_orient
        STA row_counter
        JMP mt_have_exit

.mt_exit_a
        LDA portal_a_enabled
        BNE mt_a_enabled
        JMP mt_clear
.mt_a_enabled
        LDA portal_a_room
        STA temp_y
        LDX portal_a_x
        LDY portal_a_y
        LDA portal_a_orient
        STA row_counter

 .mt_have_exit
        ; Preserve exit portal coords/orient across room-switch work (JSRs clobber X/Y).
        LDA temp_y
        STA teleport_exit_room
        STX teleport_exit_x
        STY teleport_exit_y
        LDA row_counter
        STA teleport_exit_orient

        ; If exit is in a different room, switch now.
        LDA teleport_exit_room
        CMP current_room
        BEQ mt_room_ok

        LDA teleport_exit_room
        STA current_room
        JSR set_room_tilemap
        JSR set_room_portalmap
        JSR set_room_fizzlers
        JSR build_material_planes_from_tilemap

        ; Force full redraw on next render.
        LDA #1
        STA room_dirty
        STA chell_dirty
        ; Cancel reticle.
        LDA #0
        STA reticle_active
        STA reticle_prev_active
        STA reticle_has_under
        STA chell_has_under

.mt_room_ok
        ; Restore exit portal coords/orient (room switch clobbers X/Y/etc).
        LDX teleport_exit_x
        LDY teleport_exit_y
        LDA teleport_exit_orient
        STA row_counter

        ; Compute portal origin in pixels.
        ; portal_top_y = tile_y*16
        TYA
        ASL A
        ASL A
        ASL A
        ASL A
        STA col_counter          ; portal_top_y

        ; portal_left_x = tile_x*8 (+8 for wall-left art)
        TXA
        ASL A
        ASL A
        ASL A
        STA screen_ptr           ; portal_left_x base
        LDA row_counter
        CMP #PORTAL_ORIENT_WALL_L
        BNE mt_chk_wall_r_x
        LDA screen_ptr
        CLC
        ADC #8
        STA screen_ptr
        JMP mt_portal_x_ok

 .mt_chk_wall_r_x
        CMP #PORTAL_ORIENT_WALL_R
        BNE mt_portal_x_ok
        ; Wall-right portals occupy the empty space to the *left* of the wall tile.
        ; Shift the pixel origin left by 8px (clamp at 0).
        LDA screen_ptr
        SEC
        SBC #8
        BCS mt_wall_r_x_ok
        LDA #0
 .mt_wall_r_x_ok
        STA screen_ptr
 .mt_portal_x_ok

        ; --- Momentum mapping (all 4 orientations) ---
        ; entry_orient in temp_y.
        LDA teleport_entry_kind
        BEQ mt_entry_a
        LDA portal_b_orient
        BNE mt_entry_orient_ok
 .mt_entry_a
        LDA portal_a_orient
 .mt_entry_orient_ok
        STA temp_y

        ; Back-wall portals are entered deliberately via SPACE.
        ; We don't have a Z axis, so if either end is back-wall, keep vx/vy unchanged
        ; and only reposition Chell.
        LDA temp_y
        CMP #PORTAL_ORIENT_BACK
        BNE mt_back_chk_exit
        JMP mt_place_from_orient
 .mt_back_chk_exit
        LDA row_counter
        CMP #PORTAL_ORIENT_BACK
        BNE mt_back_ok
        JMP mt_place_from_orient
 .mt_back_ok

        ; Compute (v_t, v_n) in the entry portal frame.
        ; See project plan for definitions.
        LDA temp_y
        CMP #PORTAL_ORIENT_WALL_L
        BEQ mt_vtn_wall_l
        CMP #PORTAL_ORIENT_WALL_R
        BEQ mt_vtn_wall_r
        CMP #PORTAL_ORIENT_FLOOR
        BEQ mt_vtn_floor
        CMP #PORTAL_ORIENT_BACK
        BEQ mt_vtn_floor
        ; ceiling
        JMP mt_vtn_ceil

  .mt_vtn_wall_l
         ; t=(0,+1), n=(+1,0)
         ; v_t = vy (vertical) in px/frame  => vy_stripes*(1<<PORTAL_VY_TO_PX_SHIFT)
         ; v_n = -vx (horizontal) in px/frame
         ; Use prev_vy when we entered on the landing frame (char_vy already zeroed).
         JSR get_entry_vy
         JSR portal_mul_vy_to_px
         STA teleport_vt
         LDA char_vx
         JSR neg_a
         STA teleport_vn
         JMP mt_vtn_done
  .mt_vtn_wall_r
         ; t=(0,-1), n=(-1,0)
         ; v_t = -vy (vertical) in px/frame => -(vy_stripes*(1<<PORTAL_VY_TO_PX_SHIFT))
         ; v_n = vx (horizontal) in px/frame
         JSR get_entry_vy
         JSR portal_mul_vy_to_px
         JSR neg_a
         STA teleport_vt
         LDA char_vx
         STA teleport_vn
         JMP mt_vtn_done
  .mt_vtn_floor
         ; t=(+1,0), n=(0,-1)
         ; v_t = vx (horizontal) in px/frame
         ; v_n = vy (vertical) in px/frame => vy_stripes*(1<<PORTAL_VY_TO_PX_SHIFT)
         LDA char_vx
         STA teleport_vt
         JSR get_entry_vy
         JSR portal_mul_vy_to_px
         STA teleport_vn
         JMP mt_vtn_done
  .mt_vtn_ceil
         ; t=(-1,0), n=(0,+1)
         ; v_t = -vx (horizontal) in px/frame
         ; v_n = -vy (vertical) in px/frame => -(vy_stripes*(1<<PORTAL_VY_TO_PX_SHIFT))
         LDA char_vx
         JSR neg_a
         STA teleport_vt
         JSR get_entry_vy
         JSR portal_mul_vy_to_px
         JSR neg_a
         STA teleport_vn
  .mt_vtn_done

        ; Recompose v' into screen axes for the exit portal orientation.
        ; wall_l: vx=v_n,   vy=v_t
        ; wall_r: vx=-v_n,  vy=-v_t
        ; floor:  vx=v_t,   vy=-v_n
        ; ceil:   vx=-v_t,  vy=v_n
        LDA row_counter
        CMP #PORTAL_ORIENT_WALL_L
        BEQ mt_vout_wall_l
        CMP #PORTAL_ORIENT_WALL_R
        BEQ mt_vout_wall_r
        CMP #PORTAL_ORIENT_FLOOR
        BEQ mt_vout_floor
        CMP #PORTAL_ORIENT_BACK
        BEQ mt_vout_floor
        ; ceiling
        JMP mt_vout_ceil

  .mt_vout_wall_l
         LDA teleport_vn
         STA char_vx
         LDA teleport_vt
         JSR portal_div_px_to_vy
         STA char_vy
         JMP mt_vout_done
  .mt_vout_wall_r
         LDA teleport_vn
         JSR neg_a
         STA char_vx
         LDA teleport_vt
         JSR neg_a
         JSR portal_div_px_to_vy
         STA char_vy
         JMP mt_vout_done
  .mt_vout_floor
         LDA teleport_vt
         STA char_vx
         LDA teleport_vn
         JSR neg_a
         JSR portal_div_px_to_vy
         STA char_vy
         JMP mt_vout_done
  .mt_vout_ceil
         LDA teleport_vt
         JSR neg_a
         STA char_vx
         LDA teleport_vn
         JSR portal_div_px_to_vy
         STA char_vy
  .mt_vout_done

        ; Clamp to terminal limits after mapping.
        JSR clamp_char_vx
        JSR clamp_char_vy

        ; Reset fall_distance so wall/ceiling exits don't inherit fast-fall.
        LDA #0
        STA fall_distance

        ; If exiting downward (vy >= 2), engage fast-fall immediately.
        LDA char_vy
        CMP #2
        BCC mt_no_fast_fall
        LDA #FALL_FAST_THRESHOLD
        STA fall_distance
  .mt_no_fast_fall

 .mt_place_from_orient
        ; Exit placement from orientation.
        LDA row_counter
        CMP #PORTAL_ORIENT_WALL_L
        BEQ mt_place_wall_l
        CMP #PORTAL_ORIENT_WALL_R
        BEQ mt_place_wall_r
        CMP #PORTAL_ORIENT_FLOOR
        BEQ mt_place_floor
        CMP #PORTAL_ORIENT_BACK
        BEQ mt_place_back
        ; ceiling
        JMP mt_place_ceil

 .mt_place_wall_r
         ; right wall => exit to left.
        ; Place Chell so her right edge is nudged inside the opening.
        ; This avoids embedding any part of her body into the wall tile.
        ; right_edge = portal_left + (PORTAL_WALL_W_PX-1) - nudge
        LDA screen_ptr
        CLC
        ADC #(PORTAL_WALL_W_PX-1)
        SEC
        SBC #PORTAL_EXIT_NUDGE
        ; left = right_edge - (CHELL_W_PX-1)
        SEC
        SBC #(CHELL_W_PX-1)
        BCS mt_x_store
        LDA #0
        JMP mt_x_store

 .mt_place_wall_l
         ; left wall => exit to right.
        ; Place Chell so her left edge is nudged inside the opening.
        ; This avoids embedding any part of her body into the wall tile.
        LDA screen_ptr
        CLC
        ADC #PORTAL_EXIT_NUDGE
        CMP #128
        BCC mt_x_store
        LDA #127
        JMP mt_x_store

 .mt_place_floor
        ; floor => exit upward: center X on the 16px portal span.
        LDA screen_ptr
        STA temp                 ; new_x
        ; bottom just above the *surface* row (drawn 1 tile below stored y)
        LDA col_counter
        CLC
        ADC #16
        SEC
        SBC #PORTAL_EXIT_NUDGE
        SEC
        SBC #(CHELL_H_PX-1)
        JMP mt_y_store

 .mt_place_ceil
        ; ceiling => exit downward: center X on the 16px portal span.
        LDA screen_ptr
        STA temp                 ; new_x
        ; top just below the *surface* row (drawn 1 tile above stored y)
        LDA col_counter
        SEC
        SBC #16
        CLC
        ADC #PORTAL_FC_H_PX
        CLC
        ADC #PORTAL_EXIT_NUDGE
        JMP mt_y_store

 .mt_place_back
        ; Back wall: portal is a 16x32 zone in empty space.
        ; Place Chell's top-left at the portal top-left.
        LDA screen_ptr
        STA temp                 ; new_x
        LDA col_counter
        JMP mt_y_store

  .mt_x_store
        STA temp                 ; new_x
        ; default new_y = portal_top_y
        LDA col_counter
  .mt_y_store
        STA temp_y               ; new_y

        ; Quantize teleport exit Y to our 8px stripe grid.
        ; Vertical movement assumes char_y_offset is always 0 or 8; teleport placement
        ; can produce arbitrary low-nibble offsets (e.g. 15) which breaks stepping and
        ; can leave Chell "floating".
        ;
        ; Round down for all orientations. The PORTAL_EXIT_NUDGE already pushes
        ; Chell away from the surface; rounding up on ceiling exits overcorrects
        ; and embeds her one stripe into the floor below.
        LDA temp_y
        AND #&F8
        STA temp_y
        ; Prevent y+32 overflow in grounded checks (treats overflow as solid).
        ; Keep aligned to 8px stripes (max safe is 223 -> 216 when quantized).
        LDA temp_y
        CMP #224
        BCC mt_quant_y_done
        LDA #216
        STA temp_y
 .mt_quant_y_done

        ; Write Chell position from pixel coords.
        ; Y
        LDA temp_y
        AND #&F0
        STA char_tile_pos
        LDA temp_y
        AND #&0F
        STA char_y_offset

        ; X
        LDA temp
        LSR A
        LSR A
        LSR A
        ORA char_tile_pos
        STA char_tile_pos

        LDA temp
        AND #7
        CMP #4
        BCC mt_sub_lo
        ; sub 4..7
        SEC
        SBC #4
        STA char_pixel_offset
        LDA #8
        STA char_byte_offset
        JMP mt_x_done
.mt_sub_lo
        STA char_pixel_offset
        LDA #0
        STA char_byte_offset
.mt_x_done

        ; Facing:
        ; - wall exits: face away from wall
        ; - floor/ceiling exits: face by vx sign, else keep last
        LDA row_counter
        CMP #PORTAL_ORIENT_WALL_L
        BEQ mt_face_right
        CMP #PORTAL_ORIENT_WALL_R
        BEQ mt_face_left
        LDA char_vx
        BEQ mt_face_keep
        BMI mt_face_left
 .mt_face_right
        LDA #1
        BNE mt_face_store
 .mt_face_left
        LDA #0
        BEQ mt_face_store
 .mt_face_keep
        LDA last_anim_dir
 .mt_face_store
        STA anim_dir
        STA last_anim_dir

        ; Clear grounded state and any in-flight jump rise; preserve vertical velocity.
        LDA #0
        STA char_grounded
        STA jump_timer
        STA peak_timer

        ; Avoid immediate re-trigger / edge effects.
        LDA #0
        STA move_held
        STA last_move_held
        STA action_pressed        ; consume SPACE so cube drop doesn't fire
        LDA #PORTAL_COOLDOWN_FRAMES
        STA teleport_cooldown
        LDA #8
        STA exit_cooldown

        ; Mark for redraw.
        LDA #1
        STA chell_dirty

.mt_clear
        LDA #0
        STA teleport_pending
        RTS


 ; --- Small signed helpers ---
; Get the vertical entry velocity in stripes/frame.
; If the entry was detected on the landing/head-bonk frame, movement may have
; already zeroed char_vy; in that case use char_prev_vy.
; Returns: A = signed vy (stripes/frame)
.get_entry_vy
        LDA char_vy
        BNE gev_done
        LDA char_prev_vy
 .gev_done
        RTS


; Multiply signed A (vy stripes/frame) by (1<<PORTAL_VY_TO_PX_SHIFT) to produce a
; pixels/frame-ish value for portal momentum.
.portal_mul_vy_to_px
        LDX #PORTAL_VY_TO_PX_SHIFT
 .pmv_loop
        BEQ pmv_done
        ASL A
        DEX
        JMP pmv_loop
 .pmv_done
        RTS


; Divide signed A (pixels/frame-ish) by (1<<PORTAL_VY_TO_PX_SHIFT) to produce a
; vy stripes/frame value. Rounds toward 0.
.portal_div_px_to_vy
        LDX #PORTAL_VY_TO_PX_SHIFT
        BEQ pdv_done
        BMI pdv_neg
 .pdv_pos_loop
        LSR A
        DEX
        BNE pdv_pos_loop
 .pdv_done
        RTS
 .pdv_neg
        ; abs
        JSR neg_a
 .pdv_neg_loop
        LSR A
        DEX
        BNE pdv_neg_loop
        ; restore sign
        JSR neg_a
        RTS

; Negate signed A.
.neg_a
        EOR #&FF
        CLC
        ADC #1
        RTS


; Multiply signed A by 8 (assumes range small enough to not overflow).
.mul8_signed_a
        ASL A
        ASL A
        ASL A
        RTS


; Divide signed A by 8, rounding toward 0.
.div8_signed_a
        BMI div8_neg
        LSR A
        LSR A
        LSR A
        RTS
 .div8_neg
        ; abs
        JSR neg_a
        LSR A
        LSR A
        LSR A
        ; restore sign
        JSR neg_a
        RTS


; Clamp `char_vx` to [-TERMINAL_VELOCITY_X, +TERMINAL_VELOCITY_X].
.clamp_char_vx
        LDA char_vx
        BMI cvx_neg
        CMP #(TERMINAL_VELOCITY_X+1)
        BCC cvx_done
        LDA #TERMINAL_VELOCITY_X
        STA char_vx
 .cvx_done
        RTS
 .cvx_neg
        ; if |vx| > TERMINAL_VELOCITY_X => clamp
        EOR #&FF
        CLC
        ADC #1
        CMP #(TERMINAL_VELOCITY_X+1)
        BCC cvx_done
        LDA #TERMINAL_VELOCITY_X
        JSR neg_a
        STA char_vx
        RTS


; Clamp `char_vy` to [TERMINAL_VELOCITY_UP, TERMINAL_VELOCITY_DOWN].
.clamp_char_vy
        LDA char_vy
        BMI cvy_neg
        CMP #(TERMINAL_VELOCITY_DOWN+1)
        BCC cvy_done
        LDA #TERMINAL_VELOCITY_DOWN
        STA char_vy
 .cvy_done
        RTS
 .cvy_neg
        CMP #TERMINAL_VELOCITY_UP
        BCS cvy_done
        LDA #TERMINAL_VELOCITY_UP
        STA char_vy
        RTS


; Try portal A. SEC => pending set.
.cpei_try_portal_a
        LDA portal_a_enabled
        BNE cpei_a_enabled
        JMP cpei_a_no
 .cpei_a_enabled
        LDA portal_b_enabled
        BNE cpei_a_b_enabled
        JMP cpei_a_no
 .cpei_a_b_enabled
        LDA portal_a_room
        CMP current_room
        BEQ cpei_a_room_ok
        JMP cpei_a_no
 .cpei_a_room_ok

        ; Entry intent: dot(v, n_enter) < 0.
        ; (Axis-aligned portal normals.)
        LDA portal_a_orient
        CMP #PORTAL_ORIENT_WALL_L
        BEQ cpei_a_need_vx_neg
        CMP #PORTAL_ORIENT_WALL_R
        BEQ cpei_a_need_vx_pos
        CMP #PORTAL_ORIENT_FLOOR
        BEQ cpei_a_need_vy_pos
        CMP #PORTAL_ORIENT_BACK
        BEQ cpei_a_intent_ok
        ; ceiling
        JMP cpei_a_need_vy_neg

  .cpei_a_need_vx_pos
        LDA char_vx
        BNE cpei_a_vxpos_have
        LDA keys_held
        AND #2
        BEQ cpei_a_no
        BNE cpei_a_intent_ok
  .cpei_a_vxpos_have
        BMI cpei_a_no
        JMP cpei_a_intent_ok
  .cpei_a_need_vx_neg
        LDA char_vx
        BMI cpei_a_intent_ok
        BNE cpei_a_no
        LDA keys_held
        AND #1
        BNE cpei_a_intent_ok
        JMP cpei_a_no
   .cpei_a_need_vy_pos
        LDA char_vy
        BNE cpei_a_vypos_have
        LDA char_prev_vy
    .cpei_a_vypos_have
        BEQ cpei_a_vypos_ground
        BMI cpei_a_no
        JMP cpei_a_intent_ok
 .cpei_a_vypos_ground
        ; Walking onto a floor portal should trigger it even when vy is 0.
        LDA char_grounded
        BNE cpei_a_intent_ok
        JMP cpei_a_no
 .cpei_a_need_vy_neg
        LDA char_vy
        BNE cpei_a_vyneg_have
        LDA char_prev_vy
 .cpei_a_vyneg_have
        BMI cpei_a_intent_ok
        JMP cpei_a_no
 .cpei_a_intent_ok

        ; Back wall portals require SPACE.
        LDA portal_a_orient
        CMP #PORTAL_ORIENT_BACK
        BNE cpei_a_intent_done
        LDA action_held
        BEQ cpei_a_no
 .cpei_a_intent_done

        ; Overlap test against portal rect.
        LDA portal_a_orient
        LDX portal_a_x
        LDY portal_a_y
        JSR cpei_overlap_portal_xy
        BCC cpei_a_no

        ; Cooldown only blocks re-entering the portal we just exited.
        LDA teleport_cooldown
        BEQ cpei_a_ok
        LDA teleport_last_exit_kind
        CMP #0
        BEQ cpei_a_no
  .cpei_a_ok

        LDA #1
        STA teleport_pending
        LDA #0
        STA teleport_entry_kind
        SEC
        RTS

.cpei_a_no
        CLC
        RTS


; Try portal B. SEC => pending set.
.cpei_try_portal_b
        LDA portal_b_enabled
        BNE cpei_b_enabled
        JMP cpei_b_no
 .cpei_b_enabled
        LDA portal_a_enabled
        BNE cpei_b_a_enabled
        JMP cpei_b_no
 .cpei_b_a_enabled
        LDA portal_b_room
        CMP current_room
        BEQ cpei_b_room_ok
        JMP cpei_b_no
 .cpei_b_room_ok

        ; Entry intent: dot(v, n_enter) < 0. (See portal A version.)
        LDA portal_b_orient
        CMP #PORTAL_ORIENT_WALL_L
        BEQ cpei_b_need_vx_neg
        CMP #PORTAL_ORIENT_WALL_R
        BEQ cpei_b_need_vx_pos
        CMP #PORTAL_ORIENT_FLOOR
        BEQ cpei_b_need_vy_pos
        CMP #PORTAL_ORIENT_BACK
        BEQ cpei_b_intent_ok
        ; ceiling
        JMP cpei_b_need_vy_neg

  .cpei_b_need_vx_pos
        LDA char_vx
        BNE cpei_b_vxpos_have
        LDA keys_held
        AND #2
        BEQ cpei_b_no
        BNE cpei_b_intent_ok
  .cpei_b_vxpos_have
        BMI cpei_b_no
        JMP cpei_b_intent_ok
  .cpei_b_need_vx_neg
        LDA char_vx
        BMI cpei_b_intent_ok
        BNE cpei_b_no
        LDA keys_held
        AND #1
        BNE cpei_b_intent_ok
        JMP cpei_b_no
   .cpei_b_need_vy_pos
        LDA char_vy
        BNE cpei_b_vypos_have
        LDA char_prev_vy
    .cpei_b_vypos_have
        BEQ cpei_b_vypos_ground
        BMI cpei_b_no
        JMP cpei_b_intent_ok
 .cpei_b_vypos_ground
        ; Walking onto a floor portal should trigger it even when vy is 0.
        LDA char_grounded
        BNE cpei_b_intent_ok
        JMP cpei_b_no
 .cpei_b_need_vy_neg
        LDA char_vy
        BNE cpei_b_vyneg_have
        LDA char_prev_vy
 .cpei_b_vyneg_have
        BMI cpei_b_intent_ok
        JMP cpei_b_no
 .cpei_b_intent_ok

        ; Back wall portals require SPACE.
        LDA portal_b_orient
        CMP #PORTAL_ORIENT_BACK
        BNE cpei_b_intent_done
        LDA action_held
        BEQ cpei_b_no
 .cpei_b_intent_done

        ; Overlap test against portal rect.
        LDA portal_b_orient
        LDX portal_b_x
        LDY portal_b_y
        JSR cpei_overlap_portal_xy
        BCC cpei_b_no

        ; Cooldown only blocks re-entering the portal we just exited.
        LDA teleport_cooldown
        BEQ cpei_b_ok
        LDA teleport_last_exit_kind
        CMP #1
        BEQ cpei_b_no
  .cpei_b_ok

        LDA #1
        STA teleport_pending
        LDA #1
        STA teleport_entry_kind
        SEC
        RTS

.cpei_b_no
        CLC
        RTS


; Overlap test: Chell rect (temp..temp_y, row_counter..col_counter)
; vs portal tile rect at (X=tile_x,Y=tile_y) with orientation in A.
;
; Returns: C=1 if overlap, C=0 otherwise.
; Inputs:
; - A = orient (0..4)
; - X = tile_x
; - Y = tile_y
; Clobbers: A,temp
.cpei_overlap_portal_xy
        CMP #PORTAL_ORIENT_FLOOR
        BCS cpei_overlap_fc

        ; Wall portals (8x32)
        ; Portal opening sits in the empty space adjacent to the wall tile:
        ; - wall-left  => opening is to the right  (x+1)
        ; - wall-right => opening is to the left   (x-1)
        CMP #PORTAL_ORIENT_WALL_L
        BNE cpei_overlap_wall_try_r
        CPX #15
        BEQ cpei_overlap_wall_x_ok
        INX
        JMP cpei_overlap_wall_x_ok

 .cpei_overlap_wall_try_r
        CMP #PORTAL_ORIENT_WALL_R
        BNE cpei_overlap_wall_x_ok
        CPX #0
        BEQ cpei_overlap_wall_x_ok
        DEX
 .cpei_overlap_wall_x_ok
        JSR cpei_overlap_tile_xy_8x32
        RTS

.cpei_overlap_fc
        ; Back-wall portals: 16x32 (2 tiles wide x 2 tiles tall)
        CMP #PORTAL_ORIENT_BACK
        BEQ cpei_overlap_back

        ; Floor/ceiling portals: 16x16 (2 tiles wide x 1 tile tall)
        ; AABB overlap, plus an X-center alignment guard.

        ; portal_left_x = tile_x*8
        TXA
        ASL A
        ASL A
        ASL A
        STA screen_ptr

        ; If chell_right_x < portal_left_x => no overlap
        LDA temp_y
        CMP screen_ptr
        BCC cpei_fc_no

        ; portal_right_x = portal_left_x + (PORTAL_FC_W_PX-1)
        LDA screen_ptr
        CLC
        ADC #(PORTAL_FC_W_PX-1)
        ; If portal_right_x < chell_left_x => no overlap
        CMP temp
        BCC cpei_fc_no

        ; portal_top_y = tile_y*16
        TYA
        ASL A
        ASL A
        ASL A
        ASL A
        STA screen_ptr+1

        ; If chell_bottom_y < portal_top_y => no overlap
        LDA col_counter
        CMP screen_ptr+1
        BCC cpei_fc_no

        ; portal_bottom_y = portal_top_y + (PORTAL_FC_H_PX-1)
        LDA screen_ptr+1
        CLC
        ADC #(PORTAL_FC_H_PX-1)
        ; If portal_bottom_y < chell_top_y => no overlap
        CMP row_counter
        BCC cpei_fc_no

        ; X-center alignment guard:
        ; |chell_left - portal_left| <= PORTAL_ALIGN_TOL_X
        LDA temp
        SEC
        SBC screen_ptr
        BPL cpei_fc_dx_pos
        EOR #&FF
        CLC
        ADC #1
 .cpei_fc_dx_pos
        CMP #(PORTAL_ALIGN_TOL_X+1)
        BCS cpei_fc_no

        SEC
        RTS

 .cpei_fc_no
        CLC
        RTS

 .cpei_overlap_back
        ; portal_left_x = tile_x*8
        TXA
        ASL A
        ASL A
        ASL A
        STA screen_ptr

        ; If chell_right_x < portal_left_x => no overlap
        LDA temp_y
        CMP screen_ptr
        BCC cpei_fc_no

        ; portal_right_x = portal_left_x + 15
        LDA screen_ptr
        CLC
        ADC #15
        ; If portal_right_x < chell_left_x => no overlap
        CMP temp
        BCC cpei_fc_no

        ; portal_top_y = tile_y*16
        TYA
        ASL A
        ASL A
        ASL A
        ASL A
        STA screen_ptr+1

        ; If chell_bottom_y < portal_top_y => no overlap
        LDA col_counter
        CMP screen_ptr+1
        BCC cpei_fc_no

        ; portal_bottom_y = portal_top_y + 31
        LDA screen_ptr+1
        CLC
        ADC #31
        ; If portal_bottom_y < chell_top_y => no overlap
        CMP row_counter
        BCC cpei_fc_no

        SEC
        RTS


; Overlap test: Chell rect (temp..temp_y, row_counter..col_counter)
; vs portal tile rect at (X=tile_x,Y=tile_y) sized 8x32 pixels.
;
; Returns: C=1 if overlap, C=0 otherwise.
; Clobbers: A,temp
.cpei_overlap_tile_xy_8x32
        ; portal_left_x = tile_x*8
        TXA
        ASL A
        ASL A
        ASL A

        ; stash portal_left_x
        STA screen_ptr

        ; If chell_right_x < portal_left_x => no overlap
        LDA temp_y
        CMP screen_ptr
        BCS cpei_x_ok0         ; chell_right_x >= portal_left_x
        ; chell_right_x < portal_left_x
        CLC
        RTS
.cpei_x_ok0

        ; portal_right_x = portal_left_x + (PORTAL_WALL_W_PX-1)
        LDA screen_ptr
        CLC
        ADC #(PORTAL_WALL_W_PX-1)
        ; If chell_left_x > portal_right_x => no overlap
        CMP temp
        BEQ cpei_x_ok1
        BCS cpei_x_ok1         ; portal_right_x >= chell_left_x
        ; portal_right_x < chell_left_x
        CLC
        RTS
.cpei_x_ok1

        ; portal_top_y = tile_y*16
        TYA
        ASL A
        ASL A
        ASL A
        ASL A

        ; stash portal_top_y
        STA screen_ptr+1

        ; Vertical sensitivity guard:
        ; Require that Chell's vertical center is close to the portal's vertical
        ; center. This prevents accidental teleports when she just grazes a
        ; portal with hair/feet.
        ;
        ; chell_center_y  = chell_top_y + 16
        ; portal_center_y = portal_top_y + (PORTAL_WALL_H_PX/2)
        ; require |chell_center_y - portal_center_y| <= PORTAL_ALIGN_TOL_Y

        ; portal_center_y -> temp
        LDA screen_ptr+1
        CLC
        ADC #(PORTAL_WALL_H_PX/2)
        STA temp

        ; chell_center_y -> temp_y
        LDA row_counter
        CLC
        ADC #16
        STA temp_y

        ; lower = portal_center_y - PORTAL_ALIGN_TOL_Y
        LDA temp
        SEC
        SBC #PORTAL_ALIGN_TOL_Y
        STA screen_ptr+1

        ; if chell_center_y < lower => no overlap
        LDA temp_y
        CMP screen_ptr+1
        BCC cpei_y_no

        ; upper = portal_center_y + PORTAL_ALIGN_TOL_Y
        LDA temp
        CLC
        ADC #PORTAL_ALIGN_TOL_Y
        STA screen_ptr+1

        ; if chell_center_y > upper => no overlap
        LDA temp_y
        CMP screen_ptr+1
        BEQ cpei_y_ok
        BCC cpei_y_ok
.cpei_y_no
        CLC
        RTS
.cpei_y_ok

        SEC
        RTS
