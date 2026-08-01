local addonName, ns = ...

-- This file globally polyfills the Retail C_CooldownViewer API for WotLK 3.3.5a.
-- We do this to decouple the data layer from EllesmereUI's internal namespaces,
-- allowing standard Retail renderer code to work unchanged on older clients
-- and making this Cooldown logic reusable for other addons.
-- Note: Runtime behavior requires in-client verification.

_G.C_CooldownViewer = _G.C_CooldownViewer or {}

-- Internal Data Models
local definitions = {}      -- cooldownID -> definition schema
local availability = {}     -- cooldownID -> { isKnown = boolean, activeSpellID = number, activeAuraSpellID = number }
local runtimeState = {}     -- cooldownID -> { cooldownStart, cooldownDuration, cooldownEnabled, auraActive, auraStacks, auraDuration, auraExpiration }
local categories = {}       -- categoryID -> array of cooldownIDs
local adapters = {}         -- cooldownID -> Frame-like mock object

-- Caching
local cachedPlayerAuras = {}
local cachedAuraTime = 0

-- Event Tracker Frame
local tracker = CreateFrame("Frame")

local function ValidateDefinition(def)
    if not def.key then return false, "Missing key" end
    if not def.cooldownID then return false, "Missing cooldownID" end
    if definitions[def.cooldownID] then return false, "Duplicate cooldownID" end

    local keyExists = false
    for _, existing in pairs(definitions) do
        if existing.key == def.key then
            keyExists = true
            break
        end
    end
    if keyExists then return false, "Duplicate key" end

    if not def.category then return false, "Missing category" end
    if not def.trackingType then return false, "Missing trackingType" end

    if def.trackingType == "cooldown" and not def.spellID then return false, "Tracking type cooldown requires spellID" end
    if def.trackingType == "aura" and not (def.spellID or def.auraSpellID) then return false, "Tracking type aura requires spellID or auraSpellID" end

    return true
end

-- Adapter Prototype
local AdapterMixin = {}
function AdapterMixin:GetSpellID()
    local avail = availability[self.cooldownID]
    local def = definitions[self.cooldownID]
    if avail and avail.activeSpellID then return avail.activeSpellID end
    if def then return def.overrideSpellID or def.spellID end
    return nil
end

function AdapterMixin:GetAuraSpellID()
    local avail = availability[self.cooldownID]
    local def = definitions[self.cooldownID]
    if avail and avail.activeAuraSpellID then return avail.activeAuraSpellID end
    if def then return def.auraSpellID or def.spellID end
    return nil
end

function AdapterMixin:UpdateInfo()
    self.cooldownInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(self.cooldownID)
end

local function GetOrCreateAdapter(cdID)
    if not adapters[cdID] then
        local a = { cooldownID = cdID }
        setmetatable(a, { __index = AdapterMixin })
        adapters[cdID] = a
    end
    adapters[cdID]:UpdateInfo()
    return adapters[cdID]
end

-- Registers a logical ability definition into the system.
-- The cooldownID MUST be globally unique across ALL classes and items.
-- It acts as a stable handle for UI components (like drag-and-drop or saves).
function C_CooldownViewer.RegisterDefinition(def)
    local ok, err = ValidateDefinition(def)
    if not ok then
        print("|cffff5555[CDM Polyfill Error]|r Definition rejected: " .. err .. " (" .. tostring(def.key) .. ")")
        return
    end

    definitions[def.cooldownID] = def

    categories[def.category] = categories[def.category] or {}
    table.insert(categories[def.category], def.cooldownID)

    -- Ensure deterministic sorting using order, then cooldownID as tie-breaker
    table.sort(categories[def.category], function(a, b)
        local dA = definitions[a]
        local dB = definitions[b]
        local oA = dA and dA.order or 999
        local oB = dB and dB.order or 999
        if oA == oB then
            return a < b
        end
        return oA < oB
    end)
end

function C_CooldownViewer.GetCooldownViewerCategorySet(category, includeUnknown)
    local results = {}
    local catIDs = categories[category] or {}

    for _, cdID in ipairs(catIDs) do
        local avail = availability[cdID]
        local isKnown = avail and avail.isKnown or false
        if includeUnknown or isKnown then
            table.insert(results, cdID)
        end
    end

    return results
end

function C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
    local def = definitions[cooldownID]
    local avail = availability[cooldownID]
    local state = runtimeState[cooldownID]

    if not def then return nil end

    local activeSpellID = avail and avail.activeSpellID or def.spellID

    return {
        cooldownID = cooldownID,
        spellID = activeSpellID,
        overrideSpellID = def.overrideSpellID,

        -- Runtime state fields expected by EllesmereUI adapters
        cooldownStart = state and state.cooldownStart or 0,
        cooldownDuration = state and state.cooldownDuration or 0,
        cooldownEnabled = state and state.cooldownEnabled or false,
        auraActive = state and state.auraActive or false,
        auraDuration = state and state.auraDuration or 0,
        auraExpiration = state and state.auraExpiration or 0,
        auraStacks = state and state.auraStacks or 0,
    }
end

-- Aura Caching
local function UpdateAuraCache()
    table.wipe(cachedPlayerAuras)
    for i = 1, 40 do
        local name, rank, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellID = UnitAura("player", i, "HELPFUL")
        if not name then break end
        if spellID then
            cachedPlayerAuras[spellID] = { duration = duration or 0, expirationTime = expirationTime or 0, count = count or 0 }
        end
    end
    for i = 1, 40 do
        local name, rank, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellID = UnitAura("player", i, "HARMFUL")
        if not name then break end
        if spellID then
            cachedPlayerAuras[spellID] = { duration = duration or 0, expirationTime = expirationTime or 0, count = count or 0 }
        end
    end
    cachedAuraTime = GetTime()
end

local function GetCachedAura(spellID)
    if not spellID then return nil end
    -- Fallback safety if accessed outside of normal flow
    if GetTime() > cachedAuraTime + 0.5 then
        UpdateAuraCache()
    end
    return cachedPlayerAuras[spellID]
end

-- Refresh logic
local function ReevaluateAvailability()
    local _, playerClass = UnitClass("player")

    for cdID, def in pairs(definitions) do
        local allowed = true
        if def.class and def.class ~= playerClass then allowed = false end

        -- Resolvers support
        if allowed and def.resolvers and def.resolvers.requirements then
            allowed = def.resolvers.requirements(def)
        end

        local activeSpellID = nil
        local isKnown = false

        if allowed then
            if def.resolvers and def.resolvers.resolveSpellID then
                local resolved = def.resolvers.resolveSpellID(def)
                if resolved then
                    isKnown = true
                    activeSpellID = resolved
                end
            elseif def.spellIDs then
                for i = #def.spellIDs, 1, -1 do
                    local sID = def.spellIDs[i]
                    if IsSpellKnown and IsSpellKnown(sID) then
                        isKnown = true
                        activeSpellID = sID
                        break
                    end
                end
            elseif def.spellID then
                if IsSpellKnown and IsSpellKnown(def.spellID) then
                    isKnown = true
                    activeSpellID = def.spellID
                end
            end
        end

        availability[cdID] = {
            isKnown = isKnown,
            activeSpellID = activeSpellID or def.spellID,
            activeAuraSpellID = def.auraSpellID or activeSpellID or def.spellID
        }
    end
end

local function ReevaluateState()
    for cdID, def in pairs(definitions) do
        local avail = availability[cdID]
        local state = runtimeState[cdID] or {}

        if avail and avail.isKnown then
            local spellID = avail.activeSpellID
            if def.trackingType == "cooldown" or def.trackingType == "cooldown_and_aura" then
                if spellID then
                    local start, duration, enabled = GetSpellCooldown(spellID)
                    state.cooldownStart = start or 0
                    state.cooldownDuration = duration or 0
                    state.cooldownEnabled = (enabled == 1)
                end
            end

            if def.trackingType == "aura" or def.trackingType == "cooldown_and_aura" then
                local auraID = avail.activeAuraSpellID
                if auraID then
                    local aura = GetCachedAura(auraID)
                    if aura then
                        state.auraActive = true
                        state.auraDuration = aura.duration
                        state.auraExpiration = aura.expirationTime
                        state.auraStacks = aura.count
                    else
                        state.auraActive = false
                    end
                end
            end
        else
            -- Unknown or inactive
            state.cooldownStart = 0
            state.cooldownDuration = 0
            state.cooldownEnabled = false
            state.auraActive = false
        end

        runtimeState[cdID] = state

        -- Update persistent adapter
        if adapters[cdID] then
            adapters[cdID]:UpdateInfo()
        end
    end
end

-- Event Handling
tracker:RegisterEvent("PLAYER_LOGIN")
tracker:RegisterEvent("SPELLS_CHANGED")
tracker:RegisterEvent("PLAYER_TALENT_UPDATE")
tracker:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
tracker:RegisterEvent("UNIT_AURA")
tracker:RegisterEvent("SPELL_UPDATE_COOLDOWN")

tracker:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" or event == "PLAYER_EQUIPMENT_CHANGED" then
        ReevaluateAvailability()
        ReevaluateState()
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateAuraCache()
        ReevaluateAvailability()
        ReevaluateState()
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            UpdateAuraCache()
            ReevaluateState()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        ReevaluateState()
    end
end)

-- Global Viewer Pools (Mocking Retail UI Frames)
_G.EssentialCooldownViewer = _G.EssentialCooldownViewer or {}
_G.UtilityCooldownViewer = _G.UtilityCooldownViewer or {}
_G.BuffIconCooldownViewer = _G.BuffIconCooldownViewer or {}
_G.BuffBarCooldownViewer = _G.BuffBarCooldownViewer or {}

local function CreateMockPool(categoryID)
    return {
        EnumerateActive = function()
            local entries = C_CooldownViewer.GetCooldownViewerCategorySet(categoryID, true)
            local i = 0
            return function()
                i = i + 1
                if entries[i] then
                    return GetOrCreateAdapter(entries[i])
                end
                return nil
            end
        end
    }
end

_G.EssentialCooldownViewer.itemFramePool = CreateMockPool(1)
_G.UtilityCooldownViewer.itemFramePool = CreateMockPool(2)
_G.BuffIconCooldownViewer.itemFramePool = CreateMockPool(3)
_G.BuffBarCooldownViewer.itemFramePool = CreateMockPool(4)
