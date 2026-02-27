# PORTHOLE Memory Map

BBC Master 128. BeebAsm. Emulator: B2.

This is the authoritative reference for every usable byte.

---

## Current State

Shadow is **active**. ACCCON D=1 (CRTC displays LYNNE). X is toggled
per-blitter: each screen-writing function sets X=1 around its inner loops
and restores X=0 before returning. All orchestration code runs with X=0.

Tiles are in SWRAM bank 6. Both collision planes (`solid_tile_plane`,
`solid_phys_plane`) are labeled allocations in `persistent_objects_data.asm`.

Code blob: &1900..&6F78 (22,136 bytes). Ceiling &7800. Headroom 2,184 bytes.

Level data is loaded from disc packs into LYNNE at &3000. The staging
buffer at &0E00 is used for decompression at room-load time.

---

## ACCCON (&FE34)

```
Bit 7: IRR  — Interrupt request
Bit 6: TST  — Test mode
Bit 5: IFJ  — 1MHz bus / cartridge
Bit 4: ITU  — Internal/external Tube
Bit 3: Y    — HAZEL (&C000-&DFFF)
Bit 2: X    — CPU accesses LYNNE at &3000-&7FFF (unconditional)
Bit 1: E    — VDU driver conditional shadow access (opcode-address gated)
Bit 0: D    — CRTC displays LYNNE
```

Toggle X without disturbing other bits:
```asm
LDA &FE34 : ORA #&04 : STA &FE34   ; X=1, CPU sees LYNNE
LDA &FE34 : AND #&FB : STA &FE34   ; X=0, CPU sees main RAM
```

Source: BBC Master Series Service Manual, ACCCON section.

---

## Frame Pipeline

```
MAIN LOOP:
  [X=0]  JSR wait_vsync
  [X=0]  JSR render_frame_simple    ; blitters toggle X=1 internally
  [X=0]  JSR sample_keys
  [X=0]  JSR update_chell           ; physics, collision, game logic
  [X=0]  JMP main_loop
```

X toggling is **per-blitter**, not main-loop level. Each blitter function
in render.asm sets X=1 before screen access loops and clears X=0 before
returning. This avoids needing all render-phase orchestration code below
&3000 — only the blitter inner loops themselves need to be there.

**Constraint:** when X=1, code at &3000-&7FFF reads from LYNNE, not main
RAM. Blitter code (which runs with X=1) must live below &3000.

---

## Zero Page (&00-&8F)

| Range   | Used | Free | Purpose                                          |
|---------|-----:|-----:|--------------------------------------------------|
| &00-&6F |   96 |   16 | Game state (pos, vel, flags, animation, portals)  |
| &70-&82 |   19 |    0 | Fixed pointers (screen_ptr@&71, tilemap_ptr@&79, mask_ptr@&7B) |
| &83-&8F |    0 |   13 | Available — turrets need ~4 ZP bytes              |
| **Total** | **115** | **29** |                                           |
| &90-&FF |    — |    — | **RESERVED: MOS/VDU/Econet**                     |

Invariants enforced by `tools/check-build-invariants`:
- `screen_ptr` = &71
- `tilemap_ptr` = &79

---

## Main RAM (CPU view when X=0)

### Below &3000 — render-safe zone

Blitter code that runs with X=1 must reside here. Other code in this zone
also works fine — it just isn't required to be here.

| Range       | Size  | Purpose                                         |
|-------------|------:|-------------------------------------------------|
| &0000-&00FF |   256 | Zero page                                       |
| &0100-&01FF |   256 | 6502 stack                                      |
| &0200-&08FF | 1,792 | MOS workspace                                   |
| &0900-&09DF |   224 | Trampoline code + OSFILE block + filename       |
| &09E0-&0CFF |   800 | Available (below DFS NMI handler)                |
| &0D00-&0DFF |   256 | DFS NMI handler — **do not overwrite**           |
| &0E00-&18FF | 2,816 | Staging buffer + free (boot loader, reclaimable) |
| &1900-&2FFF | 5,888 | Code: render-safe zone (visible when X=0 or X=1)|

| Section               | Start  | End    | Used  | Budget | Purpose                           |
|-----------------------|--------|--------|------:|-------:|-----------------------------------|
| main.asm              | &1900  | &1BDB  |   731 |    850 | Init, main loop, render dispatch  |
| render.asm            | &1BDB  | &2385  | 1,962 |  2,000 | Blit, save/restore, tilemap render, turret beam blit |
| render_state.asm      | &2385  | &24B7  |   306 |    512 | draw_character_current, draw_reticle_current |
| room_runtime.asm      | &24B7  | &2566  |   175 |    256 | update_screen_ptr_from_char/reticle |
| debug.asm             | &2566  | &2634  |   206 |    256 | Debug box drawing                 |
| lookup_tables.asm     | &2634  | &2664  |    48 |    128 | times16_table                     |
| sprites.asm           | &2664  | &278C  |   296 |    512 | Sprite pointer tables             |
| masks.asm             | &278C  | &28B4  |   296 |    512 | Mask pointer tables               |

### Above render-safe zone — update-only code

Game logic, physics, data. Runs only with X=0. Can extend up to &7800.

| Section                    | Start  | End    | Used  | Budget | Purpose                           |
|----------------------------|--------|--------|------:|-------:|-----------------------------------|
| portal_teleport.asm        | &28B4  | &2E05  | 1,361 |  1,536 | Portal entry detection, teleport  |
| room_exits.asm             | &2E05  | &30B6  |   689 |    768 | Room/screen transitions           |
| reticle.asm                | &30B6  | &36D1  | 1,563 |  1,792 | Reticle movement, LOS, validation |
| input.asm                  | &36D1  | &37DA  |   265 |    512 | Keyboard sampling                 |
| portal_place.asm           | &37DA  | &3CD8  | 1,278 |  1,280 | Portal placement logic            |
| frame_update.asm           | &3CD8  | &4128  | 1,104 |  1,152 | Per-frame update orchestration    |
| persistent_objects.asm     | &4128  | &4BBD  | 2,709 |  3,264 | Buttons, pads, exits, cubes, **turrets** |
| ui.asm                     | &4BBD  | &4C13  |    86 |    256 | Cursor disable, palette           |
| **sound.asm (planned)**    |   —    |   —    |     0 |    384 | SN76489 direct writes, effect envelopes |
| screens.asm                | &4C13  | &5516  | 2,307 |  2,560 | Level cards (MODE 5), MODE 7 overlays |
| loaders.asm                | &5516  | &58AF  |   921 |  1,152 | Shadow enable, SWRAM file I/O, **multi-pack** |
| timing.asm                 | &58AF  | &58C4  |    21 |     64 | VSync wait                        |
| movement.asm               | &58C4  | &5C32  |   878 |  1,024 | Walk, jump, collision, gravity    |
| laser.asm                  | &5C32  | &60A9  | 1,143 |  1,280 | Beam tracing, signal driving      |
| tilemap.asm                | &60A9  | &6CC6  | 3,101 |  5,792 | Level data, tilemap buffers, load |
| objects.asm                | &6CC6  | &6CE2  |    28 |    512 | Static object tables              |
| persistent_obj_data.asm    | &6CE2  | &6F78  |   662 |  1,152 | Object arrays, collision planes, **turret state** |

### New feature budget

| Feature                   | Budget | Where                         | Notes                                       |
|---------------------------|-------:|-------------------------------|---------------------------------------------|
| Turret logic              |   ~400 | persistent_objects (+555)      | AI, carry, disable, collision               |
| Turret state arrays       |   ~100 | persistent_obj_data (+490)     | pos, room, status, orientation per turret   |
| Turret beam blit          |   ~150 | render.asm (+38 free)          | Save-under / draw / restore (below &3000)   |
| Sound engine              |   ~300 | sound.asm (new, budget 384)    | SN76489 direct writes, envelope tables      |
| Multi-pack loader         |   ~100 | loaders.asm (+231 free)        | Pack index mapping, auto-load on advance    |
| Growth reserve            |   ~500 | Distributed                    | Headroom for existing sections              |
| **Total reserved**        |**~1,550**|                              |                                             |
| **Headroom after reserve**|  **634**| Of 2,184 current free         |                                             |

### Main RAM summary

```
Render-safe zone (&1900-&28B4):   4,020 bytes used of 5,812 available
  Free: 1,792

Update-only zone (&28B4-&6F78):  18,116 bytes used
  Ceiling: &7800    Free to ceiling: 2,184

Total code blob (&1900-&6F78):    22,136 bytes
Total main RAM (&1900-&7800):     24,320 bytes capacity
  Free: 2,184
```

---

## LYNNE / Shadow RAM (CPU view when X=1)

Visible at &3000-&7FFF when ACCCON X=1. CRTC displays this when D=1.

### Screen (&5800-&77FF)

| Address       | Size  | Purpose                                      |
|---------------|------:|----------------------------------------------|
| &5800-&77FF   | 8,192 | MODE 5 framebuffer (visible playfield)       |

### Render scratch (&7800-&7FFF)

| Address       | Size | Purpose                                       |
|---------------|-----:|-----------------------------------------------|
| &7800-&787F   |  128 | Chell save-under buffer                       |
| &7880-&78BF   |   64 | Reticle save-under buffer                     |
| &78C0-&797F   |  192 | **Turret beam save-under (4 turrets x 32+16 bytes)** |
| &7980-&7FFF   | 1,664| Free render-phase scratch                     |
| **Total**     | **2,048** |                                          |
| **Used**      |  384 | Save-under buffers (Chell + reticle + turrets)|
| **Free**      | 1,664| Available for render-phase scratch            |

Turret beam save-under: each turret saves one scanline (up to 32 bytes)
plus 16 bytes of metadata (start col, length, screen row address). 4
turrets max = 192 bytes. Beams are always horizontal, 1px tall, so
save/draw/restore is a simple contiguous byte copy.

Note: &7B00 (`CHELLDATA_BUF`) is used during boot as a SWRAM streaming
buffer. After boot it is free.

### Data area (&3000-&57FF)

10,240 bytes. Accessed by setting X=1 from code below &3000. Written at
init or room-load time.

| Address       | Size  | Purpose                                      |
|---------------|------:|----------------------------------------------|
| &3000-&47FF   | 6,144 | Level pack data (loaded from disc)           |
| &4800-&4FFF   | 2,048 | Available (future level packs / lookup tables)|
| &5000-&57FF   | 2,048 | Available                                    |
| **Total**     |**10,240**|                                            |

Level packs: with 4-5 levels per pack at ~1000 bytes each, a pack is
~4-5 KB. 6,144 bytes at &3000 comfortably fits any single pack. Packs
are swapped on level advance when crossing a pack boundary.

---

## SWRAM (&8000-&BFFF, paged via ROMSEL)

Only one SWRAM bank maps to &8000-&BFFF at a time. No executable code
in SWRAM — bank switching during rendering conflicts with sprite data
access. Always write &F4 before &FE30; use SEI around bank switches.

| Bank | Used    | Free    | Purpose                                     |
|------|--------:|--------:|---------------------------------------------|
| 4    | ~16,000 |    ~384 | Chell sprite+mask bitmaps (CHDATA)          |
| 5    |   6,784 |   9,600 | Object sprite+mask bitmaps (OBJDAT)         |
| 6    |   1,836 |  14,548 | Tileset data (tile pixel bitmaps)           |
| 7    |       0 |  16,384 | Available                                   |

### Bank 5 — object sprites

| Allocation              | Size  | Notes                               |
|-------------------------|------:|-------------------------------------|
| Portal sprites + cube   | 6,784 | Vertical, horizontal, back portals + cube |
| **Turret sprites (planned)** | **~420** | 6 frames x ~70 bytes (idle, fire, knocked) |
| **Free**                | **~9,180** | Additional object sprites        |

### Bank 6 — tileset data

Tile pixel bitmaps. 54 tiles (1,836 bytes). Paged in during tilemap
rendering (`render_cell8x16`), then paged back for sprite blitting.
Capacity for ~480 tiles (16KB).

| Allocation              | Size  | Notes                               |
|-------------------------|------:|-------------------------------------|
| Tile bitmaps            | 1,836 | 54 tiles x 34 bytes each            |
| **Free**                |**14,548**| Room for ~428 additional tiles    |

### Bank 7 — available

16,384 bytes. Potential uses:
- Additional level pack cache (preload next pack while current plays)
- Music / sound data
- Extended sprite data if bank 5 fills up

---

## Collision Planes

| Plane            | Size | Location                       | Rebuilt            | Used by                  |
|------------------|-----:|--------------------------------|--------------------|--------------------------|
| solid_tile_plane |  256 | persistent_objects_data.asm     | Init + room change | LOS, portal validation  |
| solid_phys_plane |  256 | persistent_objects_data.asm     | Every frame        | Movement collision      |

Both are needed: portals/LOS must ignore cubes; collision must not.
`solid_phys_plane` copies `solid_tile_plane` then stamps cube positions.

Turrets will also stamp into `solid_phys_plane` (they block movement)
but NOT `solid_tile_plane` (portals can pass over them, like cubes).

---

## Boot Loader (PROGRAM, &0E00-&18FF)

Separate binary assembled at &0E00. Loads LOADSCR, OBJDAT, CHDATA,
TILDAT, PORTHLE, then jumps to game. Memory is reclaimable after boot.

| Range       | Size  | Post-boot use                              |
|-------------|------:|--------------------------------------------|
| &0900-&0DFF | 1,280 | Trampolines, staging buffers               |
| &0E00-&18FF | 2,816 | Staging buffer (STAGING_BUF at &0E00)      |
| **Total**   | **4,096** |                                        |

---

## DFS Disc Layout

DFS limit: 31 catalogue entries. Current usage:

| File    | Size   | Purpose                              |
|---------|-------:|--------------------------------------|
| !Boot   |   ~50  | Auto-boot BASIC loader               |
| PROGRAM |  ~800  | BASIC boot loader                    |
| PORTHLE | ~22 KB | Main game binary                     |
| CHDATA  |  16 KB | Chell sprites (SWRAM bank 4)         |
| OBJDAT  |  16 KB | Object sprites (SWRAM bank 5)        |
| TILDAT  |  16 KB | Tile data (SWRAM bank 6)             |
| LOADSCR |  20 KB | Loading screen (MODE 2)              |
| STRTSCR |  1 KB  | Start screen (MODE 7)                |
| TEMPLTE |  1 KB  | Level card template (MODE 7, legacy) |
| APLOGO  |  ~2 KB | Aperture logo (MODE 5)               |
| LVLS01  |  ~4 KB | Level pack 1 (levels 1-5)            |
| LVLS02  |  ~4 KB | Level pack 2 (levels 6-10)           |
| LVLS03  |  ~4 KB | Level pack 3 (levels 11-15)          |
| LVLS04  |  ~4 KB | Level pack 4 (levels 16-20)          |
| **Total** | **14 files** | 17 remaining catalogue slots  |

With 20 levels in 4 packs of 5, we use 14 DFS entries — well within the
31-slot limit. Room for additional data files if needed.

---

## Planned Features — Resource Summary

### Turret sentries

- **Logic**: ~400 bytes in persistent_objects.asm. Modelled on cube
  carry/drop mechanics plus firing AI. Turret fires horizontally when
  Chell is in the same tile row and LOS is clear (no solid tiles or
  cubes blocking). Carrying disables. Cube drop knocks over permanently.
- **Beam rendering**: ~150 bytes in render.asm (below &3000). Save-under
  of one scanline (up to 32 bytes), overdraw red then yellow pixels,
  restore on cease-fire. Buffer in LYNNE scratch at &78C0.
- **State**: ~100 bytes in persistent_obj_data.asm. Per-turret: tile pos,
  room, orientation (L/R), status (active/disabled/carried/knocked).
  Max 4 turrets per level.
- **Sprites**: ~420 bytes in SWRAM bank 5. Idle, firing, knocked-over
  frames (left/right mirrored).
- **ZP**: ~4 bytes in &83-&8F range for turret processing temporaries.

### Sound engine

- **Engine**: ~300 bytes in new sound.asm section. Direct SN76489 writes
  via &FE41. Simple envelope state machine called once per frame from
  the main loop. No MOS SOUND interaction during gameplay.
- **Effect tables**: ~80 bytes inline. Pitch/volume/duration for each
  effect (portal fire, placement, cube pickup, turret fire, death, etc.).
- **Card/menu sounds**: Continue using OSWORD &07 where timing isn't
  critical (typewriter tick, etc.).

### GLaDOS boss fight (final level)

- Uses existing mechanics: portals, turrets, lasers, cubes, acid bath.
- Scripted sequence: redirect turret fire at GLaDOS target via portals.
  GLaDOS disables turrets after a few seconds (scripted timer).
  Multiple phases. Final phase: portal GLaDOS core into acid.
- GLaDOS sprite: ~200 bytes in SWRAM bank 5 (static target graphic).
- Script data: ~100 bytes in level pack (special object type or metadata).
- No new engine mechanics required — purely level design + scripting.

---

## Total Budget

| Region                    | Capacity | Used    | Free    |
|---------------------------|----------:|--------:|--------:|
| Zero page (&00-&8F)      |       144 |     115 |      29 |
| Main RAM (&1900-&7800)   |    24,320 |  22,136 |   2,184 |
| LYNNE (&3000-&7FFF)      |    20,480 |   8,384 |  12,096 |
| SWRAM Bank 4              |    16,384 | ~16,000 |    ~384 |
| SWRAM Bank 5              |    16,384 |   6,784 |   9,600 |
| SWRAM Bank 6              |    16,384 |   1,836 |  14,548 |
| SWRAM Bank 7              |    16,384 |       0 |  16,384 |
| Reclaimable (&0900-&18FF) |     4,096 |       0 |   4,096 |
| **Total**                 |**114,576**|**55,255**|**59,321**|

Main RAM after planned reservations: ~634 bytes headroom. Comfortable
with room for iteration. LYNNE + SWRAM provide >50 KB for data growth.
