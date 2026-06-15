--------------------------------------------------------------------------------
--  EllesmereUI_Kick.lua
--  Shared interrupt spell lookup and cast-bar tint helpers for nameplates
--  and unit frames.
--------------------------------------------------------------------------------

local kickSpellsByClass = {
    DEATHKNIGHT = { 47528 },
    WARRIOR = { 6552 },
    WARLOCK = { 19647, 89766, 119910, 1276467, 132409 },
    SHAMAN = { 57994 },
    ROGUE = { 1766 },
    PRIEST = { 15487 },
    PALADIN = { 31935, 96231 },
    MONK = { 116705 },
    MAGE = { 2139 },
    HUNTER = { 187707, 147362 },
    EVOKER = { 351338 },
    DRUID = { 38675, 78675, 106839 },
    DEMONHUNTER = { 183752 },
}

local activeKickSpell

local function RefreshKickAbility()
    local playerClass = UnitClassBase("player")
    local classKicks = kickSpellsByClass[playerClass]
    activeKickSpell = nil
    if not classKicks then return end
    for i = 1, #classKicks do
        local spellId = classKicks[i]
        if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
            local known = C_SpellBook.IsSpellKnownOrInSpellBook(spellId)
            local petKnown = Enum and Enum.SpellBookSpellBank
                and C_SpellBook.IsSpellKnownOrInSpellBook(spellId, Enum.SpellBookSpellBank.Pet)
            if known or petKnown then
                activeKickSpell = spellId
            end
        elseif IsSpellKnown and IsSpellKnown(spellId) then
            activeKickSpell = spellId
        end
    end
end

local function ComputeCastBarTint(readyTint, baseTint)
    if not activeKickSpell then
        return baseTint.r, baseTint.g, baseTint.b
    end
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then
        return baseTint.r, baseTint.g, baseTint.b
    end
    if not (C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean) then
        return baseTint.r, baseTint.g, baseTint.b
    end
    local cdTime = C_Spell.GetSpellCooldownDuration(activeKickSpell)
    if not (cdTime and cdTime.IsZero) then
        return baseTint.r, baseTint.g, baseTint.b
    end
    local offCooldown = cdTime:IsZero()
    local rVal = C_CurveUtil.EvaluateColorValueFromBoolean(offCooldown, baseTint.r, readyTint.r)
    local gVal = C_CurveUtil.EvaluateColorValueFromBoolean(offCooldown, baseTint.g, readyTint.g)
    local bVal = C_CurveUtil.EvaluateColorValueFromBoolean(offCooldown, baseTint.b, readyTint.b)
    return rVal, gVal, bVal
end

EllesmereUI = EllesmereUI or {}
EllesmereUI.GetActiveKickSpell = function()
    return activeKickSpell
end
EllesmereUI.RefreshKickAbility = RefreshKickAbility
EllesmereUI.ComputeCastBarTint = ComputeCastBarTint

local kickFrame = CreateFrame("Frame")
kickFrame:RegisterEvent("PLAYER_LOGIN")
kickFrame:RegisterEvent("SPELLS_CHANGED")
kickFrame:SetScript("OnEvent", function()
    RefreshKickAbility()
end)

if UnitGUID("player") then
    RefreshKickAbility()
end
