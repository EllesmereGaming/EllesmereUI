if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_Waypoint.lua
--  /way [#mapID | zone] x y [description] [; ...] prints links that place
--  Blizzard's native map pin when clicked, and announces arrival at each one.
--  /way is only registered when free; /euiway always is.
--
--  Taint: never calls C_Map.SetUserWaypoint / ClearUserWaypoint or
--  C_SuperTrack setters. They fire USER_WAYPOINT_UPDATED / SUPER_TRACKING_
--  CHANGED synchronously, so Blizzard's map pin code would run inside this
--  addon's call. The worldmap link is handled by Blizzard's own link handler
--  on a hardware click; everything else here only reads.
-------------------------------------------------------------------------------
-- Off by default and reload-gated: while off, nothing below runs.
do
    local cfg = EllesmereUIDB and EllesmereUIDB.waypointCmd
    if not (cfg and cfg.enabled == true) then return end
end

local EUI = EllesmereUI

local C_ACCENT = "|cff0CD29D"
local C_ZONE   = "|cffffffff"
local C_COORD  = "|cffffd100"
local C_DESC   = "|cff66ccff"
local C_HINT   = "|cffff9f1a"

local PREFIX = C_ACCENT .. "EllesmereUI:|r "

local function Say(msg)  EUI.Print(PREFIX .. msg) end
local function Fail(msg) EUI.Print(PREFIX .. "|cffff6060" .. msg .. "|r") end
local function Hint(msg) EUI.Print("   " .. C_HINT .. "> " .. msg .. "|r") end

-- Created in the main chunk so its handler bills to this addon.
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
--  Links
-------------------------------------------------------------------------------
local function MapLabel(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or ("#" .. mapID)
end

-- Same format as C_Map.GetUserWaypointHyperlink: x, y in 0..100 travel as
-- 0..10000.
local function PinLink(mapID, x, y)
    return ("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(mapID,
        math.floor(x * 100 + 0.5), math.floor(y * 100 + 0.5), MAP_PIN_HYPERLINK)
end

local function LinkLine(dest)
    local text = PinLink(dest.mapID, dest.x, dest.y)
        .. " " .. C_ZONE .. MapLabel(dest.mapID) .. "|r"
        .. " " .. C_COORD .. ("%.1f, %.1f"):format(dest.x, dest.y) .. "|r"
    if dest.desc then text = text .. "  " .. C_DESC .. dest.desc .. "|r" end
    return text
end

-------------------------------------------------------------------------------
--  Arrival
--  NAVIGATION_DESTINATION_REACHED did not fire for the pin on Forever in
--  testing (the target goes Invalid around 35 yd first), so the navigation
--  distance is polled, only while a /way list is pending and the pin is
--  super-tracked.
-------------------------------------------------------------------------------
local ARRIVE_YARDS  = 5
local POLL_INTERVAL = 0.5
local listed  -- destinations from the last /way, until all are reached
local ticker
local AnnounceArrival

-- C_Map vectors: Vector2DMixin on retail, a plain { x, y } table on Forever.
local function XY(v)
    if v.GetXY then return v:GetXY() end
    return v.x, v.y
end

-- Index in `listed` of the destination the native pin sits on, or nil.
local function PinnedIndex()
    if not (listed and C_Map.HasUserWaypoint()) then return nil end
    local pin = C_Map.GetUserWaypoint()
    local px, py = XY(pin.position)
    for i, dest in ipairs(listed) do
        -- The link rounds coordinates to 1/10000.
        if dest.mapID == pin.uiMapID and math.abs(dest.x / 100 - px) < 2e-4
            and math.abs(dest.y / 100 - py) < 2e-4 then
            return i
        end
    end
end

local function CheckDistance()
    local dist = C_Navigation.GetDistance()
    if dist > 0 and dist <= ARRIVE_YARDS then AnnounceArrival() end
end

-- Runs on SUPER_TRACKING_CHANGED and whenever the list changes.
local function UpdatePoll()
    local want = listed ~= nil and C_SuperTrack.IsSuperTrackingUserWaypoint()
    if want and not ticker then
        ticker = C_Timer.NewTicker(POLL_INTERVAL, CheckDistance)
    elseif not want and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function SetListed(dests)
    listed = dests
    if dests then
        ev:RegisterEvent("SUPER_TRACKING_CHANGED")
    else
        ev:UnregisterEvent("SUPER_TRACKING_CHANGED")
    end
    UpdatePoll()
end

function AnnounceArrival()
    local i = PinnedIndex()
    local dest = i and listed[i]
    if not dest or dest.reached then return end
    dest.reached = true

    local name = dest.desc or MapLabel(dest.mapID)
    if #listed > 1 then name = i .. ". " .. name end
    Say(C_ACCENT .. EllesmereUI.L("You have arrived:") .. "|r " .. C_DESC .. name .. "|r")

    -- Next destination still to reach, after this one in list order.
    for k = 1, #listed - 1 do
        local j = (i + k - 1) % #listed + 1
        if not listed[j].reached then
            Hint(EllesmereUI.L("Next:") .. "|r " .. C_ACCENT .. j .. ".|r " .. LinkLine(listed[j]))
            return
        end
    end
    if #listed > 1 then
        EUI.Print("   " .. C_ACCENT .. EllesmereUI.L("All waypoints reached.") .. "|r")
    end
    -- No Blizzard link clears the pin; point at the native gesture.
    Hint(EllesmereUI.L("To remove the pin, ctrl-click it on the world map."))
    SetListed(nil)
end

local function ShowDestinations(dests)
    SetListed(dests)
    if #dests == 1 then
        Say(LinkLine(dests[1]))
    else
        Say(C_ACCENT .. EllesmereUI.Lf("%1$d waypoints", #dests) .. "|r")
        for i, dest in ipairs(dests) do
            EUI.Print("   " .. C_ACCENT .. i .. ".|r " .. LinkLine(dest))
        end
    end
    Hint(EllesmereUI.L("Click the link to place the pin, then click the pin on the map to show the arrow."))
    if #dests > 1 then
        Hint(EllesmereUI.L("Then click another link to switch destination; the arrow follows."))
    end
end

-------------------------------------------------------------------------------
--  Parsing
-------------------------------------------------------------------------------
local function PrintUsage()
    Say(EllesmereUI.L("Usage:") .. " /way [#mapID | zone] x y [description] [; ...]")
end

-- Coordinate token -> number in 0..100, or nil. Accepts "45.3", "45,3", "45.3,".
local function ParseCoord(tok)
    local n = tonumber((tok:gsub(",$", ""):gsub(",", ".")))
    if n and n >= 0 and n <= 100 then return n end
end

-- One destination -> { mapID | zone, x, y, desc } in 0..100, or nil.
local function ParseOne(msg)
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
    if not idx then return nil end
    local spec = { x = x, y = y }
    spec.desc = idx + 2 <= #tokens and table.concat(tokens, " ", idx + 2) or nil

    if idx == 1 then
        spec.mapID = C_Map.GetBestMapForUnit("player")
        if not spec.mapID then
            Fail(EllesmereUI.L("Cannot determine your current zone."))
            return nil
        end
        return spec
    end

    local zone = table.concat(tokens, " ", 1, idx - 1)
    local id = zone:match("^#(%d+)$")
    if not id then spec.zone = zone return spec end
    spec.mapID = tonumber(id)
    if not C_Map.GetMapInfo(spec.mapID) then
        Fail(EllesmereUI.Lf("Unknown map ID: %1$s", id))
        return nil
    end
    return spec
end

-- spec -> uiMapID, or nil after reporting why. Zone names only resolve inside
-- a WithZoneTable callback.
local function Resolve(spec)
    local mapID = spec.mapID
    if not mapID then
        local matches
        mapID, matches = FindZone(spec.zone)
        if not mapID then
            if #matches == 0 then
                Fail(EllesmereUI.Lf("Unknown zone: %1$s", spec.zone))
                return nil
            end
            local names = {}
            for i = 1, math.min(#matches, 8) do
                names[i] = matches[i].name .. " (#" .. matches[i].id .. ")"
            end
            Fail(EllesmereUI.Lf("Several zones match %1$s:", spec.zone) .. " " .. table.concat(names, ", "))
            return nil
        end
    end
    if not C_Map.CanSetUserWaypointOnMap(mapID) then
        Fail(EllesmereUI.Lf("Map pins cannot be placed on %1$s.", MapLabel(mapID)))
        return nil
    end
    return mapID
end

-- Several destinations in one line: separated by ";" or pasted back to back
-- ("/way A /way B").
local function HandleWay(msg)
    msg = strtrim(msg or "")
    local lower = msg:lower()
    if lower == "clear" or lower == "reset" or lower == "remove" then
        Say(C_HINT .. EllesmereUI.L("To remove the pin, ctrl-click it on the world map.") .. "|r")
        return
    end
    msg = msg:gsub("/[Ee][Uu][Ii][Ww][Aa][Yy]%f[%s%z]", ";"):gsub("/[Ww][Aa][Yy]%f[%s%z]", ";")
    local specs, needZones = {}, false
    for part in msg:gmatch("[^;]+") do
        part = strtrim(part)
        if part ~= "" then
            local spec = ParseOne(part)
            if spec then
                specs[#specs + 1] = spec
                if spec.zone then needZones = true end
            end
        end
    end
    if #specs == 0 then PrintUsage() return end

    local function Finish()
        local dests = {}
        for _, spec in ipairs(specs) do
            local mapID = Resolve(spec)
            if mapID then
                dests[#dests + 1] = { mapID = mapID, x = spec.x, y = spec.y, desc = spec.desc }
            end
        end
        if #dests > 0 then ShowDestinations(dests) end
    end
    if needZones then WithZoneTable(Finish) else Finish() end
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
ev:SetScript("OnEvent", function(self, event)
    if event == "SUPER_TRACKING_CHANGED" then UpdatePoll() return end
    self:UnregisterEvent("PLAYER_LOGIN")
    SLASH_EUIWAY1 = "/euiway"
    SlashCmdList["EUIWAY"] = HandleWay
    if SlashTaken("/way") then return end
    -- Own SlashCmdList key (not SLASH_EUIWAY2): a key added after the chat
    -- hash already imported EUIWAY would never be picked up.
    SLASH_EUIWAYSHORT1 = "/way"
    SlashCmdList["EUIWAYSHORT"] = HandleWay
end)
