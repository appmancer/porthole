# Tiled Authoring

PORTHOLE rooms are authored as one TMX per room:

- `levels/<level>/roomNN.tmx`

The build tool `tools/gen-level` prefers TMX when present (and falls back to the
legacy glyph `roomNN.txt` format).

Tiles

- Tileset image: `tiled/porthole_tiles.png` (generated from `sprites/NewTiles - Grid.csv`)
- Tileset definition: `tiled/porthole.tsx`

Convenience tools

- Generate/update the tileset PNG:
  - `./tools/gen-tileset-png --in "sprites/NewTiles - Grid.csv" --out tiled/porthole_tiles.png`
- Convert existing glyph rooms to TMX (one-time migration):
  - `./tools/room-txt-to-tmx --level levels/level1`

Room metadata

- Preferred: author exits and gameplay objects directly in TMX object layers:
  - objectgroup `meta`: edge exits as rectangle objects of type `edge_exit` with property `to=roomNN`
  - objectgroup `objects`: gameplay objects as point objects with type `cube|button|pad|exit`
- Legacy: `levels/<level>/roomNN.meta` (see `levels/meta_spec.md`)

Migration helper

- Copy `.meta` into TMX object layers:
  - `./tools/room-meta-to-tmx --level levels/level1`
