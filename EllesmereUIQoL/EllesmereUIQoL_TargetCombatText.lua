if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EllesmereUIQoL_TargetCombatText.lua
-- The hits, heals and avoids your target takes, as scrolling text above the
-- target frame (the shared combat text scroll, EllesmereUIQoL_CombatTextScroll.lua).
--
-- Source: UNIT_COMBAT for "target", the event Blizzard's portrait hit indicator
-- (CombatFeedback) reads. C_CombatText follows one unit, which Self Combat Text
-- holds on the player. UNIT_COMBAT names no source, so it shows every hit the
-- target takes; Hide in Groups covers group play. The amount is secret: zero is
-- told apart with IsZeroValue, never by comparing it. Off, nothing is created
-- or registered.
--
-- Settings: the QoL profile's targetCombatText table. Unlock mode element
-- EUI_TargetCombatText; with nothing saved it sits above the target frame.
-------------------------------------------------------------------------------
local _, ns = ...
local EllesmereUI = _G.EllesmereUI
local PlainString, IsZeroValue = EllesmereUI.PlainString, EllesmereUI.IsZeroValue

local SMALL_SCALE = 0.75 -- glancing hits and partial avoids, as Blizzard's indicator

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
    damage = true, heal = true, avoid = true,
    hideInGroup = false,
    damageColor = { r = 1,   g = 1,    b = 1   },
    healColor   = { r = 0.1, g = 1,    b = 0.1 },
    avoidColor  = { r = 1,   g = 0.82, b = 0   },
}

-- UNIT_COMBAT events labelled with their global string (Blizzard's
-- CombatFeedbackText); WOUND, HEAL and ENERGIZE are handled apart.
local AVOID = {
    "MISS", "DODGE", "PARRY", "BLOCK", "EVADE", "IMMUNE", "DEFLECT", "ABSORB",
    "REFLECT", "RESIST", "INTERRUPT",
}
local avoidLabel = {}
local CRIT_FLAG  = { CRITICAL = true, CRUSHING = true }
-- flagText of a WOUND of zero: what the hit turned into
local ZERO_WOUND = { ABSORB = true, BLOCK = true, RESIST = true }

local ct = ns.NewCombatTextScroll({
    dbKey = "targetCombatText", defaults = DEFAULTS,
    unlockKey = "EUI_TargetCombatText", label = "Target Combat Text", order = 731,
    place = function(anchor)
        local tf = _G.EllesmereUIUnitFrames_Target
        if tf then
            anchor:SetPoint("BOTTOM", tf, "TOP", 0, 10)
        else
            anchor:SetPoint("BOTTOM", UIParent, "CENTER", 260, -140)
        end
    end,
})
local S = ct.S
local ev

local function Get(k) return ct:Get(k) end

local function ReadSettings()
    ct:ReadStyle()
    S.smallSize = S.size * SMALL_SCALE
    S.damage, S.heal, S.avoid = Get("damage"), Get("heal"), Get("avoid")
    S.hideInGroup = Get("hideInGroup") == true
    S.damageColor, S.healColor, S.avoidColor = Get("damageColor"), Get("healColor"), Get("avoidColor")
end

local function Build()
    ct:Build()
    for i = 1, #AVOID do
        local t = AVOID[i]
        local label = _G[t]
        if type(label) == "string" then avoidLabel[t] = label end
    end
    ev = CreateFrame("Frame")
end

local function EmitAvoid(key, small)
    local label = avoidLabel[key]
    if label then ct:Emit("%s", label, S.avoidColor, small and S.smallSize or S.size) end
end

-- UNIT_COMBAT payload: unit, event, flagText, amount (secret), schoolMask
local function OnUnitCombat(action, flag, amount)
    if S.hideInGroup and IsInGroup() then return end
    action, flag = PlainString(action), PlainString(flag)
    if action == "WOUND" then
        -- A WOUND of zero did nothing: absorbed, blocked, resisted or missed
        if IsZeroValue(amount) then
            if not S.avoid then return end
            if flag and ZERO_WOUND[flag] then
                EmitAvoid(flag, true)
            else
                EmitAvoid("MISS", false)
            end
            return
        end
        if not S.damage then return end
        local pt = (flag and CRIT_FLAG[flag] and S.critSize)
            or (flag == "GLANCING" and S.smallSize) or S.size
        ct:Emit("%s", ct:FormatAmount(amount), S.damageColor, pt)
    elseif action == "HEAL" then
        if not S.heal then return end
        ct:Emit("+%s", ct:FormatAmount(amount), S.healColor, flag == "CRITICAL" and S.critSize or S.size)
    elseif action and action ~= "ENERGIZE" and S.avoid then
        EmitAvoid(action, action == "BLOCK" or action == "IMMUNE")
    end
end

local function OnEvent(_, event, _unit, action, flag, amount)
    if event == "UNIT_COMBAT" then
        OnUnitCombat(action, flag, amount)
    elseif event == "PLAYER_TARGET_CHANGED" then
        ct:ClearAll()
    end
end

-- Registers only what the enabled categories need.
local function UpdateEvents()
    if S.damage or S.heal or S.avoid then
        ev:RegisterUnitEvent("UNIT_COMBAT", "target")
        ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    else
        ev:UnregisterEvent("UNIT_COMBAT")
        ev:UnregisterEvent("PLAYER_TARGET_CHANGED")
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
    else
        ev:UnregisterAllEvents()
        ct:ClearAll()
        ct.anchor:Hide()
    end
end

ns.TCT_Refresh = Refresh
ns.TCT_Get = Get
EllesmereUI._applyTargetCombatText = Refresh  -- RefreshAllAddons (profile swaps)

function ns.TCT_Set(k, v)
    ct:Settings()[k] = v
    Refresh()
end

-- QoL page reset: every setting back to its default, the anchor link dropped.
function ns.TCT_Reset()
    ct:ResetSettings()
    Refresh()
    ct:ApplyPos()
end
