-- Stub harness: the WoW Forever section of AuraBuff Reminders shows nothing in
-- combat (its Where to Show offers no In Combat entry: always unchecked). Loads
-- the aura helpers and the collectors over a stubbed internals table and drives
-- EABR.CollectForever in and out of combat, and the pre-pull snapshot, which
-- Forever no longer takes. Scenario 7 drives the Weapon Buffs reminder,
-- scenario 8 a spell group's click and tooltip rank, scenario 9 a custom
-- spell's, scenario 10 the class buffs and Mage Armors.
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
local MAIN_SRC = ReadSource("EllesmereUIAuraBuffReminders/EllesmereUIAuraBuffReminders.lua"):gsub("\r\n", "\n")

-------------------------------------------------------------------------------
--  Game API stubs
-------------------------------------------------------------------------------
local TEST = { combat = false, up = {}, src = {}, auraReads = 0, trackingWanted = {}, weaponWanted = {},
    weapon = {}, enchants = {}, bags = {} }

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function GetTime() return 100 end

-- The player's auras: TEST.up[id] = true while that spell's aura is up
C_UnitAuras = {
    GetPlayerAuraBySpellID = function(id)
        TEST.auraReads = TEST.auraReads + 1
        if TEST.up[id] then
            -- its caster: TEST.src[id], else the player
            local src = TEST.src[id] or "player"
            return { spellId = id, duration = 0, expirationTime = 0, sourceUnit = src,
                isFromPlayerOrPlayerPet = src == "player" }
        end
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
function UnitIsUnit(a, b) return a == b end
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
-- By name the game answers the highest rank in the spellbook, as /cast resolves
-- it (a spellbook showing every rank lists them lowest first)
C_Spell = {
    GetSpellName = function(id) return NAMES[id] end,
    GetSpellInfo = function(q)
        if type(q) == "string" then
            local top
            for _, sid in ipairs(BOOK) do if NAMES[sid] == q then top = sid end end
            return top and { spellID = top, name = q } or nil
        end
        return NAMES[q] and { spellID = q, name = NAMES[q] } or nil
    end,
}

EllesmereUIDB = {}
EllesmereUI = {
    -- The shared Intellect family's class list, read at load (the parent's
    -- EllesmereUI_BuffPresets.lua builds the real table in the game).
    FOREVER_BUFF_FAMILIES = { ai = { names = {}, single = {}, group = {}, ids = {},
        beneficiaries = { MAGE = true, PRIEST = true } } },
    AuraKit = { AurasRestricted = function() return false end },
    L = function(s) return s end,
    CharKey = function(sep) return "Tester" .. sep .. "Realm" end,
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
-- the class buff table, cut from the main file and loaded over this EABR
do
    local s = MAIN_SRC:find("    function EABR.FvClassBuffs()", 1, true)
    local e = s and select(2, MAIN_SRC:find("        return t\n    end\n", s, true))
    assert(s and e, "EABR.FvClassBuffs not found in the main file")
    assert(loadstring("local EABR = ...\n" .. MAIN_SRC:sub(s, e), "=FvClassBuffs"))(EABR)
end

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

-- 8. a spell group's click casts its spell by name, and its tooltip is the rank that name
--    resolves to: the group's own ID leads its rank list, so the list's order says nothing; a
--    rank learned later is read again once the families are rebuilt
local function GroupEntry(list, key)
    for _, entry in ipairs(list) do
        if entry.dismissKey == key then return entry end
    end
end
NAMES[5001], NAMES[5002], NAMES[5003] = "Shadow Protection", "Shadow Protection", "Shadow Protection"
BOOK[#BOOK + 1] = 5001
BOOK[#BOOK + 1] = 5002
local groupsBefore = fo.customGroups
fo.customGroups = { groupsBefore[1], { name = "Shadow", ids = { 5003 } } }
EABR._fvFamDirty = true
got, missing = Collect()
assert(got == "forever:1001,forever:g1,forever:g2", "a second spell group: " .. got)
e = GroupEntry(missing, "forever:g2")
assert(e.mode == "macro" and e.macro == "/cast [@player] Shadow Protection",
    "a spell group's click does not cast its spell by name")
assert(e.spellID == 5002, "ranks 1-2 known, the tooltip is not rank 2: " .. tostring(e.spellID))
assert(e.label == "Shadow" and e.texture == 5003, "a spell group's label or icon")
-- rank 3 learned (LEARNED_SPELL_IN_SKILL_LINE marks the families): the group's own ID, now the
-- top rank, leads a list the lower ranks follow
BOOK[#BOOK + 1] = 5003
EABR._fvFamDirty = true
got, missing = Collect()
e = GroupEntry(missing, "forever:g2")
assert(e.spellID == 5003, "a group holding the top rank shows a lower rank's tooltip: " .. tostring(e.spellID))
fo.customGroups = groupsBefore
for _ = 1, 3 do BOOK[#BOOK] = nil end
EABR._fvFamDirty = true

-- 9. a custom spell the character knows casts on click by name, as a spell group does, its
--    tooltip the rank that name resolves to; one it does not know (a buff someone else casts)
--    is only shown, and so is one whose name the client has not loaded
NAMES[3001] = "Mark of the Wild"
fo.customIDs = { 1001, 3001, 4001 }
EABR._fvFamDirty = true
got, missing = Collect()
assert(got == "forever:1001,forever:3001,forever:4001,forever:g1", "three custom spells: " .. got)
e = GroupEntry(missing, "forever:1001")
assert(e.mode == "macro" and e.macro == "/cast [@player] Inner Fire" and e.spellID == 1001,
    "a known custom spell does not cast by name on click")
assert(e.label == "Inner Fire" and e.texture == 1001, "a known custom spell's label or icon")
e = GroupEntry(missing, "forever:3001")
assert(e.mode == "texture" and e.macro == nil and e.spellID == 3001,
    "a custom spell the character does not know got a click")
e = GroupEntry(missing, "forever:4001")
assert(e.mode == "texture" and e.macro == nil and e.label == "4001",
    "a custom spell with no name got a click")
-- rank 2 learned: the stored rank 1 now casts and shows rank 2
NAMES[1002] = "Inner Fire"
BOOK[#BOOK + 1] = 1002
EABR._fvFamDirty = true
got, missing = Collect()
e = GroupEntry(missing, "forever:1001")
assert(e.mode == "macro" and e.spellID == 1002,
    "a known custom spell's tooltip is not its top rank: " .. tostring(e.spellID))
BOOK[#BOOK] = nil
NAMES[1002], NAMES[3001] = nil, nil
fo.customIDs = { 1001 }
EABR._fvFamDirty = true

-- 10. the class buffs: ticked by default the always-on buffs (not Thorns, Righteous Fury or Shadowform); the
--     strongest line known first;
--     another caster's blessing holds the reminder back unrecorded, the player's own is recorded and the next
--     reminder casts its rank; a Greater Blessing counts as its line and is never cast; paladin auras count only
--     when the player's own; an unticked buff; a class with none; the spells the ticked buffs cover (rebuilt as the
--     ticked set changes); through the section only out of combat and outside PvP, where the user's own custom
--     spell and a group made only of covered spells stand down, never deleted. Then Mage Armors, same helper.
local function ClassEntries(class, cfo)
    local entries = {}
    EABR.CollectClassBuffs(entries, cfo, false, {}, class)
    return entries
end
local function Recorded(key)
    local s = EllesmereUIDB.classBuffByChar
    return s and s["Tester-Realm"] and s["Tester-Realm"][key]
end
local bookBefore = #BOOK
for _, id in ipairs({ 19740, 19834, 19742, 19850, 465, 10290 }) do BOOK[#BOOK + 1] = id end
NAMES[19740], NAMES[19834], NAMES[25780] = "Blessing of Might", "Blessing of Might", "Righteous Fury"
local pfo = { classBuffPicks = {} }
local cb = ClassEntries("PALADIN", pfo)
e = GroupEntry(cb, "forever:class_blessing")
assert(e and e.mode == "spell" and e.spellID == 19834, "the strongest blessing: " .. tostring(e and e.spellID))
e = GroupEntry(cb, "forever:class_paladinaura")
assert(e and e.spellID == 10290, "the strongest aura: " .. tostring(e and e.spellID))
assert(not GroupEntry(cb, "forever:class_rfury"), "Righteous Fury showed while off by default")
TEST.up[19835], TEST.src[19835] = true, "party1"
assert(not GroupEntry(ClassEntries("PALADIN", pfo), "forever:class_blessing"),
    "another caster's blessing did not hold the reminder back")
assert(not Recorded("blessing"), "another caster's blessing was recorded")
TEST.up[19835], TEST.src[19835] = nil, nil
TEST.up[19850] = true
assert(not GroupEntry(ClassEntries("PALADIN", pfo), "forever:class_blessing"), "the player's own Wisdom still reminded")
assert(Recorded("blessing") == 1, "the player's own Wisdom was not recorded")
TEST.up[19850] = nil
e = GroupEntry(ClassEntries("PALADIN", pfo), "forever:class_blessing")
assert(e and e.spellID == 19850, "the recorded blessing's rank: " .. tostring(e and e.spellID))
TEST.up[25898] = true
assert(not GroupEntry(ClassEntries("PALADIN", pfo), "forever:class_blessing"), "a Greater Blessing did not count")
assert(Recorded("blessing") == 2, "the Greater Blessing's line was not recorded")
TEST.up[25898] = nil
TEST.up[465], TEST.src[465] = true, "party2"
assert(GroupEntry(ClassEntries("PALADIN", pfo), "forever:class_paladinaura"), "another caster's aura cleared the reminder")
TEST.src[465] = nil
assert(not GroupEntry(ClassEntries("PALADIN", pfo), "forever:class_paladinaura"),
    "the player's own aura did not clear the reminder")
TEST.up[465] = nil
pfo.classBuffPicks.paladinaura = false
assert(not GroupEntry(ClassEntries("PALADIN", pfo), "forever:class_paladinaura"), "an unticked buff still reminded")
assert(#ClassEntries("WARRIOR", pfo) == 0, "a warrior got class buff reminders")
-- the covered spells: by ID and by name for the ticked buffs only, rebuilt when the ticked set changes
local cIDs, cNames = EABR.FvClassTracked({ classBuffPicks = {} }, "PALADIN")
assert(cIDs and cIDs[19740] and cIDs[25898] and cNames["Blessing of Might"] and not cIDs[25780],
    "the default paladin buffs' spells are not the covered set")
cIDs = EABR.FvClassTracked({ classBuffPicks = { blessing = false, paladinaura = false, rfury = true } }, "PALADIN")
assert(cIDs and cIDs[25780] and not cIDs[19740], "the covered set did not follow the ticked buffs")
assert(EABR.FvClassTracked({ classBuffPicks = { blessing = false, paladinaura = false } }, "PALADIN") == nil,
    "a covered set with nothing ticked")
assert(EABR.FvClassTracked({}, "WARRIOR") == nil, "a class without class buffs covers spells")
-- the defaults of the other classes: the always-on buffs ticked, Shadowform and Thorns not
for _, id in ipairs({ 588, 15473, 467 }) do BOOK[#BOOK + 1] = id end
cb = ClassEntries("PRIEST", { classBuffPicks = {} })
assert(GroupEntry(cb, "forever:class_innerfire") and not GroupEntry(cb, "forever:class_shadowform"),
    "a priest's defaults: Inner Fire ticked, Shadowform not")
assert(#ClassEntries("DRUID", { classBuffPicks = {} }) == 0, "Thorns started ticked")
-- through the section (this harness's player is a priest): Inner Fire, ticked by default, shows and the
-- user's own reminders for it stand down (the custom spell, by name, and a group made only of it), while a
-- group of other spells and one with a spell the class buffs do not cover stay
NAMES[588] = "Inner Fire"
EABR._fvFamDirty = true
fo.customGroups[#fo.customGroups + 1] = { name = "Fire", ids = { 1001 } }
fo.customGroups[#fo.customGroups + 1] = { name = "Mixed", ids = { 1001, 2001 } }
local function HasLabel(list, label)
    for _, x in ipairs(list) do if x.label == label then return true end end
end
got, cb = Collect()
assert(got:find("forever:class_innerfire", 1, true), "Inner Fire did not show through the section: " .. got)
assert(not got:find("forever:1001", 1, true), "the custom Inner Fire showed beside the class buff: " .. got)
assert(not HasLabel(cb, "Fire"), "a group made only of Inner Fire showed beside the class buff")
assert(got:find("forever:g1", 1, true), "a group of other spells stood down: " .. got)
assert(HasLabel(cb, "Mixed"), "a group with a spell the class buffs do not cover stood down")
TEST.combat = true
got = Collect()
assert(got == "", "class buffs showed in combat: " .. got)
TEST.combat = false
-- PvP: Class Buffs does not run there, so the user's own reminders show
cb = {}
EABR.CollectForever(cb, false, true)
assert(not GroupEntry(cb, "forever:class_innerfire"), "class buffs showed in PvP")
assert(GroupEntry(cb, "forever:1001") and HasLabel(cb, "Fire"), "the user's own reminders stood down in PvP")
-- unticked: they are back, nothing was deleted
fo.classBuffPicks = { innerfire = false }
got, cb = Collect()
assert(got:find("forever:1001", 1, true) and HasLabel(cb, "Fire") and fo.customIDs[1] == 1001,
    "the user's own reminders did not come back once unticked: " .. got)
fo.classBuffPicks = nil
fo.customGroups[#fo.customGroups] = nil
fo.customGroups[#fo.customGroups] = nil
NAMES[588], NAMES[19740], NAMES[19834], NAMES[25780] = nil, nil, nil, nil
-- Mage Armors: nothing up casts the strongest line's best rank, a line up is recorded and leads the next reminder
EABR.MAGE_ARMORS = { { 168, 7300 }, { 7302 }, { 6117, 22782 } }
for _, id in ipairs({ 168, 7300, 7302, 6117 }) do BOOK[#BOOK + 1] = id end
cb = {}
EABR.CollectMageArmor(cb, false, {})
assert(#cb == 1 and cb[1].spellID == 6117 and cb[1].dismissKey == "forever:magearmor",
    "Mage Armors with nothing up: " .. tostring(cb[1] and cb[1].spellID))
TEST.up[7302] = true
cb = {}
EABR.CollectMageArmor(cb, false, {})
assert(#cb == 0 and EllesmereUIDB.mageArmorByChar["Tester-Realm"] == 2, "Ice Armor up was not recorded")
TEST.up[7302] = nil
cb = {}
EABR.CollectMageArmor(cb, false, {})
assert(#cb == 1 and cb[1].spellID == 7302, "the recorded armor's rank: " .. tostring(cb[1] and cb[1].spellID))
for _ = #BOOK, bookBefore + 1, -1 do BOOK[#BOOK] = nil end
EABR._fvFamDirty = true

-- 11. a custom spell reminds only the classes ticked on its slot, every class while none is unticked (Inner Fire's
--     class buff unticked here, so its stand-down stays out of it); the options list names the paladin's
--     Blessing and Aura Blessings and Important Auras, their reminders keep Blessing and Aura
fo.classBuffPicks = { innerfire = false }
got = Collect()
assert(got:find("forever:1001", 1, true), "the custom spell did not show with every class ticked: " .. got)
fo.customClasses = { [1001] = { PRIEST = false } }
got = Collect()
assert(not got:find("forever:1001", 1, true), "the custom spell showed on a class unticked on it: " .. got)
assert(got:find("forever:g1", 1, true), "a class unticked on a custom spell hid a spell group: " .. got)
fo.customClasses = { [1001] = { MAGE = false } }
got = Collect()
assert(got:find("forever:1001", 1, true), "the custom spell stood down on a class still ticked on it: " .. got)
fo.customClasses, fo.classBuffPicks = nil, nil
local pal = EABR.FvClassBuffs().PALADIN
assert(pal[1].menu == "Blessings" and pal[1].label == "Blessing", "the blessing's list and reminder names")
assert(pal[2].menu == "Important Auras" and pal[2].label == "Aura", "the aura's list and reminder names")

print("aurabuff reminders forever combat harness: ok")
