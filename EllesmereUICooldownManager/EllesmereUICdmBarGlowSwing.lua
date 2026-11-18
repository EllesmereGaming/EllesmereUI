if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUICdmBarGlowSwing.lua -- WoW FOREVER ONLY: the Bar Glow swing
--  condition.
--
--    entry.swingWindow = seconds | nil (off)
--        The glow only runs during the last `swingWindow` seconds of the
--        running Main Hand swing, and not while the button's own attack is
--        already queued for it (EllesmereUI.FOREVER_NEXT_SWING, names through
--        EllesmereUI.ForeverNextSwingNames). No swing running reads as outside
--        the window. Evaluated after the entry's other conditions
--        (UpdateOverlayVisuals).
--
--  The swing comes from the module's one source (ns.CDM_Swing,
--  EUI_CDM_ForeverSwing.lua), which gives each swing's duration, so its end is
--  known when it starts: one timer per window in use re-runs the glow pass as
--  the window opens and one as the swing ends. No Lua per frame. The end is a
--  prediction: a swing the server moves (haste, a parry) shifts it. A timer of
--  an earlier swing only re-runs the pass, which starts and stops glows on
--  change alone.
--
--  Cost: nothing is watched or registered until a bound entry has the key
--  (ns.BarGlowSwingSync, called by SetupOverlays). On retail this file
--  returns right below and the key is ignored.
-------------------------------------------------------------------------------
local _, ns = ...

local Swing = ns.CDM_Swing
if not Swing then return end
local MAIN_HAND = Enum.PlayerSwingType.MainHand

local GetTime = GetTime
local C_Timer_After = C_Timer.After
local PlainString = EllesmereUI.PlainString
local NextSwingNames = EllesmereUI.ForeverNextSwingNames
local EPS = 0.01  -- a timer can fire a hair before its deadline

local on = false
local windows = {}          -- [seconds] = true, the windows bound entries use
local swingEnd              -- when the running Main Hand swing ends
local queued = false        -- the attack queued now (its name), false = none
local names = {}            -- [spellID] = spell name
local ev = ns.TakeShell()
ev:Hide()

local function Repaint()
    if ns.UpdateOverlayVisuals then ns.UpdateOverlayVisuals() end
end

local function ReadQueued()
    local list = NextSwingNames()
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

-- The entry's swing condition for an overlay. spellOf(overlay) gives the
-- button's ability; it is asked only while an attack is queued.
function ns.BarGlowSwingPass(entry, overlay, spellOf)
    local window = tonumber(entry.swingWindow)
    if not window or window <= 0 then return true end
    if not swingEnd then return false end
    local now = GetTime()
    if now >= swingEnd - EPS or now < swingEnd - window - EPS then return false end
    if queued then
        local sid = spellOf and spellOf(overlay)
        if type(sid) == "number" and not issecretvalue(sid) and SpellName(sid) == queued then
            return false
        end
    end
    return true
end

local function OnTimer()
    if on then Repaint() end
end

-- A Main Hand swing from `start` lasting `d`: the window openings and the end.
local function Arm(start, d, now)
    swingEnd = start + d
    for window in pairs(windows) do
        local t = swingEnd - window - now
        if t > 0 then C_Timer_After(t, OnTimer) end
    end
    local t = swingEnd - now
    if t > 0 then C_Timer_After(t, OnTimer) end
end

local function OnSwing(swing, now, d)
    if swing ~= MAIN_HAND then return end
    Arm(now, d, now)
    -- The swing just landed: the last one's window is over, and the attack it
    -- carried is no longer queued.
    queued = ReadQueued()
    Repaint()
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

ev:SetScript("OnEvent", function(self)
    self:Show()
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
        Swing.Watch("barglow", OnSwing)
        if NextSwingNames() ~= false then ev:RegisterEvent("ACTIONBAR_UPDATE_STATE") end
        queued = ReadQueued()
        -- A swing already running (the source kept for another reader).
        local start, d = Swing.Last(MAIN_HAND)
        local now = GetTime()
        if start and now < start + d then Arm(start, d, now) end
    else
        Swing.Unwatch("barglow")
        ev:UnregisterAllEvents()
        ev:Hide()
        swingEnd, queued = nil, false
    end
end
