-- Stub harness: Nameplates on WoW Forever, the paladin's Righteous Fury as a tank signal for the
-- threat colors (EUI_Nameplates_Colors.lua). With no specs there, a paladin counts as the tank
-- while Righteous Fury is up and nobody in the group has the tank role assigned.
-- The watcher block, cut out of the real file by its first and last lines (a moved line fails
-- here by name), runs over a model of the client: the player's auras, an aura restriction that
-- makes them unreadable (secret), combat, the queue that runs as combat ends, the restriction's
-- own event, and next-frame timers.
-- What it holds: each spell ID is read on its own; a read the restriction refuses keeps the last
-- answer and is retried as combat ends AND as the restriction lifts (which can come a moment
-- later), and by any aura change once out of combat; an aura update re-reads only when it may
-- have brought or taken Righteous Fury; nothing is read while the threat colors are off.
--   lua .tools/tests/test_np_forever_fury_tank.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

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
    local f = assert(io.open(ROOT .. "/EllesmereUINameplates/EUI_Nameplates_Colors.lua", "rb"))
    SRC = f:read("*a"):gsub("\r\n", "\n")
    f:close()
end
local BLOCK
do
    local a = assert(SRC:find("local FV_TANK_CLASS = EllesmereUI.IS_FOREVER\n", 1, true), "the watcher's first line not found")
    local b = assert(SRC:find("-- Show Threat Colors (threatColorMode):", a, true), "the watcher's last line not found")
    BLOCK = SRC:sub(a, b - 1)
end

-- A value the game withholds: any use of it but the test for it is an error
local SECRET = setmetatable({}, {
    __index = function() error("a secret value was indexed", 2) end,
    __len = function() error("a secret value was measured", 2) end,
    __eq = function() error("a secret value was compared", 2) end,
})
local FURY = { 25780, 407627, 407628 }

-- One client. o.class (default PALADIN), o.forever (default true), o.noCheck (a client with no secrecy test)
local function Client(o)
    o = o or {}
    local W = { combat = false, restricted = false, auras = {}, errorIDs = {}, openIDs = {}, checks = 0, lookups = 0,
        repaints = 0, queue = {}, timers = {}, events = {}, frames = 0, role = "DAMAGER", form = false, roleTank = false }
    local frame
    local env = setmetatable({
        issecretvalue = function(v) return rawequal(v, SECRET) end,
        InCombatLockdown = function() return W.combat end,
        UnitClass = function() return "x", o.class or "PALADIN" end,
        C_Secrets = (not o.noCheck) and { ShouldSpellAuraBeSecret = function(id)
            W.checks = W.checks + 1
            if W.errorIDs[id] then error("no such spell") end
            return W.restricted and not W.openIDs[id]
        end } or nil,
        C_UnitAuras = { GetPlayerAuraBySpellID = function(id)
            W.lookups = W.lookups + 1
            if W.restricted and not W.openIDs[id] then return SECRET end
            local inst = W.auras[id]
            return inst and { spellId = id, auraInstanceID = inst } or nil
        end },
        C_Timer = { After = function(_, fn) W.timers[#W.timers + 1] = fn end },
        Enum = { AddOnRestrictionType = { Combat = 1, Chat = 5 } },
        CreateFrame = function()
            W.frames = W.frames + 1
            frame = {}
            function frame:SetScript(_, fn) self.handler = fn end
            function frame:RegisterUnitEvent(e) W.events[e] = true end
            function frame:RegisterEvent(e) W.events[e] = true end
            function frame:UnregisterEvent(e) W.events[e] = nil end
            function frame:UnregisterAllEvents() for e in pairs(W.events) do W.events[e] = nil end end
            return frame
        end,
        EllesmereUI = {
            IS_FOREVER = o.forever ~= false,
            UnitEffectiveRole = function() return W.role end,
            ForeverTankForm = function() return W.form end,
            GroupHasTankRole = function() return W.roleTank, false end,
        },
    }, { __index = _G })
    local ns = { plates = { { UpdateHealthColor = function() W.repaints = W.repaints + 1 end } },
        CombatQueue = { Defer = function(key, fn) W.queue[key] = fn end } }
    env.ns = ns
    local chunk = assert(loadstring("local _isTankRole = false\n" .. BLOCK ..
        "\nreturn FvTankSync, function() return _isTankRole end, function() return fvFury, fvFuryInst, fvFuryStale end", "=EUI_Nameplates_Colors.lua"))
    setfenv(chunk, env)
    local Sync, Verdict, State = chunk()
    W.Sync, W.Verdict, W.State = Sync, Verdict, State
    -- an event, delivered only while the watcher listens for it
    function W.Fire(event, a1, a2)
        if W.events[event] and frame and frame.handler then frame.handler(frame, event, a1, a2) end
    end
    function W.Aura(info) W.Fire("UNIT_AURA", "player", info) end
    function W.NextFrame()
        local run = W.timers
        W.timers = {}
        for _, fn in ipairs(run) do fn() end
    end
    -- combat ends: the queued work runs (the restriction is a matter of its own)
    function W.EndCombat()
        W.combat = false
        local run = W.queue
        W.queue = {}
        for _, fn in pairs(run) do fn() end
    end
    -- the aura restriction lifts, with its event, read on the next frame
    function W.Lift(silent)
        W.restricted = false
        if not silent then
            W.Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
            W.NextFrame()
        end
    end
    function W.Cost() return W.checks + W.lookups end
    return W
end
local function Gain(id, inst) return { isFullUpdate = false, addedAuras = { { spellId = id, auraInstanceID = inst } } } end
local function Loss(inst) return { isFullUpdate = false, removedAuraInstanceIDs = { inst } } end

-------------------------------------------------------------------------------
-- 1. out of combat: the verdict follows Righteous Fury, under each of its IDs
-------------------------------------------------------------------------------
for _, id in ipairs(FURY) do
    local W = Client()
    W.auras[id] = 71
    W.Sync(true)
    check(W.events.UNIT_AURA and not W.events.UPDATE_SHAPESHIFT_FORM and not W.events.ADDON_RESTRICTION_STATE_CHANGED,
        "a paladin's watcher listens to the player's auras alone")
    check(W.Verdict() == true, "Righteous Fury " .. id .. " up as the watcher arms: not the tank")
    local up, inst, stale = W.State()
    check(up == true and inst == 71 and stale == false, "the instance held: " .. tostring(inst))
    -- lost
    W.auras[id] = nil
    W.Aura(Loss(71))
    check(W.Verdict() == false and W.repaints == 1, "Righteous Fury " .. id .. " lost: still the tank, or not repainted once: " .. W.repaints)
    -- cast again
    W.auras[id] = 72
    W.Aura(Gain(id, 72))
    check(W.Verdict() == true and W.repaints == 2, "Righteous Fury " .. id .. " cast again: not the tank")
    up, inst = W.State()
    check(inst == 72, "the new instance is held")
end

-------------------------------------------------------------------------------
-- 2. an aura update is read only when it may have brought or taken it
-------------------------------------------------------------------------------
do
    local W = Client()
    W.auras[25780] = 71
    W.Sync(true)
    local cost, paints = W.Cost(), W.repaints
    W.Aura(Gain(1126, 80))                                                  -- another buff gained
    W.Aura(Loss(80))                                                        -- another buff lost
    W.Aura({ isFullUpdate = false, updatedAuraInstanceIDs = { 71 } })       -- Righteous Fury refreshed
    W.Aura({ isFullUpdate = false })
    check(W.Cost() == cost and W.repaints == paints, "an aura update that cannot have changed Righteous Fury was read: " .. (W.Cost() - cost) .. " calls")
    -- with it down, a loss of anything is nothing either
    W.auras[25780] = nil
    W.Aura(Loss(71))
    cost = W.Cost()
    W.Aura(Loss(80))
    check(W.Cost() == cost, "with Righteous Fury down a loss was read")
    -- found under its first ID: one check and one look, no more
    W.auras[25780] = 73
    cost = W.Cost()
    W.Aura(Gain(25780, 73))
    check(W.Cost() - cost == 2 and W.Verdict() == true, "a read did not stop at the ID it found: " .. (W.Cost() - cost) .. " calls")
    -- a full update, and one with no payload, read
    cost = W.Cost()
    W.Aura({ isFullUpdate = true })
    check(W.Cost() > cost, "a full update was not read")
    cost = W.Cost()
    W.Aura(nil)
    check(W.Cost() > cost, "an update with no payload was not read")
    -- an entry that cannot be read may be it
    for what, info in pairs({
        ["a secret payload"] = SECRET,
        ["a secret full-update flag"] = { isFullUpdate = SECRET },
        ["a secret list of gains"] = { isFullUpdate = false, addedAuras = SECRET },
        ["a secret gained aura"] = { isFullUpdate = false, addedAuras = { SECRET } },
        ["a gained aura with a secret spell"] = { isFullUpdate = false, addedAuras = { { spellId = SECRET } } },
        ["a secret list of losses"] = { isFullUpdate = false, removedAuraInstanceIDs = SECRET },
        ["a secret lost instance"] = { isFullUpdate = false, removedAuraInstanceIDs = { SECRET } },
    }) do
        cost = W.Cost()
        local ok, err = pcall(W.Aura, info)
        check(ok, what .. " raised: " .. tostring(err))
        check(W.Cost() > cost, what .. " was not read")
    end
end
-- held with an instance that could not be read: any loss may be it
do
    local W = Client()
    W.auras[25780] = SECRET
    W.Sync(true)
    local up, inst = W.State()
    check(up == true and inst == nil, "an instance that cannot be read is held as unknown")
    local cost = W.Cost()
    W.auras[25780] = nil
    W.Aura(Loss(80))
    check(W.Cost() > cost and W.Verdict() == false, "a loss was not read while the instance held is unknown")
end

-------------------------------------------------------------------------------
-- 3. cast in combat, where the restriction hides it: known as combat ends
-------------------------------------------------------------------------------
do
    local W = Client()
    W.Sync(true)
    check(W.Verdict() == false, "no Righteous Fury: not the tank")
    W.combat, W.restricted = true, true
    W.auras[25780] = 90
    W.Aura(SECRET)                                   -- the cast's own update, unreadable
    local up, _, stale = W.State()
    check(up == false and stale == true and W.Verdict() == false, "a refused read changed the answer or was not marked stale")
    check(W.events.ADDON_RESTRICTION_STATE_CHANGED and W.queue["np-fv-fury"] ~= nil, "a refused read in combat is not retried at its end and at the restriction's lift")
    -- the rest of the fight: its aura updates cost nothing
    local cost = W.Cost()
    for _ = 1, 50 do W.Aura(SECRET); W.Aura(Gain(1126, 80)) end
    check(W.Cost() == cost, "aura updates of the fight were read while nothing can be: " .. (W.Cost() - cost) .. " calls")
    -- combat ends, the restriction with it
    W.restricted = false
    W.EndCombat()
    check(W.Verdict() == true and W.repaints == 1, "Righteous Fury cast in combat is not known as combat ends")
    up, _, stale = W.State()
    check(stale == false and not W.events.ADDON_RESTRICTION_STATE_CHANGED, "the restriction's event stays listened to after a good read")
end
-- lost in combat: no longer the tank as combat ends
do
    local W = Client()
    W.auras[25780] = 71
    W.Sync(true)
    W.combat, W.restricted = true, true
    W.auras[25780] = nil
    W.Aura(SECRET)
    check(W.Verdict() == true, "a refused read dropped the tank verdict")
    W.restricted = false
    W.EndCombat()
    check(W.Verdict() == false and W.repaints == 1, "Righteous Fury lost in combat is still counted as combat ends")
end

-------------------------------------------------------------------------------
-- 4. the restriction lifts a moment AFTER combat ends
-------------------------------------------------------------------------------
do
    local W = Client()
    W.Sync(true)
    W.combat, W.restricted = true, true
    W.auras[25780] = 90
    W.Aura(SECRET)
    W.EndCombat()                                    -- still restricted
    local _, _, stale = W.State()
    check(W.Verdict() == false and stale == true and W.events.ADDON_RESTRICTION_STATE_CHANGED, "a retry that was refused again gave up")
    -- an addon chat restriction is no reason to read
    local cost = W.Cost()
    W.Fire("ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    W.NextFrame()
    check(W.Cost() == cost, "a chat restriction's event was read")
    -- the lift itself: read on the next frame, not inside the event
    W.restricted = false
    cost = W.Cost()
    W.Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0)
    check(W.Cost() == cost and W.Verdict() == false, "the read ran inside the restriction's own event")
    W.NextFrame()
    check(W.Verdict() == true and W.repaints == 1, "Righteous Fury is not known once the restriction lifts")
    check(not W.events.ADDON_RESTRICTION_STATE_CHANGED, "the restriction's event stays listened to")
end
-- the lift comes with no event the watcher hears: the next aura change out of combat reads
do
    local W = Client()
    W.Sync(true)
    W.combat, W.restricted = true, true
    W.auras[25780] = 90
    W.Aura(SECRET)
    W.EndCombat()
    W.Lift(true)
    check(W.Verdict() == false, "nothing has read yet")
    W.Aura(Gain(1126, 80))                           -- any aura at all
    check(W.Verdict() == true, "an aura change out of combat did not retry the refused read")
end
-- restricted with no combat at all (the watcher arms inside one): retried at the lift
do
    local W = Client()
    W.restricted = true
    W.auras[25780] = 90
    W.Sync(true)
    local _, _, stale = W.State()
    check(stale == true and W.events.ADDON_RESTRICTION_STATE_CHANGED and next(W.queue) == nil, "armed under a restriction out of combat: not waiting for its lift")
    W.Lift()
    check(W.Verdict() == true, "armed under a restriction: Righteous Fury not known at its lift")
end

-------------------------------------------------------------------------------
-- 5. each ID stands alone
-------------------------------------------------------------------------------
do
    -- an ID the client refuses to answer for does not blind the others
    local W = Client()
    W.errorIDs[407628] = true
    W.auras[25780] = 71
    W.Sync(true)
    check(W.Verdict() == true, "one ID that errors blinded the read")
    W.auras[25780] = nil
    W.Aura(Loss(71))
    local _, _, stale = W.State()
    check(W.Verdict() == false and stale == false, "with one ID erroring, a loss read by the other two is not certain")
    -- every ID refused: nothing can be said, the last answer stays
    W = Client()
    W.auras[25780] = 71
    W.Sync(true)
    for _, id in ipairs(FURY) do W.errorIDs[id] = true end
    W.auras[25780] = nil
    W.Aura(Loss(71))
    _, _, stale = W.State()
    check(W.Verdict() == true and stale == true, "with no ID answering, the read said it was down")
    -- one ID readable under the restriction and holding it: certain
    W = Client()
    W.Sync(true)
    W.combat, W.restricted = true, true
    W.openIDs[407627] = true
    W.auras[407627] = 95
    W.Aura(Gain(407627, 95))
    _, _, stale = W.State()
    check(W.Verdict() == true and stale == false, "Righteous Fury found under a readable ID was not taken as certain")
    -- one ID readable and empty, the others hidden: it cannot say
    W = Client()
    W.auras[25780] = 71
    W.Sync(true)
    W.combat, W.restricted = true, true
    W.openIDs[407627] = true
    W.Aura(SECRET)
    _, _, stale = W.State()
    check(W.Verdict() == true and stale == true, "with two IDs hidden, the read said it was down")
    -- a client with no secrecy test: the aura is read all the same, and one handed back secret is not "down"
    W = Client({ noCheck = true })
    W.auras[25780] = 71
    W.Sync(true)
    check(W.Verdict() == true and W.checks == 0, "with no secrecy test the aura was not read")
    W.combat, W.restricted = true, true
    W.auras[25780] = nil
    W.Aura(SECRET)
    _, _, stale = W.State()
    check(W.Verdict() == true and stale == true, "an aura handed back secret was taken as down")
end

-------------------------------------------------------------------------------
-- 6. the threat colors off: parked, nothing listened to, nothing read
-------------------------------------------------------------------------------
do
    local W = Client()
    W.Sync(true)
    W.combat, W.restricted = true, true
    W.Aura(SECRET)
    W.Sync(false)
    local _, _, stale = W.State()
    check(next(W.events) == nil and stale == false, "parked: an event is still listened to, or the stale mark stays")
    local cost = W.Cost()
    W.Aura(SECRET); W.Fire("ADDON_RESTRICTION_STATE_CHANGED", 1, 0); W.NextFrame(); W.restricted = false; W.EndCombat()
    check(W.Cost() == cost, "parked: something was read")
    -- armed again: read at once
    W.auras[25780] = 71
    W.Sync(true)
    check(W.Verdict() == true and W.frames == 1, "armed again: not read, or a second frame was made")
    -- the zone, roster and role pass reads it only while the watcher is armed
    check(SRC:find('    if fvTankOn then\n        if FV_TANK_CLASS == "fury" then FvFuryRead() end\n        FvReadRoleTank()\n    end\n', 1, true) ~= nil,
        "the threat cache pass reads Righteous Fury whatever the threat colors say")
end

-------------------------------------------------------------------------------
-- 7. the rest of the verdict: an assigned tank role decides alone; a warrior or
--    druid is watched for its form; every other class and client for nothing
-------------------------------------------------------------------------------
do
    local W = Client()
    W.roleTank = true
    W.auras[25780] = 71
    W.Sync(true)
    check(W.Verdict() == false, "with a tank role assigned in the group, Righteous Fury still made the paladin the tank")
    W = Client({ class = "WARRIOR" })
    W.Sync(true)
    check(W.events.UPDATE_SHAPESHIFT_FORM and not W.events.UNIT_AURA and W.Cost() == 0, "a warrior's watcher reads auras")
    W.form = true
    W.Fire("UPDATE_SHAPESHIFT_FORM")
    check(W.Verdict() == true and W.repaints == 1, "Defensive Stance did not make the warrior the tank")
    W = Client({ class = "MAGE" })
    W.Sync(true)
    check(W.frames == 0 and next(W.events) == nil, "a mage got a watcher")
    W = Client({ forever = false })
    W.auras[25780] = 71
    W.Sync(true)
    check(W.frames == 0 and W.Cost() == 0 and W.Verdict() == false, "retail got a watcher")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_np_forever_fury_tank (" .. count .. " checks)")
