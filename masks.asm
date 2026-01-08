; Character mask table - matches character_sprite_table
.character_mask_table
    EQUW chell_frame1_mask
    EQUW test_sprite16x32_mask
    ; Add more character masks here as needed

; Mask for Chell frame1 16x32 sprite in screen byte order (128 bytes).
; Blitter does: dst = (dst & mask) | pix
; So mask should be &FF where pix is transparent (keep background)
; and &00 where pix is opaque (replace).
.chell_frame1_mask
    EQUB &FF,&EE,&CC,&CC,&CC,&CC,&CC,&88,&11,&00,&00,&00,&00,&00,&00,&00
    EQUB &FF,&FF,&55,&00,&00,&11,&11,&11,&FF,&FF,&FF,&FF,&FF,&FF,&FF,&FF
    EQUB &00,&00,&88,&88,&88,&CC,&CC,&CC,&00,&00,&00,&00,&00,&00,&00,&00
    EQUB &00,&00,&11,&77,&77,&77,&33,&77,&FF,&FF,&FF,&FF,&FF,&FF,&FF,&FF
    EQUB &CC,&88,&88,&88,&88,&88,&88,&00,&00,&00,&00,&00,&00,&00,&00,&00
    EQUB &77,&33,&33,&77,&33,&33,&33,&33,&FF,&FF,&FF,&FF,&FF,&FF,&FF,&FF
    EQUB &00,&00,&88,&CC,&CC,&88,&88,&CC,&00,&00,&00,&00,&00,&00,&00,&00
    EQUB &11,&11,&11,&33,&77,&77,&33,&33,&FF,&FF,&FF,&FF,&FF,&FF,&FF,&FF

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
