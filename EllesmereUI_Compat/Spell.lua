local addonName, ns = ...
local EUICompat = _G.EUICompat

EUICompat.Spell = {}

-- Normalized Spell API
---@param spellID number
---@return table|nil
function EUICompat.Spell.GetInfo(spellID)
    if not spellID then return nil end

    local name, _, icon, castTime, minRange, maxRange
    if GetSpellInfo then
        name, _, icon, _, _, _, castTime, minRange, maxRange = GetSpellInfo(spellID)
    end

    if not name then return nil end

    return {
        spellID = spellID,
        name = name,
        iconID = icon,
        castTime = castTime or 0,
        minRange = minRange or 0,
        maxRange = maxRange or 0,
        originalIconID = icon,
        isPassive = IsPassiveSpell and IsPassiveSpell(spellID) or false,
        isKnown = EUICompat.Spell.IsKnown(spellID),
    }
end

function EUICompat.Spell.IsKnown(spellID)
    if not spellID then return false end

    if IsSpellKnown then
        return IsSpellKnown(spellID)
    elseif IsPlayerSpell then
        return IsPlayerSpell(spellID)
    end

    -- Fallback for WotLK if IsSpellKnown/IsPlayerSpell fails or isn't reliable for all spells
    local name = GetSpellInfo(spellID)
    if not name then return false end

    if GetSpellInfo(name) then
        return true
    end

    return false
end
