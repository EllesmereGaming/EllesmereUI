-- Stub harness: the WoW Forever druid mana bar's anchor edge. A change to the
-- edge it lends the Power Bar's linked elements cascades at once and queues
-- one more cascade for the next frame (a shapeshift re-lays the bars after the
-- first one in the same event); one queued at most, none in Unlock Mode.
--   lua .tools/tests/test_rb_forever_druid_mana_cascade.lua [file]
local PATH = (arg and arg[1]) or "EllesmereUIResourceBars/EUI_ResourceBars_ForeverDruidMana.lua"

local fh = assert(io.open(PATH, "rb"))
local SRC = fh:read("*a"):gsub("\r\n", "\n")
fh:close()

local s = SRC:find("local cascadeQueued = false", 1, true)
assert(s, "cascadeQueued not found")
local n = SRC:find("local function NotifyExtent()", s, true)
assert(n, "NotifyExtent not found")
local _, e = SRC:find("\nend\n", n, true)
local CHUNK = SRC:sub(s, e) .. "return NotifyExtent\n"

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-- Stubs ----------------------------------------------------------------------
local S = { shown = true, parked = false, extSide = "BOTTOM", extSig = "BOTTOM:6:2:0:0" }
local cascades, queue = 0, {}
local EUI = { _unlockActive = false }
EUI.PropagateAnchorChain = function(key)
    assert(key == "ERB_Power", "cascade for the wrong element")
    cascades = cascades + 1
end
local env = setmetatable({
    S = S, EllesmereUI = EUI,
    C_Timer = { After = function(d, fn) assert(d == 0, "not a next-frame deferral"); queue[#queue + 1] = fn end },
}, { __index = _G })
local fn = assert(loadstring(CHUNK, "@ForeverDruidMana"))
setfenv(fn, env)
local NotifyExtent = fn()
local function NextFrame()
    local q = queue
    queue = {}
    for i = 1, #q do q[i]() end
end

-- 1. A new edge cascades now and queues one more.
NotifyExtent()
check(cascades == 1 and #queue == 1, "a new edge: " .. cascades .. " cascades, " .. #queue .. " queued")

-- 2. Another change in the same frame cascades again but queues nothing more.
S.extSig = "BOTTOM:8:2:0:0"
NotifyExtent()
check(cascades == 2 and #queue == 1, "a second change queued another pass")

-- 3. The same edge again does nothing.
NotifyExtent()
check(cascades == 2 and #queue == 1, "an unchanged edge did work")

-- 4. The next frame cascades once; the next change queues again.
NextFrame()
check(cascades == 3 and #queue == 0, "the next-frame pass did not cascade once")
S.shown = false
NotifyExtent()
check(cascades == 4 and #queue == 1, "a change after the pass did not queue again")
NextFrame()
check(cascades == 5, "the second next-frame pass did not cascade")

-- 5. Unlock Mode: a change only records, and a queued pass that lands while it
-- is open cascades nothing.
S.shown = true
EUI._unlockActive = true
NotifyExtent()
check(cascades == 5 and #queue == 0, "Unlock Mode: a change cascaded or queued")
EUI._unlockActive = false
S.extSig = "BOTTOM:10:2:0:0"
NotifyExtent()
check(cascades == 6 and #queue == 1, "after Unlock Mode: a change did not cascade and queue")
EUI._unlockActive = true
NextFrame()
check(cascades == 6, "a queued pass cascaded in Unlock Mode")
EUI._unlockActive = false
S.extSig = "BOTTOM:12:2:0:0"
NotifyExtent()
check(#queue == 1, "a pass skipped in Unlock Mode left the queue blocked")
NextFrame()

-- 6. No cascade function yet (the unlock part has not run): nothing queued.
local prop = EUI.PropagateAnchorChain
EUI.PropagateAnchorChain = nil
S.extSig = "BOTTOM:14:2:0:0"
NotifyExtent()
check(#queue == 0, "queued a pass without a cascade function")
EUI.PropagateAnchorChain = prop

if fails > 0 then error(fails .. " check(s) failed") end
print("PASS test_rb_forever_druid_mana_cascade")
