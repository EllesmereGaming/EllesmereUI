local ns = {}

EUI_CLIENT_BLOCKED = false
Enum = { CooldownViewerCategory = {} }
issecretvalue = function() return false end

local bases = { [200025] = 53563, [9002] = 9001 }
C_Spell = {
    GetBaseSpell = function(id) return bases[id] or id end,
    GetOverrideSpell = function(id)
        if id == 53563 then return 200025 end
        if id == 9001 then return 9002 end
        return id
    end,
    GetSpellName = function(id) return "Spell " .. id end,
    GetSpellTexture = function(id) return id end,
}
C_SpellBook = {
    FindSpellOverrideByID = function(id)
        if id == 53563 then return 200025 end
        if id == 9001 then return 9002 end
        return id
    end,
}

local function Frame(cdID, sid, layoutIndex)
    return {
        cooldownID = cdID,
        cooldownInfo = { spellID = sid },
        layoutIndex = layoutIndex,
        IsShown = function() return true end,
        GetSpellID = function() return sid end,
    }
end

local function Pool(frames)
    return {
        EnumerateActive = function()
            local i = 0
            return function()
                i = i + 1
                return frames[i]
            end
        end,
    }
end

EssentialCooldownViewer = { itemFramePool = Pool({
    Frame(65, 53563, 1),
    Frame(90, 9001, 2),
}) }
UtilityCooldownViewer = { itemFramePool = Pool({
    Frame(66, 200025, 1),
}) }
BuffIconCooldownViewer = { itemFramePool = Pool({
    Frame(201, 7001, 1),
    Frame(202, 7001, 2),
}) }

local bars = {
    { key = "cooldowns", barType = "cooldowns", enabled = true },
    { key = "utility", barType = "utility", enabled = true },
    { key = "buffs", barType = "buffs", enabled = true },
    { key = "buff-extra", barType = "buffs", enabled = true },
    { key = "__ghost_cd", isGhostBar = true, enabled = true },
}
local stores = {
    cooldowns = { assignedSpells = { 53563 } },
    utility = { assignedSpells = { 156910 } },
    buffs = { assignedSpells = {} },
    ["buff-extra"] = { assignedSpells = {} },
    ["__ghost_cd"] = { assignedSpells = {} },
}

ns.ECME = { db = { profile = { cdmBars = { bars = bars } } } }
ns.barDataByKey = {}
for _, bar in ipairs(bars) do ns.barDataByKey[bar.key] = bar end
ns.cdmBarFrames = {}
ns.cdmBarIcons = {}
ns.ComputeTopRowStride = function(_, count) return math.max(count, 1), 1, count end
ns.GetBarSpellData = function(key) return stores[key] end
ns.CD_CLAIM_MARKER_BASE = 3000000000
ns.CdClaimMarker = function(cdID) return -(ns.CD_CLAIM_MARKER_BASE + cdID) end
ns.CdClaimMarkerToCdID = function(id)
    if type(id) == "number" and id <= -ns.CD_CLAIM_MARKER_BASE then
        return -id - ns.CD_CLAIM_MARKER_BASE
    end
end
ns.CollectCdClaimSet = function(sd)
    local out
    for _, id in ipairs(sd and sd.assignedSpells or {}) do
        local cdID = ns.CdClaimMarkerToCdID(id)
        if cdID then out = out or {}; out[cdID] = true end
    end
    return out
end
ns.HostedBuffMarkerToSpell = function() return nil end
ns.ListHasHostedMarker = function() return false end
ns.SlotIDFromKey = function() return nil end

local chunk = assert(loadfile("EllesmereUICooldownManager/EllesmereUICdmSpellPicker.lua"))
chunk("EllesmereUICooldownManager", ns)

local function equal(actual, expected, label)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(label, tostring(expected), tostring(actual)), 2)
    end
end

local entries = ns.EnumerateCDMViewerSpells(false)
equal(#entries, 3, "collided slots remain enumerable")
equal(entries[1].cdID, 65, "first collided slot")
equal(entries[1].isCdCollision, true, "first collision flag")
equal(entries[3].cdID, 66, "second collided slot")
equal(entries[3].isCdCollision, true, "second collision flag")
equal(entries[2].isCdCollision, false, "ordinary slot remains spell-keyed")

equal(ns.MigrateCollidedCDAssignments(), 1, "legacy migration count")
equal(stores.cooldowns.assignedSpells[1], ns.CdClaimMarker(65), "exact legacy slot claim")
equal(stores.utility.assignedSpells[1], 156910, "unrelated utility assignment")

equal(ns.AddTrackedCooldownByCdID("utility", 66), true, "add collided sibling")
equal(stores.utility.assignedSpells[2], ns.CdClaimMarker(66), "sibling stored independently")
equal(ns.AddTrackedCooldownByCdID("cooldowns", 66), true, "move collided sibling")
equal(stores.cooldowns.assignedSpells[1], ns.CdClaimMarker(65), "first slot survives sibling move")
equal(stores.cooldowns.assignedSpells[2], ns.CdClaimMarker(66), "moved sibling arrives")
equal(#stores.utility.assignedSpells, 1, "sibling removed from old bar only")

equal(ns.RemoveTrackedSpell("cooldowns", 1), true, "remove first collided slot")
equal(stores.cooldowns.assignedSpells[1], ns.CdClaimMarker(66), "second slot survives removal")
equal(stores.__ghost_cd.assignedSpells[1], ns.CdClaimMarker(65), "removed slot ghosts independently")

stores.cooldowns.assignedSpells = { 9001 }
stores.utility.assignedSpells = {}
equal(ns.AddTrackedSpell("utility", 9002), true, "ordinary override move")
equal(#stores.cooldowns.assignedSpells, 0, "ordinary base leaves old bar")
equal(stores.utility.assignedSpells[1], 9002, "ordinary override has one home")

equal(ns.AddTrackedBuffByCdID("buff-extra", 201), true, "first buff collision claim")
equal(ns.AddTrackedBuffByCdID("buffs", 202), false, "default buff bar rejects slot claims")
equal(stores["buff-extra"].assignedSpells[1], ns.CdClaimMarker(201), "buff collision behavior retained")

equal(ns.AddHostedBuffByCdID("cooldowns", 202), true, "host collided buff")
equal(ns.AddHostedBuffByCdID("utility", 202), true, "move hosted collided buff")
equal(stores.cooldowns.hostedBuffCdIDs[202], nil, "move clears old hosted metadata")
equal(stores.utility.hostedBuffCdIDs[202], true, "move retains new hosted metadata")

stores.cooldowns.assignedSpells = { 53563 }
stores.cooldowns.spellDurations = { [53563] = 15 }
equal(ns.MigrateCollidedCDAssignments(), 0, "duration-backed custom is not migrated")
equal(stores.cooldowns.assignedSpells[1], 53563, "custom entry remains spell-keyed")
stores.cooldowns.spellDurations = nil

-- Saved claims remain slot-keyed while a sibling is absent after a talent swap.
stores.cooldowns.assignedSpells = { ns.CdClaimMarker(65) }
stores.utility.assignedSpells = { ns.CdClaimMarker(66) }
stores.__ghost_cd.assignedSpells = {}
UtilityCooldownViewer.itemFramePool = Pool({})
entries = ns.GetCDMSpellsForBar("cooldowns")
equal(entries[1].isCdCollision, true, "claim survives absent sibling")
equal(entries[1].onEUIBar, true, "claimed row stays selected")
equal(ns.AddTrackedCooldownByCdID("utility", 65), true, "move surviving slot")
equal(#stores.cooldowns.assignedSpells, 0, "move removes old marker")
UtilityCooldownViewer.itemFramePool = Pool({ Frame(66, 200025, 1) })
equal(ns.MigrateCollidedCDAssignments(), 0, "migration is idempotent")

-- Execute the production routing section extracted by the Python runner.
if arg and arg[1] then
    wipe = function(t) for k in pairs(t) do t[k] = nil end end
    local routeChunk = assert(loadfile(arg[1]))
    routeChunk("EllesmereUICooldownManager", ns)
    stores.cooldowns.assignedSpells = { ns.CdClaimMarker(65) }
    stores.utility.assignedSpells = { ns.CdClaimMarker(66), 53563 }
    ns.RebuildSpellRouteMap()
    -- Claims must resolve before any spell-info query, including secret states.
    C_CooldownViewer = { GetCooldownViewerCooldownInfo = function()
        error("claimed slot must not read spell info")
    end }
    equal(ns.ResolveCDIDToBar(65, "utility"), "cooldowns", "exact slot outranks family")
    equal(ns.ResolveCDIDToBar(66, "cooldowns"), "utility", "sibling route is independent")
    equal(ns.RemoveTrackedSpell("cooldowns", 1), true, "remove routed slot")
    equal(ns.ResolveCDIDToBar(65, "cooldowns"), "__ghost_cd", "ghost routing invalidates cache")
    equal(ns.ResolveCDIDToBar(66, "cooldowns"), "utility", "ghost leaves sibling visible")
    equal(ns.AddTrackedCooldownByCdID("cooldowns", 65), true, "restore ghosted slot")
    equal(ns.ResolveCDIDToBar(65, "utility"), "cooldowns", "restore invalidates ghost cache")
    equal(#stores.__ghost_cd.assignedSpells, 0, "restored slot leaves ghost")

    -- Repopulate must not drop legacy buff claims while they are untalented.
    BuffIconCooldownViewer.itemFramePool = Pool({})
    C_CooldownViewer.GetCooldownViewerCooldownInfo = function(cdID)
        if cdID == 201 then return { category = 2, spellID = 7001 } end
    end
    stores.cooldowns.assignedSpells = { ns.CdClaimMarker(65), ns.CdClaimMarker(201), -13 }
    stores.utility.assignedSpells = { ns.CdClaimMarker(66) }
    stores["buff-extra"].assignedSpells = { ns.CdClaimMarker(203) }
    ns.GetActiveSpecKey = function() return "65" end
    ns.FullCDMRebuild = function() ns.RebuildSpellRouteMap() end
    ns.ReseedAssignedSpellsFromLiveIcons = function() end
    C_Timer = { After = function(_, fn) fn() end }
    ns.RepopulateFromBlizzard()
    equal(stores.cooldowns.assignedSpells[1], ns.CdClaimMarker(201), "inactive legacy buff survives repopulate")
    equal(stores.cooldowns.assignedSpells[2], -13, "equipment preset survives repopulate")
    equal(#stores.utility.assignedSpells, 0, "CD claim released on repopulate")
    equal(stores["buff-extra"].assignedSpells[1], ns.CdClaimMarker(203), "unavailable claim preserved conservatively")
end

print("cdm collision claim harness: PASS")
