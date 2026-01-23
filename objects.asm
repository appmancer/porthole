; Static object instance lists (tile-aligned stamps).
;
; Each entry is 10 bytes:
; 0: x (cell)
; 1: y (cell)
; 2: stripe_count (1/2/4); 0 terminates table
; 3: bytes_per_stripe (16/32)
; 4: stride (usually 16/32)
; 5: flags
;    bit0 = masked
;    bit7 = enabled (0 = skip)
; 6: sprite_ptr lo
; 7: sprite_ptr hi
; 8: mask_ptr lo
; 9: mask_ptr hi

STATIC_OBJ_ENTRY_SIZE = 10
STATIC_OBJ_FLAG_MASKED = 1
STATIC_OBJ_FLAG_ENABLED = &80

; Pointer table indexed by current_room.
.static_objects_room_pointers
    EQUW static_objects_room0
    EQUW static_objects_room1


; Room 0 objects
.static_objects_room0
    ; End
    EQUB 0,0,0


; Room 1 objects
.static_objects_room1
    ; End
    EQUB 0,0,0


; Enable a static object entry by setting flags bit7.
; Input: temp_sprite_ptr points to the flags byte.
.enable_static_object
    LDY #0
    LDA (temp_sprite_ptr),Y
    ORA #STATIC_OBJ_FLAG_ENABLED
    STA (temp_sprite_ptr),Y
    RTS


; Disable a static object entry by clearing flags bit7.
; Input: temp_sprite_ptr points to the flags byte.
.disable_static_object
    LDY #0
    LDA (temp_sprite_ptr),Y
    AND #&7F
    STA (temp_sprite_ptr),Y
    RTS
