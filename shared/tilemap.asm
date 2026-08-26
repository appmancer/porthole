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
LEVEL_COUNT = 13
MAX_ROOMS = 11
OBJ_COUNT = 24
OBJ_DEF_SIZE = 6
LASER_COUNT = 1
LASER_DEF_SIZE = 7
TARGET_COUNT = 2
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
.killzone_room_counts   SKIP MAX_ROOMS
.killzone_room_ptrs     SKIP MAX_ROOMS * 2

; Current-room killzone state (not in ZP — not hot-path).
.room_killzone_count    SKIP 1
.room_killzone_ptr      SKIP 2

; Room index counter used by the per-room parser loop.
; Stored here (not ZP) to avoid adding another ZP variable.
.ll_room_count  SKIP 1
.ll_room_idx    SKIP 1

; Pointer to level card overlay data in the staging buffer.
; Set by ll_parse_staged after room parsing; used by show_level_card.
.level_card_ptr SKIP 2

; Decompressed tilemaps — one 256-byte flat tilemap per room.
;
; Only the CURRENT room is resident in main RAM; every room's home is in SWRAM
; bank 6 (alongside tile pixel data) at TILEMAP_BANK_BASE + room*256. This keeps
; 2.5KB of main RAM free at the cost of a 256-byte copy per room transition.
;
; room_pointers[current_room] points at the resident page; all other entries
; point at the room's bank home. Current-room code paths are therefore unchanged
; -- only genuinely cross-room readers (the beam trace) must page bank 6 in.
;
; Paging bank 6 does not hide main RAM, so a reader that pages it can read both
; the resident page and other rooms' homes without branching.
;
; Base is &B000, leaving &8000..&AFFF (12KB) for themed tile sheets.
TILEMAP_BANK_BASE = &B000

; Must be page-aligned so (zp),Y with Y=0..255 covers exactly one room.
ALIGN 256
.room_tilemap           SKIP 256
.resident_room          SKIP 1      ; room held in room_tilemap (&FF = none)
.tilemap_saved_romsel   SKIP 1      ; ROMSEL shadow saved by tilemap_bank_in



; --- SWRAM bank 6 paging for tilemap access ---
;
; Paging bank 6 does NOT hide main RAM, so while it is in a reader can see both
; the resident page (main RAM) and every room's bank home without branching.
;
; NOT nestable with itself (single saved byte). Inner routines that do their own
; stack-based ROMSEL save/restore (e.g. redraw_tile_xy) are fine to call from
; inside an in/out pair.
.tilemap_bank_in
    PHP
    SEI
    LDA &F4
    STA tilemap_saved_romsel
    LDA tile_bank
    STA &F4
    STA ROMSEL
    PLP
    RTS

.tilemap_bank_out
    PHP
    SEI
    LDA tilemap_saved_romsel
    STA &F4
    STA ROMSEL
    PLP
    RTS


; Make current_room's tilemap resident in room_tilemap.
;
; Writes the outgoing room back to its bank home first, so runtime mutations
; (beam stamps, object tile state, and later vine burns) survive a room change.
; Then patches room_pointers: current room -> resident page, outgoing room ->
; its bank home.
;
; Clobbers: A,X,Y,temp_mask_ptr
.tilemap_make_resident
    LDA current_room
    CMP resident_room
    BEQ tmr_done

    JSR tilemap_bank_in

    ; --- Write back the outgoing room, if there is one ---
    LDA resident_room
    CMP #&FF
    BEQ tmr_no_writeback
    CLC
    ADC #>TILEMAP_BANK_BASE     ; A = resident_room
    STA temp_mask_ptr+1
    LDA #<TILEMAP_BANK_BASE
    STA temp_mask_ptr
    LDY #0
.tmr_wb
    LDA room_tilemap,Y
    STA (temp_mask_ptr),Y
    INY
    BNE tmr_wb
    ; Outgoing room's pointer goes back to its bank home.
    LDA resident_room
    ASL A
    TAX
    LDA temp_mask_ptr
    STA room_pointers,X
    LDA temp_mask_ptr+1
    STA room_pointers+1,X
.tmr_no_writeback

    ; --- Fetch the incoming room ---
    LDA current_room
    CLC
    ADC #>TILEMAP_BANK_BASE
    STA temp_mask_ptr+1
    LDA #<TILEMAP_BANK_BASE
    STA temp_mask_ptr
    LDY #0
.tmr_fetch
    LDA (temp_mask_ptr),Y
    STA room_tilemap,Y
    INY
    BNE tmr_fetch

    JSR tilemap_bank_out

    LDA current_room
    STA resident_room
    ASL A
    TAX
    LDA #<room_tilemap
    STA room_pointers,X
    LDA #>room_tilemap
    STA room_pointers+1,X
.tmr_done
    RTS


; load_level: read a level from the binary pack into the active buffer.
;
; Flow:
;   Phase 1: stage level data from SWRAM bank 7 to STAGING_BUF (&0E00)
;   Phase 2: parse staged data into active buffer + per-room tilemaps in bank 6
;
; Input: current_level set (0..LEVEL_COUNT-1).
; Clobbers: A,X,Y,temp,temp_sprite_ptr,temp_mask_ptr
.load_level
    ; No room is resident yet: the bank is about to be (re)filled, so any
    ; stale resident page must not be written back over it.
    LDA #&FF
    STA resident_room
    ; --- Phase 1: stage level data from SWRAM to STAGING_BUF ---
    JSR ll_stage_from_swram

    ; --- Phase 2: parse staged data into active buffer ---
    ; temp_sprite_ptr now points to STAGING_BUF.
    JMP ll_parse_staged


; ll_stage_from_swram: copy level data from SWRAM bank 7 to STAGING_BUF.
;
; Pages in the level pack bank, reads offset table, copies the level's
; data to STAGING_BUF, restores bank.  Returns with temp_sprite_ptr = STAGING_BUF.
;
; Clobbers: A,X,Y,temp,temp_sprite_ptr,temp_mask_ptr
.ll_stage_from_swram
    ; Compute level_in_pack index (= current_level for single-pack).
    LDA current_level
    ASL A                       ; *2
    TAX                         ; X = byte offset into offset table

    ; Page in level pack bank.
    PHP
    SEI
    LDA &F4 : PHA              ; save MOS ROMSEL shadow
    LDA level_bank
    STA &F4 : STA ROMSEL

    ; Read offset[level_in_pack] from SWRAM.
    ; Pack header at &8000: [count(1B)] [offsets(N+1)*2B]
    LDA PACK_LOAD_ADDR+1,X     ; offset[i] lo
    STA temp_sprite_ptr
    LDA PACK_LOAD_ADDR+2,X     ; offset[i] hi
    STA temp_sprite_ptr+1

    ; Read offset[i+1] (sentinel).
    LDA PACK_LOAD_ADDR+3,X     ; offset[i+1] lo
    STA temp_mask_ptr
    LDA PACK_LOAD_ADDR+4,X     ; offset[i+1] hi
    STA temp_mask_ptr+1

    ; Compute length = offset[i+1] - offset[i].
    LDA temp_mask_ptr
    SEC
    SBC temp_sprite_ptr
    STA temp                    ; length lo
    LDA temp_mask_ptr+1
    SBC temp_sprite_ptr+1
    PHA                         ; length hi on stack

    ; Compute source = PACK_LOAD_ADDR + offset[i].
    LDA temp_sprite_ptr
    CLC
    ADC #<PACK_LOAD_ADDR
    STA temp_sprite_ptr
    LDA temp_sprite_ptr+1
    ADC #>PACK_LOAD_ADDR
    STA temp_sprite_ptr+1

    ; Set destination = STAGING_BUF.
    LDA #<STAGING_BUF
    STA temp_mask_ptr
    LDA #>STAGING_BUF
    STA temp_mask_ptr+1

    ; Copy length bytes from SWRAM to main RAM.
    PLA                         ; length hi
    TAX                         ; X = full pages

    LDY #0
    LDA temp
    BEQ ll_sw_full_pages
.ll_sw_partial
    LDA (temp_sprite_ptr),Y
    STA (temp_mask_ptr),Y
    INY
    CPY temp
    BNE ll_sw_partial

    CPX #0
    BEQ ll_sw_copy_done

    ; Advance pointers past partial page.
    LDA temp_sprite_ptr
    CLC : ADC temp
    STA temp_sprite_ptr
    BCC ll_sw_no_c1
    INC temp_sprite_ptr+1
.ll_sw_no_c1
    LDA temp_mask_ptr
    CLC : ADC temp
    STA temp_mask_ptr
    BCC ll_sw_no_c2
    INC temp_mask_ptr+1
.ll_sw_no_c2

.ll_sw_full_pages
    CPX #0
    BEQ ll_sw_copy_done
    LDY #0
.ll_sw_page
    LDA (temp_sprite_ptr),Y
    STA (temp_mask_ptr),Y
    INY
    BNE ll_sw_page
    INC temp_sprite_ptr+1
    INC temp_mask_ptr+1
    DEX
    BNE ll_sw_page

.ll_sw_copy_done
    ; Restore ROMSEL.
    PLA : STA &F4 : STA ROMSEL
    PLP

    ; Set temp_sprite_ptr = STAGING_BUF for the parser.
    LDA #<STAGING_BUF
    STA temp_sprite_ptr
    LDA #>STAGING_BUF
    STA temp_sprite_ptr+1
    RTS


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
    LDA #&FF                        ; sentinel: &FF room = unused laser slot
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
    ; Destination: TILEMAP_BANK_BASE + room_idx * 256, in SWRAM bank 6.
    ; Source (STAGING_BUF) is main RAM, so paging bank 6 here is safe.
    LDA ll_room_idx
    CLC
    ADC #>TILEMAP_BANK_BASE
    STA temp_mask_ptr+1
    LDA #<TILEMAP_BANK_BASE
    STA temp_mask_ptr

    JSR tilemap_bank_in
    JSR rle_decompress          ; reads from temp_sprite_ptr, writes to temp_mask_ptr
                                ; temp_sprite_ptr is advanced past RLE data
    JSR tilemap_bank_out

    ; Set room_pointers[room_idx] = bank home address.
    LDA ll_room_idx
    ASL A                       ; *2 for word index
    TAX
    LDA #<TILEMAP_BANK_BASE
    STA room_pointers,X
    LDA ll_room_idx
    CLC
    ADC #>TILEMAP_BANK_BASE
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

    ; --- Parse killzone records ---
    LDX ll_room_idx
    LDY #0
    LDA (temp_sprite_ptr),Y    ; killzone_count
    STA killzone_room_counts,X
    ; Advance past count byte.
    INC temp_sprite_ptr
    BNE ll_kzc_no_c
    INC temp_sprite_ptr+1
.ll_kzc_no_c
    ; Store pointer to killzone data.
    TXA
    ASL A
    TAX
    LDA temp_sprite_ptr
    STA killzone_room_ptrs,X
    LDA temp_sprite_ptr+1
    STA killzone_room_ptrs+1,X
    ; Advance temp_sprite_ptr by killzone_count * 5.
    LDX ll_room_idx
    LDA killzone_room_counts,X
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

    ; room_pointers[i] = TILEMAP_BANK_BASE + i*256.
    LDA ll_room_idx
    ASL A
    TAX
    LDA #<TILEMAP_BANK_BASE
    STA room_pointers,X
    LDA ll_room_idx
    CLC
    ADC #>TILEMAP_BANK_BASE
    STA room_pointers+1,X

    ; Zero this slot's tilemap in bank 6.
    LDA ll_room_idx
    CLC
    ADC #>TILEMAP_BANK_BASE
    STA temp_mask_ptr+1
    LDA #<TILEMAP_BANK_BASE
    STA temp_mask_ptr
    JSR tilemap_bank_in
    LDA #0
    LDY #0
.ll_zero_tm
    STA (temp_mask_ptr),Y
    INY
    BNE ll_zero_tm
    JSR tilemap_bank_out

    ; Zero counts.
    LDX ll_room_idx
    LDA #0
    STA exit_left_counts,X
    STA exit_right_counts,X
    STA exit_up_counts,X
    STA exit_down_counts,X
    STA obj_room_counts,X
    STA fizzler_room_counts,X
    STA killzone_room_counts,X

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
    STA killzone_room_ptrs,X
    LDA #>STAGING_BUF
    STA exit_left_ptrs+1,X
    STA exit_right_ptrs+1,X
    STA exit_up_ptrs+1,X
    STA exit_down_ptrs+1,X
    STA obj_room_ptrs+1,X
    STA fizzler_room_ptrs+1,X
    STA killzone_room_ptrs+1,X

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
