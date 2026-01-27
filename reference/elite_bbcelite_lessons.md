# Lessons from https://elite.bbcelite.com/ (Elite on the 6502)

This document is a set of distilled notes from Mark Moxon’s “Elite on the 6502” site, focused on broadly useful BBC Micro/Master game-engine techniques (not Elite-specific gameplay).

Primary index pages:
- https://elite.bbcelite.com/ (site home)
- https://elite.bbcelite.com/deep_dives/ (deep dive index)
- https://elite.bbcelite.com/hacks/ (hacks index)

## 1) Frame-time budgeting via a “main loop counter”

Source:
- https://elite.bbcelite.com/deep_dives/scheduling_tasks_with_the_main_loop_counter.html

Elite’s main loop uses a byte counter (`MCNT`) to spread work across iterations.

Key patterns:
- Use a power-of-two modulo check via `AND #n-1`.
  - Example from the article: do something every 8 iterations via `LDA MCNT : AND #7 : BNE skip`.
- Use “compare within bucket” to stagger multiple tasks inside the same period (e.g. run task A at 10/32, task B at 20/32).
- Resetting the counter becomes a control surface (e.g. “don’t spawn for 256 iterations” by setting MCNT to 0 so it immediately underflows on entry).

General lesson:
- Treat frame time as a budget: do mandatory tasks every loop, and schedule non-critical / expensive tasks at lower rates.

## 2) Multi-key input: log pressed states, don’t poll the OS

Source:
- https://elite.bbcelite.com/deep_dives/the_key_logger.html

The BBC MOS keyboard handling (effectively 2-key rollover for “normal” usage) isn’t enough for games with chorded controls.

Elite’s approach:
- Maintain a fixed table (`KL`) of “interesting” controls.
- Scanners set entries to `&FF` while a key is pressed; the table is cleared each scan tick.
- Main loop consumes stable key-state from the logger, rather than relying on “last key pressed” style OS APIs.

General lesson:
- Use an internal “key logger” (a packed per-action bitset or `&00/&FF` bytes) as the contract between input sampling and gameplay.

## 3) Mode 5 pixel layout: precompute bit masks for packed pixels

Source:
- https://elite.bbcelite.com/deep_dives/drawing_colour_pixels_in_mode_5.html

Elite’s write-up is a clear reminder that “2bpp packed pixels” on the BBC are not linear bitpairs.

Key facts (Mode 5):
- Each byte contains 4 pixels.
- Each pixel’s two bits are split across nibbles: pixel 0 uses bits 0 and 4, pixel 1 uses bits 1 and 5, etc.
- Elite uses a precomputed mask table (`CTWOS`) analogous to the Mode 4 `TWOS` masks.

General lesson:
- For any packed pixel format, precompute per-x masks and/or pre-expanded byte patterns (avoid bit-twiddling in inner loops).

## 4) Flicker reduction without double-buffering: interleave erase and draw

Source:
- https://elite.bbcelite.com/deep_dives/flicker-free_ship_drawing.html

The BBC Master version is famous for “flicker-free” ships; the site highlights that this is not primarily a shadow-RAM/double-buffer trick.

Technique:
- Keep a “line heap” describing what’s currently on screen.
- When drawing the new shape, draw one new line, then erase one old line (and overwrite that heap slot with the new line).
- This turns “erase whole object → draw whole object” into a steady per-segment morph, reducing visible flicker.

General lesson:
- If you can represent a drawn object as a list of primitives (lines, spans, sprite rects), you can often reduce flicker by erasing incrementally as you draw.

## 5) BBC Master memory pragmatics: SWRAM, shadow RAM, and zero-page discipline

Source:
- https://elite.bbcelite.com/deep_dives/the_elite_memory_map_master.html

The Master gives you more options, but it’s still easy to lose track of what lives where.

Notable points:
- Sideways RAM bank(s) mapped at `&8000..&BFFF` can store bulk data (blueprints, token tables, etc.).
- Shadow RAM (“LYNNE”) can host screen memory, and parts of main RAM can be bank-switched between main/shadow.
- Elite swaps part of zero page (`&0090..&00EF`) with a copy stored in shadow RAM before filing-system operations.
  - Motivation: keep filing system variables stable while still using ZP aggressively during gameplay.

General lessons:
- Explicitly document a memory map and treat it as an API.
- When interacting with the OS/filing system, assume some parts of ZP and workspace are “owned” by MOS/FS and may need preservation.

## 6) Overlays on disc: swapping binaries at runtime

Source:
- https://elite.bbcelite.com/deep_dives/docked_and_flight_code.html

The disc version gains features by splitting the game into separate “docked” and “flight” binaries (loaded into the same address range).

Notable engineering tricks:
- Use `*RUN` vs `*LOAD` to control whether execution transfers to the loaded code.
- Carefully align the first few bytes of each binary so that vectors/entry stubs line up when one binary is loaded over another.
- It is possible to `*LOAD` code over the currently executing code as long as the return path lands in valid newly-loaded instructions.
- If game workspace overlaps DFS catalogue buffers, you may need to explicitly reload the catalogue before file ops (Elite uses a small `CATD` helper).
- Use different BRK handlers depending on context (flight = fatal error, docked = recover to title/menu, save/load = recover to save/load menu).

General lessons:
- If RAM is tight, code overlays are a viable “memory multiplier” on disc.
- Overlays demand strict discipline: fixed entry stubs, clear ownership of workspaces, and defensive error handling.

## 7) Classic vector graphics primitives: Bresenham + XOR gotchas

Source:
- https://elite.bbcelite.com/deep_dives/bresenhams_line_algorithm.html

Elite uses Bresenham-style stepping with an 8-bit error accumulator scaled by 256.

Notable, very “BBC-specific” detail:
- Elite uses EOR (XOR) drawing for easy erase-by-redraw.
- With XOR drawing, shared endpoints get drawn twice and cancel out, so Elite avoids plotting the first pixel (and similarly omits one endpoint for horizontal lines).

General lesson:
- When using XOR drawing, you must define and enforce a consistent “which endpoints belong to this primitive” rule.

## 8) Early rejection before expensive clipping

Source:
- https://elite.bbcelite.com/deep_dives/line-clipping.html

Elite’s line clipping is a 2-stage pipeline:
- First stage: cheap tests to reject lines that are completely off-screen.
- Second stage: only if needed, do the heavier work to clip endpoints onto the viewport.

General lesson:
- Clip/cull systems should be designed as a cascade: cheapest checks first, expensive math only when it buys you real wins.

## 9) Multiplication: shift-and-add, then specialize ruthlessly

Source:
- https://elite.bbcelite.com/deep_dives/shift-and-add_multiplication.html

The site walks through classic shift-and-add multiplication and explains how Elite ends up with multiple variants.

Useful insights:
- A “clear” reference multiply (full 8×8 → 16) is useful as a baseline.
- Hot paths often only need part of the result (e.g. the high byte), enabling tailored routines.
- Optimisations sometimes trade readability for a handful of instructions saved (Elite has examples like `FMLTU`).

General lesson:
- It’s fine to have multiple multiply routines if you can justify them by usage frequency and constraints.

## 10) Random numbers: repeatable vs non-repeatable streams

Source:
- https://elite.bbcelite.com/deep_dives/generating_random_numbers.html

Elite uses a simple pseudo-RNG built from two short sequences (“main” and “feeder”), with a variant that ignores the input carry.

Key ideas:
- Provide two entrypoints:
  - One that mixes in external state (e.g. carry) for “natural” randomness.
  - One that is deterministic for repeatable effects (explosion patterns, deterministic animations).
- Reseed from game state when appropriate, but be aware that simple RNGs can create correlations if you consume them in predictable sequences.

General lesson:
- Separate “deterministic effect RNG” from “gameplay entropy RNG” to keep both predictable where needed.

## 11) Text compression: tokenisation, recursion, and tiny control codes

Source:
- https://elite.bbcelite.com/deep_dives/printing_text_tokens.html

Elite’s text system is a practical example of extreme memory compression for strings.

Key techniques:
- Store strings as tokenised bytecode rather than literal bytes.
  - “Recursive tokens” expand into token strings that can themselves contain more tokens.
  - Two-letter tokens provide a small dictionary that also feeds procedural name generation.
  - Control codes insert dynamic values (system name, commander name, cash amount, etc.) and change rendering state (case).
- Strings are stored sequentially without an index table; the printer scans to the Nth token to save space.
- A small encoding/obfuscation step is used (EOR with a constant) when storing token bytes.
- Implementation is OS-aware: disc versions ignore a specific control code because `*CAT` prints LF/CR sequences.

General lesson:
- If you need lots of text in small space, build a tiny “string bytecode” with:
  - dictionary tokens
  - formatting control codes
  - (optional) recursive expansion

## Suggested follow-up reading (high value for BBC game work)

- Main loop structure / scheduling (good mental model for frame pipelines):
  - https://elite.bbcelite.com/deep_dives/program_flow_of_the_main_game_loop.html
  - https://elite.bbcelite.com/deep_dives/scheduling_tasks_with_the_main_loop_counter.html
- Rendering and flicker management:
  - https://elite.bbcelite.com/deep_dives/flicker-free_ship_drawing.html
  - https://elite.bbcelite.com/deep_dives/drawing_text.html
- Memory maps (practical constraints, especially on Master):
  - https://elite.bbcelite.com/deep_dives/the_elite_memory_map_master.html
  - https://elite.bbcelite.com/deep_dives/the_elite_memory_map_disc.html
- Data management on disc (overlays):
  - https://elite.bbcelite.com/deep_dives/docked_and_flight_code.html
