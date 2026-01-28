# Next Steps

This file tracks concrete, prioritized actions.
Detailed background/design context lives in `project plan.md`.

## P0: Rendering Correctness (Blockers)

## P1: Gameplay Interactions

1) Quick-shot portal firing (non-reticle)

   - Outside reticle mode, pressing `A`/`S` attempts to place portal A/B via a projected shot.
   - Direction uses `aim_held`:
     - not aiming: straight ahead
     - aim up (`:`): ~30 degrees up
     - aim down (`/`): ~30 degrees down
   - Raycast against tile solidity only (dynamic objects never block shots).
   - Disallow back-wall placement in this mode.
   - On first solid hit, derive surface orientation (wall vs floor/ceiling) and generate a small candidate list.
     - Walls: footprint 1x2; allow nudging the anchor by +/-1 tile vertically (try base, -1, +1).
     - Floor/ceiling: footprint 2x1; allow nudging anchor by +/-1 tile horizontally (try base, -1, +1).
   - Validate candidates using the same placement rules as reticle mode (portalable + required adjacent empty space).
   - Acceptance: A/S places portals reliably without reticle; small +/-1 tile slide works; never places on back wall.


## P2: Follow-ups

1) Add a short in-game debug toggle (optional)

   - Visualize dirty rects / object indices / signal bits to speed iteration.
