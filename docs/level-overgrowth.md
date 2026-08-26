# Overgrowth — feature list

Green/black themed level built around burning vines to make progress.

**Core rule:** vines block portals and block laser beams. Lasers burn vines away.

## Features

- Limited portalable wall faces at the start; most surfaces are vine-covered.
- Burn vines off a wall to reveal a portalable face underneath.
- Burn vines off an exit to open it.
- Vine floors: solid and walkable, burn through to drop to what's below.
- Vines as back-wall wallpaper — non-solid scenery, breaks up the black.
- Chained burns: clearing one vine tile lets the beam through to the next.
- Burn has a short countdown so it reads as an event, not a teleport.
- Vine density drops room to room, so the level records the player's progress.

## Lasers and sentries

- Sentries **block beams**.
- A beam hitting a sentry **disables it temporarily**; it reboots after a
  delay. It does not destroy it.
- Disabled sentries can already be picked up and carried, so the laser
  becomes a way to *acquire* a sentry, not just neutralise one.
- Rationale: destroying sentries would collapse level 10's vocabulary (block
  with a cube / close a barrier / carry to a pad) wherever a laser exists.

## Tiles required

Each is a distinct tile with a burn target — not an overlay.

| Tile | Solid | Burns to |
|---|---|---|
| Vine wall face (x4 orientations) | yes | portalable wall face, same orientation |
| Vine floor | yes | empty |
| Vine exit cover | yes | exit tile |
| Vine over bedrock (x4) *(later level)* | yes | bedrock |
| Back-wall vine wallpaper (2-3 variants) | **no** | n/a — decorative |

**Authoring rule: dense mass = burnable, sparse tendrils = scenery.**
Non-solid tiles never reach the beam's solid check, so wallpaper can never
burn. The two classes must not look alike.

Wallpaper is not optional — with black as the background fill, large untiled
areas read as *void* rather than *surface*.

## Engine work

1. **Burn table.** Flat `burn_target[tile_id]`, one byte per id, 0 = not
   burnable. Hooks the solid check at `shared/laser.asm:418` alongside the
   existing zapper case. Copy to main RAM at level load — the trace must not
   page SWRAM mid-loop. One `(room, x, y, timer)` slot per beam for the
   countdown; no per-cell state.

2. **Burn undo list.** Record `(room, x, y, original_id)` per burn (~4 bytes,
   32 entries = 128 bytes), replay in `restart_level`. Needed because
   `restart_level` (`mode5/main.asm:383`) never calls `load_level`, so burns
   otherwise survive death and an ill-timed burn softlocks. Same record
   regrowth will need later.

3. **Sentry beam interaction.** Beam stops at sentries; sets the existing
   disabled state with a reboot timer.

4. **Per-level palette.** `mode5/ui.asm:33` is a fixed 24-byte table applied
   once at startup. Needs to become per-level data.

5. **Per-level background fill.** `mode5/render.asm:413` hardcodes `LDA #&F0`
   (colour 2). Green levels need `#&00`. Same place as (4).

6. **Theme selection.** `mode5/render.asm:494` and `:550` reach `sprite_table`
   as a fixed absolute address — needs an indirect pointer or patched operands
   at level load. Do this before the burn table; both touch tile lookup.

Budget: `check-build-invariants:74` caps the `laser` section at 1664 bytes.
Current usage unmeasured — needs a build.

## Verified engine facts

- **Bit 5 of the tile id is the solid flag** (`shared/laser.asm:418`,
  `mode5/render.asm:1267`). Ids 32-63 solid, 0-31 not.
- **Portalable = ids 32/33/34/35** (T32 top, T33 right, T34 bottom, T35 left),
  checked in `shared/reticle.asm:207`. So one id swap changes art, collision
  and portal-eligibility together.
  - The same routine also tests ids 2/3/4/5 — dead code. Those are the
    pedestal button and closed-exit tiles; both rules need a pair of
    *identical* adjacent tiles and exits are authored 3,4 / 3,5. Checked all
    13 levels: 51 placements, zero matching pairs. Comment is stale, as is the
    `portalmap_ptr` mention at `mode5/render.asm:1260` (no such symbol).
- **`solid_tile_plane` is derived** from the tilemap (`mode5/render.asm:1263`)
  and rebuilt on room entry. Burns write the tilemap; patch the plane directly
  only for the current room.
- **`obj_room = &FF` means absent** — generic, type-agnostic. The cube spawner
  (`shared/persistent_objects.asm:1018`) materialises objects this way.
- **Signal bus:** `obj_channel` indexed into `sig_state`
  (`shared/persistent_objects.asm:794`). A burn can raise a signal and drive
  anything a button drives.
- **Tile payload is 2176 bytes** in a 16KB bank — seven sheets fit in the
  space already loaded at boot. No `TILDAT` swapping needed.
- Palette-only inversion is not viable: Chell's outline is 4299 pixels of
  index 0, so she would turn green. Tile art must be inverted instead
  (`tools/invert-tile-colours --pair 0,2`).

## Not in this level

Regrowth. Vines hiding bedrock. Burning to reveal cubes or sentries.
