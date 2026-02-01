#!/usr/bin/env bash
set -euo pipefail

OUT_SSD="music_test.ssd"
if [[ "${1:-}" != "" ]]; then
  OUT_SSD="$1"
fi

mkdir -p "$(dirname "${OUT_SSD}")"
rm -f "${OUT_SSD}"

# Regenerate music data from MIDI.
python3 tools/gen-music.py \
  --midi music/habanera.mid \
  --out music/habanera_data.asm \
  --title 'Bizet "Habanera"' \
  --quant 32 \
  --transpose 0 \
  --spec 'habanera_v0,1,0,61440,low,t-12' \
  --spec 'habanera_v1,3,2,61440,low'

beebasm -i music/music_test.asm -do "${OUT_SSD}" -title "MUSICT" -boot PROGRAM

python3 tools/ssd-expand "${OUT_SSD}" "${OUT_SSD}"

echo "Build complete! Output: ${OUT_SSD}"
