if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Secure.lua
--
--  The secure setup handler that performs protected frame operations, the
--  action button tables and their creation, and the event lists that are
--  re-registered on the buttons.
--  Loads after EUI_ActionBars_Controllers.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs, type = ipairs, pairs, type
local InCombatLockdown = InCombatLockdown
local EFD = ns.EFD

local EAB, EAB_VTABLE = ns.EAB, ns.EAB_VTABLE
local I = ns._internals
local SetActionBarCVar = I.SetActionBarCVar
local BAR_CONFIG, STOCK_BAR_DISPOSAL = I.BAR_CONFIG, I.STOCK_BAR_DISPOSAL
local hiddenParent = I.hiddenParent
local RegisterButtonWithController = I.RegisterButtonWithController

-------------------------------------------------------------------------------
--  Secure Setup Handler: performs protected frame ops (SetParent, SetPoint,
--  SetSize, Show/Hide) from within a restricted secure snippet so they run
--  even during combat lockdown (normal Lua cannot call these on protected
--  frames in combat, but a SecureHandlerAttributeTemplate snippet can).
--  Usage: SecureSetupHandler_PrepareRefs() once after bar frames are
--  created -> SecureSetupHandler_EncodeLayout() to write layout as
--  attributes -> SecureSetupHandler_Execute() to trigger the snippet.
-------------------------------------------------------------------------------
-- Forward declaration (populated in Button Creation below); needed here
-- because SecureSetupHandler_PrepareRefs references it.
local barButtons = {}
ns.barButtons = barButtons

local _secureHandler = CreateFrame("Frame", "EABSecureSetupHandler", UIParent, "SecureHandlerAttributeTemplate")

-- Reads encoded button data and applies SetParent + layout. Attribute format
-- per slot: "btn-N" = "barref|x|y|w|h|show" (show="1"/"0"). Frame refs: bar
-- frames as "bar-{key}", hidden parent as "hiddenParent", UIParent as
-- "uiParent", Blizzard bars as "blizzbar-{name}". Trigger: set "do-setup" to
-- any value to run the full setup.
_secureHandler:SetAttribute("_onattributechanged", [=[
    if name == "do-setup" then
        -- (setup code follows below)
    elseif name == "clear-binds" then
        self:ClearBindings()
        return
    else
        return
    end

    -- Step 1: Reparent Blizzard buttons to UIParent (extract from Blizzard bars)
    local uiParent = self:GetFrameRef("uiParent")
    local btnCount = self:GetAttribute("btn-count") or 0
    for slot = 1, btnCount do
        local btnRef = self:GetFrameRef("btn-" .. slot)
        if btnRef then
            btnRef:SetParent(uiParent)
        end
    end

    -- Step 2: Hide Blizzard bar frames
    local hiddenParent = self:GetFrameRef("hiddenParent")
    local blizzCount = self:GetAttribute("blizzbar-count") or 0
    for i = 1, blizzCount do
        local barRef = self:GetFrameRef("blizzbar-" .. i)
        if barRef then
            barRef:SetParent(hiddenParent)
        end
    end

    -- Step 3: Reparent buttons to our bar frames and apply layout
    for slot = 1, btnCount do
        local data = self:GetAttribute("layout-" .. slot)
        if data then
            local barKey, x, y, w, h, show, actionSlot = strsplit("|", data)
            local btnRef = self:GetFrameRef("btn-" .. slot)
            local barRef = self:GetFrameRef("bar-" .. barKey)
            if btnRef and barRef then
                -- Clear statehidden so the button is under our control
                btnRef:SetAttribute("statehidden", nil)
                btnRef:SetParent(barRef)
                btnRef:ClearAllPoints()
                btnRef:SetPoint("TOPLEFT", barRef, "TOPLEFT", tonumber(x) or 0, tonumber(y) or 0)
                btnRef:SetWidth(tonumber(w) or 45)
                btnRef:SetHeight(tonumber(h) or 45)
                if barKey == "PetBar" then
                    local petIndex = tonumber(actionSlot) or 1
                    btnRef:SetID(petIndex)
                    btnRef:SetAttribute("action", nil)
                elseif barKey == "StanceBar" then
                    -- Stance buttons keep their native handling
                else
                    -- All action bar buttons use explicit action attributes.
                    btnRef:SetID(0)
                    if actionSlot and actionSlot ~= "" and actionSlot ~= "0" then
                        btnRef:SetAttribute("action", tonumber(actionSlot))
                    end
                end
                if show == "1" then
                    btnRef:Show()
                else
                    btnRef:Hide()
                end
            end
        end
    end

    -- Step 4: Size and position our bar frames (hide if always-hidden or disabled)
    local barFrameCount = self:GetAttribute("barframe-count") or 0
    for i = 1, barFrameCount do
        local frameData = self:GetAttribute("barframe-" .. i)
        if frameData then
            local barKey, w, h, point, relPoint, x, y, hidden = strsplit("|", frameData)
            local barRef = self:GetFrameRef("bar-" .. barKey)
            local uip = self:GetFrameRef("uiParent")
            if barRef and uip then
                barRef:SetWidth(tonumber(w) or 1)
                barRef:SetHeight(tonumber(h) or 1)
                barRef:ClearAllPoints()
                barRef:SetPoint(point or "CENTER", uip, relPoint or "CENTER", tonumber(x) or 0, tonumber(y) or 0)
                if hidden == "1" then
                    barRef:Hide()
                else
                    barRef:Show()
                end
            end
        end
    end

    -- Step 5: MainBar paging is driven by _onstate-page -> ChildUpdate("eab-page").
    -- Each button's _childupdate-eab-page recalculates the action attribute.

    -- Step 6: All keybind dispatch uses SetOverrideBindingClick (set by UpdateKeybinds).
]=])

-- Register all buttons and bar frames as refs on the secure handler.
-- Must be called AFTER SetupBar creates buttons (barButtons is populated).
local _secureRefsReady = false
I.secureRefsReadySetters[#I.secureRefsReadySetters + 1] = function(v) _secureRefsReady = v end
-- One pass over every button that exists. Lazily built bars add buttons after
-- it has already run, so the reveal path in RefreshRuntimeVisibility clears
-- _secureRefsReady and calls this again; indices are reassigned consistently in
-- the same pass, and the only readers of btn._secureSlotIdx run after a full one.
local function SecureSetupHandler_PrepareRefs()
    if _secureRefsReady then return end
    _secureRefsReady = true

    _secureHandler:SetFrameRef("uiParent", UIParent)
    _secureHandler:SetFrameRef("hiddenParent", hiddenParent)

    -- Register all buttons (our EABButtons + Blizzard Stance/Pet)
    local btnIdx = 0
    for _, info in ipairs(BAR_CONFIG) do
        local btns = barButtons[info.key]
        if btns then
            for _, btn in ipairs(btns) do
                if btn then
                    btnIdx = btnIdx + 1
                    _secureHandler:SetFrameRef("btn-" .. btnIdx, btn)
                    btn._secureSlotIdx = btnIdx
                end
            end
        end
    end
    _secureHandler:SetAttribute("btn-count", btnIdx)

    -- Register stock bar frames to hide
    local blizzIdx = 0
    for _, entry in ipairs(STOCK_BAR_DISPOSAL) do
        local bar = _G[entry.name]
        if bar then
            blizzIdx = blizzIdx + 1
            _secureHandler:SetFrameRef("blizzbar-" .. blizzIdx, bar)
        end
    end
    if StatusTrackingBarManager and not (EAB.db and EAB.db.profile.useBlizzardDataBars) then
        blizzIdx = blizzIdx + 1
        _secureHandler:SetFrameRef("blizzbar-" .. blizzIdx, StatusTrackingBarManager)
    end
    _secureHandler:SetAttribute("blizzbar-count", blizzIdx)
end

-- Register our bar frames as refs. Called after CreateBarFrame.
local function SecureSetupHandler_RegisterBarFrame(key, frame)
    _secureHandler:SetFrameRef("bar-" .. key, frame)
end

-- Encode layout data for all buttons as attributes, then trigger the snippet.
-- layoutData: table of { slot = { barKey, x, y, w, h, show, actionSlot } }
-- barFrameData: table of { key, w, h, point, relPoint, x, y }
local function SecureSetupHandler_Execute(layoutData, barFrameData)
    for slot, d in pairs(layoutData) do
        local actionSlot = d.actionSlot or 0
        _secureHandler:SetAttribute("layout-" .. slot,
            d.barKey .. "|" .. d.x .. "|" .. d.y .. "|" .. d.w .. "|" .. d.h .. "|" .. (d.show and "1" or "0") .. "|" .. actionSlot)
    end
    -- Encode bar frame sizes/positions
    local barFrameCount = 0
    for _, d in ipairs(barFrameData) do
        barFrameCount = barFrameCount + 1
        _secureHandler:SetAttribute("barframe-" .. barFrameCount,
            d.key .. "|" .. d.w .. "|" .. d.h .. "|" .. d.point .. "|" .. d.relPoint .. "|" .. d.x .. "|" .. d.y .. "|" .. (d.hidden and "1" or "0"))
    end
    _secureHandler:SetAttribute("barframe-count", barFrameCount)
    -- Trigger the snippet
    _secureHandler:SetAttribute("do-setup", GetTime())
end

local function HideBlizzardBars()
    -- Fully hide all Blizzard action buttons (we create our own instead);
    -- Stance/Pet buttons are still reused, so only action buttons are hidden.
    for _, info in ipairs(BAR_CONFIG) do
        if info.blizzBtnPrefix and not info.isStance and not info.isPetBar then
            for i = 1, info.count do
                local btn = _G[info.blizzBtnPrefix .. i]
                if btn then
                    -- NOT reparented, and that is deliberate. The template sets
                    -- "useparent-actionpage" and then seeds self.action from
                    -- UpdateAction() in its OnLoad, so the button derives its
                    -- slot from whichever frame is its PARENT. Moving it to
                    -- hiddenParent breaks that inheritance and freezes
                    -- self.action at whatever it resolved to at load -- and
                    -- Blizzard's own ACTIONBAR_SLOT_CHANGED handler gates on
                    -- "arg1 == 0 or arg1 == tonumber(self.action)", so a button
                    -- with a stale cached slot can never match the slot that
                    -- actually changed and simply stops updating. That is what
                    -- left pressAndHoldAction unset on the natively-routed
                    -- twins and killed Hold and Release on empower KEYBINDS,
                    -- while mouse clicks (through our own buttons) were fine.
                    -- Leaving them under their real bar costs no visibility:
                    -- every stock bar is in STOCK_BAR_DISPOSAL, hidden with an
                    -- OnShow re-hide, so a child of one is never drawn.
                    ns.QuietlyHideBlizzButton(btn)
                end
            end
        end
    end
    -- MainMenuBar/StanceBar/PetActionBar need EAB.db ready, so handled here
    -- rather than at file load.
    local remainingBars = { "MainMenuBar", "StanceBar", "PetActionBar" }
    for _, name in ipairs(remainingBars) do
        local bar = _G[name]
        if bar then
            bar:UnregisterAllEvents()
            -- No Hide()/HideBase() call: SetParent(hiddenParent) below already
            -- makes the bar effectively invisible taint-free (see the note on
            -- ReassertHiddenOnShow above hiddenParent's creation).
            bar:SetParent(hiddenParent)
            -- Prevent Blizzard re-showing it (spell transforms like Ascendance
            -- can trigger ValidateActionBarTransition, creating invisible dead zones)
            ns.ReassertHiddenOnShow(bar)
            if bar.actionButtons and type(bar.actionButtons) == "table" then
                for _, child in pairs(bar.actionButtons) do
                    ns.QuietlyHideBlizzButton(child)
                end
            end
        end
    end
    -- ActionBarController retains all events so Blizzard's vehicle/override
    -- transition (ValidateActionBarTransition) works. MainMenuBarPageNumber is
    -- a legacy global absent on current clients; the live pager is
    -- MainActionBar's ActionBarPageNumber child, neutralised by KillPagerMouse.
    if MainMenuBarPageNumber then MainMenuBarPageNumber:Hide() end

    -- Replace ActionBar_PageUp/Down with versions that compute the target page
    -- and pass it to ChangeActionBarPage explicitly: stock versions derive it
    -- via GetActionBarPage(), and with MainMenuBar disabled the stock pipeline
    -- resets page to 1 after each change.
    --
    -- state-page is the RESOLVED page (7-14 in a form, vehicle, override or
    -- skyriding state), not the manual page, so cycling off it can walk out
    -- of the 1-6 range. Ask Blizzard for the page the cycle actually moves,
    -- which is what ChangeActionBarPage writes.
    local function CurrentManualPage()
        local maxPages = NUM_ACTIONBAR_PAGES or 6
        local curPage = EAB_VTABLE.GetActionBarPage() or 1
        return curPage, maxPages
    end
    -- Keep the non-secure legacy functions consistent with the secure wheel
    -- buttons. The skip mask is derived from configured bars, not live visibility
    -- (which can change in combat and cannot safely rewrite secure macros).
    local function ChangeManualPage(delta)
        local curPage, maxPages = CurrentManualPage()
        local bars = EAB.db and EAB.db.profile and EAB.db.profile.bars
        if not (bars and bars.MainBar and bars.MainBar.skipVisiblePagingBars) then
            ChangeActionBarPage((curPage - 1 + delta + maxPages) % maxPages + 1)
            return
        end
        local skip = ns.GetPagingSkipMask()
        local newPage = curPage
        for _ = 1, maxPages do
            newPage = (newPage - 1 + delta + maxPages) % maxPages + 1
            if not skip[newPage] then
                ChangeActionBarPage(newPage)
                return
            end
        end
    end
    -- Not under WoW Forever's Gamepad interface style: its controller bars page
    -- through secure "actionbar" buttons that call these globals, and a
    -- replacement of ours would run that paging insecure (blocked bar moves
    -- and errors in the gamepad buttons, in combat). A global once written
    -- stays tainted, so this is decided here, once, as the bars are taken.
    if not EllesmereUI.PadGamepadUI() then
        ActionBar_PageUp = function() ChangeManualPage(1) end
        ActionBar_PageDown = function() ChangeManualPage(-1) end
    end

    -- Hide status tracking bar manager (unless user wants Blizzard data bars).
    -- Its events come back only with a reload (ns.SetUseBlizzardDataBars).
    if not (EAB.db and EAB.db.profile.useBlizzardDataBars) then
        if StatusTrackingBarManager then
            StatusTrackingBarManager:UnregisterAllEvents()
            StatusTrackingBarManager:Hide()
            ns._eabBlizzDataBarsDropped = true
        end
    end
    -- ActionBarParent is hidden at file load; OverrideActionBar visibility is fully
    -- owned by Blizzard's ValidateActionBarTransition(). No RegisterAttributeDriver on
    -- Blizzard-owned frames -- risks tainting protected state OverrideActionBar buttons
    -- inherit. Force all Blizzard action bars "enabled" via CVars so buttons work.
    SetActionBarCVar("SHOW_MULTI_ACTIONBAR_1", "1", "EllesmereUIActionBars")
    SetActionBarCVar("SHOW_MULTI_ACTIONBAR_2", "1", "EllesmereUIActionBars")
    SetActionBarCVar("SHOW_MULTI_ACTIONBAR_3", "1", "EllesmereUIActionBars")
    SetActionBarCVar("SHOW_MULTI_ACTIONBAR_4", "1", "EllesmereUIActionBars")

end

-------------------------------------------------------------------------------
--  Button Creation: all action bar buttons (slots 1-180) are our own
--  EABButton frames. Stance/Pet bars still reuse Blizzard buttons.
-------------------------------------------------------------------------------
local allButtons = {}   -- [actionSlot] = button
-- barButtons: forward-declared above (before SecureSetupHandler_PrepareRefs)
local buttonToBar = {}  -- [btn] = { barKey, index } for taint-safe slot resolution
local barFrames  = {}   -- [barKey] = secure header frame
local dataBarFrames = {} -- [barKey] = data bar frame (XP/Rep) populated later in SetupDataBars
local blizzMovableHolders = {} -- [barKey] = holder frame for Blizzard movable frames (ExtraAction, Encounter)
local extraBarHolders = {} -- [barKey] = holder frame for extra bars (MicroBar, BagBar)
local BLIZZ_MOVABLE_OVERLAY = { -- Fixed overlay sizes for unlock mode movers (not the actual Blizzard frames)
    ExtraActionButton = { w = 100, h = 100 },
    EncounterBar      = { w = 150, h = 40 },
}
local barBaseSize = {}  -- [barKey] = { w, h } original button size before any shape/scale

-- Action slot ranges per bar (see trailing comments). MUST match Blizzard's
-- internal slot assignments per button prefix (warcraft.wiki.gg/wiki/ActionSlot).
-- Slots 133-144 are reserved/unused. Stance bar uses StanceButton1-10 (not action slots).
local BAR_SLOT_OFFSETS = {
    MainBar = 0,    -- slots 1-12 (paged)
    Bar2 = 60,      -- slots 61-72  (MultiBarBottomLeft)
    Bar3 = 48,      -- slots 49-60  (MultiBarBottomRight)
    Bar4 = 24,      -- slots 25-36  (MultiBarRight)
    Bar5 = 36,      -- slots 37-48  (MultiBarLeft)
    Bar6 = 144,     -- slots 145-156 (MultiBar5)
    Bar7 = 156,     -- slots 157-168 (MultiBar6)
    Bar8 = 168,     -- slots 169-180 (MultiBar7)
    Bar9 = 12,      -- slots 13-24   (action page 2 -- custom bar)
    Bar10 = 108,    -- slots 109-120 (action page 10 -- custom bar, no native frame)
}

-- Binding name prefixes per bar: MULTIACTIONBAR<N>BUTTON, where N is Blizzard's
-- internal bar numbering (not our sequential bar IDs).
local BINDING_MAP = {
    MainBar = "ACTIONBUTTON",
    Bar2 = "MULTIACTIONBAR1BUTTON",
    Bar3 = "MULTIACTIONBAR2BUTTON",
    Bar4 = "MULTIACTIONBAR3BUTTON",
    Bar5 = "MULTIACTIONBAR4BUTTON",
    Bar6 = "MULTIACTIONBAR5BUTTON",
    Bar7 = "MULTIACTIONBAR6BUTTON",
    Bar8 = "MULTIACTIONBAR7BUTTON",
    -- Bar9/Bar10 have no native binding commands; custom commands defined in
    -- Bindings.xml route via SetOverrideBindingClick (keypress clicks our
    -- button, which reads the paged "action" attr).
    Bar9 = "EUI_BAR9_BUTTON",
    Bar10 = "EUI_BAR10_BUTTON",
    StanceBar = "SHAPESHIFTBUTTON",
    PetBar = "BONUSACTIONBUTTON",
}

-- Readable labels for the custom Bar9/Bar10 binding commands in Bindings.xml.
-- Global writes only (no file-scope locals); keybind UI reads
-- BINDING_HEADER_<header> for the section title, BINDING_NAME_<command> per row.
_G.BINDING_HEADER_EUI_BAR9  = "EllesmereUI Action Bar 9"
_G.BINDING_HEADER_EUI_BAR10 = "EllesmereUI Action Bar 10"
for i = 1, 12 do
    _G["BINDING_NAME_EUI_BAR9_BUTTON"  .. i] = "Action Bar 9 Button "  .. i
    _G["BINDING_NAME_EUI_BAR10_BUTTON" .. i] = "Action Bar 10 Button " .. i
end

-- Flyout system lives in EUI_ActionBars_Flyout.lua (loaded after this file).
-- All usage is event-driven, so we resolve the reference lazily.
local EABFlyout
local function GetEABFlyout()
    if not EABFlyout then EABFlyout = ns.EABFlyout end
    return EABFlyout
end

-------------------------------------------------------------------------------
--  Re-register events on action buttons that HideBlizzardBars unregistered.
--  These are what Blizzard's button mixins need for real-time icon, cooldown,
--  usability, and state updates.
-------------------------------------------------------------------------------
local BUTTON_EVENT_LISTS = {
    action = {
        "ACTIONBAR_UPDATE_STATE",
        "ACTIONBAR_UPDATE_USABLE",
        -- ACTIONBAR_UPDATE_COOLDOWN and ACTIONBAR_SLOT_CHANGED are deliberately NOT
        -- registered per button: assisted-combat dirties its slot ~11x/sec at total
        -- idle (dispatching to ~140 mixins ran the full cooldown path ~1500x/sec
        -- forever), and mouseover-conditional macros re-resolve on every mouseover flip
        -- (profiled ~7s CPU per 10s of cursor sweeps). The central dispatcher owns ALL
        -- cooldown painting, lazily creates btn.chargeCooldown, and runs UpdateAction +
        -- stale count clearing for slot changes instead.
        "PLAYER_ENTERING_WORLD",
        "UPDATE_SHAPESHIFT_FORM",
        "SPELL_UPDATE_CHARGES",
        "UPDATE_INVENTORY_ALERTS",
        "PLAYER_EQUIPMENT_CHANGED",
        -- LOSS_OF_CONTROL_ADDED / _UPDATE are deliberately NOT registered per button
        -- either: they run the mixin's ActionButton_UpdateCooldown, which under our
        -- taint cannot hand the restricted loss-of-control times to SetCooldown, so
        -- the overlay never drew in PvP matches. The dispatcher paints it
        -- (ns._abLoCPass in EUI_ActionBars_Events.lua).
        "PLAYER_TARGET_CHANGED", -- native per-button usability via Blizzard's C-side dispatcher
    },
    stance = {
        "UPDATE_SHAPESHIFT_FORMS",
        "UPDATE_SHAPESHIFT_FORM",
        "ACTIONBAR_PAGE_CHANGED",
        "PLAYER_ENTERING_WORLD",
        "UPDATE_SHAPESHIFT_COOLDOWN",
    },
    pet = {
        "PET_BAR_UPDATE",
        "PET_BAR_UPDATE_COOLDOWN",
        "PET_BAR_UPDATE_USABLE",
        "PLAYER_CONTROL_LOST",
        "PLAYER_CONTROL_GAINED",
        "PLAYER_FARSIGHT_FOCUS_CHANGED",
        "PLAYER_ENTERING_WORLD",
        "PET_BAR_SHOWGRID",
        "PET_BAR_HIDEGRID",
    },
}

local function ReRegisterButtonEvents(btn, listKey)
    for _, event in ipairs(BUTTON_EVENT_LISTS[listKey]) do
        btn:RegisterEvent(event)
    end
    if listKey == "pet" then
        btn:RegisterUnitEvent("UNIT_PET", "player")
        btn:RegisterUnitEvent("UNIT_FLAGS", "pet")
    end
end

-- Bar dormancy strips this same list per button (see ns.ApplyBarDormancy;
-- the loop is inlined there).

-- Blizzard's own attack flash on our buttons. The mixin starts it from its
-- hover and show refreshes (UpdateFlash), but the events that stop it no
-- longer reach our buttons (the broadcasters are quiet), so a flash started
-- there kept running beside ours after the attack ended. Our flash
-- (ns.AB_SetAttackFlash) is the only one: a mixin start is switched off again
-- at once (flashing is the field its OnUpdate reads, which then unregisters
-- the button on its next tick), and either edge has ours read the state.
local function OnMixinStartFlash(btn)
    btn.flashing = 0
    ns.AB_SyncAttackState(btn, btn:GetAttribute("action"))
end
local function OnMixinStopFlash(btn)
    ns.AB_SyncAttackState(btn, btn:GetAttribute("action"), true)
end

-- Get or create an action button for a slot. Action bars (1-8) always create
-- our own buttons, eliminating the taint surface: Blizzard's protected
-- buttons are never reused, so cross-addon taint can't propagate to
-- SetShown/Show/Hide. Stance bar still reuses Blizzard StanceButtons (own
-- secure handling); Pet bar is set up in SetupBar. skipProtected: skip
-- SetParent/Show (combat reload; the secure handler does those instead).
local function GetOrCreateButton(slot, parent, info, index, skipProtected)
    if allButtons[slot] then
        if not skipProtected then
            allButtons[slot]:SetParent(parent)
        end
        return allButtons[slot]
    end

    local btn
    if info.isStance then
        btn = _G["StanceButton" .. index] -- reuse Blizzard buttons (own secure stance handling)
        if btn and not skipProtected then
            btn:SetAttributeNoHandler("statehidden", nil)
            ReRegisterButtonEvents(btn, "stance")
            btn:SetParent(parent)
            btn:Show()
        end
    else
        -- Action bars: create our own button. ActionBarButtonTemplate
        -- inherits SecureActionButtonTemplate, so click dispatch, drag-and-
        -- drop, and the visual mixin (icon, cooldown, border) all work.
        -- Frames persist across /reload; reuse if already in _G.
        local name = "EABButton" .. slot
        btn = _G[name]
        if not btn then
            btn = CreateFrame("CheckButton", name, parent, "ActionBarButtonTemplate, SecureActionButtonTemplate")
            -- Neuter UpdateButtonArt: it resets NormalTexture/PushedTexture
            -- atlases on every call, causing mass GPU redraws across 96
            -- buttons. We handle art ourselves (MakeButtonSquare/ApplyPushedTextures).
            btn.UpdateButtonArt = function() end
        end
        -- Template OnLoad self-registers ACTIONBAR_SLOT_CHANGED and
        -- ACTIONBAR_UPDATE_COOLDOWN; the central dispatcher owns both (see
        -- BUTTON_EVENT_LISTS note) so the mixin's own handler is killed here
        -- -- it would run Update() under our execution taint (UpdateButtonArt
        -- neuter is a tainted field in that chain), erroring on secret
        -- cooldown args and blocking SetAttribute in combat.
        btn:UnregisterEvent("ACTIONBAR_SLOT_CHANGED")
        btn:UnregisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        -- Template OnLoad also registered this button with Blizzard's
        -- ActionBarButtonEventsFrame broadcaster; that tinsert ran under OUR
        -- execution, so the stored entry is a tainted value -- every dispatch
        -- (Blizzard's own untainted SLOT_CHANGED/PEW seeding, or the tick set
        -- while the vehicle/extra button shows) would read the entry, run the
        -- button's whole mixin OnEvent tainted and carry that taint through the
        -- rest of the loop (blocked SetAttribute, secret SetCooldown rejections
        -- in combat). UnregisterEvent can't stop this
        -- (broadcaster calls OnEvent directly) and wrapping btn.OnEvent would taint
        -- every per-button dispatch (template wires OnEvent by name, resolved at fire
        -- time). Instead nil our entry out of the list in place (never tremove --
        -- shifting would rewrite later Blizzard-owned entries as tainted). The button
        -- loses nothing: every event it needs is self-registered (BUTTON_EVENT_LISTS)
        -- or centrally dispatched.
        if ActionBarButtonEventsFrame and type(ActionBarButtonEventsFrame.frames) == "table" then
            -- The entry to remove is the one this button's template OnLoad
            -- just tinsert'd -- the array tail. Checking it directly keeps
            -- the 120-button build O(n) instead of O(n^2) over Blizzard's
            -- ~180-entry list (a real slice of the combat-reload watchdog
            -- budget); the full scan stays as the fallback for any exotic
            -- insertion order.
            local fr = ActionBarButtonEventsFrame.frames
            local tail = #fr
            if fr[tail] == btn then
                fr[tail] = nil
            else
                for k, f in pairs(fr) do
                    if f == btn then fr[k] = nil end
                end
            end
        end
        -- Desaturate-on-CD / on-CD alpha: re-evaluate the icon the moment the main
        -- cooldown display completes, since writes are static between events (a charge
        -- spell's recharge-end at 0 charges IS the main cooldown, exactly this edge) --
        -- without it the icon only recovers at the next cooldown event. Re-evaluates
        -- from live data so a GCD completing on a banked-charge spell is a no-op.
        -- HookScript, never SetScript (template's charge/LoC handling may own the
        -- slot); guarded because bar rebuilds reuse these frames and HookScript stacks.
        if btn.cooldown and not EFD(btn).cdDoneHooked then
            EFD(btn).cdDoneHooked = true
            btn.cooldown:HookScript("OnCooldownDone", function(cd)
                local b = cd:GetParent()
                if EAB._RefreshCooldownVisuals then
                    EAB._RefreshCooldownVisuals(b)
                end
                -- Recharge-numbers un-hide edge: a real main cooldown's END fires
                -- no bar event, so an occluded charge countdown had no owning edge
                -- to reappear on (it stranded hidden until the next unrelated
                -- pass). The display-complete edge is the exact moment occlusion
                -- lapses; nil-check cost for every non-charge button.
                if b and b.chargeCooldown and ns.UpdateChargeNumbersVisibility then
                    local action = b.GetAttribute and b:GetAttribute("action")
                    if action and HasAction(action) then
                        ns.UpdateChargeNumbersVisibility(b, b.chargeCooldown,
                            C_ActionBar.GetActionCooldown(action),
                            C_ActionBar.GetActionCharges(action))
                    end
                end
            end)
        end
        -- Hovering runs Blizzard's secure Update() (ForceButtonRefresh),
        -- resetting desaturation with no edge for the visuals memo to catch
        -- -- an on-CD icon flashed back to color until the next real cooldown
        -- event. Re-assert right after Blizzard's handler; RefreshCooldownVisuals
        -- early-outs when both features are off (two profile reads at hover
        -- rate). Guarded like the sibling above.
        if not EFD(btn).cdHoverHooked then
            EFD(btn).cdHoverHooked = true
            btn:HookScript("OnEnter", function(self)
                if EAB._RefreshCooldownVisuals then
                    EAB._RefreshCooldownVisuals(self)
                end
                -- Same Blizzard hover repaint also resets HotKey's text color
                -- to white (see ReapplyHotkeyColors above); OnEnter never fed
                -- the event-driven reassert, so a custom color reverted on
                -- every hover until the next unrelated ACTIONBAR_* event.
                -- Queue instead of reapplying inline: coalesces with any
                -- burst already pending and costs nothing when the bar is on
                -- the default white (see ReapplyHotkeyColors' early-out).
                EAB:QueueHotkeyColorReassert()
            end)
        end
        -- The mixin's own flash hands over to ours (OnMixinStartFlash above).
        -- Guarded as above.
        if not EFD(btn).flashHooked then
            EFD(btn).flashHooked = true
            hooksecurefunc(btn, "StartFlash", OnMixinStartFlash)
            hooksecurefunc(btn, "StopFlash", OnMixinStopFlash)
        end
        -- Physical-press GCD paint: keybinds arrive as clicks too
        -- (SetOverrideBindingClick), so PostClick fires at the actual press
        -- before any server round-trip; pushes the predicted cooldown and
        -- arms the press wave (ns._EABPressPush). Guarded as above.
        if not EFD(btn).cdClickHooked then
            EFD(btn).cdClickHooked = true
            -- Captured once: the command is a property of the BUTTON, not the
            -- slot it shows, so it survives page swaps (Bar 9 shares action
            -- page 2 with a paged MainBar, making slot-derived ambiguous).
            local pressBindCmd = BINDING_MAP[info.key]
            pressBindCmd = pressBindCmd and (pressBindCmd .. index) or nil
            btn:HookScript("PostClick", function(self, _, down)
                if ns._EABPressPush then ns._EABPressPush(self) end
                -- Publish for the CDM press mirror: click-routed keybinds never
                -- fire the native binding commands. Global rather than ns (the
                -- subscriber is a separate addon, like _EAB_UpdateKeybinds).
                local onPress = _G._EUI_OnActionButtonPress
                if onPress then onPress(self, down, pressBindCmd) end
            end)
        end
        -- When the pickup modifier is held (shift-click to move abilities),
        -- clear useOnKeyDown for the duration of that mouse click: the down
        -- edge never casts (a drag consumes the action instead), and a click
        -- without a drag casts on RELEASE -- matching Blizzard's buttons,
        -- which force useOnKeyDown off for hardware mouse clicks
        -- (SecureTemplates.lua) and so act on the up edge.
        -- MOUSE-ONLY via IsUnderMouse (rect test): keybinds ALSO arrive as
        -- OnClick (SetOverrideBindingClick dispatch for all bars), and a
        -- modified KEYBIND press must cast on its configured edge.
        -- The pre-body must return its message on the UP click and ONLY
        -- there: a wrap's post-body only executes when the pre returns a
        -- message (SecureHandlers.lua), so no message = the flip sticks
        -- (#1165's delayed presses / late GCD swipes), and a DOWN-edge
        -- message = the restore lands before the release and a shift-click
        -- casts on neither edge. Both shapes shipped and failed; keep the
        -- message on the up edge.
        -- eabPickupFlipped marks OUR flip: useOnKeyDown=false is also a
        -- legitimate user setting (press-and-hold casting), and the flag
        -- keeps the restore from ever forcing those users back to true.
        -- A drag consumes the up edge and strands the flip; the next down
        -- click (mouse or keybind) clears it BEFORE the native handler
        -- runs, so that press still acts on its configured edge.
        if not btn:GetAttribute("eabPickupWrap") and not InCombatLockdown() then
            btn:SetAttribute("eabPickupWrap", true)
            SecureHandlerWrapScript(btn, "OnClick", btn, [[
                local flipped = self:GetAttribute("eabPickupFlipped")
                if down then
                    if IsModifiedClick("PICKUPACTION") and self:IsUnderMouse() then
                        if self:GetAttribute("useOnKeyDown") ~= false then
                            self:SetAttribute("eabPickupFlipped", true)
                            self:SetAttribute("useOnKeyDown", false)
                        end
                    elseif flipped then
                        self:SetAttribute("eabPickupFlipped", false)
                        self:SetAttribute("useOnKeyDown", true)
                    end
                elseif flipped then
                    return nil, "restore"
                end
            ]], [[
                self:SetAttribute("eabPickupFlipped", false)
                self:SetAttribute("useOnKeyDown", true)
            ]])
        end
        if not skipProtected then
            btn:SetParent(parent)
            btn:SetID(0)
            btn:SetAttribute("action", slot)
        end
    end

    if ns.MasqueOwnsBar(info.key) then
        -- Masque buttons skip MakeButtonSquare(), so mark them separately to keep the yellow proc glow working.
        EFD(btn).masqueOwned = true
        EAB_VTABLE.SetupCastAnimSuppression(btn)
        EAB_VTABLE.SetupAssistRotationSuppression(btn)
        if EAB_VTABLE.HookCooldownVisualsForButton then
            EAB_VTABLE.HookCooldownVisualsForButton(btn)
        end
    end
    RegisterButtonWithController(btn)
    allButtons[slot] = btn
    return btn
end

local NUM_AB_PAGES = NUM_ACTIONBAR_PAGES or 6

-- Keybind routing: every standard-bar slot -- INCLUDING empowered spells --
-- binds to native commands, where the engine pairs press and release against
-- the physical key (hold-and-release, hold-to-cast repeat and queued empowers
-- are all engine-owned there). Only custom-paged bars and the custom bars
-- (no native command exists) route keys through the button via
-- SetOverrideBindingClick. pressAndHoldAction/typerelease stay maintained on
-- the buttons for MOUSE clicks on empowered slots.

-- Safe API wrappers (these globals may move to C_ActionBar); stored on
-- EAB_VTABLE, not in file locals.
do
    local V = EAB_VTABLE
    V.GetOverrideBarIndex = GetOverrideBarIndex or (C_ActionBar and C_ActionBar.GetOverrideBarIndex) or function() return 14 end
    V.GetVehicleBarIndex = GetVehicleBarIndex or (C_ActionBar and C_ActionBar.GetVehicleBarIndex) or function() return 12 end
    V.GetTempShapeshiftBarIndex = GetTempShapeshiftBarIndex or (C_ActionBar and C_ActionBar.GetTempShapeshiftBarIndex) or function() return 13 end
    V.GetActionBarPage = GetActionBarPage or (C_ActionBar and C_ActionBar.GetActionBarPage) or function() return 1 end
    V.HasVehicleActionBar = HasVehicleActionBar or (C_ActionBar and C_ActionBar.HasVehicleActionBar) or function() return false end
    V.HasOverrideActionBar = HasOverrideActionBar or (C_ActionBar and C_ActionBar.HasOverrideActionBar) or function() return false end
    V.HasTempShapeshiftActionBar = HasTempShapeshiftActionBar or (C_ActionBar and C_ActionBar.HasTempShapeshiftActionBar) or function() return false end
end

-- Entry points the files after this one re-import by name.
I.BINDING_MAP, I.BUTTON_EVENT_LISTS = BINDING_MAP, BUTTON_EVENT_LISTS
I.ReRegisterButtonEvents, I.barFrames, I.extraBarHolders = ReRegisterButtonEvents, barFrames, extraBarHolders
I.dataBarFrames, I.blizzMovableHolders = dataBarFrames, blizzMovableHolders
I.BLIZZ_MOVABLE_OVERLAY, I.buttonToBar, I.barBaseSize = BLIZZ_MOVABLE_OVERLAY, buttonToBar, barBaseSize
I.BAR_SLOT_OFFSETS, I.allButtons, I.NUM_AB_PAGES = BAR_SLOT_OFFSETS, allButtons, NUM_AB_PAGES
I.GetEABFlyout, I.GetOrCreateButton = GetEABFlyout, GetOrCreateButton
I.SecureSetupHandler_RegisterBarFrame = SecureSetupHandler_RegisterBarFrame
I.SecureSetupHandler_PrepareRefs, I.HideBlizzardBars = SecureSetupHandler_PrepareRefs, HideBlizzardBars
I.SecureSetupHandler_Execute = SecureSetupHandler_Execute
