if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUICdmTbbDecimals.lua
--  12.1-only engine-driven decimal duration text for Tracking Bars.
--
--  The main TBB tick mirrors Blizzard's duration FontString verbatim because
--  the remaining time is a secret value in combat -- Lua cannot format it.
--  This module renders tenths anyway through the engine: a bar with Decimals
--  on gets a TIMER TWIN, a one-slot aura container of its own whose
--  SetDurationText formatter is evaluated ENGINE-side against the (possibly
--  secret) remaining duration, so the text is identical in and out of combat.
--
--  ENGINE RULES: a FontString registered with SetDurationText must be a
--  DESCENDANT of the aura button ("must inherit all forbidden parent aspects
--  from owner"), and while auras are restricted the button's whole subtree
--  refuses every call from our code (GetText and IsShown included), so its
--  string can never be read or copied onto the bar. The engine FS therefore
--  IS the bar's visible timer: drawn where the bar's own timer sits, in its
--  font and color, from the bar's proxy (below: placed by number on UIParent,
--  never inside the bar's frame tree or anchor family, which an engine subtree
--  would lock in combat). A bar whose aura lands on another unit (the entry's
--  selfAura false) gets no timer twin: the slot reads the player's auras.
--
--  Contract with the tick (EUI_CDM_BuffBarTick.lua):
--    * bar._tbbEngineFS = the engine FS of a bound timer twin (set/cleared
--      ONLY here, set once its decimal binding took). While set and the tick
--      mirrors Blizzard's frame, MirrorEngineTimer holds bar._timerText at
--      alpha 0 and turns the twin on (ns.TBBTimerTwin_Set); every other branch
--      turns it off and puts the alpha back (ns.TBBEngineTimerOff).
--    * ns.TBBDecimals_Sync() runs at the end of every BuildTrackedBuffBars.
--
--  Cost model: nothing exists until a bar enables Decimals (no container, no
--  events, no tick work -- the tick's only overhead is one nil field read).
--  Enabled, the engine writes the text C-side and the tick drops its per-tick
--  passthrough for that bar. A twin is (re)built only when its bar's ids
--  change (signature check), never per tick. Container creation is
--  combat-illegal, so a mid-combat change releases first (the tick falls back
--  to the whole-second mirror, still accurate) and the build runs at regen.
--
--  ENGINE MODE (game-drawn bars). A bar whose aura NO Blizzard bar frame
--  draws (a custom buff ID, or a spell Blizzard's bar viewer does not hold)
--  would fall back to GetPlayerAuraBySpellID, which is RequiresNonSecretAura:
--  in M+/raid combat it answers nil for a flagged spell (no bar at all) or
--  secret numbers (a full bar with no timer). Such a bar gets a TWIN instead:
--  a one-slot aura container of its own whose slot button IS the bar's active
--  look, drawn by the engine end to end (fill via SetDurationBar, timer via
--  SetDurationText, stacks via SetApplicationCount), placed by number over
--  the bar on a UIParent proxy that takes the bar's scale (so the twin is cut
--  in the bar's own units, at the bar's drawn size). The button shows only
--  while the aura is up.
--  NOTHING is ever read back from the slot: while auras are restricted the
--  button refuses every call from our code (IsShown included), and frames
--  anchored to it have restricted geometry. So the twin's regions are our own
--  frames inside the button, built in its creation window, hung off one root
--  of an explicit size centered on the button (its only anchor to the
--  button), and styled from the bar's settings (restyled in place whenever
--  auras are not restricted, else at the lift). The bar itself shows only its
--  idle look under the twin (an empty bar, or nothing under Hide When
--  Inactive), so Lua never learns whether the aura is up: an engine bar keeps
--  its slot in a group and plays no gain or loss sound. Contract (set and
--  cleared ONLY here): bar._tbbEngineMode; the tick calls ns.TBBTwin_Set(bar,
--  on) and keeps bar._tbbIdleHidden / _tbbIdleSet for the idle look.
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

-- An engine bar without Decimals reads as the tick's FormatTime does
-- (EllesmereUICdmBuffBars.lua): tenths under 10 s, whole seconds rounded up,
-- then whole minutes and hours rounded down. Built once; false = rejected.
local plainFormatter
local function GetPlainFormatter()
    if plainFormatter ~= nil then return plainFormatter or nil end
    plainFormatter = false
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter
        and Enum.NumericRuleFormatRounding) then
        return nil
    end
    local R = Enum.NumericRuleFormatRounding
    local f = C_StringUtil.CreateNumericRuleFormatter()
    local ok = pcall(f.SetBreakpoints, f, {
        { threshold = 0,    format = "%.1f", rounding = R.Nearest },
        { threshold = 10,   format = "%d",   rounding = R.Up,   step = 1 },
        { threshold = 60,   format = "%dm",  rounding = R.Down, step = 1, components = { { div = 60 } } },
        { threshold = 3600, format = "%dh",  rounding = R.Down, step = 1, components = { { div = 3600 } } },
    })
    if ok then plainFormatter = f end
    return plainFormatter or nil
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
-- slot filter can never match. Sync-time only (rebuilds), never per tick. Returns the
-- entry's selfAura (the API copy's; nil while unknown): false = an aura a slot reading
-- the player's helpful auras can never draw (on another unit, or WoW Forever's
-- debuff on the caster that Blizzard's bar finds through its linked lookup).
local function AddCooldownInfoIDs(include, cfg)
    local frame = ns.FindTBBChild and ns.FindTBBChild(cfg)
    if not frame then return nil end
    if ns.CDM_LinkedAuraBarFull and ns.CDM_LinkedAuraBarFull(frame) then return false end
    -- The frame's canonical id resolves GetSpellID/GetAuraSpellID (the actual
    -- aura variant) with its own secret handling.
    if ns.GetCanonicalSpellIDForFrame then
        AddCleanID(include, ns.GetCanonicalSpellIDForFrame(frame))
    end
    local cdID = frame.cooldownID
    if issecretvalue and issecretvalue(cdID) then return nil end
    local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
    local info = cdID and gci and gci(cdID)
    if not info then return nil end
    AddCleanID(include, info.spellID)
    AddCleanID(include, info.overrideSpellID)
    AddCleanID(include, info.overrideTooltipSpellID)
    if info.linkedSpellIDs then
        for k = 1, #info.linkedSpellIDs do
            AddCleanID(include, info.linkedSpellIDs[k])
        end
    end
    local selfAura = info.selfAura
    if issecretvalue and issecretvalue(selfAura) then return nil end
    return selfAura
end

local pendingRegen      -- true while a combat-deferred rebuild is queued

local function SyncAfterCombat()
    if pendingRegen then
        pendingRegen = nil
        ns.TBBDecimals_Sync()
    end
end

-- Smooth fills on (Tracking Bars smoothing): the twin's fill interpolates.
local function TwinSmooth()
    local sm = ns.GetTBBSmoothSettings and ns.GetTBBSmoothSettings()
    return (not sm) or sm.buffs ~= false
end

-- Whether "no Blizzard bar frame draws it" can be told yet: Blizzard's data is
-- loaded and its bar viewer holds its frames (one per tracked bar, active or
-- not), or it tracks no bar at all. Before that every bar would read as one no
-- frame draws. Kept for the frame (GetTime): the tick asks it once per bar, and
-- the category set it may read is a new table per call.
local readyAt, readyVal
local function ViewerReady()
    if not ns._cdmDataLoaded then return false end
    local now = GetTime()
    if readyAt == now then return readyVal end
    readyAt = now
    local viewer = _G.BuffBarCooldownViewer
    local pool = viewer and viewer.itemFramePool
    if pool and pool.GetNumActive and pool:GetNumActive() > 0 then
        readyVal = true
    else
        local cat = Enum.CooldownViewerCategory and Enum.CooldownViewerCategory.TrackedBar
        local get = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
        local set = cat and get and get(cat)
        readyVal = type(set) == "table" and #set == 0
    end
    return readyVal
end

-- Engine mode: an aura bar no Blizzard bar frame draws. Self-timed presets
-- (lust/potions/Time Spiral) and cooldown bars draw themselves. Such a bar is
-- drawn by its twin (see "Game-drawn bars" below); a Blizzard frame that pairs
-- later takes it back in the tick. ready: ViewerReady(), once per collect.
local function EngineMode(cfg, ready)
    if not ready then return false end
    if not ((cfg.spellID and cfg.spellID > 0) or cfg.spellIDs) then return false end
    return not (ns.FindTBBChild and ns.FindTBBChild(cfg))
end

-- The twins wanted: one per enabled, aura-driven bar in engine mode (the whole
-- bar, Decimals or not) or with Decimals on (the timer alone, timerOnly), each in
-- a container of its own, so two bars sharing an id never race for one aura.
-- Self-timed presets (lust/potions/Time Spiral) are excluded -- they already
-- render tenths from their own clean, never-secret countdown. nil when none.
--
-- Pass 0 finds the bars that want one: with none (the common case) that one walk
-- is the whole cost. Pass 1 collects every enabled aura bar's SAVED identity
-- (stored ids + override/base variants), twin or not, and claims those ids for
-- that bar. Pass 2 adds the cooldownInfo enrichment, but an id claimed by a
-- DIFFERENT bar's saved config never leaks in: spell families share one
-- cooldownInfo (ritual + art chains list each other in linkedSpellIDs), and a
-- borrowed id another bar tracks let the engine draw that bar's aura in this
-- slot (the wrong time).
local function CollectDesired()
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    local bars = tbb and tbb.bars
    if not bars then return nil end

    local work
    local ready = ViewerReady()
    for i, cfg in ipairs(bars) do
        if cfg.enabled ~= false and not cfg.popularKey and cfg.trackType ~= "cooldown" then
            local engine = EngineMode(cfg, ready)
            if engine or cfg.timerDecimals then
                work = work or {}
                work[#work + 1] = { index = i, cfg = cfg, engine = engine }
            end
        end
    end
    if not work then return nil end

    local claimed, own = {}, {}
    for i, cfg in ipairs(bars) do
        if cfg.enabled ~= false and cfg.trackType ~= "cooldown" then
            local include = {}
            AddVariants(include, cfg.spellID)
            AddVariants(include, cfg.baseSpellID)
            if cfg.spellIDs then
                for k = 1, #cfg.spellIDs do AddVariants(include, cfg.spellIDs[k]) end
            end
            own[i] = include
            for id in pairs(include) do
                if claimed[id] == nil then claimed[id] = i end
            end
        end
    end

    local list
    local extra = {}
    for n = 1, #work do
        local w = work[n]
        local include = own[w.index]
        if next(include) then
            wipe(extra)
            local selfAura = AddCooldownInfoIDs(extra, w.cfg)
            -- A timer twin reads the player's auras: an entry whose aura lands on
            -- another unit keeps the tick's whole-second passthrough.
            if w.engine or selfAura ~= false then
                for id in pairs(extra) do
                    local owner = claimed[id]
                    if owner == nil or owner == w.index then
                        include[id] = true
                    end
                end
                local ids = {}
                for id in pairs(include) do ids[#ids + 1] = id end
                table.sort(ids)
                local want = { index = w.index, include = include, ids = ids,
                    thr = ClampThr(w.cfg.timerDecimalThreshold),
                    decimals = w.cfg.timerDecimals and true or false,
                    timerOnly = not w.engine }
                -- A twin is built again only when what its slot is built with
                -- changes: the ids, its kind and (a whole bar) smoothing, the
                -- fill's interpolation. Its look restyles in place, and the
                -- timer's formatter (Decimals and its threshold) is registered
                -- again in place (SyncTwins).
                want.tsig = table.concat(ids, ",")
                    .. (w.engine and (TwinSmooth() and "|s" or "|") or "|t")
                list = list or {}
                list[#list + 1] = want
            end
        end
    end
    return list
end

-------------------------------------------------------------------------------
--  Game-drawn bars (engine mode). The twin is the bar's active look inside a
--  one-slot container of its own (see the header). Nothing here ever reads the
--  slot button or anything inside it; the only call on the button outside its
--  creation window is the timer formatter's re-registration (SetDurationTextSafe,
--  refused while auras are restricted and retried by a later sync).
-------------------------------------------------------------------------------
local IsSecret = EllesmereUI.IsSecret
local twins = {}         -- bar index -> twin record
local proxies = {}       -- bar index -> its proxy (built once, reused by each twin)
local twinOf = setmetatable({}, { __mode = "k" })      -- bar -> its twin record
local twinHooked = setmetatable({}, { __mode = "k" })  -- bars whose moves we follow
local twinWant = {}      -- scratch: bar index -> wanted entry
local twinDue = {}       -- records to place on the next frame
local twinWaitLift       -- true while a twin's restyle waits for the restriction to lift
local TWIN_STYLE = "tbbTwin"
local SPARK_TEX = "Interface\\AddOns\\EllesmereUI\\media\\cast_spark.tga"

local function Ident(v) return v end

-- A twin's setup, or a restyle while auras are not restricted, that fails is a
-- bug that would leave its bar empty: the first one of the session goes to the
-- error handler a frame later, outside the engine's frame batch (an error inside
-- it ends the batch and the slot).
local twinErrShown
local function ReportTwinError(err)
    if twinErrShown then return end
    twinErrShown = true
    C_Timer.After(0, function() geterrorhandler()(err) end)
end

-- A bar text's spot, as ApplyTrackedBuffBarSettings places it (relative to the
-- fill). outside: a vertical bar's left and right sit outside the bar (the
-- timer's rule).
local function PlaceBarText(fs, pos, sb, x, y, isVert, outside)
    fs:ClearAllPoints()
    if pos == "center" then
        fs:SetPoint("CENTER", sb, "CENTER", x, y)
        fs:SetJustifyH("CENTER")
    elseif pos == "top" then
        fs:SetPoint("BOTTOM", sb, "TOP", x, 5 + y)
        fs:SetJustifyH("CENTER")
    elseif pos == "bottom" then
        fs:SetPoint("TOP", sb, "BOTTOM", x, -5 + y)
        fs:SetJustifyH("CENTER")
    elseif pos == "left" then
        if isVert and outside then
            fs:SetPoint("RIGHT", sb, "LEFT", -5 + x, y)
            fs:SetJustifyH("RIGHT")
        else
            fs:SetPoint("LEFT", sb, "LEFT", 5 + x, y)
            fs:SetJustifyH("LEFT")
        end
    elseif isVert and outside then
        fs:SetPoint("LEFT", sb, "RIGHT", 5 + x, y)
        fs:SetJustifyH("LEFT")
    else
        fs:SetPoint("RIGHT", sb, "RIGHT", -5 + x, y)
        fs:SetJustifyH("RIGHT")
    end
end

local function PlainTexture(tex)
    local f = tex and tex:GetTexture()
    if IsSecret(f) then return nil end
    return f
end

local function PlainText(fs)
    local t = fs and fs:GetText()
    if IsSecret(t) then return nil end
    return t
end

-- The bar as drawn, in its own units (the proxy takes the bar's scale:
-- TwinPlace), so a size set on the frame alone counts too; the saved size
-- stands in while the bar has none. Also the icon square and the fill area
-- (the footprint less the icon: the bar's status bar, which its texts hang from).
local function TwinFootprint(cfg, bar)
    local PPt = EllesmereUI.PP
    local snap = (PPt and PPt.Snap) or Ident
    local w, h = bar:GetSize()
    if not (type(w) == "number" and type(h) == "number" and not IsSecret(w)
       and not IsSecret(h) and w > 0 and h > 0) then
        w, h = snap(cfg.width or 270), snap(cfg.height or 24)
    end
    local isVert = cfg.verticalOrientation and true or false
    local iconMode = cfg.iconDisplay or "none"
    local hasIcon = iconMode ~= "none"
    local iSize = isVert and w or h
    if hasIcon then
        local long = isVert and h or w
        if iSize > long - 1 then iSize = math.max(1, long - 1) end
    end
    local fw, fh, ox, oy = w, h, 0, 0
    if hasIcon then
        if isVert then
            fh = h - iSize
            if iconMode == "left" then oy = -iSize end
        else
            fw = w - iSize
            if iconMode == "left" then ox = iSize end
        end
    end
    return w, h, isVert, iconMode, hasIcon, iSize, fw, fh, ox, oy
end

-- Style the twin from the bar's settings: the geometry, fill, background,
-- spark, icon, border and texts of ApplyTrackedBuffBarSettings, each region
-- hung off the root (never off the button). full (Hide When Inactive): the twin
-- is the whole bar; else the bar shows its idle look under it and the twin
-- draws only the fill, spark, timer and stacks. Writes only, on our own frames.
-- Not drawn: Classic WoW UI's frame art, corner radius, threshold colors and
-- tick marks (the idle bar keeps its own ticks), the pandemic glow.
local function PaintTwin(rec, cfg, bar)
    local I = ns._buffBarInternals
    local w, h, isVert, iconMode, hasIcon, iSize, fw, fh, ox, oy = TwinFootprint(cfg, bar)
    local full = cfg.hideWhenInactive ~= false
    local blizzBar = ns.CdmBlizzBars()
    local classicBar = ns.CdmClassicBars()
    local stock = blizzBar and not classicBar

    -- Levels on the bar's own ladder (EUI_CDM_BuffBarFrames.lua: fill +1,
    -- border +6, text +9): the twin's fill over the idle bar's empty fill and
    -- under its border, the twin's text over the idle bar's.
    local base = bar:GetFrameLevel()
    rec.proxy:SetFrameLevel(base)
    if rec.container then rec.container:SetFrameLevel(base + 1) end
    local root, sb = rec.root, rec.sb
    root:SetSize(w, h)
    root:SetFrameLevel(base + 2)

    -- The fill area (TwinFootprint).
    sb:ClearAllPoints()
    sb:SetPoint("TOPLEFT", root, "TOPLEFT", ox, oy)
    sb:SetSize(fw, fh)
    sb:SetFrameLevel(base + 3)
    sb:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
    sb:SetReverseFill(cfg.reverseFill and true or false)
    local texPath = stock and "Interface\\Buttons\\WHITE8x8"
        or EllesmereUI.ResolveTexturePath(I.TBB_TEXTURES, cfg.texture or "none", "Interface\\Buttons\\WHITE8x8")
    if rec.texPath ~= texPath or rec.stock ~= stock or not rec.fillTex then
        rec.texPath, rec.stock = texPath, stock
        sb:SetStatusBarTexture(texPath)
        rec.fillTex = sb:GetStatusBarTexture()
        if stock then rec.fillTex:SetAtlas("UI-HUD-CoolDownManager-Bar") end
    end
    local fillTex = rec.fillTex
    local fR, fG, fB, fA = cfg.fillR or I._classR, cfg.fillG or I._classG, cfg.fillB or I._classB, cfg.fillA or 1
    local grad = cfg.gradientEnabled and not blizzBar
    local clip = rec.gradClip
    if grad then
        fillTex:SetVertexColor(1, 1, 1, 0)
        clip:ClearAllPoints()
        clip:SetAllPoints(fillTex)
        clip:SetFrameLevel(base + 4)
        local gt = rec.gradTex
        gt:SetTexture(texPath)
        gt:SetVertexColor(1, 1, 1, 1)
        gt:SetGradient(cfg.gradientDir or "HORIZONTAL", CreateColor(fR, fG, fB, fA),
            CreateColor(cfg.gradientR or 0.20, cfg.gradientG or 0.20, cfg.gradientB or 0.80, cfg.gradientA or 1))
        clip:Show()
    else
        clip:Hide()
        fillTex:SetVertexColor(fR, fG, fB, fA)
    end

    -- Background (the whole bar only).
    local bg, bbg = rec.bg, rec.blizzBg
    if full and not stock then
        bg:ClearAllPoints()
        bg:SetAllPoints(sb)
        bg:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgA or 0.4)
        bg:Show()
    else
        bg:Hide()
    end
    if full and stock then
        bbg:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
        bbg:ClearAllPoints()
        bbg:SetPoint("TOPLEFT", sb, "TOPLEFT", -2, 2)
        bbg:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 4, -7)
        bbg:Show()
    else
        bbg:Hide()
    end

    -- Spark on the fill's moving edge (AnchorTBBSparkState's sizes and offsets).
    local spark, sh = rec.spark, rec.sparkHost
    if cfg.showSpark then
        sh:SetFrameLevel(base + 5)
        sh:SetClipsChildren(not classicBar)
        if stock then
            spark:SetAtlas("UI-HUD-CoolDownManager-Bar-Pip")
            spark:SetBlendMode("BLEND")
        else
            spark:SetTexture(classicBar and ns.CDM_CLASSIC_BAR_SPARK or SPARK_TEX)
            spark:SetBlendMode("ADD")
        end
        local classicSz = classicBar and ((isVert and fw or fh) * (32 / 13))
        if isVert then
            if classicSz then spark:SetSize(classicSz, classicSz) else spark:SetSize(fw, 8) end
            if not stock then spark:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0) end
        else
            if classicSz then spark:SetSize(classicSz, classicSz) else spark:SetSize(8, fh) end
            if not stock then spark:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1) end
        end
        local anchor = grad and clip or fillTex
        local rev = cfg.reverseFill and true or false
        spark:ClearAllPoints()
        if isVert then
            spark:SetPoint("CENTER", anchor, rev and "BOTTOM" or "TOP", 0, 0)
        else
            spark:SetPoint("CENTER", anchor, rev and "LEFT" or "RIGHT", rev and 1 or -1, 0)
        end
        spark:Show()
    else
        spark:Hide()
    end

    -- Icon (the whole bar only): the art the bar's own icon shows.
    local icon = rec.icon
    rec.iconFile = PlainTexture(bar._icon and bar._icon._tex)
    if full and hasIcon then
        icon:SetSize(iSize, iSize)
        icon:ClearAllPoints()
        local pt = isVert and (iconMode == "left" and "TOPLEFT" or "BOTTOMLEFT")
            or (iconMode == "left" and "TOPLEFT" or "TOPRIGHT")
        icon:SetPoint(pt, root, pt, 0, 0)
        icon:SetFrameLevel(base + 5)
        if rec.iconFile then rec.iconTex:SetTexture(rec.iconFile) end
        icon:Show()
    else
        icon:Hide()
    end

    -- Border (the whole bar only): the secret-safe style on a host of an
    -- explicit size, as AuraKit borders its own buttons.
    local bh = rec.borderHost
    local bSz = (full and not blizzBar) and (cfg.borderSize or 0) or 0
    bh:ClearAllPoints()
    bh:SetPoint("CENTER", root, "CENTER", 0, 0)
    bh:SetSize(w, h)
    bh:SetFrameLevel(cfg.borderBehind and (base + 1) or (base + 6))
    if bSz > 0 then
        local textureKey = cfg.borderTexture or "solid"
        EllesmereUI.ApplySecretSafeBorderStyle(bh, rec, bSz,
            cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, 1,
            textureKey, cfg.borderTextureOffset, cfg.borderTextureOffsetY,
            cfg.borderTextureShiftX, cfg.borderTextureShiftY,
            "resourcebars", bSz, nil, EllesmereUI.BorderPx(cfg.borderSizePx, bSz, textureKey))
        rec.borderMade = true
        bh:Show()
    else
        if rec.borderMade then
            EllesmereUI.ApplySecretSafeBorderStyle(bh, rec, 0, 0, 0, 0, 0, "solid")
            rec.borderMade = nil
        end
        bh:Hide()
    end

    -- Texts.
    local th = rec.textHost
    th:ClearAllPoints()
    th:SetPoint("CENTER", root, "CENTER", 0, 0)
    th:SetSize(w, h)
    th:SetFrameLevel(base + 10)
    local nfs = rec.nameFS
    rec.nameText = PlainText(bar._nameText)
    local namePos = cfg.namePosition or ((cfg.showName ~= false) and "left" or "none")
    if full and namePos ~= "none" and not isVert then
        I.SetFont(nfs, cfg.nameSize or 11)
        I.SetTBBTextColor(nfs, cfg, "name")
        PlaceBarText(nfs, namePos, sb, cfg.nameX or 0, cfg.nameY or 0, false, false)
        if cfg.nameWrap then
            nfs:SetWordWrap(true)
            nfs:SetMaxLines(2)
            nfs:SetWidth(fw - 12 - (cfg.showTimer and 50 or 0))
        else
            nfs:SetWordWrap(false)
            nfs:SetMaxLines(1)
            nfs:SetWidth(fw * 0.85)
        end
        nfs:SetText(rec.nameText or "")
        nfs:Show()
    else
        nfs:Hide()
    end
    local tfs = rec.timerFS
    local timerPos = cfg.timerPosition or (cfg.showTimer and "right" or "none")
    if cfg.showTimer and timerPos ~= "none" then
        I.SetFont(tfs, cfg.timerSize or 11)
        I.SetTBBTextColor(tfs, cfg, "timer")
        PlaceBarText(tfs, timerPos, sb, cfg.timerX or 0, cfg.timerY or 0, isVert, true)
        tfs:Show()
    else
        tfs:Hide()
    end
    local sfs = rec.stacksFS
    local sPos = cfg.stacksPosition or "center"
    if sPos ~= "none" then
        I.SetFont(sfs, cfg.stacksSize or 11)
        I.SetTBBTextColor(sfs, cfg, "stacks")
        PlaceBarText(sfs, sPos, sb, cfg.stacksX or 0, cfg.stacksY or 0, isVert, false)
        sfs:Show()
    else
        sfs:Hide()
    end
end

-- The twin timer's registration options: the decimal formatter under Decimals
-- (tenths below its threshold), else the plain one; with neither (a client that
-- rejects them) the engine's own text.
local function TwinTimerOpts(decimals, thr)
    local fmt = decimals and GetDecimalFormatter(thr) or GetPlainFormatter()
    if not fmt then return {} end
    return AK.BuildDurationTextOpts(fmt, nil, decimals and 0.05 or 0.1)
end

-- The creation window: every region of the twin, the first paint, and the
-- engine bindings (the only moment the button takes our calls whatever the
-- aura restriction says). Armored by its caller.
local function InitTwin(rec, button, cfg, bar)
    local root = CreateFrame("Frame", nil, button)
    root:SetPoint("CENTER", button, "CENTER", 0, 0)
    root:SetSize(1, 1)
    rec.root = root
    rec.bg = root:CreateTexture(nil, "BACKGROUND")
    rec.blizzBg = root:CreateTexture(nil, "BACKGROUND")
    local sb = CreateFrame("StatusBar", nil, root)
    sb:SetMinMaxValues(0, 1)
    rec.sb = sb
    local clip = CreateFrame("Frame", nil, sb)
    clip:SetClipsChildren(true)
    clip:Hide()
    local gt = clip:CreateTexture(nil, "ARTWORK", nil, 1)
    gt:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
    gt:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 0, 0)
    rec.gradClip, rec.gradTex = clip, gt
    local sh = CreateFrame("Frame", nil, sb)
    sh:SetAllPoints(sb)
    local spark = sh:CreateTexture(nil, "OVERLAY", nil, 7)
    spark:SetSnapToPixelGrid(false)
    spark:SetTexelSnappingBias(0)
    rec.sparkHost, rec.spark = sh, spark
    local icon = CreateFrame("Frame", nil, root)
    local it = icon:CreateTexture(nil, "ARTWORK")
    it:SetAllPoints(icon)
    it:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    rec.icon, rec.iconTex = icon, it
    rec.borderHost = CreateFrame("Frame", nil, root)
    local th = CreateFrame("Frame", nil, root)
    rec.textHost = th
    rec.nameFS = th:CreateFontString(nil, "OVERLAY")
    rec.timerFS = th:CreateFontString(nil, "OVERLAY")
    rec.stacksFS = th:CreateFontString(nil, "OVERLAY")
    -- Fonted before registration: the engine writes every bound string.
    local SetFont = ns._buffBarInternals.SetFont
    SetFont(rec.nameFS, 11)
    SetFont(rec.timerFS, 11)
    SetFont(rec.stacksFS, 11)
    PaintTwin(rec, cfg, bar)

    local opts = {}
    if Enum.StatusBarInterpolation then
        opts.interpolation = TwinSmooth() and Enum.StatusBarInterpolation.ExponentialEaseOut
            or Enum.StatusBarInterpolation.Immediate
    end
    if Enum.StatusBarTimerDirection then opts.direction = Enum.StatusBarTimerDirection.RemainingTime end
    pcall(button.SetDurationBar, button, sb, opts)
    AK.SetDurationTextSafe(button, rec.timerFS, TwinTimerOpts(rec.decimals, rec.thr))
    pcall(button.SetApplicationCount, button, rec.stacksFS, {})
    rec.button = button
end

-- A timer twin (a bar Blizzard draws, Decimals on): the timer alone, where the
-- bar's own timer sits (PlaceBarText on the fill area), in its font and color,
-- over the bar's text (+9). Writes only, on our own frames.
local function PaintTimerTwin(rec, cfg, bar)
    local I = ns._buffBarInternals
    local w, h, isVert, _, _, _, fw, fh, ox, oy = TwinFootprint(cfg, bar)
    local base = bar:GetFrameLevel()
    rec.proxy:SetFrameLevel(base)
    if rec.container then rec.container:SetFrameLevel(base + 1) end
    local root, area = rec.root, rec.sb
    root:SetSize(w, h)
    root:SetFrameLevel(base + 2)
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", root, "TOPLEFT", ox, oy)
    area:SetSize(fw, fh)
    local th = rec.textHost
    th:ClearAllPoints()
    th:SetPoint("CENTER", root, "CENTER", 0, 0)
    th:SetSize(w, h)
    th:SetFrameLevel(base + 10)
    local tfs = rec.timerFS
    local timerPos = cfg.timerPosition or (cfg.showTimer and "right" or "none")
    if cfg.showTimer and timerPos ~= "none" then
        I.SetFont(tfs, cfg.timerSize or 11)
        I.SetTBBTextColor(tfs, cfg, "timer")
        PlaceBarText(tfs, timerPos, area, cfg.timerX or 0, cfg.timerY or 0, isVert, true)
        tfs:Show()
    else
        tfs:Hide()
    end
end

-- A timer twin's creation window: the engine FS, fonted before registration,
-- and its decimal binding (rec.bound). The window can run inside the container's
-- creation, before SyncTwins makes the twin its bar's, so bar._tbbEngineFS is set
-- here only for a twin that already is, else by SyncTwins: a bar whose binding
-- failed keeps the tick's whole-second passthrough. Armored by its caller.
local function InitTimerTwin(rec, button, cfg, bar)
    local fmt = GetDecimalFormatter(rec.thr)
    if not fmt then return end
    local root = CreateFrame("Frame", nil, button)
    root:SetPoint("CENTER", button, "CENTER", 0, 0)
    root:SetSize(1, 1)
    rec.root = root
    rec.sb = CreateFrame("Frame", nil, root)
    local th = CreateFrame("Frame", nil, root)
    rec.textHost = th
    rec.timerFS = th:CreateFontString(nil, "OVERLAY")
    ns._buffBarInternals.SetFont(rec.timerFS, 11)
    PaintTimerTwin(rec, cfg, bar)
    rec.button = button
    if AK.SetDurationTextSafe(button, rec.timerFS, AK.BuildDurationTextOpts(fmt, nil, 0.05)) then
        rec.bound = true
        if twinOf[bar] == rec then bar._tbbEngineFS = rec.timerFS end
    end
end

-- Place a twin over its bar (by number, on UIParent: an engine subtree never
-- joins the bar's frame tree or anchor family), restyle it when due, and give
-- it the bar's opacity while the tick has it on and the bar shows, else 0.
-- The proxy never shows or hides here (a frame that parents an engine
-- container cannot, in combat): alpha does it.
local function TwinPlace(rec)
    local bar, proxy = rec.bar, rec.proxy
    if not rec.container then return end
    local strata = bar:GetFrameStrata()
    if rec.strata ~= strata then
        rec.strata = strata
        proxy:SetFrameStrata(strata)
        -- A strata change collapses the child levels the paint sets.
        rec.needPaint = true
    end
    if rec.needPaint then
        rec.needPaint = nil
        local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
        local cfg = tbb and tbb.bars and tbb.bars[rec.index]
        if cfg and rec.root then
            local ok, err = pcall(rec.timerOnly and PaintTimerTwin or PaintTwin, rec, cfg, bar)
            if not ok then
                if AK.AurasRestricted and AK.AurasRestricted() then
                    rec.needPaint = true
                    twinWaitLift = true
                else
                    ReportTwinError(err)
                end
            end
        end
    end
    local a = 0
    if rec.on and bar:IsVisible() then
        local ok, l, b, w, h = pcall(bar.GetRect, bar)
        if ok and not (IsSecret(l) or IsSecret(b) or IsSecret(w) or IsSecret(h))
           and type(l) == "number" and type(b) == "number"
           and type(w) == "number" and type(h) == "number" and w > 0 then
            -- The holder takes the bar's scale, so the twin draws in the bar's
            -- own units (PaintTwin sizes it by the bar). It changes only out of
            -- combat (the holder parents an engine container); until then the
            -- placement converts for the scale it has.
            local s = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
            if proxy._k ~= s and not InCombatLockdown() then
                proxy._k = s
                proxy:SetScale(s)
                rec.pl = nil
            end
            local f = s / (proxy._k or 1)
            l, b, w, h = l * f, b * f, w * f, h * f
            if rec.pl ~= l or rec.pb ~= b or rec.pw ~= w or rec.ph ~= h then
                rec.pl, rec.pb, rec.pw, rec.ph = l, b, w, h
                proxy:ClearAllPoints()
                proxy:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
                proxy:SetSize(w, h)
            end
            local p = bar:GetParent()
            a = (bar._opacityTarget or 1) * (p and p:GetEffectiveAlpha() or 1)
        end
    end
    if rec.a ~= a then
        rec.a = a
        proxy:SetAlpha(a)
    end
end

local twinFollow = CreateFrame("Frame")
twinFollow:Hide()
twinFollow:SetScript("OnUpdate", function(self)
    self:Hide()
    for rec in pairs(twinDue) do
        twinDue[rec] = nil
        TwinPlace(rec)
    end
end)

local function Due(rec)
    twinDue[rec] = true
    twinFollow:Show()
end

-- Any bar moved, showed or hid: every twin is placed again a frame later (a
-- bar in a group hangs from the one before it, which moves it with no call of
-- its own).
local function OnTwinBarMoved()
    for _, rec in pairs(twins) do Due(rec) end
end

-- A bar's size changed: its twin is cut for the new size (and the bars after
-- it may have moved).
local function OnTwinBarSized(self)
    local rec = twinOf[self]
    if rec then rec.needPaint = true end
    OnTwinBarMoved()
end

-- Hooks on our own bar frames, once per frame: the twins follow their moves,
-- size and visibility one coalesced frame later.
local function Follow(bar)
    if twinHooked[bar] then return end
    twinHooked[bar] = true
    hooksecurefunc(bar, "SetPoint", OnTwinBarMoved)
    bar:HookScript("OnSizeChanged", OnTwinBarSized)
    bar:HookScript("OnShow", OnTwinBarMoved)
    bar:HookScript("OnHide", OnTwinBarMoved)
end

do
    local AKL = EllesmereUI.AuraKit
    if AKL and AKL.OnRestrictionLift then
        AKL.OnRestrictionLift(function()
            if not twinWaitLift then return end
            twinWaitLift = nil
            for _, rec in pairs(twins) do
                if rec.needPaint then Due(rec) end
            end
        end)
    end
end

local function BuildTwin(e, bar, cfg)
    local proxy = proxies[e.index]
    if not proxy then
        proxy = CreateFrame("Frame", nil, UIParent)
        proxy:SetSize(1, 1)
        proxy:EnableMouse(false)
        proxies[e.index] = proxy
    end
    proxy:SetAlpha(0)
    proxy:Show()
    local rec = { index = e.index, sig = e.tsig, proxy = proxy, bar = bar,
        thr = e.thr, decimals = e.decimals, timerOnly = e.timerOnly, on = false, a = 0 }
    local init = e.timerOnly and InitTimerTwin or InitTwin
    AK.styles[TWIN_STYLE] = AK.styles[TWIN_STYLE] or { width = 1, height = 1, noRegions = true }
    rec.container = AK.CreateContainer(proxy, "player", {
        point = { "CENTER", proxy, "CENTER", 0, 0 },
        slots = { {
            key = "twin",
            filter = { "HELPFUL" },
            candidateFilters = { includeSpellIDs = e.include },
            style = TWIN_STYLE,
            extraInit = function(button)
                -- Display-only: never a click or tooltip target.
                if button.SetMouseClickEnabled then button:SetMouseClickEnabled(false) end
                if button.SetMouseMotionEnabled then button:SetMouseMotionEnabled(false) end
                button:SetAllPoints(proxy)
                -- An uncaught error here aborts the engine's frame batch and
                -- kills the slot: caught, and reported after the batch.
                local ok, err = pcall(init, rec, button, cfg, bar)
                if not ok then ReportTwinError(err) end
            end,
        } },
    })
    return rec
end

local function ReleaseTwin(rec)
    if rec.container then
        AK.ReleaseContainer(rec.container)
        rec.container = nil
    end
    rec.a = 0
    rec.proxy:SetAlpha(0)
    if not InCombatLockdown() then rec.proxy:Hide() end
    twinDue[rec] = nil
    local bar = rec.bar
    if bar and twinOf[bar] == rec then
        twinOf[bar] = nil
        if rec.timerOnly then
            -- The bar's own timer takes over: never a stuck alpha-0 FS.
            if bar._tbbEngineFS == rec.timerFS then bar._tbbEngineFS = nil end
            if bar._tbbAlphaGated then
                if bar._timerText then bar._timerText:SetAlpha(1) end
                bar._tbbAlphaGated = nil
            end
        else
            bar._tbbEngineMode = nil
            bar._tbbIdleHidden = nil
            bar._tbbIdleSet = nil
        end
    end
end

-- One twin per wanted bar (CollectDesired): built again only when its signature
-- (ids, kind, smoothing) or its bar frame changes, restyled on every sync (the
-- settings may have changed), its timer formatter registered again when
-- Decimals or its threshold changed. True when a build had to wait for combat's
-- end (the bar keeps the tick's fallback until then).
local function SyncTwins(list)
    local tbb = ns.GetTrackedBuffBars and ns.GetTrackedBuffBars()
    local bars = tbb and tbb.bars
    wipe(twinWant)
    if list then
        for n = 1, #list do twinWant[list[n].index] = list[n] end
        -- Every bar's moves place the twins again (a twin's bar can hang from
        -- another bar): hooked once, from the first twin wanted.
        if bars then
            for i = 1, #bars do
                local f = ns.GetTBBFrame and ns.GetTBBFrame(i)
                if f then Follow(f) end
            end
        end
    end
    for idx, rec in pairs(twins) do
        local e = twinWant[idx]
        local bar = ns.GetTBBFrame and ns.GetTBBFrame(idx)
        if not e or e.tsig ~= rec.sig or bar ~= rec.bar then
            ReleaseTwin(rec)
            twins[idx] = nil
        end
    end
    local deferred = false
    for idx, e in pairs(twinWant) do
        local bar = ns.GetTBBFrame and ns.GetTBBFrame(idx)
        local cfg = bars and bars[idx]
        if bar and cfg then
            local rec = twins[idx]
            if not rec then
                if InCombatLockdown() then
                    deferred = true
                else
                    rec = BuildTwin(e, bar, cfg)
                    twins[idx] = rec
                end
            end
            if rec then
                twinOf[bar] = rec
                if rec.timerOnly then
                    if rec.bound then bar._tbbEngineFS = rec.timerFS end
                else
                    bar._tbbEngineMode = true
                    bar._tbbIdleSet = nil
                end
                if not rec.button then
                    -- Not set up yet: its setup registers what is wanted now.
                    rec.decimals, rec.thr = e.decimals, e.thr
                elseif rec.decimals ~= e.decimals or (e.decimals and rec.thr ~= e.thr) then
                    -- Stamped on success only: refused while auras are
                    -- restricted, retried by a later sync.
                    if AK.SetDurationTextSafe(rec.button, rec.timerFS,
                        TwinTimerOpts(e.decimals, e.thr)) then
                        rec.decimals, rec.thr = e.decimals, e.thr
                        if rec.timerOnly then
                            rec.bound = true
                            bar._tbbEngineFS = rec.timerFS
                        end
                    end
                end
                rec.needPaint = true
                Due(rec)
            end
        end
    end
    return deferred
end

-- The tick (EUI_CDM_BuffBarTick.lua): on = the bar is in its engine branch
-- (no Blizzard frame draws it, no target debuff fallback, no options preview).
-- The twin then shows over the bar whenever the engine has the aura up. A
-- changed name or icon on the bar restyles the twin.
function ns.TBBTwin_Set(bar, on)
    local rec = twinOf[bar]
    if not rec or rec.timerOnly then return end
    on = on and true or false
    if on and (PlainText(bar._nameText) ~= rec.nameText
        or PlainTexture(bar._icon and bar._icon._tex) ~= rec.iconFile) then
        rec.needPaint = true
    end
    if rec.on ~= on or rec.needPaint then
        rec.on = on
        Due(rec)
    end
end

-- The tick's timer switch for a timer twin (MirrorEngineTimer, ns.TBBEngineTimerOff
-- in EUI_CDM_BuffBarPresets.lua): on while it mirrors Blizzard's frame with the
-- timer shown, so the engine timer shows over the bar whenever the slot has the
-- aura; off in every other branch.
function ns.TBBTimerTwin_Set(bar, on)
    local rec = twinOf[bar]
    if not rec or not rec.timerOnly then return end
    on = on and true or false
    if rec.on ~= on then
        rec.on = on
        Due(rec)
    end
end

-- The tick asks for one more sync when an aura bar shows no Blizzard frame and
-- has no twin (Blizzard's frames, or its data, came after the last rebuild):
-- once per bar per rebuild, out of combat, a frame later.
local syncGen = 0
local asked = setmetatable({}, { __mode = "k" })  -- bar -> the rebuild it asked in
local requestQueued
local function RunRequestedSync()
    requestQueued = nil
    ns.TBBDecimals_Sync(true)
end
function ns.TBBDecimals_RequestSync(bar)
    -- Counted as asked only once the answer can be told (ViewerReady), so an
    -- ask made before Blizzard's frames exist comes back on a later pass.
    if asked[bar] == syncGen or InCombatLockdown() or not ViewerReady() then return end
    asked[bar] = syncGen
    if requestQueued then return end
    requestQueued = true
    C_Timer.After(0, RunRequestedSync)
end

-- requested: the tick's extra sync (above), which does not count as a rebuild.
function ns.TBBDecimals_Sync(requested)
    AK = AK or (EllesmereUI and EllesmereUI.AuraKit)
    if not AK then return end
    if not requested then syncGen = syncGen + 1 end

    -- Every bar that wants one gets a twin of its own: the whole bar (engine
    -- mode) or its timer (Decimals on a bar Blizzard draws). A build combat
    -- held back runs at regen.
    if SyncTwins(CollectDesired()) and not pendingRegen then
        pendingRegen = true
        ns.CombatQueue.Defer("TBBDecimalsSync", SyncAfterCombat)
    end
end

