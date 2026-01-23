# Next Steps

1) Add Portal B (yellow) sprite assets + wire into `tools/gen-sprites`, then update `objects.asm` to reference them (remove current red placeholder).
2) Optimize placement redraw: stamp just the portal rect (avoid full `room_dirty` redraw).
3) Add new portal types (new orientations / surfaces) once A/B flow is solid.
