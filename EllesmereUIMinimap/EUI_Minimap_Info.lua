if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Minimap_Info.lua
--
--  The clock, coordinates and location text: font, colours, anchors and
--  their update functions.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIMinimap.lua or an earlier EUI_Minimap_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local EBS, EG = I.EBS, I.EG

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local coordFrame
I.coordFrameSetters[#I.coordFrameSetters + 1] = function(v) coordFrame = v end
local clockFrame
I.clockFrameSetters[#I.clockFrameSetters + 1] = function(v) clockFrame = v end
local locationFrame
I.locationFrameSetters[#I.locationFrameSetters + 1] = function(v) locationFrame = v end
local locationBg
I.locationBgSetters[#I.locationBgSetters + 1] = function(v) locationBg = v end

local function ApplyMinimapFont(fs, size) EllesmereUI.ApplyModuleFont(fs, nil, size, "minimap") end

-- Description-text colour (clock AM/PM, the "fps"/"ms" suffixes): custom fpsColor swatch or the live accent; the dynamic values stay white. Returns r, g, b, hex.
local function GetDescColor(mp)
    local r, g, b
    if mp and mp.fpsUseAccent then
        r, g, b = EG.r, EG.g, EG.b
    else
        local c = mp and mp.fpsColor
        if c then r, g, b = c.r or 1, c.g or 1, c.b or 1 else r, g, b = 1, 1, 1 end
    end
    return r, g, b, format("%02x%02x%02x",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Cache clock CVars so we don't read them every second
local cachedUse24h, cachedUseLocal
local function RefreshClockCVars()
    cachedUse24h = GetCVar("timeMgrUseMilitaryTime") == "1"
    cachedUseLocal = GetCVar("timeMgrUseLocalTime") == "1"
end

local function UpdateClock()
    if not clockFrame then return end
    if cachedUse24h == nil then RefreshClockCVars() end
    local h, m
    if cachedUseLocal then
        local t = date("*t")
        h, m = t.hour, t.min
    else
        h, m = GetGameTime()
    end
    if cachedUse24h then
        clockFrame:SetText(format("%02d:%02d", h, m))
    else
        -- Unpadded hour in 12h (1:03, not 01:03) matching Blizzard; 24h keeps the pad. AM/PM takes the description colour only when opted in; digits stay white.
        local ampm = h >= 12 and "PM" or "AM"
        h = h % 12
        if h == 0 then h = 12 end
        local mp = EBS.db and EBS.db.profile.minimap
        if mp and mp.fpsColorClockAMPM then
            local _, _, _, hex = GetDescColor(mp)
            clockFrame:SetFormattedText("%d:%02d |cff%s%s|r", h, m, hex, ampm)
        else
            clockFrame:SetFormattedText("%d:%02d %s", h, m, ampm)
        end
    end
end

-- Coords mode/position with legacy fallback: pre-dropdown exports carry only coordsBelow (true = always-on below the map, else hover-only at the top left).
local function GetCoordsModePos(mp)
    if not mp then return "always", "topLeft" end
    local mode = mp.coordsMode or (mp.coordsBelow and "always") or "always"
    local pos = mp.coordsPosition or (mp.coordsBelow and "belowMap") or "topLeft"
    return mode, pos
end

-- Clock/location legacy fallback: pre-dropdown data carries clockInside/zoneInside
-- (default ON/OFF) plus the removed Zone/Clock checkboxes (showClock == false / hideZoneText == true meant hidden).
local function GetElementModes(mp)
    if not mp then return "inside", "inside" end
    local clockMode = mp.clockMode
    if clockMode == nil then
        if mp.showClock == false then
            clockMode = "none"
        else
            clockMode = (mp.clockInside == false) and "edge" or "inside"
        end
    end
    local locationMode = mp.locationMode
    if locationMode == nil then
        if mp.hideZoneText == true then
            locationMode = "none"
        else
            locationMode = mp.zoneInside and "inside" or "edge"
        end
    end
    return clockMode, locationMode
end

-- position key -> element point, map relPoint, base X, base Y (inside flavor). Shared by the coordinates, clock and zone text elements.
local MAP_POS_ANCHORS = {
    belowMap    = { "TOP",         "BOTTOM",       0, -5 },
    aboveMap    = { "BOTTOM",      "TOP",          0,  5 },
    topLeft     = { "TOPLEFT",     "TOPLEFT",      4, -4 },
    top         = { "TOP",         "TOP",          0, -4 },
    topRight    = { "TOPRIGHT",    "TOPRIGHT",    -4, -4 },
    left        = { "LEFT",        "LEFT",         4,  0 },
    right       = { "RIGHT",       "RIGHT",       -4,  0 },
    bottomLeft  = { "BOTTOMLEFT",  "BOTTOMLEFT",   4,  4 },
    bottom      = { "BOTTOM",      "BOTTOM",       0,  4 },
    bottomRight = { "BOTTOMRIGHT", "BOTTOMRIGHT", -4,  4 },
}

-- An inside-map offset under the WoW Forever look's Forever Square: the rim
-- and its dark line cover the map's outer 3px and its inner shadow reaches
-- 5px (FOREVER_HEAVY.band and .shade at the window scale, less the rim's
-- EBS.FV_SQUARE_OUT outside the map), over the 4px inset above, so an
-- element inside the map steps 2px further in on each axis it is inset on
-- (6px from the edge; the title bar's divider and its shadow reach no
-- further). pos: a MAP_POS_ANCHORS key (nil: inside the map). Above Map
-- rises over the title bar while it shows, keeping its gap to the frame;
-- Below Map, and every other look, keep their offsets. Blizzard Style's slim
-- square keeps the 4px inset (its line's inner shadow ends at the map's
-- edge). An EBS field.
function EBS._FvInsideXY(pos, x, y)
    if not EBS._fvSquare or pos == "belowMap" then return x, y end
    if pos == "aboveMap" then
        if EBS._fvTitleOn then y = y + EBS._SqTitle() - EBS._SqOut() end
        return x, y
    end
    if EBS._sqSlim then return x, y end
    if x ~= 0 then x = x + (x > 0 and 2 or -2) end
    if y ~= 0 then y = y + (y > 0 and 2 or -2) end
    return x, y
end

-- Anchor for the clock/zone text bar. Inside keeps the 4px map inset (7px under
-- Forever Square, past the heavy band); edge flips it so the box straddles the
-- border (7px out on squares, 3px in on circles -- the round mask curves away
-- from the frame edge). Above/Below Map float outside in both.
local function ResolveElementAnchor(pos, style, isCircle)
    local a = MAP_POS_ANCHORS[pos] or MAP_POS_ANCHORS.top
    local x, y = a[3], a[4]
    if style == "edge" and pos ~= "belowMap" and pos ~= "aboveMap" then
        if x ~= 0 then x = isCircle and (x > 0 and 3 or -3) or (x > 0 and -7 or 7) end
        if y ~= 0 then y = isCircle and (y > 0 and 3 or -3) or (y > 0 and -7 or 7) end
    else
        x, y = EBS._FvInsideXY(pos, x, y)
    end
    return a[1], a[2], x, y
end

-- Cache coord format string so we don't rebuild it every 0.5s
local cachedCoordPrec, cachedCoordFmt
local function UpdateCoords()
    if not coordFrame then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then coordFrame:SetText(""); return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then coordFrame:SetText(""); return end
    local x, y = pos:GetXY()
    local p = EBS.db and EBS.db.profile.minimap
    local prec = p and p.coordPrecision or 1
    if prec ~= cachedCoordPrec then
        cachedCoordPrec = prec
        cachedCoordFmt = format("%%.%df, %%.%df", prec, prec)
    end
    coordFrame:SetText(format(cachedCoordFmt, x * 100, y * 100))
end

-- Reactive zone coloring: tint by the current zone's PvP ruleset (friendly green, hostile/arena/combat red, sanctuary blue, contested/unknown yellow).
local function GetZoneReactionColor()
    local pvpType = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
    if pvpType == "friendly" then
        return 0.05, 0.85, 0.03
    elseif pvpType == "sanctuary" then
        return 0.035, 0.58, 0.84
    elseif pvpType == "arena" or pvpType == "hostile" or pvpType == "combat" then
        return 0.84, 0.03, 0.03
    end
    return 0.9, 0.85, 0.05
end

local lastLocationText
local function UpdateLocation()
    if not locationFrame then return end
    if InCombatLockdown() then return end
    -- Colour before the text dedup so toggles/ruleset changes repaint the same zone.
    local mp = EBS.db and EBS.db.profile.minimap
    if mp and mp.zoneReactiveColor then
        local r, g, b = GetZoneReactionColor()
        locationFrame:SetTextColor(r, g, b, 0.9)
    else
        locationFrame:SetTextColor(1, 1, 1, 0.9)
    end
    local text
    if mp and mp.zoneShowSubZone then
        local sub = GetSubZoneText()
        text = (sub and sub ~= "") and sub or (GetZoneText() or "")
    else
        text = GetZoneText() or ""
    end
    if text == lastLocationText then return end
    lastLocationText = text
    locationFrame:SetText(text)
    if locationBg then
        local tw = locationFrame:GetStringWidth() or 0
        locationBg:SetSize(tw + 20, 18)
    end
end

I.ApplyMinimapFont, I.GetCoordsModePos = ApplyMinimapFont, GetCoordsModePos
I.GetDescColor, I.GetElementModes = GetDescColor, GetElementModes
I.MAP_POS_ANCHORS, I.RefreshClockCVars = MAP_POS_ANCHORS, RefreshClockCVars
I.ResolveElementAnchor, I.UpdateClock = ResolveElementAnchor, UpdateClock
I.UpdateCoords, I.UpdateLocation = UpdateCoords, UpdateLocation
I.broken = false
