if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_ResourceBars_MirrorTimer.lua
-- Mirror Timers: the Breath, Fatigue and Feign Death bars, on EUI's own frames.
--
-- Blizzard calls them mirror timers (Blizzard_MirrorTimer): started by
-- MIRROR_TIMER_START(timer, value, maxValue, scale, paused, label), paused by
-- MIRROR_TIMER_PAUSE(timer, paused) and ended by MIRROR_TIMER_STOP(timer).
-- The value moves by scale per second (-1 draining, above 0 refilling, as a
-- breath bar once the player surfaces); a change of course comes as a new
-- MIRROR_TIMER_START. Each start or pause hands the bar to the engine (a
-- duration object: SetTimerDuration for the fill, a text binding for the
-- seconds): nothing of ours runs while a bar moves.
--
-- One bar per timer: Breath (BREATH), Fatigue (EXHAUSTION), Feign Death
-- (FEIGNDEATH, and DEATH, which Blizzard paints the same way), Battle Start
-- and Group Countdown (the game's countdowns, see KINDS). They are set in the
-- OTHER BARS section of the Cast Bar page: a switch and a fill colour each,
-- and in its cog the Low Warning.
--
-- Low Warning (optional, per bar): once a draining bar is down to Warn When
-- Left, its fill turns red and blinks; a refilling bar never warns. A one-shot
-- timer set at each start fires it, and the blink is an animation the engine
-- plays.
--
-- One Unlock Mode mover (Other Bars) places them all: the bars up at once
-- stack under it, one under the other in KINDS order, and close up as one
-- ends. In Unlock Mode every bar turned on shows a sample in the stack.
--
-- The look is the Player Cast Bar's: size, border, texture, background,
-- spark, corners, its Spell Text as the timer's name and its Duration Text as
-- the seconds left, and its style.
--
-- Blizzard's own bar for a timer is hidden while ours for that timer is on
-- (alpha 0 for a mirror timer, never a reparent or an unregister; the
-- countdown bar of TimerTracker is hidden, its golden numbers stay). Off by
-- default: nothing is built, registered or hidden until a bar is turned on.
--

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

if not (GetMirrorTimerProgress and GetMirrorTimerInfo) then return end

-- id: the settings table under profile.mirrorTimer; timers: the client's
-- timer names this bar shows; name: its name in the options; sampleFrac:
-- the fill the Unlock Mode sample shows.
local KINDS = {
    { id = "breath", name = "Breath", sampleFrac = 0.7,
      timers = { BREATH = true }, clientLabel = "BREATH_LABEL" },
    { id = "fatigue", name = "Fatigue", sampleFrac = 0.45,
      timers = { EXHAUSTION = true }, clientLabel = "EXHAUSTION_LABEL" },
    { id = "feign", name = "Feign Death", sampleFrac = 0.6,
      timers = { FEIGNDEATH = true, DEATH = true }, spell = 5384 },
}
-- The game's TimerTracker bars, counted from the event's end time (no mirror
-- timer behind them). Battle Start: the battleground's countdown before the
-- gates open (START_TIMER with the PvP begin type; a world change drops it).
-- Group Countdown: a group leader's /countdown (START_PLAYER_COUNTDOWN,
-- CANCEL_PLAYER_COUNTDOWN), which lives through a world change.
-- numbersAt: the seconds left where the game swaps its bar for its golden
-- numbers (its TimerTracker's mediumMarker for that type); ours steps aside
-- there too, so they show alone, as in the default UI.
local START_TYPES = Enum.StartTimerType
local START_KIND = {}  -- timer type -> kind
if START_TYPES and START_TYPES.PvPBeginTimer then
    KINDS[#KINDS + 1] = { id = "pvp", name = "Battle Start", sampleFrac = 0.55,
        timers = {}, startType = START_TYPES.PvPBeginTimer, numbersAt = 11 }
end
if START_TYPES and START_TYPES.PlayerCountdown then
    KINDS[#KINDS + 1] = { id = "countdown", name = "Group Countdown",
        sampleFrac = 0.5, timers = {}, startType = START_TYPES.PlayerCountdown, keepOnWorld = true,
        numbersAt = 31 }
end
for _, K in ipairs(KINDS) do
    if K.startType then START_KIND[K.startType] = K end
end
-- The name the client itself gives the timer (its bar label: BREATH_LABEL,
-- EXHAUSTION_LABEL; Feign Death has none, so the spell's name), so the
-- options, samples and mover say what the live bar says. Falls back to the
-- English name through the locale table.
local function KindName(K)
    local s = K.clientLabel and _G[K.clientLabel]
    if type(s) == "string" and s ~= "" then return s end
    if K.spell then
        local n = C_Spell.GetSpellName(K.spell)
        if type(n) == "string" and n ~= "" then return n end
    end
    return EllesmereUI.L(K.name)
end
local KIND_OF = {}     -- client timer name -> kind
for _, K in ipairs(KINDS) do
    for timer in pairs(K.timers) do KIND_OF[timer] = K end
end
ns.MT_KINDS = KINDS

-- The one inert frame at FILE SCOPE (attribution rule, see _erbEventFrame in
-- the main file): its OnEvent bills ResourceBars. The bars are made on first
-- enable.
local eventFrame = CreateFrame("Frame")

local S = { barHidden = setmetatable({}, { __mode = "k" }) }  -- events, blizzHidden, unlockHooked
local UNLOCK_KEY = "ERB_MirrorBars"
ns.MT_UNLOCK_KEY = UNLOCK_KEY
local STACK_GAP = 3     -- between two bars, past what their borders reach out
local holder            -- the stack's frame (ours), made on first enable

local IMMEDIATE = Enum.StatusBarInterpolation.Immediate
local ELAPSED   = Enum.StatusBarTimerDirection.ElapsedTime
local REMAINING = Enum.StatusBarTimerDirection.RemainingTime
local FROZEN    = 1e6   -- seconds: a duration this long stands still (a paused bar, a sample)

-------------------------------------------------------------------------------
--  Settings access
-------------------------------------------------------------------------------

local function Profile()
    local ERB = ns.ERB
    return ERB and ERB.db and ERB.db.profile
end

local function Cfg(id)
    local p = Profile()
    local m = p and p.mirrorTimer
    return m and m[id] or nil
end

-- The stack's saved position: the mirrorTimer table's own unlockPos.
local function StackCfg()
    local p = Profile()
    return p and p.mirrorTimer or nil
end

-- What every bar is drawn with: the Player Cast Bar's settings.
local function View()
    local p = Profile()
    return p and p.castBar
end

-- A restricted answer is no answer: the bar keeps what it last showed.
local IsSecret = EllesmereUI.IsSecret

-------------------------------------------------------------------------------
--  One bar: build and look
-------------------------------------------------------------------------------

-- Builds the children of obj.frame (obj: a KINDS entry).
local function BuildBar(obj)
    local f = obj.frame
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    obj.bg = bg

    local bdr = CreateFrame("Frame", nil, f)
    bdr:SetAllPoints(f)
    bdr:SetFrameLevel(f:GetFrameLevel() + 5)
    obj.border = bdr
    EllesmereUI.PP.CreateBorder(bdr, 0, 0, 0, 1, 1)

    local clip = CreateFrame("Frame", nil, f)
    clip:SetClipsChildren(true)
    obj.clip = clip

    local bar = CreateFrame("StatusBar", nil, clip)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    obj.bar = bar

    local sparkFrame = CreateFrame("Frame", nil, clip)
    sparkFrame:SetAllPoints(bar)
    sparkFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
    local spark = sparkFrame:CreateTexture(nil, "OVERLAY", nil, 1)
    spark:SetTexture(ns.SPARK_TEX)
    spark:SetBlendMode("ADD")
    obj.spark = spark

    -- Stock-style chrome (the cast bar's look, see StockStyle below): its own
    -- host above the fill, under the texts. Two handles: the Blizzard Style
    -- frame art, and the Classic WoW UI frame (its pieces ride the host).
    local art = CreateFrame("Frame", nil, f)
    art:SetAllPoints(f)
    art:EnableMouse(false)
    obj.art = art
    local frameTex = art:CreateTexture(nil, "OVERLAY", nil, 2)
    frameTex:SetSnapToPixelGrid(false); frameTex:SetTexelSnappingBias(0)
    frameTex:Hide()
    obj.frameTex = frameTex
    obj.classicTex = art:CreateTexture(nil, "OVERLAY", nil, 1)
    obj.classicTex:Hide()

    local textFrame = CreateFrame("Frame", nil, f)
    textFrame:SetAllPoints(f)
    textFrame:SetFrameLevel(bar:GetFrameLevel() + 3)
    obj.textFrame = textFrame
    -- Font before any SetText (a FontString with no font errors on SetText).
    local label = textFrame:CreateFontString(nil, "OVERLAY")
    ns.SetRBFont(label, ns.GetRBFont(), 11)
    label:SetWordWrap(false)
    label:SetText("")
    obj.label = label
    local time = textFrame:CreateFontString(nil, "OVERLAY")
    ns.SetRBFont(time, ns.GetRBFont(), 11)
    time:SetWordWrap(false)
    time:SetText("")
    obj.time = time

    -- The engine runs the fill and the seconds from one duration object.
    obj.dur = C_DurationUtil.CreateDuration()
    local binding = C_DurationUtil.CreateDurationTextBinding()
    binding:SetFontString(time)
    binding:SetDuration(obj.dur)
    -- m:ss up to 6 minutes (Breath can run 3, Feign Death 6), as the game's bar.
    local fmt = EllesmereUI.AuraKit.GetDurationFormatter(false, 360)
    if fmt then binding:SetFormatter(fmt) end
    binding:SetEnabled(false)
    obj.binding = binding

    -- Low Warning's blink: the fill and spark fade in and out, played by the
    -- engine.
    local pulse = clip:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.3)
    obj.pulse = pulse
    obj.built = true
end

-- A text on its side of the bar: left, right or center (none hides it).
local function PlaceText(fs, f, side, size, x, y, r, g, b, a)
    if side == "none" then fs:Hide(); return end
    ns.SetRBFont(fs, ns.GetRBFont(), size)
    fs:ClearAllPoints()
    if side == "center" then
        fs:SetPoint("CENTER", f, "CENTER", x, y)
        fs:SetJustifyH("CENTER")
    elseif side == "right" then
        fs:SetPoint("RIGHT", f, "RIGHT", -4 + x, y)
        fs:SetJustifyH("RIGHT")
    else
        fs:SetPoint("LEFT", f, "LEFT", 4 + x, y)
        fs:SetJustifyH("LEFT")
    end
    fs:SetTextColor(r, g, b, a)
    fs:Show()
end

-- The cast bar's style drives these bars too (Global Settings > Style, the
-- Player Cast Bar entry): "eui", "blizzard" (WoW Forever included: the
-- client's own frame art) or "classic". Latched per session like the cast
-- bar, so a switch takes a reload.
local function StockStyle()
    return (ns.ERB_CastStyle and ns.ERB_CastStyle()) or "eui"
end

-- Size, border, texture, background, spark and texts from cfg (the cast
-- bar's settings), and the fill colour from own (the bar's own settings).
local function ApplyLook(obj, cfg, own)
    local f = obj.frame
    local style = StockStyle()
    local stock = style ~= "eui"
    local blizzKit = style == "blizzard"
    -- No EUI border under a stock style: its frame art is the border.
    local bs = (not stock and cfg.borderSize) or 0
    local bdr = obj.border
    local pl = f:GetFrameLevel()
    bdr:SetFrameLevel(cfg.borderBehind and math.max(0, pl - 1) or (pl + 5))
    EllesmereUI.ApplyBorderStyle(bdr, bs,
        cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, cfg.borderA or 1,
        cfg.borderTexture or "solid", cfg.borderTextureOffset, cfg.borderTextureOffsetY,
        cfg.borderTextureShiftX, cfg.borderTextureShiftY, "resourcebars", bs,
        nil, EllesmereUI.BorderPx(cfg.borderSizePx, bs, cfg.borderTexture or "solid"))

    -- The 1px inset keeps the fill from bleeding past the border.
    local clip, bar = obj.clip, obj.bar
    local inset = (bs > 0 and EllesmereUI.PP.mult) or 0
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    clip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    clip:SetFrameLevel(pl + 1)
    bar:ClearAllPoints()
    bar:SetAllPoints(clip)
    local fillAtlas = blizzKit and ns.ERB_BlizzAtlas and ns.ERB_BlizzAtlas("cast")
    if fillAtlas then
        -- Blizzard Style: the stock fill art, greyed so the bar's own colour
        -- tints it and Breath stays blue.
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        bar:GetStatusBarTexture():SetAtlas(fillAtlas)
        bar:GetStatusBarTexture():SetDesaturated(true)
    else
        bar:SetStatusBarTexture(EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, cfg.texture, "Interface\\Buttons\\WHITE8x8"))
        bar:GetStatusBarTexture():SetDesaturated(false)
    end
    bar:SetOrientation("HORIZONTAL")
    bar:SetReverseFill(false)
    bar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
    bar:SetStatusBarColor(own.fillR or 1, own.fillG or 1, own.fillB or 1, own.fillA or 1)
    local bgAtlas = blizzKit and ns.ERB_BlizzAtlas and ns.ERB_BlizzAtlas("bg")
    obj.bg:ClearAllPoints()
    if bgAtlas then
        -- The retail background under WoW Forever too, as the cast bar.
        EllesmereUI.StockAtlas(obj.bg, bgAtlas)
        obj.bg:SetVertexColor(1, 1, 1, 1)
        obj.bg:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
        obj.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
    else
        obj.bg:SetTexture(nil)
        obj.bg:SetColorTexture(cfg.bgR or 0, cfg.bgG or 0, cfg.bgB or 0, cfg.bgA or 0.7)
        obj.bg:SetAllPoints(f)
    end

    -- Frame art: above the fill and spark, under the texts. Its seat, the
    -- timer's nudge and the spark's size are the cast bar's own (the parent's
    -- numbers; a timer bar has no icon beside it).
    local h = cfg.height or 20
    obj.art:SetFrameLevel(pl + 6)
    obj.textFrame:SetFrameLevel(pl + 8)
    local reachL, reachR, reachT, _, timerNudge, sparkExtraH, sparkNudge, sparkW =
        EllesmereUI.CastChromeGeom(blizzKit and ns.ERB_CastForever() or false)
    local frameAtlas = blizzKit and ns.ERB_BlizzAtlas and ns.ERB_BlizzAtlas("frame")
    if frameAtlas then
        ns.ERB_StockAtlas(obj.frameTex, frameAtlas)
        obj.frameTex:ClearAllPoints()
        obj.frameTex:SetPoint("TOPLEFT", f, "TOPLEFT", -reachL, reachT)
        obj.frameTex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", reachR, -2)
        obj.frameTex:Show()
    else
        obj.frameTex:Hide()
    end
    if style == "classic" and ns.ERB_SeatClassicChrome then
        ns.ERB_SeatClassicChrome(obj.classicTex, f, h, false, ns.ERB_ClassicFrameK(cfg))
    end

    local spark = obj.spark
    local sparkY = 0
    if blizzKit and not obj.blizzSpark then
        local pip = ns.ERB_BlizzAtlas and ns.ERB_BlizzAtlas("spark")
        if pip then
            obj.blizzSpark = true
            spark:SetAtlas(pip)
            spark:SetBlendMode("BLEND")
        end
    elseif style == "classic" and not obj.classicSpark then
        -- The vanilla spark stands taller than the bar and over the frame
        -- art: its host leaves the clip for the bar frame.
        obj.classicSpark = true
        spark:SetTexture(ns.ERB_CLASSIC.spark)
        local sf = spark:GetParent()
        sf:SetParent(f)
        sf:ClearAllPoints()
        sf:SetAllPoints(bar)
    end
    if style == "classic" then spark:GetParent():SetFrameLevel(pl + 7) end
    if cfg.showSpark then
        spark:ClearAllPoints()
        if style == "classic" then
            local C = ns.ERB_CLASSIC
            local ss = C.sparkSize * h / C.barH
            spark:SetSize(ss, ss)
            sparkY = C.sparkY * h / C.barH
        else
            spark:SetSize(sparkW, h + sparkExtraH)
            sparkY = sparkNudge
        end
        spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, sparkY)
        spark:Show()
    else
        spark:Hide()
    end

    -- The cast bar's Spell Text names the timer, its Duration Text counts it.
    local labelSide = (cfg.showSpellText == false) and "none" or (cfg.spellTextSide or "left")
    local timeSide = (cfg.showTimer == false) and "none" or (cfg.timerSide or "right")
    PlaceText(obj.label, f, labelSide, cfg.spellTextSize or 11, cfg.spellTextX or 0, cfg.spellTextY or 0,
        cfg.spellTextR or 1, cfg.spellTextG or 1, cfg.spellTextB or 1, cfg.spellTextA or 1)
    PlaceText(obj.time, f, timeSide, cfg.timerSize or 11, cfg.timerX or 0, (cfg.timerY or 0) + timerNudge,
        cfg.timerR or 1, cfg.timerG or 1, cfg.timerB or 1, cfg.timerA or 1)

    -- Rounded corners (EllesmereUI_RoundedCorners.lua; nothing at radius 0).
    -- The body is the clip (fill + spark) and the background.
    local radius = (not stock and cfg.cornerRadius) or 0
    if radius > 0 then
        EllesmereUI.RoundCorners(f, radius, {
            roots = { clip }, textures = { obj.bg },
            border = bdr, clip = clip,
            style = cfg.borderTexture or "solid", corners = cfg.cornerMask,
        })
    else
        EllesmereUI.RoundCorners(f, 0)
    end
end

-------------------------------------------------------------------------------
--  Fill and seconds: handed to the engine
-------------------------------------------------------------------------------

local function SecondsText(s)
    s = math.max(0, math.floor(s + 0.5))
    if s >= 60 then return string.format("%d:%02d", math.floor(s / 60), s % 60) end
    return tostring(s)
end

-- A bar standing still at frac, with seconds on it: a paused timer, or the
-- Unlock Mode sample.
local function Hold(obj, frac, seconds)
    frac = math.max(0, math.min(frac, 1))
    obj.dur:SetTimeFromStart(GetTime() - frac * FROZEN, FROZEN)
    obj.bar:SetTimerDuration(obj.dur, IMMEDIATE, ELAPSED)
    obj.binding:SetEnabled(false)
    obj.time:SetText(SecondsText(seconds))
end

-- A moving bar: left seconds to go out of total from now, draining, or
-- filling up when rising (a breath bar refilling: its seconds are the time
-- to full).
local function Run(obj, left, total, rising)
    local now = GetTime()
    if rising then
        obj.dur:SetTimeFromStart(now - (total - left), total)
        obj.bar:SetTimerDuration(obj.dur, IMMEDIATE, ELAPSED)
    else
        obj.dur:SetTimeFromEnd(now + left, total)
        obj.bar:SetTimerDuration(obj.dur, IMMEDIATE, REMAINING)
    end
    obj.binding:SetEnabled(true)
end

local WARN_R, WARN_G, WARN_B = 1, 0.1, 0.1

-- Low Warning on (red, blinking unless blink is false) or off (the fill colour).
local function Warn(K, on, blink)
    local cfg = Cfg(K.id)
    if on then
        K.bar:SetStatusBarColor(WARN_R, WARN_G, WARN_B, cfg and cfg.fillA or 1)
    elseif cfg then
        K.bar:SetStatusBarColor(cfg.fillR or 1, cfg.fillG or 1, cfg.fillB or 1, cfg.fillA or 1)
    end
    if on and blink ~= false then
        if not K.pulse:IsPlaying() then K.pulse:Play() end
    else
        K.pulse:Stop()
    end
end

-- Arms Low Warning for a draining bar at frac of its total (seconds), moving
-- unless paused: on now if already down to Warn When Left, else a one-shot
-- timer for when it gets there. No frac: no warning.
local function ArmWarn(K, frac, total, paused)
    if K.warnTimer then K.warnTimer:Cancel(); K.warnTimer = nil end
    local cfg = Cfg(K.id)
    local at = cfg and cfg.lowWarn and (cfg.lowWarnAt or 30) / 100 or 0
    if not (frac and at > 0) then return Warn(K, false) end
    if frac <= at then return Warn(K, true, not paused) end
    Warn(K, false)
    if not paused then K.warnTimer = C_Timer.NewTimer((frac - at) * total, K.warnNow) end
end

-- Where a live mirror timer (a: value read at a.at) stands now: the game's
-- answer, as its own bar reads it each frame, else, for a moving timer, where
-- its rate has carried it since the last reading.
local function Reading(a, moving)
    local now = GetTime()
    if a.at == now then return end
    local cur = GetMirrorTimerProgress(a.timer)
    if not IsSecret(cur) and type(cur) == "number" then
        a.value = cur
    elseif moving then
        a.value = a.value + a.scale * 1000 * (now - a.at)
    end
    a.at = now
end

-- The bar's state: its sample in Unlock Mode, else its live timer.
local function Show(K)
    if K.sample then
        K.label:SetText(KindName(K))
        Hold(K, K.sampleFrac, 60 * K.sampleFrac)
        return ArmWarn(K)
    end
    local a = K.active
    if not a then return ArmWarn(K) end
    K.label:SetText(a.label or "")
    if a.endTime then
        local left = a.endTime - GetTime()
        Run(K, left, a.total)
        return ArmWarn(K, left / a.total, a.total)
    end
    -- value and max in ms, moving by scale per second. This also runs on every
    -- settings apply, long after the event that brought the value.
    Reading(a, not a.paused)
    local max = a.max > 0 and a.max or 1
    local v = math.max(0, math.min(a.value, max))
    local rate = a.scale
    if a.paused or rate == 0 then
        Hold(K, v / max, v / 1000)
        ArmWarn(K, v / max, 0, true)
    elseif rate < 0 then
        Run(K, v / 1000 / -rate, max / 1000 / -rate)
        ArmWarn(K, v / max, max / 1000 / -rate)
    else
        Run(K, (max - v) / 1000 / rate, max / 1000 / rate, true)
        ArmWarn(K)   -- refilling: never warns
    end
end

-------------------------------------------------------------------------------
--  The stack
-------------------------------------------------------------------------------

-- The bars up (K.up) one under the other from the holder's top, in KINDS
-- order. The holder is as wide as the cast bar and as tall as the bars
-- turned on stacked, the mover's size in Unlock Mode.
local function Gap(view)
    local _, padH = ns.ERB_EuiBorderPad(view)
    return (padH or 0) + STACK_GAP
end

local function StackSize()
    local view = View()
    local w, hb = (view and view.width) or 220, (view and view.height) or 20
    local n = 0
    for _, K in ipairs(KINDS) do
        local cfg = Cfg(K.id)
        if cfg and cfg.enabled then n = n + 1 end
    end
    if n == 0 or not view then return w, hb end
    return w, n * hb + (n - 1) * Gap(view)
end

local function Layout()
    local view = View()
    if not (holder and view) then return end
    local y, step = 0, (view.height or 20) + Gap(view)
    for _, K in ipairs(KINDS) do
        if K.built and K.up then
            K.frame:ClearAllPoints()
            K.frame:SetPoint("TOP", holder, "TOP", 0, -y)
            y = y + step
        end
    end
end

-- Position: the unlock anchor chain first, then the saved unlock position,
-- then CENTER 0, 300.
local function PlaceStack()
    if not holder then
        holder = CreateFrame("Frame", "ERB_MirrorBars", UIParent)
        holder:EnableMouse(false)
    end
    holder:SetSize(StackSize())
    if EllesmereUI._TryOverrideAnchor and EllesmereUI._TryOverrideAnchor(UNLOCK_KEY, holder) then
        return
    end
    if EllesmereUI._unlockActive then return end
    local m = StackCfg()
    local pos = m and m.unlockPos
    if pos and pos.point then
        local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(UNLOCK_KEY)
        if anchored and holder:GetLeft() then return end
        local sx, sy = ns.SnapXY(pos.x or 0, pos.y or 0, holder, pos)
        holder:ClearAllPoints()
        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, sx, sy)
    else
        holder:ClearAllPoints()
        holder:SetPoint("CENTER", UIParent, "CENTER", 0, 300)
    end
end

local function UpdateVisibility(K)
    if not K.built then return end
    local cfg = Cfg(K.id)
    local on = cfg and cfg.enabled and (K.sample or (K.active and not K.active.underNumbers)) and true or false
    if K.up ~= on then
        K.up = on
        Layout()
    end
    EllesmereUI.SetElementVisibility(K.frame, on)
end

-- Blizzard's bar for each timer: hidden while ours for that timer is on,
-- shown again otherwise. Its frames are handed out to timers as they start,
-- so this runs one frame after every start, once Blizzard's own handler has
-- given the frame its timer.
local function ApplyBlizzard()
    -- No bar of ours on and nothing of Blizzard's hidden by us: nothing to do.
    if not (S.events or S.blizzHidden or next(S.barHidden)) then return end
    local blizz = _G.MirrorTimerContainer
    local list = blizz and blizz.mirrorTimers
    local any = false
    if list then
        for _, tf in ipairs(list) do
            local K = tf.timer and KIND_OF[tf.timer]
            local cfg = K and Cfg(K.id)
            if cfg and cfg.enabled then
                tf:SetAlpha(0)
                any = true
            elseif S.blizzHidden then
                tf:SetAlpha(1)
            end
        end
    end
    S.blizzHidden = any or nil
    -- The TimerTracker countdown bars: the bar itself hidden (its fades only
    -- move its alpha; nothing of Blizzard's shows it again), the golden
    -- numbers beside it untouched.
    local tracker = _G.TimerTracker
    list = tracker and tracker.timerList
    if not list then return end
    for _, timer in ipairs(list) do
        local K = timer.type and START_KIND[timer.type]
        local cfg = K and Cfg(K.id)
        local bar = timer.bar
        if bar and cfg and cfg.enabled and K.active then
            bar:Hide()
            S.barHidden[bar] = true
        elseif bar and S.barHidden[bar] then
            bar:Show()
            S.barHidden[bar] = nil
        end
    end
end

-------------------------------------------------------------------------------
--  The live timers
-------------------------------------------------------------------------------

local function Clear(K)
    K.active = nil
    if K.stepTimer then K.stepTimer:Cancel(); K.stepTimer = nil end
    ArmWarn(K)
    UpdateVisibility(K)
end

local function IsPaused(v)
    return v == true or (type(v) == "number" and v > 0)
end

local function StartTimer(timer, value, maxValue, scale, paused, label)
    if IsSecret(timer) or IsSecret(value) or IsSecret(maxValue) or IsSecret(scale) or IsSecret(paused) or IsSecret(label) then return end
    local K = type(timer) == "string" and KIND_OF[timer]
    if not K or type(maxValue) ~= "number" or type(value) ~= "number" then return end
    local cfg = Cfg(K.id)
    if not (cfg and cfg.enabled and K.built) then return end
    -- at: when value was read (Show reads it again on a later pass).
    K.active = { timer = timer, value = value, at = GetTime(), max = maxValue, scale = tonumber(scale) or -1,
                 label = label, paused = IsPaused(paused) }
    Show(K)
    UpdateVisibility(K)
end

-- A pause freezes the bar where the timer stands; a resume runs it again
-- from there.
local function PauseTimer(timer, paused)
    local K = not IsSecret(timer) and type(timer) == "string" and KIND_OF[timer]
    local a = K and K.active
    if not a or a.timer ~= timer or IsSecret(paused) then return end
    Reading(a, not a.paused)
    a.paused = IsPaused(paused)
    Show(K)
end

local function StopTimer(timer)
    local K = not IsSecret(timer) and type(timer) == "string" and KIND_OF[timer]
    if K and K.active and K.active.timer == timer then Clear(K) end
end

-- The countdown reaches the game's golden numbers: ours steps aside.
local function StepAside(K)
    K.stepTimer = nil
    if K.active then
        K.active.underNumbers = true
        UpdateVisibility(K)
    end
end

-- A TimerTracker countdown of type timerType: seconds left out of total.
local function StartCountdown(timerType, seconds, total)
    local K = not IsSecret(timerType) and START_KIND[timerType]
    if not K or IsSecret(seconds) or IsSecret(total) then return end
    if type(seconds) ~= "number" or type(total) ~= "number" then return end
    if total <= 0 or seconds <= 0 then  -- a cancelled countdown comes as 0, 0
        if K.active then Clear(K); ApplyBlizzard() end
        return
    end
    local cfg = Cfg(K.id)
    if not (cfg and cfg.enabled and K.built) then return end
    if K.stepTimer then K.stepTimer:Cancel(); K.stepTimer = nil end
    local wait = seconds - K.numbersAt
    K.active = { endTime = GetTime() + seconds, total = total, label = KindName(K),
                 underNumbers = wait <= 0 }
    if wait > 0 then K.stepTimer = C_Timer.NewTimer(wait, K.stepAside) end
    Show(K)
    UpdateVisibility(K)
end

local function StopCountdown(timerType)
    local K = not IsSecret(timerType) and START_KIND[timerType]
    if not (K and K.active) then return end
    Clear(K)
    ApplyBlizzard()
end

-- The timers already running when a bar comes up (a /reload under water).
local function Resync()
    for _, K in ipairs(KINDS) do
        if not K.keepOnWorld and K.active then Clear(K) end
    end
    for i = 1, 3 do
        local timer, _, maxValue, scale, paused, label = GetMirrorTimerInfo(i)
        if timer and not IsSecret(timer) and timer ~= "UNKNOWN" then
            StartTimer(timer, GetMirrorTimerProgress(timer), maxValue, scale, paused, label)
        end
    end
    for _, K in ipairs(KINDS) do UpdateVisibility(K) end
end

eventFrame:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5, a6)
    if event == "MIRROR_TIMER_START" then
        -- timer, value, maxValue, scale, paused, label
        StartTimer(a1, a2, a3, a4, a5, a6)
        C_Timer.After(0, ApplyBlizzard)
    elseif event == "MIRROR_TIMER_PAUSE" then
        PauseTimer(a1, a2)
    elseif event == "MIRROR_TIMER_STOP" then
        StopTimer(a1)
        -- Blizzard's frame for that timer is free again (Edit Mode shows it as a
        -- sample): its alpha goes back once Blizzard's own handler has let it go.
        if S.blizzHidden then C_Timer.After(0, ApplyBlizzard) end
    elseif event == "START_TIMER" then
        StartCountdown(a1, a2, a3)
        C_Timer.After(0, ApplyBlizzard)
    elseif event == "START_PLAYER_COUNTDOWN" then
        -- initiatedByGuid, timeSeconds, totalTime, informChat, initiatedByName
        StartCountdown(START_TYPES.PlayerCountdown, a2, a3)
        C_Timer.After(0, ApplyBlizzard)
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        StopCountdown(START_TYPES.PlayerCountdown)
    elseif event == "STOP_TIMER_OF_TYPE" then
        StopCountdown(a1)
    else -- PLAYER_ENTERING_WORLD (the game drops the battleground countdown too)
        Resync()
        C_Timer.After(0, ApplyBlizzard)
    end
end)

-------------------------------------------------------------------------------
--  Apply
-------------------------------------------------------------------------------

local function ApplyKind(K, view)
    local cfg = Cfg(K.id)
    if not (cfg and cfg.enabled) then
        if K.built then Clear(K) end
        return false
    end
    if not K.built then
        K.frame = CreateFrame("Frame", "ERB_Mirror_" .. K.id, UIParent)
        K.frame:SetFrameLevel(15)
        K.stepAside = function() StepAside(K) end
        K.warnNow = function() K.warnTimer = nil; Warn(K, true) end
        BuildBar(K)
    end
    K.frame:SetFrameStrata(view.frameStrata or "MEDIUM")
    K.frame:SetSize(view.width or 220, view.height or 20)
    ApplyLook(K, view, cfg)
    Show(K)
    UpdateVisibility(K)
    return true
end

function ns.MT_Apply()
    local view = View()
    if not view then return end
    local any = false
    for _, K in ipairs(KINDS) do
        if ApplyKind(K, view) then any = true end
    end
    if any then
        PlaceStack()
        Layout()   -- the cast bar's height may have changed
    end
    if any and not S.events then
        S.events = true
        eventFrame:RegisterEvent("MIRROR_TIMER_START")
        eventFrame:RegisterEvent("MIRROR_TIMER_PAUSE")
        eventFrame:RegisterEvent("MIRROR_TIMER_STOP")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        if next(START_KIND) then
            eventFrame:RegisterEvent("START_TIMER")
            eventFrame:RegisterEvent("STOP_TIMER_OF_TYPE")
        end
        if START_TYPES and START_TYPES.PlayerCountdown then
            eventFrame:RegisterEvent("START_PLAYER_COUNTDOWN")
            eventFrame:RegisterEvent("CANCEL_PLAYER_COUNTDOWN")
        end
        Resync()
    elseif not any and S.events then
        S.events = nil
        eventFrame:UnregisterAllEvents()
    end
    ApplyBlizzard()
end

-------------------------------------------------------------------------------
--  Unlock element: one mover for the whole stack
-------------------------------------------------------------------------------

function ns.MT_MakeUnlockElements(MK)
    if not MK then return nil end

    if not S.unlockHooked then
        S.unlockHooked = true
        EllesmereUI:RegisterUnlockModeListener("ERB_Mirror", function(active)
            -- A sample bar while the movers are up, so there is something to
            -- drag out of the water; MT_Apply restores the real state on exit.
            for _, K in ipairs(KINDS) do K.sample = active and true or nil end
            ns.MT_Apply()
        end)
    end

    local function AnyOn()
        for _, K in ipairs(KINDS) do
            local cfg = Cfg(K.id)
            if cfg and cfg.enabled then return true end
        end
        return false
    end

    -- The bars take the Player Cast Bar's size, not the mover's.
    return { MK({
        key = UNLOCK_KEY, label = EllesmereUI.L("Other Bars"), group = "Resource Bars",
        noResize = true,
        getFrame = function() return holder end,
        isHidden = function() return not AnyOn() end,
        getSize  = StackSize,
        savePos = function(_, point, relPoint, x, y)
            if not point then return end
            local m = StackCfg(); if not m then return end
            m.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
            if not EllesmereUI._unlockActive and holder then
                holder:ClearAllPoints()
                holder:SetPoint(point, UIParent, relPoint or point, x, y)
            end
        end,
        loadPos = function()
            local m = StackCfg()
            local pos = m and m.unlockPos
            if not pos then return nil end
            return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
        end,
        clearPos = function()
            local m = StackCfg(); if m then m.unlockPos = nil end
        end,
        applyPos = function()
            local m = StackCfg()
            local pos = m and m.unlockPos
            if not (pos and holder) then return end
            local sx, sy = ns.SnapXY(pos.x, pos.y, holder, pos)
            holder:ClearAllPoints()
            holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, sx, sy)
        end,
    }) }
end
