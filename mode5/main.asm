INCLUDE "shared/oscalls.asm"

; Zero page variables.
;
; We call MOS routines (OSBYTE/OSWRCH/OSGBPB) during gameplay, so we must avoid
; MOS/VDU/Econet-owned ZP (&90..&FF). We keep our ZP allocations in the
; language-owned range (&00..&8F).
;
; Hard layout invariants relied on by hot paths:
; - screen_ptr  must be at &71
; - tilemap_ptr must be at &79
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
.level_bank         SKIP 1    ; ROMSEL value for level pack SWRAM bank
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

  .portal_rise_timer    SKIP 1    ; Frames of portal-launch rise remaining (0 = inactive)
  .char_prev_fall_dist  SKIP 1    ; fall_distance snapshot for portal momentum

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
; Music player: only the three voice track pointers need zero page
; (read via (ptr),Y). &83-&8F is the free ZP window; this takes &83-&88 and
; leaves &89-&8F. The player's other 11 bytes are absolute (MUSIC_VAR_BASE).
; Build switch: set FALSE to omit all music and sound-effect calls, for
; bisecting audio against the rest of the build. The code is still assembled;
; only the call sites are suppressed.
ENABLE_AUDIO = TRUE
ENABLE_MUSIC      = TRUE     ; music init (envelopes + track pointers)
ENABLE_MUSIC_TICK = TRUE     ; per-frame tick + Q toggle
ENABLE_SFX   = TRUE      ; sound effects: queue + service

; Sound-effect request slot. MUST be zero page: effects are triggered from
; rendering code, which runs with ACCCON X=1 (LYNNE mapped over &3000-&7FFF).
; sound_block lives at &72xx, inside that window, so touching it from a render
; path would write to screen memory instead of RAM. Zero page is never shadowed,
; so trigger sites only ever store here and the main loop does the real work.
SFX_PENDING = &89           ; &FF = nothing queued
TRACE = &8F                 ; free debug breadcrumb byte (unused; see git log for the envelope/trampoline bug)

MUSIC_ZP_BASE = &83

TILE_SWRAM_BANK_DEFAULT = 6

; Level pack data lives in sideways RAM bank 7.
LEVEL_SWRAM_BANK_DEFAULT = 7


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
TILE_BARRIER_OPEN_T           = 30
TILE_BARRIER_OPEN_B           = 31
TILE_BARRIER_CLOSED_T         = 54
TILE_BARRIER_CLOSED_M         = 55
TILE_BARRIER_CLOSED_B         = 56

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
OBJ_TYPE_SENTRY              = 7
OBJ_TYPE_ZAPPER              = 8

; Sentry direction flag stored in obj_state bit 0.
SENTRY_DIR_LEFT              = 1
SENTRY_STATE_DISABLED        = 2

; Zapper tile IDs.
TILE_ZAPPER_LEFT_ON          = 57
TILE_ZAPPER_MID_ON           = 58
TILE_ZAPPER_RIGHT_ON         = 59
TILE_ZAPPER_LEFT_OFF         = 60
TILE_ZAPPER_RIGHT_OFF        = 61
TILE_LASER_ZAPPER_DOWN       = 62
TILE_LASER_ZAPPER_UP         = 63

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

    ; Show MODE 5 "Test Chamber XX" title card (Aperture logo on cyan).
    JSR show_level_card

    ; Fall through to .start which handles full MODE 5 hardware init.

.start
    ; NOTE: MODE 5 is set by the boot loader (PROGRAM) before loading the
    ; game binary.  We must NOT call MODE 5 here because the VDU screen
    ; clear would destroy code/data in MAIN RAM at &5800+ (our code blob
    ; extends past the MODE 5 screen start at &5800).
    ;
    ; show_level_card stays in MODE 5 (no mode switch). show_start_screen
    ; uses MODE 7 and restore_mode5 sets Video ULA + CRTC screen start.
    ; The code below completes the MODE 5 setup.

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

    ; Start the music (envelopes + track pointers).
IF ENABLE_AUDIO AND ENABLE_MUSIC
    JSR music_start_playing
ENDIF
IF ENABLE_AUDIO AND ENABLE_SFX
    JSR sfx_init
ENDIF

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
    JSR set_room_fizzlers

    ; Initialize level-global object state from generated tables.
    JSR init_persistent_objects
    JSR init_beams
    JSR spark_level_reset

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
    STA portal_rise_timer
    STA room_dirty
    STA bullet_count
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
    JSR spark_arm
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

       JSR save_and_draw_character_current
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

        ; Music runs at frame rate; the player itself only does work on
        ; every 5th frame (50Hz -> 20Hz scheduler).
IF ENABLE_AUDIO AND ENABLE_MUSIC AND ENABLE_MUSIC_TICK
        JSR music_frame_tick
ENDIF
IF ENABLE_AUDIO AND ENABLE_SFX
        JSR sfx_service
ENDIF

       ; Render previous frame immediately after VSYNC.
       ; Incremental: redraw only what changed (Chell + reticle).
       ; Force render when sentry bullets are on screen.
        LDA bullet_count
        BEQ main_no_bullet_force
        LDA #1 : STA dirty_flag
   .main_no_bullet_force
        ; A visible spark moves every frame, so it always needs a redraw.
        ; A spark off in another room does not -- forcing a render for it
        ; would put Chell through a needless peel/redraw every frame.
        LDA spark_has_under
        BNE main_spark_force
        LDA spark_active
        BEQ main_no_spark_force
        LDA spark_room
        CMP current_room
        BNE main_no_spark_force
   .main_spark_force
        LDA #1 : STA dirty_flag
   .main_no_spark_force
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

 ; --- Pre-vsync background patch ---
 ; Applies heavy background updates (portal placement, object tile changes,
 ; beam retracing) BEFORE vsync, outside the critical post-vsync window.
 ; When updates are pending, restores sprite unders first so the background
 ; patch doesn't write over stale save-under data.
 ; Called at the end of update_chell, after compute_chell_render_state.
 .pre_render_bg_patch
        LDA portal_pending
        ORA objects_pending
        BNE prbp_has_work
        RTS

   .prbp_has_work
        ; Peel the spark first -- it is drawn last, so it sits on top of
        ; both the reticle and Chell.  This also drops its save-under,
        ; which the background patch below would otherwise make stale.
        JSR spark_restore_under

        ; Restore reticle under next (LIFO peel — reticle drawn last, restored first).
        LDA reticle_has_under
        BEQ prbp_skip_restore_reticle
        JSR restore_reticle_under
        LDA #0
        STA reticle_has_under
   .prbp_skip_restore_reticle

        ; Restore Chell under.
        LDA chell_has_under
        BEQ prbp_skip_restore_chell
        JSR restore_chell_under
        LDA #0
        STA chell_has_under
   .prbp_skip_restore_chell

        ; Now the background is clean — apply portal and object tile patches.
        JSR apply_pending_portal_update
        JSR apply_pending_object_updates

        RTS


 ; --- Render (incremental frame, post-vsync blit only) ---
 ; After the pre-vsync pass has handled heavy background work, this routine
 ; only does: restore sprite unders -> save new unders -> draw sprites.
 ; This keeps the post-vsync critical window as short as possible.
 .render_frame_simple
        ; Optional debug feedback: palette flash (currently disabled).
        ; JSR palette_flash_update

        ; Room transition: redraw background first.
        LDA room_dirty
        BEQ render_no_room_redraw
        JSR set_room_tilemap
        JSR set_room_fizzlers
        LDA #0
        STA beam_do_redraw
        JSR retrace_all_beams
        JSR render_tilemap
        JSR spark_arm
        JSR render_static_objects
        JSR stamp_portals_for_current_room
        JSR render_persistent_objects_current_room
        LDA #0
        STA room_dirty
        STA chell_has_under
        STA reticle_has_under
        STA spark_has_under
        STA bullet_count

        ; Background redraw wipes sprites; force them to re-save-under and redraw.
        LDA #1
        STA chell_dirty
        LDA reticle_active
        BEQ render_no_room_redraw
        LDA #1
        STA reticle_dirty

   .render_no_room_redraw
        ; Sentry bullets: force full sprite cycle when bullets are active,
        ; then erase old bullets so save-under captures clean background.
        LDA bullet_count
        BEQ render_no_bullet_erase
        LDA #1 : STA chell_dirty
        LDA reticle_active
        BEQ render_bullet_erase
        STA reticle_dirty
   .render_bullet_erase
        JSR erase_sentry_bullets
   .render_no_bullet_erase

        ; Peel the spark before the reticle and Chell -- it is drawn last,
        ; so LIFO order restores it first.  Unconditional: it no-ops when
        ; there is nothing saved.
        JSR spark_restore_under

        ; Portal/object background patches are now handled pre-vsync in
        ; pre_render_bg_patch (called at end of update_chell), so the
        ; post-vsync window only does sprite restore/save/draw.

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
        ; Portal/object background patches already applied pre-vsync.

        ; Fall through to sprite draw.

 .render_draw_maybe
       ; Draw Chell if dirty.
       LDA chell_dirty
       BEQ render_draw_reticle_maybe

       ; screen_ptr := precomputed new pointer
       LDA chell_new_ptr
       STA screen_ptr
       LDA chell_new_ptr+1
       STA screen_ptr+1
        JSR save_and_draw_character_current
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
       JSR draw_sentry_bullets
       JSR spark_draw
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

       ; Sentry killzone check: active sentries kill Chell in their LOS.
       JSR check_killzones

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

        ; If SPACE is over a button, suppress pickup/drop on the same edge
        ; but leave the action latched so the button logic can still see it.
        JSR consume_button_press_if_overlapping
        BCS update_after_cube_pickup_drop

        ; Cube pickup/drop runs after portal entry so SPACE prioritises
        ; back-wall portal entry over cube drop.  maybe_teleport clears
        ; action_pressed when it fires, preventing an unwanted drop.
        JSR handle_cube_pickup_drop
  .update_after_cube_pickup_drop

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
         JSR check_offscreen_cube_portals
         JSR check_sentry_collisions

         ; Spark runs with cube physics rather than under the frozen-time
         ; branch: if it stopped while the reticle is up, the player could
         ; freeze time to re-aim mid-flight and the timing puzzle vanishes.
         JSR spark_update
         JSR spark_check_chell

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

        ; If portal or object changes are pending, force chell + reticle dirty
        ; so their save-under captures the updated background.
        LDA portal_pending
        ORA objects_pending
        BEQ no_bg_dirty_force
        LDA #1
        STA chell_dirty
        LDA reticle_active
        BEQ no_bg_dirty_force
        LDA #1
        STA reticle_dirty
 .no_bg_dirty_force

        ; Precompute Chell render decisions for next frame.
        LDA chell_dirty
        BEQ skip_precompute
        JSR compute_chell_render_state
 .skip_precompute

        ; Pre-vsync background patch: apply heavy portal/object updates now,
        ; outside the critical post-vsync window.  This restores sprite unders
        ; first so the background patch doesn't corrupt stale save-under data.
        JSR pre_render_bg_patch

        JSR compute_dirty_flag
        RTS


; === Render-safe zone: visible when X=0 or X=1 ===
INCLUDE "mode5/render.asm"
INCLUDE "mode5/render_state.asm"
INCLUDE "mode5/room_runtime.asm"
INCLUDE "mode5/debug.asm"
INCLUDE "mode5/lookup_tables.asm"
INCLUDE "mode5/sprites.asm"
INCLUDE "mode5/masks.asm"
; === End render-safe zone ===

; === Update-only zone: visible only when X=0 ===
INCLUDE "shared/portal_teleport.asm"
INCLUDE "shared/room_exits.asm"
INCLUDE "shared/reticle.asm"
INCLUDE "shared/input.asm"
INCLUDE "shared/portal_place.asm"
INCLUDE "shared/frame_update.asm"
INCLUDE "shared/persistent_objects.asm"
INCLUDE "mode5/ui.asm"
INCLUDE "mode5/screens.asm"
INCLUDE "mode5/loaders.asm"
INCLUDE "shared/timing.asm"
INCLUDE "shared/movement.asm"
INCLUDE "shared/laser.asm"
INCLUDE "shared/spark.asm"
INCLUDE "shared/tilemap.asm"
INCLUDE "shared/objects.asm"
INCLUDE "shared/persistent_objects_data.asm"

; --- Music ---
; Player code and its absolute state live in main RAM; the song event streams
; live in SWRAM bank 6 at &A000 (see the TILDAT block below), so the tick must
; run with bank 6 paged in.
.music_start

.music_vars     SKIP 11     ; MUSIC_VAR_BASE block (accum, waits, starts, pitch)
MUSIC_VAR_BASE = music_vars

.sound_block    SKIP 8      ; OSWORD &07 control block -- must be main RAM
.music_enabled  SKIP 1      ; 1 = playing, 0 = muted (Q toggles)
.music_q_prev   SKIP 1      ; previous Q state, for edge detection

INCLUDE "music/player.asm"

; Envelope definitions (OSWORD &08 reads these, so keep them in main RAM).
.setup_envelopes
    LDA #8
    LDX #<env_melody
    LDY #>env_melody
    JSR OSWORD
    LDA #8
    LDX #<env_bass
    LDY #>env_bass
    JSR OSWORD
    LDA #8
    LDX #<env_chord
    LDY #>env_chord
    JSR OSWORD
    LDA #8
    LDX #<env_sfx_noise
    LDY #>env_sfx_noise
    JSR OSWORD
    LDA #8
    LDX #<env_sfx_rise
    LDY #>env_sfx_rise
    JSR OSWORD
    LDA #8
    LDX #<env_sfx_fall
    LDY #>env_sfx_fall
    JSR OSWORD
    RTS

.env_melody
    EQUB 1, 4, 0,0,0, 1,20,0, 15, -1, 0, -3, 12, 8
.env_bass
    EQUB 2, 6, 0,0,0, 1,30,0, 15, -1, 0, -1, 8, 6
.env_chord
    EQUB 3, 6, 0,0,0, 1,30,0, 15, -1, 0, -1, 8, 6

; SFX envelopes. Unlike 1-3 these are new shapes, not ported from the music
; test, so the numbers are a starting point and want tuning by ear.
.env_sfx_noise
    EQUB 4, 1, 0,0,0, 1,1,1, 127, -15, -5, -10, 90, 30
.env_sfx_rise
    EQUB 5, 1, 6,0,0, 8,1,1, 127, -10, 0, -12, 100, 50
.env_sfx_fall
    EQUB 6, 1, -6,0,0, 8,1,1, 127, -12, 0, -15, 90, 30

; --- Sound effects ---
;
; Effects use channel 0 (noise) and channel 3 (tone). Channel 3 is free because
; the music runs two voices (melody + bass) on channels 1 and 2, so effects can
; never interrupt the tune.
;
; Envelope shapes 4-6 are ours; the music owns 1-3.

SFX_PORTAL_OPEN   = 0
SFX_PORTAL_FAIL   = 1
SFX_PORTAL_PASS   = 2
SFX_SENTRY_FIRE   = 3
SFX_SPARK_COLLECT = 4
SFX_SPARK_CRASH   = 5

.sfx_index      SKIP 1

; 8 bytes per effect, copied straight into the OSWORD &07 block:
;   channel(2), amplitude/envelope(2), pitch(2), duration(2)
; Channel &0010 = flush + noise channel 0; &0013 = flush + tone channel 3.
.sfx_table
    EQUB &13,&00,  5,&00, 140,&00,  4,&00   ; 0 portal open   (rising tone)
    EQUB &10,&00,  4,&00,   4,&00,  3,&00   ; 1 portal fail   (short noise)
    EQUB &10,&00,  4,&00,   6,&00,  5,&00   ; 2 portal pass   (noise whoosh)
    EQUB &10,&00,  4,&00,   3,&00,  2,&00   ; 3 sentry fire   (noise crack)
    EQUB &13,&00,  5,&00, 200,&00,  8,&00   ; 4 spark collect (bright chime)
    EQUB &10,&00,  6,&00,   7,&00,  5,&00   ; 5 spark crash   (noise thud)

; Play any queued effect. Called from the main loop, where the shadow screen is
; paged out, so sound_block is the real main-RAM copy.
.sfx_init
    LDA #&FF
    STA SFX_PENDING
    JSR setup_envelopes
    RTS


.sfx_service
    LDA SFX_PENDING
    BMI sfx_none
    PHA
    LDA #&FF
    STA SFX_PENDING
    PLA
    JMP sfx_play
  .sfx_none
    RTS


; Play sound effect A. Preserves X and Y so it is safe to call from anywhere.
; Do NOT call this from rendering code -- see SFX_PENDING above.
.sfx_play
    STA sfx_index
    TXA
    PHA
    TYA
    PHA
    LDA sfx_index
    ASL A
    ASL A
    ASL A                   ; 8 bytes per record
    TAX
    LDY #0
  .sfx_copy
    LDA sfx_table,X
    STA sound_block,Y
    INX
    INY
    CPY #8
    BNE sfx_copy
    LDA #7
    LDX #<sound_block
    LDY #>sound_block
    JSR OSWORD
    PLA
    TAY
    PLA
    TAX
    RTS


; One-shot music startup: envelopes, then start the tracks.
; music_init reads music_track_table, which lives in bank 6 with the song.
.music_start_playing
    LDA #1
    STA music_enabled
    LDA #0
    STA music_q_prev
    LDA #&FF
    STA SFX_PENDING
    JSR setup_envelopes
    JSR tilemap_bank_in
    JSR music_init
    JSR tilemap_bank_out
    RTS


; Flush all four channels (0-3), including the noise channel used by effects.
; Used before disc access, where any active sound disturbs the DFS transfer.
.sfx_silence_all
    LDX #0
  .ssa_loop
    LDA ssa_chan_lo,X
    STA sound_block+0
    LDA #0
    STA sound_block+1
    STA sound_block+2
    STA sound_block+3
    STA sound_block+4
    STA sound_block+5
    LDA #1
    STA sound_block+6
    LDA #0
    STA sound_block+7
    TXA
    PHA
    LDA #7
    LDX #<sound_block
    LDY #>sound_block
    JSR OSWORD
    PLA
    TAX
    INX
    CPX #4
    BNE ssa_loop
    RTS
  .ssa_chan_lo
    EQUB &10, &11, &12, &13     ; flush=1, channels 0..3


; Stop all three voices immediately.
; Without the flush, muting would still drain whatever is queued in the MOS
; sound buffers, so Q would take a second or so to take effect.
.music_silence
    LDX #0
  .msil_loop
    LDA msil_chan_lo,X
    STA sound_block+0
    LDA #0
    STA sound_block+1
    STA sound_block+2       ; amplitude 0
    STA sound_block+3
    STA sound_block+4       ; pitch 0
    STA sound_block+5
    LDA #1
    STA sound_block+6       ; duration 1
    LDA #0
    STA sound_block+7
    TXA
    PHA
    LDA #7
    LDX #<sound_block
    LDY #>sound_block
    JSR OSWORD
    PLA
    TAX
    INX
    CPX #3
    BNE msil_loop
    RTS

  .msil_chan_lo
    EQUB &11, &12, &13      ; flush=1, channels 1..3

; Per-frame tick, plus the Q mute toggle.
; Song data is in bank 6, so page it around the player call.
.music_frame_tick
    ; Q toggles music. Edge-triggered on press so holding it doesn't flap.
    LDX #&EF                ; INKEY(-17) = 'Q'
    JSR is_key_pressed
    LDA #0
    BCC mus_q_state
    LDA #1
  .mus_q_state
    CMP music_q_prev
    BEQ mus_no_toggle
    STA music_q_prev
    ; STA leaves flags alone, so re-test A explicitly here -- otherwise this
    ; branch reads the CMP above (always non-equal) and the toggle fires on
    ; key release as well as press.
    CMP #0
    BEQ mus_no_toggle       ; act on press only, not release
    LDA music_enabled
    EOR #1
    STA music_enabled
    BNE mus_no_toggle       ; just switched on: resume ticking
    JSR music_silence       ; just switched off: kill the channels now
  .mus_no_toggle

    LDA music_enabled
    BEQ mus_done
    JSR tilemap_bank_in
    JSR music_update_50hz
    JSR tilemap_bank_out
  .mus_done
    RTS

.end

SAVE "PORTHLE", entry, end

; Boot loader (PROGRAM) is a small machine-code binary.
; !Boot runs: *BASIC then *RUN PROGRAM.

CLEAR &0E00, &1900
ORG &0E00
.program_start
INCLUDE "mode5/boot_loader.asm"
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

; Tilemap tile data — stamps for rendering.
; Kept in main RAM for fast tile rendering.
CLEAR &8000, &C000
ORG &8000
.tildat_start
INCLUDE "sprites/generated_tiles.asm"

; RESERVED: &B000..&BB00 in this bank holds the per-room tilemaps at runtime
; (TILEMAP_BANK_BASE in shared/tilemap.asm, MAX_ROOMS * 256 bytes). Boot loads
; TILDAT once, zero-filling that region; nothing may be placed there.
; Themed tile sheets go in &8800..&9FFF.
;
; &A000..&AFFF holds the music event streams (song data only -- the player
; code itself is in main RAM, per the no-executable-code-in-SWRAM rule).
ORG &A000
INCLUDE "music/gymnopedie.asm"

; Pad to full 16KB SWRAM bank (loader expects 16KB).
ORG &C000
.tildat_end
SAVE "TILDAT", tildat_start, tildat_end

; Loading screen (MODE 2) file.
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

; Aperture logo — MODE 5 graphic (128px wide).
; Loaded at runtime by show_level_card directly into screen RAM at &5A00
; (character row 3 onwards).
PUTFILE ".tmp/aperture_logo.bin", "APLOGO", &5A00, &5A00

; Level pack — binary level data loaded at boot into SWRAM bank 7.
CLEAR &8000, &C000
ORG &8000
.lvldata_start
INCBIN ".tmp/LVLS01.dat"
ORG &C000
.lvldata_end
SAVE "LVLS01", lvldata_start, lvldata_end

; !Boot file added via build.sh post-assembly to work around beebasm PUTFILE issue.
