; Character mask table - matches character_sprite_table
.character_mask_table
    EQUW chell_run_r1_x0_mask
    EQUW chell_run_r1_x1_mask
    EQUW chell_run_r1_x2_mask
    EQUW chell_run_r1_x3_mask
    EQUW chell_run_r2_x0_mask
    EQUW chell_run_r2_x1_mask
    EQUW chell_run_r2_x2_mask
    EQUW chell_run_r2_x3_mask
    EQUW chell_run_r3_x0_mask
    EQUW chell_run_r3_x1_mask
    EQUW chell_run_r3_x2_mask
    EQUW chell_run_r3_x3_mask
    EQUW chell_run_l1_x0_mask
    EQUW chell_run_l1_x1_mask
    EQUW chell_run_l1_x2_mask
    EQUW chell_run_l1_x3_mask
    EQUW chell_run_l2_x0_mask
    EQUW chell_run_l2_x1_mask
    EQUW chell_run_l2_x2_mask
    EQUW chell_run_l2_x3_mask
    EQUW chell_run_l3_x0_mask
    EQUW chell_run_l3_x1_mask
    EQUW chell_run_l3_x2_mask
    EQUW chell_run_l3_x3_mask

    EQUW chell_idle_r_x0_mask
    EQUW chell_idle_r_x1_mask
    EQUW chell_idle_r_x2_mask
    EQUW chell_idle_r_x3_mask
    EQUW chell_idle_l_x0_mask
    EQUW chell_idle_l_x1_mask
    EQUW chell_idle_l_x2_mask
    EQUW chell_idle_l_x3_mask

    EQUW chell_jump_r_x0_mask
    EQUW chell_jump_r_x1_mask
    EQUW chell_jump_r_x2_mask
    EQUW chell_jump_r_x3_mask
    EQUW chell_jump_l_x0_mask
    EQUW chell_jump_l_x1_mask
    EQUW chell_jump_l_x2_mask
    EQUW chell_jump_l_x3_mask

    EQUW chell_fall_r_x0_mask
    EQUW chell_fall_r_x0_mask
    EQUW chell_fall_r_x0_mask
    EQUW chell_fall_r_x0_mask
    EQUW chell_fall_l_x0_mask
    EQUW chell_fall_l_x0_mask
    EQUW chell_fall_l_x0_mask
    EQUW chell_fall_l_x0_mask

    EQUW test_sprite16x32_mask

.overlay_mask_table
    EQUW chell_rgun_r1_x0_mask
    EQUW chell_rgun_r1_x1_mask
    EQUW chell_rgun_r1_x2_mask
    EQUW chell_rgun_r1_x3_mask
    EQUW chell_rgun_r2_x0_mask
    EQUW chell_rgun_r2_x1_mask
    EQUW chell_rgun_r2_x2_mask
    EQUW chell_rgun_r2_x3_mask
    EQUW chell_rgun_r3_x0_mask
    EQUW chell_rgun_r3_x1_mask
    EQUW chell_rgun_r3_x2_mask
    EQUW chell_rgun_r3_x3_mask
    EQUW chell_rgun_l1_x0_mask
    EQUW chell_rgun_l1_x1_mask
    EQUW chell_rgun_l1_x2_mask
    EQUW chell_rgun_l1_x3_mask
    EQUW chell_rgun_l2_x0_mask
    EQUW chell_rgun_l2_x1_mask
    EQUW chell_rgun_l2_x2_mask
    EQUW chell_rgun_l2_x3_mask
EQUW chell_rgun_l3_x0_mask
EQUW chell_rgun_l3_x1_mask
EQUW chell_rgun_l3_x2_mask
EQUW chell_rgun_l3_x3_mask

; Carrying cube overlays (single pose), right then left.
EQUW chell_carry_r_x0_mask
EQUW chell_carry_r_x1_mask
EQUW chell_carry_r_x2_mask
EQUW chell_carry_r_x3_mask
EQUW chell_carry_l_x0_mask
EQUW chell_carry_l_x1_mask
EQUW chell_carry_l_x2_mask
EQUW chell_carry_l_x3_mask

.reticle_mask_table
EQUW reticle_x0_mask
EQUW reticle_x1_mask


; Masks for generated character sprites.
; Chell masks are now loaded into sideways RAM at runtime (see `main.asm`).
; Blitter does: dst = (dst & mask) | pix
; So mask should be &FF where pix is transparent (keep background)
; and &00 where pix is opaque (replace).

; Mask for test 16x32 sprite in screen byte order (128 bytes).
.test_sprite16x32_mask
    ; Stripe 0 (rows 0-7)
    EQUB &00,&00,&00,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00
    EQUB &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00

    ; Stripe 1 (rows 8-15)
    EQUB &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00
    EQUB &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00

    ; Stripe 2 (rows 16-23)
    EQUB &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00
    EQUB &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00

    ; Stripe 3 (rows 24-31)
    EQUB &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00
    EQUB &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&FF,&FF,&00,  &00,&00,&00,&00
