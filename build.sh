#!/usr/bin/env bash
set -euo pipefail

VERBOSE=0
OUT_SSD="porthole.ssd"

# Usage:
#   ./build.sh [out.ssd]
#   ./build.sh -v [out.ssd]
#   BEEBASM_VERBOSE=1 ./build.sh [out.ssd]
if [[ "${BEEBASM_VERBOSE:-}" == "1" ]]; then
  VERBOSE=1
fi

if [[ "${1:-}" == "-v" ]]; then
  VERBOSE=1
  shift
fi

if [[ "${1:-}" != "" ]]; then
  OUT_SSD="$1"
fi

# Recreate the DFS image each build; beebasm won't overwrite files within
# an existing disc image.
mkdir -p "$(dirname "${OUT_SSD}")"
rm -f "${OUT_SSD}"

./tools/gen-sprites \
  --out-sprites sprites/generated_chell_sprites.asm \
  --out-masks sprites/generated_chell_masks.asm \
  --spec "chell_idle_r:sprites/Chell Idle - Reference.csv" \
  --spec "chell_idle_l^:sprites/Chell Idle - Reference.csv" \
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
  --spec "chell_rgun_l3^:sprites/Chell Running Overlays - R-Gun Frame 3.csv" \
  --spec "chell_jump_r:sprites/Chell Jump - Reference.csv" \
  --spec "chell_jump_l^:sprites/Chell Jump - Reference.csv" \
  --spec "reticle:sprites/Reticles - Reference.csv"

./tools/gen-tiles \
  --in "sprites/NewTiles - Grid.csv" \
  --out "sprites/generated_tiles.asm"

./tools/gen-level \
  --level "levels/level1" \
  --out "levels/generated_level1.asm"

BEEBASM_ARGS=(-i main.asm -do "${OUT_SSD}" -title "PORTHOLE" -boot PROGRAM)

# Always emit a symbols file for tooling.
mkdir -p .tmp
BEEBASM_ARGS+=( -dd -labels .tmp/beebasm.labels )

# Verbose beebasm listings are huge and can blow token budgets.
if [[ "${VERBOSE}" == "1" ]]; then
  BEEBASM_ARGS+=( -v )
fi

beebasm "${BEEBASM_ARGS[@]}"

# Some emulators and real-hardware tools expect a full 200KB SSD.
python3 tools/ssd-expand "${OUT_SSD}" "${OUT_SSD}"

echo "Build complete! Output: ${OUT_SSD}"
