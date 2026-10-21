if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_BlizzardSkin_TooltipVisibility.lua
--
--  When the tooltip shows: the Show Tooltips mode with its peek modifier
--  and the comparison cleanup, and the unit health strip.
--  Reads EllesmereUIBlizzardSkin.lua through ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- EllesmereUIBlizzardSkin.lua or an earlier EUI_BlizzardSkin_*.lua file
-- failed to load.
if not I or I.last ~= "TooltipAnchor" then return end

local FFD = I.FFD

-------------------------------------------------------------------------------
--  Show Tooltips (global visibility mode). The "Blizzard Tooltip" dropdown
--  (EllesmereUIDB.tooltipShowMode, default "always") suppresses the game tooltip
--  by combat state across both default-anchored and explicitly-owned paths.
--  The default-anchor post-hook also serves the cursor anchor; the SetOwner
--  post-hook covers action buttons, item slots, and custom tooltip owners.
--    always          -> never suppressed (default; the hook early-outs)
--    outOfCombat     -> hidden while in combat lockdown
--    outOfBossCombat -> hidden while a boss encounter is in progress
--    never           -> hidden always
--  IsEncounterInProgress() is queried inline (outOfBossCombat only) for the visibility
--  decision. Comparison cleanup support is installed lazily only when a non-default
--  mode is active; the default mode adds no comparison hooks or state events. An optional
--  "peek" modifier
--  (tooltipShowModifier) lifts suppression while held, so a suppressed tip can be
--  read on hover mid-combat. Suppression keeps the tooltip SHOWN but parked in a
--  hidden host frame (never Hide, never alpha) so peek is a pure reparent flip:
--  rebuilding a hidden tooltip from insecure code errors on secret cooldown data in combat, and alpha is engine-owned (FadeOut snaps it back and leaks the tip).
-------------------------------------------------------------------------------
do
    local function ShowModifierHeld()
        local mod = (EllesmereUIDB and EllesmereUIDB.tooltipShowModifier) or "none"
        if mod == "none" then return false end
        if mod == "control" then return IsControlKeyDown() end
        if mod == "alt" then return IsAltKeyDown() end
        return IsShiftKeyDown()
    end

    -- Exposed so modules with their own tooltip suppression (e.g. raid/party frames, whose OnEnter hides tips per its own combat mode) can let the same peek modifier reveal their tips.
    function EllesmereUI._tooltipPeekHeld()
        return ShowModifierHeld()
    end

    local EnsureComparisonSupport
    local UpdateStateWatcher
    local _comparisonSupportActive = false
    local _comparisonStateWatcherRegistered = false

    local function ComparisonSuppressionModeEnabled()
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return false end
        return ((EllesmereUIDB and EllesmereUIDB.tooltipShowMode) or "always") ~= "always"
    end

    local function ComparisonStateWatcherNeeded()
        local mode = (EllesmereUIDB and EllesmereUIDB.tooltipShowMode) or "always"
        return ComparisonSuppressionModeEnabled()
            and (mode == "outOfCombat" or mode == "outOfBossCombat")
    end

    -- Shared decision: should GameTooltip be suppressed right now given the user's "Show
    -- Tooltips" mode + combat state? Exposed on EllesmereUI so the cursor-anchor hook can honor it too (else cursor re-anchor would re-show a tooltip this hook just hid).
    function EllesmereUI._tooltipSuppressedByMode(tooltip)
        if tooltip ~= GameTooltip then return false end
        if tooltip.IsForbidden and tooltip:IsForbidden() then return false end
        -- Gated by the "Reskin Tooltip" master (matches the grayed-out "Show Tooltips" option), so disabling the reskin never leaves tooltips stuck suppressed at, e.g., "Never".
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then
            if UpdateStateWatcher and (_comparisonSupportActive or _comparisonStateWatcherRegistered) then
                UpdateStateWatcher()
            end
            return false
        end
        local mode = (EllesmereUIDB and EllesmereUIDB.tooltipShowMode) or "always"
        if mode == "always" then
            if UpdateStateWatcher and (_comparisonSupportActive or _comparisonStateWatcherRegistered) then
                UpdateStateWatcher()
            end
            return false
        end
        if EnsureComparisonSupport then EnsureComparisonSupport() end
        if UpdateStateWatcher then UpdateStateWatcher() end
        if ShowModifierHeld() then return false end
        if mode == "never" then
            return true
        elseif mode == "outOfCombat" then
            return InCombatLockdown()
        elseif mode == "outOfBossCombat" then
            return IsEncounterInProgress()
        end
        return false
    end

    -- Item comparisons are rendered by separate ShoppingTooltip frames. Parking
    -- GameTooltip alone therefore leaves the side-by-side comparison visible in
    -- combat when alwaysCompareItems is enabled. Keep the cleanup in this global
    -- tooltip controller rather than in ActionBars: bags, world items, and every
    -- other default-anchored item tooltip use the same comparison manager.
    -- Use Blizzard's existing comparison-suppression control field; addon-owned
    -- state stays in the shared weak-keyed FFD table so no custom state is stored
    -- on Blizzard frames.
    local _comparisonTooltips
    local _comparisonClearPending = false

    local function GetComparisonTooltips()
        if not _comparisonTooltips then
            _comparisonTooltips = { ShoppingTooltip1, ShoppingTooltip2 }
        end
        return _comparisonTooltips
    end

    local _comparisonFlagOwned = false
    local _parked = false
    local function GetComparisonState(tooltip, create)
        local state = FFD[tooltip]
        if not state and create then
            state = {}
            FFD[tooltip] = state
        end
        return state
    end

    local function ReadComparisonSuppressionFlag(tooltip)
        return tooltip.suppressAutomaticCompareItem
    end

    local function WriteComparisonSuppressionFlag(tooltip, value)
        -- Blizzard exposes this field as the per-tooltip opt-out for automatic
        -- comparisons. It is a Blizzard control input, not addon-owned state.
        tooltip.suppressAutomaticCompareItem = value
    end

    local function ForgetComparisonSuppression(tooltip)
        if not _comparisonFlagOwned or tooltip ~= GameTooltip then return end
        local state = GetComparisonState(tooltip, false)
        if state then
            state.comparisonFlagPrevious = nil
            state.comparisonFlagOwned = nil
        end
        _comparisonFlagOwned = false
    end

    local function ReleaseComparisonSuppression(tooltip)
        if not _comparisonFlagOwned or tooltip ~= GameTooltip then return end
        local state = GetComparisonState(tooltip, false)
        if not state or not state.comparisonFlagOwned then
            _comparisonFlagOwned = false
            return
        end
        if not pcall(WriteComparisonSuppressionFlag, tooltip, state.comparisonFlagPrevious) then return end
        ForgetComparisonSuppression(tooltip)
    end

    local function ArmComparisonSuppression(tooltip)
        if tooltip ~= GameTooltip then return end
        local state = GetComparisonState(tooltip, true)
        local owned = _comparisonFlagOwned and state.comparisonFlagOwned
        if not owned then
            local readOK, previous = pcall(ReadComparisonSuppressionFlag, tooltip)
            if not readOK then return end
            state.comparisonFlagPrevious = previous
            state.comparisonFlagOwned = true
            _comparisonFlagOwned = true
        end
        -- Arm at the default anchor and again from the item pre-call below. Item
        -- setters can fire OnHide while rebuilding content, which resets this
        -- Blizzard field after the anchor hook but before comparison finalization.
        if not pcall(GameTooltip_SuppressAutomaticCompareItem, tooltip) and not owned then
            ForgetComparisonSuppression(tooltip)
        end
    end

    local function OnItemTooltipPreCall(tooltip)
        -- Parking is the authoritative scope. Re-arm after item setters reset the
        -- Blizzard field so every parked item path stays comparison-suppressed.
        if tooltip ~= GameTooltip or not _parked then return end
        ArmComparisonSuppression(tooltip)
    end

    local function RegisterComparisonPreCall()
        TooltipDataProcessor.AddTooltipPreCall(Enum.TooltipDataType.Item, OnItemTooltipPreCall)
    end

    local _comparisonPreCallAttempted = false
    local function InstallComparisonPreCall()
        if _comparisonPreCallAttempted then return end
        _comparisonPreCallAttempted = true
        -- Midnight provides this processor before addon code loads. Keep the
        -- registration protected so a missing API falls back to after-show cleanup.
        pcall(RegisterComparisonPreCall)
    end

    local function ClearSuppressedComparisons()
        -- Only clear comparisons while this controller is actually parking the
        -- global tooltip. Unparked shows (mode off, or a transient rebuild)
        -- keep their legitimate comparisons untouched.
        if not _parked or not EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end

        -- Clear the manager's state and its owned shopping frames through the
        -- same public method Blizzard calls from GameTooltip_OnHide.  Fall back
        -- to Blizzard's helper only when the manager is unavailable, does not
        -- own GameTooltip, or errors; avoid a third direct Hide pass over global
        -- shopping frames that may belong to another tooltip path.
        local managerCleared = false
        if TooltipComparisonManager
            and TooltipComparisonManager.tooltip == GameTooltip
            and type(TooltipComparisonManager.Clear) == "function" then
            managerCleared = pcall(TooltipComparisonManager.Clear, TooltipComparisonManager, GameTooltip)
        end
        if not managerCleared and GameTooltip_HideShoppingTooltips then
            pcall(GameTooltip_HideShoppingTooltips, GameTooltip)
        end
    end

    local function RunSuppressedComparisonClear()
        _comparisonClearPending = false
        ClearSuppressedComparisons()
    end
    local function QueueSuppressedComparisonClear()
        if not _comparisonSupportActive then return end
        -- Queue only while parked: an unparked build's comparisons are
        -- legitimate and must not be cleared after their owner refreshes.
        if not _parked then return end
        if not ComparisonSuppressionModeEnabled()
            or not EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end
        if _comparisonClearPending then return end
        _comparisonClearPending = true
        -- This hook can run from Blizzard's protected tooltip/owner path.
        -- Defer all Hide/Clear calls out of that stack, matching the existing EUI
        -- tooltip-skin deferral rules.
        C_Timer.After(0, RunSuppressedComparisonClear)
    end

    local _comparisonTooltipHooksInstalled = false
    local _comparisonManagerHookInstalled = false
    local _comparisonHideHookInstalled = false
    local function InstallComparisonHooks()
        if EllesmereUI.BlizzSkinPadStandDown() then return end
        InstallComparisonPreCall()

        if not _comparisonHideHookInstalled then
            GameTooltip:HookScript("OnHide", function(tt)
                -- Item setters can fire OnHide while rebuilding content, so do not latch
                -- owner eligibility here. Active state is derived from IsShown instead.
                if not (_comparisonSupportActive or _comparisonStateWatcherRegistered) then return end
                if EllesmereUI._tooltipSuppressedByMode(tt) then
                    QueueSuppressedComparisonClear()
                end
            end)
            -- Blizzard resets the field itself before hooks run, so only forget
            -- our ownership; restoring would overwrite Blizzard's reset.
            GameTooltip:HookScript("OnHide", ForgetComparisonSuppression)
            _comparisonHideHookInstalled = true
        end

        if not _comparisonTooltipHooksInstalled then
            for _, comparisonTooltip in ipairs(GetComparisonTooltips()) do
                if comparisonTooltip and comparisonTooltip.HookScript then
                    comparisonTooltip:HookScript("OnShow", function()
                        if not _comparisonSupportActive then return end
                        if EllesmereUI._tooltipSuppressedByMode(GameTooltip) then
                            QueueSuppressedComparisonClear()
                        end
                    end)
                end
            end
            _comparisonTooltipHooksInstalled = true
        end

        if not _comparisonManagerHookInstalled
            and TooltipComparisonManager
            and type(TooltipComparisonManager.AnchorShoppingTooltips) == "function" then
            hooksecurefunc(TooltipComparisonManager, "AnchorShoppingTooltips", QueueSuppressedComparisonClear)
            _comparisonManagerHookInstalled = true
        end
    end

    EnsureComparisonSupport = function()
        if not ComparisonSuppressionModeEnabled() then return false end
        _comparisonSupportActive = true
        InstallComparisonHooks()
        return true
    end

    -- Suppression parks the tooltip in a hidden host frame -- NOT Hide(), NOT alpha.
    -- Hide()-based suppression forced peek to REBUILD the tooltip from our insecure
    -- execution: in combat, action tooltips read secret cooldown data and the rebuild
    -- hard-errors ("secret values are only allowed during untainted execution"),
    -- silently swallowed by FireHoveredOnEnter's pcall -- peek looked dead in combat
    -- on action bars. Alpha-based suppression fought the engine: FadeOut (hover-off
    -- on world units) snaps alpha back to full and animates it down, leaking the tip.
    -- Parking wins both ways: the tooltip stays SHOWN (secure hover path keeps
    -- building/refreshing it), visibility inherits from the hidden host regardless of
    -- engine alpha, and peek is a pure reparent flip. Parking itself never calls Hide;
    -- item setters may still fire transient OnHide while rebuilding, so restore relies
    -- on the next SetOwner. Every tooltip build starts there, covering both explicit
    -- owners and the SetOwner call inside GameTooltip_SetDefaultAnchor.
    local _suppressHost = CreateFrame("Frame", nil, UIParent)
    _suppressHost:Hide()
    local _origParent
    local function ParkTooltip(tt)
        if _parked then return end
        _parked = true
        _origParent = tt:GetParent()
        if _origParent == _suppressHost then _origParent = nil end
        tt:SetParent(_suppressHost)
    end
    local function UnparkTooltip(tt)
        if not _parked then return end
        _parked = false
        tt:SetParent(_origParent or UIParent)
        -- SetParent can demote strata; the tooltip must stay topmost.
        -- GetFrameStrata() returns a secret string once the tooltip carries
        -- secret unit data, and SetFrameStrata rejects secrets from addons.
        tt:SetFrameStrata("TOOLTIP")
    end
    local function ApplySuppression(tt)
        if EllesmereUI._tooltipSuppressedByMode(tt) then
            ArmComparisonSuppression(tt)
            ParkTooltip(tt)
            QueueSuppressedComparisonClear()
        else
            ReleaseComparisonSuppression(tt)
            UnparkTooltip(tt)
        end
    end
    local _modeShowHookInstalled = false
    local function EnsureModeShowHook()
        if _modeShowHookInstalled or EllesmereUI.BlizzSkinPadStandDown() then return end
        _modeShowHookInstalled = true
        -- Item data can hide and re-show the tooltip without another SetOwner,
        -- including after asynchronous data arrives. Re-apply before it renders.
        GameTooltip:HookScript("OnShow", function(tt)
            ApplySuppression(tt)
        end)
    end
    local function SuppressTooltipByMode(tooltip)
        if tooltip ~= GameTooltip then return end
        ApplySuppression(tooltip)
    end
    if GameTooltip_SetDefaultAnchor then
        hooksecurefunc("GameTooltip_SetDefaultAnchor", SuppressTooltipByMode)
    end
    hooksecurefunc(GameTooltip, "SetOwner", function(tt)
        -- Restore the previous build before starting the new owner path. The flag
        -- makes this a single branch until comparison support has owned it.
        if _comparisonFlagOwned then
            ReleaseComparisonSuppression(tt)
        end
        UnparkTooltip(tt)
        -- Explicitly-owned paths must follow the same global visibility mode as
        -- default-anchored paths. This includes action buttons, container items,
        -- character equipment slots, and custom EUI tooltip owners.
        if ComparisonSuppressionModeEnabled() then
            ApplySuppression(tt)
        end
    end)

    -- Re-apply the mode when combat/encounter state changes while a tooltip is
    -- already alive.  Install these events only for the two modes that need
    -- transition handling; "Never" is handled by the tooltip hooks alone.
    local stateWatcher
    local function UnregisterStateWatcher()
        if not _comparisonStateWatcherRegistered then return end
        stateWatcher:UnregisterAllEvents()
        _comparisonStateWatcherRegistered = false
    end
    local function StateWatcherOnEvent()
        if not ComparisonStateWatcherNeeded() then
            UpdateStateWatcher()
            return
        end
        -- Only act when the new state requires suppression.  Do not unpark on
        -- combat/encounter end: the cursor may have left the owner while the
        -- parked tooltip remained logically shown, and unpark would resurrect
        -- stale content.  The next SetOwner path restores it normally.
        if not EllesmereUI._tooltipSuppressedByMode(GameTooltip) then return end
        if GameTooltip:IsShown() then
            ApplySuppression(GameTooltip)
        end
        QueueSuppressedComparisonClear()
    end
    UpdateStateWatcher = function()
        if not ComparisonSuppressionModeEnabled() then
            ReleaseComparisonSuppression(GameTooltip)
            _comparisonSupportActive = false
            UnregisterStateWatcher()
            return
        end
        EnsureComparisonSupport()
        EnsureModeShowHook()
        if not ComparisonStateWatcherNeeded() then
            UnregisterStateWatcher()
            return
        end
        if not stateWatcher then
            stateWatcher = CreateFrame("Frame")
            stateWatcher:SetScript("OnEvent", StateWatcherOnEvent)
        end
        if not _comparisonStateWatcherRegistered then
            stateWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
            stateWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
            stateWatcher:RegisterEvent("ENCOUNTER_START")
            stateWatcher:RegisterEvent("ENCOUNTER_END")
            _comparisonStateWatcherRegistered = true
        end
    end
    -- First pass at login, once the interface style is known.
    local loginWatch = CreateFrame("Frame")
    loginWatch:RegisterEvent("PLAYER_LOGIN")
    loginWatch:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        UpdateStateWatcher()
    end)

    -- Live peek: pressing the modifier while already hovering reveals the tip
    -- for the current frame; releasing hides it again. Moving onto other frames
    -- while held reveals each in turn through the normal hover path -- suppression is lifted while held (globally via
    -- _tooltipSuppressedByMode, and per-module via _tooltipPeekHeld, honored by raid/party frames in their own OnEnter).
    local function KeyMatchesModifier(key, mod)
        return (mod == "shift"   and (key == "LSHIFT" or key == "RSHIFT"))
            or (mod == "control" and (key == "LCTRL"  or key == "RCTRL"))
            or (mod == "alt"     and (key == "LALT"   or key == "RALT"))
    end
    -- Reveal the tooltip for whatever the cursor is over. First re-run the
    -- hovered frame's OnEnter (buttons, icons, unit frames build their own tip)
    -- -- the topmost mouse-focus frame is often an overlay without one, so scan
    -- every frame under the cursor and walk up parents. Nameplates' clickable
    -- frame has an OnEnter that builds nothing (its tip comes from the engine's
    -- mouseover unit on a real hover), so fall back to driving the unit tooltip directly when one is up.
    -- Skip forbidden frames entirely; any access (even GetScript/GetParent) hard-errors.
    local function IsFrameForbidden(frame)
        return frame and frame.IsForbidden and frame:IsForbidden()
    end
    -- Skip protected frames; firing their secure OnEnter from insecure code is
    -- ADDON_ACTION_BLOCKED (not pcall-catchable). Nothing is lost: their tips are
    -- built by the secure hover path and revealed via the parked lane, and unit
    -- buttons still land a tip through the mouseover fallback below.
    local function IsFrameProtected(frame)
        return frame and frame.IsProtected and frame:IsProtected()
    end
    local function FireHoveredOnEnter()
        local foci = GetMouseFoci()
        local anchorFrame = foci and foci[1]
        if IsFrameForbidden(anchorFrame) then anchorFrame = nil end
        if foci then
            for _, focus in ipairs(foci) do
                local frame = focus
                while frame and frame ~= WorldFrame and frame ~= UIParent do
                    if IsFrameForbidden(frame) then
                        break
                    end
                    if not IsFrameProtected(frame) and frame.GetScript then
                        local ok, onEnter = pcall(frame.GetScript, frame, "OnEnter")
                        if ok and onEnter then
                            pcall(onEnter, frame)
                            if GameTooltip:IsShown() then return end
                            anchorFrame = frame
                            break
                        end
                    end
                    if not frame.GetParent then break end
                    local okParent, parent = pcall(frame.GetParent, frame)
                    if not okParent or IsFrameForbidden(parent) then break end
                    frame = parent
                end
            end
        end
        if not GameTooltip:IsShown() and UnitExists("mouseover") then
            GameTooltip_SetDefaultAnchor(GameTooltip, anchorFrame or UIParent)
            GameTooltip:SetUnit("mouseover")
            if EllesmereUI._repointTooltipAtCursor then
                EllesmereUI._repointTooltipAtCursor(GameTooltip)
            end
            GameTooltip:Show()
        end
    end
    local modWatcher = CreateFrame("Frame")
    modWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
    modWatcher:SetScript("OnEvent", function(_, _event, key, down)
        if EllesmereUIDB and EllesmereUIDB.customTooltips == false then return end
        local mod = (EllesmereUIDB and EllesmereUIDB.tooltipShowModifier) or "none"
        if mod == "none" or not KeyMatchesModifier(key, mod) then return end
        if down == 1 then
            if _parked and GameTooltip:IsShown() then
                -- The parked tip is alive and current under the cursor (built by the secure hover path): just reveal it, never rebuild from here (see the parking note above).
                ReleaseComparisonSuppression(GameTooltip)
                UnparkTooltip(GameTooltip)
            else
                -- No live tip: module-built tips (raid frames, CDM) skip building while suppressed, so re-drive the hovered frame's OnEnter -- with the modifier now held they build normally.
                FireHoveredOnEnter()
            end
        elseif GameTooltip:IsShown() and EllesmereUI._tooltipSuppressedByMode(GameTooltip) then
            ArmComparisonSuppression(GameTooltip)
            ParkTooltip(GameTooltip)
            QueueSuppressedComparisonClear()
        end
    end)
end

-------------------------------------------------------------------------------
--  Hide Unit Health Strip. GameTooltipStatusBar is Blizzard's health bar at
--  the bottom of unit tooltips; suppressed with a single SetAlpha(0) -- fully
--  taint-safe (only the top-level bar touched, never Shown/Hidden or given
--  custom keys, observed via hooksecurefunc never SetScript). The hook fires
--  only when Blizzard shows the bar, covering every anchor path (default,
--  cursor, unit-frame), and early-outs when off (one table read when
--  disabled, one SetAlpha when enabled). Default ENABLED (nil/true = hidden); independent of the reskin, works on default Blizzard tooltips too.
-------------------------------------------------------------------------------
do
    local function _healthStripHidden()
        -- Default enabled: hidden unless the user explicitly turned it off.
        return not (EllesmereUIDB and EllesmereUIDB.tooltipHideHealthStrip == false)
    end

    -- Live apply for the options toggle (immediate hide/restore) and login seed.
    EllesmereUI._applyTooltipHealthStrip = function()
        if not GameTooltipStatusBar then return end
        GameTooltipStatusBar:SetAlpha(_healthStripHidden() and 0 or 1)
    end

    -- Texture + height of the reskinned strip. Only the tooltip reskin restyles
    -- the bar, so this is a no-op until _ttInitVisual has called it with
    -- init=true; the options setters then re-apply live.
    local styled, texLookup
    EllesmereUI._applyTooltipHealthStripStyle = function(init)
        if init then styled = true end
        if not styled or not GameTooltipStatusBar then return end
        local db = EllesmereUIDB
        local key = db and db.tooltipHealthStripTexture
        local path = "Interface\\TargetingFrame\\UI-StatusBar"
        if key and key ~= "blizzard" then
            if not texLookup then texLookup = EllesmereUI.BuildBarTextureTables() end
            path = EllesmereUI.ResolveTexturePath(texLookup, key, "Interface\\Buttons\\WHITE8X8")
        end
        GameTooltipStatusBar:SetStatusBarTexture(path)
        GameTooltipStatusBar:SetHeight(db and db.tooltipHealthStripHeight or 3)
    end

    if GameTooltipStatusBar then
        -- Re-assert alpha 0 each time Blizzard shows the bar so it can never flash back into view (SetAlpha doesn't call Show, so no recursion).
        hooksecurefunc(GameTooltipStatusBar, "Show", function(bar)
            if _healthStripHidden() then bar:SetAlpha(0) end
        end)
        EllesmereUI._applyTooltipHealthStrip()
    end
end

I.last = "TooltipVisibility"
