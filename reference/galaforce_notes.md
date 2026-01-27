# Galaforce (KevEdwards) techniques notes

Source: https://github.com/KevEdwards/Galaforce1BBC

This document summarises techniques used in Kevin Edwards’ BBC Micro game **Galaforce**, with emphasis on **keyboard/controller handling**, and notes on other techniques that are potentially reusable in PORTHOLE.

The goal here isn’t to clone Galaforce’s architecture wholesale; it’s to highlight the specific low-level “BBC Micro way” patterns that are worth reusing.


## Keyboard / Joystick input

Galaforce primarily uses MOS `OSBYTE` calls to read input (keyboard and joystick), then packs results into small bitfields that directly index movement tables.

Repo areas of interest:

- `src/ROUT1.asm` (key/joy polling helpers, toggles)
- `src/ROUT3.asm` (movement logic that packs input bits and uses tables)
- `src/ROUT4.asm` and `src/BOMBS1.asm` (fire handling and key/joy switching)


### Key polling helper (`OSBYTE &81`)

Technique:

- Define a small helper routine that checks a specific key using `OSBYTE &81`.
- Return a result in an easy-to-branch-on form.

In Galaforce:

- `src/ROUT1.asm` defines `.check_key`.
- Calling convention (as used throughout ROUT3/ROUT4) is:
  - `X` = internal key number
  - `A = #&81`, `Y = #&FF`, then `JSR osbyte`
  - `CPY #&FF` followed by branches to detect pressed/not pressed

Link:
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ROUT1.asm

Why it matters:

- It standardises key testing and keeps the hot-path code readable.
- It avoids inlining the OSBYTE sequence everywhere.

How this maps to PORTHOLE:

- PORTHOLE currently uses `OSBYTE 129` with negative INKEY numbers in `main.asm` via `.is_key_pressed`.
- If we move toward a Galaforce-like input snapshot, we can keep our existing `OSBYTE 129` helper but change the *consumer* side: collect results once-per-frame into a small bitfield.


### Joystick polling helper (`OSBYTE &80`)

Technique:

- Use `OSBYTE &80` to query joystick state.
- Provide helpers for both joystick ports (Galaforce has `.check_joy` and `.check_joy2`).

In Galaforce:

- `src/ROUT1.asm` contains `.check_joy` / `.check_joy2`.

Link:
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ROUT1.asm

Why it matters:

- It lets gameplay code treat keyboard and joystick as equivalent “sources” of directional bits.

How this maps to PORTHOLE:

- PORTHOLE currently appears keyboard-only.
- If we add joystick later, Galaforce’s pattern (one unified set of direction bits, with keyboard/joy selection) is a good fit.


### Keyboard vs joystick mode toggle (`key_joy_flag`)

Technique:

- Keep a mode flag (`key_joy_flag`) that selects whether gameplay reads keyboard or joystick.
- Implement toggle keys as part of the input system rather than scattering the choice throughout gameplay.

In Galaforce:

- `src/ROUT1.asm` implements `.key_joy` / `.key_joy2` to toggle the mode and then calls a display routine (status/UI update).

Link:
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ROUT1.asm

Why it matters:

- Makes it easy to support both control schemes without duplicating movement and fire logic.

How this maps to PORTHOLE:

- Even if we stay keyboard-only, the same architecture is still useful for:
  - redefinable keys (swap bindings)
  - accessibility mode (swap jump/fire)
  - debug “autopilot” / playback input mode


### Pack multiple key states into a bitfield with `ROL`

This is the most “Galaforce-ish” input pattern.

Technique:

- Evaluate a sequence of key checks one-by-one.
- After each “pressed?” test, rotate a bit into a byte using `ROL`.
- The resulting byte encodes multiple simultaneous directions in a compact form.

In Galaforce:

- `src/ROUT3.asm` `.move_my_base` builds two bytes (`temp3` and `temp3+1`) by repeatedly checking keys and `ROL`-ing the result into the accumulator/temporary.

Link:
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ROUT3.asm

Why it matters:

- It keeps multi-key combos natural (e.g. left+up) without special-casing.
- It produces a stable small integer (0..15) suitable for table lookup.
- It creates a clean split:
  - input sampling (turn hardware state into bits)
  - movement application (use the bits to select deltas)

How this maps to PORTHOLE:

- PORTHOLE currently polls keys and immediately mutates `char_speed_x`, `char_facing`, and `jump_held`.
- A direct improvement, in the Galaforce spirit:
  - Sample `left/right/jump` once per frame into an `input_held` byte.
  - Also compute `input_pressed = input_held & ~input_prev` (edge-trigger events) to replace the current `jump_held` special-case.


### Table-driven movement (`key_press_relx` / `key_press_rely`)

Technique:

- Use the packed bitfield as an index into small signed delta tables.
- Apply the resulting deltas to position.

In Galaforce:

- `src/ROUT3.asm` contains `key_press_relx` and `key_press_rely` tables.
- `.move_my_base` indexes those tables based on the packed key state bytes.

Link:
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ROUT3.asm

Why it matters:

- It’s branch-light and handles diagonal combinations naturally.
- It makes it easy to tweak feel by changing tables rather than code.

How this maps to PORTHOLE:

- If we ever want “air control” vs “ground control” or different speeds while holding an item, tables make that cheap:
  - switch table pointer based on state, index stays the same.


### Fire handling: treat keyboard + joystick consistently

Technique:

- Provide a single routine that checks “fire” regardless of input device.
- Gate behaviour using `key_joy_flag` (or equivalent mode).

In Galaforce:

- `src/ROUT4.asm` `.chk_spc_fire` checks a key path and a joystick path.
- `src/BOMBS1.asm` also branches based on `key_joy_flag` when deciding whether a “fire” input is active.

Links:
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ROUT4.asm
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/BOMBS1.asm

Why it matters:

- Avoids duplicating gameplay logic (“shoot bomb”) for each control method.


### Rate-limiting toggle keys (simple debounce / repeat control)

Technique:

- Only check certain keys every N frames (or only act if a counter bit pattern matches).

In Galaforce:

- `src/ROUT1.asm` `.sound_on_off` uses a counter mask (`AND #&0F`) to limit how often the toggle can fire.

Link:
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ROUT1.asm

Why it matters:

- Cheap way to prevent toggles repeating while a key is held.

How this maps to PORTHOLE:

- This is a good pattern for debug keys (e.g. teleport to next room, toggle portal rendering overlays) where a held key should not repeatedly trigger.


## Other notable techniques (non-input)

This section is intentionally brief; it’s here to help with later deeper dives.


### XOR sprite drawing + erase-by-redraw

Technique:

- Use EOR drawing for sprites, where drawing the same image twice restores the background.
- Often paired with careful ordering to avoid overlapping artifacts.

In Galaforce:

- Sprite routines live in `src/SPRITES.asm`.

Link:
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/SPRITES.asm

Note for PORTHOLE:

- PORTHOLE is already using masked sprite drawing (`dst = (dst & mask) | pix`) with save-under restore (as described in `README.md` / `next_steps.md`).
- So the reuse here is more about “tight draw loops + consistent screen pointer approach” than about adopting EOR rendering.


### Starfield + simple RNG

Technique:

- Maintain star positions and update them with a compact RNG.
- Plot and erase stars efficiently.

In Galaforce:

- `src/STARS.asm`.

Link:
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/STARS.asm


### Pattern interpreter for enemies

Technique:

- Encode gameplay patterns as compact bytecode/data tables.
- Interpret those tables with an action dispatcher.

In Galaforce:

- Alien logic is spread across `src/ALIENS1.asm` .. `src/ALIENS4.asm`.
- Pattern data is in `src/PATT.asm` / `src/PATDAT.asm`.

Links:
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ALIENS1.asm
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ALIENS2.asm
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ALIENS3.asm
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ALIENS4.asm
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/PATT.asm
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/PATDAT.asm


### Music engine structure

Technique:

- Drive music via a regular update routine and a small set of state flags.

In Galaforce:

- `src/MUSIC1.asm` .. `src/MUSIC3.asm`.

Links:
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/MUSIC1.asm
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/MUSIC2.asm
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/MUSIC3.asm


### ZP and absolute workspace organisation

Technique:

- Keep a clearly defined ZP workspace block and a separate absolute workspace block.

In Galaforce:

- `src/ZPWORK.asm` and `src/ABSWORK.asm`.

Links:
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ZPWORK.asm
- https://github.com/KevEdwards/Galaforce1BBC/blob/master/src/ABSWORK.asm


## Suggested next steps for PORTHOLE

If you want to bring PORTHOLE’s input closer to the “Galaforce style” (without changing key bindings or device choices yet):

1. Add two bytes in ZP:
   - `input_held` (current-frame sampled bits)
   - `input_prev` (previous-frame held bits)
2. Each frame:
   - sample keys into `input_held`
   - compute `input_pressed = input_held & (input_held EOR input_prev)` (or `input_held & ~input_prev`)
   - set `input_prev = input_held`
3. Consume `input_pressed` for jump edge trigger instead of `jump_held`.

That gives you the Galaforce “sample then apply” split, works with our existing `OSBYTE 129` approach, and makes multi-key behaviour more deterministic.
