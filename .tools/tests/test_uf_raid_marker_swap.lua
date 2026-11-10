-- Stub harness: the Unit Frames raid marker on the target and focus frames
-- follows a target or focus swap whether Show Raid Marker was on at login or
-- turned on later in the session (the options, a profile switch, a Spec or
-- Conditional Override), and costs nothing while it is off.
-- Loads the real engine, cuts the raid marker painter and the engine attach
-- from the portrait file and the raid marker pass from the settings reload.
--   lua .tools/tests/test_uf_raid_marker_swap.lua        (from the repository root)
-- Each source path can be pointed elsewhere through a global:
--   UF_ENGINE_PATH, UF_PORTRAIT_PATH, UF_RELOAD_PATH
local ENGINE_PATH = rawget(_G, "UF_ENGINE_PATH") or "EllesmereUIUnitFrames/EUI_UnitFrames_Engine.lua"
local PORTRAIT_PATH = rawget(_G, "UF_PORTRAIT_PATH") or "EllesmereUIUnitFrames/EUI_UnitFrames_Portrait.lua"
local RELOAD_PATH = rawget(_G, "UF_RELOAD_PATH") or "EllesmereUIUnitFrames/EUI_UnitFrames_Reload.lua"

local function ReadSource(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    return src
end

-- From the line holding `startPat` through the first `endPat` after it.
local function Cut(src, startPat, endPat, what)
    local s = src:find(startPat, 1, true)
    assert(s, what .. ": start not found")
    s = src:sub(1, s):match(".*()\n") or 1
    local _, e = src:find(endPat, s, true)
    assert(e, what .. ": end not found")
    return src:sub(s, e)
end

-- From the line holding `startPat` up to (not including) the line holding `stopPat`.
local function CutUntil(src, startPat, stopPat, what)
    local s = src:find(startPat, 1, true)
    assert(s, what .. ": start not found")
    s = src:sub(1, s):match(".*()\n") or 1
    local e = src:find(stopPat, s, true)
    assert(e, what .. ": stop not found")
    e = src:sub(1, e):match(".*()\n")
    return src:sub(s, e)
end

local checks, fails = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-------------------------------------------------------------------------------
--  Game API stubs
-------------------------------------------------------------------------------
local W = {
    exists = {},      -- unit -> true
    marker = {},      -- unit -> raid marker index
    guid = {},        -- unit -> guid
    now = 0,
    tick = false,     -- true: every clock read moves on, so no paint is deduped
}
local allFrames = {}

-- The widget methods the sources call: a mock answers those with a no-op, and
-- any other field that was never set reads nil, as on a real frame.
local METHODS = {}
for _, path in ipairs({ ENGINE_PATH, PORTRAIT_PATH, RELOAD_PATH }) do
    for name in ReadSource(path):gmatch(":([%a_][%w_]*)%s*%(") do METHODS[name] = true end
end

local function MakeObj(kind, name)
    local o = { _kind = kind, _name = name, _shown = true, _scripts = {}, _hooks = {}, _events = {}, _attr = {} }
    setmetatable(o, { __index = function(_, k)
        if type(k) ~= "string" or k:sub(1, 1) == "_" then return nil end
        if k == "Show" then return function(self) self._shown = true end end
        if k == "Hide" then return function(self) self._shown = false end end
        if k == "IsShown" then return function(self) return self._shown end end
        if k == "SetScript" then return function(self, s, fn) self._scripts[s] = fn end end
        if k == "GetScript" then return function(self, s) return self._scripts[s] end end
        if k == "HookScript" then
            return function(self, s, fn)
                local list = self._hooks[s]
                if not list then list = {}; self._hooks[s] = list end
                list[#list + 1] = fn
            end
        end
        if k == "RegisterEvent" or k == "RegisterUnitEvent" then
            return function(self, ev) self._events[ev] = true end
        end
        if k == "UnregisterEvent" then return function(self, ev) self._events[ev] = nil end end
        if k == "SetAttribute" then return function(self, a, v) self._attr[a] = v end end
        if k == "GetAttribute" then return function(self, a) return self._attr[a] end end
        if k == "CreateTexture" then return function() return MakeObj("Texture") end end
        if k == "SetTexture" then return function(self, t) self._texture = t end end
        if k == "GetTexture" then return function(self) return self._texture end end
        if k == "GetFrameLevel" then return function() return 1 end end
        if METHODS[k] then return function() end end
        return nil
    end })
    if kind ~= "Texture" then allFrames[#allFrames + 1] = o end
    return o
end

EUI_CLIENT_BLOCKED = nil
issecretvalue = function() return false end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
CreateFrame = function(kind, name) return MakeObj(kind, name) end
UIParent = MakeObj("Frame", "UIParent")
RegisterStateDriver = function() end
RegisterUnitWatch = function() end
SecureButton_GetUnit = function(f) return f._attr.unit end
SecureButton_GetModifiedUnit = function(f) return f._attr.unit end
GetTime = function()
    if W.tick then W.now = W.now + 0.001 end
    return W.now
end
UnitExists = function(u) return W.exists[u] == true end
UnitGUID = function(u) return W.guid[u] end
GetRaidTargetIndex = function(u) return W.marker[u] end
SetRaidTargetIconTexture = function(tex, index) tex._markerIndex = index end
C_Timer = { After = function() end }
Enum = { StatusBarInterpolation = { Immediate = 0 } }
EllesmereUI = { AttachSecureUnitMenu = function() end }

-------------------------------------------------------------------------------
--  Load the real engine, then the cut portrait and reload pieces
-------------------------------------------------------------------------------
local ns = {}
local engineChunk = assert(loadstring(ReadSource(ENGINE_PATH), "=EUI_UnitFrames_Engine.lua"))
engineChunk("EllesmereUIUnitFrames", ns)
local Engine = assert(ns.Engine, "the engine did not load")

-- Counts every raid marker paint; the painter itself is the real one.
local markerPaints = 0
do
    local SetPainter = Engine.SetPainter
    Engine.SetPainter = function(channel, fn)
        if channel == "raidicon" then
            local real = fn
            fn = function(...)
                markerPaints = markerPaints + 1
                return real(...)
            end
        end
        return SetPainter(channel, fn)
    end
end

local PSRC = ReadSource(PORTRAIT_PATH)
local portraitCut = table.concat({
    "local ns, GetSettingsForUnit = ...\n",
    Cut(PSRC, 'ns.Engine.SetPainter("raidicon", function(frame, unit)', "\nend)\n", "raid marker painter"),
    Cut(PSRC, "function ns.UF_AttachEngineFrame(frame, unit, polled)", "\nend\n", "UF_AttachEngineFrame"),
}, "\n")

local profile = {}
local function GetSettingsForUnit(unit) return profile[unit] end
ns.UF_HEAL_PRED_UNITS = {}
ns.UF_StampPortraitForceUpdate = function() end
assert(loadstring(portraitCut, "=portrait cut"))(ns, GetSettingsForUnit)
assert(ns.UF_AttachEngineFrame, "UF_AttachEngineFrame was not cut")

local RSRC = ReadSource(RELOAD_PATH)
local reloadCut = table.concat({
    "local frames, GetSettingsForUnit = ...\n",
    CutUntil(RSRC, "    local RAID_MARKER_UNITS = ", "    -- Portrait settings (3D zoom", "raid marker reload pass"),
}, "\n")
local frames = {}
local RaidMarkerReload = assert(loadstring(reloadCut, "=reload cut"))

-- The global trigger frame the engine registers its target and focus edges on
local globalFrame
for _, f in ipairs(allFrames) do
    if f._events.PLAYER_TARGET_CHANGED and f._events.RAID_TARGET_UPDATE then globalFrame = f end
end
assert(globalFrame and globalFrame._scripts.OnEvent, "the engine's global trigger frame was not found")
local function Fire(event, ...)
    W.now = W.now + 1
    globalFrame._scripts.OnEvent(globalFrame, event, ...)
end

-------------------------------------------------------------------------------
--  A session: spawns the target and focus frames as the styles and Init do,
--  then the login settings reload
-------------------------------------------------------------------------------
local function Spawn(unit, enabled)
    profile[unit] = { raidMarkerEnabled = enabled }
    local frame = Engine.SpawnUnitFrame(unit, "Test_" .. unit)
    -- The style's raid marker build (EUI_UnitFrames_Builders.lua)
    local icon = frame:CreateTexture()
    frame._raidMarkerIcon = icon
    if enabled then
        frame.RaidTargetIndicator = icon
    else
        icon:Hide()
    end
    ns.UF_AttachEngineFrame(frame, unit)
    frames[unit] = frame
    return frame, icon
end

local function SetOption(unit, on)
    profile[unit].raidMarkerEnabled = on
    W.now = W.now + 1
    RaidMarkerReload(frames, GetSettingsForUnit)
end

local function Occupy(unit, guid, marker)
    W.exists[unit] = guid ~= nil
    W.guid[unit] = guid
    W.marker[unit] = marker
end

local function Shows(icon, index)
    return icon._shown == true and icon._markerIndex == index
end

local CHANGED = { target = "PLAYER_TARGET_CHANGED", focus = "PLAYER_FOCUS_CHANGED" }

-------------------------------------------------------------------------------
--  1. Show Raid Marker on at login: a swap follows the new occupant
-------------------------------------------------------------------------------
for unit, event in pairs(CHANGED) do
    for k in pairs(frames) do frames[k] = nil end
    local _, icon = Spawn(unit, true)
    RaidMarkerReload(frames, GetSettingsForUnit)
    Occupy(unit, "Creature-A", 8)
    Fire(event)
    check(Shows(icon, 8), unit .. " on at login: the marked occupant shows its skull")
    Occupy(unit, "Creature-B", nil)
    Fire(event)
    check(icon._shown == false, unit .. " on at login: a swap to an unmarked occupant hides the marker")
    Occupy(unit, "Creature-C", 3)
    Fire(event)
    check(Shows(icon, 3), unit .. " on at login: a swap to a marked occupant shows its own marker")
end

-------------------------------------------------------------------------------
--  2. Off at login, turned on in the session (the report)
-------------------------------------------------------------------------------
for unit, event in pairs(CHANGED) do
    for k in pairs(frames) do frames[k] = nil end
    local frame, icon = Spawn(unit, false)
    RaidMarkerReload(frames, GetSettingsForUnit)
    Occupy(unit, "Creature-A", 8)
    Fire(event)
    check(icon._shown == false, unit .. " off at login: no marker shows")

    -- The player turns Show Raid Marker on with the marked mob targeted
    SetOption(unit, true)
    check(Shows(icon, 8), unit .. " turned on: the current occupant's skull shows at once")

    -- Swap to a mob with no marker: the skull must go
    Occupy(unit, "Creature-B", nil)
    Fire(event)
    check(icon._shown == false, unit .. " turned on in session: a swap to an unmarked occupant hides the old marker")

    -- Swap to a mob with another marker: that marker must show
    Occupy(unit, "Creature-C", 3)
    Fire(event)
    check(Shows(icon, 3), unit .. " turned on in session: a swap to a marked occupant shows its own marker")

    -- A marker placed on the current occupant still repaints
    W.marker[unit] = 5
    Fire("RAID_TARGET_UPDATE")
    check(Shows(icon, 5), unit .. " turned on in session: a new marker on the occupant shows")

    -- The frame showing again (unit watch) repaints in full too
    Occupy(unit, "Creature-D", nil)
    for _, fn in ipairs(frame._hooks.OnShow or {}) do fn(frame) end
    check(icon._shown == false, unit .. " turned on in session: a show with an unmarked occupant hides the marker")

    -- Off, on, off, on: the channel joins the repaint list once (the clock
    -- moves on every read here, so a channel listed twice would paint twice)
    SetOption(unit, false)
    SetOption(unit, true)
    SetOption(unit, false)
    SetOption(unit, true)
    Occupy(unit, "Creature-E", 1)
    local before = markerPaints
    W.tick = true
    Fire(event)
    W.tick = false
    check(markerPaints - before == 1, unit .. " toggled several times: one marker paint per swap, got " .. (markerPaints - before))
    check(Shows(icon, 1), unit .. " toggled several times: the swap still shows the new marker")

    -- Turned off again: a swap shows nothing
    SetOption(unit, false)
    Occupy(unit, "Creature-F", 2)
    Fire(event)
    check(icon._shown == false, unit .. " turned off again: a swap to a marked occupant shows nothing")
end

-------------------------------------------------------------------------------
--  3. Off at login and never turned on: a swap paints no marker at all
-------------------------------------------------------------------------------
for unit, event in pairs(CHANGED) do
    for k in pairs(frames) do frames[k] = nil end
    local _, icon = Spawn(unit, false)
    RaidMarkerReload(frames, GetSettingsForUnit)
    -- Settings edits that leave the marker off
    SetOption(unit, false)
    SetOption(unit, false)
    Occupy(unit, "Creature-A", 8)
    local before = markerPaints
    Fire(event)
    Occupy(unit, "Creature-B", 4)
    Fire(event)
    check(markerPaints == before, unit .. " off all session: a swap runs no marker paint, got " .. (markerPaints - before))
    check(icon._shown == false, unit .. " off all session: no marker shows")
end

print(string.format("%d checks, %d failed", checks, fails))
if fails > 0 then error(fails .. " check(s) failed") end
print("PASS")
