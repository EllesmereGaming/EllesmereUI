if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_Kick.lua
--  Shared interrupt spell lookup and cast-bar tint helpers for nameplates
--  and unit frames.
--------------------------------------------------------------------------------

-- Retail interrupts by class, from the suite's interrupt data
-- (EllesmereUI_KickData.lua): every interrupt of the class, each list ending
-- with its main one, and a warlock's with the demon command spells and the
-- Grimoire of Sacrifice Spell Lock.
local kickSpellsByClass = EllesmereUI.KickData.ClassLists()

-- WoW Forever (Classic) interrupts. Classic abilities have one spell id per
-- rank and these lists are used INSTEAD of kickSpellsByClass there, never
-- merged into it: several Classic ids are different spells on retail (16979
-- is Wild Charge, 8042 is a plain Earth Shock), so a shared table would make
-- a retail Druid or Shaman resolve a kick they do not have.
-- Each class holds groups of ranks, low to high so the last known one wins (the
-- cooldown is shared across ranks). A group may name the stance it needs and
-- only counts while one of those stances is up: `stances` are gapless warrior
-- stance indexes, `formIds` druid form IDs (Forever orders the druid stance bar
-- the vanilla way, so druids are read by form ID, as in EllesmereUI_Range.lua).
-- Debuff ids (Kick - Silenced) are left out. The Felhunter's Spell Lock is a pet
-- spell, found in the pet spellbook like retail's demon interrupts.
local WARRIOR_STANCE = { BATTLE = 1, DEFENSIVE = 2, BERSERKER = 3 }
local DRUID_FORM_ID = { BEAR = 5, DIRE_BEAR = 8 }
local foreverKicksByClass = {
    WARRIOR = {
        { 72, 1671, 1672, stances = { WARRIOR_STANCE.BATTLE, WARRIOR_STANCE.DEFENSIVE } }, -- Shield Bash
        { 6552, 6554, stances = { WARRIOR_STANCE.BERSERKER } },                           -- Pummel
    },
    ROGUE = { { 1766, 1767, 1768, 1769 } },                       -- Kick
    MAGE = { { 2139 } },                                          -- Counterspell
    SHAMAN = { { 8042, 8044, 8045, 8046, 10412, 10413, 10414 } }, -- Earth Shock
    PRIEST = { { 15487 } },                                       -- Silence
    WARLOCK = { { 19244, 19647 } },                               -- Spell Lock (Felhunter)
    DRUID = {
        { 16979, formIds = { DRUID_FORM_ID.BEAR, DRUID_FORM_ID.DIRE_BEAR } }, -- Feral Charge
    },
}

local function InList(list, value)
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

local function KickGroupFormOk(group)
    if group.stances then return InList(group.stances, GetShapeshiftForm()) end
    if group.formIds then return InList(group.formIds, GetShapeshiftFormID()) end
    return true
end

-- Which spellbook knows a spell: "pet" (a summoned demon), "player", or nil.
local function KickBank(spellId)
    if C_SpellBook and C_SpellBook.IsSpellKnownOrInSpellBook then
        if Enum and Enum.SpellBookSpellBank
            and C_SpellBook.IsSpellKnownOrInSpellBook(spellId, Enum.SpellBookSpellBank.Pet) then
            return "pet"
        elseif C_SpellBook.IsSpellKnownOrInSpellBook(spellId) then
            return "player"
        end
    elseif IsSpellKnown and IsSpellKnown(spellId) then
        return "player"
    end
end

local activeKickSpell

-- A summoned demon's interrupt beats anything the player bank still reports.
--
-- The two banks were previously treated as one pool and the loop kept the LAST match,
-- so resolution depended on this table's ORDER rather than on what the player can
-- actually cast. A Demonology Warlock with a Felguard out has Axe Toss as their only
-- interrupt, but a later Warlock entry also answered as known, overwrote it, and left
-- the cast bar reading the cooldown of a spell that never fires. Kicking changed
-- nothing on screen: the bar stayed tinted "interrupt ready" and the kick-prediction
-- tick, which reads the same spell, was wrong for the same reason. Other specs were
-- unaffected because only one of their entries ever answers.
--
-- Last-match is preserved WITHIN each bank so no other class's resolution
-- changes; only the pet-over-player precedence is new.
local function RefreshKickAbility()
    local playerClass = UnitClassBase("player")
    local isForever = EllesmereUI.IS_FOREVER == true
    local kicks = isForever and foreverKicksByClass or kickSpellsByClass
    local classKicks = kicks[playerClass]
    activeKickSpell = nil
    if not classKicks then return end
    local petHit, playerHit
    -- Retail entries are bare spell ids; Forever entries are rank groups.
    for i = 1, #classKicks do
        local entry = classKicks[i]
        local isGroup = type(entry) == "table"
        if not isGroup or KickGroupFormOk(entry) then
            for j = 1, isGroup and #entry or 1 do
                local spellId = isGroup and entry[j] or entry
                local bank = KickBank(spellId)
                if bank == "pet" then petHit = spellId elseif bank == "player" then playerHit = spellId end
            end
        end
    end
    activeKickSpell = petHit or playerHit
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
-- Fix: route right-click through a hidden child SecureActionButton, whose own
-- SecureActionButton_OnClick (NOT gated -- only SecureUnitButton_OnClick is) runs
-- the menu action securely. "useparent-unit" makes the proxy resolve the unit
-- from the parent unit button, so it works for static frames AND header-managed
-- (party/raid) frames whose unit changes. Call AttachSecureUnitMenu(frame) on any
-- unit button that needs a right-click menu instead of setting *type2 = "togglemenu".
--
-- The proxy runs the "togglemenu" secure action (SecureTemplates.lua, "Unused
-- by Blizzard code"). Its classifier walks a UnitIsUnit /
-- UnitIsOtherPlayersBattlePet chain that misfires for a raid member whose unit
-- data has not streamed (zoned elsewhere) and opens a pet menu; only
-- boss/arena/party/focus tokens are special-cased ahead of that chain.
-- The "menu" action (what Blizzard's own unit buttons use: SECURE_ACTIONS.menu
-- -> ExecuteAttribute("menu-function"), with an opener such as
-- CompactUnitFrame_OpenMenu that has no battle-pet probe) is NOT usable from an
-- addon: ExecuteAttribute runs the function with the taint of the execution
-- that SET the attribute -- a menu-function written from our Lua opens a
-- tainted menu (Set Focus throws), unlike string attributes such as macrotext
-- -- and writing it from a secure click instead (a leading "/click <proxy>
-- Button4" line driving the "attribute" secure action) never landed the
-- attribute at all (menu-function stayed nil; no menu opened). Both
-- field-tested 2026-08-26; do not re-attempt without new engine facts.
--
-- Backstop: a PET-family menu opening for a raid/party token whose GUID is a
-- Player is the classifier misfire above -- re-open the correct player menu.
-- The re-open runs from this (tainted) hook, so protected items and secure
-- follow-on panels (View Houses -> Visit House) fail for THAT menu instance
-- only; the trade for not showing a pet menu on a player. Legitimate
-- pet menus (unit "pet"/"partypetN"/"raidpetN") never match the signature, and
-- the correct which comes from the TOKEN (no unit APIs -- UnitInRaid/identity
-- reads can be SECRET for exactly these unstreamed units). Installed lazily
-- with the first menu proxy; zero cost until a menu actually opens.
local menuFixHooked = false
local function InstallMenuClassifierFix()
    if menuFixHooked or type(UnitPopup_OpenMenu) ~= "function" then return end
    menuFixHooked = true
    local reopening = false
    hooksecurefunc("UnitPopup_OpenMenu", function(which, contextData)
        if reopening then return end
        if which ~= "PET" and which ~= "OTHERPET" and which ~= "OTHERBATTLEPET" then return end
        local unit = contextData and contextData.unit
        if type(unit) ~= "string" then return end
        local lu = unit:lower()
        local isRaidToken = lu:match("^raid[0-9]+$") ~= nil
        if not isRaidToken and not lu:match("^party[0-9]+$") then return end
        local guid = UnitGUID(unit)
        if issecretvalue and issecretvalue(guid) then return end
        if type(guid) ~= "string" or not guid:find("^Player%-") then return end
        reopening = true
        -- Menu.ModifyMenu callbacks run synchronously inside this call; the
        -- flag lets EllesmereUI_MenuFallbacks.lua swap the protected items of
        -- THIS (tainted) menu only for its secure replacements, and the call
        -- after the open docks its Set Focus / Follow strip to the menu.
        EllesmereUI._menuReopenUnit = unit
        -- FRESH context table, never the inbound one: OpenMenu ENRICHES its
        -- contextData in place (playerLocation/accountInfo) and asserts those
        -- fields are nil on entry -- re-passing the first open's table throws
        -- "assertion failed" at UnitPopupShared:53 (field-caught 2026-08-14;
        -- the live misfire classifies as OTHERBATTLEPET, same field capture).
        UnitPopup_OpenMenu(isRaidToken and "RAID_PLAYER" or "PARTY", { unit = unit })
        EllesmereUI._menuReopenUnit = nil
        reopening = false
        if EllesmereUI._ShowReopenedMenuExtras then EllesmereUI._ShowReopenedMenuExtras(unit) end
    end)
end

local menuProxies = setmetatable({}, { __mode = "k" })
local menuMacros = setmetatable({}, { __mode = "k" })  -- proxy -> its macrotext
-- 12.1: proxies are GLOBALLY NAMED so bindings can reach them via "/click
-- <name>" (macro transport). 12.1 broke the "click" secure action outright
-- (a typo: SecureTemplates.lua:564 calls HasAnyForbiddenAspects on the
-- mouse-button STRING instead of the delegate); /click hits
-- SecureActionButton_OnClick directly and is unaffected.
local proxyCounter = 0

-- Create (once) and return the hidden SecureActionButton proxy for a unit button.
-- Use this when wiring a SPECIFIC click/key binding to the menu -- it does NOT
-- touch the frame's own type attributes (so it won't clobber other bindings).
function EllesmereUI.GetSecureMenuProxy(frame)
    if not frame then return end
    InstallMenuClassifierFix()
    local proxy = menuProxies[frame]
    if not proxy then
        local proxyName
        proxyCounter = proxyCounter + 1
        proxyName = "EUISecureMenuProxy" .. proxyCounter
        proxy = CreateFrame("Button", proxyName, frame, "SecureActionButtonTemplate")
        proxy:SetSize(1, 1)
        proxy:SetAlpha(0)
        proxy:EnableMouse(false)          -- never catches real mouse; only the secure click delegate reaches it
        proxy:RegisterForClicks("AnyUp")
        proxy:SetAttribute("type", "togglemenu")
        -- The secure resolver looks up type by BUTTON SUFFIX (RightButton -> type2);
        -- the bare "type" may not fall back, so set every button explicitly.
        for i = 1, 5 do proxy:SetAttribute("type" .. i, "togglemenu") end
        menuMacros[proxy] = "/click " .. proxyName
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
        proxyCounter = proxyCounter + 1
        proxyName = "EUISecureTargetProxy" .. proxyCounter
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

-- The macrotext that opens a unit button's secure menu (every binding that
-- routes to the menu must use this, never a hand-built "/click <proxy>").
function EllesmereUI.GetSecureMenuMacro(frame)
    local proxy = EllesmereUI.GetSecureMenuProxy(frame)
    return proxy and menuMacros[proxy]
end

-- Route a unit button's default RIGHT-CLICK to the secure menu proxy via the
-- macro transport. Clears any specific type2 so the wildcard governs.
function EllesmereUI.AttachSecureUnitMenu(frame)
    if not frame then return end
    local proxy = EllesmereUI.GetSecureMenuProxy(frame)
    frame:SetAttribute("type2", nil)
    -- Macro transport instead of the "click" action: the 12.1 click action
    -- crashes on a Blizzard typo (see above).
    frame:SetAttribute("*type2", "macro")
    frame:SetAttribute("*macrotext2", menuMacros[proxy])
    frame:SetAttribute("*clickbutton2", nil)
    return proxy
end

local kickFrame = CreateFrame("Frame")
kickFrame:RegisterEvent("PLAYER_LOGIN")
kickFrame:RegisterEvent("SPELLS_CHANGED")
-- Swapping demons swaps the interrupt (Felguard's Axe Toss vs Felhunter's Spell
-- Lock), and the resolution above now reads the pet bank, so it has to re-run
-- when the pet changes. SPELLS_CHANGED covers most swaps but is not guaranteed
-- for every summon, and a stale pick here is invisible until the user kicks.
if kickFrame.RegisterUnitEvent then
    kickFrame:RegisterUnitEvent("UNIT_PET", "player")
else
    kickFrame:RegisterEvent("UNIT_PET")
end
-- WoW Forever's stance and form gated kicks (warrior Shield Bash / Pummel, druid
-- Feral Charge) re-resolve on a stance or form change; no other class needs it.
if EllesmereUI.IS_FOREVER == true then
    local playerClass = UnitClassBase("player")
    if playerClass == "WARRIOR" or playerClass == "DRUID" then
        kickFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    end
end
kickFrame:SetScript("OnEvent", function()
    RefreshKickAbility()
end)

if UnitGUID("player") then
    RefreshKickAbility()
end
