; Satie "Gymnopedie No. 1" sequence data.
;
; 3-voice arrangement: melody, bass counterpoint, chord (top note).
; See sound/gymnopedie_data.asm for generated event streams.

INCLUDE "sound/gymnopedie_data.asm"

; Silent track for muting a voice.
.gymno_silent
    EQUB 253, 255   ; rest for 255 ticks
    EQUB 254, 0     ; loop

.music_track_table
    EQUB <gymno_melody, >gymno_melody
    EQUB <gymno_bass,   >gymno_bass
    ; Voice 2 silenced: the arrangement reads better as bass + melody, and it
    ; frees tone channel 3 for pitched sound effects. Swap gymno_silent back
    ; for gymno_chord to restore the three-voice version.
    EQUB <gymno_silent, >gymno_silent
