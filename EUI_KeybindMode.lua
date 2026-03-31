--------------------------------------------------------------------------------
--  EUI_KeybindMode.lua
--  Fast hover-to-bind keybinding mode for EllesmereUI action bars
--------------------------------------------------------------------------------
local _, ns = ...

local EllesmereUI = EllesmereUI
local PP = nil  -- resolved on first use (EllesmereUI.PP)

-- Lua APIs
local pairs, ipairs, type = pairs, ipairs, type
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local SetBinding, GetBindingKey, SaveBindings = SetBinding, GetBindingKey, SaveBindings
local GetBindingAction = GetBindingAction

-- Debug log (saved to EUI_KeybindDebugLog saved variable)
EUI_KeybindDebugLog = EUI_KeybindDebugLog or {}
local function DebugLog(msg)
    EUI_KeybindDebugLog[#EUI_KeybindDebugLog + 1] = date("%H:%M:%S") .. " " .. msg
    print("|cff0cd29f[KB]|r " .. msg)
end

-- State
local isActive = false
local keybindFrame = nil       -- main overlay frame
local buttonOverlays = {}      -- array of overlay frames
local filterPills = {}         -- bar filter pill frames
local dimmedBars = {}          -- [barKey] = true if dimmed
local hoveredOverlay = nil     -- currently hovered button overlay
local pendingConflict = nil    -- { overlay, keyCombo, existingAction } awaiting confirm

-- Bar config: maps barKey to WoW binding command prefix
local BINDING_MAP = {
    MainBar   = "ACTIONBUTTON",
    Bar2      = "MULTIACTIONBAR1BUTTON",
    Bar3      = "MULTIACTIONBAR2BUTTON",
    Bar4      = "MULTIACTIONBAR3BUTTON",
    Bar5      = "MULTIACTIONBAR4BUTTON",
    Bar6      = "MULTIACTIONBAR5BUTTON",
    Bar7      = "MULTIACTIONBAR6BUTTON",
    Bar8      = "MULTIACTIONBAR7BUTTON",
    StanceBar = "SHAPESHIFTBUTTON",
    PetBar    = "BONUSACTIONBUTTON",
}

-- Ordered bar keys for filter pills
local BAR_ORDER = {
    "MainBar", "Bar2", "Bar3", "Bar4", "Bar5",
    "Bar6", "Bar7", "Bar8", "StanceBar", "PetBar",
}

-- Display names for filter pills
local BAR_LABELS = {
    MainBar   = "Main Bar",
    Bar2      = "Bar 2",
    Bar3      = "Bar 3",
    Bar4      = "Bar 4",
    Bar5      = "Bar 5",
    Bar6      = "Bar 6",
    Bar7      = "Bar 7",
    Bar8      = "Bar 8",
    StanceBar = "Stance",
    PetBar    = "Pet",
}

-- Colors (resolve dynamically; fall back to teal if GetAccentColor not yet available)
local ACCENT_R, ACCENT_G, ACCENT_B = 0.047, 0.824, 0.624
local WARN_R, WARN_G, WARN_B = 1.0, 0.706, 0.235
local FONT_PATH = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
local MEDIA_PATH = "Interface\\AddOns\\EllesmereUI\\media\\"

local function RefreshAccent()
    if EllesmereUI.GetAccentColor then
        ACCENT_R, ACCENT_G, ACCENT_B = EllesmereUI.GetAccentColor()
    end
end

--------------------------------------------------------------------------------
--  Keybind Profile Commands
--  All action bar binding commands we track for profile snapshots
--------------------------------------------------------------------------------
local TRACKED_COMMANDS = {}
do
    local barCounts = {
        MainBar = 12, Bar2 = 12, Bar3 = 12, Bar4 = 12,
        Bar5 = 12, Bar6 = 12, Bar7 = 12, Bar8 = 12,
        StanceBar = 10, PetBar = 10,
    }
    for _, barKey in ipairs(BAR_ORDER) do
        local prefix = BINDING_MAP[barKey]
        local count = barCounts[barKey] or 12
        for i = 1, count do
            TRACKED_COMMANDS[#TRACKED_COMMANDS + 1] = prefix .. i
        end
    end
end

--------------------------------------------------------------------------------
--  Keybind Profiles — Snapshot / Restore
--------------------------------------------------------------------------------

function EllesmereUI:SnapshotKeybinds(profileName)
    if not profileName or profileName == "" then return end
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.keybindProfiles then EllesmereUIDB.keybindProfiles = {} end

    local binds = {}
    for _, cmd in ipairs(TRACKED_COMMANDS) do
        local key1, key2 = GetBindingKey(cmd)
        if key1 then
            binds[cmd] = key1
            if key2 then
                binds[cmd .. "_2"] = key2
            end
        end
    end
    EllesmereUIDB.keybindProfiles[profileName] = { binds = binds }
end

function EllesmereUI:RestoreKeybinds(profileName)
    if not profileName or profileName == "" then return end
    if not EllesmereUIDB or not EllesmereUIDB.keybindProfiles then return end
    local profile = EllesmereUIDB.keybindProfiles[profileName]
    if not profile or not profile.binds then return end

    for _, cmd in ipairs(TRACKED_COMMANDS) do
        local key1, key2 = GetBindingKey(cmd)
        if key1 then SetBinding(key1, nil) end
        if key2 then SetBinding(key2, nil) end
    end

    for cmd, key in pairs(profile.binds) do
        if not cmd:match("_2$") then
            SetBinding(key, cmd)
            local key2 = profile.binds[cmd .. "_2"]
            if key2 then
                SetBinding(key2, cmd)
            end
        end
    end

    SaveBindings(2)
end

function EllesmereUI:GetCurrentSpecKeybindProfile()
    local specIdx = GetSpecialization and GetSpecialization()
    if not specIdx or specIdx < 1 then return nil end
    local specID = GetSpecializationInfo(specIdx)
    if not specID then return nil end

    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.specKeybindProfiles then EllesmereUIDB.specKeybindProfiles = {} end

    local profileName = EllesmereUIDB.specKeybindProfiles[specID]
    return profileName, specID
end

function EllesmereUI:AssignKeybindProfileToSpec(profileName, specID)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.specKeybindProfiles then EllesmereUIDB.specKeybindProfiles = {} end
    EllesmereUIDB.specKeybindProfiles[specID] = profileName
end

--------------------------------------------------------------------------------
--  Forward declarations
--------------------------------------------------------------------------------
local OpenKeybindMode, CloseKeybindMode

--------------------------------------------------------------------------------
--  Public API
--------------------------------------------------------------------------------
function EllesmereUI:ToggleKeybindMode()
    if isActive then
        CloseKeybindMode()
    else
        OpenKeybindMode()
    end
end

--------------------------------------------------------------------------------
--  Slash command
--------------------------------------------------------------------------------
SLASH_EUIKEYBIND1 = "/euikeybind"
SlashCmdList.EUIKEYBIND = function()
    if InCombatLockdown() then
        print("|cffff6060[EllesmereUI]|r Cannot enter Keybind Mode during combat.")
        return
    end
    EllesmereUI:ToggleKeybindMode()
end

--------------------------------------------------------------------------------
--  Overlay Frame
--------------------------------------------------------------------------------
local function CreateOverlayFrame()
    if keybindFrame then return end
    PP = PP or EllesmereUI.PP

    keybindFrame = CreateFrame("Frame", "EllesmereKeybindMode", UIParent)
    keybindFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    keybindFrame:SetAllPoints(UIParent)
    keybindFrame:EnableMouse(false)
    keybindFrame:SetAlpha(0)

    local overlay = keybindFrame:CreateTexture(nil, "BACKGROUND")
    overlay:SetAllPoints()
    overlay:SetColorTexture(0.02, 0.03, 0.04, 0.80)
    keybindFrame._overlay = overlay
end

local function DestroyOverlayFrame()
    if not keybindFrame then return end
    keybindFrame:Hide()
    keybindFrame:SetParent(nil)
    keybindFrame = nil
end

--------------------------------------------------------------------------------
--  Fade Animations
--------------------------------------------------------------------------------
local function FadeIn(onComplete)
    if not keybindFrame then return end
    keybindFrame:Show()
    local elapsed = 0
    local duration = 0.3
    keybindFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= duration then
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
            if onComplete then onComplete() end
            return
        end
        self:SetAlpha(elapsed / duration)
    end)
end

local function FadeOut(onComplete)
    if not keybindFrame then return end
    local elapsed = 0
    local duration = 0.2
    keybindFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= duration then
            self:SetAlpha(0)
            self:SetScript("OnUpdate", nil)
            if onComplete then onComplete() end
            return
        end
        self:SetAlpha(1 - (elapsed / duration))
    end)
end

--------------------------------------------------------------------------------
--  HUD Bar
--------------------------------------------------------------------------------
local hudFrame = nil

local function CreateHUD()
    if hudFrame then hudFrame:Show(); return end
    RefreshAccent()

    hudFrame = CreateFrame("Frame", nil, keybindFrame)
    hudFrame:SetSize(680, 40)
    hudFrame:SetPoint("TOP", UIParent, "TOP", 0, -18)
    hudFrame:SetFrameLevel(keybindFrame:GetFrameLevel() + 10)

    local bg = hudFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.035, 0.055, 0.075, 0.95)

    EllesmereUI.MakeBorder(hudFrame, ACCENT_R, ACCENT_G, ACCENT_B, 0.35)

    -- Accent glow along top edge
    local topGlow = hudFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
    topGlow:SetHeight(1)
    topGlow:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 1, -1)
    topGlow:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -1, -1)
    topGlow:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.40)

    -- Keybind icon (left side)
    local hudIcon = hudFrame:CreateTexture(nil, "OVERLAY")
    hudIcon:SetSize(16, 16)
    hudIcon:SetPoint("LEFT", hudFrame, "LEFT", 14, 0)
    hudIcon:SetTexture(MEDIA_PATH .. "icons\\eui-keybind-2.png")
    hudIcon:SetVertexColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)

    -- Title
    local label = hudFrame:CreateFontString(nil, "OVERLAY")
    label:SetFont(FONT_PATH, 13, "")
    label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    label:SetPoint("LEFT", hudIcon, "RIGHT", 8, 0)
    label:SetText("KEYBIND MODE")

    -- Separator
    local sep1 = hudFrame:CreateFontString(nil, "OVERLAY")
    sep1:SetFont(FONT_PATH, 11, "")
    sep1:SetTextColor(1, 1, 1, 0.15)
    sep1:SetPoint("LEFT", label, "RIGHT", 12, 0)
    sep1:SetText("|")

    -- Instructions (hoverable)
    local instr = hudFrame:CreateFontString(nil, "OVERLAY")
    instr:SetFont(FONT_PATH, 10, "")
    instr:SetTextColor(1, 1, 1, 0.45)
    instr:SetPoint("LEFT", sep1, "RIGHT", 12, 0)
    instr:SetText("Hover + press key  |  ESC unbind  |  ESC exit")

    local instrHit = CreateFrame("Frame", nil, hudFrame)
    instrHit:SetPoint("TOPLEFT", instr, "TOPLEFT", -4, 4)
    instrHit:SetPoint("BOTTOMRIGHT", instr, "BOTTOMRIGHT", 4, -4)
    instrHit:SetScript("OnEnter", function()
        instr:SetTextColor(1, 1, 1, 0.7)
        EllesmereUI.ShowWidgetTooltip(instr,
            "How to use Keybind Mode:\n\n"
            .. "1. Hover over any action button\n"
            .. "2. Press a key (or key combo) to bind it\n"
            .. "3. Press ESC while hovering to clear a binding\n"
            .. "4. Press ESC with nothing hovered to exit\n\n"
            .. "Mouse buttons (including Button4/5) also work.\n"
            .. "Conflicts are shown in orange \226\128\148 press the same key again to override.",
            { anchor = "below" })
    end)
    instrHit:SetScript("OnLeave", function()
        instr:SetTextColor(1, 1, 1, 0.45)
        EllesmereUI.HideWidgetTooltip()
    end)
    instrHit:SetMouseClickEnabled(false)

    -- Close button (right side)
    local closeBtn = CreateFrame("Button", nil, hudFrame)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("RIGHT", hudFrame, "RIGHT", -10, 0)
    closeBtn:SetFrameLevel(hudFrame:GetFrameLevel() + 2)

    local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
    closeTex:SetFont(FONT_PATH, 14, "")
    closeTex:SetTextColor(1, 1, 1, 0.35)
    closeTex:SetAllPoints()
    closeTex:SetText("X")

    closeBtn:SetScript("OnEnter", function(self)
        closeTex:SetTextColor(1, 0.35, 0.35, 0.9)
        EllesmereUI.ShowWidgetTooltip(self, "Close Keybind Mode\nBindings are saved automatically.", { anchor = "below" })
    end)
    closeBtn:SetScript("OnLeave", function()
        closeTex:SetTextColor(1, 1, 1, 0.35)
        EllesmereUI.HideWidgetTooltip()
    end)
    closeBtn:SetScript("OnClick", function() CloseKeybindMode() end)

    -- Separator before profile
    local sep2 = hudFrame:CreateFontString(nil, "OVERLAY")
    sep2:SetFont(FONT_PATH, 11, "")
    sep2:SetTextColor(1, 1, 1, 0.15)
    sep2:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
    sep2:SetText("|")

    -- Profile indicator (hoverable)
    local profFrame = CreateFrame("Frame", nil, hudFrame)
    profFrame:SetSize(140, 24)
    profFrame:SetPoint("RIGHT", sep2, "LEFT", -8, 0)
    profFrame:SetFrameLevel(hudFrame:GetFrameLevel() + 2)

    local profIcon = profFrame:CreateTexture(nil, "OVERLAY")
    profIcon:SetSize(14, 14)
    profIcon:SetPoint("LEFT", profFrame, "LEFT", 0, 0)

    local profLabel = profFrame:CreateFontString(nil, "OVERLAY")
    profLabel:SetFont(FONT_PATH, 11, "")
    profLabel:SetPoint("LEFT", profIcon, "RIGHT", 6, 0)
    profLabel:SetPoint("RIGHT", profFrame, "RIGHT", 0, 0)
    profLabel:SetJustifyH("LEFT")
    profLabel:SetWordWrap(false)

    -- Resolve spec info for profile display
    local specIdx = GetSpecialization and GetSpecialization()
    local specName, specIconPath
    if specIdx and specIdx > 0 then
        local _, sName, _, sIcon = GetSpecializationInfo(specIdx)
        specName = sName
        specIconPath = sIcon
    end

    if specIconPath then
        profIcon:SetTexture(specIconPath)
        profIcon:SetAlpha(0.8)
    else
        profIcon:SetTexture(MEDIA_PATH .. "icons\\eui-keybind-2.png")
        profIcon:SetVertexColor(1, 1, 1, 0.4)
    end

    local profileName = EllesmereUI:GetCurrentSpecKeybindProfile()
    if profileName then
        profLabel:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
        profLabel:SetText(profileName)
    else
        profLabel:SetTextColor(1, 1, 1, 0.35)
        profLabel:SetText(specName or "No Profile")
    end

    profFrame:SetScript("OnEnter", function(self)
        profLabel:SetAlpha(1)
        profIcon:SetAlpha(1)
        local tip
        if profileName then
            tip = "Keybind Profile: |cff0cd29f" .. profileName .. "|r\n\n"
                .. "Bindings will be saved to this profile when you close Keybind Mode."
        else
            tip = "No keybind profile exists for " .. (specName or "this spec") .. " yet.\n\n"
                .. "Your current bindings will be saved as a new profile when you close Keybind Mode."
        end
        EllesmereUI.ShowWidgetTooltip(self, tip, { anchor = "below" })
    end)
    profFrame:SetScript("OnLeave", function()
        profLabel:SetAlpha(0.9)
        profIcon:SetAlpha(0.8)
        EllesmereUI.HideWidgetTooltip()
    end)
    profFrame:SetMouseClickEnabled(false)
end

local function DestroyHUD()
    if hudFrame then
        hudFrame:Hide()
        hudFrame:SetParent(nil)
        hudFrame = nil
    end
end

--------------------------------------------------------------------------------
--  Filter Pills
--------------------------------------------------------------------------------
local pillContainer = nil

local function UpdatePillVisual(pill, active)
    if active then
        pill._bg:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.15)
        pill._label:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        pill._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.5)
        -- Show glow
        if pill._glow then pill._glow:Show() end
        -- Start subtle pulse
        if not pill._pulsing then
            pill._pulsing = true
            pill._pulseElapsed = 0
            pill:SetScript("OnUpdate", function(self, dt)
                self._pulseElapsed = (self._pulseElapsed or 0) + dt
                -- Gentle sine wave: border alpha oscillates 0.35 to 0.65
                local t = math.sin(self._pulseElapsed * 2.2) * 0.5 + 0.5
                local alpha = 0.35 + t * 0.30
                self._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, alpha)
                if self._glow then
                    self._glow:SetAlpha(0.15 + t * 0.15)
                end
            end)
        end
    else
        pill._bg:SetColorTexture(1, 1, 1, 0.03)
        pill._label:SetTextColor(1, 1, 1, 0.3)
        pill._border:SetColor(1, 1, 1, 0.12)
        -- Hide glow, stop pulse
        if pill._glow then pill._glow:Hide() end
        pill._pulsing = false
        pill:SetScript("OnUpdate", nil)
    end
end

local function UpdateBarDimming(barKey)
    local isDimmed = dimmedBars[barKey]
    for _, ov in ipairs(buttonOverlays) do
        if ov._barKey == barKey then
            if isDimmed then
                ov:SetAlpha(0.25)
                ov:EnableMouse(false)
            else
                ov:SetAlpha(1)
                ov:EnableMouse(true)
            end
        end
    end
end

local function CreateFilterPills()
    if pillContainer then pillContainer:Show(); return end

    pillContainer = CreateFrame("Frame", nil, keybindFrame)
    pillContainer:SetSize(1, 28)
    pillContainer:SetPoint("TOP", hudFrame, "BOTTOM", 0, -10)
    pillContainer:SetFrameLevel(keybindFrame:GetFrameLevel() + 10)

    local EAB = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)

    local pills = {}
    local totalWidth = 0

    for _, barKey in ipairs(BAR_ORDER) do
        local barFrame
        if EAB and EAB._barFrames then
            barFrame = EAB._barFrames[barKey]
        end
        if barFrame and barFrame:IsShown() then
            local pill = CreateFrame("Button", nil, pillContainer)
            pill:SetSize(70, 24)
            pill:SetFrameLevel(pillContainer:GetFrameLevel() + 1)
            pill._barKey = barKey

            local bg = pill:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            pill._bg = bg

            local label = pill:CreateFontString(nil, "OVERLAY")
            label:SetFont(FONT_PATH, 11, "")
            label:SetPoint("CENTER")
            label:SetText(BAR_LABELS[barKey] or barKey)
            pill._label = label

            pill._border = EllesmereUI.MakeBorder(pill, ACCENT_R, ACCENT_G, ACCENT_B, 0.5)

            -- Soft glow behind pill (slightly larger, blurred look)
            local glow = pill:CreateTexture(nil, "BACKGROUND", nil, -1)
            glow:SetPoint("TOPLEFT", pill, "TOPLEFT", -4, 4)
            glow:SetPoint("BOTTOMRIGHT", pill, "BOTTOMRIGHT", 4, -4)
            glow:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.20)
            pill._glow = glow

            dimmedBars[barKey] = false

            pill:SetScript("OnClick", function(self)
                dimmedBars[barKey] = not dimmedBars[barKey]
                UpdatePillVisual(self, not dimmedBars[barKey])
                UpdateBarDimming(barKey)
            end)

            pill:SetScript("OnEnter", function(self)
                local barLabel = BAR_LABELS[barKey] or barKey
                local state = dimmedBars[barKey] and "dimmed (click to show)" or "visible (click to dim)"
                EllesmereUI.ShowWidgetTooltip(self,
                    barLabel .. " \226\128\148 " .. state .. "\n\n"
                    .. "Toggle bars to focus on the ones you want to rebind.",
                    { anchor = "below" })
            end)
            pill:SetScript("OnLeave", function()
                EllesmereUI.HideWidgetTooltip()
            end)

            pills[#pills + 1] = pill
            totalWidth = totalWidth + 70 + 6
        end
    end

    totalWidth = totalWidth - 6
    local startX = -totalWidth / 2
    for i, pill in ipairs(pills) do
        pill:SetPoint("LEFT", pillContainer, "CENTER", startX + (i - 1) * 76, 0)
    end
    pillContainer:SetSize(totalWidth, 28)

    filterPills = pills
end

local function DestroyFilterPills()
    if pillContainer then
        pillContainer:Hide()
        pillContainer:SetParent(nil)
        pillContainer = nil
    end
    wipe(filterPills)
    wipe(dimmedBars)
end

--------------------------------------------------------------------------------
--  Button Overlays
--------------------------------------------------------------------------------

local function GetBindingCommand(barKey, buttonIndex)
    local prefix = BINDING_MAP[barKey]
    if not prefix then return nil end
    return prefix .. buttonIndex
end

local function GetKeybindText(barKey, buttonIndex)
    local cmd = GetBindingCommand(barKey, buttonIndex)
    if not cmd then return "" end
    local key1 = GetBindingKey(cmd)
    if key1 then
        key1 = key1:gsub("SHIFT%-", "S-")
        key1 = key1:gsub("CTRL%-", "C-")
        key1 = key1:gsub("ALT%-", "A-")
        return key1
    end
    return ""
end

--------------------------------------------------------------------------------
--  Keybind Application
--------------------------------------------------------------------------------

local function RefreshOverlayText(ov)
    local txt = GetKeybindText(ov._barKey, ov._buttonIndex)
    ov._keyText:SetText(txt)
    if ov._dash then
        ov._dash:SetShown(txt == "")
    end
end

local function ClearPendingConflict(ov)
    if pendingConflict and pendingConflict.overlay == ov then
        pendingConflict = nil
    end
    -- Reset tooltip to default
    if ov and ov._ttText then
        ov._ttText:SetText("Press a key...")
        ov._ttText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        ov._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
    end
end

local function FlashFeedback(ov, text, r, g, b)
    -- Show feedback text
    ov._ttText:SetText(text)
    ov._ttText:SetTextColor(r, g, b, 1)
    -- Flash border bright
    ov._border:SetColor(r, g, b, 1)
    ov._bg:SetColorTexture(r, g, b, 0.20)
    -- Fade back after delay
    C_Timer.After(0.8, function()
        if ov and ov._ttText then
            if hoveredOverlay == ov then
                ov._ttText:SetText("Press a key...")
                ov._ttText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
                ov._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
                ov._bg:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.12)
            else
                ov._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.3)
                ov._bg:SetColorTexture(0.05, 0.07, 0.09, 0.55)
            end
        end
    end)
end

local function DoBindKey(ov, keyCombo)
    local cmd = GetBindingCommand(ov._barKey, ov._buttonIndex)
    if not cmd then return end
    SetBinding(keyCombo, nil)
    SetBinding(keyCombo, cmd)
    SaveBindings(2)
    -- Refresh all overlays
    for _, other in ipairs(buttonOverlays) do
        RefreshOverlayText(other)
    end
    -- Shorten the display of the key for feedback
    local shortKey = keyCombo:gsub("SHIFT%-", "S-"):gsub("CTRL%-", "C-"):gsub("ALT%-", "A-")
    FlashFeedback(ov, shortKey .. "  Bound!", 0.2, 0.9, 0.4)
end

local function ApplyKeybind(ov, keyCombo)
    local cmd = GetBindingCommand(ov._barKey, ov._buttonIndex)
    if not cmd then return end

    -- If we have a pending conflict for THIS overlay with THIS key, confirm it
    if pendingConflict and pendingConflict.overlay == ov and pendingConflict.keyCombo == keyCombo then
        pendingConflict = nil
        DoBindKey(ov, keyCombo)
        return
    end

    -- Check for conflict
    local existingAction = GetBindingAction(keyCombo)
    if existingAction and existingAction ~= "" and existingAction ~= cmd then
        -- Show warning inline on the tooltip — press same key again to confirm
        pendingConflict = { overlay = ov, keyCombo = keyCombo, existingAction = existingAction }
        ov._ttText:SetText(keyCombo .. " = " .. existingAction .. "\nPress again to override")
        ov._ttText:SetTextColor(WARN_R, WARN_G, WARN_B, 1)
        ov._border:SetColor(WARN_R, WARN_G, WARN_B, 0.8)
        -- Auto-clear after 3 seconds if they don't confirm
        C_Timer.After(3, function()
            if pendingConflict and pendingConflict.overlay == ov and pendingConflict.keyCombo == keyCombo then
                ClearPendingConflict(ov)
            end
        end)
        return
    end

    -- No conflict — bind directly
    DoBindKey(ov, keyCombo)
end

local function ClearKeybind(ov)
    local cmd = GetBindingCommand(ov._barKey, ov._buttonIndex)
    if not cmd then return end
    -- Clear ALL bindings for this command (a button can have multiple keys)
    local key1, key2 = GetBindingKey(cmd)
    local cleared = false
    if key1 then
        SetBinding(key1, nil)
        cleared = true
    end
    if key2 then
        SetBinding(key2, nil)
        cleared = true
    end
    if cleared then
        SaveBindings(2)
        RefreshOverlayText(ov)
        FlashFeedback(ov, "Cleared!", 1, 0.35, 0.35)
    end
end

--------------------------------------------------------------------------------
--  Button Overlay Creation
--------------------------------------------------------------------------------

local function CreateButtonOverlay(btn, barKey, buttonIndex)
    local ov = CreateFrame("Frame", nil, keybindFrame)
    ov:SetFrameLevel(keybindFrame:GetFrameLevel() + 20)
    ov:SetSize(btn:GetWidth(), btn:GetHeight())
    ov:SetPoint("CENTER", btn, "CENTER", 0, 0)
    ov:EnableMouse(true)
    ov._barKey = barKey
    ov._buttonIndex = buttonIndex
    ov._actionBtn = btn

    local bg = ov:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.07, 0.09, 0.55)
    ov._bg = bg

    ov._border = EllesmereUI.MakeBorder(ov, ACCENT_R, ACCENT_G, ACCENT_B, 0.3)

    local keyText = ov:CreateFontString(nil, "OVERLAY")
    keyText:SetFont(FONT_PATH, 10, "OUTLINE")
    keyText:SetPoint("TOPRIGHT", ov, "TOPRIGHT", -2, -2)
    keyText:SetTextColor(1, 1, 1, 0.9)
    ov._keyText = keyText

    -- Dash placeholder (always created, shown when unbound)
    local dash = ov:CreateFontString(nil, "OVERLAY")
    dash:SetFont(FONT_PATH, 10, "")
    dash:SetPoint("CENTER")
    dash:SetTextColor(1, 1, 1, 0.2)
    dash:SetText("\226\128\148")
    ov._dash = dash

    local currentBind = GetKeybindText(barKey, buttonIndex)
    if currentBind ~= "" then
        keyText:SetText(currentBind)
        dash:Hide()
    else
        keyText:SetText("")
        dash:Show()
    end

    local tooltip = CreateFrame("Frame", nil, ov)
    tooltip:SetSize(200, 40)
    tooltip:SetPoint("TOP", ov, "BOTTOM", 0, -4)
    tooltip:SetFrameLevel(ov:GetFrameLevel() + 5)
    tooltip:Hide()

    local ttBg = tooltip:CreateTexture(nil, "BACKGROUND")
    ttBg:SetAllPoints()
    ttBg:SetColorTexture(0.031, 0.047, 0.063, 0.95)
    EllesmereUI.MakeBorder(tooltip, ACCENT_R, ACCENT_G, ACCENT_B, 0.5)

    local ttText = tooltip:CreateFontString(nil, "OVERLAY")
    ttText:SetFont(FONT_PATH, 10, "")
    ttText:SetPoint("CENTER")
    ttText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    ttText:SetText("Press a key...")
    ov._tooltip = tooltip
    ov._ttText = ttText

    -- Register all mouse buttons for binding
    ov:RegisterForDrag("LeftButton", "RightButton", "MiddleButton", "Button4", "Button5")
    ov:SetScript("OnMouseDown", function(self, button)
        if not hoveredOverlay or hoveredOverlay ~= self then return end
        -- Map WoW button names to binding format
        local btnMap = {
            LeftButton = "BUTTON1",
            RightButton = "BUTTON2",
            MiddleButton = "BUTTON3",
            Button4 = "BUTTON4",
            Button5 = "BUTTON5",
        }
        local bindBtn = btnMap[button]
        if not bindBtn then return end

        -- Build combo with modifiers
        local combo = ""
        if IsShiftKeyDown() then combo = combo .. "SHIFT-" end
        if IsControlKeyDown() then combo = combo .. "CTRL-" end
        if IsAltKeyDown() then combo = combo .. "ALT-" end
        combo = combo .. bindBtn

        DebugLog("MOUSE=" .. combo .. " bar=" .. self._barKey .. " idx=" .. self._buttonIndex)
        ApplyKeybind(self, combo)
    end)

    ov:SetScript("OnEnter", function(self)
        if dimmedBars[self._barKey] then return end
        hoveredOverlay = self
        self._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.8)
        self._bg:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.12)
        self._tooltip:Show()
        DebugLog("HOVER bar=" .. self._barKey .. " idx=" .. self._buttonIndex .. " cmd=" .. (GetBindingCommand(self._barKey, self._buttonIndex) or "nil") .. " btnName=" .. (self._actionBtn:GetName() or "anon") .. " btnID=" .. (self._actionBtn:GetID() or "?"))
    end)

    ov:SetScript("OnLeave", function(self)
        if hoveredOverlay == self then
            hoveredOverlay = nil
        end
        ClearPendingConflict(self)
        self._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.3)
        self._bg:SetColorTexture(0.05, 0.07, 0.09, 0.55)
        self._tooltip:Hide()
        self._ttText:SetText("Press a key...")
        self._ttText:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    end)

    return ov
end

local function CreateAllButtonOverlays()
    local EAB = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
    if not EAB or not EAB._barButtons then return end

    for _, barKey in ipairs(BAR_ORDER) do
        local buttons = EAB._barButtons[barKey]
        local barFrame = EAB._barFrames and EAB._barFrames[barKey]
        if buttons and barFrame and barFrame:IsShown() then
            for i, btn in ipairs(buttons) do
                if btn and btn:IsShown() then
                    local ov = CreateButtonOverlay(btn, barKey, i)
                    buttonOverlays[#buttonOverlays + 1] = ov
                    DebugLog("OVERLAY bar=" .. barKey .. " idx=" .. i .. " btn=" .. (btn:GetName() or "anon") .. " btnID=" .. (btn:GetID() or "?") .. " cmd=" .. (GetBindingCommand(barKey, i) or "nil"))
                end
            end
        end
    end
end

local function DestroyAllButtonOverlays()
    for _, ov in ipairs(buttonOverlays) do
        ov:Hide()
        ov:SetParent(nil)
    end
    wipe(buttonOverlays)
    hoveredOverlay = nil
end

--------------------------------------------------------------------------------
--  Combat auto-exit
--------------------------------------------------------------------------------
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:SetScript("OnEvent", function()
    if isActive then
        CloseKeybindMode()
        print("|cffff6060[EllesmereUI]|r Keybind Mode closed \226\128\148 entering combat.")
    end
end)

--------------------------------------------------------------------------------
--  Login: restore keybind profile for current spec
--------------------------------------------------------------------------------
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function()
    C_Timer.After(1, function()
        local profileName, specID = EllesmereUI:GetCurrentSpecKeybindProfile()
        if profileName and EllesmereUIDB.keybindProfiles
           and EllesmereUIDB.keybindProfiles[profileName] then
            EllesmereUI:RestoreKeybinds(profileName)
        elseif specID then
            local specIdx = GetSpecialization and GetSpecialization()
            if specIdx and specIdx > 0 then
                local _, specName = GetSpecializationInfo(specIdx)
                if specName then
                    EllesmereUI:SnapshotKeybinds(specName)
                    EllesmereUI:AssignKeybindProfileToSpec(specName, specID)
                end
            end
        end
    end)
end)

--------------------------------------------------------------------------------
--  Open / Close
--------------------------------------------------------------------------------
OpenKeybindMode = function()
    if isActive then return end
    if InCombatLockdown() then
        print("|cffff6060[EllesmereUI]|r Cannot enter Keybind Mode during combat.")
        return
    end

    RefreshAccent()
    isActive = true

    if EllesmereUI.IsShown and EllesmereUI:IsShown() then
        EllesmereUI:Toggle()
    end

    CreateOverlayFrame()
    CreateHUD()
    CreateFilterPills()
    CreateAllButtonOverlays()

    -- Register with WoW's ESC-to-close system
    tinsert(UISpecialFrames, "EllesmereKeybindMode")

    -- Enable mouse to block clicks from reaching the game world
    keybindFrame:EnableMouse(true)

    -- Single keyboard handler on the main frame — routes to hoveredOverlay
    keybindFrame:EnableKeyboard(true)
    keybindFrame:SetScript("OnKeyDown", function(self, key)
        -- Ignore lone modifier keys
        if key == "LSHIFT" or key == "RSHIFT"
        or key == "LCTRL" or key == "RCTRL"
        or key == "LALT" or key == "RALT" then
            self:SetPropagateKeyboardInput(true)
            return
        end

        -- ESC: if hovering, unbind; if not, exit
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            if hoveredOverlay then
                DebugLog("ESC unbind bar=" .. hoveredOverlay._barKey .. " idx=" .. hoveredOverlay._buttonIndex)
                ClearKeybind(hoveredOverlay)
            else
                CloseKeybindMode()
            end
            return
        end

        -- No overlay hovered — let key pass through to game
        if not hoveredOverlay then
            self:SetPropagateKeyboardInput(true)
            return
        end

        -- Consume the key
        self:SetPropagateKeyboardInput(false)

        -- Build key combo
        local combo = ""
        if IsShiftKeyDown() then combo = combo .. "SHIFT-" end
        if IsControlKeyDown() then combo = combo .. "CTRL-" end
        if IsAltKeyDown() then combo = combo .. "ALT-" end
        combo = combo .. key

        DebugLog("KEY=" .. combo .. " bar=" .. hoveredOverlay._barKey .. " idx=" .. hoveredOverlay._buttonIndex .. " cmd=" .. (GetBindingCommand(hoveredOverlay._barKey, hoveredOverlay._buttonIndex) or "nil"))
        ApplyKeybind(hoveredOverlay, combo)
    end)

    FadeIn()
end

CloseKeybindMode = function()
    if not isActive then return end
    isActive = false
    pendingConflict = nil

    -- Auto-save keybinds to current spec's profile
    local profileName, specID = EllesmereUI:GetCurrentSpecKeybindProfile()
    if profileName then
        EllesmereUI:SnapshotKeybinds(profileName)
    elseif specID then
        local _, specName = GetSpecializationInfo(GetSpecialization())
        if specName then
            EllesmereUI:SnapshotKeybinds(specName)
            EllesmereUI:AssignKeybindProfileToSpec(specName, specID)
        end
    end

    -- Remove from UISpecialFrames
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "EllesmereKeybindMode" then
            table.remove(UISpecialFrames, i)
        end
    end

    if keybindFrame and keybindFrame:IsShown() then
        FadeOut(function()
            DestroyAllButtonOverlays()
            DestroyFilterPills()
            DestroyHUD()
            DestroyOverlayFrame()
        end)
    else
        -- Frame already hidden by ESC/UISpecialFrames — just clean up
        DestroyAllButtonOverlays()
        DestroyFilterPills()
        DestroyHUD()
        DestroyOverlayFrame()
    end
end
