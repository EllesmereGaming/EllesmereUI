-- Run from the repository root: lua .tools/tests/test_cdm_forever_default_hidden.lua
-- WoW Forever's Cooldown Manager catalogue hides some cooldowns by default
-- (Not Displayed until the player shows them). A layout that places one keeps
-- it through the keep/drop pass, known or not, under any rank; a cooldown the
-- player moved to Not Displayed still leaves, also when it shares a name with
-- a default-hidden one. An unreadable catalogue keeps everything; without
-- Blizzard's defaults table the pass drops as before, and an entry the table
-- lacks drops as before while the others keep their slots. Retail is unchanged.
EUI_CLIENT_BLOCKED = false

local NAMES = {
    [6552] = "Pummel", [6554] = "Pummel",
    [6572] = "Revenge", [6574] = "Revenge", [9998] = "Revenge",
    [100] = "Charge", [6343] = "Thunder Clap", [12294] = "Mortal Strike",
    [871] = "Shield Wall", [872] = "Shield Wall",
    [2687] = "Bloodrage", [2688] = "Bloodrage", [9999] = "Bloodrage",
}
local KNOWN = { [6552] = true, [6554] = true, [100] = true, [6343] = true, [12294] = true, [871] = true }
C_Spell = {
    GetSpellName = function(id) return NAMES[id] end,
    GetBaseSpell = function(id) return id end,
    GetOverrideSpell = function(id) return id end,
    GetSpellTexture = function() return 136197 end,
}
C_SpellBook = { FindSpellOverrideByID = function(id) return id end }
IsPlayerSpell = function(id) return KNOWN[id] == true end
issecretvalue = function() return false end
InCombatLockdown = function() return false end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
Enum = { CooldownViewerCategory = { Essential = 0, Utility = 1, HiddenActive = -1, HiddenPassive = -2 } }

-- Blizzard's Cooldown Manager: Charge (201) and Mortal Strike (205) shown;
-- Pummel (202) and Revenge (203) hidden by default; Thunder Clap (204) moved
-- to Not Displayed by the player; Shield Wall moved there by the player (206)
-- beside a default-hidden entry of the same name (207); Bloodrage shown (208)
-- beside a default-hidden entry of the same name (209).
local HIDDEN = -1
local RAW = {
    [201] = { spellID = 100, linkedSpellIDs = {} },
    [202] = { spellID = 6552, linkedSpellIDs = { 6552, 6554 } },
    [203] = { spellID = 6572, linkedSpellIDs = { 6572, 6574 } },
    [204] = { spellID = 6343, linkedSpellIDs = {} },
    [205] = { spellID = 12294, linkedSpellIDs = {} },
    [206] = { spellID = 871, linkedSpellIDs = {} },
    [207] = { spellID = 872, linkedSpellIDs = {} },
    [208] = { spellID = 2687, linkedSpellIDs = {} },
    [209] = { spellID = 2688, linkedSpellIDs = {} },
}
local CURRENT = { [201] = 0, [202] = HIDDEN, [203] = HIDDEN, [204] = HIDDEN, [205] = 0,
    [206] = HIDDEN, [207] = HIDDEN, [208] = 0, [209] = HIDDEN }
local DEFAULT = { [201] = 0, [202] = HIDDEN, [203] = HIDDEN, [204] = 0, [205] = 0,
    [206] = 1, [207] = HIDDEN, [208] = 0, [209] = HIDDEN }
local ORDERED = { 201, 202, 203, 204, 205, 206, 207, 208, 209 }
local DIRTY, NO_DEFAULTS, SKIP_DEFAULT = false, false, nil
C_CooldownViewer = {
    GetCooldownViewerCooldownInfo = function(cd) return RAW[cd] end,
    GetCooldownViewerCategorySet = function() return {} end,
}
CooldownViewerSettings = { GetDataProvider = function()
    return {
        IsDirty = function() return DIRTY end,
        GetDisplayData = function()
            local byID, defaults = {}, {}
            for _, cd in ipairs(ORDERED) do
                local r = RAW[cd]
                byID[cd] = { cooldownID = cd, spellID = r.spellID, linkedSpellIDs = r.linkedSpellIDs,
                    category = CURRENT[cd] }
                if cd ~= SKIP_DEFAULT then defaults[cd] = { category = DEFAULT[cd] } end
            end
            return { orderedCooldownIDs = ORDERED, cooldownInfoByID = byID,
                cooldownDefaultsByID = not NO_DEFAULTS and defaults or nil }
        end,
    }
end }
-- The live viewer holds frames for the shown cooldowns only.
local FRAMES = {}
EssentialCooldownViewer = { itemFramePool = { EnumerateActive = function()
    local i = 0
    return function() i = i + 1; return FRAMES[i] end
end } }
local function Frame(cd, live)
    return { cooldownID = cd, layoutIndex = cd, IsShown = function() return true end,
        GetSpellID = function() return live end }
end
local SHOWN = { Frame(201, 100), Frame(205, 12294), Frame(208, 2687) }
FRAMES = SHOWN

local function Load(forever)
    EllesmereUI = { IS_FOREVER = forever, _ModuleNS = {},
        _Pool = { CreateFrame = function() end, Kept = function() end, Gen = function() end } }
    local bars = {
        { key = "cooldowns", barType = "cooldowns" },
        { key = "utility", barType = "utility" },
        { key = "__ghost_cd", barType = "cooldowns", isGhostBar = true },
    }
    local store, byKey = {}, {}
    for _, b in ipairs(bars) do
        byKey[b.key] = b
        store[b.key] = { assignedSpells = {} }
    end
    local prof = { _barFilterModelV6 = true, barSpells = store }
    local ns = {
        ECME = { db = { profile = { cdmBars = { bars = bars } } } },
        barDataByKey = byKey, cdmBarFrames = {}, cdmBarIcons = {},
        GHOST_CD_BAR_KEY = "__ghost_cd",
        _ecmeFC = {}, _hookFrameData = {}, _cdmDataLoaded = true,
    }
    function ns.GetBarSpellData(k) return store[k] end
    function ns.GetActiveSpecProfiles() return { ["1"] = prof } end
    function ns.GetActiveSpecKey() return "1" end
    function ns.CollectCdClaimSet() return nil end
    ns._internals = {
        broken = false, ALL_RACIAL_SPELLS = {}, ECME = ns.ECME, _myRacialsSet = {},
        GHOST_CD_BAR_KEY = "__ghost_cd",
        MAIN_BAR_KEYS = { cooldowns = true, utility = true, buffs = true, __ghost_cd = true },
        barDataByKey = byKey,
    }
    EllesmereUI._ModuleNS.EllesmereUICooldownManager = ns
    assert(loadfile("EllesmereUICooldownManager/EllesmereUICdmSpellPicker.lua"))("EllesmereUICooldownManager", ns)
    assert(loadfile("EllesmereUICooldownManager/EUI_CDM_Reconcile.lua"))("EllesmereUICooldownManager", ns)
    assert(ns._internals.broken == false, "EUI_CDM_Reconcile.lua did not load")
    return ns, store
end

local function Same(list, want)
    if #list ~= #want then return false end
    for i = 1, #want do if list[i] ~= want[i] then return false end end
    return true
end
local function Show(list) return "{" .. table.concat(list, ", ") .. "}" end
local function Reconcile(ns, store, list)
    store.cooldowns.assignedSpells = list
    ns.ReconcileAssignedSpellDrops("cooldowns")
    return store.cooldowns.assignedSpells
end

-------------------------------------------------------------------------------
-- WoW Forever
-------------------------------------------------------------------------------
local ns, store = Load(true)

-- The set: default-hidden entries by id and rank name; a key another cooldown
-- entry shares is not default-hidden; an unlisted id goes by its name.
local set = ns.CDMDefaultHiddenSet()
local IsDH = ns.CDMIsDefaultHidden
assert(IsDH(set, 6552) and IsDH(set, 6554) and IsDH(set, 6574), "default-hidden entries, every rank")
assert(IsDH(set, 9998), "an id no entry lists goes by its name")
assert(not IsDH(set, 6343), "a cooldown the player hid is not")
assert(not IsDH(set, 100) and not IsDH(set, 12294), "shown cooldowns are not")
assert(not IsDH(set, 871) and IsDH(set, 872), "a player-hidden entry is told apart by id from a same-name default-hidden one")
assert(not IsDH(set, 9999), "a name a shown entry shares is not default-hidden")

-- Pummel (known, listed under rank 1) and Revenge (not learned yet) keep their
-- slots; Thunder Clap and Shield Wall, which the player moved to Not
-- Displayed, still go.
local list = Reconcile(ns, store, { 100, 6552, 6343, 6574, 871, 12294 })
assert(Same(list, { 100, 6552, 6574, 12294 }), "default-hidden cooldowns keep their slots: " .. Show(list))

-- While the catalogue is not readable, nothing goes.
DIRTY = true
list = Reconcile(ns, store, { 100, 6552, 6343, 12294 })
assert(Same(list, { 100, 6552, 6343, 12294 }), "an unreadable catalogue keeps everything: " .. Show(list))
DIRTY = false

-- Without Blizzard's defaults table no entry reads as default-hidden: the pass
-- drops as it did before.
NO_DEFAULTS = true
list = Reconcile(ns, store, { 100, 6552, 6343, 12294 })
assert(Same(list, { 100, 12294 }), "no defaults table drops as before: " .. Show(list))
NO_DEFAULTS = false

-- An entry the defaults table lacks is left out of the set: Pummel then drops
-- as before, Revenge keeps its slot.
SKIP_DEFAULT = 202
local okS, partial = pcall(ns.CDMDefaultHiddenSet)
assert(okS, "an entry without a default does not stop the set: " .. tostring(partial))
assert(not IsDH(partial, 6552) and IsDH(partial, 6574), "only the entry without a default is left out")
list = Reconcile(ns, store, { 100, 6552, 6574, 12294 })
assert(Same(list, { 100, 6574, 12294 }), "an entry without a default drops as before: " .. Show(list))
SKIP_DEFAULT = nil

-- Once the player shows Pummel in Blizzard's Cooldown Manager it is a shown
-- cooldown like any other.
CURRENT[202] = 0
FRAMES = { Frame(201, 100), Frame(202, 6554), Frame(205, 12294), Frame(208, 2687) }
assert(not IsDH(ns.CDMDefaultHiddenSet(), 6552), "a default-hidden cooldown the player showed leaves the set")
CURRENT[202] = HIDDEN
FRAMES = SHOWN

-------------------------------------------------------------------------------
-- Retail: unchanged
-------------------------------------------------------------------------------
ns, store = Load(false)
assert(ns.CDMDefaultHiddenSet() == nil, "no default-hidden set off Forever")
list = Reconcile(ns, store, { 100, 6552, 6343, 12294 })
assert(Same(list, { 100, 12294 }), "retail drops an owned cooldown not displayed: " .. Show(list))

print("test_cdm_forever_default_hidden: all checks passed")
