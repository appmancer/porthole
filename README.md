# PORTHOLE

PORTHOLE is a BBC Master 128 (65C02) game: a demake of *Portal* reimagined as a 2D platformer.

This repo is deliberately “close to the metal”: assets are generated into beebasm source, code is cycle/size-aware, and the build produces a bootable DFS SSD disk image.


## Goals

- 2D platformer controls and feel (per-pixel substeps, consistent animation cadence).
- Stable sprite rendering with no trails (save-under / background restore).
- Room-based gameplay (flick-screen / instant transitions).
- Repeatable asset pipeline (no hand-edited hex blobs).


## Platform Constraints / Conventions

These are the project conventions we’ve been following.

- Target machine: **BBC Master 128**.
- Assembler: `beebasm`.
- The main machine code is assembled to run from `&1900`.
- Zero-page variables start at `&70` (see `main.asm`).
- DFS filename limit is **7 characters**.

### Display

The game runs in a customized **MODE 5**:

- BASIC loader (`PROGRAM`) sets `MODE 5`.
- Early in `main.asm` we re-program the 6845 CRTC:
  - `R1` (horizontal displayed) set to **32 chars** (narrower visible width).
  - `R2` (horizontal sync position) set to **45** (re-centre).

Screen layout assumptions:

- MODE 5 screen base is treated as `&5800` (see `render.asm`, `lookup_tables.asm`).
- Playfield rendering treats the world as **16 tile rows**, each row **512 bytes** apart.
- Playfield footprint: `&5800 .. &77FF`.
- “Below playfield” scratch (by convention): `&7800 .. &7FFF`.

Gotcha: avoid OS clears (`CLS`/VDU clears) after init; they can wipe the whole MODE 5 screen RAM including the scratch area.

### Memory Model

- The Master’s shadow screen RAM is used for display (still addressed like MODE 5 at `&5800`, but lives in shadow).
- Chell sprite/mask assets are stored in **sideways RAM** (paged into `&8000..&BFFF`) and loaded at runtime from DFS file `CHDATA`.


## Build & Run

### Build

Builds a bootable DFS disk image:

```bash
./build.sh
```

- Default output: `./porthole.ssd`
- Disk title: `PORTHOLE`
- Boot flow: beebasm’s `-boot PROGRAM` creates a DFS `!Boot` entry which runs BASIC file `PROGRAM`.

`build.sh` also runs the sprite pipeline before assembling.


### B2 emulator workflow

The `tools/` directory includes helpers for the B2 emulator HTTP server (defaults: `127.0.0.1:48075`, instance id `b2`).

Recommended tight loop:

```bash
./tools/b2-reload
```

That performs:

1) build disk
2) upload to B2
3) reset

Other useful helpers:

- `tools/b2-run` – upload and run an SSD
- `tools/b2-reset` – reset emulator
- `tools/b2-peek` – peek memory (hex dump)
- `tools/b2-poke` – poke memory (binary-safe)

Environment variables used by these tools:

- `B2_HOST` (default `127.0.0.1`)
- `B2_PORT` (default `48075`)
- `B2_ID` (default `b2`)


## Repository Layout

High-level:

- `main.asm` – main program entry, init, update/render pipeline, input, physics, Chell drawing, SWRAM loading.
- `render.asm` – tilemap rendering + masked sprite blitting routines.
- `sprites.asm` – sprite pointer tables (tiles + character sprites + overlay sprites).
- `masks.asm` – mask pointer tables matching `sprites.asm`.
- `lookup_tables.asm` – lookup tables for fast address maths (e.g. `times16_table`, `tile_row_screen_table`).
- `tilemap.asm` – room tilemaps and portalable layer data.
- `oscalls.asm` – MOS entry points (`OSBYTE`, `OSWRCH`, etc.).

Assets and generation:

- `sprites/` – CSV sources and generated beebasm includes.
  - `sprites/generated_chell_sprites.asm` (generated)
  - `sprites/generated_chell_masks.asm` (generated)

Tools:

- `tools/gen-sprites` – CSV → Spycat/MODE5 sprite+mask EQUB generator.
- DFS helpers: `tools/dfs-cat`, `tools/dfs-extract`, `tools/ssd-expand`.
- B2 helpers: `tools/b2-run`, `tools/b2-reset`, `tools/b2-peek`, `tools/b2-poke`, `tools/b2-reload`.

Reference material:

- `books/` – PDFs/text notes about the BBC Master MOS, SWRAM, keyboard/keycodes.


## Runtime Pipelines

### Game loop (current)

`main.asm` uses an explicit split:

- **Update pipeline** (`update_chell`)
  - input
  - movement/animation state
  - physics (gravity/jump)
  - sets `dirty_flag` when a redraw is needed

- **Render pipeline** (`render_chell`)
  - restore previous background rectangle (save-under)
  - compute new `screen_ptr` from character position
  - save-under new rectangle
  - draw body + overlay

Timing detail: rendering is performed **immediately after `wait_vsync`**, using the *previous frame’s* `dirty_flag/state` (one-frame latency). This gives the blitters maximum time before scanout and dramatically reduces visible tearing/flicker.

### Save-under / background restore

The renderer uses a restore strategy inspired by classic engines:

- Before drawing a moving sprite, save the rectangle of background it will cover.
- Next frame, restore that rectangle before drawing the sprite in its new position.

This is the “save-under buffer” pattern (often associated with Prince of Persia style engines on constrained systems).

See `next_steps.md` for the deeper rendering/memory plan discussion.


## Sprites and Masks

Sprites are stored as pixels + masks.

- Masked blit rule: `dst = (dst & mask) | pix`.
- For transparent pixels, mask bits are `1` (keep background).
- For opaque pixels, mask bits are `0` (replace background).

### Sprite sizes

- Chell body: 16x32 sprite data laid out as **4 stripes** × 8 scanlines.
- Overlays (gun/arms etc): 16x16 sprite data laid out as **2 stripes** × 8 scanlines.

### Per-pixel movement

The project supports per-pixel substeps by precomputing 4 x-offset variants (x0..x3) for each pose/frame.

Key state:

- `char_pixel_offset` – subpixel (0..3)
- `char_byte_offset` – 4px step within a cell (0 or 8)


## CSV → Sprite Pipeline

Sprite source art is captured as CSVs under `sprites/` and turned into beebasm includes.

The generator:

```bash
./tools/gen-sprites --help
```

Key points:

- CSV rows use `.` for transparent and `0`..`3` for MODE 5 colour indices.
- The generator ignores extra spreadsheet columns; it only reads the first 16 pixel tokens per row.
- It emits data in Spycat/MODE5 “screen byte order” (stripe-major ordering).
- It emits both sprite bytes and corresponding mask bytes.
- Flipping: add `^` to the spec prefix (e.g. `chell_run_l1^:...`) to generate a horizontally flipped sprite.

`build.sh` runs this generator and writes:

- `sprites/generated_chell_sprites.asm`
- `sprites/generated_chell_masks.asm`


## Keyboard Input Notes

We’ve been aiming for a Galaforce-style approach:

- Sample input once per frame into a small bitfield (`keys_held`, `keys_pressed`).
- Convert that input snapshot into game logic.

Movement keys currently use the MOS key scan (`OSBYTE 129` / INKEY negative numbers).

If you are changing key bindings, cross-check:

- `books/BBC Microcomputer Advanced User Guide.*` (key number tables)
- In-code constants/comments around input handling in `main.asm`


## Tools Reference

### DFS

- `tools/dfs-cat <ssd>` – list DFS catalogue
- `tools/dfs-extract <ssd> <file> <out>` – extract a DFS file
- `tools/ssd-expand <in.ssd> <out.ssd>` – pad/expand to full 200KB image (some emulators expect this)

### Emulator

- `tools/b2-run <ssd>`
- `tools/b2-reset`
- `tools/b2-peek <addr> <len> [suffix]`
- `tools/b2-poke <addr> "<hex bytes>" [suffix]`
- `tools/b2-reload [ssd]`


## Research / Notes

The repo contains several research notes that are worth reading for context:

- `next_steps.md` – rendering + memory plan (buffers, save-under strategy, material planes).
- `pop_beeb_lessons.md` – notes inspired by Prince of Persia/BBC techniques.
- `spycat_notes.md` – notes on Spycat sprite formats and rendering.
- `stardot_sprite_routines.md` – collected sprite routine references.
- `retrosoftware_lessons.md`, `strykers_run_enhanced_lessons.md`, `codename_droid_lessons.md` – engine notes from other BBC projects.
- `sprites/Chell Sprite Requirements.md` – checklist of sprite/overlay requirements.

Reference material is also stored under `books/`.


## Known gotchas

- Don’t manually add a `!BOOT` file when using beebasm `-boot` (beebasm auto-creates `!Boot`).
- Avoid MOS screen clear calls after init (they can wipe scratch screen memory).
- DFS filenames are limited to 7 characters.
