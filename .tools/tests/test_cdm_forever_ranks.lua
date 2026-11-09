-- Run from the repository root: lua .tools/tests/test_cdm_forever_ranks.lua
-- WoW Forever Cooldown Manager spell ranks: each rank of a spell is a spell ID
-- of its own and the ranks share the spell's name, while Blizzard's Cooldown
-- Manager shows a spell's ranks as one entry. A bar lists the spell once,
-- under any of its ranks: list presence, the options normalize pass and its
-- live-icon pass, the runtime reseed, the keep/drop pass, the picker's
-- on-bar mark and import ghosting. Retail keeps matching by exact ID and
-- variant only.
EUI_CLIENT_BLOCKED = false

local NAMES = {
    [348] = "Immolate", [707] = "Immolate", [1094] = "Immolate", [2941] = "Immolate",
    [5676] = "Searing Pain", [17919] = "Searing Pain", [17920] = "Searing Pain",
    [689] = "Drain Life", [99999] = "Immolate",
}
local KNOWN = {
    [348] = true, [707] = true, [1094] = true, [2941] = true,
    [5676] = true, [17919] = true, [17920] = true, [689] = true,
}
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

-- Blizzard's Cooldown Manager: Immolate (cooldownID 101: its catalogue lists the
-- top rank only), Searing Pain (103: its ranks linked) and Drain Life (102). A
-- frame's GetSpellID reads the highest rank known; the runtime's own read of a
-- frame (fc.spellID) can be another rank.
local INFO = {
    [101] = { spellID = 2941, linkedSpellIDs = {} },
    [102] = { spellID = 689, linkedSpellIDs = {} },
    [103] = { spellID = 5676, linkedSpellIDs = { 5676, 17919, 17920 } },
}
C_CooldownViewer = {
    GetCooldownViewerCooldownInfo = function(cd) return INFO[cd] end,
    GetCooldownViewerCategorySet = function() return {} end,
}
local FRAMES = {}
EssentialCooldownViewer = { itemFramePool = { EnumerateActive = function()
    local i = 0
    return function() i = i + 1; return FRAMES[i] end
end } }
local ORDERED = { 101, 103, 102 }
CooldownViewerSettings = { GetDataProvider = function()
    return {
        IsDirty = function() return false end,
        GetDisplayData = function()
            local byID = {}
            for _, cd in ipairs(ORDERED) do byID[cd] = { category = 0 } end
            return { orderedCooldownIDs = ORDERED, cooldownInfoByID = byID }
        end,
    }
end }
local function Frame(cd, live)
    return {
        cooldownID = cd, layoutIndex = cd,
        IsShown = function() return true end,
        GetSpellID = function() return live end,
    }
end

local function Load(forever)
    EllesmereUI = {
        IS_FOREVER = forever, _ModuleNS = {},
        _Pool = { CreateFrame = function() end, Kept = function() end, Gen = function() end },
    }
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
    function ns.TalentCondHiddenSet() return {} end
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
    assert(loadfile("EllesmereUIOptions/CooldownManager_Options/Pickers_Options.lua"))("EllesmereUIOptions", {})
    assert(ns.CDMO_EnsureAssignedSpells, "Pickers_Options.lua did not load")
    ns._CDMO_OptEnv = { NormalizeToBase = ns.NormalizeToBase, ResolveToLive = ns.ResolveToLive }
    return ns, store
end

local function Same(list, want)
    if #list ~= #want then return false end
    for i = 1, #want do if list[i] ~= want[i] then return false end end
    return true
end
local function Show(list) return "{" .. table.concat(list, ", ") .. "}" end

-------------------------------------------------------------------------------
-- WoW Forever
-------------------------------------------------------------------------------
local ns, store = Load(true)
local Find = ns.FindVariantIndexInList
assert(ns.CDMRankName, "the rank names exist on Forever")

-- 1. List presence matches another rank of the spell; the exact ID wins first.
assert(Find({ 689, 348 }, 2941) == 2, "another rank of a listed spell is found")
assert(Find({ 707, 2941 }, 2941) == 2, "the exact ID wins over another rank listed before it")
assert(Find({ -13, 689 }, 2941) == nil, "a spell not listed, slot markers aside, is not found")
assert(Find({ 348 }, 5676) == nil, "another spell is not a rank")

-- 2. Add, remove and the ghost list follow the spell, whatever the rank.
local cds, ghost = store.cooldowns.assignedSpells, store.__ghost_cd.assignedSpells
cds[1] = 348
ghost[1] = 5676
assert(ns.AddSpellToBar("cooldowns", 2941) == false and Same(cds, { 348 }),
    "adding a listed spell under its top rank adds nothing")
assert(ns.AddSpellToBar("cooldowns", 17920) == true and Same(cds, { 348, 17920 }),
    "a new spell is added")
assert(#ghost == 0, "adding a spell takes it off the hidden list, whatever rank was hidden")
assert(ns.RemoveSpellFromBar("cooldowns", 707) == 348 and Same(cds, { 17920 }),
    "removing a spell removes the rank listed")

-- 3. The picker marks a spell on the bar whatever rank is listed.
FRAMES = { Frame(101, 2941), Frame(103, 17920), Frame(102, 689) }
store.cooldowns.assignedSpells = { 348, 689 }
local onBar = {}
for _, sp in ipairs(ns.GetCDMSpellsForBar("cooldowns")) do onBar[sp.spellID] = sp.onEUIBar end
assert(onBar[2941] == true, "Immolate listed under rank 1 reads as on the bar")
assert(onBar[689] == true and onBar[17920] == false, "the other marks are unchanged")

-- 4. The options pass collapses ranks listed twice, the first staying in place,
--    and its live-icon pass adds no other rank of a listed spell.
ns.cdmBarIcons.cooldowns = { FRAMES[1], FRAMES[2], FRAMES[3] }
store.cooldowns.assignedSpells = { 2941, 348, 17920, 5676, 689 }
ns._spellOrderDirty = nil
local sd = ns.CDMO_EnsureAssignedSpells("cooldowns")
assert(Same(sd.assignedSpells, { 2941, 17920, 689 }),
    "duplicate ranks collapse to the first listed: " .. Show(sd.assignedSpells))
assert(ns._spellOrderDirty == true, "a collapse marks the render order for rebuild")

store.cooldowns.assignedSpells = { 348, 5676, 689 }
sd = ns.CDMO_EnsureAssignedSpells("cooldowns")
assert(Same(sd.assignedSpells, { 348, 5676, 689 }),
    "live top ranks of listed spells are not added, and the listed ranks are kept: "
    .. Show(sd.assignedSpells))

-- A custom spell ID is the user's own and never collapses with a rank.
store.cooldowns.assignedSpells = { 348, 99999, 5676, 689 }
store.cooldowns.customSpellIDs = { [99999] = true }
sd = ns.CDMO_EnsureAssignedSpells("cooldowns")
assert(Same(sd.assignedSpells, { 348, 99999, 5676, 689 }),
    "a custom spell ID sharing a name stays: " .. Show(sd.assignedSpells))
store.cooldowns.customSpellIDs = nil

-- 5. The runtime reseed adds no other rank of a listed spell (its own read of a
--    frame can be another rank than the options pass stored).
store.cooldowns.assignedSpells = { 2941, 17920, 689 }
ns._ecmeFC[FRAMES[1]] = { spellID = 348 }
ns._ecmeFC[FRAMES[2]] = { spellID = 5676 }
ns._ecmeFC[FRAMES[3]] = { spellID = 689 }
ns.ReseedAssignedSpellsFromLiveIcons(true)
assert(Same(store.cooldowns.assignedSpells, { 2941, 17920, 689 }),
    "the reseed adds no rank twice: " .. Show(store.cooldowns.assignedSpells))

-- 6. The keep/drop pass keeps a spell listed under a rank no frame and no
--    catalogue entry names while the spell is shown, and still drops a spell
--    the player took out of Blizzard's tracking.
store.cooldowns.assignedSpells = { 707, 689 }
ns.ReconcileAssignedSpellDrops("cooldowns")
assert(Same(store.cooldowns.assignedSpells, { 707, 689 }),
    "an older rank of a shown spell is kept: " .. Show(store.cooldowns.assignedSpells))
FRAMES = { Frame(102, 689) }
ORDERED = { 102 }
ns.ReconcileAssignedSpellDrops("cooldowns")
assert(Same(store.cooldowns.assignedSpells, { 689 }),
    "a spell no longer tracked still goes: " .. Show(store.cooldowns.assignedSpells))

-- 7. Import ghosting hides a tracked spell the layout places nowhere, once,
--    but not one the layout lists under another rank than the frame shows.
--    A custom spell ID never stands in for a rank.
local function ImportGhost(nsI, storeI, listed, custom)
    for _, b in ipairs(nsI.ECME.db.profile.cdmBars.bars) do b.enabled = true end
    local prof = nsI.GetActiveSpecProfiles()["1"]
    prof._barFilterModelV6, prof._importGhostMode = nil, true
    storeI.cooldowns.assignedSpells, storeI.cooldowns.customSpellIDs = listed, custom
    storeI.utility.assignedSpells = {}
    storeI.__ghost_cd.assignedSpells = {}
    nsI.MigrateSpecToBarFilterModelV6()
    return storeI.__ghost_cd.assignedSpells
end
FRAMES = { Frame(101, 2941), Frame(102, 689) }
ghost = ImportGhost(ns, store, { 348 })
assert(Same(ghost, { 689 }), "only the unplaced spell is hidden: " .. Show(ghost))
FRAMES = { Frame(101, 2941) }
ghost = ImportGhost(ns, store, { 99999 }, { [99999] = true })
assert(Same(ghost, { 2941 }), "a custom spell ID sharing the name places nothing: " .. Show(ghost))
-- The frame shows the top rank known, the catalogue names rank 1.
FRAMES = { Frame(103, 17920) }
local categorySet = C_CooldownViewer.GetCooldownViewerCategorySet
C_CooldownViewer.GetCooldownViewerCategorySet = function() return { 103 } end
ghost = ImportGhost(ns, store, {})
C_CooldownViewer.GetCooldownViewerCategorySet = categorySet
assert(#ghost == 1 and NAMES[ghost[1]] == "Searing Pain", "a spell is hidden once: " .. Show(ghost))

-- 8. Routing: a row whose cooldown info does not link the listed rank finds
--    the bar listing the spell, or the hidden list, by name; a custom spell ID
--    keeps exact matching.
NAMES[740], NAMES[9862], NAMES[9863] = "Tranquility", "Tranquility", "Tranquility"
INFO[105] = { spellID = 740, overrideSpellID = 9863, linkedSpellIDs = {} }
local bar4 = { key = "bar4", barType = "cooldowns", enabled = true }
table.insert(ns.ECME.db.profile.cdmBars.bars, bar4)
ns.barDataByKey.bar4 = bar4
store.bar4 = { assignedSpells = {} }
ns._hookInternals = { broken = false }
assert(loadfile("EllesmereUICooldownManager/EUI_CDM_HookResolve.lua"))("EllesmereUICooldownManager", ns)
assert(ns._hookInternals.broken == false, "EUI_CDM_HookResolve.lua did not load")
local function Route(bar4List, ghostList, custom)
    store.cooldowns.assignedSpells, store.cooldowns.customSpellIDs = {}, nil
    store.bar4.assignedSpells, store.bar4.customSpellIDs = bar4List, custom
    store.__ghost_cd.assignedSpells = ghostList
    ns.RebuildSpellRouteMap()
    return ns.ResolveCDIDToBar(105, "cooldowns")
end
assert(Route({ 9862 }, {}) == "bar4", "a placed spell shows on its bar at the rank known")
assert(Route({}, { 9862 }) == "__ghost_cd", "a hidden spell stays hidden at the rank known")
assert(Route({ 9862 }, {}, { [9862] = true }) == "cooldowns", "a custom spell ID keeps exact matching")

-------------------------------------------------------------------------------
-- Retail: no rank matching
-------------------------------------------------------------------------------
FRAMES = { Frame(101, 2941), Frame(103, 17920), Frame(102, 689) }
ORDERED = { 101, 103, 102 }
ns, store = Load(false)
assert(ns.CDMRankName == nil, "no rank names off Forever")
assert(ns.FindVariantIndexInList({ 348 }, 2941) == nil, "retail matches by ID and variant only")
store.cooldowns.assignedSpells = { 348, 689 }
onBar = {}
for _, sp in ipairs(ns.GetCDMSpellsForBar("cooldowns")) do onBar[sp.spellID] = sp.onEUIBar end
assert(onBar[2941] == false, "retail picker marks by ID and variant only")
store.cooldowns.assignedSpells = { 2941, 348, 689 }
local list = store.cooldowns.assignedSpells
ns.CDMO_EnsureAssignedSpells("cooldowns")
assert(list[1] == 2941 and list[#list] == 689, "retail normalize pass keeps its order")
FRAMES = { Frame(101, 2941) }
ghost = ImportGhost(ns, store, { 348 })
assert(Same(ghost, { 2941 }), "retail import ghosting matches by ID and variant only: " .. Show(ghost))

print("test_cdm_forever_ranks: all checks passed")
