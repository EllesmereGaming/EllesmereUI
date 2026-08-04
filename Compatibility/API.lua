local _G = _G or getfenv(0)
_G.EllesmereUI = _G.EllesmereUI or {}
_G.EllesmereUI._deferredInits = _G.EllesmereUI._deferredInits or {}

EUI = EUI or {}
EUI.API = EUI.API or {}

-- securecallfunction was introduced after Wrath.  Legacy clients do not have
-- the protected-call boundary it provides, but addon code still needs the same
-- calling convention and return values.
if not securecallfunction then
    function securecallfunction(func, ...)
        if type(func) ~= "function" then
            error("bad argument #1 to 'securecallfunction' (function expected)", 2)
        end
        return func(...)
    end
end

-- Retail's friend-list namespace replaced the legacy global APIs.  Keep the
-- modern call sites usable on 3.3.5 while preserving Retail's implementation
-- when it exists.
C_FriendList = C_FriendList or {}
if not C_FriendList.GetNumFriends then
    function C_FriendList.GetNumFriends()
        local total = GetNumFriends and GetNumFriends()
        return total or 0
    end
end
if not C_FriendList.GetNumOnlineFriends then
    function C_FriendList.GetNumOnlineFriends()
        local _, online = GetNumFriends and GetNumFriends()
        return online or 0
    end
end
if not C_FriendList.GetFriendInfoByIndex then
    function C_FriendList.GetFriendInfoByIndex(index)
        if not GetFriendInfo then return nil end
        local name, level, className, area, connected, status, note = GetFriendInfo(index)
        if not name then return nil end
        return {
            name = name,
            level = level,
            className = className,
            area = area,
            connected = connected,
            afk = status == CHAT_FLAG_AFK or status == "AFK",
            dnd = status == CHAT_FLAG_DND or status == "DND",
            notes = note,
        }
    end
end

-- IsEncounterInProgress was added after Wrath. Boss unit presence plus combat
-- is the closest legacy equivalent and is sufficient for visibility rules.
if not IsEncounterInProgress then
    function IsEncounterInProgress()
        if not UnitAffectingCombat then return false end
        for i = 1, 4 do
            local unit = "boss" .. i
            if UnitExists(unit) and UnitAffectingCombat(unit) then return true end
        end
        return false
    end
end

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


-- 3. Dynamic Fallback Proxies for Undefined Namespaces
-- 3. Dynamic Fallback Proxies
-- Removed overly permissive fallback logic to prevent silent errors.
-- Explicitly defined polyfills should be used instead.

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
C_AddOns = C_AddOns or {}
C_AddOns.DisableAddOn = DisableAddOn
C_AddOns.EnableAddOn = EnableAddOn
C_AddOns.IsAddOnLoaded = IsAddOnLoaded
C_AddOns.LoadAddOn = LoadAddOn
C_AddOns.GetNumAddOns = GetNumAddOns
C_AddOns.GetAddOnInfo = GetAddOnInfo
C_AddOns.GetAddOnEnableState = function(name, character)
    local enabled = select(4, GetAddOnInfo(name))
    return enabled and 2 or 0
end
C_AddOns.DoesAddOnExist = function(name)
    return GetAddOnInfo(name) ~= nil
end

-- C_NewItems
C_NewItems = C_NewItems or {}
C_NewItems.ClearAll = C_NewItems.ClearAll or function() end
C_NewItems.IsNewItem = C_NewItems.IsNewItem or function() return false end
C_NewItems.RemoveNewItem = C_NewItems.RemoveNewItem or function() end

-- C_ClassColor
C_ClassColor = C_ClassColor or {}
C_ClassColor.GetClassColor = function(class)
    local color = RAID_CLASS_COLORS[class]
    if color then
        return CreateColor(color.r, color.g, color.b)
    end
    return CreateColor(1, 1, 1)
end

-- C_SpecializationInfo
C_SpecializationInfo = C_SpecializationInfo or {}
if not C_SpecializationInfo.GetSpecialization then
    C_SpecializationInfo.GetSpecialization = function()
        local info = EUI.Spec and EUI.Spec:GetCurrent()
        return info and info.index
    end
end

if not C_SpecializationInfo.GetSpecializationInfo then
    C_SpecializationInfo.GetSpecializationInfo = function(specIndex)
        local info = EUI.Spec and EUI.Spec:GetInfo(specIndex or 1)
        if not info then return end
        return info.id, info.name, "", info.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
            info.role or "DAMAGER", 1, info.classToken
    end
end

GetSpecialization = GetSpecialization or C_SpecializationInfo.GetSpecialization
GetSpecializationInfo = GetSpecializationInfo or C_SpecializationInfo.GetSpecializationInfo
GetNumSpecializations = GetNumSpecializations or function()
    return EUI.Spec and EUI.Spec:GetNum() or 0
end
GetSpecializationInfoByID = GetSpecializationInfoByID or function(specID)
    local info = EUI.Spec and EUI.Spec:GetInfoByID(specID)
    if not info then return end
    return info.id, info.name, "", info.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        info.role or "DAMAGER", 1, info.classToken
end
GetSpecializationInfoForClassID = GetSpecializationInfoForClassID or function(classID, specIndex)
    local info = EUI.Spec and EUI.Spec:GetInfoForClassID(classID, specIndex)
    if not info then return end
    return info.id, info.name, "", info.icon or "Interface\\Icons\\INV_Misc_QuestionMark",
        info.role or "DAMAGER", 1, info.classToken
end
if not GetSpecializationRole then
    GetSpecializationRole = function(specIndex)
        local role = select(5, C_SpecializationInfo.GetSpecializationInfo(specIndex or (GetSpecialization and GetSpecialization())))
        return role or "DAMAGER"
    end
end

-- GetShapeshiftFormID was added after WotLK.  Retail form IDs are not the
-- same thing as the position returned by GetShapeshiftForm(), because that
-- position changes with the forms a character has learned.  Resource bars
-- rely on the stable Cat (1), Bear (5), and Moonkin (31) IDs, so recover the
-- stable ID from the active form's icon on legacy clients.
if not GetShapeshiftFormID then
    local legacyFormIDs = {
        ["ability_druid_catform"] = 1,
        ["ability_druid_treeoflife"] = 2,
        ["ability_druid_travelform"] = 3,
        ["ability_druid_aquaticform"] = 4,
        ["ability_racial_bearform"] = 5,
        ["ability_druid_direbearform"] = 5,
        ["ability_druid_forceofnature"] = 31,
        ["spell_nature_forceofnature"] = 31,
        ["ability_druid_flightform"] = 27,
        ["ability_druid_epicflightform"] = 29,
    }

    function GetShapeshiftFormID()
        local form = GetShapeshiftForm and GetShapeshiftForm() or 0
        if form == 0 or not GetShapeshiftFormInfo then return form end

        local icon = GetShapeshiftFormInfo(form)
        if type(icon) == "string" then
            local key = icon:match("([^\\/]*)$") or icon
            local stableID = legacyFormIDs[string.lower(key)]
            if stableID then return stableID end
        end

        -- Non-druid stances do not need retail's stable druid form IDs.
        return form
    end
end



-- C_CVar
C_CVar = C_CVar or {}

local CVarMap = {
    cameraDistanceMaxZoomFactor = "cameraDistanceMaxFactor",
}

-- Retail owns this CVar; the 3.3.5 client does not. Register the compatibility
-- setting so the Action Bars toggle persists and cooldown text defaults on.
if RegisterCVar then
    local ok, value = pcall(GetCVar, "countdownForCooldowns")
    if not ok or value == nil or value == "" then
        pcall(RegisterCVar, "countdownForCooldowns", "1")
    end
end

if not C_CVar.GetCVar then
    C_CVar.GetCVar = function(name)
        name = CVarMap[name] or name
        local ok, result = pcall(GetCVar, name)
        return ok and result or nil
    end
end
if not C_CVar.SetCVar then
    C_CVar.SetCVar = function(name, value)
        name = CVarMap[name] or name
        local ok, result = pcall(SetCVar, name, value)
        return ok and result or false
    end
end
if not C_CVar.GetCVarInfo then
    C_CVar.GetCVarInfo = function(name)
        name = CVarMap[name] or name
        local ok1, val = pcall(GetCVar, name)
        local ok2, def = pcall(GetCVarDefault, name)
        return (ok1 and val or nil), (ok2 and def or nil)
    end
end
if not C_CVar.GetCVarBool then
    C_CVar.GetCVarBool = function(name)
        name = CVarMap[name] or name
        local ok, result = pcall(GetCVar, name)
        return ok and result == "1" or false
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

-- Retail spell-ownership globals do not exist on the 3.3.5 client.  A number
-- of modules use these before falling back to the other one, so provide both
-- names rather than requiring every call site to special-case legacy clients.
-- C_SpellBook's compatibility implementation above uses the legacy spellbook
-- link lookup and is the authoritative check here.
if not IsSpellKnown then
    function IsSpellKnown(spell)
        return C_SpellBook.IsSpellKnown(spell)
    end
end

if not IsPlayerSpell then
    function IsPlayerSpell(spell)
        return C_SpellBook.IsSpellKnown(spell)
    end
end

-- Load Equipment Set Module immediately if present
if not EquipmentManager_GetLocationData then
    pcall(LoadAddOn, "Blizzard_EquipmentManager")
end

if not EquipmentManager_GetLocationData then
    EquipmentManager_GetLocationData = function(loc)
        if not loc or loc == 0 or loc == 1 or loc == -1 then return {} end
        if EquipmentManager_UnpackLocation then
            local player, bank, bags, slotIndex, bagIndex = EquipmentManager_UnpackLocation(loc)
            return {
                isPlayer = player,
                isBank = bank,
                isBags = bags,
                slot = slotIndex,
                bag = bagIndex,
            }
        end
        return {}
    end
end

-- C_EquipmentSet
if not C_EquipmentSet then
    C_EquipmentSet = {}
end

C_EquipmentSet.GetEquipmentSetIDs = C_EquipmentSet.GetEquipmentSetIDs or function()
    local num = GetNumEquipmentSets and GetNumEquipmentSets() or 0
    local ids = {}
    for i = 1, num do
        ids[i] = i
    end
    return ids
end

C_EquipmentSet.GetEquipmentSetInfo = C_EquipmentSet.GetEquipmentSetInfo or function(setID)
    if not GetEquipmentSetInfo then return nil end
    if type(setID) == "number" then
        local name, icon, id, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored = GetEquipmentSetInfo(setID)
        if name then
            return name, icon, id or setID, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored
        end
    elseif type(setID) == "string" then
        if GetEquipmentSetInfoByName then
            local icon, id, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored = GetEquipmentSetInfoByName(setID)
            if icon then
                return setID, icon, id or setID, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored
            end
        else
            local num = GetNumEquipmentSets and GetNumEquipmentSets() or 0
            for i = 1, num do
                local name, icon, id, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored = GetEquipmentSetInfo(i)
                if name == setID then
                    return name, icon, id or i, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored
                end
            end
        end
    end
    return nil
end

C_EquipmentSet.GetEquipmentSetID = C_EquipmentSet.GetEquipmentSetID or function(setName)
    if type(setName) == "number" then return setName end
    if not GetNumEquipmentSets then return nil end
    local num = GetNumEquipmentSets()
    for i = 1, num do
        local name = GetEquipmentSetInfo(i)
        if name == setName then
            return i
        end
    end
    return nil
end

C_EquipmentSet.UseEquipmentSet = C_EquipmentSet.UseEquipmentSet or function(setID)
    local setName = type(setID) == "string" and setID or (GetEquipmentSetInfo and (GetEquipmentSetInfo(setID)))
    if setName then
        if EquipmentManager_EquipSet then
            EquipmentManager_EquipSet(setName)
        elseif UseEquipmentSet then
            UseEquipmentSet(setName)
        end
    end
end

C_EquipmentSet.CreateEquipmentSet = C_EquipmentSet.CreateEquipmentSet or function(setName, icon)
    if SaveEquipmentSet then
        SaveEquipmentSet(setName, icon or 1)
    end
end

C_EquipmentSet.SaveEquipmentSet = C_EquipmentSet.SaveEquipmentSet or function(setID)
    local setName, icon = nil, nil
    if type(setID) == "string" then
        setName = setID
    elseif type(setID) == "number" and GetEquipmentSetInfo then
        setName, icon = GetEquipmentSetInfo(setID)
    end
    if setName and SaveEquipmentSet then
        SaveEquipmentSet(setName, icon)
    end
end

C_EquipmentSet.DeleteEquipmentSet = C_EquipmentSet.DeleteEquipmentSet or function(setID)
    local setName = type(setID) == "string" and setID or (GetEquipmentSetInfo and (GetEquipmentSetInfo(setID)))
    if setName and DeleteEquipmentSet then
        DeleteEquipmentSet(setName)
    end
end

C_EquipmentSet.ModifyEquipmentSet = C_EquipmentSet.ModifyEquipmentSet or function(setID, newName, newIcon)
    local oldName = type(setID) == "string" and setID or (GetEquipmentSetInfo and (GetEquipmentSetInfo(setID)))
    if oldName then
        if ModifyEquipmentSet then
            ModifyEquipmentSet(oldName, newName, newIcon)
        elseif SaveEquipmentSet then
            SaveEquipmentSet(newName or oldName, newIcon)
        end
    end
end

C_EquipmentSet.PickupEquipmentSet = C_EquipmentSet.PickupEquipmentSet or function(setID)
    local setName = type(setID) == "string" and setID or (GetEquipmentSetInfo and (GetEquipmentSetInfo(setID)))
    if setName and PickupEquipmentSet then
        PickupEquipmentSet(setName)
    end
end

C_EquipmentSet.GetEquipmentSetAssignedSpec = C_EquipmentSet.GetEquipmentSetAssignedSpec or function(setID)
    return nil
end

C_EquipmentSet.AssignSpecToEquipmentSet = C_EquipmentSet.AssignSpecToEquipmentSet or function(setID, specIndex)
end

C_EquipmentSet.UnassignEquipmentSetSpec = C_EquipmentSet.UnassignEquipmentSetSpec or function(setID)
end

C_EquipmentSet.GetItemIDs = C_EquipmentSet.GetItemIDs or function(setID)
    local setName = type(setID) == "string" and setID or (GetEquipmentSetInfo and (GetEquipmentSetInfo(setID)))
    if setName then
        if GetEquipmentSetItemIDs then
            return GetEquipmentSetItemIDs(setName) or {}
        elseif GetEquipmentSetLocations then
            local locations = GetEquipmentSetLocations(setName)
            local itemIDs = {}
            if locations then
                for slot, loc in pairs(locations) do
                    if loc and loc ~= 0 and EquipmentManager_UnpackLocation then
                        local player, bank, bags, slotIndex, bagIndex = EquipmentManager_UnpackLocation(loc)
                        if bags and bagIndex and slotIndex then
                            itemIDs[slot] = GetContainerItemID(bagIndex, slotIndex)
                        elseif player and slotIndex then
                            itemIDs[slot] = GetInventoryItemID("player", slotIndex)
                        end
                    end
                end
            end
            return itemIDs
        end
    end
    return {}
end

C_EquipmentSet.GetItemLocations = C_EquipmentSet.GetItemLocations or function(setID)
    local setName = type(setID) == "string" and setID or (GetEquipmentSetInfo and (GetEquipmentSetInfo(setID)))
    if setName and GetEquipmentSetLocations then
        local locations = GetEquipmentSetLocations(setName)
        local list = {}
        if locations then
            for slot, loc in pairs(locations) do
                list[#list + 1] = loc
            end
        end
        return list
    end
    return nil
end


-- 4. Global Objects & Structures (Enum, Color, TooltipDataProcessor)


-- Missing legacy constants definition
if not LE_PARTY_CATEGORY_HOME then LE_PARTY_CATEGORY_HOME = 1 end
if not LE_PARTY_CATEGORY_INSTANCE then LE_PARTY_CATEGORY_INSTANCE = 2 end
if not IsInRaid then
    function IsInRaid()
        return GetNumRaidMembers() > 0
    end
end
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
if not GetNumGroupMembers then
    function GetNumGroupMembers()
        local raidMembers = GetNumRaidMembers()
        if raidMembers > 0 then return raidMembers end

        local partyMembers = GetNumPartyMembers()
        if partyMembers > 0 then return partyMembers + 1 end
        return 0
    end
end
if not GetNumSubgroupMembers then
    function GetNumSubgroupMembers()
        return GetNumPartyMembers()
    end
end

-- Enum Namespace and catch-all safety
-- Enum Namespace
Enum = Enum or {}

-- Explicitly populate Enum subfields used in the codebase
Enum.ItemClass = {
    Weapon = 2,
    Armor = 4,
    Gem = 3,
    Container = 1,
    Consumable = 0,
    Glyph = 16,
    TradeGoods = 7,
    Tradegoods = 7,
    Projectile = 6,
    Quiver = 11,
    Recipe = 9,
    Reagent = 5,
    ItemEnhancement = 8,
    Key = 13,
    Miscellaneous = 15,
    Quest = 12,
    Questitem = 12,
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
    Unit = 6,
}

Enum.PowerType = {
    Mana = 0,
    Rage = 1,
    Focus = 2,
    Energy = 3,
    RunicPower = 6,
}
C_UnitAuras = C_UnitAuras or {}
C_UA = C_UA or {}
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
        local spellName, spellID = GetItemSpell(item)
        -- Some 3.3.5 clients return empty strings instead of nil when an item
        -- has no spell.  Match the modern C_Item contract and ensure callers
        -- never receive a string where they expect a numeric spell ID.
        if spellName == "" then spellName = nil end
        spellID = tonumber(spellID)
        return spellName, spellID
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

    -- Classic GetItemInfo returns localized class/subclass names rather than
    -- the numeric class IDs returned by retail. Translate the class name so
    -- retail category code can remain locale-independent.
    local itemClassIDs = {
        ["Consumable"]          = 0,
        ["Container"]           = 1,
        ["Bag"]                 = 1,
        ["Weapon"]              = 2,
        ["Gem"]                 = 3,
        ["Armor"]               = 4,
        ["Reagent"]             = 5,
        ["Projectile"]          = 6,
        ["Trade Goods"]         = 7,
        ["TradeGoods"]          = 7,
        ["Item Enhancement"]    = 8,
        ["Generic"]             = 8,
        ["Recipe"]              = 9,
        ["Money"]               = 10,
        ["Quiver"]              = 11,
        ["Quest"]               = 12,
        ["Questitem"]           = 12,
        ["Key"]                 = 13,
        ["Permanent"]           = 14,
        ["Miscellaneous"]       = 15,
        ["Glyph"]               = 16,
    }

    local classIndexToID = {
        [1]  = 2,  -- Weapon -> Enum.ItemClass.Weapon (2)
        [2]  = 4,  -- Armor -> Enum.ItemClass.Armor (4)
        [3]  = 1,  -- Container -> Enum.ItemClass.Container (1)
        [4]  = 0,  -- Consumable -> Enum.ItemClass.Consumable (0)
        [5]  = 16, -- Glyph -> Enum.ItemClass.Glyph (16)
        [6]  = 7,  -- Trade Goods -> Enum.ItemClass.Tradegoods (7)
        [7]  = 6,  -- Projectile -> Enum.ItemClass.Projectile (6)
        [8]  = 11, -- Quiver -> Enum.ItemClass.Quiver (11)
        [9]  = 9,  -- Recipe -> Enum.ItemClass.Recipe (9)
        [10] = 3,  -- Gem -> Enum.ItemClass.Gem (3)
        [11] = 15, -- Miscellaneous -> Enum.ItemClass.Miscellaneous (15)
        [12] = 12, -- Quest -> Enum.ItemClass.Questitem (12)
    }
    local function PopulateItemClassIDs()
        if GetAuctionItemClasses then
            local classes = { GetAuctionItemClasses() }
            for i, name in ipairs(classes) do
                if name and name ~= "" and classIndexToID[i] ~= nil then
                    itemClassIDs[name] = classIndexToID[i]
                end
            end
        end
    end
    PopulateItemClassIDs()

    local itemSubclassIDs = {
        -- Armor (4)
        ["4:Miscellaneous"]       = 0,
        ["4:Cloth"]               = 1,
        ["4:Leather"]             = 2,
        ["4:Mail"]                = 3,
        ["4:Plate"]               = 4,
        ["4:Buckler"]             = 5,
        ["4:Shields"]             = 6,
        ["4:Shield"]              = 6,
        ["4:Librams"]             = 7,
        ["4:Idols"]               = 8,
        ["4:Totems"]              = 9,
        ["4:Sigils"]              = 10,
        -- Weapon (2)
        ["2:One-Handed Axes"]     = 0,
        ["2:Two-Handed Axes"]     = 1,
        ["2:Bows"]                = 2,
        ["2:Guns"]                = 3,
        ["2:One-Handed Maces"]    = 4,
        ["2:Two-Handed Maces"]    = 5,
        ["2:Polearms"]            = 6,
        ["2:One-Handed Swords"]   = 7,
        ["2:Two-Handed Swords"]   = 8,
        ["2:Staves"]              = 10,
        ["2:One-Handed Exotics"]  = 11,
        ["2:Two-Handed Exotics"]  = 12,
        ["2:Fist Weapons"]        = 13,
        ["2:Miscellaneous"]       = 14,
        ["2:Daggers"]             = 15,
        ["2:Thrown"]              = 16,
        ["2:Crossbows"]           = 18,
        ["2:Wands"]               = 19,
        ["2:Fishing Poles"]       = 20,
    }

    local function PopulateItemSubclassIDs()
        if GetAuctionItemClasses and GetAuctionItemSubClasses then
            for i, classID in pairs(classIndexToID) do
                local subClasses = { GetAuctionItemSubClasses(i) }
                for subIdx, subName in ipairs(subClasses) do
                    if subName and subName ~= "" then
                        itemSubclassIDs[classID .. ":" .. subName] = subIdx - 1
                    end
                end
            end
        end
    end
    PopulateItemSubclassIDs()

    C_Item.GetItemInfoInstant = function(item)
        if not item then return nil end
        local name, link, rarity, level, minLevel, type, subType, stackCount, equipLoc, texture, price, classID, subclassID = GetItemInfo(item)
        local itemID = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
        if not classID and type then
            classID = itemClassIDs[type]
            if not classID and GetAuctionItemClasses then
                PopulateItemClassIDs()
                classID = itemClassIDs[type]
            end
        end
        if not subclassID and classID and subType then
            subclassID = itemSubclassIDs[classID .. ":" .. subType]
            if not subclassID and GetAuctionItemSubClasses then
                PopulateItemSubclassIDs()
                subclassID = itemSubclassIDs[classID .. ":" .. subType]
            end
        end
        return itemID, type, subType, equipLoc, texture, classID, subclassID
    end
    GetItemInfoInstant = C_Item.GetItemInfoInstant

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


-- ItemLocation Object Mock
ItemLocation = ItemLocation or {}
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

function ItemLocation:CreateFromGUID(guid)
    local obj = setmetatable({}, self)
    obj.guid = guid
    return obj
end

function ItemLocation:CreateEmpty()
    return setmetatable({}, self)
end

function ItemLocation:IsValid()
    return self:HasAnyLocation()
end

function ItemLocation:HasAnyLocation()
    return self.bag ~= nil or self.equipmentSlot ~= nil or self.guid ~= nil
end

function ItemLocation:Clear()
    self.bag = nil
    self.slot = nil
    self.equipmentSlot = nil
    self.guid = nil
end

function ItemLocation:IsEqualTo(other)
    if not other then return false end
    return self.bag == other.bag and self.slot == other.slot and self.equipmentSlot == other.equipmentSlot and self.guid == other.guid
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
        local start, duration, enabled, modRate = GetSpellCooldown(spell)
        start = start or 0
        duration = duration or 0
        modRate = modRate or 1
        local isActive = start > 0 and duration > 0
        return {
            startTime = start,
            duration = duration,
            isEnabled = enabled == nil or enabled == 1 or enabled == true,
            modRate = modRate,
            isActive = isActive,
            isOnGCD = isActive and duration <= 1.6,
        }
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
        if not IsSpellInRange then return nil end

        -- On 3.3.5 a numeric first argument is interpreted as a spellbook
        -- slot, not a spell ID. Retail callers consistently pass IDs, so
        -- resolve those to the learned spell name before invoking the legacy
        -- API. pcall also makes unknown/unlearned IDs safely indeterminate
        -- instead of aborting secure-header roster processing.
        local query = spell
        if type(spell) == "number" then
            query = GetSpellInfo(spell)
            if not query then return nil end
        end
        local ok, result = pcall(IsSpellInRange, query, unit)
        if not ok then return nil end

        -- Legacy returns 1/0; modern C_Spell returns booleans.
        if result == 1 then return true end
        if result == 0 then return false end
        return result
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

    local function OnTooltipSetUnit(self)
        if not self.GetUnit then return end
        local name, unit = self:GetUnit()
        if tooltipCallbacks[Enum.TooltipDataType.Unit] then
            local tooltipData = { name = name, unit = unit }
            for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.Unit]) do
                pcall(cb, self, tooltipData)
            end
        end
    end

    if GameTooltip then
        GameTooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell)
        GameTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
        GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)
    end
    if ItemRefTooltip then
        ItemRefTooltip:HookScript("OnTooltipSetSpell", OnTooltipSetSpell)
        ItemRefTooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
        ItemRefTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)
    end

    if GameTooltip.SetUnitAura then
        hooksecurefunc(GameTooltip, "SetUnitAura", function(self, unit, index, filter)
            if tooltipCallbacks[Enum.TooltipDataType.UnitAura] then
                local _, _, _, _, _, _, _, _, _, _, spellID = UnitAura(unit, index, filter)
                if spellID then
                    local tooltipData = { id = spellID }
                    for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.UnitAura]) do
                        pcall(cb, self, tooltipData)
                    end
                end
            end
        end)
    end

    if GameTooltip.SetUnitBuff then
        hooksecurefunc(GameTooltip, "SetUnitBuff", function(self, unit, index)
            if tooltipCallbacks[Enum.TooltipDataType.UnitAura] then
                local _, _, _, _, _, _, _, _, _, _, spellID = UnitBuff(unit, index)
                if spellID then
                    local tooltipData = { id = spellID }
                    for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.UnitAura]) do
                        pcall(cb, self, tooltipData)
                    end
                end
            end
        end)
    end

    if GameTooltip.SetUnitDebuff then
        hooksecurefunc(GameTooltip, "SetUnitDebuff", function(self, unit, index)
            if tooltipCallbacks[Enum.TooltipDataType.UnitAura] then
                local _, _, _, _, _, _, _, _, _, _, spellID = UnitDebuff(unit, index)
                if spellID then
                    local tooltipData = { id = spellID }
                    for _, cb in ipairs(tooltipCallbacks[Enum.TooltipDataType.UnitAura]) do
                        pcall(cb, self, tooltipData)
                    end
                end
            end
        end)
    end
end

-- 18. RegisterAttributeDriver / UnregisterAttributeDriver Polyfills for WotLK 3.3.5
if not _G.RegisterAttributeDriver then
    LoadAddOn("Blizzard_SecureTemplates")
    
    if not _G.RegisterAttributeDriver then
        _G.RegisterAttributeDriver = function(frame, attribute, conditional)
            if not frame or not attribute then return end
            local state = attribute
            if attribute:sub(1, 6) == "state-" then
                state = attribute:sub(7)
            end
            RegisterStateDriver(frame, state, conditional)
        end
    end
end

if not _G.UnregisterAttributeDriver then
    _G.UnregisterAttributeDriver = function(frame, attribute)
        if not frame or not attribute then return end
        local state = attribute
        if attribute:sub(1, 6) == "state-" then
            state = attribute:sub(7)
        end
        UnregisterStateDriver(frame, state)
    end
end

-- 19. GetAverageItemLevel Polyfill for WoW 3.3.5
if not _G.GetAverageItemLevel then
    _G.GetAverageItemLevel = function()
        local totalIlvl = 0
        local totalSlots = 0

        -- Standard equipment slots in WotLK (1..18, excluding 4=Shirt and 19=Tabard)
        local slots = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18}

        local mhLink = GetInventoryItemLink("player", 16)
        local is2H = false
        if mhLink then
            local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(mhLink)
            if equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" then
                is2H = true
            end
        end

        for _, slotID in ipairs(slots) do
            local link = GetInventoryItemLink("player", slotID)
            if link then
                local _, _, _, ilvl = GetItemInfo(link)
                if ilvl and ilvl > 0 then
                    totalIlvl = totalIlvl + ilvl
                    totalSlots = totalSlots + 1
                end
            elseif slotID == 17 and is2H and mhLink then
                -- 2H weapon covers off-hand slot
                local _, _, _, ilvl = GetItemInfo(mhLink)
                if ilvl and ilvl > 0 then
                    totalIlvl = totalIlvl + ilvl
                    totalSlots = totalSlots + 1
                end
            end
        end

        local avg = (totalSlots > 0) and (totalIlvl / totalSlots) or 0
        return avg, avg, avg
    end
end

-- 20. Secondary, Tertiary & Character Stats Polyfills for WotLK 3.3.5
if not _G.UnitSpellHaste then
    _G.UnitSpellHaste = function(unit)
        if GetHaste then return GetHaste() or 0 end
        if GetCombatRatingBonus then return GetCombatRatingBonus(20) or 0 end
        return 0
    end
end

if not _G.GetMasteryEffect then
    _G.GetMasteryEffect = function() return 0 end
end

if not _G.GetVersatilityBonus then
    _G.GetVersatilityBonus = function(stat) return 0 end
end

if not _G.GetLifesteal then
    _G.GetLifesteal = function() return 0 end
end

if not _G.GetAvoidance then
    _G.GetAvoidance = function() return 0 end
end

if not _G.GetSpeed then
    _G.GetSpeed = function() return 0 end
end

if not _G.issecretvalue then
    _G.issecretvalue = function(val) return false end
end

if not _G.BreakUpLargeNumbers then
    _G.BreakUpLargeNumbers = function(value)
        local n = tonumber(value)
        if not n then return tostring(value or "") end
        local s = tostring(math.floor(n))
        local left, num, right = string.match(s, '^([^%d]*%d+)(%d*)(.-)$')
        if not num then return s end
        return left .. (num:reverse():gsub('(%d%d%d)', '%1,'):reverse()) .. right
    end
end

-- Retail API used by health, power, absorb, and preview text throughout EUI.
-- The optional config argument is also supported so the unit-frame decimal
-- settings can use their custom breakpointData tables on WotLK.
if not _G.AbbreviateNumbers then
    _G.AbbreviateNumbers = function(value, config)
        local n = tonumber(value)
        if not n then return tostring(value or "") end

        local abs = math.abs(n)
        local breakpoints = config and config.breakpointData
        if breakpoints then
            for i = 1, #breakpoints do
                local data = breakpoints[i]
                if abs >= (data.breakpoint or math.huge) then
                    local divisor = data.significandDivisor or data.breakpoint
                    local fractionDivisor = data.fractionDivisor or 1
                    local scaled = math.floor(abs / divisor) / fractionDivisor
                    if n < 0 then scaled = -scaled end
                    return tostring(scaled) .. (data.abbreviation or "")
                end
            end
            return tostring(n)
        end

        local divisor, suffix
        if abs >= 1e9 then
            divisor, suffix = 1e9, "B"
        elseif abs >= 1e6 then
            divisor, suffix = 1e6, "M"
        elseif abs >= 1e3 then
            divisor, suffix = 1e3, "K"
        else
            return tostring(n)
        end

        local scaled = n / divisor
        if math.abs(scaled) >= 100 then
            return string.format("%.0f%s", scaled, suffix)
        end
        return string.format("%.1f%s", scaled, suffix)
    end
end

if not _G.AbbreviateLargeNumbers then
    _G.AbbreviateLargeNumbers = _G.AbbreviateNumbers
end

-- Retail percentage helpers used by oUF tags. ScaleTo100 is an opaque curve
-- constant on retail; WotLK only needs a sentinel because these fallbacks
-- calculate the 0..100 percentage directly.
_G.CurveConstants = _G.CurveConstants or {}
if _G.CurveConstants.ScaleTo100 == nil then
    _G.CurveConstants.ScaleTo100 = true
end

if not _G.UnitHealthPercent then
    _G.UnitHealthPercent = function(unit, usePredicted, curve)
        local maximum = UnitHealthMax(unit)
        if not maximum or maximum <= 0 then return 0 end
        return (UnitHealth(unit) or 0) / maximum * 100
    end
end

if not _G.UnitPowerPercent then
    _G.UnitPowerPercent = function(unit, powerType, usePredicted, curve)
        local maximum = UnitPowerMax(unit, powerType)
        if not maximum or maximum <= 0 then return 0 end
        return (UnitPower(unit, powerType) or 0) / maximum * 100
    end
end

-- Retail group-role helpers are not available on WotLK 3.3.5.
if not _G.UnitIsGroupLeader then
    _G.UnitIsGroupLeader = function(unit)
        if unit == "player" then
            return (IsPartyLeader and IsPartyLeader())
                or (IsRaidLeader and IsRaidLeader())
                or false
        end

        if UnitInRaid and UnitInRaid("player") then
            local unitName = UnitName(unit)
            if unitName then
                for i = 1, GetNumRaidMembers() do
                    local name, rank = GetRaidRosterInfo(i)
                    if name == unitName then return rank == 2 end
                end
            end
            return false
        end

        return UnitIsPartyLeader and UnitIsPartyLeader(unit) == 1 or false
    end
end

if not _G.UnitIsGroupAssistant then
    _G.UnitIsGroupAssistant = function(unit)
        if not (UnitInRaid and UnitInRaid("player")) then return false end

        local unitName = UnitName(unit)
        if unitName then
            for i = 1, GetNumRaidMembers() do
                local name, rank = GetRaidRosterInfo(i)
                if name == unitName then return rank == 1 end
            end
        end
        return false
    end
end

if not _G.GetCritChanceProvidesParryEffect then
    _G.GetCritChanceProvidesParryEffect = function() return false end
end

if not _G.GetCombatRatingBonusForCombatRatingValue then
    _G.GetCombatRatingBonusForCombatRatingValue = function(cr, val) return 0 end
end

if not _G.GetSpecializationMasterySpells then
    _G.GetSpecializationMasterySpells = function(specIndex) return nil, nil end
end

if not _G.GetCrestValue then
    _G.GetCrestValue = function(id) return 0 end
end

if not _G.UnitHonorLevel then
    _G.UnitHonorLevel = function(unit) return 0 end
end

if not _G.UnitHonor then
    _G.UnitHonor = function(unit) return 0 end
end

if not _G.UnitHonorMax then
    _G.UnitHonorMax = function(unit) return 0 end
end

-- C_PaperDollInfo Namespace Polyfill
_G.C_PaperDollInfo = _G.C_PaperDollInfo or {}
if not _G.C_PaperDollInfo.GetStaggerPercentage then
    _G.C_PaperDollInfo.GetStaggerPercentage = function(unit) return 0 end
end
if not _G.C_PaperDollInfo.GetArmor then
    _G.C_PaperDollInfo.GetArmor = function(unit)
        local base, effective = UnitArmor(unit or "player")
        return effective or 0, base or 0
    end
end

-- C_Spell Namespace Polyfill
_G.C_Spell = _G.C_Spell or {}
if not _G.C_Spell.GetSpellDescription then
    _G.C_Spell.GetSpellDescription = function(spellID)
        if GetSpellDescription then return GetSpellDescription(spellID) end
        return ""
    end
end

-- Retail Combat Rating Constants & Safe Wrappers for WotLK 3.3.5
CR_MASTERY = CR_MASTERY or 9901
CR_VERSATILITY_DAMAGE_DONE = CR_VERSATILITY_DAMAGE_DONE or 9902
CR_VERSATILITY_DAMAGE_TAKEN = CR_VERSATILITY_DAMAGE_TAKEN or 9903
CR_LIFESTEAL = CR_LIFESTEAL or 9904
CR_AVOIDANCE = CR_AVOIDANCE or 9905
CR_SPEED = CR_SPEED or 9906

local _native_GetCombatRating = _G.GetCombatRating
_G.GetCombatRating = function(cr)
    if not cr or type(cr) ~= "number" or cr >= 9900 then return 0 end
    if _native_GetCombatRating then
        local ok, val = pcall(_native_GetCombatRating, cr)
        if ok and val then return val end
    end
    return 0
end

local _native_GetCombatRatingBonus = _G.GetCombatRatingBonus
_G.GetCombatRatingBonus = function(cr)
    if not cr or type(cr) ~= "number" or cr >= 9900 then return 0 end
    if _native_GetCombatRatingBonus then
        local ok, val = pcall(_native_GetCombatRatingBonus, cr)
        if ok and val then return val end
    end
    return 0
end

local _native_GetCritChance = _G.GetCritChance
_G.GetCritChance = function(unit)
    if _native_GetCritChance then
        local ok, val = pcall(_native_GetCritChance)
        if ok and val then return val end
    end
    if _G.GetCombatRatingBonus then return _G.GetCombatRatingBonus(CR_CRIT_MELEE or 9) or 0 end
    return 0
end
