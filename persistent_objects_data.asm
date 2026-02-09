.persistent_data_start
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

; Previous on-screen position (tile coords) for patch/erase.
; Used by render to redraw both the old and new footprints when an object moves.
.obj_prev_x
    SKIP OBJ_COUNT
.obj_prev_y
    SKIP OBJ_COUNT

.obj_prev_room
    SKIP OBJ_COUNT

; --- Cube physics (tile-aligned) ---
;
; These arrays are currently only meaningful for cubes (OBJ_TYPE_CUBE), but are
; sized for OBJ_COUNT for simplicity.
;
; obj_vx: signed velocity in 8px tile columns per update.
; obj_vy: signed velocity in 16px tile rows per update.
.obj_vx
    SKIP OBJ_COUNT
.obj_vy
    SKIP OBJ_COUNT

; Per-object portal cooldown to prevent immediate re-entry (anti ping-pong).
.obj_portal_cd
    SKIP OBJ_COUNT


; --- Persistent object redraw bookkeeping ---
;
; obj_dirty[i]=1 marks that object i needs a background patch + restamp.
.obj_dirty
    SKIP OBJ_COUNT

; Published signal bits for this frame (level-global).
.sig_state
    SKIP 1

; Per-target lit flag, set by retrace_all_beams, read by update_beam_targets.
; Placed here (before the large 256-byte planes) so it stays below &5800
; in MAIN RAM — safe from any stray writes to the screen region.
.target_lit        SKIP TARGET_COUNT

; Bit masks for channels 0..7.
; Also kept below &5800 for the same reason.
.bit_table
    EQUB 1,2,4,8,16,32,64,128

; Static solid-tile plane (tilemap only, no objects).
; Used by LOS/portal validation which should ignore dynamic objects.
.solid_tile_plane
    SKIP 256

; Solid-tile plane for physics (tiles + standable objects).
; Rebuilt each frame from tilemap + cube positions.
.solid_phys_plane
    SKIP 256

; --- Laser beam runtime state ---
; Dynamic beam tiles stamped into tilemap (portal-redirected segments only).
MAX_BEAM_TILES = 30
.beam_tile_count   SKIP 1                ; number of dynamic beam tiles stamped
.beam_tile_pos     SKIP MAX_BEAM_TILES   ; tilemap offset (y*16+x) per tile
.beam_tile_orig    SKIP MAX_BEAM_TILES   ; original tile at that position
