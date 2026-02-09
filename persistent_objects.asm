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
CUBE_FLING_SPEED = 2           ; tiles/frame exit velocity for wall portals
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

    ; Sync tilemap tiles to reset obj_state (undo any activated pad/button/exit tiles).
    LDY #0
  .ipo_sync_tiles
    JSR update_object_tiles_for_state
    INY
    CPY #OBJ_COUNT
    BNE ipo_sync_tiles
    RTS


; Update cube physics: gravity + floor portal entry.
;
; Each non-carried cube in current_room falls 1 tile/frame if unsupported,
; and enters floor portals when directly above one.
;
; Must be called during update before rebuilding `solid_phys_plane`.
; Clobbers: A,X,Y,temp,temp_y,row_counter,col_counter
.update_cubes_physics
    LDY #0
  .ucp_loop
    CPY #OBJ_COUNT
    BCS ucp_done
    LDA obj_type,Y
    CMP #OBJ_TYPE_CUBE
    BNE ucp_next
    LDA obj_state,Y
    AND #OBJ_STATE_CARRIED
    BNE ucp_next
    LDA obj_room,Y
    CMP current_room
    BNE ucp_next

    ; --- Active cube in current room ---
    ; 1. Tick portal cooldown.
    LDA obj_portal_cd,Y
    BEQ ucp_no_cd
    SEC
    SBC #1
    STA obj_portal_cd,Y
  .ucp_no_cd
    ; 2. If cube has velocity, use velocity-based movement.
    LDA obj_vx,Y
    ORA obj_vy,Y
    BNE ucp_velocity

    ; 3. Check floor portal entry (stationary cubes).
    JSR cube_check_floor_portal
    BCS ucp_next               ; teleported — skip gravity

    ; 4. Apply gravity (fall 1 tile/frame).
    JSR cube_try_fall
    JMP ucp_next

  .ucp_velocity
    JSR cube_velocity_move

  .ucp_next
    INY
    JMP ucp_loop
  .ucp_done
    RTS


; Try to move cube Y down one tile row.
; Returns: C=0 always (gravity never "fails" in a meaningful sense).
; Clobbers: A,X,temp,temp_y
.cube_try_fall
    ; At bottom of room?
    LDA obj_y,Y
    CMP #15
    BCS ctf_done

    ; Check tiles below: (obj_x, obj_y+1) and (obj_x+1, obj_y+1).
    ; Use solid_tile_plane (tiles only, no cubes — avoids self-collision).
    LDA obj_y,Y
    CLC
    ADC #1
    TAX                        ; below_y
    LDA times16_table,X       ; below_y * 16
    CLC
    ADC obj_x,Y               ; + obj_x
    TAX
    LDA solid_tile_plane,X     ; left tile below
    BNE ctf_done
    INX
    LDA solid_tile_plane,X     ; right tile below
    BNE ctf_done

    ; Check other cubes at below_y.
    JSR cube_check_cubes_below
    BCS ctf_done               ; another cube blocks

    ; Move down one row.
    LDA obj_y,Y
    CLC
    ADC #1
    STA obj_y,Y
    LDA #1
    STA obj_dirty,Y
    STA objects_pending
  .ctf_done
    RTS


; Check if any other cube blocks cube Y from falling.
; Tests row (obj_y+1) for 2-wide overlap with another cube.
; Returns: C=1 blocked, C=0 clear.
; Clobbers: A,X,temp,temp_y
.cube_check_cubes_below
    LDA obj_y,Y
    CLC
    ADC #1
    STA temp                   ; below_y

    STY temp_y                 ; save current cube index
    LDX #0
  .cccb_loop
    CPX #OBJ_COUNT
    BCS cccb_clear
    CPX temp_y                 ; skip self
    BEQ cccb_next
    LDA obj_type,X
    CMP #OBJ_TYPE_CUBE
    BNE cccb_next
    LDA obj_state,X
    AND #OBJ_STATE_CARRIED
    BNE cccb_next
    LDA obj_room,X
    CMP current_room
    BNE cccb_next
    ; Is other cube at below_y?
    LDA obj_y,X
    CMP temp
    BNE cccb_next
    ; X overlap: 2-wide vs 2-wide. Blocked if |dx| < 2.
    LDA obj_x,X
    SEC
    SBC obj_x,Y
    BPL cccb_abs
    EOR #&FF
    CLC
    ADC #1
  .cccb_abs
    CMP #2
    BCC cccb_blocked           ; |dx| < 2 → overlap
  .cccb_next
    INX
    JMP cccb_loop
  .cccb_clear
    CLC                        ; no blocker
    RTS
  .cccb_blocked
    SEC                        ; blocked
    RTS


; Check if cube Y is at a floor portal (same tile position).
; If matched and paired portal exists, teleport the cube.
; Returns: C=1 teleported, C=0 no portal.
; Clobbers: A,X,temp,temp_y,row_counter,col_counter
.cube_check_floor_portal
    ; Skip if cooldown active.
    LDA obj_portal_cd,Y
    BNE ccfp_miss

    LDA obj_y,Y
    STA temp                   ; cube_y

    ; --- Check portal A ---
    LDA portal_a_enabled
    BEQ ccfp_try_b
    LDA portal_a_room
    CMP current_room
    BNE ccfp_try_b
    LDA portal_a_orient
    CMP #PORTAL_ORIENT_FLOOR
    BNE ccfp_try_b
    LDA portal_a_y
    CMP temp                   ; cube_y == portal_y?
    BNE ccfp_try_b
    ; X overlap (2-wide cube vs 2-wide portal): |dx| < 2
    LDA obj_x,Y
    SEC
    SBC portal_a_x
    BPL ccfp_a_abs
    EOR #&FF
    CLC
    ADC #1
  .ccfp_a_abs
    CMP #2
    BCS ccfp_try_b             ; no overlap
    ; Matched portal A → exit through portal B.
    LDA portal_b_enabled
    BEQ ccfp_miss
    LDA portal_b_orient
    CMP #PORTAL_ORIENT_BACK
    BEQ ccfp_miss
    LDA #1                     ; exit_kind = B
    JMP cube_do_portal_exit

  .ccfp_try_b
    ; --- Check portal B ---
    LDA portal_b_enabled
    BEQ ccfp_miss
    LDA portal_b_room
    CMP current_room
    BNE ccfp_miss
    LDA portal_b_orient
    CMP #PORTAL_ORIENT_FLOOR
    BNE ccfp_miss
    LDA portal_b_y
    CMP temp
    BNE ccfp_miss
    LDA obj_x,Y
    SEC
    SBC portal_b_x
    BPL ccfp_b_abs
    EOR #&FF
    CLC
    ADC #1
  .ccfp_b_abs
    CMP #2
    BCS ccfp_miss
    ; Matched portal B → exit through portal A.
    LDA portal_a_enabled
    BEQ ccfp_miss
    LDA portal_a_orient
    CMP #PORTAL_ORIENT_BACK
    BEQ ccfp_miss
    LDA #0                     ; exit_kind = A
    JMP cube_do_portal_exit

  .ccfp_miss
    CLC
    RTS


; Teleport cube Y through a portal exit.
; Input: A = exit_kind (0=A, 1=B), Y = obj_index (preserved).
; Returns: C=1 (teleported).
; Clobbers: A,X,temp,temp_y,row_counter,col_counter
.cube_do_portal_exit
    TAX
    BEQ cdpe_load_a
    ; Load portal B as exit.
    LDA portal_b_room    : STA temp          ; exit_room
    LDA portal_b_x       : STA temp_y        ; exit_x
    LDA portal_b_y       : STA row_counter   ; exit_y
    LDA portal_b_orient  : STA col_counter   ; exit_orient
    JMP cdpe_place
  .cdpe_load_a
    LDA portal_a_room    : STA temp
    LDA portal_a_x       : STA temp_y
    LDA portal_a_y       : STA row_counter
    LDA portal_a_orient  : STA col_counter

  .cdpe_place
    ; Move cube to exit room.
    LDA temp
    STA obj_room,Y

    ; Exit placement by orient.
    LDA col_counter
    CMP #PORTAL_ORIENT_WALL_L
    BEQ cdpe_wall_l
    CMP #PORTAL_ORIENT_WALL_R
    BEQ cdpe_wall_r
    CMP #PORTAL_ORIENT_CEIL
    BEQ cdpe_ceil
    ; Default: FLOOR exit — place above portal.
    LDA temp_y       : STA obj_x,Y
    LDA row_counter
    SEC : SBC #1
    STA obj_y,Y
    LDA #0
    STA obj_vx,Y : STA obj_vy,Y
    JMP cdpe_finish

  .cdpe_wall_l
    ; Left wall → cube exits right: x = portal_x + 1
    LDA temp_y
    CLC : ADC #1
    STA obj_x,Y
    LDA row_counter  : STA obj_y,Y
    LDA #CUBE_FLING_SPEED
    STA obj_vx,Y
    LDA #0 : STA obj_vy,Y
    JMP cdpe_finish

  .cdpe_wall_r
    ; Right wall → cube exits left: x = portal_x - 2 (cube is 2 wide)
    LDA temp_y
    SEC : SBC #2
    STA obj_x,Y
    LDA row_counter  : STA obj_y,Y
    LDA #(256-CUBE_FLING_SPEED)  ; two's complement negative
    STA obj_vx,Y
    LDA #0 : STA obj_vy,Y
    JMP cdpe_finish

  .cdpe_ceil
    ; Ceiling → cube exits below: y = portal_y + 1
    LDA temp_y       : STA obj_x,Y
    LDA row_counter
    CLC : ADC #1
    STA obj_y,Y
    LDA #0 : STA obj_vx,Y
    LDA #1 : STA obj_vy,Y

  .cdpe_finish
    ; Clamp x to 0..14 (2-wide cube).
    LDA obj_x,Y
    BMI cdpe_clamp_x0
    CMP #15
    BCC cdpe_x_ok
    LDA #14 : STA obj_x,Y
    JMP cdpe_x_ok
  .cdpe_clamp_x0
    LDA #0 : STA obj_x,Y
  .cdpe_x_ok
    ; Clamp y to 0..15.
    LDA obj_y,Y
    BMI cdpe_clamp_y0
    CMP #16
    BCC cdpe_y_ok
    LDA #15 : STA obj_y,Y
    JMP cdpe_y_ok
  .cdpe_clamp_y0
    LDA #0 : STA obj_y,Y
  .cdpe_y_ok
    ; Set cooldown + mark dirty.
    LDA #CUBE_PORTAL_COOLDOWN_FRAMES
    STA obj_portal_cd,Y
    LDA #1
    STA obj_dirty,Y
    STA objects_pending
    SEC                        ; teleported
    RTS


; Velocity-based cube movement (fling through portals).
;
; Each frame: check landing, apply gravity, step horizontal, step vertical.
; Input: Y = obj_index (preserved).
; Clobbers: A,X,temp,temp_y,row_counter,col_counter
.cube_velocity_move
    ; --- (a) Landing check ---
    ; If supported below AND vy >= 0: zero velocity, done.
    LDA obj_vy,Y
    BMI cvm_no_land             ; vy < 0 → rising, skip land check

    ; Check support below: solid_tile_plane at (x, y+1) and (x+1, y+1).
    LDA obj_y,Y
    CMP #15
    BCS cvm_land                ; at bottom of room → land
    CLC
    ADC #1
    TAX
    LDA times16_table,X
    CLC
    ADC obj_x,Y
    TAX
    LDA solid_tile_plane,X
    BNE cvm_land
    INX
    LDA solid_tile_plane,X
    BNE cvm_land

    ; Check other cubes below.
    JSR cube_check_cubes_below
    BCC cvm_no_land

  .cvm_land
    LDA #0
    STA obj_vx,Y
    STA obj_vy,Y
    LDA #1
    STA obj_dirty,Y
    STA objects_pending
    RTS

  .cvm_no_land
    ; --- (b) Gravity: vy = min(vy + 1, CUBE_TERMINAL_VY) ---
    LDA obj_vy,Y
    CLC
    ADC #1
    CMP #CUBE_TERMINAL_VY+1
    BCC cvm_vy_ok
    LDA #CUBE_TERMINAL_VY
  .cvm_vy_ok
    STA obj_vy,Y

    ; --- (c) Horizontal steps: loop |vx| times ---
    LDA obj_vx,Y
    BEQ cvm_vert                ; no horizontal velocity
    BPL cvm_h_right

    ; vx < 0 → moving left. Loop count = -vx (negate).
    EOR #&FF
    CLC
    ADC #1
    STA temp                    ; |vx| loop count
  .cvm_h_left_loop
    LDA temp
    BEQ cvm_vert

    ; Check left edge: x == 0 → wall.
    LDA obj_x,Y
    BEQ cvm_h_stop

    ; Check solid_tile_plane at (x-1, y).
    LDA obj_y,Y
    TAX
    LDA times16_table,X
    CLC
    ADC obj_x,Y
    SEC
    SBC #1                      ; tile at (x-1, y)
    TAX
    LDA solid_tile_plane,X
    BNE cvm_h_stop

    ; Move left.
    LDA obj_x,Y
    SEC
    SBC #1
    STA obj_x,Y
    DEC temp
    JMP cvm_h_left_loop

  .cvm_h_right
    STA temp                    ; vx (positive) = loop count
  .cvm_h_right_loop
    LDA temp
    BEQ cvm_vert

    ; Check right edge: x+2 >= 16 → wall (cube is 2 wide).
    LDA obj_x,Y
    CLC
    ADC #2
    CMP #16
    BCS cvm_h_stop

    ; Check solid_tile_plane at (x+2, y).
    LDA obj_y,Y
    TAX
    LDA times16_table,X
    CLC
    ADC obj_x,Y
    CLC
    ADC #2                      ; tile at (x+2, y)
    TAX
    LDA solid_tile_plane,X
    BNE cvm_h_stop

    ; Move right.
    LDA obj_x,Y
    CLC
    ADC #1
    STA obj_x,Y
    DEC temp
    JMP cvm_h_right_loop

  .cvm_h_stop
    LDA #0
    STA obj_vx,Y

  .cvm_vert
    ; --- (d) Vertical steps: loop |vy| times ---
    LDA obj_vy,Y
    BNE cvm_vert_go
    JMP cvm_done_dirty
  .cvm_vert_go
    BPL cvm_v_down

    ; vy < 0 → moving up. Loop count = -vy.
    EOR #&FF
    CLC
    ADC #1
    STA temp                    ; |vy| loop count
  .cvm_v_up_loop
    LDA temp
    BNE cvm_v_up_step
    JMP cvm_done_dirty
  .cvm_v_up_step

    ; Check top edge: y == 0 → ceiling.
    LDA obj_y,Y
    BEQ cvm_v_up_stop

    ; Check solid_tile_plane at (x, y-1) and (x+1, y-1).
    LDA obj_y,Y
    SEC
    SBC #1
    TAX
    LDA times16_table,X
    CLC
    ADC obj_x,Y
    TAX
    LDA solid_tile_plane,X
    BNE cvm_v_up_stop
    INX
    LDA solid_tile_plane,X
    BNE cvm_v_up_stop

    ; Move up.
    LDA obj_y,Y
    SEC
    SBC #1
    STA obj_y,Y
    DEC temp
    JMP cvm_v_up_loop

  .cvm_v_up_stop
    ; Zero vy only (keep horizontal momentum).
    LDA #0
    STA obj_vy,Y
    JMP cvm_done_dirty

  .cvm_v_down
    STA temp                    ; vy (positive) = loop count
  .cvm_v_down_loop
    LDA temp
    BNE cvm_v_down_step
    JMP cvm_done_dirty
  .cvm_v_down_step

    ; Check bottom edge: y >= 15 → floor.
    LDA obj_y,Y
    CMP #15
    BCS cvm_v_down_stop

    ; Check solid_tile_plane at (x, y+1) and (x+1, y+1).
    LDA obj_y,Y
    CLC
    ADC #1
    TAX
    LDA times16_table,X
    CLC
    ADC obj_x,Y
    TAX
    LDA solid_tile_plane,X
    BNE cvm_v_down_stop
    INX
    LDA solid_tile_plane,X
    BNE cvm_v_down_stop

    ; Check other cubes below.
    JSR cube_check_cubes_below
    BCS cvm_v_down_stop

    ; Move down one row.
    LDA obj_y,Y
    CLC
    ADC #1
    STA obj_y,Y

    ; Per-step portal check (prevents tunnelling past portals at high vy).
    JSR cube_check_floor_portal
    BCS cvm_teleported          ; teleported — exit immediately (portal sets new velocity)

    DEC temp
    JMP cvm_v_down_loop

  .cvm_v_down_stop
    ; Landed: zero both vx and vy.
    LDA #0
    STA obj_vx,Y
    STA obj_vy,Y

  .cvm_done_dirty
    LDA #1
    STA obj_dirty,Y
    STA objects_pending
  .cvm_teleported
    RTS


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
    ; Latch: once pressed, stay pressed (OR with existing state bit 0).
    ORA obj_state,Y
    AND #1

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
; Checks Chell standing on pad, then scans cubes on pad.
; Clobbers: A,X,temp,temp_y,row_counter,col_counter,temp_sprite_ptr
.compute_pad_pressed
    ; Default: not pressed.
    LDA #0
    STA col_counter

    ; --- Chell stands on pad ---
    LDA char_grounded
    BEQ pad_check_cubes

    LDA obj_room,Y
    CMP current_room
    BNE pad_check_cubes

    ; Chell feet tile_y must match (pad_y - 1)
    LDA obj_y,Y
    BEQ pad_check_cubes
    SEC
    SBC #1
    CMP row_counter
    BNE pad_check_cubes

    ; X overlap (2 tiles wide vs 2 tiles wide)
    JSR overlap_2wide_chell_vs_obj
    BCC pad_check_cubes

    LDA #1
    STA col_counter
    JMP pad_done

  ; --- Cube on pad ---
  .pad_check_cubes
    LDA col_counter
    BNE pad_done               ; already pressed by Chell

    ; Pad must be in current room.
    LDA obj_room,Y
    CMP current_room
    BNE pad_done

    ; above_y = pad_y - 1
    LDA obj_y,Y
    BEQ pad_done
    SEC
    SBC #1
    STA temp_sprite_ptr        ; above_y

    STY temp_sprite_ptr+1      ; save pad obj_index
    LDX #0
  .pad_cube_loop
    CPX #OBJ_COUNT
    BCS pad_done
    LDA obj_type,X
    CMP #OBJ_TYPE_CUBE
    BNE pad_cube_next
    LDA obj_state,X
    AND #OBJ_STATE_CARRIED
    BNE pad_cube_next
    LDA obj_room,X
    CMP current_room
    BNE pad_cube_next
    ; Cube at above_y?
    LDA obj_y,X
    CMP temp_sprite_ptr
    BNE pad_cube_next
    ; X overlap: 2-wide cube vs 2-wide pad. |dx| < 2.
    LDY temp_sprite_ptr+1      ; restore pad Y for obj_x lookup
    LDA obj_x,X
    SEC
    SBC obj_x,Y
    BPL pad_cube_abs
    EOR #&FF
    CLC
    ADC #1
  .pad_cube_abs
    CMP #2
    BCS pad_cube_next
    ; Overlap — pad pressed by cube.
    LDA #1
    STA col_counter
    LDY temp_sprite_ptr+1      ; restore pad Y
    JMP pad_done

  .pad_cube_next
    INX
    JMP pad_cube_loop

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
