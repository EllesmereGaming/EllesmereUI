"""Builds the Hide Power Bar mask of Blizzard Style's target frame art
(EUI_UnitFrames_StockStyles.lua, the blizzard kit's target.merged).

Hide Power Bar grows the health bar down over the power track. On the target
art the portrait ring sits on the right and its curve lets the power track run
further right under it than the health track, so neither stock bar mask fits
the taller bar: the health mask stretched stops short at the bottom (the power
track's end shows past the fill), the mana mask stretched cuts into the ring
mid-height. This mask is the two stock openings joined, as the bars sit on the
frame: the health mask's opening for the health track's 20 rows, the mana
mask's for the power track's 10, and the groove row between them filled with
the wider of its two neighbours.

Each opening row is the stock mask's own: a hard left edge, solid to the last
full column, then the measured edge alphas (retail 12.1.5, masks
UI-HUD-UnitFrame-Target-PortraitOn-Bar-Health-Mask and -Bar-Mana-Mask, in the
bar's own columns: health mask col - 1, mana mask col - 61, as the kit hangs
them). The bar is 134 wide (the power track) and 31 tall; the mask is 256 x 32
at 1 texel per unit, hung from the bar's top-left.

The header and footer are the shipped media/borders/glow-border.tga's
(uncompressed 32-bit, rows bottom-up, 256 x 32), copied as they are.

Run from the suite root: python .tools/stock-merged-mask/make_target_merged_mask.py
"""
import os

W, H = 256, 32

# (first column, last full column, alphas after it), per bar row, in the
# bar's columns. Health track: bar rows 0..19.
HEALTH = [
    (2, 122, (254, 16)), (1, 122, (207,)), (0, 122, (161,)), (0, 122, (74,)),
    (0, 122, (27,)), (0, 122, (25,)), (0, 121, (254, 24)), (0, 121, (254, 23)),
    (0, 121, (254, 23)), (0, 121, (254, 24)), (0, 122, (25,)), (0, 122, (25,)),
    (0, 122, (28,)), (0, 122, (72,)), (0, 122, (154,)), (0, 122, (202,)),
    (0, 122, (248, 16)), (0, 122, (253, 66)), (0, 123, (181,)), (0, 123, (245, 13)),
]
# Power track: bar rows 21..30.
POWER = [
    (0, 124, (233, 3)), (0, 124, (249, 95)), (0, 125, (232, 7)), (0, 125, (249, 142)),
    (0, 126, (237, 45)), (0, 126, (251, 218, 7)), (0, 127, (247, 171, 2)), (0, 128, (239, 140)),
    (1, 128, (253, 235, 108)), (2, 129, (253, 228, 108, 1)),
]

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "media", "borders", "glow-border.tga")
OUT = os.path.join(ROOT, "EllesmereUIUnitFrames", "Media", "blizz-target-merged-mask.tga")


def row(spec):
    first, last, edge = spec
    a = [0] * W
    for x in range(first, last + 1):
        a[x] = 255
    for i, v in enumerate(edge):
        a[last + 1 + i] = v
    return a


def render():
    rows = [row(s) for s in HEALTH]
    # The groove row: the wider of the health track's last row and the power
    # track's first, column by column.
    up, down = row(HEALTH[-1]), row(POWER[0])
    rows.append([max(u, d) for u, d in zip(up, down)])
    rows += [row(s) for s in POWER]
    while len(rows) < H:
        rows.append([0] * W)
    return rows


def main():
    t = open(SRC, "rb").read()
    assert t[2] == 2 and t[16] == 32 and not (t[17] & 0x20), "uncompressed bottom-up 32-bit TGA expected"
    assert t[12:16] == bytes((W & 255, W >> 8, H & 255, H >> 8)), "a %d x %d source expected" % (W, H)
    header, footer = t[:18], t[18 + W * H * 4:]
    img = render()
    body = bytearray()
    for y in range(H - 1, -1, -1):              # bottom-up, as the header says
        for a in img[y]:
            body += bytes((255, 255, 255, a))   # B, G, R, A
    open(OUT, "wb").write(header + bytes(body) + footer)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
