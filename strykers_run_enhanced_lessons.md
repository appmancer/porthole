# Lessons from Stryker’s Run (Enhanced, BBC Master)

Reference disassembly:
- https://level7.org.uk/miscellany/strykers-run-enhanced-disassembly.txt

Stryker’s Run (Enhanced) is a strong reference point for PORTHOLE because it demonstrates:

- **Master-specific enhancements** (sideways RAM banks, 65C02 usage)
- **lots of large sprites**
- **fast scrolling** with layered scenery
- **pragmatic sprite composition** (multi-part movers)

This document records techniques worth reusing.

## 1) Sideways RAM as the expansion mechanism (Master enhancement)

The disassembly’s technical notes state:

- Enhanced version uses sideways RAM banks **4, 5, 6, 7**.
- Adds extra scenery sprites and mover sprites, plus extra mover types.

You can see explicit bank selection via the paged ROM latch:
- `STA &FE30 ; Paged ROM latch` (e.g. loader around `&0E2D`, and many runtime places)

Example: loader copies data into sideways RAM by selecting each bank and copying pages:
- Around `&0E2A..&0E52` (select bank from `ram_banks`, copy into `&8000..`)

PORTHOLE takeaway:
- Sideways RAM is the “official” Master-friendly way to scale sprite sets.
- This aligns with storing large optional assets (voice samples, large sprite banks) in SWRAM.

## 2) Column-buffer compositing for smooth scrolling

Rather than redrawing the entire screen each scroll step, Stryker’s Run builds a *column buffer* and then plots it.

Key concepts:
- `initialise_column_buffer` clears a small buffer (`&0300..`) before composing new pixels.
  - `&1D01..&1D0B` clears `column_buffer`.
- On scroll, it composes multiple sources into the column buffer:
  - scenery layers
  - ground layer
  - movers (entities)
- Finally it writes the column buffer to the screen:
  - `plot_column_from_buffer_loop` around `&1B9A`

This is classic incremental scrolling: only the newly exposed column is generated.

PORTHOLE takeaway:
- For flick-screen we can build whole rooms once.
- If we ever implement scrolling, the proven approach is:
  - build a column/row buffer
  - composite scenery + movers into it
  - then blit it to screen

## 3) Multiple scenery layers (including extra cloud layer)

Scrolling code iterates across multiple layers per edge:
- `scroll_screen_left` around `&18DF` sets up per-layer work.
- Comment notes: “Enhanced version has extra layer for clouds” (e.g. around `&191E`).

Each layer has:
- its own sprite bank (`scenery_layer_sprite_banks`)
- its own sprite address
- its own y position (`scenery_layers_y`)
- its own flip state (`scenery_layers_flip`)

PORTHOLE takeaway:
- If we ever want parallax or foreground cover strips, the pattern is “layer tables + loop”, not special cases.

## 4) Fast masked plotting using precomputed mask tables

Stryker’s Run uses the same fundamental masked-blit rule we use:

- `dst = (dst & mask) ^ pixel_value` (equivalent to `|` if pixel_value is pre-masked)

Inside `add_column_of_sprite_to_column_buffer`:
- fetch pixel value from a *pixel table*
- fetch mask from a *mask table*
- apply to the destination byte

Relevant inner loop (around `&1CEE..&1CF8`):
- `LDA column_buffer`
- `AND scenery_mask`
- `EOR scenery_pixel_value`
- `STA column_buffer`

It also uses self-modifying code to switch between:
- masked plot (`LDA (&c8),Y`) for scenery
- unmasked plot (`LDA #&FF`) for movers

You can see this as “plot_scenery_mask_opcode” patched at runtime:
- `&1CE2` is either `LDA (&c8),Y` or `LDA #&FF`.

PORTHOLE takeaway:
- Our masked sprite blitter is on the right path.
- For performance, avoid branching inside the pixel loop: select the mode (masked/unmasked) by patching a single opcode or using separate entry points.

## 5) Flipping support via separate address tables and mask tables

The engine stores flipped and unflipped sprite-address tables:
- `flipped_scenery_sprite_addresses_*_table`
- `unflipped_scenery_sprite_addresses_*_table`

It also has two mask tables:
- comments indicate `&0480 = flipped_mask_table`, `&04C0 = unflipped_mask_table`.

PORTHOLE takeaway:
- Runtime flipping is possible, but it requires infrastructure.
- For Chell, we should still prefer offline mirroring (generator emits left-facing variants).
- For occasional scenery props, a flip flag can be viable.

## 6) Movers are multi-part sprites (legs/torso/head)

The `plot_mover` routine shows a mover can be composed from 1–3 sprite parts:
- plot first part
- optionally plot a second part using an offset
- optionally plot a third part

See `plot_mover` around `&1E6A..&1F08`.

PORTHOLE takeaway:
- This strongly supports the “composition” mindset (base body + overlays) for Chell.
- It’s a proven way to avoid a combinatorial explosion of full-body frames.

## 7) Sprite data is column-packed and RLE-like

Both screen and scenery sprites are stored as column streams with run-length encoding:
- “Zero indicates end of column.”
- run lengths encode 1/2/3 or “next byte is run length”.

This enables very fast column rendering while scrolling.

PORTHOLE takeaway:
- For our flick-screen rooms, tile stamping is simpler.
- For large scenery objects or future scrolling, storing sprites in a column-friendly packed format can be worth it.

## 8) 65C02 usage (Master)

The enhanced engine uses 65C02 instructions:
- `INC A` (`1A`)
- `DEC A` (`3A`)
- `PHX/PLX` (`DA/FA`)

PORTHOLE takeaway:
- We can safely use 65C02-only opcodes if we’re Master-only.
- This can simplify and slightly speed up inner loops.

## Concrete PORTHOLE actions inspired by Stryker’s Run

1) Use sideways RAM as the long-term home for large sprite sets and optional voice samples.
2) Keep the “composition” approach (base + overlays) rather than enumerating every combination.
3) If we later add scrolling, consider a column-buffer compositor (scenery + movers) instead of full redraw.
4) Consider optional self-modifying selection for masked/unmasked blit entry points to keep hot loops branch-free.
