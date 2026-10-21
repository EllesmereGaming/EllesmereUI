if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Paging.lua
--
--  Per-bar paging: the configurable conditions, the class-specific state
--  conditions, and the paging arrows and page number of action bar 1.
--  Loads after EUI_ActionBars_Secure.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs = ipairs, pairs
local InCombatLockdown = InCombatLockdown
local EFD = ns.EFD

local EAB, EAB_VTABLE = ns.EAB, ns.EAB_VTABLE
local I = ns._internals
local barBaseSize, barFrames, NUM_AB_PAGES = I.barBaseSize, I.barFrames, I.NUM_AB_PAGES
local SetPagingFrame = I.SetPagingFrame

-------------------------------------------------------------------------------
--  Configurable Paging System: per-bar paging based on modifier keys and
--  class forms/stances. Empty paging config = bars behave exactly as before.
-------------------------------------------------------------------------------

-- Stored on EAB_VTABLE, not in file locals.
EAB_VTABLE.BAR_KEY_TO_PAGE = {
    MainBar = 1,  Bar2 = 6,  Bar3 = 5,  Bar4 = 3,
    Bar5 = 4,     Bar6 = 13, Bar7 = 14, Bar8 = 15,
    Bar9 = 2,     Bar10 = 10,
}
EAB_VTABLE.PAGING_STATES = {
    modifier = {
        { id = "alt",   macro = "[mod:alt]",   label = "Alt" },
        { id = "shift", macro = "[mod:shift]", label = "Shift" },
        { id = "ctrl",  macro = "[mod:ctrl]",  label = "Ctrl" },
    },
    target = {
        { id = "help",  macro = "[help]",      label = "Friendly Target" },
        { id = "harm",  macro = "[harm]",      label = "Hostile Target" },
    },
    -- Shared with the CDM's Stance Bar hide (EllesmereUI_VisibilityRules.lua).
    class = EllesmereUI.CLASS_PAGING_STATES,
}

-- Modifier/Target Paging (the bar's modTargetPaging): false switches the five
-- modifier and target states off without clearing them; never set, they apply
-- whenever one holds a page, as they always did.
EAB_VTABLE.MOD_TARGET_PAGING = { shift = true, ctrl = true, alt = true, help = true, harm = true }

-- True when the bar has paging of the player's own that applies: a state
-- outside the five, or one of the five while Modifier/Target Paging is not off.
function EAB_VTABLE.HasCustomPaging(bs)
    local p = bs and bs.paging
    if not p or next(p) == nil then return false end
    if bs.modTargetPaging ~= false then return true end
    local mt = EAB_VTABLE.MOD_TARGET_PAGING
    for id in pairs(p) do
        if not mt[id] then return true end
    end
    return false
end

-- Auto-paging opt-outs for MainBar. Returns noForm, noSky: suppress implicit bonusbar
-- swaps for forms/stealth/stance (bonusbar 1-4) and skyriding (bonusbar 5). Does NOT
-- cover vehicle/override/possess -- those replace abilities outright, so suppressing
-- them would leave no way to use the vehicle. Only ever true for MainBar, the only bar
-- the engine drives off bonusbar and the only one with these toggles.
function EAB_VTABLE.GetAutoPagingOptOuts(barKey)
    if barKey ~= "MainBar" then return false, false end
    local bs = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars.MainBar
    if not bs then return false, false end
    return bs.disableFormPaging and true or false, bs.disableSkyridingPaging and true or false
end

function EAB_VTABLE.BuildPagingConditions(barKey, pagingConfig, defaultPage)
    if not pagingConfig or not next(pagingConfig) then return nil end
    local PG = EAB_VTABLE.PAGING_STATES
    local _, class = UnitClass("player")
    local noForm, noSky = EAB_VTABLE.GetAutoPagingOptOuts(barKey)
    local bs = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars[barKey]
    local noModTarget = bs and bs.modTargetPaging == false
    local parts = {}
    if barKey == "MainBar" then
        if EAB_VTABLE.GetOverrideBarIndex then
            parts[#parts + 1] = "[overridebar] " .. EAB_VTABLE.GetOverrideBarIndex()
        end
        if EAB_VTABLE.GetVehicleBarIndex then
            parts[#parts + 1] = "[vehicleui][possessbar] " .. EAB_VTABLE.GetVehicleBarIndex()
        end
    end
    if not noModTarget then
        for _, state in ipairs(PG.modifier) do
            local page = pagingConfig[state.id]
            if page then
                parts[#parts + 1] = state.macro .. " " .. page
            end
        end
    end
    -- MainBar falls back to hardcoded form pages for unconfigured (nil)
    -- states so setting a modifier doesn't break forms. false = user
    -- disabled ("None"), nil = unconfigured.
    local CLASS_DEFAULTS = {
        DRUID  = { prowl = 7, cat = 7, bear = 9, moonkin = 10 },
        ROGUE  = { stealth = 7 },
    }
    local classStates = PG.class[class]
    if classStates then
        -- noForm drops only the implicit fallback: a page the user picked for
        -- a specific form is explicit, not auto-paging, so it still applies.
        local defs = (barKey == "MainBar" and not noForm) and CLASS_DEFAULTS[class]
        for _, state in ipairs(classStates) do
            local page = pagingConfig[state.id]
            if page then
                parts[#parts + 1] = state.macro .. " " .. page
            elseif defs and defs[state.id] then
                -- nil and false both mean "no explicit page" (dropdown only
                -- offers Default or a bar; older saves stored false=Default).
                parts[#parts + 1] = state.macro .. " " .. defs[state.id]
            end
        end
    end
    -- WoW Forever: every class pages bar 1 by its stance/form offset (6 + offset), so
    -- the implicit fallback covers every offset after any explicit per-form pick.
    if barKey == "MainBar" and not noForm and EllesmereUI.IS_FOREVER then
        parts[#parts + 1] = "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10"
    end
    -- Manual pages come before the skyriding clause: the engine only consults
    -- the bonus bar while Blizzard's page is 1 (ActionBarController_UpdateAll),
    -- so [bonusbar:5] listed first pinned the bar to the skyriding page and
    -- swallowed every manual page change until the player dismounted.
    -- The form clauses above deliberately keep their old precedence -- a page
    -- picked for a specific form in the dropdowns is an explicit request, and
    -- this path is click-routed, so the icon and the key agree either way.
    if barKey == "MainBar" then
        for i = 2, NUM_AB_PAGES do
            parts[#parts + 1] = "[bar:" .. i .. "] " .. i
        end
        if not noSky then
            parts[#parts + 1] = "[bonusbar:5] 11"
        end
    end
    -- Target conditions come after bonusbar/bar so dragonriding and manual
    -- page switches take priority over target-based switching.
    if PG.target and not noModTarget then
        for _, state in ipairs(PG.target) do
            local page = pagingConfig[state.id]
            if page then
                parts[#parts + 1] = state.macro .. " " .. page
            end
        end
    end
    parts[#parts + 1] = tostring(defaultPage or 1)
    return table.concat(parts, "; ")
end

-------------------------------------------------------------------------------
--  Paging State Conditions (class-specific hardcoded fallback, used when no
--  custom paging is configured). Format: "[condition] pageNumber; ..."
-------------------------------------------------------------------------------
local function GetClassPagingConditions()
    local _, class = UnitClass("player")
    local noForm, noSky = EAB_VTABLE.GetAutoPagingOptOuts("MainBar")
    local conditions = ""

    -- Override bar (soft vehicle/quest abilities) and possess bar: remap bar
    -- 1 to those slots so our buttons stay visible and keybinds work.
    if EAB_VTABLE.GetOverrideBarIndex then
        conditions = conditions .. "[overridebar] " .. EAB_VTABLE.GetOverrideBarIndex() .. "; "
    end
    if EAB_VTABLE.GetVehicleBarIndex then
        conditions = conditions .. "[vehicleui][possessbar] " .. EAB_VTABLE.GetVehicleBarIndex() .. "; "
    end

    -- Manual page switching (pages 2-6): [bar:N] responds to the internal page set by
    -- ChangeActionBarPage() (built-in keybinds + our arrows). Listed BEFORE class form
    -- conditions to match the engine's native resolution order (manual page beats form
    -- bonusbar, which only applies on page 1). MainBar keybinds are native
    -- ACTIONBUTTONn commands, so the displayed page must resolve exactly like the
    -- engine's or a form + manual-page combo shows one ability and fires another.
    -- (Auto-paging opt-outs deliberately break from this -- why they force keys off
    -- ACTIONBUTTONn onto the click route; see UpdateKeybinds pass 1.)
    for i = 2, NUM_AB_PAGES do
        conditions = conditions .. "[bar:" .. i .. "] " .. i .. "; "
    end

    -- Class-specific form paging (page 1 only, per the ordering above)
    if not noForm then
        if EllesmereUI.IS_FOREVER then
            -- WoW Forever pages bar 1 natively by the stance/form offset for EVERY
            -- class (vanilla warrior stances, druid forms, rogue stealth): page 6 + offset.
            -- Mirror it exactly so ACTIONBUTTONn and the icon agree in every stance.
            conditions = conditions .. "[bonusbar:1] 7; [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; "
        elseif class == "DRUID" then
            conditions = conditions .. "[bonusbar:1,stealth] 7; [bonusbar:1] 7; [bonusbar:3] 9; [bonusbar:4] 10; "
        elseif class == "ROGUE" then
            conditions = conditions .. "[bonusbar:1] 7; "
        end
    end

    -- Dragonriding (all classes; page 1 only, same rule as the forms above)
    if not noSky then
        conditions = conditions .. "[bonusbar:5] 11; "
    end

    -- Default: page 1
    conditions = conditions .. "1"

    return conditions
end

-------------------------------------------------------------------------------
--  Action Bar 1 Paging Arrows + Page Number
-------------------------------------------------------------------------------
local _pagingFrame    -- forward ref
I.pagingFrameSetters[#I.pagingFrameSetters + 1] = function(v) _pagingFrame = v end
local LayoutPagingFrame  -- forward ref (used inside SetupPagingFrame closure)

-- The paging frame is parented to MainBar (see LayoutPagingFrame), so it
-- inherits the bar's mouseover-fade alpha AND secure show/hide automatically;
-- own alpha stays 1 so the parent governs solely (no double-fade).
local function SyncPagingAlpha()
    if _pagingFrame then _pagingFrame:SetAlpha(1) end
end

-- Paging arrows use SecureActionButtonTemplate type "macro"; [bar:N]
-- conditionals cycle pages statically, no dynamic attribute changes needed.
local _macroNext = "/changeactionbar [bar:6] 1"
local _macroPrev = "/changeactionbar [bar:1] 6"
for i = 1, NUM_AB_PAGES - 1 do
    _macroNext = _macroNext .. "; [bar:" .. i .. "] " .. (i + 1)
    _macroPrev = _macroPrev .. "; [bar:" .. (i + 1) .. "] " .. i
end

-- Shared by the secure paging macros and the legacy non-secure functions.
-- Only configured-on bars reserve their underlying page; hide-on-mouseover
-- still reserves a page, while disabled/always-hidden bars do not.
function ns.GetPagingSkipMask()
    local skip = {}
    local bars = EAB.db and EAB.db.profile and EAB.db.profile.bars
    if not (bars and bars.MainBar and bars.MainBar.skipVisiblePagingBars) then return skip end
    for barKey, page in pairs(EAB_VTABLE.BAR_KEY_TO_PAGE) do
        if barKey ~= "MainBar" and page >= 1 and page <= NUM_AB_PAGES then
            local settings = bars[barKey]
            if settings and settings.enabled ~= false and not settings.alwaysHidden then
                skip[page] = true
            end
        end
    end
    return skip
end

local function BuildFilteredPageMacro(delta, skip)
    local macro = {}
    for page = 1, NUM_AB_PAGES do
        local target = page
        for _ = 1, NUM_AB_PAGES do
            target = (target - 1 + delta + NUM_AB_PAGES) % NUM_AB_PAGES + 1
            if not skip[target] then break end
        end
        macro[#macro + 1] = "[bar:" .. page .. "] " .. target
    end
    return "/changeactionbar " .. table.concat(macro, "; ")
end

local function WireSecurePagingButton(btn, delta)
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", delta > 0 and _macroNext or _macroPrev)
end

local _filteredPagingActive = false

-- Changes to secure macrotext must happen out of combat. Memoization avoids
-- rewriting protected attributes during routine ApplyAll calls.
function ns.RefreshPagingCycleMacros()
    local bars = EAB.db and EAB.db.profile and EAB.db.profile.bars
    local enabled = bars and bars.MainBar and bars.MainBar.skipVisiblePagingBars

    if not enabled and not _filteredPagingActive then return end

    -- A change made in combat (an options edit, a visibility switch) runs once
    -- combat ends instead of leaving the paging macros stale until the next
    -- full apply; the deferred pass re-reads the settings then.
    if InCombatLockdown() then
        ns.CombatQueue.Defer("PagingCycleMacros", ns.RefreshPagingCycleMacros)
        return
    end

    local nextMacro, prevMacro
    if enabled then
        local skip = ns.GetPagingSkipMask()
        nextMacro = BuildFilteredPageMacro(1, skip)
        prevMacro = BuildFilteredPageMacro(-1, skip)
    else
        nextMacro = _macroNext
        prevMacro = _macroPrev
    end

    local function UpdateButton(button, macro)
        if button and button:GetAttribute("macrotext") ~= macro then
            button:SetAttribute("macrotext", macro)
        end
    end
    UpdateButton(_pagingFrame and _pagingFrame._upBtn, nextMacro)
    UpdateButton(_pagingFrame and _pagingFrame._downBtn, prevMacro)
    UpdateButton(_G.EABPageNext, nextMacro)
    UpdateButton(_G.EABPagePrev, prevMacro)
    _filteredPagingActive = not not enabled
end

local function InitPagingQuickKeybindButton(btn, atlas)
    if not btn then return end

    if not btn.QuickKeybindHighlightTexture then
        local tex = btn:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints(btn)
        tex:SetAtlas(atlas)
        tex:SetAlpha(0.8)
        tex:Hide()
        btn.QuickKeybindHighlightTexture = tex
    end

    if EFD(btn).quickKeybindInit or not QuickKeybindButtonTemplateMixin then
        return
    end

    Mixin(btn, QuickKeybindButtonTemplateMixin)
    btn:HookScript("OnShow", btn.QuickKeybindButtonOnShow)
    btn:HookScript("OnHide", btn.QuickKeybindButtonOnHide)
    btn:HookScript("OnClick", btn.QuickKeybindButtonOnClick)
    btn:HookScript("OnEnter", btn.QuickKeybindButtonOnEnter)
    btn:HookScript("OnLeave", btn.QuickKeybindButtonOnLeave)
    EFD(btn).quickKeybindInit = true
    -- Do NOT call btn:QuickKeybindButtonOnShow() eagerly here. It registers
    -- persistent EventRegistry callbacks that fire UpdateMouseWheelHandler
    -- (and thus SetScript) on a SecureActionButtonTemplate frame on every
    -- QKB mode change. The HookScript("OnShow") handles runtime visibility.
end

local function SetupPagingFrame()
    if _pagingFrame then return _pagingFrame end

    local f = CreateFrame("Frame", "EABPagingFrame", UIParent)
    f:SetSize(20, 52)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(10)

    -- Page number text
    local pageText = f:CreateFontString(nil, "OVERLAY")
    pageText:SetFont(STANDARD_TEXT_FONT, 12, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    pageText:SetTextColor(1, 1, 1, 0.9)
    pageText:SetText("1")
    f._pageText = pageText

    -- Own secure macrotext (WireSecurePagingButton), NOT Blizzard's
    -- ActionBarUpButton -- Blizzard's pager buttons are mouse-dead (KillPagerMouse).
    local upBtn = CreateFrame("Button", "EABPagingUp", f, "SecureActionButtonTemplate")
    upBtn:SetSize(18, 18)
    upBtn:RegisterForClicks("AnyUp", "AnyDown")
    upBtn:SetNormalAtlas("UI-HUD-ActionBar-PageUpArrow-Up")
    upBtn:SetPushedAtlas("UI-HUD-ActionBar-PageUpArrow-Down")
    upBtn:SetDisabledAtlas("UI-HUD-ActionBar-PageUpArrow-Disabled")
    upBtn:SetHighlightAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover")
    f._upBtn = upBtn
    InitPagingQuickKeybindButton(upBtn, "UI-HUD-ActionBar-PageUpArrow-Mouseover")

    -- same: own secure macrotext, not Blizzard's button
    local downBtn = CreateFrame("Button", "EABPagingDown", f, "SecureActionButtonTemplate")
    downBtn:SetSize(18, 18)
    downBtn:RegisterForClicks("AnyUp", "AnyDown")
    downBtn:SetNormalAtlas("UI-HUD-ActionBar-PageDownArrow-Up")
    downBtn:SetPushedAtlas("UI-HUD-ActionBar-PageDownArrow-Down")
    downBtn:SetDisabledAtlas("UI-HUD-ActionBar-PageDownArrow-Disabled")
    downBtn:SetHighlightAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover")
    f._downBtn = downBtn
    InitPagingQuickKeybindButton(downBtn, "UI-HUD-ActionBar-PageDownArrow-Mouseover")

    -- Update page text and handle combat visibility / vehicle state
    f:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    f:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    f:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
    f:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event)
        if event == "UPDATE_OVERRIDE_ACTIONBAR" or event == "UPDATE_VEHICLE_ACTIONBAR" then
            LayoutPagingFrame()
            -- Trigger page sync; the Queue callback early-returns in combat,
            -- so the sync only runs out of combat.
            EAB_VTABLE.MainBarPageSync.Queue()
            return
        end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            local s = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars["MainBar"]
            if s and not InCombatLockdown() then
                local inCombat = (event == "PLAYER_REGEN_DISABLED")
                if s.combatShowEnabled then
                    if inCombat then f:Show() else f:Hide() end
                elseif s.combatHideEnabled then
                    if inCombat then f:Hide() else f:Show() end
                end
            end
            return
        end
        local page = EAB_VTABLE.GetActionBarPage()
        pageText:SetText(tostring(page))
        -- Trigger page sync for manual page changes, form changes, etc.
        EAB_VTABLE.MainBarPageSync.Queue()
    end)

    local initPage = EAB_VTABLE.GetActionBarPage()
    pageText:SetText(tostring(initPage))

    WireSecurePagingButton(upBtn, 1)
    WireSecurePagingButton(downBtn, -1)
    upBtn.commandName = "NEXTACTIONPAGE"
    downBtn.commandName = "PREVIOUSACTIONPAGE"

    SetPagingFrame(f)
    return f
end

-- The paging arrows' sizes for a button height, shared with the options
-- preview's stand-in: arrow, page number text, the gap between them, and the
-- gap to the bar.
function ns.AB_PagingArrowMetrics(btnH)
    local arrow = math.max(14, math.floor(btnH * 0.4))
    return arrow, math.max(10, math.floor(arrow * 0.7)), 2, 4
end

LayoutPagingFrame = function()
    local f = _pagingFrame
    if not f then return end
    if InCombatLockdown() then return end
    local mainFrame = barFrames and barFrames["MainBar"]
    if not mainFrame then f:Hide(); return end

    local s = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars["MainBar"]
    if not s then f:Hide(); return end

    -- Parenting to MainBar makes it inherit secure show/hide + mouseover-fade
    -- alpha automatically, including in combat. Reparenting secure children is
    -- blocked in combat, hence the InCombatLockdown gate above.
    if f:GetParent() ~= mainFrame then
        f:SetParent(mainFrame)
        f:SetFrameStrata("MEDIUM")
        f:SetAlpha(1)
    end
    -- Five levels over the bar, and one over its end caps while they can show
    -- (retail's page arrows sit over its caps).
    local caps = s.orientation ~= "vertical" and ns.AB_CAPS[ns.AB_CapsLook("MainBar") or "-"]
    local lvl = (mainFrame:GetFrameLevel() or 1) + 1 + (caps and caps.lvl or 4)
    if f:GetFrameLevel() ~= lvl then f:SetFrameLevel(lvl) end

    if s.alwaysHidden or s.enabled == false or not s.showPagingArrows then
        f:Hide()
        return
    end

    -- Hide during vehicle/override (paging doesn't apply)
    local overridePage = mainFrame:GetAttribute("state-overridepage") or 0
    if overridePage > 0 then
        f:Hide()
        return
    end

    local isVertical = (s.orientation == "vertical")
    local base = barBaseSize and barBaseSize["MainBar"]
    local btnH = (s.buttonHeight and s.buttonHeight > 0) and s.buttonHeight or (base and base.h or 45)
    local arrowSize, textSize, gap, barGap = ns.AB_PagingArrowMetrics(btnH)

    f._upBtn:SetSize(arrowSize, arrowSize)
    f._downBtn:SetSize(arrowSize, arrowSize)
    f._pageText:SetFont(STANDARD_TEXT_FONT, textSize, (EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")

    f._upBtn:ClearAllPoints()
    f._downBtn:ClearAllPoints()
    f._pageText:ClearAllPoints()

    local onRight = s.pagingArrowsRight

    if isVertical then
        local totalW = arrowSize + gap + textSize * 2 + gap + arrowSize
        f:SetSize(totalW, arrowSize)
        f:ClearAllPoints()
        if onRight then
            f:SetPoint("TOP", mainFrame, "BOTTOM", 0, -barGap)
        else
            f:SetPoint("BOTTOM", mainFrame, "TOP", 0, barGap)
        end
        f._downBtn:SetPoint("LEFT", f, "LEFT", 0, 0)
        f._pageText:SetPoint("CENTER", f, "CENTER", 0, 0)
        f._upBtn:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    else
        local totalH = arrowSize + gap + textSize + gap + arrowSize
        f:SetSize(arrowSize, totalH)
        f:ClearAllPoints()
        if onRight then
            f:SetPoint("LEFT", mainFrame, "RIGHT", barGap, 0)
        else
            f:SetPoint("RIGHT", mainFrame, "LEFT", -barGap, 0)
        end
        f._upBtn:SetPoint("TOP", f, "TOP", 0, 0)
        f._pageText:SetPoint("CENTER", f, "CENTER", 0, 0)
        f._downBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    end

    f:Show()
end
ns.LayoutPagingFrame = LayoutPagingFrame

-- Secure snippet appended to each button's _childupdate-eab-page handler (and
-- reused as the _childupdate-eab-empower handler): after the action attr
-- changes on a page swap, re-evaluate pressAndHoldAction for empowered /
-- hold-release spells. IsPressHoldReleaseSpell and GetActionInfo exist in the
-- restricted environment even though gone from _G (GetActionInfo as a
-- scrubbing wrapper, RestrictedEnvironment.lua). On ns, not a file local.
--
-- Writes pressAndHoldAction ONLY (like Blizzard's UpdatePressAndHoldAction),
-- and only on a POSITIVE identity read: a slot whose identity is unreadable
-- at snippet time KEEPS its current value -- see the decision trailer inside.
-- It must NOT touch typerelease: Blizzard sets that to "actionrelease" once
-- in the mixin's OnLoad and never clears it, and SecureTemplates reads it on
-- EVERY key release when the ActionButtonUseKeyHeldSpell CVar is on, not just
-- for empowered spells (releasePressAndHoldAction = (not down) and
-- (pressAndHoldAction or CVar)). Clearing it on non-empower buttons would
-- leave those users' key-up path with no action type at all.
-- (2026-08-09: a [channeling]-gated typerelease disarm was field-tested on
-- live against the rank-1 queued-release latch and REVERTED -- it did not
-- stop the early release; the fix was routing empower KEYS native instead.
-- Do not re-attempt that shape without new field data.)
ns._eabEmpowerSnippet = [[
    local slot = self:GetAttribute('action')
    if slot and IsPressHoldReleaseSpell then
        local actionType, id, subType = GetActionInfo(slot)
        local spellID = nil
        if actionType == 'spell' then
            spellID = id
        elseif actionType == 'macro' and subType == 'spell' then
            spellID = id
        end
        if spellID then
            if IsPressHoldReleaseSpell(spellID) then
                self:SetAttribute('pressAndHoldAction', true)
            else
                self:SetAttribute('pressAndHoldAction', false)
            end
        elseif actionType and actionType ~= 'spell' and actionType ~= 'macro' then
            self:SetAttribute('pressAndHoldAction', false)
        end
    end
]]
-- Decision trailer for the snippet above: a readable spell identity decides
-- true/false exactly as before, and a positively non-spell action (item,
-- companion, ...) is never hold-release. EVERYTHING ELSE -- an empty slot, a
-- scrubbed in-combat read, or a macro not currently resolving to a spell
-- (mouseover macros flip constantly) -- KEEPS the current attribute. This
-- snippet runs SECURELY during combat page swaps (bonusbar/override flips in
-- encounters), where the restricted GetActionInfo read cannot be trusted to
-- see the spell: writing false there stripped hold-release from empowered
-- slots mid-fight, which presents as the Empowered Spell Input setting
-- flipping to Press-and-Tap. A stale TRUE on the other hand is inert: the
-- key-up actionrelease it allows is the same no-op every
-- Press-and-Hold-Casting key-up already fires on non-empower actions, and
-- native-routed keys never reach the button at all. The out-of-combat
-- re-checks (pass 3 of UpdateKeybinds, the combat-drop re-assert) correct
-- any kept value as soon as identity is readable again.

-- Un-park a slot that "Always Show Buttons" off left hidden. Parking writes
-- four things (alpha 0, mouse off, statehidden, Hide) and un-parking must undo
-- all four -- but EnableMouse on a protected button is combat-blocked, so
-- SafeEnableMouse silently returns and the insecure pass can only restore the
-- three unprotected ones. A form or page flip that fills the slot mid-combat
-- therefore left the button VISIBLE (alpha is unprotected) yet deaf to hover
-- and clicks, while keybinds -- which route through override bindings and need
-- no mouse -- kept working (reported: druid stance change in combat).
--
-- The restore cannot come from the OnShow -> UpdateShown wrapper: that snippet
-- gates on not IsShown(), and OnShow fires after the frame is already shown.
-- It has to happen here, before the Show. Gated on the hidden->shown edge so a
-- live on-cooldown alpha on an already-visible button is never stomped, and on
-- eab-click so a reveal never makes a click-through bar clickable.
ns._eabPageUnparkSnippet = [[
if not self:IsShown() then
    self:SetAlpha(1)
    if (self:GetAttribute('eab-click') or 1) ~= 0 then
        self:EnableMouse(true)
    end
end
]]

-- Build the _childupdate-eab-page snippet for a button at the given 1-based bar
-- index. On a page change: action = baseIndex + (page-1)*12, re-evaluate parked
-- visibility, then re-check hold-release. ALL install sites (SetupBar,
-- RebuildBarPaging) call this so the handler is byte-identical everywhere --
-- the page change rewrites the secure "action" attribute (our buttons are
-- ID=0, so actionpage is never consulted).
--
-- The visibility half is gated on eab-showempty EXISTING: it is stamped by
-- ApplyAlwaysShowButtons out of combat, and a button that has never seen a
-- stamp keeps the pre-existing behaviour (action only, visibility left to the
-- controller's deferred UpdateShown) rather than guessing at a default.
ns._eabPageVisSnippet = [[
local showEmpty = self:GetAttribute('eab-showempty')
if showEmpty then
    local withinCutoff = self:GetAttribute('eab-withincutoff') ~= 0
    local visible = withinCutoff
    if visible and showEmpty == 0 then
        visible = HasAction(slot)
    end
    -- A transient grid reveal outranks the empty-slot park, exactly as
    -- UpdateShown does: a page flip during a combat spell drag must not
    -- delete the drop targets under the cursor. Bits 2+ only -- bit 1 is
    -- Blizzard's CVAR reason and is not a transient reveal. statehidden is
    -- cleared only for a genuinely filled slot, so drag end still re-parks.
    local grid = self:GetAttribute('showgrid') or 0
    local transient = withinCutoff and (grid % 32) >= 2
    if visible or transient then
        if visible and self:GetAttribute('statehidden') then
            self:SetAttribute('statehidden', nil)
        end
]] .. ns._eabPageUnparkSnippet .. [[
        self:Show(true)
    else
        if not self:GetAttribute('statehidden') then
            self:SetAttribute('statehidden', true)
        end
        self:Hide(true)
    end
end
]]

function ns._eabBuildPageChildSnippet(baseIndex)
    return ("local page = tonumber(message) or 1; local slot = %d + (page - 1) * 12; self:SetAttribute('action', slot)\n"):format(baseIndex)
        .. ns._eabPageVisSnippet .. ns._eabEmpowerSnippet
end

-- Entry points the files after this one re-import by name.
I.SyncPagingAlpha, I.InitPagingQuickKeybindButton = SyncPagingAlpha, InitPagingQuickKeybindButton
I.GetClassPagingConditions, I.LayoutPagingFrame = GetClassPagingConditions, LayoutPagingFrame
I.SetupPagingFrame, I.WireSecurePagingButton = SetupPagingFrame, WireSecurePagingButton
