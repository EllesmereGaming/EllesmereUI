if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Visibility.lua
--
--  Bar visibility outside the secure drivers: the managed visibility of the
--  data bars and extra bars, Hide Bar When Using Gamepad, the slot-export
--  addon compatibility and the Toggle Action Bar keybind. Loads after the
--  main file and reads it through ns only.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs = ipairs, pairs
local InCombatLockdown = InCombatLockdown
local RegisterAttributeDriver = RegisterAttributeDriver
local EFD = ns.EFD

local EAB, EAB_VTABLE, barButtons = ns.EAB, ns.EAB_VTABLE, ns.barButtons
local BAR_LOOKUP, ALL_BARS, EXTRA_BARS = ns.BAR_LOOKUP, ns.ALL_BARS, ns.EXTRA_BARS
local I = ns._internals
local BAR_CONFIG, barFrames, _fadeAlpha = I.BAR_CONFIG, I.barFrames, I._fadeAlpha
local dataBarFrames, extraBarHolders, blizzMovableHolders = I.dataBarFrames, I.extraBarHolders, I.blizzMovableHolders
local hoverStates, _quickKeybindState = I.hoverStates, I._quickKeybindState
local SafeEnableMouse, SafeEnableMouseMotionOnly = I.SafeEnableMouse, I.SafeEnableMouseMotionOnly
local ShouldQuickKeybindSurfaceBar, BuildVisibilityString = I.ShouldQuickKeybindSurfaceBar, I.BuildVisibilityString

-------------------------------------------------------------------------------
--  Managed Non-Secure Visibility: XP/Rep bars and extra bars such as
--  Micro/Bag/QueueStatus are not secure bar headers, so they need an
--  explicit runtime visibility pass whenever the player's
--  combat/group/target/mount state changes.
-------------------------------------------------------------------------------
function EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info)
    if not info then return false end
    if info.noManagedVisibility then return false end
    return info.isDataBar or (info.visibilityOnly and not info.isBlizzardMovable)
end

function EAB_VTABLE.ExtraBars.GetManagedNonSecureFrame(info)
    if not EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then return nil end
    if info.isDataBar then
        return dataBarFrames[info.key]
    end
    return info.frameName and _G[info.frameName] or nil
end

function EAB_VTABLE.ExtraBars.GetManagedNonSecureVisibilityState()
    local inCombat = EAB_VTABLE.ExtraBars._managedNonSecureInCombat
    if inCombat == nil then
        inCombat = InCombatLockdown()
    end
    local inRaid = IsInRaid and IsInRaid() or false
    local inGroup = IsInGroup and IsInGroup() or false
    return {
        inCombat = inCombat,
        inRaid = inRaid,
        inParty = inGroup and not inRaid,
    }
end

function EAB_VTABLE.ExtraBars.ShouldShowManagedNonSecureBar(s)
    if not s then return false end
    local vis = EAB.VisibilityCompat.Normalize(s)
    if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then
        return false
    end
    if s.enabled == false or s.alwaysHidden then return false end
    if EllesmereUI.CheckVisibilityOptions(s) then
        return false
    end
    local state = EAB_VTABLE.ExtraBars.GetManagedNonSecureVisibilityState()
    -- Multi-select path (nil = legacy single mode below; the dragonriding
    -- scalar also routes here, same predicate CheckVisibilityMode uses)
    if EllesmereUI and EllesmereUI.EvalVisibilityExtended then
        local ext = EllesmereUI.EvalVisibilityExtended(s, "barVisibility", state, EllesmereUI.VIS_CAPS_DEFAULT)
        if ext ~= nil then return ext end
    end
    if EllesmereUI and EllesmereUI.CheckVisibilityMode then
        return EllesmereUI.CheckVisibilityMode(vis, state)
    end
    return vis ~= "never"
end

-- Deferred completion for a petbattle unsuppress that lands during combat.
-- Wild pet battles hold combat lockdown for their whole duration and the
-- [petbattle] driver flips back to "show" at battle close, BEFORE
-- PLAYER_REGEN_ENABLED. The unsuppress below then defers on InCombatLockdown(), but the
-- driver never fires again (already "show") and every other caller uses reason
-- "visibility", a different key pair -- without this the micro menu/bag bar stays
-- hidden after every wild pet battle until a /reload.
--
-- One combat-queue entry; pending frames retry once combat drops. If a new
-- battle began before regen the pending set is dropped: suppression flags
-- are still set (re-suppressing keeps the ORIGINAL pre-battle shown state,
-- see `if not ffd[suppressKey]` below), so that battle's own close
-- transition completes or re-defers as usual.
-- do-block with block locals; helper exported on the vtable.
do
    local pending
    local function DrainPending()
        local p = pending
        pending = nil
        if not p then return end
        if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then
            return -- back in a battle; its close transition owns the rest
        end
        for f in pairs(p) do
            EAB_VTABLE.ExtraBars.SetManagedBlizzOwnedSuppressed(f, "petbattle", false)
        end
    end
    EAB_VTABLE.ExtraBars.QueuePetBattleUnsuppress = function(frame)
        pending = pending or {}
        pending[frame] = true
        ns.CombatQueue.Defer("PetBattleUnsuppress", DrainPending)
    end
end

function EAB_VTABLE.ExtraBars.SetManagedBlizzOwnedSuppressed(frame, reason, suppressed)
    if not frame then return end

    local ffd = EFD(frame)
    local suppressKey = (reason == "petbattle") and "suppressedByPetBattle" or "suppressedByVisibility"
    local shownKey = (reason == "petbattle") and "wasShownBeforePetBattle" or "wasShownBeforeVisibility"

    -- EditMode-managed frames (MicroMenuContainer, BagsBar): Hide()/Show()
    -- route through protected HideBase/ShowBase, blocked in combat. Issue the
    -- protected call only on a real state transition (a redundant re-Hide on
    -- an already-hidden frame still trips ADDON_ACTION_BLOCKED each refresh,
    -- and SPELLS_CHANGED fires often mid-rotation), never in combat --
    -- RefreshRuntimeVisibility re-runs from ApplyAll on PLAYER_REGEN_ENABLED
    -- and completes the deferred transition once lockdown clears.
    --
    -- InCombatLockdown() is the RIGHT gate here, not the protected-instance
    -- check: the restriction is "protected frame op blocked in combat", and
    -- the protected-instance check reports true for a whole keystone run (it
    -- exists for secret-value reads and Blizzard panel toggles), which would
    -- strand the micro menu/bag bar unsuppressed for the entire key.
    if suppressed then
        if not ffd[suppressKey] then
            ffd[shownKey] = frame:IsShown()
        end
        ffd[suppressKey] = true
        if frame:IsShown() then
            if not InCombatLockdown() then
                frame:Hide()
                ns.AB_ExtraCapsFor(frame)
            else
                ns._eabApplyDeferred = true
            end
        end
        return
    end

    if ffd[suppressKey] then
        if InCombatLockdown() then
            -- Keep bookkeeping and mark the combat-drop ApplyAll owed. That
            -- heals "visibility" (RefreshRuntimeVisibility re-issues it) but
            -- never "petbattle": ApplyAll only calls back with "visibility"
            -- and the driver already sits at "show", so that reason needs its
            -- own completion on the same event.
            ns._eabApplyDeferred = true
            if reason == "petbattle" then
                EAB_VTABLE.ExtraBars.QueuePetBattleUnsuppress(frame)
            end
            return
        end
        local wasShown = ffd[shownKey]
        ffd[suppressKey] = nil
        ffd[shownKey] = nil
        if wasShown and not frame:IsShown() then
            frame:Show()
            ns.AB_ExtraCapsFor(frame)
        end
    end
end

function EAB_VTABLE.ExtraBars.ApplyManagedNonSecureAlpha(info, frame, s)
    if not frame or not s or not frame:IsShown() then return end

    local hstate = hoverStates[info.key]
    local resting, hoverGated = EAB_VTABLE.Hover.RestingAlpha(info.key, s)
    if hoverGated then
        if hstate and hstate.isHovered then
            frame:SetAlpha(1)
            _fadeAlpha[frame] = 1
            hstate.fadeDir = "in"
        else
            frame:SetAlpha(resting)
            _fadeAlpha[frame] = resting
            if hstate then hstate.fadeDir = "out" end
        end
    else
        frame:SetAlpha(resting)
        _fadeAlpha[frame] = resting
        if hstate then hstate.fadeDir = nil end
    end
    ns.AB_FadeTwin(frame, _fadeAlpha[frame])
end

function EAB_VTABLE.ExtraBars.ApplyManagedMouse(frame, blizzOwnedVisibility, s, shouldShow)
    if not frame or not s then return end

    shouldShow = (shouldShow ~= false)
    -- Blizzard-owned frames (QueueStatusButton) manage their own mouse state;
    -- overriding it disables clicking/hovering after every visibility refresh.
    if blizzOwnedVisibility then
        return
    elseif s.mouseoverEnabled and s.clickThrough then
        SafeEnableMouseMotionOnly(frame, shouldShow)
    else
        SafeEnableMouse(frame, shouldShow and not s.clickThrough)
    end
end

function EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(info, frame, s, shouldShow, allowShow)
    if not frame or not s then return end

    -- Show/hide the holder BEFORE the Blizzard frame so the parent has
    -- valid screen coordinates when the child's Show() triggers Blizzard
    -- Layout callbacks that call GetCenter().
    if not info.isDataBar then
        local holder = extraBarHolders[info.key]
        if holder then
            if shouldShow then holder:Show() else holder:Hide() end
        end
    end

    if info.blizzOwnedVisibility then
        EAB_VTABLE.ExtraBars.SetManagedBlizzOwnedSuppressed(frame, "visibility", not shouldShow)
    elseif shouldShow then
        if allowShow ~= false then
            frame:Show()
        end
    else
        frame:Hide()
    end

    if shouldShow then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecureAlpha(info, frame, s)
    end
    EAB_VTABLE.ExtraBars.ApplyManagedMouse(frame, info.blizzOwnedVisibility, s, shouldShow)
end

function EAB_VTABLE.ExtraBars.ApplyManagedNonSecureVisibility(info)
    if not EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then return false, nil, nil end

    local s = EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars[info.key]
    local frame = EAB_VTABLE.ExtraBars.GetManagedNonSecureFrame(info)
    if not s or not frame then return false, frame, s end

    local shouldShow = EAB_VTABLE.ExtraBars.ShouldShowManagedNonSecureBar(s)

    -- Data bars always route through their update func: the hidden path ends
    -- in the same presentation call via BeginManagedDataBarUpdate, and bars
    -- with event arming (House Favor) need the call to disarm when hidden.
    if info.isDataBar and frame._updateFunc then
        frame._updateFunc()
    else
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(info, frame, s, shouldShow, not info.isDataBar)
    end

    return shouldShow, frame, s
end

function EAB_VTABLE.ExtraBars.RefreshManagedNonSecureVisibility()
    for _, info in ipairs(EXTRA_BARS) do
        if EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then
            EAB_VTABLE.ExtraBars.ApplyManagedNonSecureVisibility(info)
        end
    end
end

-------------------------------------------------------------------------------
--  Hide Bar When Using Gamepad (per bar, s.gamepadHideBar, default off; set
--  on the Global Settings Gamepad page).
--  "Using" means CONNECTED (EllesmereUI.PadConnected: gamepad support is on
--  and a controller is present), never the last-input device, so a touch of
--  the mouse cannot flicker a bar back. A hidden bar is hidden the way Never
--  hides it: its driver compiles to "hide" (BuildVisibilityString) and it
--  joins the Never set (ns.IsNeverBar). Two cached verdicts: EAB._padOn is the
--  device verdict, EAB._padHide the one every bar reader uses (_padOn, except
--  while Quick Keybind mode is open, which brings these bars back for binding).
--  Both only turn ON out of combat: the secure drivers cannot follow in
--  combat, and a still-visible bar in the Never set would skip its content
--  walks for the rest of the fight. EAB fields, not locals: read module-wide.
-------------------------------------------------------------------------------
-- Device edges arrive through EllesmereUI.WatchPad, one call per burst; a
-- repaint only when the verdict flips.
function EAB._PadFlush(on)
    if on == EAB._padOn then return end
    if InCombatLockdown() then
        -- Keep the old verdict; the PLAYER_REGEN_ENABLED ApplyAll re-reads it.
        EAB._padStale = true
        ns._eabApplyDeferred = true
        return
    end
    EAB._padOn = on
    EAB:RefreshRuntimeVisibility()
end

-- Watches the device edges while any bar has the toggle on (unwatched they
-- cost nothing) and re-reads the devices on the watch edge and after an edge
-- that landed in combat. Runs ahead of the Never map and the drivers, so every
-- settings path (options, profile swap, spec override) re-arms here, and once
-- from FinishSetup before its pre-lockdown driver pass. Quick Keybind mode's
-- open and close edges re-run it through RefreshRuntimeVisibility.
function EAB._PadSync()
    local bars = EAB.db.profile.bars
    local any = false
    for i = 1, #BAR_CONFIG do
        local s = bars[BAR_CONFIG[i].key]
        if s and s.gamepadHideBar == true then any = true break end
    end
    if any ~= (EAB._padArmed == true) then
        EAB._padArmed = any
        if any then
            EllesmereUI.WatchPad(EAB, EAB._PadFlush)
        else
            EllesmereUI.UnwatchPad(EAB)
        end
        EAB._padStale = any or nil
    end
    if not any then
        EAB._padOn = false
    elseif EAB._padStale and not InCombatLockdown() then
        EAB._padStale = nil
        EAB._padOn = EllesmereUI.PadConnected()
    end
    -- A Quick Keybind close taken in combat keeps the bars up until its regen
    -- FinishClose re-runs this.
    local hide = (EAB._padOn and not _quickKeybindState.open) or false
    if hide and not EAB._padHide and InCombatLockdown() then return end
    EAB._padHide = hide
end

function EAB:RefreshRuntimeVisibility()
    -- Secure driver/mouse writes below are per-site combat-gated; a run
    -- during combat leaves those writes unapplied, and the REGEN_ENABLED
    -- ApplyAll (gated on this flag) is the healer.
    if InCombatLockdown() then ns._eabApplyDeferred = true end
    -- Controller verdict first: the Never map and every driver below read it.
    EAB._PadSync()
    -- Every settings path that can change a bar's Never/disabled status runs
    -- through here (this is where drivers re-derive), so this is the single
    -- recompute site for the hard-dormancy map the event walks gate on.
    ns.RecomputeNeverBars()
    -- Bars that left the Never set with their buttons skipped at load get them
    -- now (state-based; see ns._eabBuildSkippedBars). ~200 override bindings
    -- are built from BAR_CONFIG x barButtons, so a revealed bar has none until
    -- UpdateKeybinds runs; it defers itself in combat.
    if ns._eabBuildSkippedBars() and _G._EAB_UpdateKeybinds then
        _G._EAB_UpdateKeybinds()
    end
    self:_RefreshSoftTargetGate()
    for _, info in ipairs(ALL_BARS) do
        local key = info.key
        local s = self.db.profile.bars[key]
        if not s then -- skip bars without settings (not yet initialized)
        elseif EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then
            EAB_VTABLE.ExtraBars.ApplyManagedNonSecureVisibility(info)
        else
        local frame = barFrames[key] or (info.isDataBar and dataBarFrames[key]) or (info.isBlizzardMovable and blizzMovableHolders[key]) or (extraBarHolders[key]) or (info.visibilityOnly and _G[info.frameName])
        if frame then
            local vis = s.barVisibility or "always"
            local isHidden = (vis == "never") or s.alwaysHidden
            -- Runtime "Toggle Action Bar" override (keybind-driven, NOT persisted):
            -- flips a bar between always-shown and hidden without touching the saved
            -- barVisibility. Only ever set for bars whose saved mode is always/never.
            local _visToggleOv = EAB._visOverride and EAB._visOverride[key]
            if _visToggleOv then
                vis = _visToggleOv
                isHidden = (_visToggleOv == "never")
            end
            if ShouldQuickKeybindSurfaceBar(s) and barFrames[key] and frame == barFrames[key] then
                if not InCombatLockdown() then
                    RegisterAttributeDriver(frame, "state-visibility", "show")
                    -- Keep the cache in sync (see EAB_UpdateQuickKeybindVisibility):
                    -- a stale cache makes QKB exit skip restoring the real driver.
                    frame._eabLastVisStr = "show"
                    frame:Show()
                    SafeEnableMouseMotionOnly(frame, true)
                end
                -- QuickKeybind temporarily surfaces managed action bars when
                -- runtime conditions hide them, but not when the user chose
                -- an explicit "Never" visibility mode.
            elseif isHidden then
                if not info.visibilityOnly and not InCombatLockdown() then
                    if frame._eabLastVisStr ~= "hide" then

                        frame._eabLastVisStr = "hide"
                        RegisterAttributeDriver(frame, "state-visibility", "hide")
                    end
                elseif info.visibilityOnly then
                    frame:Hide()
                    if info.blizzOwnedVisibility then
                        local bf = _G[info.frameName]
                        if bf then bf:Hide() end
                    end
                end
                if not InCombatLockdown() then
                    SafeEnableMouse(frame, false)
                end
            else
                if not info.visibilityOnly and not InCombatLockdown() then
                    local newStr
                    if _visToggleOv == "always" then
                        -- Forced-show via the toggle keybind: ignore the saved mode
                        -- (which may be "never") and any non-macro hide options.
                        newStr = BuildVisibilityString(info, s, "always")
                    -- Any is driver-owned, same reason as in ApplyCombatVisibility.
                    elseif s.visibilityMatch ~= "any" and EllesmereUI.CheckVisibilityOptionsNonMacro(s) then
                        newStr = "hide"
                    else
                        newStr = BuildVisibilityString(info, s)
                    end
                    if frame._eabLastVisStr ~= newStr then

                        frame._eabLastVisStr = newStr
                        RegisterAttributeDriver(frame, "state-visibility", newStr)
                    end
                end
                if not InCombatLockdown() then
                    if vis ~= "in_combat" and vis ~= "out_of_combat" and not s.combatShowEnabled then
                        -- Only Show frames without a state-visibility driver.
                        -- Frames with a driver (any _eabLastVisStr) are managed by the driver.
                        -- Movable wrappers are ours: restore them when their hide
                        -- condition clears. Blizzard still owns child visibility.
                        if not info.blizzOwnedVisibility and not frame._eabLastVisStr
                           and (not info.isBlizzardMovable
                                or EAB_VTABLE.ExtraBars.ShouldShowManagedNonSecureBar(s)) then
                            frame:Show()
                        end
                    end
                    if barFrames[key] and frame == barFrames[key] then
                        SafeEnableMouseMotionOnly(frame, not s.clickThrough or s.mouseoverEnabled)
                    elseif info.noManagedVisibility then
                        -- skip: Blizzard owns mouse state (e.g. QueueStatusButton)
                    elseif info.isBlizzardMovable or info.blizzOwnedVisibility then
                        SafeEnableMouse(frame, false)
                    else
                        SafeEnableMouse(frame, not s.clickThrough)
                    end
                end
                if info.isDataBar and frame._updateFunc then
                    frame._updateFunc()
                end
            end
        end
        end
    end
end

-------------------------------------------------------------------------------
--  Slot-export addon compatibility: that addon exports settings by automating
--  a PickupAction + PlaceAction on every populated action slot (60+ in a
--  row). With bars that hide empty slots or use conditional visibility, each
--  pickup/place forces a costly secure show/hide pass; back-to-back that
--  stalls the client for many seconds.
--
--  The cure is the "Visibility: Always + Always Show Buttons" config, so
--  while its window is open we apply exactly that to every bar (the same
--  change the options toggles make). Each bar's real visibility settings are
--  backed up to saved variables BEFORE overwriting and restored on close. The
--  backup is persisted, so a /reload or logout with the window open can never
--  strand the user on "always": EAB:OnInitialize calls RestoreMyslotBackup
--  unconditionally on the next login, before any bar is built.
-------------------------------------------------------------------------------
-- Settings swapped to force a bar fully visible. Listed once so backup and
-- overwrite stay in sync. do/end keeps this a block upvalue, not a chunk
-- local.
do
local MYSLOT_VIS_FIELDS = {
    "barVisibility", "alwaysHidden", "mouseoverEnabled", "mouseoverAlpha",
    "_savedBarAlpha", "combatShowEnabled", "combatHideEnabled", "alwaysShowButtons",
    -- An applied Visibility override REPLACES the whole setting (a "never"
    -- would keep the bar hidden through the import); captured, force-cleared
    -- and restored like every other field here.
    "visibilityOverride",
    -- Multi-select set: backed up by reference (the shared setter assigns a
    -- fresh table on every write, so the captured table never mutates) and
    -- restored/cleared like any other field.
    "visibilityModes",
    -- The Match Mode scalar is its own store key outside visibilityModes; a
    -- surviving "any" makes the compiler build from the emptied set.
    "visibilityMatch",
    -- Hide Bar When Using Gamepad would keep the bar hidden like Never.
    "gamepadHideBar",
}
-- The option LANES (target/enemy/mounted macro lanes AND the Lua-only
-- instance/housing/skyriding/resting/VEHICLE lanes) are enumerated by the
-- live EllesmereUI.VIS_OPT_KEYS list and swapped dynamically below: ANY lane
-- left standing hides the bar past the forced "always" -- the Lua-only ones
-- through CheckVisibilityOptionsNonMacro's bare "hide" driver, which runs
-- before the mode string is even consulted. Iterating the live list means a
-- future lane can never reopen this hole.
local function MyslotEachVisField(fn)
    for _, f in ipairs(MYSLOT_VIS_FIELDS) do fn(f) end
    local optKeys = EllesmereUI and EllesmereUI.VIS_OPT_KEYS
    if optKeys then
        for _, f in ipairs(optKeys) do fn(f) end
    end
end

-- Restore real visibility settings from the persisted backup, then clear it.
-- Safe to call anytime (no-op if no backup). NOT gated on that addon being
-- enabled, so it self-heals even if it was disabled since the backup was written.
function EAB:RestoreMyslotBackup()
    local backup = self.db and self.db.profile and self.db.profile._myslotVisBackup
    if not backup then return false end
    for key, saved in pairs(backup) do
        local s = self.db.profile.bars[key]
        if s then
            MyslotEachVisField(function(f) s[f] = saved[f] end)
        end
    end
    self.db.profile._myslotVisBackup = nil
    return true
end

function EAB:SetMyslotForceShow(on)
    on = not not on
    -- The persisted backup's presence IS the "are we forcing" state, so this
    -- survives /reload without a separate flag.
    local forcing = self.db.profile._myslotVisBackup ~= nil
    if on == forcing then return end

    if on then
        -- Capture real values and PERSIST the backup BEFORE overwriting, so the
        -- backup always exists if any field was changed (crash/reload-safe).
        local backup = {}
        for _, info in ipairs(BAR_CONFIG) do
            local s = self.db.profile.bars[info.key]
            if s then
                local saved = {}
                MyslotEachVisField(function(f) saved[f] = s[f] end)
                backup[info.key] = saved
            end
        end
        self.db.profile._myslotVisBackup = backup
        -- Overwrite to "always" + "always show buttons" (mirrors the options'
        -- ApplyVisibilityKey("always"), incl. restoring a mouseover bar's real
        -- alpha so it doesn't stay faded).
        for _, info in ipairs(BAR_CONFIG) do
            local s = self.db.profile.bars[info.key]
            if s then
                s.barVisibility = "always"
                -- A lingering multi-select set would stay authoritative over
                -- the forced "always"; the backup above already captured it.
                s.visibilityModes = nil
                s.visibilityMatch = nil
                -- EVERY option lane off, macro and Lua-only alike (the live
                -- VIS_OPT_KEYS list): visOnlyVehicle and friends otherwise
                -- keep feeding CheckVisibilityOptionsNonMacro a hide verdict
                -- that overrides the forced "always" at the driver site.
                local optKeys = EllesmereUI and EllesmereUI.VIS_OPT_KEYS
                if optKeys then
                    for _, f in ipairs(optKeys) do s[f] = nil end
                end
                s.alwaysHidden = false
                s.gamepadHideBar = false
                s.mouseoverEnabled = false
                -- Force FULL opacity, never the bar's real resting value: a
                -- hidden-until-hover bar rests at mouseoverAlpha 0 (and the
                -- Any-engine parks it at 0 with the real value stashed), and
                -- RefreshMouseover's disable path paints mouseoverAlpha
                -- verbatim -- restoring the stash here re-hid the very bar
                -- this swap exists to show. The backup holds both real
                -- values; restore puts them back untouched.
                s.mouseoverAlpha = 1
                s._savedBarAlpha = nil
                s.combatShowEnabled = false
                s.combatHideEnabled = false
                s.alwaysShowButtons = true
            end
        end
    else
        self:RestoreMyslotBackup()
    end

    -- Re-apply -- the same calls the options "Visibility"/"Always Show Buttons"
    -- toggles make, now that the real settings reflect the desired state.
    if not InCombatLockdown() then
        self:RefreshRuntimeVisibility()
        self:RefreshMouseover()
        self:ApplyCombatVisibility()
        for _, info in ipairs(BAR_CONFIG) do
            self:ApplyAlwaysShowButtons(info.key)
        end
    end
    EllesmereUI:RefreshPage()
end
end -- do: MYSLOT_VIS_FIELDS scope

do
    -- Wire the integration only when that addon is enabled: otherwise the
    -- watcher is never created and SetMyslotForceShow never runs, so no
    -- settings are swapped. The OnInitialize restore runs regardless, so a
    -- leftover backup from when it was enabled always self-heals.
    local function MyslotEnabled()
        if C_AddOns and C_AddOns.GetAddOnEnableState then
            return C_AddOns.GetAddOnEnableState("Myslot") > 0
        end
        return true
    end
    if MyslotEnabled() then
        -- Its main window comes from its LibStub library's MainFrame; hook
        -- show/hide to toggle the force-show override. No-op if absent.
        local hooked = false
        local function TryHookMyslot()
            if hooked or not LibStub then return hooked end
            local lib = LibStub:GetLibrary("Myslot-5.0", true)
            local frame = lib and lib.MainFrame
            if not frame then return false end
            hooked = true
            frame:HookScript("OnShow", function() EAB:SetMyslotForceShow(true) end)
            frame:HookScript("OnHide", function() EAB:SetMyslotForceShow(false) end)
            if frame:IsShown() then EAB:SetMyslotForceShow(true) end
            return true
        end
        local watcher = ns.TakeShell()
        watcher:RegisterEvent("PLAYER_LOGIN")
        watcher:RegisterEvent("ADDON_LOADED")
        watcher:SetScript("OnEvent", function()
            if TryHookMyslot() then watcher:UnregisterAllEvents() end
        end)
    end
end

-------------------------------------------------------------------------------
--  "Toggle Action Bar" visibility keybind: per-bar keybind that flips bar UI
--  between active/shown and dormant/hidden at RUNTIME. Action bindings stay
--  live; barVisibility is never written, so the toggle does not persist
--  (/reload restores saved state).
--  Meaningful only when saved visibility is "always" or "never", and only
--  out of combat (changing a secure frame's state-visibility driver is
--  combat-blocked). The keybind itself IS saved per-bar (s.toggleVisKey) and
--  re-applied on login.
--
--  Bindings are keyed by the PRESSED KEY, not the bar, so one key on several
--  bars toggles them as a synced group: a press hides every bound bar that
--  is shown, the next press shows them all.
-------------------------------------------------------------------------------

-- Toggle every bar bound to `key` as a group. If any participant is currently
-- shown, hide them all; otherwise show them all. Only bars whose saved mode is
-- "always"/"never" participate. Runtime-only -- never writes barVisibility.
function EAB:ToggleVisKey(key)
    if InCombatLockdown() or not key then return end
    local participants, anyShown = {}, false
    for _, info in ipairs(ALL_BARS) do
        local s = self.db.profile.bars[info.key]
        if s and s.toggleVisKey == key then
            local saved = s.barVisibility or "always"
            if saved == "always" or saved == "never" then
                participants[#participants + 1] = info.key
                -- A controller-hidden bar counts as hidden (as Never does), so
                -- the first press shows it.
                local eff = (self._visOverride and self._visOverride[info.key])
                    or ((self._padHide and s.gamepadHideBar == true) and "never") or saved
                if eff == "always" then anyShown = true end
            end
        end
    end
    if #participants == 0 then return end
    local target = anyShown and "never" or "always"
    self._visOverride = self._visOverride or {}
    for _, bk in ipairs(participants) do
        self._visOverride[bk] = target
    end
    self:RefreshRuntimeVisibility()
end

-- Drop a bar's runtime toggle override so its saved visibility takes effect
-- again (called when the visibility dropdown changes in options).
function EAB:ClearVisToggleOverride(barKey)
    if self._visOverride then self._visOverride[barKey] = nil end
end

-- Rebuild override bindings from the saved per-bar keys: one pooled button
-- per UNIQUE key (a key shared by several bars drives all of them). A key is
-- only bound if at least one bar using it has a saved always/never mode, so
-- a shared key never dead-overrides the player's normal binding. Binding
-- APIs are combat-protected, so defer to PLAYER_REGEN_ENABLED in combat.
function EAB:RebuildVisToggleBindings()
    if InCombatLockdown() then
        ns.CombatQueue.Defer("RebuildVisToggleBindings", function()
            EAB:RebuildVisToggleBindings()
        end)
        return
    end
    -- Unique keys that have at least one participating (always/never) bar.
    local keys, seen = {}, {}
    for _, info in ipairs(ALL_BARS) do
        local s = self.db.profile.bars[info.key]
        local k = s and s.toggleVisKey
        if k and k ~= "" and not seen[k] then
            local saved = s.barVisibility or "always"
            if saved == "always" or saved == "never" then
                seen[k] = true
                keys[#keys + 1] = k
            end
        end
    end
    -- Clear every pooled button's binding, then (re)assign one per unique key.
    self._visToggleBtnPool = self._visToggleBtnPool or {}
    for _, btn in ipairs(self._visToggleBtnPool) do
        ClearOverrideBindings(btn)
    end
    for i, k in ipairs(keys) do
        local btn = self._visToggleBtnPool[i]
        if not btn then
            btn = CreateFrame("Button", "EUIVisToggleKeyBtn" .. i, UIParent)
            btn:Hide()
            self._visToggleBtnPool[i] = btn
        end
        local thisKey = k
        btn:SetScript("OnClick", function() EAB:ToggleVisKey(thisKey) end)
        SetOverrideBindingClick(btn, true, k, btn:GetName())
    end
end

function EAB:ApplyClickThroughForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end

    -- Data bars
    local dataFrame = dataBarFrames[barKey]
    if dataFrame then
        EAB_VTABLE.ExtraBars.ApplyManagedMouse(dataFrame, false, s, dataFrame:IsShown())
        return
    end

    -- Extra bars (MicroBar, BagBar, QueueStatus)
    for _, info in ipairs(EXTRA_BARS) do
        if info.key == barKey and not info.isDataBar and not info.isBlizzardMovable then
            if info.blizzOwnedVisibility then
                local holder = extraBarHolders[barKey]
                if holder then SafeEnableMouse(holder, false) end
                local bf = _G[info.frameName]
                if bf then SafeEnableMouse(bf, true) end
            else
                local frame = _G[info.frameName]
                if frame then SafeEnableMouse(frame, not s.clickThrough) end
            end
            return
        end
    end

    -- Action bars
    local frame = barFrames[barKey]
    if not frame then return end
    local buttons = barButtons[barKey]
    if not buttons then return end

    local enable = ShouldQuickKeybindSurfaceBar(s) or not s.clickThrough
    -- When click-through is on but mouseover is enabled, keep mouse motion
    -- so OnEnter/OnLeave still fire for hover fade.
    local motionOnly = not enable and s.mouseoverEnabled
    -- Bar frame only needs mouse motion (for hover detection); clicks pass through
    -- to the buttons or to frames behind the bar.
    SafeEnableMouseMotionOnly(frame, enable or motionOnly)
    local showEmpty = s.alwaysShowButtons
    if showEmpty == nil then showEmpty = true end
    local info = BAR_LOOKUP[barKey]
    if info and info.isStance then showEmpty = false end
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn then
            -- Don't re-enable mouse on invisible (parked) empty slots
            local isInvisible = not showEmpty and ns._eabParked(btn)
            if not isInvisible then
                if enable then
                    SafeEnableMouse(btn, true)
                elseif motionOnly then
                    SafeEnableMouseMotionOnly(btn, true)
                else
                    SafeEnableMouse(btn, false)
                end
            end
        end
    end
end

function EAB:UpdateHousingVisibility()
    -- Fully gated: with no bar using a non-macro visibility option and no
    -- managed non-secure bar, this sync can change nothing -- yet it's
    -- invoked on every soft-target flip, which churns constantly near NPCs.
    -- Flag maintained by _RefreshSoftTargetGate.
    if not self._anyNonMacroVis then return end
    -- Coalesced: an event burst schedules ONE deferred sync, not one per event.
    if self._housingVisPending then return end
    self._housingVisPending = true
    -- Defer to next frame to avoid taint from secure execution paths
    -- (e.g. CameraOrSelectOrMoveStop triggering PLAYER_MOUNT_DISPLAY_CHANGED)
    C_Timer.After(0, function()
        self._housingVisPending = nil
        if InCombatLockdown() then return end
        if _quickKeybindState.open then return end
        -- Check non-macro visibility options here. Secure frames still use the
        -- state driver for target/enemy conditions, but mounted-like druid
        -- forms are also handled here to cover cases [mounted] does not match.
        local function ShouldHideNonMacro(s)
            if not s then return false end
            -- An applied Visibility override replaces the whole setting, the shared option
            -- lanes included, and BuildVisibilityString already compiles it into a
            -- constant. Checked before the two raw lane reads below, which would otherwise
            -- keep hiding the bar on a lane the override took over.
            if EllesmereUI.VisOverrideValue(s) then return false end
            -- Under Any the driver string already carries both halves (Show lanes as
            -- disjuncts, Hide lanes as leading gates, the Lua-only ones resolved at build
            -- time with their own combat escape hatch), and the rebuild below refreshes
            -- it on exactly these events. A literal "hide" here would add nothing and
            -- would veto the whole disjunction on a lane that is not even firing.
            if s.visibilityMatch == "any" then return false end
            if s.visHideNoTarget then
                -- [noexists] in the state driver covers the basic has-target
                -- check even in combat. Out of combat also hide when a soft
                -- target is the only "target": macro conditionals count
                -- softinteract/softenemy/softfriend as "target exists" while
                -- UnitExists("target") doesn't, so test those tokens directly.
                if not UnitExists("target") and (UnitExists("softinteract") or UnitExists("softenemy") or UnitExists("softfriend")) then return true end
            end
            if s.visHideMounted then
                -- Regular mounts are handled entirely by the secure "[mounted] hide"
                -- clause, which self-updates even in combat. Druid travel/flight forms
                -- don't match [mounted] and fall back to this non-secure clobber, and a
                -- bare "hide" is a dead constant once written (the shift-out edge lands
                -- in combat, where this handler bails), so the marker lets the write
                -- site bake a combat escape hatch into the string instead.
                if not (IsMounted and IsMounted())
                    and EllesmereUI.IsPlayerMountedLike() then
                    return "combathide"
                end
            end
            -- Every other Lua-only option (both instance lanes, both housing lanes, both
            -- skyriding-mount lanes) comes from the shared evaluator, so a lane added
            -- there is live here too instead of silently going stale on the next zone or
            -- mount edge. skipMountAxis keeps the driver's [mounted]/[nomounted] clauses
            -- authoritative, leaving the narrower shapeshift check above as the only
            -- mount handling on this path. The skyriding-mount lanes can flip into
            -- combat like the form case, so the evaluator flags them "mountaxis".
            if EllesmereUI and EllesmereUI.CheckVisibilityOptionsNonMacro then
                local nonMacro = EllesmereUI.CheckVisibilityOptionsNonMacro(s, true)
                if nonMacro == "mountaxis" then return "combathide" end
                if nonMacro then return true end
            end
            return false
        end

        for _, info in ipairs(ALL_BARS) do
            local key = info.key
            local s = self.db.profile.bars[key]
            if s then
                if EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then
                    EAB_VTABLE.ExtraBars.ApplyManagedNonSecureVisibility(info)
                else
                    local frame = barFrames[key] or (info.isDataBar and dataBarFrames[key]) or (info.isBlizzardMovable and blizzMovableHolders[key]) or (extraBarHolders[key]) or (info.visibilityOnly and _G[info.frameName])
                if frame then
                    -- Secure action bar frames use the state driver for
                    -- target/enemy options (mounted-like forms handled in
                    -- ShouldHideNonMacro). Non-secure frames (data bars,
                    -- extra bars, visibility-only) need the full check: no driver.
                    local isSecure = not info.visibilityOnly and not info.isDataBar and not info.isBlizzardMovable and barFrames[key]
                    local shouldHide = isSecure and ShouldHideNonMacro(s) or (not isSecure and EllesmereUI.CheckVisibilityOptions(s))
                    -- Runtime "Toggle Action Bar" override wins over the saved mode and
                    -- non-macro hide checks, as in RefreshRuntimeVisibility: otherwise
                    -- any event routed here (target/group/mount/housing) re-applies the
                    -- saved visibility and re-shows a bar the player toggled off.
                    -- Secure managed bars only.
                    local _visToggleOv = isSecure and self._visOverride and self._visOverride[key]
                    if _visToggleOv == "never" then
                        if frame._eabLastVisStr ~= "hide" then
                            frame._eabLastVisStr = "hide"
                            RegisterAttributeDriver(frame, "state-visibility", "hide")
                        end
                    elseif _visToggleOv == "always" then
                        local ovStr = BuildVisibilityString(info, s, "always")
                        if frame._eabLastVisStr ~= ovStr then
                            frame._eabLastVisStr = ovStr
                            RegisterAttributeDriver(frame, "state-visibility", ovStr)
                        end
                    elseif shouldHide then
                        if isSecure then
                            -- "combathide" (druid mount-like form, skyriding-mount lanes): a
                            -- lane that can flip INTO combat must not be a dead constant, so
                            -- hide out of combat and fall back to the real driver in combat
                            -- (mode, prefixes and any [mounted] clause keep working there).
                            -- Never / always-hidden bars keep the plain hide.
                            local hideStr = "hide"
                            if shouldHide == "combathide" and not s.alwaysHidden
                                and (s.barVisibility or "always") ~= "never" then
                                hideStr = "[nocombat] hide; " .. BuildVisibilityString(info, s)
                            end
                            if frame._eabLastVisStr ~= hideStr then

                                frame._eabLastVisStr = hideStr
                                RegisterAttributeDriver(frame, "state-visibility", hideStr)
                            end
                        elseif info.blizzOwnedVisibility then
                            local bf = _G[info.frameName]
                            if bf then
                                EFD(bf).visWasShown = bf:IsShown()
                                bf:Hide()
                            end
                        else
                            frame:Hide()
                        end
                    elseif not s.alwaysHidden and (s.barVisibility or "always") ~= "never" then
                        if isSecure then
                            local newStr = BuildVisibilityString(info, s)
                            if frame._eabLastVisStr ~= newStr then

                                frame._eabLastVisStr = newStr
                                RegisterAttributeDriver(frame, "state-visibility", newStr)
                            end
                        elseif info.blizzOwnedVisibility then
                            local bf = _G[info.frameName]
                            if bf and EFD(bf).visWasShown then
                                bf:Show()
                            end
                            if bf then EFD(bf).visWasShown = nil end
                        -- Restore our movable wrapper, respecting all remaining
                        -- visibility gates (including pet battles).
                        elseif not info.isBlizzardMovable
                           or EAB_VTABLE.ExtraBars.ShouldShowManagedNonSecureBar(s) then
                            frame:Show()
                        end
                        -- Data bars may need to re-hide (max level, max renown, etc.)
                        if info.isDataBar and frame._updateFunc then
                            frame._updateFunc()
                        end
                    end
                end
                end
            end
        end
    end)
end

