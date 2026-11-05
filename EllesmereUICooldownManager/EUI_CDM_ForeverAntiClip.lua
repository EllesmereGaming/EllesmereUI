if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_ForeverAntiClip.lua -- WoW FOREVER ONLY: the Anti-Clip Glow.
--
--  Vanilla auras carry no time over on a refresh: a DoT cast again before it
--  runs out loses the ticks it had left, and Blizzard never opens a pandemic
--  window for it. So on Forever a bar's Pandemic Glow is the anti-clip glow: an
--  aura lights while casting its spell as your next action -- after your
--  current cast or channel and the GCD -- would land it at or after the running
--  one's expiry. The bars keep their Pandemic Glow keys and drawing (icons: the
--  buff ticker in EUI_CDM_HookViewers.lua; Tracking Bars: EUI_CDM_BuffBarTick.lua);
--  only the trigger lives here, reached through the nil-guarded ns.CDM_AntiClip,
--  ns.CDM_AntiClipPlaced (after every reanchor), ns.CDM_AntiClipSync (end of
--  every full rebuild) and ns.CDM_AntiClipBars (the Tracking Bars build).
--
--  The expiry is the item's own, read by ns.ReadAuraExpiration (Also Show Below
--  N Seconds reads it the same way): a time that reads secret lights nothing.
--  The cast time is the tracked spell's own (talents included), so an instant
--  lights only once the aura would run out before you are free, and nothing
--  lights while you are casting the spell itself. An input that cannot be read
--  counts as "free now" or "instant", which can only light the glow later.
--
--  Event-driven, probing the delta: the player's cast events say when the
--  current cast and the GCD end, and on those edges (and on cast-time changes
--  and the one idle-wait timer) only the icons the buff ticker last drew are
--  re-checked, the ticker woken only when one of them flips. An item's own aura
--  edges (a post-hook on CheckSetPandemicAlertTriggerTime, which Blizzard calls
--  on every application, refresh and removal) re-check it the same way, and
--  every reanchor wakes the ticker for the icons it placed.
--  Tracking Bars read the verdict on their own tick. Nothing is registered while
--  no bar uses the glow, and the aura-edge hooks then return at once.
-------------------------------------------------------------------------------
local _, ns = ...
-- WoW Forever (ns.CDM_ANTI_CLIP, EllesmereUICooldownManager.lua).
if not ns.CDM_ANTI_CLIP then return end

local GetTime = GetTime
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local PlainString = EllesmereUI.PlainString
local ReadExpiration = ns.ReadAuraExpiration
local GCD_SPELL = 61304
local HUGE = math.huge
local EMPTY = {}

local armed = false
local wantIcons, wantBars = false, false
local castEnd, gcdEnd = 0, 0            -- GetTime() at which the current cast / GCD ends
local castName                          -- the spell being cast or channelled (plain reads)
local castTimes = {}                    -- [spellID] = cast time in seconds (plain reads)
local names = {}                        -- [spellID] = spell name (plain reads)
local state = setmetatable({}, { __mode = "k" })    -- [icon item] = its last drawn verdict
local hooked = setmetatable({}, { __mode = "k" })
local nextWake = HUGE                   -- the earliest pending idle wake
local ev = ns.TakeShell()

local function Wake()
    ns._btDirty = true
    if ns.ArmBuffTicker then ns.ArmBuffTicker() end
end

local function SpellName(sid)
    local n = names[sid]
    if n then return n end
    n = PlainString(C_Spell.GetSpellName(sid))
    if n then names[sid] = n end
    return n
end

-- Cast time in seconds of a spell as the client reads it for you now (0 for an
-- instant). Cached; dropped when spells, talents, gear or haste change.
local function CastTime(sid)
    local c = castTimes[sid]
    if c then return c end
    local info = C_Spell.GetSpellInfo(sid)
    local ms = info and info.castTime
    if type(ms) ~= "number" or issecretvalue(ms) then return 0 end
    c = ms > 0 and ms / 1000 or 0
    castTimes[sid] = c
    return c
end

-- When the current cast or channel ends (0 while none) and which spell it is.
local function ReadCast()
    local _, _, _, _, e, _, _, _, sid = UnitCastingInfo("player")
    if type(e) ~= "number" or issecretvalue(e) then
        _, _, _, _, e, _, _, sid = UnitChannelInfo("player")
    end
    if type(e) == "number" and not issecretvalue(e) then
        castEnd = e / 1000
        castName = (type(sid) == "number" and not issecretvalue(sid)) and SpellName(sid) or nil
    else
        castEnd, castName = 0, nil
    end
end

-- When the running GCD ends; 0 while none runs (or it reads secret).
local function ReadGCD()
    local cd = C_Spell.GetSpellCooldown(GCD_SPELL)
    local s, d = cd and cd.startTime, cd and cd.duration
    if type(s) == "number" and type(d) == "number" and not issecretvalue(s)
       and not issecretvalue(d) and d > 0 then
        gcdEnd = s + d
    else
        gcdEnd = 0
    end
end

-- The verdict for one aura item now: true while casting its spell as your next
-- action would land it at or after the running aura's expiry. A false verdict
-- also returns the moment an idle wait would turn it on.
local function Evaluate(frame, now)
    local exp, rate = ReadExpiration(frame)
    if not exp then return false end
    -- The tracked spell is the one you cast (an aura's own id can differ: retail
    -- Immolate casts 348 and applies 157736); the aura's id stands in until resolved.
    local fc = ns._ecmeFC[frame]
    local sid = fc and fc.resolvedSid
    if type(sid) ~= "number" or sid <= 0 then
        -- A totem item's expiry came from its totem data, so the cached aura
        -- is unchecked here and may be a secret table (no index on one).
        local d = frame.auraDataCached
        sid = nil
        if not issecretvalue(d) and d then sid = d.spellId end
    end
    local plain = type(sid) == "number" and not issecretvalue(sid)
    -- Casting the spell itself refreshes the aura: nothing to queue.
    if castName and plain and castName == SpellName(sid) then return false end
    local c = plain and CastTime(sid) or 0
    local free = now
    if castEnd > free then free = castEnd end
    if gcdEnd > free then free = gcdEnd end
    if (exp - now) / rate <= (free - now) + c then return true end
    -- Free from `free` on, it turns on once the aura's time left fits the cast.
    local t = exp - c * rate
    if t < free then t = free end
    return false, t
end

local Probe

-- A wake already superseded by an earlier one that ran stays quiet.
local function WakeDue()
    if GetTime() + 0.01 < nextWake then return end
    nextWake = HUGE
    Probe()
end

local function Schedule(t, now)
    if t < nextWake then
        nextWake = t
        C_Timer.After(t - now + 0.02, WakeDue)
    end
end

-- Re-check only the icons the buff ticker last drew; wake it only when one of
-- them flips (the ticker redraws it and stores the new verdict).
Probe = function()
    local now = GetTime()
    local flipped = false
    for frame, was in pairs(state) do
        if frame:IsShown() then
            local on, t = Evaluate(frame, now)
            if on ~= was then flipped = true end
            if t then Schedule(t, now) end
        else
            state[frame] = nil
        end
    end
    if flipped then Wake() end
end

-- An item's aura changed: re-check the icons drawn, or let the ticker draw one
-- it has not drawn yet.
local function OnAuraEdge(frame)
    if not armed then return end
    if state[frame] == nil then Wake() else Probe() end
end

-- After every reanchor (icons joined or left the bars, an aura's first
-- activation among them): let the ticker draw the icons it has not drawn yet.
function ns.CDM_AntiClipPlaced()
    if armed then Wake() end
end

-- The GCD a cast starts can land a moment after the cast's own event.
local function Reread()
    local wasCast, wasGcd = castEnd, gcdEnd
    ReadCast(); ReadGCD()
    if castEnd ~= wasCast or gcdEnd ~= wasGcd then Probe() end
end

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_CHANNEL_UPDATE",
}
-- Everything that can change a spell's cast time: spells, talents (Forever's
-- run on traits), gear and haste.
local CAST_TIME_EVENTS = {
    "SPELLS_CHANGED", "TRAIT_CONFIG_UPDATED", "CHARACTER_POINTS_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED",
}

ev:SetScript("OnEvent", function(_, event)
    if event == "UNIT_SPELL_HASTE" or event == "SPELLS_CHANGED" or event == "TRAIT_CONFIG_UPDATED"
       or event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        wipe(castTimes)
    else
        ReadCast(); ReadGCD()
        if gcdEnd <= GetTime() and (event == "UNIT_SPELLCAST_START"
           or event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_CHANNEL_START") then
            C_Timer.After(0.05, Reread)
        end
    end
    Probe()
end)

local function SetArmed(want)
    if want == armed then return end
    armed = want
    if want then
        for i = 1, #CAST_EVENTS do ev:RegisterUnitEvent(CAST_EVENTS[i], "player") end
        for i = 1, #CAST_TIME_EVENTS do ev:RegisterEvent(CAST_TIME_EVENTS[i]) end
        ev:RegisterUnitEvent("UNIT_SPELL_HASTE", "player")
        ReadCast(); ReadGCD()
    else
        ev:UnregisterAllEvents()
        castEnd, gcdEnd, castName = 0, 0, nil
        wipe(castTimes)
        wipe(state)
    end
    -- The next pass lights or takes down the glows under the new state.
    Wake()
end

-- End of every full rebuild (options, profile and spec swaps): does any enabled
-- bar draw the glow? Blizzard Default (-1) has no anti-clip look, so it draws
-- none. The glows are drawn again under the new settings.
function ns.CDM_AntiClipSync()
    local p = ns.ECME and ns.ECME.db and ns.ECME.db.profile
    local bars = p and p.cdmBars and p.cdmBars.bars
    local want = false
    for _, bd in ipairs(bars or EMPTY) do
        if bd.enabled and bd.pandemicGlow and (bd.pandemicGlowStyle or 1) ~= -1 then
            want = true
            break
        end
    end
    wantIcons = want
    wipe(state)
    if armed == (wantIcons or wantBars) then
        if armed then Wake() end
    else
        SetArmed(wantIcons or wantBars)
    end
end

-- The Tracking Bars build: does any enabled Tracking Bar draw the glow?
function ns.CDM_AntiClipBars(want)
    wantBars = want and true or false
    SetArmed(wantIcons or wantBars)
end

-- The verdict for one Blizzard Cooldown Manager aura item. wake: the buff
-- ticker's call (icons), which hooks the item's aura edges, stores the verdict
-- the cast edges re-check and asks for a wake at the moment an idle wait would
-- turn it on; the Tracking Bars tick needs none of that.
function ns.CDM_AntiClip(frame, wake)
    if not armed then return false end
    local now = GetTime()
    local on, t = Evaluate(frame, now)
    if wake then
        if not hooked[frame] and frame.CheckSetPandemicAlertTriggerTime then
            hooked[frame] = true
            hooksecurefunc(frame, "CheckSetPandemicAlertTriggerTime", OnAuraEdge)
        end
        state[frame] = on
        if t then Schedule(t, now) end
    end
    return on
end
