local addonName, ns = ...
local EUICompat = _G.EUICompat

local Provider = {}
Provider.__index = Provider

-- Category Constants
EUICompat.CDM_CATEGORY_ESSENTIAL = 1
EUICompat.CDM_CATEGORY_UTILITY   = 2
EUICompat.CDM_CATEGORY_BUFF_ICON = 3
EUICompat.CDM_CATEGORY_BUFF_BAR  = 4

function Provider:New()
    local p = {
        callbacks = {},
        definitions = {}, -- cooldownID -> definition
        entriesByCategory = {}, -- category -> array of definitions
        runtimeState = {}, -- cooldownID -> state
    }
    setmetatable(p, Provider)
    return p
end

function Provider:GetEntries(category, includeUnknown)
    local results = {}
    local entries = self.entriesByCategory[category] or {}
    for _, def in ipairs(entries) do
        local state = self.runtimeState[def.cooldownID]
        local isKnown = state and state.isKnown or false
        if includeUnknown or isKnown then
            table.insert(results, def)
        end
    end
    -- TODO: handle sorting by def.order
    table.sort(results, function(a, b) return (a.order or 999) < (b.order or 999) end)
    return results
end

function Provider:GetEntry(cooldownID)
    return self.definitions[cooldownID]
end

function Provider:GetRuntimeState(cooldownID)
    return self.runtimeState[cooldownID]
end

function Provider:RegisterCallback(callback)
    table.insert(self.callbacks, callback)
end

function Provider:Fire(event, cooldownID)
    for _, cb in ipairs(self.callbacks) do
        local ok, err = pcall(cb, event, cooldownID)
        if not ok then
            EUICompat.Debug:Warn("CDM Callback error: %s", tostring(err))
        end
    end
end

function Provider:RefreshDefinitions()
    -- Subclass responsibility
end

function Provider:RefreshRuntimeState()
    -- Subclass responsibility
end

function Provider:RegisterDefinition(def)
    if not def.cooldownID then
        EUICompat.Debug:Warn("Attempted to register definition without cooldownID")
        return
    end
    self.definitions[def.cooldownID] = def
    self.entriesByCategory[def.category] = self.entriesByCategory[def.category] or {}
    table.insert(self.entriesByCategory[def.category], def)
end

EUICompat.CDM.ProviderBase = Provider

-- Select active provider
EUICompat.CDM.ActiveProvider = nil -- Instantiated at the end of WotLKProvider.lua/RetailProvider.lua
