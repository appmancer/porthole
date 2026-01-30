; movement.asm
; Chell movement, collision sampling, and gravity stepping.

 ; Poll Z/X for left/right movement (single-pixel).
 ;
 ; Uses OSBYTE 129 (INKEY) "scan for a particular key":
 ;   On entry:  Y=&FF, X=&80..&FF (negative INKEY number)
 ;   On exit:   XY=&FFFF if pressed, else XY=&0000
 ; Horizontal position is represented as:
 ;   char_tile_pos      = 8px steps (cell_x)
 ;   char_byte_offset   = 0 or 8 (4px step within a cell, MODE5 column stride)
 ;   char_pixel_offset  = 0..3 (1px subpixel via pre-shifted sprites)
 ;
 ; Output: C=1 if sprite needs redraw.
 .poll_move_keys
      ; Track move key transitions so we can redraw into idle.
      LDA move_held
      STA last_move_held

      LDA #0
      STA temp                  ; redraw flag
      STA move_held             ; clear each frame; set when key held


     ; Jump on RETURN (edge-triggered) when grounded.
     LDA keys_pressed_latch
     AND #4
     BEQ after_jump

     ; Only start a jump if grounded and not already moving vertically.
     LDA char_grounded
     BEQ after_jump
     LDA char_vy
     BNE after_jump

     ; Capture jump direction from held movement key.
     LDA keys_held
     AND #1
     BNE jump_face_left
     LDA keys_held
     AND #2
     BNE jump_face_right
     JMP jump_dir_done

 .jump_face_left
     LDA #0
     STA anim_dir
     STA last_anim_dir
     JMP jump_dir_done

 .jump_face_right
     LDA #1
     STA anim_dir
     STA last_anim_dir

 .jump_dir_done
     ; Start jump: upward velocity.
     LDA #JUMP_VELOCITY
     STA char_vy
     LDA #0
     STA char_grounded

     ; Preserve horizontal motion into the jump.
     LDA last_anim_dir
     BEQ jump_set_vx_left
     LDA #WALK_VELOCITY
     STA char_vx
     JMP jump_vx_done
 .jump_set_vx_left
     LDA #&FF                 ; -WALK_VELOCITY (WALK_VELOCITY=1)
     STA char_vx
 .jump_vx_done

     ; Delay next gravity tick slightly so the jump starts cleanly.
     LDA #(GRAVITY_UP_PERIOD-1)
     STA gravity_cooldown

     LDA #1
     STA temp

 .after_jump

    ; Determine intended facing from keys (prefer left if both held).
    LDA keys_held
    AND #1
    BEQ pmk_check_right
    LDA #0
    STA anim_dir
    JMP pmk_have_dir

 .pmk_check_right
    LDA keys_held
    AND #2
    BEQ pmk_no_dir
    LDA #1
    STA anim_dir

 .pmk_have_dir
      ; Mark movement intent.
      LDA #1
      STA move_held

      ; If direction changed, force a redraw so we flip immediately.
      LDA anim_dir
      CMP last_anim_dir
      BEQ pmk_dir_ok
      STA last_anim_dir
      LDA #1
      STA temp
 .pmk_dir_ok

      ; Input only sets vx while grounded, or if airborne and already slow.
      LDA char_grounded
      BNE pmk_set_walk_vx

      ; Airborne: keep fling momentum. Allow light air control only if |vx| <= WALK_VELOCITY.
      LDA char_vx
      BEQ pmk_set_walk_vx
      BMI pmk_air_abs_neg
      CMP #(WALK_VELOCITY+1)
      BCC pmk_set_walk_vx
      JMP pmk_after_vx
 .pmk_air_abs_neg
      EOR #&FF
      CLC
      ADC #1
      CMP #(WALK_VELOCITY+1)
      BCC pmk_set_walk_vx
      JMP pmk_after_vx

 .pmk_set_walk_vx
      LDA anim_dir
      BEQ pmk_set_vx_left
      LDA #WALK_VELOCITY
      STA char_vx
      JMP pmk_after_vx
 .pmk_set_vx_left
      LDA #&FF                 ; -WALK_VELOCITY (WALK_VELOCITY=1)
      STA char_vx
      JMP pmk_after_vx

 .pmk_no_dir
      ; No key held: stop movement intent, but keep animation phase.
      LDA #0
      STA move_held

      ; If grounded, kill horizontal velocity.
      LDA char_grounded
      BEQ pmk_no_key_air
      LDA #0
      STA char_vx
 .pmk_no_key_air

      ; If we just released movement keys while grounded, redraw to idle.
      LDA last_move_held
      BEQ pmk_after_vx
      LDA char_grounded
      BEQ pmk_after_vx
      LDA #1
      STA temp

 .pmk_after_vx
      ; Apply horizontal velocity (vx magnitude matters).
      JSR apply_horizontal_velocity
      STA temp_y               ; moved pixels this frame
      BEQ pmk_after_move

      LDA #1
      STA temp

      ; Advance animation every 4 pixels moved, but at most once per frame.
      ; (High vx can move many pixels; don't spin the run cycle too fast.)
      ; Keep anim_cooldown bounded (older code treated it as small).
      LDA anim_cooldown
      AND #3
      STA anim_cooldown
      LDA anim_cooldown
      CLC
      ADC temp_y
      STA anim_cooldown
      CMP #4
      BCC pmk_after_move
      SEC
      SBC #4
      STA anim_cooldown
      JSR step_anim

 .pmk_after_move
      ; Keep facing, but sync last_anim_dir.
      LDA anim_dir
      STA last_anim_dir

     LDA temp
     BEQ no_redraw
     SEC
     RTS
  .no_redraw
     CLC
     RTS
 
 .step_anim
    INC anim_frame
    LDA anim_frame
    AND #3
    STA anim_frame
    RTS


; Apply horizontal velocity using `char_vx` magnitude.
; - `char_vx` is signed pixels/frame.
; - Clamps per-frame stepping to `TERMINAL_VELOCITY_X` to bound frame time.
; - On collision, zeroes `char_vx`.
; Output: A = moved pixels (0..TERMINAL_VELOCITY_X)
.apply_horizontal_velocity
    LDA char_vx
    BEQ ahv_none
    BMI ahv_left

 .ahv_right
     ; speed = min(vx, TERMINAL_VELOCITY_X)
     CMP #TERMINAL_VELOCITY_X
     BCC ahv_have_speed
     LDA #TERMINAL_VELOCITY_X
  .ahv_have_speed
     STA hstep_rem            ; steps remaining
     LDA #0
     STA hstep_moved          ; moved
 .ahv_r_loop
     JSR step_right_pixel
     BCS ahv_r_moved
     ; blocked
     LDA #0
     STA char_vx
     LDA hstep_moved
     RTS
 .ahv_r_moved
     INC hstep_moved
     DEC hstep_rem
     BNE ahv_r_loop
     LDA hstep_moved
     RTS

 .ahv_left
     ; speed = min(|vx|, TERMINAL_VELOCITY_X)
     EOR #&FF
     CLC
     ADC #1
     CMP #TERMINAL_VELOCITY_X
     BCC ahv_l_have_speed
     LDA #TERMINAL_VELOCITY_X
 .ahv_l_have_speed
     STA hstep_rem            ; steps remaining
     LDA #0
     STA hstep_moved          ; moved
 .ahv_l_loop
     JSR step_left_pixel
     BCS ahv_l_moved
     ; blocked
     LDA #0
     STA char_vx
     LDA hstep_moved
     RTS
 .ahv_l_moved
     INC hstep_moved
     DEC hstep_rem
     BNE ahv_l_loop
     LDA hstep_moved
     RTS

 .ahv_none
     LDA #0
     RTS
 
 ; Step left by 1 pixel.
 ; Output: C=1 if moved.
 .step_left_pixel
    ; If at absolute left bound, do nothing.
    LDA char_tile_pos
    AND #15
    BNE can_step_left
    LDA char_byte_offset
    ORA char_pixel_offset
    BEQ step_left_blocked

 .can_step_left
     ; Collision check at new left edge.
     JSR will_collide_left
     BCS step_left_blocked
 
 .step_left_do_step
     LDA char_pixel_offset

    BNE step_left_dec_sub
 
    ; Wrap subpixel 0 -> 3 and move base left by 4px.
    LDA #3
    STA char_pixel_offset
 
    LDA char_byte_offset
    BNE step_left_byte_to0
 
    ; byte_offset 0: go to previous cell and use byte_offset 8.
    LDA #8
    STA char_byte_offset
    DEC char_tile_pos
    SEC
    RTS
 
 .step_left_byte_to0
    LDA #0
    STA char_byte_offset
    SEC
    RTS
 
 .step_left_dec_sub
    DEC char_pixel_offset
    SEC
    RTS
 
 .step_left_blocked
    CLC
    RTS


; Compute current character X (left edge) in pixels.
; Output: A = x (0..127)
.calc_char_x
    LDA char_tile_pos
    AND #15
    ASL A
    ASL A
    ASL A
    STA temp

    ; char_byte_offset is 0 or 8 (i.e. 0 or 4 pixels)
    LDA char_byte_offset
    LSR A
    CLC
    ADC temp
    ADC char_pixel_offset
    RTS


; Compute current character Y (top edge) in pixels.
; Output: A = y (0..255)
.calc_char_y
    ; y = tile_y*16 + char_y_offset
    LDA char_tile_pos
    AND #&F0
    CLC
    ADC char_y_offset
    RTS


; Check if moving left 1px would collide.
; Output: C=1 if collision.
.will_collide_left
    JSR calc_char_x
    BEQ collide_left

    ; Centerline walls: allow 4px overlap into solid tiles.
    ; Instead of testing the pixel just outside the left edge (x-1), test
    ; 4px inside it: (x-1)+4 = x+3.
    CLC
    ADC #3
    TAX

    ; Sample near vertical centerlines of the wall tiles.
    ; (This avoids foot/head edge jitter when straddling stripes.)
    JSR calc_char_y
    CLC
    ADC #8
    STA temp_y

    ; test at y+8 (top tile centerline)
    LDY temp_y
    JSR is_solid_physics
    BCS collide_left

    ; test at y+24 (bottom tile centerline)
    LDY temp_y
    TYA
    CLC
    ADC #16
    TAY
    JSR is_solid_physics
    BCS collide_left

    CLC
    RTS
.collide_left
    SEC
    RTS


; Check if moving right 1px would collide.
; Output: C=1 if collision.
.will_collide_right
    JSR calc_char_x

    ; Centerline walls:
    ; Allow a small overlap into solid tiles (4px) so collision feels less
    ; "boxy" without letting the feet samples enter the wall column.
    ;
    ; Instead of testing just outside the right edge (x+16), test 4px inside it.
    CLC
    ADC #12              ; test point 4px inside right edge
    BCS collide_right    ; overflow => beyond 255 (treat as solid)
    CMP #128
    BCS collide_right
    TAX

    ; Sample near vertical centerlines of the wall tiles.
    ; (This avoids foot/head edge jitter when straddling stripes.)
    JSR calc_char_y
    CLC
    ADC #8
    STA temp_y

    ; test at y+8 (top tile centerline)
    LDY temp_y
    JSR is_solid_physics
    BCS collide_right

    ; test at y+24 (bottom tile centerline)
    LDY temp_y
    TYA
    CLC
    ADC #16
    TAY
    JSR is_solid_physics
    BCS collide_right

    CLC
    RTS
.collide_right
    SEC
    RTS
  

; Apply vertical physics (jump/fall).
; - Moves by current `char_vy` (signed, in 8px steps).
; - Then applies gravity to `char_vy` for next frame.
; - Clamps falling speed to `TERMINAL_VELOCITY`.
;
; Returns: C=1 if position changed (needs redraw).
 .apply_gravity
    ; Remember pre-step vy so portal entry can trigger on landing.
    LDA char_vy
    STA char_prev_vy

    ; Jumping (vy negative) must be treated as airborne even if we were grounded
    ; at the start of the frame.
    LDA char_vy
    BMI apply_airborne

    ; If we're grounded, pin vy to 0 and don't move.
    JSR is_char_grounded
    BCC apply_airborne

    ; If we were airborne last frame, landing changes pose (jump -> idle), so
    ; force a redraw even if we didn't move this frame.
    LDA char_grounded
    BNE apply_grounded_already

    LDA #1
    STA char_grounded
    LDA #0
    STA char_vy
    STA gravity_cooldown
    SEC
    RTS

 .apply_grounded_already
    LDA #1
    STA char_grounded
    LDA #0
    STA char_vy
    STA gravity_cooldown
    CLC
    RTS

 .apply_airborne
     LDA #0
     STA char_grounded

     LDA #0
     STA temp          ; moved flag

     ; Move by current vy.
     LDA char_vy
     BNE ag_vy_nonzero
     JMP apply_gravity_only
 .ag_vy_nonzero
     BMI apply_move_up

.apply_move_down
     ; For low fall speeds, keep the old paced feel (one stripe step every
     ; FALL_STEP_PERIOD frames). For high fall speeds (fling), allow multiple
     ; stripes per frame.
     LDA char_vy
     CMP #2
     BCS fall_fast

     ; vy = 1: paced fall.
     LDA fall_cooldown
     BEQ fall_paced_do
     DEC fall_cooldown
     JMP apply_gravity_only
 .fall_paced_do
     LDA #(FALL_STEP_PERIOD-1)
     STA fall_cooldown
     JSR step_down_8
     BCC hit_ground
     LDA #1
     STA temp
     JMP apply_gravity_only

 .fall_fast
     ; vy >= 2: move by vy stripes this frame.
     LDA char_vy
     STA row_counter            ; steps remaining
 .fall_step_loop
     JSR step_down_8
     BCC hit_ground
     LDA #1
     STA temp
     DEC row_counter
     BNE fall_step_loop
     JMP apply_gravity_only

.apply_move_up
     ; Clamp rising speed to avoid pathological per-frame work.
     LDA char_vy
     CMP #TERMINAL_VELOCITY_UP
     BCS rise_vy_ok
     LDA #TERMINAL_VELOCITY_UP
     STA char_vy
 .rise_vy_ok

     ; For small jump speeds, keep the old paced rise feel (one stripe step
     ; every RISE_STEP_PERIOD frames). For high upward speeds (fling), allow
     ; multiple stripes per frame.

     ; abs(vy) in A
     LDA char_vy
     EOR #&FF
     CLC
     ADC #1
     CMP #3
     BCS rise_fast

     ; abs(vy) = 1..2: paced rise.
     LDA rise_cooldown
     BEQ rise_paced_do
     DEC rise_cooldown
     JMP apply_gravity_only
 .rise_paced_do
     LDA #(RISE_STEP_PERIOD-1)
     STA rise_cooldown
     JSR step_up_8
     BCC hit_ceiling
     LDA #1
     STA temp
     JMP apply_gravity_only

 .rise_fast
     ; abs(vy) >= 3: move by -vy stripes this frame.
     ; steps remaining = -vy
     LDA char_vy
     EOR #&FF
     CLC
     ADC #1
     STA row_counter
 .rise_step_loop
     JSR step_up_8
     BCC hit_ceiling
     LDA #1
     STA temp
     DEC row_counter
     BNE rise_step_loop
     JMP apply_gravity_only

 .hit_ground
     ; Collided: stop and mark grounded.
     LDA #0
     STA char_vy
     STA gravity_cooldown
     STA fall_cooldown
     STA rise_cooldown
     LDA #1
     STA char_grounded

    ; Landing changes pose (jump -> idle), so force a redraw even if we didn't
    ; move this frame.
    STA temp
    JMP apply_return

.hit_ceiling
     ; Hit head: stop upward motion.
     LDA #0
     STA char_vy

.apply_gravity_only
    ; If we landed during movement, don't re-accelerate.
    LDA char_grounded
    BNE apply_return

    ; Gravity for next frame (rate-limited).
    LDA gravity_cooldown
    BEQ do_gravity_tick
    DEC gravity_cooldown
    JMP apply_return

.do_gravity_tick
    ; Use a slower tick while rising (floatier jump), but always tick while
    ; falling so you can build momentum by dropping.
    LDA char_vy
    BMI gravity_rising

    LDA #(GRAVITY_DOWN_PERIOD-1)
    STA gravity_cooldown
    JMP gravity_apply

.gravity_rising
    LDA #(GRAVITY_UP_PERIOD-1)
    STA gravity_cooldown

 .gravity_apply
     LDA char_vy
     CLC
     ADC #GRAVITY_ACCEL
     STA temp_y

     ; Fast-fall disabled for now.

 .grav_clamp
     LDA temp_y

     ; Clamp positive vy to the (higher) falling terminal velocity.
     BMI store_vy
     CMP #TERMINAL_VELOCITY_DOWN
     BCC store_vy
     LDA #TERMINAL_VELOCITY_DOWN

.store_vy
    STA char_vy

.apply_return
    LDA temp
    BEQ grav_no_move
    SEC
    RTS
.grav_no_move
    CLC
    RTS


; Return C=1 if character is standing on solid.
.is_char_grounded
    ; x = left and right sample points (x+4 and x+11)
    JSR calc_char_x
    CLC
    ADC #4
    STA temp

    ; y_test = (y + 32) (just below feet edge)
    JSR calc_char_y
    CLC
    ADC #32
    BCS grounded_true
    TAY

    ; left foot center
    LDX temp
    JSR is_solid_physics
    BCS grounded_true

    ; right foot center (x+7)
    LDA temp
    CLC
    ADC #7
    CMP #128
    BCS grounded_true
    TAX
    JSR is_solid_physics
    BCS grounded_true

    CLC
    RTS
.grounded_true
    SEC
    RTS


; Step down by 8 pixels (one stripe).
; Output: C=1 if moved.
.step_down_8
    JSR will_collide_down_8
    BCS step_down_blocked

    LDA char_y_offset
    BEQ step_down_to8

    ; Was at +8: wrap to +0 and advance to next cell row.
    LDA #0
    STA char_y_offset
    LDA char_tile_pos
    CLC
    ADC #16
    STA char_tile_pos
    SEC
    RTS

.step_down_to8
    LDA #8
    STA char_y_offset
    SEC
    RTS

.step_down_blocked
    CLC
    RTS


; Step up by 8 pixels (one stripe).
; Output: C=1 if moved.
.step_up_8
    JSR will_collide_up_8
    BCS step_up_blocked

    LDA char_y_offset
    BNE step_up_to0

    ; Was at +0: wrap to +8 and move to previous cell row.
    LDA #8
    STA char_y_offset
    LDA char_tile_pos
    SEC
    SBC #16
    STA char_tile_pos
    SEC
    RTS

.step_up_to0
    LDA #0
    STA char_y_offset
    SEC
    RTS

.step_up_blocked
    CLC
    RTS


; Return C=1 if moving down 8px would collide.
.will_collide_down_8
    ; x sample points (x+4 and x+11)
    JSR calc_char_x
    CLC
    ADC #4
    STA temp

    ; y_test = (y + 8) + 31 (just below feet edge after stepping down)
    ; Keep vertical landing aligned to the 8px stripe grid.
    JSR calc_char_y
    CLC
    ADC #39
    BCS collide_down
    TAY

    ; left foot center
    LDX temp
    JSR is_solid_physics
    BCS collide_down

    ; right foot center (x+7)
    LDA temp
    CLC
    ADC #7
    CMP #128
    BCS collide_down
    TAX
    JSR is_solid_physics
    BCS collide_down

    CLC
    RTS
.collide_down
    SEC
    RTS


; Return C=1 if moving up 8px would collide.
.will_collide_up_8
    ; x sample points (x+4 and x+11)
    JSR calc_char_x
    CLC
    ADC #4
    STA temp

    ; y_test = (y - 8) (top edge after stepping up)
    ; (Ceiling contact still needs to match the stripe grid.)
    JSR calc_char_y
    CMP #8
    BCC collide_up
    SEC
    SBC #8
    TAY

    ; left head center
    LDX temp
    JSR is_solid_physics
    BCS collide_up

    ; right head center (x+7)
    LDA temp
    CLC
    ADC #7
    CMP #128
    BCS collide_up
    TAX
    JSR is_solid_physics
    BCS collide_up

    CLC
    RTS
.collide_up
    SEC
    RTS


; Step right by 1 pixel.
; Output: C=1 if moved.
.step_right_pixel
    ; Clamp/limit to max X so sprite stays on-screen.
    ; Max position is tile_x=14, byte_offset=0, pixel_offset=0 (x=112 for 16px sprite).
    LDA char_tile_pos
    AND #15
    CMP #14
    BNE can_step_right
    LDA char_byte_offset
    ORA char_pixel_offset
    BEQ step_right_blocked
 
    ; If we ever got beyond max, clamp back.
    LDA #0
    STA char_byte_offset
    STA char_pixel_offset
    CLC
    RTS
 
.can_step_right
    ; Collision check at new right edge.
    JSR will_collide_right
    BCS step_right_blocked

.step_right_do_step
    LDA char_pixel_offset
    CMP #3
    BNE step_right_inc_sub
 
    ; Wrap subpixel 3 -> 0 and move base right by 4px.
    LDA #0
    STA char_pixel_offset
 
    LDA char_byte_offset
    BEQ step_right_byte_to8
 
    ; byte_offset 8: move to next cell and clear byte_offset.
    LDA #0
    STA char_byte_offset
    INC char_tile_pos
    SEC
    RTS
 
.step_right_byte_to8
    LDA #8
    STA char_byte_offset
    SEC
    RTS
 
.step_right_inc_sub
    INC char_pixel_offset
    SEC
    RTS
 
.step_right_blocked
    CLC
    RTS
