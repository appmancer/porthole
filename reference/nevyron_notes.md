# Nevyron Reverse-Engineering Notes

Target disk: `Nevryon.ssd` (DFS image in repo root)

This document is a running notebook. We will append findings in small, targeted chunks to avoid massive tool output and token-rate-limit blowups.

## Working method (token-safe)

- One micro-goal per iteration (e.g. “identify vsync wait mechanism”).
- Avoid pasting large disassemblies or full hex dumps into chat.
- Prefer: file names + load/exec addresses + a few key routine addresses + short snippets.

### Local full-disk extraction
- The full `Nevryon.ssd` contents are extracted to: `.tmp/nevyron/Nevryon.ssd.extracted/`
  - DFS `$` dir is in `.tmp/nevyron/Nevryon.ssd.extracted/$/`
  - Level dirs are in `.tmp/nevyron/Nevryon.ssd.extracted/1/`, `.tmp/nevyron/Nevryon.ssd.extracted/2/`, etc.
- Re-extract (regenerates files; safe to rerun):
  - `python - <<'PY'
import subprocess, re
from pathlib import Path

image = 'Nevryon.ssd'
out_root = Path('.tmp/nevyron/Nevryon.ssd.extracted')
out_root.mkdir(parents=True, exist_ok=True)

cat = subprocess.check_output(['./tools/dfs-cat', image], text=True)
names = []
for line in cat.splitlines():
    m = re.match(r'^\s*\d+\s+(\S+)\s', line)
    if m:
        names.append(m.group(1))

for dfs_name in names:
    if '.' in dfs_name:
        d, f = dfs_name.split('.', 1)
    else:
        d, f = '', dfs_name
    out_path = out_root / d / f
    out_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.check_call(['./tools/dfs-extract', image, dfs_name, str(out_path)])

print(f'Extracted {len(names)} files to {out_root}')
PY`

## Question A: How does Nevyron avoid flicker/tearing?

### A.0 What we’re trying to determine
Nevyron likely uses one (or more) of these strategies:

- VBlank sync (OS call “wait for vsync”, or 6845 polling)
- Interrupt-driven timing (IRQ handler pacing)
- Double-buffer / screen start-address swapping (6845 R12/R13)
- Reduced render workload (small playfield, clipped redraw)
- Shadow screen / memory mapping tricks (Master-specific)
- “Prince of Persia” style ordering: restore/draw ordered to avoid resurrecting pixels

### A.1 Evidence to look for in code
We’ll search for:

- OSBYTE calls related to vsync / keyboard / timing
- Direct CRTC writes (`&FE00/&FE01`) especially to registers that control start address
- VIA access (`&FE4x`) suggesting interrupts or timers
- Large memory copies to screen (suggesting double buffer or whole-band blits)
- Any explicit frame pacing loop

### A.2 Catalogue snapshot (what we know so far)

From DFS catalogue (via `./tools/dfs-cat Nevryon.ssd`):

- `$.NEVRYON` load `0C0E00` exec `0C802B` len `164` start sector `205`
- `$.Loader2` load `0C0E00` exec `0C802B` len `5370` start sector `208`
- `$.Runner` load `0C3200` exec `0C802B` len `159` start sector `229`
- `$.CODE2` load `002800` exec `00283A` len `2537` start sector `236`
- `$.CODE3` load `003300` exec `003300` len `912` start sector `232`
- `$.GRAPHIX` load `003680` exec `003680` len `4992` start sector `185`
- `$.SCR` load `003000` exec `003000` len `7680` start sector `155`
- Level data appears under directories `1..4` as `LEVD1/2/3`.

Interpretation (tentative):
- There’s likely a loader chain (`NEVRYON` / `Loader2` / `Runner`) that ends up jumping into `CODE2`/`CODE3` and uses `GRAPHIX`/`SCR`.

### A.3 Working hypothesis (pending disassembly)

- The flicker-free behavior probably comes from one of:
  - strict vsync pacing + a smaller playfield redraw budget, or
  - ordering (restore/draw), or
  - start-address swapping.

We’ll confirm by locating the main loop and identifying:
- “wait for vsync” mechanism
- the exact scope of redraw per frame

## Findings log (append-only)

### A.4 Entry chain
- `$.NEVRYON`, `$.Loader2`, `$.Runner` are tokenised BASIC programs (not machine code).
- Machine code of interest:
  - `$.CODE2` load `002800` exec `00283A` len `2537` start sector `236`
  - `$.CODE3` load `003300` exec `003300` len `912` start sector `232`
- The BASIC loader(s) appear to set OS variables (`?&9D`, `?&9E`, `?&9F`, …) and issue some `*FX` commands before transferring control.

### A.5 VBlank sync mechanism
- In `CODE2` there are many occurrences of `LDA #&13 : JSR &FFF4` (OSBYTE `19`): `&2852`, `&2C1A`, `&2C64`, `&2CB2`, `&2E26`, `&2EE4`.
- In `CODE3` the same pattern appears: `&3369`, `&3424`, `&34E0`.
- This is very likely their frame pacing: “wait for vsync” via OSBYTE 19.

### A.6 Screen buffering / start-address changes
- No direct CRTC register accesses seen in `CODE2`/`CODE3` (no `STA/LDA &FE00/&FE01` signatures).
- Instead, `CODE3` uses `OSWRCH` heavily, including:
  - `VDU 31` (`&1F`) to move the text cursor (prints `x` then `y`).
  - `VDU 23` (`&17`) to redefine characters (notably chars `&E1`/`&E2`).

### A.7 Redraw scope
- `CODE3` contains a “VDU helper” routine around `&3560..&361F`.
- It self-modifies an instruction operand to point at the current string:
  - Callers put a string pointer in ZP `&95/&96`.
  - The routine stores those bytes into `&3588/&3589`, which are the low/high operand bytes of `LDA &FFFF,X` at `&3587`.
  - Net effect: `LDA &FFFF,X` becomes `LDA <string>,X` (classic 6502 self-mod pointer).
- It then loops `X` (`&90`) over the string until `&0D`.
- For each source character code:
  - `STA &3501` then `JSR &350A` where `&350A` is `OSWORD &0A` with `XY=&3501`.
  - This appears to read the 8-byte bitmap for that character into `&3502..&3509`.
  - It immediately emits `VDU 23,&E1,...` and `VDU 23,&E2,...`, building two redefined chars from the bitmap bytes (includes a couple of `ORA` combinations).
  - It prints `&E1` and `&E2` with cursor-motion VDU codes (`8`, `10`, `11`) so the pair renders as a single taller glyph.
- Implication: for this text/splash pipeline, they reuse just **two character IDs** (`&E1`/`&E2`) and redefine them per printed glyph (minimal character set pressure; no large sprite blits).

### A.8 Notes applicable to PORTHOLE
- Interesting technique: “big-font string plot” by redefining two character slots repeatedly.
- Routine: `CODE3 &3560..&361F`.
  - Input: string pointer in ZP `&95/&96` (terminated by `&0D`).
  - Uses self-modifying code at `&3587` (`LDA &FFFF,X`) by patching operand bytes at `&3588/&3589` so it becomes `LDA <string>,X`.
  - Per character: uses `OSWORD &0A` with parameter block at `&3501` (calls `OSWORD` at `&350A`) to read the 8-byte glyph definition into `&3502..&3509`.
  - Immediately emits `VDU 23` to redefine chars `&E1` and `&E2` from those bytes, then prints `&E1/&E2` with cursor motion so they stack as a taller glyph.
- Example rendered strings embedded in `CODE3` (callers `JSR &3560`): `LOADING`, `PLEASE WAIT`, `LEVEL X COMPLETED`, `BONUS X000`, `+ EXTRA SHIP!`, `PRESS SPACE TO`, `CONTINUE PLAY!`, `CREDITS:00`.
- Takeaway: for occasional UI banners, we can get a “sprite-like” big font with almost zero character set pressure (only two char IDs needed at once), at the cost of per-character `OSWORD` + `VDU 23` overhead.

### A.9 CODE is relocated to `&1100` (important)
- `$.LOADER3` (tokenised BASIC) contains `*L.CODE 1100`, then `*LO.CODE2`, `*L. CODE3`, then `CHAIN "RUNNER"`.
- Implication: when disassembling `$.CODE`, use base address `&1100` (not the catalogue load address `&0E00`). All routine addresses shift by `+&300`.

### A.10 In-game bitmap blitter (in `$.CODE`)
- With correct base `&1100`, there is a core screen blit routine starting at `&116F`.
- It writes directly to screen RAM using the classic BBC bitmapped interleaving:
  - Destination address comes from ZP `&76/&77`, aligned via `AND #&F8`, then writes with `STA (&70),Y` where `Y = (dest & 7)`.
  - It steps down 8 scanlines by adding `&140` (implemented as `ADC #&3F` + carry, then `ADC #&01` to the high byte).
- Source pointer is *self-modified*:
  - Inner loop uses `LDA &FFFF,X` at `&1193`.
  - The operand bytes for that instruction live at `&1194/&1195`, so callers can set `&1194/&1195 = <source>` and automatically retarget the blit.
- Variable-size entrypoint: `&1173` stores `X` (height in 8-scanline blocks) and `Y` (width in bytes) into internal counters before blitting.

### A.11 Screen address calculator
- Routine at `&1236` computes a screen address into ZP `&76/&77`.
- It treats `X` as an x-byte coordinate (adds `+8` per column) and flips `Y` vertically (`EOR #&FF`) before mapping through small lookup tables.

### A.12 In-game sprite pipeline usage (in `$.CODE2`)
- Many `$.CODE2` routines follow the pattern:
  - load object `X/Y` coords into `X`/`Y`, then `JSR &1236` (dest address calc)
  - set `&1194/&1195` to a source bitmap address
  - set `X=height_blocks` and `Y=width_bytes`
  - `JSR &1173` (blit)
- Example: `CODE2 &2AC4..&2B47` updates a pair of objects stored in arrays `&2B9A` (x) and `&2B9C` (y):
  - it first blits using source `&7D80` with size `1 x 6` (very likely an “erase” sprite)
  - it updates the position (horizontal + optional vertical drift)
  - it then blits using source `&3AB0` with the same size (the visible sprite)
- Takeaway: at least for these objects, Nevyron does *erase → move → redraw* by overblitting a known background/blank tile, rather than save-under.

### A.13 Main per-frame loop anchor (in `$.CODE` at `&1100`)
- There is a tight loop at `&143C..&1477` gated by `LDA &2051` and a small counter in ZP/low RAM (`INC &8F`, loop while `< 4`).
- Each tick it calls into `$.CODE2` helpers:
  - `JSR &2AA2` (updates/draws the two-object arrays at `&2B9A/&2B9C`)
  - `JSR &29E7` (iterates a 6-byte table at `&2A02` and blits each entry via `&2A08`)
  - `JSR &28D7` (draws a small `2x12` sprite at `(&2972,&2973)` and handles player proximity via `OSBYTE &81`)
- It also calls additional engine routines (`&13BC`, `&1AEB`, `&2693`, `&15C4`, `&14D9`, `&3513`) which likely cover input, physics, sound, and UI.

### A.14 True entrypoint + front-end loop (in `$.CODE` at `&1100`)
- `&1100` begins with `JSR &3115`, `JSR &1F8E`, `JSR &2CCA`, `JSR &13D1`, then checks `&2051`.
  - If `&2051==0`: `JMP &3432` (into `$.CODE3`).
  - Else: does menu/input gating via `JSR &155B` and ends up `JMP &3300` (into `$.CODE3`).
- `$.Runner` does `CALL &1100` (confirmed from tokenised BASIC bytes).
- `$.LOADER3` is mostly readable even without detokenising: `*FX200,3`, `*L.CODE 1100`, `*LO.CODE2`, `*L.CODE3`, then `CHAIN "RUNNER"`.

### A.15 VBlank sync usage is not “per-frame” (so far)
- There are **no** `OSBYTE 19` calls in `$.CODE` (the main engine blob at `&1100`).
- `OSBYTE 19` (`LDA #&13 : JSR &FFF4`) appears only in `$.CODE2`/`$.CODE3`.
- In the regions inspected, it’s used as a *delay primitive* inside small loops:
  - `CODE2 &284C..` uses `OSBYTE 19` inside a countdown loop.
  - `CODE2 &2E24..&2E39` does `blit → vsync → OSBYTE &81 (INKEY)` (key-wait loop).
  - `CODE2 &2EE2..&2EE7` does `blit → vsync → repeat` (timed loop).
  - `CODE3 &3367..` does a timed `OSBYTE 19` loop (front-end delay).

### A.16 Blitter source catalogue (immediate-pointer cases)
- Found **29** immediate blit setups in `$.CODE2` that write `&1194/&1195` then `JSR/JMP &1173`.
- Most sources are within `GRAPHIX` (`&3680..&49FF`), including `&3AB0` used as a `blocks=1 width=6` sprite.
- Non-`GRAPHIX` sources observed:
  - `&4E80` / `&4E96`: within the `&3000` picture buffer while `OPSC`/`WELLDON`/`SCR` is loaded (those files overlay at `&3000` and are large enough to cover `&4E80`).
  - `&7E00` / `&7E02`: match `$.4THDIM` (loads at `&7E00`, length `&0140`).
  - `&7D80`: used repeatedly as an “erase/blank” sprite source in screen/work RAM.
- Example in-game object pipeline (confirmed in code): `CODE2 &2ACD..&2B3F` does `erase` via `&7D80` then redraw via `&3AB0` (same `blocks=1 width=6`).

### A.17 Gameplay tick structure + pacing (in `$.CODE` at `&1100`)
- The “frame/tick” routine is `&13D1..&1477` (called from `&1109`).
- It runs **4 sub-ticks per call** using ZP `&8F` as a `0..3` counter:
  - `&1438` clears `&8F`, then `&143C` loops until `&8F == 4`.
  - Each sub-tick calls the main update/draw helpers (in `$.CODE2`) and engine routines:
    - `JSR &2AA2`, `JSR &29E7`, `JSR &28D7`
    - then `JSR &13BC` (delay), `JSR &1AEB`, `JSR &126C`, `JSR &2693`, `JSR &15C4`, `JSR &14D9`.
- **Pacing mechanism (so far):** there is no vsync gate in the main tick; instead `&13BC` is a pure CPU busy-wait.
  - `&13BC` takes a loop count from ZP `&7A`.
  - At the end it copies ZP `&92` into `&7A` (`LDA &92 : STA &7A`). `&92` is otherwise unused in `$.CODE`, so it’s likely an init-time constant (possibly from BASIC).

### A.18 Input primitives used by the tick
- Key polling is `&155B`:
  - `LDA #&81 : LDY #&FF : JSR &FFF4` (OSBYTE `&81`, with key code in `X`).
  - Returns with `Y=&FF` if the key was not pressed (callers do `BNE` on `CPY #&FF`).
- `&13D1` calls `&155B` with `X=&C8` and, when pressed, calls `&3170` (likely sound/ack).
- There’s also analogue input use via OSBYTE `&80` (ADVAL):
  - `&1517..&1558` does three `OSBYTE &80` reads with `X=1`, `X=2`, and `X=0`, then compares the returned `Y` against `&40`/`&C8` thresholds to steer object motion.

### A.19 True “outer loop” is in `$.CODE3`
- `$.CODE` entrypoint `&1100` always `JMP`s into `$.CODE3` (`&3300` or `&3432`) after the `JSR &13D1` pass.
- `$.CODE3` has a trampoline at `&34FE`: `JMP &1100`.
- Net effect: `CODE3` is the state-machine/dispatcher, looping by jumping back into `&1100`.

### A.20 What the per-tick callees look like (very rough)
 - `&126C` (called every sub-tick) looks like a **background/field update + blit driver**:
   - Special-cases `&80==&F0` (`JSR &2656` then `JMP &210A`).
   - Otherwise does `JSR &1309` (writes bytes into addresses read from tables around `&3041/&307E`, suggesting some particle/starfield stream), then `JSR &210A`.
   - Uses `&8D/&8E` and `&8B/&8C` as moving source pointers (increments low byte by `+&20` per call), then invokes the blitter (`JSR/JMP &116F`).
 - `&1AEB` appears to be an **entity list update+draw loop**:
   - Scans an array at `&1A6B` for active entries; if none, jumps to `&1D35`.
   - For each active entry, it can erase (`source=&7D80`, size `blocks=4 width=24`) and/or redraw at coords from `&1A55` (x) and `&1A60` (y).
   - Calls helpers `&2555`, `&1C5D`, `&1B87`, `&1BE3`, `&1A99` (likely state/AI, script decode via `($88),Y`, and sprite selection).
 - `&2693` looks like a **single animated object** with collision gating:
   - Uses state bytes around `&2690..&2692` plus a collision helper `&275F` that checks player coords in `&81/&82`.
   - Draws a `blocks=3 width=16` sprite using a small state machine that selects source pointers in the `&40xx` and `&47xx` ranges.
   - When its countdown reaches 0, it clears `&2692` and erases via `&7D80`.

### A.21 Screen/mode setup is done in BASIC (`$.Loader2`)
- `$.Loader2` explicitly sets `MODE 5` (tokenised BASIC line `28675`).
- It uses `VDU 23` CRTC programming via the OS, e.g.:
  - `VDU 23,0,1,40;0;0;0;` (CRTC `R1=40`, horizontal displayed)
  - `VDU 23,0,2,80;0;0;0;` (CRTC `R2=80`, horizontal sync position)
  - `VDU 23,0,6,22;0;0;0;` and `VDU 23,0,7,32;0;0;0;` (vertical timing regs)
  - `VDU 23;12,&5800 DIV 2048;0;0;0` and `VDU 23;13,&5800 MOD 2048 DIV 8;0;0;0` (CRTC `R12/R13` screen start = `&5800`)
- The repeated `VDU 23;8202;0;0;0;` decodes to `VDU 23,0,10,32,0,0,0,0,0,0` (CRTC `R10=32`), i.e. cursor effectively disabled.
- BASIC-level vblank pacing is done with `*FX19` (i.e. OSBYTE `19`) in multiple timed loops.

### A.22 No obvious IRQ/VIA timer pacing in machine code
- Scanning `$.CODE`/`$.CODE2`/`$.CODE3` finds no obvious absolute accesses to SHEILA `&FE40..&FE4F` (System VIA), nor to `&FE00/&FE01` (6845 CRTC).
- This supports the current hypothesis: in-game pacing is mainly the busy-wait at `&13BC` (plus small incremental redraw), with `OSBYTE 19` used only in front-end/delay loops.

### A.23 How `SCR` / `OPSC` / `WELLDON` are drawn (current best model)
- These files are **not** raw MODE 5 screen RAM dumps; they look like data blobs designed to be consumed by the existing bitmap blitter.
- All three load at `&3000` and are large enough to **overlay** the `GRAPHIX` region (`&3680..`), so they can’t coexist with in-game sprite assets.
- Code uses fixed source pointers that land inside the currently-loaded `&3000` blob (examples: `&3A60`, `&4C20`, `&4E80`), and then draws via the standard pipeline:
  - `JSR &1236` (screen address calc) → set `&1194/&1195` (source) → `JSR &1173` (blit).

### A.24 Example: `CODE2` “big strip” draw from `&4E80`
- Routine `$.CODE2 &2F7C..&2FEF` repeatedly blits from source `&4E80` with size `blocks=5`, `width_bytes=22`:
  - per iteration: `X = ZP &90`, `Y = &C8`, `JSR &1236`, then `JSR &1173` with `X=&05`, `Y=&16`.
  - runs as an animation loop (interleaves a flashing small sprite using source page `&36` and erases with `&7D80`), with a delay primitive `&2F66` between steps.
- Similar smaller loop exists at `$.CODE2 &31BD..&31E7` (same `&4E80` source and `blocks=5 width=22`).

### A.25 What this implies about the blob format
- The core blitter (`$.CODE &1173`) reads the source stream sequentially (`LDA &FFFF,X`) and writes into bitmapped screen RAM, stepping down scanlines by `+&140` and across by incrementing the source pointer.
- So `SCR`/`OPSC`/`WELLDON` most likely store their graphics already in **blitter-native order**:
  - per 8-scanline “block”: `width_bytes` bytes per scanline, for 8 scanlines;
  - repeated for `height_blocks` blocks.

### A.26 Which blob is loaded when the `&4E80` strip animation runs?
- `$.CODE2` contains an explicit dispatcher at `&2EFF`:
  - `LDA &2051 : CMP #&06` then either `JMP &31B1` or continues at `&2F09`.
  - Both paths ultimately run the same end-screen animation helpers (`&2F20/&2F2D/&2F3A/&2F47`) and the large strip blit that sources from `&4E80`.
- In practice, the `&4E80` region (the 880-byte strip used by `blocks=5 width=22`) is **far denser** in `WELLDON` than in `OPSC`:
  - `WELLDON` @`&4E80` has ~32% non-zero bytes; `OPSC` only ~7%.
- Conclusion: the `&4E80` strip animation is almost certainly intended to run with `WELLDON` loaded at `&3000`.
  - This matches the presence of `*L. WELLDON 3000` in `$.Loader2`.

### A.27 `&2051` is the “ships/lives” counter (max 6)
- `$.CODE2 &30F8` saves `&2051` into `&0CF3` (`STA &0CF3`), and `$.CODE2 &3115` restores it back (`LDA &0CF3 : STA &2051`).
  - `&0CF3` is printed by BASIC as `SHIPS:` (see `$.GmOv`).
- Death/life-loss path is in `$.CODE &1F29`:
  - `DEC &2051` then uses the new value to compute an `X` coordinate and blit over a ship icon (removing one from the HUD).
  - If `&2051` becomes 0, it takes a different path (no `JSR &2BA4` respawn call).
- Level-complete bonus logic is in `$.CODE3 &33E3..&3417`:
  - Checks `&2051==6` and, if not, prints a message (string at `&3656`, likely `+ EXTRA SHIP!`) then `INC &2051` and redraws the ship bar.

### A.28 Returning to BASIC is done via a tail-call into `&30F8`
- `$.CODE3 &3300` (front-end banner path) ends with `JMP &30F8` (not `JSR`).
- Because `&30F8` ends with an `RTS`, this is a deliberate “exit to BASIC” handoff: save state (`&0CF3`, `&0CF4..`) then return to the caller of the original `CALL &1100` (i.e. `$.Runner`).
- This likely explains how BASIC regains control to `CHAIN "LOADER4"`, load level files via `OSFILE (&FFF7)`, etc.

### A.29 Sprite/update throughput: blits per sub-tick (upper bounds)
This answers “how can it update so many sprites?”: the per-sub-tick work is mostly a *bounded number of cheap blits*, driven by small fixed-size loops and a fast generic blitter.

- Main tick (`$.CODE &13D1..&1477`) runs **4 sub-ticks** per call, and (in the core path) invokes these draw/update helpers every sub-tick: `&2AA2`, `&29E7`, `&28D7`, `&1AEB`, `&126C`, `&2693`, …

- `$.CODE2 &29E7` (6-entry table blitter): **exactly 6 blits** per call.
  - Loops `X=0..5` and calls `&2A08` each time; `&2A08` does one `JMP &1173`.

- `$.CODE2 &2AA2` (two-object arrays `&2B9A/&2B9C`): up to **4 blits** per call for the two objects, plus up to **2 extra** conditional blits.
  - For each active object, `&2AC4` does `erase` (`source=&7D80`, `1x6`) then `draw` (`source=&3AB0`, `1x6`) → **2 blits per object**.
  - Then `&2B48` does a proximity check and, on hit, does an extra `erase` blit (`&7D80`, `1x6`) → **+1 blit per object hit**.

- `$.CODE2 &28D7` (small 2x12 sprite + proximity): **1–2 blits** per call.
  - Always draws an `erase` (`source=&7D80`, `2x12`), and if the player is in-range it draws the animated sprite frame (`source page=&38`, `2x12`).

- `$.CODE &126C` (background/strip driver): **2 background blits** per call via `&116F`.
  - `&116F` is the default-size blitter entry (`blocks=1 width=32`). `&126C` does `JSR &116F` then `JMP &116F` → two 8-scanline strips.

- `$.CODE &2693` (single animated object): typically **1 blit** per call, with edge cases up to **2 blits**.
  - Normal animation frame is selected by `&2692` and ends in a `JMP &1173`.
  - Collision/shutdown paths can also do an `erase` via `&7D80`.

- `$.CODE &1AEB` (entity list): the list is fixed-size, and each entity update is “one big sprite blit”.
  - Entity slots: `&1AEB` scans indices `X=8..1` (it does **not** check slot 0), so it can process **up to 8 active entities** per pass.
  - Per-entity blit: typical active-entity path does one `draw` blit (`blocks=4 width=24`) after selecting the sprite pointer via `&1BE3`.
  - It also contains an `erase` blit of the same size when an entity is cleared/deactivated.

Rough “worst case” for just these callees in a single sub-tick (ignoring conditional gating inside subroutines):
- `6` (table) + `6` (two objects + both hit) + `2` (small sprite) + `2` (background strips) + `2` (animated object edge case) + `8` (entity list draws) ≈ **26 blits per sub-tick**.
- And remember the tick does 4 sub-ticks per call, but many routines have internal gating (e.g. on `&8F`, `&25A5`, etc.), so the real average is lower.

## Next session plan (in-game loop)

Micro-goal: map the *real gameplay frame loop* and how it drives the bitmap blitter.

0) Use the full extraction (avoid piecemeal extracts)
- Prefer working from `.tmp/nevyron/Nevryon.ssd.extracted/` for file bytes.
- Use `./tools/dfs-cat Nevryon.ssd` as the load/exec “manifest”.

1) Confirm loader chain + addresses
- Confirmed: `Loader2` → `LOADER3` (`*FX200,3`, `*L.CODE 1100`, `*LO.CODE2`, `*L.CODE3`, `CHAIN "RUNNER"`).
- Confirmed: `RUNNER` does `CALL &1100`.
- Done: screen/mode assumptions are set in `Loader2` (`MODE 5`, CRTC start `&5800`, cursor disabled via `VDU 23`).

2) Identify the true entrypoint + per-frame loop
- Confirmed anchor: `$.CODE` loop at `&143C..&1477`.
- Next: trace *what calls* this loop and where it returns, and identify which callee is the real gameplay “update+draw” driver (`&13BC`, `&1AEB`, `&126C`, `&2693`, ...).

3) Frame pacing placement (flicker avoidance)
- New hypothesis: gameplay pacing is **not** a simple per-frame `OSBYTE 19` gate, because `$.CODE` contains no `OSBYTE 19` calls.
- Next: locate any alternative pacing mechanisms:
  - IRQ/VIA timer setup (look for SHEILA `&FE4x` and writes to vectors `&0204..`). So far: no obvious `&FE4x` refs in `$.CODE`/`$.CODE2`/`$.CODE3`.
  - MOS time calls (`OSWORD` time/date, `OSBYTE` clock-related calls), or any explicit scanline/vblank polling.
- Also: continue recording `OSBYTE &81` (INKKEY-style) usage to map in-game keys.

4) Sprite pipeline: source bitmaps + sizes
- Catalogue every distinct source pointer written into `&1194/&1195` (e.g. `&3Axx`, `&47xx`, `&7Dxx`) and record the `(height_blocks,width_bytes)` used with `JSR &1173`.
- Determine which source ranges are:
  - direct from `GRAPHIX` (loaded at `&3680`),
  - copied/expanded tables, or
  - screen-scratch derived data.

5) Erase strategy (confirm the hypothesis)
- Verify whether “erase” is always a fixed blank tile (e.g. the `&7D80` source used in `CODE2 &2AC4..&2B47`), or whether any objects use save-under / background restore.
- Record draw order rules if multiple objects overlap.

6) Background / level rendering
- Find how `SCR` / `OPSC` / `WELLDON` assets are drawn: blitter, `OSWORD`, or pure VDU.
- For level data (`1..4/LEVD1/2/3`), identify the decode/draw routine and whether it redraws whole bands or incremental tiles.
