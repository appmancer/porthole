# Next Steps

This file tracks concrete, prioritized actions.
Detailed background/design context lives in `project plan.md`.

## P0: Bugs

None.

## P1: Gameplay Interactions

1) Portal exit orientation + body rotation (post-fling)
   
   Goal
   
   - Preserve "feet-first" entry intent through teleport:
     - Enter floor portal feet-first => exit still feet-first.
       - Out of a wall: Chell is sideways (on her back) while exiting.
       - Out of a floor: Chell is upside down while exiting.
   
   Implementation plan (no code yet)
   
   - Represent body orientation separately from facing.
     
     - Add a small enum for body rotation: 0/90/180/270 degrees.
     - Keep `anim_dir` as "facing" for controls; rotation is purely for pose + collision footprint.
   
   - Derive rotation from portal frames.
     
     - On teleport, compute the rotation that maps entry "down" (feet direction) to exit "down".
     - Store `chell_rotation` (or similar) at teleport time.
   
   - Rendering
     
     - Add rotated variants of the airborne/fall sprites needed for the mechanic:
       - upright (current)
       - sideways (wall exit)
       - upside down (floor exit)
     - Start with the minimal set required for the level; expand later.
   
   - Physics + collisions
     
     - Decide whether rotated Chell still uses the same 16x32 AABB for collision (simplest), or swaps to 32x16 when sideways.
     - If we keep the same AABB, rotation is cosmetic; if we swap, update collision sampling accordingly.
   
   - Recovery
     
      - Define how/when Chell returns to upright (e.g. on landing, or after a short airborne timer, or when `char_grounded` becomes 1).

## P2: Follow-ups

1) Cubes: gravity + portals
   
   - Cubes should be subject to gravity like Chell.
     - If dropped off a ledge, a cube should fall.
   - Cubes should interact with portals.
     - If a portal opens beneath a cube, the cube should fall through.
     - Cubes should be flung by portals (preserve momentum mapping like Chell).
