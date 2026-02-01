#!/usr/bin/env python3

"""Convert a MIDI file to a simple beebasm event stream.

Outputs EQUB pairs: pitch,duration

- pitch is BBC SOUND 8-bit pitch (0..255), with middle C = 101 and 48 units/octave.
- duration is in 1/20th-second ticks.

This tool is intentionally small and dependency-free. It supports standard MIDI
files (SMF) with note_on/note_off and a single tempo map (first tempo event).
"""

from __future__ import annotations

import argparse
import struct
from dataclasses import dataclass
from typing import Iterable, List, Optional, Tuple


MIDDLE_C_PITCH = 101
PITCH_PER_SEMITONE = 4
MIDDLE_C_MIDI = 60


def midi_note_to_beeb_pitch(midi_note: int, transpose: int = 0) -> int:
    n = midi_note + transpose
    pitch = MIDDLE_C_PITCH + (n - MIDDLE_C_MIDI) * PITCH_PER_SEMITONE
    if pitch < 0:
        return 0
    if pitch > 255:
        return 255
    return pitch


def read_varlen(data: bytes, i: int) -> Tuple[int, int]:
    v = 0
    while True:
        if i >= len(data):
            raise ValueError("Unexpected EOF in varlen")
        b = data[i]
        i += 1
        v = (v << 7) | (b & 0x7F)
        if (b & 0x80) == 0:
            return v, i


@dataclass
class NoteEvent:
    start_tick: int
    end_tick: int
    note: int


def parse_midi(path: str) -> Tuple[int, List[bytes]]:
    raw = open(path, "rb").read()
    if raw[:4] != b"MThd":
        raise ValueError("Not a MIDI file (missing MThd)")
    hdr_len = struct.unpack(">I", raw[4:8])[0]
    hdr = raw[8 : 8 + hdr_len]
    fmt, ntrks, division = struct.unpack(">HHH", hdr[:6])
    if division & 0x8000:
        raise ValueError("SMPTE time division not supported")
    ppqn = division
    tracks: List[bytes] = []
    i = 8 + hdr_len
    for _ in range(ntrks):
        if raw[i : i + 4] != b"MTrk":
            raise ValueError("Missing MTrk")
        trk_len = struct.unpack(">I", raw[i + 4 : i + 8])[0]
        trk = raw[i + 8 : i + 8 + trk_len]
        tracks.append(trk)
        i += 8 + trk_len
    return ppqn, tracks


def extract_note_events(
    trk: bytes,
    *,
    channel: int,
    tempo_us_per_qn: int,
) -> Tuple[List[NoteEvent], int]:
    t = 0
    i = 0
    running_status: Optional[int] = None
    active: dict[int, int] = {}
    notes: List[NoteEvent] = []
    tempo = tempo_us_per_qn

    while i < len(trk):
        dt, i = read_varlen(trk, i)
        t += dt
        if i >= len(trk):
            break

        b = trk[i]
        i += 1

        if b == 0xFF:  # meta
            meta_type = trk[i]
            i += 1
            mlen, i = read_varlen(trk, i)
            mdata = trk[i : i + mlen]
            i += mlen
            if meta_type == 0x51 and mlen == 3:
                tempo = (mdata[0] << 16) | (mdata[1] << 8) | mdata[2]
            continue

        if b in (0xF0, 0xF7):  # sysex
            slen, i = read_varlen(trk, i)
            i += slen
            continue

        if b & 0x80:
            status = b
            running_status = status
        else:
            if running_status is None:
                raise ValueError("Running status without prior status")
            status = running_status
            i -= 1  # b is actually data

        msg = status & 0xF0
        ch = status & 0x0F

        if msg in (0x80, 0x90):
            note = trk[i]
            vel = trk[i + 1]
            i += 2
            if ch != channel:
                continue
            is_on = (msg == 0x90) and (vel != 0)
            if is_on:
                active[note] = t
            else:
                st = active.pop(note, None)
                if st is not None and t > st:
                    notes.append(NoteEvent(start_tick=st, end_tick=t, note=note))
            continue

        # other MIDI messages with fixed lengths
        if msg in (0xA0, 0xB0, 0xE0):
            i += 2
        elif msg in (0xC0, 0xD0):
            i += 1
        else:
            # Unknown/realtime: ignore.
            pass

    return notes, tempo


def quantize_tick(t: int, grid: int) -> int:
    return int(round(t / grid)) * grid


def to_monophonic(events: List[NoteEvent]) -> List[NoteEvent]:
    # Simple policy: sort by start, then if overlaps, keep the later-starting note.
    events = sorted(events, key=lambda e: (e.start_tick, e.end_tick))
    out: List[NoteEvent] = []
    cur_end = -1
    for e in events:
        if e.start_tick >= cur_end:
            out.append(e)
            cur_end = e.end_tick
        else:
            # overlap: replace last if this starts later
            if out and e.start_tick >= out[-1].start_tick:
                out[-1] = e
                cur_end = e.end_tick
    return out


def to_monophonic_pick(events: List[NoteEvent], pick: str) -> List[NoteEvent]:
    """Reduce polyphony to a single line.

    pick:
      - 'high': pick highest active note
      - 'low': pick lowest active note
      - 'last': legacy heuristic (keep later-starting notes)
    """

    if pick not in ("high", "low", "last"):
        raise ValueError(f"Unknown pick mode: {pick}")

    if pick == "last":
        return to_monophonic(events)

    if not events:
        return []

    # Sweep boundaries; for each interval between boundaries, pick a note from
    # the active set.
    pts: List[Tuple[int, int, int]] = []
    for e in events:
        if e.end_tick <= e.start_tick:
            continue
        pts.append((e.start_tick, 1, e.note))
        pts.append((e.end_tick, -1, e.note))

    if not pts:
        return []

    # Sort by time; process note-offs before note-ons at the same tick.
    pts.sort(key=lambda x: (x[0], x[1]))
    active: set[int] = set()
    out: List[NoteEvent] = []

    i = 0
    while i < len(pts):
        t = pts[i][0]

        # Apply all changes at this tick.
        while i < len(pts) and pts[i][0] == t and pts[i][1] == -1:
            active.discard(pts[i][2])
            i += 1
        while i < len(pts) and pts[i][0] == t and pts[i][1] == 1:
            active.add(pts[i][2])
            i += 1

        if i >= len(pts):
            break
        next_t = pts[i][0]
        if next_t <= t:
            continue

        if active:
            note = max(active) if pick == "high" else min(active)
            if out and out[-1].end_tick == t and out[-1].note == note:
                out[-1].end_tick = next_t
            else:
                out.append(NoteEvent(start_tick=t, end_tick=next_t, note=note))

    return out


def emit_event_stream(
    events: List[NoteEvent],
    *,
    ppqn: int,
    tempo_us_per_qn: int,
    transpose: int,
    label: str,
    trim_leading_rest: bool,
) -> str:
    # Assemble a rest+note event stream in 1/20s ticks.
    #
    # Important: to keep multiple tracks aligned, we quantize using *absolute*
    # time mapping (MIDI tick -> 1/20s tick) rather than per-track accumulators.
    # This avoids tracks drifting relative to each other due to differing rounding
    # patterns.

    denom = ppqn * 50_000

    def t20_at(midi_tick: int) -> int:
        # Round to nearest 1/20s tick.
        num = midi_tick * tempo_us_per_qn
        return int((num + denom // 2) // denom)

    out_pairs: List[Tuple[int, int]] = []

    def emit_pair(pitch: int, dur20: int) -> None:
        if dur20 <= 0:
            return
        while dur20 > 255:
            out_pairs.append((pitch, 255))
            dur20 -= 255
        out_pairs.append((pitch, dur20))

    cur_tick = 0
    if trim_leading_rest and events:
        cur_tick = events[0].start_tick
    cur_t20 = t20_at(cur_tick)

    for e in events:
        start_t20 = t20_at(e.start_tick)
        rest20 = start_t20 - cur_t20
        if rest20 > 0:
            emit_pair(253, rest20)

        end_t20 = t20_at(e.end_tick)
        note20 = end_t20 - start_t20
        if note20 <= 0:
            note20 = 1
        emit_pair(midi_note_to_beeb_pitch(e.note, transpose), note20)
        cur_t20 = end_t20

    lines = [f".{label}"]
    for pitch, dur in out_pairs:
        lines.append(f"    EQUB {pitch}, {dur}")
    lines.append("    EQUB 254, 0")
    return "\n".join(lines) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("midi", help="Input .mid")
    ap.add_argument("--track", type=int, default=0, help="Track index (0-based)")
    ap.add_argument("--channel", type=int, default=0, help="MIDI channel 0..15")
    ap.add_argument("--transpose", type=int, default=0, help="Transpose in semitones")
    ap.add_argument(
        "--quant",
        type=int,
        default=16,
        help="Quantize grid as 1/N notes (default 1/16)",
    )
    ap.add_argument(
        "--end-ticks",
        type=int,
        default=None,
        help="Stop after this absolute tick (trim loop section)",
    )
    ap.add_argument(
        "--trim-leading-rest",
        action="store_true",
        help="Start the stream at the first note (remove initial rest)",
    )
    ap.add_argument(
        "--pick",
        choices=["high", "low", "last"],
        default="last",
        help="Polyphony reduction: high|low|last",
    )
    ap.add_argument("--label", default="music_track", help="beebasm label")
    args = ap.parse_args()

    ppqn, tracks = parse_midi(args.midi)
    if not (0 <= args.track < len(tracks)):
        raise SystemExit(f"Track out of range (0..{len(tracks) - 1})")

    # Default tempo: 120bpm => 500000 us/qn.
    tempo = 500_000
    notes, tempo = extract_note_events(
        tracks[args.track], channel=args.channel, tempo_us_per_qn=tempo
    )

    grid_ticks = max(1, int(round(ppqn * 4 / args.quant)))
    q: List[NoteEvent] = []
    for e in notes:
        st = quantize_tick(e.start_tick, grid_ticks)
        en = quantize_tick(e.end_tick, grid_ticks)
        if en <= st:
            en = st + grid_ticks
        if args.end_ticks is not None:
            if st >= args.end_ticks:
                continue
            if en > args.end_ticks:
                en = args.end_ticks
        if en > st:
            q.append(NoteEvent(st, en, e.note))

    q = to_monophonic_pick(q, args.pick)
    print(
        emit_event_stream(
            q,
            ppqn=ppqn,
            tempo_us_per_qn=tempo,
            transpose=args.transpose,
            label=args.label,
            trim_leading_rest=args.trim_leading_rest,
        )
    )


if __name__ == "__main__":
    main()
