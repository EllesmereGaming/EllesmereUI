-------------------------------------------------------------------------------
--  EllesmereUIQoL_AutoLogging.lua
--  Toggles combat logging on zone transitions based on instance type/difficulty.
--  Also forces Advanced Combat Logging on whenever logging starts.
-------------------------------------------------------------------------------

-- Retail content thresholds -- maps below these are excluded unless in LEGACY_DUNGEON_IDS.
local RETAIL_RAID_THRESHOLD    = 2657
local RETAIL_DUNGEON_THRESHOLD = 959

-- Older dungeons still used as M+ maps.
local LEGACY_DUNGEON_IDS = {
    [1594] = true,  -- MOTHERLODE!!
    [1208] = true,  -- Grimrail Depot
    [1195] = true,  -- Iron Docks
    [1651] = true,  -- Return to Karazhan
    [657]  = true,  -- The Vortex Pinnacle
    [643]  = true,  -- Throne of the Tides
    [670]  = true,  -- Grim Batol
    [658]  = true,  -- Pit of Saron
}

-- Current-tier raids whose instance ID falls BELOW the retail threshold.
-- Instance map IDs are NOT chronological: some current raids reuse a low ID
-- (e.g. Sporefall is 1592, lower than legacy raids), so the threshold alone
-- would wrongly exclude them. Whitelist those explicitly.
local CURRENT_RAID_IDS = {
    [1592] = true,  -- Sporefall
}

-- LFR difficulty IDs (regular + timewalking).
local LFR_DIFFICULTIES = { [7] = true, [17] = true }

-- Raid difficulty -> trigger key. 233 = Mythic (Flexible Raiding), the newer
-- flexible Mythic difficulty used by current raids alongside the fixed-20 id 16.
local RAID_DIFF_KEYS = {
    [16]  = "logMythic",
    [233] = "logMythic",
    [15]  = "logHeroic",
    [14]  = "logNormal",
}

-- Defaults: everything on except Scenarios.
local TRIGGER_DEFAULTS = {
    logMythic   = true,
    logHeroic   = true,
    logNormal   = true,
    logLFR      = true,
    log5pp      = true,
    logArena    = true,
    logScenario = false,
    delaystop   = true,
}

local function GetTrigger(c, key)
    local v = c[key]
    if v == nil then return TRIGGER_DEFAULTS[key] end
    return v
end

local function Cfg()
    if not EllesmereUIDB then return {} end
    EllesmereUIDB.autoLogging = EllesmereUIDB.autoLogging or {}
    return EllesmereUIDB.autoLogging
end

-- Silently sets advancedCombatLogging if it isn't already on.
local function EnsureAdvancedLogging()
    if GetCVar and GetCVar("advancedCombatLogging") ~= "1" then
        SetCVar("advancedCombatLogging", 1)
    end
end

local function ZoneShouldBeLogged()
    local c = Cfg()
    if not c.enabled then return false end

    local _, zoneType, rawDiff, _, playerCap, _, _, rawMapID = GetInstanceInfo()
    local diff  = tonumber(rawDiff)
    local mapID = tonumber(rawMapID)
    if not diff or not mapID then return false end

    if LFR_DIFFICULTIES[diff] then
        return GetTrigger(c, "logLFR")
    end

    if zoneType == "raid" and (mapID >= RETAIL_RAID_THRESHOLD or CURRENT_RAID_IDS[mapID]) then
        local key = RAID_DIFF_KEYS[diff]
        if key then return GetTrigger(c, key) end
        return true  -- timewalking and other unrecognised raid difficulties
    end

    if GetTrigger(c, "log5pp") then
        local isMythicDungeon = (diff == 23 or diff == 8)  -- 23=Keystone, 8=Mythic
        local isRetailDungeon = mapID >= RETAIL_DUNGEON_THRESHOLD or LEGACY_DUNGEON_IDS[mapID]
        if isMythicDungeon and isRetailDungeon then return true end
    end

    if GetTrigger(c, "logScenario") and zoneType == "scenario"
       and (tonumber(playerCap) or 0) > 1
       and mapID >= RETAIL_DUNGEON_THRESHOLD then
        return true
    end

    if GetTrigger(c, "logArena") and (zoneType == "arena" or zoneType == "ratedarena") then
        return true
    end

    return false
end

local STOP_DELAY_SECONDS = 30

local wasLogging = false
local _stopTimer  = nil

local function CancelStopTimer()
    if _stopTimer then _stopTimer:Cancel(); _stopTimer = nil end
end

local function ApplyLoggingState()
    local shouldLog = ZoneShouldBeLogged()
    if shouldLog then
        CancelStopTimer()
        EnsureAdvancedLogging()
        LoggingCombat(true)
    elseif wasLogging and LoggingCombat() then
        local c = Cfg()
        local delay = GetTrigger(c, "delaystop")
        if delay and not _stopTimer then
            _stopTimer = C_Timer.NewTimer(STOP_DELAY_SECONDS, function()
                _stopTimer = nil
                if LoggingCombat() then LoggingCombat(false) end
            end)
        elseif not delay then
            LoggingCombat(false)
        end
    end
    wasLogging = shouldLog
end

local events = {
    ZONE_CHANGED_NEW_AREA = function() C_Timer.After(2, ApplyLoggingState) end,
    CHALLENGE_MODE_START   = function() C_Timer.After(1, ApplyLoggingState) end,
}

-- Zone events are registered only while the feature is enabled, so a disabled
-- feature costs nothing on zone changes. The options toggle calls
-- _EUI_AutoLogging_Check, which re-syncs registration AND applies the logging
-- state immediately (disabling mid-instance still stops an active log).
local logFrame = CreateFrame("Frame")
local _eventsRegistered = false
local function SyncEventRegistration()
    local want = Cfg().enabled and true or false
    if want == _eventsRegistered then return end
    _eventsRegistered = want
    for ev in pairs(events) do
        if want then logFrame:RegisterEvent(ev) else logFrame:UnregisterEvent(ev) end
    end
end

_G._EUI_AutoLogging_Check = function()
    SyncEventRegistration()
    ApplyLoggingState()
end

logFrame:RegisterEvent("PLAYER_LOGIN")
logFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        SyncEventRegistration()
        C_Timer.After(2, ApplyLoggingState)
    elseif events[event] then
        events[event]()
    end
end)
