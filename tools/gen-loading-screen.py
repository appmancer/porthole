#!/usr/bin/env python3

"""Generate a BBC MODE 2 screen file from a PNG.

Output is a 20KB binary blob laid out exactly as MODE 2 screen memory expects
(base &3000, 160x256, 4bpp / 2 pixels per byte with bitplane interleave).

We quantize to the non-flashing BBC 8-colour palette (indices 0..7).
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
    # MODE 2 packing (2 pixels/byte):
    # pixel0 bits in 7,5,3,1 and pixel1 bits in 6,4,2,0.
    b = 0
    b |= ((c0 >> 0) & 1) << 7
    b |= ((c1 >> 0) & 1) << 6
    b |= ((c0 >> 1) & 1) << 5
    b |= ((c1 >> 1) & 1) << 4
    b |= ((c0 >> 2) & 1) << 3
    b |= ((c1 >> 2) & 1) << 2
    b |= ((c0 >> 3) & 1) << 1
    b |= ((c1 >> 3) & 1) << 0
    return b


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True, help="Input PNG")
    ap.add_argument("--out", dest="outp", required=True, help="Output .bin")
    ap.add_argument("--w", type=int, default=160)
    ap.add_argument("--h", type=int, default=256)
    args = ap.parse_args()

    w = args.w
    h = args.h
    if w != 160 or h != 256:
        raise SystemExit("Only 160x256 supported for MODE 2 output")

    # Resize/crop to target, output raw RGB.
    cmd = [
        "convert",
        args.inp,
        "-resize",
        f"{w}x{h}^",
        "-gravity",
        "center",
        "-extent",
        f"{w}x{h}",
        "-colorspace",
        "RGB",
        "-depth",
        "8",
        "rgb:-",
    ]
    raw = subprocess.check_output(cmd)
    expected = w * h * 3
    if len(raw) != expected:
        raise SystemExit(
            f"Unexpected convert output: got {len(raw)} bytes, expected {expected}"
        )

    # Quantize.
    idx = bytearray(w * h)
    j = 0
    for i in range(0, len(raw), 3):
        r = raw[i]
        g = raw[i + 1]
        b = raw[i + 2]
        idx[j] = nearest_bbc_colour(r, g, b)
        j += 1

    # Pack into MODE 2 screen memory layout.
    out = bytearray(80 * 256)  # 20480 bytes
    for y in range(256):
        row_base = (y & 7) * 0x800 + (y >> 3) * 80
        src_row = y * 160
        for xb in range(80):
            x = xb * 2
            c0 = idx[src_row + x]
            c1 = idx[src_row + x + 1]
            out[row_base + xb] = pack_mode2_byte(c0, c1)

    with open(args.outp, "wb") as f:
        f.write(out)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"ERROR running ImageMagick convert: {e}\n")
        raise SystemExit(1)
