"""Builds the corner mask of the WoW Forever look's Slim border
(EllesmereUI_RetailAtlas.lua, EllesmereUI.ForeverBorder).

The Slim art (our shipped copy and Blizzard's live "UI-HUD-ActionBar-Frame")
is a filled box: a 60% black body inside the bronze line. The ring draws its
corners RC = 12 art units square, so each holds its chamfer whole, and this
mask hides the body inside them. forever-slim-mask.tga is one 2 x RC square
holding all four corners, a corner per quadrant (white, the shape in alpha):
each corner piece's mask is that square hung from the ring box's matching
corner, so the piece only ever samples its own quadrant (a MaskTexture
ignores texcoords, so one quadrant could not be flipped into the others).

Kept, measured from each corner (art units): everything within RD = 6 of
either side (the depth the straight edge pieces draw: the clear margin, the
outer shadow, the line and 1 unit of its inner shadow), and along the
chamfer everything up to DIAG = 15.25 on x + y. Both arts put the chamfer's
inner shadow at alpha 218 / 203 on either side of that cut, the same
darkness the straight edges are cut at (229 / 204), so corners and edges
meet the frame's own body alike. Everything past it (the rest of the inner
shadow and the body) is masked out.

The header and footer are the shipped glow-corner-1.tga's (uncompressed
32-bit, rows bottom-up, 64 x 64), copied as they are.

Run from the suite root: python .tools/forever-border/make_slim_mask.py
"""
import os

RC, RD, DIAG = 12.0, 6.0, 15.25   # art units
SIDE = 2 * RC                      # the mask's square, art units
SIZE, SUB = 64, 8                  # texels a side, samples a texel a side

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "media", "rounded", "glow-corner-1.tga")
OUT = os.path.join(ROOT, "media", "borders", "forever-slim-mask.tga")


def kept(x, y):
    """A point of the square (art units, top-left origin), folded into its
    quadrant's corner."""
    fx = x if x < RC else SIDE - x
    fy = y if y < RC else SIDE - y
    return fx < RD or fy < RD or fx + fy <= DIAG


def render():
    img = []
    for ty in range(SIZE):
        row = []
        for tx in range(SIZE):
            hits = 0
            for sy in range(SUB):
                for sx in range(SUB):
                    x = (tx + (sx + 0.5) / SUB) * SIDE / SIZE
                    y = (ty + (sy + 0.5) / SUB) * SIDE / SIZE
                    if kept(x, y):
                        hits += 1
            row.append(int(round(255.0 * hits / (SUB * SUB))))
        img.append(row)
    return img


def main():
    t = open(SRC, "rb").read()
    assert t[2] == 2 and t[16] == 32 and not (t[17] & 0x20), "uncompressed bottom-up 32-bit TGA expected"
    assert t[12:16] == bytes((SIZE, 0, SIZE, 0)), "a %d x %d source expected" % (SIZE, SIZE)
    header, footer = t[:18], t[18 + SIZE * SIZE * 4:]
    img = render()
    body = bytearray()
    for y in range(SIZE - 1, -1, -1):           # bottom-up, as the header says
        for a in img[y]:
            body += bytes((255, 255, 255, a))   # B, G, R, A
    open(OUT, "wb").write(header + bytes(body) + footer)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
