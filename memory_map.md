# PORTHOLE Memory Map (Working Draft)

This document defines which address ranges are safe for what, given our current
Master-only + shadow-screen approach.

Everything in this document is negotiable. The goal is to make current
assumptions explicit so we can change them deliberately (and update code/docs in
one place) rather than by accident.

Key rule: once we enable the Master shadow screen, `&3000..&7FFF` becomes a
*banked window* (main vs shadow). Code that needs to render to the shadow
framebuffer must have the CPU mapped to the shadow bank for that window.
Therefore, do not store long-lived tables/assets in `&3000..&7FFF` unless you
explicitly intend them to be volatile (screen/scratch).

## Invariants

- The playfield framebuffer address is `&5800` (MODE 5 layout); rendering code
  assumes this.
- `&5800..&7FFF` must be treated as volatile screen bytes (visible playfield +
  agreed scratch region).
- Any asset/table needed *during rendering* must live either:
  - outside `&3000..&7FFF` (main RAM below the shadow window), or
  - in sideways RAM (SWRAM) at `&8000..&BFFF` with explicit ROMSEL banking.

## Frame Pipeline Mapping (PoP-style)

We follow a strict update-then-render pipeline:

- **Update phase (most of frame):** CPU maps `&3000..&7FFF` to **main** RAM.
  - Safe to read/write level/material working data in this window.
  - No direct writes to the displayed framebuffer.
- **Render phase (immediately after VSYNC):** CPU maps `&3000..&7FFF` to
  **shadow** RAM.
  - Writes to `&5800..&7FFF` affect the displayed framebuffer.
  - Rendering must only read render-time assets from low RAM (`< &3000`) or
    SWRAM (`&8000..&BFFF` via ROMSEL).

## Main vs Shadow (How To Think About It)

The Master provides a banked RAM window at `&3000..&7FFF`:

- **Main bank view**: normal RAM contents.
- **Shadow bank view**: a second physical RAM bank.

Only one view is CPU-visible at a time for this address range.

When we are rendering to the shadow framebuffer (our normal gameplay mode), the
CPU must be mapped to the **shadow** view for `&3000..&7FFF`. That means:

- Reads from `&58xx` return framebuffer bytes (not “main RAM data”).
- Writes to `&58xx` modify the framebuffer (and will be displayed).

So: putting sprite/mask tables at addresses like `&58CE` is unsafe because the
renderer can’t reliably read them while it is mapped to shadow for drawing.

## Main RAM (CPU)

- `&0000..&00FF`: ZP
  - This project calls MOS routines during gameplay (e.g. `OSBYTE` for VSYNC/input),
    so we must not trample MOS/VDU/Econet-owned ZP.
  - **Policy:** keep all game ZP allocations in `&00..&8F`.
    - Avoid `&90..&FF` (MOS/VDU/Econet workspace).
    - Reserve `&70..&8F` for a small fixed pointer set relied on by hot paths.
      - Invariants (see `main.asm` + `tools/check-build-invariants`):
        - `screen_ptr = &0071`
        - `tilemap_ptr = &0079`
        - `portalmap_ptr = &007B`
- `&0100..&01FF`: stack
- `&1900..`: main code + stable game state

### Shadow window (banked)

- `&3000..&7FFF`: Master LYNNE/shadow window (banked main vs shadow)
  - When mapped to **shadow**, the CRTC-visible framebuffer lives here.
  - When mapped to **main**, it can be used as general RAM, but then you are
    not drawing to the displayed shadow framebuffer.

## Reserved Regions (This Project)

These are the address allocations we want to keep stable as the project grows.

Everything here is a *current working allocation*, not a permanent promise.

### Allocation Table (Working)

Main view (`&3000..&7FFF` mapped to main; used during update/load):

- `&3000..&3FFF` (4KB): `solid` plane
- `&4000..&4FFF` (4KB): `portalable`/interaction plane (future)
- `&5000..&56FF` (~1.75KB): room working buffers
- `&5800..&7FFF` (10KB): update/load scratch (not readable during render)

Shadow view (`&3000..&7FFF` mapped to shadow; used during render):

- `&5800..&77FF` (8KB): framebuffer playfield
- `&7800..&7FFF` (2KB): render scratch
- `&3000..&57FF`: currently unused (keep clear unless explicitly allocated)

### Shadow view: framebuffer + small render scratch

These are the only parts we plan to actively write during the post-VSYNC render
phase.

- `&5800..&77FF`: framebuffer playfield (8KB)
- `&7800..&7FFF`: render scratch (2KB)
  - save-under buffers
  - small render lists
  - 256-byte streaming buffer(s) (used during load, not during render)

### Shadow view: `&3000..&57FF` (render-only tables)

We can reserve a small portion of this window for **render-only lookup tables**
that are read exclusively during the post-VSYNC render phase (while the CPU is
mapped to shadow).

Proposed allocation:

- `&3000..&37FF`: render lookup tables (row bases, column offsets, stripe tables)
- `&3800..&57FF`: reserve for future render-only tables

Policy:

- Only read these tables while mapped to **shadow** during render.
- Never read them during update (main mapping), to avoid bank hazards.
- Keep them small and deterministic; avoid anything that must persist through
  MOS screen clears unless we explicitly manage it.

### Main view: update-time working set

This is where we want bulky per-room/per-level data that update/physics uses.
It does not need to be readable during the render phase.

Suggested initial layout (main view):

- `&3000..&3FFF`: `solid` plane working set (4KB, 1bpp for 128x256)
- `&4000..&4FFF`: `portalable` plane (future) or other interaction plane (4KB)
- `&5000..&56FF`: level/room working buffers (tilemap cache, portal layer, room
  scratch)
- `&5700..&57FF`: guard/headroom
- `&5800..&7FFF`: extra update/load buffers (main view)
  - Important: overlaps framebuffer addresses; not readable while mapped to
    shadow. Use only in update/load.

## Framebuffer (shadow bank)

- `&5800..&77FF`: playfield framebuffer (16 rows x 512 bytes/row = 8KB)
- `&7800..&7FFF`: below-playfield scratch (2KB)
  - Current uses:
    - `CHELL_SAVE_UNDER_BASE = &7800` (128 bytes)
    - `RETICLE_SAVE_UNDER_BASE = &7880` (64 bytes)
    - `SOLID_TILE_PLANE = &7A00` (256 bytes)
    - `CHELLDATA_BUF = &7B00` (256-byte file streaming buffer)

### What can live in `&5800..&7FFF` in *main* RAM?

Physically, main RAM also has bytes “under” the shadow window. However, while
we are mapped to shadow for rendering, the CPU cannot see those main bytes.

We can only use main-`&5800..&7FFF` if we temporarily switch the window back to
the main view.

Policy (given the pipeline above):

- During **render phase**: treat main-`&5800..&7FFF` as unavailable.
- During **update/room-load phase**: main-`&5800..&7FFF` is usable RAM.
  - Great candidates: per-room level working buffers, portalability layers,
    decompression workspaces.

In other words: it can be a convenient scratchpad, but it should not contain
tables/assets that the renderer expects to read while drawing.

## Safe Resident Code/Data Placement

Given our renderer only writes `&5800..&77FF` (plus specific scratch areas), the
shadow bank region below the screen base is safe for long-lived code/data:

When mapped to shadow (render phase), `&3000..&57FF` is still banked RAM, but it
is *not* part of the framebuffer footprint we actively draw into.

So `&3000..&57FF` (shadow view) is a reasonable place for resident, render-safe
tables **only if** we never rely on them while the window is mapped to main.

In practice, to keep things simple:

- Keep *code* and critical always-visible tables below `&3000`.
- Use the banked window (`&3000..&7FFF`) primarily for update-phase working
  data (main view) and framebuffer+sandbox (shadow view).

Important:

- Avoid MOS screen-clear calls after init (they may touch more of screen RAM).
- Keep our own clear/draw routines confined to the framebuffer + agreed scratch.

## Sideways RAM (SWRAM)

We avoid placing large/static asset tables in `&3000..&7FFF` so that rendering
can keep the shadow mapping stable.

Bank roles (current):

- SWRAM bank `CHELL_SWRAM_BANK_DEFAULT = 4`:
  - DFS file `CHDATA` loaded at runtime to `&8000..&BFFF`
  - Chell sprites + masks + reticle sprites

- SWRAM bank `OBJ_SWRAM_BANK_DEFAULT = 5`:
  - DFS file `OBJDAT` loaded at runtime to `&8000..&BFFF`
  - Portal/object stamp sprites + masks (all the data currently generated into
    `sprites/generated_objects_{sprites,masks}.asm`)

Render policy:

- Never bank-switch mid-blit.
- For a given render pass, group operations by `ROMSEL` bank:
  - Page `chell_bank` once, draw Chell/reticle.
  - Page `obj_bank` once, stamp portals/objects.

## Immediate Fix Target (Done)

Object stamp sprite/mask data now lives in SWRAM (DFS file `OBJDAT`) and is
loaded at runtime into `OBJ_SWRAM_BANK_DEFAULT` at `&8000..&BFFF`.

This keeps portal/object stamp sprite reads out of the banked shadow window
(`&3000..&7FFF`) during the render phase.

## Level Data Storage (Draft)

Working set needed per room at runtime:

- Tilemap: 16x16 bytes = 256 bytes per room
- Portalable layer (if stored as a 16x16 byte layer): 256 bytes per room
- Any per-room object instance table pointers

Options:

1) Small levels resident in RAM (current)
   - Keep generated room tables in the main binary and point
     `tilemap_ptr/portalmap_ptr` at them.
   - Pros: simplest, no streaming.
   - Cons: caps total level data size.

2) Stream level data from DFS per room (recommended as we scale)
   - Store room tilemaps/layers compressed or raw as DFS files.
   - On room transition, stream into a buffer (e.g. `CHELLDATA_BUF` or another
     scratch buffer), then copy/decompress into a resident working buffer.
   - Pros: virtually unlimited content.
   - Cons: more loader code.

3) Use additional SWRAM banks for level blobs
   - Treat SWRAM as “asset ROM”: keep big level blobs there.
   - Pros: fast access.
   - Cons: bank management complexity.

## Practical Size Limits (Rule Of Thumb)

- Anything that must be readable while drawing should not live in main RAM
  addresses `&3000..&7FFF`.
- The banked window starts at `&3000`. If we want to freely switch main/shadow
  each frame, it’s simplest if the *main binary code* stays below `&3000`.
  - That implies a practical ceiling of ~`&1900..&2FFF` for resident code/data.
- Bulk assets belong in SWRAM banks and are paged in explicitly.
