# Room Metadata Spec (.meta)

This document describes the per-room metadata format used by the level build tools.

The goals are:

- Keep room tile authoring as tiles-only (16x16 grid).
- Put exits, spawns, and gameplay objects outside the tile layer (authoring convenience).
- Make authoring simple while generating compact runtime lookup tables.

## Files

- Room tiles: `levels/<level>/roomNN.tmx` (preferred) or `levels/<level>/roomNN.txt` (legacy)
- Room metadata (preferred): TMX object layers inside `roomNN.tmx`
- Room metadata (legacy): `levels/<level>/roomNN.meta`

Example:

- `levels/level1/room00.tmx`
- `levels/level1/room00.meta`

## Syntax rules

- One directive per line.
- Tokens are separated by whitespace.
- Blank lines are allowed.
- Comments: anything after `#` is ignored.
- Numbers are decimal.
- Room ids are `roomNN` (two digits), e.g. `room00`, `room01`.

## Coordinate system

All coordinates in `.meta` are in **cell** units on the 16x16 room grid.

- Origin `(0,0)` is the **top-left** cell.
- `x` increases to the right (0..15).
- `y` increases downward (0..15).

Cells correspond to the engine's 8x16 pixel cells.

All ranges are **0-based** and inclusive.
For example, `6 7` means rows/cells 6 and 7.

## Chell probe point (for exits)

Exit matching uses Chell's **feet** for now.

- `feet_cell_y = top_left_cell_y + 1` (Chell is 2 cells tall)
- `feet_cell_x = top_left_cell_x + 1` (approx "center" of her 2-cell width)

We can refine this later (full overlap tests, pixel-accurate feet position, etc.).

## TMX object layers (preferred)

Tiled authoring uses two object layers:

- `meta`: room-to-room edge exits
  - rectangle objects of type `edge_exit`
  - required property: `to=roomNN`
  - place rectangles on the outer border; the build derives the edge and cell range from geometry
- `objects`: gameplay objects
  - point objects with type `cube|button|pad|exit`
  - placed on the tile grid; coordinates are interpreted as cell origin

The build tool prefers TMX object layers when present and falls back to parsing `.meta`.

## Exits

Exits are always on the **outer edges** of the room.

An exit line declares:

- Which edge (`left`, `right`, `up`, `down`)
- A range along that edge (multiple cells)
- A destination room

### Exit line (default spawn rule)

Default form (recommended for normal screen-to-screen exits):

```text
exit <edge> <a0> <a1> -> <roomNN>
```

Where:

- For `left`/`right` exits: `<a0> <a1>` is `y0 y1` (inclusive)
- For `up`/`down` exits: `<a0> <a1>` is `x0 x1` (inclusive)

Example:

```text
# Top-edge opening spanning x=2..4
exit up 2 4 -> room01
```

#### Default spawn rule (no `spawn` given)

When `spawn` is omitted, the engine computes the destination spawn using a predictable edge rule:

- Momentum is preserved (vx/vy carry over).
- Facing direction is preserved.
- For `up`/`down` exits, preserve `feet_cell_x`.
- For `left`/`right` exits, preserve `feet_cell_y`.
- Enter on the **opposite edge** of the destination room.
  - `exit up` enters destination from the bottom
  - `exit down` enters destination from the top
  - `exit left` enters destination from the right
  - `exit right` enters destination from the left
- Apply a small inset (implementation detail) to avoid immediately re-triggering the same exit.

This matches "normal exits" (non-portable portals).

### Exit line (explicit spawn override)

Optional form (for special links; also useful for future scripted transitions):

```text
exit <edge> <a0> <a1> -> <roomNN> spawn <x|same> <y|same>
```

The `spawn` coordinates are in **feet-cell** coordinates.

Example:

```text
exit up 2 4 -> room01 spawn same 15
```

This means:

- Keep `feet_cell_x` unchanged.
- Force destination `feet_cell_y = 15`.

Notes:

- You usually do not need `spawn` for standard flick-screen exits.
- The portal system will use explicit spawn at runtime because portal destinations are internal.

### Validation rules for exits

- Edge must be one of `left`, `right`, `up`, `down`.
- Ranges must satisfy `0 <= a0 <= a1 <= 15`.
- Destination room must exist.
- Recommended: ranges on the same edge should not overlap (treat overlap as an authoring error).

## Objects

Gameplay objects are declared in metadata (not in the tile grid), because they have state.

Line format:

```text
obj <type> <x> <y>
```

Where `<type>` is one of:

- `cube`
- `button`
- `pad`
- `exit`

Example:

```text
obj cube 8 12
obj pad  9 13
obj exit 14 10
```

Object coordinates are in cell units, and represent the object's anchor (typically top-left of its footprint).

## Planned: Signals, Doors, Lasers (Not Implemented Yet)

We plan to extend `.meta` to support **signal channels** (bits) and more object types (doors, laser emitters/targets).

Design reference: `levels/signals_and_lasers.md`.

### Proposed syntax (sketch)

Drivers publish a signal bit:

```text
obj button <x> <y> out <sig>
obj pad    <x> <y> out <sig>
obj target <x> <y> out <sig>
```

Emitters trace a ray; targets drive signals:

```text
obj laser <x> <y> dir <left|right|up|down>
```

Consumers read signals:

```text
obj door <x> <y> in <sig>
obj dropper <x> <y> in <sig>
```

Notes:

- Signals are intended to be **level-global**, so remote puzzles work (laser in one room opens door in another).
- Start with single-input semantics (`in <sig>`). Add AND/masks later only if needed.
