; Render-side state + draw helpers.

.run_frame_seq
    EQUB 0,1,0,2

; Draw current body + overlay at screen_ptr.
.draw_character_current
    ; Keep ROMSEL stable during blit (B2/MOS IRQs may page ROMs).
    ; Preserve caller IRQ state (nested callers may already be SEI).
    PHP
    SEI
    LDA ROMSEL
    PHA

    ; Ensure Chell SWRAM bank is visible for reads.
    LDA chell_bank
    STA ROMSEL

    ; Body
    LDA chell_body_index
    JSR render_character_sprite

    ; Overlay
    LDA chell_overlay_index
    JSR render_overlay_sprite

    ; Restore previous ROM selection and caller IRQ state.
    PLA
    STA ROMSEL
    PLP
    RTS

; Draw the current reticle at screen_ptr.
; Reticle sprites live in Chell SWRAM, so we must page the bank in.
.draw_reticle_current
    ; Preserve caller IRQ state (nested callers may already be SEI).
    PHP
    SEI
    LDA ROMSEL
    PHA

    LDA chell_bank
    STA ROMSEL

    LDA reticle_state
    JSR render_reticle_sprite

    PLA
    STA ROMSEL
    PLP
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
    ; Carrying overrides gun overlays.
    LDA carried_cube_idx
    CMP #&FF
    BEQ cs_overlay_not_carrying

    ; Carry overlay: single pose, direction selects right/left base.
    LDA anim_dir
    BNE cs_overlay_carry_right
    LDA #CHELL_OVERLAY_CARRY_LEFT_BASE
    BNE cs_overlay_carry_base_ok
 .cs_overlay_carry_right
    LDA #CHELL_OVERLAY_CARRY_RIGHT_BASE
 .cs_overlay_carry_base_ok
    CLC
    ADC char_pixel_offset
    STA chell_overlay_index
    RTS

 .cs_overlay_not_carrying
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
