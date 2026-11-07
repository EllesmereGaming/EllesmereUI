-- Stub harness: the WoW Forever section of AuraBuff Reminders shows nothing in
-- combat (its Where to Show offers no In Combat entry: always unchecked). Loads
-- the aura helpers and the collectors over a stubbed internals table and drives
-- EABR.CollectForever in and out of combat, and the pre-pull snapshot, which
-- Forever no longer takes.
--   lua .tools/tests/test_abr_forever_combat.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local AURAS_SRC = ReadSource("EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Auras.lua")
local REFRESH_SRC = ReadSource("EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Refresh.lua")
local OPTIONS_SRC = ReadSource("EllesmereUIOptions/EUI_AuraBuffReminders_Options.lua")

-------------------------------------------------------------------------------
--  Game API stubs
-------------------------------------------------------------------------------
local TEST = { combat = false, up = {}, auraReads = 0, trackingWanted = {} }

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetTime() return 100 end

-- The player's auras: TEST.up[id] = true while that spell's aura is up
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
        TEST.auraReads = TEST.auraReads + 1
        if TEST.up[id] then return { spellId = id, duration = 0, expirationTime = 0 } end
    end,
    GetAuraDataByIndex = function(unit, i)
        TEST.auraReads = TEST.auraReads + 1
        local n = 0
        for id in pairs(TEST.up) do
            n = n + 1
            if n == i then return { spellId = id, name = "Aura" .. id } end
        end
    end,
    GetAuraDataBySpellName = function() return nil end,
}

-- One skill line holding the custom spell and the group's spell
local NAMES = { [1001] = "Inner Fire", [2001] = "Arcane Brilliance", [2002] = "Arcane Intellect" }
local BOOK = { 1001, 2002 }
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 } }
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #BOOK } end,
    GetSpellBookItemType = function(slot) return 1, nil, BOOK[slot] end,
    IsSpellKnown = function(id) for _, sid in ipairs(BOOK) do if sid == id then return true end end return false end,
}
C_Spell = { GetSpellName = function(id) return NAMES[id] end }

EllesmereUIDB = {}
EllesmereUI = {
    -- The shared Intellect family's class list, read at load (the parent's
    -- EllesmereUI_BuffPresets.lua builds the real table in the game).
    FOREVER_BUFF_FAMILIES = { ai = { names = {}, single = {}, group = {}, ids = {},
        beneficiaries = { MAGE = true, PRIEST = true } } },
    AuraKit = { AurasRestricted = function() return false end },
    L = function(s) return s end,
}

-------------------------------------------------------------------------------
--  The internals the two files read (the main file and the earlier parts build
--  it in the game)
-------------------------------------------------------------------------------
local EABR = { FOREVER = true }
-- The real SectionShows' rule: an unchecked In Combat hides a section in combat
function EABR.SectionShows(where)
    if where and where.in_combat == false and TEST.combat then return false end
    return not (where and where.open_world == false)
end
function EABR.FvSyncTrackingEvent(want) TEST.trackingWanted[#TEST.trackingWanted + 1] = want end

local I = {
    EABR = EABR,
    AURA_SCAN_LIMIT = 40, ICON_SIZE = 32,
    NON_SECRET_SPELL_IDS = {}, PET_CLASSES = {}, RAID_BUFFS = {}, WARLOCK_PETS = {},
    _dismissedUntilLoad = {}, combatActiveIcons = {}, cursorActiveIcons = {},
    dbSetters = {}, panelOpenSetters = {}, iconAnchorSetters = {}, combatAnchorSetters = {},
    cursorAnchorSetters = {},
    InCombat = function() return TEST.combat end,
    InMythicPlusKey = function() return false end,
    isSecret = function() return false end,
    SpellName = function(id) return NAMES[id] end,
    Known = function(id) return C_SpellBook.IsSpellKnown(id) end,
    ShortLabel = function(s) return s end,
    Tex = function(id) return id end,
    AcquireEntry = function() return {} end,
    GetPlayerClass = function() return "PRIEST" end,
}
-- Every other name the files import is a function they do not call here
setmetatable(I, { __index = function(_, k)
    if k == "broken" then return nil end
    return function() end
end })

local ns = { _abrInternals = I }
assert(loadstring(AURAS_SRC, "=EUI_AuraBuffReminders_Auras.lua"))("EllesmereUIAuraBuffReminders", ns)
assert(rawget(I, "broken") == false, "the aura helpers did not load")
assert(loadstring(REFRESH_SRC, "=EUI_AuraBuffReminders_Refresh.lua"))("EllesmereUIAuraBuffReminders", ns)
assert(rawget(I, "broken") == false, "the collectors did not load")

local db = { profile = { forever = {
    camp = false, gather = false, gatherClassTrack = true, treasure = false, wellFed = false, mageArmor = false,
    whereToShow = {},
    customIDs = { 1001 },
    customGroups = { { name = "Intellect", ids = { 2001, 2002 } } },
} } }
for _, set in ipairs(I.dbSetters) do set(db) end
local fo = db.profile.forever

local function Collect()
    local missing = {}
    EABR.CollectForever(missing, false, false)
    local keys = {}
    for _, e in ipairs(missing) do keys[#keys + 1] = e.dismissKey end
    table.sort(keys)
    return table.concat(keys, ","), missing
end

-------------------------------------------------------------------------------
--  Scenarios
-------------------------------------------------------------------------------
-- 1. out of combat: the custom spell and the group are missing, so both show
local got = Collect()
assert(got == "forever:1001,forever:g1", "out of combat: " .. got)
assert(TEST.trackingWanted[#TEST.trackingWanted] == false, "the tracking event was asked for with no tracker on")

-- 2. their auras up: nothing shows
TEST.up[1001], TEST.up[2002] = true, true
got = Collect()
assert(got == "", "auras up, still shown: " .. got)
TEST.up[1001], TEST.up[2002] = nil, nil

-- 3. in combat: nothing from the section, though both are missing, the In Combat entry was never
--    unchecked, and the snapshot taken at the pull (none on Forever) would have said absent
TEST.combat = true
I.SnapshotPlayerAuras()
got = Collect()
assert(got == "", "in combat, the WoW Forever section showed: " .. got)
-- an In Combat entry an older build saved as checked changes nothing
fo.whereToShow.in_combat = true
got = Collect()
assert(got == "", "a saved In Combat entry let the section show in combat: " .. got)
fo.whereToShow.in_combat = nil
-- the gathering trackers listen for nothing in combat either
fo.gather, fo.treasure = true, true
Collect()
assert(TEST.trackingWanted[#TEST.trackingWanted] == false, "the minimap tracking event stayed on in combat")
TEST.combat = false
Collect()
assert(TEST.trackingWanted[#TEST.trackingWanted] == true, "the tracking event did not come back after combat")
fo.gather, fo.treasure = false, false

-- 4. after combat the reminders come back
got = Collect()
assert(got == "forever:1001,forever:g1", "after combat: " .. got)

-- 5. the pre-pull snapshot: Forever reads nothing from it, so it reads no aura; retail still takes it
TEST.up[1001] = true
TEST.auraReads = 0
I.SnapshotPlayerAuras()
assert(TEST.auraReads == 0, "the pre-pull snapshot read auras on WoW Forever")
EABR.FOREVER = false
I.SnapshotPlayerAuras()
assert(TEST.auraReads > 0, "the pre-pull snapshot no longer reads auras on retail")
EABR.FOREVER = true
TEST.up[1001] = nil

-- 6. the options: the WoW Forever section's Where to Show offers no In Combat entry (Raid Buffs
--    keeps its own)
local list = OPTIONS_SRC:match("local FOREVER_SECTION_WHERE_ITEMS = (%b{})")
assert(list, "the WoW Forever section has no list of its own")
assert(not list:find("in_combat", 1, true), "the WoW Forever section still offers In Combat")
assert(OPTIONS_SRC:find("whereStore = FWhere, whereItems = FOREVER_SECTION_WHERE_ITEMS,", 1, true),
    "the WoW Forever section does not use its own list")
local raid = OPTIONS_SRC:match("local FOREVER_WHERE_ITEMS = (%b{})")
assert(raid and raid:find("in_combat", 1, true), "Raid Buffs lost its In Combat entry on WoW Forever")

print("aurabuff reminders forever combat harness: ok")
