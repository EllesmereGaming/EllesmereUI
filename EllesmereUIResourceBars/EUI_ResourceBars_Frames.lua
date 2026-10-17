if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ResourceBars_Frames.lua
--
--  Shared state and the bar helpers: orientation, gradient and flat fills,
--  fill opacity, empower stage colors, pip geometry, pixel borders,
--  CreateStatusBar, CreatePip, the main frame, the spec and power-bar checks.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not I or I.broken then return end
I.broken = true

local PP = EllesmereUI.PP

local CLASS_COLORS, DARK_BG_A, ERB = I.CLASS_COLORS, I.DARK_BG_A, I.ERB
local GetPrimaryPowerType, GetRBFont = I.GetPrimaryPowerType, I.GetRBFont
local GetSecondaryResource, SetRBFont, SnapXY = I.GetSecondaryResource, I.SetRBFont, I.SnapXY
local DEFAULTS, SetMainFrame = I.DEFAULTS, I.SetMainFrame

-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
local mainFrame
I.mainFrameSetters[#I.mainFrameSetters + 1] = function(v) mainFrame = v end
local secondaryBarTicks = {}  -- tick mark texture cache for bar-type secondary
local secondaryPipTicks = {}  -- tick mark texture cache for pip-type secondary hash lines
local _totemBorderOverlays = setmetatable({}, { __mode = "k" })
-- Engine-entry frames are created at FILE SCOPE on purpose: CPU bills a handler's
-- whole call tree to the addon whose execution context CREATED the entry frame
-- (inherited taint-style from the entry point, not the file the code lives in).
-- OnEnable/build code run under the parent's lifecycle dispatch, so a frame born
-- there bills the parent forever; born in this main chunk it stamps to
-- ResourceBars. Handlers/event registrations can attach later anywhere.
local _erbEventFrame = CreateFrame("Frame")   -- event entry; events registered in OnEnable

-- Shell pool for runtime handler hosts (the combat queue below, and up to three
-- mouse-follow anchors): born HERE so their work bills ResourceBars (attribution
-- rule above). One spare.
do
    local pool = { CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame"), CreateFrame("Frame") }
    local n = 5
    ns.TakeShell = function()
        if n > 0 then
            local f = pool[n]
            pool[n] = nil
            n = n - 1
            return f
        end
        return CreateFrame("Frame")
    end
end
ns.CombatQueue = EllesmereUI.NewCombatQueue(ns.TakeShell())
local isInCombat = false
I.isInCombatSetters[#I.isInCombatSetters + 1] = function(v) isInCombat = v end
local currentAlpha = 1
local targetAlpha = 1

-- GCD bar shell at file scope, same attribution reason as _erbEventFrame:
-- BuildGCDBar adopts this shell rather than creating its own, so its OnEvent work
-- bills ResourceBars. Child textures/sub-frames stay lazy (no handlers, birth
-- context doesn't matter).
ns.GCDShell = CreateFrame("Frame", "ERB_GCDBarFrame", UIParent)

-- Effective bar alpha: oocAlpha when "Fade Out of Combat" is on and out of combat, else
-- normal opacity (off by default). EVERY SetAlpha site routes through this -- some
-- events (UNIT_MAXHEALTH/UNIT_MAXPOWER) rebuild with no following UpdateVisibility, so
-- folding the fade in here keeps a rebuild from clobbering it. On ns.
function ns.ResolveBarAlpha(cfg)
    if cfg and cfg.oocFadeEnabled and not isInCombat then
        return cfg.oocAlpha or 0.5
    end
    return (cfg and cfg.barAlpha) or 1
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function GetAccent()
    local eg = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    if eg then return eg.r, eg.g, eg.b end
    return 12/255, 210/255, 157/255
end

local function IsVerticalOrientation(ori)
    return ori == "VERTICAL_UP" or ori == "VERTICAL_DOWN"
end
-- Shared with the options file, which needs a bar's drawn axes to grey the right
-- size slider when a dimension is matched. Exported, not duplicated, to avoid drift.
ns.IsVerticalOrientation = IsVerticalOrientation

-- Orientation-aware MatchGuard. Size sliders are labelled/stored in HORIZONTAL terms,
-- but a match locks the axis the bar is DRAWN on (swapped on a vertical bar); guarding
-- by the slider's own label would grey the wrong field and leave the written one
-- editable, silently dropping the player's change. Both guards are built and picked
-- when the widget asks (not at page build), so flipping orientation with the panel open
-- is honoured. getOri returns the bar's effective orientation.
ns.OrientedMatchGuard = function(barKey, propKey, getOri, existingDisabled, existingTooltip)
    local hD, hT, hR = EllesmereUI.MatchGuard(barKey, "Height", existingDisabled, existingTooltip)
    local wD, wT, wR = EllesmereUI.MatchGuard(barKey, "Width",  existingDisabled, existingTooltip)
    local function pick(sameAxis, swappedAxis)
        return function(...)
            if IsVerticalOrientation(getOri and getOri()) then return swappedAxis(...) end
            return sameAxis(...)
        end
    end
    if propKey == "Height" then
        return pick(hD, wD), pick(hT, wT), pick(hR, wR)
    end
    return pick(wD, hD), pick(wT, hT), pick(wR, hR)
end

-- Cached empower stage thresholds (set once at empower start, avoids per-frame API call)
local cachedStageThresholds
I.stageThresholdsSetters[#I.stageThresholdsSetters + 1] = function(v) cachedStageThresholds = v end
-- Reusable CreateColor objects for gradient (avoids per-frame allocation)
local empowerColorA = CreateColor(1, 0, 0, 1)
local empowerColorB = CreateColor(1, 0, 0, 1)

-- Bar gradients use two REUSED color objects so applying one allocates nothing
-- (CreateColor would allocate two tables/call). Re-issued on every color update
-- (cheap, same order as flat bars' SetVertexColor) and never skipped or cached,
-- so it can never go stale.
local _gradColorA = CreateColor(1, 1, 1, 1)
local _gradColorB = CreateColor(1, 1, 1, 1)

local function ApplyBarGradient(ft, dir, br, bg, bb, ba, er, eg, eb, ea)
    -- Bar colour only changes on a config edit or threshold/band crossing, but this
    -- runs on every power/health event, so skip when inputs (plus the fill-opacity
    -- multiplier scaling the alphas below) are unchanged -- else four C calls
    -- repaint an identical gradient a dozen times a second. State lives on our own
    -- texture (already carries _erbSetVC/_erbFillOp).
    if ft._lgOn and ft._lgDir == dir and ft._lgFop == ft._erbFillOp
       and ft._lgBr == br and ft._lgBg == bg and ft._lgBb == bb and ft._lgBa == ba
       and ft._lgEr == er and ft._lgEg == eg and ft._lgEb == eb and ft._lgEa == ea then
        return
    end
    ft._lgOn, ft._lgDir, ft._lgFop = true, dir, ft._erbFillOp
    ft._lgBr, ft._lgBg, ft._lgBb, ft._lgBa = br, bg, bb, ba
    ft._lgEr, ft._lgEg, ft._lgEb, ft._lgEa = er, eg, eb, ea
    ft._lfOn = nil   -- a gradient invalidates any cached flat colour

    -- Bypass the Fill Opacity SetVertexColor wrapper (if installed): gradient
    -- opacity is carried in the endpoint alphas below, and its re-assert would
    -- fight the corner alphas.
    local rawVC = ft._erbSetVC or ft.SetVertexColor
    rawVC(ft, 1, 1, 1, 1)
    local _fop = ft._erbFillOp
    if _fop then ba = (ba or 1) * _fop; ea = (ea or 1) * _fop end
    _gradColorA:SetRGBA(br, bg, bb, ba)
    _gradColorB:SetRGBA(er, eg, eb, ea)
    ft:SetGradient(dir, _gradColorA, _gradColorB)
end

-- Flat-color a bar fill (no gradient).
local function ApplyBarFlat(ft, r, g, b, a)
    -- As ApplyBarGradient: re-asserting an unchanged colour every event is waste.
    a = a or 1
    if ft._lfOn and ft._lfR == r and ft._lfG == g and ft._lfB == b and ft._lfA == a then
        return
    end
    ft._lfOn, ft._lfR, ft._lfG, ft._lfB, ft._lfA = true, r, g, b, a
    ft._lgOn = nil   -- a flat fill invalidates any cached gradient
    ft:SetVertexColor(r, g, b, a)
end
-- Shared with EUI_ResourceBars_SwingTimer.lua, which paints its rows the way the
-- GCD bar paints its fill. Exported, not duplicated, so the change-gates stay one.
ns.ApplyBarGradient = ApplyBarGradient
ns.ApplyBarFlat = ApplyBarFlat
ns.SnapXY = SnapXY
ns.CLASS_COLORS = CLASS_COLORS

-- Fill Opacity (continuous bars). Below 100 the fill turns translucent via texture
-- REGION alpha (survives every runtime SetVertexColor/SetGradient writer) and the
-- bg re-anchors to cover ONLY the empty portion, so the world shows through the
-- fill instead of the background. Fully inert at 100 (untouched unless previously
-- applied, _fillOpApplied). Value-blind by design (region alpha + relational
-- anchors only), so it renders identically when values are secret. On ns.
-- AnchorBgToFillEdge: empty side depends on fill direction --
-- VERTICAL_UP bottom-up (empty top), VERTICAL_DOWN top-down (empty bottom),
-- horizontal left-to-right (empty right); anchor is relational to the fill
-- texture's moving edge, so it tracks value changes with no per-frame work.
ns.AnchorBgToFillEdge = function(bg, tex, container, orientation)
    bg:ClearAllPoints()
    if orientation == "VERTICAL_UP" then
        bg:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", tex, "TOPRIGHT", 0, 0)
    elseif orientation == "VERTICAL_DOWN" or orientation == "VERTICAL" then
        bg:SetPoint("TOPLEFT", tex, "BOTTOMLEFT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    else
        bg:SetPoint("TOPLEFT", tex, "TOPRIGHT", 0, 0)
        bg:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    end
end

ns.ApplyFillOpacity = function(bar, orientation, fillOpacity)
    local op = fillOpacity or 100
    local sb, bg = bar._sb, bar._bg
    if not sb or not bg then return end
    if op >= 100 then
        if bar._fillOpApplied then
            bar._fillOpApplied = nil
            local tex = sb:GetStatusBarTexture()
            if tex then
                tex._erbFillOp = nil
                -- Uninstall the wrapper: clearing the shadow key restores the metatable method.
                if tex._erbVCWrapped then
                    tex.SetVertexColor = nil
                    tex._erbVCWrapped = nil
                    tex._erbSetVC = nil
                end
                tex:SetAlpha(1)
            end
            bg:ClearAllPoints()
            bg:SetAllPoints(sb)
        end
        return
    end
    local tex = sb:GetStatusBarTexture()
    if not tex then return end
    bar._fillOpApplied = true
    -- Alpha is UNIFIED on this client: SetAlpha and SetVertexColor's 4th arg write
    -- the same slot, so any runtime color writer (threshold curves, band colors,
    -- power-type recolors) would wipe a build-time alpha. Shadow SetVertexColor on
    -- this one fill texture with a wrapper that passes args through UNTOUCHED (no
    -- arithmetic, so secret color components flow safely) then re-asserts opacity.
    -- Installed only while below 100; gradient writers bypass it, carrying opacity
    -- in their endpoint alphas.
    tex._erbFillOp = op / 100
    if not tex._erbVCWrapped then
        tex._erbVCWrapped = true
        tex._erbSetVC = tex.SetVertexColor
        tex.SetVertexColor = function(t, ...)
            t._erbSetVC(t, ...)
            local o = t._erbFillOp
            if o then t:SetAlpha(o) end
        end
    end
    tex:SetAlpha(op / 100)
    ns.AnchorBgToFillEdge(bg, tex, sb, orientation)
end

-- Restore a pip/rune to full opacity after Fill Opacity was on. Only called on the
-- 100-or-above build pass while _fillOp is still set, so untouched profiles skip it.
ns.ClearPipFillOpacity = function(pip)
    pip._fillOp = nil
    pip._fill:SetAlpha(1)
    pip._bg:SetAlpha(1)
    local function reset(sb)
        if sb then
            local t = sb:GetStatusBarTexture()
            if t then t:SetAlpha(1) end
        end
    end
    reset(pip._secretBar); reset(pip._secretThreshBar); reset(pip._bandResetBar)
    if pip._bandBars then
        for k = 1, #pip._bandBars do reset(pip._bandBars[k]) end
    end
    if pip._sbgAnchored then
        pip._sbgAnchored = nil
        pip._bg:ClearAllPoints()
        pip._bg:SetAllPoints(pip)
    end
end

-- Returns the current empowered stage (0-based) based on progress and cached thresholds
local function GetCurrentEmpowerStage(progress, numStages)
    if not numStages or numStages <= 0 then return 0 end
    local thresholds = cachedStageThresholds
    if not thresholds then return 0 end

    for i = 1, #thresholds do
        if progress < thresholds[i] then
            return i - 1
        end
    end
    return #thresholds
end

-- Returns RGB color for the current empower stage (red -> yellow -> green gradient)
local function GetEmpowerStageColor(stage, maxStages)
    if maxStages <= 1 then
        return 0, 1, 0
    end

    local t = stage / maxStages

    if t < 0.5 then
        return 1, t * 2, 0
    else
        return 1 - (t - 0.5) * 2, 1, 0
    end
end

local function OrientedSize(w, h, orientation)
    if IsVerticalOrientation(orientation) then
        return h, w  -- swap width and height for vertical bars
    end
    return w, h
end

local function ApplyBarOrientation(bar, orientation)
    if not bar then return end
    if orientation == "VERTICAL_UP" then
        bar:SetOrientation("VERTICAL")
        bar:SetRotatesTexture(true)
        bar:SetReverseFill(false)
    elseif orientation == "VERTICAL_DOWN" then
        bar:SetOrientation("VERTICAL")
        bar:SetRotatesTexture(true)
        bar:SetReverseFill(true)
    else
        bar:SetOrientation("HORIZONTAL")
        bar:SetRotatesTexture(false)
        bar:SetReverseFill(false)
    end
end

-- Bar texture helper
local function ApplyBarTexture(bar, texKey)
    if not bar then return end
    local path = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
    bar:SetStatusBarTexture(path)
    -- Blizzard Style: a path swap can mint a new fill object; re-seat the
    -- bar-shape mask on it (memoized per object, so a no-op otherwise).
    if bar._blizzBarMask then ns.ERB_SeatBlizzMask(bar) end
end

-- Textured Background: the bar's own texture on a background, tinted by the
-- background colour. Callers repaint the flat colour around it; nil path clears
-- the tint a texture left behind (SetColorTexture keeps it).
function ns.ERB_BgTexture(bg, path, r, g, b, a)
    if path then
        bg:SetTexture(path)
        bg:SetVertexColor(r, g, b, a)
        bg._erbBgTex = true
    elseif bg._erbBgTex then
        bg._erbBgTex = nil
        bg:SetVertexColor(1, 1, 1, 1)
    end
end


-- Compute pixel-snapped pip geometry for a given frame's effective scale.
-- Returns a table of {x0, x1} pairs (in logical units, snapped to physical
-- pixels) for each pip index 1..numPips. Spacing between every adjacent pair
-- is guaranteed to be exactly pipSp physical pixels at any UI scale.
local function CalcPipGeometry(totalW, numPips, pipSp, frame, esOverride)
    -- esOverride: the same effective scale the caller used to snap the frame's
    -- outer dimensions (falls back to the live es). Removes a 1-px mismatch when
    -- the effective scale changes between the outer SetSize and this layout pass
    -- (reparent, scale chain update); the caller owns the source of truth.
    local es = esOverride or frame:GetEffectiveScale()
    if es <= 0 then es = 1 end
    -- 1 physical pixel in this frame's coordinate space
    local onePixel = PP.perfect / es

    -- Zero pips happens transiently while zoning (max class-resource count reads 0
    -- mid-load) and the pip division would hard-error: return empty geometry.
    if not numPips or numPips < 1 then
        return {}, 0, onePixel, 0
    end

    -- Snap spacing to nearest whole physical pixel (minimum 1px)
    local spPx = math.max(1, math.floor(pipSp / onePixel + 0.5))

    -- Total physical pixels for the whole bar
    local totalPx = math.floor(totalW / onePixel + 0.5)
    local gapPx   = spPx * (numPips - 1)
    local pipPx   = totalPx - gapPx
    local basePx  = math.floor(pipPx / numPips)
    local extraPx = pipPx - basePx * numPips -- first extraPx pips get +1px

    -- Build per-pip positions in physical pixels, convert to logical units once.
    local slots = {}
    local cursor = 0
    for i = 1, numPips do
        local w = basePx + (i <= extraPx and 1 or 0)
        local x1 = (cursor + w) * onePixel
        -- Clamp last pip's right edge to totalW so it never exceeds the container
        if i == numPips and x1 > totalW then x1 = totalW end
        slots[i] = { x0 = cursor * onePixel, x1 = x1 }
        cursor = cursor + w + spPx
    end

    return slots, spPx * onePixel, onePixel, totalPx * onePixel
end

-- Extend Top / Extend Bottom (Border Options cog on the power, class resource,
-- cast and GCD bars): how far a bar's border host reaches past the bar's top
-- and bottom edges on screen, in UI units (screen axes, a vertical bar too).
-- Read only while the bar's style is textured, the only state that shows the
-- rows, so the stored values stay inert after a switch to Solid. Kept out of
-- ns.ERB_EuiBorderPad: size matching ignores it (the extension is meant to
-- overlap a neighbour). Callers pass nil under a stock style.
function ns.ERB_BorderExtents(c)
    if not c then return 0, 0 end
    local tex = c.borderTexture
    if not tex or tex == "" or tex == "solid" then return 0, 0 end
    return c.borderExtendTop or 0, c.borderExtendBottom or 0
end

-- Seats a border host frame we created (bf) on its bar (parent). An extent
-- above 0 anchors TOPLEFT up by top and BOTTOMRIGHT down by bottom, each on
-- whole physical pixels at the host's scale (the textured backdrop snaps its
-- own anchors to the same grid); the stamp on bf makes a repeat pass with a
-- live rect a no-op. Both 0 (callers that pass none: pips, health, the stock
-- styles): an extended host goes back to SetAllPoints once, and any host whose
-- rect stopped resolving is re-seated the same way -- a bar repositioned by the
-- unlock anchor system loses this frame's SetAllPoints edge (GetLeft() nil,
-- GetWidth() 0) and the border vanishes until re-issued. Build paths only.
function ns.ERB_AnchorBorderHost(bf, parent, top, bottom)
    top, bottom = top or 0, bottom or 0
    if top > 0 or bottom > 0 then
        local es = bf:GetEffectiveScale()
        top, bottom = PP.SnapForES(top, es), PP.SnapForES(bottom, es)
        if bf._erbExtT == top and bf._erbExtB == bottom and bf:GetLeft() then return end
        bf:ClearAllPoints()
        bf:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, top)
        bf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, -bottom)
        bf._erbExtT, bf._erbExtB = top, bottom
    elseif bf._erbExtT or not bf:GetLeft() then
        bf._erbExtT, bf._erbExtB = nil, nil
        bf:SetAllPoints(parent)
    end
end

local function MakePixelBorder(parent, r, g, b, a, size, textureKey, texOffset, texOffsetY, shiftX, shiftY)
    local alpha = a or 1
    local sz = size or 1
    local bf = CreateFrame("Frame", nil, parent)
    bf:SetAllPoints(parent)
    bf:SetFrameLevel(parent:GetFrameLevel() + 1)

    EllesmereUI.ApplyBorderStyle(bf, sz, r, g, b, alpha, textureKey or "solid", texOffset, texOffsetY, shiftX, shiftY)

    return {
        _frame = bf,
        edges = PP.GetBorders(bf),
        SetColor = function(self, cr, cg, cb, ca)
            EllesmereUI.SetBorderStyleColor(bf, cr, cg, cb, ca or 1)
        end,
        SetSize = function(self, newSz)
            PP.SetBorderSize(bf, newSz)
        end,
        SetShown = function(self, shown)
            if shown then PP.ShowBorder(bf) else PP.HideBorder(bf) end
        end,
        -- edgePx: the bar's exact border size (EllesmereUI.BorderPx), nil for the legacy path.
        -- extTop / extBottom: Extend Top / Extend Bottom (ns.ERB_BorderExtents), full-bar
        -- borders only; pips never pass them.
        ApplyStyle = function(self, newSz, cr, cg, cb, ca, texKey, texOff, texOffY, sX, sY, addonKey, sizeKey, edgePx, extTop, extBottom)
            -- A bar repositioned by the unlock anchor system loses this frame's
            -- SetAllPoints edge: GetPoint still reports TOPLEFT/BOTTOMRIGHT to the bar,
            -- but the rect stops resolving (GetLeft() nil, GetWidth() 0). The strips are
            -- anchored here, so each one falls back to WHITE8X8's natural 8px on the
            -- dimension it takes from anchors and the border disappears until the border
            -- SIZE changes. Re-seating the host restores it (with the extents, if any).
            ns.ERB_AnchorBorderHost(bf, parent, extTop, extBottom)
            EllesmereUI.ApplyBorderStyle(bf, newSz, cr, cg, cb, ca or 1, texKey or "solid", texOff, texOffY, sX, sY, addonKey, sizeKey, nil, edgePx)
        end,
    }
end

-- Bar creation helpers
local function CreateStatusBar(parent, name, w, h, borderSize, borderR, borderG, borderB, borderA)
    -- Outer container: holds the border and text (never clipped).
    local bar = CreateFrame("Frame", name, parent)
    bar:SetSize(w, h)
    bar:EnableMouse(false)

    -- Inner StatusBar: clips its fill. Inset by a quarter of a physical pixel so
    -- the fill can never bleed past the border at any resolution. A quarter, not
    -- a half: an edge on a pixel centre hits the rasteriser's tie rule and the
    -- fill covers one more pixel on one side than the other.
    local sb = CreateFrame("StatusBar", nil, bar)
    local clipInset = PP.mult * 0.25
    sb:SetPoint("TOPLEFT", bar, "TOPLEFT", clipInset, -clipInset)
    sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -clipInset, clipInset)
    sb:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    sb:SetClipsChildren(true)
    bar._sb = sb

    -- Forward StatusBar methods to the inner bar so callers don't change
    bar.SetMinMaxValues = function(_, ...) sb:SetMinMaxValues(...) end
    bar.SetValue = function(_, v)
        -- Native interpolation (opt-in "Smooth Bars"): _smoothing is set only on
        -- bars whose toggle is on; nil elsewhere, so every write lands at once.
        -- The toggle alone decides: callers pass the value only.
        if bar._smoothing then
            sb:SetValue(v, bar._smoothing)
        else
            sb:SetValue(v)
        end
    end
    bar.GetValue = function(_) return sb:GetValue() end
    bar.SetStatusBarTexture = function(_, ...) sb:SetStatusBarTexture(...) end
    bar.GetStatusBarTexture = function(_) return sb:GetStatusBarTexture() end
    bar.SetStatusBarColor = function(_, ...) sb:SetStatusBarColor(...) end
    bar.GetStatusBarColor = function(_) return sb:GetStatusBarColor() end
    bar.SetFillStyle = function(_, ...) sb:SetFillStyle(...) end
    bar.SetOrientation = function(_, ...) sb:SetOrientation(...) end
    bar.SetRotatesTexture = function(_, ...) sb:SetRotatesTexture(...) end
    bar.SetReverseFill = function(_, ...) sb:SetReverseFill(...) end

    -- Background (inside the clipped area)
    local bg = sb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0x11/255, 0x11/255, 0x11/255, 0.75)
    bar._bg = bg

    -- Pixel-perfect border (on outer container, not clipped)
    local bSz = borderSize or 1
    bar._border = MakePixelBorder(bar, borderR or 0, borderG or 0, borderB or 0, borderA or 1, bSz)

    -- extTop / extBottom: Extend Top / Extend Bottom (power bar only; nil elsewhere).
    function bar:ApplyBorder(sz, r, g, b, a, textureKey, texOffset, texOffsetY, shiftX, shiftY, addonKey, sizeKey, behind, edgePx, extTop, extBottom)
        -- "Show Behind": set the border frame level before styling so the textured
        -- backdrop inherits it. +1 draws in front of the fill, level-1 behind it.
        if self._border._frame then
            local pl = self:GetFrameLevel()
            self._border._frame:SetFrameLevel(behind and math.max(0, pl - 1) or (pl + 1))
        end
        self._border:ApplyStyle(sz, r, g, b, a, textureKey, texOffset, texOffsetY, shiftX, shiftY, addonKey, sizeKey, edgePx, extTop, extBottom)
    end

    -- Lift the border above an overlay that draws inside the bar's rect. The
    -- default level (+1 over the bar, strips +1 over that) only clears the
    -- legacy fill; the 12.1 Ebon Might engine slot renders its own StatusBar
    -- deeper in the tree, so it paints over the strips and Border Size/Color
    -- look like they do nothing. "Show Behind" is honored -- that border is
    -- meant to sit under the fill. Idempotent: safe to re-assert every update.
    function bar:RaiseBorderAbove(coverLevel, behind)
        local bf = self._border and self._border._frame
        if not bf then return end
        local lvl = behind and math.max(0, self:GetFrameLevel() - 1) or (coverLevel + 1)
        bf:SetFrameLevel(lvl)
        -- Re-assert on the PP strip container too: it was levelled off the
        -- border frame at creation, and the textured-border backdrop tracks
        -- the border frame's level directly.
        local edges = PP and PP.GetBorders and PP.GetBorders(bf)
        if edges then edges:SetFrameLevel(lvl + 1) end
        -- A Bottom Separator on this bar (ns.ERB_Separators) stays above it.
        local sep = self._erbSep
        if sep and sep:IsShown() and sep:GetFrameLevel() < lvl + 2 then sep:SetFrameLevel(lvl + 2) end
    end

    -- Text overlay (above all bar borders)
    local textFrame = CreateFrame("Frame", nil, bar)
    textFrame:SetAllPoints(bar)
    textFrame:SetFrameLevel(25)
    textFrame:EnableMouse(false)
    local text = textFrame:CreateFontString(nil, "OVERLAY")
    SetRBFont(text, GetRBFont(), 11)
    text:SetTextColor(1, 1, 1, 0.9)
    text:SetPoint("CENTER", textFrame, "CENTER")
    bar._text = text

    return bar
end

-- Create a single pip (for combo points, holy power, etc.)
local function CreatePip(parent, w, h, idx, borderSize, borderR, borderG, borderB, borderA)
    local pip = CreateFrame("Frame", nil, parent)
    pip:SetSize(w, h)

    local bg = pip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
    pip._bg = bg

    local fill = pip:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    fill:SetColorTexture(1, 1, 1, 1)
    pip._fill = fill
    pip._texKey = nil  -- current bar texture key

    -- Pixel-perfect border with variable size
    local bSz = borderSize or 1
    pip._border = MakePixelBorder(pip, borderR or 0, borderG or 0, borderB or 0, borderA or 1, bSz)

    function pip:ApplyBorder(sz, r, g, b, a, textureKey, texOffset, texOffsetY, shiftX, shiftY, addonKey, sizeKey, edgePx)
        self._border:ApplyStyle(sz, r, g, b, a, textureKey, texOffset, texOffsetY, shiftX, shiftY, addonKey, sizeKey, edgePx)
    end

    function pip:ApplyTexture(texKey)
        self._texKey = texKey
        local path = EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
        self._fill:SetTexture(path)
        if self._rechargeBar then
            self._rechargeBar:SetStatusBarTexture(path)
        end
        -- Blizzard Style: a path swap mints a new recharge fill; re-seat the mask.
        if self._blizzMask then ns.ERB_MaskPip(self, self._blizzMask) end
    end

    pip._active = false
    pip._idx = idx

    function pip:SetActive(active, r, g, b, a)
        self._active = active
        if active then
            self._fill:SetVertexColor(r, g, b, a or 1)
            -- Fill Opacity on: re-assert fill alpha (unified channel, wiped by the
            -- SetVertexColor above) and hide bg so the translucent fill shows the
            -- world. _fillOp is nil unless below 100 (inert default). At
            -- factor 1 (Background on individual pips) the colour alpha
            -- written above already is the fill alpha, so it is kept.
            if self._fillOp then
                if self._fillOp < 1 then self._fill:SetAlpha(self._fillOp) end
                self._bg:SetAlpha(0)
            end
            self._fill:Show()
        else
            self._fill:Hide()
            if self._fillOp then self._bg:SetAlpha(1) end
        end
    end

    return pip
end

-- Optional gap-fill layer ("Bar Spacing" color). Opt-in: disabled draws nothing,
-- gaps keep showing the full-bar background; enabled places one texture per
-- inter-pip gap so spacing colors independently of the bar background. Only
-- READS the already-computed pip slot positions, never changes pip sizing or
-- spacing geometry. On ERB.

-- Per-pip empty-slot backdrop color. At Fill Opacity 100 it's just the Empty Bar
-- Overlay tint (bgR/G/B/A, dark theme override). Below 100 the full-bar backdrop
-- is hidden (can't hole itself behind active pips, would tint translucent fills),
-- so the overlay texture -- already covering exactly the empty regions via
-- SetActive/the secret fill-edge anchor -- takes over: composite the bar
-- background UNDER the overlay tint so empty slots keep the same stacked look.
-- force: Background on individual pips (ns.ERB_PipBgOn), which hides the
-- full-bar backdrop at every Fill Opacity, so the composite applies at 100 too.
function ERB.PipBgColor(sp, force)
    local ovR, ovG, ovB, ovA = sp.bgR, sp.bgG, sp.bgB, sp.bgA
    if sp.darkTheme then
        local dr, dg, db = EllesmereUI.GetDarkModeBg()
        ovR, ovG, ovB, ovA = dr, dg, db, DARK_BG_A
    end
    ovR, ovG, ovB, ovA = ovR or 0, ovG or 0, ovB or 0, ovA or 0
    if not force and (sp.fillOpacity or 100) >= 100 then
        return ovR, ovG, ovB, ovA
    end
    local bbR, bbG, bbB, bbA
    if sp.darkTheme then
        bbR, bbG, bbB, bbA = 0, 0, 0, 1
    else
        bbR, bbG, bbB, bbA = sp.barBgR or 0, sp.barBgG or 0, sp.barBgB or 0, sp.barBgA or 0.5
    end
    -- Standard alpha compositing: overlay OVER bar background
    local a = ovA + bbA * (1 - ovA)
    if a <= 0 then return bbR, bbG, bbB, 0 end
    local r = (ovR * ovA + bbR * bbA * (1 - ovA)) / a
    local g = (ovG * ovA + bbG * bbA * (1 - ovA)) / a
    local b = (ovB * ovA + bbB * bbA * (1 - ovA)) / a
    return r, g, b, a
end

function ERB.ApplyGapFills(frame, slots, count, isVertical, isReversed, sp, pipBg)
    local fills = frame._gapFills
    -- Pip/rune Fill Opacity hides the full-bar backdrop (would tint translucent
    -- fills from behind), so the gap strips take over in bar-bg color even with
    -- "Bar Spacing" color disabled. Background on individual pips (pipBg) keeps
    -- the gaps clear instead: only the "Bar Spacing" color paints them then.
    local fillOpActive = not pipBg and (sp.fillOpacity or 100) < 100
    if not ((sp.gapColorEnabled or fillOpActive) and slots and count and count > 1) then
        if fills then for i = 1, #fills do fills[i]:Hide() end end
        return
    end
    if not fills then fills = {}; frame._gapFills = fills end
    local r, g, b, a
    if sp.gapColorEnabled then
        r, g, b, a = sp.gapR or 0, sp.gapG or 0, sp.gapB or 0, sp.gapA or 1
    elseif sp.darkTheme then
        r, g, b, a = 0, 0, 0, 1
    else
        r, g, b, a = sp.barBgR or 0, sp.barBgG or 0, sp.barBgB or 0, sp.barBgA or 0.5
    end
    local n = 0
    for i = 1, count - 1 do
        local x1 = slots[i].x1          -- trailing edge of pip i
        local x0 = slots[i + 1].x0      -- leading edge of pip i+1
        local gapLen = x0 - x1
        if gapLen and gapLen > 0 then
            n = n + 1
            local tex = fills[n]
            if not tex then
                tex = frame:CreateTexture(nil, "BACKGROUND", nil, 0)  -- above _barBg (sublevel -1)
                fills[n] = tex
            end
            tex:SetColorTexture(r, g, b, a)
            tex:ClearAllPoints()
            if isVertical then
                if isReversed then
                    tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, x1)
                    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, x1)
                else
                    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -x1)
                    tex:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -x1)
                end
                tex:SetHeight(gapLen)
            else
                tex:SetPoint("TOPLEFT", frame, "TOPLEFT", x1, 0)
                tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x1, 0)
                tex:SetWidth(gapLen)
            end
            tex:Show()
        end
    end
    for i = n + 1, #fills do fills[i]:Hide() end
end


-------------------------------------------------------------------------------
--  Main frame construction
-------------------------------------------------------------------------------
local pips = {}
local runeFrames = {}

-------------------------------------------------------------------------------
--  Smooth animation helper for actual bar scale / offset changes
-------------------------------------------------------------------------------
local _barAnimTimers = {}
local BAR_ANIM_DURATION = 0.18

local function SmoothBarAnimate(frame, key, targetVal, applyFn)
    if not frame then return end
    if not _barAnimTimers[frame] then _barAnimTimers[frame] = {} end
    if _barAnimTimers[frame][key] then
        _barAnimTimers[frame][key]:Cancel()
        _barAnimTimers[frame][key] = nil
    end
    local startVal = frame["_barAnim_" .. key] or targetVal
    if math.abs(startVal - targetVal) < 0.001 then
        frame["_barAnim_" .. key] = targetVal
        applyFn(targetVal)
        return
    end
    local elapsed = 0
    local ticker
    ticker = C_Timer.NewTicker(0.016, function()
        elapsed = elapsed + 0.016
        local t = math.min(elapsed / BAR_ANIM_DURATION, 1)
        t = 1 - (1 - t) * (1 - t)  -- ease-out quad
        local v = startVal + (targetVal - startVal) * t
        frame["_barAnim_" .. key] = v
        applyFn(v)
        if t >= 1 then
            frame["_barAnim_" .. key] = targetVal
            ticker:Cancel()
            if _barAnimTimers[frame] then _barAnimTimers[frame][key] = nil end
        end
    end)
    _barAnimTimers[frame][key] = ticker
end

local function BuildMainFrame()
    if mainFrame then return mainFrame end

    local g = ERB.db.profile.general or DEFAULTS.profile.general

    SetMainFrame(CreateFrame("Frame", "EllesmereUIResourceBarsFrame", UIParent))
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", g.anchorX or 0, g.anchorY or -100)
    mainFrame:SetSize(1, 1)  -- invisible anchor point
    mainFrame:SetFrameStrata(g.frameStrata or "MEDIUM")
    mainFrame:SetFrameLevel(5)

    return mainFrame
end


-- Per-spec bar enable check. Per-spec enables live in Spec Overrides (they flip
-- cfg.enabled per spec), so the disabledSpecs filter is permanently inert. Kept
-- as a function so call sites stand.
local function IsSpecDisabled()
    return false
end

-- Is the power bar effectively hidden right now? True when it leaves no visible slot:
-- globally disabled, filtered for the spec, spec has no primary power, hidden per druid
-- form, or hidden by "Hide Power Bar if Resource". Mirrors what ResolveShiftDirPower
-- reacts to plus the dynamic hidePowerIfResource/per-form toggles. Gates features shown
-- only in the power bar's absence (e.g. class resource "Resource Text").
local function IsPowerBarHidden()
    local p = ERB and ERB.db and ERB.db.profile
    if not p then return false end
    local pp = p.primary
    if not pp then return true end
    if pp.enabled == false then return true end
    if IsSpecDisabled(pp) then return true end
    if _G._ERB_BarHiddenByForm(pp) then return true end  -- druid per-form bar disable
    if not GetPrimaryPowerType() then return true end
    if p.secondary and p.secondary.hidePowerIfResource and p.secondary.enabled ~= false and GetSecondaryResource() then return true end
    return false
end

I._erbEventFrame, I._totemBorderOverlays = _erbEventFrame, _totemBorderOverlays
I.ApplyBarFlat, I.ApplyBarGradient = ApplyBarFlat, ApplyBarGradient
I.ApplyBarOrientation, I.ApplyBarTexture = ApplyBarOrientation, ApplyBarTexture
I.BuildMainFrame, I.CalcPipGeometry, I.CreatePip = BuildMainFrame, CalcPipGeometry, CreatePip
I.CreateStatusBar, I.empowerColorA = CreateStatusBar, empowerColorA
I.empowerColorB, I.GetCurrentEmpowerStage = empowerColorB, GetCurrentEmpowerStage
I.GetEmpowerStageColor, I.IsPowerBarHidden = GetEmpowerStageColor, IsPowerBarHidden
I.IsSpecDisabled, I.IsVerticalOrientation = IsSpecDisabled, IsVerticalOrientation
I.MakePixelBorder, I.OrientedSize, I.pips = MakePixelBorder, OrientedSize, pips
I.runeFrames, I.secondaryBarTicks = runeFrames, secondaryBarTicks
I.secondaryPipTicks, I.SmoothBarAnimate = secondaryPipTicks, SmoothBarAnimate
I.broken = false
