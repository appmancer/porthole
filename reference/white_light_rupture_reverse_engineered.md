# White Light Rupture (Split-Screen) — Reverse Engineered Notes

Goal: document *exactly* how White Light v10 implements its fixed status bar + scrolling playfield using CRTC mid-frame reprogramming ("rupture").

Source image:

- `reference/WhiteLight-v10_BBCMicro-DFS.ssd`

This writeup is derived from disassembling the game engine module `$.W3`.

## Files / Load Addresses

From `tools/dfs-cat reference/WhiteLight-v10_BBCMicro-DFS.ssd`:

- `$.W3` load/exec `&0E00`, length 6383 bytes (main engine)
- `$.W2` load/exec `&1100`, length 12032 bytes (game init / hardware setup)

Local extracted binaries used for disassembly:

- `.tmp/wl_W3.bin` (load base `&0E00`)
- `.tmp/wl_W2.bin` (load base `&1100`)

Disassembly outputs (generated):

- `.tmp/wl_W3.disasm.txt`
- `.tmp/wl_W3.scan.io.txt`

## Key Observations

White Light's split-screen is driven by a *multi-source IRQ handler* installed at `IRQ1V`.

Within a single frame:

1) VSYNC IRQ sets CRTC for scrolling playfield and arms System VIA Timer 2 for the split point.
2) System VIA Timer 2 IRQ fires at the split point; handler rewrites CRTC for fixed status bar and arms another Timer 2 delay.
3) A later System VIA Timer 2 IRQ triggers the render kick (via User VIA Timer 2) and arms a final phase.
4) A final System VIA Timer 2 IRQ runs music/game processing during blanking and then parks Timer 2 until next VSYNC.

Rendering is *not* done directly in the System VIA phase ISR; it is triggered by User VIA Timer 2.

MOS interrupt sources are not allowed to run "in the middle" of this timing. White Light installs its own IRQ handler and enables only the interrupts it wants.

## W2: Hardware Mode + CRTC Tables (Raw)

W2 sets up the unusual video mode (ULA pixel format + CRTC timing) by writing a packed table of `(CRTC_reg, value)` pairs.

The table format:

- Read a byte = register number
- If bit 7 set (`>= &80`), stop (terminator)
- Next byte is the value to write to `&FE01`

Two notable sequences in W2 (`.tmp/wl_W2.disasm.txt`):

1) At `&1AF5`, it writes pairs from `&1D6D` until terminator, then sets `&FE20 = &4B`.
2) At `&1BF3`, it sets `&FE20 = &14` and writes pairs from `&1D52` until terminator.

The `&1D52` table bytes (as shown by the disassembly) are:

```
R0=&7F  R1=&50  R2=&62  R3=&28
R4=&26  R5=&00  R6=&20  R7=&22
R8=&01  R9=&07  R10=&00
R13=&00 R12=&06
```

The `&1D6D` table bytes are:

```
R0=&3F  R1=&28  R2=&33  R3=&24
R4=&1E  R5=&02  R6=&19  R7=&1C
R8=&93  R9=&12  R10=&72 R11=&13
R12=&28 R13=&00
```

These tables are the most direct "what did she program" reference for CRTC register values.

## CRTC Write Helper

W3 contains a helper used everywhere to write CRTC registers:

```
1006: STX &FE00    ; select CRTC register
1009: STA &FE01    ; write value
```

All CRTC writes below are via `JSR &1006`.

## CRTC Start Address Units (Important)

On the BBC Micro video hardware, the CRTC's start address (`R12/R13`) is in **MA units** (character addresses), not raw byte addresses.

Displayed byte address is:

```
byte_addr = (MA << 3) + RA
```

So when White Light sets `R12/R13 = &01/&60`, that is `MA = &0160`, which corresponds to a byte base of `&0160 << 3 = &0B00`.

This matches the earlier analysis that White Light keeps status-bar graphics in the MOS workspace region around `&0B00`.

## IRQ Vector Hook

During init (near `&0E7A`), W3 copies the old vector from `&0204/&0205` and installs a new handler:

- Old `IRQ1V` stored to ZP `$81/$82`
- New `IRQ1V = &102B`

Disassembly excerpt (`.tmp/wl_W3.disasm.txt`):

```
0E7A: LDA &0204 : STA $81
0E7F: LDA &0205 : STA $82
0E84: LDA #$2B  : STA &0204
0E89: LDA #$10  : STA &0205
```

## Interrupt Enable / VIA Setup (early init)

W3 disables interrupts, then re-enables a specific set:

```
0E53: LDA #$7F : STA &FE4E : STA &FE6E    ; disable all (System VIA IER, User VIA IER)
0E5B: LDA #$A2 : STA &FE4E                ; enable System VIA: CA1(vsync) + T2
0E60: LDA #$A0 : STA &FE6E                ; enable User VIA: T2 (render trigger)
```

It also configures User VIA ACR (Timer 1 continuous interrupt mode, PB7 output disabled):

```
0E6D: LDA &FE6B
0E70: AND #$DF
0E72: ORA #$40
0E74: STA &FE6B
```

White Light also uses User VIA Timer 1 (separate from the split) for audio timing; the IRQ handler checks for it first.

## The IRQ Dispatcher at &102B

The handler at `&102B` decides which IRQ source fired.

Order matters; it checks in this order:

1) User VIA Timer 1 (bit 6) -> jumps to `&23E0`
2) System VIA CA1 (VSYNC)   -> jumps to `&10DC`
3) User VIA Timer 2 (bit 5) -> jumps to `&100D` (render trigger)
4) Otherwise it treats it as System VIA Timer 2 and runs the split-screen phase machine.

Excerpt:

```
102B: LDA &FE6D
1030: AND &FE6E
1033: AND #$40
1035: BNE &23E0      ; User VIA T1

103A: LDA &FE4D
103D: AND #$02
103F: BNE &10DC      ; System VIA CA1 (vsync)

1041: LDA &FE6D
1044: AND #$20
1046: BNE &100D      ; User VIA T2 (render)

1048: LDA #$20
104A: STA &FE4D      ; clear System VIA T2
104D: LDX $80        ; phase variable
...
```

## The Phase Variable ($80)

ZP `$80` selects which System VIA Timer 2 phase runs:

- `$80=0` -> Phase 0 at `&1055` (do the split -> status bar)
- `$80=1` -> Phase 1 at `&1089` (short delay + kick render)
- `$80=2` -> Phase 2 at `&10A3` (blanking / music / park)

Dispatch logic:

```
104D: LDX $80
104F: DEX
1050: BEQ &1089    ; $80 == 1
1052: DEX
1053: BEQ &10A3    ; $80 == 2
1055: ...          ; $80 == 0
```

## VSYNC Handler (&10DC) — Set Up Scrolling Playfield

When System VIA CA1 triggers, White Light programs:

- System VIA Timer 2 = `&0B58` (2904 cycles) to schedule the mid-frame split.
- CRTC regs for the scrolling playfield:
  - `R5` set to `8 - fine_scroll` (sub-character smooth scroll)
  - `R6 = &1E` (30 displayed rows)
  - `R7 = &FF` (suppress VSYNC during the playfield)
  - `R12/R13` from scroll position bytes `$D1/$D0`
  - `R8 = &F0`
- `$80` cleared back to 0 (ready for Phase 0 when Timer 2 fires).

Excerpt:

```
10E1: STA &FE48        ; T2 low  = &58
10E6: STA &FE49        ; T2 high = &0B  => &0B58

10EF: LDX #$05
10F1: LDA #$08
10F2: SEC
10F3: SBC $87
10F4: JSR &1006         ; R5 = 8 - $87

10F7: INX
10F8: LDA #$1E
10FA: JSR &1006         ; R6 = &1E

10FD: INX
10FE: LDA #$FF
1100: JSR &1006         ; R7 = &FF

1103: LDX #$0C
1105: LDA $D1
1107: JSR &1006         ; R12
110A: INX
110B: LDA $D0
110D: JSR &1006         ; R13

1110: LDX #$08
1112: LDA #$F0
1114: JSR &1006         ; R8 = &F0

1117: LDA #$00
1119: STA $80
```

## Phase 0 (&1055) — Switch to Fixed Status Bar

Triggered by System VIA Timer 2 after `&0B58` cycles.

Actions:

- Set `R8 = &C0`.
- Arm System VIA Timer 2 = `&35FD` (13821 cycles) for Phase 1.
- Increment `$80` -> 1.
- Program CRTC for status bar:
  - `R4 = &1C`
  - `R5 = $87`
  - `R12/R13 = &0160` (fixed screen start address)
- Call `JSR &0142` (input maintenance; no-op on keyboard builds).

Excerpt:

```
1055: LDX #$08
1057: LDA #$C0
1059: JSR &1006         ; R8 = &C0

105C: LDA #$FD : STA &FE48
1061: LDA #$35 : STA &FE49   ; T2 = &35FD
1066: INC $80

1068: LDX #$04
106A: LDA #$1C
106C: JSR &1006         ; R4 = &1C

106F: LDX #$05
1071: LDA $87
1073: JSR &1006         ; R5 = $87

1076: LDX #$0C
1078: LDA #$01
107A: JSR &1006         ; R12 = 1
107D: INX
107E: LDA #$60
1080: JSR &1006         ; R13 = &60  => start=&0160

1083: JSR &0142
```

## Phase 1 (&1089) — Short Delay + Kick Render

Triggered by System VIA Timer 2 after `&35FD` cycles.

Actions:

- Arm System VIA Timer 2 = `&037D` (893 cycles) for Phase 2.
- Increment `$80` -> 2.
- Increment `$88` (frame counter used by the main loop).
- Arm User VIA Timer 2 = `&0001` to fire immediately.
  - That User VIA Timer 2 IRQ runs the render routine (`&0F25`) via handler `&100D`.

Excerpt:

```
1089: LDA #$7D : STA &FE48
108E: LDA #$03 : STA &FE49   ; T2 = &037D

1093: INC $80
1095: INC $88

1097: LDA #$01 : STA &FE68
109C: LDA #$00 : STA &FE69   ; User VIA T2 = &0001
```

## Phase 2 (&10A3) — Blanking Window + Park

Triggered by System VIA Timer 2 after `&037D` cycles.

Actions:

- `$80 = 0` (reset phase machine)
- Park System VIA Timer 2 by loading `&FFFF`
- Program additional CRTC registers (`R4=8`, `R6=1`, `R7=4`) to shape the end-of-frame period (this is part of the "rupture" trick: the CRTC is made to believe it is outputting two frames).
- Runs music-related routines with interrupts enabled, then returns.

Excerpt:

```
10A3: LDA #$00 : STA $80
10A7: LDA #$FF : STA &FE48
10AC: LDA #$FF : STA &FE49

10B1: LDX #$04
10B3: LDA #$08 : JSR &1006   ; R4
10B8: LDX #$06
10BA: LDA #$01 : JSR &1006   ; R6
10BF: INX
10C0: LDA #$04 : JSR &1006   ; R7

... CLI ... JSR &25BB ... JSR &2498 ... SEI ...
```

## Render Trigger (User VIA Timer 2) at &100D

When User VIA Timer 2 fires, the handler:

- clears the User VIA Timer 2 IFR flag by writing `&20` to `&FE6D`
- uses a reentrancy guard `$EF`
- calls the render routine at `&0F25`

Excerpt:

```
100D: STA &FE6D       ; clear User VIA T2
1010: LDA $EF : BNE skip
1014: LDA #$01 : STA $EF
...
101B: JSR &0F25        ; render
...
1021: LDA #$00 : STA $EF
1025: JMP &10D7        ; common RTI path
```

## What To Copy Into Our Project

If we want "exactly like White Light" behaviour, the most important things to copy are:

- VSYNC sets up playfield and arms a one-shot timer to the split point.
- System VIA Timer 2 runs a 0/1/2 phase machine to:
  - do the split
  - schedule a later phase
  - kick render via a separate timer
  - provide a safe blanking window and park
- Render is triggered by a separate timer source (User VIA Timer 2) and has a reentrancy guard.
- Keep MOS out of the critical path: install our own IRQ1V and enable only the specific interrupt sources we need.

The raw timing constants in White Light (`&0B58`, `&35FD`, `&037D`) are calibrated for White Light's exact CRTC configuration and desired split line.
We should treat them as a reference, not guaranteed values for our configuration.
