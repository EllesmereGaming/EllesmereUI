"""Builds the rounded-rect mask textures EllesmereUI_RoundedCorners.lua slices.

rounded-<n>.tga (white, the shape in alpha) and rounded-inv-<n>.tga (its
inverse) for n = 1..16: a (2n + 1) x (2n + 1) square whose corners are quarter
circles of radius n round the slice corners, a 1-texel straight run between
them. The code sets n texel slice margins, so the corners are the slices and
the straight run is what the edges stretch.

The texture is only as large as its slices need: the client shrinks a sliced
texture's corners on a region smaller than the texture itself, so a 64 texel
mask lost most of its rounding on a thin bar. The code caps the radius so a
region is never smaller than its mask (RoundedCorners Fit: radius at most
(short side - 1) / 2).

The header is the shipped 64x64 masks' (uncompressed 32-bit, rows
bottom-up), only its width and height set; the footer is copied as is.

Run from the suite root: python .tools/rounded-glow/make_rounded_masks.py
"""
import os
import struct

MAX_N, SUB = 16, 8

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "media", "rounded")


def covered(x, y, n):
    """Inside the rounded square of side 2n + 1 with corner radius n."""
    size = 2 * n + 1
    if x < 0 or y < 0 or x > size or y > size:
        return False
    cx = n if x < n else (n + 1 if x > n + 1 else None)
    cy = n if y < n else (n + 1 if y > n + 1 else None)
    if cx is None or cy is None:
        return True                             # the straight runs
    return (x - cx) ** 2 + (y - cy) ** 2 <= n * n


def render(n):
    size = 2 * n + 1
    img = []
    for ty in range(size):
        row = []
        for tx in range(size):
            hits = 0
            for sy in range(SUB):
                for sx in range(SUB):
                    if covered(tx + (sx + 0.5) / SUB, ty + (sy + 0.5) / SUB, n):
                        hits += 1
            row.append(int(round(255.0 * hits / (SUB * SUB))))
        img.append(row)
    return img


def write_tga(path, img, header, footer):
    size = len(img)
    head = bytearray(header)
    head[12:16] = struct.pack("<HH", size, size)
    body = bytearray()
    for y in range(size - 1, -1, -1):           # bottom-up, as the header says
        for a in img[y]:
            body += bytes((255, 255, 255, a))   # B, G, R, A
    open(path, "wb").write(bytes(head) + bytes(body) + footer)


def main():
    # The shipped 64x64 mask format (read from a file this tool never writes).
    t = open(os.path.join(OUT, "glow-corner-1.tga"), "rb").read()
    assert t[2] == 2 and t[16] == 32 and not (t[17] & 0x20), "uncompressed bottom-up 32-bit TGA expected"
    header, footer = t[:18], t[18 + 64 * 64 * 4:]
    for n in range(1, MAX_N + 1):
        img = render(n)
        write_tga(os.path.join(OUT, "rounded-%d.tga" % n), img, header, footer)
        inv = [[255 - a for a in row] for row in img]
        write_tga(os.path.join(OUT, "rounded-inv-%d.tga" % n), inv, header, footer)
    print("wrote rounded-1..%d and rounded-inv-1..%d to %s" % (MAX_N, MAX_N, OUT))


if __name__ == "__main__":
    main()
