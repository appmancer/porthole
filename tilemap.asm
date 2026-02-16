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
; Must be page-aligned so (zp),Y with Y=0..255 covers exactly one room.
ALIGN 256
.tilemap_buffers        SKIP MAX_ROOMS * 256


; load_level: copy level header into the active buffer, then
; RLE-decompress each room's tilemap into tilemap_buffers and
; patch room_pointers to point to the decompressed data.
;
; Input: current_level set (0..LEVEL_COUNT-1).
; Clobbers: A,X,Y,temp,temp_sprite_ptr,temp_mask_ptr
.load_level
    ; --- Phase 1: memcpy header into active buffer ---
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

    ; --- Phase 2: decompress tilemaps + patch room_pointers ---
    ; For each room slot 0..MAX_ROOMS-1:
    ;   1. Set temp_sprite_ptr = room_pointers[i] (RLE source)
    ;   2. Set temp_mask_ptr = tilemap_buffers + i*256 (destination)
    ;   3. Call rle_decompress
    ;   4. Patch room_pointers[i] = temp_mask_ptr start
    LDY #0                      ; Y = room slot index * 2
.ll_room_loop
    ; Source: room_pointers[Y] (16-bit, already in active buffer).
    LDA room_pointers,Y
    STA temp_sprite_ptr
    LDA room_pointers+1,Y
    STA temp_sprite_ptr+1

    ; Destination: tilemap_buffers + slot*256.
    ; slot = Y/2, so hi byte = >tilemap_buffers + slot.
    TYA
    PHA                         ; save pointer-table offset on stack
    LSR A                       ; slot index (0..7)
    CLC
    ADC #>tilemap_buffers
    STA temp_mask_ptr+1
    LDA #<tilemap_buffers
    STA temp_mask_ptr

    ; Decompress.
    JSR rle_decompress

    ; Patch room_pointers[slot] to point to the decompressed buffer.
    PLA                         ; restore pointer-table offset
    TAY
    LDA temp_mask_ptr
    STA room_pointers,Y
    LDA temp_mask_ptr+1
    STA room_pointers+1,Y

    ; Next room slot.
    INY
    INY
    CPY #MAX_ROOMS * 2
    BNE ll_room_loop
    RTS


; rle_decompress: decompress RLE byte-pair stream into a 256-byte buffer.
;
; Format: [count][tile_id] pairs. Emits `count` copies of `tile_id`.
; Stops when 256 tiles have been written (Y wraps from &FF to &00).
;
; Input:  temp_sprite_ptr = source (RLE data)
;         temp_mask_ptr   = destination (256-byte buffer)
; Output: temp_sprite_ptr advanced past consumed data
; Clobbers: A,X,Y,temp
.rle_decompress
    LDY #0                      ; output index (0..255)
.rle_pair
    ; Read [count][tile] pair via temp index.
    STY temp                    ; save output index
    LDY #0
    LDA (temp_sprite_ptr),Y    ; count
    TAX                         ; X = run length
    INY
    LDA (temp_sprite_ptr),Y    ; tile_id
    ; Advance source pointer by 2.
    CLC
    PHA
    LDA temp_sprite_ptr
    ADC #2
    STA temp_sprite_ptr
    BCC rle_no_carry
    INC temp_sprite_ptr+1
.rle_no_carry
    PLA                         ; A = tile_id
    LDY temp                    ; restore output index
    ; Fill X copies of A into destination.
.rle_fill
    STA (temp_mask_ptr),Y
    INY
    BEQ rle_done                ; Y wrapped to 0: 256 tiles written
    DEX
    BNE rle_fill
    BEQ rle_pair                ; unconditional — next pair
.rle_done
    RTS
