# Syncron Research Notes (Vertical Scrolling Gold Standard)

This document distills the specific engine techniques from **Syncron** (Superior, 1988; Gary Partis) that are directly applicable to a **Syncron-like Battlefield 1942 demake** (top-down, vertical scroller) on BBC Master / 65C02.

Primary reference disassembly:
- https://www.level7.org.uk/miscellany/syncron-disassembly.txt

Local disk image used here:
- `reference/Syncron.ssd`

## DFS catalogue (Syncron.ssd)

From `./tools/dfs-cat reference/Syncron.ssd`:

- `$.SYNCRON` load `&1900` exec `&8023` len `67`
- `$.LOAD` load `&1900` exec `&8023` len `272`
- `$.SYNC` load `&1900` exec `&1900` len `768`
- `$.SYNC3` load `&1F00` exec `&7400` len `22528`
- `$.SYNCPIC` load/exec `&5BD8` len `6928`

The important runtime blob is `SYNC3` (exec `&7400`), which decrypts/relocates the real game code into `&0300..&57FF`.

## High-level design (what makes Syncron fast)

Syncron’s vertical scrolling performance comes from three aligned choices:

1) **True hardware scroll**: move the display by changing the CRTC start address (no screen memory copy).
2) **Ring-buffer screen**: treat `&5800..&7FFF` as a circular screen store so start-address changes always remain within valid screen RAM.
3) **Incremental background build**: per scroll step, draw only the newly revealed **8-scanline strip** across the view.

Sprites are then layered on top using a technique that is friendly to a moving background.

## Scrolling model

### Method

Syncron scrolls vertically by adjusting **CRTC R12/R13** (display start address) and a corresponding software "screen base" pointer.

It does not bulk-copy the screen each tick.

### Scroll step size

The engine scrolls in **8-pixel steps** (one character row = 8 scanlines).

This is visible in how the pointers move:

- Software screen start address moves by **`&0140` bytes** per step.
- CRTC start address moves by **`&0028` CRTC units** per step.

`&28 * 8 = &140`, so the software and CRTC views stay aligned.

### Key state variables (from the disassembly)

- `screen_start_address` = `&A0/&A1`
  - Used by software plotters to translate world/screen coordinates into absolute screen RAM addresses.
- `crtc_start_address` = `&A2/&A3`
  - Written into CRTC R13/R12 each step.

### Key routines (addresses from the disassembly)

- `scroll_screen`: `&168E`
  - `scroll_screen_up`: `&1692..&16DE`
  - `scroll_screen_down`: `&16E1..&1732`
- CRTC update (writes R13 then R12): `&1735..&1746`

### Ring-buffer wrap

The screen region is treated as a ring:

- Total screen RAM for MODE 5 here is `&5800..&7FFF` (10KB = `&2800`).
- One 8-scanline row is `&0140` bytes.
- `&2800 / &0140 = 32` rows.

So Syncron has a natural **32-step vertical ring**, and wrap logic keeps both:

- the software screen base (`&A0/&A1`) inside the ring, and
- the CRTC start address (`&A2/&A3`) inside the matching CRTC range.

Helper mentioned in the disassembly:

- `keep_screen_high_within_screen_memory`: `&064B` (constrains the high byte for ring wrap).

## Frame pacing (IRQ + vsync)

Syncron uses a robust timing scheme:

- An IRQ handler distinguishes between:
  - **v-sync interrupt** (CA1) and
  - **timer interrupt** (System VIA Timer 1).
- The v-sync IRQ path reloads Timer 1, and the Timer 1 IRQ increments a `frame_counter`.
- The main loop busy-waits until `frame_counter` changes.

Practical effect:

- The game loop runs at a stable pace.
- Scroll updates happen in a consistent phase.

Key routines (disassembly addresses):

- `irq1_handler`: `&045C`
- v-sync path: `&044C`
- `wait_for_vsync` (actually waits for `frame_counter` change): `&09C4`
- main loop tick gate: `&100C`

## Background drawing during scroll

### What gets drawn

Each scroll step draws exactly one newly revealed **8-scanline landscape strip** across the screen width.

### How it’s represented

Syncron’s background is a three-stage indirection designed to make strip stamping cheap:

- `level_data` (`&2700..`): tile IDs for the level
- `tile_chunks_data` (`&4700..`): for each tile, references a set of chunk IDs
- `chunk_data` (`&5000..`): 8-byte bitmap chunks that are directly copied into screen RAM

This means the per-strip work is mostly:

- look up tile ID
- look up the right chunk row for that tile
- copy 8 bytes to the correct screen address

### Key routines

- `plot_landscape_strip`: `&1732..&178F`
- `calculate_level_data_address_and_offset`: `&1790`
- `calculate_tile_chunks_data_address`: `&17A9`

## Sprite rendering relative to scroll

### Technique: XOR plotting (erase-by-redraw)

Syncron uses XOR sprite plotting for dynamic objects.

Properties that matter for a vertical scroller:

- No save-under buffers.
- Erase is just "plot again".
- Background changes (via ring reuse + strip stamping) naturally clean old pixels as the scroller advances.

### Scroll-aware sprite addressing

Sprite screen addresses are computed relative to `screen_start_address` (`&A0/&A1`).
That makes sprite plotting correct regardless of where the CRTC start points within the ring.

Key routine:

- `calculate_sprite_screen_address`: `&1654`

### Update order (important)

Syncron’s per-frame order (conceptually) is:

1) Unplot player
2) Apply scroll (update start addresses; stamp new strip)
3) Plot player
4) Unplot/update/plot enemies
5) Unplot/update/plot missiles

Routines referenced in the disassembly:

- player plot/unplot: `plot_or_unplot_player` `&15D2` (called from `update_player`)
- enemies: `plot_or_unplot_enemy` `&18B5` (via `plot_or_unplot_sprite` `&15DF`)
- missiles: `update_missiles` `&11EA`, `plot_or_unplot_missile` `&1263`

## Implications for a Syncron-like Battlefield demake

Battlefield goals (top-down, vertical map, many actors) line up well with Syncron’s architecture.

### Recommended engine choices (based on Syncron)

- Vertical scrolling:
  - Use CRTC start-address scrolling over a ring buffer in `&5800..&7FFF`.
  - Scroll in 8px steps initially (Syncron shows this is both fast and visually acceptable).
- Background:
  - Stamp exactly one 8-scanline tile strip per scroll step.
  - Keep background data in an indirection chain that turns "draw strip" into a tight copy loop.
- Sprites:
  - Prefer XOR sprites for moving objects if the art style allows it.
  - Derive sprite plotting addresses from the moving `screen_start_address`.
- Timing:
  - Use an IRQ-driven frame counter; gate the game loop on that counter.

### Things to decide early

- XOR viability: does the Battlefield art direction tolerate XOR sprites (high-contrast silhouettes, limited colours)?
  - If not, a masked blitter is possible, but you will need a different erase strategy under scroll.
- Entity size: Syncron’s approach works best when sprites are small and fixed-size.
  - Your desired 8x16 for infantry/tank/plane is aligned with this.

## Quick checklist for implementation planning

- Implement ring-buffer scroll first (CRTC start address + software base pointer).
- Implement "plot one new 8-scanline strip" for the background.
- Add XOR sprite plot/unplot using scroll-relative address calculation.
- Only then scale up entity count, weapons, and capture points.
