.tilemap_data_start
; tilemap.asm
;
; Level data + active buffer for multi-level support.
;
; `load_level` reads from a binary level pack (staged from LYNNE to
; &0920) and populates the active buffer fields below.  Per-room
; exit/fizzler/obj-index pointers point directly into the staging
; buffer, which persists until the next level load.

; Global constants (max across all levels).
LEVEL_COUNT = 7
MAX_ROOMS = 8
OBJ_COUNT = 6
OBJ_DEF_SIZE = 6
LASER_COUNT = 1
LASER_DEF_SIZE = 7
TARGET_COUNT = 1
TARGET_DEF_SIZE = 4
FIZZLER_DEF_SIZE = 5

; Staging buffer for level data copied from LYNNE.
; Lives below &3000 so ACCCON X-bit doesn't affect it.
; Located at &0E00 (boot loader area, reclaimed after boot).
; Must be above &0D00 to avoid overwriting the DFS NMI handler.
STAGING_BUF = &0E00

; ================================================================
; Active buffer — game code references these labels.
; The parser populates these from the binary pack.
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

; Room index counter used by the per-room parser loop.
; Stored here (not ZP) to avoid adding another ZP variable.
.ll_room_count  SKIP 1
.ll_room_idx    SKIP 1

; Pointer to level card overlay data in the staging buffer.
; Set by ll_parse_staged after room parsing; used by show_level_card.
.level_card_ptr SKIP 2

; Decompressed tilemap buffers — one 256-byte flat tilemap per room.
; room_pointers entries are patched at load time to point here.
; Game code reads/writes via (tilemap_ptr),Y unchanged.
; Must be page-aligned so (zp),Y with Y=0..255 covers exactly one room.
ALIGN 256
.tilemap_buffers        SKIP MAX_ROOMS * 256


; load_level: read a level from the binary pack into the active buffer.
;
; Flow:
;   Phase 0: ensure correct pack is in LYNNE (may trigger DFS read)
;   Phase 1: stage level data from LYNNE (&3000+) to STAGING_BUF (&0E00)
;   Phase 2: parse staged data into active buffer + tilemap_buffers
;
; Input: current_level set (0..LEVEL_COUNT-1).
; Clobbers: A,X,Y,temp,temp_sprite_ptr,temp_mask_ptr
.load_level
    ; --- Phase 0: load pack to LYNNE ---
    JSR load_pack_for_level

    ; --- Phase 1: stage level data from LYNNE to STAGING_BUF ---
    JSR ll_stage_from_lynne

    ; --- Phase 2: parse staged data into active buffer ---
    ; temp_sprite_ptr now points to STAGING_BUF.
    ; All data is in main RAM; ACCCON X=0.
    JMP ll_parse_staged


; ll_stage_from_lynne: copy level data from LYNNE to STAGING_BUF.
;
; Computes level_in_pack, then delegates to the below-&3000 trampoline
; (lynne_stage_level) which handles ACCCON X=1, offset table reads,
; memcpy, and ACCCON restore.  Returns with temp_sprite_ptr = STAGING_BUF.
;
; Clobbers: A,X,Y,temp,temp_sprite_ptr,temp_mask_ptr
.ll_stage_from_lynne
    ; Compute level_in_pack = current_level MOD LEVELS_PER_PACK.
    LDA current_level
.ll_stg_div
    CMP #LEVELS_PER_PACK
    BCC ll_stg_div_done
    SEC
    SBC #LEVELS_PER_PACK
    BCS ll_stg_div              ; always taken (result >= 0)
.ll_stg_div_done
    ; A = level_in_pack (0-based)
    ; Offset table entry is at PACK_LOAD_ADDR + 1 + level_in_pack*2.
    ASL A                       ; *2
    TAX                         ; X = byte offset into offset table

    ; Trampoline at &0900: sets ACCCON X=1, reads offsets from LYNNE,
    ; copies level data to STAGING_BUF, restores X=0, sets temp_sprite_ptr.
    JMP lynne_stage_level


; ll_parse_staged: parse level data from STAGING_BUF into the active buffer.
;
; Pack per-level format:
;   +0    1B   room_count
;   +1    1B   start_room
;   +2    1B   start_tile_pos (y<<4 | x)
;   +3    1B   obj_count
;   +4    P*6B obj defs
;   +?    1B   laser_count
;   +?    L*7B laser defs
;   +?    1B   target_count
;   +?    T*4B target defs
;   Per room (room_count times):
;     var    RLE-compressed tilemap
;     1B     exit_left_count  + E*3B records
;     1B     exit_right_count + E*3B records
;     1B     exit_up_count    + E*3B records
;     1B     exit_down_count  + E*3B records
;     1B     obj_index_count  + N*1B indices
;     1B     fizzler_count    + F*5B records
;   Level card overlay: (row, col, len, data...)... &FF terminated
;
; Input: temp_sprite_ptr = STAGING_BUF (source cursor).
; Clobbers: A,X,Y,temp,temp_sprite_ptr,temp_mask_ptr
.ll_parse_staged
    ; --- Read level header fields ---
    LDY #0
    LDA (temp_sprite_ptr),Y    ; room_count
    STA ll_room_count
    INY
    LDA (temp_sprite_ptr),Y    ; start_room
    STA level_start_room_buf
    INY
    LDA (temp_sprite_ptr),Y    ; start_tile_pos
    STA level_start_pos_buf
    INY
    ; Advance temp_sprite_ptr past the 3 header bytes.
    ; Y=3, so add 3.
    LDA temp_sprite_ptr
    CLC
    ADC #3
    STA temp_sprite_ptr
    BCC ll_ph_no_c1
    INC temp_sprite_ptr+1
.ll_ph_no_c1

    ; --- Copy obj_defs ---
    ; Read obj_count (1 byte), copy count*6 bytes, zero-fill to OBJ_COUNT*6.
    LDY #0
    LDA (temp_sprite_ptr),Y    ; obj_count
    ; advance past count byte
    INC temp_sprite_ptr
    BNE ll_ph_no_c2
    INC temp_sprite_ptr+1
.ll_ph_no_c2
    ; A = obj_count. Compute bytes = A * 6.
    TAX                         ; X = obj_count
    LDY #0
    ; Copy X*6 bytes from temp_sprite_ptr → obj_defs.
    ; We'll iterate: for each object, copy 6 bytes.
    CPX #0
    BEQ ll_obj_zero_fill
.ll_obj_copy_outer
    LDA #6
    STA temp                    ; bytes per object
.ll_obj_copy_inner
    LDA (temp_sprite_ptr),Y
    STA obj_defs,Y
    INY
    DEC temp
    BNE ll_obj_copy_inner
    DEX
    BNE ll_obj_copy_outer
    ; Advance temp_sprite_ptr by Y bytes.
    TYA
    CLC
    ADC temp_sprite_ptr
    STA temp_sprite_ptr
    BCC ll_obj_adv
    INC temp_sprite_ptr+1
.ll_obj_adv
.ll_obj_zero_fill
    ; Zero-fill remaining obj_defs slots.
    ; Y = bytes already written. Fill to OBJ_COUNT*6.
    LDA #0
.ll_obj_zf_loop
    CPY #OBJ_COUNT * OBJ_DEF_SIZE
    BCS ll_obj_done
    STA obj_defs,Y
    INY
    BNE ll_obj_zf_loop          ; always taken
.ll_obj_done

    ; --- Copy laser_defs ---
    LDY #0
    LDA (temp_sprite_ptr),Y    ; laser_count
    INC temp_sprite_ptr
    BNE ll_ph_no_c3
    INC temp_sprite_ptr+1
.ll_ph_no_c3
    TAX
    LDY #0
    CPX #0
    BEQ ll_laser_zero_fill
.ll_laser_copy_outer
    LDA #LASER_DEF_SIZE
    STA temp
.ll_laser_copy_inner
    LDA (temp_sprite_ptr),Y
    STA laser_defs,Y
    INY
    DEC temp
    BNE ll_laser_copy_inner
    DEX
    BNE ll_laser_copy_outer
    TYA
    CLC
    ADC temp_sprite_ptr
    STA temp_sprite_ptr
    BCC ll_laser_adv
    INC temp_sprite_ptr+1
.ll_laser_adv
.ll_laser_zero_fill
    LDA #0
.ll_laser_zf_loop
    CPY #LASER_COUNT * LASER_DEF_SIZE
    BCS ll_laser_done
    STA laser_defs,Y
    INY
    BNE ll_laser_zf_loop
.ll_laser_done

    ; --- Copy target_defs ---
    LDY #0
    LDA (temp_sprite_ptr),Y    ; target_count
    INC temp_sprite_ptr
    BNE ll_ph_no_c4
    INC temp_sprite_ptr+1
.ll_ph_no_c4
    TAX
    LDY #0
    CPX #0
    BEQ ll_target_zero_fill
.ll_target_copy_outer
    LDA #TARGET_DEF_SIZE
    STA temp
.ll_target_copy_inner
    LDA (temp_sprite_ptr),Y
    STA target_defs,Y
    INY
    DEC temp
    BNE ll_target_copy_inner
    DEX
    BNE ll_target_copy_outer
    TYA
    CLC
    ADC temp_sprite_ptr
    STA temp_sprite_ptr
    BCC ll_target_adv
    INC temp_sprite_ptr+1
.ll_target_adv
.ll_target_zero_fill
    LDA #0
.ll_target_zf_loop
    CPY #TARGET_COUNT * TARGET_DEF_SIZE
    BCS ll_target_done
    STA target_defs,Y
    INY
    BNE ll_target_zf_loop
.ll_target_done

    ; --- Per-room parsing loop ---
    LDA #0
    STA ll_room_idx
.ll_room_loop
    LDA ll_room_idx
    CMP ll_room_count
    BCC ll_room_active          ; room is valid — parse it
    JMP ll_unused_rooms         ; past valid rooms → zero-fill
.ll_room_active

    ; --- RLE decompress tilemap ---
    ; Destination: tilemap_buffers + room_idx * 256.
    LDA ll_room_idx
    CLC
    ADC #>tilemap_buffers
    STA temp_mask_ptr+1
    LDA #<tilemap_buffers
    STA temp_mask_ptr

    JSR rle_decompress          ; reads from temp_sprite_ptr, writes to temp_mask_ptr
                                ; temp_sprite_ptr is advanced past RLE data

    ; Set room_pointers[room_idx] = destination buffer address.
    LDA ll_room_idx
    ASL A                       ; *2 for word index
    TAX
    LDA #<tilemap_buffers
    STA room_pointers,X
    LDA ll_room_idx
    CLC
    ADC #>tilemap_buffers
    STA room_pointers+1,X

    ; --- Parse exit records for 4 directions ---
    ; For each direction: read count byte, store count, store pointer
    ; to the exit records (which follow in the staging buffer), then
    ; advance temp_sprite_ptr by count*3.

    LDX ll_room_idx             ; X = room index (byte index for counts)
    JSR ll_parse_exits_left
    JSR ll_parse_exits_right
    JSR ll_parse_exits_up
    JSR ll_parse_exits_down

    ; --- Parse obj_room indices ---
    LDX ll_room_idx
    LDY #0
    LDA (temp_sprite_ptr),Y    ; obj_index_count
    STA obj_room_counts,X
    ; Advance past count byte.
    INC temp_sprite_ptr
    BNE ll_orc_no_c
    INC temp_sprite_ptr+1
.ll_orc_no_c
    ; Store pointer to indices.
    TXA
    ASL A
    TAX
    LDA temp_sprite_ptr
    STA obj_room_ptrs,X
    LDA temp_sprite_ptr+1
    STA obj_room_ptrs+1,X
    ; Advance temp_sprite_ptr by obj_index_count bytes.
    LDX ll_room_idx
    LDA obj_room_counts,X
    JSR ll_advance_src

    ; --- Parse fizzler records ---
    LDX ll_room_idx
    LDY #0
    LDA (temp_sprite_ptr),Y    ; fizzler_count
    STA fizzler_room_counts,X
    ; Advance past count byte.
    INC temp_sprite_ptr
    BNE ll_frc_no_c
    INC temp_sprite_ptr+1
.ll_frc_no_c
    ; Store pointer to fizzler data.
    TXA
    ASL A
    TAX
    LDA temp_sprite_ptr
    STA fizzler_room_ptrs,X
    LDA temp_sprite_ptr+1
    STA fizzler_room_ptrs+1,X
    ; Advance temp_sprite_ptr by fizzler_count * 5.
    LDX ll_room_idx
    LDA fizzler_room_counts,X
    ; Multiply by 5: A*5 = A*4 + A.
    STA temp
    ASL A
    ASL A                       ; A*4
    CLC
    ADC temp                    ; A*5
    JSR ll_advance_src

    ; Next room.
    INC ll_room_idx
    JMP ll_room_loop

    ; --- Zero-fill unused room slots ---
.ll_unused_rooms
    LDA ll_room_idx
    CMP #MAX_ROOMS
    BCS ll_rooms_done

    ; room_pointers[i] = tilemap_buffers + i*256.
    LDA ll_room_idx
    ASL A
    TAX
    LDA #<tilemap_buffers
    STA room_pointers,X
    LDA ll_room_idx
    CLC
    ADC #>tilemap_buffers
    STA room_pointers+1,X

    ; Zero tilemap buffer for this slot.
    LDA ll_room_idx
    CLC
    ADC #>tilemap_buffers
    STA temp_mask_ptr+1
    LDA #<tilemap_buffers
    STA temp_mask_ptr
    LDA #0
    LDY #0
.ll_zero_tm
    STA (temp_mask_ptr),Y
    INY
    BNE ll_zero_tm

    ; Zero counts.
    LDX ll_room_idx
    LDA #0
    STA exit_left_counts,X
    STA exit_right_counts,X
    STA exit_up_counts,X
    STA exit_down_counts,X
    STA obj_room_counts,X
    STA fizzler_room_counts,X

    ; Set pointers to a safe address (STAGING_BUF, won't be dereferenced).
    TXA
    ASL A
    TAX
    LDA #<STAGING_BUF
    STA exit_left_ptrs,X
    STA exit_right_ptrs,X
    STA exit_up_ptrs,X
    STA exit_down_ptrs,X
    STA obj_room_ptrs,X
    STA fizzler_room_ptrs,X
    LDA #>STAGING_BUF
    STA exit_left_ptrs+1,X
    STA exit_right_ptrs+1,X
    STA exit_up_ptrs+1,X
    STA exit_down_ptrs+1,X
    STA obj_room_ptrs+1,X
    STA fizzler_room_ptrs+1,X

    INC ll_room_idx
    JMP ll_unused_rooms

.ll_rooms_done
    ; temp_sprite_ptr now points to the level card overlay data
    ; in the staging buffer.  Save it for show_level_card.
    LDA temp_sprite_ptr
    STA level_card_ptr
    LDA temp_sprite_ptr+1
    STA level_card_ptr+1
    RTS


; ll_parse_exits_left: read exit count + set pointer for left exits.
; Input: X = room index, temp_sprite_ptr = source cursor.
; Clobbers: A,Y,temp. Preserves X.
.ll_parse_exits_left
    LDY #0
    LDA (temp_sprite_ptr),Y
    STA exit_left_counts,X
    INC temp_sprite_ptr
    BNE ll_pel_no_c
    INC temp_sprite_ptr+1
.ll_pel_no_c
    TXA
    ASL A
    TAY
    LDA temp_sprite_ptr
    STA exit_left_ptrs,Y
    LDA temp_sprite_ptr+1
    STA exit_left_ptrs+1,Y
    ; Advance by count*3.
    LDA exit_left_counts,X
    STA temp
    ASL A                       ; *2
    CLC
    ADC temp                    ; *3
    JMP ll_advance_src

; ll_parse_exits_right: same for right exits.
.ll_parse_exits_right
    LDY #0
    LDA (temp_sprite_ptr),Y
    STA exit_right_counts,X
    INC temp_sprite_ptr
    BNE ll_per_no_c
    INC temp_sprite_ptr+1
.ll_per_no_c
    TXA
    ASL A
    TAY
    LDA temp_sprite_ptr
    STA exit_right_ptrs,Y
    LDA temp_sprite_ptr+1
    STA exit_right_ptrs+1,Y
    LDA exit_right_counts,X
    STA temp
    ASL A
    CLC
    ADC temp
    JMP ll_advance_src

; ll_parse_exits_up: same for up exits.
.ll_parse_exits_up
    LDY #0
    LDA (temp_sprite_ptr),Y
    STA exit_up_counts,X
    INC temp_sprite_ptr
    BNE ll_peu_no_c
    INC temp_sprite_ptr+1
.ll_peu_no_c
    TXA
    ASL A
    TAY
    LDA temp_sprite_ptr
    STA exit_up_ptrs,Y
    LDA temp_sprite_ptr+1
    STA exit_up_ptrs+1,Y
    LDA exit_up_counts,X
    STA temp
    ASL A
    CLC
    ADC temp
    JMP ll_advance_src

; ll_parse_exits_down: same for down exits.
.ll_parse_exits_down
    LDY #0
    LDA (temp_sprite_ptr),Y
    STA exit_down_counts,X
    INC temp_sprite_ptr
    BNE ll_ped_no_c
    INC temp_sprite_ptr+1
.ll_ped_no_c
    TXA
    ASL A
    TAY
    LDA temp_sprite_ptr
    STA exit_down_ptrs,Y
    LDA temp_sprite_ptr+1
    STA exit_down_ptrs+1,Y
    LDA exit_down_counts,X
    STA temp
    ASL A
    CLC
    ADC temp
    JMP ll_advance_src


; ll_advance_src: advance temp_sprite_ptr by A bytes.
; Input: A = byte count to advance.
; Clobbers: A. Preserves X,Y.
.ll_advance_src
    CLC
    ADC temp_sprite_ptr
    STA temp_sprite_ptr
    BCC ll_adv_no_c
    INC temp_sprite_ptr+1
.ll_adv_no_c
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
    SEI                         ; disable interrupts during decompression
    LDY #0                      ; output index (0..255)
.rle_pair
    ; Read [count][tile] pair via temp index.
    STY temp                    ; save output index
    LDY #0
    LDA (temp_sprite_ptr),Y   ; count
    TAX                         ; X = run length
    INY
    LDA (temp_sprite_ptr),Y   ; tile_id
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
    CLI                         ; re-enable interrupts
    RTS
