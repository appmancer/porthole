# Stardot sprite routine notes (tricky’s patterns)

This document captures useful sprite-rendering techniques discussed by `tricky` on Stardot, with links back to the original posts.

Thread: https://stardot.org.uk/forums/viewtopic.php?t=27400

## Why this matters for PORTHOLE

PORTHOLE needs:

- Many moving sprites over a non-trivial background.
- Sub-byte horizontal motion (pre-shifted variants).
- Fast “erase + redraw” without leaving trails.

The thread contains several proven BBC Micro/Master techniques that map directly onto our design.

## Key posts

- Main write-up (sprite routines): https://stardot.org.uk/forums/viewtopic.php?p=399810#p399810
- Follow-up on time-slicing / avoiding flicker: https://stardot.org.uk/forums/viewtopic.php?p=399821#p399821
- Clarification on slices spanning and origin choice: https://stardot.org.uk/forums/viewtopic.php?p=399827#p399827
- Later discussion comparing save-under vs EOR methods (timings): https://stardot.org.uk/forums/viewtopic.php?p=402797#p402797
- 2025 follow-up: more notes on shifted sprites, masks, and typical 4/5 byte widths: https://stardot.org.uk/forums/viewtopic.php?p=445548#p445548

## Techniques worth reusing

### 1) Pre-shifted sprites for sub-byte movement

- For pixel-precise horizontal motion, keep a copy of each sprite at each required sub-byte offset.
- In MODE 1/5-style packed formats, that usually means 2–4 variants per direction.
- This matches our current approach (`x0..x3`).

Takeaway for PORTHOLE:
- Keep the hot blitter simple.
- Generate subpixel variants and mirrored variants offline in `tools/gen-sprites`.

### 2) Save-under background restore (screen → buffer → screen)

When sprites move over a complex background, you need to erase cleanly.

- Store the background under a sprite into a scratch buffer.
- Draw sprite.
- Later restore the background from that buffer.

This is essentially the “peel / layrsave” model used by many engines.

Takeaway for PORTHOLE:
- Move from one global save-under buffer to a small pool (Chell + cube + 1–2 extra).
- Keep each save-under buffer sized to the sprite footprint.

### 3) Self-modifying draw lists (address lists)

The thread shows a way to maintain a list of sprites to draw using self-modified `STA screen,y` sequences, and adding/removing entries by patching addresses.

Takeaway for PORTHOLE:
- If we later need many small fixed-position sprites (particles, UI elements), a draw list can outperform per-object loops.
- For now, the main win is the general idea: keep a compact draw list rather than hardcoding draw order.

### 4) Layering: background / sprites / foreground

The thread repeatedly highlights a key truth:
- Overlapping sprites and backgrounds get complicated fast.

A clean workaround is explicit layering:
- restore old background
- draw moving sprites
- draw foreground cover sprites (grates/pipes)

Takeaway for PORTHOLE:
- Implement an explicit BG/MID/FG draw pipeline (as in PoP).
- Use FG cover objects to allow “Chell behind things” without per-pixel occlusion masks.

### 5) Time-slicing screen updates to reduce flicker

If you can’t do all restore+draw inside vblank:
- Split the screen into slices (e.g. 4 bands)
- Update a band while the beam is elsewhere

Key detail: if a sprite spans slices, it can still be safe if:
- you choose a consistent origin (e.g. bottom-left), and
- the restore region is offset to cover the maximum sprite height.

Takeaway for PORTHOLE:
- We can ignore this until we have many objects.
- If flicker becomes a hard problem, time-slicing is a proven fallback.

### 6) EOR vs save-under

There’s a later post comparing costs of:
- masked blit + save-under
- EOR-with-diff restore

Conclusion in the thread: EOR is not obviously cheaper once you account for diff storage and overlap issues.

Takeaway for PORTHOLE:
- Prefer save-under/restore for correctness with overlapping objects.

## Action items for PORTHOLE

1) Extend `tools/gen-sprites` to generate mirrored left-facing variants (offline).
2) Replace the single save-under buffer with a pool.
3) Add a minimal BG/MID/FG draw list concept (start with MID=Chell, FG empty).
4) Only revisit time-slicing if flicker becomes a hard limit.
