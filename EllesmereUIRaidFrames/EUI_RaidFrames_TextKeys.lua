if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_RaidFrames_TextKeys.lua
--
--  The texts a raid frame can show, by their setting keys: Name, Level, Health,
--  Power and Heal Absorb Text on their own keys, plus a second Health Text and
--  up to four Custom texts. Every text keeps its position, offsets, size and
--  colour (texts may share a position). Read by the engine and the tiles.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not I or I.broken then return end
I.broken = true

local ipairs = ipairs

-- The nine spots, in grid order (the tile order of the Text Display list).
local POSITIONS = { "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }
local POS_INDEX = {}
for i, p in ipairs(POSITIONS) do POS_INDEX[p] = i end
ns.RF_TEXT_POSITIONS, ns.RF_TEXT_POS_INDEX = POSITIONS, POS_INDEX

-- One text: kind, label, and its keys. mode: the mode key (Health, Power, Heal
-- Absorb); fmt: the template key (Custom); above: Show Above Icons (unset: as the
-- name's). The level is drawn in the name's colour.
local function Text(id, kind, label, prefix, mode)
    return { id = id, kind = kind, label = label, mode = mode and (prefix .. "Mode") or nil,
        pos = prefix .. "Position", x = prefix .. "OffsetX", y = prefix .. "OffsetY",
        size = prefix .. "Size", cm = prefix .. "ColorMode", col = prefix .. "CustomColor",
        above = prefix .. "AboveIcons" }
end

local TEXTS = {
    { id = "name", kind = "name", label = "Name", pos = "namePosition", x = "nameOffsetX",
      y = "nameOffsetY", size = "nameSize", cm = "nameColorMode", col = "nameCustomColor",
      above = "nameTextAboveIcons" },
    { id = "level", kind = "level", label = "Level", pos = "levelTextPosition", x = "levelTextOffsetX",
      y = "levelTextOffsetY", size = "levelTextSize", cm = "nameColorMode", col = "nameCustomColor",
      above = "levelTextAboveIcons" },
    Text("hp", "hp", "Health Text", "healthText", true),
    Text("hp2", "hp", "Second Health Text", "healthText2", true),
    Text("pp", "pp", "Power Text", "powerText", true),
    Text("ha", "ha", "Heal Absorb Text", "healAbsorbText", true),
}
ns.RF_CUSTOM_TEXT_MAX = 4
for n = 1, ns.RF_CUSTOM_TEXT_MAX do
    local t = Text("custom" .. n, "custom", "Custom Text " .. n, "customText" .. n)
    t.fmt = "customText" .. n .. "Format"
    TEXTS[#TEXTS + 1] = t
end
ns.RF_TEXTS = TEXTS

-- The keys this PR adds (the second Health Text and the Custom texts), for the
-- party sync list and the scaled sizes and offsets. Defaults: off.
local NEW_KEYS, NEW_SCALE_KEYS = {}, {}
local p = I.defaults.profile
for _, t in ipairs(TEXTS) do
    if t.id == "hp2" or t.kind == "custom" then
        for _, k in ipairs({ t.mode or t.fmt, t.pos, t.x, t.y, t.size, t.cm, t.col }) do
            NEW_KEYS[#NEW_KEYS + 1] = k
        end
        NEW_SCALE_KEYS[#NEW_SCALE_KEYS + 1] = t.size
        NEW_SCALE_KEYS[#NEW_SCALE_KEYS + 1] = t.x
        NEW_SCALE_KEYS[#NEW_SCALE_KEYS + 1] = t.y
        if t.mode then p[t.mode] = "none" end
        p[t.pos] = (t.kind == "custom") and "none" or "bottom"
        p[t.x], p[t.y], p[t.size], p[t.cm] = 0, 0, (t.kind == "custom") and 10 or 9, "custom"
        p[t.col] = { r = 1, g = 1, b = 1 }
    end
    -- Show Above Icons per text: new for every text but the name (no default).
    if t.id ~= "name" then NEW_KEYS[#NEW_KEYS + 1] = t.above end
end
ns.RF_TEXT_NEW_KEYS, ns.RF_TEXT_NEW_SCALE_KEYS = NEW_KEYS, NEW_SCALE_KEYS

I.broken = false
