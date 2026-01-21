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
.fall_cooldown      SKIP 1    ; Frames until next downward step
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

; Precomputed render decisions for Chell (computed in update; used in render).
.chell_new_ptr       SKIP 2    ; next screen_ptr for Chell
.chell_body_index    SKIP 1    ; sprite index into character_sprite_table
.chell_overlay_index SKIP 1    ; sprite index into overlay_sprite_table
.last_aim_held       SKIP 1    ; previous aim_held (0/1/2)

.reticle_cell_x      SKIP 1    ; 0..7 (portal grid X)
.reticle_cell_y      SKIP 1    ; 0..15 (portal grid Y)
.reticle_state       SKIP 1    ; 0=blocked, 1=portalable
.reticle_active      SKIP 1    ; 0/1: draw reticle
.reticle_prev_active SKIP 1    ; previous frame reticle_active
.reticle_move_cd     SKIP 1    ; reticle move repeat cooldown

.chell_dirty         SKIP 1    ; 0/1: Chell moved/changed last update
.reticle_dirty       SKIP 1    ; 0/1: reticle moved/changed last update

.chell_prev_ptr      SKIP 2    ; previous Chell screen_ptr
 .reticle_prev_ptr    SKIP 2    ; previous reticle screen_ptr
 .chell_has_under     SKIP 1    ; 0/1: have valid Chell save-under
 .reticle_has_under   SKIP 1    ; 0/1: have valid reticle save-under
 
 ; --- Render list (PoP-style pipeline) ---
 ; Stored in screen scratch (not ZP) so MOS calls can't clobber it.
 ; Layout is a fixed 2-entry list.
 
 ORG &1900


CRTC_ADDR = &FE00
CRTC_DATA = &FE01
ROMSEL    = &FE30          ; Master paged ROM/SWRAM bank select

CHELL_SWRAM_BANK_DEFAULT = 4
CHELLDATA_BUF         = &7B00  ; Temp buffer in screen scratch

; Render list storage lives in screen scratch so it survives MOS calls.
RENDER_LIST_BASE      = &78C0
RENDER_COUNT          = RENDER_LIST_BASE + 0
RENDER_IDS            = RENDER_LIST_BASE + 1   ; 2 bytes
RENDER_FLAGS          = RENDER_LIST_BASE + 3   ; 2 bytes
RENDER_NEW_PTR_LO     = RENDER_LIST_BASE + 5   ; 2 bytes
RENDER_NEW_PTR_HI     = RENDER_LIST_BASE + 7   ; 2 bytes

GRAVITY_ACCEL              = 1      ; vy += 1 per gravity tick (8px steps)
GRAVITY_UP_PERIOD           = 3      ; gravity tick period while rising
GRAVITY_DOWN_PERIOD         = 1      ; gravity tick period while falling
TERMINAL_VELOCITY_DOWN      = 1      ; max falling speed (8px steps)
JUMP_VELOCITY               = &FE    ; -2 (controls hang time)
RISE_STEP_PERIOD            = 2      ; move up 1 stripe every N frames
FALL_STEP_PERIOD            = 2      ; move down 1 stripe every N frames

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
    STA fall_cooldown
    STA keys_held
    STA keys_pressed
    STA keys_prev
    STA anim_frame
    STA move_held
    STA last_move_held
    STA move_cooldown
    STA anim_cooldown
    ; save-under pool removed; leave count unused
    STA save_under_count

    STA chell_body_index
    STA chell_overlay_index
    STA last_aim_held

    ; Reticle starts inactive.
    LDA #0
    STA reticle_active
    STA reticle_prev_active
    STA reticle_move_cd
    STA reticle_cell_x
    STA reticle_cell_y
    STA reticle_state

    STA chell_dirty
    STA reticle_dirty
    STA chell_prev_ptr
    STA chell_prev_ptr+1
    STA reticle_prev_ptr
    STA reticle_prev_ptr+1
    STA chell_has_under
    STA reticle_has_under

    ; Default: face right.
    LDA #1
    STA anim_dir
    STA last_anim_dir

    ; Render background once.
    JSR render_tilemap

    ; Build collision/material plane from the tilemap.
    JSR build_material_planes_from_tilemap

    ; Draw the initial sprite once (allocates Chell save-under).
    ; Precompute render decisions, then draw from them.
    JSR compute_chell_render_state
    LDA chell_new_ptr
    STA screen_ptr
    LDA chell_new_ptr+1
    STA screen_ptr+1

    JSR save_chell_under
    JSR draw_character_current

    LDA screen_ptr
    STA chell_prev_ptr
    LDA screen_ptr+1
    STA chell_prev_ptr+1
    LDA #1
    STA chell_has_under

    ; Mark reticle as having no valid under yet.
    LDA #0
    STA reticle_has_under
 
  .main_loop
       ; Pace the loop (reduces tearing/flicker).
       JSR wait_vsync

       ; Render previous frame immediately after VSYNC.
       ; Incremental: redraw only what changed (Chell + reticle).
       LDA dirty_flag
       BEQ main_skip_render
       JSR render_frame_simple
 .main_skip_render

       ; Sample input once per frame; gameplay consumes only key bits.
       JSR sample_keys

        ; Update state for next frame.
        JSR update_chell
        JMP main_loop


 ; --- Render (incremental frame) ---
 ; Uses chell_dirty/reticle_dirty computed in the previous update.
 ; Reticle redraw condition includes chell_dirty because Chell can move under it.
 .render_frame_simple
       ; Handle reticle deactivation: restore last rect.
       LDA reticle_active
       BNE render_reticle_active
       LDA reticle_prev_active
       BEQ render_restore_maybe
       LDA reticle_has_under
       BEQ render_restore_maybe
       JSR restore_reticle_under
       LDA #0
       STA reticle_has_under
       JMP render_restore_maybe

 .render_reticle_active
       ; If reticle will be redrawn, restore it first (LIFO peel) so we don't
       ; resurrect old Chell pixels that were under the reticle.
       LDA reticle_dirty
       ORA chell_dirty
       BEQ render_restore_maybe
       LDA reticle_has_under
       BEQ render_restore_maybe
       JSR restore_reticle_under

 .render_restore_maybe
       ; Restore Chell under if it moved.
       LDA chell_dirty
       BEQ render_draw_maybe
       LDA chell_has_under
       BEQ render_draw_maybe
       JSR restore_chell_under

 .render_draw_maybe
       ; Draw Chell if dirty.
       LDA chell_dirty
       BEQ render_draw_reticle_maybe

       ; screen_ptr := precomputed new pointer
       LDA chell_new_ptr
       STA screen_ptr
       LDA chell_new_ptr+1
       STA screen_ptr+1
       JSR save_chell_under
       JSR draw_character_current

       ; Record new previous pointer.
       LDA screen_ptr
       STA chell_prev_ptr
       LDA screen_ptr+1
       STA chell_prev_ptr+1
       LDA #1
       STA chell_has_under

 .render_draw_reticle_maybe
       ; Draw reticle if active and needs redraw.
       LDA reticle_active
       BEQ render_frame_done
       LDA reticle_dirty
       ORA chell_dirty
       BEQ render_frame_done

       JSR update_screen_ptr_from_reticle
       JSR save_reticle_under
       JSR draw_reticle_current

       ; Record reticle screen_ptr for next restore.
       LDA screen_ptr
       STA reticle_prev_ptr
       LDA screen_ptr+1
       STA reticle_prev_ptr+1
       LDA #1
       STA reticle_has_under

 .render_frame_done
       RTS


; --- Update pipeline ---
; Updates Chell state from input and physics.
; Sets dirty_flag if redraw is needed.
  .update_chell
       ; Reset per-object dirty flags.
       LDA #0
       STA chell_dirty
       STA reticle_dirty

       ; Track previous reticle_active so we can detect hide/show transitions.
       LDA reticle_active
       STA reticle_prev_active

       ; Reticle mode is held (SHIFT).
       LDA keys_held
       AND #8
       BEQ update_normal_mode

       ; Reticle active while SHIFT held.
       LDA #1
       STA reticle_active

       JSR poll_reticle_keys
       BCC reticle_no_dirty
       LDA #1
       STA reticle_dirty
.reticle_no_dirty
       JMP update_apply_gravity

.update_normal_mode
       ; If we just released SHIFT, deactivate reticle and mark it dirty so render
       ; can restore its last rectangle.
       LDA reticle_active
       BEQ normal_mode_skip_hide
       LDA #0
       STA reticle_active

       LDA reticle_prev_active
       BEQ normal_mode_skip_hide
       LDA #1
       STA reticle_dirty
.normal_mode_skip_hide

       ; Normal mode: input -> update horizontal movement/anim.
       JSR poll_move_keys
       BCC update_skip_dirty_move
       LDA #1
       STA chell_dirty
.update_skip_dirty_move

.update_apply_gravity
       ; Physics -> update vertical position.
       JSR apply_gravity
       BCC update_finish
       LDA #1
       STA chell_dirty

  .update_finish
        ; Aim changes should trigger redraw while running (overlay changes).
        LDA char_grounded
        BEQ aim_change_done
        LDA move_held
        BEQ aim_change_done
        LDA aim_held
        CMP last_aim_held
        BEQ aim_change_done
        LDA #1
        STA chell_dirty
 .aim_change_done
        LDA aim_held
        STA last_aim_held

        ; Precompute Chell render decisions for next frame.
        LDA chell_dirty
        BEQ skip_precompute
        JSR compute_chell_render_state
 .skip_precompute

        ; Dirty flag for next frame.
        ; - If Chell is dirty, we must redraw Chell.
        ; - If reticle is active and (reticle_dirty or chell_dirty), redraw reticle.
        ; - If reticle just deactivated and had under saved, restore it.

        LDA #0
        STA dirty_flag

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

 .df_done
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

    ; Body
    LDA chell_body_index
    JSR render_character_sprite

    ; Overlay
    LDA chell_overlay_index
    JSR render_overlay_sprite

    ; Restore previous ROM selection and re-enable IRQs.
    LDA saved_romsel
    STA ROMSEL
    CLI
    RTS

; Draw the current reticle at screen_ptr.
; Reticle sprites live in Chell SWRAM, so we must page the bank in.
.draw_reticle_current
    SEI
    LDA ROMSEL
    STA saved_romsel

    LDA chell_bank
    STA ROMSEL

    LDA reticle_state
    JSR render_reticle_sprite

    LDA saved_romsel
    STA ROMSEL
    CLI
    RTS


; Compute render decisions for Chell (next screen pointer + sprite indices).
; Output:
; - chell_new_ptr = next screen address
; - chell_body_index = character sprite index (0-based)
; - chell_overlay_index = overlay sprite index (0-based)
.compute_chell_render_state
    ; Compute new screen pointer.
    JSR update_screen_ptr_from_char
    LDA screen_ptr
    STA chell_new_ptr
    LDA screen_ptr+1
    STA chell_new_ptr+1

    ; --- Body sprite index ---
    ; Default to idle pose; overwritten below.
    LDA char_grounded
    BNE cs_grounded

    ; Jump pose (airborne)
    LDA anim_dir
    BNE cs_jump_right
    LDA #CHELL_JUMP_LEFT_BASE
    BNE cs_body_base_ok
 .cs_jump_right
    LDA #CHELL_JUMP_RIGHT_BASE
    BNE cs_body_base_ok

 .cs_grounded
    ; Grounded: idle or running
    LDA move_held
    BNE cs_running

    ; Idle
    LDA anim_dir
    BNE cs_idle_right
    LDA #CHELL_IDLE_LEFT_BASE
    BNE cs_body_base_ok
 .cs_idle_right
    LDA #CHELL_IDLE_RIGHT_BASE
    BNE cs_body_base_ok

 .cs_running
    ; Run frame base: run_frame_seq[anim_frame] * 4
    LDX anim_frame
    LDA run_frame_seq,X
    ASL A
    ASL A

    ; Facing left adds run-left base.
    LDX anim_dir
    BNE cs_body_base_ok
    CLC
    ADC #CHELL_RUN_LEFT_BASE

 .cs_body_base_ok
    CLC
    ADC char_pixel_offset
    STA chell_body_index

    ; --- Overlay sprite index ---
    ; Jump/idle: always gun-forward overlay.
    LDA char_grounded
    BEQ cs_overlay_forward
    LDA move_held
    BEQ cs_overlay_forward

    ; Running: aim-aware overlay.
    ; Base within direction: aim_frame*4
    ; aim_frame mapping: forward=0, down=1, up=2
    LDA aim_held
    BEQ cs_overlay_aimframe_ok
    CMP #2
    BNE cs_overlay_aim_up
    LDA #1
    BNE cs_overlay_aimframe_ok
 .cs_overlay_aim_up
    LDA #2
 .cs_overlay_aimframe_ok
    ASL A
    ASL A
    STA temp

    ; If not aiming, add run-phase cycling (0/4/8).
    LDA aim_held
    BNE cs_overlay_have_index
    LDX anim_frame
    LDA run_frame_seq,X
    ASL A
    ASL A
    CLC
    ADC temp
    STA temp
 .cs_overlay_have_index

    ; Facing left adds 12.
    LDA anim_dir
    BNE cs_overlay_dir_ok
    LDA temp
    CLC
    ADC #CHELL_RUN_LEFT_BASE
    STA temp
 .cs_overlay_dir_ok

    LDA temp
    CLC
    ADC char_pixel_offset
    STA chell_overlay_index
    RTS

 .cs_overlay_forward
    LDA anim_dir
    BNE cs_overlay_forward_right
    LDA #CHELL_RUN_LEFT_BASE
    BNE cs_overlay_forward_ok
 .cs_overlay_forward_right
    LDA #0
 .cs_overlay_forward_ok
    CLC
    ADC char_pixel_offset
    STA chell_overlay_index
    RTS

 
  
; Poll reticle movement while SHIFT is held.
; Z/X/:/ move reticle in portal-grid cells.
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
    JSR calc_char_x
    CLC
    ADC #8
    LSR A
    LSR A
    LSR A
    LSR A
    CMP #8
    BCC reticle_snap_x_ok
    LDA #7
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
    STA move_cooldown

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
    CMP #7
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
    ; Update reticle_state from portalability (no LOS yet).
    ; We treat a portal cell as portalable if both underlying 8x16 tiles are portalable.

    ; y = cell_y*16 + 8
    LDY reticle_cell_y
    LDA times16_table,Y
    CLC
    ADC #8
    TAY

    ; x_left = cell_x*16 + 4
    LDY reticle_cell_x
    LDA times16_table,Y
    CLC
    ADC #4
    TAX

    JSR is_portalable
    BCC reticle_set_blocked

    ; x_right = cell_x*16 + 12
    LDY reticle_cell_x
    LDA times16_table,Y
    CLC
    ADC #12
    TAX

    ; Y must still be y_center
    LDY reticle_cell_y
    LDA times16_table,Y
    CLC
    ADC #8
    TAY

    JSR is_portalable
    BCC reticle_set_blocked

 .reticle_set_green
    LDA reticle_state
    CMP #1
    BEQ reticle_done
    LDA #1
    STA reticle_state
    LDA #1
    STA temp_y
    JMP reticle_done

 .reticle_set_blocked
    LDA reticle_state
    BEQ reticle_done
    LDA #0
    STA reticle_state
    LDA #1
    STA temp_y

 .reticle_done
    LDA temp_y
    BEQ reticle_no_redraw
    SEC
    RTS
.reticle_no_redraw
    CLC
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
 ;   bit0: left        (Z or cursor left)
 ;   bit1: right       (X or cursor right)
 ;   bit2: jump        (RETURN)
 ;   bit3: reticle     (SHIFT held)
 ;   bit4: reticle up  (':' / cursor up)
 ;   bit5: reticle down('/' / cursor down)
;
; Sample keyboard once this frame and build:
;   keys_held    = held bits
;   keys_pressed = newly pressed this frame (edge)
;   keys_prev    = last frame's keys_held
.sample_keys
     ; Safety: OSBYTE input polling expects IRQs enabled.
     CLI

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

     ; SHIFT (reticle mode)
     JSR is_shift_pressed
     BCC sample_no_shift
     LDA keys_held
     ORA #8
     STA keys_held
 .sample_no_shift

     ; Reticle up (':' or cursor up)
     ; ':' = INKEY(-73)
     LDX #&B7
     JSR is_key_pressed
     BCS sample_set_reticle_up

     ; cursor up = 138 => INKEY(-118)
     LDX #&8A
     JSR is_key_pressed
     BCC sample_no_reticle_up
 .sample_set_reticle_up
     LDA keys_held
     ORA #16
     STA keys_held
 .sample_no_reticle_up

     ; Reticle down ('/' or cursor down)
     ; '/' = INKEY(-105)
     LDX #&97
     JSR is_key_pressed
     BCS sample_set_reticle_down

     ; cursor down = 139 => INKEY(-117)
     LDX #&8B
     JSR is_key_pressed
     BCC sample_no_reticle_down
 .sample_set_reticle_down
     LDA keys_held
     ORA #32
     STA keys_held
 .sample_no_reticle_down
 
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
     ; While SHIFT is held (reticle mode), aim keys are repurposed.
     LDA #0
     STA aim_held

     LDA keys_held
     AND #8
     BNE sample_aim_done

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

; Return C=1 if SHIFT key is held.
; Uses OSBYTE &CA (202) "keyboard status byte".
; Returned status (old value) is in X:
; - bit 3 set if SHIFT is pressed.
.is_shift_pressed
    LDA #&CA
    LDX #0
    LDY #&FF
    JSR OSBYTE

    TXA
    AND #8
    BEQ shift_not_pressed
    SEC
    RTS
.shift_not_pressed
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
    JSR is_solid
    BCS collide_left

    ; test at y+24 (bottom tile centerline)
    LDY temp_y
    TYA
    CLC
    ADC #16
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
    JSR is_solid
    BCS collide_right

    ; test at y+24 (bottom tile centerline)
    LDY temp_y
    TYA
    CLC
    ADC #16
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
    JSR is_solid
    BCS grounded_true

    ; right foot center (x+7)
    LDA temp
    CLC
    ADC #7
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
    JSR is_solid
    BCS collide_down

    ; right foot center (x+7)
    LDA temp
    CLC
    ADC #7
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
    JSR is_solid
    BCS collide_up

    ; right head center (x+7)
    LDA temp
    CLC
    ADC #7
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
    ; (Purely derived from gameplay state; no extra visual bias.)
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

; Update screen_ptr from reticle portal-grid cell.
; Portal grid is 16x16 pixels, so X uses tile_x = reticle_cell_x*2.
.update_screen_ptr_from_reticle
    ; tile_y = reticle_cell_y
    LDA reticle_cell_y
    STA temp_y

    ; Look up screen base for this tile row
    ASL A
    TAY
    LDA tile_row_screen_table,Y
    STA screen_ptr
    LDA tile_row_screen_table+1,Y
    STA screen_ptr+1

    ; tile_x = reticle_cell_x * 2
    LDA reticle_cell_x
    ASL A
    TAY

    ; Add tile_x * 16
    LDA times16_table,Y
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC reticle_screen_done
    INC screen_ptr+1
.reticle_screen_done
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
