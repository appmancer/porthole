# Spycat (Disc041 / Play It Again Sam) reverse-engineering notes

Repo: `battlefield6502`  
Work area: `.tmp/spycat_extracted/disc041/`  
Emulator tooling: `./tools/b2-*` against B2 instance `b2`

## Extracted DFS contents (Disc041)
Extracted files under `.tmp/spycat_extracted/disc041/` include:
- `SPYLDR` (loader) load/exec `&08C0`
- `SPYGAME` (main game code) load `&1100`
- `SPYdata` load `&0400` (only 1024 bytes)
- `SPYP2` loaded into `&6900..&7FFF` (contains map data at high end)
- `SPYP3` loaded at `&5800`
- `SCRN` (screen) is loaded/decompressed into `&5800`

## Loader chain and entry points
From `SPYLDR`:
- Contains embedded `*LOAD` strings, including:
  - `*LOAD SPYGAME 1100`
  - `*LOAD SPYDATA 400`
  - `*LOAD SCRN`
  - `*LOAD SPYP2`
  - `*LOAD SPYP3`
- Final handoff jumps to `&2AD8`

Runtime entry points observed:
- `&2AD8` begins with `JMP &211B` (init)
- `SPYGAME` at `&1100` begins with:
  - `JMP &23CC`
  - `JMP &271E`
  - …then the screen pointer routine at `&1106`

## Map table and tile/state variable
- `$68` is the “current tile/state code” used by the main loop.
- `$68` is loaded from a 16×16 map at `&7E80`:
  - `LDA &7E80,Y` then `STA $68`
  - Index: `Y = ($84 << 4) + $83` (row-major 16×16)
- `$83/$84` are tile coordinates (x/y).
- `&7E80` is inside `SPYP2` (because `SPYP2` covers `&6900..&7FFF`).

Startup coords observed:
- `$83 = #$0F`, `$84 = #$02`, tile at that location was `#$56`.

## Tile-triggered messages / events
Two concrete tile triggers found:
- `$68 == #$37` → `JMP &20C7` (“RECOGNISED” effect)
- `$68 == #$52` → `JMP &29E2` (“SUFFOCATED” effect)

Common gating logic:
- Both are gated on `$64 == #$0D`
- Both call `JSR &23ED` with `A=#06` or `A=#07`
  - `&23ED` checks whether `A` matches any of `$0109,$010A,$010B`:
    - returns `SEC` if not present (eligible)
    - returns `CLC` if present (blocked)
- Delay loop at `&23CC`
- Both use a latch (`$20C6` observed) to avoid retrigger spam.

## Major dispatcher / object system (`&271E`)
A major dispatcher exists at `&271E`:
- Selects object index using `$0109[$85]`
- References position/object tables around:
  - `&0BA8`, `&0BC8`, `&0BE8`, `&0C08`, `&0EA0` etc.
- Uses action code from `&7EE0,X`
- Dispatches by comparing `A` against constants (0, `#$02`, `#$04`, `#$05`, `#$06`, `#$C8`, `#$FF`)
- Updates per-object state and returns to `&2775` etc.

(This looks like the main per-object “do current action” system.)

## Screen pointer computation (`&1106`)
There is a small screen pointer routine in `SPYGAME` at runtime `&1106`.

Inputs:
- `$66` = column-like coordinate
- `$67` = row-like coordinate

Outputs:
- `($69,$6A)` = computed destination pointer
- `$73 = $67 & 7` (alignment within 8-byte band)

Algorithm:
- `idx = (($67 & $F8) >> 3)`
- base pointer comes from tables at:
  - `&0F88[idx]` (low)
  - `&0F9C[idx]` (high)
- adds column offsets from:
  - `&0F38[$66]` (low)
  - `&0F60[$66]` (high/carry)

Helpers immediately after:
- `+8`, `-8`, `+&0140`, `-&0140` adjust `($69,$6A)` (used for stepping across the screen layout).

Important: the `&0Fxx` tables are in live RAM and were dumped via B2, not from `SPYdata`.

### Live table observations
Using `b2-peek` during gameplay:
- `&0F38` looks like an “add 8 each column” table with wrap:
  - `10 18 20 28 ... F8 00 08 ...`
- `&0F60` is mostly 0, then 1s, consistent with carry on wrap.
- `&0F88/&0F9C` are a row-base pointer table (non-trivial).

## Flash/invert routine (UI effect)
There is an invert loop at runtime `&0DD9..&0DF1` in SPYGAME:
- Sets `$67=$82`, `$66=#1B`, calls `JSR &1106`
- XORs `#$0F` across `0x60` bytes at `($69),Y`

This was used for a flashing/highlight effect; useful for understanding coordinate→screen pointer mapping, but not the main sprite renderer.

## Sprite rendering: masked blitter (core finding)
The key sprite routine is a masked/composited blitter starting at runtime `&1239`.

### Inner loop (confirmed from live memory)
From live bytes at runtime `&1256`:

- `LDA ($69),Y`       ; read destination byte
- `AND ($78),Y`       ; apply mask
- `ORA ($60),Y`       ; OR sprite pixels
- `STA ($69),Y`       ; write back

So:
- `dst = (dst & mask) | pixels`

It then repeats similarly for a second destination pointer `($B0,$B1)` (computed as `($69,$6A) + &0138`) which suggests a two-band layout (two screen rows/bands drawn each pass).

### Data pointers involved (live ZP)
During walking / animation, live ZP shows:
- `$9F/$A0` = sprite pixels source pointer (eg `&76E0`)
- `$A1/$A2` = adjacent sprite pointer (eg `&76E8`, likely next shift/frame chunk)
- `$78/$79` = mask pointer (eg `&7C00`, also seen `&7A80/&7B80/&7C80/&7D80`)
- `$66/$67` = destination coordinate inputs to `&1106`
- `($69,$6A)` = computed destination pointer (eg `&7050` during walking)

### Mask table
A nybble mask/lookup table exists at `&0A00`:
- `FF EE DD CC BB AA 99 88 77 66 55 44 33 22 11 00 ...`
This matches MODE5-style packed pixels / per-nybble masking patterns.

## Sprite asset storage (example blocks)
While walking, we captured:
- pixels at `&76E0` (`b2-peek 76E0 +200`) – looks like real packed pixel patterns
- masks at `&7C00` (`b2-peek 7C00 +200`) – FF/00 plus patterned nybble masks (`77/33/11`, `EE/CC/88`, etc.)

Adjacent blocks dumped:
- pixels: `&7760` (`b2-peek 7760 +80`) differs significantly from `&76E0` (different frame/variant)
- masks: `&7C80` differs from `&7C00` (different mask variant)

Pointer polls showed the engine cycling sprite pointers among:
- pixels: `&7560`, `&7660`, `&76E0`, `&77E0`, `&7960`, …
- masks: `&7A80`, `&7B00`, `&7B80`, `&7C00`, `&7C80`, `&7D80`, …

This strongly suggests:
- sprites are stored as separate mask+pixel streams
- variants/frames are block-aligned (commonly `&80` boundaries for masks; pixels also move in chunky steps)

## Reproduce / commands

### Useful disassembly (static)
- Dump the SPYGAME pointer routine and blitters:
  - `tools/6502-dis .tmp/spycat_extracted/disc041/SPYGAME.bin --base 0x1100 --addr 0x1100 --len 0x140`
  - `tools/6502-dis .tmp/spycat_extracted/disc041/SPYGAME.bin --base 0x1100 --addr 0x1239 --len 0x180`

- Dump the loader strings / load addresses:
  - `tools/6502-dis .tmp/spycat_extracted/disc041/SPYLDR.bin --base 0x0000 --addr 0x0180 --len 0x80`

### Useful B2 peeks (runtime)
- Confirm SPYGAME is resident:
  - `./tools/b2-peek 1100 +10`

- Dump the `&0Fxx` pointer tables used by `&1106`:
  - `./tools/b2-peek 0F38 +80`
  - `./tools/b2-peek 0F60 +40`
  - `./tools/b2-peek 0F88 +40`
  - `./tools/b2-peek 0F9C +40`

- Dump the nybble mask lookup table:
  - `./tools/b2-peek 0A00 +40`

- Confirm the masked blitter inner loop bytes (used when `6502-dis` shows `.byte`):
  - `./tools/b2-peek 1256 +60`

- Capture live sprite pointers while walking:
  - `./tools/b2-peek 0070 +20` (includes `$71/$72/$78/$79` etc.)
  - `./tools/b2-peek 009C +10` (includes `$9F/$A0/$A1/$A2` etc.)

- Dump a sprite+mask block once you have pointers (example values we observed):
  - `./tools/b2-peek 76E0 +200`
  - `./tools/b2-peek 7C00 +200`
  - `./tools/b2-peek 7760 +80`
  - `./tools/b2-peek 7C80 +80`

## Object & sprite systems (new findings)

### Renderer switch (`$71`)
- `$71` selects the sprite renderer path.
- Observed runtime: `$71==$02` is used by the “expanded/indexed” renderer path (the code branches away from the masked blitter when `$71==2`).
- Live evidence: forcing certain object types (eg type `#$05`) results in `$71==$02` at draw time.

### Generic object draw sizes
- The generic object renderer loads per-type sizes from live RAM tables:
  - `&06C0[type]` → width in bytes → stored in `$72`.
  - `&06E0[type]` → stripe count (vertical bands) → stored in `$7E`.
- Live dump (types `00..1F`) shows a clear grouping:
  - `00..09`: `$72=#$10`, `$7E=#$02`  (≈32×16)
  - `0A..13`: `$72=#$20`, `$7E=#$02`  (≈64×16)
  - `14..1F`: `$72=#$20`, `$7E=#$04`  (≈64×32)

### Type → sprite data pointer table (`&0FB0/&0FD0`)
- Object types index a 16-bit pointer made from:
  - low byte table at `&0FB0`
  - high byte table at `&0FD0`
- Live dump decodes (type → pointer) as:
  - `00..07` → `&0700,&0720,&0740,&0760,&0780,&07A0,&07C0,&07E0`
  - `08` → `&0600`
  - `09` → `&FFFF` (sentinel)
  - `0A..11` → `&0400,&0440,&0480,&04C0,&0500,&0540,&0580,&05C0`
  - `12..13` → `&7180,&71C0`
  - `14..1F` → `&2B70,&2BF0,&2C70,&2CF0,&2D70,&2DF0,&2E70,&2EF0,&2F70,&2FF0,&2F70,&2FF0`

### Expansion tables
- Expanded/indexed renderer uses:
  - `&0900`: byte expansion table (256 bytes, maps small indices to pixel patterns)
  - `&0A00`: nybble mask patterns (`FF EE DD ... 11 00 ...`)

### Object slot arrays
- Per-slot arrays (32 slots):
  - `&0380,slot` = x
  - `&0384,slot` = y
  - `&0388,slot` = type
  - `&038C,slot` = state
  - `&0390,slot` = counter / timer

### Active runtime snapshot (example)
- At one snapshot, `&0388` began: `09 12 00 00 0F 0F 0F 0F 05 00 05 05 ...`

## Renderer modes and blitters (new consolidated understanding)

### Annotated routine index (for later full source annotation)
- `&1106` screen pointer: `$66/$67 -> ($69,$6A), $73`
- `&1132` dest lane step: `($69,$6A)+=8`
- `&1150` dest band step: `($69,$6A)+=&0140`
- `&11CA` generic pointer add: `($60,$61)+=A`
- `&11D7` source pre-align: `($60,$61)-=A`
- `&11E8` copy blitter (non-expanded)
- `&1239` masked blitter (non-expanded)
- `&1318` expanded copy blitter (when `$71==2`)
- `&1368` expanded masked blitter (when `$71==2`)
- `&139E` expanded lane precompute (build `A7/A9/AB` lanes)
- `&13C3` expanded masked inner loop
- `$71==#$10` UI/HUD draw sites: `&1D63`, `&1F28`, `&2259`

### `$71` is a mode selector (not just “2 or not 2”)
There are **multiple independent writers** of `$71`, so it is a general “render mode / flags” byte.

#### Confirmed `$71` meanings (current best)
- `$71 == #$01`: normal (non-expanded) object/sprite draw paths
- `$71 == #$02`: expanded/indexed render paths (uses `&0900` and `&0A00`)
- `$71 == #$10`: UI/HUD draw mode (paired with `$72 == #$10`); does not use `($78,$79)` sprite masks

Confirmed writers in `SPYGAME.bin`:
- `&16BE`: `$71 := $70` (main animation path, toggles between `1` and `2`)
- `&1B3F`/`&2679`: `$71 := 1` then sometimes `INC $71` (so `1` or `2`)
- **UI/HUD paths**:
  - `&1D63`: `$71 := #$10` and `$72 := #$10`, then `JSR &11E8`
  - `&1F28`: `$71 := #$10` and `$72 := #$10`, then `JMP &116E`
  - `&2259`: `$71 := #$10` and `$72 := #$10`, then `JSR &11E8`

Practical meaning observed:
- `$71 == #$02` selects the **expanded/indexed** renderer path (tables `&0900`/`&0A00`).
- `$71 == #$10` appears to be a **UI/HUD copy width/mode** (paired with `$72 == #$10`), and does *not* use sprite mask pointers `($78,$79)`.

#### `$71==#$10` UI/HUD draw sites (confirmed writers)
- `&1D5F..&1D74`:
  - Sets `$66=1`, `$67=$7C`, `$71=$72=#10`, `$60:$61=&0CE8`
  - If `$93!=0`, calls `JSR &11E8` (copy blitter)
  - Else calls `JSR &1447` (clear/blank routine for same region)
- `&1F20..&1F2D`:
  - Sets `$71=$72=#10`, `$61=#10`, `$60 = X<<4` so source is `&10(00..F0)`
  - Calls `JSR &1EF2` to load destination `$66/$67` from tables `&0BA8/&0BC8`
  - Then `JMP &116E` (note: `&116E` is only definitely valid when `$71==2`, so treat this as a case to verify at runtime)
- `&224D..&225B`:
  - Sets `$66=$15`, `$67=$7C`, `$71=$72=#10`, `$60:$61=&2AB0`
  - Calls `JSR &11E8` (copy blitter)

### `$72` is byte width
- The blitters compare `(Y - $73)` against `$72` to decide when the column is complete.
- Common values observed:
  - `#$20` for main sprite/object classes
  - `#$10` for UI/HUD blocks

### Screen stepping helpers
Immediately after `&1106`:
- `&1132`: `($69,$6A) += #$08` (“lane step” within an 8-scanline band)
- `&1141`: `($69,$6A) -= #$08`
- `&1150`: `($69,$6A) += #$0140` (next 8-scanline band)
- `&115F`: `($69,$6A) -= #$0140`

### Routine annotation blocks

#### `&11CA` — add A to source pointer
Inputs:
- `A`: amount to add
- `$60:$61`: pointer
Outputs:
- `$60:$61 := $60:$61 + A`
Notes:
- Used as a general pointer stepper (source pixels/masks and lane precompute).

#### `&11D7` — subtract A from source pointer (pre-align)
Inputs:
- `A`: amount to subtract
- `$60:$61`: pointer
Outputs:
- `$60:$61 := $60:$61 - A`
Notes:
- Used to pre-align source streams by `$73` so the Y-loop can start at `Y=$73`.

#### `&11E8` — copy blitter (non-expanded unless `$71==2`)
Entry: `JSR &11E8` (also re-enterable at `&11EB` after setup)
Inputs:
- `$66,$67`: destination coord inputs to `&1106`
- `$60:$61`: source pointer
- `$72`: total byte width to copy
- `$71`: mode selector (`#$02` uses expanded path at `&1318`)
Outputs/side effects:
- Writes to screen at `($69,$6A)` and sometimes also `($B0,$B1) = ($69,$6A)+&0138` depending on `$73`.
Mechanics:
- Calls `&1106` to compute `($69,$6A)` and `$73`.
- Pre-aligns `$60:$61 -= $73`.
- Uses `Y` and `(Y & 7)` boundary logic to split the write between two 8-scanline bands.
- Completes when `(Y - $73) == $72`.
- On completion, tail-calls `&11CA` with `A=$73` (i.e. advances the source pointer by `$73`).
Pseudocode (conceptual):
- `for i in 0..$72-1: dst[i] = src[i]` (arranged in two phases/bands keyed by `$73`).

#### `&1239` — masked blitter (non-expanded unless `$71==2`)
Entry: `JSR &1239` (often re-entered at `&123C` inside stripe loop)
Inputs:
- `$66,$67`: destination coord inputs to `&1106`
- `$60:$61`: pixels pointer (pre-aligned inside routine)
- `$78:$79`: mask pointer (caller often pre-aligns this by `$73`)
- `$72`: total byte width per stripe
- `$7E`: stripe count (vertical bands)
- `$71`: mode selector (`#$02` uses expanded path at `&12A4`)
Outputs/side effects:
- Masked composite into screen memory at `($69,$6A)` and also into `($B0,$B1)=($69,$6A)+&0138`.
- Advances `$60:$61`, `$78:$79`, and `($69,$6A)` across stripes.
Mechanics:
- Calls `&1106` to compute `($69,$6A)` and `$73`.
- Computes `$B0:$B1 = ($69,$6A) + &0138`.
- Pre-aligns `$60:$61 -= $73`.
- If `$71==2`, branches to expanded masked path at `&12A4`.
- Otherwise, inner loop bytes (confirmed by raw bytes at `&1256`):
  - `B1 69`        `LDA ($69),Y`
  - `31 78`        `AND ($78),Y`
  - `11 60`        `ORA ($60),Y`
  - `91 69`        `STA ($69),Y`
  - then increments `Y`, checks `(Y & 7)` boundary, etc.
- Second-band inner loop is the same but uses destination `($B0),Y` (raw bytes at `&1269`).
- Stripe stepping:
  - `$60:$61 += (#$20 + $73)` via `A=#20; ADC $73; JSR &11CA` (see `&1284..&1289`).
  - `$78:$79 += #$20` (see `&128C..&1297`).
  - `($69,$6A) += &0140` via `JSR &1150` (see `&1299..&129A`).
  - `DEC $7E` and loop until zero.
Notes:
- This is the non-expanded/true mask+pixel path: `dst := (dst & mask) | pix`.

#### `&1318` — expanded copy blitter (`&11E8` when `$71==2`)
Inputs:
- Same as `&11E8`, but expects `$71==2`.
Uses:
- `&139E` lane precompute
- `&142E` expand-and-store helper (uses `&0900`)

#### `&1368` — expanded masked blitter (`&116E` when `$71==2`)
Inputs:
- Same general coordinate+source model, but expects `$71==2`.
Uses:
- `&139E` lane precompute
- `&13C3` masked composite inner loop (uses `&0900` + `&0A00`)

#### `&139E` — expanded lane precompute
Inputs:
- `$60:$61`: base source pointer
- `$69:$6A`: base destination pointer
Outputs:
- Builds 3 additional source pointers in `$9F/$A0`, `$A1/$A2`, `$A3/$A4` (bytes spaced by +8)
- Builds 3 additional destination pointers in `$A7/$A8`, `$A9/$AA`, `$AB/$AC` (lanes spaced by +8 using `&1132`)
Notes:
- Together with base `($69)`, expanded inner loops operate on 4 “lanes” per scanline.

#### `&13C3` — expanded masked composite inner loop
Inputs:
- One scanline offset in `Y`
- Source lanes (via `($60)`, `($9F)`, `($A1)`, `($A3)`) and destination lanes (via `($69)`, `($A7)`, `($A9)`, `($AB)`)
Effect:
- For each lane:
  - `pix = &0900[src_byte]`
  - `dst = (dst & &0A00[pix]) | pix`
Notes:
- This is the cleanest and most definitive statement of the expanded masked rendering algorithm.

## Expanded (indexed) renderer internals

### Expanded copy blitter (`&11E8` when `$71==2`)
- `&11E8` is the normal **copy** blitter.
- If `$71 == #$02`, it jumps to `&1318`.
- `&1318` uses `&139E` to precompute pointers, and `&142E` to expand bytes via `&0900,X` and write out to multiple destinations.

### Expanded masked blitter entry (`&116E` when `$71==2`)
- `&116E` shares the common setup used by other blitters.
- If `$71 == #$02`, it jumps to `&1368`.
- The fall-through non-2 stream around `&1199` contains an `RTS` and appears to be non-linear/unused/obfuscated; no call/jump sites into the middle were found.

### Expanded masked inner loop (`&13C3`)
This is the clean, confirmed compositing algorithm used by the expanded masked path:
- `src := ($60),Y`
- `pix := &0900[src]`
- `dst := (dst & &0A00[pix]) | pix`

`&13C3` applies that to **four parallel destination pointers** per scanline:
- `($A7)`
- `($A9)`
- `($AB)`
- `($69)`

### Why four destinations? (`&139E` + `&1132`)
`&139E` precomputes pointer “lanes”:
- It snapshots 3 extra destination pointers in `$A7/$A8`, `$A9/$AA`, `$AB/$AC`.
- After each snapshot it calls `JSR &1132` (adds `#8`), so the lanes are spaced by `+8` bytes.
- Together with base `($69)`, the inner loop can render 4 lanes per scanline with low overhead.

## Open questions / next work
- Decode the on-disc object spawn stream at `&3070 + $68*0x28` (tile/room id `$68` chooses the record).
- Precisely classify what `&1F28` is drawing when it sets `$71=$10` but jumps to `&116E` (likely still a UI path; confirm at runtime by checking `$60:$61` and `$73/$66/$67`).
- Identify where the `&0880..&08A8` pose tables are built/loaded (they live below `&1100` so aren’t in `SPYGAME.bin`).
- Confirm exact geometry for each size class by measuring how many scanlines each stripe draws in each renderer.
