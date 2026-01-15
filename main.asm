INCLUDE "oscalls.asm"

; Zero page variables for speed
; Keep tilemap_ptr at &79/&7A (see render.asm)
ORG &70
.temp               SKIP 1    ; Temporary storage
.screen_ptr         SKIP 2    ; Current screen memory location
.sprite_ptr         SKIP 2    ; Pointer to current sprite data
.temp_y             SKIP 1    ; Temporary Y storage
.row_counter        SKIP 1    ; Row counter for loops
.col_counter        SKIP 1    ; Column counter for loops
.current_room       SKIP 1    ; Current room number (0=room1, 1=room2)
.tilemap_ptr        SKIP 2    ; Pointer to current room's tilemap data
.portalmap_ptr      SKIP 2    ; Pointer to current room's portalable tile layer
.mask_ptr           SKIP 2    ; Pointer to current mask data
.char_tile_pos      SKIP 1    ; Character cell position (cell_y*16 + cell_x)
.char_pixel_offset  SKIP 1    ; Subpixel offset (0..3)
.char_byte_offset   SKIP 1    ; Byte offset within cell (0 or 8)
.char_y_offset      SKIP 1    ; Vertical offset within cell row (0 or 8)
.char_vy            SKIP 1    ; Signed vy in 8px steps
.char_grounded      SKIP 1    ; 0/1: standing on solid
.gravity_cooldown   SKIP 1    ; Frames until next gravity tick
.rise_cooldown      SKIP 1    ; Frames until next upward step
.keys_held          SKIP 1    ; Bitfield: held keys this frame
.keys_pressed       SKIP 1    ; Bitfield: edge-trigger keys (held & ~prev)
.keys_prev          SKIP 1    ; Previous frame's keys_held
.aim_held           SKIP 1    ; 0=none, 1=up, 2=down
.dirty_flag         SKIP 1    ; 0/1: needs redraw this frame
.temp_sprite_ptr    SKIP 2    ; Temp sprite pointer for striped blit

.temp_mask_ptr      SKIP 2    ; Temp mask pointer for striped blit
.chell_bank         SKIP 1    ; ROMSEL value for Chell SWRAM bank
.saved_romsel       SKIP 1    ; Saved ROMSEL around OS calls
.chelldata_fh      SKIP 1    ; File handle for CHDATA
 .anim_frame              SKIP 1    ; Animation frame (0..3)
 .anim_dir                SKIP 1    ; Direction (0=left,1=right)
 .last_anim_dir           SKIP 1    ; Previous direction for redraw
 .move_held               SKIP 1    ; 0/1: left/right held this frame
 .last_move_held          SKIP 1    ; Previous move_held (for pose redraw)
 .move_cooldown           SKIP 1    ; Frames until next move
 .anim_cooldown           SKIP 1    ; Movement counter for anim
 
 .save_under_count         SKIP 1    ; Number of active save-under slots (0..4)


.save_under_screen_low    SKIP 4    ; Saved screen_ptr low per slot
.save_under_screen_high   SKIP 4    ; Saved screen_ptr high per slot

.cube_tile_pos       SKIP 1    ; Cube cell position (cell_y*16 + cell_x)
.cube_byte_offset    SKIP 1    ; Cube byte offset within cell (0/8)
.char_sprite_index  SKIP 1    ; Stable sprite index

ORG &1900

CRTC_ADDR = &FE00
CRTC_DATA = &FE01
ROMSEL    = &FE30          ; Master paged ROM/SWRAM bank select

CHELL_SWRAM_BANK_DEFAULT = 4
CHELLDATA_BUF         = &7B00  ; Temp buffer in screen scratch

GRAVITY_ACCEL              = 1      ; vy += 1 per gravity tick (8px steps)
GRAVITY_UP_PERIOD           = 3      ; gravity tick period while rising
GRAVITY_DOWN_PERIOD         = 1      ; gravity tick period while falling
TERMINAL_VELOCITY_DOWN      = 4      ; max falling speed (8px steps)
JUMP_VELOCITY               = &FE    ; -2 (controls hang time)
RISE_STEP_PERIOD            = 2      ; move up 1 stripe every N frames

CHELL_RUN_LEFT_BASE         = 12
CHELL_IDLE_RIGHT_BASE       = 24
CHELL_IDLE_LEFT_BASE        = 28
CHELL_JUMP_RIGHT_BASE       = 32
CHELL_JUMP_LEFT_BASE        = 36

.start
    ; PROGRAM sets MODE 5, but reassert it here for safety.
    LDA #22
    JSR OSWRCH
    LDA #5
    JSR OSWRCH

    ; Disable the blinking text cursor (it writes into screen RAM).
    JSR disable_cursor

    ; Remap logical colours to physical palette:
    ; 0=black, 1=red, 2=cyan, 3=yellow
    JSR set_palette


    ; Apply the game's narrower visible width (32 chars) and re-centre.
    ; CRTC R1 (horizontal displayed) = 32
    LDA #1
    STA CRTC_ADDR
    LDA #32
    STA CRTC_DATA

    ; CRTC R2 (horizontal sync position) = 45
    LDA #2
    STA CRTC_ADDR
    LDA #45
    STA CRTC_DATA

    ; Minimal demo harness.

    ; Select room 0 so tilemap_ptr is valid (not used yet).
    LDA #0
    STA current_room
    JSR set_room_tilemap
    JSR set_room_portalmap

    ; Load Chell sprite+mask data into sideways RAM.
    ; (Do this before enabling shadow screen so OS file I/O stays simple.)
    JSR load_chell_sprites

    ; Filing-system calls may clobber ZP, so restore our room pointers.
    JSR set_room_tilemap
    JSR set_room_portalmap

    ; Enable shadow screen (Master).
    ; We still use MODE 5 layout at &5800, but in shadow RAM.
    JSR enable_shadow_screen

    ; Place Chell at cell (4,4): cell_y*16 + cell_x = 4*16 + 4 = 68
    LDA #68
    STA char_tile_pos

    ; Init state.
    LDA #0
    STA char_pixel_offset
    STA char_byte_offset
    STA char_y_offset
    STA char_vy
    STA char_grounded
    STA gravity_cooldown
    STA rise_cooldown
    STA keys_held
    STA keys_pressed
    STA keys_prev
    STA anim_frame
    STA move_held
    STA last_move_held
    STA move_cooldown
    STA anim_cooldown
    STA save_under_count

    ; Default: face right.
    LDA #1
    STA anim_dir
    STA last_anim_dir

    ; Render background once.
    JSR render_tilemap

    ; Build collision/material plane from the tilemap.
    JSR build_material_planes_from_tilemap

    ; Draw the initial sprite once (allocates save-under slot).
    JSR update_screen_ptr_from_char
    JSR save_playfield_rect
    JSR draw_character_current
 
 .main_loop
      ; Pace the loop (reduces tearing/flicker).
      JSR wait_vsync

      ; Render previous frame immediately after VSYNC.
      LDA dirty_flag
      BEQ main_skip_render
      JSR render_chell
.main_skip_render

      ; Sample input once per frame; gameplay consumes only key bits.
      JSR sample_keys

 
      ; Update state for next frame.
      JSR update_chell
      JMP main_loop


; --- Update pipeline ---
; Updates Chell state from input and physics.
; Sets dirty_flag if redraw is needed.
.update_chell
     LDA #0
     STA dirty_flag

     ; Input -> update horizontal movement/anim.
     JSR poll_move_keys
     BCC update_skip_dirty_move
     LDA #1
     STA dirty_flag
.update_skip_dirty_move

     ; Physics -> update vertical position.
     JSR apply_gravity
     BCC update_done
     LDA #1
     STA dirty_flag
.update_done
     RTS

; --- Render pipeline ---
; Redraws Chell using save-under.
.render_chell
     JSR restore_playfield_rect
     JSR update_screen_ptr_from_char
     JSR save_playfield_rect
     JSR draw_character_current
     RTS



.run_frame_seq
    EQUB 0,1,0,2
 
; Draw current body + overlay at screen_ptr.
.draw_character_current
    ; Keep ROMSEL stable during blit (B2/MOS IRQs may page ROMs).
    SEI
    LDA ROMSEL
    STA saved_romsel

    ; Ensure Chell SWRAM bank is visible for reads.
    LDA chell_bank
    STA ROMSEL

     ; Airborne: draw jump pose only.
     ; (Aim is held-only, and currently only affects overlay.)
     LDA char_grounded
     BNE draw_grounded


    ; jump_base = CHELL_JUMP_RIGHT_BASE or CHELL_JUMP_LEFT_BASE
    LDA anim_dir
    BNE jump_right
    LDA #CHELL_JUMP_LEFT_BASE
    BNE jump_base_ok
.jump_right
    LDA #CHELL_JUMP_RIGHT_BASE
.jump_base_ok
    CLC
    ADC char_pixel_offset
    STA char_sprite_index

     LDA char_sprite_index
     JSR render_character_sprite

     ; Jump: always draw gun forward overlay (no aim cycling here).
     LDA anim_dir
     BNE jump_overlay_right
     LDA #CHELL_RUN_LEFT_BASE
     BNE jump_overlay_base_ok
.jump_overlay_right
     LDA #0
.jump_overlay_base_ok
     CLC
     ADC char_pixel_offset
     JSR render_overlay_sprite

     JMP draw_done

.draw_grounded
    ; If no movement key held, use idle pose.
    LDA move_held
    BNE draw_running

    LDA anim_dir
    BNE idle_right
    LDA #CHELL_IDLE_LEFT_BASE
    BNE idle_base_ok
.idle_right
    LDA #CHELL_IDLE_RIGHT_BASE
.idle_base_ok
    CLC
    ADC char_pixel_offset
    STA char_sprite_index

    LDA char_sprite_index
    JSR render_character_sprite

     ; Idle: always draw gun forward overlay (no aim cycling here).
     LDA anim_dir
     BNE idle_overlay_right
     LDA #CHELL_RUN_LEFT_BASE
     BNE idle_overlay_base_ok
.idle_overlay_right
     LDA #0
.idle_overlay_base_ok
     CLC
     ADC char_pixel_offset
     JSR render_overlay_sprite


    JMP draw_done

  .draw_running
     ; Running: animate body + aim overlay.

 .draw_running_go
     ; Index = run_frame*4 + subpixel_offset
     ; run_frame cycles 0,1,0,2 (i.e. 1,2,1,3)
     ; Facing selects between right-facing (0..11) and left-facing (12..23).
     LDX anim_frame
     LDA run_frame_seq,X
     ASL A
     ASL A
     STA char_sprite_index


    ; If facing left, add run-left base.
    LDA anim_dir
    BNE facing_right
    LDA char_sprite_index
    CLC
    ADC #CHELL_RUN_LEFT_BASE
    STA char_sprite_index
 .facing_right
 
     LDA char_sprite_index
     CLC
     ADC char_pixel_offset
     STA char_sprite_index
 
     LDA char_sprite_index
     JSR render_character_sprite
 
     ; Overlay index must be computed independently of body sprite index.
     ; Overlay table is 24 entries:
     ;   per direction: 3 aim frames (forward/down/up) x 4 subpixel = 12
     ;   right: forward/down/up x0..x3 = 0..11
     ;   left:  forward/down/up x0..x3 = 12..23
     ; Overlay behaviour:
     ; - aim_held=0 (forward): cycle overlay with run animation.
     ; - aim_held=1 (up) or 2 (down): fixed overlay frame.
     ; Overlay table per direction: 3 aim frames (forward/down/up) x 4 subpixel.

     ; First compute a base within the direction: (aim_frame*4).
     ; aim_frame mapping: forward=0, down=1, up=2
     LDA aim_held
     BEQ run_overlay_aimframe_ok
     CMP #2
     BNE run_overlay_aim_up
     LDA #1
     BNE run_overlay_aimframe_ok
.run_overlay_aim_up
     LDA #2
.run_overlay_aimframe_ok
     ASL A
     ASL A
     STA temp

     ; If not aiming, add run-phase cycling (0/4/8).
     LDA aim_held
     BNE run_overlay_have_index

     LDX anim_frame
     LDA run_frame_seq,X
     ASL A
     ASL A
     CLC
     ADC temp
     STA temp

.run_overlay_have_index

     ; Facing left adds 12.
     LDA anim_dir
     BNE overlay_run_right
     LDA temp
     CLC
     ADC #CHELL_RUN_LEFT_BASE
     STA temp
.overlay_run_right

     LDA temp
     CLC
     ADC char_pixel_offset
     JSR render_overlay_sprite
 

  .draw_done
      ; Restore previous ROM selection and re-enable IRQs.
      LDA saved_romsel
      STA ROMSEL
      CLI
      RTS

 
  
 ; Poll Z/X for left/right movement (single-pixel).

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

 
; --- Input sampling ---
;
; keys_held bits (this repo conventions):
;   bit0: left  (Z or cursor left)
;   bit1: right (X or cursor right)
;   bit2: jump  (RETURN)
;
; Sample keyboard once this frame and build:
;   keys_held    = held bits
;   keys_pressed = newly pressed this frame (edge)
;   keys_prev    = last frame's keys_held
.sample_keys
    ; Start with no bits set.
    LDA #0
    STA keys_held

    ; Jump (RETURN)
    LDX #&B6            ; INKEY(-74) = RETURN
    JSR is_key_pressed
    BCC sample_no_jump
    LDA keys_held
    ORA #4
    STA keys_held
.sample_no_jump

    ; Left (cursor left or Z)
    LDX #&E6            ; INKEY(-26) = Left
    JSR is_key_pressed
    BCS sample_set_left
    LDX #&9E            ; INKEY(-98) = 'Z'
    JSR is_key_pressed
    BCC sample_no_left
.sample_set_left
    LDA keys_held
    ORA #1
    STA keys_held
.sample_no_left

    ; Right (cursor right or X)
    LDX #&86            ; INKEY(-122) = Right
    JSR is_key_pressed
    BCS sample_set_right
    LDX #&BD            ; INKEY(-67) = 'X'
    JSR is_key_pressed
    BCC sample_no_right
.sample_set_right
    LDA keys_held
    ORA #2
    STA keys_held
.sample_no_right

    ; keys_pressed = keys_held & ~keys_prev

    LDA keys_prev
    EOR #&FF
    AND keys_held
    STA keys_pressed

    ; Update previous snapshot for next frame.
    LDA keys_held
    STA keys_prev

    ; --- Aim sampling ---
    ; aim_held: 0=none, 1=up, 2=down
    LDA #0
    STA aim_held

    ; Prefer up if both held.
    ; ':' = INKEY(-73)
    LDX #&B7
    JSR is_key_pressed
    BCS sample_set_aim_up

    ; cursor up = 138 (see BBC User Guide sample)
    ; => INKEY(-118)
    LDX #&8A
    JSR is_key_pressed
    BCC sample_check_aim_down

.sample_set_aim_up
    LDA #1
    STA aim_held
    JMP sample_aim_done

.sample_check_aim_down
    ; '/' = INKEY(-105)
    LDX #&97
    JSR is_key_pressed
    BCS sample_set_aim_down

    ; cursor down = 139 (see BBC User Guide sample)
    ; => INKEY(-117)
    LDX #&8B
    JSR is_key_pressed
    BCC sample_aim_done

.sample_set_aim_down
    LDA #2
    STA aim_held

.sample_aim_done


; Input: X = negative INKEY number (as 8-bit value)
; Output: C=1 if pressed
.is_key_pressed
    LDY #&FF
    LDA #129
    JSR OSBYTE
    CPX #&FF
    BNE key_not_pressed
    SEC
    RTS
.key_not_pressed
    CLC
    RTS
 
 .key_left
     LDA #0
     STA anim_dir
     JMP key_held
 
 .key_right
     LDA #1
     STA anim_dir
 
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
     BCC return_redraw
     JMP did_move
 .do_move_left
     JSR step_left_pixel
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
    SEC
    SBC #1
    TAX

    JSR calc_char_y
    STA temp_y

    LDY temp_y
    JSR is_solid
    BCS collide_left

    LDY temp_y
    TYA
    CLC
    ADC #31
    TAY
    JSR is_solid
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
    CLC
    ADC #16              ; test new right edge (x+16)
    BCS collide_right    ; overflow => beyond 255 (treat as solid)
    CMP #128
    BCS collide_right
    TAX

    JSR calc_char_y
    STA temp_y

    LDY temp_y
    JSR is_solid
    BCS collide_right

    LDY temp_y
    TYA
    CLC
    ADC #31
    TAY
    JSR is_solid
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
    LDX char_vy
.move_down_loop
    JSR step_down_8
    BCC hit_ground
    LDA #1
    STA temp
    DEX
    BNE move_down_loop
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
; Tests a pixel just below the feet at left and right edges.
.is_char_grounded
    ; x = left edge
    JSR calc_char_x
    STA temp

    ; y = top
    JSR calc_char_y
    CLC
    ADC #32
    BCS grounded_true
    TAY

    ; left foot
    LDX temp
    JSR is_solid
    BCS grounded_true

    ; right foot (x+15)
    LDA temp
    CLC
    ADC #15
    CMP #128
    BCS grounded_true
    TAX
    JSR is_solid
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
    ; x = left edge
    JSR calc_char_x
    STA temp

    ; y_test = (y + 8) + 31
    JSR calc_char_y
    CLC
    ADC #39
    BCS collide_down
    TAY

    ; left bottom
    LDX temp
    JSR is_solid
    BCS collide_down

    ; right bottom
    LDA temp
    CLC
    ADC #15
    CMP #128
    BCS collide_down
    TAX
    JSR is_solid
    BCS collide_down

    CLC
    RTS
.collide_down
    SEC
    RTS

; Return C=1 if moving up 8px would collide.
.will_collide_up_8
    ; x = left edge
    JSR calc_char_x
    STA temp

    ; y_test = (y - 8)
    JSR calc_char_y
    CMP #8
    BCC collide_up
    SEC
    SBC #8
    TAY

    ; left top
    LDX temp
    JSR is_solid
    BCS collide_up

    ; right top
    LDA temp
    CLC
    ADC #15
    CMP #128
    BCS collide_up
    TAX
    JSR is_solid
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
 
; Disable the text cursor by redefining it to all zeros.
; This avoids the OS blinking cursor touching screen RAM.
.disable_cursor

    LDX #0
.cursor_loop
    LDA cursor_vdu,X
    JSR OSWRCH
    INX
    CPX #10
    BNE cursor_loop
    RTS

.cursor_vdu
    EQUB 23,1,0,0,0,0,0,0,0,0

; Set MODE 5 palette mapping.
; Uses VDU 19,logical,physical,0,0,0.
.set_palette
    LDX #0
.palette_loop
    LDA palette_vdu,X
    JSR OSWRCH
    INX
    CPX #24
    BNE palette_loop
    RTS

.palette_vdu
    ; logical 0 -> physical 0 (black)
    EQUB 19,0,0,0,0,0
    ; logical 1 -> physical 1 (red)
    EQUB 19,1,1,0,0,0
    ; logical 2 -> physical 6 (cyan)
    EQUB 19,2,6,0,0,0
    ; logical 3 -> physical 3 (yellow)
    EQUB 19,3,3,0,0,0

; Wait for a single keypress (B2-friendly, debounced).
; Uses OSBYTE 129 (INKEY-256): Y=ASCII, N set if no key.
; Returns: A = ASCII of key pressed.
.wait_key
    LDX #&00
    LDY #&00

    ; Wait for a key to be down.
.wait_key_down
    LDA #129
    JSR OSBYTE
    TYA
    BMI wait_key_down

    ; Latch key value.
    TYA
    PHA

    ; Wait for key to be released (no key down).
.wait_key_up
    LDA #129
    JSR OSBYTE
    TYA
    BPL wait_key_up

    PLA
    RTS

; Enable Master shadow screen.
; Master MOS supports selecting screen memory in shadow RAM.
; OSBYTE 114 is used by the MOS for shadow screen selection.
.enable_shadow_screen
    LDA #114
    LDX #1
    LDY #0
    JSR OSBYTE
    RTS

; Load Chell sprite+mask data into sideways RAM.
;
; We cannot safely `*LOAD` straight into `&8000` because filing system ROM code
; also lives in the `&8000..&BFFF` paged ROM window.
;
; Also, we cannot `*LOAD` into `&3000` anymore because the main program has grown
; past that address.
;
; Instead we stream CHDATA in 256-byte chunks into `CHELLDATA_BUF` and copy each
; chunk into the target SWRAM bank.
.load_chell_sprites
    ; Keep the OS/language ROM visible across filing-system calls.
    LDA ROMSEL
    STA saved_romsel

    ; Choose which ROMSEL value actually maps writable SWRAM in this environment.
    ; (Real Master: bank number alone; B2 may require bit 7.)
    JSR select_chell_romsel
    BCC chell_bank_ok

    LDX #<msg_no_swr
    LDY #>msg_no_swr
    JSR print_string_xy
.no_swr_hang
    JMP no_swr_hang

.chell_bank_ok
    ; Keep filing system ROM visible for OSFIND/OSGBPB.
    LDA saved_romsel
    STA ROMSEL

    ; Open CHDATA for input.
    LDA #&40
    LDX #<fname_chdata
    LDY #>fname_chdata
    JSR OSFIND
    BNE chdata_open_ok
    JMP chdata_open_fail
.chdata_open_ok
    STA chelldata_fh

    ; dst := &8000 (in SWRAM bank)
    LDA #&00
    STA temp_mask_ptr
    LDA #&80
    STA temp_mask_ptr+1

    ; Use OSGBPB to read 256 bytes per page.
    LDA #&40
    STA row_counter
.chdata_page_loop
    ; Build OSGBPB control block.
    LDA chelldata_fh
    STA gpb_block+0

    LDA #<CHELLDATA_BUF
    STA gpb_block+1
    LDA #>CHELLDATA_BUF
    STA gpb_block+2
    LDA #0
    STA gpb_block+3
    STA gpb_block+4

    ; 256 bytes
    LDA #0
    STA gpb_block+5
    LDA #1
    STA gpb_block+6
    LDA #0
    STA gpb_block+7
    STA gpb_block+8

    ; seq pointer (ignored for A=4, but keep it 0)
    LDA #0
    STA gpb_block+9
    STA gpb_block+10
    STA gpb_block+11
    STA gpb_block+12

    ; Read bytes from media, ignoring new sequential pointer.
    LDA #4
    LDX #<gpb_block
    LDY #>gpb_block
    JSR OSGBPB
    BCS chdata_read_fail

    ; Copy into SWRAM page with ROMSEL held stable.
    SEI
    LDA chell_bank
    STA ROMSEL

    LDA #<CHELLDATA_BUF
    STA temp_sprite_ptr
    LDA #>CHELLDATA_BUF
    STA temp_sprite_ptr+1

    LDY #0
.chdata_copy_loop
    LDA (temp_sprite_ptr),Y
    STA (temp_mask_ptr),Y
    INY
    BNE chdata_copy_loop

    ; Sanity check against the page we just copied (checks &8000 writeability too).
    JSR sanity_check_chell_swrambank
    BCS chdata_copy_fail

    ; Restore ROMSEL for filing system.
    LDA saved_romsel
    STA ROMSEL
    CLI

    INC temp_mask_ptr+1
    DEC row_counter
    BNE chdata_page_loop

    ; Close file.
    LDA #0
    LDY chelldata_fh
    JSR OSFIND

    ; Leave normal ROM selected.
    LDA saved_romsel
    STA ROMSEL
    RTS

.chdata_open_fail
    LDX #<msg_chdata_open_fail
    LDY #>msg_chdata_open_fail
    JSR print_string_xy
.chdata_hang
    JMP chdata_hang

.chdata_read_fail
    ; Restore ROMSEL before printing.
    LDA saved_romsel
    STA ROMSEL
    CLI
    LDX #<msg_chdata_read_fail
    LDY #>msg_chdata_read_fail
    JSR print_string_xy
    JMP chdata_hang

.chdata_copy_fail
    ; Restore ROMSEL before printing.
    LDA saved_romsel
    STA ROMSEL
    CLI
    LDX #<msg_swr_copy_fail
    LDY #>msg_swr_copy_fail
    JSR print_string_xy
    JMP chdata_hang

.fname_chdata
    EQUS "CHDATA",13

.gpb_block
    SKIP 13


; Select a ROMSEL value for Chell SWRAM writes.
; Tries bank 4, then bank 4|&80 (B2 quirk).
;
; Output:
; - `chell_bank` set
; - ROMSEL set to `chell_bank`
; Returns: C=0 if ok, C=1 if no mapping worked.
.select_chell_romsel
    LDA #CHELL_SWRAM_BANK_DEFAULT
    JSR romsel_writable
    BCC romsel_ok

    LDA #CHELL_SWRAM_BANK_DEFAULT
    ORA #&80
    JSR romsel_writable
    BCS romsel_fail

.romsel_ok
    STA chell_bank
    STA ROMSEL
    CLC
    RTS

.romsel_fail
    SEC
    RTS

; Test whether current A (ROMSEL value) is writable at &8000.
; Returns: C=0 writable, C=1 not writable. Preserves A.
.romsel_writable
    PHA
    STA ROMSEL

    LDA &8000
    STA temp

    LDA #&A5
    STA &8000
    CMP &8000
    BNE romsel_not_writable

    LDA #&5A
    STA &8000
    CMP &8000
    BNE romsel_not_writable

    ; Restore original byte.
    LDA temp
    STA &8000

    PLA
    CLC
    RTS

.romsel_not_writable
    ; Best-effort restore.
    LDA temp
    STA &8000
    PLA
    SEC
    RTS

; Sanity check for the Chell SWRAM bank in B2.
; Preconditions:
; - `chell_bank` has been selected into ROMSEL.
; - `temp_sprite_ptr` points at the source page buffer.
; - `temp_mask_ptr` points at the destination page in SWRAM.
;
; Returns: C=0 if ok, C=1 if failed.
.sanity_check_chell_swrambank
    ; Confirm writes stick at &8000 (restore original byte afterwards).
    LDA &8000
    STA temp

    LDA #&A5
    STA &8000
    CMP &8000
    BNE sanity_fail

    LDA #&5A
    STA &8000
    CMP &8000
    BNE sanity_fail

    ; Restore original byte.
    LDA temp
    STA &8000

    ; Confirm the first 16 bytes match what we just copied.
    LDY #0
.sanity_cmp_loop
    LDA (temp_sprite_ptr),Y
    CMP (temp_mask_ptr),Y
    BNE sanity_fail
    INY
    CPY #16
    BNE sanity_cmp_loop

    CLC
    RTS

.sanity_fail
    ; Best-effort restore of first byte.
    LDA temp
    STA &8000
    SEC
    RTS

; Print NUL-terminated string at XY using OSWRCH.
.print_string_xy
    STX temp_sprite_ptr
    STY temp_sprite_ptr+1

.print_loop
    LDY #0
    LDA (temp_sprite_ptr),Y
    BEQ print_done
    JSR OSWRCH

    INC temp_sprite_ptr
    BNE print_loop
    INC temp_sprite_ptr+1
    BNE print_loop

.print_done
    RTS

.msg_no_swr
    EQUS "NO SWRAM",13,0

.msg_chdata_open_fail
    EQUS "CHDATA OPEN FAIL",13,0

.msg_chdata_read_fail
    EQUS "CHDATA READ FAIL",13,0

.msg_swr_copy_fail
    EQUS "SWRAM COPY FAIL",13,0

; Wait for vertical sync (VBlank).
; Uses OSBYTE 19 (&13): "Wait for vertical sync".
.wait_vsync
    LDA #19
    LDX #0
    LDY #0
    JSR OSBYTE
    RTS

; Simple delay to make the demo visible.
.short_delay
    LDY #&30
.delay_outer
    LDX #&FF
.delay_inner
    DEX
    BNE delay_inner

    DEY
    BNE delay_outer
    RTS

; Update screen_ptr from char_tile_pos.
.update_screen_ptr_from_char
    ; tile_y = char_tile_pos >> 4
    LDA char_tile_pos
    LSR A
    LSR A
    LSR A
    LSR A
    STA temp_y

    ; Look up screen base for this tile row
    ASL A
    TAY
    LDA tile_row_screen_table,Y
    STA screen_ptr
    LDA tile_row_screen_table+1,Y
    STA screen_ptr+1

    ; Optional +8 scanline offset (1 stripe) within the 16px cell row.
    LDA char_y_offset
    BEQ char_y_offset_done
    INC screen_ptr+1
.char_y_offset_done

    ; tile_x = char_tile_pos & 15
    LDA char_tile_pos
    AND #15
    TAY

    ; Add tile_x * 16
    LDA times16_table,Y
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC add_byte_offset
    INC screen_ptr+1

.add_byte_offset
    LDA char_byte_offset
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC update_screen_done
    INC screen_ptr+1
.update_screen_done
    RTS

; Update screen_ptr from cube_tile_pos.
.update_screen_ptr_from_cube
    ; tile_y = cube_tile_pos >> 4
    LDA cube_tile_pos
    LSR A
    LSR A
    LSR A
    LSR A
    STA temp_y

    ; Look up screen base for this tile row
    ASL A
    TAY
    LDA tile_row_screen_table,Y
    STA screen_ptr
    LDA tile_row_screen_table+1,Y
    STA screen_ptr+1

    ; tile_x = cube_tile_pos & 15
    LDA cube_tile_pos
    AND #15
    TAY

    ; Add tile_x * 16
    LDA times16_table,Y
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC cube_add_byte_offset
    INC screen_ptr+1

.cube_add_byte_offset
    LDA cube_byte_offset
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC cube_screen_done
    INC screen_ptr+1
.cube_screen_done
    RTS

; Update char_tile_pos based on anim_dir.
; Bounces between tile_x 0..14 (sprite is 2 tiles wide).
.step_char_tile
    LDA char_tile_pos
    AND #15
    STA temp

    LDA anim_dir
    BEQ step_left

.step_right
    LDA temp
    CMP #14
    BNE step_right_inc
    LDA #0
    STA anim_dir
    RTS
.step_right_inc
    INC char_tile_pos
    RTS

.step_left
    LDA temp
    BEQ step_left_turn
    DEC char_tile_pos
    RTS
.step_left_turn
    LDA #1
    STA anim_dir
    RTS

; Set tilemap_ptr based on current_room variable.
; Uses room_pointers table to get correct room data.
.set_room_tilemap
    LDA current_room
    ASL A                   ; ×2 for 16-bit pointer
    TAX

    LDA room_pointers,X
    STA tilemap_ptr
    LDA room_pointers+1,X
    STA tilemap_ptr+1

    RTS

; Set portalmap_ptr based on current_room variable.
; Uses portal_room_pointers table to get correct room data.
.set_room_portalmap
    LDA current_room
    ASL A                   ; ×2 for 16-bit pointer
    TAX

    LDA portal_room_pointers,X
    STA portalmap_ptr
    LDA portal_room_pointers+1,X
    STA portalmap_ptr+1

    RTS

; Get cell value from cellmap at specified cell position.
; Input: Y = cell position (cell_y * 16 + cell_x)
; Output: A = cell value
.get_tilemap_tile
    LDA (tilemap_ptr),Y
    RTS

INCLUDE "sprites.asm"
INCLUDE "masks.asm"
INCLUDE "tilemap.asm"
INCLUDE "render.asm"
INCLUDE "lookup_tables.asm"

.end

SAVE "PORTHLE", start, end
PUTBASIC "program.bas", "PROGRAM"

; Chell sprite+mask data file for sideways RAM.
; This is loaded at runtime into a sideways RAM bank mapped at &8000..&BFFF.
ORG &8000
.chelldata_start
INCLUDE "sprites/generated_chell_sprites.asm"
INCLUDE "sprites/generated_chell_masks.asm"

; Pad to full 16KB SWRAM bank.
ORG &C000
.chelldata_end
SAVE "CHDATA", chelldata_start, chelldata_end
