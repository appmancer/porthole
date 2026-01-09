# Lessons from RetroSoftware Sample Code Library

This document collects techniques from the RetroSoftware wiki that are relevant to PORTHOLE.

Index: http://www.retrosoftware.co.uk/wiki/index.php?title=SampleCodeLibrary

## 1) Sorting sprites by scanline cheaply (bucket sort)

Page: http://www.retrosoftware.co.uk/wiki/index.php?title=Linear_time_bucket_sort

What it is:
- A tiny linear-time bucket sort (53–60 bytes) intended to sort many sprites by “character line” (scanline bucket) so you can render top-down and keep in step with the raster.

Why it matters for PORTHOLE:
- Once we have multiple moving entities (Chell, cube, turrets, pellets, particles), we will want deterministic ordering and potentially a “draw per band” approach to reduce flicker.
- Even if we never chase the raster, bucket sort is a compact way to build ordered draw lists.

How it maps to our engine:
- Store each sprite’s “band index” (e.g. `y >> 4` for our 16px cell rows, or `y >> 3` for 8px bands).
- Sort sprite indices into a render order list once per frame (or only when things move).

Notes:
- The version on the wiki expects buckets in ZP for best performance.

## 2) Keyboard reads without OS overhead (System VIA)

Page: http://www.retrosoftware.co.uk/wiki/index.php?title=Reading_the_keyboard_by_direct_hardware_access

What it is:
- A direct keyboard matrix poll via System VIA port A (`&FE4F`) after one-time setup of DDR and addressable latch selection.

Key takeaways:
- OSBYTE-based polling (`OSBYTE &81` / `&79`) is convenient but slower.
- Direct VIA reads are very fast, but you must:
  - keep interrupts disabled (or have an IRQ handler that doesn’t let the OS undo the VIA config), and
  - ensure the keyboard is enabled on the addressable latch.

Why it matters for PORTHOLE:
- Once we transition from demo movement to real control, direct polling will give us stable multi-key reads and more CPU for rendering.

Practical approach for PORTHOLE:
- For early development, OSBYTE reads are fine.
- For “shipping” gameplay loop, migrate to VIA polling.

## 3) Mode 4/5 address math (10KB screen)

Page: http://www.retrosoftware.co.uk/wiki/index.php?title=Calculate_Screen_Address10KMode

What it is:
- A general-purpose formula to compute a Mode 4/5 screen address for `(X_byte, Y)`.

Formula (from the page):
- `addr = ScreenBase + (((Y div 8) * BytesPerCharRow) + (Y and 7)) + (X_byte * 8)`

Why it matters for PORTHOLE:
- Our engine uses a custom MODE 5 layout (128px wide), and we already exploit the geometry heavily (32 bytes/scanline, 512 bytes per 16px cell row).
- It’s still useful as a sanity reference when we adjust screen layout, add HUD bands, or change base addresses.

## 4) Vertical rupture (Mode 5)

Page: http://www.retrosoftware.co.uk/wiki/index.php?title=VerticalRuptureScrollingMode5

What it is:
- A (brief) demo note about vertical rupture scrolling.

Why it matters for PORTHOLE:
- We currently flick between rooms (no scrolling).
- However, rupture-style tricks can be useful later for:
  - camera shakes
  - portal “warp” effects
  - heat haze / fizzler effects

## Suggested PORTHOLE action items

1) Keep a note of bucket sort as our future “sprite ordering” tool.
2) Plan for direct VIA keyboard reads once collisions/physics are in place.
3) Keep the Mode 5 address formula as a reference when altering our CRTC/screen model.
4) Treat rupture tricks as optional VFX, not core gameplay.
