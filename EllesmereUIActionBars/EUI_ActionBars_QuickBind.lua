-------------------------------------------------------------------------------
-- EllesmereUI Quick Bind Mode (Wrath 3.3.5)
-- ElvUI-style hover-to-bind implementation; replaces Blizzard_QuickKeybind,
-- which is a Retail-only load-on-demand addon.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local binder = CreateFrame("Frame", "EllesmereUIQuickBinder", UIParent)
binder:SetFrameStrata("TOOLTIP")
binder:SetFrameLevel(100)
binder:EnableMouse(true)
binder:EnableKeyboard(true)
binder:EnableMouseWheel(true)
binder:Hide()

local shade = binder:CreateTexture(nil, "BACKGROUND")
shade:SetAllPoints(binder)
shade:SetTexture(0, 0, 0, 0.3)

local window = CreateFrame("Frame", "EllesmereUIQuickBindWindow", UIParent)
window:SetFrameStrata("DIALOG")
window:SetFrameLevel(110)
window:SetWidth(390)
window:SetHeight(172)
window:SetPoint("TOP", UIParent, "TOP", 0, -110)
window:SetMovable(true)
window:EnableMouse(true)
window:SetClampedToScreen(true)
window:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
window:SetBackdropColor(0.025, 0.035, 0.04, 0.97)
window:SetBackdropBorderColor(0.05, 0.82, 0.62, 0.9)
window:Hide()

local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -14)
title:SetText("Quick Keybind Mode")

local description = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
description:SetPoint("TOPLEFT", 18, -42)
description:SetPoint("TOPRIGHT", -18, -42)
description:SetJustifyH("LEFT")
description:SetText("Hover an action button and press a key to bind it.\nPress Escape or right-click to clear all bindings for that button.")

local function MakeButton(text, x, callback, y)
    local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    button:SetWidth(160)
    button:SetHeight(24)
    button:SetPoint("BOTTOM", x, y or 13)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local active, changed, currentButton, currentCommand
local registered = setmetatable({}, { __mode = "k" })

local function Print(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff0cd29fEllesmereUI:|r " .. message)
    end
end

-- SetBinding updates Blizzard's binding table immediately, but 3.3.5 does
-- not reliably emit UPDATE_BINDINGS for addon-driven changes. EllesmereUI's
-- custom buttons execute through override bindings, so explicitly rebuild
-- that routing and repaint the hotkey labels after every change.
local function RefreshActionBarBindings()
    if InCombatLockdown() then return end
    if _G._EAB_UpdateKeybinds then
        _G._EAB_UpdateKeybinds()
    end
    if ns and ns.EAB and ns.EAB.ApplyFonts then
        ns.EAB:ApplyFonts()
    end
end

local bindingScopeButton

local function UpdateBindingScopeButton()
    if GetCurrentBindingSet() == 2 then
        bindingScopeButton:SetText("Switch to Account-wide Keybindings")
    else
        bindingScopeButton:SetText("Switch to Character-specific Keybindings")
    end
end

bindingScopeButton = MakeButton("", 0, function()
    if InCombatLockdown() then return end
    local currentBindingSet = GetCurrentBindingSet()
    local bindingSet = currentBindingSet == 2 and 1 or 2
    LoadBindings(currentBindingSet)
    SetCurrentBindingSet(bindingSet)
    LoadBindings(bindingSet)
    RefreshActionBarBindings()
    changed = false
    UpdateBindingScopeButton()
end, 43)
bindingScopeButton:SetWidth(350)

local function BindingCommand(button, kind)
    if button.commandName then return button.commandName end
    local id = button.GetID and button:GetID()
    if not id then return end
    if kind == "STANCE" then return "SHAPESHIFTBUTTON" .. id end
    if kind == "PET" then return "BONUSACTIONBUTTON" .. id end
end

local function ButtonLabel(button, command)
    local name = button.GetName and button:GetName()
    if GetBindingName and command then
        local bindingName = GetBindingName(command)
        if bindingName and bindingName ~= "" then return bindingName end
    end
    return name or command or "Action Button"
end

local function ShowBindingTooltip()
    if not currentButton or not currentCommand then return end
    GameTooltip:SetOwner(binder, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(ButtonLabel(currentButton, currentCommand), 1, 1, 1)
    local key1, key2 = GetBindingKey(currentCommand)
    if key1 or key2 then
        GameTooltip:AddLine("Bound to: " .. table.concat({ key1 or "", key2 or "" }, key2 and ", " or ""), 0.1, 0.85, 0.65)
    else
        GameTooltip:AddLine("No bindings set", 0.65, 0.65, 0.65)
    end
    GameTooltip:Show()
end

local function HoverButton(button, kind)
    if not active or InCombatLockdown() then return end
    local command = BindingCommand(button, kind)
    if not command then return end
    currentButton, currentCommand = button, command
    binder:ClearAllPoints()
    binder:SetAllPoints(button)
    binder:Show()
    ShowBindingTooltip()
end

local function LeaveButton()
    currentButton, currentCommand = nil, nil
    binder:ClearAllPoints()
    binder:Hide()
    GameTooltip:Hide()
end

local ignored = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, UNKNOWN = true, LeftButton = true,
}

local function BindInput(key)
    if not active or not currentCommand or ignored[key] then return end
    if InCombatLockdown() then return end

    if key == "ESCAPE" or key == "RightButton" then
        local old1, old2 = GetBindingKey(currentCommand)
        if old1 then SetBinding(old1) end
        if old2 then SetBinding(old2) end
        changed = true
        RefreshActionBarBindings()
        Print("Cleared bindings for " .. ButtonLabel(currentButton, currentCommand) .. ".")
        ShowBindingTooltip()
        return
    end

    if key == "MiddleButton" then key = "BUTTON3" end
    if string.find(key, "Button%d") then key = string.upper(key) end
    local binding = (IsAltKeyDown() and "ALT-" or "")
        .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
    SetBinding(binding, currentCommand)
    changed = true
    RefreshActionBarBindings()
    Print(binding .. " bound to " .. ButtonLabel(currentButton, currentCommand) .. ".")
    ShowBindingTooltip()
end

binder:SetScript("OnKeyUp", function(_, key) BindInput(key) end)
binder:SetScript("OnMouseUp", function(_, button) BindInput(button) end)
binder:SetScript("OnMouseWheel", function(_, delta)
    BindInput(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
end)
binder:SetScript("OnLeave", LeaveButton)

local function Register(button, kind)
    if not button or registered[button] then return end
    registered[button] = true
    button:HookScript("OnEnter", function(self) HoverButton(self, kind) end)
end

local function RegisterButtons()
    for i = 1, 72 do Register(_G["EABButton" .. i]) end
    local stancePrefix = _G.ShapeshiftButton1 and "ShapeshiftButton" or "StanceButton"
    for i = 1, 10 do
        Register(_G[stancePrefix .. i], "STANCE")
        Register(_G["PetActionButton" .. i], "PET")
    end
end

local function Close(save)
    if not active then return end
    active = false
    LeaveButton()
    window:Hide()
    if save then
        SaveBindings(GetCurrentBindingSet())
        RefreshActionBarBindings()
        if changed then Print("Keybindings saved.") end
    else
        LoadBindings(GetCurrentBindingSet())
        RefreshActionBarBindings()
        if changed then Print("Keybinding changes discarded.") end
    end
    changed = false
    if EllesmereUI.ActionBarsQuickBindPresentation then
        EllesmereUI.ActionBarsQuickBindPresentation(false)
    end
end

MakeButton("Discard", -88, function() Close(false) end)
MakeButton("Save", 88, function() Close(true) end)

window:SetScript("OnMouseDown", function(self) self:StartMoving() end)
window:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

function EllesmereUI.ToggleQuickBindMode(forceOpen)
    if active and not forceOpen then Close(true); return end
    if active or InCombatLockdown() then return end
    RegisterButtons()
    if EllesmereUI.ActionBarsQuickBindPresentation
        and not EllesmereUI.ActionBarsQuickBindPresentation(true) then return end
    active, changed = true, false
    UpdateBindingScopeButton()
    window:Show()
end

local function QuickBindSlashCommand()
    EllesmereUI.ToggleQuickBindMode()
end

local function RegisterQuickBindSlashCommand()
    SLASH_EABQUICKKEYBIND1 = "/kb"
    SlashCmdList["EABQUICKKEYBIND"] = QuickBindSlashCommand

    -- ElvUI registers /kb as ACECONSOLE_KB. Whichever slash alias was hashed
    -- last wins on 3.3.5, so point that existing entry at EllesmereUI too and
    -- explicitly repair the already-built hash after PLAYER_LOGIN.
    if SlashCmdList["ACECONSOLE_KB"] then
        SlashCmdList["ACECONSOLE_KB"] = QuickBindSlashCommand
    end
    if hash_SlashCmdList then
        -- Wrath's ChatFrame hash stores the callable itself (Retail stores a
        -- command-list key here). Supplying the string makes ChatEdit_ParseText
        -- try to call that string and raises "attempt to call field '?'".
        hash_SlashCmdList["/KB"] = QuickBindSlashCommand
    end
end

RegisterQuickBindSlashCommand()

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        LoadBindings(GetCurrentBindingSet())
        RefreshActionBarBindings()
        RegisterQuickBindSlashCommand()
        -- Run once more after all PLAYER_LOGIN handlers (including ElvUI's)
        -- have completed, so a later AceConsole registration cannot reclaim
        -- the command during the same event dispatch.
        C_Timer.After(0, RegisterQuickBindSlashCommand)
    elseif active then
        Close(false)
    end
end)
