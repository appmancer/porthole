.persistent_objects_start
; persistent_objects.asm
; Persistent level-global objects + signals.
;
; This file is included from `main.asm` near the portal stamping code, so label
; addresses stay stable.

; --- Persistent objects + signals ---
;
; Runtime object arrays are indexed by obj_index (0..OBJ_COUNT-1), initialized
; once from `.obj_defs` emitted by `tools/gen-level`.

OBJ_STATE_CARRIED = &80

; Cube physics tuning (tile-aligned).
; vx is in 8px tiles, vy is in 16px rows.
CUBE_TERMINAL_VX = 4
CUBE_TERMINAL_VY = 4

; Reuse Chell portal cooldown length.
CUBE_PORTAL_COOLDOWN_FRAMES = PORTAL_COOLDOWN_FRAMES

; --- Object redraw footprints (in tiles) ---
; Indexed by obj_type (OBJ_TYPE_*). Entry 0 is unused.
; These footprints are used when patching background tiles under a dirty object.
.obj_redraw_w_tiles
    EQUB 0                 ; type 0 (unused)
    EQUB 2                 ; cube   (16x16)
    EQUB 1                 ; button (8x16)
    EQUB 2                 ; pad    (16x16)
    EQUB 2                 ; exit   (16x32)
    EQUB 0                 ; spawner (tile-based, no sprite)

.obj_redraw_h_tiles
    EQUB 0                 ; type 0 (unused)
    EQUB 1                 ; cube
    EQUB 1                 ; button
    EQUB 1                 ; pad
    EQUB 2                 ; exit
    EQUB 0                 ; spawner (tile-based, no sprite)

; Initialize per-object runtime arrays from generated obj_defs.
; Clobbers: A,X,Y,temp,temp_y
.init_persistent_objects
    ; Clear signals.
    LDA #0
    STA sig_state

    ; Clear redraw bookkeeping.
    LDX #0
  .ipo_clear_dirty
    STA obj_dirty,X
    INX
    CPX #OBJ_COUNT
    BNE ipo_clear_dirty

    ; Clear per-object physics/cooldowns.
    LDX #0
  .ipo_clear_phys
    STA obj_vx,X
    STA obj_vy,X
    STA obj_portal_cd,X
    INX
    CPX #OBJ_COUNT
    BNE ipo_clear_phys

    LDX #0                  ; obj_index
    LDY #0                  ; byte offset into obj_defs
  .ipo_next
    ; type_id
    LDA obj_defs,Y
    STA obj_type,X
    INY
    ; channel
    LDA obj_defs,Y
    STA obj_channel,X
    INY
    ; init_flags -> obj_state
    LDA obj_defs,Y
    STA obj_state,X
    INY
    ; home_room
    LDA obj_defs,Y
    STA obj_room,X
    INY
    ; home_x
    LDA obj_defs,Y
    STA obj_x,X
    INY
    ; home_y
    LDA obj_defs,Y
    STA obj_y,X
    INY

    ; Initialize previous position to the starting position.
    LDA obj_x,X
    STA obj_prev_x,X
    LDA obj_y,X
    STA obj_prev_y,X
    LDA obj_room,X
    STA obj_prev_room,X

    INX
    CPX #OBJ_COUNT
    BNE ipo_next
    RTS


; Update cube physics (simple velocity + portals).
;
; - Gravity accelerates vy downwards when unsupported.
; - vx/vy are applied in tile steps.
; - If a cube overlaps a portal opening and has intent, it teleports with
;   momentum mapping (coarse, grid-aligned).
;
; Must be called during update before rebuilding `solid_phys_plane`.
; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter,screen_ptr,temp_sprite_ptr,temp_mask_ptr
; Cube physics/portal interactions are disabled in the size-recovery build.
.update_cubes_physics
    RTS


; Update a single cube's physics + portal interactions.
; Input: Y=obj_index (must be a cube in current_room and not carried).
; Output: none.
; Clobbers: A,X,temp,temp_y,row_counter,col_counter,screen_ptr,temp_sprite_ptr,temp_mask_ptr
IF 0
.update_one_cube_physics
    ; Tick portal cooldown.
    LDA obj_portal_cd,Y
    BEQ oucp_cd_done
    SEC
    SBC #1
    STA obj_portal_cd,Y
  .oucp_cd_done

    ; If overlapping a portal opening, teleport (may set objects_pending).
    JSR cube_try_portal_entry
    BCC oucp_not_teleported
    RTS
  .oucp_not_teleported

    ; --- Apply vertical movement by vy rows ---
    LDA obj_vy,Y
    BNE oucp_vy_nonzero
    JMP oucp_horiz
  .oucp_vy_nonzero
    BPL oucp_vy_down_start
    JMP oucp_vy_up

  .oucp_vy_down_start
    ; vy > 0 : step down.
    STA row_counter          ; steps
  .oucp_vy_down_loop
    ; Bottom edge: attempt to fall through a down-edge exit (off-screen simulation).
    LDA obj_y,Y
    CMP #15
    BNE oucp_down_not_bottom

    ; temp = cube center_x_cell (2-wide => left+1)
    LDA obj_x,Y
    CLC
    ADC #1
    STA temp

    ; find_exit_down_for_room clobbers Y.
    TYA
    PHA
    LDA obj_room,Y
    JSR find_exit_down_for_room
    PLA
    TAY
    BCS oucp_down_do_exit

    ; No down exit: stop falling.
    LDA #0
    STA obj_vy,Y
    JMP oucp_horiz

  .oucp_down_do_exit
    ; Record previous on-screen position for patch/erase.
    LDA obj_room,Y
    STA obj_prev_room,Y
    LDA obj_x,Y
    STA obj_prev_x,Y
    LDA obj_y,Y
    STA obj_prev_y,Y

    ; Enter destination room from the top.
    STA obj_room,Y
    LDA #0
    STA obj_y,Y

    ; Stop velocity when leaving the room.
    LDA #0
    STA obj_vx,Y
    STA obj_vy,Y
    STA obj_portal_cd,Y

    ; Mark pending patch + restamp.
    LDA #1
    STA objects_pending
    STA obj_dirty,Y
    RTS

  .oucp_down_not_bottom
    ; Can we fall one row within the room?
    JSR cube_can_fall_one_row
    BCS oucp_down_step
    ; Blocked: stop downward velocity.
    LDA #0
    STA obj_vy,Y
    JMP oucp_horiz

  .oucp_down_step
    ; Record previous on-screen position for patch/erase.
    LDA obj_room,Y
    STA obj_prev_room,Y
    LDA obj_x,Y
    STA obj_prev_x,Y
    LDA obj_y,Y
    STA obj_prev_y,Y

    ; Move down 1 tile row.
    LDA obj_y,Y
    CLC
    ADC #1
    STA obj_y,Y

    ; Mark pending patch + restamp.
    LDA #1
    STA objects_pending
    STA obj_dirty,Y

    ; Portal check at the new position.
    JSR cube_try_portal_entry
    BCC oucp_down_continue
    RTS
  .oucp_down_continue

    DEC row_counter
    BEQ oucp_vy_down_done
    JMP oucp_vy_down_loop
  .oucp_vy_down_done
    JMP oucp_horiz


  .oucp_vy_up
    ; vy < 0 : step up by -vy.
    ; steps = -vy
    EOR #&FF
    CLC
    ADC #1
    STA row_counter
  .oucp_vy_up_loop
    ; If already at top, stop.
    LDA obj_y,Y
    BEQ oucp_up_blocked

    ; Check above row tiles are empty (both columns) and no cube occupies it.
    JSR cube_can_rise_one_row
    BCS oucp_up_step
  .oucp_up_blocked
    LDA #0
    STA obj_vy,Y
    JMP oucp_horiz

  .oucp_up_step
    ; Record previous on-screen position for patch/erase.
    LDA obj_room,Y
    STA obj_prev_room,Y
    LDA obj_x,Y
    STA obj_prev_x,Y
    LDA obj_y,Y
    STA obj_prev_y,Y

    LDA obj_y,Y
    SEC
    SBC #1
    STA obj_y,Y

    LDA #1
    STA objects_pending
    STA obj_dirty,Y

    ; Portal check at the new position.
    JSR cube_try_portal_entry
    BCC oucp_up_continue
    RTS
  .oucp_up_continue

    DEC row_counter
    BEQ oucp_vy_up_done
    JMP oucp_vy_up_loop
  .oucp_vy_up_done


  .oucp_horiz
    ; --- Apply horizontal movement by vx tiles ---
    LDA obj_vx,Y
    BEQ oucp_gravity
    BMI oucp_vx_left

    ; vx > 0 : step right.
    STA row_counter
  .oucp_vx_right_loop
    JSR cube_try_step_right
    BCS oucp_vx_right_moved
    ; Blocked: stop.
    LDA #0
    STA obj_vx,Y
    JMP oucp_gravity
  .oucp_vx_right_moved
    ; Portal check at new position.
    JSR cube_try_portal_entry
    BCC oucp_vx_right_continue
    RTS
  .oucp_vx_right_continue
    DEC row_counter
    BEQ oucp_vx_right_done
    JMP oucp_vx_right_loop
  .oucp_vx_right_done
    JMP oucp_gravity

  .oucp_vx_left
    ; vx < 0 : step left by -vx.
    EOR #&FF
    CLC
    ADC #1
    STA row_counter
  .oucp_vx_left_loop
    JSR cube_try_step_left
    BCS oucp_vx_left_moved
    LDA #0
    STA obj_vx,Y
    JMP oucp_gravity
  .oucp_vx_left_moved
    JSR cube_try_portal_entry
    BCC oucp_vx_left_continue
    RTS
  .oucp_vx_left_continue
    DEC row_counter
    BEQ oucp_vx_left_done
    JMP oucp_vx_left_loop
  .oucp_vx_left_done


  .oucp_gravity
    ; --- Gravity for next frame ---
    ; If cube can fall AND isn't immediately entering a floor portal, accelerate down.
    ; (If a floor portal is active under the cube, cube_try_portal_entry will have
    ; already teleported it on this frame when cooldown permits.)

    ; Supported? (C=1 if can fall)
    JSR cube_can_fall_one_row
    BCS oucp_not_supported

    ; Supported: clamp vy to 0 if not rising.
    LDA obj_vy,Y
    BMI oucp_done
    LDA #0
    STA obj_vy,Y
    JMP oucp_done

  .oucp_not_supported
    ; Accelerate downward (vy += 1) up to terminal.
    LDA obj_vy,Y
    CMP #CUBE_TERMINAL_VY
    BCS oucp_done
    CLC
    ADC #1
    STA obj_vy,Y

  .oucp_done
    RTS


; --- Cube movement helpers ---

; C=1 if cube Y can rise one row (y-1) within its current room.
; Clobbers: A,X,temp,temp_y,row_counter,col_counter,temp_sprite_ptr
.cube_can_rise_one_row
    ; temp_y = above_y
    LDA obj_y,Y
    BNE ccror_y_ok
    JMP ccror_fail
  .ccror_y_ok
    SEC
    SBC #1
    STA temp_y

    ; temp_sprite_ptr := tilemap pointer for obj_room
    LDA obj_room,Y
    ASL A
    TAX
    LDA room_pointers,X
    STA temp_sprite_ptr
    LDA room_pointers+1,X
    STA temp_sprite_ptr+1

    ; idx = above_y*16 + obj_x
    LDX temp_y
    LDA times16_table,X
    CLC
    ADC obj_x,Y
    STA row_counter

    ; Tile 0 empty?
    TYA
    PHA
    LDY row_counter
    LDA (temp_sprite_ptr),Y
    PLA
    TAY
    BEQ ccror_tile0_ok
    CMP #TILE_BACKWALL_PORTAL
    BEQ ccror_tile0_ok
    JMP ccror_fail
  .ccror_tile0_ok

    ; Tile 1 empty?
    LDA row_counter
    CLC
    ADC #1
    STA row_counter
    TYA
    PHA
    LDY row_counter
    LDA (temp_sprite_ptr),Y
    PLA
    TAY
    BEQ ccror_tiles_ok
    CMP #TILE_BACKWALL_PORTAL
    BEQ ccror_tiles_ok
    JMP ccror_fail
  .ccror_tiles_ok

    ; Other cube check (same room at above_y)
    LDA obj_x,Y
    STA row_counter
    TYA
    STA col_counter
    LDX #0
  .ccror_scan
    CPX #OBJ_COUNT
    BEQ ccror_ok
    CPX col_counter
    BEQ ccror_next
    LDA obj_type,X
    CMP #OBJ_TYPE_CUBE
    BNE ccror_next
    LDA obj_state,X
    AND #OBJ_STATE_CARRIED
    BNE ccror_next
    LDA obj_room,X
    CMP obj_room,Y
    BNE ccror_next
    LDA obj_y,X
    CMP temp_y
    BNE ccror_next
    ; 2-wide overlap between obj_x[X] and row_counter
    LDA row_counter
    CLC
    ADC #2
    STA temp
    LDA obj_x,X
    CMP temp
    BCS ccror_next
    LDA obj_x,X
    CLC
    ADC #2
    STA temp
    LDA row_counter
    CMP temp
    BCS ccror_next
    JMP ccror_fail
  .ccror_next
    INX
    JMP ccror_scan

  .ccror_ok
    SEC
    RTS
  .ccror_fail
    CLC
    RTS


; Attempt to move cube Y one tile right.
; Output: C=1 moved, C=0 blocked.
; Clobbers: A,X,temp,temp_y,row_counter,col_counter,temp_sprite_ptr
.cube_try_step_right
    ; Reject if x would exceed 14 (2-wide cube).
    LDA obj_x,Y
    CMP #14
    BEQ ctsr_block
    CLC
    ADC #1
    STA temp             ; cand_x
    JMP cube_try_step_to_x

  .ctsr_block
    CLC
    RTS


; Attempt to move cube Y one tile left.
; Output: C=1 moved, C=0 blocked.
; Clobbers: A,X,temp,temp_y,row_counter,col_counter,temp_sprite_ptr
.cube_try_step_left
    LDA obj_x,Y
    BEQ ctsl_block
    SEC
    SBC #1
    STA temp
    JMP cube_try_step_to_x

  .ctsl_block
    CLC
    RTS


; Common step helper: move cube Y to cand_x in temp.
; Output: C=1 moved, C=0 blocked.
; Clobbers: A,X,temp_y,row_counter,col_counter,temp_sprite_ptr
.cube_try_step_to_x
    ; temp_sprite_ptr := tilemap pointer for obj_room
    LDA obj_room,Y
    ASL A
    TAX
    LDA room_pointers,X
    STA temp_sprite_ptr
    LDA room_pointers+1,X
    STA temp_sprite_ptr+1

    ; idx = obj_y*16 + cand_x
    LDA obj_y,Y
    TAX
    LDA times16_table,X
    CLC
    ADC temp
    STA row_counter

    ; Tile 0 empty?
    TYA
    PHA
    LDY row_counter
    LDA (temp_sprite_ptr),Y
    PLA
    TAY
    BEQ ctstx_tile0_ok
    CMP #TILE_BACKWALL_PORTAL
    BEQ ctstx_tile0_ok
    JMP ctstx_block
  .ctstx_tile0_ok
    ; Tile 1 empty?
    LDA row_counter
    CLC
    ADC #1
    STA row_counter
    TYA
    PHA
    LDY row_counter
    LDA (temp_sprite_ptr),Y
    PLA
    TAY
    BEQ ctstx_tiles_ok
    CMP #TILE_BACKWALL_PORTAL
    BEQ ctstx_tiles_ok
    JMP ctstx_block
  .ctstx_tiles_ok

    ; Other cube check: any cube at same y in same room overlapping new x?
    LDA temp
    STA row_counter       ; new_left
    TYA
    STA col_counter       ; self index
    LDX #0
  .ctstx_scan
    CPX #OBJ_COUNT
    BEQ ctstx_do_move
    CPX col_counter
    BEQ ctstx_next
    LDA obj_type,X
    CMP #OBJ_TYPE_CUBE
    BNE ctstx_next
    LDA obj_state,X
    AND #OBJ_STATE_CARRIED
    BNE ctstx_next
    LDA obj_room,X
    CMP obj_room,Y
    BNE ctstx_next
    LDA obj_y,X
    CMP obj_y,Y
    BNE ctstx_next
    ; 2-wide overlap between obj_x[X] and row_counter
    LDA row_counter
    CLC
    ADC #2
    STA temp_y
    LDA obj_x,X
    CMP temp_y
    BCS ctstx_next
    LDA obj_x,X
    CLC
    ADC #2
    STA temp_y
    LDA row_counter
    CMP temp_y
    BCS ctstx_next
    JMP ctstx_block
  .ctstx_next
    INX
    JMP ctstx_scan

  .ctstx_do_move
    ; Record previous for patch/erase.
    LDA obj_room,Y
    STA obj_prev_room,Y
    LDA obj_x,Y
    STA obj_prev_x,Y
    LDA obj_y,Y
    STA obj_prev_y,Y

    ; Commit x.
    LDA temp
    STA obj_x,Y

    LDA #1
    STA objects_pending
    STA obj_dirty,Y
    SEC
    RTS

  .ctstx_block
    CLC
    RTS


; --- Cube portal interactions ---

; Try to teleport cube Y through a portal opening.
; Output: C=1 if teleported, C=0 otherwise.
; Clobbers: A,X,temp,temp_y,row_counter,col_counter,screen_ptr,temp_sprite_ptr,temp_mask_ptr
.cube_try_portal_entry
    ; Cooldown blocks re-entry.
    LDA obj_portal_cd,Y
    BNE ctpe_no

    ; Prefer portal A.
    LDA portal_a_enabled
    BEQ ctpe_try_b
    LDA portal_a_room
    CMP current_room
    BNE ctpe_try_b
    LDA #0
    JSR cube_try_portal_kind
    BCS ctpe_yes

  .ctpe_try_b
    LDA portal_b_enabled
    BEQ ctpe_no
    LDA portal_b_room
    CMP current_room
    BNE ctpe_no
    LDA #1
    JSR cube_try_portal_kind
    BCS ctpe_yes

  .ctpe_no
    CLC
    RTS
  .ctpe_yes
    SEC
    RTS


; If a newly placed floor portal overlaps a cube, force the cube to fall through.
;
; Called from portal placement (reticle mode). Uses `portal_kind` to decide which
; portal instance was updated.
;
; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter,screen_ptr,temp_sprite_ptr,temp_mask_ptr
.maybe_kick_cubes_for_new_portal
    ; Determine which portal was placed.
    LDA portal_kind
    STA temp              ; entry_kind

    ; Only floor portals act as "holes" under cubes.
    LDA portal_kind
    BEQ mkcp_check_a
    ; B
    LDA portal_b_enabled
    BEQ mkcp_done
    LDA portal_b_room
    CMP current_room
    BNE mkcp_done
    LDA portal_b_orient
    CMP #PORTAL_ORIENT_FLOOR
    BNE mkcp_done
    JMP mkcp_kind_ok
  .mkcp_check_a
    LDA portal_a_enabled
    BEQ mkcp_done
    LDA portal_a_room
    CMP current_room
    BNE mkcp_done
    LDA portal_a_orient
    CMP #PORTAL_ORIENT_FLOOR
    BNE mkcp_done

  .mkcp_kind_ok
    ; Must have the other portal active to allow entry.
    LDA temp
    EOR #1
    BEQ mkcp_need_a
    ; need B
    LDA portal_b_enabled
    BEQ mkcp_done
    JMP mkcp_scan
  .mkcp_need_a
    LDA portal_a_enabled
    BEQ mkcp_done

  .mkcp_scan
    LDY #0
  .mkcp_loop
    LDA obj_type,Y
    CMP #OBJ_TYPE_CUBE
    BNE mkcp_next
    LDA obj_state,Y
    AND #OBJ_STATE_CARRIED
    BNE mkcp_next
    LDA obj_room,Y
    CMP current_room
    BNE mkcp_next

    ; Clear cooldown so the cube can enter immediately.
    LDA #0
    STA obj_portal_cd,Y
    ; Give it a small downward intent.
    STA obj_vx,Y
    LDA #1
    STA obj_vy,Y

    LDA temp
    JSR cube_try_portal_kind

  .mkcp_next
    INY
    CPY #OBJ_COUNT
    BNE mkcp_loop

  .mkcp_done
    RTS


; Try teleport for a specific entry portal kind.
; Input: A=entry_kind (0=A,1=B)
; Output: C=1 teleported, C=0 no.
; Clobbers: A,X,temp,temp_y,row_counter,col_counter,screen_ptr,temp_sprite_ptr,temp_mask_ptr
.cube_try_portal_kind
    STA temp                ; entry_kind

    ; Load entry portal state into temp_sprite_ptr (room), screen_ptr(x), temp_y(y), row_counter(orient).
    LDA temp
    BEQ ctp_k_a
    ; B
    LDA portal_b_enabled
    BNE ctp_k_b_enabled
    JMP ctp_k_no
  .ctp_k_b_enabled
    LDA portal_b_room
    STA temp_sprite_ptr
    LDA portal_b_x
    STA screen_ptr
    LDA portal_b_y
    STA temp_y
    LDA portal_b_orient
    STA row_counter
    JMP ctp_k_have_entry
  .ctp_k_a
    LDA portal_a_enabled
    BNE ctp_k_a_enabled
    JMP ctp_k_no
  .ctp_k_a_enabled
    LDA portal_a_room
    STA temp_sprite_ptr
    LDA portal_a_x
    STA screen_ptr
    LDA portal_a_y
    STA temp_y
    LDA portal_a_orient
    STA row_counter

  .ctp_k_have_entry
    ; Ignore back-wall portals for cubes (intent policy not defined).
    LDA row_counter
    CMP #PORTAL_ORIENT_BACK
    BNE ctp_k_not_back
    JMP ctp_k_no
  .ctp_k_not_back

    ; Compute entry portal collision rect in tile coords:
    ; temp_sprite_ptr+1 = rect_x0, temp_mask_ptr+1 = rect_y0, col_counter = w, screen_ptr+1 = h
    JSR cube_compute_portal_rect

    ; Overlap test vs cube rect.
    JSR cube_overlap_portal_rect
    BCS ctp_k_overlap_ok
    JMP ctp_k_no
  .ctp_k_overlap_ok

    ; Intent test.
    LDA row_counter          ; orient
    CMP #PORTAL_ORIENT_WALL_L
    BEQ ctp_k_intent_wall_l
    CMP #PORTAL_ORIENT_WALL_R
    BEQ ctp_k_intent_wall_r
    CMP #PORTAL_ORIENT_FLOOR
    BEQ ctp_k_intent_floor
    ; ceil
    JMP ctp_k_intent_ceil

  .ctp_k_intent_wall_l
    ; Enter left-wall portal by moving left (vx < 0)
    LDA obj_vx,Y
    BMI ctp_k_do
    JMP ctp_k_no
  .ctp_k_intent_wall_r
    ; Enter right-wall portal by moving right (vx > 0)
    LDA obj_vx,Y
    BNE ctp_k_wallr_nonzero
    JMP ctp_k_no
  .ctp_k_wallr_nonzero
    BMI ctp_k_no
    JMP ctp_k_do
  .ctp_k_intent_floor
    ; Enter floor portal when falling (vy > 0). If vy==0, gravity will pull it in.
    LDA obj_vy,Y
    BNE ctp_k_floor_nonzero
    LDA #1
    STA obj_vy,Y
    JMP ctp_k_do
  .ctp_k_floor_nonzero
    BMI ctp_k_no
    JMP ctp_k_do
  .ctp_k_intent_ceil
    LDA obj_vy,Y
    BMI ctp_k_do
    JMP ctp_k_no

  .ctp_k_do
    ; Stash entry orient for momentum mapping.
    LDA row_counter
    STA temp_mask_ptr      ; entry_orient

    ; Exit kind is the other portal.
    LDA temp
    EOR #1
    STA temp_y             ; exit_kind

    ; Ensure exit portal exists.
    LDA temp_y
    BEQ ctp_k_need_a
    ; Need B
    LDA portal_b_enabled
    BNE ctp_k_have_exit
    JMP ctp_k_no
  .ctp_k_need_a
    LDA portal_a_enabled
    BNE ctp_k_have_exit
    JMP ctp_k_no
  .ctp_k_have_exit
    ; Record previous position for patch/erase.
    LDA obj_room,Y
    STA obj_prev_room,Y
    LDA obj_x,Y
    STA obj_prev_x,Y
    LDA obj_y,Y
    STA obj_prev_y,Y

    ; Perform teleport (updates obj_x/obj_y/obj_room and velocities).
    JSR cube_do_teleport

    ; Mark pending patch + restamp.
    LDA #1
    STA objects_pending
    STA obj_dirty,Y

    ; Cooldown.
    LDA #CUBE_PORTAL_COOLDOWN_FRAMES
    STA obj_portal_cd,Y
    SEC
    RTS

  .ctp_k_no
    CLC
    RTS


; Compute portal collision rect for the entry portal currently in:
; - screen_ptr = portal_x (stored)
; - temp_y = portal_y (stored)
; - row_counter = orient
;
; Output:
; - temp_sprite_ptr+1 = rect_x0
; - temp_mask_ptr+1   = rect_y0
; - col_counter       = rect_w
; - screen_ptr+1      = rect_h
;
; Clobbers: A,X
.cube_compute_portal_rect
    ; y0
    LDA temp_y
    STA temp_mask_ptr+1

    ; Default dims.
    LDA #1
    STA col_counter
    LDA #2
    STA screen_ptr+1

    LDA row_counter
    CMP #PORTAL_ORIENT_FLOOR
    BCC ccpr_wall
    ; floor/ceil: 2x1
    LDA #2
    STA col_counter
    LDA #1
    STA screen_ptr+1
    LDA screen_ptr
    STA temp_sprite_ptr+1
    RTS

  .ccpr_wall
    ; wall: collision opening is adjacent to the wall tile.
    LDA row_counter
    CMP #PORTAL_ORIENT_WALL_L
    BEQ ccpr_wall_l
    ; wall_r: open to left
    LDA screen_ptr
    BEQ ccpr_wall_r_clamp
    SEC
    SBC #1
    STA temp_sprite_ptr+1
    RTS
  .ccpr_wall_r_clamp
    LDA #0
    STA temp_sprite_ptr+1
    RTS
  .ccpr_wall_l
    ; open to right
    LDA screen_ptr
    CMP #15
    BEQ ccpr_wall_l_clamp
    CLC
    ADC #1
    STA temp_sprite_ptr+1
    RTS
  .ccpr_wall_l_clamp
    LDA #15
    STA temp_sprite_ptr+1
    RTS


; Overlap test between cube Y (2x1 tiles) and portal rect.
; Inputs:
; - temp_sprite_ptr+1 = rect_x0
; - temp_mask_ptr+1   = rect_y0
; - col_counter       = rect_w
; - screen_ptr+1      = rect_h
;
; Output: C=1 overlap, C=0 no.
; Clobbers: A
.cube_overlap_portal_rect
    ; cube_x0 in temp
    LDA obj_x,Y
    STA temp

    ; if (rect_x0 + rect_w) <= cube_x0 => no overlap
    LDA temp_sprite_ptr+1
    CLC
    ADC col_counter
    CMP temp
    BEQ copr_no
    BCC copr_no

    ; if (cube_x0 + 2) <= rect_x0 => no overlap
    LDA temp
    CLC
    ADC #2
    CMP temp_sprite_ptr+1
    BEQ copr_no
    BCC copr_no

    ; y overlap
    ; if (rect_y0 + rect_h) <= cube_y0 => no overlap
    LDA temp_mask_ptr+1
    CLC
    ADC screen_ptr+1
    CMP obj_y,Y
    BEQ copr_no
    BCC copr_no

    ; if (cube_y0 + 1) <= rect_y0 => no overlap
    LDA obj_y,Y
    CLC
    ADC #1
    CMP temp_mask_ptr+1
    BEQ copr_no
    BCC copr_no

    SEC
    RTS
  .copr_no
    CLC
    RTS


; Teleport cube Y from entry portal kind in temp_mask_ptr to exit kind in temp.
; Uses entry orient in row_counter and entry rect base in temp_sprite_ptr+1/temp_mask_ptr+1.
; Updates obj_room/obj_x/obj_y and obj_vx/obj_vy.
; Clobbers: A,X,temp_y,col_counter,screen_ptr,temp_sprite_ptr

.cube_do_teleport
    ; Load exit portal state.
    ; Inputs:
    ; - temp_y = exit_kind (0=A,1=B)
    ; - temp_mask_ptr = entry_orient
    ;
    ; Locals:
    ; - temp_sprite_ptr = exit_room
    ; - screen_ptr = exit_portal_x (stored)
    ; - temp = exit_portal_y (stored)
    ; - row_counter = exit_orient
    LDA temp_y
    BEQ cdt_exit_a
    ; Exit B
    LDA portal_b_room
    STA temp_sprite_ptr
    LDA portal_b_x
    STA screen_ptr
    LDA portal_b_y
    STA temp
    LDA portal_b_orient
    STA row_counter
    JMP cdt_have_exit
  .cdt_exit_a
    LDA portal_a_room
    STA temp_sprite_ptr
    LDA portal_a_x
    STA screen_ptr
    LDA portal_a_y
    STA temp
    LDA portal_a_orient
    STA row_counter

  .cdt_have_exit
    ; Ignore back-wall exits for cubes.
    LDA row_counter
    CMP #PORTAL_ORIENT_BACK
    BNE cdt_exit_ok
    JMP cdt_abort
  .cdt_exit_ok

    ; Compute exit portal collision rect into temp_sprite_ptr+1 (x0) and temp_mask_ptr+1 (y0).
    LDA temp
    STA temp_y
    ; screen_ptr already holds stored x.
    JSR cube_compute_portal_rect

    ; --- Momentum mapping in 8px units ---
    ; vx8 in screen_ptr (signed), vy8 in temp_y (signed)
    LDA obj_vx,Y
    STA screen_ptr
    LDA obj_vy,Y
    ASL A
    STA temp_y

    ; (v_t in sprite_ptr, v_n in sprite_ptr+1)
    LDA temp_mask_ptr         ; entry_orient
    CMP #PORTAL_ORIENT_WALL_L
    BEQ cdt_vtn_wall_l
    CMP #PORTAL_ORIENT_WALL_R
    BEQ cdt_vtn_wall_r
    CMP #PORTAL_ORIENT_FLOOR
    BEQ cdt_vtn_floor
    JMP cdt_vtn_ceil

  .cdt_vtn_wall_l
    ; v_t = vy8
    LDA temp_y
    STA sprite_ptr
    ; v_n = -vx8
    LDA screen_ptr
    EOR #&FF
    CLC
    ADC #1
    STA sprite_ptr+1
    JMP cdt_recompose

  .cdt_vtn_wall_r
    ; v_t = -vy8
    LDA temp_y
    EOR #&FF
    CLC
    ADC #1
    STA sprite_ptr
    ; v_n = vx8
    LDA screen_ptr
    STA sprite_ptr+1
    JMP cdt_recompose

  .cdt_vtn_floor
    ; v_t = vx8
    LDA screen_ptr
    STA sprite_ptr
    ; v_n = vy8
    LDA temp_y
    STA sprite_ptr+1
    JMP cdt_recompose

  .cdt_vtn_ceil
    ; v_t = -vx8
    LDA screen_ptr
    EOR #&FF
    CLC
    ADC #1
    STA sprite_ptr
    ; v_n = -vy8
    LDA temp_y
    EOR #&FF
    CLC
    ADC #1
    STA sprite_ptr+1

  .cdt_recompose
    ; Recompose for exit orient in row_counter.
    ; vx8' -> screen_ptr, vy8' -> temp_y
    LDA row_counter
    CMP #PORTAL_ORIENT_WALL_L
    BEQ cdt_out_wall_l
    CMP #PORTAL_ORIENT_WALL_R
    BEQ cdt_out_wall_r
    CMP #PORTAL_ORIENT_FLOOR
    BEQ cdt_out_floor
    JMP cdt_out_ceil

  .cdt_out_wall_l
    LDA sprite_ptr+1
    STA screen_ptr
    LDA sprite_ptr
    STA temp_y
    JMP cdt_store_vel

  .cdt_out_wall_r
    LDA sprite_ptr+1
    EOR #&FF
    CLC
    ADC #1
    STA screen_ptr
    LDA sprite_ptr
    EOR #&FF
    CLC
    ADC #1
    STA temp_y
    JMP cdt_store_vel

  .cdt_out_floor
    LDA sprite_ptr
    STA screen_ptr
    LDA sprite_ptr+1
    EOR #&FF
    CLC
    ADC #1
    STA temp_y
    JMP cdt_store_vel

  .cdt_out_ceil
    LDA sprite_ptr
    EOR #&FF
    CLC
    ADC #1
    STA screen_ptr
    LDA sprite_ptr+1
    STA temp_y

  .cdt_store_vel
    ; Clamp vx8 to +/-CUBE_TERMINAL_VX.
    LDA screen_ptr
    BMI cdt_vx_neg
    CMP #CUBE_TERMINAL_VX+1
    BCC cdt_vx_store
    LDA #CUBE_TERMINAL_VX
    JMP cdt_vx_store
  .cdt_vx_neg
    EOR #&FF
    CLC
    ADC #1
    CMP #CUBE_TERMINAL_VX+1
    BCC cdt_vx_neg_ok
    LDA #CUBE_TERMINAL_VX
  .cdt_vx_neg_ok
    EOR #&FF
    CLC
    ADC #1
  .cdt_vx_store
    STA obj_vx,Y

    ; Quantize vy8 to 16px rows (toward zero), clamp to +/-CUBE_TERMINAL_VY.
    LDA temp_y
    AND #&FE
    STA temp_y
    LDA temp_y
    BMI cdt_vy_neg
    LSR A
    JMP cdt_vy_clamp
  .cdt_vy_neg
    EOR #&FF
    CLC
    ADC #1
    LSR A
    EOR #&FF
    CLC
    ADC #1
  .cdt_vy_clamp
    ; Clamp signed vy
    BMI cdt_vy_clamp_neg
    CMP #CUBE_TERMINAL_VY+1
    BCC cdt_vy_store
    LDA #CUBE_TERMINAL_VY
    JMP cdt_vy_store
  .cdt_vy_clamp_neg
    EOR #&FF
    CLC
    ADC #1
    CMP #CUBE_TERMINAL_VY+1
    BCC cdt_vy_neg_ok
    LDA #CUBE_TERMINAL_VY
  .cdt_vy_neg_ok
    EOR #&FF
    CLC
    ADC #1
  .cdt_vy_store
    STA obj_vy,Y

    ; --- Place cube near exit portal ---
    ; Default new_x/new_y = exit rect base.
    LDA temp_sprite_ptr+1     ; exit rect x0
    STA obj_x,Y
    LDA temp_mask_ptr+1       ; exit rect y0
    STA obj_y,Y

    ; Nudge along exit normal to avoid overlap.
    LDA row_counter
    CMP #PORTAL_ORIENT_WALL_L
    BEQ cdt_nudge_wall_l
    CMP #PORTAL_ORIENT_WALL_R
    BEQ cdt_nudge_wall_r
    CMP #PORTAL_ORIENT_FLOOR
    BEQ cdt_nudge_floor
    JMP cdt_nudge_ceil

  .cdt_nudge_wall_l
    ; Place to the right of the opening column.
    LDA obj_x,Y
    CLC
    ADC #1
    CMP #15
    BCC cdt_nudge_wall_l_ok
    LDA #14
  .cdt_nudge_wall_l_ok
    STA obj_x,Y
    JMP cdt_commit_room

  .cdt_nudge_wall_r
    ; Place to the left of the opening column.
    LDA obj_x,Y
    SEC
    SBC #2
    BCS cdt_nudge_wall_r_ok
    LDA #0
  .cdt_nudge_wall_r_ok
    STA obj_x,Y
    JMP cdt_commit_room

  .cdt_nudge_floor
    ; Exit upwards: y := rect_y0 - 1
    LDA obj_y,Y
    BEQ cdt_nudge_floor_ok
    SEC
    SBC #1
    STA obj_y,Y
  .cdt_nudge_floor_ok
    JMP cdt_commit_room

  .cdt_nudge_ceil
    ; Exit downwards: y := rect_y0 + 1
    LDA obj_y,Y
    CMP #15
    BEQ cdt_nudge_ceil_ok
    CLC
    ADC #1
    STA obj_y,Y
  .cdt_nudge_ceil_ok

  .cdt_commit_room
    ; Update room.
    LDA temp_sprite_ptr
    STA obj_room,Y

    CLC
    RTS

  .cdt_abort
    ; Can't teleport: keep cube where it is.
    CLC
    RTS


; Apply 16px-step gravity to cube objects.
;
; For each cube in the current room that isn't carried:
; - if both tiles below its 2-wide footprint are clear (tiles + other cubes),
;   move it down by 1 tile and mark it dirty.
;
; Must be called during update before rebuilding `solid_phys_plane`.
; Clobbers: A,X,Y,temp,temp_y,col_counter,row_counter
.update_cubes_gravity
    LDY #0
  .ucg_loop
    LDA obj_type,Y
    CMP #OBJ_TYPE_CUBE
    BEQ ucg_type_ok
    JMP ucg_next
  .ucg_type_ok

    LDA obj_room,Y
    CMP current_room
    BEQ ucg_room_ok
    JMP ucg_next
  .ucg_room_ok

    ; Skip carried cubes.
    LDA obj_state,Y
    AND #OBJ_STATE_CARRIED
    BEQ ucg_not_carried
    JMP ucg_next
  .ucg_not_carried

    ; Bottom edge: attempt to fall through a down-edge exit.
    LDA obj_y,Y
    CMP #15
    BNE ucg_not_bottom

    ; temp = cube center_x_cell (2-wide => left+1)
    LDA obj_x,Y
    CLC
    ADC #1
    STA temp

    ; If a down exit matches, move cube into the destination room and resolve
    ; its final resting position immediately (including chaining through further
    ; down exits). This is off-screen simulation; the visible room does not change.
    ; find_exit_down_for_room clobbers Y.
    TYA
    PHA
    LDA obj_room,Y
    JSR find_exit_down_for_room
    PLA
    TAY
    BCS ucg_do_exit_down
    JMP ucg_next

  .ucg_do_exit_down
    ; A = dst_room
    STA col_counter

    ; Record previous on-screen position for patch/erase.
    LDA obj_room,Y
    STA obj_prev_room,Y
    LDA obj_x,Y
    STA obj_prev_x,Y
    LDA obj_y,Y
    STA obj_prev_y,Y

    ; Move to destination room, entering from the top.
    LDA col_counter
    STA obj_room,Y
    LDA #0
    STA obj_y,Y

    ; Resolve landing position in the destination room immediately.
    ; This is off-screen simulation; the visible room does not change.
    LDA col_counter
    JSR compute_cube_landing_y_in_room

    ; Mark pending patch + restamp (current room will erase old footprint).
    LDA #1
    STA objects_pending
    STA obj_dirty,Y
    JMP ucg_next

  .ucg_not_bottom

    ; below_y = obj_y + 1
    CLC
    ADC #1
    STA temp_y

    ; idx0 = (below_y*16) + obj_x
    TAX
    LDA times16_table,X
    CLC
    ADC obj_x,Y
    TAX

    ; Blocked by solid world tile?
    LDA solid_tile_plane,X
    BEQ ucg_tile0_ok
    JMP ucg_next
  .ucg_tile0_ok
    INX
    LDA solid_tile_plane,X
    BEQ ucg_tile1_ok
    JMP ucg_next
  .ucg_tile1_ok

    ; Blocked by another cube at below_y overlapping in X?
    ; Cache this cube's x in row_counter.
    LDA obj_x,Y
    STA row_counter

    ; Cache this cube's obj_index for self-skip.
    TYA
    STA temp

    LDX #0
  .ucg_scan
    CPX #OBJ_COUNT
    BEQ ucg_can_fall
    ; Skip self.
    CPX temp
    BEQ ucg_scan_next

    LDA obj_type,X
    CMP #OBJ_TYPE_CUBE
    BNE ucg_scan_next
    LDA obj_state,X
    AND #OBJ_STATE_CARRIED
    BNE ucg_scan_next
    LDA obj_room,X
    CMP current_room
    BNE ucg_scan_next
    LDA obj_y,X
    CMP temp_y
    BNE ucg_scan_next

    ; 2-wide overlap between obj_x[X] and row_counter (this cube's x)
    ; If other_left >= this_left+2 => no overlap
    LDA row_counter
    CLC
    ADC #2
    STA col_counter
    LDA obj_x,X
    CMP col_counter
    BCS ucg_scan_next
    ; If this_left >= other_left+2 => no overlap
    LDA obj_x,X
    CLC
    ADC #2
    STA col_counter
    LDA row_counter
    CMP col_counter
    BCS ucg_scan_next

    ; Overlap => can't fall.
    JMP ucg_next

  .ucg_scan_next
    INX
    JMP ucg_scan

  .ucg_can_fall
    ; Record previous on-screen position for patch/erase.
    LDA obj_room,Y
    STA obj_prev_room,Y
    LDA obj_x,Y
    STA obj_prev_x,Y
    LDA obj_y,Y
    STA obj_prev_y,Y

    ; Move down 1 tile.
    LDA obj_y,Y
    CLC
    ADC #1
    STA obj_y,Y

    ; Mark pending patch + restamp.
    LDA #1
    STA objects_pending
    STA obj_dirty,Y

  .ucg_next
    INY
    CPY #OBJ_COUNT
    BEQ ucg_done
    JMP ucg_loop
  .ucg_done
    RTS



; Resolve cube falling immediately, including chaining through down exits.
;
; Input: Y=obj_index (cube). Uses obj_room/obj_x/obj_y.
; Output: obj_room/obj_y updated to final resting place.
; Clobbers: A,X,temp,temp_y,row_counter,col_counter,temp_sprite_ptr
.resolve_cube_fall
    ; Clamp x to 0..14 (2-wide object).
    LDA obj_x,Y
    CMP #15
    BCC rcf_x_ok
    LDA #14
    STA obj_x,Y
  .rcf_x_ok

  .rcf_loop
    ; If at bottom row, try to fall through a down exit; else we are done.
    LDA obj_y,Y
    CMP #15
    BNE rcf_try_step

    ; temp = cube center_x_cell (2-wide => left+1)
    LDA obj_x,Y
    CLC
    ADC #1
    STA temp

    ; find_exit_down_for_room clobbers Y.
    TYA
    PHA
    LDA obj_room,Y
    JSR find_exit_down_for_room
    PLA
    TAY
    BCS rcf_do_down_exit
    RTS

  .rcf_do_down_exit
    ; Enter destination room from the top.
    STA obj_room,Y
    LDA #0
    STA obj_y,Y
    JMP rcf_loop

  .rcf_try_step
    ; Can we fall one row within this room?
    JSR cube_can_fall_one_row
    BCS rcf_fall_one
    RTS

  .rcf_fall_one
    LDA obj_y,Y
    CLC
    ADC #1
    STA obj_y,Y
    JMP rcf_loop


; C=1 if cube Y can fall one tile within its current room.
; Tests world tiles and other non-carried cubes.
; Clobbers: A,X,temp,temp_y,row_counter,col_counter,temp_sprite_ptr
.cube_can_fall_one_row
    ; If already at bottom, can't fall within the room.
    LDA obj_y,Y
    CMP #15
    BNE ccfor_not_bottom
    CLC
    RTS
  .ccfor_not_bottom

    ; temp_y = below_y
    CLC
    ADC #1
    STA temp_y

    ; --- World tile check in obj_room ---
    ; temp_sprite_ptr := tilemap pointer for obj_room
    LDA obj_room,Y
    ASL A
    TAX
    LDA room_pointers,X
    STA temp_sprite_ptr
    LDA room_pointers+1,X
    STA temp_sprite_ptr+1

    ; idx = below_y*16 + obj_x
    LDX temp_y
    LDA times16_table,X
    CLC
    ADC obj_x,Y
    STA row_counter          ; idx0

    ; Tile 0
    TYA
    PHA
    LDY row_counter
    LDA (temp_sprite_ptr),Y
    PLA
    TAY
    BEQ ccfor_tile0_ok
    CMP #TILE_BACKWALL_PORTAL
    BEQ ccfor_tile0_ok
    CLC
    RTS
  .ccfor_tile0_ok

    ; Tile 1 (x+1)
    LDA row_counter
    CLC
    ADC #1
    STA row_counter
    TYA
    PHA
    LDY row_counter
    LDA (temp_sprite_ptr),Y
    PLA
    TAY
    BEQ ccfor_tile1_ok
    CMP #TILE_BACKWALL_PORTAL
    BEQ ccfor_tile1_ok
    CLC
    RTS
  .ccfor_tile1_ok

    ; --- Other cube check (in same room at below_y) ---
    ; Cache this cube's x in row_counter.
    LDA obj_x,Y
    STA row_counter

    ; Cache this cube's obj_index for self-skip.
    TYA
    STA col_counter

    LDX #0
  .ccfor_scan
    CPX #OBJ_COUNT
    BEQ ccfor_clear
    CPX col_counter
    BEQ ccfor_next

    LDA obj_type,X
    CMP #OBJ_TYPE_CUBE
    BNE ccfor_next
    LDA obj_state,X
    AND #OBJ_STATE_CARRIED
    BNE ccfor_next
    LDA obj_room,X
    CMP obj_room,Y
    BNE ccfor_next
    LDA obj_y,X
    CMP temp_y
    BNE ccfor_next

    ; 2-wide overlap between obj_x[X] and row_counter.
    ; If other_left >= this_left+2 => no overlap
    LDA row_counter
    CLC
    ADC #2
    STA temp
    LDA obj_x,X
    CMP temp
    BCS ccfor_next
    ; If this_left >= other_left+2 => no overlap
    LDA obj_x,X
    CLC
    ADC #2
    STA temp
    LDA row_counter
    CMP temp
    BCS ccfor_next

    ; Overlap => blocked.
    CLC
    RTS

  .ccfor_next
    INX
    JMP ccfor_scan

  .ccfor_clear
    SEC
    RTS


; Find matching down-edge exit for the given room.
; Input: A=room index, temp=center_x_cell
; Output: C=1 and A=dst_room on match, else C=0.
; Clobbers: A,X,Y,col_counter,temp_sprite_ptr,temp_mask_ptr,exit_dst
.find_exit_down_for_room
    TAX
    LDA exit_down_counts,X
    BNE fedfr_have
    JMP find_exit_none
  .fedfr_have
    STA col_counter

    TXA
    ASL A
    TAX
    LDA exit_down_ptrs,X
    STA temp_sprite_ptr
    LDA exit_down_ptrs+1,X
    STA temp_sprite_ptr+1
    JMP find_exit_scan


; Compute cube landing tile Y in the given room, assuming it enters from the top.
;
; Input: A=room index, Y=obj_index (cube). Uses obj_x[Y].
; Output: obj_y[Y] updated to landing row (0..15).
; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter,temp_sprite_ptr
.compute_cube_landing_y_in_room
    ; Preserve cube obj_index.
    STY temp

    ; temp_sprite_ptr := tilemap pointer for room A.
    ASL A
    TAX
    LDA room_pointers,X
    STA temp_sprite_ptr
    LDA room_pointers+1,X
    STA temp_sprite_ptr+1

    ; Restore cube obj_index.
    LDY temp

    ; Clamp x to 0..14 (2-wide object).
    LDA obj_x,Y
    CMP #15
    BCC ccl_x_ok
    LDA #14
    STA obj_x,Y
  .ccl_x_ok

    LDA #0
    STA row_counter          ; candidate_y

  .ccl_loop
    LDA row_counter
    CMP #15
    BEQ ccl_place

    ; below_y = candidate_y + 1
    CLC
    ADC #1
    TAX
    ; idx0 = below_y*16 + obj_x
    LDA times16_table,X
    CLC
    ADC obj_x,Y
    STA col_counter          ; idx0

    ; Tile 0 solidity
    LDY col_counter
    LDA (temp_sprite_ptr),Y
    TAX
    TXA
    AND #&20
    BNE ccl_place

    ; Tile 1 (x+1) solidity
    LDY col_counter
    INY
    LDA (temp_sprite_ptr),Y
    TAX
    TXA
    AND #&20
    BNE ccl_place

    ; Next row.
    LDY temp
    INC row_counter
    JMP ccl_loop

  .ccl_place
    LDY temp
    LDA row_counter
    STA obj_y,Y
    RTS


ENDIF

; Update `sig_state` from drivers, and update per-object visual state bits.
;
; - Drivers: pad/button set channel bits.
; - Consumers: exit reads channel bits.
;
; If any visible object's state bit changes in the current room, sets
; `objects_pending=1` and marks the object in `obj_dirty[]` so render can patch
; only the affected object rects.
;
; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter,screen_ptr,sprite_ptr
.update_signals_and_object_states
    ; Precompute Chell tile coords.
    ; temp = chell_x (0..15)
    LDA char_tile_pos
    AND #15
    STA temp
    ; temp_y = chell_y (0..15)
    LDA char_tile_pos
    LSR A
    LSR A
    LSR A
    LSR A
    STA temp_y
    ; row_counter = chell_bottom_y (tile y of feet)
    ; char_tile_pos stores Chell's top tile row; sprite is 2 tiles tall.
    LDA temp_y
    CLC
    ADC #1
    STA row_counter

    ; Clear published signals.
    LDA #0
    STA sig_state

    ; Pass 1: drivers (pad/button)
    LDY #0
  .usos_driver_loop
    LDA obj_type,Y
    CMP #OBJ_TYPE_PAD
    BEQ usos_do_pad
    CMP #OBJ_TYPE_BUTTON
    BEQ usos_do_button
    JMP usos_driver_next

  .usos_do_pad
    JSR compute_pad_pressed
    JMP usos_apply_driver

  .usos_do_button
    JSR compute_button_pressed

  .usos_apply_driver
    ; A = pressed (0/1)
    STA col_counter

    ; If pressed, OR its channel bit into sig_state.
    BEQ usos_driver_state
    LDX obj_channel,Y
    LDA bit_table,X
    ORA sig_state
    STA sig_state

  .usos_driver_state
    ; Update obj_state bit0 (pressed) and mark room dirty if visible state changed.
    LDA obj_state,Y
    AND #&FE
    ORA col_counter
    STA screen_ptr          ; new_state

    LDA obj_state,Y
    CMP screen_ptr
    BEQ usos_driver_next

    LDA screen_ptr
    STA obj_state,Y

    JSR update_object_tiles_for_state

    ; Visible change? only matters if this object is in the current room.
    LDA obj_room,Y
    CMP current_room
    BNE usos_driver_next
    LDA #1
    STA objects_pending
    STA obj_dirty,Y
    JMP usos_driver_next

  .usos_driver_next
    INY
    CPY #OBJ_COUNT
    BNE usos_driver_loop

    ; Beam targets as signal drivers (laser → target → channel).
    JSR update_beam_targets

    ; Pass 2: consumers (exit, spawner)
    LDY #0
  .usos_cons_loop
    LDA obj_type,Y
    CMP #OBJ_TYPE_EXIT
    BNE usos_chk_spawner

    ; open = (sig_state & (1<<channel)) != 0
    LDX obj_channel,Y
    LDA bit_table,X
    AND sig_state
    BEQ usos_exit_closed
    LDA #1
    JMP usos_exit_apply
  .usos_exit_closed
    LDA #0

  .usos_exit_apply
    STA col_counter

    ; Update obj_state bit0 (open)
    LDA obj_state,Y
    AND #&FE
    ORA col_counter
    STA screen_ptr          ; new_state

    LDA obj_state,Y
    CMP screen_ptr
    BEQ usos_cons_next

    LDA screen_ptr
    STA obj_state,Y

    JSR update_object_tiles_for_state

    ; Visible change? only matters if this exit is in the current room.
    LDA obj_room,Y
    CMP current_room
    BNE usos_cons_next
    LDA #1
    STA objects_pending
    STA obj_dirty,Y
    JMP usos_cons_next

  .usos_chk_spawner
    CMP #OBJ_TYPE_SPAWNER
    BNE usos_cons_next

    ; Check if spawner's channel is active.
    LDX obj_channel,Y
    LDA bit_table,X
    AND sig_state
    BEQ usos_cons_next         ; signal not active

    ; Get linked cube index from obj_state.
    LDX obj_state,Y
    ; Check if cube is despawned (room == &FF).
    LDA obj_room,X
    CMP #&FF
    BNE usos_cons_next         ; cube already exists

    ; Spawn cube at spawner position.
    LDA obj_room,Y
    STA obj_room,X
    LDA obj_x,Y
    STA obj_x,X
    LDA obj_y,Y
    STA obj_y,X

    ; Mark cube dirty so it gets stamped this frame.
    LDA #1
    STA obj_dirty,X
    STA objects_pending

  .usos_cons_next
    INY
    CPY #OBJ_COUNT
    BNE usos_cons_loop

    RTS


; Update tilemap entries for pad/button/exit based on obj_state bit0.
; Input: Y=obj_index
; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter,screen_ptr,temp_sprite_ptr
.update_object_tiles_for_state
    TYA
    PHA
    STA temp_y             ; obj_index

    LDA obj_type,Y
    CMP #OBJ_TYPE_PAD
    BEQ uots_pad
    CMP #OBJ_TYPE_BUTTON
    BEQ uots_button
    CMP #OBJ_TYPE_EXIT
    BEQ uots_exit
    JMP uots_done

  .uots_pad
    LDA obj_state,Y
    AND #1
    BEQ uots_pad_up
    LDA #TILE_PAD_DOWN_L
    STA temp
    LDA #TILE_PAD_DOWN_R
    STA col_counter
    JMP uots_pad_write
  .uots_pad_up
    LDA #TILE_PAD_UP_L
    STA temp
    LDA #TILE_PAD_UP_R
    STA col_counter
  .uots_pad_write
    JSR uots_set_room_ptr_and_offset
    LDA temp
    STA (temp_sprite_ptr),Y
    INY
    LDA col_counter
    STA (temp_sprite_ptr),Y
    JMP uots_done

  .uots_button
    LDA obj_state,Y
    AND #1
    BEQ uots_button_up
    LDA #TILE_BUTTON_DOWN
    JMP uots_button_write
  .uots_button_up
    LDA #TILE_BUTTON_UP
  .uots_button_write
    STA temp
    JSR uots_set_room_ptr_and_offset
    LDA temp
    STA (temp_sprite_ptr),Y
    JMP uots_done

  .uots_exit
    LDA obj_state,Y
    AND #1
    BEQ uots_exit_closed
    LDA #TILE_EXIT_OPEN_TL
    STA temp
    LDA #TILE_EXIT_OPEN_TR
    STA col_counter
    LDA #TILE_EXIT_OPEN_BL
    STA screen_ptr
    LDA #TILE_EXIT_OPEN_BR
    STA screen_ptr+1
    JMP uots_exit_write
  .uots_exit_closed
    LDA #TILE_EXIT_CLOSED_TL
    STA temp
    LDA #TILE_EXIT_CLOSED_TR
    STA col_counter
    LDA #TILE_EXIT_CLOSED_BL
    STA screen_ptr
    LDA #TILE_EXIT_CLOSED_BR
    STA screen_ptr+1
  .uots_exit_write
    JSR uots_set_room_ptr_and_offset
    LDA temp
    STA (temp_sprite_ptr),Y
    INY
    LDA col_counter
    STA (temp_sprite_ptr),Y
    TYA
    CLC
    ADC #15
    TAY
    LDA screen_ptr
    STA (temp_sprite_ptr),Y
    INY
    LDA screen_ptr+1
    STA (temp_sprite_ptr),Y

  .uots_done
    PLA
    TAY
    RTS


; Set temp_sprite_ptr to the room tilemap for obj_index in temp_y.
; Also returns Y as tilemap offset (tile_y*16 + tile_x).
; Clobbers: A,X,Y
.uots_set_room_ptr_and_offset
    LDY temp_y
    LDA obj_room,Y
    JSR get_room_tilemap_ptr

    LDY temp_y
    LDA obj_y,Y
    TAX
    LDA times16_table,X
    CLC
    ADC obj_x,Y
    TAY
    RTS


; Set temp_sprite_ptr to the tilemap pointer for room index in A.
; Clobbers: A,X
.get_room_tilemap_ptr
    ASL A
    TAX
    LDA room_pointers,X
    STA temp_sprite_ptr
    LDA room_pointers+1,X
    STA temp_sprite_ptr+1
    RTS


; Patch background and restamp only the dirty persistent objects.
;
; Must be called during render after sprite restores, so we don't resurrect
; stale pixels. This routine redraws the underlying tilemap for the object
; footprint, restamps portals for the room (so portals remain behind objects),
; then restamps the updated objects.
;
; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter,screen_ptr,sprite_ptr,mask_ptr
.apply_pending_object_updates
    LDA objects_pending
    BNE apou_go
    RTS

  .apou_go
      ; Pass 1: redraw underlying tiles for each dirty object's footprint.
      LDY #0
  .apou_redraw_loop
      LDA obj_dirty,Y
      BEQ apou_redraw_next

    ; Preserve obj_index across redraw_tile_xy (clobbers Y).
    TYA
    PHA

     ; Also keep a copy in temp_y so we can re-index arrays after Y is reused.
     STA temp_y

    ; Cache footprint top-left and lookup footprint size.
    ; Note: redraw_tile_xy -> render_cell8x16 clobbers sprite_ptr, so keep the
    ; base coords in temp_sprite_ptr.
    LDX obj_type,Y
    LDA obj_redraw_w_tiles,X
    STA mask_ptr             ; w
    LDA obj_redraw_h_tiles,X
    STA mask_ptr+1           ; h

    ; Redraw old footprint (prev coords) to erase the moved object,
    ; but only if that old footprint was in the currently-visible room.
    LDY temp_y
    LDA obj_prev_room,Y
    CMP current_room
    BNE apou_skip_redraw_old
    LDA obj_prev_x,Y
    STA temp_sprite_ptr      ; base_x
    LDA obj_prev_y,Y
    STA temp_sprite_ptr+1    ; base_y
    JSR apou_redraw_footprint
  .apou_skip_redraw_old

    ; Redraw new footprint only if the object is in the current room.
    LDY temp_y
    LDA obj_room,Y
    CMP current_room
    BNE apou_redraw_restore

    ; If the object moved within the room, redraw the new footprint as well.
    LDA obj_prev_x,Y
    CMP obj_x,Y
    BNE apou_do_redraw_new
    LDA obj_prev_y,Y
    CMP obj_y,Y
    BEQ apou_redraw_restore
  .apou_do_redraw_new
    LDA obj_x,Y
    STA temp_sprite_ptr
    LDA obj_y,Y
    STA temp_sprite_ptr+1
    JSR apou_redraw_footprint

  .apou_redraw_restore
    ; Restore obj_index.
    PLA
    TAY

  .apou_redraw_next
    INY
    CPY #OBJ_COUNT
    BNE apou_redraw_loop

    ; Portals are part of the background; redraw_tile_xy erases them.
    JSR stamp_portals_for_current_room

    ; Pass 2: restamp dirty objects with ROMSEL held on obj_bank.
    ; Preserve caller IRQ state (nested callers may already be SEI).
    PHP
    SEI
    LDA ROMSEL
    STA saved_romsel
    LDA obj_bank
    STA ROMSEL

    LDY #0
  .apou_stamp_loop
    LDA obj_dirty,Y
    BEQ apou_stamp_next

    ; Only stamp objects in the current room.
    LDA obj_room,Y
    CMP current_room
    BNE apou_commit_prev_only

    ; Stamp just this object.
    JSR stamp_persistent_object

  .apou_commit_prev_only

    ; Commit its previous position to the current position (patch is now applied).
    LDA obj_x,Y
    STA obj_prev_x,Y
    LDA obj_y,Y
    STA obj_prev_y,Y
    LDA obj_room,Y
    STA obj_prev_room,Y

    ; Clear dirty bit.
    LDA #0
    STA obj_dirty,Y

  .apou_stamp_next
    INY
    CPY #OBJ_COUNT
    BNE apou_stamp_loop

    LDA saved_romsel
    STA ROMSEL
    PLP

    LDA #0
    STA objects_pending
    RTS


; Redraw tiles for the footprint at temp_sprite_ptr (base_x/base_y).
; Uses mask_ptr (w) and mask_ptr+1 (h).
; Clobbers: A,X,Y,temp,col_counter
.apou_redraw_footprint
     ; Outer: dy (Y), inner: dx (X). Preserve dx/dy across redraw_tile_xy.
     LDY #0
   .apou_rf_dy_loop
     CPY mask_ptr+1
     BCS apou_rf_done

     ; y_cur = base_y + dy; stop if off bottom.
     TYA
     CLC
     ADC temp_sprite_ptr+1
     CMP #16
     BCS apou_rf_done
     STA col_counter          ; y_cur

     LDX #0
   .apou_rf_dx_loop
     CPX mask_ptr
     BCS apou_rf_next_row

     ; x_cur = base_x + dx; stop row if off right.
     TXA
     CLC
     ADC temp_sprite_ptr
     CMP #16
     BCS apou_rf_next_row
     STA temp                 ; x_cur

     ; Save dx/dy across redraw (it clobbers X/Y).
     TXA
     PHA
     TYA
     PHA

     LDX temp
     LDA col_counter
     JSR redraw_tile_xy

     PLA
     TAY
     PLA
     TAX

     INX
     JMP apou_rf_dx_loop

   .apou_rf_next_row
     INY
     JMP apou_rf_dy_loop

  .apou_rf_done
     RTS


; Stamp a single persistent object (tile-aligned).
; Input: Y=obj_index, screen_ptr scratch is clobbered.
; Assumes ROMSEL already points at obj_bank.
.stamp_persistent_object
    ; Preserve obj_index across stamp_striped_masked (uses Y as stride/loop).
    TYA
    PHA

    ; Skip carried cubes (they're represented by Chell's overlay while held).
    LDA obj_type,Y
    CMP #OBJ_TYPE_CUBE
    BNE spo_not_carried
    LDA obj_state,Y
    AND #OBJ_STATE_CARRIED
    BEQ spo_not_carried
    PLA
    TAY
    RTS
  .spo_not_carried

    ; screen_ptr := &5800 + y*512 + x*16
    LDA #<(&5800)
    STA screen_ptr
    LDA #>(&5800)
    STA screen_ptr+1

    ; y*512 => add (y*2) to high byte
    LDA obj_y,Y
    ASL A
    CLC
    ADC screen_ptr+1
    STA screen_ptr+1

    ; x*16 => add to low byte
    LDA obj_x,Y
    TAX
    LDA times16_table,X
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC spo_x_ok
    INC screen_ptr+1
  .spo_x_ok

    ; Choose sprite/mask + geometry from type/state.
    LDA obj_type,Y
    CMP #OBJ_TYPE_CUBE
    BNE spo_chk_button
    JMP spo_cube

  .spo_chk_button
    CMP #OBJ_TYPE_BUTTON
    BNE spo_chk_pad
    JMP spo_done

  .spo_chk_pad
    CMP #OBJ_TYPE_PAD
    BNE spo_chk_exit
    JMP spo_done

  .spo_chk_exit
    CMP #OBJ_TYPE_EXIT
    BEQ spo_done
    JMP spo_done


  .spo_cube
    LDA #<obj_cube_x0
    STA sprite_ptr
    LDA #>obj_cube_x0
    STA sprite_ptr+1
    LDA #<obj_cube_x0_mask
    STA mask_ptr
    LDA #>obj_cube_x0_mask
    STA mask_ptr+1
    ; 16x16
    LDA #2
    LDX #32
    LDY #32
    JSR stamp_striped_masked
    PLA
    TAY
    RTS

  .spo_done
    PLA
    TAY
    RTS


; Return A=1 if pad object Y is pressed, else A=0.
; Activation zone is one tile above the pad tile anchor (obj_y-1).
; Uses Chell only. Clobbers: A,temp,row_counter,col_counter
.compute_pad_pressed
    ; Default: not pressed.
    LDA #0
    STA col_counter

    ; --- Chell stands on pad ---
    LDA char_grounded
    BEQ pad_done

    LDA obj_room,Y
    CMP current_room
    BNE pad_done

    ; Chell feet tile_y must match (pad_y - 1)
    LDA obj_y,Y
    BEQ pad_done
    SEC
    SBC #1
    CMP row_counter
    BNE pad_done

    ; X overlap (2 tiles wide vs 2 tiles wide)
    JSR overlap_2wide_chell_vs_obj
    BCC pad_done

    LDA #1
    STA col_counter

  .pad_done
    LDA col_counter
    RTS


; Return A=1 if button object Y is pressed, else A=0.
; Press rule (MVP): SPACE edge while Chell overlaps the button zone.
; Clobbers: A,temp,temp_y,row_counter,col_counter,sprite_ptr
.compute_button_pressed
    LDA #0
    STA col_counter

    LDA action_pressed
    BEQ button_done

    LDA obj_room,Y
    CMP current_room
    BNE button_done

    ; Require Chell feet tile_y to match button_y.
    LDA obj_y,Y
    CMP row_counter
    BNE button_done

    ; X overlap
    JSR overlap_2wide_chell_vs_obj
    BCC button_done

    LDA #1
    STA col_counter

  .button_done
    LDA col_counter
    RTS


; Handle SPACE edge for cube pickup/drop.
;
; Rule: SPACE near cube toggles pickup/drop.
; - Pickup: cube must be in current_room, at Chell's feet tile_y, and overlap in X.
; - Drop: attempts to place the cube on Chell's feet tile_y, in front of Chell.
;
; Side effects:
; - Marks objects_pending + obj_dirty so render patches/restamps object stamps.
; - Sets chell_dirty so overlay updates immediately.
;
; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter
.handle_cube_pickup_drop
    LDA action_pressed
    BNE hcpd_go
    RTS
  .hcpd_go

    ; Precompute Chell tile coords.
    ; temp = chell_x (0..15)
    LDA char_tile_pos
    AND #15
    STA temp
    ; temp_y = chell_y (0..15)
    LDA char_tile_pos
    LSR A
    LSR A
    LSR A
    LSR A
    STA temp_y
    ; row_counter = chell_bottom_y (tile y of feet)
    ; char_tile_pos stores Chell's top tile row; sprite is 2 tiles tall.
    LDA temp_y
    CLC
    ADC #1
    STA row_counter

    ; If already carrying, try to drop.
    LDA carried_cube_idx
    CMP #&FF
    BNE hcpd_try_drop

    ; --- Pickup ---
    LDY #0
  .hcpd_pick_loop
    LDA obj_type,Y
    CMP #OBJ_TYPE_CUBE
    BNE hcpd_pick_next
    LDA obj_state,Y
    AND #OBJ_STATE_CARRIED
    BNE hcpd_pick_next
    LDA obj_room,Y
    CMP current_room
    BNE hcpd_pick_next
    LDA obj_y,Y
    CMP row_counter
    BNE hcpd_pick_next
    ; Pickup should work when Chell is adjacent (cubes are solid, so overlap is rare).
    JSR chell_near_2wide_obj
    BCC hcpd_pick_next

    ; Pick up cube Y.
    TYA
    STA carried_cube_idx
    LDA obj_state,Y
    ORA #OBJ_STATE_CARRIED
    STA obj_state,Y

    ; While carried, cube physics is disabled.
    LDA #0
    STA obj_vx,Y
    STA obj_vy,Y
    STA obj_portal_cd,Y

    LDA #1
    STA objects_pending
    STA obj_dirty,Y
    STA chell_dirty
    RTS

  .hcpd_pick_next
    INY
    CPY #OBJ_COUNT
    BNE hcpd_pick_loop
    RTS


; C=1 if Chell (temp=chell_x) is near object Y (obj_x[Y]) where both are 2 tiles wide.
; Near means overlapping OR touching edges (|dx| <= 2).
; Clobbers: A
.chell_near_2wide_obj
    ; dx = obj_left - chell_left
    LDA obj_x,Y
    SEC
    SBC temp
    BCS cno_dx_pos

    ; dx negative: abs = chell_left - obj_left
    LDA temp
    SEC
    SBC obj_x,Y
  .cno_dx_pos
    CMP #3
    BCS cno_far
    SEC
    RTS
  .cno_far
    CLC
    RTS


  .hcpd_try_drop
    ; Y := carried cube index
    LDA carried_cube_idx
    TAY

    ; Try drop candidate: in front of facing.
    ; temp already holds chell_x.

    ; candidate0: in front of facing (adjacent; Chell is 2 tiles wide)
    LDA anim_dir
    BEQ hcpd_cand0_left
    ; facing right => x = chell_x + 2
    LDA temp
    CLC
    ADC #2
    JMP hcpd_try_place
  .hcpd_cand0_left
    ; facing left => x = chell_x - 2
    LDA temp
    SEC
    SBC #2
  .hcpd_try_place
    JSR try_place_carried_cube_at_x
    BCS hcpd_drop_success
    RTS

  .hcpd_drop_success
    ; Drop succeeded: cube is now in room at new coords.
    LDA #&FF
    STA carried_cube_idx
    LDA #1
    STA chell_dirty

  .hcpd_done
    RTS


; Try to place carried cube (Y=obj_index) at candidate tile X in A.
; Uses row_counter = chell feet tile_y.
;
; Output: C=1 success (object updated + marked dirty), C=0 fail.
; Clobbers: A,X,temp_y,col_counter
.try_place_carried_cube_at_x
    ; Reject if negative (wrapped) or outside 0..14 for 2-tile-wide cube.
    CMP #&80
    BCC tpc_chk_hi
    JMP tpc_fail
  .tpc_chk_hi
    CMP #15
    BCC tpc_range_ok
    JMP tpc_fail
  .tpc_range_ok

    ; Ensure doesn't overlap Chell (both 2 tiles wide).
    STA temp_y              ; cand_x

    ; If cand_left >= chell_left+2 => ok
    LDA temp
    CLC
    ADC #2
    CMP temp_y
    BCC tpc_check_world
    BEQ tpc_check_world

    ; If chell_left >= cand_left+2 => ok
    LDA temp_y
    CLC
    ADC #2
    CMP temp
    BCC tpc_check_world
    BEQ tpc_check_world

    ; overlap
    CLC
    RTS

  .tpc_check_world
    ; Reject if solid tile at (x,y) or (x+1,y).
    ; idx = row_counter*16 + cand_x
    LDX row_counter
    LDA times16_table,X
    CLC
    ADC temp_y
    TAX
    LDA solid_tile_plane,X
    BEQ tpc_tile0_ok
    JMP tpc_fail
  .tpc_tile0_ok
    INX
    LDA solid_tile_plane,X
    BEQ tpc_tile1_ok
    JMP tpc_fail
  .tpc_tile1_ok

    ; Reject if another non-carried cube overlaps at same y.
    LDX #0
  .tpc_cube_scan
    CPX carried_cube_idx
    BEQ tpc_cube_next
    LDA obj_type,X
    CMP #OBJ_TYPE_CUBE
    BNE tpc_cube_next
    LDA obj_state,X
    AND #OBJ_STATE_CARRIED
    BNE tpc_cube_next
    LDA obj_room,X
    CMP current_room
    BNE tpc_cube_next
    LDA obj_y,X
    CMP row_counter
    BNE tpc_cube_next

    ; 2-wide overlap between obj_x[X] and cand_x(temp_y)
    ; If obj_left >= cand_left+2 => no overlap
    LDA temp_y
    CLC
    ADC #2
    STA col_counter
    LDA obj_x,X
    CMP col_counter
    BCS tpc_cube_next
    ; If cand_left >= obj_left+2 => no overlap
    LDA obj_x,X
    CLC
    ADC #2
    STA col_counter
    LDA temp_y
    CMP col_counter
    BCS tpc_cube_next

    ; overlap => can't place
    CLC
    RTS

  .tpc_cube_next
    INX
    CPX #OBJ_COUNT
    BNE tpc_cube_scan

    ; Place cube.
    LDA current_room
    STA obj_room,Y
    LDA temp_y
    STA obj_x,Y
    LDA row_counter
    STA obj_y,Y

    ; Carried cubes are not stamped while held; on drop, treat the new position
    ; as both prev and current so we don't erase an unrelated old footprint.
    LDA temp_y
    STA obj_prev_x,Y
    LDA row_counter
    STA obj_prev_y,Y
    LDA current_room
    STA obj_prev_room,Y

    LDA obj_state,Y
    AND #&7F
    STA obj_state,Y

    ; Dropped cube starts with no velocity.
    LDA #0
    STA obj_vx,Y
    STA obj_vy,Y
    STA obj_portal_cd,Y

    LDA #1
    STA objects_pending
    STA obj_dirty,Y
    SEC
    RTS

  .tpc_fail
    CLC
    RTS


; C=1 if Chell (temp=chell_x) overlaps object Y (obj_x[Y]) assuming both 2 tiles wide.
; Clobbers: A,row_counter
.overlap_2wide_chell_vs_obj
    ; If obj_left >= chell_left+2 => no overlap
    LDA temp
    CLC
    ADC #2
    STA row_counter
    LDA obj_x,Y
    CMP row_counter
    BCS ov_no

    ; If chell_left >= obj_left+2 => no overlap
    LDA obj_x,Y
    CLC
    ADC #2
    STA row_counter
    LDA temp
    CMP row_counter
    BCS ov_no

    SEC
    RTS
  .ov_no
    CLC
    RTS


; Stamp all objects whose obj_room == current_room.
; Uses obj_bank for sprite/mask reads.
; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter,screen_ptr,sprite_ptr,mask_ptr
.render_persistent_objects_current_room
    ; Page in object SWRAM for reads.
    ; Preserve caller IRQ state (nested callers may already be SEI).
    PHP
    SEI
    LDA ROMSEL
    STA saved_romsel
    LDA obj_bank
    STA ROMSEL

    LDY #0
  .rpobj_loop
    LDA obj_room,Y
    CMP current_room
    BEQ rpobj_in_room
    JMP rpobj_next

  .rpobj_in_room
    ; Skip carried cubes (they're represented by Chell's overlay while held).
    LDA obj_type,Y
    CMP #OBJ_TYPE_CUBE
    BNE rpobj_not_carried
    LDA obj_state,Y
    AND #OBJ_STATE_CARRIED
    BEQ rpobj_not_carried
    JMP rpobj_next
  .rpobj_not_carried

    ; screen_ptr := &5800 + y*512 + x*16
    LDA #<(&5800)
    STA screen_ptr
    LDA #>(&5800)
    STA screen_ptr+1

    ; y*512 => add (y*2) to high byte
    LDA obj_y,Y
    ASL A
    CLC
    ADC screen_ptr+1
    STA screen_ptr+1

    ; x*16 => add to low byte
    LDA obj_x,Y
    TAX
    LDA times16_table,X
    CLC
    ADC screen_ptr
    STA screen_ptr
    BCC rpobj_x_ok
    INC screen_ptr+1
  .rpobj_x_ok

    ; Choose sprite/mask + geometry from type/state.
    ; Use short local branches, then JMP to handlers.
    LDA obj_type,Y
    CMP #OBJ_TYPE_CUBE
    BNE rpobj_chk_button
    JMP rpobj_cube

  .rpobj_chk_button
    CMP #OBJ_TYPE_BUTTON
    BNE rpobj_chk_pad
    JMP rpobj_next

  .rpobj_chk_pad
    CMP #OBJ_TYPE_PAD
    BNE rpobj_chk_exit
    JMP rpobj_next

  .rpobj_chk_exit
    CMP #OBJ_TYPE_EXIT
    BNE rpobj_not_exit
    JMP rpobj_next
  .rpobj_not_exit
    JMP rpobj_next

  .rpobj_cube
    LDA #<obj_cube_x0
    STA sprite_ptr
    LDA #>obj_cube_x0
    STA sprite_ptr+1
    LDA #<obj_cube_x0_mask
    STA mask_ptr
    LDA #>obj_cube_x0_mask
    STA mask_ptr+1
    TYA
    PHA
    ; 16x16
    LDA #2
    LDX #32
    LDY #32
    JSR stamp_striped_masked
    PLA
    TAY
    JMP rpobj_next

  .rpobj_next
    INY
    CPY #OBJ_COUNT
    BEQ rpobj_done
    JMP rpobj_loop

  .rpobj_done
    ; Restore ROMSEL and re-enable IRQs.
    LDA saved_romsel
    STA ROMSEL
    PLP
    RTS
