# Laser System Plan

## Goal

Add laser emitters that fire beams through the tile grid. Beams pass through
portals (redirecting based on exit orientation) and activate laser targets to
drive signal channels. This is the core puzzle mechanic for redirecting beams
using player-placed portals.

## Design Decisions

### Tile-based beams (not pixel overlay)

Beams are rendered as **tiles stamped into the tilemap**, not as per-frame pixel
overlays. This is cheaper (no per-frame redraw) and integrates with the
existing tilemap rendering pipeline.

Beam tiles from the tileset:
- T38, T39: horizontal beam (left-right)
- T40, T41: vertical beam (up-down)
- T50, T51: crossroads (two beams crossing at 90 degrees)

Portal-back beam tiles: selected when the underlying tile is 19, 40, or 41
(portal-back surfaces).

### Static segment + dynamic segment

The beam is split into two parts:

1. **Static segment** (emitter → wall): The emitter position, direction, and
   termination wall are known from level geometry. The beam always reaches
   this wall — the level is designed to guarantee it. This path is
   precomputed at level load (or build time) and never changes.

2. **Dynamic segment** (portal exit → onwards): Only exists when a portal
   is placed on the wall where the static beam terminates. The beam enters
   the portal and exits the paired portal in a new direction. This part
   requires a grid-walk trace and changes whenever portals move.

This means the common case (no portal on the beam's wall) is trivially cheap:
just stamp the static beam tiles and check if a target is in the direct path.

### Retrace on every portal change

Every portal placement or removal triggers a beam recheck, because:

- Placing a portal on the beam's wall **creates** a redirect (beam passes
  through, potentially reaching a new target → signal ON)
- Removing/moving a portal off the beam's wall **breaks** the redirect
  (beam stops at wall again, target no longer lit → signal OFF)
- Placing portal B might move portal A away from the beam's wall
  (portals of the same colour replace each other)

The recheck must update signal state in both directions (on AND off).

### Chell and cubes do not block lasers

In our 2D world, objects are "in front of" the beam plane. Only solid
world geometry (walls, floors, ceilings) blocks beams. This avoids
per-frame retrace when objects move.

### No loop detection needed

Level design rules prevent placing portals behind emitters, so beam loops
cannot occur. A safety cap of ~64 steps is cheap insurance.

## Beam Trace Algorithm

### Phase 1: Static segment (precomputed)

At level load, for each emitter:

1. Start at emitter tile, walk in emitter direction
2. Record each tile position (these are the static beam tiles)
3. Stop when hitting a solid wall
4. Store: emitter direction, list of beam tile positions, wall-hit tile

This runs once and produces a fixed beam path per emitter.

### Phase 2: Portal check (on every portal change)

For each emitter's wall-hit tile:

1. Is there a portal on this tile?
   - Check portal_a and portal_b positions against the wall-hit tile
   - Entry condition: beam direction must be "into" the portal face
     (see entry table below)
2. If **no portal**: beam stops at wall. Check if a target is in the
   static path → update signal accordingly.
3. If **portal**: beam enters. Continue with dynamic trace from exit portal.

### Phase 3: Dynamic trace (grid walk from portal exit)

```
position = exit portal tile
direction = exit portal's outward normal
steps = 0

while steps < MAX_STEPS:
    advance position one tile in direction

    if out of bounds or solid wall:
        stop

    if tile is laser_target:
        activate target's signal channel
        stop (target absorbs beam)

    if position overlaps ANOTHER portal AND direction is "into" it:
        redirect through that portal (second hop)
        (continue from new exit portal)

    if room == current_room:
        record (position, beam_tile_id) for stamping

    steps += 1
```

Multiple portal hops are possible (beam redirected through two or more
portal pairs). The step cap prevents runaway.

### Portal direction mapping

Beam direction is always cardinal. When a beam enters a portal, the exit
direction is the exit portal's outward normal:

| Exit portal orient | Exit normal | Beam exits going |
|--------------------|-------------|------------------|
| WALL_L (0)         | (+1, 0)     | right            |
| WALL_R (1)         | (-1, 0)     | left             |
| FLOOR (2)          | (0, -1)     | up               |
| CEIL (3)           | (0, +1)     | down             |

Entry condition: beam must be going "into" the entry portal face.

| Entry portal orient | Beam must be going |
|---------------------|--------------------|
| WALL_L              | left               |
| WALL_R              | right              |
| FLOOR               | down               |
| CEIL                | up                 |

Back-wall portals (orient=4) do not interact with lasers.

### Beam tile selection

- Horizontal beam (left or right): stamp horizontal beam tile
- Vertical beam (up or down): stamp vertical beam tile
- If a tile already has a beam in the perpendicular direction: stamp crossroads tile

## Storage

### Static beam data (per emitter, precomputed at level load)

Per emitter:
- `emitter_room`: room the emitter is in
- `emitter_dir`: beam direction (0-3 = left/right/up/down)
- `emitter_tile`: starting tile position
- `emitter_wall_tile`: tile position where beam hits the wall
- `emitter_beam_length`: number of tiles in the static segment

The static beam tile positions are implicit: they're a straight run from
emitter_tile in emitter_dir for emitter_beam_length tiles.

Size: ~5 bytes per emitter. Level 1 has 1 emitter = 5 bytes.

### Current room beam list (dynamic segment + static segment)

A small array of `(tile_pos, original_tile)` pairs for the current room's
active beam tiles (both static and dynamic segments). Used to stamp and
unstamp beams.

- Max entries: ~30 (a room is 16x16; a beam is a straight line, maybe 16
  tiles per segment, with 2-3 segments after portal redirects)
- Size: 30 entries x 2 bytes = 60 bytes
- Location: labeled allocation in persistent_objects_data.asm

### Beam count

A single byte `beam_tile_count` tracking how many entries are in the list.

### Target lit state

A byte per target object: 0 = unlit, 1 = lit. Read by the signal pass.

### No per-room beam storage needed

On room entry, stamp beams for the new room. On room exit, unstamp.
Only the current room's beam tiles are stored.

## Retrace Triggers and Sequence

### On portal placed or removed

1. **Erase old beams**: unstamp old beam tiles in current room (restore
   original tiles in tilemap from beam list)
2. **Re-render erased positions on screen** (old beam visually disappears;
   same tile re-render mechanism used by portal stamp/unstamp)
3. Clear beam list and all target-lit flags
4. For each emitter:
   a. Recompute static segment (stamp beam tiles emitter → wall)
   b. Check if beam's wall-hit tile has a portal on it
   c. If yes: trace dynamic segment from exit portal, stamping beam tiles
   d. Mark any targets hit as lit
5. **Re-render new beam tile positions on screen** (new beam visually appears)
6. Update signal channels from target-lit flags
   (signal may turn ON or OFF depending on whether redirect still works)

Both the erase (steps 1-2) and draw (steps 4-5) must update the screen,
not just the tilemap. This ensures the old beam path disappears even if
the new path is completely different.

### On room entry

1. Clear beam list
2. For each emitter: compute static + dynamic beams
3. Stamp beams for new room
4. Render room (beams are part of the tilemap at this point)
5. Update signal channels

### On room exit

1. Unstamp current room's beams (restore originals)
2. Clear beam list

### On restart_level

Tilemaps are reloaded from generated data. Beam list is cleared.
No unstamping needed. Static beam data is recomputed at level load.

## TMX Authoring

Objects are authored in the TMX objectgroup `meta`:

- `laser` (type="laser"): emitter position and direction
  - Properties: `id` (string), `channel` (int)
  - Position: tile-aligned (x, y in pixels; div 16 for tile coords)
  - Direction: derived from position (e.g. on left wall = fires right)
    or explicit `dir` property
  - Example: room00 has `laser_0` at (0, 32), channel 1

- `target` (type="target"): receiver that drives a signal when lit
  - Properties: `id` (string), `channel` (int)
  - Position: tile-aligned
  - Has inactive/active tile visuals (swapped like pads/exits)
  - Example: room01 has a target at (224, 32), channel 2

`laser_portal_point` from the project plan is NOT needed as a separate
object type. Any portalable surface can redirect the beam — the player
decides where to place portals.

## Signal Integration

Laser targets act as signal **drivers** in the existing signal system:

- During beam recheck, each target gets a `lit` flag (0 or 1)
- In `update_signals_and_object_states`, lit targets set their channel
  bit in the signal state
- Consumers (exits, spawners) react to channel state as normal
- When a portal change causes a target to become **unlit**, the signal
  drops and consumers respond (e.g. exit closes, spawner stops)

## Files to Change

| File | Change |
|------|--------|
| main.asm | Add beam tile constants, beam list ZP vars, target-lit state |
| persistent_objects.asm | Add laser target as signal driver; call beam recheck |
| persistent_objects_data.asm | Beam list storage, static emitter data |
| frame_update.asm | Call beam recheck on portal placement |
| new laser.asm | `init_beams` (precompute static), `recheck_beams` (portal check + dynamic trace), `stamp_beams`, `unstamp_beams` |
| tools/gen-level | Parse laser and target from TMX meta; emit emitter table and target table |
| levels/level1/*.tmx | Emitter and target objects (already partially authored) |

## Size Estimate

- Static beam init: ~80 bytes (walk to wall, store data)
- Portal check + dynamic trace: ~180 bytes (grid walk + portal lookup)
- Stamp/unstamp helpers: ~60 bytes
- Beam list storage: ~64 bytes (30 entries x 2 + count + padding)
- Emitter/target tables: ~8 bytes per emitter, ~6 bytes per target
- Signal integration: ~40 bytes
- Total: ~370 bytes code + ~80 bytes data

Well within budget (10,012 bytes headroom).

## Implementation Stages

1. **Static beam only** (no portals, no signals)
   - gen-level parses emitter from TMX, emits emitter table
   - init_beams walks from emitter to wall, stores static data
   - stamp_beams fills beam tiles in current room
   - Verify: beam appears on screen from emitter to wall

2. **Targets + signals**
   - gen-level parses targets, emits target table
   - Trace checks for target tiles in beam path
   - Target lit → signal channel → exit opens (or spawner fires)
   - Verify: target in direct beam path activates signal

3. **Portal redirection**
   - On portal change, recheck beam wall-hit tile for portal
   - If portal present: dynamic trace from exit portal
   - Signal activates/deactivates based on whether redirect reaches target
   - Verify: place portal on beam wall → beam redirects → target lit
   - Verify: remove portal → beam stops at wall → signal drops

4. **Cross-room tracing + room transitions**
   - Dynamic trace follows beam into other rooms via portals
   - Only stamp tiles in current room
   - Unstamp on room exit, restamp on room entry
   - Verify: portal A in room00 on beam wall, portal B in room01 →
     beam visible in room01

## Test Plan

1. Emitter in room00 fires right; beam tiles appear across the room
2. Target in direct path; signal activates on level load
3. Place portal A on beam's termination wall, portal B on floor elsewhere;
   beam redirects upward from portal B
4. Move portal A elsewhere; beam returns to wall, signal drops
5. Place portals to route beam from room00 into room01 to hit target;
   signal activates
6. Walk to room01; beam tiles visible there
7. Place portals to make beam cross its own path; crossroads tile appears

## Design Constraints

- Avoid lasers crossing exit boundaries or back-wall portal surfaces
  (level design rule, not enforced in code)
- Emitter positions are fixed per level (not moveable objects)
- A beam that exits the 16x16 tile bounds without hitting anything just stops
- Beams do not kill Chell (could be added later as a separate hazard check,
  similar to acid, using the beam list to test overlap)
- Back-wall portals (orient=4) do not interact with lasers
