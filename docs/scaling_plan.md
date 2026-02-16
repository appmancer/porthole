# Scaling Plan: 100+ Levels

Status: **DRAFT** — awaiting review before implementation.

## Problem

Porthole currently ships 6 levels compiled inline into the main binary.
The `tilemap` section consumes ~3.7 KB with only ~2 KB of headroom before
the &7800 ceiling. At the current average of ~743 bytes per level, 100
levels would require ~72 KB — far beyond main RAM.

### Current numbers

| Metric                     | Value          |
|----------------------------|----------------|
| Levels                     | 6              |
| Tilemap section used       | 3,713 bytes    |
| Tilemap section free       | 2,079 bytes    |
| Main RAM ceiling           | &7800          |
| Average bytes per level    | ~743           |
| DFS files used / limit     | 9 / 31         |
| LYNNE &3000-&57FF          | 10,240 B free  |
| SWRAM Bank 7               | 16,384 B free  |

## Strategy overview

1. **Remove all inline level data** from the main binary.
2. **Compress** tilemaps with simple RLE.
3. **Eliminate portal maps** entirely (derive at runtime from tile properties).
4. **Pack multiple levels** into binary DFS files ("level packs").
5. **Stream from disc** at runtime: OSFILE into a workspace buffer, then
   decompress into the active tilemap buffer.

This reduces per-level storage from ~743 bytes to ~323 bytes on average,
putting 100 levels at ~32 KB on disc — well within a 200 KB DFS image.

---

## 1. Eliminate portal maps

### Background

Every room currently stores a 256-byte "portal map" indicating which tiles
accept portal placement. Across all 6 existing levels, **every portal map
is 100% zeros** — the data is never used.

### Approach

Portal eligibility is already implicit in the tile set: certain wall tiles
(left wall, right wall, floor, ceiling) are portalable, others are not.
We add a small lookup table (or bit-test on the tile ID) in
`build_material_planes_from_tilemap` that derives portalability from tile
type.

### Savings

- 256 bytes per room eliminated from level data.
- `portal_room_pointers` removed from the level header (saves 4 bytes per
  level at MAX_ROOMS=2).
- Zero runtime cost increase — a table lookup replaces a different table
  lookup.

### Changes

| File               | Change                                              |
|--------------------|-----------------------------------------------------|
| `render.asm`       | Derive portal plane from tile IDs, not portal map.  |
| `tilemap.asm`      | Remove `portal_room_pointers` from active buffer.   |
| `tools/gen-level`  | Stop emitting portal map data.                      |

---

## 2. RLE-compress tilemaps

### Background

Room tilemaps are 256-byte flat arrays (16x16 tiles). Analysis across all
levels shows ~45% of tiles are air (tile 0), with long horizontal runs of
identical wall/floor tiles.

### Format

Simple byte-pair RLE:

```
[count] [tile_id]   — repeat tile_id `count` times (count = 1..255)
```

Encoded left-to-right, top-to-bottom (same order as the flat array).
Stream ends when 256 tiles have been emitted.

### Expected compression

| Room type      | Raw  | RLE estimate | Ratio |
|----------------|------|--------------|-------|
| Sparse (lots of air) | 256 B | ~100-120 B | ~45% |
| Dense (complex geometry) | 256 B | ~140-170 B | ~60% |
| Average | 256 B | ~130 B | ~50% |

### Decompressor (6502)

The decompressor is small — roughly 30-40 bytes of code:

```
.rle_decompress
    ; src_ptr -> compressed data (set by caller)
    ; dst_ptr -> active tilemap buffer (set by caller)
    LDX #0              ; output index (0..255)
.rle_loop
    LDY #0
    LDA (src_ptr),Y     ; count
    STA temp
    INC src_ptr
    BNE +
    INC src_ptr+1
+   LDA (src_ptr),Y     ; tile
    INC src_ptr
    BNE +
    INC src_ptr+1
+   LDY temp
.rle_fill
    STA (dst_ptr,X)     ; write tile
    INX
    BEQ .rle_done       ; 256 tiles emitted
    DEY
    BNE .rle_fill
    BEQ .rle_loop
.rle_done
    RTS
```

(Exact implementation TBD — the above is illustrative.)

### Changes

| File              | Change                                         |
|-------------------|-------------------------------------------------|
| `tools/gen-level` | Add RLE encoder for tilemap output.             |
| `tilemap.asm`     | Add `rle_decompress` routine.                   |

---

## 3. Binary level pack format

### Overview

Instead of generating `.asm` INCLUDEs, `gen-level` emits binary `.dat`
files. Each file is a "level pack" containing several levels.

### Pack file layout

```
Offset  Size    Field
------  ------  -----
+0      1       Level count in this pack (N)
+1      N*2     Offset table: 16-bit LE offset to each level's data
                (relative to start of file)
+1+N*2  ...     Level data (variable length, concatenated)
```

### Per-level data layout

```
Offset  Size    Field
------  ------  -----
+0      1       Room count (R) for this level
+1      1       Start room index
+2      1       Start position (packed: y<<4 | x)

--- Object definitions ---
+3      1       Object count (P)
+4      P*6     Object defs: type(1), channel(1), flags(1),
                home_room(1), home_x(1), home_y(1)

--- Laser definitions ---
+?      1       Laser count (L)
+?      L*7     Laser defs: room(1), tx(1), ty(1), dir(1),
                channel(1), emitter_x(1), emitter_y(1)

--- Target definitions ---
+?      1       Target count (T)
+?      T*4     Target defs: room(1), tx(1), ty(1), channel(1)

--- Per-room data (repeated R times) ---
  +?    varies  RLE-compressed tilemap
  +?    1       Exit count left
  +?    E_l*5   Exit records (left)
  +?    1       Exit count right
  +?    E_r*5   Exit records (right)
  +?    1       Exit count up
  +?    E_u*5   Exit records (up)
  +?    1       Exit count down
  +?    E_d*5   Exit records (down)
  +?    1       Fizzler count
  +?    F*5     Fizzler defs

--- Level card text ---
+?      varies  MODE 7 overlay records: (row, col, len, data...),
                terminated by &FF
```

### Key design decisions

- **Self-describing**: each level carries its own counts (room count, object
  count, etc.) rather than relying on padded compile-time constants. This
  means `OBJ_COUNT`, `LASER_COUNT`, `TARGET_COUNT`, and `MAX_ROOMS` become
  runtime values read from the pack data, not fixed constants.

- **No portal maps**: omitted entirely (see section 1).

- **Level card text included**: each level carries its own GLaDOS quote for
  the MODE 7 level card. No separate pointer table in `screens.asm`.

### Size estimate per level

| Component            | Typical size | Notes                        |
|----------------------|-------------|------------------------------|
| Header + counts      | ~10 B       |                              |
| Object defs          | ~24 B       | 4 objects avg * 6 bytes      |
| Laser/target defs    | ~12 B       |                              |
| Tilemaps (RLE)       | ~200 B      | 1.5 rooms avg * ~130 B       |
| Exit data            | ~20 B       |                              |
| Fizzler data         | ~10 B       |                              |
| Level card text      | ~60 B       | GLaDOS quote + overhead      |
| **Total**            | **~336 B**  |                              |

**100 levels: ~33 KB on disc.**

---

## 4. DFS disc organization

### Pack grouping

With 22 DFS file slots remaining (31 limit - 9 existing), we can
comfortably store level packs:

| Filename | Contents     | Estimated size |
|----------|-------------|----------------|
| `LVLS01` | Levels 1-10 | ~3.4 KB        |
| `LVLS02` | Levels 11-20 | ~3.4 KB       |
| ...      | ...         | ...             |
| `LVLS10` | Levels 91-100 | ~3.4 KB      |

10 pack files, leaving 12 DFS slots for future use (sound effects, extra
graphics, etc.).

### DFS filename convention

- 7-character limit: `LVLSnn` (6 chars, fits comfortably).
- Alternative: `LVnnn` for finer granularity (5 levels per file, 20 files).

---

## 5. Runtime loading architecture

### Workspace: LYNNE &3000-&57FF

LYNNE is the 10,240-byte data area in the Master's shadow RAM, currently
unused. It sits below the shadow screen (&5800-&7FFF) and is accessed by
toggling ACCCON bit 2 (X=1).

**Advantages over SWRAM Bank 7:**
- No bank switching during decompression (LYNNE is directly addressable
  once ACCCON is set).
- 10 KB is more than enough for any single level pack.
- Code at &1900-&3000 can access LYNNE without conflicting with the
  filing system ROM.

**Constraint:** Code that accesses LYNNE must itself live below &3000
(since &3000-&7FFF is remapped). The `load_level` routine and
decompressor will be placed in the early part of the binary.

### Load flow

```
load_level(level_number):
    1. pack_index = level_number / LEVELS_PER_PACK
    2. level_in_pack = level_number MOD LEVELS_PER_PACK
    3. If pack_index != loaded_pack_index:
         a. Build filename string: "LVLS" + digits
         b. OSFILE &FF -> load pack to LYNNE &3000
         c. loaded_pack_index = pack_index
    4. Toggle ACCCON to access LYNNE
    5. Read pack directory: offset = pack[1 + level_in_pack * 2]
    6. Parse level header from pack + offset:
         - Copy counts and defs into active buffer
         - For each room: RLE-decompress tilemap into active_tilemap[]
         - Copy exit/fizzler data into active buffer
         - Store pointer to level card text for show_level_card
    7. Restore ACCCON
    8. Derive portal eligibility plane from tile IDs
```

### Caching

If the player advances to the next level within the same pack, step 3
is skipped — the pack is already in LYNNE. This makes level transitions
within a pack instant (no disc access).

### Active buffer changes

The current active buffer is a fixed-size block copied by `load_level`
via a simple `LDY / LDA / STA / INY / CPY #LEVEL_HEADER_SIZE` loop.
With variable-size level data, we replace this with a structured parser
that reads counts and copies the appropriate number of bytes for each
section.

The active buffer itself can remain at its current location. The key
change is that `OBJ_COUNT`, `LASER_COUNT`, `TARGET_COUNT`, and
`MAX_ROOMS` become runtime variables (stored in ZP or fixed RAM) rather
than assembly-time constants.

**Impact:** Code that currently uses `OBJ_COUNT` as a loop bound
(e.g. `CPX #OBJ_COUNT`) must instead load from a runtime variable.
This is a small but widespread change — every object-iteration loop
in `persistent_objects.asm`, `render.asm`, etc.

**Alternative:** Keep the padded-constant approach. Set `OBJ_COUNT=6`,
`LASER_COUNT=1`, `TARGET_COUNT=1`, `MAX_ROOMS=2` as hard ceilings, and
require all levels to fit within them. The parser zero-fills unused
slots. This avoids touching every loop in the codebase.

**Recommendation:** Keep padded constants for now. 6 objects, 1 laser,
1 target, 2 rooms per level is sufficient for 100+ puzzle levels. We
can revisit if level design demands more.

---

## 6. Level card text

### Current approach

`screens.asm` has a `level_card_ptrs` table pointing to inline overlay
data blocks, one per level. Each block is 50-80 bytes of MODE 7 screen
records.

### New approach

Level card text is embedded in the level pack data (see section 3).
When `load_level` parses a level, it stores a pointer to the level card
text region (still in LYNNE). `show_level_card` reads from that pointer
instead of the inline table.

The `level_card_ptrs` table and all `level_card_N` data blocks are
removed from `screens.asm`, freeing ~400 bytes in the screens section.

**Constraint:** LYNNE must remain accessible (ACCCON bit set) while
`show_level_card` runs. Since level cards display in MODE 7 (which
doesn't use shadow screen RAM), there is no conflict — LYNNE access
and MODE 7 display are independent.

---

## 7. Changes to `tools/gen-level`

### New mode: `--binary-pack`

```
./tools/gen-level --binary-pack \
    --levels levels/level1 levels/level2 ... levels/level10 \
    --out levels/LVLS01.dat \
    --level-cards cards/pack01.txt
```

- Reads multiple level directories.
- Emits a single binary `.dat` file in the pack format (section 3).
- RLE-compresses tilemaps.
- Omits portal maps.
- Embeds level card text from a separate text file (or inline in the
  `.tmx` as a custom property).

### Backward compatibility

Keep the existing `--label-prefix` `.asm` output mode working during
the transition. Once the new pipeline is validated, remove it.

---

## 8. Changes to `build.sh`

### Current flow

```
for each level:
    gen-level --level levels/levelN --out levels/generated_levelN.asm ...

beebasm -i main.asm -do porthole.ssd -boot PROGRAM ...
```

### New flow

```
# Generate binary level packs
gen-level --binary-pack --levels levels/level1..level10 --out .tmp/LVLS01.dat ...
gen-level --binary-pack --levels levels/level11..level20 --out .tmp/LVLS02.dat ...
...

# Assemble (no level INCLUDEs in main.asm)
beebasm -i main.asm -do porthole.ssd -boot PROGRAM ...

# Add level packs to DFS image (PUTFILE after assembly)
# beebasm PUTFILE supports adding files to an existing .ssd
```

Note: beebasm's `PUTFILE` directive can be used inside the assembly
source to place extra files on the disc. Alternatively, a post-assembly
tool can inject files into the `.ssd`.

---

## 9. Implementation order

Each step is independently testable against the existing 6 levels.

| Step | Task                                           | Risk   |
|------|-------------------------------------------------|--------|
| 1    | Eliminate portal maps (runtime derivation)      | Low    |
| 2    | RLE compressor in `gen-level`                   | Low    |
| 3    | RLE decompressor in 6502                        | Low    |
| 4    | Binary pack format in `gen-level`               | Medium |
| 5    | LYNNE workspace setup + OSFILE loader           | Medium |
| 6    | New `load_level` parser (pack -> active buffer) | Medium |
| 7    | Move level card text into packs                 | Low    |
| 8    | Remove inline level data from main binary       | Low    |
| 9    | Update `build.sh` for new pipeline              | Low    |
| 10   | Add levels 7-20 (first real batch)              | Low    |
| 11   | Add levels 21-100+                              | Low    |

Steps 1-3 can be done first as isolated improvements to the existing
system (still using inline `.asm` data, just smaller). Steps 4-9 are
the disc-streaming switchover. Steps 10-11 are content.

---

## 10. Open questions

1. **LYNNE access pattern**: Is ACCCON bit-toggling from the loader
   sufficient, or do we need a small trampoline below &3000? (The
   loader already lives at &1900, so this should be fine.)

2. **Pack granularity**: 10 levels per pack is a reasonable default.
   Fewer levels per pack means more DFS files but faster individual
   loads. More levels per pack saves DFS slots but increases load
   time for a cache miss.

3. **Level card text source**: Embed GLaDOS quotes as custom properties
   in the `.tmx` files, or keep them in a separate text file?

4. **MAX_ROOMS / OBJ_COUNT ceiling**: Keep at 2 rooms / 6 objects /
   1 laser / 1 target for all 100 levels? If any future level needs
   more, we must bump the constants and accept the active buffer growth.

5. **Level ordering**: Are levels numbered globally (1-100) or grouped
   into "chapters"? This affects pack assignment and UI display.
