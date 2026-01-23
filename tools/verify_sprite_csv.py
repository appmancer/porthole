#!/usr/bin/env python3
"""Verify sprite/mask bytes embedded in our sprite CSVs.

Some of our CSVs include computed hex byte columns to the right of the pixel
grid (e.g. two sprite bytes + two mask bytes for an 8px-wide row).

This script recomputes those bytes from the pixel columns and reports any
mismatches.

Examples:
  tools/verify_sprite_csv.py "sprites/Portal V - Red (Right).csv" --width 8
  tools/verify_sprite_csv.py "sprites/Portal B - Red.csv" --width 16
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


PIXEL_CELL_RE = re.compile(r"^[0-3.]+$")
HEXBYTE_RE = re.compile(r"^[0-9A-Fa-f]{2}$")


def parse_pixel(ch: str) -> int | None:
    if ch == ".":
        return None
    v = ord(ch) - ord("0")
    if 0 <= v <= 3:
        return v
    raise ValueError(f"invalid pixel token: {ch!r}")


def pack_sprite_byte(pixels4: list[int | None]) -> int:
    values = [0 if v is None else v for v in pixels4]
    msb = [(v >> 1) & 1 for v in values]
    lsb = [v & 1 for v in values]
    hi = (msb[0] << 3) | (msb[1] << 2) | (msb[2] << 1) | msb[3]
    lo = (lsb[0] << 3) | (lsb[1] << 2) | (lsb[2] << 1) | lsb[3]
    return (hi << 4) | lo


def pack_mask_byte(pixels4: list[int | None]) -> int:
    mask = 0xFF
    if pixels4[0] is not None:
        mask -= 0x88
    if pixels4[1] is not None:
        mask -= 0x44
    if pixels4[2] is not None:
        mask -= 0x22
    if pixels4[3] is not None:
        mask -= 0x11
    return mask


def pixels_from_cells(cells: list[str], width: int) -> list[int | None]:
    out: list[str] = []
    for cell in cells:
        cell = cell.strip()
        if not cell:
            continue
        if not PIXEL_CELL_RE.match(cell):
            continue
        out.extend(list(cell))

    if not out:
        return []

    if len(out) < width:
        out = out + ["."] * (width - len(out))
    out = out[:width]
    return [parse_pixel(ch) for ch in out]


def tail_hexbytes(cells: list[str], count: int) -> list[int] | None:
    tail = [c.strip() for c in cells[-count:]]
    if any(not HEXBYTE_RE.match(t) for t in tail):
        return None
    return [int(t, 16) for t in tail]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("csv", type=Path)
    ap.add_argument("--width", type=int, choices=(8, 16), required=True)
    args = ap.parse_args()

    path: Path = args.csv
    width: int = args.width
    expected_tail = 4 if width == 8 else 8

    bad = 0
    lines = path.read_text().splitlines()
    for idx, line in enumerate(lines, start=1):
        if not line.strip():
            continue

        cells = line.split(",")
        pixels = pixels_from_cells(cells, width)
        if not pixels:
            continue

        given = tail_hexbytes(cells, expected_tail)
        if given is None:
            print(f"{path}:{idx}: no trailing {expected_tail} hex bytes to verify")
            bad += 1
            continue

        sprite_bytes: list[int] = []
        mask_bytes: list[int] = []

        groups = width // 4
        for g in range(groups):
            p4 = pixels[g * 4 : g * 4 + 4]
            sprite_bytes.append(pack_sprite_byte(p4))
            mask_bytes.append(pack_mask_byte(p4))

        expected = sprite_bytes + mask_bytes
        if expected != given:
            bad += 1
            exp_hex = " ".join(f"{b:02X}" for b in expected)
            got_hex = " ".join(f"{b:02X}" for b in given)
            print(f"{path}:{idx}: mismatch")
            print(f"  expected: {exp_hex}")
            print(f"  got:      {got_hex}")

    if bad:
        print(f"FAIL: {bad} mismatches")
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
