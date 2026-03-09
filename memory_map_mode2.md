# PORTHOLE MODE 2 Memory Map

BBC Master 128. BeebAsm. Emulator: B2.

Target: MODE 2 nibble-split rendering with dynamic-steal audio.

---

## Overview

MODE 2 gives 16 colours at 160×256 but we keep the 128px visible width
(CRTC R1=32) giving a 16KB screen. Nibble-split rendering puts background
tiles in one nibble and foreground sprites in the other. Restoring
background after sprite movement is `AND #&F0` — no save-under buffers.

Sprites and tiles are new art for the extended palette — not conversions
of the MODE 5 assets. Sprites don't need masks (just `ORA` into the
foreground nibble), so sprite data is the same size as MODE 5 sprite+mask
combined.

---

## ACCCON (&FE34)

Same as MODE 5. Shadow active: D=1 (CRTC displays LYNNE), X toggled
per-blitter. All orchestration code runs with X=0.

---

## Zero Page (&00-&8F)

Same layout as MODE 5. Game logic is mode-independent.

| Range   | Purpose                                          |
|---------|--------------------------------------------------|
| &00-&6F | Game state (pos, vel, flags, animation, portals) |
| &70-&8F | Fixed pointers (screen_ptr, tilemap_ptr, etc.)   |
| &90-&FF | **RESERVED: MOS/VDU/Econet**                     |

---

## Main RAM (CPU view when X=0)

### Below &3000 — render-safe zone

Blitter code that runs with X=1 must reside here. Nibble-split blitters
are simpler than MODE 5 masked blitters (no AND/ORA mask pair — just ORA
sprite data into foreground nibble, AND #&F0 to restore).

| Range       | Size  | Purpose                                         |
|-------------|------:|-------------------------------------------------|
| &0000-&00FF |   256 | Zero page                                       |
| &0100-&01FF |   256 | 6502 stack                                      |
| &0200-&08FF | 1,792 | MOS workspace                                   |
| &0900-&09DF |   224 | Trampoline code + OSFILE block + filename        |
| &09E0-&0CFF |   800 | Available (below DFS NMI handler)                |
| &0D00-&0DFF |   256 | DFS NMI handler — **do not overwrite**           |
| &0E00-&12FF | 1,280 | Music engine + ring buffer (see Audio section)   |
| &1300-&18FF | 1,536 | Tune data + SFX tables (~1KB music + ~256B SFX)  |
| &1900-&2FFF | 5,888 | Code: render-safe zone (blitters, sprite tables)  |

### Above render-safe zone — update-only code

Game logic, physics, data. Runs only with X=0. Ceiling &7800.

Same sections as MODE 5 — game logic is shared. The render-safe zone may
shrink slightly (simpler blitters) giving more room here.

| Range       | Size   | Purpose                                        |
|-------------|-------:|------------------------------------------------|
| &2900-&77FF | ~20 KB | Game logic, level parsing, object management    |

---

## LYNNE / Shadow RAM (CPU view when X=1)

Visible at &3000-&7FFF when ACCCON X=1. CRTC displays this when D=1.

### Data area (&3000-&3FFF)

4,096 bytes. Below the screen. Accessed by setting X=1 from code below
&3000. Written at init or room-load time.

| Address       | Size  | Purpose                                      |
|---------------|------:|----------------------------------------------|
| &3000-&3FFF   | 4,096 | Level pack data (loaded from disc)            |

Level packs are ~1KB per level, ~5KB per pack of 5 levels. 4KB fits a
small pack; larger packs can spill into SWRAM bank 7 if needed.

### Screen (&4000-&7FFF)

| Address       | Size   | Purpose                                      |
|---------------|-------:|----------------------------------------------|
| &4000-&7FFF   | 16,384 | MODE 2 framebuffer (128px × 256 scanlines)   |

64 bytes per scanline. 1,024 bytes per cell row (16 scanlines × 64).
No render scratch area — nibble-split needs no save-under buffers.

---

## SWRAM (&8000-&BFFF, paged via ROMSEL)

Always write &F4 before &FE30; use SEI around bank switches.

| Bank | Size   | Purpose                                              |
|------|-------:|------------------------------------------------------|
| 4    | 16,384 | Chell sprites (~16KB, no masks)                      |
| 5    | 16,384 | Object sprites (~7KB) — portals, cube, sentry, etc.  |
| 6    | 16,384 | Tile bitmaps (~3.7KB at MODE 2 4bpp)                 |
| 7    | 16,384 | Available — overflow sprites, future expansion        |

Sprite data is 4bpp (double MODE 5's 2bpp) but no masks needed, so net
size per sprite ≈ MODE 5 sprite+mask. Bank 4 fits all Chell frames.
Banks 5-6 have substantial free space.

---

## Audio Architecture

### Hardware

SN76489: 3 tone channels + 1 noise channel. Directly written via &FE41.
No MOS SOUND/OSWORD during gameplay — too slow and unpredictable.

### Engine location

The audio engine and data live in **main RAM** (always accessible
regardless of ACCCON X or ROMSEL state). This is critical because:
- IRQ handlers fire at arbitrary times
- X might be 0 or 1 when the interrupt occurs
- SWRAM bank selection is unknown during IRQs
- Main RAM (&0000-&2FFF) is the only memory guaranteed accessible

### Memory budget

| Range       | Size  | Purpose                                          |
|-------------|------:|--------------------------------------------------|
| &0E00-&0FFF |   512 | Music engine code (player, IRQ hook, steal logic) |
| &1000-&107F |   128 | Music engine state (channel ptrs, counters, etc.) |
| &1080-&10FF |   128 | SFX definitions (~16 effects × 8 bytes each)     |
| &1100-&14FF | 1,024 | Tune data (current tune, loaded from disc/SWRAM)  |
| &1500-&18FF | 1,024 | Available — longer tunes or additional SFX         |
| **Total**   |**2,816**| Post-boot reclaimable area                      |

### Playback model

- **Interrupt-driven at 50Hz** via vsync (Event or IRQ1 hook).
- Engine reads next note/rest from tune data, writes SN76489 registers.
- One byte per note: pitch index (0-63) + duration in upper bits.
  Exact encoding TBD — Galaforce-style single-byte format is proven.
- Three music voices, one per tone channel. Noise channel available for
  percussion or SFX.

### Dynamic channel stealing

When a sound effect fires, the engine temporarily reassigns one or more
tone channels from music to SFX:

```
Priority levels:
  0 = Music (default, lowest priority)
  1 = Ambient SFX (footsteps, button clicks) — steal channel 3
  2 = Action SFX (portal fire, cube pickup) — steal channel 3
  3 = Impact SFX (teleport whoosh, laser hit) — steal channels 2-3
  4 = Critical SFX (death, level complete) — steal all channels
```

**Steal mechanism:**
1. SFX call sets channel's owner to "SFX" with a duration counter.
2. IRQ handler checks each channel: if SFX-owned, play SFX data instead
   of music. Decrement duration.
3. When SFX duration expires, channel reverts to music. Music pointer is
   not rewound — it continues from where it would have been (engine
   advances music pointer even for stolen channels, just doesn't write
   the registers).
4. Music remains coherent because it keeps tracking time even on muted
   channels.

**Channel assignment:**
- Channels 1-2: Music (rarely stolen, only by priority 3-4)
- Channel 3: Music + primary SFX steal target
- Noise: SFX only (explosion rumble, laser buzz, fizzler hiss)

### Tune loading

Tunes are loaded from disc into the &1100-&14FF buffer at level-card
time (between levels). One tune in RAM at a time. The level pack or a
separate disc file contains tune data. Tunes loop until the level ends
or a new tune is loaded.

### SFX table format

Each SFX definition is 8 bytes:

| Offset | Purpose                                    |
|--------|--------------------------------------------|
| 0      | Priority (0-4)                             |
| 1      | Channel preference (1-3, or 0=noise)       |
| 2      | Duration (frames)                          |
| 3      | Initial pitch                              |
| 4      | Pitch delta per frame (signed)             |
| 5      | Initial volume (0-15)                      |
| 6      | Volume delta per frame (signed)            |
| 7      | Flags (loop, noise type, etc.)             |

This gives simple pitch-slide + volume-fade envelopes. Enough for
portal whooshes, laser buzzes, button clicks, and death jingles.

---

## DFS Disc Layout

Same structure as MODE 5 but with MODE 2 specific data files:

| File    | Size   | Purpose                              |
|---------|-------:|--------------------------------------|
| !Boot   |   ~50  | Auto-boot BASIC loader               |
| PROGRAM |  ~800  | BASIC boot loader                    |
| PORTHLE | ~22 KB | Main game binary                     |
| CHDATA  |  16 KB | Chell sprites — MODE 2 4bpp          |
| OBJDAT  |  16 KB | Object sprites — MODE 2 4bpp         |
| TILDAT  |  16 KB | Tile data — MODE 2 4bpp              |
| LOADSCR |  20 KB | Loading screen (MODE 2)              |
| LVLS01  |  ~5 KB | Level pack 1                         |
| LVLS02  |  ~5 KB | Level pack 2                         |
| MUSIC01 |  ~1 KB | Tune data pack 1                     |
| MUSIC02 |  ~1 KB | Tune data pack 2                     |

---

## Total Budget

| Region                    | Capacity | Used    | Free    |
|---------------------------|----------:|--------:|--------:|
| Zero page (&00-&8F)      |       144 |    ~115 |     ~29 |
| Main RAM (&1900-&7800)   |    24,320 | ~22,000 |  ~2,300 |
| Audio area (&0E00-&18FF) |     2,816 |  ~1,800 |  ~1,000 |
| LYNNE data (&3000-&3FFF) |     4,096 |  ~4,000 |    ~100 |
| LYNNE screen (&4000-&7FFF)|   16,384 |  16,384 |       0 |
| SWRAM Bank 4              |    16,384 | ~16,000 |    ~384 |
| SWRAM Bank 5              |    16,384 |  ~7,000 |  ~9,384 |
| SWRAM Bank 6              |    16,384 |  ~3,700 | ~12,684 |
| SWRAM Bank 7              |    16,384 |       0 |  16,384 |

---

## Key Differences from MODE 5

| Aspect              | MODE 5                    | MODE 2                        |
|---------------------|---------------------------|-------------------------------|
| Screen size         | 8KB (&5800-&77FF)         | 16KB (&4000-&7FFF)           |
| LYNNE data area     | 10KB (&3000-&57FF)        | 4KB (&3000-&3FFF)            |
| Render scratch      | 2KB (&7800-&7FFF)         | None needed                   |
| Bytes per pixel     | 2bpp (4px/byte)           | 4bpp (2px/byte)              |
| Bytes per scanline  | 32                        | 64                            |
| Cell row stride     | 512                       | 1,024                         |
| Sprite masks        | Required (AND+ORA)        | Not needed (ORA only)         |
| Background restore  | Save-under buffer         | AND #&F0                      |
| Colours             | 4                         | 16 (8 per nibble)            |
| Sprite SWRAM        | 2 banks (sprite+mask)     | 2 banks (sprite only, same size) |
| Audio               | None (planned)            | IRQ-driven + dynamic steal    |
