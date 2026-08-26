#!/usr/bin/env bash
set -euo pipefail

OUT_SSD="music_test.ssd"
if [[ "${1:-}" != "" ]]; then
  OUT_SSD="$1"
fi

mkdir -p "$(dirname "${OUT_SSD}")"
rm -f "${OUT_SSD}"

# Split the MIDI into bass + chord tracks if not already done.
if [[ ! -f "sound/gymnopedie_split.mid" ]]; then
  python3 tools/midi-split.py \
    --midi "sound/Erik Satie - Gymnopedie No. 1 [Perfect MIDI].mid" \
    --track 1 --channel 1 \
    --split-note 50 \
    --out "sound/gymnopedie_split.mid"
fi

# Regenerate music data from split MIDI.
python3 tools/gen-music.py \
  --midi "sound/gymnopedie_split.mid" \
  --out sound/gymnopedie_data.asm \
  --title 'Satie "Gymnopedie No. 1"' \
  --spec 'gymno_melody,0,0,999999,trim,high,m50' \
  --spec 'gymno_bass,2,1,999999' \
  --spec 'gymno_chord,3,1,999999,high'

beebasm -i music/music_test.asm -do "${OUT_SSD}" -title "MUSICT" -boot MUSICT

python3 tools/ssd-expand "${OUT_SSD}" "${OUT_SSD}"

echo "Build complete! Output: ${OUT_SSD}"
