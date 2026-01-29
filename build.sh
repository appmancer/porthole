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
  --spec "chell_carry_r:sprites/Chell Overlays - Carrying.csv" \
  --spec "chell_carry_l^:sprites/Chell Overlays - Carrying.csv" \
  --spec "chell_jump_r:sprites/Chell Jump - Reference.csv" \
  --spec "chell_jump_l^:sprites/Chell Jump - Reference.csv" \
  --spec "reticle:sprites/Reticles - Reference.csv"

# Static object sprites embedded in main RAM (tile-aligned stamps).
./tools/gen-sprites \
  --out-sprites sprites/generated_objects_sprites.asm \
  --out-masks sprites/generated_objects_masks.asm \
  --spec "portal_v_red_r:sprites/Portal V - Red (Right).csv" \
  --spec "portal_v_red_l^:sprites/Portal V - Red (Right).csv" \
  --spec "portal_v_yel_r:sprites/Portal V - Yellow (Right).csv" \
  --spec "portal_v_yel_l^:sprites/Portal V - Yellow (Right).csv" \
  --spec "portal_b_red:sprites/Portal B - Red.csv" \
  --spec "portal_b_yel:sprites/Portal B - Yellow.csv" \
  --spec "portal_h_red_floor:sprites/Portal H - Red (Floor).csv" \
  --spec "portal_h_red_ceil:sprites/Portal H - Red (Ceil).csv" \
  --spec "portal_h_yel_floor:sprites/Portal H - Yellow (Floor).csv" \
  --spec "portal_h_yel_ceil:sprites/Portal H - Yellow (Ceil).csv" \
  --spec "obj_cube:sprites/Objects - Cube.csv" \
  --spec "obj_button:sprites/Objects - Button.csv" \
  --spec "obj_pad:sprites/Objects - Pressure Pad.csv" \
  --spec "obj_exit:sprites/Objects - Exit.csv"

./tools/gen-tiles \
  --in "sprites/NewTiles - Grid.csv" \
  --out "sprites/generated_tiles.asm"

./tools/gen-level \
  --level "levels/level2" \
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

# Build-time safety checks against label layout regressions.
./tools/check-build-invariants .tmp/beebasm.labels

# Some emulators and real-hardware tools expect a full 200KB SSD.
python3 tools/ssd-expand "${OUT_SSD}" "${OUT_SSD}"

echo "Build complete! Output: ${OUT_SSD}"
