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
- **Laser emitters + targets** — tile-based beams, portal redirect, crossroads tiles, portal-back detection all working
- **Laser → receiver → spawner chain** — emitter → portal redirect → receiver → spawner → cube spawn working in Room00/Room01
- **Signals extension** — laser_target as signal driver, spawner as rising-edge consumer both functional
- **Acid death** — Chell dies on contact, press-to-restart
- **Cube physics** — gravity (fall 1 tile/frame), pad triggering (cube on pad activates signal), floor portal entry (cube falls through floor portal to paired exit)

---

## P1: Gameplay Interactions (remaining)

1) Fizzler regions

   - Fizzler: always active; clears portals and drops carried cube on contact.
   - Block portal LOS through fizzlers.

## P2: Follow-ups

1) Falling + flinging (high-speed portal traversal)

   - At some point jumping becomes falling; Chell accelerates and moves faster.
   - Quick-shot straight-down already works while falling.
   - Velocity must be preserved through portals — enter a floor portal fast,
     exit a wall portal fast (horizontal fling across gaps).
   - Requires: higher terminal velocity, velocity mapping through portal
     orientations (vt/vn decomposition already in portal_teleport.asm),
     possibly swept collision detection to avoid tunnelling at high speeds.

2) Cube fling through portals

   - Cubes currently only support floor portal entry (gravity drop-through).
   - Full momentum mapping (like Chell) for cube-through-portal fling is a stretch goal.
