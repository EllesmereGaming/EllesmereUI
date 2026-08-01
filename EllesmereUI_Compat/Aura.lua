local addonName, ns = ...
local EUICompat = _G.EUICompat

EUICompat.Aura = {}

local function ParseAura(unit, index, filter)
    local name, rank, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellID, canApplyAura, isBossDebuff, isCastByPlayer, nameplateShowAll, timeMod

    if UnitAura then
        name, rank, icon, count, debuffType, duration, expirationTime, source, isStealable, nameplateShowPersonal, spellID, canApplyAura, isBossDebuff, isCastByPlayer, nameplateShowAll, timeMod = UnitAura(unit, index, filter)
    end

    if not name then return nil end

    return {
        name = name,
        icon = icon,
        applications = count or 0,
        dispelName = debuffType,
        duration = duration or 0,
        expirationTime = expirationTime or 0,
        sourceUnit = source,
        isStealable = isStealable,
        spellID = spellID,
        isHelpful = filter == "HELPFUL",
        isHarmful = filter == "HARMFUL",
        isBossAura = isBossDebuff,
        canApplyAura = canApplyAura,
        nameplateShowAll = nameplateShowAll,
        auraInstanceID = nil, -- Not available in WotLK
    }
end

function EUICompat.Aura.GetPlayerAura(spellID)
    if not spellID then return nil end

    -- Check buffs
    for i = 1, 40 do
        local aura = ParseAura("player", i, "HELPFUL")
        if not aura then break end
        if aura.spellID == spellID then return aura end
    end

    -- Check debuffs
    for i = 1, 40 do
        local aura = ParseAura("player", i, "HARMFUL")
        if not aura then break end
        if aura.spellID == spellID then return aura end
    end

    return nil
end
