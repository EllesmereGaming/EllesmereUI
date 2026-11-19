`HunterTracking.tga` contains Blizzard's tracking artwork in a 4-by-4 grid of
64-pixel cells. Cells 1-7 follow the public creature-type IDs: Beast, Dragonkin,
Demon, Elemental, Giant, Undead, Humanoid. Cells 8-16 use the question-mark icon
for creature types without a tracking spell. A clipped viewport applies the
normal icon's public crop and zoom without changing the sprite's secret UVs.

`HunterTrackingVisibility.tga` is an original 16-by-128 pixel alpha mask.
Columns follow the same creature-type IDs; rows 0-127 are bitmasks of the
seven active or unlearned trackers (Beast is bit 0, Humanoid is bit 6).
A set bit makes that column transparent; unsupported types are always
transparent. Native sprite selection supplies the restricted X coordinates,
while public player tracking state selects the row. Nearest filtering keeps
each cell uniformly visible or hidden, including the reminder's border.

Spell/icon file IDs, verified against [Wago Tools](https://wago.tools/db2/SpellMisc):
1494/132328, 19879/134153, 19878/136217, 19880/135861, 19882/132275,
19884/136142, 19883/135942; question mark 134400.

Artwork: Blizzard Entertainment, from the [Blizzard UI texture mirror](https://github.com/Gethe/wow-ui-textures/tree/live/ICONS).
