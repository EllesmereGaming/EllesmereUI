-------------------------------------------------------------------------------
--  EllesmereUI_Glows.lua
--  Shared glow rendering engine for the EllesmereUI addon suite.
--  Provides: Pixel Glow (procedural ants), Action Button Glow, Auto-Cast
--  Shine, Shape Glow, and FlipBook-based glows (GCD, Modern WoW, Classic WoW).
--  Each addon attaches to EllesmereUI.Glows.* instead of duplicating engines.
-------------------------------------------------------------------------------
if not EllesmereUI then return end
if EllesmereUI.Glows then return end  -- already loaded by another addon

local floor = math.floor
local min   = math.min
local ceil  = math.ceil
local sin   = math.sin

-------------------------------------------------------------------------------
--  Style Definitions (superset of all addons)
--  Each addon picks from this table by index or iterates for its dropdown.
--  Fields: name, procedural, buttonGlow, autocast, shapeGlow, atlas, texture,
--          rows, columns, frames, duration, frameW, frameH, scale, previewScale
-------------------------------------------------------------------------------
local GLOW_STYLES = {
    { name = "Pixel Glow",         procedural = true },
    { name = "Action Button Glow", buttonGlow = true },
    { name = "Auto-Cast Shine",    autocast   = true },
    { name = "Shape Glow",         shapeGlow  = true },
    { name = "GCD",
      atlas = "RotationHelper_Ants_Flipbook", texPadding = 1.6 },
    { name = "Modern WoW Glow",
      atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook", texPadding = 1.4 },
    { name = "Classic WoW Glow",
      texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows = 5, columns = 5, frames = 25, duration = 0.3,
      frameW = 48, frameH = 48, texPadding = 1.25 },
}

-------------------------------------------------------------------------------
--  Texture constants
-------------------------------------------------------------------------------
local ANTS_TEX      = [[Interface\SpellActivationOverlay\IconAlertAnts]]
local ICON_ALERT_TEX = [[Interface\SpellActivationOverlay\IconAlert]]
local BG_GLOW_L, BG_GLOW_R = 0.00781250, 0.50781250
local BG_GLOW_T, BG_GLOW_B = 0.27734375, 0.52734375
local SHINE_TEX    = [[Interface\Artifacts\Artifacts]]
local SHINE_COORDS = { 0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625 }
local SPARKLE_LAYER_SIZES = { 7, 6, 5, 4 }

-------------------------------------------------------------------------------
--  Central Glow Driver
--  One OnUpdate (on a frame we own) animates every active glow. Each animated
--  engine registers its wrapper tagged by kind; this driver gates the WHOLE
--  dispatch loop at ~60fps and routes each registered wrapper to its update
--  function. FlipBook glows are C-driven (AnimationGroup) and never register
--  here. The driver hides itself when no glow is registered (zero idle cost)
--  and re-arms when the first glow registers.
-------------------------------------------------------------------------------
local DRIVER_GATE = 0.016  -- ~60fps ceiling for the entire dispatch loop

-- Array-based registry for cheap churn. _reg is a dense 1..N array of wrapper
-- frames; _regFn the parallel array of their engine update functions (called
-- directly in the hot loop, so dispatch is pure array access with no kind->fn
-- lookup); _regIndex maps wrapper -> its slot in _reg (for O(1) swap-remove);
-- _regKind maps wrapper -> its kind tag, read only by Unregister (cold path).
-- _regCount is the live entry count.
local _reg      = {}
local _regFn    = {}
local _regIndex = {}
local _regKind  = {}
local _regCount = 0
local _driver
local _driverAccum = 0

-- Glow profiler state (toggle with /euiglowprof; profiler block at file end).
-- _glowProf is read once per driver tick; when false the only added hot-path
-- cost is that single branch.
local dps         = debugprofilestop
local _glowProf   = false
local _gpTicks    = 0    -- driver ticks measured while profiling
local _gpTotalMs  = 0    -- summed driver-tick milliseconds
local _gpPeakMs   = 0    -- worst single driver-tick milliseconds
local _gpMaxGlows = 0    -- peak simultaneous registered glows seen

local function _DriverOnUpdate(self, elapsed)
    -- Gate the WHOLE loop at ~60fps: accumulate raw elapsed and only run a
    -- dispatch pass once the accumulator reaches the gate. The accumulated dt
    -- is handed to every engine and the accumulator resets to 0 (not minus the
    -- gate), so the sum of dispatched dt equals real elapsed exactly --
    -- animation speed is identical to a per-frame OnUpdate.
    local dt = _driverAccum + elapsed
    if dt < DRIVER_GATE then
        _driverAccum = dt
        return
    end
    _driverAccum = 0
    local _gp0, _gpN
    if _glowProf then _gp0 = dps(); _gpN = _regCount end
    -- Walk the dense array by index. An engine may unregister itself (or
    -- another wrapper) from inside its own update via Stop*, which swap-removes
    -- and shrinks _regCount; re-read _regCount each step and, when the current
    -- slot was swapped, re-test the same slot instead of advancing.
    local i = 1
    while i <= _regCount do
        local wrapper = _reg[i]
        -- Visibility gate: a per-wrapper OnUpdate used to stop for free when
        -- the frame OR any ancestor was hidden. IsVisible() reproduces that
        -- (own shown flag AND every ancestor shown). It reads only boolean
        -- shown flags, never alpha, so it is safe on the secret-alpha overlays
        -- (important-cast, RaidFrames threshold) whose alpha is a secret value.
        -- A wrapper that is shown but alpha-0 stays IsVisible()==true and keeps
        -- animating exactly as it did under its own OnUpdate; only Hide()-d or
        -- hidden-ancestor wrappers are skipped, and they resume automatically.
        if (not wrapper.IsVisible) or wrapper:IsVisible() then
            local fn = _regFn[i]
            if fn then fn(wrapper, dt) end
        end
        if _reg[i] == wrapper then
            i = i + 1
        end
    end
    if _gp0 then
        local ms = dps() - _gp0
        _gpTicks = _gpTicks + 1
        _gpTotalMs = _gpTotalMs + ms
        if ms > _gpPeakMs then _gpPeakMs = ms end
        if _gpN > _gpMaxGlows then _gpMaxGlows = _gpN end
    end
    if _regCount == 0 then
        self:Hide()
    end
end

local function _Arm()
    if not _driver then
        _driver = CreateFrame("Frame")
        _driver:Hide()
        _driver:SetScript("OnUpdate", _DriverOnUpdate)
    end
    _driverAccum = 0          -- avoid a stale-dt spike after an idle period
    _driver:Show()
end

-- Register a wrapper under the given kind. Idempotent: a second Start on the
-- same wrapper does not duplicate the entry or move the count; it only refreshes
-- the kind tag (so a style switch is robust even without a Stop first). Arms the
-- driver on the 0 -> 1 transition.
local function _Register(wrapper, fn, kind)
    local i = _regIndex[wrapper]
    if i then
        _regFn[i] = fn
        _regKind[wrapper] = kind
        return
    end
    _regCount = _regCount + 1
    _reg[_regCount] = wrapper
    _regFn[_regCount] = fn
    _regIndex[wrapper] = _regCount
    _regKind[wrapper] = kind
    if _regCount == 1 then _Arm() end
end

-- Unregister a wrapper. Safe no-op when the wrapper was never registered (Stop
-- without Start), so calling every Stop* in StopAllGlows is fine. When a kind is
-- passed it must match the wrapper's current registration: this makes a lone
-- cross-kind Stop* (e.g. StopButtonGlow on an "ants"-registered wrapper) a no-op
-- instead of tearing down the still-active engine. A nil kind stays kind-agnostic.
-- Swap-removes the entry so churn stays O(1); hides the driver when empty.
local function _Unregister(wrapper, kind)
    local idx = _regIndex[wrapper]
    if not idx then return end
    if kind and _regKind[wrapper] ~= kind then return end
    local last = _reg[_regCount]
    _reg[idx] = last
    _regFn[idx] = _regFn[_regCount]
    _regIndex[last] = idx
    _reg[_regCount] = nil
    _regFn[_regCount] = nil
    _regCount = _regCount - 1
    _regIndex[wrapper] = nil
    _regKind[wrapper] = nil
    if _regCount == 0 and _driver then _driver:Hide() end
end

-------------------------------------------------------------------------------
--  Procedural Ants Engine (texcoord-scroll)
--  4 fixed edge textures whose dashes march by scrolling a tileable strip via
--  SetTexCoord -- no per-frame SetPoint/SetSize, so it is FlipBook-cheap. The
--  N (line count) / thickness / speed / color are all configurable; the dash
--  LENGTH is the texture's duty cycle rather than a runtime segment length.
-------------------------------------------------------------------------------
local DASH_H = [[Interface\AddOns\EllesmereUI\media\glow-dash-h.tga]]
local DASH_V = [[Interface\AddOns\EllesmereUI\media\glow-dash-v.tga]]

local function _AntsOnUpdate(self, elapsed)
    local d = self._euiScrollData
    if not d then return end
    d.timer = d.timer + elapsed
    if d.timer >= d.period then d.timer = d.timer - d.period end
    local w, h = d.w, d.h
    if w * h == 0 then
        w, h = self:GetSize()
        -- Same taint-strip as the ants engine (reparented frames can return
        -- secret-number sizes).
        w = tonumber(tostring(w)) or 0
        h = tonumber(tostring(h)) or 0
        if w * h == 0 and d.fallbackW and d.fallbackW > 0 then
            w = d.fallbackW; h = d.fallbackH or d.fallbackW
        end
        if w * h == 0 then return end
        -- Snap dimensions AND thickness to physical pixels so every edge renders
        -- the same whole-pixel thickness (unsnapped SetHeight/SetWidth lets some
        -- sides round thicker than others at fractional effective scale).
        local PP = EllesmereUI.PP
        local onePixel = PP.perfect / self:GetEffectiveScale()
        w = floor(w / onePixel + 0.5) * onePixel
        h = floor(h / onePixel + 0.5) * onePixel
        local sTh = floor(d.th / onePixel + 0.5) * onePixel
        if sTh < onePixel then sTh = onePixel end
        d.top:SetHeight(sTh); d.bottom:SetHeight(sTh)
        d.left:SetWidth(sTh); d.right:SetWidth(sTh)
        d.w = w; d.h = h
        -- Precompute the per-edge phase endpoints; they are invariant until the
        -- next resize/restart, so only the scroll offset o changes per tick.
        -- ph(P) = P * N / perim is the perimeter position in dash-period units;
        -- the four edges share it so dashes stay continuous around every corner.
        local k = d.N / (2 * (w + h))
        d.wk   = w * k
        d.whk  = (w + h) * k
        d.wwhk = (2 * w + h) * k
    end
    local N = d.N
    local o = (d.timer / d.period) * N   -- scroll offset (N integer -> seamless wrap)
    -- Direction is clockwise; the bottom/left edges flip their coords to match.
    local wk, whk, wwhk = d.wk, d.whk, d.wwhk
    d.top:SetTexCoord(-o, wk - o, 0, 1)
    d.right:SetTexCoord(0, 1, wk - o, whk - o)
    d.bottom:SetTexCoord(wwhk - o, whk - o, 0, 1)
    d.left:SetTexCoord(0, 1, N - o, wwhk - o)
end

-- lineLen is accepted for call-signature compatibility but unused: the dash
-- length is the texture's duty cycle, not a runtime segment length.
local function StartProceduralAnts(wrapper, N, th, period, lineLen, cr, cg, cb, szOrW, szH)
    if not wrapper._euiScrollData then
        local function mk(p1, p1f, p2, p2f)
            local t = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetPoint(p1, wrapper, p1f)
            t:SetPoint(p2, wrapper, p2f)
            return t
        end
        wrapper._euiScrollData = {
            top    = mk("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT"),
            bottom = mk("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT"),
            left   = mk("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT"),
            right  = mk("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT"),
            timer = 0, w = 0, h = 0,
        }
    end
    local d = wrapper._euiScrollData
    d.N = (N and N > 0) and N or 8
    d.period = period or 4
    d.w = 0; d.h = 0
    d.fallbackW = szOrW or 0; d.fallbackH = szH or szOrW or 0
    th = th or 2
    d.th = th
    d.top:SetTexture(DASH_H, "REPEAT", "REPEAT");    d.top:SetHeight(th)
    d.bottom:SetTexture(DASH_H, "REPEAT", "REPEAT"); d.bottom:SetHeight(th)
    d.left:SetTexture(DASH_V, "REPEAT", "REPEAT");   d.left:SetWidth(th)
    d.right:SetTexture(DASH_V, "REPEAT", "REPEAT");  d.right:SetWidth(th)
    d.top:SetVertexColor(cr, cg, cb, 1);    d.top:Show()
    d.bottom:SetVertexColor(cr, cg, cb, 1); d.bottom:Show()
    d.left:SetVertexColor(cr, cg, cb, 1);   d.left:Show()
    d.right:SetVertexColor(cr, cg, cb, 1);  d.right:Show()
    _Register(wrapper, _AntsOnUpdate, "ants")
end

local function StopProceduralAnts(wrapper)
    _Unregister(wrapper, "ants")
    local d = wrapper._euiScrollData
    if d then
        d.top:Hide(); d.bottom:Hide(); d.left:Hide(); d.right:Hide()
    end
end

-------------------------------------------------------------------------------
--  Action Button Glow Engine
--  Outer glow (soft border from IconAlert) + animated marching ants.
-------------------------------------------------------------------------------
local function _ButtonGlowOnUpdate(self, elapsed)
    local d = self._euiBgData
    if not d then return end
    AnimateTexCoords(d.ants, 256, 256, 48, 48, 22, elapsed, 0.01)
end

local function StartButtonGlow(wrapper, szOrW, cr, cg, cb, scale, szH)
    scale = scale or 1.0
    local w = szOrW or 36
    local h = szH or w
    if not wrapper._euiBgData then
        local glow = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        glow:SetTexture(ICON_ALERT_TEX)
        glow:SetTexCoord(BG_GLOW_L, BG_GLOW_R, BG_GLOW_T, BG_GLOW_B)
        glow:SetBlendMode("ADD")
        glow:SetPoint("CENTER")
        local ants = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        ants:SetTexture(ANTS_TEX)
        ants:SetBlendMode("ADD")
        ants:SetPoint("CENTER")
        wrapper._euiBgData = { glow = glow, ants = ants }
    end
    local d = wrapper._euiBgData
    -- The ants texture has transparent padding baked into its frames,
    -- so we scale up to compensate and match the button edge visually.
    local antsW, antsH = w * 1.35, h * 1.35
    local glowW, glowH = antsW * 1.3, antsH * 1.3
    d.glow:SetSize(glowW, glowH)
    d.glow:SetDesaturated(true); d.glow:SetVertexColor(cr, cg, cb, 1)
    d.glow:SetAlpha(1); d.glow:Show()
    d.ants:SetSize(antsW, antsH)
    d.ants:SetDesaturated(true); d.ants:SetVertexColor(cr, cg, cb, 1)
    d.ants:SetAlpha(1); d.ants:Show()
    _Register(wrapper, _ButtonGlowOnUpdate, "button")
end

local function StopButtonGlow(wrapper)
    _Unregister(wrapper, "button")
    if wrapper._euiBgData then
        wrapper._euiBgData.ants:Hide()
        wrapper._euiBgData.glow:Hide()
    end
end

-------------------------------------------------------------------------------
--  Auto-Cast Shine Engine
--  4 layers of sparkle dots orbit the perimeter at staggered speeds.
--  Each layer has dotsPerLayer dots evenly spaced. Layer k orbits k times
--  slower than layer 1, creating a cascading sparkle effect.
-------------------------------------------------------------------------------

-- Compute x,y offset from TOPLEFT for a point at distance `dist`
-- around the perimeter (clockwise from top-left corner).
local function _OrbitXY(dist, w, h)
    if dist < w then
        return dist, 0
    end
    dist = dist - w
    if dist < h then
        return w, -dist
    end
    dist = dist - h
    if dist < w then
        return w - dist, -h
    end
    return 0, -(h - (dist - w))
end

local function _AutoCastOnUpdate(self, elapsed)
    local d = self._euiAcData
    if not d then return end
    local layerPhase = d.layerPhase
    local basePeriod = d.period
    for layer = 1, 4 do
        layerPhase[layer] = layerPhase[layer] + elapsed / (basePeriod * layer)
        if layerPhase[layer] > 1 then layerPhase[layer] = layerPhase[layer] - 1 end
    end
    d._accum = (d._accum or 0) + elapsed
    if d._accum < 0.016 then return end
    d._accum = 0
    local w, h = d.w, d.h
    if w * h == 0 then
        w, h = self:GetSize()
        -- Strip taint from size values (reparented buttons can return
        -- "secret number" tainted dimensions from GetSize).
        w = tonumber(tostring(w)) or 0
        h = tonumber(tostring(h)) or 0
        -- Fallback to the w/h passed at start time (SetAllPoints wrappers
        -- may return 0 before layout resolves)
        if w * h == 0 and d.fallbackW and d.fallbackW > 0 then
            w = d.fallbackW; h = d.fallbackH or d.fallbackW
        end
        if w * h == 0 then return end
        d.w = w; d.h = h
        d.perim = 2 * (w + h)
        d.spacing = d.perim / d.dotsPerLayer
    end
    local perim = d.perim
    local spacing = d.spacing
    local sparkles = d.sparkles
    local dotsPerLayer = d.dotsPerLayer
    local idx = 0
    for layer = 1, 4 do
        local phase = layerPhase[layer] * perim
        for i = 1, dotsPerLayer do
            idx = idx + 1
            local dist = (spacing * i + phase) % perim
            local px, py = _OrbitXY(dist, w, h)
            local dot = sparkles[idx]
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", self, "TOPLEFT", px, py)
        end
    end
end

local function StartAutoCastShine(wrapper, szOrW, cr, cg, cb, scale, szH)
    scale = scale or 1.0
    local dotsPerLayer = 4
    local totalDots = dotsPerLayer * 4
    if not wrapper._euiAcData then
        wrapper._euiAcData = {
            sparkles = {},
            layerPhase = { 0, 0.25, 0.5, 0.75 },
            dotsPerLayer = dotsPerLayer,
            period = 2,
            w = 0, h = 0,
        }
    end
    local d = wrapper._euiAcData
    d.dotsPerLayer = dotsPerLayer
    d.layerPhase[1] = 0; d.layerPhase[2] = 0.25; d.layerPhase[3] = 0.5; d.layerPhase[4] = 0.75
    for idx = 1, totalDots do
        if not d.sparkles[idx] then
            local dot = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
            dot:SetTexture(SHINE_TEX)
            dot:SetTexCoord(SHINE_COORDS[1], SHINE_COORDS[2], SHINE_COORDS[3], SHINE_COORDS[4])
            dot:SetDesaturated(true); dot:SetBlendMode("ADD")
            d.sparkles[idx] = dot
        end
        local layer = ceil(idx / dotsPerLayer)
        local baseSz = (SPARKLE_LAYER_SIZES[layer] or 4) * scale
        d.sparkles[idx]:SetSize(baseSz, baseSz)
        d.sparkles[idx]:SetVertexColor(cr, cg, cb, 1)
        d.sparkles[idx]:Show()
    end
    for idx = totalDots + 1, #d.sparkles do d.sparkles[idx]:Hide() end
    d.w = 0; d.h = 0; d.fallbackW = szOrW or 0; d.fallbackH = szH or szOrW or 0
    _Register(wrapper, _AutoCastOnUpdate, "autocast")
end

local function StopAutoCastShine(wrapper)
    _Unregister(wrapper, "autocast")
    if wrapper._euiAcData then
        for _, dot in ipairs(wrapper._euiAcData.sparkles) do dot:Hide() end
    end
end

-------------------------------------------------------------------------------
--  Shape Glow Engine
--  Pulsing additive glow using the icon's shape mask texture.
--  Used by ActionBars (custom shapes) and CDM (custom icon shapes).
--  opts.maskPath   — path to the shape mask texture
--  opts.borderPath — path to the shape border texture
--  opts.shapeMask  — MaskTexture object for AddMaskTexture
-------------------------------------------------------------------------------
local function _ShapeGlowOnUpdate(self, elapsed)
    local d = self._euiSgData
    if not d then return end
    local timer = d.timer + elapsed * d.speed
    if timer > 6.2832 then timer = timer - 6.2832 end
    d.timer = timer
    d.glow:SetAlpha(0.25 + 0.25 * (0.5 + 0.5 * sin(timer)))
    local bright = d.bright
    if bright then
        local bTimer = (d.bTimer or 0) + elapsed * d.speed * 0.50
        if bTimer > 6.2832 then bTimer = bTimer - 6.2832 end
        d.bTimer = bTimer
        bright:SetAlpha(0.35 + 0.10 * (0.5 + 0.5 * sin(bTimer)))
    end
end

local function StartShapeGlow(wrapper, sz, cr, cg, cb, scale, opts)
    scale = scale or 1.20
    opts = opts or {}
    -- anchorFrame overrides GetParent() for cases where the wrapper is
    -- parented to a different frame (e.g. action bar wrappers use
    -- btn:GetParent() to escape mask clipping).
    local btn = opts.anchorFrame or wrapper:GetParent()
    if not btn then return end
    if not wrapper._euiSgData then
        local glow   = btn:CreateTexture(nil, "OVERLAY", nil, 5)
        glow:SetBlendMode("ADD")
        local edge   = btn:CreateTexture(nil, "OVERLAY", nil, 5)
        edge:SetBlendMode("ADD")
        local bright = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        bright:SetBlendMode("ADD")
        wrapper._euiSgData = { glow = glow, edge = edge, bright = bright, timer = 0, speed = 10.0 }
    end
    local d = wrapper._euiSgData
    d.timer = 0

    -- Glow extends slightly past the button edge for the pulsing effect
    local extend = sz * 0.10
    d.glow:ClearAllPoints()
    d.glow:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -extend,  extend)
    d.glow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  extend, -extend)
    local maskPath   = opts.maskPath
    local borderPath = opts.borderPath
    if maskPath then
        d.glow:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    else
        d.glow:SetColorTexture(1, 1, 1, 1)
    end
    d.glow:SetVertexColor(cr, cg, cb, 1)
    d.glow:SetAlpha(1); d.glow:Show()

    -- Edge: not used (created an ugly inset inner border ring)
    d.edge:Hide()

    -- Bright border overlay
    d.bright:ClearAllPoints(); d.bright:SetAllPoints(btn)
    if borderPath then
        d.bright:SetTexture(borderPath)
    else
        d.bright:SetColorTexture(0, 0, 0, 0)
    end
    d.bright:SetVertexColor(cr, cg, cb, 1)
    d.bright:SetAlpha(0.5); d.bright:Show()

    -- Mask the pulsing glow with the shape mask texture
    local shapeMask = opts.shapeMask
    if shapeMask then
        pcall(d.glow.RemoveMaskTexture, d.glow, shapeMask)
        pcall(d.glow.AddMaskTexture, d.glow, shapeMask)
    end
    _Register(wrapper, _ShapeGlowOnUpdate, "shape")
end

local function StopShapeGlow(wrapper)
    _Unregister(wrapper, "shape")
    if wrapper._euiSgData then
        wrapper._euiSgData.glow:Hide()
        wrapper._euiSgData.edge:Hide()
        wrapper._euiSgData.bright:Hide()
    end
end

-------------------------------------------------------------------------------
--  FlipBook Glow Engine
--  Handles atlas-based and raw-texture FlipBook animations (GCD, Modern WoW
--  Glow, Classic WoW Glow, and any future FlipBook styles).
-------------------------------------------------------------------------------
local function StartFlipBookGlow(wrapper, szOrW, entry, cr, cg, cb, szH)
    -- FlipBook frames have transparent padding baked in. Each atlas
    -- has a different amount, so the style entry carries a texPadding
    -- multiplier (defaults to 1 = no compensation).
    local w = szOrW or 36
    local h = szH or w
    local texW = w * (entry.texPadding or 1)
    local texH = h * (entry.texPadding or 1)

    if not wrapper._euiFlipData then
        local tex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetPoint("CENTER")
        local ag = tex:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local anim = ag:CreateAnimation("FlipBook")
        wrapper._euiFlipData = { tex = tex, ag = ag, anim = anim }
    end
    local d = wrapper._euiFlipData
    d.tex:SetSize(texW, texH)
    if entry.atlas then
        d.tex:SetAtlas(entry.atlas)
    elseif entry.texture then
        d.tex:SetTexture(entry.texture)
    end
    d.tex:SetDesaturated(true)
    d.tex:SetVertexColor(cr, cg, cb)
    d.tex:Show()
    d.anim:SetFlipBookRows(entry.rows or 6)
    d.anim:SetFlipBookColumns(entry.columns or 5)
    d.anim:SetFlipBookFrames(entry.frames or 30)
    d.anim:SetDuration(entry.duration or 1.0)
    d.anim:SetFlipBookFrameWidth(entry.frameW or 0)
    d.anim:SetFlipBookFrameHeight(entry.frameH or 0)
    if d.ag:IsPlaying() then d.ag:Stop() end
    d.ag:Play()

    -- Ants overlay: a non-desaturated duplicate at low alpha for atlas styles
    if entry.atlas then
        if not d.ants then
            local aTex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
            aTex:SetPoint("CENTER")
            aTex:SetBlendMode("ADD")
            local aAg = aTex:CreateAnimationGroup()
            aAg:SetLooping("REPEAT")
            local aAnim = aAg:CreateAnimation("FlipBook")
            d.ants = aTex; d.antsAg = aAg; d.antsAnim = aAnim
        end
        d.ants:SetSize(texW, texH)
        d.ants:SetAtlas(entry.atlas)
        d.ants:SetDesaturated(false)
        d.ants:SetVertexColor(1, 1, 1)
        d.ants:SetAlpha(0.35)
        d.antsAnim:SetFlipBookRows(entry.rows or 6)
        d.antsAnim:SetFlipBookColumns(entry.columns or 5)
        d.antsAnim:SetFlipBookFrames(entry.frames or 30)
        d.antsAnim:SetDuration(entry.duration or 1.0)
        d.antsAnim:SetFlipBookFrameWidth(entry.frameW or 0)
        d.antsAnim:SetFlipBookFrameHeight(entry.frameH or 0)
        d.ants:Show()
        if d.antsAg:IsPlaying() then d.antsAg:Stop() end
        d.antsAg:Play()
    elseif d.ants then
        d.ants:Hide()
        if d.antsAg then d.antsAg:Stop() end
    end

    wrapper:SetScript("OnUpdate", nil)
end

local function StopFlipBookGlow(wrapper)
    if wrapper._euiFlipData then
        wrapper._euiFlipData.tex:Hide()
        if wrapper._euiFlipData.ag then wrapper._euiFlipData.ag:Stop() end
        if wrapper._euiFlipData.ants then wrapper._euiFlipData.ants:Hide() end
        if wrapper._euiFlipData.antsAg then wrapper._euiFlipData.antsAg:Stop() end
    end
end

-------------------------------------------------------------------------------
--  StopAllGlows — clears any active glow engine on a wrapper frame
-------------------------------------------------------------------------------
local function StopAllGlows(wrapper)
    if not wrapper then return end
    StopProceduralAnts(wrapper)
    StopButtonGlow(wrapper)
    StopAutoCastShine(wrapper)
    StopShapeGlow(wrapper)
    StopFlipBookGlow(wrapper)
    -- Defensive scrub: the central driver owns the only OnUpdate now, so the
    -- five Stop* calls above already unregistered this wrapper from the driver.
    -- This clears any stale OnUpdate a pre-migration build may have left on the
    -- wrapper itself (harmless on our own frame; never touches the driver).
    wrapper:SetScript("OnUpdate", nil)
end

-------------------------------------------------------------------------------
--  StartGlow — unified entry point
--  wrapper  : Frame to render the glow on
--  styleIdx : index into GLOW_STYLES (1-based)
--  sz       : icon/frame size in pixels
--  cr,cg,cb : glow color (0-1)
--  opts     : optional table with overrides:
--    .scale       — override entry.scale
--    .N, .th, .period — pixel glow tuning
--    .maskPath, .borderPath, .shapeMask — shape glow textures
-------------------------------------------------------------------------------
local function StartGlow(wrapper, styleIdx, szOrW, cr, cg, cb, opts, szH)
    if not wrapper then return end
    styleIdx = tonumber(styleIdx) or 1
    if styleIdx < 1 or styleIdx > #GLOW_STYLES then styleIdx = 1 end
    local entry = GLOW_STYLES[styleIdx]
    opts = opts or {}
    local w = szOrW or 36
    local h = szH or w
    cr = cr or 1; cg = cg or 1; cb = cb or 1

    -- Stop any previous glow
    StopAllGlows(wrapper)

    if entry.procedural then
        local N       = opts.N or 8
        local th      = opts.th or 2
        local period  = opts.period or 4
        local lineLen = floor((w + h) * (2 / N - 0.1))
        lineLen = min(lineLen, min(w, h))
        if lineLen < 1 then lineLen = 1 end
        StartProceduralAnts(wrapper, N, th, period, lineLen, cr, cg, cb, w, h)

    elseif entry.buttonGlow then
        StartButtonGlow(wrapper, w, cr, cg, cb, nil, h)

    elseif entry.autocast then
        StartAutoCastShine(wrapper, w, cr, cg, cb, 1.0, h)

    elseif entry.shapeGlow then
        StartShapeGlow(wrapper, w, cr, cg, cb, 1.20, opts)

    else
        -- FlipBook mode (GCD, Modern WoW Glow, Classic WoW Glow, etc.)
        StartFlipBookGlow(wrapper, w, entry, cr, cg, cb, h)
    end

    wrapper._euiGlowActive = true
    wrapper:SetAlpha(1)
    -- No Show() — wrapper should already be shown. Toggling visibility
    -- on children of Blizzard viewer frames triggers Layout cascades.
end

local function StopGlow(wrapper)
    if not wrapper then return end
    StopAllGlows(wrapper)
    wrapper._euiGlowActive = false
    wrapper:SetAlpha(0)
end

-------------------------------------------------------------------------------
--  Public API — attached to EllesmereUI.Glows
-------------------------------------------------------------------------------
EllesmereUI.Glows = {
    STYLES              = GLOW_STYLES,

    -- High-level API (recommended)
    StartGlow           = StartGlow,
    StopGlow            = StopGlow,

    -- Low-level engines (for addons that need direct control)
    StartProceduralAnts = StartProceduralAnts,
    StopProceduralAnts  = StopProceduralAnts,
    StartButtonGlow     = StartButtonGlow,
    StopButtonGlow      = StopButtonGlow,
    StartAutoCastShine  = StartAutoCastShine,
    StopAutoCastShine   = StopAutoCastShine,
    StartShapeGlow      = StartShapeGlow,
    StopShapeGlow       = StopShapeGlow,
    StartFlipBookGlow   = StartFlipBookGlow,
    StopFlipBookGlow    = StopFlipBookGlow,
    StopAllGlows        = StopAllGlows,
}

-------------------------------------------------------------------------------
--  Glow profiler: zero cost when off, /euiglowprof to toggle.
--  Times the central driver tick directly (the true glow render cost, avg +
--  peak per dispatch pass) and samples whole-addon CPU for the parent addon
--  (where the driver runs) and AuraBuff Reminders, so glow cost can be read
--  against both addon metrics. Matches the /erfprof profiler pattern.
-------------------------------------------------------------------------------
do
    local _names = { "EllesmereUI", "EllesmereUIAuraBuffReminders" }
    local _frames = 0
    local _addonTotal, _addonPeak = {}, {}

    local function Reset()
        _gpTicks, _gpTotalMs, _gpPeakMs, _gpMaxGlows = 0, 0, 0, 0
        _frames = 0
        wipe(_addonTotal); wipe(_addonPeak)
    end

    local sampler = CreateFrame("Frame")
    sampler:Hide()
    sampler:SetScript("OnUpdate", function()
        if not _glowProf then sampler:Hide(); return end
        if not C_AddOnProfiler or not C_AddOnProfiler.GetAddOnMetric then return end
        _frames = _frames + 1
        for _, name in ipairs(_names) do
            local ms = C_AddOnProfiler.GetAddOnMetric(name, Enum.AddOnProfilerMetric.LastTime) or 0
            _addonTotal[name] = (_addonTotal[name] or 0) + ms
            if ms > (_addonPeak[name] or 0) then _addonPeak[name] = ms end
        end
    end)

    SLASH_EUIGLOWPROF1 = "/euiglowprof"
    SlashCmdList["EUIGLOWPROF"] = function(msg)
        if msg == "reset" then
            Reset()
            print("|cff00ccffGlowProf:|r data cleared")
            return
        end
        _glowProf = not _glowProf
        if _glowProf then
            Reset()
            sampler:Show()
            print("|cff00ccffGlowProf:|r ON -- run /euiglowprof again to stop")
        else
            sampler:Hide()
            local avgTick = _gpTicks > 0 and (_gpTotalMs / _gpTicks) or 0
            print(format("|cff00ccffGlowProf Report:|r  %d driver ticks, peak %d simultaneous glows",
                _gpTicks, _gpMaxGlows))
            print(format("  |cff00ccffDriver tick:|r          avg %.4f ms   peak %.4f ms", avgTick, _gpPeakMs))
            for _, name in ipairs(_names) do
                local avg = _frames > 0 and ((_addonTotal[name] or 0) / _frames) or 0
                print(format("  |cff00ccff%-22s|r avg %.4f ms   peak %.4f ms",
                    name .. ":", avg, _addonPeak[name] or 0))
            end
        end
    end
end
