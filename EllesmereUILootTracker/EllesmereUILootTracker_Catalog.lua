if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
local ADDON_NAME, ns = ...

local catalog = {}
local sourceByChest = {}
local sourceByKey = {}
local dungeonJournalIDs
local pendingItemData = {}
local VALID_EQUIP_LOCS = {
    INVTYPE_HEAD = true, INVTYPE_NECK = true, INVTYPE_SHOULDER = true,
    INVTYPE_CLOAK = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
    INVTYPE_WRIST = true, INVTYPE_HAND = true, INVTYPE_WAIST = true,
    INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true, INVTYPE_WEAPON = true, INVTYPE_SHIELD = true,
    INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_HOLDABLE = true,
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true,
}

local function RequestItemData(itemID)
    if not itemID or pendingItemData[itemID] then return end
    pendingItemData[itemID] = true
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
end

function ns.ConsumePendingCatalogItem(itemID)
    if not itemID or not pendingItemData[itemID] then return false end
    pendingItemData[itemID] = nil
    return true
end

local function DungeonKey(id)
    return "dungeon:" .. tostring(id)
end

local function RaidKey(id, difficultyID)
    return "raid:" .. tostring(id) .. ":" .. tostring(difficultyID or 16)
end

ns.DungeonKey = DungeonKey
ns.RaidKey = RaidKey

local function ResolveDungeonJournalIDs()
    if dungeonJournalIDs then return dungeonJournalIDs end
    dungeonJournalIDs = {}
    local wanted = {}
    for _, source in ipairs(ns.DUNGEON_SOURCES) do
        if source.journalInstanceID then
            dungeonJournalIDs[source.instanceID] = source.journalInstanceID
        else
            wanted[source.instanceID] = true
        end
    end
    for index = 1, 300 do
        local journalID, _, _, _, _, _, _, _, _, _, instanceID = EJ_GetInstanceByIndex(index, false)
        if not journalID then break end
        if wanted[instanceID] then dungeonJournalIDs[instanceID] = journalID end
    end
    return dungeonJournalIDs
end

local function ResolveSourceNames()
    local dungeonIDs = ResolveDungeonJournalIDs()
    for _, source in ipairs(ns.DUNGEON_SOURCES) do
        source.kind = "dungeon"
        source.key = DungeonKey(source.challengeModeID)
        source.journalInstanceID = source.journalInstanceID or dungeonIDs[source.instanceID]
        local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(source.challengeModeID)
        if not name and source.journalInstanceID then name = EJ_GetInstanceInfo(source.journalInstanceID) end
        source.name = name or ("Dungeon " .. source.challengeModeID)
        source.texture = texture
        source.coreCost = 1
        sourceByChest[source.chestItemID] = source
        sourceByKey[source.key] = source
    end
    local journal = _G.EncounterJournal
    local oldInstanceID = journal and journal.instanceID
    local oldEncounterID = journal and journal.encounterID
    for _, source in ipairs(ns.RAID_SOURCES) do
        source.kind = "raid"
        -- Midnight Season 2 reduced raid bonus rolls from two Voidcores to one.
        source.coreCost = 1
        sourceByChest[source.chestItemID] = source
        local instanceName = EJ_GetInstanceInfo(source.journalInstanceID)
        source.instanceName = instanceName
        EJ_SelectInstance(source.journalInstanceID)
        for index = 1, 30 do
            local name, _, journalEncounterID, _, _, _, dungeonEncounterID =
                EJ_GetEncounterInfoByIndex(index, source.journalInstanceID)
            if not name then break end
            if dungeonEncounterID == source.encounterID or journalEncounterID == source.encounterID then
                source.name = name
                source.journalEncounterID = journalEncounterID
                break
            end
        end
        source.name = source.name or ("Encounter " .. source.encounterID)
        for _, difficultyID in ipairs(ns.RAID_DIFFICULTIES) do
            sourceByKey[RaidKey(source.encounterID, difficultyID)] = source
        end
    end
    if oldInstanceID then
        EJ_SelectInstance(oldInstanceID)
        if oldEncounterID then EJ_SelectEncounter(oldEncounterID) end
    end
end

local function ResolveSpec(specID)
    if specID and specID > 0 then return specID end
    local lootSpec = GetLootSpecialization and GetLootSpecialization() or 0
    if lootSpec and lootSpec > 0 then return lootSpec end
    local index = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
    if index then return C_SpecializationInfo.GetSpecializationInfo(index) end
    return 0
end

local function BuildCatalog(source, specID, difficultyID)
    ResolveSourceNames()
    specID = ResolveSpec(specID)
    if specID == 0 then return {} end
    difficultyID = source.kind == "raid" and (difficultyID or 16) or DifficultyUtil.ID.DungeonChallenge
    local key = source.kind == "raid" and RaidKey(source.encounterID, difficultyID) or source.key
    catalog[key] = catalog[key] or {}
    local cached = catalog[key][specID]
    if cached and not cached.dirty then return cached.items end
    local previousItems = cached and cached.items

    local items = {}
    if not source.journalInstanceID then
        catalog[key][specID] = { items = items, dirty = false }
        return items
    end

    local classID = select(3, UnitClass("player"))
    local oldDifficulty = EJ_GetDifficulty and EJ_GetDifficulty()
    local oldClassID, oldSpecID
    if EJ_GetLootFilter then oldClassID, oldSpecID = EJ_GetLootFilter() end
    local oldSlotFilter = C_EncounterJournal and C_EncounterJournal.GetSlotFilter
        and C_EncounterJournal.GetSlotFilter()
    local journal = _G.EncounterJournal
    local oldInstanceID = journal and journal.instanceID
    local oldEncounterID = journal and journal.encounterID
    EJ_SelectInstance(source.journalInstanceID)
    EJ_SetDifficulty(difficultyID)
    EJ_SetLootFilter(classID or 0, specID)
    if C_EncounterJournal and C_EncounterJournal.SetSlotFilter then
        C_EncounterJournal.SetSlotFilter(Enum.ItemSlotFilterType.NoFilter)
    end
    if source.kind == "raid" and source.journalEncounterID then
        EJ_SelectEncounter(source.journalEncounterID)
    end

    local lootCount = EJ_GetNumLoot()
    local incomplete = lootCount == 0
    for index = 1, lootCount do
        local info = C_EncounterJournal.GetLootInfoByIndex(index)
        if info and info.itemID then
            local itemID = info.itemID
            local _, _, _, equipLoc, instantIcon = C_Item.GetItemInfoInstant(itemID)
            local name = info.name or C_Item.GetItemNameByID(itemID)
            local link = info.link or select(2, C_Item.GetItemInfo(itemID))
            local slot = info.slot
            local tokenSlot = ns.RAID_TOKEN_SLOTS and ns.RAID_TOKEN_SLOTS[itemID]
            if (not slot or slot == "") and equipLoc and equipLoc ~= "" then
                slot = _G[equipLoc] or equipLoc
            end
            if not slot or slot == "" then
                if tokenSlot == "TIER" then
                    slot = EllesmereUI.L("Tier Token")
                elseif tokenSlot then
                    slot = _G[tokenSlot] or tokenSlot
                end
            end
            if not name or not link then
                incomplete = true
                RequestItemData(itemID)
            end
            local itemLevel
            if C_Item.GetDetailedItemLevelInfo then
                itemLevel = C_Item.GetDetailedItemLevelInfo(link or itemID)
                if issecretvalue and issecretvalue(itemLevel) then itemLevel = nil end
            end
            local isGear = VALID_EQUIP_LOCS[equipLoc] or tokenSlot ~= nil
            if isGear and slot and slot ~= "" then
                items[#items + 1] = {
                    itemID = itemID,
                    name = name or ("Item " .. itemID),
                    link = link,
                    icon = info.icon or instantIcon,
                    slot = slot,
                    itemLevel = itemLevel,
                }
            elseif isGear then
                incomplete = true
                RequestItemData(itemID)
            end
        else
            incomplete = true
        end
    end

    -- Some legacy dungeons return no usable loot rows at Challenge difficulty
    -- even though their current-season pool is valid (notably King's Rest).
    -- Merge the compact seasonal fallback and let Blizzard's spec predicate
    -- select only items eligible for the active class and loot specialization.
    if source.kind == "dungeon" and source.fallbackItems then
        local present = {}
        for _, item in ipairs(items) do present[item.itemID] = true end
        for _, itemID in ipairs(source.fallbackItems) do
            local eligible = true
            if C_Item.DoesItemContainSpec then
                local ok, result = pcall(C_Item.DoesItemContainSpec, itemID, classID or 0, specID)
                if ok and result ~= nil and not (issecretvalue and issecretvalue(result)) then eligible = result end
            end
            if eligible and not present[itemID] then
                local _, _, _, equipLoc, icon = C_Item.GetItemInfoInstant(itemID)
                local name = C_Item.GetItemNameByID(itemID)
                local link = select(2, C_Item.GetItemInfo(itemID))
                local slot = equipLoc and equipLoc ~= "" and (_G[equipLoc] or equipLoc)
                local isGear = VALID_EQUIP_LOCS[equipLoc]
                if isGear and slot then
                    items[#items + 1] = {
                        itemID = itemID,
                        name = name or ("Item " .. itemID),
                        link = link,
                        icon = icon,
                        slot = slot,
                    }
                    present[itemID] = true
                elseif isGear then
                    incomplete = true
                end
                if isGear and (not name or not link or not slot) then
                    incomplete = true
                    RequestItemData(itemID)
                end
            end
        end
    end

    if oldClassID then EJ_SetLootFilter(oldClassID, oldSpecID or 0) else EJ_ResetLootFilter() end
    if oldSlotFilter and C_EncounterJournal and C_EncounterJournal.SetSlotFilter then
        C_EncounterJournal.SetSlotFilter(oldSlotFilter)
    end
    if oldDifficulty and oldDifficulty > 0 then EJ_SetDifficulty(oldDifficulty) end
    if oldInstanceID then
        EJ_SelectInstance(oldInstanceID)
        if oldEncounterID then EJ_SelectEncounter(oldEncounterID) end
    end
    -- Encounter Journal selection and item data settle asynchronously. Preserve
    -- the last usable result while a refresh is incomplete, and cache partial
    -- non-empty results so a second request during the same page build cannot
    -- replace them with an empty list. Data events mark entries dirty again.
    if incomplete and previousItems then
        local present = {}
        for _, item in ipairs(items) do present[item.itemID] = true end
        for _, item in ipairs(previousItems) do
            if not present[item.itemID] then items[#items + 1] = item end
        end
    end
    if #items > 0 then
        table.sort(items, function(a, b)
            if a.slot == b.slot then return (a.name or "") < (b.name or "") end
            return (a.slot or "") < (b.slot or "")
        end)
        catalog[key][specID] = { items = items, dirty = false }
        return items
    end
    if cached then
        cached.dirty = false
        return previousItems or {}
    end
    return items
end

function ns.GetSources(kind)
    ResolveSourceNames()
    return kind == "raid" and ns.RAID_SOURCES or ns.DUNGEON_SOURCES
end

function ns.GetSourceByChest(itemID)
    ResolveSourceNames()
    return sourceByChest[itemID]
end

function ns.GetSourceByKey(key)
    ResolveSourceNames()
    return sourceByKey[key]
end

function ns.GetCatalog(source, specID, difficultyID)
    return BuildCatalog(source, specID, difficultyID)
end

function ns.InvalidateCatalog()
    for _, specs in pairs(catalog) do
        for _, entry in pairs(specs) do entry.dirty = true end
    end
    dungeonJournalIDs = nil
end

function ns.GetMPlusTargetLevel(keyLevel)
    keyLevel = math.max(2, math.min(10, tonumber(keyLevel) or 10))
    return ns.MPLUS_TARGET_LEVELS[keyLevel]
end

local function GetItemLevelBonusID(levelDifference)
    if levelDifference == 0 then return nil end
    if levelDifference >= -100 and levelDifference <= 200 then
        return 1472 + levelDifference
    end
    if levelDifference >= 201 and levelDifference <= 400 then
        return 2929 + levelDifference
    end
end

function ns.GetTargetItemLink(itemID, specID, targetLevel, sourceKind, difficultyID, keyLevel)
    targetLevel = tonumber(targetLevel)
    if not itemID or not targetLevel or not C_Item.GetDetailedItemLevelInfo then return nil end
    local _, _, _, equipLoc, _, itemClassID = C_Item.GetItemInfoInstant(itemID)
    if not equipLoc or equipLoc == "" then return nil end
    if Enum and Enum.ItemClass and itemClassID
        and itemClassID ~= Enum.ItemClass.Armor and itemClassID ~= Enum.ItemClass.Weapon then return nil end

    local _, _, baseItemLevel = C_Item.GetDetailedItemLevelInfo(itemID)
    if issecretvalue and issecretvalue(baseItemLevel) then return nil end
    baseItemLevel = tonumber(baseItemLevel)
    if not baseItemLevel then return nil end

    local trackBonusID
    if sourceKind == "dungeon" then
        keyLevel = math.max(2, math.min(10, tonumber(keyLevel) or 10))
        trackBonusID = ns.MPLUS_TARGET_BONUS_IDS[keyLevel]
    else
        local difficultyBonuses = ns.RAID_TARGET_BONUS_IDS[difficultyID or 16]
        trackBonusID = difficultyBonuses and difficultyBonuses[targetLevel]
    end
    if not trackBonusID then return nil end

    local bonusIDs = {}
    local levelBonusID = GetItemLevelBonusID(targetLevel - baseItemLevel)
    if levelBonusID then bonusIDs[#bonusIDs + 1] = levelBonusID end
    bonusIDs[#bonusIDs + 1] = trackBonusID
    bonusIDs[#bonusIDs + 1] = 1674
    if equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_NECK" then
        bonusIDs[#bonusIDs + 1] = 13534
    end
    return string.format("item:%d:%s:::%d:%d:::%d:%s", itemID, "::::",
        UnitLevel("player"), ResolveSpec(specID), #bonusIDs, table.concat(bonusIDs, ":"))
end

function ns.GetRaidTargetLevel(source, specID, difficultyID, itemID)
    for _, item in ipairs(BuildCatalog(source, specID, difficultyID)) do
        if item.itemID == itemID and item.itemLevel then return item.itemLevel end
    end
    return ns.RAID_TARGET_LEVELS[difficultyID or 16]
end

-- Returns a name set from the authoritative "remaining items" block on a
-- Voidcache tooltip. An empty set is treated as unavailable, never as an empty
-- loot pool, so cache misses cannot erase progress.
function ns.ReadRemainingNames(chestItemID)
    if not C_TooltipInfo or not C_TooltipInfo.GetItemByID then return nil end
    local data = C_TooltipInfo.GetItemByID(chestItemID)
    if not data or not data.lines then return nil end
    local names = {}
    for index = #data.lines, 1, -1 do
        local text = data.lines[index].leftText
        if type(text) == "string" then
            local name = text:match("^%s*%-%s*(.+)$")
            if name then
                names[name] = true
            elseif next(names) then
                break
            end
        elseif next(names) then
            break
        end
    end
    return next(names) and names or nil
end
