; Character mask table - matches character_sprite_table
.character_mask_table
    EQUW chell_standing_mask   ; &0: Matches character_sprite_table[0]
    EQUW chell_standing_offset_1_pixel_mask
    EQUW chell_standing_offset_2_pixel_mask
    EQUW chell_standing_offset_3_pixel_mask
    EQUW chell_moving_right_1_mask
    ; Add more character masks here as needed

; Character mask data
.chell_standing_mask
EQUB &77, &FF, &FF, &FF, &FF, &FF, &FF, &FF,    &88, &CC, &CC, &CC, &88, &88, &88, &88
EQUB &77, &FF, &FF, &FF, &FF, &FF, &FF, &FF,    &00, &88, &88, &88, &88, &88, &88, &88
EQUB &FF, &FF, &FF, &FF, &FF, &77, &77, &77,    &88, &88, &88, &88, &88, &88, &00, &00
EQUB &77, &77, &77, &77, &77, &77, &77, &77,    &00, &00, &00, &00, &88, &88, &88, &88

.chell_standing_offset_1_pixel_mask
EQUB &33, &77, &77, &77, &77, &77, &77, &77,    &CC, &EE, &EE, &EE, &CC, &CC, &CC, &CC
EQUB &33, &77, &77, &77, &77, &77, &77, &77,    &88, &CC, &CC, &CC, &CC, &CC, &CC, &CC
EQUB &77, &77, &77, &77, &77, &77, &33, &33,    &CC, &CC, &CC, &CC, &CC, &CC, &88, &88
EQUB &33, &33, &33, &33, &33, &33, &33, &33,    &88, &88, &88, &88, &CC, &CC, &CC, &CC

.chell_standing_offset_2_pixel_mask
EQUB &11, &33, &33, &33, &33, &33, &33, &33,    &EE, &FF, &FF, &EE, &EE, &EE, &EE, &EE
EQUB &11, &33, &33, &33, &33, &33, &33, &33,    &CC, &EE, &EE, &EE, &EE, &EE, &EE, &EE
EQUB &33, &33, &33, &33, &33, &11, &11, &11,    &EE, &EE, &EE, &EE, &EE, &EE, &CC, &CC
EQUB &11, &11, &11, &11, &11, &11, &11, &11,    &CC, &CC, &CC, &CC, &EE, &EE, &EE, &EE

.chell_standing_offset_3_pixel_mask
EQUB &00, &11, &11, &11, &11, &11, &11, &11,    &FF, &FF, &FF, &FF, &FF, &FF, &FF, &FF
EQUB &00, &11, &11, &11, &11, &11, &11, &11,    &FF, &FF, &FF, &FF, &FF, &FF, &FF, &FF
EQUB &00, &11, &11, &11, &11, &00, &00, &00,    &FF, &FF, &FF, &FF, &FF, &FF, &EE, &EE
EQUB &00, &00, &00, &00, &00, &00, &00, &00,    &EE, &EE, &EE, &EE, &FF, &FF, &FF, &FF

.chell_moving_right_1_mask
EQUB &11, &11, &33, &33, &33, &33, &33, &33,    &88, &FF, &FF, &FF, &EE, &EE, &EE, &EE
EQUB &33, &33, &33, &33, &33, &77, &77, &77,    &EE, &EE, &EE, &EE, &EE, &FF, &EE, &CC
EQUB &77, &77, &77, &77, &33, &23, &23, &77,    &CC, &CC, &CC, &CC, &CC, &EE, &EE, &EE
EQUB &77, &77, &AE, &AE, &AE, &77, &77, &77,    &EE, &77, &77, &77, &77, &77, &22, &00

