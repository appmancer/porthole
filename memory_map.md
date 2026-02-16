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

Code blob: &1900..&744F (23,375 bytes). Ceiling &7800. Headroom 945 bytes.

Note: headroom is temporarily tight because 5 inline levels are padded
to MAX_ROOMS=8 rooms each. Once levels move to disc packs (scaling plan
steps 4-8), all inline level data is removed and ~3 KB is recovered.

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
| &83-&8F |    0 |   13 | Available                                         |
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
| &0900-&0DFF | 1,280 | Available (trampolines, buffers)                |
| &0E00-&18FF | 2,816 | Available (boot loader, reclaimable after boot)  |
| &1900-&2FFF | 5,888 | Code: render-safe zone (visible when X=0 or X=1)|

| Section               | Start  | End    | Used  | Budget | Purpose                           |
|-----------------------|--------|--------|------:|-------:|-----------------------------------|
| main.asm              | &1900  | &1BD3  |   723 |    850 | Init, main loop, render dispatch  |
| render.asm            | &1BD3  | &234B  | 1,912 |  1,952 | Blit, save/restore, tilemap render |
| render_state.asm      | &234B  | &247D  |   306 |    512 | draw_character_current, draw_reticle_current |
| room_runtime.asm      | &247D  | &252C  |   175 |    256 | update_screen_ptr_from_char/reticle |
| debug.asm             | &252C  | &25FA  |   206 |    256 | Debug box drawing                 |
| lookup_tables.asm     | &25FA  | &262A  |    48 |    128 | times16_table                     |
| sprites.asm           | &262A  | &2752  |   296 |    512 | Sprite pointer tables             |
| masks.asm             | &2752  | &287A  |   296 |    512 | Mask pointer tables               |
| **Total**             |        |        |**3,962**|**4,978**|                                |
| **Remaining**         |        |        |       |**2,016**| Reserve for render growth       |

### Above render-safe zone — update-only code

Game logic, physics, data. Runs only with X=0. Can extend up to &7800.

| Section                    | Start  | End    | Used  | Budget | Purpose                           |
|----------------------------|--------|--------|------:|-------:|-----------------------------------|
| portal_teleport.asm        | &287A  | &2DCB  | 1,361 |  1,536 | Portal entry detection, teleport  |
| room_exits.asm             | &2DCB  | &307C  |   689 |    768 | Room/screen transitions           |
| reticle.asm                | &307C  | &3697  | 1,563 |  1,792 | Reticle movement, LOS, validation |
| input.asm                  | &3697  | &37A0  |   265 |    512 | Keyboard sampling                 |
| portal_place.asm           | &37A0  | &3C9E  | 1,278 |  1,280 | Portal placement logic            |
| frame_update.asm           | &3C9E  | &40EE  | 1,104 |  1,152 | Per-frame update orchestration    |
| persistent_objects.asm     | &40EE  | &4B44  | 2,646 |  2,688 | Buttons, pads, exits, cubes       |
| ui.asm                     | &4B44  | &4B9A  |    86 |    256 | Cursor disable, palette           |
| screens.asm                | &4B9A  | &537B  | 2,017 |  2,048 | Level cards, MODE 7 overlays      |
| loaders.asm                | &537B  | &567F  |   772 |  1,024 | Shadow enable, SWRAM file I/O     |
| timing.asm                 | &567F  | &5694  |    21 |     64 | VSync wait                        |
| movement.asm               | &5694  | &59F2  |   862 |  1,024 | Walk, jump, collision, gravity    |
| laser.asm                  | &59F2  | &5E69  | 1,143 |  1,280 | Beam tracing, signal driving      |
| tilemap.asm                | &5E69  | &719D  | 4,916 |  5,792 | Level data, tilemap buffers, load |
| objects.asm                | &719D  | &71B9  |    28 |    512 | Static object tables              |
| persistent_objects_data.asm| &71B9  | &744F  |   662 |    768 | Object arrays, collision planes   |
| **Total**                  |        |        |**19,413**|**23,496**|                              |

**Free space above code (up to &7800 ceiling):** 945 bytes.

Note: ~3 KB of this is inline level data padded to MAX_ROOMS=8. When
levels move to disc packs (scaling plan steps 4-8), this space is
recovered.

### New feature budget

| Feature              | Budget | Notes                                     |
|----------------------|-------:|-------------------------------------------|
| Sentry system        |  ~512  | AI, collision, rendering                  |
| Sound engine         |  ~256  | Playback stubs (samples in SWRAM)         |
| Growth reserve       |  ~177  | Headroom for existing sections            |
| **Total available**  |  **945**| Tight until inline levels move to disc  |

### Main RAM summary

```
Render-safe zone (&1900-&287A):   3,962 bytes used of 5,888 available
  Free: 2,016

Update-only zone (&287A-&744F):  19,413 bytes used
  Ceiling: &7800    Free to ceiling: 945

Total code blob (&1900-&744F):   23,375 bytes
Total main RAM (&1900-&7800):    24,320 bytes capacity
  Free: 945

Note: ~3 KB is inline level data (5 levels x 8-room padding).
Once levels move to disc packs, headroom recovers to ~4 KB.
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
| &78C0-&7FFF   | 1,856| Free render-phase scratch                     |
| **Total**     | **2,048** |                                          |
| **Used**      |  192 | Save-under buffers only                       |
| **Free**      | 1,856| Available for render-phase scratch            |

Note: &7B00 (`CHELLDATA_BUF`) is used during boot as a SWRAM streaming
buffer. After boot it is free.

### Data area (&3000-&57FF)

10,240 bytes. Currently unused. Accessed by setting X=1 from code below
&3000. Written at init or room-load time.

| Address       | Size  | Purpose (planned)                            |
|---------------|------:|----------------------------------------------|
| &3000-&37FF   | 2,048 | Level tilemap data (rooms 0-3)               |
| &3800-&3FFF   | 2,048 | Portal layers + exit tables                  |
| &4000-&47FF   | 2,048 | Sound effect sample data                     |
| &4800-&4FFF   | 2,048 | Precomputed render lookup tables             |
| &5000-&57FF   | 2,048 | Future rooms / additional level data         |
| **Total**     |**10,240**|                                            |

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
| 7    |       0 |  16,384 | Available (untested)                        |

### Bank 5 — object sprites

| Allocation              | Size  | Notes                               |
|-------------------------|------:|-------------------------------------|
| Portal sprites + cube   | 6,784 | Vertical, horizontal, back portals + cube |
| **Free**                | **9,600** | Additional object sprites (fizzler, laser, acid) |

### Bank 6 — tileset data

Tile pixel bitmaps. 54 tiles (1,836 bytes). Paged in during tilemap
rendering (`render_cell8x16`), then paged back for sprite blitting.
Capacity for ~480 tiles (16KB).

| Allocation              | Size  | Notes                               |
|-------------------------|------:|-------------------------------------|
| Tile bitmaps            | 1,836 | 54 tiles x 34 bytes each            |
| **Free**                |**14,548**| Room for ~428 additional tiles    |

### Bank 7 — available

16,384 bytes. Potential uses: additional level data, music data, level
streaming buffers. Not yet tested in B2.

---

## Collision Planes

| Plane            | Size | Location                       | Rebuilt            | Used by                  |
|------------------|-----:|--------------------------------|--------------------|--------------------------|
| solid_tile_plane |  256 | persistent_objects_data.asm     | Init + room change | LOS, portal validation  |
| solid_phys_plane |  256 | persistent_objects_data.asm     | Every frame        | Movement collision      |

Both are needed: portals/LOS must ignore cubes; collision must not.
`solid_phys_plane` copies `solid_tile_plane` then stamps cube positions.

---

## Boot Loader (PROGRAM, &0E00-&18FF)

Separate binary assembled at &0E00. Loads LOADSCR, OBJDAT, CHDATA,
TILDAT, PORTHLE, then jumps to game. Memory is reclaimable after boot.

| Range       | Size  | Post-boot use                              |
|-------------|------:|--------------------------------------------|
| &0900-&0DFF | 1,280 | Trampolines, staging buffers               |
| &0E00-&18FF | 2,816 | General-purpose buffers, decompression workspace |
| **Total**   | **4,096** |                                        |

---

## Total Budget

| Region                    | Capacity | Used    | Free    |
|---------------------------|----------:|--------:|--------:|
| Zero page (&00-&8F)      |       144 |     115 |      29 |
| Main RAM (&1900-&7800)   |    24,320 |  23,375 |     945 |
| LYNNE (&3000-&7FFF)      |    20,480 |   8,384 |  12,096 |
| SWRAM Bank 4              |    16,384 | ~16,000 |    ~384 |
| SWRAM Bank 5              |    16,384 |   6,784 |   9,600 |
| SWRAM Bank 6              |    16,384 |   1,836 |  14,548 |
| SWRAM Bank 7              |    16,384 |       0 |  16,384 |
| Reclaimable (&0900-&18FF) |     4,096 |       0 |   4,096 |
| **Total**                 |**114,576**|**56,494**|**58,082**|

Main RAM free: 945 bytes (temporarily tight — inline level data pads to
MAX_ROOMS=8). Plus 12,096 LYNNE + 9,600 bank 5 + 14,548 bank 6 +
16,384 bank 7 = **52,628 bytes** of usable non-main-RAM space.
