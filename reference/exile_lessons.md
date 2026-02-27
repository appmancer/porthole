# Lessons From Exile (Superior, 1988)

Reference disassembly:
- `reference/exile-standard-disassembly.txt` (downloaded from https://www.level7.org.uk/miscellany/exile-standard-disassembly.txt)

Exile is an extreme “all systems at once” Beeb engine: 4-way scrolling, lots of moving objects, procedural world, and a tight sound driver. We are not trying to clone it, but it is a great source of proven patterns.

## 1) Video Mode, Screen Placement, and Why It Matters

### 1.1 Mode

Exile explicitly sets the Video ULA control register to `&14`:
- `&60fe  STA &fe20 ; video ULA control register` with value `&14` (`reference/exile-standard-disassembly.txt` around `&60ee..&6101`)

`&14` selects MODE 2 pixel format (16 colours) with cursor disabled.

### 1.2 Screen memory base and CRTC start

Exile uses a circular screen/work region at `&6000..&7FFF`:
- the wipe loop comment says “Wipe `&6000 - &7fff`” (`&01d0..&01e3`)
- the CRTC start address writer adds `#&0c` (“`&6000 / &800`”) when converting a byte offset into `R12/R13` (`&1f6c..&1f90`)

CRTC start address is set from a software “screen start offset” (`&b0/&b1`):
- `&1f6e..&1f7b` shifts `screen_start_offset` right by 3 (divide by 8)
- `&1f7d` adds `&0c`
- then programs `R12/R13` via `&fe00/&fe01`.

Takeaway:
- Keep your scroll math in *byte offsets* and only convert to `R12/R13` at the edge.
- A ring buffer window in RAM makes both scrolling and wraparound plotting simpler (see sprites below).

## 2) Scrolling: Logical vs Physical, and “Scroll One Axis at a Time”

### 2.1 Physical scroll via CRTC start address

Exile’s sprite plotting calls `consider_setting_crtc_start_address` (`JSR &1f58`) while calculating screen addresses (e.g. `&0fd7`).

`consider_setting_crtc_start_address`:
- waits for v-sync using a `vsync_state` counter (`&1f60..&1f69`)
- then calls `set_crtc_start_address` at `&1f6c`.

This is “hardware” scrolling: the framebuffer doesn’t move; the display window moves.

### 2.2 Scroll state is kept in fractions and “tile sections”

The disassembly shows a clear “scroll planner”:
- `consider_how_to_scroll_screen` around `&1532` computes `screen_tile_sections_to_scroll_x` (`&cf`) and `screen_tile_sections_to_scroll_y` (`&d1`.

It strongly biases toward scrolling only one axis per step:
- compares absolute x vs y scrolling required and chooses the dominant axis.

Scroll is quantified in “sections” per tile:
- comment: “In `&20` fraction sections, eight per tile” (see around `&1535`).

### 2.3 Only redraw newly exposed tiles

Before a scroll step, Exile calls `prepare_screen_for_scrolling` (`JSR &3684`) (seen e.g. `&15bd` and `&1df2`).

The pattern is the familiar one:
- decide which edge will be revealed
- wipe/clear that strip
- compute which tiles enter view
- plot only that strip.

Takeaway:
- For a 4-way scroller on Beeb, “incremental edge plot” is the winning strategy.
- Planning scroll in fixed sub-tile units keeps edge plotting and object clipping manageable.

## 3) Sprites: Plotting, Clipping, and “Avoid Full Masks”

### 3.1 Sprite source and conversion

From the disassembly notes:
- all sprites are generated from a “128x81 four colour bitmap” stored at `&53ec`.

At plot time, Exile converts 2bpp sprite data into MODE 2 byte patterns.
You can see this in the hot inner loop:
- `plot_sprite_row_loop` at `&1020` converts one source byte into 4 bytes worth of pixel data by extracting pixel pairs and looking up precomputed byte patterns.

This is a classic trade:
- store sprites compactly (2bpp)
- expand during plotting to match the packed screen format.

### 3.2 Stack as a scratch buffer

Exile pushes the converted row data to the 6502 stack, then immediately streams it to screen:
- pushes “right pixel” then “left pixel” bytes repeatedly (`PHA` sequences at `&102d`, `&1036`, `&1042`, `&104b`)
- then reads back from `&0100,X` while stepping across the row (`&105c..&106a`).

Benefit:
- avoids a separate row buffer in RAM.

### 3.3 Robust clipping and scroll-aware plotting

`consider_replotting_sprite` at `&0d4d` computes screen-relative coords, cropping, and offscreen flags for both current and previous sprite.

Notable:
- it computes `offscreen_flags` for 4 edges (prev/current × x/y) and uses that to skip work.
- when scrolling, it applies a `screen_scrolling_offset_*` to *previous* sprite positions so erase/unplot matches the shifted viewport (see `&0dbf..&0dc9`).
- it has a special path for “scrolling onto the screen” where it plots only the newly revealed portion of the sprite instead of full replot (`&0e50..&0eb6` etc).

Takeaway:
- If you want fast scroll + many sprites, you need scroll-aware sprite bookkeeping (at least for erasing/replotting) or you get seams.

### 3.4 Foreground/background plotting toggle (pseudo-layering)

There’s a self-modifying toggle at `toggle_sprite_plotting_mode` (`&10f0`) that swaps the opcodes used in the plot loop.

When plotting “background”, it conditionally avoids overwriting where “foreground” is present:
- see the comments around `&1064..&1067` explaining how the opcode swap changes behaviour.

Takeaway:
- This is a practical way to get “tiles over/under sprites” behaviour without a full compositor.

## 4) Entity System: Three Tiers of Persistence

From the disassembly notes:
- Primary list: 16 slots (active / near-screen)
- Secondary list: 32 slots (persisted off-screen)
- Tertiary list: fixed-to-location spawners (nests, turrets, etc.).

The code makes this real:
- `update_objects` starts at `&1a0b` and iterates the primary object arrays (e.g. `objects_x` at `&0891`, `objects_y` at `&08b4`, etc.), copying per-object fields into ZP “this_object_*” working vars.
- update routines are table-driven:
  - `call_object_update_routine` / `call_tile_update_routine` at `&19ea..&1a0a` builds the routine address from low/high tables (`&03b9` / `&0432`).

Takeaway:
- For a metroidvania, this primary/secondary/tertiary model is exactly what you want: stable world state without updating everything every frame.

## 5) Palette Layering (What It Is Here)

Exile uses MODE 2’s 16 logical colours but treats them as two banks:
- 0..7 for “objects”
- 8..15 for “tiles”.

The disassembly notes call these “upper and lower case letters” to keep the two sets visually distinct.

This is not nibble-split (White Light). It’s a convention + plotting support:
- keep tiles and objects from accidentally sharing colour indices
- allow palette swaps for one group without unintentionally recolouring the other.

Also note Exile uses time-sliced palette effects:
- IRQ handler briefly changes colour 0 for waterline shimmer (`&12b6..&12c5`).

Takeaway:
- If you stay in MODE 2, reserving colour ranges by “role” is a strong readability tool.

## 6) Sound: Two Envelopes (Volume + Frequency) and Distance Attenuation

Sound is updated from the IRQ path:
- `&1320..&1390` updates channels, runs envelope steps, and writes to the sound chip.

Envelope model:
- two envelopes per channel: one for volume, one for frequency (`update_sound_envelope` at `&1399`).
- envelopes include stage duration and loop counts; loop start is stored so it can jump back.

`play_sound` uses inline 4-byte parameter blocks (after the call site):
- specifies envelope + initial value + duration for volume and frequency.

Distance attenuation:
- `play_sound` calls `get_object_distance_from_screen_centre` and reduces volume for distant sounds (`&1415..&1421`).
- it also tries to pick a free channel, or a quieter channel, and suppresses far-away duplicates.

Takeaway:
- This is a great pattern for action games: SFX are cheap, spatially plausible, and don’t monopolize channels.
- For our own engine, this pairs well with studying White Light’s music/SFX coexistence.

## 7) Procedural Landscape Generation: Algorithm + Small Hand-Authored Overlay

The landscape is a 256x256 tile space:
- the algorithm provides the bulk terrain
- map data at `&4fec` overlays “set-piece” regions.

Core routine:
- `get_tile_and_check_for_tertiary_objects` at `&1715` calls `get_tile` (`&178d`) then optionally checks for tertiary objects, and may replace the tile with a tertiary object tile or a “feature” tile.

`get_tile` uses multiple derived functions of (x,y) (`f1..f5`) created via shifts/xors/adds to make structured but irregular regions:
- decides whether to use mapped data vs algorithm
- treats the “surface” specially
- carves caverns, windy caverns, solid boundaries, etc.

Feature/tertiary layer:
- for certain tile types, it searches a range of tertiary objects and swaps the tile if a spawner exists at that location.

Takeaway:
- If you want a huge world without huge map storage, this is the canonical pattern: procedural base + sparse authored patches + spawners.

## Practical Relevance to Our Project

If we go MODE 2 and want 4-way scrolling + lots of actors, Exile is a stronger reference than a pure platformer:
- edge redraw during scroll
- scroll-aware sprite clipping
- tiered entity persistence
- IRQ-synced palette and sound.

If we go “animation over backgrounds”, Exile still teaches:
- keep the world state compact (tertiary/secondary)
- spend CPU on sprites, not full background rebuilds.
