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

; --- Object redraw footprints (in tiles) ---
; Indexed by obj_type (OBJ_TYPE_*). Entry 0 is unused.
; These footprints are used when patching background tiles under a dirty object.
.obj_redraw_w_tiles
    EQUB 0                 ; type 0 (unused)
    EQUB 2                 ; cube   (16x16)
    EQUB 2                 ; button (16x16)
    EQUB 2                 ; pad    (16x16)
    EQUB 2                 ; exit   (16x32)

.obj_redraw_h_tiles
    EQUB 0                 ; type 0 (unused)
    EQUB 1                 ; cube
    EQUB 1                 ; button
    EQUB 1                 ; pad
    EQUB 2                 ; exit

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
    LDA SOLID_TILE_PLANE,X
    BEQ ucg_tile0_ok
    JMP ucg_next
  .ucg_tile0_ok
    INX
    LDA SOLID_TILE_PLANE,X
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
    LDA tile_material_flags,X
    AND #2
    BNE ccl_place

    ; Tile 1 (x+1) solidity
    LDY col_counter
    INY
    LDA (temp_sprite_ptr),Y
    TAX
    LDA tile_material_flags,X
    AND #2
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

    ; Pass 2: consumers (exit)
    LDY #0
  .usos_cons_loop
    LDA obj_type,Y
    CMP #OBJ_TYPE_EXIT
    BNE usos_cons_next

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

    ; Visible change? only matters if this exit is in the current room.
    LDA obj_room,Y
    CMP current_room
    BNE usos_cons_next
    LDA #1
    STA objects_pending
    STA obj_dirty,Y

  .usos_cons_next
    INY
    CPY #OBJ_COUNT
    BNE usos_cons_loop

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
    JMP spo_button

  .spo_chk_pad
    CMP #OBJ_TYPE_PAD
    BNE spo_chk_exit
    JMP spo_pad

  .spo_chk_exit
    CMP #OBJ_TYPE_EXIT
    BEQ spo_is_exit
    JMP spo_done

  .spo_is_exit
    JMP spo_exit

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

  .spo_button
    ; state bit0 selects x0/x1
    LDA obj_state,Y
    AND #1
    BEQ spo_button0
    LDA #<obj_button_x1
    STA sprite_ptr
    LDA #>obj_button_x1
    STA sprite_ptr+1
    LDA #<obj_button_x1_mask
    STA mask_ptr
    LDA #>obj_button_x1_mask
    STA mask_ptr+1
    JMP spo_button_stamp
  .spo_button0
    LDA #<obj_button_x0
    STA sprite_ptr
    LDA #>obj_button_x0
    STA sprite_ptr+1
    LDA #<obj_button_x0_mask
    STA mask_ptr
    LDA #>obj_button_x0_mask
    STA mask_ptr+1
  .spo_button_stamp
    ; 16x16
    LDA #2
    LDX #32
    LDY #32
    JSR stamp_striped_masked
    PLA
    TAY
    RTS

  .spo_pad
    ; state bit0 selects x0/x1
    LDA obj_state,Y
    AND #1
    BEQ spo_pad0
    LDA #<obj_pad_x1
    STA sprite_ptr
    LDA #>obj_pad_x1
    STA sprite_ptr+1
    LDA #<obj_pad_x1_mask
    STA mask_ptr
    LDA #>obj_pad_x1_mask
    STA mask_ptr+1
    JMP spo_pad_stamp
  .spo_pad0
    LDA #<obj_pad_x0
    STA sprite_ptr
    LDA #>obj_pad_x0
    STA sprite_ptr+1
    LDA #<obj_pad_x0_mask
    STA mask_ptr
    LDA #>obj_pad_x0_mask
    STA mask_ptr+1
  .spo_pad_stamp
    ; 16x16
    LDA #2
    LDX #32
    LDY #32
    JSR stamp_striped_masked
    PLA
    TAY
    RTS

  .spo_exit
    ; state bit0 selects x0/x1 (closed/open)
    LDA obj_state,Y
    AND #1
    BEQ spo_exit0
    LDA #<obj_exit_x1
    STA sprite_ptr
    LDA #>obj_exit_x1
    STA sprite_ptr+1
    LDA #<obj_exit_x1_mask
    STA mask_ptr
    LDA #>obj_exit_x1_mask
    STA mask_ptr+1
    JMP spo_exit_stamp
  .spo_exit0
    LDA #<obj_exit_x0
    STA sprite_ptr
    LDA #>obj_exit_x0
    STA sprite_ptr+1
    LDA #<obj_exit_x0_mask
    STA mask_ptr
    LDA #>obj_exit_x0_mask
    STA mask_ptr+1
  .spo_exit_stamp
    ; 16x32
    LDA #4
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
; Uses Chell + cubes. Clobbers: A,X,temp,temp_y,row_counter,col_counter,screen_ptr,sprite_ptr
.compute_pad_pressed
    ; Default: not pressed.
    LDA #0
    STA col_counter

    ; Quick reject if Chell can't be interacting with this room.
    LDA obj_room,Y
    STA sprite_ptr          ; pad_room

    ; --- Chell stands on pad ---
    LDA char_grounded
    BEQ pad_check_cubes

    LDA sprite_ptr
    CMP current_room
    BNE pad_check_cubes

    ; Chell feet tile_y must match pad_y
    LDA obj_y,Y
    CMP row_counter
    BNE pad_check_cubes

    ; X overlap (2 tiles wide vs 2 tiles wide)
    JSR overlap_2wide_chell_vs_obj
    BCC pad_check_cubes

    LDA #1
    STA col_counter
    JMP pad_done

  .pad_check_cubes
    ; --- Any cube rests on pad ---
    ; Cache pad_x/pad_y in screen_ptr for comparisons.
    LDA obj_x,Y
    STA screen_ptr          ; pad_x
    LDA obj_y,Y
    STA screen_ptr+1        ; pad_y

    LDX #0
  .pad_cube_loop
    LDA obj_type,X
    CMP #OBJ_TYPE_CUBE
    BNE pad_cube_next

    ; Ignore carried cubes.
    LDA obj_state,X
    AND #OBJ_STATE_CARRIED
    BNE pad_cube_next

    ; Same room?
    LDA obj_room,X
    CMP sprite_ptr          ; pad_room
    BNE pad_cube_next

    ; Cube rests on pad if its tile_y matches pad_y.
    ; (Both are 16px tall and sit on the same floor.)
    LDA obj_y,X
    CMP screen_ptr+1
    BNE pad_cube_next

    ; X overlap between cube and pad (both 2-wide)
    JSR overlap_2wide_cube_vs_pad
    BCC pad_cube_next

    LDA #1
    STA col_counter
    JMP pad_done

  .pad_cube_next
    INX
    CPX #OBJ_COUNT
    BNE pad_cube_loop

  .pad_done
    LDA col_counter
    RTS


; Return A=1 if button object Y is pressed, else A=0.
; Press rule (MVP): SPACE edge while Chell overlaps the button zone.
; Clobbers: A,temp,temp_y,row_counter,col_counter,sprite_ptr
.compute_button_pressed
    LDA #0
    STA col_counter

    LDA action_pressed_latch
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
    LDA action_pressed_latch
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
    LDA SOLID_TILE_PLANE,X
    BEQ tpc_tile0_ok
    JMP tpc_fail
  .tpc_tile0_ok
    INX
    LDA SOLID_TILE_PLANE,X
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


; C=1 if cube object X overlaps cached pad_x in screen_ptr.
; Assumes both are 2 tiles wide. Clobbers: A,row_counter
.overlap_2wide_cube_vs_pad
    ; If cube_left >= pad_left+2 => no overlap
    LDA screen_ptr          ; pad_left
    CLC
    ADC #2
    STA row_counter
    LDA obj_x,X
    CMP row_counter
    BCS ovcp_no

    ; If pad_left >= cube_left+2 => no overlap
    LDA obj_x,X
    CLC
    ADC #2
    STA row_counter
    LDA screen_ptr          ; pad_left
    CMP row_counter
    BCS ovcp_no

    SEC
    RTS
  .ovcp_no
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
    JMP rpobj_button

  .rpobj_chk_pad
    CMP #OBJ_TYPE_PAD
    BNE rpobj_chk_exit
    JMP rpobj_pad

  .rpobj_chk_exit
    CMP #OBJ_TYPE_EXIT
    BNE rpobj_not_exit
    JMP rpobj_exit
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

  .rpobj_button
    ; state bit0 selects x0/x1
    LDA obj_state,Y
    AND #1
    BEQ rpobj_button0
    LDA #<obj_button_x1
    STA sprite_ptr
    LDA #>obj_button_x1
    STA sprite_ptr+1
    LDA #<obj_button_x1_mask
    STA mask_ptr
    LDA #>obj_button_x1_mask
    STA mask_ptr+1
    JMP rpobj_button_stamp
  .rpobj_button0
    LDA #<obj_button_x0
    STA sprite_ptr
    LDA #>obj_button_x0
    STA sprite_ptr+1
    LDA #<obj_button_x0_mask
    STA mask_ptr
    LDA #>obj_button_x0_mask
    STA mask_ptr+1
  .rpobj_button_stamp
    ; 16x16
    TYA
    PHA
    LDA #2
    LDX #32
    LDY #32
    JSR stamp_striped_masked
    PLA
    TAY
    JMP rpobj_next

  .rpobj_pad
    ; state bit0 selects x0/x1
    LDA obj_state,Y
    AND #1
    BEQ rpobj_pad0
    LDA #<obj_pad_x1
    STA sprite_ptr
    LDA #>obj_pad_x1
    STA sprite_ptr+1
    LDA #<obj_pad_x1_mask
    STA mask_ptr
    LDA #>obj_pad_x1_mask
    STA mask_ptr+1
    JMP rpobj_pad_stamp
  .rpobj_pad0
    LDA #<obj_pad_x0
    STA sprite_ptr
    LDA #>obj_pad_x0
    STA sprite_ptr+1
    LDA #<obj_pad_x0_mask
    STA mask_ptr
    LDA #>obj_pad_x0_mask
    STA mask_ptr+1
  .rpobj_pad_stamp
    ; 16x16
    TYA
    PHA
    LDA #2
    LDX #32
    LDY #32
    JSR stamp_striped_masked
    PLA
    TAY
    JMP rpobj_next

  .rpobj_exit
    ; state bit0 selects x0/x1 (closed/open)
    LDA obj_state,Y
    AND #1
    BEQ rpobj_exit0
    LDA #<obj_exit_x1
    STA sprite_ptr
    LDA #>obj_exit_x1
    STA sprite_ptr+1
    LDA #<obj_exit_x1_mask
    STA mask_ptr
    LDA #>obj_exit_x1_mask
    STA mask_ptr+1
    JMP rpobj_exit_stamp
  .rpobj_exit0
    LDA #<obj_exit_x0
    STA sprite_ptr
    LDA #>obj_exit_x0
    STA sprite_ptr+1
    LDA #<obj_exit_x0_mask
    STA mask_ptr
    LDA #>obj_exit_x0_mask
    STA mask_ptr+1
  .rpobj_exit_stamp
    ; 16x32
    TYA
    PHA
    LDA #4
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
