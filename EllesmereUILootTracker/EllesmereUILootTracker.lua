if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local ADDON_NAME, ns = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.Lite) then return end
EllesmereUI._ModuleNS[ADDON_NAME] = ns

local L = EllesmereUI.L
local DB_DEFAULTS = {
    profile = {
        enabled = true,
        showItemTooltips = true,
        showWishlistMarkers = true,
        autoArchive = true,
        showArchived = false,
        selectedKeyLevel = 10,
        raidDifficulty = 16,
        plannerMode = "overall",
        plannerSlot = "HEAD",
        craftedTargetLevel = 318,
    },
}

ns.PRIORITY_NICE = 1
ns.PRIORITY_NEED = 2
ns.PRIORITY_BIS = 3
ns.PRIORITY_ORDER = { ns.PRIORITY_BIS, ns.PRIORITY_NEED, ns.PRIORITY_NICE }
ns.PRIORITY_NAMES = {
    [ns.PRIORITY_NICE] = "Nice to have",
    [ns.PRIORITY_NEED] = "Needed",
    [ns.PRIORITY_BIS] = "Best in Slot",
}
ns.PRIORITY_COLORS = {
    [ns.PRIORITY_NICE] = { 0.35, 0.75, 1.00 },
    [ns.PRIORITY_NEED] = { 1.00, 0.72, 0.20 },
    [ns.PRIORITY_BIS] = { 0.78, 0.35, 1.00 },
}

local profileDB
local listeners = {}
local inventorySnapshot = {}
local pendingRoll
local scanQueued
local pendingItemLoads = {}
local itemLevelCache = {}
local goalIndexes = {}
local catalogRefreshQueued

local function CurrentSeasonIDs()
    local seasonID = 0
    local displaySeasonID = 0
    if C_MythicPlus and C_MythicPlus.GetCurrentSeason then
        local id = C_MythicPlus.GetCurrentSeason()
        if id and id > 0 then seasonID = id end
    end
    if C_SeasonInfo and C_SeasonInfo.GetCurrentDisplaySeasonID then
        local id = C_SeasonInfo.GetCurrentDisplaySeasonID()
        if id and id > 0 then displaySeasonID = id end
    end
    return seasonID, displaySeasonID
end

local function SeasonID()
    local seasonID, displaySeasonID = CurrentSeasonIDs()
    -- Display season IDs restart with each expansion. Normalize the supported
    -- display ID to its globally unique Mythic+ season ID so SavedVariables do
    -- not move between keys while Blizzard's Mythic+ data is still loading.
    if seasonID == ns.SUPPORTED_SEASON_ID then
        return ns.SUPPORTED_SEASON_ID
    end
    if seasonID > 0 then return seasonID end
    if displaySeasonID == ns.SUPPORTED_DISPLAY_SEASON_ID then
        return ns.SUPPORTED_SEASON_ID
    end
    return displaySeasonID
end
ns.GetSeasonID = SeasonID

function ns.IsSeasonSupported()
    local seasonID, displaySeasonID = CurrentSeasonIDs()
    if seasonID > 0 then return seasonID == ns.SUPPORTED_SEASON_ID end
    return displaySeasonID == 0
        or displaySeasonID == ns.SUPPORTED_DISPLAY_SEASON_ID
end

local function ResolveSpecID(specID)
    if specID and specID > 0 then return specID end
    local lootSpec = GetLootSpecialization and GetLootSpecialization() or 0
    if lootSpec and lootSpec > 0 then return lootSpec end
    local index = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    if index then return C_SpecializationInfo.GetSpecializationInfo(index) end
    return 0
end
ns.ResolveSpecID = ResolveSpecID

local function EnsureCharacterDB()
    if type(EllesmereUILootTrackerCharDB) ~= "table" then EllesmereUILootTrackerCharDB = {} end
    local db = EllesmereUILootTrackerCharDB
    db.schema = 1
    db.seasons = db.seasons or {}
    local season = tostring(SeasonID())
    local legacyDisplaySeason = tostring(ns.SUPPORTED_DISPLAY_SEASON_ID or "")
    if season == tostring(ns.SUPPORTED_SEASON_ID)
        and legacyDisplaySeason ~= season
        and db.seasons[legacyDisplaySeason]
        and not db.seasons[season] then
        db.seasons[season] = db.seasons[legacyDisplaySeason]
        db.seasons[legacyDisplaySeason] = nil
    end
    db.seasons[season] = db.seasons[season] or { specs = {}, pools = {}, rolls = {} }
    local activeSeason = db.seasons[season]
    if activeSeason.dataRevision ~= ns.SEASON_DATA_REVISION then
        for _, specData in pairs(activeSeason.specs or {}) do
            for _, goal in pairs(specData.goals or {}) do
                if goal.sourceKind == "dungeon" and goal.keyLevel then
                    goal.minItemLevel = ns.GetMPlusTargetLevel(goal.keyLevel)
                end
            end
        end
        activeSeason.dataRevision = ns.SEASON_DATA_REVISION
    end
    db.activeSeason = season
    return db, activeSeason
end

function ns.GetProfile()
    return profileDB and profileDB.profile or DB_DEFAULTS.profile
end

function ns.GetSeasonData()
    return select(2, EnsureCharacterDB())
end

function ns.GetRollHistory()
    return ns.GetSeasonData().rolls
end

local function SpecData(specID)
    local season = ns.GetSeasonData()
    specID = tostring(ResolveSpecID(specID))
    season.specs[specID] = season.specs[specID] or { goals = {} }
    return season.specs[specID]
end

local function FireChanged(reason)
    for _, callback in ipairs(listeners) do
        pcall(callback, reason)
    end
end

function ns.NotifyChanged(reason)
    FireChanged(reason or "planner")
end

function ns.RegisterCallback(callback)
    if type(callback) == "function" then listeners[#listeners + 1] = callback end
end

local function GoalKey(sourceKey, itemID)
    return tostring(sourceKey) .. ":item:" .. tostring(itemID)
end

local function GoalIndexKey(specID)
    return tostring(SeasonID()) .. ":" .. tostring(ResolveSpecID(specID))
end

local function InvalidateGoalIndex(specID)
    goalIndexes[GoalIndexKey(specID)] = nil
end

function ns.GetGoals(specID, includeArchived)
    local goals = {}
    for _, goal in pairs(SpecData(specID).goals) do
        if includeArchived or goal.state ~= "archived" then goals[#goals + 1] = goal end
    end
    table.sort(goals, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        if a.sourceKey ~= b.sourceKey then return a.sourceKey < b.sourceKey end
        return a.itemID < b.itemID
    end)
    return goals
end

function ns.GetGoal(sourceKey, itemID, specID)
    return SpecData(specID).goals[GoalKey(sourceKey, itemID)]
end

function ns.GetGoalLookup(specID)
    local indexKey = GoalIndexKey(specID)
    local index = goalIndexes[indexKey]
    if index then return index end
    index = {}
    for _, goal in pairs(SpecData(specID).goals) do
        local best = index[goal.itemID]
        if not best
            or (best.state == "archived" and goal.state == "open")
            or (best.state == goal.state and goal.priority > best.priority) then
            index[goal.itemID] = goal
        end
    end
    goalIndexes[indexKey] = index
    return index
end

function ns.GetAnyGoal(itemID, specID)
    return ns.GetGoalLookup(specID)[tonumber(itemID) or itemID]
end

function ns.AddGoal(source, item, priority, specID, difficultyID, targetLevel)
    if not source or not item or not item.itemID then return end
    specID = ResolveSpecID(specID)
    local sourceKey = ns.GetSourceKey(source, difficultyID)
    local goal = {
        sourceKey = sourceKey,
        sourceKind = source.kind,
        sourceID = source.kind == "raid" and source.encounterID
            or (source.kind == "dungeon" and source.challengeModeID or source.sourceID),
        sourceName = source.name,
        instanceName = source.instanceName,
        itemID = item.itemID,
        itemName = item.name,
        itemLink = item.link,
        itemIcon = item.icon,
        itemLevel = item.itemLevel,
        priority = priority or ns.PRIORITY_NICE,
        specID = specID,
        difficultyID = source.kind == "raid" and (difficultyID or 16) or nil,
        keyLevel = source.kind == "dungeon" and ns.GetProfile().selectedKeyLevel or nil,
        minItemLevel = targetLevel,
        state = "open",
        createdAt = time(),
    }
    SpecData(specID).goals[GoalKey(sourceKey, item.itemID)] = goal
    InvalidateGoalIndex(specID)
    FireChanged("goal")
    ns.QueueInventoryScan()
    return goal
end

function ns.GetSourceKey(source, difficultyID)
    if not source then return nil end
    if source.kind == "raid" then return ns.RaidKey(source.encounterID, difficultyID) end
    if source.kind == "dungeon" then return ns.DungeonKey(source.challengeModeID) end
    return source.key or (tostring(source.kind) .. ":" .. tostring(source.sourceID or 0))
end

function ns.GetSpecData(specID)
    return SpecData(specID)
end

function ns.RemoveGoal(sourceKey, itemID, specID)
    local data = SpecData(specID)
    for _, plan in pairs(data.plans or {}) do
        for slotKey, selection in pairs(plan.slots or {}) do
            if selection.sourceKey == sourceKey and selection.itemID == itemID then
                plan.slots[slotKey] = nil
                plan.updatedAt = time()
            end
        end
    end
    data.goals[GoalKey(sourceKey, itemID)] = nil
    InvalidateGoalIndex(specID)
    FireChanged("goal")
end

function ns.SetPriority(sourceKey, itemID, priority, specID)
    local goal = ns.GetGoal(sourceKey, itemID, specID)
    if not goal then return end
    goal.priority = priority
    goal.updatedAt = time()
    InvalidateGoalIndex(specID)
    FireChanged("goal")
end

function ns.ReactivateGoal(sourceKey, itemID, specID)
    local goal = ns.GetGoal(sourceKey, itemID, specID)
    if not goal then return end
    goal.state, goal.obtainedAt, goal.obtainedLink = "open", nil, nil
    InvalidateGoalIndex(specID)
    FireChanged("goal")
end

function ns.CycleGoal(source, item, specID, difficultyID, targetLevel)
    local sourceKey = ns.GetSourceKey(source, difficultyID)
    local goal = ns.GetGoal(sourceKey, item.itemID, specID)
    if not goal then return ns.AddGoal(source, item, ns.PRIORITY_NICE, specID, difficultyID, targetLevel) end
    if goal.priority == ns.PRIORITY_NICE then
        ns.SetPriority(sourceKey, item.itemID, ns.PRIORITY_NEED, specID)
    elseif goal.priority == ns.PRIORITY_NEED then
        ns.SetPriority(sourceKey, item.itemID, ns.PRIORITY_BIS, specID)
    else
        ns.RemoveGoal(sourceKey, item.itemID, specID)
    end
end

local function PoolKey(sourceKey, specID)
    return tostring(ResolveSpecID(specID)) .. ":" .. sourceKey
end

function ns.GetPool(sourceKey, specID)
    local pools = ns.GetSeasonData().pools
    local key = PoolKey(sourceKey, specID)
    pools[key] = pools[key] or { knocked = {}, confidence = "estimated" }
    return pools[key]
end

function ns.SetPoolItemState(sourceKey, itemID, knocked, specID, confidence)
    local pool = ns.GetPool(sourceKey, specID)
    pool.knocked[itemID] = knocked and time() or nil
    pool.updatedAt = time()
    if confidence then pool.confidence = confidence end
    FireChanged("pool")
end

function ns.GetSourceSummary(source, specID, difficultyID)
    specID = ResolveSpecID(specID)
    local sourceKey = ns.GetSourceKey(source, difficultyID)
    local items = ns.GetCatalog(source, specID, difficultyID)
    if source.kind ~= "raid" and source.kind ~= "dungeon" then
        local desired = 0
        for _, item in ipairs(items) do
            local goal = ns.GetGoal(sourceKey, item.itemID, specID)
            if goal and goal.state == "open" then desired = desired + 1 end
        end
        return { sourceKey=sourceKey, desired=desired, remaining=#items, total=#items,
            chance=0, confidence="not-applicable", coreCost=0 }
    end
    local pool = ns.GetPool(sourceKey, specID)
    local desired, remaining, total = 0, 0, #items
    for _, item in ipairs(items) do
        if not pool.knocked[item.itemID] then
            remaining = remaining + 1
            local goal = ns.GetGoal(sourceKey, item.itemID, specID)
            if goal and goal.state == "open" then desired = desired + 1 end
        end
    end
    return {
        sourceKey = sourceKey,
        desired = desired,
        remaining = remaining,
        total = total,
        chance = remaining > 0 and desired / remaining or 0,
        confidence = pool.confidence,
        coreCost = source.coreCost,
    }
end

local function SafeItemLevel(link)
    if not link or not C_Item.GetDetailedItemLevelInfo then return 0 end
    local cached = itemLevelCache[link]
    if cached then return cached end
    local level = C_Item.GetDetailedItemLevelInfo(link)
    if issecretvalue and issecretvalue(level) then return 0 end
    level = tonumber(level) or 0
    if level > 0 then itemLevelCache[link] = level end
    return level
end

local function AddSnapshotItem(snapshot, link, count)
    if issecretvalue and (issecretvalue(link) or issecretvalue(count)) then return end
    if not link then return end
    local itemID = C_Item.GetItemInfoInstant(link)
    if issecretvalue and issecretvalue(itemID) then return end
    if not itemID then return end
    local entry = snapshot[itemID] or { count = 0, maxLevel = 0, link = link }
    entry.count = entry.count + (count or 1)
    local level = SafeItemLevel(link)
    if level == 0 and not pendingItemLoads[itemID] then
        pendingItemLoads[itemID] = true
        local item = Item:CreateFromItemLink(link)
        item:ContinueOnItemLoad(function()
            pendingItemLoads[itemID] = nil
            ns.QueueInventoryScan()
        end)
    end
    if level >= entry.maxLevel then entry.maxLevel, entry.link = level, link end
    snapshot[itemID] = entry
end

local function BuildInventorySnapshot()
    local snapshot = {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then AddSnapshotItem(snapshot, info.hyperlink, info.stackCount) end
        end
    end
    for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
        AddSnapshotItem(snapshot, GetInventoryItemLink("player", slot), 1)
    end
    return snapshot
end

local function InventoryChanged(previous, current)
    for itemID, entry in pairs(current) do
        local old = previous[itemID]
        if not old or old.count ~= entry.count or old.maxLevel ~= entry.maxLevel
            or old.link ~= entry.link then return true end
    end
    for itemID in pairs(previous) do
        if not current[itemID] then return true end
    end
    return false
end

function ns.GetOwnedItem(itemID, minimumItemLevel)
    local owned = inventorySnapshot[tonumber(itemID) or itemID]
    if not owned or owned.count <= 0 then return nil end
    if owned.maxLevel < (tonumber(minimumItemLevel) or 0) then return nil end
    return owned
end

function ns.IsItemOwned(itemID, minimumItemLevel)
    return ns.GetOwnedItem(itemID, minimumItemLevel) ~= nil
end

local function ReconcileInventory(snapshot)
    if not ns.GetProfile().autoArchive then return false end
    local changed
    for _, goal in ipairs(ns.GetGoals(nil, false)) do
        local owned = snapshot[goal.itemID]
        if owned and owned.count > 0 and owned.maxLevel >= (goal.minItemLevel or 0) then
            goal.state = "archived"
            goal.obtainedAt = time()
            goal.obtainedLink = owned.link
            changed = true
        end
    end
    if changed then InvalidateGoalIndex() end
    return changed and true or false
end

function ns.QueueInventoryScan()
    if scanQueued then return end
    scanQueued = true
    C_Timer.After(0.2, function()
        scanQueued = nil
        local snapshot = BuildInventorySnapshot()
        local changed = InventoryChanged(inventorySnapshot, snapshot)
        local goalsChanged = ReconcileInventory(snapshot)
        inventorySnapshot = snapshot
        if changed or goalsChanged then FireChanged("inventory") end
    end)
end

local function QueueCatalogRefresh()
    if catalogRefreshQueued then return end
    catalogRefreshQueued = true
    C_Timer.After(0.1, function()
        catalogRefreshQueued = nil
        ns.InvalidateCatalog()
        FireChanged("catalog")
    end)
end

function ns.RescanSource(source, specID, difficultyID, onDone)
    specID = ResolveSpecID(specID)
    local sourceKey = source.kind == "raid"
        and ns.RaidKey(source.encounterID, difficultyID)
        or ns.DungeonKey(source.challengeModeID)
    local candidates = ns.GetCatalog(source, specID, difficultyID)
    if #candidates == 0 then
        if onDone then onDone(false) end
        return
    end
    local attempts, previousCount, stable = 0, -1, 0
    local function Poll()
        attempts = attempts + 1
        local remainingNames = ns.ReadRemainingNames(source.chestItemID)
        local count = 0
        if remainingNames then for _ in pairs(remainingNames) do count = count + 1 end end
        if count == previousCount and count > 0 then stable = stable + 1 else stable = 1 end
        previousCount = count
        if remainingNames and count <= #candidates and stable >= 3 then
            local pool = ns.GetPool(sourceKey, specID)
            wipe(pool.knocked)
            for _, item in ipairs(candidates) do
                local name = item.name or (item.link and C_Item.GetItemNameByID(item.itemID))
                if name and not remainingNames[name] then pool.knocked[item.itemID] = time() end
            end
            pool.confidence, pool.updatedAt = "verified", time()
            FireChanged("pool")
            if onDone then onDone(true) end
        elseif attempts < 10 then
            C_Timer.After(0.3, Poll)
        elseif onDone then
            onDone(false)
        end
    end
    Poll()
end

function ns.RescanVoidcorePools(onDone)
    local sources = {}
    for _, source in ipairs(ns.GetSources("dungeon")) do sources[#sources + 1] = source end
    for _, source in ipairs(ns.GetSources("raid")) do sources[#sources + 1] = source end
    local index = 0
    local function Next()
        index = index + 1
        local source = sources[index]
        if not source then if onDone then onDone() end return end
        ns.RescanSource(source, nil, source.kind == "raid" and ns.GetProfile().raidDifficulty or nil, Next)
    end
    Next()
end

local function OnSpellConfirmation(_, spellID)
    local prompts = GetSpellConfirmationPromptsInfo and GetSpellConfirmationPromptsInfo()
    if not prompts then return end
    for _, prompt in ipairs(prompts) do
        if prompt.spellID == spellID and ns.GetSourceByChest(prompt.displayItemID) then
            local source = ns.GetSourceByChest(prompt.displayItemID)
            local difficultyID = source.kind == "raid" and (GetBonusRollEncounterJournalLinkDifficulty and GetBonusRollEncounterJournalLinkDifficulty()) or nil
            pendingRoll = {
                currencyID = prompt.currencyID,
                chestItemID = prompt.displayItemID,
                itemContext = prompt.itemContext,
                keyLevel = prompt.treasureContextLevel,
                difficultyID = difficultyID,
                specID = ResolveSpecID(),
            }
            return
        end
    end
end

local function OnBonusRoll(_, rewardType, rewardLink, _, rewardSpecID)
    if (issecretvalue and (issecretvalue(rewardType) or issecretvalue(rewardLink)))
        or rewardType ~= "item" or type(rewardLink) ~= "string" then
        pendingRoll = nil
        return
    end
    local itemID = C_Item.GetItemInfoInstant(rewardLink)
    if issecretvalue and issecretvalue(itemID) then pendingRoll = nil return end
    local context = pendingRoll
    local source = context and ns.GetSourceByChest(context.chestItemID)
    if not itemID or not source then pendingRoll = nil return end
    local specID = ResolveSpecID(rewardSpecID or context.specID)
    local difficultyID = source.kind == "raid" and (context.difficultyID or 16) or nil
    local sourceKey = source.kind == "raid" and ns.RaidKey(source.encounterID, difficultyID) or ns.DungeonKey(source.challengeModeID)
    ns.SetPoolItemState(sourceKey, itemID, true, specID, "tracked")
    local rolls = ns.GetSeasonData().rolls
    rolls[#rolls + 1] = {
        time = time(), itemID = itemID, itemLink = rewardLink, specID = specID,
        sourceKey = sourceKey, chestItemID = context.chestItemID,
        itemContext = context.itemContext, keyLevel = context.keyLevel,
        difficultyID = difficultyID, currencyID = context.currencyID,
    }
    while #rolls > 100 do table.remove(rolls, 1) end
    pendingRoll = nil
    ns.QueueInventoryScan()
    C_Timer.After(0.8, function() ns.RescanSource(source, specID, difficultyID) end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("SPELL_CONFIRMATION_PROMPT")
eventFrame:RegisterEvent("BONUS_ROLL_RESULT")
eventFrame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
eventFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
eventFrame:RegisterEvent("TRADE_SKILL_DATA_SOURCE_CHANGED")
eventFrame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" and ... == ADDON_NAME then
        profileDB = EllesmereUI.Lite.NewDB("EllesmereUILootTrackerDB", DB_DEFAULTS)
        EnsureCharacterDB()
    elseif event == "ADDON_LOADED" and (... == "Blizzard_Professions" or ... == "Blizzard_CraftingOrders") then
        if ns.QueueCraftedScan then ns.QueueCraftedScan(0.5) end
    elseif event == "PLAYER_LOGIN" then
        if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
        inventorySnapshot = BuildInventorySnapshot()
        ReconcileInventory(inventorySnapshot)
        if ns.QueueCraftedScan then ns.QueueCraftedScan(1) end
    elseif event == "SPELL_CONFIRMATION_PROMPT" then
        OnSpellConfirmation(event, ...)
    elseif event == "BONUS_ROLL_RESULT" then
        OnBonusRoll(event, ...)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        ns.InvalidateCatalog()
        FireChanged("spec")
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        local itemID = ...
        if ns.ConsumePendingCatalogItem and ns.ConsumePendingCatalogItem(itemID) then
            QueueCatalogRefresh()
        end
    elseif event == "EJ_LOOT_DATA_RECIEVED" or event == "CHALLENGE_MODE_MAPS_UPDATE" then
        QueueCatalogRefresh()
    elseif event == "TRADE_SKILL_DATA_SOURCE_CHANGED" or event == "TRADE_SKILL_LIST_UPDATE" then
        if ns.QueueCraftedScan then ns.QueueCraftedScan(0.2) end
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        ns.QueueInventoryScan()
    end
end)

_G.EllesmereUILootTracker = ns
_G._EULT_DB = function() return profileDB end

SLASH_EULT1 = "/eult"
SLASH_EULT2 = "/loottracker"
SlashCmdList.EULT = function()
    if InCombatLockdown and InCombatLockdown() then return end
    EllesmereUI:ShowModule(ADDON_NAME)
end
