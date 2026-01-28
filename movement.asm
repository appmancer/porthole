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
     LDA keys_pressed
     AND #4
     BEQ after_jump

     ; Only start a jump if grounded and not already moving vertically.
     LDA char_grounded
     BEQ after_jump
     LDA char_vy
     BNE after_jump

     ; Capture jump direction from held movement key.
     ; (This ensures "jump left" even if move cooldown delays a step.)
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
     LDA #0
     STA move_cooldown
     JMP jump_dir_done

 .jump_face_right
     LDA #1
     STA anim_dir
     STA last_anim_dir
     LDA #0
     STA move_cooldown

 .jump_dir_done
     ; Start jump: upward velocity.
     LDA #JUMP_VELOCITY
     STA char_vy
     LDA #0
     STA char_grounded

     ; Delay next gravity tick slightly so the jump starts cleanly.
     LDA #(GRAVITY_UP_PERIOD-1)
     STA gravity_cooldown

     ; Allow an immediate upward step this frame.
     LDA #0
     STA rise_cooldown

     ; Reset fall pacing when a jump starts.
     STA fall_cooldown

     LDA #1
     STA temp

 .after_jump
 
    ; Prefer left if both held.
    LDA keys_held
    AND #1
    BEQ check_right
    JMP key_left

 .check_right
    LDA keys_held
    AND #2
    BEQ no_key_held
    JMP key_right
 
 .no_key_held
      ; No key held: stop movement, but keep animation phase.
      ; This lets quick 1px taps still advance the walk cycle.
      LDA #0
      STA move_held
      STA move_cooldown

      ; If grounded, kill horizontal velocity.
      ; If airborne and we have velocity, keep drifting.
      LDA char_grounded
      BEQ no_key_airborne
      LDA #0
      STA char_vx
      JMP no_key_after_vx

  .no_key_airborne
      LDA char_vx
      BEQ no_key_after_vx
      BMI no_key_drift_left
      ; drift right
      JSR step_right_pixel
      BCS no_key_drift_moved
      ; hit wall => stop
      LDA #0
      STA char_vx
      JMP no_key_after_vx
  .no_key_drift_left
      JSR step_left_pixel
      BCS no_key_drift_moved
      LDA #0
      STA char_vx
      JMP no_key_after_vx
  .no_key_drift_moved
      LDA #1
      STA temp

  .no_key_after_vx

      ; If we just released movement keys while grounded, redraw to idle.
      LDA last_move_held
      BEQ no_key_no_redraw
      LDA char_grounded
      BEQ no_key_no_redraw
      LDA #1
      STA temp
 .no_key_no_redraw


     ; Keep facing, but sync last_anim_dir.
      LDA anim_dir
      STA last_anim_dir

     JMP return_redraw


 .key_left
      LDA #0
      STA anim_dir
      LDA #&FF
      STA char_vx
      JMP key_held
 
 .key_right
      LDA #1
      STA anim_dir
      LDA #1
      STA char_vx
 
 .key_held
      ; Mark that we are trying to move (used for idle pose selection).
      LDA #1
      STA move_held

      ; If direction changed, force a redraw so we flip immediately.
      LDA anim_dir

     CMP last_anim_dir
     BEQ move_tick
     STA last_anim_dir
     LDA #1
     STA temp
 
 .move_tick
     LDA move_cooldown
     BEQ do_move
     DEC move_cooldown
     JMP return_redraw
  .do_move
      ; Walk speed (1px per frame).
      LDA #0
      STA move_cooldown

      LDA anim_dir
      BEQ do_move_left
      JSR step_right_pixel
      BCS did_move
      BCC return_redraw
  .do_move_left
      JSR step_left_pixel
      BCS did_move
      BCC return_redraw
 .did_move
      ; We moved: redraw, and advance animation every 4 pixels.
      LDA #1
      STA temp
 
      INC anim_cooldown
      LDA anim_cooldown
      CMP #4
      BNE return_redraw
      LDA #0
      STA anim_cooldown
      JSR step_anim

 .return_redraw
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

    ; Centerline walls, nose-based:
    ; Allow a little more overlap on the right so collision matches Chell's
    ; visible "nose" rather than the full 16px bounding box.
    ;
    ; Instead of testing just outside the right edge (x+16), test further
    ; inside the sprite.
    CLC
    ADC #10              ; test point 6px inside right edge
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
    BEQ apply_gravity_only
    BMI apply_move_up

.apply_move_down
    ; Pace falling so it doesn't "teleport" by whole stripes every frame.
    ; Cap to at most one 8px stripe step per frame.
    LDA fall_cooldown
    BEQ do_fall_step
    DEC fall_cooldown
    JMP apply_gravity_only

 .do_fall_step
    LDA #(FALL_STEP_PERIOD-1)
    STA fall_cooldown

    JSR step_down_8
    BCC hit_ground
    LDA #1
    STA temp
    JMP apply_gravity_only

.apply_move_up
    ; Move upward stripe-by-stripe, but slower than falling.
    ; This avoids "teleport" jumps and keeps vertical speed reasonable.
    LDA rise_cooldown
    BEQ do_rise_step
    DEC rise_cooldown
    JMP apply_gravity_only

.do_rise_step
    LDA #(RISE_STEP_PERIOD-1)
    STA rise_cooldown

    JSR step_up_8
    BCC hit_ceiling
    LDA #1
    STA temp
    JMP apply_gravity_only

.hit_ground
    ; Collided: stop and mark grounded.
    LDA #0
    STA char_vy
    STA gravity_cooldown
    STA fall_cooldown
    LDA #1
    STA char_grounded
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
