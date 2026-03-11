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
            _frame = bf, edges = bf._ppBorders or {},
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

            local pScale = sp.scale or 1.0
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

                -- Hide pips if any exist from a previous build
                for _, pip in ipairs(_previewFrames.pips) do pip:Hide() end
            else
                -- Pips preview update
                -- pipWidth is the total bar width; divide evenly across pips.
                -- Snap helpers: round values to the pip container's physical pixel grid
                local pcScale = pc:GetEffectiveScale()
                if pcScale <= 0 then pcScale = 1 end
                -- Round to nearest pixel (for sizes)
                local function PipSnap(val)
                    return math.floor(val * pcScale + 0.5) / pcScale
                end
                local onePx = 1 / pcScale  -- exactly 1 physical pixel in local coords
                local totalW = PipSnap(sp.pipWidth)
                local pipSp = (sp.pipSpacing > 0) and math.max(onePx, PipSnap(sp.pipSpacing)) or 0
                local snappedPipH = PipSnap(sp.pipHeight)
                local numPips = 5
                local isVertical = false   -- preview always horizontal
                local isReversed = false
                -- Available length for pips along the stacking axis
                local availW = totalW - (numPips - 1) * pipSp
                local baseW = math.floor(availW * pcScale / numPips) / pcScale
                local leftover = availW - baseW * numPips
                local extraCount = math.floor(leftover * pcScale + 0.5)

                local pipX = {}
                local pipW = {}
                local x0 = 0
                for i = 1, numPips do
                    pipX[i] = x0
                    pipW[i] = baseW + (i <= extraCount and onePx or 0)
                    x0 = x0 + pipW[i] + pipSp
                end
                if isVertical then
                    pc:SetSize(snappedPipH, totalW)
                else
                    pc:SetSize(totalW, snappedPipH)
                end

                local filledCount
                if sp.thresholdEnabled then
                    filledCount = sp.thresholdCount
                else
                    filledCount = _previewPipCount
                end
                local useThresh = sp.thresholdEnabled
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
                        if sp.thresholdPartialOnly and i < sp.thresholdCount then
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
                            fs:SetPoint("CENTER", pip, "CENTER", 0, 0)
                            fs:SetTextColor(1, 1, 1, 0.9)
                            pip._pvCdText = fs
                        end
                        SetPVFont(pip._pvCdText, FONT_PATH, sp.textSize)
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

                -- Hide bar fill if it exists from a previous build
                if pc._barFill then pc._barFill:Hide() end
            end

            -- Full-bar border on container
            if not pc._barBorder then
                local PP = EllesmereUI and EllesmereUI.PP
                local bf = CreateFrame("Frame", nil, pc)
                bf:SetAllPoints(pc)
                bf:SetFrameLevel(pc:GetFrameLevel() + 2)
                if PP then
                    PP.CreateBorder(bf, sp.borderR, sp.borderG, sp.borderB, sp.borderA, sp.borderSize, "BORDER", 7)
                end
                pc._barBorder = {
                    _frame = bf,
                    edges = bf._ppBorders or {},
                    SetSize = function(self, sz)
                        if PP then PP.SetBorderSize(bf, sz) end
                    end,
                    SetColor = function(self, cr, cg, cb, ca)
                        if PP then PP.SetBorderColor(bf, cr, cg, cb, ca or 1) end
                    end,
                    SetShown = function(self, shown)
                        if PP then
                            if shown then PP.ShowBorder(bf) else PP.HideBorder(bf) end
                        end
                    end,
                }
            end
            if sp.borderSize > 0 then
                pc._barBorder:SetSize(sp.borderSize)
                pc._barBorder:SetColor(sp.borderR, sp.borderG, sp.borderB, sp.borderA)
                pc._barBorder:SetShown(true)
            else
                pc._barBorder:SetShown(false)
            end

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
                    local filledCount = sp.thresholdEnabled and sp.thresholdCount or _previewPipCount
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

        -- Row 1: Visibility | Dark Theme
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Visibility",
              values = { always = "Always", combat = "In Combat", target = "When Enemy Targeted" },
              order = { "always", "combat", "target" },
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
              end },
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
              end }
        );  y = y - h

        -- Row 2: Texture | Background Color
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

        _, h = W:Spacer(parent, y, 16);  y = y - h

        -----------------------------------------------------------------------
        --  CLASS RESOURCE BAR
        -----------------------------------------------------------------------
        local classSection
        classSection, h = W:SectionHeader(parent, "CLASS RESOURCE BAR", y);  y = y - h

        local classOff = function() local p = DB(); return p and not p.secondary.enabled end

        -- Row 1: Show Class Resource | Spacing
        local classEnableRow
        classEnableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Class Resource",
              getValue = function() local p = DB(); return p and p.secondary.enabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.enabled = v; RebuildClass()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Spacing",
              min = 0, max = 20, step = 1,
              disabled = classOff,
              disabledTooltip = "Enable Class Resource",
              getValue = function() local p = DB(); return p and p.secondary.pipSpacing or 3 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.pipSpacing = v; SmoothRefresh()
              end }
        );  y = y - h

        -- Row 2: Orientation | empty
        _, h = W:DualRow(parent, y,
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
              end },
            { type = "label", text = "" }
        );  y = y - h

        -- Row 3: (Sync) Height | (Sync) Width
        local classSizeRow
        classSizeRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 60, step = 1,
              disabled = classOff,
              disabledTooltip = "Enable Class Resource",
              getValue = function() local p = DB(); return p and p.secondary.pipHeight or 20 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.pipHeight = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Width",
              min = 10, max = 500, step = 1,
              disabled = classOff,
              disabledTooltip = "Enable Class Resource",
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

        -- Row 3: (Sync) Border | (Sync) Opacity
        local classBorderRow
        classBorderRow, h = W:DualRow(parent, y,
            { type = "colorpicker", text = "Border", hasAlpha = true,
              disabled = classOff,
              disabledTooltip = "Enable Class Resource",
              getValue = function()
                  local p = DB()
                  if not p then return 0, 0, 0, 1 end
                  return p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA
              end,
              setValue = function(r, g, b, a)
                  local p = DB(); if not p then return end
                  p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA = r, g, b, a
                  SmoothRefresh(); EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Opacity",
              min = 0, max = 100, step = 5,
              disabled = classOff,
              disabledTooltip = "Enable Class Resource",
              getValue = function() local p = DB(); return math.floor((p and p.secondary.barAlpha or 1) * 100 + 0.5) end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.barAlpha = v / 100; RefreshClass()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        _syncRows.classBorder  = classBorderRow._leftRegion
        _syncRows.classOpacity = classBorderRow._rightRegion
        -- Inline cog (RESIZE) on Border for border size
        do
            local rgn = classBorderRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Border Size",
                rows = {
                    { type = "slider", label = "Size", min = 0, max = 4, step = 1,
                      get = function() local p = DB(); return p and p.secondary.borderSize or 1 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.borderSize = v; RebuildClass()
                          EllesmereUI:RefreshPage()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Class Resource"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBorderCogDis()
                local p = DB()
                if p and not p.secondary.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateBorderCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateBorderCogDis)
            UpdateBorderCogDis()
        end
        -- Sync icon on Border
        do
            local rgn = classBorderRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Border to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local r, g, b, a = p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA
                    local sz = p.secondary.borderSize or 1
                    p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA = r, g, b, a
                    p.primary.borderSize = sz
                    p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA = r, g, b, a
                    p.health.borderSize = sz
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local sr, sg, sb, sa, ssz = p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA, p.secondary.borderSize or 1
                    local function eq(t) return t.borderR == sr and t.borderG == sg and t.borderB == sb and t.borderA == sa and (t.borderSize or 1) == ssz end
                    return eq(p.primary) and eq(p.health)
                end,
                flashTargets = function() return { _syncRows.classBorder, _syncRows.powerBorder, _syncRows.healthBorder } end,
            })
        end
        -- Sync icon on Opacity
        do
            local rgn = classBorderRow._rightRegion
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

        -- Row 4: Class Colored Fill (inline swatch) | Resource Text (inline cog RESIZE)
        local classColorRow
        classColorRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Class Colored Fill",
              disabled = classOff,
              disabledTooltip = "Enable Class Resource",
              getValue = function() local p = DB(); return p and (p.secondary.classColored ~= false) end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.classColored = v; RebuildClass()
                  EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Resource Text",
              disabled = classOff,
              disabledTooltip = "Enable Class Resource",
              getValue = function() local p = DB(); return p and p.secondary.showText end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.showText = v; RebuildClass()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        -- Inline color swatch on Class Colored Fill
        do
            local rgn = classColorRow._leftRegion
            local swatch, _ = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 2,
                function()
                    local p = DB()
                    if not p then return 0xDB/255, 0xCF/255, 0x37/255, 1 end
                    return p.secondary.fillR, p.secondary.fillG, p.secondary.fillB, p.secondary.fillA
                end,
                function(r, g, b, a)
                    local p = DB(); if not p then return end
                    p.secondary.fillR, p.secondary.fillG, p.secondary.fillB, p.secondary.fillA = r, g, b, a
                    RebuildClass(); SmoothRefresh()
                end, true, 20)
            PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
            rgn._lastInline = swatch
            local swDis = CreateFrame("Frame", nil, rgn)
            swDis:SetAllPoints(swatch)
            swDis:SetFrameLevel(swatch:GetFrameLevel() + 5)
            local swDisTex = swDis:CreateTexture(nil, "OVERLAY")
            swDisTex:SetAllPoints()
            swDisTex:SetColorTexture(0.12, 0.12, 0.12, 0.75)
            swDis:EnableMouse(true)
            swDis:SetScript("OnEnter", function()
                local p = DB()
                if p and not p.secondary.enabled then
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Enable Class Resource"))
                else
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("This option requires Class Colored Fill to be disabled"))
                end
            end)
            swDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateClassSwDis()
                local p = DB()
                if p and (not p.secondary.enabled or (p.secondary.classColored ~= false)) then
                    swDis:Show(); swatch:SetAlpha(0.3)
                else
                    swDis:Hide(); swatch:SetAlpha(1)
                end
            end
            swatch:HookScript("OnShow", UpdateClassSwDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateClassSwDis)
            UpdateClassSwDis()
        end
        -- Inline cog for Charged Combo Point color
        do
            local rgn = classColorRow._leftRegion
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
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
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

        -- Row 5: Threshold Color (inline swatch) | Threshold Count (inline cog)
        local threshRow
        threshRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Threshold Color",
              disabled = function() local p = DB(); return p and not p.secondary.enabled end,
              disabledTooltip = function() local p = DB(); if p and not p.secondary.enabled then return "Enable Class Resource" end end,
              getValue = function() local p = DB(); return p and p.secondary.thresholdEnabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.thresholdEnabled = v; RefreshClass()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Threshold",
              min = 1, max = IsBarTypeSecondary() and 100 or 10, step = 1,
              disabled = function() local p = DB(); return p and (not p.secondary.enabled or not p.secondary.thresholdEnabled) end,
              disabledTooltip = function() local p = DB(); if p and not p.secondary.enabled then return "Enable Class Resource" end; return "This option requires Threshold Color to be enabled" end,
              getValue = function() local p = DB(); return p and p.secondary.thresholdCount or 3 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.thresholdCount = v; RefreshClass()
              end }
        );  y = y - h
        -- Inline swatch on Threshold Color
        do
            local rgn = threshRow._leftRegion
            local swatch, _ = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 2,
                function()
                    local p = DB()
                    if not p then return 0x0c/255, 0xd2/255, 0x9d/255, 1 end
                    return p.secondary.thresholdR, p.secondary.thresholdG, p.secondary.thresholdB, p.secondary.thresholdA
                end,
                function(r, g, b, a)
                    local p = DB(); if not p then return end
                    p.secondary.thresholdR, p.secondary.thresholdG, p.secondary.thresholdB, p.secondary.thresholdA = r, g, b, a
                    SmoothRefresh()
                end, true, 20)
            PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
            rgn._lastInline = swatch
            local swDis = CreateFrame("Frame", nil, rgn)
            swDis:SetAllPoints(swatch)
            swDis:SetFrameLevel(swatch:GetFrameLevel() + 5)
            local swDisTex = swDis:CreateTexture(nil, "OVERLAY")
            swDisTex:SetAllPoints()
            swDisTex:SetColorTexture(0.12, 0.12, 0.12, 0.75)
            swDis:EnableMouse(true)
            swDis:SetScript("OnEnter", function()
                local p = DB()
                if p and not p.secondary.enabled then
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Enable Class Resource"))
                else
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Threshold Color"))
                end
            end)
            swDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateSwDis2()
                local p = DB()
                if p and (not p.secondary.enabled or not p.secondary.thresholdEnabled) then swDis:Show() else swDis:Hide() end
            end
            swatch:HookScript("OnShow", UpdateSwDis2)
            EllesmereUI.RegisterWidgetRefresh(UpdateSwDis2)
            UpdateSwDis2()
        end
        -- Inline cog on Threshold Count for partial coloring toggle
        do
            local rgn = threshRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Threshold Coloring",
                rows = {
                    { type = "toggle", label = "Only Color At/Above Threshold",
                      get = function() local p = DB(); return p and p.secondary.thresholdPartialOnly end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.thresholdPartialOnly = v; RefreshClass()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                if IsBarTypeSecondary() then
                    EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("This option is not available for your spec"))
                else
                    EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("This option requires Threshold Color to be enabled"))
                end
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisThresh()
                local p = DB()
                if p and (not p.secondary.enabled or not p.secondary.thresholdEnabled or IsBarTypeSecondary()) then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisThresh)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisThresh)
            UpdateCogDisThresh()
        end

        -- Row 6: Anchored To | Anchor Position (inline DIRECTIONS cog)
        local classAnchorRow
        classAnchorRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Anchored To",
              disabled = classOff,
              disabledTooltip = "Enable Class Resource",
              values = {
                  none = "None", erb_powerbar = "Power Bar", erb_health = "Health Bar",
                  ["---1"] = "---",
                  erb_cdm = "CDM Cooldowns", mouse = "Mouse Cursor",
                  partyframe = "Party Frame", playerframe = "Player Frame", erb_castbar = "Cast Bar",
              },
              order = { "none", "erb_powerbar", "erb_health", "---1", "erb_cdm", "mouse", "partyframe", "playerframe", "erb_castbar" },
              getValue = function() local p = DB(); return p and p.secondary.anchorTo or "none" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.anchorTo = v; SmoothRefresh()
              end },
            { type = "dropdown", text = "Anchor Position",
              disabled = function() local p = DB(); return p and (not p.secondary.enabled or (p.secondary.anchorTo or "none") == "none") end,
              disabledTooltip = "Set Anchored To first",
              values = { left = "Left", right = "Right", top = "Top", bottom = "Bottom" },
              order = { "left", "right", "top", "bottom" },
              getValue = function() local p = DB(); return p and p.secondary.anchorPosition or "left" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.secondary.anchorPosition = v; SmoothRefresh()
              end }
        );  y = y - h
        -- Inline DIRECTIONS cog on Anchor Position for growth + x/y
        do
            local rgn = classAnchorRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Class Resource Anchor",
                rows = {
                    { type = "dropdown", label = "Growth",
                      values = { UP = "Up", DOWN = "Down", LEFT = "Left", RIGHT = "Right" },
                      order = { "UP", "DOWN", "LEFT", "RIGHT" },
                      disabled = function() local p = DB(); return p and (p.secondary.anchorTo or "none") == "mouse" end,
                      disabledTooltip = EllesmereUI.DisabledTooltip("Not available for Mouse Cursor anchor"),
                      get = function() local p = DB(); return p and p.secondary.growthDirection or "UP" end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.growthDirection = v; SmoothRefresh()
                      end },
                    { type = "toggle", label = "Grow Centered",
                      disabled = function() local p = DB(); return p and (p.secondary.anchorTo or "none") == "mouse" end,
                      disabledTooltip = EllesmereUI.DisabledTooltip("Not available for Mouse Cursor anchor"),
                      get = function() local p = DB(); return p and p.secondary.growCentered ~= false end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.growCentered = v; SmoothRefresh()
                      end },
                    { type = "slider", label = "X Offset", min = -125, max = 125, step = 1,
                      get = function() local p = DB(); return p and p.secondary.anchorX or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.anchorX = v; SmoothRefresh()
                      end },
                    { type = "slider", label = "Y Offset", min = -125, max = 125, step = 1,
                      get = function() local p = DB(); return p and p.secondary.anchorY or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.secondary.anchorY = v; SmoothRefresh()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Set Anchored To first"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateClassAnchorCogDis()
                local p = DB()
                if p and (not p.secondary.enabled or (p.secondary.anchorTo or "none") == "none") then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateClassAnchorCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateClassAnchorCogDis)
            UpdateClassAnchorCogDis()
        end

        _, h = W:Spacer(parent, y, 16);  y = y - h

        -----------------------------------------------------------------------
        --  POWER BAR
        -----------------------------------------------------------------------
        local powerSection
        powerSection, h = W:SectionHeader(parent, "POWER BAR", y);  y = y - h

        local noPrimaryPower = not HasPrimaryPower()
        local SPEC_DIS = "This option is not available for your spec"
        local powerOff = function()
            if noPrimaryPower then return true end
            local p = DB(); return p and not p.primary.enabled
        end
        local powerDisTip = function()
            if noPrimaryPower then return SPEC_DIS end
            return "Enable Power Bar"
        end

        -- Row 1: Show Power Bar | Orientation
        local powerEnableRow
        powerEnableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Power Bar",
              disabled = noPrimaryPower and function() return true end or nil,
              disabledTooltip = noPrimaryPower and SPEC_DIS or nil,
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

        -- Row 2: (Sync) Height | (Sync) Width
        local powerSizeRow
        powerSizeRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 30, step = 1,
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              getValue = function() local p = DB(); return p and p.primary.height or 16 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.height = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Width",
              min = 50, max = 350, step = 1,
              disabled = powerOff,
              disabledTooltip = powerDisTip,
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

        -- Row 3: (Sync) Border | (Sync) Opacity
        local powerBorderRow
        powerBorderRow, h = W:DualRow(parent, y,
            { type = "colorpicker", text = "Border", hasAlpha = true,
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              getValue = function()
                  local p = DB()
                  if not p then return 0, 0, 0, 1 end
                  return p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA
              end,
              setValue = function(r, g, b, a)
                  local p = DB(); if not p then return end
                  p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA = r, g, b, a
                  SmoothRefresh(); EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Opacity",
              min = 0, max = 100, step = 5,
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              getValue = function() local p = DB(); return math.floor((p and p.primary.barAlpha or 1) * 100 + 0.5) end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.barAlpha = v / 100; RefreshPower()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        _syncRows.powerBorder  = powerBorderRow._leftRegion
        _syncRows.powerOpacity = powerBorderRow._rightRegion
        -- Inline cog (RESIZE) on Border for border size
        do
            local rgn = powerBorderRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Border Size",
                rows = {
                    { type = "slider", label = "Size", min = 0, max = 4, step = 1,
                      get = function() local p = DB(); return p and p.primary.borderSize or 1 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.primary.borderSize = v; RebuildPower()
                          EllesmereUI:RefreshPage()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip(noPrimaryPower and SPEC_DIS or "Enable Power Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBorderCogDisP()
                if noPrimaryPower then cogDis:Show(); return end
                local p = DB()
                if p and not p.primary.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateBorderCogDisP)
            EllesmereUI.RegisterWidgetRefresh(UpdateBorderCogDisP)
            UpdateBorderCogDisP()
        end
        -- Sync icon on Border
        do
            local rgn = powerBorderRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Border to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local r, g, b, a = p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA
                    local sz = p.primary.borderSize or 1
                    p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA = r, g, b, a
                    p.secondary.borderSize = sz
                    p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA = r, g, b, a
                    p.health.borderSize = sz
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local sr, sg, sb, sa, ssz = p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA, p.primary.borderSize or 1
                    local function eq(t) return t.borderR == sr and t.borderG == sg and t.borderB == sb and t.borderA == sa and (t.borderSize or 1) == ssz end
                    return eq(p.secondary) and eq(p.health)
                end,
                flashTargets = function() return { _syncRows.powerBorder, _syncRows.classBorder, _syncRows.healthBorder } end,
            })
        end
        -- Sync icon on Opacity
        do
            local rgn = powerBorderRow._rightRegion
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

        -- Row 4: Power Colored Fill (inline swatch) | Power Text (inline cog RESIZE)
        local powerColorRow
        powerColorRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Power Colored Fill",
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              getValue = function() local p = DB(); return p and not p.primary.customColored end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.customColored = not v; RebuildPower()
                  EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Power Text",
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              values = { none = "None", smart = "Smart Text", curpp = "Power Value", perpp = "Power %", both = "Power Value | Power %" },
              order = { "none", "smart", "curpp", "perpp", "both" },
              getValue = function() local p = DB(); return p and p.primary.textFormat or "none" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.textFormat = v; RefreshPower()
              end }
        );  y = y - h
        -- Inline color swatch on Power Colored Fill
        do
            local rgn = powerColorRow._leftRegion
            local swatch, _ = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 2,
                function()
                    local p = DB()
                    if not p then return 0x23/255, 0x8F/255, 0xE7/255, 1 end
                    return p.primary.fillR, p.primary.fillG, p.primary.fillB, p.primary.fillA
                end,
                function(r, g, b, a)
                    local p = DB(); if not p then return end
                    p.primary.fillR, p.primary.fillG, p.primary.fillB, p.primary.fillA = r, g, b, a
                    RebuildPower(); SmoothRefresh()
                end, true, 20)
            PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
            rgn._lastInline = swatch
            local swDis = CreateFrame("Frame", nil, rgn)
            swDis:SetAllPoints(swatch)
            swDis:SetFrameLevel(swatch:GetFrameLevel() + 5)
            local swDisTex = swDis:CreateTexture(nil, "OVERLAY")
            swDisTex:SetAllPoints()
            swDisTex:SetColorTexture(0.12, 0.12, 0.12, 0.75)
            swDis:EnableMouse(true)
            swDis:SetScript("OnEnter", function()
                if noPrimaryPower then
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip(SPEC_DIS))
                    return
                end
                local p = DB()
                if p and not p.primary.enabled then
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Enable Power Bar"))
                else
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Power Colored Fill"))
                end
            end)
            swDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdatePowerSwDis()
                if noPrimaryPower then swDis:Show(); swatch:SetAlpha(0.3); return end
                local p = DB()
                if p and (not p.primary.enabled or not p.primary.customColored) then
                    swDis:Show(); swatch:SetAlpha(0.3)
                else
                    swDis:Hide(); swatch:SetAlpha(1)
                end
            end
            swatch:HookScript("OnShow", UpdatePowerSwDis)
            EllesmereUI.RegisterWidgetRefresh(UpdatePowerSwDis)
            UpdatePowerSwDis()
        end
        -- Inline cog (RESIZE) on Power Text for percent sign + text size + x/y offsets
        do
            local rgn = powerColorRow._rightRegion
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
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip(noPrimaryPower and SPEC_DIS or "Enable Power Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateCogDisP2()
                if noPrimaryPower then cogDis:Show(); return end
                local p = DB()
                if p and not p.primary.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateCogDisP2)
            EllesmereUI.RegisterWidgetRefresh(UpdateCogDisP2)
            UpdateCogDisP2()
        end

        -- Row 5: Threshold Color (inline swatch) | Threshold % (percent-based)
        local powerThreshRow
        powerThreshRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Threshold Color",
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              getValue = function() local p = DB(); return p and p.primary.thresholdEnabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.thresholdEnabled = v; RefreshPower()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Threshold %",
              min = 1, max = 99, step = 1,
              disabled = function()
                  if noPrimaryPower then return true end
                  local p = DB(); return p and (not p.primary.enabled or not p.primary.thresholdEnabled)
              end,
              disabledTooltip = function()
                  if noPrimaryPower then return SPEC_DIS end
                  local p = DB(); if p and not p.primary.enabled then return "Enable Power Bar" end
                  return "Enable Threshold Color first"
              end,
              getValue = function() local p = DB(); return p and p.primary.thresholdPct or 30 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.thresholdPct = v; RefreshPower()
              end }
        );  y = y - h
        -- Inline swatch on Threshold Color
        do
            local rgn = powerThreshRow._leftRegion
            local swatch, _ = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 2,
                function()
                    local p = DB()
                    if not p then return 1, 0.2, 0.2, 1 end
                    return p.primary.thresholdR, p.primary.thresholdG, p.primary.thresholdB, p.primary.thresholdA
                end,
                function(r, g, b, a)
                    local p = DB(); if not p then return end
                    p.primary.thresholdR, p.primary.thresholdG, p.primary.thresholdB, p.primary.thresholdA = r, g, b, a
                    SmoothRefresh()
                end, true, 20)
            PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
            rgn._lastInline = swatch
            local swDis = CreateFrame("Frame", nil, rgn)
            swDis:SetAllPoints(swatch)
            swDis:SetFrameLevel(swatch:GetFrameLevel() + 5)
            local swDisTex = swDis:CreateTexture(nil, "OVERLAY")
            swDisTex:SetAllPoints()
            swDisTex:SetColorTexture(0.12, 0.12, 0.12, 0.75)
            swDis:EnableMouse(true)
            swDis:SetScript("OnEnter", function()
                if noPrimaryPower then
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip(SPEC_DIS))
                    return
                end
                local p = DB()
                if p and not p.primary.enabled then
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Enable Power Bar"))
                else
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Threshold Color"))
                end
            end)
            swDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdatePowerThreshSwDis()
                if noPrimaryPower then swDis:Show(); return end
                local p = DB()
                if p and (not p.primary.enabled or not p.primary.thresholdEnabled) then swDis:Show() else swDis:Hide() end
            end
            swatch:HookScript("OnShow", UpdatePowerThreshSwDis)
            EllesmereUI.RegisterWidgetRefresh(UpdatePowerThreshSwDis)
            UpdatePowerThreshSwDis()
        end

        -- Row 6: Anchored To | Anchor Position (inline DIRECTIONS cog)
        local powerAnchorRow
        powerAnchorRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Anchored To",
              disabled = powerOff,
              disabledTooltip = powerDisTip,
              values = {
                  none = "None", erb_classresource = "Class Resource", erb_health = "Health Bar",
                  ["---1"] = "---",
                  erb_cdm = "CDM Cooldowns", mouse = "Mouse Cursor",
                  partyframe = "Party Frame", playerframe = "Player Frame", erb_castbar = "Cast Bar",
              },
              order = { "none", "erb_classresource", "erb_health", "---1", "erb_cdm", "mouse", "partyframe", "playerframe", "erb_castbar" },
              getValue = function() local p = DB(); return p and p.primary.anchorTo or "none" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.anchorTo = v; SmoothRefresh()
              end },
            { type = "dropdown", text = "Anchor Position",
              disabled = function()
                  if noPrimaryPower then return true end
                  local p = DB(); return p and (not p.primary.enabled or (p.primary.anchorTo or "none") == "none")
              end,
              disabledTooltip = function()
                  if noPrimaryPower then return SPEC_DIS end
                  return "Set Anchored To first"
              end,
              values = { left = "Left", right = "Right", top = "Top", bottom = "Bottom" },
              order = { "left", "right", "top", "bottom" },
              getValue = function() local p = DB(); return p and p.primary.anchorPosition or "left" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.primary.anchorPosition = v; SmoothRefresh()
              end }
        );  y = y - h
        -- Inline DIRECTIONS cog on Anchor Position for x/y
        do
            local rgn = powerAnchorRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Power Bar Anchor",
                rows = {
                    { type = "slider", label = "X Offset", min = -125, max = 125, step = 1,
                      get = function() local p = DB(); return p and p.primary.anchorX or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.primary.anchorX = v; SmoothRefresh()
                      end },
                    { type = "slider", label = "Y Offset", min = -125, max = 125, step = 1,
                      get = function() local p = DB(); return p and p.primary.anchorY or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.primary.anchorY = v; SmoothRefresh()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip(noPrimaryPower and SPEC_DIS or "Set Anchored To first"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdatePowerAnchorCogDis()
                if noPrimaryPower then cogDis:Show(); return end
                local p = DB()
                if p and (not p.primary.enabled or (p.primary.anchorTo or "none") == "none") then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdatePowerAnchorCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdatePowerAnchorCogDis)
            UpdatePowerAnchorCogDis()
        end

        _, h = W:Spacer(parent, y, 16);  y = y - h

        -----------------------------------------------------------------------
        --  HEALTH BAR
        -----------------------------------------------------------------------
        local healthSection
        healthSection, h = W:SectionHeader(parent, "HEALTH BAR", y);  y = y - h

        local healthOff = function() local p = DB(); return p and not p.health.enabled end

        -- Row 1: Show Health Bar | Orientation
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

        -- Row 2: (Sync) Height | (Sync) Width
        local healthSizeRow
        healthSizeRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 40, step = 1,
              disabled = healthOff,
              disabledTooltip = "Enable Health Bar",
              getValue = function() local p = DB(); return p and p.health.height or 20 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.height = v; SmoothRefresh()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Width",
              min = 50, max = 350, step = 1,
              disabled = healthOff,
              disabledTooltip = "Enable Health Bar",
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

        -- Row 3: (Sync) Border | (Sync) Opacity
        local healthBorderRow
        healthBorderRow, h = W:DualRow(parent, y,
            { type = "colorpicker", text = "Border", hasAlpha = true,
              disabled = healthOff,
              disabledTooltip = "Enable Health Bar",
              getValue = function()
                  local p = DB()
                  if not p then return 0, 0, 0, 1 end
                  return p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA
              end,
              setValue = function(r, g, b, a)
                  local p = DB(); if not p then return end
                  p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA = r, g, b, a
                  SmoothRefresh(); EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Opacity",
              min = 0, max = 100, step = 5,
              disabled = healthOff,
              disabledTooltip = "Enable Health Bar",
              getValue = function() local p = DB(); return math.floor((p and p.health.barAlpha or 1) * 100 + 0.5) end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.barAlpha = v / 100; RefreshHealth()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        _syncRows.healthBorder  = healthBorderRow._leftRegion
        _syncRows.healthOpacity = healthBorderRow._rightRegion
        -- Inline cog (RESIZE) on Border for border size
        do
            local rgn = healthBorderRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Border Size",
                rows = {
                    { type = "slider", label = "Size", min = 0, max = 4, step = 1,
                      get = function() local p = DB(); return p and p.health.borderSize or 1 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.health.borderSize = v; RebuildHealth()
                          EllesmereUI:RefreshPage()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Health Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBorderCogDisH()
                local p = DB()
                if p and not p.health.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateBorderCogDisH)
            EllesmereUI.RegisterWidgetRefresh(UpdateBorderCogDisH)
            UpdateBorderCogDisH()
        end
        -- Sync icon on Border
        do
            local rgn = healthBorderRow._leftRegion
            EllesmereUI.BuildSyncIcon({
                region  = rgn,
                tooltip = "Apply Border to all Bars",
                onClick = function()
                    local p = DB(); if not p then return end
                    local r, g, b, a = p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA
                    local sz = p.health.borderSize or 1
                    p.secondary.borderR, p.secondary.borderG, p.secondary.borderB, p.secondary.borderA = r, g, b, a
                    p.secondary.borderSize = sz
                    p.primary.borderR, p.primary.borderG, p.primary.borderB, p.primary.borderA = r, g, b, a
                    p.primary.borderSize = sz
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end,
                isSynced = function()
                    local p = DB(); if not p then return false end
                    local sr, sg, sb, sa, ssz = p.health.borderR, p.health.borderG, p.health.borderB, p.health.borderA, p.health.borderSize or 1
                    local function eq(t) return t.borderR == sr and t.borderG == sg and t.borderB == sb and t.borderA == sa and (t.borderSize or 1) == ssz end
                    return eq(p.secondary) and eq(p.primary)
                end,
                flashTargets = function() return { _syncRows.healthBorder, _syncRows.classBorder, _syncRows.powerBorder } end,
            })
        end
        -- Sync icon on Opacity
        do
            local rgn = healthBorderRow._rightRegion
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

        -- Row 4: Health Colored Fill (inline swatch) | Health Text (inline cog RESIZE)
        local healthColorRow
        healthColorRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Health Colored Fill",
              disabled = healthOff,
              disabledTooltip = "Enable Health Bar",
              getValue = function() local p = DB(); return p and p.health.customColored end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.customColored = v
                  if v and p.health.darkTheme then p.health.darkTheme = false end
                  RebuildHealth(); EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Health Text",
              disabled = healthOff,
              disabledTooltip = "Enable Health Bar",
              values = { none = "None", perhp = "Health %", perhpnosign = "Health % (No Sign)", curhpshort = "Health #", perhpnum = "Health % | #", both = "Health # | %" },
              order = { "none", "---", "perhp", "perhpnosign", "curhpshort", "perhpnum", "both" },
              getValue = function() local p = DB(); return p and p.health.textFormat or "none" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.textFormat = v; RefreshHealth()
              end }
        );  y = y - h
        -- Inline color swatch on Health Colored Fill
        do
            local rgn = healthColorRow._leftRegion
            local swatch, _ = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 2,
                function()
                    local p = DB()
                    if not p then return 0x40/255, 0xD9/255, 0x67/255, 1 end
                    return p.health.fillR, p.health.fillG, p.health.fillB, p.health.fillA
                end,
                function(r, g, b, a)
                    local p = DB(); if not p then return end
                    p.health.fillR, p.health.fillG, p.health.fillB, p.health.fillA = r, g, b, a
                    if not p.health.customColored then p.health.customColored = true end
                    if p.health.darkTheme then p.health.darkTheme = false end
                    SmoothRefresh(); EllesmereUI:RefreshPage()
                end, true, 20)
            PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
            rgn._lastInline = swatch
            local swDis = CreateFrame("Frame", nil, rgn)
            swDis:SetAllPoints(swatch)
            swDis:SetFrameLevel(swatch:GetFrameLevel() + 5)
            local swDisTex = swDis:CreateTexture(nil, "OVERLAY")
            swDisTex:SetAllPoints()
            swDisTex:SetColorTexture(0.12, 0.12, 0.12, 0.75)
            swDis:EnableMouse(true)
            swDis:SetScript("OnEnter", function()
                local p = DB()
                if p and not p.health.enabled then
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Enable Health Bar"))
                else
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Health Colored Fill"))
                end
            end)
            swDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateHealthSwDis()
                local p = DB()
                if p and (not p.health.enabled or not p.health.customColored) then
                    swDis:Show(); swatch:SetAlpha(0.3)
                else
                    swDis:Hide(); swatch:SetAlpha(1)
                end
            end
            swatch:HookScript("OnShow", UpdateHealthSwDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateHealthSwDis)
            UpdateHealthSwDis()
        end
        -- Inline cog (RESIZE) on Health Text for text size + x/y offsets
        do
            local rgn = healthColorRow._rightRegion
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
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
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

        -- Row 5: Threshold Color (inline swatch) | Threshold % (percent-based)
        local healthThreshRow
        healthThreshRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Threshold Color",
              disabled = healthOff,
              disabledTooltip = "Enable Health Bar",
              getValue = function() local p = DB(); return p and p.health.thresholdEnabled end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.thresholdEnabled = v; RefreshHealth()
                  EllesmereUI:RefreshPage()
              end },
            { type = "slider", text = "Threshold %",
              min = 1, max = 99, step = 1,
              disabled = function() local p = DB(); return p and (not p.health.enabled or not p.health.thresholdEnabled) end,
              disabledTooltip = function() local p = DB(); if p and not p.health.enabled then return "Enable Health Bar" end; return "Enable Threshold Color first" end,
              getValue = function() local p = DB(); return p and p.health.thresholdPct or 30 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.thresholdPct = v; RefreshHealth()
              end }
        );  y = y - h
        -- Inline swatch on Threshold Color
        do
            local rgn = healthThreshRow._leftRegion
            local swatch, _ = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 2,
                function()
                    local p = DB()
                    if not p then return 1, 0.2, 0.2, 1 end
                    return p.health.thresholdR, p.health.thresholdG, p.health.thresholdB, p.health.thresholdA
                end,
                function(r, g, b, a)
                    local p = DB(); if not p then return end
                    p.health.thresholdR, p.health.thresholdG, p.health.thresholdB, p.health.thresholdA = r, g, b, a
                    SmoothRefresh()
                end, true, 20)
            PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
            rgn._lastInline = swatch
            local swDis = CreateFrame("Frame", nil, rgn)
            swDis:SetAllPoints(swatch)
            swDis:SetFrameLevel(swatch:GetFrameLevel() + 5)
            local swDisTex = swDis:CreateTexture(nil, "OVERLAY")
            swDisTex:SetAllPoints()
            swDisTex:SetColorTexture(0.12, 0.12, 0.12, 0.75)
            swDis:EnableMouse(true)
            swDis:SetScript("OnEnter", function()
                local p = DB()
                if p and not p.health.enabled then
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Enable Health Bar"))
                else
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Threshold Color"))
                end
            end)
            swDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateHealthThreshSwDis()
                local p = DB()
                if p and (not p.health.enabled or not p.health.thresholdEnabled) then swDis:Show() else swDis:Hide() end
            end
            swatch:HookScript("OnShow", UpdateHealthThreshSwDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateHealthThreshSwDis)
            UpdateHealthThreshSwDis()
        end

        -- Row 6: Anchored To | Anchor Position (inline DIRECTIONS cog)
        local healthAnchorRow
        healthAnchorRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Anchored To",
              disabled = healthOff,
              disabledTooltip = "Enable Health Bar",
              values = {
                  none = "None", erb_classresource = "Class Resource", erb_powerbar = "Power Bar",
                  ["---1"] = "---",
                  erb_cdm = "CDM Cooldowns", mouse = "Mouse Cursor",
                  partyframe = "Party Frame", playerframe = "Player Frame", erb_castbar = "Cast Bar",
              },
              order = { "none", "erb_classresource", "erb_powerbar", "---1", "erb_cdm", "mouse", "partyframe", "playerframe", "erb_castbar" },
              getValue = function() local p = DB(); return p and p.health.anchorTo or "none" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.anchorTo = v; SmoothRefresh()
              end },
            { type = "dropdown", text = "Anchor Position",
              disabled = function() local p = DB(); return p and (not p.health.enabled or (p.health.anchorTo or "none") == "none") end,
              disabledTooltip = "Set Anchored To first",
              values = { left = "Left", right = "Right", top = "Top", bottom = "Bottom" },
              order = { "left", "right", "top", "bottom" },
              getValue = function() local p = DB(); return p and p.health.anchorPosition or "left" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.health.anchorPosition = v; SmoothRefresh()
              end }
        );  y = y - h
        -- Inline DIRECTIONS cog on Anchor Position for x/y
        do
            local rgn = healthAnchorRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Health Bar Anchor",
                rows = {
                    { type = "slider", label = "X Offset", min = -125, max = 125, step = 1,
                      get = function() local p = DB(); return p and p.health.anchorX or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.health.anchorX = v; SmoothRefresh()
                      end },
                    { type = "slider", label = "Y Offset", min = -125, max = 125, step = 1,
                      get = function() local p = DB(); return p and p.health.anchorY or 0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.health.anchorY = v; SmoothRefresh()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.DIRECTIONS_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Set Anchored To first"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateHealthAnchorCogDis()
                local p = DB()
                if p and (not p.health.enabled or (p.health.anchorTo or "none") == "none") then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateHealthAnchorCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateHealthAnchorCogDis)
            UpdateHealthAnchorCogDis()
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
                p.health.offsetX = 0;   p.health.offsetY = -64;   p.health.unlockPos = nil; p.health.scale = 1.0
                p.primary.offsetX = 0;  p.primary.offsetY = -52; p.primary.unlockPos = nil; p.primary.scale = 1.0
                p.secondary.offsetX = 0; p.secondary.offsetY = -38; p.secondary.unlockPos = nil; p.secondary.scale = 1.0
                p.secondary.countTextUnlockPos = nil
                p.castBar.unlockPos = nil; p.castBar.anchorX = 0; p.castBar.anchorY = -50
                Refresh()
            end,
            nil,
            "Click to reset all element positions and scales to defaults"
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
        pf.container:ClearAllPoints(); pf.container:SetPoint("CENTER", pf.container:GetParent(), "CENTER", 0, 0)
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
        end

        -- Border (pixel-perfect via PP)
        local PP = EllesmereUI.PP
        if PP and pf.barFrame._ppBorders then
            PP.UpdateBorder(pf.barFrame, bs, cb.borderR, cb.borderG, cb.borderB, cb.borderA)
        end

        -- Status bar inset: snap to container's pixel grid
        local inset = Snap(bs)
        pf.bar:ClearAllPoints()
        pf.bar:SetPoint("TOPLEFT", pf.barFrame, "TOPLEFT", inset, -inset)
        pf.bar:SetPoint("BOTTOMRIGHT", pf.barFrame, "BOTTOMRIGHT", -inset, inset)
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
        if cb.gradientEnabled then
            local dir = cb.gradientDir or "HORIZONTAL"
            fillTex:SetGradient(dir, CreateColor(cb.fillR, cb.fillG, cb.fillB, cb.fillA), CreateColor(cb.gradientR, cb.gradientG, cb.gradientB, cb.gradientA))
        else
            fillTex:SetVertexColor(cb.fillR, cb.fillG, cb.fillB, cb.fillA)
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

        -- Icon: left side of container, flush against the edge (hidden when showIcon is off)
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
        container:SetScale(previewScale)

        -- Snap helper: round to the preview container's physical pixel grid
        local cScale = container:GetEffectiveScale()
        if cScale <= 0 then cScale = 1 end
        local function Snap(val)
            return math.floor(val * cScale + 0.5) / cScale
        end

        local w, h = Snap(cb.width), Snap(cb.height)
        local hasIcon = cb.showIcon ~= false
        local iconW = hasIcon and Snap(h) or 0
        container:SetSize(w + iconW, h)

        -- Bar frame (holds bg, border, status bar)
        local barFrame = CreateFrame("Frame", nil, container)
        barFrame:SetSize(w, h)
        barFrame:SetPoint("LEFT", container, "LEFT", iconW, 0)
        _castBarPreviewFrames.barFrame = barFrame
        _castBarPreviewFrames.container = container

        -- Background
        local bg = barFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local texKey = cb.texture
        if texKey == "blizzard" then
            bg:SetAtlas("UI-CastingBar-Background", true)
        else
            bg:SetColorTexture(cb.bgR, cb.bgG, cb.bgB, cb.bgA)
        end
        _castBarPreviewFrames.bg = bg

        -- Border (pixel-perfect via PP)
        local bs = cb.borderSize
        local PP = EllesmereUI.PP
        PP.CreateBorder(barFrame, cb.borderR, cb.borderG, cb.borderB, cb.borderA, bs, "BORDER", 7)

        -- Status bar (inset by border size, snapped to container pixel grid)
        local inset = Snap(bs)
        local bar = CreateFrame("StatusBar", nil, barFrame)
        bar:SetPoint("TOPLEFT", barFrame, "TOPLEFT", inset, -inset)
        bar:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", -inset, inset)
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
        spark:SetTexture("Interface\\AddOns\\EllesmereUINameplates\\Media\\cast_spark.tga")
        spark:SetBlendMode("ADD")
        spark:SetSize(8, h)
        spark:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
        if not cb.showSpark then spark:Hide() end
        _castBarPreviewFrames.spark = spark

        -- Icon: left side of container, flush against the edge (hidden when showIcon is off)
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
                    { type = "slider", label = "Scale", min = 0.5, max = 3, step = 0.05,
                      get = function() local p = DB(); return p and p.castBar.scale or 1.0 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.scale = v; RefreshCast()
                      end },
                },
                footer = { unlockKey = "ERB_CastBar" },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
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
        classSizeRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Height",
              min = 1, max = 60, step = 1,
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.height or 20 end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.height = v; RefreshCast()
              end },
            { type = "slider", text = "Width",
              min = 50, max = 500, step = 1,
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
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

        -- Row 3: Border (cog RESIZE: size) | Show Spark
        local castBorderRow
        castBorderRow, h = W:DualRow(parent, y,
            { type = "colorpicker", text = "Border", hasAlpha = true,
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              getValue = function()
                  local p = DB()
                  if not p then return 0, 0, 0, 1 end
                  return p.castBar.borderR, p.castBar.borderG, p.castBar.borderB, p.castBar.borderA
              end,
              setValue = function(r, g, b, a)
                  local p = DB(); if not p then return end
                  p.castBar.borderR, p.castBar.borderG, p.castBar.borderB, p.castBar.borderA = r, g, b, a
                  RefreshCast(); EllesmereUI:RefreshPage()
              end },
            { type = "toggle", text = "Show Spark",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.showSpark end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showSpark = v; RefreshCast()
              end }
        );  y = y - h
        -- Inline cog (RESIZE) on Border for border size
        do
            local rgn = castBorderRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Border Size",
                rows = {
                    { type = "slider", label = "Size", min = 0, max = 4, step = 1,
                      get = function() local p = DB(); return p and p.castBar.borderSize or 1 end,
                      set = function(v)
                          local p = DB(); if not p then return end
                          p.castBar.borderSize = v; RefreshCast()
                          EllesmereUI:RefreshPage()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
            local cogDis = CreateFrame("Frame", nil, rgn)
            cogDis:SetAllPoints(cogBtn)
            cogDis:SetFrameLevel(cogBtn:GetFrameLevel() + 5)
            cogDis:EnableMouse(true)
            cogDis:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Player Cast Bar"))
            end)
            cogDis:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateBorderCogDis()
                local p = DB()
                if p and not p.castBar.enabled then cogDis:Show() else cogDis:Hide() end
            end
            cogBtn:HookScript("OnShow", UpdateBorderCogDis)
            EllesmereUI.RegisterWidgetRefresh(UpdateBorderCogDis)
            UpdateBorderCogDis()
        end

        -- Row 4: Custom Color (multiSwatch + cog: gradient) | Bar Texture
        local castColorRow
        castColorRow, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Custom Color",
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
                  { tooltip = "Main Color", hasAlpha = true,
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
                        RefreshCast()
                    end },
              } },
            { type = "dropdown", text = "Bar Texture",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              values = texValues, order = texOrder,
              getValue = function() local p = DB(); return p and p.castBar.texture or "none" end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.texture = v; RefreshCast()
              end }
        );  y = y - h
        -- Inline cog on Custom Color for gradient settings
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
            local swatch = castColorRow._leftRegion._control
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

        -- Row 5: Spell Text (cog RESIZE: text size + x/y) | Duration Text (cog RESIZE: timer size + x/y)
        local textRow
        textRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Spell Text",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.showSpellText end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showSpellText = v; RefreshCast()
              end },
            { type = "toggle", text = "Duration Text",
              disabled = castOff,
              disabledTooltip = "Enable Player Cast Bar",
              getValue = function() local p = DB(); return p and p.castBar.showTimer end,
              setValue = function(v)
                  local p = DB(); if not p then return end
                  p.castBar.showTimer = v; RefreshCast()
              end }
        );  y = y - h
        -- Inline cog (RESIZE) on Spell Text for text size + x/y
        do
            local rgn = textRow._leftRegion
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
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
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
        -- Inline cog (RESIZE) on Duration Text for timer size + x/y
        do
            local rgn = textRow._rightRegion
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
            local cogBtn = MakeCogBtn(rgn, cogShow, nil, EllesmereUI.RESIZE_ICON)
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
