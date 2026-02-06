# PORTHOLE Memory Map

BBC Master 128. BeebAsm. Emulator: B2.

This is the authoritative reference for every usable byte.

---

## Current State

Shadow is **not active**. OSBYTE 114 does not set ACCCON shadow bits in
B2. Everything runs in main RAM. Screen at &5800-&7FFF leaves 571 bytes
free. LYNNE (20KB shadow RAM) is completely unused.

## Target State

Set ACCCON D+X manually. Screen moves to LYNNE. Main RAM &5800-&7FFF
freed for code. Toggle X between update (X=0, main RAM) and render
(X=1, LYNNE).

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
  [X=0]    JSR wait_vsync
  [X=0->1] LDA &FE34 : ORA #&04 : STA &FE34
  [X=1]    JSR render_frame_simple    ; screen writes hit LYNNE
  [X=1->0] LDA &FE34 : AND #&FB : STA &FE34
  [X=0]    JSR sample_keys
  [X=0]    JSR update_chell           ; physics, collision, game logic
  [X=0]    JMP main_loop
```

**Constraint:** when X=1, code at &3000-&7FFF reads from LYNNE, not main
RAM. Render-phase code must live below &3000.

---

## Zero Page (&00-&8F)

| Range   | Used | Free | Purpose                                          |
|---------|-----:|-----:|--------------------------------------------------|
| &00-&6F |   96 |   16 | Game state (pos, vel, flags, animation, portals)  |
| &70-&82 |   19 |    0 | Fixed pointers (screen_ptr@&71, tilemap_ptr@&79, portalmap_ptr@&7B) |
| &83-&8F |    0 |   13 | Available                                         |
| **Total** | **115** | **29** |                                           |
| &90-&FF |    — |    — | **RESERVED: MOS/VDU/Econet**                     |

Invariants enforced by `tools/check-build-invariants`:
- `screen_ptr` = &71
- `tilemap_ptr` = &79
- `portalmap_ptr` = &7B

---

## Main RAM (CPU view when X=0)

### Below &3000 — render-safe zone

This code executes during both update and render phases. When shadow is
enabled, render-phase subroutines must reside here (below &3000).

| Range       | Size  | Purpose                                         |
|-------------|------:|-------------------------------------------------|
| &0000-&00FF |   256 | Zero page                                       |
| &0100-&01FF |   256 | 6502 stack                                      |
| &0200-&08FF | 1,792 | MOS workspace                                   |
| &0900-&0DFF | 1,280 | Available (LYNNE access trampolines, buffers)    |
| &0E00-&18FF | 2,816 | Available (boot loader, reclaimable after boot)  |
| &1900-&2FFF | 5,888 | Code: render-safe zone (visible when X=0 or X=1)|

Reorder includes so render sections assemble into &1900-&2FFF.

| Section               | Current | Budget | Purpose                           |
|-----------------------|--------:|-------:|-----------------------------------|
| main.asm              |     567 |    768 | Init, main loop, render dispatch  |
| render.asm (blitters) |   1,650 |  1,792 | Blit, save/restore under, tilemap render |
| render_state.asm      |     283 |    512 | draw_character_current, draw_reticle_current |
| room_runtime.asm      |     168 |    256 | update_screen_ptr_from_char/reticle |
| debug.asm             |     196 |    256 | Debug box drawing (render-time)   |
| Trampoline code       |       0 |    128 | LYNNE data access helpers         |
| **Total**             | **2,864** | **3,712** |                              |
| **Remaining**         |         | **2,176** | Reserve for render growth     |

### Above &3000 — update-only zone

Game logic, physics, data. Not accessible during render phase.

| Section                    | Current | Budget | Purpose                           |
|----------------------------|--------:|-------:|-----------------------------------|
| portal_teleport.asm        |   1,349 |  1,536 | Portal entry detection, teleport  |
| room_exits.asm             |     627 |    768 | Room/screen transitions           |
| reticle.asm                |   1,565 |  1,792 | Reticle movement, LOS, validation |
| input.asm                  |     265 |    512 | Keyboard sampling                 |
| portal_place.asm           |   1,089 |  1,280 | Portal placement logic            |
| frame_update.asm           |     793 |  1,024 | Per-frame update orchestration    |
| persistent_objects.asm     |   1,448 |  1,664 | Buttons, pads, exits, cubes       |
| ui.asm                     |      86 |    256 | Cursor disable, palette           |
| loaders.asm                |     768 |  1,024 | Shadow enable, SWRAM file I/O     |
| timing.asm                 |      21 |     64 | VSync wait                        |
| movement.asm               |     789 |  1,024 | Walk, jump, collision, gravity    |
| sprites.asm                |     294 |    512 | Sprite pointer tables             |
| masks.asm                  |     294 |    512 | Mask pointer tables               |
| tilemap.asm                |   1,117 |  1,280 | Room tilemaps, exits, object defs |
| lookup_tables.asm          |      48 |    128 | times16 table                     |
| persistent_objects_data.asm|     304 |    768 | Object arrays, solid_phys_plane, SOLID_TILE_PLANE |
| generated_tiles.asm        |   1,836 |      — | Tile pixel data **(→ SWRAM bank 6)** |
| **Subtotal**               |**12,693**|**14,144**|                                |
| **After tile relocation**  |**10,857**|**14,144**| Tiles move to SWRAM bank 6    |

**New feature budget (main RAM above existing code, up to &7FFF):**

Update-only zone capacity with shadow: 20,480 bytes (&3000-&7FFF).
After tile relocation and existing budgets: 20,480 − 14,144 = **6,336** free.

| Feature              | Budget | Notes                                     |
|----------------------|-------:|-------------------------------------------|
| Laser system         |  2,560 | Beam tracing on tile grid, portal redirection, crossroads tiles, signal driving to targets |
| Fizzler logic        |    512 | Region check: clear portals, drop cube, block LOS |
| Acid/hazard          |    512 | Fatal surface, death + level reset trigger |
| Sound engine         |  1,536 | Playback, channel mixing, event triggers  |
| Cube portal physics  |    512 | Cubes falling through portals autonomously |
| Growth reserve       |    704 | Headroom for existing sections            |
| **Total new**        | **6,336** |                                        |

### Main RAM summary

```
Render-safe zone (&1900-&2FFF):    5,888 bytes available
  Current:   2,864    Budgeted: 3,712    Free: 2,176

Update-only zone (&3000-&7FFF):   20,480 bytes available (with shadow)
  Current:  10,857    Budgeted: 14,144   Free for new features: 6,336
  (Before tile relocation: 12,693 current)

Total main RAM (&1900-&7FFF):     26,368 bytes
  Current:  13,721    Free: 12,647
  (Before tile relocation: 15,557 current, 10,811 free)
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
| &78C0-&79FF   |  320 | Free (render list constants are dead code)    |
| &7A00-&7AFF   |  256 | Free (SOLID_TILE_PLANE moves to main RAM)     |
| &7B00-&7FFF   | 1,280| Free (CHELLDATA_BUF is boot-only, portal snap is dead code) |
| **Total scratch** | **2,048** |                                          |
| **Used**      |  192 | Save-under buffers only                       |
| **Free**      | 1,856| Available for render-phase scratch            |

### Data area (&3000-&57FF)

10,240 bytes. Accessed by setting X=1 from trampoline code below &3000.
Written at init or room-load time. Read during render (X=1) or via
trampoline during update.

| Address       | Size  | Budget | Purpose                              |
|---------------|------:|-------:|--------------------------------------|
| &3000-&37FF   | 2,048 |  2,048 | Level tilemap data (rooms 0-3)       |
| &3800-&3FFF   | 2,048 |  2,048 | Portal layers + exit tables          |
| &4000-&47FF   | 2,048 |  2,048 | Sound effect sample data             |
| &4800-&4FFF   | 2,048 |  2,048 | Precomputed render lookup tables     |
| &5000-&57FF   | 2,048 |  2,048 | Future rooms / additional level data |
| **Total**     |**10,240**|**10,240**|                                  |

---

## SWRAM (&8000-&BFFF, paged via ROMSEL)

Only one SWRAM bank maps to &8000-&BFFF at a time. No executable code
in SWRAM — bank switching during rendering conflicts with sprite data
access.

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
| **Free**                | **9,600** | Additional object sprites (fizzler, laser, acid) |

### Bank 6 — tileset data

Tile pixel bitmaps. Currently 54 tiles (1,836 bytes) in main RAM — moving
here frees 1,836 bytes of main RAM and allows growth to 16KB (up to ~480
tiles). Paged in briefly during tilemap rendering, then paged back to
bank 4/5 for sprite blitting.

| Allocation              | Size  | Notes                               |
|-------------------------|------:|-------------------------------------|
| Tile bitmaps (current)  | 1,836 | 54 tiles × 34 bytes each            |
| **Free**                |**14,548**| Room for ~428 additional tiles    |

### Bank 7 — available

16,384 bytes. Potential uses: additional level data, music data, level
streaming buffers.

---

## Collision Planes

| Plane            | Size | Location           | Rebuilt            | Used by                  |
|------------------|-----:|--------------------|--------------------|--------------------------|
| SOLID_TILE_PLANE |  256 | Main RAM (data section) | Init + room change | LOS, portal validation  |
| solid_phys_plane |  256 | Main RAM (data section) | Every frame        | Movement collision      |

Both are needed: portals/LOS must ignore cubes; collision must not.
solid_phys_plane copies SOLID_TILE_PLANE then stamps cube positions.

With shadow enabled, both live in main RAM (accessible during update,
X=0). SOLID_TILE_PLANE moves from its current &7A00 address into the
persistent_objects_data section.

---

## Boot Loader (PROGRAM, &0E00-&18FF)

Separate binary assembled at &0E00. Loads LOADSCR, OBJDAT, CHDATA,
PORTHLE, then jumps to game. Memory is reclaimable after boot.

| Range       | Size  | Post-boot use                              |
|-------------|------:|--------------------------------------------|
| &0900-&0DFF | 1,280 | LYNNE access trampolines, staging buffers  |
| &0E00-&18FF | 2,816 | General-purpose buffers, decompression workspace |
| **Total**   | **4,096** |                                        |

---

## Total Budget

| Region                    | Capacity | Allocated | Free    |
|---------------------------|----------:|----------:|--------:|
| Zero page (&00-&8F)      |       144 |       115 |      29 |
| Main RAM (&1900-&7FFF)   |    26,368 |    13,721 |  12,647 |
| LYNNE (&3000-&7FFF)      |    20,480 |     8,384 |  12,096 |
| SWRAM Bank 4              |    16,384 |   ~16,000 |    ~384 |
| SWRAM Bank 5              |    16,384 |     6,784 |   9,600 |
| SWRAM Bank 6              |    16,384 |     1,836 |  14,548 |
| SWRAM Bank 7              |    16,384 |         0 |  16,384 |
| Reclaimable (&0900-&18FF) |     4,096 |         0 |   4,096 |
| **Total**                 |**116,624**| **46,840**|**69,784**|

Without shadow: main RAM free = 571 bytes.
With shadow + tile relocation: main RAM free = 12,647 bytes. Plus 12,096
LYNNE + 9,600 bank 5 + 14,548 bank 6 + 16,384 bank 7 = **65,275 bytes**
of usable space.

---

## Implementation Steps

1. **Enable shadow** — write ACCCON D=1, X=1 in init; verify CRTC
   displays LYNNE in B2
2. **Add X toggle** — X=1 before render, X=0 after, in main loop
3. **Relocate render code** — reorder includes so blitters + screen-write
   routines assemble below &3000
4. **Move tiles to SWRAM bank 6** — update build to load tile data into
   bank 6, add bank-switching in tilemap renderer
5. **Move SOLID_TILE_PLANE** — from &7A00 into main RAM data section
6. **Remove dead buffers** — render list (&78C0), portal snap (&7FF0),
   CHELLDATA_BUF (&7B00) constants
7. **Raise code ceiling** — build checks from &5800 to &7FFF
8. **Per-section budgets** — add to `tools/check-build-invariants`
9. **Test SWRAM banks 6-7** — verify writable in B2
10. **Populate LYNNE** — move level data into &3000-&57FF
