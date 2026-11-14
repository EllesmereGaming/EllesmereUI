if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EllesmereUI_HealthBars.lua
--  Finds EllesmereUI's health bars (nameplates, unit frames, raid and party
--  frames) and hands each one to the bar features (Health Ticks, Health
--  Animations). It reads the module namespaces through EllesmereUI._ModuleNS and
--  changes no module file. Nothing is registered while no feature is on.
--
--  A feature (HB.AddFeature) is a table:
--    Resolve()          settings changed: rebuild what the feature needs per place
--    Wants(place)       true when the feature draws on that place now
--    Apply(bar, e, force)  draw on the bar. Called only while the unit exists and
--                       the bar fills left to right. force: a new occupant or a new
--                       max health, so start over
--    Clear(bar, e)      remove what the feature drew (cheap when nothing is there)
--    Health(unit, set)  optional, UNIT_HEALTH: set = HB.byUnit[unit] (bar -> entry)
--    Redo(bar, e)       optional, after a loading screen: build the bar's drawing again
--  An entry e: place, unit, kind ("plate", "raid", "unit"), owner, ffd.
--  Features keep their per-bar state in weak tables of their own.
--------------------------------------------------------------------------------
local EllesmereUI = EllesmereUI

local pairs, ipairs, next, type = pairs, ipairs, next, type
local UnitExists = UnitExists
local GetTime = GetTime
local EMPTY = {}

local HB = {}
EllesmereUI.HealthBars = HB

-- group: where EllesmereUI draws the bar. anim: Health Animations covers it.
-- mine: My Damage Colors works there (enemy plates only).
HB.PLACES = {
    { id = "enemy",        label = "Enemy Nameplates",    group = "plates", anim = true, mine = true },
    { id = "friendly",     label = "Friendly Nameplates", group = "plates", anim = true },
    { id = "raid",         label = "Raid Frames",         group = "raid",   anim = true },
    { id = "party",        label = "Party Frames",        group = "raid",   anim = true },
    { id = "player",       label = "Player Frame",        group = "unit" },
    { id = "target",       label = "Target Frame",        group = "unit" },
    { id = "focus",        label = "Focus Frame",         group = "unit" },
    { id = "targettarget", label = "Target of Target",    group = "unit" },
    { id = "focustarget",  label = "Focus Target",        group = "unit" },
    { id = "pet",          label = "Pet Frame",           group = "unit" },
    { id = "boss",         label = "Boss Frames",         group = "unit" },
}
HB.PLACE = {}
for _, def in ipairs(HB.PLACES) do HB.PLACE[def.id] = def end

local UF_UNITS = {
    player = { "player" }, target = { "target" }, focus = { "focus" },
    targettarget = { "targettarget" }, focustarget = { "focustarget" },
    pet = { "pet" }, boss = { "boss1", "boss2", "boss3", "boss4", "boss5" },
}

local PLATE_TOKEN, RAID_TOKEN = {}, {}
for i = 1, 40 do
    PLATE_TOKEN["nameplate" .. i] = true
    RAID_TOKEN["raid" .. i] = true
end
for i = 1, 4 do RAID_TOKEN["party" .. i] = true end
RAID_TOKEN.player = true

local function ModNS(folder)
    local reg = EllesmereUI._ModuleNS
    return type(reg) == "table" and reg[folder] or nil
end
local function NP() return ModNS("EllesmereUINameplates") end
local function RF() return ModNS("EllesmereUIRaidFrames") end
local function UF() return ModNS("EllesmereUIUnitFrames") end

-------------------------------------------------------------------------------
--  Features
-------------------------------------------------------------------------------
local FEATURES = {}
local WANT = {}   -- WANT[place] = at least one feature draws there
local anyOn = false
local reported = {}

-- A feature error is shown once, then ignored, so one bug cannot break the
-- other feature or spam the player.
local function Safe(f, fn, ...)
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok and not reported[f] then
        reported[f] = true
        geterrorhandler()(err)
    end
end

function HB.AddFeature(f)
    FEATURES[#FEATURES + 1] = f
end

local function Resolve()
    for i = 1, #FEATURES do Safe(FEATURES[i], FEATURES[i].Resolve) end
    anyOn = false
    for _, def in ipairs(HB.PLACES) do
        local w = false
        for i = 1, #FEATURES do
            if FEATURES[i].Wants(def.id) then
                w = true
                break
            end
        end
        WANT[def.id] = w
        if w then anyOn = true end
    end
end

-------------------------------------------------------------------------------
--  Attached bars. BARS[bar] = entry; byUnit[unit][bar] = entry (unit events).
-------------------------------------------------------------------------------
local BARS = setmetatable({}, { __mode = "k" })
local byUnit = {}
HB.BARS, HB.byUnit = BARS, byUnit

-- The features follow a left-to-right horizontal fill only.
local function AxisOK(bar)
    if bar:GetOrientation() == "VERTICAL" then return false end
    if bar:GetReverseFill() then return false end
    if bar._euiInv then return false end
    return true
end

local function Apply(bar, e, force)
    local unit = e.unit
    local ok = (unit and UnitExists(unit) and AxisOK(bar)) and true or false
    local place = e.place
    for i = 1, #FEATURES do
        local f = FEATURES[i]
        if ok and f.Wants(place) then
            Safe(f, f.Apply, bar, e, force)
        else
            Safe(f, f.Clear, bar, e)
        end
    end
end

local function Unlink(bar, e)
    local u = e.unit
    if u then
        local set = byUnit[u]
        if set then set[bar] = nil end
    end
    e.unit = nil
end

local function Detach(bar)
    local e = BARS[bar]
    if not e then return end
    for i = 1, #FEATURES do Safe(FEATURES[i], FEATURES[i].Clear, bar, e) end
    Unlink(bar, e)
end
HB.Detach = Detach

local function Attach(bar, place, unit, kind, owner, force, ffd)
    if not WANT[place] then
        Detach(bar)
        return
    end
    local e = BARS[bar]
    if not e then
        e = {}
        BARS[bar] = e
    end
    local same = (e.unit == unit and e.place == place and e.owner == owner)
    if e.unit ~= unit then
        Unlink(bar, e)
        local set = byUnit[unit]
        if not set then
            set = {}
            byUnit[unit] = set
        end
        set[bar] = e
        e.unit = unit
    end
    e.place, e.kind, e.owner, e.ffd = place, kind, owner, ffd
    Apply(bar, e, force or not same)
end

-------------------------------------------------------------------------------
--  Nameplates
-------------------------------------------------------------------------------
-- The plate for a token: (plate, place) or nil.
local function PlateFor(unit)
    local np = NP()
    if not np then return nil end
    local pl = np.plates and np.plates[unit]
    if pl and pl.unit == unit and pl.health then return pl, "enemy" end
    pl = np.friendlyPlates and np.friendlyPlates[unit]
    if pl and pl.unit == unit and pl.health then return pl, "friendly" end
    return nil
end

local function AttachPlate(unit, force)
    local pl, place = PlateFor(unit)
    if not pl then return false end
    Attach(pl.health, place, unit, "plate", pl, force)
    return true
end

local function DetachKindForUnit(unit, kind)
    local set = byUnit[unit]
    if not set then return end
    for bar, e in pairs(set) do
        if e.kind == kind then Detach(bar) end  -- only clears its own key
    end
end

local function ScanPlates(force)
    local np = NP()
    for bar, e in pairs(BARS) do
        if e.kind == "plate" and e.unit then
            local pl = PlateFor(e.unit)
            if pl ~= e.owner then Detach(bar) end
        end
    end
    if not np then return end
    for _, pl in pairs(np.plates or EMPTY) do
        local u = pl.unit
        if u and pl.health then Attach(pl.health, "enemy", u, "plate", pl, force) end
    end
    for _, pl in pairs(np.friendlyPlates or EMPTY) do
        local u = pl.unit
        if u and pl.health then Attach(pl.health, "friendly", u, "plate", pl, force) end
    end
end

-------------------------------------------------------------------------------
--  Raid and party frames
-------------------------------------------------------------------------------
local raidQueued, raidForce, lastLazyRaid = false, false, 0
local SCAN_SEEN = {}

local function ScanRaid(force)
    local rf = RF()
    local seen = SCAN_SEEN
    for k in pairs(seen) do seen[k] = nil end
    if rf and type(rf.GetFFD) == "function" then
        local lists = { rf._allButtons, rf._partyAllButtons }
        for li = 1, 2 do
            local list = lists[li]
            if type(list) == "table" then
                for i = 1, #list do
                    local btn = list[i]
                    local d = btn and rf.GetFFD(btn)
                    local bar = d and d.health
                    if bar and d.styled and btn:IsVisible() then
                        local unit = btn:GetAttribute("unit")
                        if type(unit) == "string" and unit ~= "" then
                            Attach(bar, d._isParty and "party" or "raid", unit, "raid", btn, force, d)
                            seen[bar] = true
                        end
                    end
                end
            end
        end
    end
    for bar, e in pairs(BARS) do
        if e.kind == "raid" and e.unit and not seen[bar] then Detach(bar) end
    end
end

local function QueueRaidScan(force, delay)
    if force then raidForce = true end
    if raidQueued then return end
    raidQueued = true
    C_Timer.After(delay or 0, function()
        raidQueued = false
        local f = raidForce
        raidForce = false
        if anyOn then ScanRaid(f) end
    end)
end

-- A raid or party token fired an event but has no bar: look again, at most
-- every 3 seconds (EllesmereUI may build or show its frames late).
local function LazyRaid()
    local now = GetTime()
    if now - lastLazyRaid < 3 then return end
    lastLazyRaid = now
    QueueRaidScan(false)
end

-------------------------------------------------------------------------------
--  Unit frames
-------------------------------------------------------------------------------
local function ScanUnit(place, force)
    local uf = UF()
    local frames = uf and uf.frames
    for _, unit in ipairs(UF_UNITS[place]) do
        local f = type(frames) == "table" and frames[unit]
        local bar = type(f) == "table" and f.Health
        if bar then Attach(bar, place, unit, "unit", f, force) end
    end
end

-- The owner still shows this unit on this bar.
local function StillValid(bar, e, unit)
    local kind = e.kind
    if kind == "plate" then
        local pl = PlateFor(unit)
        return pl ~= nil and pl == e.owner and pl.health == bar
    elseif kind == "raid" then
        return e.owner:GetAttribute("unit") == unit
    end
    return true
end

-------------------------------------------------------------------------------
--  Events (registered only while a feature is on)
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local H = {}

-- Detaches the bars of a token whose owner moved on. Returns whether a valid
-- plate bar and a valid raid bar remain.
local function CheckUnit(unit, set)
    local hasPlate, hasRaid = false, false
    for bar, e in pairs(set) do
        if not StillValid(bar, e, unit) then
            Detach(bar)  -- only clears its own key: allowed during the walk
        elseif e.kind == "plate" then
            hasPlate = true
        elseif e.kind == "raid" then
            hasRaid = true
        end
    end
    return hasPlate, hasRaid
end

local function FindMissing(unit, hasPlate, hasRaid)
    if not hasPlate and PLATE_TOKEN[unit] then
        AttachPlate(unit, true)
    elseif not hasRaid and RAID_TOKEN[unit] then
        LazyRaid()
    end
end

function H.UNIT_HEALTH(unit)
    local set = byUnit[unit]
    local hasPlate, hasRaid = false, false
    if set and next(set) then
        hasPlate, hasRaid = CheckUnit(unit, set)
        if next(set) then
            for i = 1, #FEATURES do
                local f = FEATURES[i]
                if f.Health then Safe(f, f.Health, unit, set) end
            end
        end
    end
    FindMissing(unit, hasPlate, hasRaid)
end

function H.UNIT_MAXHEALTH(unit)
    local set = byUnit[unit]
    local hasPlate, hasRaid = false, false
    if set and next(set) then
        hasPlate, hasRaid = CheckUnit(unit, set)
        for bar, e in pairs(set) do Apply(bar, e, true) end
    end
    FindMissing(unit, hasPlate, hasRaid)
end

function H.NAME_PLATE_UNIT_ADDED(unit)
    DetachKindForUnit(unit, "plate")
    if not AttachPlate(unit, true) then
        -- The plate may be attached after this handler: look again a frame later.
        C_Timer.After(0, function()
            if anyOn then AttachPlate(unit, true) end
        end)
    end
end

function H.NAME_PLATE_UNIT_REMOVED(unit)
    DetachKindForUnit(unit, "plate")
end

function H.PLAYER_TARGET_CHANGED()
    ScanUnit("target", true)
    ScanUnit("targettarget", true)
end

function H.PLAYER_FOCUS_CHANGED()
    ScanUnit("focus", true)
    ScanUnit("focustarget", true)
end

function H.UNIT_TARGET(unit)
    if unit == "target" then
        ScanUnit("targettarget", true)
    elseif unit == "focus" then
        ScanUnit("focustarget", true)
    end
end

function H.UNIT_PET(unit)
    if unit == "player" then ScanUnit("pet", true) end
end

function H.INSTANCE_ENCOUNTER_ENGAGE_UNIT()
    ScanUnit("boss", true)
    C_Timer.After(0.2, function()
        if anyOn then ScanUnit("boss", true) end
    end)
end

function H.GROUP_ROSTER_UPDATE()
    -- A token may have a new occupant: the secure headers reassign their buttons
    -- in their own handler, so look a frame later, and once more after a moment.
    QueueRaidScan(true, 0)
    C_Timer.After(0.5, function() QueueRaidScan(false) end)
end

function H.PLAYER_ENTERING_WORLD()
    C_Timer.After(0, function() HB.Refresh(true) end)
end

-- A push in the first frames after a loading screen can run before the game has
-- laid the frames out: build every drawn bar again once it has.
function H.LOADING_SCREEN_DISABLED()
    C_Timer.After(0.5, function()
        if not anyOn then return end
        for bar, e in pairs(BARS) do
            if e.unit then
                for i = 1, #FEATURES do
                    local f = FEATURES[i]
                    if f.Redo then Safe(f, f.Redo, bar, e) end
                end
            end
        end
        HB.Refresh(true)
    end)
end

ev:SetScript("OnEvent", function(_, event, a1)
    local h = H[event]
    if h then h(a1) end
end)

local BASE_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "NAME_PLATE_UNIT_ADDED",
    "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD",
    "LOADING_SCREEN_DISABLED" }
local registered = false

local function SyncEvents()
    if anyOn and not registered then
        for _, e in ipairs(BASE_EVENTS) do ev:RegisterEvent(e) end
        ev:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
        ev:RegisterUnitEvent("UNIT_PET", "player")
        registered = true
    elseif not anyOn and registered then
        for _, e in ipairs(BASE_EVENTS) do ev:UnregisterEvent(e) end
        ev:UnregisterEvent("UNIT_TARGET")
        ev:UnregisterEvent("UNIT_PET")
        registered = false
    end
end

-------------------------------------------------------------------------------
--  Refresh: settings changed, a profile switch or a new world. force: redraw
--  every bar. An option change calls QueueRefresh (one pass per 0.05 s, so a
--  slider drag draws once per pause, not once per step).
-------------------------------------------------------------------------------
function HB.Refresh(force)
    Resolve()
    SyncEvents()
    if not anyOn then
        for bar in pairs(BARS) do Detach(bar) end
        return
    end
    ScanPlates(force)
    ScanRaid(force)
    for place in pairs(UF_UNITS) do ScanUnit(place, force) end
end

local refreshQueued = false
function HB.QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.05, function()
        refreshQueued = false
        HB.Refresh(false)
    end)
end

-- One refresh at login (the saved settings are there by then). The event leaves
-- the list afterwards.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    HB.Refresh(true)
end)
