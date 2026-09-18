if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EllesmereUI_WarriorCharges.lua
-- 12.1 ONLY: engine-fed charge fills for the two Warrior class-resource buffs
-- the aura read surface refuses outright (not whitelisted: GetPlayerAuraBySpellID
-- answers nil WHILE the buff is visibly up, so no Lua path, plain or secret,
-- can ever hold the real count):
--   Fury - Whirlwind stacks (85739, max 4)
--   Arms - Sweeping Strikes charges (260708; 18 with Broad Strokes, else 12)
--
-- This REPLACED the old cast-count simulator (UNIT_SPELLCAST_SUCCEEDED
-- prediction plus range probes whose edges were unmeasurable). One-slot aura
-- containers (includeSpellIDs: helpful-on-self passes the identity gate
-- regardless of secrecy) register a slot-child StatusBar through
-- SetApplicationBar: the ENGINE writes the aura's true application count into
-- the bar on every apply / update / clear (a clear writes 0), C-side,
-- identical in and out of restricted content. No polling, no cast handlers,
-- no prediction: the fill IS the server count. Separator ticks over the fill
-- keep the segmented pip look.
--
-- MULTI-HOST: every display surface that shows these charges is a HOST with
-- its own proxy, containers and registered bars (one registered bar per slot
-- button), all consuming the exported _G._EWC table:
--   "erb" - ResourceBars class resource bar (adapter in
--           EUI_ResourceBars_WarriorCharges.lua)
--   "uf"  - Unit Frames player class power row (ns._WCUF_Sync adapter)
--   "np"  - Nameplates target-plate class power (ns._WCNP_* adapters)
-- This file lives in the PARENT addon so every consumer gets the feed no
-- matter which child addons are enabled. Until a host's deferred build lands
-- its row simply shows empty (sub-second, and combat-legal since 68914).
--
-- Same contract as the Ebon Might / Arcane Soul engine-slot drivers: the slot
-- subtree is styled INSIDE the creation window and denied to addon code
-- afterward (reads AND writes, even our own regions, while auras are secret
-- -- field-proven under /euidev), so fill texture/color/orientation changes
-- land on the next /reload; out of restriction a pcall'd live recolor works
-- and denied writes re-apply at the restriction lift. Separators and the
-- empty-cell strip live on OUR proxy and restyle live.

local EllesmereUI = _G.EllesmereUI

-- hosts[key] = { key, proxy, emptyTex, sepHost, seps = {}, armed (power key),
--   syncFrame/syncOpts, lastR/G/B/A, pendR/G/B/A, dirty,
--   ph[powerKey] = { container, btn, bar, bft, tc, fs, built, queued, err,
--                    textErr, regMax } }
local S = { hosts = {} }
S.class = select(2, UnitClass("player"))

local PHASES = {
    WHIRLWIND_STACKS = {
        maxApps = 4,
        -- Buff + cast ids folded like the Arcane Soul include set: an id that
        -- never appears as a player buff simply never matches.
        include = { [85739] = true, [190411] = true },
    },
    SWEEPING_STRIKES = {
        maxApps = 18, -- talent cap: 12 from the ability + 6 from Broad Strokes
        include = { [260708] = true },
    },
}

local function Host(key)
    local H = S.hosts[key]
    if not H then
        H = { key = key, ph = {}, seps = {} }
        S.hosts[key] = H
    end
    return H
end

-------------------------------------------------------------------------------
--  Talent-dependent caps
-------------------------------------------------------------------------------

local BROAD_STROKES = 1261049 -- Colossus Smash grants +6 charges when known

-- Effective registration max. Sweeping Strikes caps at 18 only with Broad
-- Strokes known; without it the buff can never exceed 12. IsSpellKnown is a
-- cheap C call and this runs only on Sync passes (login/spec/talent/settings
-- edges; every consumer coalesces trait bursts before reaching here), so no
-- memo.
local function EffectiveMaxApps(powerKey, cfg)
    if powerKey == "SWEEPING_STRIKES" then
        local sb = C_SpellBook
        if not (sb and sb.IsSpellKnown and sb.IsSpellKnown(BROAD_STROKES)) then
            return 12
        end
    end
    return cfg.maxApps
end

-------------------------------------------------------------------------------
--  Restriction-lift re-apply. Post-window writes into a slot subtree are
--  denied while auras are secret: every write is pcall'd, a denial marks the
--  host dirty, and ONE lift callback re-runs each dirty host's pending color
--  and Sync when the restriction actually ends.
-------------------------------------------------------------------------------

local HostRecolor -- forward (lift re-applies through it)
local HostSyncByKey -- forward

local function EnsureLift()
    if S.liftHooked then return end
    local AK = EllesmereUI.AuraKit
    if not (AK and AK.OnRestrictionLift) then return end
    S.liftHooked = true
    AK.OnRestrictionLift(function()
        for _, H in pairs(S.hosts) do
            if H.dirty then
                H.dirty = nil
                if H.armed and H.pendR then
                    local key = H.armed
                    local r, g, b, a = H.pendR, H.pendG, H.pendB, H.pendA
                    H.lastR = nil -- force the change gate open
                    HostRecolor(H, key, r, g, b, a)
                end
                if H.armed and H.syncFrame then
                    HostSyncByKey(H, H.syncFrame, H.armed, H.syncOpts)
                end
            end
        end
    end)
end

-- Change-gated live recolor (a few compares per call). The latest color is
-- always stashed as pend: the creation-window bake reads it (the only write
-- that always lands) and the lift re-applies it.
HostRecolor = function(H, powerKey, r, g, b, a)
    if H.armed ~= powerKey then return end
    H.pendR, H.pendG, H.pendB, H.pendA = r, g, b, a
    local st = H.ph[powerKey]
    local bft = st and st.bft
    if not bft then return end -- not built yet: stash only, no write to try
    if H.lastR == r and H.lastG == g and H.lastB == b and H.lastA == a then return end
    if pcall(bft.SetVertexColor, bft, r, g, b, a or 1) then
        H.lastR, H.lastG, H.lastB, H.lastA = r, g, b, a
    else
        H.dirty = true
        EnsureLift()
    end
end

-------------------------------------------------------------------------------
--  Container build (one slot per host+buff, engine-owned end to end)
-------------------------------------------------------------------------------

local function BuildHostPhase(H, powerKey, opts)
    local AK = EllesmereUI.AuraKit
    local cfg = PHASES[powerKey]
    local st = H.ph[powerKey]
    if st.container then return end

    local styleKey = "war:" .. H.key .. ":" .. powerKey
    AK.styles[styleKey] = AK.styles[styleKey]
        or { noRegions = true, width = 1, height = 1 }
    if not H.proxy then
        H.proxy = CreateFrame("Frame", nil, UIParent)
        H.proxy:Hide()
    end

    -- Bake the fill's look now: the subtree is denied to addon code after the
    -- creation window (under restriction that denial covers even our own
    -- regions, so this is the ONLY color write that always lands). The host's
    -- consumer stashes its fully resolved color into H.pend* before the
    -- queued job runs; opts colors are the belt for a job that outruns it.
    local maxApps = EffectiveMaxApps(powerKey, cfg)
    local texPath = opts.texPath or "Interface\\Buttons\\WHITE8x8"
    local r = H.pendR or opts.r or 1
    local g = H.pendG or opts.g or 1
    local b = H.pendB or opts.b or 1
    local a = (H.pendR and (H.pendA or 1)) or opts.a or 1
    local fillAlpha = opts.fillAlpha or 1
    local ori = opts.ori or "HORIZONTAL"

    local container = AK.CreateContainerShell(H.proxy, { point = { "CENTER" } })
    AK.AddSlotToContainer(container, {
        key = powerKey,
        filter = { "HELPFUL" },
        candidateFilters = { includeSpellIDs = cfg.include },
        style = styleKey,
        extraInit = function(button)
            -- Creation window: the only legal moment to touch this subtree.
            -- Two-point anchoring sizes the button by anchors forever; all
            -- repositioning after this is proxy moves.
            button:SetAllPoints(H.proxy)
            -- Display-only overlay: an engine aura button comes mouse-enabled,
            -- and clicks alone would make it an invisible blocker over the
            -- host's row for as long as the buff is up.
            if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
            if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
            st.btn = button

            local bar = CreateFrame("StatusBar", nil, button)
            bar:SetAllPoints(button)
            if ori == "HORIZONTAL" then
                bar:SetOrientation("HORIZONTAL")
            else
                -- Legacy pip rows fill top-down unless VERTICAL_UP reverses.
                bar:SetOrientation("VERTICAL")
                bar:SetReverseFill(ori ~= "VERTICAL_UP")
            end
            bar:SetStatusBarTexture(texPath)
            local bft = bar:GetStatusBarTexture()
            if bft then
                bft:SetVertexColor(r, g, b, a)
                if fillAlpha < 1 then bft:SetAlpha(fillAlpha) end
            end
            -- ARMORED: an uncaught error here aborts the engine's
            -- CreateFrameBatch and kills the slot; failures land in st.err and
            -- the host's row stays empty for the session.
            local ok, err = pcall(function()
                local barOpts = { maxApplications = maxApps }
                if Enum.StatusBarInterpolation then
                    barOpts.interpolation = Enum.StatusBarInterpolation.Immediate
                end
                button:SetApplicationBar(bar, barOpts)
            end)
            if not ok then st.err = err; return end
            st.bar = bar
            st.bft = bft
            st.regMax = maxApps

            -- Threshold apparatus, baked IN-WINDOW (the only moment subtree
            -- creation is always legal): one mask riding the fill texture's
            -- rect (SetAllPoints here, NEVER re-anchored -- an outside mask
            -- SetPoint'ing to bft is denied as a forbidden-aspect dependent,
            -- field-proven) plus five generic strip textures (settings cap
            -- thresholds at 5), hidden until styled. Post-window styling
            -- (position/color/shown) is plain-texture work: legal while
            -- unrestricted, pcall'd with a lift re-apply under restriction.
            -- ARTWORK on the bar draws above the fill; the separator ticks
            -- live at +4 above all of it.
            st.thMask = bar:CreateMaskTexture()
            st.thMask:SetTexture("Interface\\Buttons\\WHITE8x8",
                "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
            st.thMask:SetAllPoints(bft)
            st.thStrips = {}
            for i = 1, 5 do
                -- Sublevels +1..+5: the StatusBar fill texture draws at
                -- ARTWORK sublevel 0, and strips below it never render
                -- (field-proven). Ticks stay above on the +4 sepHost frame.
                local strip = bar:CreateTexture(nil, "ARTWORK", nil, i)
                strip:AddMaskTexture(st.thMask)
                strip:Hide()
                st.thStrips[i] = strip
            end

            -- Count text (opt-in per host): engine-stamped true count via
            -- SetApplicationCount. Look baked from the host's live count
            -- fontstring when one exists by job time, else the opts fields.
            -- The formatter makes every value render ("%d" from 0 up);
            -- without it the engine only shows counts above 1.
            if opts.text then
                local okT, errT = pcall(function()
                    local tc = CreateFrame("Frame", nil, button)
                    tc:SetAllPoints(button)
                    tc:SetFrameLevel(button:GetFrameLevel() + 6)
                    local fs = tc:CreateFontString(nil, "OVERLAY")
                    local lc = opts.text.fontFrom
                    local f, sz, fl
                    if lc and lc.GetFont then f, sz, fl = lc:GetFont() end
                    if f then
                        fs:SetFont(f, sz, fl)
                    else
                        fs:SetFont("Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF", 12, "OUTLINE")
                    end
                    fs:SetTextColor(opts.text.r or 1, opts.text.g or 1, opts.text.b or 1, 0.9)
                    local anchor = opts.text.anchor or "CENTER"
                    fs:SetPoint(anchor, button, anchor, opts.text.x or 0, opts.text.y or 0)
                    local fmt
                    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
                       and Enum.NumericRuleFormatRounding then
                        local nf = C_StringUtil.CreateNumericRuleFormatter()
                        local okB = pcall(nf.SetBreakpoints, nf, {
                            { threshold = 0, format = "%d", step = 1,
                              rounding = Enum.NumericRuleFormatRounding.Down },
                        })
                        if okB then fmt = nf end
                    end
                    button:SetApplicationCount(fs, fmt and { formatter = fmt } or nil)
                    st.tc, st.fs = tc, fs
                    tc:SetShown(opts.text.shown and true or false)
                end)
                if not okT then st.textErr = errT end
            end
        end,
    })
    AK.FinishContainer(container, "player")
    st.container = container
    st.built = true
end

local function EnsureHostBuilt(H, powerKey, opts)
    local st = H.ph[powerKey]
    if not st then st = {}; H.ph[powerKey] = st end
    if st.built or st.queued or st.err then return end
    local AK = EllesmereUI.AuraKit
    if not (AK and AK.QueueBuildJob) then return end
    st.queued = true
    AK.QueueBuildJob(function()
        st.queued = nil
        -- Latched, not retried: a hard build failure must not re-enter on
        -- every consumer pass and turn one broken container into a storm.
        local ok, err = pcall(BuildHostPhase, H, powerKey, opts)
        if not ok then st.err = err; return end
        -- The build was deferred past the Sync that requested it: re-run the
        -- attach with the stored sync args.
        if H.armed == powerKey and H.syncFrame then
            HostSyncByKey(H, H.syncFrame, powerKey, H.syncOpts)
        end
    end, "war:" .. H.key .. ":" .. powerKey)
end

-------------------------------------------------------------------------------
--  Separator ticks + empty-cell strip (ours, restyle live): keep the
--  segmented pip look over the one continuous engine fill. Integer counts
--  land exactly on the boundaries.
-------------------------------------------------------------------------------

local function StyleSeparators(H, frame, sp, n)
    if not H.sepHost then
        H.sepHost = CreateFrame("Frame", nil, H.proxy)
        H.sepHost:SetAllPoints(H.proxy)
    end
    local sep = sp.sep or {}
    -- Color: an explicit sep color from the host, else the legacy gap-strip
    -- chain (explicit gap color > opaque black in dark theme > bar bg color).
    local r, g, b, a
    if sep.r then
        r, g, b, a = sep.r, sep.g or 0, sep.b or 0, sep.a or 1
    elseif sp.gapColorEnabled then
        r, g, b, a = sp.gapR or 0, sp.gapG or 0, sp.gapB or 0, sp.gapA or 1
    elseif sp.darkTheme then
        r, g, b, a = 0, 0, 0, 1
    else
        r, g, b, a = sp.barBgR or 0, sp.barBgG or 0, sp.barBgB or 0, sp.barBgA or 0.5
    end
    local ori = sp.pipOrientation or "HORIZONTAL"
    local vertical = ori ~= "HORIZONTAL"
    local PP = EllesmereUI.PP
    local es = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    local sepW = sep.w or sp.pipSpacing or 1
    if PP and PP.SnapForES then sepW = PP.SnapForES(sepW, es) end
    if sepW <= 0 then sepW = 1 end
    local len = (vertical and frame:GetHeight() or frame:GetWidth()) or 0

    -- Optional empty-cell strip UNDER the engine fill (hosts whose legacy
    -- pips carry an "empty" color rather than relying on the row backdrop).
    -- Proxy-level texture: children (the engine container) render above it.
    if sep.empty then
        if not H.emptyTex then
            H.emptyTex = H.proxy:CreateTexture(nil, "BACKGROUND")
        end
        local inset = sep.emptyInset or 0
        H.emptyTex:ClearAllPoints()
        if vertical then
            H.emptyTex:SetPoint("TOPLEFT", H.proxy, "TOPLEFT", 0, -inset)
            H.emptyTex:SetPoint("BOTTOMRIGHT", H.proxy, "BOTTOMRIGHT", 0, inset)
        else
            H.emptyTex:SetPoint("TOPLEFT", H.proxy, "TOPLEFT", inset, 0)
            H.emptyTex:SetPoint("BOTTOMRIGHT", H.proxy, "BOTTOMRIGHT", -inset, 0)
        end
        H.emptyTex:SetColorTexture(sep.empty.r or 0.2, sep.empty.g or 0.2,
            sep.empty.b or 0.2, sep.empty.a or 1)
        H.emptyTex:Show()
    elseif H.emptyTex then
        H.emptyTex:Hide()
    end

    -- Boundary positions. Parametric cell geometry when the host supplies it
    -- (fixed stride, or the stretch-to-width layout); uniform fractions
    -- otherwise (the near-uniform ERB slot layout).
    local function BoundaryPos(i)
        if sep.stretch and sep.stretch > 0 then
            local gapPx = sep.gap or 0
            local basePipW = (sep.stretch - (n - 1) * gapPx) / n
            return i * (basePipW + gapPx) - gapPx / 2
        elseif sep.cellW then
            local pad = sep.pad or 0
            local gapPx = sep.gap or 0
            return pad / 2 + i * (sep.cellW + gapPx) - gapPx / 2
        end
        return len * i / n
    end

    for i = 1, n - 1 do
        local t = H.seps[i]
        if not t then
            t = H.sepHost:CreateTexture(nil, "ARTWORK")
            H.seps[i] = t
        end
        t:SetColorTexture(r, g, b, a)
        t:ClearAllPoints()
        -- Snap the tick's EDGE offset, not just the boundary center: a
        -- half-pixel-offset 1px line can disappear into the pixel grid.
        local off = BoundaryPos(i) - sepW / 2
        if PP and PP.SnapForES then off = PP.SnapForES(off, es) end
        if vertical then
            -- Fill runs top-down (or bottom-up for VERTICAL_UP); either way
            -- the boundaries sit at the same fractions from the fill edge.
            t:SetPoint("LEFT", H.sepHost, "LEFT", 0, 0)
            t:SetPoint("RIGHT", H.sepHost, "RIGHT", 0, 0)
            if ori == "VERTICAL_UP" then
                t:SetPoint("BOTTOM", H.sepHost, "BOTTOM", 0, off)
            else
                t:SetPoint("TOP", H.sepHost, "TOP", 0, -off)
            end
            t:SetHeight(sepW)
        else
            t:SetPoint("TOP", H.sepHost, "TOP", 0, 0)
            t:SetPoint("BOTTOM", H.sepHost, "BOTTOM", 0, 0)
            t:SetPoint("LEFT", H.sepHost, "LEFT", off, 0)
            t:SetWidth(sepW)
        end
        t:Show()
    end
    for i = n, #H.seps do H.seps[i]:Hide() end
end

-------------------------------------------------------------------------------
--  Threshold strips (proxy-side, engine-driven): threshold/band coloring with
--  ZERO Lua count reads. A static color strip spans [start-1, cap] of the
--  row; a mask anchored to the ENGINE fill texture's rect clips it to the
--  filled region, so the visible part is exactly [start-1, cur] -- the fill
--  edge performs the comparison C-side. Everything lives on sepHost (outside
--  the slot subtree): creation, recolor and retire stay legal at any time in
--  any restriction state; only ANCHORS touch the subtree (legal). SEMANTIC
--  NOTE: the legacy pips flipped the WHOLE fill to the topmost reached band
--  color; a continuous bar renders bands as RANGES instead, matching the
--  Ignore Pain bar's range coloring -- the continuous-bar convention.
--  "Up to" (reverse) modes have no engine expression and render nothing.
-------------------------------------------------------------------------------

local function StyleThresholds(H, frame, sp, n)
    local st = H.armed and H.ph[H.armed]
    local strips = st and st.thStrips
    if not strips then return end
    local spec = H.thSpec
    -- Every write below touches the slot subtree post-window (the strips and
    -- mask were BAKED in the creation window; an outside mask anchored to
    -- bft is denied as a forbidden-aspect dependent -- field-proven): legal
    -- while unrestricted, denied under restriction. ONE pcall covers the
    -- whole restyle; a denial rides the host dirty flag so the lift's Sync
    -- re-run restyles, and a throw can never abort the caller's paint pass again
    local ok = pcall(function()
        if not spec or n <= 0 then
            for i = 1, #strips do strips[i]:Hide() end
            return
        end
        local ori = sp.pipOrientation or "HORIZONTAL"
        local vertical = ori ~= "HORIZONTAL"
        local len = (vertical and frame:GetHeight() or frame:GetWidth()) or 0
        local used = 0
        for k = 1, #spec do
            local band = spec[k]
            if band.start and band.start >= 1 and band.start <= n
               and used < #strips then
                used = used + 1
                local t = strips[used]
                t:SetColorTexture(band.r, band.g, band.b, band.a)
                -- Strip origin measured from the FILL ORIGIN (left; top for
                -- reversed vertical; bottom for VERTICAL_UP), the separator
                -- ticks' fractions.
                local off = len * (band.start - 1) / n
                t:ClearAllPoints()
                if vertical then
                    t:SetPoint("LEFT", st.bar, "LEFT", 0, 0)
                    t:SetPoint("RIGHT", st.bar, "RIGHT", 0, 0)
                    if ori == "VERTICAL_UP" then
                        t:SetPoint("BOTTOM", st.bar, "BOTTOM", 0, off)
                        t:SetPoint("TOP", st.bar, "TOP", 0, 0)
                    else
                        t:SetPoint("TOP", st.bar, "TOP", 0, -off)
                        t:SetPoint("BOTTOM", st.bar, "BOTTOM", 0, 0)
                    end
                else
                    t:SetPoint("TOP", st.bar, "TOP", 0, 0)
                    t:SetPoint("BOTTOM", st.bar, "BOTTOM", 0, 0)
                    t:SetPoint("LEFT", st.bar, "LEFT", off, 0)
                    t:SetPoint("RIGHT", st.bar, "RIGHT", 0, 0)
                end
                t:Show()
            end
        end
        for i = used + 1, #strips do strips[i]:Hide() end
    end)
    if not ok then
        H.dirty = true
        EnsureLift()
    end
end

-- Threshold inputs, handed raw from the consumer's paint pass and
-- change-gated here with ALLOC-FREE field compares (the pass cadence is the
-- class bar tick; a rebuild only runs on a real settings/spec/cap change).
local function HostThresholds(H, powerKey, mode, count, r, g, b, a,
                              bandOn, bands, bandReverse, reverse)
    if H.armed ~= powerKey then return end
    local st = H.ph[powerKey]
    local n = (st and st.regMax) or 0
    -- v1: "Up to" modes render nothing (no engine expression).
    if reverse then count = nil end
    if bandReverse then bandOn = false end
    local inp = H.thIn
    if not inp then inp = { bands = {} }; H.thIn = inp end
    local bn = (bandOn and bands and #bands) or 0
    local changed = inp.mode ~= mode or inp.count ~= count or inp.n ~= n
        or inp.r ~= r or inp.g ~= g or inp.b ~= b or inp.a ~= a or inp.bn ~= bn
    if not changed and bn > 0 then
        for k = 1, bn do
            local sb, b2 = inp.bands[k], bands[k]
            if not sb or sb.to ~= b2.to or sb.r ~= b2.r or sb.g ~= b2.g
               or sb.b ~= b2.b or sb.a ~= b2.a then
                changed = true
                break
            end
        end
    end
    if not changed then return end
    inp.mode, inp.count, inp.n = mode, count, n
    inp.r, inp.g, inp.b, inp.a, inp.bn = r, g, b, a, bn
    local spec = H.thSpecStore
    if not spec then spec = {}; H.thSpecStore = spec end
    local used = 0
    if bn > 0 then
        local prev = 0
        for k = 1, bn do
            local b2 = bands[k]
            local sb = inp.bands[k]
            if not sb then sb = {}; inp.bands[k] = sb end
            sb.to, sb.r, sb.g, sb.b, sb.a = b2.to, b2.r, b2.g, b2.b, b2.a
            used = used + 1
            local e = spec[used]
            if not e then e = {}; spec[used] = e end
            e.start = prev + 1
            e.r, e.g, e.b = b2.r or 1, b2.g or 1, b2.b or 1
            e.a = b2.a or a or 1
            prev = b2.to or prev
        end
    elseif count and count > 0 and n > 0 then
        -- Pip-class thresholds are ABSOLUTE stack counts (field round:
        -- mode arrives nil and a percent fallback turned "6 stacks" into
        -- start=1). The value|percent mode split belongs to the value
        -- bars, never these two powers.
        local start = count
        used = 1
        local e = spec[1]
        if not e then e = {}; spec[1] = e end
        e.start, e.r, e.g, e.b, e.a = start, r or 1, g or 1, b or 1, a or 1
    end
    for i = used + 1, #spec do spec[i] = nil end
    H.thSpec = (used > 0) and spec or nil
    if H.lastStyleFrame then
        StyleThresholds(H, H.lastStyleFrame, H.lastStyleOpts, H.lastStyleN)
    end
end

-------------------------------------------------------------------------------
--  Host sync / gate (generic core)
-------------------------------------------------------------------------------

local function HostGate(H)
    H.armed = nil
    if H.proxy then H.proxy:Hide() end
end

HostSyncByKey = function(H, frame, powerKey, opts)
    if S.class ~= "WARRIOR" then return end
    local cfg = powerKey and PHASES[powerKey]
    if not (cfg and frame and opts) then
        HostGate(H)
        return
    end
    if H.armed ~= powerKey then H.lastR = nil end -- phase swap: re-apply color
    H.armed = powerKey
    H.syncFrame, H.syncOpts = frame, opts
    local st = H.ph[powerKey]
    if not (st and st.built) then
        EnsureHostBuilt(H, powerKey, opts)
        -- Nothing to show yet (sub-second build window): row stays empty.
        if H.proxy then H.proxy:Hide() end
        return
    end
    if st.err or not st.bar then
        if H.proxy then H.proxy:Hide() end
        return
    end
    -- Attach: the proxy rides the host's row frame (the Ebon Might shape);
    -- anchors keep it in step with every relayout at zero per-frame cost.
    -- manualAttach hosts (nameplate) position and size the proxy themselves
    -- BEFORE calling Sync -- the proxy then IS the row frame.
    if not opts.manualAttach then
        H.proxy:SetParent(frame)
        H.proxy:ClearAllPoints()
        H.proxy:SetAllPoints(frame)
    end
    local lvl = opts.manualAttach and H.proxy:GetFrameLevel() or frame:GetFrameLevel()
    st.container:SetFrameLevel(lvl + 1)
    st.container:Show()
    -- Talent-dependent cap (Broad Strokes): re-register the bar when the
    -- effective max changes. Post-window button calls are denied under
    -- restriction: pcall, and a denial re-applies at the lift (which re-runs
    -- this Sync). The ticks below always follow the REGISTERED max, so a
    -- denied re-register never splits fill scale from tick count.
    local wantMax = EffectiveMaxApps(powerKey, cfg)
    if st.regMax ~= wantMax and st.btn and st.bar then
        local okR = pcall(function()
            local barOpts = { maxApplications = wantMax }
            if Enum.StatusBarInterpolation then
                barOpts.interpolation = Enum.StatusBarInterpolation.Immediate
            end
            st.btn:SetApplicationBar(st.bar, barOpts)
        end)
        if okR then
            st.regMax = wantMax
        else
            H.dirty = true
            EnsureLift()
        end
    end
    StyleSeparators(H, opts.manualAttach and H.proxy or frame, opts, st.regMax or wantMax)
    -- Stashed for mid-session threshold restyles (settings edit between
    -- Syncs); NOT a resize-heal mechanism.
    H.lastStyleFrame = opts.manualAttach and H.proxy or frame
    H.lastStyleOpts = opts
    H.lastStyleN = st.regMax or wantMax
    StyleThresholds(H, H.lastStyleFrame, opts, H.lastStyleN)
    -- +4, not +1..+3: the engine subtree stacks container(+1) -> slot button
    -- -> fill bar, so the fill paints around +2/+3 (its exact level cannot be
    -- read back; the Ebon Might driver clears it with the same margin).
    H.sepHost:SetFrameLevel(lvl + 4)
    -- Count text visibility rides every Sync (the carrier is ours to toggle;
    -- the fontstring itself is engine-fed). Denied writes defer to the lift.
    if st.tc and opts.text then
        if not pcall(st.tc.SetShown, st.tc, opts.text.shown and true or false) then
            H.dirty = true
            EnsureLift()
        end
    end
    H.proxy:Show()
    -- Only one phase is ever armed per host; park the others so a spec swap
    -- never leaves two overlays stacked on the same rect.
    for key, other in pairs(H.ph) do
        if key ~= powerKey and other.container then other.container:Hide() end
    end
end

local function HostEngineOn(H, powerKey)
    if not H or H.armed ~= powerKey then return false end
    local st = H.ph[powerKey]
    return (st and st.built and st.bar and not st.err) and true or false
end

-------------------------------------------------------------------------------
--  Export. Living in the parent addon, this exists for every child no matter
--  which modules are enabled.
-------------------------------------------------------------------------------

_G._EWC = {
    -- opts: { texPath, r,g,b,a, fillAlpha, ori ("HORIZONTAL"/"VERTICAL"/
    -- "VERTICAL_UP"), manualAttach, sep = { r,g,b,a, w, cellW, gap, pad,
    -- stretch, empty = {r,g,b,a}, emptyInset }, text = { fontFrom, r,g,b,
    -- anchor, x, y, shown }, plus any legacy gap-color fields
    -- (gapColorEnabled/darkTheme/barBg*/pipOrientation/pipSpacing).
    Sync = function(hostKey, frame, powerKey, opts)
        HostSyncByKey(Host(hostKey), frame, powerKey, opts)
    end,
    Thresholds = function(hostKey, powerKey, mode, count, r, g, b, a,
                          bandOn, bands, bandReverse, reverse)
        local H = S.hosts[hostKey]
        if H then
            HostThresholds(H, powerKey, mode, count, r, g, b, a,
                bandOn, bands, bandReverse, reverse)
        end
    end,
    Gate = function(hostKey)
        local H = S.hosts[hostKey]
        if H then HostGate(H) end
    end,
    EngineOn = function(hostKey, powerKey)
        return HostEngineOn(S.hosts[hostKey], powerKey)
    end,
    Recolor = function(hostKey, powerKey, r, g, b, a)
        local H = S.hosts[hostKey]
        if H then HostRecolor(H, powerKey, r, g, b, a) end
    end,
    -- Talent-aware registration cap for a power key (0 for unknown keys) --
    -- consumers size their layouts from this so geometry and fill scale agree.
    MaxApps = function(powerKey)
        local cfg = PHASES[powerKey]
        return cfg and EffectiveMaxApps(powerKey, cfg) or 0
    end,
    -- Create-on-demand proxy handle for manualAttach hosts: they position and
    -- size it, then call Sync with the same frame and opts.manualAttach.
    GetProxy = function(hostKey)
        local H = Host(hostKey)
        if not H.proxy then
            H.proxy = CreateFrame("Frame", nil, UIParent)
            H.proxy:Hide()
        end
        return H.proxy
    end,
}
