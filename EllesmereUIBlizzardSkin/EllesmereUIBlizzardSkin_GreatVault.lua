if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIBlizzardSkin_GreatVault.lua
--  Great Vault reskin.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local LOCK_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-------------------------------------------------------------------------------
--  Config / Theme Access
-------------------------------------------------------------------------------
local DEFAULT_RESKIN = {
    BG_R = 0.03, BG_G = 0.045, BG_B = 0.05,
    QT_ALPHA = 0.96,
    BRD_ALPHA = 0.4,
}

local STYLE = {
    paddings = {
        inset = 3,
        activityCard = 4,
        concessionCard = 6,
        icon = 2,
    },
    sizes = {
        itemName = 10,
        threshold = 10,
        progress = 11,
        overlayTitle = 18,
        overlayText = 11,
        warningText = 10,
        headerTitle = 14,
        progressBarHeight = 3,
        lockIcon = 28,
    },
    offsets = {
        progressBar = { x = 0, y = 0 },
        lockIcon = { x = 0, y = -7 },
        selectRewardButton = { x = 0, y = -4 },
    },
    alpha = {
        selectedGlow = 0.08,
        selectedBorder = 0.75,
        activityUnlockedBorder = 0.45,
        activityLockedBorder = 0.15,
        overlayText = 0.9,
        warningText = 0.85,
        progressRewardFill = 0.95,
        progressUnlockedFill = 0.7,
        progressRewardTrack = 0.16,
        progressUnlockedTrack = 0.12,
        progressLockedTrack = 0.10,
        thresholdUnlocked = 0.92,
        thresholdLocked = 0.65,
        progressUnlockedText = 0.9,
        rewardsLabel = 0.75,
        itemName = 0.95,
    },
    colors = {
        white = { r = 1, g = 1, b = 1 },
        itemSlotBackground = { r = 0.5, g = 0.5, b = 0.5, a = 0.7 },
        itemDefaultBorder = { r = 0.4, g = 0.4, b = 0.4, a = 1 },
        progressInactive = { r = 0.55, g = 0.55, b = 0.55, a = 1 },
        complete = { r = 0.176, g = 0.796, b = 0.349 },
        locked = { r = 0.812, g = 0.592, b = 0.212, a = 1 },
        typeName = { r = 0.812, g = 0.592, b = 0.212 },
    },
}

local function IsGreatVaultSkinEnabled()
    -- Independent toggle, default on (not tied to any master reskin setting).
    return not EllesmereUIDB or EllesmereUIDB.reskinGreatVault ~= false
end

local function BuildThemeContext()
    local r, g, b = EllesmereUI.GetAccentColor()
    return {
        accent = { r = r, g = g, b = b },
        borderAPI = EllesmereUI.PP or EllesmereUI.PanelPP,
        fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("blizzardSkin") or STANDARD_TEXT_FONT,
        reskin = EllesmereUI.RESKIN or DEFAULT_RESKIN,
    }
end

-------------------------------------------------------------------------------
--  Low-Level Skin Primitives
-------------------------------------------------------------------------------
local function ApplyColorTexture(texture, color, alpha)
    if not texture or not color then return end
    texture:SetColorTexture(color.r or 1, color.g or 1, color.b or 1, alpha or color.a or 1)
end

local function SetBorderColor(frame, theme, color, alpha)
    local pp = theme and theme.borderAPI
    if pp and pp.SetBorderColor and frame and frame._ppBorders and color then
        pp.SetBorderColor(frame, color.r or 1, color.g or 1, color.b or 1, alpha or color.a or 1)
    end
end

local function StripTexture(texture)
    if texture and texture.SetAlpha and not texture._euiOwned then
        texture:SetAlpha(0)
    end
end

local function SuppressTexture(texture)
    if not texture or texture._euiOwned then return end
    local d = GetFFD(texture)
    if d.suppressed then return end
    d.suppressed = true

    if texture.Hide then texture:Hide() end
    if texture.SetAlpha then texture:SetAlpha(0) end

    if texture.Show then
        hooksecurefunc(texture, "Show", function(self)
            self:Hide()
            self:SetAlpha(0)
        end)
    end
end

local function ApplyFont(fontString, theme, size, r, g, b, a, flags)
    if not fontString then return end

    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fontString, true) end
    fontString:SetFont((theme and theme.fontPath) or STANDARD_TEXT_FONT, size, flags or "")
    fontString:SetTextColor(r or 1, g or 1, b or 1, a or 1)
end

local function EnsureBackdrop(frame, theme, alpha)
    if not frame then return end

    local rs = theme.reskin
    local d = GetFFD(frame)
    if not d.bg then
        d.bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        d.bg:SetAllPoints()
        d.bg._euiOwned = true
    end

    d.bg:SetColorTexture(rs.BG_R, rs.BG_G, rs.BG_B, alpha or rs.QT_ALPHA)
    d.bg:Show()

    local pp = theme.borderAPI
    if pp and pp.CreateBorder and not d.borderCreated then
        d.borderCreated = true
        pp.CreateBorder(frame, 1, 1, 1, rs.BRD_ALPHA, 1, "OVERLAY", 7)
    end
end

local function EnsureInsetBackdrop(frame, theme, padding)
    if not frame then return nil end

    local pad = padding or STYLE.paddings.inset
    local pp = theme.borderAPI
    local d = GetFFD(frame)

    if not d.skinFrame then
        local skinFrame = CreateFrame("Frame", nil, frame)
        d.skinFrame = skinFrame
    end

    local skinFrame = d.skinFrame
    skinFrame:ClearAllPoints()
    skinFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
    skinFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pad, pad)
    skinFrame:SetFrameLevel(math.max(1, frame:GetFrameLevel()))

    if pp and pp.CreateBorder and not skinFrame._euiBorderCreated then
        skinFrame._euiBorderCreated = true
        pp.CreateBorder(skinFrame, 1, 1, 1, theme.reskin.BRD_ALPHA, 1, "OVERLAY", 7)
    end

    skinFrame:Show()
    return skinFrame
end

local function EnsureSelectionGlow(frame, anchorFrame)
    if not frame then return nil end

    local d = GetFFD(frame)
    if not d.selectedGlow then
        local glow = frame:CreateTexture(nil, "ARTWORK", nil, -5)
        glow._euiOwned = true
        glow:Hide()
        d.selectedGlow = glow
    end

    local glow = d.selectedGlow
    local anchor = anchorFrame or frame
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    return glow
end

local function EnsureProgressBar(frame, anchorFrame)
    if not frame then return nil end

    local d = GetFFD(frame)
    if not d.progressBarFrame then
        local barFrame = CreateFrame("Frame", nil, frame)
        local track = barFrame:CreateTexture(nil, "BACKGROUND", nil, -4)
        local fill = barFrame:CreateTexture(nil, "ARTWORK", nil, -3)

        track:SetAllPoints()
        track._euiOwned = true
        fill:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
        fill:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
        fill._euiOwned = true

        barFrame._euiTrack = track
        barFrame._euiFill = fill
        barFrame:SetScript("OnSizeChanged", function(self)
            if self._euiFill then
                local ratio = self._euiRatio or 0
                local width = math.max(0, self:GetWidth() * ratio)
                self._euiFill:SetWidth(width)
                self._euiFill:SetShown(width > 0)
            end
        end)

        d.progressBarFrame = barFrame
    end

    local barFrame = d.progressBarFrame
    local anchor = anchorFrame or frame
    local pp = EllesmereUI.PP or EllesmereUI.PanelPP
    local px = pp and pp.Scale and pp.Scale(1) or 1
    barFrame:ClearAllPoints()
    barFrame:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", px, px)
    barFrame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -px, px)
    barFrame:SetHeight(STYLE.sizes.progressBarHeight)
    return barFrame
end

local function EnsureLockIcon(frame, anchorFrame)
    if not frame then return nil end

    local d = GetFFD(frame)
    if not d.lockIcon then
        local lock = frame:CreateTexture(nil, "OVERLAY", nil, 3)
        lock:SetTexture(LOCK_TEXTURE)
        lock._euiOwned = true
        d.lockIcon = lock
    end

    local lock = d.lockIcon
    local anchor = anchorFrame or frame
    lock:SetSize(STYLE.sizes.lockIcon, STYLE.sizes.lockIcon)
    lock:ClearAllPoints()
    lock:SetPoint("CENTER", anchor, "CENTER", STYLE.offsets.lockIcon.x, STYLE.offsets.lockIcon.y)
    lock:SetVertexColor(1, 1, 1, 1)
    return lock
end

local function ResolveWeeklyRewardItemLink(activityFrame, itemFrame)
    if itemFrame then
        if itemFrame.itemLink then
            return itemFrame.itemLink
        end
        if itemFrame.itemHyperlink then
            return itemFrame.itemHyperlink
        end
        if itemFrame.itemDBID and C_WeeklyRewards and C_WeeklyRewards.GetItemHyperlink then
            local itemLink = C_WeeklyRewards.GetItemHyperlink(itemFrame.itemDBID)
            if itemLink then
                return itemLink
            end
        end
    end

    local info = activityFrame and activityFrame.info
    local rewards = info and info.rewards
    if type(rewards) ~= "table" then
        return nil
    end

    for _, reward in ipairs(rewards) do
        if reward and reward.itemDBID and C_WeeklyRewards and C_WeeklyRewards.GetItemHyperlink then
            local itemLink = C_WeeklyRewards.GetItemHyperlink(reward.itemDBID)
            if itemLink then
                return itemLink
            end
        end
    end

    return nil
end

local function ResolveItemBorderColor(itemLink)
    if not itemLink then
        return STYLE.colors.itemDefaultBorder
    end

    local quality
    if C_Item and C_Item.GetItemQualityByID then
        quality = C_Item.GetItemQualityByID(itemLink)
    end
    if not quality then
        local _, _, itemQuality = GetItemInfo(itemLink)
        quality = itemQuality
    end

    if quality then
        local r, g, b
        if C_Item and C_Item.GetItemQualityColor then
            r, g, b = C_Item.GetItemQualityColor(quality)
        elseif GetItemQualityColor then
            r, g, b = GetItemQualityColor(quality)
        end
        if r and g and b then
            return { r = r, g = g, b = b, a = 1 }
        end
    end

    return STYLE.colors.itemDefaultBorder
end

local function EnsureIconChrome(itemFrame, theme, borderColor)
    if not itemFrame or not itemFrame.Icon then return end

    local icon = itemFrame.Icon
    local pad = STYLE.paddings.icon
    local pp = theme.borderAPI
    local d = GetFFD(itemFrame)

    if not d.iconBg then
        local bg = itemFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
        bg._euiOwned = true
        d.iconBg = bg
    end

    d.iconBg:ClearAllPoints()
    d.iconBg:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    d.iconBg:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    ApplyColorTexture(d.iconBg, STYLE.colors.itemSlotBackground)

    if not d.iconBorder then
        local borderHost = CreateFrame("Frame", nil, itemFrame)
        d.iconBorder = borderHost

        if pp and pp.CreateBorder then
            pp.CreateBorder(borderHost, 1, 1, 1, 1, 2, "OVERLAY", 7)
        end
    end

    local borderHost = d.iconBorder
    borderHost:ClearAllPoints()
    borderHost:SetPoint("TOPLEFT", icon, "TOPLEFT", -pad, pad)
    borderHost:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", pad, -pad)
    borderHost:SetFrameLevel(itemFrame:GetFrameLevel() + 1)
    SetBorderColor(borderHost, theme, borderColor or STYLE.colors.itemDefaultBorder, 1)

    return borderHost
end

local function SuppressItemButtonChrome(itemFrame)
    if not itemFrame then return end

    for _, key in ipairs({
        "Border", "Background", "IconBorder", "IconOverlay", "IconOverlay2",
        "SlotBackground", "Highlight", "Glow", "NormalTexture", "PushedTexture",
    }) do
        SuppressTexture(itemFrame[key])
    end

    if itemFrame.GetNormalTexture then
        SuppressTexture(itemFrame:GetNormalTexture())
    end
    if itemFrame.GetPushedTexture then
        SuppressTexture(itemFrame:GetPushedTexture())
    end
    if itemFrame.GetHighlightTexture then
        SuppressTexture(itemFrame:GetHighlightTexture())
    end

    for i = 1, select("#", itemFrame:GetRegions()) do
        local region = select(i, itemFrame:GetRegions())
        if region and region:IsObjectType("Texture") and region ~= itemFrame.Icon and not region._euiOwned then
            SuppressTexture(region)
        end
    end
end

local function ApplyStoredAnchorOffset(frame, cacheKey, offsetX, offsetY)
    if not frame then return end

    local d = GetFFD(frame)
    local appliedOffsetKey = cacheKey .. "AppliedOffset"
    local appliedOffset = d[appliedOffsetKey] or { x = 0, y = 0 }
    local cachedPoints = {}

    for i = 1, frame:GetNumPoints() do
        local point, relativeTo, relativePoint, xOfs, yOfs = frame:GetPoint(i)
        cachedPoints[i] = {
            point = point,
            relativeTo = relativeTo,
            relativePoint = relativePoint,
            x = (xOfs or 0) - appliedOffset.x,
            y = (yOfs or 0) - appliedOffset.y,
        }
    end

    d[cacheKey] = cachedPoints
    d[appliedOffsetKey] = { x = offsetX or 0, y = offsetY or 0 }

    if #cachedPoints == 0 then return end

    frame:ClearAllPoints()
    for _, anchor in ipairs(cachedPoints) do
        frame:SetPoint(
            anchor.point,
            anchor.relativeTo,
            anchor.relativePoint,
            (anchor.x or 0) + (offsetX or 0),
            (anchor.y or 0) + (offsetY or 0)
        )
    end
end

-------------------------------------------------------------------------------
--  Component Stylers
-------------------------------------------------------------------------------
local function RefreshButtonState(button)
    if not button then return end
    -- Engine button treatment: flat theme block, 1px border, white hover, and
    -- a label that mirrors the enabled/disabled state. Idempotent, so calling
    -- it from every refresh pass is free after the first.
    local WSkin = ns.WSkin
    if not WSkin or not WSkin.Button then return end
    WSkin.Button(button)
    WSkin.StateButtonLabel(button)
    -- Fully opaque fill: the engine block carries the theme backdrop's
    -- translucency, which reads washed out over the vault scene.
    local d = WSkin.GetFFD and WSkin.GetFFD(button)
    local theme = WSkin.Theme
    if d and d.bg and theme then
        d.bg:SetColorTexture(theme.bgR or 0, theme.bgG or 0, theme.bgB or 0, 1)
    end
end

local function RefreshTypeFrameState(frame, theme)
    if not frame then return end
    if frame.Name then
        local c = STYLE.colors.typeName
        frame.Name:SetTextColor(c.r, c.g, c.b, 1)

        local d = GetFFD(frame)
        if not d.nameRaised then
            d.nameRaised = true
            local raiseFrame = CreateFrame("Frame", nil, frame)
            raiseFrame:SetAllPoints()
            raiseFrame:SetFrameLevel(frame:GetFrameLevel() + 20)
            frame.Name:SetParent(raiseFrame)
        end
    end
end

local function RefreshActivityItemState(itemFrame, activityFrame, theme)
    if not itemFrame then return end

    SuppressItemButtonChrome(itemFrame)

    if itemFrame.Icon then
        itemFrame.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end

    local itemLink = ResolveWeeklyRewardItemLink(activityFrame, itemFrame)
    local borderColor = ResolveItemBorderColor(itemLink)
    EnsureIconChrome(itemFrame, theme, borderColor)

    if itemFrame.Name then
        ApplyFont(itemFrame.Name, theme, STYLE.sizes.itemName, 1, 1, 1, STYLE.alpha.itemName)
    end
end

local function GetProgressTextColor(progress, threshold)
    if not progress or not threshold or threshold <= 0 or progress <= 0 then
        return STYLE.colors.progressInactive
    end
    return STYLE.colors.locked
end

local function GetActivityState(frame, selectedActivity)
    local hasRewards = frame and frame.hasRewards or false
    local progress = frame and frame.info and frame.info.progress or 0
    local threshold = frame and frame.info and frame.info.threshold or 0
    local isComplete = hasRewards or (threshold > 0 and progress >= threshold)

    return {
        hasRewards = hasRewards,
        isSelected = selectedActivity and selectedActivity == frame and hasRewards or false,
        isComplete = isComplete,
        progress = progress,
        threshold = threshold,
        ratio = (threshold and threshold > 0) and (progress / threshold) or 0,
        progressColor = GetProgressTextColor(progress, threshold),
    }
end

local function SetActivityProgressBar(frame, ratio, color, alpha, trackAlpha)
    local d = GetFFD(frame)
    if not frame or not d.progressBarFrame then return end

    local barFrame = d.progressBarFrame
    local clampedRatio = math.max(0, math.min(1, ratio or 0))
    barFrame._euiRatio = clampedRatio

    if barFrame._euiTrack then
        barFrame._euiTrack:SetColorTexture(1, 1, 1, trackAlpha or STYLE.alpha.progressLockedTrack)
    end

    if barFrame._euiFill then
        ApplyColorTexture(barFrame._euiFill, color or STYLE.colors.white, alpha or 1)
        local width = math.max(0, barFrame:GetWidth() * clampedRatio)
        barFrame._euiFill:SetWidth(width)
        barFrame._euiFill:SetShown(width > 0)
    end
end

local function RefreshSelectableCardState(theme, skinFrame, glow, state)
    if glow then
        ApplyColorTexture(glow, theme.accent, STYLE.alpha.selectedGlow)
        glow:SetShown(state.isSelected and true or false)
    end

    if not skinFrame then return end

    if state.isSelected then
        SetBorderColor(skinFrame, theme, theme.accent, STYLE.alpha.selectedBorder)
    else
        SetBorderColor(skinFrame, theme, state.borderColor or STYLE.colors.white, state.borderAlpha)
    end
end

local function RefreshActivityVisualState(frame, selectedActivity, theme)
    if not frame then return end

    StripTexture(frame.Background)
    if frame.Border then
        local bd = GetFFD(frame.Border)
        if not bd.suppressed then
            bd.suppressed = true
            frame.Border:SetAlpha(0)
            frame.Border:Hide()
            hooksecurefunc(frame.Border, "Show", function(self)
                self:Hide()
                self:SetAlpha(0)
            end)
        else
            frame.Border:SetAlpha(0)
            frame.Border:Hide()
        end
    end
    StripTexture(frame.SelectedTexture)
    StripTexture(frame.ItemGlow)
    if frame.UncollectedGlow then
        local ud = GetFFD(frame.UncollectedGlow)
        if not ud.hidden then
            ud.hidden = true
            local hiddenParent = CreateFrame("Frame")
            hiddenParent:Hide()
            frame.UncollectedGlow:SetParent(hiddenParent)
        end
    end
    if frame.UnselectedFrame then
        frame.UnselectedFrame:SetAlpha(0)
    end

    local skinFrame = EnsureInsetBackdrop(frame, theme, STYLE.paddings.activityCard)
    local glow = EnsureSelectionGlow(frame, skinFrame)
    EnsureProgressBar(frame, skinFrame)
    EnsureLockIcon(frame, skinFrame)

    local activityState = GetActivityState(frame, selectedActivity)
    local complete = STYLE.colors.complete

    local borderColor, borderAlpha
    if activityState.isComplete then
        borderColor = complete
        borderAlpha = STYLE.alpha.selectedBorder
    else
        borderColor = STYLE.colors.locked
        borderAlpha = STYLE.alpha.activityLockedBorder
    end

    RefreshSelectableCardState(theme, skinFrame, glow, {
        isSelected = activityState.isSelected,
        borderColor = borderColor,
        borderAlpha = borderAlpha,
    })

    -- Tile background: bottom half for completed, top half for incomplete
    if not skinFrame._euiTileBg then
        local tbg = skinFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
        tbg:SetAllPoints()
        tbg:SetAtlas("characterupdate_background")
        tbg._euiOwned = true
        skinFrame._euiTileBg = tbg
    end
    if activityState.isComplete then
        skinFrame._euiTileBg:SetTexCoord(0, 1, 0.5, 1)
    else
        skinFrame._euiTileBg:SetTexCoord(0, 1, 0, 0.5)
    end

    -- Dark overlay: 20% on complete, 40% on incomplete
    if not skinFrame._euiDarkOverlay then
        local overlay = skinFrame:CreateTexture(nil, "ARTWORK", nil, 2)
        overlay:SetAllPoints()
        overlay:SetColorTexture(0, 0, 0, 1)
        overlay._euiOwned = true
        skinFrame._euiDarkOverlay = overlay
    end
    if activityState.isComplete then
        skinFrame._euiDarkOverlay:SetAlpha(0.2)
    else
        skinFrame._euiDarkOverlay:SetAlpha(0.4)
    end
    skinFrame._euiDarkOverlay:Show()

    if activityState.isComplete then
        SetActivityProgressBar(frame, 1, complete, STYLE.alpha.progressRewardFill, STYLE.alpha.progressRewardTrack)
    else
        SetActivityProgressBar(
            frame,
            activityState.ratio,
            activityState.progressColor,
            activityState.progressColor.a,
            STYLE.alpha.progressLockedTrack
        )
    end

    local d = GetFFD(frame)
    if d.lockIcon then
        d.lockIcon:SetShown(not activityState.isComplete)
    end

    if frame.Threshold then
        local thresholdAlpha = activityState.isComplete and STYLE.alpha.thresholdUnlocked or STYLE.alpha.thresholdLocked
        ApplyFont(frame.Threshold, theme, STYLE.sizes.threshold, 1, 1, 1, thresholdAlpha)
    end

    if frame.Progress then
        if activityState.isComplete then
            -- Grab Blizzard's difficulty text, stripping our ilvl prefix if
            -- we already modified it on a prior pass so it stays current.
            local rawText = frame.Progress:GetText() or ""
            local diffText = rawText:match("^%d+%s*%((.+)%)$") or rawText
            ApplyFont(frame.Progress, theme, STYLE.sizes.progress, complete.r, complete.g, complete.b, 1)

            local info = frame.info
            local ilvl
            if info and info.id and C_WeeklyRewards and C_WeeklyRewards.GetExampleRewardItemHyperlinks then
                local itemLink = C_WeeklyRewards.GetExampleRewardItemHyperlinks(info.id)
                if itemLink and GetDetailedItemLevelInfo then
                    ilvl = GetDetailedItemLevelInfo(itemLink)
                end
            end
            if ilvl then
                frame.Progress:SetText(ilvl .. " (" .. diffText .. ")")
            end
        else
            local progressColor = activityState.progressColor
            ApplyFont(
                frame.Progress,
                theme,
                STYLE.sizes.progress,
                progressColor.r,
                progressColor.g,
                progressColor.b,
                progressColor.a
            )
        end
    end

    if frame.CompletedIcon and activityState.isComplete then
        frame.CompletedIcon:SetAtlas("VAS-icon-checkmark-glw")
        frame.CompletedIcon:SetVertexColor(complete.r, complete.g, complete.b, 1)
        frame.CompletedIcon:SetDrawLayer("OVERLAY", 4)
    end

    if frame.CompletedActivityFlipbook then
        local fd = GetFFD(frame.CompletedActivityFlipbook)
        if not fd.hidden then
            fd.hidden = true
            local hiddenParent = CreateFrame("Frame")
            hiddenParent:Hide()
            fd.hiddenParent = hiddenParent
            frame.CompletedActivityFlipbook:SetParent(hiddenParent)
        end
    end

    RefreshActivityItemState(frame.ItemFrame, frame, theme)
end

local function RefreshConcessionVisualState(frame, selectedActivity, theme)
    if not frame then return end

    StripTexture(frame.Background)
    StripTexture(frame.SelectedTexture)
    StripTexture(frame.Divider1)
    StripTexture(frame.Divider2)
    if frame.UnselectedFrame then
        frame.UnselectedFrame:SetAlpha(0)
    end

    local skinFrame = EnsureInsetBackdrop(frame, theme, STYLE.paddings.concessionCard)
    local glow = EnsureSelectionGlow(frame, skinFrame)

    RefreshSelectableCardState(theme, skinFrame, glow, {
        isSelected = selectedActivity and selectedActivity == frame or false,
        borderColor = STYLE.colors.white,
        borderAlpha = STYLE.alpha.activityLockedBorder,
    })

    if frame.RewardsFrame then
        if frame.RewardsFrame.Label then
            ApplyFont(frame.RewardsFrame.Label, theme, STYLE.sizes.itemName, 1, 1, 1, STYLE.alpha.rewardsLabel)
        end
        if frame.RewardsFrame.Text then
            ApplyFont(frame.RewardsFrame.Text, theme, STYLE.sizes.itemName, theme.accent.r, theme.accent.g, theme.accent.b, 1)
        end
    end
end

local function RefreshOverlayState(overlay, theme)
    if not overlay then return end

    EnsureBackdrop(overlay, theme, 0.97)
    if overlay.Background then overlay.Background:SetAlpha(0) end
    if overlay.NineSlice then overlay.NineSlice:SetAlpha(0) end

    if overlay.Title then
        ApplyFont(overlay.Title, theme, STYLE.sizes.overlayTitle, theme.accent.r, theme.accent.g, theme.accent.b, 1)
    end
    if overlay.Text then
        ApplyFont(overlay.Text, theme, STYLE.sizes.overlayText, 1, 1, 1, STYLE.alpha.overlayText)
    end
end

local function RefreshWarningDialogState(frame, theme)
    if not frame then return end

    EnsureBackdrop(frame, theme, 0.97)
    if frame.NineSlice then frame.NineSlice:SetAlpha(0) end
    if frame.WarningIcon and frame.WarningIcon.SetDesaturated then
        frame.WarningIcon:SetDesaturated(true)
    end
    if frame.Description then
        ApplyFont(frame.Description, theme, STYLE.sizes.warningText, 1, 1, 1, STYLE.alpha.warningText)
    end
    -- Any standard buttons on the dialog get the engine treatment too
    -- (depth-capped, no-op when there are none).
    if ns.WSkin and ns.WSkin.ButtonsIn then ns.WSkin.ButtonsIn(frame) end
end

-------------------------------------------------------------------------------
--  Frame Orchestration / Hooks
-------------------------------------------------------------------------------
local RefreshGreatVaultFrame

local function ScheduleGreatVaultRefresh(frame)
    if not frame then return end
    local d = GetFFD(frame)
    if d.refreshQueued then return end

    d.refreshQueued = true
    C_Timer.After(0, function()
        d.refreshQueued = nil
        if frame and not frame:IsForbidden() then
            RefreshGreatVaultFrame(frame)
        end
    end)
end

RefreshGreatVaultFrame = function(frame)
    if not frame or frame:IsForbidden() or not frame:IsShown() or not IsGreatVaultSkinEnabled() then return end

    local theme = BuildThemeContext()

    -- Window border: the engine's shared atlas frame, so the vault carries the
    -- same soft-edged border as every other Window Skins pack. The 0.2 darken
    -- wash that tames the vault scene stays, on our own overlay frame.
    local d = GetFFD(frame)
    if not d.borderOverlay then
        local overlay = CreateFrame("Frame", nil, frame)
        overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
        overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 8)
        overlay:SetFrameLevel(frame:GetFrameLevel() + 2)

        local darken = overlay:CreateTexture(nil, "BACKGROUND", nil, 1)
        darken:SetAllPoints()
        darken:SetColorTexture(0, 0, 0, 0.2)
        darken._euiOwned = true

        d.borderOverlay = overlay
    end
    -- The atlas border hangs on the inset overlay, not the frame: the vault frame's
    -- bounds extend ~10px past its visible panel, so a border on the frame itself draws
    -- off the panel edge. At half opacity so it sits back against the vault scene.
    if ns.WSkin and ns.WSkin.AtlasBorder then
        ns.WSkin.AtlasBorder(d.borderOverlay)
        local ab = ns.WSkin.GetFFD and ns.WSkin.GetFFD(d.borderOverlay).atlasBorderFrame
        if ab then ab:SetAlpha(0.65) end
    end

    -- Hide Blizzard's border decorations
    SuppressTexture(frame.BorderShadow)
    if frame.BorderContainer then
        local bcd = GetFFD(frame.BorderContainer)
        if not bcd.hidden then
            bcd.hidden = true
            local hiddenParent = CreateFrame("Frame")
            hiddenParent:Hide()
            frame.BorderContainer:SetParent(hiddenParent)
        end
    end

    -- Header adjustments
    if frame.HeaderFrame then
        local hf = frame.HeaderFrame
        local hfd = GetFFD(hf)
        if not hfd.adjusted then
            hfd.adjusted = true

            if hf.Text then
                local point, rel, relPoint, x, y = hf.Text:GetPoint(1)
                if point then
                    hf.Text:ClearAllPoints()
                    hf.Text:SetPoint(point, rel, relPoint, x, (y or 0) + 30)
                end
                hf.Text:SetFont(theme.fontPath, STYLE.sizes.headerTitle, "")
            end

            if hf.HeaderDivider then
                local hd = hf.HeaderDivider
                local w = hd:GetWidth()
                local h = hd:GetHeight()
                if w and w > 0 and h and h > 0 then
                    hd:SetSize(w * 0.60, h * 0.60)
                end
                local point, rel, relPoint, x, y = hd:GetPoint(1)
                if point then
                    hd:ClearAllPoints()
                    hd:SetPoint(point, rel, relPoint, x, (y or 0) - 15)
                end
            end
        end
    end

    for _, typeFrame in ipairs({ frame.RaidFrame, frame.MythicFrame, frame.PVPFrame, frame.WorldFrame }) do
        if typeFrame and typeFrame:IsShown() then
            RefreshTypeFrameState(typeFrame, theme)
        end
    end

    local concessionType = Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Concession
    if frame.Activities then
        for _, activityFrame in ipairs(frame.Activities) do
            if activityFrame.type == concessionType then
                RefreshConcessionVisualState(activityFrame, frame.selectedActivity, theme)
            else
                RefreshActivityVisualState(activityFrame, frame.selectedActivity, theme)
            end
        end
    end

    ApplyStoredAnchorOffset(
        frame.SelectRewardButton,
        "_euiOriginalPoints",
        STYLE.offsets.selectRewardButton.x,
        STYLE.offsets.selectRewardButton.y
    )
    RefreshButtonState(frame.SelectRewardButton)

    -- Close button: engine primitive, same X glyph and hover as every pack.
    if frame.CloseButton and ns.WSkin and ns.WSkin.CloseButton then
        ns.WSkin.CloseButton(frame.CloseButton)
    end

    RefreshOverlayState(frame.Overlay, theme)
    RefreshWarningDialogState(_G.WeeklyRewardExpirationWarningDialog, theme)
end

local function HookGreatVault()
    local frame = _G.WeeklyRewardsFrame
    if not frame then return end
    local d = GetFFD(frame)
    if d.hooked then return end

    d.hooked = true

    -- Window-style system: treat Blizzard's vault scene as this window's EUI
    -- backdrop, so picking Modern fades the scene and shows the flat user
    -- color instead (nil-safe if the scene texture key is absent).
    if ns.WSkin and ns.WSkin.AdoptShell then
        local scene = frame.Background or frame.BackgroundTile
        ns.WSkin.AdoptShell("greatvault", frame, scene)
    end

    frame:HookScript("OnShow", function(self)
        ScheduleGreatVaultRefresh(self)
    end)

    for _, methodName in ipairs({ "Refresh", "UpdateSelection", "SetUpConditionalActivities" }) do
        hooksecurefunc(frame, methodName, function(self)
            ScheduleGreatVaultRefresh(self)
        end)
    end
end

do
    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("ADDON_LOADED")
    hookFrame:RegisterEvent("PLAYER_LOGIN")
    hookFrame:SetScript("OnEvent", function(self, _, addon)
        if addon and addon ~= "Blizzard_WeeklyRewards" then return end

        if addon == "Blizzard_WeeklyRewards" or (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards")) then
            HookGreatVault()
            self:UnregisterEvent("ADDON_LOADED")
            self:UnregisterEvent("PLAYER_LOGIN")
        end
    end)
end
