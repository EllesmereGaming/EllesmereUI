`HunterTracking.tga` contains Blizzard's tracking artwork in a 4-by-4 grid of
64-pixel cells. Cells 1-7 follow the public creature-type IDs: Beast, Dragonkin,
Demon, Elemental, Giant, Undead, Humanoid. Cells 8-16 use the question-mark icon
for creature types without a tracking spell. A clipped viewport applies the
normal icon's public crop and zoom without changing the sprite's secret UVs.

`HunterTrackingVisibility.tga` is an original 16-by-128 pixel alpha mask.
Columns follow the same creature-type IDs; rows 0-127 are bitmasks of the
seven active or unlearned trackers (Beast is bit 0, Humanoid is bit 6).
A set bit makes that column transparent; unsupported types are always
transparent. A transparent native reverse-fill status bar takes the restricted
creature type as its value on a 0-16 range. Its fill's left edge positions the
mask so the chosen column overlaps the source. The mask spans 16 source widths
and 128 source heights; its public row shifts it up by that many source heights.
Its UVs stay at the full texture and are never read or rewritten. Nearest
filtering keeps each cell uniformly visible or hidden, including the border.

Spell/icon file IDs, verified against [Wago Tools](https://wago.tools/db2/SpellMisc):
1494/132328, 19879/134153, 19878/136217, 19880/135861, 19882/132275,
19884/136142, 19883/135942; question mark 134400.

Artwork: Blizzard Entertainment, from the [Blizzard UI texture mirror](https://github.com/Gethe/wow-ui-textures/tree/live/ICONS).
