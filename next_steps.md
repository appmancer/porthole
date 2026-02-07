# Next Steps

This file tracks concrete, prioritized actions.
Detailed background/design context lives in `project plan.md`.
Architecture reference auto-loaded from `MEMORY.md`.

---

## Done

- **P0: Movement Overhaul** — all 3 tasks complete (direction fix, pipeline restructure, dead code cleanup)
- **Memory Layout Refactoring** — shadow RAM active, tile data in SWRAM bank 6, section budgets enforced
- **Pressure pads** — pad activation (Chell/cube), tile swap (up/down), signal channel → exit open/close all working
- **Tile swap plumbing** — pads and exits swap tiles on state change
- **Signals** — pad → channel → exit chain functional

---

## P1: Gameplay Interactions (remaining)

1) Signals extension

   - Extend existing pad/button/exit system with:
     - `laser_target` as signal driver when lit.
     - `spawner` as signal consumer (rising edge spawns a cube).

4) ~~Acid~~ ✓ + fizzler regions

   - ~~Acid: kill Chell on contact, reset on next key press.~~ DONE
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

2) Falling + flinging (high-speed portal traversal)

   - At some point jumping becomes falling; Chell accelerates and moves faster.
   - Quick-shot straight-down already works while falling.
   - Velocity must be preserved through portals — enter a floor portal fast,
     exit a wall portal fast (horizontal fling across gaps).
   - Requires: higher terminal velocity, velocity mapping through portal
     orientations (vt/vn decomposition already in portal_teleport.asm),
     possibly swept collision detection to avoid tunnelling at high speeds.
