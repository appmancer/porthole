; persistent_objects.asm
; Persistent level-global objects + signals.
;
; This file is included from `main.asm` near the portal stamping code, so label
; addresses stay stable.

; --- Persistent objects + signals ---
;
; Runtime object arrays are indexed by obj_index (0..OBJ_COUNT-1), initialized
; once from `.obj_defs` emitted by `tools/gen-level`.

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

    ; Cache footprint top-left.
    LDA obj_x,Y
    STA row_counter          ; x
    LDA obj_y,Y
    STA temp_y               ; y
    LDA obj_type,Y
    STA col_counter          ; type

    ; Row 0: (x,y) and (x+1,y)
    LDX row_counter
    LDA temp_y
    JSR redraw_tile_xy

    LDX row_counter
    CPX #15
    BEQ apou_maybe_row1
    INX
    LDA temp_y
    JSR redraw_tile_xy

  .apou_maybe_row1
    ; Exit is 16x32, so also redraw the row below.
    LDA col_counter
    CMP #OBJ_TYPE_EXIT
    BNE apou_redraw_restore

    ; If already on bottom tile row, there's no valid second row to redraw.
    LDA temp_y
    CMP #15
    BEQ apou_redraw_restore

    ; Row 1: (x,y+1) and (x+1,y+1)
    CLC
    ADC #1
    LDX row_counter
    JSR redraw_tile_xy

    LDX row_counter
    CPX #15
    BEQ apou_redraw_restore
    INX
    LDA temp_y
    JSR redraw_tile_xy

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
    CLI

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

    ; Same room?
    LDA obj_room,X
    CMP sprite_ptr          ; pad_room
    BNE pad_cube_next

    ; Cube bottom tile_y must match pad_y.
    LDA obj_y,X
    CLC
    ADC #1
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
    CLI
    RTS
