-------------------------------------------------------------------------------
--  EllesmereUI_Mouse.lua
--  The suite's single shared cursor service. Every feature that follows or
--  watches the pointer subscribes here instead of owning an OnUpdate, so the
--  whole suite pays for GetCursorPosition and the per-frame entry ONCE.
--
--  Two tiers, both demand-gated (zero subscribers anywhere = zero cost):
--
--  Tier A (SubscribeFrame): per-render-frame callbacks riding the shared
--  Tick driver -- for pixels GLUED to the pointer (cursor-anchored bars,
--  rings). Position has no engine easing, so a moving cursor genuinely needs
--  one reposition per rendered frame. motionOnly subscribers are parked after
--  ~1s of stillness (mouselook freezes GetCursorPosition, so combat camera
--  control parks them too); the watch ticker re-arms them on the first moved
--  sample, worst case one watch interval (~50ms) behind the first pixel of
--  motion, then per-frame while it moves. Non-motionOnly subscribers (time-
--  driven transients: trail fades, ring fills) keep the driver alive until
--  they unsubscribe themselves.
--
--  Tier B (SubscribeTick): low-rate callbacks on a self-stopping anim ticker
--  (the C engine sleeps between fires -- no per-frame Lua exists for these).
--  For region checks and state watches (mouseover visibility fades, panel
--  state). The same ticker doubles as Tier A's motion watch: 20 Hz while any
--  Tier A subscriber exists, 0.15s otherwise, stopped at zero subscribers.
--
--  Attribution: everything here is parent-born, so subscriber work bills the
--  parent addon bucket (frame-birth rule) -- accepted and documented; the
--  suite TOTAL is what the consolidation lowers.
-------------------------------------------------------------------------------
local EUI = EllesmereUI
local Tick = EUI.Tick

local GetCursorPosition, GetTime = GetCursorPosition, GetTime

local M = {}
EUI.Mouse = M

-- Last sampled raw (unscaled) cursor coordinates. Valid whenever any
-- subscriber exists; on-demand callers use M.Get() which re-samples.
M.rawX, M.rawY = 0, 0

local frameSubs, frameCount = {}, 0   -- key -> {fn, motionOnly}
local tickSubs,  tickCount  = {}, 0   -- key -> {fn, interval, acc}
local frameArmed = false              -- Tier A riding the shared driver
local stillSince = 0
local ticker, tickerInterval

local STILL_AFTER = 1.0
local WATCH_FAST  = 0.05              -- 20 Hz motion watch while Tier A exists
local WATCH_SLOW  = 0.15              -- Tier B-only cadence
local AFK_AFTER   = 30                -- long-still: fast watch drops to slow

-- Fresh coordinates on demand (event handlers, batch region checks). Also
-- refreshes rawX/rawY so tick subscribers see the newest sample.
function M.Get()
    local x, y = GetCursorPosition()
    if x ~= M.rawX or y ~= M.rawY then
        M.rawX, M.rawY = x, y
        stillSince = GetTime()
    end
    return M.rawX, M.rawY
end

local function OnRenderFrame(elapsed)
    local x, y = GetCursorPosition()
    local moved = (x ~= M.rawX or y ~= M.rawY)
    if moved then
        M.rawX, M.rawY = x, y
        stillSince = GetTime()
    end
    local anyAlways = false
    for _, s in pairs(frameSubs) do
        s.fn(x, y, moved, elapsed)
        if not s.motionOnly then anyAlways = true end
    end
    -- Park the per-frame path once every remaining subscriber is motion-only
    -- and the cursor has settled; the watch ticker owns the re-arm.
    if not anyAlways and GetTime() - stillSince > STILL_AFTER then
        frameArmed = false
        Tick.Remove("mouse")
    end
end

local function WatchBody()
    -- Sample whenever the per-frame path is not doing it: keeps rawX/rawY
    -- fresh for Tier B subscribers AND doubles as Tier A's motion watch --
    -- the first moved sample re-arms the per-frame path.
    if not frameArmed then
        local x, y = GetCursorPosition()
        if x ~= M.rawX or y ~= M.rawY then
            M.rawX, M.rawY = x, y
            stillSince = GetTime()
            if frameCount > 0 then
                frameArmed = true
                Tick.Add("mouse", OnRenderFrame)
            end
        end
    end
    -- Tier B dispatch on per-subscriber accumulators.
    for _, s in pairs(tickSubs) do
        s.acc = s.acc + tickerInterval
        if s.acc >= s.interval then
            s.acc = 0
            s.fn(M.rawX, M.rawY)
        end
    end
    -- Long-still downshift: Tier A subscribers exist but the cursor has not
    -- moved for 30s (AFK, reading, mouselook held) -- drop the 20 Hz watch
    -- to the slow cadence. The first movement after that pays ONE slow
    -- interval (<=150ms) of catch-up, then per-frame glue resumes; motion
    -- within the 30s window always re-arms at the fast ~50ms. Tier B
    -- accumulators read tickerInterval, so they stay exact through swaps.
    local want
    if frameCount > 0
       and (frameArmed or (GetTime() - stillSince) <= AFK_AFTER) then
        want = WATCH_FAST
    else
        want = WATCH_SLOW
    end
    if want ~= tickerInterval and ticker then
        ticker.Stop()
        tickerInterval = want
        ticker.Start(want)
    end
    return (frameCount + tickCount) > 0   -- falsy = self-stop at zero subs
end

-- One host frame, parent main chunk (parent-billed by design; see header).
local watchHost = CreateFrame("Frame")

local function EnsureTicker()
    if frameCount + tickCount == 0 then
        if ticker then ticker.Stop() end
        return
    end
    local want = (frameCount > 0) and WATCH_FAST or WATCH_SLOW
    if not ticker then
        tickerInterval = want
        ticker = Tick.NewAnimTicker(watchHost, WatchBody, want)
        ticker.Start()
        return
    end
    if want ~= tickerInterval then
        ticker.Stop()
        tickerInterval = want
        ticker.Start(want)
    else
        ticker.Start()
    end
end

-- Tier A. fn(cx, cy, moved, elapsed) per render frame while armed. Same key
-- replaces. motionOnly subscribers park with the cursor; others hold the
-- driver until unsubscribed (transient animators must unsubscribe when done).
function M.SubscribeFrame(key, fn, motionOnly)
    if not key or type(fn) ~= "function" then return end
    if not frameSubs[key] then frameCount = frameCount + 1 end
    frameSubs[key] = { fn = fn, motionOnly = motionOnly and true or false }
    if not frameArmed then
        frameArmed = true
        stillSince = GetTime()
        Tick.Add("mouse", OnRenderFrame)
    end
    EnsureTicker()
end

function M.UnsubscribeFrame(key)
    if not frameSubs[key] then return end
    frameSubs[key] = nil
    frameCount = frameCount - 1
    if frameCount == 0 and frameArmed then
        frameArmed = false
        Tick.Remove("mouse")
    end
    EnsureTicker()
end

-- Tier B. fn(rawX, rawY) every `interval` seconds (multiples of the watch
-- cadence). Same key replaces and keeps the accumulator.
function M.SubscribeTick(key, interval, fn)
    if not key or type(fn) ~= "function" then return end
    local s = tickSubs[key]
    if s then
        s.fn = fn
        s.interval = interval or WATCH_SLOW
    else
        tickCount = tickCount + 1
        tickSubs[key] = { fn = fn, interval = interval or WATCH_SLOW, acc = 0 }
    end
    EnsureTicker()
end

function M.UnsubscribeTick(key)
    if not tickSubs[key] then return end
    tickSubs[key] = nil
    tickCount = tickCount - 1
    EnsureTicker()
end
