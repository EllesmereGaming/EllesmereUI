"""Builds the pill and circle art EllesmereUI_RoundedCorners.lua draws the settings
controls with (EllesmereUI.SetPillArt / SetCircleArt), one texel per screen pixel.

pill-<h>.tga (white, the shape in alpha) for h = 2..48: a stadium h texels tall
with round ends of radius h / 2. Its width is 2 * floor(h / 2) + 1, the slice
margins floor(h / 2) left and right and none top and bottom, so the one middle
column is what the straight run stretches: for an even h the ends are whole
half circles and the middle column is the straight run; for an odd h the
middle column is the circle's own centre column. Drawn h pixels tall on a layer
of one unit per pixel, every texel lands on one pixel at any width.

circle-<d>.tga for d = 2..48: a circle d texels across, drawn unsliced on a
region d pixels square (the toggle knob, the slider thumb).

The header is the shipped 64x64 masks' (uncompressed 32-bit, rows bottom-up),
only its width and height set; the footer is copied as is.

Run from the suite root: python .tools/rounded-glow/make_pill_art.py
"""
import os
import struct

MIN_H, MAX_H, SUB = 2, 48, 8

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "media", "rounded")


def stadium(x, y, h, cxl, cxr):
    """Inside the stadium of height h whose end circles (radius h / 2) are
    centred at (cxl, h / 2) and (cxr, h / 2), with the straight run between."""
    r = h / 2.0
    if y < 0 or y > h:
        return False
    if cxl <= x <= cxr:
        return True
    cx = cxl if x < cxl else cxr
    return (x - cx) ** 2 + (y - r) ** 2 <= r * r


def render(w, h, inside):
    img = []
    for ty in range(h):
        row = []
        for tx in range(w):
            hits = 0
            for sy in range(SUB):
                for sx in range(SUB):
                    if inside(tx + (sx + 0.5) / SUB, ty + (sy + 0.5) / SUB):
                        hits += 1
            row.append(int(round(255.0 * hits / (SUB * SUB))))
        img.append(row)
    return img


def write_tga(path, img, header, footer):
    h, w = len(img), len(img[0])
    head = bytearray(header)
    head[12:16] = struct.pack("<HH", w, h)
    body = bytearray()
    for y in range(h - 1, -1, -1):              # bottom-up, as the header says
        for a in img[y]:
            body += bytes((255, 255, 255, a))   # B, G, R, A
    open(path, "wb").write(bytes(head) + bytes(body) + footer)


def main():
    # The shipped 64x64 mask format (read from a file this tool never writes).
    t = open(os.path.join(OUT, "glow-corner-1.tga"), "rb").read()
    assert t[2] == 2 and t[16] == 32 and not (t[17] & 0x20), "uncompressed bottom-up 32-bit TGA expected"
    header, footer = t[:18], t[18 + 64 * 64 * 4:]
    for h in range(MIN_H, MAX_H + 1):
        m = h // 2
        w = 2 * m + 1
        if h % 2 == 0:
            cxl, cxr = float(m), float(m + 1)       # whole half circles, a 1 texel run
        else:
            cxl = cxr = m + 0.5                     # the centre column is the run
        img = render(w, h, lambda x, y, h=h, a=cxl, b=cxr: stadium(x, y, h, a, b))
        write_tga(os.path.join(OUT, "pill-%d.tga" % h), img, header, footer)
        c = h / 2.0
        img = render(h, h, lambda x, y, c=c: (x - c) ** 2 + (y - c) ** 2 <= c * c)
        write_tga(os.path.join(OUT, "circle-%d.tga" % h), img, header, footer)
    print("wrote pill-%d..%d and circle-%d..%d to %s" % (MIN_H, MAX_H, MIN_H, MAX_H, OUT))


if __name__ == "__main__":
    main()
