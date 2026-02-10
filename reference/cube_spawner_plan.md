# Cube Spawner Plan

## Goal

Add a cube spawner object that creates/recreates cubes when triggered by a
channel signal. Cubes can start despawned (invisible) and appear only when
the spawner fires. Fizzlers (future) can destroy cubes, and the spawner
can respawn them.

## Design: Sentinel Room for Despawn

Use `obj_room = &FF` as "not in any room" (despawned). This works almost
for free because all existing code gates on `obj_room == current_room`:

- Room &FF never matches current_room (0..N)
- Despawned cubes don't render, don't collide, can't be picked up, don't
  get gravity, don't block other cubes
- No new state bit needed; no widespread code changes

### Spawner behaviour

- New object type: `OBJ_TYPE_SPAWNER = 5`
- Invisible (no sprite stamp, 0x0 redraw footprint)
- Consumer: listens on a channel in `update_signals_and_object_states` pass 2
- On **rising edge** of channel signal (0 -> 1):
  1. Find first cube with same channel number
  2. If cube is carried: force-drop it (clear CARRIED bit, set
     `carried_cube_idx = &FF`, mark chell_dirty)
  3. Save cube's old position in obj_prev_x/y/room for patch/erase
  4. Set cube's room/x/y to spawner's room/x/y
  5. Clear cube velocity and portal cooldown
  6. Mark cube dirty + objects_pending

### Cube despawn (for fizzler, future)

- Set `obj_room = &FF`, save prev position, mark dirty
- Redraw code erases old footprint (prev_room matches current_room)
  but skips stamp (new room = &FF doesn't match)

### Level authoring

- Cubes that start despawned: set `home_room = &FF` in obj_defs
  (or a sentinel value in the TMX, e.g. room property "despawned")
- gen-level: add "spawner" to OBJECT_TYPE_TO_ID
- gen-level: support init_flags or a "despawned" property on cube objects
  that sets home_room to &FF in the emitted obj_defs

## Files to Change

| File | Change |
|------|--------|
| main.asm | Add `OBJ_TYPE_SPAWNER = 5` constant |
| persistent_objects.asm | Add spawner footprint (0x0), consumer logic in pass 2, `spawner_spawn_cube` subroutine |
| tools/gen-level | Add "spawner" to OBJECT_TYPE_TO_ID; support despawned cubes |
| levels/level1/*.tmx | Add spawner object; optionally mark cube as starting despawned |

## Size Estimate

~120 bytes for spawner consumer + spawn subroutine. Well within
persistent_objects budget (1,448 used / 1,664 budget = 216 free).

## Dependencies

None. Can be implemented independently. Fizzler destruction uses the same
sentinel room mechanism but is a separate feature.

## Test Plan

1. Add a spawner (type=spawner, channel=N) and a cube (type=cube,
   channel=N, despawned) to a room in Tiled
2. Add a button or pad on the same channel
3. Press button -> cube appears at spawner position
4. Pick up cube, move it away, press button again -> cube returns to spawner
5. Carry cube while pressing button -> cube force-drops and respawns
