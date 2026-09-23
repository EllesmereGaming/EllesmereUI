if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIQoL_FlightTimer.lua  (WoW Forever only)
--  Progress bar with an ETA for flight-master flights. Route lengths come from
--  the game's TaxiPath data (EllesmereUIQoL_FlightTimerData.lua); the client
--  exposes no flight duration, so time is length / speed, with the speed
--  corrected by every flight that lands normally.
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

local function Cfg()
    if not EllesmereUIDB then return {} end
    EllesmereUIDB.flightTimer = EllesmereUIDB.flightTimer or {}
    return EllesmereUIDB.flightTimer
end

local function Get(key)
    local v = Cfg()[key]
    if v == nil then return DEFAULTS[key] end
    return v
end

local function Enabled()
    return Cfg().enabled == true
end

local function Speed()
    return Cfg().speed or DEFAULT_SPEED
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
    local c = Cfg()
    if c.fillR then return c.fillR, c.fillG, c.fillB end
    local EG = EllesmereUI.ELLESMERE_GREEN
    return EG.r, EG.g, EG.b
end

-- Sums the stored length of every hop on the way to slot; nil when any hop
-- is missing from the data, which leaves the bar showing elapsed time only.
local function RouteYards(slot)
    local idBySlot = {}
    for _, node in ipairs(C_TaxiMap.GetAllTaxiNodes(GetTaxiMapID())) do
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
    local pos = Cfg().pos
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
    return path or EllesmereUI.GetFontPath("extras")
end

local function TextOutline()
    local mode = Get("outlineMode")
    if mode == "outline" then return EllesmereUI.SlugFlag("OUTLINE, SLUG") end
    if mode == "thick" then return EllesmereUI.SlugFlag("THICKOUTLINE, SLUG") end
    if mode == "none" then return "" end
    return EllesmereUI.GetFontOutlineFlag("extras")
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

local function ApplyStyle()
    if not bar then return end
    local PP = EllesmereUI.PP
    bar:SetSize(Get("width"), Get("height"))
    bar:SetStatusBarTexture(EllesmereUI.ResolveTexturePath(BAR_TEXTURES, Get("texture"), "Interface\\Buttons\\WHITE8x8"))
    local r, g, b = FillColor()
    bar:SetStatusBarColor(r, g, b, Get("fillOpacity") / 100)
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

local function UpdateText()
    local elapsed = GetTime() - flight.start
    if flight.preview and elapsed >= flight.eta then
        EndFlight()
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
        flight.eta = yards / Speed()
    end
    CreateBar()
    bar.dest:SetText(dest or "")
    -- A plain SetValue does not reliably take the fill back from an armed
    -- SetTimerDuration, so an elapsed-only flight hides the fill instead.
    bar:GetStatusBarTexture():SetAlpha(flight.eta and 1 or 0)
    if flight.eta then
        local dur = C_DurationUtil.CreateDuration()
        dur:SetTimeFromStart(now, flight.eta)
        bar:SetTimerDuration(dur, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)
    end
    UpdateText()
    bar:Show()
    if not ticker then ticker = C_Timer.NewTicker(1, UpdateText) end
end

-- Moves the stored speed halfway toward what this flight measured. A flight
-- that ran more than 2x off the estimate is treated as bad data, not a speed.
local function Land()
    if flight.yards and not flight.early then
        local measured = flight.yards / (GetTime() - flight.start)
        local speed = Speed()
        if measured > speed * 0.5 and measured < speed * 2 then
            Cfg().speed = speed + (measured - speed) * 0.5
        end
    end
    EndFlight()
end

local function OnEvent(_, event)
    if event == "PLAYER_CONTROL_LOST" then
        -- A click the server refused leaves pending behind; a stun minutes later
        -- must not start a flight from it.
        if pending and GetTime() - pending.clicked < 5 then
            StartFlight(pending.dest, pending.yards)
        end
        pending = nil
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
            group    = "Quality of Life",
            order    = 730,
            isHidden = function() return not Enabled() end,
            getFrame = function()
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
                local pos = Cfg().pos
                if pos and pos.point then return pos end
                return { point = "CENTER", relPoint = "CENTER", x = 0, y = 250 }
            end,
            clearPos = function()
                Cfg().pos = nil
                if bar then ApplyPosition() end
            end,
            applyPos = function()
                CreateBar()
                ApplyPosition()
            end,
        }),
    })
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    Apply()
    RegisterUnlock()
end)
