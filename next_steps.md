# Next Steps

## Next Steps

### Portal Teleportation MVP (no code yet)

- Define portal rects in pixels for each orientation and the exact mapping from stored portal `(room, tile_x, tile_y, orient)` to that rect.
- Add runtime state needed:
  - per-portal: enabled, room, tile_x, tile_y, orient
  - teleport: cooldown frames, last-teleport id (optional)
- Trigger rule (intent): teleport only if Chell overlaps the portal rect and `dot(v, n_enter) < 0`.
- Momentum rule: compute `v_t=dot(v,t_enter)`, `v_n=-dot(v,n_enter)`, then `v'=v_t*t_exit + v_n*n_exit`.
- On teleport: clear grounded, place Chell just outside exit rect by `PORTAL_EXIT_NUDGE` pixels along `n_exit`, apply cooldown.
- Pick initial tuning constants: `g=1 px/frame^2`, `vy_terminal=28 px/frame` ("spicy" cap), plus `PORTAL_EXIT_NUDGE`, `PORTAL_COOLDOWN_FRAMES`.
- First implementation step: detect portal overlap + intent only (no teleport yet).
  - For current room: compute Chell rect/point and portal rects.
  - Overlap + `dot(v, n_enter) < 0` => set `teleport_pending` and record which portal is the entry.

### Test Scenarios (B2)

- Fall into floor portal -> out floor portal (launch upward).
- Run into right-wall portal -> out floor portal (convert horizontal to vertical).
- Fall into floor portal -> out right-wall portal (convert vertical to horizontal).
- Skim past/parallel to portal face: should not trigger.
