if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Bars.lua
--
--  The secure bar frames, SetupBar and the first-install capture of
--  Blizzard's layout.
--  Loads after EUI_ActionBars_Paging.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local _G = _G
local ipairs, pairs, type, pcall = ipairs, pairs, type, pcall
local min, max = math.min, math.max
local InCombatLockdown = InCombatLockdown
local RegisterStateDriver = RegisterStateDriver
local EFD = ns.EFD

local EAB, EAB_VTABLE, barButtons = ns.EAB, ns.EAB_VTABLE, ns.barButtons
local I = ns._internals
local BAR_CONFIG = I.BAR_CONFIG
local RegisterBarWithOverrideController = I.RegisterBarWithOverrideController
local BAR_SLOT_OFFSETS, barBaseSize, barFrames = I.BAR_SLOT_OFFSETS, I.barBaseSize, I.barFrames
local BINDING_MAP, buttonToBar, GetEABFlyout = I.BINDING_MAP, I.buttonToBar, I.GetEABFlyout
local GetOrCreateButton, ReRegisterButtonEvents = I.GetOrCreateButton, I.ReRegisterButtonEvents
local SecureSetupHandler_RegisterBarFrame = I.SecureSetupHandler_RegisterBarFrame
local GetClassPagingConditions = I.GetClassPagingConditions

-------------------------------------------------------------------------------
--  Secure Bar Frame Creation
--  Each bar gets a SecureHandlerStateTemplate frame. Our buttons are created
--  with SetID(0) + an explicit "action" attribute, so CalculateAction resolves
--  the slot from that attribute (path 2), NOT from actionpage. Paging works by
--  the bar's _onstate-page handler doing ChildUpdate("eab-page", page), and each
--  button's _childupdate-eab-page snippet rewriting its "action" attribute. The
--  frame "actionpage" attribute is kept only for insecure range-check reads.
-------------------------------------------------------------------------------
local function CreateBarFrame(info)
    local key = info.key
    local frame = CreateFrame("Frame", "EABBar_" .. key, UIParent, "SecureHandlerStateTemplate")
    frame:SetSize(1, 1)
    frame:SetPoint("CENTER")
    -- Render above any Blizzard bar art that might bleed through
    frame:SetFrameLevel(math.max(frame:GetFrameLevel(), 10))
    -- Bar frames never intercept clicks (only buttons do); motion is enabled
    -- later by the hover system for OnEnter/OnLeave.
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
    end
    frame._barKey = key
    frame._barInfo = info

    if key == "MainBar" then
        -- MainBar paging: the state driver evaluates conditions (forms,
        -- vehicle, override, possess, bonus bars, modifiers); _onstate-page
        -- runs ChildUpdate("eab-page", page), and each button's
        -- _childupdate-eab-page rewrites action = baseIndex + (page-1)*12.
        local barSettings = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars[key]
        local customPaging = barSettings and barSettings.paging
        local pagingConditions
        if EAB_VTABLE.HasCustomPaging(barSettings) then
            pagingConditions = EAB_VTABLE.BuildPagingConditions("MainBar", customPaging, 1)
        else
            -- No custom paging: use hardcoded class defaults (zero impact)
            pagingConditions = GetClassPagingConditions()
        end

        -- Mark MainBar as the override bar target so the override controller
        -- propagates vehicle/override/petbattle state changes.
        frame:SetAttribute("state-overridebar", true)

        -- Propagate page state to actionpage in the restricted environment so
        -- it stays untainted. The same write goes to MainActionBar: the native
        -- ACTIONBUTTONn keys fire Blizzard's ActionButton1-12, which resolve
        -- their slot from that frame's actionpage at click time, and Blizzard's
        -- own writer (ActionBarController_UpdateAll) cannot be relied on once
        -- the stock bars are disposed, so without the mirror a key can fire a
        -- page the icon does not show. The secure ChildUpdate is
        -- the missing half of the paging contract: each button gets an
        -- attribute change so OnAttributeChanged -> UpdateAction re-evaluates
        -- the derived slot even in combat. NEVER CallMethod here: vehicle/
        -- override transitions evaluate all state drivers in one secure pass,
        -- and CallMethod exits to insecure Lua mid-pass, tainting the context
        -- -- Blizzard's ActionBarController drivers in the same pass inherit
        -- it and OverrideActionBar:Show() hits ADDON_ACTION_BLOCKED. Page
        -- sync instead rides ACTIONBAR_PAGE_CHANGED (paging frame OnEvent).
        frame:SetFrameRef("blizzmainbar", MainActionBar)
        frame:SetAttributeNoHandler("_onstate-page", [[
            local page = tonumber(newstate) or 1
            self:SetAttribute("actionpage", page)
            self:ChildUpdate("eab-page", page)
            self:GetFrameRef("blizzmainbar"):SetAttribute("actionpage", page)
        ]])

        RegisterStateDriver(frame, "page", pagingConditions)
    end

    -- Bars 2-8 (nativeActionPage) and 9-10 (customPage): buttons have static action
    -- attrs set in SetupBar pointing at the bar's default page. Custom paging installs
    -- a state driver + ChildUpdate to recalculate the action attr on page change --
    -- identical machinery either way, differing only in the default page source.
    local defaultPage = info.nativeActionPage or info.customPage
    if defaultPage then
        frame:Execute(("self:SetAttribute('actionpage', %d)"):format(defaultPage))

        -- Configurable paging: install a state driver on top of the default
        -- page; when no conditions match, fall back to the bar's default.
        local barSettings = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars[key]
        local customPaging = barSettings and barSettings.paging
        if EAB_VTABLE.HasCustomPaging(barSettings) then
            frame:SetAttributeNoHandler("_onstate-page", [[
                local page = tonumber(newstate) or 1
                self:SetAttribute("actionpage", page)
                self:ChildUpdate("eab-page", page)
            ]])
            frame._eabPagingInstalled = true
            local conditions = EAB_VTABLE.BuildPagingConditions(key, customPaging, defaultPage)
            if conditions then
                RegisterStateDriver(frame, "page", conditions)
            end
        end
    end

    barFrames[key] = frame

    -- Empower re-check: setting "state-eabempower" dispatches ChildUpdate to
    -- re-evaluate pressAndHoldAction on all children. MUST be an _onstate-
    -- handler on a state- attribute: these bars are SecureHandlerStateTemplate,
    -- whose dispatcher only matches "^state%-(.+)" -> "_onstate-<id>". No
    -- _onattributechanged path exists here (that's SecureHandlerAttributeTemplate,
    -- i.e. OverrideController); a plain-attribute trigger fires NOTHING.
    frame:SetAttributeNoHandler("_onstate-eabempower", [[
        self:ChildUpdate("eab-empower", "")
    ]])

    -- Secure visibility: show/hide even in combat by setting the state
    -- attribute directly. RegisterStateDriver installs the snippet at
    -- creation (out of combat); later SetAttribute("state-eabvis", "hide")
    -- triggers it from the secure environment.
    frame:SetAttribute("_onstate-eabvis", [[
        if newstate == "hide" then
            self:Hide()
        else
            self:Show()
        end
    ]])
    -- If always-hidden or disabled, start hidden so the secure snippet hides
    -- it immediately, before combat can return after a brief reload regen.
    local s = EAB.db and EAB.db.profile.bars[key]
    local startHidden = s and (s.alwaysHidden or s.enabled == false)
    RegisterStateDriver(frame, "eabvis", startHidden and "hide" or "show")

    -- Register with the override controller so vehicle/override/petbattle
    -- state changes propagate to this bar frame.
    RegisterBarWithOverrideController(frame)

    -- Register with secure handler so it can reparent buttons to this frame
    SecureSetupHandler_RegisterBarFrame(key, frame)
    -- Custom modifier paging rewrites button action attrs from a SECURE state
    -- driver, no dispatcher event exists. The driver's "state-page" write
    -- fires this frame's insecure OnAttributeChanged -- the one clean owning
    -- edge to retire the filled lists and slot->button map so the next
    -- cooldown pass rebuilds against the new mapping.
    frame:HookScript("OnAttributeChanged", function(_, name)
        if name == "state-page" then
            ns._cdFilledDirty = true
            ns._slotBtnMapDirty = true
            ns._cdDirtyUntil = GetTime() + 2
        end
    end)

    -- Bar dormancy edges. OnShow/OnHide fire on EFFECTIVE visibility, secure
    -- driver flips included, and the dormancy handler is all unprotected API,
    -- so both edges are combat-legal. Buttons don't exist yet at creation
    -- time (handler no-ops until they do); FinishSetup's initial sync covers
    -- bars that START hidden (their OnHide never fires).
    frame:HookScript("OnShow", function(f)
        if ns.ApplyBarDormancy then ns.ApplyBarDormancy(f._barKey, false) end
    end)
    frame:HookScript("OnHide", function(f)
        if ns.ApplyBarDormancy then ns.ApplyBarDormancy(f._barKey, true) end
    end)
    return frame
end

-- Rebuild the paging state driver for a bar after settings change. Called from the
-- options panel when the user modifies paging config. Must be called out of combat.
function ns.RebuildBarPaging(barKey)
    if InCombatLockdown() then return end
    local frame = barFrames[barKey]
    if not frame then return end
    local info = frame._barInfo
    if not info then return end
    local barSettings = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars[barKey]
    local customPaging = barSettings and barSettings.paging

    if barKey == "MainBar" then
        local pagingConditions
        if EAB_VTABLE.HasCustomPaging(barSettings) then
            pagingConditions = EAB_VTABLE.BuildPagingConditions("MainBar", customPaging, 1)
        else
            pagingConditions = GetClassPagingConditions()
        end
        -- Force re-evaluation by unregistering first
        UnregisterStateDriver(frame, "page")
        RegisterStateDriver(frame, "page", pagingConditions)
    elseif info.nativeActionPage or info.customPage then
        local defaultPage = info.nativeActionPage or info.customPage
        if EAB_VTABLE.HasCustomPaging(barSettings) then
            -- Install handler if not already present
            if not frame._eabPagingInstalled then
                frame:SetAttributeNoHandler("_onstate-page", [[
                    local page = tonumber(newstate) or 1
                    self:SetAttribute("actionpage", page)
                    self:ChildUpdate("eab-page", page)
                ]])
                frame._eabPagingInstalled = true
                -- Must set the secure "action" attr (buttons are ID=0, so
                -- CalculateAction never consults "actionpage"). Same builder
                -- as SetupBar so paging added live behaves identically -- no /reload needed.
                local btns = barButtons[barKey]
                if btns then
                    for idx, btn in ipairs(btns) do
                        if not btn:GetAttribute("_childupdate-eab-page") then
                            btn:SetAttributeNoHandler("_childupdate-eab-page", ns._eabBuildPageChildSnippet(idx))
                        end
                    end
                end
            end
            local conditions = EAB_VTABLE.BuildPagingConditions(barKey, customPaging, defaultPage)
            if conditions then
                UnregisterStateDriver(frame, "page")
                RegisterStateDriver(frame, "page", conditions)
            end
        else
            -- No paging configured: remove state driver, restore fixed page
            UnregisterStateDriver(frame, "page")
            frame:Execute(("self:SetAttribute('actionpage', %d)"):format(defaultPage))
        end
    end

    -- Keybind routing derives from paging config (UpdateKeybinds pass 1):
    -- custom paging and auto-paging opt-outs both force click-routed keys.
    -- Rebuild now since toggling a paging setting fires no binding event
    -- (waiting on UPDATE_BINDINGS could wait forever); the signature diff
    -- makes this a no-op when routing didn't change, and UpdateKeybinds
    -- re-arms itself out of combat, so calling it unconditionally is safe.
    if _G._EAB_UpdateKeybinds then _G._EAB_UpdateKeybinds() end
end


-------------------------------------------------------------------------------
--  Bar Setup creates frames and buttons for each bar
-------------------------------------------------------------------------------
-- Build a bar's buttons into an EXISTING bar frame and record its base size.
-- Split out of SetupBar so a bar whose buttons were skipped at load can have
-- them built later, at the reveal edge: CreateBarFrame always creates a frame,
-- so re-running SetupBar there would leave a second one behind.
-- On ns rather than a file local: the lazy bar build in
-- EUI_ActionBars_VisibilityDrivers.lua calls it too.
ns.BuildBarButtons = function(info, frame, skipProtected)
    -- Shrink the clickable area to match a custom visual shape so a square
    -- hit rect can't steal clicks from diamond/circle/etc neighbours. Insets
    -- are a fraction of button size; "none" resets to full square.
    -- Out-of-combat only (SetHitRectInsets on a protected button is unsafe
    -- in combat), behind the same not-skipProtected guard as SetParent.
    local function ApplyShapeHitRects(btn, shape)
        if not btn then return end
        local w, h = btn:GetSize()
        if not w or w == 0 then w = 45 end
        if not h or h == 0 then h = 45 end
        local insetX, insetY = 0, 0
        if shape == "diamond" or shape == "circle" then
            insetX = math.floor(w * 0.146)
            insetY = math.floor(h * 0.146)
        elseif shape == "hexagon" then
            insetX = math.floor(w * 0.12)
            insetY = math.floor(h * 0.12)
        elseif shape == "shield" then
            insetX = math.floor(w * 0.10)
            insetY = math.floor(h * 0.15)
        end
        btn:SetHitRectInsets(insetX, insetX, insetY, insetY)
    end

    local key = info.key
    local buttons = {}
    -- The layout shape: stock styles draw no custom shape, so their hit rects stay full.
    local buttonShape = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars[key]
        and ns.AB_LayoutShape(EAB.db.profile.bars[key], key) or "none"

    if info.isStance then
        -- Stance bar: reuse StanceButton1-N
        for i = 1, info.count do
            local btn = _G["StanceButton" .. i]
            if btn then
                -- Stance buttons skip GetOrCreateButton, so set the Masque flag here.
                EFD(btn).masqueOwned = ns.MasqueOwnsBar(key) or nil
                if not skipProtected then
                    ApplyShapeHitRects(btn, buttonShape)
                    btn:SetAttributeNoHandler("statehidden", nil)
                    ReRegisterButtonEvents(btn, "stance")
                    btn:SetParent(frame)
                end
                buttons[i] = btn
            end
        end
    elseif info.isPetBar then
        -- Pet bar: reuse PetActionButton1-N
        for i = 1, info.count do
            local btn = _G["PetActionButton" .. i]
            if btn then
                -- Pet buttons skip GetOrCreateButton, so set the Masque flag before laying them out and styling them.
                EFD(btn).masqueOwned = ns.MasqueOwnsBar(key) or nil
                if not skipProtected then
                    ApplyShapeHitRects(btn, buttonShape)
                    btn:SetAttributeNoHandler("statehidden", nil)
                    ReRegisterButtonEvents(btn, "pet")
                    btn:SetParent(frame)
                end
                buttons[i] = btn
                -- Hook drag handlers so spellbook drops work even though
                -- the original PetActionBar is hidden and unregistered.
                btn:HookScript("OnReceiveDrag", function(self)
                    if InCombatLockdown() then return end
                    -- Blizzard's mixin handler runs first; fall back to
                    -- PickupPetAction if it didn't fire. The resulting
                    -- PET_BAR_UPDATE triggers our full refresh automatically.
                    local cType = GetCursorInfo()
                    if cType == "petaction" then
                        PickupPetAction(self:GetID())
                    end
                end)
            end
        end
    else
        -- Action bars (never stance/pet in this branch): our own EABButtons.
        local slotOffset = BAR_SLOT_OFFSETS[key] or 0
        for i = 1, info.count do
            local slot = slotOffset + i
            local btn = GetOrCreateButton(slot, frame, info, i, skipProtected)
            if btn then
                local bindPrefix = BINDING_MAP[key]
                if not skipProtected then
                    ApplyShapeHitRects(btn, buttonShape)
                    -- Explicit action attr: CalculateAction sees it non-zero
                    -- and returns it directly (path 2).
                    btn:SetAttribute("action", slot)
                    if bindPrefix then
                        btn:SetAttributeNoHandler("binding", bindPrefix .. i)
                    end
                    -- Force visual refresh; events are centrally dispatched
                    -- (per-button registration on 96 buttons caused mass
                    -- OnEvent->UpdateAction calls per tick -- screen blink).
                    -- Taint-safe refresh; avoids passing secret cooldown values through a tainted call.
                    EAB_VTABLE.ForceButtonRefresh(btn, slot)
                    -- Reconcile attack visuals and the equipped border on rebuild.
                    ns.AB_SyncAttackState(btn, slot)
                    ns.AB_SyncEquippedBorder(btn, slot)
                end
                if bindPrefix then
                    btn.commandName = bindPrefix .. i
                end
                -- Always register both so empower spells (hold-and-release)
                -- receive the key-down event even when CVar is key-up mode.
                -- useOnKeyDown controls which event fires normal spells.
                btn:RegisterForClicks("AnyDown", "AnyUp")
                btn:SetAttribute("useOnKeyDown", GetCVarBool("ActionButtonUseKeyDown"))
                if btn.EnableMouseWheel then
                    btn:EnableMouseWheel(true)
                end
                if not skipProtected then
                    btn:SetAttribute("showgrid", 1)
                end
                GetEABFlyout():RegisterButton(btn)
                -- Page child-update: rewrites the secure "action" attr on a page
                -- change, then re-checks hold-release. Shared builder so SetupBar
                -- and RebuildBarPaging install byte-identical handlers.
                if (key == "MainBar" or frame._eabPagingInstalled)
                   and not btn:GetAttribute("_childupdate-eab-page") then
                    btn:SetAttributeNoHandler("_childupdate-eab-page", ns._eabBuildPageChildSnippet(i))
                end
                -- Empower re-check on slot change (spec swap, drag, etc.)
                -- The bar header's _onstate-eabempower dispatches ChildUpdate
                -- when addon code sets "state-eabempower".
                if not btn:GetAttribute("_childupdate-eab-empower") then
                    btn:SetAttributeNoHandler("_childupdate-eab-empower", ns._eabEmpowerSnippet)
                end
                buttons[i] = btn
                buttonToBar[btn] = { barKey = key, index = i }
            end
        end
    end

    barButtons[key] = buttons
    ns._eabBarNoButtons[key] = nil

    -- Store original button size before any shape/scale modifications.
    -- StanceButtons and PetActionButtons are 30x30; action buttons are 45x45.
    -- Round to nearest integer to eliminate floating-point noise from Blizzard's
    -- scaling the intended sizes are always whole numbers.
    local btn1 = buttons[1]
    barBaseSize[key] = {
        w = math.floor((btn1 and btn1:GetWidth() or 45) + 0.5),
        h = math.floor((btn1 and btn1:GetHeight() or 45) + 0.5),
    }

    return buttons
end

-- Keeps every bar frame on screen, the way Blizzard's own bars are: bar
-- positions are offsets from the screen centre, so a higher UI Scale, an
-- import made at another scale or a narrower screen would otherwise push a bar
-- near an edge past it. Display only: the saved position is never rewritten,
-- so the bar goes back to it once the screen has room. Protected on our secure
-- bar frames in combat, so the combat /reload build runs this at combat end.
-- On ns, not a file local.
ns._eabClampAllBars = function()
    for _, f in pairs(barFrames) do
        f:SetClampedToScreen(true)
    end
end

local function SetupBar(info, skipProtected)
    local key = info.key
    local frame = CreateBarFrame(info)
    if skipProtected or InCombatLockdown() then
        -- One key: every bar of the combat build shares the single pass.
        ns.CombatQueue.Defer("EABClampBars", ns._eabClampAllBars)
    else
        frame:SetClampedToScreen(true)
    end
    -- A bar that can never become visible AND has no key bound gets no buttons
    -- at load: the button loop is 95 % of such a bar's setup cost, and most of
    -- that is Blizzard's CreateFrame on the action button template, which only
    -- a lower button count can reach. A hidden bar with keys keeps its buttons:
    -- its bindings stay live by contract and click-routed keys need a button to
    -- route to. The frame IS still built, so barFrames[key] stays non-nil for
    -- its 52 indexing sites and barButtons[key] is empty, not nil.
    -- ns._eabBuildSkippedBars builds them when the bar leaves the Never set or
    -- a key lands on it.
    if ns.IsNeverBar(info) and not ns.BarHasBoundKeys(info) then
        barButtons[key] = {}
        ns._eabBarNoButtons[key] = true
        -- Placeholder only, same fallback the button-derived value would take
        -- with no buttons. BuildBarButtons recomputes it from the real button.
        barBaseSize[key] = { w = 45, h = 45 }
        return frame, barButtons[key]
    end
    return frame, ns.BuildBarButtons(info, frame, skipProtected)
end

-------------------------------------------------------------------------------
--  First-Install Capture: no saved vars, so read Blizzard Edit Mode settings
--  for initial bar positions, icon counts, orientation and visibility.
-------------------------------------------------------------------------------
local function CaptureBlizzardDefaults()
    local captured = {}
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()

    -- Edit Mode stacks only the bottom bars that are SHOWN and parks a hidden
    -- one in its default position at UIParent's top-left corner until it
    -- shows. This returns the CENTER offsets of the slot the stack gives such
    -- a bar once it shows: right above the last shown bar before it in
    -- Blizzard's stack order, at the stack's left edge plus the bar's own
    -- indent (WoW Forever's default anchors carry one). nil when the bar is
    -- not parked there (moved in Edit Mode, or a layout with no stack).
    local function StackSlot(bar)
        local pt, rel, rpt, px, py = bar:GetPoint(1)
        if pt ~= "TOPLEFT" or rel ~= UIParent or rpt ~= "TOPLEFT" or px ~= 0 or py ~= 0 then return nil end
        local EU, EM = _G.EditModeUtil, _G.EditModeManagerFrame
        local ok, list
        if EU and EU.GetBottomActionBars then
            ok, list = pcall(EU.GetBottomActionBars, EU)
        elseif EM and EM.GetBottomActionBars then
            ok, list = pcall(EM.GetBottomActionBars, EM)
        end
        if not ok or type(list) ~= "table" then return nil end
        local function Anchor(f)
            if not (EM and EM.GetDefaultAnchor) then return nil end
            local okA, a = pcall(EM.GetDefaultAnchor, EM, f)
            return okA and type(a) == "table" and a or nil
        end
        local below, listed
        for i = 1, #list do
            local f = list[i]
            if f == bar then listed = true; break end
            if f and f:IsShown() and not f.skipAutomaticPositioning
                and (not f.IsInDefaultPosition or f:IsInDefaultPosition()) then
                local a = Anchor(f)
                if not (a and a.bottomBarExcludeFromStackIncrement) then below = f end
            end
        end
        if not listed then return nil end
        below = below or _G.MainActionBar
        local l, t = below and below:GetLeft(), below and below:GetTop()
        local w, h = bar:GetWidth(), bar:GetHeight()
        if not (l and t and w and h) then return nil end
        local kB = below:GetEffectiveScale() / uiScale
        local k = bar:GetEffectiveScale() / uiScale
        local aB, a = Anchor(below), Anchor(bar)
        local left = (l - (aB and aB.bottomBarOffsetX or 0)) * kB + (a and a.bottomBarOffsetX or 0) * k
        local bottom = t * kB + (tonumber(_G.BOTTOM_ACTION_BARS_SPACER_Y) or 4) * k
        return left + w * k / 2 - uiW / 2, bottom + h * k / 2 - uiH / 2
    end

    -- MainActionBar is the Edit Mode frame for Action Bar 1 (there is no MainMenuBar).
    -- Chain: ActionButton1 > MainActionBarButtonContainer1 > MainActionBar > UIParent
    local mainActionBar = _G["MainActionBar"]

    for _, info in ipairs(BAR_CONFIG) do
        local bar = _G[info.blizzFrame]
        if info.key == "MainBar" then
            -- MainBar reads Edit Mode settings + position from MainActionBar.
            -- Early disposal reparents it to the full-screen hiddenParent, so
            -- GetCenter still returns valid coordinates.
            local data = {}
            local mabPos = mainActionBar
            if mabPos then
                local cx, cy = mabPos:GetCenter()
                if cx and cy then
                    local bScale = mabPos:GetEffectiveScale()
                    cx = cx * bScale / uiScale
                    cy = cy * bScale / uiScale
                    data.point = "CENTER"
                    data.relPoint = "CENTER"
                    data.x = cx - (uiW / 2)
                    data.y = cy - (uiH / 2)
                end
            end

            local mab = mainActionBar
            if mab then
                if mab.numButtonsShowable and mab.numButtonsShowable > 0 then
                    data.numIcons = mab.numButtonsShowable
                end
                if mab.numRows and mab.numRows > 0 then
                    data.numRows = mab.numRows
                end
                if mab.GetSettingValue then
                    local ok, val = pcall(mab.GetSettingValue, mab, 0)
                    if ok and val ~= nil then data.orientation = (val == 0) and "horizontal" or "vertical" end
                    ok, val = pcall(mab.GetSettingValue, mab, 3)
                    if ok and val ~= nil and val > 0 then data.blizzIconScale = val / 100 end
                end
            end

            captured["MainBar"] = data

        elseif bar and bar:GetPoint(1) then
            local data = {}

            -- Position: convert to UIParent-relative CENTER coords.
            local cx, cy = bar:GetCenter()
            if cx and cy then
                local bScale = bar:GetEffectiveScale()
                cx = cx * bScale / uiScale
                cy = cy * bScale / uiScale
                data.point = "CENTER"
                data.relPoint = "CENTER"
                data.x = cx - (uiW / 2)
                data.y = cy - (uiH / 2)
            end

            -- A stance or pet bar hidden right now (no forms yet, no pet out)
            -- was never stacked: it takes the slot it gets once it shows.
            if (info.isStance or info.isPetBar) and not bar:IsShown() then
                local sx, sy = StackSlot(bar)
                if sx then
                    data.point, data.relPoint = "CENTER", "CENTER"
                    data.x, data.y, data.stackSlot = sx, sy, true
                end
            end

            -- Number of visible buttons try Edit Mode setting 2 first
            if bar.GetSettingValue then
                local ok, val = pcall(bar.GetSettingValue, bar, 2)
                if ok and val and val >= 6 and val <= 12 then
                    data.numIcons = val
                end
            end
            if not data.numIcons and bar.numButtonsShowable and bar.numButtonsShowable > 0 then
                data.numIcons = bar.numButtonsShowable
            end

            -- Number of rows try Edit Mode setting 1 first
            if bar.GetSettingValue then
                local ok, val = pcall(bar.GetSettingValue, bar, 1)
                if ok and val and val >= 1 and val <= 4 then
                    data.numRows = val
                end
            end
            if not data.numRows and bar.numRows and bar.numRows > 0 then
                data.numRows = bar.numRows
            end

            -- Orientation
            if bar.isHorizontal ~= nil then
                data.orientation = bar.isHorizontal and "horizontal" or "vertical"
            end
            if bar.GetSettingValue then
                local ok, val = pcall(bar.GetSettingValue, bar, 0)
                if ok and val ~= nil then
                    data.orientation = (val == 0) and "horizontal" or "vertical"
                end
            end

            -- Icon size (Edit Mode setting 3).
            if bar.GetSettingValue then
                local ok, val = pcall(bar.GetSettingValue, bar, 3)
                if ok and val ~= nil and val > 0 then
                    data.blizzIconScale = val / 100
                end
            end

            -- Always Show Buttons (setting 9): 0=off, 1=on
            if bar.GetSettingValue and info.key ~= "MainBar" and not info.isStance and not info.isPetBar then
                local ok, val = pcall(bar.GetSettingValue, bar, 9)
                if ok and val ~= nil then
                    data.alwaysShowButtons = (val == 1)
                end
            end

            -- An empty bar with alwaysShowButtons off would vanish entirely once we take over, so force it on.
            if data.alwaysShowButtons == false and info.blizzBtnPrefix then
                local numToCheck = data.numIcons or info.count or 12
                local hasAny = false
                for i = 1, numToCheck do
                    local btn = _G[info.blizzBtnPrefix .. i]
                    if btn and btn.action and HasAction(btn.action) then
                        hasAny = true
                        break
                    end
                end
                if not hasAny then
                    data.alwaysShowButtons = true
                end
            end

            -- Visibility (setting 5, bars 2-8 only): 0=Always, 1=InCombat,
            -- 2=OutOfCombat, 3=Hidden. A bar disabled via Gameplay > Action
            -- Bars (CVars) reports IsShown()=false while setting 5 still
            -- claims "Always Visible"; IsShown=false takes priority.
            if not bar:IsShown() then
                data.visibility = 3
            elseif bar.GetSettingValue and not info.isStance and not info.isPetBar then
                local ok, val = pcall(bar.GetSettingValue, bar, 5)
                if ok and val ~= nil then
                    data.visibility = val
                end
            end

            captured[info.key] = data
        end
    end
    return captured
end

-- First-install end cap span: the elements in one row directly beside
-- Blizzard's Action Bar 1 at capture time (horizontal bars 2-8 shown at all
-- times, the micro menu, the bag bar; stance and pet bars depend on the class,
-- so never), walked outward from bar 1 on each side. The last one each way
-- carries bar 1's cap for that side (ns.AB_CapsSides). Same row = vertical
-- overlap of at least half the shorter one; directly beside = facing edges
-- -8..12 apart (Blizzard's WoW Forever row leaves 4.5 and 7), the nearest
-- first. Returns the left and right bar keys, nil for none.
function ns.AB_CaptureCapSpan(captured)
    local main = _G.MainActionBar
    local mc = captured and captured.MainBar
    if not main or not mc or mc.orientation == "vertical" then return nil, nil end
    local uiS = UIParent:GetEffectiveScale()
    local function Rect(f)
        if not (f and f.GetLeft) then return nil end
        local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
        if not (l and r and t and b) or r - l < 1 or t - b < 1 then return nil end
        local k = f:GetEffectiveScale() / uiS
        return { l * k, r * k, t * k, b * k }
    end
    local home = Rect(main)
    if not home or home[2] - home[1] < 20 then return nil, nil end
    local cands = {}
    for _, info in ipairs(BAR_CONFIG) do
        local d = captured[info.key]
        if info.key ~= "MainBar" and d and info.blizzFrame and not info.isStance and not info.isPetBar
            and d.orientation == "horizontal" and (d.visibility == nil or d.visibility == 0) then
            local r = Rect(_G[info.blizzFrame])
            if r then cands[#cands + 1] = { key = info.key, r = r } end
        end
    end
    local mcf, mm = _G.MicroMenuContainer, _G.MicroMenu
    if mcf and mcf:IsShown() and mm and mm:GetParent() == mcf and mm:IsShown() and mm.isHorizontal ~= false then
        local r = Rect(mcf)
        if r then cands[#cands + 1] = { key = "MicroBar", r = r } end
    end
    local bags = _G.BagsBar
    if bags and bags:IsShown() and bags.isHorizontal ~= false then
        local r = Rect(bags)
        if r then cands[#cands + 1] = { key = "BagBar", r = r } end
    end
    local function Walk(dir)
        local cur, last, used = home, nil, {}
        while true do
            local best, bestGap
            for i = 1, #cands do
                local c = cands[i]
                if not used[c] then
                    local r = c.r
                    local ov = min(cur[3], r[3]) - max(cur[4], r[4])
                    if ov >= 0.5 * min(cur[3] - cur[4], r[3] - r[4]) then
                        local gap = (dir > 0) and (r[1] - cur[2]) or (cur[1] - r[2])
                        if gap >= -8 and gap <= 12 and (not bestGap or gap < bestGap) then
                            best, bestGap = c, gap
                        end
                    end
                end
            end
            if not best then return last end
            used[best] = true
            last, cur = best.key, best.r
        end
    end
    return Walk(-1), Walk(1)
end

-- Entry points the files after this one re-import by name.
I.CaptureBlizzardDefaults, I.SetupBar = CaptureBlizzardDefaults, SetupBar
