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

### Backgrounds (future)

We want an equivalent pipeline for backgrounds:

- authoring format (tilemap CSV, Tiled export, custom editor, etc.)
- converter to beebasm includes or compressed blobs
- room-load routine to build/decompress into clean buffer

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

## Next Implementation Steps

1) Define memory layout for `solid` and `portalable` planes (8KB working-set).
2) Implement fast bit-test routines (`is_solid`, `is_portalable`).
3) Decide authoring format for planes (tile layer vs compressed pixels) and implement room-load expansion.
4) Move towards shadow-based double buffering / vblank-sync only when needed.

## Open Questions

- Exact method of enabling and controlling Master shadow screen in B2/MOS.
- Whether rooms should be tile-built, pre-rendered/compressed, or hybrid.
- Whether portal placement is allowed on all solid surfaces or walls-only (affects surface-normal logic).
