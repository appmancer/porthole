#!/usr/bin/env bash
set -euo pipefail

OUT_SSD="${1:-porthole.ssd}"

# Recreate the DFS image each build; beebasm won't overwrite files within
# an existing disc image.
mkdir -p "$(dirname "${OUT_SSD}")"
rm -f "${OUT_SSD}"

beebasm -i main.asm -do "${OUT_SSD}" -title "PORTHOLE" -boot PROGRAM -v

echo "Build complete! Output: ${OUT_SSD}"
