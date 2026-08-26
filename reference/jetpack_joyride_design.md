# PORTHOLE II: THE ESCAPE — BBC Master Design Document

BBC Master 128, MODE 2, BeebASM. Infinite horizontal scroller.

---

## Core Concept

Chell has escaped the test chambers. Now she's fleeing through the
Aperture Science facility with a stolen jetpack and a rescued lab dog.
GlaDOS is not pleased.

One-button jetpack game. Fly to avoid obstacles, collect data cores.
The dog runs along the ground and jumps to collect cores you can't
reach. Inspired by Jetpack Joyride (Halfbrick Studios).

### Setting

The Porthole universe. Same facility, same aesthetic. Corridors,
industrial walls, warning stripes. GlaDOS deploys zappers, missiles,
and lasers to recapture Chell. The dog is an Aperture Science test
animal — subject #K9-07 — who has decided to leave too.

---

## Controls

- **One button** (SPACE or joystick fire): hold to thrust upward,
  release to fall. That's it.
- Thrust applies upward acceleration; gravity pulls down when released.
- Player cannot move left/right — the world scrolls past.

---

## Player

- Fixed X position on screen (roughly 1/4 from left edge).
- Y position controlled by thrust vs gravity.
- Jetpack flame animation when thrusting (2-frame cycle).
- Sprite: 8x16 pixels (1 byte wide x 16 rows).
- Collision box: slightly smaller than visual for forgiveness.

---

## The Dog

The dog runs along the ground as a companion. It is immune to all
hazards (zappers, missiles). Its purpose is to collect cores.

### Dog AI

- **Default**: runs at scroll speed, holding position on screen.
- **Core at ground level nearby**: accelerates toward the coin.
- **Core slightly above ground**: jumps to reach it.
- **No cores nearby**: occasional small random hops for personality.
- **Falls behind**: speeds up to catch the player's X position.
- **Gets ahead**: slows down to stay roughly below the player.

### Dog sprite

- 8x8 or 8x16 pixels.
- 2-3 frame run animation cycle.
- 1 jump frame (legs tucked).
- Faces right always (world scrolls left).

### Dog jump physics

- Fixed jump height, sufficient to reach cores ~2 tiles above ground.
- Simple ballistic arc (initial vy, gravity pulls back down).
- Cannot double-jump.
- Landing snaps back to ground level.

### Core collection

- Dog collects cores by overlap, same as player.
- Collected cores count toward the same score.
- Visual feedback: coin vanishes with a small sparkle or sound.

---

## Cores

- Small sprites (8x8), scattered procedurally.
- Appear in patterns: lines, arcs, clusters.
- Core patterns are generated per "segment" of the level.
- Placed in both air (for player) and low (for dog).
- Max ~10 cores on screen at once.
- Collected by player OR dog on overlap.

---

## Obstacles

### Zappers

- Static horizontal or vertical bars.
- Background tiles — scroll for free with hardware scroll.
  No independent movement, no sprite cost.
- Horizontal zappers block a height band.
- Vertical zappers block a column (Chell must fly over/under).
- Kill Chell on contact. Dog is immune.
- Visual: alternating colour pattern (flashing via palette cycle).

### Missiles

- Warning indicator appears at right edge (flashing arrow).
- Missile enters from the right, travels horizontally left.
- Independent sprite, moves faster than scroll speed.
- 1-2 on screen at once.
- Kill the player on contact. Dog is immune.
- Sprite: 16x8 pixels (2 bytes wide).

### Lasers

- Warning beams appear briefly (thin line across screen).
- Then full laser fires for a short duration.
- Horizontal beam at a fixed Y, spanning the full screen width.
- Can be a single scanline toggled by palette/colour — very cheap.
- Kill the player on contact. Dog is immune.

---

## Scrolling Engine

Based on Moon Raider's proven architecture.

### Hardware scroll

- CRTC R12/R13 set screen start address.
- Advance by 8 bytes per frame = 4 MODE 2 pixels per frame.
- Screen memory (&3000-&7FFF, 20KB) used as circular buffer.
- Wrap-around: when high byte >= &80, subtract &50.

### New column drawing

- Each frame, draw one new tile column at the right edge.
- Column = 256 scanlines = 256 bytes (one byte per scanline).
- Tile data generated procedurally (ceiling, flat floor, zappers).
- Old left-edge column wiped on alternate frame (spread work).

### Scroll speed

- Base: 4 pixels/frame (200px/sec at 50fps).
- Increases gradually as distance increases.
- Max: 8 pixels/frame (2 column draws per frame) or faster via
  CRTC double-step.

### Split-nibble rendering

- Background tiles in high nibble (&F0).
- Foreground sprites in low nibble (&0F).
- Sprite cleanup: AND #&F0 — no save-under needed.
- Sprite draw: ORA sprite data into low nibble.

---

## Sprite System

All game objects (player, dog, cores, missiles) are foreground sprites
rendered into the low nibble.

### Object table

| Type    | Max | Size   | Movement              |
|---------|-----|--------|-----------------------|
| Player  |   1 | 8x16   | Y only (thrust/grav)  |
| Dog     |   1 | 8x16   | X relative + Y jump   |
| Cores   |  10 | 8x8    | Scroll only           |
| Missiles|   2 | 16x8   | Fast horizontal       |

All objects have X coordinates decremented each frame to compensate
for hardware scroll (Moon Raider pattern).

### Drawing order

1. Clear all sprite areas: AND #&F0 on previous positions.
2. Draw all sprites: ORA sprite data at new positions.

No EOR — nibble-split gives us free background restore.

---

## Procedural Generation

The world is generated in "segments" — each segment defines:
- Ceiling presence (open or enclosed corridor).
- Obstacle placement (zappers, laser triggers).
- Core pattern.
- Ground is always flat (lab floor).

Segments are chosen from a pool, difficulty-weighted:
- Easy segments dominate early.
- Hard segments (narrow gaps, multiple zappers) appear later.
- Missile/laser frequency increases with time.

### Segment format (compact)

Each segment is ~16-32 bytes defining:
- Length in columns (8-32 columns).
- Ceiling height (4-bit, constant or absent per segment).
- Obstacle list (type, column offset, Y position).
- Core pattern ID.

A pool of ~20-30 segments gives good variety in <1KB.

---

## Power-ups

Appear as foreground sprites, collected on contact (player only).

- **Shield**: absorbs one hit. Visual indicator on Chell sprite.
- **Slo-mo**: halves scroll speed for ~5 seconds. Everything slows.
- **Magnet**: widens core collection radius for ~5 seconds.
  Implementation: expand collision box, no physics change needed.

---

## Difficulty Curve

### Levels and sections

The game is divided into **levels**. Each level is 10 **sections**.
After completing 10 sections, the level number increments, scroll
speed increases, and the section sequence restarts with harder
variants.

A section is a short themed phase — a few seconds of gameplay
with a clear character (coins, obstacles, or a breather).

### Section pool

Each level draws from a pool of 10 section types, shuffled into
a random order at the start of the level:

| Type              | Count | Content                         |
|-------------------|-------|---------------------------------|
| Ground cores      | 2     | Easy cores along the floor      |
| Air cores         | 1     | Core arcs in the upper half     |
| Breather          | 2     | Empty corridor, sparse cores    |
| Horizontal zappers| 1     | Dodge zapper bars               |
| Vertical zappers  | 1     | Weave through columns           |
| Missiles          | 1     | Missile warnings + dodging      |
| Lasers            | 1     | Laser warnings + beams          |
| Gauntlet          | 1     | Zapper + missile combo          |

The proportions ensure every level has breathing room (4 easy
sections) balanced against challenge (6 obstacle sections).

**Level 1 exception**: sections 1-3 are fixed as ground cores,
air cores, breather — easing the player in. Sections 4-10 are
shuffled from the remaining pool.

### Shuffle implementation

At level start, fill a 10-byte array with section type IDs
(respecting the counts above). Fisher-Yates shuffle the
non-fixed portion. Index through the array during play.
Cost: 10 bytes + ~30 bytes of shuffle code.

### Speed ramp

Speed increases at each level boundary (every 10 sections):

| Level | Speed (px/frame) | Columns/frame | Feel        |
|-------|-------------------|---------------|-------------|
| 1     | 4                 | 1             | Gentle      |
| 2     | 5                 | 1-2           | Brisk       |
| 3     | 6                 | 1-2           | Fast        |
| 4     | 7                 | 2             | Intense     |
| 5+    | 8                 | 2             | Relentless  |

Speed stays constant within a level. The jump between levels
is noticeable — it's a "oh no it got faster" moment.

Implementation: fractional accumulator for sub-pixel scrolling.
Same pattern as the music 20Hz tick.

### Difficulty within sections

At higher levels, the same section types get harder:
- **Zappers**: closer together, narrower gaps.
- **Missiles**: faster, more frequent, multiple simultaneous.
- **Lasers**: shorter warning time.
- **Coins**: placed in riskier positions near hazards.

Implementation: each section template has a `level` parameter
that tightens spacing and timing. The segment data itself stays
the same — just the generation parameters scale.

### Level display

Level number, score, and time shown on the status bar:

```
LEVEL 03  SCORE 00450  TIME 2:35
```

Updated in-place each frame (just the changing digits). The
status bar scrolls with the hardware scroll, so the rightmost
edge must be redrawn each frame (Moon Raider pattern).

### Tile set rotation

Each level uses a different tile set, swapped by switching
SWRAM bank at the level boundary. Gives visual progression
with zero code change — the column-fill routine just reads
different tile data.

| Level | Tile set          | Feel                        |
|-------|-------------------|-----------------------------|
| 1     | Lab corridors     | White walls, grey floor     |
| 2     | Maintenance       | Pipes, warning stripes      |
| 3     | Server room       | Racks, blinking lights      |
| 4     | Overgrown lab     | Vines, cracked walls        |
| 5+    | Cycle 1-4         | Repeat with palette shift   |

Tile sets are stored in SWRAM banks. At 3-4KB per set, we can
fit 4 sets across banks 5-6 with room to spare. A palette
tweak on the cycle-repeat levels (5+) makes them feel fresh
even with reused tiles.

---

## Scoring & Progression

- **Cores**: +1 per core (player or dog).
- **Time**: elapsed time displayed on status bar.
- **Speed ramp**: scroll speed increases gradually with time.
- Game ends on player death. Dog runs off screen to the right.
- High score stored in main RAM (lost on power off, or saved to
  filing system if we want persistence).

---

## Screen Layout

```
+----------------------------------+
| LEVEL 03  SCORE 00450  TIME 2:35 |  <- Status bar (top 2 char rows)
+----------------------------------+
|                                  |
|          [player]                |
|                      o  o  o     |  <- Cores
|   ====ZAPPER====                 |
|                                  |
|              o                   |
|         [dog]    o               |
|================================= |  <- Ground
+----------------------------------+
```

- Status bar: top 2 character rows (redrawn right edge after scroll).
- Playfield: remaining 30 character rows.
- Ground: bottom 2 character rows (flat, lab floor).

---

## Memory Map (MODE 2, BBC Master)

### Zero Page (&00-&8F)

| Range   | Purpose                                     |
|---------|---------------------------------------------|
| &00-&0F | Scroll state (screen start, column ptr)     |
| &10-&1F | Player state (x, y, vy, thrust, alive)      |
| &20-&2F | Dog state (x, y, vy, jumping, target_coin)  |
| &30-&3F | Generation state (segment ptr, column idx)  |
| &40-&4F | Missile state (x, y, active, speed)         |
| &50-&5F | Timing, score, distance                     |
| &60-&6F | Temp pointers, sprite drawing               |
| &70-&8F | Additional game state / free                |

### Main RAM

| Range       | Size   | Purpose                                |
|-------------|--------|----------------------------------------|
| &0900-&0CFF |  1,024 | Object arrays (cores, missiles)        |
| &0D00-&0DFF |    256 | DFS NMI — do not touch                 |
| &0E00-&18FF |  2,816 | Music engine + data (shared w/ Porthole)|
| &1900-&2FFF |  5,888 | Game code: render-safe zone (blitters)  |
| &3000-&7FFF | 20,480 | LYNNE: screen (hardware scrolled)      |

### SWRAM (&8000-&BFFF)

| Bank | Purpose                                      |
|------|----------------------------------------------|
| 4    | Player + dog sprites, coin sprites           |
| 5    | Tile data, obstacle sprites, missile sprites |
| 6    | Segment pool, procedural gen tables           |
| 7    | Music data / free                            |

---

## Colour Palette (MODE 2, 16 colours)

MODE 2 with split-nibble gives us 8 background colours (high nibble)
and 8 foreground colours (low nibble).

### Background (high nibble)

| Index | Use                    |
|-------|------------------------|
| 0     | Sky (dark blue/black)  |
| 1     | Ground (brown/grey)    |
| 2     | Ceiling (grey)         |
| 3     | Zapper bar (yellow)    |
| 4     | Wall detail            |
| 5-7   | Reserved / decoration  |

### Foreground (low nibble)

| Index | Use                    |
|-------|------------------------|
| 0     | Transparent (no sprite)|
| 1     | Player (white)         |
| 2     | Dog (brown/tan)        |
| 3     | Core (yellow)          |
| 4     | Missile (red)          |
| 5     | Jetpack flame (orange) |
| 6     | UI / score text        |
| 7     | Sparkle / effects      |

---

## Audio

Reuse the 3-voice music engine from Porthole.

- **Music**: upbeat chiptune loop (not Gymnopédie!).
- **SFX via channel steal**:
  - Jetpack thrust: noise channel buzz.
  - Core collect: short high blip.
  - Missile warning: rising tone.
  - Death: descending crash.
  - Dog bark: short noise burst (on jump?).

---

## Development Phases

### Phase 1: Scroll engine proof-of-concept
- MODE 2 setup with CRTC hardware scroll.
- Circular buffer column fill with flat ground/sky.
- Status bar that doesn't scroll (or is redrawn).

### Phase 2: Player
- Thrust/gravity physics.
- Sprite rendering in low nibble.
- Ground collision.

### Phase 3: Dog
- Ground-running sprite with animation.
- Jump physics.
- Follow-player AI.

### Phase 4: Cores
- Procedural coin placement.
- Player + dog collection.
- Score display.

### Phase 5: Obstacles
- Zappers in background tiles.
- Missiles as independent sprites.
- Collision detection.
- Death + restart.

### Phase 6: Polish
- Music integration.
- Difficulty ramp.
- Title screen.
- High score.

---

## Open Questions

- GlaDOS taunts on the status bar? ("You can't escape.")
- Reuse Porthole tile art directly, or new art for the
  escape corridors?
- How does the dog enter at game start? Already running?
  Chell opens a cage?
- Power-up spawn frequency / difficulty curve tuning.
- Ceiling sections: always present, sometimes, or alternating?
