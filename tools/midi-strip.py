#!/usr/bin/env python3

"""Write a new MIDI file keeping only specified tracks.

Example:
  python3 tools/midi-strip.py \
    --midi sound/gymnopedie_split.mid \
    --keep 0 2 3 \
    --out sound/gymnopedie_3voice.mid
"""

from __future__ import annotations

import argparse
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import midi2beeb


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--midi", required=True, help="Input .mid file")
    ap.add_argument("--out", required=True, help="Output .mid file")
    ap.add_argument("--keep", type=int, nargs="+", required=True,
                    help="Track indices to keep (0-based)")
    args = ap.parse_args()

    ppqn, tracks = midi2beeb.parse_midi(args.midi)

    kept = []
    for i in args.keep:
        if not (0 <= i < len(tracks)):
            raise SystemExit(f"Track {i} out of range (0..{len(tracks) - 1})")
        kept.append(tracks[i])

    out = bytearray()
    out.extend(b'MThd')
    out.extend(struct.pack(">I", 6))
    out.extend(struct.pack(">HHH", 1, len(kept), ppqn))

    for trk in kept:
        out.extend(b'MTrk')
        out.extend(struct.pack(">I", len(trk)))
        out.extend(trk)

    with open(args.out, "wb") as f:
        f.write(out)

    print(f"Wrote {args.out}: {len(kept)} tracks (kept {args.keep} from {len(tracks)} original)")


if __name__ == "__main__":
    main()
