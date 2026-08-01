local addonName, ns = ...
local EUICompat = _G.EUICompat

EUICompat.Cooldowns = {}

---@param spellID number
---@return table
function EUICompat.Cooldowns.GetSpellCooldown(spellID)
    local start, duration, enabled = 0, 0, 1

    if GetSpellCooldown then
        start, duration, enabled = GetSpellCooldown(spellID)
    end

    return {
        startTime = start or 0,
        duration = duration or 0,
        isEnabled = enabled == 1,
        modRate = 1,
    }
end

---@param spellID number
---@return table|nil
function EUICompat.Cooldowns.GetSpellCharges(spellID)
    if not GetSpellCharges then return nil end

    local currentCharges, maxCharges, cooldownStart, cooldownDuration, chargeModRate = GetSpellCharges(spellID)

    if currentCharges == nil then return nil end

    return {
        currentCharges = currentCharges or 0,
        maxCharges = maxCharges or 0,
        cooldownStartTime = cooldownStart or 0,
        cooldownDuration = cooldownDuration or 0,
        chargeModRate = chargeModRate or 1,
    }
end
