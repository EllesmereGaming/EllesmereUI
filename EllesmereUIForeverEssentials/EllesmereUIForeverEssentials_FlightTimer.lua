if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_FlightTimer.lua  (WoW Forever only)
--  Progress bar with an ETA for flight-master flights. Route lengths come from
--  the game's TaxiPath data (EllesmereUIForeverEssentials_FlightTimerData.lua);
--  the client exposes no flight duration, so time is length / speed, with the
--  speed corrected by every flight that lands normally.
-------------------------------------------------------------------------------
local DEFAULT_SPEED = 30.4 -- yards per second; fitted to measured Classic flight times
local PREVIEW_SECONDS = 15
local TEXT_PAD = 6

-- Settings live in EllesmereUIDB.flightTimer; unset keys read these.
local DEFAULTS = {
    width = 240, height = 20,
    texture = "none",
    fillOpacity = 100, classColored = false,
    bgA = 0.8,
    borderSize = 1, borderR = 0, borderG = 0, borderB = 0,
    destText = "left", destSize = 12, destX = 0, destY = 0,
    timeText = "right", timeSize = 12, timeX = 0, timeY = 0,
    showTotal = false,
    font = "__global", outlineMode = "__global",
}

local BAR_TEXTURES, BAR_TEXTURE_NAMES, BAR_TEXTURE_ORDER = EllesmereUI.BuildBarTextureTables()

local routes = EllesmereUI._FlightTimerRoutes
local bar, events, ticker, hooked
local pending   -- destination picked on the flight map, waiting for takeoff
local flight    -- the flight in progress

-- Cfg() is the WRITE accessor (creates the table); Read() never creates it, so
-- a user who never touches the feature gets no saved table.
local function Cfg()
    if not EllesmereUIDB then return {} end
    EllesmereUIDB.flightTimer = EllesmereUIDB.flightTimer or {}
    return EllesmereUIDB.flightTimer
end

local _NOCFG = {}
local function Read()
    return EllesmereUIDB and EllesmereUIDB.flightTimer or _NOCFG
end

local function Get(key)
    local v = Read()[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

local function Enabled()
    return Read().enabled == true
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
local function RouteYards(slot)
    -- The taxi UI can open without a map id; no id means no route lookup.
    local mapID = GetTaxiMapID and GetTaxiMapID()
    local nodes = mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes(mapID)
    if not nodes then return nil end
    local idBySlot = {}
    for _, node in ipairs(nodes) do
        idBySlot[node.slotIndex] = node.nodeID
    end
    local yards = 0
    for hop = 1, GetNumRoutes(slot) do
        local from = idBySlot[TaxiGetNodeSlot(slot, hop, true)]
        local to = idBySlot[TaxiGetNodeSlot(slot, hop, false)]
        local hopYards = from and to and routes[from * 10000 + to]
        if not hopYards then return nil end
        yards = yards + hopYards
    end
    return yards > 0 and yards or nil
end

local function ApplyPosition()
    local pos = Read().pos
    bar:ClearAllPoints()
    if pos and pos.point then
        bar:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, 250)
    end
end

-- "__global" follows the EUI Fonts & Colors defaults; anything else is a key
-- in the shared font registry.
local function TextFont()
    local key = Get("font")
    local path = key ~= "__global" and EllesmereUI.ResolveFontName(key)
    return path or EllesmereUI.GetFontPath("essentials")
end

local function TextOutline()
    local mode = Get("outlineMode")
    if mode == "outline" then return EllesmereUI.SlugFlag("OUTLINE, SLUG") end
    if mode == "thick" then return EllesmereUI.SlugFlag("THICKOUTLINE, SLUG") end
    if mode == "none" then return "" end
    return EllesmereUI.GetFontOutlineFlag("essentials")
end

local function StyleText(fs, prefix, font, flag)
    local side = Get(prefix .. "Text")
    if side == "none" then fs:Hide(); return end
    local x, y = Get(prefix .. "X"), Get(prefix .. "Y")
    -- An empty flag means Drop Shadow, which only renders through the font object.
    EllesmereUI.PrimeFontShadow(fs, flag == "")
    fs:SetFont(font, Get(prefix .. "Size"), flag)
    fs:ClearAllPoints()
    if side == "left" then
        fs:SetPoint("LEFT", bar, "LEFT", TEXT_PAD + x, y)
        fs:SetJustifyH("LEFT")
    elseif side == "right" then
        fs:SetPoint("RIGHT", bar, "RIGHT", -TEXT_PAD + x, y)
        fs:SetJustifyH("RIGHT")
    else
        fs:SetPoint("CENTER", bar, "CENTER", x, y)
        fs:SetJustifyH("CENTER")
    end
    fs:Show()
end

-- The fill's one alpha owner: a texture's SetAlpha and its colour alpha are the
-- same channel, so the user's opacity and the elapsed-only hide are both set
-- here. A plain SetValue does not reliably take the fill back from an armed
-- SetTimerDuration, so an elapsed-only flight hides the fill instead.
local function ApplyFillColor()
    local r, g, b = FillColor()
    local a = (flight and not flight.eta) and 0 or Get("fillOpacity") / 100
    bar:SetStatusBarColor(r, g, b, a)
end

local function ApplyStyle()
    if not bar then return end
    local PP = EllesmereUI.PP
    bar:SetSize(Get("width"), Get("height"))
    bar:SetStatusBarTexture(EllesmereUI.ResolveTexturePath(BAR_TEXTURES, Get("texture"), "Interface\\Buttons\\WHITE8x8"))
    ApplyFillColor()
    bar.bg:SetColorTexture(0.1, 0.1, 0.1, Get("bgA"))
    local bs = Get("borderSize")
    if bs > 0 then
        PP.UpdateBorder(bar, bs, Get("borderR"), Get("borderG"), Get("borderB"), 1)
        PP.ShowBorder(bar)
    else
        PP.HideBorder(bar)
    end
    local font, flag = TextFont(), TextOutline()
    StyleText(bar.dest, "dest", font, flag)
    StyleText(bar.time, "time", font, flag)
    bar.dest:SetWidth(math.max(1, Get("width") - 2 * TEXT_PAD))
end

local function CreateBar()
    if bar then return end
    bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    EllesmereUI.PP.CreateBorder(bar, 0, 0, 0, 1, 1, "OVERLAY", 2)
    bar.time = bar:CreateFontString(nil, "OVERLAY")
    bar.dest = bar:CreateFontString(nil, "OVERLAY")
    bar.dest:SetWordWrap(false)
    bar:Hide()
    ApplyStyle()
    ApplyPosition()
end

local function EndFlight()
    flight = nil
    if ticker then ticker:Cancel(); ticker = nil end
    if bar then bar:Hide() end
end

local Land

local function UpdateText()
    local elapsed = GetTime() - flight.start
    if flight.preview and elapsed >= flight.eta then
        EndFlight()
    elseif not flight.preview and elapsed > 2 and not UnitOnTaxi("player") then
        -- Landing edge missed (PLAYER_CONTROL_GAINED is the precise one): end the
        -- flight here instead of running on, but learn nothing from a late read.
        flight.early = true
        Land()
    elseif flight.eta then
        local left = FormatTime(flight.eta - elapsed)
        bar.time:SetText(Get("showTotal") and (left .. " / " .. FormatTime(flight.eta)) or left)
    else
        bar.time:SetText(FormatTime(elapsed))
    end
end

local function StartFlight(dest, yards, preview)
    local now = GetTime()
    flight = { dest = dest, yards = yards, start = now, preview = preview }
    if preview then
        flight.eta = PREVIEW_SECONDS
    elseif yards then
        flight.mult = SpeedMultiplier()
        flight.eta = yards / (Speed() * flight.mult)
    end
    CreateBar()
    bar.dest:SetText(dest or "")
    ApplyFillColor()
    if flight.eta then
        local dur = C_DurationUtil.CreateDuration()
        dur:SetTimeFromStart(now, flight.eta)
        bar:SetTimerDuration(dur, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
    end
    UpdateText()
    bar:Show()
    if not ticker then ticker = C_Timer.NewTicker(1, UpdateText) end
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
        -- Only a taxi takeoff counts: a stun or fear neither starts a flight nor
        -- uses up the pending click. A click the server refused leaves pending
        -- behind; a takeoff minutes later must not start a flight from it.
        if UnitOnTaxi("player") then
            if pending and GetTime() - pending.clicked < 5 then
                StartFlight(pending.dest, pending.yards)
            end
            pending = nil
        end
    elseif event == "PLAYER_CONTROL_GAINED" then
        if flight and not flight.preview and not UnitOnTaxi("player") then Land() end
    end
end

local function OnTakeTaxiNode(slot)
    if not Enabled() then return end
    pending = { dest = TaxiNodeName(slot), yards = RouteYards(slot), clicked = GetTime() }
end

local function Apply()
    if Enabled() then
        if not hooked then
            hooksecurefunc("TakeTaxiNode", OnTakeTaxiNode)
            hooksecurefunc("TaxiRequestEarlyLanding", function()
                if flight then flight.early = true end
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

-- Options-page entry points.
EllesmereUI._FlightTimer = {
    Get = Get,
    Cfg = Cfg,
    Apply = Apply,
    ApplyStyle = ApplyStyle,
    ApplyPosition = function() if bar then ApplyPosition() end end,
    textures = { lookup = BAR_TEXTURES, names = BAR_TEXTURE_NAMES, order = BAR_TEXTURE_ORDER },
    Preview = function()
        if flight and not flight.preview then return end
        StartFlight(EllesmereUI.L("Flight Timer Preview"), nil, true)
    end,
}

local function Resized()
    ApplyStyle()
    if EllesmereUI._unlockActive and EllesmereUI.RepositionBarToMover then
        EllesmereUI.RepositionBarToMover("EUI_FlightTimer")
    end
end

local function RegisterUnlock()
    local MK = EllesmereUI.MakeUnlockElement
    local PPs = EllesmereUI.PP
    EllesmereUI:RegisterUnlockElements({
        MK({
            key      = "EUI_FlightTimer",
            label    = "Flight Timer",
            group    = "Forever Essentials",
            order    = 730,
            isHidden = function() return not Enabled() end,
            -- Nothing is built while the feature is off (the unlock core calls
            -- getFrame / applyPos for every element at each login).
            getFrame = function()
                if not Enabled() then return nil end
                CreateBar()
                return bar
            end,
            getSize = function() return Get("width"), Get("height") end,
            setWidth = function(_, w)
                Cfg().width = math.max(50, PPs.Snap(w))
                Resized()
            end,
            setHeight = function(_, h)
                Cfg().height = math.max(4, PPs.Snap(h))
                Resized()
            end,
            savePos = function(_, point, relPoint, x, y)
                if not point then return end
                Cfg().pos = { point = point, relPoint = relPoint, x = x, y = y }
                if bar and not EllesmereUI._unlockActive then ApplyPosition() end
            end,
            loadPos = function()
                local pos = Read().pos
                if pos and pos.point then return pos end
                return { point = "CENTER", relPoint = "CENTER", x = 0, y = 250 }
            end,
            clearPos = function()
                Cfg().pos = nil
                if bar then ApplyPosition() end
            end,
            applyPos = function()
                if not Enabled() then return end
                CreateBar()
                ApplyPosition()
            end,
        }),
    }, "EllesmereUIForeverEssentials")
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
    RegisterUnlock()
end)
