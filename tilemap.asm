

; Screen tilemap data
.room_pointers
EQUW room1
EQUW room2

; Screen tilemap (16x13 large blocks, stored as nibbles in 136 bytes)
.screen_tilemap
.room1
;top room
EQUB &59, &99, &99, &99, &99, &99, &99, &9C ; 1
EQUB &62, &22, &22, &22, &22, &22, &22, &26 ; 2
EQUB &62, &22, &22, &22, &22, &22, &22, &26 ; 3
EQUB &62, &22, &22, &22, &22, &22, &22, &26 ; 4
EQUB &62, &22, &22, &22, &22, &22, &22, &26 ; 5
EQUB &62, &22, &22, &22, &22, &22, &22, &26 ; 6
EQUB &78, &88, &88, &88, &88, &88, &88, &8B ; 7
EQUB &11, &11, &11, &11, &11, &11, &11, &11 ; 8
; middle section
EQUB &62, &AA, &AA, &AA, &AA, &AA, &AA, &26 ; 1
EQUB &62, &AA, &AA, &AA, &AA, &AA, &AA, &26 ; 2
EQUB &62, &AA, &AA, &AA, &AA, &AA, &AA, &26 ; 3
EQUB &62, &AA, &AA, &AA, &AA, &AA, &AA, &26 ; 4
EQUB &62, &AA, &AA, &AA, &AA, &AA, &AA, &26 ; 5
EQUB &62, &AA, &AA, &AA, &AA, &AA, &AA, &26 ; 6
EQUB &78, &88, &88, &88, &88, &88, &88, &8B ; 7
; outside walls
EQUB &11, &11, &11, &11, &11, &11, &11, &11 ; 8

.room2
;top room
EQUB &62, &AA, &AA, &AA, &AA, &AA, &AA, &26 ; 1
EQUB &62, &AA, &AA, &AA, &AA, &AA, &AA, &26 ; 2
EQUB &62, &AA, &AA, &AA, &AA, &AA, &AA, &26 ; 3
EQUB &62, &AA, &AA, &AA, &AA, &AA, &AA, &26 ; 4
EQUB &62, &AA, &AA, &AA, &AA, &AA, &AA, &26 ; 5
EQUB &62, &AA, &AA, &AA, &AA, &AA, &AA, &26 ; 6
EQUB &78, &88, &88, &88, &88, &88, &88, &8B ; 7
; middle section
EQUB &11, &11, &11, &11, &11, &11, &11, &11 ; 8
; bottom room
EQUB &59, &99, &99, &99, &99, &99, &99, &9C ; 1
EQUB &62, &22, &22, &22, &22, &22, &22, &26 ; 2
EQUB &62, &22, &22, &22, &22, &22, &22, &26 ; 3
EQUB &62, &22, &22, &22, &22, &22, &22, &26 ; 4
EQUB &62, &22, &22, &22, &22, &22, &22, &26 ; 5
EQUB &62, &22, &22, &22, &22, &22, &22, &26 ; 6
EQUB &78, &88, &88, &88, &88, &88, &88, &8B ; 7
; outside walls
EQUB &11, &11, &11, &11, &11, &11, &11, &11 ; 8

