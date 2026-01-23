# Next Steps

## Portal Teleportation MVP

### Current Status

- Portals support 4 orientations: wall-left, wall-right, floor, ceiling.
- Entry detection: overlap + "push into face" using velocity (`dot(v, n_enter) < 0`).
  - Floor/ceiling entry uses `char_prev_vy` so entry can trigger on the landing frame.
- Entry alignment guards:
  - walls: Chell center Y must be within `PORTAL_ALIGN_TOL_Y` of portal center Y (prevents hair-grazes)
  - floor/ceiling: Chell left X must be within `PORTAL_ALIGN_TOL_X` of portal left X
- Teleportation: immediate teleport to the other portal, including cross-room transition.
- Exit placement: pixel-space nudge + simple visual-bound tuning.
- Momentum mapping implemented for all orientations (preserves components in portal frame).
- Re-trigger guard: cooldown frames; during cooldown only re-entry to the last-exit portal is blocked (enables bouncy elevator).
- Teleport exit Y is quantized/clamped to the 8px stripe grid (avoids invalid `char_y_offset` values that can break gravity).

### Next Work

- Tighten ceiling/floor placement rules:
  - require clearance for a 16x32 exit volume so you can’t place a portal that forces Chell into geometry.
  - clamp/validate against top/bottom-of-room so exit never wraps.
- Fix yellow floor/ceiling portal art if still matching red (CSV palette indices).
- Finish “canonical portal rects” for all orientations and use them everywhere (draw, overlap, exit placement, exit nudges).
- Add high-speed tunnelling protection: swept/stepped portal hit detection so fast flings can’t skip the portal rect.
- Revisit anti-ping-pong: store last-exit portal id (kind + room + orient + xy) and ignore re-entry until you’ve moved away.

### Test Scenarios (B2)

- Run into right-wall portal -> out left-wall portal: velocity exits moving left.
- Run into left-wall portal -> out right-wall portal: velocity exits moving right.
- Fall into floor portal -> out ceiling portal: emerges downward.
- Jump into ceiling portal -> out floor portal: emerges upward.
- Jump so only hair/feet grazes a high portal: should NOT trigger unless vertically aligned.
- Skim past/parallel to portal face: should not trigger.
