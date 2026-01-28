# Next Steps

This file tracks concrete, prioritized actions.
Detailed background/design context lives in `project plan.md`.

## P0: Rendering Correctness (Blockers)

## P1: Gameplay Interactions

2) Cube pickup/drop

   - SPACE near cube toggles pickup/drop.
   - While carried: cube position follows Chell; collisions/portals define drop rules.
   - Acceptance: can carry cube between rooms, drop onto pad, and leave it parked.


## P2: Follow-ups

1) Tighten object redraw footprint logic

   - Per-type footprint tables (w/h in tiles) instead of hardcoded 2x1 vs exit 2x2.

2) Add a short in-game debug toggle (optional)

   - Visualize dirty rects / object indices / signal bits to speed iteration.
