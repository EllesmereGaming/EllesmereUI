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


-- 3. Dynamic Fallback Proxies for Undefined Namespaces
-- 3. Dynamic Fallback Proxies
-- Removed overly permissive fallback logic to prevent silent errors.
-- Explicitly defined polyfills should be used instead.

-- DurationObject class
local DurationObject = {}
DurationObject.__index = DurationObject
_G.EllesmereUI.DurationObject = DurationObject

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
    return _G.EllesmereUI.DurationObject:Create(start, duration, start + duration)
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
    return _G.EllesmereUI.DurationObject:Create(0, 0, 0)
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
C_AddOns.GetAddOnEnableState = function(name, character)
    local enabled = select(4, GetAddOnInfo(name))
    return enabled and 2 or 0
end
C_AddOns.DoesAddOnExist = function(name)
    return GetAddOnInfo(name) ~= nil
end

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


-- C_CVar
C_CVar = C_CVar or {}

local CVarMap = {
    cameraDistanceMaxZoomFactor = "cameraDistanceMaxFactor",
}

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


-- 4. Global Objects & Structures (Enum, Color, TooltipDataProcessor)


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
