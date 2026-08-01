local addonName, ns = ...
local EUICompat = _G.EUICompat

if not EUICompat.IsWotLK then return end

local WotLKProvider = setmetatable({}, { __index = EUICompat.CDM.ProviderBase })
WotLKProvider.__index = WotLKProvider

function WotLKProvider:New()
    local p = EUICompat.CDM.ProviderBase.New(self)
    setmetatable(p, WotLKProvider)
    return p
end

-- Refresh logic for known spells based on definitions
function WotLKProvider:RefreshDefinitions()
    local _, playerClass = UnitClass("player")

    for cdID, def in pairs(self.definitions) do
        -- Check class restriction
        local allowed = true
        if def.class and def.class ~= playerClass then
            allowed = false
        end

        local activeSpellID = nil
        local isKnown = false

        if allowed then
            if def.spellIDs then
                -- Ranked spells: find highest known rank
                for i = #def.spellIDs, 1, -1 do
                    local sID = def.spellIDs[i]
                    if EUICompat.Spell.IsKnown(sID) then
                        isKnown = true
                        activeSpellID = sID
                        break
                    end
                end
            elseif def.spellID then
                if EUICompat.Spell.IsKnown(def.spellID) then
                    isKnown = true
                    activeSpellID = def.spellID
                end
            end

            -- Override resolver logic (talents, etc.)
            if def.resolveSpellID then
                local resID = def:resolveSpellID()
                if resID then
                    isKnown = true
                    activeSpellID = resID
                end
            end
        end

        local state = self.runtimeState[cdID] or { cooldownID = cdID }
        state.isKnown = isKnown
        state.activeSpellID = activeSpellID or def.spellID
        state.activeAuraSpellID = def.auraSpellID or state.activeSpellID

        self.runtimeState[cdID] = state
    end

    self:Fire("EUI_CDM_DEFINITIONS_CHANGED")
end

function WotLKProvider:RefreshRuntimeState()
    for cdID, def in pairs(self.definitions) do
        local state = self.runtimeState[cdID]
        if state and state.isKnown then
            local spellID = state.activeSpellID

            if def.trackingType == "cooldown" or def.trackingType == "cooldown_and_aura" then
                if spellID then
                    local cd = EUICompat.Cooldowns.GetSpellCooldown(spellID)
                    if cd then
                        state.cooldownStart = cd.startTime
                        state.cooldownDuration = cd.duration
                        state.cooldownEnabled = cd.isEnabled
                    end

                    local charges = EUICompat.Cooldowns.GetSpellCharges(spellID)
                    if charges then
                        state.charges = charges.currentCharges
                        state.maxCharges = charges.maxCharges
                        state.chargeStart = charges.cooldownStartTime
                        state.chargeDuration = charges.cooldownDuration
                    end
                end
            end

            if def.trackingType == "aura" or def.trackingType == "cooldown_and_aura" then
                local auraID = state.activeAuraSpellID
                if auraID then
                    local aura = EUICompat.Aura.GetPlayerAura(auraID)
                    if aura then
                        state.auraActive = true
                        state.auraDuration = aura.duration
                        state.auraExpiration = aura.expirationTime
                        state.auraStacks = aura.applications
                    else
                        state.auraActive = false
                    end
                end
            end
        end
    end

    self:Fire("EUI_CDM_RUNTIME_UPDATED")
end

EUICompat.CDM.WotLKProvider = WotLKProvider

EUICompat.CDM.ActiveProvider = WotLKProvider:New()
