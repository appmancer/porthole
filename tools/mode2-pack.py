#!/usr/bin/env python3

"""Pack a 160x256 PNG into a BBC MODE 2 20KB screen file.

This is a *pixel-by-pixel* packer:
- It does not resample.
- It expects the input to already be 160x256.

The output is raw MODE 2 screen memory layout (base &3000), 20480 bytes.

Palette mapping: nearest of the 8 non-flashing BBC colours (0..7).
"""

from __future__ import annotations

import argparse
import subprocess
import sys


BBC_PALETTE = [
    (0, 0, 0),
    (255, 0, 0),
    (0, 255, 0),
    (255, 255, 0),
    (0, 0, 255),
    (255, 0, 255),
    (0, 255, 255),
    (255, 255, 255),
]


def nearest_bbc_colour(r: int, g: int, b: int) -> int:
    best_i = 0
    best_d = 1 << 62
    for i, (pr, pg, pb) in enumerate(BBC_PALETTE):
        dr = r - pr
        dg = g - pg
        db = b - pb
        d = dr * dr + dg * dg + db * db
        if d < best_d:
            best_d = d
            best_i = i
    return best_i


def pack_mode2_byte(c0: int, c1: int) -> int:
    # MODE 2 packing (2 pixels/byte, 4 bits per pixel in interleaved bitplanes):
    # left pixel bits in 7,5,3,1 and right pixel bits in 6,4,2,0.
    # Bit significance: treat bit7/5/3/1 (left) and 6/4/2/0 (right) as MSB..LSB.
    # i.e. c bit3 is stored in bit7/6, and c bit0 in bit1/0.
    b = 0
    b |= ((c0 >> 3) & 1) << 7
    b |= ((c1 >> 3) & 1) << 6
    b |= ((c0 >> 2) & 1) << 5
    b |= ((c1 >> 2) & 1) << 4
    b |= ((c0 >> 1) & 1) << 3
    b |= ((c1 >> 1) & 1) << 2
    b |= ((c0 >> 0) & 1) << 1
    b |= ((c1 >> 0) & 1) << 0
    return b


def mode2_offset(xbyte: int, y: int) -> int:
    # MODE 2 layout (Advanced User Guide style):
    # &3000, &3008, &3010, ... across a scanline, with the low 3 bits selecting
    # the scanline within an 8-row band.
    #
    # bytes_per_scanline = 80
    # band_stride = 80 * 8 = 640 = &0280
    return (y & 7) + (xbyte << 3) + ((y >> 3) * 0x280)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--in", dest="inp", required=True, help="Input PNG (must be 160x256)"
    )
    ap.add_argument("--out", dest="outp", required=True, help="Output .bin")
    args = ap.parse_args()

    wh = subprocess.check_output(
        ["identify", "-format", "%w %h", args.inp], text=True
    ).strip()
    if wh != "160 256":
        raise SystemExit(f"Input must be 160x256, got {wh}")

    raw = subprocess.check_output(
        [
            "convert",
            args.inp,
            "-colorspace",
            "RGB",
            "-depth",
            "8",
            "rgb:-",
        ]
    )
    expected = 160 * 256 * 3
    if len(raw) != expected:
        raise SystemExit(
            f"Unexpected convert output: got {len(raw)} bytes, expected {expected}"
        )

    # Quantize to BBC colours.
    idx = bytearray(160 * 256)
    j = 0
    for i in range(0, len(raw), 3):
        idx[j] = nearest_bbc_colour(raw[i], raw[i + 1], raw[i + 2])
        j += 1

    # Pack into MODE 2 screen memory layout.
    out = bytearray(80 * 256)  # 20480 bytes
    for y in range(256):
        src_row = y * 160
        for xb in range(80):
            x = xb * 2
            c0 = idx[src_row + x]
            c1 = idx[src_row + x + 1]
            out[mode2_offset(xb, y)] = pack_mode2_byte(c0, c1)

    with open(args.outp, "wb") as f:
        f.write(out)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"ERROR running ImageMagick: {e}\n")
        raise SystemExit(1)
