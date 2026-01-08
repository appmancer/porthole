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
EQUW chell_frame1           ; &0: Chell (frame1) 16x32, MODE 5 screen-byte order
EQUW test_sprite16x32       ; &1: Test 16x32 sprite (screen byte order)

; Wide 8x16 tile sprite data
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

; Character sprites (screen byte order)
;
; Convention for 16x32 in MODE 5:
; - 4 stripes of 8 scanlines
; - within each stripe: 4 byte-columns × 8 rows
;   (i.e. the BBC's 8x8 block order)
.chell_frame1
    EQUB &00,&00,&10,&10,&10,&10,&00,&30,&00,&E0,&F0,&F0,&C0,&30,&F0,&C0
    EQUB &00,&00,&00,&20,&D0,&C0,&00,&08,&00,&00,&00,&00,&00,&00,&00,&00
    EQUB &70,&40,&10,&30,&20,&10,&10,&10,&03,&0F,&07,&81,&60,&B0,&B0,&B0
    EQUB &0E,&0E,&08,&00,&00,&00,&80,&00,&00,&00,&00,&00,&00,&00,&00,&00
    EQUB &10,&20,&20,&20,&30,&30,&30,&70,&A0,&90,&F0,&F0,&40,&30,&F0,&F0
    EQUB &00,&80,&80,&00,&80,&80,&80,&80,&00,&00,&00,&00,&00,&00,&00,&00
    EQUB &70,&70,&30,&00,&00,&33,&33,&11,&F0,&F0,&F0,&F0,&00,&77,&77,&BB
    EQUB &C0,&C0,&C0,&80,&00,&00,&88,&77,&00,&00,&00,&00,&00,&00,&00,&00

.test_sprite16x32
    ; Stripe 0 (rows 0-7)
    EQUB &FF,&FF,&FF,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF
    EQUB &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF

    ; Stripe 1 (rows 8-15)
    EQUB &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF
    EQUB &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF

    ; Stripe 2 (rows 16-23)
    EQUB &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF
    EQUB &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF

    ; Stripe 3 (rows 24-31)
    EQUB &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF
    EQUB &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&00,&00,&FF,  &FF,&FF,&FF,&FF
