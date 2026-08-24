if EUI_CLIENT_BLOCKED then return end
local ADDON_NAME, ns = ...

ns.PLAN_MODES = { "overall", "mplus", "raid" }
ns.PLAN_MODE_NAMES = {
    overall = "Overall BiS",
    mplus = "Mythic+ BiS",
    raid = "Raid BiS",
}

ns.PLAN_SLOTS = {
    { key="HEAD", name=HEADSLOT, inventorySlot=INVSLOT_HEAD, locs={ ["INVTYPE_HEAD"]=true } },
    { key="NECK", name=NECKSLOT, inventorySlot=INVSLOT_NECK, locs={ ["INVTYPE_NECK"]=true } },
    { key="SHOULDER", name=SHOULDERSLOT, inventorySlot=INVSLOT_SHOULDER, locs={ ["INVTYPE_SHOULDER"]=true } },
    { key="BACK", name=BACKSLOT, inventorySlot=INVSLOT_BACK, locs={ ["INVTYPE_CLOAK"]=true } },
    { key="CHEST", name=CHESTSLOT, inventorySlot=INVSLOT_CHEST, locs={ ["INVTYPE_CHEST"]=true, ["INVTYPE_ROBE"]=true } },
    { key="WRIST", name=WRISTSLOT, inventorySlot=INVSLOT_WRIST, locs={ ["INVTYPE_WRIST"]=true } },
    { key="HANDS", name=HANDSSLOT, inventorySlot=INVSLOT_HAND, locs={ ["INVTYPE_HAND"]=true } },
    { key="WAIST", name=WAISTSLOT, inventorySlot=INVSLOT_WAIST, locs={ ["INVTYPE_WAIST"]=true } },
    { key="LEGS", name=LEGSSLOT, inventorySlot=INVSLOT_LEGS, locs={ ["INVTYPE_LEGS"]=true } },
    { key="FEET", name=FEETSLOT, inventorySlot=INVSLOT_FEET, locs={ ["INVTYPE_FEET"]=true } },
    { key="FINGER1", name=FINGER0SLOT, inventorySlot=INVSLOT_FINGER1, locs={ ["INVTYPE_FINGER"]=true } },
    { key="FINGER2", name=FINGER1SLOT, inventorySlot=INVSLOT_FINGER2, locs={ ["INVTYPE_FINGER"]=true } },
    { key="TRINKET1", name=TRINKET0SLOT, inventorySlot=INVSLOT_TRINKET1, locs={ ["INVTYPE_TRINKET"]=true } },
    { key="TRINKET2", name=TRINKET1SLOT, inventorySlot=INVSLOT_TRINKET2, locs={ ["INVTYPE_TRINKET"]=true } },
    { key="MAINHAND", name=MAINHANDSLOT, inventorySlot=INVSLOT_MAINHAND, locs={ ["INVTYPE_WEAPON"]=true, ["INVTYPE_2HWEAPON"]=true, ["INVTYPE_WEAPONMAINHAND"]=true, ["INVTYPE_RANGED"]=true, ["INVTYPE_RANGEDRIGHT"]=true } },
    { key="OFFHAND", name=SECONDARYHANDSLOT, inventorySlot=INVSLOT_OFFHAND, locs={ ["INVTYPE_WEAPON"]=true, ["INVTYPE_WEAPONOFFHAND"]=true, ["INVTYPE_SHIELD"]=true, ["INVTYPE_HOLDABLE"]=true } },
}

local slotByKey = {}
for _, slot in ipairs(ns.PLAN_SLOTS) do slotByKey[slot.key] = slot end

local function PlanRef(mode, slotKey)
    return tostring(mode) .. ":" .. tostring(slotKey)
end

function ns.GetPlan(mode, specID)
    local data = ns.GetSpecData(specID)
    data.plans = data.plans or {}
    data.plans[mode] = data.plans[mode] or { slots = {}, updatedAt = time() }
    return data.plans[mode]
end

function ns.RefreshPlanTargets(mode, specID, keyLevel)
    local plan = ns.GetPlan(mode, specID)
    local targetLevel = ns.GetMPlusTargetLevel(keyLevel)
    for _, selection in pairs(plan.slots) do
        if selection.sourceKind == "dungeon" then
            selection.keyLevel = keyLevel
            selection.targetLevel = targetLevel
            local goal = ns.GetGoal(selection.sourceKey, selection.itemID, specID)
            if goal then
                goal.keyLevel = keyLevel
                goal.minItemLevel = targetLevel
                if goal.state == "archived" and goal.obtainedLink and C_Item.GetDetailedItemLevelInfo then
                    local obtainedLevel = C_Item.GetDetailedItemLevelInfo(goal.obtainedLink)
                    if not (issecretvalue and issecretvalue(obtainedLevel))
                        and (tonumber(obtainedLevel) or 0) < targetLevel then
                        goal.state, goal.obtainedAt, goal.obtainedLink = "open", nil, nil
                    end
                end
            end
        end
    end
end

function ns.GetPlanSlot(slotKey)
    return slotByKey[slotKey]
end

local function RemovePlannerRef(selection, mode, slotKey, specID)
    if not selection then return end
    local goal = ns.GetGoal(selection.sourceKey, selection.itemID, specID)
    if not goal or not goal.plannerRefs then return end
    goal.plannerRefs[PlanRef(mode, slotKey)] = nil
    if not next(goal.plannerRefs) then
        goal.plannerRefs = nil
        if goal.plannerOnly then
            ns.RemoveGoal(selection.sourceKey, selection.itemID, specID)
        elseif goal.plannerPreviousPriority then
            local priority = goal.plannerPreviousPriority
            goal.plannerPreviousPriority = nil
            ns.SetPriority(selection.sourceKey, selection.itemID, priority, specID)
        end
    end
end

function ns.SetPlannedItem(mode, slotKey, candidate, specID)
    local plan = ns.GetPlan(mode, specID)
    local old = plan.slots[slotKey]
    if old and candidate and old.sourceKey == candidate.sourceKey and old.itemID == candidate.item.itemID then
        return
    end
    RemovePlannerRef(old, mode, slotKey, specID)
    plan.slots[slotKey] = nil
    if candidate then
        local source, item = candidate.source, candidate.item
        local conflicts = {}
        if slotKey == "MAINHAND" and item.equipLoc == "INVTYPE_2HWEAPON" then
            conflicts[#conflicts + 1] = "OFFHAND"
        elseif slotKey == "OFFHAND" then
            local main = plan.slots.MAINHAND
            if main and main.equipLoc == "INVTYPE_2HWEAPON" then conflicts[#conflicts + 1] = "MAINHAND" end
        elseif slotKey == "FINGER1" then
            if plan.slots.FINGER2 and plan.slots.FINGER2.itemID == item.itemID then conflicts[#conflicts + 1] = "FINGER2" end
        elseif slotKey == "FINGER2" then
            if plan.slots.FINGER1 and plan.slots.FINGER1.itemID == item.itemID then conflicts[#conflicts + 1] = "FINGER1" end
        elseif slotKey == "TRINKET1" then
            if plan.slots.TRINKET2 and plan.slots.TRINKET2.itemID == item.itemID then conflicts[#conflicts + 1] = "TRINKET2" end
        elseif slotKey == "TRINKET2" then
            if plan.slots.TRINKET1 and plan.slots.TRINKET1.itemID == item.itemID then conflicts[#conflicts + 1] = "TRINKET1" end
        end
        for _, conflictKey in ipairs(conflicts) do
            RemovePlannerRef(plan.slots[conflictKey], mode, conflictKey, specID)
            plan.slots[conflictKey] = nil
        end
        local sourceKey = source.kind == "raid"
            and ns.RaidKey(source.encounterID, candidate.difficultyID)
            or ns.DungeonKey(source.challengeModeID)
        local goal = ns.GetGoal(sourceKey, item.itemID, specID)
        if not goal then
            goal = ns.AddGoal(source, item, ns.PRIORITY_BIS, specID,
                candidate.difficultyID, candidate.targetLevel)
            if goal then goal.plannerOnly = true end
        else
            if not goal.plannerRefs then goal.plannerPreviousPriority = goal.priority end
            ns.SetPriority(sourceKey, item.itemID, ns.PRIORITY_BIS, specID)
        end
        if goal then
            goal.plannerRefs = goal.plannerRefs or {}
            goal.plannerRefs[PlanRef(mode, slotKey)] = true
        end
        plan.slots[slotKey] = {
            itemID=item.itemID, itemName=item.name, itemIcon=item.icon, itemLink=item.link,
            equipLoc=item.equipLoc, sourceKey=sourceKey, sourceKind=source.kind,
            sourceName=source.name, instanceName=source.instanceName,
            sourceID=source.kind == "raid" and source.encounterID or source.challengeModeID,
            difficultyID=candidate.difficultyID, keyLevel=candidate.keyLevel,
            targetLevel=candidate.targetLevel, selectedAt=time(),
        }
    end
    plan.updatedAt = time()
    ns.NotifyChanged("planner")
end

function ns.GetPlannerCandidates(mode, slotKey, specID, difficultyID, keyLevel)
    local slot = slotByKey[slotKey]
    if not slot then return {} end
    local candidates, seen = {}, {}
    local function AddKind(kind)
        for _, source in ipairs(ns.GetSources(kind)) do
            local diff = kind == "raid" and difficultyID or nil
            for _, item in ipairs(ns.GetCatalog(source, specID, diff)) do
                if not item.isToken and item.equipLoc and slot.locs[item.equipLoc] then
                    local sourceKey = kind == "raid" and ns.RaidKey(source.encounterID, diff)
                        or ns.DungeonKey(source.challengeModeID)
                    local unique = sourceKey .. ":" .. item.itemID
                    if not seen[unique] then
                        seen[unique] = true
                        local level = kind == "dungeon" and ns.GetMPlusTargetLevel(keyLevel)
                            or ns.GetRaidTargetLevel(source, specID, diff, item.itemID)
                        candidates[#candidates + 1] = {
                            source=source, item=item, sourceKey=sourceKey,
                            difficultyID=diff, keyLevel=kind == "dungeon" and keyLevel or nil,
                            targetLevel=level,
                        }
                    end
                end
            end
        end
    end
    if mode ~= "raid" then AddKind("dungeon") end
    if mode ~= "mplus" then AddKind("raid") end
    table.sort(candidates, function(a, b)
        if (a.targetLevel or 0) ~= (b.targetLevel or 0) then return (a.targetLevel or 0) > (b.targetLevel or 0) end
        return (a.item.name or "") < (b.item.name or "")
    end)
    return candidates
end

local STAT_KEYS = {
    { key="ITEM_MOD_STRENGTH_SHORT", name=SPELL_STAT1_NAME or "Strength" },
    { key="ITEM_MOD_AGILITY_SHORT", name=SPELL_STAT2_NAME or "Agility" },
    { key="ITEM_MOD_INTELLECT_SHORT", name=SPELL_STAT4_NAME or "Intellect" },
    { key="ITEM_MOD_STAMINA_SHORT", name=SPELL_STAT3_NAME or "Stamina" },
    { key="ITEM_MOD_CRIT_RATING_SHORT", name=STAT_CRITICAL_STRIKE or "Critical Strike" },
    { key="ITEM_MOD_HASTE_RATING_SHORT", name=STAT_HASTE or "Haste" },
    { key="ITEM_MOD_MASTERY_RATING_SHORT", name=STAT_MASTERY or "Mastery" },
    { key="ITEM_MOD_VERSATILITY", name=STAT_VERSATILITY or "Versatility" },
    { key="ITEM_MOD_ARMOR_SHORT", name=ARMOR or "Armor" },
}
ns.PLANNER_STAT_KEYS = STAT_KEYS

local RATING_INDEX = {
    ITEM_MOD_CRIT_RATING_SHORT = CR_CRIT_MELEE,
    ITEM_MOD_HASTE_RATING_SHORT = CR_HASTE_MELEE,
    ITEM_MOD_MASTERY_RATING_SHORT = CR_MASTERY,
    ITEM_MOD_VERSATILITY = CR_VERSATILITY_DAMAGE_DONE,
}

function ns.GetPlannerDREstimate(statKey, plannedRating)
    local ratingIndex = RATING_INDEX[statKey]
    if not ratingIndex or not GetCombatRating or not GetCombatRatingBonus then return nil end
    local ratingValue, percentValue = GetCombatRating(ratingIndex), GetCombatRatingBonus(ratingIndex)
    if issecretvalue and (issecretvalue(ratingValue) or issecretvalue(percentValue)) then return nil end
    local currentRating = tonumber(ratingValue) or 0
    local currentPercent = tonumber(percentValue) or 0
    if currentRating <= 0 or currentPercent <= 0 then return nil end
    local estimated = (tonumber(plannedRating) or 0) * currentPercent / currentRating
    return estimated, estimated >= 30
end

local function AddLinkStats(total, link)
    if not link or not GetItemStats then return end
    local stats = GetItemStats(link)
    if type(stats) ~= "table" then return end
    for _, info in ipairs(STAT_KEYS) do
        local value = stats[info.key]
        if not (issecretvalue and issecretvalue(value)) then
            total[info.key] = (total[info.key] or 0) + (tonumber(value) or 0)
        end
    end
end

function ns.GetPlannerStats(mode, specID)
    local planned, current = {}, {}
    local plan = ns.GetPlan(mode, specID)
    for _, slot in ipairs(ns.PLAN_SLOTS) do
        local selection = plan.slots[slot.key]
        if selection then
            local link = ns.GetTargetItemLink(selection.itemID, specID, selection.targetLevel,
                selection.sourceKind, selection.difficultyID, selection.keyLevel) or selection.itemLink
            AddLinkStats(planned, link)
        end
        AddLinkStats(current, GetInventoryItemLink("player", slot.inventorySlot))
    end
    return planned, current
end


local SIMC_SLOT_NAMES = {
    HEAD="head", NECK="neck", SHOULDER="shoulder", BACK="back", CHEST="chest",
    WRIST="wrist", HANDS="hands", WAIST="waist", LEGS="legs", FEET="feet",
    FINGER1="finger1", FINGER2="finger2", TRINKET1="trinket1", TRINKET2="trinket2",
    MAINHAND="main_hand", OFFHAND="off_hand",
}

function ns.GetSimCPlan(mode, specID)
    local plan = ns.GetPlan(mode, specID)
    local lines = {
        "# EllesmereUI Loot Tracker planned gear",
        "# Import this gear block into SimulationCraft or Raidbots Top Gear.",
    }
    for _, slot in ipairs(ns.PLAN_SLOTS) do
        local selection = plan.slots[slot.key]
        if selection then
            local name = (selection.itemName or ("item_" .. selection.itemID)):lower()
                :gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
            lines[#lines + 1] = string.format("%s=%s,id=%d,ilevel=%d",
                SIMC_SLOT_NAMES[slot.key], name, selection.itemID, selection.targetLevel or 0)
        end
    end
    return table.concat(lines, "\n")
end
