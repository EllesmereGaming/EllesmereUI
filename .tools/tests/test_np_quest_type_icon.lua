-- Stub harness: the Nameplates quest objective type icon. Cuts the objective type resolver, its cache and the
-- cache drop from EUI_Nameplates_Colors.lua and the icon layout helper from EUI_Nameplates_Name.lua, and drives:
--   1. a quest's kill and item objectives resolve to their types by their exact text;
--   2. no match, two objectives with the same text, an unreadable objective and other objective types give nil
--      (the generic quest icon), never a guess;
--   3. secret values, a quest not on the log and a bad quest ID give nil;
--   4. the objectives are read once per quest until the cache is dropped, an unreadable list is remembered,
--      and the drop does nothing while the option is off;
--   5. the layout: the element's width and height, the count left-aligned with the frame, the icon 2 px right of
--      the count and flush with the frame's right edge, the 8 px floor.
--   lua .tools/tests/test_np_quest_type_icon.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local COLORS_SRC = ReadSource("EllesmereUINameplates/EUI_Nameplates_Colors.lua")
local NAME_SRC = ReadSource("EllesmereUINameplates/EUI_Nameplates_Name.lua")

local function Cut(src, from, to, label)
    local s = src:find(from, 1, true)
    local e = s and src:find(to, s, true)
    assert(s and e, label .. " not found")
    return src:sub(s, e - 1)
end

-------------------------------------------------------------------------------
--  Stubs
-------------------------------------------------------------------------------
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local SECRET = {}
function issecretvalue(v) return v == SECRET end
local OBJECTIVES, reads = {}, 0
C_QuestLog = {
    GetQuestObjectives = function(questID)
        reads = reads + 1
        return OBJECTIVES[questID]
    end,
}

local ns = { _questObjType = {} }
local resolverSrc = Cut(COLORS_SRC, "local questObjectiveTypeCache = {}",
    "\n-- Is this unit one of the local player's active quest objectives", "the resolver")
local dropSrc = Cut(COLORS_SRC, "function ns.InvalidateQuestObjectiveTypeCache()",
    "\n-- Live refresh for the quest options", "the cache drop")
-- The cut takes the resolver's two cache lines with it; only the resolver and the drop are exported.
local Resolve = assert(loadstring("local ns = ...\n" .. resolverSrc .. "\n" .. dropSrc
    .. "\nreturn ResolveQuestObjectiveType\n", "=Colors cut"))(ns)
local Layout = assert(loadstring("local ns = ...\n" .. Cut(NAME_SRC, "function ns.NP_QuestTypeIconLayout(",
    "\n-- Hides the frame; the name width", "the layout helper") .. "\nreturn ns.NP_QuestTypeIconLayout\n",
    "=Name cut"))(ns)

local function Eq(got, want, label)
    if got ~= want then error(label .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2) end
end

-------------------------------------------------------------------------------
--  1. kill and item objectives by their exact text
-------------------------------------------------------------------------------
OBJECTIVES[101] = {
    { text = "0/6 Kobold Vermin slain", type = "monster" },
    { text = "0/4 Gold Dust", type = "item" },
}
Eq(Resolve(101, "0/6 Kobold Vermin slain", true), "monster", "a kill objective")
Eq(Resolve(101, "0/4 Gold Dust", true), "item", "an item objective")

-------------------------------------------------------------------------------
--  2. never a guess
-------------------------------------------------------------------------------
Eq(Resolve(101, "0/6 Kobold Vermin", true), nil, "a text no objective has")
OBJECTIVES[102] = {
    { text = "0/3 Boars", type = "monster" },
    { text = "0/3 Boars", type = "item" },
}
Eq(Resolve(102, "0/3 Boars", true), nil, "two objectives with the same text")
OBJECTIVES[103] = {
    { text = "0/5 Wolves slain", type = "monster" },
    { text = nil, type = "item" },
}
Eq(Resolve(103, "0/5 Wolves slain", true), nil, "a quest with an unreadable objective")
OBJECTIVES[104] = {
    { text = "0/1 Crates searched", type = "object" },
    { text = "Explore the mine", type = "event" },
    { text = "0/1 Ward placed", type = "progressbar" },
}
Eq(Resolve(104, "0/1 Crates searched", true), nil, "an object objective")
Eq(Resolve(104, "Explore the mine", true), nil, "an event objective")
OBJECTIVES[105] = {
    { text = SECRET, type = "monster" },
}
Eq(Resolve(105, "0/2 Gnolls", true), nil, "a secret objective text")
OBJECTIVES[106] = { SECRET }
Eq(Resolve(106, "0/2 Gnolls", true), nil, "a secret objective entry")
OBJECTIVES[107] = {
    { text = "0/2 Gnolls slain", type = SECRET },
}
Eq(Resolve(107, "0/2 Gnolls slain", true), nil, "a secret objective type")

-------------------------------------------------------------------------------
--  3. secret inputs, a quest not on the log, a bad quest ID
-------------------------------------------------------------------------------
Eq(Resolve(SECRET, "0/4 Gold Dust", true), nil, "a secret quest ID")
Eq(Resolve(101, SECRET, true), nil, "a secret tooltip text")
Eq(Resolve(101, "0/4 Gold Dust", SECRET), nil, "a secret on-quest answer")
Eq(Resolve(101, "0/4 Gold Dust", false), nil, "a quest not on the log")
-- bad IDs get objectives of their own, so only the ID checks keep them out
OBJECTIVES[0], OBJECTIVES[101.5] = OBJECTIVES[101], OBJECTIVES[101]
Eq(Resolve(0, "0/4 Gold Dust", true), nil, "quest ID 0")
Eq(Resolve(101.5, "0/4 Gold Dust", true), nil, "a fractional quest ID")
Eq(Resolve(101, nil, true), nil, "no tooltip text")

-------------------------------------------------------------------------------
--  4. the cache and its drop
-------------------------------------------------------------------------------
ns._questObjectiveTypeEnabled = true
ns.InvalidateQuestObjectiveTypeCache()
reads = 0
Resolve(101, "0/6 Kobold Vermin slain", true)
Resolve(101, "0/4 Gold Dust", true)
Resolve(101, "nothing", true)
Eq(reads, 1, "objectives read once per quest")
-- progress moved: the cache is dropped (QUEST_LOG_UPDATE), the new text resolves
OBJECTIVES[101][1].text = "1/6 Kobold Vermin slain"
Eq(Resolve(101, "1/6 Kobold Vermin slain", true), nil, "a new count before the drop")
ns._questObjType.nameplate1 = "monster"
ns.InvalidateQuestObjectiveTypeCache()
Eq(ns._questObjType.nameplate1, nil, "the drop forgets the per-unit types")
Eq(Resolve(101, "1/6 Kobold Vermin slain", true), "monster", "a new count after the drop")
Eq(reads, 2, "objectives read again after the drop")
-- an unreadable list is remembered until the drop
OBJECTIVES[108] = SECRET
reads = 0
Resolve(108, "0/1 Thing", true)
Resolve(108, "0/1 Thing", true)
Eq(reads, 1, "an unreadable objective list read again")
-- option off: the drop does nothing
ns._questObjectiveTypeEnabled = false
ns._questObjType.nameplate2 = "item"
reads = 0
ns.InvalidateQuestObjectiveTypeCache()
Resolve(101, "1/6 Kobold Vermin slain", true)
Eq(reads, 0, "the drop ran with the option off")
Eq(ns._questObjType.nameplate2, "item", "the drop cleared the unit types with the option off")
ns._questObjectiveTypeEnabled = true

-------------------------------------------------------------------------------
--  5. the layout
-------------------------------------------------------------------------------
local function Check(counterW, counterH, fontSize, scale, wantSize)
    local w, h, textX, iconX, size = Layout(counterW, counterH, fontSize, scale)
    local label = ("layout %d/%d/%d/%d"):format(counterW, counterH, fontSize, scale)
    Eq(size, wantSize, label .. " icon size")
    Eq(w, counterW + 2 + size, label .. " width")
    Eq(h, math.max(counterH, size), label .. " height")
    Eq(textX - counterW / 2, -w / 2, label .. " count left edge")
    Eq(iconX, (textX + counterW / 2) + 2, label .. " icon 2 px right of the count")
    Eq(iconX + size, w / 2, label .. " icon right edge")
end
Check(20, 14, 14, 100, 11)   -- 14 x 0.8 = 11.2
Check(31, 24, 24, 200, 38)   -- 24 x 0.8 x 2 = 38.4
Check(12, 8, 6, 50, 8)       -- 6 x 0.8 x 0.5 = 2.4: the 8 px floor
Check(18, 12, 12, 150, 14)   -- 12 x 0.8 x 1.5 = 14.4

print("nameplates quest objective type icon harness: ok")
