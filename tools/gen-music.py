#!/usr/bin/env python3

"""Generate beebasm music event streams from a MIDI file.

This is a thin wrapper around tools/midi2beeb.py that writes a complete ASM data
file (header + one or more labelled tracks).

Example:
  python3 tools/gen-music.py \
    --midi music/habanera.mid \
    --out music/habanera_data.asm \
    --title 'Bizet "Habanera"' \
    --spec 'habanera_melody,1,0,30720,trim' \
    --spec 'habanera_bass,3,2,30720'

Spec format (comma-separated):
  label,track,channel,end_ticks[,trim]

- label: beebasm label name (without leading dot)
- track: MIDI track index (0-based)
- channel: MIDI channel 0..15
- end_ticks: stop after this absolute tick (int)
- trim: optional literal 'trim' to remove leading rest
"""

from __future__ import annotations

import argparse
import os
import sys
import struct


def _import_midi2beeb():
    # Allow running from repo root: import tools/midi2beeb.py as a module.
    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, here)
    import midi2beeb  # type: ignore

    return midi2beeb


def _first_tempo_us_per_qn(midi2beeb, tracks: list[bytes], default: int) -> int:
    # Scan tracks for the first tempo meta event (0xFF 0x51).
    tempo = default
    for trk in tracks:
        try:
            _, tempo = midi2beeb.extract_note_events(
                trk, channel=0, tempo_us_per_qn=tempo
            )
        except Exception:
            continue
        if tempo != default:
            return tempo
    return tempo


def parse_spec(s: str):
    parts = [p.strip() for p in s.split(",") if p.strip()]
    if len(parts) < 4:
        raise SystemExit(
            f"Bad --spec '{s}'. Expected label,track,channel,end_ticks[,flags...]"
        )
    label = parts[0]
    track = int(parts[1])
    channel = int(parts[2])
    end_ticks = int(parts[3])
    trim = False
    pick = "last"
    transpose = 0
    for flag in parts[4:]:
        if flag == "trim":
            trim = True
            continue
        if flag.startswith("t") and len(flag) > 1:
            try:
                transpose = int(flag[1:])
            except ValueError:
                raise SystemExit(f"Bad --spec '{s}'. Bad transpose flag '{flag}'.")
            continue
        if flag in ("high", "low", "last"):
            pick = flag
            continue
        raise SystemExit(f"Bad --spec '{s}'. Unknown flag '{flag}'.")
    return label, track, channel, end_ticks, trim, pick, transpose


def _read_varlen(data: bytes, i: int):
    v = 0
    while True:
        if i >= len(data):
            raise ValueError("Unexpected EOF in varlen")
        b = data[i]
        i += 1
        v = (v << 7) | (b & 0x7F)
        if (b & 0x80) == 0:
            return v, i


def midi_track_summary(trk: bytes):
    """Return basic stats: channels used, program changes, note range, polyphony."""

    t = 0
    i = 0
    running_status = None
    # channel -> current program
    prog: dict[int, int] = {}
    prog_seen: dict[int, set[int]] = {}
    # note activity per channel
    active: dict[int, set[int]] = {c: set() for c in range(16)}
    max_poly: dict[int, int] = {c: 0 for c in range(16)}
    note_min: dict[int, int] = {}
    note_max: dict[int, int] = {}
    tempo_us = None

    while i < len(trk):
        dt, i = _read_varlen(trk, i)
        t += dt
        if i >= len(trk):
            break
        b = trk[i]
        i += 1

        if b == 0xFF:
            meta_type = trk[i]
            i += 1
            mlen, i = _read_varlen(trk, i)
            mdata = trk[i : i + mlen]
            i += mlen
            if meta_type == 0x51 and mlen == 3:
                tempo_us = (mdata[0] << 16) | (mdata[1] << 8) | mdata[2]
            continue

        if b in (0xF0, 0xF7):
            slen, i = _read_varlen(trk, i)
            i += slen
            continue

        if b & 0x80:
            status = b
            running_status = status
        else:
            if running_status is None:
                raise ValueError("Running status without prior status")
            status = running_status
            i -= 1

        msg = status & 0xF0
        ch = status & 0x0F

        if msg in (0x80, 0x90):
            note = trk[i]
            vel = trk[i + 1]
            i += 2
            is_on = (msg == 0x90) and (vel != 0)
            if is_on:
                active[ch].add(note)
            else:
                active[ch].discard(note)
            if active[ch]:
                max_poly[ch] = max(max_poly[ch], len(active[ch]))
            note_min[ch] = min(note_min.get(ch, note), note)
            note_max[ch] = max(note_max.get(ch, note), note)
            continue

        if msg == 0xC0:  # program change
            p = trk[i]
            i += 1
            prog[ch] = p
            prog_seen.setdefault(ch, set()).add(p)
            continue

        # other MIDI messages with fixed lengths
        if msg in (0xA0, 0xB0, 0xE0):
            i += 2
        elif msg in (0xD0,):
            i += 1
        else:
            # unknown / realtime
            pass

    chans = sorted([c for c in range(16) if c in note_min or c in prog_seen])
    return {
        "tempo_us": tempo_us,
        "channels": chans,
        "programs": {c: sorted(list(prog_seen.get(c, set()))) for c in chans},
        "note_min": {c: note_min.get(c) for c in chans},
        "note_max": {c: note_max.get(c) for c in chans},
        "max_poly": {c: max_poly.get(c, 0) for c in chans},
    }


GM_PROGRAM_NAMES = [
    # 0..127 General MIDI Level 1 program names.
    "Acoustic Grand Piano",
    "Bright Acoustic Piano",
    "Electric Grand Piano",
    "Honky-tonk Piano",
    "Electric Piano 1",
    "Electric Piano 2",
    "Harpsichord",
    "Clavinet",
    "Celesta",
    "Glockenspiel",
    "Music Box",
    "Vibraphone",
    "Marimba",
    "Xylophone",
    "Tubular Bells",
    "Dulcimer",
    "Drawbar Organ",
    "Percussive Organ",
    "Rock Organ",
    "Church Organ",
    "Reed Organ",
    "Accordion",
    "Harmonica",
    "Tango Accordion",
    "Acoustic Guitar (nylon)",
    "Acoustic Guitar (steel)",
    "Electric Guitar (jazz)",
    "Electric Guitar (clean)",
    "Electric Guitar (muted)",
    "Overdriven Guitar",
    "Distortion Guitar",
    "Guitar harmonics",
    "Acoustic Bass",
    "Electric Bass (finger)",
    "Electric Bass (pick)",
    "Fretless Bass",
    "Slap Bass 1",
    "Slap Bass 2",
    "Synth Bass 1",
    "Synth Bass 2",
    "Violin",
    "Viola",
    "Cello",
    "Contrabass",
    "Tremolo Strings",
    "Pizzicato Strings",
    "Orchestral Harp",
    "Timpani",
    "String Ensemble 1",
    "String Ensemble 2",
    "Synth Strings 1",
    "Synth Strings 2",
    "Choir Aahs",
    "Voice Oohs",
    "Synth Choir",
    "Orchestra Hit",
    "Trumpet",
    "Trombone",
    "Tuba",
    "Muted Trumpet",
    "French Horn",
    "Brass Section",
    "Synth Brass 1",
    "Synth Brass 2",
    "Soprano Sax",
    "Alto Sax",
    "Tenor Sax",
    "Baritone Sax",
    "Oboe",
    "English Horn",
    "Bassoon",
    "Clarinet",
    "Piccolo",
    "Flute",
    "Recorder",
    "Pan Flute",
    "Blown Bottle",
    "Shakuhachi",
    "Whistle",
    "Ocarina",
    "Lead 1 (square)",
    "Lead 2 (sawtooth)",
    "Lead 3 (calliope)",
    "Lead 4 (chiff)",
    "Lead 5 (charang)",
    "Lead 6 (voice)",
    "Lead 7 (fifths)",
    "Lead 8 (bass + lead)",
    "Pad 1 (new age)",
    "Pad 2 (warm)",
    "Pad 3 (polysynth)",
    "Pad 4 (choir)",
    "Pad 5 (bowed)",
    "Pad 6 (metallic)",
    "Pad 7 (halo)",
    "Pad 8 (sweep)",
    "FX 1 (rain)",
    "FX 2 (soundtrack)",
    "FX 3 (crystal)",
    "FX 4 (atmosphere)",
    "FX 5 (brightness)",
    "FX 6 (goblins)",
    "FX 7 (echoes)",
    "FX 8 (sci-fi)",
    "Sitar",
    "Banjo",
    "Shamisen",
    "Koto",
    "Kalimba",
    "Bag pipe",
    "Fiddle",
    "Shanai",
    "Tinkle Bell",
    "Agogo",
    "Steel Drums",
    "Woodblock",
    "Taiko Drum",
    "Melodic Tom",
    "Synth Drum",
    "Reverse Cymbal",
    "Guitar Fret Noise",
    "Breath Noise",
    "Seashore",
    "Bird Tweet",
    "Telephone Ring",
    "Helicopter",
    "Applause",
    "Gunshot",
]


def gm_name(prog: int) -> str:
    if 0 <= prog < len(GM_PROGRAM_NAMES):
        return GM_PROGRAM_NAMES[prog]
    return "?"


def main() -> None:
    midi2beeb = _import_midi2beeb()

    ap = argparse.ArgumentParser()
    ap.add_argument("--midi", required=True, help="Input .mid")
    ap.add_argument("--out", required=True, help="Output .asm")
    ap.add_argument("--title", default="", help="Optional tune title for header")
    ap.add_argument(
        "--list",
        action="store_true",
        help="Print MIDI track/channel summary and exit",
    )
    ap.add_argument(
        "--quant",
        type=int,
        default=16,
        help="Quantize grid as 1/N notes (default 1/16)",
    )
    ap.add_argument("--transpose", type=int, default=0, help="Transpose in semitones")
    ap.add_argument(
        "--spec",
        action="append",
        default=[],
        help="Track spec: label,track,channel,end_ticks[,trim] (repeatable)",
    )
    args = ap.parse_args()
    if args.list:
        ppqn, tracks = midi2beeb.parse_midi(args.midi)
        print(f"ppqn={ppqn} tracks={len(tracks)}")
        for ti, trk in enumerate(tracks):
            s = midi_track_summary(trk)
            if not s["channels"] and s["tempo_us"] is None:
                continue
            tempo = f" tempo_us/qn={s['tempo_us']}" if s["tempo_us"] is not None else ""
            print(f"track {ti}:{tempo}")
            for ch in s["channels"]:
                progs = s["programs"].get(ch) or []
                if progs:
                    pr = ",".join(f"{p}({gm_name(p)})" for p in progs)
                else:
                    pr = "-"
                nmin = s["note_min"].get(ch)
                nmax = s["note_max"].get(ch)
                mp = s["max_poly"].get(ch, 0)
                print(f"  ch{ch}: prog={pr} notes={nmin}..{nmax} max_poly={mp}")
        return

    if not args.spec:
        raise SystemExit("At least one --spec is required")

    ppqn, tracks = midi2beeb.parse_midi(args.midi)

    # Default tempo: 120bpm => 500000 us/qn.
    tempo = 500_000
    tempo = _first_tempo_us_per_qn(midi2beeb, tracks, tempo)

    # Use the first tempo found in the file (typically track 0).

    header = []
    header.append("; Generated music data (auto).")
    if args.title:
        header.append(f"; Title: {args.title}")
    header.append(f"; Source: {args.midi}")
    header.append("; Tool: tools/gen-music.py (via tools/midi2beeb.py)")
    header.append(";")
    header.append("; Event format: EQUB pitch,duration")
    header.append("; - pitch 0..252: BBC SOUND 8-bit pitch")
    header.append("; - pitch 253: rest")
    header.append("; - pitch 254: loop")
    header.append("; - pitch 255: end")
    header.append("; - duration is in 1/20s ticks")
    header.append("")

    chunks = ["\n".join(header)]

    grid_ticks = max(1, int(round(ppqn * 4 / args.quant)))
    for spec_s in args.spec:
        label, track_i, channel, end_ticks, trim, pick, spec_transpose = parse_spec(
            spec_s
        )
        if not (0 <= track_i < len(tracks)):
            raise SystemExit(
                f"Spec '{spec_s}': track out of range (0..{len(tracks) - 1})"
            )
        if not (0 <= channel <= 15):
            raise SystemExit(f"Spec '{spec_s}': channel must be 0..15")

        notes, _ = midi2beeb.extract_note_events(
            tracks[track_i], channel=channel, tempo_us_per_qn=tempo
        )

        q = []
        for e in notes:
            st = midi2beeb.quantize_tick(e.start_tick, grid_ticks)
            en = midi2beeb.quantize_tick(e.end_tick, grid_ticks)
            if en <= st:
                en = st + grid_ticks
            if st >= end_ticks:
                continue
            if en > end_ticks:
                en = end_ticks
            if en > st:
                q.append(midi2beeb.NoteEvent(st, en, e.note))
        q = midi2beeb.to_monophonic_pick(q, pick)

        chunks.append(
            midi2beeb.emit_event_stream(
                q,
                ppqn=ppqn,
                tempo_us_per_qn=tempo,
                transpose=args.transpose + spec_transpose,
                label=label,
                trim_leading_rest=trim,
            ).rstrip()
        )
        chunks.append("")

    out_txt = "\n".join(chunks).rstrip() + "\n"
    with open(args.out, "w", encoding="ascii", newline="\n") as f:
        f.write(out_txt)


if __name__ == "__main__":
    main()
