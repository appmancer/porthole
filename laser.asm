.laser_start
; laser.asm — Laser beam system.
;
; Stage 1: data infrastructure only. Beam tiles are pre-authored in tilemaps.
; Future stages add target signal activation (Stage 2) and portal
; redirection (Stage 3).
;
; Generated tables (from tools/gen-level):
;   laser_defs:  LASER_COUNT entries of LASER_DEF_SIZE bytes each
;                (room, wall_tile_x, wall_tile_y, dir, channel)
;   target_defs: TARGET_COUNT entries of TARGET_DEF_SIZE bytes each
;                (room, tile_x, tile_y, channel)

; Initialize beam runtime state from generated laser/target tables.
; Called once at level load.
; Clobbers: none
.init_beams
    ; Stage 1: no runtime state to initialize.
    ; laser_defs and target_defs are read directly from generated tables.
    RTS
