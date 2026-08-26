# White Light — Sprite Technique Analysis

Disc: `reference/WhiteLight-v10_BBCMicro-DFS.ssd` (BBC Micro, DFS)

## Overview

White Light is a vertically scrolling shooter for the BBC Micro. It
uses CRTC hardware scrolling (R12/R13 ring buffer) and renders
multiple masked sprites per frame with no visible flicker. The key
technique is a **nibble-split** rendering method that eliminates
save-under buffers and per-pixel mask data entirely.

## File Structure

| File | Load addr | Size | Role |
|------|-----------|------|------|
| !BOOT | — | 17B | `*BASIC` then `CHAIN"WL"` |
| WL | &0000 | 40B | BASIC loader: detects Model B vs Master, runs W1 |
| W1 | &1200 | 15,006B | Title screen (MODE 7→MODE 1), CRTC init, chains to W2 |
| W2 | &1100 | 12,032B | Game init: sets MODE 2 ULA, palette, screen clear, chains to W3 |
| W3 | &0E00 | 6,383B | **Main game engine**: sprites, scroll, game loop |
| W4 | &1400 | 5,456B | Level transition / setup, chains onward |
| W5 | &1200 | 17,939B | Largest module (level data + code?) |
| W6 | &1200 | 14,192B | Alternate game module, chains to W5 |
| LV* | &10000/&20000 | 6,432B each | Level data (14 files) |
| MUS* | &0720 | 992B each | Music data (5 files) |

Chain order: `!BOOT → WL → W1 → W2 → W3 → W4 → ...`

## Display Mode — The Hybrid Mode Trick

White Light runs a **hybrid display mode**: MODE 2 pixels with MODE 0
CRTC timing. The MOS is never told about the switch, so pressing BREAK
returns to MODE 1 (the title screen mode set by W1).

### Why Hybrid?

Standard MODE 2 uses a 20KB screen (&3000-&7FFF). By switching the
CRTC to MODE 0's faster character clock, the 14-bit CRTC address space
covers only 16KB instead of the 64KB that MODE 2's slower clock would
span. The screen shrinks to &4000-&7FFF, **freeing &3000-&3FFF (4KB)
for game data** — enough for sprite graphics and level tables.

### How It Works

W2 programs the hardware directly without using VDU calls:

**Step 1 — ULA control register (&FE20) = &14:**

```
&14 = 0001 0100
         ^^^
    Bits 4-2 = 101 → MODE 2 pixel format (2 pixels/byte, 16 colours)
```

Compare with standard MODE 2 ULA value &F4 — same bits 4-2, just
different cursor bits (7-5).

**Step 2 — CRTC registers (MODE 0 horizontal timing):**

| Reg | Value | Standard MODE 2 | Standard MODE 0 | Meaning |
|-----|-------|-----------------|-----------------|---------|
| R0 | **127** | 63 | **127** | Horizontal total |
| R1 | **80** | 20 | **80** | Horizontal displayed |
| R2 | 98 | 25 | 98 | H sync position |
| R4 | 38 | 38 | 38 | Vertical total |
| R6 | 32 | 32 | 32 | Vertical displayed |
| R9 | 7 | 7 | 7 | Scanlines per char |
| R12:R13 | &06:&00 | &0C:&00 | &0C:&00 | Screen start |

R0=127, R1=80 is MODE 0's horizontal timing: 128 total CRTC characters,
80 displayed. In MODE 0, each CRTC character = 1 byte (2MHz clock). In
standard MODE 2, each CRTC character = 4 bytes (0.5MHz clock), giving
R1=20 for the same 80 bytes per scanline.

Both produce 80 bytes/scanline = 160 pixels in MODE 2. But the CRTC's
14-bit address counter covers 16,384 × 1 byte = **16KB** at MODE 0's
clock rate, vs 16,384 × 4 bytes = 64KB at MODE 2's clock rate (wrapped
to 20KB by hardware).

### The Result

| Property | Standard MODE 2 | White Light hybrid |
|----------|----------------|--------------------|
| Colours | 16 | 16 |
| Resolution | 160×256 | 160×256 |
| Bytes/scanline | 80 | 80 |
| Screen size | 20KB (&3000-&7FFF) | **16KB (&4000-&7FFF)** |
| RAM freed | — | **4KB (&3000-&3FFF)** |
| MOS mode | MODE 2 | MODE 1 (stale) |
| BREAK returns to | MODE 2 | **MODE 1** |

Visible colours confirm the MODE 2 pixel format: the game shows 4
terrain colours (black, white, cyan, blue) plus 2 sprite colours (red,
yellow) — impossible in MODE 1's 4-colour limit.

### Setup Sequence in W2

W2 actually programs two configurations in sequence:

1. **Temporary config** (ULA &4B, CRTC R1=40, R9=18): Used during the
   title→game transition. R9=18 means 19 scanlines per character row
   (non-standard). This mode is active while W2 clears the status bar
   area (&7C00-&7FFF) and loads level data from disc.

2. **Final game config** (ULA &14, CRTC R1=80, R9=7): Switches to the
   hybrid MODE 2/MODE 0 display. Programs palette via &FE21, then
   jumps to W3 (the main engine).

## The Nibble-Split Technique

### MODE 2 Byte Layout

Each byte encodes 2 pixels with 4 bits each, interleaved:

```
Bit:   7  6  5  4  3  2  1  0
       L3 R3 L2 R2 L1 R1 L0 R0
       ─────────  ─────────
       high nib   low nib
       (D3,D2)    (D1,D0)
```

The high nibble contains D3,D2 of both pixels. The low nibble contains
D1,D0 of both pixels. White Light exploits this by assigning each
nibble to a different rendering layer:

- **High nibble** = background (tile terrain)
- **Low nibble** = sprites

### Background Constraint

Background tiles only use logical colours where D1=0 and D0=0:
**colours 0, 4, 8, 12**. These produce bytes where the low nibble is
always zero — all colour information sits in the high nibble.

Example: left pixel colour 8, right pixel colour 4:

```
Colour 8: D3=1 D2=0 → bits 7,5 = 1,0
Colour 4: D3=0 D2=1 → bits 6,4 = 0,1
Result byte: 1001 0000 = &90  (low nibble = &00)
```

### Sprite Constraint

Sprites only use logical colours where D3=0 and D2=0:
**colours 0 (transparent), 1, 2, 3**. These produce bytes where the
high nibble is always zero.

Example: both pixels colour 3 (D1=1, D0=1):

```
Left:  bits 3,1 = 1,1
Right: bits 2,0 = 1,1
Result byte: 0000 1111 = &0F  (high nibble = &00)
```

### Plot Operation

```
LDA ($sprite),Y    ; load sprite byte (e.g. &0F)
AND #$0F           ; ensure only low nibble
ORA ($screen),Y    ; merge with background's high nibble
STA ($screen),Y    ; write combined byte
```

Result: `&0F ORA &90 = &9F`. The background's high nibble (&90) is
preserved. The sprite's low nibble (&0F) is added.

### Erase Operation

```
LDA ($screen),Y    ; load screen byte (e.g. &9F)
AND #$F0           ; wipe low nibble, keep high nibble
STA ($screen),Y    ; background restored perfectly
```

Result: `&9F AND &F0 = &90`. Original background byte, no buffer
needed.

### Combined Colours and Palette

The displayed logical colour is background + sprite:

```
              Sprite +0    Sprite +1    Sprite +2    Sprite +3
              (transp)
BG colour 0:     0            1            2            3
BG colour 4:     4            5            6            7
BG colour 8:     8            9           10           11
BG colour 12:   12           13           14           15
```

The palette (VDU 19) maps each logical colour to a physical colour.
For sprites to appear consistent on all backgrounds, each sprite
colour index maps to the same physical colour across all four groups:

| Sprite colour | Logical colours | All map to (example) |
|---------------|-----------------|----------------------|
| +1 | 1, 5, 9, 13 | physical white |
| +2 | 2, 6, 10, 14 | physical red |
| +3 | 3, 7, 11, 15 | physical yellow |

This uses all 16 palette entries: 4 background + 12 sprite-on-background
combinations.

## Actual Blit Code in W3

The sprite engine lives in W3 (loaded at &0E00). The disassembler
misidentifies `ORA ($92),Y` (opcode &11) as data, but the raw bytes
confirm the patterns.

### Direct Blit (&1349-&1389)

Unrolled loop, 6 scanlines per call, Y offsets &00/&08/&10/&18/&20/&28:

```
Per scanline (raw bytes):
B1 A0    LDA ($A0),Y    ; sprite source
29 0F    AND #$0F       ; low nibble only
11 92    ORA ($92),Y    ; merge onto screen
91 92    STA ($92),Y    ; write back
```

Repeated 6 times with Y = &00, &08, &10, &18, &20, &28 (stepping
through character row scanlines). Outer loop decrements X from &14
(20 columns per sprite row). `JSR $138A` advances to the next
character row after each set of 6 scanlines.

### Colour-Remapped Blit (&13C9-&1425)

Same structure but with a lookup table for team colours:

```
Per scanline (raw bytes):
B1 A0       LDA ($A0),Y    ; sprite source
29 0F       AND #$0F       ; low nibble → index (0-15)
AA          TAX
BD 30 26    LDA $2630,X    ; colour remap table (16 bytes)
11 92       ORA ($92),Y    ; merge remapped colour
91 92       STA ($92),Y
```

Same sprite shape data, different 16-byte lookup table → different
team colours. Multiple palettes from one sprite sheet.

### Erase (&156B-&159B and &15BF-&15EB)

Two erase routines for two sprite layers, same pattern:

```
Per scanline:
B1 92    LDA ($92),Y    ; screen byte
29 F0    AND #$F0       ; clear sprite nibble
91 92    STA ($92),Y    ; background restored
```

### Screen Address Advance (&138A)

Advances both sprite source and screen destination pointers after each
character row. Screen wraps within &4000-&7FFF (16KB ring buffer):

```
; Screen pointer wrap:
LDA $92 : SEC : SBC #$08 : STA $92
LDA $93 : CLC : ADC #$02 : AND #$3F : ORA #$40 : STA $93
```

Character row stride = &0200 (512 bytes). Ring buffer: AND #$3F keeps
high byte in range &00-&3F, ORA #$40 forces into &4000-&7FFF.

### Sprite Source Advance

```
; Sprite pointer advance:
LDA $A0 : CLC : ADC #$28 : STA $A0
```

Sprite row stride = &28 (40 bytes per sprite row), matching the screen
width of 40 bytes per scanline (R1=&40=64... actually set in W3 init).

## CRTC Scrolling

W3 uses interrupt-driven CRTC scrolling. The scroll registers R12/R13
are updated via a helper at &1006:

```
1006: STX $FE00    ; select CRTC register
1009: STA $FE01    ; write value
```

Called from the vsync interrupt handler (~&10DC) which sets:
- R5 (vertical fine adjust) for sub-character smooth scroll
- R6 (&1E = 30 displayed rows)
- R12/R13 from ZP variables $D0/$D1 (scroll position)
- R8 (&F0) for interlace/cursor control

A split-screen interrupt switches display parameters mid-frame for
a fixed status bar below the scrolling area (see next section).

## Split-Screen Status Bar

White Light displays a fixed status bar below the scrolling game area.
The game area scrolls via dynamic R12/R13; the status bar stays at a
fixed screen address. This is achieved with a **3-phase timer interrupt
state machine** that reprograms the CRTC mid-frame.

### Interrupt Handler Structure (&102B)

The interrupt handler at &102B reads a phase variable at ZP $80 to
decide what to do:

```
Phase variable $80:
  0 → mid-frame split point (game area just finished displaying)
  1 → short delay after status bar setup
  2 → post-status-bar (blanking period, safe to run game logic)
```

### Phase Transitions

**Vsync (entry at ~&10DC):**

Fires at the start of each frame. Sets up the CRTC for the game area:

```
R5  = fine vertical adjust (sub-character smooth scroll)
R6  = &1E (30 displayed rows for game area)
R7  = vertical sync position
R12 = high byte of scroll position (from ZP $D0)
R13 = low byte of scroll position (from ZP $D1)
R8  = &F0 (interlace/cursor control)
```

Then programs Timer 1 to fire after 30 rows have been displayed,
sets $80 = 0, and returns.

**Phase 0 (~&1055) — Mid-frame split:**

Timer 1 fires when the CRTC has finished drawing the 30 game rows.
The handler reprograms the CRTC for the status bar:

```
R12 = &01 }  Fixed screen start address &0160
R13 = &60 }  (status bar lives at a known location in screen RAM)
R6  = &04    (4 displayed rows for status bar)
R5  = &00    (no fine scroll — status bar is static)
```

Sets a short Timer 1 delay, advances to $80 = 1.

**Phase 1 (~&1089) — Short delay:**

Brief timer to let the status bar finish displaying. Advances to
$80 = 2, sets Timer 1 for the remaining blanking period.

**Phase 2 (~&10A3) — Blanking / game logic:**

Fires during vertical blanking after the status bar. This is the
safe window for game logic that would otherwise cause tearing. The
handler can trigger deferred work (sound updates, input polling, etc.)
before the next vsync restarts the cycle.

### Timing Diagram

```
Vsync ─────────────────────────────────────────────────
  │  Program CRTC for game area (R12/R13 = scroll pos)
  │  R6 = 30 rows, R5 = fine scroll
  │  Start Timer 1 for ~30 rows
  ▼
 ┌─────────────────────────────────┐
 │  Game area (30 rows, scrolling) │  ← CRTC displays from $D0/$D1
 └─────────────────────────────────┘
  │  Timer 1 fires → Phase 0
  │  Reprogram CRTC: R12/R13 = &0160 (fixed)
  │  R6 = 4 rows, R5 = 0
  ▼
 ┌─────────────────────────────────┐
 │  Status bar (4 rows, fixed)     │  ← CRTC displays from &0160
 └─────────────────────────────────┘
  │  Timer 1 fires → Phase 1 → Phase 2
  │  Blanking period: safe for game logic
  ▼
Vsync ─────────────────────────────────────────────────
```

### Key Design Points

1. **No ULA mode switch** — the status bar stays in MODE 2, using the
   same nibble-split palette. Text/numbers are drawn as sprites or
   pre-rendered tiles, not via the MOS character system.

2. **Fixed screen address** — the status bar at &0160 never moves,
   even as the game area's R12/R13 scroll. This means status bar
   content can be updated at any time without worrying about scroll
   position.

3. **Timer-driven, not scanline-counted** — the split point is set
   by Timer 1 duration, calibrated to fire after exactly 30 character
   rows. This is more flexible than counting HSync interrupts.

4. **Render triggered after status bar** — Phase 1 arms User VIA
   Timer2 to fire immediately, which calls the render routine. Phase 2
   runs the music engine. See "Frame Pipeline" below for the full
   execution flow.

### Applicability to Battlefield 6502

We need a status bar showing: team tickets (×2), current class, ammo,
and health. The same technique works on the BBC Master:

- Use Timer 1 to split after our scrolling game area
- Reprogram R12/R13 to a fixed status bar address in LYNNE
- Draw status elements as pre-rendered tile graphics (not VDU text)
- The status bar lives at a known address, updated whenever values
  change — no need to synchronise with scroll position
- On the Master, LYNNE gives us &3000-&7FFF for the game area;
  the status bar could use a small region at the bottom of this range
  or a separate area depending on our scroll buffer layout

## Two Sprite Layers

W3 uses two independent sprite layers with separate ZP pointer pairs:

| Layer | Source ptr | Screen ptr | Used for |
|-------|-----------|------------|----------|
| 1 | $A0/$A1 | $92/$93 | Player / primary sprites |
| 2 | $A6/$A7 | $94/$95 | Enemies / secondary sprites |

Each layer has its own plot and erase routines. The game loop at
~&2170 iterates over entity arrays at &0300+, erasing old positions
then plotting new ones.

## Colour Remap System

White Light uses a 16-byte colour remap table in the remapped blit path
to transform sprite colours without needing separate sprite data per
variant. The same mechanism extends naturally to team colours.

### The Remap Mechanism

The remapped blit at &13C9 adds one extra step compared to the direct
blit at &1349:

```
Direct blit:     LDA sprite / AND #$0F / ORA screen / STA screen
Remapped blit:   LDA sprite / AND #$0F / TAX / LDA $2630,X / ORA screen / STA screen
```

The 16-byte table at &2630 maps each possible low-nibble value (encoding
two pixels' D1,D0 colour bits) to a replacement nibble. Since the low
nibble encodes two 2-bit pixel colours simultaneously, the table operates
on both pixels in a single lookup.

### Static Table in W3 Binary

The 16 bytes at &2630 in the W3 file are:

```
&2630:  00 05 0A 0F 05 05 0F 0F 0A 0F 0A 0F 0F 0F 0F 0F
```

This maps every non-transparent pixel to sprite colour 3 (monochrome).
However, this is the default/initial state in the binary — **the table
is patched per-level** during setup. In actual gameplay, enemies display
the same 2 sprite colours as the player. The active remap table during
gameplay is likely identity or near-identity (colours 1→1, 2→2, 3→3),
preserving the full sprite detail.

### Two Blit Paths

The sprite engine uses two blit routines (see "Actual Blit Code" above):

| Path | Routine | Extra cost | Purpose |
|------|---------|-----------|---------|
| Direct blit | &1349 | — | Primary sprites |
| Remapped blit | &13C9 | +2 per byte (TAX, LDA table,X) | Colour-variant sprites |

Both player and enemies share the same 2-colour sprite data. The
remapped blit path exists for flexibility — a different remap table
could produce monochrome silhouettes, colour-shifted variants, or
team colours without changing the sprite graphics.

### Palette Design

The palette maps 16 logical colours → 8 physical colours. The per-level
palette is loaded by W3's routine at &264B from a 16-byte table at
&26F0 (populated during level setup by the loading chain).

W5 contains a 6-stage fade table at &2302, with Set 0 being the
full-colour game palette:

```
Palette Set 0 (game colours):
  L0  = black      BG colour 0 (space/void)
  L1  = red        Sprite +1 on BG 0
  L2  = green      Sprite +2 on BG 0
  L3  = yellow     Sprite +3 on BG 0
  L4  = blue       BG colour 4 (water/terrain)
  L5  = magenta    Sprite +1 on BG 4
  L6  = cyan       Sprite +2 on BG 4
  L7  = white      Sprite +3 on BG 4
  L8  = white      BG colour 8 (bright terrain)
  L9  = red        Sprite +1 on BG 8
  L10 = green      Sprite +2 on BG 8
  L11 = yellow     Sprite +3 on BG 8
  L12 = blue       BG colour 12 (same as BG 4)
  L13 = magenta    Sprite +1 on BG 12
  L14 = cyan       Sprite +2 on BG 12
  L15 = white      Sprite +3 on BG 12
```

The 4 background colours: black, blue, white, blue. Sprite colours
shift slightly across backgrounds — sprite +1 is red on black/white but
magenta on blue. This is acceptable because enemies are mostly over
black space and the colour shift is subtle.

The 6-stage fade table provides smooth level transitions:
Set 0 = full colour → Set 5 = nearly all black. The palette load loop
at &22E5 (in W5) writes 16 entries per iteration, incrementing through
the 96-byte table until the counter reaches &60.

### Applicability to Battlefield 6502

For our two-team game with nibble-split rendering:

**Palette constraint**: 4 background colours (D3,D2 only) + 3 sprite
colours (D1,D0) = 16 logical colours. Each sprite colour must look
acceptable on every background.

**Team colours via remap tables**: Two different 16-byte remap tables
produce two team colours from the same sprite sheet:

```
Team 1 (red):    remap sprite colours 1,2 → shades of red
Team 2 (blue):   remap sprite colours 1,2 → shades of blue
```

The player's team uses the direct blit (full colour detail), while
the opposing team and AI use the remapped blit (team-coloured).

**Proposed palette** (terrain: black, yellow, green, cyan; teams: red,
white, magenta):

```
              Sprite 0    Sprite 1    Sprite 2    Sprite 3
              (transp)
  BG  0:     black        red         white       magenta
  BG  4:     yellow       red         white       magenta
  BG  8:     green        red         white       magenta
  BG 12:     cyan         red         white       magenta
```

This requires all 4 entries per sprite colour to map to the same physical
colour — constraining the palette to 4+3=7 unique physical colours out
of 8 available. The terrain colours (black, yellow, green, cyan) use
physical colours 0, 3, 2, 6. Sprite colours (red, white, magenta) use
physical colours 1, 7, 5.

Remap table examples (from 2-colour sprites to team monochrome):
- Team Red: map sprite colours 1,2 → red shades (e.g. both → colour 1)
- Team Blue: map sprite colours 1,2 → blue shades (e.g. both → colour 4)

## Half-Width Multicolour Font

MODE 2's standard OS font is 8 pixels wide = 4 bytes per scanline = 20
characters per line. Far too wide and clunky for a game. White Light
implements a custom half-width font: **4 pixels wide × 8 pixels tall**,
giving 40 characters per line — readable text in a 16-colour mode.

### Font Data (&2000)

Each character is 16 bytes, stored in W5's address space at &2000.
The layout matches the BBC Micro's interleaved screen memory:

```
Bytes 0-7:   left column (scanlines 0-7, 2 pixels each)
Bytes 8-15:  right column (scanlines 0-7, 2 pixels each)
Total:       4 pixels wide × 8 scanlines = 16 bytes per character
```

Characters start from ASCII 'A' (0x41). Character index = code - 0x41.
The font includes A-Z plus additional symbols (at least indices 0-32).

### Multicolour Gradient

The font uses 4 MODE 2 colours for a top-to-bottom metallic gradient:

```
Character 'A':                 Colours used:
    44        row 0            4 = blue (top highlights)
  66  66      row 1            6 = cyan (upper body)
  @@  @@      row 2            2 = green (middle body)
  ******      row 3            3 = yellow (bright centre)
  @@  @@      row 4
  66  66      row 5
  44  44      row 6
              row 7 (blank)
```

This uses colours from BOTH nibbles: colour 4 (D2 only, high nibble),
colour 2 and 3 (D1/D0, low nibble), colour 6 = 4+2 (both nibbles).
The font data is NOT nibble-split — it encodes the complete byte value
for each pixel pair.

### Rendering Routine (&15DA in W5)

The text renderer is a simple loop:

```
.print_string               ; &15DA
    LDY #$00
    LDA ($F0),Y             ; load char from string ptr at ZP $F0/$F1
    BEQ done                ; null terminator → return
    INC $F0                 ; advance string pointer
    CMP #$20               ; space?
    BEQ advance_only        ; skip rendering, just advance screen pos

    SEC : SBC #$41          ; char index = ASCII - 'A'
    STA $7C
    LDA #$00                ; calculate font address:
    ASL $7C : ROL A         ;   index × 16 (four shifts)
    ASL $7C : ROL A
    ASL $7C : ROL A
    ASL $7C : ROL A
    ADC #$20                ; + &2000 (font data base)
    STA $7D                 ; $7C/$7D → font bitmap address

    LDY #$0F                ; copy 16 bytes
.copy:
    LDA ($7C),Y             ; font data
    STA ($78),Y             ; → screen
    DEY : BPL copy

.advance_only
    LDA $78 : ADC #$10      ; advance screen ptr by 16 bytes
    STA $78                  ;   (2 CRTC columns = 1 character width)
    ...
    JMP print_string         ; next character
```

Key points:
- **Direct screen write** (STA, not AND/ORA) — overwrites both nibbles
- **16-byte block copy** — simple LDA/STA loop, no masking needed
- **Screen advance = 16 bytes** — 2 CRTC columns per character position
- Works on status bar and high score screen where background is controlled

### Two Text Systems

W5 has two separate text rendering approaches:

| System | Used for | Mechanism |
|--------|----------|-----------|
| Font renderer (&15DA) | High score screen, messages | 16-byte bitmap copy from &2000 |
| Character tile table (&19EB) | In-game status bar | Maps ASCII → tile/sprite IDs |

The tile table at &19EB maps character codes to indices in a graphics
tileset, used for rendering score and status values during gameplay.
This allows individual characters to be updated without redrawing the
entire status bar.

### Applicability to Battlefield 6502

The half-width font technique works directly for our game:

- **Status bar text**: class name, ammo count, health, tickets — all
  need readable text in MODE 2
- **Font storage**: 32 characters × 16 bytes = 512 bytes (A-Z, 0-9,
  plus a few symbols)
- **Rendering**: direct STA to the status bar area in LYNNE. The status
  bar has a fixed background, so overwriting both nibbles is safe.
- **Multicolour**: use team colours or a neutral gradient. Since the
  font writes directly, it can use any of the 16 logical colours.
- **Screen layout**: in our CRTC column layout (8 bytes per column),
  each half-width character = 2 columns = 16 bytes. At 40 chars/line,
  that's 80 CRTC columns = full screen width.

The font data can live in SWRAM alongside level data, or in main RAM
if we have space below &3000. At 512 bytes it's modest.

## What Makes This Fast

1. **No save-under buffers** — background survives in the high nibble
2. **No mask data** — the mask is a constant `#$0F` (plot) / `#$F0`
   (erase), not loaded from memory
3. **Erase is 3 instructions per byte** — LDA/AND/STA, no buffer read
4. **Unrolled inner loops** — 6 scanlines hard-coded per iteration
5. **Colour remap via lookup** — one 16-byte table per team/variant,
   no separate sprite data needed
6. **Two pointer pairs** — can blit two layers without reloading ZP

## Frame Pipeline — IRQ-Driven Rendering

White Light does **not** use the classic game loop pattern of
"wait vsync → read input → update → render → loop". Instead, the
**IRQ handler drives rendering** and the **main loop runs game logic**
asynchronously.

### Interrupt Chain

Each frame triggers a cascade of timed interrupts:

```
VSYNC (System VIA CA1)
  │  &10DC: Program CRTC for game area
  │         R5 = fine scroll, R6 = &1E (30 rows)
  │         R12/R13 = scroll position from $D0/$D1
  │         R8 = &F0
  │         Arm System VIA Timer2 (~2,904 cycles)
  │
  │  ┌──────────────────────────────────────────┐
  │  │ CRTC displays 30 scrolling game rows     │
  │  └──────────────────────────────────────────┘
  ▼
System VIA Timer2 → Phase 0 (&1055)
  │  Reprogram CRTC for status bar:
  │    R12/R13 = &0160 (fixed address)
  │    R4 = &1C, R5 = fine scroll, R8 = &C0
  │  Scan keyboard (JSR &0142)
  │  Arm Timer2 = &35FD (~13,821 cycles)
  │
  │  ┌──────────────────────────────────────────┐
  │  │ CRTC displays status bar (fixed)         │
  │  └──────────────────────────────────────────┘
  ▼
System VIA Timer2 → Phase 1 (&1089)
  │  INC $88 (frame counter — main loop reads this)
  │  Arm User VIA Timer2 = &0001 (fires immediately)
  │  Arm System VIA Timer2 = &FFFF (park until next vsync)
  ▼
User VIA Timer2 → Render routine (&100D → &0F25)
  │  Reentrancy guard ($EF) — skip if already rendering
  │  CLI — re-enable interrupts (allows music + next vsync)
  │  ├── Scroll: update $D0/$D1 (CRTC scroll position)
  │  ├── JSR &1634 — stars: erase old, move, draw new
  │  ├── JSR &16A1 — sprites: erase old, draw new (nibble-split)
  │  ├── JSR &1A47 — bullets: move, collide, draw
  │  └── JSR &2325 — stamp terrain strip (if scrolled this frame)
  ▼
(Back to foreground main loop)
```

### Main Loop (&0EF8) — Foreground

The main loop runs whenever the CPU isn't servicing interrupts:

```
.main_loop
    LDA $EE : BEQ main_loop    ; wait for "active" flag
    LDA $88 : CMP #$02         ; wait for 2+ frames elapsed
    BCC main_loop
    SEI                         ; --- critical section ---
    copy &0E00-&0E2F → &0E30+  ; snapshot entity live → render copy
    copy player state
    CLI                         ; --- end critical section ---
    JSR $2151                   ; game logic: AI, physics, level progression,
                                ;   entity spawning, collision response,
                                ;   double-buffer entity state → &0300+ arrays
    LDA #$00 : STA $88          ; reset frame counter
    JMP main_loop
```

The main loop does **no rendering at all**. It only updates game state
and copies entity arrays for the IRQ render routine to consume.

### Double-Buffering

The IRQ render routine reads from "render copy" arrays at &0E30+ and
&0300+. The main loop writes to "live" arrays at &0E00+. The snapshot
copy happens under SEI so the IRQ can't see a half-written state.

This decouples game logic from rendering: the main loop can take
variable time per tick (complex AI, many entities) without affecting
the render frame rate. The render always uses a consistent snapshot.

### Nested Interrupts

The render routine does `CLI` at &0F29, re-enabling interrupts while
it draws. This allows:
- User VIA Timer1 → music playback (SN76489)
- System VIA Timer2 → split-screen phases
- Vsync → next frame's CRTC setup

The reentrancy guard ($EF) prevents the render from calling itself if
the next vsync/phase chain fires before rendering completes. If the
render is still running when the next trigger arrives, that frame's
render is simply skipped.

### Why This Matters

| | Platform game pipeline | White Light pipeline |
|---|---|---|
| Render timing | Synchronous (after vsync wait) | Asynchronous (IRQ-driven) |
| Main loop does | Input + logic + render | Logic only |
| Render budget | Must finish before next vsync | Can race the beam |
| Frame drops | Stall (visible hitch) | Skip render (logic continues) |
| Input latency | 1 frame (read at top of loop) | <1 frame (read mid-frame) |
| Complexity | Simple | Higher (double-buffer, reentrancy) |

The IRQ-driven approach is better for a game with many entities and
complex AI — the game logic can take a variable number of frames while
the render runs at a steady rate from the last snapshot.

### Applicability to Battlefield 6502

Our game has 24 entity slots, AI state machines, hitscan shooting,
class/weapon logic, and map lookups — all of which take variable time.
The White Light pipeline is a much better fit than the strict
synchronous pipeline we inherited from the platform game pattern:

- **Main loop**: keyboard scan, entity AI, physics, combat, level
  progression. No screen access needed — runs with ACCCON X=0.
- **IRQ render** (after status bar): shadow_screen_on, erase old
  sprites, scroll + stamp, draw new sprites, shadow_screen_off.
  Simpler than White Light — no starfield layer to manage.
  Reads from render copy arrays (below &3000, cached before X=1).
- **Double-buffer**: main loop snapshots entity state to render arrays
  under SEI. Same pattern as our existing `build_render_list`.
- **Graceful frame drops**: if AI takes too long, the render skips a
  frame (entities stay at old positions) but the game doesn't freeze.

The main change: move all screen-touching code (`xor_blit_entity`,
`stamp_strip`, `calc_screen_addr`) into an IRQ-triggered render
routine, and move game logic into the main loop foreground.

## Input Handling

White Light uses a **three-layer** input system: a swappable hardware
handler for movement + fire, hardcoded engine scans for bomb and music
toggle, and a per-frame interrupt routine for analogue joystick ADC.

### Swappable Input Handler (&0110)

W2 copies one of four 66-byte input handler routines to &0110-&0151
based on hardware detection at startup:

| Variant | Source | Hardware | Detection |
|---------|--------|----------|-----------|
| &2250 | Early BBC (OS 0.10) | Analogue joystick (ADC at &FEC0) | $10 = 0 |
| &22C5 | BBC B OS 1.2 / B+ | Analogue joystick (ADC at &FE18) | $10 = 1 |
| &2292 | Master (with joystick) | Digital joystick (User VIA &FE60) | $11 = 1, &FE60 bit 0 = 0 |
| &2307 | Fallback / configured | Keyboard (System VIA &FE4F) | Default |

Each handler has two entry points within the same 66-byte block:

- **&0110** — full input scan, called from the player update at &18ED.
  Stores five boolean flags: ZP $01 (LEFT), $02 (RIGHT), $03 (UP),
  $04 (DOWN), $05 (FIRE).
- **&0142** — per-frame maintenance, called from IRQ Phase 0. For
  analogue joystick variants this alternates ADC channels to read
  X/Y axes into $0A/$0B. For keyboard/digital variants this is
  just RTS.

### Keyboard Handler (Variant &2307)

The keyboard variant scans 5 configurable keys in a tight loop:

```
.scan_keys              ; entry at &0110
    LDA #$00
    LDX #$04
.clear
    STA $01,X           ; clear flags $01-$05
    DEX : BPL clear
    SEI
    LDA #$7F : STA $FE43    ; System VIA DDRA (keyboard scan mode)
    LDA #$03 : STA $FE40    ; select slow data bus
    LDX #$04
.loop
    LDA key_table,X         ; load scan code from &013D+X
    STA $FE4F               ; write to keyboard scan register
    LDA $FE4F               ; read back — bit 7 = pressed
    BPL not_pressed
    STA $01,X               ; store non-zero to flag
.not_pressed
    DEX : BPL loop
    LDA #$0B : STA $FE40    ; restore VIA latch
    CLI : RTS

.key_table                  ; 5 bytes at &013D
    EQUB &61                ; $01 LEFT  = Z
    EQUB &42                ; $02 RIGHT = X
    EQUB &48                ; $03 UP    = :
    EQUB &68                ; $04 DOWN  = /
    EQUB &49                ; $05 FIRE  = RETURN
```

The key table at &013D is patched from user configuration data at
&01A1-&01A4 before the handler is installed.

### Analogue Joystick Handler (Variants &2250/&22C5)

The Phase 0 interrupt calls &0142 every frame to cycle the ADC:

```
.phase0_adc             ; at &0142
    LDA $09             ; toggle (0 or 1)
    EOR #$01 : STA $09
    TAX
    LDA $FEC1           ; read ADC conversion result
    STA $0A,X           ; store to $0A (X axis) or $0B (Y axis)
    STX $FEC0           ; start next conversion on other channel
    RTS
```

The movement scan at &0110 thresholds the analogue values:

```
    LDA $0A : JSR threshold   ; X axis → UP/DOWN
    LDA $0B : JSR threshold   ; Y axis → LEFT/RIGHT
    LDA $FE40 : AND #$10      ; System VIA PB4 = fire button
    EOR #$10 : STA $05        ; invert (active low)
    RTS

.threshold              ; A = analogue value (0-255)
    LDX #$00 : LDY #$00
    CMP #$40 : BCS +    ; < &40 → one direction
    LDY #$01
+   CMP #$C0 : BCC +    ; >= &C0 → other direction
    LDX #$01
+   RTS                  ; X, Y = direction flags
```

Dead zone from &40 to &BF (centre ~&80 is ignored).

### Digital Joystick Handler (Variant &2292)

Reads 5 bits directly from User VIA Port B (&FE60):

```
    LDA $FE60 : AND #$10 : EOR #$10 : STA $02   ; bit 4 = RIGHT
    LDA $FE60 : AND #$08 : EOR #$08 : STA $03   ; bit 3 = UP
    LDA $FE60 : AND #$04 : EOR #$04 : STA $04   ; bit 2 = DOWN
    LDA $FE60 : AND #$02 : EOR #$02 : STA $01   ; bit 1 = LEFT
    LDA $FE60 : AND #$01 : EOR #$01 : STA $05   ; bit 0 = FIRE
    RTS
```

Phase 0 handler is just RTS (no ADC to service).

### Hardcoded Engine Scans

Two additional inputs are scanned directly by the W3 engine at &199F,
outside the swappable handler:

**Bomb (SHIFT, key code &00)** — scanned at &19D3:

```
    LDA $01A5           ; bomb key code = &00 (SHIFT)
    STA $FE4F           ; scan key
    LDA $FE4F           ; bit 7 = pressed
    ...
    AND #$80 : BPL skip ; not pressed
    CMP $18E7 : BEQ skip; edge detect (new press only)
    LDX $06 : BEQ skip  ; no bombs available
    DEC $06             ; use a bomb
    JSR $1C64           ; cascade kill (screen-clearing bomb)
```

The bomb key code at &01A5 is loaded from W2's data table (&1CC9 = &00
= SHIFT). It's configurable in principle but defaults to SHIFT. The
player gets one bomb on each respawn (INC $06 at &19CC).

**Music toggle (f1/f2, key codes &71/&72)** — scanned at &19AA:

```
    LDA #$71 : STA $FE4F : LDA $FE4F   ; scan f1
    BPL + : STA $6F                     ; f1 pressed → $6F = non-zero (music on)
+   LDA #$72 : STA $FE4F : LDA $FE4F   ; scan f2
    BPL + : LDA #$00 : STA $6F          ; f2 pressed → $6F = 0 (music off)
```

### Movement Consumer (&18ED)

The player update code doesn't know or care which hardware handler
ran — it just reads the five boolean flags:

```
    JSR $0110           ; scan input → $01-$05
    LDA $01 : BEQ +     ; LEFT?  → DEC $24 (bounds-checked)
    LDA $02 : BEQ +     ; RIGHT? → INC $24
    LDA $03 : BEQ +     ; UP?    → DEC $25, DEC $25 (double speed)
    LDA $04 : BEQ +     ; DOWN?  → INC $25, INC $25
    LDA $05 : BEQ +     ; FIRE?  → spawn bullets (weapon table lookup)
```

Boundaries: X clamped to &01-&3A, Y clamped to &80-&C0. Vertical
movement is 2 units per frame (twice horizontal speed).

### Input Timing

The three scan layers fire at different points in the frame:

1. **Phase 0 interrupt** (&0142): ADC cycling, runs just after the
   game area finishes displaying. Latency: ~0 frames for analogue.
2. **Render update** (&18ED → &0110): movement + fire, runs inside
   the IRQ-driven render path. Input is read immediately before the
   player position is used for rendering — minimal latency.
3. **Render update** (&199F): bomb + music, runs after movement,
   still inside the render IRQ. Same low latency.

This gives better input latency than scanning at the top of a
synchronous main loop, because the scan happens right before rendering
rather than a full frame earlier.

### Applicability to Battlefield 6502

Our input system already uses the Galaforce-style "scan once, consume
everywhere" pattern. The White Light additions worth adopting:

- **Swappable handler block**: we could support keyboard and joystick
  by copying different 66-byte routines to a fixed address
- **Scan inside the render path**: move keyboard scan from the main
  loop to just before rendering for lower latency
- **Edge detection for special actions**: the bomb uses CMP with
  previous state to detect new presses — prevents auto-repeat on
  held keys

## Memory Map (During Gameplay)

The hybrid mode trick is the key to fitting everything in 32KB:

```
&0000-&00FF  Zero page — game state, pointers, scroll vars
             $80       IRQ phase (0/1/2 for split-screen)
             $92/$93   Screen blit pointer (layer 1)
             $94/$95   Screen blit pointer (layer 2)
             $A0/$A1   Sprite source pointer (layer 1)
             $A6/$A7   Sprite source pointer (layer 2)
             $D0/$D1   CRTC scroll position (→ R13/R12)

&0100-&01FF  Stack + game tables
             Keyboard handler code (copied from level data)
             Entity type property table

&0200-&02FF  MOS vectors (preserved)
             IRQ1V → &102B (game's IRQ handler)

&0300-&05CF  Entity + bullet arrays (~720 bytes)
             Struct-of-arrays: X, Y, type, health, velocity,
             AI state, save-under addresses (16 entity slots,
             32 bullet slots)

&0600-&06FF  Terrain tile map (256 bytes)
             Used for scrolling terrain + bullet collision

&0700-&07FF  Sound data + disc I/O workspace (256 bytes)
             Music channel pointers, sound effect tables

&0800-&0DFF  MOS workspace (reclaimed after *TAPE)
             &0B00-&0CFF  Status bar graphics cache (512 bytes)
             &0A8E-&0AFF  Music engine state (pitch, timers)

&0E00-&26EF  W3 game engine — code + data (6,383 bytes)
             &0E00-&0E8F  Entity position arrays (in-situ)
             &0E90-&0FFF  Main loop + scroll engine
             &1000-&10FF  IRQ handler (3-phase split-screen)
             &1100-&11A8  Screen addr calc + CRTC register table
             &11A9-&14FF  Sprite system (blit, erase, advance)
             &1500-&16FF  Star/particle system
             &1700-&1AFF  Enemy system + AI
             &1AEF-&1FFF  Physics + scoring
             &2000-&24FF  Level progression + rendering
             &2500-&265F  Music engine + palette
             &2630-&263F  Colour remap table (16 bytes)
             &2640-&26EF  Exit handler + strings + misc data

&2700-&3FFF  Level data (loaded from disc, ~6,400 bytes)  ← KEY!
             &2700-&2FFF  Enemy wave patterns (~2,304 bytes)
             &3000-&3FFF  Tile patterns + sprite graphics (~4,096 bytes)
                          ↑ This region is ONLY available because the
                            hybrid mode moved screen to &4000-&7FFF

&4000-&7FFF  SCREEN — 16KB ring buffer
             80 bytes/scanline × 8 scanlines × 25 rows = 16,000 bytes
             CRTC R12/R13 scrolls within this region
             Status bar at fixed CRTC address &0160
             Software wraps with AND #$3F / ORA #$40
```

### How They Fit 6KB of Level Data

The hybrid mode's 4KB saving is the linchpin. Without it, the level
data (&2700-&3FFF) would collide with screen memory. The 6,400 bytes
of per-level data (enemy waves + tile graphics + sprite frames) could
not fit below &3000 alongside the 6,383-byte engine.

```
Standard MODE 2:  Engine (6.2KB) ends at &26EF
                  Screen starts at &3000
                  Gap: &2700-&2FFF = only 768 bytes for level data!

Hybrid mode:      Engine (6.2KB) ends at &26EF
                  Screen starts at &4000
                  Gap: &2700-&3FFF = 6,400 bytes for level data ✓
```

### Module Overlap Trick

The large setup modules (W5: 17,939 bytes, W6: 14,192 bytes) load at
&1200 and extend well into &4000+ — directly into screen memory. This
works because:

1. The screen is blank/disabled during loading
2. The module unpacks its data (graphics, palette, map) into the
   correct RAM locations (&2700-&3FFF for level data, etc.)
3. The screen is cleared and the game starts
4. The overlapping portion of the module code is no longer needed

This lets each level carry ~18KB of data in a single disc load despite
only having ~6KB of permanent level storage.

### MOS Workspace Reclamation

After OSBYTE to disable DFS (*TAPE), White Light reclaims:
- &0300-&07FF: normally DFS workspace, now entity/bullet arrays
- &0800-&0CFF: normally language workspace, now music + status bar cache

Only &0200-&02FF (MOS vectors) is preserved. The game handles its own
disc I/O when chain-loading between levels.

## Developer Talk Notes (Sarah Walker, Acorn/BBC Micro gathering)

Source: `reference/Sarah Walker talking about White Light.md`
(auto-captioned transcript — timecodes approximate, some transcription
errors)

Sarah Walker presented a postmortem of White Light's development at a
BBC Micro community event (circa 2018). Key technical points relevant
to our project:

### Rupture Technique (6:55–10:08)

The split-screen approach is called "rupture" and originates from the
Amstrad CPC demo scene. The core trick: program the CRTC to think it's
displaying **two frames** but only output **one physical frame** to the
TV.

- **First "frame"**: the scrolling game area. R5 (vertical adjust)
  shifts the display up/down for sub-character smooth scrolling. Vsync
  and blanking are suppressed at the end of this frame (no retrace).
- **Second "frame"**: a short frame (one character row high) for the
  score display. R5 cancels the first frame's adjust so the total
  comes to exactly 312 lines. Vsync IS enabled here, triggering the
  actual retrace.
- **Forced blanking** hides the "junk lines" that appear at the top
  of the display during the transition between frames. Without
  blanking, "lines bouncing at the top of the screen" are visible.
  The first timer interrupt turns blanking off just before the game
  area starts displaying.

### MOS Timer Interference (8:20–8:28)

> "that huge involve kicking up the OS cuz the OS tiny [timer]
> routines would cause havoc with it so we turn them off"

Sarah explicitly states that the MOS's own timer interrupt handling
had to be **disabled** because it interfered with the CRTC split
timing. The MOS uses System VIA Timer 1 for its own purposes (keyboard
scanning, cursor flash, sound processing). If these routines run at
the wrong moment — particularly during the narrow window when the CRTC
is being reprogrammed mid-frame — they can delay the split handler
enough to cause visible glitches.

White Light solves this by **hooking IRQ1V** (not IRQ2V) and handling
all interrupts directly, bypassing the MOS interrupt dispatcher
entirely. This is more aggressive than our current approach of hooking
IRQ2V (the MOS's secondary vector for "unrecognised" interrupts).

**Implications for Battlefield 6502**: Our current implementation hooks
IRQ2V and lets the MOS handle Timer 2 dispatch. If we see timing
jitter at the split boundary, we may need to:

1. Hook IRQ1V directly and check for Timer 2 before the MOS gets it
2. Or disable MOS timer processing (OSBYTE 14 to disable event, or
   mask System VIA Timer 1 during the critical display period)
3. Or accept that the Master's MOS is faster than the BBC B's and
   the jitter may be tolerable

### Sprite Rendering as Background Process (16:05–17:51)

Sprite plotting runs as a **free-running background task**, not
synchronised to vsync:

- Game logic (enemies, AI, player, bullets, stars) runs in an
  interrupt routine at 50Hz — specifically the second timer interrupt,
  timed to fire **just after the player sprite has been drawn by the
  CRTC**. This means the player sprite can be plotted during vblank
  and the beam has already passed it before the interrupt fires.
- Between interrupts, the CPU free-runs the sprite erase/plot cycle.
  Each pass picks up the latest entity coordinates from the game logic.
- Enemy update rate varies with the number of on-screen sprites: more
  sprites = slower erase/plot cycle = fewer AI updates. "If it's good
  enough for [Nick] Pelling [Fire Track], it's good enough for me."

This is essentially cooperative multitasking between the IRQ game tick
and the foreground sprite renderer — the same pattern documented in
the "Frame Pipeline" section above.

### Concurrent Programming / Mutexes (17:37–18:06)

The coordinate handoff between game logic (IRQ) and sprite renderer
(foreground) uses a simple mutex:

- Game logic disables the interrupts that trigger its own 50Hz
  processing during critical updates to entity coordinates
- Sprite renderer can't be stopped by disabling interrupts (it runs
  in foreground), so it uses a different mechanism: checking a flag
  to ensure coordinates are consistent before reading them

"It's crude but it works." Sarah notes it was "slightly painful to
implement" but not much more complex than basic SEI/CLI protection.

### Nibble-Split Technique Origin (13:11–13:58)

Sarah confirms the technique came from Fire Track (by Nick Pelling):

> "instead of having full four bits per pixel for your sprites we take
> the four bits which are on the screen buffer and we split them in
> half so the bottom two bits are used to store the background color
> and the top [two] bits are used to store the sprite color"

(Note: she says bottom=background, top=sprite — the inverse of our
convention. The principle is identical; the nibble assignment is
arbitrary as long as the palette matches.)

Key benefits she identifies:
- "Proper masking for free" — transparent pixels automatically
- "Less memory" — 2bpp sprites instead of 4bpp
- Erase is trivial: "just replace the top two bits and leave the
  bottom two bits alone"
- Overlapping sprites "might get the wrong color" but "doesn't really
  matter, doesn't happen often enough"

### Evolution of Sprite Techniques (10:48–13:06)

Sarah went through three approaches before settling on nibble-split:

1. **Full 4bpp sprites with masking + save-under**: correct but slow
   and memory-hungry. Masking was byte-level (not pixel-level),
   producing ugly black borders. Save-under required strict draw/erase
   ordering — getting it wrong left "fountain bits of sprite all over
   the screen."

2. **Background tile redraw for erase**: mark which tiles had sprites,
   redraw those tiles. Eliminated ordering problems but "quite slow."

3. **Nibble-split** (from Fire Track): the final approach. Fast erase,
   no save-under, automatic transparency, consistent colours.

### Flash-White Effect (15:34–15:54)

When a sprite is "hit" it flashes white. With nibble-split, you can't
just OR white into the sprite layer — you need to reconstruct a mask
from the sprite data and use it to set all sprite pixels to colour 3
(white). This required "a lookup table" — the only place where
nibble-split adds complexity compared to the old approach.

### Software Bass Synthesis (19:46–22:22)

Not directly relevant to our project, but notable: White Light
generates bass tones in software by toggling the SN76489's volume
at ~100Hz, using System VIA timers. This produces square waves below
the chip's native frequency limit (~130Hz). A variable duty cycle
(25% instead of 50%) gives a "slightly nice non-BBC kind of sound."
Uses 2% CPU. PWM (varying duty cycle over time) is used on static
screens where no CRTC split is needed (the timers are free).

**This means the System VIA timers are fully committed during
gameplay**: Timer 1 for the CRTC split phases, Timer 2 for the
render trigger. The software bass can only run on menu/transition
screens where the split-screen timer chain isn't active.

### Postmortem (31:53–34:11)

- Game was "probably too long" — could have dropped one of the three
  level cycles and shortened individual levels by a third
- Only 16 enemy patterns total, not enough variety
- Difficulty was contentious: "one person has actually completed the
  game" — Sarah feels this is acceptable but acknowledges feedback
  that it's too hard
- The "evil filing system stuff" (trashing DFS workspace for RAM)
  caused compatibility problems with MMFS on flash storage — a hack
  she "got told off for over and over"
- Development took ~9 years elapsed (2008–2017) but most of that was
  gaps. Active coding would have been "within a year"

## Applicability to Battlefield 6502

Our game also runs in MODE 2 with LYNNE shadow RAM. The nibble-split
technique maps directly:

- Background tiles re-encoded to use only colours 0, 4, 8, 12
  (high nibble only, D3+D2 bits)
- Sprite data re-encoded to use only colours 0-3
  (low nibble only, D1+D0 bits)
- Palette designed so sprite colours +1/+2/+3 look consistent
  across all 4 background colours
- Plot: `LDA sprite / AND #$0F / ORA screen / STA screen`
- Erase: `LDA screen / AND #$F0 / STA screen`

### Trade-offs vs current XOR approach

| | XOR (current) | Nibble-split (White Light) |
|---|---|---|
| Background colours | Full 16 | 4 (high nibble only) |
| Sprite colours | Complementary (uncontrolled) | 3 chosen + transparent |
| Erase cost | 5 instr/byte (LDA/EOR/STA) | 3 instr/byte (LDA/AND/STA) |
| Plot cost | 5 instr/byte (LDA/EOR/STA) | 7 instr/byte (LDA/AND/ORA/STA) |
| Save-under | None | None |
| Mask data | None | None (constant &0F) |
| Sprite appearance | Ghostly/complementary | Solid, consistent |
| Palette control | None | Full (team colours, etc.) |
| Tile re-encoding | Not needed | Required (high nibble only) |

### What we'd need to change

1. Redesign palette: 4 background + 12 combined entries
2. Re-encode tile data: all tiles use only colours 0/4/8/12
3. Update `gen-tiles` tool to emit high-nibble-only tile data
4. Re-encode sprite data: use only colours 0-3
5. Replace `xor_blit_entity` with AND/ORA blit
6. Replace XOR erase with AND #$F0 erase
7. Grenade sprite: same treatment
