if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ResourceBars_Build.lua
--
--  Tick marks, hash lines, the Ironfur overlay and BuildBars.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local PP = EllesmereUI.PP
local UnitHealthMax, UnitPowerMax = UnitHealthMax, UnitPowerMax

local CLASS_COLORS, DARK_BG_A, DARK_FILL_A = I.CLASS_COLORS, I.DARK_BG_A, I.DARK_FILL_A
local ERB, GetPrimaryPowerType, GetRBFont = I.ERB, I.GetPrimaryPowerType, I.GetRBFont
local GetSecondaryResource, IP, POWER_COLORS = I.GetSecondaryResource, I.IP, I.POWER_COLORS
local SetRBFont, SnapXY = I.SetRBFont, I.SnapXY
local ResolveThresholdSpecEntry, DEFAULTS = I.ResolveThresholdSpecEntry, I.DEFAULTS
local ApplyBarFlat, ApplyBarGradient = I.ApplyBarFlat, I.ApplyBarGradient
local ApplyBarOrientation, ApplyBarTexture = I.ApplyBarOrientation, I.ApplyBarTexture
local BuildMainFrame, CalcPipGeometry = I.BuildMainFrame, I.CalcPipGeometry
local CreatePip, CreateStatusBar = I.CreatePip, I.CreateStatusBar
local IsPowerBarHidden, IsSpecDisabled = I.IsPowerBarHidden, I.IsSpecDisabled
local MakePixelBorder, OrientedSize, pips = I.MakePixelBorder, I.OrientedSize, I.pips
local runeFrames, secondaryBarTicks = I.runeFrames, I.secondaryBarTicks
local secondaryPipTicks, SmoothBarAnimate = I.secondaryPipTicks, I.SmoothBarAnimate
local ApplyBarAnchor, ApplyFreeBarPosition = I.ApplyBarAnchor, I.ApplyFreeBarPosition
local GetAnchorOffsets, NormalizeAnchorKey = I.GetAnchorOffsets, I.NormalizeAnchorKey
local ReapplyInternalBarAnchors = I.ReapplyInternalBarAnchors
local ResolveExpandDirSign = I.ResolveExpandDirSign

local mainFrame
I.mainFrameSetters[#I.mainFrameSetters + 1] = function(v) mainFrame = v end
local healthBar
I.healthBarSetters[#I.healthBarSetters + 1] = function(v) healthBar = v end
local primaryBar
I.primaryBarSetters[#I.primaryBarSetters + 1] = function(v) primaryBar = v end
local secondaryFrame
I.secondaryFrameSetters[#I.secondaryFrameSetters + 1] = function(v) secondaryFrame = v end
local secondaryBar  -- bar-style secondary (e.g. Devourer soul fragments, Elemental maelstrom)
I.secondaryBarSetters[#I.secondaryBarSetters + 1] = function(v) secondaryBar = v end
local castBarFrame
I.castBarFrameSetters[#I.castBarFrameSetters + 1] = function(v) castBarFrame = v end
local cachedClass
I.cachedClassSetters[#I.cachedClassSetters + 1] = function(v) cachedClass = v end
local cachedPrimary
I.cachedPrimarySetters[#I.cachedPrimarySetters + 1] = function(v) cachedPrimary = v end
local cachedSecondary
I.cachedSecondarySetters[#I.cachedSecondarySetters + 1] = function(v) cachedSecondary = v end

-- Resource bar tick marks (bar-type secondary only)

-- Parse comma-separated tick values string into a table of numbers.
local function ParseTickValues(str)
    if not str or str == "" then return nil end
    local vals = {}
    for s in str:gmatch("[^,]+") do
        local n = tonumber(s:match("^%s*(.-)%s*$"))
        if n and n > 0 then vals[#vals + 1] = n end
    end
    if #vals == 0 then return nil end
    return vals
end

-- ApplyResourceBarTicks(sb, maxVal, tickStr, tickCache, hashWidth=1, hashR/G/B/A=
-- white, hashIsPercent, maxRenderVal, vInset). hashIsPercent: frac=v/100 not
-- v/maxVal (bar-type only; pips always use counts). maxRenderVal: suppress ticks past
-- that value-position (Devourer in Void Meta caps at 39). vInset: vertical shrink so
-- hash lines sit inside the border (default 0, callers pass borderSize*PP.mult).
-- HideResourceBarTicks hides a cache from OUTSIDE this function on branch switches
-- (pips/runes/Ironfur/Ignore Pain hide BAR ticks; bar branch hides PIP ticks). It must
-- also clear owner._tickState/._hashApplied: ApplyResourceBarTicks and
-- UpdateSecondaryResource both memo/gate on those, so without the clear the next
-- IDENTICAL call is a no-op and ticks never return (e.g. Balance Druid cat/bear back to
-- Moonkin hits the same memo). Branch-switch edge only.
local function HideResourceBarTicks(tickCache, owner)
    for i = 1, #tickCache do tickCache[i]:Hide() end
    if owner then
        owner._tickState = nil     -- ApplyResourceBarTicks' layout memo
        owner._hashApplied = nil   -- UpdateSecondaryResource's re-apply gate
    end
end

local function ApplyResourceBarTicks(sb, maxVal, tickStr, tickCache, hashWidth, hashR, hashG, hashB, hashA, hashIsPercent, maxRenderVal, vInset)
    -- UNIT_POWER_FREQUENT drives this several times a second, but tick layout is a
    -- pure function of the args plus the bar's size/pixel multiplier -- never the
    -- live resource value. Without this guard every tick texture is torn down and
    -- rebuilt continuously.
    -- Orientation: a plain container (the pip/rune strip, secondaryFrame)
    -- carries a stamped token (_ticksOri, written beside the pip layout --
    -- it has no inner StatusBar for the probe below to read); bar-type
    -- callers resolve through their inner StatusBar. Vertical bars lay ticks
    -- ALONG Y as horizontal strips; reverse fill / VERTICAL_DOWN measures
    -- from the top, matching the pip slot mapping and ApplyBarOrientation.
    local vert, revFill
    local oriTok = sb and sb._ticksOri
    if oriTok then
        vert = oriTok ~= "HORIZONTAL"
        revFill = oriTok == "VERTICAL_DOWN" or oriTok == "VERTICAL"
    else
        local oriSb = sb and (sb._sb or (sb.GetOrientation and sb))
        vert = (oriSb and oriSb.GetOrientation
            and oriSb:GetOrientation() == "VERTICAL") or false
        revFill = (vert and oriSb.GetReverseFill and oriSb:GetReverseFill()) or false
    end
    if sb then
        local _pp = EllesmereUI and EllesmereUI.PP
        local w, h = sb:GetWidth(), sb:GetHeight()
        local mult = (_pp and _pp.mult) or 1
        local st = sb._tickState
        if st and st.maxVal == maxVal and st.tickStr == tickStr and st.hw == hashWidth
           and st.r == hashR and st.g == hashG and st.b == hashB and st.a == hashA
           and st.pct == hashIsPercent and st.cap == maxRenderVal and st.vi == vInset
           and st.w == w and st.h == h and st.mult == mult
           and st.vert == vert and st.rev == revFill then
            return
        end
        if not st then st = {}; sb._tickState = st end
        st.maxVal, st.tickStr, st.hw = maxVal, tickStr, hashWidth
        st.r, st.g, st.b, st.a = hashR, hashG, hashB, hashA
        st.pct, st.cap, st.vi = hashIsPercent, maxRenderVal, vInset
        st.w, st.h, st.mult = w, h, mult
        st.vert, st.rev = vert, revFill
    end

    local vals = ParseTickValues(tickStr)

    for i = 1, #tickCache do tickCache[i]:Hide() end

    if not vals or not sb or maxVal <= 0 then return end

    local PP = EllesmereUI and EllesmereUI.PP
    local tickW = hashWidth or 1
    local tR, tG, tB, tA = hashR or 1, hashG or 1, hashB or 1, hashA or 0.7

    -- Tick textures must live ABOVE the inner StatusBar (_sb) or the fill covers
    -- them: overlay frame on the outer container, one level above the inner bar.
    if not sb._tickOverlay then
        local ov = CreateFrame("Frame", nil, sb)
        ov:SetAllPoints()
        local innerSb = sb._sb
        if innerSb then
            ov:SetFrameLevel(innerSb:GetFrameLevel() + 1)
        end
        sb._tickOverlay = ov
    end
    local tickParent = sb._tickOverlay

    -- Create tick textures as needed
    while #tickCache < #vals do
        local t = tickParent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        tickCache[#tickCache + 1] = t
    end

    local pxW = PP and (tickW * PP.mult) or tickW
    local barW = sb:GetWidth()
    local barH = sb:GetHeight()
    local vI = vInset or 0
    -- Clamp so a fat border on a short bar can never invert the cross-axis
    -- span (the inset shrinks the tick along whichever axis it spans).
    if vert then
        if vI * 2 >= barW then vI = math.max(0, (barW - 1) / 2) end
    else
        if vI * 2 >= barH then vI = math.max(0, (barH - 1) / 2) end
    end
    local tickH = barH - vI * 2
    for i, v in ipairs(vals) do
        local frac, inRange
        if hashIsPercent then
            inRange = (v <= 100)
            frac = v / 100
        else
            inRange = (v <= maxVal)
            frac = v / maxVal
        end
        -- Optional value-position cap (e.g. Devourer in Void Meta: nothing > 39).
        if maxRenderVal and inRange then
            local valPos = hashIsPercent and (frac * maxVal) or v
            if valPos > maxRenderVal then inRange = false end
        end
        if inRange then
            local t = tickCache[i]
            t:SetColorTexture(tR, tG, tB, tA)
            t:ClearAllPoints()
            if vert then
                local off = PP and PP.Scale(barH * frac) or (barH * frac)
                off = math.max(0, math.min(off, PP and PP.Scale(barH - pxW) or (barH - pxW)))
                t:SetSize(barW - vI * 2, pxW)
                if revFill then
                    t:SetPoint("TOPLEFT", sb, "TOPLEFT", vI, -off)
                else
                    t:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", vI, off)
                end
            else
                local off = PP and PP.Scale(barW * frac) or (barW * frac)
                off = math.max(0, math.min(off, PP and PP.Scale(barW - pxW) or (barW - pxW)))
                t:SetSize(pxW, tickH)
                t:SetPoint("TOPLEFT", sb, "TOPLEFT", off, -vI)
            end
            t:Show()
        end
    end
end

-- Value mode needs a readable max: getMaxFn returns the current max; if it is
-- secret, fall back to the last-known-good value cached on the bar frame.
-- Source: the active threshold entry when it has its own hash lines, else the
-- bar-wide hashEnabled/hashValues (which conditional overrides can set).
function ns.ApplyHashLines(sb, cfg, getMaxFn)
    if not sb then return end
    local tickCache = sb._userHashTicks
    local ent = cfg and ResolveThresholdSpecEntry(cfg)
    if not (ent and ent.hashValues and ent.hashValues ~= "") then
        ent = cfg and cfg.hashEnabled and cfg or nil
    end
    local hashStr = ent and ent.hashValues
    if not hashStr or hashStr == "" then
        if tickCache then HideResourceBarTicks(tickCache, sb) end
        return
    end
    if not tickCache then tickCache = {}; sb._userHashTicks = tickCache end
    local isPercent = (ent.hashMode or "percent") == "percent"
    local maxVal
    if isPercent then
        maxVal = 100
    else
        local mx = getMaxFn and getMaxFn() or nil
        if mx and issecretvalue and issecretvalue(mx) then mx = nil end
        if mx and mx > 0 then
            sb._hashMaxCache = mx
        else
            mx = sb._hashMaxCache  -- last-known-good, or nil on first secret read
        end
        maxVal = mx or 0
    end
    -- Shrink the hash vertically by the border so it sits inside the bar. An
    -- exact SOLID border size is the inset; a textured one keeps its step.
    local PP = EllesmereUI and EllesmereUI.PP
    local hbs = cfg.borderSize or 0
    local htex = cfg.borderTexture
    if not htex or htex == "" or htex == "solid" then
        hbs = EllesmereUI.BorderPx(cfg.borderSizePx, hbs, htex) or hbs
    end
    local vInset = hbs * ((PP and PP.mult) or 1)
    ApplyResourceBarTicks(sb, maxVal, hashStr, tickCache,
        ent.hashWidth, ent.hashColorR, ent.hashColorG, ent.hashColorB, ent.hashColorA,
        isPercent, nil, vInset)
end

-- Moving-hash overlay for the Guardian Ironfur bar, above the inner StatusBar fill so
-- ticks are never covered. Ticks pool in ironfurTickTex (secondaryBar is a singleton).
local ironfurTickTex = {}
local function EnsureIronfurOverlay(sb)
    if sb._ifOverlay then return sb._ifOverlay end
    local ov = CreateFrame("Frame", nil, sb)
    ov:SetAllPoints()
    local innerSb = sb._sb
    if innerSb then ov:SetFrameLevel(innerSb:GetFrameLevel() + 2) end
    sb._ifOverlay = ov
    return ov
end

-- BuildBars -- applies per-element scale, border, colors, text positioning
-- Rounded corners (EllesmereUI_RoundedCorners.lua; nothing at radius 0 or
-- under the stock styles, which shape the bars with their own masks).
-- Health / power: the outer frame is the shape, the clipping inner bar the body.
function ns.ERB_RoundBar(bar, cfg)
    if not bar then return end
    local radius = (not ns.ERB_BarsBlizz() and cfg.cornerRadius) or 0
    if radius <= 0 then EllesmereUI.RoundCorners(bar, 0); return end
    EllesmereUI.RoundCorners(bar, radius, {
        roots = { bar._sb }, clip = bar._sb,
        border = bar._border and bar._border._frame, style = cfg.borderTexture or "solid",
        corners = cfg.cornerMask,
    })
end
-- Class resource: the whole row rounds its outline; with Border on Pips each
-- shown pip (or rune) also rounds inside its own border (pips only show from
-- BuildBars, before this runs). The pip loop runs only while pips are rounded
-- or were rounded before.
do
    local pipsRounded = false
    local function RoundPipList(list, radius, style, corners)
        for i = 1, #list do
            local pip = list[i]
            if radius <= 0 then
                EllesmereUI.RoundCorners(pip, 0)
            elseif pip:IsShown() then
                EllesmereUI.RoundCorners(pip, radius, {
                    style = style, border = pip._border and pip._border._frame,
                    corners = corners,
                })
            end
        end
    end
    function ns.ERB_RoundSecondary(sp, isBarType)
        local radius = (not ns.ERB_BarsBlizz() and sp.cornerRadius) or 0
        local style = sp.borderTexture or "solid"
        local onPips = sp.borderOnPips and not isBarType
        local rowBorder = secondaryFrame._barBorder
        if radius > 0 then
            EllesmereUI.RoundCorners(secondaryFrame, radius, {
                style = style,
                border = not onPips and rowBorder and rowBorder._frame or nil,
                clip = isBarType and secondaryBar and secondaryBar._sb or nil,
                corners = sp.cornerMask,
            })
        else
            EllesmereUI.RoundCorners(secondaryFrame, 0)
        end
        local pipRadius = onPips and radius or 0
        if pipRadius > 0 or pipsRounded then
            RoundPipList(pips, pipRadius, style, sp.cornerMask)
            RoundPipList(runeFrames, pipRadius, style, sp.cornerMask)
            pipsRounded = pipRadius > 0
        end
    end
end

local function BuildBars()
    -- Frames are being recreated, so every value/config cache keyed on the previous
    -- ones is stale. Bumping the generation invalidates them all at once; without
    -- it, a rebuild that leaves the resource value unchanged lets
    -- UpdateSecondaryResource early-out and the new pips stay unpopulated.
    ns.CfgGen = (ns.CfgGen or 0) + 1
    local p = ERB.db.profile

    -- If the profile is missing critical sub-tables, reset to defaults
    if type(p.primary) ~= "table" or type(p.secondary) ~= "table"
    or type(p.general) ~= "table" then
        ERB.db:ResetProfile()
        p = ERB.db.profile
    end

    local g = p.general or DEFAULTS.profile.general

    if not mainFrame then BuildMainFrame() end

    -- Classic "Border Around All": read once per build; the visibility pass
    -- that follows every build re-judges the group from the new layout.
    ns._erbGroupOn = ns.ERB_GroupSettingOn(p)
    ns._erbGrpGeomDirty = true

    -- Clear animation state so DB values are always authoritative on a fresh build
    local _animClearKeys = { "scale", "ox", "oy", "w", "h" }
    for _, _animBar in ipairs({ healthBar, primaryBar, secondaryFrame, castBarFrame }) do
        if _animBar then
            for _, _k in ipairs(_animClearKeys) do
                _animBar["_barAnim_" .. _k] = nil
            end
        end
    end

    -- Fallback defaults for nil-safe reads
    local FALLBACK = DEFAULTS.profile

    -- Health bar
    local hp = _G._ERB_ResolveHealthCfg(p) or FALLBACK.health
    -- Snap width/height to a whole number of physical pixels: SnapForES (round to
    -- nearest), NOT PP.Scale (truncate) -- see the Power bar note below.
    local hpWidth = hp.width or 214
    local hpHeight = hp.height or 16
    local _hpEs = (healthBar and healthBar:GetEffectiveScale()) or (UIParent and UIParent:GetEffectiveScale()) or 1
    if PP and PP.SnapForES then
        hpWidth = PP.SnapForES(hpWidth, _hpEs)
        hpHeight = PP.SnapForES(hpHeight, _hpEs)
    end
    do
        local hpOri = hp.orientation or g.orientation or "HORIZONTAL"
        if not healthBar then
            I.SetHealthBar(CreateStatusBar(mainFrame, "ERB_HealthBar", hpWidth, hpHeight,
                hp.borderSize, hp.borderR, hp.borderG, hp.borderB, hp.borderA))
            healthBar:SetFrameStrata(hp.frameStrata or g.frameStrata or "MEDIUM")
            healthBar:SetFrameLevel(10)
        end
        if not hp.enabled then
            -- Disabled: keep frame positioned at zero alpha for anchors
            local ow, oh = OrientedSize(hpWidth, hpHeight, hpOri)
            healthBar:SetSize(ow, oh)
            healthBar:Show()
            if EllesmereUI._TryOverrideAnchor and EllesmereUI._TryOverrideAnchor("ERB_Health", healthBar) then
                -- Override anchor owns position (zero-alpha anchor target)
            elseif hp.unlockPos and hp.unlockPos.point then
                local rp = hp.unlockPos.relPoint or hp.unlockPos.point
                local sx, sy = SnapXY(hp.unlockPos.x, hp.unlockPos.y, healthBar, hp.unlockPos)
                healthBar:ClearAllPoints()
                healthBar:SetPoint(hp.unlockPos.point, UIParent, rp, sx, sy)
            end
            EllesmereUI.SetElementVisibility(healthBar, false)
            ns.HealthIndicatorsApply(healthBar, nil)
        else
        local healthAnchorKey = NormalizeAnchorKey(hp.anchorTo)
        if EllesmereUI._TryOverrideAnchor and EllesmereUI._TryOverrideAnchor("ERB_Health", healthBar) then
            -- Override anchor owns positioning; only update size
            local ow, oh = OrientedSize(hpWidth, hpHeight, hpOri)
            healthBar:SetSize(ow, oh)
        elseif healthAnchorKey ~= "none" then
            local ow, oh = OrientedSize(hpWidth, hpHeight, hpOri)
            local offsetX, offsetY = GetAnchorOffsets(hp)
            healthBar:SetSize(ow, oh)
            if not ApplyBarAnchor(healthBar, healthAnchorKey, hp.anchorPosition, offsetX, offsetY, hp.growthDirection, hp.growCentered) then
                ApplyFreeBarPosition(healthBar, hp, 0, -64, ow, oh)
            end
        elseif hp.unlockPos and hp.unlockPos.point then
            local rp = hp.unlockPos.relPoint or hp.unlockPos.point
            local ow, oh = OrientedSize(hpWidth, hpHeight, hpOri)
            ApplyBarAnchor(healthBar, "none")
            healthBar:SetSize(ow, oh)
            if not EllesmereUI._unlockActive then
                if not EllesmereUI.IsUnlockAnchored("ERB_Health") or not healthBar:GetLeft() then
                    local sx, sy = SnapXY(hp.unlockPos.x, hp.unlockPos.y, healthBar, hp.unlockPos)
                    healthBar:ClearAllPoints()
                    healthBar:SetPoint(hp.unlockPos.point, UIParent, rp, sx, sy)
                end
            end
        else
            -- Clear any mouse-tracking OnUpdate from a previous anchor
            ApplyBarAnchor(healthBar, "none")
            if EllesmereUI._unlockActive then
                -- During unlock mode, only update size -- position is managed by the mover
                local ow, oh = OrientedSize(hpWidth, hpHeight, hpOri)
                healthBar:SetSize(ow, oh)
            else
                local function ApplyHealthBarTransform()
                    local ox = healthBar["_barAnim_ox"] or hp.offsetX or 0
                    local oy = healthBar["_barAnim_oy"] or hp.offsetY or -64
                    local w = healthBar["_barAnim_w"] or hpWidth
                    local h2 = healthBar["_barAnim_h"] or hpHeight
                    local ow, oh = OrientedSize(w, h2, hpOri)
                    healthBar:ClearAllPoints()
                    healthBar:SetPoint("CENTER", mainFrame, "CENTER", ox, oy)
                    healthBar:SetSize(ow, oh)
                end
                SmoothBarAnimate(healthBar, "ox", hp.offsetX or 0, function() ApplyHealthBarTransform() end)
                SmoothBarAnimate(healthBar, "oy", hp.offsetY or -64, function() ApplyHealthBarTransform() end)
                SmoothBarAnimate(healthBar, "w", hpWidth, function() ApplyHealthBarTransform() end)
                SmoothBarAnimate(healthBar, "h", hpHeight, function() ApplyHealthBarTransform() end)
            end
        end
        if ns.ERB_BarsBlizz() then
            -- Blizzard Style / Classic WoW UI: the stock bar frame replaces the EUI border.
            healthBar:ApplyBorder(0, 0, 0, 0, 0)
            local bw, bh = OrientedSize(hpWidth, hpHeight, hpOri)
            ns.ERB_ApplyBlizzBarChrome(healthBar, healthBar._sb, bw, bh, ns.IsVerticalOrientation(hpOri), ns.ERB_BarFrameK(hp))
        else
            healthBar:ApplyBorder(hp.borderSize, hp.borderR, hp.borderG, hp.borderB, hp.borderA, hp.borderTexture, hp.borderTextureOffset, hp.borderTextureOffsetY, hp.borderTextureShiftX, hp.borderTextureShiftY, "resourcebars", hp.borderSize, hp.borderBehind,
                EllesmereUI.BorderPx(hp.borderSizePx, hp.borderSize, hp.borderTexture))
        end

        -- Bar texture (must be applied before colors since SetStatusBarTexture resets vertex color).
        -- Health's own texture (the Texture cog) counts only while splitTex is on; nil or false
        -- matches the main row.
        ApplyBarTexture(healthBar, (p.splitTex == true and hp.barTexture) or g.barTexture or "none")

        -- Colors: custom colored > class color. Gradient is additive: when enabled
        -- it fills from the resolved custom/class base to the gradient end color.
        local hft = healthBar:GetStatusBarTexture()
        do
            local fR, fG, fB, fA
            if hp.customColored then
                fR, fG, fB, fA = hp.fillR, hp.fillG, hp.fillB, 1
            else
                local cc = CLASS_COLORS[cachedClass]
                if cc then fR, fG, fB, fA = cc[1], cc[2], cc[3], 1
                else fR, fG, fB, fA = 0.15, 0.75, 0.30, 1 end
            end
            if hp.gradientEnabled then
                ApplyBarGradient(hft, hp.gradientDir or "HORIZONTAL",
                    fR, fG, fB, fA,
                    hp.gradientR, hp.gradientG, hp.gradientB, hp.gradientA)
            else
                ApplyBarFlat(hft, fR, fG, fB, fA)
            end
            healthBar._bg:SetColorTexture(hp.bgR, hp.bgG, hp.bgB, hp.bgA)
            -- Textured Background: flat while Fill Color is below 100.
            if g.barTextureBg or healthBar._bg._erbBgTex then
                ns.ERB_BgTexture(healthBar._bg, g.barTextureBg and (hp.fillOpacity or 100) >= 100
                    and EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, (p.splitTex == true and hp.barTexture) or g.barTexture, nil),
                    hp.bgR, hp.bgG, hp.bgB, hp.bgA)
            end
        end

        healthBar._text:ClearAllPoints()
        local _hpTA = hp.textAnchor or "CENTER"
        healthBar._text:SetPoint(_hpTA, healthBar, _hpTA, hp.textXOffset, hp.textYOffset)
        SetRBFont(healthBar._text, GetRBFont(), hp.textSize)
        -- Text color: class color when textCustomColored == false, else custom (default custom)
        if hp.textCustomColored == false then
            local tcc = CLASS_COLORS[cachedClass]
            if tcc then
                healthBar._text:SetTextColor(tcc[1], tcc[2], tcc[3], 1)
            else
                healthBar._text:SetTextColor(1, 1, 1, 1)
            end
        else
            healthBar._text:SetTextColor(hp.textFillR or 1, hp.textFillG or 1, hp.textFillB or 1, hp.textFillA or 1)
        end
        healthBar:Show()
        healthBar:SetAlpha(ns.ResolveBarAlpha(hp))
        ApplyBarOrientation(healthBar, hpOri)
        ns.ApplyFillOpacity(healthBar, hpOri, hp.fillOpacity)
        if IsSpecDisabled(hp) then
            EllesmereUI.SetElementVisibility(healthBar, false)
        end
        -- Absorb / heal absorb / max health reduction overlays
        -- (EUI_ResourceBars_HealthIndicators.lua): settings pass only.
        ns.HealthIndicatorsApply(healthBar, (not IsSpecDisabled(hp)) and hp or nil, hpOri)
        -- Rounded corners (EllesmereUI_RoundedCorners.lua), after the retexture
        -- and the overlays, so overlays built by this pass join the body:
        -- nothing at radius 0 or under the stock styles.
        ns.ERB_RoundBar(healthBar, hp)
        end
    end

    -- Power bar (primary resource)
    I.SetCachedPrimary(GetPrimaryPowerType())
    local pp = _G._ERB_ResolvePowerCfg(p) or FALLBACK.primary
    -- Expand height when the spec has no class resource and the option is on.
    -- Suppressed in unlock mode or with the options panel open, so the
    -- mover/getSize sees the real stored height, not the expanded one.
    local ppHeight = pp.height or 14
    local ppExpandDelta = 0
    local ppDirSign = 1  -- expand direction: +1 grow up (class resource above), -1 grow down (below)
    local _heightMatched = EllesmereUI.GetHeightMatchTarget and EllesmereUI.GetHeightMatchTarget("ERB_Power")
    -- Runtime suppression only -- never reads or writes the saved setting
    -- (see _ERB_SuppressExpand in OnInitialize).
    if pp.expandIfNoResource and not _heightMatched
       and not EllesmereUI._erbExpandSuppressed and not EllesmereUI._unlockActive then
        local sp2 = _G._ERB_ResolveSecondaryCfg(p) or FALLBACK.secondary
        -- The class resource leaves an empty slot to expand into when "Show Class
        -- Resource" is off, spec-disabled, or the spec has none. Mirrors the
        -- "Shift Elements if No Resource" checks (IsSpecDisabled +
        -- GetSecondaryResource) plus the master-disable case.
        if sp2.enabled == false or IsSpecDisabled(sp2) or not GetSecondaryResource() then
            ppExpandDelta = math.max(0, (sp2.pipHeight or 20) + (pp.expandIfNoResourceExtraY or 0))
            ppHeight = ppHeight + ppExpandDelta
            ppDirSign = ResolveExpandDirSign(pp, sp2)
        end
    end
    -- Clean stale key from the retired suppress/restore system
    if pp._expandWasOn ~= nil then pp._expandWasOn = nil end
    -- SnapForES (round to nearest), NOT PP.Scale (truncate toward zero): 214.6
    -- rounds to 215 instead of losing 1px. Truncating would let a stale stored
    -- value (e.g. from a previous UI scale) land 1px short of the width-match
    -- target, forcing the user to un-match/re-match to fix it.
    local ppWidthRaw = pp.width or 214
    local _ppEs = (primaryBar and primaryBar:GetEffectiveScale()) or (UIParent and UIParent:GetEffectiveScale()) or 1
    if PP and PP.SnapForES then
        ppWidthRaw = PP.SnapForES(ppWidthRaw, _ppEs)
        ppHeight = PP.SnapForES(ppHeight, _ppEs)
    end
    local ppWidth = ppWidthRaw
    -- Always create the frame when enabled so anchored elements (CDM bars, cast
    -- bar) have a valid target; with no primary power for the spec it stays at
    -- zero alpha but keeps its position.
    if not primaryBar then
        I.SetPrimaryBar(CreateStatusBar(mainFrame, "ERB_PrimaryBar", ppWidth, ppHeight,
            pp.borderSize, pp.borderR, pp.borderG, pp.borderB, pp.borderA))
        primaryBar:SetFrameStrata(pp.frameStrata or g.frameStrata or "MEDIUM")
        primaryBar:SetFrameLevel(10)
    end
    if pp.enabled ~= false and cachedPrimary then
        local ppOri = pp.orientation or g.orientation or "HORIZONTAL"
        local primaryAnchorKey = NormalizeAnchorKey(pp.anchorTo)
        local primaryOverrideOwned = EllesmereUI._TryOverrideAnchor
            and EllesmereUI._TryOverrideAnchor("ERB_Power", primaryBar)
        local primaryUnlockAnchored = EllesmereUI.IsUnlockAnchored("ERB_Power")
        if primaryOverrideOwned or primaryUnlockAnchored then
            -- Unlock anchor system / override anchor owns positioning; only update size
            local ow, oh = OrientedSize(ppWidth, ppHeight, ppOri)
            primaryBar:SetSize(ow, oh)
        elseif primaryAnchorKey ~= "none" then
            local ow, oh = OrientedSize(ppWidth, ppHeight, ppOri)
            local offsetX, offsetY = GetAnchorOffsets(pp)
            primaryBar:SetSize(ow, oh)
            if not ApplyBarAnchor(primaryBar, primaryAnchorKey, pp.anchorPosition, offsetX, offsetY, pp.growthDirection, pp.growCentered) then
                ApplyFreeBarPosition(primaryBar, pp, 0, -54, ow, oh)
            end
        elseif pp.unlockPos and pp.unlockPos.point then
            local rp = pp.unlockPos.relPoint or pp.unlockPos.point
            local ow, oh = OrientedSize(ppWidth, ppHeight, ppOri)
            ApplyBarAnchor(primaryBar, "none")
            primaryBar:SetSize(ow, oh)
            if not EllesmereUI._unlockActive then
                if not EllesmereUI.IsUnlockAnchored("ERB_Power") or not primaryBar:GetLeft() then
                    local sx, sy = SnapXY(pp.unlockPos.x, pp.unlockPos.y, primaryBar, pp.unlockPos)
                    -- Dragged bars store the UNexpanded CENTER (expand is suppressed
                    -- during unlock capture), so SetSize alone grows symmetrically;
                    -- shift the center by ppDirSign so the bar grows toward the
                    -- class resource.
                    if ppExpandDelta > 0 and pp.unlockPos.point == "CENTER" then
                        sy = sy + ppDirSign * ppExpandDelta * 0.5
                    end
                    primaryBar:ClearAllPoints()
                    primaryBar:SetPoint(pp.unlockPos.point, UIParent, rp, sx, sy)
                end
            end
        else
            -- Clear any mouse-tracking OnUpdate from a previous anchor
            ApplyBarAnchor(primaryBar, "none")
            if EllesmereUI._unlockActive then
                -- During unlock mode, only update size -- position is managed by the mover
                local ow, oh = OrientedSize(ppWidth, ppHeight, ppOri)
                primaryBar:SetSize(ow, oh)
            else
                local function ApplyPowerBarTransform()
                    local ox = primaryBar["_barAnim_ox"] or pp.offsetX or 0
                    local oy = primaryBar["_barAnim_oy"] or pp.offsetY or -54
                    local w = primaryBar["_barAnim_w"] or ppWidth
                    local h2 = primaryBar["_barAnim_h"] or ppHeight
                    local ow, oh = OrientedSize(w, h2, ppOri)
                    primaryBar:ClearAllPoints()
                    -- Expand toward the class resource: the edge facing AWAY stays
                    -- fixed (ppDirSign +1 = grow up, -1 = grow down). Derive the
                    -- shift from the ANIMATED height (h2), not the final delta, so
                    -- the fixed edge holds for the whole tween.
                    local base = ppHeight - ppExpandDelta
                    local extra = (ppExpandDelta > 0) and (ppDirSign * (h2 - base) * 0.5) or 0
                    primaryBar:SetPoint("CENTER", mainFrame, "CENTER", ox, oy + extra)
                    primaryBar:SetSize(ow, oh)
                end
                SmoothBarAnimate(primaryBar, "ox", pp.offsetX or 0, function() ApplyPowerBarTransform() end)
                SmoothBarAnimate(primaryBar, "oy", pp.offsetY or -54, function() ApplyPowerBarTransform() end)
                SmoothBarAnimate(primaryBar, "w", ppWidth, function() ApplyPowerBarTransform() end)
                SmoothBarAnimate(primaryBar, "h", ppHeight, function() ApplyPowerBarTransform() end)
            end
        end
        -- expandIfNoResource grows the power bar toward the class resource (above
        -- ->up, below->down) via ppDirSign/ResolveExpandDirSign for the free and
        -- dragged branches above; anchorTo/unlock-anchored branches grow per their
        -- own anchor edge.
        if ns.ERB_BarsBlizz() then
            -- Blizzard Style / Classic WoW UI: the stock bar frame replaces the EUI border.
            primaryBar:ApplyBorder(0, 0, 0, 0, 0)
            local bw, bh = OrientedSize(ppWidth, ppHeight, ppOri)
            ns.ERB_ApplyBlizzBarChrome(primaryBar, primaryBar._sb, bw, bh, ns.IsVerticalOrientation(ppOri), ns.ERB_BarFrameK(pp))
        else
            -- Extend Top / Extend Bottom re-seat the border host (the stock branch
            -- above passes none, so an extended host goes back to the bar's rect).
            primaryBar:ApplyBorder(pp.borderSize, pp.borderR, pp.borderG, pp.borderB, pp.borderA, pp.borderTexture, pp.borderTextureOffset, pp.borderTextureOffsetY, pp.borderTextureShiftX, pp.borderTextureShiftY, "resourcebars", pp.borderSize, pp.borderBehind,
                EllesmereUI.BorderPx(pp.borderSizePx, pp.borderSize, pp.borderTexture), ns.ERB_BorderExtents(pp))
        end
        -- Draw Above GCD Bar: re-lifts the border ApplyBorder just re-levelled
        -- (inert unless it was ever on).
        ns.ERB_PowerLift(pp)

        -- Bar texture (must be applied before colors since SetStatusBarTexture resets vertex color).
        -- Same per-bar rule as health: power's own key only while splitTex is on.
        ApplyBarTexture(primaryBar, (p.splitTex == true and pp.barTexture) or g.barTexture or "none")
        ns.ERB_RoundBar(primaryBar, pp)

        -- Colors: custom colored > power type color. Gradient is additive: when on
        -- it fills from the resolved custom/power base to the gradient end color.
        local pft = primaryBar:GetStatusBarTexture()
        do
            local fR, fG, fB, fA
            if pp.customColored then
                fR, fG, fB, fA = pp.fillR, pp.fillG, pp.fillB, 1
            else
                local pc = POWER_COLORS[cachedPrimary]
                if pc then fR, fG, fB, fA = pc[1], pc[2], pc[3], 1
                else fR, fG, fB, fA = 1, 1, 1, 1 end
            end
            if pp.gradientEnabled then
                ApplyBarGradient(pft, pp.gradientDir or "HORIZONTAL",
                    fR, fG, fB, fA,
                    pp.gradientR, pp.gradientG, pp.gradientB, pp.gradientA)
            else
                ApplyBarFlat(pft, fR, fG, fB, fA)
            end
            primaryBar._bg:SetColorTexture(pp.bgR, pp.bgG, pp.bgB, pp.bgA)
            -- Textured Background: flat while Fill Color is below 100.
            if g.barTextureBg or primaryBar._bg._erbBgTex then
                ns.ERB_BgTexture(primaryBar._bg, g.barTextureBg and (pp.fillOpacity or 100) >= 100
                    and EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, (p.splitTex == true and pp.barTexture) or g.barTexture, nil),
                    pp.bgR, pp.bgG, pp.bgB, pp.bgA)
            end
        end

        primaryBar._text:ClearAllPoints()
        local _ppTA = pp.textAnchor or "CENTER"
        primaryBar._text:SetPoint(_ppTA, primaryBar, _ppTA, pp.textXOffset, pp.textYOffset)
        SetRBFont(primaryBar._text, GetRBFont(), pp.textSize)
        -- Text color: power-type color when textCustomColored == false, else custom (default custom)
        if pp.textCustomColored == false then
            local tpc = POWER_COLORS[cachedPrimary]
            if tpc then
                primaryBar._text:SetTextColor(tpc[1], tpc[2], tpc[3], 1)
            else
                primaryBar._text:SetTextColor(1, 1, 1, 1)
            end
        else
            primaryBar._text:SetTextColor(pp.textFillR or 1, pp.textFillG or 1, pp.textFillB or 1, pp.textFillA or 1)
        end
        primaryBar:Show()
        local hidePower = p.secondary and p.secondary.hidePowerIfResource and p.secondary.enabled ~= false and cachedSecondary
        if hidePower then
            EllesmereUI.SetElementVisibility(primaryBar, false)
        else
            primaryBar:SetAlpha(ns.ResolveBarAlpha(pp))
        end
        ApplyBarOrientation(primaryBar, ppOri)
        ns.ApplyFillOpacity(primaryBar, ppOri, pp.fillOpacity)
        if IsSpecDisabled(pp) then
            EllesmereUI.SetElementVisibility(primaryBar, false)
        end
    elseif primaryBar then
        -- Enabled but no resource for this spec: keep the frame positioned at
        -- zero alpha so anchored elements (CDM bars, etc.) have a target.
        local ppOri = pp.orientation or g.orientation or "HORIZONTAL"
        local ow, oh = OrientedSize(ppWidth, ppHeight, ppOri)
        primaryBar:SetSize(ow, oh)
        primaryBar:Show()
        if not (EllesmereUI._TryOverrideAnchor and EllesmereUI._TryOverrideAnchor("ERB_Power", primaryBar))
           and not EllesmereUI.IsUnlockAnchored("ERB_Power") then
            if pp.unlockPos and pp.unlockPos.point then
                local rp = pp.unlockPos.relPoint or pp.unlockPos.point
                local sx, sy = SnapXY(pp.unlockPos.x, pp.unlockPos.y, primaryBar, pp.unlockPos)
                primaryBar:ClearAllPoints()
                primaryBar:SetPoint(pp.unlockPos.point, UIParent, rp, sx, sy)
            elseif not primaryBar:GetLeft() then
                primaryBar:ClearAllPoints()
                primaryBar:SetPoint("CENTER", mainFrame, "CENTER", pp.offsetX or 0, pp.offsetY or -54)
            end
        end
        EllesmereUI.SetElementVisibility(primaryBar, false)
    end


    -- Class resource (secondary: pips / runes)
    I.SetCachedSecondary(GetSecondaryResource())
    local sp = _G._ERB_ResolveSecondaryCfg(p) or FALLBACK.secondary
    -- Create the frame UNCONDITIONALLY (mirrors the power bar) so anchored elements
    -- always have a target and "Shift Elements if No Resource" works whether the bar
    -- is spec-hidden OR toggled off. When off, the branch below keeps it sized and
    -- zero-alpha.
    if not secondaryFrame then
        I.SetSecondaryFrame(CreateFrame("Frame", "ERB_SecondaryFrame", mainFrame))
        secondaryFrame:SetFrameStrata(g.frameStrata or "MEDIUM")
        secondaryFrame:SetFrameLevel(10)
    end
    -- Draw Above Other Bars: the slot's level is written only while it is on, or
    -- once to put it back at 10; before the art sync and the border, which level
    -- off it.
    if sp.raiseLevel or secondaryFrame._erbRaised then ns.ERB_ClassRaise(sp) end
    -- Blizzard Class Resource Art (EUI_ResourceBars_BlizzClassArt.lua): claims or
    -- hands back Blizzard's class resource frame and sets ns._erbArtOn, which
    -- stands the pips down at the end of this block while the slot keeps its
    -- size and position for anchors, the unlock mover, shift and expand.
    if ns.ERB_BlizzArtSync then ns.ERB_BlizzArtSync(sp, cachedSecondary, secondaryFrame) end
    if sp.enabled ~= false and not IsSpecDisabled(sp) and cachedSecondary then

        local maxPts = cachedSecondary.max or 5
        if cachedSecondary.type == "custom" and EllesmereUI then
            local powerType = cachedSecondary.power
            if powerType == "SOUL_FRAGMENTS" and EllesmereUI.GetSoulFragments then
                local _, realMax = EllesmereUI.GetSoulFragments()
                if realMax and realMax > 0 then maxPts = realMax end
            elseif powerType == "MAELSTROM_WEAPON" and EllesmereUI.GetMaelstromWeapon then
                local _, realMax = EllesmereUI.GetMaelstromWeapon()
                if realMax and realMax > 0 then maxPts = realMax end
                -- Enhance 5-bar mode: cap visual pips to 5, overflow handled at render time
                if sp.enhanceFiveBar and maxPts > 5 then
                    cachedSecondary._realMax = maxPts
                    maxPts = 5
                else
                    cachedSecondary._realMax = nil
                end
            elseif powerType == "TIP_OF_THE_SPEAR" and EllesmereUI.GetTipOfTheSpear then
                local _, realMax = EllesmereUI.GetTipOfTheSpear()
                if realMax and realMax > 0 then maxPts = realMax end
            elseif (powerType == "WHIRLWIND_STACKS" or powerType == "SWEEPING_STRIKES")
                   and _G._EWC then
                -- Talent-aware cap from the engine-slot module (Broad Strokes).
                local realMax = _G._EWC.MaxApps(powerType)
                if realMax and realMax > 0 then maxPts = realMax end
            elseif powerType == "ICICLES" then
                maxPts = 5
            end
        end
        -- Single source of truth for effective scale: captured once and passed to
        -- every snap and to CalcPipGeometry, so an effective-scale change mid-build
        -- (reparent, etc.) cannot desync frame dimensions from pip layout by 1px.
        local _crEs = (secondaryFrame and secondaryFrame:GetEffectiveScale())
                      or (UIParent and UIParent:GetEffectiveScale()) or 1
        local pipH = PP.SnapForES(sp.pipHeight or 20, _crEs)
        local pipSp = sp.pipSpacing or 1
        local pipOri = sp.pipOrientation or "HORIZONTAL"
        local isVertical = (pipOri ~= "HORIZONTAL")
        -- Tick-orientation stamp for the pip/rune hash lanes: secondaryFrame
        -- is a plain container, so ApplyResourceBarTicks cannot probe an inner
        -- StatusBar for it. Always written (HORIZONTAL included) so a flip
        -- back never reads stale.
        secondaryFrame._ticksOri = pipOri
        local isReversed = (pipOri == "VERTICAL_UP")
        local totalW

        local isBarType = cachedSecondary.type == "bar"
        -- Background on individual pips (pip and rune resources only).
        local pipBg = ns.ERB_PipBgOn(sp, isBarType)
        totalW = sp.pipWidth or 214

        -- Frame dimensions snapped ONCE with the captured _crEs; pip layout below
        -- uses the SAME _crEs and totalW, so slot positions align with the frame
        -- edges exactly. NEVER resize the frame after layout -- that re-introduces
        -- the 1px shift this design eliminates.
        local widthSnapped  = PP.SnapForES(totalW, _crEs)
        local heightSnapped = PP.SnapForES(pipH,   _crEs)
        local frameW = isVertical and heightSnapped or widthSnapped
        local frameH = isVertical and widthSnapped  or heightSnapped
        local secondaryAnchorKey = NormalizeAnchorKey(sp.anchorTo)
        local secondaryOverrideOwned = EllesmereUI._TryOverrideAnchor
            and EllesmereUI._TryOverrideAnchor("ERB_ClassResource", secondaryFrame)
        local secondaryUnlockAnchored = EllesmereUI.IsUnlockAnchored("ERB_ClassResource")
        if secondaryOverrideOwned or secondaryUnlockAnchored then
            -- Unlock anchor system / override anchor owns positioning; only update size
            secondaryFrame:SetSize(frameW, frameH)
        elseif secondaryAnchorKey ~= "none" then
            local offsetX, offsetY = GetAnchorOffsets(sp)
            secondaryFrame:SetSize(frameW, frameH)
            if not ApplyBarAnchor(secondaryFrame, secondaryAnchorKey, sp.anchorPosition, offsetX, offsetY, sp.growthDirection, sp.growCentered) then
                ApplyFreeBarPosition(secondaryFrame, sp, 0, -38, frameW, frameH)
            end
        elseif sp.unlockPos and sp.unlockPos.point then
            ApplyBarAnchor(secondaryFrame, "none")
            secondaryFrame:SetSize(frameW, frameH)
            -- ApplySavedPositions is the SINGLE authority for unlock positions;
            -- applying here too double-snaps (BuildBars and applyPos capture
            -- effective scale at different times, so SnapCenterForDim can differ by
            -- 1px). Fall back inline only when the frame has no bounds yet (first
            -- build, before ApplySavedPositions ran).
            if not secondaryFrame:GetLeft() then
                local sx, sy = SnapXY(sp.unlockPos.x, sp.unlockPos.y, secondaryFrame, sp.unlockPos)
                secondaryFrame:ClearAllPoints()
                secondaryFrame:SetPoint(sp.unlockPos.point, UIParent, sp.unlockPos.relPoint or sp.unlockPos.point, sx, sy)
            end
        else
            ApplyBarAnchor(secondaryFrame, "none")
            if EllesmereUI._unlockActive then
                -- During unlock mode, only update size -- position is managed by the mover
                secondaryFrame:SetSize(frameW, frameH)
            else
                local function ApplySecondaryBarTransform()
                    local ox = secondaryFrame["_barAnim_ox"] or sp.offsetX or 0
                    local oy = secondaryFrame["_barAnim_oy"] or sp.offsetY or -38
                    local w  = secondaryFrame["_barAnim_w"] or frameW
                    local h2 = secondaryFrame["_barAnim_h"] or frameH
                    secondaryFrame:ClearAllPoints()
                    secondaryFrame:SetPoint("CENTER", mainFrame, "CENTER", ox, oy)
                    secondaryFrame:SetSize(w, h2)
                end
                SmoothBarAnimate(secondaryFrame, "ox", sp.offsetX or 0, function() ApplySecondaryBarTransform() end)
                SmoothBarAnimate(secondaryFrame, "oy", sp.offsetY or -38, function() ApplySecondaryBarTransform() end)
                SmoothBarAnimate(secondaryFrame, "w", frameW, function() ApplySecondaryBarTransform() end)
                SmoothBarAnimate(secondaryFrame, "h", frameH, function() ApplySecondaryBarTransform() end)
            end
        end

        -- Create/reuse pips or bar
        if isBarType then
            -- Bar-style secondary (e.g. Devourer soul fragments, Elemental maelstrom)
            -- Hide all pips, runes, and pip tick marks
            for i = 1, #pips do if pips[i] then pips[i]:Hide() end end
            for i = 1, #runeFrames do if runeFrames[i] then runeFrames[i]:Hide() end end
            HideResourceBarTicks(secondaryPipTicks, secondaryFrame)
            ERB.ApplyGapFills(secondaryFrame, nil, 0, isVertical, isReversed, sp)  -- no pips -> hide any gap fills
            ns.ERB_ClassSeps(sp)  -- Separators: the bottom-edge line only (no gaps)

            if not secondaryBar then
                I.SetSecondaryBar(CreateStatusBar(secondaryFrame, "ERB_SecondaryBar", totalW, pipH,
                    0, 0, 0, 0, 0))
                secondaryBar:SetMinMaxValues(0, maxPts)
                secondaryBar:SetValue(0)
                -- Apply the Smooth Bars setting to the freshly created bar.
                if ERB.ApplySmoothing then ERB:ApplySmoothing() end
            else
                -- For existing bars, only update min/max if needed (don't reset value to 0)
                local actualMax = maxPts
                if cachedSecondary.power == "BREWMASTER_STAGGER" then
                    actualMax = UnitHealthMax("player") or 1
                    if actualMax <= 0 then actualMax = 1 end
                elseif cachedSecondary.power == "IGNOREPAIN_BAR" then
                    local hm = UnitHealthMax("player")
                    if hm and not (issecretvalue and issecretvalue(hm)) and hm > 0 then
                        actualMax = hm * IP.CAP
                    end
                end
                if secondaryBar._lastMaxC ~= actualMax then
                    secondaryBar._lastMaxC = actualMax
                    secondaryBar:SetMinMaxValues(0, actualMax)
                end
            end
            secondaryBar:SetSize(totalW, pipH)
            secondaryBar:ClearAllPoints()
            secondaryBar:SetAllPoints(secondaryFrame)

            -- Texture and orientation MUST be applied before colors:
            -- SetStatusBarTexture and SetRotatesTexture both reset vertex color. Use
            -- the Class Resource's own pipOrientation (the key the dropdown writes),
            -- NOT p.general.orientation -- that renders vertical fill horizontally.
            ApplyBarTexture(secondaryBar, g.barTexture or "none")
            ApplyBarOrientation(secondaryBar, pipOri)

            local pc = POWER_COLORS[cachedSecondary.power]
            if sp.darkTheme then
                local _dfr, _dfg, _dfb = EllesmereUI.GetDarkModeFill()
                local _dbr, _dbg, _dbb = EllesmereUI.GetDarkModeBg()
                secondaryBar:GetStatusBarTexture():SetVertexColor(_dfr, _dfg, _dfb, DARK_FILL_A)
                secondaryBar._bg:SetColorTexture(_dbr, _dbg, _dbb, DARK_BG_A)
            elseif cachedSecondary.power == "BREWMASTER_STAGGER" then
                -- Brewmaster Stagger: always use threshold colors (green/yellow/red), start with green
                secondaryBar:GetStatusBarTexture():SetVertexColor(0.2, 0.8, 0.2, 1)
                secondaryBar._lastStaggerR, secondaryBar._lastStaggerG, secondaryBar._lastStaggerB = 0.2, 0.8, 0.2
                secondaryBar._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
            elseif sp.resourceColored then
                -- Per-spec resource/power color; falls back to class color.
                local rr, rg, rb = ERB.ResolveSecondaryResourceColor(cachedSecondary.power)
                if not rr then
                    local cc = CLASS_COLORS[cachedClass]
                    if cc then rr, rg, rb = cc[1], cc[2], cc[3] else rr, rg, rb = 1, 1, 1 end
                end
                secondaryBar:GetStatusBarTexture():SetVertexColor(rr, rg, rb, 1)
                secondaryBar._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
            elseif sp.classColored ~= false then
                -- Power types in secondary slot use power color; class resources use class color
                local pc2 = POWER_COLORS[cachedSecondary.power]
                if pc2 then
                    secondaryBar:GetStatusBarTexture():SetVertexColor(pc2[1], pc2[2], pc2[3], 1)
                else
                    local cc = CLASS_COLORS[cachedClass]
                    if cc then
                        secondaryBar:GetStatusBarTexture():SetVertexColor(cc[1], cc[2], cc[3], 1)
                    end
                end
                secondaryBar._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
            else
                -- classColored explicitly false -- use custom fill color
                secondaryBar:GetStatusBarTexture():SetVertexColor(sp.fillR, sp.fillG, sp.fillB, 1)
                secondaryBar._bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
            end
            -- Textured Background: the class resource textures its own empty-bar
            -- background (Empty Bar Overlay; Dark Mode Background in Dark Mode).
            if g.barTextureBg or secondaryBar._bg._erbBgTex then
                local br, bgg, bb, ba = sp.bgR, sp.bgG, sp.bgB, sp.bgA
                if sp.darkTheme then
                    br, bgg, bb = EllesmereUI.GetDarkModeBg()
                    ba = DARK_BG_A
                end
                ns.ERB_BgTexture(secondaryBar._bg, g.barTextureBg
                    and (sp.fillOpacity or 100) >= 100 and EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, g.barTexture, nil), br, bgg, bb, ba)
            end
            -- Blizzard atlas fill swaps in AFTER the tint chain: the art is
            -- pre-colored (every color mode above overridden to white) since
            -- SetStatusBarTexture resets orientation/vertex color. No atlas for
            -- this power = the ApplyBarTexture fill and its tints stand.
            secondaryBar._atlasFill = nil
            if sp.useBlizzardAtlas then
                local atlas = ns.GetBlizzardPowerAtlas(cachedSecondary.power)
                if atlas then
                    secondaryBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
                    secondaryBar:GetStatusBarTexture():SetAtlas(atlas, true)
                    ApplyBarOrientation(secondaryBar, pipOri)
                    secondaryBar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
                    -- An active atlas fill is NEVER tinted: every live recolor
                    -- path must check this stamp.
                    secondaryBar._atlasFill = true
                end
            end
            ns.ApplyFillOpacity(secondaryBar, pipOri, sp.fillOpacity)
            secondaryBar:ApplyBorder(0, 0, 0, 0, 0)
            if cachedSecondary.power == "IRONFUR_BAR" then
                -- Guardian Ironfur: no static threshold hash lines; the moving
                -- per-cast hash lines are drawn live in UpdateIronfurBar.
                HideResourceBarTicks(secondaryBarTicks, secondaryBar)
                EnsureIronfurOverlay(secondaryBar)
            elseif cachedSecondary.power == "IGNOREPAIN_BAR" then
                -- Prot Ignore Pain: no static threshold hash lines -- the absorb
                -- value is secret, so value-positioned hashes are meaningless. The
                -- moving duration hash line is drawn separately via IP.UpdateHash.
                HideResourceBarTicks(secondaryBarTicks, secondaryBar)
            else
                -- Resolve hash lines from thresholdSpecs entry (falls back to legacy tickValues)
                local _buildTsEntry = ResolveThresholdSpecEntry(sp)
                local _buildTickStr = (_buildTsEntry and _buildTsEntry.hashValues ~= "") and _buildTsEntry.hashValues or sp.tickValues
                local _buildHW = _buildTsEntry and _buildTsEntry.hashWidth or 1
                local _buildHR = _buildTsEntry and _buildTsEntry.hashColorR or 1
                local _buildHG = _buildTsEntry and _buildTsEntry.hashColorG or 1
                local _buildHB = _buildTsEntry and _buildTsEntry.hashColorB or 1
                local _buildHA = _buildTsEntry and _buildTsEntry.hashColorA or 0.7
                local _buildHPct = _buildTsEntry and _buildTsEntry.hashMode == "percent"
                -- Devourer in Void Meta (1217607): cap the bar at 40, so hide any
                -- hash above 39 (nothing at/beyond the meta edge).
                local _buildHashCap = (cachedSecondary.power == "SOUL_FRAGMENTS_DEVOURER"
                    and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID(1217607)) and 39 or nil
                ApplyResourceBarTicks(secondaryBar, maxPts, _buildTickStr, secondaryBarTicks, _buildHW, _buildHR, _buildHG, _buildHB, _buildHA, _buildHPct, _buildHashCap)
            end
            secondaryBar:Show()
        elseif cachedSecondary.type == "runes" then
            local numPips = 6
            -- Frame size already set with the SAME _crEs; slots are computed
            -- inside that fixed frame, so no resize.
            local slots = CalcPipGeometry(totalW, numPips, pipSp, secondaryFrame, _crEs)
            for i = 1, 6 do
                if not runeFrames[i] then
                    runeFrames[i] = CreatePip(secondaryFrame, 20, pipH, i,
                        0, 0, 0, 0, 0)
                    -- Countdown number on its own overlay ABOVE the bar border (whichever
                    -- one is visible: per-pip when Border on Individual Pips is on, else
                    -- the outer secondaryFrame._barBorder at level +5) -- the number must
                    -- clear that (not just the pip) while staying below the
                    -- count/value text overlay (level 25). Recharge fill stays
                    -- framed by the border, matching the ready-rune fill.
                    local cdOverlay = CreateFrame("Frame", nil, runeFrames[i])
                    cdOverlay:SetAllPoints(runeFrames[i])
                    cdOverlay:SetFrameLevel(secondaryFrame:GetFrameLevel() + 10)
                    local cdText = cdOverlay:CreateFontString(nil, "OVERLAY")
                    runeFrames[i]._cdText = cdText
                end
                -- Re-apply font size, color and offsets every rebuild so textSize /
                -- textXOffset / textYOffset changes take effect live.
                local cdText = runeFrames[i]._cdText
                if cdText then
                    cdText:SetTextColor(sp.textR or 1, sp.textG or 1, sp.textB or 1, 0.8)
                    SetRBFont(cdText, GetRBFont(), sp.textSize or 9)
                    cdText:ClearAllPoints()
                    cdText:SetPoint("CENTER", runeFrames[i], "CENTER",
                        sp.textXOffset or 0, sp.textYOffset or 0)
                end
                local x0 = slots[i].x0
                local x1 = slots[i].x1
                local rf = runeFrames[i]
                local function ApplyRunePos()
                    local ap0 = rf["_barAnim_x0"] or x0
                    local aw  = rf["_barAnim_x1"] or (x1 - x0)
                    local ah  = rf["_barAnim_ph"] or pipH
                    rf:ClearAllPoints()
                    if isVertical then
                        if isReversed then
                            rf:SetPoint("BOTTOM", secondaryFrame, "BOTTOM", 0, ap0)
                        else
                            rf:SetPoint("TOP", secondaryFrame, "TOP", 0, -ap0)
                        end
                        rf:SetHeight(aw)
                        rf:SetWidth(ah)
                    else
                        rf:SetPoint("LEFT", secondaryFrame, "LEFT", ap0, 0)
                        rf:SetWidth(aw)
                        rf:SetHeight(ah)
                    end
                end
                rf["_barAnim_x0"] = x0
                rf["_barAnim_x1"] = x1 - x0
                rf["_barAnim_ph"] = pipH
                ApplyRunePos()
                if sp.borderOnPips then
                    runeFrames[i]:ApplyBorder(sp.borderSize, sp.borderR, sp.borderG, sp.borderB, sp.borderA,
                        sp.borderTexture, sp.borderTextureOffset, sp.borderTextureOffsetY,
                        sp.borderTextureShiftX, sp.borderTextureShiftY, "resourcebars", sp.borderSize,
                        EllesmereUI.BorderPx(sp.borderSizePx, sp.borderSize, sp.borderTexture))
                else
                    runeFrames[i]:ApplyBorder(0, 0, 0, 0, 0)
                end
                runeFrames[i]:ApplyTexture(g.barTexture or "none")
                runeFrames[i]._bg:SetColorTexture(ERB.PipBgColor(sp, pipBg))
                -- Textured Background, as the bar-type branch.
                if g.barTextureBg or runeFrames[i]._bg._erbBgTex then
                    ns.ERB_BgTexture(runeFrames[i]._bg, g.barTextureBg and not pipBg
                        and (sp.fillOpacity or 100) >= 100 and EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, g.barTexture, nil), ERB.PipBgColor(sp, pipBg))
                end
                -- Fill Opacity: same stamp as regular pips (consumed by
                -- SetActive in the rune update). Inert at 100 unless restoring.
                -- Background on individual pips takes the same path at factor 1:
                -- each rune's own backdrop is then its only background.
                local _runeOp = sp.fillOpacity or 100
                if _runeOp < 100 or pipBg then
                    local _rOp = (_runeOp < 100) and (_runeOp / 100) or 1
                    runeFrames[i]._fillOp = _rOp
                    runeFrames[i]._fill:SetAlpha(_rOp)
                elseif runeFrames[i]._fillOp then
                    ns.ClearPipFillOpacity(runeFrames[i])
                end
                runeFrames[i]:Show()
            end
            for i = 7, #pips do if pips[i] then pips[i]:Hide() end end
            if secondaryBar then secondaryBar:Hide() end
            HideResourceBarTicks(secondaryBarTicks, secondaryBar)
            -- Hash lines for rune-type resources (drawn on secondaryFrame)
            local _runeTsEntry = ResolveThresholdSpecEntry(sp)
            local _runeTickStr = (_runeTsEntry and _runeTsEntry.hashValues ~= "") and _runeTsEntry.hashValues or nil
            local _runeHW = _runeTsEntry and _runeTsEntry.hashWidth or 1
            local _runeHR = _runeTsEntry and _runeTsEntry.hashColorR or 1
            local _runeHG = _runeTsEntry and _runeTsEntry.hashColorG or 1
            local _runeHB = _runeTsEntry and _runeTsEntry.hashColorB or 1
            local _runeHA = _runeTsEntry and _runeTsEntry.hashColorA or 0.7
            ApplyResourceBarTicks(secondaryFrame, 6, _runeTickStr, secondaryPipTicks, _runeHW, _runeHR, _runeHG, _runeHB, _runeHA)
            ERB.ApplyGapFills(secondaryFrame, slots, numPips, isVertical, isReversed, sp, pipBg)
            ns.ERB_ClassSeps(sp, slots, numPips, isVertical, isReversed)
        else
            -- Frame size already set with the SAME _crEs; slots are computed
            -- inside that fixed frame, so no resize.
            local slots = CalcPipGeometry(totalW, maxPts, pipSp, secondaryFrame, _crEs)
            for i = 1, maxPts do
                if not pips[i] then
                    pips[i] = CreatePip(secondaryFrame, 20, pipH, i,
                        0, 0, 0, 0, 0)
                end
                local x0 = slots[i].x0
                local x1 = slots[i].x1
                local pip = pips[i]
                local function ApplyPipPos()
                    local ap0 = pip["_barAnim_x0"] or x0
                    local aw  = pip["_barAnim_x1"] or (x1 - x0)
                    local ah  = pip["_barAnim_ph"] or pipH
                    pip:ClearAllPoints()
                    if isVertical then
                        if isReversed then
                            pip:SetPoint("BOTTOM", secondaryFrame, "BOTTOM", 0, ap0)
                        else
                            pip:SetPoint("TOP", secondaryFrame, "TOP", 0, -ap0)
                        end
                        pip:SetHeight(aw)
                        pip:SetWidth(ah)
                    else
                        pip:SetPoint("LEFT", secondaryFrame, "LEFT", ap0, 0)
                        pip:SetWidth(aw)
                        pip:SetHeight(ah)
                    end
                end
                pip["_barAnim_x0"] = x0
                pip["_barAnim_x1"] = x1 - x0
                pip["_barAnim_ph"] = pipH
                ApplyPipPos()
                if sp.borderOnPips then
                    pips[i]:ApplyBorder(sp.borderSize, sp.borderR, sp.borderG, sp.borderB, sp.borderA,
                        sp.borderTexture, sp.borderTextureOffset, sp.borderTextureOffsetY,
                        sp.borderTextureShiftX, sp.borderTextureShiftY, "resourcebars", sp.borderSize,
                        EllesmereUI.BorderPx(sp.borderSizePx, sp.borderSize, sp.borderTexture))
                else
                    pips[i]:ApplyBorder(0, 0, 0, 0, 0)
                end
                pips[i]:ApplyTexture(g.barTexture or "none")
                pips[i]._bg:SetColorTexture(ERB.PipBgColor(sp, pipBg))
                -- Textured Background, as the bar-type branch.
                if g.barTextureBg or pips[i]._bg._erbBgTex then
                    ns.ERB_BgTexture(pips[i]._bg, g.barTextureBg and not pipBg
                        and (sp.fillOpacity or 100) >= 100 and EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, g.barTexture, nil), ERB.PipBgColor(sp, pipBg))
                end
                -- Fill Opacity: stamp the per-pip factor (consumed by SetActive
                -- and the secret renderer). Inert at 100 unless restoring.
                -- Background on individual pips takes the same path at factor 1:
                -- each pip's own backdrop is then its only background.
                local _pipOp = sp.fillOpacity or 100
                if _pipOp < 100 or pipBg then
                    local _pOp = (_pipOp < 100) and (_pipOp / 100) or 1
                    pips[i]._fillOp = _pOp
                    pips[i]._fill:SetAlpha(_pOp)
                elseif pips[i]._fillOp then
                    ns.ClearPipFillOpacity(pips[i])
                end
                pips[i]:Show()
            end
            for i = maxPts + 1, #pips do if pips[i] then pips[i]:Hide() end end
            ERB.ApplyGapFills(secondaryFrame, slots, maxPts, isVertical, isReversed, sp, pipBg)
            ns.ERB_ClassSeps(sp, slots, maxPts, isVertical, isReversed)
            for i = 1, #runeFrames do if runeFrames[i] then runeFrames[i]:Hide() end end
            if secondaryBar then secondaryBar:Hide() end
            HideResourceBarTicks(secondaryBarTicks, secondaryBar)
            -- Hash lines for pip-type resources (drawn on secondaryFrame)
            local _pipTsEntry = ResolveThresholdSpecEntry(sp)
            local _pipTickStr = (_pipTsEntry and _pipTsEntry.hashValues ~= "") and _pipTsEntry.hashValues or nil
            local _pipHW = _pipTsEntry and _pipTsEntry.hashWidth or 1
            local _pipHR = _pipTsEntry and _pipTsEntry.hashColorR or 1
            local _pipHG = _pipTsEntry and _pipTsEntry.hashColorG or 1
            local _pipHB = _pipTsEntry and _pipTsEntry.hashColorB or 1
            local _pipHA = _pipTsEntry and _pipTsEntry.hashColorA or 0.7
            ApplyResourceBarTicks(secondaryFrame, maxPts, _pipTickStr, secondaryPipTicks, _pipHW, _pipHR, _pipHG, _pipHB, _pipHA)
        end

        -- Full-bar border (wraps the entire class resource bar)
        if not secondaryFrame._barBorder then
            secondaryFrame._barBorder = MakePixelBorder(secondaryFrame,
                sp.borderR, sp.borderG, sp.borderB, sp.borderA, sp.borderSize, sp.borderTexture, sp.borderTextureOffset, sp.borderTextureOffsetY)
        end
        -- "Show Behind": set the level BEFORE ApplyStyle so the textured backdrop
        -- inherits it. +5 = in front (above bar-type secondaries), -1 = behind.
        if secondaryFrame._barBorder._frame then
            local pl = secondaryFrame:GetFrameLevel()
            secondaryFrame._barBorder._frame:SetFrameLevel(sp.borderBehind and math.max(0, pl - 1) or (pl + 5))
        end
        if ns.ERB_BarsBlizz() then
            -- Blizzard Style / Classic WoW UI: the stock bar frame replaces the
            -- full-bar border; pips keep their own borders and spacing. Under
            -- Blizzard Style the fill and backing (bar-type) or every pip/rune
            -- texture take the bar-shape mask, and the row carries the inner
            -- bevel: on the bar's own StatusBar for a bar-type, on an overlay
            -- above the pips otherwise, so a segmented row still reads as one
            -- recessed bar. Classic WoW UI creates no mask (every seat below
            -- is a no-op) and no bevel.
            secondaryFrame._barBorder:ApplyStyle(0,0,0,0,0)
            secondaryFrame._blizzVertical = isVertical or nil
            -- Sized from the row's target size: the frame may still be animating to it.
            ns.ERB_ApplyBlizzBarChrome(secondaryFrame, nil, frameW, frameH, isVertical, ns.ERB_BarFrameK(sp))
            local rowMask = secondaryFrame._blizzBarMask
            if secondaryBar then ns.ERB_SeatBlizzMask(secondaryFrame, secondaryBar) end
            local shade = secondaryFrame._blizzShadeFrame
            if ns.ERB_BarsClassic() then
                if shade then shade:Hide() end
            elseif isBarType then
                -- The bevel rides the overlay frame here too, over the layer
                -- bars (Ironfur / Ignore Pain) the bar-type stacks on its fill.
                local sb = secondaryBar and secondaryBar._sb
                if sb then
                    if not shade then
                        shade = CreateFrame("Frame", nil, secondaryFrame)
                        secondaryFrame._blizzShadeFrame = shade
                    end
                    shade:ClearAllPoints()
                    shade:SetAllPoints(sb)
                    shade:SetFrameLevel(secondaryFrame:GetFrameLevel() + 9)
                    shade._blizzVertical = isVertical
                    shade:Show()
                    ns.ERB_BlizzBarShadow(shade, rowMask)
                elseif shade then
                    shade:Hide()
                end
            else
                for i = 1, #pips do if pips[i] then ns.ERB_MaskPip(pips[i], rowMask) end end
                for i = 1, #runeFrames do if runeFrames[i] then ns.ERB_MaskPip(runeFrames[i], rowMask) end end
                if not shade then
                    shade = CreateFrame("Frame", nil, secondaryFrame)
                    secondaryFrame._blizzShadeFrame = shade
                end
                shade:ClearAllPoints()
                shade:SetAllPoints(secondaryFrame)
                -- Above the pips (+1) and their inner bars (up to six threshold
                -- bands plus the reset bar), below the rune countdown overlay
                -- (+10) and the count text (25).
                shade:SetFrameLevel(secondaryFrame:GetFrameLevel() + 9)
                shade._blizzVertical = isVertical
                shade:Show()
                ns.ERB_BlizzBarShadow(shade, rowMask)
            end
        elseif sp.borderOnPips and not isBarType then
            secondaryFrame._barBorder:ApplyStyle(0,0,0,0,0)
        else
            -- Extend Top / Extend Bottom: this full-bar border only (the two
            -- branches above pass none, so an extended host is re-seated).
            secondaryFrame._barBorder:ApplyStyle(sp.borderSize, sp.borderR, sp.borderG, sp.borderB, sp.borderA,
                sp.borderTexture, sp.borderTextureOffset, sp.borderTextureOffsetY,
                sp.borderTextureShiftX, sp.borderTextureShiftY, "resourcebars", sp.borderSize,
                EllesmereUI.BorderPx(sp.borderSizePx, sp.borderSize, sp.borderTexture), ns.ERB_BorderExtents(sp))
        end

        -- Full-bar background (behind all pips) -- what shows through the pip
        -- gaps. In dark theme inactive pips are opaque gray (DARK_BG, alpha 1), so
        -- a semi-transparent gap reads as "no background" next to them: force
        -- opaque black to keep a solid separator cohesive with the opaque pips.
        if not secondaryFrame._barBg then
            secondaryFrame._barBg = secondaryFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
        end
        -- Blizzard Style: the backdrop takes the bar-shape mask like the fills.
        if secondaryFrame._blizzBarMask and secondaryFrame._blizzMaskedBarBg ~= secondaryFrame._barBg then
            secondaryFrame._barBg:AddMaskTexture(secondaryFrame._blizzBarMask)
            secondaryFrame._blizzMaskedBarBg = secondaryFrame._barBg
        end
        secondaryFrame._barBg:ClearAllPoints()
        if secondaryBar and secondaryBar._fillOpApplied and secondaryBar:IsShown() then
            -- Bar-type Fill Opacity active: the full-bar backdrop must retreat to
            -- the empty portion too, or it tints the translucent fill from behind
            -- and defeats the world-show-through. Anchor to secondaryBar's own
            -- inset inner StatusBar (_sb), not the uninset outer secondaryFrame,
            -- or a sub-pixel sliver of _barBg peeks out past the fill's clipped edge.
            ns.AnchorBgToFillEdge(secondaryFrame._barBg, secondaryBar:GetStatusBarTexture(),
                secondaryBar._sb, sp.pipOrientation or "HORIZONTAL")
            secondaryFrame._barBg:Show()
        elseif pipBg or (sp.fillOpacity or 100) < 100 then
            -- Background on individual pips: every pip carries its own backdrop.
            -- Pip/rune-type Fill Opacity active: a full-frame backdrop cannot hole
            -- itself behind each active pip, so it would tint every translucent pip
            -- fill. Hide it; ApplyGapFills draws the gap strips in the bar-bg color
            -- and inactive pips keep their own per-pip background.
            secondaryFrame._barBg:Hide()
        elseif isBarType then
            -- Bar-type: anchor to secondaryBar's inset inner StatusBar (_sb) so
            -- _barBg does not extend a sub-pixel inset past the fill/bg's own clipped edge.
            secondaryFrame._barBg:SetAllPoints(secondaryBar._sb)
            secondaryFrame._barBg:Show()
        else
            -- Pip/rune-type: flush to secondaryFrame so this shows through the
            -- gaps between pips (see comment above).
            secondaryFrame._barBg:SetAllPoints(secondaryFrame)
            secondaryFrame._barBg:Show()
        end
        if sp.darkTheme then
            secondaryFrame._barBg:SetColorTexture(0, 0, 0, 1)
        else
            secondaryFrame._barBg:SetColorTexture(sp.barBgR or 0, sp.barBgG or 0, sp.barBgB or 0, sp.barBgA or 0.5)
        end
        ns.ERB_RoundSecondary(sp, isBarType)

        if sp.showText then
            if not secondaryFrame._countText then
                -- Parent to a high-level overlay so text renders above pip fills and borders
                if not secondaryFrame._countTextOverlay then
                    secondaryFrame._countTextOverlay = CreateFrame("Frame", nil, secondaryFrame)
                    secondaryFrame._countTextOverlay:SetAllPoints(secondaryFrame)
                end
                secondaryFrame._countTextOverlay:SetFrameLevel(secondaryFrame:GetFrameLevel() + 15)
                secondaryFrame._countText = secondaryFrame._countTextOverlay:CreateFontString(nil, "OVERLAY")
            end
            secondaryFrame._countText:SetTextColor(sp.textR or 1, sp.textG or 1, sp.textB or 1, 0.9)
            -- Keep overlay level current in case frame levels shifted: 15 over the
            -- slot (25 at its default 10; Draw Above Other Bars lifts the slot).
            if secondaryFrame._countTextOverlay then
                secondaryFrame._countTextOverlay:SetFrameLevel(secondaryFrame:GetFrameLevel() + 15)
            end
            secondaryFrame._countText:ClearAllPoints()
            secondaryFrame._countText:SetParent(secondaryFrame._countTextOverlay)
            local _spTA = sp.textAnchor or "CENTER"
            secondaryFrame._countText:SetPoint(_spTA, secondaryFrame, _spTA, sp.textXOffset, sp.textYOffset)
            SetRBFont(secondaryFrame._countText, GetRBFont(), sp.textSize)
            -- "Only if Power Bar Hidden": the fontstring is still created and
            -- updated (so text-value writes never hit nil), just hidden while the
            -- power bar is visible. Re-evaluated every build (spec/power changes
            -- trigger a rebuild, same as the shift feature).
            if _G._ERB_TextHiddenByForm(ERB.db.profile.secondary, true) or (sp.showTextOnlyIfNoPower and not IsPowerBarHidden()) then
                secondaryFrame._countText:Hide()
            else
                secondaryFrame._countText:Show()
            end
        elseif secondaryFrame._countText then
            secondaryFrame._countText:Hide()
        end

        -- Warrior charge buffs: hand the engine-slot module the resolved build
        -- (it parks itself for every other power type and non-warriors; see
        -- EUI_ResourceBars_WarriorCharges.lua). Must run after _countText is
        -- created and styled above -- the engine bakes its count-text font from
        -- this fontstring at slot-creation time and never re-reads it.
        if ns.WC_Sync then
            ns.WC_Sync(secondaryFrame, sp, cachedSecondary and cachedSecondary.power, g)
        end

        secondaryFrame:Show()
        if ns._erbArtOn then
            -- Blizzard's frame stands in: the slot stays shown and sized at zero alpha.
            EllesmereUI.SetElementVisibility(secondaryFrame, false)
        else
            secondaryFrame:SetAlpha(ns.ResolveBarAlpha(sp))
        end
    elseif secondaryFrame then
        -- Enabled but no resource for this spec: keep the frame positioned
        -- at zero alpha so anchored elements have a valid target.
        local pipH = sp.pipHeight or 20
        local pipW = sp.pipWidth or ((pp.width or 214))
        secondaryFrame:SetSize(pipW, pipH)
        secondaryFrame:Show()
        if not (EllesmereUI._TryOverrideAnchor and EllesmereUI._TryOverrideAnchor("ERB_ClassResource", secondaryFrame))
           and not EllesmereUI.IsUnlockAnchored("ERB_ClassResource") then
            if sp.unlockPos and sp.unlockPos.point then
                local rp = sp.unlockPos.relPoint or sp.unlockPos.point
                local sx, sy = SnapXY(sp.unlockPos.x, sp.unlockPos.y, secondaryFrame, sp.unlockPos)
                secondaryFrame:ClearAllPoints()
                secondaryFrame:SetPoint(sp.unlockPos.point, UIParent, rp, sx, sy)
            elseif not secondaryFrame:GetLeft() then
                secondaryFrame:ClearAllPoints()
                secondaryFrame:SetPoint("CENTER", mainFrame, "CENTER", sp.offsetX or 0, sp.offsetY or -74)
            end
        end
        EllesmereUI.SetElementVisibility(secondaryFrame, false)
    end

    -- Bottom Separator on the power bar, placed after the class resource block
    -- so it levels above both border stacks (inert unless it was ever on).
    ns.ERB_PowerSep(pp)

    -- Hash lines on the health and power bars
    do
        local _prof = ERB.db and ERB.db.profile
        if _prof then
            ns.ApplyHashLines(healthBar, _prof.health,
                function() return UnitHealthMax("player") end)
            ns.ApplyHashLines(primaryBar, _prof.primary,
                function() return UnitPowerMax("player", GetPrimaryPowerType()) end)
        end
    end

    ReapplyInternalBarAnchors()

    -- "Shift Elements if No Resource": re-cascade the class resource bar so
    -- anchored elements pick up (or drop) the temporary shift. The present/absent
    -- transition keeps the frame the same size, so neither OnSizeChanged nor the
    -- SetPoint move-hook fires and the cascade must be explicit. Gated so a
    -- None-forever profile schedules ZERO anchor work, and never fires during
    -- unlock mode (unlock entry/exit manage the shift).
    do
        local sp = ERB.db and ERB.db.profile and ERB.db.profile.secondary
        local active = sp ~= nil and (sp.shiftElementsIfNoResource == "Up"
            or sp.shiftElementsIfNoResource == "Down")
        -- Re-cascade only on an actual shift-state CHANGE (present<->absent, or
        -- feature toggled off) -- firing every BuildBars while merely enabled
        -- would re-walk the whole anchor chain each rebuild, a large CPU drain on
        -- a busy chain. The present<->absent transition is the only moment frame
        -- size is unchanged, hence the only moment the normal hooks miss.
        -- dir: 0 = present, +/-1 = absent.
        if not EllesmereUI._unlockActive and EllesmereUI.PropagateAnchorChain then
            local dir = 0
            if active and EllesmereUI._GetAnchorTargetShiftDir then
                dir = EllesmereUI._GetAnchorTargetShiftDir("ERB_ClassResource") or 0
            end
            if dir ~= (ERB._lastShiftDir or 0) then
                ERB._lastShiftDir = dir
                EllesmereUI.PropagateAnchorChain("ERB_ClassResource")
            end
        end
    end

    -- "Shift Elements if No Power": same re-cascade for the power bar. The
    -- present/absent transition (e.g. a Hunter swapping specs) keeps the frame
    -- size unchanged, so the cascade must be explicit; gated so a None-forever
    -- profile schedules ZERO anchor work, and never fires during unlock mode.
    do
        local pp = ERB.db and ERB.db.profile and ERB.db.profile.primary
        local active = pp ~= nil and (pp.shiftElementsIfNoPower == "Up"
            or pp.shiftElementsIfNoPower == "Down")
        -- Same transition-only guard as the class-resource block above: cascade
        -- only when the shift state actually changes, not every BuildBars call.
        if not EllesmereUI._unlockActive and EllesmereUI.PropagateAnchorChain then
            local dir = 0
            if active and EllesmereUI._GetAnchorTargetShiftDir then
                dir = EllesmereUI._GetAnchorTargetShiftDir("ERB_Power") or 0
            end
            if dir ~= (ERB._lastShiftDirPower or 0) then
                ERB._lastShiftDirPower = dir
                EllesmereUI.PropagateAnchorChain("ERB_Power")
            end
        end
    end

    -- WoW Forever druid mana bar (EUI_ResourceBars_ForeverDruidMana.lua):
    -- restyled after every Power Bar build; nil on every other client/class.
    if ns.FDM_Apply then ns.FDM_Apply(primaryBar, pp, g) end

    -- The stack layout just settled (build, spec, form, expand, shift and options all
    -- end here): ask Unit Frames to re-anchor its bottom-anchored player auras to the
    -- new footprint. This only arms its one-shot re-anchor for the next frame (no
    -- geometry is read here), and does nothing unless the player bottom-anchors auras.
    if EllesmereUI.UF_RequestResourceReanchor then EllesmereUI.UF_RequestResourceReanchor() end
end

I.ApplyResourceBarTicks, I.BuildBars = ApplyResourceBarTicks, BuildBars
I.EnsureIronfurOverlay, I.ironfurTickTex = EnsureIronfurOverlay, ironfurTickTex
I.broken = false
