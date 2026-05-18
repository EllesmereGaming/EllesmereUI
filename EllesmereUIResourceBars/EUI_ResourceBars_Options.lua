-------------------------------------------------------------------------------
--  EUI_ResourceBars_Options.lua
--  Registers the Resource Bars module with EllesmereUI
--  Pages: Class, Power and Health Bars | Cast Bar | Unlock Mode
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local abs = math.abs

local PAGE_DISPLAY   = "Class, Power and Health Bars"
local PAGE_CASTBAR   = "Cast Bar"
local PAGE_UNLOCK    = "Unlock Mode"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP

    local db
    C_Timer.After(0, function() db = _G._ERB_AceDB end)

    local function DB()
        if not db then db = _G._ERB_AceDB end
        return db and db.profile
    end

    local function Refresh()
        if _G._ERB_Apply then _G._ERB_Apply() end
    end

    ---------------------------------------------------------------------------
    --  Smooth animation helper for scale / offset changes
    --  Lerps from current to target, calling applyFn(v) each frame.
    --  key is a string used to cancel previous anims on same property.
    ---------------------------------------------------------------------------
    local _animTimers = {}  -- [frame][key] = ticker
    local ANIM_DURATION = 0.18

    local function SmoothAnimate(frame, key, targetVal, applyFn)
        if not frame then return end
        if not _animTimers[frame] then _animTimers[frame] = {} end
        if _animTimers[frame][key] then
            _animTimers[frame][key]:Cancel()
            _animTimers[frame][key] = nil
        end
        local startVal = frame["_anim_" .. key] or targetVal
        frame["_anim_" .. key] = targetVal
        if math.abs(startVal - targetVal) < 0.001 then
            applyFn(targetVal)
            return
        end
        local elapsed = 0
        local ticker
        ticker = C_Timer.NewTicker(0.016, function()
            elapsed = elapsed + 0.016
            local t = math.min(elapsed / ANIM_DURATION, 1)
            t = 1 - (1 - t) * (1 - t)  -- ease-out quad
            local v = startVal + (targetVal - startVal) * t
            applyFn(v)
            if t >= 1 then
                ticker:Cancel()
                if _animTimers[frame] then _animTimers[frame][key] = nil end
            end
        end)
        _animTimers[frame][key] = ticker
    end

    ---------------------------------------------------------------------------
    --  Preview Header
    ---------------------------------------------------------------------------
    local _previewHeaderBuilder
    local _previewFrames = {}
    local _previewHintFS
    local _previewScale = 1
    local _previewBuilding = false  -- true while _previewHeaderBuilder is executing
    local IsBarTypeSecondary  -- forward declaration; assigned below
    local HasClassResource     -- forward declaration; assigned below

    -- Helper: returns true if the current class/spec has any secondary resource
    HasClassResource = function()
        local gsr = _G._ERB_GetSecondaryResource
        return gsr and gsr() ~= nil
    end

    -- Helper: returns true if the current class/spec uses a bar-type secondary (no pips)
    IsBarTypeSecondary = function()
        local _, cf = UnitClass("player")
        local spec = GetSpecialization()
        if cf == "DRUID" and spec == 1 then return true end -- Balance (Astral Power bar)
        if cf == "SHAMAN" and spec == 1 then return true end -- Elemental
        if cf == "PRIEST" and spec == 3 then return true end -- Shadow
        if cf == "MONK" and spec == 1 then return true end -- Brewmaster
        if cf == "HUNTER" and (spec == 1 or spec == 2) then return true end -- BM / MM Focus bar
        if cf == "DEMONHUNTER" and spec then
            local specID = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(spec)
            if specID == 1480 then return true end -- Devourer
        end
        return false
    end

    -- Helper: returns true if the current class/spec has a primary power bar
    local HasPrimaryPower = function()
        local gpp = _G._ERB_GetPrimaryPowerType
        return gpp and gpp() ~= nil
    end

    local function IsPreviewHintDismissed()
        return EllesmereUIDB and EllesmereUIDB.previewHintDismissed
    end

    local FONT_PATH = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("resourceBars"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
    local function GetRBOptOutline()
        return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or ""
    end
    local function GetRBOptUseShadow()
        return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow()
    end
    local function SetPVFont(fs, font, size)
        if not (fs and fs.SetFont) then return end
        local f = GetRBOptOutline()
        fs:SetFont(font, size, f)
        if f == "" then fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
        else fs:SetShadowOffset(0, 0) end
    end
    local CONTENT_PAD = 45
    local SIDE_PAD = 20

    local CLASS_COLORS = {
        WARRIOR     = { 0.78, 0.61, 0.43 },
        PALADIN     = { 0.96, 0.55, 0.73 },
        HUNTER      = { 0.67, 0.83, 0.45 },
        ROGUE       = { 1.00, 0.96, 0.41 },
        PRIEST      = { 1.00, 1.00, 1.00 },
        DEATHKNIGHT = { 0.77, 0.12, 0.23 },
        SHAMAN      = { 0.00, 0.44, 0.87 },
        MAGE        = { 0.25, 0.78, 0.92 },
        WARLOCK     = { 0.53, 0.53, 0.93 },
        MONK        = { 0.00, 1.00, 0.60 },
        DRUID       = { 1.00, 0.49, 0.04 },
        DEMONHUNTER = { 0.64, 0.19, 0.79 },
        EVOKER      = { 0.20, 0.58, 0.50 },
    }

    local DARK_FILL_R, DARK_FILL_G, DARK_FILL_B = 0x11/255, 0x11/255, 0x11/255
    local DARK_BG_R, DARK_BG_G, DARK_BG_B = 0x4f/255, 0x4f/255, 0x4f/255

    ---------------------------------------------------------------------------
    --  Preview pixel helpers (same technique as nameplates display preview)
    --  Uses Snap() based on the preview container's effective scale instead
    --  of PixelUtil, which snaps to screen pixels and can disagree with the
    --  preview's own pixel grid at certain panel scales.
    ---------------------------------------------------------------------------
    local function UnsnapTex(tex)
        if tex.SetSnapToPixelGrid then
            tex:SetSnapToPixelGrid(false); tex:SetTexelSnappingBias(0)
        end
    end

    -- Snap helper created per-preview-build so it reads the correct effective scale
    local _previewSnap  -- set in _previewHeaderBuilder

    -- Border refreshers re-snap sizes when scale changes
    local _borderRefreshers = {}
    --- Pixel-perfect border for preview frames.
    --- Uses the unified PP border system (raw integer sizes, never scaled).
    local function MakePreviewBorder(parent, r, g, b, a, size)
        local alpha = a or 1
        local sz = size or 1

        local bf = CreateFrame("Frame", nil, parent)
        bf:SetAllPoints(parent)
        bf:SetFrameLevel(parent:GetFrameLevel() + 2)

        local PP = EllesmereUI and EllesmereUI.PP
        if PP then
            PP.CreateBorder(bf, r, g, b, alpha, sz, "BORDER", 7)
        end

        return {
            _frame = bf, edges = (PP and PP.GetBorders(bf)) or {},
            SetColor = function(self, cr, cg, cb, ca)
                if PP then PP.SetBorderColor(bf, cr, cg, cb, ca or 1) end
            end,
            SetSize = function(self, newSz)
                if PP then PP.SetBorderSize(bf, newSz) end
            end,
            SetShown = function(self, shown)
                if PP then
                    if shown then PP.ShowBorder(bf) else PP.HideBorder(bf) end
                end
            end,
        }
    end

    ---------------------------------------------------------------------------
    --  Preview random fill percentages (randomized each page visit)
    ---------------------------------------------------------------------------
    local _previewPipCount = 3  -- randomized each page visit
    local _previewBarFillPct = 65 -- randomized each page visit (30-80)

    local function UpdatePreviewHeader()
        local p = DB()
        if not p then return end

        -- No class resource for this spec hide everything
        if not HasClassResource() then
            local pc = _previewFrames.pipContainer
            if pc then pc:Hide() end
            if _previewHintFS then _previewHintFS:Hide() end
            EllesmereUI:UpdateContentHeaderHeight(0)
            return
        end

        local container = _previewFrames.pipContainer and _previewFrames.pipContainer:GetParent()
        local sp = p.secondary
        local isBar = IsBarTypeSecondary()

        -- Class resource preview
        local pc = _previewFrames.pipContainer
        if pc then
            local pipH = sp.pipHeight

            -- Resolve fill color
            local _, cf = UnitClass("player")
            local cc = CLASS_COLORS[cf]
            local pr, pg, pb
            if sp.darkTheme then
                pr, pg, pb = DARK_FILL_R, DARK_FILL_G, DARK_FILL_B
            elseif sp.classColored ~= false then
                pr, pg, pb = cc and cc[1] or 0.95, cc and cc[2] or 0.90, cc and cc[3] or 0.60
            else
                -- classColored explicitly false -- use custom fill color
                pr, pg, pb = sp.fillR, sp.fillG, sp.fillB
            end









            -- Static center -- no y-offset interaction with preview

            local pScale = 1.0
            local function ApplyPipTransform()
                local s = pc["_anim_scale"] or pScale
                pc:SetScale(s)
                pc:ClearAllPoints()
                pc:SetPoint("CENTER", container, "CENTER", 0, 0)
            end
            SmoothAnimate(pc, "scale", pScale, function() ApplyPipTransform() end)



            if isBar then
                -- Bar-type preview update
                local totalW = p.primary.width or 214
                pc:SetSize(totalW, pipH)

                -- Background
                if pc._barBg then
                    if sp.darkTheme then
                        pc._barBg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, 1)
                    elseif sp.classColored then
                        pc._barBg:SetColorTexture(pr * 0.3, pg * 0.3, pb * 0.3, 0.5)
                    else
                        pc._barBg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                    end
                    UnsnapTex(pc._barBg)
                end

                -- Fill
                if pc._barFill then
                    local fillFrac = _previewBarFillPct / 100
                    pc._barFill:SetWidth(totalW * fillFrac)
                    pc._barFill:SetHeight(pipH)
                    local texKey = p.general.barTexture or "none"
                    local texLookup = _G._ERB_BarTextures or {}
                    local texPath = texLookup[texKey]
                    if texPath then
                        pc._barFill:SetTexture(texPath)
                    else
                        pc._barFill:SetTexture("Interface\\Buttons\\WHITE8x8")
                    end
                    pc._barFill:SetVertexColor(pr, pg, pb, 1)
                    UnsnapTex(pc._barFill)
                    pc._barFill:Show()
                end

                -- Tick marks on bar preview
                if not pc._previewTicks then pc._previewTicks = {} end
                do
                    -- Resolve hash lines from thresholdSpecs entry (falls back to legacy tickValues)
                    local _pvTsEntry = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(sp) or nil
                    local tickStr = (_pvTsEntry and _pvTsEntry.hashValues ~= "") and _pvTsEntry.hashValues or (sp.tickValues or "")
                    local ticks = pc._previewTicks
                    for i = 1, #ticks do ticks[i]:Hide() end
                    local vals = {}
                    for s in tickStr:gmatch("[^,]+") do
                        local n = tonumber(s:match("^%s*(.-)%s*$"))
                        if n and n > 0 then vals[#vals + 1] = n end
                    end
                    -- Use the actual resource max for tick positioning
                    local gsr = _G._ERB_GetSecondaryResource
                    local secInfo = gsr and gsr()
                    local previewMax = (secInfo and secInfo.max) or 100
                    local PP = EllesmereUI and EllesmereUI.PP
                    local onePx = PP and PP.Scale(1) or 1
                    for i, v in ipairs(vals) do
                        if v <= previewMax then
                            if not ticks[i] then
                                local t = pc:CreateTexture(nil, "OVERLAY", nil, 7)
                                t:SetColorTexture(1, 1, 1, 1)
                                t:SetSnapToPixelGrid(false)
                                t:SetTexelSnappingBias(0)
                                ticks[i] = t
                            end
                            local t = ticks[i]
                            t:ClearAllPoints()
                            local frac = v / previewMax
                            local off = PP and PP.Scale(totalW * frac) or (totalW * frac)
                            t:SetSize(onePx, pipH)
                            t:SetPoint("TOPLEFT", pc, "TOPLEFT", off, 0)
                            t:Show()
                        end
                    end
                end

                -- Hide pips if any exist from a previous build
                for _, pip in ipairs(_previewFrames.pips) do pip:Hide() end
            else
                -- Pips preview update
                -- Use the same pixel-perfect geometry as the actual resource bar
                local CalcPG = _G._ERB_CalcPipGeometry
                local pcScale = pc:GetEffectiveScale()
                if pcScale <= 0 then pcScale = 1 end
                local onePx = 1 / pcScale
                local function PipSnap(val)
                    return math.floor(val * pcScale + 0.5) / pcScale
                end
                local totalW = PipSnap(sp.pipWidth)
                local snappedPipH = PipSnap(sp.pipHeight)
                local numPips = 5
                local isVertical = false
                local isReversed = false

                local slots
                if CalcPG then
                    slots = CalcPG(totalW, numPips, sp.pipSpacing or 1, pc)
                end

                local pipX = {}
                local pipW = {}
                if slots then
                    for i = 1, numPips do
                        pipX[i] = slots[i].x0
                        pipW[i] = slots[i].x1 - slots[i].x0
                    end
                else
                    -- Fallback if CalcPipGeometry not available yet
                    local pipSp = (sp.pipSpacing > 0) and math.max(onePx, PipSnap(sp.pipSpacing)) or 0
                    local availW = totalW - (numPips - 1) * pipSp
                    local baseW = math.floor(availW * pcScale / numPips) / pcScale
                    local leftover = availW - baseW * numPips
                    local extraCount = math.floor(leftover * pcScale + 0.5)
                    local x0 = 0
                    for i = 1, numPips do
                        pipX[i] = x0
                        pipW[i] = baseW + (i <= extraCount and onePx or 0)
                        x0 = x0 + pipW[i] + pipSp
                    end
                end
                if isVertical then
                    pc:SetSize(snappedPipH, totalW)
                else
                    pc:SetSize(totalW, snappedPipH)
                end

                local _pvTsEntry2 = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(sp) or nil
                local _pvThreshCount = _pvTsEntry2 and _pvTsEntry2.thresholdCount or sp.thresholdCount
                local _pvPartialOnly = _pvTsEntry2 and _pvTsEntry2.thresholdPartialOnly or sp.thresholdPartialOnly
                local filledCount
                local _pvTsEnabled = _pvTsEntry2 and (_pvTsEntry2.thresholdEnabled ~= false) or false
                if _pvTsEnabled then
                    filledCount = _pvThreshCount
                else
                    filledCount = _previewPipCount
                end
                local useThresh = _pvTsEnabled
                local tr, tg, tb = sp.thresholdR, sp.thresholdG, sp.thresholdB

                for i, pip in ipairs(_previewFrames.pips) do
                    if isVertical then
                        pip:SetSize(snappedPipH, pipW[i])
                        pip:ClearAllPoints()
                        if isReversed then
                            pip:SetPoint("BOTTOM", pc, "BOTTOM", 0, pipX[i])
                        else
                            pip:SetPoint("TOP", pc, "TOP", 0, -pipX[i])
                        end
                    else
                        pip:SetSize(pipW[i], snappedPipH)
                        pip:ClearAllPoints()
                        pip:SetPoint("LEFT", pc, "LEFT", pipX[i], 0)
                    end
                    if sp.darkTheme then
                        pip._bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, 1)
                    elseif sp.classColored then
                        pip._bg:SetColorTexture(pr * 0.5, pg * 0.5, pb * 0.5, 0.5)
                    else
                        pip._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                    end
                    UnsnapTex(pip._bg)

                    local texKey = p.general.barTexture or "none"
                    local texLookup = _G._ERB_BarTextures or {}
                    local texPath = texLookup[texKey]
                    if texPath then
                        pip._fill:SetTexture(texPath)
                    else
                        pip._fill:SetTexture("Interface\\Buttons\\WHITE8x8")
                    end
                    UnsnapTex(pip._fill)

                    if pip._border then pip._border:SetShown(false) end
                    local active = i <= filledCount
                    if active and useThresh then
                        if _pvPartialOnly and i < _pvThreshCount then
                            pip._fill:SetVertexColor(pr, pg, pb, 1)
                        else
                            pip._fill:SetVertexColor(tr, tg, tb, 1)
                        end
                        pip._fill:Show()
                    elseif active then
                        pip._fill:SetVertexColor(pr, pg, pb, 1)
                        pip._fill:Show()
                    else
                        pip._fill:Hide()
                    end

                    -- DK rune duration preview: show fake cooldown numbers on unfilled pips
                    if cf == "DEATHKNIGHT" and sp.showText then
                        if not pip._pvCdText then
                            local overlay = CreateFrame("Frame", nil, pip)
                            overlay:SetAllPoints(pip)
                            overlay:SetFrameLevel(pip:GetFrameLevel() + 3)
                            local fs = overlay:CreateFontString(nil, "OVERLAY")
                            fs:SetTextColor(1, 1, 1, 0.9)
                            pip._pvCdText = fs
                        end
                        SetPVFont(pip._pvCdText, FONT_PATH, sp.textSize)
                        pip._pvCdText:ClearAllPoints()
                        pip._pvCdText:SetPoint("CENTER", pip, "CENTER",
                            sp.textXOffset or 0, sp.textYOffset or 0)
                        if not active then
                            -- Fake durations: higher numbers for pips further right
                            local fakeDurations = { 2, 4, 7, 9, 10 }
                            pip._pvCdText:SetText(tostring(fakeDurations[i] or ""))
                            pip._pvCdText:Show()
                        else
                            pip._pvCdText:SetText("")
                            pip._pvCdText:Hide()
                        end
                    elseif pip._pvCdText then
                        pip._pvCdText:Hide()
                    end

                    pip:Show()
                end
                for i = numPips + 1, #_previewFrames.pips do
                    _previewFrames.pips[i]:Hide()
                end

                -- Hide bar fill and tick marks if they exist from a previous build
                if pc._barFill then pc._barFill:Hide() end
                if pc._previewTicks then
                    for i = 1, #pc._previewTicks do pc._previewTicks[i]:Hide() end
                end
            end

            -- Full-bar border on container (PP or textured via ApplyBorderStyle)
            if not pc._barBorderFrame then
                local bf = CreateFrame("Frame", nil, pc)
                bf:SetAllPoints(pc)
                bf:SetFrameLevel(pc:GetFrameLevel() + 2)
                pc._barBorderFrame = bf
            end
            EllesmereUI.ApplyBorderStyle(pc._barBorderFrame, sp.borderSize or 1,
                sp.borderR or 0, sp.borderG or 0, sp.borderB or 0, sp.borderA or 1,
                sp.borderTexture or "solid", sp.borderTextureOffset, sp.borderTextureOffsetY,
                sp.borderTextureShiftX, sp.borderTextureShiftY)

            -- Full-bar background (for pips only bar-type uses _barBg)
            if not isBar then
                if not pc._pipBarBg then
                    pc._pipBarBg = pc:CreateTexture(nil, "BACKGROUND", nil, -1)
                    UnsnapTex(pc._pipBarBg)
                end
                pc._pipBarBg:ClearAllPoints()
                pc._pipBarBg:SetAllPoints(pc)
                pc._pipBarBg:SetColorTexture(sp.barBgR or 0, sp.barBgG or 0, sp.barBgB or 0, sp.barBgA or 0.5)
                pc._pipBarBg:Show()
            elseif pc._pipBarBg then
                pc._pipBarBg:Hide()
            end

            -- Count text (centered on bar) — DK uses per-pip duration instead
            local isDK = cf == "DEATHKNIGHT"
            if sp.showText and pc._countText and not isDK then
                SetPVFont(pc._countText, FONT_PATH, sp.textSize)
                pc._countText:ClearAllPoints()
                pc._countText:SetPoint("CENTER", pc, "CENTER", sp.textXOffset or 0, sp.textYOffset or 0)
                if isBar then
                    pc._countText:SetText(tostring(_previewBarFillPct))
                else
                    local _pvTsE3 = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(sp) or nil
                    local _pvE3Enabled = _pvTsE3 and (_pvTsE3.thresholdEnabled ~= false) or false
                    local filledCount = _pvE3Enabled and (_pvTsE3.thresholdCount or sp.thresholdCount) or _previewPipCount
                    pc._countText:SetText(tostring(filledCount))
                end
                pc._countText:Show()
            elseif pc._countText then
                pc._countText:Hide()
            end

            if sp.enabled then
                pc:Show()
            else
                pc:Hide()
            end
        end

        -- Preview height: hardcoded 80px
        do
            local TOTAL_H = 80
            _headerBaseH = TOTAL_H
            if container then container:SetHeight(80) end
            if not _previewBuilding then
                local hintH = (_previewHintFS and _previewHintFS:IsShown()) and 35 or 0
                EllesmereUI:UpdateContentHeaderHeight(TOTAL_H + hintH)
            end
        end
    end




    ---------------------------------------------------------------------------
    --  Forward declarations for preview click-to-scroll
    ---------------------------------------------------------------------------
    local CreateHitOverlay
    local _hitOverlays = {}
    local _headerBaseH = 0

    ---------------------------------------------------------------------------
    --  Preview Header Builder
    ---------------------------------------------------------------------------
    _previewHeaderBuilder = function(hdr, hdrW)
        local p = DB()
        if not p then return 0 end
        if not HasClassResource() then return 0 end
        _previewBuilding = true
        local _, classFile = UnitClass("player")

        local container = CreateFrame("Frame", nil, hdr)
        container:SetSize(hdrW, 100)
        container:SetPoint("CENTER", hdr, "CENTER", 0, 0)

        -- Scale the preview so pixel sizes match real bars on screen.
        -- Same technique as nameplates display preview: compensate for the
        -- EllesmereUI panel's effective scale vs UIParent's effective scale.
        local previewScale = UIParent:GetEffectiveScale() / hdr:GetEffectiveScale()
        _previewScale = previewScale
        container:SetScale(previewScale)

        -- Snap helper for this preview's effective scale
        _previewSnap = function(val)
            local s = container:GetEffectiveScale()
            return math.floor(val * s + 0.5) / s
        end

        local sp = p.secondary
        local pipH = sp.pipHeight
        local isBar = IsBarTypeSecondary()

        -- pipC is the container for either pips or the bar preview
        local pipC = CreateFrame("Frame", nil, container)
        _previewFrames.pipContainer = pipC
        _previewFrames.pips = {}

        if isBar then
            -- Bar-type preview (Devourer, Elemental Shaman)
            local totalW = p.primary.width or 214
            pipC:SetSize(totalW, pipH)
            pipC:SetPoint("CENTER", container, "CENTER", 0, 0)

            -- Background
            local bg = pipC:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            UnsnapTex(bg)
            pipC._barBg = bg

            -- Fill (status bar style via texture + width clipping)
            local fill = pipC:CreateTexture(nil, "ARTWORK")
            fill:SetPoint("LEFT")
            fill:SetHeight(pipH)
            local texKey = p.general.barTexture or "none"
            local texLookup = _G._ERB_BarTextures or {}
            local texPath = texLookup[texKey]
            if texPath then
                fill:SetTexture(texPath)
            else
                fill:SetTexture("Interface\\Buttons\\WHITE8x8")
            end
            UnsnapTex(fill)
            pipC._barFill = fill
        else
            -- Pips preview: pipWidth is total bar width; divide evenly across pips.
            -- Any remainder pixels go into pip widths, not spacing.
            local numPips = 5
            local totalW = sp.pipWidth
            local pipSp = sp.pipSpacing
            local baseW = math.floor((totalW - (numPips - 1) * pipSp) / numPips)
            local remainder = totalW - (numPips - 1) * pipSp - baseW * numPips

            local pipX = {}
            local cursor = 0
            for i = 1, numPips do
                pipX[i] = cursor
                cursor = cursor + baseW + (i <= remainder and 1 or 0) + pipSp
            end
            pipC:SetSize(totalW, pipH)
            pipC:SetPoint("CENTER", container, "CENTER", 0, 0)

            for i = 1, numPips do
                local pip = CreateFrame("Frame", nil, pipC)
                local thisPipW = baseW + (i <= remainder and 1 or 0)
                pip:SetSize(thisPipW, pipH)
                pip:SetPoint("LEFT", pipC, "LEFT", pipX[i], 0)
                local bg = pip:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                if sp.darkTheme then
                    bg:SetColorTexture(DARK_BG_R, DARK_BG_G, DARK_BG_B, 1)
                elseif sp.classColored then
                    local cc = CLASS_COLORS[classFile]
                    local cr, cg, cb = cc and cc[1] or 0.95, cc and cc[2] or 0.90, cc and cc[3] or 0.60
                    bg:SetColorTexture(cr * 0.5, cg * 0.5, cb * 0.5, 0.5)
                else
                    bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                end
                UnsnapTex(bg)
                pip._bg = bg
                local fill = pip:CreateTexture(nil, "ARTWORK")
                fill:SetAllPoints()
                local texKey = p.general.barTexture or "none"
                local texLookup = _G._ERB_BarTextures or {}
                local texPath = texLookup[texKey]
                if texPath then
                    fill:SetTexture(texPath)
                else
                    fill:SetTexture("Interface\\Buttons\\WHITE8x8")
                end
                fill:SetVertexColor(1, 1, 1, 1)
                UnsnapTex(fill)
                pip._fill = fill
                pip._border = MakePreviewBorder(pip, 0, 0, 0, 0, 0)
                pip._border:SetShown(false)
                _previewFrames.pips[i] = pip
            end
        end

        -- Count text on container (centered on bar for both types)
        local countTextOverlay = CreateFrame("Frame", nil, pipC)
        countTextOverlay:SetAllPoints(pipC)
        countTextOverlay:SetFrameLevel(pipC:GetFrameLevel() + 10)
        local countText = countTextOverlay:CreateFontString(nil, "OVERLAY")
        SetPVFont(countText, FONT_PATH, sp.textSize)
        countText:SetTextColor(1, 1, 1, 0.9)
        countText:SetPoint("CENTER", pipC, "CENTER", sp.textXOffset or 0, sp.textYOffset or 0)
        pipC._countText = countText

        UpdatePreviewHeader()

        -- Create hit overlays for preview click-to-scroll (pips only)
        wipe(_hitOverlays)
        local overlayLevel = container:GetFrameLevel() + 20
        if pipC then CreateHitOverlay(pipC, "classResource", overlayLevel) end
        if pipC and pipC._countText then
            -- Small padded frame around the text for easier clicking
            local ctHit = CreateFrame("Frame", nil, pipC)
            ctHit:SetPoint("TOPLEFT", pipC._countText, "TOPLEFT", -2, 2)
            ctHit:SetPoint("BOTTOMRIGHT", pipC._countText, "BOTTOMRIGHT", 2, -2)
            CreateHitOverlay(ctHit, "countText", overlayLevel + 5)
        end

        -- Hint text
        if _previewHintFS and not _previewHintFS:GetParent() then
            _previewHintFS = nil
        end
        local hintShown = not IsPreviewHintDismissed()

        -- Height: hardcoded 80px preview area
        local TOTAL_H = 80
        _headerBaseH = TOTAL_H
        if hintShown then
            if not _previewHintFS then
                -- Parent to a thin non-clipping child frame so the cache
                -- system stashes/restores it properly on page switch.
                local hintHost = CreateFrame("Frame", nil, hdr)
                hintHost:SetAllPoints(hdr)
                _previewHintFS = EllesmereUI.MakeFont(hintHost, 11, nil, 1, 1, 1)
                _previewHintFS:SetAlpha(0.45)
                _previewHintFS:SetText("Click elements to scroll to and highlight their options")
            end
            _previewHintFS:GetParent():SetParent(hdr)
            _previewHintFS:GetParent():Show()
            _previewHintFS:ClearAllPoints()
            _previewHintFS:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 20)
            _previewHintFS:Show()
            TOTAL_H = TOTAL_H + 35
        elseif _previewHintFS then
            _previewHintFS:Hide()
        end

        container:SetHeight(80)
        _previewBuilding = false
        return TOTAL_H
    end

    local _refreshTimer
    local function DebouncedRefresh()
        if _refreshTimer then _refreshTimer:Cancel() end
        _refreshTimer = C_Timer.NewTimer(0.05, function()
            _refreshTimer = nil
            Refresh()
        end)
    end

    ---------------------------------------------------------------------------
    --  Preview click-to-scroll infrastructure
    ---------------------------------------------------------------------------
    local _glowFrame
    local _clickMappings = {}   -- populated in BuildBarDisplayPage

    local function PlaySettingGlow(targetFrame)
        if not targetFrame then return end
        if not _glowFrame then
            _glowFrame = CreateFrame("Frame")
            local c = EllesmereUI.ELLESMERE_GREEN
            local function MkEdge()
                local t = _glowFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                t:SetColorTexture(c.r, c.g, c.b, 1)
                if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
                return t
            end
            _glowFrame._top = MkEdge()
            _glowFrame._bot = MkEdge()
            _glowFrame._lft = MkEdge()
            _glowFrame._rgt = MkEdge()
            local glowPx = PP.Scale(2)
            _glowFrame._top:SetHeight(glowPx)
            _glowFrame._top:SetPoint("TOPLEFT"); _glowFrame._top:SetPoint("TOPRIGHT")
            _glowFrame._bot:SetHeight(glowPx)
            _glowFrame._bot:SetPoint("BOTTOMLEFT"); _glowFrame._bot:SetPoint("BOTTOMRIGHT")
            _glowFrame._lft:SetWidth(glowPx)
            _glowFrame._lft:SetPoint("TOPLEFT", _glowFrame._top, "BOTTOMLEFT")
            _glowFrame._lft:SetPoint("BOTTOMLEFT", _glowFrame._bot, "TOPLEFT")
            _glowFrame._rgt:SetWidth(glowPx)
            _glowFrame._rgt:SetPoint("TOPRIGHT", _glowFrame._top, "BOTTOMRIGHT")
            _glowFrame._rgt:SetPoint("BOTTOMRIGHT", _glowFrame._bot, "TOPRIGHT")
        end
        _glowFrame:SetParent(targetFrame)
        _glowFrame:SetAllPoints(targetFrame)
        _glowFrame:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
        _glowFrame:SetAlpha(1)
        _glowFrame:Show()
        local elapsed = 0
        _glowFrame:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= 0.75 then
                self:Hide(); self:SetScript("OnUpdate", nil); return
            end
            self:SetAlpha(1 - elapsed / 0.75)
        end)
    end

    local function NavigateToSetting(key)
        local m = _clickMappings[key]
        if not m or not m.section or not m.target then return end

        -- Dismiss the hint text on first click
        if not IsPreviewHintDismissed() and _previewHintFS and _previewHintFS:IsShown() then
            EllesmereUIDB = EllesmereUIDB or {}
            EllesmereUIDB.previewHintDismissed = true
            local hint = _previewHintFS
            local _, anchorTo, _, _, startY = hint:GetPoint(1)
            startY = startY or 5
            anchorTo = anchorTo or hint:GetParent()
            local startHeaderH = _headerBaseH + 35
            local targetHeaderH = _headerBaseH
            local steps = 0
            local ticker
            ticker = C_Timer.NewTicker(0.016, function()
                steps = steps + 1
                local progress = steps * 0.016 / 0.3
                if progress >= 1 then
                    hint:Hide(); ticker:Cancel()
                    if targetHeaderH > 0 then
                        EllesmereUI:SetContentHeaderHeightSilent(targetHeaderH)
                    end
                    return
                end
                hint:SetAlpha(0.45 * (1 - progress))
                hint:ClearAllPoints()
                hint:SetPoint("BOTTOM", anchorTo, "BOTTOM", 0, startY + progress * 12)
                local hh = startHeaderH - 35 * progress
                if hh > 0 then
                    EllesmereUI:SetContentHeaderHeightSilent(hh)
                end
            end)
        end

        local sf = EllesmereUI._scrollFrame
        if not sf then return end
        local _, _, _, _, headerY = m.section:GetPoint(1)
        if not headerY then return end
        local scrollPos = math.max(0, math.abs(headerY) - 40)
        EllesmereUI.SmoothScrollTo(scrollPos)
        local glowTarget = m.target
        if m.slotSide and m.target then
            local region = (m.slotSide == "left") and m.target._leftRegion or m.target._rightRegion
            if region then glowTarget = region end
        end
        C_Timer.After(0.15, function() PlaySettingGlow(glowTarget) end)
    end

    CreateHitOverlay = function(element, mappingKey, frameLevelOverride)
        local anchor = element
        if not anchor.CreateTexture then anchor = anchor:GetParent() end
        local btn = CreateFrame("Button", nil, anchor)
        btn:SetAllPoints(element)
        btn:SetFrameLevel(frameLevelOverride or (anchor:GetFrameLevel() + 20))
        btn:RegisterForClicks("LeftButtonDown")
        local c = EllesmereUI.ELLESMERE_GREEN
        local brd = EllesmereUI.PP.CreateBorder(btn, c.r, c.g, c.b, 1, 2, "OVERLAY", 7)
        brd:Hide()
        btn:SetScript("OnEnter", function() brd:Show() end)
        btn:SetScript("OnLeave", function() brd:Hide() end)
        btn:SetScript("OnMouseDown", function() NavigateToSetting(mappingKey) end)
        _hitOverlays[#_hitOverlays + 1] = btn
        return btn
    end

    -- Non-debounced refresh for smooth animation of scale/offset changes
    local function SmoothRefresh()
        Refresh(); UpdatePreviewHeader()
    end

    local function RefreshClass()
        DebouncedRefresh(); UpdatePreviewHeader()
    end
    local function RefreshHealth()
        DebouncedRefresh(); UpdatePreviewHeader()
    end
    local function RefreshPower()
        DebouncedRefresh(); UpdatePreviewHeader()
    end
    local function RebuildClass()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end
    local function RebuildHealth()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end
    local function RebuildPower()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end

    ---------------------------------------------------------------------------
    --  MakeCogBtn helper (inline cog button next to a DualRow region)
    ---------------------------------------------------------------------------
    local function MakeCogBtn(rgn, showFn, anchorTo, iconPath)
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", anchorTo or rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints()
        cogTex:SetTexture(iconPath or EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
        cogBtn:SetScript("OnClick", function(self) showFn(self) end)
        return cogBtn
    end

    ---------------------------------------------------------------------------
    --  BuildThresholdSettingsButton: shared builder for threshold per-spec
    --  popup. Used by class resource, power bar, and health bar sections.
    --
    --  cfg = {
    --    parentRgn      -- the DualRow right region to host the button
    --    getBarData     -- fn() returns the bar sub-table (p.secondary, p.primary, p.health)
    --    refreshFn      -- fn() called after any setting change
    --    rebuildFn      -- fn() called for structural changes (hash lines)
    --    disabledFn     -- fn() returns true when the parent bar is disabled
    --    disabledTip    -- string for disabled tooltip
    --    showHash       -- bool: include hash line row + hash cog
    --    showPartialCog -- bool: include "Only Color At/Above Threshold" cog
    --    isBarTypeFn    -- fn(specID) returns true for bar-type specs (only for showHash)
    --    thresholdLabel -- string: label for threshold input (e.g. "Threshold" or "Threshold %")
    --    threshMin      -- number: slider min (default 1)
    --    threshMax      -- number: slider max (default 99)
    --    popupTitle     -- string: popup title
    --    defaultR/G/B/A -- default threshold color
    --  }
    --  Returns: settingsBtn (the button frame)
    ---------------------------------------------------------------------------
    local function BuildThresholdSettingsButton(cfg)
        local parentRgn = cfg.parentRgn
        local CLOSE_ICON_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
        local POPUP_W = 410
        local POPUP_PAD = 14
        local ROW_GAP = 6
        local EG = EllesmereUI.ELLESMERE_GREEN
        local CLASS_COLORS_L = CLASS_COLORS

        local barTypeSpecs = _G._ERB_BAR_TYPE_SPECS or {}
        local function IsSpecBarType_L(specID)
            if not cfg.isBarTypeFn then return false end
            if specID == 0 then return cfg.isBarTypeFn() end
            return barTypeSpecs[specID] or false
        end
        local function IsEntryBarType_L(entry)
            if not cfg.showHash then return false end
            if not entry or not entry.specIDs or #entry.specIDs == 0 then return false end
            return IsSpecBarType_L(entry.specIDs[1])
        end
        local function SpecName_L(specID)
            if specID == 0 then return "All Specs" end
            local _, name, _, _, _, _, className = GetSpecializationInfoByID(specID)
            if name and className then return name .. " " .. className end
            return name or ("Spec " .. specID)
        end
        local function EntryLabel_L(entry)
            if not entry or not entry.specIDs or #entry.specIDs == 0 then return "Unknown" end
            if entry.specIDs[1] == 0 then return "All Specs" end
            local names = {}
            for _, sid in ipairs(entry.specIDs) do names[#names + 1] = SpecName_L(sid) end
            return table.concat(names, ", ")
        end

        local defR = cfg.defaultR or 1
        local defG = cfg.defaultG or 0.2
        local defB = cfg.defaultB or 0.2
        local defA = cfg.defaultA or 1

        -- Settings Button
        local BTN_W, BTN_H = 140, 30
        local settingsBtn = CreateFrame("Button", nil, parentRgn)
        PP.Size(settingsBtn, BTN_W, BTN_H)
        PP.Point(settingsBtn, "RIGHT", parentRgn, "RIGHT", -20, 0)
        settingsBtn:SetFrameLevel(parentRgn:GetFrameLevel() + 2)
        local btnBg = EllesmereUI.SolidTex(settingsBtn, "BACKGROUND",
            EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
        btnBg:SetAllPoints()
        settingsBtn._border = EllesmereUI.MakeBorder(settingsBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
        local btnLbl = EllesmereUI.MakeFont(settingsBtn, 13, nil, 1, 1, 1)
        btnLbl:SetAlpha(EllesmereUI.DD_TXT_A)
        btnLbl:SetPoint("CENTER")
        btnLbl:SetText("Settings")
        settingsBtn:SetScript("OnEnter", function(self)
            btnBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
            if self._border and self._border.SetColor then self._border:SetColor(1, 1, 1, 0.3) end
        end)
        settingsBtn:SetScript("OnLeave", function(self)
            btnBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            if self._border and self._border.SetColor then self._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A) end
        end)
        -- disabled overlay
        local btnDis = CreateFrame("Frame", nil, parentRgn)
        btnDis:SetAllPoints(settingsBtn)
        btnDis:SetFrameLevel(settingsBtn:GetFrameLevel() + 5)
        btnDis:EnableMouse(true)
        btnDis:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(settingsBtn, EllesmereUI.DisabledTooltip(cfg.disabledTip or "Enable this bar"))
        end)
        btnDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateBtnDis()
            if cfg.disabledFn and cfg.disabledFn() then btnDis:Show() else btnDis:Hide() end
        end
        settingsBtn:HookScript("OnShow", UpdateBtnDis)
        EllesmereUI.RegisterWidgetRefresh(UpdateBtnDis)
        UpdateBtnDis()

        -- Popup (lazy)
        local popup
        local _entryFrames = {}
        local _tempSpecSel = {}
        local _specDDRefresh

        -- Sentinel keys for role shortcuts (negative to avoid specID collision)
        local ROLE_ALL_HEALERS = -1
        local ROLE_ALL_TANKS   = -2
        local ROLE_ALL_DPS     = -3
        local _roleSpecCache = {}  -- [ROLE_KEY] = { specID, specID, ... }

        -- Check if a specID is already claimed by an existing entry
        local function IsSpecClaimed(specID)
            local bd = cfg.getBarData()
            if not bd or not bd.thresholdSpecs then return false end
            for _, entry in ipairs(bd.thresholdSpecs) do
                if entry.specIDs then
                    for _, sid in ipairs(entry.specIDs) do
                        if sid == 0 then return true end  -- All Specs claims everything
                        if sid == specID then return true end
                    end
                end
            end
            return false
        end
        local function HasAllSpecsEntry()
            local bd = cfg.getBarData()
            if not bd or not bd.thresholdSpecs then return false end
            for _, entry in ipairs(bd.thresholdSpecs) do
                if entry.specIDs then
                    for _, sid in ipairs(entry.specIDs) do
                        if sid == 0 then return true end
                    end
                end
            end
            return false
        end

        local function BuildSpecItems_L()
            local items = {}
            items[#items + 1] = { key = 0, label = "All Specs", isAction = true, lockedFn = HasAllSpecsEntry }
            items[#items + 1] = { key = ROLE_ALL_HEALERS, label = "All Healers", isAction = true, lockedFn = HasAllSpecsEntry }
            items[#items + 1] = { key = ROLE_ALL_TANKS, label = "All Tanks", isAction = true, lockedFn = HasAllSpecsEntry }
            items[#items + 1] = { key = ROLE_ALL_DPS, label = "All DPS", isAction = true, lockedFn = HasAllSpecsEntry }

            -- Build class list sorted alphabetically by class name
            local classList = {}
            for classID = 1, (GetNumClasses and GetNumClasses() or 13) do
                local className, classFile = GetClassInfo(classID)
                if className then
                    classList[#classList + 1] = { classID = classID, className = className, classFile = classFile }
                end
            end
            table.sort(classList, function(a, b) return a.className < b.className end)

            -- Build role caches
            local healers, tanks, dps = {}, {}, {}
            for _, cls in ipairs(classList) do
                items[#items + 1] = { isHeader = true, label = cls.className }
                local numSpecs = GetNumSpecializationsForClassID(cls.classID) or 0
                for specIndex = 1, numSpecs do
                    local specID, specName, _, _, role = GetSpecializationInfoForClassID(cls.classID, specIndex)
                    if specID and specName then
                        local sid = specID
                        items[#items + 1] = { key = specID, label = specName, lockedFn = function() return IsSpecClaimed(sid) end }
                        if role == "HEALER" then healers[#healers + 1] = specID
                        elseif role == "TANK" then tanks[#tanks + 1] = specID
                        else dps[#dps + 1] = specID end
                    end
                end
            end
            _roleSpecCache[ROLE_ALL_HEALERS] = healers
            _roleSpecCache[ROLE_ALL_TANKS] = tanks
            _roleSpecCache[ROLE_ALL_DPS] = dps
            return items
        end

        local RefreshPopupEntries_L

        local function BuildPopup_L()
            popup = CreateFrame("Frame", nil, UIParent)
            popup:SetFrameStrata("DIALOG")
            popup:SetFrameLevel(200)
            popup:SetClampedToScreen(true)
            popup:EnableMouse(true)
            popup:SetScale(0.9)
            popup:Hide()
            PP.Size(popup, POPUP_W, 300)

            local bg = popup:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.06, 0.08, 0.10, 0.95)
            PP.CreateBorder(popup, 1, 1, 1, 0.15, 1, "BORDER", 7)

            local clickCatcher = CreateFrame("Button", nil, popup)
            clickCatcher:SetFrameStrata("DIALOG")
            clickCatcher:SetFrameLevel(popup:GetFrameLevel() - 1)
            clickCatcher:SetAllPoints(UIParent)
            clickCatcher:SetScript("OnClick", function() popup:Hide() end)
            clickCatcher:Hide()
            popup:SetScript("OnShow", function() clickCatcher:Show() end)
            popup:SetScript("OnHide", function() clickCatcher:Hide() end)

            if EllesmereUI._popupFrames then
                EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = popup }
            end

            local curY = -POPUP_PAD

            local titleFS = EllesmereUI.MakeFont(popup, 13, nil, 1, 1, 1)
            titleFS:SetAlpha(0.55)
            titleFS:SetPoint("TOP", popup, "TOP", 0, curY)
            titleFS:SetText(cfg.popupTitle or "Threshold Settings")
            curY = curY - 25

            -- Centered dropdown + Add button
            local DD_W, ADD_W, GAP_L = 220, 90, 10
            local rowW = DD_W + GAP_L + ADD_W
            local ddRow = CreateFrame("Frame", nil, popup)
            ddRow:SetSize(rowW, 30)
            ddRow:SetPoint("TOP", popup, "TOP", 0, curY)
            ddRow:SetFrameLevel(popup:GetFrameLevel() + 5)

            local specItems = BuildSpecItems_L()
            local specDDHost = CreateFrame("Frame", nil, ddRow)
            specDDHost:SetSize(DD_W, 30)
            specDDHost:SetPoint("LEFT", ddRow, "LEFT", 0, 0)
            specDDHost:SetFrameLevel(ddRow:GetFrameLevel())

            local cbDD, cbDDRefresh  -- forward-declare for closure access
            cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                specDDHost, DD_W, specDDHost:GetFrameLevel() + 2,
                specItems,
                function(key)
                    -- Role shortcuts never show as "checked"
                    if key == ROLE_ALL_HEALERS or key == ROLE_ALL_TANKS or key == ROLE_ALL_DPS then return false end
                    return _tempSpecSel[key] or false
                end,
                function(key, val)
                    -- Role shortcuts + All Specs: select and close dropdown
                    local roleSpecs = _roleSpecCache[key]
                    if roleSpecs then
                        wipe(_tempSpecSel)
                        for _, sid in ipairs(roleSpecs) do _tempSpecSel[sid] = true end
                        cbDD:Click()  -- close the dropdown
                        if cbDDRefresh then cbDDRefresh() end
                        return
                    end
                    if key == 0 then
                        wipe(_tempSpecSel)
                        _tempSpecSel[0] = true
                        cbDD:Click()  -- close the dropdown
                        if cbDDRefresh then cbDDRefresh() end
                        return
                    end
                    if val then
                        _tempSpecSel[0] = nil
                        _tempSpecSel[key] = true
                    else
                        _tempSpecSel[key] = nil
                    end
                    if cbDDRefresh then cbDDRefresh() end
                end,
                nil, 10, true
            )
            PP.Point(cbDD, "LEFT", specDDHost, "LEFT", 0, 0)
            -- Reduce dropdown label font by 2px (default is 13)
            for _, rgn2 in ipairs({ cbDD:GetRegions() }) do
                if rgn2.SetFont and rgn2.GetText then
                    local f, _, fl = rgn2:GetFont(); if f then rgn2:SetFont(f, 11, fl or "") end; break
                end
            end

            local _origRefresh = cbDDRefresh
            local function WrappedRefresh()
                _origRefresh()
                local regions = { cbDD:GetRegions() }
                for _, rgn2 in ipairs(regions) do
                    if rgn2.GetText and rgn2:GetText() == "None" then
                        rgn2:SetText("Select a Spec..."); break
                    end
                end
            end
            _specDDRefresh = WrappedRefresh
            WrappedRefresh()

            local addBtn = CreateFrame("Button", nil, ddRow)
            PP.Size(addBtn, ADD_W, 30)
            addBtn:SetPoint("LEFT", specDDHost, "RIGHT", GAP_L, 0)
            addBtn:SetFrameLevel(ddRow:GetFrameLevel() + 2)
            local addBg = EllesmereUI.SolidTex(addBtn, "BACKGROUND", 0.05, 0.07, 0.09, 0.92)
            addBg:SetAllPoints()
            addBtn._border = EllesmereUI.MakeBorder(addBtn, 1, 1, 1, 0.4, PP)
            local addLbl = EllesmereUI.MakeFont(addBtn, 11, nil, 1, 1, 1)
            addLbl:SetAlpha(0.5)
            addLbl:SetPoint("CENTER")
            addLbl:SetText("Add Specs")
            addBtn:SetScript("OnEnter", function()
                addLbl:SetAlpha(0.7)
                if addBtn._border and addBtn._border.SetColor then addBtn._border:SetColor(1, 1, 1, 0.6) end
            end)
            addBtn:SetScript("OnLeave", function()
                addLbl:SetAlpha(0.5)
                if addBtn._border and addBtn._border.SetColor then addBtn._border:SetColor(1, 1, 1, 0.4) end
            end)
            addBtn:SetScript("OnClick", function()
                local bd = cfg.getBarData(); if not bd then return end
                local ids = {}
                if _tempSpecSel[0] then
                    ids[1] = 0
                else
                    for sid in pairs(_tempSpecSel) do
                        if sid ~= 0 then ids[#ids + 1] = sid end
                    end
                end
                if #ids == 0 then return end
                if not bd.thresholdSpecs then bd.thresholdSpecs = {} end
                local newEntry = {
                    specIDs = ids,
                    thresholdEnabled = true,
                    thresholdPct = cfg.threshMin == 1 and 30 or 30,
                    thresholdPartialOnly = false,
                    thresholdR = defR, thresholdG = defG, thresholdB = defB, thresholdA = defA,
                }
                if cfg.showHash then
                    local isBar = IsSpecBarType_L(ids[1])
                    newEntry.hashValues = ""
                    newEntry.hashWidth = 1
                    newEntry.hashColorR = 1; newEntry.hashColorG = 1; newEntry.hashColorB = 1; newEntry.hashColorA = 0.7
                    newEntry.thresholdCount = isBar and 30 or 3
                else
                    newEntry.thresholdPct = 30
                end
                bd.thresholdSpecs[#bd.thresholdSpecs + 1] = newEntry
                wipe(_tempSpecSel)
                WrappedRefresh()
                RefreshPopupEntries_L()
                cfg.refreshFn()
            end)

            curY = curY - 36

            -- Scrollable entry container
            local POPUP_MAX_H = 375
            local headerH = math.abs(curY)

            local scrollFrame = CreateFrame("ScrollFrame", nil, popup)
            scrollFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, curY)
            scrollFrame:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, curY)
            scrollFrame:SetFrameLevel(popup:GetFrameLevel() + 1)

            local scrollChild = CreateFrame("Frame", nil, scrollFrame)
            scrollChild:SetWidth(POPUP_W)
            scrollFrame:SetScrollChild(scrollChild)

            local scrollBar = CreateFrame("Frame", nil, popup)
            scrollBar:SetWidth(4)
            scrollBar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -3, curY)
            scrollBar:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -3, 4)
            scrollBar:SetFrameLevel(popup:GetFrameLevel() + 10)
            scrollBar:Hide()
            local scrollTrack = scrollBar:CreateTexture(nil, "BACKGROUND")
            scrollTrack:SetAllPoints()
            scrollTrack:SetColorTexture(1, 1, 1, 0.04)
            local scrollThumb = scrollBar:CreateTexture(nil, "OVERLAY")
            scrollThumb:SetWidth(4)
            scrollThumb:SetColorTexture(1, 1, 1, 0.15)
            scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, 0)
            scrollThumb:SetHeight(30)

            scrollFrame:SetScript("OnMouseWheel", function(self, delta)
                local maxScroll = self:GetVerticalScrollRange()
                if maxScroll <= 0 then return end
                local cur = self:GetVerticalScroll()
                self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * 30)))
            end)
            scrollFrame:SetScript("OnScrollRangeChanged", function(self, _, yRange)
                if not yRange or yRange <= 0 then scrollBar:Hide(); return end
                scrollBar:Show()
                local barH = scrollBar:GetHeight()
                if barH <= 0 then return end
                scrollThumb:SetHeight(math.max(20, barH * (self:GetHeight() / (self:GetHeight() + yRange))))
            end)
            scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
                local maxScroll = self:GetVerticalScrollRange()
                if maxScroll <= 0 then return end
                local barH = scrollBar:GetHeight()
                local thumbH = scrollThumb:GetHeight()
                local travel = barH - thumbH
                scrollThumb:ClearAllPoints()
                scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, -travel * (offset / maxScroll))
            end)

            popup._scrollFrame = scrollFrame
            popup._scrollChild = scrollChild
            popup._headerH = headerH
            popup._maxH = POPUP_MAX_H
        end -- BuildPopup_L

        RefreshPopupEntries_L = function()
            if not popup then return end
            local bd = cfg.getBarData(); if not bd then return end
            if not bd.thresholdSpecs then bd.thresholdSpecs = {} end
            local entries = bd.thresholdSpecs

            local scrollChild = popup._scrollChild
            local curY = 0
            local ENTRY_W = POPUP_W - POPUP_PAD * 2
            local ENTRY_H = cfg.showHash and 89 or 60

            for i = 1, #_entryFrames do
                if _entryFrames[i] then _entryFrames[i]:Hide() end
            end

            for idx, entry in ipairs(entries) do
                local ef = _entryFrames[idx]
                if not ef then
                    ef = CreateFrame("Frame", nil, scrollChild)
                    ef:SetFrameLevel(popup:GetFrameLevel() + 2)
                    _entryFrames[idx] = ef

                    local entBg = ef:CreateTexture(nil, "BACKGROUND")
                    entBg:SetAllPoints()
                    entBg:SetColorTexture(1, 1, 1, 0.02)

                    local delBtn = CreateFrame("Button", nil, ef)
                    delBtn:SetSize(14, 14)
                    delBtn:SetPoint("TOPRIGHT", ef, "TOPRIGHT", -6, -9)
                    delBtn:SetFrameLevel(ef:GetFrameLevel() + 3)
                    local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                    delIcon:SetAllPoints()
                    delIcon:SetTexture(CLOSE_ICON_PATH)
                    delIcon:SetAlpha(0.4)
                    delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
                    delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
                    ef._delBtn = delBtn

                    local specLbl = EllesmereUI.MakeFont(ef, 14, nil, 1, 1, 1)
                    specLbl:SetAlpha(0.85)
                    specLbl:SetPoint("TOPLEFT", ef, "TOPLEFT", 8, -9)
                    specLbl:SetPoint("RIGHT", ef, "RIGHT", -26, 0)
                    specLbl:SetJustifyH("LEFT")
                    specLbl:SetWordWrap(false)
                    ef._specLbl = specLbl

                    -- Threshold row Y offset depends on whether hash row exists
                    local threshY = cfg.showHash and -61 or -33

                    -- Hash row (only for class resource)
                    if cfg.showHash then
                        local hashLbl = EllesmereUI.MakeFont(ef, 13, nil, 1, 1, 1)
                        hashLbl:SetAlpha(0.6)
                        hashLbl:SetPoint("TOPLEFT", ef, "TOPLEFT", 8, -33)
                        ef._hashLbl = hashLbl

                        local hashHint = EllesmereUI.MakeFont(ef, 10, nil, 1, 1, 1)
                        hashHint:SetAlpha(0.35)
                        hashHint:SetPoint("LEFT", hashLbl, "RIGHT", 4, 0)
                        ef._hashHint = hashHint

                        local hashInput = CreateFrame("EditBox", nil, ef)
                        hashInput:SetSize(100, 22)
                        hashInput:SetPoint("LEFT", hashHint, "RIGHT", 8, 0)
                        hashInput:SetFrameLevel(ef:GetFrameLevel() + 3)
                        hashInput:SetAutoFocus(false)
                        hashInput:SetFontObject(GameFontHighlightSmall)
                        local hiFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"
                        hashInput:SetFont(hiFont, 12, "")
                        hashInput:SetTextColor(1, 1, 1, 0.75)
                        hashInput:SetJustifyH("CENTER")
                        local hiBg = hashInput:CreateTexture(nil, "BACKGROUND")
                        hiBg:SetAllPoints()
                        hiBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                        EllesmereUI.MakeBorder(hashInput, 1, 1, 1, 0.08, PP)
                        ef._hashInput = hashInput

                        local _, hashCogShow = EllesmereUI.BuildCogPopup({
                            title = "Hash Line Style", bgAlpha = 1,
                            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
                            rows = {
                                { type = "slider", label = "Hash Width", min = 1, max = 4, step = 1,
                                  get = function()
                                      if not ef._entryIdx then return 1 end
                                      local bd2 = cfg.getBarData(); if not bd2 then return 1 end
                                      local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                      return ent and ent.hashWidth or 1
                                  end,
                                  set = function(v)
                                      if not ef._entryIdx then return end
                                      local bd2 = cfg.getBarData(); if not bd2 then return end
                                      local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                      if ent then ent.hashWidth = v; cfg.rebuildFn() end
                                  end },
                                { type = "colorpicker", label = "Hash Color", hasAlpha = true,
                                  get = function()
                                      if not ef._entryIdx then return 1, 1, 1, 0.7 end
                                      local bd2 = cfg.getBarData(); if not bd2 then return 1, 1, 1, 0.7 end
                                      local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                      if not ent then return 1, 1, 1, 0.7 end
                                      return ent.hashColorR or 1, ent.hashColorG or 1, ent.hashColorB or 1, ent.hashColorA or 0.7
                                  end,
                                  set = function(r, g, b, a)
                                      if not ef._entryIdx then return end
                                      local bd2 = cfg.getBarData(); if not bd2 then return end
                                      local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                      if ent then
                                          ent.hashColorR, ent.hashColorG, ent.hashColorB, ent.hashColorA = r, g, b, a
                                          cfg.rebuildFn()
                                      end
                                  end },
                            },
                        })
                        local hashCogBtn = CreateFrame("Button", nil, ef)
                        hashCogBtn:SetSize(20, 20)
                        hashCogBtn:SetPoint("LEFT", hashInput, "RIGHT", 6, 0)
                        hashCogBtn:SetFrameLevel(ef:GetFrameLevel() + 5)
                        hashCogBtn:SetAlpha(0.4)
                        local hashCogTex = hashCogBtn:CreateTexture(nil, "OVERLAY")
                        hashCogTex:SetAllPoints()
                        hashCogTex:SetTexture(EllesmereUI.COGS_ICON)
                        hashCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                        hashCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                        hashCogBtn:SetScript("OnClick", function(self) hashCogShow(self) end)
                        ef._hashCogBtn = hashCogBtn
                    end

                    -- Threshold row
                    local threshLbl2 = EllesmereUI.MakeFont(ef, 13, nil, 1, 1, 1)
                    threshLbl2:SetAlpha(0.6)
                    threshLbl2:SetPoint("TOPLEFT", ef, "TOPLEFT", 8, threshY)
                    threshLbl2:SetText(cfg.thresholdLabel or "Threshold")
                    ef._threshLbl = threshLbl2

                    local threshInput = CreateFrame("EditBox", nil, ef)
                    threshInput:SetSize(50, 22)
                    threshInput:SetPoint("LEFT", threshLbl2, "RIGHT", 8, 0)
                    threshInput:SetFrameLevel(ef:GetFrameLevel() + 3)
                    threshInput:SetAutoFocus(false)
                    threshInput:SetFontObject(GameFontHighlightSmall)
                    local tiFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"
                    threshInput:SetFont(tiFont, 12, "")
                    threshInput:SetTextColor(1, 1, 1, 0.75)
                    threshInput:SetJustifyH("CENTER")
                    threshInput:SetNumeric(true)
                    local tiBg = threshInput:CreateTexture(nil, "BACKGROUND")
                    tiBg:SetAllPoints()
                    tiBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                    EllesmereUI.MakeBorder(threshInput, 1, 1, 1, 0.08, PP)
                    ef._threshInput = threshInput

                    -- Inline color swatch
                    local entrySwatch, entrySwatchSnap = EllesmereUI.BuildColorSwatch(ef, ef:GetFrameLevel() + 4,
                        function()
                            if not ef._entryIdx then return defR, defG, defB, defA end
                            local bd2 = cfg.getBarData(); if not bd2 then return defR, defG, defB, defA end
                            local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                            if not ent then return defR, defG, defB, defA end
                            return ent.thresholdR or defR, ent.thresholdG or defG, ent.thresholdB or defB, ent.thresholdA or defA
                        end,
                        function(r, g, b, a)
                            if not ef._entryIdx then return end
                            local bd2 = cfg.getBarData(); if not bd2 then return end
                            local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                            if ent then ent.thresholdR, ent.thresholdG, ent.thresholdB, ent.thresholdA = r, g, b, a; cfg.refreshFn() end
                        end, true, 19)
                    entrySwatch:SetPoint("LEFT", threshInput, "RIGHT", 8, 0)
                    ef._entrySwatch = entrySwatch
                    ef._entrySwatchSnap = entrySwatchSnap

                    -- Inline toggle
                    local entryToggle, _, entrySnap = EllesmereUI.BuildToggleControl(
                        ef, ef:GetFrameLevel() + 4,
                        function()
                            if not ef._entryIdx then return false end
                            local bd2 = cfg.getBarData(); if not bd2 then return false end
                            local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                            if not ent then return false end
                            if ent.thresholdEnabled == nil then return true end
                            return ent.thresholdEnabled
                        end,
                        function(v)
                            if not ef._entryIdx then return end
                            local bd2 = cfg.getBarData(); if not bd2 then return end
                            local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                            if ent then ent.thresholdEnabled = v; cfg.refreshFn() end
                            if RefreshPopupEntries_L then RefreshPopupEntries_L() end
                        end,
                        { sizeRatio = 0.95 }
                    )
                    entryToggle:SetPoint("LEFT", entrySwatch, "RIGHT", 6, 0)
                    ef._entryToggle = entryToggle
                    ef._entrySnap = entrySnap

                    -- Cog (only if showPartialCog)
                    if cfg.showPartialCog then
                        local _, entryCogShow = EllesmereUI.BuildCogPopup({
                            title = "Threshold Coloring", bgAlpha = 1,
                            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
                            rows = {
                                { type = "toggle", label = "Reverse Threshold Fill Color",
                                  get = function()
                                      if not ef._entryIdx then return false end
                                      local bd2 = cfg.getBarData(); if not bd2 then return false end
                                      local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                      return ent and ent.thresholdPartialOnly
                                  end,
                                  set = function(v)
                                      if not ef._entryIdx then return end
                                      local bd2 = cfg.getBarData(); if not bd2 then return end
                                      local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                      if ent then ent.thresholdPartialOnly = v; cfg.refreshFn() end
                                  end },
                            },
                        })
                        local cogBtn2 = CreateFrame("Button", nil, ef)
                        cogBtn2:SetSize(20, 20)
                        cogBtn2:SetPoint("LEFT", entryToggle, "RIGHT", 6, 0)
                        cogBtn2:SetFrameLevel(ef:GetFrameLevel() + 5)
                        cogBtn2:SetAlpha(0.4)
                        local cogTex2 = cogBtn2:CreateTexture(nil, "OVERLAY")
                        cogTex2:SetAllPoints()
                        cogTex2:SetTexture(EllesmereUI.COGS_ICON)
                        cogBtn2:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                        cogBtn2:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                        cogBtn2:SetScript("OnClick", function(self) entryCogShow(self) end)
                        ef._cogBtn = cogBtn2
                    end

                    -- Disabled overlay (excludes toggle)
                    local threshDis = CreateFrame("Frame", nil, ef)
                    threshDis:SetPoint("TOPLEFT", threshLbl2, "TOPLEFT", -2, 4)
                    threshDis:SetPoint("BOTTOMRIGHT", entryToggle, "BOTTOMLEFT", -4, -4)
                    threshDis:SetFrameLevel(ef:GetFrameLevel() + 6)
                    threshDis:EnableMouse(true)
                    local threshDisTex = threshDis:CreateTexture(nil, "OVERLAY")
                    threshDisTex:SetAllPoints()
                    threshDisTex:SetColorTexture(0.06, 0.08, 0.10, 0.7)
                    threshDis:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(threshDis, EllesmereUI.DisabledTooltip("Threshold Color"))
                    end)
                    threshDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    ef._threshDis = threshDis
                end -- end entry frame creation

                -- Populate entry
                ef:SetSize(ENTRY_W, ENTRY_H)
                ef:ClearAllPoints()
                ef:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", POPUP_PAD, curY)
                ef._entryIdx = idx

                ef._specLbl:SetText(EntryLabel_L(entry))
                do
                    local firstSID = entry.specIDs and entry.specIDs[1]
                    local classFile
                    if firstSID == 0 then
                        local _, cf = UnitClass("player"); classFile = cf
                    elseif firstSID then
                        local _, _, _, _, _, cf = GetSpecializationInfoByID(firstSID); classFile = cf
                    end
                    local cc = classFile and CLASS_COLORS_L[classFile]
                    if cc then ef._specLbl:SetTextColor(cc[1], cc[2], cc[3], 1)
                    else ef._specLbl:SetTextColor(1, 1, 1, 1) end
                end

                ef._delBtn:SetScript("OnClick", function()
                    local bd2 = cfg.getBarData(); if not bd2 then return end
                    table.remove(bd2.thresholdSpecs, idx)
                    wipe(_tempSpecSel)
                    if _specDDRefresh then _specDDRefresh() end
                    RefreshPopupEntries_L()
                    cfg.refreshFn()
                end)

                if cfg.showHash and ef._hashLbl then
                    local isBar = IsEntryBarType_L(entry)
                    local hashWord = isBar and "Percent" or "Stack"
                    ef._hashLbl:SetText("Hash at " .. hashWord)
                    ef._hashHint:SetText(isBar and "(Ex: 25,50,75)" or "(Ex: 2,4)")
                    ef._hashInput:SetText(entry.hashValues or "")
                    ef._hashInput:SetScript("OnEnterPressed", function(self)
                        local bd2 = cfg.getBarData(); if not bd2 then return end
                        local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[idx]
                        if ent then ent.hashValues = self:GetText(); cfg.rebuildFn() end
                        self:ClearFocus()
                    end)
                    ef._hashInput:SetScript("OnEscapePressed", function(self)
                        local bd2 = cfg.getBarData(); if not bd2 then return end
                        local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[idx]
                        self:SetText(ent and ent.hashValues or ""); self:ClearFocus()
                    end)
                end

                -- Threshold input
                local threshKey = cfg.showHash and "thresholdCount" or "thresholdPct"
                local threshDef = cfg.showHash and (IsEntryBarType_L(entry) and 30 or 3) or 30
                local threshMaxVal = cfg.threshMax or 99
                if cfg.showHash then
                    threshMaxVal = IsEntryBarType_L(entry) and 100 or 10
                end
                ef._threshInput:SetText(tostring(entry[threshKey] or threshDef))
                ef._threshInput:SetScript("OnEnterPressed", function(self)
                    local val = tonumber(self:GetText())
                    if not val then self:SetText(tostring(entry[threshKey] or threshDef)); self:ClearFocus(); return end
                    val = math.max(cfg.threshMin or 1, math.min(threshMaxVal, math.floor(val + 0.5)))
                    self:SetText(tostring(val))
                    local bd2 = cfg.getBarData(); if not bd2 then return end
                    local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[idx]
                    if ent then ent[threshKey] = val; cfg.refreshFn() end
                    self:ClearFocus()
                end)
                ef._threshInput:SetScript("OnEscapePressed", function(self)
                    self:SetText(tostring(entry[threshKey] or threshDef)); self:ClearFocus()
                end)

                if ef._entrySnap then ef._entrySnap() end
                if ef._entrySwatchSnap then ef._entrySwatchSnap() end

                local entEnabled = entry.thresholdEnabled
                if entEnabled == nil then entEnabled = true end
                if not entEnabled then ef._threshDis:Show() else ef._threshDis:Hide() end

                ef:Show()
                curY = curY - ENTRY_H - ROW_GAP
            end

            local contentH = math.abs(curY) + POPUP_PAD
            scrollChild:SetSize(POPUP_W, math.max(1, contentH))
            local headerH = popup._headerH or 0
            local scrollH = math.min(contentH, popup._maxH - headerH)
            scrollH = math.max(scrollH, POPUP_PAD)
            popup._scrollFrame:SetHeight(scrollH)
            PP.Size(popup, POPUP_W, headerH + scrollH + POPUP_PAD)
        end

        local function TogglePopup_L(anchor)
            if not popup then BuildPopup_L() end
            if popup:IsShown() then popup:Hide(); return end
            wipe(_tempSpecSel)
            if _specDDRefresh then _specDDRefresh() end
            RefreshPopupEntries_L()
            if popup._scrollFrame then popup._scrollFrame:SetVerticalScroll(0) end
            popup:ClearAllPoints()
            popup:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
            popup:Show()
        end

        settingsBtn:SetScript("OnClick", function(self) TogglePopup_L(self) end)
        settingsBtn:HookScript("OnHide", function()
            if popup and popup:IsShown() then popup:Hide() end
        end)

        return settingsBtn
    end -- BuildThresholdSettingsButton

    local VALID_ANCHOR_TARGETS = EllesmereUI.RESOURCE_BAR_ANCHOR_KEYS or {}

    local function GetAnchorDropdownValue(value)
        if VALID_ANCHOR_TARGETS[value] then
            return value
        end
        return "none"
    end

    ---------------------------------------------------------------------------
    --  Bar Display page
    ---------------------------------------------------------------------------
    local function BuildBarDisplayPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        parent._showRowDivider = true

        -- Shared row references for sync icon flashTargets (populated per section)
        local _syncRows = {}

        -- Bar texture dropdown values (built from _ERB globals)
        -- Re-append SharedMedia textures now (options open later than init,
        -- so SM packs that register textures lazily are available by now).
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(
                _G._ERB_BarTextureNames or {},
                _G._ERB_BarTextureOrder or {},
                nil,
                _G._ERB_BarTextures
            )
        end
        local hbtValues = {}
        local hbtOrder = {}
        do
            local texNames = _G._ERB_BarTextureNames or {}
            local texOrder2 = _G._ERB_BarTextureOrder or {}
            local texLookup = _G._ERB_BarTextures or {}
            for _, key in ipairs(texOrder2) do
                if key ~= "---" then
                    hbtValues[key] = texNames[key] or key
                end
                hbtOrder[#hbtOrder + 1] = key
            end
            hbtValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    return texLookup[key]
                end,
            }
        end

        -- Randomize preview fill each time user navigates to this page
        local minPips = math.floor(5 * 0.50 + 0.5)
        local maxPips = math.floor(5 * 0.75 + 0.5)
        _previewPipCount = math.random(minPips, maxPips)
        _previewBarFillPct = math.random(30, 80)

        EllesmereUI:SetContentHeader(_previewHeaderBuilder)

        -- Populate click mappings for preview hit overlays
        wipe(_clickMappings)

        -----------------------------------------------------------------------
        --  BAR DISPLAY
        -----------------------------------------------------------------------
        local generalSection
        generalSection, h = W:SectionHeader(parent, "BAR DISPLAY", y);  y = y - h

        -- Row 1: Visibility | Visibility Options (checkbox dropdown)
        local visRow
        visRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Visibility",
              values = EllesmereUI.VIS_VALUES,
              order = EllesmereUI.VIS_ORDER,
              getValue = function()
                  local p = DB(); if not p then return "always" end
                  return p.secondary.visibility or "always"
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.visibility = v
                  p.health.visibility = v
                  p.primary.visibility = v
                  Refresh()
                  EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Visibility Options",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end }
        );  y = y - h

        -- Replace the dummy right dropdown with our checkbox dropdown
        do
            local rightRgn = visRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local visItems = EllesmereUI.VIS_OPT_ITEMS
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                visItems,
                function(k)
                    local p = DB(); if not p then return false end
                    return p.secondary[k] or false
                end,
                function(k, v)
                    local p = DB(); if not p then return end
                    p.secondary[k] = v
                    p.health[k] = v
                    p.primary[k] = v
                    Refresh()
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Row 2: Dark Theme | Background Color
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Dark Theme",
              getValue = function()
                  local p = DB(); if not p then return false end
                  return p.health.darkTheme
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.darkTheme = v
                  p.primary.darkTheme = v
                  p.secondary.darkTheme = v
                  if v then
                      p.health.customColored = false
                      p.primary.customColored = false
                  end
                  RebuildHealth(); RebuildPower(); RebuildClass()
                  EllesmereUI:RefreshPage()
              end },
            { type = "colorpicker", text = "Background", hasAlpha = true,
              disabled = function() local p = DB(); return p and p.health.darkTheme end,
              disabledTooltip = "Disable Dark Theme first",
              getValue = function()
                  local p = DB()
                  if not p then return 0x11/255, 0x11/255, 0x11/255, 0.75 end
                  return p.health.bgR, p.health.bgG, p.health.bgB, p.health.bgA
              end,
              setValue = function(r, g, b, a)
                  local p = DB(); if not p then return end
                  p.health.bgR, p.health.bgG, p.health.bgB, p.health.bgA = r, g, b, a
                  p.primary.bgR, p.primary.bgG, p.primary.bgB, p.primary.bgA = r, g, b, a
                  p.secondary.barBgR, p.secondary.barBgG, p.secondary.barBgB, p.secondary.barBgA = r, g, b, a
                  if p.health.darkTheme then p.health.darkTheme = false end
                  if p.primary.darkTheme then p.primary.darkTheme = false end
                  if p.secondary.darkTheme then p.secondary.darkTheme = false end
                  if not p.health.customColored then p.health.customColored = true end
                  if not p.primary.customColored then p.primary.customColored = true end
                  SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Row 3: Texture | (empty)
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Texture", values = hbtValues, order = hbtOrder,
              getValue = function()
                  local p = DB(); if not p then return "none" end
                  return p.general.barTexture or "none"
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.general.barTexture = v; SmoothRefresh()
              end },
            { type = "label", text = "" }
        );  y = y - h

        _, h = W:Spacer(parent, y, 16);  y = y - h

        -----------------------------------------------------------------------
        --  CLASS RESOURCE BAR
        -----------------------------------------------------------------------
        local classSection
        classSection, h = W:SectionHeader(parent, "CLASS RESOURCE BAR", y);  y = y - h

        local classOff = function() local p = DB(); return p and not p.secondary.enabled end

        -- Row 1: Show Class Resource (inline cog: Spacing) | Orientation
        local classEnableRow
        classEnableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Class Resource",
              getValue = function() local p = DB(); return p and p.secondary.enabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.enabled = v; RebuildClass()
                  EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Orientation",
              disabled = classOff,
              disabledTooltip = "Enable Class Resource",
              values = { HORIZONTAL = "Horizontal", VERTICAL_UP = "Vertical Up", VERTICAL_DOWN = "Vertical Down" },
              order  = { "HORIZONTAL", "VERTICAL_UP", "VERTICAL_DOWN" },
              getValue = function()
                  local p = DB(); if not p then return "HORIZONTAL" end
                  local v = p.secondary.pipOrientation or "HORIZONTAL"
                  if v == "VERTICAL" then v = "VERTICAL_DOWN" end
                  return v
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.pipOrientation = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        -- Inline cog on Show Class Resource: Spacing + Hide Power Bar
        do
            local rgn = classEnableRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Class Resource",
                rows = {
                    { type = "slider", label = "Spacing", min = 0, max = 20, step = 1,
                      get = function() local p = DB(); return p and p.secondary.pipSpacing or 3 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.pipSpacing = v; SmoothRefresh()
                      end },
                    { type = "toggle", label = "Hide Power Bar if Resource",
                      get = function() local p = DB(); return p and p.secondary.hidePowerIfResource end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.hidePowerIfResource = v; RebuildClass()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Class Resource"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateClassCogDis()
                local p = DB()
                if p and not p.secondary.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateClassCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateClassCogDis)
            UpdateClassCogDis()
        end

        -- Row 2: (Sync) Height | (Sync) Width
        local classSizeRow
        local chDis, chTip, chRaw = EllesmereUI.MatchGuard("ERB_ClassResource", "Height", classOff, "Enable Class Resource")
        local cwDis, cwTip, cwRaw = EllesmereUI.MatchGuard("ERB_ClassResource", "Width", classOff, "Enable Class Resource")
        classSizeRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 60, step = 1,
              disabled = chDis, disabledTooltip = chTip, rawTooltip = chRaw,
              getValue = function() local p = DB(); return p and p.secondary.pipHeight or 20 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.pipHeight = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Width",
              min = 10, max = 500, step = 1,
              disabled = cwDis, disabledTooltip = cwTip, rawTooltip = cwRaw,
              getValue = function() local p = DB(); return p and p.secondary.pipWidth or 214 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.pipWidth = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        _syncRows.classHeight = classSizeRow._leftRegion
        _syncRows.classWidth  = classSizeRow._rightRegion
        do
            local rgn = classSizeRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Height to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.secondary.pipHeight or 20
                    p.primary.height = v; p.health.height = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.secondary.pipHeight or 20
                    return (p.primary.height or 16) == v and (p.health.height or 20) == v
                end,
                flashTargets = function() return { _syncRows.classHeight, _syncRows.powerHeight, _syncRows.healthHeight } end,
            })
        end
        do
            local rgn = classSizeRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Width to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local totalW = p.secondary.pipWidth or 214
                    p.primary.width = totalW; p.health.width = totalW
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local totalW = p.secondary.pipWidth or 214
                    return (p.primary.width or 220) == totalW and (p.health.width or 220) == totalW
                end,
                flashTargets = function() return { _syncRows.classWidth, _syncRows.powerWidth, _syncRows.healthWidth } end,
            })
        end

        -- Row: Border Style dropdown (+ inline offset cog)
        do
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local classBsRow
            classBsRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style",
                  disabled = classOff,
                  disabledTooltip = "Enable Class Resource",
                  values=texValues, order=texOrder,
                  getValue=function() local p = DB(); return p and p.secondary.borderTexture or "solid" end,
                  setValue=function(v)
                      local p = DB(); if not p then return end
                      p.secondary.borderTexture = v; p.secondary.borderTextureOffset = nil; p.secondary.borderTextureOffsetY = nil; p.secondary.borderTextureShiftX = nil; p.secondary.borderTextureShiftY = nil
                      if v ~= "solid" then
                          p.secondary.borderR = 1; p.secondary.borderG = 1; p.secondary.borderB = 1; p.secondary.borderA = 1
                      else
                          p.secondary.borderR = 0; p.secondary.borderG = 0; p.secondary.borderB = 0; p.secondary.borderA = 1
                      end
                      local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                      if defSz then p.secondary.borderSize = defSz end
                      RebuildClass(); EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Border Size",
                  min = 0, max = 4, step = 1,
                  disabled = classOff,
                  disabledTooltip = "Enable Class Resource",
                  getValue = function() local p = DB(); return p and p.secondary.borderSize or 1 end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.borderSize = v; RebuildClass()
                      EllesmereUI:RefreshPage()
                  end });  y = y - h
            _syncRows.classBorder = classBsRow._rightRegion
            -- Inline color swatch on Border Size (right region)
            do
                local rgn = classBsRow._rightRegion
                local ctrl = rgn._control
                local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, classBsRow:GetFrameLevel() + 3,
                    function()
                        local p = DB()
                        return (p and p.secondary.borderR or 0), (p and p.secondary.borderG or 0),
                               (p and p.secondary.borderB or 0), (p and p.secondary.borderA or 1)
                    end,
                    function(r, g, b, a)
                        local p = DB(); if not p then return end
                        p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA = r, g, b, a
                        SmoothRefresh(); EllesmereUI:RefreshPage()
                    end,
                    true, 20)
                PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch() end)
            end
            do
                local rgn = classBsRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    rows = {
                        { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.secondary.borderTextureOffset
                              if v then return v end
                              local dox = EllesmereUI.GetBorderDefaults("resourcebars", p.secondary.borderTexture or "solid", p.secondary.borderSize or 1)
                              return dox
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.secondary.borderTextureOffset = v; RebuildClass(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.secondary.borderTextureOffsetY
                              if v then return v end
                              local _, doy = EllesmereUI.GetBorderDefaults("resourcebars", p.secondary.borderTexture or "solid", p.secondary.borderSize or 1)
                              return doy
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.secondary.borderTextureOffsetY = v; RebuildClass(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.secondary.borderTextureShiftX
                              if v then return v end
                              local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", p.secondary.borderTexture or "solid", p.secondary.borderSize or 1)
                              return dsx
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.secondary.borderTextureShiftX = v == 0 and nil or v; RebuildClass(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.secondary.borderTextureShiftY
                              if v then return v end
                              local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", p.secondary.borderTexture or "solid", p.secondary.borderSize or 1)
                              return dsy
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.secondary.borderTextureShiftY = v == 0 and nil or v; RebuildClass(); EllesmereUI:RefreshPage()
                          end },
                    },
                })
                local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                local function UpdateCogVis()
                    local p = DB()
                    local tex = p and p.secondary.borderTexture or "solid"
                    if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
            -- Sync icon: Border Style (class -> primary + health)
            EllesmereUI.BuildSyncIcon({
                region  = classBsRow._leftRegion,
                tooltip = "Apply Border Style to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local s = p.secondary
                    local function apply(t)
                        t.borderTexture = s.borderTexture
                        t.borderTextureOffset = s.borderTextureOffset; t.borderTextureOffsetY = s.borderTextureOffsetY
                        t.borderTextureShiftX = s.borderTextureShiftX; t.borderTextureShiftY = s.borderTextureShiftY
                        t.borderR = s.borderR; t.borderG = s.borderG; t.borderB = s.borderB; t.borderA = s.borderA
                        t.borderSize = s.borderSize
                    end
                    apply(p.primary); apply(p.health)
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local bt = p.secondary.borderTexture or "solid"
                    return (p.primary.borderTexture or "solid") == bt and (p.health.borderTexture or "solid") == bt
                end,
                flashTargets = function() return { classBsRow._leftRegion } end,
            })
            -- Sync icon on Border (right region of Border Style row)
            EllesmereUI.BuildSyncIcon({
                region  = classBsRow._rightRegion,
                tooltip = "Apply Border to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local r, g, b, a = p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA
                    local sz = p.secondary.borderSize or 1
                    local bt = p.secondary.borderTexture or "solid"
                    p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA = r, g, b, a
                    p.primary.borderSize = sz; p.primary.borderTexture = bt
                    p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA = r, g, b, a
                    p.health.borderSize = sz; p.health.borderTexture = bt
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local sr, sg, sb, sa, ssz = p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA, p.secondary.borderSize or 1
                    local sbt = p.secondary.borderTexture or "solid"
                    local function eq(t) return t.borderR == sr and t.borderG == sg and t.borderB == sb and t.borderA == sa and (t.borderSize or 1) == ssz and (t.borderTexture or "solid") == sbt end
                    return eq(p.primary) and eq(p.health)
                end,
                flashTargets = function() return { _syncRows.classBorder, _syncRows.powerBorder, _syncRows.healthBorder } end,
            })
        end

        -- Row 4: (Sync) Opacity | Fill Color
        local classBorderRow
        classBorderRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Opacity",
              min = 0, max = 100, step = 5,
              disabled = classOff,
              disabledTooltip = "Enable Class Resource",
              getValue = function() local p = DB(); return math.floor((p and p.secondary.barAlpha or 1) * 100 + 0.5) end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.barAlpha = v / 100; RefreshClass()
                  EllesmereUI:RefreshPage()
              end },
            { type = "multiSwatch", text = "Fill Color",
              disabled = classOff,
              disabledTooltip = "Enable Class Resource",
              swatches = {
                { tooltip = "Custom Colored",
                  hasAlpha = true,
                  getValue = function()
                      local p = DB()
                      if not p then return 0xDB/255, 0xCF/255, 0x37/255, 1 end
                      return p.secondary.fillR, p.secondary.fillG, p.secondary.fillB, p.secondary.fillA
                  end,
                  setValue = function(r, g, b, a)
                      local p = DB(); if not p then return end
                      p.secondary.fillR, p.secondary.fillG, p.secondary.fillB, p.secondary.fillA = r, g, b, a
                      RebuildClass(); SmoothRefresh()
                  end,
                  onClick = function(self)
                      local p = DB(); if not p then return end
                      if p.secondary.classColored ~= false then
                          p.secondary.classColored = false; RebuildClass()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local p = DB()
                      local isClassColored = not p or (p.secondary.classColored ~= false)
                      return isClassColored and 0.3 or 1
                  end },
                { tooltip = "Dynamic Colored",
                  getValue = function()
                      local _, classFile = UnitClass("player")
                      local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                      if cc then return cc.r, cc.g, cc.b, 1 end
                      return 1, 0.82, 0, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      local p = DB(); if not p then return end
                      p.secondary.classColored = true; RebuildClass()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local p = DB()
                      local isClassColored = not p or (p.secondary.classColored ~= false)
                      return isClassColored and 1 or 0.3
                  end },
              } }
        );  y = y - h
        _syncRows.classOpacity = classBorderRow._leftRegion
        -- Sync icon on Opacity
        do
            local rgn = classBorderRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Opacity to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.secondary.barAlpha or 1
                    p.primary.barAlpha = v; p.health.barAlpha = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.secondary.barAlpha or 1
                    return (p.primary.barAlpha or 1) == v and (p.health.barAlpha or 1) == v
                end,
                flashTargets = function() return { _syncRows.classOpacity, _syncRows.powerOpacity, _syncRows.healthOpacity } end,
            })
        end

        -- Row 5: Resource Text | Threshold & Hash Lines
        local classColorRow
        classColorRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Resource Text",
              disabled = classOff,
              disabledTooltip = "Enable Class Resource",
              getValue = function() local p = DB(); return p and p.secondary.showText end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.showText = v; RebuildClass()
                  EllesmereUI:RefreshPage()
              end },
            { type = "label", text = "Threshold & Hash Lines" }
        );  y = y - h
        -- Inline cog for Charged Combo Point color (on Fill Color)
        do
            local rgn = classBorderRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Charged Points",
                rows = {
                    { type = "colorpicker", label = "Charged Color", hasAlpha = false,
                      get = function()
                          local p = DB()
                          if not p then return 0.44, 0.77, 1.00, 1 end
                          return p.secondary.chargedR or 0.44, p.secondary.chargedG or 0.77,
                                 p.secondary.chargedB or 1.00, p.secondary.chargedA or 1
                      end,
                      set = function(cr, cg, cb, ca)
                          local p = DB(); if not p then return end
                          p.secondary.chargedR, p.secondary.chargedG = cr, cg
                          p.secondary.chargedB, p.secondary.chargedA = cb, ca
                          RebuildClass(); SmoothRefresh()
                      end },
                },
                footer = false,
            })
            local chargedCog = MakeCogBtn(rgn, cogShow)
            local chargedCogDis = CreateFrame("Frame", nil, rgn)
            chargedCogDis:SetAllPoints(chargedCog)
            chargedCogDis:SetFrameLevel(chargedCog:GetFrameLevel() + 5)
            chargedCogDis:EnableMouse(true)
            chargedCogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(chargedCog, EllesmereUI.DisabledTooltip("Enable Class Resource"))
            end)
            chargedCogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateChargedCogDis()
                local p = DB()
                if p and not p.secondary.enabled then
                    chargedCogDis:Show(); chargedCog:SetAlpha(0.15)
                else
                    chargedCogDis:Hide(); chargedCog:SetAlpha(0.4)
                end
            end
            chargedCog:HookScript("OnShow", UpdateChargedCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateChargedCogDis)
            UpdateChargedCogDis()
        end
        -- Inline cog (RESIZE) on Resource Text for size + position
        do
            local rgn = classColorRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Resource Count",
                rows = {
                    { type = "slider", label = "Size", min = 8, max = 24, step = 1,
                      get = function() local p = DB(); return p and p.secondary.textSize or 11 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.textSize = v; RefreshClass()
                      end },
                    { type = "slider", label = "X Offset", min = -50, max = 50, step = 1,
                      get = function() local p = DB(); return p and p.secondary.textXOffset or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.textXOffset = v; RefreshClass()
                      end },
                    { type = "slider", label = "Y Offset", min = -50, max = 50, step = 1,
                      get = function() local p = DB(); return p and p.secondary.textYOffset or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.textYOffset = v; RefreshClass()
                      end },
                },
                footer = false,
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Class Resource"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisCount()
                local p = DB()
                if p and not p.secondary.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisCount)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisCount)
            UpdateCogDisCount()
        end

        -- Settings button + popup on Threshold & Hash Lines (row 5 slot 2)
        do
            local settingsRgn = classColorRow._rightRegion
            local CLOSE_ICON_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
            local POPUP_W = 410
            local POPUP_PAD = 14
            local ROW_GAP = 6
            local EG = EllesmereUI.ELLESMERE_GREEN

            -- bar-type spec lookup
            local barTypeSpecs = _G._ERB_BAR_TYPE_SPECS or {}
            local function IsSpecBarType(specID)
                if specID == 0 then return IsBarTypeSecondary() end
                return barTypeSpecs[specID] or false
            end
            local function IsEntryBarType(entry)
                if not entry or not entry.specIDs or #entry.specIDs == 0 then return false end
                return IsSpecBarType(entry.specIDs[1])
            end
            local function SpecName(specID)
                if specID == 0 then return "All Specs" end
                local _, name, _, _, _, _, className = GetSpecializationInfoByID(specID)
                if name and className then return name .. " " .. className end
                return name or ("Spec " .. specID)
            end
            local function EntryLabel(entry)
                if not entry or not entry.specIDs or #entry.specIDs == 0 then return "Unknown" end
                if entry.specIDs[1] == 0 then return "All Specs" end
                local names = {}
                for _, sid in ipairs(entry.specIDs) do names[#names + 1] = SpecName(sid) end
                return table.concat(names, ", ")
            end

            ---------------------------------------------------------------
            --  Settings Button (party-mode keybind style)
            ---------------------------------------------------------------
            local BTN_W, BTN_H = 140, 30
            local settingsBtn = CreateFrame("Button", nil, settingsRgn)
            PP.Size(settingsBtn, BTN_W, BTN_H)
            PP.Point(settingsBtn, "RIGHT", settingsRgn, "RIGHT", -20, 0)
            settingsBtn:SetFrameLevel(settingsRgn:GetFrameLevel() + 2)
            local btnBg = EllesmereUI.SolidTex(settingsBtn, "BACKGROUND",
                EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            btnBg:SetAllPoints()
            settingsBtn._border = EllesmereUI.MakeBorder(settingsBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
            local btnLbl = EllesmereUI.MakeFont(settingsBtn, 13, nil, 1, 1, 1)
            btnLbl:SetAlpha(EllesmereUI.DD_TXT_A)
            btnLbl:SetPoint("CENTER")
            btnLbl:SetText("Settings")
            settingsBtn:SetScript("OnEnter", function(self)
                btnBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
                if self._border and self._border.SetColor then self._border:SetColor(1, 1, 1, 0.3) end
            end)
            settingsBtn:SetScript("OnLeave", function(self)
                btnBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                if self._border and self._border.SetColor then self._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A) end
            end)
            -- disabled overlay
            local btnDis = CreateFrame("Frame", nil, settingsRgn)
            btnDis:SetAllPoints(settingsBtn)
            btnDis:SetFrameLevel(settingsBtn:GetFrameLevel() + 5)
            btnDis:EnableMouse(true)
            btnDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(settingsBtn, EllesmereUI.DisabledTooltip("Enable Class Resource"))
            end)
            btnDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBtnDis()
                local p = DB()
                if p and not p.secondary.enabled then btnDis:Show() else btnDis:Hide() end
            end
            settingsBtn:HookScript("OnShow", UpdateBtnDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateBtnDis)
            UpdateBtnDis()

            ---------------------------------------------------------------
            --  Popup Frame (lazy-created)
            ---------------------------------------------------------------
            local popup
            local _entryFrames = {}  -- pool of entry UI frames
            local _tempSpecSel = {}  -- transient dropdown selection
            local _specDDRefresh     -- set after dropdown creation

            -- Build the spec items list for the dropdown
            local CR_ROLE_HEALERS = -1
            local CR_ROLE_TANKS   = -2
            local CR_ROLE_DPS     = -3
            local _crRoleCache = {}

            local function IsCRSpecClaimed(specID)
                local p = DB()
                local sec = p and p.secondary
                if not sec or not sec.thresholdSpecs then return false end
                for _, entry in ipairs(sec.thresholdSpecs) do
                    if entry.specIDs then
                        for _, sid in ipairs(entry.specIDs) do
                            if sid == 0 then return true end
                            if sid == specID then return true end
                        end
                    end
                end
                return false
            end
            local function HasCRAllSpecs()
                local p = DB()
                local sec = p and p.secondary
                if not sec or not sec.thresholdSpecs then return false end
                for _, entry in ipairs(sec.thresholdSpecs) do
                    if entry.specIDs then
                        for _, sid in ipairs(entry.specIDs) do
                            if sid == 0 then return true end
                        end
                    end
                end
                return false
            end

            local function BuildSpecItems()
                local items = {}
                items[#items + 1] = { key = 0, label = "All Specs", isAction = true, lockedFn = HasCRAllSpecs }

                local classList = {}
                for classID = 1, (GetNumClasses and GetNumClasses() or 13) do
                    local className, classFile = GetClassInfo(classID)
                    if className then
                        classList[#classList + 1] = { classID = classID, className = className }
                    end
                end
                table.sort(classList, function(a, b) return a.className < b.className end)

                local healers, tanks, dps = {}, {}, {}
                for _, cls in ipairs(classList) do
                    items[#items + 1] = { isHeader = true, label = cls.className }
                    local numSpecs = GetNumSpecializationsForClassID(cls.classID) or 0
                    for specIndex = 1, numSpecs do
                        local specID, specName, _, _, role = GetSpecializationInfoForClassID(cls.classID, specIndex)
                        if specID and specName then
                            local sid = specID
                            items[#items + 1] = { key = specID, label = specName, lockedFn = function() return IsCRSpecClaimed(sid) end }
                            if role == "HEALER" then healers[#healers + 1] = specID
                            elseif role == "TANK" then tanks[#tanks + 1] = specID
                            else dps[#dps + 1] = specID end
                        end
                    end
                end
                _crRoleCache[CR_ROLE_HEALERS] = healers
                _crRoleCache[CR_ROLE_TANKS] = tanks
                _crRoleCache[CR_ROLE_DPS] = dps
                return items
            end

            -- Forward declarations for popup internals
            local RefreshPopupEntries

            local function MakeCheckbox(parentF, size)
                local cb = CreateFrame("Button", nil, parentF)
                cb:SetSize(size, size)
                local cbBg = cb:CreateTexture(nil, "BACKGROUND")
                cbBg:SetAllPoints()
                cbBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                local cbCheck = cb:CreateTexture(nil, "OVERLAY")
                cbCheck:SetSize(size - 4, size - 4)
                cbCheck:SetPoint("CENTER")
                cbCheck:SetColorTexture(EG.r, EG.g, EG.b, 1)
                cbCheck:Hide()
                cb._check = cbCheck
                cb.SetChecked = function(self, val) if val then cbCheck:Show() else cbCheck:Hide() end end
                cb.GetChecked = function(self) return cbCheck:IsShown() end
                return cb
            end

            local function BuildPopup()
                popup = CreateFrame("Frame", "EUI_ThreshSpecPopup", UIParent)
                popup:SetFrameStrata("DIALOG")
                popup:SetFrameLevel(200)
                popup:SetClampedToScreen(true)
                popup:EnableMouse(true)
                popup:SetScale(0.85)
                popup:Hide()
                PP.Size(popup, POPUP_W, 300) -- height updated dynamically

                local bg = popup:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetColorTexture(0.06, 0.08, 0.10, 0.95)
                PP.CreateBorder(popup, 1, 1, 1, 0.15, 1, "BORDER", 7)

                -- click-outside-to-close
                local clickCatcher = CreateFrame("Button", nil, popup)
                clickCatcher:SetFrameStrata("DIALOG")
                clickCatcher:SetFrameLevel(popup:GetFrameLevel() - 1)
                clickCatcher:SetAllPoints(UIParent)
                clickCatcher:SetScript("OnClick", function() popup:Hide() end)
                clickCatcher:Hide()
                popup:SetScript("OnShow", function() clickCatcher:Show() end)
                popup:SetScript("OnHide", function() clickCatcher:Hide() end)

                -- register popup for scale tracking
                if EllesmereUI._popupFrames then
                    EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = popup }
                end

                local curY = -POPUP_PAD

                -- Title
                local titleFS = EllesmereUI.MakeFont(popup, 13, nil, 1, 1, 1)
                titleFS:SetAlpha(0.55)
                titleFS:SetPoint("TOP", popup, "TOP", 0, curY)
                titleFS:SetText("Threshold & Hash Lines")
                curY = curY - 25

                -- Centered container for dropdown + Add button
                local DD_W, ADD_W, GAP = 220, 90, 10
                local rowW = DD_W + GAP + ADD_W
                local ddRow = CreateFrame("Frame", nil, popup)
                ddRow:SetSize(rowW, 30)
                ddRow:SetPoint("TOP", popup, "TOP", 0, curY)
                ddRow:SetFrameLevel(popup:GetFrameLevel() + 5)

                -- Spec dropdown (checkbox multi-select with search)
                local specItems = BuildSpecItems()
                local specDDHost = CreateFrame("Frame", nil, ddRow)
                specDDHost:SetSize(DD_W, 30)
                specDDHost:SetPoint("LEFT", ddRow, "LEFT", 0, 0)
                specDDHost:SetFrameLevel(ddRow:GetFrameLevel())

                local cbDD, cbDDRefresh  -- forward-declare for closure access
                cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                    specDDHost, DD_W, specDDHost:GetFrameLevel() + 2,
                    specItems,
                    function(key)
                        if key == CR_ROLE_HEALERS or key == CR_ROLE_TANKS or key == CR_ROLE_DPS then return false end
                        return _tempSpecSel[key] or false
                    end,
                    function(key, val)
                        local crRoleSpecs = _crRoleCache[key]
                        if crRoleSpecs then
                            wipe(_tempSpecSel)
                            for _, sid in ipairs(crRoleSpecs) do _tempSpecSel[sid] = true end
                            cbDD:Click()
                            if cbDDRefresh then cbDDRefresh() end
                            return
                        end
                        if key == 0 then
                            wipe(_tempSpecSel)
                            _tempSpecSel[0] = true
                            cbDD:Click()
                            if cbDDRefresh then cbDDRefresh() end
                            return
                        end
                        if val then
                            _tempSpecSel[0] = nil
                            _tempSpecSel[key] = true
                        else
                            _tempSpecSel[key] = nil
                        end
                        if cbDDRefresh then cbDDRefresh() end
                    end,
                    nil, 10, true
                )
                PP.Point(cbDD, "LEFT", specDDHost, "LEFT", 0, 0)
                -- Reduce dropdown label font by 2px
                for _, rgn2 in ipairs({ cbDD:GetRegions() }) do
                    if rgn2.SetFont and rgn2.GetText then
                        local f, _, fl = rgn2:GetFont(); if f then rgn2:SetFont(f, 11, fl or "") end; break
                    end
                end

                -- Replace "None" with placeholder text on the dropdown label
                local _origRefresh = cbDDRefresh
                local function WrappedRefresh()
                    _origRefresh()
                    local regions = { cbDD:GetRegions() }
                    for _, rgn2 in ipairs(regions) do
                        if rgn2.GetText and rgn2:GetText() == "None" then
                            rgn2:SetText("Select a Spec...")
                            break
                        end
                    end
                end
                _specDDRefresh = WrappedRefresh
                WrappedRefresh()

                -- Add Specs button (Reload UI footer style)
                local addBtn = CreateFrame("Button", nil, ddRow)
                PP.Size(addBtn, ADD_W, 30)
                addBtn:SetPoint("LEFT", specDDHost, "RIGHT", GAP, 0)
                addBtn:SetFrameLevel(ddRow:GetFrameLevel() + 2)
                local addBg = EllesmereUI.SolidTex(addBtn, "BACKGROUND", 0.05, 0.07, 0.09, 0.92)
                addBg:SetAllPoints()
                addBtn._border = EllesmereUI.MakeBorder(addBtn, 1, 1, 1, 0.4, PP)
                local addLbl = EllesmereUI.MakeFont(addBtn, 11, nil, 1, 1, 1)
                addLbl:SetAlpha(0.5)
                addLbl:SetPoint("CENTER")
                addLbl:SetText("Add Specs")
                addBtn:SetScript("OnEnter", function()
                    addLbl:SetAlpha(0.7)
                    if addBtn._border and addBtn._border.SetColor then addBtn._border:SetColor(1, 1, 1, 0.6) end
                end)
                addBtn:SetScript("OnLeave", function()
                    addLbl:SetAlpha(0.5)
                    if addBtn._border and addBtn._border.SetColor then addBtn._border:SetColor(1, 1, 1, 0.4) end
                end)
                addBtn:SetScript("OnClick", function()
                    local p = DB(); if not p then return end
                    -- collect selected specIDs
                    local ids = {}
                    if _tempSpecSel[0] then
                        ids[1] = 0
                    else
                        for sid in pairs(_tempSpecSel) do
                            if sid ~= 0 then ids[#ids + 1] = sid end
                        end
                    end
                    if #ids == 0 then return end
                    -- ensure thresholdSpecs exists
                    if not p.secondary.thresholdSpecs then p.secondary.thresholdSpecs = {} end
                    local isBar = IsSpecBarType(ids[1])
                    local p2 = p.secondary
                    local newEntry = {
                        specIDs = ids,
                        hashValues = "",
                        hashWidth = 1,
                        hashColorR = 1, hashColorG = 1, hashColorB = 1, hashColorA = 0.7,
                        thresholdEnabled = true,
                        thresholdCount = isBar and 30 or 3,
                        thresholdPartialOnly = false,
                        thresholdR = p2.thresholdR or 0x0c/255,
                        thresholdG = p2.thresholdG or 0xd2/255,
                        thresholdB = p2.thresholdB or 0x9d/255,
                        thresholdA = p2.thresholdA or 1,
                    }
                    p.secondary.thresholdSpecs[#p.secondary.thresholdSpecs + 1] = newEntry
                    wipe(_tempSpecSel)
                    if WrappedRefresh then WrappedRefresh() end
                    RefreshPopupEntries()
                    RefreshClass()
                end)

                curY = curY - 36

                -------------------------------------------------------
                --  Scrollable entry container
                -------------------------------------------------------
                local POPUP_MAX_H = 375
                local headerH = math.abs(curY)  -- height consumed by title+dropdown row

                local scrollFrame = CreateFrame("ScrollFrame", nil, popup)
                scrollFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, curY)
                scrollFrame:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, curY)
                scrollFrame:SetFrameLevel(popup:GetFrameLevel() + 1)

                local scrollChild = CreateFrame("Frame", nil, scrollFrame)
                scrollChild:SetWidth(POPUP_W)
                scrollFrame:SetScrollChild(scrollChild)

                -- Thin scrollbar track + thumb
                local scrollBar = CreateFrame("Frame", nil, popup)
                scrollBar:SetWidth(4)
                scrollBar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -3, curY)
                scrollBar:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -3, 4)
                scrollBar:SetFrameLevel(popup:GetFrameLevel() + 10)
                scrollBar:Hide()
                local scrollTrack = scrollBar:CreateTexture(nil, "BACKGROUND")
                scrollTrack:SetAllPoints()
                scrollTrack:SetColorTexture(1, 1, 1, 0.04)
                local scrollThumb = scrollBar:CreateTexture(nil, "OVERLAY")
                scrollThumb:SetWidth(4)
                scrollThumb:SetColorTexture(1, 1, 1, 0.15)
                scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, 0)
                scrollThumb:SetHeight(30)

                scrollFrame:SetScript("OnMouseWheel", function(self, delta)
                    local maxScroll = self:GetVerticalScrollRange()
                    if maxScroll <= 0 then return end
                    local cur = self:GetVerticalScroll()
                    local step = 30
                    self:SetVerticalScroll(math.max(0, math.min(maxScroll, cur - delta * step)))
                end)
                scrollFrame:SetScript("OnScrollRangeChanged", function(self, _, yRange)
                    if not yRange or yRange <= 0 then
                        scrollBar:Hide()
                        return
                    end
                    scrollBar:Show()
                    local barH = scrollBar:GetHeight()
                    if barH <= 0 then return end
                    local thumbH = math.max(20, barH * (self:GetHeight() / (self:GetHeight() + yRange)))
                    scrollThumb:SetHeight(thumbH)
                end)
                scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
                    local maxScroll = self:GetVerticalScrollRange()
                    if maxScroll <= 0 then return end
                    local barH = scrollBar:GetHeight()
                    local thumbH = scrollThumb:GetHeight()
                    local travel = barH - thumbH
                    local frac = offset / maxScroll
                    scrollThumb:ClearAllPoints()
                    scrollThumb:SetPoint("TOP", scrollBar, "TOP", 0, -travel * frac)
                end)

                popup._scrollFrame = scrollFrame
                popup._scrollChild = scrollChild
                popup._headerH = headerH
                popup._maxH = POPUP_MAX_H
            end -- BuildPopup

            ---------------------------------------------------------------
            --  Build/Refresh dynamic entry frames
            ---------------------------------------------------------------
            RefreshPopupEntries = function()
                if not popup then return end
                local p = DB(); if not p then return end
                local sp = p.secondary
                if not sp.thresholdSpecs then sp.thresholdSpecs = {} end
                local entries = sp.thresholdSpecs

                local scrollChild = popup._scrollChild
                local curY = 0  -- relative to scrollChild top
                local ENTRY_W = POPUP_W - POPUP_PAD * 2
                local LINE_H = 26

                -- hide all existing entry frames
                for i = 1, #_entryFrames do
                    if _entryFrames[i] then _entryFrames[i]:Hide() end
                end

                for idx, entry in ipairs(entries) do
                    local ef = _entryFrames[idx]
                    if not ef then
                        ef = CreateFrame("Frame", nil, scrollChild)
                        ef:SetFrameLevel(popup:GetFrameLevel() + 2)
                        _entryFrames[idx] = ef

                        -- entry background
                        local entBg = ef:CreateTexture(nil, "BACKGROUND")
                        entBg:SetAllPoints()
                        entBg:SetColorTexture(1, 1, 1, 0.02)
                        ef._bg = entBg

                        -- delete button
                        local delBtn = CreateFrame("Button", nil, ef)
                        delBtn:SetSize(14, 14)
                        delBtn:SetPoint("TOPRIGHT", ef, "TOPRIGHT", -6, -9)
                        delBtn:SetFrameLevel(ef:GetFrameLevel() + 3)
                        local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                        delIcon:SetAllPoints()
                        delIcon:SetTexture(CLOSE_ICON_PATH)
                        delIcon:SetAlpha(0.4)
                        delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
                        delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
                        ef._delBtn = delBtn

                        -- spec group label (class-colored)
                        local specLbl = EllesmereUI.MakeFont(ef, 14, nil, 1, 1, 1)
                        specLbl:SetAlpha(0.85)
                        specLbl:SetPoint("TOPLEFT", ef, "TOPLEFT", 8, -9)
                        specLbl:SetPoint("RIGHT", ef, "RIGHT", -26, 0)
                        specLbl:SetJustifyH("LEFT")
                        specLbl:SetWordWrap(false)
                        ef._specLbl = specLbl

                        -- Hash row: "Hash at X" label + hint + input + cog
                        local hashLbl = EllesmereUI.MakeFont(ef, 13, nil, 1, 1, 1)
                        hashLbl:SetAlpha(0.6)
                        hashLbl:SetPoint("TOPLEFT", ef, "TOPLEFT", 8, -33)
                        ef._hashLbl = hashLbl

                        local hashHint = EllesmereUI.MakeFont(ef, 10, nil, 1, 1, 1)
                        hashHint:SetAlpha(0.35)
                        hashHint:SetPoint("LEFT", hashLbl, "RIGHT", 4, 0)
                        ef._hashHint = hashHint

                        local hashInput = CreateFrame("EditBox", nil, ef)
                        hashInput:SetSize(100, 22)
                        hashInput:SetPoint("LEFT", hashHint, "RIGHT", 8, 0)
                        hashInput:SetFrameLevel(ef:GetFrameLevel() + 3)
                        hashInput:SetAutoFocus(false)
                        hashInput:SetFontObject(GameFontHighlightSmall)
                        local hiFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"
                        hashInput:SetFont(hiFont, 12, "")
                        hashInput:SetTextColor(1, 1, 1, 0.75)
                        hashInput:SetJustifyH("CENTER")
                        local hiBg = hashInput:CreateTexture(nil, "BACKGROUND")
                        hiBg:SetAllPoints()
                        hiBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                        EllesmereUI.MakeBorder(hashInput, 1, 1, 1, 0.08, PP)
                        ef._hashInput = hashInput

                        -- Hash cog: width slider + color swatch
                        local hashCogFrame, hashCogShow = EllesmereUI.BuildCogPopup({
                            title = "Hash Line Style", bgAlpha = 1, frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
                            rows = {
                                { type = "slider", label = "Hash Width", min = 1, max = 4, step = 1,
                                  get = function()
                                      if not ef._entryIdx then return 1 end
                                      local p2 = DB(); if not p2 then return 1 end
                                      local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[ef._entryIdx]
                                      return ent and ent.hashWidth or 1
                                  end,
                                  set = function(v)
                                      if not ef._entryIdx then return end
                                      local p2 = DB(); if not p2 then return end
                                      local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[ef._entryIdx]
                                      if ent then ent.hashWidth = v; RebuildClass() end
                                  end },
                                { type = "colorpicker", label = "Hash Color", hasAlpha = true,
                                  get = function()
                                      if not ef._entryIdx then return 1, 1, 1, 0.7 end
                                      local p2 = DB(); if not p2 then return 1, 1, 1, 0.7 end
                                      local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[ef._entryIdx]
                                      if not ent then return 1, 1, 1, 0.7 end
                                      return ent.hashColorR or 1, ent.hashColorG or 1, ent.hashColorB or 1, ent.hashColorA or 0.7
                                  end,
                                  set = function(r, g, b, a)
                                      if not ef._entryIdx then return end
                                      local p2 = DB(); if not p2 then return end
                                      local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[ef._entryIdx]
                                      if ent then
                                          ent.hashColorR, ent.hashColorG, ent.hashColorB, ent.hashColorA = r, g, b, a
                                          RebuildClass()
                                      end
                                  end },
                            },
                        })
                        local hashCogBtn = CreateFrame("Button", nil, ef)
                        hashCogBtn:SetSize(20, 20)
                        hashCogBtn:SetPoint("LEFT", hashInput, "RIGHT", 6, 0)
                        hashCogBtn:SetFrameLevel(ef:GetFrameLevel() + 5)
                        hashCogBtn:SetAlpha(0.4)
                        local hashCogTex = hashCogBtn:CreateTexture(nil, "OVERLAY")
                        hashCogTex:SetAllPoints()
                        hashCogTex:SetTexture(EllesmereUI.COGS_ICON)
                        hashCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                        hashCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                        hashCogBtn:SetScript("OnClick", function(self) hashCogShow(self) end)
                        ef._hashCogBtn = hashCogBtn

                        -- Threshold row: label + input + swatch + toggle + cog
                        local threshLbl2 = EllesmereUI.MakeFont(ef, 13, nil, 1, 1, 1)
                        threshLbl2:SetAlpha(0.6)
                        threshLbl2:SetPoint("TOPLEFT", ef, "TOPLEFT", 8, -61)
                        threshLbl2:SetText("Threshold")
                        ef._threshLbl = threshLbl2

                        local threshInput = CreateFrame("EditBox", nil, ef)
                        threshInput:SetSize(50, 22)
                        threshInput:SetPoint("LEFT", threshLbl2, "RIGHT", 8, 0)
                        threshInput:SetFrameLevel(ef:GetFrameLevel() + 3)
                        threshInput:SetAutoFocus(false)
                        threshInput:SetFontObject(GameFontHighlightSmall)
                        local tiFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"
                        threshInput:SetFont(tiFont, 12, "")
                        threshInput:SetTextColor(1, 1, 1, 0.75)
                        threshInput:SetJustifyH("CENTER")
                        threshInput:SetNumeric(true)
                        local tiBg = threshInput:CreateTexture(nil, "BACKGROUND")
                        tiBg:SetAllPoints()
                        tiBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                        EllesmereUI.MakeBorder(threshInput, 1, 1, 1, 0.08, PP)
                        ef._threshInput = threshInput

                        -- Inline color swatch (after threshold input)
                        local entrySwatch, entrySwatchSnap = EllesmereUI.BuildColorSwatch(ef, ef:GetFrameLevel() + 4,
                            function()
                                if not ef._entryIdx then return 0x0c/255, 0xd2/255, 0x9d/255, 1 end
                                local p2 = DB(); if not p2 then return 0x0c/255, 0xd2/255, 0x9d/255, 1 end
                                local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[ef._entryIdx]
                                if not ent then return p2.secondary.thresholdR or 0x0c/255, p2.secondary.thresholdG or 0xd2/255, p2.secondary.thresholdB or 0x9d/255, p2.secondary.thresholdA or 1 end
                                return ent.thresholdR or p2.secondary.thresholdR or 0x0c/255,
                                       ent.thresholdG or p2.secondary.thresholdG or 0xd2/255,
                                       ent.thresholdB or p2.secondary.thresholdB or 0x9d/255,
                                       ent.thresholdA or p2.secondary.thresholdA or 1
                            end,
                            function(r, g, b, a)
                                if not ef._entryIdx then return end
                                local p2 = DB(); if not p2 then return end
                                local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[ef._entryIdx]
                                if ent then
                                    ent.thresholdR, ent.thresholdG, ent.thresholdB, ent.thresholdA = r, g, b, a
                                    SmoothRefresh()
                                end
                            end, true, 19)
                        entrySwatch:SetPoint("LEFT", threshInput, "RIGHT", 8, 0)
                        ef._entrySwatch = entrySwatch
                        ef._entrySwatchSnap = entrySwatchSnap

                        -- Inline threshold toggle (after swatch)
                        local entryToggle, _, entrySnap = EllesmereUI.BuildToggleControl(
                            ef, ef:GetFrameLevel() + 4,
                            function()
                                if not ef._entryIdx then return false end
                                local p2 = DB(); if not p2 then return false end
                                local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[ef._entryIdx]
                                if not ent then return false end
                                if ent.thresholdEnabled == nil then return true end
                                return ent.thresholdEnabled
                            end,
                            function(v)
                                if not ef._entryIdx then return end
                                local p2 = DB(); if not p2 then return end
                                local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[ef._entryIdx]
                                if ent then ent.thresholdEnabled = v; RefreshClass() end
                                if RefreshPopupEntries then RefreshPopupEntries() end
                            end,
                            { sizeRatio = 0.95 }
                        )
                        entryToggle:SetPoint("LEFT", entrySwatch, "RIGHT", 6, 0)
                        ef._entryToggle = entryToggle
                        ef._entrySnap = entrySnap

                        -- Cog button for threshold partial coloring (25% smaller, after toggle)
                        local entryCogFrame, entryCogShow = EllesmereUI.BuildCogPopup({
                            title = "Threshold Coloring", bgAlpha = 1, frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
                            rows = {
                                { type = "toggle", label = "Only Color At/Above Threshold",
                                  get = function()
                                      if not ef._entryIdx then return false end
                                      local p2 = DB(); if not p2 then return false end
                                      local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[ef._entryIdx]
                                      return ent and ent.thresholdPartialOnly
                                  end,
                                  set = function(v)
                                      if not ef._entryIdx then return end
                                      local p2 = DB(); if not p2 then return end
                                      local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[ef._entryIdx]
                                      if ent then ent.thresholdPartialOnly = v; RefreshClass() end
                                  end },
                            },
                        })
                        local cogBtn2 = CreateFrame("Button", nil, ef)
                        cogBtn2:SetSize(20, 20)
                        cogBtn2:SetPoint("LEFT", entryToggle, "RIGHT", 6, 0)
                        cogBtn2:SetFrameLevel(ef:GetFrameLevel() + 5)
                        cogBtn2:SetAlpha(0.4)
                        local cogTex2 = cogBtn2:CreateTexture(nil, "OVERLAY")
                        cogTex2:SetAllPoints()
                        cogTex2:SetTexture(EllesmereUI.COGS_ICON)
                        cogBtn2:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                        cogBtn2:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
                        cogBtn2:SetScript("OnClick", function(self) entryCogShow(self) end)
                        ef._cogBtn = cogBtn2

                        -- Disabled overlay for threshold row (excludes toggle so it stays clickable)
                        local threshDis = CreateFrame("Frame", nil, ef)
                        threshDis:SetPoint("TOPLEFT", threshLbl2, "TOPLEFT", -2, 4)
                        threshDis:SetPoint("BOTTOMRIGHT", entryToggle, "BOTTOMLEFT", -4, -4)
                        threshDis:SetFrameLevel(ef:GetFrameLevel() + 6)
                        threshDis:EnableMouse(true)
                        local threshDisTex = threshDis:CreateTexture(nil, "OVERLAY")
                        threshDisTex:SetAllPoints()
                        threshDisTex:SetColorTexture(0.06, 0.08, 0.10, 0.7)
                        threshDis:SetScript("OnEnter", function()
                            EllesmereUI.ShowWidgetTooltip(threshDis, EllesmereUI.DisabledTooltip("Threshold Color"))
                        end)
                        threshDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                        ef._threshDis = threshDis
                    end -- end entry frame creation

                    -- Position and populate entry
                    local isBar = IsEntryBarType(entry)
                    local ENTRY_H = 89
                    ef:SetSize(ENTRY_W, ENTRY_H)
                    ef:ClearAllPoints()
                    ef:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", POPUP_PAD, curY)
                    ef._entryIdx = idx

                    -- spec label
                    ef._specLbl:SetText(EntryLabel(entry))
                    -- Class-color the spec label from the first specID
                    do
                        local firstSID = entry.specIDs and entry.specIDs[1]
                        local classFile
                        if firstSID == 0 then
                            local _, cf = UnitClass("player")
                            classFile = cf
                        elseif firstSID then
                            local _, _, _, _, _, cf = GetSpecializationInfoByID(firstSID)
                            classFile = cf
                        end
                        local cc = classFile and CLASS_COLORS[classFile]
                        if cc then
                            ef._specLbl:SetTextColor(cc[1], cc[2], cc[3], 1)
                        else
                            ef._specLbl:SetTextColor(1, 1, 1, 1)
                        end
                    end

                    -- delete button
                    ef._delBtn:SetScript("OnClick", function()
                        local p2 = DB(); if not p2 then return end
                        table.remove(p2.secondary.thresholdSpecs, idx)
                        RefreshPopupEntries()
                        RefreshClass()
                    end)

                    -- hash label + hint + input
                    local hashWord = isBar and "Percent" or "Stack"
                    ef._hashLbl:SetText("Hash at " .. hashWord)
                    ef._hashHint:SetText(isBar and "(Ex: 25,50,75)" or "(Ex: 2,4)")
                    ef._hashInput:SetText(entry.hashValues or "")
                    ef._hashInput:SetScript("OnEnterPressed", function(self)
                        local p2 = DB(); if not p2 then return end
                        local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[idx]
                        if ent then
                            ent.hashValues = self:GetText()
                            RebuildClass()
                        end
                        self:ClearFocus()
                    end)
                    ef._hashInput:SetScript("OnEscapePressed", function(self)
                        local p2 = DB(); if not p2 then return end
                        local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[idx]
                        self:SetText(ent and ent.hashValues or "")
                        self:ClearFocus()
                    end)

                    -- threshold input
                    local threshMax = isBar and 100 or 10
                    ef._threshInput:SetText(tostring(entry.thresholdCount or (isBar and 30 or 3)))
                    ef._threshInput:SetScript("OnEnterPressed", function(self)
                        local val = tonumber(self:GetText())
                        if not val then self:SetText(tostring(entry.thresholdCount or 3)); self:ClearFocus(); return end
                        val = math.max(1, math.min(threshMax, math.floor(val + 0.5)))
                        self:SetText(tostring(val))
                        local p2 = DB(); if not p2 then return end
                        local ent = p2.secondary.thresholdSpecs and p2.secondary.thresholdSpecs[idx]
                        if ent then ent.thresholdCount = val; RefreshClass() end
                        self:ClearFocus()
                    end)
                    ef._threshInput:SetScript("OnEscapePressed", function(self)
                        self:SetText(tostring(entry.thresholdCount or (isBar and 30 or 3)))
                        self:ClearFocus()
                    end)

                    -- Refresh per-entry toggle + swatch
                    if ef._entrySnap then ef._entrySnap() end
                    if ef._entrySwatchSnap then ef._entrySwatchSnap() end

                    -- Show/hide threshold disabled overlay based on per-entry toggle
                    local entEnabled = entry.thresholdEnabled
                    if entEnabled == nil then entEnabled = true end
                    if not entEnabled then
                        ef._threshDis:Show()
                    else
                        ef._threshDis:Hide()
                    end

                    ef:Show()
                    curY = curY - ENTRY_H - ROW_GAP
                end

                -- Size the scroll child to fit all entries
                local contentH = math.abs(curY) + POPUP_PAD
                scrollChild:SetSize(POPUP_W, math.max(1, contentH))

                -- Clamp popup height: header + content, max POPUP_MAX_H
                local headerH = popup._headerH or 0
                local scrollH = math.min(contentH, popup._maxH - headerH)
                scrollH = math.max(scrollH, POPUP_PAD)
                popup._scrollFrame:SetHeight(scrollH)

                local totalH = headerH + scrollH + POPUP_PAD
                PP.Size(popup, POPUP_W, totalH)
            end

            ---------------------------------------------------------------
            --  Show/Hide popup
            ---------------------------------------------------------------
            local function TogglePopup(anchor)
                if not popup then BuildPopup() end
                if popup:IsShown() then
                    popup:Hide()
                    return
                end
                wipe(_tempSpecSel)
                if _specDDRefresh then _specDDRefresh() end
                RefreshPopupEntries()
                if popup._scrollFrame then popup._scrollFrame:SetVerticalScroll(0) end
                popup:ClearAllPoints()
                popup:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
                popup:Show()
            end

            settingsBtn:SetScript("OnClick", function(self) TogglePopup(self) end)

            -- Close popup when the settings button hides (page switch or main panel close)
            settingsBtn:HookScript("OnHide", function()
                if popup and popup:IsShown() then popup:Hide() end
            end)
        end

        -- Row: Anchor to Cursor | Cursor Position (cog: X + Y)
        do
            local _, cursorH = EllesmereUI.BuildCursorAnchorRow({
                W = W, parent = parent, y = y,
                getData = function() local p = DB(); return p and p.secondary or {} end,
                onApply = function() RebuildClass(); SmoothRefresh() end,
                makeCogBtn = MakeCogBtn,
                disabledFn = function() local p = DB(); return p and not p.secondary.enabled end,
                disabledTip = "Enable Class Resource",
            })
            y = y - cursorH
        end

        -- Row: Simple Runes (DK only)
        do
            local _, playerClass = UnitClass("player")
            if playerClass == "DEATHKNIGHT" then
                local simpleRuneRow
                simpleRuneRow, h = W:DualRow(parent, y,
                    { type = "toggle", text = "Simple Runes",
                      disabled = function() local p = DB(); return p and not p.secondary.enabled end,
                      disabledTooltip = "Enable Class Resource",
                      getValue = function() local p = DB(); return p and p.secondary.runesSimple end,
                      setValue = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.runesSimple = v
                          RebuildClass()
                      end },
                    { type = "label", text = "" }); y = y - h
            end
        end

        _, h = W:Spacer(parent, y, 16);  y = y - h

        -----------------------------------------------------------------------
        --  POWER BAR
        -----------------------------------------------------------------------
        local powerSection
        powerSection, h = W:SectionHeader(parent, "POWER BAR", y);  y = y - h

        local powerOff = function()
            local p = DB(); return p and not p.primary.enabled
        end
        local powerDisTip = "Enable Power Bar"

        -- Row 1: Show Power Bar | Orientation
        local powerEnableRow
        powerEnableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Power Bar",
              getValue = function() local p = DB(); return p and p.primary.enabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.enabled = v; RebuildPower()
                  EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Orientation",
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              values = { HORIZONTAL = "Horizontal", VERTICAL_UP = "Vertical Up", VERTICAL_DOWN = "Vertical Down" },
              order = { "HORIZONTAL", "VERTICAL_UP", "VERTICAL_DOWN" },
              getValue = function()
                  local p = DB(); if not p then return "HORIZONTAL" end
                  return p.primary.orientation or p.general.orientation or "HORIZONTAL"
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.orientation = v; Refresh()
              end }
        );  y = y - h
        -- Inline cog on Show Power Bar: Expand if No Resource
        do
            local rgn = powerEnableRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Power Bar",
                rows = {
                    { type = "toggle", label = "Expand Bar if No Resource",
                      tooltip = "When your spec has no class resource, automatically adds the class resource height to the power bar. Automatically disabled when Power Bar height is matched to another element.",
                      get = function()
                          -- Force off when height matched
                          if EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power") then
                              return false
                          end
                          local p = DB(); return p and p.primary.expandIfNoResource
                      end,
                      set = function(v)
                          -- Block enable when height matched
                          if v and EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power") then
                              return
                          end
                          local p = DB(); if not p then return end
                          p.primary.expandIfNoResource = v; Refresh()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow)

            -- Inline spec-picker button for per-spec enable/disable
            local specBtn = CreateFrame("Button", nil, rgn)
            specBtn:SetSize(26, 26)
            specBtn:SetPoint("RIGHT", cogBtn, "LEFT", -4, 0)
            rgn._lastInline = specBtn
            specBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            specBtn:SetAlpha(0.4)
            local specTex = specBtn:CreateTexture(nil, "OVERLAY")
            specTex:SetAllPoints()
            specTex:SetDesaturated(true)
            do
                local _, classFile = UnitClass("player")
                local SPRITE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\glyph.tga"
                local COORDS = {
                    WARRIOR={0,0.125,0,0.125}, MAGE={0.125,0.25,0,0.125}, ROGUE={0.25,0.375,0,0.125},
                    DRUID={0.375,0.5,0,0.125}, EVOKER={0.5,0.625,0,0.125}, HUNTER={0,0.125,0.125,0.25},
                    SHAMAN={0.125,0.25,0.125,0.25}, PRIEST={0.25,0.375,0.125,0.25}, WARLOCK={0.375,0.5,0.125,0.25},
                    PALADIN={0,0.125,0.25,0.375}, DEATHKNIGHT={0.125,0.25,0.25,0.375},
                    MONK={0.25,0.375,0.25,0.375}, DEMONHUNTER={0.375,0.5,0.25,0.375},
                }
                specTex:SetTexture(SPRITE)
                local c = classFile and COORDS[classFile]
                if c then specTex:SetTexCoord(c[1], c[2], c[3], c[4]) end
            end
            specBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, "Enable/Disable per Spec")
            end)
            specBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4); EllesmereUI.HideWidgetTooltip() end)
            specBtn:SetScript("OnClick", function()
                local p = DB(); if not p then return end
                if not p.primary.disabledSpecs then p.primary.disabledSpecs = {} end
                local SPEC_DATA = EllesmereUI._SPEC_DATA
                local preChecked = {}
                local allSpecIDs = {}
                if SPEC_DATA then
                    for _, cls in ipairs(SPEC_DATA) do
                        for _, spec in ipairs(cls.specs) do
                            allSpecIDs[#allSpecIDs + 1] = spec.id
                            if not p.primary.disabledSpecs[spec.id] then
                                preChecked[spec.id] = true
                            end
                        end
                    end
                end
                local dummyDB = { _erbPower = { _specs = {} } }
                EllesmereUI:ShowSpecAssignPopup({
                    db              = dummyDB,
                    dbKey           = "_erbPower",
                    presetKey       = "_specs",
                    title           = "Power Bar",
                    subtitle        = "Enable for these specs:",
                    buttonText      = "Apply",
                    preCheckedSpecs = preChecked,
                    onConfirm       = function(assignments)
                        p.primary.disabledSpecs = {}
                        for _, specID in ipairs(allSpecIDs) do
                            if not assignments[specID] then
                                p.primary.disabledSpecs[specID] = true
                            end
                        end
                        Refresh(); EllesmereUI:RefreshPage()
                    end,
                })
            end)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip(powerDisTip))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdatePowerCogDis()
                local off = powerOff()
                if off then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdatePowerCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdatePowerCogDis)
            UpdatePowerCogDis()
        end

        -- Row 2: (Sync) Height | (Sync) Width
        local powerSizeRow
        local phDis, phTip, phRaw = EllesmereUI.MatchGuard("ERB_Power", "Height", powerOff, powerDisTip)
        local pwDis, pwTip, pwRaw = EllesmereUI.MatchGuard("ERB_Power", "Width", powerOff, powerDisTip)
        powerSizeRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 30, step = 1,
              disabled = phDis, disabledTooltip = phTip, rawTooltip = phRaw,
              getValue = function() local p = DB(); return p and p.primary.height or 16 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.height = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Width",
              min = 50, max = 350, step = 1,
              disabled = pwDis, disabledTooltip = pwTip, rawTooltip = pwRaw,
              getValue = function() local p = DB(); return p and p.primary.width or 220 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.width = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        _syncRows.powerHeight = powerSizeRow._leftRegion
        _syncRows.powerWidth  = powerSizeRow._rightRegion
        do
            local rgn = powerSizeRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Height to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.primary.height or 16
                    p.secondary.pipHeight = v; p.health.height = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.primary.height or 16
                    return (p.secondary.pipHeight or 20) == v and (p.health.height or 20) == v
                end,
                flashTargets = function() return { _syncRows.powerHeight, _syncRows.classHeight, _syncRows.healthHeight } end,
            })
        end
        do
            local rgn = powerSizeRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Width to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.primary.width or 220
                    p.secondary.pipWidth = v
                    p.health.width = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.primary.width or 220
                    return (p.secondary.pipWidth or 214) == v and (p.health.width or 220) == v
                end,
                flashTargets = function() return { _syncRows.powerWidth, _syncRows.classWidth, _syncRows.healthWidth } end,
            })
        end

        -- Row: Power Border Style dropdown (+ inline offset cog)
        do
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local pwrBsRow
            pwrBsRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style",
                  disabled = powerOff,
                  disabledTooltip = powerDisTip,
                  values=texValues, order=texOrder,
                  getValue=function() local p = DB(); return p and p.primary.borderTexture or "solid" end,
                  setValue=function(v)
                      local p = DB(); if not p then return end
                      p.primary.borderTexture = v; p.primary.borderTextureOffset = nil; p.primary.borderTextureOffsetY = nil; p.primary.borderTextureShiftX = nil; p.primary.borderTextureShiftY = nil
                      if v ~= "solid" then
                          p.primary.borderR = 1; p.primary.borderG = 1; p.primary.borderB = 1; p.primary.borderA = 1
                      else
                          p.primary.borderR = 0; p.primary.borderG = 0; p.primary.borderB = 0; p.primary.borderA = 1
                      end
                      local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                      if defSz then p.primary.borderSize = defSz end
                      RebuildPower(); EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Border Size",
                  min = 0, max = 4, step = 1,
                  disabled = powerOff,
                  disabledTooltip = powerDisTip,
                  getValue = function() local p = DB(); return p and p.primary.borderSize or 1 end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.primary.borderSize = v; RebuildPower()
                      EllesmereUI:RefreshPage()
                  end });  y = y - h
            _syncRows.powerBorder = pwrBsRow._rightRegion
            -- Inline color swatch on Border Size (right region)
            do
                local rgn = pwrBsRow._rightRegion
                local ctrl = rgn._control
                local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, pwrBsRow:GetFrameLevel() + 3,
                    function()
                        local p = DB()
                        return (p and p.primary.borderR or 0), (p and p.primary.borderG or 0),
                               (p and p.primary.borderB or 0), (p and p.primary.borderA or 1)
                    end,
                    function(r, g, b, a)
                        local p = DB(); if not p then return end
                        p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA = r, g, b, a
                        SmoothRefresh(); EllesmereUI:RefreshPage()
                    end,
                    true, 20)
                PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch() end)
            end
            do
                local rgn = pwrBsRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    rows = {
                        { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.primary.borderTextureOffset
                              if v then return v end
                              local dox = EllesmereUI.GetBorderDefaults("resourcebars", p.primary.borderTexture or "solid", p.primary.borderSize or 1)
                              return dox
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.primary.borderTextureOffset = v; RebuildPower(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.primary.borderTextureOffsetY
                              if v then return v end
                              local _, doy = EllesmereUI.GetBorderDefaults("resourcebars", p.primary.borderTexture or "solid", p.primary.borderSize or 1)
                              return doy
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.primary.borderTextureOffsetY = v; RebuildPower(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.primary.borderTextureShiftX
                              if v then return v end
                              local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", p.primary.borderTexture or "solid", p.primary.borderSize or 1)
                              return dsx
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.primary.borderTextureShiftX = v == 0 and nil or v; RebuildPower(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.primary.borderTextureShiftY
                              if v then return v end
                              local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", p.primary.borderTexture or "solid", p.primary.borderSize or 1)
                              return dsy
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.primary.borderTextureShiftY = v == 0 and nil or v; RebuildPower(); EllesmereUI:RefreshPage()
                          end },
                    },
                })
                local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                local function UpdateCogVis()
                    local p = DB()
                    local tex = p and p.primary.borderTexture or "solid"
                    if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
            -- Sync icon: Border Style (power -> secondary + health)
            EllesmereUI.BuildSyncIcon({
                region  = pwrBsRow._leftRegion,
                tooltip = "Apply Border Style to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local s = p.primary
                    local function apply(t)
                        t.borderTexture = s.borderTexture
                        t.borderTextureOffset = s.borderTextureOffset; t.borderTextureOffsetY = s.borderTextureOffsetY
                        t.borderTextureShiftX = s.borderTextureShiftX; t.borderTextureShiftY = s.borderTextureShiftY
                        t.borderR = s.borderR; t.borderG = s.borderG; t.borderB = s.borderB; t.borderA = s.borderA
                        t.borderSize = s.borderSize
                    end
                    apply(p.secondary); apply(p.health)
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local bt = p.primary.borderTexture or "solid"
                    return (p.secondary.borderTexture or "solid") == bt and (p.health.borderTexture or "solid") == bt
                end,
                flashTargets = function() return { pwrBsRow._leftRegion } end,
            })
            -- Sync icon on Border (right region of Border Style row)
            EllesmereUI.BuildSyncIcon({
                region  = pwrBsRow._rightRegion,
                tooltip = "Apply Border to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local r, g, b, a = p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA
                    local sz = p.primary.borderSize or 1
                    local bt = p.primary.borderTexture or "solid"
                    p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA = r, g, b, a
                    p.secondary.borderSize = sz; p.secondary.borderTexture = bt
                    p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA = r, g, b, a
                    p.health.borderSize = sz; p.health.borderTexture = bt
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local sr, sg, sb, sa, ssz = p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA, p.primary.borderSize or 1
                    local sbt = p.primary.borderTexture or "solid"
                    local function eq(t) return t.borderR == sr and t.borderG == sg and t.borderB == sb and t.borderA == sa and (t.borderSize or 1) == ssz and (t.borderTexture or "solid") == sbt end
                    return eq(p.secondary) and eq(p.health)
                end,
                flashTargets = function() return { _syncRows.powerBorder, _syncRows.classBorder, _syncRows.healthBorder } end,
            })
        end

        -- Row 4: (Sync) Opacity | Fill Color
        local powerBorderRow
        powerBorderRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Opacity",
              min = 0, max = 100, step = 5,
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              getValue = function() local p = DB(); return math.floor((p and p.primary.barAlpha or 1) * 100 + 0.5) end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.barAlpha = v / 100; RefreshPower()
                  EllesmereUI:RefreshPage()
              end },
            { type = "multiSwatch", text = "Fill Color",
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              swatches = {
                { tooltip = "Custom Colored",
                  hasAlpha = true,
                  getValue = function()
                      local p = DB()
                      if not p then return 0x23/255, 0x8F/255, 0xE7/255, 1 end
                      return p.primary.fillR, p.primary.fillG, p.primary.fillB, p.primary.fillA
                  end,
                  setValue = function(r, g, b, a)
                      local p = DB(); if not p then return end
                      p.primary.fillR, p.primary.fillG, p.primary.fillB, p.primary.fillA = r, g, b, a
                      RebuildPower(); SmoothRefresh()
                  end,
                  onClick = function(self)
                      local p = DB(); if not p then return end
                      if not p.primary.customColored then
                          p.primary.customColored = true; RebuildPower()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local p = DB()
                      local isPowerColored = not p or not p.primary.customColored
                      return isPowerColored and 0.3 or 1
                  end },
                { tooltip = "Power Colored",
                  getValue = function()
                      local gpp = _G._ERB_GetPrimaryPowerType
                      local pc = gpp and _G._ERB_PowerColors and _G._ERB_PowerColors[gpp()]
                      if pc then return pc[1], pc[2], pc[3], 1 end
                      return 0x23/255, 0x8F/255, 0xE7/255, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      local p = DB(); if not p then return end
                      p.primary.customColored = false; RebuildPower()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local p = DB()
                      local isPowerColored = not p or not p.primary.customColored
                      return isPowerColored and 1 or 0.3
                  end },
              } }
        );  y = y - h
        _syncRows.powerOpacity = powerBorderRow._leftRegion
        -- Sync icon on Opacity
        do
            local rgn = powerBorderRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Opacity to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.primary.barAlpha or 1
                    p.secondary.barAlpha = v; p.health.barAlpha = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.primary.barAlpha or 1
                    return (p.secondary.barAlpha or 1) == v and (p.health.barAlpha or 1) == v
                end,
                flashTargets = function() return { _syncRows.powerOpacity, _syncRows.classOpacity, _syncRows.healthOpacity } end,
            })
        end

        -- Row 5: Power Text | Threshold Settings
        local powerColorRow
        powerColorRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Power Text",
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              values = { none = "None", smart = "Smart Text", curpp = "Power Value", perpp = "Power %", both = "Power Value | Power %" },
              order = { "none", "smart", "curpp", "perpp", "both" },
              getValue = function() local p = DB(); return p and p.primary.textFormat or "none" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.textFormat = v; RefreshPower()
              end },
            { type = "label", text = "Threshold Settings" }
        );  y = y - h
        -- Inline cog (RESIZE) on Power Text for percent sign + text size + x/y offsets
        do
            local rgn = powerColorRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Power Text",
                rows = {
                    { type = "toggle", label = "Show %",
                      get = function()
                          local p = DB()
                          return (not p) or p.primary.showPercent ~= false
                      end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.primary.showPercent = v; RefreshPower()
                      end },
                    { type = "slider", label = "Size", min = 8, max = 24, step = 1,
                      get = function() local p = DB(); return p and p.primary.textSize or 11 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.primary.textSize = v; RefreshPower()
                      end },
                    { type = "slider", label = "X Offset", min = -50, max = 50, step = 1,
                      get = function() local p = DB(); return p and p.primary.textXOffset or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.primary.textXOffset = v; RefreshPower()
                      end },
                    { type = "slider", label = "Y Offset", min = -50, max = 50, step = 1,
                      get = function() local p = DB(); return p and p.primary.textYOffset or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.primary.textYOffset = v; RefreshPower()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Power Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisP2()
                local p = DB()
                if p and not p.primary.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisP2)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisP2)
            UpdateCogDisP2()
        end

        -- Threshold Settings popup on Power Text row5slot2
        BuildThresholdSettingsButton({
            parentRgn = powerColorRow._rightRegion,
            getBarData = function() local p = DB(); return p and p.primary end,
            refreshFn = function() RefreshPower(); SmoothRefresh() end,
            rebuildFn = function() RebuildPower() end,
            disabledFn = powerOff,
            disabledTip = "Enable Power Bar",
            showHash = false,
            showPartialCog = true,
            thresholdLabel = "Threshold %",
            threshMin = 1, threshMax = 99,
            popupTitle = "Power Bar Threshold",
            defaultR = 1.0, defaultG = 0.2, defaultB = 0.2, defaultA = 1,
        })

        -- Row: Anchor to Cursor | Cursor Position (cog: X + Y)
        do
            local _, cursorH = EllesmereUI.BuildCursorAnchorRow({
                W = W, parent = parent, y = y,
                getData = function() local p = DB(); return p and p.primary or {} end,
                onApply = function() RebuildPower(); SmoothRefresh() end,
                makeCogBtn = MakeCogBtn,
                disabledFn = function()
                      local p = DB(); return p and not p.primary.enabled
                end,
                disabledTip = "Enable Power Bar",
            })
            y = y - cursorH
        end

        -- Row 7: Power Type override (spec-dependent, like UF Power Type dropdown)
        do
            local _, playerClass = UnitClass("player")
            local SPEC_POWER_ALTS = {
                DRUID  = { [1] = { "Mana", "Astral Power" }, [2] = { "Energy", "Mana" }, [3] = { "Rage", "Mana" } },
                PRIEST = { [3] = { "Mana", "Insanity" } },
                SHAMAN = { [1] = { "Mana", "Maelstrom" } },
                EVOKER = { [3] = { "Ebon Might", "Mana" } },
            }
            local classAlts = SPEC_POWER_ALTS[playerClass]
            if classAlts then
                local spec = GetSpecialization and GetSpecialization()
                local data = spec and classAlts[spec]
                if data then
                    local ptValues = { ["default"] = data[1], ["alt"] = data[2] }
                    local ptOrder  = { "default", "alt" }
                    local powerTypeRow
                    powerTypeRow, h = W:DualRow(parent, y,
                        { type="dropdown", text="Power Type",
                          disabled = powerOff,
                          disabledTooltip = powerDisTip,
                          values = ptValues, order = ptOrder,
                          getValue = function()
                              local s = GetSpecialization and GetSpecialization()
                              if not s or not classAlts[s] then return "default" end
                              local p = DB(); if not p then return "default" end
                              local ov = p.primary.powerTypeOverride
                              if ov and ov[s] then return "alt" end
                              return "default"
                          end,
                          setValue = function(v)
                              local s = GetSpecialization and GetSpecialization()
                              if not s then return end
                              local p = DB(); if not p then return end
                              if v == "alt" then
                                  if not p.primary.powerTypeOverride then p.primary.powerTypeOverride = {} end
                                  p.primary.powerTypeOverride[s] = true
                              else
                                  if p.primary.powerTypeOverride then p.primary.powerTypeOverride[s] = nil end
                              end
                              RebuildPower()
                          end },
                        { type="label", text="" }); y = y - h

                    local function UpdatePowerTypeRow()
                        local s = GetSpecialization and GetSpecialization()
                        if s and classAlts[s] then
                            powerTypeRow:Show()
                        else
                            powerTypeRow:Hide()
                        end
                    end
                    EllesmereUI.RegisterWidgetRefresh(UpdatePowerTypeRow)
                    UpdatePowerTypeRow()
                end
            end
        end

        _, h = W:Spacer(parent, y, 16);  y = y - h

        -----------------------------------------------------------------------
        --  HEALTH BAR
        -----------------------------------------------------------------------
        local healthSection
        healthSection, h = W:SectionHeader(parent, "HEALTH BAR", y);  y = y - h

        local healthOff = function() local p = DB(); return p and not p.health.enabled end

        -- Row 1: Show Health Bar (+ inline spec picker) | Orientation
        local healthEnableRow
        healthEnableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Health Bar",
              getValue = function() local p = DB(); return p and p.health.enabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.enabled = v; RebuildHealth()
                  EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Orientation",
              disabled = healthOff,
              disabledTooltip = "Enable Health Bar",
              values = { HORIZONTAL = "Horizontal", VERTICAL_UP = "Vertical Up", VERTICAL_DOWN = "Vertical Down" },
              order = { "HORIZONTAL", "VERTICAL_UP", "VERTICAL_DOWN" },
              getValue = function()
                  local p = DB(); if not p then return "HORIZONTAL" end
                  return p.health.orientation or p.general.orientation or "HORIZONTAL"
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.orientation = v; Refresh()
              end }
        );  y = y - h
        -- Inline spec-picker button on Show Health Bar
        do
            local rgn = healthEnableRow._leftRegion
            local specBtn = CreateFrame("Button", nil, rgn)
            specBtn:SetSize(26, 26)
            specBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = specBtn
            specBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            specBtn:SetAlpha(0.4)
            local specTex = specBtn:CreateTexture(nil, "OVERLAY")
            specTex:SetAllPoints()
            specTex:SetDesaturated(true)
            do
                local _, classFile = UnitClass("player")
                local SPRITE = "Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\glyph.tga"
                local COORDS = {
                    WARRIOR={0,0.125,0,0.125}, MAGE={0.125,0.25,0,0.125}, ROGUE={0.25,0.375,0,0.125},
                    DRUID={0.375,0.5,0,0.125}, EVOKER={0.5,0.625,0,0.125}, HUNTER={0,0.125,0.125,0.25},
                    SHAMAN={0.125,0.25,0.125,0.25}, PRIEST={0.25,0.375,0.125,0.25}, WARLOCK={0.375,0.5,0.125,0.25},
                    PALADIN={0,0.125,0.25,0.375}, DEATHKNIGHT={0.125,0.25,0.25,0.375},
                    MONK={0.25,0.375,0.25,0.375}, DEMONHUNTER={0.375,0.5,0.25,0.375},
                }
                specTex:SetTexture(SPRITE)
                local c = classFile and COORDS[classFile]
                if c then specTex:SetTexCoord(c[1], c[2], c[3], c[4]) end
            end
            specBtn:SetScript("OnEnter", function(self)
                self:SetAlpha(0.7)
                EllesmereUI.ShowWidgetTooltip(self, "Enable/Disable per Spec")
            end)
            specBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4); EllesmereUI.HideWidgetTooltip() end)
            specBtn:SetScript("OnClick", function()
                local p = DB(); if not p then return end
                if not p.health.disabledSpecs then p.health.disabledSpecs = {} end
                local SPEC_DATA = EllesmereUI._SPEC_DATA
                local preChecked = {}
                local allSpecIDs = {}
                if SPEC_DATA then
                    for _, cls in ipairs(SPEC_DATA) do
                        for _, spec in ipairs(cls.specs) do
                            allSpecIDs[#allSpecIDs + 1] = spec.id
                            if not p.health.disabledSpecs[spec.id] then
                                preChecked[spec.id] = true
                            end
                        end
                    end
                end
                local dummyDB = { _erbHealth = { _specs = {} } }
                EllesmereUI:ShowSpecAssignPopup({
                    db              = dummyDB,
                    dbKey           = "_erbHealth",
                    presetKey       = "_specs",
                    title           = "Health Bar",
                    subtitle        = "Enable for these specs:",
                    buttonText      = "Apply",
                    preCheckedSpecs = preChecked,
                    onConfirm       = function(assignments)
                        p.health.disabledSpecs = {}
                        for _, specID in ipairs(allSpecIDs) do
                            if not assignments[specID] then
                                p.health.disabledSpecs[specID] = true
                            end
                        end
                        RebuildHealth(); EllesmereUI:RefreshPage()
                    end,
                })
            end)
        end

        -- Row 2: (Sync) Height | (Sync) Width
        local healthSizeRow
        local hhDis, hhTip, hhRaw = EllesmereUI.MatchGuard("ERB_Health", "Height", healthOff, "Enable Health Bar")
        local hwDis, hwTip, hwRaw = EllesmereUI.MatchGuard("ERB_Health", "Width", healthOff, "Enable Health Bar")
        healthSizeRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 40, step = 1,
              disabled = hhDis, disabledTooltip = hhTip, rawTooltip = hhRaw,
              getValue = function() local p = DB(); return p and p.health.height or 20 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.height = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Width",
              min = 50, max = 350, step = 1,
              disabled = hwDis, disabledTooltip = hwTip, rawTooltip = hwRaw,
              getValue = function() local p = DB(); return p and p.health.width or 220 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.width = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        _syncRows.healthHeight = healthSizeRow._leftRegion
        _syncRows.healthWidth  = healthSizeRow._rightRegion
        do
            local rgn = healthSizeRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Height to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.health.height or 20
                    p.secondary.pipHeight = v; p.primary.height = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.health.height or 20
                    return (p.secondary.pipHeight or 20) == v and (p.primary.height or 16) == v
                end,
                flashTargets = function() return { _syncRows.healthHeight, _syncRows.classHeight, _syncRows.powerHeight } end,
            })
        end
        do
            local rgn = healthSizeRow._rightRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Width to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.health.width or 220
                    p.secondary.pipWidth = v
                    p.primary.width = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.health.width or 220
                    return (p.primary.width or 220) == v and (p.secondary.pipWidth or 214) == v
                end,
                flashTargets = function() return { _syncRows.healthWidth, _syncRows.classWidth, _syncRows.powerWidth } end,
            })
        end

        -- Row: Health Border Style dropdown (+ inline offset cog)
        do
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local hpBsRow
            hpBsRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style",
                  disabled = healthOff,
                  disabledTooltip = "Enable Health Bar",
                  values=texValues, order=texOrder,
                  getValue=function() local p = DB(); return p and p.health.borderTexture or "solid" end,
                  setValue=function(v)
                      local p = DB(); if not p then return end
                      p.health.borderTexture = v; p.health.borderTextureOffset = nil; p.health.borderTextureOffsetY = nil; p.health.borderTextureShiftX = nil; p.health.borderTextureShiftY = nil
                      if v ~= "solid" then
                          p.health.borderR = 1; p.health.borderG = 1; p.health.borderB = 1; p.health.borderA = 1
                      else
                          p.health.borderR = 0; p.health.borderG = 0; p.health.borderB = 0; p.health.borderA = 1
                      end
                      local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                      if defSz then p.health.borderSize = defSz end
                      RebuildHealth(); EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Border Size",
                  min = 0, max = 4, step = 1,
                  disabled = healthOff,
                  disabledTooltip = "Enable Health Bar",
                  getValue = function() local p = DB(); return p and p.health.borderSize or 1 end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.health.borderSize = v; RebuildHealth()
                      EllesmereUI:RefreshPage()
                  end });  y = y - h
            _syncRows.healthBorder = hpBsRow._rightRegion
            -- Inline color swatch on Border Size (right region)
            do
                local rgn = hpBsRow._rightRegion
                local ctrl = rgn._control
                local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, hpBsRow:GetFrameLevel() + 3,
                    function()
                        local p = DB()
                        return (p and p.health.borderR or 0), (p and p.health.borderG or 0),
                               (p and p.health.borderB or 0), (p and p.health.borderA or 1)
                    end,
                    function(r, g, b, a)
                        local p = DB(); if not p then return end
                        p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA = r, g, b, a
                        SmoothRefresh(); EllesmereUI:RefreshPage()
                    end,
                    true, 20)
                PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch() end)
            end
            do
                local rgn = hpBsRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    rows = {
                        { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.health.borderTextureOffset
                              if v then return v end
                              local dox = EllesmereUI.GetBorderDefaults("resourcebars", p.health.borderTexture or "solid", p.health.borderSize or 1)
                              return dox
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.health.borderTextureOffset = v; RebuildHealth(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.health.borderTextureOffsetY
                              if v then return v end
                              local _, doy = EllesmereUI.GetBorderDefaults("resourcebars", p.health.borderTexture or "solid", p.health.borderSize or 1)
                              return doy
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.health.borderTextureOffsetY = v; RebuildHealth(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.health.borderTextureShiftX
                              if v then return v end
                              local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", p.health.borderTexture or "solid", p.health.borderSize or 1)
                              return dsx
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.health.borderTextureShiftX = v == 0 and nil or v; RebuildHealth(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.health.borderTextureShiftY
                              if v then return v end
                              local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", p.health.borderTexture or "solid", p.health.borderSize or 1)
                              return dsy
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.health.borderTextureShiftY = v == 0 and nil or v; RebuildHealth(); EllesmereUI:RefreshPage()
                          end },
                    },
                })
                local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                local function UpdateCogVis()
                    local p = DB()
                    local tex = p and p.health.borderTexture or "solid"
                    if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
            -- Sync icon: Border Style (health -> secondary + primary)
            EllesmereUI.BuildSyncIcon({
                region  = hpBsRow._leftRegion,
                tooltip = "Apply Border Style to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local s = p.health
                    local function apply(t)
                        t.borderTexture = s.borderTexture
                        t.borderTextureOffset = s.borderTextureOffset; t.borderTextureOffsetY = s.borderTextureOffsetY
                        t.borderTextureShiftX = s.borderTextureShiftX; t.borderTextureShiftY = s.borderTextureShiftY
                        t.borderR = s.borderR; t.borderG = s.borderG; t.borderB = s.borderB; t.borderA = s.borderA
                        t.borderSize = s.borderSize
                    end
                    apply(p.secondary); apply(p.primary)
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local bt = p.health.borderTexture or "solid"
                    return (p.secondary.borderTexture or "solid") == bt and (p.primary.borderTexture or "solid") == bt
                end,
                flashTargets = function() return { hpBsRow._leftRegion } end,
            })
            -- Sync icon on Border (right region of Border Style row)
            EllesmereUI.BuildSyncIcon({
                region  = hpBsRow._rightRegion,
                tooltip = "Apply Border to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local r, g, b, a = p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA
                    local sz = p.health.borderSize or 1
                    local bt = p.health.borderTexture or "solid"
                    p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA = r, g, b, a
                    p.secondary.borderSize = sz; p.secondary.borderTexture = bt
                    p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA = r, g, b, a
                    p.primary.borderSize = sz; p.primary.borderTexture = bt
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local sr, sg, sb, sa, ssz = p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA, p.health.borderSize or 1
                    local sbt = p.health.borderTexture or "solid"
                    local function eq(t) return t.borderR == sr and t.borderG == sg and t.borderB == sb and t.borderA == sa and (t.borderSize or 1) == ssz and (t.borderTexture or "solid") == sbt end
                    return eq(p.secondary) and eq(p.primary)
                end,
                flashTargets = function() return { _syncRows.healthBorder, _syncRows.classBorder, _syncRows.powerBorder } end,
            })
        end

        -- Row 4: (Sync) Opacity | Fill Color
        local healthBorderRow
        healthBorderRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Opacity",
              min = 0, max = 100, step = 5,
              disabled = healthOff,
              disabledTooltip = "Enable Health Bar",
              getValue = function() local p = DB(); return math.floor((p and p.health.barAlpha or 1) * 100 + 0.5) end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.barAlpha = v / 100; RefreshHealth()
                  EllesmereUI:RefreshPage()
              end },
            { type = "multiSwatch", text = "Fill Color",
              disabled = healthOff,
              disabledTooltip = "Enable Health Bar",
              swatches = {
                { tooltip = "Custom Colored",
                  hasAlpha = true,
                  getValue = function()
                      local p = DB()
                      if not p then return 37/255, 193/255, 29/255, 1 end
                      return p.health.fillR, p.health.fillG, p.health.fillB, p.health.fillA
                  end,
                  setValue = function(r, g, b, a)
                      local p = DB(); if not p then return end
                      p.health.fillR, p.health.fillG, p.health.fillB, p.health.fillA = r, g, b, a
                      if not p.health.customColored then p.health.customColored = true end
                      if p.health.darkTheme then p.health.darkTheme = false end
                      SmoothRefresh(); EllesmereUI:RefreshPage()
                  end,
                  onClick = function(self)
                      local p = DB(); if not p then return end
                      if not p.health.customColored then
                          p.health.customColored = true
                          if p.health.darkTheme then p.health.darkTheme = false end
                          RebuildHealth(); EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local p = DB()
                      local isClassColored = not p or not p.health.customColored
                      return isClassColored and 0.3 or 1
                  end },
                { tooltip = "Class Colored",
                  getValue = function()
                      local _, classFile = UnitClass("player")
                      local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                      if cc then return cc.r, cc.g, cc.b, 1 end
                      return 37/255, 193/255, 29/255, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      local p = DB(); if not p then return end
                      p.health.customColored = false
                      if p.health.darkTheme then p.health.darkTheme = false end
                      RebuildHealth(); EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local p = DB()
                      local isClassColored = not p or not p.health.customColored
                      return isClassColored and 1 or 0.3
                  end },
              } }
        );  y = y - h
        _syncRows.healthOpacity = healthBorderRow._leftRegion
        -- Sync icon on Opacity
        do
            local rgn = healthBorderRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Opacity to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local v = p.health.barAlpha or 1
                    p.secondary.barAlpha = v; p.primary.barAlpha = v
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local v = p.health.barAlpha or 1
                    return (p.secondary.barAlpha or 1) == v and (p.primary.barAlpha or 1) == v
                end,
                flashTargets = function() return { _syncRows.healthOpacity, _syncRows.classOpacity, _syncRows.powerOpacity } end,
            })
        end

        -- Row 5: Health Text | Threshold Settings
        local healthColorRow
        healthColorRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Health Text",
              disabled = healthOff,
              disabledTooltip = "Enable Health Bar",
              values = { none = "None", perhp = "Health %", perhpnosign = "Health % (No Sign)", curhpshort = "Health #", perhpnum = "Health % | #", both = "Health # | %" },
              order = { "none", "---", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both" },
              getValue = function() local p = DB(); return p and p.health.textFormat or "none" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.textFormat = v; RefreshHealth()
              end },
            { type = "label", text = "Threshold Settings" }
        );  y = y - h
        -- Inline cog (RESIZE) on Health Text for text size + x/y offsets
        do
            local rgn = healthColorRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Health Text",
                rows = {
                    { type = "slider", label = "Size", min = 8, max = 24, step = 1,
                      get = function() local p = DB(); return p and p.health.textSize or 11 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.health.textSize = v; RefreshHealth()
                      end },
                    { type = "slider", label = "X Offset", min = -50, max = 50, step = 1,
                      get = function() local p = DB(); return p and p.health.textXOffset or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.health.textXOffset = v; RefreshHealth()
                      end },
                    { type = "slider", label = "Y Offset", min = -50, max = 50, step = 1,
                      get = function() local p = DB(); return p and p.health.textYOffset or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.health.textYOffset = v; RefreshHealth()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Health Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisH2()
                local p = DB()
                if p and not p.health.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisH2)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisH2)
            UpdateCogDisH2()
        end

        -- Threshold Settings popup on Health Text row5slot2
        BuildThresholdSettingsButton({
            parentRgn = healthColorRow._rightRegion,
            getBarData = function() local p = DB(); return p and p.health end,
            refreshFn = function() RefreshHealth(); SmoothRefresh() end,
            rebuildFn = function() RebuildHealth() end,
            disabledFn = healthOff,
            disabledTip = "Enable Health Bar",
            showHash = false,
            showPartialCog = false,
            thresholdLabel = "Threshold %",
            threshMin = 1, threshMax = 99,
            popupTitle = "Health Bar Threshold",
            defaultR = 1.0, defaultG = 0.2, defaultB = 0.2, defaultA = 1,
        })

        -- Row: Anchor to Cursor | Cursor Position (cog: X + Y)
        do
            local _, cursorH = EllesmereUI.BuildCursorAnchorRow({
                W = W, parent = parent, y = y,
                getData = function() local p = DB(); return p and p.health or {} end,
                onApply = function() RebuildHealth(); SmoothRefresh() end,
                makeCogBtn = MakeCogBtn,
                disabledFn = function() local p = DB(); return p and not p.health.enabled end,
                disabledTip = "Enable Health Bar",
            })
            y = y - cursorH
        end

        _, h = W:Spacer(parent, y, 16);  y = y - h

        -- Wire up click mappings for preview hit overlays
        _clickMappings.classResource = { section = classSection, target = classEnableRow }
        _clickMappings.countText = { section = classSection, target = classColorRow }

        return math.abs(y)
    end

        ---------------------------------------------------------------------------
    --  Unlock Mode page
    ---------------------------------------------------------------------------
    local function BuildUnlockPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, "POSITIONING", y);  y = y - h

        _, h = W:Toggle(parent, "Unlock Elements", y,
            function() return EllesmereUI._unlockModeActive or false end,
            function(v)
                if EllesmereUI and EllesmereUI.ToggleUnlockMode then
                    EllesmereUI:ToggleUnlockMode()
                end
            end,
            nil,
            "Opens the shared Unlock Mode to reposition and scale elements"
        );  y = y - h

        _, h = W:Spacer(parent, y, 12);  y = y - h

        _, h = W:SectionHeader(parent, "RESET", y);  y = y - h

        _, h = W:Toggle(parent, "Reset Positions", y,
            function() return false end,
            function()
                local p = DB(); if not p then return end
                p.health.offsetX = 0;   p.health.offsetY = -64;   p.health.unlockPos = nil
                p.primary.offsetX = 0;  p.primary.offsetY = -52; p.primary.unlockPos = nil
                p.secondary.offsetX = 0; p.secondary.offsetY = -38; p.secondary.unlockPos = nil
                p.secondary.countTextUnlockPos = nil
                p.castBar.unlockPos = nil; p.castBar.anchorX = 0; p.castBar.anchorY = -50
                Refresh()
            end,
            nil,
            "Click to reset all element positions to defaults"
        );  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Cast Bar preview state
    ---------------------------------------------------------------------------
    local _castBarPreviewFill = 0.65
    local _castBarPreviewFrames = {}
    local _castBarPreviewScale = 1

    -- Shuffled spell icon pool for cast bar preview (same spells as nameplates)
    local _castBarIconPool = { 136197, 236802, 135808, 136116, 135735, 136048, 135812, 136075 }
    local _castBarIconIdx = 0
    local function ShuffleCastBarIcons()
        _castBarIconIdx = 0
        for i = #_castBarIconPool, 2, -1 do
            local j = math.random(i)
            _castBarIconPool[i], _castBarIconPool[j] = _castBarIconPool[j], _castBarIconPool[i]
        end
    end
    local function NextCastBarIcon()
        _castBarIconIdx = _castBarIconIdx + 1
        if _castBarIconIdx > #_castBarIconPool then _castBarIconIdx = 1 end
        return _castBarIconPool[_castBarIconIdx]
    end

    local function UpdateCastBarPreview()
        local p = DB()
        if not p then return end
        local cb = p.castBar
        local pf = _castBarPreviewFrames

        if not pf.bar then return end

        -- Snap helper: round to the preview container's physical pixel grid
        local cScale = pf.container:GetEffectiveScale()
        if cScale <= 0 then cScale = 1 end
        local function Snap(val)
            return math.floor(val * cScale + 0.5) / cScale
        end

        local w, h = Snap(cb.width), Snap(cb.height)
        local bs = cb.borderSize

        -- Container size: icon (h×h) + bar (only when icon shown)
        local hasIcon = cb.showIcon ~= false
        local iconW = hasIcon and Snap(h) or 0
        pf.container:SetSize(w + iconW, h)

        -- Scale down to fit when the cast bar is wider than the panel
        local PAD = EllesmereUI.CONTENT_PAD or 10
        local hdr = pf.container:GetParent()
        local availW = (hdr:GetWidth() - PAD * 2) / _castBarPreviewScale
        local fitScale = 1
        if (w + iconW) > availW and (w + iconW) > 0 and availW > 0 then
            fitScale = availW / (w + iconW)
        end
        pf.container:SetScale(_castBarPreviewScale * fitScale)

        pf.container:ClearAllPoints(); pf.container:SetPoint("CENTER", hdr, "CENTER", 0, 0)
        -- Bar frame
        pf.barFrame:SetSize(w, h)
        pf.barFrame:ClearAllPoints()
        pf.barFrame:SetPoint("LEFT", pf.container, "LEFT", iconW, 0)

        -- Background
        local texKey = cb.texture
        if texKey == "blizzard" then
            pf.bg:SetAtlas("UI-CastingBar-Background", true)
            pf.bg:ClearAllPoints()
            pf.bg:SetAllPoints(pf.barFrame)
        else
            pf.bg:SetTexture(nil)
            pf.bg:SetColorTexture(cb.bgR, cb.bgG, cb.bgB, cb.bgA)
            pf.bg:ClearAllPoints()
            pf.bg:SetAllPoints(pf.barFrame)
        end

        -- Border wraps container (bar + icon) - PP or textured via ApplyBorderStyle
        if pf.container._border then
            EllesmereUI.ApplyBorderStyle(pf.container._border, cb.borderSize or 0,
                cb.borderR or 0, cb.borderG or 0, cb.borderB or 0, cb.borderA or 1,
                cb.borderTexture or "solid", cb.borderTextureOffset, cb.borderTextureOffsetY,
                cb.borderTextureShiftX, cb.borderTextureShiftY)
        end

        -- Status bar: full bar frame, no inset
        pf.bar:ClearAllPoints()
        pf.bar:SetAllPoints(pf.barFrame)
        pf.bar:SetValue(_castBarPreviewFill)

        -- Bar texture
        local texLookup = _G._ERB_CastBarTextures or {}
        local texPath = texLookup[texKey]
        if texKey == "blizzard" then
            pf.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            pf.bar:GetStatusBarTexture():SetAtlas("UI-CastingBar-Fill", true)
        elseif texPath then
            pf.bar:SetStatusBarTexture(texPath)
        else
            pf.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        end

        -- Bar color / gradient
        local fillTex = pf.bar:GetStatusBarTexture()
        local fR, fG, fB, fA = cb.fillR, cb.fillG, cb.fillB, cb.fillA
        if cb.classColored == true then
            local _, cf = UnitClass("player")
            local cc = cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
            if cc then fR, fG, fB = cc.r, cc.g, cc.b end
        end
        if cb.gradientEnabled then
            local dir = cb.gradientDir or "HORIZONTAL"
            fillTex:SetGradient(dir, CreateColor(fR, fG, fB, fA), CreateColor(cb.gradientR, cb.gradientG, cb.gradientB, cb.gradientA))
        else
            fillTex:SetVertexColor(fR, fG, fB, fA)
        end

        -- Spark
        if cb.showSpark then
            pf.spark:SetSize(8, h)
            pf.spark:ClearAllPoints()
            pf.spark:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
            pf.spark:Show()
        else
            pf.spark:Hide()
        end

        -- Icon: left side of container, full size
        do
            local iSize = Snap(h)
            pf.iconFrame:SetSize(iSize, iSize)
            pf.iconFrame:ClearAllPoints()
            pf.iconFrame:SetPoint("TOPLEFT", pf.container, "TOPLEFT", 0, 0)
            if hasIcon then pf.iconFrame:Show() else pf.iconFrame:Hide() end
        end

        -- Timer text
        if cb.showTimer then
            SetPVFont(pf.timerText, FONT_PATH, cb.timerSize or 11)
            pf.timerText:ClearAllPoints()
            pf.timerText:SetPoint("RIGHT", pf.bar, "RIGHT", -4 + (cb.timerX or 0), cb.timerY or 0)
            local remaining = 3.0 * (1 - _castBarPreviewFill)
            pf.timerText:SetText(string.format("%.1f", remaining))
            pf.timerText:Show()
        else
            pf.timerText:Hide()
        end

        -- Spell name text
        if cb.showSpellText then
            SetPVFont(pf.spellText, FONT_PATH, cb.spellTextSize or 11)
            pf.spellText:ClearAllPoints()
            pf.spellText:SetPoint("LEFT", pf.bar, "LEFT", 4 + (cb.spellTextX or 0), cb.spellTextY or 0)
            pf.spellText:SetText("Spell Name")
            pf.spellText:Show()
        else
            pf.spellText:Hide()
        end

        -- Update header height: 80px preview + optional hint text
        local hintH = (_previewHintFS and _previewHintFS:IsShown()) and 35 or 0
        EllesmereUI:UpdateContentHeaderHeight(80 + hintH)
    end

    local _castBarPreviewBuilder = function(hdr, hdrW)
        local p = DB()
        if not p then return 0 end
        local cb = p.castBar

        local previewScale = UIParent:GetEffectiveScale() / hdr:GetEffectiveScale()
        _castBarPreviewScale = previewScale

        local container = CreateFrame("Frame", nil, hdr)
        container:SetPoint("CENTER", hdr, "CENTER", 0, 0)

        -- Snap helper: round to the preview container's physical pixel grid
        -- (use previewScale for initial snap; adjusted below if we scale-to-fit)
        local cScale = UIParent:GetEffectiveScale()
        if cScale <= 0 then cScale = 1 end
        local function Snap(val)
            return math.floor(val * cScale + 0.5) / cScale
        end

        local w, h = Snap(cb.width), Snap(cb.height)
        local hasIcon = cb.showIcon ~= false
        local iconW = hasIcon and Snap(h) or 0

        -- Scale down to fit when the cast bar is wider than the panel
        local PAD = EllesmereUI.CONTENT_PAD or 10
        local availW = (hdrW - PAD * 2) / previewScale
        local fitScale = 1
        if (w + iconW) > availW and (w + iconW) > 0 and availW > 0 then
            fitScale = availW / (w + iconW)
        end
        container:SetScale(previewScale * fitScale)

        container:SetSize(w + iconW, h)

        -- Bar frame (holds bg, status bar)
        local barFrame = CreateFrame("Frame", nil, container)
        barFrame:SetSize(w, h)
        barFrame:SetPoint("LEFT", container, "LEFT", iconW, 0)
        _castBarPreviewFrames.barFrame = barFrame
        _castBarPreviewFrames.container = container

        -- Border: dedicated child frame covering bar + icon (PP or textured)
        local bdrFrame = CreateFrame("Frame", nil, container)
        bdrFrame:SetAllPoints(container)
        bdrFrame:SetFrameLevel(container:GetFrameLevel() + 5)
        container._border = bdrFrame
        EllesmereUI.ApplyBorderStyle(bdrFrame, cb.borderSize or 0,
            cb.borderR or 0, cb.borderG or 0, cb.borderB or 0, cb.borderA or 1,
            cb.borderTexture or "solid", cb.borderTextureOffset, cb.borderTextureOffsetY,
            cb.borderTextureShiftX, cb.borderTextureShiftY)

        -- Background (full bar area, no inset)
        local bg = barFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local texKey = cb.texture
        if texKey == "blizzard" then
            bg:SetAtlas("UI-CastingBar-Background", true)
        else
            bg:SetColorTexture(cb.bgR, cb.bgG, cb.bgB, cb.bgA)
        end
        _castBarPreviewFrames.bg = bg

        -- Status bar (full bar area, no inset)
        local bar = CreateFrame("StatusBar", nil, barFrame)
        bar:SetAllPoints()
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(_castBarPreviewFill)

        local texLookup = _G._ERB_CastBarTextures or {}
        local texPath = texLookup[texKey]
        if texKey == "blizzard" then
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            bar:GetStatusBarTexture():SetAtlas("UI-CastingBar-Fill", true)
        elseif texPath then
            bar:SetStatusBarTexture(texPath)
        else
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        end

        local fillTex = bar:GetStatusBarTexture()
        if cb.gradientEnabled then
            local dir = cb.gradientDir or "HORIZONTAL"
            fillTex:SetGradient(dir, CreateColor(cb.fillR, cb.fillG, cb.fillB, cb.fillA), CreateColor(cb.gradientR, cb.gradientG, cb.gradientB, cb.gradientA))
        else
            fillTex:SetVertexColor(cb.fillR, cb.fillG, cb.fillB, cb.fillA)
        end
        _castBarPreviewFrames.bar = bar

        -- Spark
        local spark = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
        spark:SetBlendMode("ADD")
        spark:SetSize(8, h)
        spark:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
        if not cb.showSpark then spark:Hide() end
        _castBarPreviewFrames.spark = spark

        -- Icon: left side of container, full size
        local iconFrame = CreateFrame("Frame", nil, container)
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(NextCastBarIcon())
        local iSize = Snap(h)
        iconFrame:SetSize(iSize, iSize)
        iconFrame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        if not hasIcon then iconFrame:Hide() end
        _castBarPreviewFrames.iconFrame = iconFrame
        _castBarPreviewFrames.icon = icon

        -- Timer text
        local timerText = bar:CreateFontString(nil, "OVERLAY")
        SetPVFont(timerText, FONT_PATH, cb.timerSize or 11)
        timerText:SetPoint("RIGHT", bar, "RIGHT", -4 + (cb.timerX or 0), cb.timerY or 0)
        timerText:SetJustifyH("RIGHT")
        if cb.showTimer then
            local remaining = 3.0 * (1 - _castBarPreviewFill)
            timerText:SetText(string.format("%.1f", remaining))
        else
            timerText:Hide()
        end
        _castBarPreviewFrames.timerText = timerText

        -- Spell name text
        local spellText = bar:CreateFontString(nil, "OVERLAY")
        SetPVFont(spellText, FONT_PATH, cb.spellTextSize or 11)
        spellText:SetPoint("LEFT", bar, "LEFT", 4 + (cb.spellTextX or 0), cb.spellTextY or 0)
        spellText:SetJustifyH("LEFT")
        if cb.showSpellText then
            spellText:SetText("Spell Name")
        else
            spellText:Hide()
        end
        _castBarPreviewFrames.spellText = spellText

        -- Create hit overlays for preview click-to-scroll
        wipe(_hitOverlays)
        local overlayLevel = container:GetFrameLevel() + 20
        CreateHitOverlay(barFrame, "castBar", overlayLevel)
        CreateHitOverlay(iconFrame, "castIcon", overlayLevel + 5)
        if cb.showTimer then
            local ttHit = CreateFrame("Frame", nil, bar)
            ttHit:SetPoint("TOPLEFT", timerText, "TOPLEFT", -2, 2)
            ttHit:SetPoint("BOTTOMRIGHT", timerText, "BOTTOMRIGHT", 2, -2)
            CreateHitOverlay(ttHit, "castTimer", overlayLevel + 5)
        end
        if cb.showSpellText then
            local stHit = CreateFrame("Frame", nil, bar)
            stHit:SetPoint("TOPLEFT", spellText, "TOPLEFT", -2, 2)
            stHit:SetPoint("BOTTOMRIGHT", spellText, "BOTTOMRIGHT", 2, -2)
            CreateHitOverlay(stHit, "castSpellText", overlayLevel + 5)
        end

        -- Hint text
        local TOTAL_H = 80
        _headerBaseH = TOTAL_H
        local hintShown = not IsPreviewHintDismissed()
        if hintShown then
            if not _previewHintFS then
                local hintHost = CreateFrame("Frame", nil, hdr)
                hintHost:SetAllPoints(hdr)
                _previewHintFS = EllesmereUI.MakeFont(hintHost, 11, nil, 1, 1, 1)
                _previewHintFS:SetAlpha(0.45)
                _previewHintFS:SetText("Click elements to scroll to and highlight their options")
            end
            _previewHintFS:GetParent():SetParent(hdr)
            _previewHintFS:GetParent():Show()
            _previewHintFS:ClearAllPoints()
            _previewHintFS:SetPoint("BOTTOM", hdr, "BOTTOM", 0, 20)
            _previewHintFS:Show()
            TOTAL_H = TOTAL_H + 35
        elseif _previewHintFS then
            _previewHintFS:Hide()
        end

        return TOTAL_H
    end

    ---------------------------------------------------------------------------
    --  Cast Bar page
    ---------------------------------------------------------------------------
    local function BuildCastBarPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        parent._showRowDivider = true

        _castBarPreviewFill = math.random(30, 85) / 100
        ShuffleCastBarIcons()
        EllesmereUI:SetContentHeader(_castBarPreviewBuilder)

        -- Wipe click mappings (shared with display page)
        wipe(_clickMappings)

        -- Re-append SharedMedia textures for cast bar (catches lazy-registered SM packs)
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(
                _G._ERB_CastBarTextureNames or {},
                _G._ERB_CastBarTextureOrder or {},
                nil,
                _G._ERB_CastBarTextures
            )
        end
        -- Texture dropdown values (same as nameplates)
        local texValues = {}
        local texOrder = {}
        do
            local names = _G._ERB_CastBarTextureNames or {}
            local order = _G._ERB_CastBarTextureOrder or {}
            local lookup = _G._ERB_CastBarTextures or {}
            for _, key in ipairs(order) do
                if key ~= "---" then
                    texValues[key] = names[key] or key
                end
                texOrder[#texOrder + 1] = key
            end
            texValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    return lookup[key]
                end,
            }
        end

        local castOff = function() local p = DB(); return p and not p.castBar.enabled end

        local function RefreshCast()
            if _G._ERB_Apply then _G._ERB_Apply() end
            if EllesmereUI.NotifyElementResized then
                EllesmereUI.NotifyElementResized("ERB_CastBar")
            end
            UpdateCastBarPreview()
        end

        local castSection
        castSection, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

        -- Row 1: Enable Player Cast Bar | Show Spell Icon
        local castEnableRow
        castEnableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.enabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.enabled = v; RefreshCast()
                  EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Show Spell Icon",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.showIcon ~= false end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showIcon = v; RefreshCast()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        -- Inline cog (DIRECTIONS) on Enable for x/y position
        do
            local rgn = castEnableRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Cast Bar Position",
                rows = {
                    { type = "slider", label = "X Offset", min = -600, max = 600, step = 1,
                      get = function() local p = DB(); return p and p.castBar.anchorX or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.anchorX = v; RefreshCast()
                      end },
                    { type = "slider", label = "Y Offset", min = -600, max = 600, step = 1,
                      get = function() local p = DB(); return p and p.castBar.anchorY or -54 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.anchorY = v; RefreshCast()
                      end },
                },
                footer = { unlockKey = "ERB_CastBar" },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Player Cast Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisCB1()
                local p = DB()
                if p and not p.castBar.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisCB1)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisCB1)
            UpdateCogDisCB1()
        end

        -- Row 2: Height | Width (sync icons push to power + health bars)
        local classSizeRow
        local cbhDis, cbhTip, cbhRaw = EllesmereUI.MatchGuard("ERB_CastBar", "Height", castOff, "Enable Player Cast Bar")
        local cbwDis, cbwTip, cbwRaw = EllesmereUI.MatchGuard("ERB_CastBar", "Width", castOff, "Enable Player Cast Bar")
        classSizeRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 60, step = 1,
              disabled = cbhDis, disabledTooltip = cbhTip, rawTooltip = cbhRaw,
              getValue = function() local p = DB(); return p and p.castBar.height or 20 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.height = v; RefreshCast()
              end },
            { type = "slider", text = "Width",
              min = 50, max = 500, step = 1,
              disabled = cbwDis, disabledTooltip = cbwTip, rawTooltip = cbwRaw,
              getValue = function() local p = DB(); return p and p.castBar.width or 220 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.width = v; RefreshCast()
              end }
        );  y = y - h

        _, h = W:Spacer(parent, y, 16);  y = y - h

        -----------------------------------------------------------------------
        local displaySection
        displaySection, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

        -- Row: Cast Bar Border Style dropdown (+ inline offset cog)
        do
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local cbBsRow
            cbBsRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style",
                  disabled = castOff,
                  disabledTooltip = "Enable Player Cast Bar",
                  values=texValues, order=texOrder,
                  getValue=function() local p = DB(); return p and p.castBar.borderTexture or "solid" end,
                  setValue=function(v)
                      local p = DB(); if not p then return end
                      p.castBar.borderTexture = v; p.castBar.borderTextureOffset = nil; p.castBar.borderTextureOffsetY = nil; p.castBar.borderTextureShiftX = nil; p.castBar.borderTextureShiftY = nil
                      if v ~= "solid" then
                          p.castBar.borderR = 1; p.castBar.borderG = 1; p.castBar.borderB = 1; p.castBar.borderA = 1
                      else
                          p.castBar.borderR = 0; p.castBar.borderG = 0; p.castBar.borderB = 0; p.castBar.borderA = 1
                      end
                      local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                      if defSz then p.castBar.borderSize = defSz end
                      RefreshCast(); EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Border Size",
                  min = 0, max = 4, step = 1,
                  disabled = castOff,
                  disabledTooltip = "Enable Player Cast Bar",
                  getValue = function()
                      local p = DB(); return p and (p.castBar.borderSize or 0) or 0
                  end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.castBar.borderSize = v; RefreshCast(); EllesmereUI:RefreshPage()
                  end });  y = y - h
            -- Inline border color swatch on Border slider (right region)
            do
                local rgn = cbBsRow._rightRegion
                local ctrl = rgn._control
                local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, cbBsRow:GetFrameLevel() + 3,
                    function()
                        local p = DB()
                        return (p and p.castBar.borderR or 0), (p and p.castBar.borderG or 0),
                               (p and p.castBar.borderB or 0), (p and p.castBar.borderA or 1)
                    end,
                    function(r, g, b, a)
                        local p = DB(); if not p then return end
                        p.castBar.borderR, p.castBar.borderG, p.castBar.borderB, p.castBar.borderA = r, g, b, a
                        RefreshCast(); EllesmereUI:RefreshPage()
                    end,
                    true, 20)
                PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                -- Disable swatch when border size is 0
                local borderSwatchBlock = CreateFrame("Frame", nil, borderSwatch)
                borderSwatchBlock:SetAllPoints()
                borderSwatchBlock:SetFrameLevel(borderSwatch:GetFrameLevel() + 10)
                borderSwatchBlock:EnableMouse(true)
                borderSwatchBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(borderSwatch, EllesmereUI.DisabledTooltip("Set Border above 0"))
                end)
                borderSwatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateBorderSwatchState()
                    local p = DB()
                    local noBorder = not p or (p.castBar.borderSize or 0) == 0
                    if noBorder then borderSwatch:SetAlpha(0.3); borderSwatchBlock:Show()
                    else borderSwatch:SetAlpha(1); borderSwatchBlock:Hide() end
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch(); UpdateBorderSwatchState() end)
                UpdateBorderSwatchState()
            end
            do
                local rgn = cbBsRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    rows = {
                        { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.castBar.borderTextureOffset
                              if v then return v end
                              local dox = EllesmereUI.GetBorderDefaults("resourcebars", p.castBar.borderTexture or "solid", p.castBar.borderSize or 0)
                              return dox
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.castBar.borderTextureOffset = v; RefreshCast(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.castBar.borderTextureOffsetY
                              if v then return v end
                              local _, doy = EllesmereUI.GetBorderDefaults("resourcebars", p.castBar.borderTexture or "solid", p.castBar.borderSize or 0)
                              return doy
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.castBar.borderTextureOffsetY = v; RefreshCast(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.castBar.borderTextureShiftX
                              if v then return v end
                              local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", p.castBar.borderTexture or "solid", p.castBar.borderSize or 0)
                              return dsx
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.castBar.borderTextureShiftX = v == 0 and nil or v; RefreshCast(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.castBar.borderTextureShiftY
                              if v then return v end
                              local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", p.castBar.borderTexture or "solid", p.castBar.borderSize or 0)
                              return dsy
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.castBar.borderTextureShiftY = v == 0 and nil or v; RefreshCast(); EllesmereUI:RefreshPage()
                          end },
                    },
                })
                local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                local function UpdateCogVis()
                    local p = DB()
                    local tex = p and p.castBar.borderTexture or "solid"
                    if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
        end

        -- Row 2: Show Spark | Color (multiSwatch + cog: gradient)
        local castColorRow
        castColorRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Spark",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.showSpark end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showSpark = v; RefreshCast()
              end },
            { type = "multiSwatch", text = "Color",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              swatches = {
                  { tooltip = "Gradient End Color", hasAlpha = true,
                    getValue = function()
                        local p = DB()
                        if not p then return 0.20, 0.20, 0.80, 1 end
                        return p.castBar.gradientR, p.castBar.gradientG, p.castBar.gradientB, p.castBar.gradientA
                    end,
                    setValue = function(r, g, b, a)
                        local p = DB(); if not p then return end
                        p.castBar.gradientR, p.castBar.gradientG, p.castBar.gradientB, p.castBar.gradientA = r, g, b, a
                        RefreshCast()
                    end },
                  { tooltip = "Custom Colored", hasAlpha = true,
                    getValue = function()
                        local p = DB()
                        if not p then
                            local _, cf = UnitClass("player")
                            local cc = CLASS_COLORS[cf]
                            return cc and cc[1] or 1, cc and cc[2] or 0.70, cc and cc[3] or 0, 1
                        end
                        return p.castBar.fillR, p.castBar.fillG, p.castBar.fillB, p.castBar.fillA
                    end,
                    setValue = function(r, g, b, a)
                        local p = DB(); if not p then return end
                        p.castBar.fillR, p.castBar.fillG, p.castBar.fillB, p.castBar.fillA = r, g, b, a
                        if p.castBar.classColored then p.castBar.classColored = false end
                        RefreshCast(); EllesmereUI:RefreshPage()
                    end,
                    onClick = function(self)
                        local p = DB(); if not p then return end
                        if p.castBar.classColored then
                            p.castBar.classColored = false
                            RefreshCast(); EllesmereUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        local p = DB()
                        return (p and not p.castBar.classColored) and 1 or 0.3
                    end },
                  { tooltip = "Class Colored",
                    getValue = function()
                        local _, classFile = UnitClass("player")
                        local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                        if cc then return cc.r, cc.g, cc.b, 1 end
                        return 1, 0.70, 0, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        local p = DB(); if not p then return end
                        p.castBar.classColored = true
                        RefreshCast(); EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local p = DB()
                        return (not p or p.castBar.classColored == true) and 1 or 0.3
                    end },
              } }
        );  y = y - h
        -- Inline cog on Color for gradient settings
        do
            local rgn = castColorRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Gradient Settings",
                rows = {
                    { type = "toggle", label = "Enable Gradient",
                      get = function() local p = DB(); return p and p.castBar.gradientEnabled end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.gradientEnabled = v; RefreshCast()
                          EllesmereUI:RefreshPage()
                      end },
                    { type = "dropdown", label = "Gradient Direction",
                      values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                      order = { "HORIZONTAL", "VERTICAL" },
                      get = function() local p = DB(); return p and p.castBar.gradientDir or "HORIZONTAL" end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.gradientDir = v; RefreshCast()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Player Cast Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisGrad()
                local p = DB()
                if p and not p.castBar.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisGrad)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisGrad)
            UpdateCogDisGrad()
        end

        -- Manual gradient swatch enable/disable (cursor addon pattern)
        do
            local swatch = castColorRow._rightRegion._control
            local function UpdateGradientSwatch()
                local p = DB()
                if not p or not p.castBar.enabled then
                    swatch:SetAlpha(0.15); swatch:Disable()
                    swatch._disabledTooltip = "Enable Player Cast Bar"
                elseif not p.castBar.gradientEnabled then
                    swatch:SetAlpha(0.15); swatch:Disable()
                    swatch._disabledTooltip = "Enable Gradient"
                else
                    swatch:SetAlpha(1); swatch:Enable()
                    swatch._disabledTooltip = nil
                end
            end
            UpdateGradientSwatch()
            EllesmereUI.RegisterWidgetRefresh(UpdateGradientSwatch)
        end

        -- Row 3: Bar Texture | Spell Text (cog RESIZE: text size + x/y)
        local textRow
        textRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Bar Texture",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              values = texValues, order = texOrder,
              getValue = function() local p = DB(); return p and p.castBar.texture or "none" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.texture = v; RefreshCast()
              end },
            { type = "toggle", text = "Spell Text",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.showSpellText end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showSpellText = v; RefreshCast()
              end }
        );  y = y - h
        -- Inline cog (RESIZE) on Spell Text for text size + x/y
        do
            local rgn = textRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Spell Text Settings",
                rows = {
                    { type = "slider", label = "Text Size", min = 8, max = 24, step = 1,
                      get = function() local p = DB(); return p and p.castBar.spellTextSize or 11 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.spellTextSize = v; RefreshCast()
                      end },
                    { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                      get = function() local p = DB(); return p and p.castBar.spellTextX or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.spellTextX = v; RefreshCast()
                      end },
                    { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                      get = function() local p = DB(); return p and p.castBar.spellTextY or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.spellTextY = v; RefreshCast()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Player Cast Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisSpellText()
                local p = DB()
                if p and (not p.castBar.enabled or not p.castBar.showSpellText) then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisSpellText)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisSpellText)
            UpdateCogDisSpellText()
        end
        -- Row 4: Duration Text (cog RESIZE: timer size + x/y) | Show Total Duration
        local timerRow
        timerRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Duration Text",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.showTimer end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showTimer = v; RefreshCast()
              end },
            { type = "toggle", text = "Show Total Duration",
              tooltip = "Shows elapsed / total duration (e.g. 0.4 / 2.0) instead of counting down from the total.",
              disabled = function()
                  local p = DB()
                  return castOff() or not (p and p.castBar.showTimer)
              end,
              disabledTooltip = "Enable Duration Text",
              getValue = function() local p = DB(); return p and p.castBar.showTotalDuration end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showTotalDuration = v; RefreshCast()
              end }
        );  y = y - h
        -- Inline cog (RESIZE) on Duration Text for timer size + x/y
        do
            local rgn = timerRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Timer Settings",
                rows = {
                    { type = "slider", label = "Timer Size", min = 8, max = 24, step = 1,
                      get = function() local p = DB(); return p and p.castBar.timerSize or 11 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.timerSize = v; RefreshCast()
                      end },
                    { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                      get = function() local p = DB(); return p and p.castBar.timerX or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.timerX = v; RefreshCast()
                      end },
                    { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                      get = function() local p = DB(); return p and p.castBar.timerY or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.timerY = v; RefreshCast()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Player Cast Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisTimer()
                local p = DB()
                if p and (not p.castBar.enabled or not p.castBar.showTimer) then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisTimer)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisTimer)
            UpdateCogDisTimer()
        end

        -- ── MARKS section ───────────────────────────────────────────
        _, h = W:SectionHeader(parent, "TICK MARKERS", y);  y = y - h

        local marksOff = function()
            local p = DB()
            return castOff() or not (p and p.castBar.showChannelTicks)
        end

        -- Helper: attach an inline color swatch to a region with disabled overlay
        local function AttachInlineSwatch(rgn, getFunc, setFunc, disabledFunc, disabledTooltip)
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, getFunc, setFunc, true, 20)
            PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -12, 0)

            local block = CreateFrame("Frame", nil, swatch)
            block:SetAllPoints()
            block:SetFrameLevel(swatch:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip(disabledTooltip))
            end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                local off = disabledFunc()
                swatch:SetAlpha(off and 0.3 or 1)
                if off then block:Show() else block:Hide() end
                updateSwatch()
            end)
            local initOff = disabledFunc()
            swatch:SetAlpha(initOff and 0.3 or 1)
            if initOff then block:Show() else block:Hide() end
        end

        -- Marks Row 1: Enable Tick Markers (master) | Channel Ticks (+ color)
        local marksRow1
        marksRow1, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Tick Markers",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.showChannelTicks end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showChannelTicks = v
                  if v and not (p.castBar.showTickMarks or p.castBar.showLastTick) then
                      p.castBar.showTickMarks = true
                  end
                  RefreshCast()
                  EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Channel Ticks",
              tooltip = "Damage tick marks on channeled spells. Only supported spells are shown — request missing spells on Discord.",
              disabled = marksOff,
              disabledTooltip = "Enable Tick Markers",
              getValue = function() local p = DB(); return p and p.castBar.showTickMarks end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showTickMarks = v; RefreshCast()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        AttachInlineSwatch(marksRow1._rightRegion,
            function()
                local p = DB(); if not p then return 1, 1, 1, 0.7 end
                return p.castBar.tickMarksR or 1, p.castBar.tickMarksG or 1,
                       p.castBar.tickMarksB or 1, p.castBar.tickMarksA or 0.7
            end,
            function(r, g, b, a)
                local p = DB(); if not p then return end
                p.castBar.tickMarksR = r; p.castBar.tickMarksG = g
                p.castBar.tickMarksB = b; p.castBar.tickMarksA = a
                RefreshCast()
            end,
            function() return marksOff() or not (DB() and DB().castBar.showTickMarks) end,
            "Enable Channel Ticks"
        )

        -- Marks Row 2: Last Tick (+ color) | Colored Empowered Stages
        local marksRow2
        marksRow2, h = W:DualRow(parent, y,
            { type = "toggle", text = "Last Tick",
              tooltip = "Highlights the final damage tick. Requires a supported channeled spell.",
              disabled = marksOff,
              disabledTooltip = "Enable Tick Markers",
              getValue = function() local p = DB(); return p and p.castBar.showLastTick end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showLastTick = v; RefreshCast()
                  EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Colored Empowered Stages",
              tooltip = "Changes the cast bar color based on the current empower stage. Colors transition from red (stage 1) through yellow to green (max stage).",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.coloredEmpowerStages end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.coloredEmpowerStages = v; RefreshCast()
              end }
        );  y = y - h

        AttachInlineSwatch(marksRow2._leftRegion,
            function()
                local p = DB(); if not p then return 1, 0.82, 0, 0.95 end
                return p.castBar.lastTickR or 1, p.castBar.lastTickG or 0.82,
                       p.castBar.lastTickB or 0, p.castBar.lastTickA or 0.95
            end,
            function(r, g, b, a)
                local p = DB(); if not p then return end
                p.castBar.lastTickR = r; p.castBar.lastTickG = g
                p.castBar.lastTickB = b; p.castBar.lastTickA = a
                RefreshCast()
            end,
            function() return marksOff() or not (DB() and DB().castBar.showLastTick) end,
            "Enable Last Tick"
        )

        -- ── LATENCY section ─────────────────────────────────────────
        _, h = W:SectionHeader(parent, "LATENCY", y);  y = y - h

        local latOff = function()
            local p = DB()
            return castOff() or not (p and p.castBar.latencyEnabled)
        end

        -- Latency Row 1: Enable Latency Overlay (+ color) | Show Latency Text
        local latRow1
        latRow1, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Latency Overlay",
              tooltip = "Shows a colored overlay at the end of the cast bar representing your network latency for each spell. Helps you time spell queuing.",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.latencyEnabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.latencyEnabled = v; RefreshCast()
                  EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Show Latency Text",
              tooltip = "Appends your latency in milliseconds to the cast timer, e.g. 1.8 (42ms).",
              disabled = latOff,
              disabledTooltip = "Enable Latency Overlay",
              getValue = function() local p = DB(); return p and p.castBar.latencyShowText end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.latencyShowText = v; RefreshCast()
              end }
        );  y = y - h

        AttachInlineSwatch(latRow1._leftRegion,
            function()
                local p = DB(); if not p then return 0.835, 0.290, 0.290, 1 end
                return p.castBar.latencyR or 0.835, p.castBar.latencyG or 0.290,
                       p.castBar.latencyB or 0.290, p.castBar.latencyA or 1
            end,
            function(r, g, b, a)
                local p = DB(); if not p then return end
                p.castBar.latencyR = r; p.castBar.latencyG = g
                p.castBar.latencyB = b; p.castBar.latencyA = a
                RefreshCast()
            end,
            latOff,
            "Enable Latency Overlay"
        )

        -- Wire up click mappings for cast bar preview hit overlays
        _clickMappings.castBar       = { section = castSection, target = classSizeRow }
        _clickMappings.castIcon      = { section = castSection, target = castEnableRow, slotSide = "right" }
        _clickMappings.castSpellText = { section = displaySection, target = textRow, slotSide = "left" }
        _clickMappings.castTimer     = { section = displaySection, target = textRow, slotSide = "right" }

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIResourceBars", {
        title       = "Resource Bars",
        description = "Custom class resource, health, and mana bar display.",
        pages       = { PAGE_DISPLAY, PAGE_CASTBAR },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_DISPLAY then
                return BuildBarDisplayPage(pageName, parent, yOffset)
            elseif pageName == PAGE_CASTBAR then
                return BuildCastBarPage(pageName, parent, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DISPLAY then
                return _previewHeaderBuilder
            elseif pageName == PAGE_CASTBAR then
                return _castBarPreviewBuilder
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_DISPLAY then
                -- Randomize preview values when switching TO this tab
                local minPips = math.floor(5 * 0.50 + 0.5)
                local maxPips = math.floor(5 * 0.75 + 0.5)
                _previewPipCount = math.random(minPips, maxPips)
                _previewBarFillPct = math.random(30, 80)
                UpdatePreviewHeader()
                -- Refresh hint visibility never recreate here, just show/hide
                local dismissed = IsPreviewHintDismissed()
                if _previewHintFS then
                    if dismissed then
                        _previewHintFS:Hide()
                    else
                        _previewHintFS:SetAlpha(0.45)
                        _previewHintFS:Show()
                        if _previewHintFS:GetParent() then _previewHintFS:GetParent():Show() end
                    end
                end
                -- Set correct header height based on current hint state
                if _headerBaseH > 0 then
                    EllesmereUI:SetContentHeaderHeightSilent(_headerBaseH + (dismissed and 0 or 35))
                end
            elseif pageName == PAGE_CASTBAR then
                -- Randomize cast bar preview fill each time the tab is opened
                _castBarPreviewFill = math.random(30, 85) / 100
                UpdateCastBarPreview()
            end
        end,
        onReset = function()
            if _G._ERB_AceDB then
                _G._ERB_AceDB:ResetProfile()
            end
            Refresh()
        end,
    })

    SLASH_ERBOPT1 = "/erbopt"
    SlashCmdList.ERBOPT = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIResourceBars")
    end
end)
