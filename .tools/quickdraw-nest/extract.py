#!/usr/bin/env python3
"""Cut the nest-geometry functions out of EUI_Quickdraw_Geometry.lua and
EUI_Quickdraw_Nests.lua by name, so sweep.lua always runs the live source rather
than a stale copy of it.

    python3 extract.py && lua5.1 sweep.lua

Cut by NAME rather than by line number on purpose: a copy pinned to line
numbers goes quietly stale the first time anything above it moves, and the
sweep would then be proving something about last week's geometry."""
import os, re

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_DIR = os.path.join(HERE, "..", "..", "EllesmereUIQuickdraw")
# The files that hold the nest geometry, in load order.
SRCS = ["EUI_Quickdraw_Geometry.lua", "EUI_Quickdraw_Nests.lua"]
OUT = os.path.join(HERE, "geom_extract.lua")

lines = []
for name in SRCS:
    lines += open(os.path.join(SRC_DIR, name)).read().split("\n")
defs = []  # (lineno0, name)
for i, l in enumerate(lines):
    m = re.match(r"^local function (\w+)|^function PaletteView:(\w+)|^function (\w+)\(", l)
    if m:
        defs.append((i, m.group(1) or m.group(2) or m.group(3)))

def span(first, last):
    """lines from the def of `first` up to just before the def after `last`."""
    starts = {n: i for i, n in defs}
    a = starts[first]
    idx = [k for k, (i, n) in enumerate(defs) if n == last][0]
    b = defs[idx + 1][0] if idx + 1 < len(defs) else len(lines)
    return lines[a:b]

out = ["-- extracted from " + " and ".join(SRCS) + " by extract.py -- do not edit"]
for pair in [("NestBBox", "AddRegion"), ("AutoGridColumns", "GridBase"),
             ("PerimeterSpan", "PerimeterNearest"),
             ("NestMetrics", "RunBox"), ("PerimeterNest", "HaloNest"),
             ("StripCellNest", "StripCellNest"),
             ("CellChildGeom", "CellChildGeom")]:
    out += span(*pair)
open(OUT, "w").write("\n".join(out) + "\n")
print("wrote", OUT, len(out), "lines")
