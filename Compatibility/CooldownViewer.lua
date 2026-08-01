local addonName, ns = ...

_G.C_CooldownViewer = _G.C_CooldownViewer or {}

-- Internal State
local definitions = {} -- cdID -> def
local entriesByCategory = {} -- cat -> array of defs
local knownSpellsCache = {} -- cdID -> { isKnown = bool, activeSpellID = number, activeAuraSpellID = number }

-- Event Tracker Frame
local tracker = CreateFrame("Frame")

-- Registration
function C_CooldownViewer.RegisterDefinition(def)
    if not def.cooldownID then return end
    definitions[def.cooldownID] = def
    entriesByCategory[def.category] = entriesByCategory[def.category] or {}
    table.insert(entriesByCategory[def.category], def)
end

-- Retail API: GetCooldownViewerCategorySet
-- Returns an array of cooldownIDs for the category
function C_CooldownViewer.GetCooldownViewerCategorySet(category, includeUnknown)
    local results = {}
    local entries = entriesByCategory[category] or {}

    for _, def in ipairs(entries) do
        local state = knownSpellsCache[def.cooldownID]
        local isKnown = state and state.isKnown or false
        if includeUnknown or isKnown then
            table.insert(results, def.cooldownID)
        end
    end

    -- Sort by order
    table.sort(results, function(a, b)
        local defA = definitions[a]
        local defB = definitions[b]
        return (defA and defA.order or 999) < (defB and defB.order or 999)
    end)

    return results
end

local function ParseAura(unit, index, filter)
    local name, rank, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellID = UnitAura(unit, index, filter)
    if not name then return nil end
    return { spellID = spellID, duration = duration or 0, expirationTime = expirationTime or 0, count = count or 0 }
end

local function GetPlayerAura(spellID)
    if not spellID then return nil end
    for i = 1, 40 do
        local aura = ParseAura("player", i, "HELPFUL")
        if not aura then break end
        if aura.spellID == spellID then return aura end
    end
    for i = 1, 40 do
        local aura = ParseAura("player", i, "HARMFUL")
        if not aura then break end
        if aura.spellID == spellID then return aura end
    end
    return nil
end

-- Retail API: GetCooldownViewerCooldownInfo
-- Returns cooldown info table, calculated synchronously on-demand to avoid stale state.
function C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
    local def = definitions[cooldownID]
    local state = knownSpellsCache[cooldownID]

    if not def then return nil end

    local activeSpellID = state and state.activeSpellID or def.spellID
    local activeAuraSpellID = state and state.activeAuraSpellID or activeSpellID

    local info = {
        cooldownID = cooldownID,
        spellID = activeSpellID,
        overrideSpellID = def.overrideSpellID,
    }

    if state and state.isKnown then
        if def.trackingType == "cooldown" or def.trackingType == "cooldown_and_aura" then
            if activeSpellID then
                local start, duration, enabled = GetSpellCooldown(activeSpellID)
                info.cooldownStart = start or 0
                info.cooldownDuration = duration or 0
                info.cooldownEnabled = enabled == 1
            end
        end

        if def.trackingType == "aura" or def.trackingType == "cooldown_and_aura" then
            if activeAuraSpellID then
                local aura = GetPlayerAura(activeAuraSpellID)
                if aura then
                    info.auraActive = true
                    info.auraDuration = aura.duration
                    info.auraExpiration = aura.expirationTime
                    info.auraStacks = aura.count
                else
                    info.auraActive = false
                end
            end
        end
    end

    return info
end

-- WotLK Tracker Logic (Known spells cache only, evaluated rarely)
local function RefreshKnownSpells()
    local _, playerClass = UnitClass("player")

    for cdID, def in pairs(definitions) do
        local allowed = true
        if def.class and def.class ~= playerClass then allowed = false end

        local activeSpellID = nil
        local isKnown = false

        if allowed then
            if def.spellIDs then
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

        local state = knownSpellsCache[cdID] or {}
        state.isKnown = isKnown
        state.activeSpellID = activeSpellID or def.spellID
        state.activeAuraSpellID = def.auraSpellID or state.activeSpellID

        knownSpellsCache[cdID] = state
    end
end

-- Events
tracker:RegisterEvent("PLAYER_LOGIN")
tracker:RegisterEvent("SPELLS_CHANGED")
tracker:RegisterEvent("PLAYER_TALENT_UPDATE")

tracker:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" or event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        RefreshKnownSpells()
    end
end)

_G.EssentialCooldownViewer = _G.EssentialCooldownViewer or {}
_G.UtilityCooldownViewer = _G.UtilityCooldownViewer or {}
_G.BuffIconCooldownViewer = _G.BuffIconCooldownViewer or {}
_G.BuffBarCooldownViewer = _G.BuffBarCooldownViewer or {}

local function MockPool(cat)
    return {
        EnumerateActive = function()
            local entries = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
            local i = 0
            return function()
                i = i + 1
                if entries[i] then
                    return {
                        cooldownID = entries[i],
                        GetSpellID = function(self) return C_CooldownViewer.GetCooldownViewerCooldownInfo(self.cooldownID).spellID end,
                        cooldownInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(entries[i])
                    }
                end
                return nil
            end
        end
    }
end

_G.EssentialCooldownViewer.itemFramePool = MockPool(1)
_G.UtilityCooldownViewer.itemFramePool = MockPool(2)
_G.BuffIconCooldownViewer.itemFramePool = MockPool(3)
_G.BuffBarCooldownViewer.itemFramePool = MockPool(4)
