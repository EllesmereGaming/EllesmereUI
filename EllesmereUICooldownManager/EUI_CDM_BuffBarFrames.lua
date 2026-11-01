if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_BuffBarFrames.lua
--
--  Bar frame creation, threshold overlays, tick marks, charge hash lines, the
--  spark anchor and ApplyTrackedBuffBarSettings.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._buffBarInternals
-- EllesmereUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local pcall = pcall
local max = math.max

local _classB, _classG, _classR, SetFont = I._classB, I._classG, I._classR, I.SetFont
local SetTBBTextColor, TBB_TEXTURES = I.SetTBBTextColor, I.TBB_TEXTURES
local _MarkTBBReflowDirty = I._MarkTBBReflowDirty

-------------------------------------------------------------------------------
--  Frame Creation
-------------------------------------------------------------------------------
local function CreateTrackedBuffBarFrame(parent, idx)
    local wrapFrame = CreateFrame("Frame", "ECME_TBBWrap" .. idx, parent)
    -- MEDIUM strata at level 100 by default (cfg.strata can move the whole bar via
    -- ApplyTrackedBuffBarSettings); level 100 keeps it above overlapping buff-icon
    -- displays (MEDIUM, low levels). Internal level order: strips +6 < glow +7 < text +8.
    wrapFrame:SetFrameStrata("MEDIUM")
    wrapFrame:SetFrameLevel(100)
    -- Visibility is a group reflow input: every Show/Hide edge, whichever path drives it, dirties the reflow.
    wrapFrame:SetScript("OnShow", _MarkTBBReflowDirty)
    wrapFrame:SetScript("OnHide", _MarkTBBReflowDirty)

    local bar = CreateFrame("StatusBar", "ECME_TBB" .. idx, wrapFrame)
    if bar.EnableMouseClicks then bar:EnableMouseClicks(false) end
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.65)
    bar:SetClipsChildren(true)
    wrapFrame._bar = bar

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    wrapFrame._bg = bg

    -- Spark on a dedicated overlay above the (gradient) fill and threshold overlays
    -- so it always draws OVER both; ApplyTrackedBuffBarSettings owns the final level
    -- (this value only holds until the first apply). Clipped to the bar so it never
    -- spills past the ends. SnapToPixelGrid off so it tracks the smoothly-interpolated
    -- fill edge at sub-pixel precision instead of jumping a pixel at a grid line.
    local sparkOverlay = CreateFrame("Frame", nil, bar)
    sparkOverlay:SetAllPoints(bar)
    sparkOverlay:SetClipsChildren(true)
    sparkOverlay:SetFrameLevel(bar:GetFrameLevel() + 2)
    wrapFrame._sparkOverlay = sparkOverlay
    local spark = sparkOverlay:CreateTexture(nil, "OVERLAY", nil, 7)
    spark:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga")
    spark:SetBlendMode("ADD")
    spark:SetSnapToPixelGrid(false)
    spark:SetTexelSnappingBias(0)
    spark:Hide()
    wrapFrame._spark = spark

    -- Gradient clip frame (created lazily in ApplySettings)
    wrapFrame._gradClip = nil
    wrapFrame._gradTex  = nil

    -- Text overlay: parented to wrapFrame (not bar) so bar's SetClipsChildren can't
    -- chop text when font size exceeds bar height. Level sits above the border (bar+6
    -- in ApplySettings, PP strips at +7) and the pandemic glow overlay (bar+8), so
    -- timer/name/stacks render on top of both; keyed off bar so they track together.
    local textOverlay = CreateFrame("Frame", nil, wrapFrame)
    textOverlay:SetAllPoints(bar)
    textOverlay:SetFrameLevel(bar:GetFrameLevel() + 9)
    wrapFrame._textOverlay = textOverlay

    -- Timer text
    local timerText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFont(timerText, 11)
    timerText:SetTextColor(1, 1, 1, 0.9)
    timerText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    timerText:SetJustifyH("RIGHT")
    wrapFrame._timerText = timerText

    -- Name text
    local nameText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFont(nameText, 11)
    nameText:SetTextColor(1, 1, 1, 0.9)
    nameText:SetPoint("LEFT", bar, "LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    wrapFrame._nameText = nameText

    -- Stacks text
    local stacksText = textOverlay:CreateFontString(nil, "OVERLAY")
    SetFont(stacksText, 11)
    stacksText:SetTextColor(1, 1, 1, 0.9)
    stacksText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    stacksText:Hide()
    wrapFrame._stacksText = stacksText

    -- Icon
    local icon = CreateFrame("Frame", nil, wrapFrame)
    icon:SetSize(24, 24)
    icon:Hide()
    local iconTex = icon:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    icon._tex = iconTex
    wrapFrame._icon = icon

    -- Border container
    local bdrContainer = CreateFrame("Frame", nil, wrapFrame)
    bdrContainer:SetAllPoints(wrapFrame)
    bdrContainer:SetFrameLevel(wrapFrame:GetFrameLevel() + 5)
    bdrContainer:Hide()
    wrapFrame._barBorder = bdrContainer

    -- Pandemic glow overlay above the border, whose PP strips draw at bar+7
    -- (border frame +6 plus the +1 the strip container adds), so a border
    -- cannot bury the edge-hugging glow (wrapFrame+9 = bar+8).
    local panGlow = CreateFrame("Frame", nil, wrapFrame)
    panGlow:SetAllPoints(wrapFrame)
    panGlow:SetFrameLevel(wrapFrame:GetFrameLevel() + 9)
    panGlow:SetAlpha(0)
    panGlow:EnableMouse(false)
    wrapFrame._pandemicGlowOverlay = panGlow

    wrapFrame:Hide()
    return wrapFrame
end

-------------------------------------------------------------------------------
--  Threshold Overlays (stacked StatusBars, secret-safe)
--
--  bar._stackCount may be a secret number, so it can NEVER be compared or sorted in
--  Lua. Each threshold gets its own StatusBar with range (value-1, value): SetValue
--  compares in the C layer, and the overlay snaps 0 -> full as the count crosses it.
--  With several thresholds every crossed overlay is full at once, so "highest
--  crossed wins" must be draw order, not an if: overlay i is parented to overlay i-1
--  (a child renders above its parent) and the list stays sorted ascending, so the
--  highest crossed threshold paints last. Frame levels stay pinned at sb+2, leaving
--  the tick overlay (sb+3) and charge hash lines (sb+4) on top.
-------------------------------------------------------------------------------
local function EnsureTBBThresholdOverlay(bar, i)
    local pool = bar._threshOverlays
    if not pool then pool = {}; bar._threshOverlays = pool end
    if pool[i] then return pool[i] end
    local sb = bar._bar
    if not sb then return nil end
    local overlay = CreateFrame("StatusBar", nil, pool[i - 1] or sb)
    overlay:SetAllPoints(sb:GetStatusBarTexture())
    overlay:SetFrameLevel(sb:GetFrameLevel() + 2)
    overlay:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    overlay:SetMinMaxValues(0, 1)
    overlay:SetValue(0)
    overlay:Hide()
    pool[i] = overlay
    return overlay
end

local function HideTBBThresholdOverlaysFrom(bar, first)
    local pool = bar._threshOverlays
    if not pool then return end
    for i = first, #pool do
        if pool[i] then pool[i]:Hide() end
    end
end

-- Multi-threshold list only when opted in and non-empty; nil means the legacy single-threshold keys own the rendering.
local function TBBMultiThresholdList(cfg)
    if not cfg.stackThresholdMulti then return nil end
    local list = cfg.stackThresholds
    if not list or #list == 0 then return nil end
    return list
end

local function ApplyTBBThresholdOverlay(overlay, sb, texPath, orient, reverse, i, r, g, b, a, value, blizzAtlas)
    overlay:SetStatusBarTexture(texPath)
    overlay:SetOrientation(orient)
    overlay:SetReverseFill(reverse)
    local tex = overlay:GetStatusBarTexture()
    -- Blizzard Style: the segment takes the same atlas as the fill it covers.
    if blizzAtlas then tex:SetAtlas("UI-HUD-CoolDownManager-Bar") end
    tex:SetVertexColor(r, g, b, a)
    tex:SetDrawLayer("ARTWORK", i)
    overlay:ClearAllPoints()
    overlay:SetAllPoints(sb:GetStatusBarTexture())
    overlay:SetMinMaxValues(value - 1, value)
    overlay:SetValue(0)
    overlay:Show()
end

local function SetupTBBThresholdOverlay(bar, cfg)
    if not cfg.stackThresholdEnabled
       or (cfg.trackType == "cooldown" and cfg.chargeHashLines == true) then
        HideTBBThresholdOverlaysFrom(bar, 1)
        return
    end
    local sb = bar._bar
    if not sb then return end
    local texPath = EllesmereUI.ResolveTexturePath(TBB_TEXTURES, cfg.texture or "none", "Interface\\Buttons\\WHITE8x8")
    local orient  = cfg.verticalOrientation and "VERTICAL" or "HORIZONTAL"
    local reverse = cfg.reverseFill and true or false

    local n = 0
    local list = TBBMultiThresholdList(cfg)
    if list then
        -- Sorted ascending by the options editor, so index order is draw order.
        for i = 1, #list do
            local t = list[i]
            local overlay = EnsureTBBThresholdOverlay(bar, i)
            if not overlay then break end
            ApplyTBBThresholdOverlay(overlay, sb, texPath, orient, reverse, i,
                t.r or 0.8, t.g or 0.1, t.b or 0.1, t.a or 1, t.value or 5, bar._blizzFillAtlas)
            n = i
        end
    else
        local overlay = EnsureTBBThresholdOverlay(bar, 1)
        if overlay then
            ApplyTBBThresholdOverlay(overlay, sb, texPath, orient, reverse, 1,
                cfg.stackThresholdR or 0.8, cfg.stackThresholdG or 0.1,
                cfg.stackThresholdB or 0.1, cfg.stackThresholdA or 1,
                cfg.stackThreshold or 5, bar._blizzFillAtlas)
            n = 1
        end
    end
    HideTBBThresholdOverlaysFrom(bar, n + 1)
end

local function FeedTBBThresholdOverlay(bar)
    local pool = bar._threshOverlays
    if not pool then return end
    local v = bar._stackCount or 0
    for i = 1, #pool do
        local overlay = pool[i]
        if overlay and overlay:IsShown() then overlay:SetValue(v) end
    end
end

-------------------------------------------------------------------------------
--  Tick Marks
-------------------------------------------------------------------------------
-- Cooldown state must follow the SAVED spell, not the transient override
-- returned for an icon while a proc is active. The base fallback only handles
-- a saved talent override that is no longer learned.
local function StableCooldownSpellID(cfg)
    local sid = cfg and cfg.spellID
    if type(sid) ~= "number" or sid <= 0 then return nil end
    local base = cfg.baseSpellID
    if type(base) == "number" and base > 0 and IsPlayerSpell
       and not IsPlayerSpell(sid) and IsPlayerSpell(base) then
        return base
    end
    return sid
end

local function GetTBBMaxCharges(cfg)
    if not cfg or cfg.trackType ~= "cooldown" then return nil end
    local sid = StableCooldownSpellID(cfg)
    local ch = sid and C_Spell and C_Spell.GetSpellCharges
        and C_Spell.GetSpellCharges(sid)
    local maxCharges = ch and ch.maxCharges
    if issecretvalue and issecretvalue(maxCharges) then return nil end
    if type(maxCharges) == "number" and maxCharges > 1 then
        return math.floor(maxCharges + 0.5)
    end
    return nil
end
ns.GetTBBMaxCharges = GetTBBMaxCharges

-- "all" (any case, anywhere in the list) puts a tick between every stack: N
-- stacks give N-1 interior divisions, the same convention as the charge hash
-- lines below. Numbers listed alongside it are redundant and ignored.
local function ParseTickValues(str, maxStacks)
    if not str or str == "" then return nil end
    local vals = {}
    for s in str:gmatch("[^,]+") do
        local tok = s:match("^%s*(.-)%s*$")
        if tok:lower() == "all" then
            local m = maxStacks and math.floor(maxStacks) or 0
            if m < 2 then return nil end
            local out = {}
            for i = 1, m - 1 do out[i] = i end
            return out
        end
        local n = tonumber(tok)
        if n and n > 0 then vals[#vals + 1] = n end
    end
    return #vals > 0 and vals or nil
end

local function ApplyTBBTickMarks(sb, cfg, tickCache, isVert, tickParent)
    local maxStacks = cfg.stackThresholdMax or 10
    local vals = ParseTickValues(cfg.stackThresholdTicks, maxStacks)
    if tickCache then
        for i = 1, #tickCache do tickCache[i]:Hide() end
    end
    -- Ticks are governed by Max Stacks alone (the options input unlocks with it); Enable Stack Threshold only drives the recolor overlay, not ticks.
    if (cfg.trackType == "cooldown" and cfg.chargeHashLines == true)
       or not cfg.stackThresholdMaxEnabled
       or not vals or maxStacks < 1 or not tickCache then return end

    local PP = EllesmereUI and EllesmereUI.PP
    local parent = tickParent or sb
    while #tickCache < #vals do
        local t = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
        tickCache[#tickCache + 1] = t
    end

    -- Legacy bars carry no tick-color fields: fall back to white so their ticks render unchanged.
    local tickR = cfg.stackThresholdTickR or 1
    local tickG = cfg.stackThresholdTickG or 1
    local tickB = cfg.stackThresholdTickB or 1
    local tickA = cfg.stackThresholdTickA
    if tickA == nil then tickA = 1 end

    local onePx = PP and PP.Scale(1) or 1
    local barW, barH = sb:GetWidth(), sb:GetHeight()
    -- Ticks measure stack fractions from the fill's ORIGIN, so they mirror when Reverse Fill moves the origin to the other end.
    local reverse = cfg.reverseFill and true or false
    for i, v in ipairs(vals) do
        if v <= maxStacks then
            local t = tickCache[i]
            local frac = v / maxStacks
            t:SetColorTexture(tickR, tickG, tickB, tickA)
            t:ClearAllPoints()
            if isVert then
                local off = PP and PP.Scale(barH * frac) or (barH * frac)
                t:SetSize(barW, onePx)
                if reverse then
                    t:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, -off)
                else
                    t:SetPoint("BOTTOMLEFT", sb, "BOTTOMLEFT", 0, off)
                end
            else
                local off = PP and PP.Scale(barW * frac) or (barW * frac)
                t:SetSize(onePx, barH)
                if reverse then
                    t:SetPoint("TOPRIGHT", sb, "TOPRIGHT", -off, 0)
                else
                    t:SetPoint("TOPLEFT", sb, "TOPLEFT", off, 0)
                end
            end
            t:Show()
        end
    end
end
ns.ApplyTBBTickMarks = ApplyTBBTickMarks

-- Charge separators are fixed geometry over the full StatusBar: N charges give
-- N-1 separators. Equal divisions do not move when Reverse Fill changes the
-- recovery origin; vertical bars just rotate the marks.
local function ApplyTBBChargeHashLines(bar, cfg, maxCharges)
    if not bar or not cfg then return end
    local sb = bar._bar
    if not sb then return end

    local ticks = bar._chargeHashTicks
    if cfg.chargeHashLines ~= true or cfg.trackType ~= "cooldown"
       or type(maxCharges) ~= "number" or maxCharges <= 1 then
        if ticks then
            for i = 1, #ticks do ticks[i]:Hide() end
        end
        bar._chargeHashLineCacheValid = nil
        if bar._chargeHashOverlay then bar._chargeHashOverlay:Hide() end
        return
    end

    local barW, barH = sb:GetWidth(), sb:GetHeight()
    if not barW or not barH or barW <= 0 or barH <= 0 then
        if ticks then
            for i = 1, #ticks do ticks[i]:Hide() end
        end
        if bar._chargeHashOverlay then bar._chargeHashOverlay:Hide() end
        bar._chargeHashLineCacheValid = nil
        return
    end

    local width = tonumber(cfg.chargeHashLineWidth) or 2
    width = math.max(1, math.min(10, math.floor(width + 0.5)))
    local lineR = cfg.chargeHashLineR or 0
    local lineG = cfg.chargeHashLineG or 0
    local lineB = cfg.chargeHashLineB or 0
    local lineA = cfg.chargeHashLineA
    if lineA == nil then lineA = 1 end
    local isVert = cfg.verticalOrientation and true or false
    local reverse = cfg.reverseFill and true or false
    local effectiveScale = sb:GetEffectiveScale() or 1
    -- Also runs from the shared timer tick, so the cache stays SCALAR: synthesized table/string keys would allocate even on a cache hit.
    if bar._chargeHashLineCacheValid
       and bar._chargeHashLineMaxCharges == maxCharges
       and bar._chargeHashLineWidth == width
       and bar._chargeHashLineVertical == isVert
       and bar._chargeHashLineReverse == reverse
       and bar._chargeHashLineBarW == barW
       and bar._chargeHashLineBarH == barH
       and bar._chargeHashLineScale == effectiveScale
       and bar._chargeHashLineR == lineR
       and bar._chargeHashLineG == lineG
       and bar._chargeHashLineB == lineB
       and bar._chargeHashLineA == lineA
       and bar._chargeHashOverlay and bar._chargeHashOverlay:IsShown() then
        return
    end

    if ticks then
        for i = 1, #ticks do ticks[i]:Hide() end
    end

    if not bar._chargeHashOverlay then
        local overlay = CreateFrame("Frame", nil, sb)
        overlay:SetAllPoints(sb)
        overlay:SetFrameLevel(sb:GetFrameLevel() + 5)
        bar._chargeHashOverlay = overlay
    end
    bar._chargeHashOverlay:Show()
    if not ticks then
        ticks = {}
        bar._chargeHashTicks = ticks
    end

    while #ticks < maxCharges - 1 do
        local tick = bar._chargeHashOverlay:CreateTexture(nil, "OVERLAY", nil, 7)
        tick:SetSnapToPixelGrid(false)
        tick:SetTexelSnappingBias(0)
        ticks[#ticks + 1] = tick
    end

    -- Divider boundary bars: hidden StatusBars frozen at value i of maxCharges (clean
    -- constants). Their texture edges come from the same engine math as the charge hash
    -- fill's live countTexture edge, so ticks centered here leave no sub-pixel sliver
    -- beside the partial-charge shade at any bar width (a PP.Scale-snapped offset could
    -- sit up to a physical pixel off that native edge and shimmer at unlucky widths).
    local divBars = bar._chargeHashDivBars
    if not divBars then divBars = {}; bar._chargeHashDivBars = divBars end
    for i = 1, maxCharges - 1 do
        local db2 = divBars[i]
        if not db2 then
            db2 = CreateFrame("StatusBar", nil, sb)
            db2:SetAllPoints(sb)
            db2:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            local dt = db2:GetStatusBarTexture()
            dt:SetSnapToPixelGrid(false)
            dt:SetTexelSnappingBias(0)
            db2:SetAlpha(0)
            db2:EnableMouse(false)
            divBars[i] = db2
        end
        db2:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
        db2:SetReverseFill(reverse)
        db2:SetMinMaxValues(0, maxCharges)
        db2:SetValue(i)
        db2:Show()
    end
    for i = maxCharges, #divBars do divBars[i]:Hide() end

    local PP = EllesmereUI and EllesmereUI.PP
    local lineWidth = PP and PP.Scale(width) or width
    local halfLine = lineWidth / 2
    for i = 1, maxCharges - 1 do
        local tick = ticks[i]
        local divTex = divBars[i] and divBars[i]:GetStatusBarTexture()
        tick:SetColorTexture(lineR, lineG, lineB, lineA)
        tick:ClearAllPoints()
        if isVert then
            tick:SetSize(barW, lineWidth)
            if divTex then
                if reverse then
                    tick:SetPoint("TOP", divTex, "BOTTOM", 0, halfLine)
                else
                    tick:SetPoint("BOTTOM", divTex, "TOP", 0, -halfLine)
                end
            else
                local offset = PP and PP.Scale(barH * (i / maxCharges)) or (barH * (i / maxCharges))
                tick:SetPoint("CENTER", sb, "BOTTOM", 0, offset)
            end
        else
            tick:SetSize(lineWidth, barH)
            if divTex then
                if reverse then
                    tick:SetPoint("RIGHT", divTex, "LEFT", halfLine, 0)
                else
                    tick:SetPoint("LEFT", divTex, "RIGHT", -halfLine, 0)
                end
            else
                local offset = PP and PP.Scale(barW * (i / maxCharges)) or (barW * (i / maxCharges))
                tick:SetPoint("CENTER", sb, "LEFT", offset, 0)
            end
        end
        tick:Show()
    end
    for i = maxCharges, #ticks do ticks[i]:Hide() end
    bar._chargeHashLineCacheValid = true
    bar._chargeHashLineMaxCharges = maxCharges
    bar._chargeHashLineWidth = width
    bar._chargeHashLineVertical = isVert
    bar._chargeHashLineReverse = reverse
    bar._chargeHashLineBarW = barW
    bar._chargeHashLineBarH = barH
    bar._chargeHashLineScale = effectiveScale
    bar._chargeHashLineR = lineR
    bar._chargeHashLineG = lineG
    bar._chargeHashLineB = lineB
    bar._chargeHashLineA = lineA
end
-- Exported for the options popout preview: its bars have no timer tick to re-drive width-gated geometry once the fill's anchor-derived size resolves.
ns.ApplyTBBChargeHashLines = ApplyTBBChargeHashLines

local function AnchorTBBSparkState(bar, anchor, isVert, reverse, flushToEdge)
    local sb, spark = bar and bar._bar, bar and bar._spark
    if not sb or not spark or not anchor then return end
    isVert = isVert and true or false
    reverse = reverse and true or false
    flushToEdge = flushToEdge and true or false
    local barW, barH = sb:GetWidth(), sb:GetHeight()
    if bar._sparkAnchorTarget == anchor
       and bar._sparkAnchorVertical == isVert
       and bar._sparkAnchorReverse == reverse
       and bar._sparkAnchorFlush == flushToEdge
       and bar._sparkAnchorBarW == barW
       and bar._sparkAnchorBarH == barH then
        return
    end
    -- Blizzard Style pip is an atlas: an 8-coord rotation would sample the
    -- whole sheet, so its coords are left to the atlas (vertical bars keep the
    -- upright pip).
    -- The classic pip is the vanilla cast bar spark, a 32px square on a 13px
    -- bar, scaled by the bar's thickness (the overlay clips it to the bar).
    local classicSz = bar._classicSpark and ((isVert and barW or barH) * (32 / 13))
    if isVert then
        if classicSz then spark:SetSize(classicSz, classicSz) else spark:SetSize(barW, 8) end
        if not bar._blizzSpark then spark:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0) end
    else
        if classicSz then spark:SetSize(classicSz, classicSz) else spark:SetSize(8, barH) end
        if not bar._blizzSpark then spark:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1) end
    end
    spark:ClearAllPoints()
    if isVert then
        spark:SetPoint("CENTER", anchor, reverse and "BOTTOM" or "TOP", 0, 0)
    else
        spark:SetPoint("CENTER", anchor,
            reverse and "LEFT" or "RIGHT",
            flushToEdge and 0 or (reverse and 1 or -1), 0)
    end
    bar._sparkAnchorTarget = anchor
    bar._sparkAnchorVertical = isVert
    bar._sparkAnchorReverse = reverse
    bar._sparkAnchorFlush = flushToEdge
    bar._sparkAnchorBarW = barW
    bar._sparkAnchorBarH = barH
end

local function AnchorTBBSpark(bar, cfg, anchor, flushToEdge)
    if not cfg then return end
    AnchorTBBSparkState(bar, anchor, cfg.verticalOrientation,
        cfg.reverseFill, flushToEdge)
end

-- Stock style icon art for a tracked bar's icon over the full spell art,
-- sized to the icon square. Blizzard Style: the viewer's rounded mask and
-- ring overlay (same proportional inset as the CDM icons). Classic WoW UI:
-- the vanilla action button ring round the square icon, no mask. One-time
-- structure, size-memoized geometry; never runs unless a style is on.
ns.ApplyTBBBlizzIconArt = function(bar, iSize)
    local icon = bar._icon
    local tex = icon and icon._tex
    if not tex then return end
    local classic = ns.CdmClassicBars()
    if not bar._blizzIconOverlay then
        tex:SetTexCoord(0, 1, 0, 1)
        if not classic then
            local mask = icon:CreateMaskTexture()
            mask:SetAtlas(ns.CDM_BLIZZ_MASK)
            mask:SetAllPoints(icon)
            tex:AddMaskTexture(mask)
            bar._blizzIconMask = mask
        end
        local ov = icon:CreateTexture(nil, "OVERLAY", nil, 5)
        if classic then ov:SetTexture(ns.CDM_CLASSIC_RING) else ns.CdmStockAtlas(ov, ns.CDM_BLIZZ_OVERLAY, true) end
        ov:SetSnapToPixelGrid(false)
        ov:SetTexelSnappingBias(0)
        bar._blizzIconOverlay = ov
    end
    -- The ring overhangs the bar, so the icon draws above the fill (the
    -- viewer levels its icon above its bar the same way) and, under classic,
    -- above the cast bar chrome (+6) whose end caps reach under it;
    -- re-asserted here because a strata change collapses child levels.
    if bar._bar then
        local lvl = bar._bar:GetFrameLevel() + (classic and 7 or 3)
        if icon:GetFrameLevel() ~= lvl then icon:SetFrameLevel(lvl) end
    end
    if bar._blizzIconSize ~= iSize then
        bar._blizzIconSize = iSize
        local ov = bar._blizzIconOverlay
        if classic then
            ns.CdmPlaceClassicRing(ov, icon, iSize, iSize)
        else
            ov:ClearAllPoints()
            ov:SetPoint("TOPLEFT", icon, "TOPLEFT", -iSize * ns.CDM_BLIZZ_RING_X, iSize * ns.CDM_BLIZZ_RING_Y)
            ov:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", iSize * ns.CDM_BLIZZ_RING_X, -iSize * ns.CDM_BLIZZ_RING_Y)
        end
    end
end

-- Classic WoW UI bar chrome: the vanilla cast bar frame (the shared
-- nine-slice in EllesmereUI_ClassicArt.lua, caps and rims at the sheet's own
-- pixel size, only the window stretching) laid over the tracked bar's fill on
-- an art frame above the fill, its threshold overlays, spark, ticks and
-- charge hash lines, below the texts and the icon. The frame's reach (14.5
-- left and right, 12 above and 11 below the fill at full size) is fixed
-- whatever the bar's size, scaled only by the bar's own Border Size
-- percentage (`pct`, nil = the shared default), so a bar in a tight group
-- never paints across its neighbour; a vertical bar turns the art a quarter
-- turn counter-clockwise. One-time regions, geometry memoized by the seat.
ns.CDM_CLASSIC_BAR_SPARK  = "Interface\\CastingBar\\UI-CastingBar-Spark"
ns.ApplyTBBClassicChrome = function(bar, sb, isVert, thick, pct)
    local CF = EllesmereUI.ClassicFrame
    if not CF then return end
    local art = bar._classicArt
    if not art then
        art = CreateFrame("Frame", nil, bar)
        art:SetAllPoints(sb)
        art:EnableMouse(false)
        bar._classicArt = art
        bar._classicChrome = CF.Create(art, "OVERLAY", 0)
    end
    -- Above the fill, threshold overlays (+2), the spark's own host, ticks
    -- (+4) and the charge hash lines (+5); below the icon (+7) and the text
    -- overlay (+7). Re-asserted because a strata change collapses child levels.
    local lvl = sb:GetFrameLevel() + 6
    if art:GetFrameLevel() ~= lvl then art:SetFrameLevel(lvl) end
    CF.Seat(bar._classicChrome, art, CF.ScaleK(pct), isVert)
end

-- Defined with the charge renderer (EUI_CDM_BuffBarCooldown.lua). ApplySettings calls it whenever a
-- pooled bar frame is restyled so stale composite geometry cannot leak into a
-- different bar after deletion, reordering or a tracking-type change.
local _restoreTBBNormalFill
I.restoreNormalFillSetters[#I.restoreNormalFillSetters + 1] = function(v) _restoreTBBNormalFill = v end

-------------------------------------------------------------------------------
--  Apply Visual Settings
-------------------------------------------------------------------------------
local function ApplyTrackedBuffBarSettings(bar, cfg)
    if not bar or not cfg then return end
    local sb = bar._bar
    if not sb then return end
    -- Stock styles (Global Settings > Style) with every setting still
    -- applied: Blizzard Style = the viewer's bar, background and pip art;
    -- Classic WoW UI = the vanilla cast bar frame and spark round the user's
    -- own fill and background. Reload-gated, so the per-bar one-time setup
    -- below never has to be undone.
    local blizzBar = ns.CdmBlizzBars()
    local classicBar = ns.CdmClassicBars()
    if blizzBar and not classicBar and not bar._blizzSpark and bar._spark then
        bar._blizzSpark = true
        bar._spark:SetAtlas("UI-HUD-CoolDownManager-Bar-Pip")
        bar._spark:SetBlendMode("BLEND")
    elseif classicBar and not bar._classicSpark and bar._spark then
        bar._classicSpark = true
        bar._spark:SetTexture(ns.CDM_CLASSIC_BAR_SPARK)
        -- The vanilla spark stands taller than the bar: its host leaves the
        -- clipping StatusBar for the wrap (same rect) so it can overhang, as
        -- the cast bar's does; the strata block below levels it over the chrome.
        local so = bar._sparkOverlay
        if so then
            so:SetParent(bar)
            so:ClearAllPoints()
            so:SetAllPoints(sb)
            so:SetClipsChildren(false)
        end
    end
    if _restoreTBBNormalFill then _restoreTBBNormalFill(bar, cfg) end

    -- User-selectable strata for the whole bar (options setter keeps grouped bars
    -- uniform). A parent strata change COLLAPSES child frame levels, so the wrap
    -- level and the constructor's internal ladder are re-asserted whenever strata
    -- actually changes; the change guard keeps the common repaint path free of it.
    local strata = cfg.strata or "MEDIUM"
    if bar._lastStrata ~= strata then
        bar._lastStrata = strata
        bar:SetFrameStrata(strata)
        bar:SetFrameLevel(100)
        local base = bar:GetFrameLevel()
        sb:SetFrameLevel(base + 1)
        if bar._gradClip then bar._gradClip:SetFrameLevel(sb:GetFrameLevel() + 1) end
        if bar._chargeHashFillClip then bar._chargeHashFillClip:SetFrameLevel(sb:GetFrameLevel() + 1) end
        if bar._threshOverlays then
            for i = 1, #bar._threshOverlays do
                local ov = bar._threshOverlays[i]
                if ov then ov:SetFrameLevel(sb:GetFrameLevel() + 2) end
            end
        end
        -- Spark sits one level ABOVE the threshold overlays: at equal level it
        -- loses the tie to them (created lazily, so they win) and vanishes the
        -- moment a threshold is crossed. Ticks and charge hash lines shift up
        -- in step to keep their order. The classic spark rides above the
        -- chrome instead, as the vanilla spark draws over its frame: sb+8, above
        -- the pandemic glow (base+8), level with the text.
        if bar._sparkOverlay then bar._sparkOverlay:SetFrameLevel(sb:GetFrameLevel() + (classicBar and 8 or 3)) end
        -- Tick overlay MUST be re-asserted here too: SetFrameStrata collapses descendant levels, so otherwise ticks land at a default level.
        if bar._tickOverlay then bar._tickOverlay:SetFrameLevel(sb:GetFrameLevel() + 4) end
        if bar._chargeHashOverlay then bar._chargeHashOverlay:SetFrameLevel(sb:GetFrameLevel() + 5) end
        -- Border at base+6, not +5: tick marks sit at sb+4 (= base+5), which
        -- would TIE the border cross-subtree, and the lazily-created tick overlay wins
        -- ties, putting ticks ON TOP of the border. One level up keeps the border above
        -- ticks; charge hash lines tie it and win via later creation, as intended.
        if bar._barBorder then bar._barBorder:SetFrameLevel(base + 6) end
        -- Glow +8: the border's PP strips draw at +7 and would tie it; text stays on top.
        if bar._pandemicGlowOverlay then bar._pandemicGlowOverlay:SetFrameLevel(base + 8) end
        if bar._textOverlay then bar._textOverlay:SetFrameLevel(sb:GetFrameLevel() + 8) end
    end

    -- width/height are always VISUAL dimensions describing the bar's TOTAL footprint,
    -- icon included: the wrap is exactly width x height and a shown icon carves its
    -- square out of the fill. Horizontal: width=long side, height=short side.
    -- Vertical: width=short side, height=long side.
    local PPt = EllesmereUI and EllesmereUI.PP
    local snap = PPt and PPt.Snap or function(v) return v end
    local w = snap(cfg.width or 270)
    local h = snap(cfg.height or 24)
    local isVert = cfg.verticalOrientation
    bar._lastVertical = isVert
    local iconMode = cfg.iconDisplay or "none"
    local hasIcon = iconMode ~= "none"
    local iSize = isVert and w or h
    if hasIcon then
        -- Never let the icon square consume the whole footprint
        local long = isVert and h or w
        if iSize > long - 1 then iSize = max(1, long - 1) end
    end

    bar:SetSize(w, h)

    -- Position StatusBar inside wrapFrame
    sb:ClearAllPoints()
    if hasIcon then
        if isVert then
            if iconMode == "left" then
                -- Left = Top for vertical
                sb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -iSize)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            else
                -- Right = Bottom for vertical
                sb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, iSize)
            end
        else
            if iconMode == "left" then
                sb:SetPoint("TOPLEFT", bar, "TOPLEFT", iSize, 0)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
            else
                sb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
                sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -iSize, 0)
            end
        end
    else
        sb:SetAllPoints(bar)
    end

    -- Orientation and fill direction
    sb:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
    sb:SetReverseFill(cfg.reverseFill and true or false)

    -- Texture
    local texPath = EllesmereUI.ResolveTexturePath(TBB_TEXTURES, cfg.texture or "none", "Interface\\Buttons\\WHITE8x8")
    if blizzBar and not classicBar then
        -- The viewer's bar atlas (tinted by Fill Color below). _lastTexPath
        -- stays a real file path: the charge hash fill re-reads it. Classic
        -- keeps the user's texture: its frame is chrome round the fill.
        texPath = "Interface\\Buttons\\WHITE8x8"
        if not bar._blizzFillAtlas then
            sb:SetStatusBarTexture(texPath)
            sb:GetStatusBarTexture():SetAtlas("UI-HUD-CoolDownManager-Bar")
            bar._lastTexPath = texPath
            bar._blizzFillAtlas = true
        end
    elseif bar._lastTexPath ~= texPath then
        sb:SetStatusBarTexture(texPath)
        bar._lastTexPath = texPath
    end
    local fillTex = sb:GetStatusBarTexture()
    bar._cachedOurFillTex = fillTex

    -- Fill color
    local fR = cfg.fillR or _classR
    local fG = cfg.fillG or _classG
    local fB = cfg.fillB or _classB
    local fA = cfg.fillA or 1
    fillTex:SetVertexColor(fR, fG, fB, fA)
    bar._baseFillR, bar._baseFillG, bar._baseFillB, bar._baseFillA = fR, fG, fB, fA

    -- Background
    if blizzBar and not classicBar then
        -- The viewer's shadowed bar background overhangs the fill, so it lives
        -- on the wrap (the StatusBar clips its own regions).
        if bar._bg then bar._bg:Hide() end
        local bbg = bar._blizzBg
        if not bbg then
            bbg = bar:CreateTexture(nil, "BACKGROUND")
            bbg:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
            -- Anchored once: the fill StatusBar is the bar's for life.
            bbg:SetPoint("TOPLEFT", sb, "TOPLEFT", -2, 2)
            bbg:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 4, -7)
            bar._blizzBg = bbg
        end
        bbg:Show()
    elseif bar._bg then
        bar._bg:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgA or 0.4)
    end
    -- Classic WoW UI: the vanilla cast bar frame over the fill and background.
    if classicBar then ns.ApplyTBBClassicChrome(bar, sb, isVert, isVert and w or h, cfg.stockBorderScale) end

    -- Gradient (an EUI-look effect; the stock styles keep their flat fill)
    if cfg.gradientEnabled and not blizzBar then
        local dir = cfg.gradientDir or "HORIZONTAL"
        fillTex:SetVertexColor(1, 1, 1, 0)
        if not bar._gradClip then
            local clip = CreateFrame("Frame", nil, sb)
            clip:SetClipsChildren(true)
            clip:SetFrameLevel(sb:GetFrameLevel() + 1)
            local tex = clip:CreateTexture(nil, "ARTWORK", nil, 1)
            tex:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
            bar._gradClip = clip
            bar._gradTex  = tex
        end
        bar._gradClip:ClearAllPoints()
        bar._gradClip:SetAllPoints(fillTex)
        bar._gradTex:SetTexture(texPath)
        bar._gradTex:SetVertexColor(1, 1, 1, 1)
        bar._gradTex:SetGradient(dir,
            CreateColor(fR, fG, fB, fA),
            CreateColor(cfg.gradientR or 0.20, cfg.gradientG or 0.20, cfg.gradientB or 0.80, cfg.gradientA or 1))
        bar._gradClip:Show()
        bar._gradientActive = true
    else
        if bar._gradClip then bar._gradClip:Hide() end
        bar._gradientActive = nil
        fillTex:SetVertexColor(fR, fG, fB, fA)
    end

    -- Opacity
    bar._opacityTarget = cfg.opacity or 1.0
    if not bar._tbbReady then bar:SetAlpha(bar._opacityTarget) end

    SetTBBTextColor(bar._timerText, cfg, "timer")
    SetTBBTextColor(bar._nameText, cfg, "name")
    SetTBBTextColor(bar._stacksText, cfg, "stacks")

    -- Timer text. Vertical bars honor the same position choices as horizontal: left/right sit OUTSIDE the (thin) bar, top/bottom above/below it, center inside.
    local timerPos = cfg.timerPosition or (cfg.showTimer and "right" or "none")
    if timerPos ~= "none" then
        bar._timerText:Show()
        SetFont(bar._timerText, cfg.timerSize or 11)
        bar._timerText:ClearAllPoints()
        local tX, tY = cfg.timerX or 0, cfg.timerY or 0
        if isVert and timerPos == "center" then
            bar._timerText:SetPoint("CENTER", sb, "CENTER", tX, tY)
            bar._timerText:SetJustifyH("CENTER")
        elseif isVert and timerPos == "top" then
            bar._timerText:SetPoint("BOTTOM", sb, "TOP", tX, 5 + tY)
            bar._timerText:SetJustifyH("CENTER")
        elseif isVert and timerPos == "bottom" then
            bar._timerText:SetPoint("TOP", sb, "BOTTOM", tX, -5 + tY)
            bar._timerText:SetJustifyH("CENTER")
        elseif isVert and timerPos == "left" then
            bar._timerText:SetPoint("RIGHT", sb, "LEFT", -5 + tX, tY)
            bar._timerText:SetJustifyH("RIGHT")
        elseif isVert then
            bar._timerText:SetPoint("LEFT", sb, "RIGHT", 5 + tX, tY)
            bar._timerText:SetJustifyH("LEFT")
        elseif timerPos == "center" then
            bar._timerText:SetPoint("CENTER", sb, "CENTER", tX, tY)
            bar._timerText:SetJustifyH("CENTER")
        elseif timerPos == "top" then
            bar._timerText:SetPoint("BOTTOM", sb, "TOP", tX, 5 + tY)
            bar._timerText:SetJustifyH("CENTER")
        elseif timerPos == "bottom" then
            bar._timerText:SetPoint("TOP", sb, "BOTTOM", tX, -5 + tY)
            bar._timerText:SetJustifyH("CENTER")
        elseif timerPos == "left" then
            bar._timerText:SetPoint("LEFT", sb, "LEFT", 5 + tX, tY)
            bar._timerText:SetJustifyH("LEFT")
        else
            bar._timerText:SetPoint("RIGHT", sb, "RIGHT", -5 + tX, tY)
            bar._timerText:SetJustifyH("RIGHT")
        end
    else
        bar._timerText:Hide()
    end

    -- Spark anchors to the MOVING edge of the fill. With Reverse Fill the fill anchors at the far end and the near edge moves, so the spark side flips.
    bar._lastReverse = cfg.reverseFill and true or false
    if cfg.showSpark then
        local sparkAnchor = (bar._gradientActive and bar._gradClip) or fillTex
        AnchorTBBSpark(bar, cfg, sparkAnchor)
        bar._spark:Show()
    else
        bar._spark:Hide()
    end

    -- Name text
    local namePos = cfg.namePosition or ((cfg.showName ~= false) and "left" or "none")
    if namePos ~= "none" and not isVert then
        bar._nameText:Show()
        SetFont(bar._nameText, cfg.nameSize or 11)
        bar._nameText:ClearAllPoints()
        local nX, nY = cfg.nameX or 0, cfg.nameY or 0
        if namePos == "center" then
            bar._nameText:SetPoint("CENTER", sb, "CENTER", nX, nY)
            bar._nameText:SetJustifyH("CENTER")
        elseif namePos == "top" then
            bar._nameText:SetPoint("BOTTOM", sb, "TOP", nX, 5 + nY)
            bar._nameText:SetJustifyH("CENTER")
        elseif namePos == "bottom" then
            bar._nameText:SetPoint("TOP", sb, "BOTTOM", nX, -5 + nY)
            bar._nameText:SetJustifyH("CENTER")
        elseif namePos == "right" then
            bar._nameText:SetPoint("RIGHT", sb, "RIGHT", -5 + nX, nY)
            bar._nameText:SetJustifyH("RIGHT")
        else
            bar._nameText:SetPoint("LEFT", sb, "LEFT", 5 + nX, nY)
            bar._nameText:SetJustifyH("LEFT")
        end
        -- Text width + wrap mode (icon's square is not text space). Wrap on: 2 lines within
        -- the text area. Off (default): one line truncated with an ellipsis at 85% of fill width.
        local fillW = hasIcon and (w - iSize) or w
        if cfg.nameWrap then
            bar._nameText:SetWordWrap(true)
            bar._nameText:SetMaxLines(2)
            bar._nameText:SetWidth(fillW - 12 - (cfg.showTimer and 50 or 0))
        else
            bar._nameText:SetWordWrap(false)
            bar._nameText:SetMaxLines(1)
            bar._nameText:SetWidth(fillW * 0.85)
        end
    else
        bar._nameText:Hide()
    end

    -- Icon
    if hasIcon and bar._icon then
        bar._icon:SetSize(iSize, iSize)
        bar._icon:ClearAllPoints()
        if isVert then
            if iconMode == "left" then
                bar._icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            else
                bar._icon:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
            end
        else
            if iconMode == "left" then
                bar._icon:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            else
                bar._icon:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
            end
        end
        if blizzBar then ns.ApplyTBBBlizzIconArt(bar, iSize) end
        bar._icon:Show()
    elseif bar._icon then
        bar._icon:Hide()
    end

    -- Stacks text positioning
    if bar._stacksText then
        local sPos = cfg.stacksPosition or "center"
        if sPos == "none" then
            bar._stacksText:Hide()
            bar._stacksHidden = true
        else
            bar._stacksHidden = nil
            SetFont(bar._stacksText, cfg.stacksSize or 11)
            bar._stacksText:ClearAllPoints()
            local sX, sY = cfg.stacksX or 0, cfg.stacksY or 0
            if sPos == "top" then
                bar._stacksText:SetPoint("BOTTOM", sb, "TOP", sX, 5 + sY)
            elseif sPos == "bottom" then
                bar._stacksText:SetPoint("TOP", sb, "BOTTOM", sX, -5 + sY)
            elseif sPos == "left" then
                bar._stacksText:SetPoint("LEFT", sb, "LEFT", 5 + sX, sY)
            elseif sPos == "right" then
                bar._stacksText:SetPoint("RIGHT", sb, "RIGHT", -5 + sX, sY)
            else
                bar._stacksText:SetPoint("CENTER", sb, "CENTER", sX, sY)
            end
        end
    end

    -- Border (PP or textured via ApplyBorderStyle; none under Blizzard Style)
    if bar._barBorder then
        bar._barBorder:SetAllPoints(bar)
        local bSz = blizzBar and 0 or (cfg.borderSize or 0)
        local textureKey = cfg.borderTexture or "solid"
        -- Exact size (borderSizePx) for the bar's own step; a stock style forces 0 and stays legacy.
        local edgePx
        if not blizzBar then edgePx = EllesmereUI.BorderPx(cfg.borderSizePx, bSz, textureKey) end
        -- Border container is a child of the bar: +6 draws in front of the fill AND above
        -- the tick marks at sb+4 (=bar+5, which would tie and lose to the lazily-created
        -- tick overlay); "Show Behind" uses level-1. Set BEFORE ApplyBorderStyle so the textured backdrop inherits it.
        local baseLvl = bar:GetFrameLevel()
        bar._barBorder:SetFrameLevel(cfg.borderBehind and math.max(0, baseLvl - 1) or (baseLvl + 6))
        EllesmereUI.ApplyBorderStyle(bar._barBorder, bSz,
            cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, 1,
            textureKey, cfg.borderTextureOffset, cfg.borderTextureOffsetY,
            cfg.borderTextureShiftX, cfg.borderTextureShiftY,
            "resourcebars", bSz, nil, edgePx)
    end

    -- Threshold overlay + tick marks
    SetupTBBThresholdOverlay(bar, cfg)
    if not bar._threshTicks then bar._threshTicks = {} end
    if not bar._tickOverlay then
        local to = CreateFrame("Frame", nil, sb)
        to:SetAllPoints(sb)
        to:SetFrameLevel(sb:GetFrameLevel() + 4)
        bar._tickOverlay = to
    end
    ApplyTBBTickMarks(sb, cfg, bar._threshTicks, isVert, bar._tickOverlay)
    ApplyTBBChargeHashLines(bar, cfg, GetTBBMaxCharges(cfg))
    bar._ticksDirty = true
    -- The settings may change what the name, icon, fill colour and stacks show:
    -- the next live tick re-reads them (TBBContentDue in EUI_CDM_BuffBarTick.lua).
    bar._cChild = nil
end

-- Exposed for the options popout preview: preview bars are built and skinned by the SAME code as live bars, so the preview cannot drift from rendering.
ns.CreateTBBBarFrame  = CreateTrackedBuffBarFrame
ns.ApplyTBBBarSettings = ApplyTrackedBuffBarSettings

-- The width and height a tracking bar's textured border draws OUTSIDE the bar,
-- in bar units, for its unlock element's getMatchPad: exactly the arguments
-- ApplyTrackedBuffBarSettings passes to ApplyBorderStyle (the numeric step as the
-- "resourcebars" size key, alpha 1, no scale normalizing). nil under the stock
-- styles (no EUI border) and for a border that draws nothing outside. `frame` is
-- the bar: its effective scale (a position scale rides on it) is the grid the
-- border's anchors snap to.
function ns.TBBBorderMatchPad(cfg, frame)
    if not cfg or not EllesmereUI.BorderMatchPad or ns.CdmBlizzBars() then return nil end
    local bSz = cfg.borderSize or 0
    local textureKey = cfg.borderTexture or "solid"
    if textureKey == "solid" then return nil end
    local es
    if frame then
        local ok, s = pcall(frame.GetEffectiveScale, frame)
        if ok then es = s end
    end
    return EllesmereUI.BorderMatchPad(bSz, textureKey,
        cfg.borderTextureOffset, cfg.borderTextureOffsetY,
        cfg.borderTextureShiftX, cfg.borderTextureShiftY,
        "resourcebars", bSz, EllesmereUI.BorderPx(cfg.borderSizePx, bSz, textureKey), nil, 1, es)
end

-- "TBB_" .. index and "TBBG_" .. group key, each built once, so the per-build
-- pad notifier builds no strings.
ns._tbbUKey = setmetatable({}, { __index = function(t, k)
    local v = "TBB_" .. k
    t[k] = v
    return v
end })
ns._tbbgUKey = setmetatable({}, { __index = function(t, k)
    local v = "TBBG_" .. k
    t[k] = v
    return v
end })

I.AnchorTBBSpark, I.AnchorTBBSparkState = AnchorTBBSpark, AnchorTBBSparkState
I.ApplyTBBChargeHashLines, I.ApplyTBBTickMarks = ApplyTBBChargeHashLines, ApplyTBBTickMarks
I.ApplyTrackedBuffBarSettings = ApplyTrackedBuffBarSettings
I.CreateTrackedBuffBarFrame = CreateTrackedBuffBarFrame
I.FeedTBBThresholdOverlay = FeedTBBThresholdOverlay
I.StableCooldownSpellID = StableCooldownSpellID
I.broken = false
