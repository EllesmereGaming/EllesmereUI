if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_ThreatFeed.lua  (WoW Forever only)
--  The threat list for the Damage Meters "Threat" meter type: the threat
--  meter's data and settings (tracked unit, pets, pull aggro line, displayed
--  value, highlight colours) handed over as rows a Damage Meters window paints
--  in its own style. Damage Meters starts it while one of its windows shows
--  the list and stops it when none does, whatever the threat meter window's
--  own state. The two read through separate collectors, so neither rewrites
--  the rows the other has on screen.
-------------------------------------------------------------------------------
local _, module = ...
local ns = module.ThreatMeter
local EUI = EllesmereUI
local Get = ns.Get

local UPDATE_DELAY = 0.2
local FOLLOW_INTERVAL = 0.5
local PET_ICON = EUI.ClientIcon(132161)

local collector = ns.NewCollector()
local list = collector.list
local pool = {}                               -- pooled rows, by position
local sources = {}                            -- the rows on screen
local session = { combatSources = sources }   -- what a window paints
local events, active, notify
local pending, threatOn, flagsUnit, mobUnit, followTicker, titleName
local units = false   -- Force English Units, the Damage Meters setting the value text follows
local cfg             -- the list's settings, resolved once per settings change
local RequestUpdate

-- "1.", "2.", ... built once each. The pull line takes no rank.
local RANKS = setmetatable({}, { __index = function(t, i)
    local s = i .. "."
    t[i] = s
    return s
end })

-- The icon a Damage Meters row carries for a class: WoW Forever's one spec
-- per class. Kept once found; a failed read tries again next time.
local specIcons = {}
local function SpecIcon(unit, class)
    local icon = specIcons[class]
    if icon then return icon end
    local _, _, classID = UnitClass(unit)
    if issecretvalue(classID) or type(classID) ~= "number" then return nil end
    local _, _, _, fileID = GetSpecializationInfoForClassID(classID, 1)
    if issecretvalue(fileID) or type(fileID) ~= "number" then return nil end
    specIcons[class] = fileID
    return fileID
end

-- The threat settings the rows use, read once after each settings change
-- (ns.FeedChanged drops it; the meter's settings writes all pass there).
local function Settings()
    if cfg then return cfg end
    cfg = {
        pets = Get("pets"), pullBar = Get("pullBar"),
        showValue = Get("showValue"), showPercent = Get("showPercent"),
        pullPercent = Get("percentMode") == "pull",
        pullColor = Get("pullColor"),
        playerColor = Get("playerColorOn") and Get("playerColor") or nil,
        tankColor = Get("tankColorOn") and Get("tankColor") or nil,
    }
    return cfg
end

-- One row: the fields a Damage Meters row reads, plus the threat ones
-- (rankText, threatText, threatColor, threatPet). The value text is rebuilt only
-- when its numbers or the unit style change.
local function FillRow(r, e, rank, c)
    local unit = e.unit
    if e.pull then
        r.name, r.classFilename, r.specIconID = EllesmereUI.L("Pull Aggro"), nil, nil
        r.rankText, r.threatColor = "", c.pullColor
    else
        local class = ns.ClassOf(unit)
        local name = EUI.WithSurname(UnitName(unit))
        if not issecretvalue(name) and name == nil then name = unit end
        r.name, r.classFilename = name, class
        if e.isPet then
            r.specIconID = PET_ICON
        else
            r.specIconID = class and SpecIcon(unit, class) or nil
        end
        r.rankText = RANKS[rank]
        r.threatColor = (e.own and c.playerColor) or (e.tanking and c.tankColor) or nil
    end
    r.threatPet = e.isPet == true
    r.isLocalPlayer = e.own == true
    r.totalAmount = e.raw
    local raw = c.showValue and e.raw or nil
    local pct
    if c.showPercent and not (e.pull and raw) then
        if c.pullPercent then pct = e.scaled else pct = e.rawPct end
    end
    if r.threatText == nil or r._raw ~= raw or r._pct ~= pct or r._units ~= units then
        r._raw, r._pct, r._units = raw, pct, units
        if raw and pct then
            r.threatText = format("%s  %.0f%%", EUI.AbbreviateNumber(raw, units), pct)
        elseif raw then
            r.threatText = EUI.AbbreviateNumber(raw, units)
        elseif pct then
            r.threatText = format("%.0f%%", pct)
        else
            r.threatText = ""
        end
    end
end

-- Reads the mob's threat into the rows and titles the list with the mob.
-- Returns true when there is anything to repaint: rows now or before, or a new title.
local function Build()
    local c = Settings()
    local mob = mobUnit
    local count = 0
    if mob then
        local me, tankRaw = collector.Collect(mob, c.pets)
        if #list > 0 then
            if c.pullBar then collector.AddPullEntry(me, tankRaw) end
            collector.Sort()
        end
        count = #list
    end
    local had = #sources
    local rank = 0
    for i = 1, count do
        local e = list[i]
        if not e.pull then rank = rank + 1 end
        local r = pool[i]
        if not r then r = {}; pool[i] = r end
        FillRow(r, e, rank, c)
        sources[i] = r
    end
    for i = had, count + 1, -1 do sources[i] = nil end
    -- (The secret test first: a secret name cannot be tested or joined.)
    local title = session.threatTitle
    local name = mob and EUI.WithSurname(UnitName(mob))
    if issecretvalue(name) or not name then
        titleName = nil
        session.threatTitle = EllesmereUI.L("Threat")
    elseif name ~= titleName then
        titleName = name
        session.threatTitle = format(EllesmereUI.L("Threat - %s"), name)
    end
    return count > 0 or had > 0 or session.threatTitle ~= title
end

-- The two threat events fire for every unit in every fight nearby, so they are
-- registered only while a mob resolves (as the meter window does).
local function SetThreatEvents(on)
    if on == threatOn then return end
    threatOn = on
    if on then
        events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    else
        events:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    end
end

-- No threat event names a derived token (targettarget): while the list follows
-- what a friendly unit is fighting, re-read on a short interval, in combat only.
local function SetFollow(on)
    if on then
        if not followTicker then followTicker = C_Timer.NewTicker(FOLLOW_INTERVAL, RequestUpdate) end
    elseif followTicker then
        followTicker:Cancel()
        followTicker = nil
    end
end

local function Update()
    pending = false
    if not active then return end
    local tracked = ns.GetTrackedUnit()
    if tracked ~= flagsUnit then
        events:RegisterUnitEvent("UNIT_FLAGS", "pet", tracked)
        flagsUnit = tracked
    end
    local mob = ns.ResolveSource(tracked)
    mobUnit = mob
    SetThreatEvents(mob ~= nil)
    SetFollow(mob ~= nil and mob ~= tracked and InCombatLockdown())
    return Build()
end

-- A list that stayed empty under the same title has nothing to repaint.
local function Tick()
    local changed = Update()
    if changed and active and notify then notify() end
end

-- A raid pull is a burst of per-unit updates: one rebuild per short window.
RequestUpdate = function()
    if pending then return end
    pending = true
    C_Timer.After(UPDATE_DELAY, Tick)
end

-- The feed's event filter, on the threat meter's rules: a threat-list change
-- counts only for the mob shown (a secret comparison counts as a match), a
-- threat-situation or pet change only for a unit the list can hold, a target or
-- flags change only for the tracked unit (or the pet). Combat edges start and
-- stop the follow reads.
local function OnEvent(_, event, unit)
    if event == "GROUP_ROSTER_UPDATE" then
        ns.RosterChanged()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
        if (event == "PLAYER_FOCUS_CHANGED") ~= (ns.GetTrackedUnit() == "focus") then return end
    end
    if pending then return end
    if event == "UNIT_THREAT_LIST_UPDATE" then
        local mob = mobUnit
        if not mob then return end
        if unit ~= mob then
            local same = UnitIsUnit(unit, mob)
            if not issecretvalue(same) and not same then return end
        end
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
        if not (ns.MEMBER_UNITS[unit] or (ns.PET_UNITS[unit] and Settings().pets)) then return end
    elseif event == "UNIT_PET" then
        if not (ns.MEMBER_UNITS[unit] and Settings().pets) then return end
    elseif event == "UNIT_TARGET" or event == "UNIT_FLAGS" then
        if unit == "pet" then
            if not Settings().pets then return end
        elseif unit ~= ns.GetTrackedUnit() then
            return
        end
    end
    RequestUpdate()
end

-- onUpdate runs after every rebuild an event starts; the rows are ready on
-- return (the caller paints them).
local function Start(onUpdate)
    notify = onUpdate
    if active then return end
    active = true
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("PLAYER_FOCUS_CHANGED")
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    events:RegisterEvent("UNIT_PET")
    events:RegisterEvent("PLAYER_REGEN_DISABLED")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
    flagsUnit = nil
    -- The roster memos missed every change made while nothing listened (the
    -- threat meter window keeps them current while it is on).
    if not Get("enabled") then ns.RosterChanged() end
    Update()
end

local function Stop()
    if not active then return end
    active = false
    events:UnregisterAllEvents()
    threatOn, flagsUnit, mobUnit, titleName = false, nil, nil, nil
    SetFollow(false)
    cfg = nil
    for i = #sources, 1, -1 do sources[i] = nil end
end

-- A threat setting changed (the meter's options, its header menu, /euitm).
function ns.FeedChanged()
    cfg = nil
    if active then RequestUpdate() end
end

EUI._ThreatFeed = {
    Start = Start,
    Stop = Stop,
    IsActive = function() return active == true end,
    -- eng: the window's Force English Units; a change rebuilds the value texts.
    Session = function(eng)
        eng = eng == true
        if active and eng ~= units then
            units = eng
            Build()
        end
        return session
    end,
    -- Tracked unit, displayed value and pets, for the window's settings menu.
    MenuItems = function(items) return ns.DataMenuItems(items) end,
}
