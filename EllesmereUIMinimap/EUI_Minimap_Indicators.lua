if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Minimap_Indicators.lua
--
--  The custom indicator buttons, the Great Vault button with its tooltip
--  and the M+ Portal button.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIMinimap.lua or an earlier EUI_Minimap_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local EBS, GetFFD, GetCustomTooltipScale = I.EBS, I.GetFFD, I.GetCustomTooltipScale
local GetInteractableBtnSize, SetPortalFlyout = I.GetInteractableBtnSize, I.SetPortalFlyout

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local MO_Evaluate
I.moEvaluateSetters[#I.moEvaluateSetters + 1] = function(v) MO_Evaluate = v end

-------------------------------------------------------------------------------
--  Minimap Indicator Buttons (custom replacements for Blizzard's reparented frames)
--  Our own Button with black bg, icon and click handler: no Blizzard frame
--  reparenting = no taint, no layout fights.
-------------------------------------------------------------------------------
local _customIndicators = {}  -- { tracking, calendar, mail, crafting }

-- Native atlas aspect ratios (width / height) and per-icon scale multipliers
local INDICATOR_ATLAS_RATIO = {
    ["UI-HUD-Minimap-Tracking-Up"]           = 15 / 14,
    ["UI-HUD-Minimap-Tracking-Mouseover"]    = 15 / 14,
    ["UI-HUD-Minimap-Tracking-Down"]         = 16 / 15,
    ["UI-HUD-Minimap-Mail-Up"]               = 19.5 / 15,
    ["UI-HUD-Minimap-Mail-Mouseover"]        = 19.5 / 15,
    ["UI-HUD-Minimap-CraftingOrder-Up-2x"]   = 17 / 16,
    ["UI-HUD-Minimap-CraftingOrder-Over-2x"] = 17 / 16,
    ["UI-HUD-Minimap-CraftingOrder-Down-2x"] = 17 / 16,
}
local INDICATOR_ATLAS_SCALE = {}
-- Calendar atlases: all 31 days share the same ratio/scale
for day = 1, 31 do
    local prefix = "UI-HUD-Calendar-" .. day
    INDICATOR_ATLAS_RATIO[prefix .. "-Up"]        = 21 / 19
    INDICATOR_ATLAS_RATIO[prefix .. "-Mouseover"] = 21 / 19
    INDICATOR_ATLAS_RATIO[prefix .. "-Down"]      = 21 / 19
    INDICATOR_ATLAS_SCALE[prefix .. "-Up"]        = 1.25
    INDICATOR_ATLAS_SCALE[prefix .. "-Mouseover"] = 1.25
    INDICATOR_ATLAS_SCALE[prefix .. "-Down"]      = 1.25
end
-- Per-icon pixel offset from center { x, y }
local INDICATOR_ATLAS_OFFSET = {
    _gameTime = { 2, -2 },
    _mail     = { 1, -1 },
}

local function CreateIndicatorBtn(name, parent, upAtlas, overAtlas, downAtlas, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(GetInteractableBtnSize(), GetInteractableBtnSize())
    btn:SetFrameLevel(parent:GetFrameLevel() + 20)
    btn:EnableMouse(true)

    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)
    btn._bg = bg

    -- Icon sized to preserve the atlas aspect ratio within the button.
    local icon = btn:CreateTexture(nil, "ARTWORK")
    local inset = 3
    local ratio = upAtlas and INDICATOR_ATLAS_RATIO[upAtlas]
    if ratio then
        local btnSz = GetInteractableBtnSize()
        local avail = btnSz - inset * 2
        local scale = INDICATOR_ATLAS_SCALE[upAtlas] or 1
        local iconW, iconH
        if ratio >= 1 then
            iconW = avail * scale
            iconH = (avail / ratio) * scale
        else
            iconH = avail * scale
            iconW = (avail * ratio) * scale
        end
        icon:SetSize(iconW, iconH)
        local off = INDICATOR_ATLAS_OFFSET[name]
        icon:SetPoint("CENTER", btn, "CENTER", off and off[1] or 0, off and off[2] or 0)
    else
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
    end
    if upAtlas then icon:SetAtlas(upAtlas) end
    btn._icon = icon
    btn._upAtlas = upAtlas
    btn._overAtlas = overAtlas
    btn._downAtlas = downAtlas
    btn._indicatorKey = name

    btn:SetScript("OnEnter", function(self)
        if self._overAtlas and self._icon then self._icon:SetAtlas(self._overAtlas) end
    end)
    btn:SetScript("OnLeave", function(self)
        if self._upAtlas and self._icon then self._icon:SetAtlas(self._upAtlas) end
    end)
    btn:SetScript("OnMouseDown", function(self)
        if self._downAtlas and self._icon then self._icon:SetAtlas(self._downAtlas) end
    end)
    btn:SetScript("OnMouseUp", function(self)
        local over = self:IsMouseOver()
        local atlas = over and self._overAtlas or self._upAtlas
        if atlas and self._icon then self._icon:SetAtlas(atlas) end
    end)

    if onClick then
        btn:SetScript("OnClick", function(self)
            if GetFFD(self).freeMoveJustDragged then return end
            onClick(self)
        end)
    end

    return btn
end

-- Great Vault button: top of the ungrouped stack above the flyout toggle; a single "whole" atlas scaled to fit.
local GREAT_VAULT_WHOLE_ATLAS = "greatVault-whole-normal"

local function GetOrderedWeeklyActivities(activityType)
    if not C_WeeklyRewards or not C_WeeklyRewards.GetActivities then return nil end

    local activities = C_WeeklyRewards.GetActivities(activityType)
    if type(activities) ~= "table" or #activities == 0 then
        return nil
    end

    local ordered = {}
    for i = 1, #activities do
        ordered[i] = activities[i]
    end

    table.sort(ordered, function(a, b)
        local aIndex = a and a.index or 0
        local bIndex = b and b.index or 0
        if aIndex == bIndex then
            return (a and a.threshold or 0) < (b and b.threshold or 0)
        end
        return aIndex < bIndex
    end)

    return ordered
end

local function GetVaultTokenColor(state)
    if state == "done" then
        return 0.176, 0.796, 0.349
    elseif state == "partial" then
        return 0.812, 0.592, 0.212
    end

    return 0.58, 0.58, 0.58
end

-- Build vault row data: { label, isRaid, tokens = { {text, state}, ... } }
local function BuildVaultRowData(label, activityType, isRaid)
    local activities = GetOrderedWeeklyActivities(activityType)
    local tokens = {}
    for i = 1, 3 do
        local info = activities and activities[i]
        if not info then
            tokens[i] = { text = "-", state = "empty" }
        else
            local progress = math.max(0, tonumber(info.progress) or 0)
            local threshold = math.max(0, tonumber(info.threshold) or 0)
            local level = math.max(0, tonumber(info.level) or 0)
            if threshold <= 0 then
                tokens[i] = { text = "-", state = "empty" }
            elseif progress >= threshold then
                if isRaid then
                    tokens[i] = { text = ("%d/%d"):format(progress, threshold), state = "done" }
                elseif level > 0 then
                    tokens[i] = { text = "+" .. level, state = "done" }
                else
                    tokens[i] = { text = ("%d/%d"):format(progress, threshold), state = "done" }
                end
            else
                tokens[i] = { text = ("%d/%d"):format(progress, threshold), state = progress > 0 and "partial" or "empty" }
            end
        end
    end
    return { label = label, tokens = tokens }
end

-- Custom multi-column vault tooltip (pixel-aligned columns via FontStrings)
local _vaultTT
local _vaultTTRows = {}  -- [row][col] = FontString
local VAULT_COL_GAP = 8
local VAULT_ROW_H = 14
local VAULT_PAD = 6

local function GetVaultTooltip()
    if _vaultTT then return _vaultTT end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.90)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:Hide()

    -- Fade animations (matches ShowWidgetTooltip/HideWidgetTooltip)
    local fadeInAG = f:CreateAnimationGroup()
    local fadeIn = fadeInAG:CreateAnimation("Alpha")
    fadeIn:SetDuration(0.25); fadeIn:SetSmoothing("OUT")
    fadeInAG:SetScript("OnFinished", function() f:SetAlpha(1) end)
    f._fadeInAG = fadeInAG; f._fadeIn = fadeIn

    local fadeOutAG = f:CreateAnimationGroup()
    local fadeOut = fadeOutAG:CreateAnimation("Alpha")
    fadeOut:SetDuration(0.25); fadeOut:SetSmoothing("IN")
    fadeOutAG:SetScript("OnFinished", function() f:SetAlpha(0); f:Hide() end)
    f._fadeOutAG = fadeOutAG; f._fadeOut = fadeOut

    -- Title row (font set at show-time)
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "")  -- placeholder, updated on show
    title:SetTextColor(0.80, 0.80, 0.80, 1)
    title:SetPoint("TOP", f, "TOP", 0, -VAULT_PAD)
    title:SetText(EllesmereUI.L("Great Vault"))
    f._title = title

    -- 3 data rows x 4 columns (label + 3 tokens)
    for row = 1, 3 do
        _vaultTTRows[row] = {}
        for col = 0, 3 do
            local fs = f:CreateFontString(nil, "OVERLAY")
            fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "")  -- placeholder, updated on show
            fs:SetJustifyH("LEFT")
            _vaultTTRows[row][col] = fs
        end
    end

    _vaultTT = f
    return f
end

local function ShowVaultTooltip(anchor)
    local raidType = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Raid) or 3
    local dungeonType = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Activities) or 1
    local worldType = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.World) or 6

    local rows = {
        BuildVaultRowData(EllesmereUI.L("Raids"), raidType, true),
        BuildVaultRowData(EllesmereUI.L("Mythic+"), dungeonType, false),
        BuildVaultRowData(EllesmereUI.L("World"), worldType, false),
    }

    local tt = GetVaultTooltip()
    -- Scale the whole tooltip to the user's Custom Tooltip Size (re-applied each show).
    tt:SetScale(GetCustomTooltipScale())

    local fontPath = (EllesmereUI.GetFontPath("minimap")) or "Fonts\\FRIZQT__.TTF"
    local fontFlags = (EllesmereUI.GetFontOutlineFlag("minimap")) or ""
    tt._title:SetFont(fontPath, 11, fontFlags)
    for r = 1, 3 do
        _vaultTTRows[r][0]:SetFont(fontPath, 11, fontFlags)
        for c = 1, 3 do
            _vaultTTRows[r][c]:SetFont(fontPath, 10, fontFlags)
        end
    end

    local colWidths = { 0, 0, 0, 0 }
    for r = 1, 3 do
        local rd = rows[r]
        local labelFS = _vaultTTRows[r][0]
        labelFS:SetText(rd.label)
        labelFS:SetTextColor(0.812, 0.592, 0.212, 1)
        local w = labelFS:GetStringWidth() or 0
        if w > colWidths[1] then colWidths[1] = w end

        for c = 1, 3 do
            local tk = rd.tokens[c]
            local fs = _vaultTTRows[r][c]
            fs:SetText(tk.text)
            local tr, tg, tb = GetVaultTokenColor(tk.state)
            fs:SetTextColor(tr, tg, tb, 1)
            local tw = fs:GetStringWidth() or 0
            if tw > colWidths[c + 1] then colWidths[c + 1] = tw end
        end
    end

    local titleTop = VAULT_PAD + (tt._title:GetStringHeight() or 14) + 4
    local colX = { VAULT_PAD }
    for c = 2, 4 do
        colX[c] = colX[c - 1] + colWidths[c - 1] + VAULT_COL_GAP
    end
    local totalW = colX[4] + colWidths[4] + VAULT_PAD

    for r = 1, 3 do
        local y = -(titleTop + (r - 1) * VAULT_ROW_H)
        for c = 0, 3 do
            _vaultTTRows[r][c]:ClearAllPoints()
            _vaultTTRows[r][c]:SetPoint("TOPLEFT", tt, "TOPLEFT", colX[c + 1], y)
        end
    end

    local totalH = titleTop + 3 * VAULT_ROW_H + VAULT_PAD
    tt:SetSize(totalW, totalH)
    tt:ClearAllPoints()
    local gpt = EBS._Grow.center[EBS._Grow.Dir()] or EBS._Grow.center.left
    tt:SetPoint(gpt[1], anchor, gpt[2], gpt[3], gpt[4])

    tt._fadeOutAG:Stop()
    tt._fadeInAG:Stop()
    tt:SetAlpha(0)
    tt:Show()
    tt._fadeIn:SetFromAlpha(0)
    tt._fadeIn:SetToAlpha(1)
    tt._fadeInAG:Play()
end

local function HideVaultTooltip()
    if not _vaultTT or not _vaultTT:IsShown() then return end
    _vaultTT._fadeInAG:Stop()
    _vaultTT._fadeOutAG:Stop()
    _vaultTT._fadeOut:SetFromAlpha(_vaultTT:GetAlpha())
    _vaultTT._fadeOut:SetToAlpha(0)
    _vaultTT._fadeOutAG:Play()
end

local function SizeGreatVaultBtn(btn, showBg)
    local btnSz = GetInteractableBtnSize()
    btn:SetSize(btnSz, btnSz)
    if btn._bg then btn._bg:SetShown(showBg ~= false) end
    local inset = 3
    local avail = btnSz - inset * 2
    -- Whole is 105x108: height is the limiting dimension. Fit by height.
    local wholeH = avail
    local wholeW = wholeH * (105 / 108)
    btn._whole:SetSize(wholeW, wholeH)
    btn._whole:ClearAllPoints()
    btn._whole:SetPoint("CENTER", btn, "CENTER", 0, 0)
end

local function CreateGreatVaultBtn(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(GetInteractableBtnSize(), GetInteractableBtnSize())
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)
    btn:EnableMouse(true)

    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)
    btn._bg = bg

    local whole = btn:CreateTexture(nil, "ARTWORK")
    whole:SetAtlas(GREAT_VAULT_WHOLE_ATLAS)
    btn._whole = whole

    SizeGreatVaultBtn(btn)

    btn:SetScript("OnEnter", function(self)
        self._whole:SetVertexColor(1, 1, 1, 1)
        ShowVaultTooltip(self)
    end)
    btn:SetScript("OnLeave", function(self)
        self._whole:SetVertexColor(0.85, 0.85, 0.85, 1)
        HideVaultTooltip()
        EllesmereUI.HideWidgetTooltip()
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._whole:SetVertexColor(0.7, 0.7, 0.7, 1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        local over = self:IsMouseOver()
        local v = over and 1 or 0.85
        self._whole:SetVertexColor(v, v, v, 1)
    end)
    btn:SetScript("OnClick", function(self)
        if GetFFD(self).freeMoveJustDragged then return end
        EllesmereUI.ToggleGreatVault()
    end)

    -- Resting tint matches OnLeave state
    whole:SetVertexColor(0.85, 0.85, 0.85, 1)

    btn._indicatorKey = "_greatVault"

    return btn
end

-------------------------------------------------------------------------------
-- M+ Portal button. Identical flyout as Chat sidebar but anchored to minimap.
-------------------------------------------------------------------------------
local _portalFlyout
I.portalFlyoutSetters[#I.portalFlyoutSetters + 1] = function(v) _portalFlyout = v end

local function ToggleMinimapPortalFlyout(anchorBtn)
    if InCombatLockdown() then return end
    if not _portalFlyout then
        -- WoW Forever: the Teleport Menu (Forever Essentials) instead of the M+ portals.
        local Create = EllesmereUI.IS_FOREVER and EllesmereUI._ForeverTeleport.Create or EllesmereUI.CreatePortalFlyout
        SetPortalFlyout(Create({
            name = "EUIMinimap", bg = { 0.04, 0.04, 0.06 }, clamp = true, unitEvents = true,
            labelFont = (EllesmereUI.GetFontPath("minimap")) or "Fonts\\FRIZQT__.TTF",
            labelFlags = "OUTLINE",
        }))
        -- Keep the mouseover stack shown while open; re-evaluate on close so it can hide.
        _portalFlyout:HookScript("OnShow", function() if MO_Evaluate then MO_Evaluate() end end)
        _portalFlyout:HookScript("OnHide", function() if MO_Evaluate then MO_Evaluate() end end)
    end
    local flyout = _portalFlyout
    -- Scale to the user's M+ Portals Scale (safe with secure children: combat
    -- early-returns above). Set before the anchor math so GetEffectiveScale reflects it.
    local _mp = EBS.db and EBS.db.profile.minimap
    flyout:SetScale(_mp and _mp.extraFlyoutScale or 1.0)
    if flyout:IsShown() then
        flyout:Hide()
    else
        -- Open in the Grow Tooltip/Popup direction. Anchor through UIParent in
        -- effective-scale space so the flyout's own scale never shifts it off the
        -- button. 4px gap on the facing edge; the other axis keeps its top/left edge.
        local bs = anchorBtn:GetEffectiveScale()
        local fs = flyout:GetEffectiveScale()
        local bTop    = anchorBtn:GetTop()    * bs
        local bBottom = anchorBtn:GetBottom() * bs
        local bLeft   = anchorBtn:GetLeft()   * bs
        local bRight  = anchorBtn:GetRight()  * bs
        local dir = EBS._Grow.Dir()
        flyout:ClearAllPoints()
        if dir == "right" then
            flyout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (bRight + 4) / fs, (bTop + 4) / fs)
        elseif dir == "up" then
            flyout:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fs, (bTop + 4) / fs)
        elseif dir == "down" then
            flyout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fs, (bBottom - 4) / fs)
        else
            flyout:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fs, (bTop + 4) / fs)
        end
        flyout:Show()
    end
end

local function SizePortalBtn(btn, showBg)
    local btnSz = GetInteractableBtnSize()
    btn:SetSize(btnSz, btnSz)
    if btn._bg then btn._bg:SetShown(showBg ~= false) end
    local inset = 4
    local avail = btnSz - inset * 2
    btn._icon:SetSize(avail, avail)
    btn._icon:ClearAllPoints()
    btn._icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
end

local function CreatePortalBtn(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(GetInteractableBtnSize(), GetInteractableBtnSize())
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)
    btn:EnableMouse(true)

    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)
    btn._bg = bg

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(EllesmereUI.IS_FOREVER and 134414 or "Interface\\Icons\\Spell_Arcane_PortalDalaran")
    icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
    btn._icon = icon

    SizePortalBtn(btn)

    btn:SetScript("OnEnter", function(self)
        self._icon:SetVertexColor(1, 1, 1, 1)
        if _portalFlyout and _portalFlyout:IsShown() then return end
        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.IS_FOREVER and "Teleport Menu" or "M+ Portals", { anchor = EBS._Grow.TT(), scale = GetCustomTooltipScale() })
    end)
    btn:SetScript("OnLeave", function(self)
        self._icon:SetVertexColor(0.85, 0.85, 0.85, 1)
        EllesmereUI.HideWidgetTooltip()
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._icon:SetVertexColor(0.7, 0.7, 0.7, 1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        local over = self:IsMouseOver()
        local v = over and 1 or 0.85
        self._icon:SetVertexColor(v, v, v, 1)
    end)
    btn:SetScript("OnClick", function(self)
        if GetFFD(self).freeMoveJustDragged then return end
        EllesmereUI.HideWidgetTooltip(true)
        ToggleMinimapPortalFlyout(self)
    end)

    icon:SetVertexColor(0.85, 0.85, 0.85, 1)

    btn._indicatorKey = "_portals"

    return btn
end

I._customIndicators, I.CreateGreatVaultBtn = _customIndicators, CreateGreatVaultBtn
I.CreateIndicatorBtn, I.CreatePortalBtn = CreateIndicatorBtn, CreatePortalBtn
I.HideVaultTooltip, I.INDICATOR_ATLAS_OFFSET = HideVaultTooltip, INDICATOR_ATLAS_OFFSET
I.INDICATOR_ATLAS_RATIO, I.INDICATOR_ATLAS_SCALE = INDICATOR_ATLAS_RATIO, INDICATOR_ATLAS_SCALE
I.ShowVaultTooltip, I.SizeGreatVaultBtn = ShowVaultTooltip, SizeGreatVaultBtn
I.SizePortalBtn = SizePortalBtn
I.broken = false
