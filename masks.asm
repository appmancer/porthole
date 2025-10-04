; Character mask table - matches character_sprite_table
.character_mask_table
    EQUW chell_standing_mask   ; &0: Matches character_sprite_table[0]
    EQUW chell_moving_right_1_mask
    ; Add more character masks here as needed

; Character mask data
.chell_standing_mask
EQUB &77, &FF, &FF, &FF, &FF, &FF, &FF, &FF,    &88, &CC, &CC, &CC, &88, &88, &88, &88
EQUB &77, &FF, &FF, &FF, &FF, &FF, &FF, &FF,    &00, &88, &88, &88, &88, &88, &88, &88
EQUB &FF, &FF, &FF, &FF, &FF, &77, &77, &77,    &88, &88, &88, &88, &88, &88, &00, &00
EQUB &77, &77, &77, &77, &77, &77, &77, &77,    &00, &00, &00, &00, &88, &88, &88, &88

.chell_moving_right_1_mask
EQUB &11, &11, &33, &33, &33, &33, &33, &33,    &88, &FF, &FF, &FF, &EE, &EE, &EE, &EE
EQUB &33, &33, &33, &33, &33, &77, &77, &77,    &EE, &EE, &EE, &EE, &EE, &FF, &EE, &CC
EQUB &77, &77, &77, &77, &33, &23, &23, &77,    &CC, &CC, &CC, &CC, &CC, &EE, &EE, &EE
EQUB &77, &77, &AE, &AE, &AE, &77, &77, &77,    &EE, &77, &77, &77, &77, &77, &22, &00

