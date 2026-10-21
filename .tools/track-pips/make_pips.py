"""Builds the upgrade track pips Item Icons draws
(EllesmereUIQoL_ItemIcons_Track.lua).

EllesmereUIQoL/Media/track_pips_<n>.tga, n = 1 to 5: n white pips with a dark
rim, on transparent, laid out as dice faces (1 center, 2 diagonal, 3 diagonal
and center, 4 corners, 5 corners and center). The code tints the white with
the track color; the rim stays dark, so the pips read on bright icons.

Each file is 64x64, uncompressed 32-bit BGRA, rows bottom-up (descriptor 0x08,
8 alpha bits), with no footer. Edges are antialiased from SUB x SUB samples
per texel.

Run from the suite root: python .tools/track-pips/make_pips.py
"""
import os
import struct

SIZE, SUB = 64, 8
FILL_R, RIM_R = 8.5, 11.5       # white fill radius, outer radius of the rim
RIM_ALPHA = 0.85
LO, MID, HI = 12.5, 32.0, 51.5  # pip centers, texels from the top-left as drawn

LAYOUTS = {
    1: [(MID, MID)],
    2: [(HI, LO), (LO, HI)],
    3: [(HI, LO), (MID, MID), (LO, HI)],
    4: [(LO, LO), (HI, LO), (LO, HI), (HI, HI)],
    5: [(LO, LO), (HI, LO), (MID, MID), (LO, HI), (HI, HI)],
}

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "EllesmereUIQoL", "Media")


def render(centers):
    """Rows of (gray, alpha) in 0..1, row 0 = the top as drawn."""
    fill2, rim2 = FILL_R * FILL_R, RIM_R * RIM_R
    img = []
    for ty in range(SIZE):
        row = []
        for tx in range(SIZE):
            lit = cover = 0.0
            for sy in range(SUB):
                y = ty + (sy + 0.5) / SUB
                for sx in range(SUB):
                    x = tx + (sx + 0.5) / SUB
                    d2 = min((x - cx) ** 2 + (y - cy) ** 2 for cx, cy in centers)
                    if d2 <= fill2:
                        lit += 1.0
                        cover += 1.0
                    elif d2 <= rim2:
                        cover += RIM_ALPHA
            n = SUB * SUB
            row.append((lit / cover if cover > 0 else 0.0, cover / n))
        img.append(row)
    return img


def write_tga(path, img):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x08)
    body = bytearray()
    for y in range(SIZE - 1, -1, -1):           # bottom-up
        for gray, alpha in img[y]:
            g = int(round(gray * 255))
            body += bytes((g, g, g, int(round(alpha * 255))))   # B, G, R, A
    with open(path, "wb") as f:
        f.write(header + bytes(body))


def main():
    for n, centers in sorted(LAYOUTS.items()):
        write_tga(os.path.join(OUT, "track_pips_%d.tga" % n), render(centers))
    print("wrote track_pips_1..%d.tga to %s" % (len(LAYOUTS), OUT))


if __name__ == "__main__":
    main()
