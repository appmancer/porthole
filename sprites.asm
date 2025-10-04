.sprite_table
EQUW largebrick ; todo - this should be the blank tile
EQUW largebrick        ; &1
EQUW smallbrick        ; &2
EQUW boulder_left      ; &3
EQUW boulder_right     ; &4
EQUW corner_top_left   ; &5
EQUW side_wall         ; &6
EQUW corner_bottom_left; &7
EQUW floor             ; &8
EQUW ceiling           ; &9
EQUW metalplate        ; &A
EQUW corner_bottom_right;&B
EQUW corner_top_right   ;&C

; Character sprite table - separate from room tiles
.character_sprite_table
EQUW chell_standing    ; &0: Chell standing animation
EQUW chell_moving_right_1 ; &1: Chell moving right animation frame 1
; Add more character sprites here as needed

; Wide 8x16 sprite data 
.sprite_data
.largebrick ; &1
EQUB &1F, &1F, &1F, &1F, &1F, &1F, &1F, &FF, &0F, &0F, &0F, &0F, &0F, &0F, &0F, &FF
EQUB &0F, &0F, &0F, &0F, &0F, &0F, &0F, &FF, &1F, &1F, &1F, &1F, &1F, &1F, &1F, &FF
.smallbrick ; &2
EQUB &2D, &2D, &2D, &F0, &0F, &0F, &0F, &F0, &0F, &0F, &0F, &F0, &4B, &4B, &4B, &F0
EQUB &2D, &2D, &2D, &F0, &0F, &0F, &0F, &F0, &0F, &0F, &0F, &F0, &4B, &4B, &4B, &F0
.boulder_left ; &3
EQUB &00, &00, &00, &11, &23, &57, &47, &57, &00, &00, &00, &FF, &0F, &FF, &0F, &6F
EQUB &8F, &8F, &AF, &AF, &CC, &8F, &AF, &8F, &0F, &0F, &0F, &0F, &0F, &0F, &0F, &0F
.boulder_right ; &4
EQUB &00, &00, &00, &FF, &0F, &BF, &07, &07, &00, &00, &00, &88, &4C, &2E, &0F, &0F
EQUB &0F, &0F, &0F, &3F, &0F, &0F, &0F, &0F, &0F, &1F, &1F, &3F, &1F, &3F, &1F, &3F
.corner_top_left   ; &5
EQUB &AA, &5D, &AE, &5F, &AF, &5F, &AF, &5F, &AA, &55, &AA, &55, &AA, &55, &AA, &5D
EQUB &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F, &AA, &5D, &AE, &5D, &AE, &5F, &AE, &5F
.side_wall ; &6
EQUB &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F
EQUB &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F
.corner_bottom_left; &7
EQUB &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F,    &AE, &5E, &AC, &5C, &AC, &58, &A8, &50
EQUB &AF, &5E, &AE, &5C, &AC, &58, &A0, &50,    &A0, &50, &A0, &50, &A0, &50, &A0, &50
.floor ; &8
EQUB &A0, &50, &A0, &50, &A0, &50, &A0, &50,    &A0, &50, &A0, &50, &A0, &50, &A0, &50
EQUB &A0, &50, &A0, &50, &A0, &50, &A0, &50,    &A0, &50, &A0, &50, &A0, &50, &A0, &50
.ceiling ; &9
EQUB &AA, &55, &AA, &55, &AA, &55, &AA, &55, &AA, &55, &AA, &55, &AA, &55, &AA, &55
EQUB &AA, &55, &AA, &55, &AA, &55, &AA, &55, &AA, &55, &AA, &55, &AA, &55, &AA, &55
.metalplate ; &A
EQUB &FF, &FF, &8F, &8F, &8F, &8F, &8F, &8F, &FF, &FF, &1E, &1E, &1E, &1E, &1E, &1E 
EQUB &8F, &8F, &8F, &8F, &8F, &8F, &F0, &F0, &1E, &1E, &1E, &1E, &1E, &1E, &F0, &F0
.corner_bottom_right ;&B
EQUB &AF, &D7, &EB, &D7, &EB, &F5, &EB, &F5, &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F
EQUB &FA, &F5, &FA, &F5, &FA, &F5, &FA, &F5, &AF, &5F, &AF, &D7, &EB, &F5, &EB, &F5
.corner_top_right ;&C
EQUB &AA, &55, &AA, &55, &AA, &55, &AA, &55, &AB, &55, &AB, &57, &AF, &57, &AF, &5F
EQUB &AA, &55, &AB, &55, &AB, &57, &AF, &57, &AF, &5F, &AF, &5F, &AF, &5F, &AF, &5F

.character_sprites
; Each character is 8x16 pixels (2 wide sprites)
.chell_standing
EQUB &77, &CF, &8F, &9E, &AC, &BC, &BC, &BC,   &88, &CC, &4C, &CC, &88, &88, &88, &88
EQUB &75, &8F, &8F, &AD, &AD, &AD, &AD, &AD,   &00, &88, &88, &88, &88, &88, &88, &88
EQUB &AD, &8F, &8F, &8F, &FF, &57, &57, &57,   &88, &88, &88, &88, &88, &88, &00, &00
EQUB &57, &57, &57, &57, &57, &47, &47, &77,   &00, &00, &00, &00, &88, &88, &88, &88

.chell_moving_right_1
EQUB &11, &21, &23, &23, &23, &23, &23, &23,    &88, &3F, &1F, &7B, &A2, &E2, &E2, &E2
EQUB &33, &23, &23, &23, &23, &76, &56, &AD,    &E6, &2E, &2E, &A6, &A6, &3D, &6E, &C4
EQUB &47, &47, &47, &47, &33, &23, &23, &47,    &4C, &4C, &4C, &4C, &CC, &AE, &AE, &AE
EQUB &57, &57, &AE, &AE, &AE, &57, &57, &77,    &AE, &57, &57, &57, &57, &57, &22, &00
