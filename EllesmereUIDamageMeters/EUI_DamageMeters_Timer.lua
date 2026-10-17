if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_DamageMeters_Timer.lua
--
--  The standalone combat timer, the show/hide hotkey and the timer's
--  unlock element.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._dmInternals
-- EllesmereUIDamageMeters.lua or an earlier EUI_DamageMeters_*.lua file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = EllesmereUI

local DB, MAX_WINDOWS, _windows = I.DB, I.MAX_WINDOWS, I._windows
local GetCurrentViewDuration, FormatTimer = I.GetCurrentViewDuration, I.FormatTimer
local FormatTimerDecimal, GetAccentRGB = I.FormatTimerDecimal, I.GetAccentRGB
local SetDMFont, SetSATimer = I.SetDMFont, I.SetSATimer
local SetUpdateSATimerText = I.SetUpdateSATimerText

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._dmInternals, which hands the value to every copy.
local _inCombat = I._inCombat
I.inCombatSetters[#I.inCombatSetters + 1] = function(v) _inCombat = v end
local _needsFinalRefresh = I._needsFinalRefresh
I.needsFinalRefreshSetters[#I.needsFinalRefreshSetters + 1] = function(v) _needsFinalRefresh = v end
local _ttFrame
I.ttFrameSetters[#I.ttFrameSetters + 1] = function(v) _ttFrame = v end

-- Assigned below and handed to the earlier files (SetUpdateSATimerText).
local UpdateSATimerText

-- Standalone Combat Timer
local _saTimer  -- frame reference
local _saTimerFS -- fontstring
I.saTimerSetters[#I.saTimerSetters + 1] = function(v) _saTimer = v end
local _saTimerBG -- backdrop texture
local _saTimerBorder -- PP border child frame
local _saTimerPreview = false
local _saTimerLive = false  -- last live/idle state seen (drives OOC desaturation)

local function GetSATimerPreviewText()
    return DB().standaloneTimerDecimal and "11:37.0" or "11:37"
end

-- Per-user font override for the standalone timer only (standaloneTimerFont,
-- a dropdown key: "__global"/nil = follow the Damage Meters module font).
local function GetSATimerFontOverride()
    local key = DB().standaloneTimerFont
    if key and key ~= "__global" and EllesmereUI and EllesmereUI.ResolveFontName then
        local path = EllesmereUI.ResolveFontName(key)
        if path and path ~= "" then return path end
    end
    return nil
end

local function GetSATimerColor()
    local cfg = DB()
    if cfg.standaloneTimerUseAccent then return GetAccentRGB() end
    local c = cfg.standaloneTimerColor
    return c and c.r or 1, c and c.g or 1, c and c.b or 1
end

local function ApplySATimerColor()
    if not _saTimerFS then return end
    local cfg = DB()
    local r, g, b = GetSATimerColor()
    if cfg.standaloneTimerDesatOOC and not (_inCombat or _needsFinalRefresh) then
        -- Luminance gray: desaturation keeps the configured color's brightness
        local l = 0.299 * r + 0.587 * g + 0.114 * b
        r, g, b = l, l, l
    end
    _saTimerFS:SetTextColor(r, g, b, 1)
end

local function ApplySATimerStyle()
    if not _saTimer or not _saTimerFS then return end
    local cfg = DB()
    _saTimer:SetFrameStrata(cfg.standaloneTimerStrata or "HIGH")

    local outline = cfg.standaloneTimerOutline or "INHERIT"
    local outlineFlags
    if outline == "NONE" then
        outlineFlags = ""
    elseif outline == "THICKOUTLINE" then
        outlineFlags = "THICKOUTLINE"
    elseif outline == "INHERIT" then
        outlineFlags = nil
    else
        outlineFlags = "OUTLINE"
    end
    SetDMFont(_saTimerFS, cfg.standaloneTimerSize or 26, outlineFlags, GetSATimerFontOverride())
    ApplySATimerColor()

    local previousText = _saTimerFS:GetText()
    -- Auto-size worst case must cover the decimal form, or live tenths clip.
    _saTimerFS:SetText(cfg.standaloneTimerDecimal and "99:99.9" or "99:99")
    local autoWidth = (_saTimerFS:GetStringWidth() or 30) + 4
    local autoHeight = (_saTimerFS:GetStringHeight() or 14) + 4
    _saTimerFS:SetText(previousText)
    _saTimer:SetSize(cfg.standaloneTimerWidth and math.max(40, cfg.standaloneTimerWidth) or autoWidth,
                     cfg.standaloneTimerHeight and math.max(20, cfg.standaloneTimerHeight) or autoHeight)

    if _saTimerBG then
        local c = cfg.standaloneTimerBackgroundColor or { r = 0, g = 0, b = 0, a = 0 }
        _saTimerBG:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, c.a or 0)
    end

    if _saTimerBorder then
        local PP = EllesmereUI and EllesmereUI.PP
        local c = cfg.standaloneTimerBorderColor or { r = 0, g = 0, b = 0, a = 1 }
        local borderSize = math.max(0, math.floor((cfg.standaloneTimerBorderSize or 0) + 0.5))
        if borderSize > 0 and PP and PP.UpdateBorder then
            PP.UpdateBorder(_saTimerBorder, borderSize, c.r or 0, c.g or 0, c.b or 0, c.a == nil and 1 or c.a)
            _saTimerBorder:Show()
        else
            _saTimerBorder:Hide()
        end
    end

    _saTimerFS:ClearAllPoints()
    local borderSize = cfg.standaloneTimerBorderSize or 0
    local inset = borderSize > 0 and borderSize + 3 or 0
    _saTimerFS:SetPoint("LEFT", _saTimer, "LEFT", inset, 0)
    _saTimerFS:SetPoint("RIGHT", _saTimer, "RIGHT", -inset, 0)
    -- Preserve the old binary left-align preference until the user chooses
    -- a value in the new three-way alignment control.
    local textAlign = cfg.standaloneTimerTextAlign
    if not textAlign then
        local anchor = cfg.standaloneTimerAnchor or "free"
        if anchor == "free" then
            textAlign = cfg.standaloneTimerAlignLeft and "LEFT" or "RIGHT"
        else
            textAlign = (anchor == "topleft" or anchor == "bottomleft") and "LEFT" or "RIGHT"
        end
    end
    _saTimerFS:SetJustifyH(textAlign)
end

-- Decimal display: API duration is whole seconds, so tenths are derived from a GetTime() anchor
-- reset on every API value change -- display-only smoothing clamped inside the current second; the API stays authoritative and re-anchors each tick, so it cannot drift.
local _saDecBase, _saDecAnchor = nil, 0

UpdateSATimerText = function()
    if not _saTimer or not _saTimerFS then return end
    local cfg = DB()
    if not cfg.standaloneTimer then return end
    -- The timer runs on its own ticker and re-shows itself every 0.1s, so the hotkey
    -- toggle has to be checked here rather than hiding the frame from the outside
    if ns._toggleHidden and cfg.toggleIncludeTimer and not ns._optionsOpen
       and not EUI._unlockActive and not _saTimerPreview then
        if _saTimer:IsShown() then _saTimer:Hide() end
        return
    end
    -- Same source as the window's Current timer so the two can never disagree. Visible while
    -- combat is live (or polling a group fight we're not in); out of combat it hides unless Show Out of Combat keeps it up (last fight's frozen duration).
    local live = _inCombat or _needsFinalRefresh
    if live or cfg.standaloneTimerShowOOC then
        if not _saTimer:IsShown() and not _saTimerPreview then _saTimer:Show() end
        if live or not _saTimerPreview then
            local dur = GetCurrentViewDuration()
            if cfg.standaloneTimerDecimal then
                if live then
                    if dur ~= _saDecBase then
                        _saDecBase = dur
                        _saDecAnchor = GetTime()
                    end
                    local frac = GetTime() - _saDecAnchor
                    if frac > 0.9 then frac = 0.9 end
                    dur = dur + frac
                end
                _saTimerFS:SetText(FormatTimerDecimal(dur))
            else
                _saTimerFS:SetText(FormatTimer(dur))
            end
        end
    else
        if not _saTimerPreview then
            if _saTimer:IsShown() then _saTimer:Hide() end
            _saTimerFS:SetText("")
        end
    end
    if _saTimerLive ~= live then
        _saTimerLive = live
        ApplySATimerColor()
    end
end
SetUpdateSATimerText(UpdateSATimerText)

local function RepositionSATimer()
    if not _saTimer then return end
    local cfg = DB()
    -- While the timer has a live unlock anchor link, the anchor system owns
    -- its position -- do not fight it.
    if EUI.IsUnlockAnchored and EUI.IsUnlockAnchored("EDM_CombatTimer") then
        return
    end
    local anchor = cfg.standaloneTimerAnchor or "free"

    _saTimer:ClearAllPoints()

    if anchor == "free" then
        -- Lock Position & Disable Click: click-through and immovable; the
        -- shift+drag lane only exists while unlocked. Our own frame, so the
        -- direct mouse-state writes are safe.
        local locked = cfg.standaloneTimerLocked == true
        _saTimer:SetMovable(not locked)
        _saTimer:EnableMouse(not locked)
        if _saTimer.EnableMouseMotion then _saTimer:EnableMouseMotion(not locked) end
        local pos = cfg.standaloneTimerPos
        if pos and pos.point then
            _saTimer:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        elseif pos and pos.x and pos.y then
            -- Legacy drag format: TOPLEFT offset from UIParent's BOTTOMLEFT
            _saTimer:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
        else
            local W1 = _windows[1]
            if W1 and W1.frame then
                _saTimer:SetPoint("BOTTOMRIGHT", W1.frame, "TOPRIGHT", 0, 5)
            else
                _saTimer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
        return
    end

    _saTimer:SetMovable(false)
    _saTimer:EnableMouse(false)
    if _saTimer.EnableMouseMotion then _saTimer:EnableMouseMotion(false) end

    -- Find the highest (max top) and lowest (min bottom) window
    local topWin, botWin
    local maxTop, minBot = -math.huge, math.huge
    for _, w in ipairs(_windows) do
        if w.frame and w.frame:IsShown() then
            local t = w.frame:GetTop()
            local b = w.frame:GetBottom()
            if t and t > maxTop then maxTop = t; topWin = w end
            if b and b < minBot then minBot = b; botWin = w end
        end
    end

    local isTop = anchor == "topleft" or anchor == "topright"
    local isLeft = anchor == "topleft" or anchor == "bottomleft"
    local ref = isTop and topWin or botWin

    if not ref or not ref.frame then
        _saTimer:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end

    if isTop and isLeft then
        _saTimer:SetPoint("BOTTOMLEFT", ref.frame, "TOPLEFT", 0, 0)
    elseif isTop then
        _saTimer:SetPoint("BOTTOMRIGHT", ref.frame, "TOPRIGHT", 0, 0)
    elseif isLeft then
        _saTimer:SetPoint("TOPLEFT", ref.frame, "BOTTOMLEFT", 0, 0)
    else
        _saTimer:SetPoint("TOPRIGHT", ref.frame, "BOTTOMRIGHT", 0, 0)
    end
end

-- Styles, places and hides the standalone timer as it is built (combat state then
-- decides whether it shows); a profile swap runs it again on the kept timer.
local function SetupSATimer()
    _saTimer:SetMovable(true)
    _saTimer:EnableMouse(true)
    ApplySATimerStyle()
    _saTimerFS:SetText("0:00")

    RepositionSATimer()

    _saTimer:Hide()  -- starts hidden; combat state controls visibility
    UpdateSATimerText()  -- Show Out of Combat can bring it straight back up
end

local function CreateSATimer()
    if _saTimer then return end
    local cfg = DB()

    SetSATimer(CreateFrame("Frame", "EllesmereUIDMStandaloneTimer", UIParent))
    _saTimer:SetSize(1, 1)
    _saTimer:SetClampedToScreen(true)
    _saTimer:SetFrameStrata("HIGH")
    _saTimer:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            local c = DB()
            -- Belt and braces: locked timers are click-through (EnableMouse
            -- off), so this handler should never fire while locked.
            if c.standaloneTimerLocked then return end
            if (c.standaloneTimerAnchor or "free") == "free" then self:StartMoving() end
        end
    end)
    _saTimer:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local c = DB()
        if (c.standaloneTimerAnchor or "free") == "free" then
            local left, top = self:GetLeft(), self:GetTop()
            if left and top then c.standaloneTimerPos = { x = left, y = top } end
        end
    end)

    _saTimerBG = _saTimer:CreateTexture(nil, "BACKGROUND")
    _saTimerBG:SetAllPoints()

    _saTimerBorder = CreateFrame("Frame", nil, _saTimer)
    _saTimerBorder:SetAllPoints(_saTimer)
    _saTimerBorder:SetFrameLevel(_saTimer:GetFrameLevel() + 5)
    local PP = EllesmereUI and EllesmereUI.PP
    if PP and PP.CreateBorder then PP.CreateBorder(_saTimerBorder, 0, 0, 0, 1, 1) end

    _saTimerFS = _saTimer:CreateFontString(nil, "OVERLAY")
    SetupSATimer()
end

ns.ApplySATimer = function()
    local cfg = DB()
    if cfg.standaloneTimer then
        if not _saTimer then CreateSATimer() end
        ApplySATimerStyle()
        local prevText = _saTimerFS:GetText()
        RepositionSATimer()
        if _saTimerPreview then
            _saTimerFS:SetText(GetSATimerPreviewText())
        else
            _saTimerFS:SetText(prevText or "0:00")
            UpdateSATimerText()
        end
    else
        if _saTimer then _saTimer:Hide() end
    end
end

ns.ShowSATimerPreview = function()
    if not _saTimer then CreateSATimer() end
    if not _saTimer then return end
    -- Show Out of Combat already keeps real data on screen (last segment duration, or 0:00) -- never clobber it with the preview value
    if DB().standaloneTimerShowOOC then
        UpdateSATimerText()
        return
    end
    _saTimerPreview = true
    _saTimerFS:SetText(GetSATimerPreviewText())
    _saTimer:Show()
end
ns.HideSATimerPreview = function()
    local wasPreview = _saTimerPreview
    _saTimerPreview = false
    if not _saTimer then return end
    local cfg = DB()
    if cfg.standaloneTimer and cfg.standaloneTimerShowOOC then
        -- Show Out of Combat was enabled during this preview session: swap the preview value for the real one (last segment, or 0:00)
        if wasPreview then UpdateSATimerText() end
        return
    end
    if not _inCombat then _saTimer:Hide() end
end

-------------------------------------------------------------------------------
--  Show/hide all windows hotkey
-------------------------------------------------------------------------------

-- Re-applies the current toggle state to every frame it covers. Also used by the
-- options page when the Combat Timer / Spell History checkboxes change while the
-- toggle is already active, so the newly included element follows immediately.
-- includeSpellHistory is read here rather than inside ApplySpellHistory because that
-- entry point rebuilds the icon strip and the bar window unconditionally; with the
-- default (Spell History not covered) the hotkey would pay both rebuilds per press.
ns.ApplyDMToggleState = function(includeSpellHistory)
    -- The row tooltip is parented to UIParent, not to the window, so it would be
    -- left floating if the hotkey is pressed while hovering a row
    if ns._toggleHidden and _ttFrame then _ttFrame:Hide() end
    for _, w in ipairs(_windows) do w.UpdateVisibility() end
    if _saTimer then UpdateSATimerText() end
    if includeSpellHistory == nil then includeSpellHistory = DB().toggleIncludeSpellHistory end
    if includeSpellHistory and ns.ApplySpellHistory then ns.ApplySpellHistory() end
end

ns.ToggleDMWindows = function()
    ns._toggleHidden = not ns._toggleHidden
    ns.ApplyDMToggleState()
    -- The mouseover scan caches each target's isActive answer per visibility
    -- generation, so without a bump it keeps the pre-toggle answer and re-shows a
    -- hover-gated window on the next pass. Deferred by a frame the way the
    -- dispatcher defers its own events: this runs from a hardware keypress, and
    -- other modules' updaters have no business running in that context.
    if EUI.RequestVisibilityUpdate then C_Timer.After(0, EUI.RequestVisibilityUpdate) end
end

-- Both damage meter hotkeys live on override bindings, which are protected: a rebind
-- during combat has to wait for regen (pressing the key itself is a hardware click and
-- works in combat). UPDATE_BINDINGS matters too -- LoadBindings, which the settings
-- panel runs on cancel and on a binding-set switch, drops every override, so a
-- configured key would otherwise stay dead until the next profile change. Our own
-- writes raise that event as well, hence the short self-write window.
-- Zero cost with no key: the event is registered only while a key is laid down, and a
-- pass that finds nothing configured and nothing applied never touches the binding API.
do
    local kbFrame = CreateFrame("Frame")
    local selfWriteUntil = 0
    -- The key each button currently carries (nil = none). Tracked apart from the
    -- configured key so that clearing a key still gets its one ClearOverrideBindings,
    -- and so a key dropped by LoadBindings is re-laid from the configured value.
    local appliedReset, appliedToggle

    local function WantKey(key)
        if key == nil or key == "" then return nil end
        return key
    end

    ns.ApplyDMKeybinds = function()
        local c = DB()
        local wantReset, wantToggle = WantKey(c.resetDataKey), WantKey(c.toggleWindowsKey)
        if not wantReset and not wantToggle and not appliedReset and not appliedToggle then
            kbFrame:UnregisterEvent("UPDATE_BINDINGS")
            return
        end
        if InCombatLockdown() then
            ns.CombatQueue.Defer("DMKeybinds", ns.ApplyDMKeybinds)
            return
        end
        selfWriteUntil = GetTime() + 0.5
        local resetBtn = _G.EllesmereUIDMResetBindBtn
        if resetBtn then
            ClearOverrideBindings(resetBtn)
            if wantReset then
                SetOverrideBindingClick(resetBtn, true, wantReset, "EllesmereUIDMResetBindBtn")
            end
            appliedReset = wantReset
        end
        local toggleBtn = _G.EllesmereUIDMToggleBindBtn
        if toggleBtn then
            ClearOverrideBindings(toggleBtn)
            if wantToggle then
                SetOverrideBindingClick(toggleBtn, true, wantToggle, "EllesmereUIDMToggleBindBtn")
            end
            appliedToggle = wantToggle
        end
        if wantReset or wantToggle then
            kbFrame:RegisterEvent("UPDATE_BINDINGS")
        else
            kbFrame:UnregisterEvent("UPDATE_BINDINGS")
        end
    end

    kbFrame:SetScript("OnEvent", function(_, event)
        -- Ours, echoing back: ignore, or we re-enter forever
        if event == "UPDATE_BINDINGS" and GetTime() < selfWriteUntil then return end
        ns.ApplyDMKeybinds()
    end)
end

-- Accent color callback for standalone timer
EUI.RegAccent({ type = "callback", fn = function()
    if not _saTimer or not _saTimerFS then return end
    local cfg = DB()
    if cfg.standaloneTimerUseAccent then
        ApplySATimerColor()
    end
end })

-- Unlock-mode element for the standalone timer, built on demand by ns.RegisterDMUnlock (lives here since the closures need the _saTimer upvalues above). Sizes to its text and would shift children, so it may anchor TO elements but never serve as an anchor target.
ns.MakeSATimerUnlockElement = function(MK)
    return MK({
        key   = "EDM_CombatTimer",
        label = "Combat Timer",
        group = "Damage Meters",
        order = 650 + MAX_WINDOWS + 1,
        noResize = true,
        noAnchorTarget = true,
        getFrame = function() return _saTimer end,
        getSize = function()
            if _saTimer then return _saTimer:GetWidth(), _saTimer:GetHeight() end
            return 60, 20
        end,
        isHidden = function() return not DB().standaloneTimer end,
        savePos = function(_, point, relPoint, x, y)
            local cfg = DB()
            cfg.standaloneTimerPos = { point = point, relPoint = relPoint or point, x = x, y = y }
            -- A manual unlock-mode move implies free placement: un-snap the window-anchor mode or RepositionSATimer would fight the drag
            if (cfg.standaloneTimerAnchor or "free") ~= "free" then
                cfg.standaloneTimerAnchor = "free"
            end
        end,
        loadPos = function()
            local pos = DB().standaloneTimerPos
            if not pos then return nil end
            if pos.point then
                return { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y }
            end
            if pos.x and pos.y then
                -- Legacy drag format: TOPLEFT offset from UIParent's BOTTOMLEFT
                return { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = pos.x, y = pos.y }
            end
            return nil
        end,
        clearPos = function() DB().standaloneTimerPos = nil end,
        applyPos = function() RepositionSATimer() end,
    })
end

I.CreateSATimer, I.SetupSATimer = CreateSATimer, SetupSATimer
I.UpdateSATimerText = UpdateSATimerText
I.broken = false
