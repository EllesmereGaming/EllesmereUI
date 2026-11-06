if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- EUI_ResourceBars_MirrorTimer.lua
-- Mirror Timers: the Breath, Fatigue and Feign Death bars, on EUI's own frames.
--
-- Blizzard calls them mirror timers (Blizzard_MirrorTimer): started by
-- MIRROR_TIMER_START(timer, value, maxValue, scale, paused, label), paused by
-- MIRROR_TIMER_PAUSE(timer, paused) and ended by MIRROR_TIMER_STOP(timer).
-- Blizzard's own bars read GetMirrorTimerProgress on every frame for as long as
-- one runs, which is also what follows a breath bar refilling once the player
-- surfaces. This file reads the same call at 20 Hz, only while an unpaused
-- timer is up; nothing at all runs the rest of the time.
--
-- One bar per timer, each with its own settings, position and Unlock Mode
-- mover, the way the action bars are one per bar: Breath (BREATH), Fatigue
-- (EXHAUSTION), Feign Death (FEIGNDEATH, and DEATH, which Blizzard paints the
-- same way), Battle Start and Group Countdown (the game's countdowns, see
-- KINDS). They
-- are configured on the Cast Bar page, picked from its bar selector.
--
-- Each bar: bg, border (every border style), a StatusBar in a clip frame, an
-- optional spark and two texts (the game's label, the seconds left), each
-- placed left, right or center with its own size, offsets and colour.
--
-- Low Warning (optional, per bar): once a draining bar is down to Warn When
-- Left, it turns red and blinks. A refilling bar never warns. Both ride the
-- 20 Hz read.
--
-- Blizzard's own bar for a timer is made invisible (alpha 0, never a reparent
-- or an unregister) while ours for that timer is on with Hide Blizzard Bar;
-- the others keep showing. Off by default: nothing is built, registered or
-- hidden until a bar is turned on.
--
-- The build and style code is shared with the options preview (ns.MT_*).

local _, ns = ...
local EllesmereUI = _G.EllesmereUI

if not (GetMirrorTimerProgress and GetMirrorTimerInfo) then return end

-- id: the settings table under profile.mirrorTimer; timers: the client's
-- timer names this bar shows; name: the selector and mover name; sampleFrac:
-- the fill the Unlock Mode and options previews show.
local KINDS = {
    { id = "breath",  unlock = "ERB_MirrorBreath",  name = "Breath",      sampleFrac = 0.7,  order = 509,
      timers = { BREATH = true }, clientLabel = "BREATH_LABEL" },
    { id = "fatigue", unlock = "ERB_MirrorFatigue", name = "Fatigue",     sampleFrac = 0.45, order = 510,
      timers = { EXHAUSTION = true }, clientLabel = "EXHAUSTION_LABEL" },
    { id = "feign",   unlock = "ERB_MirrorFeign",   name = "Feign Death", sampleFrac = 0.6,  order = 511,
      timers = { FEIGNDEATH = true, DEATH = true }, spell = 5384 },
}
-- The game's TimerTracker bars, counted from the event's end time (no mirror
-- timer behind them). Battle Start: the battleground's countdown before the
-- gates open (START_TIMER with the PvP begin type; a world change drops it).
-- Group Countdown: a group leader's /countdown (START_PLAYER_COUNTDOWN,
-- CANCEL_PLAYER_COUNTDOWN), which lives through a world change.
local START_TYPES = Enum and Enum.StartTimerType
local START_KIND = {}  -- timer type -> kind
if START_TYPES and START_TYPES.PvPBeginTimer then
    KINDS[#KINDS + 1] = { id = "pvp", unlock = "ERB_MirrorPvP", name = "Battle Start", sampleFrac = 0.55,
        order = 512, timers = {}, startType = START_TYPES.PvPBeginTimer, numbersAt = 11 }
end
if START_TYPES and START_TYPES.PlayerCountdown then
    KINDS[#KINDS + 1] = { id = "countdown", unlock = "ERB_MirrorCountdown", name = "Group Countdown",
        sampleFrac = 0.5, order = 513, timers = {}, startType = START_TYPES.PlayerCountdown, keepOnWorld = true,
        numbersAt = 31 }
end
-- numbersAt: the seconds left where the game swaps its bar for its golden
-- numbers (its TimerTracker's mediumMarker for that type). Ours steps aside
-- there too, so they show alone, unless Show Under the Golden Numbers
-- (showUnderNumbers) keeps it up to the end.
for _, K in ipairs(KINDS) do
    if K.startType then START_KIND[K.startType] = K end
end
-- The name the client itself gives the timer (its bar label: BREATH_LABEL,
-- EXHAUSTION_LABEL; Feign Death has none, so the spell's name), so the
-- options, previews and movers say what the live bar says. Falls back to
-- the English name through the locale table.
local function KindName(K)
    local s = K.clientLabel and _G[K.clientLabel]
    if type(s) == "string" and s ~= "" then return s end
    if K.spell then
        local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(K.spell)
        if type(n) == "string" and n ~= "" then return n end
    end
    return EllesmereUI.L(K.name)
end
ns.MT_Name = KindName
local KIND_OF = {}     -- client timer name -> kind
local KIND_BY_ID = {}
for _, K in ipairs(KINDS) do
    KIND_BY_ID[K.id] = K
    for timer in pairs(K.timers) do KIND_OF[timer] = K end
end
ns.MT_KINDS, ns.MT_KIND_BY_ID = KINDS, KIND_BY_ID

-- Bar shells + ticker host at FILE SCOPE (attribution rule, see _erbEventFrame
-- in the main file): the OnEvent and OnLoop work bills ResourceBars. Children
-- stay lazy.
for _, K in ipairs(KINDS) do
    K.frame = CreateFrame("Frame", "ERB_Mirror_" .. K.id, UIParent)
    K.frame:Hide()
end
local eventFrame = CreateFrame("Frame")
local tickFrame = CreateFrame("Frame")

local S = {}   -- events, blizzHidden, unlockHooked

-------------------------------------------------------------------------------
--  Settings access
-------------------------------------------------------------------------------

local function Cfg(id)
    local ERB = ns.ERB
    local db = ERB and ERB.db
    local p = db and db.profile
    local m = p and p.mirrorTimer
    return m and m[id] or nil
end
ns.MT_Cfg = Cfg

-- A restricted answer is no answer: the bar keeps what it last showed.
local function Plain(v)
    return not (issecretvalue and issecretvalue(v))
end

-------------------------------------------------------------------------------
--  One bar: build, look, paint (shared with the options preview)
-------------------------------------------------------------------------------

-- Builds the children of obj.frame. obj is a KINDS entry, or a preview table
-- the options page makes ({ frame = <its container> }); mk is its frame maker
-- (the options page pool's CreateFrame there, so a rebuilt page reuses them).
local MAX_DIGITS = 5   -- cells: up to "mm:ss"

local function BuildBar(obj, mk)
    local CreateFrame = mk or CreateFrame
    local f = obj.frame
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    obj.bg = bg

    local bdr = CreateFrame("Frame", nil, f)
    bdr:SetAllPoints(f)
    bdr:SetFrameLevel(f:GetFrameLevel() + 5)
    obj.border = bdr
    local PP = EllesmereUI.PP
    if PP then PP.CreateBorder(bdr, 0, 0, 0, 1, 1) end

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
    if frameTex.SetSnapToPixelGrid then frameTex:SetSnapToPixelGrid(false); frameTex:SetTexelSnappingBias(0) end
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
    -- The seconds are drawn one digit per fixed cell (the widest digit's
    -- width), so a narrow 1 does not shift the others as they count down.
    -- obj.time stays as the invisible box that places them (and that the
    -- options' click overlay follows).
    obj.digits = {}
    for i = 1, MAX_DIGITS do
        local d = textFrame:CreateFontString(nil, "OVERLAY")
        ns.SetRBFont(d, ns.GetRBFont(), 11)
        d:SetWordWrap(false)
        d:SetJustifyH("CENTER")
        d:SetText("")
        d:Hide()
        obj.digits[i] = d
    end
    obj.built = true
end
ns.MT_BuildBar = BuildBar

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
ns.MT_StockStyle = StockStyle

-- Size, border, texture, background, spark and texts from cfg.
local function ApplyLook(obj, cfg, onePx)
    local f = obj.frame
    local PP = EllesmereUI.PP
    local style = StockStyle()
    local stock = style ~= "eui"
    local blizzKit = style == "blizzard"
    -- No EUI border under a stock style: its frame art is the border.
    local bs = (not stock and cfg.borderSize) or 0
    local bdr = obj.border
    local pl = f:GetFrameLevel()
    bdr:SetFrameLevel(cfg.borderBehind and math.max(0, pl - 1) or (pl + 5))
    if not bdr:GetLeft() then bdr:SetAllPoints(f) end
    EllesmereUI.ApplyBorderStyle(bdr, bs,
        cfg.borderR or 0, cfg.borderG or 0, cfg.borderB or 0, cfg.borderA or 1,
        cfg.borderTexture or "solid", cfg.borderTextureOffset, cfg.borderTextureOffsetY,
        cfg.borderTextureShiftX, cfg.borderTextureShiftY, "resourcebars", bs,
        nil, EllesmereUI.BorderPx(cfg.borderSizePx, bs, cfg.borderTexture or "solid"))

    -- The 1px inset keeps the fill from bleeding past the border.
    local clip, bar = obj.clip, obj.bar
    local inset = (bs > 0 and (onePx or (PP and PP.mult))) or 0
    clip:ClearAllPoints()
    clip:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
    clip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
    clip:SetFrameLevel(pl + 1)
    bar:ClearAllPoints()
    bar:SetAllPoints(clip)
    local fillAtlas = blizzKit and ns.ERB_BlizzAtlas and ns.ERB_BlizzAtlas("cast")
    if fillAtlas then
        -- Blizzard Style: the stock fill art, greyed so the bar's own colour
        -- tints it (Paint) and Breath stays blue.
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        bar:GetStatusBarTexture():SetAtlas(fillAtlas)
        bar:GetStatusBarTexture():SetDesaturated(true)
    else
        bar:SetStatusBarTexture(EllesmereUI.ResolveTexturePath(_G._ERB_BarTextures, cfg.texture, "Interface\\Buttons\\WHITE8x8"))
        bar:GetStatusBarTexture():SetDesaturated(false)
    end
    bar:SetOrientation("HORIZONTAL")
    bar:SetReverseFill(false)
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

    -- Frame art: above the fill and spark, under the texts.
    local h = cfg.height or 20
    local art = obj.art
    art:SetFrameLevel(pl + 6)
    obj.textFrame:SetFrameLevel(pl + 8)
    local frameAtlas = blizzKit and ns.ERB_BlizzAtlas and ns.ERB_BlizzAtlas("frame")
    if frameAtlas then
        ns.ERB_StockAtlas(obj.frameTex, frameAtlas)
        obj.frameTex:ClearAllPoints()
        obj.frameTex:SetPoint("TOPLEFT", f, "TOPLEFT", -2, 2)
        obj.frameTex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 2, -2)
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
            spark:SetSize(8, h)
        end
        spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, sparkY)
        spark:Show()
    else
        spark:Hide()
    end

    PlaceText(obj.label, f, cfg.labelSide or "left", cfg.labelSize or 11, cfg.labelX or 0, cfg.labelY or 0,
        cfg.labelR or 1, cfg.labelG or 1, cfg.labelB or 1, cfg.labelA or 1)
    PlaceText(obj.time, f, cfg.timeSide or "right", cfg.timeSize or 11, cfg.timeX or 0, cfg.timeY or 0,
        cfg.timeR or 1, cfg.timeG or 1, cfg.timeB or 1, cfg.timeA or 1)
    -- Digit cells: same font and colour; the box itself is never seen.
    local time = obj.time
    time:SetAlpha(0)
    obj.timeShown = (cfg.timeSide or "right") ~= "none"
    for i = 1, MAX_DIGITS do
        local d = obj.digits[i]
        ns.SetRBFont(d, ns.GetRBFont(), cfg.timeSize or 11)
        d:SetTextColor(cfg.timeR or 1, cfg.timeG or 1, cfg.timeB or 1, cfg.timeA or 1)
        if not obj.timeShown then d:Hide() end
    end
    local wide, wideW = "0", -1
    for n = 0, 9 do
        time:SetText(tostring(n))
        local w = time:GetStringWidth() or 0
        if w > wideW then wide, wideW = tostring(n), w end
    end
    obj.wideDigit, obj.digitW = wide, wideW
    time:SetText(":")
    obj.colonW = time:GetStringWidth() or 0
    obj.lastTime = nil
    time:SetText("")

    -- Rounded corners (EllesmereUI_RoundedCorners.lua; nothing at radius 0).
    -- The body is the clip (fill + spark) and the background.
    local radius = (not stock and cfg.cornerRadius) or 0
    if radius > 0 and EllesmereUI.RoundCorners then
        EllesmereUI.RoundCorners(f, radius, {
            roots = { clip }, textures = { obj.bg },
            border = bdr, clip = clip,
            style = cfg.borderTexture or "solid", corners = cfg.cornerMask,
        })
    elseif EllesmereUI.RoundCorners then
        EllesmereUI.RoundCorners(f, 0)
    end
end
ns.MT_ApplyLook = ApplyLook

local WARN_R, WARN_G, WARN_B = 1, 0.1, 0.1
local PULSE_PERIOD = 0.6   -- seconds per blink

-- Fill, seconds and colour for a bar at fraction `frac` of its maximum.
-- `still`: the previews, which nothing ticks, so no pulse (it would freeze
-- half-faded).
local function Paint(obj, cfg, frac, seconds, rising, still)
    frac = math.max(0, math.min(frac or 0, 1))
    obj.bar:SetMinMaxValues(0, 1)
    obj.bar:SetValue(frac)
    -- Seconds under a minute, then m:ss (Breath can run 3 minutes, Feign
    -- Death 6), as the game's own bar.
    local secs = math.max(0, math.floor((seconds or 0) + 0.5))
    local txt
    if secs >= 60 then
        txt = string.format("%d:%02d", math.floor(secs / 60), secs % 60)
    else
        txt = string.format("%d", secs)
    end
    if txt ~= obj.lastTime then
        obj.lastTime = txt
        local n = math.min(#txt, MAX_DIGITS)
        txt = txt:sub(-n)
        -- The box holds the same pattern in the widest digit, so it keeps its
        -- size while the digits change; each cell is a digit's or the colon's width.
        local wide = obj.wideDigit or "0"
        local time = obj.time
        time:SetText((txt:gsub("%d", wide)))
        local dw, colw = obj.digitW or 0, obj.colonW or 0
        local x = 0
        for i = 1, MAX_DIGITS do
            local d = obj.digits[i]
            if i <= n and obj.timeShown then
                local ch = txt:sub(i, i)
                local w = (ch == ":") and colw or dw
                d:ClearAllPoints()
                d:SetPoint("CENTER", time, "LEFT", x + w / 2, 0)
                d:SetText(ch)
                d:Show()
                x = x + w
            else
                d:Hide()
            end
        end
    end

    local r, g, b, a = cfg.fillR or 1, cfg.fillG or 1, cfg.fillB or 1, cfg.fillA or 1
    local alpha = 1
    local start = (cfg.lowWarnAt or 30) / 100
    if cfg.lowWarn and not rising and start > 0 and frac <= start then
        -- The warning fires at the threshold: red and blinking until the bar
        -- refills or ends.
        r, g, b = WARN_R, WARN_G, WARN_B
        if not still then
            local s = math.sin(GetTime() * math.pi * 2 / PULSE_PERIOD)
            alpha = 0.35 + 0.65 * math.abs(s)
        end
    end
    local tex = obj.bar:GetStatusBarTexture()
    if cfg.gradientEnabled then
        tex:SetGradient(cfg.gradientDir or "HORIZONTAL", CreateColor(r, g, b, a),
            CreateColor(cfg.gradientR or 0.2, cfg.gradientG or 0.2, cfg.gradientB or 0.8, cfg.gradientA or 1))
    else
        tex:SetVertexColor(1, 1, 1, 1)
        obj.bar:SetStatusBarColor(r, g, b, a)
    end
    obj.frame:SetAlpha(alpha)
end
ns.MT_Paint = Paint

-------------------------------------------------------------------------------
--  The live bars
-------------------------------------------------------------------------------

local function PaintLive(K, cfg)
    if K.sample then
        K.label:SetText(KindName(K))
        Paint(K, cfg, K.sampleFrac, 60 * K.sampleFrac, false, true)
        return
    end
    local a = K.active
    if not a then return end
    K.label:SetText(a.label or "")
    local max = (a.max and a.max > 0) and a.max or 1
    Paint(K, cfg, (a.value or 0) / max, (a.value or 0) / 1000, a.rising, a.paused)
end

-- Position: the unlock anchor chain first, then a saved unlock position, then
-- the CENTER offsets (the GCD bar's three-way split).
local function ApplyPosition(K, cfg)
    local f = K.frame
    f:SetSize(cfg.width or 200, cfg.height or 20)
    if EllesmereUI._TryOverrideAnchor and EllesmereUI._TryOverrideAnchor(K.unlock, f) then
        return
    end
    if EllesmereUI._unlockActive then return end
    local pos = cfg.unlockPos
    if pos and pos.point then
        local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(K.unlock)
        if anchored and f:GetLeft() then return end
        local sx, sy = ns.SnapXY(pos.x or 0, pos.y or 0, f, pos)
        f:ClearAllPoints()
        f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, sx, sy)
    else
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", cfg.anchorX or 0, cfg.anchorY or 300)
    end
end

local function UpdateVisibility(K)
    if not K.built then return end
    local cfg = Cfg(K.id)
    local on = cfg and cfg.enabled and (K.sample or (K.active and not K.active.underNumbers)) and true or false
    EllesmereUI.SetElementVisibility(K.frame, on)
end

-- Blizzard's bar for each timer: invisible while ours for that timer is on with
-- Hide Blizzard Bar, shown otherwise. Its frames are handed out to timers as
-- they start, so this runs one frame after every start, once Blizzard's own
-- handler has given the frame its timer.
local function ApplyBlizzard()
    local blizz = _G.MirrorTimerContainer
    local frames = blizz and blizz.mirrorTimers
    if not frames then return end
    local any = false
    for _, tf in ipairs(frames) do
        local K = tf.timer and KIND_OF[tf.timer]
        local cfg = K and Cfg(K.id)
        local hide = cfg and cfg.enabled and cfg.hideBlizzard ~= false
        if hide then
            tf:SetAlpha(0)
            any = true
        elseif S.blizzHidden then
            tf:SetAlpha(1)
        end
    end
    S.blizzHidden = any or nil
    -- The TimerTracker bars (their big final numbers stay). Their fade
    -- animations set the bar's alpha, so the ticker runs this again while
    -- ours count.
    local tracker = _G.TimerTracker
    if tracker and tracker.timerList then
        local anyHidden = false
        for _, timer in ipairs(tracker.timerList) do
            local K = timer.type and START_KIND[timer.type]
            if K and timer.bar then
                local cfg = Cfg(K.id)
                if cfg and cfg.enabled and cfg.hideBlizzard ~= false and K.active then
                    timer.bar:SetAlpha(0)
                    anyHidden = true
                elseif S.trackerHidden then
                    timer.bar:SetAlpha(timer.barShowing and 1 or 0)
                end
            end
        end
        S.trackerHidden = anyHidden or nil
    end
end

local function AnyRunning()
    for _, K in ipairs(KINDS) do
        if K.active and not K.active.paused then return true end
    end
    return false
end

local ticker = EllesmereUI.Tick.NewAnimTicker(tickFrame, function()
    local running = false
    for _, K in ipairs(KINDS) do
        local a = K.active
        if a and not a.paused then
            running = true
            local ms
            if a.endTime then
                ms = math.max(0, (a.endTime - GetTime()) * 1000)
            else
                ms = GetMirrorTimerProgress(a.timer)
            end
            if Plain(ms) and type(ms) == "number" then
                -- Refilling: the value went up since the last read.
                if a.value and ms ~= a.value then a.rising = ms > a.value end
                a.value = ms
                local cfg = Cfg(K.id)
                if cfg and K.built and not K.sample then PaintLive(K, cfg) end
                -- A countdown ends at zero: the game sends nothing when the
                -- gates open.
                if a.endTime and ms <= 0 then
                    K.active = nil
                    UpdateVisibility(K)
                elseif a.endTime and K.numbersAt and not a.underNumbers
                       and cfg and not cfg.showUnderNumbers and ms < K.numbersAt * 1000 then
                    a.underNumbers = true
                    UpdateVisibility(K)
                end
            end
        end
    end
    if S.trackerHidden then ApplyBlizzard() end
    return running
end, 0.05)

local function Restart()
    if AnyRunning() then ticker.Start() else ticker.Stop() end
end

local function IsPaused(v)
    return v == true or (type(v) == "number" and v > 0)
end

local function StartTimer(timer, value, maxValue, paused, label)
    if not (Plain(timer) and Plain(value) and Plain(maxValue) and Plain(paused) and Plain(label)) then return end
    local K = type(timer) == "string" and KIND_OF[timer]
    if not K or type(maxValue) ~= "number" then return end
    local cfg = Cfg(K.id)
    if not (cfg and cfg.enabled and K.built) then return end
    K.active = { timer = timer, value = value, max = maxValue, label = label,
                 paused = IsPaused(paused), rising = false }
    PaintLive(K, cfg)
    UpdateVisibility(K)
    Restart()
end

local function StopTimer(timer)
    local K = Plain(timer) and type(timer) == "string" and KIND_OF[timer]
    if not (K and K.active and K.active.timer == timer) then return end
    K.active = nil
    UpdateVisibility(K)
    Restart()
end

-- A TimerTracker countdown of type timerType: seconds left out of total.
local function StartCountdown(timerType, seconds, total)
    local K = Plain(timerType) and START_KIND[timerType]
    if not (K and Plain(seconds) and Plain(total)) then return end
    if type(seconds) ~= "number" or type(total) ~= "number" then return end
    if total <= 0 or seconds <= 0 then  -- a cancelled countdown comes as 0, 0
        if K.active then
            K.active = nil
            UpdateVisibility(K)
            ApplyBlizzard()
            Restart()
        end
        return
    end
    local cfg = Cfg(K.id)
    if not (cfg and cfg.enabled and K.built) then return end
    K.active = { endTime = GetTime() + seconds, value = seconds * 1000, max = total * 1000,
                 label = KindName(K), paused = false, rising = false }
    PaintLive(K, cfg)
    UpdateVisibility(K)
    Restart()
end

local function StopCountdown(timerType)
    local K = Plain(timerType) and START_KIND[timerType]
    if not (K and K.active) then return end
    K.active = nil
    UpdateVisibility(K)
    ApplyBlizzard()
    Restart()
end

-- The timers already running when a bar comes up (a /reload under water).
local function Resync()
    for _, K in ipairs(KINDS) do
        if not K.keepOnWorld then K.active = nil end
    end
    for i = 1, 3 do
        local timer, value, maxValue, _, paused, label = GetMirrorTimerInfo(i)
        if Plain(timer) and timer and timer ~= "UNKNOWN" then
            StartTimer(timer, value, maxValue, paused, label)
        end
    end
    for _, K in ipairs(KINDS) do UpdateVisibility(K) end
    Restart()
end

eventFrame:SetScript("OnEvent", function(_, event, a1, a2, a3, _, a5, a6)
    if event == "MIRROR_TIMER_START" then
        -- timer, value, maxValue, scale, paused, label
        StartTimer(a1, a2, a3, a5, a6)
        C_Timer.After(0, ApplyBlizzard)
    elseif event == "MIRROR_TIMER_PAUSE" then
        local K = Plain(a1) and type(a1) == "string" and KIND_OF[a1]
        local a = K and K.active
        if a and a.timer == a1 and Plain(a2) then
            a.paused = IsPaused(a2)
            local cfg = Cfg(K.id)
            if cfg then PaintLive(K, cfg) end
            Restart()
        end
    elseif event == "MIRROR_TIMER_STOP" then
        StopTimer(a1)
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

local function ApplyKind(K)
    local cfg = Cfg(K.id)
    if not (cfg and cfg.enabled) then
        K.active = nil
        if K.built then EllesmereUI.SetElementVisibility(K.frame, false) end
        return false
    end
    if not K.built then
        K.frame:SetFrameLevel(15)
        BuildBar(K)
    end
    K.frame:SetFrameStrata(cfg.frameStrata or "MEDIUM")
    K.frame:Show()
    ApplyPosition(K, cfg)
    ApplyLook(K, cfg)
    PaintLive(K, cfg)
    UpdateVisibility(K)
    return true
end

function ns.MT_Apply()
    local any = false
    for _, K in ipairs(KINDS) do
        if ApplyKind(K) then any = true end
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
        if KIND_BY_ID.countdown then
            eventFrame:RegisterEvent("START_PLAYER_COUNTDOWN")
            eventFrame:RegisterEvent("CANCEL_PLAYER_COUNTDOWN")
        end
        Resync()
    elseif not any and S.events then
        S.events = nil
        eventFrame:UnregisterAllEvents()
        Restart()
    end
    ApplyBlizzard()
end

-------------------------------------------------------------------------------
--  Unlock elements, one per bar
-------------------------------------------------------------------------------

function ns.MT_MakeUnlockElements(MK, Rebuild)
    if not MK then return nil end
    local PP = EllesmereUI.PP

    if not S.unlockHooked and EllesmereUI.RegisterUnlockModeListener then
        S.unlockHooked = true
        EllesmereUI:RegisterUnlockModeListener("ERB_Mirror", function(active)
            -- A sample bar while the movers are up, so there is something to
            -- drag out of the water; MT_Apply restores the real state on exit.
            for _, K in ipairs(KINDS) do K.sample = active and true or nil end
            if ns.MT_Apply then ns.MT_Apply() end
        end)
    end

    local out = {}
    for _, K in ipairs(KINDS) do
        local id, f = K.id, K.frame
        out[#out + 1] = MK({
            key = K.unlock, label = KindName(K), group = "Resource Bars", order = K.order,
            getFrame = function() return K.built and f or nil end,
            isHidden = function() local cfg = Cfg(id); return not (cfg and cfg.enabled) end,
            getSize  = function() local cfg = Cfg(id); return (cfg and cfg.width or 200), (cfg and cfg.height or 20) end,
            getMatchPad = function() return ns.ERB_EuiBorderPad(Cfg(id)) end,
            setWidth = function(_, w)
                local cfg = Cfg(id); if not cfg then return end
                cfg.width = PP.Snap(math.max(w, 10))
                Rebuild()
            end,
            setHeight = function(_, h)
                local cfg = Cfg(id); if not cfg then return end
                cfg.height = PP.Snap(math.max(h, 4))
                Rebuild()
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                local cfg = Cfg(id); if not cfg then return end
                cfg.unlockPos = { point = point, relPoint = relPoint or point, x = x, y = y }
                if not EllesmereUI._unlockActive and K.built then
                    f:ClearAllPoints()
                    f:SetPoint(point, UIParent, relPoint or point, x, y)
                end
            end,
            loadPos = function()
                local cfg = Cfg(id)
                local pos = cfg and cfg.unlockPos
                if not pos then return nil end
                return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
            end,
            clearPos = function()
                local cfg = Cfg(id); if not cfg then return end
                cfg.unlockPos = nil
                cfg.anchorX = nil; cfg.anchorY = nil
            end,
            applyPos = function()
                local cfg = Cfg(id)
                local pos = cfg and cfg.unlockPos
                if not (pos and K.built) then return end
                local sx, sy = ns.SnapXY(pos.x, pos.y, f, pos)
                f:ClearAllPoints()
                f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, sx, sy)
            end,
        })
    end
    return out
end
