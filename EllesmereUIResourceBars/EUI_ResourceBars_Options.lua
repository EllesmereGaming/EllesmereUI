-------------------------------------------------------------------------------
--  EUI_ResourceBars_Options.lua
--  Registers the Resource Bars module with EllesmereUI
--  Pages: Class, Power and Health Bars | Cast Bar | Unlock Mode
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local abs = math.abs

local PAGE_DISPLAY   = "Class, Power and Health Bars"
local PAGE_CASTBAR   = "Cast Bar"
local PAGE_GCD       = "GCD Bar"
local PAGE_TOTEM     = "Totem Bar"
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
    local HasClassResource     -- forward declaration; assigned below

    -- Helper: returns true if the current class/spec has any secondary resource
    HasClassResource = function()
        local gsr = _G._ERB_GetSecondaryResource
        return gsr and gsr() ~= nil
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
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, f == "") end
        fs:SetFont(font, size, f)
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

    -- Dark Mode preview colours pull from the global per-profile palette
    -- (EllesmereUI.GetDarkModeFill / GetDarkModeBg). Like the live bars, the
    -- preview ignores the Dark Mode opacity sliders (background drawn at alpha 1).

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

    -- Discrete pip count for the current spec's preview: use the real
    -- resource max (Fury Whirlwind 4, Arms Sweeping Strikes 12/18, DK runes
    -- 6, Maelstrom Weapon 5/10, ...) so the preview matches the live bar;
    -- generic 5 as fallback when there is no discrete secondary.
    local function PreviewPipCount()
        local gsr = _G._ERB_GetSecondaryResource
        local info = gsr and gsr()
        if not info or info.type == "bar" then return 5 end
        local m = info.max
        -- Talent-dependent maxes come from the live trackers
        if info.power == "SWEEPING_STRIKES" and EllesmereUI and EllesmereUI.GetSweepingStrikes then
            local _, realMax = EllesmereUI.GetSweepingStrikes()
            if realMax and realMax > 0 then m = realMax end
        elseif info.power == "WHIRLWIND_STACKS" and EllesmereUI and EllesmereUI.GetWhirlwindStacks then
            local _, realMax = EllesmereUI.GetWhirlwindStacks()
            if realMax and realMax > 0 then m = realMax end
        elseif info.power == "MAELSTROM_WEAPON" and EllesmereUI and EllesmereUI.GetMaelstromWeapon then
            local _, realMax = EllesmereUI.GetMaelstromWeapon()
            if realMax and realMax > 0 then m = realMax end
        end
        if type(m) == "number" and m >= 2 and m <= 20 then return m end
        return 5
    end

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
        local isBar = ns.IsBarTypeSecondary()

        -- Class resource preview
        local pc = _previewFrames.pipContainer
        if pc then
            local pipH = sp.pipHeight

            -- Resolve fill color
            local _, cf = UnitClass("player")
            local cc = CLASS_COLORS[cf]
            local pr, pg, pb
            if sp.darkTheme then
                pr, pg, pb = EllesmereUI.GetDarkModeFill()
            elseif sp.resourceColored then
                -- Per-spec resource/power color; falls back to class color.
                local gsr = _G._ERB_GetSecondaryResource
                local rslv = _G._ERB_ResolveSecondaryResourceColor
                local rr, rg, rb
                if gsr and rslv then
                    local info = gsr()
                    if info and info.power ~= nil then rr, rg, rb = rslv(info.power) end
                end
                if rr then pr, pg, pb = rr, rg, rb
                else pr, pg, pb = cc and cc[1] or 0.95, cc and cc[2] or 0.90, cc and cc[3] or 0.60 end
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
                        local _dbr, _dbg, _dbb = EllesmereUI.GetDarkModeBg()
                        pc._barBg:SetColorTexture(_dbr, _dbg, _dbb, 1)
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
                    -- Fill Opacity preview: translucent fill + bg over the
                    -- empty portion only (mirrors the live bar)
                    local _pvOp = (sp.fillOpacity or 100) / 100
                    pc._barFill:SetAlpha(_pvOp)
                    if pc._barBg then
                        pc._barBg:ClearAllPoints()
                        if _pvOp < 1 then
                            pc._barBg:SetPoint("TOPLEFT", pc._barFill, "TOPRIGHT", 0, 0)
                            pc._barBg:SetPoint("BOTTOMRIGHT", pc, "BOTTOMRIGHT", 0, 0)
                        else
                            pc._barBg:SetAllPoints(pc)
                        end
                    end
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
                    local _pvHashPct = _pvTsEntry and _pvTsEntry.hashMode == "percent"
                    local PP = EllesmereUI and EllesmereUI.PP
                    local onePx = PP and PP.Scale(1) or 1
                    for i, v in ipairs(vals) do
                        local _pvFrac, _pvOk
                        if _pvHashPct then
                            _pvOk = (v <= 100); _pvFrac = v / 100
                        else
                            _pvOk = (v <= previewMax); _pvFrac = v / previewMax
                        end
                        if _pvOk then
                            if not ticks[i] then
                                local t = pc:CreateTexture(nil, "OVERLAY", nil, 7)
                                t:SetColorTexture(1, 1, 1, 1)
                                t:SetSnapToPixelGrid(false)
                                t:SetTexelSnappingBias(0)
                                ticks[i] = t
                            end
                            local t = ticks[i]
                            t:ClearAllPoints()
                            local frac = _pvFrac
                            local off = PP and PP.Scale(totalW * frac) or (totalW * frac)
                            t:SetSize(onePx, pipH)
                            t:SetPoint("TOPLEFT", pc, "TOPLEFT", off, 0)
                            t:Show()
                        end
                    end
                end

                -- Hide pips if any exist from a previous build
                for _, pip in ipairs(_previewFrames.pips) do pip:Hide() end
                -- No pips in bar-type -> hide any gap fills
                if pc._gapFills then for i = 1, #pc._gapFills do pc._gapFills[i]:Hide() end end
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
                local numPips = PreviewPipCount()
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
                    -- _previewPipCount is randomized against the generic
                    -- 5-pip preview; rescale for specs with other pip counts
                    -- (e.g. 12/18 Sweeping Strikes charges).
                    if numPips ~= 5 then
                        filledCount = math.max(1, math.min(numPips,
                            math.floor(_previewPipCount / 5 * numPips + 0.5)))
                    end
                end
                -- Expose to the count-text block below so the number always
                -- matches the lit segments
                pc._pvShownCount = filledCount
                local useThresh = _pvTsEnabled
				-- use current spec threshold color if configured
				local tr = _pvTsEntry2 and _pvTsEntry2.thresholdR or sp.thresholdR
				local tg = _pvTsEntry2 and _pvTsEntry2.thresholdG or sp.thresholdG
				local tb = _pvTsEntry2 and _pvTsEntry2.thresholdB or sp.thresholdB

                -- Top up pip frames if this spec needs more than were built
                -- (pip counts differ per spec: 3-18). Styling is applied in
                -- the loop below, so bare bg+fill textures suffice here.
                for i = #_previewFrames.pips + 1, numPips do
                    local pip = CreateFrame("Frame", nil, pc)
                    local bg = pip:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints()
                    pip._bg = bg
                    local fill = pip:CreateTexture(nil, "ARTWORK")
                    fill:SetAllPoints()
                    pip._fill = fill
                    _previewFrames.pips[i] = pip
                end
                for i = 1, math.min(numPips, #_previewFrames.pips) do
                    local pip = _previewFrames.pips[i]
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
                        local _dbr, _dbg, _dbb = EllesmereUI.GetDarkModeBg()
                        pip._bg:SetColorTexture(_dbr, _dbg, _dbb, 1)
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
                    -- Fill Opacity preview: translucent fill; active pips hide
                    -- their bg so the fill reveals what is behind (mirrors the
                    -- live pips)
                    local _pvPipOp = (sp.fillOpacity or 100) / 100
                    pip._fill:SetAlpha(_pvPipOp)
                    pip._bg:SetAlpha((active and _pvPipOp < 1) and 0 or 1)

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
                            local fakeDurations = { 2, 4, 6, 7, 9, 10 }
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

                -- Optional gap-color fill layer (mirrors the live bar; opt-in).
                if not pc._gapFills then pc._gapFills = {} end
                do
                    local pvFills = pc._gapFills
                    if sp.gapColorEnabled and numPips > 1 then
                        local gr, gg, gb, ga = sp.gapR or 0, sp.gapG or 0, sp.gapB or 0, sp.gapA or 1
                        local gn = 0
                        for i = 1, numPips - 1 do
                            local gx = pipX[i] + pipW[i]
                            local gw = pipX[i + 1] - gx
                            if gw and gw > 0 then
                                gn = gn + 1
                                local tex = pvFills[gn]
                                if not tex then
                                    tex = pc:CreateTexture(nil, "BACKGROUND", nil, 0)
                                    UnsnapTex(tex)
                                    pvFills[gn] = tex
                                end
                                tex:SetColorTexture(gr, gg, gb, ga)
                                tex:ClearAllPoints()
                                tex:SetPoint("TOPLEFT", pc, "TOPLEFT", gx, 0)
                                tex:SetPoint("BOTTOMLEFT", pc, "BOTTOMLEFT", gx, 0)
                                tex:SetWidth(gw)
                                tex:Show()
                            end
                        end
                        for i = gn + 1, #pvFills do pvFills[i]:Hide() end
                    else
                        for i = 1, #pvFills do pvFills[i]:Hide() end
                    end
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
                pc._barBorderFrame = bf
            end
            pc._barBorderFrame:SetFrameLevel(sp.borderBehind and math.max(0, pc:GetFrameLevel() - 1) or (pc:GetFrameLevel() + 2))
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
                local _pvTA = sp.textAnchor or "CENTER"
                pc._countText:SetPoint(_pvTA, pc, _pvTA, sp.textXOffset or 0, sp.textYOffset or 0)
                if isBar then
                    local percentSuffix = (sp.showPercent == false) and "" or "%"
                    pc._countText:SetText(tostring(_previewBarFillPct) .. percentSuffix)
                else
                    -- Mirror the pip loop's filled count (threshold-resolved
                    -- and rescaled to the spec's pip count) so the number
                    -- always matches the lit segments. Live pip resources
                    -- render the bare count only -- the "cur / max" format
                    -- belongs exclusively to bar-type stack bars (Show Max
                    -- Stacks), which the isBar branch above previews.
                    local shown = pc._pvShownCount or _previewPipCount
                    pc._countText:SetText(tostring(shown))
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
        local isBar = ns.IsBarTypeSecondary()

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
            local numPips = PreviewPipCount()
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
                    local _dbr, _dbg, _dbb = EllesmereUI.GetDarkModeBg()
                    bg:SetColorTexture(_dbr, _dbg, _dbb, 1)
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
        do local _pvTA = sp.textAnchor or "CENTER"; countText:SetPoint(_pvTA, pipC, _pvTA, sp.textXOffset or 0, sp.textYOffset or 0) end
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
                _previewHintFS:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
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
    -- Druid-only per-form popup button. `field` picks the map the toggles write:
    -- "textDisabledForms" (text rows) or "barDisabledForms" (whole-bar enable rows).
    local function AddFormDisableBtn(rgn, leftOf, cfgFn, refreshFn, field, title, tooltip)
        local _, classFile = UnitClass("player")
        if classFile ~= "DRUID" then return end
        field = field or "textDisabledForms"
        title = title or "Enable/Disable per Form"
        tooltip = tooltip or EllesmereUI.L(title)
        local FORMS = { { key = "mana", label = "Caster" },
                        { key = "rage", label = "Bear" },
                        { key = "energy", label = "Cat" } }
        local rows = {}
        for _, f in ipairs(FORMS) do
            local key = f.key
            rows[#rows + 1] = { type = "toggle", label = f.label,
                get = function()
                    local c = cfgFn()
                    return not (c and c[field] and c[field][key])
                end,
                set = function(v)
                    local c = cfgFn(); if not c then return end
                    if v then
                        if c[field] then c[field][key] = nil end
                    else
                        c[field] = c[field] or {}
                        c[field][key] = true
                    end
                    refreshFn()
                end }
        end
        local _, formShow = EllesmereUI.BuildCogPopup({
            title = title, bgAlpha = 1,
            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
            rows = rows,
        })
        local btn = CreateFrame("Button", nil, rgn)
        btn:SetSize(26, 26)
        btn:SetPoint("RIGHT", leftOf or rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = btn
        btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        btn:SetAlpha(0.4)
        local tex = btn:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetDesaturated(true)
        tex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\class-full\\glyph.tga")
        tex:SetTexCoord(0.375, 0.5, 0, 0.125)  -- DRUID glyph
        btn:SetScript("OnEnter", function(self) self:SetAlpha(0.7); EllesmereUI.ShowWidgetTooltip(self, tooltip) end)
        btn:SetScript("OnLeave", function(self) self:SetAlpha(0.4); EllesmereUI.HideWidgetTooltip() end)
        btn:SetScript("OnClick", function(self) formShow(self) end)
        return btn
    end
    -- The L() literals keep both popup titles in the static locale key list
    -- (.tools/extract-locale-keys.sh only sees literal string arguments).
    local function AddFormTextBtn(rgn, leftOf, cfgFn, refreshFn)
        return AddFormDisableBtn(rgn, leftOf, cfgFn, refreshFn, "textDisabledForms",
            "Enable/Disable per Form", EllesmereUI.L("Enable/Disable per Form"))
    end
    local function AddFormBarBtn(rgn, cfgFn, refreshFn)
        return AddFormDisableBtn(rgn, nil, cfgFn, refreshFn, "barDisabledForms",
            "Enable/Disable Bar per Form", EllesmereUI.L("Enable/Disable Bar per Form"))
    end

    ---------------------------------------------------------------------------
    --  multi-band threshold popup definition editor (opt-in). A small popup, opened per
    --  threshold-spec entry from its "Bands" button, that edits entry.bands --
    --  an ordered list of { to=<boundary>, r,g,b,a } color stops. `to` is a
    --  resource count for pip resources, or a percent/value for bar-type bars.
    --  ShowBandEditor() rebinds it to the calling bar each time it opens.
    ---------------------------------------------------------------------------
    local _bandCloseIcon = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
    local bandPopup
    local _bandRows = {}
    local _bandEntryIdx
    local _bandGetBarData, _bandRefreshFn, _bandCountBased
    local _bandLockPercent, _bandPercentMax   -- Brewmaster stagger: force percent, cap 500
    local _bandDefR, _bandDefG, _bandDefB, _bandDefA = 1, 0.2, 0.2, 1
    local _bandModeRow, _bandModeSeg, _bandModeSegRefresh, _bandModeHint, _bandAddBtn, _bandTitleFS
    local _bandReverseRow, _bandReverseSeg, _bandReverseSegRefresh
    local BAND_POPUP_W = 300
    local BAND_ROW_H = 26
    local BAND_PAD = 14
    local BAND_GAP = 10
    local RefreshBandEditor  -- forward decl

    -- Shared explainer tooltip for the Multi toggle + Bands button.
    local BAND_HELP_TIP =
        "Color the bar by ranges instead of a single threshold.\n"
        .. "Up to (<=) / From (>=)\n"
		.. "Any remaning values outside the bands will use fill color.\n"
        .. "|cff888888Bars can use % or actual value; pip resources use counts.|r"

    local BAND_REPLACES_TIP =
        "Single threshold is off while Multi-band is on.\n"

    -- Shown on the greyed percent/value control for Brewmaster stagger.
    local STAGGER_PCT_TIP =
        "Stagger value can only be percent based"

    local function CurrentBandEntry()
        if not _bandEntryIdx or not _bandGetBarData then return nil end
        local bd = _bandGetBarData(); if not bd or not bd.thresholdSpecs then return nil end
        return bd.thresholdSpecs[_bandEntryIdx]
    end

    local function SortBands(bands)
        table.sort(bands, function(a, b) return (a.to or 0) < (b.to or 0) end)
    end

    local function BuildBandPopup()
        bandPopup = CreateFrame("Frame", nil, UIParent)
        bandPopup:SetFrameStrata("FULLSCREEN_DIALOG")
        bandPopup:SetFrameLevel(260)
        bandPopup:SetClampedToScreen(true)
        bandPopup:EnableMouse(true)
        bandPopup:SetScale(0.9)
        bandPopup:Hide()
        PP.Size(bandPopup, BAND_POPUP_W, 200)

        local bg = bandPopup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.08, 0.10, 0.97)
        PP.CreateBorder(bandPopup, 1, 1, 1, 0.18, 1, "BORDER", 7)

        local clickCatcher = CreateFrame("Button", nil, bandPopup)
        clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        clickCatcher:SetFrameLevel(bandPopup:GetFrameLevel() - 1)
        clickCatcher:SetAllPoints((EllesmereUI.GetMainFrame and EllesmereUI:GetMainFrame()) or UIParent)
        clickCatcher:SetScript("OnClick", function() bandPopup:Hide() end)
        clickCatcher:Hide()
        -- Close on entering combat
        bandPopup:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_REGEN_DISABLED" then self:Hide() end
        end)
        bandPopup:SetScript("OnShow", function(self)
            clickCatcher:Show()
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
            self:SetScript("OnUpdate", function(p)
                if IsMouseButtonDown("LeftButton") then
                    local mf = EllesmereUI._mainFrame
                    local dm = EllesmereUI._openDropdownMenu
                        if not p:IsMouseOver() and not (mf and mf:IsMouseOver()) and not (dm and dm:IsShown() and dm:IsMouseOver()) then p:Hide() end
                end
            end)
        end)
        bandPopup:SetScript("OnHide", function(self)
            clickCatcher:Hide()
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
            self:SetScript("OnUpdate", nil)
        end)

        _bandTitleFS = EllesmereUI.MakeFont(bandPopup, 13, nil, 1, 1, 1)
        _bandTitleFS:SetAlpha(0.6)
        _bandTitleFS:SetPoint("TOP", bandPopup, "TOP", 0, -BAND_PAD)
        _bandTitleFS:SetText(EllesmereUI.L("Color Bands"))

        -- Labeled row (label left, control right) -- matches the detail-pane rows.
        local function HeaderRow(labelText)
            local rf = CreateFrame("Frame", nil, bandPopup)
            rf:SetFrameLevel(bandPopup:GetFrameLevel() + 3)
            PP.Height(rf, BAND_ROW_H)
            local lbl = EllesmereUI.MakeFont(rf, 12, nil, 1, 1, 1)
            lbl:SetAlpha(0.6)
            lbl:SetPoint("LEFT", rf, "LEFT", 0, 0)
            lbl:SetText(EllesmereUI.L(labelText))
            rf._lbl = lbl
            return rf
        end

        -- Row: value units -- a segmented switch (Amount / Percent), bar-type only
        -- (count-based shows a hint instead).
        _bandModeRow = HeaderRow("Values as")
        _bandModeSeg, _, _bandModeSegRefresh = EllesmereUI.BuildSegmentedControl({
            parent    = _bandModeRow,
            keys      = { "amount", "percent" },
            labels    = { amount = "Amount", percent = "Percent" },
            autoWidth = true,
            square    = true,
            height    = 22,
            getChecked = function(key)
                local ent = CurrentBandEntry()
                local isPercent = (_bandLockPercent or (ent and ent.bandMode == "percent")) or false
                if key == "percent" then return isPercent else return not isPercent end
            end,
            isDisabled = function() return _bandLockPercent and true or false end,
            onToggle = function(key)
                if _bandLockPercent then return end
                local ent = CurrentBandEntry(); if not ent then return end
                ent.bandMode = (key == "percent") and "percent" or "value"
                if _bandRefreshFn then _bandRefreshFn() end
                RefreshBandEditor()
            end,
        })
        _bandModeSeg:SetPoint("RIGHT", _bandModeRow, "RIGHT", 0, 0)
        -- Disabled-state tooltip (Brewmaster stagger: percent-only).
        local _bandModeDis = CreateFrame("Frame", nil, _bandModeRow)
        _bandModeDis:SetAllPoints(_bandModeSeg)
        _bandModeDis:SetFrameLevel(_bandModeSeg:GetFrameLevel() + 5)
        _bandModeDis:EnableMouse(true)
        _bandModeDis:SetScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L(STAGGER_PCT_TIP)) end)
        _bandModeDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        _bandModeDis:Hide()
        _bandModeRow._staggerDis = _bandModeDis
        _bandModeHint = EllesmereUI.MakeFont(bandPopup, 10, nil, 1, 1, 1)
        _bandModeHint:SetAlpha(0.4)

        -- Row: direction -- a segmented switch (always one of two values)
        _bandReverseRow = HeaderRow("Direction")
        _bandReverseSeg, _, _bandReverseSegRefresh = EllesmereUI.BuildSegmentedControl({
            parent    = _bandReverseRow,
            keys      = { "upto", "from" },
            labels    = { upto = "Up to", from = "From" },
            autoWidth = true,
            square    = true,
            height    = 22,
            getChecked = function(key)
                local ent = CurrentBandEntry()
                local reverse = ent and ent.bandReverse and true or false
                if key == "from" then return reverse else return not reverse end
            end,
            onToggle = function(key)
                local ent = CurrentBandEntry(); if not ent then return end
                ent.bandReverse = (key == "from")
                if _bandRefreshFn then _bandRefreshFn() end
                RefreshBandEditor()
            end,
        })
        _bandReverseSeg:SetPoint("RIGHT", _bandReverseRow, "RIGHT", 0, 0)

        -- Add Band button
        _bandAddBtn = CreateFrame("Button", nil, bandPopup)
        PP.Size(_bandAddBtn, BAND_POPUP_W - BAND_PAD * 2, 26)
        _bandAddBtn:SetFrameLevel(bandPopup:GetFrameLevel() + 3)
        local abg = EllesmereUI.SolidTex(_bandAddBtn, "BACKGROUND", 0.05, 0.07, 0.09, 0.92)
        abg:SetAllPoints()
        _bandAddBtn._border = EllesmereUI.MakeBorder(_bandAddBtn, 1, 1, 1, 0.4, PP)
        local albl = EllesmereUI.MakeFont(_bandAddBtn, 12, nil, 1, 1, 1)
        albl:SetAlpha(0.5)
        albl:SetPoint("CENTER")
        albl:SetText(EllesmereUI.L("+ Add Band"))
        _bandAddBtn:SetScript("OnEnter", function()
            albl:SetAlpha(0.7)
            if _bandAddBtn._border and _bandAddBtn._border.SetColor then _bandAddBtn._border:SetColor(1, 1, 1, 0.6) end
        end)
        _bandAddBtn:SetScript("OnLeave", function()
            albl:SetAlpha(0.5)
            if _bandAddBtn._border and _bandAddBtn._border.SetColor then _bandAddBtn._border:SetColor(1, 1, 1, 0.4) end
        end)
        _bandAddBtn:SetScript("OnClick", function()
            local ent = CurrentBandEntry(); if not ent then return end
            if not ent.bands then ent.bands = {} end
            local last = ent.bands[#ent.bands]
            local nextTo = last and ((last.to or 0) + 1) or 1
            ent.bands[#ent.bands + 1] = { to = nextTo, r = _bandDefR, g = _bandDefG, b = _bandDefB, a = _bandDefA }
            SortBands(ent.bands)
            if _bandRefreshFn then _bandRefreshFn() end
            RefreshBandEditor()
        end)
    end

    -- Lazily create the widgets for band row k; returns the row table.
    local function EnsureBandRow(k)
        local row = _bandRows[k]
        if row then return row end
        row = {}
        local rf = CreateFrame("Frame", nil, bandPopup)
        rf:SetSize(BAND_POPUP_W - BAND_PAD * 2, BAND_ROW_H)
        rf:SetFrameLevel(bandPopup:GetFrameLevel() + 2)
        row.frame = rf

        local lbl = EllesmereUI.MakeFont(rf, 12, nil, 1, 1, 1)
        lbl:SetAlpha(0.6)
        lbl:SetPoint("LEFT", rf, "LEFT", 2, 0)
        lbl:SetText(EllesmereUI.L("Up to"))  -- band colors values up to `to`
        row.lbl = lbl

        local input = CreateFrame("EditBox", nil, rf)
        input:SetSize(54, 22)
        input:SetPoint("LEFT", lbl, "RIGHT", 6, 0)
        input:SetFrameLevel(rf:GetFrameLevel() + 2)
        input:SetAutoFocus(false)
        input:SetFontObject(GameFontHighlightSmall)
        local inFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"
        input:SetFont(inFont, 12, "")
        input:SetTextColor(1, 1, 1, 0.75)
        input:SetJustifyH("CENTER")
        input:SetNumeric(true)
        local inBg = input:CreateTexture(nil, "BACKGROUND")
        inBg:SetAllPoints()
        inBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
        EllesmereUI.MakeBorder(input, 1, 1, 1, 0.08, PP)
        row.input = input

        -- Commit on focus loss (Enter clears focus -> triggers this; Escape sets
        -- _cancelCommit so leaving the field discards the typed text).
        local function CommitInput(self)
            if self._cancelCommit then self._cancelCommit = nil; return end
            local ent = CurrentBandEntry()
            local band = ent and ent.bands and ent.bands[row._idx]
            if not band then return end
            local val = tonumber(self:GetText())
            if val then
                local pctMax = _bandPercentMax or 100
                local hi = _bandCountBased and 100 or ((not _bandLockPercent and ent.bandMode == "value") and 1000000 or pctMax)
                val = math.max(1, math.min(hi, math.floor(val + 0.5)))
                band.to = val
                SortBands(ent.bands)
                if _bandRefreshFn then _bandRefreshFn() end
            end
            RefreshBandEditor()
        end
        input:SetScript("OnEditFocusLost", CommitInput)
        input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(self) self._cancelCommit = true; self:ClearFocus(); RefreshBandEditor() end)

        local swatch, swatchSnap = EllesmereUI.BuildColorSwatch(rf, rf:GetFrameLevel() + 3,
            function()
                local ent = CurrentBandEntry()
                local band = ent and ent.bands and ent.bands[row._idx]
                if not band then return _bandDefR, _bandDefG, _bandDefB, _bandDefA end
                return band.r or _bandDefR, band.g or _bandDefG, band.b or _bandDefB, band.a or _bandDefA
            end,
            function(r, g, b, a)
                local ent = CurrentBandEntry()
                local band = ent and ent.bands and ent.bands[row._idx]
                if band then
                    band.r, band.g, band.b, band.a = r, g, b, a
                    if _bandRefreshFn then _bandRefreshFn() end
                end
            end, true, 19)
        swatch:SetPoint("LEFT", input, "RIGHT", 10, 0)
        row.swatch = swatch
        row.swatchSnap = swatchSnap

        local delBtn = CreateFrame("Button", nil, rf)
        delBtn:SetSize(14, 14)
        delBtn:SetPoint("RIGHT", rf, "RIGHT", -2, 0)
        delBtn:SetFrameLevel(rf:GetFrameLevel() + 3)
        local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
        delIcon:SetAllPoints()
        delIcon:SetTexture(_bandCloseIcon)
        delIcon:SetAlpha(0.4)
        delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
        delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
        delBtn:SetScript("OnClick", function()
            local ent = CurrentBandEntry()
            if ent and ent.bands and ent.bands[row._idx] then
                table.remove(ent.bands, row._idx)
                if _bandRefreshFn then _bandRefreshFn() end
                RefreshBandEditor()
            end
        end)
        row.delBtn = delBtn

        _bandRows[k] = row
        return row
    end

    RefreshBandEditor = function()
        if not bandPopup then return end
        local ent = CurrentBandEntry()
        if not ent then bandPopup:Hide(); return end
        if not ent.bands then ent.bands = {} end

        local curY = -(BAND_PAD + 24)  -- below the title

        local function placeRow(rf)
            rf:ClearAllPoints()
            PP.Point(rf, "TOPLEFT", bandPopup, "TOPLEFT", BAND_PAD, curY)
            PP.Point(rf, "TOPRIGHT", bandPopup, "TOPRIGHT", -BAND_PAD, curY)
            rf:Show()
            curY = curY - BAND_ROW_H - BAND_GAP
        end

        -- Mode row (bar-type) or a hint (count-based, boundaries are counts)
        if _bandCountBased then
            _bandModeRow:Hide()
            _bandModeHint:ClearAllPoints()
            _bandModeHint:SetPoint("TOPLEFT", bandPopup, "TOPLEFT", BAND_PAD, curY - 4)
            _bandModeHint:SetText(EllesmereUI.L("Boundaries are resource counts"))
            _bandModeHint:Show()
            curY = curY - 18 - BAND_GAP
        else
            _bandModeHint:Hide()
            -- Static descriptor; the segmented pill shows Amount vs Percent.
            if _bandModeSegRefresh then _bandModeSegRefresh() end
            -- Brewmaster stagger: percent locked, grey the control + tooltip.
            if _bandModeRow._staggerDis then _bandModeRow._staggerDis:SetShown(_bandLockPercent and true or false) end
            if _bandModeRow._lbl then _bandModeRow._lbl:SetAlpha(_bandLockPercent and 0.3 or 0.6) end
            placeRow(_bandModeRow)
        end

        -- Band rows. Header reflects direction: "From" (>=) when reverse, else "Up to".
        local reverse = ent.bandReverse and true or false

        -- Direction row
        if _bandReverseSegRefresh then _bandReverseSegRefresh() end
        placeRow(_bandReverseRow)
        local rowLabel = reverse and EllesmereUI.L("From") or EllesmereUI.L("Up to")
        local n = #ent.bands
        for k = 1, n do
            local row = EnsureBandRow(k)
            row._idx = k
            row.lbl:SetText(rowLabel)
            row.frame:ClearAllPoints()
            PP.Point(row.frame, "TOPLEFT", bandPopup, "TOPLEFT", BAND_PAD, curY)
            row.input:SetText(tostring(ent.bands[k].to or 1))
            if row.swatchSnap then row.swatchSnap() end
            row.frame:Show()
            curY = curY - BAND_ROW_H - 4
        end
        for k = n + 1, #_bandRows do
            if _bandRows[k] then _bandRows[k].frame:Hide() end
        end

        curY = curY - 4
        _bandAddBtn:ClearAllPoints()
        PP.Point(_bandAddBtn, "TOPLEFT", bandPopup, "TOPLEFT", BAND_PAD, curY)
        curY = curY - 26

        local totalH = math.abs(curY) + BAND_PAD
        PP.Size(bandPopup, BAND_POPUP_W, totalH)
    end

    -- params = { getBarData, refreshFn, entryIdx, anchor, countBased, defR/G/B/A }
    local function ShowBandEditor(params)
        if not bandPopup then BuildBandPopup() end
        _bandGetBarData = params.getBarData
        _bandRefreshFn  = params.refreshFn
        _bandEntryIdx   = params.entryIdx
        _bandCountBased = params.countBased and true or false
        _bandLockPercent = params.lockPercent and true or false
        _bandPercentMax = params.percentMax
        _bandDefR = params.defR or 1
        _bandDefG = params.defG or 0.2
        _bandDefB = params.defB or 0.2
        _bandDefA = params.defA or 1
        local ent = CurrentBandEntry()
        if ent then
            if _bandLockPercent then ent.bandMode = "percent" end  -- stagger: percent-only
            if not ent.bands then ent.bands = {} end
            -- Seed a starter band from the single threshold the first time.
            if #ent.bands == 0 then
                local seedTo = _bandCountBased and (ent.thresholdCount or 3) or (ent.thresholdPct or 30)
                ent.bands[1] = {
                    to = seedTo,
                    r = ent.thresholdR or _bandDefR, g = ent.thresholdG or _bandDefG,
                    b = ent.thresholdB or _bandDefB, a = ent.thresholdA or _bandDefA,
                }
            end
        end
        RefreshBandEditor()
        bandPopup:ClearAllPoints()
        bandPopup:SetPoint("TOP", params.anchor, "BOTTOM", 0, -4)
        bandPopup:Show()
    end

    ---------------------------------------------------------------------------
    --  Buff colors editor. A per-threshold-entry list of { spellID, r,g,b,a }.
    --  The bar takes a buff's color while that buff is active; the FIRST active
    --  buff (list order = priority) wins and overrides threshold coloring. Stored
    --  on the entry, so it's per-spec via the entry's specIDs. Mirrors the band
    --  editor. Edits CurrentBuffEntry().buffColors.
    ---------------------------------------------------------------------------
    local buffPopup
    local _buffRows = {}
    local _buffEntryIdx
    local _buffGetBarData, _buffRefreshFn
    local _buffTitleFS, _buffAddBtn
    local BUFF_POPUP_W = 320
    local BUFF_ROW_H = 26
    local RefreshBuffEditor  -- forward decl
    -- Drag-to-reorder (list order = buff priority). Machinery mirrors the
    -- BuildCogPopup 'reorder' row type.
    local _BuffDragTick      -- forward decl (called each frame from the popup OnUpdate)
    local _buffInsLine       -- insertion-line texture (created in BuildBuffPopup)
    local _buffDrag = { row = nil, startY = nil, active = false }
    local BUFF_STEP = BUFF_ROW_H + 4
    local BUFF_HELP_TIP =
        "Recolor the bar while you have a buff. The first active buff in the list wins, so order = priority. Overrides threshold coloring while active.\n"
        .. "You must be tracking the buff in Blizzard CDM, added to EUI CDM, and this only works with CDM trackable buffs."

    local function CurrentBuffEntry()
        if not _buffEntryIdx or not _buffGetBarData then return nil end
        local bd = _buffGetBarData(); if not bd or not bd.thresholdSpecs then return nil end
        return bd.thresholdSpecs[_buffEntryIdx]
    end

    local function BuildBuffPopup()
        buffPopup = CreateFrame("Frame", nil, UIParent)
        buffPopup:SetFrameStrata("FULLSCREEN_DIALOG")
        buffPopup:SetFrameLevel(260)
        buffPopup:SetClampedToScreen(true)
        buffPopup:EnableMouse(true)
        buffPopup:SetScale(0.9)
        buffPopup:Hide()
        PP.Size(buffPopup, BUFF_POPUP_W, 200)
        local bg = buffPopup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.08, 0.10, 0.97)
        PP.CreateBorder(buffPopup, 1, 1, 1, 0.18, 1, "BORDER", 7)

        -- Insertion line shown while dragging a row to reorder.
        _buffInsLine = buffPopup:CreateTexture(nil, "OVERLAY", nil, 7)
        _buffInsLine:SetHeight(2)
        -- ELLESMERE_GREEN is the resolved THEME accent (ACCENT_COLOR is never set);
        -- matches the raid "Sort By" reorder line rather than falling back to green.
        local _bilEG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
        _buffInsLine:SetColorTexture(_bilEG.r, _bilEG.g, _bilEG.b, 0.9)
        _buffInsLine:Hide()

        local clickCatcher = CreateFrame("Button", nil, buffPopup)
        clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        clickCatcher:SetFrameLevel(buffPopup:GetFrameLevel() - 1)
        clickCatcher:SetAllPoints((EllesmereUI.GetMainFrame and EllesmereUI:GetMainFrame()) or UIParent)
        clickCatcher:SetScript("OnClick", function() if _buffDrag.active then return end buffPopup:Hide() end)
        clickCatcher:Hide()
        buffPopup:SetScript("OnShow", function(self)
            clickCatcher:Show()
            self:SetScript("OnUpdate", function(pp)
                if _buffDrag.row then _BuffDragTick(); return end  -- dragging: move/reorder, never dismiss
                if IsMouseButtonDown("LeftButton") then
                    local mf = EllesmereUI._mainFrame
                    if not pp:IsMouseOver() and not (mf and mf:IsMouseOver()) then pp:Hide() end
                end
            end)
        end)
        buffPopup:SetScript("OnHide", function(self) clickCatcher:Hide(); self:SetScript("OnUpdate", nil) end)

        _buffTitleFS = EllesmereUI.MakeFont(buffPopup, 13, nil, 1, 1, 1)
        _buffTitleFS:SetAlpha(0.7)
        _buffTitleFS:SetPoint("TOP", buffPopup, "TOP", 0, -BAND_PAD)
        _buffTitleFS:SetText(EllesmereUI.L("Buff Colors"))
		local ht = buffPopup:CreateFontString(nil, "OVERLAY")
		local FONT = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
		ht:SetFont(FONT, 10, "")
		ht:SetPoint("TOPLEFT", buffPopup, "TOPLEFT", 16, -BAND_PAD - 4)
		ht:SetTextColor(1, 1, 1, 0.25)
		ht:SetText(EllesmereUI.L("Drag to Reorder"))

        _buffAddBtn = CreateFrame("Button", nil, buffPopup)
        PP.Size(_buffAddBtn, BUFF_POPUP_W - BAND_PAD * 2, 26)
        _buffAddBtn:SetFrameLevel(buffPopup:GetFrameLevel() + 3)
        local abg = EllesmereUI.SolidTex(_buffAddBtn, "BACKGROUND", 0.05, 0.07, 0.09, 0.92)
        abg:SetAllPoints()
        _buffAddBtn._border = EllesmereUI.MakeBorder(_buffAddBtn, 1, 1, 1, 0.4, PP)
        local albl = EllesmereUI.MakeFont(_buffAddBtn, 12, nil, 1, 1, 1)
        albl:SetAlpha(0.5); albl:SetPoint("CENTER"); albl:SetText(EllesmereUI.L("+ Add Buff"))
        _buffAddBtn:SetScript("OnEnter", function() albl:SetAlpha(0.7); if _buffAddBtn._border and _buffAddBtn._border.SetColor then _buffAddBtn._border:SetColor(1, 1, 1, 0.6) end end)
        _buffAddBtn:SetScript("OnLeave", function() albl:SetAlpha(0.5); if _buffAddBtn._border and _buffAddBtn._border.SetColor then _buffAddBtn._border:SetColor(1, 1, 1, 0.4) end end)
        _buffAddBtn:SetScript("OnClick", function()
            local ent = CurrentBuffEntry(); if not ent then return end
            if not ent.buffColors then ent.buffColors = {} end
            ent.buffColors[#ent.buffColors + 1] = { spellID = nil, r = 0.2, g = 0.6, b = 1.0, a = 1 }
            if _buffRefreshFn then _buffRefreshFn() end
            RefreshBuffEditor()
        end)
    end

    local function EnsureBuffRow(k)
        local row = _buffRows[k]
        if row then return row end
        row = {}
        local rf = CreateFrame("Frame", nil, buffPopup)
        rf:SetSize(BUFF_POPUP_W - BAND_PAD * 2, BUFF_ROW_H)
        rf:SetFrameLevel(buffPopup:GetFrameLevel() + 2)
        row.frame = rf

        local input = CreateFrame("EditBox", nil, rf)
        input:SetSize(58, 22)
        input:SetPoint("LEFT", rf, "LEFT", 16, 0)
        input:SetFrameLevel(rf:GetFrameLevel() + 2)
        input:SetAutoFocus(false)
        local inFont = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"
        input:SetFont(inFont, 12, "")
        input:SetTextColor(1, 1, 1, 0.75)
        input:SetJustifyH("CENTER")
        input:SetNumeric(true)
        input:SetMaxLetters(7)
        local inBg = input:CreateTexture(nil, "BACKGROUND"); inBg:SetAllPoints()
        inBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
        EllesmereUI.MakeBorder(input, 1, 1, 1, 0.08, PP)
        row.input = input

        -- Drag grip (reorder). List order = buff priority, so let users drag rows.
        local grip = CreateFrame("Button", nil, rf)
        grip:SetSize(14, BUFF_ROW_H)
        grip:SetPoint("LEFT", rf, "LEFT", 0, 0)
        grip:SetFrameLevel(rf:GetFrameLevel() + 4)
        local gripFS = grip:CreateFontString(nil, "OVERLAY")
        gripFS:SetFont(inFont, 13, "")
        gripFS:SetPoint("CENTER")
        gripFS:SetText("=")
        gripFS:SetTextColor(1, 1, 1, 0.25)
        grip:SetScript("OnEnter", function() gripFS:SetTextColor(1, 1, 1, 0.6) end)
        grip:SetScript("OnLeave", function() gripFS:SetTextColor(1, 1, 1, 0.25) end)
        grip:SetScript("OnMouseDown", function(self, b)
            if b ~= "LeftButton" then return end
            local _, cy = GetCursorPosition()
            _buffDrag.row = row; _buffDrag.startY = cy; _buffDrag.active = false
        end)
        row.grip = grip

        local nameFS = EllesmereUI.MakeFont(rf, 11, nil, 1, 1, 1)
        nameFS:SetAlpha(0.6)
        nameFS:SetPoint("LEFT", input, "RIGHT", 8, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWidth(150)
        nameFS:SetWordWrap(false)
        row.nameFS = nameFS

        local function RefreshName()
            local ent = CurrentBuffEntry()
            local e = ent and ent.buffColors and ent.buffColors[row._idx]
            local id = e and e.spellID
            if id and C_Spell and C_Spell.GetSpellName then
                nameFS:SetText(C_Spell.GetSpellName(id) or "|cffcc5555Unknown ID|r")
            else
                nameFS:SetText("|cff888888(enter Spell ID)|r")
            end
        end
        row.RefreshName = RefreshName

        local function CommitInput(self)
            if self._cancelCommit then self._cancelCommit = nil; return end
            local ent = CurrentBuffEntry()
            local e = ent and ent.buffColors and ent.buffColors[row._idx]
            if not e then return end
            local val = tonumber(self:GetText())
            e.spellID = (val and val > 0) and val or nil
            RefreshName()
            if _buffRefreshFn then _buffRefreshFn() end
        end
        input:SetScript("OnEditFocusLost", CommitInput)
        input:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        input:SetScript("OnEscapePressed", function(self) self._cancelCommit = true; self:ClearFocus(); RefreshBuffEditor() end)

        local swatch, swatchSnap = EllesmereUI.BuildColorSwatch(rf, rf:GetFrameLevel() + 3,
            function()
                local ent = CurrentBuffEntry()
                local e = ent and ent.buffColors and ent.buffColors[row._idx]
                if not e then return 0.2, 0.6, 1.0, 1 end
                return e.r or 0.2, e.g or 0.6, e.b or 1.0, e.a or 1
            end,
            function(r, g, b, a)
                local ent = CurrentBuffEntry()
                local e = ent and ent.buffColors and ent.buffColors[row._idx]
                if e then e.r, e.g, e.b, e.a = r, g, b, a; if _buffRefreshFn then _buffRefreshFn() end end
            end, true, 19)
        swatch:SetPoint("RIGHT", rf, "RIGHT", -24, 0)
        row.swatch = swatch
        row.swatchSnap = swatchSnap

        local delBtn = CreateFrame("Button", nil, rf)
        delBtn:SetSize(14, 14)
        delBtn:SetPoint("RIGHT", rf, "RIGHT", -2, 0)
        delBtn:SetFrameLevel(rf:GetFrameLevel() + 3)
        local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
        delIcon:SetAllPoints(); delIcon:SetTexture(_bandCloseIcon); delIcon:SetAlpha(0.4)
        delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
        delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
        delBtn:SetScript("OnClick", function()
            local ent = CurrentBuffEntry()
            if ent and ent.buffColors and ent.buffColors[row._idx] then
                table.remove(ent.buffColors, row._idx)
                if _buffRefreshFn then _buffRefreshFn() end
                RefreshBuffEditor()
            end
        end)
        row.delBtn = delBtn

        _buffRows[k] = row
        return row
    end

    RefreshBuffEditor = function()
        if not buffPopup then return end
        local ent = CurrentBuffEntry()
        if not ent then buffPopup:Hide(); return end
        if not ent.buffColors then ent.buffColors = {} end
        local curY = -(BAND_PAD + 24)
        local n = #ent.buffColors
        for k = 1, n do
            local row = EnsureBuffRow(k)
            row._idx = k
            row.frame:ClearAllPoints()
            PP.Point(row.frame, "TOPLEFT", buffPopup, "TOPLEFT", BAND_PAD, curY)
            row._baseY = curY  -- for the drag-reorder hit test
            row.frame:SetFrameLevel(buffPopup:GetFrameLevel() + 2)  -- reset after a drag raised it
            row.frame:SetAlpha(1)
            row.input:SetText(ent.buffColors[k].spellID and tostring(ent.buffColors[k].spellID) or "")
            if row.RefreshName then row.RefreshName() end
            if row.swatchSnap then row.swatchSnap() end
            row.frame:Show()
            curY = curY - BUFF_ROW_H - 4
        end
        for k = n + 1, #_buffRows do if _buffRows[k] then _buffRows[k].frame:Hide() end end
        curY = curY - 4
        _buffAddBtn:ClearAllPoints()
        PP.Point(_buffAddBtn, "TOPLEFT", buffPopup, "TOPLEFT", BAND_PAD, curY)
        curY = curY - 26
        PP.Size(buffPopup, BUFF_POPUP_W, math.abs(curY) + BAND_PAD)
    end

    -- Called every frame from the popup's OnUpdate while a grip is held. Tells a
    -- click from a drag, moves the dragged row to follow the cursor (with an
    -- insertion line), and on release reorders ent.buffColors (order = priority)
    -- and re-renders. Mirrors the BuildCogPopup 'reorder' row machinery.
    _BuffDragTick = function()
        local d = _buffDrag
        local row = d.row
        if not row then return end
        local down = IsMouseButtonDown("LeftButton")
        local _, cy = GetCursorPosition()
        if not d.active then
            if not down then d.row = nil; return end          -- released before threshold = a click
            if math.abs(cy - (d.startY or cy)) < 3 then return end
            d.active = true
            row.frame:SetFrameLevel(buffPopup:GetFrameLevel() + 20)
            row.frame:SetAlpha(0.85)
        end
        local ent = CurrentBuffEntry()
        local n = (ent and ent.buffColors) and #ent.buffColors or 0
        local sc = buffPopup:GetEffectiveScale()
        local cY = cy / sc
        local mT = buffPopup:GetTop() or 0
        -- Insertion index among the STATIC (non-dragged) rows.
        local iI = n
        for ri = 1, n do
            local r2 = _buffRows[ri]
            if r2 ~= row and r2._baseY then
                local rm = mT + r2._baseY - BUFF_ROW_H / 2
                if cY > rm then iI = ri; break end
                iI = ri + 1
            end
        end
        iI = math.max(1, math.min(iI, n + 1))
        if down then
            local firstY = -(BAND_PAD + 24)
            local lnY = (iI <= 1) and (firstY + 2) or (firstY - (iI - 1) * BUFF_STEP + 2)
            _buffInsLine:ClearAllPoints()
            _buffInsLine:SetPoint("TOPLEFT", buffPopup, "TOPLEFT", BAND_PAD, lnY)
            _buffInsLine:SetPoint("TOPRIGHT", buffPopup, "TOPRIGHT", -BAND_PAD, lnY)
            _buffInsLine:Show()
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", buffPopup, "TOPLEFT", BAND_PAD, cY - mT)
        else
            -- Dropped: reorder the list + re-render.
            local from = row._idx
            if from and from < iI then iI = iI - 1 end
            local to = math.max(1, math.min(iI, n))
            _buffInsLine:Hide()
            d.row = nil; d.active = false
            if ent and ent.buffColors and from and from ~= to then
                local mv = table.remove(ent.buffColors, from)
                table.insert(ent.buffColors, to, mv)
                if _buffRefreshFn then _buffRefreshFn() end
            end
            RefreshBuffEditor()
        end
    end

    local function ShowBuffEditor(params)
        if not buffPopup then BuildBuffPopup() end
        _buffGetBarData = params.getBarData
        _buffRefreshFn  = params.refreshFn
        _buffEntryIdx   = params.entryIdx
        local ent = CurrentBuffEntry()
        if ent and not ent.buffColors then ent.buffColors = {} end
        RefreshBuffEditor()
        buffPopup:ClearAllPoints()
        buffPopup:SetPoint("TOP", params.anchor, "BOTTOM", 0, -4)
        buffPopup:Show()
    end

    ---------------------------------------------------------------------------
    --  BuildThresholdSettingsButton: shared builder for threshold per-spec
    --  popup. Used by power bar and health bar sections.
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
	--    settingsPage   -- frame for settings
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

        -- Druid "form specific": Advanced mode only.
		-- Allows threshold for each resource type based on form
        local _playerClassFile = select(2, UnitClass("player"))
        local hasFormToggle = cfg.formCapable and cfg.singleSpec and _playerClassFile == "DRUID"
        local FORM_LABEL = { mana = "Caster", rage = "Bear", energy = "Cat" }
        local function DefaultFormEntries()
            return {
                { formKey = "mana",   thresholdEnabled = true, thresholdPct = 30, thresholdPartialOnly = true,
                  thresholdR = defR, thresholdG = defG, thresholdB = defB, thresholdA = defA },
                { formKey = "rage",   thresholdEnabled = true, thresholdPct = 30, thresholdPartialOnly = false,
                  thresholdR = defR, thresholdG = defG, thresholdB = defB, thresholdA = defA },
                { formKey = "energy", thresholdEnabled = true, thresholdPct = 30, thresholdPartialOnly = true,
                  thresholdR = defR, thresholdG = defG, thresholdB = defB, thresholdA = defA },
            }
        end
        local function IsFormMode()
            local bd = cfg.getBarData()
            return (bd and bd.thresholdFormMode) and true or false
        end

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
        btnLbl:SetText(EllesmereUI.L("Settings"))
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
            EllesmereUI.ShowWidgetTooltip(settingsBtn, EllesmereUI.DisabledTooltip(cfg.disabledTip or "this bar"))
        end)
        btnDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateBtnDis()
            local off = cfg.disabledFn and cfg.disabledFn()
            if off then
                btnDis:Show()
                settingsBtn:SetAlpha(0.3)
                if parentRgn._label then parentRgn._label:SetAlpha(0.3) end
            else
                btnDis:Hide()
                settingsBtn:SetAlpha(1)
                if parentRgn._label then parentRgn._label:SetAlpha(1) end
            end
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
        local SetFormMode, LayoutHeaderForMode

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
            clickCatcher:SetAllPoints((EllesmereUI.GetMainFrame and EllesmereUI:GetMainFrame()) or UIParent)
            clickCatcher:SetScript("OnClick", function() popup:Hide() end)
            clickCatcher:Hide()
            popup:SetScript("OnShow", function(self)
                clickCatcher:Show()
                self:SetScript("OnUpdate", function(p)
                    if IsMouseButtonDown("LeftButton") then
                        local mf = EllesmereUI._mainFrame
                        local dm = EllesmereUI._openDropdownMenu
                        if not p:IsMouseOver() and not (mf and mf:IsMouseOver()) and not (dm and dm:IsShown() and dm:IsMouseOver()) then p:Hide() end
                    end
                end)
            end)
            popup:SetScript("OnHide", function(self)
                clickCatcher:Hide()
                self:SetScript("OnUpdate", nil)
            end)

            if EllesmereUI._popupFrames then
                EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = popup }
            end

            local curY = -POPUP_PAD

            local titleFS = EllesmereUI.MakeFont(popup, 13, nil, 1, 1, 1)
            titleFS:SetAlpha(0.55)
            titleFS:SetPoint("TOP", popup, "TOP", 0, curY)
            titleFS:SetText(cfg.popupTitle or EllesmereUI.L("Threshold Settings"))
            curY = curY - 25

            -- Mode switch (druid power bar): Single per-spec vs three per-form
            -- entries. Sits between the title and the spec chrome.
            if hasFormToggle then
                local pillRow = CreateFrame("Frame", nil, popup)
                pillRow:SetSize(POPUP_W, 26)
                pillRow:SetPoint("TOP", popup, "TOP", 0, curY)
                pillRow:SetFrameLevel(popup:GetFrameLevel() + 6)
                local modeSeg, _, modeSegRefresh = EllesmereUI.BuildSegmentedControl({
                    parent    = pillRow,
                    keys      = { "single", "form" },
                    labels    = { single = "Single", form = "Form specific" },
                    autoWidth = true,
                    square    = true,
                    height    = 22,
                    getChecked = function(key)
                        if key == "form" then return IsFormMode() else return not IsFormMode() end
                    end,
                    onToggle = function(key)
                        if SetFormMode then SetFormMode(key == "form") end
                    end,
                })
                modeSeg:SetPoint("CENTER", pillRow, "CENTER", 0, 0)
                popup._modeSeg = modeSeg
                popup._modeSegRefresh = modeSegRefresh
                curY = curY - 30
            end
            -- Header bottom when the spec chrome is hidden (form mode).
            popup._afterPillY = curY

            -- Spec dropdown + Add button -- skipped in singleSpec mode (Advanced
            -- per-spec: the spec is implied, one config only).
            if not cfg.singleSpec then
            -- Centered dropdown + Add button
            local DD_W, ADD_W, GAP_L = 220, 90, 10
            local rowW = DD_W + GAP_L + ADD_W
            local ddRow = CreateFrame("Frame", nil, popup)
            ddRow:SetSize(rowW, 30)
            ddRow:SetPoint("TOP", popup, "TOP", 0, curY)
            ddRow:SetFrameLevel(popup:GetFrameLevel() + 5)
            popup._ddRow = ddRow

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
                    if rgn2.GetText and EllesmereUI.EnKey(rgn2:GetText()) == "None" then
                        rgn2:SetText(EllesmereUI.L("Select a Spec...")); break
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
            addLbl:SetText(EllesmereUI.L("Add Specs"))
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
                -- Smart default for the power bar's "Threshold color below value":
                -- spender resources (mana/energy/focus) start ON (warn when low),
                -- builders (rage/runic/fury) start OFF (warn when high). Only when the
                -- entry covers the current spec -- the one whose power type we can read.
                if cfg.showPartialCog then
                    local curIdx = GetSpecialization()
                    local curSpecID = curIdx and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(curIdx)
                    if curSpecID then
                        for _, sid in ipairs(ids) do
                            if sid == curSpecID then
                                local _, token = UnitPowerType("player")
                                if token == "MANA" or token == "FOCUS" or token == "ENERGY" then
                                    newEntry.thresholdPartialOnly = true
                                end
                                break
                            end
                        end
                    end
                end
                bd.thresholdSpecs[#bd.thresholdSpecs + 1] = newEntry
                wipe(_tempSpecSel)
                WrappedRefresh()
                RefreshPopupEntries_L()
                cfg.refreshFn()
            end)

            curY = curY - 36
            end -- not singleSpec
            popup._afterDDY = curY

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
            popup._scrollBar = scrollBar
            popup._headerH = headerH
            popup._maxH = POPUP_MAX_H

            -- Re-anchor the scroll region for the current mode. In form mode the
            -- spec chrome is hidden, so the list starts higher (right below the
            -- mode pill). Data swap is handled separately by SetFormMode.
            LayoutHeaderForMode = function(on)
                if not hasFormToggle then return end
                local topY = on and popup._afterPillY or popup._afterDDY
                if popup._ddRow then popup._ddRow:SetShown(not on) end
                scrollFrame:ClearAllPoints()
                scrollFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", 0, topY)
                scrollFrame:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, topY)
                scrollBar:ClearAllPoints()
                scrollBar:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -3, topY)
                scrollBar:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -3, 4)
                popup._headerH = math.abs(topY)
            end

            -- Swap the live thresholdSpecs between the single per-spec list and the
            -- three per-form entries, stashing the inactive set so switching back
            -- restores the user's config.
            SetFormMode = function(on)
                local bd = cfg.getBarData(); if not bd then return end
                on = on and true or false
                if (bd.thresholdFormMode and true or false) ~= on then
                    if on then
                        bd._singleSpecsBackup = bd.thresholdSpecs
                        bd.thresholdSpecs = bd._formSpecsBackup or DefaultFormEntries()
                        bd._formSpecsBackup = nil
                        bd.thresholdFormMode = true
                    else
                        bd._formSpecsBackup = bd.thresholdSpecs
                        bd.thresholdSpecs = bd._singleSpecsBackup or {}
                        bd._singleSpecsBackup = nil
                        bd.thresholdFormMode = nil
                    end
                end
                LayoutHeaderForMode(on)
                if popup._modeSegRefresh then popup._modeSegRefresh() end
                RefreshPopupEntries_L()
                if popup._scrollFrame then popup._scrollFrame:SetVerticalScroll(0) end
                cfg.refreshFn()
                if cfg.rebuildFn then cfg.rebuildFn() end
            end

            -- Apply the initial layout for whatever mode was persisted.
            if hasFormToggle then LayoutHeaderForMode(IsFormMode()) end
        end -- BuildPopup_L

        RefreshPopupEntries_L = function()
            if not popup then return end
            local bd = cfg.getBarData(); if not bd then return end
            local formMode = (bd.thresholdFormMode and hasFormToggle) and true or false
            -- Form mode: guarantee the three per-form entries exist.
            if formMode and (not bd.thresholdSpecs or #bd.thresholdSpecs == 0) then
                bd.thresholdSpecs = DefaultFormEntries()
            end
            if not bd.thresholdSpecs then bd.thresholdSpecs = {} end
            local entries = bd.thresholdSpecs

            -- singleSpec (Advanced): exactly one config, no spec chrome.
            if cfg.singleSpec and #entries == 0 then
                entries[1] = { specIDs = { 0 }, thresholdEnabled = false,
                    thresholdPct = 30, thresholdR = defR, thresholdG = defG, thresholdB = defB, thresholdA = defA }
            end

            local scrollChild = popup._scrollChild
            local curY = 0
            local ENTRY_W = POPUP_W - POPUP_PAD * 2
            local ENTRY_H = (cfg.singleSpec and not formMode) and 40 or (cfg.showHash and 89 or 60)
            local effThreshY = (cfg.singleSpec and not formMode) and -8 or (cfg.showHash and -61 or -33)

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

                    -- Threshold row Y offset depends on whether hash row exists.
                    -- singleSpec has no spec-label row, so the threshold row sits
                    -- at the top.
                    local threshY = cfg.singleSpec and -8 or (cfg.showHash and -61 or -33)

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
                    threshLbl2:SetPoint("LEFT", ef, "TOPLEFT", 8, threshY - 11)
                    threshLbl2:SetText(cfg.thresholdLabel or EllesmereUI.L("Threshold"))
                    ef._threshLbl = threshLbl2

                    local threshInput = CreateFrame("EditBox", nil, ef)
                    threshInput:SetSize(40, 22)
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
                    do
                        local cogRows = {}
                        if cfg.showPartialCog then
                            cogRows[#cogRows + 1] = { type = "toggle", label = "Threshold color below value",
                                rawTooltip = true,
                                disabled = function()
                                    if not ef._entryIdx then return false end
                                    local bd2 = cfg.getBarData(); if not bd2 then return false end
                                    local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                    return (ent and ent.multiBandEnabled) and true or false
                                end,
                                disabledTooltip = "Single-threshold options don't apply while Multi-band coloring is on.",
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
                                end }
                        end
                        cogRows[#cogRows + 1] = { type = "toggle", label = "Recolor Text Instead Of Bar",
                            get = function()
                                if not ef._entryIdx then return false end
                                local bd2 = cfg.getBarData(); if not bd2 then return false end
                                local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                return ent and ent.thresholdTextInstead
                            end,
                            set = function(v)
                                if not ef._entryIdx then return end
                                local bd2 = cfg.getBarData(); if not bd2 then return end
                                local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                                if ent then ent.thresholdTextInstead = v; cfg.refreshFn() end
                            end }
                        local _, entryCogShow = EllesmereUI.BuildCogPopup({
                            title = "Threshold Coloring", bgAlpha = 1, minWidth = 280,
                            frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
                            rows = cogRows,
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

                    -- Multi-band: per-entry toggle + "Bands" editor button (right side)
                    local bandsBtn = CreateFrame("Button", nil, ef)
                    bandsBtn:SetSize(58, 22)
                    bandsBtn:SetPoint("RIGHT", ef, "TOPRIGHT", -8, threshY - 11)
                    bandsBtn:SetFrameLevel(ef:GetFrameLevel() + 4)
                    local bbBg = bandsBtn:CreateTexture(nil, "BACKGROUND")
                    bbBg:SetAllPoints()
                    bbBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                    bandsBtn._border = EllesmereUI.MakeBorder(bandsBtn, 1, 1, 1, 0.08, PP)
                    local bbLbl = EllesmereUI.MakeFont(bandsBtn, 12, nil, 1, 1, 1)
                    bbLbl:SetAlpha(0.8)
                    bbLbl:SetPoint("CENTER")
                    bbLbl:SetText(EllesmereUI.L("Bands"))
                    bandsBtn:SetScript("OnEnter", function(self)
                        bbBg:SetColorTexture(0.16, 0.16, 0.16, 0.9)
                        EllesmereUI.ShowWidgetTooltip(self, BAND_HELP_TIP)
                    end)
                    bandsBtn:SetScript("OnLeave", function(self)
                        bbBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                        EllesmereUI.HideWidgetTooltip()
                    end)
                    bandsBtn:SetScript("OnClick", function(self)
                        if not ef._entryIdx then return end
                        ShowBandEditor({
                            getBarData = cfg.getBarData, refreshFn = cfg.refreshFn,
                            entryIdx = ef._entryIdx, anchor = self, countBased = false,
                            defR = defR, defG = defG, defB = defB, defA = defA,
                        })
                    end)
                    ef._bandsBtn = bandsBtn

                    local multiToggle, _, multiSnap = EllesmereUI.BuildToggleControl(
                        ef, ef:GetFrameLevel() + 4,
                        function()
                            if not ef._entryIdx then return false end
                            local bd2 = cfg.getBarData(); if not bd2 then return false end
                            local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                            return ent and ent.multiBandEnabled or false
                        end,
                        function(v)
                            if not ef._entryIdx then return end
                            local bd2 = cfg.getBarData(); if not bd2 then return end
                            local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[ef._entryIdx]
                            if ent then ent.multiBandEnabled = v; cfg.refreshFn() end
                            if RefreshPopupEntries_L then RefreshPopupEntries_L() end
                        end,
                        { sizeRatio = 0.95 }
                    )
                    multiToggle:SetPoint("RIGHT", bandsBtn, "LEFT", -8, 0)
                    ef._multiToggle = multiToggle
                    ef._multiSnap = multiSnap
                    multiToggle:HookScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, BAND_HELP_TIP) end)
                    multiToggle:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                    local multiLbl = EllesmereUI.MakeFont(ef, 11, nil, 1, 1, 1)
                    multiLbl:SetAlpha(0.55)
                    multiLbl:SetText(EllesmereUI.L("Multi"))
                    multiLbl:SetPoint("RIGHT", multiToggle, "LEFT", -4, 0)
                    ef._multiLbl = multiLbl

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
                        local tip = (ef._threshDisTip == "MULTI") and BAND_REPLACES_TIP
                            or EllesmereUI.DisabledTooltip("Threshold Color")
                        EllesmereUI.ShowWidgetTooltip(threshDis, tip)
                    end)
                    threshDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    ef._threshDis = threshDis
                end -- end entry frame creation

                -- Populate entry
                ef:SetSize(ENTRY_W, ENTRY_H)
                ef:ClearAllPoints()
                ef:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", POPUP_PAD, curY)
                ef._entryIdx = idx

                if ef._threshLbl then
                    ef._threshLbl:ClearAllPoints()
                    ef._threshLbl:SetPoint("LEFT", ef, "TOPLEFT", 8, effThreshY - 11)
                end
                if ef._bandsBtn then
                    ef._bandsBtn:ClearAllPoints()
                    ef._bandsBtn:SetPoint("RIGHT", ef, "TOPRIGHT", -8, effThreshY - 11)
                end

                if formMode then
                    -- Form mode: fixed per-form entries -- form name label, no delete.
                    ef._specLbl:Show()
                    ef._delBtn:Hide()
                    ef._specLbl:SetText(EllesmereUI.L(FORM_LABEL[entry.formKey] or "Unknown"))
                    local cc = CLASS_COLORS_L["DRUID"]
                    if cc then ef._specLbl:SetTextColor(cc[1], cc[2], cc[3], 1)
                    else ef._specLbl:SetTextColor(1, 1, 1, 1) end
                elseif cfg.singleSpec then
                    -- Advanced: spec is implied -- no spec label, no delete.
                    ef._specLbl:Hide()
                    ef._delBtn:Hide()
                else
                    ef._specLbl:Show()
                    ef._delBtn:Show()
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
                end

                if cfg.showHash and ef._hashLbl then
                    local isBar = IsEntryBarType_L(entry)
                    local hashWord = isBar and "Percent" or "Stack"
                    ef._hashLbl:SetText(EllesmereUI.Lf("Hash at %1$s", hashWord))
                    ef._hashHint:SetText(isBar and EllesmereUI.L("(Ex: 25,50,75)") or EllesmereUI.L("(Ex: 2,4)"))
                    ef._hashInput:SetText(entry.hashValues or "")
                    -- Commit on focus loss (Enter clears focus; Escape discards).
                    ef._hashInput:SetScript("OnEditFocusLost", function(self)
                        if self._cancelCommit then self._cancelCommit = nil; return end
                        local bd2 = cfg.getBarData(); if not bd2 then return end
                        local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[idx]
                        if ent then ent.hashValues = self:GetText(); cfg.rebuildFn() end
                    end)
                    ef._hashInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                    ef._hashInput:SetScript("OnEscapePressed", function(self)
                        self._cancelCommit = true
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
                -- Commit on focus loss (Enter clears focus; Escape discards).
                ef._threshInput:SetScript("OnEditFocusLost", function(self)
                    if self._cancelCommit then self._cancelCommit = nil; return end
                    local val = tonumber(self:GetText())
                    if not val then self:SetText(tostring(entry[threshKey] or threshDef)); return end
                    val = math.max(cfg.threshMin or 1, math.min(threshMaxVal, math.floor(val + 0.5)))
                    self:SetText(tostring(val))
                    local bd2 = cfg.getBarData(); if not bd2 then return end
                    local ent = bd2.thresholdSpecs and bd2.thresholdSpecs[idx]
                    if ent then ent[threshKey] = val; cfg.refreshFn() end
                end)
                ef._threshInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                ef._threshInput:SetScript("OnEscapePressed", function(self)
                    self._cancelCommit = true
                    self:SetText(tostring(entry[threshKey] or threshDef)); self:ClearFocus()
                end)

                if ef._entrySnap then ef._entrySnap() end
                if ef._entrySwatchSnap then ef._entrySwatchSnap() end
                if ef._multiSnap then ef._multiSnap() end

                -- Multi-band on: the single-threshold input + swatch are replaced by
                -- bands. Enable the "Bands" button and hide the cog.
                local entEnabled = entry.thresholdEnabled
                if entEnabled == nil then entEnabled = true end
                local multiOn = entry.multiBandEnabled and true or false
                -- Single threshold + multi-band are independent: multi can be toggled
                -- even with single off (single on only => single; both on => multi
                -- wins; single off + multi on => multi; both off => none).
                if ef._multiToggle then
                    ef._multiToggle:SetAlpha(1)
                    ef._multiToggle:SetEnabled(true)
                end
                if ef._bandsBtn then
                    ef._bandsBtn:SetAlpha(multiOn and 1 or 0.35)
                    ef._bandsBtn:SetEnabled(multiOn)
                end
                if ef._cogBtn then ef._cogBtn:Show() end

                if multiOn then
                    ef._threshDisTip = "MULTI"
                    ef._threshDis:Show()
                elseif not entEnabled then
                    ef._threshDisTip = nil
                    ef._threshDis:Show()
                else
                    ef._threshDis:Hide()
                end

                -- Dim only duplicates the resolver can never reach
                -- per-spec or inactive-talent cards stay fully visible.
                -- Form entries are each unique (one per form) -- never dimmed.
                ef:SetAlpha((not formMode) and ns._ERB_IsThresholdCardShadowed(entries, idx) and 0.45 or 1)

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
            if hasFormToggle then
                if LayoutHeaderForMode then LayoutHeaderForMode(IsFormMode()) end
                if popup._modeSegRefresh then popup._modeSegRefresh() end
            end
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
    --  Shared, context-aware HEALTH section builder (grown incrementally; both
    --  the Simple page and the Advanced per-spec page render through this).
    --    ctx.cfg()    -> health config table -- DB().health on Simple; the
    --                    per-spec copy-on-unsync override on Advanced.
    --    ctx.advanced -> true on Advanced (hides controls that only make sense
    --                    globally, e.g. the per-spec enable picker, since a
    --                    synced section already falls back to the Simple config).
    --  Returns the y after the rows it rendered. Captures the module-scope apply
    --  helpers (RebuildHealth/Refresh/...); assigned to ns so the Advanced file
    --  (separate .lua, same addon ns) can call it too.
    ---------------------------------------------------------------------------

    function ns.ERB_BuildHealthSection(parent, y, ctx)
        local W = EllesmereUI.Widgets
        local _, h
        local function cfg() return ctx.cfg() end
        local function healthOff() local c = cfg(); return not (c and c.enabled) end

        local hdr
        hdr, h = W:SectionHeader(parent, "HEALTH BAR", y);  y = y - h

        -- Advanced: a Synced/Re-sync toggle in the header. Controls are ALWAYS
        -- built (so the section is the same height synced or not); when synced a
        -- near-opaque overlay (built at the end) covers them. _advTop marks the
        -- content top for that overlay.
        local _advTop = y  -- content top (also used by the Simple override overlay)
        if ctx.advanced then
            local EGc  = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
            local syncBtn = CreateFrame("Button", nil, hdr)
            syncBtn:SetSize(92, 22)
            syncBtn:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, 6)
            syncBtn:SetFrameLevel(hdr:GetFrameLevel() + 60)
            local sbg  = EllesmereUI.SolidTex(syncBtn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
            local sbrd = EllesmereUI.MakeBorder(syncBtn, 1, 1, 1, 0.22, EllesmereUI.PanelPP)
            local slbl = EllesmereUI.MakeFont(syncBtn, 11, nil, 1, 1, 1)
            slbl:SetPoint("CENTER")
            if ctx.synced then
                slbl:SetText(EllesmereUI.L("Synced")); slbl:SetTextColor(1, 1, 1, 0.5)
            else
                slbl:SetText(EllesmereUI.L("Re-sync")); slbl:SetTextColor(EGc.r, EGc.g, EGc.b, 1)
            end
            syncBtn:SetScript("OnEnter", function() if sbrd and sbrd.SetColor then sbrd:SetColor(EGc.r, EGc.g, EGc.b, 0.7) end end)
            syncBtn:SetScript("OnLeave", function() if sbrd and sbrd.SetColor then sbrd:SetColor(1, 1, 1, 0.22) end end)
            syncBtn:SetScript("OnClick", function() if ctx.onToggleSync then ctx.onToggleSync() end end)
            _advTop = y
        end

        -- Row 1: Show Health Bar | Orientation
        local healthEnableRow
        healthEnableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Health Bar",
              getValue = function() local c = cfg(); return c and c.enabled end,
              -- DependentSetValue: the rows below Row 1 are hidden while the
              -- bar is off; the flip forces the full rebuild.
              setValue = EllesmereUI.DependentSetValue(
                  function() local c = cfg(); return c and c.enabled end,
                  function(v)
                      local c = cfg(); if not c then return end
                      c.enabled = v; RebuildHealth()
                      EllesmereUI:RefreshPage()
                  end) },
            { type = "dropdown", text = "Orientation",
              disabled = healthOff,
              disabledTooltip = "Health Bar",
              values = { HORIZONTAL = "Horizontal", VERTICAL_UP = "Vertical Up", VERTICAL_DOWN = "Vertical Down" },
              order = { "HORIZONTAL", "VERTICAL_UP", "VERTICAL_DOWN" },
              getValue = function()
                  local c = cfg(); local p = DB()
                  return (c and c.orientation) or (p and p.general.orientation) or "HORIZONTAL"
              end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.orientation = v; Refresh()
              end }
        );  y = y - h
        AddFormBarBtn(healthEnableRow._leftRegion, cfg, RebuildHealth)

        -- (Per-spec enable picker removed: per-spec enables now live in Spec
        -- Overrides -- capture "Show Health Bar" while editing as a group.)

        -- Everything below Row 1 is HIDDEN entirely while the bar is off (the
        -- toggle's DependentSetValue forces the rebuild on flips).
        if not healthOff() then
        -- Row 2: Height | Width. MatchGuard (dimension matched to ANOTHER element
        -- via Unlock Mode) is a global relationship that greys the slider in BOTH
        -- modes -- you can't per-spec override a matched dimension. Only the
        -- "apply to all bars" sync icons below are Simple-only.
        local function guard(propKey)
            return EllesmereUI.MatchGuard("ERB_Health", propKey, healthOff, "Health Bar")
        end
        local hhDis, hhTip, hhRaw = guard("Height")
        local hwDis, hwTip, hwRaw = guard("Width")
        local healthSizeRow
        healthSizeRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 40, step = 1,
              disabled = hhDis, disabledTooltip = hhTip, rawTooltip = hhRaw,
              getValue = function() local c = cfg(); return c and c.height or 20 end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.height = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Width",
              min = 50, max = 800, step = 1,
              disabled = hwDis, disabledTooltip = hwTip, rawTooltip = hwRaw,
              getValue = function() local c = cfg(); return c and c.width or 220 end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.width = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        if not ctx.advanced and ctx.syncRows then
            ctx.syncRows.healthHeight = healthSizeRow._leftRegion
            ctx.syncRows.healthWidth  = healthSizeRow._rightRegion
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
                    flashTargets = function() return { ctx.syncRows.healthHeight, ctx.syncRows.classHeight, ctx.syncRows.powerHeight } end,
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
                    flashTargets = function() return { ctx.syncRows.healthWidth, ctx.syncRows.classWidth, ctx.syncRows.powerWidth } end,
                })
            end
        end

        -- Row: Health Border Style dropdown (+ inline offset cog). Style/size/
        -- colour/cog operate on cfg(); the cross-bar "apply to all" sync icons
        -- (+ _syncRows registration) are Simple-only.
        do
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local hpBsRow
            hpBsRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style",
                  disabled = healthOff,
                  disabledTooltip = "Health Bar",
                  values=texValues, order=texOrder,
                  getValue=function() local c = cfg(); return c and c.borderTexture or "solid" end,
                  setValue=function(v)
                      local c = cfg(); if not c then return end
                      c.borderTexture = v; c.borderTextureOffset = nil; c.borderTextureOffsetY = nil; c.borderTextureShiftX = nil; c.borderTextureShiftY = nil
                      local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      c.borderR = _bcol.r; c.borderG = _bcol.g; c.borderB = _bcol.b; c.borderA = 1
                      c.borderBehind = _bbehind
                      local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                      if defSz then c.borderSize = defSz end
                      RebuildHealth(); EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Border Size",
                  min = 0, max = 4, step = 1,
                  disabled = healthOff,
                  disabledTooltip = "Health Bar",
                  getValue = function() local c = cfg(); return c and c.borderSize or 1 end,
                  setValue = function(v)
                      local c = cfg(); if not c then return end
                      c.borderSize = v; RebuildHealth()
                      EllesmereUI:RefreshPage()
                  end });  y = y - h
            -- Inline color swatch on Border Size (right region)
            do
                local rgn = hpBsRow._rightRegion
                local ctrl = rgn._control
                local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, hpBsRow:GetFrameLevel() + 3,
                    function()
                        local c = cfg()
                        return (c and c.borderR or 0), (c and c.borderG or 0),
                               (c and c.borderB or 0), (c and c.borderA or 1)
                    end,
                    function(r, g, b, a)
                        local c = cfg(); if not c then return end
                        c.borderR, c.borderG, c.borderB, c.borderA = r, g, b, a
                        SmoothRefresh(); EllesmereUI:RefreshPage()
                    end,
                    true, 20)
                PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch() end)
                local swBlock = CreateFrame("Frame", nil, borderSwatch)
                swBlock:SetAllPoints()
                swBlock:SetFrameLevel(borderSwatch:GetFrameLevel() + 10)
                swBlock:EnableMouse(true)
                swBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(borderSwatch, EllesmereUI.DisabledTooltip("Health Bar")) end)
                swBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateBorderSwDis()
                    if healthOff() then borderSwatch:SetAlpha(0.3); swBlock:Show()
                    else borderSwatch:SetAlpha(1); swBlock:Hide() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateBorderSwDis)
                UpdateBorderSwDis()
            end
            do
                local rgn = hpBsRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    rows = {
                        { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                          get = function()
                              local c = cfg(); if not c then return 0 end
                              local v = c.borderTextureOffset
                              if v then return v end
                              local dox = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                              return dox
                          end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderTextureOffset = v; RebuildHealth(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                          get = function()
                              local c = cfg(); if not c then return 0 end
                              local v = c.borderTextureOffsetY
                              if v then return v end
                              local _, doy = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                              return doy
                          end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderTextureOffsetY = v; RebuildHealth(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                          get = function()
                              local c = cfg(); if not c then return 0 end
                              local v = c.borderTextureShiftX
                              if v then return v end
                              local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                              return dsx
                          end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderTextureShiftX = v == 0 and nil or v; RebuildHealth(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                          get = function()
                              local c = cfg(); if not c then return 0 end
                              local v = c.borderTextureShiftY
                              if v then return v end
                              local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                              return dsy
                          end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderTextureShiftY = v == 0 and nil or v; RebuildHealth(); EllesmereUI:RefreshPage()
                          end },
                        { type = "toggle", label = "Show Behind",
                          get = function() local c = cfg(); return c and c.borderBehind or false end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderBehind = v == false and nil or v; RebuildHealth(); EllesmereUI:RefreshPage()
                          end },
                    },
                })
                local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                local function UpdateCogVis()
                    local c = cfg()
                    local tex = c and c.borderTexture or "solid"
                    if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
            -- Cross-bar "apply to all" sync icons -- Simple only.
            if not ctx.advanced and ctx.syncRows then
                ctx.syncRows.healthBorder = hpBsRow._rightRegion
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
                            t.borderBehind = s.borderBehind
                        end
                        apply(p.secondary); apply(p.primary)
                        SmoothRefresh(); EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local p = DB(); if not p then return false end
                        local bt = p.health.borderTexture or "solid"
                        local bh = p.health.borderBehind or false
                        return (p.secondary.borderTexture or "solid") == bt and (p.primary.borderTexture or "solid") == bt
                            and (p.secondary.borderBehind or false) == bh and (p.primary.borderBehind or false) == bh
                    end,
                    flashTargets = function() return { hpBsRow._leftRegion } end,
                })
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
                    flashTargets = function() return { ctx.syncRows.healthBorder, ctx.syncRows.classBorder, ctx.syncRows.powerBorder } end,
                })
            end
        end

        -- Row 4: Opacity | Fill Color (gradient/custom/class). Opacity "apply to
        -- all" sync icon is Simple-only; the gradient swatch disables when this
        -- spec's threshold coloring is on.
        local healthBorderRow
        healthBorderRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Opacity",
              min = 0, max = 100, step = 5,
              disabled = healthOff,
              disabledTooltip = "Health Bar",
              getValue = function() local c = cfg(); return math.floor((c and c.barAlpha or 1) * 100 + 0.5) end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.barAlpha = v / 100; RefreshHealth()
                  EllesmereUI:RefreshPage()
              end },
            { type = "multiSwatch", text = "Fill Color",
              disabled = healthOff,
              disabledTooltip = "Health Bar",
              swatches = {
                { tooltip = "Gradient End Color", hasAlpha = true,
                  disabled = function()
                      local c = cfg(); if not c then return true end
                      if not c.enabled then return true end
                      local tse = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(c)
                      if tse and (tse.thresholdEnabled ~= false) then return true end
                      return not c.gradientEnabled
                  end,
                  disabledTooltip = function()
                      local c = cfg()
                      if not c or not c.enabled then return "Health Bar" end
                      local tse = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(c)
                      if tse and (tse.thresholdEnabled ~= false) then return "This option requires Threshold Settings to be disabled" end
                      return "Gradient"
                  end,
                  getValue = function()
                      local c = cfg()
                      if not c then return 0.20, 0.20, 0.80, 1 end
                      return c.gradientR, c.gradientG, c.gradientB, c.gradientA
                  end,
                  setValue = function(r, g, b, a)
                      local c = cfg(); if not c then return end
                      c.gradientR, c.gradientG, c.gradientB, c.gradientA = r, g, b, a
                      SmoothRefresh()
                  end },
                { tooltip = "Custom Colored",
                  hasAlpha = true,
                  getValue = function()
                      local c = cfg()
                      if not c then return 37/255, 193/255, 29/255, 1 end
                      return c.fillR, c.fillG, c.fillB, c.fillA
                  end,
                  setValue = function(r, g, b, a)
                      local c = cfg(); if not c then return end
                      c.fillR, c.fillG, c.fillB, c.fillA = r, g, b, a
                      if not c.customColored then c.customColored = true end
                      SmoothRefresh(); EllesmereUI:RefreshPage()
                  end,
                  onClick = function(self)
                      local c = cfg(); if not c then return end
                      if not c.customColored then
                          c.customColored = true
                          RebuildHealth(); EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local c = cfg()
                      local isClassColored = not c or not c.customColored
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
                      local c = cfg(); if not c then return end
                      c.customColored = false
                      RebuildHealth(); EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local c = cfg()
                      local isClassColored = not c or not c.customColored
                      return isClassColored and 1 or 0.3
                  end },
              } }
        );  y = y - h
        if not ctx.advanced and ctx.syncRows then
            ctx.syncRows.healthOpacity = healthBorderRow._leftRegion
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
                flashTargets = function() return { ctx.syncRows.healthOpacity, ctx.syncRows.classOpacity, ctx.syncRows.powerOpacity } end,
            })
        end
        -- Inline cog on Fill Color for gradient settings
        do
            local rgn = healthBorderRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Fill Settings",
                rows = {
                    { type = "toggle", label = "Enable Gradient",
                      get = function() local c = cfg(); return c and c.gradientEnabled end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.gradientEnabled = v; RebuildHealth()
                          EllesmereUI:RefreshPage()
                      end },
                    { type = "dropdown", label = "Gradient Direction",
                      values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                      order = { "HORIZONTAL", "VERTICAL" },
                      get = function() local c = cfg(); return c and c.gradientDir or "HORIZONTAL" end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.gradientDir = v; RebuildHealth()
                      end },
                    { type = "slider", label = "Fill Opacity", min = 0, max = 100, step = 1,
                      tooltip = "Opacity of the bar fill; below 100 the world shows through the fill instead of the background.",
                      get = function() local c = cfg(); return (c and c.fillOpacity) or 100 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.fillOpacity = v; RebuildHealth()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Health Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisGrad()
                local c = cfg()
                if c and not c.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisGrad)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisGrad)
            UpdateCogDisGrad()
        end

        -- Out of Combat Opacity: inline cog on the Opacity slider. Dims the Health
        -- bar to this alpha while out of combat (100 = no fade). Applied via
        -- ns.ResolveBarAlpha in UpdateVisibility; reacts to combat.
        do
            local rgn = healthBorderRow._leftRegion
            local _, oocCogShow = EllesmereUI.BuildCogPopup({
                title = "Out of Combat Opacity",
                rows = {
                    { type = "toggle", label = "Fade Out of Combat",
                      get = function() local c = cfg(); return c and c.oocFadeEnabled == true end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.oocFadeEnabled = v; RefreshHealth()
                      end },
                    { type = "slider", label = "Opacity",
                      min = 0, max = 100, step = 1,
                      disabled = function() local c = cfg(); return not (c and c.oocFadeEnabled) end,
                      get = function() local c = cfg(); return math.floor(((c and c.oocAlpha) or 0.5) * 100 + 0.5) end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.oocAlpha = v / 100; RefreshHealth()
                      end },
                },
            })
            local oocCog = MakeCogBtn(rgn, oocCogShow)
            local oocCogDis = CreateFrame("Frame", nil, rgn)
            oocCogDis:SetAllPoints(oocCog)
            oocCogDis:SetFrameLevel(oocCog:GetFrameLevel() + 5)
            oocCogDis:EnableMouse(true)
            oocCogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(oocCog, EllesmereUI.DisabledTooltip("Health Bar"))
            end)
            oocCogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateOocCogDis()
                local c = cfg()
                if c and not c.enabled then oocCogDis:Show(); oocCog:SetAlpha(0.15) else oocCogDis:Hide(); oocCog:SetAlpha(0.4) end
            end
            oocCog:HookScript("OnShow", UpdateOocCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateOocCogDis)
            UpdateOocCogDis()
        end

        -- Text Color disable: bar off OR Health Text is None.
        local function healthTextDis()
            local c = cfg()
            if not c then return false end
            if not c.enabled then return true end
            return c.textFormat == "none"
        end
        local function healthTextDisTip()
            local c = cfg()
            if c and not c.enabled then return "Health Bar" end
            return "This option requires a Health Text format other than None"
        end

        -- Row: Health Text | Text Color
        local healthTextSizeRow
        healthTextSizeRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Health Text",
              disabled = healthOff,
              disabledTooltip = "Health Bar",
              values = { none = "None", perhp = "Health %", perhpnosign = "Health % (No Sign)", curhpshort = "Health #", perhpnum = "Health % | #", both = "Health # | %" },
              order = { "none", "---", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both" },
              getValue = function() local c = cfg(); return c and c.textFormat or "none" end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.textFormat = v; RefreshHealth(); EllesmereUI:RefreshPage()
              end },
            { type = "multiSwatch", text = "Text Color",
              disabled = healthTextDis,
              disabledTooltip = healthTextDisTip,
              swatches = {
                { tooltip = "Custom Colored",
                  hasAlpha = true,
                  getValue = function()
                      local c = cfg()
                      if not c then return 1, 1, 1, 1 end
                      return c.textFillR, c.textFillG, c.textFillB, c.textFillA
                  end,
                  setValue = function(r, g, b, a)
                      local c = cfg(); if not c then return end
                      c.textFillR, c.textFillG, c.textFillB, c.textFillA = r, g, b, a
                      RebuildHealth(); SmoothRefresh()
                  end,
                  onClick = function(self)
                      local c = cfg(); if not c then return end
                      if c.textCustomColored == false then
                          c.textCustomColored = true; RebuildHealth()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local c = cfg()
                      local isClassColored = c and c.textCustomColored == false
                      return isClassColored and 0.3 or 1
                  end },
                { tooltip = "Class Colored",
                  getValue = function()
                      local _, classFile = UnitClass("player")
                      local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                      if cc then return cc.r, cc.g, cc.b, 1 end
                      return 1, 1, 1, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      local c = cfg(); if not c then return end
                      c.textCustomColored = false; RebuildHealth()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local c = cfg()
                      local isClassColored = c and c.textCustomColored == false
                      return isClassColored and 1 or 0.3
                  end },
              } }
        );  y = y - h
        -- Inline cog (RESIZE) on Health Text for x/y offsets
        do
            local rgn = healthTextSizeRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Health Text",
                rows = {
                    { type = "dropdown", label = "Anchor",
                      values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                      order = { "LEFT", "CENTER", "RIGHT" },
                      tooltip = "Anchor the text inside the bar. The X/Y offsets move it from there.",
                      get = function() local c = cfg(); return c and c.textAnchor or "CENTER" end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.textAnchor = v; RefreshHealth()
                      end },
                    { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                      get = function() local c = cfg(); return c and c.textXOffset or 0 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.textXOffset = v; RefreshHealth()
                      end },
                    { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                      get = function() local c = cfg(); return c and c.textYOffset or 0 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.textYOffset = v; RefreshHealth()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            AddFormTextBtn(rgn, cogBtn, cfg, RefreshHealth)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Health Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisH2()
                local c = cfg()
                if c and not c.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisH2)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisH2)
            UpdateCogDisH2()
        end

        -- Row 5: Text Size | Threshold Settings
        local healthColorRow
        healthColorRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Text Size", min = 8, max = 24, step = 1,
              disabled = healthTextDis,
              disabledTooltip = healthTextDisTip,
              getValue = function() local c = cfg(); return c and c.textSize or 11 end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.textSize = v; RefreshHealth()
              end },
            { type = "label", text = "Threshold Settings" }
        );  y = y - h
        -- Threshold Settings popup. Simple edits DB().health (multi-spec, with
        -- the spec dropdown). Advanced edits the per-spec override (cfg()) in
        -- singleSpec mode: collapse thresholdSpecs to ONE implied-spec entry,
        -- seeded from whatever Simple resolved for this spec, else defaults.
        if ctx.advanced and ctx.specID then
            local c = cfg()
            local ts = c and c.thresholdSpecs
            local normalized = ts and #ts == 1 and ts[1].specIDs and #ts[1].specIDs == 1 and ts[1].specIDs[1] == 0
            if c and not normalized then
                local match, allM
                if ts then
                    for _, e in ipairs(ts) do
                        if e.specIDs then
                            for _, sid in ipairs(e.specIDs) do
                                if sid == ctx.specID then match = e end
                                if sid == 0 then allM = e end
                            end
                        end
                    end
                end
                local src = match or allM
                local single = {}
                if src then
                    for k, v in pairs(src) do
                        if type(v) == "table" then
                            local t = {}
                            for k2, v2 in pairs(v) do
                                if type(v2) == "table" then
                                    local r = {}; for k3, v3 in pairs(v2) do r[k3] = v3 end; t[k2] = r
                                else t[k2] = v2 end
                            end
                            single[k] = t
                        else single[k] = v end
                    end
                else
                    single.thresholdEnabled = false; single.thresholdPct = 30
                    single.thresholdR = 1; single.thresholdG = 0.2; single.thresholdB = 0.2; single.thresholdA = 1
                end
                single.specIDs = { 0 }
                c.thresholdSpecs = { single }
            end
        end

        BuildThresholdSettingsButton({
            parentRgn = healthColorRow._rightRegion,
            getBarData = function() return cfg() end,
            singleSpec = ctx.advanced or nil,
            refreshFn = function() RefreshHealth(); SmoothRefresh() end,
            rebuildFn = function() RebuildHealth() end,
            disabledFn = healthOff,
            disabledTip = "Health Bar",
            showHash = false,
            showPartialCog = false,
            thresholdLabel = "Threshold %",
            threshMin = 1, threshMax = 99,
            popupTitle = "Health Bar Threshold",
            defaultR = 1.0, defaultG = 0.2, defaultB = 0.2, defaultA = 1,
        })
        -- Thresholds have their own per-spec system: lock the slot whenever a
        -- Spec Overrides editing session is active.
        if EllesmereUI.SpecOverrides_AttachEditLock then
            EllesmereUI.SpecOverrides_AttachEditLock(healthColorRow._rightRegion,
                "Thresholds have their own per-spec system and can't be edited while editing a spec group")
        end
        end   -- close Health Bar hidden-while-disabled gate

        -- Synced overlay: cover the fully-built content (near-opaque, controls
        -- barely visible) so the section is the same height synced or not.
        if ctx.advanced and ctx.synced and _advTop then
            local EGc  = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
            local CPAD = EllesmereUI.CONTENT_PAD or 45
            local ov = CreateFrame("Button", nil, parent)
            ov:SetPoint("TOPLEFT", parent, "TOPLEFT", CPAD, _advTop)
            ov:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CPAD, _advTop)
            ov:SetHeight(math.max(1, _advTop - y))
            ov:SetFrameLevel(parent:GetFrameLevel() + 50)
            local obg = ov:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints()
            obg:SetColorTexture(13 / 255, 17 / 255, 25 / 255, 0.96)
            local olbl = EllesmereUI.MakeFont(ov, 12, nil, 1, 1, 1); olbl:SetPoint("CENTER")
            olbl:SetTextColor(1, 1, 1, 0.56)
            olbl:SetText(EllesmereUI.L("Synced with Simple Mode") .. "   —   " .. EllesmereUI.L("click to customise"))
            ov:SetScript("OnEnter", function() olbl:SetTextColor(EGc.r, EGc.g, EGc.b, 1) end)
            ov:SetScript("OnLeave", function() olbl:SetTextColor(1, 1, 1, 0.56) end)
            ov:SetScript("OnClick", function() if ctx.onToggleSync then ctx.onToggleSync() end end)
            ns.ERB_OverlayHealOnShow(ov, obg, olbl)
        end

        -- Simple page: if the current spec overrides Health in Advanced, cover
        -- these controls so edits here aren't silently ignored.
        if not ctx.advanced then ns.ERB_SimpleOverrideOverlay(parent, _advTop, y, "health") end
		-- ns.ERB_ThresholdSettings(parent, _advTop, y, "health")

        return y
    end

    ---------------------------------------------------------------------------
    --  Shared, context-aware POWER section builder (mirror of the health one).
    --  ctx.cfg() -> power table (DB().primary Simple; per-spec override Advanced).
    ---------------------------------------------------------------------------
    function ns.ERB_BuildPowerSection(parent, y, ctx)
        local W = EllesmereUI.Widgets
        local _, h
        local function cfg() return ctx.cfg() end
        local function powerOff() local c = cfg(); return not (c and c.enabled) end
        local powerDisTip = "Power Bar"

        local hdr
        hdr, h = W:SectionHeader(parent, "POWER BAR", y);  y = y - h

        -- Advanced: Synced/Re-sync toggle; controls always built, overlaid when
        -- synced (built at the end) so the section height stays constant.
        local _advTop = y  -- content top (also used by the Simple override overlay)
        if ctx.advanced then
            local EGc  = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
            local syncBtn = CreateFrame("Button", nil, hdr)
            syncBtn:SetSize(92, 22)
            syncBtn:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, 6)
            syncBtn:SetFrameLevel(hdr:GetFrameLevel() + 60)
            local sbg  = EllesmereUI.SolidTex(syncBtn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
            local sbrd = EllesmereUI.MakeBorder(syncBtn, 1, 1, 1, 0.22, EllesmereUI.PanelPP)
            local slbl = EllesmereUI.MakeFont(syncBtn, 11, nil, 1, 1, 1)
            slbl:SetPoint("CENTER")
            if ctx.synced then
                slbl:SetText(EllesmereUI.L("Synced")); slbl:SetTextColor(1, 1, 1, 0.5)
            else
                slbl:SetText(EllesmereUI.L("Re-sync")); slbl:SetTextColor(EGc.r, EGc.g, EGc.b, 1)
            end
            syncBtn:SetScript("OnEnter", function() if sbrd and sbrd.SetColor then sbrd:SetColor(EGc.r, EGc.g, EGc.b, 0.7) end end)
            syncBtn:SetScript("OnLeave", function() if sbrd and sbrd.SetColor then sbrd:SetColor(1, 1, 1, 0.22) end end)
            syncBtn:SetScript("OnClick", function() if ctx.onToggleSync then ctx.onToggleSync() end end)
            _advTop = y
        end

        -- Row 1: Show Power Bar | Orientation
        local powerEnableRow
        powerEnableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Power Bar",
              getValue = function() local c = cfg(); return c and c.enabled end,
              -- DependentSetValue: the rows below Row 1 are hidden while the
              -- bar is off; the flip forces the full rebuild.
              setValue = EllesmereUI.DependentSetValue(
                  function() local c = cfg(); return c and c.enabled end,
                  function(v)
                      local c = cfg(); if not c then return end
                      c.enabled = v; RebuildPower()
                      EllesmereUI:RefreshPage()
                  end) },
            { type = "dropdown", text = "Orientation",
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              values = { HORIZONTAL = "Horizontal", VERTICAL_UP = "Vertical Up", VERTICAL_DOWN = "Vertical Down" },
              order = { "HORIZONTAL", "VERTICAL_UP", "VERTICAL_DOWN" },
              getValue = function()
                  local c = cfg(); local p = DB()
                  return (c and c.orientation) or (p and p.general.orientation) or "HORIZONTAL"
              end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.orientation = v; Refresh()
              end }
        );  y = y - h
        AddFormBarBtn(powerEnableRow._leftRegion, cfg, RebuildPower)

        -- (Per-spec enable picker removed: per-spec enables now live in Spec
        -- Overrides -- capture "Show Power Bar" while editing as a group.)

        -- Everything below Row 1 is HIDDEN entirely while the bar is off (the
        -- toggle's DependentSetValue forces the rebuild on flips).
        if not powerOff() then
        -- Row 2: Height | Width (MatchGuard both modes; sync icons Simple-only).
        local function guard(propKey)
            return EllesmereUI.MatchGuard("ERB_Power", propKey, powerOff, powerDisTip)
        end
        local phDis, phTip, phRaw = guard("Height")
        local pwDis, pwTip, pwRaw = guard("Width")
        local powerSizeRow
        powerSizeRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 30, step = 1,
              disabled = phDis, disabledTooltip = phTip, rawTooltip = phRaw,
              getValue = function() local c = cfg(); return c and c.height or 16 end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.height = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Width",
              min = 50, max = 800, step = 1,
              disabled = pwDis, disabledTooltip = pwTip, rawTooltip = pwRaw,
              getValue = function() local c = cfg(); return c and c.width or 220 end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.width = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        if not ctx.advanced and ctx.syncRows then
            ctx.syncRows.powerHeight = powerSizeRow._leftRegion
            ctx.syncRows.powerWidth  = powerSizeRow._rightRegion
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
                    flashTargets = function() return { ctx.syncRows.powerHeight, ctx.syncRows.classHeight, ctx.syncRows.healthHeight } end,
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
                    flashTargets = function() return { ctx.syncRows.powerWidth, ctx.syncRows.classWidth, ctx.syncRows.healthWidth } end,
                })
            end
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
                  getValue=function() local c = cfg(); return c and c.borderTexture or "solid" end,
                  setValue=function(v)
                      local c = cfg(); if not c then return end
                      c.borderTexture = v; c.borderTextureOffset = nil; c.borderTextureOffsetY = nil; c.borderTextureShiftX = nil; c.borderTextureShiftY = nil
                      local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      c.borderR = _bcol.r; c.borderG = _bcol.g; c.borderB = _bcol.b; c.borderA = 1
                      c.borderBehind = _bbehind
                      local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                      if defSz then c.borderSize = defSz end
                      RebuildPower(); EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Border Size",
                  min = 0, max = 4, step = 1,
                  disabled = powerOff,
                  disabledTooltip = powerDisTip,
                  getValue = function() local c = cfg(); return c and c.borderSize or 1 end,
                  setValue = function(v)
                      local c = cfg(); if not c then return end
                      c.borderSize = v; RebuildPower()
                      EllesmereUI:RefreshPage()
                  end });  y = y - h
            do
                local rgn = pwrBsRow._rightRegion
                local ctrl = rgn._control
                local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, pwrBsRow:GetFrameLevel() + 3,
                    function()
                        local c = cfg()
                        return (c and c.borderR or 0), (c and c.borderG or 0),
                               (c and c.borderB or 0), (c and c.borderA or 1)
                    end,
                    function(r, g, b, a)
                        local c = cfg(); if not c then return end
                        c.borderR, c.borderG, c.borderB, c.borderA = r, g, b, a
                        SmoothRefresh(); EllesmereUI:RefreshPage()
                    end,
                    true, 20)
                PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch() end)
                local swBlock = CreateFrame("Frame", nil, borderSwatch)
                swBlock:SetAllPoints()
                swBlock:SetFrameLevel(borderSwatch:GetFrameLevel() + 10)
                swBlock:EnableMouse(true)
                swBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(borderSwatch, EllesmereUI.DisabledTooltip(powerDisTip)) end)
                swBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateBorderSwDis()
                    if powerOff() then borderSwatch:SetAlpha(0.3); swBlock:Show()
                    else borderSwatch:SetAlpha(1); swBlock:Hide() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateBorderSwDis)
                UpdateBorderSwDis()
            end
            do
                local rgn = pwrBsRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    rows = {
                        { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                          get = function()
                              local c = cfg(); if not c then return 0 end
                              local v = c.borderTextureOffset
                              if v then return v end
                              local dox = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                              return dox
                          end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderTextureOffset = v; RebuildPower(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                          get = function()
                              local c = cfg(); if not c then return 0 end
                              local v = c.borderTextureOffsetY
                              if v then return v end
                              local _, doy = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                              return doy
                          end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderTextureOffsetY = v; RebuildPower(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                          get = function()
                              local c = cfg(); if not c then return 0 end
                              local v = c.borderTextureShiftX
                              if v then return v end
                              local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                              return dsx
                          end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderTextureShiftX = v == 0 and nil or v; RebuildPower(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                          get = function()
                              local c = cfg(); if not c then return 0 end
                              local v = c.borderTextureShiftY
                              if v then return v end
                              local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                              return dsy
                          end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderTextureShiftY = v == 0 and nil or v; RebuildPower(); EllesmereUI:RefreshPage()
                          end },
                        { type = "toggle", label = "Show Behind",
                          get = function() local c = cfg(); return c and c.borderBehind or false end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderBehind = v == false and nil or v; RebuildPower(); EllesmereUI:RefreshPage()
                          end },
                    },
                })
                local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                local function UpdateCogVis()
                    local c = cfg()
                    local tex = c and c.borderTexture or "solid"
                    if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
            if not ctx.advanced and ctx.syncRows then
                ctx.syncRows.powerBorder = pwrBsRow._rightRegion
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
                            t.borderBehind = s.borderBehind
                        end
                        apply(p.secondary); apply(p.health)
                        SmoothRefresh(); EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local p = DB(); if not p then return false end
                        local bt = p.primary.borderTexture or "solid"
                        local bh = p.primary.borderBehind or false
                        return (p.secondary.borderTexture or "solid") == bt and (p.health.borderTexture or "solid") == bt
                            and (p.secondary.borderBehind or false) == bh and (p.health.borderBehind or false) == bh
                    end,
                    flashTargets = function() return { pwrBsRow._leftRegion } end,
                })
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
                    flashTargets = function() return { ctx.syncRows.powerBorder, ctx.syncRows.classBorder, ctx.syncRows.healthBorder } end,
                })
            end
        end

        -- Row 4: Opacity | Fill Color (gradient/custom/power-colored)
        local powerBorderRow
        powerBorderRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Opacity",
              min = 0, max = 100, step = 5,
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              getValue = function() local c = cfg(); return math.floor((c and c.barAlpha or 1) * 100 + 0.5) end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.barAlpha = v / 100; RefreshPower()
                  EllesmereUI:RefreshPage()
              end },
            { type = "multiSwatch", text = "Fill Color",
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              swatches = {
                { tooltip = "Gradient End Color", hasAlpha = true,
                  disabled = function()
                      local c = cfg(); if not c then return true end
                      if not c.enabled then return true end
                      local tse = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(c)
                      if tse and (tse.thresholdEnabled ~= false) then return true end
                      return not c.gradientEnabled
                  end,
                  disabledTooltip = function()
                      local c = cfg()
                      if not c or not c.enabled then return powerDisTip end
                      local tse = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(c)
                      if tse and (tse.thresholdEnabled ~= false) then return "This option requires Threshold Settings to be disabled" end
                      return "Gradient"
                  end,
                  getValue = function()
                      local c = cfg()
                      if not c then return 0.20, 0.20, 0.80, 1 end
                      return c.gradientR, c.gradientG, c.gradientB, c.gradientA
                  end,
                  setValue = function(r, g, b, a)
                      local c = cfg(); if not c then return end
                      c.gradientR, c.gradientG, c.gradientB, c.gradientA = r, g, b, a
                      SmoothRefresh()
                  end },
                { tooltip = "Custom Colored",
                  hasAlpha = true,
                  getValue = function()
                      local c = cfg()
                      if not c then return 0x23/255, 0x8F/255, 0xE7/255, 1 end
                      return c.fillR, c.fillG, c.fillB, c.fillA
                  end,
                  setValue = function(r, g, b, a)
                      local c = cfg(); if not c then return end
                      c.fillR, c.fillG, c.fillB, c.fillA = r, g, b, a
                      RebuildPower(); SmoothRefresh()
                  end,
                  onClick = function(self)
                      local c = cfg(); if not c then return end
                      if not c.customColored then
                          c.customColored = true; RebuildPower()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local c = cfg()
                      local isPowerColored = not c or not c.customColored
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
                      local c = cfg(); if not c then return end
                      c.customColored = false; RebuildPower()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local c = cfg()
                      local isPowerColored = not c or not c.customColored
                      return isPowerColored and 1 or 0.3
                  end },
              } }
        );  y = y - h
        if not ctx.advanced and ctx.syncRows then
            ctx.syncRows.powerOpacity = powerBorderRow._leftRegion
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
                flashTargets = function() return { ctx.syncRows.powerOpacity, ctx.syncRows.classOpacity, ctx.syncRows.healthOpacity } end,
            })
        end
        do
            local rgn = powerBorderRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Fill Settings",
                rows = {
                    { type = "toggle", label = "Enable Gradient",
                      get = function() local c = cfg(); return c and c.gradientEnabled end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.gradientEnabled = v; RebuildPower()
                          EllesmereUI:RefreshPage()
                      end },
                    { type = "dropdown", label = "Gradient Direction",
                      values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
                      order = { "HORIZONTAL", "VERTICAL" },
                      get = function() local c = cfg(); return c and c.gradientDir or "HORIZONTAL" end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.gradientDir = v; RebuildPower()
                      end },
                    { type = "slider", label = "Fill Opacity", min = 0, max = 100, step = 1,
                      tooltip = "Opacity of the bar fill; below 100 the world shows through the fill instead of the background.",
                      get = function() local c = cfg(); return (c and c.fillOpacity) or 100 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.fillOpacity = v; RebuildPower()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip(powerDisTip))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisGrad()
                local c = cfg()
                if c and not c.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisGrad)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisGrad)
            UpdateCogDisGrad()
        end

        -- Out of Combat Opacity: inline cog on the Opacity slider. Dims the Power
        -- bar to this alpha while out of combat (100 = no fade). Applied via
        -- ns.ResolveBarAlpha in UpdateVisibility; reacts to combat.
        do
            local rgn = powerBorderRow._leftRegion
            local _, oocCogShow = EllesmereUI.BuildCogPopup({
                title = "Out of Combat Opacity",
                rows = {
                    { type = "toggle", label = "Fade Out of Combat",
                      get = function() local c = cfg(); return c and c.oocFadeEnabled == true end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.oocFadeEnabled = v; RefreshPower()
                      end },
                    { type = "slider", label = "Opacity",
                      min = 0, max = 100, step = 1,
                      disabled = function() local c = cfg(); return not (c and c.oocFadeEnabled) end,
                      get = function() local c = cfg(); return math.floor(((c and c.oocAlpha) or 0.5) * 100 + 0.5) end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.oocAlpha = v / 100; RefreshPower()
                      end },
                },
            })
            local oocCog = MakeCogBtn(rgn, oocCogShow)
            local oocCogDis = CreateFrame("Frame", nil, rgn)
            oocCogDis:SetAllPoints(oocCog)
            oocCogDis:SetFrameLevel(oocCog:GetFrameLevel() + 5)
            oocCogDis:EnableMouse(true)
            oocCogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(oocCog, EllesmereUI.DisabledTooltip(powerDisTip))
            end)
            oocCogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateOocCogDis()
                local c = cfg()
                if c and not c.enabled then oocCogDis:Show(); oocCog:SetAlpha(0.15) else oocCogDis:Hide(); oocCog:SetAlpha(0.4) end
            end
            oocCog:HookScript("OnShow", UpdateOocCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateOocCogDis)
            UpdateOocCogDis()
        end

        -- Text Color disable: bar off OR Power Text is None.
        local function powerTextDis()
            local c = cfg()
            if not c then return false end
            if not c.enabled then return true end
            return c.textFormat == "none"
        end
        local function powerTextDisTip()
            local c = cfg()
            if c and not c.enabled then return powerDisTip end
            return "This option requires a Power Text format other than None"
        end

        -- Row: Power Text | Text Color
        local powerTextSizeRow
        powerTextSizeRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Power Text",
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              values = { none = "None", smart = "Smart Text", curpp = "Power Value", perpp = "Power %", both = "Power Value | Power %" },
              order = { "none", "smart", "curpp", "perpp", "both" },
              getValue = function() local c = cfg(); return c and c.textFormat or "none" end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.textFormat = v; RefreshPower(); EllesmereUI:RefreshPage()
              end },
            { type = "multiSwatch", text = "Text Color",
              disabled = powerTextDis,
              disabledTooltip = powerTextDisTip,
              swatches = {
                { tooltip = "Custom Colored",
                  hasAlpha = true,
                  getValue = function()
                      local c = cfg()
                      if not c then return 1, 1, 1, 1 end
                      return c.textFillR, c.textFillG, c.textFillB, c.textFillA
                  end,
                  setValue = function(r, g, b, a)
                      local c = cfg(); if not c then return end
                      c.textFillR, c.textFillG, c.textFillB, c.textFillA = r, g, b, a
                      RebuildPower(); SmoothRefresh()
                  end,
                  onClick = function(self)
                      local c = cfg(); if not c then return end
                      if c.textCustomColored == false then
                          c.textCustomColored = true; RebuildPower()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local c = cfg()
                      local isPowerColored = c and c.textCustomColored == false
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
                      local c = cfg(); if not c then return end
                      c.textCustomColored = false; RebuildPower()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local c = cfg()
                      local isPowerColored = c and c.textCustomColored == false
                      return isPowerColored and 1 or 0.3
                  end },
              } }
        );  y = y - h

        -- Row 5: Text Size | Threshold Settings
        local powerColorRow
        powerColorRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Text Size", min = 8, max = 24, step = 1,
              disabled = powerTextDis,
              disabledTooltip = powerTextDisTip,
              getValue = function() local c = cfg(); return c and c.textSize or 11 end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.textSize = v; RefreshPower()
              end },
            { type = "label", text = "Threshold Settings" }
        );  y = y - h
        -- Inline cog (RESIZE) on Power Text for percent sign + x/y offsets
        do
            local rgn = powerTextSizeRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Power Text",
                rows = {
                    { type = "toggle", label = "Show %",
                      get = function() local c = cfg(); return (not c) or c.showPercent ~= false end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.showPercent = v; RefreshPower()
                      end },
                    { type = "dropdown", label = "Anchor",
                      values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                      order = { "LEFT", "CENTER", "RIGHT" },
						tooltip = "Anchor the text inside the bar. The X/Y offsets move it from there.",
                      get = function() local c = cfg(); return c and c.textAnchor or "CENTER" end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.textAnchor = v; RefreshPower()
                      end },
                    { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                      get = function() local c = cfg(); return c and c.textXOffset or 0 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.textXOffset = v; RefreshPower()
                      end },
                    { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                      get = function() local c = cfg(); return c and c.textYOffset or 0 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.textYOffset = v; RefreshPower()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            AddFormTextBtn(rgn, cogBtn, cfg, RefreshPower)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Power Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisP2()
                local c = cfg()
                if c and not c.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisP2)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisP2)
            UpdateCogDisP2()
        end
        -- Threshold Settings popup. Advanced => singleSpec on the per-spec override
        -- (normalize cfg().thresholdSpecs to one implied-spec entry). Form-specific
        -- mode holds three per-form entries and manages its own list, so skip it.
        if ctx.advanced and ctx.specID and not (cfg() and cfg().thresholdFormMode) then
            local c = cfg()
            local ts = c and c.thresholdSpecs
            local normalized = ts and #ts == 1 and ts[1].specIDs and #ts[1].specIDs == 1 and ts[1].specIDs[1] == 0
            if c and not normalized then
                local match, allM
                if ts then
                    for _, e in ipairs(ts) do
                        if e.specIDs then
                            for _, sid in ipairs(e.specIDs) do
                                if sid == ctx.specID then match = e end
                                if sid == 0 then allM = e end
                            end
                        end
                    end
                end
                local src = match or allM
                local single = {}
                if src then
                    for k, v in pairs(src) do
                        if type(v) == "table" then
                            local t = {}
                            for k2, v2 in pairs(v) do
                                if type(v2) == "table" then
                                    local r = {}; for k3, v3 in pairs(v2) do r[k3] = v3 end; t[k2] = r
                                else t[k2] = v2 end
                            end
                            single[k] = t
                        else single[k] = v end
                    end
                else
                    single.thresholdEnabled = false; single.thresholdPct = 30
                    single.thresholdR = 1; single.thresholdG = 0.2; single.thresholdB = 0.2; single.thresholdA = 1
                end
                single.specIDs = { 0 }
                c.thresholdSpecs = { single }
            end
        end
        BuildThresholdSettingsButton({
            parentRgn = powerColorRow._rightRegion,
            getBarData = function() return cfg() end,
            singleSpec = ctx.advanced or nil,
            refreshFn = function() RefreshPower(); SmoothRefresh() end,
            rebuildFn = function() RebuildPower() end,
            disabledFn = powerOff,
            disabledTip = "Power Bar",
            showHash = false,
            showPartialCog = true,
            thresholdLabel = "Threshold %",
            threshMin = 1, threshMax = 99,
            popupTitle = "Power Bar Threshold",
            defaultR = 1.0, defaultG = 0.2, defaultB = 0.2, defaultA = 1,
            formCapable = true,
        })
        -- Thresholds have their own per-spec system: lock the slot whenever a
        -- Spec Overrides editing session is active.
        if EllesmereUI.SpecOverrides_AttachEditLock then
            EllesmereUI.SpecOverrides_AttachEditLock(powerColorRow._rightRegion,
                "Thresholds have their own per-spec system and can't be edited while editing a spec group")
        end
        end   -- close Power Bar hidden-while-disabled gate

        -- Synced overlay: cover the fully-built content so size is constant.
        if ctx.advanced and ctx.synced and _advTop then
            local EGc  = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
            local CPAD = EllesmereUI.CONTENT_PAD or 45
            local ov = CreateFrame("Button", nil, parent)
            ov:SetPoint("TOPLEFT", parent, "TOPLEFT", CPAD, _advTop)
            ov:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CPAD, _advTop)
            ov:SetHeight(math.max(1, _advTop - y))
            ov:SetFrameLevel(parent:GetFrameLevel() + 50)
            local obg = ov:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints()
            obg:SetColorTexture(13 / 255, 17 / 255, 25 / 255, 0.96)
            local olbl = EllesmereUI.MakeFont(ov, 12, nil, 1, 1, 1); olbl:SetPoint("CENTER")
            olbl:SetTextColor(1, 1, 1, 0.56)
            olbl:SetText(EllesmereUI.L("Synced with Simple Mode") .. "   —   " .. EllesmereUI.L("click to customise"))
            ov:SetScript("OnEnter", function() olbl:SetTextColor(EGc.r, EGc.g, EGc.b, 1) end)
            ov:SetScript("OnLeave", function() olbl:SetTextColor(1, 1, 1, 0.56) end)
            ov:SetScript("OnClick", function() if ctx.onToggleSync then ctx.onToggleSync() end end)
            ns.ERB_OverlayHealOnShow(ov, obg, olbl)
        end

        -- Simple page: if the current spec overrides Power in Advanced, cover
        -- these controls so edits here aren't silently ignored.
        if not ctx.advanced then ns.ERB_SimpleOverrideOverlay(parent, _advTop, y, "primary") end

        return y
    end

    ---------------------------------------------------------------------------
    --  Shared, context-aware CLASS RESOURCE (secondary) section builder.
    --  ctx.cfg() -> secondary table. The Guardian/Prot special-bar rows show in
    --  both modes for the relevant spec (global storage). The Hide-Power cog and
    --  the per-spec enable picker are Simple-only. Threshold (bespoke popup) is
    --  appended in a later chunk.
    ---------------------------------------------------------------------------
    function ns.ERB_BuildClassResourceSection(parent, y, ctx)
        local W = EllesmereUI.Widgets
        local _, h
        local function cfg() return ctx.cfg() end
        local function classOff() local c = cfg(); return not (c and c.enabled) end

        local hdr
        hdr, h = W:SectionHeader(parent, "CLASS RESOURCE BAR", y);  y = y - h

        local _advTop = y  -- content top (also used by the Simple override overlay)
        if ctx.advanced then
            local EGc = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
            local syncBtn = CreateFrame("Button", nil, hdr)
            syncBtn:SetSize(92, 22)
            syncBtn:SetPoint("BOTTOMRIGHT", hdr, "BOTTOMRIGHT", 0, 6)
            syncBtn:SetFrameLevel(hdr:GetFrameLevel() + 60)
            local sbg  = EllesmereUI.SolidTex(syncBtn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
            local sbrd = EllesmereUI.MakeBorder(syncBtn, 1, 1, 1, 0.22, EllesmereUI.PanelPP)
            local slbl = EllesmereUI.MakeFont(syncBtn, 11, nil, 1, 1, 1)
            slbl:SetPoint("CENTER")
            if ctx.synced then
                slbl:SetText(EllesmereUI.L("Synced")); slbl:SetTextColor(1, 1, 1, 0.5)
            else
                slbl:SetText(EllesmereUI.L("Re-sync")); slbl:SetTextColor(EGc.r, EGc.g, EGc.b, 1)
            end
            syncBtn:SetScript("OnEnter", function() if sbrd and sbrd.SetColor then sbrd:SetColor(EGc.r, EGc.g, EGc.b, 0.7) end end)
            syncBtn:SetScript("OnLeave", function() if sbrd and sbrd.SetColor then sbrd:SetColor(1, 1, 1, 0.22) end end)
            syncBtn:SetScript("OnClick", function() if ctx.onToggleSync then ctx.onToggleSync() end end)
            _advTop = y
        end

        -- Guardian Ironfur + Prot Ignore Pain special bars. These stay global at
        -- runtime (stored on DB().secondary, not per-spec), but the row is shown in
        -- both Simple and Advanced for the relevant spec -- like the Enhance 5-bar
        -- toggle. In Advanced gate on the configured spec; in Simple gate on the
        -- active spec.
        do
            local function _IsGuardianDruid()
                if ctx.advanced then return ctx.specID == 104 end
                local _, cf = UnitClass("player")
                if cf ~= "DRUID" then return false end
                local s = GetSpecialization()
                local sid = s and GetSpecializationInfo(s)
                return sid == 104
            end
            if _IsGuardianDruid() then
                local _ifOff = function() local p = DB(); return p and not p.secondary.guardianIronfurBar end
                local _, hh = W:DualRow(parent, y,
                    { type = "toggle", text = "Guardian Druid Ironfur Bar",
                      tooltip = "Replaces the class resource bar with an Ironfur tracker. Each Ironfur cast adds a hash line that slides from right to left as its buff decays. Duration is talent-aware (Ursoc's Endurance and Guardian of Elune).",
                      getValue = function() local p = DB(); return p and p.secondary.guardianIronfurBar end,
                      setValue = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.guardianIronfurBar = v; RebuildClass()
                          EllesmereUI:RefreshPage()
                      end },
                    { type = "toggle", text = "Show Hash Lines",
                      disabled = _ifOff,
                      disabledTooltip = "Guardian Druid Ironfur Bar",
                      getValue = function() local p = DB(); return p and p.secondary.guardianShowHashLines ~= false end,
                      setValue = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.guardianShowHashLines = v; SmoothRefresh()
                          EllesmereUI:RefreshPage()
                      end }
                );  y = y - hh
            end
            local function _IsProtWarrior()
                if ctx.advanced then return ctx.specID == 73 end
                local _, cf = UnitClass("player")
                if cf ~= "WARRIOR" then return false end
                local s = GetSpecialization()
                local sid = s and GetSpecializationInfo(s)
                return sid == 73
            end
            if _IsProtWarrior() then
                local ipBarTip = "Creates a class resource bar for Ignore Pain tracking. To see stack text, you must have Ignore Pain tracked in your Blizzard CDM \"Tracked Buffs\" or \"Tracked Bars\" section."
                local ipHashTip = "Draws a hash line that resets to the right edge when you cast Ignore Pain and slides left as the buff runs out."
                local ipRow
                ipRow, h = W:DualRow(parent, y,
                    { type = "toggle", text = "Prot Warrior Ignore Pain Bar",
                      tooltip = ipBarTip,
                      getValue = function() local p = DB(); return p and p.secondary.protIgnorePainBar end,
                      setValue = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.protIgnorePainBar = v; RebuildClass()
                          EllesmereUI:RefreshPage()
                      end },
                    { type = "toggle", text = "Show Hash Line",
                      tooltip = ipHashTip,
                      disabled = function() local p = DB(); return not (p and p.secondary.protIgnorePainBar) end,
                      disabledTooltip = "Prot Warrior Ignore Pain Bar",
                      getValue = function() local p = DB(); return p and p.secondary.protIgnorePainHashLine ~= false end,
                      setValue = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.protIgnorePainHashLine = v
                          EllesmereUI:RefreshPage()
                      end }
                );  y = y - h
                local function IPControlTip(rgn, tip)
                    local c = rgn and rgn._control
                    if not c or not c.HookScript then return end
                    c:HookScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, tip) end)
                    c:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                end
                IPControlTip(ipRow._leftRegion, ipBarTip)
                IPControlTip(ipRow._rightRegion, ipHashTip)
            end
            local function _IsArmsWarrior()
                if ctx.advanced then return ctx.specID == 71 end
                local _, cf = UnitClass("player")
                if cf ~= "WARRIOR" then return false end
                local s = GetSpecialization()
                local sid = s and GetSpecializationInfo(s)
                return sid == 71
            end
            if _IsArmsWarrior() then
                local ssBarTip = "Shows Sweeping Strikes charges on the resource bar; Unit Frames and the personal Nameplate show them regardless."
                local ssRow
                ssRow, h = W:DualRow(parent, y,
                    { type = "toggle", text = "Arms Warrior Sweeping Strikes Bar",
                      tooltip = ssBarTip,
                      getValue = function() local p = DB(); return p and p.secondary.armsSweepingStrikesBar end,
                      setValue = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.armsSweepingStrikesBar = v; RebuildClass()
                          EllesmereUI:RefreshPage()
                      end },
                    { type = "label", text = "" }
                );  y = y - h
            end
        end

        -- Row 1: Show Class Resource | Orientation
        local classEnableRow
        classEnableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Class Resource",
              getValue = function() local c = cfg(); return c and c.enabled end,
              -- DependentSetValue: the rows below Row 1 are hidden while the
              -- bar is off; the flip forces the full rebuild.
              setValue = EllesmereUI.DependentSetValue(
                  function() local c = cfg(); return c and c.enabled end,
                  function(v)
                      local c = cfg(); if not c then return end
                      c.enabled = v; RebuildClass()
                      EllesmereUI:RefreshPage()
                  end) },
            { type = "dropdown", text = "Orientation",
              disabled = classOff,
              disabledTooltip = "Class Resource",
              values = { HORIZONTAL = "Horizontal", VERTICAL_UP = "Vertical Up", VERTICAL_DOWN = "Vertical Down" },
              order  = { "HORIZONTAL", "VERTICAL_UP", "VERTICAL_DOWN" },
              getValue = function()
                  local c = cfg(); if not c then return "HORIZONTAL" end
                  local v = c.pipOrientation or "HORIZONTAL"
                  if v == "VERTICAL" then v = "VERTICAL_DOWN" end
                  return v
              end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.pipOrientation = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        -- Hide-Power cog + per-spec enable picker -- Simple only.
        if not ctx.advanced then
            do
                local rgn = classEnableRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Class Resource",
                    rows = {
                        { type = "toggle", label = "Hide Power Bar if Resource",
                          get = function() local c = cfg(); return c and c.hidePowerIfResource end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.hidePowerIfResource = v; RebuildClass()
                          end },
                    },
                })
                local cogBtn = MakeCogBtn(rgn, cogShow)
                local cogDis = CreateFrame("Frame", nil, rgn)
                cogDis:SetAllPoints(cogBtn)
                cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
                cogDis:EnableMouse(true)
                cogDis:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Class Resource"))
                end)
                cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateClassCogDis()
                    if classOff() then cogDis:Show() else cogDis:Hide() end
                end
                cogBtn:HookScript("OnShow", UpdateClassCogDis)
                EllesmereUI.RegisterWidgetRefresh(UpdateClassCogDis)
                UpdateClassCogDis()
            end
            -- (Per-spec enable picker removed: per-spec enables now live in
            -- Spec Overrides -- capture "Show Class Resource" while editing
            -- as a group.)
        end
        -- Chains left of the Hide-Power cog in Simple mode (rgn._lastInline),
        -- or the toggle itself in Advanced.
        AddFormBarBtn(classEnableRow._leftRegion, cfg, RebuildClass)

        -- Everything below Row 1 is HIDDEN entirely while the bar is off (the
        -- toggle's DependentSetValue forces the rebuild on flips).
        -- classColorRow is hoisted above the gate: the section returns it for
        -- the Simple page's count-text click mapping (nil while hidden).
        local classColorRow
        if not classOff() then
        -- Row 2: Height | Width (MatchGuard both modes; sync icons Simple-only).
        local function classGuard(propKey)
            return EllesmereUI.MatchGuard("ERB_ClassResource", propKey, classOff, "Class Resource")
        end
        local chDis, chTip, chRaw = classGuard("Height")
        local cwDis, cwTip, cwRaw = classGuard("Width")
        local classSizeRow
        classSizeRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 60, step = 1,
              disabled = chDis, disabledTooltip = chTip, rawTooltip = chRaw,
              getValue = function() local c = cfg(); return c and c.pipHeight or 20 end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.pipHeight = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Width",
              min = 10, max = 800, step = 1,
              disabled = cwDis, disabledTooltip = cwTip, rawTooltip = cwRaw,
              getValue = function() local c = cfg(); return c and c.pipWidth or 214 end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.pipWidth = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        if not ctx.advanced and ctx.syncRows then
            ctx.syncRows.classHeight = classSizeRow._leftRegion
            ctx.syncRows.classWidth  = classSizeRow._rightRegion
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
                    flashTargets = function() return { ctx.syncRows.classHeight, ctx.syncRows.powerHeight, ctx.syncRows.healthHeight } end,
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
                    flashTargets = function() return { ctx.syncRows.classWidth, ctx.syncRows.powerWidth, ctx.syncRows.healthWidth } end,
                })
            end
        end

        -- Row: Border Style dropdown (+ inline offset cog)
        do
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local classBsRow
            classBsRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style",
                  disabled = classOff,
                  disabledTooltip = "Class Resource",
                  values=texValues, order=texOrder,
                  getValue=function() local c = cfg(); return c and c.borderTexture or "solid" end,
                  setValue=function(v)
                      local c = cfg(); if not c then return end
                      c.borderTexture = v; c.borderTextureOffset = nil; c.borderTextureOffsetY = nil; c.borderTextureShiftX = nil; c.borderTextureShiftY = nil
                      local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      c.borderR = _bcol.r; c.borderG = _bcol.g; c.borderB = _bcol.b; c.borderA = 1
                      c.borderBehind = _bbehind
                      local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                      if defSz then c.borderSize = defSz end
                      RebuildClass(); EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Border Size",
                  min = 0, max = 4, step = 1,
                  disabled = classOff,
                  disabledTooltip = "Class Resource",
                  getValue = function() local c = cfg(); return c and c.borderSize or 1 end,
                  setValue = function(v)
                      local c = cfg(); if not c then return end
                      c.borderSize = v; RebuildClass()
                      EllesmereUI:RefreshPage()
                  end });  y = y - h
            if not ctx.advanced and ctx.syncRows then ctx.syncRows.classBorder = classBsRow._rightRegion end
            -- Inline color swatch on Border Size (right region)
            do
                local rgn = classBsRow._rightRegion
                local ctrl = rgn._control
                local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, classBsRow:GetFrameLevel() + 3,
                    function()
                        local c = cfg()
                        return (c and c.borderR or 0), (c and c.borderG or 0),
                               (c and c.borderB or 0), (c and c.borderA or 1)
                    end,
                    function(r, g, b, a)
                        local c = cfg(); if not c then return end
                        c.borderR, c.borderG, c.borderB, c.borderA = r, g, b, a
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
                              local c = cfg(); if not c then return 0 end
                              local v = c.borderTextureOffset
                              if v then return v end
                              local dox = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                              return dox
                          end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderTextureOffset = v; RebuildClass(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                          get = function()
                              local c = cfg(); if not c then return 0 end
                              local v = c.borderTextureOffsetY
                              if v then return v end
                              local _, doy = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                              return doy
                          end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderTextureOffsetY = v; RebuildClass(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                          get = function()
                              local c = cfg(); if not c then return 0 end
                              local v = c.borderTextureShiftX
                              if v then return v end
                              local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                              return dsx
                          end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderTextureShiftX = v == 0 and nil or v; RebuildClass(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                          get = function()
                              local c = cfg(); if not c then return 0 end
                              local v = c.borderTextureShiftY
                              if v then return v end
                              local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", c.borderTexture or "solid", c.borderSize or 1)
                              return dsy
                          end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderTextureShiftY = v == 0 and nil or v; RebuildClass(); EllesmereUI:RefreshPage()
                          end },
                        { type = "toggle", label = "Show Behind",
                          get = function() local c = cfg(); return c and c.borderBehind or false end,
                          set = function(v)
                              local c = cfg(); if not c then return end
                              c.borderBehind = v == false and nil or v; RebuildClass(); EllesmereUI:RefreshPage()
                          end },
                    },
                })
                local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                local function UpdateCogVis()
                    local c = cfg()
                    local tex = c and c.borderTexture or "solid"
                    if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
            -- Cross-bar sync icons (Simple page only).
            if not ctx.advanced and ctx.syncRows then
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
                            t.borderBehind = s.borderBehind
                        end
                        apply(p.primary); apply(p.health)
                        SmoothRefresh(); EllesmereUI:RefreshPage()
                    end,
                    isSynced = function()
                        local p = DB(); if not p then return false end
                        local bt = p.secondary.borderTexture or "solid"
                        local bh = p.secondary.borderBehind or false
                        return (p.primary.borderTexture or "solid") == bt and (p.health.borderTexture or "solid") == bt
                            and (p.primary.borderBehind or false) == bh and (p.health.borderBehind or false) == bh
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
                    flashTargets = function() return { ctx.syncRows.classBorder, ctx.syncRows.powerBorder, ctx.syncRows.healthBorder } end,
                })
            end
        end

        -- Row: Bar Spacing (slider + opt-in gap-color toggle/swatch) | Empty Bar Overlay (opacity slider + inline color swatch)
        -- Empty Bar Overlay exposes bgR/G/B/A, the overlay tint on the (empty)
        -- pip backgrounds. Bar Spacing's color is opt-in: an inline toggle
        -- (gapColorEnabled) activates a gap-only fill layer (gapR/G/B/A).
        do
            local classGapRow
            classGapRow, h = W:DualRow(parent, y,
                { type = "slider", pixel = true, text = "Bar Spacing", min = 0, max = 20, step = 1,
                  disabled = classOff,
                  disabledTooltip = "Class Resource",
                  getValue = function() local c = cfg(); return c and c.pipSpacing or 3 end,
                  setValue = function(v)
                      local c = cfg(); if not c then return end
                      c.pipSpacing = v; SmoothRefresh()
                  end },
                { type = "slider", text = "Empty Bar Overlay", min = 0, max = 100, step = 5,
                  disabled = classOff,
                  disabledTooltip = "Class Resource",
                  getValue = function() local c = cfg(); return math.floor(((c and c.bgA) or 0.1) * 100 + 0.5) end,
                  setValue = function(v)
                      local c = cfg(); if not c then return end
                      c.bgA = v / 100; RefreshClass()
                      EllesmereUI:RefreshPage()
                  end });  y = y - h
            -- Inline enable toggle + gap-color swatch on Bar Spacing (left region).
            do
                local rgn = classGapRow._leftRegion
                local ctrl = rgn._control
                local gapSwatch, updateGapSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, classGapRow:GetFrameLevel() + 3,
                    function()
                        local c = cfg()
                        return (c and c.gapR or 0), (c and c.gapG or 0),
                               (c and c.gapB or 0), (c and c.gapA or 1)
                    end,
                    function(r, g, b, a)
                        local c = cfg(); if not c then return end
                        c.gapR, c.gapG, c.gapB, c.gapA = r, g, b, a
                        SmoothRefresh(); EllesmereUI:RefreshPage()
                    end,
                    true, 20)
                PP.Point(gapSwatch, "RIGHT", rgn._lastInline or ctrl, "LEFT", -8, 0)
                rgn._lastInline = gapSwatch
                EllesmereUI.RegisterWidgetRefresh(function() updateGapSwatch() end)
                local gapBlock = CreateFrame("Frame", nil, gapSwatch)
                gapBlock:SetAllPoints()
                gapBlock:SetFrameLevel(gapSwatch:GetFrameLevel() + 10)
                gapBlock:EnableMouse(true)
                gapBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(gapSwatch, "Enable the toggle to set a custom gap color")
                end)
                gapBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateGapSwatchState()
                    local c = cfg()
                    if c and c.gapColorEnabled then
                        gapSwatch:SetAlpha(1); gapBlock:Hide()
                    else
                        gapSwatch:SetAlpha(0.3); gapBlock:Show()
                    end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateGapSwatchState)
                UpdateGapSwatchState()
                EllesmereUI.BuildInlineToggle({
                    region = rgn,
                    getValue = function() local c = cfg(); return c and c.gapColorEnabled end,
                    setValue = function(v)
                        local c = cfg(); if not c then return end
                        c.gapColorEnabled = v and true or nil
                        SmoothRefresh(); EllesmereUI:RefreshPage()
                    end,
                })
            end
            -- Inline overlay-color swatch on Empty Bar Overlay (right region, RGB only).
            do
                local rgn = classGapRow._rightRegion
                local ctrl = rgn._control
                local ovSwatch, updateOvSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, classGapRow:GetFrameLevel() + 3,
                    function()
                        local c = cfg()
                        return (c and c.bgR or 1), (c and c.bgG or 1),
                               (c and c.bgB or 1), 1
                    end,
                    function(r, g, b)
                        local c = cfg(); if not c then return end
                        c.bgR, c.bgG, c.bgB = r, g, b
                        RefreshClass(); EllesmereUI:RefreshPage()
                    end,
                    false, 20)
                PP.Point(ovSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                EllesmereUI.RegisterWidgetRefresh(function() updateOvSwatch() end)
            end
        end

        -- Row 4: (Sync) Opacity | Fill Color
        local classBorderRow
        classBorderRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Opacity",
              min = 0, max = 100, step = 5,
              disabled = classOff,
              disabledTooltip = "Class Resource",
              getValue = function() local c = cfg(); return math.floor(((c and c.barAlpha) or 1) * 100 + 0.5) end,
              setValue = function(v)
                  local c = cfg(); if not c then return end
                  c.barAlpha = v / 100; RefreshClass()
                  EllesmereUI:RefreshPage()
              end },
            { type = "multiSwatch", text = "Fill Color",
              disabled = function() local c = cfg(); return (not c) or (not c.enabled) or c.darkTheme end,
              disabledTooltip = function()
                  local c = cfg()
                  if c and c.darkTheme then return "This option requires Dark Mode Class Resource to be disabled" end
                  return "Class Resource"
              end,
              swatches = {
                { tooltip = "Custom Colored",
                  hasAlpha = true,
                  getValue = function()
                      local c = cfg()
                      if not c then return 0xDB/255, 0xCF/255, 0x37/255, 1 end
                      return c.fillR, c.fillG, c.fillB, c.fillA
                  end,
                  setValue = function(r, g, b, a)
                      local c = cfg(); if not c then return end
                      c.fillR, c.fillG, c.fillB, c.fillA = r, g, b, a
                      RebuildClass(); SmoothRefresh()
                  end,
                  onClick = function(self)
                      local c = cfg(); if not c then return end
                      local inCustom = (not c.resourceColored) and (c.classColored == false)
                      if not inCustom then
                          c.resourceColored = nil
                          c.classColored = false; RebuildClass()
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local c = cfg()
                      local inCustom = c and (not c.resourceColored) and (c.classColored == false)
                      return inCustom and 1 or 0.3
                  end },
                { tooltip = "Class Colored",
                  getValue = function()
                      local _, classFile = UnitClass("player")
                      local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                      if cc then return cc.r, cc.g, cc.b, 1 end
                      return 1, 0.82, 0, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      local c = cfg(); if not c then return end
                      c.resourceColored = nil
                      c.classColored = true; RebuildClass()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local c = cfg()
                      local isClassMode = c and (not c.resourceColored) and (c.classColored ~= false)
                      return isClassMode and 1 or 0.3
                  end },
                { tooltip = "Class Resource Color",
                  getValue = function()
                      -- Show the current spec's resolved resource/power color.
                      local gsr = _G._ERB_GetSecondaryResource
                      local rslv = _G._ERB_ResolveSecondaryResourceColor
                      if gsr and rslv then
                          local info = gsr()
                          if info and info.power ~= nil then
                              local rr, rg, rb = rslv(info.power)
                              if rr then return rr, rg, rb, 1 end
                          end
                      end
                      local _, classFile = UnitClass("player")
                      local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                      if cc then return cc.r, cc.g, cc.b, 1 end
                      return 1, 0.82, 0, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      local c = cfg(); if not c then return end
                      c.resourceColored = true
                      c.classColored = true; RebuildClass()
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local c = cfg()
                      return (c and c.resourceColored) and 1 or 0.3
                  end },
              } }
        );  y = y - h
        -- Inline cog for Charged Combo Point color (on Fill Color)
        do
            local rgn = classBorderRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Fill Settings",
                rows = {
                    { type = "colorpicker", label = "Charged Color", hasAlpha = false,
                      get = function()
                          local c = cfg()
                          if not c then return 0.44, 0.77, 1.00, 1 end
                          return c.chargedR or 0.44, c.chargedG or 0.77,
                                 c.chargedB or 1.00, c.chargedA or 1
                      end,
                      set = function(cr, cg, cb, ca)
                          local c = cfg(); if not c then return end
                          c.chargedR, c.chargedG = cr, cg
                          c.chargedB, c.chargedA = cb, ca
                          RebuildClass(); SmoothRefresh()
                      end },
                    { type = "slider", label = "Fill Opacity", min = 0, max = 100, step = 1,
                      tooltip = "Opacity of the resource fill; below 100 the world shows through the fill instead of the background.",
                      get = function() local c = cfg(); return (c and c.fillOpacity) or 100 end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.fillOpacity = v; RebuildClass(); SmoothRefresh()
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
                EllesmereUI.ShowWidgetTooltip(chargedCog, EllesmereUI.DisabledTooltip("Class Resource"))
            end)
            chargedCogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateChargedCogDis()
                local c = cfg()
                if not (c and c.enabled) then
                    chargedCogDis:Show(); chargedCog:SetAlpha(0.15)
                else
                    chargedCogDis:Hide(); chargedCog:SetAlpha(0.4)
                end
            end
            chargedCog:HookScript("OnShow", UpdateChargedCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateChargedCogDis)
            UpdateChargedCogDis()
        end
        if not ctx.advanced and ctx.syncRows then
            ctx.syncRows.classOpacity = classBorderRow._leftRegion
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
                    flashTargets = function() return { ctx.syncRows.classOpacity, ctx.syncRows.powerOpacity, ctx.syncRows.healthOpacity } end,
                })
            end
        end

        -- Out of Combat Opacity: inline cog on the Opacity slider. Dims the Class
        -- Resource bar to this alpha while out of combat (100 = no fade). Applied
        -- via ns.ResolveBarAlpha in UpdateVisibility; reacts to combat.
        do
            local rgn = classBorderRow._leftRegion
            local _, oocCogShow = EllesmereUI.BuildCogPopup({
                title = "Out of Combat Opacity",
                rows = {
                    { type = "toggle", label = "Fade Out of Combat",
                      get = function() local c = cfg(); return c and c.oocFadeEnabled == true end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.oocFadeEnabled = v; RefreshClass()
                      end },
                    { type = "slider", label = "Opacity",
                      min = 0, max = 100, step = 1,
                      disabled = function() local c = cfg(); return not (c and c.oocFadeEnabled) end,
                      get = function() local c = cfg(); return math.floor(((c and c.oocAlpha) or 0.5) * 100 + 0.5) end,
                      set = function(v)
                          local c = cfg(); if not c then return end
                          c.oocAlpha = v / 100; RefreshClass()
                      end },
                },
            })
            local oocCog = MakeCogBtn(rgn, oocCogShow)
            local oocCogDis = CreateFrame("Frame", nil, rgn)
            oocCogDis:SetAllPoints(oocCog)
            oocCogDis:SetFrameLevel(oocCog:GetFrameLevel() + 5)
            oocCogDis:EnableMouse(true)
            oocCogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(oocCog, EllesmereUI.DisabledTooltip("Class Resource"))
            end)
            oocCogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateOocCogDis()
                local c = cfg()
                if c and not c.enabled then oocCogDis:Show(); oocCog:SetAlpha(0.15) else oocCogDis:Hide(); oocCog:SetAlpha(0.4) end
            end
            oocCog:HookScript("OnShow", UpdateOocCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateOocCogDis)
            UpdateOocCogDis()
        end

        -- Resource Text + the bespoke threshold popup below operate purely on the
        -- class-resource (secondary) config and never touch other bars. To make
        -- them per-spec without rewriting every access path, shadow DB() within
        -- this scope so DB().secondary resolves to cfg() -- the global secondary on
        -- Simple, or the per-spec override (e.secondary) on Advanced. Returns nil
        -- when synced (cfg()==nil) so the existing `if not p` guards short-circuit;
        -- the synced overlay covers these controls anyway.
        local DB = function()
            local c = cfg()
            if not c then return nil end
            return { secondary = c }
        end

        -- Row 5: Resource Text | Threshold & Hash Lines
        classColorRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Resource Text",
              disabled = classOff,
              disabledTooltip = "Class Resource",
              getValue = function() local p = DB(); return p and p.secondary.showText end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.showText = v; RebuildClass()
                  EllesmereUI:RefreshPage()
              end },
            { type = "label", text = "Threshold & Hash Lines" }
        );  y = y - h
        -- Inline color swatch on Resource Text
        do
            local rgn = classColorRow._leftRegion
            local ctrl = rgn._control
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, classColorRow:GetFrameLevel() + 3,
                function()
                    local p = DB()
                    if not p then return 1, 1, 1, 1 end
                    return p.secondary.textR or 1, p.secondary.textG or 1, p.secondary.textB or 1, 1
                end,
                function(r, g, b)
                    local p = DB(); if not p then return end
                    p.secondary.textR, p.secondary.textG, p.secondary.textB = r, g, b
                    RefreshClass()
                end,
                false, 20)
            PP.Point(swatch, "RIGHT", rgn._lastInline or ctrl, "LEFT", -8, 0)
            rgn._lastInline = swatch
            local swatchDis = CreateFrame("Frame", nil, swatch)
            swatchDis:SetAllPoints(); swatchDis:SetFrameLevel(swatch:GetFrameLevel() + 10); swatchDis:EnableMouse(true)
            swatchDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Resource Text"))
            end)
            swatchDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateSwatchDis()
                updateSwatch()
                local p = DB()
                local off = not p or not p.secondary.enabled or not p.secondary.showText
                if off then swatch:SetAlpha(0.3); swatchDis:Show() else swatch:SetAlpha(1); swatchDis:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateSwatchDis)
            UpdateSwatchDis()
        end
        -- Inline cog on Resource Text for size + position
        do
            local rgn = classColorRow._leftRegion
            local resTextRows = {
                { type = "toggle", label = "Show %",
                  get = function()
                      local p = DB()
                      return (not p) or p.secondary.showPercent ~= false
                  end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.showPercent = v; RefreshClass()
                  end },
                { type = "toggle", label = "Only if Power Bar Hidden",
                  tooltip = "Show the resource text only while the power bar is hidden - disabled, filtered off for this spec, a spec with no power, or hidden by \"Hide Power Bar if Resource\". Off = always show the text.",
                  get = function() local p = DB(); return p and p.secondary.showTextOnlyIfNoPower end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.showTextOnlyIfNoPower = v; RebuildClass()
                  end },
                { type = "slider", label = "Size", min = 8, max = 24, step = 1,
                  get = function() local p = DB(); return p and p.secondary.textSize or 11 end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.textSize = v; RefreshClass()
                  end },
                { type = "dropdown", label = "Anchor",
                  values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                  order = { "LEFT", "CENTER", "RIGHT" },
					tooltip = "Anchor the text inside the bar. The X/Y offsets move it from there.",
                  get = function() local p = DB(); return p and p.secondary.textAnchor or "CENTER" end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.textAnchor = v; RefreshClass()
                  end },
                { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                  get = function() local p = DB(); return p and p.secondary.textXOffset or 0 end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.textXOffset = v; RefreshClass()
                  end },
                { type = "slider", label = "Y Offset", min = -100, max = 100, step = 1,
                  get = function() local p = DB(); return p and p.secondary.textYOffset or 0 end,
                  set = function(v)
                      local p = DB(); if not p then return end
                      p.secondary.textYOffset = v; RefreshClass()
                  end },
            }
            -- Devourer (DH soul fragments) only: option to hide the "/ max"
            -- suffix on the count text. Inserted above "Show %".
            do
                local gsr = _G._ERB_GetSecondaryResource
                local secInfo = gsr and gsr()
                if secInfo and secInfo.power == "SOUL_FRAGMENTS_DEVOURER" then
                    table.insert(resTextRows, 1, {
                        type = "toggle", label = "Show Max Stacks",
                        get = function()
                            local p = DB()
                            return (not p) or p.secondary.showMaxStacks ~= false
                        end,
                        set = function(v)
                            local p = DB(); if not p then return end
                            p.secondary.showMaxStacks = v; RefreshClass()
                        end })
                end
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Resource Text",
                rows = resTextRows,
                footer = false,
            })
            local cogBtn = MakeCogBtn(rgn, cogShow)
            AddFormTextBtn(rgn, cogBtn, function() return DB() and DB().secondary end, RefreshClass)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Resource Text"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisCount()
                local p = DB()
                local off = not p or not p.secondary.enabled or not p.secondary.showText
                if off then cogDis:Show(); cogBtn:SetAlpha(0.15) else cogDis:Hide(); cogBtn:SetAlpha(0.4) end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisCount)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisCount)
            UpdateCogDisCount()
        end

		-- class settings [start]
        -- Settings button + popup on Threshold & Hash Lines (row 5 slot 2)
        do
            local settingsRgn = classColorRow._rightRegion
            -- Thresholds have their own per-spec system: lock the slot
            -- whenever a Spec Overrides editing session is active.
            if EllesmereUI.SpecOverrides_AttachEditLock then
                EllesmereUI.SpecOverrides_AttachEditLock(settingsRgn,
                    "Thresholds have their own per-spec system and can't be edited while editing a spec group")
            end

            -- Advanced: this popup edits the per-spec override (cfg()), which only
            -- applies while playing ctx.specID. Drop the spec-assignment chrome
            -- (dropdown + Add Specs) and present a single implied-spec card set --
            -- the base card plus any talent variants -- re-tagged to specIDs={0}.
            -- Talent variants still work via the per-card "+" button.
            local advSingle = (ctx.advanced and ctx.specID) and true or nil
            if advSingle then
                local c = cfg()
                if c then
                    local ts = c.thresholdSpecs
                    -- Already normalized? every card carries specIDs == {0}.
                    local normalized = ts and #ts > 0
                    if ts then
                        for _, e in ipairs(ts) do
                            if not (e.specIDs and #e.specIDs == 1 and e.specIDs[1] == 0) then
                                normalized = false; break
                            end
                        end
                    end
                    if not normalized then
                        -- Keep only the cards relevant to this spec (its own + any
                        -- All-Specs cards, incl. their talent variants), re-tagged.
                        local kept = {}
                        if ts then
                            for _, e in ipairs(ts) do
                                local rel = false
                                if e.specIDs then
                                    for _, sid in ipairs(e.specIDs) do
                                        if sid == 0 or sid == ctx.specID then rel = true; break end
                                    end
                                end
                                if rel then e.specIDs = { 0 }; kept[#kept + 1] = e end
                            end
                        end
                        if #kept == 0 then
                            kept[1] = {
                                specIDs = { 0 },
                                hashValues = "", hashWidth = 1,
                                hashColorR = 1, hashColorG = 1, hashColorB = 1, hashColorA = 0.7,
                                thresholdEnabled = false,
                                thresholdCount = (ctx.specID == 263 and c.enhanceFiveBar) and 7 or 3,
                                thresholdPartialOnly = false,
                                thresholdR = 0x0c/255, thresholdG = 0xd2/255, thresholdB = 0x9d/255, thresholdA = 1,
                            }
                        end
                        c.thresholdSpecs = kept
                    end
                end
            end
            local CLOSE_ICON_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"
            local POPUP_W = 480
            local POPUP_PAD = 14
            local ROW_GAP = 6
            local EG = EllesmereUI.ELLESMERE_GREEN

            -- Deep copy a thresholdSpecs entry (scalars + nested arrays like
            -- specIDs and bands) so a duplicated variant doesn't share tables.
            local function CopyThresholdEntry(src)
                local out = {}
                for k, v in pairs(src) do
                    if type(v) == "table" then
                        local t = {}
                        for k2, v2 in pairs(v) do
                            if type(v2) == "table" then
                                local r = {}
                                for k3, v3 in pairs(v2) do r[k3] = v3 end
                                t[k2] = r
                            else
                                t[k2] = v2
                            end
                        end
                        out[k] = t
                    else
                        out[k] = v
                    end
                end
                return out
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
            btnLbl:SetText(EllesmereUI.L("Settings"))
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
                EllesmereUI.ShowWidgetTooltip(settingsBtn, EllesmereUI.DisabledTooltip("Class Resource"))
            end)
            btnDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBtnDis()
                local p = DB()
                -- In Advanced, DB() is nil when no spec is selected/customised (the
                -- override doesn't exist) -- there's nothing to configure, so disable.
                if not p or not p.secondary.enabled then btnDis:Show() else btnDis:Hide() end
            end
            settingsBtn:HookScript("OnShow", UpdateBtnDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateBtnDis)
            UpdateBtnDis()

            ---------------------------------------------------------------
            --  Popup Frame (lazy-created)
            ---------------------------------------------------------------
			local thrPage
			local specContainer
			local contentHalfSize
			local totalW
			local halfW
			local totalH
            local _entryFrames = {}  -- pool of entry UI frames
            local _addNewBtn         -- empty-state "Add Threshold" button (Advanced only)
            local _tempSpecSel = {}  -- transient dropdown selection
            local _specDDRefresh     -- set after dropdown creation
            local _selectedIdx       -- selected threshold entry (drives the right pane)
            local RefreshDetail      -- right-pane refresher (assigned in BuildFrame)

            -- Build the spec items list for the dropdown
            local CR_ROLE_HEALERS = -1
            local CR_ROLE_TANKS   = -2
            local CR_ROLE_DPS     = -3
            local _crRoleCache = {}

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
                            items[#items + 1] = { key = specID, label = specName, lockedFn = function() return ns.IsCRSpecClaimed(sid) end }
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

            -- Forward declarations for page internals
            local RefreshSpecEntries

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

            local function BuildFrame(args)
				local hdrH     = 40
				local PP       = EllesmereUI.PanelPP or EllesmereUI.PP
				local SIDE_PAD = 20
				local CPAD     = EllesmereUI.CONTENT_PAD or 45
				local INNERPAD = 10
				local ROW_H          = 50
				-- colors
				local defR           = 1
				local defG           = 0.2
				local defB           = 0.2
				local defA           = 1
				local BORDER_R       = EllesmereUI.BORDER_R
				local BORDER_G       = EllesmereUI.BORDER_G
				local BORDER_B       = EllesmereUI.BORDER_B
				local EG             = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
				local CLASS_COLORS_L = CLASS_COLORS

				-- Bottom = the section's actual final Y (args.botY), so the overlay
				-- covers exactly the built section height
				-- Simple mode appends an "Anchor to Cursor" row after this section
				-- Extend the overlay one row down in simple mode
				local thrPageBotY    = args.botY - ((ctx and ctx.advanced) and 0 or ROW_H)
				thrPage = CreateFrame("Frame", nil, parent)
				PP.Point(thrPage, "TOPLEFT", parent, "TOPLEFT", CPAD, args.topY)
				PP.Point(thrPage, "TOPRIGHT", parent, "TOPRIGHT", -CPAD, args.topY)
				PP.Point(thrPage, "BOTTOMLEFT", parent, "TOPLEFT", CPAD, thrPageBotY)
				-- The unlock-mode cycle can leave this lazily-built frame with an
				-- undefined rect.
				-- Capture the resolved anchors so ToggleFrame can re-assert them
				-- before every Show to force a rect recompute.
				local _thrPts = {}
				for p = 1, thrPage:GetNumPoints() do _thrPts[p] = { thrPage:GetPoint(p) } end
				thrPage._reanchor = function()
					thrPage:ClearAllPoints()
					for p = 1, #_thrPts do thrPage:SetPoint(unpack(_thrPts[p])) end
				end
				thrPage:SetFrameLevel(parent:GetFrameLevel() + 50)
				thrPage:EnableMouse(true)
				local obg = thrPage:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints()
				obg:SetColorTexture(13 / 255, 17 / 255, 25 / 255, 1)
				-- 1px center divider (matches global BORDER style)
				local div = thrPage:CreateTexture(nil, "ARTWORK")
				div:SetColorTexture(BORDER_R, BORDER_G, BORDER_B, 0.05)
				div:SetWidth(1)
				div:SetPoint("TOP", thrPage, "TOP", 0, 0)
				div:SetPoint("BOTTOM", thrPage, "BOTTOM", 0, 0)

				-- sizing for inside frame
				totalW             = thrPage:GetWidth()
				halfW              = thrPage:GetWidth() / 2
				contentHalfSize    = math.floor(halfW - (SIDE_PAD * 2))
				totalH             = thrPage:GetHeight()
				local curY               = -INNERPAD
				local BUTTON_W, BUTTON_H = 80, 29
				local MEDIA              = "Interface\\AddOns\\EllesmereUI\\media\\"

				-- back button
				local backBtn            = CreateFrame("Button", nil, thrPage)
				PP.Size(backBtn, BUTTON_W, BUTTON_H)
				PP.Point(backBtn, "TOPLEFT", thrPage, "TOPLEFT", SIDE_PAD, curY)
				backBtn:SetFrameLevel(thrPage:GetFrameLevel() + 2)
				local backBg = backBtn:CreateTexture(nil, "BACKGROUND")
				backBg:SetAllPoints()
				backBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
				local backBrd = EllesmereUI.MakeBorder(backBtn, 1, 1, 1, 0.12, PP)

				local backIcon = backBtn:CreateTexture(nil, "ARTWORK")
				backIcon:SetSize(14, 14)
				PP.Point(backIcon, "LEFT", backBtn, "LEFT", 10, 0)
				backIcon:SetTexture(MEDIA .. "icons\\eui-arrow-left.png")
				backIcon:SetVertexColor(EG.r, EG.g, EG.b)
				backIcon:SetAlpha(0.6)
				if backIcon.SetSnapToPixelGrid then
					backIcon:SetSnapToPixelGrid(false); backIcon:SetTexelSnappingBias(0)
				end

				local backLbl = EllesmereUI.MakeFont(backBtn, 12, nil, 1, 1, 1, 0.55)
				PP.Point(backLbl, "LEFT", backIcon, "RIGHT", 6, 0)
				backLbl:SetText(EllesmereUI.L("Back"))

				backBtn:SetScript("OnEnter", function()
					backBg:SetColorTexture(0.11, 0.13, 0.15, 0.50)
					backBrd:SetColor(1, 1, 1, 0.22)
					backIcon:SetAlpha(0.85)
					backLbl:SetAlpha(0.85)
				end)
				backBtn:SetScript("OnLeave", function()
					backBg:SetColorTexture(0.06, 0.08, 0.10, 0.50)
					backBrd:SetColor(1, 1, 1, 0.12)
					backIcon:SetAlpha(0.6)
					backLbl:SetAlpha(0.55)
				end)
				backBtn:SetScript("OnClick", function()
					thrPage:Hide()
				end)


                -- Spec-assignment chrome (dropdown + Add Specs) -- Simple only; in
                -- Advanced the card set is implicitly this spec (see advSingle).
				local specDDHost
                if not advSingle then
                -- Centered container for dropdown + Add button
					local ADD_W, GAP_L = 90, 10
					local DD_W = contentHalfSize - (INNERPAD * 2) - BUTTON_W - ADD_W
					local rowW = DD_W + GAP_L + ADD_W
					local ddRow = CreateFrame("Frame", nil, backBtn)
					ddRow:SetSize(DD_W, BUTTON_H)
					ddRow:SetPoint("TOPLEFT", backBtn, "TOPRIGHT", 10, 0)
					ddRow:SetFrameLevel(thrPage:GetFrameLevel() + 2)

					-- Spec dropdown (checkbox multi-select with search)
					local specItems = BuildSpecItems()
					specDDHost = CreateFrame("Frame", nil, ddRow)
					specDDHost:SetSize(DD_W, BUTTON_H)
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
							if rgn2.GetText and EllesmereUI.EnKey(rgn2:GetText()) == "None" then
								rgn2:SetText(EllesmereUI.L("Select a Spec..."))
								break
							end
						end
					end
					_specDDRefresh = WrappedRefresh
					WrappedRefresh()

					-- Add Specs button (Reload UI footer style)
					local addBtn = CreateFrame("Button", nil, ddRow)
					PP.Size(addBtn, ADD_W, BUTTON_H)
					addBtn:SetPoint("LEFT", specDDHost, "RIGHT", GAP_L, 0)
					addBtn:SetFrameLevel(ddRow:GetFrameLevel() + 2)
					local addBg = EllesmereUI.SolidTex(addBtn, "BACKGROUND", 0.05, 0.07, 0.09, 0.92)
					addBg:SetAllPoints()
					addBtn._border = EllesmereUI.MakeBorder(addBtn, 1, 1, 1, 0.4, PP)
					local addLbl = EllesmereUI.MakeFont(addBtn, 11, nil, 1, 1, 1)
					addLbl:SetAlpha(0.5)
					addLbl:SetPoint("CENTER")
					addLbl:SetText(EllesmereUI.L("Add Specs"))
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
						local isBar = ns.IsSpecBarType(ids[1])
						local _enhAdd = false
						if p.secondary.enhanceFiveBar then
							for _, sid in ipairs(ids) do if sid == 263 then _enhAdd = true; break end end
						end
						local p2 = p.secondary
						local newEntry = {
							specIDs = ids,
							hashValues = "",
							hashWidth = 1,
							hashColorR = 1, hashColorG = 1, hashColorB = 1, hashColorA = 0.7,
							thresholdEnabled = true,
							thresholdCount = _enhAdd and 7 or (isBar and 30 or 3),
							thresholdPartialOnly = false,
							thresholdR = p2.thresholdR or 0x0c/255,
							thresholdG = p2.thresholdG or 0xd2/255,
							thresholdB = p2.thresholdB or 0x9d/255,
							thresholdA = p2.thresholdA or 1,
						}
						-- Smart default for "Threshold color below value": the only
						-- bar-type spender class resource is Hunter Focus -> start ON
						-- (warn when low); builders (Maelstrom/Insanity/Astral) start OFF.
						-- Only when the entry covers the current spec (resource readable).
						if isBar then
							local curIdx = GetSpecialization()
							local curSpecID = curIdx and C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(curIdx)
							if curSpecID then
								for _, sid in ipairs(ids) do
									if sid == curSpecID then
										local gsr = _G._ERB_GetSecondaryResource
										local info = gsr and gsr()
										if info and info.power == "FOCUS_BAR" then
											newEntry.thresholdReverse = true
										end
										break
									end
								end
							end
						end
						p.secondary.thresholdSpecs[#p.secondary.thresholdSpecs + 1] = newEntry
						_selectedIdx = #p.secondary.thresholdSpecs
						wipe(_tempSpecSel)
						if WrappedRefresh then WrappedRefresh() end
						RefreshSpecEntries()
						if RefreshDetail then RefreshDetail() end
						RefreshClass()
					end)

					curY = curY - 36
                end  -- not advSingle (spec dropdown + Add hidden in Advanced)

                -------------------------------------------------------
                --  Scrollable entry container
                -------------------------------------------------------
				curY = curY - BUTTON_H - INNERPAD
                local headerH = math.abs(curY)  -- height consumed by title+dropdown row

				-- total region, 3x inner padding, button height
				local specContainerH = totalH - (INNERPAD * 3) - BUTTON_H
				specContainer = CreateFrame("Frame", nil, backBtn)
				specContainer:SetFrameStrata("DIALOG")
				specContainer:SetFrameLevel(200)
				PP.Point(specContainer, "TOPLEFT", thrPage, "TOPLEFT", SIDE_PAD, -ROW_H)
				PP.Size(specContainer, contentHalfSize, specContainerH)

				local bg = specContainer:CreateTexture(nil, "BACKGROUND")
				bg:SetAllPoints()
				bg:SetColorTexture(0.06, 0.08, 0.10, 0.95)
				PP.CreateBorder(specContainer, 1, 1, 1, 0.15, 1, "BORDER", 7)
				-- Scrollable entry container

				local headerH = math.abs(curY)

				local scrollFrame = CreateFrame("ScrollFrame", nil, specContainer)
				scrollFrame:SetPoint("TOPLEFT", specContainer, "TOPLEFT", 1, -2)
				scrollFrame:SetPoint("TOPRIGHT", specContainer, "TOPRIGHT", -1, -2)
				scrollFrame:SetPoint("BOTTOMRIGHT", specContainer, "BOTTOMRIGHT", -1, 1)
				scrollFrame:SetFrameLevel(specContainer:GetFrameLevel() + 1)

				local scrollChild = CreateFrame("Frame", nil, scrollFrame)
				scrollChild:SetWidth(contentHalfSize)
				scrollFrame:SetScrollChild(scrollChild)

                -- Thin scrollbar track + thumb
				local scrollBar = CreateFrame("Frame", nil, specContainer)
                scrollBar:SetWidth(4)
				scrollBar:SetPoint("TOPRIGHT", specContainer, "TOPRIGHT", -3, -4)
				scrollBar:SetPoint("BOTTOMRIGHT", specContainer, "BOTTOMRIGHT", -3, 4)
				scrollBar:SetFrameLevel(specContainer:GetFrameLevel() + 10)
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

                specContainer._scrollFrame = scrollFrame
                specContainer._scrollChild = scrollChild
                specContainer._headerH = headerH
				specContainer._maxH = specContainerH

				---------------------------------------------------------------
				--  Right detail pane (config for the selected entry)
				---------------------------------------------------------------
				local detailC = CreateFrame("Frame", nil, thrPage)
				detailC:SetFrameStrata("DIALOG")
				detailC:SetFrameLevel(200)
				-- The right side has no header row, so start it at the top
				PP.Point(detailC, "TOPRIGHT", thrPage, "TOPRIGHT", -SIDE_PAD, -INNERPAD)
				PP.Size(detailC, contentHalfSize, specContainerH + (ROW_H - INNERPAD))
				local dBg = detailC:CreateTexture(nil, "BACKGROUND")
				dBg:SetAllPoints()
				dBg:SetColorTexture(0.06, 0.08, 0.10, 0.95)
				PP.CreateBorder(detailC, 1, 1, 1, 0.15, 1, "BORDER", 7)
				detailC:EnableMouse(true)

				local DPAD  = 16
				local DLVL  = detailC:GetFrameLevel() + 2
				local ROWH  = 26
				local ROWGAP = 12
				local INW   = contentHalfSize - DPAD * 2  -- inner content width
				local MEDIAF = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"

				-- Placeholder shown when nothing is selected
				local dPlaceholder = EllesmereUI.MakeFont(detailC, 13, nil, 1, 1, 1)
				dPlaceholder:SetAlpha(0.4)
				dPlaceholder:SetPoint("CENTER")
				dPlaceholder:SetText(EllesmereUI.L("Select or add an entry"))

				-- The currently-selected threshold card (live), or nil.
				local function CurEntry()
					local pp = DB(); if not pp then return nil end
					local sp = pp.secondary
					if not sp or not sp.thresholdSpecs then return nil end
					return _selectedIdx and sp.thresholdSpecs[_selectedIdx] or nil
				end

				local _allRows = {}
				-- Makes a labeled row frame and registers it for the layout pass.
				local function DRow(labelText, h)
					local rf = CreateFrame("Frame", nil, detailC)
					rf:SetFrameLevel(DLVL)
					rf._rawH = h or ROWH  -- design-space height for the layout pass
					PP.Height(rf, rf._rawH)
					if labelText then
						local lbl = EllesmereUI.MakeFont(rf, 13, nil, 1, 1, 1)
						lbl:SetAlpha(0.6)
						lbl:SetPoint("LEFT", rf, "LEFT", 0, 0)
						lbl:SetText(EllesmereUI.L(labelText))
						rf._lbl = lbl
					end
					_allRows[#_allRows + 1] = rf
					return rf
				end

				-- Small helper for the value edit boxes (hash / threshold).
				local function MakeInput(parent, w, numeric)
					local ib = CreateFrame("EditBox", nil, parent)
					PP.Size(ib, w, 22)
					ib:SetFrameLevel(parent:GetFrameLevel() + 3)
					ib:SetAutoFocus(false)
					ib:SetFont(MEDIAF, 12, "")
					ib:SetTextColor(1, 1, 1, 0.75)
					ib:SetJustifyH("CENTER")
					if numeric then ib:SetNumeric(true) end
					local ibg = ib:CreateTexture(nil, "BACKGROUND")
					ibg:SetAllPoints()
					ibg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
					EllesmereUI.MakeBorder(ib, 1, 1, 1, 0.08, PP)
					return ib
				end

				----------------------------------------------------------------
				-- Row: Talent gate (single-spec cards only)
				----------------------------------------------------------------
				local talentRow = DRow("Talent", ROWH)
				talentRow._talentValues = { _menuOpts = { searchable = true, parent = thrPage } }
				talentRow._talentOrder = {}
				local talentDD = EllesmereUI.BuildDropdownControl(
					talentRow, 170, talentRow:GetFrameLevel() + 2,
					talentRow._talentValues, talentRow._talentOrder,
					function()
						local ent = CurEntry(); if not ent then return 0 end
						return ent.talentSpellID or 0
					end,
					function(key)
						local ent = CurEntry(); if not ent then return end
						if key == 0 then
							ent.talentSpellID = nil; ent.talentName = nil
						else
							ent.talentSpellID = key
							ent.talentName = talentRow._talentValues[key]
						end
						RebuildClass()
						if talentRow._talentDD and talentRow._talentDD._refreshLabel then
							talentRow._talentDD._refreshLabel()
						end
						-- The dropdown lives in the detail pane (not inside a list
						-- frame), so rebuilding the list won't churn the open menu --
						-- refresh it to relabel + re-dim duplicate cards live.
						RefreshSpecEntries()
					end,
					function(key)
						local ent = CurEntry(); if not ent then return false end
						local pp = DB(); if not pp then return false end
						local specs = pp.secondary.thresholdSpecs; if not specs then return false end
						local wantGate = (key ~= 0) and key or nil
						for i, other in ipairs(specs) do
							if i ~= _selectedIdx then
								local og = other.talentSpellID
								local sameGate = (wantGate == nil and og == nil)
									or (wantGate ~= nil and og == wantGate)
								if sameGate and ns.SpecsConflict(ent.specIDs, other.specIDs) then
									return EllesmereUI.L("Already used by another card for this spec")
								end
							end
						end
						return false
					end
				)
				talentDD:SetHeight(22)
				talentDD:SetPoint("RIGHT", talentRow, "RIGHT", 0, 0)
				talentRow._talentDD = talentDD
				-- Keep the menu above the cog popups
				talentDD:HookScript("OnClick", function()
					local m = talentDD._ddMenu
					if m then m:SetFrameStrata("TOOLTIP") end
				end)
				talentDD:HookScript("OnHide", function()
					talentDD._invalidateMenu()
				end)
				-- Blocker: greys the picker for a spec whose class the player isn't
				-- (its talents aren't in the player's loadout). Toggled in RefreshDetail.
				local talentDis = CreateFrame("Frame", nil, talentRow)
				talentDis:SetPoint("TOPLEFT", talentDD, "TOPLEFT", 0, 0)
				talentDis:SetPoint("BOTTOMRIGHT", talentDD, "BOTTOMRIGHT", 0, 0)
				talentDis:SetFrameLevel(talentDD:GetFrameLevel() + 10)
				talentDis:EnableMouse(true)
				local talentDisTex = talentDis:CreateTexture(nil, "OVERLAY")
				talentDisTex:SetAllPoints()
				talentDisTex:SetColorTexture(0.06, 0.08, 0.10, 0.6)
				talentDis:SetScript("OnEnter", function()
					EllesmereUI.ShowWidgetTooltip(talentDis, EllesmereUI.L("Talent gating is only available while playing this spec's class"))
				end)
				talentDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
				talentDis:Hide()
				talentRow._dis = talentDis

				----------------------------------------------------------------
				-- Row: Hash values ("Hash at X" + input + hint)
				----------------------------------------------------------------
				local hashRow = DRow(nil, ROWH)
				local hashLbl = EllesmereUI.MakeFont(hashRow, 13, nil, 1, 1, 1)
				hashLbl:SetAlpha(0.6)
				hashLbl:SetPoint("LEFT", hashRow, "LEFT", 0, 0)
				hashRow._lbl2 = hashLbl
				-- Hash style cog
				local hashCog, hashCogShow = EllesmereUI.BuildCogPopup({
					title = "Hash Line Style", bgAlpha = 1, frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500,
					rows = {
						{ type = "toggle", label = "Position by percent",
						  disabled = function()
						      local ent = CurEntry(); return not (ent and ns.IsEntryBarType(ent))
						  end,
						  disabledTooltip = "Bar-type resources only (pips use stack counts)",
						  get = function() local ent = CurEntry(); return (ent and ent.hashMode == "percent") and true or false end,
						  set = function(v)
						      local ent = CurEntry(); if not ent then return end
						      ent.hashMode = v and "percent" or "value"
						      RebuildClass()
						      if RefreshDetail then RefreshDetail() end
						  end },
						{ type = "slider", label = "Hash Width", min = 1, max = 4, step = 1,
						  get = function() local ent = CurEntry(); return ent and ent.hashWidth or 1 end,
						  set = function(v) local ent = CurEntry(); if ent then ent.hashWidth = v; RebuildClass() end end },
					},
				})
				local hashCogBtn = CreateFrame("Button", nil, hashRow)
				hashCogBtn:SetSize(20, 20)
				hashCogBtn:SetPoint("RIGHT", hashRow, "RIGHT", 0, 0)
				hashCogBtn:SetFrameLevel(hashRow:GetFrameLevel() + 5)
				hashCogBtn:SetAlpha(0.5)
				local hashCogTex = hashCogBtn:CreateTexture(nil, "OVERLAY")
				hashCogTex:SetAllPoints(); hashCogTex:SetTexture(EllesmereUI.COGS_ICON)
				hashCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.8) end)
				hashCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
				hashCogBtn:SetScript("OnClick", function(self) hashCogShow(self) end)
				local hashSwatch, hashSwatchSnap = EllesmereUI.BuildColorSwatch(
					hashRow, hashRow:GetFrameLevel() + 4,
					function()
						local ent = CurEntry(); if not ent then return 1, 1, 1, 0.7 end
						return ent.hashColorR or 1, ent.hashColorG or 1, ent.hashColorB or 1, ent.hashColorA or 0.7
					end,
					function(r, g, b, a)
						local ent = CurEntry(); if not ent then return end
						ent.hashColorR, ent.hashColorG, ent.hashColorB, ent.hashColorA = r, g, b, a
						RebuildClass()
					end, true, 19)
				hashSwatch:SetPoint("RIGHT", hashCogBtn, "LEFT", -8, 0)
				hashRow._swatchSnap = hashSwatchSnap
				local hashInput = MakeInput(hashRow, 120, false)
				hashInput:SetPoint("RIGHT", hashSwatch, "LEFT", -8, 0)
				local hashHint = EllesmereUI.MakeFont(hashRow, 10, nil, 1, 1, 1)
				hashHint:SetAlpha(0.35)
				hashHint:SetPoint("RIGHT", hashInput, "LEFT", -8, 0)
				hashRow._hint = hashHint
				local function _hashCommit(self)
					if self._cancelCommit then self._cancelCommit = nil; return end
					local ent = CurEntry(); if not ent then return end
					ent.hashValues = self:GetText()
					RebuildClass()
				end
				hashInput:SetScript("OnEditFocusLost", _hashCommit)
				hashInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
				hashInput:SetScript("OnEscapePressed", function(self)
					self._cancelCommit = true
					local ent = CurEntry()
					self:SetText(ent and ent.hashValues or "")
					self:ClearFocus()
				end)
				hashRow._input = hashInput

				----------------------------------------------------------------
				-- Row: Threshold (input + swatch + enable toggle)
				----------------------------------------------------------------
				local threshRow = DRow("Threshold", ROWH)
				-- Threshold options cog: per-entry gating mirrors RefreshDetail so the
				-- moved rows (Threshold as / Direction / Only color at-above) grey correctly.
				local function _thrEnt() return CurEntry() end
				local function _thrIsBar() local e=_thrEnt(); return (e and ns.IsEntryBarType(e)) and true or false end
				local function _thrIsStagger()
					local e=_thrEnt(); if not e then return false end
					if advSingle then return ctx.specID == 268 end
					if e.specIDs then for _, sp in ipairs(e.specIDs) do if sp == 268 then return true end end end
					return false
				end
				local function _thrIsEnhance()
					local e=_thrEnt(); if not e then return false end
					local pp = DB(); if not (pp and pp.secondary.enhanceFiveBar == true) then return false end
					if advSingle then return ctx.specID == 263 end
					if e.specIDs then for _, sp in ipairs(e.specIDs) do if sp == 263 then return true end end end
					return false
				end
				local function _thrEnabled() local e=_thrEnt(); if not e then return false end local v=e.thresholdEnabled; if v==nil then v=true end return v end
				local function _thrMultiOn() local e=_thrEnt(); return (e and e.multiBandEnabled and not _thrIsEnhance()) and true or false end
				local function _thrOptUsable() return _thrEnabled() and not _thrMultiOn() end
				local function _thrOffTip() if _thrMultiOn() then return BAND_REPLACES_TIP end return "Enable the Threshold toggle to use these options." end
				local function _thrIsUpTo() local e=_thrEnt(); return (e and e.thresholdReverse) and true or false end
				local threshCog, threshCogShow = EllesmereUI.BuildCogPopup({
					title = "Threshold Options", bgAlpha = 1, frameStrata = "FULLSCREEN_DIALOG", frameLevel = 500, minWidth = 320,
					rows = {
						{ type = "segmented", label = "Threshold as",
							keys = { "percent", "value" }, labels = { percent = "Percent", value = "Value" }, rawTooltip = true,
							disabled = function() return (not _thrOptUsable()) or (not _thrIsBar()) or _thrIsStagger() end,
							disabledTooltip = function()
								if not _thrOptUsable() then return _thrOffTip() end
								if not _thrIsBar() then return "This option applies to bar-type resources only (pips use stack counts)." end
								return STAGGER_PCT_TIP
							end,
							get = function() local e=_thrEnt(); return (e and e.thresholdMode) or "percent" end,
							set = function(v) local e=_thrEnt(); if not e then return end e.thresholdMode=v; RefreshClass(); if RefreshDetail then RefreshDetail() end end },
						{ type = "segmented", label = "Direction",
							keys = { "upto", "from" }, labels = { upto = "Up to", from = "From" }, rawTooltip = true,
							disabled = function() return not _thrOptUsable() end,
							disabledTooltip = function() return _thrOffTip() end,
							get = function() local e=_thrEnt(); return (e and e.thresholdReverse) and "upto" or "from" end,
							set = function(v) local e=_thrEnt(); if not e then return end e.thresholdReverse=(v=="upto"); RefreshClass(); if RefreshDetail then RefreshDetail() end end },
						{ type = "toggle", label = "Only color at/above threshold", rawTooltip = true,
							disabled = function() return (not _thrOptUsable()) or _thrIsBar() or _thrIsUpTo() end,
							disabledTooltip = function()
								if not _thrOptUsable() then return _thrOffTip() end
								if _thrIsBar() then return "This option applies to pip-type resources only." end
								return "Only available with the 'From' direction -- it highlights the pips at/above the threshold."
							end,
							get = function() local e=_thrEnt(); return (e and e.thresholdPartialOnly) and true or false end,
							set = function(v) local e=_thrEnt(); if not e then return end e.thresholdPartialOnly=v; RefreshClass(); if RefreshDetail then RefreshDetail() end end },
					},
				})
				local threshCogBtn = CreateFrame("Button", nil, threshRow)
				threshCogBtn:SetSize(20, 20)
				threshCogBtn:SetPoint("RIGHT", threshRow, "RIGHT", 0, 0)
				threshCogBtn:SetFrameLevel(threshRow:GetFrameLevel() + 5)
				threshCogBtn:SetAlpha(0.5)
				local threshCogTex = threshCogBtn:CreateTexture(nil, "OVERLAY")
				threshCogTex:SetAllPoints(); threshCogTex:SetTexture(EllesmereUI.COGS_ICON)
				threshCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.8) end)
				threshCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
				threshCogBtn:SetScript("OnClick", function(self) threshCogShow(self) end)
				local threshEnable, _, threshEnableSnap = EllesmereUI.BuildToggleControl(
					threshRow, DLVL + 4,
					function()
						local ent = CurEntry(); if not ent then return false end
						if ent.thresholdEnabled == nil then return true end
						return ent.thresholdEnabled
					end,
					function(v)
						local ent = CurEntry(); if not ent then return end
						ent.thresholdEnabled = v
						RefreshClass()
						if RefreshDetail then RefreshDetail() end
					end,
					{ sizeRatio = 0.95 }
				)
				local threshSwatch, threshSwatchSnap = EllesmereUI.BuildColorSwatch(
					threshRow, threshRow:GetFrameLevel() + 4,
					function()
						local ent = CurEntry()
						local pp = DB()
						local base = pp and pp.secondary
						if not ent then return 0x0c/255, 0xd2/255, 0x9d/255, 1 end
						return ent.thresholdR or (base and base.thresholdR) or 0x0c/255,
							ent.thresholdG or (base and base.thresholdG) or 0xd2/255,
							ent.thresholdB or (base and base.thresholdB) or 0x9d/255,
							ent.thresholdA or (base and base.thresholdA) or 1
					end,
					function(r, g, b, a)
						local ent = CurEntry(); if not ent then return end
						ent.thresholdR, ent.thresholdG, ent.thresholdB, ent.thresholdA = r, g, b, a
						SmoothRefresh()
					end, true, 19)
				threshSwatch:SetPoint("RIGHT", threshCogBtn, "LEFT", -8, 0)
				local threshInput = MakeInput(threshRow, 50, true)
				threshInput:SetPoint("RIGHT", threshSwatch, "LEFT", -8, 0)
				threshEnable:SetPoint("RIGHT", threshInput, "LEFT", -8, 0)
				local function _threshCommit(self)
					if self._cancelCommit then self._cancelCommit = nil; return end
					local ent = CurEntry(); if not ent then return end
					local mn, mx, df = self._min or 1, self._max or 100, self._def or 3
					local val = tonumber(self:GetText())
					if not val then self:SetText(tostring(ent.thresholdCount or df)); return end
					val = math.max(mn, math.min(mx, math.floor(val + 0.5)))
					self:SetText(tostring(val))
					ent.thresholdCount = val
					RefreshClass()
				end
				threshInput:SetScript("OnEditFocusLost", _threshCommit)
				threshInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
				threshInput:SetScript("OnEscapePressed", function(self)
					self._cancelCommit = true
					local ent = CurEntry()
					self:SetText(tostring((ent and ent.thresholdCount) or self._def or 3))
					self:ClearFocus()
				end)
				threshRow._input = threshInput
				threshRow._enableSnap = threshEnableSnap
				threshRow._swatchSnap = threshSwatchSnap
				-- Greys the threshold input + swatch (label kept) while the threshold
				-- is off or replaced by multi-band
				local threshDis = CreateFrame("Frame", nil, threshRow)
				threshDis:SetPoint("TOPLEFT", threshInput, "TOPLEFT", -2, 3)
				threshDis:SetPoint("BOTTOMRIGHT", threshSwatch, "BOTTOMRIGHT", 3, -3)
				threshDis:SetFrameLevel(threshRow:GetFrameLevel() + 6)
				threshDis:EnableMouse(true)
				local threshDisTex = threshDis:CreateTexture(nil, "OVERLAY")
				threshDisTex:SetAllPoints()
				threshDisTex:SetColorTexture(0.06, 0.08, 0.10, 0.7)
				threshDis:SetScript("OnEnter", function()
					local tip = (threshRow._disTip == "MULTI") and BAND_REPLACES_TIP
						or EllesmereUI.DisabledTooltip("Threshold Color")
					EllesmereUI.ShowWidgetTooltip(threshDis, tip)
				end)
				threshDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
				threshRow._dis = threshDis

				----------------------------------------------------------------
				-- Row: Multi-band (toggle + Bands editor button)
				----------------------------------------------------------------
				local multiRow = DRow("Multi-band Coloring", ROWH)
				local bandsBtn = CreateFrame("Button", nil, multiRow)
				PP.Size(bandsBtn, 60, 22)
				bandsBtn:SetPoint("RIGHT", multiRow, "RIGHT", 0, 0)
				bandsBtn:SetFrameLevel(multiRow:GetFrameLevel() + 4)
				local bbBg = bandsBtn:CreateTexture(nil, "BACKGROUND")
				bbBg:SetAllPoints()
				bbBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
				bandsBtn._border = EllesmereUI.MakeBorder(bandsBtn, 1, 1, 1, 0.08, PP)
				local bbLbl = EllesmereUI.MakeFont(bandsBtn, 12, nil, 1, 1, 1)
				bbLbl:SetAlpha(0.8); bbLbl:SetPoint("CENTER")
				bbLbl:SetText(EllesmereUI.L("Bands"))
				bandsBtn:SetScript("OnEnter", function(self)
					bbBg:SetColorTexture(0.16, 0.16, 0.16, 0.9)
					EllesmereUI.ShowWidgetTooltip(self, BAND_HELP_TIP)
				end)
				bandsBtn:SetScript("OnLeave", function(self)
					bbBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
					EllesmereUI.HideWidgetTooltip()
				end)
				bandsBtn:SetScript("OnClick", function(self)
					local ent = CurEntry(); if not ent then return end
					local isStag
					if advSingle then isStag = (ctx.specID == 268)
					elseif ent.specIDs then
						for _, s in ipairs(ent.specIDs) do if s == 268 then isStag = true end end
					end
					ShowBandEditor({
						getBarData = function() local pp = DB(); return pp and pp.secondary end,
						refreshFn = function() RefreshClass() end,
						entryIdx = _selectedIdx, anchor = self,
						countBased = not ns.IsEntryBarType(ent),
						lockPercent = isStag, percentMax = isStag and 500 or nil,
						defR = 0x0c/255, defG = 0xd2/255, defB = 0x9d/255, defA = 1,
					})
				end)
				multiRow._bandsBtn = bandsBtn
				local multiToggle, _, multiSnap = EllesmereUI.BuildToggleControl(
					multiRow, DLVL + 4,
					function()
						local ent = CurEntry(); return ent and ent.multiBandEnabled or false
					end,
					function(v)
						local ent = CurEntry(); if not ent then return end
						ent.multiBandEnabled = v
						RefreshClass()
						if RefreshDetail then RefreshDetail() end
					end,
					{ sizeRatio = 0.95 }
				)
				multiToggle:SetPoint("RIGHT", bandsBtn, "LEFT", -10, 0)
				multiRow._toggle = multiToggle
				multiRow._snap = multiSnap
				multiToggle:HookScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, BAND_HELP_TIP) end)
				multiToggle:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

				-- Disabled overlay: covers the toggle + Bands button when multi-band
				-- can't apply (Enhance 5-bar style)
				local multiDis = CreateFrame("Frame", nil, multiRow)
				multiDis:SetPoint("TOPLEFT", multiToggle, "TOPLEFT", -3, 3)
				multiDis:SetPoint("BOTTOMRIGHT", bandsBtn, "BOTTOMRIGHT", 3, -3)
				multiDis:SetFrameLevel(multiRow:GetFrameLevel() + 8)
				multiDis:EnableMouse(true)
				local multiDisTex = multiDis:CreateTexture(nil, "OVERLAY")
				multiDisTex:SetAllPoints()
				multiDisTex:SetColorTexture(0.06, 0.08, 0.10, 0.7)
				multiDis:SetScript("OnEnter", function()
					EllesmereUI.ShowWidgetTooltip(multiDis, EllesmereUI.L("Unavailable with Enhancement 5-bar style."))
				end)
				multiDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
				multiDis:Hide()
				multiRow._dis = multiDis

				----------------------------------------------------------------
				-- Row: Buff colors (per-entry list). "Buffs" opens the editor;
				-- the toggle enables applying them. First active buff wins and
				-- overrides threshold coloring.
				----------------------------------------------------------------
				local buffRow = DRow("Buff Colors", ROWH)
				local buffsBtn = CreateFrame("Button", nil, buffRow)
				PP.Size(buffsBtn, 60, 22)
				buffsBtn:SetPoint("RIGHT", buffRow, "RIGHT", 0, 0)
				buffsBtn:SetFrameLevel(buffRow:GetFrameLevel() + 4)
				local fbBg = buffsBtn:CreateTexture(nil, "BACKGROUND"); fbBg:SetAllPoints()
				fbBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
				buffsBtn._border = EllesmereUI.MakeBorder(buffsBtn, 1, 1, 1, 0.08, PP)
				local fbLbl = EllesmereUI.MakeFont(buffsBtn, 12, nil, 1, 1, 1)
				fbLbl:SetAlpha(0.8); fbLbl:SetPoint("CENTER"); fbLbl:SetText(EllesmereUI.L("Buffs"))
				buffsBtn:SetScript("OnEnter", function(self) fbBg:SetColorTexture(0.16, 0.16, 0.16, 0.9); EllesmereUI.ShowWidgetTooltip(self, BUFF_HELP_TIP) end)
				buffsBtn:SetScript("OnLeave", function(self) fbBg:SetColorTexture(0.12, 0.12, 0.12, 0.8); EllesmereUI.HideWidgetTooltip() end)
				buffsBtn:SetScript("OnClick", function(self)
					local ent = CurEntry(); if not ent then return end
					ShowBuffEditor({
						getBarData = function() local pp = DB(); return pp and pp.secondary end,
						refreshFn = function() RefreshClass() end,
						entryIdx = _selectedIdx, anchor = self,
					})
				end)
				buffRow._buffsBtn = buffsBtn
				local buffToggle, _, buffSnap = EllesmereUI.BuildToggleControl(
					buffRow, DLVL + 4,
					function() local ent = CurEntry(); return ent and ent.buffColorEnabled or false end,
					function(v)
						local ent = CurEntry(); if not ent then return end
						ent.buffColorEnabled = v
						RefreshClass()
						if RefreshDetail then RefreshDetail() end
					end,
					{ sizeRatio = 0.95 }
				)
				buffToggle:SetPoint("RIGHT", buffsBtn, "LEFT", -10, 0)
				buffRow._toggle = buffToggle
				buffRow._snap = buffSnap
				buffToggle:HookScript("OnEnter", function(self) EllesmereUI.ShowWidgetTooltip(self, BUFF_HELP_TIP) end)
				buffToggle:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

				----------------------------------------------------------------
				-- Row: Recolor text instead of bar. Bar-wide (section-level field),
				-- not per-entry -- shown once at the bottom of the pane, and only for
				-- resources where it applies (continuous bars + Guardian Ironfur).
				----------------------------------------------------------------
				local textInsteadRow = DRow("Recolor Text Instead Of Bar", ROWH)
				local textInsteadToggle, _, textInsteadSnap = EllesmereUI.BuildToggleControl(
					textInsteadRow, DLVL + 4,
					function() local ent = CurEntry(); return ent and ent.thresholdTextInstead or false end,
					function(v) local ent = CurEntry(); if not ent then return end
						ent.thresholdTextInstead = v; RefreshClass() end,
					{ sizeRatio = 0.95 }
				)
				textInsteadToggle:SetPoint("RIGHT", textInsteadRow, "RIGHT", 0, 0)
				textInsteadRow._toggle = textInsteadToggle
				textInsteadRow._snap = textInsteadSnap
				-- Disable overlay: Vengeance soul fragments + Prot Ignore Pain bar are secret,
				-- so recoloring text can't work there (toggled per-entry in RefreshDetail).
				local TI_BLOCK_TIP = "Not available for this spec: Vengeance soul fragments and the Protection Ignore Pain bar use secret values that can't be read into a text color, so recoloring the text would have no effect."
				local textInsteadDis = CreateFrame("Frame", nil, textInsteadRow)
				textInsteadDis:SetPoint("TOPLEFT", textInsteadRow, "TOPLEFT", -2, 3)
				textInsteadDis:SetPoint("BOTTOMRIGHT", textInsteadToggle, "BOTTOMRIGHT", 3, -3)
				textInsteadDis:SetFrameLevel(textInsteadRow:GetFrameLevel() + 6)
				textInsteadDis:EnableMouse(true)
				local textInsteadDisTex = textInsteadDis:CreateTexture(nil, "OVERLAY")
				textInsteadDisTex:SetAllPoints()
				textInsteadDisTex:SetColorTexture(0.06, 0.08, 0.10, 0.7)
				textInsteadDis:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(textInsteadDis, EllesmereUI.L(TI_BLOCK_TIP)) end)
				textInsteadDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
				textInsteadDis:Hide()
				textInsteadRow._dis = textInsteadDis
				----------------------------------------------------------------
				-- Row: Stagger ceiling % (Brewmaster only). The stagger bar fills to
				-- this % of max health (lower = fills sooner); the color % thresholds
				-- still use REAL max health. Bar-wide (DB().secondary); placed only for stagger.
				----------------------------------------------------------------
				local ceilingRow = DRow("Stagger Full %", ROWH)
				local ceilingInput = MakeInput(ceilingRow, 50, true)
				ceilingInput:SetPoint("RIGHT", ceilingRow, "RIGHT", 0, 0)
				ceilingInput:SetMaxLetters(3)
				local function ceilingSnap()
					local p = DB()
					ceilingInput:SetText(tostring((p and p.secondary.staggerCeilingPercent) or 100))
				end
				local function CeilingCommit(self)
					if self._cancelCommit then self._cancelCommit = nil; return end
					local p = DB(); if not p then return end
					local v = tonumber(self:GetText())
					if v then
						v = math.max(1, math.min(500, math.floor(v + 0.5)))
						p.secondary.staggerCeilingPercent = v
						RefreshClass()
					end
					ceilingSnap()
				end
				ceilingInput:SetScript("OnEditFocusLost", CeilingCommit)
				ceilingInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
				ceilingInput:SetScript("OnEscapePressed", function(self) self._cancelCommit = true; self:ClearFocus(); ceilingSnap() end)

				----------------------------------------------------------------
				-- RefreshDetail: repaint the pane for the selected entry.
				----------------------------------------------------------------
				RefreshDetail = function()
					local ent = CurEntry()
					if not ent then
						for _, rf in ipairs(_allRows) do rf:Hide() end
						dPlaceholder:Show()
						return
					end
					dPlaceholder:Hide()

					local isBar = ns.IsEntryBarType(ent)
					local isGuardian, isIgnorePain, isVengeance
					if advSingle then
						isGuardian = (ctx.specID == 104)
						isIgnorePain = (ctx.specID == 73)
						isVengeance = (ctx.specID == 581)
					else
						if ent.specIDs then
							for _, s in ipairs(ent.specIDs) do
								if s == 104 then isGuardian = true end
								if s == 73 then isIgnorePain = true end
								if s == 581 then isVengeance = true end
							end
						end
					end
					-- "Recolor text instead" no-ops for secret resources (Vengeance soul
					-- fragments; Prot Ignore Pain bar) -- grey the toggle for those entries.
					local _tiPP = DB()
					local tiBlocked = (isVengeance or (isIgnorePain and _tiPP and _tiPP.secondary.protIgnorePainBar)) and true or false
					textInsteadRow._dis:SetShown(tiBlocked)
					if textInsteadRow._lbl then textInsteadRow._lbl:SetAlpha(tiBlocked and 0.3 or 0.6) end
					-- Brewmaster only, keyed off the SELECTED entry's spec (not the live spec),
					-- so editing another spec's entry while playing Brewmaster stays unlocked.
					local isStagger
					if advSingle then isStagger = (ctx.specID == 268)
					elseif ent.specIDs then
						for _, s in ipairs(ent.specIDs) do if s == 268 then isStagger = true end end
					end
					if isStagger and ent.thresholdMode == "value" then ent.thresholdMode = "percent" end

					-- talent gate is single-spec only
					local allowTalent
					if advSingle then
						allowTalent = true
					else
						local ids = ent.specIDs
						allowTalent = (ids and #ids == 1 and ids[1] ~= 0) and true or false
					end

					-- Refill talent options from the active loadout + the entry's
					-- saved gate (even if off-spec/off-loadout).
					if allowTalent then
						local loadoutTalents = (ns.GetLoadoutTalents()) or {}
						local vals, ord = talentRow._talentValues, talentRow._talentOrder
						wipe(ord)
						for k in pairs(vals) do if k ~= "_menuOpts" then vals[k] = nil end end
						vals[0] = EllesmereUI.L("No talent"); ord[#ord + 1] = 0
						for _, t in ipairs(loadoutTalents) do
							if vals[t.spellID] == nil then ord[#ord + 1] = t.spellID end
							vals[t.spellID] = t.name
						end
						if ent.talentSpellID and vals[ent.talentSpellID] == nil then
							vals[ent.talentSpellID] = ent.talentName
								or (C_Spell.GetSpellName and C_Spell.GetSpellName(ent.talentSpellID))
								or ("Spell " .. ent.talentSpellID)
							ord[#ord + 1] = ent.talentSpellID
						end
						if talentDD._invalidateMenu then talentDD._invalidateMenu() end
						if talentDD._refreshLabel then talentDD._refreshLabel() end
					end

					-- Hash row text
					local hashWord
					if isBar then
						hashWord = (ent.hashMode == "percent") and EllesmereUI.L("Percent") or EllesmereUI.L("Value")
					else
						hashWord = EllesmereUI.L("Stack")
					end
					hashRow._lbl2:SetText(EllesmereUI.Lf("Hash at %1$s", hashWord))
					hashRow._hint:SetText(isBar and EllesmereUI.L("(Ex: 25,50,75)") or EllesmereUI.L("(Ex: 2,4)"))
					hashRow._input:SetText(ent.hashValues or "")

					-- Threshold input bounds (Enhance five-bar minimum). Bar-type can
					-- read the threshold as % (max 100) or an absolute value (higher cap).
					local threshIsValue = isBar and not isStagger and ent.thresholdMode == "value"
					local threshMax = isStagger and 500 or (isBar and (threshIsValue and 1000 or 100) or 10)
					local entryIsEnhance = false
					local pp = DB()
					if pp and pp.secondary.enhanceFiveBar == true then
						if advSingle then
							entryIsEnhance = (ctx.specID == 263)
						elseif ent.specIDs then
							for _, s in ipairs(ent.specIDs) do
								if s == 263 then entryIsEnhance = true; break end
							end
						end
					end
					local threshMin = entryIsEnhance and 7 or 1
					local threshDef = entryIsEnhance and 7 or (isBar and 30 or 3)
					threshInput._min, threshInput._max, threshInput._def = threshMin, threshMax, threshDef
					threshInput:SetText(tostring(ent.thresholdCount or threshDef))
					if entryIsEnhance then
						threshInput:SetScript("OnEnter", function(self)
							EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Enhance 5 Bar minimum is %d (if you want less just change 5 bar color)"):format(threshMin))
						end)
						threshInput:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
					else
						threshInput:SetScript("OnEnter", nil)
						threshInput:SetScript("OnLeave", nil)
					end
					threshRow._lbl:SetText(EllesmereUI.L("Threshold") .. ((isBar and not threshIsValue) and " %" or ""))

					-- Talent gating only makes sense on your own class (talents come
					-- from your loadout) -- block the picker for other classes' specs.
					local talentClassOK = true
					if allowTalent then
						local specID = advSingle and ctx.specID or (ent.specIDs and ent.specIDs[1])
						if specID and specID ~= 0 then
							local _, _, _, _, _, classFile = GetSpecializationInfoByID(specID)
							local _, playerClass = UnitClass("player")
							talentClassOK = (classFile == playerClass)
						end
						talentRow._dis:SetShown(not talentClassOK)
					end

					-- Snap the toggles / swatches to the entry
					if talentDD._refreshLabel then talentDD._refreshLabel() end
					hashRow._swatchSnap()
					threshEnableSnap(); threshSwatchSnap(); multiSnap(); buffSnap(); textInsteadSnap(); ceilingSnap()

					-- Enable/disable + greying state. Single threshold and multi-band are independent toggles
					local entEnabled = ent.thresholdEnabled
					if entEnabled == nil then entEnabled = true end
					local multiOn = (ent.multiBandEnabled and not entryIsEnhance) and true or false
					if entryIsEnhance then
						multiToggle:SetAlpha(0.35); multiToggle:SetEnabled(false)
						bandsBtn:SetAlpha(0.35); bandsBtn:SetEnabled(false)
						if multiRow._lbl then multiRow._lbl:SetAlpha(0.3) end
						multiRow._dis:Show()
					else
						multiToggle:SetAlpha(1); multiToggle:SetEnabled(true)
						bandsBtn:SetAlpha(multiOn and 1 or 0.35); bandsBtn:SetEnabled(multiOn)
						if multiRow._lbl then multiRow._lbl:SetAlpha(0.6) end
						multiRow._dis:Hide()
					end
					if multiOn then
						threshRow._disTip = "MULTI"; threshDis:Show()
					elseif not entEnabled then
						threshRow._disTip = nil; threshDis:Show()
					else
						threshDis:Hide()
					end

					-- Layout pass: place visible rows top-to-bottom.
					for _, rf in ipairs(_allRows) do rf:Hide() end
					local yy = -DPAD
					local function place(rf)
						rf:ClearAllPoints()
						PP.Point(rf, "TOPLEFT", detailC, "TOPLEFT", DPAD, yy)
						PP.Point(rf, "TOPRIGHT", detailC, "TOPRIGHT", -DPAD, yy)
						rf:Show()
						yy = yy - (rf._rawH or ROWH) - ROWGAP
					end
					if allowTalent then place(talentRow) end
					if not isGuardian and not isIgnorePain then place(hashRow) end
					place(threshRow)
					place(multiRow)
					place(buffRow)
					-- Bar-wide text-instead toggle: always shown as a row on the right
					-- detail panel. (No visible effect for pip resources / Ignore Pain,
					-- where the render path keeps its own coloring.)
					place(textInsteadRow)
					if isStagger then place(ceilingRow) end
				end
				thrPage:Hide();
            end -- BuildFrame

			-- BuildFrame is not called here. It's built lazily on first open
			-- (ToggleFrame)

            ---------------------------------------------------------------
            --  Build/Refresh dynamic entry frames
            ---------------------------------------------------------------
            RefreshSpecEntries = function(scrollToSel)
                local p = DB(); if not p then return end
                local sp = p.secondary
                if not sp.thresholdSpecs then sp.thresholdSpecs = {} end
                local entries = sp.thresholdSpecs
                local PP = EllesmereUI.PanelPP or EllesmereUI.PP

                -- Which entry the resolver actually picks in-game right now. seeds
                -- the default selection (opens with the active entry pre-selected).
                local activeIdx
                do
                    local resolved = _G._ERB_ResolveThresholdSpecEntry and _G._ERB_ResolveThresholdSpecEntry(sp)
                    if resolved then
                        for i = 1, #entries do
                            if entries[i] == resolved then activeIdx = i; break end
                        end
                    end
                end

                -- Resolve/clamp the selection. Default to the active entry, else first.
                if #entries == 0 then
                    _selectedIdx = nil
                else
                    if _selectedIdx and _selectedIdx > #entries then _selectedIdx = #entries end
                    if not _selectedIdx or _selectedIdx < 1 then _selectedIdx = activeIdx or 1 end
                end

                local scrollChild = specContainer._scrollChild
                local curY = 0
                local ENTRY_W = contentHalfSize - 6
                local ENTRY_H = 32

                -- Paints one row's bg/accent for the current selection state.
                local function PaintRow(f)
                    local sel = (f._entryIdx ~= nil) and (_selectedIdx == f._entryIdx)
                    f._selected = sel
                    f._accent:SetShown(sel)
                    -- Recolor the accent bar to the live theme accent each paint (its
                    -- creation-time color is otherwise stale after a theme change).
                    f._accent:SetColorTexture(EG.r, EG.g, EG.b, 1)
                    if sel then
                        f._bg:SetColorTexture(EG.r, EG.g, EG.b, 0.10)
                    else
                        f._bg:SetColorTexture(1, 1, 1, 0.02)
                    end
                end

                -- hide all existing entry frames
                for i = 1, #_entryFrames do
                    if _entryFrames[i] then _entryFrames[i]:Hide() end
                end

                for idx, entry in ipairs(entries) do
                    local ef = _entryFrames[idx]
                    if not ef then
                        ef = CreateFrame("Button", nil, scrollChild)
                        ef:SetFrameLevel(thrPage:GetFrameLevel() + 2)
                        ef:RegisterForClicks("LeftButtonUp")
                        _entryFrames[idx] = ef

                        -- entry background
                        local entBg = ef:CreateTexture(nil, "BACKGROUND")
                        entBg:SetAllPoints()
                        entBg:SetColorTexture(1, 1, 1, 0.02)
                        ef._bg = entBg

                        -- selection accent (left ELLESMERE_GREEN bar)
                        local accent = ef:CreateTexture(nil, "ARTWORK")
                        accent:SetPoint("TOPLEFT", ef, "TOPLEFT", 0, 0)
                        accent:SetPoint("BOTTOMLEFT", ef, "BOTTOMLEFT", 0, 0)
                        accent:SetWidth(3)
                        accent:SetColorTexture(EG.r, EG.g, EG.b, 1)
                        accent:Hide()
                        ef._accent = accent

                        -- delete button
                        local delBtn = CreateFrame("Button", nil, ef)
                        delBtn:SetSize(14, 14)
                        delBtn:SetPoint("RIGHT", ef, "RIGHT", -8, 0)
                        delBtn:SetFrameLevel(ef:GetFrameLevel() + 3)
                        local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                        delIcon:SetAllPoints()
                        delIcon:SetTexture(CLOSE_ICON_PATH)
                        delIcon:SetAlpha(0.4)
                        delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
                        delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
                        ef._delBtn = delBtn

                        -- Add-variant button: duplicate this entry as a talent-gated
                        -- sibling for the same spec. Sits left of the delete X.
                        local varBtn = CreateFrame("Button", nil, ef)
                        PP.Size(varBtn, 84, 20)
                        varBtn:SetPoint("RIGHT", delBtn, "LEFT", -10, 0)
                        varBtn:SetFrameLevel(ef:GetFrameLevel() + 3)
                        local varBg = varBtn:CreateTexture(nil, "BACKGROUND")
                        varBg:SetAllPoints()
                        varBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                        varBtn._border = EllesmereUI.MakeBorder(varBtn, 1, 1, 1, 0.08, PP)
                        local varLbl = EllesmereUI.MakeFont(varBtn, 11, nil, 1, 1, 1)
                        varLbl:SetText(EllesmereUI.L("Add Variant"))
                        varLbl:SetAlpha(0.65)
                        varLbl:SetPoint("CENTER")
                        varBtn:SetScript("OnEnter", function(self)
                            varBg:SetColorTexture(0.16, 0.16, 0.16, 0.9)
                            varLbl:SetAlpha(0.9)
                            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Add a talent variant of this entry"))
                        end)
                        varBtn:SetScript("OnLeave", function()
                            varBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                            varLbl:SetAlpha(0.65)
                            EllesmereUI.HideWidgetTooltip()
                        end)
                        varBtn:SetScript("OnClick", function()
                            if not ef._entryIdx then return end
                            local p2 = DB(); if not p2 then return end
                            local specs = p2.secondary.thresholdSpecs
                            local src = specs and specs[ef._entryIdx]; if not src then return end
                            local copy = CopyThresholdEntry(src)
                            copy.talentSpellID = nil
                            copy.talentName = nil
                            table.insert(specs, ef._entryIdx + 1, copy)
                            _selectedIdx = ef._entryIdx + 1
                            RefreshSpecEntries()
                            if RefreshDetail then RefreshDetail() end
                            RebuildClass()
                        end)
                        ef._varBtn = varBtn

                        -- spec/talent group label (class-colored)
                        local specLbl = EllesmereUI.MakeFont(ef, 14, nil, 1, 1, 1)
                        specLbl:SetAlpha(0.85)
                        specLbl:SetPoint("LEFT", ef, "LEFT", 12, 0)
                        specLbl:SetPoint("RIGHT", varBtn, "LEFT", -8, 0)
                        specLbl:SetJustifyH("LEFT")
                        specLbl:SetWordWrap(false)
                        ef._specLbl = specLbl

                        -- Whole row selects this entry -> repaint + refresh the
                        -- right detail pane (no list rebuild, so no scroll jump).
                        ef:SetScript("OnClick", function(self)
                            if not self._entryIdx then return end
                            _selectedIdx = self._entryIdx
                            for i = 1, #_entryFrames do
                                local f = _entryFrames[i]
                                if f and f:IsShown() then PaintRow(f) end
                            end
                            if RefreshDetail then RefreshDetail() end
                        end)
                        ef:SetScript("OnEnter", function(self)
                            if not self._selected then self._bg:SetColorTexture(1, 1, 1, 0.06) end
                        end)
                        ef:SetScript("OnLeave", function(self)
                            if not self._selected then self._bg:SetColorTexture(1, 1, 1, 0.02) end
                        end)
                    end -- end entry frame creation

                    ef._entryIdx = idx
                    ef:SetSize(ENTRY_W, ENTRY_H)
                    ef:ClearAllPoints()
                    ef:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, curY)
                    ef._yOffset = -curY

                    -- spec label (Advanced: the spec is implicit, so label the card
                    -- by its talent gate -- "Default" for the base card)
                    if advSingle then
                        ef._specLbl:SetText(entry.talentName or EllesmereUI.L("Default"))
                    else
                        ef._specLbl:SetText(ns.EntryLabel(entry))
                    end
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

                    -- Talent variants are single-spec only ("All Specs"/multi-spec
                    -- cards span specs, so a talent gate is meaningless). Hide the
                    -- "Add variant" button there and strip any stale gate (legacy).
                    local _allowTalent
                    if advSingle then
                        _allowTalent = true
                    else
                        local ids = entry.specIDs
                        _allowTalent = (ids and #ids == 1 and ids[1] ~= 0) and true or false
                    end
                    if ef._varBtn then ef._varBtn:SetShown(_allowTalent) end
                    if not _allowTalent and entry.talentSpellID then
                        entry.talentSpellID = nil
                        entry.talentName = nil
                        RebuildClass()
                    end

                    -- delete button
                    ef._delBtn:SetScript("OnClick", function()
                        local p2 = DB(); if not p2 then return end
                        table.remove(p2.secondary.thresholdSpecs, idx)
                        local n = #p2.secondary.thresholdSpecs
                        if n == 0 then _selectedIdx = nil
                        elseif _selectedIdx and _selectedIdx > n then _selectedIdx = n end
                        RefreshSpecEntries()
                        if RefreshDetail then RefreshDetail() end
                        RefreshClass()
                    end)

                    -- selection highlight + shadow-dim (duplicates the resolver
                    -- can never reach are dimmed).
                    PaintRow(ef)
                    ef:SetAlpha(ns._ERB_IsThresholdCardShadowed(entries, idx) and 0.45 or 1)

                    ef:Show()
                    curY = curY - ENTRY_H - ROW_GAP
                end

                -- Empty-state add (Advanced only). In Advanced the spec-assignment
                -- chrome (dropdown + Add Specs) is hidden, so deleting the last card
                -- would otherwise strand the user. Show a single "Add Threshold"
                -- button while empty; the normal cards replace it once one exists.
                if advSingle and #entries == 0 then
                    if not _addNewBtn then
                        local b = CreateFrame("Button", nil, scrollChild)
                        PP.Size(b, contentHalfSize - 12, 30)
                        local bbg = EllesmereUI.SolidTex(b, "BACKGROUND", 0.05, 0.07, 0.09, 0.92)
                        bbg:SetAllPoints()
                        b._border = EllesmereUI.MakeBorder(b, 1, 1, 1, 0.4, PP)
                        local blbl = EllesmereUI.MakeFont(b, 12, nil, 1, 1, 1)
                        blbl:SetAlpha(0.5); blbl:SetPoint("CENTER")
                        blbl:SetText(EllesmereUI.L("Add Threshold"))
                        b:SetScript("OnEnter", function()
                            blbl:SetAlpha(0.7)
                            if b._border and b._border.SetColor then b._border:SetColor(1, 1, 1, 0.6) end
                        end)
                        b:SetScript("OnLeave", function()
                            blbl:SetAlpha(0.5)
                            if b._border and b._border.SetColor then b._border:SetColor(1, 1, 1, 0.4) end
                        end)
                        b:SetScript("OnClick", function()
                            local p2 = DB(); if not p2 then return end
                            local sp2 = p2.secondary; if not sp2 then return end
                            if not sp2.thresholdSpecs then sp2.thresholdSpecs = {} end
                            local isBar = ns.IsSpecBarType(ctx.specID)
                            sp2.thresholdSpecs[#sp2.thresholdSpecs + 1] = {
                                specIDs = { 0 },
                                hashValues = "", hashWidth = 1,
                                hashColorR = 1, hashColorG = 1, hashColorB = 1, hashColorA = 0.7,
                                thresholdEnabled = true,
                                thresholdCount = (ctx.specID == 263 and sp2.enhanceFiveBar) and 7 or (isBar and 30 or 3),
                                thresholdPartialOnly = false,
                                thresholdR = 0x0c/255, thresholdG = 0xd2/255, thresholdB = 0x9d/255, thresholdA = 1,
                            }
                            _selectedIdx = #sp2.thresholdSpecs
                            RefreshSpecEntries()
                            if RefreshDetail then RefreshDetail() end
                            RebuildClass()
                        end)
                        _addNewBtn = b
                    end
                    _addNewBtn:ClearAllPoints()
                    _addNewBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 6, -6)
                    _addNewBtn:Show()
                    curY = -(6 + 30)
                elseif _addNewBtn then
                    _addNewBtn:Hide()
                end

                -- Size the scroll child to fit all entries
                local contentH = math.abs(curY) + SIDE_PAD
                scrollChild:SetSize(contentHalfSize, math.max(1, contentH))

                -- Clamp scroll-frame height: header + content, max container height
                local headerH = specContainer._headerH or 0
                local scrollH = math.min(contentH, specContainer._maxH - headerH)
                scrollH = math.max(scrollH, SIDE_PAD)
                specContainer._scrollFrame:SetHeight(scrollH)

                -- Scroll the list to the selected row (on open / add).
                if scrollToSel and _selectedIdx and _entryFrames[_selectedIdx] then
                    local sf = specContainer._scrollFrame
                    local viewH = sf:GetHeight()
                    local range = math.max(0, contentH - viewH)
                    local target = math.max(0, math.min(range, (_entryFrames[_selectedIdx]._yOffset or 0) - 8))
                    sf:SetVerticalScroll(target)
                end
            end
			-- (No immediate populate: the frame is built + populated lazily on the
			-- first ToggleFrame open, which also calls RefreshSpecEntries.)

            ---------------------------------------------------------------
            --  Show/Hide popup
            ---------------------------------------------------------------
            local function ToggleFrame(anchor)
                -- Nothing to configure when there's no config (Advanced, no spec
                -- selected/customised) -- the disabled overlay already blocks this,
                -- but guard the open path too.
                if not DB() then return end
                if not thrPage then BuildFrame({topY = _advTop, botY = y}) end
				if thrPage:IsShown() then
					-- Unlock cycle fix to redraw correctly
					if thrPage:GetLeft() ~= nil then
						thrPage:Hide()
						return
					end
					thrPage:Hide()
				end
                wipe(_tempSpecSel)
                if _specDDRefresh then _specDDRefresh() end
                -- Re-pick the active entry (resolver) each open, then scroll to it.
                _selectedIdx = nil
                RefreshSpecEntries(true)
                if RefreshDetail then RefreshDetail() end
				if thrPage._reanchor then thrPage._reanchor() end
				thrPage:Show()
            end

            settingsBtn:SetScript("OnClick", function(self) ToggleFrame(self) end)

            -- Close popup when the settings button hides (page switch or main panel close)
            settingsBtn:HookScript("OnHide", function()
                if thrPage and thrPage:IsShown() then thrPage:Hide() end
            end)

            -- Spec/talent changes move which entry the resolver picks (the active
            -- glow) and change the available loadout talents -- refresh the open
            -- popup live. Keep the current selection (don't yank the user mid-edit).
            -- The event frame + accent callback are module-level singletons: this
            -- section builder re-runs on every options rebuild (Simple/Advanced,
            -- sync toggles, spec add/remove), so creating them per build would leak
            -- a permanently-registered frame and a permanent accent entry each
            -- time. They read the current popup through ns._thrCtx, refreshed here
            -- on every build.
            ns._thrCtx = { page = thrPage, entryFrames = _entryFrames,
                           refresh = RefreshSpecEntries, refreshDetail = RefreshDetail }
            if not ns._thrEventsFrame then
                local ev = CreateFrame("Frame")
                ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
                ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
                ev:RegisterEvent("TRAIT_CONFIG_UPDATED")
                ev:RegisterEvent("PLAYER_TALENT_UPDATE")
                ev:SetScript("OnEvent", function(_, event)
                    local c = ns._thrCtx
                    if c and c.page and c.page:IsShown() then
                        -- Threshold popup open: lightweight in-place refresh (a full
                        -- page rebuild would tear the open popup down).
                        if c.refresh then c.refresh() end
                        if c.refreshDetail then c.refreshDetail() end
                    elseif (event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED")
                           and EllesmereUI:IsShown() and EllesmereUI:GetActivePage() == PAGE_DISPLAY then
                        -- The display page (Simple/Advanced) is the open page. Redraw
						-- correctly on spec swap
                        C_Timer.After(0, function()
                            if EllesmereUI:IsShown() and EllesmereUI:GetActivePage() == PAGE_DISPLAY then
                                EllesmereUI:RefreshPage(true)
                            end
                        end)
                    end
                end)
                ns._thrEventsFrame = ev
                -- Theme/accent change: the selection highlight uses the live accent.
                EllesmereUI.RegAccent({ type = "callback", fn = function(r, g, b)
                    local c = ns._thrCtx
                    if not (c and c.page and c.page:IsShown()) then return end
                    local ef = c.entryFrames
                    for i = 1, #ef do
                        local f = ef[i]
                        if f and f:IsShown() then
                            f._accent:SetColorTexture(r, g, b, 1)
                            if f._selected then f._bg:SetColorTexture(r, g, b, 0.10) end
                        end
                    end
                end })
            end
        end
		-- class settings [end]
        -- Row: Custom Recharge Color | Simple Runes (DK), Shaman Enhance, Hunter Focus.
        -- DK rune + Shaman enhance fields are resolved per-spec at runtime, so they
        -- route through cfg(). Hunter "Focus as Power" is read globally (power-type
        -- resolution), so it stays a Simple-page (global) toggle.
        do
            local _, playerClass = UnitClass("player")
            if playerClass == "DEATHKNIGHT" then
                local simpleRuneRow
                simpleRuneRow, h = W:DualRow(parent, y,
                    { type = "toggle", text = "Custom Recharge Color",
                      tooltip = "Choose the color of recharging runes instead of a dimmed version of the rune color.",
                      disabled = classOff,
                      disabledTooltip = "Class Resource",
                      getValue = function() local c = cfg(); return c and c.runesCustomRecharge end,
                      setValue = function(v)
                          local c = cfg(); if not c then return end
                          c.runesCustomRecharge = v
                          RebuildClass()
                          EllesmereUI:RefreshPage()
                      end },
                    { type = "toggle", text = "Simple Runes",
                      tooltip = "Show rune count in center and remove recharge text/animation",
                      disabled = classOff,
                      disabledTooltip = "Class Resource",
                      getValue = function() local c = cfg(); return c and c.runesSimple end,
                      setValue = function(v)
                          local c = cfg(); if not c then return end
                          c.runesSimple = v
                          RebuildClass()
                      end }); y = y - h
                -- Inline color swatch for custom recharge color (left region)
                do
                    local rgn = simpleRuneRow._leftRegion
                    local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                        rgn, simpleRuneRow:GetFrameLevel() + 3,
                        function()
                            local c = cfg(); if not c then return 0.5, 0.5, 0.5, 1 end
                            return c.runesRechargeR or 0.5, c.runesRechargeG or 0.5, c.runesRechargeB or 0.5, c.runesRechargeA or 1
                        end,
                        function(r, g, b, a)
                            local c = cfg(); if not c then return end
                            c.runesRechargeR = r
                            c.runesRechargeG = g
                            c.runesRechargeB = b
                            c.runesRechargeA = a
                            SmoothRefresh()
                        end, true, 20)
                    swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = swatch
                    local swatchBlock = CreateFrame("Frame", nil, swatch)
                    swatchBlock:SetAllPoints()
                    swatchBlock:SetFrameLevel(swatch:GetFrameLevel() + 10)
                    swatchBlock:EnableMouse(true)
                    swatchBlock:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Custom Recharge Color"))
                    end)
                    swatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                    local function UpdateRechargeSwatch()
                        local c = cfg()
                        local off = not (c and c.enabled) or not c.runesCustomRecharge
                        if off then swatch:SetAlpha(0.3); swatchBlock:Show() else swatch:SetAlpha(1); swatchBlock:Hide() end
                    end
                    EllesmereUI.RegisterWidgetRefresh(function() if updateSwatch then updateSwatch() end; UpdateRechargeSwatch() end)
                    UpdateRechargeSwatch()
                end
            end
            if playerClass == "HUNTER" and not ctx.advanced then
                _, h = W:DualRow(parent, y,
                    { type = "toggle", text = "Show Focus as Power Bar (BM/MM)",
                      tooltip = "When enabled, BM and MM specs show Focus as the standard power bar instead of a class resource bar.",
                      getValue = function()
                          local p = DB(); if not p then return false end
                          return p.secondary.hunterFocusAsPower or false
                      end,
                      setValue = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.hunterFocusAsPower = v
                          RebuildPower(); RebuildClass()
                          EllesmereUI:RefreshPage()
                      end },
                    { type = "label", text = "" }); y = y - h
            end
            if playerClass == "SHAMAN" then
                -- Enhance 5-bar applies to Enhancement (specID 263) only. In Advanced
                -- gate on the configured spec; in Simple gate on the active spec.
                local function _enhSpecOK()
                    if ctx.advanced then return ctx.specID == 263 end
                    return GetSpecialization() == 2
                end
                local enhRow
                enhRow, h = W:DualRow(parent, y,
                    { type = "toggle", text = "Enhance 5 Bar Style",
                      disabled = function()
                          local c = cfg()
                          return not (c and c.enabled) or not _enhSpecOK()
                      end,
                      disabledTooltip = "Requires Enhancement Shaman with Class Resource enabled.", rawTooltip = true,
                      getValue = function() local c = cfg(); return c and c.enhanceFiveBar end,
                      setValue = function(v)
                          local c = cfg(); if not c then return end
                          c.enhanceFiveBar = v; RebuildClass()
                          EllesmereUI:RefreshPage()
                      end },
                    { type = "label", text = "" }); y = y - h
                -- Inline color swatch for overflow color
                do
                    local rgn = enhRow._leftRegion
                    local swatch = EllesmereUI.BuildColorSwatch(
                        rgn, enhRow:GetFrameLevel() + 3,
                        function()
                            local c = cfg(); if not c then return 1, 0.6, 0.2, 1 end
                            return c.enhanceOverflowR or 1, c.enhanceOverflowG or 0.6, c.enhanceOverflowB or 0.2, 1
                        end,
                        function(r, g, b)
                            local c = cfg(); if not c then return end
                            c.enhanceOverflowR = r
                            c.enhanceOverflowG = g
                            c.enhanceOverflowB = b
                            SmoothRefresh()
                        end, false, 20)
                    swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                    rgn._lastInline = swatch
                    local function UpdateEnhSwatchVis()
                        local c = cfg()
                        local off = not (c and c.enabled) or not c.enhanceFiveBar or not _enhSpecOK()
                        swatch:SetAlpha(off and 0.3 or 1)
                    end
                    EllesmereUI.RegisterWidgetRefresh(UpdateEnhSwatchVis)
                    UpdateEnhSwatchVis()
                end
            end
        end
        end   -- close Class Resource hidden-while-disabled gate

        -- Synced overlay (advanced + synced): cover the built content.
        if ctx.advanced and ctx.synced and _advTop then
            local EGc  = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
            local CPAD = EllesmereUI.CONTENT_PAD or 45
            local ov = CreateFrame("Button", nil, parent)
            ov:SetPoint("TOPLEFT", parent, "TOPLEFT", CPAD, _advTop)
            ov:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -CPAD, _advTop)
            ov:SetHeight(math.max(1, _advTop - y))
            ov:SetFrameLevel(parent:GetFrameLevel() + 50)
            local obg = ov:CreateTexture(nil, "BACKGROUND"); obg:SetAllPoints()
            obg:SetColorTexture(13 / 255, 17 / 255, 25 / 255, 0.96)
            local olbl = EllesmereUI.MakeFont(ov, 12, nil, 1, 1, 1); olbl:SetPoint("CENTER")
            olbl:SetTextColor(1, 1, 1, 0.56)
            olbl:SetText(EllesmereUI.L("Synced with Simple Mode") .. "   —   " .. EllesmereUI.L("click to customise"))
            ov:SetScript("OnEnter", function() olbl:SetTextColor(EGc.r, EGc.g, EGc.b, 1) end)
            ov:SetScript("OnLeave", function() olbl:SetTextColor(1, 1, 1, 0.56) end)
            ov:SetScript("OnClick", function() if ctx.onToggleSync then ctx.onToggleSync() end end)
            ns.ERB_OverlayHealOnShow(ov, obg, olbl)
        end

        -- Simple page: if the current spec overrides the Class Resource in
        -- Advanced, cover these controls so edits here aren't silently ignored.
        if not ctx.advanced then ns.ERB_SimpleOverrideOverlay(parent, _advTop, y, "secondary") end

        -- Return the header + row frames so the Simple page can wire its
        -- preview click-mappings (classSection/classEnableRow, and the
        -- Resource Text row for the count-text overlay).
        return y, hdr, classEnableRow, classColorRow
    end
--- [class resource end]
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

        -- Populate click mappings for preview hit overlays. _clickMappings is
        -- ONE module-shared table read by the LIVE preview header's clicks --
        -- a hidden search pre-build of this page must not wipe it out from
        -- under whichever ERB page the player is actually viewing.
        if not EllesmereUI._prebuilding then
            wipe(_clickMappings)
        end

        -- The Simple | Advanced sub-menu was retired: per-spec editing now
        -- lives in the shared Spec Overrides system (spec groups + editing-as).
        -- Legacy Advanced data migrates via MigrateRBAdvancedProfile.

        -----------------------------------------------------------------------
        --  BAR DISPLAY
        -----------------------------------------------------------------------
        local generalSection
        generalSection, h = W:SectionHeader(parent, "BAR DISPLAY", y);  y = y - h

        -- Row 1: Visibility | Visibility Options (checkbox dropdown)
        -- One control drives all three bars: the scalar and the multi-select
        -- set are written to health/primary/secondary in lockstep; reads come
        -- from secondary (the representative table).
        local function ApplyVisScalarAll(_, mode)
            local p = DB(); if not p then return end
            p.secondary.visibility = mode
            p.health.visibility = mode
            p.primary.visibility = mode
        end
        local function MirrorVisModes()
            local p = DB(); if not p then return end
            local src = p.secondary.visibilityModes
            if src then
                local c1, c2 = {}, {}
                for k in pairs(src) do c1[k] = true; c2[k] = true end
                p.health.visibilityModes = c1
                p.primary.visibilityModes = c2
            else
                p.health.visibilityModes = nil
                p.primary.visibilityModes = nil
            end
        end
        local visRow
        visRow, h = EllesmereUI.BuildVisibilityModeRow(W, parent, y,
            { getStore = function() local p = DB(); return p and p.secondary end,
              legacyKey = "visibility",
              caps = { partyIncludesRaid = true, luaDragonriding = true },
              applyScalarFn = ApplyVisScalarAll,
              onChanged = function()
                  MirrorVisModes()
                  Refresh()
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
            local visItems = EllesmereUI.VIS_OPT_ITEMS_RESOURCE_BARS
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

        -- Row 2: Dark Mode Class Resource | Background Color
        -- Dark mode applies ONLY to the class resource bar (secondary). It uses the
        -- same flat dark fill/bg as Unit Frames / Raid Frames. secondary.darkTheme is
        -- the single source of truth; health/primary are never darkened.
        -- The Background colour is shared by Health & Power (and, when Dark Mode is
        -- off, the class resource bar). While Dark Mode is on the class resource bar
        -- stays dark, so the label calls out that only Health & Power are affected.
        local bgLabel = "Background"
        do
            local p0 = DB()
            if p0 and p0.secondary.darkTheme then bgLabel = "Background (Health & Power)" end
        end
        local bgRow
        bgRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Dark Mode Class Resource",
              getValue = function()
                  local p = DB(); if not p then return false end
                  return p.secondary.darkTheme
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.darkTheme = v
                  RebuildClass()
                  -- Force a full rebuild so the Background label re-renders.
                  EllesmereUI:RefreshPage(true)
              end },
            { type = "slider", text = bgLabel, min = 0, max = 100, step = 1,
              getValue = function()
                  local p = DB(); return math.floor(((p and p.health.bgA or 0.75) * 100) + 0.5)
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  local a = v / 100
                  p.health.bgA = a
                  p.primary.bgA = a
                  p.secondary.barBgA = a
                  SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        -- Inline color swatch on Background (right region). Opacity lives in
        -- the slider (a view over the same bgA keys the old picker wrote), so
        -- the swatch is color-only.
        do
            local rgn = bgRow._rightRegion
            local ctrl = rgn._control
            local bgSwatch, bgUpdateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, bgRow:GetFrameLevel() + 3,
                function()
                    local p = DB()
                    return (p and p.health.bgR or 0x11/255), (p and p.health.bgG or 0x11/255),
                           (p and p.health.bgB or 0x11/255)
                end,
                function(r, g, b)
                    local p = DB(); if not p then return end
                    p.health.bgR, p.health.bgG, p.health.bgB = r, g, b
                    p.primary.bgR, p.primary.bgG, p.primary.bgB = r, g, b
                    p.secondary.barBgR, p.secondary.barBgG, p.secondary.barBgB = r, g, b
                    SmoothRefresh()
                    EllesmereUI:RefreshPage()
                end,
                nil, 20)
            PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(bgUpdateSwatch)
        end

        -- Row 3: Texture | Frame Strata
        local strataValues = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High", DIALOG = "Dialog" }
        local strataOrder = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }
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
            { type = "dropdown", text = "Frame Strata",
              tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
              values = strataValues, order = strataOrder,
              getValue = function()
                  local p = DB(); return p and p.general.frameStrata or "MEDIUM"
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.general.frameStrata = v; SmoothRefresh()
              end }
        );  y = y - h

        -- Row 4: Shift Elements if No Resource | Expand Power Bar if No Resource
        local shiftResRow
        shiftResRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Shift Elements if No Resource",
              tooltip = "Shifts any elements anchored to the class resource bar up or down to offset the missing class resource.",
              -- Mutually exclusive with "Expand Power Bar if No Resource": grey this
              -- while expand is on, but only when it is itself OFF (== "None") so a
              -- legacy profile that has both on can still turn this off (no deadlock).
              -- NOTE: independent of "Show Class Resource" -- the shift setting is
              -- exactly what's wanted while the resource bar is hidden, so toggling
              -- it must NOT change this control's disabled state.
              disabled = function()
                  local p = DB(); if not p then return false end
                  -- Expand only blocks shift when it is EFFECTIVELY on (power bar
                  -- enabled and not height-matched -- otherwise expand shows/acts off).
                  local heightMatched = EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power")
                  local expandOn = p.primary.enabled and p.primary.expandIfNoResource and not heightMatched
                  local shiftOff = (p.secondary.shiftElementsIfNoResource or "None") == "None"
                  return expandOn and shiftOff and true or false
              end,
              disabledTooltip = "This option can't be used while Expand Power Bar if No Resource is enabled.",
              values = { None = "None", Up = "Up", Down = "Down" },
              order = { "None", "Up", "Down" },
              getValue = function() local p = DB(); return (p and p.secondary.shiftElementsIfNoResource) or "None" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.shiftElementsIfNoResource = v
                  -- Enabling shift turns off the mutually-exclusive expand option.
                  if v ~= "None" then p.primary.expandIfNoResource = false end
                  RebuildClass()
                  EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Expand Power Bar if No Resource",
              tooltip = "When the class resource bar is not shown, this automatically adds the class resource height to the power bar.",
              -- Mutually exclusive with "Shift Elements if No Resource": grey this
              -- while shift is set, but only when it is itself OFF so a legacy profile
              -- that has both on can still turn this off (no deadlock).
              disabled = function()
                  local p = DB(); if not p then return false end
                  if not p.primary.enabled then return true end
                  -- Disabled when height matched
                  if EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power") then return true end
                  -- Shift blocks expand when the dropdown is set to Up/Down. This is
                  -- independent of "Show Class Resource" -- toggling the resource bar
                  -- must NOT change this control's disabled state.
                  local shiftOn = (p.secondary.shiftElementsIfNoResource or "None") ~= "None"
                  return shiftOn and not p.primary.expandIfNoResource and true or false
              end,
              disabledTooltip = function()
                  local p = DB()
                  if p and not p.primary.enabled then return "Power Bar" end
                  if EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power") then
                      return "This option can't be used while you have the Power Bar Height Matched in the Unlock Mode."
                  end
                  return "This option can't be used while Shift Elements if No Resource is enabled."
              end,
              getValue = function()
                  -- Force off when height matched
                  if EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power") then
                      return false
                  end
                  local p = DB(); return p and p.primary.expandIfNoResource
              end,
              setValue = function(v)
                  -- Block enable when height matched
                  if v and EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power") then
                      return
                  end
                  local p = DB(); if not p then return end
                  p.primary.expandIfNoResource = v
                  -- Enabling expand turns off the mutually-exclusive shift option.
                  if v then p.secondary.shiftElementsIfNoResource = "None" end
                  Refresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        -- Inline reposition cog on "Shift Elements if No Resource": Extra Y Offset
        do
            local rgn = shiftResRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Shift Offset",
                rows = {
                    { type = "slider", label = "Extra Y Offset", min = -50, max = 50, step = 1,
                      get = function() local p = DB(); return (p and p.secondary.shiftElementsIfNoResourceExtraY) or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.shiftElementsIfNoResourceExtraY = v
                          RebuildClass()
                      end },
                },
            })
            MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
        end

        -- Row 5: Shift Elements if No Power | (blank)
        local shiftPowRow
        shiftPowRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Shift Elements if No Power",
              tooltip = "Shifts any elements anchored to the power bar up or down to offset the missing power bar. Applies both when the Power Bar is disabled and for specs that have no power (for example, Beast Mastery and Marksmanship Hunters, whose Focus shows as the class resource bar).",
              -- Intentionally NOT disabled when the Power Bar is off: this setting
              -- is meant to fire precisely when the bar is disabled, so it must
              -- stay configurable in that state.
              values = { None = "None", Up = "Up", Down = "Down" },
              order = { "None", "Up", "Down" },
              getValue = function() local p = DB(); return (p and p.primary.shiftElementsIfNoPower) or "None" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.shiftElementsIfNoPower = v
                  RebuildPower()
                  EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Smooth Bars",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end }
        );  y = y - h
        -- Inline reposition cog on "Shift Elements if No Power": Extra Y Offset
        do
            local rgn = shiftPowRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Shift Offset",
                rows = {
                    { type = "slider", label = "Extra Y Offset", min = -50, max = 50, step = 1,
                      get = function() local p = DB(); return (p and p.primary.shiftElementsIfNoPowerExtraY) or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.primary.shiftElementsIfNoPowerExtraY = v
                          RebuildPower()
                      end },
                },
            })
            MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
        end

        -- Replace the dummy "Smooth Bars" right dropdown with a checkbox dropdown.
        -- Each item enables native StatusBar interpolation on its bar; off = a
        -- plain SetValue with zero added cost. Defaults all off.
        do
            local rightRgn = shiftPowRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local smoothItems = {
                { key = "secondary", label = "Class Resource Bar" },
                { key = "primary",   label = "Power Bar" },
                { key = "health",    label = "Health Bar" },
            }
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                smoothItems,
                function(k)
                    local p = DB(); if not p then return false end
                    return (p[k] and p[k].smoothBars) or false
                end,
                function(k, v)
                    local p = DB(); if not p then return end
                    if p[k] then p[k].smoothBars = v end
                    if _G._ERB_ApplySmoothing then _G._ERB_ApplySmoothing() end
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        _, h = W:Spacer(parent, y, 16);  y = y - h

        -----------------------------------------------------------------------
        --  CLASS RESOURCE BAR  (header + Row 1 etc. now via the shared builder)
        -----------------------------------------------------------------------
        local classSection, classEnableRow, classResourceTextRow
        y, classSection, classEnableRow, classResourceTextRow = ns.ERB_BuildClassResourceSection(parent, y, {
            cfg = function() return DB().secondary end, advanced = false, syncRows = _syncRows,
        })

        -- Row: Anchor to Cursor | Cursor Position (cog: X + Y). Appended
        -- outside the shared section builder, so it carries its own
        -- hidden-while-disabled gate (the builder's toggle rebuilds on flips).
        if DB().secondary.enabled then
            local _, cursorH = EllesmereUI.BuildCursorAnchorRow({
                W = W, parent = parent, y = y,
                getData = function() local p = DB(); return p and p.secondary or {} end,
                onApply = function() RebuildClass(); SmoothRefresh() end,
                makeCogBtn = MakeCogBtn,
            })
            y = y - cursorH
        end

        _, h = W:Spacer(parent, y, 16);  y = y - h

        -----------------------------------------------------------------------
        --  POWER BAR  (section header + Row 1 now via the shared builder)
        -----------------------------------------------------------------------
        y = ns.ERB_BuildPowerSection(parent, y, {
            cfg = function() return DB().primary end, advanced = false, syncRows = _syncRows,
        })

        -- Row: Anchor to Cursor | Cursor Position (cog: X + Y). Appended
        -- outside the shared section builder, so it carries its own
        -- hidden-while-disabled gate (the builder's toggle rebuilds on flips).
        if DB().primary.enabled then
            local _, cursorH = EllesmereUI.BuildCursorAnchorRow({
                W = W, parent = parent, y = y,
                getData = function() local p = DB(); return p and p.primary or {} end,
                onApply = function() RebuildPower(); SmoothRefresh() end,
                makeCogBtn = MakeCogBtn,
            })
            y = y - cursorH
        end

        -- Row 7: Power Type override (spec-dependent, like UF Power Type
        -- dropdown). Hidden with the rest of the Power section while the bar
        -- is off.
        if DB().primary.enabled then
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
        --  HEALTH BAR  (section header + Row 1 now via the shared builder)
        -----------------------------------------------------------------------
        y = ns.ERB_BuildHealthSection(parent, y, {
            cfg = function() return DB().health end, advanced = false, syncRows = _syncRows,
        })

        -- Row: Anchor to Cursor | Cursor Position (cog: X + Y). Appended
        -- outside the shared section builder, so it carries its own
        -- hidden-while-disabled gate (the builder's toggle rebuilds on flips).
        if DB().health.enabled then
            local _, cursorH = EllesmereUI.BuildCursorAnchorRow({
                W = W, parent = parent, y = y,
                getData = function() local p = DB(); return p and p.health or {} end,
                onApply = function() RebuildHealth(); SmoothRefresh() end,
                makeCogBtn = MakeCogBtn,
            })
            y = y - cursorH
        end

        _, h = W:Spacer(parent, y, 16);  y = y - h

        -- Wire up click mappings for preview hit overlays (never from a
        -- hidden pre-build: the shared live table would end up pointing at
        -- off-screen rows).
        if not EllesmereUI._prebuilding then
            _clickMappings.classResource = { section = classSection, target = classEnableRow }
            -- The Resource Text row lives inside the shared class-resource
            -- section builder, so it must be returned from there -- naming a
            -- local from that scope here silently resolves to nil and the
            -- count-text click does nothing.
            _clickMappings.countText = { section = classSection, target = classResourceTextRow, slotSide = "left" }
        end

		-- local thresholdPage = CreateFrame("Frame", nil, root)
        -- thresholdPage:SetAllPoints(root)
        -- thresholdPage:SetFrameLevel(root:GetFrameLevel())
        -- thresholdPage:Hide()

        return math.abs(y)
    end

	----------------------------------------
	--- end of bar display
	----------------------------------------

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
                p.gcdBar.unlockPos = nil; p.gcdBar.anchorX = 0; p.gcdBar.anchorY = -78
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

        -- Container size: icon (hxh) + bar (only when icon shown)
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
        -- Bar frame (sits beside the icon; iconOnRight puts the icon on the right)
        local iconOnRight = hasIcon and cb.iconOnRight
        pf.barFrame:SetSize(w, h)
        pf.barFrame:ClearAllPoints()
        pf.barFrame:SetPoint("LEFT", pf.container, "LEFT", iconOnRight and 0 or iconW, 0)

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
            pf.container._border:SetFrameLevel(cb.borderBehind and math.max(0, pf.container:GetFrameLevel() - 1) or (pf.container:GetFrameLevel() + 5))
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
        local fillOp = (cb.fillOpacity or 100) / 100
        if cb.gradientEnabled then
            local dir = cb.gradientDir or "HORIZONTAL"
            fillTex:SetGradient(dir, CreateColor(fR, fG, fB, fA * fillOp), CreateColor(cb.gradientR, cb.gradientG, cb.gradientB, cb.gradientA * fillOp))
        else
            fillTex:SetVertexColor(fR, fG, fB, fA * fillOp)
        end
        -- Mirror the live bar's Fill Opacity bg behavior: below 100 the bg
        -- covers only the empty portion so the translucent fill shows what is
        -- behind the bar; at 100 it spans the whole bar frame.
        if texKey ~= "blizzard" then
            pf.bg:ClearAllPoints()
            if (cb.fillOpacity or 100) < 100 then
                pf.bg:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
                pf.bg:SetPoint("BOTTOMRIGHT", pf.barFrame, "BOTTOMRIGHT", 0, 0)
            else
                pf.bg:SetAllPoints(pf.barFrame)
            end
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

        -- Icon: left or right side of container, full size
        do
            local iSize = Snap(h)
            pf.iconFrame:SetSize(iSize, iSize)
            pf.iconFrame:ClearAllPoints()
            if iconOnRight then
                pf.iconFrame:SetPoint("TOPRIGHT", pf.container, "TOPRIGHT", 0, 0)
            else
                pf.iconFrame:SetPoint("TOPLEFT", pf.container, "TOPLEFT", 0, 0)
            end
            if hasIcon then pf.iconFrame:Show() else pf.iconFrame:Hide() end
        end

        -- Cast text side-aware layout (mirrors the live cast bar)
        local cbTimerW   = (cb.timerSize or 11) * 2.2
        local cbDurSide   = cb.timerSide or "right"
        local cbSpellSide = cb.spellTextSide or "left"
        local cbBarW = pf.bar:GetWidth() or 0
        -- Timer / duration text
        if cb.showTimer then
            SetPVFont(pf.timerText, FONT_PATH, cb.timerSize or 11)
            local pt, xb, jh = ns.GetCastTextAnchor(cbDurSide, false, cbTimerW)
            pf.timerText:ClearAllPoints()
            pf.timerText:SetJustifyH(jh)
            pf.timerText:SetPoint(pt, pf.bar, pt, xb + (cb.timerX or 0), cb.timerY or 0)
            -- Preview total cast time is 3.0s; mirror the live "elapsed / total" mode.
            if cb.showTotalDuration then
                pf.timerText:SetText(string.format("%.1f / %.1f", 3.0 * _castBarPreviewFill, 3.0))
            else
                pf.timerText:SetText(string.format("%.1f", 3.0 * (1 - _castBarPreviewFill)))
            end
            pf.timerText:Show()
        else
            pf.timerText:Hide()
        end

        -- Spell name text
        if cb.showSpellText then
            SetPVFont(pf.spellText, FONT_PATH, cb.spellTextSize or 11)
            local pt, xb, jh = ns.GetCastTextAnchor(cbSpellSide, cb.showTimer and cbDurSide == cbSpellSide, cbTimerW)
            pf.spellText:ClearAllPoints()
            pf.spellText:SetJustifyH(jh)
            pf.spellText:SetPoint(pt, pf.bar, pt, xb + (cb.spellTextX or 0), cb.spellTextY or 0)
            if cbSpellSide == "center" then
                pf.spellText:SetWidth(cbBarW * 0.6)
            elseif cbBarW > 0 then
                pf.spellText:SetWidth(cbBarW - 8 - (cb.showTimer and cbTimerW or 0))
            end
            pf.spellText:SetText(EllesmereUI.L("Spell Name"))
            pf.spellText:Show()
        else
            pf.spellText:Hide()
        end
        -- Re-flow so a live JustifyH change takes effect on already-rendered text.
        ns.ReflowFontString(pf.timerText)
        ns.ReflowFontString(pf.spellText)

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
            if cb.showTotalDuration then
                timerText:SetText(string.format("%.1f / %.1f", 3.0 * _castBarPreviewFill, 3.0))
            else
                timerText:SetText(string.format("%.1f", 3.0 * (1 - _castBarPreviewFill)))
            end
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
            spellText:SetText(EllesmereUI.L("Spell Name"))
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
                _previewHintFS:SetText(EllesmereUI.L("Click elements to scroll to and highlight their options"))
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

        -- Wipe click mappings (shared with display page; never from a hidden
        -- pre-build -- see the matching guard in BuildBarDisplayPage)
        if not EllesmereUI._prebuilding then
            wipe(_clickMappings)
        end

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

        -- Strata dropdown values for the Cast Bar Frame Strata control.
        local cbStrataValues = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High", DIALOG = "Dialog" }
        local cbStrataOrder = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }

        -- Row 1: Enable Player Cast Bar | Frame Strata
        local castEnableRow
        castEnableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.enabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.enabled = v; RefreshCast()
                  EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Frame Strata",
              tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
              disabled = castOff,
              disabledTooltip = "Player Cast Bar",
              values = cbStrataValues, order = cbStrataOrder,
              getValue = function()
                  local p = DB(); return p and p.castBar.frameStrata or "MEDIUM"
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.frameStrata = v; RefreshCast()
              end }
        );  y = y - h
        -- (No position cog here: the cast bar is positioned via Unlock Mode;
        -- the old X/Y offset cog wrote anchor keys the runtime never reads.)

        -- Row 2: Height | Width (sync icons push to power + health bars)
        local classSizeRow
        local cbhDis, cbhTip, cbhRaw = EllesmereUI.MatchGuard("ERB_CastBar", "Height", castOff, "Player Cast Bar")
        local cbwDis, cbwTip, cbwRaw = EllesmereUI.MatchGuard("ERB_CastBar", "Width", castOff, "Player Cast Bar")
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
              min = 50, max = 800, step = 1,
              disabled = cbwDis, disabledTooltip = cbwTip, rawTooltip = cbwRaw,
              getValue = function() local p = DB(); return p and p.castBar.width or 220 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.width = v; RefreshCast()
              end }
        );  y = y - h

        -- Row 3: Show Spell Icon (cog: Icon on Right) | Show Spark
        local iconRow
        iconRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Spell Icon",
              disabled = castOff,
              disabledTooltip = "Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.showIcon ~= false end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showIcon = v; RefreshCast()
                  EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Show Spark",
              disabled = castOff,
              disabledTooltip = "Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.showSpark end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showSpark = v; RefreshCast()
              end }
        );  y = y - h
        -- Inline cog on Show Spell Icon: Icon on Right
        do
            local rgn = iconRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Spell Icon Settings",
                rows = {
                    { type = "toggle", label = "Icon on Right",
                      tooltip = "Attach the spell icon to the right of the cast bar instead of the left.",
                      get = function() local p = DB(); return p and p.castBar.iconOnRight end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.iconOnRight = v; RefreshCast()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                local p = DB()
                local req = (p and not p.castBar.enabled) and "Player Cast Bar" or "Show Spell Icon"
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip(req))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisIcon()
                local p = DB()
                if p and (not p.castBar.enabled or p.castBar.showIcon == false) then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisIcon)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisIcon)
            UpdateCogDisIcon()
        end

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
                  disabledTooltip = "Player Cast Bar",
                  values=texValues, order=texOrder,
                  getValue=function() local p = DB(); return p and p.castBar.borderTexture or "solid" end,
                  setValue=function(v)
                      local p = DB(); if not p then return end
                      p.castBar.borderTexture = v; p.castBar.borderTextureOffset = nil; p.castBar.borderTextureOffsetY = nil; p.castBar.borderTextureShiftX = nil; p.castBar.borderTextureShiftY = nil
                      local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      p.castBar.borderR = _bcol.r; p.castBar.borderG = _bcol.g; p.castBar.borderB = _bcol.b; p.castBar.borderA = 1
                      p.castBar.borderBehind = _bbehind
                      local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                      if defSz then p.castBar.borderSize = defSz end
                      RefreshCast(); EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Border Size",
                  min = 0, max = 4, step = 1,
                  disabled = castOff,
                  disabledTooltip = "Player Cast Bar",
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
                    EllesmereUI.ShowWidgetTooltip(borderSwatch, EllesmereUI.DisabledTooltip("This option requires a Border Size above 0."))
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
                        { type = "toggle", label = "Show Behind",
                          get = function() local p = DB(); return p and p.castBar.borderBehind or false end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.castBar.borderBehind = v == false and nil or v; RefreshCast(); EllesmereUI:RefreshPage()
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

        -- Row 2: Color (multiSwatch + cog: gradient) | (empty)
        local castColorRow
        castColorRow, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Color",
              disabled = castOff,
              disabledTooltip = "Player Cast Bar",
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
              } },
            { type = "slider", text = "Background", min = 0, max = 100, step = 1,
              disabled = castOff,
              disabledTooltip = "Player Cast Bar",
              getValue = function()
                  local p = DB(); return math.floor(((p and p.castBar.bgA or 0.7) * 100) + 0.5)
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.bgA = v / 100; RefreshCast()
              end }
        );  y = y - h
        -- Inline cog on Color for gradient settings
        do
            local rgn = castColorRow._leftRegion
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
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Player Cast Bar"))
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
            local swatch = castColorRow._leftRegion._control
            local function UpdateGradientSwatch()
                local p = DB()
                if not p or not p.castBar.enabled then
                    swatch:SetAlpha(0.15); swatch:Disable()
                    swatch._disabledTooltip = "Player Cast Bar"
                elseif not p.castBar.gradientEnabled then
                    swatch:SetAlpha(0.15); swatch:Disable()
                    swatch._disabledTooltip = "Gradient"
                else
                    swatch:SetAlpha(1); swatch:Enable()
                    swatch._disabledTooltip = nil
                end
            end
            UpdateGradientSwatch()
            EllesmereUI.RegisterWidgetRefresh(UpdateGradientSwatch)
        end
        -- Inline color swatch on Background (right region)
        do
            local rgn = castColorRow._rightRegion
            local ctrl = rgn._control
            local bgSwatch, bgUpdateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, castColorRow:GetFrameLevel() + 3,
                function()
                    local p = DB()
                    return (p and p.castBar.bgR or 0), (p and p.castBar.bgG or 0), (p and p.castBar.bgB or 0)
                end,
                function(r, g, b)
                    local p = DB(); if not p then return end
                    p.castBar.bgR, p.castBar.bgG, p.castBar.bgB = r, g, b
                    RefreshCast()
                end,
                nil, 20)
            PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local function UpdateBgSwatch()
                local p = DB()
                if not p or not p.castBar.enabled then
                    bgSwatch:SetAlpha(0.15); bgSwatch:Disable()
                    bgSwatch._disabledTooltip = "Player Cast Bar"
                else
                    bgSwatch:SetAlpha(1); bgSwatch:Enable()
                    bgSwatch._disabledTooltip = nil
                end
                bgUpdateSwatch()
            end
            UpdateBgSwatch()
            EllesmereUI.RegisterWidgetRefresh(UpdateBgSwatch)
        end

        -- Row 3: Bar Texture | Spell Text (cog RESIZE: text size + x/y)
        local textRow
        textRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Bar Texture",
              disabled = castOff,
              disabledTooltip = "Player Cast Bar",
              values = texValues, order = texOrder,
              getValue = function() local p = DB(); return p and p.castBar.texture or "none" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.texture = v; RefreshCast()
              end },
            { type = "dropdown", text = "Spell Text",
              disabled = castOff,
              disabledTooltip = "Player Cast Bar",
              values = { none = "None", left = "Left", right = "Right", center = "Center" },
              order = { "none", "left", "right", "center" },
              getValue = function()
                  local p = DB(); if not p or not p.castBar.showSpellText then return "none" end
                  return p.castBar.spellTextSide or "left"
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  if v == "none" then
                      p.castBar.showSpellText = false
                  else
                      p.castBar.showSpellText = true
                      p.castBar.spellTextSide = v
                  end
                  RefreshCast(); EllesmereUI:RefreshPage()
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
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Player Cast Bar"))
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
            { type = "dropdown", text = "Duration Text",
              disabled = castOff,
              disabledTooltip = "Player Cast Bar",
              values = { none = "None", right = "Right", left = "Left" },
              order = { "none", "right", "left" },
              getValue = function()
                  local p = DB(); if not p or not p.castBar.showTimer then return "none" end
                  return p.castBar.timerSide or "right"
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  if v == "none" then
                      p.castBar.showTimer = false
                  else
                      p.castBar.showTimer = true
                      p.castBar.timerSide = v
                  end
                  RefreshCast(); EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Show Total Duration",
              tooltip = "Shows elapsed / total duration (e.g. 0.4 / 2.0) instead of counting down from the total.",
              disabled = function()
                  local p = DB()
                  return castOff() or not (p and p.castBar.showTimer)
              end,
              disabledTooltip = "Duration Text",
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
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Player Cast Bar"))
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

        -- Row 5: Fill Opacity | (empty)
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Fill Opacity", min = 0, max = 100, step = 1,
              tooltip = "Opacity of the bar fill; below 100 the world shows through the fill instead of the background.",
              disabled = castOff,
              disabledTooltip = "Player Cast Bar",
              getValue = function() local p = DB(); return p and (p.castBar.fillOpacity or 100) or 100 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.fillOpacity = v; RefreshCast()
              end },
            { type = "label", text = "" }
        );  y = y - h

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
              disabledTooltip = "Player Cast Bar",
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
              tooltip = "Shows tick marks on channeled spells. Only supported spells are shown, request missing spells on Discord.",
              disabled = marksOff,
              disabledTooltip = "Tick Markers",
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
            "Channel Ticks"
        )

        -- Marks Row 2: Last Tick (+ color) | Colored Empowered Stages
        local marksRow2
        marksRow2, h = W:DualRow(parent, y,
            { type = "toggle", text = "Last Tick",
              tooltip = "Highlights the final damage tick. Requires a supported channeled spell.",
              disabled = marksOff,
              disabledTooltip = "Tick Markers",
              getValue = function() local p = DB(); return p and p.castBar.showLastTick end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showLastTick = v; RefreshCast()
                  EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Colored Empowered Stages",
              tooltip = "Changes the cast bar color based on the current empower stage. Colors transition from red (stage 1) through yellow to green (max stage).",
              disabled = castOff,
              disabledTooltip = "Player Cast Bar",
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
            "Last Tick"
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
              disabledTooltip = "Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.latencyEnabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.latencyEnabled = v; RefreshCast()
                  EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Show Latency Text",
              tooltip = "Appends your latency in milliseconds to the cast timer, e.g. 1.8 (42ms).",
              disabled = latOff,
              disabledTooltip = "Latency Overlay",
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
            "Latency Overlay"
        )

        -- Wire up click mappings for cast bar preview hit overlays (never
        -- from a hidden pre-build: the shared live table would end up
        -- pointing at off-screen rows).
        if not EllesmereUI._prebuilding then
            _clickMappings.castBar       = { section = castSection, target = classSizeRow }
            _clickMappings.castIcon      = { section = castSection, target = castEnableRow, slotSide = "right" }
            _clickMappings.castSpellText = { section = displaySection, target = textRow, slotSide = "left" }
            _clickMappings.castTimer     = { section = displaySection, target = textRow, slotSide = "right" }
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Totem Bar options page
    ---------------------------------------------------------------------------
    local function BuildTotemBarPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        parent._showRowDivider = true

        -- No custom preview header for totem bar
        EllesmereUI:HideContentHeader()

        -- Shared live table; never wiped from a hidden pre-build (see the
        -- matching guard in BuildBarDisplayPage).
        if not EllesmereUI._prebuilding then
            wipe(_clickMappings)
        end

        local function RefreshTotem()
            if _G._ERB_Apply then _G._ERB_Apply() end
            if EllesmereUI.NotifyElementResized then
                EllesmereUI.NotifyElementResized("ERB_TotemBar")
            end
        end

        local totemOff = function()
            local p = DB()
            return p and not p.totemBar.enabledClasses
        end

        local timerOff = function()
            local p = DB()
            return p and (not p.totemBar.enabledClasses or not p.totemBar.showTimer)
        end

        -- LAYOUT section
        local layoutSection
        layoutSection, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

        local ALL_CLASSES = {
            "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
            "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "MONK",
            "DRUID", "DEMONHUNTER", "EVOKER",
        }

        -- Row 1: Enabled Classes dropdown | Icon Size (+ spacing cog)
        local row1
        do
            local classItems = {}
            classItems[#classItems + 1] = { key = "NONE", label = EllesmereUI.L("None (Disabled)") }
            for _, cf in ipairs(ALL_CLASSES) do
                local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
                local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cf])
                    or (cf:sub(1, 1):upper() .. cf:sub(2):lower())
                local hex = color and color.colorStr or "ffffffff"
                classItems[#classItems + 1] = { key = cf, label = "|c" .. hex .. name .. "|r" }
            end

            row1, h = W:DualRow(parent, y,
                { type = "label", text = "Enabled Classes" },
                { type = "slider", text = "Icon Size",
                  min = 16, max = 60, step = 1,
                  disabled = totemOff,
                  disabledTooltip = "Select a class above", rawTooltip = true,
                  getValue = function() local p = DB(); return p and (p.totemBar.iconSize or 30) end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.totemBar.iconSize = v; RefreshTotem()
                  end }
            );  y = y - h

            -- Class dropdown on left region
            local leftRgn = row1._leftRegion
            local cbDD, cbDDRefresh
            cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                leftRgn, 210, leftRgn:GetFrameLevel() + 2,
                classItems,
                function(key)
                    local p = DB()
                    if not p then return false end
                    if key == "NONE" then return not p.totemBar.enabledClasses end
                    return p.totemBar.enabledClasses and p.totemBar.enabledClasses[key] or false
                end,
                function(key, v)
                    local p = DB()
                    if not p then return end
                    if key == "NONE" then
                        p.totemBar.enabledClasses = nil
                    else
                        if not p.totemBar.enabledClasses then
                            p.totemBar.enabledClasses = {}
                        end
                        p.totemBar.enabledClasses[key] = v or nil
                        if not next(p.totemBar.enabledClasses) then
                            p.totemBar.enabledClasses = nil
                        end
                    end
                    local ddMenu = cbDD._ddMenu
                    if ddMenu then
                        for _, sf in ipairs({ ddMenu:GetChildren() }) do
                            local sc = sf.GetScrollChild and sf:GetScrollChild()
                            if sc then
                                for _, row in ipairs({ sc:GetChildren() }) do
                                    if row._updateCheck then row._updateCheck() end
                                end
                            end
                        end
                    end
                    RefreshTotem()
                    EllesmereUI:RefreshPage()
                end, nil, 8, false)
            PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
            leftRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)

            -- Spacing cog on Icon Size (right region)
            local rgn = row1._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Settings",
                rows = {
                    { type = "slider", pixel = true, label = "Spacing", min = 0, max = 20, step = 1,
                      get = function() local p = DB(); return p and (p.totemBar.spacing or 2) end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.totemBar.spacing = v; RefreshTotem()
                      end },
                },
            })
            MakeCogBtn(rgn, cogShow)
        end

        -- Row 2: Timer Size | Show Timer
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Timer Size",
              min = 6, max = 24, step = 1,
              disabled = timerOff,
              disabledTooltip = "Show Timer",
              getValue = function() local p = DB(); return p and (p.totemBar.timerSize or 11) end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.totemBar.timerSize = v; RefreshTotem()
              end },
            { type = "toggle", text = "Show Timer",
              disabled = totemOff,
              disabledTooltip = "Select a class above", rawTooltip = true,
              getValue = function() local p = DB(); return p and p.totemBar.showTimer ~= false end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.totemBar.showTimer = v; RefreshTotem()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Row 3: Border Style | Border Size (+ inline swatch + offset cog)
        do
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local bsRow
            bsRow, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Border Style",
                  disabled = totemOff,
                  disabledTooltip = "Select a class above", rawTooltip = true,
                  values = texValues, order = texOrder,
                  getValue = function() local p = DB(); return p and (p.totemBar.borderTexture or "solid") end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.totemBar.borderTexture = v
                      p.totemBar.borderTextureOffset = nil; p.totemBar.borderTextureOffsetY = nil
                      p.totemBar.borderTextureShiftX = nil; p.totemBar.borderTextureShiftY = nil
                      local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      p.totemBar.borderR = _bcol.r; p.totemBar.borderG = _bcol.g; p.totemBar.borderB = _bcol.b; p.totemBar.borderA = 1
                      p.totemBar.borderBehind = _bbehind
                      local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                      if defSz then p.totemBar.borderSize = defSz end
                      RefreshTotem(); EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Border Size",
                  min = 0, max = 4, step = 1,
                  disabled = totemOff,
                  disabledTooltip = "Select a class above", rawTooltip = true,
                  getValue = function()
                      local p = DB(); return p and (p.totemBar.borderSize or 0) or 0
                  end,
                  setValue = function(v)
                      local p = DB(); if not p then return end
                      p.totemBar.borderSize = v; RefreshTotem(); EllesmereUI:RefreshPage()
                  end }
            );  y = y - h

            -- Inline border color swatch on Border Size slider
            do
                local rgn = bsRow._rightRegion
                local ctrl = rgn._control
                local PP = EllesmereUI.PP
                local borderSwatch, updateBorderSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, bsRow:GetFrameLevel() + 3,
                    function()
                        local p = DB()
                        return (p and p.totemBar.borderR or 0), (p and p.totemBar.borderG or 0),
                               (p and p.totemBar.borderB or 0), (p and p.totemBar.borderA or 1)
                    end,
                    function(r, g, b, a)
                        local p = DB(); if not p then return end
                        p.totemBar.borderR = r; p.totemBar.borderG = g; p.totemBar.borderB = b; p.totemBar.borderA = a
                        RefreshTotem(); EllesmereUI:RefreshPage()
                    end,
                    true, 20)
                PP.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                -- Disable swatch when border size is 0
                local borderSwatchBlock = CreateFrame("Frame", nil, borderSwatch)
                borderSwatchBlock:SetAllPoints()
                borderSwatchBlock:SetFrameLevel(borderSwatch:GetFrameLevel() + 10)
                borderSwatchBlock:EnableMouse(true)
                borderSwatchBlock:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(borderSwatch, EllesmereUI.DisabledTooltip("This option requires a Border Size above 0."))
                end)
                borderSwatchBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateBorderSwatchState()
                    local p = DB()
                    local noBorder = not p or (p.totemBar.borderSize or 0) == 0
                    if noBorder then borderSwatch:SetAlpha(0.3); borderSwatchBlock:Show()
                    else borderSwatch:SetAlpha(1); borderSwatchBlock:Hide() end
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateBorderSwatch(); UpdateBorderSwatchState() end)
                UpdateBorderSwatchState()
            end

            -- Border offset cog on Border Style dropdown
            do
                local rgn = bsRow._leftRegion
                EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    rows = {
                        { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.totemBar.borderTextureOffset
                              if v then return v end
                              local dox = EllesmereUI.GetBorderDefaults("resourcebars", p.totemBar.borderTexture or "solid", p.totemBar.borderSize or 0)
                              return dox
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.totemBar.borderTextureOffset = v; RefreshTotem(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.totemBar.borderTextureOffsetY
                              if v then return v end
                              local _, doy = EllesmereUI.GetBorderDefaults("resourcebars", p.totemBar.borderTexture or "solid", p.totemBar.borderSize or 0)
                              return doy
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.totemBar.borderTextureOffsetY = v; RefreshTotem(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.totemBar.borderTextureShiftX
                              if v then return v end
                              local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", p.totemBar.borderTexture or "solid", p.totemBar.borderSize or 0)
                              return dsx
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.totemBar.borderTextureShiftX = v == 0 and nil or v; RefreshTotem(); EllesmereUI:RefreshPage()
                          end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                          get = function()
                              local p = DB(); if not p then return 0 end
                              local v = p.totemBar.borderTextureShiftY
                              if v then return v end
                              local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", p.totemBar.borderTexture or "solid", p.totemBar.borderSize or 0)
                              return dsy
                          end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.totemBar.borderTextureShiftY = v == 0 and nil or v; RefreshTotem(); EllesmereUI:RefreshPage()
                          end },
                        { type = "toggle", label = "Show Behind",
                          get = function() local p = DB(); return p and p.totemBar.borderBehind or false end,
                          set = function(v)
                              local p = DB(); if not p then return end
                              p.totemBar.borderBehind = v == false and nil or v; RefreshTotem(); EllesmereUI:RefreshPage()
                          end },
                    },
                }, rgn, totemOff)
            end
        end

        -- Row 4: Frame Strata | Orientation
        local tmStrataValues = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High", DIALOG = "Dialog" }
        local tmStrataOrder = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Frame Strata",
              tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
              disabled = totemOff,
              disabledTooltip = "Select a class above", rawTooltip = true,
              values = tmStrataValues, order = tmStrataOrder,
              getValue = function()
                  local p = DB(); return p and p.totemBar.frameStrata or "MEDIUM"
              end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.totemBar.frameStrata = v; RefreshTotem()
              end },
            { type = "dropdown", text = "Orientation",
              disabled = totemOff,
              disabledTooltip = "Select a class above", rawTooltip = true,
              values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" },
              order = { "HORIZONTAL", "VERTICAL" },
              getValue = function() local p = DB(); return p and (p.totemBar.orientation or "HORIZONTAL") end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.totemBar.orientation = v; RefreshTotem()
              end }
        );  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  GCD Bar page
    ---------------------------------------------------------------------------
    local function BuildGCDBarPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        parent._showRowDivider = true

        -- Re-append SharedMedia textures (catches lazy-registered SM packs)
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(
                _G._ERB_BarTextureNames or {},
                _G._ERB_BarTextureOrder or {},
                nil,
                _G._ERB_BarTextures
            )
        end
        -- Bar texture dropdown values (same set the renderer uses)
        local texValues, texOrder = {}, {}
        do
            local texNames = _G._ERB_BarTextureNames or {}
            local texOrder2 = _G._ERB_BarTextureOrder or {}
            local texLookup = _G._ERB_BarTextures or {}
            for _, key in ipairs(texOrder2) do
                if key ~= "---" then texValues[key] = texNames[key] or key end
                texOrder[#texOrder + 1] = key
            end
            texValues._menuOpts = { itemHeight = 28, background = function(key) return texLookup[key] end }
        end

        local gcdOff = function() local p = DB(); return p and not p.gcdBar.enabled end

        local function RefreshGCD()
            if _G._ERB_Apply then _G._ERB_Apply() end
            if EllesmereUI.NotifyElementResized then
                EllesmereUI.NotifyElementResized("ERB_GCDBar")
            end
        end

        -----------------------------------------------------------------------
        local _sec
        _sec, h = W:SectionHeader(parent, "LAYOUT", y);  y = y - h

        local gStrataValues = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High", DIALOG = "Dialog" }
        local gStrataOrder = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" }

        -- Row: Enable GCD Bar (+ position cog) | Frame Strata
        local enableRow
        enableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable GCD Bar",
              tooltip = "Shows a bar that fills over the global cooldown.",
              getValue = function() local p = DB(); return p and p.gcdBar.enabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.gcdBar.enabled = v; RefreshGCD(); EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Frame Strata",
              tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
              disabled = gcdOff, disabledTooltip = "GCD Bar",
              values = gStrataValues, order = gStrataOrder,
              getValue = function() local p = DB(); return p and p.gcdBar.frameStrata or "MEDIUM" end,
              setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.frameStrata = v; RefreshGCD() end }
        );  y = y - h
        -- Inline position cog (X/Y + unlock) on Enable
        do
            local rgn = enableRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "GCD Bar Position",
                rows = {
                    -- X/Y edit whichever position is in effect: the saved unlock
                    -- position takes priority in the renderer, so once it exists
                    -- these sliders adjust it (otherwise they adjust the CENTER offset).
                    { type = "slider", label = "X Offset", min = -600, max = 600, step = 1,
                      get = function()
                          local p = DB(); if not p then return 0 end
                          local g = p.gcdBar
                          if g.unlockPos and g.unlockPos.point then return g.unlockPos.x or 0 end
                          return g.anchorX or 0
                      end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          local g = p.gcdBar
                          if g.unlockPos and g.unlockPos.point then g.unlockPos.x = v else g.anchorX = v end
                          RefreshGCD()
                      end },
                    { type = "slider", label = "Y Offset", min = -600, max = 600, step = 1,
                      get = function()
                          local p = DB(); if not p then return 0 end
                          local g = p.gcdBar
                          if g.unlockPos and g.unlockPos.point then return g.unlockPos.y or 0 end
                          return g.anchorY or -78
                      end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          local g = p.gcdBar
                          if g.unlockPos and g.unlockPos.point then g.unlockPos.y = v else g.anchorY = v end
                          RefreshGCD()
                      end },
                },
                footer = { unlockKey = "ERB_GCDBar" },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("GCD Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDis()
                local p = DB()
                if p and not p.gcdBar.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDis)
            UpdateCogDis()
        end

        -- Row: Height | Width
        local ghDis, ghTip, ghRaw = EllesmereUI.MatchGuard("ERB_GCDBar", "Height", gcdOff, "GCD Bar")
        local gwDis, gwTip, gwRaw = EllesmereUI.MatchGuard("ERB_GCDBar", "Width", gcdOff, "GCD Bar")
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Height", min = 1, max = 60, step = 1,
              disabled = ghDis, disabledTooltip = ghTip, rawTooltip = ghRaw,
              getValue = function() local p = DB(); return p and p.gcdBar.height or 12 end,
              setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.height = v; RefreshGCD() end },
            { type = "slider", text = "Width", min = 50, max = 500, step = 1,
              disabled = gwDis, disabledTooltip = gwTip, rawTooltip = gwRaw,
              getValue = function() local p = DB(); return p and p.gcdBar.width or 220 end,
              setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.width = v; RefreshGCD() end }
        );  y = y - h

        -- Row: Orientation | Instance Only
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Orientation",
              disabled = gcdOff, disabledTooltip = "GCD Bar",
              values = { HORIZONTAL = "Horizontal (Right)", HORIZONTAL_LEFT = "Horizontal (Left)", VERTICAL_UP = "Vertical (Up)", VERTICAL_DOWN = "Vertical (Down)" },
              order = { "HORIZONTAL", "HORIZONTAL_LEFT", "VERTICAL_UP", "VERTICAL_DOWN" },
              getValue = function() local p = DB(); return p and p.gcdBar.orientation or "HORIZONTAL" end,
              setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.orientation = v; RefreshGCD(); EllesmereUI:RefreshPage() end },
            { type = "toggle", text = "Instance Only",
              tooltip = "Only show the GCD bar while in a dungeon, raid, arena or battleground.",
              disabled = gcdOff, disabledTooltip = "GCD Bar",
              getValue = function() local p = DB(); return p and p.gcdBar.instanceOnly end,
              setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.instanceOnly = v; RefreshGCD() end }
        );  y = y - h

        -- Row: Only Instant Casts | Always Show
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Only Instant Casts",
              tooltip = "Only show the GCD bar for instant-cast abilities. While hard-casting or channeling a spell, the bar stays hidden (the cast bar already shows that progress).",
              disabled = gcdOff, disabledTooltip = "GCD Bar",
              getValue = function() local p = DB(); return p and p.gcdBar.instantOnly end,
              setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.instantOnly = v; RefreshGCD() end },
            { type = "toggle", text = "Always Show",
              tooltip = "Keep the GCD bar visible (sitting empty) when no global cooldown is running, instead of hiding it.",
              disabled = gcdOff, disabledTooltip = "GCD Bar",
              getValue = function() local p = DB(); return p and p.gcdBar.alwaysShow end,
              setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.alwaysShow = v; RefreshGCD() end }
        );  y = y - h

        _, h = W:Spacer(parent, y, 16);  y = y - h

        -----------------------------------------------------------------------
        _sec, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

        -- Row: Border Style | Border Size (+ inline color swatch + offset cog)
        do
            local btValues, btOrder = EllesmereUI.GetBorderTextureDropdown()
            local bsRow
            bsRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style",
                  disabled = gcdOff, disabledTooltip = "GCD Bar",
                  values=btValues, order=btOrder,
                  getValue=function() local p = DB(); return p and p.gcdBar.borderTexture or "solid" end,
                  setValue=function(v)
                      local p = DB(); if not p then return end
                      p.gcdBar.borderTexture = v; p.gcdBar.borderTextureOffset = nil; p.gcdBar.borderTextureOffsetY = nil; p.gcdBar.borderTextureShiftX = nil; p.gcdBar.borderTextureShiftY = nil
                      local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                      p.gcdBar.borderR = _bcol.r; p.gcdBar.borderG = _bcol.g; p.gcdBar.borderB = _bcol.b; p.gcdBar.borderA = 1
                      p.gcdBar.borderBehind = _bbehind
                      local defSz = EllesmereUI.GetBorderDefaultSize("resourcebars", v)
                      if defSz then p.gcdBar.borderSize = defSz end
                      RefreshGCD(); EllesmereUI:RefreshPage()
                  end },
                { type = "slider", text = "Border Size", min = 0, max = 4, step = 1,
                  disabled = gcdOff, disabledTooltip = "GCD Bar",
                  getValue = function() local p = DB(); return p and (p.gcdBar.borderSize or 0) or 0 end,
                  setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.borderSize = v; RefreshGCD(); EllesmereUI:RefreshPage() end });  y = y - h
            -- Border color swatch on the size slider (right region)
            do
                local rgn = bsRow._rightRegion
                local ctrl = rgn._control
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, bsRow:GetFrameLevel() + 3,
                    function()
                        local p = DB()
                        return (p and p.gcdBar.borderR or 0), (p and p.gcdBar.borderG or 0),
                               (p and p.gcdBar.borderB or 0), (p and p.gcdBar.borderA or 1)
                    end,
                    function(r, g, b, a)
                        local p = DB(); if not p then return end
                        p.gcdBar.borderR, p.gcdBar.borderG, p.gcdBar.borderB, p.gcdBar.borderA = r, g, b, a
                        RefreshGCD(); EllesmereUI:RefreshPage()
                    end, true, 20)
                PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
                local block = CreateFrame("Frame", nil, swatch)
                block:SetAllPoints()
                block:SetFrameLevel(swatch:GetFrameLevel() + 10)
                block:EnableMouse(true)
                block:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("This option requires a Border Size above 0."))
                end)
                block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateSwatchState()
                    local p = DB()
                    local noBorder = not p or (p.gcdBar.borderSize or 0) == 0
                    if noBorder then swatch:SetAlpha(0.3); block:Show() else swatch:SetAlpha(1); block:Hide() end
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateSwatch(); UpdateSwatchState() end)
                UpdateSwatchState()
            end
            -- Offset cog on Border Style (left region), hidden for "solid"
            do
                local rgn = bsRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    rows = {
                        { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                          get = function() local p = DB(); if not p then return 0 end; local v = p.gcdBar.borderTextureOffset; if v then return v end; local dox = EllesmereUI.GetBorderDefaults("resourcebars", p.gcdBar.borderTexture or "solid", p.gcdBar.borderSize or 0); return dox end,
                          set = function(v) local p = DB(); if not p then return end; p.gcdBar.borderTextureOffset = v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                          get = function() local p = DB(); if not p then return 0 end; local v = p.gcdBar.borderTextureOffsetY; if v then return v end; local _, doy = EllesmereUI.GetBorderDefaults("resourcebars", p.gcdBar.borderTexture or "solid", p.gcdBar.borderSize or 0); return doy end,
                          set = function(v) local p = DB(); if not p then return end; p.gcdBar.borderTextureOffsetY = v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                          get = function() local p = DB(); if not p then return 0 end; local v = p.gcdBar.borderTextureShiftX; if v then return v end; local _, _, dsx = EllesmereUI.GetBorderDefaults("resourcebars", p.gcdBar.borderTexture or "solid", p.gcdBar.borderSize or 0); return dsx end,
                          set = function(v) local p = DB(); if not p then return end; p.gcdBar.borderTextureShiftX = v == 0 and nil or v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                          get = function() local p = DB(); if not p then return 0 end; local v = p.gcdBar.borderTextureShiftY; if v then return v end; local _, _, _, dsy = EllesmereUI.GetBorderDefaults("resourcebars", p.gcdBar.borderTexture or "solid", p.gcdBar.borderSize or 0); return dsy end,
                          set = function(v) local p = DB(); if not p then return end; p.gcdBar.borderTextureShiftY = v == 0 and nil or v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                        { type = "toggle", label = "Show Behind",
                          get = function() local p = DB(); return p and p.gcdBar.borderBehind or false end,
                          set = function(v) local p = DB(); if not p then return end; p.gcdBar.borderBehind = v == false and nil or v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                    },
                })
                local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
                local function UpdateCogVis()
                    local p = DB()
                    local tex = p and p.gcdBar.borderTexture or "solid"
                    if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
                UpdateCogVis()
            end
        end

        -- Row: Color (gradient end / custom / class + gradient cog) | Background (+ bg swatch)
        local colorRow
        colorRow, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Color",
              disabled = gcdOff, disabledTooltip = "GCD Bar",
              swatches = {
                  { tooltip = "Gradient End Color", hasAlpha = true,
                    getValue = function() local p = DB(); if not p then return 0.20, 0.20, 0.80, 1 end; return p.gcdBar.gradientR, p.gcdBar.gradientG, p.gcdBar.gradientB, p.gcdBar.gradientA end,
                    setValue = function(r, g, b, a) local p = DB(); if not p then return end; p.gcdBar.gradientR, p.gcdBar.gradientG, p.gcdBar.gradientB, p.gcdBar.gradientA = r, g, b, a; RefreshGCD() end },
                  { tooltip = "Custom Colored", hasAlpha = true,
                    getValue = function() local p = DB(); if not p then local _, cf = UnitClass("player"); local cc = CLASS_COLORS[cf]; return cc and cc[1] or 1, cc and cc[2] or 0.70, cc and cc[3] or 0, 1 end; return p.gcdBar.fillR, p.gcdBar.fillG, p.gcdBar.fillB, p.gcdBar.fillA end,
                    setValue = function(r, g, b, a) local p = DB(); if not p then return end; p.gcdBar.fillR, p.gcdBar.fillG, p.gcdBar.fillB, p.gcdBar.fillA = r, g, b, a; if p.gcdBar.classColored then p.gcdBar.classColored = false end; RefreshGCD(); EllesmereUI:RefreshPage() end,
                    onClick = function(self) local p = DB(); if not p then return end; if p.gcdBar.classColored then p.gcdBar.classColored = false; RefreshGCD(); EllesmereUI:RefreshPage(); return end; if self._eabOrigClick then self._eabOrigClick(self) end end,
                    refreshAlpha = function() local p = DB(); return (p and not p.gcdBar.classColored) and 1 or 0.3 end },
                  { tooltip = "Class Colored",
                    getValue = function() local _, classFile = UnitClass("player"); local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]; if cc then return cc.r, cc.g, cc.b, 1 end; return 1, 0.70, 0, 1 end,
                    setValue = function() end,
                    onClick = function() local p = DB(); if not p then return end; p.gcdBar.classColored = true; RefreshGCD(); EllesmereUI:RefreshPage() end,
                    refreshAlpha = function() local p = DB(); return (not p or p.gcdBar.classColored == true) and 1 or 0.3 end },
              } },
            { type = "slider", text = "Background", min = 0, max = 100, step = 1,
              disabled = gcdOff, disabledTooltip = "GCD Bar",
              getValue = function() local p = DB(); return math.floor(((p and p.gcdBar.bgA or 0.7) * 100) + 0.5) end,
              setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.bgA = v / 100; RefreshGCD() end }
        );  y = y - h
        -- Gradient cog on Color
        do
            local rgn = colorRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Gradient Settings",
                rows = {
                    { type = "toggle", label = "Enable Gradient",
                      get = function() local p = DB(); return p and p.gcdBar.gradientEnabled end,
                      set = function(v) local p = DB(); if not p then return end; p.gcdBar.gradientEnabled = v; RefreshGCD(); EllesmereUI:RefreshPage() end },
                    { type = "dropdown", label = "Gradient Direction",
                      values = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }, order = { "HORIZONTAL", "VERTICAL" },
                      get = function() local p = DB(); return p and p.gcdBar.gradientDir or "HORIZONTAL" end,
                      set = function(v) local p = DB(); if not p then return end; p.gcdBar.gradientDir = v; RefreshGCD() end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("GCD Bar")) end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisGrad() local p = DB(); if p and not p.gcdBar.enabled then cogDis:Show() else cogDis:Hide() end end
            cogBtn:HookScript("OnShow", UpdateCogDisGrad)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisGrad)
            UpdateCogDisGrad()
        end
        -- Gradient end-color swatch enable/disable
        do
            local swatch = colorRow._leftRegion._control
            local function UpdateGradientSwatch()
                local p = DB()
                if not p or not p.gcdBar.enabled then swatch:SetAlpha(0.15); swatch:Disable(); swatch._disabledTooltip = "GCD Bar"
                elseif not p.gcdBar.gradientEnabled then swatch:SetAlpha(0.15); swatch:Disable(); swatch._disabledTooltip = "Gradient"
                else swatch:SetAlpha(1); swatch:Enable(); swatch._disabledTooltip = nil end
            end
            UpdateGradientSwatch()
            EllesmereUI.RegisterWidgetRefresh(UpdateGradientSwatch)
        end
        -- Background color swatch on the Background slider (right region)
        do
            local rgn = colorRow._rightRegion
            local ctrl = rgn._control
            local bgSwatch, bgUpdateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, colorRow:GetFrameLevel() + 3,
                function() local p = DB(); return (p and p.gcdBar.bgR or 0), (p and p.gcdBar.bgG or 0), (p and p.gcdBar.bgB or 0) end,
                function(r, g, b) local p = DB(); if not p then return end; p.gcdBar.bgR, p.gcdBar.bgG, p.gcdBar.bgB = r, g, b; RefreshGCD() end,
                nil, 20)
            PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local function UpdateBgSwatch()
                local p = DB()
                if not p or not p.gcdBar.enabled then bgSwatch:SetAlpha(0.15); bgSwatch:Disable(); bgSwatch._disabledTooltip = "GCD Bar"
                else bgSwatch:SetAlpha(1); bgSwatch:Enable(); bgSwatch._disabledTooltip = nil end
                bgUpdateSwatch()
            end
            UpdateBgSwatch()
            EllesmereUI.RegisterWidgetRefresh(UpdateBgSwatch)
        end

        -- Row: Bar Texture | Show Spark
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Bar Texture",
              disabled = gcdOff, disabledTooltip = "GCD Bar",
              values = texValues, order = texOrder,
              getValue = function() local p = DB(); return p and p.gcdBar.texture or "none" end,
              setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.texture = v; RefreshGCD() end },
            { type = "toggle", text = "Show Spark",
              tooltip = "Show a small glowing spark that moves along the leading edge of the fill.",
              disabled = gcdOff, disabledTooltip = "GCD Bar",
              getValue = function() local p = DB(); return p and p.gcdBar.showSpark end,
              setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.showSpark = v; RefreshGCD() end }
        );  y = y - h

        -- Row: Deplete Fill (left half only)
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Deplete Fill",
              tooltip = "Start the bar full and drain it as the global cooldown elapses, instead of filling it up.",
              disabled = gcdOff, disabledTooltip = "GCD Bar",
              getValue = function() local p = DB(); return p and p.gcdBar.depleteFill end,
              setValue = function(v) local p = DB(); if not p then return end; p.gcdBar.depleteFill = v; RefreshGCD() end },
            { type = "spacer" }
        );  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIResourceBars", {
        title       = "Resource Bars",
        description = "Custom class resource, health, and mana bar display.",
        pages       = { PAGE_DISPLAY, PAGE_CASTBAR, PAGE_GCD, PAGE_TOTEM },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_DISPLAY then
                return BuildBarDisplayPage(pageName, parent, yOffset)
            elseif pageName == PAGE_CASTBAR then
                return BuildCastBarPage(pageName, parent, yOffset)
            elseif pageName == PAGE_GCD then
                return BuildGCDBarPage(pageName, parent, yOffset)
            elseif pageName == PAGE_TOTEM then
                return BuildTotemBarPage(pageName, parent, yOffset)
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
