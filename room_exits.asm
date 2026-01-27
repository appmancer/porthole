; room_exits.asm
; Room transitions via edge exits.

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
