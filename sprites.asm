; Room tile sprites (8x16 cells).
; Generated from `sprites/NewTiles - Grid.csv`.
INCLUDE "sprites/generated_tiles.asm"

; Character sprite table - separate from room tiles.
; Indices are used by render_character_sprite.
;
; Layout:
; - Run: 3 frames * 4 subpixel shifts, right then left
; - Idle: 1 frame * 4 shifts, right then left
; - Jump: 1 frame * 4 shifts, right then left
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

; Idle pose (single frame).
EQUW chell_idle_r_x0
EQUW chell_idle_r_x1
EQUW chell_idle_r_x2
EQUW chell_idle_r_x3
EQUW chell_idle_l_x0
EQUW chell_idle_l_x1
EQUW chell_idle_l_x2
EQUW chell_idle_l_x3

; Jump pose (single frame), used while airborne.
EQUW chell_jump_r_x0
EQUW chell_jump_r_x1
EQUW chell_jump_r_x2
EQUW chell_jump_r_x3
EQUW chell_jump_l_x0
EQUW chell_jump_l_x1
EQUW chell_jump_l_x2
EQUW chell_jump_l_x3

EQUW test_sprite16x32       ; Debug 16x32 sprite (screen byte order)

; Overlay sprite table (16x16, two stripes). Drawn at Chell Y+16.
; Indices match character_sprite_table for convenience.
.overlay_sprite_table
EQUW chell_rgun_r1_x0
EQUW chell_rgun_r1_x1
EQUW chell_rgun_r1_x2
EQUW chell_rgun_r1_x3
EQUW chell_rgun_r2_x0
EQUW chell_rgun_r2_x1
EQUW chell_rgun_r2_x2
EQUW chell_rgun_r2_x3
EQUW chell_rgun_r3_x0
EQUW chell_rgun_r3_x1
EQUW chell_rgun_r3_x2
EQUW chell_rgun_r3_x3
EQUW chell_rgun_l1_x0
EQUW chell_rgun_l1_x1
EQUW chell_rgun_l1_x2
EQUW chell_rgun_l1_x3
EQUW chell_rgun_l2_x0
EQUW chell_rgun_l2_x1
EQUW chell_rgun_l2_x2
EQUW chell_rgun_l2_x3
EQUW chell_rgun_l3_x0
EQUW chell_rgun_l3_x1
EQUW chell_rgun_l3_x2
EQUW chell_rgun_l3_x3

; Carrying cube overlays (single pose), right then left.
EQUW chell_carry_r_x0
EQUW chell_carry_r_x1
EQUW chell_carry_r_x2
EQUW chell_carry_r_x3
EQUW chell_carry_l_x0
EQUW chell_carry_l_x1
EQUW chell_carry_l_x2
EQUW chell_carry_l_x3

; Reticle sprites (16x16). Generated from `sprites/Reticles - Reference.csv`.
; reticle_x0 = blocked/unportalable, reticle_x1 = portalable.
.reticle_sprite_table
EQUW reticle_x0
EQUW reticle_x1

; Character sprites (screen byte order)
;
; Convention for 16x32 in MODE 5:
; - 4 stripes of 8 scanlines
; - within each stripe: 4 byte-columns × 8 rows
;   (i.e. the BBC's 8x8 block order)
;
; Generated from CSV sources in sprites/.
; Chell sprites are now loaded into sideways RAM at runtime (see `main.asm`).

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
