-- Stub harness: loads the Action Bars range file outside the game and pages a
-- bar the way the game does. ACTIONBAR_PAGE_CHANGED fires first; the secure
-- state driver applies the new page on its next update, writing the bar
-- frame's "state-page" (whose OnAttributeChanged hook calls
-- ns._eabRangePageEdge) after _onstate-page has set the frame's actionpage.
-- Out-of-range coloring must follow the page the bar shows: the main bar
-- paged away and back keeps tinting an out-of-range spell, and a bar with
-- custom paging resolves and arms the slots of the page it is on.
--   lua .tools/tests/test_ab_range_paging.lua        (from the repository root)
local ROOT = arg and arg[1] or "."
local FILE = arg and arg[2] or "EllesmereUIActionBars/EUI_ActionBars_Range.lua"

local function ReadSource(name)
    local f = assert(io.open(name:find("^%a:") and name or (ROOT .. "/" .. name), "rb"))
    local src = f:read("*a")
    f:close()
    return src
end
local SRC = ReadSource(FILE)

local RED = { r = 0.7, g = 0.2, b = 0.2 }

local function Load(bars)
    local T = { timers = {}, armed = {}, page = { MainBar = 1, Bar2 = 6 }, actions = {}, outOfRange = {} }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.EUI_CLIENT_BLOCKED = nil
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.C_Timer = { After = function(_, fn) T.timers[#T.timers + 1] = fn end }
    env.hooksecurefunc = function(tbl, name, fn)
        local orig = tbl[name]
        tbl[name] = function(...) orig(...); fn(...) end
    end
    env.HasAction = function(slot) return T.actions[slot] ~= nil end
    env.IsActionInRange = function(slot)
        if not T.actions[slot] then return nil end
        return not T.outOfRange[slot]
    end
    env.C_ActionBar = { EnableActionRangeCheck = function(slot, on) T.armed[slot] = on or nil end }

    local efd = {}
    local frames, barButtons, buttonToBar = {}, {}, {}
    for key, count in pairs({ MainBar = 12, Bar2 = 12 }) do
        local frame = { _barKey = key }
        function frame:GetAttribute(name)
            if name == "actionpage" then return T.page[key] end
        end
        frames[key] = frame
        local list = {}
        for i = 1, count do
            local btn = { icon = {} }
            function btn.icon:SetVertexColor(r, g, b) self.r, self.g, self.b = r, g, b end
            function btn:UpdateUsable() self.icon:SetVertexColor(1, 1, 1) end
            list[i] = btn
            buttonToBar[btn] = { barKey = key, index = i }
        end
        barButtons[key] = list
    end
    T.frames, T.buttons = frames, barButtons

    local shell = {}
    function shell:RegisterEvent() end
    function shell:SetScript(_, fn) self.handler = fn end
    local ns = {
        EFD = function(btn)
            local t = efd[btn]
            if not t then t = {}; efd[btn] = t end
            return t
        end,
        EAB = { db = { profile = { bars = bars } } },
        EAB_VTABLE = { GetActionBarPage = function() return 1 end },
        barButtons = barButtons,
        TakeShell = function() return shell end,
        _eabBarDormant = {},
        _internals = {
            BAR_CONFIG = { { key = "MainBar" }, { key = "Bar2" } },
            NUM_ACTIONBAR_BUTTONS = 12,
            BAR_SLOT_OFFSETS = { MainBar = 0, Bar2 = 60 },
            barFrames = frames, buttonToBar = buttonToBar,
        },
    }
    local chunk = assert(loadstring(SRC, "=EUI_ActionBars_Range.lua"))
    setfenv(chunk, env)
    chunk("EllesmereUIActionBars", ns)
    T.ns, T.shell = ns, shell
    return T
end

local function Event(T, event, ...) T.shell.handler(T.shell, event, ...) end
local function RunTimers(T)
    local list = T.timers
    T.timers = {}
    for i = 1, #list do list[i]() end
end
-- The game's order for a page change: the event, then the state driver's
-- write a frame later (the hook in EUI_ActionBars_Bars.lua), then our flush.
local function PageTo(T, barKey, page, withEvent)
    if withEvent then Event(T, "ACTIONBAR_PAGE_CHANGED") end
    T.page[barKey] = page
    if T.ns._eabRangePageEdge then T.ns._eabRangePageEdge(barKey) end
    RunTimers(T)
end
local function Tinted(btn) return btn.icon.r == RED.r and btn.icon.g == RED.g and btn.icon.b == RED.b end
local function ArmedRange(T, from, to)
    for s = from, to do if not T.armed[s] then return false end end
    return true
end
local function ArmedCount(T)
    local n = 0
    for _ in pairs(T.armed) do n = n + 1 end
    return n
end

local fails = 0
local function Check(cond, msg)
    if not cond then fails = fails + 1; print("FAIL: " .. msg) end
end

-------------------------------------------------------------------------------
-- 1. the report: a ranged spell on bar 1 out of range, page away and back
-------------------------------------------------------------------------------
do
    local T = Load({ MainBar = { outOfRangeColoring = true, outOfRangeColor = RED }, Bar2 = {} })
    T.actions[3] = "Shoot"
    T.outOfRange[3] = true
    T.actions[15] = "Mend Pet"
    T.ns.EAB:ApplyRangeColoring()
    local b3 = T.buttons.MainBar[3]
    Check(ArmedRange(T, 1, 12) and ArmedCount(T) == 12, "page 1: its slots are not the armed ones")
    Check(Tinted(b3), "page 1: the out-of-range spell is not tinted")

    PageTo(T, "MainBar", 2, true)
    Check(ArmedRange(T, 13, 24) and ArmedCount(T) == 12, "page 2: the bar did not arm page 2's slots")
    Check(not Tinted(b3), "page 2: button 3 kept page 1's tint")

    PageTo(T, "MainBar", 1, true)
    Check(ArmedRange(T, 1, 12) and ArmedCount(T) == 12, "back on page 1: page 1's slots are not armed")
    Check(Tinted(b3), "back on page 1: the out-of-range spell lost its tint (the report)")

    -- the armed slot keeps reporting: in range, then out again
    Event(T, "ACTION_RANGE_CHECK_UPDATE", 3, true, true)
    Check(not Tinted(b3), "back on page 1: an in-range report did not clear the tint")
    Event(T, "ACTION_RANGE_CHECK_UPDATE", 3, false, true)
    Check(Tinted(b3), "back on page 1: an out-of-range report did not tint")
end

-------------------------------------------------------------------------------
-- 2. one flush per frame for every bar that paged, none while range coloring
--    is off everywhere
-------------------------------------------------------------------------------
do
    local T = Load({ MainBar = { outOfRangeColoring = true, outOfRangeColor = RED }, Bar2 = {} })
    T.ns.EAB:ApplyRangeColoring()
    Event(T, "ACTIONBAR_PAGE_CHANGED")
    T.page.MainBar = 3
    if T.ns._eabRangePageEdge then
        T.ns._eabRangePageEdge("MainBar")
        T.ns._eabRangePageEdge("MainBar")
        T.ns._eabRangePageEdge("Bar2")
    end
    Check(#T.timers == 1, "several page edges in one frame did not share one flush (" .. #T.timers .. ")")
    RunTimers(T)
    Check(ArmedRange(T, 25, 36) and ArmedCount(T) == 12, "page 3: the bar did not arm page 3's slots")

    local off = Load({ MainBar = {}, Bar2 = {} })
    off.ns.EAB:ApplyRangeColoring()
    Event(off, "ACTIONBAR_PAGE_CHANGED")
    if off.ns._eabRangePageEdge then off.ns._eabRangePageEdge("MainBar") end
    Check(#off.timers == 0, "range coloring off: a page edge still scheduled work")
end

-------------------------------------------------------------------------------
-- 3. a bar with custom paging resolves the page it is on
-------------------------------------------------------------------------------
do
    local bar2 = { outOfRangeColoring = true, outOfRangeColor = RED }
    local T = Load({ MainBar = {}, Bar2 = bar2 })
    T.frames.Bar2._eabPagingConds = "[mod:shift] 7; 6"
    T.actions[73] = "Arcane Shot"
    T.outOfRange[73] = true
    T.ns.EAB:ApplyRangeColoring()
    Check(ArmedRange(T, 61, 72) and ArmedCount(T) == 12, "bar 2 on its default page: slots 61-72 not armed")
    PageTo(T, "Bar2", 7, false)
    Check(ArmedRange(T, 73, 84) and ArmedCount(T) == 12, "bar 2 paged to 7: slots 73-84 not armed")
    Check(Tinted(T.buttons.Bar2[1]), "bar 2 paged to 7: its out-of-range spell is not tinted")
    -- custom paging removed: the bar's fixed page
    T.frames.Bar2._eabPagingConds = false
    T.page.Bar2 = 6
    Check(T.ns._internals.GetButtonActionSlot(T.buttons.Bar2[1]) == 61, "bar 2 unpaged: not its fixed slot")
end

print(fails == 0 and "action bars range paging harness: ok" or ("action bars range paging harness: " .. fails .. " failure(s)"))
if fails > 0 then error("failures") end
