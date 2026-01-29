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

    INX
    CPX #OBJ_COUNT
    BNE ipo_next
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

    ; Cache footprint top-left and lookup footprint size.
    ; Note: redraw_tile_xy -> render_cell8x16 clobbers sprite_ptr, so keep the
    ; base coords in temp_sprite_ptr.
    LDA obj_x,Y
    STA temp_sprite_ptr      ; base_x
    LDA obj_y,Y
    STA temp_sprite_ptr+1    ; base_y

    LDX obj_type,Y
    LDA obj_redraw_w_tiles,X
    STA mask_ptr             ; w
    LDA obj_redraw_h_tiles,X
    STA mask_ptr+1           ; h

    ; Redraw tiles in the footprint, clamped to the 16x16 tile grid.
    ; Outer: dy (Y), inner: dx (X). Preserve dx/dy across redraw_tile_xy.
    LDY #0
  .apou_dy_loop
    CPY mask_ptr+1
    BCS apou_redraw_restore

    ; y_cur = base_y + dy; stop if off bottom.
    TYA
    CLC
    ADC temp_sprite_ptr+1
    CMP #16
    BCS apou_redraw_restore
    STA col_counter          ; y_cur

    LDX #0
  .apou_dx_loop
    CPX mask_ptr
    BCS apou_next_row

    ; x_cur = base_x + dx; stop row if off right.
    TXA
    CLC
    ADC temp_sprite_ptr
    CMP #16
    BCS apou_next_row
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
    JMP apou_dx_loop

  .apou_next_row
    INY
    JMP apou_dy_loop

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

    ; Stamp just this object.
    JSR stamp_persistent_object

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
; - Drop: attempts to place the cube on Chell's feet tile_y, in front of Chell if possible.
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

    ; Try drop candidates: in front, behind, then aligned.
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

    ; candidate1: behind
    LDA anim_dir
    BEQ hcpd_cand1_left
    ; facing right => behind is chell_x - 2
    LDA temp
    SEC
    SBC #2
    JMP hcpd_try_place2
  .hcpd_cand1_left
    ; facing left => behind is chell_x + 2
    LDA temp
    CLC
    ADC #2
  .hcpd_try_place2
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
