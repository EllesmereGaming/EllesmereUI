-- Stub harness: WoW Forever AuraBuff Reminders Raid Buffs with Divine Spirit
-- (website bug #240). Loads the real aura helpers, spell tables, defaults and
-- collectors over stubbed internals and the real WoW Forever buff families, and
-- drives EABR.CollectForeverRaidBuffs for a priest with and without the Divine
-- Spirit talent, solo and in a party, out of combat and under lockdown, plus a
-- warrior's "I am missing others' buffs" view, the group watch and the label.
--   lua .tools/tests/test_abr_forever_raid_buffs_spirit.lua   (from the repository root)
-- ABR_ROOT (a global) or arg[1] points it at another tree.
local ROOT = rawget(_G, "ABR_ROOT") or (arg and arg[1]) or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local PRESETS_SRC = ReadSource("EllesmereUI_BuffPresets.lua")
local MAIN_SRC = ReadSource("EllesmereUIAuraBuffReminders/EllesmereUIAuraBuffReminders.lua")
local AURAS_SRC = ReadSource("EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Auras.lua")
local DATA_SRC = ReadSource("EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Data.lua")
local DEFAULTS_SRC = ReadSource("EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Defaults.lua")
local REFRESH_SRC = ReadSource("EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Refresh.lua")

local function Cut(src, from, to, label)
    local s = src:find(from, 1, true)
    local e = s and select(2, src:find(to, s, true))
    assert(s and e, label .. " not found")
    return src:sub(s, e)
end

-------------------------------------------------------------------------------
--  Game API stubs
-------------------------------------------------------------------------------
-- TEST.units[token] = { class, buffs = { [spell name] = aura instance ID } }
-- secretVals: values the game would hand back secret; secretSpell: spells whose aura is secret
local TEST = { units = {}, known = {}, lockdown = false, restricted = false, usable = {}, now = 100,
    secretVals = {}, secretSpell = {} }
local NAMES = {
    [1243] = "Power Word: Fortitude", [10938] = "Power Word: Fortitude", [21562] = "Prayer of Fortitude",
    [21564] = "Prayer of Fortitude",
    [14752] = "Divine Spirit", [14818] = "Divine Spirit", [14819] = "Divine Spirit", [27841] = "Divine Spirit",
    [27681] = "Prayer of Spirit",
    [1126] = "Mark of the Wild", [21849] = "Gift of the Wild", [1459] = "Arcane Intellect",
    [23028] = "Arcane Brilliance", [6673] = "Battle Shout",
}

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function tContains(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
function GetTime() return TEST.now end
function InCombatLockdown() return TEST.lockdown end
function IsInGroup() return TEST.units.party1 ~= nil end
function IsInRaid() return false end
function GetNumGroupMembers() local n = 0 for _ in pairs(TEST.units) do n = n + 1 end return n end
function GetNumSubgroupMembers() return GetNumGroupMembers() - 1 end
function UnitExists(u) return TEST.units[u] ~= nil end
function UnitIsConnected(u) return TEST.units[u] ~= nil end
function UnitIsDeadOrGhost() return false end
function UnitIsPlayer(u) return TEST.units[u] ~= nil end
function UnitIsUnit(a, b) return a == b end
function UnitInRange(u) return TEST.units[u] ~= nil, true end
function UnitIsVisible(u) return TEST.units[u] ~= nil end
function UnitClass(u) local t = TEST.units[u]; if t then return t.class, t.class end end
function CreateFrame()
    local f = { events = {} }
    function f:SetScript() end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:RegisterUnitEvent(e) self.events[e] = true end
    function f:UnregisterAllEvents() wipe(self.events) end
    return f
end
C_Secrets = { ShouldSpellAuraBeSecret = function(id) return TEST.secretSpell[id] == true end }
C_UnitAuras = {
    GetAuraDataBySpellName = function(u, name)
        local t = TEST.units[u]
        local iid = t and t.buffs[name]
        if iid then return { auraInstanceID = iid, name = name } end
    end,
    GetPlayerAuraBySpellID = function() return nil end,
    GetAuraDataByIndex = function() return nil end,
}
C_SpellBook = { IsSpellKnown = function(id) return TEST.known[id] == true end }
C_Spell = {
    GetSpellName = function(id) return NAMES[id] end,
    GetSpellInfo = function() return nil end,
    GetSpellTexture = function(id) return id end,
    -- the group versions: usable (reagent in the bags) only while TEST.usable says so
    IsSpellUsable = function(id) return TEST.usable[id] == true, false end,
}
Enum = { ItemWeaponSubclass = { Axe1H = 0, Axe2H = 1, Bow = 2, Gun = 3, Mace1H = 4, Mace2H = 5, Polearm = 6,
    Sword1H = 7, Sword2H = 8, Warglaive = 9, Staff = 10, Fist = 13, Dagger = 15, Crossbow = 18, Wand = 19 } }

-------------------------------------------------------------------------------
--  EllesmereUI: the real WoW Forever buff families, cut from the parent file
-------------------------------------------------------------------------------
EllesmereUI = {
    IS_FOREVER = true,
    RAID_PREP_IDS = { raidBuffs = {}, flask = {}, rune = {}, oldRune = {} },
    AuraKit = { AurasRestricted = function() return TEST.restricted end },
    L = function(s) return s end,
    UnitEffectiveRole = function() return nil end,
    RegisterBorderDefaults = function() end,
    Glows = { MakeView = function() return {} end, StopAllGlows = function() end },
}
assert(loadstring(Cut(PRESETS_SRC, "    EllesmereUI.FOREVER_BUFF_FAMILIES = {", "\n    }\n",
    "EllesmereUI.FOREVER_BUFF_FAMILIES"), "=FOREVER_BUFF_FAMILIES"))()
assert(EllesmereUI.FOREVER_BUFF_FAMILIES.spirit and EllesmereUI.FOREVER_BUFF_FAMILIES.fort, "families not cut")

-- The real label shortener, cut from the main file
local ShortLabel = assert(loadstring(Cut(MAIN_SRC, "local LABEL_OVERRIDES = {", "    return name:match(\"^(%S+)\") or name\nend\n",
    "ShortLabel") .. "\nreturn ShortLabel", "=ShortLabel"))()

-------------------------------------------------------------------------------
--  The internals the files read (the main file builds it in the game)
-------------------------------------------------------------------------------
local function Load(forever)
    local EABR = { FOREVER = forever }
    -- every content bucket shown (the section's Where to Show is not under test)
    function EABR.SectionShows() return true end
    local I = {
        EABR = EABR,
        AURA_SCAN_LIMIT = 40, ICON_SIZE = 32,
        NON_SECRET_SPELL_IDS = {},
        combatActiveIcons = {}, cursorActiveIcons = {},
        dbSetters = {}, panelOpenSetters = {}, iconAnchorSetters = {}, combatAnchorSetters = {},
        cursorAnchorSetters = {},
        InCombat = function() return TEST.lockdown end,
        InMythicPlusKey = function() return false end,
        isSecret = function(v) return TEST.secretVals[v] == true end,
        SpellName = function(id) return NAMES[id] end,
        Known = function(id) return C_SpellBook.IsSpellKnown(id) end,
        ShortLabel = ShortLabel,
        Tex = function(id) return id end,
        AcquireEntry = function() return {} end,
    }
    setmetatable(I, { __index = function(_, k)
        if k == "broken" then return nil end
        return function() end
    end })
    local ns = { _abrInternals = I }
    for _, part in ipairs({ { AURAS_SRC, "Auras" }, { DATA_SRC, "Data" }, { DEFAULTS_SRC, "Defaults" },
        { REFRESH_SRC, "Refresh" } }) do
        assert(loadstring(part[1], "=" .. part[2]))("EllesmereUIAuraBuffReminders", ns)
        assert(rawget(I, "broken") == false, part[2] .. " did not load")
    end
    return EABR, I
end

-------------------------------------------------------------------------------
--  Defaults: Divine Spirit on WoW Forever only
-------------------------------------------------------------------------------
do
    local _, I = Load(false)
    assert(I.defaults.profile.raidBuffs.enabled.spirit == nil, "retail defaults gained a Divine Spirit key")
end
local EABR, I = Load(true)
assert(I.defaults.profile.raidBuffs.enabled.spirit == true, "Divine Spirit is not on by default on WoW Forever")
assert(ShortLabel("Divine Spirit") == "Spirit", "label: " .. ShortLabel("Divine Spirit"))
assert(ShortLabel("Power Word: Fortitude") == "Fortitude", "the Fortitude label changed")

local SPIRIT
for _, b in ipairs(I.RAID_BUFFS) do if b.key == "spirit" then SPIRIT = b end end
assert(SPIRIT and SPIRIT.class == "PRIEST" and SPIRIT.fam == EllesmereUI.FOREVER_BUFF_FAMILIES.spirit,
    "no Divine Spirit raid buff on WoW Forever")

local db = { profile = { raidBuffs = {
    enabled = { motw = true, bshout = true, fort = true, ai = true, spirit = true },
    whereToShow = {}, showWhen = { othersMissing = true, iAmMissing = false },
} } }
for _, set in ipairs(I.dbSetters) do set(db) end
local rb = db.profile.raidBuffs

local function Collect(class)
    local missing = {}
    EABR.CollectForeverRaidBuffs(missing, class or "PRIEST", true)
    local keys = {}
    for _, e in ipairs(missing) do keys[#keys + 1] = e.dismissKey .. "=" .. e.mode end
    table.sort(keys)
    return table.concat(keys, ","), missing
end
local function Entry(missing, key)
    for _, e in ipairs(missing) do if e.dismissKey == key then return e end end
end

local iid = 0
local function Unit(class, ...)
    local t = { class = class, buffs = {} }
    for i = 1, select("#", ...) do iid = iid + 1; t.buffs[select(i, ...)] = iid end
    return t
end

-------------------------------------------------------------------------------
--  1. A priest without the talent: Fortitude alone, as before
-------------------------------------------------------------------------------
TEST.known = { [1243] = true, [10938] = true }
TEST.units = { player = Unit("PRIEST", "Power Word: Fortitude"), party1 = Unit("WARRIOR"), party2 = Unit("MAGE", "Power Word: Fortitude") }
local got, missing = Collect()
assert(got == "raidbuff:fort=spell", "priest without Divine Spirit: " .. got)
local e = Entry(missing, "raidbuff:fort")
assert(e.groupHave == 2 and e.groupTotal == 3, "Fortitude coverage")
assert(e.spellID == 10938 and EABR._fvCastSpell == 10938 and EABR._fvCastUnit == "party1",
    "Fortitude cast: " .. tostring(EABR._fvCastSpell) .. " on " .. tostring(EABR._fvCastUnit))
local W = EABR._fvWatch
assert(W and W.ids[1243] and not W.ids[14752], "the watch does not follow Fortitude alone")
-- everyone buffed: nothing shows, the button stays bound to Fortitude on the player
TEST.units.party1.buffs["Power Word: Fortitude"] = 99
got = Collect()
assert(got == "", "Fortitude up everywhere, still shown: " .. got)
assert(EABR._fvCastSpell == 10938 and EABR._fvCastUnit == "player", "idle binding moved off Fortitude")

-------------------------------------------------------------------------------
--  2. Solo with the talent: Divine Spirit missing on the player shows
-------------------------------------------------------------------------------
TEST.known[14752], TEST.known[27841] = true, true
TEST.units = { player = Unit("PRIEST", "Power Word: Fortitude") }
got, missing = Collect()
assert(got == "raidbuff:spirit=spell", "solo, Divine Spirit missing: " .. got)
assert(Entry(missing, "raidbuff:spirit").label == "Spirit", "Divine Spirit label")
assert(EABR._fvCastSpell == 27841 and EABR._fvCastUnit == "player", "solo Divine Spirit cast")
TEST.units.player.buffs["Divine Spirit"] = 98
got = Collect()
assert(got == "", "solo, Divine Spirit up: " .. got)
-- Prayer of Spirit on the player counts too
TEST.units.player.buffs["Divine Spirit"] = nil
TEST.units.player.buffs["Prayer of Spirit"] = 97
got = Collect()
assert(got == "", "Prayer of Spirit up, still shown: " .. got)
-- the switch turns it off
TEST.units.player.buffs["Prayer of Spirit"] = nil
rb.enabled.spirit = false
got = Collect()
assert(got == "", "Divine Spirit unticked, still shown: " .. got)
rb.enabled.spirit = true

-------------------------------------------------------------------------------
--  3. In a party: one provider reminder at a time, Fortitude first
-------------------------------------------------------------------------------
TEST.units = { player = Unit("PRIEST", "Power Word: Fortitude", "Divine Spirit"),
    party1 = Unit("WARRIOR"), party2 = Unit("MAGE", "Power Word: Fortitude") }
got, missing = Collect()
assert(got == "raidbuff:fort=spell", "both missing, not Fortitude alone: " .. got)
assert(EABR._fvCastSpell == 10938 and EABR._fvCastUnit == "party1", "both missing, the button left Fortitude")
assert(Entry(missing, "raidbuff:fort").spellID == EABR._fvCastSpell, "the reminder does not show the bound cast")
-- the watch follows both buffs, and the found auras of both are kept
W = EABR._fvWatch
assert(W.ids[1243] and W.ids[21564] and W.ids[14752] and W.ids[27681], "the watch misses a buff")
local found = EABR._fvInst.party2
assert(found[TEST.units.party2.buffs["Power Word: Fortitude"]], "the Fortitude aura found was dropped")
assert(EABR.FvAuraRelevant("party1", { addedAuras = { { spellId = 27841 } } }), "an added Divine Spirit was not heard")
assert(EABR.FvAuraRelevant("party1", { addedAuras = { { spellId = 10938 } } }), "an added Fortitude was not heard")
assert(not EABR.FvAuraRelevant("party1", { addedAuras = { { spellId = 1459 } } }), "an unrelated aura asked a refresh")
assert(EABR.FvAuraRelevant("party2", { removedAuraInstanceIDs = { TEST.units.party2.buffs["Power Word: Fortitude"] } }),
    "a Fortitude removal was not heard")
-- a payload the restriction made unreadable asks a refresh while either watched buff stays readable
local SECRET = {}
TEST.secretVals[SECRET] = true
TEST.secretSpell[1243], TEST.now = true, TEST.now + 1
assert(EABR.FvAuraRelevant("party1", SECRET), "Fortitude unreadable: a readable Divine Spirit was not heard")
TEST.secretSpell[1243], TEST.secretSpell[14752], TEST.now = nil, true, TEST.now + 1
assert(EABR.FvAuraRelevant("party1", SECRET), "Divine Spirit unreadable: a readable Fortitude was not heard")
TEST.secretSpell[1243], TEST.now = true, TEST.now + 1
assert(not EABR.FvAuraRelevant("party1", SECRET), "neither readable, still asked a refresh")
TEST.secretSpell[1243], TEST.secretSpell[14752], TEST.now = nil, nil, TEST.now + 1
-- Fortitude done: Divine Spirit takes the button
TEST.units.party1.buffs["Power Word: Fortitude"] = 96
got, missing = Collect()
assert(got == "raidbuff:spirit=spell", "Fortitude done, not Divine Spirit: " .. got)
e = Entry(missing, "raidbuff:spirit")
assert(e.groupHave == 1 and e.groupTotal == 3, "Divine Spirit coverage")
assert(EABR._fvCastSpell == 27841 and EABR._fvCastUnit == "party1" and e.spellID == 27841, "Divine Spirit cast")
-- Prayer of Spirit known with its reagent: the group version on the player
TEST.known[27681], TEST.usable[27681] = true, true
Collect()
assert(EABR._fvCastSpell == 27681 and EABR._fvCastUnit == "player", "Prayer of Spirit not picked")
TEST.known[27681], TEST.usable[27681] = nil, nil
-- a dismissed Fortitude lets Divine Spirit show
TEST.units.party1.buffs["Power Word: Fortitude"] = nil
I._dismissedUntilLoad["raidbuff:fort"] = true
got = Collect()
assert(got == "raidbuff:spirit=spell", "Fortitude dismissed: " .. got)
assert(EABR._fvCastSpell == 27841, "Fortitude dismissed, the button did not follow Divine Spirit")
I._dismissedUntilLoad["raidbuff:fort"] = nil

-------------------------------------------------------------------------------
--  4. Under lockdown only the buff the button casts shows
-------------------------------------------------------------------------------
Collect()                                   -- out of combat: Fortitude missing, bound
EABR._providerCastSpell = EABR._fvCastSpell -- what the render binds
assert(EABR._providerCastSpell == 10938, "pre-pull binding")
TEST.lockdown = true
got, missing = Collect()
assert(got == "raidbuff:fort=spell" and Entry(missing, "raidbuff:fort").spellID == 10938, "in combat, Fortitude: " .. got)
-- Fortitude back, Divine Spirit missing: the button still casts Fortitude, so nothing shows
TEST.units.party1.buffs["Power Word: Fortitude"] = 95
got = Collect()
assert(got == "", "in combat, Divine Spirit showed on a Fortitude button: " .. got)
assert(EABR._fvCastSpell == 10938, "the binding moved in combat")
TEST.lockdown = false
got = Collect()
assert(got == "raidbuff:spirit=spell", "after combat, Divine Spirit: " .. got)
-- bound to Divine Spirit before the pull: it shows in combat
EABR._providerCastSpell = EABR._fvCastSpell
TEST.lockdown = true
got, missing = Collect()
assert(got == "raidbuff:spirit=spell" and Entry(missing, "raidbuff:spirit").spellID == 27841, "in combat, Divine Spirit: " .. got)
-- bound to a group version before the pull: its buff still shows in combat
TEST.units.party1.buffs["Power Word: Fortitude"] = nil
EABR._providerCastSpell = 21564
got, missing = Collect()
assert(got == "raidbuff:fort=spell" and Entry(missing, "raidbuff:fort").spellID == 21564,
    "in combat on Prayer of Fortitude, Fortitude: " .. got)
TEST.units.party1.buffs["Power Word: Fortitude"] = 95
TEST.lockdown = false
EABR._providerCastSpell = nil
-- everyone has both: nothing shows, and the button goes back to the first buff, Fortitude
for _, u in pairs(TEST.units) do
    u.buffs["Power Word: Fortitude"], u.buffs["Divine Spirit"] = 90, 91
end
got = Collect()
assert(got == "", "both up everywhere, still shown: " .. got)
assert(EABR._fvCastSpell == 10938 and EABR._fvCastUnit == "player", "idle binding is not Fortitude on the player")

-------------------------------------------------------------------------------
--  5. A warrior's "I am missing others' buffs": Fortitude, never Divine Spirit
-------------------------------------------------------------------------------
rb.showWhen.iAmMissing = true
TEST.known = { [6673] = true }
TEST.units = { player = Unit("WARRIOR", "Battle Shout"), party1 = Unit("PRIEST", "Battle Shout") }
got = Collect("WARRIOR")
assert(got == "raidbuff:fort=texture", "receiver view: " .. got)
-- with only Divine Spirit ticked there is nothing to receive, so the roster goes unheard
rb.enabled = { spirit = true }
got = Collect("WARRIOR")
assert(got == "", "receiver view, Divine Spirit only: " .. got)
assert(not EABR._fvWatch.world.events.GROUP_ROSTER_UPDATE, "the roster is heard for a talent buff")

print("aurabuff reminders forever raid buffs divine spirit harness: ok")
