INCLUDE "oscalls.asm"

; Zero page variables.
;
; We call MOS routines (OSBYTE/OSWRCH/OSGBPB) during gameplay, so we must avoid
; MOS/VDU/Econet-owned ZP (&90..&FF). We keep our ZP allocations in the
; language-owned range (&00..&8F).
;
; Hard layout invariants relied on by hot paths:
; - screen_ptr  must be at &71
; - tilemap_ptr must be at &79
; - portalmap_ptr must be at &7B
;
ORG &70
.temp               SKIP 1    ; Temporary storage (must stay at &70)
.screen_ptr         SKIP 2    ; Current screen memory location (must stay at &71)
.sprite_ptr         SKIP 2    ; Pointer to current sprite data
.temp_y             SKIP 1    ; Temporary Y storage
.row_counter        SKIP 1    ; Row counter for loops
.col_counter        SKIP 1    ; Column counter for loops
.current_room       SKIP 1    ; Current room number (0=room1, 1=room2)
.tilemap_ptr        SKIP 2    ; Pointer to current room's tilemap data
.portalmap_ptr      SKIP 2    ; Pointer to current room's portalable tile layer
.mask_ptr           SKIP 2    ; Pointer to current mask data
.temp_sprite_ptr    SKIP 2    ; Temp sprite pointer for striped blit
.temp_mask_ptr      SKIP 2    ; Temp mask pointer for striped blit

; Remaining game state ZP (kept below &70).
ORG &00
.char_tile_pos      SKIP 1    ; Character cell position (cell_y*16 + cell_x)
.char_pixel_offset  SKIP 1    ; Subpixel offset (0..3)
.char_byte_offset   SKIP 1    ; Byte offset within cell (0 or 8)
.char_y_offset      SKIP 1    ; Vertical offset within cell row (0 or 8)
.char_vy            SKIP 1    ; Signed vy in 8px steps
.char_vx            SKIP 1    ; Signed vx in px/frame (used for portal intent + momentum)
.char_prev_vy       SKIP 1    ; Previous vy (for floor/ceiling entry on landing)
.char_grounded      SKIP 1    ; 0/1: standing on solid
.jump_timer         SKIP 1    ; Frames remaining in jump rise (0 = not jumping)
.peak_timer         SKIP 1    ; Frames remaining at jump apex (0 = not at peak)
.fall_distance      SKIP 1    ; 8px steps fallen (0 while grounded/rising)
.room_dirty         SKIP 1    ; 0/1: room background needs redraw
.objects_pending    SKIP 1    ; 0/1: persistent objects need restamp
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
.dirty_flag         SKIP 1    ; 0/1: needs redraw this frame

; ROMSEL/SWRAM bank state.
.chell_bank         SKIP 1    ; ROMSEL value for Chell SWRAM bank
.obj_bank           SKIP 1    ; ROMSEL value for Object SWRAM bank
.tile_bank          SKIP 1    ; ROMSEL value for tile data SWRAM bank
.saved_romsel       SKIP 1    ; Saved ROMSEL around OS calls

  ; Animation.
  .anim_frame              SKIP 1    ; Animation frame (0..3)
  .anim_dir                SKIP 1    ; Direction (0=left,1=right)
  .last_anim_dir           SKIP 1    ; Previous direction for redraw
  .move_held               SKIP 1    ; 0/1: left/right held this frame
  .last_move_held          SKIP 1    ; Previous move_held (for pose redraw)
  .anim_cooldown           SKIP 1    ; Movement counter for anim

  ; Horizontal step loop scratch (used by movement.asm).
  .hstep_rem               SKIP 1
  .hstep_moved             SKIP 1

  ; Cube + carry.
  .cube_tile_pos       SKIP 1
  .cube_byte_offset    SKIP 1
  .carried_cube_idx    SKIP 1
  .char_sprite_index   SKIP 1

  ; Precomputed render decisions for Chell (computed in update; used in render).
  .chell_new_ptr       SKIP 2
  .chell_body_index    SKIP 1
  .chell_overlay_index SKIP 1
  .chell_air_pose      SKIP 1    ; 0=jump/neutral airborne, 1=fall (committed descent)
  .last_aim_held       SKIP 1

  ; Reticle state.
  .reticle_cell_x      SKIP 1
  .reticle_cell_y      SKIP 1
  .reticle_state       SKIP 1
  .reticle_active      SKIP 1
  .reticle_prev_active SKIP 1
  .reticle_move_cd     SKIP 1
  .reticle_wall_orient SKIP 1

  .exit_dst            SKIP 1
  .chell_dirty         SKIP 1
  .reticle_dirty       SKIP 1

  .chell_prev_ptr      SKIP 2
  .reticle_prev_ptr    SKIP 2
  .chell_has_under     SKIP 1
  .reticle_has_under   SKIP 1

  .reticle_debug_reason SKIP 1

  ; Portal stamping (partial redraw) state.
  .portal_pending      SKIP 1
  .portal_kind         SKIP 1
  .portal_old_x        SKIP 1
  .portal_old_y        SKIP 1
  .portal_old_room     SKIP 1
  .portal_old_enabled  SKIP 1
  .portal_old_orient   SKIP 1

  ; Portal instances.
  .portal_a_enabled    SKIP 1
  .portal_a_room       SKIP 1
  .portal_a_x          SKIP 1
  .portal_a_y          SKIP 1
  .portal_a_orient     SKIP 1
  .portal_b_enabled    SKIP 1
  .portal_b_room       SKIP 1
  .portal_b_x          SKIP 1
  .portal_b_y          SKIP 1
  .portal_b_orient     SKIP 1

  ; Portal teleportation.
  .teleport_pending    SKIP 1
  .teleport_entry_kind SKIP 1
  .teleport_cooldown   SKIP 1
  .teleport_exit_room  SKIP 1
  .teleport_exit_x     SKIP 1
  .teleport_exit_y     SKIP 1
  .teleport_exit_orient SKIP 1
  .teleport_vt         SKIP 1
  .teleport_vn         SKIP 1
  .teleport_last_exit_kind SKIP 1

  ; LOS scratch.
  .los_x0        SKIP 1
  .los_y0        SKIP 1
  .los_x1        SKIP 1
  .los_y1        SKIP 1
  .los_dx        SKIP 1
  .los_dy        SKIP 1
  .los_err       SKIP 1
  .los_steps     SKIP 1
  .los_sx        SKIP 1
  .los_sy        SKIP 1
  .los_prev_tile SKIP 1

  ; Quick-shot scratch.
  .shot_hit_tilepos SKIP 1

  ; Global sim pacing.
  ; 0/1 toggled each frame; when 0 we run gameplay update.
  .sim_phase            SKIP 1

  ; Debug flags.
  ; bit0: show debug boxes for sprite footprints.
  .debug_flags          SKIP 1

  .char_dead            SKIP 1    ; 0=alive, 1=dead (waiting for keypress)
  .current_level        SKIP 1    ; 0-indexed level number (0..LEVEL_COUNT-1)

  ; Fizzler region state (per-room).
  .room_fizzler_count   SKIP 1    ; fizzlers in current room (0..4)
  .room_fizzler_ptr     SKIP 2    ; pointer to current room's fizzler_defs data

 ORG &1900


CRTC_ADDR = &FE00
CRTC_DATA = &FE01
ROMSEL    = &FE30          ; Master paged ROM/SWRAM bank select
ACCCON    = &FE34          ; Master ACCCON register (D=display, E=VDU, X=CPU shadow)

CHELL_SWRAM_BANK_DEFAULT = 4
CHELLDATA_BUF         = &7B00  ; Temp buffer in screen scratch

; Object (portal stamp) sprite+mask data lives in sideways RAM.
OBJ_SWRAM_BANK_DEFAULT = 5

; Tile bitmap data lives in sideways RAM bank 6.
TILE_SWRAM_BANK_DEFAULT = 6


FALL_POSE_VY_THRESHOLD       = 2      ; switch to falling pose after 2+ fall steps (not immediately)
JUMP_RISE_FRAMES             = 5      ; frames of 8px upward movement per jump (40px rise)
JUMP_PEAK_FRAMES             = 2      ; frames of hang time at apex before falling
FALL_FAST_THRESHOLD          = 12     ; 8px steps before fast-fall kicks in (6 tiles)
TERMINAL_VELOCITY_DOWN      = 6      ; max falling speed (8px steps)
TERMINAL_VELOCITY_UP        = &FA    ; -6: max rising speed (8px steps)
TERMINAL_VELOCITY_X         = 12     ; max |vx| (px/frame), also per-frame step clamp
WALK_VELOCITY               = 2      ; |vx| while walking / air-control (px/update)

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

; Tile id for the special "backwall portal surface".
; Back-wall portals may only be placed onto 2x2 regions of this tile.
TILE_BACKWALL_PORTAL         = 29

; Tile ids for tile-backed objects (from reordered tileset).
TILE_PAD_UP_L                 = 49
TILE_PAD_UP_R                 = 50
TILE_PAD_DOWN_L               = 51
TILE_PAD_DOWN_R               = 52
TILE_BUTTON_UP                = 1
TILE_BUTTON_DOWN              = 2
TILE_EXIT_CLOSED_TL           = 3
TILE_EXIT_CLOSED_TR           = 4
TILE_EXIT_CLOSED_BL           = 5
TILE_EXIT_CLOSED_BR           = 6
TILE_EXIT_OPEN_TL             = 7
TILE_EXIT_OPEN_TR             = 8
TILE_EXIT_OPEN_BL             = 9
TILE_EXIT_OPEN_BR             = 10
TILE_BARRIER_OPEN_L           = 54
TILE_BARRIER_OPEN_R           = 55
TILE_BARRIER_CLOSED_L         = 30
TILE_BARRIER_CLOSED_R         = 31

; Overlay sprite indices (overlay_sprite_table).
CHELL_OVERLAY_CARRY_RIGHT_BASE = 24
CHELL_OVERLAY_CARRY_LEFT_BASE  = 28

; Persistent gameplay object type IDs (from tools/gen-level output).
OBJ_TYPE_CUBE                = 1
OBJ_TYPE_BUTTON              = 2
OBJ_TYPE_PAD                 = 3
OBJ_TYPE_EXIT                = 4
OBJ_TYPE_SPAWNER             = 5
OBJ_TYPE_BARRIER             = 6

; Hazard tile IDs. Touching any of these kills Chell.
TILE_ACID                    = 11

; Beam direction constants (beam travel direction).
BEAM_DIR_LEFT                = 0
BEAM_DIR_RIGHT               = 1
BEAM_DIR_UP                  = 2
BEAM_DIR_DOWN                = 3

; Laser beam tile IDs (from tileset).
TILE_BEAM_V                  = 15
TILE_BEAM_H                  = 16
TILE_BEAM_V_BACK             = 17
TILE_BEAM_H_BACK             = 18
TILE_CROSSROADS              = 27
TILE_CROSSROADS_BACK         = 28
TILE_PORTALABLE_BACK         = 29

CHELL_W_PX                   = 16
CHELL_H_PX                   = 32

; Approx visible bounds (used for portal exit placement).
; When facing right, Chell's visible "nose" is around x+10 (see will_collide_right).
CHELL_NOSE_X_RIGHT          = 10
CHELL_NOSE_X_LEFT           = 3

CHELL_RUN_LEFT_BASE         = 12
CHELL_IDLE_RIGHT_BASE       = 24
CHELL_IDLE_LEFT_BASE        = 28
CHELL_JUMP_RIGHT_BASE       = 32
CHELL_JUMP_LEFT_BASE        = 36
CHELL_FALL_RIGHT_BASE       = 40
CHELL_FALL_LEFT_BASE        = 44

; Dead Chell sprite (single frame, no subpixel or direction variants).
CHELL_DEAD_BASE              = 48

.entry
    ; One-time start screen (before any MODE 5 setup).
    JSR show_start_screen

    ; Initialize level counter.
    LDA #0
    STA current_level

    ; Fall through to start_level.

.start_level
    ; Load the current level's header block into the active buffer.
    JSR load_level

    ; Show MODE 7 "Test Chamber XX" title card.
    JSR show_level_card

    ; Fall through to .start which handles full MODE 5 hardware init.

.start
    ; NOTE: MODE 5 is set by the boot loader (PROGRAM) before loading the
    ; game binary.  We must NOT call MODE 5 here because the VDU screen
    ; clear would destroy code/data in MAIN RAM at &5800+ (our code blob
    ; extends past the MODE 5 screen start at &5800).
    ;
    ; restore_mode5 (called by screen routines above) sets Video ULA +
    ; CRTC screen start. The code below completes the MODE 5 setup.

    ; Disable the blinking text cursor (it writes into screen RAM).
    JSR disable_cursor

    ; Rebuild bit_table in case MOS screen operations (cursor flash, VDU
    ; output during boot) corrupted MAIN RAM in the &5800+ screen region.
    LDX #0
    LDA #1
.rebuild_bit_table
    STA bit_table,X
    ASL A
    INX
    CPX #8
    BNE rebuild_bit_table

    ; Remap logical colours to physical palette:
    ; 0=black, 1=red, 2=cyan, 3=yellow
    JSR set_palette


    ; Disable MOS ESCAPE key processing so it doesn't set the escape condition.
    LDA #229
    LDX #1
    LDY #0
    JSR OSBYTE

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

    ; Sideways RAM sprite banks are loaded by PROGRAM at boot.
    ; PROGRAM also writes `chell_bank`/`obj_bank` (ROMSEL values) into ZP.

    ; Enable shadow screen (Master).
    ; Writes ACCCON directly to set D=1 (CRTC displays LYNNE).
    JSR enable_shadow_acccon

    ; First-time init: ensure beam list is empty before first restart.
    LDA #0
    STA beam_tile_count

  .restart_level
    ; Restore any dynamic beam tiles to old room's tilemap before switching.
    ; (tilemap_ptr still points to previous room; beam_do_redraw=0 since screen
    ; will be fully redrawn.)
    LDA #0
    STA beam_do_redraw
    JSR unstamp_beam_tiles
    ; Clear the shadow screen before redrawing.
    JSR clear_lynne_screen

    ; Select the level-defined start room (from active buffer).
    LDA level_start_room_buf
    STA current_room
    JSR set_room_tilemap
    JSR set_room_portalmap
    JSR set_room_fizzlers

    ; Initialize level-global object state from generated tables.
    JSR init_persistent_objects
    JSR init_beams

    ; Place Chell at the level-defined start tile (from active buffer).
    LDA level_start_pos_buf
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
    STA jump_timer
    STA peak_timer
    STA fall_distance
    STA room_dirty
    STA objects_pending
    STA exit_cooldown
    STA exit_probe0
    STA exit_probe1
    STA keys_held
    STA keys_pressed
    STA keys_prev
    STA action_held
    STA action_prev
     STA action_pressed
    STA anim_frame
    STA move_held
    STA last_move_held
    STA anim_cooldown
    STA chell_body_index
    STA chell_overlay_index
    STA chell_air_pose
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
      STA carried_cube_idx

      ; Clear debug/temporary state.
       LDA #0
       STA debug_flags
       STA sim_phase
       STA char_dead

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
        JSR debug_draw_chell_box

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
        ; Consume the pending redraw request so we don't re-render on skipped sim frames.
        LDA #0
        STA dirty_flag
  .main_skip_render

         ; Sample input once per frame.
         JSR sample_keys

         ; ESCAPE restarts the level.
         LDX #&8F            ; INKEY(-113) = ESCAPE
         JSR is_key_pressed
         BCC no_restart
         JMP restart_level
       .no_restart

         ; Cheat: L skips to next level.
         LDX #&A9            ; INKEY(-87) = 'L'
         JSR is_key_pressed
         BCC no_skip_level
         JMP advance_level
       .no_skip_level

         ; Slow-motion pacing: update gameplay every other frame (50% speed).
         LDA sim_phase
         BNE main_skip_update
         JSR update_chell

   .main_skip_update
         LDA sim_phase
         EOR #1
         STA sim_phase
         JMP main_loop


 ; --- Level advance (called when player enters open exit) ---
 .advance_level
    INC current_level
    LDA current_level
    CMP #LEVEL_COUNT
    BCC al_not_done
    ; All levels complete — show completion screen, restart from level 0.
    JSR show_complete_screen
    LDA #0
    STA current_level
 .al_not_done
    JMP start_level

 ; --- Render (incremental frame) ---
 ; Uses chell_dirty/reticle_dirty computed in the previous update.
 ; Reticle redraw condition includes chell_dirty because Chell can move under it.
 .render_frame_simple
        ; Optional debug feedback: palette flash (currently disabled).
        ; JSR palette_flash_update

        ; Room transition: redraw background first.
        LDA room_dirty
        BEQ render_no_room_redraw
        JSR set_room_tilemap
        JSR set_room_portalmap
        JSR set_room_fizzlers
        LDA #0
        STA beam_do_redraw
        JSR retrace_all_beams
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

        ; Persistent object visual changes: we will patch the background.
        ; Force sprites to redraw so save-under captures the updated BG.
        LDA objects_pending
        BEQ render_no_obj_force
        LDA #1
        STA chell_dirty
        LDA reticle_active
        BEQ render_no_obj_force
        LDA #1
        STA reticle_dirty
  .render_no_obj_force

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
        JSR apply_pending_portal_update

        ; If persistent objects changed visually, patch and restamp them now.
        JSR apply_pending_object_updates

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
        JSR debug_draw_chell_box

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
         JSR debug_draw_reticle_box

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

       ; Death state: freeze gameplay, wait for any new keypress to restart.
       LDA char_dead
       BEQ uc_alive

       ; Any new keypress or action press restarts the level.
       LDA keys_pressed
       ORA action_pressed
       BEQ uc_dead_wait
       JMP restart_level
     .uc_dead_wait
       ; Clear consumed inputs and compute dirty flag.
       LDA #0
       STA keys_pressed
       STA action_pressed
       JSR compute_dirty_flag
       RTS

     .uc_alive
       ; Reticle mode vs normal mode.
       JSR maybe_update_reticle_mode
       BCS update_finish
       JSR update_normal_mode

       ; Hazard check: acid/goo kills Chell on contact.
       JSR check_acid_death

       ; Fizzler contact: clears portals and drops carried cube.
       JSR check_fizzler_contact

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

        ; Cube pickup/drop runs after portal entry so SPACE prioritises
        ; back-wall portal entry over cube drop.  maybe_teleport clears
        ; action_pressed when it fires, preventing an unwanted drop.
        JSR handle_cube_pickup_drop

        ; Room exits (screen transitions).
        JSR check_room_exits

        ; Exit object entered? (SPACE on open exit → advance level)
        JSR check_exit_entered
        BCC update_finish_no_gameplay
        JMP advance_level

  .update_finish_no_gameplay

         ; Update persistent objects + channel signals (pads/buttons -> exits).
         ; Signals must run every frame so spawners fire immediately when
         ; a beam hits a target (even while reticle mode is still active).
         JSR update_signals_and_object_states

         ; Cube physics runs in the shared path so cubes fall even while
         ; reticle mode is active (update_normal_mode is skipped then).
         JSR update_cubes_physics

        ; While in reticle mode we ignore aim-based redraws.
        LDA reticle_active
        BNE aim_change_done

        ; Aim changes should trigger redraw while grounded (overlay changes).
        LDA char_grounded
        BEQ aim_change_done
        LDA aim_held
        CMP last_aim_held
        BEQ aim_change_done
        LDA #1
        STA chell_dirty
 .aim_change_done
        LDA aim_held
        STA last_aim_held

        ; Clear latched edge inputs now that update consumed them.
        LDA #0
        STA keys_pressed
        STA action_pressed

        ; Precompute Chell render decisions for next frame.
        LDA chell_dirty
        BEQ skip_precompute
        JSR compute_chell_render_state
 .skip_precompute

        JSR compute_dirty_flag
        RTS


; === Render-safe zone: visible when X=0 or X=1 ===
INCLUDE "render.asm"
INCLUDE "render_state.asm"
INCLUDE "room_runtime.asm"
INCLUDE "debug.asm"
INCLUDE "lookup_tables.asm"
INCLUDE "sprites.asm"
INCLUDE "masks.asm"
; === End render-safe zone ===

; === Update-only zone: visible only when X=0 ===
INCLUDE "portal_teleport.asm"
INCLUDE "room_exits.asm"
INCLUDE "reticle.asm"
INCLUDE "input.asm"
INCLUDE "portal_place.asm"
INCLUDE "frame_update.asm"
INCLUDE "persistent_objects.asm"
INCLUDE "ui.asm"
INCLUDE "screens.asm"
INCLUDE "loaders.asm"
INCLUDE "timing.asm"
INCLUDE "movement.asm"
INCLUDE "laser.asm"
INCLUDE "tilemap.asm"
INCLUDE "objects.asm"
INCLUDE "persistent_objects_data.asm"

.end

SAVE "PORTHLE", entry, end

; Boot loader (PROGRAM) is a small machine-code binary.
; !Boot runs: *BASIC then *RUN PROGRAM.

CLEAR &0E00, &1900
ORG &0E00
.program_start
INCLUDE "boot_loader.asm"
.program_end
SAVE "PROGRAM", program_start, program_end

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

; Tile bitmap data for sideways RAM bank 6.
; Room tile sprites (8x16 cells), generated from `sprites/NewTiles - Grid.csv`.
; Labels (sprite_table etc.) are global and resolve to &8000+offset.
CLEAR &8000, &C000
ORG &8000
.tiledata_start
INCLUDE "sprites/generated_tiles.asm"

; Pad to full 16KB SWRAM bank.
ORG &C000
.tiledata_end
SAVE "TILDAT", tiledata_start, tiledata_end

; Loading screen (MODE 2) file.
;
; Binary is generated at build-time into .tmp/loadscr_mode2.bin.
; It is laid out as MODE 2 screen memory (20KB) and is intended to be
; *LOADed to &3000 from BASIC during boot.

CLEAR &3000, &8000
ORG &3000
.loadscr_start
INCBIN ".tmp/loadscr_mode2.bin"
.loadscr_end
SAVE "LOADSCR", loadscr_start, loadscr_end

; Start screen (MODE 7) — raw 1000-byte teletext screen.
; Loaded at runtime by show_start_screen via OSFILE to &7C00.

CLEAR &7C00, &8000
ORG &7C00
.strtscr_start
INCBIN "P8FF-3F7F"
.strtscr_end
SAVE "STRTSCR", strtscr_start, strtscr_end

; Level card template — raw 1000-byte MODE 7 screen (Aperture logo + yellow area).
; Loaded at runtime by show_level_card via OSFILE to &7C00.
PUTFILE "TEMPLATE", "TEMPLTE", &7C00, &7C00
