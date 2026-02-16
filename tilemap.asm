.tilemap_data_start
; tilemap.asm
;
; Level data + active buffer for multi-level support.
;
; All levels are included with prefixed labels. At level load time,
; `load_level` memcpy's the selected level's header block into the
; active buffer. Game code references the active buffer labels unchanged.

; Global constants (max across all levels).
LEVEL_COUNT = 5
MAX_ROOMS = 8
OBJ_COUNT = 6
OBJ_DEF_SIZE = 6
LASER_COUNT = 1
LASER_DEF_SIZE = 7
TARGET_COUNT = 1
TARGET_DEF_SIZE = 4
FIZZLER_DEF_SIZE = 5

; Header block size: sum of all fields in the active buffer.
; With MAX_ROOMS=8: 1+1 + 16 + 24*4 + 36 + 24 + 7 + 4 + 24 = 209
LEVEL_HEADER_SIZE = 1 + 1 + (MAX_ROOMS*2) + (MAX_ROOMS + MAX_ROOMS*2)*4 + (OBJ_COUNT*OBJ_DEF_SIZE) + (MAX_ROOMS + MAX_ROOMS*2) + (LASER_COUNT*LASER_DEF_SIZE) + (TARGET_COUNT*TARGET_DEF_SIZE) + (MAX_ROOMS + MAX_ROOMS*2)

; Include all level data files (prefixed labels).
INCLUDE "levels/generated_level1.asm"
INCLUDE "levels/generated_level2.asm"
INCLUDE "levels/generated_level3.asm"
INCLUDE "levels/generated_level4.asm"
INCLUDE "levels/generated_level5.asm"

; Level header pointer table (indexed by current_level).
.level_header_ptrs
    EQUW level1_header
    EQUW level2_header
    EQUW level3_header
    EQUW level4_header
    EQUW level5_header

; ================================================================
; Active buffer — game code references these labels.
; Order must exactly match the header block emitted by gen-level.
; ================================================================
.level_start_room_buf   SKIP 1
.level_start_pos_buf    SKIP 1
.room_pointers          SKIP MAX_ROOMS * 2
.exit_left_counts       SKIP MAX_ROOMS
.exit_left_ptrs         SKIP MAX_ROOMS * 2
.exit_right_counts      SKIP MAX_ROOMS
.exit_right_ptrs        SKIP MAX_ROOMS * 2
.exit_up_counts         SKIP MAX_ROOMS
.exit_up_ptrs           SKIP MAX_ROOMS * 2
.exit_down_counts       SKIP MAX_ROOMS
.exit_down_ptrs         SKIP MAX_ROOMS * 2
.obj_defs               SKIP OBJ_COUNT * OBJ_DEF_SIZE
.obj_room_counts        SKIP MAX_ROOMS
.obj_room_ptrs          SKIP MAX_ROOMS * 2
.laser_defs             SKIP LASER_COUNT * LASER_DEF_SIZE
.target_defs            SKIP TARGET_COUNT * TARGET_DEF_SIZE
.fizzler_room_counts    SKIP MAX_ROOMS
.fizzler_room_ptrs      SKIP MAX_ROOMS * 2

; Decompressed tilemap buffers — one 256-byte flat tilemap per room.
; room_pointers entries are patched at load time to point here.
; Game code reads/writes via (tilemap_ptr),Y unchanged.
.tilemap_buffers        SKIP MAX_ROOMS * 256


; load_level: copy level header into the active buffer.
; Input: current_level set (0..LEVEL_COUNT-1).
; Clobbers: A,X,Y,temp_sprite_ptr
.load_level
    LDA current_level
    ASL A
    TAX
    LDA level_header_ptrs,X
    STA temp_sprite_ptr
    LDA level_header_ptrs+1,X
    STA temp_sprite_ptr+1
    LDY #0
.ll_copy
    LDA (temp_sprite_ptr),Y
    STA level_start_room_buf,Y
    INY
    CPY #LEVEL_HEADER_SIZE
    BNE ll_copy
    RTS
