if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnitFrames_Engine.lua
--
--  The unit-frame update engine: event routing and repaint scheduling for the
--  single-unit frames (player/target/focus/pet/tot/fot/boss1-5). Owns NOTHING
--  visual -- painters live in EllesmereUIUnitFrames.lua and are registered per
--  channel; this file decides only WHO gets painted and WHEN.
--
--  Design rules:
--  - One tracker frame per unit token, created once, events registered via
--    RegisterUnitEvent so the client filters delivery C-side. Tokens are fixed
--    for the session; nothing ever re-registers.
--  - Vehicle handling is done at REGISTRATION, not remap time: the player
--    frame's tracker registers every unit event for BOTH "player" and
--    "vehicle", the pet frame's for both "pet" and "player". Painters read
--    frame._euiUnit (the live token) at paint time, so a vehicle swap needs no
--    event surgery at all.
--  - targettarget/focustarget have no unit events; ONE shared 0.5s ticker
--    repaints them (value channels every tick, identity channels only when
--    the GUID actually changed). The ticker frame is hidden -- and therefore
--    completely idle -- whenever neither frame is shown.
--  - Same-frame dedupe: each (frame, channel) paint is stamped with a global
--    generation + GetTime pair; stacked triggers inside one frame collapse to
--    one paint.
-------------------------------------------------------------------------------

local ADDON_NAME, ns = ...
local EllesmereUI = _G.EllesmereUI
if not EllesmereUI then return end

local issecretvalue = _G.issecretvalue
local UnitExists, UnitGUID, GetTime = UnitExists, UnitGUID, GetTime
local CreateFrame = CreateFrame

local Engine = {}
ns.Engine = Engine

-------------------------------------------------------------------------------
--  Painter registry: channel -> fn(frame, unit, event). Registered once by the
--  main file. A channel with no painter is simply never scheduled.
-------------------------------------------------------------------------------
local painters = {}

function Engine.SetPainter(channel, fn)
    painters[channel] = fn
end

-------------------------------------------------------------------------------
--  Channel -> unit events. This mirrors the exact event set the old element
--  wiring listened to, so update timing is indistinguishable to the user.
--  (health carries connection/faction; text rides health+power+name/level;
--  absorb covers both absorb kinds plus heal prediction.)
-------------------------------------------------------------------------------
local CHANNEL_EVENTS = {
    -- UNIT_MAX_HEALTH_MODIFIERS_CHANGED rides health/text: modifier changes can
    -- move the value and effective max with no UNIT_HEALTH/UNIT_MAXHEALTH behind
    -- them (Blizzard's own unit frames repaint health from this event).
    health   = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_CONNECTION", "UNIT_FACTION",
                 "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" },
    power    = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_POWER_BAR_SHOW", "UNIT_POWER_BAR_HIDE", "UNIT_CONNECTION" },
    -- UNIT_AURA deliberately absent here too: absorb VALUE changes already
    -- ride the two absorb events below, so the long-form Absorb / Heal Absorb
    -- text zones only go stale on the no-event timer-expiry class -- and the
    -- armed belt's disarm edge (ns.UF_AbDisarm) recomposes text once at
    -- exactly that moment. (The "Short" variants ride the Override's
    -- _absGate lockstep instead, which the absorb channel already covers.)
    text     = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
                 "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_CONNECTION",
                 "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
                 "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" },
    -- (UNIT_HEAL_PREDICTION deliberately absent: the absorb painter never
    -- rendered incoming heals and early-returned on it; not delivering it at
    -- all is the same behavior for less dispatch.)
    -- UNIT_AURA deliberately absent (Blizzard parity): the timer-expiry
    -- shield with no event at all (VDH Infernal Strike field class) is
    -- covered by the armed-frames belt in the main file (ns.UF_AbArm), not
    -- by riding the chattiest event in the game. Raid Frames uses the same
    -- belt design. UNIT_HEALTH deliberately absent too: the absorb painter
    -- reads amounts/max/sizes but never current health -- the overlays are
    -- clip-anchored to the health texture edge, which the client moves for
    -- free (Blizzard's CUF needs health-driven prediction repaints only
    -- because its bars compute widths in Lua). Max range changes still ride
    -- UNIT_MAXHEALTH; the event-less shield clear rides the belt.
    absorb   = { "UNIT_MAXHEALTH",
                 "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
                 "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" },
    portrait = { "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CONNECTION" },
}

-- Events consumed by the castbar channel; routed raw (event identity matters
-- to the painter), never deduped -- a STOP and a START in one frame are both
-- real.
local CASTBAR_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_INTERRUPTIBLE",
    "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
}

-------------------------------------------------------------------------------
--  Castbar driver. Owns the cast state machine for frame.Castbar and calls
--  the bar's Post* hooks with the same shapes the old element wiring used, so
--  every existing hook runs unchanged. The bar itself stays hidden while
--  idle, and its OnUpdate only exists to serve the time text and the
--  post-interrupt hold -- the fill animation is engine-driven through
--  SetTimerDuration (secret-safe by construction; Lua never reads the clock).
--
--  Event payload note: 12.1 delivers the cast identifier used for
--  cross-checking at the FOURTH event argument (and interrupt/empower stops
--  carry their extras before it); the positional reads below mirror the
--  field-proven live behavior exactly.
-------------------------------------------------------------------------------
do
    local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
    local FALLBACK_ICON = 136243

    local function ResetCastState(element)
        element.casting, element.channeling, element.empowering = nil, nil, nil
        element.notInterruptible, element.spellID, element.castID = nil, nil, nil
        element.spellName = nil
        -- Empower stage pips outlive the cast otherwise (the old element
        -- wiring hid them in its reset).
        if element.Pips then
            for _, pip in next, element.Pips do pip:Hide() end
        end
    end

    local function CastOnUpdate(self, elapsed)
        if self.casting or self.channeling or self.empowering then
            if self.Time then
                local durationObject = self:GetTimerDuration()
                if durationObject then
                    if (self.delay or 0) ~= 0 then
                        if self.CustomDelayText then
                            self:CustomDelayText(durationObject)
                        else
                            self.Time:SetFormattedText("%.1f|cffff0000%s%.2f|r",
                                durationObject:GetRemainingDuration(),
                                self.channeling and "-" or "+", self.delay)
                        end
                    elseif self.CustomTimeText then
                        self:CustomTimeText(durationObject)
                    else
                        self.Time:SetFormattedText("%.1f", durationObject:GetRemainingDuration())
                    end
                end
            end
        elseif (self.holdTime or 0) > 0 then
            self.holdTime = self.holdTime - elapsed
        else
            ResetCastState(self)
            self:Hide()
        end
    end

    -- Full (re)derivation of the current cast: real cast-start events and
    -- every identity repaint (target swap, show, force) land here, matching
    -- the old full-update behavior on those paths.
    local function StartCast(frame, element, unit, event)
        local direction = Enum.StatusBarTimerDirection.ElapsedTime
        local duration
        local name, text, texture, startTime, endTime, isTradeSkill, _, notInterruptible, spellID, castID =
            UnitCastingInfo(unit)
        if name then
            element.casting = true
            element.channeling, element.empowering = nil, nil
            duration = UnitCastingDuration(unit)
        else
            local isEmpowered
            name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellID, isEmpowered, _, castID =
                UnitChannelInfo(unit)
            if isEmpowered then
                element.empowering = true
                element.casting, element.channeling = nil, nil
                duration = UnitEmpoweredChannelDuration(unit)
            else
                element.channeling = true
                element.casting, element.empowering = nil, nil
                duration = UnitChannelDuration(unit)
                direction = Enum.StatusBarTimerDirection.RemainingTime
            end
        end

        if not name or (isTradeSkill and element.hideTradeSkills) then
            -- A target swap during the post-interrupt hold keeps the hold on
            -- screen; anything else clears the bar outright.
            if not (event == "PLAYER_TARGET_CHANGED" and (element.holdTime or 0) > 0) then
                ResetCastState(element)
                element:Hide()
            end
            return
        end

        element.delay = 0
        element.holdTime = 0
        element.notInterruptible = notInterruptible
        element.castID = castID
        element.spellID = spellID
        element.spellName = text

        if unit == "player" then
            -- Cast clock endpoints are only readable for the player.
            element.startTime = startTime / 1000
            if element.empowering then
                element.endTime = (endTime + GetUnitEmpowerHoldAtMaxTime(unit)) / 1000
            else
                element.endTime = endTime / 1000
            end
        end

        element:SetTimerDuration(duration, element.smoothing, direction)

        if element.Icon then element.Icon:SetTexture(texture or FALLBACK_ICON) end
        if element.Spark then element.Spark:Show() end
        if element.Text then element.Text:SetText(text) end
        if element.Time then element.Time:SetText() end

        local safeZone = element.SafeZone
        if safeZone and unit == "player" then
            local isHoriz = element:GetOrientation() == "HORIZONTAL"
            safeZone:ClearAllPoints()
            safeZone:SetPoint(isHoriz and "TOP" or "LEFT")
            safeZone:SetPoint(isHoriz and "BOTTOM" or "RIGHT")
            if element.channeling then
                safeZone:SetPoint(element:GetReverseFill() and (isHoriz and "RIGHT" or "TOP")
                    or (isHoriz and "LEFT" or "BOTTOM"))
            else
                safeZone:SetPoint(element:GetReverseFill() and (isHoriz and "LEFT" or "BOTTOM")
                    or (isHoriz and "RIGHT" or "TOP"))
            end
            local zoneEnd = endTime
            if element.empowering then zoneEnd = zoneEnd + GetUnitEmpowerHoldAtMaxTime(unit) end
            local ratio = (select(4, GetNetStats())) / (zoneEnd - startTime)
            if ratio > 1 then ratio = 1 end
            safeZone[isHoriz and "SetWidth" or "SetHeight"](safeZone,
                element[isHoriz and "GetWidth" or "GetHeight"](element) * ratio)
        end

        if element.empowering and element.UpdatePips then
            element:UpdatePips(UnitEmpoweredStagePercentages(unit))
        end

        if element.PostCastStart then element:PostCastStart(unit) end
        element:Show()
    end

    local function UpdateCast(frame, element, unit, event, castID)
        if not element:IsShown() or not castID or element.castID ~= castID then return end
        local direction = Enum.StatusBarTimerDirection.ElapsedTime
        local duration, name, startTime, _
        if event == "UNIT_SPELLCAST_DELAYED" then
            name, _, _, startTime = UnitCastingInfo(unit)
            duration = UnitCastingDuration(unit)
        else
            name, _, _, startTime = UnitChannelInfo(unit)
            if event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
                duration = UnitEmpoweredChannelDuration(unit)
            else
                duration = UnitChannelDuration(unit)
                direction = Enum.StatusBarTimerDirection.RemainingTime
            end
        end
        if not name then return end
        if unit == "player" then
            -- Delay accumulates only for the player (readable clock).
            startTime = startTime / 1000
            local delta
            if element.channeling then
                delta = element.startTime - startTime
            else
                delta = startTime - element.startTime
            end
            if delta < 0 then delta = 0 end
            element.delay = (element.delay or 0) + delta
        end
        element:SetTimerDuration(duration, element.smoothing, direction)
        if element.PostCastUpdate then element:PostCastUpdate(unit) end
    end

    local function StopCast(frame, element, unit, event, a, b, c)
        local castID, interruptedBy, empowerComplete
        if event == "UNIT_SPELLCAST_STOP" then
            castID = a
        elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
            empowerComplete, interruptedBy, castID = a, b, c
        else -- UNIT_SPELLCAST_CHANNEL_STOP
            interruptedBy, castID = a, b
        end
        if not element:IsShown() or not castID or element.castID ~= castID then return end
        if element.Spark then element.Spark:Hide() end
        if interruptedBy then
            if element.Text then element.Text:SetText(INTERRUPTED) end
            element.holdTime = element.timeToHold or 0
            element:SetMinMaxValues(0, 1)
            element:SetValue(1)
            if element.PostCastInterrupted then element:PostCastInterrupted(unit, interruptedBy) end
        else
            if element.PostCastStop then element:PostCastStop(unit, empowerComplete) end
        end
        ResetCastState(element)
    end

    local function FailCast(frame, element, unit, event, a, b)
        local castID, interruptedBy
        if event == "UNIT_SPELLCAST_INTERRUPTED" then
            interruptedBy, castID = a, b
        else -- UNIT_SPELLCAST_FAILED
            castID = a
        end
        if not element:IsShown() or not castID or element.castID ~= castID then return end
        if element.Text then
            element.Text:SetText(event == "UNIT_SPELLCAST_FAILED" and FAILED or INTERRUPTED)
        end
        if element.Spark then element.Spark:Hide() end
        element.holdTime = element.timeToHold or 0
        element:SetMinMaxValues(0, 1)
        element:SetValue(1)
        if interruptedBy then
            if element.PostCastInterrupted then element:PostCastInterrupted(unit, interruptedBy) end
        else
            if element.PostCastFail then element:PostCastFail(unit) end
        end
        ResetCastState(element)
    end

    -- The castbar channel painter. Real events arrive as
    -- (frame, unit, event, eventUnit, e2, e3, e4, e5, e6): the cast
    -- identifier the handlers cross-check sits at event argument FOUR, with
    -- the interrupt/empower extras leading it -- the positions the live
    -- behavior is proven against. Identity repaints arrive with pseudo-event
    -- names and re-derive the current cast in full.
    local function CastbarPainter(frame, unit, event, _, e2, e3, e4, e5, e6)
        local element = frame.Castbar
        if not element then return end
        if not Engine.ElementOn(frame, "Castbar") then return end
        if not element._euiCastDriver then
            element._euiCastDriver = true
            -- One-time per-element state the old wiring seeded on enable:
            -- the pip registry (the module's UpdatePips indexes it, and an
            -- empower cast crashed StartCast before PostCastStart without
            -- it -- taking the icon/text/target updates down with it).
            element.Pips = element.Pips or {}
            element:SetScript("OnUpdate", CastOnUpdate)
        end
        if event == "UNIT_SPELLCAST_START"
            or event == "UNIT_SPELLCAST_CHANNEL_START"
            or event == "UNIT_SPELLCAST_EMPOWER_START" then
            StartCast(frame, element, unit, event)
        elseif event == "UNIT_SPELLCAST_DELAYED"
            or event == "UNIT_SPELLCAST_CHANNEL_UPDATE"
            or event == "UNIT_SPELLCAST_EMPOWER_UPDATE" then
            UpdateCast(frame, element, unit, event, e4)
        elseif event == "UNIT_SPELLCAST_STOP"
            or event == "UNIT_SPELLCAST_CHANNEL_STOP"
            or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
            StopCast(frame, element, unit, event, e4, e5, e6)
        elseif event == "UNIT_SPELLCAST_FAILED"
            or event == "UNIT_SPELLCAST_INTERRUPTED" then
            FailCast(frame, element, unit, event, e4, e5)
        elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE"
            or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
            if not element:IsShown() then return end
            element.notInterruptible = event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE"
            if element.PostCastInterruptible then element:PostCastInterruptible(unit) end
        else
            -- Pseudo-event (Show/ForceUpdate/target swap): full re-derive.
            StartCast(frame, element, unit, event)
        end
    end
    Engine.SetPainter("castbar", CastbarPainter)
end

-------------------------------------------------------------------------------
--  Attached frames + trackers
-------------------------------------------------------------------------------
local attached = {}      -- frame -> { unit = token, channels = { name, ... } }
local trackers = {}      -- primary token -> tracker frame
local unitFrames = {}    -- primary token -> frame (1:1 for our layout)

-- Which secondary token shares a frame's events (vehicle design, see header).
local SECONDARY_TOKEN = { player = "vehicle", pet = "player" }

-- Paint stamping: one generation per hardware frame is enough to collapse
-- stacked same-frame triggers without ever suppressing a later real change.
local paintGen = 0
local lastGenTime = 0

local function Bump()
    local now = GetTime()
    if now ~= lastGenTime then
        paintGen = paintGen + 1
        lastGenTime = now
    end
    return paintGen
end

-- Identity edges are never eaten by a same-frame value paint: painters may
-- skip identity-only work (the text painter's name/level zones) on value
-- events, so an identity event landing after a value paint in the same
-- hardware frame must still reach the painter (RepaintAll wipes the stamps
-- for the same reason).
local IDENTITY_EVENTS = {
    UNIT_NAME_UPDATE = true, UNIT_LEVEL = true, UNIT_CONNECTION = true, UNIT_FACTION = true,
}

local function Paint(frame, channel, event)
    local fn = painters[channel]
    if not fn then return end
    local gen = Bump()
    local stamps = frame._euiPaintStamps
    if not stamps then stamps = {}; frame._euiPaintStamps = stamps end
    -- Castbar events are never deduped: each event name is a distinct edge.
    if channel ~= "castbar" and not IDENTITY_EVENTS[event] then
        local key = stamps[channel]
        if key == gen then return end
        stamps[channel] = gen
    end
    fn(frame, frame._euiUnit, event)
end

-- Full repaint of every attached channel on one frame (identity changes:
-- target swap, vehicle flip, PEW, explicit refresh from settings code).
function Engine.RepaintAll(frame, event)
    local info = attached[frame]
    if not info then return end
    -- Clear stamps first: an identity repaint must never be eaten by a
    -- value paint that happened earlier in this same hardware frame.
    if frame._euiPaintStamps then wipe(frame._euiPaintStamps) end
    for i = 1, #info.channels do
        Paint(frame, info.channels[i], event or "ForceUpdate")
    end
end

-- Suite-wide repaint (colors changed, profile switched). Replaces the old
-- library-object walk. Exported for the parent's color chokepoint.
function Engine.ForceAll(event)
    for frame in pairs(attached) do
        Engine.RepaintAll(frame, event or "ForceUpdate")
    end
end
EllesmereUI._UFEngineForceAll = Engine.ForceAll

-------------------------------------------------------------------------------
--  Event routing
-------------------------------------------------------------------------------
-- A max-health change lands in two steps: the max moves first, the value
-- follows. A paint driven by UNIT_MAXHEALTH runs between them and renders the
-- new max against the pre-change value, same-frame dedupe drops the correcting
-- UNIT_HEALTH, and at full health nothing else fires afterwards (druid form
-- stamina talents). One next-frame repaint reads settled values.
local RESETTLE_EVENTS = {
    UNIT_MAXHEALTH = true,
    UNIT_MAX_HEALTH_MODIFIERS_CHANGED = true,
}

-- tracker.channelsByEvent: event -> { channelName, ... } for its frame.
local function TrackerOnEvent(self, event, unitToken, ...)
    local frame = self._euiFrame
    if not frame or not frame:IsShown() then return end
    local chans = self._euiChannelsByEvent[event]
    if not chans then return end
    for i = 1, #chans do
        local ch = chans[i]
        if ch == "castbar" then
            -- Raw route: event identity and payload both matter (cast edges),
            -- and consecutive same-frame events each carry distinct data --
            -- never deduped.
            local fn = painters[ch]
            if fn then fn(frame, frame._euiUnit, event, unitToken, ...) end
        else
            Paint(frame, ch, event)
        end
    end

    if RESETTLE_EVENTS[event] and not self._euiResettle then
        self._euiResettle = true
        C_Timer.After(0, function()
            self._euiResettle = nil
            local f = self._euiFrame
            if not f or not f:IsShown() then return end
            for i = 1, #chans do Paint(f, chans[i], "Resettle") end
        end)
    end
end

local function EnsureTracker(token)
    local t = trackers[token]
    if t then return t end
    t = CreateFrame("Frame")
    t:SetScript("OnEvent", TrackerOnEvent)
    t._euiChannelsByEvent = {}
    trackers[token] = t
    return t
end

--- Attaches a frame to the engine. channels = array of channel names; the
--- exact set drives which events get registered, so a frame with no castbar
--- never hears a spellcast event.
function Engine.Attach(frame, unit, channels)
    local t = EnsureTracker(unit)
    t._euiFrame = frame
    attached[frame] = { unit = unit, channels = channels }
    unitFrames[unit] = frame
    -- Unit-watch shows happen while events were being dropped (hidden frames
    -- skip dispatch), so a freshly shown frame repaints in full.
    if not frame._euiEngineShowHook then
        frame._euiEngineShowHook = true
        frame:HookScript("OnShow", function(f) Engine.RepaintAll(f, "Show") end)
    end
    local secondary = SECONDARY_TOKEN[unit]
    local byEvent = t._euiChannelsByEvent
    for i = 1, #channels do
        local ch = channels[i]
        local events = (ch == "castbar") and CASTBAR_EVENTS or CHANNEL_EVENTS[ch]
        if events then
            for j = 1, #events do
                local ev = events[j]
                local list = byEvent[ev]
                if not list then
                    list = {}
                    byEvent[ev] = list
                    if secondary then
                        t:RegisterUnitEvent(ev, unit, secondary)
                    else
                        t:RegisterUnitEvent(ev, unit)
                    end
                end
                local seen = false
                for k = 1, #list do if list[k] == ch then seen = true break end end
                if not seen then list[#list + 1] = ch end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Eventless units: targettarget/focustarget. One shared ticker, 0.5s (the
--  cadence users already know), alive only while at least one of the two
--  frames is shown. Value channels repaint every tick; identity channels
--  (portrait, full text) only when the GUID actually changed --
--  compared through a secret-safe equality that treats an unreadable GUID as
--  "changed" so restricted content fails open to a repaint, never to staleness.
-------------------------------------------------------------------------------
local pollFrames = {}    -- frame -> true (tot/fot)
local pollTicker = CreateFrame("Frame")
pollTicker:Hide()
local pollAccum = 0
local POLL_INTERVAL = 0.5

local function GuidChanged(frame)
    local unit = frame._euiUnit
    local guid = UnitExists(unit) and UnitGUID(unit) or nil
    local old = frame._euiLastGuid
    if issecretvalue and (issecretvalue(guid) or issecretvalue(old)) then
        frame._euiLastGuid = guid
        return true
    end
    if guid ~= old then
        frame._euiLastGuid = guid
        return true
    end
    return false
end

pollTicker:SetScript("OnUpdate", function(self, elapsed)
    pollAccum = pollAccum + elapsed
    if pollAccum < POLL_INTERVAL then return end
    pollAccum = 0
    for frame in pairs(pollFrames) do
        if frame:IsShown() and UnitExists(frame._euiUnit) then
            if GuidChanged(frame) then
                Engine.RepaintAll(frame, "PollIdentity")
            else
                Paint(frame, "health", "Poll")
                Paint(frame, "power", "Poll")
                Paint(frame, "text", "Poll")
                Paint(frame, "absorb", "Poll")
            end
        end
    end
end)

local function PollVisibilityChanged()
    for frame in pairs(pollFrames) do
        if frame:IsShown() then pollTicker:Show(); return end
    end
    pollTicker:Hide()
end

--- Attaches an eventless frame (tot/fot): no tracker, ticker-driven. The
--- OnShow repaint keeps the first visible paint instant instead of waiting
--- out a poll interval.
function Engine.AttachPolled(frame, unit, channels)
    attached[frame] = { unit = unit, channels = channels }
    unitFrames[unit] = frame
    pollFrames[frame] = true
    -- The polled-frame marker settings code checks (portrait art heal, text
    -- class-color reapply).
    frame.__eventless = true
    frame:HookScript("OnShow", function(f)
        f._euiLastGuid = nil
        Engine.RepaintAll(f, "Show")
        PollVisibilityChanged()
    end)
    frame:HookScript("OnHide", PollVisibilityChanged)
    PollVisibilityChanged()
end

-------------------------------------------------------------------------------
--  Secure layer: frame spawning, unit watching, vehicle resolution, and
--  default-frame suppression. All original code on the raw Blizzard secure
--  APIs; the click/menu surface uses the suite's own macro-proxy menu
--  (AttachSecureUnitMenu), the proven path around the 12.1 togglemenu bug.
-------------------------------------------------------------------------------

-- Everything we spawn parents here: one state driver hides the whole set
-- during pet battles.
local petBattleHider = CreateFrame("Frame", "EllesmereUIUnitFrames_Hider", UIParent, "SecureHandlerStateTemplate")
petBattleHider:SetAllPoints(UIParent)
RegisterStateDriver(petBattleHider, "visibility", "[petbattle] hide; show")

-- The live unit a secure button is presenting: the modified unit with the
-- pet-vs-vehicle distinction resolved (a pet button whose real unit is not
-- the pet is standing in for the vehicle).
local function ResolveActiveUnit(frame)
    local real = SecureButton_GetUnit(frame)
    local mod = SecureButton_GetModifiedUnit(frame)
    if real == "playerpet" then real = "pet" end
    if mod == "playerpet" then mod = "pet" end
    if mod == "playertarget" then mod = "target" end
    if mod == "pet" and real ~= "pet" then mod = "vehicle" end
    return mod or real or frame._euiBaseUnit
end

local function EvalActiveUnit(frame)
    if not frame then return end
    local resolved = ResolveActiveUnit(frame)
    if resolved and resolved ~= frame._euiUnit then
        -- Never adopt a unit that does not exist yet. Vehicle entry resolves
        -- "vehicle" at transition START, before the unit is queryable: adopting
        -- then paints empty text (UnitName nil renders ""), and every later
        -- vehicle edge no-ops on resolved == frame._euiUnit, so an idle vehicle
        -- stays blank for the whole ride. Holding the OLD unit keeps this
        -- re-firing on each transition edge until the resolved unit is real,
        -- and THAT swap's RepaintAll paints with live data -- the same guard
        -- the oUF-era swap had. The base unit is exempt: it must always be
        -- adoptable (nonexistent target/focus frames hide via unit-watch, and
        -- refusing the base would strand a stale token instead).
        if resolved ~= frame._euiBaseUnit and not UnitExists(resolved) then return end
        frame._euiUnit = resolved
        Engine.RepaintAll(frame, "UnitChanged")
    end
end
Engine.EvalActiveUnit = EvalActiveUnit

-------------------------------------------------------------------------------
--  Element compatibility surface: the settings code toggles rendering per
--  element (portrait off, castbar off...) through the same three methods it
--  always called. "Disabled" = the matching painter skips it; the widgets and
--  their fields stay untouched.
-------------------------------------------------------------------------------
local ELEMENT_CHANNEL = {
    Health = "health", Power = "power", Castbar = "castbar",
    Portrait = "portrait", HealthPrediction = "absorb",
    RaidTargetIndicator = "raidicon",
}

--- True when a painter would render this element right now.
function Engine.ElementOn(frame, elementName)
    local off = frame._euiElementsOff
    return not (off and off[elementName])
end

local function Frame_IsElementEnabled(self, elementName)
    return self[elementName] ~= nil and Engine.ElementOn(self, elementName)
end

local function Frame_EnableElement(self, elementName)
    local off = self._euiElementsOff
    if off then off[elementName] = nil end
    -- Match the old enable semantics: an immediate refresh of that element.
    local channel = ELEMENT_CHANNEL[elementName]
    if channel == "castbar" then
        local fn = painters[channel]
        if fn then fn(self, self._euiUnit, "ForceUpdate") end
    elseif channel then
        Paint(self, channel, "ForceUpdate")
    end
end

local function Frame_DisableElement(self, elementName)
    local off = self._euiElementsOff
    if not off then off = {}; self._euiElementsOff = off end
    off[elementName] = true
end

--- Spawns one secure unit button. The caller styles it and attaches engine
--- channels afterward; RegisterUnitWatch owns show/hide from here on.
function Engine.SpawnUnitFrame(unit, name)
    -- Contextual pings: TEMPLATE-PURE, and the button must NEVER carry a
    -- `.unit` FIELD. Blizzard's ping mixin reads `self.unit or
    -- self:GetAttribute("unit")` inside PingManager's secure gather, and an
    -- addon-written field is a tainted read that turns a secret GUID
    -- "inaccessible" to the securecopy at the secure boundary (hard error +
    -- wedged listener); the attribute is the sanctioned channel and keeps
    -- the whole chain secure, so secrets pass and enemy pings work exactly
    -- like the default frames (field-proven 2026-08-20). Hence the live
    -- token lives in `_euiUnit`, and GetIsPingable/GetTargetInfo are never
    -- overridden here (raw override = securecopy error, secrecy-guarded
    -- override = pings dead in all restricted content; both field-failed).
    local frame = CreateFrame("Button", name, petBattleHider,
        "SecureUnitButtonTemplate, PingableUnitFrameTemplate")
    frame._euiBaseUnit = unit
    frame._euiUnit = unit
    frame.IsElementEnabled = Frame_IsElementEnabled
    frame.EnableElement = Frame_EnableElement
    frame.DisableElement = Frame_DisableElement
    frame:SetAttribute("unit", unit)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("toggleForVehicle", true)
    if EllesmereUI.AttachSecureUnitMenu then
        EllesmereUI.AttachSecureUnitMenu(frame)
    end
    -- The secure environment rewrites the unit attribute on vehicle and pet
    -- transitions; re-resolve whenever it moves.
    frame:HookScript("OnAttributeChanged", function(self, attr)
        if attr == "unit" or attr == "toggleForVehicle" then
            EvalActiveUnit(self)
        end
    end)
    RegisterUnitWatch(frame)
    return frame
end

-------------------------------------------------------------------------------
--  Default Blizzard unit frame suppression: the module's battle-tested
--  ns.UF_HideBlizzard owns the mechanics (alt-power-bar taint handling, the
--  boss-container-no-reparent rule); the engine just routes to it.
-------------------------------------------------------------------------------
function Engine.HideBlizzardUnitFrame(unit)
    if ns.UF_HideBlizzard then ns.UF_HideBlizzard(unit) end
end

-- Vehicle/pet transitions for the player and pet frames: the dual-token
-- event registration means nothing re-registers here -- these just move
-- frame._euiUnit and trigger the full repaint.
local vehicleWatch = CreateFrame("Frame")
vehicleWatch:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
vehicleWatch:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
vehicleWatch:RegisterUnitEvent("UNIT_PET", "player")
vehicleWatch:SetScript("OnEvent", function()
    EvalActiveUnit(unitFrames.player)
    EvalActiveUnit(unitFrames.pet)
end)

-------------------------------------------------------------------------------
--  Global (non-unit) triggers
-------------------------------------------------------------------------------
local globalFrame = CreateFrame("Frame")
globalFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
globalFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
globalFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
globalFrame:RegisterEvent("RAID_TARGET_UPDATE")
globalFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
-- 2D portrait art streams in AFTER the paint that asked for it (loading
-- screens, vehicle transitions); this unitless event is the only trigger
-- that follows, so it fans the portrait painter out to every shown frame
-- (rare event, bounded fan-out -- the old element wiring registered it
-- unconditionally on every portrait frame).
globalFrame:RegisterEvent("PORTRAITS_UPDATED")
globalFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_TARGET_CHANGED" then
        local f = unitFrames.target
        if f then Engine.RepaintAll(f, event) end
        local tot = unitFrames.targettarget
        if tot then tot._euiLastGuid = nil; pollAccum = POLL_INTERVAL end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        local f = unitFrames.focus
        if f then Engine.RepaintAll(f, event) end
        local fot = unitFrames.focustarget
        if fot then fot._euiLastGuid = nil; pollAccum = POLL_INTERVAL end
    elseif event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        for i = 1, 5 do
            local f = unitFrames["boss" .. i]
            if f and f:IsShown() then Engine.RepaintAll(f, event) end
        end
    elseif event == "RAID_TARGET_UPDATE" then
        local fn = painters.raidicon
        if fn then
            for frame, info in pairs(attached) do
                if frame:IsShown() then fn(frame, frame._euiUnit, event) end
            end
        end
    elseif event == "PORTRAITS_UPDATED" then
        local fn = painters.portrait
        if fn then
            for frame in pairs(attached) do
                if frame:IsShown() then fn(frame, frame._euiUnit, event) end
            end
        end
    else -- PLAYER_ENTERING_WORLD: the world changed under every frame.
        -- Loading screens can land mid-vehicle-transition; re-resolve the
        -- swappable frames before repainting so the repaint reads the right
        -- unit.
        EvalActiveUnit(unitFrames.player)
        EvalActiveUnit(unitFrames.pet)
        for frame in pairs(attached) do
            if frame:IsShown() then Engine.RepaintAll(frame, event) end
        end
    end
end)
