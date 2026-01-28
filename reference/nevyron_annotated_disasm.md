# Nevyron: Annotated Disassembly (Key Sprite/Update Routines)

This is a **targeted, annotated** disassembly focusing on how Nevryon updates lots of sprites per update.

Conventions:
- Addresses are **runtime** addresses (i.e. after `$.CODE` is relocated to `&1100`).
- `$.CODE2` is assumed to run at `&2800`, `$.CODE3` at `&3300`.
- The core render pipeline is:
  - `JSR &1236` compute destination screen address into ZP `&76/&77`.
  - write blit source pointer into `&1194/&1195` (self-modifies `LDA &FFFF,X`).
  - `JSR &1173` blit `(height_blocks,width_bytes)`.

---

## `$.CODE &1173` — Core Variable-Size Bitmap Blitter

```asm
1173: 86 74     STX $74
1175: 84 75     STY $75
1177: 84 78     STY $78
1179: A2 00     LDX #$00
117B: A5 79     LDA $79
117D: C9 01     CMP #$01
117F: F0 03     BEQ $1184
1181: A6 75     LDX $75
1183: CA        DEX
1184: A5 76     LDA $76
1186: 29 F8     AND #$F8
1188: 85 70     STA $70
118A: A5 77     LDA $77
118C: 85 71     STA $71
118E: A5 76     LDA $76
1190: 29 07     AND #$07
1192: A8        TAY
1193: BD FF FF  LDA $FFFF,X
1196: 91 70     STA ($70),Y
...
11A4: C0 08     CPY #$08
11A6: D0 EB     BNE $1193
11A8: A5 70     LDA $70
11AA: 69 3F     ADC #$3F
11AC: 85 70     STA $70
11AE: A5 71     LDA $71
11B0: 69 01     ADC #$01
11B2: 85 71     STA $71
...
11BE: 18        CLC
11BF: A5 76     LDA $76
11C1: 69 08     ADC #$08
11C3: 85 76     STA $76
11C5: 90 02     BCC $11C9
11C7: E6 77     INC $77
...
11D0: C6 74     DEC $74
11D2: D0 B0     BNE $1184
11D4: 60        RTS
```

- **Source stream**: `LDA $FFFF,X` is the heart: callers patch its operand bytes at `&1194/&1195` to point at the current sprite.
- **Destination**: uses ZP `&76/&77` and writes to bitmapped screen memory with the classic MODE-5-ish interleaving.
- **Scanline stepping**: when `Y` reaches 8, it adds `&140` to the destination by `ADC #&3F` + carry into high (`+&01`).
- **Block stepping**: when a block finishes, it adds `+8` to `&76/&77` and repeats for `height_blocks`.

Why this matters: almost every “sprite” update becomes a cheap parameter setup + `JSR &1173`.

---

## `$.CODE &1236` — Screen Address Calculator

```asm
1236: 98        TYA
1237: 49 FF     EOR #$FF
1239: A8        TAY
123A: 29 07     AND #$07
123C: 85 77     STA $77
123E: 98        TYA
123F: 4A        LSR A
1240: 4A        LSR A
1241: 4A        LSR A
1242: A8        TAY
1243: B9 09 12  LDA $1209,Y
1246: 85 76     STA $76
1248: A5 77     LDA $77
124A: C9 08     CMP #$08
124C: F0 04     BEQ $1252
124E: 65 76     ADC $76
1250: 85 76     STA $76
1252: B9 1F 12  LDA $121F,Y
1255: 85 77     STA $77
1257: 8A        TXA
1258: F0 11     BEQ $126B
...
126B: 60        RTS
```

- Inputs: `X` = x coordinate (byte-ish), `Y` = y coordinate.
- It **flips Y vertically** (`EOR #&FF`) before mapping through tables at `&1209`/`&121F`.
- Output: ZP `&76/&77` is the base destination for the blitter.

---

## `$.CODE &13D1` — Main “Tick”: 4 Sub-Ticks, Lots of Blits

```asm
13D1: 20 AA 25  JSR $25AA
...
1438: A9 00     LDA #$00
143A: 85 8F     STA $8F
143C: AD 51 20  LDA $2051
143F: F0 36     BEQ $1477
1441: 20 A2 2A  JSR $2AA2
1444: 20 E7 29  JSR $29E7
1447: 20 D7 28  JSR $28D7
144A: E6 8F     INC $8F
144C: 20 BC 13  JSR $13BC
144F: 20 EB 1A  JSR $1AEB
1452: 20 6C 12  JSR $126C
...
145D: 20 93 26  JSR $2693
...
1471: A5 8F     LDA $8F
1473: C9 04     CMP #$04
1475: 90 C5     BCC $143C
1477: 60        RTS
```

- The key idea: the “tick” runs **4 sub-ticks**, and each sub-tick calls several sprite drivers.
- This naturally spreads heavy sprite work across time, instead of trying to do “everything once per frame”.

---

## `$.CODE2 &29E7` — 6-Entry Table = 6 Guaranteed Blits

```asm
29E7: A2 09     LDX #$09
29E9: A0 5F     LDY #$5F
29EB: 20 36 12  JSR $1236
29EE: A2 00     LDX #$00
29F0: BD 02 2A  LDA $2A02,X
29F3: 8E D3 28  STX $28D3
29F6: 20 08 2A  JSR $2A08
...
29FD: E0 06     CPX #$06
29FF: D0 EF     BNE $29F0
2A01: 60        RTS
```

- Loops `X=0..5` and calls `&2A08` each time.
- So it’s a fixed upper bound: **6 blits per call**.

### `$.CODE2 &2A08` — Turn a Tile Index into a Sprite Pointer

```asm
2A08: 8E D3 28  STX $28D3
2A0B: 0A        ASL A
2A0C: 0A        ASL A
2A0D: 0A        ASL A
2A0E: 18        CLC
2A0F: 69 60     ADC #$60
2A11: 8D 94 11  STA $1194
2A14: A9 3A     LDA #$3A
2A16: 8D 95 11  STA $1195
2A19: A2 01     LDX #$01
2A1B: A0 08     LDY #$08
2A1D: 4C 73 11  JMP $1173
```

- `A` is a small index; it multiplies by 8 and adds `&60` → low byte into `&1194`.
- High byte is fixed `&3A`, so the source is `&3A60 + index*8`.
- This is essentially “tile blit from an atlas page”, and it ends in a tail-call to the blitter.

---

## `$.CODE2 &2AA2` — Two-Object Update: Erase→Move→Draw

```asm
2AA2: A2 00     LDX #$00
2AA4: BD 9A 2B  LDA $2B9A,X
2AA7: C9 FF     CMP #$FF
2AA9: F0 03     BEQ $2AAE
2AAB: 20 C4 2A  JSR $2AC4
...
2AB7: 20 C4 2A  JSR $2AC4
2ABA: A2 00     LDX #$00
2ABC: 20 48 2B  JSR $2B48
2ABF: A2 01     LDX #$01
2AC1: 4C 48 2B  JMP $2B48
```

Inside `&2AC4` we see the key pattern:
- **erase old** with `source=&7D80` (blank sprite), `1x6`.
- update coords.
- **draw new** with `source=&3AB0`, `1x6`.

This makes each small moving object cost ~2 blits, no save-under management.

---

## `$.CODE &1AEB` — Entity List Loop (Up to 8 Entities)

```asm
1AEB: A2 08     LDX #$08
1AED: BD 6B 1A  LDA $1A6B,X
1AF0: D0 06     BNE $1AF8
1AF2: CA        DEX
1AF3: D0 F8     BNE $1AED
...
1B6B: 20 36 12  JSR $1236
1B6E: 20 E3 1B  JSR $1BE3
1B71: A2 04     LDX #$04
1B73: A0 18     LDY #$18
1B75: 20 73 11  JSR $1173
...
```

- Scans slots `X=8..1` and processes non-zero entries.
- Typical active entity path ends in **one large draw blit**: `blocks=4`, `width=24`.
- There is also an erase path of the same size when an entity is cleared.

### `$.CODE &1BE3` — Select Entity Sprite Pointer

```asm
1BE3: AE F5 16  LDX $16F5
1BE6: BD 6B 1A  LDA $1A6B,X
1BE9: C9 0A     CMP #$0A
1BEB: 90 0E     BCC $1BFB
...
1BFB: AA        TAX
1BFC: BD 0C 1C  LDA $1C0C,X
1BFF: 8D 94 11  STA $1194
1C02: BD 13 1C  LDA $1C13,X
1C05: 8D 95 11  STA $1195
1C08: AE F5 16  LDX $16F5
1C0B: 60        RTS
```

- This routine’s job is just: **set `&1194/&1195`** based on an entity type/state.
- The draw code that calls it can then blindly do `JSR &1173`.

---

## `$.CODE &2693` — Single Animated Object (1 Blit, Sometimes +Erase)

```asm
2693: AD 92 26  LDA $2692
2696: D0 01     BNE $2699
2698: 60        RTS
...
26B6: A2 00     LDX #$00
26B8: AC 91 26  LDY $2691
26BB: 20 36 12  JSR $1236
26BE: A9 80     LDA #$80
26C0: 8D 94 11  STA $1194
26C3: A9 7D     LDA #$7D
26C5: 8D 95 11  STA $1195
26C8: A2 03     LDX #$03
26CA: A0 10     LDY #$10
26CC: 4C 73 11  JMP $1173
...
2703: A9 90     LDA #$90
2705: 8D 94 11  STA $1194
2708: A9 40     LDA #$40
270A: 8D 95 11  STA $1195
270D: 4C 73 11  JMP $1173
```

- State machine chooses a sprite source (mostly `&40xx` / `&47xx`) and then tail-calls the blitter.
- Collision/shutdown paths erase with `&7D80`.

---

## `$.CODE2 &28D7` — Small Sprite With Proximity Gating

```asm
28DF: AE 72 29  LDX $2972
28E2: AC 73 29  LDY $2973
28E5: 20 36 12  JSR $1236
28E8: A9 80     LDA #$80
28EA: 8D 94 11  STA $1194
28ED: A9 7D     LDA #$7D
28EF: 8D 95 11  STA $1195
28F2: A2 02     LDX #$02
28F4: A0 0C     LDY #$0C
28F6: 20 73 11  JSR $1173
...
293F: ...
2953: 8D 94 11  STA $1194
2956: A9 38     LDA #$38
2958: 8D 95 11  STA $1195
295B: A2 02     LDX #$02
295D: A0 0C     LDY #$0C
295F: 20 73 11  JSR $1173
```

- Always does an **erase** blit of size `2x12`.
- If in-range, does a **draw** blit of size `2x12` from an animation frame (page `&38`, low byte computed from `&2974`).

---

## Takeaway: why the sprite updates scale

- Everything is “set pointer + `JSR &1173`”.
- Many sprite systems are fixed-size loops with hard caps (6-entry table, 2-object array, 8-slot entity list).
- Work is spread across 4 sub-ticks, so worst-case sprite loads are amortized.
