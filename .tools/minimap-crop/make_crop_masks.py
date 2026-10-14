"""Builds the crop masks of the Forever client's square minimap frames
(EllesmereUIMinimap.lua, EBS._MapCrop).

While a square frame (the WoW Forever look's Forever Square, Blizzard Style's
slim Square) shows its title bar, the map loses half the bar's extra height
off its top and bottom each, so the whole frame, bar included, is a square.
The canvas stays square (Blizzard's projection and player arrow need it) and a
mask cuts the strips, as Rectangular's 4:3 crop mask does; a crop of fixed
pixels is a different share of every map size, so there is one mask per cut.

EllesmereUIMinimap/Media/crop/minimap-crop-<r>.tga (the module's own media:
only the minimap uses them) keeps the middle of a 256-row mask and cuts r
rows off its top and its bottom (the minimap stretches the mask over the
canvas, so r rows are r * size / 256 pixels). The code picks the r nearest
the crop and sizes the map's visible rect from that r, so the cut and the
frame agree.

The range covers both frames' crops over the Map Size slider (100 to 600):
r = round(crop * 256 / size). Keep TITLE_OUT and SIZES in step with
EBS.FV_SQUARE_* / EBS.FV_SLIM_* and the options slider, and EBS.CROP_MASK_MIN /
CROP_MASK_MAX with the range printed here.

The header and footer are the shipped minimap_rectangular-crop-mask.tga's
(uncompressed 32-bit, rows bottom-up, 8 alpha bits), copied as they are but
for the width: the masks are 8 texels wide, every column alike.

Run from the suite root: python .tools/minimap-crop/make_crop_masks.py
"""
import os
import struct

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "EllesmereUIMinimap", "Media", "minimap_rectangular-crop-mask.tga")
OUT = os.path.join(ROOT, "EllesmereUIMinimap", "Media", "crop")

# (title bar's outer edge above the map's top, frame's outer edge past the
# map's other edges): Forever Square, Blizzard Style's slim Square.
TITLE_OUT = [(27.0, 3.0), (24.0, 2.75)]
SIZES = (100, 600)
ROWS, WIDTH = 256, 8
CUT = bytes((0, 0, 0, 0))            # the shipped mask's cut texel
KEEP = bytes((255, 255, 255, 255))   # BGRA


def crop_rows():
    rs = []
    for title, out in TITLE_OUT:
        crop = (title - out) / 2.0
        for size in SIZES:
            rs.append(int(crop * ROWS / size + 0.5))
    return min(rs), max(rs)


def main():
    src = open(SRC, "rb").read()
    header = bytearray(src[:18])
    w, h = struct.unpack("<HH", bytes(header[12:16]))
    assert header[2] == 2 and header[16] == 32 and header[17] == 0x08 and (w, h) == (256, ROWS), header.hex()
    footer = src[18 + w * h * 4:]
    assert footer.endswith(b"TRUEVISION-XFILE.\x00") and len(footer) == 26, footer
    header[12:14] = struct.pack("<H", WIDTH)
    lo, hi = crop_rows()
    os.makedirs(OUT, exist_ok=True)
    for r in range(lo, hi + 1):
        rows = []
        for y in range(ROWS):
            rows.append((CUT if y < r or y >= ROWS - r else KEEP) * WIDTH)
        data = bytes(header) + b"".join(rows) + footer
        with open(os.path.join(OUT, "minimap-crop-%d.tga" % r), "wb") as f:
            f.write(data)
    print("wrote minimap-crop-%d .. %d (%d masks, %d bytes each) to %s" % (lo, hi, hi - lo + 1, len(data), OUT))


if __name__ == "__main__":
    main()
