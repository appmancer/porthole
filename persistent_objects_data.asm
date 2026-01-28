; persistent_objects_data.asm
; Runtime arrays for persistent objects + signal bits.
;
; This file is included from `main.asm` near the end, where the data previously
; lived, so addresses remain stable.

; --- Persistent objects (runtime state) ---
; Indexed by obj_index (0..OBJ_COUNT-1)
.obj_type
    SKIP OBJ_COUNT
.obj_channel
    SKIP OBJ_COUNT
.obj_state
    SKIP OBJ_COUNT
.obj_room
    SKIP OBJ_COUNT
.obj_x
    SKIP OBJ_COUNT
.obj_y
    SKIP OBJ_COUNT


; --- Persistent object redraw bookkeeping ---
;
; obj_dirty[i]=1 marks that object i needs a background patch + restamp.
.obj_dirty
    SKIP OBJ_COUNT

; Published signal bits for this frame (level-global).
.sig_state
    SKIP 1

; Bit masks for channels 0..7
.bit_table
    EQUB 1,2,4,8,16,32,64,128
