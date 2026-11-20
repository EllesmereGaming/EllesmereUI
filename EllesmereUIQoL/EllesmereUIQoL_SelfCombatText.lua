if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EllesmereUIQoL_SelfCombatText.lua
-- Self combat text (damage taken, heals received, avoids, power gains, combat
-- enter/leave) drawn above the player frame in place of Blizzard's
-- WorldFrame-pinned scrolling text. The display is the shared combat text
-- scroll (EllesmereUIQoL_CombatTextScroll.lua).
--
-- Blizzard's CombatText frame is only hidden, never written to: its OnEvent
-- bails while hidden. Event data from C_CombatText.GetCurrentEventInfo is
-- secret, so values only reach C formatters and FontString setters; nothing
-- here compares or does arithmetic on them. Off, nothing is created or
-- registered.
--
-- Settings: the QoL profile's selfCombatText table, read into a cache by
-- Refresh. Login (EllesmereUIQoL.lua), profile swaps (RefreshAllAddons) and
-- option changes all route through Refresh. The anchor box is an unlock mode
-- element (EUI_SelfCombatText): unlock mode applies saved positions and
-- anchor links; with nothing saved it sits above the player frame.
-------------------------------------------------------------------------------
local _, ns = ...
local EllesmereUI = _G.EllesmereUI
local IsSecret, PlainString, IsZeroValue = EllesmereUI.IsSecret, EllesmereUI.PlainString, EllesmereUI.IsZeroValue

local DEFAULTS = {
    enabled = false,
    size = 16, critScale = 1.5, rise = 80, duration = 1.9,
    stagger = true,
    anim = "straight",     -- straight | fountain | static
    direction = "up",      -- up | down
    font = "__combat",     -- __combat (CombatTextFont), __global (QoL font) or a font key
    outline = "OUTLINE",   -- NONE | OUTLINE | THICKOUTLINE
    shadow = false,
    abbreviate = false,
    damage = true, heal = true, avoid = true, combat = true, power = false,
    damageColor = { r = 1,   g = 0.1, b = 0.1 },
    healColor   = { r = 0.1, g = 1,   b = 0.1 },
    avoidColor  = { r = 1,   g = 1,   b = 1   },
    combatColor = { r = 1,   g = 0.1, b = 0.1 },
    powerColor  = { r = 0.1, g = 0.1, b = 1   },
}

-- type -> isCrit
local DAMAGE = {
    DAMAGE = false, SPELL_DAMAGE = false, DAMAGE_SHIELD = false,
    DAMAGE_CRIT = true, SPELL_DAMAGE_CRIT = true,
}
local HEAL = {
    HEAL = false, PERIODIC_HEAL = false,
    HEAL_CRIT = true, PERIODIC_HEAL_CRIT = true,
}
-- Avoid types; Build fills avoidLabel with their COMBAT_TEXT_* strings.
local AVOID = {
    "MISS", "DODGE", "PARRY", "EVADE", "IMMUNE", "DEFLECT", "REFLECT", "RESIST", "BLOCK", "ABSORB",
}
local avoidLabel = {}
local ENERGIZE = { ENERGIZE = true, PERIODIC_ENERGIZE = true }

local ct = ns.NewCombatTextScroll({
    dbKey = "selfCombatText", defaults = DEFAULTS,
    unlockKey = "EUI_SelfCombatText", label = "Self Combat Text", order = 730,
    place = function(anchor)
        local pf = _G.EllesmereUIUnitFrames_Player
        if pf then
            anchor:SetPoint("BOTTOM", pf, "TOP", 0, 10)
        else
            anchor:SetPoint("BOTTOM", UIParent, "CENTER", 0, -140)
        end
    end,
})
-- Settings as the message path reads them, refilled by Refresh
local S = ct.S
local ev

local function Get(k) return ct:Get(k) end

local function ReadSettings()
    ct:ReadStyle()
    S.damage, S.heal, S.avoid, S.combat = Get("damage"), Get("heal"), Get("avoid"), Get("combat")
    S.power = Get("power")
    S.damageColor, S.healColor = Get("damageColor"), Get("healColor")
    S.avoidColor, S.combatColor = Get("avoidColor"), Get("combatColor")
    S.powerColor = Get("powerColor")
end

local function Build()
    ct:Build()
    -- The plain and SPELL_ forms of an avoid share Blizzard's label.
    for i = 1, #AVOID do
        local t = AVOID[i]
        local label = _G["COMBAT_TEXT_" .. t]
        avoidLabel[t], avoidLabel["SPELL_" .. t] = label, label
    end
    ev = CreateFrame("Frame")
end

local function Emit(fmt, value, c, crit, label)
    ct:Emit(fmt, value, c, crit and S.critSize or S.size, label)
end

local function FormatAmount(n) return ct:FormatAmount(n) end

local function SetUnit()
    C_CombatText.SetActiveUnit(UnitHasVehicleUI("player") and "vehicle" or "player")
end

-- A power token's localized name (MANA -> "Mana"); nil when the token is secret
-- or names no string, and the gain then shows without one.
local function PowerLabel(token)
    token = PlainString(token)
    local name = token and _G[token]
    if type(name) == "string" then return name end
end

-- data = amount, arg3 = power token. A plain amount of zero or less is no gain.
-- A secret one is never compared: IsZeroValue tells a zero (a gain at a full
-- resource) without reading it, and any other secret gain shows.
local function EmitPower()
    local amount, token = C_CombatText.GetCurrentEventInfo()
    if IsSecret(amount) then
        if IsZeroValue(amount) then return end
    elseif not ((amount and tonumber(amount) or 0) > 0) then
        return
    end
    local label = PowerLabel(token)
    Emit(label and "+%s %s" or "+%s", FormatAmount(amount), S.powerColor, false, label)
end

local function OnEvent(_, event, arg1, arg2)
    if event == "COMBAT_TEXT_UPDATE" then
        -- data = amount (damage) or source name (heals); arg3 = heal amount
        local crit = DAMAGE[arg1]
        if crit ~= nil then
            if not S.damage then return end
            local data = C_CombatText.GetCurrentEventInfo()
            Emit("-%s", FormatAmount(data), S.damageColor, crit)
            return
        end
        crit = HEAL[arg1]
        if crit ~= nil then
            if not S.heal then return end
            local _, arg3 = C_CombatText.GetCurrentEventInfo()
            Emit("+%s", FormatAmount(arg3), S.healColor, crit)
            return
        end
        local label = S.avoid and avoidLabel[arg1]
        if label then
            Emit("%s", label, S.avoidColor, false)
        elseif S.power and ENERGIZE[arg1] then
            EmitPower()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        Emit("%s", _G.ENTERING_COMBAT or "+Combat", S.combatColor, false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        Emit("%s", _G.LEAVING_COMBAT or "-Combat", S.combatColor, false)
    elseif event == "UNIT_ENTERED_VEHICLE" then
        C_CombatText.SetActiveUnit(arg2 and "vehicle" or "player")
    elseif event == "UNIT_EXITING_VEHICLE" then
        C_CombatText.SetActiveUnit("player")
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_CombatText" and _G.CombatText then
            _G.CombatText:Hide()
            ev:UnregisterEvent("ADDON_LOADED")
        end
    end
end

-- Registers only the events the enabled categories need.
local function UpdateEvents()
    if S.damage or S.heal or S.avoid or S.power then
        ev:RegisterEvent("COMBAT_TEXT_UPDATE")
        ev:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        ev:RegisterUnitEvent("UNIT_EXITING_VEHICLE", "player")
    else
        ev:UnregisterEvent("COMBAT_TEXT_UPDATE")
        ev:UnregisterEvent("UNIT_ENTERED_VEHICLE")
        ev:UnregisterEvent("UNIT_EXITING_VEHICLE")
    end
    if S.combat then
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ev:UnregisterEvent("PLAYER_REGEN_DISABLED")
        ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function Refresh()
    local want = Get("enabled") == true
    if want == ct.active then
        if want then
            ReadSettings()
            ct:ApplyAnim()
            UpdateEvents()
        end
        return
    end
    ct.active = want
    if want then
        if not ct.anchor then Build() end
        ReadSettings()
        ct:ApplyAnim()
        ct.anchor:Show()
        ev:SetScript("OnEvent", OnEvent)
        UpdateEvents()
        SetUnit()
        if _G.CombatText then
            _G.CombatText:Hide()
        else
            ev:RegisterEvent("ADDON_LOADED")
        end
    else
        ev:UnregisterAllEvents()
        ct.anchor:Hide()
        if _G.CombatText then _G.CombatText:Show() end
    end
end

ns.SCT_Refresh = Refresh
ns.SCT_Get = Get
EllesmereUI._applySelfCombatText = Refresh  -- RefreshAllAddons (profile swaps)

function ns.SCT_Set(k, v)
    ct:Settings()[k] = v
    Refresh()
end

-- QoL page reset: every setting back to its default, the anchor link dropped.
function ns.SCT_Reset()
    ct:ResetSettings()
    Refresh()
    ct:ApplyPos()
end
