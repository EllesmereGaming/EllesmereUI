if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_DamageMeters_State.lua
--
--  Header button layout, per-window settings and position, the shared
--  combat and segment state, unlock registration and the session events.
--  Reads the earlier Damage Meters files through ns and ns._dmInternals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._dmInternals
-- EllesmereUIDamageMeters.lua or an earlier EUI_DamageMeters_*.lua file
-- failed to load.
if not I or I.broken then return end
I.broken = true

local EUI = EllesmereUI

local DB, DM_TYPE_ICONS, DM_TYPE_NAMES = I.DB, I.DM_TYPE_ICONS, I.DM_TYPE_NAMES
local GetHeaderH, HOME_DEFAULTS, MAX_WINDOWS = I.GetHeaderH, I.HOME_DEFAULTS, I.MAX_WINDOWS
local MIN_H, MIN_W, SetCombatEndTime = I.MIN_H, I.MIN_W, I.SetCombatEndTime
local SetCurViewFrozenDur, SetInEncounter = I.SetCurViewFrozenDur, I.SetInEncounter
local SetInCombat, SetNeedsFinalRefresh = I.SetInCombat, I.SetNeedsFinalRefresh

-- Header icon visibility (hide until title bar hovered)
local function ResetButtonHidden(cfg)
    cfg = cfg or DB()
    return cfg.hideResetButton == true
end

local function GetHeaderLayoutButtons(W, cfg)
    local buttons = {}
    if not W or not W.hdrBtns then return buttons end
    local hideReset = ResetButtonHidden(cfg)
    for _, btn in ipairs(W.hdrBtns) do
        if btn ~= W.resetBtn or not hideReset then
            buttons[#buttons + 1] = btn
        end
    end
    return buttons
end
-- The same count without building the list (the title fit runs on every paint).
function ns.DMHeaderButtonCount(W, cfg)
    if not W or not W.hdrBtns then return 0 end
    local hideReset = ResetButtonHidden(cfg)
    local n = 0
    for _, btn in ipairs(W.hdrBtns) do
        if btn ~= W.resetBtn or not hideReset then n = n + 1 end
    end
    return n
end

local function LayoutHeaderButtons(W, cfg, iconSz)
    if not W or not W.header or not W.hdrBtns then return end
    local btnPad = ns.DMHdrIconPad()
    local lift = ns.DMHdrLift(cfg and cfg.hdrHeight)
    local layoutBtns = GetHeaderLayoutButtons(W, cfg)
    for bi, btn in ipairs(layoutBtns) do
        if iconSz then
            btn:SetSize(iconSz, iconSz)
            -- Inset stock art follows the new size.
            if btn._hdrIcon and btn._hdrIcon._hdrArt then ns.DMSeatHdrArt(btn._hdrIcon, iconSz) end
        end
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", W.header, "RIGHT", -(iconSz * (bi - 1) + btnPad * bi + 2), lift)
    end
end

local function SetHeaderButtonsShown(W, shown)
    if not W or not W.hdrBtns then return end
    local hideReset = ResetButtonHidden()
    for _, btn in ipairs(W.hdrBtns) do
        if btn == W.resetBtn and hideReset then
            btn:Hide()
            btn:SetAlpha(0)
            btn:EnableMouse(false)
        else
            btn:Show()
            btn:SetAlpha(shown and 1 or 0)
            btn:EnableMouse(shown)
        end
    end
    -- Title reserves room for the icons and must re-fit whenever hide-until-hover shows/hides them
    W._hdrIconsShown = shown and true or false
    if W.FitTitle then W.FitTitle() end
end

local function EnsureHeaderButtonsHoverHooks(W)
    if not W or W._hdrHideUntilHoverHooksInstalled then return end
    W._hdrHideUntilHoverHooksInstalled = true

    local function Show()
        local cfg = DB()
        if not cfg.hdrMouseoverIcons then return end
        SetHeaderButtonsShown(W, true)
    end

    local function MaybeHide()
        local cfg = DB()
        if not cfg.hdrMouseoverIcons then return end
        if not W.header then return end
        C_Timer.After(0, function()
            if not W.header then return end
            if W.header:IsMouseOver() then return end
            SetHeaderButtonsShown(W, false)
        end)
    end

    if W.header then
        W.header:HookScript("OnEnter", Show)
        W.header:HookScript("OnLeave", MaybeHide)
    end
    if W.hdrBtns then
        for _, btn in ipairs(W.hdrBtns) do
            btn:HookScript("OnEnter", Show)
            btn:HookScript("OnLeave", MaybeHide)
        end
    end
end

local function ApplyHeaderButtonsHoverVisibility(W, cfg)
    if not W or not W.header or not W.hdrBtns then return end
    EnsureHeaderButtonsHoverHooks(W)
    if cfg and cfg.hdrMouseoverIcons then
        SetHeaderButtonsShown(W, W.header:IsMouseOver())
    else
        SetHeaderButtonsShown(W, true)
    end
end

-- Per-window DB accessor
local function WinDB(idx)
    local cfg = DB()
    if not cfg.windows then cfg.windows = {} end
    if not cfg.windows[idx] then
        cfg.windows[idx] = {
            position = nil,
            width = 375,
            height = 150,
        }
    end
    return cfg.windows[idx]
end

-- Applies a window's saved position. Two formats: unlock format { point, relPoint, x, y } (relative
-- to UIParent, from unlock mode's Save & Exit); legacy format { x = left, y = top } (TOPLEFT offset from UIParent's BOTTOMLEFT, from header drags outside unlock mode)
ns.ApplyWinPosition = function(frame, wdb, idx)
    -- The resize grip owns the frame's anchor while a drag is in flight. Even
    -- with the format converted above, re-anchoring mid-resize would fight the
    -- grip's live SetPoint for a frame; leave it alone until the drag ends.
    -- ns._windows, not the _windows local: that local is declared BELOW this
    -- function, so referencing it here would read a nil global and the guard
    -- would silently never fire.
    local W = ns._windows and ns._windows[idx]
    if W and W.resizing then return end
    local pos = wdb.position
    -- Unlock-anchored window (e.g. one meter window anchored to another): the
    -- anchor system owns the position ENTIRELY -- the standard Build* guard
    -- (see the ERB/CDM siblings), but stricter: never seed from the stored
    -- absolute either. A window anchored long ago carries an arbitrarily
    -- stale absolute (wherever it sat before being anchored), and re-applying
    -- it on every login/reload flashed the window at that spot for the first
    -- frames until the login anchor pass landed (field report). With no
    -- geometry yet the window simply stays UNPLACED (renders nothing) for
    -- those frames instead; a genuinely absent anchor target is what the
    -- fallback-anchor feature covers.
    if EUI.IsUnlockAnchored and EUI.IsUnlockAnchored("EDM_Win" .. idx) then
        return
    end
    frame:ClearAllPoints()
    if pos and pos.point then
        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    elseif pos and pos.x and pos.y then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
    else
        -- Default: 20px from bottom-right of screen, cascading per window
        local uiW = UIParent:GetWidth()
        local fw, fh = frame:GetSize()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT",
            uiW - fw - 20 + (idx - 1) * 20, fh + 20 - (idx - 1) * 20)
    end
end

-- Bookmarks are shared across all windows (stored in dm.bookmarks)
local function GetBookmarks()
    local cfg = DB()
    if not cfg.bookmarks then
        cfg.bookmarks = {}
        for _, dt in ipairs(HOME_DEFAULTS) do
            cfg.bookmarks[#cfg.bookmarks + 1] = dt
        end
    end
    return cfg.bookmarks
end

-- ipairs over the bookmarks this client offers, keeping each one's index in
-- the saved list: a type not offered here (WoW Forever's Threat in a profile
-- brought elsewhere) gets no card, and its bookmark stays saved.
local function NextHomeType(list, i)
    i = i + 1
    local v = list[i]
    while v ~= nil and not DM_TYPE_NAMES[v] do
        i = i + 1
        v = list[i]
    end
    if v ~= nil then return i, v end
end
function ns.DMHomeTypes(list)
    return NextHomeType, list, 0
end


-- Shared state
local _inCombat = false
local _inEncounter = false       -- true between ENCOUNTER_START and ENCOUNTER_END
I.inCombatSetters[#I.inCombatSetters + 1] = function(v) _inCombat = v end
I.inEncounterSetters[#I.inEncounterSetters + 1] = function(v) _inEncounter = v end
local _windows = {}  -- array of active window tables
ns._windows = _windows
-- Windows taken out of use (a closed window, or one past a profile's window
-- count), kept whole with their frames: ns.DMAcquireWindow brings them back.
ns._dmParked = {}

-- Hotkey toggle state. Deliberately not persisted: a window hidden by accident would
-- otherwise stay gone after a reload with nothing on screen explaining why. Every place
-- that can show one of the toggled frames consults this flag, because the shared
-- visibility dispatcher, the standalone timer ticker and the spell history rebuild all
-- re-show their frames on their own schedule. Options mode and unlock mode still win.
ns._toggleHidden = false

ns._DM_TYPE_NAMES = DM_TYPE_NAMES
ns._DM_TYPE_ICONS = DM_TYPE_ICONS

-- Unlock mode registration: each window is a first-class unlock element (EDM_Win1..N) via the
-- core mover system (drag, exact X/Y, anchor-to-element, width/height matching). Index-based
-- keys; deletion re-keys anchor/match links via ShiftIndexedAnchorKeys (see W.Destroy). Called
-- on login, window add/remove, and profile swap; slots beyond the live count unregister.
ns.RegisterDMUnlock = function()
    if not EUI or not EUI.RegisterUnlockElements or not EUI.MakeUnlockElement then return end
    local MK = EUI.MakeUnlockElement
    local function winOf(key)
        local i = tonumber(string.match(key or "", "(%d+)$"))
        return i and _windows[i], i
    end
    local elements = {}
    for i = 1, #_windows do
        elements[#elements + 1] = MK({
            key   = "EDM_Win" .. i,
            label = "Damage Meter " .. i,
            group = "Damage Meters",
            order = 650 + i,
            getFrame = function(key)
                local w = winOf(key)
                return w and w.frame
            end,
            getSize = function(key)
                local w, idx = winOf(key)
                if w and w.frame then return w.frame:GetWidth(), w.frame:GetHeight() end
                local wdb = idx and WinDB(idx)
                return wdb and wdb.width or 375, wdb and wdb.height or 150
            end,
            -- A textured window border's reach past the window's edges, so size
            -- matching lines up with what is on screen. Mirrors ns.ApplyWindowBorder:
            -- the border hugs an overlay target set out by the Width/Height
            -- Offsets, and its top starts below the header when the header is
            -- left out. Each side clamped at 0. nil under a stock look or solid.
            getMatchPad = function()
                if ns.DMBlizz() then return nil end
                local cfg = DB()
                local size = tonumber(cfg.windowBorderSize) or 0
                local texture = cfg.windowBorderTexture or "solid"
                if size <= 0 or texture == "solid" then return nil end
                local color = cfg.windowBorderColor
                local l, r, t, b = EUI.BorderReach(size, texture, nil, nil, nil, nil, nil, nil,
                    EUI.BorderPx(cfg.windowBorderSizePx, size, texture), nil, color and color.a or 1)
                if not l then return nil end
                local ox = tonumber(cfg.windowBorderOffsetX) or 0
                local oy = tonumber(cfg.windowBorderOffsetY) or 0
                l, r, b = l + ox, r + ox, b + oy
                if cfg.windowBorderIncludeHeader ~= false then
                    t = t + oy
                else
                    t = t + oy - GetHeaderH()
                end
                local pw = (l > 0 and l or 0) + (r > 0 and r or 0)
                local ph = (t > 0 and t or 0) + (b > 0 and b or 0)
                if pw <= 0 and ph <= 0 then return nil end
                return pw, ph
            end,
            setWidth = function(key, newW)
                local w, idx = winOf(key)
                if not w or not w.frame then return end
                local PPu = EUI.PP
                local v = math.max(MIN_W, newW or MIN_W)
                v = PPu and PPu.Snap and PPu.Snap(v) or math.floor(v + 0.5)
                w.frame:SetWidth(v)
                if EUI._unlockActive then WinDB(idx).width = math.floor(v + 0.5) end
                if w.FitTitle then w.FitTitle() end
            end,
            setHeight = function(key, newH)
                local w, idx = winOf(key)
                if not w or not w.frame then return end
                local PPu = EUI.PP
                local v = math.max(MIN_H, newH or MIN_H)
                v = PPu and PPu.Snap and PPu.Snap(v) or math.floor(v + 0.5)
                w.frame:SetHeight(v)
                if EUI._unlockActive then WinDB(idx).height = math.floor(v + 0.5) end
            end,
            savePos = function(key, point, relPoint, x, y)
                local w, idx = winOf(key)
                if not idx then return end
                WinDB(idx).position = { point = point, relPoint = relPoint or point, x = x, y = y }
                if w and w.ApplyPosition and not EUI._unlockActive then w.ApplyPosition() end
            end,
            loadPos = function(key)
                local _, idx = winOf(key)
                local pos = idx and WinDB(idx).position
                if not pos then return nil end
                -- Return a copy: callers may hold or rebase the table, and the
                -- live DB entry must never be mutated through it
                if pos.point then
                    return { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y }
                end
                if pos.x and pos.y then
                    -- Legacy drag format: TOPLEFT offset from UIParent's BOTTOMLEFT
                    return { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = pos.x, y = pos.y }
                end
                return nil
            end,
            clearPos = function(key)
                local _, idx = winOf(key)
                if idx then WinDB(idx).position = nil end
            end,
            applyPos = function(key)
                local w = winOf(key)
                if w and w.ApplyPosition then w.ApplyPosition() end
            end,
        })
    end
    -- Standalone combat timer rides the master toggle (factory defined in EUI_DamageMeters_Timer.lua, resolved via ns)
    if DB().standaloneTimer and ns.MakeSATimerUnlockElement then
        elements[#elements + 1] = ns.MakeSATimerUnlockElement(MK)
    end
    -- Icon History is owned by the spell-history file, but participates in the
    -- same first-class unlock system as the meter windows and combat timer.
    local spellHistory = DB().spellHistory
    if spellHistory and spellHistory.iconEnabled and ns.MakeIconHistoryUnlockElement then
        elements[#elements + 1] = ns.MakeIconHistoryUnlockElement(MK)
    end
    EUI:RegisterUnlockElements(elements, "EllesmereUIDamageMeters")
    -- Drop registrations for window slots beyond the live count and optional
    -- elements while disabled (symmetric across profile swaps).
    if EUI.UnregisterUnlockElement then
        for i = #_windows + 1, MAX_WINDOWS do
            EUI:UnregisterUnlockElement("EDM_Win" .. i)
        end
        if not DB().standaloneTimer then
            EUI:UnregisterUnlockElement("EDM_CombatTimer")
        end
        if not (spellHistory and spellHistory.iconEnabled) then
            EUI:UnregisterUnlockElement("EDM_IconHistory")
        end
    end
    -- Windows paint their border before they register (build, profile swap,
    -- new window), so ApplyWindowBorder's pad report found no element yet:
    -- record each window's pad now, or the first border edit after login
    -- would only be recorded, never re-pushed.
    if EUI.MatchPadChanged then
        for i = 1, #_windows do EUI.MatchPadChanged("EDM_Win" .. i) end
    end
end
local _combatEndTime = 0       -- GetTime() at combat end; control-flow sentinel (ticker teardown / freeze-once)
local _needsFinalRefresh = false
local _curViewFrozenDur = 0    -- final Current-session duration, pinned when combat ends
I.combatEndTimeSetters[#I.combatEndTimeSetters + 1] = function(v) _combatEndTime = v end
I.needsFinalRefreshSetters[#I.needsFinalRefreshSetters + 1] = function(v) _needsFinalRefresh = v end
I.curViewFrozenDurSetters[#I.curViewFrozenDurSetters + 1] = function(v) _curViewFrozenDur = v end
-- Tracks feigned GUIDs since C_DamageMeter can give a feign a valid deathRecapID, which the
-- deathRecapID > 0 filter would treat as a real death. Cleared at combat/encounter start and on
-- 0 HP (confirmed real death); UnitIsFeignDeath can remain true through a feign-then-die transition so it can't be used to clear safely.
local _feignDeathGUIDs = {}

-- In-combat death time placeholders, keyed by deathRecapID (NeverSecret, unique
-- per death). deathTimeSeconds is SECRET while in combat, so a Deaths row read
-- 0:00 until combat ended; the row's first appearance is stamped with the plain
-- live session duration instead (accurate to one refresh interval) and the
-- engine's exact value replaces it as soon as it reads plain. Wiped at every
-- combat start with the feign cache.
local _deathStamps = {}

-- Switch a window to a segment (sessionID) or session type (Current/Overall); windows with
-- syncSegments switch together. On ns not local: CreateDMWindow is at Lua 5.1's 60-upvalue limit.
function ns.ApplySegmentSelection(W, sessionType, sessionID)
    local targets = { W }
    if WinDB(W.idx).syncSegments then
        targets = {}
        for _, w in ipairs(_windows) do
            if WinDB(w.idx).syncSegments then targets[#targets + 1] = w end
        end
    end
    for _, w in ipairs(targets) do
        if sessionID then
            w.curSessionID = sessionID
        else
            w.curSession = sessionType
            WinDB(w.idx).curSession = sessionType
            w.curSessionID = nil
        end
        if w.CloseSource then w.CloseSource() end
        w.Refresh()
    end
end

-- Combat start: switch windows viewing a past segment back to Current (per-window autoCurrentOnCombat option); Overall windows untouched.
function ns.AutoCurrentOnCombat()
    for _, w in ipairs(_windows) do
        if w.curSessionID and WinDB(w.idx).autoCurrentOnCombat then
            w.curSessionID = nil
            w.curSession = Enum.DamageMeterSessionType.Current
            WinDB(w.idx).curSession = Enum.DamageMeterSessionType.Current
            if w.CloseSource then w.CloseSource() end
            w.Refresh()
        end
    end
end

-- Single source of truth for the "Current" session timer (window and standalone both read this).
-- Live, it reads the SAME session the bars render so a server-side roll (chain-pull boss) resets
-- it in lockstep with no separate clock to drift; once combat ends every caller is gated off and returns the value pinned at the freeze instant.
local function GetCurrentViewDuration()
    if _inCombat or _needsFinalRefresh then
        if C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
            local d = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current)
            if type(d) == "number" and not (issecretvalue and issecretvalue(d)) then
                _curViewFrozenDur = d   -- keep the pin warm with the last live value
                return d
            end
        end
        return _curViewFrozenDur or 0
    end
    -- Not live: show the pinned final duration, falling back to the API if unpinned (fresh load/reload with retained session data)
    if _curViewFrozenDur and _curViewFrozenDur > 0 then return _curViewFrozenDur end
    if C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
        local d = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current)
        if type(d) == "number" and not (issecretvalue and issecretvalue(d)) then return d end
    end
    return 0
end

-- Stop the live timer AND pin its final value atomically at every combat-end freeze site. The d
-- >= pin guard keeps the last live value if Current already rolled to a fresh (smaller) session; the pin resets to 0 at every combat START so it can't carry across combats.
local function FreezeCombat(ts)
    SetCombatEndTime(ts or GetTime())
    if C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds then
        local d = C_DamageMeter.GetSessionDurationSeconds(Enum.DamageMeterSessionType.Current)
        if type(d) == "number" and not (issecretvalue and issecretvalue(d)) and d >= (_curViewFrozenDur or 0) then
            SetCurViewFrozenDur(d)
        end
    end
end

local _raidUnits, _partyUnits = {}, {}
for i = 1, 40 do _raidUnits[i] = "raid" .. i end
for i = 1, 4 do _partyUnits[i] = "party" .. i end

local function IsGroupInCombat()
    if UnitAffectingCombat("player") then return true end
    if IsInRaid() then
        local n = GetNumGroupMembers()
        for i = 1, n do
            if UnitAffectingCombat(_raidUnits[i]) then return true end
        end
    elseif IsInGroup() then
        local n = GetNumGroupMembers() - 1  -- party units exclude player
        for i = 1, n do
            if UnitAffectingCombat(_partyUnits[i]) then return true end
        end
    end
    return false
end

-- Clear cached feign GUIDs before filtering so real deaths after Feign Death are not hidden by stale entries
local function CleanupFeignCache()
    if not next(_feignDeathGUIDs) then return end
    -- Build GUID -> unit map for the group so iteration below runs O(N+M) instead of O(N*M)
    local present = {}
    local function note(unit)
        local g = UnitGUID(unit)
        if g and not (issecretvalue and issecretvalue(g)) then present[g] = unit end
    end
    note("player")
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do note(_raidUnits[i]) end
    elseif IsInGroup() then
        for i = 1, GetNumGroupMembers() - 1 do note(_partyUnits[i]) end
    end
    -- HP == 0 confirms a real death; Feign Death keeps actual HP, and UnitIsFeignDeath can linger after a feign-then-die transition
    for guid in pairs(_feignDeathGUIDs) do
        local unit = present[guid]
        if not unit then
            _feignDeathGUIDs[guid] = nil  -- player left the group: untrackable
        else
            local hp = UnitHealth(unit)
            if hp and not (issecretvalue and issecretvalue(hp)) and hp <= 0 then
                _feignDeathGUIDs[guid] = nil
            end
        end
    end
end

local StopSharedTicker   -- forward declaration (defined in EUI_DamageMeters_Lifecycle.lua)
local StartSharedTicker  -- forward declaration (defined in EUI_DamageMeters_Lifecycle.lua)
local _sharedTicker      -- the live refresh ticker (assigned in EUI_DamageMeters_Lifecycle.lua)
I.stopSharedTickerSetters[#I.stopSharedTickerSetters + 1] = function(v) StopSharedTicker = v end
I.startSharedTickerSetters[#I.startSharedTickerSetters + 1] = function(v) StartSharedTicker = v end
I.sharedTickerSetters[#I.sharedTickerSetters + 1] = function(v) _sharedTicker = v end
local _targetsCache = {} -- Damage Done targets map (BuildAllPlayerTargets): { key = sessionKey, map = { [playerName] = sorted targets } }

-- Keystone start: wipe data so Overall = this dungeon run
-- Keystone end: auto-swap windows from Current to Overall (if enabled)
local instanceFrame = CreateFrame("Frame")
instanceFrame:RegisterEvent("CHALLENGE_MODE_START")
instanceFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
instanceFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
instanceFrame:RegisterEvent("DAMAGE_METER_RESET")
instanceFrame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
instanceFrame:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
instanceFrame:SetScript("OnEvent", function(_, event)
    if event == "CHALLENGE_MODE_START" then
        if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
            C_DamageMeter.ResetAllCombatSessions()
        end
        SetCombatEndTime(0); SetCurViewFrozenDur(0)
        -- Auto-swap: Overall -> Current on key start
        for _, w in ipairs(_windows) do
            local wdb2 = WinDB(w.idx)
            if wdb2.autoSwapMythic and w.curSession == Enum.DamageMeterSessionType.Overall then
                w.curSession = Enum.DamageMeterSessionType.Current
                wdb2.curSession = Enum.DamageMeterSessionType.Current
                w.curSessionID = nil
            end
            -- Default on M+ Start: switch this window to its configured meter type
            if wdb2.mythicStartDMType and w.SetDMType then
                w.SetDMType(wdb2.mythicStartDMType)
            end
            w.Refresh()
        end
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        -- Auto-swap: Current -> Overall on key completion
        for _, w in ipairs(_windows) do
            local wdb2 = WinDB(w.idx)
            if wdb2.autoSwapMythic and not w.curSessionID and w.curSession == Enum.DamageMeterSessionType.Current then
                w.curSession = Enum.DamageMeterSessionType.Overall
                wdb2.curSession = Enum.DamageMeterSessionType.Overall
                w.curSessionID = nil
                w.Refresh()
            end
        end
    elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
        -- Blizzard created/updated a combat session (boss kill, combat end); "Current" may now point
        -- elsewhere. Invalidate cache for the next ticker refresh; force an immediate refresh only out of combat (the shared ticker covers combat at refreshRate).
        -- Readable session data changed: refresh the breakdown resolver's
        -- class:spec -> guid snapshot (ns route: this closure predates the
        -- resolver's definition).
        if ns._SnapshotSourceKeys and not InCombatLockdown() then
            ns._SnapshotSourceKeys()
        end
        if not instanceFrame._sessionPending then
            instanceFrame._sessionPending = true
            C_Timer.After(0.1, function()
                instanceFrame._sessionPending = nil
                for _, w in ipairs(_windows) do
                    -- Data-only: session updates change DATA never STYLE. _barCacheKey gates the
                    -- per-bar restyle; nilling it here made every death restyle all bars at ticker rate (the dominant profiled cost). Style invalidation belongs to the settings/palette appliers only.
                    w._cachedTargets = nil
                end
                if not _inCombat then
                    for _, w in ipairs(_windows) do w.Refresh() end
                elseif not _sharedTicker then
                    -- Ticker died from a teardown race; a new server session is our cue to revive it
                    StartSharedTicker()
                end
            end)
        end
    elseif event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
        -- Authoritative "Current just rolled" signal (boss-pull reset trigger, catches rolls the
        -- ticker-only model could miss between polls). Can fire continuously during combat, so a
        -- debounced repaint per burst (each paying a session-fetch C call, multiplied across windows) would dwarf the ticker's rate; in combat we only invalidate
        -- caches (ENCOUNTER_START/REGEN_DISABLED already force immediate repaints at segment
        -- boundaries, ticker covers the rest). Out of combat, one debounced repaint keeps rolls prompt.
            for _, w in ipairs(_windows) do
                -- Data caches only -- style never changes on a session roll (see SESSION_UPDATED note above)
                w._cachedTargets = nil
            end
            if _inCombat or _needsFinalRefresh then
                if not _sharedTicker then StartSharedTicker() end
            elseif not instanceFrame._curSessionPending then
                instanceFrame._curSessionPending = true
                C_Timer.After(0.1, function()
                    instanceFrame._curSessionPending = nil
                    for _, w in ipairs(_windows) do w.Refresh() end
                end)
            end
    elseif event == "DAMAGE_METER_RESET" then
        -- Blizzard cleared all session data (auto-reset CVar, manual reset, etc.)
        SetCombatEndTime(0); SetCurViewFrozenDur(0)
        if _targetsCache then wipe(_targetsCache) end
        for _, w in ipairs(_windows) do
            w._barCacheKey = nil
            w._cachedTargets = nil
            w.Refresh()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Zone transition (load screen); WoW does not re-fire PLAYER_REGEN_DISABLED here, so
        -- combat state must be re-derived per branch below or the session-derived timer would blank.
        if UnitAffectingCombat("player") then
            -- Still personally in combat after the load (e.g. reload on a target dummy, or zoning into an active fight): restore the live timer.
            SetInCombat(true)
            SetCombatEndTime(0)
            SetNeedsFinalRefresh(false)
            if not _sharedTicker then StartSharedTicker() end
        elseif IsGroupInCombat() then
            -- Not personally in combat but the group is (reload while dead/spectating): poll like the
            -- teammate pre-warm rather than asserting _inCombat -- SharedRefreshTick self-terminates the instant the group leaves combat, so a stale flag can't tick forever.
            SetInCombat(false)
            SetCombatEndTime(0)
            SetNeedsFinalRefresh(true)
            if not _sharedTicker then StartSharedTicker() end
        else
            -- Out of combat: force-end. Covers hearth/teleport, leaving a BG/arena, abandoning an M+ key, any other zone-out.
            local wasLive = _inCombat or _needsFinalRefresh or _inEncounter
            SetInEncounter(false)
            SetInCombat(false)
            SetNeedsFinalRefresh(false)
            StopSharedTicker()
            -- Freeze (pin) the timer if combat was still live
            if wasLive and _combatEndTime == 0 then FreezeCombat() end
        end
        -- Refresh after zone-in to pick up visibility/data changes (window 1's
        -- refresh also applies the standalone timer's visibility)
        for _, w in ipairs(_windows) do
            w._barCacheKey = nil
        end
        C_Timer.After(0.5, function()
            for _, w in ipairs(_windows) do w.Refresh() end
        end)
    end
end)

I._combatEndTime, I._deathStamps = _combatEndTime, _deathStamps
I._feignDeathGUIDs, I._inCombat = _feignDeathGUIDs, _inCombat
I._needsFinalRefresh, I._targetsCache, I._windows = _needsFinalRefresh, _targetsCache, _windows
I.ApplyHeaderButtonsHoverVisibility = ApplyHeaderButtonsHoverVisibility
I.CleanupFeignCache, I.FreezeCombat = CleanupFeignCache, FreezeCombat
I.GetBookmarks, I.GetCurrentViewDuration = GetBookmarks, GetCurrentViewDuration
I.IsGroupInCombat, I.LayoutHeaderButtons, I.WinDB = IsGroupInCombat, LayoutHeaderButtons, WinDB
I.broken = false
