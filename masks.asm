; Character mask table - matches character_sprite_table
.character_mask_table
    EQUW chell_pos1_x0_mask
    EQUW chell_pos1_x1_mask
    EQUW chell_pos1_x2_mask
    EQUW chell_pos1_x3_mask
    EQUW chell_pos2_x0_mask
    EQUW chell_pos2_x1_mask
    EQUW chell_pos2_x2_mask
    EQUW chell_pos2_x3_mask
    EQUW test_sprite16x32_mask
    ; Add more character masks here as needed

; Masks for generated character sprites.
; Blitter does: dst = (dst & mask) | pix
; So mask should be &FF where pix is transparent (keep background)
; and &00 where pix is opaque (replace).
INCLUDE "sprites/generated_chell_masks.asm"

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
