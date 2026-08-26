#!/usr/bin/env python3

"""Split a MIDI track into two tracks by pitch threshold.

Notes below the threshold go to a 'low' track, notes at or above go to a
'high' track. The result is a new MIDI file with the original tracks plus
the two split tracks appended.

Example:
  python3 tools/midi-split.py \
    --midi sound/gymnopedie.mid \
    --track 1 --channel 1 \
    --split-note 50 \
    --out sound/gymnopedie_split.mid

This adds two new tracks to the output:
  track N:   notes below split-note (bass)
  track N+1: notes at or above split-note (chords)
"""

from __future__ import annotations

import argparse
import struct
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import midi2beeb


def build_midi_track(events: list[midi2beeb.NoteEvent], channel: int) -> bytes:
    """Build a raw MTrk data blob from NoteEvents."""
    # Sort by start time, then by note
    events = sorted(events, key=lambda e: (e.start_tick, e.note))

    # Build a list of (absolute_tick, status_byte, data1, data2)
    raw_events: list[tuple[int, int, int, int]] = []
    for e in events:
        raw_events.append((e.start_tick, 0x90 | channel, e.note, 80))  # note on
        raw_events.append((e.end_tick, 0x80 | channel, e.note, 0))     # note off

    # Sort by tick, note-offs before note-ons at same tick
    raw_events.sort(key=lambda x: (x[0], 0 if (x[1] & 0xF0) == 0x80 else 1))

    # Encode as MIDI track data with delta times
    data = bytearray()
    prev_tick = 0
    for tick, status, d1, d2 in raw_events:
        dt = tick - prev_tick
        prev_tick = tick
        # Write variable-length delta
        data.extend(encode_varlen(dt))
        data.append(status)
        data.append(d1)
        data.append(d2)

    # End of track
    data.extend(encode_varlen(0))
    data.extend(b'\xFF\x2F\x00')

    return bytes(data)


def encode_varlen(value: int) -> bytes:
    """Encode an integer as MIDI variable-length quantity."""
    if value < 0:
        raise ValueError(f"Negative varlen: {value}")
    result = bytearray()
    result.append(value & 0x7F)
    value >>= 7
    while value:
        result.append((value & 0x7F) | 0x80)
        value >>= 7
    result.reverse()
    return bytes(result)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--midi", required=True, help="Input .mid file")
    ap.add_argument("--out", required=True, help="Output .mid file")
    ap.add_argument("--track", type=int, required=True, help="Track index to split (0-based)")
    ap.add_argument("--channel", type=int, required=True, help="MIDI channel (0-based)")
    ap.add_argument("--split-note", type=int, default=50,
                    help="MIDI note number for split threshold (default 50 = D3). "
                         "Notes below this go to low track, >= go to high track.")
    args = ap.parse_args()

    ppqn, tracks = midi2beeb.parse_midi(args.midi)

    if not (0 <= args.track < len(tracks)):
        raise SystemExit(f"Track {args.track} out of range (0..{len(tracks) - 1})")

    # Extract all note events from the target track+channel
    # Use a default tempo; we don't need tempo for splitting, just ticks
    notes, _ = midi2beeb.extract_note_events(
        tracks[args.track], channel=args.channel, tempo_us_per_qn=500_000
    )

    low_notes = [e for e in notes if e.note < args.split_note]
    high_notes = [e for e in notes if e.note >= args.split_note]

    print(f"Track {args.track}, channel {args.channel}: {len(notes)} notes total")
    print(f"  Low (< {args.split_note}): {len(low_notes)} notes")
    print(f"  High (>= {args.split_note}): {len(high_notes)} notes")

    if low_notes:
        lo_min = min(e.note for e in low_notes)
        lo_max = max(e.note for e in low_notes)
        print(f"    Low range: MIDI {lo_min}..{lo_max}")
    if high_notes:
        hi_min = min(e.note for e in high_notes)
        hi_max = max(e.note for e in high_notes)
        print(f"    High range: MIDI {hi_min}..{hi_max}")

    # Build new track data
    low_trk = build_midi_track(low_notes, args.channel)
    high_trk = build_midi_track(high_notes, args.channel)

    # Write output MIDI: original tracks + 2 new split tracks
    ntrks = len(tracks) + 2
    out = bytearray()

    # MThd
    out.extend(b'MThd')
    out.extend(struct.pack(">I", 6))
    out.extend(struct.pack(">HHH", 1, ntrks, ppqn))

    # Original tracks
    for trk in tracks:
        out.extend(b'MTrk')
        out.extend(struct.pack(">I", len(trk)))
        out.extend(trk)

    # Low track
    out.extend(b'MTrk')
    out.extend(struct.pack(">I", len(low_trk)))
    out.extend(low_trk)

    # High track
    out.extend(b'MTrk')
    out.extend(struct.pack(">I", len(high_trk)))
    out.extend(high_trk)

    with open(args.out, "wb") as f:
        f.write(out)

    print(f"\nWrote {args.out} ({ntrks} tracks)")
    print(f"  Track 0..{len(tracks)-1}: original")
    print(f"  Track {len(tracks)}: bass (low)")
    print(f"  Track {len(tracks)+1}: chords (high)")


if __name__ == "__main__":
    main()
