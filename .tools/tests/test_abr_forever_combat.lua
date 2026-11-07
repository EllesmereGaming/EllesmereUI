-- Stub harness: the WoW Forever section of AuraBuff Reminders shows nothing in
-- combat (its Where to Show offers no In Combat entry: always unchecked). Loads
-- the aura helpers and the collectors over a stubbed internals table and drives
-- EABR.CollectForever in and out of combat, and the pre-pull snapshot, which
-- Forever no longer takes. Scenario 7 drives the Weapon Buffs reminder.
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
local TEST = { combat = false, up = {}, auraReads = 0, trackingWanted = {}, weaponWanted = {},
    weapon = {}, enchants = {}, bags = {} }

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
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1 },
    WeaponSlot = { MainHand = 1, OffHand = 2 }, ItemEnchantType = { Imbue = 1, Temporary = 2 },
    -- the game's values: the weapon categories (blade, blunt, ranged) are built from them at load
    ItemWeaponSubclass = { Axe1H = 0, Axe2H = 1, Bow = 2, Gun = 3, Mace1H = 4, Mace2H = 5, Polearm = 6,
        Sword1H = 7, Sword2H = 8, Warglaive = 9, Staff = 10, Fist = 13, Dagger = 15, Crossbow = 18, Wand = 19 } }
-- Weapons: TEST.weapon[slot] = an item ID (a one-handed sword), TEST.enchants[weaponSlot] = the
-- game's enchant list for that weapon, TEST.bags[itemID] = how many the bags hold
function GetInventoryItemID(_, slot) return TEST.weapon[slot] end
C_Item = {
    GetItemInfoInstant = function(id)
        if id then return id, nil, nil, "INVTYPE_WEAPON", nil, 2, 7 end
    end,
    GetWeaponEnchantInfo = function(ws) return TEST.enchants[ws] or {} end,
    GetItemIconByID = function(id) return 500000 + id end,
}
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
function EABR.FvSyncWeaponEvents(want) TEST.weaponWanted[#TEST.weaponWanted + 1] = want end
-- The main file's catalogue, cut to the one category a priest's blade can take
EABR.FV_WEAPON_BUFFS = {
    { key = "sharpening", name = "Sharpening Stone", weapon = "BLADED", items = { 2862, 2863 } },
}

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
    CachedGetItemCount = function(id) return TEST.bags[id] or 0 end,
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
assert(TEST.weaponWanted[#TEST.weaponWanted] == false, "the weapon events were asked for with Weapon Buffs off")

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

-- 7. Weapon Buffs: a blade with no stone and stones in the bags shows the main hand's reminder,
--    whose click applies the highest owned stone to slot 16; nothing in combat, where its events
--    are released; Show Below shows it a minute before the stone runs out and otherwise arms the
--    one refresh at that moment; Hide When None in Bags hides a chosen stone the bags lack
local function WeaponEntry(missing)
    for _, e in ipairs(missing) do
        if e.dismissKey == "forever:weapon_mh_temp" then return e end
    end
end
fo.weapon, fo.weaponHideNoItem, fo.weaponShowBelow = true, true, 1
TEST.weapon[16] = 9001
TEST.bags[2862], TEST.bags[2863] = 2, 3
local missing
got, missing = Collect()
assert(got == "forever:1001,forever:g1,forever:weapon_mh_temp", "an unbuffed blade: " .. got)
local e = WeaponEntry(missing)
assert(e.mode == "macro" and e.macro == "/use item:2863\n/use 16" and e.bagCount == 3 and not e.desaturated,
    "the reminder does not apply the highest owned stone to the main hand")
assert(e.label == "Main Hand" and e.expireAt == nil, "an absent stone's label or countdown")
assert(TEST.weaponWanted[#TEST.weaponWanted] == true, "the weapon events were not asked for")
fo.weaponLowRank = true
got, missing = Collect()
assert(WeaponEntry(missing).macro == "/use item:2862\n/use 16", "Lowest Owned did not pick the lowest stone")
fo.weaponLowRank = false
TEST.combat = true
got = Collect()
assert(got == "", "in combat, Weapon Buffs showed: " .. got)
assert(TEST.weaponWanted[#TEST.weaponWanted] == false, "the weapon events stayed on in combat")
TEST.combat = false
-- 50 s of stone left: inside the minute, shown with its countdown
TEST.enchants[1] = { { hasEnchant = true, enchantType = 2, timeLeft = 50000 } }
got, missing = Collect()
e = WeaponEntry(missing)
assert(e and e.expireAt == 150 and e.expireTotal == 50, "a stone inside its Show Below minute")
-- 300 s left: hidden, one refresh armed for the minute mark (GetTime() = 100)
TEST.enchants[1] = { { hasEnchant = true, enchantType = 2, timeLeft = 300000 } }
EABR._nextDurationRefreshTime = nil
got = Collect()
assert(got == "forever:1001,forever:g1", "a stone with five minutes left showed: " .. got)
assert(EABR._nextDurationRefreshTime == 340, "the refresh at the minute mark: " .. tostring(EABR._nextDurationRefreshTime))
-- an imbue on the weapon does not count as its stone
TEST.enchants[1] = { { hasEnchant = true, enchantType = 1, timeLeft = 300000 } }
got = Collect()
assert(got == "forever:1001,forever:g1,forever:weapon_mh_temp", "an imbue hid the stone's reminder: " .. got)
TEST.enchants[1] = nil
-- a chosen stone the bags lack: hidden by default, greyed out when Hide When None in Bags is off
TEST.bags[2862], TEST.bags[2863] = nil, nil
fo.weaponHands = { PRIEST = { mhTemp = "sharpening" } }
got = Collect()
assert(got == "forever:1001,forever:g1", "a chosen stone the bags lack showed: " .. got)
fo.weaponHideNoItem = false
got, missing = Collect()
e = WeaponEntry(missing)
assert(e and e.mode == "texture" and e.desaturated and e.tooltipItem == 2863, "a chosen stone the bags lack, greyed")
-- Auto never offers a stone the bags lack; Off asks nothing
fo.weaponHands.PRIEST.mhTemp = nil
got = Collect()
assert(got == "forever:1001,forever:g1", "Auto offered a stone the bags lack: " .. got)
fo.weaponHands.PRIEST.mhTemp = "off"
TEST.bags[2863] = 1
got = Collect()
assert(got == "forever:1001,forever:g1", "a hand set to Off reminded: " .. got)
-- no weapon in the hand: nothing
fo.weaponHands.PRIEST.mhTemp = nil
TEST.weapon[16] = nil
got = Collect()
assert(got == "forever:1001,forever:g1", "an empty hand reminded: " .. got)
fo.weapon = false

print("aurabuff reminders forever combat harness: ok")
