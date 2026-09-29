if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
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
      -- 5x5 grid = 25 cells, but only the first 22 are real ant frames; the last
      -- 3 are blank. Playing all 25 flashed an empty gap each loop that read as a
      -- backwards stutter. 22 matches what the Action Button Glow uses.
      -- This entry also doubles as Action Button Glow's FlipBook twin on
      -- engine-hosted buttons; the twin adds ABG's soft outer halo via
      -- opts.abgHalo, scoped to that substitution (see StartEngineGlow) --
      -- a direct Classic pick keeps this entry's bare-ants look.
      rows = 5, columns = 5, frames = 22, duration = 0.3,
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

-- Array-based registry for cheap churn. _reg is a dense 1..N array of wrapper frames;
-- _regFn the parallel array of their engine update functions (called directly in the
-- hot loop, so dispatch is pure array access with no kind->fn lookup); _regIndex maps
-- wrapper -> its slot in _reg (for O(1) swap-remove); _regKind maps wrapper -> its kind
-- tag, read only by Unregister (cold path). _regCount is the live entry count.
local _reg      = {}
local _regFn    = {}
local _regIndex = {}
local _regKind  = {}
local _regCount = 0
local _driver
local _driverAccum = 0

-- Unregister a wrapper. Safe no-op when the wrapper was never registered (Stop
-- without Start), so calling every Stop* in StopAllGlows is fine. When a kind is
-- passed it must match the wrapper's current registration: this makes a lone
-- cross-kind Stop* (e.g. StopButtonGlow on an "ants"-registered wrapper) a no-op
-- instead of tearing down the still-active engine. A nil kind stays kind-agnostic.
-- Swap-removes the entry so churn stays O(1); hides the driver when empty.
-- (Defined above the driver loop: the loop drops forbidden wrappers itself.)
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

local function _VisProbe(w) return w:IsVisible() end

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
        -- 12.1: a wrapper inside an ENGINE aura-button subtree has a SECRET
        -- visibility (the engine drives the button's shown state); a boolean test on it
        -- errors. Treat secret as hidden: the animation freezes for those wrappers
        -- while restricted (the glow still renders when its parent is actually shown)
        -- instead of ticking on the engine's 10x hidden pool buttons. Since PTR build
        -- 68914 the aura-button subtree is FORBIDDEN to addon code outside sanctioned
        -- windows: the IsVisible call itself throws instead of returning a secret, and
        -- one throwing wrapper would error every driver pass and freeze every other
        -- registered glow behind it. Probe under pcall and drop a throwing wrapper
        -- permanently -- forbidden-partition membership never recovers. (Driver styles
        -- should not be hosted there at all; StartEngineGlow is the sanctioned path.
        -- This guard makes a mistake non-fatal.)
        local vis = true
        if wrapper.IsVisible then
            local okv
            okv, vis = pcall(_VisProbe, wrapper)
            if not okv then
                _Unregister(wrapper)
                vis = false
            elseif issecretvalue and issecretvalue(vis) then
                vis = false
            end
        end
        if vis then
            local fn = _regFn[i]
            if fn then fn(wrapper, dt) end
        end
        if _reg[i] == wrapper then
            i = i + 1
        end
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

-------------------------------------------------------------------------------
--  Procedural Ants Engine (texcoord-scroll)
--  4 fixed edge textures whose dashes march by scrolling a tileable strip via
--  SetTexCoord -- no per-frame SetPoint/SetSize, so it is FlipBook-cheap. The
--  N (line count) / thickness / speed / color are all configurable; the dash
--  LENGTH is the texture's duty cycle rather than a runtime segment length.
-------------------------------------------------------------------------------
local DASH_H = [[Interface\AddOns\EllesmereUI\media\glow-dash-h.tga]]
local DASH_V = [[Interface\AddOns\EllesmereUI\media\glow-dash-v.tga]]

-- Resolve the wrapper's pixel-snapped size and precompute the per-edge phase endpoints
-- (invariant until the next resize). Returns false while the size is still 0, the scale
-- chain is degenerate, or the pixel grid is unusable, so the caller retries on a later
-- tick. Shared by the animated (_AntsOnUpdate) and static (_AntsStaticSettle) paths.
local function _AntsResolveSize(self, d)
    local w, h = self:GetSize()
    -- A secret size (the wrapper sits in a restricted layout) never reaches tostring or
    -- arithmetic: it takes the start-time fallback. Plain sizes keep the taint strip.
    if issecretvalue(w) or issecretvalue(h) then
        w, h = 0, 0
    else
        w = tonumber(tostring(w)) or 0
        h = tonumber(tostring(h)) or 0
    end
    if w * h == 0 and d.fallbackW and d.fallbackW > 0 then
        w = d.fallbackW; h = d.fallbackH or d.fallbackW
    end
    if w * h == 0 then return false end
    -- Snap dimensions AND thickness to physical pixels so every edge renders
    -- the same whole-pixel thickness (unsnapped SetHeight/SetWidth lets some
    -- sides round thicker than others at fractional effective scale).
    local PP = EllesmereUI.PP
    -- A degenerate scale chain (0 while layout is unresolved, or the
    -- SetScale(0.001) hide path) makes onePixel enormous, which collapses the
    -- snap below to w = h = 0 and turns the k divide into N/0. Every phase
    -- endpoint then goes non-finite and SetTexCoord rejects it on every driver
    -- tick. Stay unresolved instead and retry once the scale is real.
    local es = self:GetEffectiveScale()
    -- Same subtree class the GetSize taint-strip above exists for: a secret
    -- effective scale would hard-error on the comparison below, so take the
    -- retry path instead. No-op for normal values.
    if not es or (issecretvalue and issecretvalue(es)) or es < 0.1 then return false end
    local onePixel = PP.perfect / es
    w = floor(w / onePixel + 0.5) * onePixel
    h = floor(h / onePixel + 0.5) * onePixel
    -- A genuinely sub-pixel wrapper passes the size test above but snaps to 0;
    -- floor both dimensions at one pixel so (w + h) is always a real divisor.
    if w < onePixel then w = onePixel end
    if h < onePixel then h = onePixel end
    -- Total sanity gate before anything is cached. An infinite onePixel (a
    -- bogus PP.physicalHeight makes PP.perfect infinite) snaps w and h to NaN,
    -- which slips past every comparison above and then poisons the k divide
    -- below. NaN and inf both fail this test, so the phase endpoints are always
    -- real numbers and SetTexCoord can never be handed a value it rejects.
    if not (w > 0 and h > 0 and w + h < math.huge) then return false end
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
    return true
end

local function _AntsOnUpdate(self, elapsed)
    local d = self._euiScrollData
    if not d then return end
    d.timer = d.timer + elapsed
    if d.timer >= d.period then d.timer = d.timer - d.period end
    -- Positive-test rather than == 0 so a non-finite cached size fails it too
    -- and re-resolves, instead of feeding bad texcoords in forever.
    if not (d.w > 0 and d.h > 0) then
        if not _AntsResolveSize(self, d) then return end
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

-- Static (non-marching) dashes: draw once at the frozen base phase (scroll
-- offset 0). These are exactly the animated coords evaluated at o = 0, so the
-- dashes stay corner-continuous -- a dashed border rather than marching ants.
local function _AntsDrawStatic(self, d)
    local N = d.N
    local wk, whk, wwhk = d.wk, d.whk, d.wwhk
    d.top:SetTexCoord(0, wk, 0, 1)
    d.right:SetTexCoord(0, 1, wk, whk)
    d.bottom:SetTexCoord(wwhk, whk, 0, 1)
    d.left:SetTexCoord(0, 1, N, wwhk)
end

-- One-shot settler for static mode when the size was not resolved at Start time
-- (SetAllPoints wrappers can read 0 before layout resolves). Resolves, draws
-- once, then unregisters so a static border costs nothing per frame thereafter.
local function _AntsStaticSettle(self, elapsed)
    local d = self._euiScrollData
    if not d then _Unregister(self, "ants"); return end
    if not (d.w > 0 and d.h > 0) then
        if not _AntsResolveSize(self, d) then return end
    end
    _AntsDrawStatic(self, d)
    _Unregister(self, "ants")
end

-- lineLen is accepted for call-signature compatibility but unused: the dash
-- length is the texture's duty cycle, not a runtime segment length.
local function StartProceduralAnts(wrapper, N, th, period, lineLen, cr, cg, cb, szOrW, szH, bgR, bgG, bgB, bgA, static)
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
    -- bgR being non-nil is the "background on" signal; callers pass nil to
    -- disable. Do NOT change this to `bgR > 0`: a fully black background is
    -- r=0, which is a valid enabled color and must still draw.
    if bgR then
        if not d.bgTop then
            local function mkBg(p1, p1f, p2, p2f)
                local t = wrapper:CreateTexture(nil, "OVERLAY", nil, 6)
                t:SetPoint(p1, wrapper, p1f)
                t:SetPoint(p2, wrapper, p2f)
                return t
            end
            d.bgTop    = mkBg("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT")
            d.bgBottom = mkBg("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT")
            d.bgLeft   = mkBg("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT")
            d.bgRight  = mkBg("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT")
        end
        bgA = bgA or 1
        d.bgTop:SetHeight(th); d.bgBottom:SetHeight(th)
        d.bgLeft:SetWidth(th); d.bgRight:SetWidth(th)
        d.bgTop:SetColorTexture(bgR, bgG or 0, bgB or 0, bgA);       d.bgTop:Show()
        d.bgBottom:SetColorTexture(bgR, bgG or 0, bgB or 0, bgA);    d.bgBottom:Show()
        d.bgLeft:SetColorTexture(bgR, bgG or 0, bgB or 0, bgA);      d.bgLeft:Show()
        d.bgRight:SetColorTexture(bgR, bgG or 0, bgB or 0, bgA);     d.bgRight:Show()
    elseif d.bgTop then
        d.bgTop:Hide(); d.bgBottom:Hide(); d.bgLeft:Hide(); d.bgRight:Hide()
    end
    d.top:SetVertexColor(cr, cg, cb, 1);    d.top:Show()
    d.bottom:SetVertexColor(cr, cg, cb, 1); d.bottom:Show()
    d.left:SetVertexColor(cr, cg, cb, 1);   d.left:Show()
    d.right:SetVertexColor(cr, cg, cb, 1);  d.right:Show()
    if static then
        -- Frozen dashes: draw once now (size permitting) and stay off the
        -- animation driver. If layout has not resolved yet, a one-shot settler
        -- draws on the first tick that reads a real size, then unregisters.
        if _AntsResolveSize(wrapper, d) then
            _AntsDrawStatic(wrapper, d)
            _Unregister(wrapper, "ants")   -- clear any prior animated registration
        else
            _Register(wrapper, _AntsStaticSettle, "ants")
        end
    else
        _Register(wrapper, _AntsOnUpdate, "ants")
    end
end

local function StopProceduralAnts(wrapper)
    _Unregister(wrapper, "ants")
    local d = wrapper._euiScrollData
    if d then
        d.top:Hide(); d.bottom:Hide(); d.left:Hide(); d.right:Hide()
        if d.bgTop then d.bgTop:Hide(); d.bgBottom:Hide(); d.bgLeft:Hide(); d.bgRight:Hide() end
    end
end

-- Recolor active dashes in place. Secret-safe: r,g,b,a flow straight into
-- SetVertexColor with no arithmetic, so a secret (restricted) color is fine.
-- Used by the Raid Frames Frame-Border threshold recolor.
local function SetProceduralAntsColor(wrapper, r, g, b, a)
    local d = wrapper._euiScrollData
    if not d then return end
    a = a or 1
    d.top:SetVertexColor(r, g, b, a)
    d.bottom:SetVertexColor(r, g, b, a)
    d.left:SetVertexColor(r, g, b, a)
    d.right:SetVertexColor(r, g, b, a)
end

-------------------------------------------------------------------------------
--  Action Button Glow Engine
--  Outer glow (soft border from IconAlert) + animated marching ants.
-------------------------------------------------------------------------------
-- Marching-ants sprite cycler. Replaces a Blizzard SharedXML global that was
-- removed in 12.0 (present on live, nil on the PTR -> the glow OnUpdate erroring
-- out). Framerate-independent: it advances by however many cells the elapsed
-- time covers and carries the remainder, so the march speed is identical whether
-- the glow driver ticks at 60fps or faster, and it does not inherit the original
-- global's framerate-dependent quirks. ANTS_FRAME_TIME (seconds per cell) is the
-- single knob for the speed. State lives on our own ants texture.
local ANTS_FRAME_TIME = 0.017  -- ~59 cells/sec -> ~0.37s per 22-frame loop
local function _AnimateTexCoords(tex, sheetW, sheetH, cellW, cellH, numFrames, elapsed)
    if not tex._euiAnimCols then
        tex._euiAnimCols  = floor(sheetW / cellW)
        tex._euiAnimColW  = cellW / sheetW
        tex._euiAnimRowH  = cellH / sheetH
        tex._euiAnimFrame = 0
        tex._euiAnimAccum = 0
    end
    tex._euiAnimAccum = tex._euiAnimAccum + elapsed
    if tex._euiAnimAccum < ANTS_FRAME_TIME then return end

    local advance = floor(tex._euiAnimAccum / ANTS_FRAME_TIME)
    tex._euiAnimAccum = tex._euiAnimAccum - advance * ANTS_FRAME_TIME
    local frame = (tex._euiAnimFrame + advance) % numFrames
    tex._euiAnimFrame = frame

    local cols = tex._euiAnimCols
    local colW = tex._euiAnimColW
    local rowH = tex._euiAnimRowH
    local left = (frame % cols) * colW
    local top  = floor(frame / cols) * rowH
    tex:SetTexCoord(left, left + colW, top, top + rowH)
end

local function _ButtonGlowOnUpdate(self, elapsed)
    local d = self._euiBgData
    if not d then return end
    _AnimateTexCoords(d.ants, 256, 256, 48, 48, 22, elapsed)
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
        -- A secret size never reaches tostring or arithmetic: it takes the
        -- start-time fallback below. Plain sizes keep the taint strip.
        if issecretvalue(w) or issecretvalue(h) then
            w, h = 0, 0
        else
            w = tonumber(tostring(w)) or 0
            h = tonumber(tostring(h)) or 0
        end
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
-- Region creation only: the texture with its looping FlipBook group, plus on
-- request the atlas ants overlay (ants) and ABG's soft halo (halo), all
-- hidden. Shared with PrewarmEngineHost, which creates without configuring.
-- Each part's field appears only once its regions exist.
local function _EnsureFlip(wrapper, ants, halo)
    local d = wrapper._euiFlipData
    if not d then
        local tex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        tex:SetPoint("CENTER")
        tex:Hide()
        local ag = tex:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local anim = ag:CreateAnimation("FlipBook")
        d = { tex = tex, ag = ag, anim = anim }
        wrapper._euiFlipData = d
    end
    if ants and not d.ants then
        local aTex = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        aTex:SetPoint("CENTER")
        aTex:SetBlendMode("ADD")
        aTex:Hide()
        local aAg = aTex:CreateAnimationGroup()
        aAg:SetLooping("REPEAT")
        d.antsAnim = aAg:CreateAnimation("FlipBook")
        d.antsAg = aAg
        d.ants = aTex
    end
    if halo and not d.halo then
        local haloTex = wrapper:CreateTexture(nil, "OVERLAY", nil, 6)
        haloTex:SetTexture(ICON_ALERT_TEX)
        haloTex:SetTexCoord(BG_GLOW_L, BG_GLOW_R, BG_GLOW_T, BG_GLOW_B)
        haloTex:SetBlendMode("ADD")
        haloTex:SetPoint("CENTER")
        haloTex:Hide()
        d.halo = haloTex
    end
    return d
end

local function StartFlipBookGlow(wrapper, szOrW, entry, cr, cg, cb, szH, opts)
    -- FlipBook frames have transparent padding baked in. Each atlas
    -- has a different amount, so the style entry carries a texPadding
    -- multiplier (defaults to 1 = no compensation).
    local w = szOrW or 36
    local h = szH or w
    local texW = w * (entry.texPadding or 1)
    local texH = h * (entry.texPadding or 1)

    local d = _EnsureFlip(wrapper, entry.atlas ~= nil, opts and opts.abgHalo)
    d.tex:SetSize(texW, texH)
    if entry.atlas then
        d.tex:SetAtlas(entry.atlas)
    elseif entry.texture then
        d.tex:SetTexture(entry.texture)
    end
    if cr then
        d.tex:SetDesaturated(true)
        d.tex:SetVertexColor(cr, cg, cb)
    else
        -- no color requested - just show atlas untinted
        d.tex:SetDesaturated(false)
        d.tex:SetVertexColor(1, 1, 1)
    end
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

    -- Soft outer halo: matches the halo StartButtonGlow draws behind its ants.
    -- Keyed on the CALL (opts.abgHalo -- set only by StartEngineGlow's Action
    -- Button Glow substitution), never on the shared style entry: a direct
    -- Classic WoW Glow pick and the RestrictionSafeStyle Pixel remap keep
    -- their own bare-ants look, while the ABG stand-in matches the real
    -- thing instead of rendering visibly thinner.
    if opts and opts.abgHalo then
        d.halo:SetSize(texW * 1.3, texH * 1.3)
        d.halo:SetDesaturated(true)
        -- The halo carries the glow color (the ants stay white); no color
        -- chosen = the suite's canonical gold, the same default
        -- StartNativeGlow feeds tinted styles.
        d.halo:SetVertexColor(opts.haloR or 1.0, opts.haloG or 0.788, opts.haloB or 0.137, 1)
        d.halo:Show()
    elseif d.halo then
        d.halo:Hide()
    end

    wrapper:SetScript("OnUpdate", nil)
end

local function StopFlipBookGlow(wrapper)
    if wrapper._euiFlipData then
        wrapper._euiFlipData.tex:Hide()
        if wrapper._euiFlipData.ag then wrapper._euiFlipData.ag:Stop() end
        if wrapper._euiFlipData.ants then wrapper._euiFlipData.ants:Hide() end
        if wrapper._euiFlipData.antsAg then wrapper._euiFlipData.antsAg:Stop() end
        if wrapper._euiFlipData.halo then wrapper._euiFlipData.halo:Hide() end
    end
end

-- Defined above StopAllGlows so engine-hosted ants (StartEngineGlow /
-- StartAnimatedAnts) tear down through the same unified stop path.
local function StopAnimatedAnts(wrapper)
    local d = wrapper._euiAnimAnts
    if not d then return end
    for i = 1, 4 do
        d.groups[i]:Stop()
        d.strips[i]:Hide()
        if d.bgs and d.bgs[i] then d.bgs[i]:Hide() end
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
    StopAnimatedAnts(wrapper)
    -- Blizzard Border (EllesmereUI.Glows.STEALABLE_BORDER) is a static texture
    -- on the same hosts; a stop clears it too.
    local steal = wrapper._euiStealTex
    if steal then steal:Hide() end
    -- StartSpecGlow's change signature describes a glow that is now gone.
    local sig = wrapper._euiSpecSig
    if sig then sig.idx = nil end
    -- Defensive scrub: the central driver owns the only OnUpdate now, so the
    -- five Stop* calls above already unregistered this wrapper from the driver.
    -- This clears any stale OnUpdate a pre-migration build may have left on the
    -- wrapper itself (harmless on our own frame; never touches the driver).
    wrapper:SetScript("OnUpdate", nil)
end

-------------------------------------------------------------------------------
--  ApplyMaskWith -- bound every texture a glow engine created on a wrapper
--  with the caller's MaskTexture (caller supplies CLAMPTOBLACKADDITIVE wrap).
--  Every glow engine creates its textures directly on the wrapper, so the
--  region list is the complete set. Used by threshold-gated glows: the mask
--  tracks a gate StatusBar's fill rect, so a C-side value comparison decides
--  visibility without the value ever crossing into Lua. Masks keep rendering
--  where a SetClipsChildren bound goes dark on secret-derived rects in
--  restricted content. Dedicated wrappers only: the mask is never removed.
-------------------------------------------------------------------------------
local function ApplyMaskWith(wrapper, mask)
    if not (wrapper and mask) then return end
    for _, r in ipairs({ wrapper:GetRegions() }) do
        if r.AddMaskTexture and r._euiTGMask ~= mask then
            r._euiTGMask = mask
            r:AddMaskTexture(mask)
        end
    end
end

-------------------------------------------------------------------------------
--  StartGlow — unified entry point
--  wrapper  : Frame to render the glow on
--  styleIdx : index into GLOW_STYLES (1-based)
--  sz       : icon/frame size in pixels
--  cr,cg,cb : glow color (0-1)
--  opts     : optional table with overrides:
--    .scale       — override entry.scale
    --    .N, .th, .period, .bg — pixel glow tuning/background
--    .maskPath, .borderPath, .shapeMask — shape glow textures
--    .untinted    -- a nil color stays nil on the FlipBook path (the atlas's
--                   own untinted look) instead of desaturated white
-------------------------------------------------------------------------------
local function StartGlow(wrapper, styleIdx, szOrW, cr, cg, cb, opts, szH)
    if not wrapper then return end
    styleIdx = tonumber(styleIdx) or 1
    if styleIdx < 1 or styleIdx > #GLOW_STYLES then styleIdx = 1 end
    local entry = GLOW_STYLES[styleIdx]
    opts = opts or {}
    local w = szOrW or 36
    local h = szH or w
    local keepUntinted = opts.untinted and cr == nil
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
        local bg = opts.bg
        StartProceduralAnts(wrapper, N, th, period, lineLen, cr, cg, cb, w, h,
            bg and (bg.r or 0) or nil, bg and (bg.g or 0) or nil, bg and (bg.b or 0) or nil, bg and (bg.a or 1) or nil)

    elseif entry.buttonGlow then
        StartButtonGlow(wrapper, w, cr, cg, cb, nil, h)

    elseif entry.autocast then
        StartAutoCastShine(wrapper, w, cr, cg, cb, 1.0, h)

    elseif entry.shapeGlow then
        StartShapeGlow(wrapper, w, cr, cg, cb, 1.20, opts)

    else
        -- FlipBook mode (GCD, Modern WoW Glow, Classic WoW Glow, etc.)
        if keepUntinted then
            StartFlipBookGlow(wrapper, w, entry, nil, nil, nil, h, opts)
        else
            StartFlipBookGlow(wrapper, w, entry, cr, cg, cb, h, opts)
        end
    end

    if opts.maskWith then ApplyMaskWith(wrapper, opts.maskWith) end

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
--  Animation-driven glow (engine aura buttons)
--  The 12.1 slot-button subtree is forbidden to addon code outside its
--  creation window, so the driver-ticked engines above (Lua OnUpdate)
--  freeze there. This variant reproduces the Pixel Glow march with C-side
--  AnimationGroups: created and started once in the creation window, it
--  animates forever with zero per-frame Lua -- identically in and out of
--  secret contexts.
-------------------------------------------------------------------------------
local ANIM_MASK_TEX = [[Interface\Buttons\WHITE8X8]]

-- One hidden background strip of the animated ants, spanning p1 to p2.
local function _MkAntsBg(wrapper, p1, p2)
    local t = wrapper:CreateTexture(nil, "OVERLAY", nil, 6)
    t:SetPoint(p1, wrapper, p1)
    t:SetPoint(p2, wrapper, p2)
    t:Hide()
    return t
end

-- Region creation only (shared with PrewarmEngineHost): per edge the rect mask,
-- the dash strip and its looping Translation, then the background strips,
-- all hidden. The data table appears only once every region exists.
local function _EnsureAnimAnts(wrapper)
    local d = wrapper._euiAnimAnts
    if d then return d end
    d = { strips = {}, masks = {}, groups = {}, trs = {}, bgs = {} }
    for i = 1, 4 do
        local mask = wrapper:CreateMaskTexture()
        mask:SetTexture(ANIM_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        local strip = wrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        strip:AddMaskTexture(mask)
        strip:Hide()
        local ag = strip:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local tr = ag:CreateAnimation("Translation")
        tr:SetSmoothing("NONE")
        d.masks[i], d.strips[i], d.groups[i], d.trs[i] = mask, strip, ag, tr
    end
    -- Background strips: top, right, bottom, left (same order as the edges).
    d.bgs[1] = _MkAntsBg(wrapper, "TOPLEFT", "TOPRIGHT")
    d.bgs[2] = _MkAntsBg(wrapper, "TOPRIGHT", "BOTTOMRIGHT")
    d.bgs[3] = _MkAntsBg(wrapper, "BOTTOMLEFT", "BOTTOMRIGHT")
    d.bgs[4] = _MkAntsBg(wrapper, "TOPLEFT", "BOTTOMLEFT")
    wrapper._euiAnimAnts = d
    return d
end

-- Marching dashes: per edge, a dash strip one pattern-cycle longer than the edge slides
-- by exactly one cycle and loops; a rect mask clips it to the edge, so the snap-back is
-- invisible and the march is seamless. Strip texcoords carry the cumulative perimeter
-- phase, keeping dashes corner-continuous exactly like the driver-ticked ants (phase
-- matters modulo one cycle, so the one-cycle anchor offsets cancel out).
-- bgR non-nil = background on (same contract as StartProceduralAnts): a static
-- solid strip under each edge. The strips are created WITH the dash strips on
-- the first call, so turning the background on later never creates a region
-- outside the host's creation window.
local function StartAnimatedAnts(wrapper, N, th, period, cr, cg, cb, w, h, ca, bgR, bgG, bgB, bgA)
    N = (N and N > 0) and N or 8
    th = th or 2
    period = period or 4
    w = w or 36; h = h or w
    local perim = 2 * (w + h)
    local P = perim / N              -- pixels per dash cycle
    local step = period / N          -- seconds per dash cycle
    local d = _EnsureAnimAnts(wrapper)
    for i = 1, 4 do
        local t = d.bgs[i]
        if bgR then
            if i == 1 or i == 3 then t:SetHeight(th) else t:SetWidth(th) end
            t:SetColorTexture(bgR, bgG or 0, bgB or 0, bgA or 1)
            t:Show()
        else
            t:Hide()
        end
    end
    -- Edge order (clockwise): 1 top scrolls right, 2 right scrolls down,
    -- 3 bottom scrolls left, 4 left scrolls up. base = cumulative
    -- perimeter phase in cycles at the edge's visual start. Computed per
    -- edge in place (no per-call tables).
    cr, cg, cb, ca = cr or 1, cg or 1, cb or 1, ca or 1
    for i = 1, 4 do
        local mask, strip, ag, tr = d.masks[i], d.strips[i], d.groups[i], d.trs[i]
        ag:Stop()
        strip:SetVertexColor(cr, cg, cb, ca)
        mask:ClearAllPoints()
        strip:ClearAllPoints()
        if i == 1 or i == 3 then
            local base = 0
            if i == 3 then base = (w + h) / P end
            strip:SetTexture(DASH_H, "REPEAT", "REPEAT")
            mask:SetSize(w, th)
            strip:SetSize(w + P, th)
            if i == 1 then
                mask:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 0, 0)
                strip:SetPoint("TOPLEFT", wrapper, "TOPLEFT", -P, 0)
                tr:SetOffset(P, 0)
            else
                mask:SetPoint("BOTTOMLEFT", wrapper, "BOTTOMLEFT", 0, 0)
                strip:SetPoint("BOTTOMLEFT", wrapper, "BOTTOMLEFT", 0, 0)
                tr:SetOffset(-P, 0)
            end
            strip:SetTexCoord(base, base + (w + P) / P, 0, 1)
        else
            local base = w / P
            if i == 4 then base = (w + h + w) / P end
            strip:SetTexture(DASH_V, "REPEAT", "REPEAT")
            mask:SetSize(th, h)
            strip:SetSize(th, h + P)
            if i == 2 then
                mask:SetPoint("TOPRIGHT", wrapper, "TOPRIGHT", 0, 0)
                strip:SetPoint("TOPRIGHT", wrapper, "TOPRIGHT", 0, P)
                tr:SetOffset(0, -P)
            else
                mask:SetPoint("BOTTOMLEFT", wrapper, "BOTTOMLEFT", 0, 0)
                strip:SetPoint("BOTTOMLEFT", wrapper, "BOTTOMLEFT", 0, -P)
                tr:SetOffset(0, P)
            end
            strip:SetTexCoord(0, 1, base, base + (h + P) / P)
        end
        strip:Show()
        tr:SetDuration(step)
        ag:Play()
    end
end

-------------------------------------------------------------------------------
--  StartEngineGlow — StartGlow for wrappers on ENGINE aura-button subtrees
--  (12.1 forbidden partition: NP purge, RF DM fx, RF BM icon glow, ...).
--  Driver-ticked engines cannot run there -- the driver's Lua reads on the
--  wrapper throw outside sanctioned windows -- so every driver style routes
--  to its C-side equivalent and animates identically in and out of secret
--  contexts: Pixel Glow renders its GENUINE dash march through the animated
--  ants engine (not a lookalike remap), Action Button Glow plays its
--  flipbook twin (the same IconAlertAnts sheet the driver version scrolls),
--  and Auto-Cast Shine / Shape Glow -- no C-side equivalent built -- fall
--  back to the Modern WoW Glow loop (options on engine-hosted pickers hide
--  those two; the fallback only covers stale saved values). FlipBook picks
--  pass through untouched. Never registers with the central driver.
-------------------------------------------------------------------------------
local ABG_HALO_OPTS = { abgHalo = true }  -- shared scratch for the no-opts ABG substitution (halo color rewritten per call, read synchronously)
local function StartEngineGlow(wrapper, styleIdx, szOrW, cr, cg, cb, opts, szH)
    if not wrapper then return end
    styleIdx = tonumber(styleIdx) or 1
    if styleIdx < 1 or styleIdx > #GLOW_STYLES then styleIdx = 1 end
    local entry = GLOW_STYLES[styleIdx]
    if entry.procedural then
        opts = opts or {}
        local w = szOrW or 36
        local bg = opts.bg
        StopAllGlows(wrapper)
        StartAnimatedAnts(wrapper, opts.N or 8, opts.th or 2, opts.period or 4,
            cr or 1, cg or 1, cb or 1, w, szH or w, nil,
            bg and (bg.r or 0) or nil, bg and (bg.g or 0) or nil, bg and (bg.b or 0) or nil, bg and (bg.a or 1) or nil)
        wrapper._euiGlowActive = true
        wrapper:SetAlpha(1)
        return
    end
    if entry.buttonGlow then
        -- Classic's flipbook sheet plus ABG's soft outer halo (opts.abgHalo),
        -- scoped to this substitution and never to the shared Classic entry.
        -- Real ABG anatomy: the ants stay white (nil color = the flipbook's
        -- white default) while the COLOR rides the halo alone -- gold when
        -- the caller never chose one.
        styleIdx = 7
        -- untinted would turn the white ants into the sheet's raw gold; the
        -- substitution always wants them white.
        if opts then opts.abgHalo = true; opts.untinted = nil else opts = ABG_HALO_OPTS end
        opts.haloR, opts.haloG, opts.haloB = cr, cg, cb
        cr, cg, cb = nil, nil, nil
    elseif entry.autocast or entry.shapeGlow then
        styleIdx = 6
    end
    StartGlow(wrapper, styleIdx, szOrW, cr, cg, cb, opts, szH)
end

-------------------------------------------------------------------------------
--  Public API — attached to EllesmereUI.Glows
-------------------------------------------------------------------------------
-- Styles that render through C-side FlipBook AnimationGroups (GCD, Modern WoW Glow,
-- Classic WoW Glow) animate IDENTICALLY under 12.1 aura restrictions; driver-ticked
-- styles (Pixel, Action Button, Auto-Cast, Shape) cannot -- secret visibility blocks
-- their Lua ticks, leaving a frozen artifact. Kept for external callers that want a
-- plain style REMAP (in-tree engine-button hosts use StartEngineGlow instead, which
-- renders Pixel genuinely): Pixel -> Classic WoW Glow (ants), everything else
-- driver-based -> Modern WoW Glow (the standard proc loop).
local SAFE_STYLE_MAP = { [1] = 7, [2] = 6, [3] = 6, [4] = 6 }
local function RestrictionSafeStyle(idx)
    local entry = GLOW_STYLES[idx]
    if entry and (entry.procedural or entry.buttonGlow or entry.autocast or entry.shapeGlow) then
        return SAFE_STYLE_MAP[idx] or 6
    end
    return idx
end

EllesmereUI.Glows = {
    STYLES              = GLOW_STYLES,

    -- High-level API (recommended)
    StartGlow           = StartGlow,
    StartEngineGlow     = StartEngineGlow,
    StopGlow            = StopGlow,
    RestrictionSafeStyle = RestrictionSafeStyle,

    -- Low-level engines (for addons that need direct control)
    StartProceduralAnts = StartProceduralAnts,
    StopProceduralAnts  = StopProceduralAnts,
    SetProceduralAntsColor = SetProceduralAntsColor,
    StartButtonGlow     = StartButtonGlow,
    StopButtonGlow      = StopButtonGlow,
    StartAutoCastShine  = StartAutoCastShine,
    StopAutoCastShine   = StopAutoCastShine,
    StartAnimatedAnts   = StartAnimatedAnts,
    StopAnimatedAnts    = StopAnimatedAnts,
    StartShapeGlow      = StartShapeGlow,
    StopShapeGlow       = StopShapeGlow,
    StartFlipBookGlow   = StartFlipBookGlow,
    StopFlipBookGlow    = StopFlipBookGlow,
    ApplyMaskWith       = ApplyMaskWith,
    StopAllGlows        = StopAllGlows,
}

-------------------------------------------------------------------------------
--  Blizzard Border: the static art Blizzard's own target frame puts on a buff
--  it can steal or purge. No driver and no animation, so it renders the same
--  in and out of restricted content on engine aura buttons (where a glow host
--  belongs to a purgeable GROUP, never to a per-aura read). Its picker value
--  sits outside the STYLES list. The texture is made on first use (the
--  flipbook glows create theirs on the same hosts the same way); Show/Hide
--  then only resize, tint and toggle it.
-------------------------------------------------------------------------------
do
    local G = EllesmereUI.Glows
    local TEX = "Interface\\TargetingFrame\\UI-TargetingFrame-Stealable"
    -- Blizzard draws it 24 px on a 21 px buff icon.
    local SCALE = 24 / 21
    G.STEALABLE_BORDER = 99

    function G.EnsureStealableBorder(host)
        local tex = host._euiStealTex
        if not tex then
            tex = host:CreateTexture(nil, "OVERLAY")
            tex:SetTexture(TEX)
            tex:SetBlendMode("ADD")
            tex:SetPoint("CENTER")
            tex:Hide()
            host._euiStealTex = tex
        end
        return tex
    end

    -- w/h: the icon's size; nil color = Blizzard's own look. A tint
    -- desaturates first, like the flipbook glows, so the pick reads true.
    function G.ShowStealableBorder(host, w, h, cr, cg, cb)
        local tex = G.EnsureStealableBorder(host)
        w = w or 24
        h = h or w
        tex:SetSize(w * SCALE, h * SCALE)
        tex:SetDesaturated(cr ~= nil)
        tex:SetVertexColor(cr or 1, cg or 1, cb or 1)
        tex:Show()
    end

    function G.HideStealableBorder(host)
        local tex = host and host._euiStealTex
        if tex then tex:Hide() end
        -- StartSpecGlow's change check must not skip showing it again.
        local s = host and host._euiSpecSig
        if s and s.idx == G.STEALABLE_BORDER then s.idx = nil end
    end
end

-------------------------------------------------------------------------------
--  Unified glow model
--  GLOW_STYLES is the one style table (the "shared index"). Modules keep their
--  historical saved numbering through a VIEW, hosts describe what can render
--  where, and StartSpecGlow renders a whole glow setting (style, color, pixel
--  parameters, background) in one call. Saved keys stay module-owned: these
--  helpers only translate and render.
-------------------------------------------------------------------------------
do
    local G = EllesmereUI.Glows

    -- Suite default look ("default" color mode): gold for the drawn engines,
    -- the atlas's own untinted look for FlipBook styles.
    local DEF_R, DEF_G, DEF_B = 1.0, 0.788, 0.137
    G.DEFAULT_COLOR = { r = DEF_R, g = DEF_G, b = DEF_B }

    -- A module's style list in its saved order. list[i] is the shared entry
    -- itself, or a proxy over it when overrides[i] adds module-only fields
    -- (read through __index, so frames/texPadding always come from the shared
    -- table). toShared[i] / fromShared[shared] translate saved <-> shared.
    -- ordered = the saved values in shared order, so every menu lists the
    -- styles the same way whatever a module's saved numbering is.
    function G.MakeView(order, overrides)
        local list, toShared, fromShared, ordered = {}, {}, {}, {}
        for i = 1, #order do
            local si = order[i]
            local ov = overrides and overrides[i]
            list[i] = ov and setmetatable(ov, { __index = GLOW_STYLES[si] }) or GLOW_STYLES[si]
            toShared[i] = si
            fromShared[si] = i
        end
        for si = 1, #GLOW_STYLES do
            if fromShared[si] then ordered[#ordered + 1] = fromShared[si] end
        end
        return { list = list, toShared = toShared, fromShared = fromShared, ordered = ordered }
    end

    -- Styles each host can render, by shared index. Only technical limits live
    -- here; which styles a site OFFERS (e.g. no Shape without an icon shape) is
    -- the site's own excludes list.
    --   icon   : our own frame, driver-ticked engines allowed
    --   bar    : our own rectangular frame; Shape has no shape to follow
    --   engine : 12.1 aura-button subtree; no driver ticks, so no Auto-Cast or
    --            Shape (Pixel renders as animated ants, ABG as its FlipBook twin)
    G.HOSTS = {
        icon   = { true, true, true, true,  true, true, true },
        bar    = { true, true, true, false, true, true, true },
        engine = { true, true, false, false, true, true, true },
    }

    -- Rectangles (buff bars, whole-frame glows): the texture styles
    -- (ABG, GCD, Modern, Classic) are square art that stretches on a wide bar,
    -- and Shape has no shape to follow, so only Pixel and Auto-Cast draw
    -- cleanly. Rectangle sites pass this as their excludes, in the options and
    -- in the live spec (an engine host drops Auto-Cast on top: Pixel only).
    G.RECT_EXCLUDES = { [2] = true, [4] = true, [5] = true, [6] = true, [7] = true }

    -- Nearest renderable replacement, in preference order, per wanted style.
    local FALLBACK = {
        [1] = { 7, 6, 5 },   -- Pixel      -> Classic ants
        [2] = { 7, 6, 1 },   -- ABG        -> Classic
        [3] = { 6, 5, 1 },   -- Auto-Cast  -> Modern (StartEngineGlow's own remap)
        [4] = { 6, 1, 7 },   -- Shape      -> Modern
        [5] = { 6, 7, 1 },
        [6] = { 5, 7, 1 },
        [7] = { 1, 6, 5 },
    }

    -- Shared index -> renderable shared index, plus whether it had to change.
    function G.ResolveStyle(idx, host, excludes)
        idx = tonumber(idx) or 1
        -- Blizzard Border is a plain texture: every host can show it.
        if idx == G.STEALABLE_BORDER then return idx, false end
        if idx < 1 or idx > #GLOW_STYLES then idx = 1 end
        local caps = G.HOSTS[host or "icon"] or G.HOSTS.icon
        if caps[idx] and not (excludes and excludes[idx]) then return idx, false end
        local alts = FALLBACK[idx]
        for k = 1, #alts do
            local a = alts[k]
            if caps[a] and not (excludes and excludes[a]) then return a, true end
        end
        return 1, true
    end

    -- Color for a mode. nil = the suite default (StartSpecGlow resolves it per
    -- style). A nil mode is a legacy site that never stored one: it reads as
    -- custom with the site's own default, so its look is unchanged.
    function G.ResolveColor(mode, r, g, b, defR, defG, defB)
        if mode == "default" then return nil end
        if mode == "class" then
            -- The palette colour (custom + Class Color Darken); an unknown class is white.
            local c = EllesmereUI.GetClassColor(EllesmereUI._playerClass)
            return c.r, c.g, c.b
        end
        if r ~= nil then return r, g or 0, b or 0 end
        return defR, defG, defB
    end

    -- Legacy sites store a class-color boolean instead of a mode.
    function G.DeriveColorMode(mode, classFlag)
        if mode then return mode end
        return classFlag and "class" or "custom"
    end

    -- Speed: the UI shows 1-8 with higher = faster; saved values are the march
    -- period in seconds. Stored periods above 8 (older 1-10 sliders) still
    -- render as saved and read as the slowest step until edited.
    function G.SpeedToUI(period)
        local v = 9 - (period or 4)
        if v < 1 then v = 1 elseif v > 8 then v = 8 end
        return v
    end
    function G.SpeedFromUI(v) return 9 - v end

    -- Spec from a settings table using the prefix key schema shared by the aura
    -- managers: <p>Type (shared index, 0 = off), <p>ColorMode, legacy
    -- <p>ClassColor, <p>R/G/B, <p>Lines, <p>Thickness, <p>Speed, <p>Background,
    -- <p>BackgroundR/G/B. Returns nil when off. Keys are built once per prefix.
    local _prefixKeys = {}
    local function PrefixKeys(p)
        local k = _prefixKeys[p]
        if not k then
            k = { type = p .. "Type", mode = p .. "ColorMode", class = p .. "ClassColor",
                  r = p .. "R", g = p .. "G", b = p .. "B", lines = p .. "Lines",
                  th = p .. "Thickness", speed = p .. "Speed", bg = p .. "Background",
                  bgR = p .. "BackgroundR", bgG = p .. "BackgroundG", bgB = p .. "BackgroundB" }
            _prefixKeys[p] = k
        end
        return k
    end
    G.PrefixKeys = PrefixKeys

    function G.SpecFromPrefix(out, t, p, defR, defG, defB)
        local k = PrefixKeys(p)
        local style = t and t[k.type] or 0
        if not style or style == 0 then return nil end
        out.style = style
        out.r, out.g, out.b = G.ResolveColor(G.DeriveColorMode(t[k.mode], t[k.class]),
            t[k.r], t[k.g], t[k.b], defR, defG, defB)
        out.lines, out.thickness, out.speed = t[k.lines], t[k.th], t[k.speed]
        if t[k.bg] then
            out.bg, out.bgR, out.bgG, out.bgB = true, t[k.bgR] or 0, t[k.bgG] or 0, t[k.bgB] or 0
        else
            -- out is the caller's reused scratch: clear the colour too.
            out.bg, out.bgR, out.bgG, out.bgB = nil, nil, nil, nil
        end
        return out
    end

    -- Options previews sit in the panel, whose pixel grid differs from
    -- UIParent's: a raw thickness would draw a different (or no) pixel count
    -- there. Pass PANEL_EXTRA as StartSpecGlow's extra to draw the pixels the
    -- live UIParent glow shows.
    G.PANEL_EXTRA = { panel = true }
    function G.PanelThickness(th)
        local PP, PPP = EllesmereUI.PP, EllesmereUI.PanelPP
        local px = math.floor(th / ((PP and PP.mult) or 1) + 0.5)
        if px < 1 then px = 1 end
        return px * ((PPP and PPP.mult) or 1)
    end

    -- Scratch opts for StartSpecGlow: every field is rewritten on every call.
    -- StartEngineGlow writes abgHalo/halo* into the table it is given, so a
    -- field left over from one call would leak into the next (a Classic pick
    -- after an ABG pick would keep the halo).
    local _opts, _bg = {}, {}

    -- spec = { style = shared index, r, g, b (already resolved; nil = default
    --          look), lines, thickness, speed (period), bg, bgR, bgG, bgB,
    --          excludes }
    -- host = "icon" | "bar" | "engine"; extra = { maskWith, maskPath,
    --          borderPath, shapeMask, anchorFrame, panel } (optional, read in this call)
    -- Restarts only when something changed; returns the rendered shared index
    -- and whether it was converted from the requested one.
    function G.StartSpecGlow(wrapper, spec, w, h, host, extra)
        if not (wrapper and spec) then return end
        local idx, converted = G.ResolveStyle(spec.style, host, spec.excludes)
        w = w or 36; h = h or w
        local s = wrapper._euiSpecSig
        -- Blizzard Border: no glow, no parameters; nil color = Blizzard's art.
        if idx == G.STEALABLE_BORDER then
            local r, g, b = spec.r, spec.g, spec.b
            -- StopGlow leaves the host at alpha 0 and a caller may park it
            -- there, so the alpha is re-asserted even when nothing changed.
            wrapper:SetAlpha(1)
            if s and s.idx == idx and s.w == w and s.h == h
               and s.r == r and s.g == g and s.b == b then
                return idx, false
            end
            -- Clear the flag too (StopAllGlows keeps it), so later calls skip the teardown.
            if wrapper._euiGlowActive then StopAllGlows(wrapper); wrapper._euiGlowActive = false end
            G.ShowStealableBorder(wrapper, w, h, r, g, b)
            if not s then s = {}; wrapper._euiSpecSig = s end
            s.idx, s.host, s.w, s.h, s.r, s.g, s.b = idx, host, w, h, r, g, b
            return idx, false
        end
        -- A shown Blizzard Border needs no separate hide: every start below
        -- runs StopAllGlows first, which hides it and clears the signature.
        local entry = GLOW_STYLES[idx]
        local r, g, b = spec.r, spec.g, spec.b
        local isFlip = not (entry.procedural or entry.buttonGlow or entry.autocast or entry.shapeGlow)
        -- Default look: FlipBooks stay untinted (nil). The engine-hosted ABG
        -- twin takes nil too (white ants, gold halo); everything else is gold.
        if r == nil and not isFlip
           and not (host == "engine" and entry.buttonGlow) then
            r, g, b = DEF_R, DEF_G, DEF_B
        end
        local N, th, period = spec.lines or 8, spec.thickness or 2, spec.speed or 4
        if extra and extra.panel then th = G.PanelThickness(th) end
        local bgOn = spec.bg and true or false
        -- An off background draws nothing, so its colour never counts (a
        -- reused scratch spec can still carry an old one).
        local bgR, bgG, bgB = 0, 0, 0
        if bgOn then bgR, bgG, bgB = spec.bgR or 0, spec.bgG or 0, spec.bgB or 0 end
        local mask = extra and extra.maskWith or nil
        local maskPath = extra and extra.maskPath or nil
        local shapeMask = extra and extra.shapeMask or nil

        if s and wrapper._euiGlowActive and s.idx == idx and s.host == host
           and s.w == w and s.h == h and s.r == r and s.g == g and s.b == b
           and s.N == N and s.th == th and s.period == period
           and s.bg == bgOn and s.bgR == bgR and s.bgG == bgG and s.bgB == bgB
           and s.mask == mask and s.maskPath == maskPath and s.shapeMask == shapeMask then
            return idx, converted
        end

        local o = _opts
        o.N, o.th, o.period = N, th, period
        if bgOn then
            _bg.r, _bg.g, _bg.b, _bg.a = bgR, bgG, bgB, 1
            o.bg = _bg
        else
            o.bg = nil
        end
        o.untinted = (r == nil) or nil
        o.abgHalo, o.haloR, o.haloG, o.haloB = nil, nil, nil, nil
        o.maskWith = mask
        o.maskPath    = maskPath
        o.borderPath  = extra and extra.borderPath or nil
        o.shapeMask   = shapeMask
        o.anchorFrame = extra and extra.anchorFrame or nil
        if host == "engine" then
            StartEngineGlow(wrapper, idx, w, r, g, b, o, h)
        else
            StartGlow(wrapper, idx, w, r, g, b, o, h)
        end

        -- Stored after the start: StartGlow's StopAllGlows invalidates it.
        s = wrapper._euiSpecSig
        if not s then s = {}; wrapper._euiSpecSig = s end
        s.idx, s.host, s.w, s.h, s.r, s.g, s.b = idx, host, w, h, r, g, b
        s.N, s.th, s.period = N, th, period
        s.bg, s.bgR, s.bgG, s.bgB, s.mask = bgOn, bgR, bgG, bgB, mask
        s.maskPath, s.shapeMask = maskPath, shapeMask
        return idx, converted
    end

    -- Create the regions an engine-hosted glow can need, hidden and
    -- unconfigured, from the host's creation window (extraInit): a later style
    -- or background change then only reconfigures existing regions, and the
    -- first StartSpecGlow does the only setup (nothing is sized, tinted or
    -- played here). need = nil creates every family; else a table naming what
    -- the site can draw: ants (Pixel's animated ants and their background
    -- strips), flip (the FlipBook styles, with the atlas ants overlay and
    -- ABG's halo), stealable (the Blizzard Border texture). Pass a file-scope
    -- constant. w, h stay for call compatibility (creation needs no size).
    -- Repeat calls are free: each family's data table appears only once its
    -- regions exist.
    function G.PrewarmEngineHost(wrapper, w, h, need)
        if not wrapper then return end
        if not need or need.ants then _EnsureAnimAnts(wrapper) end
        if not need or need.flip then _EnsureFlip(wrapper, true, true) end
        if not need or need.stealable then G.EnsureStealableBorder(wrapper) end
    end
end

