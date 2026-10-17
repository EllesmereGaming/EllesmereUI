if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_DamageMeters_Lifecycle.lua
--
--  The shared refresh ticker, the combat and PvP events, the key binding
--  buttons and the login build of the windows.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._dmInternals
-- EllesmereUIDamageMeters.lua or an earlier EUI_DamageMeters_*.lua file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = EllesmereUI

local DB, EnsureDB, MAX_WINDOWS = I.DB, I.EnsureDB, I.MAX_WINDOWS
local REFRESH_RATE_FLOOR = I.REFRESH_RATE_FLOOR
local REFRESH_RATE_HARD_FLOOR, TICK_COMBAT = I.REFRESH_RATE_HARD_FLOOR, I.TICK_COMBAT
local _deathStamps, _feignDeathGUIDs = I._deathStamps, I._feignDeathGUIDs
local _targetsCache, _windows, FreezeCombat = I._targetsCache, I._windows, I.FreezeCombat
local IsGroupInCombat, _srcKeyGuid = I.IsGroupInCombat, I._srcKeyGuid
local AppendDMSharedMedia, SnapshotSourceKeys = I.AppendDMSharedMedia, I.SnapshotSourceKeys
local _hoverPollFrame, EnsureTooltipFrame = I._hoverPollFrame, I.EnsureTooltipFrame
local CreateDMWindow, CreateSATimer = I.CreateDMWindow, I.CreateSATimer
local SetupSATimer, UpdateSATimerText = I.SetupSATimer, I.UpdateSATimerText
local SetInCombat, SetNeedsFinalRefresh = I.SetInCombat, I.SetNeedsFinalRefresh
local SetSharedTicker, SetCombatEndTime = I.SetSharedTicker, I.SetCombatEndTime
local SetCurViewFrozenDur, SetInEncounter = I.SetCurViewFrozenDur, I.SetInEncounter
local SetPlayerGUID, SetTTLastScale = I.SetPlayerGUID, I.SetTTLastScale
local SetActiveRow, SetStartSharedTicker = I.SetActiveRow, I.SetStartSharedTicker
local SetStopSharedTicker = I.SetStopSharedTicker

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._dmInternals, which hands the value to every copy.
local _inCombat = I._inCombat
I.inCombatSetters[#I.inCombatSetters + 1] = function(v) _inCombat = v end
local _combatEndTime = I._combatEndTime
I.combatEndTimeSetters[#I.combatEndTimeSetters + 1] = function(v) _combatEndTime = v end
local _needsFinalRefresh = I._needsFinalRefresh
I.needsFinalRefreshSetters[#I.needsFinalRefreshSetters + 1] = function(v) _needsFinalRefresh = v end
local _sharedTicker
I.sharedTickerSetters[#I.sharedTickerSetters + 1] = function(v) _sharedTicker = v end
local _ttFrame
I.ttFrameSetters[#I.ttFrameSetters + 1] = function(v) _ttFrame = v end
local _saTimer
I.saTimerSetters[#I.saTimerSetters + 1] = function(v) _saTimer = v end

-- Bumped whenever a build of the windows starts or _EDM_Apply() supersedes one. The
-- login build is staggered across frames, so a profile swap arriving while it is still
-- in flight would otherwise let the pending steps assign _windows[i] over the windows
-- the swap had just set up -- abandoning those frames while they stay parented and
-- visible. A staggered step checks this before doing any work and drops out if a newer
-- build has taken over.
local _buildGen = 0
local _combatGen = 0     -- monotonic segment token; stale deferred teardowns compare against it
-- Assigned below. The first two are handed to the earlier files
-- (SetStopSharedTicker, SetStartSharedTicker).
local StopSharedTicker
local StartSharedTicker
local ScheduleStopTicker

-- Shared refresh ticker (one ticker for ALL windows). _sharedTicker is declared in
-- EUI_DamageMeters_State.lua (so the session-update handler can revive it after a teardown race); assigned by Start/StopSharedTicker

local _regenTimestamp = 0  -- GetTime() when player left combat

-- Dedicated combat-timer ticker: keeps header clocks (and the standalone timer) ticking once per displayed second regardless of refresh rate, only while the shared ticker runs (combat); the second
-- memo in UpdateTimerText makes redundant ticks free. Historical-session windows are skipped -- their duration is static and already painted by RefreshUI.
local _timerTicker
local _saDecimalTicker

local function TimerTick()
    for _, w in ipairs(_windows) do
        if not w.curSessionID and w.UpdateTimerText then w.UpdateTimerText() end
    end
    if _windows[1] and UpdateSATimerText then UpdateSATimerText() end
end

local function StopTimerTicker()
    if _timerTicker then _timerTicker:Cancel(); _timerTicker = nil end
    if _saDecimalTicker then _saDecimalTicker:Cancel(); _saDecimalTicker = nil end
end

-- What the ticks feed: true while something is on screen (a visible window, or the enabled
-- standalone timer, whose clock lives on these tickers); "stamp" while only a hidden window
-- on the live Current Deaths view needs them (ns._DMHiddenDeathsPass, no clock); false
-- otherwise. A hidden window's refresh only marks it stale for its OnShow catch-up.
local function AnyTickViewer()
    if DB().standaloneTimer then return true end
    local stamp = false
    for _, w in ipairs(_windows) do
        local f = w.frame
        -- A Threat window (WoW Forever) is painted by its own list's updates.
        if f and w.curDMType ~= "threat" then
            if f:IsVisible() then return true end
            if w.curDMType == Enum.DamageMeterType.Deaths and not w.curSessionID
               and w.curSession == Enum.DamageMeterSessionType.Current then stamp = "stamp" end
        end
    end
    return stamp
end

local function SharedRefreshTick()
    -- Player out of combat but group still fighting (player died mid-pull)
    if _needsFinalRefresh then
        local groupDone = not IsGroupInCombat()
        -- Failsafe: if player has been out of combat for 5s, force-freeze
        -- even if IsGroupInCombat still reports true (healer HoTs, API lag)
        if not groupDone and _regenTimestamp > 0 and (GetTime() - _regenTimestamp) > 5 then
            groupDone = true
        end
        if groupDone then
            -- Group combat ended: freeze timer (pin final duration), final refresh, stop
            FreezeCombat(_regenTimestamp > 0 and _regenTimestamp or GetTime())
            SetInCombat(false)
            SetNeedsFinalRefresh(false)
            _regenTimestamp = 0
            for _, w in ipairs(_windows) do
                if w.curDMType ~= "threat" then w.Refresh() end
            end
            if _sharedTicker then _sharedTicker:Cancel(); SetSharedTicker(nil) end
            StopTimerTicker()
            return
        end
        -- Group still fighting: fall through to normal refresh
    end
    if _combatEndTime > 0 or (not _inCombat and not _needsFinalRefresh) then
        -- Combat fully ended or state lost: stop ticking
        if _sharedTicker then _sharedTicker:Cancel(); SetSharedTicker(nil) end
        StopTimerTicker()
        return
    end
    -- (Threat windows, WoW Forever, are painted by their own list's updates.)
    for _, w in ipairs(_windows) do
        if w.curDMType ~= "threat" then w.Refresh() end
    end
    -- Nothing on screen any more (each window above only marked itself stale): stop, and the
    -- next window to show restarts the ticks. The group-fight poll and a hidden live Deaths
    -- view keep their tick, no clock.
    local v = AnyTickViewer()
    if v ~= true then
        if _needsFinalRefresh or v then StopTimerTicker() else StopSharedTicker() end
    end
end

-- Only active during combat to avoid idle CPU cost, and only while AnyTickViewer or the
-- group-fight poll (_needsFinalRefresh) needs a tick. Gated here rather than at the call
-- sites, so the session-event revivals cannot bring back a ticker with nothing to paint.
StartSharedTicker = function()
    if _sharedTicker then _sharedTicker:Cancel(); SetSharedTicker(nil) end
    StopTimerTicker()
    local viewers = AnyTickViewer()
    if not viewers and not _needsFinalRefresh then
        -- Data keeps moving with nothing refreshing it: mark every (hidden) window stale so
        -- its show catches up at once instead of a tick later.
        for _, w in ipairs(_windows) do w._refreshPending = true end
        return
    end
    local rate = DB().refreshRate or TICK_COMBAT
    -- Belt for values the login clamp has not seen yet (a profile imported
    -- mid-session from an old export can carry a sub-floor rate). Respects
    -- unsafeRefreshRate the same way the login clamp does; the hard floor
    -- applies either way so 0 or negative can never reach the ticker.
    local floor = DB().unsafeRefreshRate and REFRESH_RATE_HARD_FLOOR or REFRESH_RATE_FLOOR
    if rate < floor then rate = floor end
    SetSharedTicker(C_Timer.NewTicker(rate, SharedRefreshTick))
    -- The poll or a hidden live Deaths view alone (nothing on screen) needs no clock
    if viewers ~= true then return end
    _timerTicker = C_Timer.NewTicker(0.5, TimerTick)
    -- Tenths display needs a faster brush than the 0.5s timer tick; combat-only, opt-in only, standalone timer only
    local cfg = DB()
    if cfg.standaloneTimer and cfg.standaloneTimerDecimal then
        _saDecimalTicker = C_Timer.NewTicker(0.1, UpdateSATimerText)
    end
end
SetStartSharedTicker(StartSharedTicker)

StopSharedTicker = function()
    if _sharedTicker then _sharedTicker:Cancel(); SetSharedTicker(nil) end
    StopTimerTicker()
end
SetStopSharedTicker(StopSharedTicker)

-- Something came on screen (a window's OnShow, after its catch-up; a build or profile
-- swap, whose windows show without an OnShow edge): start the ticks, or add the clock
-- to a clockless ticker. The clock runs whenever anything is on screen, so its absence
-- is the signal. On ns: CreateDMWindow sits at the 60-upvalue cap.
ns._DMReviveTicks = function()
    if (_inCombat or _needsFinalRefresh) and not _timerTicker then StartSharedTicker() end
end

-- Stop the ticker after `delay`, no-op if a newer combat segment started (generation mismatch)
-- or combat is still live. Guards against cancelling the NEXT segment's ticker when a boss is pulled within the stop delay of the previous pack ending.
ScheduleStopTicker = function(delay)
    local gen = _combatGen
    C_Timer.After(delay, function()
        if gen ~= _combatGen then return end
        if _inCombat or _needsFinalRefresh then return end
        StopSharedTicker()
    end)
end

-- Combat state tracking (shared, group-aware)
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
combatFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
combatFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
combatFrame:RegisterEvent("UNIT_FLAGS")
combatFrame:RegisterEvent("ENCOUNTER_START")
combatFrame:RegisterEvent("ENCOUNTER_END")
-- Detect Feign Death via UNIT_SPELLCAST_SUCCEEDED (Blizzard doesn't fire UNIT_AURA for FD, and
-- the combat log is unreliable for this). High-frequency event, so gate it with a tight integer compare.
combatFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
combatFrame:SetScript("OnEvent", function(_, event, ...)
    -- UNIT_SPELLCAST_SUCCEEDED is the highest-frequency event here; check first with a tight integer compare so non-FD casts cost ~nothing
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if not unit then return end
        -- spellID can be a secret number when tainted by C_DamageMeter (comparing one throws "attempt to compare a secret value");
        -- without a usable spellID we can't classify the cast, so bail
        if issecretvalue and issecretvalue(spellID) then return end
        if spellID == 5384 then -- Feign Death
            local guid = UnitGUID(unit)
            if guid and not (issecretvalue and issecretvalue(guid)) then
                _feignDeathGUIDs[guid] = true
            end
        end
        -- Do not clear on non-FD casts: a live hunter can still have a feign entry with a valid
        -- deathRecapID; CleanupFeignCache clears it once they are truly dead.
        return
    end
    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- The TWO stale-key edges own the additive snapshot map's wipe:
        -- membership changes (guids leave) and spec changes (a respec strands
        -- the old CLASS:specIcon key; field dump showed a lone live mage
        -- blocked by its former twin's echo, and a respec's old key can
        -- ambiguous-block the new one). Never mid-combat, where the rebuild
        -- would read secrets and trade good captures for nothing; the lift
        -- edge re-runs the harvest anyway.
        if not InCombatLockdown() then
            wipe(_srcKeyGuid)
            SnapshotSourceKeys()
        end
        return
    end
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- Doc-sequenced to fire AFTER a restriction deactivates: the Combat
        -- restriction lifting is the exact declassified edge -- the moment
        -- every source field reads plain again. Snapshot right here (the
        -- function self-gates against the activation-side firing).
        local rType = ...
        if Enum.AddOnRestrictionType and rType == Enum.AddOnRestrictionType.Combat
           and not InCombatLockdown() then
            SnapshotSourceKeys()
        end
        return
    end
    if event == "UNIT_FLAGS" then
        -- Moved profiling inside the gate so filtered-out calls are truly zero-cost
        -- Quick bail: only care when in an instance, out of combat, and ticker not running
        if _inCombat or _sharedTicker or not IsInInstance() then return end
        local unit = ...
        if not unit or not (unit:match("^raid") or unit:match("^party")) then return end
        -- Group member entered combat before us: start polling so bars populate
        if IsGroupInCombat() then
            SetCombatEndTime(0)
            SetCurViewFrozenDur(0)
            -- A stale stamp of the last fight would trip the 5s failsafe on the first tick
            _regenTimestamp = 0
            -- Pre-warm: a teammate pulled before us. Mark a final-refresh poll (NOT _inCombat --
            -- the player may never personally enter combat, so nothing would ever clear _inCombat if we set it). SharedRefreshTick refreshes while the group fights and self-terminates when it leaves combat.
            SetNeedsFinalRefresh(true)
            _combatGen = _combatGen + 1
            StartSharedTicker()
        end
        return
    end
    if event == "ENCOUNTER_START" then
        SetInEncounter(true)
        -- A boss pull is a hard segment boundary even in chain-pull combat, where PLAYER_REGEN_DISABLED
        -- never fires: bump the segment token (pending deferred stops no-op), assert combat, reset
        -- the timer pin. No clock anchored here -- the timer derives from the live "Current" session so it self-resets on the roll; a synchronous read here would race it and show the stale pre-pull duration.
        _combatGen = _combatGen + 1
        if next(_feignDeathGUIDs) then wipe(_feignDeathGUIDs) end -- new segment: stale feign tags would mis-filter real deaths
        if next(_deathStamps) then wipe(_deathStamps) end
        SetInCombat(true)
        SetCombatEndTime(0)
        SetCurViewFrozenDur(0)
        _regenTimestamp = 0
        SetNeedsFinalRefresh(false)
        if not _sharedTicker then StartSharedTicker() end
        ns.AutoCurrentOnCombat()
        for _, w in ipairs(_windows) do
            w._barCacheKey = nil
            w._cachedTargets = nil
            w.Refresh()
        end
        return
    end
    if event == "ENCOUNTER_END" then
        SetInEncounter(false)
        local success = select(5, ...)   -- 1 = kill, 0 = wipe
        -- On a clean kill, end combat promptly (PLAYER_REGEN_ENABLED can lag ENCOUNTER_END by
        -- several seconds). If it was NOT a clean kill and the group is still fighting (wipe with
        -- survivors, adds left, AoE into the next pack), do NOT hard-freeze mid-combat -- keep the ticker live and freeze only once the group truly leaves combat.
        if _inCombat or _needsFinalRefresh then
            local gen = _combatGen
            -- Short delay: let Blizzard finalize the session data first
            C_Timer.After(0.5, function()
                if gen ~= _combatGen then return end   -- a new segment (chain pull) started
                if _combatEndTime > 0 then return end  -- already ended elsewhere
                if success ~= 1 and IsGroupInCombat() then
                    SetNeedsFinalRefresh(true)
                    if not _sharedTicker then StartSharedTicker() end
                    return
                end
                FreezeCombat()
                SetInCombat(false)
                SetNeedsFinalRefresh(false)
                for _, w in ipairs(_windows) do w.Refresh() end
                ScheduleStopTicker(0.5)
            end)
        end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then
        -- Ignore post-match cleanup combat after a PvP match ends
        if _G._EUIDM_PvpBlocked and _G._EUIDM_PvpBlocked() then return end
        _combatGen = _combatGen + 1
        if next(_feignDeathGUIDs) then wipe(_feignDeathGUIDs) end -- new segment: stale feign tags would mis-filter real deaths
        if next(_deathStamps) then wipe(_deathStamps) end
        SetInCombat(true)
        SetCombatEndTime(0)
        SetCurViewFrozenDur(0)
        _regenTimestamp = 0
        SetNeedsFinalRefresh(false)
        if _targetsCache then wipe(_targetsCache) end
        StartSharedTicker()
        ns.AutoCurrentOnCombat()
    else
        _regenTimestamp = GetTime()
        -- Feign Death + group still fighting: keep timer running
        if UnitIsFeignDeath and UnitIsFeignDeath("player") and IsGroupInCombat() then return end
        if _targetsCache then wipe(_targetsCache) end
        -- Check if group is still fighting (player died but boss alive)
        if IsGroupInCombat() then
            SetNeedsFinalRefresh(true)  -- let tick poll until group leaves combat
            -- The poll needs its tick even when a fully hidden meter let the ticker lapse
            if not _sharedTicker then StartSharedTicker() end
            -- Don't freeze timer -- group is still in combat
        else
            -- Freeze timer: entire group out of combat. Guard against overwriting an earlier freeze (e.g. ENCOUNTER_END already froze at the boss end)
            if _combatEndTime == 0 then FreezeCombat() end
            SetInCombat(false)
            SetNeedsFinalRefresh(false)
            for _, w in ipairs(_windows) do w.Refresh() end
            -- One final tick then stop (guarded so it can't cancel a new segment).
            ScheduleStopTicker(DB().refreshRate or TICK_COMBAT)
        end
        -- Delayed refresh after exiting combat: API needs a moment to declassify secret source GUIDs so breakdowns work post-combat
        C_Timer.After(0.5, function()
            for _, w in ipairs(_windows) do w.Refresh() end
            -- Declassified = the ideal moment to refresh the breakdown
            -- resolver's class:spec -> guid snapshot for the NEXT pull.
            if ns._SnapshotSourceKeys and not InCombatLockdown() then
                ns._SnapshotSourceKeys()
            end
        end)
    end
end)


-- PvP match end detection: arenas/solo shuffle don't reliably fire PLAYER_REGEN_ENABLED when the
-- match ends (IsGroupInCombat() stays true between rounds), so track match state via C_PvP and force-end the segment when the match finishes.
do
    local _pvpMatchActive = false
    local _pvpBlockUntil = 0

    local pvpFrame = CreateFrame("Frame")
    pvpFrame:RegisterEvent("PVP_MATCH_COMPLETE")
    pvpFrame:RegisterEvent("PVP_MATCH_STATE_CHANGED")
    pvpFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    pvpFrame:SetScript("OnEvent", function()
        if not C_PvP or not C_PvP.IsMatchActive then return end
        local active = C_PvP.IsMatchActive()
        if active and not _pvpMatchActive then
            _pvpMatchActive = true
        elseif not active and _pvpMatchActive then
            _pvpMatchActive = false
            C_Timer.After(1.5, function()
                if _pvpMatchActive then return end
                if _combatEndTime > 0 then return end
                FreezeCombat()
                SetInCombat(false)
                SetNeedsFinalRefresh(false)
                for _, w in ipairs(_windows) do w.Refresh() end
                ScheduleStopTicker(0.5)
                -- Block new segments from post-match cleanup damage
                _pvpBlockUntil = GetTime() + 20
            end)
        end
    end)

    -- Expose the block check so combat start can respect it
    _G._EUIDM_PvpBlocked = function()
        return GetTime() < _pvpBlockUntil
    end
end

-- Reset Data keybind button (hidden, receives override binding click)
if not _G["EllesmereUIDMResetBindBtn"] then
    local btn = CreateFrame("Button", "EllesmereUIDMResetBindBtn", UIParent)
    btn:Hide()
    btn:SetScript("OnClick", function()
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
            C_DamageMeter.ResetAllCombatSessions()
            SetCombatEndTime(0); SetCurViewFrozenDur(0)
            for _, w in ipairs(_windows) do w.Refresh() end
        end
    end)
end

-- Show/hide all windows keybind button (hidden, receives override binding click)
if not _G["EllesmereUIDMToggleBindBtn"] then
    local btn = CreateFrame("Button", "EllesmereUIDMToggleBindBtn", UIParent)
    btn:Hide()
    btn:SetScript("OnClick", function()
        if ns.ToggleDMWindows then ns.ToggleDMWindows() end
    end)
end

-- Init
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if EUI and EUI.ADDON_ROSTER then
        for _, info in ipairs(EUI.ADDON_ROSTER) do
            if info.folder == "EllesmereUIDamageMeters" and info.comingSoon then return end
        end
    end

    EnsureDB()
    -- DB is now available; rebuild number format so a saved forceEnglishUnits preference applies at login (load-time build ran before the DB existed)
    if ns.RebuildNumberFormat then ns.RebuildNumberFormat() end
    -- A profile already on Classic WoW UI gets its one-time seed here (the
    -- Style page seeds on the switch; flags make both idempotent).
    if ns.DMClassic() then ns.DMSeedClassic(DB()) end
    -- Disable Blizzard's built-in damage meter UI; C_DamageMeter API still works
    EllesmereUI.SetCVar("damageMeterEnabled", 0, "EllesmereUIDamageMeters")
    AppendDMSharedMedia()

    SetPlayerGUID(UnitGUID("player"))

    -- Restore the reset data and show/hide all windows keybinds
    ns.ApplyDMKeybinds()

    -- Defer window creation off the login frame to avoid blocking
    local cfg = DB()
    if not cfg.windows then cfg.windows = {} end
    -- windowCount is authoritative; trim stale array entries beyond it
    local winCount = math.max(1, cfg.windowCount or 1)
    cfg.windowCount = winCount
    for i = winCount + 1, MAX_WINDOWS do cfg.windows[i] = nil end
    local winIdx = 0
    _buildGen = _buildGen + 1
    local myBuildGen = _buildGen
    local function CreateNextWindow()
        -- A rebuild has superseded this staggered build; carrying on would overwrite the
        -- windows it created and leave those frames orphaned but visible.
        if myBuildGen ~= _buildGen then return end
        winIdx = winIdx + 1
        if winIdx > winCount then
            -- All windows exist: register them with the core unlock mode system
            ns.RegisterDMUnlock()
            if cfg.standaloneTimer then CreateSATimer() end
            ns._DMReviveTicks()
            -- Pre-create tooltip frame so first hover doesn't pay creation cost
            EnsureTooltipFrame()
            local sc = (cfg.hoverTooltipScale or 100) / 100
            if _ttFrame then _ttFrame:SetScale(sc); SetTTLastScale(sc) end
            return
        end
        _windows[winIdx] = CreateDMWindow(winIdx)
        ns.ApplyWindowBorder()
        C_Timer.After(0, CreateNextWindow)
    end
    C_Timer.After(0, CreateNextWindow)

    -- Profile swap: the windows are kept and re-read the new profile (W.Reapply); windows
    -- past its window count are parked (W.Park) and come back when a later profile, or
    -- New Window, needs them again.
    _G._EDM_Apply = function()
        -- Supersede any staggered build still in flight, so its remaining steps do not
        -- assign over the windows set up below
        _buildGen = _buildGen + 1
        -- Hide tooltip
        if _ttFrame then _ttFrame:Hide() end
        SetActiveRow(nil); _hoverPollFrame:Hide()
        local c = DB()
        -- Clear the hotkey toggle so a profile swap never lands in a hidden state whose
        -- cause is no longer visible, then re-apply both keybinds from the new profile
        ns._toggleHidden = false
        ns.ApplyDMKeybinds()
        -- Force English Units from the new profile
        ns.RebuildNumberFormat()
        if not c.windows then c.windows = {} end
        local wc = math.max(1, c.windowCount or 1)
        c.windowCount = wc
        for i = wc + 1, MAX_WINDOWS do c.windows[i] = nil end
        -- Windows past the new count are parked, the last first (they come back in order)
        for i = #_windows, wc + 1, -1 do
            local w = _windows[i]
            _windows[i] = nil
            w.Park()
        end
        -- Kept windows re-read the new profile; a slot with none brings back a parked
        -- window or builds one
        for i = 1, wc do
            local w = _windows[i]
            if w then w.Reapply(i) else _windows[i] = ns.DMAcquireWindow(i) end
        end
        ns.ApplyWindowBorder()
        -- A window that left the Threat type may leave its list with no window (WoW Forever)
        if ns.DMThreatSync then ns.DMThreatSync() end
        -- Spell History caches its profile table; refresh it before rebuilding
        -- optional unlock registrations so enable state and positions agree.
        if ns.RefreshSpellHistoryProfile then ns.RefreshSpellHistoryProfile() end
        -- Refresh unlock registrations for the new profile's window count
        ns.RegisterDMUnlock()
        -- The standalone timer is kept: set up again as built, or hidden while disabled
        if _saTimer then
            if c.standaloneTimer then SetupSATimer() else _saTimer:Hide() end
        elseif c.standaloneTimer then
            CreateSATimer()
        end
        -- Pre-create tooltip frame so first hover doesn't pay creation cost. This and the
        -- ticker below are the staggered build's closing steps, repeated here because
        -- this pass may have superseded that build before it reached them.
        EnsureTooltipFrame()
        -- Update tooltip scale
        if _ttFrame then
            local sc = (c.hoverTooltipScale or 100) / 100
            _ttFrame:SetScale(sc)
        end
        ns._DMReviveTicks()
    end
end)

-- The start values the copies were built from: nothing may read them again.
I._combatEndTime, I._inCombat, I._needsFinalRefresh = nil, nil, nil
I.broken = false
