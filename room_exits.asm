.room_exits_start
; room_exits.asm
; Room transitions via edge exits.

; --- Room exits / transitions ---
;
; Uses the active buffer exit tables populated by load_level from the binary pack.
;
; Supports left/right and up/down edge exits.
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
    ; --- Down edge ---
    ; Trigger exits only when Chell is moving into the edge.
    JSR calc_char_y
    CMP #224
    BCC check_up_edge

    ; Require downward intent (vy > 0), allowing a 1-frame grace via char_prev_vy.
    LDA char_vy
    BNE exits_vy_down_have
    LDA char_prev_vy
 .exits_vy_down_have
    BEQ check_up_edge
    BMI check_up_edge

    ; X range match uses Chell's center X cell.
    ; temp := ((x + 8) >> 3)
    JSR calc_char_x
    CLC
    ADC #8
    LSR A
    LSR A
    LSR A
    STA temp

    JSR find_exit_down
    BCC check_up_edge

    ; Enter destination from above. A already holds dst room.
    JSR transition_enter_from_up
    SEC
    RTS

 .check_up_edge
    ; --- Up edge ---
    JSR calc_char_y
    BNE exits_check_right

    ; Require upward intent (vy < 0), allowing a 1-frame grace via char_prev_vy.
    LDA char_vy
    BNE exits_vy_up_have
    LDA char_prev_vy
 .exits_vy_up_have
    BEQ exits_check_right
    BPL exits_check_right

    ; temp := ((x + 8) >> 3)
    JSR calc_char_x
    CLC
    ADC #8
    LSR A
    LSR A
    LSR A
    STA temp

    JSR find_exit_up
    BCC exits_check_right

    ; Enter destination from below. A already holds dst room.
    JSR transition_enter_from_down
    SEC
    RTS

 .exits_check_right
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


; Find matching down-edge exit for current_room.
; Input: temp = center_x_cell
; Output: C=1 and A=dst_room on match, else C=0.
.find_exit_down
    LDX current_room
    LDA exit_down_counts,X
    BEQ find_exit_none
    STA col_counter

    TXA
    ASL A
    TAX
    LDA exit_down_ptrs,X
    STA temp_sprite_ptr
    LDA exit_down_ptrs+1,X
    STA temp_sprite_ptr+1
    JMP find_exit_scan


; Find matching up-edge exit for current_room.
; Input: temp = center_x_cell
; Output: C=1 and A=dst_room on match, else C=0.
.find_exit_up
    LDX current_room
    LDA exit_up_counts,X
    BEQ find_exit_none
    STA col_counter

    TXA
    ASL A
    TAX
    LDA exit_up_ptrs,X
    STA temp_sprite_ptr
    LDA exit_up_ptrs+1,X
    STA temp_sprite_ptr+1
    JMP find_exit_scan


; Room transition helpers.
; Inputs:
; - A = destination room index
; - temp_y = preserved top Y (pixel)
; Preserves velocity; snaps X to the new edge.
.transition_enter_from_left
    PHA
    LDA #0
    STA beam_do_redraw
    JSR unstamp_beam_tiles
    PLA
    STA current_room
    JSR set_room_tilemap
    JSR set_room_fizzlers
    LDA temp_y : PHA             ; save spawn Y across plane rebuild
    JSR build_material_planes_from_tilemap
    PLA : STA temp_y             ; restore spawn Y

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
    PHA
    LDA #0
    STA beam_do_redraw
    JSR unstamp_beam_tiles
    PLA
    STA current_room
    JSR set_room_tilemap
    JSR set_room_fizzlers
    LDA temp_y : PHA             ; save spawn Y across plane rebuild
    JSR build_material_planes_from_tilemap
    PLA : STA temp_y             ; restore spawn Y

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


; Vertical transition helpers.
; Inputs:
; - A = destination room index
; Preserves X (clamped) and horizontal subpixel offsets; snaps Y to the new edge.
.transition_enter_from_up
    PHA
    LDA #0
    STA beam_do_redraw
    JSR unstamp_beam_tiles
    PLA
    STA current_room
    JSR set_room_tilemap
    JSR set_room_fizzlers
    JSR build_material_planes_from_tilemap

    ; Keep X, but clamp left tile_x to 0..14 (Chell is 2 tiles wide).
    LDA char_tile_pos
    AND #15
    CMP #15
    BNE tefu_x_ok
    ; x==15 => clamp to 14 and clear sub offsets.
    LDA char_tile_pos
    AND #&F0
    ORA #14
    STA char_tile_pos
    LDA #0
    STA char_byte_offset
    STA char_pixel_offset
    JMP tefu_y_set
  .tefu_x_ok
    ; keep existing x nibble
    LDA char_tile_pos
    AND #15
    STA temp
    LDA char_tile_pos
    AND #&F0
    ORA temp
    STA char_tile_pos

  .tefu_y_set
    ; Spawn at the top edge.
    LDA char_tile_pos
    AND #15
    STA temp
    LDA #&00
    ORA temp
    STA char_tile_pos
    LDA #0
    STA char_y_offset

    ; Mark for redraw.
    LDA #1
    STA room_dirty
    STA chell_dirty
    ; Clear movement intent so we don't immediately re-trigger exits.
    LDA #0
    STA move_held
    STA last_move_held
    LDA #8
    STA exit_cooldown

    ; If we were fast-falling, restore fall_distance so fast-fall
    ; continues in the new room. (The screen-bottom overflow in
    ; will_collide_down_8 falsely resets it before the exit fires.)
    LDA char_prev_vy
    CMP #2
    BCC tefu_no_fast_fall
    LDA #FALL_FAST_THRESHOLD
    STA fall_distance
  .tefu_no_fast_fall

    ; Cancel reticle.
    LDA #0
    STA reticle_active
    STA reticle_prev_active
    STA reticle_has_under
    STA chell_has_under
    RTS


.transition_enter_from_down
    PHA
    LDA #0
    STA beam_do_redraw
    JSR unstamp_beam_tiles
    PLA
    STA current_room
    JSR set_room_tilemap
    JSR set_room_fizzlers
    JSR build_material_planes_from_tilemap

    ; Keep X, but clamp left tile_x to 0..14 (Chell is 2 tiles wide).
    LDA char_tile_pos
    AND #15
    CMP #15
    BNE tefd_x_ok
    LDA char_tile_pos
    AND #&F0
    ORA #14
    STA char_tile_pos
    LDA #0
    STA char_byte_offset
    STA char_pixel_offset
    JMP tefd_y_set
  .tefd_x_ok
    LDA char_tile_pos
    AND #15
    STA temp
    LDA char_tile_pos
    AND #&F0
    ORA temp
    STA char_tile_pos

  .tefd_y_set
    ; Spawn at the bottom edge (top y = 224 => tile_y = 14).
    LDA char_tile_pos
    AND #15
    STA temp
    LDA #&E0
    ORA temp
    STA char_tile_pos
    LDA #0
    STA char_y_offset

    ; Mark for redraw.
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
