-- Stub harness: the Group Finder's per-character filters. Every character's
-- first login with filters of its own starts from a copy of the profile's
-- filters, and the profile keeps them for the characters that log in later;
-- filter keys read and write the character's copy, everything else the
-- profile; the results list's display settings live in the profile.
--   lua .tools/tests/test_gf_char_filters.lua      (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local SRC = ReadSource("EllesmereUIGroupFinder/EllesmereUIGroupFinder.lua")

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function CopyTable(t)
    local c = {}
    for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end
    return c
end
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end

local T = {}
EllesmereUI = {
    HELD_BACK_ADDONS = {},
    _ModuleNS = {},
    NewCombatQueue = function() return {} end,
    -- named in the module's stale-parent guard (the lists' font families, the
    -- settings preview's names)
    SetFontFamily = function() end,
    PREVIEW_ROSTER = {},
    Lite = {
        NewAddon = function() T.addon = {}; return T.addon end,
        NewDB = function(name, defaults)
            T.db = { profile = T.profile, ResetProfile = function(self) wipe(self.profile) end }
            return T.db
        end,
    },
}

-- a profile from before per-character filters, shared by two characters
T.profile = { search = { padding = 12, ratingOn = true, ratingValue = 2000, regions = { na = true },
    dimPicks = { activities = { 1, 2 } }, iconSize = 140 }, apps = {} }

local ns = {}
assert(loadstring(SRC, "=EllesmereUIGroupFinder.lua"))("EllesmereUIGroupFinder", ns)
assert(T.addon and T.addon.OnInitialize, "the module has no initialize")

-- before the profile is ready: the display settings read nothing, writes go nowhere
local early = ns.OwnListDB()
early.rowHeight = 30
assert(ns.OwnListDB().rowHeight == nil, "a write landed before the profile was ready")

-- 1. the first character: a copy of the profile's filters, the profile keeps its own
EllesmereUIGroupFinderCharDB = nil
T.addon:OnInitialize()
local first = EllesmereUIGroupFinderCharDB
assert(first.filters.ratingOn == true and first.filters.ratingValue == 2000, "the first character lost the filters")
assert(first.filters.regions.na == true and first.filters.dimPicks.activities[2] == 2)
assert(T.profile.search.ratingOn == true and T.profile.search.regions.na == true,
    "the profile's filters were taken from the characters that log in later")
assert(first.filters.regions ~= T.profile.search.regions, "the character's filters share a table with the profile")

-- reads and writes: filter keys are the character's, the rest the profile's
local cfg = ns.Cfg()
cfg.regions.eu = true
cfg.ratingValue = 2500
assert(T.profile.search.regions.eu == nil and T.profile.search.ratingValue == 2000,
    "a character's filter change reached the profile")
assert(cfg.ratingValue == 2500 and first.filters.regions.eu == true)
cfg.iconSize = 150
assert(T.profile.search.iconSize == 150 and first.filters.iconSize == nil, "a display setting left the profile")
-- Your Class: each tab's tick is the character's; the raids tab's Has / No pick is the profile's, like the dungeons one
cfg.extraMyClass, cfg.raidMyClass, cfg.raidMyClassMissing = true, true, false
assert(first.filters.extraMyClass == true and first.filters.raidMyClass == true
    and T.profile.search.extraMyClass == nil and T.profile.search.raidMyClass == nil,
    "a Your Class tick left the character")
assert(T.profile.search.raidMyClassMissing == false and first.filters.raidMyClassMissing == nil,
    "the raids tab's Has / No pick is not in the profile")
cfg.extraMyClass, cfg.raidMyClass, cfg.raidMyClassMissing = nil, nil, nil

-- the results list's display settings: in the profile
ns.OwnListDB().rowHeight = 44
assert(T.profile.ownList and T.profile.ownList.rowHeight == 44, "the list's settings are not in the profile")

-- 2. a second character on the same profile starts from the profile's filters too
EllesmereUIGroupFinderCharDB = nil
T.addon:OnInitialize()
local second = EllesmereUIGroupFinderCharDB
assert(second ~= first)
assert(second.filters.ratingOn == true and second.filters.ratingValue == 2000 and second.filters.regions.na == true,
    "the second character did not get the profile's filters")
assert(second.filters.regions.eu == nil, "the second character got the first one's own change")

-- 3. a character that already has filters keeps them
second.filters.ratingValue = 1800
T.addon:OnInitialize()
assert(EllesmereUIGroupFinderCharDB.filters.ratingValue == 1800, "a later login replaced the character's filters")

-- 4. the module reset clears the character's filters and the profile
ns.ResetSettings()
assert(next(EllesmereUIGroupFinderCharDB.filters) == nil and next(T.profile) == nil)

print("group finder character filters harness: ok")
