#!/usr/bin/env python3

"""Resample a PNG down to BBC MODE 2 and pack it.

This is a *sampling* converter:
- It resizes/crops the input to 160x256 using ImageMagick.
- Then it maps pixels to the BBC 8-colour palette and packs to MODE 2 memory.

Use this to compare against a hand-prepared 160x256 source fed into
tools/mode2-pack.py.
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
    return (y & 7) + (xbyte << 3) + ((y >> 3) * 0x280)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True, help="Input PNG")
    ap.add_argument("--out", dest="outp", required=True, help="Output .bin")
    ap.add_argument(
        "--fit",
        choices=["crop", "contain", "stretch"],
        default="crop",
        help="How to fit the source into 160x256",
    )
    ap.add_argument(
        "--filter",
        default="box",
        help="ImageMagick resize filter (e.g. box, point, triangle, lanczos)",
    )
    args = ap.parse_args()

    # Resize strategy.
    if args.fit == "crop":
        resize_arg = "160x256^"
        extent = True
    elif args.fit == "contain":
        resize_arg = "160x256"
        extent = True
    else:
        resize_arg = "160x256!"
        extent = False

    cmd = [
        "convert",
        args.inp,
        "-filter",
        args.filter,
        "-resize",
        resize_arg,
    ]
    if extent:
        cmd += [
            "-gravity",
            "center",
            "-extent",
            "160x256",
        ]
    cmd += [
        "-colorspace",
        "RGB",
        "-depth",
        "8",
        "rgb:-",
    ]
    raw = subprocess.check_output(cmd)
    expected = 160 * 256 * 3
    if len(raw) != expected:
        raise SystemExit(
            f"Unexpected convert output: got {len(raw)} bytes, expected {expected}"
        )

    idx = bytearray(160 * 256)
    j = 0
    for i in range(0, len(raw), 3):
        idx[j] = nearest_bbc_colour(raw[i], raw[i + 1], raw[i + 2])
        j += 1

    out = bytearray(80 * 256)
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
