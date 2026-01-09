#!/usr/bin/env bash
set -euo pipefail

OUT_SSD="${1:-porthole.ssd}"

# Recreate the DFS image each build; beebasm won't overwrite files within
# an existing disc image.
mkdir -p "$(dirname "${OUT_SSD}")"
rm -f "${OUT_SSD}"

./tools/gen-sprites \
  --out-sprites sprites/generated_chell_sprites.asm \
  --out-masks sprites/generated_chell_masks.asm \
  --spec "chell_pos1:sprites/Chell Position 1 - Sheet3.csv" \
  --spec "chell_pos2:sprites/Chell Position 2 - Sheet3.csv"

beebasm -i main.asm -do "${OUT_SSD}" -title "PORTHOLE" -boot PROGRAM -v

echo "Build complete! Output: ${OUT_SSD}"
