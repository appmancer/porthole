# Next Steps

## Portal Teleportation MVP

### Current Status

- Wall portals only (left/right).
- Entry detection: overlap + "push into face" using velocity (`dot(v, n_enter) < 0`).
- Entry vertical alignment guard: Chell center Y must be within `PORTAL_ALIGN_TOL_Y` of portal center Y (prevents hair-grazes).
- Teleportation: immediate teleport to the other portal, including cross-room transition.
- Exit placement: pixel-space nudge + simple visual-bound tuning.
- Momentum mapping implemented for wall portals (preserves components in portal frame).
- Re-trigger guard: cooldown frames.

### Next Work

- Finish “canonical portal rects” for all orientations and use them everywhere (draw, overlap, exit placement).
  - Wall portals now use `PORTAL_WALL_W_PX/PORTAL_WALL_H_PX`.
- Add anti-ping-pong beyond simple cooldown:
  - store last-exit portal id (kind + room + orient + xy) and ignore re-entry until you’ve moved away.
- Handle high-speed tunnelling: swept/stepped portal hit detection so fast flings can’t skip the portal rect.
- Extend to floor/ceiling portals once placement and portalable-surface rules exist.

### Test Scenarios (B2)

- Run into right-wall portal -> out left-wall portal: velocity exits moving left.
- Run into left-wall portal -> out right-wall portal: velocity exits moving right.
- Jump so only hair/feet grazes a high portal: should NOT trigger unless vertically aligned.
- Skim past/parallel to portal face: should not trigger.
