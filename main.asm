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
.char_vx            SKIP 1    ; Signed vx in px/frame (used for portal intent + momentum)
.char_prev_vy       SKIP 1    ; Previous vy (for floor/ceiling entry on landing)
.char_grounded      SKIP 1    ; 0/1: standing on solid
.gravity_cooldown   SKIP 1    ; Frames until next gravity tick
.rise_cooldown      SKIP 1    ; Frames until next upward step
.fall_cooldown      SKIP 1    ; Frames until next downward step
.room_dirty         SKIP 1    ; 0/1: room background needs redraw
.exit_cooldown      SKIP 1    ; frames to ignore exits after transition
.exit_probe0        SKIP 1    ; exit Y probe cell (y+8)>>4
.exit_probe1        SKIP 1    ; exit Y probe cell (y+24)>>4
.keys_held          SKIP 1    ; Bitfield: held keys this frame
.keys_pressed       SKIP 1    ; Bitfield: edge-trigger keys (held & ~prev)
.keys_prev          SKIP 1    ; Previous frame's keys_held
.aim_held           SKIP 1    ; 0=none, 1=up, 2=down

; Action button (SPACE) state.
.action_held        SKIP 1
.action_prev        SKIP 1
.action_pressed     SKIP 1

  ; Portal placement requests.
  ; - Set on A/S key-down (edge).
  ; - If reticle is not green that frame, it stays set until either:
  ;   - placement succeeds, or
  ;   - reticle is moved (or reticle mode is exited).
  ; bit0 = A, bit1 = B
  .portal_req        SKIP 1
.dirty_flag         SKIP 1    ; 0/1: needs redraw this frame
.temp_sprite_ptr    SKIP 2    ; Temp sprite pointer for striped blit

 .temp_mask_ptr      SKIP 2    ; Temp mask pointer for striped blit
 .chell_bank         SKIP 1    ; ROMSEL value for Chell SWRAM bank
 .obj_bank           SKIP 1    ; ROMSEL value for Object SWRAM bank
  .saved_romsel       SKIP 1    ; Saved ROMSEL around OS calls
 .chelldata_fh       SKIP 1    ; File handle for CHDATA
 .objdata_fh        SKIP 1    ; File handle for OBJDAT
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
.char_sprite_index   SKIP 1    ; Stable sprite index

; Precomputed render decisions for Chell (computed in update; used in render).
.chell_new_ptr       SKIP 2    ; next screen_ptr for Chell
.chell_body_index    SKIP 1    ; sprite index into character_sprite_table
.chell_overlay_index SKIP 1    ; sprite index into overlay_sprite_table
.last_aim_held       SKIP 1    ; previous aim_held (0/1/2)

.reticle_cell_x      SKIP 1    ; 0..14 (portal span X, top-left tile_x)
.reticle_cell_y      SKIP 1    ; 0..15 (portal grid Y)
.reticle_state       SKIP 1    ; 0=blocked, 1=portalable
 .reticle_active      SKIP 1    ; 0/1: draw reticle
 .reticle_prev_active SKIP 1    ; previous frame reticle_active
 .reticle_move_cd     SKIP 1    ; reticle move repeat cooldown
  .reticle_wall_orient SKIP 1    ; 0..4 (wall_l, wall_r, floor, ceil, back)

.exit_dst            SKIP 1    ; scratch: exit destination room index

.chell_dirty         SKIP 1    ; 0/1: Chell moved/changed last update
.reticle_dirty       SKIP 1    ; 0/1: reticle moved/changed last update

.chell_prev_ptr      SKIP 2    ; previous Chell screen_ptr
.reticle_prev_ptr    SKIP 2    ; previous reticle screen_ptr
.chell_has_under     SKIP 1    ; 0/1: have valid Chell save-under
.reticle_has_under   SKIP 1    ; 0/1: have valid reticle save-under

; Debug: why the reticle is currently green.
; 0 = not green / unknown
; 1 = floor/ceiling 2x1 match
; 2 = wall 1x2 match (left column)
; 3 = wall 1x2 match (right column)
; 4 = back-wall 2x2 empty match at y
; 5 = back-wall 2x2 empty match at y-1
 .reticle_debug_reason SKIP 1

 ; Portal stamping (partial redraw) state.
 .portal_pending      SKIP 1    ; 0/1: portal moved/placed; render must update background
 .portal_kind         SKIP 1    ; 0 = red (A), 1 = yellow (B)
  .portal_old_x        SKIP 1
  .portal_old_y        SKIP 1
  .portal_old_room     SKIP 1
  .portal_old_enabled  SKIP 1    ; 0/1: whether old portal was enabled
  .portal_old_orient   SKIP 1

  ; Portal instances (global per level)
  .portal_a_enabled    SKIP 1
  .portal_a_room       SKIP 1
  .portal_a_x          SKIP 1
  .portal_a_y          SKIP 1
  .portal_a_orient     SKIP 1    ; 0..4 (wall_l, wall_r, floor, ceil, back)
  .portal_b_enabled    SKIP 1
  .portal_b_room       SKIP 1
  .portal_b_x          SKIP 1
  .portal_b_y          SKIP 1
  .portal_b_orient     SKIP 1    ; 0..4 (wall_l, wall_r, floor, ceil, back)

  ; Portal teleportation (MVP wiring)
  .teleport_pending    SKIP 1    ; 0/1: overlap+intent detected; pending teleport
  .teleport_entry_kind SKIP 1    ; 0=A (red), 1=B (yellow)
  .teleport_cooldown   SKIP 1    ; frames remaining before portal can re-trigger
  .teleport_exit_room  SKIP 1
  .teleport_exit_x     SKIP 1
  .teleport_exit_y     SKIP 1
  .teleport_exit_orient SKIP 1
  .teleport_vt         SKIP 1    ; scratch: v_t during teleport
  .teleport_vn         SKIP 1    ; scratch: v_n during teleport
  .teleport_last_exit_kind SKIP 1    ; 0/1, $FF=none (debug/anti-ping-pong)

 ; --- Reticle LOS scratch ---
; All values are in pixels unless noted.
.los_x0        SKIP 1    ; ray start X
.los_y0        SKIP 1    ; ray start Y
.los_x1        SKIP 1    ; ray target X
.los_y1        SKIP 1    ; ray target Y
.los_dx        SKIP 1    ; abs(x1-x0)
.los_dy        SKIP 1    ; abs(y1-y0)
.los_err       SKIP 1    ; Bresenham error accumulator
.los_steps     SKIP 1    ; loop counter (major axis delta)
.los_sx        SKIP 1    ; step X (+1 or $FF)
.los_sy        SKIP 1    ; step Y (+1 or $FF)
.los_prev_tile SKIP 1    ; last visited tilepos (y*16+x), $FF = none
 
 ; --- Render list (PoP-style pipeline) ---
 ; Stored in screen scratch (not ZP) so MOS calls can't clobber it.
 ; Layout is a fixed 2-entry list.
 
 ORG &1900


CRTC_ADDR = &FE00
CRTC_DATA = &FE01
ROMSEL    = &FE30          ; Master paged ROM/SWRAM bank select

CHELL_SWRAM_BANK_DEFAULT = 4
CHELLDATA_BUF         = &7B00  ; Temp buffer in screen scratch

; Object (portal stamp) sprite+mask data lives in sideways RAM.
OBJ_SWRAM_BANK_DEFAULT = 5

; Render list storage lives in screen scratch so it survives MOS calls.
RENDER_LIST_BASE      = &78C0
RENDER_COUNT          = RENDER_LIST_BASE + 0
RENDER_IDS            = RENDER_LIST_BASE + 1   ; 2 bytes
RENDER_FLAGS          = RENDER_LIST_BASE + 3   ; 2 bytes
RENDER_NEW_PTR_LO     = RENDER_LIST_BASE + 5   ; 2 bytes
RENDER_NEW_PTR_HI     = RENDER_LIST_BASE + 7   ; 2 bytes

; Scratch state stored in the "below playfield" screen RAM.
; This avoids using MOS workspace zero-page addresses (e.g. &A0..) that file I/O can clobber.
PORTAL_REQ_SNAP_POS   = &7FF0   ; (x<<4)|y
PORTAL_REQ_SNAP_ORIENT= &7FF1

GRAVITY_ACCEL              = 1      ; vy += 1 per gravity tick (8px steps)
GRAVITY_UP_PERIOD           = 3      ; gravity tick period while rising
GRAVITY_DOWN_PERIOD         = 1      ; gravity tick period while falling
TERMINAL_VELOCITY_DOWN      = 1      ; max falling speed (8px steps)
JUMP_VELOCITY               = &FE    ; -2 (controls hang time)
RISE_STEP_PERIOD            = 2      ; move up 1 stripe every N frames
FALL_STEP_PERIOD            = 2      ; move down 1 stripe every N frames

PORTAL_EXIT_NUDGE           = 2
PORTAL_COOLDOWN_FRAMES      = 8

PORTAL_WALL_W_PX            = 8
PORTAL_WALL_H_PX            = 32
PORTAL_ALIGN_TOL_Y          = 8      ; max |chell_center_y - portal_center_y|

PORTAL_FC_W_PX              = 16
PORTAL_FC_H_PX              = 16
PORTAL_ALIGN_TOL_X          = 4      ; max |chell_center_x - portal_center_x|

PORTAL_ORIENT_WALL_L         = 0
PORTAL_ORIENT_WALL_R         = 1
PORTAL_ORIENT_FLOOR          = 2
PORTAL_ORIENT_CEIL           = 3
PORTAL_ORIENT_BACK           = 4

; Persistent gameplay object type IDs (from tools/gen-level output).
OBJ_TYPE_CUBE                = 1
OBJ_TYPE_BUTTON              = 2
OBJ_TYPE_PAD                 = 3
OBJ_TYPE_EXIT                = 4

CHELL_W_PX                   = 16
CHELL_H_PX                   = 32

; Approx visible bounds (used for portal exit placement).
; When facing right, Chell's visible "nose" is around x+10 (see will_collide_right).
CHELL_NOSE_X_RIGHT          = 10

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

      ; Load portal stamp sprites+masks into sideways RAM.
      ; Must happen before shadow screen is enabled (OS file I/O stays simpler).
      JSR load_obj_sprites

    ; Filing-system calls may clobber ZP, so restore our room pointers.
    JSR set_room_tilemap
    JSR set_room_portalmap

    ; Enable shadow screen (Master).
    ; We still use MODE 5 layout at &5800, but in shadow RAM.
    JSR enable_shadow_screen

    ; Initialize level-global object state from generated tables.
    JSR init_persistent_objects

    ; Place Chell at cell (4,4): cell_y*16 + cell_x = 4*16 + 4 = 68
    LDA #68
    STA char_tile_pos

    ; Init state.
    LDA #0
    STA char_pixel_offset
    STA char_byte_offset
    STA char_y_offset
    STA char_vy
    STA char_vx
    STA char_prev_vy
    STA char_grounded
    STA gravity_cooldown
    STA rise_cooldown
    STA fall_cooldown
    STA room_dirty
    STA exit_cooldown
    STA exit_probe0
    STA exit_probe1
    STA keys_held
    STA keys_pressed
    STA keys_prev
    STA action_held
    STA action_prev
     STA action_pressed
     STA portal_req
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
     STA reticle_wall_orient

    STA chell_dirty
    STA reticle_dirty
    STA chell_prev_ptr
    STA chell_prev_ptr+1
    STA reticle_prev_ptr
    STA reticle_prev_ptr+1
    STA chell_has_under
    STA reticle_has_under
    STA reticle_debug_reason

     STA portal_pending
     STA portal_kind
     STA portal_old_x
     STA portal_old_y
     STA portal_old_room
     STA portal_old_enabled
     STA portal_old_orient

     STA portal_a_enabled
     STA portal_a_room
     STA portal_a_x
     STA portal_a_y
     STA portal_a_orient
     STA portal_b_enabled
     STA portal_b_room
     STA portal_b_x
     STA portal_b_y
     STA portal_b_orient

     STA teleport_pending
     STA teleport_entry_kind
     STA teleport_cooldown
     STA teleport_exit_room
     STA teleport_exit_x
     STA teleport_exit_y
     STA teleport_exit_orient
     LDA #&FF
     STA teleport_last_exit_kind

    ; Default: face right.
    LDA #1
    STA anim_dir
    STA last_anim_dir

    ; Render background once.
    JSR render_tilemap
    JSR render_static_objects
    JSR stamp_portals_for_current_room
    JSR render_persistent_objects_current_room

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
        ; Room transition: redraw background first.
        LDA room_dirty
        BEQ render_no_room_redraw
        JSR set_room_tilemap
        JSR set_room_portalmap
        JSR render_tilemap
        JSR render_static_objects
        JSR stamp_portals_for_current_room
        JSR render_persistent_objects_current_room
        LDA #0
        STA room_dirty
        STA chell_has_under
        STA reticle_has_under

        ; Background redraw wipes sprites; force them to re-save-under and redraw.
        LDA #1
        STA chell_dirty
        LDA reticle_active
        BEQ render_no_room_redraw
        LDA #1
        STA reticle_dirty

  .render_no_room_redraw
        ; Portal placement: we will patch the background this frame.
        ; Force both sprites to redraw so their save-under captures the updated BG.
        LDA portal_pending
        BEQ render_no_portal_force
        LDA #1
        STA chell_dirty
        LDA reticle_active
        BEQ render_no_portal_force
        LDA #1
        STA reticle_dirty
  .render_no_portal_force

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
        BEQ render_portal_maybe
        LDA chell_has_under
        BEQ render_portal_maybe
        JSR restore_chell_under

  .render_portal_maybe
        ; If a portal was placed/moved, update background now (after restores).
        JSR apply_pending_portal_update

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

        ; Reticle is drawn tile-aligned to the 16px portal grid.
 .render_reticle_pos_ok
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

        ; Reticle mode is held (SHIFT), but only allowed when Chell is stable.
        ; Strictly one or the other:
        ; - If Chell is moving vertically (jump/fall), reticle cannot become active.
        LDA keys_held
        AND #8
        BEQ update_normal_mode

        LDA char_grounded
        BEQ update_normal_mode
        LDA char_vy
        BNE update_normal_mode

        ; Reticle active while SHIFT held and Chell is stable.
        LDA #1
        STA reticle_active

         JSR poll_reticle_keys
         BCC reticle_no_dirty
         LDA #1
         STA reticle_dirty
  .reticle_no_dirty

          ; Portal placement request handling.
          ; We latch A/S key-down into portal_req and allow placement on a later
          ; green frame. To avoid "delayed shot at a new target" we snapshot the
          ; current target on the press frame (portal_req bit7 marks snapshot-pending)
          ; and cancel the request if the target changes afterward.

          LDA portal_req
          BEQ reticle_req_ok

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
          BEQ reticle_req_no_snap

          LDA temp
          STA PORTAL_REQ_SNAP_POS
          LDA reticle_wall_orient
          STA PORTAL_REQ_SNAP_ORIENT

          ; Clear snapshot-pending flag.
          LDA portal_req
          AND #&7F
          STA portal_req

  .reticle_req_no_snap

          ; If the target changed after the request was made, cancel it.
          LDA portal_req
          AND #3
          BEQ reticle_req_ok

          LDA temp
          CMP PORTAL_REQ_SNAP_POS
          BNE reticle_cancel_req
          LDA reticle_wall_orient
          CMP PORTAL_REQ_SNAP_ORIENT
          BEQ reticle_req_ok

  .reticle_cancel_req
          LDA #0
          STA portal_req

  .reticle_req_ok

          ; Portal placement while in reticle mode.
          ; Use portal_req (latched edge) so a one-frame reticle flicker doesn't
          ; force you to re-press.
          ; Only place when the reticle is currently valid (green).
          LDA reticle_state
          BEQ reticle_place_done

          ; Prefer Portal A if both pressed.
          LDA portal_req
          AND #1
          BEQ reticle_check_place_b
          LDA #0
          JSR place_portal_from_reticle
          ; Consume request (requires key-up before next placement).
          LDA portal_req
          AND #&FE
          STA portal_req
          JMP reticle_place_done

   .reticle_check_place_b
          LDA portal_req
          AND #2
          BEQ reticle_place_done
          LDA #1
          JSR place_portal_from_reticle
          ; Consume request.
          LDA portal_req
          AND #&FD
          STA portal_req

   .reticle_place_done
         ; While in reticle mode, gameplay time is frozen.
         ; Chell does not step or fall; only the reticle updates.
         JMP update_finish

 .update_normal_mode
       ; Portal placement requests are only meaningful in reticle mode.
       ; Clear them when not in reticle mode so taps can't leak into gameplay.
       LDA #0
       STA portal_req

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
        ; While reticle mode is active, gameplay time is frozen.
        ; Don't allow teleports or room transitions to advance.
        LDA reticle_active
        BNE update_finish_no_gameplay

        ; Portal entry detection (overlap + intent only; no teleport yet).
        JSR check_portal_entry_intent

        ; If a portal entry was detected, perform the teleport now.
        ; (We can later split this into pending + consume phases.)
        JSR maybe_teleport

        ; Room exits (screen transitions).
        JSR check_room_exits

  .update_finish_no_gameplay

         ; Update persistent objects + channel signals (pads/buttons -> exits).
         ; While reticle mode is active we freeze gameplay, so skip this work.
         LDA reticle_active
         BNE update_skip_objects
         JSR update_signals_and_object_states
  .update_skip_objects

        ; While in reticle mode we ignore aim-based redraws.
        LDA reticle_active
        BNE aim_change_done

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

         ; Room redraw requested (room transition or object visual change).
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


INCLUDE "portal_teleport.asm"


; --- Room exits / transitions ---
;
; Uses the generated exit tables in `levels/generated_level1.asm`.
;
; For now we support left/right edge exits only.
;
; Exit matching uses Chell's feet cell:
;   feet_cell_y = (top_y + 31) >> 4
; (We can tighten this later to require a full 16x32 clearance.)
;
; Returns: C=1 if room changed.
.check_room_exits
    ; Don't transition while in reticle mode.
    LDA reticle_active
    BEQ exits_check_cooldown
    CLC
    RTS

.exits_check_cooldown
    LDA exit_cooldown
    BEQ exits_check_edges
    DEC exit_cooldown
    CLC
    RTS

.exits_check_edges
    ; --- Right edge ---
    ; Trigger exits only when Chell is facing/moving into the edge.
    ; This avoids immediate bounce-back when spawning at an entrance.
    JSR calc_char_x
    CMP #112
    BCC check_left_edge

    LDA anim_dir
    BEQ check_left_edge
    LDA move_held
    ORA last_move_held
    BEQ check_left_edge

    ; Preserve current top Y pixel (for spawn), in temp_y.
    JSR calc_char_y
    STA temp_y

    ; Compute feet_cell_y into temp (0..15).
    LDA temp_y
    CLC
    ADC #31
    LSR A
    LSR A
    LSR A
    LSR A
    STA temp

    JSR find_exit_right
    BCC check_left_edge

    ; Enter destination from left. A already holds dst room.
    JSR transition_enter_from_left
    SEC
    RTS

.check_left_edge
    JSR calc_char_x
    BNE exits_none

    LDA anim_dir
    BNE exits_none
    LDA move_held
    ORA last_move_held
    BEQ exits_none

    ; Preserve current top Y pixel (for spawn), in temp_y.
    JSR calc_char_y
    STA temp_y

    ; Compute feet_cell_y into temp (0..15).
    LDA temp_y
    CLC
    ADC #31
    LSR A
    LSR A
    LSR A
    LSR A
    STA temp

    JSR find_exit_left
    BCC exits_none

    ; Enter destination from right. A already holds dst room.
    JSR transition_enter_from_right
    SEC
    RTS

.exits_none
    CLC
    RTS


; Find matching right-edge exit for current_room.
; Input: temp = feet_cell_y
; Output: C=1 and A=dst_room on match, else C=0.
.find_exit_right
    LDX current_room
    LDA exit_right_counts,X
    BEQ find_exit_none
    STA col_counter

    TXA
    ASL A
    TAX
    LDA exit_right_ptrs,X
    STA temp_sprite_ptr
    LDA exit_right_ptrs+1,X
    STA temp_sprite_ptr+1
    JMP find_exit_scan

; Find matching left-edge exit for current_room.
.find_exit_left
    LDX current_room
    LDA exit_left_counts,X
    BEQ find_exit_none
    STA col_counter

    TXA
    ASL A
    TAX
    LDA exit_left_ptrs,X
    STA temp_sprite_ptr
    LDA exit_left_ptrs+1,X
    STA temp_sprite_ptr+1

.find_exit_scan
    ; col_counter = count, temp_sprite_ptr points at entries.
    ; Each entry: a0,a1,dst
    LDY #0
.find_exit_loop
    ; a0
    LDA (temp_sprite_ptr),Y
    STA temp_mask_ptr
    ; a1
    INY
    LDA (temp_sprite_ptr),Y
    STA temp_mask_ptr+1
    ; dst
    INY
    LDA (temp_sprite_ptr),Y
    STA exit_dst

    ; Check feet within [a0..a1]
    LDA temp
    CMP temp_mask_ptr
    BCC find_exit_next
    LDA temp
    CMP temp_mask_ptr+1
    BCC find_exit_match
    BEQ find_exit_match
    JMP find_exit_next

.find_exit_match
    LDA exit_dst
    SEC
    RTS

.find_exit_next
    ; advance ptr by 3 bytes
    LDA temp_sprite_ptr
    CLC
    ADC #3
    STA temp_sprite_ptr
    BCC find_exit_next_ok
    INC temp_sprite_ptr+1
.find_exit_next_ok

    LDY #0
    DEC col_counter
    BNE find_exit_loop

.find_exit_none
    CLC
    RTS


; Room transition helpers.
; Inputs:
; - A = destination room index
; - temp_y = preserved top Y (pixel)
; Preserves velocity; snaps X to the new edge.
.transition_enter_from_left
    STA current_room
    JSR set_room_tilemap
    JSR set_room_portalmap
    JSR build_material_planes_from_tilemap

    ; Spawn at the left edge (entrance).
    LDA temp_y
    AND #&F0
    STA char_tile_pos
    LDA temp_y
    AND #&0F
    STA char_y_offset
    LDA #0
    STA char_byte_offset
    STA char_pixel_offset

    ; Mark for redraw
    LDA #1
    STA room_dirty
    STA chell_dirty
    ; Clear movement intent so we don't immediately re-trigger exits.
    LDA #0
    STA move_held
    STA last_move_held
    LDA #8
    STA exit_cooldown

    ; Cancel reticle.
    LDA #0
    STA reticle_active
    STA reticle_prev_active
    STA reticle_has_under
    STA chell_has_under
    RTS

.transition_enter_from_right
    STA current_room
    JSR set_room_tilemap
    JSR set_room_portalmap
    JSR build_material_planes_from_tilemap

    ; Spawn at the right edge (entrance).
    ; x=112 => tile_x=14, byte/pixel offset 0.
    LDA temp_y
    AND #&F0
    ORA #14
    STA char_tile_pos
    LDA temp_y
    AND #&0F
    STA char_y_offset
    LDA #0
    STA char_byte_offset
    STA char_pixel_offset

    ; Mark for redraw
    LDA #1
    STA room_dirty
    STA chell_dirty
    ; Clear movement intent so we don't immediately re-trigger exits.
    LDA #0
    STA move_held
    STA last_move_held
    LDA #8
    STA exit_cooldown

    ; Cancel reticle.
    LDA #0
    STA reticle_active
    STA reticle_prev_active
    STA reticle_has_under
    STA chell_has_under
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

 
  
INCLUDE "reticle.asm"


  ; Poll Z/X for left/right movement (single-pixel).
  ; (Moved to movement.asm)

 
INCLUDE "input.asm"


; Place a portal by updating the current room's static-object entry.
; This updates global portal state (one A + one B per level).
;
; Input:
; - A = 0 for Portal A (red)
; - A = 1 for Portal B (yellow)
;
.place_portal_from_reticle
     STA portal_kind

      ; Snapshot old portal state (for erase).
     LDA portal_kind
     BEQ ppr_snap_a
      ; B
      LDA portal_b_enabled
      STA portal_old_enabled
      LDA portal_b_room
      STA portal_old_room
      LDA portal_b_x
      STA portal_old_x
      LDA portal_b_y
      STA portal_old_y
      LDA portal_b_orient
      STA portal_old_orient
      JMP ppr_compute_new
    .ppr_snap_a
      LDA portal_a_enabled
      STA portal_old_enabled
      LDA portal_a_room
      STA portal_old_room
      LDA portal_a_x
      STA portal_old_x
      LDA portal_a_y
      STA portal_old_y
      LDA portal_a_orient
      STA portal_old_orient

   .ppr_compute_new
      ; Compute new x.
      ; Wall portal can snap to either the left or right 8px column within the
      ; 16px reticle span. reticle_debug_reason distinguishes:
      ;   2 = left column match
      ;   3 = right column match
     LDA reticle_debug_reason
     AND #&7F
     CMP #3
     BNE ppr_x_left
     LDA reticle_cell_x
     CLC
     ADC #1
     JMP ppr_x_store
   .ppr_x_left
     LDA reticle_cell_x
   .ppr_x_store
     STA temp

      ; y (clamp away from final row only for 2-tile-tall portals)
      LDA reticle_cell_y
      STA temp_y

      ; Orientation computed by reticle validation.
      ; 0..4 (wall_l, wall_r, floor, ceil, back)
      LDA reticle_wall_orient
      STA row_counter

      ; For floor/ceiling portals, the surface tiles are solid.
      ; Store the portal's rect in the adjacent empty space so overlap can occur:
      ; - floor surface at y => portal rect at y-1
      ; - ceiling surface at y => portal rect at y+1
      LDA row_counter
      CMP #PORTAL_ORIENT_FLOOR
      BNE ppr_not_floor
      LDA temp_y
      BEQ ppr_reject_oob
      DEC temp_y
      JMP ppr_y_ok
  .ppr_not_floor
      CMP #PORTAL_ORIENT_CEIL
      BNE ppr_not_ceil
      LDA temp_y
      CMP #15
      BEQ ppr_reject_oob
      INC temp_y
      JMP ppr_y_ok
  .ppr_not_ceil

      ; Wall/back-wall stamps are 2 tiles tall; clamp y so y+1 stays in range.
      CMP #PORTAL_ORIENT_FLOOR
      BCS ppr_y_ok
      LDA temp_y
      CMP #15
      BNE ppr_y_ok
      LDA #14
      STA temp_y
    .ppr_y_ok

      JMP ppr_overlap_check

  .ppr_reject_oob
      RTS

   .ppr_overlap_check

       ; Prevent overlapping portals (red and yellow cannot overlap).
       ; Disallow placement if tile footprints intersect.
      ; new footprint dims (tile units) into col_counter(w) and screen_ptr(h)
      LDA row_counter
      CMP #PORTAL_ORIENT_BACK
      BEQ ppr_new_back
      CMP #PORTAL_ORIENT_FLOOR
      BCS ppr_new_fc
      ; wall (1x2)
      LDA #1
      STA col_counter
      LDA #2
      STA screen_ptr
      JMP ppr_overlap_have_new
   .ppr_new_fc
      ; floor/ceiling (2x1)
      LDA #2
      STA col_counter
      LDA #1
      STA screen_ptr
      JMP ppr_overlap_have_new
   .ppr_new_back
      ; back wall (2x2)
      LDA #2
      STA col_counter
      STA screen_ptr

   .ppr_overlap_have_new
      ; Determine other portal (the one we're not placing).
      LDA portal_kind
      BEQ ppr_check_vs_b

      ; Placing B: check against A
      LDA portal_a_enabled
      BEQ ppr_no_overlap
      LDA portal_a_room
      CMP current_room
      BNE ppr_no_overlap
      LDA portal_a_x
      STA screen_ptr+1          ; other_x
      LDA portal_a_y
      STA temp_mask_ptr         ; other_y
      LDA portal_a_orient
      JMP ppr_overlap_have_other

   .ppr_check_vs_b
      ; Placing A: check against B
      LDA portal_b_enabled
      BEQ ppr_no_overlap
      LDA portal_b_room
      CMP current_room
      BNE ppr_no_overlap
      LDA portal_b_x
      STA screen_ptr+1          ; other_x
      LDA portal_b_y
      STA temp_mask_ptr         ; other_y
      LDA portal_b_orient

   .ppr_overlap_have_other
      ; other dims into temp_mask_ptr+1(w) and temp_sprite_ptr(h)
      CMP #PORTAL_ORIENT_BACK
      BEQ ppr_other_back
      CMP #PORTAL_ORIENT_FLOOR
      BCS ppr_other_fc
      ; wall (1x2)
      LDA #1
      STA temp_mask_ptr+1
      LDA #2
      STA temp_sprite_ptr
      JMP ppr_overlap_test
   .ppr_other_fc
      ; floor/ceiling (2x1)
      LDA #2
      STA temp_mask_ptr+1
      LDA #1
      STA temp_sprite_ptr
      JMP ppr_overlap_test
   .ppr_other_back
      ; back wall (2x2)
      LDA #2
      STA temp_mask_ptr+1
      STA temp_sprite_ptr

   .ppr_overlap_test
      ; X overlap:
      ; if (new_x + new_w) <= other_x => no overlap
      LDA temp
      CLC
      ADC col_counter
      CMP screen_ptr+1
      BEQ ppr_no_overlap
      BCC ppr_no_overlap

      ; if (other_x + other_w) <= new_x => no overlap
      LDA screen_ptr+1
      CLC
      ADC temp_mask_ptr+1
      CMP temp
      BEQ ppr_no_overlap
      BCC ppr_no_overlap

      ; Y overlap:
      ; if (new_y + new_h) <= other_y => no overlap
      LDA temp_y
      CLC
      ADC screen_ptr
      CMP temp_mask_ptr
      BEQ ppr_no_overlap
      BCC ppr_no_overlap

      ; if (other_y + other_h) <= new_y => no overlap
      LDA temp_mask_ptr
      CLC
      ADC temp_sprite_ptr
      CMP temp_y
      BEQ ppr_no_overlap
      BCC ppr_no_overlap

      ; Intersects => reject placement.
      RTS

    .ppr_no_overlap

      ; Commit new state.
      LDA portal_kind
      BEQ ppr_set_a
      ; B
     LDA #1
     STA portal_b_enabled
     LDA current_room
     STA portal_b_room
     LDA temp
     STA portal_b_x
     LDA temp_y
     STA portal_b_y
     LDA row_counter
     STA portal_b_orient
     JMP ppr_done
   .ppr_set_a
     LDA #1
     STA portal_a_enabled
     LDA current_room
     STA portal_a_room
     LDA temp
     STA portal_a_x
     LDA temp_y
     STA portal_a_y
     LDA row_counter
     STA portal_a_orient
   .ppr_done

     LDA #1
     STA portal_pending
     RTS


; Apply a pending portal update without redrawing the whole room.
; This erases the old portal stamp by re-rendering the underlying tiles, then
; stamps the updated portal entry.
;
; Safe to call unconditionally; returns quickly if portal_pending=0.
.apply_pending_portal_update
     LDA portal_pending
     BNE apu_go
     RTS

  .apu_go
      ; Erase old stamp if it was previously enabled AND visible in this room.
      LDA portal_old_enabled
      BNE apu_old_enabled
      JMP apu_stamp_new
  .apu_old_enabled
      LDA portal_old_room
      CMP current_room
      BEQ apu_old_visible
      JMP apu_stamp_new
  .apu_old_visible

      ; Redraw underlying tiles for the old portal footprint.
      LDA portal_old_orient
      CMP #PORTAL_ORIENT_BACK
      BEQ apu_erase_back
      CMP #PORTAL_ORIENT_FLOOR
      BCS apu_erase_fc

      ; Wall: 1x2 tiles at (x,y) and (x,y+1)
      LDX portal_old_x
      LDA portal_old_y
      JSR redraw_tile_xy

      LDA portal_old_y
      CMP #15
      BNE apu_wall_redraw2
      JMP apu_stamp_new
  .apu_wall_redraw2
      CLC
      ADC #1
      LDX portal_old_x
      JSR redraw_tile_xy
      JMP apu_stamp_new

  .apu_erase_fc
      ; Floor/ceiling: 2x1 tiles at (x,y) and (x+1,y)
      ; Stored y is the collision rect (in empty space). Drawn portal lives on the
      ; surface tile row, so adjust Y for redraw.
      LDA portal_old_orient
      LDX portal_old_x
      LDY portal_old_y
      CMP #PORTAL_ORIENT_FLOOR
      BNE apu_erase_fc_not_floor
      INY
      JMP apu_erase_fc_have_y
  .apu_erase_fc_not_floor
      CMP #PORTAL_ORIENT_CEIL
      BNE apu_erase_fc_have_y
      DEY
  .apu_erase_fc_have_y
       ; Preserve adjusted Y across redraw_tile_xy (it clobbers Y).
       STY temp_y
       ; Redraw both tiles in the 2x1 footprint.
       LDX portal_old_x
       LDA temp_y
       JSR redraw_tile_xy

       LDX portal_old_x
       CPX #15
       BEQ apu_stamp_new
       INX
       LDA temp_y
       JSR redraw_tile_xy

       JMP apu_stamp_new

  .apu_erase_back
      ; Back wall: 2x2 tiles at (x,y),(x+1,y),(x,y+1),(x+1,y+1)
      LDA portal_old_y
      STA temp_y

      ; top row
      LDX portal_old_x
      LDA temp_y
      JSR redraw_tile_xy
      LDX portal_old_x
      CPX #15
      BEQ apu_back_skip_topx
      INX
      LDA temp_y
      JSR redraw_tile_xy
  .apu_back_skip_topx

      ; bottom row
      LDA temp_y
      CMP #15
      BEQ apu_stamp_new
      CLC
      ADC #1
      STA temp_y
      LDX portal_old_x
      LDA temp_y
      JSR redraw_tile_xy
      LDX portal_old_x
      CPX #15
      BEQ apu_stamp_new
      INX
      LDA temp_y
      JSR redraw_tile_xy

      LDX portal_old_x
      CPX #15
      BEQ apu_stamp_new
      INX
      LDA temp_y
      JSR redraw_tile_xy

  .apu_stamp_new
      ; Stamp the newly placed portal if it is visible in this room.
     LDA portal_kind
     BEQ apu_try_a
     ; B
     LDA portal_b_enabled
     BEQ apu_done
     LDA portal_b_room
     CMP current_room
     BNE apu_done
       LDA portal_b_orient
       STA row_counter
       LDA #1
       PHA
       LDX portal_b_x
       LDY portal_b_y
       ; Adjust draw Y for floor/ceiling (stored y is collision rect).
       LDA row_counter
       CMP #PORTAL_ORIENT_FLOOR
      BNE apu_stamp_b_not_floor
      INY
      JMP apu_stamp_b_y_ok
  .apu_stamp_b_not_floor
       CMP #PORTAL_ORIENT_CEIL
       BNE apu_stamp_b_y_ok
       DEY
   .apu_stamp_b_y_ok
       PLA
       JSR stamp_portal_xy
       JMP apu_done
  .apu_try_a
     LDA portal_a_enabled
     BEQ apu_done
      LDA portal_a_room
      CMP current_room
      BNE apu_done
        LDA portal_a_orient
        STA row_counter
        LDA #0
        PHA
         LDX portal_a_x
         LDY portal_a_y
        ; Adjust draw Y for floor/ceiling (stored y is collision rect).
        LDA row_counter
        CMP #PORTAL_ORIENT_FLOOR
       BNE apu_stamp_a_not_floor
       INY
       JMP apu_stamp_a_y_ok
  .apu_stamp_a_not_floor
        CMP #PORTAL_ORIENT_CEIL
        BNE apu_stamp_a_y_ok
        DEY
   .apu_stamp_a_y_ok
        PLA
         JSR stamp_portal_xy

  .apu_done
     LDA #0
     STA portal_pending
     RTS


; Redraw a single 8x16 tile from the tilemap.
; Inputs:
; - A = tile_y (0..15)
; - X = tile_x (0..15)
; Clobbers: A,X,Y,temp,row_counter,temp_y,screen_ptr
.redraw_tile_xy
     STA temp_y
     STX row_counter

     ; Fetch tile id: idx = y*16 + x
     LDY temp_y
     LDA times16_table,Y
     CLC
     ADC row_counter
     TAY
     LDA (tilemap_ptr),Y
     STA temp

     ; screen_ptr := base of tile row
     LDA temp_y
     ASL A
     TAY
     LDA tile_row_screen_table,Y
     STA screen_ptr
     LDA tile_row_screen_table+1,Y
     STA screen_ptr+1

     ; + x*16
     LDY row_counter
     LDA times16_table,Y
     CLC
     ADC screen_ptr
     STA screen_ptr
     BCC rtx_x_ok
     INC screen_ptr+1
  .rtx_x_ok

     LDA temp
     JSR render_cell8x16
     RTS


; Stamp portal sprite at tile coordinates.
; Inputs:
; - A = kind (0=red, 1=yellow)
; - X = tile_x (0..15)
; - Y = tile_y (0..15)
; - row_counter = orient (0=left wall, 1=right wall)
; Uses fixed stamp geometry: 8x32 (1 tile wide x 2 tiles tall).
  .stamp_portal_xy
       ; Preserve kind.
       STA temp

     ; screen_ptr := &5800 + y*512 + x*16
     LDA #<(&5800)
     STA screen_ptr
     LDA #>(&5800)
     STA screen_ptr+1

     ; y*512 => add (y*2) to high byte
     TYA
     ASL A
     CLC
     ADC screen_ptr+1
     STA screen_ptr+1

     ; x*16 => add to low byte
     TXA
     TAY
     LDA times16_table,Y
     CLC
     ADC screen_ptr
     STA screen_ptr
     BCC spx_ok
     INC screen_ptr+1
  .spx_ok

       ; sprite_ptr/mask_ptr
       ; Choose based on portal kind + orientation.
      ; Note: our source CSVs are the "(Right)" wall variant, so:
      ; - *_r_* = right-wall portal art (tile id 5)
      ; - *_l_* = left-wall portal art, generated by flip_x
      ;
      ; Flipped inputs synthesize x0..x3 shifts; x3 corresponds to the
      ; unshifted variant when flip_x is enabled.
      ; When the portal pixels live in the *right* half of the 16px sprite, we
      ; start 16 bytes into each stripe.
      ; Floor/ceiling: 16x16 (2 stripes, 32 bytes/stripe).
      ; Back wall: 16x32 (4 stripes, 32 bytes/stripe).
      ;
      ; Note: sprite+mask bytes live in object SWRAM; page it in for reads.
      SEI
      LDA ROMSEL
      STA saved_romsel
      LDA obj_bank
      STA ROMSEL

       LDA row_counter
       CMP #PORTAL_ORIENT_BACK
       BEQ spx_is_back
       CMP #PORTAL_ORIENT_FLOOR
       BCS spx_not_wall
       JMP spx_is_wall
 .spx_not_wall

      LDA temp
      BEQ spx_fc_red

      ; Yellow floor/ceiling
      LDA row_counter
      CMP #PORTAL_ORIENT_CEIL
      BEQ spx_fc_yel_ceil
       ; floor
        LDA #<portal_h_yel_floor_x0
        STA sprite_ptr
        LDA #>portal_h_yel_floor_x0
        STA sprite_ptr+1
        LDA #<portal_h_yel_floor_x0_mask
        STA mask_ptr
        LDA #>portal_h_yel_floor_x0_mask
        STA mask_ptr+1
       JMP spx_fc_stamp
  .spx_fc_yel_ceil
        LDA #<portal_h_yel_ceil_x0
        STA sprite_ptr
        LDA #>portal_h_yel_ceil_x0
        STA sprite_ptr+1
        LDA #<portal_h_yel_ceil_x0_mask
        STA mask_ptr
        LDA #>portal_h_yel_ceil_x0_mask
        STA mask_ptr+1
       JMP spx_fc_stamp

 .spx_fc_red
      LDA row_counter
      CMP #PORTAL_ORIENT_CEIL
      BEQ spx_fc_red_ceil
       ; floor
        LDA #<portal_h_red_floor_x0
        STA sprite_ptr
        LDA #>portal_h_red_floor_x0
        STA sprite_ptr+1
        LDA #<portal_h_red_floor_x0_mask
        STA mask_ptr
        LDA #>portal_h_red_floor_x0_mask
        STA mask_ptr+1
       JMP spx_fc_stamp
  .spx_fc_red_ceil
        LDA #<portal_h_red_ceil_x0
        STA sprite_ptr
        LDA #>portal_h_red_ceil_x0
        STA sprite_ptr+1
        LDA #<portal_h_red_ceil_x0_mask
        STA mask_ptr
        LDA #>portal_h_red_ceil_x0_mask
        STA mask_ptr+1

  .spx_fc_stamp
       ; A=stripe_count, X=bytes_per_stripe, Y=stride
       LDA #2
       LDX #32
       LDY #32
       JSR stamp_striped_masked
       JMP spx_done

 .spx_is_back
      LDA temp
      BEQ spx_back_red

       ; Yellow back wall
        LDA #<portal_b_yel_x0
        STA sprite_ptr
        LDA #>portal_b_yel_x0
        STA sprite_ptr+1
        LDA #<portal_b_yel_x0_mask
        STA mask_ptr
        LDA #>portal_b_yel_x0_mask
        STA mask_ptr+1
       JMP spx_back_stamp

  .spx_back_red
        LDA #<portal_b_red_x0
        STA sprite_ptr
        LDA #>portal_b_red_x0
        STA sprite_ptr+1
        LDA #<portal_b_red_x0_mask
        STA mask_ptr
        LDA #>portal_b_red_x0_mask
        STA mask_ptr+1

  .spx_back_stamp
       ; A=stripe_count, X=bytes_per_stripe, Y=stride
       LDA #4
       LDX #32
       LDY #32
       JSR stamp_striped_masked
       JMP spx_done

 .spx_is_wall
      LDA temp
      BEQ spx_red

      ; Yellow
      LDA row_counter
      BEQ spx_yel_leftwall
       ; right wall: use authored right-wall sprite
        LDA #<portal_v_yel_r_x0
        STA sprite_ptr
        LDA #>portal_v_yel_r_x0
        STA sprite_ptr+1
        LDA #<portal_v_yel_r_x0_mask
        STA mask_ptr
        LDA #>portal_v_yel_r_x0_mask
        STA mask_ptr+1
       JMP spx_stamp
    .spx_yel_leftwall
       ; left wall: use flipped sprite, unshifted = x3
        LDA #<portal_v_yel_l_x3
        STA sprite_ptr
        LDA #>portal_v_yel_l_x3
        STA sprite_ptr+1
        LDA #<portal_v_yel_l_x3_mask
        STA mask_ptr
        LDA #>portal_v_yel_l_x3_mask
        STA mask_ptr+1

      ; Offset into right half (columns 2+3) of each 16x32 stripe.
      LDA sprite_ptr
      CLC
      ADC #16
      STA sprite_ptr
      BCC spx_yel_ptr_ok
      INC sprite_ptr+1
   .spx_yel_ptr_ok
      LDA mask_ptr
      CLC
      ADC #16
      STA mask_ptr
      BCC spx_yel_mask_ok
      INC mask_ptr+1
   .spx_yel_mask_ok
      JMP spx_stamp

  .spx_red
      ; Red
      LDA row_counter
      BEQ spx_red_leftwall
       ; right wall: use authored right-wall sprite
        LDA #<portal_v_red_r_x0
        STA sprite_ptr
        LDA #>portal_v_red_r_x0
        STA sprite_ptr+1
        LDA #<portal_v_red_r_x0_mask
        STA mask_ptr
        LDA #>portal_v_red_r_x0_mask
        STA mask_ptr+1
       JMP spx_stamp
    .spx_red_leftwall
       ; left wall: use flipped sprite, unshifted = x3
        LDA #<portal_v_red_l_x3
        STA sprite_ptr
        LDA #>portal_v_red_l_x3
        STA sprite_ptr+1
        LDA #<portal_v_red_l_x3_mask
        STA mask_ptr
        LDA #>portal_v_red_l_x3_mask
        STA mask_ptr+1

      ; Offset into right half (columns 2+3) of each 16x32 stripe.
      LDA sprite_ptr
      CLC
      ADC #16
      STA sprite_ptr
      BCC spx_red_ptr_ok
      INC sprite_ptr+1
   .spx_red_ptr_ok
      LDA mask_ptr
      CLC
      ADC #16
      STA mask_ptr
      BCC spx_red_mask_ok
      INC mask_ptr+1
   .spx_red_mask_ok

  .spx_stamp
       ; A=stripe_count, X=bytes_per_stripe, Y=stride
       LDA #4
       LDX #16
       LDY #32
       JSR stamp_striped_masked
       JMP spx_done

  .spx_done
      ; Restore ROMSEL and re-enable IRQs.
      LDA saved_romsel
      STA ROMSEL
      CLI
      RTS



; Stamp portals that belong to current_room.
.stamp_portals_for_current_room
     ; Portal A
     LDA portal_a_enabled
     BEQ spcr_b
     LDA portal_a_room
     CMP current_room
     BNE spcr_b
      LDA portal_a_orient
      STA row_counter
      LDA #0
      PHA
      LDX portal_a_x
      LDY portal_a_y
      ; Adjust draw Y for floor/ceiling (stored y is collision rect).
      LDA row_counter
      CMP #PORTAL_ORIENT_FLOOR
      BNE spcr_a_not_floor
      INY
      JMP spcr_a_y_ok
  .spcr_a_not_floor
      CMP #PORTAL_ORIENT_CEIL
      BNE spcr_a_y_ok
      DEY
  .spcr_a_y_ok
      PLA
      JSR stamp_portal_xy

  .spcr_b
     ; Portal B
     LDA portal_b_enabled
     BEQ spcr_done
     LDA portal_b_room
     CMP current_room
     BNE spcr_done
      LDA portal_b_orient
      STA row_counter
      LDA #1
      PHA
      LDX portal_b_x
      LDY portal_b_y
      ; Adjust draw Y for floor/ceiling (stored y is collision rect).
      LDA row_counter
      CMP #PORTAL_ORIENT_FLOOR
      BNE spcr_b_not_floor
      INY
      JMP spcr_b_y_ok
  .spcr_b_not_floor
      CMP #PORTAL_ORIENT_CEIL
      BNE spcr_b_y_ok
      DEY
  .spcr_b_y_ok
      PLA
      JSR stamp_portal_xy

  .spcr_done
      RTS


INCLUDE "persistent_objects.asm"
 
INCLUDE "ui.asm"

INCLUDE "loaders.asm"

INCLUDE "room_runtime.asm"

; Chell movement and physics.
INCLUDE "movement.asm"


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



INCLUDE "sprites.asm"
INCLUDE "masks.asm"
INCLUDE "tilemap.asm"
INCLUDE "objects.asm"
INCLUDE "render.asm"
INCLUDE "lookup_tables.asm"

INCLUDE "persistent_objects_data.asm"

.end

SAVE "PORTHLE", start, end
PUTBASIC "program.bas", "PROGRAM"

; Object stamp sprite+mask data file for sideways RAM.
; This is loaded at runtime into a sideways RAM bank mapped at &8000..&BFFF.
ORG &8000
.objdata_start
INCLUDE "sprites/generated_objects_sprites.asm"
INCLUDE "sprites/generated_objects_masks.asm"

; Pad to full 16KB SWRAM bank.
ORG &C000
.objdata_end
SAVE "OBJDAT", objdata_start, objdata_end

; Chell sprite+mask data file for sideways RAM.
; This is loaded at runtime into a sideways RAM bank mapped at &8000..&BFFF.

; Reuse the &8000..&BFFF assembly window for a second banked-data file.
CLEAR &8000, &C000
ORG &8000
.chelldata_start
INCLUDE "sprites/generated_chell_sprites.asm"
INCLUDE "sprites/generated_chell_masks.asm"

; Pad to full 16KB SWRAM bank.
ORG &C000
.chelldata_end
SAVE "CHDATA", chelldata_start, chelldata_end
