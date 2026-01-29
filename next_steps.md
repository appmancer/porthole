# Next Steps

This file tracks concrete, prioritized actions.
Detailed background/design context lives in `project plan.md`.

## P0: Rendering Correctness (Blockers)

## P1: Gameplay Interactions

1) Fling ("fast in, fast out") via real momentum

   Why it doesn't conserve momentum today

   - Vertical speed is effectively quantized/capped: `TERMINAL_VELOCITY_DOWN=1` and falling movement is paced to at most one 8px stripe step per frame.
   - Horizontal speed magnitude is not applied: movement uses only the sign of `char_vx` (1px/frame stepping), so large velocities produced by portal mapping don't translate into distance.

   Implementation plan (no code yet)

   - Horizontal velocity (required for shaft crossing)
     - Change horizontal movement so `char_vx` magnitude matters.
     - Per frame, apply up to `abs(char_vx)` 1px steps (with collision per step), with a clamp to avoid pathological frame time.

   - Vertical velocity (variety of fall speeds)
     - Raise `TERMINAL_VELOCITY_DOWN` to a meaningful range (in 8px stripes/frame).
     - Change falling so it can move multiple 8px stripes per frame based on `char_vy` magnitude (remove the one-stripe cap).
     - Tune gravity so terminal velocity is reached after ~12-ish tiles of fall (tunable via accel + tick periods).

   - Portal momentum mapping (unit scaling)
     - Keep the current entry/exit normal/tangent approach, but introduce an explicit scale between axes:
       - vertical units are "stripes/frame" (8px chunks)
       - horizontal units are "pixels/frame"
     - When converting vertical speed into horizontal on exit, multiply by 8 (and the inverse when converting horizontal into vertical).
     - Apply clamping after mapping to the new terminal limits.

   - Controls and readability
     - Add "fast fall" while airborne when Down is held (accelerate toward terminal faster).
     - Add a falling sprite state that triggers only when descent is committed (e.g. vy beyond a threshold), so small drops still read as a controlled jump.

2) Portal exit orientation + body rotation (post-fling)

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

1) Add a short in-game debug toggle (optional)

   - Visualize dirty rects / object indices / signal bits to speed iteration.
