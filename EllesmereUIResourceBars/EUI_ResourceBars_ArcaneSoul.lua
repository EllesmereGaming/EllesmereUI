if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_ResourceBars_ArcaneSoul.lua
-- 12.1 ONLY: engine-slot driver for the Sunfury Arcane Mage "Arcane Soul" callout.
--
-- Arcane Soul (451038) is a fixed 4s buff granted the instant Arcane Surge
-- (buff 365362) ends -- but Surge's own length is NOT fixed: Savor the Moment adds
-- 0.8s per Spellfire Sphere held at cast time, and that sphere count is a
-- secret value the moment you pull. Predicting the window from the CAST (what
-- the reference helper addons do) is therefore wrong by up to 2.4s.
--
-- So this tracks the LIVE Arcane Surge buff, whose remaining duration already
-- carries the sphere bonus -- and never reads it. Two hidden one-slot aura
-- containers on the player (includeSpellIDs -- helpful-on-self passes the
-- identity gate regardless of secrecy) whose slot subtrees ARE the display:
-- the button shows only while its aura is up, and a bound FontString renders
-- the countdown through a NumericRuleFormatter evaluated C-side. Exact in
-- restricted content, and zero Lua per frame -- no OnUpdate, no polling, no
-- duration ever crossing into Lua.
--
-- Two containers rather than one two-slot container: AddAuraSlot has no
-- per-slot layout override, so a shared container would lay the slots out
-- side by side. The buffs can never overlap, so both slot buttons simply
-- SetAllPoints the one movable proxy (the EbonMight121-proven shape) and only
-- ever one of them is visible.
--
-- Everything the display does beyond "show remaining" is a formatter
-- breakpoint, because the subtree is denied to addon code after creation:
-- the "hide until the last N seconds" rule is an empty format above the
-- threshold, the GCD counter is a components div by the GCD length, and the
-- final-Barrage "LAST" is a literal band below one GCD. Colors ride a Step
-- ColorCurve on the same registration, which doubles as the belt-and-braces
-- hide (alpha 0 above the threshold) if the empty format is ever rejected.

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

-- Arcane Surge splits cast id from aura id, exactly like Ebon Might (395152 ->
-- 395296, which EUI_ResourceBars_EbonMight121 tracks by the AURA id). The suite
-- already records the pair in EllesmereUI_BuffPresets: [365350] = { class =
-- "MAGE", alts = { 365362 } }. UNIT_SPELLCAST_SUCCEEDED reports the CAST id;
-- the buff that lands on the player is the ALT. Both go in the slot's candidate
-- set the way BmIncludeMap folds a preset's alts into one slot -- an id that
-- never appears as a player buff simply never matches.
local SURGE_CAST_ID   = 365350  -- Arcane Surge, the castable ability
local SURGE_AURA_ID   = 365362  -- Arcane Surge, the buff it applies
local SOUL_AURA_ID    = 451038  -- Arcane Soul (fixed 4s, granted when Surge ends)
local ARCANE_SPEC_ID  = 62
local SUNFURY_TREE_ID = 39      -- C_ClassTalents.GetActiveHeroTalentSpec()
local GCD_SPELL_ID    = 61304
local STYLE_KEY       = "erb:arcsoul121"
local UNLOCK_KEY      = "EUI_ArcaneSoul"

local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = -150 }

-- proxy, built, queued, gcdLen, dirty, fsErr, ev/evCast, sample, class;
-- ph[phase] = { container, btn, fs, stamp }
local S = { ph = { surge = {}, soul = {} } }
S.class = select(2, UnitClass("player"))

-------------------------------------------------------------------------------
--  Settings access
-------------------------------------------------------------------------------

local function P()
    local ERB = ns.ERB
    local db = ERB and ERB.db
    local p = db and db.profile
    return p and p.arcaneSoul or nil
end

-- countMode is one stored key so the options page keeps one dropdown, but the
-- two phases resolve their display independently:
--   "seconds"    -> tenths of a second in both phases
--   "gcd"        -> whole GCDs in both (Barrage count + LAST inside Soul)
--   "secondsGcd" -> tenths counting down to the window, Barrage count inside it
-- Counting GCDs before the window opens and counting Barrages inside it are
-- different questions, so they are separately answerable.
local function PhaseMode(phase)
    local p = P()
    local m = p and p.countMode
    if m == "gcd" then return "gcd" end
    if m == "secondsGcd" then return (phase == "soul") and "gcd" or "seconds" end
    return "seconds"
end

-- Does any phase need a GCD length? Drives the one combat event this module
-- registers, so a pure-seconds setup stays event-free in combat.
local function NeedsGcd()
    local p = P()
    local m = p and p.countMode
    return m == "gcd" or m == "secondsGcd"
end

-- Seconds of Arcane Surge left at which "Soul in" starts showing. Floor 1,
-- never 0: a 0 threshold would collide with the tenths breakpoint at 0.
local function Thr()
    local p = P()
    local v = tonumber(p and p.threshold) or 5
    if v < 1 then v = 1 elseif v > 15 then v = 15 end
    return math.floor(v + 0.5)
end

local function TextSize()
    local p = P()
    local v = tonumber(p and p.textSize) or 24
    if v < 10 then v = 10 elseif v > 48 then v = 48 end
    return math.floor(v + 0.5)
end

local function ProxySize()
    local sz = TextSize()
    return math.max(80, sz * 6), math.max(20, math.floor(sz * 1.6))
end

local function PreColor()
    local p = P() or {}
    return p.preR or 0.64, p.preG or 0.21, p.preB or 0.93
end

local function SoulColor()
    local p = P() or {}
    return p.soulR or 0.64, p.soulG or 0.21, p.soulB or 0.93
end

local function LastColor()
    local p = P() or {}
    return p.lastR or 1.0, p.lastG or 0.25, p.lastB or 0.25
end

-------------------------------------------------------------------------------
--  Fonts -- the Battle Res text pattern: "__global" follows the EUI Fonts &
--  Colors defaults, a named key resolves through the shared font registry, and
--  outline overrides stay slug-gated. Key is "resourceBars" (this module's own
--  entry in _addonKeyToFolder), so a per-module font override applies here too.
-------------------------------------------------------------------------------

local function GetASFont()
    local p = P()
    local key = (p and p.font) or "__global"
    if key ~= "__global" and EllesmereUI and EllesmereUI.ResolveFontName then
        local path = EllesmereUI.ResolveFontName(key)
        if path then return path end
    end
    return (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("resourceBars"))
        or STANDARD_TEXT_FONT
end

local function GetASOutline()
    local p = P()
    local mode = (p and p.outlineMode) or "__global"
    if mode == "outline" then
        return (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
    end
    if mode == "thick" then
        return (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("THICKOUTLINE, SLUG")) or "THICKOUTLINE, SLUG"
    end
    if mode == "none" then return "" end
    return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("resourceBars"))
        or (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
end

-- Empty flags = Drop Shadow mode, primed via FontObject (instance shadow
-- setters do not render). The primed object resolves BLACK, so the instance
-- color is always re-stated afterwards -- it is also the fallback tint if the
-- engine ever refuses the color curve.
local function ApplyFsLook(phase, fs)
    if not fs then return end
    local flags = GetASOutline()
    if EllesmereUI and EllesmereUI.PrimeFontShadow then
        EllesmereUI.PrimeFontShadow(fs, flags == "")
    end
    fs:SetFont(GetASFont(), TextSize(), flags)
    local r, g, b
    if phase == "soul" then r, g, b = SoulColor() else r, g, b = PreColor() end
    fs:SetTextColor(r, g, b, 1)
end

-------------------------------------------------------------------------------
--  GCD length -- a PLAIN NUMBER, used only to build breakpoints and curve
--  points. Never compared against anything the engine owns.
--
--  The live cooldown first: the one moment this matters is the Arcane Surge
--  cast, which starts a GCD, so the client's own number carries every haste
--  buff that is currently up. It is secret in restricted combat, hence the
--  issecretvalue guard (captureGCD's pattern); the haste formula is the
--  fallback (ns.GCDTailAlpha's pattern), then the last known value, then the
--  unhasted 1.5.
-------------------------------------------------------------------------------

local function ReadLiveGcd()
    local cd = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(GCD_SPELL_ID)
    local d = cd and cd.duration
    if d == nil then return nil end
    if issecretvalue and issecretvalue(d) then return nil end
    if type(d) ~= "number" then return nil end
    -- duration only means anything while the cooldown runs; idle it reports 0.
    if d >= 0.7 and d <= 1.6 then return d end
    return nil
end

local function ReadHasteGcd()
    local haste = UnitSpellHaste and UnitSpellHaste("player")
    if haste == nil then return nil end
    if issecretvalue and issecretvalue(haste) then return nil end
    if type(haste) ~= "number" then return nil end
    return 1.5 / (1 + haste / 100)
end

local function GetGcdLen()
    local ok, len = pcall(ReadLiveGcd)
    if not ok then len = nil end
    if not len then
        local ok2, hasted = pcall(ReadHasteGcd)
        if ok2 then len = hasted end
    end
    if not len then len = S.gcdLen or 1.5 end
    if len < 0.75 then len = 0.75 elseif len > 1.6 then len = 1.6 end -- engine floor / unhasted cap
    len = math.floor(len * 100 + 0.5) / 100  -- bounds the formatter and curve caches
    S.gcdLen = len
    return len
end

-------------------------------------------------------------------------------
--  Formatters
--
--  Schema per the field-proven CDM/AuraKit tables: step and rounding live at
--  the BREAKPOINT level, components carry only the divisor, and a breakpoint
--  owns every value at or above its threshold. Thresholds are always in
--  SECONDS -- components change the displayed number, not the banding.
--
--  Two shapes here are novel for this codebase and so are attempted in
--  descending order with pcall on every SetBreakpoints: a format with a
--  LITERAL PREFIX ("Soul in %.1f") and a format with NO conversion at all
--  ("" to hide, "LAST" to warn). Each degrades to something still useful.
-------------------------------------------------------------------------------

local function NewFormatter(points)
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum and Enum.NumericRuleFormatRounding) then
        return nil
    end
    local f = C_StringUtil.CreateNumericRuleFormatter()
    if not pcall(f.SetBreakpoints, f, points) then return nil end
    return f
end

-- Whole-GCD counting is laid out as one explicit band per GCD rather than
-- through a components divisor. Every proven divisor in this suite is an
-- INTEGER (60, 3600, 86400); a GCD is fractional (1.25s at raid haste), and a
-- fractional div is accepted by the validator and then ignored, which renders
-- the raw seconds instead of the count -- indistinguishable from "the counter
-- shows whole seconds". Bands need no divisor at all: band N owns
-- [ (N-1)*gcd, N*gcd ), which is exactly ceil(remaining / gcd). The epsilon
-- keeps the boundary off the band edge so an exact multiple of the GCD counts
-- as the lower band (a press landing precisely as the window shuts does not
-- land). The divisor form is kept as a fallback for the day divs go fractional.
local BAND_EPS = 0.0001
local BAND_MAX = 24

local function GcdBandPoints(prefix, gcd, upTo, firstLabel)
    local pts = {}
    for n = 1, BAND_MAX do
        local t = (n == 1) and 0 or ((n - 1) * gcd + BAND_EPS)
        if n > 1 and t >= upTo then break end
        pts[#pts + 1] = { threshold = t, format = (n == 1 and firstLabel) or (prefix .. n) }
    end
    return pts
end

-- Arcane Surge phase: nothing at all until `thr` seconds remain, then the
-- countdown to the Soul window. Attempts run best-first and each is retried
-- with hide rules "" then " " then none -- a formatter with no hide rule still
-- hides above the threshold via the alpha-0 color curve. The last attempt is
-- always TENTHS OF SECONDS, never the engine default: a formatter that fails
-- to build leaves SetDurationText with no formatter at all, and the engine
-- default renders bare whole seconds.
local surgeFmtCache = {}
local function SurgeFormatter(mode, thr, gcd)
    local key = mode .. "|" .. thr .. "|" .. tostring(gcd or 0)
    local cached = surgeFmtCache[key]
    if cached ~= nil then return cached or nil end

    local Up   = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up
    local Down = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Down
    local attempts
    if mode == "gcd" then
        attempts = {
            GcdBandPoints("Soul in ", gcd, thr, "Soul in 1"),
            { { threshold = 0, format = "Soul in %d", step = 1, rounding = Up, components = { { div = gcd } } } },
            { { threshold = 0, format = "Soul in %.1f", step = 0.1, rounding = Down } },
            { { threshold = 0, format = "%.1f", step = 0.1, rounding = Down } },
        }
    else
        attempts = {
            { { threshold = 0, format = "Soul in %.1f", step = 0.1, rounding = Down } },
            { { threshold = 0, format = "%.1f", step = 0.1, rounding = Down } },
        }
    end
    local hides = { "", " ", false }

    for a = 1, #attempts do
        local base = attempts[a]
        for h = 1, #hides do
            local points = {}
            for i = 1, #base do points[i] = base[i] end
            -- Every band sits strictly below thr (GcdBandPoints stops there),
            -- so the hide rule always lands last and never duplicates a threshold.
            if hides[h] then points[#points + 1] = { threshold = thr, format = hides[h] } end
            local f = NewFormatter(points)
            if f then
                surgeFmtCache[key] = f
                return f
            end
        end
    end
    surgeFmtCache[key] = false
    return nil
end

-- Arcane Soul phase: seconds left, or the number of Arcane Barrages that still
-- fit. Barrage is instant and GCD-capped, so that count is ceil(remaining/gcd),
-- and the final one is the "do not cast another" warning. Soul is a fixed 4s;
-- the band table is generated a little past that for headroom.
local SOUL_BAND_MAX_S = 6
local soulFmtCache = {}
local function SoulFormatter(mode, gcd)
    local key = mode .. "|" .. tostring(gcd or 0)
    local cached = soulFmtCache[key]
    if cached ~= nil then return cached or nil end

    local Up   = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Up
    local Down = Enum and Enum.NumericRuleFormatRounding and Enum.NumericRuleFormatRounding.Down
    local f
    if mode == "gcd" then
        f = NewFormatter(GcdBandPoints("", gcd, SOUL_BAND_MAX_S, "LAST"))
        if not f then
            -- Divisor fallback. If the literal-only "LAST" band is what was
            -- refused, the same ceil renders a "1" there instead -- still red,
            -- because the color flip rides the curve, not the text.
            local count = { threshold = gcd + BAND_EPS, format = "%d", step = 1, rounding = Up,
                components = { { div = gcd } } }
            f = NewFormatter({ { threshold = 0, format = "LAST" }, count })
                or NewFormatter({
                    { threshold = 0, format = "%d", step = 1, rounding = Up, components = { { div = gcd } } },
                    count,
                })
        end
    end
    if not f then
        f = NewFormatter({ { threshold = 0, format = "%.1f", step = 0.1, rounding = Down } })
    end
    soulFmtCache[key] = f or false
    return f
end

-------------------------------------------------------------------------------
--  Color curves. Step type: a point owns every value from its position up to
--  the next one, so the bands line up exactly with the formatter's.
-------------------------------------------------------------------------------

-- Colors bake in at AddPoint time, so a curve exists per distinct color set.
-- Dragging a colour picker walks through hundreds of them, so the cache is
-- bounded rather than unbounded-but-small: past the cap it starts over, and
-- the settled color is rebuilt once on the next apply.
local CURVE_CACHE_MAX = 64
local curveCache, curveCacheN = {}, 0
local curvePts
local function BuildCurve()
    local c = C_CurveUtil.CreateColorCurve()
    c:SetType(Enum.LuaCurveType.Step)
    for i = 1, #curvePts do
        local pt = curvePts[i]
        c:AddPoint(pt[1], CreateColor(pt[2], pt[3], pt[4], pt[5]))
    end
    return c
end

local function StepCurve(key, points)
    local cached = curveCache[key]
    if cached ~= nil then return cached or nil end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType) then
        curveCache[key] = false
        return nil
    end
    curvePts = points
    local ok, curve = pcall(BuildCurve)
    curvePts = nil
    if not ok or not curve then
        curveCache[key] = false
        return nil
    end
    if curveCacheN >= CURVE_CACHE_MAX then
        curveCache, curveCacheN = {}, 0
    end
    curveCache[key] = curve
    curveCacheN = curveCacheN + 1
    return curve
end

-- Visible below the threshold, alpha 0 above it: the second, independent hide
-- for the pre-Soul text (the formatter's empty-format rule is the first).
local function SurgeCurve(thr)
    local r, g, b = PreColor()
    local key = string.format("s|%d|%.3f|%.3f|%.3f", thr, r, g, b)
    return StepCurve(key, { { 0, r, g, b, 1 }, { thr, r, g, b, 0 } })
end

-- Seconds mode is one flat color; GCD mode flips to the Last color for the
-- final Barrage. Two points either way -- a one-point curve has no band.
local function SoulCurve(mode, gcd)
    local sr, sg, sb = SoulColor()
    if mode ~= "gcd" then
        local key = string.format("c|%.3f|%.3f|%.3f", sr, sg, sb)
        return StepCurve(key, { { 0, sr, sg, sb, 1 }, { 60, sr, sg, sb, 1 } })
    end
    local lr, lg, lb = LastColor()
    local key = string.format("l|%.2f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f", gcd, sr, sg, sb, lr, lg, lb)
    return StepCurve(key, { { 0, lr, lg, lb, 1 }, { gcd + 0.0001, sr, sg, sb, 1 } })
end

-------------------------------------------------------------------------------
--  Duration-text binding
--
--  SetDurationText is a button call, so it is denied while auras are secret.
--  Every attempt is stamped only on a COMPLETE landing (BmRebindDurationCurve's
--  rule): a denied or color-stripped registration leaves the stamp alone and
--  raises S.dirty, so the restriction-lift drain re-runs it. Until then the
--  previously bound formatter keeps rendering -- stale banding, still correct
--  time, which is the accepted degradation.
-------------------------------------------------------------------------------

local function StampFor(phase, mode, thr, gcd)
    if phase == "surge" then
        local r, g, b = PreColor()
        return string.format("%s|%d|%.2f|%.3f|%.3f|%.3f", mode, thr, gcd or 0, r, g, b)
    end
    local sr, sg, sb = SoulColor()
    local lr, lg, lb = LastColor()
    return string.format("%s|%.2f|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f",
        mode, gcd or 0, sr, sg, sb, lr, lg, lb)
end

local function BindPhase(phase, force)
    local AK = EllesmereUI.AuraKit
    local st = S.ph[phase]
    if not (AK and st.btn and st.fs) then return end

    local mode = PhaseMode(phase)
    local thr = Thr()
    local gcd = (mode == "gcd") and GetGcdLen() or nil
    local stamp = StampFor(phase, mode, thr, gcd)
    if not force and st.stamp == stamp then return end

    local fmt, curve
    if phase == "surge" then
        fmt, curve = SurgeFormatter(mode, thr, gcd), SurgeCurve(thr)
    else
        fmt, curve = SoulFormatter(mode, gcd), SoulCurve(mode, gcd)
    end

    local ok, full = AK.SetDurationTextSafe(st.btn, st.fs, AK.BuildDurationTextOpts(fmt, curve))
    if ok and (full or not curve) then
        st.stamp = stamp
    else
        st.stamp = nil
        S.dirty = true
    end
end

-------------------------------------------------------------------------------
--  Build
-------------------------------------------------------------------------------

local function EnsureProxy()
    if S.proxy then return end
    S.proxy = CreateFrame("Frame", nil, UIParent)
    S.proxy:SetSize(ProxySize())
    S.proxy:Hide()
end

local SURGE_INCLUDE = { [SURGE_AURA_ID] = true, [SURGE_CAST_ID] = true }
local SOUL_INCLUDE  = { [SOUL_AURA_ID] = true }

local function BuildPhase(phase, include)
    local AK = EllesmereUI.AuraKit
    local st = S.ph[phase]
    if st.container then return end

    local container = AK.CreateContainerShell(S.proxy, { point = { "CENTER" } })
    AK.AddSlotToContainer(container, {
        key = phase,
        filter = { "HELPFUL" },
        candidateFilters = { includeSpellIDs = include },
        style = STYLE_KEY,
        extraInit = function(button)
            -- Creation window: the only legal moment to touch this subtree.
            -- Two-point anchoring sizes the button by anchors forever; all
            -- repositioning after this is proxy moves.
            button:SetAllPoints(S.proxy)
            -- Display-only overlay with no OnClick: an engine aura button comes
            -- mouse-enabled, and clicks alone would make it an invisible blocker
            -- over its whole rect for as long as the buff is up.
            if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
            if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
            st.btn = button

            -- ARMORED: an uncaught error here aborts the engine's
            -- CreateFrameBatch and kills the slot. Failures land in S.fsErr.
            local okFS, errFS = pcall(function()
                local tc = CreateFrame("Frame", nil, button)
                tc:SetAllPoints(button)
                tc:SetFrameLevel(button:GetFrameLevel() + 5)
                local fs = tc:CreateFontString(nil, "OVERLAY")
                -- Font BEFORE registration (the engine SetText()s every
                -- registered string; an unfonted FontString hard-errors).
                ApplyFsLook(phase, fs)
                fs:SetPoint("CENTER", button, "CENTER", 0, 0)
                st.fs = fs
                BindPhase(phase, true)
            end)
            if not okFS then S.fsErr = errFS end

        end,
    })
    AK.FinishContainer(container, "player")
    -- One container-level set lifts the whole engine subtree above the proxy.
    container:SetFrameLevel(S.proxy:GetFrameLevel() + 1)
    st.container = container
end

-- POSITION ONLY. Unlock mode owns the frame's placement for as long as the
-- mover is up, and GetBarFrame -> elem.getFrame runs on every drag frame, so
-- this must never be reachable from getFrame: re-anchoring there yanks the
-- frame the player is dragging straight back to the stored position. Only
-- applyPos and ordinary (non-unlock) applies call it. Same split as the Target
-- Distance element, whose getFrame deliberately skips ApplyFrameSettings.
local function ApplyPosition()
    if not S.proxy then return end
    -- Anchored to another element: the unlock anchor system owns placement;
    -- re-applying the stored absolute here would slam the frame back to a
    -- stale spot on every apply (same guard as the GCD / totem bars).
    local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(UNLOCK_KEY)
    if anchored and S.proxy:GetLeft() then return end

    local p = P()
    local pos = (p and p.unlockPos) or DEFAULT_POS
    local pt = pos.point or "CENTER"
    local px, py = pos.x or 0, pos.y or 0
    local PPa = EllesmereUI and EllesmereUI.PP
    if PPa then
        local es = S.proxy:GetEffectiveScale()
        -- CENTER anchor with stored CENTER offsets: SnapCenterForDim gives
        -- odd-pixel-dim frames the +0.5 offset that lands edges on whole pixels.
        local isCenterAnchor = (pt == "CENTER") and (pos.relPoint == "CENTER" or pos.relPoint == nil)
        if isCenterAnchor and PPa.SnapCenterForDim then
            px = PPa.SnapCenterForDim(px, S.proxy:GetWidth() or 0, es)
            py = PPa.SnapCenterForDim(py, S.proxy:GetHeight() or 0, es)
        elseif PPa.SnapForES then
            px = PPa.SnapForES(px, es)
            py = PPa.SnapForES(py, es)
        end
    end
    S.proxy:ClearAllPoints()
    S.proxy:SetPoint(pt, UIParent, pos.relPoint or pt, px, py)
end

-- LOOK ONLY: size, fonts, colors, duration bindings. Safe to run at any time,
-- including mid-drag.
local function ApplyLook()
    if not S.proxy then return end
    S.proxy:SetSize(ProxySize())

    -- Font/size/color live on OUR regions, but they are children of an engine
    -- aura button, so post-creation writes are denied under aura secrecy like
    -- any other write into that subtree: pcall and defer to the lift.
    for phase, st in pairs(S.ph) do
        if st.fs then
            if not pcall(ApplyFsLook, phase, st.fs) then S.dirty = true end
        end
        BindPhase(phase)
    end
end

local function ApplySettings()
    ApplyLook()
    ApplyPosition()
end

local function Build()
    local AK = EllesmereUI.AuraKit
    if S.built or not AK then return end
    AK.styles[STYLE_KEY] = AK.styles[STYLE_KEY]
        or { noRegions = true, width = 1, height = 1 }
    EnsureProxy()
    BuildPhase("surge", SURGE_INCLUDE)
    BuildPhase("soul", SOUL_INCLUDE)
    S.built = true

    -- Self-guarded dirty flag: lift callbacks are never unregistered, so an
    -- idle firing must cost one boolean test.
    if not S.liftHooked and AK.OnRestrictionLift then
        S.liftHooked = true
        AK.OnRestrictionLift(function()
            if not S.dirty then return end
            S.dirty = nil
            if ns.AS_Apply then ns.AS_Apply() end
        end)
    end
end

local function EnsureBuilt()
    if S.built or S.queued or S.buildErr then return end
    local AK = EllesmereUI.AuraKit
    if not (AK and AK.QueueBuildJob) then return end
    S.queued = true
    AK.QueueBuildJob(function()
        S.queued = nil
        -- Latched, not retried: every ERB:ApplyAll would otherwise re-enter a
        -- hard build failure and turn one broken container into an error storm.
        -- The display stays absent until a /reload; the reason sits in S.buildErr.
        local ok, err = pcall(Build)
        if not ok then
            S.buildErr = err
            return
        end
        ApplySettings()
    end, "erb:arcsoul-shell")
end

-------------------------------------------------------------------------------
--  Unlock-mode sample. Engine slots only render while their aura is up, so the
--  mover gets a plain sample string on the proxy -- our own frame, no engine
--  restrictions -- shown only while unlock mode is open.
-------------------------------------------------------------------------------

local function ShowSample()
    EnsureProxy()
    local fs = S.sample
    if not fs then
        fs = S.proxy:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("CENTER", S.proxy, "CENTER", 0, 0)
        S.sample = fs
    end
    local flags = GetASOutline()
    if EllesmereUI and EllesmereUI.PrimeFontShadow then
        EllesmereUI.PrimeFontShadow(fs, flags == "")
    end
    fs:SetFont(GetASFont(), TextSize(), flags)
    fs:SetTextColor(PreColor())
    fs:SetText(PhaseMode("surge") == "gcd" and "Soul in 3" or "Soul in 3.2")
    fs:Show()
    S.proxy:Show()
end

local function HideSample()
    if S.sample then S.sample:Hide() end
end

-------------------------------------------------------------------------------
--  Gating -- MAGE + Arcane + Sunfury. The hero-tree test only ever NARROWS:
--  an unreadable or absent answer falls through to the spec-only gate rather
--  than parking a display the player asked for.
-------------------------------------------------------------------------------

local function EnabledForClass()
    local p = P()
    return (p and p.enabled and S.class == "MAGE") and true or false
end

local function GateOK()
    if not EnabledForClass() then return false end
    -- Both spellings are live in this codebase (the options pages use the
    -- C_ namespace, the modules the globals); take whichever answers.
    local idx = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
        and C_SpecializationInfo.GetSpecialization())
        or (GetSpecialization and GetSpecialization())
    if not idx then return false end
    local specID = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
        and C_SpecializationInfo.GetSpecializationInfo(idx))
        or (GetSpecializationInfo and GetSpecializationInfo(idx))
    if specID ~= ARCANE_SPEC_ID then return false end
    if C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec then
        local ok, tree = pcall(C_ClassTalents.GetActiveHeroTalentSpec)
        if ok and type(tree) == "number" and tree ~= SUNFURY_TREE_ID then return false end
    end
    return true
end

local function Park()
    HideSample()
    if S.proxy then S.proxy:Hide() end
end

local function Activate()
    EnsureProxy()
    ApplyLook()
    -- Placement belongs to the mover while unlock mode is open (see ApplyPosition).
    if not (EllesmereUI and EllesmereUI._unlockActive) then ApplyPosition() end
    S.proxy:Show()
    if not S.built then EnsureBuilt() end
end

-------------------------------------------------------------------------------
--  Events -- registered only while the feature is on and the player is a Mage.
--  Seconds mode costs nothing in combat at all; GCD mode adds the one Surge
--  cast, which is where the GCD length is worth re-reading.
-------------------------------------------------------------------------------

local applyPending
local function RunPendingApply()
    applyPending = nil
    if ns.AS_Apply then ns.AS_Apply() end
end

-- Talent/loadout changes fire in a burst (a loadout swap applies many nodes at
-- once); coalesce into one gate re-evaluation.
local function ScheduleApply()
    if applyPending then return end
    applyPending = true
    C_Timer.After(0.1, RunPendingApply)
end

local function OnGateEvent(_, event, _, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if spellID ~= SURGE_CAST_ID then return end
        -- Rebind only on a genuine change: the deadband stops haste jitter from
        -- churning the formatter cache, and a denied rebind leaves the previous
        -- (still ticking) binding in place.
        local prev = S.gcdLen
        local len = GetGcdLen()
        if prev and len >= prev - 0.02 and len <= prev + 0.02 then
            S.gcdLen = prev
            return
        end
        BindPhase("surge")
        BindPhase("soul")
        return
    end
    ScheduleApply()
end

local function EnsureGateEvents()
    if not S.ev then
        S.ev = CreateFrame("Frame")
        S.ev:SetScript("OnEvent", OnGateEvent)
    end
    if not S.evGate then
        S.evGate = true
        S.ev:RegisterEvent("PLAYER_ENTERING_WORLD")
        S.ev:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        S.ev:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        S.ev:RegisterEvent("TRAIT_CONFIG_UPDATED")
    end
    local wantCast = NeedsGcd()
    if wantCast and not S.evCast then
        S.evCast = true
        S.ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    elseif not wantCast and S.evCast then
        S.evCast = nil
        S.ev:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end

local function DropGateEvents()
    if not S.ev then return end
    S.ev:UnregisterAllEvents()
    S.evGate, S.evCast = nil, nil
end

-------------------------------------------------------------------------------
--  Single entry point: called from ERB:ApplyAll (login, profile swap, every
--  options change) and from this module's own gate events.
-------------------------------------------------------------------------------

function ns.AS_Apply()
    if not EnabledForClass() then
        DropGateEvents()
        Park()
        return
    end
    EnsureGateEvents()
    if EllesmereUI and EllesmereUI._unlockActive then
        Activate()
        ShowSample()
        return
    end
    HideSample()
    if not GateOK() then
        Park()
        return
    end
    Activate()
end

-------------------------------------------------------------------------------
--  Unlock element
-------------------------------------------------------------------------------

function ns.AS_MakeUnlockElement(MK)
    if not MK or S.class ~= "MAGE" then return nil end

    if not S.unlockHooked and EllesmereUI and EllesmereUI.RegisterUnlockModeListener then
        S.unlockHooked = true
        EllesmereUI:RegisterUnlockModeListener(UNLOCK_KEY, function(active)
            if active then
                if EnabledForClass() then
                    Activate()
                    ShowSample()
                end
            else
                HideSample()
                if ns.AS_Apply then ns.AS_Apply() end
            end
        end)
    end

    return MK({
        key = UNLOCK_KEY, label = "Arcane Soul", group = "Resource Bars", order = 507,
        noResize = true,
        noAnchorTarget = true,
        isHidden = function() return not EnabledForClass() end,
        getFrame = function()
            if not EnabledForClass() then return nil end
            Activate()
            if EllesmereUI._unlockActive then ShowSample() end
            return S.proxy
        end,
        getSize = function() return ProxySize() end,
        savePos = function(_, point, relPoint, x, y)
            if not point then return end
            local p = P(); if not p then return end
            p.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
            if not EllesmereUI._unlockActive then ApplyPosition() end
        end,
        loadPos = function()
            local p = P()
            local pos = p and p.unlockPos
            if pos and pos.point then
                return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
            end
            return { point = DEFAULT_POS.point, relPoint = DEFAULT_POS.relPoint,
                x = DEFAULT_POS.x, y = DEFAULT_POS.y }
        end,
        clearPos = function()
            local p = P(); if p then p.unlockPos = nil end
            if S.proxy then ApplyPosition() end
        end,
        applyPos = function()
            if not EnabledForClass() then return end
            Activate()
            -- applyPos IS the "put it where it is stored" request, so it places
            -- unconditionally -- unlike getFrame/Activate above.
            ApplyPosition()
            if EllesmereUI._unlockActive then ShowSample() end
        end,
    })
end
