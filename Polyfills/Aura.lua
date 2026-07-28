-- C_UnitAuras & C_UA
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
        return _G.EllesmereUI.DurationObject:Create(expirationTime - duration, duration, expirationTime)
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
