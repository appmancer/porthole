#!/usr/bin/env bash
set -euo pipefail

# Build a standalone SSD that fills a MODE 5 screen with a tile set, so you
# can see what it actually looks like on a Beeb.
#
# Usage:
#   ./build_tile_test.sh                          # green vine tiles
#   ./build_tile_test.sh "sprites/NewTiles - Grid.csv" [out.ssd]

TILE_CSV="${1:-sprites/GreenTiles - Grid.csv}"
OUT_SSD="${2:-tile_test.ssd}"

mkdir -p .tmp "$(dirname "${OUT_SSD}")"
rm -f "${OUT_SSD}"

./tools/gen-tiles --in "${TILE_CSV}" --out .tmp/generated_test_tiles.asm

# gen-tiles prepends an implicit tile 0, so the viewer's tile count is one
# less than the number of sprite_table entries.
TILE_COUNT=$(grep -c '^    EQUW ' .tmp/generated_test_tiles.asm)
TILE_COUNT=$((TILE_COUNT - 1))
echo "TILE_COUNT = ${TILE_COUNT}" > .tmp/test_tiles_count.asm

if [[ -n "${BEEBASM_PATH:-}" ]]; then
  BEEBASM="${BEEBASM_PATH}"
elif [[ -f .tmp/beebasm-repo/beebasm ]]; then
  BEEBASM=".tmp/beebasm-repo/beebasm"
else
  BEEBASM="beebasm"
fi

"${BEEBASM}" -i sprites/tile_test.asm -do "${OUT_SSD}" -title "TILET" -boot TILET

python3 tools/ssd-expand "${OUT_SSD}" "${OUT_SSD}"

echo "Built ${OUT_SSD} from ${TILE_CSV} (${TILE_COUNT} tiles)"
