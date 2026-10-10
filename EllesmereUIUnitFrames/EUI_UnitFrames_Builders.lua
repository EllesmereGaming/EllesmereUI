if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Builders.lua
--
--  The unified frame border with its hover handlers, the aura crop helpers
--  and the four style functions that build a spawned unit frame, published
--  as I.Style*Frame (EUI_UnitFrames_Init.lua). Reads earlier files through
--  ns and ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, ns = ...

local math_floor = math.floor
local PP = EllesmereUI.PP
local GetMiniDonorSettings = ns.GetMiniDonorSettings

local I = ns._internals
local GetSettingsForUnit, UnitToSettingsKey, SetFSFont = I.GetSettingsForUnit, I.UnitToSettingsKey, I.SetFSFont
local ApplyDarkTheme, ApplyClassColor, SpecHasClassPower = I.ApplyDarkTheme, I.ApplyClassColor, I.SpecHasClassPower
local ApplyHealthBarTexture, ApplyHealthBarAlpha = I.ApplyHealthBarTexture, I.ApplyHealthBarAlpha
local CreateHealthBar, CreateAbsorbBar, CreatePowerBar, CreatePortrait =
    I.CreateHealthBar, I.CreateAbsorbBar, I.CreatePowerBar, I.CreatePortrait
local CreateCastBar, SetupShowOnCastBar, CreateBottomTextBar =
    I.CreateCastBar, I.SetupShowOnCastBar, I.CreateBottomTextBar
local ReparentBarsToClip, UpdateBordersForScale = I.ReparentBarsToClip, I.UpdateBordersForScale
local SlotWidthMul, EstimateUFTextWidth = I.SlotWidthMul, I.EstimateUFTextWidth
local db
I.dbSetters[#I.dbSetters + 1] = function(v) db = v end

-- Boss frames have an independent Hover / Target border recolor (mirrors Raid Frames
-- "Hover Borders"); both default OFF. Priority: hover (moused over) > target (current
-- target) > the frame's normal border color. Recolors the existing unified border in
-- place. _hovered is maintained by OnEnter/OnLeave hooks; _isTarget by the boss target
-- updater. On ns to avoid the Lua 200-local cap.
ns.ApplyBossBorderState = function(self)
    if not self.unifiedBorder then return end
    local s = db.profile.boss
    if not s then return end
    local r, g, b, a
    if self._hovered and s.bossHoverBorderEnabled then
        local c = s.bossHoverBorderColor or { r = 1, g = 1, b = 1 }
        r, g, b, a = c.r, c.g, c.b, s.bossHoverBorderAlpha or 1
    elseif self._isTarget and s.bossTargetBorderEnabled then
        local c = s.bossTargetBorderColor or { r = 1, g = 1, b = 1 }
        r, g, b, a = c.r, c.g, c.b, s.bossTargetBorderAlpha or 1
    else
        -- The normal colour the reload sweep painted: the same settings table
        -- (the donor's while inheriting, never the unused boss copy).
        local bsrc = ns.UF_BossBorderSettings()
        local c = bsrc.borderColor or { r = 0, g = 0, b = 0 }
        r, g, b, a = c.r, c.g, c.b, bsrc.borderAlpha or 1
    end
    EllesmereUI.SetBorderStyleColor(self.unifiedBorder, r, g, b, a)
    local seam = self.Power and self.Power._pbSeam
    if seam and seam:IsShown() then seam._tex:SetVertexColor(r, g, b, a) end
    local portraitSeam = self._portraitSeparator
    if portraitSeam and portraitSeam:IsShown() then portraitSeam._tex:SetVertexColor(r, g, b, a) end
end

local function FrameBorderEnter(self)
    if not self.unifiedBorder then return end
    if self._blizzArtFrame then return end  -- Blizzard Style: no EUI border to recolor
    local unit = self._euiUnit or "player"
    if unit:match("^boss%d$") then
        self._hovered = true
        ns.ApplyBossBorderState(self)
        return
    end
    local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget")
    local settings = isMini and GetMiniDonorSettings(unit) or GetSettingsForUnit(unit)
    -- Highlight defaults ON (nil == enabled); only an explicit false disables it.
    if settings.highlightEnabled == false then return end
    -- Per-mini-frame opt-out: with "Show Highlight Border" off, a mini frame never
    -- recolors on hover even when the donor (main frame) highlight is enabled. (When the
    -- donor highlight is off we already returned above, so this has no effect then.)
    if isMini and GetSettingsForUnit(unit).showHighlightBorder == false then return end
    local hc = settings.highlightColor or { r = 1, g = 1, b = 1 }
    local ha = settings.highlightAlpha or 1
    EllesmereUI.SetBorderStyleColor(self.unifiedBorder, hc.r, hc.g, hc.b, ha)
    -- The portrait's Outer Ring wears the frame border tint (only once built).
    local pt = self.Portrait
    local ring = pt and pt.backdrop and pt.backdrop._outerRing
    if ring and ring:IsShown() then ring:SetVertexColor(hc.r, hc.g, hc.b, ha) end
    -- So does the Power Bar Seam (only once built).
    local seam = self.Power and self.Power._pbSeam
    if seam and seam:IsShown() then seam._tex:SetVertexColor(hc.r, hc.g, hc.b, ha) end
    local portraitSeam = self._portraitSeparator
    if portraitSeam and portraitSeam:IsShown() then portraitSeam._tex:SetVertexColor(hc.r, hc.g, hc.b, ha) end
end
local function FrameBorderLeave(self)
    if not self.unifiedBorder then return end
    if self._blizzArtFrame then return end  -- Blizzard Style: no EUI border to recolor
    local unit = self._euiUnit or "player"
    if unit:match("^boss%d$") then
        self._hovered = false
        ns.ApplyBossBorderState(self)
        return
    end
    local isMini = (unit == "pet" or unit == "targettarget" or unit == "focustarget")
    local settings = isMini and GetMiniDonorSettings(unit) or GetSettingsForUnit(unit)
    local bc = settings.borderColor or { r = 0, g = 0, b = 0 }
    local ba = settings.borderAlpha or 1
    EllesmereUI.SetBorderStyleColor(self.unifiedBorder, bc.r, bc.g, bc.b, ba)
    local pt = self.Portrait
    local ring = pt and pt.backdrop and pt.backdrop._outerRing
    if ring and ring:IsShown() then ring:SetVertexColor(bc.r, bc.g, bc.b, ba) end
    local seam = self.Power and self.Power._pbSeam
    if seam and seam:IsShown() then seam._tex:SetVertexColor(bc.r, bc.g, bc.b, ba) end
    local portraitSeam = self._portraitSeparator
    if portraitSeam and portraitSeam:IsShown() then portraitSeam._tex:SetVertexColor(bc.r, bc.g, bc.b, ba) end
end

-- Unified border for unit frames using the PP border system
local function CreateUnifiedBorder(frame, unit)
    local settings = GetSettingsForUnit(unit or "player")
    local size = settings.borderSize or 1
    local bc = settings.borderColor or { r = 0, g = 0, b = 0 }
    local textureKey = settings.borderTexture or "solid"

    local border = CreateFrame("Frame", nil, frame)
    PP.Point(border, "TOPLEFT", frame, "TOPLEFT", 0, 0)
    PP.Point(border, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    local borderBehind = settings.borderBehind
    border:SetFrameLevel(borderBehind and math.max(0, frame:GetFrameLevel() - 1) or (frame:GetFrameLevel() + 10))

    EllesmereUI.ApplyBorderStyle(border, size, bc.r, bc.g, bc.b, settings.borderAlpha or 1, textureKey, settings.borderTextureOffset, settings.borderTextureOffsetY, settings.borderTextureShiftX, settings.borderTextureShiftY, "unitframes", size, nil,
        EllesmereUI.BorderPx(settings.borderSizePx, size, textureKey))

    frame.unifiedBorder = border

    if size == 0 then
        border:Hide()
    end

    frame:HookScript("OnEnter", FrameBorderEnter)
    frame:HookScript("OnLeave", FrameBorderLeave)

    return border
end

-- Cropped aura icons: the button becomes a rectangle (height = 80% of width) and the
-- texture is trimmed top/bottom so the visible art keeps its aspect ratio (no vertical
-- squish), matching the action bar "cropped" shape. Horizontal keeps the normal 0.07
-- zoom (span 0.86); vertical span derives from the button's ACTUAL width/height
-- (height = uSpan * h/w, centered) so texture width:height always equals the frame's
-- exactly, even after height rounds to whole pixels.
local AURA_CROP_HEIGHT = 0.80
local AURA_ZOOM = 0.07
-- zoom (optional) overrides the default AURA_ZOOM crop; per-unit/per-category
-- Icon Zoom values flow in here, defaulting to AURA_ZOOM so unset = unchanged.
local function SetAuraIconCrop(icon, cropped, w, h, zoom)
    if not icon then return end
    local z = zoom or AURA_ZOOM
    if cropped and w and h and w > 0 then
        local uSpan = 1 - 2 * z
        local vSpan = uSpan * (h / w)
        local v0 = 0.5 - vSpan / 2
        icon:SetTexCoord(z, 1 - z, v0, 1 - v0)
    else
        icon:SetTexCoord(z, 1 - z, z, 1 - z)
    end
end
-- Exposed so the options live preview can apply the exact same crop math
-- (rectangular height = 80% of width + aspect-preserving texcoord trim).
ns.SetAuraIconCrop = SetAuraIconCrop
function ns.GetAuraCropHeight(cropped, w)
    if cropped then return math_floor(w * AURA_CROP_HEIGHT + 0.5) end
    return w
end

-- Anchor a stack-count FontString per the "Position" setting. Default anchor is the
-- classic aura-button corner (BOTTOMRIGHT -1,0); corner anchors tuck the number inside
-- the icon edge, center sits dead-center. User X/Y offset adds on top. On ns for the
-- 200-local cap.
function ns.ApplyStackAnchor(fs, parent, pos, offX, offY)
    if not fs or not parent then return end
    local point, baseX = "BOTTOMRIGHT", -1
    if pos == "bottomleft" then point, baseX = "BOTTOMLEFT", 1
    elseif pos == "topright" then point, baseX = "TOPRIGHT", -1
    elseif pos == "topleft" then point, baseX = "TOPLEFT", 1
    elseif pos == "center" then point, baseX = "CENTER", 0 end
    fs:ClearAllPoints()
    fs:SetPoint(point, parent, point, baseX + (offX or 0), offY or 0)
end

-- 12.1 aura containers own every unit frame's buff/debuff rows
-- (EUI_UnitFrames_AuraContainers.lua): hand the container file its
-- always-fresh settings access and build the unit's containers.
local function CreateTargetAuras(frame, unit)
    ns.UF_GetSettings = GetSettingsForUnit
    ns.UF_GetProfile = ns.UF_GetProfile or function() return db and db.profile end
    return ns.UF_CreateAuraContainers(frame, unit or "target")
end

-- Pet frame buffs and debuffs are opt-in: the containers are only built once one
-- of the two is on (here at spawn, or from the options when it gets turned on).
function ns.UF_EnsurePetAuras(frame)
    frame = frame or (ns.frames and ns.frames.pet)
    local s = frame and GetSettingsForUnit("pet")
    if not s then return end
    if s.showBuffs == true or (s.debuffAnchor or "none") ~= "none" then
        CreateTargetAuras(frame, "pet")
    end
end

-- "Absorb Short" zero-hide: a binary StatusBar gate (max 1) fed the raw absorb clips
-- the abbreviated text away at zero shield, secret-safely (absorb only feeds SetValue,
-- never compared). The zone FontString is reparented into a clip frame that tracks the
-- gate fill; the HealthPrediction Override drives it. Lazy: _absGate/_absClip stay nil
-- until a zone uses Absorb Short. content "absorbshort" gates shield absorbs,
-- "healabsorbshort" heal absorbs (g._euiHealGate); anything else tears the gate down.
local function ApplyAbsorbGate(frame, unit, textOverlay, zone, fs, content)
    local isHeal = (content == "healabsorbshort")
    local wantGate = (content == "absorbshort" or isHeal)
    local g = frame._absGate and frame._absGate[zone]
    if wantGate then
        if not g then
            frame._absGate = frame._absGate or {}
            frame._absClip = frame._absClip or {}
            g = CreateFrame("StatusBar", nil, textOverlay)
            g:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            g:SetStatusBarColor(1, 1, 1, 0)  -- geometry only; never drawn
            g:SetMinMaxValues(0, 1)
            g:SetValue(0)
            local clip = CreateFrame("Frame", nil, textOverlay)
            clip:SetClipsChildren(true)
            clip:SetFrameLevel(textOverlay:GetFrameLevel() + 1)
            clip:SetPoint("TOPLEFT", g, "TOPLEFT", 0, 0)
            clip:SetPoint("BOTTOMRIGHT", g:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
            frame._absGate[zone] = g
            frame._absClip[zone] = clip
        end
        local clip = frame._absClip[zone]
        g._euiHealGate = isHeal
        g:ClearAllPoints()
        g:SetAllPoints(fs)  -- gate spans the zone's text allocation (live)
        if fs:GetParent() ~= clip then fs:SetParent(clip) end
        g:Show(); clip:Show()
        local amt
        if isHeal then
            amt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)) or 0
        else
            amt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0
        end
        g:SetValue(amt)
    elseif g then
        local clip = frame._absClip[zone]
        if fs:GetParent() == clip then fs:SetParent(textOverlay) end
        g:Hide(); if clip then clip:Hide() end
    end
end

local function StyleFullFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local powerPos = settings.powerPosition or "below"
    local powerIsAtt = (powerPos == "below" or powerPos == "above")
    local powerExtra = powerIsAtt and settings.powerHeight or 0
    local playerTargetHeight = settings.healthHeight + powerExtra
    local btbPos = settings.btbPosition or "bottom"
    local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
    local btbExtra = (settings.bottomTextBar and btbIsAttached) and (settings.bottomTextBarHeight or 16) or 0
    local targetFrameHeight = playerTargetHeight + btbExtra
    local totalWidth = 0
    local portraitHeight = playerTargetHeight
    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    local isAttached = pStyle == "attached"

    if unit == "player" then
        local pSide = settings.portraitSide or "left"
        -- For attached, "top" falls back to default side
        local effectiveSide = pSide
        if isAttached and pSide == "top" then effectiveSide = "left" end
        -- Class power "above" adds height above health bar ("top" floats outside)
        local cpAboveH = 0
        if SpecHasClassPower() then
            local cpSt = settings.classPowerStyle or "none"
            if ns.UF_ForeverCPStyle then cpSt = ns.UF_ForeverCPStyle(cpSt) end
            local cpPo = (cpSt == "modern") and (settings.classPowerPosition or "top") or "none"
            if cpSt == "modern" and cpPo == "above" then
                local cpSizeAdj = settings.classPowerSize or 8
                local cpPipH = math.max(3, math.floor(cpSizeAdj * 0.375))
                cpAboveH = cpPipH
            end
        end
        local playerHeightWithCp = playerTargetHeight + cpAboveH
        -- Apply portrait size adjustment
        local pSizeAdj = settings.portraitSize or 0
        local adjPortraitH = playerHeightWithCp + pSizeAdj
        if adjPortraitH < 8 then adjPortraitH = 8 end
        if not isAttached then pSizeAdj = pSizeAdj + 10 end
        if not showPortrait then
            totalWidth = settings.frameWidth
            portraitHeight = 0
        elseif isAttached then
            totalWidth = adjPortraitH + settings.frameWidth
        else
            -- Detached: portrait doesn't contribute to frame width
            totalWidth = settings.frameWidth
            portraitHeight = 0
        end
        -- Health bar xOffset: only offset when portrait is attached on the left
        local healthXOffset = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
        local healthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
        PP.Size(frame, totalWidth, playerHeightWithCp + btbExtra)
        frame.Health = CreateHealthBar(frame, unit, settings.healthHeight, healthXOffset, settings, healthRightInset)
        frame.Power = CreatePowerBar(frame, unit, settings)
        -- Always create absorb bar; oUF element disabled later if not wanted
        CreateAbsorbBar(frame, unit, settings)
        -- Always create portrait; hide backdrop when disabled
        frame.Portrait = CreatePortrait(frame, pSide, playerHeightWithCp, unit)
        EllesmereUI._ufPortraitSide[frame] = pSide
        if frame.Portrait and not showPortrait then
            frame.Portrait.backdrop:Hide()
        end
        -- Re-anchor health bar to portrait's actual snapped width (eliminates sub-pixel gap)
        if frame.Portrait and frame.Portrait.backdrop and showPortrait and isAttached and frame.Health then
            local snappedPortW = frame.Portrait.backdrop:GetWidth()
            local newXOff = (effectiveSide == "left") and snappedPortW or 0
            local newRI = (effectiveSide == "right") and snappedPortW or 0
            local powerAboveOff = (powerPos == "above") and settings.powerHeight or 0
            local topOff = cpAboveH + powerAboveOff
            frame.Health:ClearAllPoints()
            PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", newXOff, -topOff)
            PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -newRI, 0)
            PP.Height(frame.Health, settings.healthHeight)
            frame.Health._xOffset = newXOff
            frame.Health._rightInset = newRI
            frame.Health._topOffset = topOff
        end

        -- Always create castbar; oUF element disabled later if not wanted
        frame.Castbar = CreateCastBar(frame, unit, settings)
        SetupShowOnCastBar(frame, "player")

        -- Create player buffs and debuffs using shared aura setup
        CreateTargetAuras(frame, unit)
    elseif unit == "target" then
        local pSide = settings.portraitSide or "right"
        -- For attached, "top" falls back to default side
        local effectiveSide = pSide
        if isAttached and pSide == "top" then effectiveSide = "right" end
        local pSizeAdj = settings.portraitSize or 0
        local adjPortraitH = playerTargetHeight + pSizeAdj
        if not isAttached then pSizeAdj = pSizeAdj + 10 end
        if adjPortraitH < 8 then adjPortraitH = 8 end
        if not showPortrait then
            totalWidth = settings.frameWidth
        elseif isAttached then
            totalWidth = adjPortraitH + settings.frameWidth
        else
            totalWidth = settings.frameWidth
        end
        local healthXOffset = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
        local healthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
        PP.Size(frame, totalWidth, targetFrameHeight)
        frame.Health = CreateHealthBar(frame, unit, settings.healthHeight, healthXOffset, settings, healthRightInset)
        frame.Power = CreatePowerBar(frame, unit, settings)
        CreateAbsorbBar(frame, unit, settings)
        frame.Castbar = CreateCastBar(frame, unit, settings)
        SetupShowOnCastBar(frame, unit)
        frame.Portrait = CreatePortrait(frame, pSide, playerTargetHeight, unit)
        EllesmereUI._ufPortraitSide[frame] = pSide
        if frame.Portrait and not showPortrait then
            frame.Portrait.backdrop:Hide()
        end
        -- Re-anchor health bar to portrait's actual snapped width (eliminates sub-pixel gap)
        if frame.Portrait and frame.Portrait.backdrop and showPortrait and isAttached and frame.Health then
            local snappedPortW = frame.Portrait.backdrop:GetWidth()
            local newXOff = (effectiveSide == "left") and snappedPortW or 0
            local newRI = (effectiveSide == "right") and snappedPortW or 0
            local powerAboveOff = (powerPos == "above") and settings.powerHeight or 0
            frame.Health:ClearAllPoints()
            PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", newXOff, -powerAboveOff)
            PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -newRI, 0)
            PP.Height(frame.Health, settings.healthHeight)
            frame.Health._xOffset = newXOff
            frame.Health._rightInset = newRI
            frame.Health._topOffset = powerAboveOff
        end

        CreateTargetAuras(frame, unit)
    end

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)
    ReparentBarsToClip(frame, settings.powerPosition, settings)

    -- Raid target marker icon -- oUF's RaidTargetIndicator element manages
    -- visibility via RAID_TARGET_UPDATE. We only assign the element when
    -- enabled so oUF registers/unregisters the event accordingly.
    do
        local raidIconHolder = CreateFrame("Frame", nil, frame)
        raidIconHolder:SetAllPoints(frame)
        raidIconHolder:SetFrameLevel(frame:GetFrameLevel() + 20)
        local raidIcon = raidIconHolder:CreateTexture(nil, "OVERLAY", nil, 7)
        local rmSize  = settings.raidMarkerSize or 28
        local rmAlign = settings.raidMarkerAlign or "right"
        local rmX     = settings.raidMarkerX or 0
        local rmY     = settings.raidMarkerY or 0
        local rmAnchor = (rmAlign == "left") and "TOPLEFT"
            or (rmAlign == "center") and "TOP"
            or "TOPRIGHT"
        raidIcon:SetSize(rmSize, rmSize)
        raidIcon:SetPoint("CENTER", frame, rmAnchor, rmX, rmY)
        frame._raidMarkerIcon = raidIcon
        frame._raidMarkerHolder = raidIconHolder
        if settings.raidMarkerEnabled then
            frame.RaidTargetIndicator = raidIcon
        else
            raidIcon:Hide()
        end
    end

    -- Text overlay frame -- sits above the StatusBar for clean text rendering.
    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints(frame.Health)
    textOverlay:SetFrameStrata(frame:GetFrameStrata())
    textOverlay:SetFrameLevel(math.max(frame:GetFrameLevel() + 20, frame.Health:GetFrameLevel() + 12))
    frame._textOverlay = textOverlay

    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "both"
    local centerContent = settings.centerTextContent or "none"
    local extraContent = settings.extraTextContent or "none"
    local lts = settings.leftTextSize or settings.textSize or 12
    local rts = settings.rightTextSize or settings.textSize or 12
    local cts = settings.centerTextSize or settings.textSize or 12
    local ets = settings.extraTextSize or settings.textSize or 12

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, lts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, rts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, cts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    frame.CenterText = centerText

    -- Extra Text: a 4th text zone, identical to the others (same tags + absorb gate);
    -- anchors per extraTextAlign, capped at 95% of the bar width (ellipsis truncation).
    local extraText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(extraText, ets)
    extraText:SetWordWrap(false)
    extraText:SetTextColor(1, 1, 1)
    frame.ExtraText = extraText

    -- Shorthand aliases for font/tag application code
    frame.NameText = leftText
    frame.HealthValue = rightText

    -- Apply tags based on content. Extra Text is handled identically to the other
    -- zones (same ContentToTag + absorb gate); only positioning differs (alignment-
    -- based anchor, 95%-of-bar-width clamp with ellipsis truncation).
    local function ApplyTextTags(lc, rc, cc, ec)
        ec = ec or (settings.extraTextContent or "none")
        ns.SetTextZone(frame, leftText, lc, "leftText", settings)
        ns.SetTextZone(frame, rightText, rc, "rightText", settings)
        ns.SetTextZone(frame, centerText, cc, "centerText", settings)
        ns.SetTextZone(frame, extraText, ec, "extraText", settings)
        ApplyAbsorbGate(frame, unit, textOverlay, "left", leftText, lc)
        ApplyAbsorbGate(frame, unit, textOverlay, "right", rightText, rc)
        ApplyAbsorbGate(frame, unit, textOverlay, "center", centerText, cc)
        ApplyAbsorbGate(frame, unit, textOverlay, "extra", extraText, ec)
        ns.UF_PaintText(frame, frame._euiUnit or unit)
    end
    ApplyTextTags(leftContent, rightContent, centerContent, extraContent)
    frame._applyTextTags = ApplyTextTags

    -- Position and show/hide based on content + offsets
    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "both"
        local cc = s.centerTextContent or "none"
        local lsz = s.leftTextSize or s.textSize or 12
        local rsz = s.rightTextSize or s.textSize or 12
        local csz = s.centerTextSize or s.textSize or 12
        local lxo = s.leftTextX or 0
        local lyo = s.leftTextY or 0
        local rxo = s.rightTextX or 0
        local ryo = s.rightTextY or 0
        local cxo = s.centerTextX or 0
        local cyo = s.centerTextY or 0
        local barW = s.frameWidth or 181

        -- Extra Text: anchored per extraTextAlign (left/right/center); ellipsis-
        -- truncated past 95% of health bar width (SetWordWrap(false) + capped width below).
        local ec = s.extraTextContent or "none"
        SetFSFont(extraText, s.extraTextSize or s.textSize or 12)
        extraText:ClearAllPoints()
        if ec ~= "none" then
            local exo = s.extraTextX or 0
            local eyo = s.extraTextY or 0
            local ealign = s.extraTextAlign or "left"
            if ealign == "right" then
                extraText:SetJustifyH("RIGHT")
                PP.Point(extraText, "RIGHT", textOverlay, "RIGHT", -5 + exo, eyo)
            elseif ealign == "center" then
                extraText:SetJustifyH("CENTER")
                PP.Point(extraText, "CENTER", textOverlay, "CENTER", exo, eyo)
            else
                extraText:SetJustifyH("LEFT")
                PP.Point(extraText, "LEFT", textOverlay, "LEFT", 5 + exo, eyo)
            end
            PP.Width(extraText, barW * 0.95 * SlotWidthMul(s, "extraText"))
            extraText:Show()
            ApplyClassColor(extraText, unit, s.extraTextClassColor, s.extraTextColorR, s.extraTextColorG, s.extraTextColorB)
        else extraText:Hide() end

        -- Each text position renders independently; Center no longer hides Left/Right.
        SetFSFont(centerText, csz)
        centerText:ClearAllPoints()
        if cc ~= "none" then
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9 * SlotWidthMul(s, "centerText"))
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        else centerText:Hide() end

        SetFSFont(leftText, lsz)
        leftText:ClearAllPoints()
        if lc ~= "none" then
            leftText:SetJustifyH("LEFT")
            PP.Point(leftText, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
            -- Constrain width when opposing right text exists
            if rc ~= "none" then
                local rightUsed = EstimateUFTextWidth(rc)
                PP.Width(leftText, math.max(barW - rightUsed - 10, 20) * SlotWidthMul(s, "leftText"))
            else
                PP.Width(leftText, barW * 0.9 * SlotWidthMul(s, "leftText"))
            end
            leftText:Show()
            ApplyClassColor(leftText, unit, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
        else leftText:Hide() end

        SetFSFont(rightText, rsz)
        rightText:ClearAllPoints()
        if rc ~= "none" then
            rightText:SetJustifyH("RIGHT")
            PP.Point(rightText, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
            -- Constrain width when opposing left text exists
            if lc ~= "none" then
                local leftUsed = EstimateUFTextWidth(lc)
                PP.Width(rightText, math.max(barW - leftUsed - 10, 20) * SlotWidthMul(s, "rightText"))
            else
                PP.Width(rightText, barW * 0.9 * SlotWidthMul(s, "rightText"))
            end
            rightText:Show()
            ApplyClassColor(rightText, unit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
        else rightText:Hide() end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions

    -- Bottom Text Bar
    if settings.bottomTextBar then
        local anchorFrame = (powerIsAtt and frame.Power) or frame.Health
        local btbPos = settings.btbPosition or "bottom"
        local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
        -- BTB spans full frame width; offset left when portrait is attached on the left
        local btbXOff = 0
        if btbIsAttached and showPortrait and isAttached then
            local pSide = settings.portraitSide or (unit == "player" and "left" or "right")
            local eSide = pSide
            if pSide == "top" then eSide = (unit == "player") and "left" or "right" end
            if eSide == "left" then
                local ppPos2 = settings.powerPosition or "below"
                local ppIsAtt2 = (ppPos2 == "below" or ppPos2 == "above")
                local barH = settings.healthHeight + (ppIsAtt2 and (settings.powerHeight or 6) or 0)
                local adj = barH + (settings.portraitSize or 0)
                if adj < 8 then adj = 8 end
                btbXOff = -adj
            end
        end
        frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, anchorFrame, btbXOff, totalWidth)
        frame._btb = frame.BottomTextBar
        -- Cast bar positioning owned by centralized unlock system
    end
end


local function StyleFocusFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local fPpPos = settings.powerPosition or "below"
    local fPpIsAtt = (fPpPos == "below" or fPpPos == "above")
    local powerHeight = fPpIsAtt and (settings.powerHeight or 6) or 0
    local focusBarHeight = settings.healthHeight + powerHeight
    local btbPos = settings.btbPosition or "bottom"
    local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
    local btbExtra = (settings.bottomTextBar and btbIsAttached) and (settings.bottomTextBarHeight or 16) or 0
    local focusFrameHeight = focusBarHeight + btbExtra
    local totalWidth = 0
    local portraitHeight = 0
    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    local isAttached = pStyle == "attached"
    local pSide = settings.portraitSide or "right"
    -- For attached, "top" falls back to default side
    local effectiveSide = pSide
    if isAttached and pSide == "top" then effectiveSide = "right" end
    local pSizeAdj = settings.portraitSize or 0
    if not isAttached then pSizeAdj = pSizeAdj + 10 end
    local adjPortraitH = focusBarHeight + pSizeAdj
    if adjPortraitH < 8 then adjPortraitH = 8 end

    if not showPortrait then
        totalWidth = settings.frameWidth
    elseif isAttached then
        totalWidth = adjPortraitH + settings.frameWidth
    else
        totalWidth = settings.frameWidth
    end

    PP.Size(frame, totalWidth, focusFrameHeight)
    local healthXOffset = (showPortrait and isAttached and effectiveSide == "left") and adjPortraitH or 0
    local healthRightInset = (showPortrait and isAttached and effectiveSide == "right") and adjPortraitH or 0
    frame.Health = CreateHealthBar(frame, unit, settings.healthHeight, healthXOffset, settings, healthRightInset)
    frame.Power = CreatePowerBar(frame, unit, settings)
    CreateAbsorbBar(frame, unit, settings)
    frame.Castbar = CreateCastBar(frame, unit, settings)
    -- Always create portrait; hide backdrop when disabled
    frame.Portrait = CreatePortrait(frame, pSide, focusBarHeight, unit)
    EllesmereUI._ufPortraitSide[frame] = pSide
    if frame.Portrait and not showPortrait then
        frame.Portrait.backdrop:Hide()
    end
    -- Re-anchor health bar to portrait's actual snapped width (eliminates sub-pixel gap)
    if frame.Portrait and frame.Portrait.backdrop and showPortrait and isAttached and frame.Health then
        local snappedPortW = frame.Portrait.backdrop:GetWidth()
        local newXOff = (effectiveSide == "left") and snappedPortW or 0
        local newRI = (effectiveSide == "right") and snappedPortW or 0
        local powerAboveOff = (fPpPos == "above") and (settings.powerHeight or 6) or 0
        frame.Health:ClearAllPoints()
        PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", newXOff, -powerAboveOff)
        PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -newRI, 0)
        PP.Height(frame.Health, settings.healthHeight)
        frame.Health._xOffset = newXOff
        frame.Health._rightInset = newRI
        frame.Health._topOffset = powerAboveOff
    end

    PP.Size(frame, totalWidth, focusBarHeight)

    SetupShowOnCastBar(frame, "focus")

    CreateTargetAuras(frame, unit)

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)
    ReparentBarsToClip(frame, settings.powerPosition, settings)

    -- Raid target marker icon
    do
        local raidIconHolder = CreateFrame("Frame", nil, frame)
        raidIconHolder:SetAllPoints(frame)
        raidIconHolder:SetFrameLevel(frame:GetFrameLevel() + 20)
        local raidIcon = raidIconHolder:CreateTexture(nil, "OVERLAY", nil, 7)
        local rmSize  = settings.raidMarkerSize or 28
        local rmAlign = settings.raidMarkerAlign or "right"
        local rmX     = settings.raidMarkerX or 0
        local rmY     = settings.raidMarkerY or 0
        local rmAnchor = (rmAlign == "left") and "TOPLEFT"
            or (rmAlign == "center") and "TOP"
            or "TOPRIGHT"
        raidIcon:SetSize(rmSize, rmSize)
        raidIcon:SetPoint("CENTER", frame, rmAnchor, rmX, rmY)
        frame._raidMarkerIcon = raidIcon
        frame._raidMarkerHolder = raidIconHolder
        if settings.raidMarkerEnabled then
            frame.RaidTargetIndicator = raidIcon
        else
            raidIcon:Hide()
        end
    end

    -- Text overlay frame -- sits above the StatusBar and unified border.
    -- Parented to frame (not Health) so text is not clipped by the health bar.
    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints(frame.Health)
    textOverlay:SetFrameStrata(frame:GetFrameStrata())
    textOverlay:SetFrameLevel(math.max(frame:GetFrameLevel() + 20, frame.Health:GetFrameLevel() + 12))
    frame._textOverlay = textOverlay

    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "perhp"
    local centerContent = settings.centerTextContent or "none"
    local extraContent = settings.extraTextContent or "none"
    local lts = settings.leftTextSize or settings.textSize or 12
    local rts = settings.rightTextSize or settings.textSize or 12
    local cts = settings.centerTextSize or settings.textSize or 12
    local ets = settings.extraTextSize or settings.textSize or 12

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, lts)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, rts)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, cts)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    frame.CenterText = centerText

    -- Extra Text: a 4th text zone, identical to the others (same tags + absorb gate);
    -- anchors per extraTextAlign, capped at 95% of the bar width (ellipsis truncation).
    local extraText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(extraText, ets)
    extraText:SetWordWrap(false)
    extraText:SetTextColor(1, 1, 1)
    frame.ExtraText = extraText

    -- Shorthand aliases for font/tag application code
    frame.NameText = leftText
    frame.HealthValue = rightText

    -- Apply tags based on content. Extra Text is handled identically to the other
    -- zones (same ContentToTag + absorb gate); only positioning differs (alignment-
    -- based anchor, 95%-of-bar-width clamp with ellipsis truncation).
    local function ApplyTextTags(lc, rc, cc, ec)
        ec = ec or (settings.extraTextContent or "none")
        ns.SetTextZone(frame, leftText, lc, "leftText", settings)
        ns.SetTextZone(frame, rightText, rc, "rightText", settings)
        ns.SetTextZone(frame, centerText, cc, "centerText", settings)
        ns.SetTextZone(frame, extraText, ec, "extraText", settings)
        ApplyAbsorbGate(frame, unit, textOverlay, "left", leftText, lc)
        ApplyAbsorbGate(frame, unit, textOverlay, "right", rightText, rc)
        ApplyAbsorbGate(frame, unit, textOverlay, "center", centerText, cc)
        ApplyAbsorbGate(frame, unit, textOverlay, "extra", extraText, ec)
        ns.UF_PaintText(frame, frame._euiUnit or unit)
    end
    ApplyTextTags(leftContent, rightContent, centerContent, extraContent)
    frame._applyTextTags = ApplyTextTags

    -- Position and show/hide based on content + offsets
    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "perhp"
        local cc = s.centerTextContent or "none"
        local lsz = s.leftTextSize or s.textSize or 12
        local rsz = s.rightTextSize or s.textSize or 12
        local csz = s.centerTextSize or s.textSize or 12
        local lxo = s.leftTextX or 0
        local lyo = s.leftTextY or 0
        local rxo = s.rightTextX or 0
        local ryo = s.rightTextY or 0
        local cxo = s.centerTextX or 0
        local cyo = s.centerTextY or 0
        local barW = s.frameWidth or 181

        -- Extra Text: anchored per extraTextAlign (left/right/center); ellipsis-
        -- truncated past 95% of health bar width (SetWordWrap(false) + capped width below).
        local ec = s.extraTextContent or "none"
        SetFSFont(extraText, s.extraTextSize or s.textSize or 12)
        extraText:ClearAllPoints()
        if ec ~= "none" then
            local exo = s.extraTextX or 0
            local eyo = s.extraTextY or 0
            local ealign = s.extraTextAlign or "left"
            if ealign == "right" then
                extraText:SetJustifyH("RIGHT")
                PP.Point(extraText, "RIGHT", textOverlay, "RIGHT", -5 + exo, eyo)
            elseif ealign == "center" then
                extraText:SetJustifyH("CENTER")
                PP.Point(extraText, "CENTER", textOverlay, "CENTER", exo, eyo)
            else
                extraText:SetJustifyH("LEFT")
                PP.Point(extraText, "LEFT", textOverlay, "LEFT", 5 + exo, eyo)
            end
            PP.Width(extraText, barW * 0.95 * SlotWidthMul(s, "extraText"))
            extraText:Show()
            ApplyClassColor(extraText, unit, s.extraTextClassColor, s.extraTextColorR, s.extraTextColorG, s.extraTextColorB)
        else extraText:Hide() end

        -- Each text position renders independently; Center no longer hides Left/Right.
        SetFSFont(centerText, csz)
        centerText:ClearAllPoints()
        if cc ~= "none" then
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9 * SlotWidthMul(s, "centerText"))
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        else centerText:Hide() end

        SetFSFont(leftText, lsz)
        leftText:ClearAllPoints()
        if lc ~= "none" then
            leftText:SetJustifyH("LEFT")
            PP.Point(leftText, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
            if rc ~= "none" then
                local rightUsed = EstimateUFTextWidth(rc)
                PP.Width(leftText, math.max(barW - rightUsed - 10, 20) * SlotWidthMul(s, "leftText"))
            else
                PP.Width(leftText, barW * 0.9 * SlotWidthMul(s, "leftText"))
            end
            leftText:Show()
            ApplyClassColor(leftText, unit, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
        else leftText:Hide() end

        SetFSFont(rightText, rsz)
        rightText:ClearAllPoints()
        if rc ~= "none" then
            rightText:SetJustifyH("RIGHT")
            PP.Point(rightText, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
            if lc ~= "none" then
                local leftUsed = EstimateUFTextWidth(lc)
                PP.Width(rightText, math.max(barW - leftUsed - 10, 20) * SlotWidthMul(s, "rightText"))
            else
                PP.Width(rightText, barW * 0.9 * SlotWidthMul(s, "rightText"))
            end
            rightText:Show()
            ApplyClassColor(rightText, unit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
        else rightText:Hide() end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions

    -- Bottom Text Bar
    if settings.bottomTextBar then
        local anchorFrame = (fPpIsAtt and frame.Power) or frame.Health
        local btbPos = settings.btbPosition or "bottom"
        local btbIsAttached = (btbPos == "top" or btbPos == "bottom")
        -- BTB spans full frame width; offset left when portrait is attached on the left
        local btbXOff = 0
        if btbIsAttached and showPortrait and isAttached and effectiveSide == "left" then
            btbXOff = -adjPortraitH
        end
        frame.BottomTextBar = CreateBottomTextBar(frame, unit, settings, anchorFrame, btbXOff, totalWidth)
        frame._btb = frame.BottomTextBar
        -- Cast bar positioning owned by centralized unlock system
    end
end

-- WoW Forever pets have power (hunter pet focus, warlock pet mana), so there the
-- pet frame carries a power bar driven by the pet's own power settings, laid out
-- like the boss frames'. A plain boolean, fixed per session.
ns.UF_PetHasPower = (EllesmereUI.IS_FOREVER == true)

local function StyleSimpleFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    if pStyle == "detached" then pStyle = "attached" end
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    local pSide = settings.portraitSide or "left"
    -- WoW Forever pet power bar (Blizzard Style keeps its stock one instead): an
    -- attached bar adds its height to the stack and the portrait squares off the
    -- whole stack, as on the boss frames. Zero for every other mini frame.
    local petPower = unit == "pet" and ns.UF_PetHasPower and not ns.UF_Blizz()
    local ppPos = petPower and (settings.powerPosition or "below") or "none"
    local powerH = (ppPos == "below" or ppPos == "above") and (settings.powerHeight or 6) or 0
    local aboveOff = (ppPos == "above") and powerH or 0
    local barH = settings.healthHeight + powerH
    local totalWidth = settings.frameWidth
    local portraitOffset = 0  -- applied to Health TOPLEFT when portrait on left
    local healthRightInset = 0  -- applied to Health RIGHT when portrait on right
    if showPortrait then
        totalWidth = barH + settings.frameWidth
        if pSide == "right" then
            healthRightInset = barH
        else
            portraitOffset = barH
        end
    end

    PP.Size(frame, totalWidth, barH)

    local health = CreateFrame("StatusBar", nil, frame)
    PP.Point(health, "TOPLEFT", frame, "TOPLEFT", portraitOffset, -aboveOff)
    PP.Point(health, "RIGHT", frame, "RIGHT", -healthRightInset, 0)
    PP.Height(health, settings.healthHeight)
    health._topOffset = aboveOff  -- SnapLayout re-anchoring
    health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    health:GetStatusBarTexture():SetHorizTile(false)

    local bg = health:CreateTexture(nil, "BACKGROUND")
    PP.Point(bg, "TOPLEFT", health, "TOPLEFT", 0, 0)
    PP.Point(bg, "BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0, 0, 0, 0.5)
    health.bg = bg

    if unit ~= "pet" then health.colorClass = true end
    health.colorReaction = true
    health.colorTapped = true
    health.colorDisconnected = true
    health._euiUnitKey = UnitToSettingsKey(unit)

    -- Inherit health bar texture from the donor frame (Copy Look From),
    -- unless this frame set its own override.
    local unitKey = UnitToSettingsKey(unit)
    local donor = GetMiniDonorSettings(unitKey)
    ApplyHealthBarTexture(health, unitKey, ns.ResolveHealthBarTextureKey(settings, donor))
    ApplyHealthBarAlpha(health, unitKey)
    health:SetReverseFill(settings.healthReverseFill and true or false)
    ns.ApplyHealthOrientation(health, settings)
    ApplyDarkTheme(health, unit)

    frame.Health = health
    -- Blizzard Style: the stock small-frame power bar. Otherwise only a WoW Forever
    -- pet has one, built even at "none" so its position changes live (the painter
    -- is parked while it is hidden); ToT and FoT carry none.
    if petPower then
        frame.Power = CreatePowerBar(frame, unit, settings)
        if ppPos == "none" then frame:DisableElement("Power") end
    else
        frame.Power = ns.UF_BlizzMiniPower(frame, unit, settings)
    end
    -- A pet is never an attackable NPC, so the melee-mob gray-out pass (a pcall
    -- per paint) can never act on a WoW Forever pet's bar, stock or not (the pet
    -- defaults to an attached bar there, so it would run): drop it.
    if unit == "pet" and ns.UF_PetHasPower and frame.Power then frame.Power.PostUpdate = nil end

    -- Always create portrait; hide backdrop when disabled.
    frame.Portrait = CreatePortrait(frame, pSide, barH, unit)
    EllesmereUI._ufPortraitSide[frame] = pSide
    if frame.Portrait and not showPortrait then
        frame.Portrait.backdrop:Hide()
    end
    if frame.Portrait and frame.Portrait.backdrop and showPortrait then
        local portW = math.max(barH, 1)
        health:ClearAllPoints()
        if pSide == "right" then
            PP.Point(health, "TOPLEFT", frame, "TOPLEFT", 0, -aboveOff)
            PP.Point(health, "RIGHT", frame, "RIGHT", -portW, 0)
            health._xOffset = 0
            health._rightInset = portW
        else
            PP.Point(health, "TOPLEFT", frame, "TOPLEFT", portW, -aboveOff)
            PP.Point(health, "RIGHT", frame, "RIGHT", 0, 0)
            health._xOffset = portW
            health._rightInset = 0
        end
        PP.Height(health, settings.healthHeight)
        health._topOffset = aboveOff
    end

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)
    ReparentBarsToClip(frame, settings.powerPosition, settings)

    -- Text overlay frame (parented to frame, not health, to avoid clipping)
    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints(health)
    textOverlay:SetFrameLevel(health:GetFrameLevel() + 12)
    frame._textOverlay = textOverlay

    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "none"
    local centerContent = settings.centerTextContent or "none"

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, settings.leftTextSize or settings.textSize or 12)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, settings.rightTextSize or settings.textSize or 12)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, settings.centerTextSize or settings.textSize or 12)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    frame.CenterText = centerText

    -- Shorthand aliases for font/tag application code
    frame.NameText = leftText
    frame.HealthValue = rightText

    local function ApplyTextTags(lc, rc, cc)
        ns.SetTextZone(frame, leftText, lc, "leftText", settings)
        ns.SetTextZone(frame, rightText, rc, "rightText", settings)
        ns.SetTextZone(frame, centerText, cc, "centerText", settings)
        ApplyAbsorbGate(frame, unit, textOverlay, "left", leftText, lc)
        ApplyAbsorbGate(frame, unit, textOverlay, "right", rightText, rc)
        ApplyAbsorbGate(frame, unit, textOverlay, "center", centerText, cc)
        ns.UF_PaintText(frame, frame._euiUnit or unit)
    end
    ApplyTextTags(leftContent, rightContent, centerContent)
    frame._applyTextTags = ApplyTextTags

    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "none"
        local cc = s.centerTextContent or "none"
        local lsz = s.leftTextSize or s.textSize or 12
        local rsz = s.rightTextSize or s.textSize or 12
        local csz = s.centerTextSize or s.textSize or 12
        local lxo = s.leftTextX or 0
        local lyo = s.leftTextY or 0
        local rxo = s.rightTextX or 0
        local ryo = s.rightTextY or 0
        local cxo = s.centerTextX or 0
        local cyo = s.centerTextY or 0
        local barW = s.frameWidth or 100
        -- Each text position renders independently; Center no longer hides Left/Right.
        SetFSFont(centerText, csz)
        centerText:ClearAllPoints()
        if cc ~= "none" then
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9 * SlotWidthMul(s, "centerText"))
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        else centerText:Hide() end

        SetFSFont(leftText, lsz)
        if lc ~= "none" then
            leftText:ClearAllPoints()
            leftText:SetJustifyH("LEFT")
            PP.Point(leftText, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
            if rc ~= "none" then
                local rightUsed = EstimateUFTextWidth(rc)
                PP.Width(leftText, math.max(barW - rightUsed - 10, 20) * SlotWidthMul(s, "leftText"))
            else
                PP.Width(leftText, barW * 0.9 * SlotWidthMul(s, "leftText"))
            end
            leftText:Show()
            ApplyClassColor(leftText, unit, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
        else leftText:Hide() end
        SetFSFont(rightText, rsz)
        if rc ~= "none" then
            rightText:ClearAllPoints()
            rightText:SetJustifyH("RIGHT")
            PP.Point(rightText, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
            if lc ~= "none" then
                local leftUsed = EstimateUFTextWidth(lc)
                PP.Width(rightText, math.max(barW - leftUsed - 10, 20) * SlotWidthMul(s, "rightText"))
            else
                PP.Width(rightText, barW * 0.9 * SlotWidthMul(s, "rightText"))
            end
            rightText:Show()
            ApplyClassColor(rightText, unit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
        else rightText:Hide() end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions
    if unit == "pet" then ns.UF_EnsurePetAuras(frame) end
end


local function StyleBossFrame(frame, unit)
    local settings = GetSettingsForUnit(unit)
    local bPpPos = settings.powerPosition or "below"
    local bPpIsAtt = (bPpPos == "below" or bPpPos == "above")
    local powerHeight = bPpIsAtt and (settings.powerHeight or 6) or 0
    local bossBarHeight = settings.healthHeight + powerHeight
    local totalWidth = 0
    local portraitHeight = 0
    local pStyle = settings.portraitStyle or db.profile.portraitStyle or "attached"
    if pStyle == "detached" then pStyle = "attached" end
    local showPortrait = pStyle ~= "none" and settings.showPortrait ~= false
    if not showPortrait then
        totalWidth = settings.frameWidth
    else
        totalWidth = bossBarHeight + settings.frameWidth
    end

    PP.Size(frame, totalWidth, bossBarHeight)
    local pSide = settings.portraitSide or "right"
    local healthRightInset = (showPortrait and pSide == "right") and bossBarHeight or 0
    frame.Health = CreateHealthBar(frame, unit, settings.healthHeight, portraitHeight, settings, healthRightInset)
    frame.Power = CreatePowerBar(frame, unit, settings)
    -- Always create the absorb bar (visibility gated at render time). Boss frames
    -- carry no absorb settings of their own: they render with the TARGET frame's
    -- styling (donor convention, like textures) behind "Show on Boss Frames" in the
    -- absorb cog. Geometry (reverse fill) still comes from the boss block via `settings`.
    CreateAbsorbBar(frame, unit, settings)
    -- Always create portrait; hide backdrop when disabled
    frame.Portrait = CreatePortrait(frame, pSide, bossBarHeight, unit)
    EllesmereUI._ufPortraitSide[frame] = pSide
    if frame.Portrait and not showPortrait then
        frame.Portrait.backdrop:Hide()
    end
    -- Re-anchor health bar to portrait's actual snapped width (eliminates sub-pixel gap)
    if frame.Portrait and frame.Portrait.backdrop and showPortrait and frame.Health then
        local snappedPortW = frame.Portrait.backdrop:GetWidth()
        local powerAboveOff = (bPpPos == "above") and (settings.powerHeight or 6) or 0
        frame.Health:ClearAllPoints()
        if pSide == "left" then
            PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", snappedPortW, -powerAboveOff)
            PP.Point(frame.Health, "RIGHT", frame, "RIGHT", 0, 0)
            frame.Health._xOffset = snappedPortW
            frame.Health._rightInset = 0
        else
            PP.Point(frame.Health, "TOPLEFT", frame, "TOPLEFT", 0, -powerAboveOff)
            PP.Point(frame.Health, "RIGHT", frame, "RIGHT", -snappedPortW, 0)
            frame.Health._xOffset = 0
            frame.Health._rightInset = snappedPortW
        end
        PP.Height(frame.Health, settings.healthHeight)
        frame.Health._topOffset = powerAboveOff
    end

    PP.Size(frame, totalWidth, bossBarHeight)

    frame.Castbar = CreateCastBar(frame, unit, settings)
    SetupShowOnCastBar(frame, unit)

    CreateTargetAuras(frame, unit)

    CreateUnifiedBorder(frame, unit)
    UpdateBordersForScale(frame, unit)
    ReparentBarsToClip(frame, settings.powerPosition, settings)

    -- Raid target marker icon (boss frames) -- anchored outside the LEFT edge
    do
        local raidIconHolder = CreateFrame("Frame", nil, frame)
        raidIconHolder:SetAllPoints(frame)
        raidIconHolder:SetFrameLevel(frame:GetFrameLevel() + 20)
        local raidIcon = raidIconHolder:CreateTexture(nil, "OVERLAY", nil, 7)
        local rmSize  = settings.raidMarkerSize or 28
        local rmAlign = settings.raidMarkerAlign or "left"
        local rmX     = settings.raidMarkerX or 0
        local rmY     = settings.raidMarkerY or 0
        raidIcon:SetSize(rmSize, rmSize)
        if rmAlign == "left" then
            raidIcon:SetPoint("RIGHT", frame, "LEFT", rmX, rmY)
        elseif rmAlign == "center" then
            raidIcon:SetPoint("CENTER", frame, "CENTER", rmX, rmY)
        else
            raidIcon:SetPoint("LEFT", frame, "RIGHT", rmX, rmY)
        end
        frame._raidMarkerIcon = raidIcon
        frame._raidMarkerHolder = raidIconHolder
        if settings.raidMarkerEnabled then
            frame.RaidTargetIndicator = raidIcon
        else
            raidIcon:Hide()
        end
    end

    -- Text overlay frame (parented to frame, not health, to avoid clipping)
    local textOverlay = CreateFrame("Frame", nil, frame)
    textOverlay:SetAllPoints(frame.Health)
    textOverlay:SetFrameLevel(frame.Health:GetFrameLevel() + 12)
    frame._textOverlay = textOverlay

    local leftContent = settings.leftTextContent or "name"
    local rightContent = settings.rightTextContent or "perhp"
    local centerContent = settings.centerTextContent or "none"
    local extraContent = settings.extraTextContent or "none"

    local leftText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftText, settings.leftTextSize or settings.textSize or 12)
    leftText:SetWordWrap(false)
    leftText:SetTextColor(1, 1, 1)
    frame.LeftText = leftText

    local rightText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightText, settings.rightTextSize or settings.textSize or 12)
    rightText:SetWordWrap(false)
    rightText:SetTextColor(1, 1, 1)
    frame.RightText = rightText

    local centerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerText, settings.centerTextSize or settings.textSize or 12)
    centerText:SetWordWrap(false)
    centerText:SetTextColor(1, 1, 1)
    frame.CenterText = centerText

    -- Extra Text: a 4th text zone, identical to the others (same tags + absorb
    -- gate); it only anchors per extraTextAlign and is capped at 95% of the bar
    -- width (ellipsis truncation). Mirrors the Main Frames implementation.
    local extraText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFSFont(extraText, settings.extraTextSize or settings.textSize or 12)
    extraText:SetWordWrap(false)
    extraText:SetTextColor(1, 1, 1)
    frame.ExtraText = extraText

    frame.NameText = leftText
    frame.HealthValue = rightText

    local function ApplyTextTags(lc, rc, cc, ec)
        -- Callers that predate the Extra Text zone pass 3 args; fall back to
        -- the stored content so those sites keep working (same as Main Frames).
        ec = ec or (settings.extraTextContent or "none")
        ns.SetTextZone(frame, leftText, lc, "leftText", settings)
        ns.SetTextZone(frame, rightText, rc, "rightText", settings)
        ns.SetTextZone(frame, centerText, cc, "centerText", settings)
        ns.SetTextZone(frame, extraText, ec, "extraText", settings)
        ApplyAbsorbGate(frame, unit, textOverlay, "left", leftText, lc)
        ApplyAbsorbGate(frame, unit, textOverlay, "right", rightText, rc)
        ApplyAbsorbGate(frame, unit, textOverlay, "center", centerText, cc)
        ApplyAbsorbGate(frame, unit, textOverlay, "extra", extraText, ec)
        ns.UF_PaintText(frame, frame._euiUnit or unit)
    end
    ApplyTextTags(leftContent, rightContent, centerContent, extraContent)
    frame._applyTextTags = ApplyTextTags

    local function ApplyTextPositions(s)
        local lc = s.leftTextContent or "name"
        local rc = s.rightTextContent or "perhp"
        local cc = s.centerTextContent or "none"
        local lsz = s.leftTextSize or s.textSize or 12
        local rsz = s.rightTextSize or s.textSize or 12
        local csz = s.centerTextSize or s.textSize or 12
        local lxo = s.leftTextX or 0
        local lyo = s.leftTextY or 0
        local rxo = s.rightTextX or 0
        local ryo = s.rightTextY or 0
        local cxo = s.centerTextX or 0
        local cyo = s.centerTextY or 0
        local barW = s.frameWidth or 100
        -- Extra Text: anchored per extraTextAlign (left/right/center); ellipsis-
        -- truncated past 95% of health bar width (SetWordWrap(false) + capped width below), matching Main Frames.
        local ec = s.extraTextContent or "none"
        SetFSFont(extraText, s.extraTextSize or s.textSize or 12)
        extraText:ClearAllPoints()
        if ec ~= "none" then
            local exo = s.extraTextX or 0
            local eyo = s.extraTextY or 0
            local ealign = s.extraTextAlign or "left"
            if ealign == "right" then
                extraText:SetJustifyH("RIGHT")
                PP.Point(extraText, "RIGHT", textOverlay, "RIGHT", -5 + exo, eyo)
            elseif ealign == "center" then
                extraText:SetJustifyH("CENTER")
                PP.Point(extraText, "CENTER", textOverlay, "CENTER", exo, eyo)
            else
                extraText:SetJustifyH("LEFT")
                PP.Point(extraText, "LEFT", textOverlay, "LEFT", 5 + exo, eyo)
            end
            PP.Width(extraText, barW * 0.95 * SlotWidthMul(s, "extraText"))
            extraText:Show()
            ApplyClassColor(extraText, unit, s.extraTextClassColor, s.extraTextColorR, s.extraTextColorG, s.extraTextColorB)
        else extraText:Hide() end
        -- Each text position renders independently; Center no longer hides Left/Right.
        SetFSFont(centerText, csz)
        centerText:ClearAllPoints()
        if cc ~= "none" then
            centerText:SetJustifyH("CENTER")
            PP.Point(centerText, "CENTER", textOverlay, "CENTER", cxo, cyo)
            PP.Width(centerText, barW * 0.9 * SlotWidthMul(s, "centerText"))
            centerText:Show()
            ApplyClassColor(centerText, unit, s.centerTextClassColor, s.centerTextColorR, s.centerTextColorG, s.centerTextColorB)
        else centerText:Hide() end

        SetFSFont(leftText, lsz)
        if lc ~= "none" then
            leftText:ClearAllPoints()
            leftText:SetJustifyH("LEFT")
            PP.Point(leftText, "LEFT", textOverlay, "LEFT", 5 + lxo, lyo)
            if rc ~= "none" then
                local rightUsed = EstimateUFTextWidth(rc)
                PP.Width(leftText, math.max(barW - rightUsed - 10, 20) * SlotWidthMul(s, "leftText"))
            else
                PP.Width(leftText, barW * 0.9 * SlotWidthMul(s, "leftText"))
            end
            leftText:Show()
            ApplyClassColor(leftText, unit, s.leftTextClassColor, s.leftTextColorR, s.leftTextColorG, s.leftTextColorB)
        else leftText:Hide() end
        SetFSFont(rightText, rsz)
        if rc ~= "none" then
            rightText:ClearAllPoints()
            rightText:SetJustifyH("RIGHT")
            PP.Point(rightText, "RIGHT", textOverlay, "RIGHT", -5 + rxo, ryo)
            if lc ~= "none" then
                local leftUsed = EstimateUFTextWidth(lc)
                PP.Width(rightText, math.max(barW - leftUsed - 10, 20) * SlotWidthMul(s, "rightText"))
            else
                PP.Width(rightText, barW * 0.9 * SlotWidthMul(s, "rightText"))
            end
            rightText:Show()
            ApplyClassColor(rightText, unit, s.rightTextClassColor, s.rightTextColorR, s.rightTextColorG, s.rightTextColorB)
        else rightText:Hide() end
    end
    ApplyTextPositions(settings)
    frame._applyTextPositions = ApplyTextPositions
end


-- (Styles are no longer registered anywhere: the spawn sites call
-- StyleFullFrame/StyleFocusFrame/StyleSimpleFrame/StyleBossFrame
-- directly, and the engine's portrait painter always routes through the shared
-- gated PortraitOverride.)

I.StyleFullFrame, I.StyleFocusFrame = StyleFullFrame, StyleFocusFrame
I.StyleSimpleFrame, I.StyleBossFrame = StyleSimpleFrame, StyleBossFrame
