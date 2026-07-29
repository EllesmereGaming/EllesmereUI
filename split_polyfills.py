import os
import re

with open('Polyfills.lua', 'r') as f:
    lines = f.readlines()

def get_block_by_indices(start_idx, end_idx):
    return "".join(lines[start_idx:end_idx])

# The sections for API.lua:
api_lua = """local _G = _G or getfenv(0)
_G.EllesmereUI = _G.EllesmereUI or {}
_G.EllesmereUI._deferredInits = _G.EllesmereUI._deferredInits or {}

EUI = EUI or {}
EUI.API = EUI.API or {}

""" + get_block_by_indices(12, 428) + get_block_by_indices(569, 1262)

with open('Compatibility/API.lua', 'w') as f:
    f.write(api_lua)

# Texture.lua:
color_lua = get_block_by_indices(429, 467)
with open('Compatibility/Texture.lua', 'w') as f:
    f.write("-- Texture.lua\n")
    f.write(color_lua)

# Timer.lua:
timer_lua = get_block_by_indices(469, 569)
with open('Compatibility/Timer.lua', 'w') as f:
    f.write("-- Timer.lua\n")
    f.write(timer_lua)

# Atlas.lua:
atlas_lua = "EUI_AtlasMap = {\n"
for i in range(1295, 1314):
    atlas_lua += lines[i]
atlas_lua += "}\n"
with open('Compatibility/Atlas.lua', 'w') as f:
    f.write(atlas_lua)

# Empty others:
for fname in ["Cooldown.lua", "Secure.lua", "Layout.lua"]:
    with open(f"Compatibility/{fname}", 'w') as f:
        f.write(f"-- {fname}\n")
