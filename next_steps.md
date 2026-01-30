# Next Steps

This file tracks concrete, prioritized actions.
Detailed background/design context lives in `project plan.md`.

## P0: Bugs

1) Jumping normally triggers falling
   
   - Hypothesis: our `FALL_POSE_VY_THRESHOLD` is low enough that a normal jump's descent reaches it quickly, so the fall pose appears during what the player still perceives as a jump arc.
   - Verify by logging/observing `char_vy` over a normal jump:
     - Jump starts with `JUMP_VELOCITY=&FE` (-2 stripes/frame), gravity ticks every `GRAVITY_UP_PERIOD=3` while rising, then every `GRAVITY_DOWN_PERIOD=2` while falling.
     - Note the first frame where `char_vy` becomes `>= FALL_POSE_VY_THRESHOLD`.
   - Candidate adjustments (pick one later):
     - Raise threshold (e.g. 3+), or
     - Add a short post-jump grace window before fall pose is allowed, or
     - Gate on actual downward movement occurring (not just vy sign/value).
   - Code refs: `main.asm` (`FALL_POSE_VY_THRESHOLD`, `JUMP_VELOCITY`), `movement.asm` (`.apply_gravity`), `render_state.asm` (`.compute_chell_render_state`).

2) Keyboard responsiveness is really bad
   
   - Symptom: RETURN sometimes needs many presses before jump triggers.
   - Primary hypothesis (strong): we currently sample keys every frame (`sample_keys`), but **gameplay update runs every other frame** (`sim_phase`), so one-frame edges in `keys_pressed` can be dropped.
     - A press that begins and ends during a skipped-update frame never reaches `poll_move_keys` (which reads `keys_pressed`).
   - Confirm in code:
     - `main.asm` main loop: update only when `sim_phase==0`.
     - `input.asm`: `keys_pressed = keys_held & ~keys_prev` is a one-frame pulse.
     - `movement.asm`: jump uses `keys_pressed & #4` (edge-triggered).
   - Galaforce-style next step (investigation output, not implementation): decide whether we want:
     - update every frame, OR
     - latch/queue important edge events (jump/portal fire/action) until the next update consumes them.
   - Code refs: `main.asm` (sim pacing), `input.asm` (`.sample_keys`), `movement.asm` (`.poll_move_keys`), `reference/galaforce_notes.md`.

3) Idle jump applies forward momentum
   
   - Repro is deterministic in code: if no left/right is held on the jump press, we still set `char_vx` from `last_anim_dir`.
   - Confirm:
     - `movement.asm` `.poll_move_keys` jump path: if neither left nor right is held, it falls through to `.jump_dir_done` and then uses `last_anim_dir` to set `char_vx` to +/-`WALK_VELOCITY`.
   - Next step: decide expected behaviour (straight up if no direction held vs preserve last direction).

4) Walking on portals should trigger them
   
   - Current rules (per code): must overlap portal rect and satisfy intent `dot(v,n_enter) < 0`.
     - Walls: requires `char_vx` sign matching portal orientation.
     - Floor/ceiling: requires `char_vy` sign (uses `char_prev_vy` when vy got zeroed on landing).
     - Back wall: requires SPACE (`action_held`).
   - Investigation checklist:
     - Ensure the portal overlap test is actually reachable while grounded (collision vs portal opening).
     - Validate that portal orientation sign expectations match movement direction the player uses to walk “into” a portal.
     - Confirm we aren’t missing the overlap due to the narrowed chell rect used when moving right/left (nose bias).
   - Code refs: `portal_teleport.asm` (`.check_portal_entry_intent`, `.cpei_overlap_portal_xy`), `movement.asm` (wall collision constraints).

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
