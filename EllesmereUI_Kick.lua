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

-- Secure unit context menu (12.0.7+).
-- 12.0.7 gates SecureUnitButton_OnClick: a "menu"/"togglemenu" action is silently
-- dropped unless C_ClickBindings has a binding for that button (the default
-- RightButton -> OpenContextMenu interaction is missing for many users / wiped by
-- click-cast setups). Re-opening the menu from insecure Lua instead TAINTS it, so
-- its protected items (Set Focus -> FocusUnit, Follow, etc.) throw
-- ADDON_ACTION_FORBIDDEN. The only way the protected items work is a SECURE open.
--
-- Fix: route right-click through the UN-gated "click" secure action to a hidden
-- child SecureActionButton, whose own SecureActionButton_OnClick (NOT gated -- only
-- SecureUnitButton_OnClick is) runs "togglemenu" securely. "useparent-unit" makes
-- the proxy resolve the unit from the parent unit button, so it works for static
-- frames AND header-managed (party/raid) frames whose unit changes. Call
-- AttachSecureUnitMenu(frame) on any unit button that needs a right-click menu
-- instead of setting *type2 = "togglemenu".
local menuProxies = setmetatable({}, { __mode = "k" })
-- 12.1: proxies are GLOBALLY NAMED so bindings can reach them via "/click
-- <name>" (macro transport). 12.1 broke the "click" secure action outright
-- (a typo: SecureTemplates.lua:564 calls HasAnyForbiddenAspects on the
-- mouse-button STRING instead of the delegate); /click hits
-- SecureActionButton_OnClick directly and is unaffected. On 12.0 the click
-- transport works and proxies stay anonymous.
local proxyCounter = 0

-- Create (once) and return the hidden SecureActionButton proxy for a unit button.
-- Use this when wiring a SPECIFIC click/key binding to the menu -- it does NOT
-- touch the frame's own type attributes (so it won't clobber other bindings).
function EllesmereUI.GetSecureMenuProxy(frame)
    if not frame then return end
    local proxy = menuProxies[frame]
    if not proxy then
        local proxyName
        if EllesmereUI.IS_121 then
            proxyCounter = proxyCounter + 1
            proxyName = "EUISecureMenuProxy" .. proxyCounter
        end
        proxy = CreateFrame("Button", proxyName, frame, "SecureActionButtonTemplate")
        proxy:SetSize(1, 1)
        proxy:SetAlpha(0)
        proxy:EnableMouse(false)          -- never catches real mouse; only the secure click delegate reaches it
        proxy:RegisterForClicks("AnyUp")
        proxy:SetAttribute("type", "togglemenu")
        -- The secure resolver looks up type by BUTTON SUFFIX (RightButton -> type2);
        -- the bare "type" may not fall back, so set every button explicitly.
        for i = 1, 5 do proxy:SetAttribute("type" .. i, "togglemenu") end
        proxy:SetAttribute("useparent-unit", true)
        -- Act on mouse-up regardless of the "cast on key down" CVar. Without this,
        -- SecureActionButton_OnClick's clickAction gate skips the menu action on the
        -- up-click when ActionButtonUseKeyDown is on (the delegate fires an up).
        proxy:SetAttribute("useOnKeyDown", false)
        menuProxies[frame] = proxy
    end
    return proxy
end

-- Same idea as GetSecureMenuProxy but for the "target" action. 12.0.7 gates a
-- raw "target" on unit buttons unless the button has a default ClickBindings
-- Interaction binding -- only plain unmodified left-click has one, so every other
-- target binding (other buttons, modifiers, keybinds) resolves to None and is
-- dropped. Routing those through this ungated SecureActionButton proxy restores
-- them. Used only for non-left-click target bindings (see ClickCast).
local targetProxies = setmetatable({}, { __mode = "k" })
function EllesmereUI.GetSecureTargetProxy(frame)
    if not frame then return end
    local proxy = targetProxies[frame]
    if not proxy then
        local proxyName
        if EllesmereUI.IS_121 then
            proxyCounter = proxyCounter + 1
            proxyName = "EUISecureTargetProxy" .. proxyCounter
        end
        proxy = CreateFrame("Button", proxyName, frame, "SecureActionButtonTemplate")
        proxy:SetSize(1, 1)
        proxy:SetAlpha(0)
        proxy:EnableMouse(false)          -- never catches real mouse; only the secure click delegate reaches it
        proxy:RegisterForClicks("AnyUp")
        proxy:SetAttribute("type", "target")
        -- type looked up by button SUFFIX (RightButton -> type2); set every button.
        for i = 1, 5 do proxy:SetAttribute("type" .. i, "target") end
        proxy:SetAttribute("useparent-unit", true)
        -- Act on the up-click regardless of the "cast on key down" CVar (same
        -- clickAction gate that bit the menu proxy).
        proxy:SetAttribute("useOnKeyDown", false)
        targetProxies[frame] = proxy
    end
    return proxy
end

-- Route a unit button's default RIGHT-CLICK to the secure menu proxy via the
-- ungated "click" action. Clears any specific type2 so the wildcard governs.
function EllesmereUI.AttachSecureUnitMenu(frame)
    if not frame then return end
    local proxy = EllesmereUI.GetSecureMenuProxy(frame)
    frame:SetAttribute("type2", nil)
    if EllesmereUI.IS_121 then
        -- Macro transport ("/click <proxy>") instead of the "click" action:
        -- the 12.1 click action crashes on a Blizzard typo (see above).
        frame:SetAttribute("*type2", "macro")
        frame:SetAttribute("*macrotext2", "/click " .. proxy:GetName())
        frame:SetAttribute("*clickbutton2", nil)
    else
        frame:SetAttribute("*type2", "click")
        frame:SetAttribute("*clickbutton2", proxy)
    end
    return proxy
end

local kickFrame = CreateFrame("Frame")
kickFrame:RegisterEvent("PLAYER_LOGIN")
kickFrame:RegisterEvent("SPELLS_CHANGED")
kickFrame:SetScript("OnEvent", function()
    RefreshKickAbility()
end)

if UnitGUID("player") then
    RefreshKickAbility()
end
