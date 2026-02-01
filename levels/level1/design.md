# Level 1 Design Sketch (8 Chambers)

This is a rough progression plan for a Portal-like 2D flick-screen level.

Assumptions / available mechanics:

- Portals: LOS-gated placement onto portalable surfaces; wall/floor/ceiling as supported.
- Objects: cube, floor pad, button, exit door (signal channels).
- Timed door: opens for N frames after a trigger.
- Fizzler: clears portals; deletes carried cubes (and optionally any cube touching it).
- Cube spawner: produces a new cube to avoid softlocks.
- Hazards: toxic goo (kill-on-contact; also deletes cubes).
- Lasers: axis-aligned beams; receiver opens a door/channel.
- Moving platform/elevator: moves Chell (and optionally cube) between fixed stops.

Design goals:

- Introduce one new idea per chamber, then recombine.
- Keep solutions about planning/positioning rather than twitch combat.
- Never softlock: if a cube can be destroyed, a spawner (or respawn rule) exists.

## Chamber 01: Two Portals, One Door

Teach: reticle + LOS + portalable surfaces.

- Exit is visible but blocked.
- Only one obvious portalable panel is visible from spawn.
- Second panel is visible only after a short reposition (small ledge/step).

Solve: place A on the first panel, move to see the second, place B, walk through.

## Chamber 02: Goo Gap

Teach: toxic goo = consequence; portals = safe routing.

- Goo pit splits the room; exit on far side.
- Portalable surface near start and another on far side.
- Include a tempting-but-wrong portalable surface that strands you above goo, but is recoverable.

Solve: portal bridge across the gap.

## Chamber 03: Impossible Cube

Teach: cube acquisition/transport via portals.

- Cube is visible on a ledge with no direct walking path.
- Pad/button near exit requires cube.

Solve: place portals to "pick up" cube remotely, then carry to the trigger.

## Chamber 04: Timed Door Prep

Teach: timed doors reward pre-placing portals.

- Timer button is in a side alcove.
- Timed door is far enough away that you cannot run it without portals.

Solve: pre-place one portal at the timed door, hit timer, portal to the door immediately.

## Chamber 05: Fizzler Separation

Teach: fizzler deletes cube + clears portals; separate routes for player vs cube.

- Fizzler sits between the cube route and the exit corridor.
- Exit power is held by a floor pad that needs a cube (or persistent weight).

Solve: deliver cube to the pad without taking it through the fizzler (portal relay/toss), then take a fizzler-safe route to the exit.

## Chamber 06: Cube Spawner Insurance

Teach: spawner prevents softlock; cubes become "consumable".

- The intended solution risks losing the cube to goo/fizzler.
- Spawner produces a replacement cube (button-triggered or timed cooldown).

Solve: iterate: recover a new cube, then deliver it safely.

## Chamber 07: Laser Receiver Door

Teach: beam routing via portals; receiver opens exit channel.

- Laser emitter fires a fixed axis-aligned beam.
- Receiver is placed so direct beam path is blocked by static tiles.
- Optional: beam also guards a corridor (instant death), encouraging portal bypass.

Solve: re-route the beam into the receiver using portals to open the exit.

Implementation note: a good early constraint is axis-aligned only, no mirrors.

## Chamber 08: Elevator Vantage + Multi-Objective (Final)

Teach: moving platform creates new shooter position for LOS; combine prior mechanics.

- Elevator lifts Chell to a window where a high portalable panel becomes visible (new LOS).
- Goo below punishes failed traversal.
- Fizzler blocks the "obvious" carry path.
- Timed door gates access to the elevator.
- Laser receiver opens final exit (channel-gated).
- Cube/spawner used to hold a pad while Chell completes the route.

Solve (one possible structure):

1) Use timed door + portals to reach elevator.
2) Ride elevator to gain LOS, place portal to reach a new area.
3) Route laser into receiver to open exit.
4) Use cube (with spawner as backup) to hold pad while you take the fizzler-safe path.

### Elevator behavior choice

- Auto-looping elevator: makes timing/commitment part of the puzzle.
- Button-controlled elevator: reduces timing pressure; more planning-focused.

Recommendation: button-controlled for Level 1 pacing.
