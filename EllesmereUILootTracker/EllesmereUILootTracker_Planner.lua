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

local catalystSource = { kind="catalyst", key="catalyst", sourceID=1, name="Catalyst Tier Set" }
local craftedSource = { kind="crafted", key="crafted", sourceID=1, name="Crafted Gear" }

local function ValidItemLink(link)
    return type(link) == "string"
        and (link:find("|Hitem:", 1, true) ~= nil or link:match("^item:%d+") ~= nil)
end

local function ItemRecord(itemID, link, recipeID, recipeName)
    itemID = tonumber(itemID)
    if not itemID then return nil end
    local _, _, _, equipLoc, icon, classID = C_Item.GetItemInfoInstant(itemID)
    if not equipLoc or equipLoc == "" then return nil end
    if Enum and Enum.ItemClass and classID ~= Enum.ItemClass.Armor
        and classID ~= Enum.ItemClass.Weapon then return nil end
    local name, cachedLink = C_Item.GetItemInfo(itemID)
    if (not name or not cachedLink) and ns.RequestCatalogItemData then ns.RequestCatalogItemData(itemID) end
    local resolvedLink = (ValidItemLink(link) and link) or cachedLink or ("item:" .. itemID)
    local itemLevel = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(resolvedLink)
    if issecretvalue and issecretvalue(itemLevel) then itemLevel = nil end
    return {
        itemID=itemID, name=name or ("Item " .. itemID), link=resolvedLink,
        icon=icon, equipLoc=equipLoc, slot=_G[equipLoc] or equipLoc,
        itemLevel=tonumber(itemLevel), recipeID=recipeID, recipeName=recipeName,
    }
end

local function CatalystCatalog(specID)
    local classID = select(3, UnitClass("player"))
    local items = {}
    for _, itemID in ipairs(ns.CATALYST_ITEMS_BY_CLASS[classID] or {}) do
        local item = ItemRecord(itemID)
        if item then items[#items + 1] = item
        elseif ns.RequestCatalogItemData then ns.RequestCatalogItemData(itemID) end
    end
    return items
end

local function CraftedStore()
    local season = ns.GetSeasonData()
    season.craftedItems = season.craftedItems or {}
    return season.craftedItems
end

local function CraftedCatalog(specID)
    local items = {}
    local classID = select(3, UnitClass("player"))
    for itemID, saved in pairs(CraftedStore()) do
        local eligible = true
        if C_Item.DoesItemContainSpec then
            local ok, result = pcall(C_Item.DoesItemContainSpec, tonumber(itemID), classID or 0, specID)
            if ok and result ~= nil and not (issecretvalue and issecretvalue(result)) then eligible = result end
        end
        if eligible then
            local item = ItemRecord(itemID, saved.link, saved.recipeID, saved.recipeName)
            if item then
                -- Older manual-ID entries stored the edit-box text ("237834")
                -- as if it were a hyperlink. Repair them while the catalog is
                -- read so future sessions no longer need the fallback.
                if saved.link ~= item.link then saved.link = item.link end
                items[#items + 1] = item
            end
        end
    end
    table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)
    return items
end

catalystSource.getCatalog = CatalystCatalog
craftedSource.getCatalog = CraftedCatalog
ns.RegisterSource(catalystSource)
ns.RegisterSource(craftedSource)

local function SaveCraftedItem(itemID, link, recipeID, recipeName, allowLegacy)
    local item = ItemRecord(itemID, link, recipeID, recipeName)
    if not item or (not allowLegacy and item.itemID < 260000) then return false end
    local store = CraftedStore()
    local old = store[item.itemID]
    store[item.itemID] = {
        link=item.link, recipeID=recipeID, recipeName=recipeName,
        discoveredAt=old and old.discoveredAt or time(),
    }
    return old == nil
end

function ns.AddCraftedItemLink(value)
    local itemID = tonumber(value)
    if not itemID and type(value) == "string" then itemID = C_Item.GetItemInfoInstant(value) end
    if not itemID then return false, "invalid" end
    if SaveCraftedItem(itemID, type(value) == "string" and value or nil, nil, nil, true) then
        ns.NotifyChanged("crafted")
    end
    return ItemRecord(itemID) ~= nil
end

function ns.ScanCraftedItems()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return 0 end
    local ok, recipeIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not ok or type(recipeIDs) ~= "table" then return 0 end
    local added = 0
    for _, recipeID in ipairs(recipeIDs) do
        local recipeInfo = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
        local ids
        if C_TradeSkillUI.GetRecipeQualityItemIDs then
            local qualityOK, qualityIDs = pcall(C_TradeSkillUI.GetRecipeQualityItemIDs, recipeID)
            if qualityOK and type(qualityIDs) == "table" then ids = qualityIDs end
        end
        -- Quality IDs are returned from lowest to highest quality. Keep one
        -- planner entry per recipe instead of showing every quality variant.
        local bestID = ids and ids[#ids]
        local bestLink = bestID and select(2, C_Item.GetItemInfo(bestID))
        if not bestID and C_TradeSkillUI.GetRecipeItemLink then
            local linkOK, link = pcall(C_TradeSkillUI.GetRecipeItemLink, recipeID)
            if linkOK and link then bestID, bestLink = C_Item.GetItemInfoInstant(link), link end
        end
        if bestID and SaveCraftedItem(bestID, bestLink, recipeID, recipeInfo and recipeInfo.name, false) then
            added = added + 1
        end
    end
    if added > 0 then ns.NotifyChanged("crafted") end
    return added
end

local craftedScanQueued
function ns.QueueCraftedScan(delay)
    if craftedScanQueued then return end
    craftedScanQueued = true
    C_Timer.After(delay or 0.3, function()
        craftedScanQueued = nil
        ns.ScanCraftedItems()
    end)
end

local function PlanRef(mode, slotKey)
    return tostring(mode) .. ":" .. tostring(slotKey)
end

function ns.GetPlan(mode, specID)
    local data = ns.GetSpecData(specID)
    data.plans = data.plans or {}
    data.plans[mode] = data.plans[mode] or { slots = {}, updatedAt = time() }
    return data.plans[mode]
end

local function SyncGoalFromPlans(goal, specID)
    if not goal or not goal.plannerRefs then return end
    local best
    for _, savedPlan in pairs(ns.GetSpecData(specID).plans or {}) do
        for _, selection in pairs(savedPlan.slots or {}) do
            if selection.sourceKey == goal.sourceKey and selection.itemID == goal.itemID
                and (not best or (selection.targetLevel or 0) > (best.targetLevel or 0)) then
                best = selection
            end
        end
    end
    if best then
        goal.minItemLevel, goal.linkKind = best.targetLevel, best.linkKind
        goal.difficultyID, goal.keyLevel = best.difficultyID, best.keyLevel
        goal.itemLevel = best.itemLevel or goal.itemLevel
    end
end

function ns.RefreshPlanTargets(mode, specID, keyLevel, difficultyID, craftedTargetLevel)
    local plan = ns.GetPlan(mode, specID)
    local targetLevel = ns.GetMPlusTargetLevel(keyLevel)
    for _, selection in pairs(plan.slots) do
        if not selection.itemLevel and selection.itemLink and C_Item.GetDetailedItemLevelInfo then
            local level = C_Item.GetDetailedItemLevelInfo(selection.itemLink)
            if not (issecretvalue and issecretvalue(level)) then selection.itemLevel = tonumber(level) end
        end
        if selection.sourceKind == "dungeon" or selection.linkKind == "dungeon" then
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
        elseif selection.sourceKind == "catalyst" then
            local raidLevel = ns.RAID_TARGET_LEVELS[difficultyID or 16]
            selection.difficultyID = difficultyID
            selection.targetLevel = mode == "overall" and math.max(raidLevel or 0, targetLevel or 0)
                or (raidLevel or selection.targetLevel)
            local goal = ns.GetGoal(selection.sourceKey, selection.itemID, specID)
            if goal then goal.minItemLevel = selection.targetLevel end
        elseif selection.sourceKind == "crafted" then
            selection.targetLevel = tonumber(craftedTargetLevel) or selection.targetLevel
            local goal = ns.GetGoal(selection.sourceKey, selection.itemID, specID)
            if goal then goal.minItemLevel = selection.targetLevel end
        end
    end
    for _, selection in pairs(plan.slots) do
        SyncGoalFromPlans(ns.GetGoal(selection.sourceKey, selection.itemID, specID), specID)
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
    else
        SyncGoalFromPlans(goal, specID)
    end
end

function ns.SetPlannedItem(mode, slotKey, candidate, specID)
    local plan = ns.GetPlan(mode, specID)
    local old = plan.slots[slotKey]
    if old and candidate and old.sourceKey == candidate.sourceKey and old.itemID == candidate.item.itemID then
        if old.sourceKind == "dungeon" or old.sourceKind == "raid" then
            old.catalyst = ns.ToggleGoalCatalyst(old.sourceKey, old.itemID, specID)
            plan.updatedAt = time()
        end
        return
    end
    plan.slots[slotKey] = nil
    RemovePlannerRef(old, mode, slotKey, specID)
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
            local conflict = plan.slots[conflictKey]
            plan.slots[conflictKey] = nil
            RemovePlannerRef(conflict, mode, conflictKey, specID)
        end
        local sourceKey = ns.GetSourceKey(source, candidate.difficultyID)
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
            goal.linkKind = candidate.linkKind
            goal.recipeID = item.recipeID
        end
        plan.slots[slotKey] = {
            itemID=item.itemID, itemName=item.name, itemIcon=item.icon, itemLink=item.link,
            itemLevel=item.itemLevel,
            equipLoc=item.equipLoc, sourceKey=sourceKey, sourceKind=source.kind,
            sourceName=source.name, instanceName=source.instanceName,
            sourceID=source.kind == "raid" and source.encounterID
                or (source.kind == "dungeon" and source.challengeModeID or source.sourceID),
            difficultyID=candidate.difficultyID, keyLevel=candidate.keyLevel,
            targetLevel=candidate.targetLevel, linkKind=candidate.linkKind,
            recipeID=item.recipeID, selectedAt=time(),
            catalyst=goal and goal.catalyst or nil,
        }
        SyncGoalFromPlans(goal, specID)
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
    local catalystLevel = mode == "mplus" and ns.GetMPlusTargetLevel(keyLevel)
        or ns.RAID_TARGET_LEVELS[difficultyID or 16]
    if mode == "overall" then catalystLevel = math.max(catalystLevel or 0, ns.GetMPlusTargetLevel(keyLevel) or 0) end
    for _, special in ipairs({
        { source=catalystSource, level=catalystLevel,
          linkKind=mode == "mplus" and "dungeon" or "catalyst" },
        { source=craftedSource, level=tonumber(ns.GetProfile().craftedTargetLevel) or 318,
          linkKind="crafted" },
    }) do
        for _, item in ipairs(ns.GetCatalog(special.source, specID)) do
            if item.equipLoc and slot.locs[item.equipLoc] then
                local sourceKey = special.source.key
                local unique = sourceKey .. ":" .. item.itemID
                if not seen[unique] then
                    seen[unique] = true
                    candidates[#candidates + 1] = {
                        source=special.source, item=item, sourceKey=sourceKey,
                        difficultyID=special.source.kind == "catalyst" and difficultyID or nil,
                        keyLevel=special.source.kind == "catalyst" and keyLevel or nil,
                        targetLevel=special.level or item.itemLevel,
                        linkKind=special.linkKind,
                    }
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if (a.targetLevel or 0) ~= (b.targetLevel or 0) then return (a.targetLevel or 0) > (b.targetLevel or 0) end
        return (a.item.name or "") < (b.item.name or "")
    end)
    return candidates
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
            if selection.sourceKind == "crafted" then
                lines[#lines + 1] = "# Crafted item: configure missives, embellishment and sockets manually."
            end
            local name = (selection.itemName or ("item_" .. selection.itemID)):lower()
                :gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
            lines[#lines + 1] = string.format("%s=%s,id=%d,ilevel=%d",
                SIMC_SLOT_NAMES[slot.key], name, selection.itemID, selection.targetLevel or 0)
        end
    end
    return table.concat(lines, "\n")
end
