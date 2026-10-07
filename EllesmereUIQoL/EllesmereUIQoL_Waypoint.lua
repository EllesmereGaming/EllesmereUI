if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_Waypoint.lua
--  /way [#mapID | zone] x y [description] and /way clear, on Blizzard's native
--  map pin + super-tracking. The pin clears itself on arrival.
--  /way is only registered when free; /euiway always is.
-------------------------------------------------------------------------------
-- Off by default and reload-gated: while off, nothing below runs.
do
    local cfg = EllesmereUIDB and EllesmereUIDB.waypointCmd
    if not (cfg and cfg.enabled == true) then return end
end

local EUI = EllesmereUI
local L, Lf = EUI.L, EUI.Lf

local PREFIX = "|cff0CD29DEllesmereUI:|r "

local function Say(msg)  EUI.Print(PREFIX .. msg) end
local function Fail(msg) EUI.Print(PREFIX .. "|cffff6060" .. msg .. "|r") end

-- Created in the main chunk so its handlers bill to this addon.
local ev = CreateFrame("Frame")

-------------------------------------------------------------------------------
--  Zone name -> uiMapID
--  Built on the first by-name /way through RunBudgeted (the scan scales with
--  the map ID range); lookups queued during the scan resolve when it ends.
-------------------------------------------------------------------------------
local MAP_SCAN_MAX   = 3500
local MAP_SCAN_CHUNK = 250
local ZONE_TYPES = {
    [Enum.UIMapType.Continent] = 1,
    [Enum.UIMapType.Zone]      = 3,  -- preferred on a name clash
    [Enum.UIMapType.Dungeon]   = 0,
    [Enum.UIMapType.Micro]     = 2,
}
local zoneByName     -- [lowercase name] = { id = uiMapID, prio = n, name = display }
local zoneWaiters    -- callbacks queued while the scan runs

local function ScanMaps(first, last)
    for id = first, last do
        local info = C_Map.GetMapInfo(id)
        local prio = info and ZONE_TYPES[info.mapType]
        if prio and info.name and info.name ~= "" and C_Map.CanSetUserWaypointOnMap(id) then
            local key = info.name:lower()
            local cur = zoneByName[key]
            if not cur or prio > cur.prio then
                zoneByName[key] = { id = id, prio = prio, name = info.name }
            end
        end
    end
end

local function WithZoneTable(fn)
    if zoneWaiters then zoneWaiters[#zoneWaiters + 1] = fn return end
    if zoneByName then fn() return end
    zoneByName, zoneWaiters = {}, { fn }
    local steps = {}
    for first = 1, MAP_SCAN_MAX, MAP_SCAN_CHUNK do
        local last = math.min(first + MAP_SCAN_CHUNK - 1, MAP_SCAN_MAX)
        steps[#steps + 1] = function() ScanMaps(first, last) end
    end
    EUI.RunBudgeted(steps, 8, function()
        local waiters = zoneWaiters
        zoneWaiters = nil
        for _, w in ipairs(waiters) do w() end
    end)
end

-- Returns uiMapID, or nil + candidates sorted by name when ambiguous / unknown.
-- Only valid inside a WithZoneTable callback.
local function FindZone(name)
    local key = name:lower()
    local hit = zoneByName[key]
    if hit then return hit.id end

    local matches = {}
    for k, v in pairs(zoneByName) do
        if k:find(key, 1, true) then matches[#matches + 1] = v end
    end
    if #matches == 1 then return matches[1].id end
    table.sort(matches, function(a, b) return a.name < b.name end)
    return nil, matches
end

-------------------------------------------------------------------------------
--  Clear on arrival
--  Events are registered only while a pin placed by /way exists. Blizzard
--  clears super-tracking itself on arrival (no type), so `tracked` only drops
--  when the player super-tracks something else.
-------------------------------------------------------------------------------
local target   -- { mapID, x, y } in 0..1, the pin /way placed
local tracked  -- our pin is the super-tracked destination

local function IsOurPin()
    if not (target and C_Map.HasUserWaypoint()) then return false end
    local pin = C_Map.GetUserWaypoint()
    return pin and pin.uiMapID == target.mapID
        and math.abs(pin.position.x - target.x) < 1e-4
        and math.abs(pin.position.y - target.y) < 1e-4
end

local function StopWatch()
    target, tracked = nil, false
    ev:UnregisterEvent("NAVIGATION_DESTINATION_REACHED")
    ev:UnregisterEvent("SUPER_TRACKING_CHANGED")
    ev:UnregisterEvent("USER_WAYPOINT_UPDATED")
end

-- Set before C_Map.SetUserWaypoint so the USER_WAYPOINT_UPDATED it fires
-- already sees the new pin as ours.
local function StartWatch(mapID, x, y)
    target = target or {}
    target.mapID, target.x, target.y = mapID, x, y
    tracked = true
    ev:RegisterEvent("NAVIGATION_DESTINATION_REACHED")
    ev:RegisterEvent("SUPER_TRACKING_CHANGED")
    ev:RegisterEvent("USER_WAYPOINT_UPDATED")
end

local function OnWatchEvent(event, isWaypoint)
    if event == "USER_WAYPOINT_UPDATED" then
        if not IsOurPin() then StopWatch() end
    elseif event == "SUPER_TRACKING_CHANGED" then
        local t = C_SuperTrack.GetHighestPrioritySuperTrackingType()
        if t then tracked = (t == Enum.SuperTrackingType.UserWaypoint) end
    elseif not isWaypoint and tracked and IsOurPin() then
        StopWatch()
        C_Map.ClearUserWaypoint()
        Say(L("You have arrived at your destination."))
    end
end

-------------------------------------------------------------------------------
--  Commands
-------------------------------------------------------------------------------
local function PrintUsage()
    Say(L("Usage:") .. " /way [#mapID | zone] x y [description]")
    Say("/way clear - " .. L("Remove the current map pin."))
end

local function ClearWaypoint()
    StopWatch()
    if C_Map.HasUserWaypoint() then
        C_Map.ClearUserWaypoint()
        Say(L("Map pin removed."))
    else
        Say(L("No map pin to remove."))
    end
end

local function MapLabel(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or ("#" .. mapID)
end

local function SetWaypoint(mapID, x, y, desc)
    if not C_Map.CanSetUserWaypointOnMap(mapID) then
        Fail(Lf("Map pins cannot be placed on %1$s.", MapLabel(mapID)))
        return
    end
    x, y = x / 100, y / 100
    StartWatch(mapID, x, y)
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    C_SuperTrack.SetSuperTrackedUserWaypoint(true)

    local link = C_Map.GetUserWaypointHyperlink()
    local text = Lf("Waypoint set: %1$s %2$s, %3$s", MapLabel(mapID),
        ("%.1f"):format(x * 100), ("%.1f"):format(y * 100))
    if desc then text = text .. " - " .. desc end
    if link then text = text .. " " .. link end
    Say(text)
end

local function SetWaypointInZone(zone, x, y, desc)
    WithZoneTable(function()
        local mapID, matches = FindZone(zone)
        if mapID then SetWaypoint(mapID, x, y, desc) return end
        if #matches == 0 then
            Fail(Lf("Unknown zone: %1$s", zone))
            return
        end
        local names = {}
        for i = 1, math.min(#matches, 8) do
            names[i] = matches[i].name .. " (#" .. matches[i].id .. ")"
        end
        Fail(Lf("Several zones match \"%1$s\":", zone) .. " " .. table.concat(names, ", "))
    end)
end

-- Coordinate token -> number in 0..100, or nil. Accepts "45.3", "45,3", "45.3,".
local function ParseCoord(tok)
    local n = tonumber((tok:gsub(",$", ""):gsub(",", ".")))
    if n and n >= 0 and n <= 100 then return n end
end

local function HandleWay(msg)
    msg = strtrim(msg or "")
    if msg == "" then PrintUsage() return end
    local lower = msg:lower()
    if lower == "clear" or lower == "reset" or lower == "remove" then ClearWaypoint() return end

    -- "45, 67" / "45. 67" -> "45 67", then split on spaces.
    msg = msg:gsub("(%d)[%.,]%s+(%d)", "%1 %2")
    local tokens = {}
    for t in msg:gmatch("%S+") do tokens[#tokens + 1] = t end

    -- First pair of consecutive coordinates splits zone / x y / description.
    local idx, x, y
    for i = 1, #tokens - 1 do
        x, y = ParseCoord(tokens[i]), ParseCoord(tokens[i + 1])
        if x and y then idx = i break end
    end
    if not idx then PrintUsage() return end
    local desc = idx + 2 <= #tokens and table.concat(tokens, " ", idx + 2) or nil

    if idx == 1 then
        local mapID = C_Map.GetBestMapForUnit("player")
        if not mapID then
            Fail(L("Cannot determine your current zone."))
            return
        end
        SetWaypoint(mapID, x, y, desc)
        return
    end

    local zone = table.concat(tokens, " ", 1, idx - 1)
    local id = zone:match("^#(%d+)$")
    if not id then SetWaypointInZone(zone, x, y, desc) return end
    if not C_Map.GetMapInfo(tonumber(id)) then
        Fail(Lf("Unknown map ID: %1$s", id))
        return
    end
    SetWaypoint(tonumber(id), x, y, desc)
end

-------------------------------------------------------------------------------
--  Slash registration
-------------------------------------------------------------------------------
-- True when another addon already registered the given command.
local function SlashTaken(cmd)
    for key in pairs(SlashCmdList) do
        local i = 1
        local s = _G["SLASH_" .. key .. i]
        while type(s) == "string" do
            if s:lower() == cmd then return true end
            i = i + 1
            s = _G["SLASH_" .. key .. i]
        end
    end
    return false
end

ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, ...)
    if event ~= "PLAYER_LOGIN" then OnWatchEvent(event, ...) return end
    self:UnregisterEvent("PLAYER_LOGIN")
    SLASH_EUIWAY1 = "/euiway"
    SlashCmdList["EUIWAY"] = HandleWay
    if SlashTaken("/way") then return end
    -- Own SlashCmdList key (not SLASH_EUIWAY2): a key added after the chat
    -- hash already imported EUIWAY would never be picked up.
    SLASH_EUIWAYSHORT1 = "/way"
    SlashCmdList["EUIWAYSHORT"] = HandleWay
end)
