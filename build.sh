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
  --spec "chell_run_r1:sprites/Chell Run Right - Frame 1.csv" \
  --spec "chell_run_r2:sprites/Chell Run Right - Frame 2.csv" \
  --spec "chell_run_r3:sprites/Chell Run Right - Frame 3.csv" \
  --spec "chell_run_l1^:sprites/Chell Run Right - Frame 1.csv" \
  --spec "chell_run_l2^:sprites/Chell Run Right - Frame 2.csv" \
  --spec "chell_run_l3^:sprites/Chell Run Right - Frame 3.csv" \
  --spec "chell_rgun_r1:sprites/Chell Running Overlays - R-Gun Frame 1.csv" \
  --spec "chell_rgun_r2:sprites/Chell Running Overlays - R-Gun Frame 2.csv" \
  --spec "chell_rgun_r3:sprites/Chell Running Overlays - R-Gun Frame 3.csv" \
  --spec "chell_rgun_l1^:sprites/Chell Running Overlays - R-Gun Frame 1.csv" \
  --spec "chell_rgun_l2^:sprites/Chell Running Overlays - R-Gun Frame 2.csv" \
  --spec "chell_rgun_l3^:sprites/Chell Running Overlays - R-Gun Frame 3.csv"

beebasm -i main.asm -do "${OUT_SSD}" -title "PORTHOLE" -boot PROGRAM -v

echo "Build complete! Output: ${OUT_SSD}"
