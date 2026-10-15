"""Builds the Glow / Shadow corner art EllesmereUI_RoundedCorners.lua draws.

Every texel samples the glow border's own edge cell (the left cell of
media/borders/glow-border.tga, which the rounded sides draw) at its distance
from the rounded outline, so a corner and the side it meets fade alike.

Two sets, each 64x64, white with the fade in alpha, texel (0, 0) at the outer
corner of the TOPLEFT piece as drawn:
  glow-corner-<n>.tga  radius at least half the glow width: the piece runs
                       from its outer corner to the arc center, the band
                       round the outline. Step f = band width / radius, NA
                       steps spaced evenly in log(f) from F_MIN to 2.
  glow-tight-<n>.tga   radius under half the glow width: the piece is the
                       square the whole band crosses, its arc center at k of
                       it (k = S / E, S = E / 2 + radius). NB steps of k
                       between 0.5 and 1.
F_MIN, NA and NB must match GLOW_FMIN, GLOW_NA and GLOW_NB in the Lua file.
The TGA header and footer are copied from a shipped 64x64 file.

Run from the suite root: python .tools/rounded-glow/make_glow_corners.py
"""
import math
import os
import struct

F_MIN, NA, NB = 0.03, 32, 12
SIZE, SUB = 64, 8

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MEDIA = os.path.join(ROOT, "media")
OUT = os.path.join(MEDIA, "rounded")


def load_alpha(path):
    """Alpha rows of an uncompressed 32-bit TGA, row 0 = the top as drawn."""
    b = open(path, "rb").read()
    assert b[2] == 2 and b[16] == 32, "uncompressed 32-bit TGA expected"
    w, h = struct.unpack("<HH", b[12:16])
    top_down = bool(b[17] & 0x20)
    off = 18 + b[0]
    rows = []
    for row in range(h):
        y = row if top_down else h - 1 - row
        rows.append((y, [b[off + (row * w + x) * 4 + 3] for x in range(w)]))
    rows.sort()
    return w, h, [r for _, r in rows]


# The edge cell's fade across the band, outer side first (texels 0..31 of the
# left cell; every row is the same).
_, _, EDGE_ROWS = load_alpha(os.path.join(MEDIA, "borders", "glow-border.tga"))
PROFILE = [a / 255.0 for a in EDGE_ROWS[len(EDGE_ROWS) // 2][:32]]


def fade(f):
    """The side piece's alpha at fraction f across the band (0 = outer edge),
    filtered the way the client samples the strip (linear between texels)."""
    if f < 0.0 or f > 1.0:
        return 0.0
    g = f * 32.0 - 0.5
    i = int(math.floor(g))
    t = g - i
    a = PROFILE[min(31, max(0, i))]
    b = PROFILE[min(31, max(0, i + 1))]
    return a + (b - a) * t


def corner_alpha(x, y, e):
    """glow-corner: unit piece, arc center (1, 1), band e wide inside the
    circle of radius 1 round it (the outline runs mid-band). A step f (band
    width over the outline radius) gives e = f / (1 + f / 2)."""
    rho = math.hypot(1.0 - x, 1.0 - y)
    return fade((1.0 - rho) / e)


def tight_alpha(x, y, k):
    """glow-tight: unit piece = the band width, arc center (k, k); past the
    center on either axis the band runs straight, as on the sides."""
    if x < k and y < k:
        return fade(k - math.hypot(k - x, k - y))
    if x < k:
        return fade(x)
    if y < k:
        return fade(y)
    return fade(min(x, y))


def render(fn, p):
    img = []
    for ty in range(SIZE):
        row = []
        for tx in range(SIZE):
            s = 0.0
            for sy in range(SUB):
                y = (ty + (sy + 0.5) / SUB) / SIZE
                for sx in range(SUB):
                    x = (tx + (sx + 0.5) / SUB) / SIZE
                    s += fn(x, y, p)
            row.append(int(round(255.0 * s / (SUB * SUB))))
        img.append(row)
    return img


def write_tga(path, img, template):
    t = open(template, "rb").read()
    header, footer = t[:18], t[18 + SIZE * SIZE * 4:]
    assert struct.unpack("<HH", header[12:16]) == (SIZE, SIZE)
    assert not (header[17] & 0x20), "template stores rows bottom-up"
    body = bytearray()
    for y in range(SIZE - 1, -1, -1):           # bottom-up, as the template
        for a in img[y]:
            body += bytes((255, 255, 255, a))   # B, G, R, A
    open(path, "wb").write(header + bytes(body) + footer)


def main():
    template = os.path.join(OUT, "rounded-8.tga")
    for n in range(1, NA + 1):
        f = F_MIN * (2.0 / F_MIN) ** ((n - 1) / (NA - 1))
        write_tga(os.path.join(OUT, "glow-corner-%d.tga" % n), render(corner_alpha, f / (1.0 + f / 2.0)), template)
    for n in range(1, NB + 1):
        k = 0.5 + 0.5 * (n - 0.5) / NB
        write_tga(os.path.join(OUT, "glow-tight-%d.tga" % n), render(tight_alpha, k), template)
    print("wrote %d glow-corner and %d glow-tight files to %s" % (NA, NB, OUT))


if __name__ == "__main__":
    main()
