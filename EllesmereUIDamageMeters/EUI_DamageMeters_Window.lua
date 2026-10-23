if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_DamageMeters_Window.lua
--
--  The context menu and CreateDMWindow, the factory of one meter window.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._dmInternals
-- EllesmereUIDamageMeters.lua or an earlier EUI_DamageMeters_*.lua file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = EllesmereUI
local L = _G.EllesmereUI.L

local BAR_POOL_SIZE, BAR_TEX, DB = I.BAR_POOL_SIZE, I.BAR_TEX, I.DB
local DM_TYPE_ICONS, DM_TYPE_NAMES, GetHeaderH = I.DM_TYPE_ICONS, I.DM_TYPE_NAMES, I.GetHeaderH
local ICON_ALPHA, ICON_HOVER_ALPHA = I.ICON_ALPHA, I.ICON_HOVER_ALPHA
local MAX_WINDOWS, MEDIA, MIN_H, MIN_W = I.MAX_WINDOWS, I.MEDIA, I.MIN_H, I.MIN_W
local PEAK_BUDGET, RANK_STRINGS, RESIZE_ICON = I.PEAK_BUDGET, I.RANK_STRINGS, I.RESIZE_ICON
local SESSION_TYPE_NAMES, SESSION_TYPES = I.SESSION_TYPE_NAMES, I.SESSION_TYPES
local _feignDeathGUIDs, _windows = I._feignDeathGUIDs, I._windows
local ApplyHeaderButtonsHoverVisibility = I.ApplyHeaderButtonsHoverVisibility
local CleanupFeignCache, GetBookmarks = I.CleanupFeignCache, I.GetBookmarks
local GetCurrentViewDuration = I.GetCurrentViewDuration
local LayoutHeaderButtons, WinDB, AbbrevNumber = I.LayoutHeaderButtons, I.WinDB, I.AbbrevNumber
local AggregateEnemyPlayers, ApplyBarTexture = I.AggregateEnemyPlayers, I.ApplyBarTexture
local BuildPlayerTargets, FormatBarValue = I.BuildPlayerTargets, I.FormatBarValue
local FormatTimer, GetAccentRGB = I.FormatTimer, I.GetAccentRGB
local GetBarTexturePath, GetBreakdownDuration = I.GetBarTexturePath, I.GetBreakdownDuration
local PhysicalPixels, ResolveIcon, SetDMFont = I.PhysicalPixels, I.ResolveIcon, I.SetDMFont
local StripRealm, _hoverPollFrame, _ttBars = I.StripRealm, I._hoverPollFrame, I._ttBars
local ApplyInheritedBlizzardBorder = I.ApplyInheritedBlizzardBorder
local EnsureTooltipFrame, HideBarTooltip = I.EnsureTooltipFrame, I.HideBarTooltip
local HideTTTargets, TT_HDR_H, TT_WIDTH = I.HideTTTargets, I.TT_HDR_H, I.TT_WIDTH
local SetActiveRow, SetCombatEndTime = I.SetActiveRow, I.SetCombatEndTime
local SetCurViewFrozenDur = I.SetCurViewFrozenDur

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._dmInternals, which hands the value to every copy.
local _ttFrame
I.ttFrameSetters[#I.ttFrameSetters + 1] = function(v) _ttFrame = v end

-- The player's GUID: set at login by EUI_DamageMeters_Lifecycle.lua
-- (SetPlayerGUID), read here only.
local _playerGUID
I.playerGUIDSetters[#I.playerGUIDSetters + 1] = function(v) _playerGUID = v end

-- EDM Context Menu (shared)
local _edmMenu, _edmSub
local CTX_ITEM_H   = 22
local CTX_HDR_H    = 20
local CTX_SEP_H    = 7
local CTX_PAD      = 0
local CTX_MIN_W    = 100
local CTX_FONT_SZ  = 11
local CTX_ARROW_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow.png"

local function MakeMenuPanel(level)
    local RS = EUI.RESKIN or {}
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(200 + (level or 0) * 10)
    f:SetClampedToScreen(true); f:EnableMouse(true)
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
    bg:SetColorTexture(RS.BG_R or 0.067, RS.BG_G or 0.067, RS.BG_B or 0.067, RS.CTX_ALPHA or 0.95)
    -- WoW Forever: Forever's dropdown panel in place of the EUI border.
    if not ns.DMFvMenuArt(f, bg) then
        local PP_L = EUI.PP
        if PP_L and PP_L.CreateBorder then PP_L.CreateBorder(f, 1, 1, 1, RS.BRD_ALPHA or 0.18, 1) end
        ApplyInheritedBlizzardBorder(f, "popupMenu")
    end
    f._pool = {}; f:Hide()
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:SetScript("OnEvent", function(self) self:Hide() end)
    return f
end

local function EnsureMenuRow(menu, idx)
    local row = menu._pool[idx]
    if row then return row end
    local fontPath = (EUI.GetFontPath("damageMeters")) or "Fonts\\FRIZQT__.TTF"
    local outline = (EUI.GetFontOutlineFlag("damageMeters")) or ""
    row = CreateFrame("Button", nil, menu)
    row._hl = row:CreateTexture(nil, "BACKGROUND", nil, 1); row._hl:SetAllPoints()
    row._lbl = row:CreateFontString(nil, "OVERLAY"); row._lbl:SetFont(fontPath, CTX_FONT_SZ, outline)
    row._lbl:SetPoint("LEFT", row, "LEFT", 8, 0); row._lbl:SetJustifyH("LEFT")
    row._arrow = row:CreateTexture(nil, "ARTWORK"); row._arrow:SetTexture(CTX_ARROW_ICON)
    row._arrow:SetSize(19, 19); row._arrow:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row._arrow:SetRotation(math.pi / 2); row._arrow:SetVertexColor(1, 1, 1, 0.75); row._arrow:Hide()
    row._timer = row:CreateFontString(nil, "OVERLAY"); row._timer:SetFont(fontPath, CTX_FONT_SZ, outline)
    row._timer:SetPoint("RIGHT", row, "RIGHT", -8, 0); row._timer:SetJustifyH("RIGHT"); row._timer:SetText("")
    row._sep = row:CreateTexture(nil, "ARTWORK"); row._sep:SetHeight(1)
    row._sep:SetPoint("LEFT", row, "LEFT", 6, 0); row._sep:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row._sep:SetColorTexture(1, 1, 1, 0.12); row._sep:SetPoint("CENTER"); row._sep:Hide()
    menu._pool[idx] = row
    return row
end

local function LayoutMenu(menu, items, onDismiss, isChild)
    if not menu._fvArt then ApplyInheritedBlizzardBorder(menu, "popupMenu") end
    local fontPath = (EUI.GetFontPath("damageMeters")) or "Fonts\\FRIZQT__.TTF"
    local outline = (EUI.GetFontOutlineFlag("damageMeters")) or ""
    -- WoW Forever: gold active and hovered items, tan timers (no accent).
    local fv = ns.DMForever()
    local EG = fv and ns.DM_FV.gold or EUI.ELLESMERE_GREEN
    local hlAlpha = EUI.DD_ITEM_HL_A or 0.08
    for _, r in ipairs(menu._pool) do r:Hide() end
    if not menu._mfs then menu._mfs = menu:CreateFontString(nil, "OVERLAY") end
    menu._mfs:SetFont(fontPath, CTX_FONT_SZ, outline)
    local maxW = 0
    for _, item in ipairs(items) do
        if type(item) == "table" and item.text then
            local extra = ""
            if item.timerText then extra = "  " .. item.timerText end
            menu._mfs:SetText(item.text .. extra); local w = menu._mfs:GetStringWidth() or 0
            if w > maxW then maxW = w end
        end
    end
    menu._mfs:SetText(""); menu._mfs:Hide()
    local menuW = math.max(CTX_MIN_W, maxW + 50)
    local y = -CTX_PAD
    for idx, item in ipairs(items) do
        local row = EnsureMenuRow(menu, idx)
        row._sep:Hide(); row._arrow:Hide(); row._hl:SetColorTexture(1, 1, 1, 0)
        if row._timer then row._timer:SetText("") end
        if item == "---" then
            row:SetSize(menuW, CTX_SEP_H); row:ClearAllPoints(); row:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, y)
            row._lbl:SetText(""); row._sep:Show(); row:EnableMouse(false)
            row:SetScript("OnEnter", nil); row:SetScript("OnLeave", nil); row:SetScript("OnClick", nil)
            row:Show(); y = y - CTX_SEP_H
        elseif item.isHeader then
            row:SetSize(menuW, CTX_HDR_H); row:ClearAllPoints(); row:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, y)
            row._lbl:SetFont(fontPath, CTX_FONT_SZ, outline); row._lbl:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row._lbl:SetText(item.text); row._lbl:SetTextColor(1, 0.82, 0, 1); row:EnableMouse(false)
            row:SetScript("OnEnter", nil); row:SetScript("OnLeave", nil); row:SetScript("OnClick", nil)
            row:Show(); y = y - CTX_HDR_H
        else
            local rowH = item.compact and (CTX_ITEM_H - 2) or CTX_ITEM_H
            row:SetSize(menuW, rowH); row:ClearAllPoints(); row:SetPoint("TOPLEFT", menu, "TOPLEFT", 0, y)
            row._lbl:SetFont(fontPath, CTX_FONT_SZ, outline)
            row._lbl:SetText(item.text or ""); row:EnableMouse(true)
            -- Timer text (accent-colored, right-aligned)
            if item.timerText and row._timer then
                row._timer:SetFont(fontPath, CTX_FONT_SZ, outline)
                local ar, ag, ab
                if fv then local c = ns.DM_FV.tan; ar, ag, ab = c.r, c.g, c.b else ar, ag, ab = GetAccentRGB() end
                row._timer:SetTextColor(ar, ag, ab, 0.9)
                row._timer:SetText(item.timerText)
                row._lbl:SetPoint("RIGHT", row._timer, "LEFT", -6, 0)
            else
                row._lbl:SetPoint("RIGHT", row, "RIGHT", -18, 0)
            end
            -- Inline input field (e.g. width entry)
            if item.isInput then
                row._lbl:SetTextColor(1, 1, 1, 1)
                row:EnableMouse(false)
                row:SetScript("OnEnter", nil); row:SetScript("OnLeave", nil); row:SetScript("OnClick", nil)
                if not row._editBox then
                    local box = CreateFrame("EditBox", nil, row)
                    box:SetSize(50, 18)
                    box:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                    box:SetFrameLevel(row:GetFrameLevel() + 3)
                    box:SetFont(fontPath, 10, outline)
                    box:SetTextColor(1, 1, 1, 0.9)
                    box:SetJustifyH("CENTER")
                    local boxBg = box:CreateTexture(nil, "BACKGROUND")
                    boxBg:SetAllPoints(); boxBg:SetColorTexture(0, 0, 0, 0.4)
                    box:SetAutoFocus(false)
                    box:SetNumeric(true)
                    box:SetMaxLetters(5)
                    row._editBox = box
                end
                row._editBox:Show()
                row._editBox:SetNumber(item.getValue and item.getValue() or 0)
                row._editBox:SetScript("OnEnterPressed", function(self)
                    local val = math.max(item.min or 1, math.floor(self:GetNumber() + 0.5))
                    self:SetNumber(val)
                    if item.setValue then item.setValue(val) end
                    self:ClearFocus()
                end)
                row._editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                row:Show(); y = y - rowH
            end
            if item.isInput then -- skip normal item logic
            else
            local disabled = item.isDisabled and item.isDisabled()
            if item.children then row._arrow:SetVertexColor(1, 1, 1, disabled and 0.2 or 0.75); row._arrow:Show() end
            if disabled then
                row._lbl:SetTextColor(0.4, 0.4, 0.4, 0.5)
                row:SetScript("OnEnter", function() if not isChild and _edmSub then _edmSub:Hide() end end)
                row:SetScript("OnLeave", nil); row:SetScript("OnClick", nil)
            else
                local active = item.isActive
                if active and EG then row._lbl:SetTextColor(EG.r, EG.g, EG.b, 1) else row._lbl:SetTextColor(1, 1, 1, 1) end
                if active then row._hl:SetColorTexture(1, 1, 1, hlAlpha); row._hl:Show() end
                local itemRef = item
                row:SetScript("OnEnter", function(self)
                    self._hl:SetColorTexture(1, 1, 1, hlAlpha)
                    if EG then self._lbl:SetTextColor(EG.r, EG.g, EG.b, 1) end
                    if itemRef.tooltip and EUI.ShowWidgetTooltip then EUI.ShowWidgetTooltip(self, itemRef.tooltip) end
                    if itemRef.children then
                        if not _edmSub then _edmSub = MakeMenuPanel(1) end
                        LayoutMenu(_edmSub, itemRef.children, onDismiss, true)
                        _edmSub:ClearAllPoints()
                        local right = self:GetRight(); local subW = _edmSub:GetWidth(); local screenW = UIParent:GetRight()
                        if right and subW and screenW and (right + subW) > screenW then
                            _edmSub:SetPoint("TOPRIGHT", self, "TOPLEFT", 0, 0)
                        else _edmSub:SetPoint("TOPLEFT", self, "TOPRIGHT", 0, 0) end
                        _edmSub:Show()
                    elseif not isChild and _edmSub then _edmSub:Hide() end
                end)
                row:SetScript("OnLeave", function(self)
                    EUI.HideWidgetTooltip()
                    self._hl:SetColorTexture(1, 1, 1, active and hlAlpha or 0)
                    if active and EG then self._lbl:SetTextColor(EG.r, EG.g, EG.b, 1) else self._lbl:SetTextColor(1, 1, 1, 1) end
                    if isChild then return end
                    if _edmSub and _edmSub:IsShown() and _edmSub:IsMouseOver() then return end
                    if _edmSub and itemRef.children then _edmSub:Hide() end
                end)
                row:SetScript("OnClick", function()
                    if itemRef.children then return end
                    if itemRef.onClick then itemRef.onClick() end
                    if onDismiss then onDismiss() end
                end)
            end
            if row._editBox then row._editBox:Hide() end
            row:Show(); y = y - rowH
            end -- close isInput else
        end
    end
    menu:SetSize(menuW, math.abs(y) + CTX_PAD)
end

local _edmMenuAnchor = nil  -- tracks which button opened the menu (for toggle)

local function ShowEDMMenu(items, anchorBtn)
    if not _edmMenu then
        _edmMenu = MakeMenuPanel(0)
        local acc = 0
        _edmMenu:SetScript("OnUpdate", function(self, dt)
            acc = acc + dt; if acc < 0.1 then return end; acc = 0
            local over = self:IsMouseOver()
                or (_edmSub and _edmSub:IsShown() and _edmSub:IsMouseOver())
                or (_edmMenuAnchor and _edmMenuAnchor:IsMouseOver())
            if not over and IsMouseButtonDown("LeftButton") then self:Hide() end
        end)
        _edmMenu:HookScript("OnHide", function()
            if _edmSub then _edmSub:Hide() end
            _edmMenuAnchor = nil
            EUI.HideWidgetTooltip()
        end)
    end

    -- Toggle: if same button clicked again while menu is open, close it
    if anchorBtn and _edmMenu:IsShown() and _edmMenuAnchor == anchorBtn then
        _edmMenu:Hide()
        return
    end

    local function dismiss() _edmMenu:Hide(); if _edmSub then _edmSub:Hide() end end
    LayoutMenu(_edmMenu, items, dismiss)
    _edmMenu:ClearAllPoints()
    if anchorBtn then
        _edmMenu:SetPoint("BOTTOMRIGHT", anchorBtn, "TOPRIGHT", 0, 0)
    else
        local scale = _edmMenu:GetEffectiveScale(); local cx, cy = GetCursorPosition()
        _edmMenu:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    end
    _edmMenuAnchor = anchorBtn
    _edmMenu:Show()
end

-- Window Factory: creates a fully independent damage meter window with its own frame tree, bar
-- pool, scroll state, source window, home screen, and refresh cycle. Returns a window table W with all state and a Destroy method.
local UpdateSATimerText  -- forward declaration (defined in EUI_DamageMeters_Timer.lua)
I.updateSATimerTextSetters[#I.updateSATimerTextSetters + 1] = function(v) UpdateSATimerText = v end

local function CreateDMWindow(winIdx)
    -- Function-locals, not upvalues: this function sits at Lua 5.1's
    -- 60-upvalue cap (see the notes at ns._AnchorBreakdownFrame and the
    -- syncSegments switch), so the secret helpers come back in through ns.
    local IsSecret, IsOwnRow = ns._IsSecret, ns._IsOwnRow
    local wdb = WinDB(winIdx)
    local W = {}
    W.idx = winIdx
    W.curDMType    = wdb.curDMType or Enum.DamageMeterType.DamageDone
    -- A type this client does not offer (WoW Forever's Threat without Forever
    -- Essentials, or in a profile brought elsewhere) reads as Damage Done; the
    -- saved choice stays.
    if not DM_TYPE_NAMES[W.curDMType] then W.curDMType = Enum.DamageMeterType.DamageDone end
    W.curSession   = wdb.curSession or Enum.DamageMeterSessionType.Current
    W.curSessionID = nil
    W.visibleCount = 0
    W.isHovered    = false
    W.resizing     = false
    W.windowLocked = wdb.locked or false
    W.snapDisabled = wdb.snapDisabled or false
    W.sourceOpen   = false
    W.sourceGUID   = nil
    W.sourceCreatureID = nil
    W.sourceClass  = nil
    W.cachedSources = nil
    W.stickyAtTop  = false
    W.stickyGuard  = false
    W.refreshElapsed = 0
    W.hdrIcons     = {}
    local cfg = DB()
    local PP = EUI and EUI.PP

    -- Forward declarations (defined later in this function)
    local RefreshHome
    local RefreshUI
    local homeFrame

    -- Row factory
    local function MakeRow(parent)
        local bar = {}
        bar.row = CreateFrame("Button", nil, parent)
        bar.row:SetHeight(18); bar.row:EnableMouse(true); bar.row:RegisterForClicks("AnyUp")
        bar.fill = CreateFrame("StatusBar", nil, bar.row)
        bar.fill:SetMinMaxValues(0, 1); bar.fill:SetValue(0); bar.fill:SetStatusBarTexture(BAR_TEX)
        bar.classIcon = bar.fill:CreateTexture(nil, "OVERLAY")
        bar.classIcon:SetSize(18, 18); bar.classIcon:SetPoint("LEFT", bar.row, "LEFT", 0, 0)
        local _cz = DB().classIconZoom or 0.06
        bar.classIcon:SetTexCoord(_cz, 1 - _cz, _cz, 1 - _cz); bar.classIcon:Hide()
        -- Per-bar border (lazy-created, only when borderSize > 0)
        function bar.ApplyBorder()
            local c = DB()
            local sz = c.borderSize or 0
            -- Stock-style rows carry no EUI border: Blizzard Style draws the
            -- stock shadow edge, Classic WoW UI a plain bar.
            if sz <= 0 or ns.DMBlizz() or (c.barSeparators and ns.DMUseBarSeparators(c)) then
                if bar._borderFrame then bar._borderFrame:Hide() end
                if bar._fillBorder then bar._fillBorder:Hide() end
                return
            end
            -- Follow-fill mode: fill extent is SECRET geometry, so nothing may measure it
            -- (Backdrop/NineSlice crash on GetWidth of a frame anchored to it) -- render four
            -- plain color strips via engine anchors instead (left fixed, right rides the fill); always solid regardless of Border Style, styled path stays full-row only.
            if c.borderFollowFill then
                if bar._borderFrame then bar._borderFrame:Hide() end
                local fb = bar._fillBorder
                if not fb then
                    fb = CreateFrame("Frame", nil, bar.row)
                    fb:SetFrameLevel(bar.row:GetFrameLevel() + 3)
                    fb:SetPoint("TOPLEFT", bar.row, "TOPLEFT")
                    fb:SetSize(1, 1)  -- inert; the strips carry the shape
                    fb.top = fb:CreateTexture(nil, "OVERLAY")
                    fb.bottom = fb:CreateTexture(nil, "OVERLAY")
                    fb.left = fb:CreateTexture(nil, "OVERLAY")
                    fb.right = fb:CreateTexture(nil, "OVERLAY")
                    bar._fillBorder = fb
                end
                local ft = bar.fill:GetStatusBarTexture()
                local anchorL = c.borderFollowFillIcon and bar.row or bar.fill
                local r, g, b, a = c.borderR or 0, c.borderG or 0, c.borderB or 0, c.borderA or 1
                fb.top:SetColorTexture(r, g, b, a)
                fb.bottom:SetColorTexture(r, g, b, a)
                fb.left:SetColorTexture(r, g, b, a)
                fb.right:SetColorTexture(r, g, b, a)
                fb.top:ClearAllPoints()
                fb.top:SetPoint("TOPLEFT", anchorL, "TOPLEFT", 0, 0)
                fb.top:SetPoint("TOPRIGHT", ft, "TOPRIGHT", 0, 0)
                fb.top:SetHeight(sz)
                fb.bottom:ClearAllPoints()
                fb.bottom:SetPoint("BOTTOMLEFT", anchorL, "BOTTOMLEFT", 0, 0)
                fb.bottom:SetPoint("BOTTOMRIGHT", ft, "BOTTOMRIGHT", 0, 0)
                fb.bottom:SetHeight(sz)
                fb.left:ClearAllPoints()
                fb.left:SetPoint("TOPLEFT", anchorL, "TOPLEFT", 0, -sz)
                fb.left:SetPoint("BOTTOMLEFT", anchorL, "BOTTOMLEFT", 0, sz)
                fb.left:SetWidth(sz)
                fb.right:ClearAllPoints()
                fb.right:SetPoint("TOPRIGHT", ft, "TOPRIGHT", 0, -sz)
                fb.right:SetPoint("BOTTOMRIGHT", ft, "BOTTOMRIGHT", 0, sz)
                fb.right:SetWidth(sz)
                fb:Show()
                return
            end
            if bar._fillBorder then bar._fillBorder:Hide() end
            if not bar._borderFrame then
                bar._borderFrame = CreateFrame("Frame", nil, bar.row)
                bar._borderFrame:SetAllPoints(bar.row)
                bar._borderFrame:SetFrameLevel(bar.row:GetFrameLevel() + 3)
            end
            bar._borderFrame:Show()
            local tex = c.borderTexture or "solid"
            -- Exact size (nil = the legacy step path) only while it still pairs with sz + tex.
            local px = EllesmereUI.BorderPx(c.borderSizePx, sz, tex)
            EllesmereUI.ApplyBorderStyle(bar._borderFrame, sz,
                c.borderR or 0, c.borderG or 0, c.borderB or 0, c.borderA or 1,
                tex, c.borderTextureOffset, c.borderTextureOffsetY,
                c.borderTextureShiftX, c.borderTextureShiftY, "damagemeters", sz, nil, px)
        end
        bar.ApplyBorder()
        function bar.ApplyIconBorder()
            local c = DB()
            local sz = c.iconBorderSize or 0
            local showIcon = (c.iconStyle or "spec") ~= "none"
            if not c.customIconBorder or sz <= 0 or not showIcon then
                if bar._iconBorderFrame then bar._iconBorderFrame:Hide() end
                return
            end
            if not bar._iconBorderFrame then
                bar._iconBorderFrame = CreateFrame("Frame", nil, bar.row)
                bar._iconBorderFrame:SetFrameLevel(bar.row:GetFrameLevel() + 6)
                bar._iconBorderFrame:SetAllPoints(bar.classIcon) -- tracks icon size/position
            end
            local tex = c.iconBorderTexture or "solid"
            local px = EllesmereUI.BorderPx(c.iconBorderSizePx, sz, tex)
            EllesmereUI.ApplyBorderStyle(bar._iconBorderFrame, sz,
                c.iconBorderR or 0, c.iconBorderG or 0, c.iconBorderB or 0, c.iconBorderA or 1,
                tex, c.iconBorderTextureOffset, c.iconBorderTextureOffsetY,
                c.iconBorderTextureShiftX, c.iconBorderTextureShiftY, "damagemeters_icon", sz, nil, px)
            -- After styling: ApplyBorderStyle shows its target, and a border anchored to a hidden icon still draws.
            bar._iconBorderFrame:SetShown(bar.classIcon:IsShown())
        end
        bar.ApplyIconBorder()
        -- Per-bar track background (behind the fill). Default alpha 0 = invisible.
        bar._bg = bar.row:CreateTexture(nil, "BACKGROUND", nil, -8)
        bar._bg:SetAllPoints(bar.row)
        function bar.ApplyBg()
            local c = DB()
            -- Blizzard Style: the stock track and edge; Classic WoW UI keeps
            -- the plain track below.
            if ns.DMStyle() == "blizzard" then ns.DMApplyBlizzBarBg(bar); return end
            local a = c.barBgAlpha or 0
            -- Class-colored track when enabled: tint the bg with this bar's class color (x bg
            -- alpha), else the custom bg color. classFile can be secret, so guard before indexing
            -- (RAID_CLASS_COLORS[secret] throws); GetClassColor honors global overrides. Mirrors fill/text class coloring.
            if c.barBgUseClassColor then
                local cf = bar._class
                if cf and (not issecretvalue or not issecretvalue(cf)) and RAID_CLASS_COLORS[cf] then
                    local cc = EUI.GetClassColor(cf)
                    if cc then bar._bg:SetColorTexture(cc.r, cc.g, cc.b, a); return end
                end
            end
            bar._bg:SetColorTexture(c.barBgR or 0, c.barBgG or 0, c.barBgB or 0, a)
        end
        bar.ApplyBg()
        local tf = CreateFrame("Frame", nil, bar.fill)
        -- Keep text ABOVE the per-bar border (bar.row +3, lazy-created in ApplyBorder); keyed off
        -- bar.row like the border so the two can't tie and let a later-enabled border cover the text
        tf:SetAllPoints(bar.fill); tf:SetFrameLevel(bar.row:GetFrameLevel() + 4)
        bar.pos = tf:CreateFontString(nil, "OVERLAY"); bar.pos:SetPoint("LEFT", tf, "LEFT", 3, 0); SetDMFont(bar.pos, 11)
        bar.label = tf:CreateFontString(nil, "OVERLAY"); bar.label:SetPoint("LEFT", bar.pos, "RIGHT", 2, 0); bar.label:SetPoint("RIGHT", tf, "RIGHT", -70, 0); bar.label:SetJustifyH("LEFT"); SetDMFont(bar.label, 11)
        bar.label:SetWordWrap(false)
        bar.amount = tf:CreateFontString(nil, "OVERLAY"); bar.amount:SetPoint("RIGHT", tf, "RIGHT", -3, 0); bar.amount:SetJustifyH("RIGHT"); SetDMFont(bar.amount, 11)
        -- Bar Text X/Y offsets (Bar Text size cogs): re-applies the creation anchors above with
        -- profile offsets added. The label's Y rides its RIGHT point; LEFT already follows bar.pos on both axes.
        bar.ApplyTextOffsets = function()
            local c2 = DB()
            local lx, ly = c2.leftTextOffsetX or 0, c2.leftTextOffsetY or 0
            local rx, ry = c2.rightTextOffsetX or 0, c2.rightTextOffsetY or 0
            bar.pos:SetPoint("LEFT", tf, "LEFT", 3 + lx, ly)
            bar.label:SetPoint("RIGHT", tf, "RIGHT", -70, ly)
            bar.amount:SetPoint("RIGHT", tf, "RIGHT", -3 + rx, ry)
        end
        bar.ApplyTextOffsets()
        bar.row:SetScript("OnClick", function(_, button)
            if button == "LeftButton" then
                -- In combat, rows open when a PLAIN guid exists for them:
                -- death recaps (NeverSecret plain ID), the local player's
                -- own breakdown (own GUID plain), and group members via the
                -- identity-exempt token channel (ns._ResolveGroupGUID).
                -- Everything else keeps the block until combat ends.
                if InCombatLockdown() and not IsOwnRow(bar._src)
                   and W.curDMType ~= Enum.DamageMeterType.Deaths
                   and not ns._ResolveGroupGUID(bar._src) then
                    return
                end
                if bar._src and (bar._srcGUID or bar._src.sourceCreatureID) then
                    -- Deaths without recap data: block click
                    if W.curDMType == Enum.DamageMeterType.Deaths then
                        local rid = bar._src.deathRecapID
                        if not rid or (issecretvalue and issecretvalue(rid)) or rid <= 0 then return end
                        if C_DeathRecap and C_DeathRecap.GetRecapEvents then
                            local ok, raw = pcall(C_DeathRecap.GetRecapEvents, rid)
                            if not ok or not raw or #raw == 0 then return end
                        end
                    end
                    -- Rows mid-combat carry SECRET GUIDs the getters would
                    -- refuse as arguments; store a plain one instead so the
                    -- panel's per-tick refresh stays legal: own GUID for the
                    -- own row, the identity-exempt token guid for group rows.
                    -- Deaths rows keep their guid untouched (recap path).
                    local guid, cid = bar._srcGUID, bar._src.sourceCreatureID
                    if IsSecret(guid) or IsSecret(cid) then
                        if IsOwnRow(bar._src) then
                            guid, cid = UnitGUID("player"), nil
                        elseif W.curDMType ~= Enum.DamageMeterType.Deaths then
                            local rg = ns._ResolveGroupGUID(bar._src)
                            if rg then guid, cid = rg, nil end
                        end
                    end
                    W.OpenSource(guid, cid, StripRealm(bar._src.name), bar._class, bar._src.deathRecapID, bar._src.name)
                end
            elseif button == "RightButton" then
                W.ShowHome()
            end
        end)
        bar._hl = tf:CreateTexture(nil, "BACKGROUND")
        bar._hl:SetAllPoints(bar.row); bar._hl:SetColorTexture(1, 1, 1, 0.08); bar._hl:Hide()
        bar.row:SetScript("OnEnter", function()
            bar._hl:Show()
            -- Threat rows (WoW Forever) have no breakdown to show.
            if W.curDMType == "threat" then return end
            -- Deaths without recap: show "no recap available" tooltip
            if W.curDMType == Enum.DamageMeterType.Deaths and bar._src then
                local rid = bar._src.deathRecapID
                local hasRecap = rid and not (issecretvalue and issecretvalue(rid)) and rid > 0
                if hasRecap and C_DeathRecap and C_DeathRecap.GetRecapEvents then
                    local ok, raw = pcall(C_DeathRecap.GetRecapEvents, rid)
                    if not ok or not raw or #raw == 0 then hasRecap = false end
                end
                if not hasRecap then
                    EnsureTooltipFrame()
                    local playerName = StripRealm(bar._src.name, bar._src)
                    _ttFrame._hdrText:SetText(EllesmereUI.Lf("%1$s's Death Recap", playerName))
                    local cfg2 = DB()
                    local hc = cfg2.hdrBgColor; local hR = hc and hc.r or 0x1B/255; local hG = hc and hc.g or 0x1B/255; local hB = hc and hc.b or 0x1B/255
                    ns.DMPaintHeaderBg(_ttFrame._hdrBg, hR, hG, hB, cfg2.hdrBgAlpha or 1)
                    local tR, tG, tB
                    if cfg2.hdrTextUseAccent ~= false then tR, tG, tB = ns.DMTitleRGB()
                    else local tc = cfg2.hdrTextColor; tR = tc and tc.r or 1; tG = tc and tc.g or 1; tB = tc and tc.b or 1 end
                    _ttFrame._hdrText:SetTextColor(tR, tG, tB, 1)
                    for bi = 1, #_ttBars do if _ttBars[bi] then _ttBars[bi].row:Hide() end end
                    HideTTTargets()
                    _ttFrame._combatMsg:SetText(EllesmereUI.L("No death recap available"))
                    _ttFrame._combatMsg:Show()
                    _ttFrame:SetSize(TT_WIDTH, TT_HDR_H + 40)
                    ns._AnchorBreakdownFrame(bar.row, W.frame)
                    _ttFrame:Show()
                    return
                end
            end
            -- The combat message only for rows the API keeps unreadable:
            -- own breakdown, death recaps, and group rows resolvable through
            -- the identity-exempt token channel all fall through to the
            -- normal hover path, whose builders are secret-safe.
            -- Gated on Show Breakdown on Hover like ShowBarTooltip: with the option off
            -- this branch still showed the disclaimer for ally rows.
            if InCombatLockdown() and DB().showHoverTooltip ~= false
               and not IsOwnRow(bar._src)
               and W.curDMType ~= Enum.DamageMeterType.Deaths
               and not ns._ResolveGroupGUID(bar._src) then
                EnsureTooltipFrame()
                -- Show header with player name + type
                local playerName = StripRealm(bar._src and bar._src.name, bar._src)
                local typeName = L(DM_TYPE_NAMES[W.curDMType] or "Damage Done")
                _ttFrame._hdrText:SetText(EllesmereUI.Lf("%1$s's %2$s Breakdown", playerName, typeName))
                local cfg2 = DB()
                local hc = cfg2.hdrBgColor; local hR = hc and hc.r or 0x1B/255; local hG = hc and hc.g or 0x1B/255; local hB = hc and hc.b or 0x1B/255
                ns.DMPaintHeaderBg(_ttFrame._hdrBg, hR, hG, hB, cfg2.hdrBgAlpha or 1)
                local tR, tG, tB
                if cfg2.hdrTextUseAccent ~= false then tR, tG, tB = ns.DMTitleRGB()
                else local tc = cfg2.hdrTextColor; tR = tc and tc.r or 1; tG = tc and tc.g or 1; tB = tc and tc.b or 1 end
                _ttFrame._hdrText:SetTextColor(tR, tG, tB, 1)
                -- Hide bars, show combat message
                for bi = 1, #_ttBars do if _ttBars[bi] then _ttBars[bi].row:Hide() end end
                HideTTTargets()
                _ttFrame._combatMsg:SetText(EllesmereUI.L("Detailed information is\nsecret while in combat"))
                _ttFrame._combatMsg:Show()
                _ttFrame:SetSize(TT_WIDTH, TT_HDR_H + 40)
                ns._AnchorBreakdownFrame(bar.row, W.frame)
                _ttFrame:Show()
                return
            end
            SetActiveRow(bar); bar._win = W; _hoverPollFrame:Show()
        end)
        bar.row:SetScript("OnLeave", function()
            bar._hl:Hide()
            SetActiveRow(nil); _hoverPollFrame:Hide(); HideBarTooltip()
        end)
        bar._src = nil; bar._srcGUID = nil; bar._class = nil; bar._win = W
        bar.row:Hide()
        return bar
    end

    -- Spell tooltip on breakdown-row hover: uses the real GameTooltip for full native info
    -- (cooldown/range/cast time/description) -- deliberate exception to the no-GameTooltip rule,
    -- which exists to avoid taint in secure/chat-frame contexts; these rows are our own non-secure
    -- frames so SetOwner+SetSpellByID+Show is safe. Anchored LEFT via ANCHOR_NONE + manual SetPoint; bar._spellID is nil on non-spell rows, and secret-value + valid-spell checks guard the rest -- ShowWidgetTooltip's combat suppression does not apply here, so these guards are the only protection.
    local function ShowSpellRowTooltip(anchor, spellID)
        if not spellID or type(spellID) ~= "number" then return end
        local cfg = DB()
        if cfg and cfg.showSpellTooltips == false then return end
        if issecretvalue and issecretvalue(spellID) then return end
        -- Only show for a real, resolvable spell.
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
        if not name or (issecretvalue and issecretvalue(name)) then return end
        GameTooltip:SetOwner(anchor, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -6, 0)
        GameTooltip:SetSpellByID(spellID)
        GameTooltip:Show()
    end

    local function MakeSpellRow(parent)
        local bar = {}
        bar.row = CreateFrame("Button", nil, parent); bar.row:SetHeight(18); bar.row:EnableMouse(true); bar.row:RegisterForClicks("AnyUp")
        bar.fill = CreateFrame("StatusBar", nil, bar.row); bar.fill:SetMinMaxValues(0, 1); bar.fill:SetValue(0); bar.fill:SetStatusBarTexture(BAR_TEX)
        -- Blizzard Style: the same track and edge as the main rows (Classic
        -- WoW UI rows stay plain).
        if ns.DMStyle() == "blizzard" then
            bar._bg = bar.row:CreateTexture(nil, "BACKGROUND")
            ns.DMApplyBlizzBarBg(bar)
        end
        bar.classIcon = bar.fill:CreateTexture(nil, "OVERLAY"); bar.classIcon:SetSize(18, 18); bar.classIcon:SetPoint("LEFT", bar.row, "LEFT", 0, 0); bar.classIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92); bar.classIcon:Hide()
        local tf = CreateFrame("Frame", nil, bar.fill); tf:SetAllPoints(bar.fill); tf:SetFrameLevel(bar.fill:GetFrameLevel() + 2)
        bar.label = tf:CreateFontString(nil, "OVERLAY"); bar.label:SetPoint("LEFT", tf, "LEFT", 3, 0); bar.label:SetPoint("RIGHT", tf, "RIGHT", -70, 0); bar.label:SetJustifyH("LEFT"); SetDMFont(bar.label, 11)
        bar.label:SetWordWrap(false)
        bar.amount = tf:CreateFontString(nil, "OVERLAY"); bar.amount:SetPoint("RIGHT", tf, "RIGHT", -3, 0); bar.amount:SetJustifyH("RIGHT"); SetDMFont(bar.amount, 11)
        bar.row:SetScript("OnClick", function() W.CloseSource() end)
        bar.row:SetScript("OnEnter", function(self) ShowSpellRowTooltip(self, bar._spellID) end)
        bar.row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar._spellID = nil; bar.row:Hide()
        return bar
    end

    -- Main container
    local frame = CreateFrame("Frame", "EllesmereUIDMFrame" .. winIdx, UIParent)
    frame:SetSize(wdb.width or 300, wdb.height or 200)
    frame:SetClampedToScreen(true); frame:SetMovable(true)
    W.frame = frame

    ns.ApplyWinPosition(frame, wdb, winIdx)
    -- Used by unlock mode's applyPosition callback; W.idx (not winIdx) so it survives re-indexing
    W.ApplyPosition = function() ns.ApplyWinPosition(frame, wdb, W.idx) end

    frame._bg = frame:CreateTexture(nil, "BACKGROUND")
    frame._bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -GetHeaderH())
    frame._bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    ns.DMPaintWindowBg(frame._bg, cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgAlpha or 0.75, true, cfg.bgTexture)

    -- Header (inside the classic box's line; flush on every other look)
    local ci = ns.DMClassicInset()
    local header = CreateFrame("Frame", nil, frame)
    header:SetHeight(GetHeaderH()); header:SetPoint("TOPLEFT", frame, "TOPLEFT", ci, -ci); header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -ci, -ci)
    header:SetFrameLevel(frame:GetFrameLevel() + 5)
    W.header = header

    -- Independent overlay target so the frame border can start at the window top or below the header without affecting window layout
    local windowBorderTarget = CreateFrame("Frame", nil, frame)
    windowBorderTarget:EnableMouse(false)
    W.windowBorderTarget = windowBorderTarget
    ns.DMSetWindowBorderLayer(W, cfg)

    do local hc = cfg.hdrBgColor; local hR = hc and hc.r or 0x1B/255; local hG = hc and hc.g or 0x1B/255; local hB = hc and hc.b or 0x1B/255
    header._hdrBg = header:CreateTexture(nil, "BACKGROUND"); header._hdrBg:SetAllPoints(); ns.DMPaintHeaderBg(header._hdrBg, hR, hG, hB, cfg.hdrBgAlpha or 1) end
    header._bottomBorder = header:CreateTexture(nil, "OVERLAY", nil, 7)
    header._bottomBorder:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    header._bottomBorder:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    if not ns.DMClassicSeparator(header._bottomBorder, PhysicalPixels(1)) then
        local size = cfg.hdrBottomBorderSize or 0
        local color = cfg.hdrBottomBorderColor or {}
        header._bottomBorder:SetHeight(PhysicalPixels(size))
        header._bottomBorder:SetColorTexture(color.r or 0, color.g or 0, color.b or 0, color.a or 1)
        header._bottomBorder:SetShown(size > 0 and not ns.DMBlizz())
    end

    local hdrFS = cfg.hdrFontSize or 11
    local txOX, txOY = cfg.hdrTextOffX or 0, cfg.hdrTextOffY or 0
    W.titleText = header:CreateFontString(nil, "OVERLAY"); SetDMFont(W.titleText, hdrFS)
    W.titleText:SetPoint("LEFT", header, "LEFT", 6 + txOX, txOY + ns.DMHdrLift(cfg.hdrHeight))
    do
        local tR, tG, tB
        if cfg.hdrTextUseAccent ~= false then tR, tG, tB = ns.DMTitleRGB()
        else local tc = cfg.hdrTextColor; tR = tc and tc.r or 1; tG = tc and tc.g or 1; tB = tc and tc.b or 1 end
        W.titleText:SetTextColor(tR, tG, tB, 1)
    end
    W._fullTitle = L("Damage Done")
    W.titleText:SetText(L("Damage Done"))

    W.timerText = header:CreateFontString(nil, "OVERLAY"); SetDMFont(W.timerText, hdrFS)
    W.timerText:SetTextColor(1, 1, 1, 0.7); W.timerText:SetPoint("LEFT", W.titleText, "RIGHT", 4, 0); W.timerText:SetText("(0:00)")
    if wdb.hideTimer then W.timerText:Hide() end

    if EUI.RegAccent then
        -- Propagates a live accent color change to header text, header icons, bars (via
        -- Refresh), and home screen cards (via RefreshHome), each gated on its own accent-use toggle
        EUI.RegAccent({ type = "callback", fn = function(r, g, b)
            -- A parked window re-reads the accent when it is brought back (W.Reapply).
            if W._parked then return end
            local c = DB()
            -- (WoW Forever's title keeps its gold.)
            if c.hdrTextUseAccent ~= false and not ns.DMForever() then W.titleText:SetTextColor(r, g, b, 1) end
            if c.iconColorUseAccent then
                for _, ic in ipairs(W.hdrIcons) do
                    if not ic._hdrArt then ic:SetVertexColor(r, g, b, ICON_ALPHA) end
                end
            end
            W.Refresh()
            if homeFrame and homeFrame:IsShown() then RefreshHome() end
        end })
    end

    -- Header buttons (size and gap follow the style: ns.DMHdrIconSize)
    local btnSize = ns.DMHdrIconSize(cfg)
    local btnPad = ns.DMHdrIconPad()

    W.hdrIcons = {}
    local function GetIconColor()
        local c = DB()
        if c.iconColorUseAccent then return GetAccentRGB() end
        local ic = c.iconColor; return ic and ic.r or 1, ic and ic.g or 1, ic and ic.b or 1
    end

    -- artKey: the header key whose stock-style art replaces the EUI glyph
    -- under a stock style (ns.DM_HDR_ART); the glyph stays where none exists.
    local function MakeHeaderBtn(texFile, xOff, tooltip, onClick, artKey)
        local btn = CreateFrame("Button", nil, header)
        btn:SetSize(btnSize, btnSize); btn:SetPoint("RIGHT", header, "RIGHT", xOff, ns.DMHdrLift())
        btn:SetFrameLevel(header:GetFrameLevel() + 2)
        local ir, ig, ib = GetIconColor()
        local icon = btn:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints()
        btn._hdrIcon = icon
        if not ns.DMPaintHdrArt(icon, artKey) then
            icon:SetTexture(MEDIA .. texFile); icon:SetDesaturated(true); icon:SetVertexColor(ir, ig, ib, ICON_ALPHA)
        end
        W.hdrIcons[#W.hdrIcons + 1] = icon
        btn:SetScript("OnEnter", function(self)
            if not ns.DMHdrHover(icon, true) then
                local r, g, b = GetIconColor(); icon:SetVertexColor(r, g, b, ICON_HOVER_ALPHA)
            end
            -- Suppress tooltip while this button's menu is open
            if _edmMenu and _edmMenu:IsShown() and _edmMenuAnchor == self then return end
            EUI.ShowWidgetTooltip(self, tooltip)
        end)
        btn:SetScript("OnLeave", function()
            if not ns.DMHdrHover(icon, false) then
                local r, g, b = GetIconColor(); icon:SetVertexColor(r, g, b, ICON_ALPHA)
            end
            EUI.HideWidgetTooltip()
        end)
        btn:SetScript("OnClick", function(self)
            EUI.HideWidgetTooltip()
            onClick(self)
        end)
        return btn
    end

    W.settingsBtn = MakeHeaderBtn("dm_settings.png", -(btnPad + 2), "Settings", function()
        -- "Default on M+ Start" submenu: meter type this window switches to when a key starts; "Off" (default) leaves it alone
        local function mStartEntry(label, dmType)
            return { text = label, isActive = (wdb.mythicStartDMType == dmType),
                     onClick = function() wdb.mythicStartDMType = dmType end }
        end
        local mStartChildren = {
            { text = L("Off"), isActive = (not wdb.mythicStartDMType),
              onClick = function() wdb.mythicStartDMType = false end },
            "---",
            mStartEntry(L("Damage Done"), Enum.DamageMeterType.DamageDone),
            mStartEntry(L("Healing"), Enum.DamageMeterType.HealingDone),
            mStartEntry(L("Damage Taken"), Enum.DamageMeterType.DamageTaken),
            mStartEntry(L("Avoidable Damage Taken"), Enum.DamageMeterType.AvoidableDamageTaken),
            mStartEntry(L("Enemy Damage Taken"), Enum.DamageMeterType.EnemyDamageTaken),
            mStartEntry(L("Interrupts"), Enum.DamageMeterType.Interrupts),
            mStartEntry(L("Dispels"), Enum.DamageMeterType.Dispels),
            mStartEntry(L("Deaths"), Enum.DamageMeterType.Deaths),
        }
        -- An instance rule changed: re-apply every window now, and move the mouseover
        -- scan's cached predicate on next frame (deferred like the hotkey toggle), so a
        -- hover cannot reveal a window the new rule hides.
        local function rulesChanged()
            for _, w in ipairs(_windows) do w.UpdateVisibility() end
            C_Timer.After(0, EUI.RequestVisibilityUpdate)
        end
        local items = {
            { text = L("Hide in Dungeons"), isActive = wdb.hideInDungeon, onClick = function()
                wdb.hideInDungeon = not wdb.hideInDungeon
                rulesChanged()
            end },
            { text = L("Hide in Raids"), isActive = wdb.hideInRaid, onClick = function()
                wdb.hideInRaid = not wdb.hideInRaid
                rulesChanged()
            end },
            { text = L("Hide in Delves"), noForever = true, isActive = wdb.hideInDelve, onClick = function()
                wdb.hideInDelve = not wdb.hideInDelve
                rulesChanged()
            end },
            { text = L("Hide in PvP"), isActive = wdb.hideInPvP, onClick = function()
                wdb.hideInPvP = not wdb.hideInPvP
                rulesChanged()
            end },
            { text = L("Hide out of Instances"), isActive = wdb.hideOutOfInstance, onClick = function()
                wdb.hideOutOfInstance = not wdb.hideOutOfInstance
                rulesChanged()
            end },
            "---",
            { text = L("Width"), isInput = true,
              getValue = function() return math.floor(frame:GetWidth() + 0.5) end,
              setValue = function(v)
                  local left, top = frame:GetLeft(), frame:GetTop()
                  frame:SetSize(math.max(MIN_W, v), frame:GetHeight())
                  if left and top then frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) end
                  wdb.width = math.floor(frame:GetWidth() + 0.5)
              end,
              min = MIN_W },
            { text = L("Height"), isInput = true,
              getValue = function() return math.floor(frame:GetHeight() + 0.5) end,
              setValue = function(v)
                  local left, top = frame:GetLeft(), frame:GetTop()
                  frame:SetSize(frame:GetWidth(), math.max(MIN_H, v))
                  if left and top then frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) end
                  wdb.height = math.floor(frame:GetHeight() + 0.5)
              end,
              min = MIN_H },
            { text = W.snapDisabled and L("Enable Snapping") or L("Disable Snapping"), onClick = function()
                W.snapDisabled = not W.snapDisabled
                wdb.snapDisabled = W.snapDisabled
            end },
            { text = L("Hide Timer"), noThreat = true, isActive = wdb.hideTimer, onClick = function()
                wdb.hideTimer = not wdb.hideTimer
                W.timerText:SetShown(not wdb.hideTimer)
            end },
            { text = L("Auto Swap Current/Overall"), noForever = true,
              tooltip = L("Auto switch your window to overall at the end of an M+ run, and current at the start"),
              isActive = wdb.autoSwapMythic, onClick = function()
                wdb.autoSwapMythic = not wdb.autoSwapMythic
            end },
            { text = L("Auto Current on Combat"), noThreat = true,
              tooltip = L("Entering combat switches this window back to Current if viewing a past segment"),
              isActive = wdb.autoCurrentOnCombat, onClick = function()
                wdb.autoCurrentOnCombat = not wdb.autoCurrentOnCombat
            end },
            { text = L("Sync Segment Selection"), noThreat = true,
              tooltip = L("Selecting a segment switches all synced windows to it"),
              isActive = wdb.syncSegments, onClick = function()
                wdb.syncSegments = not wdb.syncSegments
            end },
            { text = L("Default on M+ Start"), noForever = true,
              tooltip = L("Set your window to this Meter Type on dungeon start"),
              children = mStartChildren },
            { text = L("Settings"), onClick = function()
                EUI:ShowModule("EllesmereUIDamageMeters")
            end },
        }
        -- WoW Forever has no delves and no keystones: the entries only those drive are
        -- left out of the menu there (their saved values stay, and stay inert).
        if EUI.IS_FOREVER then
            for i = #items, 1, -1 do
                local e = items[i]
                if type(e) == "table" and e.noForever then table.remove(items, i) end
            end
        end
        -- A Threat window's list settings head the menu (WoW Forever).
        if W.curDMType == "threat" and ns.DMThreatMenu then ns.DMThreatMenu(items) end
        ShowEDMMenu(items, W.settingsBtn)
    end, "settings")

    W.segmentBtn = MakeHeaderBtn("dm_sheet.png", -(btnSize + btnPad * 2 + 2), L("Select Segment"), function()
        -- A Threat list (WoW Forever) has no segments.
        if W.curDMType == "threat" then return end
        local items = {}
        -- Segments first (top of upward menu)
        if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
            local sessions = C_DamageMeter.GetAvailableCombatSessions()
            if sessions and #sessions > 0 then
                local startIdx = math.max(1, #sessions - 19)
                for i = startIdx, #sessions do
                    local s = sessions[i]
                    local segName = s.name
                    if not segName or (issecretvalue and issecretvalue(segName)) or segName == "" then segName = "Combat" end
                    local segTime = FormatTimer(s.durationSeconds or 0)
                    items[#items + 1] = {
                        text = segName, timerText = segTime, compact = true,
                        isActive = (W.curSessionID == s.sessionID),
                        onClick = function() ns.ApplySegmentSelection(W, nil, s.sessionID) end,
                    }
                end
            end
        end
        -- Divider + Current/Overall at bottom
        items[#items + 1] = "---"
        for _, sType in ipairs(SESSION_TYPES) do
            items[#items + 1] = {
                text = L(SESSION_TYPE_NAMES[sType] or "Unknown"),
                isActive = (not W.curSessionID and sType == W.curSession),
                onClick = function() ns.ApplySegmentSelection(W, sType, nil) end,
            }
        end
        ShowEDMMenu(items, W.segmentBtn)
    end, "segment")

    -- Switch this window to a meter type (data + icon + refresh). Shared by the
    -- mode button and the "Default on M+ Start" key-start hook so both stay in sync.
    function W.SetDMType(dmType)
        W.curDMType = dmType; wdb.curDMType = dmType
        if W.CloseSource then W.CloseSource() end
        -- A full row pass: a Threat list's ranks skip its pull line, so a row that
        -- keeps its slot across the switch would keep that rank.
        W._barCacheKey = nil
        W.Refresh()
        if W._modeIcon then ns.DMSetTypeIcon(W._modeIcon, dmType) end
        -- Leaving Threat may leave its list with no window (WoW Forever)
        if ns.DMThreatSync then ns.DMThreatSync() end
    end

    W.modeBtn = MakeHeaderBtn("dm_arrow.png", -(btnSize * 2 + btnPad * 3 + 2), "Switch Meter Type", function()
        local function sel(dmType) return function() W.SetDMType(dmType) end end
        local function entry(label, dmType) return { text = label, onClick = sel(dmType), isActive = (dmType == W.curDMType) } end
        local cur = W.curDMType
        local dmActive = (cur == Enum.DamageMeterType.DamageDone or cur == Enum.DamageMeterType.DamageTaken or cur == Enum.DamageMeterType.AvoidableDamageTaken or cur == Enum.DamageMeterType.EnemyDamageTaken)
        local actActive = (cur == Enum.DamageMeterType.Interrupts or cur == Enum.DamageMeterType.Dispels or cur == Enum.DamageMeterType.Deaths)
        local items = {
            { text = L("Damage"), isActive = dmActive, children = {
                entry(L("Damage Done"), Enum.DamageMeterType.DamageDone), entry(L("Damage Taken"), Enum.DamageMeterType.DamageTaken),
                entry(L("Avoidable Damage Taken"), Enum.DamageMeterType.AvoidableDamageTaken), entry(L("Enemy Damage Taken"), Enum.DamageMeterType.EnemyDamageTaken),
            }},
            entry(L("Healing"), Enum.DamageMeterType.HealingDone),
            { text = L("Actions"), isActive = actActive, children = {
                entry(L("Interrupts"), Enum.DamageMeterType.Interrupts), entry(L("Dispels"), Enum.DamageMeterType.Dispels), entry(L("Deaths"), Enum.DamageMeterType.Deaths),
            }},
        }
        -- WoW Forever with Forever Essentials: its threat list
        if DM_TYPE_NAMES.threat then items[#items + 1] = entry(L("Threat"), "threat") end
        ShowEDMMenu(items, W.modeBtn)
    end)
    -- Set mode icon to current DM type icon
    W._modeIcon = W.hdrIcons[#W.hdrIcons]
    ns.DMSetTypeIcon(W._modeIcon, W.curDMType)

    -- + (new window) or x (close window) button, left of mode icon
    local winActionIcon = (winIdx == 1) and (MEDIA .. "dm_open.png") or (MEDIA .. "dm_close.png")
    local winActionTip = (winIdx == 1) and L("New Window") or L("Close Window")
    local winActionKey = (winIdx == 1) and "open" or "close"
    W.winActionBtn = MakeHeaderBtn("dm_settings.png", -(btnSize * 4 + btnPad * 5 + 2), winActionTip, function()
        if winIdx ~= 1 and W.windowLocked then return end
        if winIdx == 1 then
            if #_windows >= MAX_WINDOWS then return end
            local newIdx2 = #_windows + 1
            local srcW2 = frame:GetWidth(); local srcH2 = frame:GetHeight()
            local srcLeft2 = frame:GetLeft()
            local GAP = 10

            -- Find the highest top and lowest bottom among all existing windows
            local highestTop = frame:GetTop() or 0
            local lowestBot = frame:GetBottom() or 0
            for _, w in ipairs(_windows) do
                if w.frame then
                    local t = w.frame:GetTop()
                    local b = w.frame:GetBottom()
                    if t and t > highestTop then highestTop = t end
                    if b and b < lowestBot then lowestBot = b end
                end
            end

            -- Try above first (new bottom = highest top + gap); if that clears the screen top, place below the lowest window instead
            local screenTop2 = UIParent:GetTop() or 0
            local newTop2 = highestTop + srcH2 + GAP
            if newTop2 > screenTop2 then
                newTop2 = lowestBot - GAP
            end

            local nwdb = WinDB(newIdx2)
            nwdb.width = math.floor(srcW2 + 0.5); nwdb.height = math.floor(srcH2 + 0.5)
            nwdb.position = { x = srcLeft2, y = newTop2 }
            -- A closed window comes back before a new one is built
            local nw = ns.DMAcquireWindow(newIdx2)
            _windows[newIdx2] = nw
            if ns.ApplyWindowBorder then ns.ApplyWindowBorder() end
            -- Persist count
            local c = DB(); c.windowCount = newIdx2
            ns.RegisterDMUnlock()
            nw.ShowHome()
        else
            W.Destroy()
        end
    end, winActionKey)
    -- Override icon texture (the stock art, when any, was painted by key);
    -- close icon 2px larger for visibility
    do
        local iconTex = W.hdrIcons[#W.hdrIcons]
        if not iconTex._hdrArt then iconTex:SetTexture(winActionIcon) end
        if winIdx ~= 1 then W._closeIconTex = iconTex end
        -- (The thin glyph only; the vanilla red X fills its crop already.)
        if winIdx ~= 1 and not iconTex._hdrArt then
            iconTex:ClearAllPoints()
            iconTex:SetSize(btnSize + 2, btnSize + 2)
            iconTex:SetPoint("CENTER", W.winActionBtn, "CENTER", 0, 0)
        end
        -- Disable + button at max windows / close button when locked
        if winIdx == 1 then
            W.winActionBtn:HookScript("OnEnter", function(self)
                if #_windows >= MAX_WINDOWS then
                    iconTex:SetAlpha(0.2)
                    EUI.HideWidgetTooltip()
                    EUI.ShowWidgetTooltip(self, EllesmereUI.Lf("You may only have %1$d windows active", MAX_WINDOWS))
                end
            end)
        else
            W.winActionBtn:HookScript("OnEnter", function(self)
                if W.windowLocked then
                    local ir, ig, ib = GetIconColor()
                    if not ns.DMHdrHover(iconTex, false, true) then iconTex:SetVertexColor(ir, ig, ib, ICON_ALPHA * 0.5) end
                    EUI.HideWidgetTooltip()
                    EUI.ShowWidgetTooltip(self, "Unlock Window to Close")
                end
            end)
            W.winActionBtn:HookScript("OnLeave", function()
                if W.windowLocked then
                    local ir, ig, ib = GetIconColor()
                    if not ns.DMHdrHover(iconTex, false, true) then iconTex:SetVertexColor(ir, ig, ib, ICON_ALPHA * 0.5) end
                end
            end)
        end
    end
    -- Apply initial close icon dimming if window starts locked
    if winIdx ~= 1 and W.windowLocked and W._closeIconTex then
        local ir, ig, ib = GetIconColor()
        if not ns.DMHdrHover(W._closeIconTex, false, true) then W._closeIconTex:SetVertexColor(ir, ig, ib, ICON_ALPHA * 0.5) end
    end

    -- Reset Data button, left of win action button
    W.resetBtn = MakeHeaderBtn("dm_undo.png", -(btnSize * 3 + btnPad * 4 + 2), "Reset Data", function()
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
            C_DamageMeter.ResetAllCombatSessions()
            SetCombatEndTime(0); SetCurViewFrozenDur(0)
            for _, w in ipairs(_windows) do w.Refresh() end
        end
    end, "reset")

    -- Ordered list of header buttons for live resize/reposition
    W.hdrBtns = { W.settingsBtn, W.segmentBtn, W.modeBtn, W.resetBtn, W.winActionBtn }
    LayoutHeaderButtons(W, cfg, btnSize)

    -- Truncate the header title so it never runs under the right-side icons; mirrors the icon layout math (N buttons of hdrIconSize spaced by btnPad from the right) rather than relying on GetLeft (can lag a SetPoint)
    function W.FitTitle()
        local fs = W.titleText
        local full = W._fullTitle
        if not fs or not full then return end
        local c = DB()
        local iconSz = ns.DMHdrIconSize(c)
        local n = ns.DMHeaderButtonCount(W, c)
        -- Icons hidden until hover occupy no space, so the title gets the whole header instead of truncating against a gap that isn't there
        if W._hdrIconsShown == false then n = 0 end
        local headerW = frame:GetWidth() or (wdb.width or 300)
        local btnLeft = headerW - (iconSz * n) - (btnPad * n) - 2
        local avail = btnLeft - (6 + (c.hdrTextOffX or 0)) - 6
        if avail < 1 then avail = 1 end
        -- The same title in the same room keeps the fit on screen (the header style
        -- pass drops this memo: a font change moves the widths).
        if W._fitFull == full and W._fitAvail == avail then return end
        W._fitFull, W._fitAvail = full, avail
        fs:SetText(full)
        if fs:GetStringWidth() <= avail then return end
        local s = full
        while #s > 1 do
            -- Drop one character, not one byte: localised titles are UTF-8 and a mid-codepoint cut renders as garbage
            local i = #s
            while i > 1 do
                local b = string.byte(s, i)
                if b < 0x80 or b >= 0xC0 then break end
                i = i - 1
            end
            s = string.sub(s, 1, i - 1)
            fs:SetText(s .. "...")
            if fs:GetStringWidth() <= avail then break end
        end
    end

    -- Option: hide header icons until the title bar is hovered
    ApplyHeaderButtonsHoverVisibility(W, cfg)

    -- Snap helpers (X-axis alignment + width matching against other DM windows)
    local SNAP_THRESH = 6

    -- Find the closest other DM window by 2D edge-to-edge distance; optional left/top overrides let drag pass an unsnapped target position
    local function FindClosestWindow(overrideL, overrideT)
        local myL = overrideL or frame:GetLeft() or 0
        local myW2 = frame:GetWidth() or 0
        local myH2 = frame:GetHeight() or 0
        local myT = overrideT or frame:GetTop() or 0
        local myR = myL + myW2
        local myB = myT - myH2
        local closest, closestDist = nil, math.huge
        for _, otherW in ipairs(_windows) do
            if otherW ~= W and otherW.frame and otherW.frame:IsShown() then
                local oL = otherW.frame:GetLeft() or 0
                local oR = otherW.frame:GetRight() or 0
                local oT = otherW.frame:GetTop() or 0
                local oB = otherW.frame:GetBottom() or 0
                local gapX = 0
                if myR < oL then gapX = oL - myR
                elseif myL > oR then gapX = myL - oR end
                local gapY = 0
                if myB > oT then gapY = myB - oT
                elseif myT < oB then gapY = oB - myT end
                local dist = math.sqrt(gapX * gapX + gapY * gapY)
                if dist < closestDist then closestDist = dist; closest = otherW end
            end
        end
        return closest
    end

    local function SnapResizeWidth(newW)
        local near = FindClosestWindow()
        if not near then return newW end
        local oW = near.frame:GetWidth()
        if oW and math.abs(newW - oW) <= SNAP_THRESH then return oW end
        return newW
    end

    local function SnapResizeHeight(newH)
        local near = FindClosestWindow()
        if not near then return newH end
        local oH = near.frame:GetHeight()
        if oH and math.abs(newH - oH) <= SNAP_THRESH then return oH end
        return newH
    end

    -- Header drag (manual, with real-time X-axis snapping)
    header:EnableMouse(true)
    local dragging = false
    local dragStartCX, dragStartCY, dragStartLeft, dragStartTop
    local dragFrame = CreateFrame("Frame"); dragFrame:Hide()
    dragFrame:SetScript("OnUpdate", function()
        if not dragging then return end
        -- Stop drag if mouse button was released (catches cases where OnMouseUp doesn't fire)
        if not IsMouseButtonDown("LeftButton") then
            dragging = false; dragFrame:Hide()
            local left, top = frame:GetLeft(), frame:GetTop()
            if left and top then
                if PP and PP.Snap then left = PP.Snap(left); top = PP.Snap(top) end
                wdb.position = { x = left, y = top }
                frame:ClearAllPoints()
                frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
                -- Manual placement overrides any unlock-mode anchor on this window
                if EllesmereUIDB and EllesmereUIDB.unlockAnchors then
                    EllesmereUIDB.unlockAnchors["EDM_Win" .. W.idx] = nil
                end
                if EUI.ScheduleSettleReapply then EUI.ScheduleSettleReapply() end
            end
        end
        local cx, cy = GetCursorPosition(); local es = frame:GetEffectiveScale()
        local newLeft = dragStartLeft + (cx/es - dragStartCX)
        local newTop = dragStartTop + (cy/es - dragStartCY)
        -- Snap to closest window only (use unsnapped target to prevent oscillation)
        local near = not W.snapDisabled and FindClosestWindow(newLeft, newTop)
        if near then
            local myW = frame:GetWidth()
            local myH = frame:GetHeight()
            local oLeft = near.frame:GetLeft()
            local oRight = near.frame:GetRight()
            local oTop = near.frame:GetTop()
            local oBot = near.frame:GetBottom()
            -- X axis
            if oLeft and oRight then
                local bestDist = SNAP_THRESH + 1
                local snappedLeft = newLeft
                local d1 = math.abs(newLeft - oLeft)
                if d1 < bestDist then bestDist = d1; snappedLeft = oLeft end
                local d2 = math.abs((newLeft + myW) - oRight)
                if d2 < bestDist then bestDist = d2; snappedLeft = oRight - myW end
                local d3 = math.abs(newLeft - oRight)
                if d3 < bestDist then bestDist = d3; snappedLeft = oRight end
                local d4 = math.abs((newLeft + myW) - oLeft)
                if d4 < bestDist then bestDist = d4; snappedLeft = oLeft - myW end
                if bestDist <= SNAP_THRESH then newLeft = snappedLeft end
            end
            -- Y axis
            if oTop and oBot then
                local bestDistY = SNAP_THRESH + 1
                local snappedTop = newTop
                local d1 = math.abs(newTop - oTop)
                if d1 < bestDistY then bestDistY = d1; snappedTop = oTop end
                local d2 = math.abs((newTop - myH) - oBot)
                if d2 < bestDistY then bestDistY = d2; snappedTop = oBot + myH end
                local d3 = math.abs(newTop - oBot)
                if d3 < bestDistY then bestDistY = d3; snappedTop = oBot end
                local d4 = math.abs((newTop - myH) - oTop)
                if d4 < bestDistY then bestDistY = d4; snappedTop = oTop + myH end
                if bestDistY <= SNAP_THRESH then newTop = snappedTop end
            end
        end
        -- Snap position to physical pixel grid
        if PP and PP.Snap then newLeft = PP.Snap(newLeft); newTop = PP.Snap(newTop) end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, newTop)
    end)

    header:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or W.windowLocked then return end
        local bars = EUI._ModuleNS.EllesmereUIDataBars
        if bars and bars.MeterDockState and bars.MeterDockState(W.idx) then return end
        if EUI.InProtectedInstance() then return end
        local cx, cy = GetCursorPosition(); local es = frame:GetEffectiveScale()
        dragStartCX = cx/es; dragStartCY = cy/es
        dragStartLeft = frame:GetLeft(); dragStartTop = frame:GetTop()
        if not dragStartLeft or not dragStartTop then return end
        dragging = true; dragFrame:Show()
    end)
    header:SetScript("OnMouseUp", function(_, button)
        -- Right-click on the header toggles the meter-type home screen, matching the window body's right-click behavior
        if button == "RightButton" then
            if not dragging and W.ToggleHome then W.ToggleHome() end
            return
        end
        if button ~= "LeftButton" or not dragging then return end
        dragging = false; dragFrame:Hide()
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then
            if PP and PP.Snap then left = PP.Snap(left); top = PP.Snap(top) end
            wdb.position = { x = left, y = top }
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            -- Manual placement overrides any unlock-mode anchor on this window
            if EllesmereUIDB and EllesmereUIDB.unlockAnchors then
                EllesmereUIDB.unlockAnchors["EDM_Win" .. W.idx] = nil
            end
            -- Reposition elements anchored to this window
            if EUI.ScheduleSettleReapply then EUI.ScheduleSettleReapply() end
        end
    end)

    -- Right-click catcher: opens the home screen on right-click over empty content area below
    -- the header; sits behind the viewport so bar clicks pass through normally.
    local rightClickCatcher = CreateFrame("Button", nil, frame)
    rightClickCatcher:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    rightClickCatcher:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ci, ci)
    rightClickCatcher:SetFrameLevel(frame:GetFrameLevel() + 1)
    rightClickCatcher:RegisterForClicks("RightButtonUp")
    rightClickCatcher:EnableMouseWheel(false)
    if rightClickCatcher.SetMouseClickEnabled then rightClickCatcher:SetMouseClickEnabled(true) end
    rightClickCatcher:SetScript("OnClick", function() W.ShowHome() end)

    -- Viewport + scroll
    local viewport = CreateFrame("ScrollFrame", nil, frame)
    viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ci, ci)
    W.viewport = viewport

    local content = CreateFrame("Frame", nil, viewport); content:SetSize(1, 1)
    viewport:SetScrollChild(content)
    W.content = content

    viewport:SetScript("OnSizeChanged", function(self, w, h)
        -- Tracked through guarded pin/unpin resizes too, so "grew" compares against the real last height.
        local grew = h and h > (W._vpH or 0)
        W._vpH = h
        if W.stickyGuard then return end
        if w and w > 0 then content:SetWidth(w) end
        W.UpdateSticky(nil, W.visibleCount)
        if W._decorSync then ns.DMSyncRowDecor(W) end
        -- A taller viewport reveals rows the last pass skipped; the grip drag queues once on release.
        -- In combat the running ticker fills them (a pin/unpin resize would otherwise double its pass).
        -- (A Threat window, WoW Forever, has no ticker: it fills them in combat too.)
        if grew and not W.resizing and (not InCombatLockdown() or W.curDMType == "threat") then W.QueueRepopulate() end
    end)

    -- Mouse wheel scrolling (no visual scrollbar)
    local _scrollMax = 0
    local _scrollRefreshPending = false
    -- Rows scrolled or resized into view are filled only by a RefreshUI pass (the ticker
    -- is stopped out of combat): one coalesced pass next frame, through one reused callback.
    local function RunRepopulate()
        _scrollRefreshPending = false
        if W._lastSession then RefreshUI(W._lastSession) end
    end
    function W.QueueRepopulate()
        if _scrollRefreshPending or not W._lastSession then return end
        _scrollRefreshPending = true
        C_Timer.After(0, RunRepopulate)
    end
    viewport:EnableMouseWheel(true)
    viewport:SetScript("OnMouseWheel", function(_, delta)
        local c = DB(); local _, _, stride = ns._RowMetrics(c.barHeight or 18, c.barSpacing or 2, frame:GetEffectiveScale())
        local cur = viewport:GetVerticalScroll() or 0
        -- Return to the row grid after the bottom clamp splits a row.
        local target = (math.floor(cur / stride + 0.5) - delta * 2) * stride
        local newVal = math.max(0, math.min(_scrollMax, target))
        viewport:SetVerticalScroll(newVal)
        W.UpdateSticky(nil, W.visibleCount)
        if W._decorSync then ns.DMSyncRowDecor(W) end
        W.QueueRepopulate()
    end)

    -- Bar pool
    W.rowPool = {}
    for i = 1, BAR_POOL_SIZE do W.rowPool[i] = MakeRow(content) end

    -- Sticky player bar
    W.stickyPlayer = MakeRow(frame)
    W.stickyPlayer.row:SetFrameLevel(frame:GetFrameLevel() + 8)
    W.stickyPlayer.row:Hide()

    local onePx = (PP and PP.mult) or 1
    W.stickySep = CreateFrame("Frame", nil, frame)
    W.stickySep:SetHeight(onePx); W.stickySep:SetFrameLevel(frame:GetFrameLevel() + 10)
    local sepTex = W.stickySep:CreateTexture(nil, "OVERLAY", nil, 6); sepTex:SetAllPoints(); sepTex:SetColorTexture(0, 0, 0, 1)
    W.stickySep:Hide()

    -- Source window
    W.sourceFrame = CreateFrame("Frame", nil, frame)
    W.sourceFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    W.sourceFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ci, ci)
    W.sourceFrame:SetFrameLevel(frame:GetFrameLevel() + 20); W.sourceFrame:EnableMouse(true); W.sourceFrame:Hide()
    W.sourceFrame._bg = W.sourceFrame:CreateTexture(nil, "BACKGROUND"); W.sourceFrame._bg:SetAllPoints()
    ns.DMPaintWindowBg(W.sourceFrame._bg, cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgAlpha or 0.75, nil, cfg.bgTexture)

    W.srcViewport = CreateFrame("ScrollFrame", nil, W.sourceFrame); W.srcViewport:SetAllPoints()
    W.srcContent = CreateFrame("Frame", nil, W.srcViewport); W.srcContent:SetSize(1, 1); W.srcViewport:SetScrollChild(W.srcContent)
    W.srcViewport:SetScript("OnSizeChanged", function(_, w) W.srcContent:SetWidth(w) end)

    -- Mouse wheel scrolling for spell breakdown
    local _srcScrollMax = 0
    W.srcViewport:EnableMouseWheel(true)
    W.srcViewport:SetScript("OnMouseWheel", function(_, delta)
        local c = DB(); local _, _, step = ns._RowMetrics(c.barHeight or 18, c.barSpacing or 2, frame:GetEffectiveScale()); step = step * 2
        local cur = W.srcViewport:GetVerticalScroll() or 0
        W.srcViewport:SetVerticalScroll(math.max(0, math.min(_srcScrollMax, cur - delta * step)))
    end)

    W.sourceFrame:SetScript("OnMouseDown", function() W.CloseSource() end)

    W.spellPool = nil  -- lazy-created on first OpenSource
    local function EnsureSpellPool()
        if W.spellPool then return end
        W.spellPool = {}
        for i = 1, BAR_POOL_SIZE do W.spellPool[i] = MakeSpellRow(W.srcContent) end
    end

    -- Resize grip
    W.resizeGrip = CreateFrame("Button", nil, frame)
    W.resizeGrip:SetSize(18, 18); W.resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    W.resizeGrip:SetFrameLevel(frame:GetFrameLevel() + 15)
    local gripTex = W.resizeGrip:CreateTexture(nil, "ARTWORK"); gripTex:SetAllPoints()
    gripTex:SetTexture(RESIZE_ICON); gripTex:SetDesaturated(true); gripTex:SetVertexColor(1, 1, 1)
    W.resizeGrip:EnableMouse(true); W.resizeGrip:SetAlpha(0)
    W.resizeGrip:SetScript("OnEnter", function(self) if not W.windowLocked then self:SetAlpha(0.7) end end)
    W.resizeGrip:SetScript("OnLeave", function(self) self:SetAlpha((W.isHovered and not W.windowLocked) and 0.3 or 0) end)

    -- Lock icon (shows/hides with resize grip, click toggles lock state)
    W.lockBtn = CreateFrame("Button", nil, frame)
    W.lockBtn:SetSize(13, 17)
    W.lockBtn:SetFrameLevel(frame:GetFrameLevel() + 16)
    W.lockBtn:EnableMouse(true); W.lockBtn:SetAlpha(0)
    local lockTex = W.lockBtn:CreateTexture(nil, "ARTWORK"); lockTex:SetAllPoints()
    lockTex:SetDesaturated(true); lockTex:SetVertexColor(1, 1, 1)
    -- The vanilla lock art is a square button: give it a square to sit in.
    if ns.DMHdrArt("locked") then W.lockBtn:SetSize(18, 18) end

    local function UpdateLockIcon()
        if W.windowLocked then
            if not ns.DMPaintHdrArt(lockTex, "locked") then lockTex:SetTexture(MEDIA .. "dm_locked.png") end
            W.lockBtn:ClearAllPoints()
            W.lockBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
        else
            if not ns.DMPaintHdrArt(lockTex, "unlocked") then lockTex:SetTexture(MEDIA .. "dm_unlocked.png") end
            W.lockBtn:ClearAllPoints()
            W.lockBtn:SetPoint("RIGHT", W.resizeGrip, "LEFT", -2, 0)
        end
        -- Dim close icon when locked (non-window-1 only)
        if winIdx ~= 1 and W._closeIconTex then
            local ir, ig, ib = GetIconColor()
            if not ns.DMHdrHover(W._closeIconTex, false, W.windowLocked) then
                W._closeIconTex:SetVertexColor(ir, ig, ib, W.windowLocked and (ICON_ALPHA * 0.5) or ICON_ALPHA)
            end
        end
    end
    UpdateLockIcon()

    W.lockBtn:SetScript("OnEnter", function(self)
        self:SetAlpha(0.7)
        EUI.ShowWidgetTooltip(self, W.windowLocked and "Locked" or "Unlocked")
    end)
    W.lockBtn:SetScript("OnLeave", function(self)
        self:SetAlpha(W.isHovered and 0.3 or 0)
        EUI.HideWidgetTooltip()
    end)
    W.lockBtn:SetScript("OnClick", function()
        W.windowLocked = not W.windowLocked
        wdb.locked = W.windowLocked
        UpdateLockIcon()
        if W.windowLocked then
            W.resizeGrip:SetAlpha(0)
            W.lockBtn:SetAlpha(W.isHovered and 0.3 or 0)
        else
            local a = W.isHovered and 0.3 or 0
            W.resizeGrip:SetAlpha(a)
            W.lockBtn:SetAlpha(a)
        end
        EUI.HideWidgetTooltip()
        EUI.ShowWidgetTooltip(W.lockBtn, W.windowLocked and "Locked" or "Unlocked")
    end)
    W._updateLockIcon = UpdateLockIcon

    local resizeStartX, resizeStartY, resizeStartW, resizeStartH
    local resizeAnchorLeft, resizeAnchorTop  -- pinned TOPLEFT during resize
    local resizeFrame = CreateFrame("Frame"); resizeFrame:Hide()
    local resizeAxis = nil  -- nil = free, "w" = width only, "h" = height only
    local resizeShiftWas = false
    resizeFrame:SetScript("OnUpdate", function()
        if not W.resizing then return end
        local cx, cy = GetCursorPosition(); local es = frame:GetEffectiveScale()
        local dx = cx/es - resizeStartX
        local dy = resizeStartY - cy/es
        local shiftDown = IsShiftKeyDown()
        local newW, newH
        if shiftDown then
            if not resizeShiftWas then
                resizeAxis = math.abs(dx) >= math.abs(dy) and "w" or "h"
            end
            if resizeAxis == "w" then
                newW = math.max(MIN_W, resizeStartW + dx); newH = math.max(MIN_H, resizeStartH)
            else
                newW = math.max(MIN_W, resizeStartW); newH = math.max(MIN_H, resizeStartH + dy)
            end
        else
            resizeAxis = nil
            newW = math.max(MIN_W, resizeStartW + dx); newH = math.max(MIN_H, resizeStartH + dy)
        end
        -- Snap width/height to other windows
        if not W.snapDisabled then
            newW = SnapResizeWidth(newW)
            newH = SnapResizeHeight(newH)
        end
        -- Cap size so frame can't extend past screen edges from pinned TOPLEFT
        local screenW = UIParent:GetRight() or 0
        local screenB = UIParent:GetBottom() or 0
        local maxW = screenW - resizeAnchorLeft
        local maxH = resizeAnchorTop - screenB
        if maxW > MIN_W then newW = math.min(newW, maxW) end
        if maxH > MIN_H then newH = math.min(newH, maxH) end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", resizeAnchorLeft, resizeAnchorTop)
        frame:SetSize(newW, newH)
        resizeShiftWas = shiftDown
    end)

    W.resizeGrip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or W.windowLocked then return end
        local bars = EUI._ModuleNS.EllesmereUIDataBars
        if bars and bars.MeterDockState and bars.MeterDockState(W.idx) then return end
        if EUI.InProtectedInstance() then return end
        local left, top = frame:GetLeft(), frame:GetTop()
        if left and top then
            frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            -- Convert the STORED position to match the pin immediately, not
            -- just on mouse-up. wdb.position is point-format whenever unlock
            -- mode saved it (an imported profile is all point-format), and
            -- ApplyWinPosition re-applies that as SetPoint(pos.point, ...) --
            -- a different anchor from the TOPLEFT pin above. Any re-apply that
            -- lands mid-drag therefore yanks the frame back to its old anchor,
            -- which is the resize "glitch": random, because it depends on
            -- whether a refresh happens while the mouse is down. A window whose
            -- position is already legacy format never showed it, since that
            -- re-applies to the same corner the pin uses.
            if wdb.position and wdb.position.point then
                wdb.position = { x = left, y = top }
            end
        end
        resizeAnchorLeft = left; resizeAnchorTop = top
        local cx, cy = GetCursorPosition(); local es = frame:GetEffectiveScale()
        resizeStartX = cx/es; resizeStartY = cy/es; resizeStartW = frame:GetWidth(); resizeStartH = frame:GetHeight()
        W.resizing = true; resizeFrame:Show()
    end)
    W.resizeGrip:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not W.resizing then return end
        W.resizing = false; resizeFrame:Hide()
        wdb.width = math.floor(frame:GetWidth() + 0.5); wdb.height = math.floor(frame:GetHeight() + 0.5)
        -- Resize pins the TOPLEFT corner, so a point-based position from unlock mode (e.g.
        -- CENTER-anchored) no longer describes this spot; re-save in TOPLEFT drag format to match
        if wdb.position and wdb.position.point then
            local left, top = frame:GetLeft(), frame:GetTop()
            if left and top then wdb.position = { x = left, y = top } end
        end
        W.UpdateSticky(nil, W.visibleCount)
        if W._decorSync then ns.DMSyncRowDecor(W) end
        W.QueueRepopulate()
        -- Refresh home screen card widths one frame after resize
        if homeFrame and homeFrame:IsShown() then
            C_Timer.After(0, function() if RefreshHome then RefreshHome() end end)
        end
    end)

    -- Hover fade (scrollbar + resize grip)
    do
        local fadeSpeed = 1 / 0.12; local fadeAlpha = 0; local fadeTarget = 0
        local fadeFrame2 = CreateFrame("Frame"); fadeFrame2:Hide()
        fadeFrame2:SetScript("OnUpdate", function(self, dt)
            local step = fadeSpeed * dt
            fadeAlpha = fadeTarget > fadeAlpha and math.min(fadeTarget, fadeAlpha + step) or math.max(fadeTarget, fadeAlpha - step)
            if math.abs(fadeAlpha - fadeTarget) < 0.001 then fadeAlpha = fadeTarget end
            if W.resizeGrip and not W.windowLocked and not W.resizeGrip:IsMouseOver() then W.resizeGrip:SetAlpha(fadeAlpha * 0.3) end
            if W.lockBtn and not W.lockBtn:IsMouseOver() then W.lockBtn:SetAlpha(fadeAlpha * 0.3) end
            if fadeAlpha == fadeTarget then self:Hide() end
        end)
        local function FadeIn() fadeTarget = 1; fadeFrame2:Show() end
        local function FadeOut() fadeTarget = 0; fadeFrame2:Show() end
        local wasOver = false
        local hoverTicker  -- forward ref
        local function HoverPoll()
            local over = frame:IsMouseOver() or (W.resizeGrip and W.resizeGrip:IsMouseOver()) or (W.lockBtn and W.lockBtn:IsMouseOver())
            if over and not wasOver then
                wasOver = true; W.isHovered = true
                FadeIn()
            elseif not over and wasOver then
                wasOver = false; W.isHovered = false
                FadeOut()
                -- Stop polling until next OnEnter
                if hoverTicker then hoverTicker:Cancel(); hoverTicker = nil end
            end
        end
        local function StartHoverPoll()
            if hoverTicker then return end
            hoverTicker = C_Timer.NewTicker(0.1, HoverPoll)
        end
        -- OnEnter on the main frame starts the poll
        frame:HookScript("OnEnter", StartHoverPoll)
        -- Also start from children that sit above the frame
        header:HookScript("OnEnter", StartHoverPoll)
        viewport:HookScript("OnEnter", StartHoverPoll)
        rightClickCatcher:HookScript("OnEnter", StartHoverPoll)
        W.resizeGrip:HookScript("OnEnter", StartHoverPoll)
        W.lockBtn:HookScript("OnEnter", StartHoverPoll)
        W._startHoverPoll = StartHoverPoll
        -- Ends any hover at once (W.Park): the poll and the fade stop, and the grip and lock go to alpha 0.
        W._endHover = function()
            if hoverTicker then hoverTicker:Cancel(); hoverTicker = nil end
            wasOver = false; W.isHovered = false
            fadeAlpha, fadeTarget = 0, 0; fadeFrame2:Hide()
            W.resizeGrip:SetAlpha(0); W.lockBtn:SetAlpha(0)
        end
        -- Hook bar rows so entering from the content area starts the poll
        for _, bar in ipairs(W.rowPool) do bar.row:HookScript("OnEnter", StartHoverPoll) end
        if W.stickyPlayer then W.stickyPlayer.row:HookScript("OnEnter", StartHoverPoll) end
    end

    -- Per-window functions
    local function ResetScrollAnchors()
        if not viewport or not header or not frame then return end
        W.stickyGuard = true
        -- ci: the classic box's inset (0 on every other look), as at creation.
        viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
        viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ci, ci)
        -- Clamp scroll
        if content then
            local viewH = frame:GetHeight() - GetHeaderH() - 2 * ci
            if viewH < 1 then viewH = 1 end
            local totalH = content:GetHeight()
            local maxScr = math.max(0, totalH - viewH)
            _scrollMax = maxScr
            local cur = viewport:GetVerticalScroll()
            if cur > maxScr then viewport:SetVerticalScroll(maxScr) end
        end
        W.stickyGuard = false
    end

    local function RecalcViewport(dataCount)
        if not viewport or not content then return end
        local c = DB(); local _, _, stride = ns._RowMetrics(c.barHeight or 18, c.barSpacing or 2, frame:GetEffectiveScale())
        local totalH = dataCount * stride
        content:SetHeight(math.max(10, totalH))
        local viewH = viewport:GetHeight(); if viewH < 1 then viewH = 1 end
        _scrollMax = math.max(0, totalH - viewH)
        local cur = viewport:GetVerticalScroll() or 0
        if cur > _scrollMax then viewport:SetVerticalScroll(_scrollMax) end
    end

    function W.UpdateSticky(sources, visibleCount)

        if W.stickyGuard then return end
        -- Don't show sticky while home screen or source window is open
        if (homeFrame and homeFrame:IsShown()) or W.sourceOpen then
            W.stickyPlayer.row:Hide(); W.stickySep:Hide(); return
        end
        if sources then W.cachedSources = sources end
        sources = W.cachedSources
        if not W.stickyPlayer or not W.stickySep then return end
        local c = DB()
        -- (A Threat list, WoW Forever, pins no row.)
        if c.showPinnedSelf == false or not _playerGUID or not sources or #sources == 0
           or W.curDMType == "threat" then
            W.stickyPlayer.row:Hide(); W.stickySep:Hide(); ResetScrollAnchors(); W.stickyAtTop = false; return
        end
        local playerIdx
        for i, src in ipairs(sources) do if src.isLocalPlayer then playerIdx = i; break end end
        if not playerIdx then W.stickyPlayer.row:Hide(); W.stickySep:Hide(); ResetScrollAnchors(); W.stickyAtTop = false; return end
        local barH, _, stride, pxMult = ns._RowMetrics(c.barHeight or 18, c.barSpacing or 2, frame:GetEffectiveScale())
        local scrollVal = viewport:GetVerticalScroll() or 0
        local fullViewH = frame:GetHeight() - GetHeaderH() - 2 * ci
        if fullViewH < 1 then fullViewH = 1 end
        local barTop = (playerIdx - 1) * stride
        local barBot = barTop + barH
        -- Unpin the instant the player bar is fully within the viewport (1px tolerance for float drift)
        if barTop >= scrollVal - 1 and barBot <= scrollVal + fullViewH + 1 then
            W.stickyPlayer.row:Hide(); W.stickySep:Hide(); ResetScrollAnchors(); W.stickyAtTop = false; return
        end
        local pinTop = (barTop < scrollVal); W.stickyAtTop = pinTop
        local pinnedH = barH + pxMult
        W.stickyPlayer.row:ClearAllPoints(); W.stickySep:ClearAllPoints(); W.stickySep:SetHeight(pxMult)
        if pinTop then
            W.stickyPlayer.row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0); W.stickyPlayer.row:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
            W.stickySep:SetPoint("TOPLEFT", W.stickyPlayer.row, "BOTTOMLEFT", 0, 0); W.stickySep:SetPoint("TOPRIGHT", W.stickyPlayer.row, "BOTTOMRIGHT", 0, 0)
        else
            W.stickyPlayer.row:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", ci, ci); W.stickyPlayer.row:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ci, ci)
            W.stickySep:SetPoint("BOTTOMLEFT", W.stickyPlayer.row, "TOPLEFT", 0, 0); W.stickySep:SetPoint("BOTTOMRIGHT", W.stickyPlayer.row, "TOPRIGHT", 0, 0)
        end
        W.stickyGuard = true
        if pinTop then
            viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -pinnedH); viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ci, ci)
        else
            viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0); viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ci, pinnedH + ci)
        end
        -- Clamp scroll after viewport resize
        local newViewH = viewport:GetHeight()
        if newViewH and newViewH > 0 then
            -- The content holds at most the pool, as RecalcViewport sizes it.
            local totalH = math.min(#sources, BAR_POOL_SIZE) * stride
            local maxScr = math.max(0, totalH - newViewH)
            _scrollMax = maxScr
            local cur = viewport:GetVerticalScroll()
            if cur > maxScr then viewport:SetVerticalScroll(maxScr) end
        end
        W.stickyGuard = false
        -- Fill sticky bar (cached -- only SetValue/SetText per tick)
        local isDeaths = (W.curDMType == Enum.DamageMeterType.Deaths)
        local isCount = (W.curDMType == Enum.DamageMeterType.Interrupts or W.curDMType == Enum.DamageMeterType.Dispels)
        local src = sources[playerIdx]; local maxAmt = isDeaths and 1 or (sources[1] and sources[1].totalAmount or 1)
        local bar = W.stickyPlayer
        local leftFS = c.leftFontSize or c.fontSize or 11; local rightFS = c.rightFontSize or c.fontSize or 11
        local iconStyle = c.iconStyle or "spec"
        local showIcon = iconStyle ~= "none"; local showClassColor = c.showClassColor ~= false
        local texPath, texKey = GetBarTexturePath()
        -- Layout cache: only rebuild on settings change (iconStyle, as the row key: a style switch re-resolves the icon)
        local stickyCacheKey = leftFS .. "|" .. rightFS .. "|" .. texPath .. "|" .. iconStyle .. "|" .. tostring(showClassColor) .. "|" .. barH .. "|" .. tostring(c.classIconZoom) .. "|" .. tostring(c.barFillAlpha)
        if (c.spriteIconZoom or 0) ~= 0 then stickyCacheKey = stickyCacheKey .. "|" .. c.spriteIconZoom end
        if stickyCacheKey ~= W._stickyCacheKey then
            W._stickyCacheKey = stickyCacheKey
            bar.row:SetHeight(barH)
            bar.fill:ClearAllPoints(); bar.fill:SetHeight(barH)
            ApplyBarTexture(bar.fill, texPath, texKey)
            bar.fill:SetAlpha(c.barFillAlpha or 1)
            SetDMFont(bar.pos, leftFS); SetDMFont(bar.label, leftFS); SetDMFont(bar.amount, rightFS)
            bar.label:SetWidth(math.max(20, (frame:GetWidth() or 200) * 0.60))
            W._stickyClassCache = false; W._stickySpecCache = nil  -- false: never a classFilename, forces the icon/colour pass
        end
        bar.row:Show()
        -- Icon + color: only when class changes
        -- Same spec-aware memo as the row loop below: the sticky bar is
        -- re-pointed at whatever source holds the player's rank.
        local classFile = src.classFilename
        local specIcon = src.specIconID
        if classFile ~= W._stickyClassCache or specIcon ~= W._stickySpecCache then
            W._stickyClassCache = classFile
            W._stickySpecCache = specIcon
            local iconOffset = showIcon and ResolveIcon(src, bar.classIcon, barH) or 0
            if not showIcon then bar.classIcon:Hide() end
            if bar._iconBorderFrame then bar._iconBorderFrame:SetShown(c.customIconBorder and (c.iconBorderSize or 0) > 0 and bar.classIcon:IsShown()) end
            bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", iconOffset, 0)
            bar.fill:SetPoint("TOPRIGHT", bar.row, "TOPRIGHT", 0, 0)
            if showClassColor then
                local cc = classFile and RAID_CLASS_COLORS[classFile] and EUI.GetClassColor(classFile)
                if cc then bar.fill:SetStatusBarColor(cc.r, cc.g, cc.b)
                elseif W.curDMType == Enum.DamageMeterType.EnemyDamageTaken then bar.fill:SetStatusBarColor(0xDD/255, 0x31/255, 0x31/255)
                else bar.fill:SetStatusBarColor(0.5, 0.5, 0.5) end
            end
            -- Repaint class-colored background for the new class (no-op when off); bar._class set here so ApplyBg reads the current class
            bar._class = classFile
            if c.barBgUseClassColor then bar.ApplyBg() end
        end
        -- Accent / custom fill: outside the class memo (as the rows paint it), so Use Accent,
        -- Custom Color and a live accent change reach the pinned row.
        if not showClassColor then
            if c.barColorUseAccent ~= false then local ar2, ag2, ab2 = GetAccentRGB(); bar.fill:SetStatusBarColor(ar2, ag2, ab2)
            else local bc = c.barColor; bar.fill:SetStatusBarColor(bc and bc.r or 0.35, bc and bc.g or 0.55, bc and bc.b or 0.8) end
        end
        -- Per-tick: value + text only
        if isDeaths then
            bar.fill:SetMinMaxValues(0, 1); bar.fill:SetValue(1)
        else
            bar.fill:SetMinMaxValues(0, maxAmt); bar.fill:SetValue(src.totalAmount or 0)
        end
        -- Rank: only when position changes
        local hideNums = c.hideNumbers
        if hideNums then
            bar.pos:SetText("")
            W._stickyRankCache = nil  -- un-hiding repaints the rank
        elseif playerIdx ~= W._stickyRankCache then
            W._stickyRankCache = playerIdx
            bar.pos:SetText(RANK_STRINGS[playerIdx] or (playerIdx .. "."))
        end
        -- Name: only when source name changes (guard secret values)
        local srcName = src.name
        if issecretvalue and issecretvalue(srcName) then
            bar.label:SetText(StripRealm(srcName, src))
            W._stickyNameCache = nil
        elseif srcName ~= W._stickyNameCache then
            W._stickyNameCache = srcName
            bar.label:SetText(StripRealm(srcName, src))
        end
        if isDeaths then
            local isOverall = (not W.curSessionID and W.curSession == Enum.DamageMeterSessionType.Overall)
            bar.amount:SetText(isOverall and "" or ns._DeathTimeText(src,
                not W.curSessionID and W.curSession == Enum.DamageMeterSessionType.Current))
        elseif isCount then
            bar.amount:SetText(AbbrevNumber(src.totalAmount))
        else
            bar.amount:SetText(FormatBarValue(src.totalAmount, src.amountPerSecond, c.numberFormat or 2))
        end
        if c.rightTextUseThreatGradient then
            if not W._valueGradientRange then ns.DMPrepareValueGradient(W, sources, #sources) end
            ns.DMPaintValueGradient(bar, W, src, playerIdx)
            bar._valueGradientActive = true
        elseif bar._valueGradientActive then
            bar._valueGradientActive, bar._gradT = nil, nil
            local color = c.rightTextUseClassColor and classFile and EUI.GetClassColor(classFile) or c.rightTextColor
            bar.amount:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
        end
        bar._src = src; bar._srcGUID = src.sourceGUID; bar._class = classFile
        W.stickySep:Show()
        if c.barSeparators or c.iconSeparator or c.showPlayerMarker or W._decorSync then
            ns.DMApplyRowDecor(bar, W, src, pinTop and 0 or -1)
        end

    end

    RefreshUI = function(session)

        if not frame then return end
        -- Hidden (a deferred or repopulate pass landing after a hide): no paint. The
        -- OnShow catch-up refetches, so the skipped session never reaches the screen.
        if not frame:IsVisible() then W._refreshPending = true; return end
        W._lastSession = session  -- cache for scroll-triggered refresh

        -- Populate rows
        local count = 0
        if session and session.combatSources then

            local sources = session.combatSources
            local c = DB(); local barH, barSp, stride = ns._RowMetrics(c.barHeight or 18, c.barSpacing or 2, frame:GetEffectiveScale())
            local rowDecor = c.barSeparators or c.iconSeparator or c.showPlayerMarker or W._decorSync
            local leftFS = c.leftFontSize or c.fontSize or 11; local rightFS = c.rightFontSize or c.fontSize or 11
            local fontSize = leftFS -- compat for cacheKey
            local showIcon = (c.iconStyle or "spec") ~= "none"
            local showClassColor = c.showClassColor ~= false; local texPath, texKey = GetBarTexturePath()
            local rowWidth = viewport:GetWidth() or 200
            local labelMaxW = math.max(20, rowWidth * 0.60)
            local isDeaths = (W.curDMType == Enum.DamageMeterType.Deaths)
            local isCount = (W.curDMType == Enum.DamageMeterType.Interrupts or W.curDMType == Enum.DamageMeterType.Dispels)
            -- WoW Forever's Threat rows carry their rank, value text and highlight colour.
            local isThreat = (W.curDMType == "threat")
            -- Deaths: reverse to chronological (API returns most recent first) and filter feign
            -- deaths; CleanupFeignCache runs first so real deaths after Feign Death aren't hidden by the cached spell 5384 GUID
            if isDeaths then
                CleanupFeignCache()
                local rev = {}
                for ri = #sources, 1, -1 do
                    local s = sources[ri]
                    local rid = s.deathRecapID
                    local sg = s.sourceGUID
                    -- _feignDeathGUIDs[secret] throws ("cannot be indexed with secret keys"), so only
                    -- consult the cache for a plain-string GUID; secret-GUID rows fall back to the deathRecapID-only filter
                    local sgOk = sg and (not issecretvalue or not issecretvalue(sg))
                    if not (issecretvalue and issecretvalue(rid)) and rid and rid > 0
                       and not (sgOk and _feignDeathGUIDs[sg]) then
                        rev[#rev + 1] = s
                    end
                end
                sources = rev
            end
            local maxAmt = isDeaths and 1 or (sources[1] and sources[1].totalAmount or 1)
            count = math.min(#sources, BAR_POOL_SIZE)
            if c.rightTextUseThreatGradient then ns.DMPrepareValueGradient(W, sources, #sources) end
            -- Before the visible range below: it must read this segment's clamped scroll and pinned viewport.
            RecalcViewport(count)
            W.UpdateSticky(sources, count)
            -- Cache key: detects settings changes that require full bar rebuild
            local iconStyle = c.iconStyle or "spec"
            local cacheKey = leftFS .. "|" .. rightFS .. "|" .. texPath .. "|" .. iconStyle .. "|" .. tostring(showClassColor) .. "|" .. tostring(c.barColorUseAccent) .. "|" .. barH .. "|" .. barSp .. "|" .. tostring(c.hideNumbers) .. "|" .. tostring(c.leftTextUseClassColor) .. "|" .. tostring(c.rightTextUseClassColor) .. "|" .. tostring(c.barFillAlpha) .. "|" .. tostring(c.classIconZoom)
            if (c.spriteIconZoom or 0) ~= 0 or c.rightTextUseThreatGradient then
                cacheKey = cacheKey .. "|" .. tostring(c.spriteIconZoom) .. "|" .. tostring(c.rightTextUseThreatGradient)
            end
            local fullRebuild = (cacheKey ~= W._barCacheKey)
            if fullRebuild then W._barCacheKey = cacheKey end

            local numFmt = c.numberFormat or 2
            local isSecret = issecretvalue and true or false

            -- Visible range calculation
            local scrollOff = viewport:GetVerticalScroll() or 0
            local viewH = viewport:GetHeight() or 200
            -- Unresolved rect (first pass after build): fill every row once. A squeezed
            -- but resolved viewport keeps its real height, or it would fill the pool every tick.
            if viewH <= 0 and not viewport:IsRectValid() then viewH = count * stride end
            local visFirst = math.floor(scrollOff / stride) + 1
            local visLast = math.min(count, math.ceil((scrollOff + viewH) / stride))

            for i = 1, BAR_POOL_SIZE do
                local bar = W.rowPool[i]
                if i <= count then
                    local src = sources[i]
                    if not bar.row:IsShown() then bar.row:Show() end

                    -- Layout + appearance: only on settings change or bar reuse
                    if fullRebuild or bar._cachedSlot ~= i then
                        bar._cachedSlot = i
                        bar.row:ClearAllPoints()
                        local yOff = -((i-1) * stride)
                        bar.row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, yOff)
                        bar.row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, yOff)
                        bar.row:SetHeight(barH)
                        bar.fill:ClearAllPoints(); bar.fill:SetHeight(barH)
                        ApplyBarTexture(bar.fill, texPath, texKey)
                        bar.fill:SetAlpha(c.barFillAlpha or 1)
                        SetDMFont(bar.pos, leftFS); SetDMFont(bar.label, leftFS); SetDMFont(bar.amount, rightFS)
                        bar.label:SetWidth(labelMaxW)
                        if c.hideNumbers then
                            bar.pos:SetText("")
                        else
                            bar.pos:SetText(RANK_STRINGS[i] or (i .. "."))
                        end
                        -- false: never a classFilename, so the next visible pass always re-seats the fill cleared above
                        bar._cachedClass = false; bar._cachedSpecIcon = nil; bar._cachedColorClass = false
                        bar._cachedRank = nil; bar._cachedThreatColor = nil; bar._gradT = nil
                    end

                    -- Per-tick content: only for visible bars
                    if i >= visFirst and i <= visLast then
                        -- Icon: only when class changes
                        -- Icon: only when the icon's own inputs change. The
                        -- memo must include the SPEC, not just the class: bars
                        -- are recycled by rank, so a swap between same-class
                        -- players of different specs left classFile unchanged
                        -- and the row kept the previous player's spec icon.
                        local classFile = src.classFilename
                        local specIcon = src.specIconID
                        if classFile ~= bar._cachedClass or specIcon ~= bar._cachedSpecIcon then
                            bar._cachedClass = classFile
                            bar._cachedSpecIcon = specIcon
                            local iconOffset = showIcon and ResolveIcon(src, bar.classIcon, barH) or 0
                            if not showIcon then bar.classIcon:Hide() end
                            if bar._iconBorderFrame then bar._iconBorderFrame:SetShown(c.customIconBorder and (c.iconBorderSize or 0) > 0 and bar.classIcon:IsShown()) end
                            bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", iconOffset, 0)
                            bar.fill:SetPoint("TOPRIGHT", bar.row, "TOPRIGHT", 0, 0)
                            bar._cachedColorClass = false
                            -- Repaint class-colored background for the new class (no-op when off); bar._class set here so ApplyBg reads the current class
                            bar._class = classFile
                            if c.barBgUseClassColor then bar.ApplyBg() end
                        end

                        -- Fill value
                        if isDeaths then
                            bar.fill:SetMinMaxValues(0, 1)
                            bar.fill:SetValue(1)
                        else
                            bar.fill:SetMinMaxValues(0, maxAmt)
                            bar.fill:SetValue(src.totalAmount or 0)
                        end

                        -- Threat: the pull line takes no rank, so ranks move with it
                        if isThreat and not c.hideNumbers and bar._cachedRank ~= src.rankText then
                            bar._cachedRank = src.rankText
                            bar.pos:SetText(src.rankText)
                        end

                        -- Color (a Threat row's highlight wins; false makes the
                        -- next plain row repaint its own colour, which drops the
                        -- highlight memo)
                        local threatColor = isThreat and src.threatColor
                        if threatColor then
                            if bar._cachedThreatColor ~= threatColor then
                                bar._cachedThreatColor = threatColor
                                bar.fill:SetStatusBarColor(threatColor.r, threatColor.g, threatColor.b)
                            end
                            bar._cachedColorClass = false
                        elseif showClassColor then
                            if classFile ~= bar._cachedColorClass then
                                bar._cachedColorClass = classFile
                                bar._cachedThreatColor = nil
                                local cc = classFile and RAID_CLASS_COLORS[classFile] and EUI.GetClassColor(classFile)
                                if cc then bar.fill:SetStatusBarColor(cc.r, cc.g, cc.b)
                                elseif W.curDMType == Enum.DamageMeterType.EnemyDamageTaken then bar.fill:SetStatusBarColor(0xDD/255, 0x31/255, 0x31/255)
                                else bar.fill:SetStatusBarColor(0.5, 0.5, 0.5) end
                            end
                        elseif fullRebuild or not bar._cachedColorClass then
                            bar._cachedColorClass = false
                            bar._cachedThreatColor = nil
                            if c.barColorUseAccent ~= false then local ar2, ag2, ab2 = GetAccentRGB(); bar.fill:SetStatusBarColor(ar2, ag2, ab2)
                            else local bc = c.barColor; bar.fill:SetStatusBarColor(bc and bc.r or 0.35, bc and bc.g or 0.55, bc and bc.b or 0.8) end
                        end

                        -- Left text color (pos + label)
                        if c.leftTextUseClassColor then
                            local cc = classFile and RAID_CLASS_COLORS[classFile] and EUI.GetClassColor(classFile)
                            local lr, lg, lb = cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1
                            bar.label:SetTextColor(lr, lg, lb)
                            bar.pos:SetTextColor(lr, lg, lb)
                        elseif fullRebuild then
                            local tc = c.leftTextColor
                            local lr, lg, lb = tc and tc.r or 1, tc and tc.g or 1, tc and tc.b or 1
                            bar.label:SetTextColor(lr, lg, lb)
                            bar.pos:SetTextColor(lr, lg, lb)
                        end
                        -- Right text color (amount)
                        if c.rightTextUseThreatGradient then
                            ns.DMPaintValueGradient(bar, W, src, i)
                        elseif c.rightTextUseClassColor then
                            local cc = classFile and RAID_CLASS_COLORS[classFile] and EUI.GetClassColor(classFile)
                            local rr, rg, rb = cc and cc.r or 1, cc and cc.g or 1, cc and cc.b or 1
                            bar.amount:SetTextColor(rr, rg, rb)
                        elseif fullRebuild then
                            local tc = c.rightTextColor
                            local rr, rg, rb = tc and tc.r or 1, tc and tc.g or 1, tc and tc.b or 1
                            bar.amount:SetTextColor(rr, rg, rb)
                        end

                        -- Name
                        local srcName = src.name
                        if isSecret and issecretvalue(srcName) then
                            bar.label:SetText(StripRealm(srcName, src))
                            bar._cachedSrcName = nil
                        elseif srcName ~= bar._cachedSrcName then
                            bar._cachedSrcName = srcName
                            bar._cachedDisplayName = StripRealm(srcName, src)
                            bar.label:SetText(bar._cachedDisplayName)
                        end

                        -- Amount text (guard secret values -- can't compare)
                        local fmtVal
                        if isThreat then
                            fmtVal = src.threatText
                        elseif isDeaths then
                            local isOverall = (not W.curSessionID and W.curSession == Enum.DamageMeterSessionType.Overall)
                            fmtVal = isOverall and "" or ns._DeathTimeText(src,
                                not W.curSessionID and W.curSession == Enum.DamageMeterSessionType.Current)
                        elseif isCount then
                            fmtVal = AbbrevNumber(src.totalAmount)
                        else
                            fmtVal = FormatBarValue(src.totalAmount, src.amountPerSecond, numFmt)
                        end
                        if isSecret and issecretvalue(fmtVal) then
                            bar.amount:SetText(fmtVal)
                            bar._cachedAmtText = nil
                        elseif fmtVal ~= bar._cachedAmtText then
                            bar._cachedAmtText = fmtVal
                            bar.amount:SetText(fmtVal)
                        end
                        bar._src = src; bar._srcGUID = src.sourceGUID; bar._class = classFile
                        if rowDecor then ns.DMApplyRowDecor(bar, W, src, i) end
                    end
                else
                    if bar.row:IsShown() then bar.row:Hide() end
                    bar._src = nil; bar._srcGUID = nil; bar._class = nil
                    bar._cachedSlot = nil; bar._cachedClass = false; bar._cachedSpecIcon = nil; bar._cachedColorClass = false
                    bar._cachedSrcName = nil; bar._cachedDisplayName = nil; bar._cachedAmtText = nil
                    bar._cachedRank = nil; bar._cachedThreatColor = nil
                end
            end

        else
            for i = 1, BAR_POOL_SIZE do W.rowPool[i].row:Hide() end
            W.cachedSources = nil
            RecalcViewport(0)
            W.UpdateSticky(nil, 0)
        end
        W.visibleCount = count
        if W._decorSync then ns.DMSyncRowDecor(W) end

        W.UpdateTimerText()
        local isOverall = (not W.curSessionID and W.curSession == Enum.DamageMeterSessionType.Overall)
        local typeName = L(DM_TYPE_NAMES[W.curDMType] or "Damage Done")
        W._fullTitle = isOverall and EllesmereUI.Lf("Overall %1$s", typeName) or typeName
        -- A Threat list (WoW Forever) names its mob and has no segments.
        if session and session.threatTitle then W._fullTitle = session.threatTitle end
        W.FitTitle()
        if winIdx == 1 then UpdateSATimerText() end

        if W.sourceOpen then
            W.RefreshBreakdown()
        end

    end

    -- Header combat timer, decoupled from the meter refresh rate: the shared timer ticker calls this
    -- between refreshes so the clock ticks smoothly at slow rates. Memoized on the displayed second (inputs: resolved duration second + the blank state from Overall/no-data gates).
    function W.UpdateTimerText()
        -- IsVisible covers a hidden timer (hideTimer) and a hidden window alike: no duration
        -- read. The second-memo repaints on the first tick after it shows again, and a
        -- window's OnShow catch-up refresh runs this at once.
        if not W.timerText or not W.timerText:IsVisible() then return end
        -- A Threat list (WoW Forever) has no fight clock.
        if W.curDMType == "threat" then
            if W._timerSec ~= -1 then W._timerSec = -1; W.timerText:SetText("") end
            return
        end
        local isOverall = (not W.curSessionID and W.curSession == Enum.DamageMeterSessionType.Overall)
        local dur
        if W.curSessionID then
            -- Historical session: use that session's stored API duration
            if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
                local sess = C_DamageMeter.GetAvailableCombatSessions()
                if sess then for _, s in ipairs(sess) do if s.sessionID == W.curSessionID then dur = s.durationSeconds; break end end end
            end
        elseif W.curSession == Enum.DamageMeterSessionType.Current then
            -- Live "Current" view: derived from the SAME session the bars render, so it resets
            -- on a Current roll and freezes at combat end in lockstep with the bars (see GetCurrentViewDuration)
            dur = GetCurrentViewDuration()
        elseif not isOverall then
            -- Overall never reads a duration (the isOverall gate below blanks its timer)
            dur = C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds and C_DamageMeter.GetSessionDurationSeconds(W.curSession)
        end
        -- Hide timer when segment has no data (count == 0) or is Overall
        local sec = -1
        if not isOverall and dur and type(dur) == "number" and dur > 0 and (W.visibleCount or 0) > 0 then
            sec = math.floor(dur)
        end
        if W._timerSec == sec then return end
        W._timerSec = sec
        if sec >= 0 then
            W.timerText:SetText("(" .. FormatTimer(dur) .. ")")
        else
            W.timerText:SetText("")
        end
    end

    -- sync: paint in this call even past PEAK_BUDGET (the OnShow catch-up, which must
    -- never leave the pre-hide rows up for a frame).
    function W.Refresh(sync)
        if not frame then return end
        -- Hidden by any rule (instance rule, the hotkey, a failing global rule, between
        -- hovers, Alt-Z): no fetch, no paint. The frame's OnShow runs one catch-up.
        if not frame:IsVisible() then
            W._refreshPending = true
            -- The standalone timer rides window 1's refresh and has its own visibility
            if winIdx == 1 then UpdateSATimerText() end
            -- A live Deaths view still stamps its in-combat death times
            ns._DMHiddenDeathsPass(W)
            return
        end
        -- WoW Forever's Threat type: Forever Essentials' list, no session fetch.
        if W.curDMType == "threat" then
            RefreshUI(ns.DMThreatSession and ns.DMThreatSession())
            return
        end

        local apiStart = debugprofilestop()
        local session
        if W.curSessionID and C_DamageMeter and C_DamageMeter.GetCombatSessionFromID then
            local ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, W.curSessionID, W.curDMType)
            if ok then session = s end
        elseif C_DamageMeter and C_DamageMeter.GetCombatSessionFromType then
            session = C_DamageMeter.GetCombatSessionFromType(W.curSession, W.curDMType)
        end
        local apiMs = debugprofilestop() - apiStart

        -- If API spiked, defer UI work to next frame so peaks don't stack
        if apiMs > PEAK_BUDGET and not sync then
            C_Timer.After(0, function()
                RefreshUI(session)
            end)
        else
            RefreshUI(session)
        end

    end

    function W.RefreshBreakdown()
        if not W.sourceOpen then return end
        if not W.sourceGUID and not W.sourceCreatureID then return end
        -- Hidden: the OnShow catch-up reaches the breakdown through RefreshUI
        if not frame:IsVisible() then W._refreshPending = true; return end
        if not C_DamageMeter then return end
        EnsureSpellPool()

        local isDeathRecap = (W.curDMType == Enum.DamageMeterType.Deaths)

        -- Death recap: use C_DeathRecap API instead of combatSpells
        if isDeathRecap then
            local recapID = W.sourceRecapID
            if recapID and issecretvalue and issecretvalue(recapID) then recapID = nil end
            local events
            if recapID and recapID > 0 and C_DeathRecap and C_DeathRecap.GetRecapEvents then
                local ok, raw = pcall(C_DeathRecap.GetRecapEvents, recapID)
                if ok and raw and #raw > 0 then events = raw end
            end
            if not events then
                if W.spellPool then for i = 1, BAR_POOL_SIZE do W.spellPool[i].row:Hide() end end
                return
            end
            -- Same secret discipline as the hover recap: undocumented event
            -- fields may be SECRET mid-combat, so reads are guarded before Lua
            -- touches them or handed whole to engine sinks; plain values render
            -- byte-identically to the pre-combat output.
            local maxHP, maxHPSecret = 1, nil
            if C_DeathRecap.GetRecapMaxHealth then
                local ok2, hp = pcall(C_DeathRecap.GetRecapMaxHealth, recapID)
                if ok2 and hp then
                    if IsSecret(hp) then maxHPSecret = hp
                    elseif type(hp) == "number" and hp > 0 then maxHP = hp end
                end
            end
            -- Events come newest-first from API; reverse to oldest-first
            local reversed = {}
            for ri = #events, 1, -1 do reversed[#reversed + 1] = events[ri] end
            local c = DB(); local barH, _, stride = ns._RowMetrics(c.barHeight or 18, c.barSpacing or 2, frame:GetEffectiveScale())
            local leftFS = c.leftFontSize or c.fontSize or 11; local rightFS = c.rightFontSize or c.fontSize or 11
            local texPath, texKey = GetBarTexturePath()
            local deathTime = reversed[#reversed] and reversed[#reversed].timestamp
            if IsSecret(deathTime) then deathTime = nil end
            deathTime = deathTime or GetTime()
            local evCount = math.min(#reversed, BAR_POOL_SIZE)
            for i = 1, BAR_POOL_SIZE do
                local bar = W.spellPool[i]
                if i <= evCount then
                    local ev = reversed[i]; bar.row:Show()
                    bar.row:ClearAllPoints()
                    bar.row:SetPoint("TOPLEFT", W.srcContent, "TOPLEFT", 0, -((i-1) * stride))
                    bar.row:SetPoint("TOPRIGHT", W.srcContent, "TOPRIGHT", 0, -((i-1) * stride))
                    bar.row:SetHeight(barH)
                    -- Spell icon (135274 = melee attack fallback); a secret id
                    -- goes into GetSpellTexture whole (AllowedWhenTainted)
                    local iconOffset = 0
                    local spID = ev.spellId
                    local spIcon
                    if spID and (IsSecret(spID) or spID > 0) then
                        spIcon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spID)
                    end
                    if not spIcon then spIcon = 135274 end
                    local _cz = DB().classIconZoom or 0.06
                    bar.classIcon:SetTexture(spIcon); bar.classIcon:SetTexCoord(_cz, 1 - _cz, _cz, 1 - _cz); bar.classIcon:SetSize(barH, barH); bar.classIcon:Show(); iconOffset = barH
                    bar.fill:ClearAllPoints(); bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", iconOffset, 0)
                    bar.fill:SetPoint("TOPRIGHT", bar.row, "TOPRIGHT", 0, 0); bar.fill:SetHeight(barH)
                    -- Fill = HP% remaining at this event; secret HP numbers go
                    -- to the StatusBar whole, which divides engine-side
                    local curHP = ev.currentHP or 0
                    local hpPct
                    if not IsSecret(curHP) and not maxHPSecret and type(curHP) == "number" then
                        hpPct = maxHP > 0 and (curHP / maxHP) or 0
                        hpPct = math.min(1, math.max(0, hpPct))
                    end
                    ApplyBarTexture(bar.fill, texPath, texKey)
                    if hpPct then bar.fill:SetMinMaxValues(0, 1); bar.fill:SetValue(hpPct)
                    else bar.fill:SetMinMaxValues(0, maxHPSecret or maxHP); bar.fill:SetValue(curHP) end
                    local evType = ev.event or ""
                    if IsSecret(evType) then evType = "" end
                    local isHeal = (evType == "SPELL_HEAL" or evType == "SPELL_PERIODIC_HEAL")
                    local isFatal = (i == evCount and not isHeal)
                    if isHeal then
                        bar.fill:SetStatusBarColor(0.10, 0.50, 0.10)
                    else
                        bar.fill:SetStatusBarColor(0.60, 0.08, 0.08)
                    end
                    SetDMFont(bar.label, leftFS); SetDMFont(bar.amount, rightFS)
                    bar.label:SetTextColor(1, 1, 1); bar.amount:SetTextColor(1, 1, 1)
                    -- Label: time before death + spell name. A secret name is
                    -- KEPT (FontStrings display secrets) and engine-formatted
                    -- so it never meets Lua concatenation.
                    local spellName = ev.spellName
                    local nameSecret = IsSecret(spellName)
                    if not nameSecret and (not spellName or spellName == "") then
                        if isHeal then spellName = "Heal"
                        elseif evType == "SWING_DAMAGE" then spellName = "Melee"
                        else spellName = "Unknown" end
                    end
                    local ts = ev.timestamp
                    local td
                    if not IsSecret(ts) then td = deathTime - (ts or deathTime) end
                    if td then bar.label:SetFormattedText("-%.1fs %s", td, spellName)
                    else bar.label:SetFormattedText("%s", spellName) end
                    -- Amount: damage/heal + overkill on killing blow + HP%
                    local amt = ev.amount or 0
                    local pctStr = hpPct and format(" (%.0f%%)", hpPct * 100) or ""
                    if IsSecret(amt) then
                        -- Secret amount: engine abbreviation, no sign/overkill dressing
                        bar.amount:SetFormattedText("%s%s", AbbrevNumber(amt), pctStr)
                    else
                        local amtStr
                        if isHeal then
                            amtStr = "+" .. AbbrevNumber(math.abs(amt))
                        else
                            amtStr = "-" .. AbbrevNumber(amt)
                        end
                        local overkill = ev.overkill
                        if isFatal and overkill and not IsSecret(overkill) and type(overkill) == "number" and overkill > 0 then
                            bar.amount:SetText(amtStr .. " |cffff3333(" .. EllesmereUI.Lf("%1$s overkill", AbbrevNumber(overkill)) .. ")|r" .. pctStr)
                        else
                            bar.amount:SetText(amtStr .. pctStr)
                        end
                    end
                    bar._spellID = spID
                else bar.row:Hide(); bar._spellID = nil end
            end
            local srcTotalH = evCount * stride
            W.srcContent:SetHeight(math.max(10, srcTotalH))
            local srcViewH = W.srcViewport:GetHeight(); if srcViewH < 1 then srcViewH = 1 end
            _srcScrollMax = math.max(0, srcTotalH - srcViewH)
            return
        end

        -- Enemy Damage Taken: show per-player breakdown instead of per-spell
        if W.curDMType == Enum.DamageMeterType.EnemyDamageTaken then
            local guid = W.sourceGUID
            local cid = W.sourceCreatureID
            local srcData
            if W.curSessionID and C_DamageMeter.GetCombatSessionSourceFromID then
                local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromID, W.curSessionID, W.curDMType, guid, cid)
                if ok then srcData = sd end
            elseif C_DamageMeter.GetCombatSessionSourceFromType then
                local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromType, W.curSession, W.curDMType, guid, cid)
                if ok then srcData = sd end
            end
            local c = DB(); local barH, _, stride = ns._RowMetrics(c.barHeight or 18, c.barSpacing or 2, frame:GetEffectiveScale())
            local players = AggregateEnemyPlayers(srcData, GetBreakdownDuration(W.curSession, W.curSessionID))
            if not players then
                if W.spellPool then for i = 1, BAR_POOL_SIZE do W.spellPool[i].row:Hide() end end
                return
            end
            local leftFS = c.leftFontSize or c.fontSize or 11; local rightFS = c.rightFontSize or c.fontSize or 11
            local texPath, texKey = GetBarTexturePath()
            local maxAmt = players[1].total
            local pCount = math.min(#players, BAR_POOL_SIZE)
            for i = 1, BAR_POOL_SIZE do
                local bar = W.spellPool[i]
                if i <= pCount then
                    local p = players[i]; bar.row:Show()
                    bar.row:ClearAllPoints()
                    bar.row:SetPoint("TOPLEFT", W.srcContent, "TOPLEFT", 0, -((i-1) * stride))
                    bar.row:SetPoint("TOPRIGHT", W.srcContent, "TOPRIGHT", 0, -((i-1) * stride))
                    bar.row:SetHeight(barH)
                    -- Class/spec icon via ResolveIcon (consistent with main bars)
                    local fakeSrc = { classFilename = p.class, specIconID = p.specIcon }
                    local iconOffset = ResolveIcon(fakeSrc, bar.classIcon, barH)
                    bar.fill:ClearAllPoints(); bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", iconOffset, 0)
                    bar.fill:SetPoint("TOPRIGHT", bar.row, "TOPRIGHT", 0, 0); bar.fill:SetHeight(barH)
                    ApplyBarTexture(bar.fill, texPath, texKey); bar.fill:SetMinMaxValues(0, maxAmt); bar.fill:SetValue(p.total)
                    local cc = p.class and RAID_CLASS_COLORS[p.class] and EUI.GetClassColor(p.class)
                    if cc then bar.fill:SetStatusBarColor(cc.r, cc.g, cc.b)
                    else local ar2, ag2, ab2 = GetAccentRGB(); bar.fill:SetStatusBarColor(ar2, ag2, ab2) end
                    SetDMFont(bar.label, leftFS); SetDMFont(bar.amount, rightFS)
                    bar.label:SetTextColor(1, 1, 1); bar.amount:SetTextColor(1, 1, 1)
                    bar.label:SetText(StripRealm(p.name, nil, p))
                    bar.amount:SetText(FormatBarValue(p.total, p.amountPerSecond, c.numberFormat or 2)); bar._spellID = nil
                else bar.row:Hide(); bar._spellID = nil end
            end
            local srcTotalH = pCount * stride
            W.srcContent:SetHeight(math.max(10, srcTotalH))
            local srcViewH = W.srcViewport:GetHeight(); if srcViewH < 1 then srcViewH = 1 end
            _srcScrollMax = math.max(0, srcTotalH - srcViewH)
            return
        end

        -- Standard spell breakdown (non-Deaths)
        -- Pass guid/cid straight through -- API accepts its own secret values
        local guid = W.sourceGUID
        local cid = W.sourceCreatureID
        local srcData
        if W.curSessionID and C_DamageMeter.GetCombatSessionSourceFromID then
            local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromID, W.curSessionID, W.curDMType, guid, cid)
            if ok then srcData = sd end
        elseif C_DamageMeter.GetCombatSessionSourceFromType then
            local ok, sd = pcall(C_DamageMeter.GetCombatSessionSourceFromType, W.curSession, W.curDMType, guid, cid)
            if ok then srcData = sd end
        end
        if not srcData or not srcData.combatSpells then
            if W.spellPool then for i = 1, BAR_POOL_SIZE do W.spellPool[i].row:Hide() end end
            return
        end
        local spells = srcData.combatSpells; local c = DB(); local barH, barSp, stride = ns._RowMetrics(c.barHeight or 18, c.barSpacing or 2, frame:GetEffectiveScale())
        local leftFS = c.leftFontSize or c.fontSize or 11; local rightFS = c.rightFontSize or c.fontSize or 11; local texPath, texKey = GetBarTexturePath()
        local sorted = {}
        for _, spell in ipairs(spells) do local ok, amt = pcall(function() return spell.totalAmount end); sorted[#sorted + 1] = { spell = spell, amount = (ok and amt) or 0 } end
        -- API returns combatSpells pre-sorted; no table.sort needed
        local maxAmt = sorted[1] and sorted[1].amount or 1
        -- Sum totals for percentage (skip if amounts are secret)
        local totalDmg = 0
        local canPercent = maxAmt and (not issecretvalue or not issecretvalue(maxAmt)) and type(maxAmt) == "number"
        if canPercent then for _, e in ipairs(sorted) do totalDmg = totalDmg + e.amount end end
        local spCount = math.min(#sorted, BAR_POOL_SIZE)
        for i = 1, BAR_POOL_SIZE do
            local bar = W.spellPool[i]
            if i <= spCount then
                local entry = sorted[i]; local spell = entry.spell; bar.row:Show()
                bar.row:ClearAllPoints()
                local yOff2 = -((i-1) * stride)
                bar.row:SetPoint("TOPLEFT", W.srcContent, "TOPLEFT", 0, yOff2)
                bar.row:SetPoint("TOPRIGHT", W.srcContent, "TOPRIGHT", 0, yOff2)
                bar.row:SetHeight(barH)
                local iconOffset = 0
                -- Same secret-spellID handling as the tooltip breakdown (PopulatePreview): a
                -- secret id goes through pcall and its result is tested by type().
                local spID = spell.spellID
                local getTex = C_Spell and C_Spell.GetSpellTexture
                local spIcon, haveIcon
                if spID and getTex then
                    if IsSecret(spID) then
                        local ok, tex = pcall(getTex, spID)
                        if ok and type(tex) ~= "nil" then spIcon, haveIcon = tex, true end
                    else
                        spIcon = getTex(spID)
                        haveIcon = spIcon and true or false
                    end
                end
                if haveIcon then
                    local _cz = DB().classIconZoom or 0.06
                    bar.classIcon:SetTexture(spIcon); bar.classIcon:SetTexCoord(_cz, 1 - _cz, _cz, 1 - _cz); bar.classIcon:SetSize(barH, barH); bar.classIcon:Show(); iconOffset = barH
                else bar.classIcon:Hide() end
                bar.fill:ClearAllPoints(); bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", iconOffset, 0)
                bar.fill:SetPoint("TOPRIGHT", bar.row, "TOPRIGHT", 0, 0); bar.fill:SetHeight(barH)
                ApplyBarTexture(bar.fill, texPath, texKey); bar.fill:SetMinMaxValues(0, maxAmt); bar.fill:SetValue(entry.amount)
                if W.sourceClass and RAID_CLASS_COLORS[W.sourceClass] then
                    local cc = EUI.GetClassColor(W.sourceClass); bar.fill:SetStatusBarColor(cc.r, cc.g, cc.b)
                else local ar2, ag2, ab2 = GetAccentRGB(); bar.fill:SetStatusBarColor(ar2, ag2, ab2) end
                SetDMFont(bar.label, leftFS); SetDMFont(bar.amount, rightFS)
                local spellName
                if spell.spellID then local okS, sn = pcall(function() return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spell.spellID) end); spellName = (okS and sn) or nil end
                bar.label:SetText(spellName or spell.creatureName or L("Unknown"))
                if canPercent and totalDmg > 0 then
                    bar.amount:SetText(format("%s  %.1f%%", AbbrevNumber(entry.amount), (entry.amount / totalDmg) * 100))
                else
                    bar.amount:SetText(AbbrevNumber(entry.amount))
                end
                bar._spellID = spell.spellID
            else bar.row:Hide(); bar._spellID = nil end
        end

        -- Targets section (DamageDone only): show top 3 enemies this player hit.
        -- Skipped in combat: it cross-references and COMPARES amounts across
        -- sources in Lua, which secrets cannot survive.
        local targetsRendered = 0
        if W.curDMType == Enum.DamageMeterType.DamageDone and not InCombatLockdown() then
            if not W._cachedTargets then
                W._cachedTargets = BuildPlayerTargets(W.sourceRawName, W.curSession, W.curSessionID, 3) or false
            end
            local tList = W._cachedTargets
            if tList and tList ~= false then
                -- Divider + "Targets" label
                local divY = -(spCount * stride + barSp * 2)
                if not W._targetDivider then
                    W._targetDivider = W.srcContent:CreateTexture(nil, "ARTWORK")
                    W._targetDivider:SetHeight(PhysicalPixels(1)); W._targetDivider:SetColorTexture(1, 1, 1, 0.15)
                    W._targetLabel = W.srcContent:CreateFontString(nil, "OVERLAY")
                    SetDMFont(W._targetLabel, leftFS - 1)
                    W._targetLabel:SetTextColor(0.6, 0.6, 0.6, 1); W._targetLabel:SetText(EllesmereUI.L("Targets"))
                end
                W._targetDivider:ClearAllPoints()
                W._targetDivider:SetPoint("TOPLEFT", W.srcContent, "TOPLEFT", 0, divY)
                W._targetDivider:SetPoint("TOPRIGHT", W.srcContent, "TOPRIGHT", 0, divY)
                W._targetDivider:Show()
                local labelY = divY - barSp - 10
                W._targetLabel:ClearAllPoints()
                W._targetLabel:SetPoint("LEFT", W.srcContent, "TOPLEFT", 3, labelY)
                SetDMFont(W._targetLabel, leftFS - 1)
                W._targetLabel:Show()

                local tStartY = labelY - 12
                local tMaxAmt = tList[1].total
                for ti = 1, #tList do
                    local tIdx = spCount + ti
                    if tIdx > BAR_POOL_SIZE then break end
                    local bar = W.spellPool[tIdx]
                    local t = tList[ti]; bar.row:Show()
                    bar.row:ClearAllPoints()
                    bar.row:SetPoint("TOPLEFT", W.srcContent, "TOPLEFT", 0, tStartY - ((ti-1) * stride))
                    bar.row:SetPoint("TOPRIGHT", W.srcContent, "TOPRIGHT", 0, tStartY - ((ti-1) * stride))
                    bar.row:SetHeight(barH)
                    bar.classIcon:Hide()
                    bar.fill:ClearAllPoints(); bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", 0, 0)
                    bar.fill:SetPoint("TOPRIGHT", bar.row, "TOPRIGHT", 0, 0); bar.fill:SetHeight(barH)
                    ApplyBarTexture(bar.fill, texPath, texKey); bar.fill:SetMinMaxValues(0, tMaxAmt); bar.fill:SetValue(t.total)
                    bar.fill:SetStatusBarColor(0xDD/255, 0x31/255, 0x31/255)
                    SetDMFont(bar.label, leftFS); SetDMFont(bar.amount, rightFS)
                    bar.label:SetTextColor(1, 1, 1); bar.amount:SetTextColor(1, 1, 1)
                    bar.label:SetText(t.name)
                    bar.amount:SetText(FormatBarValue(t.total, t.amountPerSecond, c.numberFormat or 2)); bar._spellID = nil
                    targetsRendered = targetsRendered + 1
                end
            end
        end
        -- Hide divider/label if no targets
        if targetsRendered == 0 then
            if W._targetDivider then W._targetDivider:Hide() end
            if W._targetLabel then W._targetLabel:Hide() end
        end

        local extraH = 0
        if targetsRendered > 0 then
            -- divider gap + label + target bars
            extraH = (barSp * 2) + 1 + barSp + 10 + 12 + (targetsRendered * stride)
        end
        local srcTotalH = spCount * stride + extraH
        W.srcContent:SetHeight(math.max(10, srcTotalH))
        local srcViewH = W.srcViewport:GetHeight(); if srcViewH < 1 then srcViewH = 1 end
        _srcScrollMax = math.max(0, srcTotalH - srcViewH)
    end

    function W.OpenSource(guid, creatureID, name, classFile, recapID, rawName)
        if not W.sourceFrame then return end
        W.sourceGUID = guid; W.sourceCreatureID = creatureID; W.sourceClass = classFile; W.sourceOpen = true
        W.sourceRecapID = recapID; W.sourceRawName = rawName
        W._cachedTargets = nil
        W.HideHome()
        if viewport then viewport:Hide() end
        if W.stickyPlayer then W.stickyPlayer.row:Hide() end
        if W.stickySep then W.stickySep:Hide() end
        if W._decorSync then ns.DMSyncRowDecor(W) end
        if frame._bg then frame._bg:Hide() end
        W.sourceFrame:Show(); W.RefreshBreakdown()
    end

    function W.CloseSource()
        local wasOpen = W.sourceOpen
        W.sourceOpen = false; W.sourceGUID = nil; W.sourceCreatureID = nil; W.sourceRecapID = nil; W.sourceRawName = nil
        W._cachedTargets = nil
        if W.sourceFrame then W.sourceFrame:Hide() end
        if viewport then viewport:Show() end
        if frame._bg then frame._bg:Show() end
        W.UpdateSticky(nil, W.visibleCount)
        if W._decorSync then ns.DMSyncRowDecor(W) end
        -- The last pass skipped the pin state while the source was up: rows it reveals need a fill.
        if wasOpen then W.QueueRepopulate() end
    end

    -- Home screen (quick links grid): 2-column card layout with accent indicators, + add button, hint text
    local homeScroll, homeChild  -- homeFrame is forward-declared above
    local homeCards = {}
    local homeAddBtn, homeTitle
    local _homeScrollMax = 0
    local CARD_H       = 26
    local CARD_GAP     = 4
    local CARD_COL_GAP = 4
    local CARD_PAD_X   = 8
    local CARD_PAD_TOP = 6
    local CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A = 0.12, 0.12, 0.12, 0.8
    local CARD_HL_A    = 0.18

    local function MakeCard(parent)
        local card = CreateFrame("Button", nil, parent)
        card:SetHeight(CARD_H)
        card:RegisterForClicks("AnyUp")

        card._bg = card:CreateTexture(nil, "BACKGROUND")
        card._bg:SetAllPoints()
        card._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A)

        card._accent = card:CreateTexture(nil, "ARTWORK")
        card._accent:SetWidth(2)
        card._accent:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        card._accent:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
        card._accent:Hide()

        local fontPath = (EUI.GetFontPath("damageMeters")) or "Fonts\\FRIZQT__.TTF"
        local outline = (EUI.GetFontOutlineFlag("damageMeters")) or ""
        local iconSz = CARD_H - 2
        card._icon = card:CreateTexture(nil, "OVERLAY")
        card._icon:SetSize(iconSz, iconSz)
        card._icon:SetPoint("LEFT", card, "LEFT", 6, 0)
        card._icon:SetDesaturated(true)

        card._lbl = card:CreateFontString(nil, "OVERLAY")
        card._lbl:SetFont(fontPath, CTX_FONT_SZ, outline)
        card._lbl:SetPoint("LEFT", card._icon, "RIGHT", 5, 0)
        card._lbl:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        card._lbl:SetJustifyH("LEFT")
        card._lbl:SetWordWrap(false)

        card._arrow = card:CreateTexture(nil, "ARTWORK")
        card._arrow:SetTexture(CTX_ARROW_ICON)
        card._arrow:SetSize(18, 18)
        card._arrow:SetPoint("RIGHT", card, "RIGHT", -4, 0)
        card._arrow:SetRotation(math.pi / 2)
        card._arrow:SetVertexColor(1, 1, 1, 1)

        return card
    end

    RefreshHome = function()
        if not homeFrame or not homeFrame:IsShown() then return end
        local bookmarks = GetBookmarks()
        local fontPath = (EUI.GetFontPath("damageMeters")) or "Fonts\\FRIZQT__.TTF"
        local outline = (EUI.GetFontOutlineFlag("damageMeters")) or ""
        local EG = EUI.ELLESMERE_GREEN
        local acR, acG, acB = GetAccentRGB()
        -- WoW Forever: the header's tan glyphs in place of the accent.
        local fvG = ns.DMForever() and ns.DM_FV.glyph

        -- Calculate column width from scroll frame. An unplaced window (an
        -- unlock-anchored one before the login anchor pass lands) has no
        -- width yet; laying out from zero would collapse every card. The
        -- scroll frame's size hook runs this again once the width arrives.
        local totalW = homeScroll and homeScroll:GetWidth() or homeFrame:GetWidth()
        if not totalW or totalW < 1 then return end
        local colW = (totalW - CARD_PAD_X * 2 - CARD_COL_GAP) / 2

        -- Hide all existing cards
        for _, c in ipairs(homeCards) do c:Hide() end

        -- Layout bookmarks in 2-column grid. Cards go by display position (shown);
        -- idx stays the bookmark's place in the saved list, for removal.
        local row, col = 0, 0
        local startY = -CARD_PAD_TOP
        local shown = 0

        for idx, dmType in ns.DMHomeTypes(bookmarks) do
            shown = shown + 1
            local card = homeCards[shown]
            if not card then
                card = MakeCard(homeChild)
                homeCards[shown] = card
            end

            local label = L(DM_TYPE_NAMES[dmType] or "Unknown")
            local isActive = (dmType == W.curDMType)

            local xOff = CARD_PAD_X + col * (colW + CARD_COL_GAP)
            local yOff = startY - row * (CARD_H + CARD_GAP)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", homeChild, "TOPLEFT", xOff, yOff)
            card:SetWidth(colW)

            -- WoW Forever: Forever's list buttons, the selected one marking
            -- the active meter (no accent strip).
            if not ns.DMFvCard(card._bg, isActive and "selected" or "normal") then
                card._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A)
            end
            card._lbl:SetFont(fontPath, CTX_FONT_SZ, outline)
            card._lbl:SetText(label)
            card._icon:SetTexture(DM_TYPE_ICONS[dmType] or MEDIA .. "dm_home_damage.png")
            card._arrow:Show()

            if isActive then
                card._accent:SetColorTexture(acR, acG, acB, 1)
                card._accent:SetShown(not ns._dmForever)
                if fvG then
                    card._icon:SetVertexColor(fvG[1], fvG[2], fvG[3], 1)
                else
                    card._icon:SetVertexColor(acR, acG, acB, 1)
                end
                card._lbl:SetTextColor(1, 1, 1, 1)
                card._arrow:SetVertexColor(1, 1, 1, 1)
            else
                card._accent:Hide()
                if fvG then
                    local k = ns.DM_HDR_IDLE
                    card._icon:SetVertexColor(fvG[1] * k, fvG[2] * k, fvG[3] * k, 1)
                else
                    card._icon:SetVertexColor(acR, acG, acB, 0.6)
                end
                card._lbl:SetTextColor(1, 1, 1, 0.8)
                card._arrow:SetVertexColor(1, 1, 1, 1)
            end

            card:SetScript("OnEnter", function(self)
                if not ns.DMFvCard(self._bg, "hover") then
                    self._bg:SetColorTexture(CARD_BG_R + 0.06, CARD_BG_G + 0.06, CARD_BG_B + 0.06, CARD_BG_A + CARD_HL_A)
                end
                self._lbl:SetTextColor(1, 1, 1, 1)
                self._arrow:SetVertexColor(1, 1, 1, 1)
            end)
            card:SetScript("OnLeave", function(self)
                if not ns.DMFvCard(self._bg, isActive and "selected" or "normal") then
                    self._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A)
                end
                if isActive then
                    self._lbl:SetTextColor(1, 1, 1, 1)
                    self._arrow:SetVertexColor(1, 1, 1, 1)
                else
                    self._lbl:SetTextColor(1, 1, 1, 0.8)
                    self._arrow:SetVertexColor(1, 1, 1, 1)
                end
            end)
            card:SetScript("OnClick", function(_, button)
                if button == "MiddleButton" then
                    table.remove(bookmarks, idx)
                    RefreshHome()
                elseif button == "LeftButton" then
                    W.HideHome()
                    W.SetDMType(dmType)
                end
            end)

            card:Show()
            col = col + 1
            if col >= 2 then col = 0; row = row + 1 end
        end

        -- "+ ADD NEW" button (full width, below the grid), while a type this client
        -- offers has no card yet
        local addRow = (col > 0) and (row + 1) or row
        local offered = 0
        for _ in pairs(DM_TYPE_NAMES) do offered = offered + 1 end
        if shown < offered then
            if not homeAddBtn then
                homeAddBtn = CreateFrame("Button", nil, homeChild)
                homeAddBtn:SetHeight(CARD_H)
                homeAddBtn._bg = homeAddBtn:CreateTexture(nil, "BACKGROUND"); homeAddBtn._bg:SetAllPoints()
                homeAddBtn._plus = homeAddBtn:CreateFontString(nil, "OVERLAY")
                homeAddBtn._lbl = homeAddBtn:CreateFontString(nil, "OVERLAY")
                homeAddBtn._hint = homeAddBtn:CreateFontString(nil, "OVERLAY")
                homeAddBtn._plus:SetPoint("RIGHT", homeAddBtn._lbl, "LEFT", -4, 0)
                homeAddBtn._hint:SetPoint("LEFT", homeAddBtn._lbl, "RIGHT", 6, 0)
            end
            if not ns.DMFvCard(homeAddBtn._bg, "normal", 0.5) then
                homeAddBtn._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A * 0.5)
            end
            homeAddBtn._plus:SetFont(fontPath, 13, outline)
            homeAddBtn._plus:SetText("+")
            homeAddBtn._plus:SetTextColor(1, 1, 1, 0.3)
            homeAddBtn._lbl:SetFont(fontPath, CTX_FONT_SZ, outline)
            homeAddBtn._lbl:SetText(EllesmereUI.L("ADD NEW"))
            homeAddBtn._lbl:SetTextColor(1, 1, 1, 0.3)
            homeAddBtn._hint:SetFont(fontPath, 9, outline)
            homeAddBtn._hint:SetText(EllesmereUI.L("(middle click to remove)"))
            homeAddBtn._hint:SetTextColor(1, 1, 1, 0.3)
            -- Center the group: offset label so plus+label+hint are visually centered
            local plusW = homeAddBtn._plus:GetStringWidth() + 4
            local hintW = 6 + homeAddBtn._hint:GetStringWidth()
            local shift = (plusW - hintW) / 2
            homeAddBtn._lbl:ClearAllPoints()
            homeAddBtn._lbl:SetPoint("CENTER", homeAddBtn, "CENTER", shift, 0)
            homeAddBtn:ClearAllPoints()
            homeAddBtn:SetPoint("TOPLEFT", homeChild, "TOPLEFT", CARD_PAD_X, startY - addRow * (CARD_H + CARD_GAP))
            homeAddBtn:SetPoint("TOPRIGHT", homeChild, "TOPRIGHT", -CARD_PAD_X, startY - addRow * (CARD_H + CARD_GAP))
            homeAddBtn:SetScript("OnEnter", function(self)
                if not ns.DMFvCard(self._bg, "hover", 0.7) then
                    self._bg:SetColorTexture(CARD_BG_R + 0.04, CARD_BG_G + 0.04, CARD_BG_B + 0.04, CARD_BG_A * 0.7)
                end
                self._lbl:SetTextColor(1, 1, 1, 0.5); self._plus:SetTextColor(1, 1, 1, 0.5)
            end)
            homeAddBtn:SetScript("OnLeave", function(self)
                if not ns.DMFvCard(self._bg, "normal", 0.5) then
                    self._bg:SetColorTexture(CARD_BG_R, CARD_BG_G, CARD_BG_B, CARD_BG_A * 0.5)
                end
                self._lbl:SetTextColor(1, 1, 1, 0.3); self._plus:SetTextColor(1, 1, 1, 0.3)
            end)
            homeAddBtn:SetScript("OnClick", function()
                local items = {}
                for dt, n in pairs(DM_TYPE_NAMES) do
                    local pinned = false
                    for _, b in ipairs(bookmarks) do if b == dt then pinned = true; break end end
                    if not pinned then items[#items + 1] = { text = EllesmereUI.L(n), onClick = function()
                        bookmarks[#bookmarks + 1] = dt; RefreshHome()
                    end } end
                end
                table.sort(items, function(a2, b2) return a2.text < b2.text end)
                ShowEDMMenu(items)
            end)
            homeAddBtn:Show()
            addRow = addRow + 1
        elseif homeAddBtn then
            homeAddBtn:Hide()
        end

        -- Set scroll child height to fit all content + 5px bottom padding
        local contentH = math.abs(startY) + addRow * (CARD_H + CARD_GAP) + 5
        homeChild:SetHeight(math.max(10, contentH))

        if homeScroll then
            local viewH = homeScroll:GetHeight()
            _homeScrollMax = math.max(0, contentH - viewH)
            local cur = homeScroll:GetVerticalScroll() or 0
            if cur > _homeScrollMax then homeScroll:SetVerticalScroll(_homeScrollMax) end
        end
    end

    function W.ShowHome()
        if not homeFrame then
            homeFrame = CreateFrame("Frame", nil, frame)
            homeFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            homeFrame:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
            homeFrame:SetFrameLevel(frame:GetFrameLevel() + 25)
            homeFrame:EnableMouse(true); homeFrame:Hide()

            local hBg = homeFrame:CreateTexture(nil, "BACKGROUND")
            hBg:SetAllPoints()
            hBg:SetColorTexture(0.03, 0.03, 0.03, 0.95)

            homeScroll = CreateFrame("ScrollFrame", nil, homeFrame)
            homeScroll:SetPoint("TOPLEFT", homeFrame, "TOPLEFT", 0, 0)
            homeScroll:SetPoint("BOTTOMRIGHT", homeFrame, "BOTTOMRIGHT", 0, 0)
            homeChild = CreateFrame("Frame", nil, homeScroll)
            homeChild:SetSize(1, 1)
            homeScroll:SetScrollChild(homeChild)
            homeScroll:SetScript("OnSizeChanged", function(_, w)
                homeChild:SetWidth(w)
                -- The grid is laid out from this width: re-flow it when the
                -- width changes while the page is up (first placement of an
                -- anchored window, a resize).
                if w and w > 1 and homeFrame:IsShown() then RefreshHome() end
            end)

            -- Mouse wheel scrolling (no visual scrollbar)
            local function HomeWheel(_, delta)
                local cur = homeScroll:GetVerticalScroll() or 0
                homeScroll:SetVerticalScroll(math.max(0, math.min(_homeScrollMax, cur - delta * 30)))
            end
            homeScroll:EnableMouseWheel(true)
            homeScroll:SetScript("OnMouseWheel", HomeWheel)
            homeFrame:EnableMouseWheel(true)
            homeFrame:SetScript("OnMouseWheel", HomeWheel)


            homeFrame:SetScript("OnMouseDown", function(_, button)
                if button == "RightButton" then W.HideHome() end
            end)
        end

        if viewport then viewport:Hide() end
        if W.stickyPlayer then W.stickyPlayer.row:Hide() end
        if W.stickySep then W.stickySep:Hide() end
        if frame._bg then frame._bg:Hide() end
        homeFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -ci, ci)
        homeFrame:Show()
        if W._decorSync then ns.DMSyncRowDecor(W) end
        RefreshHome()
    end

    function W.HideHome()
        local wasUp = homeFrame and homeFrame:IsShown()
        if homeFrame then homeFrame:Hide() end
        if viewport then viewport:Show() end
        if W._decorSync then ns.DMSyncRowDecor(W) end
        if frame._bg then frame._bg:Show() end
        -- ShowHome hid the pinned row on its pinned anchors: re-run the pin pass (OpenSource sets sourceOpen first).
        if wasUp and not W.sourceOpen then W.QueueRepopulate() end
    end

    function W.ToggleHome()
        if homeFrame and homeFrame:IsShown() then W.HideHome() else W.ShowHome() end
    end

    -- (Refresh ticker is shared across all windows -- see EUI_DamageMeters_Lifecycle.lua)

    -- Per-window instance rules (Hide in Dungeons / Raids / Delves / PvP / out of
    -- Instances); shared by UpdateVisibility and the mouseover predicate below.
    local function InstanceHidden()
        local _, iType = IsInInstance()
        if wdb.hideInDungeon and iType == "party" then return true end
        if wdb.hideInRaid and iType == "raid" then return true end
        if wdb.hideInDelve and C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress() then return true end
        if wdb.hideInPvP and (iType == "pvp" or iType == "arena") then return true end
        if wdb.hideOutOfInstance and (iType == "none" or iType == nil) then return true end
        return false
    end

    -- Visibility
    function W.UpdateVisibility()
        if not frame then return end
        local bars = EUI._ModuleNS.EllesmereUIDataBars
        local docked, shown
        if bars and bars.MeterDockState then docked, shown = bars.MeterDockState(W.idx) end
        if docked then
            bars.PlaceDockMeter(frame, W.idx)
            if not shown then frame:Hide(); return end
            if bars.MeterDockOverridesVisibility and bars.MeterDockOverridesVisibility() then
                frame:SetAlpha(1)
                frame:EnableMouse(true)
                frame:Show()
                return
            end
        end
        local c = DB()
        if EUI._unlockActive or ns._optionsOpen then frame:SetAlpha(1); frame:EnableMouse(true); frame:Show(); return end
        -- Hotkey toggle outranks every configured rule but yields to the two modes above
        if ns._toggleHidden then frame:Hide(); return end
        local vis = EUI.EvalVisibility(c)
        if not vis or vis == false then frame:Hide(); return end
        -- Per-window instance visibility
        if InstanceHidden() then frame:Hide(); return end
        if vis == "mouseover" then frame:Hide()
        else frame:SetAlpha(1); frame:EnableMouse(true); frame:Show() end
    end

    -- The mouseover scan's predicate (registered here and again by W.Reapply). Hover-gated
    -- sets only reveal while their conditions pass; a legacy single "mouseover" behaves exactly as before
    local function MouseoverActive()
        -- The mouseover scanner shows the frame without going through UpdateVisibility,
        -- so the toggle and the window's instance rules have to be refused here as well
        local bars = EUI._ModuleNS.EllesmereUIDataBars
        if bars and bars.MeterDockState then
            local docked, shown = bars.MeterDockState(W.idx)
            if docked and not shown then return false end
        end
        if ns._toggleHidden or InstanceHidden() then return false end
        local c = DB()
        return c ~= nil and EUI.VisWantsMouseover(c, "visibility")
    end
    EUI.RegisterVisibilityUpdater(W.UpdateVisibility)
    if EUI.RegisterMouseoverTarget then
        EUI.RegisterMouseoverTarget(frame, MouseoverActive)
    end

    -- Catch-up: refreshes skipped while hidden leave W._refreshPending, so the first show
    -- (a rule, the hotkey, a hover, the options preview, Alt-Z) repaints once, in-call,
    -- before the frame draws; then the ticks a fully hidden meter let lapse come back.
    frame:HookScript("OnShow", function()
        -- A Threat window (WoW Forever) always repaints: its list stops while
        -- no Threat window is on screen.
        if W._refreshPending or W.curDMType == "threat" then
            W._refreshPending = nil
            W.Refresh(true)
        end
        ns._DMReviveTicks()
    end)
    -- (Only where the Threat type is offered: set at login, before any window is built.)
    if DM_TYPE_NAMES.threat then
        frame:HookScript("OnHide", function()
            if W.curDMType == "threat" then ns.DMThreatSync(W) end
        end)
    end


    -- Park: takes this window out of use and keeps it whole for W.Reapply (a closed
    -- window, or one past a profile's window count): hidden, out of the visibility
    -- updates and the mouseover scan (no ghost resurrection), any hover, drag or
    -- resize ended, and listed in ns._dmParked.
    function W.Park()
        if W._parked then return end
        W._parked = true
        dragging = false; dragFrame:Hide()
        W.resizing = false; resizeFrame:Hide()
        W._endHover()
        frame:Hide()
        EUI.UnregisterVisibilityUpdater(W.UpdateVisibility)
        EUI.UnregisterMouseoverTarget(frame)
        local parked = ns._dmParked
        parked[#parked + 1] = W
    end

    -- Destroy (the close button): the window is parked and its slot removed (a window
    -- already parked holds no slot)
    function W.Destroy()
        if W._parked then return end
        W.Park()
        -- Remove from runtime array
        local oldCount = #_windows
        local runtimeIdx
        for i, w in ipairs(_windows) do if w == W then runtimeIdx = i; break end end
        if runtimeIdx then table.remove(_windows, runtimeIdx) end
        -- Compact DB: remove entry and shift remaining down (no holes). Uses W.idx (not the
        -- winIdx upvalue) since prior deletions may have shifted this window's slot since creation.
        local removedIdx = runtimeIdx or W.idx
        local c = DB()
        if c.windows then
            table.remove(c.windows, removedIdx)
            c.windowCount = #c.windows
        end
        -- Update remaining windows' idx to match their new DB position
        for i, w in ipairs(_windows) do w.idx = i end
        -- Re-key unlock anchor/size-match links for the shifted window set and refresh registrations (drops the stale highest EDM_Win slot)
        if EUI.ShiftIndexedAnchorKeys then EUI.ShiftIndexedAnchorKeys("EDM_Win", removedIdx, oldCount) end
        ns.RegisterDMUnlock()
    end

    -- The first paint of a built or re-applied window, a frame later (off the build or
    -- profile swap frame): one per frame however often it is asked for, none while parked.
    local function FirstPaint()
        W._firstPaintPending = nil
        if W._parked then return end
        W.Refresh()
        -- First install: show home page so user can pick a mode
        if not wdb.curDMType then W.ShowHome() end
    end

    -- Reapply: points this window at slot idx of the profile now active and re-reads
    -- every setting read while it was built above, leaving it as a newly built window
    -- for that slot (a profile swap keeps its windows; a parked window comes back).
    function W.Reapply(idx)
        if W._parked then
            W._parked = nil
            EUI.RegisterVisibilityUpdater(W.UpdateVisibility)
        else
            -- A fresh scan entry, as a new window gets: the cached answer is the old profile's
            EUI.UnregisterMouseoverTarget(frame)
        end
        EUI.RegisterMouseoverTarget(frame, MouseoverActive)
        W.idx = idx
        wdb = WinDB(idx)
        local c = DB()
        -- Window state, as set at the top of this function
        local dmType = wdb.curDMType or Enum.DamageMeterType.DamageDone
        if not DM_TYPE_NAMES[dmType] then dmType = Enum.DamageMeterType.DamageDone end
        W.curDMType = dmType
        W.curSession = wdb.curSession or Enum.DamageMeterSessionType.Current
        W.curSessionID = nil
        W.visibleCount = 0
        W.windowLocked = wdb.locked or false
        W.snapDisabled = wdb.snapDisabled or false
        W.sourceClass = nil
        W.cachedSources = nil
        W.stickyAtTop = false
        W.stickyGuard = false
        -- Every paint memo and the cached session: any of their inputs may differ now
        W._barCacheKey, W._stickyCacheKey, W._lastSession, W._refreshPending = nil, nil, nil, nil
        W._stickyClassCache, W._stickySpecCache, W._stickyRankCache, W._stickyNameCache = nil, nil, nil, nil
        W._timerSec, W._fitFull, W._fitAvail, W._cachedTargets = nil, nil, nil, nil
        -- A drag or resize in flight ends here
        dragging = false; dragFrame:Hide()
        W.resizing = false; resizeFrame:Hide()
        frame:SetSize(wdb.width or 300, wdb.height or 200)
        -- An unlock-anchored window waits unplaced for its anchor, as a new one does
        frame:ClearAllPoints()
        W.ApplyPosition()
        -- Home page and breakdown closed, every row empty, scrolled to the top
        W.HideHome()
        W.CloseSource()
        for i = 1, BAR_POOL_SIZE do
            local bar = W.rowPool[i]
            bar.row:Hide(); bar.classIcon:Hide()
            bar._src = nil; bar._srcGUID = nil; bar._class = nil
            bar._cachedSlot = nil; bar._cachedClass = false; bar._cachedSpecIcon = nil; bar._cachedColorClass = false
            bar._cachedSrcName = nil; bar._cachedDisplayName = nil; bar._cachedAmtText = nil
            bar._cachedRank = nil; bar._cachedThreatColor = nil
        end
        local sp = W.stickyPlayer
        sp.row:Hide(); sp.classIcon:Hide(); W.stickySep:Hide()
        if W._decorSync then ns.DMSyncRowDecor(W) end
        sp._src = nil; sp._srcGUID = nil; sp._class = nil
        viewport:SetVerticalScroll(0)
        RecalcViewport(0)
        W.srcViewport:SetVerticalScroll(0); _srcScrollMax = 0
        if homeScroll then homeScroll:SetVerticalScroll(0) end
        -- Window and breakdown background, header bar
        local bgR, bgG, bgB, bgA = c.bgR or 0, c.bgG or 0, c.bgB or 0, c.bgAlpha or 0.75
        local hdrH = GetHeaderH()
        frame._bg:ClearAllPoints()
        frame._bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -hdrH)
        frame._bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        ns.DMPaintWindowBg(frame._bg, bgR, bgG, bgB, bgA, true, c.bgTexture)
        ns.DMPaintWindowBg(W.sourceFrame._bg, bgR, bgG, bgB, bgA, nil, c.bgTexture)
        header:SetHeight(hdrH)
        local hc = c.hdrBgColor
        ns.DMPaintHeaderBg(header._hdrBg, hc and hc.r or 0x1B/255, hc and hc.g or 0x1B/255, hc and hc.b or 0x1B/255, c.hdrBgAlpha or 1)
        if not ns.DMClassicSeparator(header._bottomBorder, PhysicalPixels(1)) then
            local size = c.hdrBottomBorderSize or 0
            local color = c.hdrBottomBorderColor or {}
            header._bottomBorder:SetHeight(PhysicalPixels(size))
            header._bottomBorder:SetColorTexture(color.r or 0, color.g or 0, color.b or 0, color.a or 1)
            header._bottomBorder:SetShown(size > 0 and not ns.DMBlizz())
        end
        -- Title and timer
        local titleFS = c.hdrFontSize or 11
        SetDMFont(W.titleText, titleFS)
        W.titleText:ClearAllPoints()
        W.titleText:SetPoint("LEFT", header, "LEFT", 6 + (c.hdrTextOffX or 0), (c.hdrTextOffY or 0) + ns.DMHdrLift(c.hdrHeight))
        local tR, tG, tB
        if c.hdrTextUseAccent ~= false then tR, tG, tB = ns.DMTitleRGB()
        else local tc = c.hdrTextColor; tR = tc and tc.r or 1; tG = tc and tc.g or 1; tB = tc and tc.b or 1 end
        W.titleText:SetTextColor(tR, tG, tB, 1)
        W._fullTitle = L("Damage Done")
        W.titleText:SetText(W._fullTitle)
        SetDMFont(W.timerText, titleFS)
        W.timerText:SetText("(0:00)")
        W.timerText:SetShown(not wdb.hideTimer)
        -- Header buttons: size, glyph colour, meter type icon, close icon, lock state
        local sz = ns.DMHdrIconSize(c)
        local ir, ig, ib = GetIconColor()
        for _, btn in ipairs(W.hdrBtns) do btn:SetSize(sz, sz) end
        for _, ic in ipairs(W.hdrIcons) do
            if not ic._hdrArt then ic:SetVertexColor(ir, ig, ib, ICON_ALPHA) end
        end
        ns.DMSetTypeIcon(W._modeIcon, W.curDMType)
        local closeTex = W._closeIconTex
        if closeTex and not closeTex._hdrArt then
            closeTex:ClearAllPoints()
            closeTex:SetSize(sz + 2, sz + 2)
            closeTex:SetPoint("CENTER", W.winActionBtn, "CENTER", 0, 0)
        end
        LayoutHeaderButtons(W, c, sz)
        UpdateLockIcon()
        local a = W.isHovered and 0.3 or 0
        W.resizeGrip:SetAlpha(W.windowLocked and 0 or a)
        W.lockBtn:SetAlpha(a)
        ApplyHeaderButtonsHoverVisibility(W, c)
        -- Rows and the pinned row: borders, track, text offsets
        for i = 1, BAR_POOL_SIZE do
            local bar = W.rowPool[i]
            bar.ApplyBorder(); bar.ApplyIconBorder(); bar.ApplyBg(); bar.ApplyTextOffsets()
        end
        sp.ApplyBorder(); sp.ApplyIconBorder(); sp.ApplyBg(); sp.ApplyTextOffsets()
        W.UpdateVisibility()
        if not W._firstPaintPending then
            W._firstPaintPending = true
            C_Timer.After(0, FirstPaint)
        end
    end

    W.UpdateVisibility()

    -- Defer initial refresh off the init frame
    W._firstPaintPending = true
    C_Timer.After(0, FirstPaint)

    if cfg.hdrBottomSeparator then ns.DMApplyHeaderSeparator(W) end
    return W
end

-- A window for slot idx: a parked window brought back (W.Reapply), else a new one.
-- Slot 1 always gets a window built for it (its header carries New Window), and
-- every parked window was built for a later slot.
function ns.DMAcquireWindow(idx)
    local parked = ns._dmParked
    local w = idx ~= 1 and parked[#parked]
    if w then
        parked[#parked] = nil
        w.Reapply(idx)
        return w
    end
    return CreateDMWindow(idx)
end

I.CreateDMWindow = CreateDMWindow
I.broken = false
