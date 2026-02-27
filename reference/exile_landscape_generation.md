# Exile Procedural Landscape Generation (Deep Dive)

Source: `reference/exile-standard-disassembly.txt` (Exile standard disassembly from level7.org.uk).

This note focuses only on “how a tile is chosen” for the 256x256 world, and how Exile layers:
- a procedural base terrain
- a small authored overlay (“map data”)
- a location-fixed spawner/feature layer (“tertiary objects”)

Key entry points:
- `&1715 get_tile_and_check_for_tertiary_objects`
- `&178d get_tile` (core procedural algorithm + map overlay)

## 1) Coordinate Model

Tile coordinates are 8-bit:
- `tile_x` in `&95`
- `tile_y` in `&97`

So the world is conceptually 256x256 tiles.

The algorithm treats special bands of `tile_y` as “above surface”, “surface”, and “below surface”.

## 2) Overall Tile Selection Pipeline

The full selection is:

1) `get_tile` returns `tile_type_and_flip` (top two bits are `TILE_FLIP_*`).
2) The caller strips flip, optionally checks the tertiary object lists, and may replace the tile with:
   - a tile associated with a tertiary object at that coordinate, OR
   - a “feature tile” chosen from `feature_tiles_table`.

Then it may call a tile update routine depending on tile flags.

This is all in `&1715..&178c`.

## 3) `get_tile` Structure (Procedural Base + Map Data Overlay)

`get_tile` (`&178d`) builds several derived values from (x,y) that the disassembler labels `f1..fN`.
They are not PRNG calls; they are deterministic bit-mixing functions chosen to create “structured irregularity”.

High-level shape:

```text
f1 = mix(x,y)

if near key story bands of y and f1 says “use map”:
  tile = map_data(f2,f4)
else:
  tile = procedural_terrain(f1,f4,f5,...,x,y)
```

### 3.1 f1 (a triangular-ish mix of x and y)

At `&178d..&179b`:
- takes `y`, shifts, XORs with `x`, masks, adds `x`, adds `y`.
- stores into `&9d` as `f1_tile_xy`.

This f1 then seeds multiple downstream decisions.

### 3.2 Decide “map overlay” vs “procedural”

At `&179d..&17d4`, Exile uses y bands and derived variants of f1 (`f2`, `f3`, `f4`) to decide whether to consult the map overlay.

The key branch is:
- `&17ce  CPY #&20`
- `&17d0  BCS &17f6`  (if not in the band, skip map)
- `&17d2  CMP #&20`
- `&17d4  BCS &17f2`  (if in the band but above threshold, use procedural)

Interpretation:
- The overlay is *sparse* and only consulted in certain regions; otherwise the algorithm runs.
- Even inside those regions, some positions still come from the procedural path.

### 3.3 Map data addressing (overlay)

When the map overlay path is taken (`&17d6..&17eb`):
- sets `tile_was_from_map_data` by `DEC &00` (top bit set)
- computes an address using `f2` and `f4`, with base described as `&4FEC = map_data`.
- reads one byte: `LDA (map_data_address),Y` with `Y = &EC`.

So map data is stored as bytes that already include tile id + optional flip flags.

Practical takeaway:
- “Authored” content is not a full 256x256 map; it’s a compact keyed overlay looked up through a mixing function.

## 4) Procedural Terrain Path

If overlay is skipped, `get_tile_from_algorithm_skipping_check` at `&17f6` handles the bulk terrain.

### 4.1 The surface and above-surface

At `&17f6..&17fe`:
- if `y < &4E` => SPACE
- if `y == &4E` => `get_tile_for_surface` (`&1937`)
- if `y == &4F` => “one below surface” band

`get_tile_for_surface` (`&1937..&1945`) is a small surface-decoration system:
- mostly SPACE
- occasionally picks from `surface_feature_tiles_table` based on a function of x
- sets horizontal flip depending on f1.

The `y == &4F` band (`&1800..&180d`) is a special-case “solid layer” with a leaf placed at exactly `x == &40`.

### 4.2 Force solid world boundaries

At `&1814..&182c`, Exile forces the “sides/bottom” of the world to be solid:
- the solid margin width depends on whether you are in the top/bottom half of the world (`BIT tile_y`).

This ensures you can’t leave the generated play space.

### 4.3 Earth vs stone and big caverns

Beyond the forced-solid margins, it uses f1/f5-like tests to decide:
- where to place “square caverns” (`&183d..&1851`)
- where to place passages/shafts/slopes (`&1852..&19a6`)
- otherwise it falls back to “earth or stone” chosen from `earth_tiles_rotation_table` using f1 (`&191c..&1927`).

### 4.4 Square caverns (and “windy” caverns)

At `&1830..&1842` it creates a function `f5` and checks `AND #&E8` to decide square cavern cells.

If in the *bottom half* of the world, those caverns can become wind tiles:
- `&1849  LDA #&0E ; TILE_VARIABLE_WIND`
- one special cavern uses a constant downdraft via flip (`&184f`).

### 4.5 Vertical shafts

At `&1852..&1877` it derives `f6` from f1 and x.
If `f6 & 7 == 0`, it emits `TILE_CHECK_TERTIARY_OBJECT_RANGE_EIGHT` (type `&08`), i.e. a tile that later triggers tertiary object checks.

### 4.6 Horizontal passages + passage features

At `&1892..&18d7` it sometimes creates empty horizontal passages, and sometimes “feature” tiles inside them:
- features are selected by offsets into `horizontal_passage_feature_tiles_table`.
- it explicitly avoids placing these features where sloping passages cut through.

### 4.7 Sloping passages and sloping cavern segments

At `&18df..&191b` it calls `calculate_slope_function_for_tile_x_y` (`&1946`).

This function:
- sometimes yields “this tile is part of a sloping cavern/passage”
- returns carry clear for “passage area” and sets Y to a slope type.

Then `consider_sloping_passage` chooses either:
- empty centre (SPACE)
- an edge tile from `slope_tiles_table` OR a feature tile from `sloping_passage_feature_tiles_table`
- applies a rotation from `tile_rotations_table`.

This is how Exile gets lots of diagonals and caves without storing geometry.

## 5) Tertiary Objects and Feature Tiles (the third layer)

After `get_tile` returns, `get_tile_and_check_for_tertiary_objects` (`&1715..&178c`) may replace the tile:

- For certain “check tertiary range” tile types, it scans a list for a tertiary object at (x,y).
- If found, it substitutes that object’s `tertiary_objects_tile_and_flip`.
- If not found, it substitutes a “feature” tile based on tile type via `feature_tiles_table`.

This produces the feeling of authored landmarks and spawners inside an otherwise algorithmic world.

## 6) Why This Is Relevant

If you want a large 4-way scrolling world but don’t want to store a huge map, Exile is the canonical pattern:
- deterministic base terrain from cheap bit-math
- small overlay for key areas
- spawner list for “persistent-but-not-simulated” actors

Even if you *don’t* want procedural terrain, the tertiary-object promotion/demotion idea is directly reusable for a lightweight metroidvania.
