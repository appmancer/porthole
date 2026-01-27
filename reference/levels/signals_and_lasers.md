# Signals And Lasers (Design Notes)

This document captures an implementation-friendly plan for **signals** (triggers) and **lasers** as puzzle primitives.

Goal: enable Portal-style rooms where the player opens an exit door and reaches the exit, using buttons/pads/cubes/lasers (and portals).

## Signals (Channels)

Treat triggers as boolean **channels** (bits), evaluated every frame.

- A channel is either `0` (low) or `1` (high).
- Multiple sources can drive the same channel; combine with **OR**.
- Consumers (doors, droppers, etc.) read channels and change their state.

Recommended model:

- `sig_state[NUM_SIG_BYTES]` is the published signal state for this frame.
- Each update:
  - Clear `sig_state` to 0.
  - Update all *drivers* (pads, buttons, laser targets) and set bits in `sig_state`.
  - Update all *consumers* (doors, droppers, etc.) using `sig_state`.

This avoids hardcoding "door knows about pad" and allows remote puzzles.

### Scope of channels

Channels should be **level-global**, not per-room.

Reason: puzzles often use remote triggers (laser in room A opens door in room C).

## Object Types (Gameplay)

These are logical object types; their exact sprite/rendering is separate.

- `button`: momentary press (or optional toggle) -> drives a channel.
- `pad`: pressure plate; high while a cube or Chell is on it -> drives a channel.
- `laser_emitter`: emits a ray in one cardinal direction.
- `laser_target`: becomes "lit" if any laser ray reaches it -> drives a channel.
- `door`: blocks movement (and lasers) while closed; becomes passable while open.
- `exit`: winning trigger zone. Usually paired with a `door` (the exit door).

## Laser Rules (Logic)

### Ray propagation

A laser ray:

- starts at an emitter origin `(room, x, y)` with direction `dir` in `{left,right,up,down}`
- continues in a straight line until it hits something
- may pass through portals (turning / translating)
- may cross room boundaries through exits

### Blocking

The ray stops when it hits any of:

- solid world geometry
- a closed door
- a cube
- Chell

The ray may also hit a `laser_target` (in which case the target is lit and the ray stops).

### Portals

If the ray intersects a portal and is moving into its face:

- teleport the ray origin to the exit portal mouth
- rotate/redirect direction according to portal normal mapping (cardinal only)
- apply an "epsilon" offset along the exit normal so the ray does not immediately re-hit the portal

To avoid infinite loops:

- cap traversals per ray, e.g. `MAX_PORTAL_HOPS = 8`
- optionally maintain a small visited set of `(room, x, y, dir)` to early-out if repeating

### Crossing rooms via exits

Lasers can cross rooms. If a ray leaves the room bounds:

- check whether it is leaving through an exit opening (defined in `roomNN.meta`)
- if so, transition the ray into the destination room using the same edge mapping as Chell (opposite edge, preserve along-edge coordinate)
- if not, stop the ray

Cap cross-room travel to keep frame time bounded:

- `MAX_ROOM_CROSSES` or `MAX_TOTAL_STEPS`

## Laser Beam Rendering (Overlay)

Key constraint: the current renderer restores sprite rectangles from a clean background.

Therefore, laser beams must be treated as a **dynamic overlay** and redrawn each frame.

Recommended render order per frame:

1) Restore moved object rects from clean -> live.
2) Draw laser beam segments into the live buffer.
3) Draw sprites (Chell, cubes, reticle, etc.).

This ensures sprite restores never need to preserve/restore beams.

### Beam thickness tuned for MODE 5

MODE 5 pixels are not square (roughly 2:1 width:height).

To keep a roughly consistent visual thickness:

- vertical beam: **4 px wide** (exactly 1 screen byte)
- horizontal beam: **8 px tall** (8 scanlines)

This also keeps drawing fast and byte-friendly.

### Alignment constraints (for speed)

To avoid expensive partial-byte masking, constrain authoring:

- beam centerline X is always byte-aligned (`x % 4 == 0`)
- emitters/targets are placed so the above holds automatically

Practical authoring rule:

- define emitter/target position in room cells (8x16), but the engine snaps to a byte-aligned pixel X when computing the ray origin.

### Animation (optional)

Keep it cheap:

- alternate two byte patterns per frame (solid vs dashed), still byte-aligned
- do not do per-pixel noise

## Data Needed For Offscreen Simulation

Because lasers can originate in other rooms, we must be able to trace rays without requiring the full "current room" pixel-precise material planes.

Recommended approach:

- store a compact per-room collision grid for laser tracing:
  - 16x16 cells (same as `roomNN.txt`) is enough for axis-aligned rays
  - 1 bit per cell (solid/non-solid) => 32 bytes per room
- keep dynamic object state (cube positions, door open/closed, portal placements) for all rooms
- offscreen physics is allowed to "sleep": object positions are stable until the room becomes active again

Note: if we later need pixel-accurate beam blocking, we can refine the grid, but start with cell-level to keep it simple and cheap.

## Metadata / Authoring (Planned Extensions)

`reference/levels/meta_spec.md` currently supports:

- `exit ... -> roomNN`
- `obj cube|button|pad|exit x y`

Planned additions (syntax sketch, not final):

```text
# Signals are small integers, level-global.
# Drivers
obj button <x> <y> out <sig>
obj pad    <x> <y> out <sig>
obj target <x> <y> out <sig>

# Emitters specify direction; no signal directly (targets drive signals).
obj laser  <x> <y> dir <left|right|up|down>

# Consumers
obj door   <x> <y> in <sig>
obj dropper <x> <y> in <sig>
```

Open question: do we want multi-input doors?

- simple: `in <sig>` (door opens if that bit is high)
- advanced: `inmask <hex>` / `inall <sig0> <sig1> ...` for AND semantics

Recommendation: start with single-input OR-only; add AND later only if needed.

## Implementation Stages

Stage 1: Signals + doors (no lasers)

- Implement `sig_state` bits.
- Pads/buttons drive bits.
- Doors consume bits (toggle solidness + visuals).

Stage 2: Laser targets (no beam rendering)

- Trace rays in logic only; light targets and set signal bits.
- Keep strict caps to guarantee frame time.

Stage 3: Beam rendering (current room only)

- Overlay draw after restores.
- Use byte-aligned chunky beam.

Stage 4: Cross-room tracing

- Allow rays to cross exits into other rooms.
- Draw only the part in the current room.

Stage 5: Portals + cross-room

- Ray portal traversal + caps.
- Regression test for loops and worst-case traversal.
