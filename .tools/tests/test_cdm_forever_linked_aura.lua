-- Stub harness: Cooldown Manager, the Arcane Blast buff icon on WoW Forever
-- (EUI_CDM_ForeverLinkedAura.lua).
-- On WoW Forever the Arcane Blast buff sits on the caster as a debuff. Blizzard's buff icon
-- scans helpful auras only, so every refresh clears the icon's swipe and stack count and only
-- the linked-spell lookup at its end finds the aura again: a plain icon holding aura data
-- nothing draws. After each such refresh the file draws the swipe and the count from that
-- data; while the times are secret (combat) the swipe runs for the aura's 18 seconds from the
-- cast that applied it; a refresh in which Blizzard armed the cooldown itself is left alone.
-- Driven here: the real file, loaded whole, over an item that refreshes in the order
-- Blizzard's buff icon does (the helpful scan, the cooldown, the stack count, then the linked
-- lookup), with a clock, the player's casts and secret values.
--   lua .tools/tests/test_cdm_forever_linked_aura.lua        (from the repository root)
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
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local SRC = ReadSource("EllesmereUICooldownManager/EUI_CDM_ForeverLinkedAura.lua")

-- A secret value: a table whose index, compare, arithmetic and join raise.
local secretMT = {}
secretMT.__index = function() error("a secret value was indexed", 2) end
secretMT.__lt = function() error("a secret value was compared", 2) end
secretMT.__le = function() error("a secret value was compared", 2) end
secretMT.__add = function() error("a secret value was added", 2) end
secretMT.__sub = function() error("a secret value was subtracted", 2) end
secretMT.__concat = function() error("a secret value was joined", 2) end
local function Secret(v) return setmetatable({ __v = v }, secretMT) end
local function issecretvalue(v) return type(v) == "table" and getmetatable(v) == secretMT end

-- Blizzard's buff entries: 1001 is the Arcane Blast buff, 1002 some other buff.
local INFO = {
    [1001] = { spellID = 400574, linkedSpellIDs = { 400573 } },
    [1002] = { spellID = 12345, linkedSpellIDs = {} },
}

-- A fresh load of the file. client: { forever, class }.
local function Load(client)
    local W = { now = 100, infoCalls = 0, shells = 0, frames = 0, events = {}, active = {}, registers = 0, unregisters = 0 }
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.GetTime = function() return W.now end
    env.UnitClass = function() return "Player", client and client.class or "MAGE" end
    env.issecretvalue = issecretvalue
    env.EllesmereUI = { IS_FOREVER = not (client and client.forever == false),
                        IsSecret = function(v) return v ~= nil and issecretvalue(v) end }
    env.C_CooldownViewer = { GetCooldownViewerCooldownInfo = function(id) W.infoCalls = W.infoCalls + 1; return INFO[id] end }
    env.hooksecurefunc = function(t, name, fn)
        local orig = assert(type(t[name]) == "function" and t[name], "no such function to hook: " .. tostring(name))
        t[name] = function(...) orig(...); fn(...) end
    end
    local function EventFrame()
        local f = {}
        function f:SetScript(_, fn) W.onEvent = fn end
        function f:RegisterUnitEvent(ev, unit) W.events[ev] = unit; W.registers = W.registers + 1 end
        function f:UnregisterEvent(ev) W.events[ev] = nil; W.unregisters = W.unregisters + 1 end
        return f
    end
    -- a frame made outside the module's shell pool is counted
    env.CreateFrame = function() W.frames = W.frames + 1; return EventFrame() end
    env.BuffIconCooldownViewer = { itemFramePool = { EnumerateActive = function()
        local i = 0
        return function() i = i + 1; return W.active[i] end
    end } }
    local ns = {}
    function ns.TakeShell() W.shells = W.shells + 1; return EventFrame() end
    local chunk = assert(loadstring(SRC, "=EUI_CDM_ForeverLinkedAura.lua"))
    setfenv(chunk, env)
    chunk("EllesmereUICooldownManager", ns)
    W.ns = ns
    -- The player's cast of a spell.
    function W.Cast(id) W.onEvent(nil, "UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-GUID", id) end
    return W
end

-- A buff icon item. world.helpful: what the helpful scan finds (the aura, once Blizzard fixed
-- it); world.linked: what the linked-spell lookup finds.
local function NewItem(W, cdID)
    local cd = { sets = 0 }
    function cd:SetCooldown(s, d, r) self.start, self.dur, self.rate = s, d, r; self.sets = self.sets + 1 end
    function cd:Clear() self.start, self.dur, self.rate = nil, nil, nil end
    function cd:SetSwipeColor(_, _, _, a) self.swipe = a end
    local fs = { text = "" }
    function fs:SetText(t) self.text = t end
    local item = { cooldownID = cdID, Cooldown = cd, Applications = { Applications = fs }, shown = true, world = {} }
    function item:IsShown() return self.shown end
    function item:GetCooldownSwipeColor() return { r = 1, g = 1, b = 1, a = 0.8 } end
    function item:RefreshData()
        self.auraDataCached = self.world.helpful
        local ad = self.auraDataCached
        if ad and ad.expirationTime - W.now > 0 then
            self.Cooldown:SetCooldown(ad.expirationTime - ad.duration, ad.duration, ad.timeMod)
        else
            self.Cooldown:Clear()
        end
        self.Applications.Applications:SetText((ad and ad.applications > 1) and ad.applications or "")
        if not ad then self.auraDataCached = self.world.linked end
    end
    return item
end
local function Aura(exp, dur, apps) return { expirationTime = exp, duration = dur, timeMod = 1, applications = apps } end
local function Hidden(exp, dur, apps)
    return { expirationTime = Secret(exp), duration = Secret(dur), timeMod = Secret(1), applications = Secret(apps) }
end
local function Refresh(item)
    local ok, err = pcall(item.RefreshData, item)
    check(ok, "a refresh raised: " .. tostring(err))
end

-------------------------------------------------------------------------------
-- 1. only WoW Forever mages build anything
-------------------------------------------------------------------------------
do
    local W = Load({ forever = false })
    check(W.ns.CDM_LinkedAuraPlaced == nil and W.shells == 0, "the file built something off WoW Forever")
    W = Load({ class = "WARRIOR" })
    check(W.ns.CDM_LinkedAuraPlaced == nil and W.shells == 0, "the file built something for another class")
    W = Load()
    check(type(W.ns.CDM_LinkedAuraPlaced) == "function", "a WoW Forever mage does not get the reanchor hook")
    check(W.shells == 1 and W.frames == 0, "the cast event's frame is not one of the module's shells (" .. W.shells .. ")")
    check(next(W.events) == nil, "a cast event is heard before any Arcane Blast icon is tracked")
    -- a viewer that is not there yet is no error
    W.active = nil
    local envless = Load()
    envless.ns.CDM_LinkedAuraPlaced()
    check(next(envless.events) == nil, "an empty viewer registered the cast event")
end

-------------------------------------------------------------------------------
-- 2. the icon is hooked once; the cast event is heard only while it is tracked
-------------------------------------------------------------------------------
do
    local W = Load()
    local ab, other = NewItem(W, 1001), NewItem(W, 1002)
    W.active = { ab, other }
    local otherRefresh, abRefresh = other.RefreshData, ab.RefreshData
    W.ns.CDM_LinkedAuraPlaced()
    check(other.RefreshData == otherRefresh, "an item of another buff was hooked")
    check(ab.RefreshData ~= abRefresh, "the Arcane Blast item was not hooked")
    check(W.events.UNIT_SPELLCAST_SUCCEEDED == "player", "the player's casts are not heard while the icon is tracked")
    local hookedOnce = ab.RefreshData
    local calls = W.infoCalls
    for _ = 1, 5 do W.ns.CDM_LinkedAuraPlaced() end
    check(ab.RefreshData == hookedOnce, "a later reanchor hooked the item again")
    check(W.registers == 1 and W.unregisters == 0, "a later reanchor registered the cast event again (" .. W.registers .. ")")
    check(W.infoCalls == calls, "a later reanchor read the entry's info again (" .. (W.infoCalls - calls) .. ")")
    -- the icon leaves the bar: the casts are no longer heard; it comes back: heard again, hooked once
    W.active = { other }
    W.ns.CDM_LinkedAuraPlaced()
    check(W.events.UNIT_SPELLCAST_SUCCEEDED == nil, "the player's casts are still heard with no Arcane Blast icon tracked")
    W.active = {}
    W.ns.CDM_LinkedAuraPlaced()
    check(W.events.UNIT_SPELLCAST_SUCCEEDED == nil, "an empty bar hears the player's casts")
    W.active = { other, ab }
    W.ns.CDM_LinkedAuraPlaced()
    check(W.events.UNIT_SPELLCAST_SUCCEEDED == "player" and ab.RefreshData == hookedOnce, "the icon's return is not heard, or hooked it twice")
    check(W.registers == 2 and W.unregisters == 1, "the cast event was not registered and dropped once per change (" .. W.registers .. " / " .. W.unregisters .. ")")
    -- a pooled, hooked item bound to another buff later is left alone
    ab.cooldownID = 1002
    ab.world.linked = Aura(300, 18, 3)
    W.now = 290
    Refresh(ab)
    check(ab.Cooldown.start == nil and ab.Applications.Applications.text == "", "an item rebound to another buff was drawn")
    W.active = { ab }
    W.ns.CDM_LinkedAuraPlaced()
    check(W.events.UNIT_SPELLCAST_SUCCEEDED == nil, "an item rebound to another buff keeps the cast event")
end

-------------------------------------------------------------------------------
-- 3. plain times: the swipe and the count are drawn from the aura the icon holds
-------------------------------------------------------------------------------
do
    local W = Load()
    local ab = NewItem(W, 1001)
    W.active = { ab }
    W.ns.CDM_LinkedAuraPlaced()
    W.now = 100
    W.Cast(1239700)
    ab.world.linked = Aura(118, 18, 1)
    Refresh(ab)
    check(ab.Cooldown.start == 100 and ab.Cooldown.dur == 18 and ab.Cooldown.rate == 1, "a fresh aura is not armed 100 + 18 (" .. tostring(ab.Cooldown.start) .. ")")
    check(ab.Cooldown.swipe == 0.8, "the swipe does not take Blizzard's colour")
    check(ab.Applications.Applications.text == "", "one stack shows a count")
    -- a recast adds a stack; the game reads the time left as the duration
    W.now = 103
    W.Cast(1239700)
    ab.world.linked = Aura(118, 15, 2)
    Refresh(ab)
    check(ab.Cooldown.start == 100 and ab.Cooldown.dur == 18, "a second stack moves the swipe's start (" .. tostring(ab.Cooldown.start) .. ")")
    check(ab.Applications.Applications.text == 2, "two stacks do not show 2")
    -- Blizzard arms the cooldown itself (its fix): left alone, on that refresh only
    W.now = 104
    ab.world.helpful = Aura(118, 15, 2)
    Refresh(ab)
    check(ab.Cooldown.start == 103 and ab.Cooldown.dur == 15, "a cooldown Blizzard armed itself was drawn over")
    ab.world.helpful = nil
    W.now = 105
    Refresh(ab)
    check(ab.Cooldown.start == 100 and ab.Cooldown.dur == 18, "the next refresh Blizzard did not arm is not drawn")
    -- the aura is consumed: nothing stays armed
    W.now = 110
    ab.world.linked = nil
    Refresh(ab)
    check(ab.Cooldown.start == nil and ab.Applications.Applications.text == "", "a consumed aura keeps its swipe or count")
    -- an aura whose time has run out, and one with no duration, arm nothing
    ab.world.linked = Aura(109, 18, 1)
    Refresh(ab)
    check(ab.Cooldown.start == nil, "an aura past its end was armed")
    ab.world.linked = Aura(130, 0, 1)
    Refresh(ab)
    check(ab.Cooldown.start == nil, "an aura with no duration was armed")
end

-------------------------------------------------------------------------------
-- 4. secret times (combat): the swipe runs 18 s from the cast that applied the aura
-------------------------------------------------------------------------------
do
    local W = Load()
    local ab = NewItem(W, 1001)
    W.active = { ab }
    W.ns.CDM_LinkedAuraPlaced()
    W.now = 200
    W.Cast(400574)
    ab.world.linked = Hidden(218, 18, 1)
    W.now = 200.2
    Refresh(ab)
    check(ab.Cooldown.start == 200 and ab.Cooldown.dur == 18 and ab.Cooldown.rate == 1, "a hidden aura is not timed from its cast (" .. tostring(ab.Cooldown.start) .. ")")
    check(issecretvalue(ab.Applications.Applications.text), "a secret count does not go straight to the text")
    -- every rank of the spell applies the aura
    for _, rank in ipairs({ 400574, 1239696, 1239697, 1239699, 1239700 }) do
        local R = Load()
        local item = NewItem(R, 1001)
        R.active = { item }
        R.ns.CDM_LinkedAuraPlaced()
        R.now = 300
        R.Cast(rank)
        item.world.linked = Hidden(318, 18, 1)
        Refresh(item)
        check(item.Cooldown.start == 300, "the cast of rank " .. rank .. " does not time the aura")
    end
    -- a recast while it is up adds a stack: the start stays
    W.now = 205
    W.Cast(1239696)
    Refresh(ab)
    check(ab.Cooldown.start == 200, "a recast while the aura is up restarts the swipe")
    -- the cached aura hidden whole, and a secret spell id: no error, nothing armed
    ab.world.linked = Secret({})
    Refresh(ab)
    check(ab.Cooldown.start == nil, "an aura hidden whole was armed")
    local ok, err = pcall(W.Cast, Secret(400574))
    check(ok, "a secret cast spell id raised: " .. tostring(err))
    -- a spell that is not an Arcane Blast rank applies nothing
    ab.world.linked = nil
    W.now = 400
    Refresh(ab)
    W.now = 410
    W.Cast(1239698)
    ab.world.linked = Hidden(428, 18, 1)
    Refresh(ab)
    check(ab.Cooldown.start == nil, "another spell's cast timed the aura")
    -- past its 18 seconds, a start is not used
    ab.world.linked = nil
    Refresh(ab)
    W.now = 500
    W.Cast(400574)
    ab.world.linked = Hidden(518, 18, 1)
    W.now = 519
    Refresh(ab)
    check(ab.Cooldown.start == nil, "a swipe was armed past the aura's 18 seconds")
end

-------------------------------------------------------------------------------
-- 5. an aura consumed within a second of its cast leaves no start behind
-------------------------------------------------------------------------------
do
    local W = Load()
    local ab = NewItem(W, 1001)
    W.active = { ab }
    W.ns.CDM_LinkedAuraPlaced()
    W.now = 500
    W.Cast(400574)
    W.now = 500.3
    ab.world.linked = Hidden(518, 18, 1)
    Refresh(ab)
    check(ab.Cooldown.start == 500, "the first aura is not timed from its cast")
    W.now = 500.6           -- consumed by an instant spell, within a second of the cast
    ab.world.linked = nil
    Refresh(ab)
    W.now = 503             -- the next Arcane Blast applies a new aura
    W.Cast(400574)
    ab.world.linked = Hidden(521, 18, 1)
    W.now = 503.1
    Refresh(ab)
    check(ab.Cooldown.start == 503, "a new aura is timed from the consumed one's cast (" .. tostring(ab.Cooldown.start) .. ")")
    -- the same with the first aura hidden whole
    W = Load()
    ab = NewItem(W, 1001)
    W.active = { ab }
    W.ns.CDM_LinkedAuraPlaced()
    W.now = 600
    W.Cast(400574)
    W.now = 600.2
    ab.world.linked = Secret({})
    Refresh(ab)
    W.now = 600.5
    ab.world.linked = nil
    Refresh(ab)
    W.now = 604
    W.Cast(400574)
    ab.world.linked = Hidden(622, 18, 1)
    Refresh(ab)
    check(ab.Cooldown.start == 604, "a new aura is timed from a hidden one's cast (" .. tostring(ab.Cooldown.start) .. ")")
    -- a refresh that runs before the cast's aura is there (the cast came first) keeps the start
    W = Load()
    ab = NewItem(W, 1001)
    W.active = { ab }
    W.ns.CDM_LinkedAuraPlaced()
    W.now = 700
    W.Cast(400574)
    W.now = 700.1
    Refresh(ab)             -- the aura has not arrived yet
    W.now = 700.3
    ab.world.linked = Hidden(718, 18, 1)
    Refresh(ab)
    check(ab.Cooldown.start == 700, "a refresh ahead of the aura dropped its cast's start (" .. tostring(ab.Cooldown.start) .. ")")
    -- an aura that went while its icon showed another buff (no refresh of the entry saw it
    -- go): the next cast starts clean, so the look the cast itself takes keeps the new start
    W = Load()
    ab = NewItem(W, 1001)
    W.active = { ab }
    W.ns.CDM_LinkedAuraPlaced()
    W.now = 1100
    W.Cast(400574)
    ab.world.linked = Hidden(1118, 18, 1)
    Refresh(ab)
    check(ab.Cooldown.start == 1100, "the first aura is not timed from its cast")
    ab.cooldownID = 1002    -- the pooled item shows another buff, with no aura of its own
    ab.world.linked = nil
    Refresh(ab)
    ab.cooldownID = 1001    -- and the Arcane Blast buff again
    W.now = 1120            -- 20 s on: the old aura is long over
    W.Cast(400574)
    W.now = 1120.3
    ab.world.linked = Hidden(1138, 18, 1)
    Refresh(ab)
    check(ab.Cooldown.start == 1120, "a new cast is judged by the last aura's mark (" .. tostring(ab.Cooldown.start) .. ")")
    -- with no aura for more than a second after a cast, the start is dropped
    W = Load()
    ab = NewItem(W, 1001)
    W.active = { ab }
    W.ns.CDM_LinkedAuraPlaced()
    W.now = 800
    W.Cast(400574)          -- resisted: no aura follows
    W.now = 801.5
    Refresh(ab)
    W.now = 810
    ab.world.linked = Hidden(828, 18, 1)
    Refresh(ab)
    check(ab.Cooldown.start == nil, "an aura with no known cast was timed from an older one")
end

-------------------------------------------------------------------------------
-- 6. a cast draws at once on a shown icon, as the aura's own refresh may already have run
-------------------------------------------------------------------------------
do
    local W = Load()
    local ab = NewItem(W, 1001)
    W.active = { ab }
    W.ns.CDM_LinkedAuraPlaced()
    W.now = 900
    ab.world.linked = Hidden(918, 18, 1)
    Refresh(ab)             -- the aura's refresh runs first: no start is known yet
    check(ab.Cooldown.start == nil, "an aura with no known cast was armed")
    W.Cast(400574)
    check(ab.Cooldown.start == 900 and ab.Cooldown.dur == 18, "the cast does not draw the icon at once")
    -- a hidden icon is left alone
    W = Load()
    ab = NewItem(W, 1001)
    W.active = { ab }
    W.ns.CDM_LinkedAuraPlaced()
    ab.shown = false
    ab.auraDataCached = Hidden(1018, 18, 1)
    W.now = 1000
    W.Cast(400574)
    check(ab.Cooldown.start == nil, "the cast drew an icon that is not shown")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_cdm_forever_linked_aura (%d checks)"):format(count))
