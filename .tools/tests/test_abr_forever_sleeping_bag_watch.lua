-- Stub harness: AuraBuff Reminders' WoW Forever Sleeping Bag arrival watcher
-- (EABR.FvSyncSleepBagWatch in EUI_AuraBuffReminders_Lifecycle.lua). While the
-- reminder is on below max level with no Cozy Sleeping Bag owned, one frame of
-- ours listens to BAG_UPDATE_DELAYED and counts the bag once per bag change;
-- the bag showing up marks it owned, stops the watcher and asks for a refresh.
-- Cuts the function out of the file and drives it on a fake frame.
--   lua .tools/tests/test_abr_forever_sleeping_bag_watch.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

local SRC = ReadSource("EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Lifecycle.lua")
local a = assert(SRC:find("    local sleepWatch\n", 1, true), "the watcher's local is missing")
local f0 = assert(SRC:find("    function EABR.FvSyncSleepBagWatch(want)", a, true), "the watcher is missing")
local e = assert(SRC:find("\n    end\n", SRC:find("        end\n    end", f0, true), true), "the watcher's end is missing")
local CUT = SRC:sub(a, e + 8)

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

local frames, events = 0, {}
local frame
local count, refreshes, bags = 0, 0, 0
local env = setmetatable({
    EABR = { SLEEPING_BAG_ITEM = 211527 },
    CreateFrame = function()
        frames = frames + 1
        frame = { scripts = {} }
        function frame:SetScript(name, fn) self.scripts[name] = fn end
        function frame:RegisterEvent(ev) events[ev] = true end
        function frame:UnregisterEvent(ev) events[ev] = nil end
        return frame
    end,
    C_Item = { GetItemCount = function(id) count = count + 1; return id == 211527 and bags or 0 end },
    RequestRefresh = function() refreshes = refreshes + 1 end,
}, { __index = _G })
local chunk = assert(loadstring(CUT, "=watcher"))
setfenv(chunk, env)
chunk()
local EABR = env.EABR
local function Fire() if events.BAG_UPDATE_DELAYED and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, "BAG_UPDATE_DELAYED") end end

-- Off: nothing is built.
EABR.FvSyncSleepBagWatch(false)
check(frames == 0 and not events.BAG_UPDATE_DELAYED, "off built or registered something")

-- On with no bag: one frame, listening; a bag change without the bag counts once and changes nothing.
EABR.FvSyncSleepBagWatch(true)
check(frames == 1 and events.BAG_UPDATE_DELAYED, "on: not listening to bag changes")
Fire()
check(count == 1 and refreshes == 0 and EABR._fvSleepBag == nil and events.BAG_UPDATE_DELAYED,
    "a bag change without the bag acted")
-- Asking again changes nothing (no second frame, no second registration).
EABR.FvSyncSleepBagWatch(true)
check(frames == 1, "a second frame was built")

-- The bag arrives: owned, the watcher stops, one refresh.
bags = 1
Fire()
check(count == 2 and EABR._fvSleepBag == true and refreshes == 1, "the bag arriving did not wake the reminder")
check(not events.BAG_UPDATE_DELAYED and EABR._fvSleepWatch == false, "the watcher kept listening once the bag came")
Fire()
check(count == 2 and refreshes == 1, "a stopped watcher still counted")

-- Turned on again later: the same frame listens again; off stops it.
EABR.FvSyncSleepBagWatch(true)
check(frames == 1 and events.BAG_UPDATE_DELAYED, "turned on again: not listening")
EABR.FvSyncSleepBagWatch(false)
check(not events.BAG_UPDATE_DELAYED, "off kept listening")

if fails > 0 then error(fails .. " check(s) failed") end
print("aurabuff reminders forever sleeping bag watcher harness: ok")
