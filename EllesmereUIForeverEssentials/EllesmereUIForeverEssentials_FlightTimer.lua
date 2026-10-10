if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_FlightTimer.lua  (WoW Forever only)
--  Route display with an ETA for flight-master flights: a thin track between
--  the two ends, stops scrolling past a "you" marker. Route lengths come from
--  the game's TaxiPath data (EllesmereUIForeverEssentials_FlightTimerData.lua);
--  the client exposes no flight duration, so time is length / speed, with the
--  speed corrected by every flight that lands normally. The options page shows
--  the same display flying a sample route on a loop.
--
--  Known issue: a reload, relog or crash mid-flight drops the bar for the rest
--  of that flight. The client gives no destination or progress for a flight
--  already under way, and saving it would go stale across a logout or crash,
--  so the bar returns with the next takeoff instead.
-------------------------------------------------------------------------------
local _, module = ...

local DEFAULT_SPEED = 30.4 -- yards per second; fitted to measured Classic flight times
local PREVIEW_SECONDS = 20
local PREVIEW_HOLD = 2 -- seconds a finished preview flight stays before the next
local TRACK_HEIGHT = 3
local PIN_SIZE = 14
-- Seconds before arrival a stop scrolls in at the track's right end.
local LOOKAHEAD = 60
local WHITE = "Interface\\Buttons\\WHITE8x8"
local STOP_ICON = "Interface\\Minimap\\Tracking\\FlightMaster"
-- Slow Fall's feather: "come down gently" reads as land here.
local EXIT_ICON = "Interface\\Icons\\Spell_Magic_FeatherFall"
local EXIT_SIZE = 28

-- Preview: a real two-stop route per faction as node id / name pairs, played
-- fast-forward in PREVIEW_SECONDS (the path the game flies between the ends).
local PREVIEW_ROUTES = {
    Horde = { 80, "Ratchet", 25, "Crossroads", 30, "Freewind Post", 40, "Gadgetzan" },
    Alliance = { 6, "Ironforge", 74, "Thorium Point", 71, "Morgan's Vigil", 5, "Lakeshire" },
}

-- Settings live in EllesmereUIDB.flightTimer; unset keys read these.
local DEFAULTS = {
    enabled = true,
    -- trackHeight: its own key; the retired bar style's `height` stays unread.
    width = 300, trackHeight = TRACK_HEIGHT, showEndCaps = true,
    texture = "none",
    fillOpacity = 100, classColored = false,
    bgA = 0.8,
    borderSize = 1, borderR = 0, borderG = 0, borderB = 0,
    -- destText / timeText: "none" hides; any other value (older saves hold a
    -- side from the retired bar style) shows.
    destText = "show", destSize = 12, destX = 0, destY = 0,
    timeText = "show", timeSize = 12, timeX = 0, timeY = 0,
    showTotal = false, earlyExit = true, fade = false,
}

local BAR_TEXTURES, BAR_TEXTURE_NAMES, BAR_TEXTURE_ORDER = EllesmereUI.BuildBarTextureTables()

local routes = EllesmereUI._FlightTimerRoutes
local bar, events, ticker, hooked
local pending   -- destination picked on the flight map, waiting for takeoff
local flight    -- the flight in progress

local F = module.Feature("flightTimer", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = 0, y = 250 })
local Get, Cfg, Read, Enabled = F.Get, F.Cfg, F.Read, F.Enabled

-- The display's full height, centred on the track: end names above it, stop
-- icons and names below (the same room the stop strip clips to).
local function BoxHeight()
    return math.max(PIN_SIZE, Get("trackHeight")) + 2 * (Get("destSize") + 8)
end

-- How much further a label must sit from a mark of this height, centred on
-- the track, to clear a track taller than the mark.
local function Rise(size)
    return math.max(0, (Get("trackHeight") - size) / 2)
end

local function Speed()
    return Read().speed or DEFAULT_SPEED
end

-- Frequent Flier, node 110300 of the Adventure Legacy tree (1188), makes
-- flight path mounts 20% faster. Legacy perks are bought per character. Both
-- lookups may return nothing (a character with no config for the tree), so a
-- missing answer reads as no perk rather than erroring at takeoff.
local function SpeedMultiplier()
    local configID = C_Traits.GetConfigIDByTreeID(1188)
    local node = configID and C_Traits.GetNodeInfo(configID, 110300)
    return (node and node.activeRank or 0) > 0 and 1.2 or 1
end

local function FormatTime(sec)
    sec = math.max(0, math.floor(sec + 0.5))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- The time text of flight fl at elapsed seconds: the time left, plus the
-- full time with Show Total Time.
local function TimeLeft(fl, elapsed)
    local left = FormatTime(fl.eta - elapsed)
    return Get("showTotal") and (left .. " / " .. FormatTime(fl.eta)) or left
end

local function FillColor()
    if Get("classColored") then
        local _, classFile = UnitClass("player")
        local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
        if cc then return cc.r, cc.g, cc.b end
    end
    local c = Read()
    if c.fillR then return c.fillR, c.fillG, c.fillB end
    local EG = EllesmereUI.ELLESMERE_GREEN
    return EG.r, EG.g, EG.b
end

-- Sums the stored length of every hop on the way to slot; nil when any hop
-- is missing from the data, which leaves the bar showing elapsed time only.
-- Also returns every node on the way, start first, each with the yards flown
-- to reach it (nil once a hop is missing).
local function RouteInfo(slot)
    local hops = GetNumRoutes(slot)
    if hops < 1 then return nil end
    -- The taxi UI can open without a map id; no id means no route lookup.
    local mapID = GetTaxiMapID and GetTaxiMapID()
    local nodes = mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes(mapID)
    local idBySlot = {}
    for _, node in ipairs(nodes or idBySlot) do
        idBySlot[node.slotIndex] = node.nodeID
    end
    local yards = 0
    local points = { { name = TaxiNodeName(TaxiGetNodeSlot(slot, 1, true)), yards = 0 } }
    for hop = 1, hops do
        local toSlot = TaxiGetNodeSlot(slot, hop, false)
        local from = idBySlot[TaxiGetNodeSlot(slot, hop, true)]
        local to = idBySlot[toSlot]
        local hopYards = from and to and routes[from * 10000 + to]
        yards = yards and hopYards and yards + hopYards
        points[#points + 1] = { name = TaxiNodeName(toSlot), yards = yards }
    end
    return yards and yards > 0 and yards or nil, points
end

-- Text in Forever Essentials' font and outline (Fonts page, else the global font).
local function StyleFont(fs, size)
    EllesmereUI.ApplyModuleFont(fs, nil, size, "essentials")
end

-- A mark on the route (an end, a stop, "you"): an icon with a label.
local function NewMark(parent, texture, w, h)
    local m = { icon = parent:CreateTexture(nil, "OVERLAY"), label = parent:CreateFontString(nil, "OVERLAY") }
    m.icon:SetTexture(texture)
    m.icon:SetSize(w, h or w)
    m.label:SetWordWrap(false)
    return m
end

-- text: a string shows icon and label, nil the icon alone, false neither.
local function ShowMark(m, text)
    m.icon:SetShown(text ~= false)
    m.icon:SetAlpha(1)
    m.label:SetShown(text and true or false)
    m.label:SetAlpha(1)
    if text then
        StyleFont(m.label, Get("destSize"))
        m.label:SetText(text)
    end
end

-- ShowMark's text for a mark shown only when show; with names off, icon only.
local function MarkText(show, name, names)
    if not show then return false end
    return names and (name or "") or nil
end

-- Every function below draws into a display b (the bar on screen, or the
-- options preview) showing flight fl.

-- Puts the stop strip where elapsed has it, dims the stops already passed,
-- then slides it on. One long translation over the whole flight ran far too
-- fast in the client, so each slide is short and the 1 s ticker restarts the
-- next from the exact spot: no drift, and a slide slightly longer than a tick
-- never snaps back.
local SLIDE = 1.25
local function ScrollStrip(b, fl, elapsed)
    local clip = b.clip
    if not clip:IsShown() then return end
    local g = clip.glide
    g:Stop()
    clip.strip:ClearAllPoints()
    clip.strip:SetPoint("CENTER", b, "CENTER", -elapsed * clip.pps, 0)
    if elapsed < fl.eta then
        g.move:SetOffset(-SLIDE * clip.pps, 0)
        g:Play()
    end
    local flown = elapsed / fl.eta * fl.yards
    for k = 1, #fl.points - 2 do
        local y = fl.points[k + 1].yards
        if y and y <= flown then
            b.stops[k].icon:SetAlpha(0.4)
            b.stops[k].label:SetAlpha(0.4)
        end
    end
end

-- A side-scroller: the two ends hold still at the track's ends and "you" at
-- its centre. Stops scroll in from the right as they near, cross "you" the
-- moment they are reached, and run out to the left.
local function LayoutRoute(b, fl)
    local points = fl and fl.points
    local n = points and #points or 0
    local names = Get("destText") ~= "none"
    local dx, dy = Get("destX"), Get("destY")
    local level = b.track:GetFrameLevel() + 2
    b.over:SetFrameLevel(level)
    b.clip:SetFrameLevel(level)

    -- The ends: a dot in the fill colour (Show End Caps) with the node's name
    -- above it; a hidden dot still places its name.
    local caps = Get("showEndCaps")
    for i = 1, 2 do
        local m, side = b.ends[i], i == 1 and "LEFT" or "RIGHT"
        ShowMark(m, MarkText(n > 0, n > 0 and points[i == 1 and 1 or n].name, names))
        if not caps then m.icon:Hide() end
        m.icon:SetVertexColor(FillColor())
        m.label:ClearAllPoints()
        m.label:SetPoint("BOTTOM" .. side, m.icon, "TOP" .. side, dx, 4 + dy + Rise(PIN_SIZE / 2))
        -- Each end name gets at most 47% of the bar's width; a longer one is cut off.
        m.label:SetWidth(Get("width") * 0.47)
        m.label:SetJustifyH(side)
    end

    -- Where each stop sits comes from its arrival time, known only with route
    -- lengths and an ETA. After an early landing request the route ends at the
    -- next stop; stops already passed would keep sliding out, so the strip
    -- and "you" go entirely.
    local moving = points and fl.eta and fl.yards and not fl.early
    local scroll = moving and n > 2
    local clip = b.clip
    clip:SetShown(scroll)
    if scroll then
        -- Inside the two end dots, tall enough for a stop's icon and the name
        -- under it.
        clip:ClearAllPoints()
        clip:SetPoint("BOTTOMLEFT", b, "LEFT", PIN_SIZE / 2, -PIN_SIZE / 2 - Get("destSize") - 8 - Rise(PIN_SIZE))
        clip:SetPoint("TOPRIGHT", b, "RIGHT", -PIN_SIZE / 2, PIN_SIZE / 2 + 2)
        -- px per second of flight: a stop comes in LOOKAHEAD seconds out
        -- (scaled down with the clock for a fast-forward preview).
        clip.pps = Get("width") / 2 / (fl.lookahead or LOOKAHEAD)
    end
    -- b.stops[k] is the stop at points[k + 1]; leftovers from a longer
    -- route are hidden.
    for k = 1, math.max(n - 2, #b.stops) do
        local y = scroll and k <= n - 2 and points[k + 1].yards
        local m = b.stops[k]
        if y and not m then
            m = NewMark(clip.strip, STOP_ICON, PIN_SIZE)
            b.stops[k] = m
        end
        if m then
            ShowMark(m, MarkText(y, y and points[k + 1].name, names))
            m.label:ClearAllPoints()
            m.label:SetPoint("TOP", m.icon, "BOTTOM", 0, -4 - Rise(PIN_SIZE))
            if y then
                m.icon:ClearAllPoints()
                m.icon:SetPoint("CENTER", clip.strip, "CENTER", y / fl.yards * fl.eta * clip.pps, 0)
            end
        end
    end
    if scroll then ScrollStrip(b, fl, math.max(0, math.min(GetTime() - fl.start, fl.eta))) end

    -- "You are here": a white post at the centre, where each stop is reached;
    -- a direct flight has no stops to reach, so none.
    ShowMark(b.you, MarkText(scroll, EllesmereUI.L("You"), names))
    b.you.label:ClearAllPoints()
    b.you.label:SetPoint("BOTTOM", b.you.icon, "TOP", 0, 2 + Rise(PIN_SIZE + 4))
end

local RequestLanding -- the early exit button's click; defined with the flight code

-- Early exit button right of the bar, built on first enable. Greyed out once a
-- landing is requested, as Blizzard's leave button does.
local function StyleExit(b, fl)
    local btn = b.exit
    if not Get("earlyExit") then
        if btn then btn:Hide() end
        return
    end
    if not btn then
        btn = CreateFrame("Button", nil, b)
        btn:SetSize(EXIT_SIZE, EXIT_SIZE)
        btn:SetPoint("LEFT", b, "RIGHT", PIN_SIZE / 2 + 6, 0)
        btn:SetNormalTexture(EXIT_ICON)
        btn:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the icon frame
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        EllesmereUI.PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 2)
        btn:SetScript("OnClick", function() RequestLanding(b) end)
        btn:SetScript("OnEnter", function(self)
            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.L("Land at the next flight point"))
        end)
        btn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        b.exit = btn
    end
    local done = fl and fl.early
    btn:SetEnabled(not done)
    btn:SetAlpha(done and 0.4 or 1)
    btn:Show()
end

local function StyleBar(b, fl)
    local PP = EllesmereUI.PP
    local track = b.track
    b:SetSize(Get("width"), BoxHeight())
    track:SetHeight(Get("trackHeight"))
    track:SetStatusBarTexture(EllesmereUI.ResolveTexturePath(BAR_TEXTURES, Get("texture"), WHITE))
    -- The fill's one alpha owner: a texture's SetAlpha and its colour alpha
    -- are the same channel. A plain SetValue does not reliably take the fill
    -- back from an armed SetTimerDuration, so an elapsed-only flight hides it.
    local cr, cg, cb = FillColor()
    track:SetStatusBarColor(cr, cg, cb, (fl and not fl.eta) and 0 or Get("fillOpacity") / 100)
    track.bg:SetColorTexture(0.1, 0.1, 0.1, Get("bgA"))
    -- The border draws inside the track: kept under half its height in pixels,
    -- so at least a pixel of fill always shows (the saved size is kept).
    local cap = math.floor((Get("trackHeight") / (PP.mult or 1) - 1) / 2)
    local bs = math.max(0, math.min(Get("borderSize"), cap))
    if bs > 0 then
        PP.UpdateBorder(track, bs, Get("borderR"), Get("borderG"), Get("borderB"), 1)
        PP.ShowBorder(track)
    else
        PP.HideBorder(track)
    end
    -- The time sits left of the track, mirroring the early exit button on the
    -- right; under the track is the stop names' lane.
    b.time:SetShown(Get("timeText") ~= "none")
    StyleFont(b.time, Get("timeSize"))
    b.time:ClearAllPoints()
    b.time:SetPoint("RIGHT", b, "LEFT", -PIN_SIZE / 2 - 6 + Get("timeX"), Get("timeY"))
    LayoutRoute(b, fl)
    StyleExit(b, fl)
end

-- An invisible box around the whole display, sized by StyleBar: the unlock
-- mover takes the frame's own size, so this gives it a grabbable area. The
-- track is the thin line through its middle.
local function BuildBar(parent)
    local b = CreateFrame("Frame", nil, parent)
    local track = CreateFrame("StatusBar", nil, b)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetMinMaxValues(0, 1)
    track:SetValue(0)
    track.bg = track:CreateTexture(nil, "BACKGROUND")
    track.bg:SetAllPoints()
    EllesmereUI.PP.CreateBorder(track, 0, 0, 0, 1, 1, "OVERLAY", 2)
    b.track = track
    b.time = b:CreateFontString(nil, "OVERLAY")
    b.time:SetJustifyH("RIGHT")
    -- PP.CreateBorder draws on its own frame one level above the bar, so the
    -- marks sit on frames two levels up (set in LayoutRoute) to stay on top.
    b.over = CreateFrame("Frame", nil, b)
    b.over:SetAllPoints()
    b.ends = { NewMark(b.over, WHITE, PIN_SIZE / 2), NewMark(b.over, WHITE, PIN_SIZE / 2) }
    b.ends[1].icon:SetPoint("CENTER", b, "LEFT")
    b.ends[2].icon:SetPoint("CENTER", b, "RIGHT")
    b.you = NewMark(b.over, WHITE, 2, PIN_SIZE + 4)
    b.you.icon:SetPoint("CENTER", b, "CENTER")
    -- The stops ride a strip inside a clipping frame (see ScrollStrip).
    b.clip = CreateFrame("Frame", nil, b)
    b.clip:SetClipsChildren(true)
    b.clip.strip = CreateFrame("Frame", nil, b.clip)
    b.clip.strip:SetSize(1, 1)
    b.clip.glide = b.clip.strip:CreateAnimationGroup()
    b.clip.glide.move = b.clip.glide:CreateAnimation("Translation")
    b.clip.glide.move:SetSmoothing("NONE")
    b.clip.glide.move:SetDuration(SLIDE)
    b.stops = {}
    return b
end

local function CreateBar()
    if bar then return end
    bar = BuildBar(UIParent)
    bar:Hide()
    StyleBar(bar, flight)
    F.Place(bar)
end

local RefreshPreview -- the options preview's restyle; defined with it below

local function ApplyStyle()
    if bar then StyleBar(bar, flight) end
    RefreshPreview()
end

-- Shows or hides the bar, faded in and out when the setting is on. Same fade
-- as EllesmereUI's widget tooltips: 0.25 s, easing out on show, in on hide.
local FADE_TIME = 0.25
local function ShowBar(show)
    local g = bar.fade
    if g then g:Stop() end
    if not Get("fade") then
        bar:SetAlpha(1)
        bar:SetShown(show)
        return
    end
    if not show and not bar:IsShown() then return end
    if not g then
        g = bar:CreateAnimationGroup()
        g.alpha = g:CreateAnimation("Alpha")
        g.alpha:SetDuration(FADE_TIME)
        g:SetScript("OnFinished", function(self)
            bar:SetAlpha(self.to)
            if self.to == 0 then bar:Hide() end
        end)
        bar.fade = g
    end
    if show and not bar:IsShown() then
        bar:SetAlpha(0)
        bar:Show()
    end
    g.to = show and 1 or 0
    g.alpha:SetFromAlpha(bar:GetAlpha())
    g.alpha:SetToAlpha(g.to)
    g.alpha:SetSmoothing(show and "OUT" or "IN")
    g:Play()
end

local function EndFlight()
    flight = nil
    if ticker then ticker:Cancel(); ticker = nil end
    if bar then ShowBar(false) end
end

local Land

local function UpdateText()
    local elapsed = GetTime() - flight.start
    if elapsed > 2 and not UnitOnTaxi("player") then
        -- Landing edge missed (PLAYER_CONTROL_GAINED is the precise one): end the
        -- flight here instead of running on, but learn nothing from a late read.
        flight.early = true
        Land()
    elseif flight.eta then
        bar.time:SetText(TimeLeft(flight, elapsed))
        ScrollStrip(bar, flight, elapsed)
    else
        bar.time:SetText(FormatTime(elapsed))
    end
end

local function ArmTimer(b, fl)
    if not fl.eta then return end
    local dur = C_DurationUtil.CreateDuration()
    dur:SetTimeFromStart(fl.start, fl.eta)
    b.track:SetTimerDuration(dur,Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
end

-- points: every node on the way, start first (see RouteInfo).
local function StartFlight(yards, points)
    flight = { yards = yards, start = GetTime(), points = points }
    if yards then
        flight.mult = SpeedMultiplier()
        flight.eta = yards / (Speed() * flight.mult)
    end
    CreateBar()
    ArmTimer(bar, flight)
    ShowBar(true)
    StyleBar(bar, flight)
    UpdateText()
    if not ticker then ticker = C_Timer.NewTicker(1, UpdateText) end
end

-- An early landing stops at the next node on the way: the timer and the
-- route end there instead. Nothing is learned from it.
-- Assumes the server lands at the very next node: a request made right on top
-- of one may land at the node after, and the bar then ends early.
local function Retarget(b, fl)
    fl.early = true
    local points = fl.points
    if points and fl.yards and fl.eta then
        local flown = (GetTime() - fl.start) / fl.eta * fl.yards
        for i, p in ipairs(points) do
            if p.yards and p.yards > flown then
                for j = #points, i + 1, -1 do points[j] = nil end
                fl.eta = fl.eta * p.yards / fl.yards
                fl.yards = p.yards
                ArmTimer(b, fl)
                break
            end
        end
    end
    StyleBar(b, fl)
end

-- Moves the stored speed a quarter of the way toward what this flight measured.
-- A flight more than a third off the estimate is treated as bad data, not a speed.
-- The stored speed excludes Frequent Flier so every character can share it.
Land = function()
    if flight.yards and not flight.early then
        local measured = flight.yards / (GetTime() - flight.start) / flight.mult
        local speed = Speed()
        if measured > speed * 0.75 and measured < speed * 1.33 then
            Cfg().speed = speed + (measured - speed) * 0.25
        end
    end
    EndFlight()
end

local function OnEvent(_, event)
    if event == "PLAYER_CONTROL_LOST" then
        -- UnitOnTaxi is still false when this fires at takeoff, so a fresh
        -- flight-map click is the signal. A click the server refused leaves
        -- pending behind; a takeoff minutes later must not start a flight from
        -- it. A stun right after a refused click is ended by UpdateText's
        -- not-on-taxi check two seconds in.
        if pending and GetTime() - pending.clicked < 5 then
            StartFlight(pending.yards, pending.points)
        end
        pending = nil
    elseif event == "PLAYER_CONTROL_GAINED" then
        if flight and not UnitOnTaxi("player") then Land() end
    end
end

local function OnTakeTaxiNode(slot)
    if not Enabled() then return end
    local yards, points = RouteInfo(slot)
    pending = { yards = yards, points = points, clicked = GetTime() }
end

local function Apply()
    if Enabled() then
        if not hooked then
            hooksecurefunc("TakeTaxiNode", OnTakeTaxiNode)
            hooksecurefunc("TaxiRequestEarlyLanding", function()
                if flight then
                    Retarget(bar, flight)
                    UpdateText()
                end
            end)
            hooked = true
        end
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        events:RegisterEvent("PLAYER_CONTROL_LOST")
        events:RegisterEvent("PLAYER_CONTROL_GAINED")
    else
        if events then events:UnregisterAllEvents() end
        pending = nil
        if flight then EndFlight() end
    end
end

-------------------------------------------------------------------------------
--  Options preview: the same display in the Travel page's content header,
--  flying a real route of the player's faction (PREVIEW_ROUTES) on a loop,
--  sped up. Built when the page first opens; its ticker runs only while it is
--  visible, so a closed panel or another page costs nothing.
-------------------------------------------------------------------------------
local preview -- view, bar, the sample route and the flight drawn from it
local StartPreviewFlight

local function PreviewTick()
    local v, fl = preview, preview.flight
    local elapsed = GetTime() - fl.start
    -- The finished flight holds a moment, then the next one starts.
    if elapsed >= fl.eta + PREVIEW_HOLD then return StartPreviewFlight() end
    elapsed = math.min(elapsed, fl.eta)
    v.bar.time:SetText(TimeLeft(fl, elapsed))
    ScrollStrip(v.bar, fl, elapsed)
end

StartPreviewFlight = function()
    local v = preview
    local fl, points = v.flight, v.points
    -- An early landing cuts the route short: refill it from the full one.
    for i, p in ipairs(v.route) do points[i] = p end
    for i = #v.route + 1, #points do points[i] = nil end
    fl.points, fl.yards, fl.start, fl.early = points, v.yards, GetTime(), nil
    fl.eta = PREVIEW_SECONDS
    fl.lookahead = LOOKAHEAD * PREVIEW_SECONDS / (v.yards / Speed())
    ArmTimer(v.bar, fl)
    StyleBar(v.bar, fl)
    PreviewTick()
end

local RefreshPreviewNow -- RefreshPreview's body, defined below

local function PreviewShow()
    if preview.ticker then return end
    StartPreviewFlight()
    -- Settings may have changed while the page was away.
    RefreshPreviewNow()
    preview.ticker = C_Timer.NewTicker(1, PreviewTick)
end

local function PreviewHide()
    if preview.ticker then
        preview.ticker:Cancel()
        preview.ticker = nil
    end
    preview.bar.clip.glide:Stop()
end

-- The preview's early exit button lands the sample flight at its next stop.
local function PreviewLanding()
    local fl = preview.flight
    if fl.early then return end
    Retarget(preview.bar, fl)
    PreviewTick()
end

RequestLanding = function(b)
    if b == bar then
        -- The hook on TaxiRequestEarlyLanding retargets the bar.
        if flight and not flight.early then TaxiRequestEarlyLanding() end
    else
        PreviewLanding()
    end
end

-- force: draw while the header is still being built (not shown yet).
RefreshPreview = function(force)
    local v = preview
    if not (v and (force or v.view:IsVisible())) then return end
    RefreshPreviewNow()
end

RefreshPreviewNow = function()
    local v = preview
    -- Scaled down when the bar, the time on its left and the early exit
    -- button on its right are wider than the header.
    local w = Get("width") + 2 * (PIN_SIZE / 2 + 6 + EXIT_SIZE)
    local pw = v.view:GetParent():GetWidth()
    local available = (pw > 0 and pw) or v.availableWidth or w + 40
    local scale = math.min(1, math.max(100, available - 40) / w)
    v.bar:SetScale(scale)
    StyleBar(v.bar, v.flight)
    v.previewHeight = BoxHeight() * scale + 30
    v.view:SetHeight(v.previewHeight)
    if v.onHeightChanged then v.onHeightChanged(v.previewHeight) end
end

local hookedParents = {}
local function CreateSettingsPreview(parent, availableWidth, onHeightChanged)
    local v = preview
    if not v then
        local route = PREVIEW_ROUTES[UnitFactionGroup("player")] or PREVIEW_ROUTES.Alliance
        v = { route = {}, points = {}, flight = {}, yards = 0 }
        for i = 1, #route, 2 do
            if i > 1 then v.yards = v.yards + routes[route[i - 2] * 10000 + route[i]] end
            v.route[#v.route + 1] = { name = route[i + 1], yards = v.yards }
        end
        v.view = CreateFrame("Frame", nil, parent)
        v.bar = BuildBar(v.view)
        v.bar:SetPoint("CENTER")
        v.view:SetScript("OnShow", PreviewShow)
        v.view:SetScript("OnHide", PreviewHide)
        preview = v
        StartPreviewFlight()
    end
    -- Frames outlive a page rebuild, so the view is reused.
    v.availableWidth, v.onHeightChanged = availableWidth, onHeightChanged
    v.view:SetParent(parent)
    v.view:ClearAllPoints()
    v.view:SetPoint("TOPLEFT")
    v.view:SetPoint("TOPRIGHT")
    if not hookedParents[parent] then
        hookedParents[parent] = true
        local lastWidth
        parent:HookScript("OnSizeChanged", function(_, width)
            if width == lastWidth then return end
            lastWidth = width
            if v.view:GetParent() == parent then RefreshPreview() end
        end)
    end
    v.view:Show()
    RefreshPreview(true)
    -- A new frame starts shown, so no OnShow fires for the first open.
    if v.view:IsVisible() then PreviewShow() end
    return v
end

-- Options-page entry points.
EllesmereUI._FlightTimer = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    ApplyStyle = ApplyStyle,
    ApplyPosition = function() F.Place(bar) end,
    textures = { lookup = BAR_TEXTURES, names = BAR_TEXTURE_NAMES, order = BAR_TEXTURE_ORDER },
    CreateSettingsPreview = CreateSettingsPreview,
}

F.Start(Apply, {
    key = "EUI_FlightTimer", label = "Flight Timer", order = 730, minWidth = 50,
    frame = function(build)
        if build then CreateBar() end
        return bar
    end,
    -- Follows the text around the track.
    height = BoxHeight,
    applyStyle = ApplyStyle,
})
