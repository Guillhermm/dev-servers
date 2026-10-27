#!/usr/bin/env python3
"""Generate the Dock icon for the Dev Servers app.

Draws three stacked server rows with status dots in pure Python, no image
libraries, then hands the PNGs to macOS `iconutil` to build the .icns.

    python3 tools/make_icon.py
"""

from __future__ import annotations

import math
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ICONSET = REPO / "build" / "icon.iconset"
OUT = REPO / "build" / "Dev Servers.app" / "Contents" / "Resources" / "icon.icns"

BG = (20, 28, 26)
BG_EDGE = (34, 48, 44)
ROW = (58, 74, 70)
SLOT = (30, 40, 38)
DOT_ON = (92, 214, 140)
DOT_OFF = (150, 160, 156)


def blend(dst, src, a):
    return tuple(round(d + (s - d) * a) for d, s in zip(dst, src))


def write_png(path: Path, px, size):
    raw = b"".join(
        b"\x00" + b"".join(bytes(px[y][x]) for x in range(size))
        for y in range(size)
    )

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    path.write_bytes(png)


def draw(size: int):
    S = size * 4  # supersample, then box-filter down
    px = [[BG for _ in range(S)] for _ in range(S)]

    # rounded-square plate with a soft vertical gradient
    pad, radius = S * 0.06, S * 0.22
    for y in range(S):
        base = blend(BG_EDGE, BG, y / S)
        for x in range(S):
            dx = max(pad - x, 0, x - (S - pad - 1))
            dy = max(pad - y, 0, y - (S - pad - 1))
            cx = min(max(x, pad + radius), S - pad - radius)
            cy = min(max(y, pad + radius), S - pad - radius)
            if dx or dy:
                continue
            if math.hypot(x - cx, y - cy) <= radius:
                px[y][x] = base

    def rrect(x0, y0, x1, y1, r, col):
        for y in range(int(y0), int(y1) + 1):
            for x in range(int(x0), int(x1) + 1):
                if not (0 <= x < S and 0 <= y < S):
                    continue
                cx = min(max(x, x0 + r), x1 - r)
                cy = min(max(y, y0 + r), y1 - r)
                d = math.hypot(x - cx, y - cy)
                if d <= r + 1:
                    px[y][x] = blend(px[y][x], col, min(1.0, max(0.0, r + 1 - d)))

    def disc(cx, cy, r, col):
        rrect(cx - r, cy - r, cx + r, cy + r, r, col)

    # three stacked server rows, each with a status dot and two vent slots
    row_h, gap = S * 0.17, S * 0.045
    top = S * 0.5 - (3 * row_h + 2 * gap) / 2
    left, right = S * 0.20, S * 0.80
    dots = [DOT_ON, DOT_ON, DOT_OFF]
    for i in range(3):
        y0 = top + i * (row_h + gap)
        y1 = y0 + row_h
        rrect(left, y0, right, y1, row_h * 0.28, ROW)
        disc(left + row_h * 0.62, (y0 + y1) / 2, row_h * 0.19, dots[i])
        for k in range(2):
            sx = left + row_h * 1.35 + k * row_h * 0.62
            rrect(sx, (y0 + y1) / 2 - row_h * 0.07, sx + row_h * 0.42, (y0 + y1) / 2 + row_h * 0.07,
                  row_h * 0.07, SLOT)

    # box-filter down to the target size
    out = [[BG] * size for _ in range(size)]
    for y in range(size):
        for x in range(size):
            acc = [0, 0, 0]
            for j in range(4):
                for i in range(4):
                    p = px[y * 4 + j][x * 4 + i]
                    acc[0] += p[0]; acc[1] += p[1]; acc[2] += p[2]
            out[y][x] = tuple(v // 16 for v in acc)
    return out


def main() -> int:
    if not shutil.which("iconutil"):
        print("iconutil not found (macOS only)", file=sys.stderr)
        return 1
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True)
    OUT.parent.mkdir(parents=True, exist_ok=True)

    for size, names in [
        (16, ["icon_16x16.png"]), (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
        (64, ["icon_32x32@2x.png"]), (128, ["icon_128x128.png"]),
        (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
        (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
        (1024, ["icon_512x512@2x.png"]),
    ]:
        img = draw(size)
        for n in names:
            write_png(ICONSET / n, img, size)
        print(f"  {size}px")

    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(OUT)], check=True)
    shutil.rmtree(ICONSET)
    print(f"wrote {OUT}  ({OUT.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
