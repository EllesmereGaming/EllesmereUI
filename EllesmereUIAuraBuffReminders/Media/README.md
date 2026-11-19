`HunterTracking.tga` repacks Blizzard's icons into a 4-by-4 grid of 64-pixel
cells, indexed natively by creature type: 1-7 are Beast, Dragonkin, Demon,
Elemental, Giant, Undead, Humanoid; 8-16 are question marks. This avoids a Lua
table lookup with a secret creature type. Both files use lossless TGA RLE.

`HunterTrackingVisibility.tga` is an original 16-by-128 alpha lookup table.
Rows are active/unlearned tracking bitmasks (Beast bit 0, Humanoid bit 6);
set bits and unsupported types are transparent. A native reverse-fill bar
positions the secret column; public geometry selects the row. Full UVs and
nearest filtering preserve whole-cell visibility on the icon and border.

Spell/icon file IDs, verified against [Wago Tools](https://wago.tools/db2/SpellMisc):
1494/132328, 19879/134153, 19878/136217, 19880/135861, 19882/132275,
19884/136142, 19883/135942; question mark 134400.

Artwork: Blizzard Entertainment, from the [Blizzard UI texture mirror](https://github.com/Gethe/wow-ui-textures/tree/live/ICONS).
