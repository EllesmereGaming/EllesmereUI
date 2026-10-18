if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Vehicle.lua
--
--  The vehicle exit button, hiding Blizzard's vehicle and override bar,
--  the vehicle highlight fix, housing editor keybinds and grid show/hide.
--  Loads after EUI_ActionBars_Keybinds.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs, pcall = ipairs, pairs, pcall
local InCombatLockdown = InCombatLockdown
local C_Timer_After = C_Timer.After
local EFD = ns.EFD

local EAB, EAB_VTABLE, barButtons = ns.EAB, ns.EAB_VTABLE, ns.barButtons
local I = ns._internals
local _gridState, BAR_CONFIG, NUM_ACTIONBAR_BUTTONS = I._gridState, I.BAR_CONFIG, I.NUM_ACTIONBAR_BUTTONS
local SafeEnableMouse = I.SafeEnableMouse
local SetShowGridInsecure, SHOWGRID = I.SetShowGridInsecure, I.SHOWGRID
local barFrames = I.barFrames
local hoverStates = I.hoverStates
local _bindState, _eabBindOwner, UpdateKeybinds = I._bindState, I._eabBindOwner, I.UpdateKeybinds

-------------------------------------------------------------------------------
--  Vehicle Exit Button: reparent to UIParent so it stays visible when
--  ActionBarParent is hidden. Position and visibility are fully
--  Blizzard-owned (no unlock mode, no SetPoint hook). ActionBarController is
--  disabled above, so Blizzard's transition system won't reposition it.
-------------------------------------------------------------------------------
do
    local btn = MainMenuBarVehicleLeaveButton
    if btn then
        btn:SetParent(UIParent)
        local vehVis = ns.TakeShell()
        vehVis:RegisterEvent("UNIT_ENTERED_VEHICLE")
        vehVis:RegisterEvent("UNIT_EXITED_VEHICLE")
        vehVis:RegisterEvent("PLAYER_ENTERING_WORLD")
        vehVis:RegisterEvent("PLAYER_REGEN_ENABLED") -- guardrails-allow: combat-deferral by Ellesmere: moved verbatim from EllesmereUIActionBars.lua
        vehVis:SetScript("OnEvent", function(self, event, unit)
            -- Only the UNIT_ events carry a unit; PLAYER_ENTERING_WORLD's first
            -- arg is isInitialLogin, so testing it as a unit skipped the whole
            -- pass on a fresh login.
            if (event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE")
                and unit ~= "player" then
                return
            end
            if event ~= "PLAYER_REGEN_ENABLED" then
                -- MainMenuBarVehicleLeaveButton is EditMode-managed, so SetShown
                -- routes through protected HideBase/ShowBase and is blocked in ANY
                -- combat, not only inside a live keystone. Do NOT AND this with a
                -- protected-instance check: that is false in every normal dungeon and
                -- goes false the instant a key COMPLETES (requires
                -- IsChallengeModeActive), so combat vehicle events call straight
                -- through and trip ADDON_ACTION_BLOCKED. Same rule as the micro
                -- menu/bag bar site above -- InCombatLockdown is the whole gate.
                -- Nothing lost by deferring: the protected call couldn't have
                -- succeeded in combat either way, and PLAYER_REGEN_ENABLED re-applies
                -- the state on lockdown end.
                if InCombatLockdown() then return end
            end
            local show = (CanExitVehicle and CanExitVehicle()) or false
            -- A redundant SetShown on a frame already in that state still trips
            -- the block, so only issue the protected op on a real transition.
            if btn:IsShown() ~= show then
                btn:SetShown(show)
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Hide Blizzard's Vehicle / Override Bar  (opt-in)
--
--  Bar 1 already pages to [vehicleui][possessbar] and the leave button is
--  reparented to UIParent above, so nothing is lost while hidden.
--
--  Suppression is alpha + mouse on the TOP-LEVEL bar only, never SetParent,
--  never Hide, never recursion into descendants: OverrideActionBar is a
--  protected, EditMode-managed frame (reparenting taints the transition
--  code), while SetAlpha is unprotected and combat-legal. Only mouse state
--  we disabled ourselves is ever restored.
--
--  Blizzard docks the micro menu INTO this bar, where it would inherit
--  alpha 0; it is moved out instead (ReclaimMicroMenu), not disabled in
--  place.
-------------------------------------------------------------------------------

-- Snapshot where MicroMenu lives while it is still home, so the reclaim has a
-- real anchor to restore instead of guessing one.
function EAB:CacheMicroMenuHome()
    if self._eabMicroHome then return end
    if not (MicroMenu and MicroMenu.GetPoint) then return end
    -- Never snapshot while docked: a /reload inside a vehicle or pet battle
    -- would record the DOCKED anchor as "home" in the write-once cache.
    if self:MicroMenuDockedIn(OverrideActionBar) or self:MicroMenuDockedIn(PetBattleFrame) then return end
    local p, rel, relP, x, y = MicroMenu:GetPoint(1)
    if p then
        self._eabMicroHome = { p, rel, relP, x or 0, y or 0 }
    end
end

-- Blizzard docks MicroMenu several levels deep, so a one-level parent test
-- misses it. Walk the chain.
function EAB:MicroMenuDockedIn(root)
    if not (MicroMenu and root) then return false end
    local p = MicroMenu.GetParent and MicroMenu:GetParent()
    local guard = 0
    while p and guard < 8 do
        if p == root then return true end
        p = p.GetParent and p:GetParent()
        guard = guard + 1
    end
    return false
end

-- Hand MicroMenu back to its own container: left docked it inherits alpha 0
-- and sits invisible over the vehicle exit button (or, for pet battles,
-- stays parented under PetBattleFrame and never comes back at all -- MicroMenuContainer
-- stays shown and draggable in Edit Mode, but empty), still taking clicks.
-- ResetMicroMenuPosition() is NOT the right call: it re-derives the dock from
-- current game state, which mid-vehicle/mid-battle resolves back into the
-- docked frame (no-op).
function EAB:ReclaimMicroMenu()
    if InCombatLockdown() then return end
    if not (MicroMenu and MicroMenuContainer) then return end
    self:CacheMicroMenuHome()
    if not (self:MicroMenuDockedIn(OverrideActionBar) or self:MicroMenuDockedIn(PetBattleFrame)) then return end
    MicroMenu:SetParent(MicroMenuContainer)
    local h = self._eabMicroHome
    if h then
        MicroMenu:ClearAllPoints()
        MicroMenu:SetPoint(h[1], h[2] or MicroMenuContainer, h[3], h[4], h[5])
    end
    MicroMenu:SetAlpha(1)
    ns.AB_ExtraCapsShown("MicroBar")
end

-- Blizzard docks MicroMenu into PetBattleFrame for the duration of a pet
-- battle, the same multi-level docking behavior as OverrideActionBar for
-- vehicles -- confirmed via a live capture: MicroMenu's parent chain still
-- ran through PetBattleFrame two full seconds after PET_BATTLE_CLOSE, with
-- MicroMenuContainer sitting empty (but shown/draggable) the whole time.
-- Wild battles hold combat lockdown through their own close event, so the
-- reclaim (which no-ops in combat, see above) is retried once on the next
-- PLAYER_REGEN_ENABLED, same pattern as QueuePetBattleUnsuppress uses for
-- the sibling suppression bug this branch was originally about.
do
    -- One keyed combat-queue entry (idempotent), the QueuePetBattleUnsuppress
    -- shape above.
    local function ReclaimMicroMenu()
        EAB:ReclaimMicroMenu()
    end
    local function TryReclaimAfterPetBattle()
        if InCombatLockdown() then
            ns.CombatQueue.Defer("ReclaimMicroMenu", ReclaimMicroMenu)
            return
        end
        EAB:ReclaimMicroMenu()
    end
    local petBattleReclaimFrame = CreateFrame("Frame")
    petBattleReclaimFrame:RegisterEvent("PET_BATTLE_CLOSE")
    petBattleReclaimFrame:SetScript("OnEvent", TryReclaimAfterPetBattle)
end

function EAB:ApplyVehicleBarVisibility()
    local bar = OverrideActionBar
    if not bar then return end
    local hide = self.db and self.db.profile and self.db.profile.hideBlizzardVehicleBar
    if hide then
        self:ReclaimMicroMenu()
        bar:SetAlpha(0)
        -- Guarded: the restore below may only undo OUR disable, never switch
        -- on mouse Blizzard had off for its own reasons.
        if not self._eabVehMouseOff then
            self._eabVehMouseOff = true
            SafeEnableMouse(bar, false)
        end
    else
        bar:SetAlpha(1)
        if self._eabVehMouseOff then
            self._eabVehMouseOff = nil
            SafeEnableMouse(bar, true)
        end
    end
end

-- Arm or disarm the watch. Everything is created on first enable: never
-- enabled = no event frame, no registrations, no hook. HookScript cannot be
-- undone, so the hook installs at most once and gates on the setting inside;
-- disabling unregisters the events.
function EAB:UpdateVehicleBarWatch()
    local on = self.db and self.db.profile and self.db.profile.hideBlizzardVehicleBar
    local f = self._eabVehWatch
    if not on then
        if f then f:UnregisterAllEvents() end
        self:ApplyVehicleBarVisibility()
        return
    end
    if not f then
        f = ns.TakeShell()
        f:SetScript("OnEvent", function()
            EAB:CacheMicroMenuHome()
            EAB:ApplyVehicleBarVisibility()
        end)
        self._eabVehWatch = f
    end
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- The bar's own OnShow is the deterministic edge; one deferred re-assert
    -- follows because the micro menu dock can land later in the same frame.
    if not self._eabVehShowHooked and OverrideActionBar then
        self._eabVehShowHooked = true
        OverrideActionBar:HookScript("OnShow", function()
            if not (EAB.db and EAB.db.profile
                    and EAB.db.profile.hideBlizzardVehicleBar) then return end
            EAB:ApplyVehicleBarVisibility()
            C_Timer_After(0, function() EAB:ApplyVehicleBarVisibility() end)
        end)
    end
    self:ApplyVehicleBarVisibility()
end

-------------------------------------------------------------------------------
--  Vehicle Highlight Fix: during vehicle/override paging, empty MainBar
--  buttons can retain a stale "checked" state from the normal bar.
--  CheckedTexture uses the same texture as HighlightTexture, so it looks
--  like a permanent highlight. The inverted mouseover behavior (hides on
--  enter, returns on leave) is WoW's native CheckButton behavior when checked.
--  Fix: after a page change, clear the checked state and hide CheckedTexture
--  on MainBar buttons with no action on the new page.
-------------------------------------------------------------------------------
do
    local _vehHighlightPending = false

    local function FixVehicleHighlights()
        _vehHighlightPending = false
        local mainFrame = barFrames and barFrames["MainBar"]
        if not mainFrame then return end
        local page = tonumber(mainFrame:GetAttribute("actionpage")) or 1
        local buttons = barButtons and barButtons["MainBar"]
        if not buttons then return end

        -- Only apply the alpha-0 fallback on vehicle/override/bonus pages
        -- (page > 6). On normal pages (1-6), just restore alpha to 1 so
        -- Blizzard's SetChecked/UpdateState manages checked visuals normally.
        local isSpecialPage = (page > 6)

        for i, btn in ipairs(buttons) do
            if btn then
                local ct = btn.CheckedTexture
                if isSpecialPage then
                    local slot = i + (page - 1) * NUM_ACTIONBAR_BUTTONS
                    if not HasAction(slot) then
                        -- SetChecked might be protected during combat; pcall.
                        -- Also hide CheckedTexture as a visual fallback.
                        pcall(btn.SetChecked, btn, false)
                        if ct then ct:SetAlpha(0) end
                    else
                        -- Slot has an action; restore alpha so Blizzard's
                        -- UpdateState manages checked visuals (honors the
                        -- Show Highlight on Spell Cast setting).
                        if ct then ct:SetAlpha(EAB:GetCheckedAlpha("MainBar")) end
                    end
                else
                    -- Normal page: restore alpha on all buttons so checked
                    -- state renders correctly when spells are dragged in
                    -- (honors the Show Highlight on Spell Cast setting).
                    if ct then ct:SetAlpha(EAB:GetCheckedAlpha("MainBar")) end
                end
            end
        end
    end

    local function QueueVehicleHighlightFix()
        if _vehHighlightPending then return end
        _vehHighlightPending = true
        C_Timer_After(0, FixVehicleHighlights)
    end

    local vehHighlightFrame = ns.TakeShell()
    vehHighlightFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
    vehHighlightFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
    vehHighlightFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    vehHighlightFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    vehHighlightFrame:SetScript("OnEvent", QueueVehicleHighlightFix)
end


-------------------------------------------------------------------------------
--  Housing Editor Keybind Clearing: when the house editor is active, clear
--  our override bindings so Blizzard's housing hotkeys work. Restore them
--  when the editor closes.
-------------------------------------------------------------------------------
local _housingEventFrame = CreateFrame("Frame")
local IsHouseEditorActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive
if IsHouseEditorActive then
    _housingEventFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    _housingEventFrame:SetScript("OnEvent", function()
        if IsHouseEditorActive() then
            -- House editor opened: clear ALL override bindings so housing hotkeys work
            if _bindState.housingCleared then return end
            _bindState.housingCleared = true
            if not InCombatLockdown() then
                ClearOverrideBindings(_eabBindOwner)
                -- Bindings no longer match the cached signature; force the
                -- next UpdateKeybinds to rebuild even if routing is identical.
                _bindState.sigValid = false
            end
        else
            -- House editor closed: restore our override bindings. Call
            -- unconditionally -- UpdateKeybinds defers itself in combat, and a
            -- combat guard here would drop the restore with nothing to re-arm
            -- it, leaving every override binding cleared until reload.
            if not _bindState.housingCleared then return end
            _bindState.housingCleared = false
            UpdateKeybinds()
        end
    end)
end

-------------------------------------------------------------------------------
--  Grid Show/Hide (show empty slots during spell drag)
-------------------------------------------------------------------------------

-- Reached only on a real off -> on edge: ns.EABQueueGrid settles the event
-- storm a bag sort produces (its old 0.1s throttle here could not, because
-- every HIDEGRID in the storm reset _gridState.shown and re-armed it).
local function OnGridChange()
    if InCombatLockdown() then return end
    _gridState.shown = true

    -- Propagate showgrid to the controller so the secure environment
    -- knows buttons should be visible (handles combat transitions).
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local buttons = barButtons[info.key]
            if buttons then
                for _, btn in ipairs(buttons) do
                    if btn then
                        SetShowGridInsecure(btn, true, SHOWGRID.GAME_EVENT)
                    end
                end
            end
        end
    end

    -- When the player starts dragging a spell, show all button slots
    -- so they can see where to drop it (even empty ones).
    -- Respect the icon cutoff so hidden overflow buttons stay hidden.
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            local s = EAB.db.profile.bars[info.key]
            local numIcons = s and (s.overrideNumIcons or s.numIcons) or info.count
            if not numIcons or numIcons < 1 then numIcons = info.count end
            if numIcons > info.count then numIcons = info.count end
            if info.isStance then numIcons = GetNumShapeshiftForms() or info.count end
            if numIcons < 1 then numIcons = 1 end
            for i = 1, numIcons do
                local btn = buttons[i]
                if btn then
                    -- Clear statehidden so the secure UpdateShown snippet
                    -- allows the button to stay visible during drag.
                    if btn:GetAttribute("statehidden") then
                        btn:SetAttributeNoHandler("statehidden", nil)
                    end
                    local gfd = EFD(btn)
                    if gfd.slotBG then gfd.slotBG:Show() end
                    -- Show borders during drag
                    if gfd.borders and not (gfd.shapeMask and gfd.shapeMask:IsShown()) then
                        gfd.borders:Show()
                    end
                    if gfd.shapeBorder and EFD(gfd.shapeBorder).wantsShow then
                        gfd.shapeBorder:Show()
                    end
                    -- Make hidden empty buttons visible during drag. The park
                    -- verdict is taken before the Show: our own Show keeps
                    -- alpha, so it must not read as a secure reveal.
                    local parked = ns._eabParked(btn)
                    btn:Show()
                    if parked then
                        btn:SetAlpha(1)
                    end
                    gfd.parkA0 = nil
                    -- Re-enable mouse so empty slots accept drops
                    SafeEnableMouse(btn, true)
                end
            end
        end
    end

    -- Mouseover bar forcing moved to CURSOR_CHANGED handler, which only
    -- fires for real cursor drags. ACTIONBAR_SHOWGRID also fires for
    -- equipment changes, bag sorts, etc. which should not affect mouseover.
end

-- Show All During Drag: restore bars saved as Never that were surfaced for a
-- cursor drag (CURSOR_CHANGED handler). Idempotent, safe from every drag-end
-- path. Clears only the overrides the drag itself planted, so a
-- toggle-keybind override the user set stays intact. If the drag ends in
-- combat the driver swap is deferred: RefreshRuntimeVisibility skips secure
-- writes there, and PLAYER_REGEN_ENABLED's ApplyAll re-runs it clean.
function EAB._RestoreDragNeverBars()
    local forced = _gridState._dragNeverForced
    if not forced then return end
    _gridState._dragNeverForced = nil
    if EAB._visOverride then
        for key in pairs(forced) do
            if EAB._visOverride[key] == "always" then
                EAB._visOverride[key] = nil
            end
        end
    end
    EAB:RefreshRuntimeVisibility()
    -- A bar opted into BOTH drag and spellbook surfacing skips the spellbook
    -- plant while the drag override holds it; re-evaluate so it stays up when
    -- the drag ends with the spellbook still open.
    EAB._UpdateSpellbookNeverBars()
end

-- Show When Spellbook Is Open (per-bar opt-in, s.spellbookShow, ANY
-- visibility mode): while the spellbook (PlayerSpellsFrame) or macro panel
-- (MacroFrame) is open, opted-in bars force-show the same way a cursor drag
-- surfaces them by default:
--   * non-always modes (Never, conditional drivers) plant the runtime
--     _visOverride slot (never persisted) -- own forced-set so the drag
--     trigger and this one restore independently; same combat guard
--     (secure driver swaps are combat-blocked; a panel opened mid-combat
--     surfaces once combat ends, through the module's combat queue).
--   * mouseover bars force alpha 1 (StopFade), re-asserted on every call
--     because a drag's grid-hide fade can land while the panel stays open;
--     released to the normal fade-out on close unless hovered.
-- resync = drop everything planted first and re-evaluate (options toggle
-- flips while the panel is already open). While the option stands down
-- (EAB._sbOff, set by the wiring below; the options grey its row) both
-- panels count as closed.
function EAB._UpdateSpellbookNeverBars(resync)
    local open = not EAB._sbOff and ((PlayerSpellsFrame and PlayerSpellsFrame:IsShown())
        or (MacroFrame and MacroFrame:IsShown()))
    if resync == true or not open then
        local forced = _gridState._sbNeverForced
        if forced then
            _gridState._sbNeverForced = nil
            if EAB._visOverride then
                for key in pairs(forced) do
                    if EAB._visOverride[key] == "always" then
                        EAB._visOverride[key] = nil
                    end
                end
            end
            EAB:RefreshRuntimeVisibility()
        end
        local mo = _gridState._sbMoForced
        if mo then
            _gridState._sbMoForced = nil
            for key in pairs(mo) do
                local s = EAB.db.profile.bars[key]
                local state = hoverStates[key]
                if s and s.mouseoverEnabled and state and not state.isHovered then
                    EAB_VTABLE.Hover.FadeOut(key, state)
                end
            end
        end
        if not open then return end
    end
    if InCombatLockdown() then
        -- The panel may close before combat ends: the queued pass reads it again.
        ns.CombatQueue.Defer("SpellbookNever", EAB._UpdateSpellbookNeverBars)
    elseif not _gridState._sbNeverForced then
        local forced
        for _, info in ipairs(BAR_CONFIG) do
            local s = EAB.db.profile.bars[info.key]
            if s and s.spellbookShow and s.enabled ~= false
               and ((s.barVisibility or "always") ~= "always" or s.alwaysHidden
                    or (EAB._padHide and s.gamepadHideBar == true))
               and not (EAB._visOverride and EAB._visOverride[info.key]) then
                EAB._visOverride = EAB._visOverride or {}
                EAB._visOverride[info.key] = "always"
                forced = forced or {}
                forced[info.key] = true
            end
        end
        if forced then
            _gridState._sbNeverForced = forced
            EAB:RefreshRuntimeVisibility()
        end
    end
    local mo
    for _, info in ipairs(BAR_CONFIG) do
        local s = EAB.db.profile.bars[info.key]
        if s and s.spellbookShow and s.enabled ~= false and s.mouseoverEnabled then
            local frame = barFrames[info.key]
            if frame then
                -- Through the hover system's OWN fade-in, never a raw
                -- SetAlpha: FadeInOne targets the bar's true shown alpha
                -- (_savedBarAlpha) and keeps state.fadeDir truthful --
                -- a raw SetAlpha leaves the resting "out" memo in place,
                -- so the close-path FadeOut treats the bar as already
                -- faded and skips it (bar stuck visible until a hover).
                EAB_VTABLE.Hover.FadeInOne(info.key,
                    EAB_VTABLE.Hover.GetState(info.key, frame))
                mo = mo or {}
                mo[info.key] = true
            end
        end
    end
    _gridState._sbMoForced = mo
end

-- Trigger wiring: OnShow/OnHide HookScripts on the two panels (both are
-- LoadOnDemand -- ADDON_LOADED installs late hooks, unregistering once both
-- are in). WoW Forever's Gamepad interface style shows and hides both panels
-- from secure code, where a hook of ours would taint it: under that style the
-- option stands down for the session (EAB._sbOff), decided once logged in and
-- again before each late hook.
do
    local hooked = {}
    local function OnPanelToggle()
        EAB._UpdateSpellbookNeverBars()
    end
    local function TryHook(name)
        if hooked[name] then return true end
        local f = _G[name]
        if not f then return false end
        hooked[name] = true
        f:HookScript("OnShow", OnPanelToggle)
        f:HookScript("OnHide", OnPanelToggle)
        return true
    end
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_LOGIN")
    ev:SetScript("OnEvent", function(self, event, addon)
        if event == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
            if EllesmereUI.PadGamepadUI() then
                EAB._sbOff = true
                return
            end
            local a, b = TryHook("PlayerSpellsFrame"), TryHook("MacroFrame")
            if not (a and b) then self:RegisterEvent("ADDON_LOADED") end
        else
            local name = (addon == "Blizzard_PlayerSpells" and "PlayerSpellsFrame")
                or (addon == "Blizzard_MacroUI" and "MacroFrame")
            if not name then return end
            if EllesmereUI.PadGamepadUI() then
                -- Switched to that style since login: no late hook, and a hook
                -- already in place sees both panels as closed from here on.
                EAB._sbOff = true
                self:UnregisterEvent("ADDON_LOADED")
                EAB._UpdateSpellbookNeverBars()
                return
            end
            TryHook(name)
            if hooked.PlayerSpellsFrame and hooked.MacroFrame then
                self:UnregisterEvent("ADDON_LOADED")
            end
        end
    end)
end

-- Entry points the files after this one re-import by name. The housing API
-- may be absent: false keeps the key published (a nil publish would make
-- Setup's import raise), and Setup's guard reads false as "no editor".
I.IsHouseEditorActive, I.OnGridChange = IsHouseEditorActive or false, OnGridChange
