#!/usr/bin/env python3

"""Unpack a BBC MODE 2 20KB screen file into a PNG for sanity checking.

Input is a raw MODE 2 screen memory dump (20480 bytes, base &3000 layout).
Output is a 160x256 PNG using the BBC 8-colour palette.
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


def mode2_offset(xbyte: int, y: int) -> int:
    return (y & 7) + (xbyte << 3) + ((y >> 3) * 0x280)


def unpack_byte(b: int):
    # Left pixel bits: 7,5,3,1. Right pixel bits: 6,4,2,0.
    c0 = (
        (((b >> 7) & 1) << 3)
        | (((b >> 5) & 1) << 2)
        | (((b >> 3) & 1) << 1)
        | (((b >> 1) & 1) << 0)
    )
    c1 = (
        (((b >> 6) & 1) << 3)
        | (((b >> 4) & 1) << 2)
        | (((b >> 2) & 1) << 1)
        | (((b >> 0) & 1) << 0)
    )
    return c0, c1


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--in", dest="inp", required=True, help="Input MODE2 .bin (20480 bytes)"
    )
    ap.add_argument("--out", dest="outp", required=True, help="Output .png")
    args = ap.parse_args()

    data = open(args.inp, "rb").read()
    if len(data) != 20480:
        raise SystemExit(f"Expected 20480 bytes, got {len(data)}")

    # Build raw RGB for 160x256.
    rgb = bytearray(160 * 256 * 3)
    for y in range(256):
        dst_row = y * 160 * 3
        for xb in range(80):
            b = data[mode2_offset(xb, y)]
            c0, c1 = unpack_byte(b)

            # MODE 2 supports 16 logical colours; we map flashing colours back to base.
            c0 &= 7
            c1 &= 7

            r, g, bl = BBC_PALETTE[c0]
            di = dst_row + (xb * 2) * 3
            rgb[di + 0] = r
            rgb[di + 1] = g
            rgb[di + 2] = bl

            r, g, bl = BBC_PALETTE[c1]
            di += 3
            rgb[di + 0] = r
            rgb[di + 1] = g
            rgb[di + 2] = bl

    # Write via ImageMagick.
    ppm_header = f"P6\n160 256\n255\n".encode("ascii")
    proc = subprocess.Popen(["convert", "ppm:-", args.outp], stdin=subprocess.PIPE)
    assert proc.stdin is not None
    proc.stdin.write(ppm_header)
    proc.stdin.write(rgb)
    proc.stdin.close()
    rc = proc.wait()
    if rc != 0:
        raise SystemExit(f"convert failed with exit code {rc}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.stderr.write(f"ERROR running ImageMagick: {e}\n")
        raise SystemExit(1)
