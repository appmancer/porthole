# Next Steps

This file tracks concrete, prioritized actions.
Detailed background/design context lives in `project plan.md`.

## P0: Persistent Objects + Signals (2-Room Playground)

1) Build output: emit “persistent level-global objects” (DONE)

   - `levels/generated_level1.asm` now emits:
     - `OBJ_COUNT`, `OBJ_DEF_SIZE`
     - `.obj_defs` entries: `type_id, channel, init_flags, home_room, home_x, home_y`
     - `.obj_room_counts`, `.obj_room_ptrs`, plus per-room `..._obj_indices` lists of `obj_index` bytes
   - `obj_index` ordering is deterministic: sort by TMX `id` string; legacy `__meta__:` ids sort last.

2) Runtime: add persistent object state arrays and room materialization
   
   - Allocate per-object arrays indexed by `obj_index`: `obj_state[]`, plus `obj_room/x/y` at least for cube.
   - On room entry, do not respawn; render objects whose `obj_room == current_room`.

3) Implement channel-driven behavior
   
   - `pad`: pressed if Chell stands on it OR cube rests on it.
   - `button`: pressed by SPACE while Chell overlaps interaction zone.
   - `exit`: open if signal bit for `channel` is set.

4) Rendering for object state changes (MVP-safe)
   
   - If any object’s visible state changes, set `room_dirty=1` and redraw tilemap + objects next frame (safe with save-under).
   - Later optimize to restamp only changed object rects.

Acceptance checks (P0)

- Room00: pad(channel 0) and exit(channel 0) behave: pad pressed -> exit opens.
- Room01: cube spawns from TMX and persists if moved/left in another room.
- Leaving and returning to rooms preserves cube position and any puzzle state.
