# Lessons from https://revs.bbcelite.com/ (Revs on the BBC Micro)

These are distilled notes from Mark Moxon’s “Revs on the BBC Micro” software-archaeology site, focused on BBC Micro–useful engine techniques (not the specific racing/gameplay rules).

Primary index pages:
- https://revs.bbcelite.com/ (site home)
- https://revs.bbcelite.com/deep_dives/ (deep dive index)

## 1) Custom screen modes are a memory tool, not just a look

Source:
- https://revs.bbcelite.com/deep_dives/hidden_secrets_of_the_custom_screen_mode.html

Revs doesn’t just pick an OS mode; it reprograms the 6845 CRTC + Video ULA to create a *shorter* Mode 5-like display:
- Reduce vertical displayed rows (Revs uses 26 rows instead of 32)
- Change screen base (Revs uses `&5A80` as screen start)

Key takeaways:
- A custom screen mode can shrink the screen RAM footprint drastically, freeing memory for code/data.
- If you avoid the OS mode-change path, the OS won’t clear screen RAM — useful when you already unpacked/cached graphics.
- Your “screen base” contract becomes an engine contract; address computations must follow it.

## 2) Split-screen done *really* robustly: multi-section palettes + timing slack

Source:
- https://revs.bbcelite.com/deep_dives/hidden_secrets_of_the_custom_screen_mode.html

Revs splits the screen into **five** sections, switching between Mode 4 and Mode 5 and changing palettes per section.

Two especially reusable ideas:
- **Pipeline your timer programming**: Revs uses User VIA Timer 1 in continuous mode and latches the next countdown value so timing stays regular even if the CPU is momentarily busy.
- **Design palette transitions to tolerate lateness**: Revs switches palettes in “safe” scanline regions where using the wrong palette briefly doesn’t visibly glitch.

General lesson:
- In interrupt-split displays, you don’t only need the correct split time—you want the split to be resilient to occasional interrupt latency.

## 3) Hide code/data in screen memory by controlling the palette

Source:
- https://revs.bbcelite.com/deep_dives/hidden_secrets_of_the_custom_screen_mode.html

The “blue sky” is literally running code/data in screen memory, made invisible by mapping all four colours to blue for that section.

General lesson:
- If you have predictable “flat colour” regions, you can sometimes treat parts of screen RAM as a memory pool (with strong constraints and good documentation).

## 4) A *screen buffer* can be faster than direct drawing if you choose the right representation

Source:
- https://revs.bbcelite.com/deep_dives/drawing_the_track_view.html

Revs draws the scene into a buffer made of vertical columns (“dash data blocks”), then blasts a scanline to the real screen using an *unrolled* sequence of tiny macros.

The crucial trick is that the buffer is not a framebuffer. It’s closer to an **edge + run-length fill encoding**:
- Buffer byte `0` means “repeat previous pixel byte” (so regions fill for free)
- Buffer byte `&55` means “set to black” (since `0` is reserved for repeat)
- Non-zero/non-`&55` means “explicit pixel byte here”

This makes filling “free” during the copy step.

General lessons:
- If your draw step needs to touch every scanline anyway, you can move “fill work” into the copy step by using a buffer encoding that makes fill implicit.
- Using RAM tables for speed is sometimes the right trade (Revs uses a 256-byte `zeroIfYIs55` table to avoid branches).

## 5) Unroll loops when the hot path is fixed-width

Source:
- https://revs.bbcelite.com/deep_dives/drawing_the_track_view.html

Revs draws a line across the screen using 40 consecutive `DRAW_BYTE` macro instances rather than looping.

General lesson:
- On fixed-width inner loops (like 40 columns, 32 tiles, etc.), loop unrolling can be a big win on 6502—especially if it also simplifies addressing modes.

## 6) Object rendering tailored to the buffer: vertical edges, not spans

Source:
- https://revs.bbcelite.com/deep_dives/creating_objects_from_edges.html

Because Revs’s buffer is organised as vertical columns, objects are drawn as vertical edges:
- Draw left edge
- Draw right edge
- Fill between edges (right-to-left) into the buffer
- Then explicitly “restore background” immediately to the right of the object so the subsequent implicit fill works correctly

General lesson:
- Match your rendering primitives to your buffer layout. If your buffer is column-oriented, edge/column operations are naturally cheap.

## 7) Data-driven scaling without sprites: “scaffolds”

Source:
- https://revs.bbcelite.com/deep_dives/scaling_objects_with_scaffolds.html

Revs uses no sprites for cars/signs. Objects are defined as rect parts, and dimensions are references into a per-object “scaffold” (a small set of canonical measurements). To scale an object:
- Scale the scaffold entries (cheap shifts/adds)
- The object parts automatically scale because they’re expressed in scaffold indices

General lessons:
- Store shapes using a small parameter set that scales cheaply.
- If you do need multiple sizes, consider “scale factors + lookup” approaches before you go to full sprite sheets.

## 8) Main loop scheduling + a pragmatic approach to “real time”

Source:
- https://revs.bbcelite.com/deep_dives/scheduling_tasks_in_the_main_loop.html

Revs uses a 16-bit main loop counter and schedules tasks (sound flushes, driver speed recalcs, light timing) by checking bits/modulos.

Interesting tradeoff: the game timers (lap/clock) tick based on loop iterations rather than a hardware timer; Revs then adjusts how much time gets added per tick using per-track parameters to compensate.

General lessons:
- Frame/loop counters are a cheap scheduler.
- If true wall-clock isn’t required, “simulation time” can be derived from loop pace and then tuned/compensated.

## 9) Extreme memory packing: relocate and even self-reassemble

Sources:
- https://revs.bbcelite.com/deep_dives/the_revs_memory_map.html
- https://revs.bbcelite.com/deep_dives/the_jigsaw_puzzle_binary.html

Revs shows two levels of packing:
- A loader-time relocation puzzle to get code/data into the tightest map.
- A runtime “dashboard jigsaw” that copies chunks in/out of screen memory depending on whether you’re in Mode 7 menus or the custom driving mode.

General lessons:
- If you have distinct modes (menu vs game), consider treating them as different memory maps and explicitly moving/overlapping data.
- Copying blocks around can be cheaper than permanently reserving RAM, especially if the transitions are relatively infrequent.

## Particularly reusable Revs ideas for BBC games

- Interrupt-driven split screens can be made artifact-resistant by designing *slack* regions for palette switches.
- A buffer format can be designed so the “blit” does implicit fill, rather than painting every pixel.
- If you own the whole frame pipeline, you can repurpose screen memory as a scratch pool, or even store code there (with care).

## Suggested “next deep dives” on Revs

- Track data design and generation:
  - https://revs.bbcelite.com/deep_dives/the_track_data_file_format.html
  - https://revs.bbcelite.com/deep_dives/building_a_3d_track_from_sections_and_segments.html
- Driving model + feel:
  - https://revs.bbcelite.com/deep_dives/summary_of_the_driving_model.html
  - https://revs.bbcelite.com/deep_dives/the_core_driving_model.html
- Sound:
  - https://revs.bbcelite.com/deep_dives/the_engine_sounds.html

## Gary Partis: Psycastria and Syncron

You mentioned Psycastria and Syncron as good “BBC Andrew Braybrook” candidates.

To do a similar deep-dive-style distillation, I’ll need a good analysis/source/disassembly reference for each (equivalent to the Moxon Elite/Revs sites). If you have preferred links, send them over.

If not, tell me which direction you prefer and I can proceed accordingly:
- gameplay-first (play + take notes on feel/tech constraints)
- code-first (hunt down disassemblies / reconstructed source)
