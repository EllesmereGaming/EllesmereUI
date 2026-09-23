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
    local routeInfoReads = 0
    C_CooldownViewer = { GetCooldownViewerCooldownInfo = function()
        routeInfoReads = routeInfoReads + 1
        return nil
    end }
    equal(ns.ResolveCDIDToBar(65, "utility"), "cooldowns", "exact slot outranks family")
    equal(ns.ResolveCDIDToBar(66, "cooldowns"), "utility", "sibling route is independent")
    equal(routeInfoReads, 0, "claimed routes do not read spell info")
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

-- Duplicate views and base-only API ties must not migrate unrelated assignments.
for _, sd in pairs(stores) do sd.assignedSpells = {} end
EssentialCooldownViewer.itemFramePool = Pool({ Frame(301, 8001, 1) })
UtilityCooldownViewer.itemFramePool = Pool({ Frame(302, 8001, 1) })
stores.cooldowns.assignedSpells = { 8001 }
equal(#ns.EnumerateCDMViewerSpells(false), 1, "same spell in two viewers remains deduplicated")
equal(ns.MigrateCollidedCDAssignments(), 0, "duplicate views do not migrate")
bases[8002] = 8001
UtilityCooldownViewer.itemFramePool = Pool({ Frame(302, 8002, 1) })
equal(ns.EnumerateCDMViewerSpells(false)[1].isCdCollision, false, "base-only tie does not collide")
equal(ns.MigrateCollidedCDAssignments(), 0, "base-only tie does not migrate")

-- Distinct source spells remain separable even when both show Virtue.
local light = Frame(65, 53563, 1)
light.cooldownInfo.overrideSpellID = 200025
light.GetSpellID = function() return 200025 end
EssentialCooldownViewer.itemFramePool = Pool({ light })
UtilityCooldownViewer.itemFramePool = Pool({ Frame(66, 200025, 1) })
equal(#ns.EnumerateCDMViewerSpells(false), 2, "same displayed override retains distinct source slots")
stores.cooldowns.assignedSpells = { 53563 }
ns.AddTrackedCooldownByCdID("cooldowns", 65)
equal(#stores.cooldowns.assignedSpells, 1, "early picker click leaves one assignment")
equal(stores.cooldowns.assignedSpells[1], ns.CdClaimMarker(65), "early picker settles legacy identity")
equal(ns.MigrateCollidedCDAssignments(), 0, "early click cannot capture sibling later")
stores.cooldowns.assignedSpells = { ns.CdClaimMarker(65), ns.CdClaimMarker(66), 156910 }
ns.MoveTrackedSpell("cooldowns", 1, 3)
equal(stores.cooldowns.assignedSpells[3], ns.CdClaimMarker(65), "index move retains slot marker")
ns.SwapTrackedSpells("cooldowns", 1, 3)
equal(stores.cooldowns.assignedSpells[1], ns.CdClaimMarker(65), "index swap retains first slot")
equal(stores.cooldowns.assignedSpells[3], ns.CdClaimMarker(66), "index swap retains sibling")

stores.cooldowns.assignedSpells = { ns.CdClaimMarker(999) }
stores.__ghost_cd.assignedSpells = {}
C_CooldownViewer = { GetCooldownViewerCooldownInfo = function() return nil end }
equal(ns.RemoveTrackedSpell("cooldowns", 1), true, "remove unavailable legacy buff")
equal(#stores.__ghost_cd.assignedSpells, 0, "unavailable legacy buff is never ghosted")

if arg and arg[1] then
    -- User-provided live Beacon metadata, with the exact saved placement.
    for _, sd in pairs(stores) do sd.assignedSpells = {} end
    stores.cooldowns.assignedSpells = { ns.CdClaimMarker(29265) }
    stores.utility.assignedSpells = { ns.CdClaimMarker(90506), 156910 }
    stores.__ghost_cd.assignedSpells = { 53563 }
    EssentialCooldownViewer.itemFramePool = Pool({ Frame(29265, 200025, 1) })
    UtilityCooldownViewer.itemFramePool = Pool({ Frame(90506, 53563, 1) })
    local info = {
        [29265] = { spellID = 200025, overrideSpellID = 200025, isKnown = true, category = 0, flags = 0 },
        [90506] = { spellID = 53563, overrideSpellID = 200025, isKnown = true, category = 0, flags = 2 },
    }
    local combat, reads = false, 0
    InCombatLockdown = function() return combat end
    C_CooldownViewer.GetCooldownViewerCooldownInfo = function(cdID)
        reads = reads + 1
        assert(not combat, "combat rebuild must use clean cached metadata")
        return info[cdID]
    end
    ns.RebuildSpellRouteMap()
    equal(ns.ResolveCDIDToBar(29265, "cooldowns"), "cooldowns", "native Virtue remains above")
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "__ghost_cd", "overridden Light duplicate is hidden")
    equal(stores.utility.assignedSpells[1], ns.CdClaimMarker(90506), "hidden Light keeps Utility slot")
    equal(stores.utility.assignedSpells[2], 156910, "Faith assignment unchanged")
    info[777] = { spellID = 888, overrideSpellID = 888, isKnown = true, category = 0 }
    equal(ns.ResolveCDIDToBar(777, "utility"), "utility", "unrelated route is cached")
    ns.RefreshRedundantOverrideClaims()
    equal(ns._cdidRouteMap[777], "utility", "unchanged suppression preserves unrelated route cache")
    local cachedReads = reads
    ns.ResolveCDIDToBar(777, "utility")
    equal(reads, cachedReads, "unchanged refresh avoids another route metadata query")
    EssentialCooldownViewer.itemFramePool = Pool({})
    ns.RefreshRedundantOverrideClaims()
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "utility", "absent native frame restores Light on reanchor")
    EssentialCooldownViewer.itemFramePool = Pool({ Frame(29265, 200025, 1) })
    ns.RefreshRedundantOverrideClaims()
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "__ghost_cd", "returning native frame clears cached fallback")
    info[29265].isInvisible = true
    ns.RebuildSpellRouteMap()
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "utility", "invisible native cannot suppress Light")
    info[29265].isInvisible = false
    bars[1].enabled = false
    ns.RebuildSpellRouteMap()
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "utility", "disabled native bar cannot suppress Light")
    bars[1].enabled = true
    local secretCategory = 123456789
    issecretvalue = function(value) return value == secretCategory end
    info[29265].category = secretCategory
    ns.RebuildSpellRouteMap()
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "utility", "secret-tagged metadata is rejected")
    issecretvalue = function() return false end
    info[29265].category = 0
    ns.RebuildSpellRouteMap()
    combat = true
    local beforeReads = reads
    ns.RebuildSpellRouteMap()
    equal(reads, beforeReads, "combat rebuild makes no metadata calls")
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "__ghost_cd", "duplicate stays hidden in combat")
    ns._overrideClaimInfo = nil
    ns.RebuildSpellRouteMap()
    equal(ns._overrideClaimRefreshPending, true, "combat login requests refresh")
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "utility", "combat login fails open without metadata")
    combat = false
    ns.RebuildSpellRouteMap()
    equal(ns._overrideClaimRefreshPending, nil, "post-combat rebuild clears request")
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "__ghost_cd", "post-combat rebuild suppresses duplicate")
    info[29265].isKnown = false
    info[90506].overrideSpellID = 53563
    ns.RebuildSpellRouteMap()
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "utility", "Light returns after removing Virtue talent")
    info[29265].isKnown = true
    info[90506].overrideSpellID = 200025
    ns.RebuildSpellRouteMap()
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "__ghost_cd", "retalenting Virtue hides duplicate again")
    stores.cooldowns.assignedSpells = {}
    ns.RebuildSpellRouteMap()
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "utility", "unclaimed native Virtue leaves sole claimed icon visible")
    stores.__ghost_cd.assignedSpells = { ns.CdClaimMarker(29265) }
    ns.RebuildSpellRouteMap()
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "utility", "hidden native Virtue does not suppress Light slot")
    stores.__ghost_cd.assignedSpells = {}
    stores.cooldowns.assignedSpells = { ns.CdClaimMarker(29265) }
    info[29265].category = 2
    ns.RebuildSpellRouteMap()
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "utility", "buff entry cannot suppress cooldown")
    info[29265].category = 0
    info[29265].isKnown = false
    ns.RebuildSpellRouteMap()
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "utility", "unknown replacement cannot suppress cooldown")
    info[29265] = nil
    ns.RebuildSpellRouteMap()
    equal(ns.ResolveCDIDToBar(90506, "cooldowns"), "utility", "unavailable metadata keeps icon visible")
    equal(ns._overrideClaimRefreshPending, true, "transient missing metadata requests post-combat retry")
end

print("cdm collision claim harness: PASS")
