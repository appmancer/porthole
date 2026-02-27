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

mkdir -p .tmp

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
  --spec "chell_fall_r@1:sprites/Chell Falling - Reference.csv" \
  --spec "chell_fall_l^@1:sprites/Chell Falling - Reference.csv" \
  --spec "chell_dead@1:sprites/Chell Dead - Reference.csv" \
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
  --spec "obj_cube:sprites/Objects - Cube.csv"

./tools/gen-tiles \
  --in "sprites/NewTiles - Grid.csv" \
  --out "sprites/generated_tiles.asm"

# --- Aperture logo (MODE 5 level card) ---
./tools/png-to-mode5 --in aperture.png --out .tmp/aperture_logo.bin \
  --width 128 --fg 0 --bg 2 --threshold 128

# --- Binary level pack (LYNNE-loaded) ---
./tools/gen-level --binary-pack \
  --levels levels/level1 levels/level2 levels/level3 levels/level4 levels/level5 levels/level6 levels/level7 \
  --out ".tmp/LVLS01.dat"

LOADSCR_WH=$(identify -format "%w %h" loading.png 2>/dev/null || true)
if [[ "${LOADSCR_WH}" == "160 256" ]]; then
  python3 tools/mode2-pack.py --in loading.png --out .tmp/loadscr_mode2.bin
else
  python3 tools/mode2-sample.py \
    --in loading.png \
    --out .tmp/loadscr_mode2.bin \
    --fit crop \
    --filter box
fi

# Optional sanity check: reconstruct a PNG from the packed MODE 2 screen.
if [[ "${GEN_LOADSCR_PREVIEW:-}" == "1" ]]; then
  python3 tools/mode2-unpack.py --in .tmp/loadscr_mode2.bin --out .tmp/loadscr_preview.png
fi

# Use beebasm v1.11+ (has fixes for DFS catalog corruption bugs in v1.10).
# Prefer locally-built v1.11 over system beebasm (snap is still on v1.10).
# Allow override via BEEBASM_PATH environment variable.
if [[ -n "${BEEBASM_PATH:-}" ]]; then
  BEEBASM="${BEEBASM_PATH}"
elif [[ -f .tmp/beebasm-repo/beebasm ]]; then
  BEEBASM=".tmp/beebasm-repo/beebasm"
else
  BEEBASM="beebasm"
fi

BEEBASM_ARGS=(-i main.asm -do "${OUT_SSD}" -title "PORTAL" -boot PROGRAM)

# Always emit a symbols file for tooling.
BEEBASM_ARGS+=( -dd -labels .tmp/beebasm.labels )

# Verbose beebasm listings are huge and can blow token budgets.
if [[ "${VERBOSE}" == "1" ]]; then
  BEEBASM_ARGS+=( -v )
fi

"${BEEBASM}" "${BEEBASM_ARGS[@]}"

# Build-time safety checks against label layout regressions.
./tools/check-build-invariants .tmp/beebasm.labels

# Protect MOS/VDU/Econet ZP workspaces.
# - All our ZP allocations must stay in &00..&8F.
# - Only a small fixed set of pointers is allowed in &70..&8F (layout invariants).
python3 - <<'PY'
import ast
import sys

p = '.tmp/beebasm.labels'
txt = open(p, 'r', encoding='utf-8').read().strip().replace('L', '')
labels = ast.literal_eval(txt)[0]

zp = [(k, int(v)) for k, v in labels.items() if k.startswith('.') and 0x0000 <= int(v) <= 0x00FF]

bad_90 = sorted([(k, v) for k, v in zp if 0x90 <= v <= 0xFF], key=lambda kv: kv[1])
if bad_90:
    sys.stderr.write('ERROR: game ZP labels overlap MOS/VDU/Econet workspace &90..&FF:\n')
    for k, v in bad_90:
        sys.stderr.write(f'  {k} = &{v:02X}\n')
    sys.stderr.write('Fix: keep game ZP variables <= &8F (see main.asm ZP layout).\n')
    sys.exit(1)

allowed_70 = {
    '.temp', '.screen_ptr', '.sprite_ptr', '.temp_y', '.row_counter', '.col_counter', '.current_room',
    '.tilemap_ptr', '.mask_ptr', '.temp_sprite_ptr', '.temp_mask_ptr',
}
bad_70 = sorted([(k, v) for k, v in zp if 0x70 <= v <= 0x8F and k not in allowed_70], key=lambda kv: kv[1])
if bad_70:
    sys.stderr.write('ERROR: unexpected game ZP labels in &70..&8F (reserved for fixed pointers):\n')
    for k, v in bad_70:
        sys.stderr.write(f'  {k} = &{v:02X}\n')
    sys.stderr.write('Fix: move these ZP vars below &70 (see main.asm ZP layout).\n')
    sys.exit(1)
PY

# Some emulators and real-hardware tools expect a full 200KB SSD.
python3 tools/ssd-expand "${OUT_SSD}" "${OUT_SSD}"

echo "Build complete! Output: ${OUT_SSD}"
