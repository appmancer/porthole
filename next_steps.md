# Next Steps

1) Hook portal placement input:
   - when reticle is valid, place Portal A/B by updating the room's static-object entry (x/y + enable bit)
   - force a redraw (cheap first pass: set `room_dirty` so tilemap + static objects restamp)
2) Add Portal B (yellow) sprite assets + wire into `tools/gen-sprites`, then update `objects.asm` to reference them (remove current red placeholder).
3) (Optional) Optimize placement redraw: stamp just the portal rect instead of full `room_dirty` redraw.
