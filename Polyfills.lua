--------------------------------------------------------------------------------
--  Polyfills.lua
--  Central polyfill and compatibility layer for World of Warcraft 3.3.5a (WotLK)
--  Bridges modern Retail APIs into the legacy 3.3.5 client environment.
--------------------------------------------------------------------------------

local _G = _G or getfenv(0)

-- Safe initial initialization of EllesmereUI global namespace and deferred inits list
_G.EllesmereUI = _G.EllesmereUI or {}
_G.EllesmereUI._deferredInits = _G.EllesmereUI._deferredInits or {}

-- 1. Mixin & Object Orientation Shims
if not Mixin then
    function Mixin(target, ...)
        for i = 1, select("#", ...) do
            local source = select(i, ...)
            if source then
                for k, v in pairs(source) do
                    target[k] = v
                end
            end
        end
        return target
    end
end

if not CreateFromMixins then
    function CreateFromMixins(...)
        return Mixin({}, ...)
    end
end

-- 2. C_Timer Polyfill with OnUpdate Accumulator Pool
if not C_Timer then
    C_Timer = {}
    local timers = {}
    local tickerId = 0
    local timerFrame = CreateFrame("Frame")

    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        local now = GetTime()
        for id, t in pairs(timers) do
            if not t.cancelled then
                if now >= t.nextTrigger then
                    if t.isTicker then
                        t.iterations = t.iterations + 1
                        t.nextTrigger = t.nextTrigger + t.duration
                        if t.nextTrigger < now then
                            t.nextTrigger = now + t.duration
                        end
                        local success, err = pcall(t.callback, t)
                        if not success then
                            geterrorhandler()(err)
                        end
                        if t.cancelled then
                            timers[id] = nil
                        elseif t.maxIterations and t.iterations >= t.maxIterations then
                            t.cancelled = true
                            timers[id] = nil
                        end
                    else
                        t.cancelled = true
                        timers[id] = nil
                        local success, err = pcall(t.callback, t)
                        if not success then
                            geterrorhandler()(err)
                        end
                    end
                end
            else
                timers[id] = nil
            end
        end
        if not next(timers) then
            self:Hide()
        end
    end)
    timerFrame:Hide()

    local function createTimer(duration, callback, isTicker, maxIterations)
        tickerId = tickerId + 1
        local id = tickerId
        local t = {
            id = id,
            duration = duration,
            callback = callback,
            isTicker = isTicker,
            iterations = 0,
            maxIterations = maxIterations,
            nextTrigger = GetTime() + duration,
            cancelled = false,
        }
        function t:Cancel()
            self.cancelled = true
            timers[id] = nil
        end
        timers[id] = t
        timerFrame:Show()
        return t
    end

    function C_Timer.After(duration, callback)
        createTimer(duration, callback, false)
    end

    function C_Timer.NewTimer(duration, callback)
        return createTimer(duration, callback, false)
    end

    function C_Timer.NewTicker(duration, callback, iterations)
        return createTimer(duration, callback, true, iterations)
    end
end

-- 3. Dynamic Fallback Proxies for Undefined Namespaces
local fallbackMeta = {
    __index = function(t, k)
        local f = function(...)
            return nil
        end
        rawset(t, k, f)
        return f
    end
}

local namespaces = {
    "C_AddOns", "C_ChallengeMode", "C_ClassColor", "C_ClassTalents",
    "C_CooldownViewer", "C_CurveUtil", "C_DurationUtil", "C_EditMode",
    "C_EncodingUtil", "C_EventUtils", "C_Garrison", "C_IncomingSummon",
    "C_PartyInfo", "C_PlayerInfo", "C_PvP", "C_SpecializationInfo",
    "C_StringUtil", "C_Traits", "C_UnitAuras", "C_UA", "C_AddOnProfiler",
    "C_PlayerInteractionManager"
}

for _, nsName in ipairs(namespaces) do
    if not _G[nsName] then
        _G[nsName] = setmetatable({}, fallbackMeta)
    end
end

-- DurationObject class
local DurationObject = {}
DurationObject.__index = DurationObject

function DurationObject:Create(startTime, duration, expirationTime)
    local obj = setmetatable({}, self)
    obj.startTime = startTime or 0
    obj.duration = duration or 0
    obj.expirationTime = expirationTime or 0
    return obj
end

function DurationObject:IsZero()
    if self.duration == 0 then
        return true
    end
    local now = GetTime()
    if self.expirationTime > 0 then
        return now >= self.expirationTime
    end
    if self.startTime > 0 then
        return now >= (self.startTime + self.duration)
    end
    return false
end

-- AuraUtil Namespace fallback
if not AuraUtil then
    AuraUtil = {
        AuraFilters = {
            CrowdControl = "CROWD_CONTROL"
        }
    }
end

-- C_ActionBar Namespace
C_ActionBar = C_ActionBar or {}

C_ActionBar.GetActionCooldown = function(action)
    local start, duration, enable = GetActionCooldown(action)
    start = start or 0
    duration = duration or 0
    local isActive = (start > 0 and duration > 0)
    local isOnGCD = false
    if isActive and duration > 0 and duration <= 1.5 then
        isOnGCD = true
    end
    return {
        startTime = start,
        duration = duration,
        enable = enable,
        isActive = isActive,
        isOnGCD = isOnGCD,
    }
end

C_ActionBar.GetActionCooldownDuration = function(action)
    local start, duration = GetActionCooldown(action)
    start = start or 0
    duration = duration or 0
    return DurationObject:Create(start, duration, start + duration)
end

C_ActionBar.GetActionCharges = function(action)
    return {
        currentCharges = 0,
        maxCharges = 0,
        cooldownStart = 0,
        cooldownDuration = 0,
    }
end

C_ActionBar.GetActionChargeDuration = function(action)
    return DurationObject:Create(0, 0, 0)
end

C_ActionBar.IsUsableAction = function(action)
    local isUsable, noMana = IsUsableAction(action)
    return isUsable, noMana
end

C_ActionBar.UsesActionText = function(action)
    local actionType, id = GetActionInfo(action)
    return actionType == "macro"
end

C_ActionBar.GetActionText = function(action)
    return GetActionText(action)
end

C_ActionBar.GetActionDisplayCount = function(action)
    return GetActionCount(action)
end

C_ActionBar.IsAssistedCombatAction = function(action)
    return false
end

C_ActionBar.EnableActionRangeCheck = function(slot, enable)
    -- No-op fallback
end

C_ActionBar.GetActionBarPage = function()
    return CURRENT_ACTIONBAR_PAGE or 1
end

-- 4. Specific Namespace Implementations

-- C_AddOns
C_AddOns.DisableAddOn = DisableAddOn
C_AddOns.EnableAddOn = EnableAddOn
C_AddOns.IsAddOnLoaded = IsAddOnLoaded
C_AddOns.GetAddOnEnableState = function(name, character)
    local enabled = select(4, GetAddOnInfo(name))
    return enabled and 2 or 0
end
C_AddOns.DoesAddOnExist = function(name)
    return GetAddOnInfo(name) ~= nil
end

-- C_ClassColor
C_ClassColor.GetClassColor = function(class)
    local color = RAID_CLASS_COLORS[class]
    if color then
        return CreateColor(color.r, color.g, color.b)
    end
    return CreateColor(1, 1, 1)
end

-- C_SpecializationInfo
C_SpecializationInfo.GetSpecialization = function()
    local maxPoints = -1
    local activeSpec = 1
    for i = 1, 3 do
        local _, _, pointsSpent = GetTalentTabInfo(i)
        if pointsSpent and pointsSpent > maxPoints then
            maxPoints = pointsSpent
            activeSpec = i
        end
    end
    return activeSpec
end

C_SpecializationInfo.GetSpecializationInfo = function(specIndex)
    local _, class = UnitClass("player")
    local name, icon, pointsSpent = GetTalentTabInfo(specIndex or 1)
    return specIndex, name or "Spec", "", icon or "Interface\\Icons\\INV_Misc_QuestionMark", "DAMAGER", 1
end

-- C_UnitAuras & C_UA
local function PackAuraData(name, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId)
    if name then
        return {
            name = name,
            icon = icon,
            applications = count,
            dispelType = dispelType,
            duration = duration,
            expirationTime = expirationTime,
            sourceUnit = source,
            isStealable = isStealable == 1 or isStealable == true,
            nameplateShowPersonal = nameplateShowPersonal == 1 or nameplateShowPersonal == true,
            spellId = spellId,
            auraInstanceID = spellId or name or 0,
            castByPlayer = (source == "player")
        }
    end
    return nil
end

C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
    return PackAuraData(UnitAura(unit, index, filter))
end

C_UnitAuras.GetPlayerAuraBySpellID = function(spellID)
    local nameToFind = GetSpellInfo(spellID)
    if not nameToFind then return nil end
    for i = 1, 40 do
        local name, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitAura("player", i)
        if not name then break end
        if name == nameToFind or spellId == spellID then
            return PackAuraData(name, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId)
        end
    end
    for i = 1, 40 do
        local name, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitAura("player", i, "HARMFUL")
        if not name then break end
        if name == nameToFind or spellId == spellID then
            return PackAuraData(name, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId)
        end
    end
    return nil
end

C_UnitAuras.GetAuraDataByAuraInstanceID = function(unit, iid)
    if not unit or not iid then return nil end
    for i = 1, 40 do
        local name, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitAura(unit, i, "HELPFUL")
        if not name then break end
        if spellId == iid then
            return PackAuraData(name, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId)
        end
    end
    for i = 1, 40 do
        local name, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitAura(unit, i, "HARMFUL")
        if not name then break end
        if spellId == iid then
            return PackAuraData(name, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId)
        end
    end
    return nil
end

C_UnitAuras.GetAuraDataBySpellName = function(unit, name, filter)
    if not unit or not name then return nil end
    local scanFilters = {"HELPFUL", "HARMFUL"}
    if filter then
        if string.find(filter, "HELPFUL") then
            scanFilters = {"HELPFUL"}
        elseif string.find(filter, "HARMFUL") then
            scanFilters = {"HARMFUL"}
        end
    end
    for _, f in ipairs(scanFilters) do
        for i = 1, 40 do
            local auraName, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId = UnitAura(unit, i, f)
            if not auraName then break end
            if auraName == name then
                return PackAuraData(auraName, rank, icon, count, dispelType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellId)
            end
        end
    end
    return nil
end

C_UnitAuras.IsAuraFilteredOutByInstanceID = function(unit, iid, filter)
    return false
end

C_UnitAuras.GetAuraDuration = function(unit, iid)
    if not unit or not iid then return nil end
    local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, iid)
    if aura then
        local duration = aura.duration or 0
        local expirationTime = aura.expirationTime or 0
        return DurationObject:Create(expirationTime - duration, duration, expirationTime)
    end
    return nil
end

C_UnitAuras.GetAuraDispelTypeColor = function(unitOrDispelType, iid, curve)
    local dispelType
    if type(unitOrDispelType) == "string" and not iid then
        dispelType = unitOrDispelType
    elseif unitOrDispelType and iid then
        local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unitOrDispelType, iid)
        dispelType = aura and aura.dispelType
    end
    local color = dispelType and DebuffTypeColor[dispelType]
    if color then
        return CreateColor(color.r, color.g, color.b)
    end
    return CreateColor(1, 1, 1)
end

C_UA.GetAuraDataByIndex = C_UnitAuras.GetAuraDataByIndex
C_UA.GetPlayerAuraBySpellID = C_UnitAuras.GetPlayerAuraBySpellID
C_UA.GetAuraDataByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID
C_UA.GetAuraDataBySpellName = C_UnitAuras.GetAuraDataBySpellName
C_UA.IsAuraFilteredOutByInstanceID = C_UnitAuras.IsAuraFilteredOutByInstanceID
C_UA.GetAuraDuration = C_UnitAuras.GetAuraDuration
C_UA.GetAuraDispelTypeColor = C_UnitAuras.GetAuraDispelTypeColor

C_UA.GetAuraSlots = function(unit, filter)
    local slots = {}
    for i = 1, 40 do
        local name = UnitAura(unit, i, filter)
        if not name then break end
        slots[#slots + 1] = i
    end
    return slots
end
C_UA.GetAuraDataBySlot = function(unit, slot)
    return PackAuraData(UnitAura(unit, slot))
end

-- C_Item
if not C_Item then
    C_Item = {}

    C_Item.GetItemInfo = function(item)
        return GetItemInfo(item)
    end

    C_Item.GetItemCount = function(item, includeBank, includeReagentBank)
        return GetItemCount(item, includeBank)
    end

    C_Item.GetItemIconByID = function(itemID)
        if not itemID then return nil end
        local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID)
        return itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    C_Item.GetItemSpell = function(item)
        return GetItemSpell(item)
    end

    C_Item.GetItemQualityByID = function(itemLink)
        if not itemLink then return nil end
        return select(3, GetItemInfo(itemLink))
    end

    C_Item.GetItemQualityColor = function(rarity)
        return GetItemQualityColor(rarity)
    end

    C_Item.GetItemStats = function(itemLink)
        if not itemLink then return nil end
        return GetItemStats(itemLink)
    end

    C_Item.GetItemGem = function(itemLink, index)
        if type(itemLink) ~= "string" or not index then return nil end
        local parts = { itemLink:match("item:(%d*):(%d*):(%d*):(%d*):(%d*):(%d*)") }
        local gemID = tonumber(parts[2 + index])
        if gemID and gemID > 0 then
            local gemLink = select(2, GetItemInfo(gemID))
            return nil, gemLink
        end
        return nil
    end

    C_Item.RequestLoadItemDataByID = function(itemID)
        -- No-op fallback
    end

    C_Item.GetItemMaxStackSizeByID = function(itemID)
        if not itemID then return 1 end
        return select(8, GetItemInfo(itemID)) or 1
    end

    C_Item.GetDetailedItemLevelInfo = function(itemLink)
        if not itemLink then return 0 end
        return select(4, GetItemInfo(itemLink)) or 0
    end

    C_Item.GetItemInfoInstant = function(item)
        if not item then return nil end
        local name, link, rarity, level, minLevel, type, subType, stackCount, equipLoc, texture, price, classID, subclassID = GetItemInfo(item)
        local itemID = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
        return itemID, type, subType, equipLoc, texture, classID, subclassID
    end

    C_Item.DoesItemExist = function(loc)
        if not loc then return false end
        if loc:IsBagAndSlot() then
            local bag, slot = loc:GetBagAndSlot()
            return GetContainerItemLink(bag, slot) ~= nil
        elseif loc:IsEquipmentSlot() then
            local eqSlot = loc:GetEquipmentSlot()
            return GetInventoryItemLink("player", eqSlot) ~= nil
        end
        return false
    end

    C_Item.GetCurrentItemLevel = function(loc)
        if not loc then return 0 end
        local link
        if loc:IsBagAndSlot() then
            local bag, slot = loc:GetBagAndSlot()
            link = GetContainerItemLink(bag, slot)
        elseif loc:IsEquipmentSlot() then
            local eqSlot = loc:GetEquipmentSlot()
            link = GetInventoryItemLink("player", eqSlot)
        end
        if link then
            return select(4, GetItemInfo(link)) or 0
        end
        return 0
    end

    C_Item.IsLocked = function(loc)
        if not loc then return false end
        if loc:IsBagAndSlot() then
            local bag, slot = loc:GetBagAndSlot()
            return select(3, GetContainerItemInfo(bag, slot)) == true
        elseif loc:IsEquipmentSlot() then
            local eqSlot = loc:GetEquipmentSlot()
            return IsInventoryItemLocked(eqSlot) == true
        end
        return false
    end

    C_Item.IsBoundToAccountUntilEquip = function(loc)
        return false
    end
end

-- Tooltip Scanner for isBound (Soulbound) checking
local tooltipScanner
local function IsItemBound(bag, slot)
    if not tooltipScanner then
        tooltipScanner = CreateFrame("GameTooltip", "EllesmereUITooltipScanner", nil, "GameTooltipTemplate")
        tooltipScanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    tooltipScanner:ClearLines()
    tooltipScanner:SetBagItem(bag, slot)
    for i = 1, tooltipScanner:NumLines() do
        local fontStr = _G["EllesmereUITooltipScannerTextLeft" .. i]
        local text = fontStr and fontStr:GetText()
        if text == ITEM_SOULBOUND then
            return true
        end
    end
    return false
end

-- C_Container
if not C_Container then
    C_Container = {}

    C_Container.GetContainerNumSlots = function(bag)
        return GetContainerNumSlots(bag)
    end

    C_Container.GetContainerItemInfo = function(bag, slot)
        local texture, itemCount, locked, quality, readable, lootable, itemLink = GetContainerItemInfo(bag, slot)
        if texture then
            local itemID = itemLink and tonumber(itemLink:match("item:(%d+)"))
            return {
                iconFileID = texture,
                stackCount = itemCount,
                isLocked = locked == 1 or locked == true,
                quality = quality,
                isReadable = readable == 1 or readable == true,
                itemLink = itemLink,
                itemID = itemID,
                isFiltered = false,
                hasNoValue = false,
                isBound = IsItemBound(bag, slot)
            }
        end
        return nil
    end

    C_Container.GetContainerItemLink = function(bag, slot)
        return GetContainerItemLink(bag, slot)
    end

    C_Container.GetContainerItemCooldown = function(bag, slot)
        return GetContainerItemCooldown(bag, slot)
    end

    C_Container.PickupContainerItem = function(bag, slot)
        return PickupContainerItem(bag, slot)
    end

    C_Container.ContainerIDToInventoryID = function(bag)
        return ContainerIDToInventoryID(bag)
    end

    C_Container.GetContainerNumFreeSlots = function(bag)
        return GetContainerNumFreeSlots(bag)
    end

    C_Container.SetItemSearch = function(text)
        -- No-op fallback
    end

    C_Container.SortBags = function()
        -- No-op fallback
    end

    C_Container.SortBank = function()
        -- No-op fallback
    end

    C_Container.GetContainerItemQuestInfo = function(bag, slot)
        local isQuestItem, questId, isActive = GetContainerItemQuestInfo(bag, slot)
        if isQuestItem or questId then
            return {
                isQuestItem = isQuestItem == 1 or isQuestItem == true,
                questID = questId,
                isActive = isActive == 1 or isActive == true,
            }
        end
        return nil
    end
end

-- C_Spell
if not C_Spell then
    C_Spell = {}

    C_Spell.GetSpellInfo = function(spell)
        local name, rank, icon, castTime, minRange, maxRange, spellID = GetSpellInfo(spell)
        if name then
            return {
                name = name,
                iconID = icon,
                originalIconID = icon,
                castTime = castTime,
                minRange = minRange,
                maxRange = maxRange,
                spellID = spellID or (type(spell) == "number" and spell) or nil
            }
        end
        return nil
    end

    C_Spell.GetSpellCooldown = function(spell)
        return GetSpellCooldown(spell)
    end

    C_Spell.GetSpellCooldownDuration = function(spell)
        local start, duration = GetSpellCooldown(spell)
        start = start or 0
        duration = duration or 0
        return DurationObject:Create(start, duration, start + duration)
    end

    C_Spell.IsSpellPassive = function(spellID)
        if IsPassiveSpell then
            return IsPassiveSpell(spellID) == true
        end
        return false
    end

    C_Spell.GetSpellName = function(spell)
        return select(1, GetSpellInfo(spell))
    end

    C_Spell.GetSpellTexture = function(spell)
        return select(3, GetSpellInfo(spell))
    end

    C_Spell.GetSpellDescription = function(spell)
        if GetSpellDescription then
            return GetSpellDescription(spell)
        end
        return ""
    end

    C_Spell.IsSpellInRange = function(spell, unit)
        if IsSpellInRange then
            return IsSpellInRange(spell, unit)
        end
        return nil
    end

    C_Spell.GetSpellCastCount = function(spell)
        return 0
    end

    C_Spell.GetSpellCharges = function(spell)
        return {
            currentCharges = 0,
            maxCharges = 0,
            cooldownStart = 0,
            cooldownDuration = 0
        }
    end
end

-- C_SpellBook
if not C_SpellBook then
    C_SpellBook = {}

    C_SpellBook.GetNumSpellBookSkillLines = function()
        if GetNumSpellTabs then
            return GetNumSpellTabs()
        end
        return 0
    end

    C_SpellBook.GetSpellBookSkillLineInfo = function(tab)
        if GetSpellTabInfo then
            local name, texture, offset, numSpells, isGuild, offSpecID = GetSpellTabInfo(tab)
            if name then
                return {
                    name = name,
                    icon = texture,
                    itemIndexOffset = offset,
                    numSpellBookItems = numSpells,
                    isGuild = isGuild,
                    offSpecID = offSpecID,
                }
            end
        end
        return nil
    end

    C_SpellBook.GetSpellBookItemType = function(index, bank)
        local bookType = "spell"
        if bank == "pet" or bank == 2 then
            bookType = "pet"
        end
        local spellType, id = GetSpellBookItemType(index, bookType)
        return spellType, id, id
    end

    C_SpellBook.IsSpellInSpellBook = function(spell, bank)
        local name = GetSpellInfo(spell)
        if name then
            return GetSpellLink(name) ~= nil
        end
        return false
    end

    C_SpellBook.IsSpellKnownOrInSpellBook = function(spellId, bank)
        local name = GetSpellInfo(spellId)
        if name then
            return GetSpellLink(name) ~= nil
        end
        return false
    end

    C_SpellBook.IsSpellKnown = function(spell)
        local name = GetSpellInfo(spell)
        if name then
            return GetSpellLink(name) ~= nil
        end
        return false
    end

    C_SpellBook.FindSpellOverrideByID = function(spell)
        return spell
    end
end

-- Load Equipment Set Module immediately if present
if not EquipmentManager_GetLocationData then
    pcall(LoadAddOn, "Blizzard_EquipmentManager")
end

-- C_EquipmentSet
if not C_EquipmentSet then
    C_EquipmentSet = {}

    C_EquipmentSet.GetEquipmentSetIDs = function()
        local num = GetNumEquipmentSets and GetNumEquipmentSets() or 0
        local ids = {}
        for i = 1, num do
            ids[i] = i
        end
        return ids
    end

    C_EquipmentSet.GetItemLocations = function(setID)
        local num = GetNumEquipmentSets and GetNumEquipmentSets() or 0
        if setID > 0 and setID <= num then
            local name = GetEquipmentSetInfo(setID)
            if name then
                local locations = GetEquipmentSetLocations(name)
                local list = {}
                if locations then
                    for slot, loc in pairs(locations) do
                        list[#list + 1] = loc
                    end
                end
                return list
            end
        end
        return nil
    end
end

-- C_Map
if not C_Map then
    C_Map = {}

    C_Map.GetBestMapForUnit = function(unit)
        if GetCurrentMapAreaID then
            return GetCurrentMapAreaID()
        end
        return 0
    end

    C_Map.GetPlayerMapPosition = function(mapID, unit)
        if GetPlayerMapPosition then
            local x, y = GetPlayerMapPosition(unit or "player")
            if x and y then
                return {
                    GetXY = function()
                        return x, y
                    end
                }
            end
        end
        return nil
    end

    C_Map.GetMapInfo = function(mapID)
        local continentIdx = GetCurrentMapContinent and GetCurrentMapContinent() or 0
        local continents = { GetMapContinents() }
        local continentName = continents[continentIdx] or "Northrend"

        if mapID == 9999 then
            return {
                name = continentName,
                mapType = 2, -- Continent
                parentMapID = 0
            }
        else
            return {
                name = GetRealZoneText() or GetZoneText() or "Unknown Zone",
                mapType = 3, -- Zone
                parentMapID = 9999
            }
        end
    end
end

if not GetPhysicalScreenSize then
    function GetPhysicalScreenSize()
        local resIndex = GetCurrentResolution()
        local resString = resIndex and select(resIndex, GetScreenResolutions())
        if resString then
            local w, h = string.match(resString, "(%d+)x(%d+)")
            if w and h then
                return tonumber(w), tonumber(h)
            end
        end
        local w = UIParent:GetWidth() or 1920
        local h = UIParent:GetHeight() or 1080
        return w, h
    end
end

-- C_QuestLog
if not C_QuestLog then
    C_QuestLog = {}

    C_QuestLog.GetNumQuestLogEntries = function()
        return GetNumQuestLogEntries()
    end

    C_QuestLog.GetLogIndexForQuestID = function(questID)
        local num = GetNumQuestLogEntries()
        for i = 1, num do
            local _, _, _, _, _, _, _, _, qID = GetQuestLogTitle(i)
            if qID == questID then
                return i
            end
        end
        return nil
    end

    C_QuestLog.IsOnQuest = function(questID)
        return C_QuestLog.GetLogIndexForQuestID(questID) ~= nil
    end

    C_QuestLog.GetInfo = function(index)
        local title, level, questTag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, questID, startEvent = GetQuestLogTitle(index)
        if title then
            local complete = (isComplete == 1 or isComplete == true)
            return {
                title = title,
                level = level,
                questClassification = questTag,
                frequency = isDaily and 1 or 0,
                isHeader = isHeader,
                isCollapsed = isCollapsed,
                isComplete = complete,
                questID = questID,
            }
        end
        return nil
    end

    C_QuestLog.IsComplete = function(questID)
        local idx = C_QuestLog.GetLogIndexForQuestID(questID)
        if idx then
            local info = C_QuestLog.GetInfo(idx)
            return info and info.isComplete or false
        end
        return false
    end

    C_QuestLog.GetQuestWatchType = function(questID)
        return 0
    end
end

-- C_PlayerInteractionManager
if not C_PlayerInteractionManager then
    C_PlayerInteractionManager = {
        IsInteractingWithNpcOfType = function(type)
            return false
        end
    }
end

-- C_AddOnProfiler
if not C_AddOnProfiler then
    C_AddOnProfiler = {
        GetAddOnMetric = function() return 0 end,
    }
end

-- 4. Global Objects & Structures (Enum, Color, TooltipDataProcessor)

-- ItemLocation Object Mock
if not ItemLocation then
    ItemLocation = {}
    ItemLocation.__index = ItemLocation

    function ItemLocation:CreateFromBagAndSlot(bag, slot)
        local obj = setmetatable({}, self)
        obj.bag = bag
        obj.slot = slot
        return obj
    end

    function ItemLocation:CreateFromEquipmentSlot(slotID)
        local obj = setmetatable({}, self)
        obj.equipmentSlot = slotID
        return obj
    end

    function ItemLocation:IsValid()
        return true
    end

    function ItemLocation:GetBagAndSlot()
        return self.bag, self.slot
    end

    function ItemLocation:GetEquipmentSlot()
        return self.equipmentSlot
    end

    function ItemLocation:IsEquipmentSlot()
        return self.equipmentSlot ~= nil
    end

    function ItemLocation:IsBagAndSlot()
        return self.bag ~= nil and self.slot ~= nil
    end
end

-- ColorMixin & CreateColor
if not ColorMixin then
    ColorMixin = {}
    ColorMixin.__index = ColorMixin

    function ColorMixin:SetRGBA(r, g, b, a)
        self.r = r
        self.g = g
        self.b = b
        self.a = a or 1
    end

    function ColorMixin:GetRGB()
        return self.r, self.g, self.b
    end

    function ColorMixin:GetRGBA()
        return self.r, self.g, self.b, self.a
    end

    function ColorMixin:GenerateHexColor()
        local r = math.floor(self.r * 255 + 0.5)
        local g = math.floor(self.g * 255 + 0.5)
        local b = math.floor(self.b * 255 + 0.5)
        local a = math.floor((self.a or 1) * 255 + 0.5)
        return string.format("%.2x%.2x%.2x%.2x", a, r, g, b)
    end
end

if not CreateColor then
    function CreateColor(r, g, b, a)
        local color = setmetatable({}, ColorMixin)
        color:SetRGBA(r or 1, g or 1, b or 1, a or 1)
        return color
    end
end

-- Enum Namespace and catch-all safety
if not Enum then
    local emptyTable = {}
    local enumMeta = {
        __index = function(t, k)
            return 0
        end
    }
    local enumGroupMeta = {
        __index = function(t, k)
            local sub = setmetatable({}, enumMeta)
            rawset(t, k, sub)
            return sub
        end
    }
    Enum = setmetatable({}, enumGroupMeta)
end

-- Explicitly populate Enum subfields used in the codebase
Enum.ItemClass = {
    Weapon = 2,
    Armor = 4,
    Gem = 3,
    Container = 1,
    Consumable = 0,
    Glyph = 16,
    TradeGoods = 7,
    Projectile = 6,
    Quiver = 11,
    Recipe = 9,
    Reagent = 5,
    Key = 13,
    Miscellaneous = 15,
    Quest = 12,
    Profession = 19,
    Housing = 20,
}

Enum.ItemBind = {
    None = 0,
    OnAcquire = 1,
    OnEquip = 2,
}

Enum.SpellBookSpellBank = {
    Player = "spell",
    Pet = "pet",
}

Enum.SpellBookItemType = {
    Spell = "SPELL",
    FutureSpell = "FUTURESPELL",
    PetAction = "PETACTION",
    Flyout = "FLYOUT",
}

Enum.BankType = {
    Character = 1,
    Account = 2,
}

Enum.BagSlotFlags = {
    ClassEquipment = 1,
    ClassConsumables = 2,
    ClassProfessionGoods = 3,
    ClassReagents = 4,
    ClassJunk = 5,
}

Enum.QuestClassification = {
    Normal = 0,
    Elite = 1,
    Rare = 2,
    RareElite = 3,
    WorldQuest = 4,
}

Enum.TooltipDataType = {
    Spell = 1,
    UnitAura = 2,
    Item = 3,
    Macro = 4,
    PetAction = 5,
}

Enum.PowerType = {
    Mana = 0,
    Rage = 1,
    Focus = 2,
    Energy = 3,
    RunicPower = 6,
}

-- TooltipDataProcessor Polyfill
if not TooltipDataProcessor then
    TooltipDataProcessor = {}
    local tooltipCallbacks = {}

    TooltipDataProcessor.AddTooltipPostCall = function(dataType, callback)
        if not tooltipCallbacks[dataType] then
            tooltipCallbacks[dataType] = {}
        end
        table.insert(tooltipCallbacks[dataType], callback)
    end

    local function OnTooltipSetSpell(self)
        if not self.GetSpell then return end
        local name, rank, id = self:GetSpell()
        if id and tooltipCallbacks[Enum.TooltipDataType.Spell] then
            local tooltipData = { id = id }
            for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.Spell]) do
                pcall(cb, self, tooltipData)
            end
        end
    end

    local function OnTooltipSetItem(self)
        if not self.GetItem then return end
        local name, link = self:GetItem()
        if link then
            local id = tonumber(link:match("item:(%d+)"))
            if id and tooltipCallbacks[Enum.TooltipDataType.Item] then
                local tooltipData = { id = id }
                for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.Item]) do
                    pcall(cb, self, tooltipData)
                end
            end
        end
    end

    if GameTooltip then
        GameTooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell)
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell)
        ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
    end

    local originalSetUnitAura = GameTooltip.SetUnitAura
    if originalSetUnitAura then
        GameTooltip.SetUnitAura = function(self, unit, index, filter)
            local result = originalSetUnitAura(self, unit, index, filter)
            if tooltipCallbacks[Enum.TooltipDataType.UnitAura] then
                local _, _, _, _, _, _, _, _, _, _, spellID = UnitAura(unit, index, filter)
                if spellID then
                    local tooltipData = { id = spellID }
                    for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.UnitAura]) do
                        pcall(cb, self, tooltipData)
                    end
                end
            end
            return result
        end
    end

    local originalSetUnitBuff = GameTooltip.SetUnitBuff
    if originalSetUnitBuff then
        GameTooltip.SetUnitBuff = function(self, unit, index)
            local result = originalSetUnitBuff(self, unit, index)
            if tooltipCallbacks[Enum.TooltipDataType.UnitAura] then
                local _, _, _, _, _, _, _, _, _, _, spellID = UnitBuff(unit, index)
                if spellID then
                    local tooltipData = { id = spellID }
                    for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.UnitAura]) do
                        pcall(cb, self, tooltipData)
                    end
                end
            end
            return result
        end
    end

    local originalSetUnitDebuff = GameTooltip.SetUnitDebuff
    if originalSetUnitDebuff then
        GameTooltip.SetUnitDebuff = function(self, unit, index)
            local result = originalSetUnitDebuff(self, unit, index)
            if tooltipCallbacks[Enum.TooltipDataType.UnitAura] then
                local _, _, _, _, _, _, _, _, _, _, spellID = UnitDebuff(unit, index)
                if spellID then
                    local tooltipData = { id = spellID }
                    for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.UnitAura]) do
                        pcall(cb, self, tooltipData)
                    end
                end
            end
            return result
        end
    end
end

-- 5. Frame Metatable Extensions safely supporting modern methods
local EUI_AtlasMap = {
    ["uitools-icon-close"] = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    ["Azerite-PointingArrow"] = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
    ["shop-card-wide-frame-default"] = "Interface\\DialogFrame\\UI-DialogBox-Background",
    ["shop-card-wide-frame-hover"] = "Interface\\DialogFrame\\UI-DialogBox-Background",
    ["lootroll-animreveal-a"] = "Interface\\TargetingFrame\\UI-StatusBar",
    ["UI-Journeys-Delve-Companion-Ring"] = "Interface\\Minimap\\MiniMap-TrackingBorder",
    ["Ui-Dialog-New-Background"] = "Interface\\DialogFrame\\UI-DialogBox-Background",
    ["UI-QuestTrackerButton-Secondary-Collapse"] = "Interface\\Buttons\\UI-MinusButton-Up",
    ["UI-QuestTrackerButton-Secondary-Expand"] = "Interface\\Buttons\\UI-PlusButton-Up",
    ["QuestLog-main-background"] = "Interface\\QuestFrame\\UI-QuestLog-Background",
    ["UI-RefreshButton"] = "Interface\\Buttons\\UI-RotationLeft-Button-Up",
    ["characterupdate_background"] = "Interface\\DialogFrame\\UI-DialogBox-Background",
    ["VAS-icon-checkmark-glw"] = "Interface\\RAIDFRAME\\ReadyCheck-Ready",
    ["charactercreate-icon-dice"] = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
    ["bag-main"] = "Interface\\Buttons\\Button-Backpack-Up",
    ["Crosshair_Quest_64"] = "Interface\\Icons\\INV_Misc_QuestionMark",
    ["UI-HUD-RotationHelper-Inactive-2x"] = "Interface\\Buttons\\UI-Quickslot-Depress",
    ["UI-HUD-ActionBar-IconFrame-Slot"] = "Interface\\Buttons\\UI-EmptySlot",
    ["UI-HUD-ActionBar-IconFrame-Down"] = "Interface\\Buttons\\UI-Quickslot-Depress",
}

local cooldownFrame = CreateFrame("Cooldown", nil, WorldFrame)
local cooldownMeta = getmetatable(cooldownFrame).__index

local frameMetas = {
    getmetatable(CreateFrame("Frame")).__index,
    getmetatable(CreateFrame("Frame"):CreateTexture()).__index,
    getmetatable(CreateFrame("Frame"):CreateFontString()).__index,
    cooldownMeta,
}

for _, meta in ipairs(frameMetas) do
    if meta then
        if not meta.SetShown then
            meta.SetShown = function(self, show)
                if show then self:Show() else self:Hide() end
            end
        end
        if not meta.SetSnapToPixelGrid then
            meta.SetSnapToPixelGrid = function(self, snap) end
        end
        if not meta.SetPixelSnapDisabled then
            meta.SetPixelSnapDisabled = function(self, disable) end
        end
        if not meta.IsForbidden then
            meta.IsForbidden = function(self) return false end
        end
        if not meta.SetTexelSnappingBias then
            meta.SetTexelSnappingBias = function(self, bias) end
        end
        if not meta.PixelSnap then
            meta.PixelSnap = function(self, val) return val end
        end
        if not meta.SetAtlas then
            meta.SetAtlas = function(self, atlas, useAtlasSize)
                if not atlas or atlas == "" then
                    self:SetTexture(nil)
                    return
                end
                local path = EUI_AtlasMap[atlas] or "Interface\\Icons\\INV_Misc_QuestionMark"
                self:SetTexture(path)
            end
        end
        if not meta.SetAlphaFromBoolean then
            meta.SetAlphaFromBoolean = function(self, value, trueAlpha, falseAlpha)
                if trueAlpha == nil then trueAlpha = 1 end
                if falseAlpha == nil then falseAlpha = 0 end
                if value then
                    self:SetAlpha(trueAlpha)
                else
                    self:SetAlpha(falseAlpha)
                end
            end
        end
    end
end

if cooldownMeta then
    if not cooldownMeta.SetCooldownFromDurationObject then
        cooldownMeta.SetCooldownFromDurationObject = function(self, durObj)
            if not durObj then
                self:SetCooldown(0, 0)
                return
            end
            local start = durObj.startTime
            local duration = durObj.duration
            if (not start or start == 0) and durObj.expirationTime and durObj.expirationTime > 0 then
                start = durObj.expirationTime - duration
            end
            self:SetCooldown(start or 0, duration or 0)
        end
    end
end

-- Missing legacy constants definition
if not LE_PARTY_CATEGORY_HOME then LE_PARTY_CATEGORY_HOME = 1 end
if not LE_PARTY_CATEGORY_INSTANCE then LE_PARTY_CATEGORY_INSTANCE = 2 end
if not IsInGroup then
    function IsInGroup(category)
        if category == LE_PARTY_CATEGORY_INSTANCE then
            local _, instanceType = IsInInstance()
            return (instanceType == "pvp" or instanceType == "arena" or GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0)
        else
            return (GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0)
        end
    end
end
