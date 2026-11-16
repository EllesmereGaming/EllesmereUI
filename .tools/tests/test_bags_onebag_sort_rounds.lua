-- Stub harness: the Bags OneBag sort run (DoPhysicalSort in EUI_Bags_Header.lua):
-- its rounds, the wait between them and its end. The real code, cut out of the
-- file from the two work frames to the end of DoPhysicalSort (a moved line fails
-- here by name), runs over a stubbed bag engine with a fake clock: latency,
-- item locks, BAG_UPDATE per answer, BAG_UPDATE_DELAYED once per frame that had
-- a bag update, ITEM_LOCK_CHANGED per lock change.
-- The engine is a model, not the client: a picked-up item is locked until the
-- server answers, a pickup of a locked item fails, an answer unlocks both slots,
-- timers fire on the first frame at or past their due time. Which frames get an
-- event that is being dispatched when a frame registers for it is not known, so
-- every scenario runs under both answers: "A" (the frames registered when the
-- dispatch began) and "B" (a frame that registers during it gets it too).
--   lua .tools/tests/test_bags_onebag_sort_rounds.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local SRC
do
    local src = ReadSource("EllesmereUIBags/EUI_Bags_Header.lua")
    local a = assert(src:find("    local consolidateFrame, retryFrame\n", 1, true), "the work frames' line not found")
    local b = assert(src:find("    -- skipRefresh: the caller refreshes the bags", a, true), "the end of DoPhysicalSort not found")
    SRC = src:sub(a, b - 1)
        .. "\n    DoVisualSort = function() VISUAL_CALLS = VISUAL_CALLS + 1 end\n"
        .. "    return DoPhysicalSort\n"
end

-- Deterministic random
local seed
local function rnd(n) seed = (seed * 16807) % 2147483647; return (seed % n) + 1 end

local MAXSTACK = {}
for id = 1, 8 do MAXSTACK[id] = 20 end

-- opts: latency; spread (seconds between the answers of one pass); unlockLag
-- (frames between an answer's bag change and its unlock); model "A" / "B"; dt;
-- stuckLock (an unrelated item locked for good); lateUnlock (that item's lock
-- ends this long after the run's end began waiting, told through lateVia:
-- "ITEM_LOCK_CHANGED" or "BAG_UPDATE_DELAYED"); noise (a lock event that long
-- into that wait, with the item still locked); reagent; dropAll (the server
-- never answers); timersFirst (timers before events in a frame); mergeOnly;
-- sorted (the bags start sorted, nothing to merge); combatAt (combat starts);
-- drawError (the bags repaint errors while the run holds it)
local function Run(opts)
    seed = opts.seed or 7
    local dt = opts.dt or (1 / 60)
    local now = 0
    local bags = {}
    local SLOTS = { [0] = 16, 20, 20, 20, 20, opts.reagent and 16 or 0 }
    for b = 0, 5 do bags[b] = { n = SLOTS[b] } end
    if opts.sorted then
        local b, s = 0, 0
        for id = 10, 40 do
            s = s + 1
            if s > bags[b].n then b, s = b + 1, 1 end
            bags[b][s] = { id = id, count = 1, locked = false }
        end
    else
        local placed = 0
        while placed < (opts.items or 60) do
            local b = rnd(5) - 1
            local s = rnd(bags[b].n)
            if not bags[b][s] then
                local id = rnd(25)
                bags[b][s] = { id = id, count = MAXSTACK[id] and rnd(19) or 1, locked = false }
                placed = placed + 1
            end
        end
    end
    if opts.reagent then
        for _ = 1, 10 do
            local s = rnd(16)
            if not bags[5][s] then bags[5][s] = { id = 30 + rnd(6), count = 1, locked = false } end
        end
    end
    local stuck
    if opts.stuckLock then
        for s = 1, bags[3].n do
            if bags[3][s] then stuck = bags[3][s]; stuck.locked = true; break end
        end
    end

    -- event registry
    local regs, regId = {}, 0
    local function IsReg(f, e)
        for _, r in ipairs(regs[e] or {}) do if r.f == f then return r end end
    end
    local function Reg(f, e)
        if IsReg(f, e) then return end
        regs[e] = regs[e] or {}
        regId = regId + 1
        regs[e][#regs[e] + 1] = { f = f, id = regId }
    end
    local function Unreg(f, e)
        local l = regs[e]
        if not l then return end
        for i = #l, 1, -1 do if l[i].f == f then table.remove(l, i) end end
    end
    local function Fire(e, ...)
        local l = regs[e]
        if not l then return end
        if opts.model == "B" then
            local done = {}
            while true do
                local pick
                for _, r in ipairs(regs[e] or {}) do if not done[r.id] then pick = r; break end end
                if not pick then break end
                done[pick.id] = true
                if pick.f._onevent then pick.f._onevent(pick.f, e, ...) end
            end
        else
            local snap = {}
            for i, r in ipairs(l) do snap[i] = r end
            for _, r in ipairs(snap) do
                local cur = IsReg(r.f, e)
                if cur and cur.id == r.id and r.f._onevent then r.f._onevent(r.f, e, ...) end
            end
        end
    end
    local function CreateFrame()
        local f = {}
        function f:RegisterEvent(e) Reg(self, e) end
        function f:UnregisterEvent(e) Unreg(self, e) end
        function f:UnregisterAllEvents() for e in pairs(regs) do Unreg(self, e) end end
        function f:SetScript(_, fn) self._onevent = fn end
        return f
    end

    -- timers
    local timers, tseq = {}, 0
    local function After(d, fn)
        tseq = tseq + 1
        timers[#timers + 1] = { due = now + d - 1e-9, fn = fn, seq = tseq }
    end

    -- what the run did, in order: "R" a repaint while the run holds the bags, "M" a
    -- batch of item moves, "F" the repaint that gives the bags back
    local log = {}
    local function Note(token)
        if token == "M" and log[#log] == "M" then return end
        log[#log + 1] = token
    end

    -- server answers
    local answers = {}
    local delayedPending = false
    local lastBatchAt
    local cursor
    local function Item(b, s) return bags[b] and bags[b][s] end
    local function SetLock(it, on)
        if it and it.locked ~= on then
            it.locked = on
            Fire("ITEM_LOCK_CHANGED")
        end
    end
    local function Pickup(b, s)
        if not cursor then
            local it = Item(b, s)
            if it and not it.locked then cursor = { b, s }; SetLock(it, true) end
            return
        end
        local src = cursor
        local tit = Item(b, s)
        if tit and tit.locked then return end -- target locked: the item stays on the cursor
        cursor = nil
        SetLock(tit, true)
        Note("M")
        if opts.dropAll then return end
        local k = #answers
        answers[#answers + 1] = { due = now + opts.latency + (opts.spread or 0) * k, fn = function()
            local cur = Item(src[1], src[2])
            local tgt = Item(b, s)
            if cur and tgt and cur.id == tgt.id and (MAXSTACK[cur.id] or 1) > 1 then
                local mv = math.min(MAXSTACK[cur.id] - tgt.count, cur.count)
                tgt.count = tgt.count + mv
                cur.count = cur.count - mv
                if cur.count == 0 then bags[src[1]][src[2]] = nil end
            else
                bags[src[1]][src[2]], bags[b][s] = tgt, cur
            end
            local function unlock()
                SetLock(cur, false)
                SetLock(tgt, false)
            end
            if (opts.unlockLag or 0) > 0 then
                answers[#answers + 1] = { due = now + (opts.unlockLag * dt) - 1e-9, fn = unlock }
            else
                unlock()
            end
            Fire("BAG_UPDATE", src[1])
            if b ~= src[1] then Fire("BAG_UPDATE", b) end
            delayedPending = true
        end }
    end
    local function ClearCursor()
        if cursor then
            SetLock(Item(cursor[1], cursor[2]), false)
            cursor = nil
        end
    end

    local W = { holds = 0, releases = 0, errors = 0 }
    local EUI_Bags = { refreshEnabled = true }
    function EUI_Bags:RefreshInventory()
        if self.refreshEnabled then
            Note("F")
        else
            Note("R")
            if opts.drawError then error("repaint bug") end
        end
    end

    local env = setmetatable({
        CreateFrame = CreateFrame,
        sortLocked = false,
        ApplySortEnabled = function() end,
        EUI_Bags = EUI_Bags,
        InCombatLockdown = function() return false end,
        GetCVar = function() return "1" end,
        PlaySound = function() end,
        SOUNDKIT = { UI_BAG_SORTING_01 = 1 },
        EllesmereUI = {
            HoldCVar = function() W.holds = W.holds + 1 end,
            ReleaseCVar = function() W.releases = W.releases + 1 end,
            DropHold = function() end,
        },
        securecallfunction = function(fn, ...)
            if not pcall(fn, ...) then W.errors = W.errors + 1 end
        end,
        C_Timer = { After = After },
        C_Container = {
            GetContainerNumSlots = function(b) return bags[b] and bags[b].n or 0 end,
            GetContainerItemInfo = function(b, s)
                local it = Item(b, s)
                if it then return { itemID = it.id, stackCount = it.count, isLocked = it.locked } end
            end,
            GetContainerItemLink = function(b, s)
                local it = Item(b, s)
                return it and ("item:" .. it.id)
            end,
            PickupContainerItem = Pickup,
        },
        ClearCursor = ClearCursor,
        C_Item = {
            GetItemInfo = function(id) return nil, nil, nil, nil, nil, nil, nil, MAXSTACK[id] or 1 end,
            IsLocked = function(loc) local it = Item(loc.bag, loc.slot); return it and it.locked or false end,
        },
        ItemLocation = { CreateFromBagAndSlot = function(_, b, s) return { bag = b, slot = s } end },
        ns = { SpecialBags = function() return nil end },
        EUI_CategoryManager = {
            ClassifyAll = function(_, items) for _, d in ipairs(items) do d.categoryIndex = 1 end end,
            GetCategories = function() return { {} } end,
            GetGroupMembers = function() return {} end,
        },
        PreCacheSortFields = function() end,
        VisualSortCompare = function(a, b)
            if a.info.itemID ~= b.info.itemID then return a.info.itemID < b.info.itemID end
            return a.pos < b.pos
        end,
        BP = function() return { bagSortToBottom = false } end,
        VISUAL_CALLS = 0,
    }, { __index = _G })
    local chunk = assert(loadstring(SRC, "=EUI_Bags_Header.lua"))
    setfenv(chunk, env)
    local DoPhysicalSort = chunk()

    DoPhysicalSort(opts.mergeOnly)
    W.atOnce = EUI_Bags.refreshEnabled       -- the run ended inside the click
    local finishAt = EUI_Bags.refreshEnabled and 0 or nil
    local tailAt, lateDone, noiseDone, combatDone
    while now < (opts.maxT or 20) do
        now = now + dt
        local function RunAnswers()
            table.sort(answers, function(a, b) return a.due < b.due end)
            local due, rest = {}, {}
            for _, a in ipairs(answers) do if a.due <= now then due[#due + 1] = a else rest[#rest + 1] = a end end
            answers = rest
            for _, a in ipairs(due) do a.fn() end
            if delayedPending then
                delayedPending = false
                lastBatchAt = now
                Fire("BAG_UPDATE_DELAYED")
            end
        end
        local function RunTimers()
            local due, rest = {}, {}
            for _, t in ipairs(timers) do if t.due <= now then due[#due + 1] = t else rest[#rest + 1] = t end end
            timers = rest
            table.sort(due, function(a, b) return a.seq < b.seq end)
            for _, t in ipairs(due) do t.fn() end
        end
        if opts.combatAt and not combatDone and now >= opts.combatAt then
            combatDone = true
            Fire("PLAYER_REGEN_DISABLED")
        end
        if opts.timersFirst then RunTimers(); RunAnswers() else RunAnswers(); RunTimers() end
        -- the run's end is waiting for the last locks
        if not tailAt and regs.ITEM_LOCK_CHANGED and #regs.ITEM_LOCK_CHANGED > 0 then tailAt = now end
        if opts.noise and tailAt and not noiseDone and now >= tailAt + opts.noise - 1e-9 then
            noiseDone = true
            Fire("ITEM_LOCK_CHANGED")
            Fire("BAG_UPDATE_DELAYED")
        end
        if opts.lateUnlock and tailAt and not lateDone and now >= tailAt + opts.lateUnlock - 1e-9 then
            lateDone = true
            stuck.locked = false
            Fire(opts.lateVia)
        end
        if not finishAt and EUI_Bags.refreshEnabled then finishAt = now end
        if finishAt and now > finishAt + 4 then break end
    end

    -- sorted: bags 0-4 as one list, then bag 5 alone
    local function SortedRange(b0, b1)
        local seenEmpty, last = false, -1
        for b = b0, b1 do
            for s = 1, bags[b].n do
                local it = bags[b][s]
                if it then
                    if seenEmpty or it.id < last then return false end
                    last = it.id
                else
                    seenEmpty = true
                end
            end
        end
        return true
    end
    local merged, partials = true, {}
    for b = 0, 4 do
        for s = 1, bags[b].n do
            local it = bags[b][s]
            if it and MAXSTACK[it.id] and it.count < MAXSTACK[it.id] then
                partials[it.id] = (partials[it.id] or 0) + 1
                if partials[it.id] > 1 then merged = false end
            end
        end
    end
    local leftover = 0
    for _, l in pairs(regs) do leftover = leftover + #l end
    W.finishAt, W.tailAt, W.lastBatchAt = finishAt, tailAt, lastBatchAt
    W.sorted = SortedRange(0, 4) and (not opts.reagent or SortedRange(5, 5))
    W.merged, W.leftover, W.locked, W.visual = merged, leftover, env.sortLocked, env.VISUAL_CALLS
    W.log = table.concat(log)
    return W
end

-- What every run owes, however it ends: it ends, the bags are given back by one
-- repaint, the sound effects are released once, the button unlocks, no event stays
-- registered, and a repaint inside the run always has moves right behind it
-- (failedMoves: except where an unrelated lock makes a round's moves fail).
local function Owed(w, name, failedMoves)
    check(w.finishAt ~= nil, name .. ": the run never gave the bags back")
    check(w.leftover == 0, name .. ": " .. w.leftover .. " event registration(s) left")
    check(w.holds == 1 and w.releases == 1, name .. ": sound effects held " .. w.holds .. " and released " .. w.releases .. " time(s)")
    check(w.locked == false, name .. ": the Sort button stayed locked")
    local _, finals = w.log:gsub("F", "")
    check(finals == 1 and w.log:sub(-1) == "F", name .. ": the bags are given back by one last repaint: " .. w.log)
    if not failedMoves then
        check(not w.log:find("R[RF]"), name .. ": a repaint inside the run with no moves behind it: " .. w.log)
    end
end

local SCENARIOS = {
    { name = "latency 0.05",                    latency = 0.05, within = 1.0 },
    { name = "latency 0.10",                    latency = 0.10, within = 1.6 },
    { name = "latency 0.20",                    latency = 0.20, within = 2.7 },
    { name = "latency 0.30",                    latency = 0.30, within = 3.7 },
    { name = "answers a frame apart",           latency = 0.05, spread = 1 / 60 },
    { name = "answers 10 ms apart",             latency = 0.08, spread = 0.01 },
    { name = "unlocks two frames late",         latency = 0.05, unlockLag = 2, within = 2.6 },
    { name = "a reagent bag",                   latency = 0.05, reagent = true },
    { name = "20 frames a second",              latency = 0.05, dt = 1 / 20 },
    { name = "timers before events",            latency = 0.05, timersFirst = true },
}
for _, model in ipairs({ "A", "B" }) do
    for _, sc in ipairs(SCENARIOS) do
        sc.model = model
        local name = model .. " " .. sc.name
        local w = Run(sc)
        Owed(w, name)
        check(w.sorted, name .. ": the bags are not sorted")
        check(w.merged, name .. ": partial stacks were left unmerged")
        check(w.log:find("R", 1, true) ~= nil, name .. ": no round was drawn")
        check(w.errors == 0, name .. ": a repaint errored")
        if sc.within then
            check(w.finishAt ~= nil and w.finishAt <= sc.within, ("%s: the sort took %.3f s"):format(name, w.finishAt or -1))
        end
        -- nothing is locked once the last answers are in, so the bags come back in that frame
        if not sc.spread and not sc.unlockLag then
            check(w.finishAt == w.lastBatchAt and w.tailAt == nil,
                ("%s: the bags came back at %.3f, the last answers at %.3f"):format(name, w.finishAt or -1, w.lastBatchAt or -1))
        end
    end
end

for _, model in ipairs({ "A", "B" }) do
    -- nothing to merge or sort: the run ends inside the click
    local w = Run({ latency = 0.05, model = model, sorted = true })
    Owed(w, model .. " already sorted")
    check(w.atOnce == true and w.log == "F", model .. " already sorted: the bags are not given back at once: " .. w.log)

    -- a category's Sort Items: the merge run, then the display sort, one repaint
    w = Run({ latency = 0.05, model = model, mergeOnly = true })
    Owed(w, model .. " merge only")
    check(w.merged and w.visual == 1, model .. " merge only: stacks merged " .. tostring(w.merged) .. ", display sorts " .. w.visual)
    check(not w.log:find("R", 1, true), model .. " merge only: a repaint inside the run: " .. w.log)

    -- the server never answers: the backstop ends the run, whose end then waits
    -- out its cap for the moves that stay locked
    w = Run({ latency = 0.05, model = model, dropAll = true })
    Owed(w, model .. " no answers")
    check(w.finishAt ~= nil and w.finishAt >= 5.25 and w.finishAt < 5.4, ("%s no answers: the run ended at %.3f"):format(model, w.finishAt or -1))

    -- an unrelated item stays locked (a trade, a mail attachment): the run's end
    -- waits for it no longer than the cap, and an event that finds it still locked
    -- ends nothing
    w = Run({ latency = 0.05, model = model, stuckLock = true, noise = 0.05 })
    Owed(w, model .. " a stuck lock", true)
    check(w.tailAt ~= nil and w.finishAt ~= nil and w.finishAt - w.tailAt > 0.28 and w.finishAt - w.tailAt < 0.36,
        ("%s a stuck lock: the end waited %.3f s"):format(model, (w.finishAt or 0) - (w.tailAt or 0)))
    -- ...and ends at the event that finds nothing locked, whichever it is
    for _, via in ipairs({ "ITEM_LOCK_CHANGED", "BAG_UPDATE_DELAYED" }) do
        w = Run({ latency = 0.05, model = model, stuckLock = true, lateUnlock = 0.1, lateVia = via })
        Owed(w, model .. " a lock that ends, " .. via, true)
        check(w.tailAt ~= nil and w.finishAt ~= nil and w.finishAt - w.tailAt > 0.08 and w.finishAt - w.tailAt < 0.14,
            ("%s a lock that ends, %s: the end waited %.3f s"):format(model, via, (w.finishAt or 0) - (w.tailAt or 0)))
    end

    -- combat starts mid-run: the run ends at that edge, once
    w = Run({ latency = 0.10, model = model, combatAt = 0.25 })
    Owed(w, model .. " combat")
    check(w.finishAt ~= nil and w.finishAt >= 0.25 and w.finishAt < 0.29, ("%s combat: the run ended at %.3f"):format(model, w.finishAt or -1))

    -- the per-round repaint errors: reported, and the run still reaches its end
    w = Run({ latency = 0.05, model = model, drawError = true })
    Owed(w, model .. " a repaint that errors")
    check(w.errors > 0 and w.sorted, model .. " a repaint that errors: errors " .. w.errors .. ", sorted " .. tostring(w.sorted))
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_bags_onebag_sort_rounds (" .. count .. " checks)")
