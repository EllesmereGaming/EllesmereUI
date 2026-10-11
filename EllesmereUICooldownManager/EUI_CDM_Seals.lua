if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  EUI_CDM_Seals.lua
--  "Seals" preset for Tracking Bars on WoW Forever Paladins: ONE bar that follows
--  whichever seal is up.
--
--  Seals are not in Blizzard's CDM data, so the bar is self-driven like the lust and
--  potion presets: the tracking tick hands it to ns.UpdateSealBar and the tick's
--  _UpdateSelfTimedBar draws the fill, timer and spark.
--
--  Where the running seal comes from (Forever hides aura data in combat):
--    1. the aura itself, whenever the client lets us read it (authoritative);
--    2. otherwise a cast mirror: the window the cast started, lasting as long as the
--       last clean reading showed, else the baseline (the cooldown bars' cast mirror
--       works the same way).
--  Seals are matched by NAME: every rank of a seal shares its name.
--------------------------------------------------------------------------------
local _, ns = ...

-- Seals exist only for Paladins on WoW Forever; everywhere else this file is inert.
if not EllesmereUI.IS_FOREVER then return end
local _, playerClass = UnitClass("player")
if playerClass ~= "PALADIN" then return end

-- This file leans on these members of the Cooldown Manager namespace. Fail loudly once if an
-- update removed one, rather than erroring later on a nil.
local REQUIRED_NS_MEMBERS = { "TakeShell", "GetTrackedBuffBars", "BUFF_BAR_PRESETS", "TBB_POPULAR_BUFFS" }
for _, member in ipairs(REQUIRED_NS_MEMBERS) do
    if ns[member] == nil then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555EUI Seals:|r EllesmereUI no longer provides ns."
            .. member .. ", so the Seals bar is disabled.")
        return
    end
end

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local SEAL_PRESET_KEY = "paladin_seals"

-- Window length until a clean reading shows the real one (Forever beta baseline).
local BASELINE_SEAL_SECONDS = 30

-- After a cast, a reading that finds no aura is not trusted for this long: the cast event can
-- land before the client has applied the aura.
local CAST_SETTLE_SECONDS = 0.5

-- Floor between two aura readings fed by UNIT_AURA (which fires far more often than a seal changes).
local AURA_REFRESH_INTERVAL = 0.2

-- Picker art while the spell texture is not loaded yet (same fallback the other presets use).
local FALLBACK_ICON = 134400

-- One Blizzard spell id per seal (rank 1 from Classic-era data, which Forever reuses). They only
-- resolve the localized seal names; every other rank shares its seal's name. To track a
-- further seal, cast it, run "/euiseals auras" for its id and add it here.
local SEAL_SPELL_IDS = {
    20154,    -- Seal of Righteousness
    21082,    -- Seal of the Crusader
    20375,    -- Seal of Command
    20164,    -- Seal of Justice
    20165,    -- Seal of Light
    20166,    -- Seal of Wisdom
    1311649,  -- Seal of Fury (Forever only; id read from its aura)
}

-- Events the tracker listens to while a Seals bar exists. The first group is player-scoped.
local PLAYER_UNIT_EVENTS = { "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED" }
local GLOBAL_EVENTS = { "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_DEAD" }

-------------------------------------------------------------------------------
--  SealWindow: pure window maths (no WoW API, so the plain-Lua tests can drive it)
-------------------------------------------------------------------------------
---@class SealWindow
---@field name string             seal spell name (rank-independent)
---@field icon string|number|nil  texture file id or path
---@field duration number         full window length in seconds
---@field expirationTime number   GetTime() value the window ends at
---@field fromCast boolean        true when mirrored from a cast, false when read from the aura
---@field castTime number|nil     GetTime() of the cast a mirrored window came from

---@class AuraReading
---@field name string
---@field icon string|number|nil
---@field duration number
---@field expirationTime number

---@class CastReading
---@field name string
---@field icon string|number|nil
---@field castTime number
---@field knownDuration number|nil  duration last seen on a clean reading of this seal

local SealWindow = {}
ns.SealWindow = SealWindow

-- True for a finite number above zero; nil, NaN, infinity and non-numbers are not usable seconds.
function SealWindow.IsUsableSeconds(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end

-- Window from a clean aura reading; nil when the aura has no usable timer (permanent or garbled).
---@param reading AuraReading
---@return SealWindow|nil
function SealWindow.FromAura(reading)
    if not SealWindow.IsUsableSeconds(reading.duration)
       or not SealWindow.IsUsableSeconds(reading.expirationTime) then
        return nil
    end
    return {
        name = reading.name,
        icon = reading.icon,
        duration = reading.duration,
        expirationTime = reading.expirationTime,
        fromCast = false,
    }
end

-- Window mirrored from a cast: the known duration when there is one, else the baseline.
---@param cast CastReading
---@return SealWindow
function SealWindow.FromCast(cast)
    local duration = SealWindow.IsUsableSeconds(cast.knownDuration) and cast.knownDuration
        or BASELINE_SEAL_SECONDS
    return {
        name = cast.name,
        icon = cast.icon,
        duration = duration,
        expirationTime = cast.castTime + duration,
        fromCast = true,
        castTime = cast.castTime,
    }
end

-- Seconds left in the window, never negative.
function SealWindow.SecondsLeft(window, now)
    return math.max(0, window.expirationTime - now)
end

-- True while the window still has time left.
function SealWindow.IsRunning(window, now)
    return window ~= nil and SealWindow.SecondsLeft(window, now) > 0
end

-- True while a mirrored window is young enough that "no aura" is not yet proof the seal is gone.
function SealWindow.IsSettling(window, now)
    return window.fromCast == true and window.castTime ~= nil
        and (now - window.castTime) < CAST_SETTLE_SECONDS
end

-------------------------------------------------------------------------------
--  SealTracker: where the running seal window comes from
-------------------------------------------------------------------------------
---@class SealTrackerState
---@field window SealWindow|nil          the window we believe is running
---@field sealNames table<string, true>  localized seal names (set)
---@field observedSeconds table<string, number>  per-session: real duration seen per seal
---@field listening boolean
---@field auraStale boolean              an aura event arrived since the last reading
---@field lastAuraReading number         GetTime() of the last reading
---@field eventFrame table|nil
local tracker = {
    window = nil,
    sealNames = {},
    observedSeconds = {},
    listening = false,
    auraStale = false,
    lastAuraReading = 0,
    eventFrame = nil,
}

local SealTracker = {}
ns.SealTracker = SealTracker

-- True for a secret value; comparing or indexing one would raise an error.
local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- Wakes the idle-parked tracking tick so a new or changed window starts drawing.
local function WakeTick()
    if ns.WakeTBBTick then ns.WakeTBBTick() end
end

-- Rebuilds the localized seal-name set from the seal spell ids.
function SealTracker.RebuildSealNames()
    wipe(tracker.sealNames)
    local getSpellName = C_Spell and C_Spell.GetSpellName
    if not getSpellName then return end
    for _, spellID in ipairs(SEAL_SPELL_IDS) do
        local sealName = getSpellName(spellID)
        if sealName then tracker.sealNames[sealName] = true end
    end
end

-- Sorted copy of the known seal names, for diagnostics.
function SealTracker.GetSealNames()
    local names = {}
    for sealName in pairs(tracker.sealNames) do names[#names + 1] = sealName end
    table.sort(names)
    return names
end

-- Icon for an aura reading: the aura's own when readable, else the spell texture looked up by name.
local function ReadAuraIcon(auraIcon, sealName)
    if auraIcon ~= nil and not IsSecret(auraIcon) then return auraIcon end
    return C_Spell.GetSpellTexture(sealName)
end

-- Reads the running seal from the player's auras. Returns the window (nil when no seal aura
-- is up) and `blocked`: true when the client hid the data (secret values or a failed query),
-- which means "unknown", not "no seal".
---@return SealWindow|nil window
---@return boolean blocked
local function ReadRunningSeal()
    for sealName in pairs(tracker.sealNames) do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", sealName, "HELPFUL")
        if not ok or IsSecret(aura) then return nil, true end
        if aura then
            local duration, expirationTime = aura.duration, aura.expirationTime
            if IsSecret(duration) or IsSecret(expirationTime) then return nil, true end
            return SealWindow.FromAura({
                name = sealName,
                icon = ReadAuraIcon(aura.icon, sealName),
                duration = duration,
                expirationTime = expirationTime,
            }), false
        end
    end
    return nil, false
end

-- Takes one aura reading and folds it into the tracker: authoritative whenever the client lets
-- us read it, ignored when blocked (the cast mirror keeps running).
local function AcceptAuraReading(now)
    local reading, blocked = ReadRunningSeal()
    if blocked then return end
    local mirrored = tracker.window
    if reading then
        -- Mid-swap the reading can still show the OLD seal; a fresh cast of another seal wins until it settles.
        if mirrored and reading.name ~= mirrored.name and SealWindow.IsSettling(mirrored, now) then return end
        tracker.observedSeconds[reading.name] = reading.duration
        tracker.window = reading
        return
    end
    -- No aura. Right after a cast that can just mean it has not landed yet.
    if mirrored and SealWindow.IsSettling(mirrored, now) then return end
    tracker.window = nil
end

-- Takes a reading and wakes the tick when a seal (or a different seal) just appeared.
local function RefreshFromAura(now)
    tracker.auraStale = false
    tracker.lastAuraReading = now
    local nameBefore = tracker.window and tracker.window.name
    AcceptAuraReading(now)
    local nameAfter = tracker.window and tracker.window.name
    if nameAfter and nameAfter ~= nameBefore then WakeTick() end
end

-- Starts the mirror window for a seal cast; the next readable aura reading refines it.
local function MirrorSealCast(spellID, now)
    if IsSecret(spellID) or type(spellID) ~= "number" then return end
    local sealName = C_Spell.GetSpellName(spellID)
    if not sealName or not tracker.sealNames[sealName] then return end
    tracker.window = SealWindow.FromCast({
        name = sealName,
        icon = C_Spell.GetSpellTexture(spellID),
        castTime = now,
        knownDuration = tracker.observedSeconds[sealName],
    })
    WakeTick()
end

-- Names may have changed (spellbook, zone) and a carried seal needs a fresh reading.
local function RefreshNamesAndAura(now)
    SealTracker.RebuildSealNames()
    RefreshFromAura(now)
end

-- Handlers per event; each receives GetTime() first, then the event's own arguments.
local EVENT_HANDLERS = {
    -- UNIT_SPELLCAST_SUCCEEDED args: unit, castGUID, spellID
    UNIT_SPELLCAST_SUCCEEDED = function(now, _, _, spellID) MirrorSealCast(spellID, now) end,
    UNIT_AURA = function(now)
        tracker.auraStale = true
        -- Throttled: the tick consumes whatever is left stale on its next pass.
        if now - tracker.lastAuraReading >= AURA_REFRESH_INTERVAL then RefreshFromAura(now) end
    end,
    PLAYER_DEAD = function() tracker.window = nil end,
    PLAYER_ENTERING_WORLD = RefreshNamesAndAura,
    SPELLS_CHANGED = RefreshNamesAndAura,
}

-- OnEvent script of the tracker's frame: routes an event to its handler.
local function DispatchEvent(_, event, ...)
    local handler = EVENT_HANDLERS[event]
    if handler then handler(GetTime(), ...) end
end

-- Starts listening. Idempotent; called when the first Seals bar appears.
function SealTracker.Start()
    if tracker.listening then return end
    tracker.listening = true
    if not tracker.eventFrame then
        tracker.eventFrame = ns.TakeShell()
        tracker.eventFrame:SetScript("OnEvent", DispatchEvent)
    end
    SealTracker.RebuildSealNames()
    for _, event in ipairs(PLAYER_UNIT_EVENTS) do tracker.eventFrame:RegisterUnitEvent(event, "player") end
    for _, event in ipairs(GLOBAL_EVENTS) do tracker.eventFrame:RegisterEvent(event) end
    RefreshFromAura(GetTime())
end

-- Stops listening and forgets the window. Idempotent; called when the last Seals bar goes away.
function SealTracker.Stop()
    if not tracker.listening then return end
    tracker.listening = false
    tracker.eventFrame:UnregisterAllEvents()
    tracker.window = nil
    tracker.auraStale = false
end

-- True while the tracker is listening.
function SealTracker.IsListening()
    return tracker.listening
end

-- The window to draw this frame, or nil when no seal is up. A stale aura reading is taken here
-- (at most one per call) instead of in the event handler, because UNIT_AURA fires far more
-- often than a bar needs redrawing.
---@param now number GetTime() for this frame
---@return SealWindow|nil
function SealTracker.GetWindow(now)
    if tracker.auraStale then RefreshFromAura(now) end
    if tracker.window and not SealWindow.IsRunning(tracker.window, now) then tracker.window = nil end
    return tracker.window
end

-- Arms the tracker only while an enabled Seals bar exists. Fanned out from UpdateLustListener,
-- so every add/remove/rebuild path that refreshes the other preset listeners refreshes this one.
function ns.UpdateSealListener()
    local tbb = ns.GetTrackedBuffBars()
    local sealBarExists = false
    for _, cfg in ipairs(tbb and tbb.bars or {}) do
        if cfg.enabled ~= false and cfg.popularKey == SEAL_PRESET_KEY then
            sealBarExists = true
            break
        end
    end
    if sealBarExists then SealTracker.Start() else SealTracker.Stop() end
end

-------------------------------------------------------------------------------
--  Drawing (called from the Tracking Bars tick)
-------------------------------------------------------------------------------
-- Points the bar's name and icon at the running seal. Compares against what the bar shows now,
-- so a rebuild that reset them is corrected on the next tick without any stamp to go stale.
local function ShowSealIdentity(bar, window)
    local nameText = bar._nameText
    if nameText and window.name and nameText:GetText() ~= window.name then
        nameText:SetText(window.name)
    end
    local iconTexture = bar._icon and bar._icon._tex
    if iconTexture and window.icon and iconTexture:GetTexture() ~= window.icon then
        iconTexture:SetTexture(window.icon)
    end
end

-- Draws one Seals bar for this tick; returns true while a seal is up, which keeps the tick awake.
-- `drawSelfTimed` is the tick's _UpdateSelfTimedBar (file-local there), passed in so fill, timer,
-- spark and hide logic stay shared with the other self-timed presets. It takes three positional
-- arguments on purpose: it runs every tick, where EllesmereUI forbids per-frame table allocation.
function ns.UpdateSealBar(bar, cfg, drawSelfTimed)
    local window = SealTracker.GetWindow(GetTime())
    if not window then
        -- An expiry in the past makes the shared drawer hide the bar and report "not live".
        return drawSelfTimed(bar, cfg, 0, BASELINE_SEAL_SECONDS)
    end
    ShowSealIdentity(bar, window)
    return drawSelfTimed(bar, cfg, window.expirationTime, window.duration)
end

-------------------------------------------------------------------------------
--  Picker preset
-------------------------------------------------------------------------------
-- The preset entry in the shape the Tracking Bars picker stores on a bar. tbbOnly keeps it out of
-- the cooldown/utility pickers; this file only loads for Forever Paladins, so only they see it.
local function BuildPresetEntry()
    return {
        key = SEAL_PRESET_KEY,
        name = "Seals",
        icon = C_Spell.GetSpellTexture(SEAL_SPELL_IDS[1]) or FALLBACK_ICON,
        spellIDs = { unpack(SEAL_SPELL_IDS) },
        duration = BASELINE_SEAL_SECONDS,
        customDuration = BASELINE_SEAL_SECONDS,  -- compat alias the picker copies onto the bar
        tbbOnly = true,
    }
end

-- Appends the preset to both lists the picker and the bar builder read (the Tracking Bars list is
-- a load-time copy of the preset list). Idempotent.
local function RegisterPreset()
    for _, presetList in ipairs({ ns.BUFF_BAR_PRESETS, ns.TBB_POPULAR_BUFFS }) do
        local alreadyListed = false
        for _, entry in ipairs(presetList) do
            if entry.key == SEAL_PRESET_KEY then alreadyListed = true; break end
        end
        if not alreadyListed then presetList[#presetList + 1] = BuildPresetEntry() end
    end
end
RegisterPreset()

-------------------------------------------------------------------------------
--  Diagnostics: /euiseals [auras]
-------------------------------------------------------------------------------
-- One chat line in the addon's colour.
local function Say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff0cd29fEUI Seals:|r " .. message)
end

-- Prints the player's helpful auras with spell ids (readable out of combat), to find a seal's id.
local function DumpAuras()
    for index = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
        if not aura then return end
        if IsSecret(aura) or IsSecret(aura.name) or IsSecret(aura.spellId) then
            Say(index .. ": (secret)")
        else
            Say(string.format("%d: %s  id=%s  duration=%s", index, tostring(aura.name),
                tostring(aura.spellId), tostring(aura.duration)))
        end
    end
end

-- Prints the tracker state: the seal names it resolved, whether it listens, and the window it would draw.
local function DumpStatus()
    local sealNames = SealTracker.GetSealNames()
    Say(string.format("listening=%s, %d seal names: %s", tostring(tracker.listening),
        #sealNames, table.concat(sealNames, ", ")))
    local now = GetTime()
    local window = SealTracker.GetWindow(now)
    if not window then
        Say("window: none")
        return
    end
    Say(string.format("window: %s, %.1fs left of %.0fs (%s)", window.name,
        SealWindow.SecondsLeft(window, now), window.duration,
        window.fromCast and "mirrored from cast" or "read from aura"))
end

-- Subcommands of /euiseals; anything else prints the status.
local SUBCOMMANDS = { auras = DumpAuras }

-- Slash handler: runs the named subcommand, else the status dump.
local function HandleSlash(argument)
    local command = (argument or ""):lower():match("^%s*(%S*)")
    local run = SUBCOMMANDS[command] or DumpStatus
    run()
end

SLASH_EUISEALS1 = "/euiseals"
SlashCmdList.EUISEALS = HandleSlash
