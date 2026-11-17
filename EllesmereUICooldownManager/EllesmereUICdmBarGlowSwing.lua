if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICdmBarGlowSwing.lua -- WoW FOREVER ONLY: the Bar Glow swing
--  condition.
--
--    entry.swingWindow = seconds | nil (off)
--        The glow only runs during the last `swingWindow` seconds of the
--        running Main Hand swing, and not while the button's own attack is
--        already queued for it (EllesmereUI.FOREVER_NEXT_SWING). No swing
--        running reads as outside the window. Evaluated after the entry's
--        other conditions (UpdateOverlayVisuals).
--
--  PLAYER_SWING gives each swing's duration, so its end is known when it
--  starts: one timer per window in use re-runs the glow pass as the window
--  opens and one as the swing ends. No Lua per frame. The end is a
--  prediction: a swing the server moves (haste, a parry) shifts it.
--
--  Cost: nothing is registered until a bound entry has the key
--  (ns.BarGlowSwingSync, called by SetupOverlays). On retail this file
--  returns right below and the key is ignored.
-------------------------------------------------------------------------------
local _, ns = ...

local SWING = Enum.PlayerSwingType
if not (C_SwingTimer and SWING) then return end

local GetTime = GetTime
local C_Timer_After = C_Timer.After
local PlainString = EllesmereUI.PlainString
local EPS = 0.01  -- a timer can fire a hair before its deadline

local on = false
local windows = {}          -- [seconds] = true, the windows bound entries use
local swingEnd              -- when the running Main Hand swing ends
local swingGen = 0          -- timers of an earlier swing do nothing
local queueNames            -- the class's on-next-swing attack names, false = none
local queued = false        -- the attack queued now (its name), false = none
local names = {}            -- [spellID] = spell name
local ev = ns.TakeShell()
ev:Hide()

local function Repaint()
    if ns.UpdateOverlayVisuals then ns.UpdateOverlayVisuals() end
end

local function QueueNames()
    if queueNames ~= nil then return queueNames end
    local _, classFile = UnitClass("player")
    local ids = EllesmereUI.FOREVER_NEXT_SWING and EllesmereUI.FOREVER_NEXT_SWING[classFile]
    if not (ids and C_Spell.IsCurrentSpell) then
        queueNames = false
        return false
    end
    local list = {}
    for i = 1, #ids do
        local n = PlainString(C_Spell.GetSpellName(ids[i]))
        if not n then return nil end  -- not loaded yet: asked again next time
        list[#list + 1] = n
    end
    queueNames = list
    return list
end

local function ReadQueued()
    local list = QueueNames()
    if not list then return false end
    for i = 1, #list do
        local cur = C_Spell.IsCurrentSpell(list[i])
        if not issecretvalue(cur) and cur then return list[i] end
    end
    return false
end

local function SpellName(sid)
    local n = names[sid]
    if n then return n end
    n = PlainString(C_Spell.GetSpellName(sid))
    if n then names[sid] = n end
    return n
end

-- The entry's swing condition for the button's ability `sid` (nil = none known).
function ns.BarGlowSwingPass(entry, sid)
    local window = tonumber(entry.swingWindow)
    if not window or window <= 0 then return true end
    if not swingEnd then return false end
    local now = GetTime()
    if now >= swingEnd - EPS or now < swingEnd - window - EPS then return false end
    if queued and type(sid) == "number" and not issecretvalue(sid) and SpellName(sid) == queued then
        return false
    end
    return true
end

local function OnTimer(gen)
    if gen == swingGen and on then Repaint() end
end

-- ACTIONBAR_UPDATE_STATE storms in combat: bursts fold into one read on the
-- next frame, which repaints only when the queued attack changed.
ev:SetScript("OnUpdate", function(self)
    self:Hide()
    local q = ReadQueued()
    if q == queued then return end
    queued = q
    Repaint()
end)

ev:SetScript("OnEvent", function(self, event, dur, swing)
    if event ~= "PLAYER_SWING" then
        self:Show()
        return
    end
    if issecretvalue(dur) or issecretvalue(swing) or swing ~= SWING.MainHand then return end
    if type(dur) ~= "number" or dur ~= dur or dur <= 0 or dur == math.huge then return end
    swingEnd = GetTime() + dur
    swingGen = swingGen + 1
    local gen = swingGen
    for window in pairs(windows) do
        if window < dur then
            C_Timer_After(dur - window, function() OnTimer(gen) end)
        end
    end
    C_Timer_After(dur, function() OnTimer(gen) end)
    -- The swing just landed: the last one's window is over, and the attack it
    -- carried is no longer queued.
    queued = ReadQueued()
    Repaint()
end)

-- SetupOverlays: the windows bound entries use (a set of seconds), or nil for none.
function ns.BarGlowSwingSync(used)
    wipe(windows)
    if used then
        for window in pairs(used) do windows[window] = true end
    end
    local want = next(windows) ~= nil
    if want == on then return end
    on = want
    if on then
        ev:RegisterEvent("PLAYER_SWING")
        if QueueNames() ~= false then ev:RegisterEvent("ACTIONBAR_UPDATE_STATE") end
        queued = ReadQueued()
    else
        ev:UnregisterAllEvents()
        ev:Hide()
        swingEnd, queued = nil, false
        swingGen = swingGen + 1
    end
end
