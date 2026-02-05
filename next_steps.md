# Next Steps

This file tracks concrete, prioritized actions.
Detailed background/design context lives in `project plan.md`.

## P0: Bugs

None.

## P1: Gameplay Interactions

1) Pressure pad activation (Chell + cube)

   - Treat `pad` object anchor as the **tile swap location**.
   - Define pad activation zone one tile above the anchor (Chell feet/cube overlap).
   - When active, set its signal channel bit for the frame.

2) Tile swap plumbing for puzzle visuals

   - Add a per-frame tile swap list (room,x,y,tile_id).
   - Apply swaps before render (pads, exits, laser receivers, lasers).
   - Ensure swaps are re-applied only when state changes (no per-frame churn).

3) Signals extension (existing system)

   - Keep pad/button/exit logic, extend with:
     - `laser_target` as signal driver when lit.
     - `spawner` as signal consumer (rising edge spawns a cube).

4) Acid + fizzler regions

   - Parse `acid` and `fizzler` rectangles from TMX meta.
   - Acid: kill Chell on contact, reset on next key press.
   - Fizzler: always active; clears portals and drops carried cube.
   - Block portal LOS through fizzlers.

5) Laser emitters + targets (tile-based beams)

   - Parse `laser_emitter`, `laser_target`, `laser_portal_point` from TMX meta.
   - Trace beam on the tile grid **only when it changes** (portal placed/removed, blocker moved).
   - Emit beam tiles (T38/T39/T40/T41) and crossroads (T50/T51).
   - Detect portal-back tiles by tile id 19/40/41.

6) Laser → receiver → spawner chain (Room00/Room01)

   - Room00: emitter fires into wall; portal on `laser_portal_point` redirects.
   - Room01: receiver lit on channel 1; spawner creates cube at `cube` point.

## P2: Follow-ups

1) Cubes: gravity + portals
   
   - Cubes should interact with portals.
     - If a portal opens beneath a cube, the cube should fall through.
      - Cubes should be flung by portals (preserve momentum mapping like Chell).

## P0: Plan — Simplified Movement + Size Recovery (Option A)

Goal: get the build running again with a short, fast hop movement model, while
shrinking code size enough to stay below the framebuffer boundary.

### Movement rewrite (short hop)

- Replace current vertical physics with a small LUT-driven state machine.
- LUT (Option A): 10-frame hop, stripes per update:
  `-1,-1,-1,-1,0,+1,+1,+1,+1,+1`
- State variables:
  - `jump_active` (0/1)
  - `jump_phase` (0..JUMP_LUT_LEN)
  - `char_grounded` remains authoritative for standing
  - `char_vy` becomes informational (portal intent)
- Flow per update:
  - If `jump_active` and `jump_phase < JUMP_LUT_LEN`, apply LUT step.
  - If blocked (ceiling/ground), end jump immediately.
  - If LUT ends, transition to fall: 1 stripe down per update until grounded.
- Keep horizontal movement simple (no acceleration changes yet).

### Size recovery (build must run)

- Remove the heavy cube portal/physics code from the mainline branch.
- Keep that work on a reference branch (`heavy-physics-baseline`).
- Verify `.end < &5800` after each change.

### Current breakage context (why build is "broken")

- When code grows past `&5800`, render writes overwrite code and crash ("Bad program").
- This already happened once (`.end` > `&5800`), and we backed it out by reverting
  heavy cube-physics changes to keep a reference branch.
- Even after restoring code size, the runtime is still broken (tiles incorrect;
  no Chell or objects), so we should treat the build as broken until we can
  boot and see the expected room + sprites.

### Memory map alignment

- Keep code + update-time data below `&3000`.
- Shadow view `&3000..&57FF` reserved for render-only lookup tables.
- No render-time reads from main banked window.

### Micro-task order

1) Remove heavy cube physics from mainline (done by reverting to baseline files).
2) Finish movement rewrite using LUT (Option A).
3) Build + boot test (verify tiles, Chell, objects render).
4) Play-test feel; tune only LUT values if needed.
