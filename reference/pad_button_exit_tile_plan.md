# Tile-Backed Pads/Buttons/Exits Plan

## Goal
Convert pads, buttons, and exits from dynamic stamped sprites to tile-backed state changes, while keeping cubes dynamic. Reduce runtime complexity and code size without changing gameplay.

## Scope
- Keep cubes as dynamic objects (position, physics, sprite stamping).
- Convert pads/buttons/exits to tile-backed states.
- Preserve existing controls and signal logic.
- Keep portals/reticle/LOS unchanged in this plan.

## Phase 1 — Tile IDs and Authoring
1. Confirm or add tile IDs for stateful objects:
   - pad_up / pad_down
   - button_up / button_down
   - exit_closed / exit_open (likely 2 tiles tall)
2. Ensure these tiles are generated in `sprites/generated_tiles.asm` and remain stable.
3. Update Tiled authoring (if needed) so pads/buttons/exits map to the correct base tile IDs.

### Room Authoring (What Changes)
- Keep **object definitions** for pads/buttons/exits in the Tiled objects layer (IDs, channels, persistence).
- Also place the **base tiles** in the tile layer at their fixed positions:
  - pad_up / button_up / exit_closed
- Runtime logic flips those tiles to the “active” variants when state changes.

## Phase 2 — Data Layout
4. Extend generated object data to include static tile positions for pads/buttons/exits:
   - `obj_tile_x[]`, `obj_tile_y[]`, `obj_tile_kind[]`
   - These positions are fixed for pads/buttons/exits (cubes remain dynamic).
5. Keep `obj_state[]` bitflags for pressed/open states only.

## Phase 3 — Runtime State and Signals
6. Update `update_signals_and_object_states` to compute state transitions:
   - Pad pressed if Chell stands on it or a cube rests on it.
   - Button pressed on SPACE while Chell overlaps.
   - Exit open if channel bit is set.
7. Only trigger redraw when state changes (edge-triggered by state bit transitions).

## Phase 4 — Tile-Backed Rendering
8. Add a helper to redraw only affected tiles on state change:
   - `redraw_object_tiles(obj_index)`
   - Pads/buttons: redraw 1x1 tile
   - Exits: redraw 1x2 tiles
9. Use existing `redraw_tile_xy` in `portal_place.asm` for the actual draw.

## Phase 5 — Code Pruning
10. Remove pad/button/exit paths from dynamic stamp/render pipeline:
    - Drop their branches in `stamp_persistent_object` and `render_persistent_objects_current_room`.
11. Remove unused sprite/mask selection for pads/buttons/exits.
12. Keep cube stamping and rendering unchanged.

## Phase 6 — Validation
13. Functional checks:
    - Pad presses with Chell or cube; releases when neither is present.
    - Button presses with SPACE while overlapping; releases on SPACE up.
    - Exit opens/closes with channel signals.
14. Visual checks:
    - Tile changes render immediately and persist.
    - No per-frame re-stamping of pad/button/exit tiles.
15. Size check:
    - Confirm `.end` moves down (target ~800–1200 bytes saved).

## Optional — Laser Beams as Tiles
16. Model laser beams as tile overlays:
    - Recompute beam path when emitter state changes.
    - Redraw only affected tiles, no per-frame sprite stamping.

## Notes
- This plan keeps the gameplay semantics intact and focuses on reducing rendering and per-frame object work.
- Cubes remain dynamic; pads/buttons/exits become stateful tiles.
