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
- **Fizzler regions** — parsed from TMX metadata, clear portals and destroy carried cube on contact, block portal LOS, surgical per-tile erase (no full room redraw), laser beams pass through
- **Pedestal button latching** — buttons latch on first SPACE press (permanent activation), pads remain momentary. Buttons parsed from meta objectgroup.

---

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

3) Portable laser emitter (turret)

   - A carryable object (like a cube) that emits a laser beam in the direction it faces.
   - **Puzzle tool, not weapon** — beam is a signal source, not damage.
   - Pickup/drop like cubes. Falls under gravity like cubes.
   - Cubes block all beams (universal rule).
   - Knocked over / dropped = disabled (on its back). Placed upright = active.
   - Creates resource tension: limited cubes serve as pad weights AND beam blockers.
   - Puzzle patterns: position emitter to hit receiver; combine with portal redirect;
     block a turret beam with a cube (but that cube was on a pad...).

   Object system (small):
   - New OBJ_TYPE (6), 16x16 sprites (left/right/disabled), facing state in obj_state bits.
   - Widen existing type checks in pickup/drop, gravity, pad detection, floor portal.
   - ~50-80 bytes new code + sprite data in SWRAM bank 5.

   Laser system (large — biggest piece of work):
   - Current laser architecture assumes build-time-known emitter positions. `laser_defs`
     has pre-computed emitter+wall endpoints; `check_static_targets` traces between them;
     `trace_dynamic_beam` only handles the portal-redirected segment after the static part.
   - A turret breaks this: emitter position is runtime-variable, no pre-computed wall
     endpoint. The **entire beam** must be traced dynamically from the turret's tile
     position, not just the portal-redirected tail.
   - Needs a second trace mode: full dynamic trace from arbitrary (x, y, dir). Every tile
     checks tilemap solidity, targets, portals, AND cube positions (new).
   - Beam invalidation: retrace when turret moves, cube enters/leaves path, or portal
     changes. Current retrace trigger (portal placement only) must be extended.
   - Fixed emitters + turret emitters must coexist in the same retrace loop.
   - Estimate ~200-300 bytes for the dynamic trace path + cube collision checks.
   - Total turret feature: ~300-400 bytes code + sprite data. ~8KB headroom available.
