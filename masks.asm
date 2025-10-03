; Character mask table - matches character_sprite_table
.character_mask_table
    EQUW chell_standing_mask   ; &0: Matches character_sprite_table[0]
    ; Add more character masks here as needed

; Character mask data
.chell_standing_mask
EQUB &77, &FF, &FF, &FF, &FF, &FF, &FF, &FF,    &88, &CC, &CC, &CC, &88, &88, &88, &88
EQUB &FF, &FF, &FF, &FF, &FF, &FF, &FF, &FF,    &88, &88, &88, &88, &88, &88, &88, &88
EQUB &FF, &FF, &FF, &FF, &FF, &77, &88, &88,    &88, &88, &88, &88, &88, &88, &00, &00
EQUB &77, &77, &77, &77, &77, &77, &77, &77,    &00, &00, &00, &00, &88, &88, &88, &88
