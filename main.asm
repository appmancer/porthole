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


; Detect Chell walking into a portal.
;
; Rule (wall portals only for now): trigger when Chell overlaps the portal rect
; (8x32) and is moving into the face (left portal => moving left, right portal
; => moving right). We also require the *other* portal to be enabled so the
; eventual teleport has a destination.
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
        JSR cpei_try_portal_a
        BCS cpei_done
        JSR cpei_try_portal_b

.cpei_done
        RTS


; If teleport_pending is set, teleport Chell to the other portal.
; Wall portals only (0=left wall, 1=right wall).
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
        BNE mt_portal_x_ok
        LDA screen_ptr
        CLC
        ADC #8
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
        ; t=(0,+1), n=(+1,0) => v_t=vy, v_n=-vx
        LDA char_vy
        STA teleport_vt
        LDA char_vx
        EOR #&FF
        CLC
        ADC #1
        STA teleport_vn
        JMP mt_vtn_done
 .mt_vtn_wall_r
        ; t=(0,-1), n=(-1,0) => v_t=-vy, v_n=vx
        LDA char_vy
        EOR #&FF
        CLC
        ADC #1
        STA teleport_vt
        LDA char_vx
        STA teleport_vn
        JMP mt_vtn_done
 .mt_vtn_floor
        ; t=(+1,0), n=(0,-1) => v_t=vx, v_n=vy
        LDA char_vx
        STA teleport_vt
        LDA char_vy
        STA teleport_vn
        JMP mt_vtn_done
 .mt_vtn_ceil
        ; t=(-1,0), n=(0,+1) => v_t=-vx, v_n=-vy
        LDA char_vx
        EOR #&FF
        CLC
        ADC #1
        STA teleport_vt
        LDA char_vy
        EOR #&FF
        CLC
        ADC #1
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
        STA char_vy
        JMP mt_vout_done
 .mt_vout_wall_r
        LDA teleport_vn
        EOR #&FF
        CLC
        ADC #1
        STA char_vx
        LDA teleport_vt
        EOR #&FF
        CLC
        ADC #1
        STA char_vy
        JMP mt_vout_done
 .mt_vout_floor
        LDA teleport_vt
        STA char_vx
        LDA teleport_vn
        EOR #&FF
        CLC
        ADC #1
        STA char_vy
        JMP mt_vout_done
 .mt_vout_ceil
        LDA teleport_vt
        EOR #&FF
        CLC
        ADC #1
        STA char_vx
        LDA teleport_vn
        STA char_vy
 .mt_vout_done

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
        ; right wall => exit to left: x = portal_left_x - CHELL_W_PX - nudge
        LDA screen_ptr
        SEC
        SBC #(CHELL_W_PX+PORTAL_EXIT_NUDGE)
        BCS mt_x_store
        LDA #0
        JMP mt_x_store

 .mt_place_wall_l
        ; left wall => exit to right.
        ; Place Chell so her visible "nose" sits just outside the portal.
        LDA screen_ptr
        CLC
        ADC #((PORTAL_WALL_W_PX-1)+PORTAL_EXIT_NUDGE)
        SEC
        SBC #CHELL_NOSE_X_RIGHT
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
        ; - For wall/floor exits: round down to avoid pushing into nearby geometry.
        ; - For ceiling exits: round up so we don't snap upward into the ceiling.
        LDA row_counter
        CMP #PORTAL_ORIENT_CEIL
        BNE mt_quant_y_down
        LDA temp_y
        CLC
        ADC #7
        AND #&F8
        STA temp_y
        JMP mt_quant_y_clamp
 .mt_quant_y_down
        LDA temp_y
        AND #&F8
        STA temp_y
 .mt_quant_y_clamp
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
        BNE mt_face_store
 .mt_face_keep
        LDA last_anim_dir
 .mt_face_store
        STA anim_dir
        STA last_anim_dir

        ; Clear grounded state; preserve vertical velocity for now.
        LDA #0
        STA char_grounded

        ; Avoid immediate re-trigger / edge effects.
        LDA #0
        STA move_held
        STA last_move_held
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


; Try portal A. SEC => pending set.
.cpei_try_portal_a
        LDA portal_a_enabled
        BEQ cpei_a_no
        LDA portal_b_enabled
        BEQ cpei_a_no
        LDA portal_a_room
        CMP current_room
        BNE cpei_a_no

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
        BEQ cpei_a_no
        BMI cpei_a_no
        JMP cpei_a_intent_ok
 .cpei_a_need_vx_neg
        LDA char_vx
        BMI cpei_a_intent_ok
        JMP cpei_a_no
  .cpei_a_need_vy_pos
        LDA char_vy
        BNE cpei_a_vypos_have
        LDA char_prev_vy
   .cpei_a_vypos_have
        BEQ cpei_a_no
        BMI cpei_a_no
        JMP cpei_a_intent_ok
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
        BEQ cpei_b_no
        LDA portal_a_enabled
        BEQ cpei_b_no
        LDA portal_b_room
        CMP current_room
        BNE cpei_b_no

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
        BEQ cpei_b_no
        BMI cpei_b_no
        JMP cpei_b_intent_ok
 .cpei_b_need_vx_neg
        LDA char_vx
        BMI cpei_b_intent_ok
        JMP cpei_b_no
  .cpei_b_need_vy_pos
        LDA char_vy
        BNE cpei_b_vypos_have
        LDA char_prev_vy
   .cpei_b_vypos_have
        BEQ cpei_b_no
        BMI cpei_b_no
        JMP cpei_b_intent_ok
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
        ; For wall-left, the portal pixels live in the right half of the 16px stamp,
        ; so the collision rect starts at +8px.
        CMP #PORTAL_ORIENT_WALL_L
        BNE cpei_overlap_wall_x_ok
        CPX #15
        BEQ cpei_overlap_wall_x_ok
        INX
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
    ; Update reticle_state from portalability (no LOS yet).
    ;
    ; In the side-on platform view:
    ; - Floor/ceiling portals are 16x16 pixels (2 tiles wide x 1 tile tall)
    ; - Wall portals are 8x32 pixels (1 tile wide x 2 tiles tall)
    ; - Back-wall portals are 16x32 pixels (2 tiles wide x 2 tiles tall)
    ;
    ; Rules (current):
    ; - Floor: two adjacent tiles must both be ╥ (tile id 2)
    ; - Ceiling: two adjacent tiles must both be ╨ (tile id 4)
    ; - Wall: two stacked tiles must both be ╢ (tile id 3) or both be ╟ (tile id 5)
    ;   (we accept either the left or right 8px column within the 16px portal cell)

    ; tile_x0 = reticle_cell_x (top-left)
    LDA reticle_cell_x
    STA col_counter
    ; tile_x1 = tile_x0 + 1
    CLC
    ADC #1
    STA row_counter

    ; -------- Floor / ceiling test (2x1) --------
    ; idx0 = times16_table[y] + tile_x0
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
    BNE reticle_try_wall

    ; Must be floor or ceiling face.
    LDA temp
    CMP #2
    BEQ reticle_floor_ceiling_match
    CMP #4
    BEQ reticle_floor_ceiling_match
    JMP reticle_try_wall

  .reticle_floor_ceiling_match
    LDA #1
    STA reticle_debug_reason
    ; Orient from tile type: 2=floor face, 4=ceiling face
    LDA temp
    CMP #4
    BEQ reticle_is_ceiling
    LDA #PORTAL_ORIENT_FLOOR
    BNE reticle_fc_orient_done
  .reticle_is_ceiling
    LDA #PORTAL_ORIENT_CEIL
  .reticle_fc_orient_done
    STA reticle_wall_orient
    JMP reticle_set_green

    ; -------- Wall test (1x2) --------
  .reticle_try_wall
    ; Need 2 tiles height.
    LDA reticle_cell_y
    CMP #15
    BNE reticle_wall_height_ok
    JMP reticle_set_blocked
  .reticle_wall_height_ok

    ; Try left column: (tile_x0, y) and (tile_x0, y+1)
    LDY reticle_cell_y
    LDA times16_table,Y
    CLC
    ADC col_counter
    TAY
    LDA (tilemap_ptr),Y
    STA temp

    ; temp must be 3 (╢) or 5 (╟)
    CMP #3
    BEQ wall_left_ok_type
    CMP #5
    BNE reticle_try_wall_right
  .wall_left_ok_type

    ; Compare with below tile.
    LDY reticle_cell_y
    INY
    LDA times16_table,Y
    CLC
    ADC col_counter
    TAY
    LDA (tilemap_ptr),Y
    CMP temp
    BNE reticle_try_wall_right
     LDA #2
     STA reticle_debug_reason
     ; temp is tile type (3=left wall, 5=right wall)
     LDA temp
     CMP #5
     BNE wall_left_is_left
     LDA #1
     BNE wall_left_orient_done
   .wall_left_is_left
     LDA #0
   .wall_left_orient_done
     STA reticle_wall_orient
      JMP reticle_set_green

  .reticle_try_wall_right
    ; Try right column: (tile_x1, y) and (tile_x1, y+1)
    LDY reticle_cell_y
    LDA times16_table,Y
    CLC
    ADC row_counter
    TAY
    LDA (tilemap_ptr),Y
    STA temp

    CMP #3
    BEQ wall_right_ok_type
    CMP #5
    BEQ wall_right_ok_type
    JMP reticle_try_backwall
  .wall_right_ok_type

    LDY reticle_cell_y
    INY
    LDA times16_table,Y
    CLC
    ADC row_counter
    TAY
    LDA (tilemap_ptr),Y
    CMP temp
    BNE reticle_try_backwall
      LDA #3
      STA reticle_debug_reason
      ; temp is tile type (3=left wall, 5=right wall)
      LDA temp
      CMP #5
      BNE wall_right_is_left
      LDA #1
      BNE wall_right_orient_done
    .wall_right_is_left
      LDA #0
    .wall_right_orient_done
      STA reticle_wall_orient
      JMP reticle_set_green

    ; -------- Back-wall test (2x2 empties) --------
    ; Back wall is represented by empty tiles (id 0).
    ; Requires a 2x2 empty space; the reticle indicates the centre point where
    ; the four tiles meet.

  .reticle_try_backwall
     ; Try top-left at (x0, y)
     JSR reticle_backwall_at_y
     BCC reticle_set_blocked
       LDA #4
       STA reticle_debug_reason
      LDA #PORTAL_ORIENT_BACK
      STA reticle_wall_orient
      JMP reticle_set_green

; Check back-wall portalability (2x2 empty) at current reticle_cell_y.
; Returns C=1 if tile(y,x0..x1) and tile(y+1,x0..x1) are all 0.
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
    BNE backwall_fail
    INY
    LDA (tilemap_ptr),Y
    BNE backwall_fail

    ; row y+1
    LDY reticle_cell_y
    INY
    LDA times16_table,Y
    CLC
    ADC col_counter
    TAY
    LDA (tilemap_ptr),Y
    BNE backwall_fail
    INY
    LDA (tilemap_ptr),Y
    BNE backwall_fail

    SEC
    RTS

  .backwall_fail
    CLC
    RTS

  .reticle_set_green
    ; Candidate surface match passed; now require line-of-sight.
    JSR reticle_check_los
    BCS reticle_set_green_now

    ; LOS blocked: keep the base reason but mark it with bit 7.
    LDA reticle_debug_reason
    ORA #&80
    STA reticle_debug_reason
    JMP reticle_set_blocked_los

  .reticle_set_green_now
    LDA reticle_state
    CMP #1
    BEQ reticle_done
    LDA #1
    STA reticle_state
    LDA #1
    STA temp_y
    JMP reticle_done

  ; Blocked due to LOS. Do not clear reticle_debug_reason (it already contains
  ; the base reason, possibly ORed with $80).
  .reticle_set_blocked_los
    LDA reticle_state
    BEQ reticle_done
    LDA #0
    STA reticle_state
    LDA #1
    STA temp_y
    JMP reticle_done

  .reticle_set_blocked
    LDA #0
    STA reticle_debug_reason
    STA reticle_wall_orient
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


; --- Reticle line-of-sight ---
;
; Returns C=1 if Chell can see the candidate portal target, else C=0.
; Uses the solid-tile plane (SOLID_TILE_PLANE) only.
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

    ; Compute ray target based on the chosen placement kind.
    LDA reticle_debug_reason
    AND #&7F
    BNE reticle_los_kind_ok
    CLC
    RTS
  .reticle_los_kind_ok
    CMP #1
    BEQ reticle_los_target_floor
    CMP #2
    BEQ reticle_los_target_wall_left
    CMP #3
    BEQ reticle_los_target_wall_right
    CMP #4
    BEQ reticle_los_target_backwall_y
    CMP #5
    BEQ reticle_los_target_backwall_yminus1
    JMP reticle_los_fail

  ; --- Floor/ceiling (2x1) ---
  .reticle_los_target_floor
    ; target_x = reticle_cell_x*8 + 8 (centre of 2-tile span)
    LDA reticle_cell_x
    ASL A
    ASL A
    ASL A
    CLC
    ADC #8
    STA los_x1

    ; Compute tile top Y = reticle_cell_y*16.
    LDA reticle_cell_y
    ASL A
    ASL A
    ASL A
    ASL A
    STA los_y1

    ; Choose the side of the solid tile that faces the shooter.
    ; If shooter is above tile centre -> aim just above the tile; else just below.
    CLC
    ADC #8              ; A = tile_top + 8 (centre)
    CMP los_y0
    BCC los_floor_shooter_below

    ; shooter above: y = tile_top - 1 (clamped)
    LDA los_y1
    BEQ los_floor_y_ok
    DEC los_y1
  .los_floor_y_ok
    JMP reticle_los_nudge_and_cast

  .los_floor_shooter_below
    ; shooter below: y = tile_top + 16
    LDA los_y1
    CLC
    ADC #16
    STA los_y1
    JMP reticle_los_nudge_and_cast

  ; --- Wall (1x2), left column ---
  .reticle_los_target_wall_left
    LDA reticle_cell_x
    JMP reticle_los_wall_common

  ; --- Wall (1x2), right column ---
  .reticle_los_target_wall_right
    LDA reticle_cell_x
    CLC
    ADC #1
  .reticle_los_wall_common
    ; A = wall tile_x
    ; Compute wall tile left pixel X = tile_x*8 in temp.
    STA temp
    ASL A
    ASL A
    ASL A
    STA los_x1           ; provisional: tile_left

    ; target_y = reticle_cell_y*16 + 16 (centre of 2-tile height)
    LDA reticle_cell_y
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC #16
    STA los_y1

    ; Choose the side of the solid tile that faces the shooter.
    ; If shooter is left of tile centre -> x = tile_left - 1, else x = tile_left + 8.
    LDA los_x1
    CLC
    ADC #4               ; tile centre X
    CMP los_x0
    BCC los_wall_shooter_right

    ; shooter left: x = tile_left - 1 (clamped)
    LDA los_x1
    BEQ los_wall_x_ok
    DEC los_x1
  .los_wall_x_ok
    JMP reticle_los_nudge_and_cast

  .los_wall_shooter_right
    ; shooter right: x = tile_left + 8
    LDA los_x1
    CLC
    ADC #8
    CMP #128
    BCC los_wall_right_ok
    LDA #127
  .los_wall_right_ok
    STA los_x1
    JMP reticle_los_nudge_and_cast

  ; --- Backwall (2x2 empty), at y ---
  .reticle_los_target_backwall_y
    LDA reticle_cell_y
    JMP reticle_los_backwall_common

  ; --- Backwall (2x2 empty), at y-1 ---
  .reticle_los_target_backwall_yminus1
    LDA reticle_cell_y
    BEQ reticle_los_fail
    SEC
    SBC #1
  .reticle_los_backwall_common
    ; Preserve effective tile_y (in A) before computing X.
    STA temp_y

    ; target_x = reticle_cell_x*8 + 8 (centre)
    LDA reticle_cell_x
    ASL A
    ASL A
    ASL A
    CLC
    ADC #8
    STA los_x1

    ; target_y = tile_y*16 + 16 (centre of 2-tile height)
    ; Restore effective tile_y.
    LDA temp_y
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC #16
    STA los_y1
    ; Back-wall target is on a tile join; nudge toward shooter to avoid
    ; boundary cases that can falsely hit solids.
    JMP reticle_los_nudge_and_cast

  ; Nudge target 1px toward the shooter (helps avoid grazing the destination wall).
  .reticle_los_nudge_and_cast
    ; Nudge X
    LDA los_x1
    CMP los_x0
    BEQ reticle_los_nudge_y
    BCC reticle_los_nudge_x_right
    ; target > shooter: move target left
    LDA los_x1
    BEQ reticle_los_nudge_y
    DEC los_x1
    JMP reticle_los_nudge_y
  .reticle_los_nudge_x_right
    ; target < shooter: move target right
    LDA los_x1
    CMP #127
    BEQ reticle_los_nudge_y
    INC los_x1

  .reticle_los_nudge_y
    ; Nudge Y
    LDA los_y1
    CMP los_y0
    BEQ reticle_los_cast
    BCC reticle_los_nudge_y_down
    ; target > shooter: move target up
    LDA los_y1
    BEQ reticle_los_cast
    DEC los_y1
    JMP reticle_los_cast
  .reticle_los_nudge_y_down
    ; target < shooter: move target down
    LDA los_y1
    CMP #255
    BEQ reticle_los_cast
    INC los_y1

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

    LDA SOLID_TILE_PLANE,Y
    BEQ los_tile_ok
    SEC
    RTS

  .los_tile_ok
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

 
; --- Input sampling ---
;
  ; keys_held bits (this repo conventions):
  ;   bit0: left        (Z or cursor left)
  ;   bit1: right       (X or cursor right)
  ;   bit2: jump        (RETURN)
  ;   bit3: reticle     (SHIFT held)
  ;   bit4: reticle up  (':' / cursor up)
  ;   bit5: reticle down('/' / cursor down)
  ;   bit6: portal A    ('A')
  ;   bit7: portal B    ('S')
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

      ; Portal A ('A')
      LDX #&BE            ; INKEY(-66) = 'A'
      JSR is_key_pressed
      BCC sample_no_portal_a
      LDA keys_held
      ORA #64
      STA keys_held
  .sample_no_portal_a

      ; Portal B ('S')
      LDX #&AE            ; INKEY(-82) = 'S'
      JSR is_key_pressed
      BCC sample_no_portal_b
      LDA keys_held
      ORA #&80
      STA keys_held
  .sample_no_portal_b
  
      ; keys_pressed = keys_held & ~keys_prev


    LDA keys_prev
    EOR #&FF
    AND keys_held
    STA keys_pressed

     ; Update previous snapshot for next frame.
     LDA keys_held
     STA keys_prev

       ; --- Action button (SPACE) ---
      ; Keep separate from keys_held (we've run out of bits).
      LDA action_held
      STA action_prev
      LDA #0
      STA action_held

      ; SPACE = INKEY(-99)
      LDX #&9D
      JSR is_key_pressed
      BCC sample_no_action
      LDA #1
      STA action_held
 .sample_no_action

       ; action_pressed = action_held & ~action_prev
       LDA action_prev
       EOR #&FF
       AND action_held
       STA action_pressed

      ; --- Portal placement requests (A/S) ---
      ; We latch the A/S key-down edges into portal_req so if the reticle is
      ; briefly not green on that exact frame, the placement still happens on the
      ; next green frame.
      ;
      ; portal_req is consumed/cancelled in reticle mode.

      ; If A just pressed, set request bit0.
      LDA keys_pressed
      AND #64
      BEQ sample_no_portal_req_a
      LDA portal_req
      ORA #&81
      STA portal_req
  .sample_no_portal_req_a

      ; If S just pressed, set request bit1.
      LDA keys_pressed
      AND #&80
      BEQ sample_no_portal_req_b
      LDA portal_req
      ORA #&82
      STA portal_req
  .sample_no_portal_req_b

      ; portal_req is sticky after a tap. It is cleared when:
      ; - the portal is successfully placed (consumed),
      ; - the reticle moves, or
      ; - reticle mode is exited.

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
 
INCLUDE "ui.asm"

INCLUDE "loaders.asm"

INCLUDE "room_runtime.asm"

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
