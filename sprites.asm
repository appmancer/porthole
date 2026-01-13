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
; Indices are used by render_character_sprite.
;
; For the demo we use: index = run_frame*4 + subpixel_offset
; - run_frame: 0..2 (1..3)
; - subpixel_offset: 0..3
; We store right-facing first, then left-facing (mirrored).
.character_sprite_table
EQUW chell_run_r1_x0
EQUW chell_run_r1_x1
EQUW chell_run_r1_x2
EQUW chell_run_r1_x3
EQUW chell_run_r2_x0
EQUW chell_run_r2_x1
EQUW chell_run_r2_x2
EQUW chell_run_r2_x3
EQUW chell_run_r3_x0
EQUW chell_run_r3_x1
EQUW chell_run_r3_x2
EQUW chell_run_r3_x3
EQUW chell_run_l1_x0
EQUW chell_run_l1_x1
EQUW chell_run_l1_x2
EQUW chell_run_l1_x3
EQUW chell_run_l2_x0
EQUW chell_run_l2_x1
EQUW chell_run_l2_x2
EQUW chell_run_l2_x3
EQUW chell_run_l3_x0
EQUW chell_run_l3_x1
EQUW chell_run_l3_x2
EQUW chell_run_l3_x3
EQUW test_sprite16x32       ; Debug 16x32 sprite (screen byte order)

; Overlay sprite table (16x16, two stripes). Drawn at Chell Y+16.
; Indices match character_sprite_table for convenience.
.overlay_sprite_table
EQUW chell_rgun_r1_x1
EQUW chell_rgun_r1_x2
EQUW chell_rgun_r1_x3
EQUW chell_rgun_r1_x4
EQUW chell_rgun_r2_x1
EQUW chell_rgun_r2_x2
EQUW chell_rgun_r2_x3
EQUW chell_rgun_r2_x4
EQUW chell_rgun_r3_x1
EQUW chell_rgun_r3_x2
EQUW chell_rgun_r3_x3
EQUW chell_rgun_r3_x4
EQUW chell_rgun_l1_x1
EQUW chell_rgun_l1_x2
EQUW chell_rgun_l1_x3
EQUW chell_rgun_l1_x4
EQUW chell_rgun_l2_x1
EQUW chell_rgun_l2_x2
EQUW chell_rgun_l2_x3
EQUW chell_rgun_l2_x4
EQUW chell_rgun_l3_x1
EQUW chell_rgun_l3_x2
EQUW chell_rgun_l3_x3
EQUW chell_rgun_l3_x4

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
;
; Generated from CSV sources in sprites/.
INCLUDE "sprites/generated_chell_sprites.asm"

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
