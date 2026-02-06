# Next Steps

This file tracks concrete, prioritized actions.
Detailed background/design context lives in `project plan.md`.
Architecture reference auto-loaded from `MEMORY.md`.
Full overhaul rationale in `.claude/plans/serene-herding-kahan.md`.

---

## P0: Movement Overhaul (3 tasks, do in order)

### Task 1: Fix direction-change early return + collision asymmetry

Two small edits that fix the "can't jump left" bug and collision asymmetry.

**Edit A — Remove early return on direction change**

File: `movement.asm`, lines 70-72. Current code:

```asm
      ; Jump started: return early so apply_gravity sees jump_active.
      SEC
      RTS
```

Delete these 2 lines (the `SEC` and `RTS`). The direction-change block at lines
62-69 should fall through to `.pmk_dir_ok` and continue to velocity + movement
code. This removes a 1-update-frame delay on direction changes and fixes the
missing horizontal drift when pressing LEFT+JUMP while facing right.

**Edit B — Remove redundant collision early exit**

File: `movement.asm`, line 322. Current code:

```asm
.will_collide_left
    JSR calc_char_x
    BEQ collide_left          ; ← delete this line
```

Delete the `BEQ collide_left` line. `step_left_pixel` (lines 241-246) already
prevents calling `will_collide_left` when x=0, so this is dead code. Removing it
makes the function symmetric with `will_collide_right` which has no such early exit.

**Test:**
- `./build.sh` succeeds, `.end < &5800`
- Boot in B2: walk left/right into walls (symmetric stopping distance)
- Face right, press LEFT+JUMP: Chell jumps leftward (was broken before)
- Face left, press LEFT+JUMP: still works
- Jump straight up (RETURN only): no horizontal drift
- Change direction while walking: no hesitation/pause frame

---

### Task 2: Restructure poll_move_keys into clean pipeline

Replace the tangled `poll_move_keys` (movement.asm:18-162) with a clean
`update_chell_movement` that separates concerns and has a single vx writer.

**New pipeline (inside update_chell_movement):**

```
1. update_grounded_state     ; ground probe (skip during jump arc)
2. update_facing_and_intent  ; keys → anim_dir, move_held, redraw flag
3. resolve_horizontal_vx     ; THE single vx writer (replaces 2 competing writers)
4. apply_horizontal_velocity ; pixel stepping with collision (KEEP AS-IS)
5. update_run_animation      ; anim_cooldown + frame advance
6. sync last_anim_dir
```

**resolve_horizontal_vx rules (single vx writer):**
- Grounded + key held: `vx = ±WALK_VELOCITY`
- Grounded + no key: `vx = 0`
- Airborne + key held + `|vx| <= WALK_VELOCITY`: `vx = ±WALK_VELOCITY`
- Airborne + `|vx| > WALK_VELOCITY`: preserve vx (portal fling)
- Airborne + no key: preserve vx (momentum)

**Also: remove vx-setting from ag_start_jump** (movement.asm:440-458).
Delete `ag_jump_set_vx_left`, `ag_jump_set_vx_right`, and the no-key `STA char_vx`.
Jump start only sets: `jump_active=1, jump_phase=0, char_grounded=0, char_vy=0`.
The vx is already correct from `resolve_horizontal_vx` which ran earlier.

**Update caller in frame_update.asm:128:**
Replace `JSR poll_move_keys` with `JSR update_chell_movement`.

**Keep these functions unchanged:**
- `apply_horizontal_velocity` (movement.asm:177-235) — well-structured step loop
- `step_left_pixel` / `step_right_pixel` — correct pixel stepping
- `apply_gravity` (movement.asm:406-555) — just remove the vx writes from jump start
- `step_up_8` / `step_down_8` — correct stripe stepping
- All collision probes (`will_collide_*`, `is_char_grounded`)
- `calc_char_x` / `calc_char_y`

**Test:**
- All Task 1 tests still pass
- Portal fling: emerge from portal with high vx, air control does NOT override it
- Walk off ledge: falls correctly, can steer in air
- Jump with no direction key: straight up (vx=0)
- `./build.sh` succeeds, `.end < &5800`

---

### Task 3: Remove dead ZP, constants, and dead code

Cleanup pass after the restructure is working.

**Remove dead ZP variables (main.asm):**
- `gravity_cooldown` (line ~38) — never read
- `rise_cooldown` (line ~39) — never read
- `fall_cooldown` (line ~40) — never read
- `move_cooldown` (line ~70) — never read (only written in reticle.asm)

**Remove dead write in reticle.asm:**
- Find `STA move_cooldown` and delete it (variable is never read)

**Remove dead constants (main.asm):**
- `GRAVITY_ACCEL`, `GRAVITY_UP_PERIOD`, `GRAVITY_DOWN_PERIOD`
- `JUMP_VELOCITY`, `RISE_STEP_PERIOD`, `FALL_STEP_PERIOD`
- (Keep `TERMINAL_VELOCITY_DOWN/UP` — used by portal_teleport.asm)

**Remove dead code (main.asm):**
- Check if `step_char_tile` (~lines 739-766) is called anywhere. If not, delete it.

**Remove init writes for deleted variables (main.asm init section):**
- Delete any `STA gravity_cooldown`, `STA rise_cooldown`, `STA fall_cooldown`,
  `STA move_cooldown` in the init block.

**Test:**
- `./build.sh` succeeds
- `.end` address should be a few bytes lower than before
- Full play-test: everything still works

---

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
