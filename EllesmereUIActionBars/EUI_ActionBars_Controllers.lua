if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ActionBars_Controllers.lua
--
--  The secure button controller (show-grid state, drag and click snippets)
--  and the override controller that follows vehicle, override and
--  possess bars.
--  Loads after EUI_ActionBars_Disposal.lua; reads ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...

local pairs, type = pairs, type
local InCombatLockdown = InCombatLockdown
local RegisterAttributeDriver = RegisterAttributeDriver

local I = ns._internals

-------------------------------------------------------------------------------
--  Central Action Button Controller: a SecureHandlerAttributeTemplate that
--  manages ALL action buttons. Tracks button-to-action mappings in a secure
--  table, implements bitwise showgrid, and defers visibility flush so rapid
--  state changes batch into a single update pass.
-------------------------------------------------------------------------------
local ActionButtonController = CreateFrame("Frame", "EABActionButtonController", UIParent, "SecureHandlerAttributeTemplate")

-- Showgrid reasons (bitwise flags)
local SHOWGRID = {
    GAME_EVENT = 2,
    SPELLBOOK  = 4,
    KEYBOUND   = 16,
    ALWAYS     = 32,
}

-- Lua-side button registry: [button] = actionSlot
local _controllerButtons = {}

ActionButtonController:Execute([[
    _eabBtnMap = table.new()
    _eabPendingVis = table.new()
]])

-- Secure method: SetShowGrid (bitwise flag toggle). Restricted Lua has no bit
-- library, so modular arithmetic tests/flips individual bits in the bitmask.
ActionButtonController:SetAttributeNoHandler("SetShowGrid", [[
    local show, reason, force = ...
    local cur = self:GetAttribute("showgrid") or 0
    local prev = cur

    if show then
        if cur % (reason * 2) < reason then cur = cur + reason end
    elseif cur % (reason * 2) >= reason then
        cur = cur - reason
    end

    if (prev ~= cur) or force then
        self:SetAttribute("showgrid", cur)
        for btn in pairs(_eabBtnMap) do
            btn:RunAttribute("SetShowGrid", show, reason)
        end
    end
]])

-- Secure method: run a named RunAttribute on every button matching an action slot
ActionButtonController:SetAttributeNoHandler("ForActionSlot", [[
    local slot, method = ...
    for btn, act in pairs(_eabBtnMap) do
        if act == slot then btn:RunAttribute(method) end
    end
]])

-- Deferred visibility: "flush"=0 marks dirty; the attribute driver resets it
-- to 1 after ~200ms, applying pending changes in one batch instead of per-change.
RegisterAttributeDriver(ActionButtonController, "flush", 1)

ActionButtonController:SetAttributeNoHandler("_onattributechanged", [[
    if name == "flush" and value == 1 then
        for btn in pairs(_eabPendingVis) do
            btn:RunAttribute("UpdateShown")
            _eabPendingVis[btn] = nil
        end
    end
]])

-- Per-button secure snippets (installed via WrapScript during registration)
local BTN_ON_ATTRIBUTE_CHANGED = [[
    if name == "action" then
        local prev = _eabBtnMap[self]
        if prev ~= value then
            _eabBtnMap[self] = value
            _eabPendingVis[self] = value
            control:SetAttribute("flush", 0)
        end
    end
]]

local BTN_POST_CLICK = [[
    control:RunAttribute("ForActionSlot", self:GetAttribute("action"), "UpdateShown")
]]

-- Forward the drag kind so the post-handler can refresh visibility for the
-- affected action slot.
local BTN_ON_RECEIVE_DRAG_BEFORE = [[
    if kind then return "message", kind end
]]

local BTN_ON_RECEIVE_DRAG_AFTER = [[
    control:RunAttribute("ForActionSlot", self:GetAttribute("action"), "UpdateShown")
]]

-- Re-evaluate on show/hide to catch delayed state changes from the secure environment.
local BTN_ON_SHOW_HIDE = [[
    self:RunAttribute("UpdateShown")
]]

-- Showgrid monitor: when Blizzard changes ActionButton1's showgrid
-- (e.g. during spell drag in combat), propagate to all our buttons.
local function InitShowGridMonitor()
    if not ActionButton1 then return end
    ActionButtonController:WrapScript(ActionButton1, "OnAttributeChanged", [[
        if name ~= "showgrid" then return end
        for r = 2, 4, 2 do
            local on = value % (r * 2) >= r
            control:RunAttribute("SetShowGrid", on, r)
        end
    ]])
end

-- Register a button with the controller (adds WrapScript handlers + secure table entry)
local function RegisterButtonWithController(btn)
    if _controllerButtons[btn] then return end

    -- On /reload, Lua locals reset but frames survive: if the button already
    -- carries our secure snippets, skip WrapScript+Execute (re-wrapping in
    -- combat taints the restricted env) and just restore the Lua registry.
    if btn:GetAttribute("_eabControllerRegistered") then
        _controllerButtons[btn] = true
        return
    end

    ActionButtonController:WrapScript(btn, "OnAttributeChanged", BTN_ON_ATTRIBUTE_CHANGED)
    ActionButtonController:WrapScript(btn, "PostClick", BTN_POST_CLICK)
    ActionButtonController:WrapScript(btn, "OnReceiveDrag", BTN_ON_RECEIVE_DRAG_BEFORE, BTN_ON_RECEIVE_DRAG_AFTER)
    ActionButtonController:WrapScript(btn, "OnShow", BTN_ON_SHOW_HIDE)
    ActionButtonController:WrapScript(btn, "OnHide", BTN_ON_SHOW_HIDE)
    -- Combat drag belt: dragging FROM one of our buttons reveals empty drop
    -- targets via the controller's secure broadcast, independent of the
    -- ActionButton1 showgrid monitor (which depends on Blizzard's retained
    -- MainActionBar event chain staying secure end to end). Pre-wrap returns
    -- nothing so the native drag proceeds untouched; the matching grid-off
    -- arrives via the monitor or, failing that, the regen apply -- but only
    -- when a pickup actually happens, which is what the guard below is for.
    -- OnDragStart fires on the GESTURE, not on a successful pickup. Blizzard's
    -- own handler no-ops when the bars are locked and the PICKUPACTION modifier
    -- is not held, so an unconditional reveal here lit every empty slot on a
    -- plain left-drag over a locked bar -- and since no pickup happened, no
    -- ACTIONBAR_HIDEGRID ever arrived to turn it back off. It then sat there
    -- until some unrelated repaint cleared it (reported: "goes away in 5-15
    -- seconds, or when I use the spell"). Mirror Blizzard's own condition so
    -- the reveal only fires when the drag will actually pick the action up.
    -- IsModifiedClick is whitelisted in the restricted environment.
    ActionButtonController:WrapScript(btn, "OnDragStart", [[
        if control:GetAttribute("eab-barslocked") ~= 1 or IsModifiedClick("PICKUPACTION") then
            control:RunAttribute("SetShowGrid", true, 2)
        end
    ]])

    -- Per-button showgrid: toggle the flag bit and update visibility. With "Always Show
    -- Buttons" off, empty slots are parked statehidden+Hidden+ alpha0+mouse-off, and
    -- insecure reversal is gated out of combat, so a combat spell drag needs drop
    -- targets revealed entirely INSIDE the restricted env: TRANSIENT grid reasons
    -- (every bit below ALWAYS) override statehidden for within-cutoff buttons, and
    -- Show/alpha/mouse restore on the hidden->shown edge only (so a live on-CD alpha on
    -- a visible button is never stomped). eab-withincutoff keeps icon-cutoff buttons
    -- out of the override; eab-click carries the bar's click-through setting so a
    -- reveal never turns a click-through bar clickable.
    btn:SetAttributeNoHandler("SetShowGrid", [[
        local show, reason, force = ...
        local cur = self:GetAttribute("showgrid") or 0
        local prev = cur

        if show then
            if cur % (reason * 2) < reason then cur = cur + reason end
        elseif cur % (reason * 2) >= reason then
            cur = cur - reason
        end

        if (prev ~= cur) or force then
            self:SetAttribute("showgrid", cur)
            local vis
            -- >= 2, NOT > 0: Blizzard's own SetShowGrid writes this same
            -- attribute on native buttons, and its CVAR reason is bit 1 --
            -- stamped at every login when the user has Blizzard's Always
            -- Show Buttons on. Counting it here made empty slots
            -- un-hideable (v8.7.5 report). Transient means bits 2+ only.
            if (cur % 32) >= 2 and (self:GetAttribute("eab-withincutoff") or 1) ~= 0 then
                vis = true
            else
                vis = (cur > 0 or HasAction(self:GetAttribute("action") or 0))
                    and not self:GetAttribute("statehidden")
            end
            if vis then
                if not self:IsShown() then
                    self:SetAlpha(1)
                    if (self:GetAttribute("eab-click") or 1) ~= 0 then
                        self:EnableMouse(true)
                    end
                end
                self:Show(true)
            else
                self:Hide(true)
            end
        end
    ]])

    -- Visibility: show if grid active or action exists, unless explicitly
    -- state-hidden. Same transient-grid override and edge-gated alpha/mouse
    -- restore as SetShowGrid, so a mid-drag flush cannot re-hide a revealed target.
    btn:SetAttributeNoHandler("UpdateShown", [[
        local cur = self:GetAttribute("showgrid") or 0
        local hasAct = HasAction(self:GetAttribute("action") or 0)
        local hidden = self:GetAttribute("statehidden")
        local vis
        -- >= 2, not > 0: bit 1 is Blizzard's CVAR reason (see SetShowGrid
        -- above) and must never count as a transient reveal.
        if (cur % 32) >= 2 and (self:GetAttribute("eab-withincutoff") or 1) ~= 0 then
            vis = true
        else
            vis = (cur > 0 or hasAct) and not hidden
        end
        if vis then
            if not self:IsShown() then
                self:SetAlpha(1)
                if (self:GetAttribute("eab-click") or 1) ~= 0 then
                    self:EnableMouse(true)
                end
            end
            self:Show(true)
        else
            self:Hide(true)
        end
    ]])

    -- Add to the secure button map
    ActionButtonController:SetFrameRef("add", btn)
    ActionButtonController:Execute([[
        local b = self:GetFrameRef("add")
        _eabBtnMap[b] = b:GetAttribute("action") or 0
    ]])

    -- Mark the button so we can detect it survived a /reload
    btn:SetAttributeNoHandler("_eabControllerRegistered", true)

    _controllerButtons[btn] = true
end

-- Lua-side showgrid manipulation (out of combat only)
local function SetShowGridInsecure(btn, show, reason, force)
    if InCombatLockdown() then ns._eabApplyDeferred = true return end
    if type(reason) ~= "number" then return end

    local value = btn:GetAttribute("showgrid") or 0
    local prevValue = value

    if show then
        value = bit.bor(value, reason)
    else
        value = bit.band(value, bit.bnot(reason))
    end

    if (value ~= prevValue) or force then
        btn:SetAttribute("showgrid", value)
    end
end

-------------------------------------------------------------------------------
--  Override Controller: monitors vehicle/override/possess/form/petbattle
--  states via attribute drivers and propagates changes to all registered bar
--  frames. Parented to UIParent -- never parent addon frames to
--  OverrideActionBar, which taints its child hierarchy and blocks BeginActionBarTransition.
-------------------------------------------------------------------------------
local OverrideController
do
    OverrideController = CreateFrame("Frame", "EABOverrideController", UIParent,
        "SecureHandlerAttributeTemplate")

    OverrideController:SetAttributeNoHandler("_onattributechanged", [[
        -- Propagate known state attributes to all registered bar frames
        if name == "overrideui" or name == "petbattleui" or name == "overridepage" then
            for _, f in pairs(_eabBarFrames) do
                f:SetAttribute("state-" .. name, name == "overridepage" and value or (value == 1))
            end
        else
            -- Any other attribute change: re-evaluate the override page from
            -- Blizzard's vehicle/override/shapeshift APIs.
            local pg = 0
            if HasVehicleActionBar and HasVehicleActionBar() then
                pg = GetVehicleBarIndex and GetVehicleBarIndex() or 0
            elseif HasOverrideActionBar and HasOverrideActionBar() then
                pg = GetOverrideBarIndex and GetOverrideBarIndex() or 0
            elseif HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() then
                pg = GetTempShapeshiftBarIndex() or 0
            end
            if self:GetAttribute("overridepage") ~= pg then
                self:SetAttribute("overridepage", pg)
            end
        end
    ]])

    -- Secure table of bar frames that receive state broadcasts
    OverrideController:Execute([[ _eabBarFrames = table.new() ]])

    -- overrideui driven by [overridebar][vehicleui] macro instead of parenting
    -- to OverrideActionBar (which would taint the protected frame).
    for attr, driver in pairs({
        form = "[form]1;0",
        overridebar = "[overridebar]1;0",
        overrideui = "[overridebar][vehicleui]1;0",
        possessbar = "[possessbar]1;0",
        sstemp = "[shapeshift]1;0",
        vehicle = "[@vehicle,exists]1;0",
        vehicleui = "[vehicleui]1;0",
        petbattleui = "[petbattle]1;0",
    }) do
        RegisterAttributeDriver(OverrideController, attr, driver)
    end
end

-- Add a bar frame to the watch list. Deduped in the snippet: the secure list
-- can never be pruned, so a re-registration would grow it and every sweep permanently.
local function RegisterBarWithOverrideController(frame)
    OverrideController:SetFrameRef("add", frame)
    OverrideController:Execute([[
        local f = self:GetFrameRef("add")
        for i = 1, #_eabBarFrames do
            if _eabBarFrames[i] == f then return end
        end
        table.insert(_eabBarFrames, f)
    ]])

    -- Initialize state on the frame
    frame:SetAttribute("state-overrideui", tonumber(OverrideController:GetAttribute("overrideui")) == 1)
    frame:SetAttribute("state-petbattleui", tonumber(OverrideController:GetAttribute("petbattleui")) == 1)
    frame:SetAttribute("state-overridepage", OverrideController:GetAttribute("overridepage") or 0)
end

-- Entry points the files after this one re-import by name.
I.SHOWGRID, I.SetShowGridInsecure, I._controllerButtons = SHOWGRID, SetShowGridInsecure, _controllerButtons
I.RegisterButtonWithController = RegisterButtonWithController
I.RegisterBarWithOverrideController = RegisterBarWithOverrideController
I.ActionButtonController, I.InitShowGridMonitor = ActionButtonController, InitShowGridMonitor
