-------------------------------------------------------------------------------
--  EllesmereUI Shared Ticker
--
--  Self-disarming OnUpdate drivers: a driver frame only exists-as-running
--  while at least one subscriber is registered, so an idle UI runs no
--  per-frame code at all.
--
--  ATTRIBUTION (probe-verified 2026-07-26): the engine bills a script
--  handler's ENTIRE call tree to the addon whose execution context called
--  CreateFrame for the frame carrying the handler. The handler closure's
--  origin does not matter; who called SetScript does not matter; only the
--  frame's birth context matters -- and that context is inherited from the
--  current engine entry point (taint-style), NOT from the file the code
--  lives in. OnInitialize/OnEnable run under the parent's lifecycle
--  dispatch, so frames created there are billed to the PARENT forever.
--
--  Because of that rule there are two ways to use this module:
--
--    * EllesmereUI.Tick.Add/Remove -- the shared driver. Its frame is
--      created in this (parent) file, so ALL subscriber work is billed to
--      the parent addon. Fine for parent-owned work only.
--
--    * EllesmereUI.Tick.NewDriver(frame) -- per-addon driver. The caller
--      passes a frame it created in its OWN MAIN CHUNK (file scope), which
--      stamps the frame to that addon; every subscriber tick then bills the
--      subscribing addon. The driver logic living here in parent code is
--      irrelevant to attribution -- only the frame's birth context counts.
--
--  Usage:
--      -- child file scope:
--      ns.Drv = EllesmereUI.Tick.NewDriver(CreateFrame("Frame"))
--      -- anywhere:
--      ns.Drv.Add("erb_cast", function(dt) ... end)
--      ns.Drv.Remove("erb_cast")
--
--  Contract (identical for the shared driver and per-addon drivers):
--    * Add is idempotent. Calling it again with the same key replaces the
--      function and does not duplicate the entry, so an event handler can arm
--      unconditionally without first checking whether it is already armed.
--      That is deliberate: a missed re-arm freezes a bar, so callers should
--      always arm rather than trying to be clever about whether it is needed.
--    * A subscriber MUST remove itself once its work has settled (animation
--      reached its target, cast ended, cooldown finished). Removing from
--      inside your own tick is safe and is the normal way to do it.
--    * Remove on an unregistered key is a no-op, so pairing every start with
--      a stop is always safe.
--    * dt is real elapsed time since the previous dispatch, so animation
--      speed matches a per-frame OnUpdate exactly.
--
--  Note: EllesmereUI_Glows.lua deliberately keeps its own private driver. It
--  already implements this same arm/disarm discipline and is already free
--  when idle, so there is nothing to gain by routing it through here.
-------------------------------------------------------------------------------

local Tick = {}
EllesmereUI.Tick = Tick

-- Build a driver instance around the given frame. The frame's creating
-- context is what the engine bills, so callers wanting per-addon attribution
-- MUST create the frame in their own main chunk and pass it in. The nil
-- fallback creates a parent-stamped frame here: everything still works, but
-- the work is billed to the parent.
local function NewDriver(frame)
    if not frame then frame = CreateFrame("Frame") end
    local reg   = {}   -- dense array of keys
    local regFn = {}   -- parallel array of tick functions
    local index = {}   -- key -> position in reg
    local count = 0
    local drv = {}

    frame:Hide()
    frame:SetScript("OnUpdate", function(self, elapsed)
        -- Walk the dense array by index. A subscriber may remove itself (or
        -- another subscriber) from inside its own tick, which swap-removes
        -- and shrinks count, so re-read count every step and re-test the
        -- current slot when it was swapped rather than advancing past the
        -- entry that moved into it.
        local i = 1
        while i <= count do
            local key = reg[i]
            local fn = regFn[i]
            if fn then fn(elapsed) end
            if reg[i] == key then
                i = i + 1
            end
        end
        if count == 0 then
            self:Hide()
        end
    end)

    -- Register (or replace) the tick function for a key. Arms the driver on
    -- the 0 -> 1 transition.
    function drv.Add(key, fn)
        if not key or type(fn) ~= "function" then return end
        local i = index[key]
        if i then
            regFn[i] = fn
            return
        end
        count = count + 1
        reg[count] = key
        regFn[count] = fn
        index[key] = count
        if count == 1 then frame:Show() end
    end

    -- Unregister a key. Swap-removes so churn stays O(1). Hides the driver
    -- once the last subscriber leaves, which is what makes idle free.
    function drv.Remove(key)
        local i = index[key]
        if not i then return end
        local lastKey = reg[count]
        reg[i] = lastKey
        regFn[i] = regFn[count]
        index[lastKey] = i
        reg[count] = nil
        regFn[count] = nil
        count = count - 1
        index[key] = nil
        if count == 0 then frame:Hide() end
    end

    function drv.Has(key)
        return index[key] ~= nil
    end

    -- Number of live subscribers. Zero means no per-frame code is running.
    function drv.Count()
        return count
    end

    return drv
end

Tick.NewDriver = NewDriver

-- Fixed-rate ticker without per-frame dispatch: a looping Animation fires
-- OnLoop at the configured interval and the C engine sleeps between fires,
-- so subscribing costs zero Lua at frame rate. Use for work that is
-- genuinely time-based (drains, recharges, hash motion); value fills should
-- be event-driven with an eased SetValue instead and need no ticker at all.
--
-- fn returns truthy to keep ticking; falsy stops the loop (self-disarm).
-- Start() on a playing ticker is one IsPlaying check, so arming can stay
-- indiscriminate. As with NewDriver, pass a frame created in the SUBSCRIBING
-- addon's main chunk so the engine bills that addon.
function Tick.NewAnimTicker(frame, fn, interval)
    if not frame then frame = CreateFrame("Frame") end
    local ag = frame:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local anim = ag:CreateAnimation("Animation")
    anim:SetDuration(interval or 0.05)
    local t = {}
    ag:SetScript("OnLoop", function()
        if not fn() then
            ag:Stop()
        end
    end)
    function t.Start(newInterval)
        if not ag:IsPlaying() then
            if newInterval then anim:SetDuration(newInterval) end
            ag:Play()
        end
    end
    function t.Stop()
        ag:Stop()
    end
    function t.IsPlaying()
        return ag:IsPlaying()
    end
    return t
end

-- The shared driver: frame created here in the parent, so subscriber work is
-- billed to the parent addon. Parent-owned subscribers only; children should
-- carry their own NewDriver(frame) with a file-scope-created frame.
local shared = NewDriver(CreateFrame("Frame"))
Tick.Add    = shared.Add
Tick.Remove = shared.Remove
Tick.Has    = shared.Has
Tick.Count  = shared.Count
