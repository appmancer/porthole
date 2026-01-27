# Lessons from Codename: Droid (Superior, 1987)

Reference disassembly:
- https://level7.org.uk/miscellany/codename-droid-disassembly.txt

Codename: Droid is a great example of a fast, practical BBC engine with smooth movement and lots of on-screen activity.

This document records the techniques that look directly relevant to PORTHOLE.

## 1) Frame pacing via VSYNC

Main loop repeatedly calls `wait_for_vsync` (`JSR &2719`) and interleaves update phases with vsync waits.

Example near game loop start:
- `&1113  JSR &2719 ; wait_for_vsync`
- `&1143  JSR &2719 ; wait_for_vsync`
- `&114c  JSR &2719 ; wait_for_vsync`

Takeaway for PORTHOLE:
- We should keep a clear model of frame phases (input → physics → erase/restore → draw) and only add vblank syncing if flicker becomes objectionable.

## 2) “Dirty” scrolling via CRTC start address

Droid scrolls by adjusting the CRTC start address each scroll step:
- `set_crtc_address` is called (`JSR &2704`) after updating `crtc_address_low/high`.

Example (scroll right):
- updates `screen_start_address_low/high`
- updates `crtc_address_low/high`
- `JSR &2704 ; set_crtc_address`

Takeaway for PORTHOLE:
- If we ever move from flick-screen to scrolling, CRTC start-address scrolling is the likely path.
- This repo currently treats `&7800..&7FFF` as scratch “below playfield”; if we adopt CRTC start-address scrolling later we must revisit that contract.

## 3) Tile plotting: draw only what enters the view

During scrolling, Droid plots only the newly revealed column/row:
- `plot_column_of_tiles` (`JSR &18cf`) during horizontal scroll
- `plot_row_of_tiles` (`JSR &1a28`) during vertical scroll

This is classic incremental tile rendering: cheap per-step redraw instead of rebuilding the full screen.

Takeaway for PORTHOLE:
- For flick-screen rooms we can still use “render full room once” into a clean background.
- If we later implement scrolling, incremental column/row drawing is the right approach.

## 4) Sub-tile scroll fractions

Droid tracks fractional scroll state:
- `left_edge_x_fraction` / `right_edge_x_fraction` range 0..3
- a new tile column is consumed when the fraction wraps

This matches our concept of `x_sub` (0..3) for 2bpp packed pixels.

Takeaway for PORTHOLE:
- Our `x0..x3` subpixel variants and `x_sub` logic are aligned with proven Beeb practice.

## 5) Conditional mirroring / flip flags for certain tiles

The disassembly shows tile sprite entries sometimes include flip flags:
- `FLIP_HORIZONTALLY` is stored into `tile_sprites_addresses_table` for an animated chandelier.

Example:
- `&11a3 LDA #&02 ; FLIP_HORIZONTALLY`
- `&11a5 STA &0fda ; tile_sprites_addresses_table + 2 * TILE_CHANDELIER`

Takeaway for PORTHOLE:
- Mirroring at draw-time is a powerful tool, but it complicates the hot blitter.
- For Chell, we should keep mirroring in the *asset pipeline* (generate left-facing sprites offline).
- For occasional tiles/props, a flip flag can be viable if it’s rare and the renderer supports it cheaply.

## 6) Input handling via OS key state

Droid reads `os_most_recently_pressed_key` / `os_first_pressed_key` and uses custom suppression for auto-repeat.

Takeaway for PORTHOLE:
- Start with OS-provided key state for iteration.
- Migrate to direct VIA scanning later if we need more speed and reliable multi-key reads.

## Suggested PORTHOLE action items

1) Keep the `x_sub` 0..3 model (matches Droid’s fractions).
2) Prefer offline mirroring for character sprites.
3) Keep incremental tile redraw in mind if we ever add scrolling.
4) Treat CRTC start-address scrolling as a later feature that would require revisiting our screen-memory scratch conventions.
