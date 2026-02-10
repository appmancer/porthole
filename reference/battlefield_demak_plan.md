# Battlefield 1942 Demake Plan (Syncron-Like Vertical Scroller)

This document captures a concrete, implementation-oriented plan for a BBC Master (65C02) demake of **Battlefield 1942** as a **top-down vertical scroller**, using **Syncron-like** scrolling and rendering techniques.

Key reference:
- `reference/syncron_research.md`

## High-level game pitch

- Top-down 2D battlefield over a tall vertical map.
- Player chooses role **before spawn**:
  - `infantry` (faster capture; general weapon)
  - `anti_tank` (slower capture; limited rockets)
- Limited ammo; rearm at fixed rearm points.
- Capture-and-hold control points (CTF-like territory control): take points, hold to spawn and to win.

Vehicles are simple state transitions:

- Jeep: medium speed, unarmed.
- Tank: slow, high armor, powerful shot.
- Boat: jeep-on-water.
- Plane: fast; shoots other planes; bombs ground targets.

Visual priority: fast, readable gameplay over detail.

## Non-negotiable technical constraints

- Scrolling should be **hardware start-address scrolling** (CRTC) like Syncron.
- Scroll step is **8 pixels** (one character row = 8 scanlines).
- Keep sprites **small and fixed-size**; target is **8x16** for everything.

Rationale: 8x16 aligns with the engine’s 8x16 cell grid and keeps CPU cost predictable.

## Display mode direction

- Prefer MODE 5-style bitmap (or the existing custom narrow MODE 5 approach in this repo).
- Avoid MODE 2 for this project: it changes memory layout and increases bandwidth cost; it would force a rewrite of the core scroll+strip routines.

## Core engine architecture (Syncron-like)

### 1) Scrolling model (ring-buffer screen)

Adopt Syncron’s model:

- Screen memory is treated as a **ring buffer**.
- Each scroll step:
  - advances a software "screen base" pointer by one row
  - updates CRTC R12/R13 to match
  - stamps the newly revealed 8-scanline strip

Outcome: no full-screen copies; constant work per scroll step.

### 2) Background rendering: stamp one strip per scroll step

- World is tile-based.
- Each scroll step draws exactly one **8-scanline** horizontal strip across the view.

Target background data design (Syncron-inspired):

- `map` (tile IDs)
- `tile -> chunk row -> chunk IDs`
- `chunk bitmaps` (8-byte or otherwise strip-native)

Goal: strip stamping is a tight loop: lookup + copy bytes.

### 3) Sprites: XOR plotting (erase-by-redraw)

Plan: use **XOR sprites** for moving objects (player, NPCs, bullets, vehicles).

Why XOR:

- Scrolling background makes save-under expensive/fragile.
- XOR gives cheap erase (plot again) and is naturally compatible with a moving ring-buffer background.

Important constraints:

- Sprite art must be designed to look good under XOR (high-contrast silhouettes; avoid subtle shading).
- Keep a strict draw order to avoid overlap artifacts (or avoid sprite overlap by design).

### 4) Timing: IRQ-driven frame counter

Use a Syncron-like pacing scheme:

- IRQ handler increments a `frame_counter`.
- Main loop waits for `frame_counter` change.

This makes scroll + input + drawing occur in a stable cadence.

## Gameplay systems (bounded and cheap)

### Entities

Target: up to ~20 combatants on screen, but budgeted.

Approach:

- Fixed-size entity slots.
- Stagger AI updates (e.g. 1/2/4 frame cadence) to keep per-frame cost bounded.
- Cap projectiles and effects hard (bullets, bombs, explosions).

### Movement

- Input supports 8-way movement.
- Use a speed table that compensates for MODE 5 pixel aspect (avoid shallow diagonals).
- Consider fixed-point position (subpixel) even if scroll is 8px steps.

### Spawning / roles

- Role is chosen before spawn.
- Spawn points are fixed per team / per held control point.

### Ammo + rearm

- Weapons have limited ammo.
- Rearm points are fixed world locations; rearm is fast and obvious.

### Control points

- Each control point has:
  - owner
  - capture progress
  - spawn enablement
  - optional vehicle availability

Capture rule (simple, demake-friendly):

- Standing in the capture zone adds progress.
- Multiple friendlies add progress faster.
- Enemies contest and/or reverse.

## Data + authoring direction

- Map is a tall vertical strip; designed around 8px scroll steps.
- Key authored features:
  - terrain tiles
  - capture point zones
  - spawn points
  - rearm points
  - vehicle spawn pads

Keep authoring grid aligned to the engine’s cell model (8x16 cells).

## Risks / watchouts

- XOR overlap artifacts: if many entities overlap, redraw order matters and can look messy.
- Strip stamping cost: the strip draw must be extremely tight; it runs every scroll step.
- HUD + UI: should avoid heavy per-frame redraw; consider fixed HUD band or a low-frequency update.

## Milestone: first playable (technical proof)

Build in this order:

1) Hardware vertical scroll in 8px steps (ring-buffer).
2) Stamp the new 8-scanline strip from a simple test tilemap.
3) XOR draw/un-draw one 8x16 player sprite with scroll-aware address computation.
4) Add bullets (capped) and 4 AI enemies.
5) Add capture point progress + respawn.
6) Scale up entity count and add vehicle state machines.
