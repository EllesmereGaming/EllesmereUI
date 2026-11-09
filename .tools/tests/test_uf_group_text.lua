-- Stub harness: the Unit Frames raid group number ([group], the Group Number
-- text) repaints from one roster pass per burst of GROUP_ROSTER_UPDATE, and
-- only its own zones; value ticks leave it alone; the event is registered only
-- while a zone reads the roster.
--   lua .tools/tests/test_uf_group_text.lua [EUI_UnitFrames_Text.lua]
local PATH = (arg and arg[1]) or "EllesmereUIUnitFrames/EUI_UnitFrames_Text.lua"

local fh = assert(io.open(PATH, "rb"))
local SRC = fh:read("*a"):gsub("\r\n", "\n")
fh:close()

-- From the line holding `startPat` through the first `endPat` after it.
local function Cut(startPat, endPat, what)
    local s = SRC:find(startPat, 1, true)
    assert(s, what .. ": start not found")
    s = SRC:sub(1, s):match(".*()\n") or 1
    local _, e = SRC:find(endPat, s, true)
    assert(e, what .. ": end not found")
    return SRC:sub(s, e)
end

local CHUNK = table.concat({
    Cut("    local VALUE_CLASS = {", "\n    }\n", "VALUE_CLASS"),
    Cut("    local PIECE_READS = {", "\n    }\n", "PIECE_READS"),
    Cut("    local scratch = {}", "\n    end\n", "PaintText"),
    Cut("    local rosterEv = CreateFrame", "\n        return z\n    end\n", "MarkReads"),
    Cut("    rosterEv:SetScript(\"OnEvent\"", "\n    end)\n", "roster pass"),
    "return MarkReads, PaintText, rosterEv\n",
}, "\n")

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-- Stubs ----------------------------------------------------------------------
local ROSTER, HP, EXISTS, NOW = { player = 2 }, { player = 100 }, { player = true }, 1
local P = setmetatable({}, { __index = function(t, k)
    local f = function() return "" end
    rawset(t, k, f)
    return f
end })
P.group = function(u) return ROSTER[u] or "" end
P.curhp = function(u) return HP[u] or 0 end

local function NewFrame()
    local f = { shown = true, events = {}, scripts = {} }
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:SetScript(k, fn) self.scripts[k] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    return f
end

local frames = {}
local env = setmetatable({
    P = P, frames = frames, ns = {},
    UnitExists = function(u) return EXISTS[u] == true end,
    CreateFrame = function() return NewFrame() end,
    GetTime = function() return NOW end,
}, { __index = _G })
local fn = assert(loadstring(CHUNK, "@Text"))
setfenv(fn, env)
local MarkReads, PaintText, rosterEv = fn()

local function FS()
    local fs = { sets = 0 }
    function fs:SetFormattedText(fmt, ...) self.sets = self.sets + 1; self.text = string.format(fmt, ...) end
    return fs
end
local function Zone(piece) return MarkReads({ fs = FS(), fmt = "%s", pieces = { piece } }) end
local function Fire(n)
    for _ = 1, n do rosterEv.scripts.OnEvent(rosterEv, "GROUP_ROSTER_UPDATE") end
end
local function Tick()
    NOW = NOW + 1
    if rosterEv.shown and rosterEv.scripts.OnUpdate then rosterEv.scripts.OnUpdate(rosterEv, 0.016) end
end

-- 1. The frame starts hidden with no event; a [group] zone reads the roster
-- only and registers the event.
check(rosterEv.shown == false, "the roster frame is shown at load")
check(not rosterEv.events.GROUP_ROSTER_UPDATE, "the event is registered before any [group] zone")
local hpZ, grpZ = Zone(P.curhp), Zone(P.group)
check(grpZ.roster == true and not grpZ.any, "a [group] zone is not a roster-only zone")
check(hpZ.hp == true and not hpZ.roster, "a health zone reads the roster")
check(rosterEv.events.GROUP_ROSTER_UPDATE == true, "the [group] zone did not register the event")
frames.player = { _euiUnit = "player", _euiTextZones = { hpZ, grpZ } }

-- 2. A health tick repaints the health text and leaves the group number alone.
PaintText(frames.player, "player", "UNIT_HEALTH")
check(hpZ.fs.sets == 1 and grpZ.fs.sets == 0, "a health tick repainted the group number")

-- 3. A full repaint (no event) paints both.
NOW = NOW + 1
PaintText(frames.player, "player")
check(hpZ.fs.sets == 2 and grpZ.fs.sets == 1 and grpZ.fs.text == "2", "a full repaint missed a zone")

-- 4. A burst of roster events paints nothing at once, then one pass on the next
-- frame repaints only the group number, and the frame hides again.
ROSTER.player = 5
Fire(3)
check(grpZ.fs.sets == 1 and hpZ.fs.sets == 2, "a roster event painted before the next frame")
check(rosterEv.shown == true, "a roster event did not arm the pass")
Tick()
check(grpZ.fs.sets == 2 and grpZ.fs.text == "5", "the roster pass did not repaint the group number once")
check(hpZ.fs.sets == 2, "the roster pass repainted the health text")
check(rosterEv.shown == false, "the roster pass did not hide its frame")
Tick()
check(grpZ.fs.sets == 2, "a pass ran without a roster event")

-- 5. A frame without a unit is not painted but keeps the event registered;
-- with no [group] zone left anywhere the event goes, and a new one brings it back.
EXISTS.target = false
local tgtZ = Zone(P.group)
frames.target = { _euiUnit = "target", _euiTextZones = { tgtZ } }
frames.player._euiTextZones = { hpZ }
Fire(1); Tick()
check(tgtZ.fs.sets == 0, "the roster pass painted a frame without a unit")
check(rosterEv.events.GROUP_ROSTER_UPDATE == true, "the event went while a [group] zone exists")
frames.target._euiTextZones = {}
Fire(1); Tick()
check(not rosterEv.events.GROUP_ROSTER_UPDATE, "the event stayed with no [group] zone left")
frames.player._euiTextZones = { hpZ, Zone(P.group) }
check(rosterEv.events.GROUP_ROSTER_UPDATE == true, "a new [group] zone did not register the event again")

if fails > 0 then error(fails .. " check(s) failed") end
print("PASS test_uf_group_text")
