# Lessons from `pop-beeb` (Prince of Persia on BBC Master)

This document captures specific engine patterns from KieranHJ’s Prince of Persia port (`pop-beeb`) that are worth reusing in PORTHOLE.

Reference project: https://github.com/kieranhj/pop-beeb

## Big-picture takeaways

- Treat rendering as a *pipeline* with explicit stages and lists, not a free-for-all of drawing calls.
- Use a save/restore approach (“save-under” / “peel”) to erase moving objects instead of re-rendering the background.
- Keep the hot blitters simple; push complexity into offline asset generation or precomputed tables.
- Be deliberate about memory/banking boundaries on the Master (shadow screen, sideways RAM banks, etc.).

## Rendering pipeline: BG / MID / FG lists + peel buffers

`pop-beeb` draws the scene by collecting images into separate lists, then rendering them in a predictable order.

Key routine: `Source/GRAFIX.S` `DRAWALL` (around line 484)
- https://github.com/kieranhj/pop-beeb/blob/master/Source/GRAFIX.S#L484

The critical sequence is:

1) **Peel** previously saved underlayers (restore what was behind moving objects)
2) Clear peel list
3) Draw wipes
4) Draw background list
5) Draw mid list (characters/active objects) and save-under as needed
6) Draw foreground list
7) Draw messages

Supporting routines (all in `Source/GRAFIX.S`):
- `SNGPEEL` (peel/restore) around line 641: https://github.com/kieranhj/pop-beeb/blob/master/Source/GRAFIX.S#L641
- `ZEROPEEL` (reset peel list / choose peel buffer) around line 999: https://github.com/kieranhj/pop-beeb/blob/master/Source/GRAFIX.S#L999
- `ADDPEEL` (register a saved underlayer) around line 436: https://github.com/kieranhj/pop-beeb/blob/master/Source/GRAFIX.S#L436
- `DRAWBACK` (background list) around line 571: https://github.com/kieranhj/pop-beeb/blob/master/Source/GRAFIX.S#L571
- `DRAWMID` (mid list; characters; layrsave) around line 679: https://github.com/kieranhj/pop-beeb/blob/master/Source/GRAFIX.S#L679
- `DRAWFORE` (foreground list) around line 603: https://github.com/kieranhj/pop-beeb/blob/master/Source/GRAFIX.S#L603

### How this maps to PORTHOLE

We’ve already proven the core mechanism (save-under / restore) with Chell.

Next evolution steps (PORTHOLE):
- Replace the single save-under buffer with a small pool (one per “active moving object”).
- Maintain explicit draw lists:
  - background is mostly static (room render into the screen)
  - mid: Chell, cubes, turrets, pellets
  - fore: grates/pipes/foreground cover objects that should draw over Chell

This gives us “Chell behind foreground” without needing a per-pixel foreground mask.

## Save-under and fast blitters (lay/fastlay/peel)

`pop-beeb` has multiple rendering routines with different constraints:
- a “fast lay” path for simple cases (no clipping/mirroring/etc.)
- a more general lay path
- a save-under (“layrsave”) path that stores the underlayer into a peel buffer

The high-level plumbing for these calls lives in `Source/GRAFIX.S` (see `DRAWMID`).

In the port’s Beeb-specific codebase, the fast plotters are also broken into separate modules:
- `game/beeb-plot-fastlay.asm`
- `game/beeb-plot-layrsave.asm`
- `game/beeb-plot-peel.asm`
- `game/beeb-plot-wipe.asm`

(These are the “engine primitives” that the higher-level image-list pipeline uses.)

### PORTHOLE implication

Keep our blitter surface-area small and predictable:
- One masked sprite blitter (already great).
- One save-under and one restore-under routine per moving object.
- Optional: a “fast lay” for 8×16 cells (background build), because those are aligned and don’t need subpixel offsets.

## Collision model in PoP (very game-specific)

PoP’s collision is not “pixel material planes”; it’s based on per-block semantics and barrier distances.

Relevant starting points:
- `CHECKBARR` (barrier collision scan) `Source/COLL.S` around line 72: https://github.com/kieranhj/pop-beeb/blob/master/Source/COLL.S#L72
- `COLLISIONS` (respond to collision) around line 400: https://github.com/kieranhj/pop-beeb/blob/master/Source/COLL.S#L400
- `CHECKCOLL` (block-specific collision rules) around line 527: https://github.com/kieranhj/pop-beeb/blob/master/Source/COLL.S#L527
- `GETFWDDIST` (careful step distance) around line 822: https://github.com/kieranhj/pop-beeb/blob/master/Source/COLL.S#L822
- `ANIMCHAR` (drives animation/state sequencing) around line 994: https://github.com/kieranhj/pop-beeb/blob/master/Source/COLL.S#L994

### PORTHOLE implication

For PORTHOLE, we keep PoP’s *architectural* lesson (tight hot-path queries, game-specific rules expressed explicitly),
while using our own collision truth model:

- `solid` 1bpp plane for pixel-perfect collision queries.
- `portalable` stored sparsely as a tile-layer (or later as spans), since portal checks are not in the hot path.

## Memory/banking pragmatism

The Master architecture constraints are real; `pop-beeb` is explicit about them.

The developer notes have useful discussion on shadow RAM, double-buffering constraints, and sideways RAM usage:
- Notes: https://github.com/kieranhj/pop-beeb/blob/master/Notes/pop%20notes.txt
- “* Notes:” section around line 315: https://github.com/kieranhj/pop-beeb/blob/master/Notes/pop%20notes.txt#L315
- “Image lists” section around line 1135: https://github.com/kieranhj/pop-beeb/blob/master/Notes/pop%20notes.txt#L1135
- “Double-buffering” section around line 1277: https://github.com/kieranhj/pop-beeb/blob/master/Notes/pop%20notes.txt#L1277

Sideways RAM as an asset store is a recurring theme in the notes (sprites/background sets).
For PORTHOLE this aligns nicely with your idea:
- Sideways RAM banks as a home for sampled voice lines / SFX, loaded once per episode.

Related code modules in `pop-beeb`:
- `lib/swr.asm` (sideways RAM support): https://github.com/kieranhj/pop-beeb/blob/master/lib/swr.asm
- `game/beeb_audio_banks.asm` and `game/beeb_sfx_bank.asm` (audio bank organisation)

## Concrete actions for PORTHOLE (derived from these lessons)

1) Implement explicit BG/MID/FG draw lists.
2) Replace one global save-under buffer with a small pool (Chell + cube to start).
3) Keep sprite blitters simple; do mirroring and subpixel variants in the generator.
4) Keep collision truth separate from background pixels (material planes + sparse portal layer).
5) Plan sideways RAM usage for bulk assets (SFX/voice, later sprite sets).
