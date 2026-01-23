# Next Steps

## Portal Teleportation MVP

### Current Status

- Wall portals only (left/right).
- Entry detection: overlap + "push into face" (currently approximated from input/facing).
- Teleportation: immediate teleport to the other portal, including cross-room transition.
- Exit placement: pixel-space nudge + simple visual-bound tuning.
- Re-trigger guard: cooldown frames.

### Next Work

- Define canonical portal rects in pixels for each orientation and use them everywhere (draw, overlap, exit placement).
- Add real horizontal velocity (`char_vx`, px/frame) so entry intent becomes `dot(v, n_enter) < 0` instead of input-derived.
- Implement momentum mapping using the design rules:
  - compute `(v_t, v_n)` in the entry portal frame
  - recompose `v'` in the exit portal frame
- Add anti-ping-pong: store last-exit portal id and/or a short grace window so you can’t instantly re-trigger the same portal.
- Extend to floor/ceiling portals once placement and portalable-surface rules exist.

### Test Scenarios (B2)

- Fall into floor portal -> out floor portal (launch upward).
- Run into right-wall portal -> out floor portal (convert horizontal to vertical).
- Fall into floor portal -> out right-wall portal (convert vertical to horizontal).
- Skim past/parallel to portal face: should not trigger.
