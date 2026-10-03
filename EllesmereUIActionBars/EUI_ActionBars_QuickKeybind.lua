if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_QuickKeybind.lua
--
--  Quick Keybind Mode support for the EAB buttons and the paging arrows, and
--  the Swiftmend brightness scan over the action buttons. Loads after
--  EUI_ActionBars_ExtraBars.lua and reads the main file through ns only.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs = ipairs, pairs
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After
local RegisterAttributeDriver = RegisterAttributeDriver
local GetBindingKey = GetBindingKey
local EFD = ns.EFD

local EAB, barButtons = ns.EAB, ns.barButtons
local LayoutPagingFrame, ResolveBorderThickness = ns.LayoutPagingFrame, ns.ResolveBorderThickness
local I = ns._internals
local BAR_CONFIG, barFrames, hoverStates, _quickKeybindState = I.BAR_CONFIG, I.barFrames, I.hoverStates, I._quickKeybindState
local InitPagingQuickKeybindButton, SyncPagingAlpha, StopFade = I.InitPagingQuickKeybindButton, I.SyncPagingAlpha, I.StopFade
local SHOWGRID, SetShowGridInsecure = I.SHOWGRID, I.SetShowGridInsecure
local SafeEnableMouseMotionOnly, ShouldQuickKeybindSurfaceBar = I.SafeEnableMouseMotionOnly, I.ShouldQuickKeybindSurfaceBar
local EAB_UpdateQuickKeybindButtons -- assigned below, published as ns.EAB_UpdateQuickKeybindButtons
local _pagingFrame -- set by the main file through ns._PagingFrameBind
function ns._PagingFrameBind(f) _pagingFrame = f end

-------------------------------------------------------------------------------
--  QuickKeybind compatibility: modern QuickKeybind works off visible
--  buttons' `commandName` plus `DoModeChange(...)`. Blizzard's stock helpers
--  only know about their own named bar buttons, so only EAB-owned buttons
--  and the custom paging arrows need an explicit mode toggle here.
-------------------------------------------------------------------------------
local function EAB_SetQuickKeybindEffects(btn, show)
    if not btn or btn:IsForbidden() then return end
    if btn.DoModeChange then
        btn:DoModeChange(show)
    elseif btn.QuickKeybindHighlightTexture then
        btn.QuickKeybindHighlightTexture:SetShown(show)
    end
    -- Suppress/restore the secure action so spells don't fire during QKB.
    -- Only action buttons (those with an action attr) need this.
    if not InCombatLockdown() and btn.commandName and btn:GetAttribute("action") then
        if show then
            btn:SetAttribute("type", nil)
        else
            btn:SetAttribute("type", "action")
        end
    end
    _quickKeybindState.art.ApplyButtonHighlightAlpha(btn, show)
    if btn.UpdateMouseWheelHandler then
        btn:UpdateMouseWheelHandler()
    end
end

EAB_UpdateQuickKeybindButtons = function(show)
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for _, btn in ipairs(buttons) do
                if btn and btn.commandName then
                    EAB_SetQuickKeybindEffects(btn, show)
                end
            end
        end
    end
    if _pagingFrame then
        if _pagingFrame._upBtn then
            EAB_SetQuickKeybindEffects(_pagingFrame._upBtn, show)
        end
        if _pagingFrame._downBtn then
            EAB_SetQuickKeybindEffects(_pagingFrame._downBtn, show)
        end
    end
end

_quickKeybindState.macroButtons = setmetatable({}, { __mode = "k" })

-- Macro quick-keybind uses our OWN capture overlay instead of Blizzard's
-- QuickKeybindButtonTemplateMixin. Driving Blizzard's secure input path from
-- addon code tainted it, so any key Blizzard passes through during capture
-- -- e.g. F11 = SCREENSHOT, which it RUNs via the protected RunBinding --
-- threw ADDON_ACTION_FORBIDDEN. Capturing on a plain frame we own consumes
-- the key before Blizzard's input handler sees it, so every key (including
-- system/function keys) binds cleanly with no taint.

_quickKeybindState.GetMacroBindingContext = function(command)
    return C_KeyBindings and C_KeyBindings.GetBindingContextForAction
        and C_KeyBindings.GetBindingContextForAction(command)
end

_quickKeybindState.SetOutput = function(text)
    if QuickKeybindFrame and QuickKeybindFrame.SetOutputText then
        QuickKeybindFrame:SetOutputText(text)
    end
end

_quickKeybindState.NormalizeMacroBindInput = function(input)
    input = GetConvertedKeyOrButton and GetConvertedKeyOrButton(input) or input
    if IsKeyPressIgnoredForBinding and IsKeyPressIgnoredForBinding(input) then return end
    return input
end

_quickKeybindState.SetMacroButtonTooltip = function(button)
    if not button or not button.commandName or not QuickKeybindTooltip then return end
    QuickKeybindTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip_AddHighlightLine(QuickKeybindTooltip, GetBindingName(button.commandName))

    local key1 = GetBindingKeyForAction(button.commandName)
    if key1 then
        GameTooltip_AddInstructionLine(QuickKeybindTooltip, key1)
        GameTooltip_AddNormalLine(QuickKeybindTooltip, ESCAPE_TO_UNBIND)
    else
        GameTooltip_AddErrorLine(QuickKeybindTooltip, NOT_BOUND)
        GameTooltip_AddNormalLine(QuickKeybindTooltip, PRESS_KEY_TO_BIND)
    end

    QuickKeybindTooltip:Show()
end

_quickKeybindState.BindMacroInput = function(input)
    -- Rebinding during combat is unsafe and the rest of QKB is combat-gated, so
    -- match that here even though our capture frame is insecure.
    if InCombatLockdown() then return end
    local button = _quickKeybindState.hoveredMacroButton
    if not button then return end

    _quickKeybindState.UpdateMacroButtonCommand(button)
    local command = button.commandName
    if not command then return end

    local context = _quickKeybindState.GetMacroBindingContext(command)
    local old1, old2 = GetBindingKey(command, nil, context)

    if input == "ESCAPE" then
        -- Full unbind: clear EVERY key bound to this macro, matching the rebind
        -- path below (which clears both old keys before setting the new one).
        if old1 then SetBinding(old1, nil, context) end
        if old2 then SetBinding(old2, nil, context) end
        _quickKeybindState.SetOutput(KEY_UNBOUND)
        _quickKeybindState.SetMacroButtonTooltip(button)
        return
    end

    local key = _quickKeybindState.NormalizeMacroBindInput(input)
    if not key then return end

    local newKey = CreateKeyChordStringUsingMetaKeyState and CreateKeyChordStringUsingMetaKeyState(key) or key
    if old1 then SetBinding(old1, nil, context) end
    if old2 then SetBinding(old2, nil, context) end
    SetBinding(newKey, nil, context)

    if SetBinding(newKey, command, context) then
        _quickKeybindState.SetOutput(KEY_BOUND)
    else
        if old1 then SetBinding(old1, command, context) end
        if old2 then SetBinding(old2, command, context) end
    end

    _quickKeybindState.SetMacroButtonTooltip(button)
end

_quickKeybindState.GetMacroBindFrame = function()
    if _quickKeybindState.macroBindFrame then return _quickKeybindState.macroBindFrame end

    -- A plain (insecure) frame we fully own -- never a secure template.
    -- Capturing input on it consumes the keypress, so it never reaches
    -- Blizzard's secure input path (no SetPropagateKeyboardInput, default = consume).
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(1000)
    frame:EnableMouse(true)
    frame:EnableKeyboard(true)
    frame:EnableMouseWheel(true)
    frame:Hide()

    frame:SetScript("OnLeave", function(self)
        local button = self.button
        self.button = nil
        _quickKeybindState.hoveredMacroButton = nil
        self:Hide()
        if QuickKeybindTooltip then QuickKeybindTooltip:Hide() end
        if button then _quickKeybindState.RefreshMacroButton(button) end
    end)
    frame:SetScript("OnKeyDown", function(_, key)
        _quickKeybindState.BindMacroInput(key)
    end)
    frame:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" then
            _quickKeybindState.BindMacroInput(mouseButton)
        end
    end)
    frame:SetScript("OnMouseWheel", function(_, delta)
        _quickKeybindState.BindMacroInput(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
    end)

    _quickKeybindState.macroBindFrame = frame
    return frame
end

-- Controller: while armed over a macro, the overlay also takes Blizzard's
-- native gamepad buttons, re-decided on every arm, so buttons bind only while
-- a controller is the active input and the overlay is shown. The pad button
-- bound to the game menu unbinds the macro, as Escape does, instead of being
-- bound to it.
-- Never while the controller-cursor addon is loaded or the Gamepad interface
-- style is on: their D-pad and face buttons drive a cursor or the focus and
-- would bind here instead.
_quickKeybindState.ArmMacroPad = function(frame)
    local want = EllesmereUI.PadNative() and not EllesmereUI.PadCP()
        and not EllesmereUI.PadGamepadUI()
    if not want and not frame._padOn then return end
    -- Binding is out of combat only (BindMacroInput), so is the switch.
    if InCombatLockdown() then return end
    if want and not frame._padInit then
        frame._padInit = true
        frame:SetScript("OnGamePadButtonDown", function(_, button)
            -- The pointer's click buttons click, as Left/Right do on the mouse.
            if button == GetCVar("GamePadCursorLeftClick")
               or button == GetCVar("GamePadCursorRightClick") then
                return
            end
            if GetBindingFromClick(button) == "TOGGLEGAMEMENU" then button = "ESCAPE" end
            _quickKeybindState.BindMacroInput(button)
        end)
    end
    frame._padOn = want or nil
    frame:EnableGamePadButton(want)
end

_quickKeybindState.HideMacroBindFrame = function()
    local frame = _quickKeybindState.macroBindFrame
    if not frame then return end

    local button = frame.button
    frame.button = nil
    _quickKeybindState.hoveredMacroButton = nil
    frame:Hide()
    if QuickKeybindTooltip then QuickKeybindTooltip:Hide() end
    if button then _quickKeybindState.RefreshMacroButton(button, false) end
end

_quickKeybindState.UpdateMacroButtonCommand = function(button)
    if not button or not MacroFrame or not MacroFrame.GetMacroDataIndex or not GetMacroInfo then return end

    local index
    if (button == MacroFrameSelectedMacroButton or button == MacroFrame.SelectedMacroButton)
        and MacroFrame.GetSelectedIndex then
        local selected = MacroFrame:GetSelectedIndex()
        if selected then index = MacroFrame:GetMacroDataIndex(selected) end
    elseif button.GetElementData then
        local data = button:GetElementData()
        if data then index = MacroFrame:GetMacroDataIndex(data) end
    end

    local name = index and GetMacroInfo(index)
    button.commandName = name and ("MACRO " .. name) or nil
end

_quickKeybindState.RefreshMacroButton = function(button, show)
    if not button then return end
    _quickKeybindState.UpdateMacroButtonCommand(button)
    if show == nil then
        show = _quickKeybindState.open
    end
    EAB_SetQuickKeybindEffects(button, show and button:IsShown())
end

-- On hover (in QKB mode) park the capture overlay over the macro button and arm
-- its tooltip, so the next key/mouse/wheel press binds to THIS macro.
_quickKeybindState.SelectMacroButton = function(button)
    if not _quickKeybindState.open then return end
    _quickKeybindState.UpdateMacroButtonCommand(button)
    if not button.commandName then return end

    _quickKeybindState.hoveredMacroButton = button

    local frame = _quickKeybindState.GetMacroBindFrame()
    frame.button = button
    frame:ClearAllPoints()
    frame:SetAllPoints(button)
    _quickKeybindState.ArmMacroPad(frame)  -- controller buttons, only while armed
    frame:Show()

    _quickKeybindState.RefreshMacroButton(button, true)
    if button.QuickKeybindHighlightTexture then
        button.QuickKeybindHighlightTexture:SetAlpha(1)
    end
    _quickKeybindState.SetMacroButtonTooltip(button)
end

_quickKeybindState.InitMacroButton = function(button)
    if not button or EFD(button).qkbMacroHooked or not QuickKeybindButtonTemplateMixin then return end

    -- No Mixin/QuickKeybindButton* method calls: those invoke Blizzard's secure input
    -- path from addon code and taint it. Our own capture overlay (above) handles all
    -- key/mouse/wheel input; these hooks only manage hover + visuals. Do NOT
    -- EnableMouseWheel on the Blizzard button -- with no wheel handler it would swallow
    -- scroll and break the macro list; the overlay owns the wheel.
    if not button.QuickKeybindHighlightTexture then
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints(button)
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0.5)
        tex:Hide()
        button.QuickKeybindHighlightTexture = tex
    end

    button:HookScript("OnShow", function(self)
        _quickKeybindState.RefreshMacroButton(self)
    end)
    button:HookScript("OnHide", function(self)
        _quickKeybindState.RefreshMacroButton(self, false)
    end)
    button:HookScript("OnClick", function(self)
        _quickKeybindState.UpdateMacroButtonCommand(self)
        if _quickKeybindState.open then
            _quickKeybindState.SetMacroButtonTooltip(self)
        end
    end)
    button:HookScript("OnEnter", function(self)
        _quickKeybindState.SelectMacroButton(self)
    end)
    button:HookScript("OnLeave", function(self)
        -- The overlay sits over the button, so the button's OnLeave fires the
        -- instant we park it. Ignore that case; the overlay's own OnLeave tears
        -- down when the cursor truly leaves.
        local frame = _quickKeybindState.macroBindFrame
        if frame and frame:IsShown() and frame.button == self then return end
        if _quickKeybindState.hoveredMacroButton == self then
            _quickKeybindState.hoveredMacroButton = nil
        end
        if QuickKeybindTooltip then QuickKeybindTooltip:Hide() end
        _quickKeybindState.RefreshMacroButton(self)
    end)

    local fd = EFD(button)
    fd.qkbMacroHooked = true
    _quickKeybindState.macroButtons[button] = true
    _quickKeybindState.RefreshMacroButton(button)
end

_quickKeybindState.UpdateMacroButtons = function(show)
    if show == false then
        _quickKeybindState.HideMacroBindFrame()
    end
    for button in pairs(_quickKeybindState.macroButtons) do
        _quickKeybindState.RefreshMacroButton(button, show)
    end
end

_quickKeybindState.InitMacroFrame = function()
    if _quickKeybindState.macroFrameHooked or not MacroFrame or not QuickKeybindButtonTemplateMixin then return end

    _quickKeybindState.InitMacroButton(MacroFrameSelectedMacroButton or MacroFrame.SelectedMacroButton)

    local scrollBox = MacroFrame.MacroSelector and MacroFrame.MacroSelector.ScrollBox
    if not scrollBox or not scrollBox.ForEachFrame then return end

    _quickKeybindState.macroScrollUpdate = function(frame)
        if not frame or not frame.GetView or not frame:GetView() then return end
        frame:ForEachFrame(_quickKeybindState.InitMacroButton)
        _quickKeybindState.UpdateMacroButtons(_quickKeybindState.open)
    end
    C_Timer_After(0, function()
        _quickKeybindState.macroScrollUpdate(scrollBox)
    end)
    hooksecurefunc(scrollBox, "Update", _quickKeybindState.macroScrollUpdate)

    _quickKeybindState.macroFrameHooked = true
    _quickKeybindState.UpdateMacroButtons(_quickKeybindState.open)
end

local function EAB_UpdateQuickKeybindVisibility(show)
    if InCombatLockdown() then return end

    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local s = EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars[key]
        local frame = barFrames[key]

        if show and frame and ShouldQuickKeybindSurfaceBar(s) then
            RegisterAttributeDriver(frame, "state-visibility", "show")
            -- Keep the visibility cache in sync with the driver we just set.
            -- Otherwise RefreshRuntimeVisibility on QKB exit sees the stale
            -- pre-QKB string still equal to the recomputed real string and
            -- skips re-registering, leaving conditionally-hidden bars
            -- (notably the Pet Bar on non-pet classes) stuck on "show" until reload.
            frame._eabLastVisStr = "show"
            frame:Show()
            SafeEnableMouseMotionOnly(frame, true)
        end

        local buttons = barButtons[key]
        if buttons then
            for _, btn in ipairs(buttons) do
                if btn then
                    _quickKeybindState.art.ApplyButtonHighlightAlpha(btn, show)
                end
            end
        end

        if not info.isStance and not info.isPetBar then
            if buttons then
                for _, btn in ipairs(buttons) do
                    if btn then
                        SetShowGridInsecure(btn, show, SHOWGRID.KEYBOUND)
                    end
                end
            end
        end
    end

    _quickKeybindState.art.ForEachSpecialButton(function(btn)
        _quickKeybindState.art.ApplyButtonHighlightAlpha(btn, show)
    end)

    if show then
        for _, info in ipairs(BAR_CONFIG) do
            local key = info.key
            local s = EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars[key]
            local frame = barFrames[key]
            local state = hoverStates[key]
            if frame and ShouldQuickKeybindSurfaceBar(s) and s.mouseoverEnabled then
                StopFade(frame, 1)
                if state then state.fadeDir = "in" end
                if key == "MainBar" then SyncPagingAlpha(1) end
            end
            EAB:ApplyAlwaysShowButtons(key)
            EAB:ApplyClickThroughForBar(key)
        end
    else
        -- Pad verdict back first (the open flag is already down), so the
        -- drivers below compile Hide Bar When Using Gamepad again.
        EAB._PadSync()
        EAB:ApplyCombatVisibility()
        EAB:RefreshRuntimeVisibility()
        for _, info in ipairs(BAR_CONFIG) do
            EAB:ApplyAlwaysShowButtons(info.key)
            EAB:ApplyClickThroughForBar(info.key)
        end
        EAB:RefreshMouseover()
    end

    if _pagingFrame then
        LayoutPagingFrame()
    end
end

_quickKeybindState.FinishClose = function()
    _quickKeybindState.closePending = false
    -- Restore action type on buttons that were suppressed during QKB mode. This handles
    -- the deferred-close-during-combat case where SetAttribute was blocked earlier.
    EAB_UpdateQuickKeybindButtons(false)
    EAB_UpdateQuickKeybindVisibility(false)
    -- Restore bar strata if HideDim couldn't (combat-deferred close)
    if _quickKeybindState.strataCache and not InCombatLockdown() then
        for frame, orig in pairs(_quickKeybindState.strataCache) do
            frame:SetFrameStrata(orig)
        end
        _quickKeybindState.strataCache = nil
    end
end

-- One-time initialization: hook QKB scripts on all action buttons so mouse
-- binding works. ActionBarButtonTemplate provides the mixin methods but
-- Blizzard only wires OnClick/OnEnter/OnLeave on buttons it knows by name
-- (ActionButton1-12, MultiBar*, etc.); our custom EABButtons need explicit
-- hookup for mouse-button binding to communicate with QKB.
_quickKeybindState.InitButtons = function()
    if _quickKeybindState.buttonsInit then return end
    if not QuickKeybindButtonTemplateMixin then return end
    _quickKeybindState.buttonsInit = true
    local PP = EllesmereUI and EllesmereUI.PP
    local EG = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local buttons = barButtons[info.key]
            if buttons then
                for _, btn in ipairs(buttons) do
                    if btn and btn.commandName then
                        if not btn.QuickKeybindButtonOnClick then
                            Mixin(btn, QuickKeybindButtonTemplateMixin)
                        end
                        local fd = EFD(btn)
                        if not fd.qkbClickHooked and btn.QuickKeybindButtonOnClick then
                            btn:HookScript("OnClick", btn.QuickKeybindButtonOnClick)
                            btn:HookScript("OnEnter", btn.QuickKeybindButtonOnEnter)
                            btn:HookScript("OnLeave", btn.QuickKeybindButtonOnLeave)
                            -- Accent border + highlight color on hover during QKB
                            btn:HookScript("OnEnter", function(self)
                                if not _quickKeybindState.open then return end
                                if not EG then return end
                                local fd = EFD(self)
                                if fd.borders and PP then
                                    PP.UpdateBorder(self, nil, EG.r, EG.g, EG.b, 0.9)
                                    fd.borderKey = nil
                                end
                                local hl = self.HighlightTexture
                                if hl then hl:SetVertexColor(EG.r, EG.g, EG.b, 1) end
                                fd.qkbHoverActive = true
                            end)
                            btn:HookScript("OnLeave", function(self)
                                local fd = EFD(self)
                                if not fd.qkbHoverActive then return end
                                fd.qkbHoverActive = nil
                                fd.borderKey = nil
                                local bk = fd.barKey
                                if bk and PP then
                                    EAB:ApplyBordersForBar(bk)
                                end
                                local hl = self.HighlightTexture
                                if hl then
                                    local p = EAB and EAB.db and EAB.db.profile
                                    local useCC = p and p.highlightUseClassColor
                                    local cc = (p and p.highlightCustomColor) or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
                                    local hr, hg, hb = cc.r, cc.g, cc.b
                                    if useCC then
                                        local _, ct = UnitClass("player")
                                        local c2 = ct and RAID_CLASS_COLORS[ct]
                                        if c2 then hr, hg, hb = c2.r, c2.g, c2.b end
                                    end
                                    hl:SetVertexColor(hr, hg, hb, 1)
                                end
                                local bk = EFD(self).barKey
                                local s = bk and EAB.db and EAB.db.profile
                                    and EAB.db.profile.bars and EAB.db.profile.bars[bk]
                                if s and PP then
                                    local c = s.borderColor or { r = 0, g = 0, b = 0, a = 1 }
                                    local cr, cg, cb, ca = c.r, c.g, c.b, c.a or 1
                                    if s.borderClassColor then
                                        local _, ct = UnitClass("player")
                                        local cc = ct and RAID_CLASS_COLORS[ct]
                                        if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                                    end
                                    local sz, px = ResolveBorderThickness(s)
                                    -- Solid strips: an exact size flows only for a solid bar
                                    -- (a textured bar's exact size is its edge art, not a strip).
                                    if px and (s.borderTexture or "solid") == "solid" then sz = px end
                                    if sz > 0 then
                                        PP.UpdateBorder(self, sz, cr, cg, cb, ca)
                                    else
                                        PP.HideBorder(self)
                                    end
                                end
                            end)
                            fd.qkbClickHooked = true
                        end
                    end
                end
            end
        end
    end
end

-- Dim overlay: darkens the rest of the UI while Quick Keybind mode is active.
-- Action bars are raised above it so they remain visually prominent.
_quickKeybindState.GetDimOverlay = function()
    if _quickKeybindState.dimFrame then return _quickKeybindState.dimFrame end
    local dim = CreateFrame("Frame", nil, UIParent)
    dim:SetFrameStrata("HIGH")
    dim:SetFrameLevel(0)
    dim:SetAllPoints(UIParent)
    dim:EnableMouse(false)
    dim:SetMouseClickEnabled(false)
    dim:SetMouseMotionEnabled(false)
    local tex = dim:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0, 0.40)
    dim:SetAlpha(0)
    dim:Hide()
    _quickKeybindState.dimFrame = dim
    return dim
end

_quickKeybindState.ShowDim = function()
    local dim = _quickKeybindState.GetDimOverlay()
    dim:Show()
    UIFrameFadeIn(dim, 0.2, dim:GetAlpha(), 1)
    -- Raise action bar frames above the dim
    for _, info in ipairs(BAR_CONFIG) do
        local frame = barFrames[info.key]
        if frame and not InCombatLockdown() then
            if not _quickKeybindState.strataCache then
                _quickKeybindState.strataCache = {}
            end
            if not _quickKeybindState.strataCache[frame] then
                _quickKeybindState.strataCache[frame] = frame:GetFrameStrata()
            end
            frame:SetFrameStrata("DIALOG")
        end
    end
    if _pagingFrame and not InCombatLockdown() then
        if not _quickKeybindState.strataCache then _quickKeybindState.strataCache = {} end
        if not _quickKeybindState.strataCache[_pagingFrame] then
            _quickKeybindState.strataCache[_pagingFrame] = _pagingFrame:GetFrameStrata()
        end
        _pagingFrame:SetFrameStrata("DIALOG")
    end
end

_quickKeybindState.HideDim = function()
    local dim = _quickKeybindState.dimFrame
    if not dim then return end
    UIFrameFadeOut(dim, 0.2, dim:GetAlpha(), 0)
    C_Timer_After(0.2, function()
        if dim:GetAlpha() < 0.01 then dim:Hide() end
    end)
    -- Restore bar strata
    if _quickKeybindState.strataCache and not InCombatLockdown() then
        for frame, orig in pairs(_quickKeybindState.strataCache) do
            frame:SetFrameStrata(orig)
        end
        _quickKeybindState.strataCache = nil
    end
end

_quickKeybindState.Open = function()
    if _quickKeybindState.open then return end
    if InCombatLockdown() then return end
    _quickKeybindState.closePending = false
    _quickKeybindState.open = true
    -- Bars hidden by Hide Bar When Using Gamepad come back for binding: the
    -- open flag drops the pad verdict (EAB._PadSync), so they leave the Never
    -- set and surface below like any other runtime-hidden bar.
    if EAB._padHide then EAB:RefreshRuntimeVisibility() end
    _quickKeybindState.InitButtons()
    _quickKeybindState.InitMacroFrame()
    EAB_UpdateQuickKeybindButtons(true)
    _quickKeybindState.UpdateMacroButtons(true)
    EAB_UpdateQuickKeybindVisibility(true)
    _quickKeybindState.ShowDim()
end

local function EAB_QuickKeybindClose()
    if not _quickKeybindState.open and not _quickKeybindState.closePending then return end
    _quickKeybindState.HideDim()
    if InCombatLockdown() then
        -- Drop the visual bind overlays immediately so Bar 1 does not look
        -- stuck in QuickKeybind mode, then defer the protected visibility
        -- cleanup until combat ends.
        _quickKeybindState.open = false
        _quickKeybindState.closePending = true
        EAB_UpdateQuickKeybindButtons(false)
        _quickKeybindState.UpdateMacroButtons(false)
        -- Mouseover fading is alpha-only and already operates during combat,
        -- so restore that presentation immediately even though secure
        -- visibility drivers still have to wait until combat ends.
        EAB:RefreshMouseover()
        ns.CombatQueue.Defer("QuickKeybindClose", function()
            if _quickKeybindState.closePending then
                _quickKeybindState.FinishClose()
            elseif _quickKeybindState.open
                and not (QuickKeybindFrame and QuickKeybindFrame:IsShown()) then
                EAB_QuickKeybindClose()
            end
        end)
        return
    end
    _quickKeybindState.open = false
    EAB_UpdateQuickKeybindButtons(false)
    _quickKeybindState.UpdateMacroButtons(false)
    _quickKeybindState.FinishClose()
end

-- Defer hook until QuickKeybindFrame exists (it loads after PLAYER_LOGIN).
local _qkbHookFrame = CreateFrame("Frame")
_qkbHookFrame:RegisterEvent("PLAYER_LOGIN")
_qkbHookFrame:RegisterEvent("ADDON_LOADED")
_qkbHookFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        C_Timer_After(1, function()
            local qkb = QuickKeybindFrame
            if qkb then
                if _pagingFrame then
                    InitPagingQuickKeybindButton(_pagingFrame._upBtn, "UI-HUD-ActionBar-PageUpArrow-Mouseover")
                    InitPagingQuickKeybindButton(_pagingFrame._downBtn, "UI-HUD-ActionBar-PageDownArrow-Mouseover")
                end
                -- Install a stable frame-owned wrapper once, then update
                -- target callbacks each session so /reload never stacks
                -- stale closures pointing at an old Lua chunk.
                local qfd = EFD(qkb)
                if not qfd.quickKeybindShowHook then
                    qfd.quickKeybindShowHook = function(frame)
                        local ffd = EFD(frame)
                        if ffd.quickKeybindOnShow then
                            ffd.quickKeybindOnShow()
                        end
                    end
                    qfd.quickKeybindHideHook = function(frame)
                        local ffd = EFD(frame)
                        if ffd.quickKeybindOnHide then
                            ffd.quickKeybindOnHide()
                        end
                    end
                    qkb:HookScript("OnShow", qfd.quickKeybindShowHook)
                    qkb:HookScript("OnHide", qfd.quickKeybindHideHook)
                end
                qfd.quickKeybindOnShow = _quickKeybindState.Open
                qfd.quickKeybindOnHide = EAB_QuickKeybindClose
                _quickKeybindState.InitMacroFrame()
                if _quickKeybindState.macroFrameHooked then
                    self:UnregisterEvent("ADDON_LOADED")
                end
            end
        end)
    elseif event == "ADDON_LOADED" and (addonName == "Blizzard_MacroUI" or addonName == "Blizzard_QuickKeybind") then
        _quickKeybindState.InitMacroFrame()
        if _quickKeybindState.macroFrameHooked then
            self:UnregisterEvent("ADDON_LOADED")
        end
    end
end)

-------------------------------------------------------------------------------
--  Swiftmend Brightness Fix (action bar scan): scans all EABButton slots for
--  Swiftmend by matching icon file ID. Re-scans on slot changes so bar
--  rearrangement is covered.
-------------------------------------------------------------------------------
;(function()
    local function ScanABSwiftmend()
        local _, cls = UnitClass("player")
        if cls ~= "DRUID" then return end
        local hook   = EllesmereUI and EllesmereUI._HookSwiftmendIcon
        local iconID = EllesmereUI and EllesmereUI._SWIFTMEND_ICON
        if not hook or not iconID then return end
        for slot = 1, 180 do
            local btn = _G["EABButton" .. slot]
            if btn and btn.icon then
                local t = btn.icon:GetTexture()
                if not issecretvalue(t) and t == iconID then hook(btn.icon) end
            end
        end
    end
    _G._EAB_ScanSwiftmend = ScanABSwiftmend
    -- The scan is druid-only (it bails on class), so non-druids get no
    -- listener at all: class never changes within a session.
    local _, _playerCls = UnitClass("player")
    if _playerCls ~= "DRUID" then return end
    local f = ns.TakeShell()
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    -- Coalesced: one 0.5s rescan window at a time. ACTIONBAR_SLOT_CHANGED can
    -- storm (mouseover-conditional macros re-resolving on every flip);
    -- scheduling a timer per event ran the full scan dozens of times/sec.
    local _smPending = false
    local function SwiftmendRescan()
        _smPending = false
        ScanABSwiftmend()
    end
    f:SetScript("OnEvent", function()
        if not _smPending then
            _smPending = true
            C_Timer.After(0.5, SwiftmendRescan)
        end
    end)
end)()

ns.EAB_UpdateQuickKeybindButtons = EAB_UpdateQuickKeybindButtons -- called by the main file
