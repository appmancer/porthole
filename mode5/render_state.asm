.render_state_start
; Render-side state + draw helpers.

.run_frame_seq
    EQUB 0,1,0,2

; Save background + draw body + overlay at screen_ptr (merged).
;
; Merges save_chell_under + masked body blit into one pass, saving an
; entire 128-byte screen traversal (~2,600 cycles / ~20 scanlines).
; Then draws the overlay using the existing render_overlay_sprite.
;
; Input: screen_ptr = Chell top-left screen address
;        chell_body_index, chell_overlay_index = precomputed
; Preserves: screen_ptr
.save_and_draw_character_current
    PHP
    SEI
    LDA &F4 : PHA             ; save MOS ROMSEL shadow
    LDA chell_bank
    STA &F4 : STA ROMSEL

    ; Save buffer pointer.
    LDA #<(CHELL_SAVE_UNDER_BASE)
    STA temp_mask_ptr
    LDA #>(CHELL_SAVE_UNDER_BASE)
    STA temp_mask_ptr+1

    ; Body sprite + mask pointers (from SWRAM bank).
    LDA chell_body_index
    ASL A : TAX
    LDA character_sprite_table,X   : STA sprite_ptr
    LDA character_sprite_table+1,X : STA sprite_ptr+1
    LDA character_mask_table,X     : STA mask_ptr
    LDA character_mask_table+1,X   : STA mask_ptr+1

    JSR shadow_screen_on

    ; --- Merged save-under + masked body blit (4 stripes × 32 bytes) ---
    LDX #0
.sadc_stripe
    LDY #0
.sadc_byte
    ; Save screen byte to buffer.
    LDA (screen_ptr),Y
    STA (temp_mask_ptr),Y

    ; Masked blit: same logic as plot_sprite12x32_masked_striped.
    LDA (mask_ptr),Y
    BEQ sadc_opaque
    CMP #&FF
    BEQ sadc_maybe_transparent

    ; Partial mask: screen = (screen AND mask) OR sprite.
    STA temp
    LDA (screen_ptr),Y
    AND temp
    ORA (sprite_ptr),Y
    STA (screen_ptr),Y
    JMP sadc_next

.sadc_opaque
    LDA (sprite_ptr),Y
    STA (screen_ptr),Y
    JMP sadc_next

.sadc_maybe_transparent
    LDA (sprite_ptr),Y
    BEQ sadc_next
    ORA (screen_ptr),Y
    STA (screen_ptr),Y

.sadc_next
    INY
    CPY #32
    BNE sadc_byte

    ; Advance to next stripe.
    INC screen_ptr+1

    LDA sprite_ptr
    CLC : ADC #32 : STA sprite_ptr
    BCC sadc_sp_ok : INC sprite_ptr+1
.sadc_sp_ok
    LDA mask_ptr
    CLC : ADC #32 : STA mask_ptr
    BCC sadc_mp_ok : INC mask_ptr+1
.sadc_mp_ok
    LDA temp_mask_ptr
    CLC : ADC #32 : STA temp_mask_ptr
    BCC sadc_bp_ok : INC temp_mask_ptr+1
.sadc_bp_ok
    INX
    CPX #4
    BNE sadc_stripe

    ; Restore screen_ptr (advanced 4 stripes).
    LDA screen_ptr+1
    SEC : SBC #4
    STA screen_ptr+1

    JSR shadow_screen_off

    ; --- Overlay (reuses existing routine; toggles shadow internally) ---
    LDA char_dead
    BNE sadc_no_overlay
    LDA chell_overlay_index
    JSR render_overlay_sprite
.sadc_no_overlay

    PLA : STA &F4 : STA ROMSEL
    PLP
    RTS

; Draw the current reticle at screen_ptr.
; Reticle sprites live in Chell SWRAM, so we must page the bank in.
.draw_reticle_current
    ; Preserve caller IRQ state (nested callers may already be SEI).
    PHP
    SEI
    LDA &F4 : PHA             ; save MOS ROMSEL shadow

    LDA chell_bank
    STA &F4 : STA ROMSEL      ; update both shadow and register

    LDA reticle_state
    JSR render_reticle_sprite

    PLA : STA &F4 : STA ROMSEL
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

    ; Dead: show dead sprite, no overlay.
    LDA char_dead
    BEQ cs_alive
    LDA #CHELL_DEAD_BASE
    STA chell_body_index
    LDA #0
    STA chell_overlay_index
    RTS
  .cs_alive

    ; --- Body sprite index ---
    ; Default to idle pose; overwritten below.
    LDA char_grounded
    BNE cs_grounded

    ; Airborne: jump pose unless we've committed to a fall (vy threshold).
    ; Rising (vy negative) always uses jump.
    LDA char_vy
    BMI cs_air_jump
    CMP #FALL_POSE_VY_THRESHOLD
    BCC cs_air_jump

    ; Fall pose.
    LDA anim_dir
    BNE cs_fall_right
    LDA #CHELL_FALL_LEFT_BASE
    BNE cs_body_base_no_subpixel
 .cs_fall_right
    LDA #CHELL_FALL_RIGHT_BASE
    BNE cs_body_base_no_subpixel

 .cs_air_jump
    ; Jump pose.
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
    JMP cs_overlay_start

  .cs_body_base_no_subpixel
    ; Falling pose: ignore char_pixel_offset (fall is visually straight down).
    STA chell_body_index
    JMP cs_overlay_start

    ; --- Overlay sprite index ---
  .cs_overlay_start
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
    ; Airborne always uses gun-forward overlay.
    ; Grounded idle can aim up/down via aim_held.
    LDA char_grounded
    BEQ cs_overlay_forward_noaim

    ; Grounded idle: allow up/down aim overlays.
    ; aim_held: 0=none, 1=up, 2=down
    LDA aim_held
    BEQ cs_overlay_idle_aimframe_ok
    CMP #2
    BNE cs_overlay_idle_aim_up
    LDA #1
    BNE cs_overlay_idle_aimframe_ok
 .cs_overlay_idle_aim_up
    LDA #2
 .cs_overlay_idle_aimframe_ok
    ASL A
    ASL A
    STA temp

    ; Facing left adds 12.
    LDA anim_dir
    BNE cs_overlay_idle_dir_ok
    LDA temp
    CLC
    ADC #CHELL_RUN_LEFT_BASE
    STA temp
 .cs_overlay_idle_dir_ok

    LDA temp
    CLC
    ADC char_pixel_offset
    STA chell_overlay_index
    RTS

 .cs_overlay_forward_noaim
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


; XOR horizontal line across cells (sentry bullet visual effect).
; Must live below &3000 for shadow screen access.
; Input: screen_ptr = left byte of first cell at target scanline
;        col_counter = number of cells to span
;        temp_y = color byte (&0F or &FF)
; Clobbers: A, Y, screen_ptr, col_counter
.xor_hline
    JSR shadow_screen_on
.xhl_loop
    LDY #0
    LDA (screen_ptr),Y
    EOR temp_y
    STA (screen_ptr),Y
    LDY #8
    LDA (screen_ptr),Y
    EOR temp_y
    STA (screen_ptr),Y
    ; Next cell: +16 bytes
    LDA screen_ptr
    CLC : ADC #16
    STA screen_ptr
    BCC xhl_nc
    INC screen_ptr+1
.xhl_nc
    DEC col_counter
    BNE xhl_loop
    JSR shadow_screen_off
    RTS
