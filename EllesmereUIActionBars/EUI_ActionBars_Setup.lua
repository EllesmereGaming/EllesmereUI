if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Setup.lua
--
--  Edit Mode icon count sync and EAB:FinishSetup.
--  Loads after EUI_ActionBars_Init.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs, type, pcall = ipairs, pairs, type, pcall
local wipe, tinsert = wipe, table.insert
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After
local RegisterAttributeDriver = RegisterAttributeDriver
local EFD = ns.EFD

local EAB, EAB_VTABLE, barButtons = ns.EAB, ns.EAB_VTABLE, ns.barButtons
local I = ns._internals
local SetActionBarCVar = I.SetActionBarCVar
local LatchMasqueBarOwnership = I.LatchMasqueBarOwnership
local _dragState, _gridState, _quickKeybindState = I._dragState, I._gridState, I._quickKeybindState
local ALL_BARS, BAR_CONFIG, BAR_LOOKUP, FadeTo = I.ALL_BARS, I.BAR_CONFIG, I.BAR_LOOKUP, I.FadeTo
local ShouldQuickKeybindSurfaceBar, STOCK_BAR_DISPOSAL = I.ShouldQuickKeybindSurfaceBar, I.STOCK_BAR_DISPOSAL
local StopFade = I.StopFade
local hiddenParent = I.hiddenParent
local _controllerButtons, ActionButtonController = I._controllerButtons, I.ActionButtonController
local InitShowGridMonitor, SetShowGridInsecure, SHOWGRID = I.InitShowGridMonitor, I.SetShowGridInsecure, I.SHOWGRID
local BAR_SLOT_OFFSETS, barFrames, blizzMovableHolders = I.BAR_SLOT_OFFSETS, I.barFrames, I.blizzMovableHolders
local buttonToBar, dataBarFrames, extraBarHolders = I.buttonToBar, I.dataBarFrames, I.extraBarHolders
local GetEABFlyout, HideBlizzardBars = I.GetEABFlyout, I.HideBlizzardBars
local SecureSetupHandler_Execute = I.SecureSetupHandler_Execute
local SecureSetupHandler_PrepareRefs = I.SecureSetupHandler_PrepareRefs
local SyncPagingAlpha = I.SyncPagingAlpha
local SetupBar = I.SetupBar
local ComputeBarLayout, LayoutBar = I.ComputeBarLayout, I.LayoutBar
local AttachHoverHooks, hoverStates = I.AttachHoverHooks, I.hoverStates
local BuildVisibilityString = I.BuildVisibilityString
local _bindState, ApplyKeyDownCVar, UpdateKeybinds = I._bindState, I.ApplyKeyDownCVar, I.UpdateKeybinds
local IsHouseEditorActive, OnGridChange = I.IsHouseEditorActive, I.OnGridChange
local ApplyAll = I.ApplyAll
local RegisterWithUnlockMode, RestoreBarPositions = I.RegisterWithUnlockMode, I.RestoreBarPositions

-------------------------------------------------------------------------------
--  Edit Mode Icon Count Sync: when EUI's configured icon count for a bar
--  exceeds Edit Mode's setting, update the Edit Mode layout data via
--  C_EditMode.SaveLayouts so Blizzard's own code applies the higher count
--  (untainted). Avoids writing numButtonsShowable directly, which taints.
-------------------------------------------------------------------------------
local function SyncEditModeIconCounts()
    if InCombatLockdown() then return end
    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then return end
    -- A missing shared helper must not abort visual setup before proc-glow
    -- events are registered. Skip the sync rather than save layouts without
    -- the shared preset merge and restore tracking.
    if type(EllesmereUI.EditModeOpen) ~= "function"
       or type(EllesmereUI.EditModeLayoutsForSave) ~= "function"
       or type(EllesmereUI.NoteEditModeSetting) ~= "function" then return end

    -- Never write while Blizzard's Edit Mode is open. The manager keeps its OWN copy of
    -- layoutInfo for the whole session and pushes that copy whole on Save, so a write from here
    -- is either discarded by the next Save or discards the edit in progress. This runs again on
    -- the next options close, so skipping costs nothing.
    if EllesmereUI.EditModeOpen() then return end

    -- SaveLayouts replaces the character's ENTIRE layout set (the client holds it and writes it
    -- at logout), so the payload has to have the shape Blizzard always passes: the presets
    -- first, then the saved layouts, with activeLayout an index into that merged list. When
    -- the presets cannot be resolved, skip the write entirely rather than send the short list.
    local layoutInfo, numPresets = EllesmereUI.EditModeLayoutsForSave()
    if not layoutInfo then return end

    -- Build desired icon counts keyed by systemIndex (all bars are system 0).
    -- MainMenuBar has no system; MainActionBar is system=0 systemIndex=1.
    local desired = {}
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local s = EAB.db and EAB.db.profile and EAB.db.profile.bars[info.key]
            local euiCount = s and (s.overrideNumIcons or s.numIcons) or info.count
            if not euiCount or euiCount < 1 then euiCount = info.count end
            local blizzBar = _G[info.blizzFrame]
            if blizzBar and blizzBar.system == 0 and blizzBar.systemIndex then
                desired[blizzBar.systemIndex] = euiCount
            end
            if info.nativeMainBar and _G.MainActionBar then
                local mab = _G.MainActionBar
                if mab.system == 0 and mab.systemIndex then
                    desired[mab.systemIndex] = euiCount
                end
            end
        end
    end

    -- Setting 2 = NumIcons. GetSettingValue(bar, 2) returns the actual count
    -- (6-12), so the raw layout value appears to be the actual count too.
    local ICON_COUNT_SETTING = 2
    local changed = false

    -- HideBarArt setting: force to 1 (hidden) on all action bar layouts
    local HIDE_BAR_ART_SETTING = Enum and Enum.EditModeActionBarSetting
        and Enum.EditModeActionBarSetting.HideBarArt

    -- Check ALL saved layouts so switching never reverts to fewer icons. The merged-in presets
    -- are read-only (SaveLayouts drops edits to them), so they are carried through untouched.
    -- Each row is noted for Uninstall EUI: a raised count is put back when its earlier value is
    -- known, and bar art is noted every time (shown is Blizzard's default, the fallback for an
    -- account older than the record).
    for layoutIndex, layout in ipairs(layoutInfo.layouts) do
        if layoutIndex > numPresets and type(layout.systems) == "table" then
            for _, sysInfo in ipairs(layout.systems) do
                if sysInfo.system == 0 and sysInfo.systemIndex and type(sysInfo.settings) == "table" then
                    local want = desired[sysInfo.systemIndex]
                    for _, s in ipairs(sysInfo.settings) do
                        if want and s.setting == ICON_COUNT_SETTING and s.value < want then
                            EllesmereUI.NoteEditModeSetting(layout, sysInfo, s.setting, s.value, want)
                            s.value = want
                            changed = true
                        end
                        if HIDE_BAR_ART_SETTING and s.setting == HIDE_BAR_ART_SETTING then
                            EllesmereUI.NoteEditModeSetting(layout, sysInfo, s.setting, s.value, 1, 0)
                            if s.value ~= 1 then
                                s.value = 1
                                changed = true
                            end
                        end
                    end
                end
            end
        end
    end

    if changed then
        C_EditMode.SaveLayouts(layoutInfo)
    end
end

function EAB:SyncEditModeIcons()
    if InCombatLockdown() then
        -- Keyed: repeated calls in one combat collapse into one idempotent sync.
        ns.CombatQueue.Defer("SyncEditModeIcons", SyncEditModeIconCounts)
        return
    end
    SyncEditModeIconCounts()
end

-- The actual bar creation, positioning, and event registration.
function EAB:FinishSetup()
    -- Run-once: reachable from OnEnable AND OnFirstLogin, and a module
    -- disable/re-enable dispatches OnEnable again. Everything here using
    -- HookScript (hover hooks on ~140 buttons, flyout OnHide, stock-bar
    -- OnShow) stacks a second permanent handler on re-entry -- HookScript
    -- can't be unhooked -- and the pet/stance event frames would duplicate.
    if ns._eabFinishSetupDone then return end
    ns._eabFinishSetupDone = true

    -- Masque group and AddButton registration are one-time for the session, so
    -- lock ownership to the current profile snapshot before any layout or style
    -- path asks ns.MasqueOwnsBar().
    LatchMasqueBarOwnership()
    for _, info in ipairs(BAR_CONFIG) do
        if ns._masqueBarsLatched[info.key] == true then
            ns.InitializeMasque()
            break
        end
    end

    local function DoSetupSecure()
        -- Non-protected setup: create bar frames, compute layout, register events.
        -- Protected operations (SetParent, SetPoint on Blizzard buttons) are
        -- dispatched through the secure handler so they work even in combat.

        local inCombat = InCombatLockdown()

        if not inCombat then
            -- Normal load: use the direct path (all protected ops are fine)
            HideBlizzardBars()
            for _, info in ipairs(BAR_CONFIG) do
                SetupBar(info, false)
                LayoutBar(info.key)
            end
            -- Register secure handler refs now that buttons exist
            SecureSetupHandler_PrepareRefs()
            -- Apply the current page to MainBar buttons. The state driver
            -- evaluated during CreateBarFrame (before buttons existed), so
            -- buttons still have their initial action=slot from
            -- GetOrCreateButton; recalculate using the actual current page.
            local mbFrame = barFrames["MainBar"]
            if mbFrame then
                local curPage = tonumber(mbFrame:GetAttribute("state-page")) or 1
                local mbBtns = barButtons["MainBar"]
                if mbBtns then
                    for i, btn in ipairs(mbBtns) do
                        btn:SetAttribute("action", i + (curPage - 1) * 12)
                    end
                end
            end
            RestoreBarPositions()
        else
            -- Combat reload: non-protected setup only; secure handler does the rest.
            -- Stock bar disposal (including ActionBarParent) already happened at
            -- file load time. OverrideActionBar is fully Blizzard-owned.
            SetActionBarCVar("SHOW_MULTI_ACTIONBAR_1", "1", "EllesmereUIActionBars")
            SetActionBarCVar("SHOW_MULTI_ACTIONBAR_2", "1", "EllesmereUIActionBars")
            SetActionBarCVar("SHOW_MULTI_ACTIONBAR_3", "1", "EllesmereUIActionBars")
            SetActionBarCVar("SHOW_MULTI_ACTIONBAR_4", "1", "EllesmereUIActionBars")

            -- Create bar frames and buttons (no protected ops)
            for _, info in ipairs(BAR_CONFIG) do
                SetupBar(info, true)
            end
            -- Register secure handler refs now that buttons exist
            SecureSetupHandler_PrepareRefs()

            -- Compute layout and encode for secure handler
            local layoutData = {}
            local barFrameData = {}
            local positions = EAB.db.profile.barPositions or {}

            for _, info in ipairs(BAR_CONFIG) do
                local key = info.key
                local buttons = barButtons[key]
                local s = EAB.db.profile.bars[key]
                local slotOffset = BAR_SLOT_OFFSETS[key] or 0
                if buttons then
                    local btnLayout, frameW, frameH = ComputeBarLayout(key)
                    local pos = positions[key]
                    local point = pos and pos.point or "CENTER"
                    local relPoint = pos and pos.relPoint or "CENTER"
                    local px = pos and pos.x or 0
                    local py = pos and pos.y or 0
                    tinsert(barFrameData, { key = key, w = frameW, h = frameH,
                        point = point, relPoint = relPoint, x = px, y = py,
                        hidden = (s and (s.alwaysHidden or s.enabled == false)) and true or false })

                    for i, btnData in pairs(btnLayout) do
                        local btn = buttons[i]
                        if btn and btn._secureSlotIdx then
                            local actionSlot = 0
                            if key == "MainBar" then
                                -- For MainBar, actionSlot encodes the button index (1-12)
                                actionSlot = i
                            elseif info.isPetBar then
                                -- PetActionButtons use their index (1-10) as their slot ID
                                actionSlot = i
                            elseif not info.isStance then
                                actionSlot = slotOffset + i
                            end
                            layoutData[btn._secureSlotIdx] = {
                                barKey = key,
                                x = btnData.x, y = btnData.y,
                                w = btnData.w, h = btnData.h,
                                show = btnData.show,
                                actionSlot = actionSlot,
                            }
                        end
                    end
                end
            end

            -- Dispatch all protected operations through the secure handler
            SecureSetupHandler_Execute(layoutData, barFrameData)
        end

        -- Both broadcasters are killed at file-load time (top of file), and
        -- the per-button ACTIONBAR_UPDATE_COOLDOWN registration is stripped at
        -- button creation, so this dispatcher is the ONLY owner of the cooldown
        -- pipeline -- swipes, desaturation and on-CD alpha all ride it. It used
        -- to be set up inside the out-of-combat branch above, which left a
        -- /reload taken in combat with no cooldown events at all for the rest
        -- of the session. It registers events and builds closures, nothing
        -- protected, so both paths get it here, after their buttons exist.
        -- DEFERRED one tick: ~1,600 lines of closure construction + ~25 event
        -- registrations, pure insecure and self-guarded (_dispatcherSetup).
        -- C_Timer callbacks fire on the first frame AFTER the loading screen,
        -- so this leaves the shared login watchdog budget (one combat-sized
        -- budget for the whole suite's OnEnable chain) without losing the
        -- combat-legal window: nothing here is combat-blocked. One tick with
        -- no cooldown events is invisible during the loading screen.
        C_Timer_After(0, function() EAB:SetupEventDispatcher() end)

        -- Visual styling: defer visuals to out-of-combat if needed.
        local function DoVisuals()
            ApplyAll()
            -- Reapply unlock-mode positions + anchor chains now that bars exist.
            -- (The EUI_UnlockMode hook on EAB.ApplyAll doesn't fire because
            -- ApplyAll is a local function, not on the addon table.)
            if EllesmereUI._applySavedPositions then
                -- NOTE: C_Timer callbacks do not run during the loading screen, so on a
                -- combat reload this fires after lockdown has re-engaged. The in-window
                -- pass lives in EUI_UnlockMode's synchronous PLAYER_LOGIN handler; this
                -- delayed pass is the settle correction once element sizes stabilize.
                C_Timer_After(1.5, EllesmereUI._applySavedPositions)
            end
            ApplyKeyDownCVar()
            self:SyncEditModeIcons()
            self:HookProcGlow()
            self:ScanExistingProcs()
            -- Re-scan after a delay to catch procs that Blizzard populates late
            C_Timer_After(2, function() self:ScanExistingProcs() end)
            -- Clear stale count text when a slot becomes empty. The central
            -- dispatcher's ACTIONBAR_SLOT_CHANGED branch handles this for our
            -- fresh EABButton frames; the UpdateCount hook covers Blizzard
            -- buttons that receive events natively.
            for _, info in ipairs(BAR_CONFIG) do
                if not info.isStance and not info.isPetBar then
                    local btns = barButtons[info.key]
                    if btns then
                        for _, b in ipairs(btns) do
                            if not b._eabCountFixed then
                                b._eabCountFixed = true
                                if b.UpdateCount then
                                    hooksecurefunc(b, "UpdateCount", function(self)
                                        if not self:HasAction() then
                                            self.Count:SetText("")
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end
            end
        end

        if InCombatLockdown() then
            ns.CombatQueue.Defer("FinishSetupVisuals", function()
                C_Timer_After(0.1, DoVisuals)
            end)
        else
            C_Timer_After(0.1, DoVisuals)
        end
    end

    DoSetupSecure()

    -- Override keybinds (custom-paged/flyout click routes) + saved "Toggle
    -- Action Bar" keys: engine binding-table rebuilds, protected. On a combat
    -- /reload InCombatLockdown() is already true here and this loading-screen
    -- execution is the ONLY place the rebuild is legal, so it stays in-window.
    -- Out of combat there is no window to protect, and the whole suite's
    -- OnEnable chain shares this one watchdog budget (AB is first in it):
    -- move the rebuild to its own execution so it neither dies at the tail
    -- of the bar build nor starves the modules behind it. If a pull starts
    -- in the one-frame gap, both callees bail and re-arm on regen -- the
    -- same contract the combat path already lives on.
    -- loginBuilt: the login loading screen's restore pass (PLAYER_ENTERING_WORLD
    -- below) only checks the signature after this build instead of forcing another.
    if InCombatLockdown() then
        if UpdateKeybinds() then _bindState.loginBuilt = true end
        EAB:RebuildVisToggleBindings()
    else
        C_Timer_After(0, function()
            if UpdateKeybinds() then _bindState.loginBuilt = true end
            EAB:RebuildVisToggleBindings()
        end)
    end

    -- Initialize the showgrid monitor on ActionButton1 so that when
    -- Blizzard changes its showgrid attribute (e.g. during combat spell
    -- drag), the change propagates to all our managed buttons.
    InitShowGridMonitor()

    -- Register ACTIONBAR_SHOWGRID/HIDEGRID on the controller itself
    -- so the secure showgrid state stays in sync with game events.
    -- Note: RunAttribute cannot be called from Lua; use SetAttribute to
    -- trigger the secure _onattributechanged snippet instead.
    local _gridSurfacedBars = {}
    local _gridRestorePending = false
    local function RestoreGridSurfacedBars()
        _gridRestorePending = false
        if InCombatLockdown() then
            -- Restore swallowed by combat (drag ended after combat began):
            -- flag the regen ApplyAll so the stomped drivers still re-derive.
            ns._eabApplyDeferred = true
            return
        end
        -- If something is still on the cursor (spell swap), don't restore yet
        if GetCursorInfo() then return end
        for key in pairs(_gridSurfacedBars) do
            local info = BAR_LOOKUP[key]
            local s = EAB.db.profile.bars[key]
            local frame = barFrames[key]
            if info and s and frame then
                if s.mouseoverEnabled then
                    -- The drag has fully ended (cursor cleared, checked above). If
                    -- the cursor is still over this bar, the spell was dropped here
                    -- (or you're just hovering it), so keep it shown and let the
                    -- normal OnLeave fade it on real exit. Otherwise hide as before.
                    local state = hoverStates[key]
                    if frame:IsMouseOver() then
                        if state then state.isHovered = true; state.fadeDir = "in" end
                        StopFade(frame, s._savedBarAlpha or 1)
                        if key == "MainBar" then SyncPagingAlpha(s._savedBarAlpha or 1) end
                    else
                        if state then state.isHovered = false; state.fadeDir = "out" end
                        StopFade(frame, 0)
                        if key == "MainBar" then SyncPagingAlpha(0) end
                    end
                end
            end
        end
        wipe(_gridSurfacedBars)
        -- Re-derive every driver through the single recompute site instead of
        -- a local predicate: the surface condition above admits option-driven
        -- bars (visHideMounted etc.) whose barVisibility is "always", and a
        -- restore predicate maintained separately drifted and left exactly
        -- those bars stuck on "show" until a settings toggle or /reload. The
        -- surface stomp syncs _eabLastVisStr, so this compare-and-register
        -- pass re-registers precisely the stomped bars.
        EAB:RefreshRuntimeVisibility()
    end
    -- Registering events on a frame stamps it with the EventRegistrations forbidden
    -- aspect, and the restricted environment refuses frames carrying any aspect. The
    -- controller wraps buttons and executes snippets, so its events must live on a
    -- plain sidecar listener, never on the controller.
    -- Mirror Blizzard's lockActionBars setting onto the controller so the
    -- secure OnDragStart wrapper can tell a real pickup from a dead gesture
    -- (see the wrapper in RegisterButtonWithController). Attribute, not a
    -- chunk local: the snippet
    -- can only read attributes anyway.
    ns.EABSyncBarsLocked = function()
        -- No _eabApplyDeferred here, unlike the widget-writing guards: nothing
        -- else needs re-applying, and PLAYER_REGEN_ENABLED re-syncs this.
        if InCombatLockdown() then return end
        local locked
        if Settings and Settings.GetValue then
            local ok, v = pcall(Settings.GetValue, "lockActionBars")
            -- v ~= nil, not just ok: this seeds during FinishSetup, which can
            -- run before the setting is registered. Accepting nil as "false"
            -- would skip the CVar fallback and seed a LOCKED bar as unlocked.
            if ok and v ~= nil then locked = v and true or false end
        end
        if locked == nil and C_CVar and C_CVar.GetCVarBool then
            locked = C_CVar.GetCVarBool("lockActionBars") and true or false
        end
        local v = locked and 1 or 0
        -- Guarded: SetAttribute re-runs the controller's _onattributechanged
        -- snippet, and CVAR_UPDATE is a firehose at login.
        if ActionButtonController:GetAttribute("eab-barslocked") ~= v then
            ActionButtonController:SetAttribute("eab-barslocked", v)
        end
    end

    EAB._abcEvents = ns.TakeShell()

    -- Controller-side grid appliers, run from the settle in ns.EABQueueGrid.
    _gridState.showFns[#_gridState.showFns + 1] = function()
        -- Cancel any pending restore (swap case: drop + immediate pickup)
        _gridRestorePending = false
        if not InCombatLockdown() then
            for btn in pairs(_controllerButtons) do
                SetShowGridInsecure(btn, true, SHOWGRID.GAME_EVENT)
            end
            -- Temporarily surface bars hidden by conditional visibility
            -- (combat-only, target-only, etc.) so the user can place spells.
            for _, info in ipairs(BAR_CONFIG) do
                if not info.isStance and not info.isPetBar then
                    local s = EAB.db.profile.bars[info.key]
                    local frame = barFrames[info.key]
                    if s and frame and not s.alwaysHidden
                       and not (EAB._padHide and s.gamepadHideBar == true) then
                        local vis = s.barVisibility or "always"
                        -- Any visibility option at all counts: a bar the player cannot
                        -- see is a bar they cannot drop a spell onto, so surfacing one
                        -- that did not strictly need it is the harmless direction.
                        local hasCondition = vis ~= "always" and vis ~= "never"
                        if not hasCondition and EllesmereUI.VisHasAnyOption then
                            hasCondition = EllesmereUI.VisHasAnyOption(s)
                        end
                        if hasCondition then
                            _gridSurfacedBars[info.key] = true
                            RegisterAttributeDriver(frame, "state-visibility", "show")
                            -- Keep the cache in sync with the stomp (same
                            -- class as the QuickKeybind surface fix): a
                            -- stale cache holding the real string makes
                            -- every later refresh compare equal and skip
                            -- re-registering, leaving the bar stuck on
                            -- "show" until a settings toggle or /reload.
                            frame._eabLastVisStr = "show"
                            frame:Show()
                        end
                        -- Mouseover bars: force alpha to 1 during drag
                        if s.mouseoverEnabled then
                            _gridSurfacedBars[info.key] = true
                            StopFade(frame, 1)
                        end
                    end
                end
            end
        end
    end

    _gridState.hideFns[#_gridState.hideFns + 1] = function()
        if not InCombatLockdown() then
            for btn in pairs(_controllerButtons) do
                SetShowGridInsecure(btn, false, SHOWGRID.GAME_EVENT)
            end
            -- Defer restore: spell swaps fire HIDEGRID then SHOWGRID
            -- in rapid succession. Deferring lets the next SHOWGRID
            -- cancel the restore so bars stay visible.
            if next(_gridSurfacedBars) then
                _gridRestorePending = true
                C_Timer_After(0, RestoreGridSurfacedBars)
            end
        end
    end

    EAB._abcEvents:SetScript("OnEvent", function(_, event, arg1)
        if event == "ACTIONBAR_SHOWGRID" then
            ns.EABQueueGrid(true)
        elseif event == "ACTIONBAR_HIDEGRID" or event == "PET_BAR_HIDEGRID" then
            ns.EABQueueGrid(false)
        elseif event == "CVAR_UPDATE" then
            -- Name-filtered: CVAR_UPDATE fires for every cvar, dozens of times
            -- at login. The lock matters to the drag wrapper; Cast Actions on
            -- Key Down re-applies useOnKeyDown (combat-deferred).
            if arg1 == "lockActionBars" then ns.EABSyncBarsLocked()
            elseif arg1 == "ActionButtonUseKeyDown" then ApplyKeyDownCVar() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- A lock toggled during combat deferred; pick it up on regen.
            ns.EABSyncBarsLocked()
            -- The curated-set retire a combat SPELLS_CHANGED held back (below).
            if ns._cdCuratedAfterCombat then
                ns._cdCuratedAfterCombat = nil
                ns._cdCuratedDirty = true
                ns._cdFilledDirty = true
            end
        elseif event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
            if event == "PLAYER_ENTERING_WORLD" then ns.EABSyncBarsLocked() end
            -- Spec/talent swaps refill slots: retire the filled-slot fast
            -- lists (see the dispatcher's repaint walks) AND the curated-set
            -- memo (talents change what the viewer curates). Talents and spec
            -- never change in combat, where SPELLS_CHANGED still fires (several
            -- times a fight for some classes), so a combat fire re-curates at
            -- combat's end instead of re-walking the viewer data now.
            ns._cdFilledDirty = true
            if event == "SPELLS_CHANGED" and InCombatLockdown() then
                ns._cdCuratedAfterCombat = true
            else
                ns._cdCuratedDirty = true
            end
            -- Force visibility update on all managed buttons
            if not InCombatLockdown() then
                for btn in pairs(_controllerButtons) do
                    local showgrid = btn:GetAttribute("showgrid") or 0
                    local hasAction = btn.HasAction and btn:HasAction()
                    local hidden = btn:GetAttribute("statehidden")
                    if not hidden and (showgrid > 0 or hasAction) then
                        if not btn:IsShown() then
                            btn:Show()
                            -- Our Show keeps alpha: a surfaced 2-park sits at 0.
                            local pfd = ns._eabFD[btn]
                            if pfd and pfd.parkA0 == 2 and btn:IsShown() then pfd.parkA0 = 1 end
                        end
                    end
                end
            end
        end
    end)
    EAB._abcEvents:RegisterEvent("ACTIONBAR_SHOWGRID")
    EAB._abcEvents:RegisterEvent("ACTIONBAR_HIDEGRID")
    EAB._abcEvents:RegisterEvent("PET_BAR_HIDEGRID")
    EAB._abcEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
    EAB._abcEvents:RegisterEvent("SPELLS_CHANGED")
    EAB._abcEvents:RegisterEvent("CVAR_UPDATE")
    EAB._abcEvents:RegisterEvent("PLAYER_REGEN_ENABLED") -- guardrails-allow: combat-deferral by Ellesmere: moved verbatim from EllesmereUIActionBars.lua
    -- Seed before the first drag: PLAYER_ENTERING_WORLD may already be past.
    ns.EABSyncBarsLocked()

    -- Reset showgrid state at login (covers waiting for the game to apply
    -- the always-show-buttons state to the main bar).
    if ActionButton1 then
        ActionButton1:SetAttribute("showgrid", 0)
    end

    -- Suppress action bar tooltips per-bar when the setting is enabled.
    -- Hooks GameTooltip:SetAction/SetPetAction which Blizzard action
    -- buttons call on hover. Zero per-frame cost.
    if GameTooltip then
        local function ShouldHideTooltip(tip)
            local owner = tip:GetOwner()
            if not owner then return false end
            local info = buttonToBar[owner]
            if not info then return false end
            local s = EAB.db and EAB.db.profile.bars[info.barKey]
            return s and s.disableTooltips
        end
        hooksecurefunc(GameTooltip, "SetAction", function(self)
            if ShouldHideTooltip(self) then self:Hide() end
        end)
        hooksecurefunc(GameTooltip, "SetPetAction", function(self)
            if ShouldHideTooltip(self) then self:Hide() end
        end)
    end

    -- Attach hover hooks for mouseover -- DEFERRED one tick: ~290 HookScript
    -- calls + ~60 closures, the heaviest pure-insecure chunk in the login
    -- window. HookScript is combat-legal; every hoverStates consumer nil-
    -- guards, so one unpopulated tick is a silent no-op; and After(0) fires
    -- before DoVisuals' +0.1s RefreshMouseover walk.
    C_Timer_After(0, function()
        for _, info in ipairs(BAR_CONFIG) do
            AttachHoverHooks(info.key)
        end
    end)

    -- When a spell flyout closes, fade out any bars that were kept visible by it.
    -- Not under WoW Forever's Gamepad interface style, which shows and hides
    -- the flyout from secure code (the flyout skin stands down there too).
    do
        local flyFrame = GetEABFlyout():GetFrame()
        if flyFrame and not EllesmereUI.PadGamepadUI() then
            flyFrame:HookScript("OnHide", function()
                if _quickKeybindState.open then return end
                for key, state in pairs(hoverStates) do
                    if not state.isHovered then
                        EAB_VTABLE.Hover.FadeOut(key, state)
                    end
                end
            end)
        end
    end

    -- When the screen's coordinate space changes (UI Scale, resolution, window
    -- size), put every bar back on its SAVED position. The bars are clamped to
    -- the screen (SetupBar), and the engine can rewrite a clamped frame's
    -- anchor to the spot it clamped it to; re-applying the saved record returns
    -- a bar to its real spot once the screen has room again. Display only:
    -- nothing here reads a live anchor or writes a saved position (the saved
    -- record changes only when the player moves the bar). Gated on UIParent's
    -- size, so a scale event that changes nothing costs one compare. Skipped
    -- while an unlock session is open or suspended for combat: its movers own
    -- the bars until Save & Exit or Cancel.
    do
        local scaleFrame = ns.TakeShell()
        scaleFrame._eabW, scaleFrame._eabH = UIParent:GetSize()
        local function ReapplySavedBarPositions()
            if EllesmereUI._unlockActive or EllesmereUI._unlockModeSessionActive then return end
            RestoreBarPositions()
            -- Anchored bars take their spot from the anchor, not the record.
            -- The helper lives in the unlock core, built at PLAYER_LOGIN.
            local reapply = EllesmereUI.ReapplyUnlockAnchor
            local adb = EllesmereUIDB and EllesmereUIDB.unlockAnchors
            if reapply and adb then
                local bars = EAB.db.profile.bars
                for _, info in ipairs(BAR_CONFIG) do
                    local key = info.key
                    local ai = adb[key]
                    if ai and ai.target then
                        -- A growth bar with no captured pin keeps its LIVE
                        -- edge on a re-apply (the settle pass skips it for the
                        -- same reason), which would fix a clamped spot in place.
                        local s = bars[key]
                        local gd = (s and s.growDirection or "up"):upper()
                        if ai.mode == "POINT" or key == "StanceBar" or gd == "CENTER" or ai.refFor == gd then
                            reapply(key)
                        end
                    end
                end
            end
        end
        scaleFrame:RegisterEvent("UI_SCALE_CHANGED")
        scaleFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
        scaleFrame:SetScript("OnEvent", function(sf)
            local w, h = UIParent:GetSize()
            if w == sf._eabW and h == sf._eabH then return end
            if EllesmereUI._unlockActive or EllesmereUI._unlockModeSessionActive then return end
            sf._eabW, sf._eabH = w, h
            if InCombatLockdown() then
                ns.CombatQueue.Defer("EABReapplyBarPositions", ReapplySavedBarPositions)
            else
                ReapplySavedBarPositions()
            end
        end)
    end

    -- Register events
    self:RegisterEvent("UPDATE_BINDINGS", function()
        if InCombatLockdown() then
            ns.CombatQueue.Defer("UpdateKeybinds", UpdateKeybinds)
        else
            UpdateKeybinds()
        end
        self:ApplyFonts()
    end)

    _gridState.showFns[#_gridState.showFns + 1] = OnGridChange
    self:RegisterEvent("ACTIONBAR_SHOWGRID", function() ns.EABQueueGrid(true) end)
    -- Pet actions fire their own grid events when dragging pet spells
    self:RegisterEvent("PET_BAR_SHOWGRID", function() ns.EABQueueGrid(true) end)

    -- Detect bar-to-bar drags (CURSOR_CHANGED) and clear grid state on drop.
    -- Also show mouseover-faded bars while dragging so the player can drop
    -- spells/items onto them.  Purely visual -- no secure frame access.
    local DRAG_TYPES = {
        spell = true, macro = true,
        petaction = true, mount = true, companion = true,
    }
    _dragState.visible = false
    _dragState.strataCache = {}  -- [frame] = originalStrata
    local function ResetDragState()
        -- Stale drag-forced Never bars (drag ended across a loading screen /
        -- combat edge) go back to hidden with the rest of the drag state.
        EAB._RestoreDragNeverBars()
        -- Force-restore all strata and clear drag visibility without the
        -- guard check, so stale state from spec changes etc. is always cleaned.
        _dragState.visible = false
        -- Skip the restore if in combat; the strata cache entries survive
        -- and will be restored on the next PLAYER_REGEN_ENABLED call.
        if InCombatLockdown() then return end
        for frame, orig in pairs(_dragState.strataCache) do
            frame:SetFrameStrata(orig)
        end
        wipe(_dragState.strataCache)
    end
    local function SetDragVisible(show)
        if _dragState.visible == show then return end
        _dragState.visible = show
        for _, info in ipairs(ALL_BARS) do
            local key = info.key
            local s = self.db.profile.bars[key]
            if not s then -- skip bars without settings
            else
            local frame = barFrames[key]
                or (info.isDataBar and dataBarFrames[key])
                or (info.isBlizzardMovable and blizzMovableHolders[key])
                or extraBarHolders[key]
                or (info.visibilityOnly and _G[info.frameName])
            -- For extra bars, alpha is managed on the Blizzard frame directly
            if info.visibilityOnly and not info.isDataBar and not info.isBlizzardMovable then
                local bf = _G[info.frameName]
                if bf then frame = bf end
            end
            if frame then
                local state = hoverStates[key]
                if show then
                    -- Raise strata so bars render above the spellbook.
                    -- SetFrameStrata is protected on secure frames in combat,
                    -- so only do this out of combat.
                    if not InCombatLockdown() then
                        if not _dragState.strataCache[frame] then
                            _dragState.strataCache[frame] = frame:GetFrameStrata()
                        end
                        frame:SetFrameStrata("FULLSCREEN_DIALOG")
                    end
                    -- Show mouseover-faded bars at full opacity
                    if s.mouseoverEnabled then
                        local fullAlpha = s._savedBarAlpha or 1
                        StopFade(frame, fullAlpha)
                        if state then state.fadeDir = "in" end
                        if key == "MainBar" then SyncPagingAlpha(fullAlpha) end
                    end
                else
                    -- Restore original strata (only if we changed it)
                    if not InCombatLockdown() then
                        local orig = _dragState.strataCache[frame]
                        if orig then
                            frame:SetFrameStrata(orig)
                            _dragState.strataCache[frame] = nil
                        end
                    end
                    -- Fade back out if mouseover-enabled and not hovered. Skip
                    -- position-only Blizzard-owned bars (the QueueStatus eye): EUI
                    -- controls only their position, never fades them out.
                    if s.mouseoverEnabled and not info.noManagedVisibility then
                        if not (state and state.isHovered) then
                            StopFade(frame)
                            FadeTo(frame, 0, s.mouseoverSpeed or 0.15)
                            if state then state.fadeDir = "out" end
                            if key == "MainBar" then SyncPagingAlpha(0) end
                        end
                    end
                end
            end
        end
        end
    end

    self:RegisterEvent("CURSOR_CHANGED", function()
        local cursorType = GetCursorInfo()
        if cursorType then
            if DRAG_TYPES[cursorType] then
                SetDragVisible(true)
                -- Through the queue, never straight into OnGridChange: a
                -- direct call flips _gridState.shown, and this drag's own
                -- ACTIONBAR_SHOWGRID would then settle as a no-op and skip
                -- the controller-side applier.
                ns.EABQueueGrid(true)
                -- Force mouseover bars visible during real cursor drags
                _gridState._mouseoverForced = true
                for _, info in ipairs(BAR_CONFIG) do
                    local s = EAB.db.profile.bars[info.key]
                    if s and s.mouseoverEnabled then
                        local frame = barFrames[info.key]
                        if frame then
                            StopFade(frame, 1)
                            if info.key == "MainBar" then SyncPagingAlpha(1) end
                        end
                    end
                end
                -- Show During Drag (per-bar opt-in, s.dragShow): surface bars saved as
                -- Never so the drag can be dropped onto them. Surgical -- every other
                -- visibility mode already shows during a drag (mouseover forcing
                -- above, conditional drivers). Reuses the runtime _visOverride slot
                -- (never persisted) and skips bars the toggle keybind already
                -- overrides. Secure driver swaps are combat-blocked, so combat drags
                -- leave Never bars hidden.
                if not InCombatLockdown() and not _gridState._dragNeverForced then
                    local forced
                    for _, info in ipairs(BAR_CONFIG) do
                        local s = EAB.db.profile.bars[info.key]
                        if s and s.dragShow and s.enabled ~= false
                           and (s.barVisibility == "never" or s.alwaysHidden)
                           and not (EAB._visOverride and EAB._visOverride[info.key]) then
                            EAB._visOverride = EAB._visOverride or {}
                            EAB._visOverride[info.key] = "always"
                            forced = forced or {}
                            forced[info.key] = true
                        end
                    end
                    if forced then
                        _gridState._dragNeverForced = forced
                        EAB:RefreshRuntimeVisibility()
                    end
                end
            end
        else
            SetDragVisible(false)
            EAB._RestoreDragNeverBars()
            -- Fallback for a cursor cleared without a HIDEGRID; the queue
            -- dedupes when both arrive. OnGridHide owns the state flip and
            -- the re-assert, so this must not clear _gridState.shown itself
            -- (that would make the settle skip the hide appliers).
            if _gridState.shown then ns.EABQueueGrid(false) end
        end
    end)

    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        -- Re-apply anything deferred during combat -- but ONLY if something actually
        -- deferred. ns._eabApplyDeferred is set by every combat-gated apply site whose
        -- skipped work this ApplyAll heals (LayoutBar, shapes, grid, page sync,
        -- suppress/unsuppress, the visibility appliers, and ApplyAll itself when run
        -- mid-combat). The unconditional version ran the full ~30ms bar reskin on EVERY
        -- combat drop -- a visible hitch between every dungeon pack, paid even when
        -- combat deferred nothing.
        if ns._eabApplyDeferred then
            ns._eabApplyDeferred = nil
            ns._eabMainBarAsbOwed = nil
            ApplyAll()
        elseif ns._eabMainBarAsbOwed then
            -- Only main bar AlwaysShow passes ran in combat (page flips, spell
            -- swaps): its own pass writes what they skipped.
            ns._eabMainBarAsbOwed = nil
            self:ApplyAlwaysShowButtons("MainBar")
        end
        -- The pet bar's combat parking changed a slot: one pet pass finishes it
        -- (Hide, mouse, statehidden), not the full ApplyAll.
        if ns._eabPetRegenHeal and ns._eabPetReconcile then ns._eabPetReconcile() end
        -- Restore any strata changes that couldn't be done in combat
        ResetDragState()
        -- Quick Keybind buttons may need reassertion after combat transitions
        _quickKeybindState.ReassertButtonsAfterCombatChange()
        -- Combat page flips can leave empower hold-release attrs stale while
        -- the routing signature is unchanged; repair once per combat drop.
        if ns._EABReassertEmpowerAttrs then ns._EABReassertEmpowerAttrs() end
    end)

    self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        _quickKeybindState.ReassertButtonsAfterCombatChange()
    end)

    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        -- After any loading screen, reset vehicle/housing keybind flags and re-apply
        -- bindings. WoW can briefly report vehicleui/overridebar during zone
        -- transitions, which clears our override bindings. If the restore races with
        -- InCombatLockdown() the bindings stay cleared forever. This catches that.
        ResetDragState()
        C_Timer_After(0.2, function()
            -- Reset stale flags -- if we're not actually in housing the flag
            -- should be false. Plain Lua state, safe in combat.
            local inHousing = IsHouseEditorActive and IsHouseEditorActive()
            if not inHousing and _bindState.housingCleared then
                _bindState.housingCleared = false
            end
            -- This is the restore point for the transient-clear race above, so it
            -- must never be skipped: bindings can be cleared or wrongly routed while
            -- the cached signature claims they are applied. Force the rebuild past
            -- the signature short-circuit, and call unconditionally --
            -- UpdateKeybinds defers itself to PLAYER_REGEN_ENABLED in combat. Zoning
            -- INTO combat (die, release, run back in while the raid still fights)
            -- needs this or empower slots sit on native bindings (Press-and-Tap
            -- behaviour) until the next reload.
            -- The one exception is the login loading screen right after the login
            -- build (loginBuilt): nothing can have cleared the bindings since (the
            -- housing clear invalidates the signature itself), so only the signature
            -- check runs, which still rebuilds on any change.
            if _bindState.loginBuilt then
                _bindState.loginBuilt = nil
            else
                _bindState.sigValid = false
            end
            UpdateKeybinds()
        end)
        -- Re-evaluate visibility options (visOnlyInstances, visHideHousing,
        -- etc.) after every loading screen. ZONE_CHANGED_NEW_AREA alone is
        -- insufficient: it can fire before GetInstanceInfo() updates, and
        -- doesn't fire at all on /reload inside an instance.
        self:UpdateHousingVisibility()
    end)

    local function QueueAlwaysShowButtonsRefresh()
        -- During drag, skip. OnGridChange already shows everything, and
        -- HIDEGRID / CURSOR_CHANGED will restore afterwards.
        if _gridState.shown then return end
        if _gridState.visPending then return end
        _gridState.visPending = true
        C_Timer_After(0, function()
            _gridState.visPending = false
            if _gridState.shown then return end
            for _, info in ipairs(BAR_CONFIG) do
                self:ApplyAlwaysShowButtons(info.key)
            end
        end)
    end

    -- Slot changes alone are not sufficient for all paging transitions
    -- (dragonriding, druid forms, mount state). Include page/bonus events
    -- so empty-slot visibility refreshes immediately on those swaps.
    self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", QueueAlwaysShowButtonsRefresh)
    self:RegisterEvent("UPDATE_BONUS_ACTIONBAR", QueueAlwaysShowButtonsRefresh)

    -- Spec swap: Blizzard may re-show SlotArt/SlotBackground or change button
    -- regions after our hooks ran. Deferred re-apply ensures our cosmetic
    -- overrides (squaring, borders, slot art hiding) are re-enforced after
    -- Blizzard finishes processing the spec change.
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function()
        C_Timer.After(0.5, function()
            if not InCombatLockdown() then
                ApplyAll()
                RestoreBarPositions()
            end
        end)
    end)

    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
        self:UpdateHousingVisibility()
    end)

    -- Visibility option events: mounted, target, group changes
    self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", function()
        self:UpdateHousingVisibility()
    end)
    -- Resting: IsResting() has no dedicated poll, so without this the Resting axis only
    -- re-evaluated when some unrelated event above happened to fire afterward.
    self:RegisterEvent("PLAYER_UPDATE_RESTING", function()
        self:UpdateHousingVisibility()
    end)
    -- Party Mode axis: no game event, so the core fires its own edge
    -- (EllesmereUI.FireVisEdge, re-fired after combat for secure bars).
    if EllesmereUI.RegisterVisEdge and not self._partyVisEdge then
        self._partyVisEdge = true
        EllesmereUI.RegisterVisEdge(function() self:UpdateHousingVisibility() end)
    end
    -- Vehicle edges for the In Vehicle axis (same reasoning as Resting; the
    -- sync is gated + coalesced, so the rare fire costs a flag check).
    self:RegisterEvent("UNIT_ENTERED_VEHICLE", function()
        self:UpdateHousingVisibility()
    end)
    self:RegisterEvent("UNIT_EXITED_VEHICLE", function()
        self:UpdateHousingVisibility()
    end)
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", function()
        self:UpdateHousingVisibility()
    end)
    -- Dragonriding visibility modes on the managed non-secure bars:
    -- capability edge plus the airborne edge (probed at load in
    -- EllesmereUI_Visibility.lua; the secure bars need neither -- their
    -- state driver re-evaluates [advflyable,flying] natively).
    self:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED", function()
        self:UpdateHousingVisibility()
    end)
    if EllesmereUI._hasGlidingEvent then
        self:RegisterEvent("PLAYER_IS_GLIDING_CHANGED", function()
            self:UpdateHousingVisibility()
        end)
    end
    -- Immediate soft-target override: when the only "target" is a soft-interact NPC
    -- (dialogue in view cone), the [noexists] state driver instantly shows the bar.
    -- Override to "hide" in the same frame so the bar never visibly flashes. The
    -- deferred UpdateHousingVisibility that follows handles the general case and
    -- restores the normal driver string when the soft target clears.
    local function ImmediateSoftTargetCheck()
        -- Fully gated (same flag the 0.1s poll already uses): without a
        -- "Hide when No Target" bar, the four UnitExists calls and the
        -- all-bars walk below are dead weight on every soft-target flip --
        -- and soft-interact churns constantly near NPCs.
        if not self._anyHideNoTarget then return end
        if InCombatLockdown() then return end
        -- [noexists] in macro conditionals considers soft-interact/
        -- softenemy/softfriend as "target exists", but UnitExists("target")
        -- does NOT. Check the soft-target unit tokens directly.
        local hasSoftInteract = UnitExists("softinteract")
        local hasSoftEnemy = UnitExists("softenemy")
        local hasSoftFriend = UnitExists("softfriend")
        local hasHardTarget = UnitExists("target")
        local softOnly = (hasSoftInteract or hasSoftEnemy or hasSoftFriend) and not hasHardTarget
        for _, info in ipairs(ALL_BARS) do
            local s = self.db.profile.bars[info.key]
            if s and (s.visHideNoTarget or (s.visHideWithTarget and s.visibilityMatch == "any"))
                    and not (self._visOverride and self._visOverride[info.key]) then
                local frame = barFrames[info.key]
                if frame then
                    -- Under Any a literal "hide" would veto the whole disjunction on this
                    -- one lane; the rebuild below lets the shared builder drop just it.
                    if softOnly and s.visHideNoTarget and s.visibilityMatch ~= "any" then
                        if frame._eabLastVisStr ~= "hide" then
                            frame._eabLastVisStr = "hide"
                            RegisterAttributeDriver(frame, "state-visibility", "hide")
                        end
                    else
                        local newStr = BuildVisibilityString(info, s)
                        if frame._eabLastVisStr ~= newStr then
                            frame._eabLastVisStr = newStr
                            RegisterAttributeDriver(frame, "state-visibility", newStr)
                        end
                    end
                end
            end
        end
    end
    self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        -- Defer: UnitExists("target") is not always updated at the exact
        -- moment PLAYER_TARGET_CHANGED fires, so an immediate check can
        -- wrongly see no hard target and keep the bar hidden. Run next frame.
        C_Timer.After(0, function()
            ImmediateSoftTargetCheck()
            self:UpdateHousingVisibility()
        end)
    end)
    self:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED", function()
        ImmediateSoftTargetCheck()
        self:UpdateHousingVisibility()
    end)
    local function RegisterIfValid(event, fn)
        if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsEventValid(event) then
            self:RegisterEvent(event, fn)
        end
    end
    RegisterIfValid("PLAYER_SOFT_ENEMY_CHANGED", function()
        ImmediateSoftTargetCheck()
        self:UpdateHousingVisibility()
    end)
    RegisterIfValid("PLAYER_SOFT_FRIEND_CHANGED", function()
        ImmediateSoftTargetCheck()
        self:UpdateHousingVisibility()
    end)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        self:UpdateHousingVisibility()
    end)
    -- Polling fallback: some soft-target transitions (notably Action Targeting walking
    -- into range) do not reliably fire the dedicated soft-target events on every
    -- client/patch. Check the soft-target unit tokens every 0.1s and sync visibility
    -- only when the state changes. Gated on _anyHideNoTarget: for users with no "Hide
    -- when No Target" bar this is a single flag check that then returns, so the
    -- machinery costs nothing. The state token is four cached booleans (no per-tick
    -- allocation); refresh only runs when a token actually flips.
    self:_RefreshSoftTargetGate()
    -- Hover-gated bars (Match Any plus mouseover) need their resting alpha re-derived
    -- whenever the state their other disjuncts read moves. Rather than hand-wiring the
    -- five relevant events here, ride the shared visibility dispatcher: it already watches
    -- exactly that set, pcall-wraps each updater and defers one frame (imperceptible for
    -- alpha). Same registration Friends, Quest Tracker and Damage Meters use.
    EllesmereUI.RegisterVisibilityUpdater(function()
        EAB:RefreshHoverGatedAlpha()
    end)
    local lastI, lastE, lastF, lastT
    local function PollSoftTargetState()
        if InCombatLockdown() then return end
        if not self._anyHideNoTarget then return end
        local i  = UnitExists("softinteract") and true or false
        local e  = UnitExists("softenemy") and true or false
        local fr = UnitExists("softfriend") and true or false
        local t  = UnitExists("target") and true or false
        if i ~= lastI or e ~= lastE or fr ~= lastF or t ~= lastT then
            lastI, lastE, lastF, lastT = i, e, fr, t
            ImmediateSoftTargetCheck()
            self:UpdateHousingVisibility()
        end
    end
    C_Timer.NewTicker(0.1, PollSoftTargetState)
    -- Combat exit: synchronously restore all visHideNoTarget bar state drivers. During
    -- combat, ImmediateSoftTargetCheck and UpdateHousingVisibility are blocked by
    -- InCombatLockdown. If a bar's driver was overridden to "hide" (soft-target
    -- override) before combat started, it stays stuck the entire fight. The shared
    -- visibility dispatcher uses a double-deferred path that can miss rapid combat
    -- re-entry; this handler runs at the exact frame lockdown lifts, with no deferral,
    -- guaranteeing restoration.
    do
        local regenFrame = ns.TakeShell()
        regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED") -- guardrails-allow: combat-deferral by Ellesmere: moved verbatim from EllesmereUIActionBars.lua
        regenFrame:SetScript("OnEvent", function()
            for _, info in ipairs(ALL_BARS) do
                local s = self.db.profile.bars[info.key]
                if s and (s.visHideNoTarget or (s.visHideWithTarget and s.visibilityMatch == "any"))
                    and not (self._visOverride and self._visOverride[info.key]) then
                    local frame = barFrames[info.key]
                    if frame then
                        local newStr = BuildVisibilityString(info, s)
                        if frame._eabLastVisStr ~= newStr then
                            frame._eabLastVisStr = newStr
                            RegisterAttributeDriver(frame, "state-visibility", newStr)
                        end
                    end
                end
            end
        end)
    end

    -- Grid hide: restore empty slot visibility
    local function OnGridHide()
        _gridState.shown = false

        -- Clear the game event showgrid flag on all managed buttons
        if not InCombatLockdown() then
            for _, info in ipairs(BAR_CONFIG) do
                if not info.isStance and not info.isPetBar then
                    local btns = barButtons[info.key]
                    if btns then
                        for _, btn in ipairs(btns) do
                            if btn then
                                SetShowGridInsecure(btn, false, SHOWGRID.GAME_EVENT)
                            end
                        end
                    end
                end
            end
        end

        -- Defer visibility update by one frame so ACTIONBAR_SLOT_CHANGED
        -- processes first. Without this, a spell dropped onto a previously
        -- empty slot is not yet registered when ApplyAlwaysShowButtons runs,
        -- causing the button to be hidden as empty.
        C_Timer.After(0, function()
            if InCombatLockdown() then return end
            -- The grid show force-showed buttons, so the stamps no longer
            -- reflect button state and every bar must re-assert.
            if ns._asbStamp then wipe(ns._asbStamp) end
            for _, info2 in ipairs(BAR_CONFIG) do
                self:ApplyAlwaysShowButtons(info2.key)
            end
        end)

        -- Restore mouseover fade on bars that were forced visible during drag.
        -- Only needed if a real cursor drag happened (CURSOR_CHANGED forced them).
        -- _gridState tracks whether forcing occurred via the CURSOR_CHANGED path.
        if _gridState._mouseoverForced then
            _gridState._mouseoverForced = false
            for _, info in ipairs(BAR_CONFIG) do
                local s = EAB.db.profile.bars[info.key]
                if s and s.mouseoverEnabled then
                    local state = hoverStates[info.key]
                    if state and not state.isHovered then
                        EAB_VTABLE.Hover.FadeOut(info.key, state)
                    end
                end
            end
        end
        -- Re-hide Never bars surfaced by Show All During Drag.
        EAB._RestoreDragNeverBars()
    end
    _gridState.hideFns[#_gridState.hideFns + 1] = OnGridHide
    self:RegisterEvent("ACTIONBAR_HIDEGRID", function() ns.EABQueueGrid(false) end)
    self:RegisterEvent("PET_BAR_HIDEGRID", function() ns.EABQueueGrid(false) end)

    -- Spell updates: refresh button icons and visibility
    -- Also re-layout the stance bar since GetNumShapeshiftForms() may have changed
    self:RegisterEvent("SPELLS_CHANGED", function()
        if _gridState.spellsPending then return end
        _gridState.spellsPending = true
        C_Timer_After(0, function()
            _gridState.spellsPending = false
            -- The stance bar follows the number of forms, which only a talent or a
            -- newly learned spell changes. SPELLS_CHANGED also fires mid-combat on
            -- every spell swap (procs, Holy Armaments), where both passes are
            -- combat-gated and would only flag a full ApplyAll for combat end.
            local nForms = GetNumShapeshiftForms() or 0
            if nForms ~= _gridState.spellsForms then
                _gridState.spellsForms = nForms
                LayoutBar("StanceBar")
                self:RefreshRuntimeVisibility() -- re-eval stance bar show/hide
            end
            -- Content-signature gate: SPELLS_CHANGED also fires mid-combat on
            -- spell-override flips (proc morphs), where slot CONTENTS are identical and
            -- the full AlwaysShow + ForceButtonRefresh sweep below (~140 buttons;
            -- measured 4.6ms + 1.7ms in one storm frame) repaints nothing new -- the
            -- icon/override branches already own morph visuals. A cheap GetActionInfo
            -- sweep proves whether contents actually changed; only a real change (spec
            -- swap, learn/unlearn) pays the heal this pass exists for. Secret ids
            -- (instanced combat) stamp as "?" -- stable -- and genuine combat content
            -- swaps still repaint via SLOT_CHANGED's own targeted path. PER-BUTTON
            -- DELTA: the aggregate signature could only say "something changed" -- and
            -- a single spell TRANSFORM legitimately changes it (GetActionInfo reports
            -- the override), so every mid-combat transform paid the full ~140-button
            -- ForceButtonRefresh + per-bar AlwaysShow response (measured
            -- 1.68ms + 0.53ms in one frame) to heal 1-2 slots. The same walk
            -- that builds the signature now also diffs a per-button token, so
            -- the heal touches exactly the changed buttons. The full sweep
            -- survives only for the cold start (nil signature: reload/profile
            -- flip/Never-set change), where "everything changed" is true.
            local sig = {}
            local isSecQ = issecretvalue
            local coldStart = ns._eabSpellsSig == nil
            local changed, changedBars
            for _, info in ipairs(BAR_CONFIG) do
                if not info.isStance and not info.isPetBar
                    and not ns._eabBarNever[info.key] then
                    local btns = barButtons[info.key]
                    if btns then
                        for _, btn in ipairs(btns) do
                            if btn then
                                local a = btn:GetAttribute("action")
                                local t2, id, st
                                if a then t2, id, st = GetActionInfo(a) end
                                local tok
                                if isSecQ and (isSecQ(t2) or isSecQ(id) or isSecQ(st)) then
                                    tok = "?"
                                else
                                    tok = (t2 or "-") .. (id or 0) .. (st or "")
                                end
                                sig[#sig + 1] = tok
                                local fd = EFD(btn)
                                if fd.spellsTok ~= tok then
                                    fd.spellsTok = tok
                                    if not coldStart then
                                        if not changed then
                                            changed = {}
                                            changedBars = {}
                                        end
                                        changed[#changed + 1] = btn
                                        changedBars[info.key] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
            sig = table.concat(sig, ",")
            if sig == ns._eabSpellsSig then return end
            ns._eabSpellsSig = sig
            if not coldStart then
                -- Targeted heal: only the buttons whose content token
                -- changed, and only their bars' AlwaysShow passes.
                if changed then
                    for key in pairs(changedBars) do
                        self:ApplyAlwaysShowButtons(key)
                    end
                    for i = 1, #changed do
                        local btn = changed[i]
                        EAB_VTABLE.ForceButtonRefresh(btn, btn:GetAttribute("action"))
                    end
                end
                return
            end
            for _, info in ipairs(BAR_CONFIG) do
                self:ApplyAlwaysShowButtons(info.key)
            end
            -- Force visual refresh on all action buttons. Spec swap changes which
            -- spells occupy each slot; the C-side ACTIONBAR_SLOT_CHANGED handler may
            -- not fire UpdateAction on our EABButton frames. Without this, cooldown
            -- swipes (including GCD) can disappear after swap. A spec swap changes slot
            -- CONTENTS while slot numbers stay identical, so this needs the forced
            -- refresh path (ForceButtonRefresh; also handles the secret-safe variant).
            for _, info in ipairs(BAR_CONFIG) do
                if not info.isStance and not info.isPetBar
                    and not ns._eabBarNever[info.key] then
                    local btns = barButtons[info.key]
                    if btns then
                        for _, btn in ipairs(btns) do
                            if btn then
                                EAB_VTABLE.ForceButtonRefresh(btn, btn:GetAttribute("action"))
                            end
                        end
                    end
                end
            end
        end)
    end)

    -- Slot changed: update visibility when a spell is placed/removed from a slot.
    -- This can fire per-slot (12+ times during a bar page swap), so use the
    -- shared debounced visibility queue. Only an empty <-> filled flip changes
    -- what the pass shows, and empowered casts and spell overrides re-fire this
    -- for slots whose contents stay put, so a numbered slot is probed against
    -- its last seen state first; slot 0 (every slot) always refreshes.
    local asbSlotFilled = {}
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", function(_, _, slot)
        if slot and slot ~= 0 then
            local filled = HasAction(slot) and true or false
            if asbSlotFilled[slot] == filled then return end
            asbSlotFilled[slot] = filled
        end
        QueueAlwaysShowButtonsRefresh()
    end)

    -- Pet bar: re-layout and refresh visibility when the pet's action bar changes.
    -- PET_BAR_UPDATE covers ability changes; PET_UI_UPDATE covers summoning/dismissal;
    -- UNIT_PET covers pet swaps. PLAYER_ENTERING_WORLD ensures button state is
    -- populated on login (PetActionBar was unregistered from all events, so Blizzard's
    -- own update never fires). PET_BAR_UPDATE_USABLE fires when action usability
    -- changes so icon dimming stays current; UNIT_AURA "pet" can also affect usability.
    -- PET_ATTACK_START / PET_ATTACK_STOP start and stop the Attack button's flash
    -- (no PET_BAR_UPDATE marks a pet that stops attacking on its own, e.g. as
    -- combat ends; Blizzard's bar catches it through UNIT_FLAGS, which fires on
    -- every pet flag change).
    -- Coalesced: any event burst schedules ONE deferred pass per frame through a cached
    -- closure. "full" absorbs "cd": every full path repaints cooldowns too. A hidden
    -- pet bar skips all of it -- the secure
    -- [pet] driver keeps visibility correct engine-side -- and the show edge
    -- reconciles with one full pass (ns._eabPetReconcile).
    local _petPendingKind = nil  -- nil | "cd" | "full"
    -- Set by PET_ATTACK_STOP, cleared by PET_ATTACK_START, a summon or
    -- dismissal and a loading screen. GetPetActionInfo can still report the
    -- attack when the stop fires, which kept the Attack button flashing after
    -- the pet stopped, so the stop turns it off. Only the stop overrides: a pet
    -- that stops with no stop event (sent back with Follow) is read from
    -- GetPetActionInfo, as Blizzard's bar reads it.
    local petAttackStopped = false
    local PetBarDeferred
    PetBarDeferred = function()
        local kind = _petPendingKind
        _petPendingKind = nil
        if not kind then return end
        do
            if kind == "cd" then
                -- Cooldown-only path: safe during combat, no taint risk.
                -- Update each button's cooldown frame directly.
                for i = 1, NUM_PET_ACTION_SLOTS do
                    local btn = _G["PetActionButton" .. i]
                    if btn and btn.cooldown then
                        local start, duration, enable = GetPetActionCooldown(i)
                        CooldownFrame_Set(btn.cooldown, start, duration, enable)
                    end
                end
                return
            end
            if InCombatLockdown() then
                -- Combat-safe path: update textures and visual state per-button
                -- without touching protected frame operations (Show/Hide/SetParent).
                -- This allows pet abilities to appear when summoning a pet mid-combat.
                local hasPetBar = PetHasActionBar()
                -- Always Show Buttons off: the hide-empty rule by alpha alone, on
                -- the buttons within the icon cutoff (Show, Hide and mouse are
                -- protected here). A slot is empty only while a pet bar is out,
                -- as in ns.AB_EmptySlot; a button hidden out of combat stays
                -- parked until the regen pass lays the bar out again.
                local petInfo, petS = BAR_LOOKUP["PetBar"], self.db.profile.bars["PetBar"]
                local parkCut = 0
                if petInfo and petS and petS.alwaysShowButtons == false
                   and not (_gridState.shown or ShouldQuickKeybindSurfaceBar(petS)) then
                    parkCut = petS.overrideNumIcons or petS.numIcons or petInfo.count
                    if parkCut < 1 or parkCut > petInfo.count then parkCut = petInfo.count end
                end
                for i = 1, NUM_PET_ACTION_SLOTS do
                    local btn = _G["PetActionButton" .. i]
                    if btn then
                        local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled = GetPetActionInfo(i)
                        -- Any change here drops the pet layout memo and asks
                        -- the regen pass for the Hide / mouse work combat
                        -- withholds; so does a filled slot whose button was
                        -- hidden out of combat, which only that pass can show.
                        if i <= parkCut then
                            local pfd = EFD(btn)
                            if not btn:IsShown() then
                                if hasPetBar and texture then
                                    ns._eabPetLayoutSig, ns._eabPetRegenHeal = nil, true
                                end
                            elseif hasPetBar and not texture then
                                if not pfd.parkA0 then
                                    btn:SetAlpha(0)
                                    ns._eabMarkParked(btn, petInfo)
                                    ns._eabPetLayoutSig, ns._eabPetRegenHeal = nil, true
                                end
                            elseif pfd.parkA0 then
                                btn:SetAlpha(1)
                                pfd.parkA0 = nil
                                ns._eabPetLayoutSig, ns._eabPetRegenHeal = nil, true
                            end
                        end
                        if hasPetBar and texture then
                            if isToken then btn.icon:SetTexture(_G[texture])
                            else btn.icon:SetTexture(texture) end
                            -- Dim icon when the ability is not currently usable.
                            local usable = GetPetActionSlotUsable(i)
                            local shade = usable and 1 or 0.4
                            btn.icon:SetVertexColor(shade, shade, shade)
                            btn.icon:Show()
                            -- AutoCastOverlay (AutoCastOverlayMixin) replaced the old
                            -- AutoCastShine API in modern WoW. SetShown controls the
                            -- corner-ring frame; ShowAutoCastEnabled starts/stops the
                            -- rotating shine animation.
                            if btn.AutoCastOverlay then
                                btn.AutoCastOverlay:SetShown(autoCastAllowed)
                                btn.AutoCastOverlay:ShowAutoCastEnabled(autoCastEnabled)
                            end
                        else
                            btn.icon:Hide()
                            if btn.AutoCastOverlay then btn.AutoCastOverlay:Hide() end
                        end
                        -- Reflect the active state so pet mode buttons (Passive /
                        -- Assist / Defend) highlight the currently selected mode.
                        -- Attack actions flash instead of showing the full highlight.
                        -- SetChecked / StartFlash / StopFlash are visual-only and safe
                        -- to call during combat lockdown.
                        local ct = btn:GetCheckedTexture()
                        local ctA = EAB:GetCheckedAlpha("PetBar")
                        if isActive and petAttackStopped and IsPetAttackAction(i) then isActive = false end
                        if isActive then
                            if IsPetAttackAction(i) then
                                btn:StartFlash()
                                if ct then ct:SetAlpha(0.5 * ctA) end
                            else
                                btn:StopFlash()
                                if ct then ct:SetAlpha(1.0 * ctA) end
                            end
                            btn:SetChecked(true)
                        else
                            btn:StopFlash()
                            btn:SetChecked(false)
                        end
                        -- Update cooldown
                        if btn.cooldown then
                            local start, duration, enable = GetPetActionCooldown(i)
                            CooldownFrame_Set(btn.cooldown, start, duration, enable)
                        end
                    end
                end
                return
            end
            -- Full update path: only safe out of combat.
            if _gridState.shown then
                -- During a spell drag, skip PetActionBar:Update() which
                -- hides empty slots. Just refresh textures per-button so
                -- the vacated slot clears its icon while the grid stays.
                for i = 1, NUM_PET_ACTION_SLOTS do
                    local btn = _G["PetActionButton" .. i]
                    if btn then
                        local name, texture, isToken = GetPetActionInfo(i)
                        if texture then
                            if isToken then btn.icon:SetTexture(_G[texture])
                            else btn.icon:SetTexture(texture) end
                            btn.icon:Show()
                        else
                            btn.icon:Hide()
                        end
                    end
                end
                return
            end
            -- Blizzard's bar update paints the pet buttons, and with no pet bar
            -- it also hides its own bar. That hide runs Edit Mode's bottom bar
            -- stack pass from here, which on WoW Forever writes the snap fields
            -- of the stacked bars (MainActionBar to the micro menu) under our
            -- taint: Blizzard's next stack pass reads them and is blocked in
            -- combat, and every pass after it writes them tainted again. So it
            -- runs only while a pet bar is out; with none the buttons are
            -- emptied here, as its update would leave them.
            if PetHasActionBar() then
                if PetActionBar and PetActionBar.Update then
                    PetActionBar:Update()
                end
            else
                for i = 1, NUM_PET_ACTION_SLOTS do
                    local btn = _G["PetActionButton" .. i]
                    if btn then
                        btn.icon:Hide()
                        if btn.AutoCastOverlay then btn.AutoCastOverlay:Hide() end
                        btn:StopFlash()
                        btn:SetChecked(false)
                        if btn.cooldown then
                            local start, duration, enable = GetPetActionCooldown(i)
                            CooldownFrame_Set(btn.cooldown, start, duration, enable)
                        end
                    end
                end
            end
            -- Blizzard's update reads GetPetActionInfo too: the stop wins.
            if petAttackStopped then
                for i = 1, NUM_PET_ACTION_SLOTS do
                    local btn = IsPetAttackAction(i) and _G["PetActionButton" .. i]
                    if btn then
                        btn:SetChecked(false)
                        btn:StopFlash()
                    end
                end
            end
            -- Layout only when the populated-slot SHAPE changed (summon,
            -- dismiss, swap): re-laying the whole bar per aura/usable event
            -- was the pet handler's dominant cost. Every other writer of the
            -- pet buttons (LayoutBar, ApplyAlwaysShowButtons, the combat branch
            -- above) clears the memo, so it only ever holds what this pass drew;
            -- it is stored after the two passes, which clear it themselves.
            local sig = PetHasActionBar() and "p" or "n"
            for i = 1, NUM_PET_ACTION_SLOTS do
                sig = sig .. (GetPetActionInfo(i) and "1" or "0")
            end
            if sig ~= ns._eabPetLayoutSig then
                LayoutBar("PetBar")
                self:ApplyAlwaysShowButtons("PetBar")
                ns._eabPetLayoutSig = sig
            end
            ns._eabPetRegenHeal = nil
            -- Re-register the state driver so the [pet] condition is always
            -- current after a pet summon, swap, or dismissal.
            local petInfo = BAR_LOOKUP["PetBar"]
            local petFrame = barFrames["PetBar"]
            local petS = self.db.profile.bars["PetBar"]
            -- Not while a runtime rule owns the driver (a surfacing override from
            -- the toggle keybind or the spellbook, or Hide Bar When Using
            -- Gamepad): RefreshRuntimeVisibility registered that string (an
            -- override keeps the [pet] term), and a plain rebuild here would
            -- stomp it on the reveal's own reconcile pass.
            if petInfo and petFrame and petS and not petS.alwaysHidden
               and not (self._visOverride and self._visOverride.PetBar)
               and not (self._padHide and petS.gamepadHideBar == true) then
                RegisterAttributeDriver(petFrame, "state-visibility", BuildVisibilityString(petInfo, petS))
            end
        end
    end
    local function UpdatePetBar(_, event)
        -- Kept while the bar is hidden too, for its show edge's pass.
        if event == "PET_ATTACK_STOP" then petAttackStopped = true
        elseif event == "PET_ATTACK_START" or event == "UNIT_PET" or event == "PET_UI_UPDATE"
            or event == "PLAYER_ENTERING_WORLD" then petAttackStopped = false end
        -- Hidden pet bar: skip entirely. The [pet] visibility driver
        -- evaluates engine-side regardless, and the show edge runs a full
        -- reconcile pass, so nothing here can be missed.
        local pf = barFrames["PetBar"]
        if pf and not pf:IsVisible() then return end
        local kind = (event == "PET_BAR_UPDATE_COOLDOWN") and "cd" or "full"
        local prev = _petPendingKind
        _petPendingKind = (kind == "full" or prev == "full") and "full" or "cd"
        if not prev then C_Timer_After(0, PetBarDeferred) end
    end
    -- Bar-reveal reconcile (ApplyBarDormancy show edge): one full pass
    -- covers everything the hidden-skip above dropped.
    ns._eabPetReconcile = function()
        local prev = _petPendingKind
        _petPendingKind = "full"
        if not prev then C_Timer_After(0, PetBarDeferred) end
    end
    local _petEventFrame = ns.TakeShell()
    _petEventFrame:RegisterEvent("PET_BAR_UPDATE")
    _petEventFrame:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
    _petEventFrame:RegisterEvent("PET_BAR_UPDATE_USABLE")
    _petEventFrame:RegisterEvent("PET_UI_UPDATE")
    _petEventFrame:RegisterEvent("PET_ATTACK_START")
    _petEventFrame:RegisterEvent("PET_ATTACK_STOP")
    _petEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _petEventFrame:RegisterUnitEvent("UNIT_PET", "player")
    _petEventFrame:RegisterUnitEvent("UNIT_AURA", "pet")
    _petEventFrame:SetScript("OnEvent", UpdatePetBar)

    -- StanceBarMixin:UpdateState owns Blizzard's active highlight and cooldown
    -- swipe, but HideBlizzardBars unregisters that bar's events. Reconcile both
    -- visuals on the reused buttons without invoking the hidden bar's layout
    -- or visibility updates. SetChecked and CooldownFrame_Set are visual-only,
    -- matching the pet bar painter above.
    -- Per-form memo of the last (start, duration, enable) triple pushed. The
    -- cooldown event refires on every GCD for form classes and the swipe is a
    -- pure function of those three values, so an identical triple is skipped.
    -- Invalidation inputs, each named: the triple itself (compared per
    -- form); the form list and the world enter (their events wipe the memo);
    -- the show-edge reconcile (the hidden bar may have been repainted by
    -- anything meanwhile -- its no-event call wipes too). Secret values
    -- (instanced combat) cannot be compared: that form pushes unconditionally
    -- and drops its memo.
    local stanceLast = {}
    local function UpdateStanceState(_, event)
        if event ~= "UPDATE_SHAPESHIFT_COOLDOWN" then wipe(stanceLast) end
        -- Hidden stance bar: skip. The show edge reruns this painter
        -- (ns._eabStanceReconcile), and the event refires every GCD for
        -- form classes, so nothing can stay stale while visible.
        local sf = barFrames["StanceBar"]
        if sf and not sf:IsVisible() then return end
        local numForms = GetNumShapeshiftForms()
        for i = 1, numForms do
            local btn = _G["StanceButton" .. i]
            if btn then
                -- Clicks toggle the checked state optimistically; reconcile it
                -- from the actual form even when the cooldown has not changed.
                local _, isActive = GetShapeshiftFormInfo(i)
                btn:SetChecked(isActive)
            end
            if btn and btn.cooldown then
                local start, duration, enable = GetShapeshiftFormCooldown(i)
                if issecretvalue and (issecretvalue(start) or issecretvalue(duration)
                                      or issecretvalue(enable)) then
                    stanceLast[i] = nil
                    CooldownFrame_Set(btn.cooldown, start, duration, enable)
                else
                    local m = stanceLast[i]
                    if not m or m[1] ~= start or m[2] ~= duration or m[3] ~= enable then
                        if not m then m = {}; stanceLast[i] = m end
                        m[1], m[2], m[3] = start, duration, enable
                        CooldownFrame_Set(btn.cooldown, start, duration, enable)
                    end
                end
            end
        end
    end
    ns._eabStanceReconcile = UpdateStanceState
    local _stanceEventFrame = ns.TakeShell()
    _stanceEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN")
    _stanceEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    _stanceEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
    _stanceEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _stanceEventFrame:SetScript("OnEvent", UpdateStanceState)


    -- Talent changes can cause Blizzard to re-show hidden bars.
    -- Re-run the hider and re-unregister events on the affected frames.
    -- The OnShow hooks below also catch this, but this is a safety net.
    self:RegisterEvent("PLAYER_TALENT_UPDATE", function()
        if InCombatLockdown() then return end
        for _, entry in ipairs(STOCK_BAR_DISPOSAL) do
            local bar = _G[entry.name]
            if bar then
                if not entry.retainEvents then
                    bar:UnregisterAllEvents()
                end
                -- No Hide(): see ReassertHiddenOnShow's note above
                -- hiddenParent's creation. Reparenting alone is enough.
                bar:SetParent(hiddenParent)
            end
        end
        -- Both event broadcasters are quieted at file-load time (top of file).
        -- Redundant quieting here as a safety net in case Blizzard re-creates
        -- them; the same helper, so Blizzard's two seeding registrations stay.
        if ns.QuietBroadcasters then ns.QuietBroadcasters() end
        -- ...then hand control back to the mode machine: this safety net can
        -- run after "full" has registered, so without the resync it silently
        -- drops that tick set while the mode check believes it is still active.
        if ns.ResyncBroadcaster then ns.ResyncBroadcaster() end
    end)

    -- Hook Show on stock bars so they can never re-appear regardless
    -- of what fires them (talent changes, spec swaps, zone transitions, etc.).
    -- ReassertHiddenOnShow reparents rather than Hide()s -- see its note above
    -- hiddenParent's creation.
    for _, entry in ipairs(STOCK_BAR_DISPOSAL) do
        local bar = _G[entry.name]
        if bar then
            ns.ReassertHiddenOnShow(bar)
        end
    end

    -- Register with unlock mode immediately. FinishSetup runs at
    -- PLAYER_LOGIN, inside the pre-lockdown window on a combat reload, so
    -- registering now (instead of on a timer) lets the position pass in
    -- DoVisuals resolve anchored elements before lockdown re-engages.
    -- (EllesmereUI is a hard dependency, so it is always loaded here.)
    RegisterWithUnlockMode()

    -- Apply visibility drivers now, for the same reason: the real conditional driver
    -- strings (e.g. PetBar's [pet]-gated visibility) must register before combat
    -- lockdown re-engages -- the secure state engine then evaluates them correctly
    -- even IN combat. ApplyAll's visibility pass is skipped while in combat, so
    -- without this call a combat reload left bars on their placeholder "show" driver
    -- (petless PetBar visible) until combat dropped. Idempotent out of combat: the
    -- _eabLastVisStr cache skips unchanged re-registrations, so the later ApplyAll
    -- pass is a no-op for these. Extra bars (built on a later timer) are nil-skipped
    -- here, exactly as on a normal login.
    -- Controller verdict first (Hide Bar When Using Gamepad): on a combat
    -- reload this is the last out-of-combat moment, and the first
    -- RefreshRuntimeVisibility only lands after lockdown is back.
    self._PadSync()
    self:ApplyCombatVisibility()
    self:UpdateVehicleBarWatch()

    -- Dormancy initial sync: bars that START hidden never fire an OnHide
    -- edge, and the creation-time OnHide fired before buttons existed. Runs
    -- after the visibility drivers above have settled each frame's state.
    -- The per-key memo makes this a no-op for anything the edges already handled.
    for _, info in ipairs(BAR_CONFIG) do
        local f = barFrames[info.key]
        if f then ns.ApplyBarDormancy(info.key, not f:IsVisible()) end
    end
end
