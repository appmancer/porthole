# PORTHOLE – Rendering & Memory Plan (Master-only)

This document captures the current design direction for PORTHOLE’s 2D platformer engine on the BBC Master (emulator-first). It is intentionally a draft: we’ll keep it consistent, and revise it when reality forces us to.

## Goals

- Smooth-feeling character movement and animation (including per-pixel substeps).
- Sprites never leave trails; no tile-redraw “guesswork” for cleanup.
- Room transitions are instant (flick-screen), with predictable performance.
- Asset pipeline is repeatable (no manual hex transcription).

## Core Idea

Treat backgrounds as *bitmaps* at runtime.

- Build a room’s background once into a **clean background buffer**.
- During gameplay, sprites are drawn onto a **live buffer**.
- When a sprite moves, erase by copying the affected rectangle from clean → live.

This removes the need to re-render tiles behind sprites in the hot path.

## Master-only Memory Model

We target BBC Master 128.

Important correction/clarification: on the Master, “shadow RAM” usually refers to the **LYNNE** region (20KB) of the upper 32KB of standard RAM that can be paged in as **shadow screen memory**, not a whole extra 64KB linear RAM bank.

The Master’s extra 128KB RAM is broadly:

- **32KB main user RAM** (`&0000..&7FFF`, with some areas paged/overlaid depending on configuration)
- **Upper 32KB of standard RAM**, which can be paged into different logical ranges for:
  - **LYNNE (20KB)**: shadow screen capability (paged over `&3000..&7FFF`)
  - **HAZEL/ANDY**: MOS/ROM workspace
- **64KB sideways RAM**: four 16KB banks, paged into `&8000..&BFFF`

For PORTHOLE we still keep the guiding principle:

- **Main RAM**: game logic, state, tables, code.
- **Shadow screen (LYNNE)**: used for screen memory when we enable it.
- **Sideways RAM**: a candidate for bulk assets or additional buffers if we choose.

For the current working memory map and the update-then-render (PoP-style)
bank-mapping policy, see `memory_map.md`.

### Screen Geometry (current)

- Display is a custom MODE 5:
  - CRTC horizontal displayed = 32 bytes per scanline (128px wide).
- Renderer treats playfield as:
  - 16 tile rows
  - 512 bytes per tile row (32 bytes/scanline × 16 scanlines/tile)
- Playfield footprint: `&5800 .. &77FF` (8KB)
- “Below playfield” region: `&7800 .. &7FFF` (2KB)

`&7800..&7FFF` is only “scratch” by convention: it is still screen memory, but it is outside the playfield footprint in our current layout.

## Memory Map (Draft)

Addresses are subject to change, but we should avoid scattering.

- **Code**: assembled at `&1900`
- **Screen playfield (visible)**: `&5800 .. &77FF`
- **Screen scratch (below playfield)**: `&7800 .. &7FFF` (2KB, by convention)
- **Material plane `solid` (1bpp)**: `&3000 .. &3FFF` (4KB)
- **Portalable tile-layer (sparse, 16×16 bytes)**: stored per-room with `portalmap_ptr`

## Buffer Plan (Draft)

Long-term (Master-only target):

- Keep pixel buffers in shadow/Aux RAM.
- Keep gameplay logic and authoritative collision/materials in main RAM.

Today’s implementation uses a 128-byte save-under buffer at `&7800` to preserve the demo while material planes occupy `&3000..&4FFF`.

> If we later decide to use full 10KB MODE 5 buffers, we must revisit the `&7800..&7FFF` scratch convention.

## Rendering Pipeline

### Room load / transition

1) Populate **clean playfield buffer**.
   - Either stamp tiles into it, or decompress a pre-rendered room.
2) Initialize **live playfield buffer** by copying clean → live (8KB copy).
3) Enter gameplay loop.

### Gameplay frame loop (high level)

For each moving object (starting with Chell):

1) Restore last frame’s rectangle: copy from clean → live.
2) Draw the new sprite frame (masked blit) into live.

The hot path should not call the tile renderer.

### Rendering pipeline plan (PoP/SpyCat-inspired)

Goal: make rendering predictable and cheap, so we can finish all restore+draw work immediately after VSYNC and avoid top-of-screen tearing.

**P1: Treat rendering as a pipeline (PoP “peel list” discipline)**

- Build a small **render list** during update (for the *next* frame): Chell, reticle, cube, etc.
  - Each entry includes:
    - `needs_redraw` (object moved or must be reblitted)
    - `prev_ptr` + `has_under` (for restore)
    - `new_ptr` (screen pointer for new draw position)
    - `sprite_id` / `frame_id` and any palette/variant flags
    - `bank_id` (sideways RAM bank for sprite reads)
- Render phase (immediately after `wait_vsync`) executes two explicit passes:
  1) **Restore pass (peel)**: for each `needs_redraw && has_under`, restore under in reverse list order (LIFO).
  2) **Draw pass**: for each `needs_redraw`, save-under at `new_ptr` and blit the chosen sprite.
- Invariants:
  - Never “save-under” if any overlapping newer sprite is still visible (restore-first avoids under-buffer contamination).
  - Always restore newest-first when objects can overlap (LIFO).

**P2: Keep post-VSYNC work minimal (SpyCat table-driven setup)**

- Do sprite/frame selection and as much pointer math as possible in update.
- Make screen pointer computation table-driven and branch-light:
  - row base pointer tables + column offset tables (SpyCat pattern)
  - avoid general multiplies/divides in the render phase
- Where possible, group draws by `bank_id` so we can page SWRAM once per render pass (rather than per sprite).

**P3: Evolve to BG/MID/FG lists (PoP layering)**

- BG: room drawn once per load (or on room transitions)
- MID: moving gameplay objects (Chell, cubes, pellets)
- FG: foreground cover tiles/props (pipes/grates) drawn after MID to create depth without per-pixel occlusion

## Sprites

### Sprite storage

- Sprites are stored as:
  - pixel bytes
  - mask bytes
- Masked blit rule:
  - `dst = (dst & mask) | pix`

### Per-pixel movement

We already author subpixel variants (x offsets 0..3) per pose.

- Maintain `x_sub` in range 0..3.
- Sprite selection becomes `(pose, x_sub)`.
- The current sprite data format stays **4 bytes per scanline** (16px window), with the 4th byte acting as spill/empty as needed (character is ~12px wide).

Gameplay simplification (current plan):

- **Collision/physics is only evaluated when `x_sub = 0`**.
- Horizontal motion still looks smooth because we render `x_sub` 0..3, but we only apply collision resolution and state transitions at the aligned phase.

## Background restore strategy

### Phase 1 (recommended)

Use rectangle restore from clean buffer:

- Choose a fixed restore rectangle that safely covers the sprite footprint.
- Start simple: 4 bytes wide × 32 scanlines = 128 bytes.
- If we add effects/overlap, expand to a slightly wider rect or per-object rect sizes.

### Phase 2 (optional)

If we need many moving objects and more complex overlapping, consider:

- object render ordering rules
- dirty-rect list
- restore batching

But start with correctness and simplicity.

## Tooling / Asset Pipeline

### Sprites

- Source CSVs live in `sprites/`.
- `tools/gen-sprites` generates:
  - `sprites/generated_chell_sprites.asm`
  - `sprites/generated_chell_masks.asm`
- `build.sh` runs the generator before assembling.

### Rooms / Backgrounds (current)

We already have a repeatable room pipeline, and we now treat Tiled as the source of truth for both tiles and gameplay objects.

Authoring files

- Room tiles are authored per-room under `levels/<level>/`:
  - `roomNN.tmx` (Tiled TMX, preferred)
  - `roomNN.txt` (legacy glyph grid, still supported)
- Room transitions (flick-screen exits) are authored in TMX objectgroup `meta`:
  - rectangle objects of type `edge_exit`
  - property `to=roomNN`
- Gameplay objects (cube/button/pad/exit) are authored in TMX objectgroup `objects`:
  - point objects with type `cube|button|pad|exit`
  - required property `id=<string>` unique across the whole level (for persistence)
  - property `channel=<int>` (defaults to 0 in tooling if omitted)
- Legacy gameplay metadata (`roomNN.meta`) remains as a fallback only (see `reference/levels/meta_spec.md`).

Build outputs

- `tools/gen-level` compiles the authored rooms into `levels/generated_level1.asm`:
  - room tilemaps (256 bytes per room)
  - edge-exit lookup tables (per-room)
  - gameplay object tables (per-room for now; will evolve to persistent level-global indices)

Tiles

- Tile pixel art source: `sprites/NewTiles - Grid.csv`
- `tools/gen-tiles` compiles it into `sprites/generated_tiles.asm` (tile IDs must stay stable).
- For Tiled authoring, `tools/gen-tileset-png` can generate a preview tilesheet at `tiled/porthole_tiles.png`.

Gameplay object sprites

- Object sprites are authored as CSVs under `sprites/` and compiled via `tools/gen-sprites`.
- Current object sprite contracts:
  - `cube`: 16x16 masked
  - `button`: 16x16 masked, 2 states (inactive/active)
  - `pad`: 16x16 masked, 2 states (up/down)
  - `exit`: 16x32 masked, 2 states (closed/open) so Chell can pass through
- State ordering convention for 2-block CSVs: block 0 = inactive/up/closed, block 1 = active/down/open.

Persistence + signals (design direction)

We need puzzle state to persist across room transitions, so we treat objects as level-global entities.

- Authoring identity: every TMX object has a stable `id` (string), unique across the whole level.
- Build-time mapping: convert `id` strings to a stable `obj_index` and emit compact runtime tables:
  - `obj_defs[]`: type, channel, initial flags, home room/x/y
  - per-room lists of `obj_index` values
- Runtime state arrays indexed by `obj_index`:
  - `obj_state[]` (pressed/open bits etc.)
  - `obj_room[]`, `obj_x[]`, `obj_y[]` (cube requires these; others can be fixed to home)
- Signals are derived each frame from state + contacts:
  - `pad` pressed if Chell stands on it OR cube rests on it
  - `button` pressed on SPACE (action key) while Chell overlaps the button zone
  - `exit` open if `signal_bits & (1<<channel)`

## Switching Rules

- No per-byte/per-scanline bank switching.
- Any shadow/main mapping changes must happen:
  - at init,
  - on room transitions,
  - or at most once per frame.

## Material Planes (Collision / Interaction Truth)

Backgrounds are cosmetic only; gameplay uses separate *material planes*.

We use **two 1bpp planes** for PORTHOLE:

- `solid` (1 = blocks movement)
- `portalable` (1 = portal may be placed; should imply `solid=1`)

For a 128×256 playfield:

- 1 plane = 128×256 bits = 4096 bytes (4KB)
- 2 planes = 8KB per room (working-set)

If we later need other mechanics (deadly, bouncy, one-way, etc.), we add more planes rather than overloading existing meanings.

### Authoring vs runtime

- Authoring/storage can remain tile-based or compressed.
- On room load, expand/build the two 1bpp planes into RAM for pixel-perfect queries.

### Core queries

- `is_solid(x,y)` reads `solid` plane bit.
- `is_portalable(x,y)` reads `portalable` plane bit.

## Portal Reticle + Line Of Sight (Plan)

### Summary

We want portal placement to be a *decision/puzzle*, not a precision movement test.

Because Chell only moves left/right, we add a SHIFT-held reticle mode to allow aiming at any portalable surface (including high placements on “back wall/flats” type surfaces).

### Controls

- Normal mode: `Z/X` move Chell left/right.
- Reticle mode: hold **SHIFT** to control a portal reticle.
  - While SHIFT held:
    - `Z/X` move reticle left/right
    - cursor `Up/Down` move reticle up/down

(We still keep “quick shot” aiming available while jumping/falling; reticle mode is for deliberate placements.)

### Reticle snapping

- Reticle snaps to a **16×16 portal grid**.
- Because the renderer’s base cell grid is 8×16, a 16×16 portal grid means:
  - X steps are 16px (2 tiles/cells)
  - Y steps are 16px (1 tile/cell)

### Reticle visuals (size)

- Reticle should be small enough to not obscure the target surface, but large enough to read in MODE 5.
- We snap to a 16×16 portal grid, so we can represent the cell center cleanly.
- Recommended: **8×8 crosshair** centered on the portal-cell center `(cell_x*16+8, cell_y*16+8)`.
  - This avoids needing a full 16×16 sprite.
  - If we want clearer “cell framing”, add an optional faint 16×16 outline later.

### Development plan

Stage 0: Input + state (no rendering)

- Add a `reticle_active` boolean (SHIFT held), plus `reticle_cell_x` (0..7) and `reticle_cell_y` (0..15).
- On first entry into reticle mode, initialize reticle position from Chell’s gun position (snap to portal grid) so the reticle starts “where the player is looking”, not at an arbitrary corner.
- While reticle mode is active:
  - `Z/X` move `reticle_cell_x` left/right (clamped 0..7)
  - cursor `Up/Down` move `reticle_cell_y` up/down (clamped 0..15)
- Ensure we retain “quick shot” behaviour outside reticle mode (so portals can be fired while jumping/falling without entering reticle mode).

Stage 1: Reticle rendering (no portal placement yet)

- Reticle must not leave trails. Use the existing save-under mechanism:
  - At start of each frame, restore all previous save-under rectangles once.
  - Save-under and draw Chell.
  - Save-under and draw the reticle.
- Reticle sprite assets: two 8×8 masked sprites (valid/invalid). (User to supply red/green versions.)
- Reticle screen position:
  - Convert `reticle_cell_x/reticle_cell_y` to pixel coordinates.
  - Draw centered within the portal cell (see “Reticle visuals”).

Stage 2: Placement validity (ignoring LOS)

- Define what “portalable” means for this stage:
  - Either derived from tile type (e.g. brick tiles are portalable), or a separate portalable plane.
  - For now, treat this as a plug-in query `is_portalable_surface_at(cell_x, cell_y, orientation)`.
- Add a `reticle_state` enum for feedback:
  - `RETICLE_INVALID_SURFACE`
  - `RETICLE_VALID_SURFACE_NO_LOS`
  - `RETICLE_VALID_SURFACE_AND_LOS`
- Compute the placement footprint from the portal size:
  - Portals span 16px along the surface.
  - When checking placement, validate the whole footprint (not just the anchor cell).

Stage 3: Line-of-sight raycast

Rules (agreed):

- Only the tile world blocks LOS (floors/ceilings/walls). Dynamic objects never block LOS.
- LOS is evaluated against the full visible tile field (screens may show two rooms at once).
- LOS succeeds if Chell can see either the **top** or **bottom** sample point of the target portal cell.

Implementation outline:

- Define start point `(gun_x, gun_y)`.
- Define target points for the portal cell:
  - top sample: `(target_x, cell_y*16 + 1)`
  - bottom sample: `(target_x, cell_y*16 + 15)`
  - Where `target_x = cell_x*16 + 8` (center).
- Perform a grid raycast for each sample (integer DDA / Bresenham style).
  - Step across the underlying **collision tiles** (8×16) and query solidity.
  - A ray is blocked if it enters a solid tile before reaching the target.
- Reticle is “green” only if placement is valid AND LOS passes.

Stage 4: “Enter portal” intent (back wall / flats concern)

Open question (agreed to document first): if the back wall/far plane can host portals, how do we prevent accidental entry when Chell runs past?

Candidate policies:

- Require an explicit “enter” input while overlapping a portal (e.g. hold `Up` or press `RETURN`).
- Treat far-plane portals as a separate interaction mode (enter/exit toggles plane).
- Add a small “deadzone” so simply crossing the portal’s X-range doesn’t trigger; require being centered and pressing a direction.

### Validity feedback

- Reticle indicates at least:
  - placeable + LOS (e.g. “green” or solid)
  - not placeable (e.g. “red” or hollow)
  - blocked by LOS (e.g. “X” overlay)

### LOS rules (agreed)

- Floors, ceilings, and walls all block LOS.
- Only the tile world blocks LOS; dynamic objects (cubes/buttons) do not.
- Some screens may show two rooms at once; LOS is evaluated against the **full visible tile field**.

### LOS condition (agreed)

- For a target tile, Chell has LOS if she has clear line-of-sight to **either**:
  - the top sample point of the tile, OR
  - the bottom sample point of the tile.

This makes portal placement tolerant: if the top edge is visible, you can still place a portal even if the lower edge is occluded (and vice versa).

### LOS algorithm (concept)

- Define a start point at Chell’s portal gun position `(gun_x, gun_y)`.
- Define two target points at the reticle location:
  - `(target_x, target_y_top)`
  - `(target_x, target_y_bottom)`
- Perform a 2D tile-grid raycast for each target point (integer DDA / Bresenham stepping across tiles).
- A ray is blocked if it hits any `solid` tile before reaching the target.
- LOS passes if either ray reaches the target unblocked.

### Open questions

- Entering “back wall” portals: how do we capture player intent so Chell doesn’t accidentally enter while just running past?
  - Candidates: require an explicit “enter” input while overlapping, or use a direction modifier (e.g. hold Up), or treat back-wall portals as a separate interaction mode.
- How do we choose the portal surface normal under the reticle (wall/floor/ceiling/back wall) when multiple surfaces overlap in screen space?
- How should reticle mode interact with jumping/falling (can the player hold SHIFT midair, does it freeze Chell horizontal movement, etc.)?

## Portal Teleportation Rules (Design)

This section captures the intended "Portal feel" for teleportation in our 2D side-on interpretation.

### Coordinate system + portal frame

- Screen space: +X right, +Y down.
- Velocity `v = (vx, vy)`.
- Each portal has a local frame:
  - `n` = portal normal pointing *out* of the portal (the direction you exit).
  - `t` = portal tangent along the portal surface.
- Define a deterministic tangent from the normal:
  - `t = perp(n) = (-n_y, n_x)`

### Entry intent ("push into it")

- Teleport triggers only if Chell overlaps the portal rectangle and is moving into its face:
  - require `dot(v, n_enter) < 0`.

### Momentum preservation (velocity, not facing)

- Preserve momentum magnitude and components relative to the portal plane. Do not preserve facing.
- Compute components in the *enter* portal frame:
  - `v_t = dot(v, t_enter)` (tangent component, signed)
  - `v_n = -dot(v, n_enter)` (speed into the portal, positive when entering)
- Recompose in the *exit* portal frame:
  - `v' = v_t * t_exit + v_n * n_exit`

This automatically enables "flinging": high-speed falls can convert into high-speed horizontal/vertical exit motion.

### Canonical normals (side-on)

- Left-wall portal (exit right): `n=(+1, 0)`, `t=(0, +1)`
- Right-wall portal (exit left): `n=(-1, 0)`, `t=(0, -1)`
- Floor portal (exit up): `n=(0, -1)`, `t=(+1, 0)`
- Ceiling portal (exit down): `n=(0, +1)`, `t=(-1, 0)`

### Exit facing + grounded state

- Always clear grounded state on teleport.
- Facing is derived from the exit:
  - wall exits: face away from the wall (from `n_exit.x`)
  - floor/ceiling exits: face by horizontal motion sign (`sign(v'.x)`) or last input

### Exit placement + anti-ping-pong

- On exit, place Chell slightly outside the exit portal along `n_exit` so she is not still overlapping.
- Add a short post-teleport cooldown / grace distance so she cannot immediately re-trigger.

### High-speed traversal (tunnelling)

- Teleport detection must still work when Chell moves faster than 1px/frame (terminal velocity / fling speeds).
- Teleport detection must still work when Chell moves faster than 1px/frame (terminal velocity / fling speeds).
- Later this likely implies a swept/stepped check against the portal rectangle to avoid skipping through it.

### Tuning targets (initial)

- Teleportation itself is lossless (no damping).
- Airborne motion should be lossless (no per-frame drag), so the "bouncy elevator" can run forever.
- Gravity: `g = 1 px/frame^2` (simple integer).
- Terminal velocity ("spicy" fling cap): `vy_terminal = 28 px/frame`.
  - Roughly 1.5 screens of rise from a floor exit in the no-drag ideal case (`h ~= vy^2/(2g)`).

### Sanity checks (classic maneuvers)

- Terminal fall into floor, out floor: `v=(0,+V)` -> `v'=(0,-V)`.
- Run into right-wall portal, out floor: `v=(+V,0)` -> `v'=(0,-V)`.
- Fall into floor, out right-wall portal: `v=(0,+V)` -> `v'=(-V,0)`.

## Procedural Portal Rendering ("Probability Portal", no side-on sprite)

### Motivation

In a 4-colour palette, we want portals (A/B) to be highly readable without having to reserve red/yellow inside background tiles. A mostly monochrome background (cyan/black) keeps the level readable while letting portals and interactive objects “own” the highlight colours.

Instead of using authored portal sprites (at least for side-on portals), generate a portal’s look procedurally **once at placement time** and then treat it as part of the background.

### Core requirements

- **No shimmer**: portal pixels must be stable frame-to-frame.
- **Cheap at runtime**: generation happens only on placement/move; rendering loop treats portal as background.
- **Deterministic but varied**: each placement should look slightly different, but remain stable after creation.
- **Blend + connection hint**:
  - portal is clearly “mostly A” (red) or “mostly B” (yellow)
  - portal optionally contains a small amount of the *other* portal colour to suggest connection
  - portal colour “bleeds” into the surface for a few columns (e.g. max 5 columns deep)

### Rendering model

- On portal placement:
  - compute and store a per-portal `portal_seed` (1–2 bytes) so the pattern is stable for that portal instance.
  - stamp the portal into the **clean background buffer**, then copy that rectangle into the **live buffer** (or redraw that rect immediately) so sprite restore works naturally.
- On portal removal:
  - restore the affected rectangle from clean background (or rebuild the clean background for that room if needed).

### Pattern generation: ordered dither (recommended)

Avoid per-pixel PRNG calls (costly) and instead use a small threshold map (e.g. 4×4 ordered dither) to approximate “probability” as coverage.

- Let `t` be a threshold 0..15 from a 4×4 table.
- The table lookup is phase-shifted by the portal seed so each placement is different:
  - `tx = (x + seed_x) & 3`
  - `ty = (y + seed_y) & 3`
  - `t = dither4x4[ty*4 + tx]`
- For each pixel in the portal footprint:
  - if `t < main_level` → write the portal’s main colour
  - else if `t < main_level + alt_level` → write the other-portal colour
  - else → leave the underlying pixel unchanged

This produces the intended “probability rule” look while remaining deterministic and stable.

#### Example `dither4x4`

Any low-discrepancy 4×4 threshold pattern works. One common choice is a 4×4 Bayer matrix (values 0..15):

- ` 0  8  2 10`
- `12  4 14  6`
- ` 3 11  1  9`
- `15  7 13  5`

Store it in row-major order as 16 bytes (0..15). The seed offsets select different phases of the same pattern.

#### Portal seed suggestions

Goal: stable for an instance, but different each time you place (even at the same location).

- Maintain a monotonically increasing `portal_place_counter` (wrap is fine).
- On placement, derive `portal_seed` from a mix of:
  - `portal_place_counter`
  - `reticle_cell_x`, `reticle_cell_y`
  - Chell’s position (`char_tile_pos`, possibly `char_pixel_offset`)
  - `current_room`

Example (conceptually):

- `seed_x = portal_place_counter ^ reticle_cell_x ^ (char_tile_pos << 1)`
- `seed_y = (portal_place_counter << 1) ^ reticle_cell_y ^ current_room`

This is intentionally simple: it doesn’t need cryptographic randomness, just visual variation.

### Column depth rules (example)

Treat the portal as blending into the surface across a small number of columns from the edge inward (e.g. 5 columns max). Each column has its own `(main_level, alt_level)` in 0..16 units.

Example levels (out of 16):

- col0: main=16, alt=0 (100% main)
- col1: main=14, alt=2 (mostly main, slight alt)
- col2: main=10, alt=2 (main + a little alt, some unchanged)
- col3: main=5,  alt=1 (mostly unchanged)
- col4: main=3,  alt=1 (subtle fade)

These numbers are tuning knobs.

### Outline / rim

Even with a cyan/black background, a thin rim helps readability and avoids colour bleed. Options:

- 1px black outline around the portal footprint, OR
- black pixels on the inner edge only (cheaper, still defines shape)

### Gameplay clarity rules (suggested)

- If only one portal exists (the other is not placed yet), suppress the “other portal colour” speckles (use black speckles instead) to avoid implying an active connection.
- When the second portal becomes active, redraw **both** portals using their full A↔B speckle rules so the player immediately sees the connection.

### MODE 5 packing note

MODE 5 pixel packing makes true “per pixel” writes expensive. The ordered-dither approach is still viable, but implementation should aim to operate on convenient pixel groupings (where possible) and only run on placement time, not per frame.

#### What does “5 columns” mean in MODE 5?

In our custom MODE 5 setup (128px wide = 32 bytes/scanline):

- **1 screen byte = 4 horizontal pixels** (2 bits per pixel).
- Therefore:
  - **5 pixel-columns** = 5 pixels (awkward: crosses byte boundaries)
  - **5 byte-columns** = 20 pixels (often a better fit for byte-wide loops)

If we want the portal blend depth to be easy to stamp quickly, prefer depths that are multiples of **4 pixels** (byte-aligned) or **8 pixels** (tile half-cell, 2 bytes). If we truly want a 5-pixel blend, we can still do it, but it will require per-byte masking and partial updates at the left/right edges.

## Next Implementation Steps

1) Implement persistent Tiled-authored objects (cube/button/pad/exit) using stable TMX `id` values and level-global state arrays.

2) Hook up signals (channel bits) so pad/button drive exit open/closed in the 2-room playground; button uses SPACE (action key).

3) Continue portal placement/teleportation improvements (tracked in `next_steps.md`) without duplicating object/persistence background here.

## Open Questions

- Exact method of enabling and controlling Master shadow screen in B2/MOS.
- Whether rooms should be tile-built, pre-rendered/compressed, or hybrid.
- Whether portal placement is allowed on all solid surfaces or walls-only (affects surface-normal logic).
