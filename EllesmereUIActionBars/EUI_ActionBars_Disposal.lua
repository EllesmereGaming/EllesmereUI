if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Disposal.lua
--
--  The hidden dump frame and the early disposal of Blizzard's stock action
--  bars, which runs while this file loads.
--  Loads after EllesmereUIActionBars.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs, type, pcall = ipairs, pairs, type, pcall
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local GetBindingKey = GetBindingKey

local ForceCooldownPaint = ns.ForceCooldownPaint
local I = ns._internals
local FormatHotkeyText = I.FormatHotkeyText

-------------------------------------------------------------------------------
--  Hidden Dump Frame -- reparenting stock frames here is safer than :Hide(),
--  which can trigger taint chains in protected code paths. Full-size so
--  reparented frames keep valid rect queries.
-------------------------------------------------------------------------------
local hiddenParent = CreateFrame("Frame", "EABHiddenParent", UIParent)
hiddenParent:SetAllPoints(UIParent)
hiddenParent:Hide()

-- Quietly hide a Blizzard action button without ever calling a protected
-- Hide()/SetShown(): Blizzard's own UpdateShownButtons (ActionBar.lua) reads
-- the statehidden attribute on its next pass and calls SetShown(false)
-- itself. That next pass is not immediate, so this alone does not guarantee
-- the button reports Hidden right away -- every caller already reparents or
-- hides the button's bar ancestor first, which is what keeps it invisible
-- in the meantime. On ns, not a file local.
function ns.QuietlyHideBlizzButton(btn)
    btn:UnregisterAllEvents()
    btn:SetAttributeNoHandler("statehidden", true)
end

-- Re-hide a stock bar Blizzard just re-Show()'d, without calling Hide() or
-- HideBase(): both route through a protected setter (SetShownBase, reached
-- either directly or via Edit Mode's HideOverride/UpdateVisibility) from
-- addon-context Lua, and the next combat-transition SetShownBase call then
-- hits ADDON_ACTION_BLOCKED -- the confirmed cause of the
-- MultiBarBottomLeftButton1 SetShown crash reported from Cooldown Manager
-- play. Reparenting under hiddenParent needs no protected call and achieves
-- the same result: the bar stays effectively invisible regardless of its
-- own Shown state. On ns, not a file local.
function ns.ReassertHiddenOnShow(bar)
    bar:HookScript("OnShow", function(self)
        if not InCombatLockdown() then
            self:SetParent(hiddenParent)
        end
    end)
end

-- Blizzard's two event broadcasters dispatch to ALL registered buttons, causing
-- mass redraws; our central dispatcher handles the needed events with
-- HasAction() filtering (GCD swipes ride its ACTIONBAR_UPDATE_COOLDOWN). The
-- block below quiets them at file load, before any button exists, keeping
-- exactly two of Blizzard's own registrations alive (see there), and adds the
-- rest back only while the vehicle/override bar or ExtraActionButton1 shows.
do
    -- The tick set "full" mode adds and removes: what the vehicle/override
    -- bar and ExtraActionButton1 need painted. NEVER the two seeding events.
    local _abefEvents = {
        "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_STATE",
        "ACTIONBAR_UPDATE_USABLE",
        -- Spell-typed extra-action buttons (delve abilities) carry no action
        -- slot, so their cooldown fires SPELL_UPDATE_COOLDOWN not this event.
        "SPELL_UPDATE_COOLDOWN",
        "UPDATE_SHAPESHIFT_FORM",
    }
    local _aaefEvents = {
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED",
    }
    -- The rest of what ActionBarButtonEventsFrame registers in its own OnLoad.
    -- ACTIONBAR_SLOT_CHANGED and PLAYER_ENTERING_WORLD are in neither list and
    -- are never registered or unregistered by us in any mode: those two stay
    -- Blizzard's own registrations, so their dispatch runs UNTAINTED. They are
    -- the only way Blizzard's hidden ActionButtonN twins ever learn
    -- pressAndHoldAction (Update -> UpdatePressAndHoldAction -> SetAttribute;
    -- a natively routed empower key drives those twins, not ours), and
    -- untainted is what lets that Update write the attribute in combat and
    -- hand secret cooldown values to SetCooldown in restricted content, where
    -- a dispatch of ours would raise once per twin with a running cooldown. A
    -- registration made by us taints every dispatch of that event, which is
    -- why every other event is dropped here and added back only while the
    -- vehicle/extra buttons need painting. Our EABButtons are removed from the
    -- broadcaster's frames list at creation (GetOrCreateButton), so the
    -- untainted loop only ever reaches Blizzard-owned entries.
    local _abefQuiet = {
        "UPDATE_BINDINGS", "GAME_PAD_ACTIVE_CHANGED", "PET_BAR_UPDATE",
        "UNIT_FLAGS", "UNIT_AURA", "PLAYER_MOUNT_DISPLAY_CHANGED",
    }
    -- WoW Forever puts two of Blizzard's own bars on ActionBarButtonEventsFrame,
    -- and both are on screen there: the shaman Call Totem Bar
    -- (MultiCastActionBarFrame) and the Gamepad interface style's bars (their
    -- cooldowns, keybind text, form icons and pet state ride it). For a
    -- shaman, or with that style on once logged in, Blizzard keeps every
    -- registration of that frame, untouched and so untainted. Decided once,
    -- before the first quieting: nothing of ours can put a Blizzard
    -- registration back untainted. ActionBarActionEventsFrame stays quiet for
    -- everyone: our own buttons land in its frames list through the mixin's
    -- Update (tainted entries), so its loop would carry our taint into the
    -- Blizzard bars it reaches after them.
    local _keepBlizz
    local function KeepBlizzBroadcasters()
        if _keepBlizz == nil then
            local _, cls = UnitClass("player")
            _keepBlizz = EllesmereUI.IS_FOREVER == true
                and (cls == "SHAMAN" or EllesmereUI.PadGamepadUI())
        end
        return _keepBlizz
    end
    -- Drops every registration except the two seeding events. Also the reset
    -- step of every mode change, and the setup path's safety net. Never
    -- UnregisterAllEvents on ActionBarButtonEventsFrame anywhere: it would take
    -- the seeding registrations with it, and nothing of ours can put them
    -- back untainted.
    ns.QuietBroadcasters = function()
        local abef = ActionBarButtonEventsFrame
        if abef and not KeepBlizzBroadcasters() then
            for _, ev in ipairs(_abefQuiet) do abef:UnregisterEvent(ev) end
            for _, ev in ipairs(_abefEvents) do abef:UnregisterEvent(ev) end
        end
        local aaef = ActionBarActionEventsFrame
        if aaef then aaef:UnregisterAllEvents() end
    end
    -- Retail quiets at file load, before any button exists. WoW Forever waits
    -- for login, where the interface style it decides on is settled, and from
    -- then on asks for a reload when the player switches to the Gamepad style
    -- with the broadcasters already quiet (its bars would stay unpainted).
    if EllesmereUI.IS_FOREVER and not IsLoggedIn() then
        local loginFrame = ns.TakeShell()
        local styleAsked = false
        local function StyleCheck()
            if styleAsked or not EllesmereUI.PadGamepadUI() then return end
            styleAsked = true
            loginFrame:UnregisterAllEvents()
            -- The Gamepad style's D-pad cannot reach the popup, so chat says it too.
            -- A confirm, not RequestReload: an event cannot reload, its click can.
            EllesmereUI.PrintError(EllesmereUI.L("The interface style changed. Type /reload so the action bars match it."))
            EllesmereUI:ShowConfirmPopup({
                title       = EllesmereUI.L("Reload Required"),
                message     = EllesmereUI.L("The interface style changed. Reload so the action bars match it."),
                confirmText = EllesmereUI.L("Reload Now"),
                cancelText  = EllesmereUI.L("Later"),
                reload      = true,
            })
        end
        loginFrame:RegisterEvent("PLAYER_LOGIN")
        loginFrame:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_LOGIN" then
                self:UnregisterEvent("PLAYER_LOGIN")
                ns.QuietBroadcasters()
                if not KeepBlizzBroadcasters() and not (C_EventUtils and C_EventUtils.IsEventValid
                    and not C_EventUtils.IsEventValid("INPUT_DEVICE_INTERFACE_TRANSITION")) then
                    self:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
                end
                return
            end
            -- The style is read one frame after the transition event.
            C_Timer.After(0, StyleCheck)
        end)
    else
        ns.QuietBroadcasters()
    end
    -- Add the tick set back only while needed, tracked as two independent
    -- flags so one turning off never strands the other: the vehicle/override
    -- bar (OverrideActionBarButton1-6) and ExtraActionButton1 (delve abilities
    -- with no action slot -- only this broadcaster paints them). The cost story
    -- of the quiet state: SLOT_CHANGED fires only when a slot actually changes
    -- and Blizzard's handler gates on "arg1 == 0 or arg1 == self.action", so a
    -- single twin does real work per event; PLAYER_ENTERING_WORLD is one pass
    -- over the twins per loading screen. ACTIONBAR_UPDATE_COOLDOWN, the event
    -- the perf campaign profiled out (~11x/sec at total idle), is in the tick set.
    local _vehNeed, _extraNeed = false, false
    local _broadcasterMode = "off"
    -- Cooldowns read SECRET in restricted content (instance-gated, not
    -- combat-gated), and the tick set is a registration of OURS: its dispatch
    -- runs under our taint, so Blizzard's own ActionButton_UpdateCooldown ->
    -- SetCooldown is rejected on every twin with a running cooldown, at the
    -- tick rate. No tick set there at all; the vehicle/extra buttons keep the
    -- two seeding events plus our dispatcher's direct paints.
    local function CooldownsSecret()
        if not (C_Secrets and C_Secrets.ShouldCooldownsBeSecret) then return false end
        local ok, secret = pcall(C_Secrets.ShouldCooldownsBeSecret)
        return (ok and secret) and true or false
    end
    -- Never on WoW Forever. Its UpdateAction reads the cast-animation fields
    -- (actionButtonCastType) before anything else, and our dispatch of the
    -- tick and spellcast sets writes those fields onto every Blizzard button
    -- tainted: one episode left Blizzard's own seeding dispatch tainted for
    -- the session (blocked SetShown and rejected secret cooldowns in combat,
    -- the gamepad bars' class flyout). Kept broadcasters need nothing added,
    -- and our dispatcher paints ExtraActionButton1 and the override bar.
    local function ApplyBroadcaster()
        local want = (_vehNeed or _extraNeed) and "full" or "off"
        -- Folded into `want` so the mode comparison below sees the change and
        -- re-applies; PLAYER_ENTERING_WORLD and the REGEN edges re-run this.
        if want == "full" and (EllesmereUI.IS_FOREVER or CooldownsSecret()) then
            want = "off"
        end
        if want == _broadcasterMode then return end
        _broadcasterMode = want
        -- Drop to the quiet state first (the two seeding registrations survive
        -- it), then add the tick set.
        ns.QuietBroadcasters()
        if want == "full" then
            if ActionBarButtonEventsFrame then
                for _, ev in ipairs(_abefEvents) do
                    ActionBarButtonEventsFrame:RegisterEvent(ev)
                end
            end
            if ActionBarActionEventsFrame then
                for _, ev in ipairs(_aaefEvents) do
                    ActionBarActionEventsFrame:RegisterUnitEvent(ev, "player")
                end
            end
        end
    end
    -- For callers that quiet the broadcasters DIRECTLY rather than through
    -- ApplyBroadcaster (the setup path's safety net, which can run after "full"
    -- has registered): the tick set is gone while _broadcasterMode still claims
    -- it, and the mode check above would early-out forever. Any direct
    -- quieting must come back through here.
    ns.ResyncBroadcaster = function()
        _broadcasterMode = nil   -- the caller has just quieted the frames; never early-out
        ApplyBroadcaster()
    end
    -- Recompute from ground truth on a broad event set rather than tracking
    -- enter/exit: vehicle enter events don't reliably fire/keep state. Ground
    -- truth is Blizzard's own answer, never the buttons' shown state:
    -- ExtraActionButton1 is created shown and only its bar is ever hidden, and
    -- the override buttons stay shown from load until their bar's first use,
    -- so reading IsShown() on them held "full" on for good.
    local function RefreshBroadcasterNeeds()
        _vehNeed = (C_ActionBar.HasVehicleActionBar() or C_ActionBar.HasOverrideActionBar()) and true or false
        _extraNeed = C_ActionBar.HasExtraActionBar() and true or false
        ApplyBroadcaster()
    end
    -- Exposed for the extra action button's Show-hook refresh in
    -- SetupBlizzardMovableFrame (a reliable trigger for delve entry).
    ns.RefreshBroadcaster = RefreshBroadcasterNeeds
    local barFrame = ns.TakeShell()
    barFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
    barFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    barFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
    barFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
    barFrame:RegisterEvent("UPDATE_EXTRA_ACTIONBAR")
    barFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- The combat edges only re-check secrecy, and WoW Forever never re-registers.
    if not EllesmereUI.IS_FOREVER then
        barFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        barFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    barFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            -- Undeferred, and a secrecy re-check only: the needs are unchanged
            -- at a combat edge, so this early-outs unless the secret state moved.
            ApplyBroadcaster()
            return
        end
        C_Timer.After(0, RefreshBroadcasterNeeds) -- deferred so Blizzard's bar state has settled
        -- On vehicle/override entry, force-paint OverrideActionBar cooldowns:
        -- the broadcaster only catches the NEXT change, so an already-running
        -- cooldown needs an initial paint.
        if (event == "UNIT_ENTERED_VEHICLE" or event == "UPDATE_VEHICLE_ACTIONBAR"
            or event == "UPDATE_OVERRIDE_ACTIONBAR") and not (unit and unit ~= "player") then
            C_Timer.After(0, function()
                for i = 1, 6 do
                    local btn = _G["OverrideActionBarButton" .. i]
                    if btn then
                        -- Cooldown-only refresh; avoids passing secret cooldown values through a tainted call.
                        ForceCooldownPaint(btn)
                        local hk = btn.HotKey
                        if hk then
                            local key1 = GetBindingKey("ACTIONBUTTON" .. i)
                            if key1 then
                                hk:SetText(FormatHotkeyText(key1))
                                hk:Show()
                            end
                        end
                    end
                end
            end)
        end
    end)
end

-------------------------------------------------------------------------------
--  Early Blizzard Bar Disposal (file load time): runs before combat state is
--  restored, so protected calls (Hide, SetParent) execute cleanly without
--  tainting Blizzard's ActionBarController call chain.
-------------------------------------------------------------------------------
do
    -- Make Blizzard's action bar pager unclickable. MainActionBar stays in
    -- Blizzard's parent chain and is alpha-hidden, so its children stay live
    -- -- ActionBarPageNumber (frameLevel 100, above our buttons) holds
    -- UpButton/DownButton that page the main bar on click: invisible but
    -- fully clickable. Reached by parentKey (no global name for the modern
    -- frame), every step guarded so a rename degrades to a no-op. Mouse state
    -- only, never Hide(): the parent has taint history around its protected
    -- shown state, and these are ordinary QuickKeybindButtonTemplate buttons,
    -- so disabling mouse is unprotected, combat-safe, and enough. Nothing of
    -- ours clicks them -- EUI's paging arrows drive their own secure buttons.
    local function KillPagerMouse(bar)
        local pager = bar and bar.ActionBarPageNumber
        if not pager then return end
        local function killOne(f)
            if not f or type(f.IsMouseEnabled) ~= "function" then return end
            if not f:IsMouseEnabled() then return end -- no-op after first pass
            f:EnableMouse(false)
            if f.EnableMouseClicks then f:EnableMouseClicks(false) end
            if f.EnableMouseMotion then f:EnableMouseMotion(false) end
        end
        killOne(pager)
        killOne(pager.UpButton)
        killOne(pager.DownButton)
        -- Cover anything else Blizzard parents in here later (ResizeLayoutFrame).
        -- Runs on every MainActionBar Show (form, stance and page flips), so
        -- it reads the live list instead of building a table.
        if type(pager.GetChildren) == "function" then
            for i = 1, pager:GetNumChildren() do
                killOne((select(i, pager:GetChildren())))
            end
        end
    end

    local framesToHide = {
        "MainActionBar",
        "MultiBar5",
        "MultiBar6",
        "MultiBar7",
        "MultiBarBottomLeft",
        "MultiBarBottomRight",
        "MultiBarLeft",
        "MultiBarRight",
    }

    local keepEvents = {
        MainActionBar = true,
    }

    for _, frameName in ipairs(framesToHide) do
        local frame = _G[frameName]
        if frame then
            if not keepEvents[frameName] then
                frame:UnregisterAllEvents()
            end

            -- MainActionBar stays in Blizzard's parent chain so pet battle
            -- restoration of MicroMenu works; all others safely reparent.
            if frameName == "MainActionBar" then
                EllesmereUI.HideFrame(frame)
                -- Keep MainActionBar invisible when Blizzard re-shows it on
                -- spec/zone/vehicle/bonus-bar transitions WITHOUT touching its
                -- protected shown state: Hide() from this insecure hook taints the
                -- frame, and ValidateActionBarTransition then hits ADDON_ACTION_BLOCKED
                -- on the next combat SetShownBase. SetAlpha is unprotected, inherits to
                -- children, and works in combat, so the bar stays hidden taint-free.
                hooksecurefunc(frame, "Show", function(self)
                    self:SetAlpha(0)
                    KillPagerMouse(self) -- re-assert: layout apply can re-enable pager mouse
                end)
                -- Disable mouse on MainActionBar: Blizzard can Show() it in
                -- combat (mount/dismount), and at alpha 0 / level 50 it would
                -- invisibly intercept clicks above our EABButtons.
                frame:EnableMouse(false)
                if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
                if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
                -- EnableMouse(false) on a parent does NOT disable children, so
                -- the pager's invisible arrows would still eat clicks.
                KillPagerMouse(frame)
                if frame.Selection then frame.Selection:Hide(); frame.Selection:SetAlpha(0) end -- Edit Mode selection/mover
                local caps = frame.EndCaps
                if caps then
                    caps:Hide() -- artwork (gryphons/endcaps/border)
                    -- WoW Forever: each end cap is an Edit Mode system of its own that
                    -- shows itself and its selection overlay whenever Edit Mode opens
                    -- (the overlay ignores the bar's alpha). Silence both overlays like
                    -- the bar's own; Edit Mode's Show never resets alpha or mouse.
                    local l, r = caps.LeftEndCap, caps.RightEndCap
                    if l and l.Selection then l.Selection:SetAlpha(0); l.Selection:EnableMouse(false) end
                    if r and r.Selection then r.Selection:SetAlpha(0); r.Selection:EnableMouse(false) end
                end
                if frame.BorderArt then frame.BorderArt:Hide() end
                frame:SetAlpha(0)
            else
                -- No Hide()/HideBase() here: reparenting to hiddenParent (kept
                -- permanently Hidden) makes the bar effectively invisible
                -- regardless of its own Shown state -- see ReassertHiddenOnShow's
                -- note above hiddenParent's creation for the taint this avoids.
                frame:SetParent(hiddenParent)
            end

            if frame.actionButtons and type(frame.actionButtons) == "table" then
                for _, button in pairs(frame.actionButtons) do
                    ns.QuietlyHideBlizzButton(button)
                end
            end
        end
    end

    -- Hide ActionBarParent (stock bars' container) -- cosmetic only, the
    -- individual bars are already reparented; OverrideActionBar hangs off
    -- UIParent so it's unaffected. Done at file load rather than via
    -- RegisterAttributeDriver to avoid tainting protected frame state.
    if ActionBarParent then
        ActionBarParent:Hide()
        ActionBarParent:SetParent(hiddenParent)
    end
end

-- Entry points the files after this one re-import by name.
I.hiddenParent = hiddenParent
