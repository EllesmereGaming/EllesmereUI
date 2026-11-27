if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUICdmTbbDecimals.lua
--  12.1-only engine-driven decimal duration text for Tracking Bars.
--
--  The main TBB tick mirrors Blizzard's duration FontString verbatim because
--  the remaining time is a secret value in combat -- Lua cannot format it.
--  This module renders tenths anyway: each opted-in bar gets its own aura
--  container with one slot whose SetDurationText formatter is evaluated
--  ENGINE-side against the (possibly secret) remaining duration, so the text
--  is identical in and out of combat.
--
--  ENGINE RULES: a FontString registered with SetDurationText must be a
--  DESCENDANT of the aura button ("must inherit all forbidden parent aspects
--  from owner"), and it is a forbidden object to addon code: it cannot be
--  read back (GetText), so its string can never be copied onto the bar. The
--  engine FS IS the bar's visible timer text: styled from bar._timerText and
--  anchored like it, inside a container parented (through a holder frame of
--  ours) to the bar's text overlay, so it hides, fades and layers with the
--  bar. The engine shows the slot button exactly while the aura exists. Slot
--  buttons are never placed by the engine: extraInit anchors them.
--
--  Contract with the tick (EUI_CDM_BuffBarTick.lua):
--    * bar._tbbEngineFS = the bound engine FS (set/cleared ONLY here). While
--      set, the tick holds bar._timerText at alpha 0 and skips its own timer
--      text (MirrorEngineTimer); unbound bars keep the whole-second Blizzard
--      passthrough.
--    * ns.TBBDecimals_Sync() runs at the end of every BuildTrackedBuffBars.
--
--  Cost model: nothing exists until a bar enables Decimals (no container, no
--  events, no tick work -- the tick's only overhead is one nil field read).
--  Containers are (re)built only when the set of opted-in bars or their
--  spells changes (signature check), never per tick. Threshold and timer
--  style changes re-apply on the live FS; under aura restriction the style
--  copy waits for the lift. A mid-combat slot-set change unbinds everything
--  first (whole-second passthrough) and the rebuild runs at regen.
--------------------------------------------------------------------------------

local _, ns = ...

local AK -- EllesmereUI.AuraKit, resolved at first sync

-- Per-bar decimal threshold (Duration Text cog slider, 1-120, default 5):
-- tenths render below it. Integer-keyed cache (one engine formatter per
-- distinct threshold; bounded by the slider range, so no eviction needed).
-- Floor 1, never 0: a 0 threshold would collide with the tenths breakpoint
-- at threshold = 0 in GetDecimalFormatter's table.
local function ClampThr(v)
    v = tonumber(v) or 5
    if v < 1 then v = 1 elseif v > 120 then v = 120 end
    return math.floor(v + 0.5)
end

local formatterByThr = {}
local function GetDecimalFormatter(thr)
    thr = ClampThr(thr)
    local cached = formatterByThr[thr]
    if cached ~= nil then
        if cached then return cached end
        return nil -- false sentinel: this threshold's table was rejected
    end
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum.NumericRuleFormatRounding) then
        formatterByThr[thr] = false
        return nil
    end
    local Nearest = Enum.NumericRuleFormatRounding.Nearest
    local Up      = Enum.NumericRuleFormatRounding.Up
    local f = C_StringUtil.CreateNumericRuleFormatter()
    -- Shape of the field-proven threshold-text formatter: tenths Nearest below the
    -- threshold, whole seconds Up to the minute, then m:ss/h/d with boundaries offset
    -- just above the unit edge so UP-rounded input never flashes "60". step/rounding
    -- live at the BREAKPOINT level; components carry only the divisor. Off-shape tables
    -- get silently rejected or default-rounded by the validator -- do not restyle.
    local points = {
        { threshold = 0, format = "%.1f", rounding = Nearest },
    }
    if thr <= 59 then
        points[#points + 1] = { threshold = thr, format = "%d", rounding = Up, step = 1 }
        points[#points + 1] = { threshold = 59.0001, format = "%d:%02d", rounding = Up, step = 1,
            components = { { div = 60 }, { mod = 60 } } }
    else
        -- Threshold past the minute boundary: tenths run right up to it,
        -- then hand off straight to m:ss (no whole-second band).
        points[#points + 1] = { threshold = thr + 0.0001, format = "%d:%02d", rounding = Up, step = 1,
            components = { { div = 60 }, { mod = 60 } } }
    end
    points[#points + 1] = { threshold = 3599.0001, format = "%dh", rounding = Up, step = 1,
        components = { { div = 3600 } } }
    points[#points + 1] = { threshold = 86399.0001, format = "%dd", rounding = Up, step = 1,
        components = { { div = 86400 } } }
    local ok = pcall(f.SetBreakpoints, f, points)
    if not ok then
        formatterByThr[thr] = false
        return nil
    end
    formatterByThr[thr] = f
    return f
end

-- Variant expansion for one stored spell id: the live aura can come up under
-- the talent override (or base) form of the id the config captured.
local function AddVariants(include, sid)
    if type(sid) ~= "number" or sid <= 0 then return end
    include[sid] = true
    if C_Spell then
        if C_Spell.GetOverrideSpell then
            local o = C_Spell.GetOverrideSpell(sid)
            if type(o) == "number" and o > 0 then include[o] = true end
        end
        if C_Spell.GetBaseSpell then
            local b = C_Spell.GetBaseSpell(sid)
            if type(b) == "number" and b > 0 then include[b] = true end
        end
    end
end

-- Secret-guarded AddVariants for ids read off live frames/cooldownInfo (an
-- active frame's ids can be SECRET; a secret table key would blow up the
-- filter). issecretvalue FIRST, arithmetic after.
local function AddCleanID(include, id)
    if issecretvalue and issecretvalue(id) then return end
    if type(id) ~= "number" or id <= 0 then return end
    AddVariants(include, id)
end

-- Reconcile a config's include set against Blizzard's cooldown info -- the SAME source
-- of truth the tick's frame matching trusts (MatchesSID). The aura that actually
-- appears often carries an id that exists ONLY in linkedSpellIDs (variant chains:
-- rituals, Eclipse-style pairs), never in the stored config ids, and without it the
-- slot filter can never match. Sync-time only (rebuilds), never per tick.
local function AddCooldownInfoIDs(include, cfg)
    local frame = ns.FindTBBChild and ns.FindTBBChild(cfg)
    if not frame then return end
    -- The frame's canonical id resolves GetSpellID/GetAuraSpellID (the actual
    -- aura variant) with its own secret handling.
    if ns.GetCanonicalSpellIDForFrame then
        AddCleanID(include, ns.GetCanonicalSpellIDForFrame(frame))
    end
    local cdID = frame.cooldownID
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    local info = cdID and gci and gci(cdID)
    if not info then return end
    AddCleanID(include, info.spellID)
    AddCleanID(include, info.overrideSpellID)
    AddCleanID(include, info.overrideTooltipSpellID)
    if info.linkedSpellIDs then
        for k = 1, #info.linkedSpellIDs do
            AddCleanID(include, info.linkedSpellIDs[k])
        end
    end
end

local containers     -- live AuraContainers (one per decimal bar), or nil
local holders        -- our frame around each container (always hideable)
local signature      -- signature string of the live slot set
local boundIndex = {}   -- bar index -> slot button (rebuilt per container)
local boundThr = {}     -- bar index -> threshold its binding was registered with
local boundCarrier = {} -- bar index -> frame the engine FS is anchored in
local boundStyle = {}   -- bar index -> style signature last copied onto the FS
local pendingRegen      -- true while a combat-deferred rebuild is queued
local styleDirty        -- a style copy was refused under aura restriction
local liftHooked

-- The bar timer's look as one string, to detect settings changes. Anchor and
-- color come from settings: GetPoint/GetTextColor on the bar's own FS can
-- return secrets once the bar has mirrored a secret value.
local function TimerStyleSig(out, cfg)
    local path, size, flags = out:GetFont()
    local sx, sy = out:GetShadowOffset()
    local sr, sg, sb, sa = out:GetShadowColor()
    local point, relPoint, x, y, justify = ns.TBBTimerAnchor(cfg)
    return table.concat({ tostring(path), tostring(size), tostring(flags),
        sx or 0, sy or 0, sr, sg, sb, sa,
        tostring(cfg.timerTextR), tostring(cfg.timerTextG),
        tostring(cfg.timerTextB), tostring(cfg.timerTextA),
        point, relPoint, x, y, justify,
        tostring(cfg.showTimer), tostring(cfg.timerPosition) }, "|")
end

-- Give the engine FS the bar timer's look. The carrier covers the status bar
-- the timer anchors to, so the same anchor lands in the same place.
-- Only in the button's creation window or out of aura restriction.
local function ApplyTimerStyle(fs, carrier, out, cfg)
    local path, size, flags = out:GetFont()
    fs:SetFont(path or (ns.GetCDMFont and ns.GetCDMFont())
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\EUI Highway.ttf",
        size or 11, flags or "")
    ns.SetTBBTextColor(fs, cfg, "timer")
    fs:SetShadowOffset(out:GetShadowOffset())
    fs:SetShadowColor(out:GetShadowColor())
    local point, relPoint, x, y, justify = ns.TBBTimerAnchor(cfg)
    fs:SetJustifyH(justify)
    fs:ClearAllPoints()
    fs:SetPoint(point, carrier, relPoint, x, y)
    fs:SetShown(cfg.showTimer and (cfg.timerPosition or "right") ~= "none" and true or false)
end

local function OnLift()
    if styleDirty then
        styleDirty = nil
        ns.TBBDecimals_Sync()
    end
end

local function SyncAfterCombat()
    if pendingRegen then
        pendingRegen = nil
        ns.TBBDecimals_Sync()
    end
end

local function UnmarkAll()
    for idx in pairs(boundIndex) do
        local bar = ns.GetTBBFrame and ns.GetTBBFrame(idx)
        if bar then
            bar._tbbEngineFS = nil
            -- The tick holds the bar's timer FS at alpha 0 while bound; an
            -- unbound bar must never keep a stuck alpha-0 FS.
            if bar._tbbAlphaGated then
                if bar._timerText then bar._timerText:SetAlpha(1) end
                bar._tbbAlphaGated = nil
            end
        end
    end
    wipe(boundIndex)
    wipe(boundThr)
    wipe(boundCarrier)
    wipe(boundStyle)
end

local function ReleaseCurrent()
    UnmarkAll()
    -- Hide our holders first: hiding an engine container can be refused under
    -- aura restriction, and a surviving one draws its emptied slot as "0".
    if holders then
        for i = 1, #holders do holders[i]:Hide() end
        holders = nil
    end
    if containers then
        for i = 1, #containers do
            AK.ReleaseContainer(containers[i]) -- hides it: the engine stops driving
        end
        containers = nil
        signature = nil
    end
end

-- Desired slot set: one entry per enabled, aura-driven bar with Decimals on.
-- Self-timed presets (lust/potions/Time Spiral) are excluded -- they already
-- render tenths from their own clean, never-secret countdown.
--
-- Two passes. Pass 1 collects each aura bar's SAVED identity (stored ids + override/base
-- variants) and claims those ids for that bar -- every enabled aura bar, Decimals on or
-- not. Pass 2 adds the cooldownInfo enrichment, but an id claimed by a DIFFERENT bar's
-- saved config never leaks in: spell families share one cooldownInfo (ritual + art
-- chains list each other in linkedSpellIDs), and a borrowed id another bar tracks let
-- the engine bind that bar's aura to this slot (wrong time, or "0.0").
local function CollectDesired()
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    local bars = tbb and tbb.bars
    if not bars then return nil, "" end

    local work
    local claimed = {}
    for i, cfg in ipairs(bars) do
        if cfg.enabled ~= false and cfg.trackType ~= "cooldown" then
            local include = {}
            AddVariants(include, cfg.spellID)
            AddVariants(include, cfg.baseSpellID)
            if cfg.spellIDs then
                for k = 1, #cfg.spellIDs do AddVariants(include, cfg.spellIDs[k]) end
            end
            for id in pairs(include) do
                if claimed[id] == nil then claimed[id] = i end
            end
            if cfg.timerDecimals and not cfg.popularKey and next(include) then
                work = work or {}
                work[#work + 1] = { index = i, cfg = cfg, include = include }
            end
        end
    end
    if not work then return nil, "" end

    local desired, sigParts = {}, {}
    local extra = {}
    for n = 1, #work do
        local w = work[n]
        wipe(extra)
        AddCooldownInfoIDs(extra, w.cfg)
        for id in pairs(extra) do
            local owner = claimed[id]
            if owner == nil or owner == w.index then
                w.include[id] = true
            end
        end
        local ids = {}
        for id in pairs(w.include) do ids[#ids + 1] = id end
        table.sort(ids)
        -- thr intentionally stays OUT of the signature: a slider move
        -- re-registers the live binding in place (no container swap).
        desired[#desired + 1] = { index = w.index, cfg = w.cfg, include = w.include, ids = ids,
            thr = ClampThr(w.cfg.timerDecimalThreshold) }
        sigParts[#sigParts + 1] = w.index .. "=" .. table.concat(ids, ",")
    end
    return desired, table.concat(sigParts, ";")
end

local function BuildContainer(desired)
    AK.styles.tbbDecimalText = AK.styles.tbbDecimalText
        or { width = 1, height = 1, noRegions = true }

    containers, holders = {}, {}
    for n = 1, #desired do
        local want = desired[n]
        local slot = {
            key = "tbb" .. want.index,
            filter = { "HELPFUL" },
            candidateFilters = { includeSpellIDs = want.include },
            style = "tbbDecimalText",
            extraInit = function(button)
                if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
                local fmt = GetDecimalFormatter(want.thr)
                -- Any early return leaves the bar unbound: whole-second passthrough.
                if not fmt then return end
                local bar = ns.GetTBBFrame and ns.GetTBBFrame(want.index)
                if not (bar and bar._timerText) then return end
                -- The bound FS MUST be a descendant of the aura button (aspect
                -- inheritance), and addon code may not read it back, so it IS
                -- the bar's visible timer text. Styled BEFORE registration
                -- (style-before-register contract).
                -- The engine never places slot buttons: cover the status bar the
                -- timer text anchors to, so its anchor copies over exactly.
                local out = bar._timerText
                button:SetAllPoints(bar._bar or bar)
                local carrier = CreateFrame("Frame", nil, button)
                carrier:SetAllPoints(button)
                local fs = carrier:CreateFontString(nil, "OVERLAY")
                ApplyTimerStyle(fs, carrier, out, want.cfg)
                -- 68914 schema: updateInterval is a binding-level knob now,
                -- so the formatter + 0.05s interval travel on a configured
                -- DurationTextBinding via options.binding (BuildDurationTextOpts).
                if not AK.SetDurationTextSafe(button, fs,
                    AK.BuildDurationTextOpts(fmt, nil, 0.05)) then
                    fs:Hide()
                    return
                end
                boundIndex[want.index] = button
                boundThr[want.index] = want.thr
                boundCarrier[want.index] = carrier
                boundStyle[want.index] = TimerStyleSig(out, want.cfg)
                bar._tbbEngineFS = fs
            end,
        }

        -- One container per bar, inside a holder of ours on the bar's text
        -- overlay: it hides, fades and layers with the bar's own text, and the
        -- holder can always be hidden on teardown. Strata and level set by hand
        -- (the CDM aura icons do the same) so it never draws under the bar fill.
        -- point is REQUIRED: the engine parses auras from a run-when-visible
        -- OnUpdate, and an unanchored container never processes a single aura.
        local bar = ns.GetTBBFrame and ns.GetTBBFrame(want.index)
        local parent = bar and bar._timerText and bar._timerText:GetParent()
        if parent then
            local holder = CreateFrame("Frame", nil, parent)
            holder:SetAllPoints(parent)
            holder:SetFrameLevel(parent:GetFrameLevel() + 1)
            local c = AK.CreateContainer(holder, "player", {
                point = { "BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0 },
                slots = { slot },
            })
            c:SetFrameStrata(holder:GetFrameStrata())
            c:SetFrameLevel(holder:GetFrameLevel() + 1)
            containers[#containers + 1] = c
            holders[#holders + 1] = holder
        end
    end
end

function ns.TBBDecimals_Sync()
    AK = AK or (EllesmereUI and EllesmereUI.AuraKit)
    if not AK then return end

    local desired, sig = CollectDesired()

    if not desired then
        if containers then ReleaseCurrent() end
        return
    end

    if containers and sig == signature then
        -- Same slot set: re-register any binding whose threshold slider moved
        -- -- a fresh SetDurationText on the live button swaps the formatter in
        -- place (no container swap needed) -- and re-copy a changed timer look.
        for n = 1, #desired do
            local want = desired[n]
            local button = boundIndex[want.index]
            local bar = ns.GetTBBFrame and ns.GetTBBFrame(want.index)
            if button and bar then
                if bar._tbbEngineFS and boundThr[want.index] ~= want.thr then
                    local fmt = GetDecimalFormatter(want.thr)
                    if fmt then
                        -- Stamp only on success: SetDurationTextSafe never throws
                        -- anymore, and a denied re-registration under restriction must
                        -- stay unstamped so a later Sync retries it.
                        local ok = AK.SetDurationTextSafe(button, bar._tbbEngineFS,
                            AK.BuildDurationTextOpts(fmt, nil, 0.05))
                        if ok then boundThr[want.index] = want.thr end
                    end
                end
                -- Timer look changed in the options: re-copy it. Refused under
                -- aura restriction -> stays unstamped and retries at the lift.
                local fs, carrier = bar._tbbEngineFS, boundCarrier[want.index]
                if fs and carrier and bar._timerText then
                    local styleSig = TimerStyleSig(bar._timerText, want.cfg)
                    if styleSig ~= boundStyle[want.index] then
                        if AK.CanTouchButton(button) then
                            ApplyTimerStyle(fs, carrier, bar._timerText, want.cfg)
                            boundStyle[want.index] = styleSig
                        else
                            styleDirty = true
                        end
                    end
                end
            end
        end
        if styleDirty and not liftHooked and AK.OnRestrictionLift then
            liftHooked = true
            AK.OnRestrictionLift(OnLift)
        end
        return
    end

    -- Slot set changed. The old bindings would keep writing the OLD spell's
    -- time onto re-purposed bar indexes, so tear down FIRST (bars fall back
    -- to the accurate whole-second passthrough for the gap), then build.
    -- The build waits for regen; the teardown does not.
    ReleaseCurrent()

    if InCombatLockdown() then
        pendingRegen = true
        ns.CombatQueue.Defer("TBBDecimalsSync", SyncAfterCombat)
        return
    end
    pendingRegen = nil

    BuildContainer(desired)
    signature = containers and sig or nil
end

