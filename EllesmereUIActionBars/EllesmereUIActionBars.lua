-------------------------------------------------------------------------------
--  EllesmereUIActionBars.lua  Custom Action Bars (full rewrite)
--
--  Creates its own secure action bar frames and buttons instead of hooking
--  Blizzard's Edit Mode bars.  Eliminates taint issues and hacky workarounds.
--
--  Button reuse strategy (matches Blizzard):
--    Slots  1- 72 reuse Blizzard ActionButton1-12, MultiBar*Button1-12
--    Slots 73-144 create new buttons via ActionBarButtonTemplate
--    Slots 145-180 reuse Blizzard MultiBar5-7 Button1-12
--
--  Paging via RegisterStateDriver on secure header frames.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EAB = EllesmereUI.Lite.NewAddon(ADDON_NAME)
ns.EAB = EAB

local PP = EllesmereUI.PP

-------------------------------------------------------------------------------
--  Upvalues
-------------------------------------------------------------------------------
local _G = _G
local ipairs, pairs, type, pcall = ipairs, pairs, type, pcall
local abs, ceil, floor, min, max = math.abs, math.ceil, math.floor, math.min, math.max
local wipe, tinsert = wipe, table.insert
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After
local RegisterStateDriver = RegisterStateDriver
local UnregisterStateDriver = UnregisterStateDriver
local RegisterAttributeDriver = RegisterAttributeDriver
local UnregisterAttributeDriver = UnregisterAttributeDriver
local GetBindingKey = GetBindingKey

-------------------------------------------------------------------------------
--  Bar configuration
-------------------------------------------------------------------------------
local BAR_CONFIG = {
    { key = "MainBar",   label = "Action Bar 1 (Main)", barID = 1,  count = 12, blizzBtnPrefix = "ActionButton",              blizzFrame = "MainMenuBar" },
    { key = "Bar2",      label = "Action Bar 2",        barID = 2,  count = 12, blizzBtnPrefix = "MultiBarBottomLeftButton",   blizzFrame = "MultiBarBottomLeft" },
    { key = "Bar3",      label = "Action Bar 3",        barID = 3,  count = 12, blizzBtnPrefix = "MultiBarBottomRightButton",  blizzFrame = "MultiBarBottomRight" },
    { key = "Bar4",      label = "Action Bar 4",        barID = 4,  count = 12, blizzBtnPrefix = "MultiBarRightButton",        blizzFrame = "MultiBarRight" },
    { key = "Bar5",      label = "Action Bar 5",        barID = 5,  count = 12, blizzBtnPrefix = "MultiBarLeftButton",         blizzFrame = "MultiBarLeft" },
    { key = "Bar6",      label = "Action Bar 6",        barID = 6,  count = 12, blizzBtnPrefix = "MultiBar5Button",          blizzFrame = "MultiBar5" },
    { key = "Bar7",      label = "Action Bar 7",        barID = 7,  count = 12, blizzBtnPrefix = "MultiBar6Button",          blizzFrame = "MultiBar6" },
    { key = "Bar8",      label = "Action Bar 8",        barID = 8,  count = 12, blizzBtnPrefix = "MultiBar7Button",          blizzFrame = "MultiBar7" },
    { key = "StanceBar", label = "Stance Bar",          barID = 0,  count = 10, blizzBtnPrefix = "StanceButton",               blizzFrame = "StanceBar", isStance = true },
    { key = "PetBar",    label = "Pet Bar",             barID = 0,  count = 10, blizzBtnPrefix = "PetActionButton",            blizzFrame = "PetActionBar", isPetBar = true },
}

-- Backward-compat aliases for the options file (which references the old field names)
for _, info in ipairs(BAR_CONFIG) do
    info.buttonPrefix = info.blizzBtnPrefix
    info.frameName    = info.blizzFrame
    info.fallbackFrame = nil  -- no longer needed; we own the bar frames
end

local EXTRA_BARS = {
    { key = "MicroBar", label = "Micro Menu Bar", frameName = "MicroMenuContainer", hoverFrame = "MicroMenu", visibilityOnly = true },
    { key = "BagBar",   label = "Bag Bar",        frameName = "BagsBar", visibilityOnly = true },
    { key = "XPBar",    label = "XP Bar",         visibilityOnly = true, isDataBar = true },
    { key = "RepBar",   label = "Reputation Bar",  visibilityOnly = true, isDataBar = true },
    { key = "ExtraActionButton", label = "Extra Action Button", visibilityOnly = true, isBlizzardMovable = true },
    { key = "EncounterBar",      label = "Encounter Bar",         visibilityOnly = true, isBlizzardMovable = true },
}

local ALL_BARS = {}
for _, info in ipairs(BAR_CONFIG) do ALL_BARS[#ALL_BARS + 1] = info end
for _, info in ipairs(EXTRA_BARS) do ALL_BARS[#ALL_BARS + 1] = info end

local BAR_LOOKUP = {}
for _, info in ipairs(BAR_CONFIG) do BAR_LOOKUP[info.key] = info end

local BAR_DROPDOWN_VALUES = {}
local BAR_DROPDOWN_ORDER = {}
do
    local _DROPDOWN_EXCLUDE = { ExtraActionButton = true, EncounterBar = true }
    for _, info in ipairs(ALL_BARS) do
        if not _DROPDOWN_EXCLUDE[info.key] then
            BAR_DROPDOWN_VALUES[info.key] = info.label
            BAR_DROPDOWN_ORDER[#BAR_DROPDOWN_ORDER + 1] = info.key
        end
    end
end

local VISIBILITY_ONLY = {}
for _, info in ipairs(EXTRA_BARS) do
    VISIBILITY_ONLY[info.key] = true
end

local DATA_BAR = {}
for _, info in ipairs(EXTRA_BARS) do
    if info.isDataBar then DATA_BAR[info.key] = true end
end

ns.BAR_DROPDOWN_VALUES = BAR_DROPDOWN_VALUES
ns.BAR_DROPDOWN_ORDER  = BAR_DROPDOWN_ORDER
ns.VISIBILITY_ONLY     = VISIBILITY_ONLY
ns.DATA_BAR            = DATA_BAR
ns.BAR_LOOKUP          = BAR_LOOKUP
ns.ALL_BARS            = ALL_BARS
ns.EXTRA_BARS          = EXTRA_BARS

-------------------------------------------------------------------------------
--  Media paths
-------------------------------------------------------------------------------
local MEDIA_DIR = "Interface\\AddOns\\EllesmereUIActionBars\\Media\\"
local FONT_PATH = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("actionBars"))
    or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function GetEABOutline()
    return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag()) or "OUTLINE"
end
local function GetEABUseShadow()
    return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow()
end
local HIGHLIGHT_TEXTURES = {
    MEDIA_DIR .. "highlight-2.png",
    MEDIA_DIR .. "highlight-3.png",
    MEDIA_DIR .. "highlight-4.png",
}
ns.HIGHLIGHT_TEXTURES = HIGHLIGHT_TEXTURES

local SHAPE_MEDIA = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\"
local SHAPE_MASKS = {
    circle   = SHAPE_MEDIA .. "circle_mask.tga",
    csquare  = SHAPE_MEDIA .. "csquare_mask.tga",
    diamond  = SHAPE_MEDIA .. "diamond_mask.tga",
    hexagon  = SHAPE_MEDIA .. "hexagon_mask.tga",
    portrait = SHAPE_MEDIA .. "portrait_mask.tga",
    shield   = SHAPE_MEDIA .. "shield_mask.tga",
    square   = SHAPE_MEDIA .. "square_mask.tga",
}
local SHAPE_BORDERS = {
    circle   = SHAPE_MEDIA .. "circle_border.tga",
    csquare  = SHAPE_MEDIA .. "csquare_border.tga",
    diamond  = SHAPE_MEDIA .. "diamond_border.tga",
    hexagon  = SHAPE_MEDIA .. "hexagon_border.tga",
    portrait = SHAPE_MEDIA .. "portrait_border.tga",
    shield   = SHAPE_MEDIA .. "shield_border.tga",
    square   = SHAPE_MEDIA .. "square_border.tga",
}
local SHAPE_INSETS = {
    circle = 17, csquare = 17, diamond = 14,
    hexagon = 17, portrait = 17, shield = 13, square = 17,
}
local SHAPE_ZOOM_DEFAULTS = {
    none = 5.5, cropped = 2, square = 6.0, circle = 6.0, csquare = 6.0,
    diamond = 6.0, hexagon = 6.0, portrait = 6.0, shield = 6.0,
}
ns.SHAPE_ZOOM_DEFAULTS = SHAPE_ZOOM_DEFAULTS
ns.SHAPE_MASKS   = SHAPE_MASKS
ns.SHAPE_BORDERS = SHAPE_BORDERS

local SHAPE_BTN_EXPAND  = 10
local SHAPE_ICON_EXPAND = 7
ns.SHAPE_BTN_EXPAND  = SHAPE_BTN_EXPAND
ns.SHAPE_ICON_EXPAND = SHAPE_ICON_EXPAND

local SHAPE_ICON_EXPAND_OFFSETS = {
    circle = 2, csquare = 4, diamond = 2, hexagon = 4,
    portrait = 2, shield = 2, square = 4,
}

-- Per-shape edge scale so the circular edge path stays inside the mask.
local SHAPE_EDGE_SCALES = {
    circle = 0.75, csquare = 0.75, diamond = 0.70,
    hexagon = 0.65, portrait = 0.70, shield = 0.65, square = 0.75,
}
local SHAPE_KEYBIND_OFFSETS = {
    none = { x=0, y=0 }, cropped = { x=0, y=0 }, square = { x=0, y=0 },
    circle = { x=0, y=0 }, csquare = { x=0, y=0 }, diamond = { x=0, y=0 },
    hexagon = { x=0, y=0 }, portrait = { x=0, y=0 }, shield = { x=0, y=0 },
}
local SHAPE_COUNT_OFFSETS = {
    none = { x=0, y=0 }, cropped = { x=0, y=0 }, square = { x=0, y=0 },
    circle = { x=0, y=0 }, csquare = { x=0, y=0 }, diamond = { x=0, y=0 },
    hexagon = { x=0, y=0 }, portrait = { x=0, y=0 }, shield = { x=0, y=0 },
}

-- Border thickness mapping
ns.BORDER_THICKNESS = {
    none   = { regular = 0, shape = 0 },
    thin   = { regular = 1, shape = 0 },
    normal = { regular = 2, shape = 0 },
    heavy  = { regular = 3, shape = 0 },
    strong = { regular = 4, shape = 7 },
}
ns.BORDER_THICKNESS_ORDER  = { "none", "thin", "normal", "heavy", "strong" }
ns.BORDER_THICKNESS_LABELS = { none="None", thin="Thin", normal="Normal", heavy="Heavy", strong="Strong" }
ns.BORDER_THICKNESS_DEFAULT_REGULAR = "thin"
ns.BORDER_THICKNESS_DEFAULT_SHAPE   = "strong"

-------------------------------------------------------------------------------
--  Defaults
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        squareIcons = true,
        iconZoom = 5.5,
        selectedBar = "MainBar",
        font = FONT_PATH,
        cooldownEdgeSize = 2.1,
        cooldownEdgeColor = { r = 0.973, g = 0.839, b = 0.604, a = 1 },
        cooldownEdgeUseClassColor = false,
        pushedTextureType = 2,
        pushedUseClassColor = false,
        pushedCustomColor = { r = 0.973, g = 0.839, b = 0.604, a = 1 },
        pushedBorderSize = 4,
        highlightTextureType = 2,
        highlightUseClassColor = false,
        highlightCustomColor = { r = 0.973, g = 0.839, b = 0.604, a = 1 },
        highlightBorderSize = 4,
        procGlowType = 1,
        procGlowColor = { r = 1, g = 0.776, b = 0.376 },
        procGlowUseClassColor = false,
        procGlowScale = 1.0,
        procGlowEnabled = false,
        hideCastingAnimations = true,
        barPositions = {},
        bars = {},
    },
}

for _, info in ipairs(BAR_CONFIG) do
    defaults.profile.bars[info.key] = {
        enabled = true,
        borderEnabled = true,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        borderSize = 1,
        borderClassColor = false,
        borderThickness = "thin",
        buttonPadding = 2,
        barScale = 1.0,
        mouseoverEnabled = false,
        mouseoverAlpha = 1,
        combatShowEnabled = false,
        combatHideEnabled = false,
        housingHideEnabled = false,
        barVisibility = "always",
        visHideHousing = false,
        visOnlyInstances = false,
        visHideMounted = false,
        visHideNoTarget = false,
        visHideNoEnemy = false,
        hideKeybind = false,
        keybindFontSize = 12,
        keybindFontColor = { r = 1, g = 1, b = 1 },
        countFontSize = 12,
        countFontColor = { r = 1, g = 1, b = 1 },
        alwaysHidden = false,
        mouseoverSpeed = 0.15,
        clickThrough = false,
        overrideNumIcons = nil,
        overrideNumRows  = nil,
        growDirection    = "up",
        alwaysShowButtons = true,
        bgEnabled = false,
        bgColor = { r = 0, g = 0, b = 0, a = 0.5 },
        outOfRangeColoring = false,
        outOfRangeColor = { r = 0.8, g = 0.1, b = 0.1 },
        buttonShape = "none",
        shapeBorderEnabled = true,
        shapeBorderColor = { r = 0, g = 0, b = 0, a = 1 },
        shapeBorderSize = 7,
        shapeBorderClassColor = nil,
        iconZoom = nil,
        keybindOffsetX = 0,
        keybindOffsetY = 0,
        countOffsetX = 0,
        countOffsetY = 0,
        orientation = "horizontal",
        numIcons = 12,
        numRows = 1,
    }
end

for _, info in ipairs(EXTRA_BARS) do
    defaults.profile.bars[info.key] = {
        mouseoverEnabled = false,
        mouseoverAlpha = 1,
        combatShowEnabled = false,
        combatHideEnabled = false,
        housingHideEnabled = false,
        alwaysHidden = false,
        mouseoverSpeed = 0.15,
        clickThrough = false,
    }
    if info.isDataBar then
        local d = defaults.profile.bars[info.key]
        d.width = 400
        d.height = 18
        d.orientation = "HORIZONTAL"
        d.clickThrough = true  -- default on for data bars
    end
end

-- Blizzard data bar override (let Blizzard control XP + Rep via Edit Mode)
defaults.profile.useBlizzardDataBars = false

ns.defaults = defaults

-------------------------------------------------------------------------------
--  Utility helpers
-------------------------------------------------------------------------------
local function SafeEnableMouse(frame, enable)
    if not frame then return end
    if frame.IsProtected and frame:IsProtected() and InCombatLockdown() then return end
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(enable)
        frame:SetMouseMotionEnabled(enable)
    else
        frame:EnableMouse(enable)
    end
end

-- Like SafeEnableMouse but only enables mouse motion (OnEnter/OnLeave),
-- keeping click-through so clicks pass to frames behind.
local function SafeEnableMouseMotionOnly(frame, enable)
    if not frame then return end
    if frame.IsProtected and frame:IsProtected() and InCombatLockdown() then return end
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
        frame:SetMouseMotionEnabled(enable)
    else
        frame:EnableMouse(enable)
    end
end

local fadeAnims = {}

-- Shared OnUpdate frame for fading Blizzard-owned frames (extra bars).
-- Using CreateAnimationGroup on Blizzard frames can spread taint, so we
-- drive alpha changes manually via a single update frame instead.
local _extraFadeQueue = {}
local _extraFadeFrame = CreateFrame("Frame")

local function _ExtraFadeOnUpdate(_, elapsed)
    local anyActive = false
    for frame, info in pairs(_extraFadeQueue) do
        info.elapsed = info.elapsed + elapsed
        local t = info.elapsed / info.duration
        if t >= 1 then
            frame:SetAlpha(info.toAlpha)
            _extraFadeQueue[frame] = nil
        else
            -- Smooth in/out easing
            local e = t < 0.5 and (2 * t * t) or (1 - (-2 * t + 2)^2 / 2)
            frame:SetAlpha(info.fromAlpha + (info.toAlpha - info.fromAlpha) * e)
            anyActive = true
        end
    end
    if not anyActive then
        _extraFadeFrame:SetScript("OnUpdate", nil)
    end
end
_extraFadeFrame:SetScript("OnUpdate", nil)  -- start idle

-- Drag visibility state (file-scope so ApplyAll can reset strata on spec change)
local _dragVisible = false
local _dragStrataCache = {}

-- Set of frames we own (bar frames, not Blizzard frames).
-- Blizzard-owned frames use the _extraFadeQueue path to avoid taint.
local _ownedFrames = {}

local function FadeTo(frame, toAlpha, duration)
    duration = duration or 0.1
    if abs(frame:GetAlpha() - toAlpha) < 0.01 then
        frame:SetAlpha(toAlpha)
        return
    end

    -- Use OnUpdate path for Blizzard-owned frames to avoid taint from
    -- CreateAnimationGroup on frames we don't own.
    if not _ownedFrames[frame] then
        local existing = _extraFadeQueue[frame]
        if existing and existing.toAlpha == toAlpha then return end
        _extraFadeQueue[frame] = {
            fromAlpha = frame:GetAlpha(),
            toAlpha   = toAlpha,
            duration  = duration,
            elapsed   = 0,
        }
        _extraFadeFrame:SetScript("OnUpdate", _ExtraFadeOnUpdate)
        return
    end

    local data = fadeAnims[frame]
    if not data then
        local group = frame:CreateAnimationGroup()
        group:SetLooping("NONE")
        local anim = group:CreateAnimation("Alpha")
        anim:SetSmoothing("IN_OUT")
        anim:SetOrder(0)
        data = { group = group, anim = anim }
        fadeAnims[frame] = data
        group:SetScript("OnFinished", function(self)
            if self._toAlpha then
                self:GetParent():SetAlpha(self._toAlpha)
                self._toAlpha = nil
            end
        end)
    end
    local group, anim = data.group, data.anim
    -- Already animating toward the same target -- don't restart
    if group:IsPlaying() and group._toAlpha == toAlpha then return end
    if group:IsPlaying() then group:Stop() end
    group._toAlpha = toAlpha
    anim:SetFromAlpha(frame:GetAlpha())
    anim:SetToAlpha(toAlpha)
    anim:SetDuration(duration)
    anim:SetStartDelay(0)
    group:Restart()
end

local function StopFade(frame)
    -- Clear from OnUpdate queue (Blizzard-owned frames)
    _extraFadeQueue[frame] = nil
    -- Clear animation group (owned frames)
    local data = fadeAnims[frame]
    if data and data.group and data.group:IsPlaying() then
        data.group:Stop()
        data.group._toAlpha = nil
    end
end

-- Resolve borderThickness dropdown to actual pixel values
local function ResolveBorderThickness(s)
    local thickness = s.borderThickness or "thin"
    local entry = ns.BORDER_THICKNESS[thickness]
    if not entry then entry = ns.BORDER_THICKNESS["thin"] end
    local shape = s.buttonShape or "none"
    if shape ~= "none" and shape ~= "cropped" then
        if thickness == "thin" and s.shapeBorderSize and s.shapeBorderSize ~= entry.shape then
            return s.shapeBorderSize
        end
        return entry.shape
    else
        return entry.regular
    end
end
ns.ResolveBorderThickness = ResolveBorderThickness

-- Condense keybind text (CTRL-2 C2, Mouse Button 4 M4, etc.)
local function FormatHotkeyText(text)
    if not text or text == "" then return "" end
    text = text:gsub("CTRL%-", "C")
    text = text:gsub("ALT%-", "A")
    text = text:gsub("SHIFT%-", "S")
    text = text:gsub("Mouse Button ", "M")
    text = text:gsub("MOUSEWHEELUP", "MwU")
    text = text:gsub("MOUSEWHEELDOWN", "MwD")
    text = text:gsub("NUMPAD", "N")
    text = text:gsub("NUMPADDECIMAL", "N.")
    text = text:gsub("NUMPADPLUS", "N+")
    text = text:gsub("NUMPADMINUS", "N-")
    text = text:gsub("NUMPADMULTIPLY", "N*")
    text = text:gsub("NUMPADDIVIDE", "N/")
    text = text:gsub("BUTTON", "M")
    return text
end

-- Check if a button has an action assigned
local function ButtonHasAction(btn, prefix)
    if not btn then return false end
    if btn.HasAction then
        local ok, has = pcall(btn.HasAction, btn)
        if ok then return has end
    end
    return btn.icon and btn.icon:IsShown() and btn.icon:GetTexture() ~= nil
end
ns.ButtonHasAction = ButtonHasAction

-------------------------------------------------------------------------------
--  Blizzard Bar Hider
--  Hides default Blizzard action bars by reparenting to a hidden frame.
--  Similar to the standard blizzardHider pattern.
-------------------------------------------------------------------------------
local hiddenParent = CreateFrame("Frame", "EABHiddenParent", UIParent)
hiddenParent:Hide()

local BLIZZARD_BARS_TO_HIDE = {
    "MainActionBar",
    "MainMenuBar",
    "MultiBarBottomLeft",
    "MultiBarBottomRight",
    "MultiBarRight",
    "MultiBarLeft",
    "MultiBar5",
    "MultiBar6",
    "MultiBar7",
    "StanceBar",
    "PetActionBar",
}

-------------------------------------------------------------------------------
--  Secure Setup Handler
--  Performs protected frame operations (SetParent, SetPoint, SetSize, Show/Hide)
--  from within a restricted secure snippet, allowing them to run even during
--  combat lockdown. Normal Lua cannot call these on protected frames in combat,
--  but a SecureHandlerAttributeTemplate snippet can.
--
--  Usage:
--   1. Call SecureSetupHandler_PrepareRefs() once after bar frames are created.
--   2. Call SecureSetupHandler_EncodeLayout() to write button layout as attributes.
--   3. Call SecureSetupHandler_Execute() to trigger the snippet.
-------------------------------------------------------------------------------
local _secureHandler = CreateFrame("Frame", "EABSecureSetupHandler", UIParent, "SecureHandlerAttributeTemplate")

-- The secure snippet reads encoded button data and applies SetParent + layout.
-- Attribute format per button slot:
--   "btn-N" = "barref|x|y|w|h|show"  (show = "1" or "0")
-- Bar frame refs are registered as "bar-{key}".
-- Hidden parent ref is registered as "hiddenParent".
-- UIParent ref is registered as "uiParent".
-- Blizzard bar refs are registered as "blizzbar-{name}".
-- Trigger: setting "do-setup" to any value runs the full setup.
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
                btnRef:SetParent(barRef)
                btnRef:ClearAllPoints()
                btnRef:SetPoint("TOPLEFT", barRef, "TOPLEFT", tonumber(x) or 0, tonumber(y) or 0)
                btnRef:SetWidth(tonumber(w) or 45)
                btnRef:SetHeight(tonumber(h) or 45)
                if barKey == "PetBar" then
                    -- PetActionButtons use their slot index as their frame ID
                    -- to know which pet ability to display. Must not be reset to 0.
                    local petIndex = tonumber(actionSlot) or 1
                    btnRef:SetID(petIndex)
                    btnRef:SetAttribute("action", nil)
                else
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

    -- Step 5: Set up MainBar paging attributes on buttons.
    -- _childupdate-offset can only be set from the restricted environment on
    -- protected frames, so we do it here rather than from normal Lua.
    -- For MainBar buttons, actionSlot encodes the button index (1-12).
    local mainOffset = self:GetAttribute("mainbar-offset") or 0
    for slot = 1, btnCount do
        local data = self:GetAttribute("layout-" .. slot)
        if data then
            local barKey, _, _, _, _, _, actionSlot = strsplit("|", data)
            if barKey == "MainBar" then
                local idx = tonumber(actionSlot) or 0
                if idx > 0 then
                    local btnRef = self:GetFrameRef("btn-" .. slot)
                    if btnRef then
                        btnRef:SetAttribute("index", idx)
                        btnRef:SetAttribute("_childupdate-offset", [[
                            local offset = message or 0
                            local id = self:GetAttribute("index") + offset
                            if self:GetAttribute("action") ~= id then
                                self:SetAttribute("action", id)
                            end
                        ]])
                        btnRef:SetAttribute("action", idx + mainOffset)
                    end
                end
            end
        end
    end

    -- Step 6: Native Blizzard keybinds -- no override bindings needed.
    -- Blizzard's C-level system routes key presses via MultiActionButtonDown/Up.
]=])

-- Register all Blizzard buttons and bar frames as refs on the secure handler.
-- Must be called after bar frames are created (after CreateBarFrame runs).
local _secureRefsReady = false
local function SecureSetupHandler_PrepareRefs()
    if _secureRefsReady then return end
    _secureRefsReady = true

    _secureHandler:SetFrameRef("uiParent", UIParent)
    _secureHandler:SetFrameRef("hiddenParent", hiddenParent)

    -- Register all Blizzard buttons
    local btnIdx = 0
    for _, info in ipairs(BAR_CONFIG) do
        if info.blizzBtnPrefix and not info.isStance and not info.isPetBar then
            for i = 1, info.count do
                local btn = _G[info.blizzBtnPrefix .. i]
                if btn then
                    btnIdx = btnIdx + 1
                    _secureHandler:SetFrameRef("btn-" .. btnIdx, btn)
                    -- Store mapping: blizzBtnPrefix+i -> slot index
                    btn._secureSlotIdx = btnIdx
                end
            end
        elseif info.isStance then
            for i = 1, info.count do
                local btn = _G["StanceButton" .. i]
                if btn then
                    btnIdx = btnIdx + 1
                    _secureHandler:SetFrameRef("btn-" .. btnIdx, btn)
                    btn._secureSlotIdx = btnIdx
                end
            end
        elseif info.isPetBar then
            for i = 1, info.count do
                local btn = _G["PetActionButton" .. i]
                if btn then
                    btnIdx = btnIdx + 1
                    _secureHandler:SetFrameRef("btn-" .. btnIdx, btn)
                    btn._secureSlotIdx = btnIdx
                end
            end
        end
    end
    _secureHandler:SetAttribute("btn-count", btnIdx)

    -- Register Blizzard bar frames to hide
    local blizzIdx = 0
    for _, name in ipairs(BLIZZARD_BARS_TO_HIDE) do
        local bar = _G[name]
        if bar then
            blizzIdx = blizzIdx + 1
            _secureHandler:SetFrameRef("blizzbar-" .. blizzIdx, bar)
        end
    end
    -- Also hide StatusTrackingBarManager if not using Blizzard data bars
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
    -- Encode button layout
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
    -- Pass current MainBar page offset so the snippet can set initial action slots
    local mainFrame = barFrames["MainBar"]
    local mainOffset = mainFrame and (mainFrame:GetAttribute("actionOffset") or 0) or 0
    _secureHandler:SetAttribute("mainbar-offset", mainOffset)
    -- Native Blizzard keybinds: no override bind data needed for combat reload.
    _secureHandler:SetAttribute("bind-count", 0)
    -- Trigger the snippet
    _secureHandler:SetAttribute("do-setup", GetTime())
end

local function HideBlizzardBars()
    -- First, extract all Blizzard buttons we want to reuse by reparenting
    -- them to UIParent temporarily. This must happen BEFORE we hide the
    -- parent bar frames, otherwise the buttons become invisible.
    for _, info in ipairs(BAR_CONFIG) do
        if info.blizzBtnPrefix then
            for i = 1, info.count do
                local btn = _G[info.blizzBtnPrefix .. i]
                if btn then
                    btn:SetParent(UIParent)
                end
            end
        end
    end

    -- Now hide the Blizzard bar frames
    for _, name in ipairs(BLIZZARD_BARS_TO_HIDE) do
        local bar = _G[name]
        if bar then
            bar:UnregisterAllEvents()
            bar:SetParent(hiddenParent)
            bar:Hide()
        end
    end
    -- Also hide the MainActionBar container and related frames
    if MainActionBarController then
        MainActionBarController:UnregisterAllEvents()
    end
    -- Hide status tracking bar manager (unless user wants Blizzard data bars)
    if not (EAB.db and EAB.db.profile.useBlizzardDataBars) then
        if StatusTrackingBarManager then
            StatusTrackingBarManager:UnregisterAllEvents()
            StatusTrackingBarManager:Hide()
        end
    end
    -- Hide the action bar page number
    if MainMenuBarPageNumber then MainMenuBarPageNumber:Hide() end
    -- Hide ActionBarParent normally; show it during full vehicle UI so
    -- Blizzard's vehicle bar can render.  Combat-safe via attribute driver.
    if ActionBarParent then
        RegisterAttributeDriver(ActionBarParent, "state-visibility",
            "[vehicleui][overridebar] show; hide")
    end
    -- Let Blizzard's OverrideActionBar show itself for override bars and
    -- skinned vehicles (quest mini-vehicles, encounter abilities, etc.).
    -- Blizzard's ActionBarController handles populating it correctly.
    -- Combat-safe via attribute driver -- no direct Hide() calls.
    if OverrideActionBar then
        RegisterAttributeDriver(OverrideActionBar, "state-visibility",
            "[vehicleui][overridebar] show; hide")
    end
    -- Native Blizzard keybinds: keep actionButtons tables and
    -- MultiActionButtonDown/Up intact so Blizzard's C-level binding
    -- system can route key presses to our (re-skinned) buttons.

    -- Force all Blizzard action bars to be "enabled" via CVars so buttons work
    C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_1", "1")
    C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_2", "1")
    C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_3", "1")
    C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_4", "1")
end

-------------------------------------------------------------------------------
--  Button Creation / Reuse
--  Reuses Blizzard buttons for slots 1-72 and 145-180.
--  Creates new buttons for slots 73-144.
--  IMPORTANT: Buttons must be extracted (reparented) BEFORE HideBlizzardBars()
--  hides their original parents.
-------------------------------------------------------------------------------
local allButtons = {}   -- [actionSlot] = button
local barButtons = {}   -- [barKey] = { btn1, btn2, ... }
local barFrames  = {}   -- [barKey] = secure header frame
local dataBarFrames = {} -- [barKey] = data bar frame (XP/Rep) populated later in SetupDataBars
local blizzMovableHolders = {} -- [barKey] = holder frame for Blizzard movable frames (ExtraAction, Encounter)
local extraBarHolders = {} -- [barKey] = holder frame for extra bars (MicroBar, BagBar)
local BLIZZ_MOVABLE_OVERLAY = { -- Fixed overlay sizes for unlock mode movers (not the actual Blizzard frames)
    ExtraActionButton = { w = 100, h = 100 },
    EncounterBar      = { w = 150, h = 40 },
}
local barBaseSize = {}  -- [barKey] = { w, h } original button size before any shape/scale

-- Map bar config to action slot ranges
-- These MUST match Blizzard's internal action slot assignments for each
-- button prefix.  Confirmed via warcraft.wiki.gg/wiki/ActionSlot:
--   ActionButton1-12           slots 1-12  (paged via state driver)
--   MultiBarBottomLeftButton   slots 61-72
--   MultiBarBottomRightButton  slots 49-60
--   MultiBarRightButton        slots 25-36
--   MultiBarLeftButton         slots 37-48
--   MultiBar5Button            slots 145-156
--   MultiBar6Button            slots 157-168
--   MultiBar7Button            slots 169-180
-- Slots 133-144 are reserved/unknown (not used by any bar).
-- Stance bar: uses StanceButton1-10 (not action slots)
local BAR_SLOT_OFFSETS = {
    MainBar = 0,    -- slots 1-12 (paged)
    Bar2 = 60,      -- slots 61-72  (MultiBarBottomLeft)
    Bar3 = 48,      -- slots 49-60  (MultiBarBottomRight)
    Bar4 = 24,      -- slots 25-36  (MultiBarRight)
    Bar5 = 36,      -- slots 37-48  (MultiBarLeft)
    Bar6 = 144,     -- slots 145-156 (MultiBar5)
    Bar7 = 156,     -- slots 157-168 (MultiBar6)
    Bar8 = 168,     -- slots 169-180 (MultiBar7)
}

-- Keybind binding name prefixes per bar
-- WoW binding names: MULTIACTIONBAR<N>BUTTON where N maps to the bar's
-- Blizzard internal numbering (not our sequential bar IDs).
local BINDING_MAP = {
    MainBar = "ACTIONBUTTON",
    Bar2 = "MULTIACTIONBAR1BUTTON",
    Bar3 = "MULTIACTIONBAR2BUTTON",
    Bar4 = "MULTIACTIONBAR3BUTTON",
    Bar5 = "MULTIACTIONBAR4BUTTON",
    Bar6 = "MULTIACTIONBAR5BUTTON",
    Bar7 = "MULTIACTIONBAR6BUTTON",
    Bar8 = "MULTIACTIONBAR7BUTTON",
    StanceBar = "SHAPESHIFTBUTTON",
    PetBar = "BONUSACTIONBUTTON",
}

-------------------------------------------------------------------------------
--  Custom Spell Flyout System
--  Replaces Blizzard's SpellFlyout for our action buttons to avoid taint.
--  Intercepts flyout-type action clicks in the secure environment and opens
--  our own flyout frame with spell-type buttons (secure casting, no taint).
-------------------------------------------------------------------------------

-- Layout constants
local FLYOUT_BTN_SPACING = 4

-- All known flyout IDs in retail WoW
local KNOWN_FLYOUT_IDS = {
    1, 8, 9, 10, 11, 12, 66, 67, 84, 92, 93, 96,
    103, 106, 217, 219, 220, 222, 223, 224, 225, 226, 227, 229,
}

-- Flyout button mixin (individual spell buttons inside the flyout menu)
local EABFlyoutBtnMixin = {}

function EABFlyoutBtnMixin:Setup()
    self:SetAttribute("type", "spell")
    self:RegisterForClicks("AnyUp", "AnyDown")
    self:SetScript("OnEnter", self.OnEnter)
    self:SetScript("OnLeave", self.OnLeave)
    self:SetScript("PostClick", self.PostClick)
end

function EABFlyoutBtnMixin:OnEnter()
    if GetCVarBool("UberTooltips") then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 4, 4)
        if GameTooltip:SetSpellByID(self.spellID) then
            self.UpdateTooltip = self.OnEnter
        else
            self.UpdateTooltip = nil
        end
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.spellName, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
        self.UpdateTooltip = nil
    end
end

function EABFlyoutBtnMixin:OnLeave()
    GameTooltip:Hide()
end

function EABFlyoutBtnMixin:OnDataChanged()
    local fid = self:GetAttribute("flyoutID")
    local idx = self:GetAttribute("flyoutIndex")
    local sid, overrideSid, known, name = GetFlyoutSlotInfo(fid, idx)
    local tex = C_Spell.GetSpellTexture(overrideSid)
    self.icon:SetTexture(tex)
    self.icon:SetDesaturated(not known)
    self.spellID = sid
    self.spellName = name
    self:Refresh()
end

function EABFlyoutBtnMixin:PostClick()
    self:RefreshState()
end

function EABFlyoutBtnMixin:Refresh()
    self:RefreshCooldown()
    self:RefreshState()
    self:RefreshUsable()
    self:RefreshCount()
end

function EABFlyoutBtnMixin:RefreshCooldown()
    if self.spellID then
        ActionButton_UpdateCooldown(self)
    end
end

function EABFlyoutBtnMixin:RefreshState()
    if self.spellID then
        self:SetChecked(C_Spell.IsCurrentSpell(self.spellID) and true)
    else
        self:SetChecked(false)
    end
end

function EABFlyoutBtnMixin:RefreshUsable()
    local ico = self.icon
    local sid = self.spellID
    if sid then
        local usable, oom = C_Spell.IsSpellUsable(sid)
        if oom then
            ico:SetDesaturated(true)
            ico:SetVertexColor(0.4, 0.4, 1.0)
        elseif usable then
            ico:SetDesaturated(false)
            ico:SetVertexColor(1, 1, 1)
        else
            ico:SetDesaturated(true)
            ico:SetVertexColor(0.4, 0.4, 0.4)
        end
    else
        ico:SetDesaturated(false)
        ico:SetVertexColor(1, 1, 1)
    end
end

function EABFlyoutBtnMixin:RefreshCount()
    local sid = self.spellID
    if sid and C_Spell.IsConsumableSpell(sid) then
        local ct = C_Spell.GetSpellCastCount(sid)
        self.Count:SetText(ct > 9999 and "*" or ct)
    else
        self.Count:SetText("")
    end
end

-- Flyout frame mixin (the container that holds all flyout buttons)
local EABFlyoutFrameMixin = {}

-- Secure snippet: toggles the flyout open/closed, positions buttons
local SECURE_TOGGLE = [[
    local flyoutID = ...
    local caller = self:GetAttribute("caller")

    -- Toggle off if already open on the same button
    if self:IsShown() and caller == self:GetParent() then
        self:Hide()
        return
    end

    -- Sync this flyout's data if we haven't seen it before
    if not EAB_FLYOUT_DATA[flyoutID] then
        self:SetAttribute("_pendingSyncID", flyoutID)
        self:CallMethod("EnsureFlyoutSynced")
    end

    local data = EAB_FLYOUT_DATA[flyoutID]
    local slotCount = data and data.numSlots or 0
    local known = data and data.isKnown or false

    self:SetParent(caller)

    if slotCount == 0 or not known then
        self:Hide()
        return
    end

    local dir = caller:GetAttribute("flyoutDirection") or "UP"
    self:SetAttribute("direction", dir)

    -- Match flyout button size to the caller button
    local cW = caller:GetWidth()
    local cH = caller:GetHeight()

    local prev = nil
    local shown = 0

    for i = 1, slotCount do
        if data[i].isKnown then
            shown = shown + 1
            local btn = EAB_FLYOUT_BTNS[shown]
            btn:SetWidth(cW)
            btn:SetHeight(cH)
            btn:ClearAllPoints()

            if dir == "UP" then
                if prev then
                    btn:SetPoint("BOTTOM", prev, "TOP", 0, EAB_FLYOUT_SPACING)
                else
                    btn:SetPoint("BOTTOM", self, "BOTTOM", 0, 0)
                end
            elseif dir == "DOWN" then
                if prev then
                    btn:SetPoint("TOP", prev, "BOTTOM", 0, -EAB_FLYOUT_SPACING)
                else
                    btn:SetPoint("TOP", self, "TOP", 0, 0)
                end
            elseif dir == "LEFT" then
                if prev then
                    btn:SetPoint("RIGHT", prev, "LEFT", -EAB_FLYOUT_SPACING, 0)
                else
                    btn:SetPoint("RIGHT", self, "RIGHT", 0, 0)
                end
            elseif dir == "RIGHT" then
                if prev then
                    btn:SetPoint("LEFT", prev, "RIGHT", EAB_FLYOUT_SPACING, 0)
                else
                    btn:SetPoint("LEFT", self, "LEFT", 0, 0)
                end
            end

            btn:SetAttribute("spell", data[i].spellID)
            btn:SetAttribute("flyoutID", flyoutID)
            btn:SetAttribute("flyoutIndex", i)
            btn:Enable()
            btn:Show()
            btn:CallMethod("OnDataChanged")

            prev = btn
        end
    end

    -- Hide unused buttons
    for i = shown + 1, #EAB_FLYOUT_BTNS do
        EAB_FLYOUT_BTNS[i]:Hide()
    end

    if shown == 0 then
        self:Hide()
        return
    end

    local vert = false

    self:ClearAllPoints()
    if dir == "UP" then
        self:SetPoint("BOTTOM", caller, "TOP", 0, EAB_FLYOUT_SPACING)
        vert = true
    elseif dir == "DOWN" then
        self:SetPoint("TOP", caller, "BOTTOM", 0, -EAB_FLYOUT_SPACING)
        vert = true
    elseif dir == "LEFT" then
        self:SetPoint("RIGHT", caller, "LEFT", -EAB_FLYOUT_SPACING, 0)
    elseif dir == "RIGHT" then
        self:SetPoint("LEFT", caller, "RIGHT", EAB_FLYOUT_SPACING, 0)
    end

    if vert then
        self:SetWidth(cW)
        self:SetHeight((cH + EAB_FLYOUT_SPACING) * shown - EAB_FLYOUT_SPACING)
    else
        self:SetWidth((cW + EAB_FLYOUT_SPACING) * shown - EAB_FLYOUT_SPACING)
        self:SetHeight(cH)
    end

    self:CallMethod("OnFlyoutOpened")
    self:Show()
]]

function EABFlyoutFrameMixin:Init()
    self.btns = {}

    -- Initialize secure environment tables
    self:Execute(([[
        EAB_FLYOUT_DATA = newtable()
        EAB_FLYOUT_BTNS = newtable()
        EAB_FLYOUT_SPACING = %d
    ]]):format(FLYOUT_BTN_SPACING))

    self:SetAttribute("Toggle", SECURE_TOGGLE)
    self:SetAttribute("_onhide", [[ self:Hide(true) ]])

    self:SyncAllFlyouts()
end

function EABFlyoutFrameMixin:SyncAllFlyouts()
    -- Discover flyout IDs from all action slots (covers any flyout, including new ones)
    local seen = {}
    local maxSlots = 0
    for slot = 1, 180 do
        local aType, aID = GetActionInfo(slot)
        if aType == "flyout" and aID and not seen[aID] then
            seen[aID] = true
            local n = self:SyncFlyoutData(aID)
            if n > maxSlots then maxSlots = n end
        end
    end
    -- Also sync the known list as a safety net for unbound flyouts
    for _, fid in ipairs(KNOWN_FLYOUT_IDS) do
        if not seen[fid] then
            local n = self:SyncFlyoutData(fid)
            if n > maxSlots then maxSlots = n end
        end
    end
    self:EnsureButtons(maxSlots)
end

function EABFlyoutFrameMixin:SyncSingleFlyout(flyoutID)
    local n = self:SyncFlyoutData(flyoutID)
    if n > #self.btns then
        self:EnsureButtons(n)
        return true
    end
    return false
end

-- Called from the secure toggle via CallMethod when an unknown flyout ID is encountered.
-- Reads the pending ID from an attribute (secure env can't pass args to CallMethod).
function EABFlyoutFrameMixin:EnsureFlyoutSynced()
    local fid = self:GetAttribute("_pendingSyncID")
    if not fid then return end
    self:SyncSingleFlyout(fid)
end

function EABFlyoutFrameMixin:SyncFlyoutData(flyoutID)
    local _, _, numSlots, isKnown = GetFlyoutInfo(flyoutID)

    self:Execute(([[
        local fid = %d
        local ns = %d
        local kn = %q == "true"
        local d = EAB_FLYOUT_DATA[fid] or newtable()
        d.numSlots = ns
        d.isKnown = kn
        EAB_FLYOUT_DATA[fid] = d
        for i = ns + 1, #d do d[i].isKnown = false end
    ]]):format(flyoutID, numSlots, tostring(isKnown)))

    for slot = 1, numSlots do
        local sid, _, slotKnown = GetFlyoutSlotInfo(flyoutID, slot)
        if slotKnown then
            local petIdx, petName = GetCallPetSpellInfo(sid)
            if petIdx and not (petName and petName ~= "") then
                slotKnown = false
            end
        end
        self:Execute(([[
            local d = EAB_FLYOUT_DATA[%d][%d] or newtable()
            d.spellID = %d
            d.isKnown = %q == "true"
            EAB_FLYOUT_DATA[%d][%d] = d
        ]]):format(flyoutID, slot, sid, tostring(slotKnown), flyoutID, slot))
    end

    return numSlots
end

function EABFlyoutFrameMixin:EnsureButtons(count)
    for i = #self.btns + 1, count do
        local btn = self:MakeFlyoutButton(i)
        self:SetFrameRef("_eabFlySlot", btn)
        self:Execute([[ tinsert(EAB_FLYOUT_BTNS, self:GetFrameRef("_eabFlySlot")) ]])
        self.btns[i] = btn
    end
end

-- Secure snippet for flyout button clicks: close the flyout on key-up
local FLYBTN_PRE = [[ if not down then return nil, "close" end ]]
local FLYBTN_POST = [[ if message == "close" then control:Hide() end ]]

function EABFlyoutFrameMixin:MakeFlyoutButton(idx)
    local name = "EABFlyoutBtn" .. idx
    local btn = CreateFrame("CheckButton", name, self,
        "SmallActionButtonTemplate, SecureActionButtonTemplate")
    Mixin(btn, EABFlyoutBtnMixin)
    btn:Setup()
    self:WrapScript(btn, "OnClick", FLYBTN_PRE, FLYBTN_POST)
    return btn
end

function EABFlyoutFrameMixin:ForVisible(method, ...)
    for _, btn in ipairs(self.btns) do
        if btn:IsShown() then btn[method](btn, ...) end
    end
end

-- Style flyout buttons to match the parent bar's appearance.
-- Called from the secure toggle via CallMethod after the flyout opens.
function EABFlyoutFrameMixin:OnFlyoutOpened()
    local caller = self:GetParent()
    if not caller then return end

    -- Find the bar key from the caller button
    local barKey = caller._eabBarKey
    if not barKey then return end

    local prof = EAB.db and EAB.db.profile
    if not prof then return end
    local s = prof.bars and prof.bars[barKey]
    if not s then return end

    local PP = EllesmereUI and EllesmereUI.PP
    local shape = s.buttonShape or "none"
    local zoom = ((s.iconZoom or prof.iconZoom or 5.5)) / 100
    local brdSz = ResolveBorderThickness(s)
    local brdOn = brdSz > 0
    local brdColor = s.borderColor or { r = 0, g = 0, b = 0, a = 1 }
    local cr, cg, cb, ca = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
    if s.borderClassColor then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
        end
    end
    local shapeBrdColor = s.shapeBorderColor or brdColor
    local sbR, sbG, sbB, sbA = shapeBrdColor.r, shapeBrdColor.g, shapeBrdColor.b, shapeBrdColor.a or 1
    if s.borderClassColor then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then sbR, sbG, sbB = cc.r, cc.g, cc.b end
        end
    end

    for _, btn in ipairs(self.btns) do
        if btn:IsShown() then
            -- Strip default SmallActionButton art
            self:StripFlyoutButtonArt(btn)

            if shape ~= "none" and shape ~= "cropped" and SHAPE_MASKS[shape] then
                -- Apply shape mask to flyout button
                self:ApplyFlyoutShape(btn, shape, brdOn, sbR, sbG, sbB, sbA, brdSz, zoom)
            else
                -- Square/cropped: apply borders and zoom
                self:ApplyFlyoutSquare(btn, brdOn, cr, cg, cb, ca, brdSz, zoom, shape == "cropped")
            end

            -- Apply pushed/highlight/misc texture animations to match the bar
            -- Only outside combat SetPushedTexture is restricted on secure buttons in combat.
            -- The textures persist after being set, so this only needs to run once per button.
            if not InCombatLockdown() then
                self:ApplyFlyoutAnimations(btn, prof)
            end
        end
    end
end

-- Apply pushed/highlight/misc button texture animations to a flyout button,
-- matching the global animation settings used on all action bar buttons.
-- NOTE: called via CallMethod (restricted env) cannot use file-local upvalues.
-- All texture operations are inlined; texture paths are read from the EAB profile.
function EABFlyoutFrameMixin:ApplyFlyoutAnimations(btn, prof)
    local useCC = prof.pushedUseClassColor
    local customC = prof.pushedCustomColor or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local cr, cg, cb, ca = customC.r, customC.g, customC.b, customC.a or 1
    if useCC then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
    end

    local mediaDir = "Interface\\AddOns\\EllesmereUIActionBars\\Media\\"
    local hlTex = {
        mediaDir .. "highlight-2.png",
        mediaDir .. "highlight-3.png",
        mediaDir .. "highlight-4.png",
    }
    local function ApplyTex(tex, path)
        if not tex then return end
        tex:SetAtlas(nil)
        tex:SetTexture(path)
        tex:SetTexCoord(0, 1, 0, 1)
        tex:ClearAllPoints()
        tex:SetAllPoints(btn)
    end

    -- Pushed texture
    -- Use btn:SetPushedTexture() to register the change with the button system,
    -- then retrieve the texture object to apply color/coords.
    local pType = prof.pushedTextureType or 2
    if pType == 6 then
        btn:SetPushedTexture("")
        local pt = btn:GetPushedTexture()
        if pt then pt:SetAlpha(0) end
    else
        local texPath
        if pType <= 3 then
            texPath = hlTex[pType] or hlTex[2]
        elseif pType == 4 then
            texPath = "Interface\\Buttons\\WHITE8X8"
        else -- pType == 5
            texPath = hlTex[1]
        end
        btn:SetPushedTexture(texPath)
        local pt = btn:GetPushedTexture()
        if pt then
            pt:SetAlpha(1)
            pt:SetTexCoord(0, 1, 0, 1)
            pt:ClearAllPoints()
            pt:SetAllPoints(btn)
            if pType == 4 then
                pt:SetVertexColor(cr, cg, cb, 0.35)
            else
                pt:SetVertexColor(cr, cg, cb, 1)
            end
        end
    end

    -- Highlight texture
    local hType = prof.highlightTextureType or 2
    local hUseCC = prof.highlightUseClassColor
    local hCustomC = prof.highlightCustomColor or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local hr, hg, hb = hCustomC.r, hCustomC.g, hCustomC.b
    if hUseCC then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then hr, hg, hb = cc.r, cc.g, cc.b end end
    end
    if btn.HighlightTexture then
        if hType == 6 then
            btn.HighlightTexture:SetAlpha(0)
        else
            btn.HighlightTexture:SetAlpha(1)
            if hType <= 3 then
                ApplyTex(btn.HighlightTexture, hlTex[hType] or hlTex[1])
                btn.HighlightTexture:SetVertexColor(hr, hg, hb, 1)
            elseif hType == 4 then
                btn.HighlightTexture:SetColorTexture(hr, hg, hb, 0.35)
            elseif hType == 5 then
                ApplyTex(btn.HighlightTexture, hlTex[1])
                btn.HighlightTexture:SetVertexColor(hr, hg, hb, 1)
            end
        end
    end

    -- NewActionTexture (uses pushed color)
    if btn.NewActionTexture then
        btn.NewActionTexture:SetDesaturated(true)
        btn.NewActionTexture:SetVertexColor(cr, cg, cb, ca)
    end
end

-- Remove default SmallActionButton template art from a flyout button
function EABFlyoutFrameMixin:StripFlyoutButtonArt(btn)
    if btn._eabFlyStripped then return end
    local nt = btn.NormalTexture or btn:GetNormalTexture()
    if nt then nt:SetAlpha(0) end
    if btn.SlotBackground then btn.SlotBackground:Hide() end
    if btn.SlotArt then btn.SlotArt:Hide() end
    if btn.IconMask then
        btn.IconMask:Hide()
        btn.IconMask:SetTexture(nil)
        btn.IconMask:ClearAllPoints()
        btn.IconMask:SetSize(0.001, 0.001)
    end
    if btn.FlyoutBorderShadow then btn.FlyoutBorderShadow:SetAlpha(0) end
    -- Ensure icon fills the button
    local icon = btn.icon or btn.Icon
    if icon then
        icon:ClearAllPoints()
        icon:SetAllPoints(btn)
    end
    btn._eabFlyStripped = true
end

-- Apply square borders and zoom to a flyout button
function EABFlyoutFrameMixin:ApplyFlyoutSquare(btn, brdOn, cr, cg, cb, ca, brdSz, zoom, cropped)
    local PP = EllesmereUI and EllesmereUI.PP
    -- Remove shape mask if previously applied
    if btn._eabShapeMask then
        local icon = btn.icon or btn.Icon
        if icon then pcall(icon.RemoveMaskTexture, icon, btn._eabShapeMask) end
        if btn.cooldown and not btn.cooldown:IsForbidden() then
            pcall(btn.cooldown.RemoveMaskTexture, btn.cooldown, btn._eabShapeMask)
            pcall(btn.cooldown.SetSwipeTexture, btn.cooldown, "")
        end
        btn._eabShapeMask:Hide()
    end
    if btn._eabShapeBorder then btn._eabShapeBorder:Hide() end

    local icon = btn.icon or btn.Icon
    if icon then
        icon:ClearAllPoints()
        icon:SetAllPoints(btn)
        if cropped then
            local z = zoom or 0
            icon:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
        elseif zoom > 0 then
            icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        else
            icon:SetTexCoord(0, 1, 0, 1)
        end
    end

    if PP then
        if brdOn then
            if not btn._eabBorders then
                PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", -1)
                btn._eabBorders = btn._ppBorders
            end
            PP.UpdateBorder(btn, brdSz, cr, cg, cb, ca)
            PP.ShowBorder(btn)
        elseif btn._eabBorders then
            PP.HideBorder(btn)
        end
    end
end

-- Apply shape mask, border, and zoom to a flyout button
function EABFlyoutFrameMixin:ApplyFlyoutShape(btn, shape, brdOn, brdR, brdG, brdB, brdA, brdSz, zoom)
    local PP = EllesmereUI and EllesmereUI.PP
    local maskTex = SHAPE_MASKS[shape]
    if not maskTex then return end

    -- Hide square borders when using shapes
    if btn._eabBorders and PP then PP.HideBorder(btn) end

    -- Create or reuse shape mask
    if not btn._eabShapeMask then
        btn._eabShapeMask = btn:CreateMaskTexture()
    end
    local mask = btn._eabShapeMask
    mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:ClearAllPoints()
    if brdSz and brdSz >= 1 then
        if PP then
            PP.Point(mask, "TOPLEFT", btn, "TOPLEFT", 1, -1)
            PP.Point(mask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        else
            mask:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
            mask:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        end
    else
        mask:SetAllPoints(btn)
    end
    mask:Show()

    local icon = btn.icon or btn.Icon
    if icon then
        pcall(icon.RemoveMaskTexture, icon, mask)
        icon:AddMaskTexture(mask)
    end

    -- Expand icon for shape inset
    local shapeOffset = SHAPE_ICON_EXPAND_OFFSETS[shape] or 0
    local shapeDefault = (SHAPE_ZOOM_DEFAULTS[shape] or 6.0) / 100
    local iconExp = SHAPE_ICON_EXPAND + shapeOffset + ((zoom or 0) - shapeDefault) * 200
    if iconExp < 0 then iconExp = 0 end
    local halfIE = iconExp / 2
    if icon and PP then
        icon:ClearAllPoints()
        PP.Point(icon, "TOPLEFT", btn, "TOPLEFT", -halfIE, halfIE)
        PP.Point(icon, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", halfIE, -halfIE)
    end

    -- Expand texcoords for shape
    local insetPx = SHAPE_INSETS[shape] or 17
    local visRatio = (128 - 2 * insetPx) / 128
    local expand = ((1 / visRatio) - 1) * 0.5
    if icon then icon:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand) end

    -- Mask cooldown frame
    if btn.cooldown and not btn.cooldown:IsForbidden() then
        pcall(btn.cooldown.RemoveMaskTexture, btn.cooldown, mask)
        pcall(btn.cooldown.AddMaskTexture, btn.cooldown, mask)
        if btn.cooldown.SetSwipeTexture then
            pcall(btn.cooldown.SetSwipeTexture, btn.cooldown, maskTex)
        end
        local useCircular = (shape ~= "square" and shape ~= "csquare")
        if btn.cooldown.SetUseCircularEdge then
            pcall(btn.cooldown.SetUseCircularEdge, btn.cooldown, useCircular)
        end
    end

    -- Shape border overlay
    if not btn._eabShapeBorder then
        btn._eabShapeBorder = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    end
    local borderTex = btn._eabShapeBorder
    pcall(borderTex.RemoveMaskTexture, borderTex, mask)
    borderTex:ClearAllPoints()
    borderTex:SetAllPoints(btn)
    if brdOn and SHAPE_BORDERS[shape] then
        borderTex:SetTexture(SHAPE_BORDERS[shape])
        borderTex:SetVertexColor(brdR, brdG, brdB, brdA)
        borderTex:Show()
    else
        borderTex:Hide()
    end
end

-- Flyout manager: creates the frame on demand, registers buttons, handles events
local EABFlyout = CreateFrame("Frame")

-- Secure snippet: intercepts flyout-type action clicks on registered buttons
local INTERCEPT_CLICK = [[
    local aType, aID = GetActionInfo(self:GetEffectiveAttribute("action", button))
    if aType == "flyout" then
        if not down then
            control:SetAttribute("caller", self:GetFrameRef("_eabFlyOwner") or self)
            control:RunAttribute("Toggle", aID)
        end
        return false
    end
]]

function EABFlyout:GetFrame()
    if self._frame then return self._frame end

    local f = CreateFrame("Frame", nil, nil, "SecureHandlerShowHideTemplate")
    Mixin(f, EABFlyoutFrameMixin)
    f:Init()
    f:HookScript("OnShow", function() self:OnShown() end)
    f:HookScript("OnHide", function() self:OnHidden() end)

    self:RegisterEvent("SPELL_FLYOUT_UPDATE")
    self:RegisterEvent("PET_STABLE_UPDATE")
    self:SetScript("OnEvent", self.OnEvent)

    self._frame = f
    return f
end

function EABFlyout:RegisterButton(button, owner)
    local f = self:GetFrame()
    -- Store a reference to the "real" parent button so the secure env
    -- can reparent the flyout to the correct visual button
    if owner then
        SecureHandlerSetFrameRef(button, "_eabFlyOwner", owner)
    end
    f:WrapScript(button, "OnClick", INTERCEPT_CLICK)
end

function EABFlyout:OnEvent(event, arg1)
    if event == "SPELL_FLYOUT_UPDATE" then
        if arg1 then
            if InCombatLockdown() then
                self._pendingSync = true
                self:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                self._frame:SyncSingleFlyout(arg1)
            end
        end
        if self._frame then self._frame:ForVisible("Refresh") end
    elseif event == "PET_STABLE_UPDATE" then
        if InCombatLockdown() then
            self._pendingSync = true
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            self._frame:SyncAllFlyouts()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if self._pendingSync then
            self._frame:SyncAllFlyouts()
            self._pendingSync = nil
        end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    elseif event == "CURRENT_SPELL_CAST_CHANGED" then
        if self._frame then self._frame:ForVisible("RefreshState") end
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if self._frame then self._frame:ForVisible("RefreshCooldown") end
    elseif event == "SPELL_UPDATE_USABLE" then
        if self._frame then self._frame:ForVisible("RefreshUsable") end
    end
end

function EABFlyout:OnShown()
    if not self._flyoutVisible then
        self._flyoutVisible = true
        self:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        self:RegisterEvent("SPELL_UPDATE_USABLE")
    end
end

function EABFlyout:OnHidden()
    if self._flyoutVisible then
        self._flyoutVisible = nil
        self:UnregisterEvent("CURRENT_SPELL_CAST_CHANGED")
        self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        self:UnregisterEvent("SPELL_UPDATE_USABLE")
    end
end

-- Public API for checking flyout visibility (used by mouseover fade logic)
function EABFlyout:IsVisible()
    return self._frame and self._frame:IsVisible()
end

function EABFlyout:IsMouseOver(...)
    return self._frame and self._frame:IsMouseOver(...)
end

function EABFlyout:GetParent()
    return self._frame and self._frame:GetParent()
end

-- Forward declaration -- defined fully in the keybind section below.
-- Allows SetupBar to eagerly create bind buttons while out of combat.
local GetOrCreateBindButton

-- Get or create an action button for a given slot
-- skipProtected: if true, skip SetParent/SetID/Show (used during combat reload;
-- the secure handler will perform those operations instead)
local function GetOrCreateButton(slot, parent, info, index, skipProtected)
    if allButtons[slot] then
        if not skipProtected then
            allButtons[slot]:SetParent(parent)
        end
        return allButtons[slot]
    end

    -- Try to reuse a Blizzard button
    local btn
    if info.blizzBtnPrefix and not info.isStance and not info.isPetBar then
        btn = _G[info.blizzBtnPrefix .. index]
    elseif info.isStance then
        btn = _G["StanceButton" .. index]
    end

    if btn then
        if not skipProtected then
            -- Reparent the Blizzard button to our bar frame
            btn:SetParent(parent)
            btn:SetID(0)  -- Reset ID to avoid Blizzard paging interference
            btn.Bar = nil  -- Drop reference to Blizzard bar parent
            btn:Show()
        end
    else
        -- Create a new button (for slots 73-132 that don't have Blizzard equivalents)
        -- These are our own frames, not protected, so CreateFrame is always safe
        local name = "EABButton" .. slot
        btn = CreateFrame("CheckButton", name, parent, "ActionBarButtonTemplate")
        btn:SetAttribute("action", slot)
    end

    allButtons[slot] = btn
    return btn
end

-------------------------------------------------------------------------------
--  Paging State Conditions (class-specific)
--  Format: "[condition] pageNumber; ..."
--  Page numbers map to action bar pages (1-based).
--  bonusbar:5 = dragonriding for all classes.
-------------------------------------------------------------------------------
local function GetClassPagingConditions()
    local _, class = UnitClass("player")
    local conditions = ""

    -- Override bar (soft vehicle / quest abilities) and possess bar: remap bar 1
    -- to show those action slots so our buttons stay visible and keybinds work.
    if GetOverrideBarIndex then
        conditions = conditions .. "[overridebar] " .. GetOverrideBarIndex() .. "; "
    end
    if GetVehicleBarIndex then
        conditions = conditions .. "[vehicleui][possessbar] " .. GetVehicleBarIndex() .. "; "
    end

    -- Class-specific paging
    if class == "DRUID" then
        conditions = conditions .. "[bonusbar:1,stealth] 7; [bonusbar:1] 7; [bonusbar:3] 9; [bonusbar:4] 10; "
    elseif class == "ROGUE" then
        conditions = conditions .. "[bonusbar:1] 7; "
    end

    -- Dragonriding (all classes)
    conditions = conditions .. "[bonusbar:5] 11; "


    -- Default: page 1
    conditions = conditions .. "1"

    return conditions
end

-------------------------------------------------------------------------------
--  Secure Bar Frame Creation
--  Each bar gets a SecureHandlerStateTemplate frame that manages paging.
--  Paging uses the _childupdate-offset pattern: the parent frame
--  computes an action offset and broadcasts it to children via ChildUpdate.
--  Each button has a _childupdate-offset handler that sets its own action.
-------------------------------------------------------------------------------
local NUM_ACTIONBAR_BUTTONS = NUM_ACTIONBAR_BUTTONS or 12

local function CreateBarFrame(info)
    local key = info.key
    local frame = CreateFrame("Frame", "EABBar_" .. key, UIParent, "SecureHandlerStateTemplate")
    frame:SetSize(1, 1)
    frame:SetPoint("CENTER")
    -- Bar frames never need to intercept mouse clicks; only buttons do.
    -- Motion is enabled later by the hover system for OnEnter/OnLeave.
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
    end
    frame._barKey = key
    frame._barInfo = info

    if key == "MainBar" then
        -- Main bar uses paging via state driver
        local pagingConditions = GetClassPagingConditions()

        frame:SetAttribute("barLength", NUM_ACTIONBAR_BUTTONS)

        -- Secure snippet: when page state changes, compute action offset
        -- and broadcast to all child buttons via ChildUpdate.
        frame:SetAttribute("_onstate-page", [[
            local page = tonumber(newstate) or 1
            -- Possess/bonus bar fallback: resolve the real page index
            if page == 11 then
                if HasVehicleActionBar() then
                    page = GetVehicleBarIndex()
                elseif HasOverrideActionBar() then
                    page = GetOverrideBarIndex()
                elseif HasTempShapeshiftActionBar() then
                    page = GetTempShapeshiftBarIndex()
                elseif HasBonusActionBar() then
                    page = GetBonusBarIndex()
                end
            end
            local barLen = self:GetAttribute("barLength")
            local offset = (page - 1) * barLen
            self:SetAttribute("actionOffset", offset)
            control:ChildUpdate("offset", offset)
        ]])

        RegisterStateDriver(frame, "page", pagingConditions)
    end

    barFrames[key] = frame
    -- Install a secure visibility handler so we can show/hide the frame
    -- even during combat by setting the state attribute directly.
    -- RegisterStateDriver installs the _onstate snippet at creation time
    -- (always out of combat). Later, SetAttribute("state-eabvis", "hide")
    -- triggers the snippet from the secure environment.
    frame:SetAttribute("_onstate-eabvis", [[
        if newstate == "hide" then
            self:Hide()
        else
            self:Show()
        end
    ]])
    -- Set initial visibility based on settings. If the bar is always-hidden
    -- or disabled, start hidden so the secure snippet hides it immediately
    -- before combat can come back after a brief regen during reload.
    local s = EAB.db and EAB.db.profile.bars[key]
    local startHidden = s and (s.alwaysHidden or s.enabled == false)
    RegisterStateDriver(frame, "eabvis", startHidden and "hide" or "show")

    -- Register with secure handler so it can reparent buttons to this frame
    SecureSetupHandler_RegisterBarFrame(key, frame)
    _ownedFrames[frame] = true
    return frame
end

-------------------------------------------------------------------------------
--  Bar Setup creates frames and buttons for each bar
-------------------------------------------------------------------------------
local function SetupBar(info, skipProtected)
    local key = info.key
    local frame = CreateBarFrame(info)
    local buttons = {}

    if info.isStance then
        -- Stance bar: reuse StanceButton1-N
        for i = 1, info.count do
            local btn = _G["StanceButton" .. i]
            if btn then
                if not skipProtected then btn:SetParent(frame) end
                buttons[i] = btn
            end
        end
    elseif info.isPetBar then
        -- Pet bar: reuse PetActionButton1-N
        for i = 1, info.count do
            local btn = _G["PetActionButton" .. i]
            if btn then
                if not skipProtected then btn:SetParent(frame) end
                buttons[i] = btn
                -- Hook drag handlers so spellbook drops work even though
                -- the original PetActionBar is hidden and unregistered.
                btn:HookScript("OnReceiveDrag", function(self)
                    if InCombatLockdown() then return end
                    -- The Blizzard mixin handler runs first; this hook
                    -- calls PickupPetAction as a fallback in case the
                    -- mixin handler didn't fire properly. The resulting
                    -- PET_BAR_UPDATE event triggers our full refresh
                    -- (LayoutBar + ApplyAlwaysShowButtons) automatically.
                    local cType = GetCursorInfo()
                    if cType == "petaction" then
                        PickupPetAction(self:GetID())
                    end
                end)
            end
        end
    else
        local slotOffset = BAR_SLOT_OFFSETS[key] or 0
        for i = 1, info.count do
            local slot = slotOffset + i
            local btn

            if key == "MainBar" then
                -- Main bar buttons: reuse ActionButton1-12
                btn = _G["ActionButton" .. i]
                if btn then
                    if not skipProtected then
                        btn:SetParent(frame)
                        btn:SetID(0)
                        btn.Bar = nil
                    end

                    -- SetAttribute is allowed in combat on non-protected frames,
                    -- but ActionButton1 is protected. Defer to secure handler.
                    if not skipProtected then
                        btn:SetAttribute("index", i)
                        btn:SetAttribute("_childupdate-offset", [[
                            local offset = message or 0
                            local id = self:GetAttribute("index") + offset
                            if self:GetAttribute("action") ~= id then
                                self:SetAttribute("action", id)
                            end
                        ]])
                        local curOffset = frame:GetAttribute("actionOffset") or 0
                        btn:SetAttribute("action", i + curOffset)
                    end
                end
            else
                btn = GetOrCreateButton(slot, frame, info, i, skipProtected)
                if btn and not info.isStance then
                    if not skipProtected then
                        btn:SetAttribute("action", slot)
                    end
                end
            end

            if btn then
                -- RegisterForClicks and EnableMouseWheel are not protected
                if btn.RegisterForClicks then
                    btn:RegisterForClicks("AnyDown", "AnyUp")
                end
                if btn.EnableMouseWheel then
                    btn:EnableMouseWheel(true)
                end
                -- Tell the Blizzard mixin to always consider the grid
                -- "shown" so its UpdateShownState never hides our buttons.
                -- We control visibility purely through alpha instead.
                if not skipProtected then
                    btn:SetAttribute("showgrid", 1)
                end
                -- Register parent button with our custom flyout system
                -- (intercepts flyout clicks to avoid Blizzard taint path).
                -- Stance and pet bar buttons don't have flyout actions.
                if not info.isStance and not info.isPetBar then
                    EABFlyout:RegisterButton(btn)
                end
                buttons[i] = btn
            end
        end
    end

    barButtons[key] = buttons

    -- Store original button size before any shape/scale modifications.
    -- StanceButtons and PetActionButtons are 30x30; action buttons are 45x45.
    -- Round to nearest integer to eliminate floating-point noise from Blizzard's
    -- scaling the intended sizes are always whole numbers.
    local btn1 = buttons[1]
    barBaseSize[key] = {
        w = math.floor((btn1 and btn1:GetWidth() or 45) + 0.5),
        h = math.floor((btn1 and btn1:GetHeight() or 45) + 0.5),
    }

    return frame, buttons
end

-------------------------------------------------------------------------------
--  First-Install Capture
--  On first load (no saved vars), read Blizzard Edit Mode settings to
--  determine initial bar positions, icon counts, orientation, visibility.
-------------------------------------------------------------------------------
local function CaptureBlizzardDefaults()
    local captured = {}
    local uiW, uiH = UIParent:GetSize()
    local uiScale = UIParent:GetEffectiveScale()

    -- MainActionBar is the Edit Mode frame for Action Bar 1 in modern WoW.
    -- MainMenuBar no longer exists; the parent chain is:
    -- ActionButton1 MainActionBarButtonContainer1 MainActionBar UIParent
    local mainActionBar = _G["MainActionBar"]

    for _, info in ipairs(BAR_CONFIG) do
        local bar = _G[info.blizzFrame]
        if info.key == "MainBar" then
            -- MainBar: use MainActionBar for Edit Mode settings,
            -- and ActionButton1-12 for position (since the container
            -- frame may be larger than the visible buttons).
            local data = {}
            local btn1 = _G["ActionButton1"]
            if btn1 and btn1:GetLeft() then
                local l, r, t, b = btn1:GetLeft(), btn1:GetRight(), btn1:GetTop(), btn1:GetBottom()
                for i = 2, 12 do
                    local bn = _G["ActionButton" .. i]
                    if bn and bn:IsVisible() and bn:GetLeft() then
                        local bl, br, bt, bb = bn:GetLeft(), bn:GetRight(), bn:GetTop(), bn:GetBottom()
                        if bl < l then l = bl end
                        if br > r then r = br end
                        if bt > t then t = bt end
                        if bb < b then b = bb end
                    end
                end
                local bScale = btn1:GetEffectiveScale()
                local cx = ((l + r) / 2) * bScale / uiScale
                local cy = ((t + b) / 2) * bScale / uiScale
                data.point = "CENTER"
                data.relPoint = "CENTER"
                data.x = cx - (uiW / 2)
                data.y = cy - (uiH / 2)
            end

            -- Read Edit Mode settings from MainActionBar
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

            -- If alwaysShowButtons is off and the bar has no assigned abilities,
            -- force it on so the bar stays visible after we take over.
            -- Users with empty bars + hidden-empty-slots would otherwise lose
            -- the bar entirely on first install.
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

            -- Visibility (setting 5): 0=Always, 1=InCombat, 2=OutOfCombat, 3=Hidden
            -- Only bars 2-8 support this setting.
            -- IMPORTANT: A bar can be disabled entirely via Gameplay > Action Bars
            -- checkboxes (CVars), in which case IsShown()=false even though
            -- setting 5 says "Always Visible". IsShown=false takes priority.
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

-------------------------------------------------------------------------------
--  Layout Engine positions buttons in a grid
-------------------------------------------------------------------------------
-- Snap a value to a whole number of physical pixels at the bar's effective scale.
-- Uses the same approach as the border system: convert to physical pixels,
-- round to nearest integer, convert back. Every element ends up exactly N
-- physical pixels, eliminating sub-pixel drift between siblings.
local function SnapForScale(x, barScale)
    if x == 0 then return 0 end
    local es = (UIParent:GetScale() or 1) * (barScale or 1)
    return PP.SnapForES(x, es)
end


-- Compute layout for a bar and return a table of per-button data.
-- Returns: { [i] = { x, y, w, h, show } }, frameW, frameH
local function ComputeBarLayout(key)
    local info = BAR_LOOKUP[key]
    if not info then return {}, 1, 1 end
    local buttons = barButtons[key]
    if not buttons then return {}, 1, 1 end

    local s = EAB.db.profile.bars[key]
    local barScale = s.barScale or 1.0
    if barScale < 0.1 then barScale = 0.1 end
    local numIcons = s.overrideNumIcons or s.numIcons or info.count
    if numIcons < 1 then numIcons = info.count end
    if numIcons > info.count then numIcons = info.count end
    if info.isStance then numIcons = GetNumShapeshiftForms() or info.count end

    local numRows = s.overrideNumRows or s.numRows or 1
    if numRows < 1 then numRows = 1 end
    local stride = ceil(numIcons / numRows)
    local padding = SnapForScale(s.buttonPadding or 2, barScale)
    local isVertical = (s.orientation == "vertical")
    local growUp = (s.growDirection or "up") == "up"
    local shape = s.buttonShape or "none"

    local base = barBaseSize[key]
    local btnW = base and base.w or 45
    local btnH = base and base.h or 45
    if shape ~= "none" and shape ~= "cropped" then
        btnW = btnW + SHAPE_BTN_EXPAND
        btnH = btnH + SHAPE_BTN_EXPAND
    end
    if shape == "cropped" then btnH = btnH * 0.80 end
    btnW = SnapForScale(btnW, barScale)
    btnH = SnapForScale(btnH, barScale)
    local stepW = btnW + padding
    local stepH = btnH + padding

    local showEmpty = s.alwaysShowButtons
    if showEmpty == nil then showEmpty = true end
    if info.isStance then showEmpty = false end

    local result = {}
    for i = 1, info.count do
        local btn = buttons[i]
        if not btn then break end
        if i > numIcons then
            result[i] = { x = 0, y = 0, w = btnW, h = btnH, show = false }
        else
            local col, row
            if isVertical then
                col = floor((i - 1) / stride)
                row = (i - 1) % stride
            else
                col = (i - 1) % stride
                row = floor((i - 1) / stride)
            end
            local xOff = col * stepW
            local yOff
            if isVertical then
                yOff = -(row * stepH)
            else
                if growUp then
                    local flippedRow = (numRows - 1) - row
                    yOff = -(flippedRow * stepH)
                else
                    yOff = -(row * stepH)
                end
            end
            local show = true
            if not showEmpty and not gridShown and not ButtonHasAction(btn, info.blizzBtnPrefix) then
                show = false
            end
            result[i] = { x = xOff, y = yOff, w = btnW, h = btnH, show = show }
        end
    end

    local totalCols = isVertical and numRows or stride
    local totalRows = isVertical and stride or numRows
    local frameW = SnapForScale(totalCols * btnW + (totalCols - 1) * padding, barScale)
    local frameH = SnapForScale(totalRows * btnH + (totalRows - 1) * padding, barScale)
    return result, max(frameW, 1), max(frameH, 1)
end

local function LayoutBar(key)
    if InCombatLockdown() then return end
    local info = BAR_LOOKUP[key]
    if not info then return end
    local frame = barFrames[key]
    local buttons = barButtons[key]
    if not frame or not buttons then return end

    local s = EAB.db.profile.bars[key]
    local barScale = s.barScale or 1.0
    if barScale < 0.1 then barScale = 0.1 end
    local numIcons = s.overrideNumIcons or s.numIcons or info.count
    if numIcons < 1 then numIcons = info.count end
    if numIcons > info.count then numIcons = info.count end
    if info.isStance then numIcons = GetNumShapeshiftForms() or info.count end

    local numRows = s.overrideNumRows or s.numRows or 1
    if numRows < 1 then numRows = 1 end

    local stride = ceil(numIcons / numRows)
    local padding = SnapForScale(s.buttonPadding or 2, barScale)
    local isVertical = (s.orientation == "vertical")
    local growUp = (s.growDirection or "up") == "up"
    local shape = s.buttonShape or "none"

    -- Button size: use the original button size captured during SetupBar.
    -- StanceButtons are 30x30; action buttons are 45x45.
    local base = barBaseSize[key]
    local btnW = base and base.w or 45
    local btnH = base and base.h or 45

    -- Shape expansion
    if shape ~= "none" and shape ~= "cropped" then
        btnW = btnW + SHAPE_BTN_EXPAND
        btnH = btnH + SHAPE_BTN_EXPAND
    end
    if shape == "cropped" then
        btnH = btnH * 0.80
    end

    -- Snap button dimensions for this bar's scale
    btnW = SnapForScale(btnW, barScale)
    btnH = SnapForScale(btnH, barScale)
    local stepW = btnW + padding
    local stepH = btnH + padding

    -- Show empty slots (stance bar always forces this off)
    local showEmpty = s.alwaysShowButtons
    if showEmpty == nil then showEmpty = true end
    if info.isStance then showEmpty = false end

    for i = 1, info.count do
        local btn = buttons[i]
        if not btn then break end

        if i > numIcons then
            btn:Hide()
            btn:SetAlpha(0)
        else
            -- Always keep buttons within the icon range shown. Visibility
            -- is controlled purely through alpha so page swaps during
            -- combat never leave buttons stuck in a hidden state.
            btn:Show()

            local col, row
            if isVertical then
                col = floor((i - 1) / stride)
                row = (i - 1) % stride
            else
                col = (i - 1) % stride
                row = floor((i - 1) / stride)
            end

            btn:ClearAllPoints()
            local xOff = col * stepW
            local yOff
            if isVertical then
                yOff = -(row * stepH)
            else
                if growUp then
                    local flippedRow = (numRows - 1) - row
                    yOff = -(flippedRow * stepH)
                else
                    yOff = -(row * stepH)
                end
            end
            btn:SetPoint("TOPLEFT", frame, "TOPLEFT", xOff, yOff)
            btn:SetSize(btnW, btnH)

            -- Resize the autocast overlay to match the button size
            if btn.AutoCastOverlay then
                btn.AutoCastOverlay:SetAllPoints(btn)
            end

            if not showEmpty and not gridShown and not ButtonHasAction(btn, info.blizzBtnPrefix) then
                btn:SetAlpha(0)
            else
                if not s.mouseoverEnabled then
                    btn:SetAlpha(1)
                end
            end
        end
    end

    -- Size the bar frame to encompass all visible buttons
    local totalCols = isVertical and numRows or stride
    local totalRows = isVertical and stride or numRows
    local frameW = totalCols * btnW + (totalCols - 1) * padding
    local frameH = totalRows * btnH + (totalRows - 1) * padding
    frame:SetSize(max(frameW, 1), max(frameH, 1))

    -- Set flyoutDirection on every button based on bar orientation and actual
    -- screen position. Divide the screen into thirds on each axis and pick the
    -- direction that opens away from the nearest screen edge.
    local flyDir
    do
        local cx, cy = frame:GetCenter()
        local uiW = UIParent:GetWidth()
        local uiH = UIParent:GetHeight()
        local uiScale = UIParent:GetEffectiveScale()
        local fScale  = frame:GetEffectiveScale()
        -- Convert to UIParent coordinate space
        if cx and cy then
            cx = cx * fScale / uiScale
            cy = cy * fScale / uiScale
        end
        if cx and cy then
            local thirdW = uiW / 3
            local thirdH = uiH / 3
            if isVertical then
                -- Vertical bar: flyout goes left if bar is in the right third, else right
                flyDir = (cx > thirdW * 2) and "LEFT" or "RIGHT"
            else
                -- Horizontal bar: flyout goes down if bar is in the top third, else up
                flyDir = (cy > thirdH * 2) and "DOWN" or "UP"
            end
        else
            -- Frame not yet on screen safe fallback
            flyDir = isVertical and "RIGHT" or "UP"
        end
    end
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn and not InCombatLockdown() then
            btn:SetAttribute("flyoutDirection", flyDir)
        end
    end
end

-------------------------------------------------------------------------------
--  Visual Customization Button Appearance
-------------------------------------------------------------------------------
local function HideSelfDeferred(self)
    -- Reuse a cached closure per frame to avoid allocation on every OnShow
    if not self._eabHideFn then
        self._eabHideFn = function()
            if self and not self:IsForbidden() then self:Hide() end
        end
    end
    C_Timer_After(0, self._eabHideFn)
end

local function HideBorder(button)
    if button.NormalTexture then
        button.NormalTexture:Hide()
        button.NormalTexture:SetAlpha(0)
    end
    if button.icon and button.IconMask then
        button.icon:RemoveMaskTexture(button.IconMask)
        -- Neutralize IconMask so Blizzard's UpdateButtonArt can never
        -- re-apply it visually (it calls icon:AddMaskTexture(self.IconMask)
        -- on combat transitions, bar page changes, etc.)
        button.IconMask:Hide()
        button.IconMask:SetTexture(nil)
        button.IconMask:ClearAllPoints()
        button.IconMask:SetSize(0.001, 0.001)
    end
end

local function SetSquareTexture(texture, texPath)
    if not texture then return end
    texture:SetAtlas(nil)
    texture:SetTexture(texPath)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:ClearAllPoints()
    texture:SetAllPoints(texture:GetParent())
end

local function HideTexture(texture)
    if not texture then return end
    texture:SetAlpha(0)
end

local function MakeButtonSquare(btn)
    if btn._eabSquared then return end
    HideBorder(btn)
    -- Ensure the button has GetPopupDirection for Blizzard's SpellFlyout system.
    -- ActionBarButtonTemplate may not always inherit this from FlyoutButtonMixin.
    if not btn.GetPopupDirection then
        btn.GetPopupDirection = function(self)
            return self:GetAttribute("flyoutDirection") or "UP"
        end
    end
    if btn.NormalTexture and not btn._eabNTHooked then
        btn.NormalTexture:HookScript("OnShow", HideSelfDeferred)
        btn._eabNTHooked = true
    end
    if not btn._eabShowHooked then
        -- Cache the deferred closure per button to avoid allocation on every OnShow
        local hideBorderFn = function()
            if btn and not btn:IsForbidden() then HideBorder(btn) end
        end
        btn:HookScript("OnShow", function() C_Timer_After(0, hideBorderFn) end)
        btn._eabShowHooked = true
    end
    -- Hook UpdateButtonArt to re-neutralize IconMask after Blizzard re-adds it
    -- (fires on combat transitions, bar page changes, bonus bar swaps, etc.)
    -- Deferred via C_Timer to avoid tainting Blizzard's secure call chains.
    if not btn._eabArtHooked and btn.UpdateButtonArt then
        hooksecurefunc(btn, "UpdateButtonArt", function(self)
            if not self._eabArtFn then
                self._eabArtFn = function()
                    if self and not self:IsForbidden() then HideBorder(self) end
                end
            end
            C_Timer_After(0, self._eabArtFn)
        end)
        btn._eabArtHooked = true
    end
    SetSquareTexture(btn.HighlightTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(btn.NewActionTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(btn.PushedTexture, HIGHLIGHT_TEXTURES[2])
    SetSquareTexture(btn.Flash, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(btn.CheckedTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(btn.Border, HIGHLIGHT_TEXTURES[1])
    HideTexture(btn.FlyoutBorderShadow)
    if btn.cooldown then
        btn.cooldown:ClearAllPoints()
        btn.cooldown:SetAllPoints(btn)
    end
    if btn.SpellCastAnimFrame and not btn._eabCastHooked then
        btn.SpellCastAnimFrame:HookScript("OnShow", function(self)
            local prof = EAB.db and EAB.db.profile
            if not prof then return end
            if not prof.hideCastingAnimations and not btn._eabShapeApplied and not btn._eabCropped then return end
            self:SetAlpha(0)
            if not self._eabHideFn then
                self._eabHideFn = function()
                    if self and not self:IsForbidden() then self:Hide(); self:SetAlpha(1) end
                end
            end
            C_Timer_After(0, self._eabHideFn)
        end)
        btn._eabCastHooked = true
    end
    if btn.InterruptDisplay and not btn._eabIntHooked then
        btn.InterruptDisplay:HookScript("OnShow", function(self)
            local prof = EAB.db and EAB.db.profile
            if not prof then return end
            if not prof.hideCastingAnimations and not btn._eabShapeApplied and not btn._eabCropped then return end
            self:SetAlpha(0)
            if not self._eabHideFn then
                self._eabHideFn = function()
                    if self and not self:IsForbidden() then self:Hide(); self:SetAlpha(1) end
                end
            end
            C_Timer_After(0, self._eabHideFn)
        end)
        btn._eabIntHooked = true
    end
    if btn.SlotBackground then
        btn.SlotBackground:Hide()
        if not btn._eabSlotBG then
            local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
            bg:SetAllPoints(btn)
            bg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
            btn._eabSlotBG = bg
        end
    end
    if btn.SlotArt then btn.SlotArt:Hide() end
    -- Hook Border to suppress Blizzard's item quality overlay (Dragonflight+).
    -- Blizzard calls Border:SetAtlas() to show quality colors on consumables.
    -- We re-apply our square texture whenever Blizzard tries to set an atlas,
    -- and hide it when a custom shape is active (shape border handles visuals).
    if btn.Border and not btn._eabBorderHooked then
        local _borderGuard = false
        hooksecurefunc(btn.Border, "SetAtlas", function(self)
            if _borderGuard then return end
            _borderGuard = true
            if btn._eabShapeApplied then
                self:Hide()
            else
                self:SetAtlas(nil)
                self:SetTexture(HIGHLIGHT_TEXTURES[1])
                self:SetTexCoord(0, 1, 0, 1)
                self:ClearAllPoints()
                self:SetAllPoints(btn)
            end
            _borderGuard = false
        end)
        hooksecurefunc(btn.Border, "Show", function(self)
            if btn._eabShapeApplied then
                if not self._eabBorderHideFn then
                    self._eabBorderHideFn = function()
                        if self and not self:IsForbidden() then self:Hide() end
                    end
                end
                C_Timer_After(0, self._eabBorderHideFn)
            end
        end)
        btn._eabBorderHooked = true
    end
    btn._eabSquared = true
end

local function EnsureBorders(btn)
    if btn._eabBorders then return btn._eabBorders end
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then
        PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", -1)
        btn._eabBorders = btn._ppBorders
    end
    return btn._eabBorders
end

local function ApplyButtonBorders(btn, on, cr, cg, cb, ca, sz, zoom)
    MakeButtonSquare(btn)
    local PP = EllesmereUI and EllesmereUI.PP
    if not on then
        if btn._eabBorders then
            PP.HideBorder(btn)
        end
        btn._eabBorderKey = nil
    else
        local es = btn:GetEffectiveScale()
        local stateKey = cr * 1000000 + cg * 10000 + cb * 100 + ca + sz * 0.001 + zoom * 10000000 + es * 0.0001
        if btn._eabBorderKey == stateKey then return end
        btn._eabBorderKey = stateKey
        EnsureBorders(btn)
        PP.UpdateBorder(btn, sz, cr, cg, cb, ca)
        local b = btn._eabBorders
        if b then
            if not (btn._eabShapeMask and btn._eabShapeMask:IsShown()) then
                PP.ShowBorder(btn)
            end
        end
    end
    if zoom > 0 then
        local icon = btn.icon or btn.Icon
        if icon and icon.SetTexCoord and not (btn._eabShapeMask and btn._eabShapeMask:IsShown()) and not btn._eabCropped then
            icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
        end
    end
end

-------------------------------------------------------------------------------
--  Shape Masking
-------------------------------------------------------------------------------
local function MaskFrameTextures(frame, mask)
    if not frame or not mask then return end
    for _, region in ipairs({frame:GetRegions()}) do
        if region.AddMaskTexture then
            pcall(region.AddMaskTexture, region, mask)
        end
    end
end

local function UnmaskFrameTextures(frame, mask)
    if not frame or not mask then return end
    for _, region in ipairs({frame:GetRegions()}) do
        if region.RemoveMaskTexture then
            pcall(region.RemoveMaskTexture, region, mask)
        end
    end
end

local function ApplyShapeToButton(btn, shape, brdOn, brdR, brdG, brdB, brdA, brdSize, zoom)
    if shape == "none" or shape == "cropped" then
        -- Remove shape mask if previously applied
        if btn._eabShapeMask then
            local mask = btn._eabShapeMask
            local icon = btn.icon or btn.Icon
            if icon then pcall(icon.RemoveMaskTexture, icon, mask) end
            -- Unmask slot BG from main mask
            if btn._eabSlotBG then pcall(btn._eabSlotBG.RemoveMaskTexture, btn._eabSlotBG, mask) end
            -- Unmask cooldown frames and restore default swipe
            if btn.cooldown and not btn.cooldown:IsForbidden() then
                pcall(btn.cooldown.RemoveMaskTexture, btn.cooldown, mask)
                pcall(btn.cooldown.SetSwipeTexture, btn.cooldown, "")
            end
            if btn.chargeCooldown and not btn.chargeCooldown:IsForbidden() then
                pcall(btn.chargeCooldown.RemoveMaskTexture, btn.chargeCooldown, mask)
                pcall(btn.chargeCooldown.SetSwipeTexture, btn.chargeCooldown, "")
            end
            -- Neutralize the mask so it can't clip anything even if a stale
            -- reference remains (clear texture + shrink to zero)
            mask:SetTexture(nil)
            mask:ClearAllPoints()
            mask:SetSize(0.001, 0.001)
            mask:Hide()
        end
        -- Remove overlay mask if it existed
        if btn._eabOverlayMask then
            local omask = btn._eabOverlayMask
            if btn.HighlightTexture then pcall(btn.HighlightTexture.RemoveMaskTexture, btn.HighlightTexture, omask) end
            if btn.PushedTexture then pcall(btn.PushedTexture.RemoveMaskTexture, btn.PushedTexture, omask) end
            if btn.CheckedTexture then pcall(btn.CheckedTexture.RemoveMaskTexture, btn.CheckedTexture, omask) end
            if btn.NewActionTexture then pcall(btn.NewActionTexture.RemoveMaskTexture, btn.NewActionTexture, omask) end
            if btn.Flash then pcall(btn.Flash.RemoveMaskTexture, btn.Flash, omask) end
            if btn.Border then pcall(btn.Border.RemoveMaskTexture, btn.Border, omask) end
            local nt = btn.NormalTexture or btn:GetNormalTexture()
            if nt then pcall(nt.RemoveMaskTexture, nt, omask) end
            if btn.SpellActivationAlert then
                UnmaskFrameTextures(btn.SpellActivationAlert, omask)
                btn.SpellActivationAlert._eabShapeMasked = nil
            end
            omask:SetTexture(nil)
            omask:ClearAllPoints()
            omask:SetSize(0.001, 0.001)
            omask:Hide()
        elseif btn._eabShapeMask then
            -- Overlays were on the main mask (no border case) clean them off
            local mask = btn._eabShapeMask
            if btn.HighlightTexture then pcall(btn.HighlightTexture.RemoveMaskTexture, btn.HighlightTexture, mask) end
            if btn.PushedTexture then pcall(btn.PushedTexture.RemoveMaskTexture, btn.PushedTexture, mask) end
            if btn.CheckedTexture then pcall(btn.CheckedTexture.RemoveMaskTexture, btn.CheckedTexture, mask) end
            if btn.NewActionTexture then pcall(btn.NewActionTexture.RemoveMaskTexture, btn.NewActionTexture, mask) end
            if btn.Flash then pcall(btn.Flash.RemoveMaskTexture, btn.Flash, mask) end
            if btn.Border then pcall(btn.Border.RemoveMaskTexture, btn.Border, mask) end
            local nt = btn.NormalTexture or btn:GetNormalTexture()
            if nt then pcall(nt.RemoveMaskTexture, nt, mask) end
            if btn.SpellActivationAlert then
                UnmaskFrameTextures(btn.SpellActivationAlert, mask)
                btn.SpellActivationAlert._eabShapeMasked = nil
            end
        end
        -- Clean up glow wrapper mask
        if btn._eabGlowWrapper then
            local mask = btn._eabShapeMask
            if mask then UnmaskFrameTextures(btn._eabGlowWrapper, mask) end
            if btn._eabGlowWrapper._eabOwnMask then
                UnmaskFrameTextures(btn._eabGlowWrapper, btn._eabGlowWrapper._eabOwnMask)
                btn._eabGlowWrapper._eabOwnMask:Hide()
            end
        end
        if btn._eabShapeBorder then
            btn._eabShapeBorder:Hide()
            btn._eabShapeBorder._eabWantsShow = false
            btn._eabShapeBorder:SetTexture(nil)
        end
        -- Clear shape tracking flags
        btn._eabShapeApplied = nil
        btn._eabShapeName = nil
        btn._eabShapeMaskPath = nil
        -- Restore cooldown edge to default (non-circular, not forced on)
        if btn.cooldown and not btn.cooldown:IsForbidden() then
            if btn.cooldown.SetUseCircularEdge then pcall(btn.cooldown.SetUseCircularEdge, btn.cooldown, false) end
        end
        if btn.chargeCooldown and not btn.chargeCooldown:IsForbidden() then
            if btn.chargeCooldown.SetUseCircularEdge then pcall(btn.chargeCooldown.SetUseCircularEdge, btn.chargeCooldown, false) end
        end
        -- Restore icon
        local icon = btn.icon or btn.Icon
        if icon then
            icon:ClearAllPoints()
            icon:SetSize(0, 0)
            icon:SetAllPoints(btn)
            if shape == "cropped" then
                local z = (zoom or 0)
                icon:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
                btn._eabCropped = true
            else
                btn._eabCropped = false
                if zoom and zoom > 0 then
                    icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                else
                    icon:SetTexCoord(0, 1, 0, 1)
                end
            end
        end
        -- Show square borders
        if btn._eabBorders then
            PP.ShowBorder(btn)
        end
        -- Re-enable Blizzard's Border texture (was hidden for custom shapes)
        if btn.Border then
            SetSquareTexture(btn.Border, HIGHLIGHT_TEXTURES[1])
        end
        return
    end

    -- Custom shape
    local maskTex = SHAPE_MASKS[shape]
    if not maskTex then return end

    if not btn._eabShapeMask then
        btn._eabShapeMask = btn:CreateMaskTexture()
    end
    local mask = btn._eabShapeMask
    mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:Show()

    local icon = btn.icon or btn.Icon

    -- Always remove existing mask references before re-adding
    -- (AddMaskTexture is additive; stale references cause shape-inside-shape)
    if icon then pcall(icon.RemoveMaskTexture, icon, mask) end
    if btn._eabSlotBG then pcall(btn._eabSlotBG.RemoveMaskTexture, btn._eabSlotBG, mask) end
    if btn.cooldown and not btn.cooldown:IsForbidden() then
        pcall(btn.cooldown.RemoveMaskTexture, btn.cooldown, mask)
    end
    if btn.chargeCooldown and not btn.chargeCooldown:IsForbidden() then
        pcall(btn.chargeCooldown.RemoveMaskTexture, btn.chargeCooldown, mask)
    end
    do
        -- Remove overlay textures from whichever mask they were on
        local omask = btn._eabOverlayMask or mask
        if btn.HighlightTexture then pcall(btn.HighlightTexture.RemoveMaskTexture, btn.HighlightTexture, omask) end
        if btn.PushedTexture then pcall(btn.PushedTexture.RemoveMaskTexture, btn.PushedTexture, omask) end
        if btn.CheckedTexture then pcall(btn.CheckedTexture.RemoveMaskTexture, btn.CheckedTexture, omask) end
        if btn.NewActionTexture then pcall(btn.NewActionTexture.RemoveMaskTexture, btn.NewActionTexture, omask) end
        if btn.Flash then pcall(btn.Flash.RemoveMaskTexture, btn.Flash, omask) end
        if btn.Border then pcall(btn.Border.RemoveMaskTexture, btn.Border, omask) end
        local nt2 = btn.NormalTexture or btn:GetNormalTexture()
        if nt2 then pcall(nt2.RemoveMaskTexture, nt2, omask) end
        if btn.SpellActivationAlert then
            UnmaskFrameTextures(btn.SpellActivationAlert, omask)
            btn.SpellActivationAlert._eabShapeMasked = nil
        end
        -- Also clean from main mask if overlay mask was separate
        if btn._eabOverlayMask and btn._eabOverlayMask ~= mask then
            if btn.HighlightTexture then pcall(btn.HighlightTexture.RemoveMaskTexture, btn.HighlightTexture, mask) end
            if btn.PushedTexture then pcall(btn.PushedTexture.RemoveMaskTexture, btn.PushedTexture, mask) end
            if btn.CheckedTexture then pcall(btn.CheckedTexture.RemoveMaskTexture, btn.CheckedTexture, mask) end
            if btn.NewActionTexture then pcall(btn.NewActionTexture.RemoveMaskTexture, btn.NewActionTexture, mask) end
            if btn.Flash then pcall(btn.Flash.RemoveMaskTexture, btn.Flash, mask) end
            if btn.Border then pcall(btn.Border.RemoveMaskTexture, btn.Border, mask) end
            if nt2 then pcall(nt2.RemoveMaskTexture, nt2, mask) end
        end
        if btn._eabGlowWrapper then
            UnmaskFrameTextures(btn._eabGlowWrapper, mask)
            if btn._eabGlowWrapper._eabOwnMask then
                UnmaskFrameTextures(btn._eabGlowWrapper, btn._eabGlowWrapper._eabOwnMask)
            end
        end
    end

    -- Apply mask to icon
    if icon then icon:AddMaskTexture(mask) end

    -- Determine which mask to use for overlay/animation textures
    -- When border is strong (brdSize >= 1), use a separate inset mask so
    -- animations stop at the border edge instead of bleeding past it.
    local overlayMask
    if brdSize and brdSize >= 1 then
        if not btn._eabOverlayMask then
            btn._eabOverlayMask = btn:CreateMaskTexture()
        end
        overlayMask = btn._eabOverlayMask
        overlayMask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        overlayMask:ClearAllPoints()
        local inset = 3
        PP.Point(overlayMask, "TOPLEFT", btn, "TOPLEFT", inset, -inset)
        PP.Point(overlayMask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
        overlayMask:Show()
    else
        -- No border overlays share the main mask, hide overlay mask if it exists
        if btn._eabOverlayMask then btn._eabOverlayMask:Hide() end
        overlayMask = mask
    end

    -- Apply overlay mask to all button overlay textures
    if btn.HighlightTexture then pcall(btn.HighlightTexture.AddMaskTexture, btn.HighlightTexture, overlayMask) end
    if btn.PushedTexture then pcall(btn.PushedTexture.AddMaskTexture, btn.PushedTexture, overlayMask) end
    if btn.CheckedTexture then pcall(btn.CheckedTexture.AddMaskTexture, btn.CheckedTexture, overlayMask) end
    if btn.NewActionTexture then pcall(btn.NewActionTexture.AddMaskTexture, btn.NewActionTexture, overlayMask) end
    if btn.Flash then pcall(btn.Flash.AddMaskTexture, btn.Flash, overlayMask) end
    -- Hide Blizzard's item quality border (Dragonflight+) for custom shapes
    -- it uses a round atlas that doesn't match non-square shapes.
    if btn.Border then
        btn.Border:Hide()
    end
    if btn._eabSlotBG then pcall(btn._eabSlotBG.AddMaskTexture, btn._eabSlotBG, mask) end
    local nt = btn.NormalTexture or btn:GetNormalTexture()
    if nt then pcall(nt.AddMaskTexture, nt, overlayMask) end

    -- Expand icon beyond button frame
    local shapeOffset = SHAPE_ICON_EXPAND_OFFSETS[shape] or 0
    local shapeDefault = (SHAPE_ZOOM_DEFAULTS[shape] or 6.0) / 100
    local iconExp = SHAPE_ICON_EXPAND + shapeOffset + ((zoom or 0) - shapeDefault) * 200
    if iconExp < 0 then iconExp = 0 end
    local halfIE = iconExp / 2
    if icon then
        icon:ClearAllPoints()
        PP.Point(icon, "TOPLEFT", btn, "TOPLEFT", -halfIE, halfIE)
        PP.Point(icon, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", halfIE, -halfIE)
    end

    -- Mask inset for border
    mask:ClearAllPoints()
    if brdSize and brdSize >= 1 then
        PP.Point(mask, "TOPLEFT", btn, "TOPLEFT", 1, -1)
        PP.Point(mask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    else
        mask:SetAllPoints(btn)
    end

    -- Expand texcoords
    local insetPx = SHAPE_INSETS[shape] or 17
    local visRatio = (128 - 2 * insetPx) / 128
    local expand = ((1 / visRatio) - 1) * 0.5
    if icon then icon:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand) end

    -- Hide square borders
    if btn._eabBorders then
        PP.HideBorder(btn)
    end

    -- Shape border texture
    if not btn._eabShapeBorder then
        btn._eabShapeBorder = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    end
    local borderTex = btn._eabShapeBorder
    pcall(borderTex.RemoveMaskTexture, borderTex, mask)
    borderTex:ClearAllPoints()
    borderTex:SetAllPoints(btn)
    if brdOn and SHAPE_BORDERS[shape] then
        borderTex:SetTexture(SHAPE_BORDERS[shape])
        borderTex:SetVertexColor(brdR, brdG, brdB, brdA)
        borderTex:Show()
        borderTex._eabWantsShow = true
    else
        borderTex:Hide()
        borderTex._eabWantsShow = false
    end

    -- Apply mask to cooldown frames so swipe follows the shape
    if btn.cooldown and not btn.cooldown:IsForbidden() then
        pcall(btn.cooldown.AddMaskTexture, btn.cooldown, mask)
        if btn.cooldown.SetSwipeTexture then
            pcall(btn.cooldown.SetSwipeTexture, btn.cooldown, maskTex)
        end
    end
    if btn.chargeCooldown and not btn.chargeCooldown:IsForbidden() then
        pcall(btn.chargeCooldown.AddMaskTexture, btn.chargeCooldown, mask)
        if btn.chargeCooldown.SetSwipeTexture then
            pcall(btn.chargeCooldown.SetSwipeTexture, btn.chargeCooldown, maskTex)
        end
    end

    -- Mask proc glow animation frames
    if btn.SpellActivationAlert then
        MaskFrameTextures(btn.SpellActivationAlert, overlayMask)
        btn.SpellActivationAlert._eabShapeMasked = true
    end
    if btn._eabGlowWrapper then
        local w = btn._eabGlowWrapper
        if not w._eabOwnMask then
            w._eabOwnMask = w:CreateMaskTexture()
        end
        w._eabOwnMask:ClearAllPoints()
        PP.Point(w._eabOwnMask, "TOPLEFT", btn, "TOPLEFT", 1, -1)
        PP.Point(w._eabOwnMask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        w._eabOwnMask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        w._eabOwnMask:Show()
        MaskFrameTextures(w, w._eabOwnMask)
    end

    -- Store shape tracking flags for cooldown edge system
    btn._eabShapeApplied = true
    btn._eabShapeName = shape
    btn._eabShapeMaskPath = maskTex

    -- Apply shape-specific cooldown edge: circular edge for non-square shapes,
    -- per-shape scale, custom texture + current color.
    local shapeEdgeScale = SHAPE_EDGE_SCALES[shape] or 0.60
    local useCircular = (shape ~= "square" and shape ~= "csquare")
    do
        local edgeTex = "Interface\\AddOns\\EllesmereUIActionBars\\Media\\edge.png"
        local p = EAB.db and EAB.db.profile
        local cr, cg, cb, ca = 0.973, 0.839, 0.604, 1
        if p then
            if p.cooldownEdgeUseClassColor then
                local _, cls = UnitClass("player")
                local cc = RAID_CLASS_COLORS[cls]
                if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                ca = (p.cooldownEdgeColor and p.cooldownEdgeColor.a) or 1
            elseif p.cooldownEdgeColor then
                cr = p.cooldownEdgeColor.r or cr
                cg = p.cooldownEdgeColor.g or cg
                cb = p.cooldownEdgeColor.b or cb
                ca = p.cooldownEdgeColor.a or ca
            end
        end
        for _, cd in ipairs({btn.cooldown, btn.chargeCooldown}) do
            if cd and not cd:IsForbidden() then
                if cd.SetEdgeTexture then pcall(cd.SetEdgeTexture, cd, edgeTex) end
                if cd.SetEdgeColor then pcall(cd.SetEdgeColor, cd, cr, cg, cb, ca) end
                if cd.SetUseCircularEdge then pcall(cd.SetUseCircularEdge, cd, useCircular) end
                if cd.SetEdgeScale then pcall(cd.SetEdgeScale, cd, shapeEdgeScale) end
            end
        end
    end

    btn._eabCropped = false
end

-------------------------------------------------------------------------------
--  EAB Methods Apply functions called by the options UI
-------------------------------------------------------------------------------
function EAB:ApplyBordersForBar(barKey)
    if not self.db then return end
    if not self.db.profile.squareIcons then return end
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local c = s.borderColor or { r=0, g=0, b=0, a=1 }
    local sz = ResolveBorderThickness(s)
    local on = sz > 0
    local cr, cg, cb, ca = c.r, c.g, c.b, c.a or 1
    if s.borderClassColor then
        local _, classToken = UnitClass("player")
        if classToken then
            local cc = RAID_CLASS_COLORS[classToken]
            if cc then cr, cg, cb = cc.r, cc.g, cc.b end
        end
    end
    local zoom = ((s.iconZoom or self.db.profile.iconZoom or 5.5)) / 100
    local buttons = barButtons[barKey]
    if not buttons then return end
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn then
            btn._eabBarKey = barKey
            ApplyButtonBorders(btn, on, cr, cg, cb, ca, sz, zoom)
        end
    end
end

function EAB:ApplyBorders()
    if not self.db then return end
    for _, info in ipairs(BAR_CONFIG) do
        self:ApplyBordersForBar(info.key)
    end
end

function EAB:ApplyShapesForBar(barKey)
    if InCombatLockdown() then return end
    if not self.db then return end
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local shape = s.buttonShape or "none"
    local zoom = ((s.iconZoom or self.db.profile.iconZoom or 5.5)) / 100
    local brdSz = ResolveBorderThickness(s)
    local brdOn = brdSz > 0
    local brdColor = s.shapeBorderColor or s.borderColor or { r=0, g=0, b=0, a=1 }
    local brdR, brdG, brdB, brdA = brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
    if s.borderClassColor then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then brdR, brdG, brdB = cc.r, cc.g, cc.b end end
    end
    local buttons = barButtons[barKey]
    if not buttons then return end
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn then
            ApplyShapeToButton(btn, shape, brdOn, brdR, brdG, brdB, brdA, brdSz, zoom)
        end
    end
    LayoutBar(barKey)
end

function EAB:ApplyShapes()
    if not self.db then return end
    for _, info in ipairs(BAR_CONFIG) do
        self:ApplyShapesForBar(info.key)
    end
end

function EAB:ApplyScaleForBar(barKey)
    if InCombatLockdown() then return end
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local frame = barFrames[barKey]
    if not frame then return end
    local scale = s.barScale or 1.0
    if scale < 0.1 then scale = 0.1 end
    local prev = frame._eabLastScale
    frame:SetScale(scale)
    -- Only re-snap borders when the scale actually changed (avoids iterating
    -- every registered border in the UI on bar-paging events where scale is
    -- unchanged).
    if prev ~= scale then
        frame._eabLastScale = scale
        local ppRef = EllesmereUI and EllesmereUI.PP
        if ppRef and ppRef.ResnapAllBorders then ppRef.ResnapAllBorders() end
    end
end

-- Same as ApplyScaleForBar but preserves the bar's visual center.
-- Call this from the options slider; the normal ApplyScaleForBar is used
-- during layout/init where the bar will be re-positioned anyway.
function EAB:ApplyScalePreserveCenter(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local frame = barFrames[barKey]
    if not frame then return end
    local scale = s.barScale or 1.0
    if scale < 0.1 then scale = 0.1 end

    local oldLeft, oldRight = frame:GetLeft(), frame:GetRight()
    local oldTop, oldBottom = frame:GetTop(), frame:GetBottom()
    if oldLeft and oldRight and oldTop and oldBottom then
        local uiS = UIParent:GetEffectiveScale()
        local oldS = frame:GetEffectiveScale()
        local oldCX = (oldLeft + oldRight) * 0.5 * oldS / uiS
        local oldCY = (oldTop + oldBottom) * 0.5 * oldS / uiS
        frame:SetScale(scale)
        local newS = frame:GetEffectiveScale()
        local uiH = UIParent:GetHeight()
        pcall(function()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "TOPLEFT",
                oldCX * uiS / newS,
                (oldCY - uiH) * uiS / newS)
        end)
        -- Persist the new anchor
        local pt, _, rpt, px, py = frame:GetPoint(1)
        if pt then
            self.db.profile.barPositions[barKey] = {
                point = pt, relPoint = rpt, x = px, y = py,
            }
        end
    else
        frame:SetScale(scale)
    end
    -- Re-snap borders after scale change so they stay pixel-perfect
    local PP = EllesmereUI and EllesmereUI.PP
    if PP and PP.ResnapAllBorders then PP.ResnapAllBorders() end
end

function EAB:ApplyPaddingForBar(barKey)
    LayoutBar(barKey)
end

function EAB:ApplyIconRowOverrides(barKey)
    LayoutBar(barKey)
    self:ApplyAlwaysShowButtons(barKey)
end

function EAB:ApplyBarOpacity(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local frame = barFrames[barKey]
    if not frame then return end
    if not s.mouseoverEnabled then
        frame:SetAlpha(s.mouseoverAlpha or 1)
    end
end

function EAB:BarSupportsOrientation(barKey)
    return BAR_LOOKUP[barKey] ~= nil
end

function EAB:GetOrientationForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return true end
    return s.orientation ~= "vertical"
end

function EAB:SetOrientationForBar(barKey, isHorizontal)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    s.orientation = isHorizontal and "horizontal" or "vertical"
    LayoutBar(barKey)
end

-------------------------------------------------------------------------------
--  Font / Keybind Text
-------------------------------------------------------------------------------
function EAB:ApplyFontsForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local buttons = barButtons[barKey]
    if not buttons then return end
    local fontPath = EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("actionBars") or FONT_PATH
    local hideKB = s.hideKeybind
    local kbSize = s.keybindFontSize or 12
    -- Stance/pet bar buttons are smaller (30px vs 45px) shrink keybind text
    -- by 2px so it doesn't overwhelm the icon.
    local info = BAR_LOOKUP[barKey]
    if info and (info.isStance or info.isPetBar) then kbSize = max(kbSize - 2, 6) end
    local kbColor = s.keybindFontColor or { r=1, g=1, b=1 }
    local ctSize = s.countFontSize or 12
    local ctColor = s.countFontColor or { r=1, g=1, b=1 }
    local kbOX = s.keybindOffsetX or 0
    local kbOY = s.keybindOffsetY or 0
    local ctOX = s.countOffsetX or 0
    local ctOY = s.countOffsetY or 0
    local RANGE_INDICATOR = RANGE_INDICATOR or "\226\128\162"

    for i = 1, #buttons do
        local btn = buttons[i]
        if not btn then break end

        -- Keybind text
        local hk = btn.HotKey
        if hk then
            if hideKB then
                hk:SetText("")
                hk:Hide()
            else
                -- Get binding text
                local bindingAction
                local info = BAR_LOOKUP[barKey]
                if info and not info.isStance and not info.isPetBar then
                    if barKey == "MainBar" then
                        bindingAction = "ACTIONBUTTON" .. i
                    else
                        local bindPrefix = BINDING_MAP[barKey]
                        if bindPrefix then
                            bindingAction = bindPrefix .. i
                        end
                    end
                elseif info and info.isStance then
                    bindingAction = "SHAPESHIFTBUTTON" .. i
                elseif info and info.isPetBar then
                    bindingAction = "BONUSACTIONBUTTON" .. i
                end

                local key1 = bindingAction and GetBindingKey(bindingAction)
                local text = key1 and FormatHotkeyText(key1) or ""
                if text == RANGE_INDICATOR or text == "\226\128\162" then text = "" end
                hk:SetText(text)
                hk:Show()
                hk:SetFont(fontPath, kbSize, "OUTLINE")
                hk:SetShadowOffset(0, 0)
                hk:SetTextColor(kbColor.r, kbColor.g, kbColor.b)
                hk:ClearAllPoints()
                hk:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -1 + kbOX, -3 + kbOY)
                hk:SetPoint("TOPLEFT", btn, "TOPLEFT", 4 + kbOX, -3 + kbOY)
                hk:SetJustifyH("RIGHT")
            end
        end

        -- Count / charges text
        local ct = btn.Count
        if ct then
            ct:SetFont(fontPath, ctSize, "OUTLINE")
            ct:SetShadowOffset(0, 0)
            ct:SetTextColor(ctColor.r, ctColor.g, ctColor.b)
            ct:ClearAllPoints()
            ct:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1 + ctOX, 4 + ctOY)
        end
    end
end

function EAB:ApplyFonts()
    for _, info in ipairs(BAR_CONFIG) do
        self:ApplyFontsForBar(info.key)
    end
end

-------------------------------------------------------------------------------
--  Background Texture
-------------------------------------------------------------------------------
local barBackgrounds = {}  -- [barKey] = texture

function EAB:ApplyBackgroundForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local frame = barFrames[barKey]
    if not frame then return end

    if not s.bgEnabled then
        if barBackgrounds[barKey] then barBackgrounds[barKey]:Hide() end
        return
    end

    local bg = barBackgrounds[barKey]
    if not bg then
        bg = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        barBackgrounds[barKey] = bg
    end

    local c = s.bgColor or { r=0, g=0, b=0, a=0.5 }
    bg:SetColorTexture(c.r, c.g, c.b, c.a)
    local padX = s.bgPadX or 0
    local padY = s.bgPadY or 0
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -padX, padY)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", padX, -padY)
    bg:Show()
end

-------------------------------------------------------------------------------
--  Always Show Buttons
-------------------------------------------------------------------------------
function EAB:ApplyAlwaysShowButtons(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local info = BAR_LOOKUP[barKey]
    if not info then return end
    local buttons = barButtons[barKey]
    if not buttons then return end
    local showEmpty = s.alwaysShowButtons
    if showEmpty == nil then showEmpty = true end
    -- Stance bar always hides empty slots (count is dynamic per class)
    if info.isStance then showEmpty = false end

    -- During a spell drag (grid shown), keep everything visible
    if gridShown then return end

    -- Respect icon cutoff
    local numIcons = s.overrideNumIcons or s.numIcons or info.count
    if numIcons < 1 then numIcons = info.count end
    if numIcons > info.count then numIcons = info.count end
    if info.isStance then numIcons = GetNumShapeshiftForms() or info.count end

    local clickable = not s.clickThrough
    local lastVisible = 0
    for i = 1, numIcons do
        local btn = buttons[i]
        if btn then
            local hasAction = ButtonHasAction(btn, info.blizzBtnPrefix)
            local visible = showEmpty or hasAction

            if btn._eabSlotBG then
                btn._eabSlotBG:SetShown(visible)
            end
            if btn._eabBorders and not (btn._eabShapeMask and btn._eabShapeMask:IsShown()) then
                btn._eabBorders:SetShown(visible)
            end
            if btn._eabShapeBorder then
                btn._eabShapeBorder:SetShown(visible and btn._eabShapeBorder._eabWantsShow == true)
            end

            if not visible then
                btn:SetAlpha(0)
                -- Invisible empty slots should not catch mouse events
                SafeEnableMouse(btn, false)
            else
                if not s.mouseoverEnabled then
                    btn:SetAlpha(1)
                end
                -- Restore mouse state based on bar's click-through setting
                SafeEnableMouse(btn, clickable)
                lastVisible = i
            end
        end
    end
    -- Hide buttons beyond cutoff
    for i = numIcons + 1, #buttons do
        local btn = buttons[i]
        if btn then
            btn:SetAlpha(0)
            if not InCombatLockdown() then btn:Hide() end
        end
    end

    -- Note: frame size is left as-is from LayoutBar.  The mouseover
    -- OnEnter handler already checks cursor proximity to visible buttons,
    -- so shrinking the frame is unnecessary and can misposition bars
    -- whose anchor point isn't TOPLEFT.
end

-------------------------------------------------------------------------------
--  Out-of-Range Icon Coloring
--
--  Uses the retail ACTION_RANGE_CHECK_UPDATE event to tint action button
--  icons when the target is out of range.  Each slot is opted-in via
--  C_ActionBar.EnableActionRangeCheck so the client fires the event only
--  for slots we care about.
-------------------------------------------------------------------------------
local _rangeSlots = {}          -- [actionSlot] = true  (slots with range checking enabled)
local _rangeOutOfRange = {}     -- [actionSlot] = true  (currently out of range)
local _rangeEventFrame          -- lazy-created event frame
local _rangeSlotPending = false -- debounce for per-slot range re-enable

-- Resolve the action slot for a button (handles paging for MainBar)
local function GetButtonActionSlot(btn)
    if not btn then return nil end
    local action = btn.action
    if action and type(action) == "number" and action > 0 then return action end
    return nil
end

-- Apply or remove the range tint on a single button
local function ApplyRangeTint(btn, outOfRange, barSettings)
    local ico = btn.icon or btn.Icon
    if not ico then return end
    if outOfRange and barSettings.outOfRangeColoring then
        local c = barSettings.outOfRangeColor or { r = 0.7, g = 0.2, b = 0.2 }
        ico:SetVertexColor(c.r, c.g, c.b)
        btn._eabRangeTinted = true
    elseif btn._eabRangeTinted then
        ico:SetVertexColor(1, 1, 1)
        btn._eabRangeTinted = nil
    end
end

-- Enable range checking for all active button slots on a bar
local function EnableRangeCheckForBar(barKey)
    local buttons = barButtons[barKey]
    if not buttons then return end
    local s = EAB.db.profile.bars[barKey]
    if not s or not s.outOfRangeColoring then return end
    for _, btn in ipairs(buttons) do
        local slot = GetButtonActionSlot(btn)
        if slot and not _rangeSlots[slot] then
            _rangeSlots[slot] = true
            if C_ActionBar and C_ActionBar.EnableActionRangeCheck then
                pcall(C_ActionBar.EnableActionRangeCheck, slot, true)
            end
        end
    end
end

-- Disable range checking for all slots on a bar and clear tints
local function DisableRangeCheckForBar(barKey)
    local buttons = barButtons[barKey]
    if not buttons then return end
    local s = EAB.db.profile.bars[barKey]
    for _, btn in ipairs(buttons) do
        local slot = GetButtonActionSlot(btn)
        if slot and _rangeSlots[slot] then
            _rangeSlots[slot] = nil
            _rangeOutOfRange[slot] = nil
            if C_ActionBar and C_ActionBar.EnableActionRangeCheck then
                pcall(C_ActionBar.EnableActionRangeCheck, slot, false)
            end
        end
        if btn._eabRangeTinted then
            local ico = btn.icon or btn.Icon
            if ico then ico:SetVertexColor(1, 1, 1) end
            btn._eabRangeTinted = nil
        end
    end
end

-- Refresh range state for all bars (called from ApplyAll and on setting change)
function EAB:ApplyRangeColoring()
    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local s = self.db.profile.bars[key]
        if s and s.outOfRangeColoring then
            EnableRangeCheckForBar(key)
        else
            DisableRangeCheckForBar(key)
        end
    end

    -- Hook Blizzard's usability update so our range tint is re-applied
    -- after Blizzard resets the icon vertex color.
    for _, info in ipairs(BAR_CONFIG) do
        local btns = barButtons[info.key]
        if btns then
            for _, btn in ipairs(btns) do
                if not btn._eabRangeHooked and btn.UpdateUsable then
                    btn._eabRangeHooked = true
                    hooksecurefunc(btn, "UpdateUsable", function(self)
                        if not self._eabRangeTinted then return end
                        local slot = GetButtonActionSlot(self)
                        if slot and _rangeOutOfRange[slot] then
                            local s
                            for _, inf in ipairs(BAR_CONFIG) do
                                local bs = barButtons[inf.key]
                                if bs then
                                    for _, b in ipairs(bs) do
                                        if b == self then s = EAB.db.profile.bars[inf.key]; break end
                                    end
                                end
                                if s then break end
                            end
                            if s and s.outOfRangeColoring then
                                ApplyRangeTint(self, true, s)
                            end
                        end
                    end)
                end
            end
        end
    end
    -- Set up the event listener if not already created
    if not _rangeEventFrame then
        _rangeEventFrame = CreateFrame("Frame")
        _rangeEventFrame:RegisterEvent("ACTION_RANGE_CHECK_UPDATE")
        _rangeEventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        _rangeEventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
        _rangeEventFrame:RegisterEvent("ACTION_USABLE_CHANGED")
        _rangeEventFrame:SetScript("OnEvent", function(_, event, slot, inRange, checksRange)
            if event == "ACTION_RANGE_CHECK_UPDATE" then
                if not _rangeSlots[slot] then return end
                local wasOut = _rangeOutOfRange[slot]
                local isOut = checksRange and not inRange
                if isOut then
                    _rangeOutOfRange[slot] = true
                else
                    _rangeOutOfRange[slot] = nil
                end
                -- Only update visuals when state actually changes
                if (wasOut ~= nil) == (isOut) then return end
                for _, info in ipairs(BAR_CONFIG) do
                    local btns = barButtons[info.key]
                    local s = EAB.db.profile.bars[info.key]
                    if btns and s and s.outOfRangeColoring then
                        for _, btn in ipairs(btns) do
                            if GetButtonActionSlot(btn) == slot then
                                ApplyRangeTint(btn, isOut, s)
                            end
                        end
                    end
                end
            elseif event == "ACTIONBAR_SLOT_CHANGED" then
                -- When a slot changes (paging, drag, etc.), re-enable range
                -- checking for the new action and clear stale tint
                if slot and _rangeSlots[slot] then
                    _rangeOutOfRange[slot] = nil
                    if C_ActionBar and C_ActionBar.EnableActionRangeCheck then
                        pcall(C_ActionBar.EnableActionRangeCheck, slot, true)
                    end
                end
                -- Debounce the full re-enable pass so 12+ per-slot fires
                -- during a bar page swap collapse into one deferred call
                if not _rangeSlotPending then
                    _rangeSlotPending = true
                    C_Timer_After(0, function()
                        _rangeSlotPending = false
                        for _, info in ipairs(BAR_CONFIG) do
                            local s = EAB.db.profile.bars[info.key]
                            if s and s.outOfRangeColoring then
                                EnableRangeCheckForBar(info.key)
                            end
                        end
                    end)
                end
            elseif event == "ACTIONBAR_PAGE_CHANGED" then
                -- Page changed: clear all range state and re-enable for new slots
                wipe(_rangeOutOfRange)
                for _, info in ipairs(BAR_CONFIG) do
                    local s = EAB.db.profile.bars[info.key]
                    if s and s.outOfRangeColoring then
                        local btns = barButtons[info.key]
                        if btns then
                            for _, btn in ipairs(btns) do
                                if btn._eabRangeTinted then
                                    local ico = btn.icon or btn.Icon
                                    if ico then ico:SetVertexColor(1, 1, 1) end
                                    btn._eabRangeTinted = nil
                                end
                            end
                        end
                        EnableRangeCheckForBar(info.key)
                    end
                end
            elseif event == "ACTION_USABLE_CHANGED" then
                -- Blizzard resets icon vertex colors on usability changes;
                -- re-apply range tint on any out-of-range buttons.
                for _, info in ipairs(BAR_CONFIG) do
                    local btns = barButtons[info.key]
                    local s = EAB.db.profile.bars[info.key]
                    if btns and s and s.outOfRangeColoring then
                        for _, btn in ipairs(btns) do
                            local bSlot = GetButtonActionSlot(btn)
                            if bSlot and _rangeOutOfRange[bSlot] then
                                ApplyRangeTint(btn, true, s)
                            end
                        end
                    end
                end
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Mouseover Fade System
-------------------------------------------------------------------------------
local hoverStates = {}  -- [barKey] = { frame=, buttons=, isHovered=false }
local AttachExtraBarHoverHooks  -- forward declaration; defined near SetupExtraBarHolder

local function AttachHoverHooks(barKey)
    local frame = barFrames[barKey]
    local buttons = barButtons[barKey]
    if not frame or not buttons then return end

    local state = hoverStates[barKey]
    if not state then
        state = { frame = frame, buttons = buttons, isHovered = false, fadeDir = nil }
        hoverStates[barKey] = state
    end

    local function OnEnter(self)
        -- Skip hidden empty buttons (alwaysShowButtons off)
        local s = EAB.db.profile.bars[barKey]
        if s then
            local showEmpty = s.alwaysShowButtons
            if showEmpty == nil then showEmpty = true end
            if not showEmpty then
                if self ~= frame then
                    -- Individual button: skip if it's hidden (no action)
                    if self.GetAlpha and self:GetAlpha() < 0.01 then
                        return
                    end
                else
                    -- Bar frame itself (gaps between buttons): only allow if
                    -- the cursor is near a visible button.  Check if any
                    -- button with alpha > 0 contains the cursor position
                    -- (with padding to cover gaps between visible buttons).
                    local cx, cy = GetCursorPosition()
                    local scale = frame:GetEffectiveScale()
                    cx, cy = cx / scale, cy / scale
                    local pad = (s.buttonPadding or 2) + 2
                    local nearVisible = false
                    for i = 1, #buttons do
                        local btn = buttons[i]
                        if btn and btn:IsShown() and btn:GetAlpha() > 0.01 then
                            local bl, bb, bw, bh = btn:GetRect()
                            if bl and cx >= bl - pad and cx <= bl + bw + pad and cy >= bb - pad and cy <= bb + bh + pad then
                                nearVisible = true
                                break
                            end
                        end
                    end
                    if not nearVisible then return end
                end
            end
        end
        state.isHovered = true
        if s and s.mouseoverEnabled and state.fadeDir ~= "in" then
            state.fadeDir = "in"
            StopFade(frame)
            FadeTo(frame, 1, s.mouseoverSpeed or 0.15)
        end
    end

    local function OnLeave()
        state.isHovered = false
        C_Timer_After(0.1, function()
            if state.isHovered then return end
            -- Keep bar visible while a spell flyout spawned from this bar is open
            if EABFlyout:IsVisible() and EABFlyout:IsMouseOver() then return end
            local s = EAB.db.profile.bars[barKey]
            if s and s.mouseoverEnabled and state.fadeDir ~= "out" then
                state.fadeDir = "out"
                FadeTo(frame, 0, s.mouseoverSpeed or 0.15)
            end
        end)
    end

    -- When the flyout closes, re-evaluate whether the bar should fade out
    do
        local flyFrame = EABFlyout:GetFrame()
        if flyFrame then
            flyFrame:HookScript("OnHide", function()
                if state.isHovered then return end
                local s = EAB.db.profile.bars[barKey]
                if s and s.mouseoverEnabled and state.fadeDir ~= "out" then
                    state.fadeDir = "out"
                    FadeTo(frame, 0, s.mouseoverSpeed or 0.15)
                end
            end)
        end
    end

    frame:HookScript("OnEnter", OnEnter)
    frame:HookScript("OnLeave", OnLeave)
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn then
            btn:HookScript("OnEnter", OnEnter)
            btn:HookScript("OnLeave", OnLeave)
        end
    end
end

function EAB:RefreshMouseover()
    for _, info in ipairs(ALL_BARS) do
        local key = info.key
        local s = self.db.profile.bars[key]
        if not s then break end
        local frame = barFrames[key] or (info.isDataBar and dataBarFrames[key]) or (info.isBlizzardMovable and blizzMovableHolders[key]) or (extraBarHolders[key]) or (info.visibilityOnly and _G[info.frameName])
        if frame then
            -- For extra bars (MicroBar, BagBar), fade the Blizzard frame directly
            -- since that's what AttachExtraBarHoverHooks targets.
            if info.visibilityOnly and not info.isDataBar and not info.isBlizzardMovable then
                local blizzFrame = _G[info.frameName]
                if blizzFrame then frame = blizzFrame end
            end
            if s.mouseoverEnabled then
                -- Ensure extra bars have hover hooks attached (may not have been
                -- set up at load time if mouseover was disabled then)
                if info.visibilityOnly and not info.isDataBar and not info.isBlizzardMovable then
                    AttachExtraBarHoverHooks(info)
                end
                StopFade(frame)
                frame:SetAlpha(0)
                local state = hoverStates[key]
                if state then state.fadeDir = "out" end
            else
                StopFade(frame)
                frame:SetAlpha(s.mouseoverAlpha or 1)
                local state = hoverStates[key]
                if state then state.fadeDir = nil end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Visibility Condition Builder
--  Generates the correct macro condition string for RegisterStateDriver
--  based on bar type and user settings (combat show/hide).
--
--  Bar type rules:
--    MainBar (bar 1):  Stays visible during vehicle/override (paging handles
--                      showing the correct actions).  Hides during pet battle.
--    Bars 2-8:         Hide during vehicle UI, pet battle, and override bar
--                      (only bar 1 pages to show override/vehicle actions).
--    StanceBar:        Hide during vehicle UI and pet battle.
--    PetBar:           Hide during pet battle.  Only show when the player has
--                      a pet and is not in a vehicle/override/possess state.
-------------------------------------------------------------------------------
local function BuildVisibilityString(info, s)
    local key = info.key
    local vis = s.barVisibility or "always"

    -- Build visibility-option hide clauses that can be expressed as macro
    -- conditionals. These run inside the secure state driver so they work
    -- even in combat without taint.
    local visOptHide = ""
    if s.visHideMounted then visOptHide = visOptHide .. "[mounted] hide; " end
    if s.visHideNoTarget then visOptHide = visOptHide .. "[noexists] hide; " end
    if s.visHideNoEnemy then visOptHide = visOptHide .. "[noharm] hide; " end

    -- Pet bar has unique logic: it only shows when a pet is active and
    -- the player is not in a vehicle/override/possess state.
    if info.isPetBar then
        local petShow
        if vis == "in_combat" then
            petShow = "[combat] show; hide"
        elseif s.combatShowEnabled then
            petShow = "[combat] show; hide"
        elseif s.combatHideEnabled then
            petShow = "[combat] hide; show"
        else
            petShow = "show"
        end
        return "[petbattle] hide; " .. visOptHide .. "[novehicleui,pet,nooverridebar,nopossessbar] " .. petShow .. "; hide"
    end

    -- Build the hide-prefix based on bar type
    local hidePrefix
    if key == "MainBar" then
        hidePrefix = "[petbattle] hide; "
    elseif info.isStance then
        hidePrefix = "[vehicleui][petbattle] hide; "
    else
        hidePrefix = "[vehicleui][petbattle][overridebar] hide; "
    end

    -- Inject visibility-option hide clauses after the standard hide-prefix
    hidePrefix = hidePrefix .. visOptHide

    -- Append visibility mode conditions
    if vis == "never" then
        return hidePrefix .. "hide"
    elseif vis == "in_combat" then
        return hidePrefix .. "[combat] show; hide"
    elseif vis == "in_raid" then
        return hidePrefix .. "[group:raid] show; hide"
    elseif vis == "in_party" then
        return hidePrefix .. "[group:party] show; [group:raid] show; hide"
    elseif vis == "solo" then
        return hidePrefix .. "[nogroup] show; hide"
    end

    -- Legacy boolean fallback (for any bars not yet migrated)
    if s.combatShowEnabled then
        return hidePrefix .. "[combat] show; hide"
    elseif s.combatHideEnabled then
        return hidePrefix .. "[combat] hide; show"
    end
    return hidePrefix .. "show"
end

-------------------------------------------------------------------------------
--  Extra Bar Visibility (Pet Battle / Vehicle Hiding)
--  MicroBar, BagBar, data bars, and Blizzard movable frames are not
--  SecureHandlerStateTemplate frames, so we use a single secure proxy
--  frame that monitors [petbattle] and [vehicleui] conditions and calls
--  methods to show/hide the extra bar frames.
-------------------------------------------------------------------------------
local _extraBarVisProxy  -- created once, reused

function EAB:ApplyExtraBarVisibility()
    if not _extraBarVisProxy then
        _extraBarVisProxy = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
        _extraBarVisProxy:SetAttribute("_onstate-extravis", [[
            self:CallMethod("OnExtraVisChanged", newstate)
        ]])
        _extraBarVisProxy.OnExtraVisChanged = function(_, state)
            -- state is "hide" during pet battle, "show" otherwise
            local shouldHide = (state == "hide")
            for _, info in ipairs(EXTRA_BARS) do
                local key = info.key
                local s = EAB.db and EAB.db.profile.bars[key]
                if s and not s.alwaysHidden then
                    local frame
                    if info.isDataBar then
                        frame = dataBarFrames[key]
                    elseif info.isBlizzardMovable then
                        frame = blizzMovableHolders[key]
                    else
                        -- MicroBar, BagBar: hide the Blizzard frame directly
                        frame = _G[info.frameName]
                    end
                    if frame then
                        if shouldHide then
                            frame:Hide()
                        else
                            frame:Show()
                            -- Restore correct alpha: mouseover bars fade to 0 when not hovered,
                            -- so Show() alone leaves them invisible after a pet battle ends.
                            if s.mouseoverEnabled then
                                local hstate = hoverStates[key]
                                local isHovered = hstate and hstate.isHovered
                                if not isHovered then
                                    frame:SetAlpha(0)
                                else
                                    frame:SetAlpha(s.mouseoverAlpha or 1)
                                end
                            else
                                frame:SetAlpha(s.mouseoverAlpha or 1)
                            end
                            -- Data bars may need to re-evaluate (XP at max, etc.)
                            if info.isDataBar then
                                local df = dataBarFrames[key]
                                if df and df._updateFunc then df._updateFunc() end
                            end
                        end
                    end
                end
            end
        end
    end
    -- Register the state driver: hide during pet battle, show otherwise
    RegisterStateDriver(_extraBarVisProxy, "extravis", "[petbattle] hide; show")
end

-------------------------------------------------------------------------------
--  Combat Show/Hide, Always Hidden, Click-Through, Housing
-------------------------------------------------------------------------------
function EAB:ApplyCombatVisibility()
    if InCombatLockdown() then return end
    for _, info in ipairs(ALL_BARS) do
        local key = info.key
        local s = self.db.profile.bars[key]
        if not s then break end
        local frame = barFrames[key] or (info.isDataBar and dataBarFrames[key]) or (info.isBlizzardMovable and blizzMovableHolders[key]) or (extraBarHolders[key]) or (info.visibilityOnly and _G[info.frameName])
        if frame and not info.visibilityOnly then
            if s.alwaysHidden then
                RegisterAttributeDriver(frame, "state-visibility", "hide")
            else
                RegisterAttributeDriver(frame, "state-visibility", BuildVisibilityString(info, s))
            end
        end
    end
    -- Apply pet battle / vehicle hiding for extra bars (MicroBar, BagBar,
    -- data bars).  These use a dedicated secure proxy since they are not
    -- SecureHandlerStateTemplate frames themselves.
    self:ApplyExtraBarVisibility()
end

function EAB:ApplyAlwaysHidden()
    for _, info in ipairs(ALL_BARS) do
        local key = info.key
        local s = self.db.profile.bars[key]
        if not s then break end
        local frame = barFrames[key] or (info.isDataBar and dataBarFrames[key]) or (info.isBlizzardMovable and blizzMovableHolders[key]) or (extraBarHolders[key]) or (info.visibilityOnly and _G[info.frameName])
        if frame then
            local vis = s.barVisibility or "always"
            local isHidden = (vis == "never") or s.alwaysHidden
            if isHidden then
                if not info.visibilityOnly and not InCombatLockdown() then
                    RegisterAttributeDriver(frame, "state-visibility", "hide")
                elseif info.visibilityOnly then
                    frame:Hide()
                end
                if not InCombatLockdown() then
                    SafeEnableMouse(frame, false)
                end
            else
                if not info.visibilityOnly and not InCombatLockdown() then
                    RegisterAttributeDriver(frame, "state-visibility", BuildVisibilityString(info, s))
                end
                if not InCombatLockdown() then
                    if vis ~= "in_combat" and not s.combatShowEnabled then
                        -- ExtraActionButton and EncounterBar holders manage
                        -- their own visibility based on active content.
                        if not info.isBlizzardMovable then
                            frame:Show()
                        end
                    end
                    if barFrames[key] and frame == barFrames[key] then
                        SafeEnableMouseMotionOnly(frame, not s.clickThrough)
                    elseif info.isBlizzardMovable then
                        -- Blizzard movable holders must never eat clicks.
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


function EAB:ApplySmartNumIcons(barKey)
    -- No-op: bar frame size is always determined by the user's numIcons
    -- setting. Empty button visibility is handled by ApplyAlwaysShowButtons.
end

function EAB:ApplyClickThroughForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end

    -- Data bars
    local dataFrame = dataBarFrames[barKey]
    if dataFrame then
        SafeEnableMouse(dataFrame, not s.clickThrough)
        return
    end

    -- Extra bars (MicroBar, BagBar)
    for _, info in ipairs(EXTRA_BARS) do
        if info.key == barKey and not info.isDataBar and not info.isBlizzardMovable then
            local frame = _G[info.frameName]
            if frame then SafeEnableMouse(frame, not s.clickThrough) end
            return
        end
    end

    -- Action bars
    local frame = barFrames[barKey]
    if not frame then return end
    local buttons = barButtons[barKey]
    if not buttons then return end

    local enable = not s.clickThrough
    -- Bar frame only needs mouse motion (for hover detection); clicks pass through
    -- to the buttons or to frames behind the bar.
    SafeEnableMouseMotionOnly(frame, enable)
    local showEmpty = s.alwaysShowButtons
    if showEmpty == nil then showEmpty = true end
    local info = BAR_LOOKUP[barKey]
    if info and info.isStance then showEmpty = false end
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn then
            -- Don't re-enable mouse on invisible empty slots
            local isInvisible = (btn:GetAlpha() == 0) and not showEmpty
            if not isInvisible then
                SafeEnableMouse(btn, enable)
            end
        end
    end
end

function EAB:UpdateHousingVisibility()
    -- Defer to next frame to avoid taint from secure execution paths
    -- (e.g. CameraOrSelectOrMoveStop triggering PLAYER_MOUNT_DISPLAY_CHANGED)
    C_Timer.After(0, function()
        if InCombatLockdown() then return end
        -- Check only housing and instance-only options here. Mounted, target,
        -- and enemy options are handled by the secure state driver via
        -- BuildVisibilityString and re-evaluate automatically.
        local function ShouldHideNonMacro(s)
            if not s then return false end
            if s.visOnlyInstances then
                local _, iType, diffID = GetInstanceInfo()
                diffID = tonumber(diffID) or 0
                local inInstance = false
                if diffID > 0 then
                    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then
                        inInstance = false
                    elseif iType == "party" or iType == "raid" or iType == "scenario" or iType == "arena" or iType == "pvp" then
                        inInstance = true
                    end
                end
                if not inInstance then return true end
            end
            if s.visHideHousing then
                if C_Map and C_Map.GetBestMapForUnit then
                    local mapID = C_Map.GetBestMapForUnit("player")
                    if mapID and mapID > 2600 then return true end
                end
            end
            return false
        end

        for _, info in ipairs(ALL_BARS) do
            local key = info.key
            local s = self.db.profile.bars[key]
            if s then
                local frame = barFrames[key] or (info.isDataBar and dataBarFrames[key]) or (info.isBlizzardMovable and blizzMovableHolders[key]) or (extraBarHolders[key]) or (info.visibilityOnly and _G[info.frameName])
                if frame then
                    -- Secure action bar frames use the state driver for mounted/
                    -- target/enemy options, so only check housing/instances here.
                    -- Non-secure frames (data bars, extra bars, visibility-only)
                    -- need the full check since they have no state driver.
                    local isSecure = not info.visibilityOnly and not info.isDataBar and not info.isBlizzardMovable and barFrames[key]
                    local shouldHide = isSecure and ShouldHideNonMacro(s) or (not isSecure and EllesmereUI.CheckVisibilityOptions(s))
                    if shouldHide then
                        if isSecure then
                            RegisterAttributeDriver(frame, "state-visibility", "hide")
                        else
                            frame:Hide()
                        end
                    elseif not s.alwaysHidden and (s.barVisibility or "always") ~= "never" then
                        if isSecure then
                            RegisterAttributeDriver(frame, "state-visibility", BuildVisibilityString(info, s))
                        elseif not info.isBlizzardMovable then
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
    end)
end

-------------------------------------------------------------------------------
--  Pushed / Highlight / Cooldown Edge / Misc Textures / Proc Glows
--  These are global settings that apply to ALL action bar buttons.
-------------------------------------------------------------------------------
local PUSHED_TYPES = {
    [1] = "light",   -- Light overlay
    [2] = "medium",  -- Medium overlay
    [3] = "strong",  -- Strong overlay
    [4] = "solid",   -- Solid color fill
    [5] = "border",  -- Border only
    [6] = "none",    -- No pushed effect
}

function EAB:ApplyPushedTextures()
    local p = self.db.profile
    local pType = p.pushedTextureType or 2
    local useCC = p.pushedUseClassColor
    local customC = p.pushedCustomColor or { r=0.973, g=0.839, b=0.604, a=1 }
    local brdSize = p.pushedBorderSize or 4

    local cr, cg, cb = customC.r, customC.g, customC.b
    if useCC then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
    end

    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and btn.PushedTexture then
                    if pType == 6 then
                        btn.PushedTexture:SetAlpha(0)
                    else
                        btn.PushedTexture:SetAlpha(1)
                        if pType <= 3 then
                            -- Light/Medium/Strong: use highlight textures at full opacity
                            SetSquareTexture(btn.PushedTexture, HIGHLIGHT_TEXTURES[pType] or HIGHLIGHT_TEXTURES[2])
                            btn.PushedTexture:SetVertexColor(cr, cg, cb, 1)
                        elseif pType == 4 then
                            btn.PushedTexture:SetColorTexture(cr, cg, cb, 0.35)
                        elseif pType == 5 then
                            SetSquareTexture(btn.PushedTexture, HIGHLIGHT_TEXTURES[1])
                            btn.PushedTexture:SetVertexColor(cr, cg, cb, 1)
                        end
                    end
                end
            end
        end
    end
end

function EAB:ApplyHighlightTextures()
    local p = self.db.profile
    local hType = p.highlightTextureType or 2
    local useCC = p.highlightUseClassColor
    local customC = p.highlightCustomColor or { r=0.973, g=0.839, b=0.604, a=1 }

    local cr, cg, cb = customC.r, customC.g, customC.b
    if useCC then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
    end

    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and btn.HighlightTexture then
                    if hType == 6 then
                        btn.HighlightTexture:SetAlpha(0)
                    else
                        btn.HighlightTexture:SetAlpha(1)
                        if hType <= 3 then
                            SetSquareTexture(btn.HighlightTexture, HIGHLIGHT_TEXTURES[hType] or HIGHLIGHT_TEXTURES[1])
                            btn.HighlightTexture:SetVertexColor(cr, cg, cb, 1)
                        elseif hType == 4 then
                            btn.HighlightTexture:SetColorTexture(cr, cg, cb, 0.35)
                        elseif hType == 5 then
                            SetSquareTexture(btn.HighlightTexture, HIGHLIGHT_TEXTURES[1])
                            btn.HighlightTexture:SetVertexColor(cr, cg, cb, 1)
                        end
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Custom Proc Glow (FlipBook-based, no LibCustomGlow)
--  Hooks Blizzard's SpellActivationAlert to reconfigure the FlipBook
--  textures/animations with user-selected glow styles.
-------------------------------------------------------------------------------

-- Loop glow types: atlas-based Blizzard FlipBook styles + procedural engines
local LOOP_GLOW_TYPES = {
    { name = "Pixel Glow",           procedural = true },
    { name = "Custom Proc Glow",     buttonGlow = true, scale = 1.36, previewScale = 1.28 },
    { name = "Auto-Cast Shine",      autocast = true },
    { name = "Shape Glow",           shapeGlow = true, scale = 1.20, previewScale = 1.20 },
    { name = "GCD",                  atlas = "RotationHelper_Ants_Flipbook",  scale = 1.12, previewScale = 1.47 },
    { name = "Modern WoW Glow",      atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook",  scale = 1.02, previewScale = 1.34 },
    { name = "Classic WoW Glow",     texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows = 5, columns = 5, frames = 25, duration = 0.3, frameW = 48, frameH = 48, scale = 1.09, previewScale = 1.47 },
}
ns.LOOP_GLOW_TYPES = LOOP_GLOW_TYPES

-- Proc start types: the initial burst animation
local PROC_START_TYPES = {
    { name = "Modern Blizzard Proc",  atlas = "UI-HUD-ActionBar-Proc-Start-Flipbook" },
    { name = "Blue Proc",             atlas = "RotationHelper-ProcStartBlue-Flipbook-2x" },
    { name = "Hide",                  hide = true },
}
ns.PROC_START_TYPES = PROC_START_TYPES

-------------------------------------------------------------------------------
--  Glow Engines provided by shared EllesmereUI_Glows.lua
-------------------------------------------------------------------------------
local StartProceduralAnts, StopProceduralAnts
local StartButtonGlow, StopButtonGlow
local StartAutoCastShine, StopAutoCastShine
local StartShapeGlow, StopShapeGlow
do
    local g = EllesmereUI.Glows
    StartProceduralAnts = g.StartProceduralAnts
    StopProceduralAnts  = g.StopProceduralAnts
    StartButtonGlow     = g.StartButtonGlow
    StopButtonGlow      = g.StopButtonGlow
    StartAutoCastShine  = g.StartAutoCastShine
    StopAutoCastShine   = g.StopAutoCastShine
    StartShapeGlow      = g.StartShapeGlow
    StopShapeGlow       = g.StopShapeGlow
end
ns.StartProceduralAnts = StartProceduralAnts
ns.StopProceduralAnts  = StopProceduralAnts
ns.StartButtonGlow     = StartButtonGlow
ns.StopButtonGlow      = StopButtonGlow
ns.StartAutoCastShine  = StartAutoCastShine
ns.StopAutoCastShine   = StopAutoCastShine
ns.StartShapeGlow      = StartShapeGlow
ns.StopShapeGlow       = StopShapeGlow

local function StopAllProceduralGlows(wrapper)
    _G_Glows.StopAllGlows(wrapper)
end

local procGlowHooked = false
local activeProcs = {}

local function GetFlipBookAnim(animGroup)
    if not animGroup then return nil end
    if animGroup.FlipAnim then return animGroup.FlipAnim end
    for _, anim in pairs({animGroup:GetAnimations()}) do
        if anim.SetFlipBookRows then return anim end
    end
    return nil
end

local function UpdateFlipbook(btn)
    local region = btn.SpellActivationAlert
    if not region then return end

    if btn._eabShapeMask and btn._eabShapeApplied and not region._eabShapeMasked then
        for _, tex in ipairs({region:GetRegions()}) do
            if tex and tex.AddMaskTexture then
                pcall(tex.AddMaskTexture, tex, btn._eabShapeMask)
            end
        end
        region._eabShapeMasked = true
    end

    local p = EAB.db and EAB.db.profile
    if not p then return end

    if p.procGlowEnabled == false then
        -- Custom shapes always use Shape Glow even if custom proc glow is "off"
        if not (btn._eabShapeMask and btn._eabShapeApplied) then
            if btn._eabGlowWrapper then
                StopAllProceduralGlows(btn._eabGlowWrapper)
                btn._eabGlowWrapper:Hide()
            end
            if region.ProcLoopFlipbook then
                region.ProcLoopFlipbook:Show()
                region.ProcLoopFlipbook:SetDesaturated(false)
                region.ProcLoopFlipbook:SetVertexColor(1, 1, 1)
                region.ProcLoopFlipbook:SetScale(1)
            end
            if region.ProcStartFlipbook then
                region.ProcStartFlipbook:Show()
                region.ProcStartFlipbook:SetDesaturated(false)
                region.ProcStartFlipbook:SetVertexColor(1, 1, 1)
                region.ProcStartFlipbook:SetScale(1)
            end
            region:SetScale(1)
            if region.ProcLoop then
                local loopFlip = GetFlipBookAnim(region.ProcLoop)
                if loopFlip then loopFlip:SetDuration(1.0) end
            end
            if region.ProcStartAnim then
                local startFlip = GetFlipBookAnim(region.ProcStartAnim)
                if startFlip then startFlip:SetDuration(0.702) end
            end
            if btn._eabAntsGroup then btn._eabAntsGroup:Stop() end
            if btn._eabAntsOverlay then btn._eabAntsOverlay:Hide() end
            return
        end
    end

    local cr, cg, cb
    if p.procGlowUseClassColor then
        local _, class = UnitClass("player")
        local cc = RAID_CLASS_COLORS[class]
        if cc then cr, cg, cb = cc.r, cc.g, cc.b else cr, cg, cb = 1, 1, 1 end
    else
        local c = p.procGlowColor or { r = 1, g = 0.776, b = 0.376 }
        cr, cg, cb = c.r, c.g, c.b
    end

    local loopIdx = p.procGlowType or 1
    if loopIdx < 1 or loopIdx > #LOOP_GLOW_TYPES then loopIdx = 1 end
    -- Force Shape Glow for custom shapes regardless of user selection
    if btn._eabShapeMask and btn._eabShapeApplied then
        for si, entry in ipairs(LOOP_GLOW_TYPES) do
            if entry.shapeGlow then loopIdx = si; break end
        end
    end
    local loopEntry = LOOP_GLOW_TYPES[loopIdx]

    if not btn._eabGlowWrapper then
        local wrapper = CreateFrame("Frame", nil, btn)
        wrapper:SetAllPoints(btn)
        wrapper:SetFrameLevel(btn:GetFrameLevel() + 1)
        btn._eabGlowWrapper = wrapper
    end
    local wrapper = btn._eabGlowWrapper
    -- Keep wrapper just above btn base but below shape border overlay
    wrapper:SetFrameLevel(btn:GetFrameLevel() + 1)

    if btn._eabShapeMask and btn._eabShapeApplied and btn._eabShapeMaskPath then
        if not wrapper._eabOwnMask then
            wrapper._eabOwnMask = wrapper:CreateMaskTexture()
        end
        wrapper._eabOwnMask:ClearAllPoints()
        PP.Point(wrapper._eabOwnMask, "TOPLEFT", btn, "TOPLEFT", 1, -1)
        PP.Point(wrapper._eabOwnMask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        wrapper._eabOwnMask:SetTexture(btn._eabShapeMaskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        wrapper._eabOwnMask:Show()
    elseif wrapper._eabOwnMask then
        wrapper._eabOwnMask:Hide()
    end

    if loopEntry.procedural or loopEntry.buttonGlow or loopEntry.autocast or loopEntry.shapeGlow then
        if region.ProcStartFlipbook then region.ProcStartFlipbook:Hide() end
        if region.ProcStartAnim then
            local startFlip = GetFlipBookAnim(region.ProcStartAnim)
            if startFlip then startFlip:SetDuration(0) end
        end
        if region.ProcLoop then
            local loopFlip = GetFlipBookAnim(region.ProcLoop)
            if loopFlip then loopFlip:SetDuration(0) end
        end
        if region.ProcLoopFlipbook then region.ProcLoopFlipbook:Hide() end

        if region.ProcStartAnim and not region._eabStartFinishHooked then
            region.ProcStartAnim:HookScript("OnFinished", function()
                if activeProcs[btn] then
                    local pp = EAB.db and EAB.db.profile
                    local idx = pp and pp.procGlowType or 1
                    local entry = LOOP_GLOW_TYPES[idx]
                    if entry and (entry.procedural or entry.buttonGlow or entry.autocast or entry.shapeGlow) then
                        if region.ProcLoopFlipbook then region.ProcLoopFlipbook:Hide() end
                        if region.ProcLoop then
                            local lf = GetFlipBookAnim(region.ProcLoop)
                            if lf then lf:SetDuration(0) end
                        end
                    end
                end
            end)
            region._eabStartFinishHooked = true
        end

        if region.ProcLoop and not region._eabLoopPlayHooked then
            region.ProcLoop:HookScript("OnPlay", function()
                if activeProcs[btn] then
                    local pp = EAB.db and EAB.db.profile
                    local idx = pp and pp.procGlowType or 1
                    local entry = LOOP_GLOW_TYPES[idx]
                    if entry and (entry.procedural or entry.buttonGlow or entry.autocast or entry.shapeGlow) then
                        if region.ProcLoopFlipbook then region.ProcLoopFlipbook:Hide() end
                    end
                end
            end)
            region._eabLoopPlayHooked = true
        end

        StopAllProceduralGlows(wrapper)
        wrapper:Show()
        region:SetScale(1)
        if region.ProcLoopFlipbook then region.ProcLoopFlipbook:Hide() end
        if region.ProcStartFlipbook then region.ProcStartFlipbook:Hide() end
        if btn._eabAntsGroup then btn._eabAntsGroup:Stop() end
        if btn._eabAntsOverlay then btn._eabAntsOverlay:Hide() end

        local sz = min(btn:GetWidth(), btn:GetHeight()) or 36
        local userScale = p.procGlowScale or 1.0

        if loopEntry.procedural then
            local N = 8
            local th = 2
            local period = 4
            local lineLen = floor((sz + sz) * (2 / N - 0.1))
            lineLen = min(lineLen, sz)
            if lineLen < 1 then lineLen = 1 end
            StartProceduralAnts(wrapper, N, th, period, lineLen, cr, cg, cb)
        elseif loopEntry.buttonGlow then
            local baseScale = loopEntry.scale or 1
            local finalScale = baseScale * userScale
            StartButtonGlow(wrapper, sz, cr, cg, cb, finalScale)
        elseif loopEntry.autocast then
            StartAutoCastShine(wrapper, sz, cr, cg, cb, userScale)
        elseif loopEntry.shapeGlow then
            local baseScale = loopEntry.scale or 1.20
            local finalScale = baseScale * userScale
            local maskPath = btn._eabShapeMaskPath or SHAPE_MASKS[btn._eabShapeName or ""]
            local borderPath = SHAPE_BORDERS[btn._eabShapeName or ""]
            StartShapeGlow(wrapper, sz, cr, cg, cb, finalScale, {
                maskPath   = maskPath,
                borderPath = borderPath,
                shapeMask  = btn._eabShapeMask,
            })
        end
        if wrapper._eabOwnMask then
            MaskFrameTextures(wrapper, wrapper._eabOwnMask)
        end
    else
        StopAllProceduralGlows(wrapper)
        wrapper:Hide()

        if region.ProcLoopFlipbook then region.ProcLoopFlipbook:Show() end
        if region.ProcStartFlipbook then region.ProcStartFlipbook:Show() end

        if region.ProcLoopFlipbook and region.ProcLoop then
            local flipAnim = GetFlipBookAnim(region.ProcLoop)
            if loopEntry.atlas then
                region.ProcLoopFlipbook:SetAtlas(loopEntry.atlas)
            elseif loopEntry.texture then
                region.ProcLoopFlipbook:SetTexture(loopEntry.texture)
            end
            if flipAnim then
                flipAnim:SetFlipBookRows(loopEntry.rows or 6)
                flipAnim:SetFlipBookColumns(loopEntry.columns or 5)
                flipAnim:SetFlipBookFrames(loopEntry.frames or 30)
                flipAnim:SetDuration(loopEntry.duration or 1.0)
                flipAnim:SetFlipBookFrameWidth(loopEntry.frameW or 0.0)
                flipAnim:SetFlipBookFrameHeight(loopEntry.frameH or 0.0)
            end
            local baseScale = loopEntry.scale or 1
            local userScale = p.procGlowScale or 1.0
            local finalScale = baseScale * userScale
            region:SetScale(finalScale)
            region.ProcLoopFlipbook:SetDesaturated(true)
            region.ProcLoopFlipbook:SetVertexColor(cr, cg, cb)

            if loopEntry.atlas then
                if not btn._eabAntsOverlay then
                    local antsTex = region:CreateTexture(nil, "OVERLAY", nil, 2)
                    antsTex:SetBlendMode("ADD")
                    local antsGroup = antsTex:CreateAnimationGroup()
                    antsGroup:SetLooping("REPEAT")
                    local antsAnim = antsGroup:CreateAnimation("FlipBook")
                    btn._eabAntsOverlay = antsTex
                    btn._eabAntsGroup = antsGroup
                    btn._eabAntsAnim = antsAnim
                end
                local antsTex = btn._eabAntsOverlay
                local antsAnim = btn._eabAntsAnim
                antsTex:ClearAllPoints()
                antsTex:SetAllPoints(region.ProcLoopFlipbook)
                antsTex:SetAtlas(loopEntry.atlas)
                antsAnim:SetFlipBookRows(loopEntry.rows or 6)
                antsAnim:SetFlipBookColumns(loopEntry.columns or 5)
                antsAnim:SetFlipBookFrames(loopEntry.frames or 30)
                antsAnim:SetDuration(loopEntry.duration or 1.0)
                antsAnim:SetFlipBookFrameWidth(loopEntry.frameW or 0.0)
                antsAnim:SetFlipBookFrameHeight(loopEntry.frameH or 0.0)
                antsTex:SetDesaturated(false)
                antsTex:SetVertexColor(1, 1, 1)
                antsTex:SetAlpha(0.35)
                antsTex:Show()
                btn._eabAntsGroup:Play()
            else
                if btn._eabAntsOverlay then
                    if btn._eabAntsGroup then btn._eabAntsGroup:Stop() end
                    btn._eabAntsOverlay:Hide()
                end
            end
        end
    end

    -- Proc start burst
    local startAnim = PROC_START_TYPES[1]
    if region.ProcStartFlipbook and region.ProcStartAnim then
        local flipAnim = GetFlipBookAnim(region.ProcStartAnim)
        if startAnim.atlas then
            region.ProcStartFlipbook:SetAtlas(startAnim.atlas)
        elseif startAnim.texture then
            region.ProcStartFlipbook:SetTexture(startAnim.texture)
        end
        if flipAnim then
            flipAnim:SetFlipBookRows(startAnim.rows or 6)
            flipAnim:SetFlipBookColumns(startAnim.columns or 5)
            flipAnim:SetFlipBookFrames(startAnim.frames or 30)
            flipAnim:SetDuration(startAnim.duration or 0.702)
            flipAnim:SetFlipBookFrameWidth(startAnim.frameW or 0.0)
            flipAnim:SetFlipBookFrameHeight(startAnim.frameH or 0.0)
        end
        region.ProcStartFlipbook:SetScale(startAnim.scale or 1)
        region.ProcStartFlipbook:SetDesaturated(true)
        region.ProcStartFlipbook:SetVertexColor(cr, cg, cb)
    end

    if btn._eabShapeMask and btn._eabShapeApplied then
        MaskFrameTextures(region, btn._eabShapeMask)
        region._eabShapeMasked = true
    end
end

function EAB:HookProcGlow()
    if procGlowHooked then return end
    procGlowHooked = true
    if ActionButtonSpellAlertManager then
        if ActionButtonSpellAlertManager.ShowAlert then
            hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, btn)
                if not btn then return end
                if not btn._eabSquared then return end
                if not btn._eabShowAlertFn then
                    btn._eabShowAlertFn = function()
                        activeProcs[btn] = true
                        UpdateFlipbook(btn)
                    end
                end
                C_Timer_After(0, btn._eabShowAlertFn)
            end)
        end
        if ActionButtonSpellAlertManager.HideAlert then
            hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, btn)
                if not btn then return end
                if not btn._eabSquared then return end
                if not btn._eabHideAlertFn then
                    btn._eabHideAlertFn = function()
                        activeProcs[btn] = nil
                        if btn._eabGlowWrapper then
                            StopAllProceduralGlows(btn._eabGlowWrapper)
                            btn._eabGlowWrapper:Hide()
                        end
                        if btn._eabAntsGroup then btn._eabAntsGroup:Stop() end
                        if btn._eabAntsOverlay then btn._eabAntsOverlay:Hide() end
                    end
                end
                C_Timer_After(0, btn._eabHideAlertFn)
            end)
        end
    end
end

function EAB:RefreshProcGlows()
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and activeProcs[btn] then
                    UpdateFlipbook(btn)
                end
            end
        end
    end
end

function EAB:ScanExistingProcs()
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and btn.SpellActivationAlert and btn.SpellActivationAlert:IsShown() then
                    activeProcs[btn] = true
                    UpdateFlipbook(btn)
                end
            end
        end
    end
end

local EDGE_TEXTURE = "Interface\\AddOns\\EllesmereUIActionBars\\Media\\edge.png"

local function GetClassColor()
    local _, class = UnitClass("player")
    local c = RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function ResolveCooldownEdgeColor(p)
    if p.cooldownEdgeUseClassColor then
        local cr, cg, cb = GetClassColor()
        local c = p.cooldownEdgeColor or { a = 1 }
        return cr, cg, cb, c.a or 1
    end
    local c = p.cooldownEdgeColor or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    return c.r, c.g, c.b, c.a
end

local function ApplySingleCooldownEdge(cdFrame, edgeSize, cr, cg, cb, ca)
    if not cdFrame then return end
    if cdFrame:IsForbidden() then return end
    if cdFrame.SetEdgeTexture then cdFrame:SetEdgeTexture(EDGE_TEXTURE) end
    if cdFrame.SetEdgeScale then cdFrame:SetEdgeScale(edgeSize) end
    if cdFrame.SetEdgeColor then cdFrame:SetEdgeColor(cr, cg, cb, ca) end
end

-- After applying edge cosmetics, enforce shape-based edge visibility.
-- Must be called after ApplySingleCooldownEdge since SetEdgeTexture may
-- re-enable drawing.
local function EnforceShapeEdgeSingle(cd, edgeScale, useCircular)
    if not cd or cd:IsForbidden() then return end
    if cd.SetEdgeTexture then pcall(cd.SetEdgeTexture, cd, EDGE_TEXTURE) end
    if cd.SetUseCircularEdge then pcall(cd.SetUseCircularEdge, cd, useCircular) end
    if cd.SetEdgeScale then pcall(cd.SetEdgeScale, cd, edgeScale) end
end

local function EnforceShapeEdge(btn)
    if not btn or not btn._eabShapeApplied then return end
    local shapeName = btn._eabShapeName
    if not shapeName then return end
    local edgeScale = SHAPE_EDGE_SCALES[shapeName] or 0.60
    local useCircular = (shapeName ~= "square" and shapeName ~= "csquare")
    EnforceShapeEdgeSingle(btn.cooldown, edgeScale, useCircular)
    EnforceShapeEdgeSingle(btn.chargeCooldown, edgeScale, useCircular)
end

local function ApplyButtonCooldownEdge(btn, edgeSize, cr, cg, cb, ca)
    -- Square/csquare use the user's edge size; other shapes force 1.0
    -- since EnforceShapeEdge will override with per-shape scale anyway.
    local sn = btn._eabShapeApplied and btn._eabShapeName
    local sz = edgeSize
    if sn and sn ~= "square" and sn ~= "csquare" then sz = 1.0 end
    ApplySingleCooldownEdge(btn.cooldown, sz, cr, cg, cb, ca)
    ApplySingleCooldownEdge(btn.chargeCooldown, sz, cr, cg, cb, ca)
    EnforceShapeEdge(btn)
end

-- Hook to re-apply edge settings whenever Blizzard resets a cooldown.
-- Per-button hooks avoid tainting the secure execution path.
local cooldownEdgeHooked = false

-- Batched cooldown edge patching: instead of creating a new closure + timer
-- per SetCooldown call, collect pending (btn, cdFrame) pairs and flush them
-- all in a single C_Timer_After(0) callback.  SetCooldown fires on every GCD
-- for every button, so this eliminates dozens of allocations per second.
local _cdPending = {}       -- reusable { [cdFrame] = btn, ... }
local _cdPendingCount = 0
local _cdTimerScheduled = false

local function _FlushCDPatch()
    _cdTimerScheduled = false
    local p = EAB.db and EAB.db.profile
    if not p then wipe(_cdPending); _cdPendingCount = 0; return end
    local cr, cg, cb, ca = ResolveCooldownEdgeColor(p)
    local baseSz = p.cooldownEdgeSize or 2.1
    for cdFrame, btn in pairs(_cdPending) do
        if cdFrame and not cdFrame:IsForbidden() then
            local sz = baseSz
            local sn = btn._eabShapeApplied and btn._eabShapeName
            if sn and sn ~= "square" and sn ~= "csquare" then sz = 1.0 end
            ApplySingleCooldownEdge(cdFrame, sz, cr, cg, cb, ca)
            if btn._eabShapeMaskPath and btn._eabShapeApplied then
                local mask = btn._eabShapeMask
                if mask then
                    pcall(cdFrame.RemoveMaskTexture, cdFrame, mask)
                    pcall(cdFrame.AddMaskTexture, cdFrame, mask)
                end
                if cdFrame.SetSwipeTexture then
                    pcall(cdFrame.SetSwipeTexture, cdFrame, btn._eabShapeMaskPath)
                end
            end
            EnforceShapeEdge(btn)
        end
    end
    wipe(_cdPending)
    _cdPendingCount = 0
end

local function HookButtonCooldownEdge(btn)
    if not btn or not btn._eabSquared then return end
    if btn._eabCDEdgeHooked then return end
    btn._eabCDEdgeHooked = true

    local function OnSetCooldown(cdFrame)
        if not cdFrame then return end
        if not _cdPending[cdFrame] then
            _cdPendingCount = _cdPendingCount + 1
        end
        _cdPending[cdFrame] = btn
        if not _cdTimerScheduled then
            _cdTimerScheduled = true
            C_Timer_After(0, _FlushCDPatch)
        end
    end

    if btn.cooldown and btn.cooldown.SetCooldown then
        hooksecurefunc(btn.cooldown, "SetCooldown", OnSetCooldown)
    end
    if btn.chargeCooldown and btn.chargeCooldown.SetCooldown then
        hooksecurefunc(btn.chargeCooldown, "SetCooldown", OnSetCooldown)
    end
end

local function HookCooldownEdge()
    if cooldownEdgeHooked then return end
    cooldownEdgeHooked = true
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and btn._eabSquared then
                    HookButtonCooldownEdge(btn)
                end
            end
        end
    end
end

function EAB:ApplyCooldownEdge()
    if not self.db.profile.squareIcons then return end
    HookCooldownEdge()
    local p = self.db.profile
    local cr, cg, cb, ca = ResolveCooldownEdgeColor(p)
    local sz = p.cooldownEdgeSize or 2.1
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and btn._eabSquared then
                    ApplyButtonCooldownEdge(btn, sz, cr, cg, cb, ca)
                end
            end
        end
    end
end

function EAB:ApplyMiscTextures()
    local p = self.db.profile

    -- Color the "other" button textures (CheckedTexture, NewActionTexture,
    -- Border) using the pushed texture color settings.  These are the
    -- hard-coded textures the user can't individually customize.
    local useCC = p.pushedUseClassColor
    local customC = p.pushedCustomColor or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local cr, cg, cb, ca = customC.r, customC.g, customC.b, customC.a or 1
    if useCC then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
    end
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and btn._eabSquared then
                    -- Do NOT color CheckedTexture or Border Blizzard uses
                    -- these for item rarity borders (green/blue/purple) on
                    -- active trinkets / equipped items.
                    if btn.NewActionTexture then btn.NewActionTexture:SetDesaturated(true); btn.NewActionTexture:SetVertexColor(cr, cg, cb, ca) end
                end
            end
        end
    end

    -- Hide casting animations if enabled (or forced by custom shapes)
    local anyCustomShape = false
    for _, info2 in ipairs(BAR_CONFIG) do
        local bs = p.bars[info2.key]
        if bs and bs.buttonShape and bs.buttonShape ~= "none" then
            anyCustomShape = true
            break
        end
    end
    if p.hideCastingAnimations or anyCustomShape then
        if ActionBarActionEventsFrame then
            ActionBarActionEventsFrame:UnregisterEvent("UNIT_SPELLCAST_START")
            ActionBarActionEventsFrame:UnregisterEvent("UNIT_SPELLCAST_STOP")
            ActionBarActionEventsFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
            ActionBarActionEventsFrame:UnregisterEvent("UNIT_SPELLCAST_FAILED")
            ActionBarActionEventsFrame:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
        end
    else
        if ActionBarActionEventsFrame then
            ActionBarActionEventsFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
            ActionBarActionEventsFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
            ActionBarActionEventsFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            ActionBarActionEventsFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
            ActionBarActionEventsFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        end
    end
end

-------------------------------------------------------------------------------
--  Keybind System
--  Binds keys to our buttons. On MainBar, bindings are ACTIONBUTTON1-12.
--  On other bars, we use the standard MULTIACTIONBAR bindings.
--
--  Each button gets a hidden SecureActionButtonTemplate child ("bind button")
--  that receives keybind presses and mirrors the parent's action.
--
--  Cast-on-key-down (ActionButtonUseKeyDown CVar):
--    When ON:  keys are bound with "HOTKEY" click type. A WrapScript in the
--              secure env translates HOTKEY -> LeftButton on key-down.
--              typerelease="actionrelease" is set so hold-to-cast works.
--    When OFF: keys are bound with "LeftButton" click type. The bind button
--              fires normally on key-up. No HOTKEY translation occurs.
--              Zero overhead vs. not having the bind button at all.
-------------------------------------------------------------------------------
local _vehicleBindsCleared = false
local _housingBindsCleared = false

-- Secure controller used to WrapScript bind buttons in the secure environment.
local _bindController = CreateFrame("Frame", nil, nil, "SecureHandlerAttributeTemplate")

-- Returns true if the cast-on-key-down CVar is currently enabled.
local function IsKeyDownEnabled()
    return GetCVar("ActionButtonUseKeyDown") == "1"
end

GetOrCreateBindButton = function(btn)
    if btn._bindBtn then return btn._bindBtn end
    -- Bind buttons must be created out of combat. If called in combat
    -- (should not happen after eager creation in SetupBar), bail out.
    if InCombatLockdown() then return nil end

    local bind = CreateFrame("Button", btn:GetName() .. "_EABBind", btn, "SecureActionButtonTemplate")
    bind:SetAttributeNoHandler("type", "action")
    bind:SetAttributeNoHandler("useparent-action", true)
    bind:SetAttributeNoHandler("useparent-checkfocuscast", true)
    bind:SetAttributeNoHandler("useparent-checkmouseovercast", true)
    bind:SetAttributeNoHandler("useparent-checkselfcast", true)
    bind:SetAttributeNoHandler("useparent-flyoutDirection", true)
    bind:SetAttributeNoHandler("useparent-pressAndHoldAction", true)
    bind:SetAttributeNoHandler("useparent-unit", true)
    bind:SetSize(1, 1)
    bind:EnableMouseWheel(true)
    bind:RegisterForClicks("AnyUp", "AnyDown")

    -- Register with our custom flyout system (intercepts flyout clicks
    -- in the secure env so they never reach Blizzard's taint-prone path).
    -- The owner ref lets the flyout frame reparent to the visible button.
    EABFlyout:RegisterButton(bind, btn)

    -- Translate HOTKEY virtual click into LeftButton inside the secure env.
    -- Only active when keys are bound with "HOTKEY" click type (key-down mode).
    -- When key-down is off, keys are bound as "LeftButton" so this never fires.
    -- For flyout actions, translate to LeftButton so the flyout WrapScript
    -- (registered earlier in the chain) can intercept and open the flyout.
    _bindController:WrapScript(bind, "OnClick", [[
        if button == "HOTKEY" then
            return "LeftButton"
        end
    ]])

    -- Visual feedback: push/release the parent button on key down/up.
    -- Safe for both key-down and key-up modes.
    bind:SetScript("PreClick", function(self, _, down)
        local owner = self:GetParent()
        if down then
            if owner:GetButtonState() == "NORMAL" then
                owner:SetButtonState("PUSHED")
            end
        else
            if owner:GetButtonState() == "PUSHED" then
                owner:SetButtonState("NORMAL")
            end
        end
    end)

    btn._bindBtn = bind
    return bind
end

-- Applies the correct typerelease to a bind button based on whether
-- cast-on-key-down is currently enabled. Called out of combat only.
local function ApplyBindButtonMode(bind, keyDownEnabled)
    if keyDownEnabled then
        -- Key-down mode: typerelease="actionrelease" enables hold-to-cast.
        bind:SetAttributeNoHandler("typerelease", "actionrelease")
    else
        -- Key-up mode: no typerelease needed.
        bind:SetAttributeNoHandler("typerelease", nil)
    end
end

local function UpdateKeybinds()
    -- Native Blizzard keybinds: Blizzard's C-level binding system handles all
    -- keybind routing via MultiActionButtonDown/Up. No override bindings needed.
    -- This gives us press-and-hold casting support (only available through
    -- Blizzard's native binding path) while cast-on-key-down continues to work
    -- via the ActionButtonUseKeyDown CVar.
end

-- Called when ActionButtonUseKeyDown CVar changes. Defers to out-of-combat.
local function ApplyKeyDownCVar()
    if InCombatLockdown() then
        -- Can't rebind in combat; defer until combat ends.
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            self:SetScript("OnEvent", nil)
            UpdateKeybinds()
        end)
        return
    end
    UpdateKeybinds()
end
-------------------------------------------------------------------------------
--  Vehicle / Override Keybind Clearing
--  When the player enters a vehicle or override bar, clear our override
--  bindings so Blizzard's vehicle UI receives the keybinds.  Restore them
--  when the player exits.
-------------------------------------------------------------------------------
local function ClearKeybindsForVehicle()
    if _vehicleBindsCleared then return end
    _vehicleBindsCleared = true
    if InCombatLockdown() then return end
    for _, info in ipairs(BAR_CONFIG) do
        local btns = barButtons[info.key]
        if btns then
            for _, btn in ipairs(btns) do
                if btn and btn._bindBtn then
                    ClearOverrideBindings(btn._bindBtn)
                end
            end
        end
    end
end

local function RestoreKeybindsAfterVehicle()
    if not _vehicleBindsCleared then return end
    _vehicleBindsCleared = false
    if InCombatLockdown() then
        -- Defer restore until combat drops
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            -- Only restore if still out of vehicle state
            if _vehicleBindsCleared then return end
            UpdateKeybinds()
        end)
        return
    end
    UpdateKeybinds()
end

local _vehicleStateFrame = CreateFrame("Frame", nil, UIParent, "SecureHandlerStateTemplate")
_vehicleStateFrame:SetAttribute("_onstate-vehicleui", [[
    if newstate == "invehicle" then
        self:CallMethod("OnVehicleEnter")
    else
        self:CallMethod("OnVehicleExit")
    end
]])
_vehicleStateFrame.OnVehicleEnter = ClearKeybindsForVehicle
_vehicleStateFrame.OnVehicleExit  = RestoreKeybindsAfterVehicle
RegisterStateDriver(_vehicleStateFrame, "vehicleui", "[vehicleui] invehicle; novehicle")

-------------------------------------------------------------------------------
--  Vehicle Exit Button
--  Reparent Blizzard's MainMenuBarVehicleLeaveButton so it stays visible
--  when we hide the default action bars.  Strip taint-causing scripts,
--  reparent to UIParent, hook SetPoint to block Blizzard repositioning.
--  FinishSetup re-anchors to barFrames["MainBar"] once it exists, or to a
--  saved unlock-mode position if one is stored.
-------------------------------------------------------------------------------

-- Apply saved or default anchor for the vehicle exit button.
-- Shared by the SetPoint hook, unlock mode applyPosition, and FinishSetup.
-- Stored on EAB rather than a file-scope local to avoid hitting the 200
-- local/upvalue limit in this large file.
function EAB.AnchorVehicleButton()
    local btn = MainMenuBarVehicleLeaveButton
    if not btn or InCombatLockdown() then return end
    local pos = EAB.db and EAB.db.profile.barPositions
                and EAB.db.profile.barPositions["VehicleExit"]
    btn:ClearAllPoints()
    if pos then
        btn:SetPoint(pos.point, UIParent, pos.relPoint or pos.point,
                     pos.x, pos.y)
    else
        local bar1 = barFrames["MainBar"]
        if bar1 then
            btn:SetPoint("BOTTOM", bar1, "TOPRIGHT", 0, 4)
        else
            btn:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 130)
        end
    end
end

do
    local btn = MainMenuBarVehicleLeaveButton
    if btn then
        -- Prevent taint from EditModeManager's UpdateBottomActionBarPositions
        btn:SetScript("OnShow", nil)
        btn:SetScript("OnHide", nil)

        btn:SetParent(UIParent)
        btn:ClearAllPoints()
        btn:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 130) -- temporary fallback

        btn:SetFrameStrata("MEDIUM")
        btn:SetFrameLevel(100)

        -- Block Blizzard from repositioning the button.
        -- Use a guard flag to prevent infinite recursion since our own
        -- SetPoint calls inside the hook would re-trigger it.
        local hookGuard = false
        hooksecurefunc(btn, "SetPoint", function(self, _, parent)
            if hookGuard then return end
            local bar1 = barFrames["MainBar"]
            local anchor = bar1 or UIParent
            if parent ~= anchor and parent ~= UIParent then
                hookGuard = true
                EAB.AnchorVehicleButton()
                hookGuard = false
            end
        end)

        -- Override visibility: only show when the player can actually exit
        -- a vehicle, never for Edit Mode previews.  This also fixes campaign
        -- vehicles whose ActionBarController state isn't MAIN.
        hooksecurefunc(btn, "UpdateShownState", function(self)
            local shouldShow = CanExitVehicle()
            if self:IsShown() ~= shouldShow then
                self:SetShown(shouldShow)
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Housing Editor Keybind Clearing
--  When the house editor is active, clear our override bindings so Blizzard's
--  housing hotkeys work.  Restore them when the editor closes.
-------------------------------------------------------------------------------
local _housingEventFrame = CreateFrame("Frame")
local IsHouseEditorActive = C_HouseEditor and C_HouseEditor.IsHouseEditorActive
if IsHouseEditorActive then
    _housingEventFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
    _housingEventFrame:SetScript("OnEvent", function()
        if IsHouseEditorActive() then
            -- House editor opened clear our override bindings
            if _housingBindsCleared then return end
            _housingBindsCleared = true
            if not InCombatLockdown() then
                for _, info in ipairs(BAR_CONFIG) do
                    local btns = barButtons[info.key]
                    if btns then
                        for _, btn in ipairs(btns) do
                            if btn and btn._bindBtn then
                                ClearOverrideBindings(btn._bindBtn)
                            end
                        end
                    end
                end
            end
        else
            -- House editor closed restore our override bindings
            if not _housingBindsCleared then return end
            _housingBindsCleared = false
            if not InCombatLockdown() then
                UpdateKeybinds()
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Grid Show/Hide (show empty slots during spell drag)
-------------------------------------------------------------------------------
local gridShown = false
local _buttonVisibilityPending = false -- debounce for empty-button visibility refresh
local _spellsChangedPending = false -- debounce for SPELLS_CHANGED

local function OnGridChange()
    if InCombatLockdown() then return end
    gridShown = true
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
            for i = 1, numIcons do
                local btn = buttons[i]
                if btn then
                    if btn._eabSlotBG then btn._eabSlotBG:Show() end
                    -- Show borders during drag
                    if btn._eabBorders and not (btn._eabShapeMask and btn._eabShapeMask:IsShown()) then
                        btn._eabBorders:Show()
                    end
                    if btn._eabShapeBorder and btn._eabShapeBorder._eabWantsShow then
                        btn._eabShapeBorder:Show()
                    end
                    -- Make hidden empty buttons visible during drag
                    btn:Show()
                    if btn:GetAlpha() < 0.01 then
                        btn:SetAlpha(1)
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Apply All orchestrates full visual application
-------------------------------------------------------------------------------
local function ApplyAll()
    -- Restore any strata raised during a drag that wasn't cleaned up
    if _dragVisible then
        _dragVisible = false
        for frame, orig in pairs(_dragStrataCache) do
            frame:SetFrameStrata(orig)
        end
        wipe(_dragStrataCache)
    end

    local inCombat = InCombatLockdown()

    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local s = EAB.db.profile.bars[key]
        local frame = barFrames[key]

        -- Bar enabled/disabled toggle (protected frames can't be shown/hidden in combat)
        if frame and s and not inCombat then
            if s.enabled == false then
                frame:Hide()
            elseif not s.alwaysHidden then
                frame:Show()
            end
        end

        if not inCombat then
            EAB:ApplyScaleForBar(key)
            LayoutBar(key)
        end
        EAB:ApplyBordersForBar(key)
        if not inCombat then EAB:ApplyShapesForBar(key) end
        EAB:ApplyFontsForBar(key)
        EAB:ApplyBackgroundForBar(key)
        if not inCombat then EAB:ApplyAlwaysShowButtons(key) end
        if not inCombat then EAB:ApplyClickThroughForBar(key) end
    end

    EAB:ApplyPushedTextures()
    EAB:ApplyHighlightTextures()
    EAB:ApplyCooldownEdge()
    EAB:ApplyMiscTextures()
    if not inCombat then EAB:ApplyCombatVisibility() end
    if not inCombat then EAB:ApplyAlwaysHidden() end
    EAB:RefreshMouseover()
    EAB:RefreshProcGlows()
    EAB:ApplyRangeColoring()
end

-------------------------------------------------------------------------------
--  Position Save/Restore
-------------------------------------------------------------------------------
local function SaveBarPosition(barKey)
    local frame = barFrames[barKey]
    if not frame then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then
        EAB.db.profile.barPositions[barKey] = {
            point = point, relPoint = relPoint, x = x, y = y,
        }
    end
end

local function RestoreBarPositions()
    local positions = EAB.db.profile.barPositions
    if not positions then return end
    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local pos = positions[key]
        local frame = barFrames[key]
        if pos and frame then
            frame:ClearAllPoints()
            frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
        end
    end
end


-------------------------------------------------------------------------------
--  Unlock Mode Integration
--  Register bars with EUI_UnlockMode for positioning.
-------------------------------------------------------------------------------
local function RegisterWithUnlockMode()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end

    local elements = {}
    local orderBase = 200  -- action bars sort after unit frames (100+)

    for idx, info in ipairs(BAR_CONFIG) do
        local key = info.key
        elements[#elements + 1] = {
            key   = key,
            label = info.label,
            group = "Action Bars",
            order = orderBase + idx,
            isHidden = function()
                local s = EAB.db.profile.bars[info.key]
                return s and s.alwaysHidden
            end,
            getFrame = function()
                return barFrames[info.key]
            end,
            getSize = function()
                local frame = barFrames[info.key]
                if frame then return frame:GetWidth(), frame:GetHeight() end
                return 1, 1
            end,
            getScale = function()
                local s = EAB.db.profile.bars[info.key]
                return s and s.barScale or 1.0
            end,
            savePosition = function(_, point, relPoint, x, y, scale)
                if point and x and y then
                    EAB.db.profile.barPositions[info.key] = {
                        point = point, relPoint = relPoint or point, x = x, y = y,
                    }
                else
                    SaveBarPosition(info.key)
                end
                if scale then
                    EAB.db.profile.bars[info.key].barScale = scale
                    EAB:ApplyScaleForBar(info.key)
                end
            end,
            restorePosition = function()
                local pos = EAB.db.profile.barPositions[info.key]
                local frame = barFrames[info.key]
                if pos and frame then
                    frame:ClearAllPoints()
                    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
                end
            end,
        }
    end

    -- Blizzard movable frames (Extra Action Button, Encounter Bar)
    local blizzOrder = orderBase + #BAR_CONFIG
    for _, info in ipairs(EXTRA_BARS) do
        if info.isBlizzardMovable then
            blizzOrder = blizzOrder + 1
            local bk = info.key
            elements[#elements + 1] = {
                key   = bk,
                label = info.label,
                group = "Action Bars",
                order = blizzOrder,
                getFrame = function()
                    return blizzMovableHolders[bk]
                end,
                getSize = function()
                    local ov = BLIZZ_MOVABLE_OVERLAY[bk]
                    if ov then return ov.w, ov.h end
                    return 50, 50
                end,
                getScale = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    return pos and pos.scale or 1.0
                end,
                loadPosition = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    if not pos then return nil end
                    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y, scale = pos.scale }
                end,
                savePosition = function(_, point, relPoint, x, y, scale)
                    if point and x and y then
                        EAB.db.profile.barPositions[bk] = {
                            point = point, relPoint = relPoint or point, x = x, y = y,
                            scale = scale,
                        }
                    end
                    -- Apply to holder immediately
                    local holder = blizzMovableHolders[bk]
                    if holder and point and x and y and not InCombatLockdown() then
                        holder:ClearAllPoints()
                        holder:SetPoint(point, UIParent, relPoint or point, x, y)
                        if scale then holder:SetScale(scale) end
                    end
                end,
                clearPosition = function()
                    EAB.db.profile.barPositions[bk] = nil
                end,
                applyPosition = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    local holder = blizzMovableHolders[bk]
                    if not holder or InCombatLockdown() then return end
                    holder:ClearAllPoints()
                    if pos then
                        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
                        if pos.scale then holder:SetScale(pos.scale) end
                    else
                        -- Reset to centered default
                        holder:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
                    end
                end,
            }
        end
    end

    -- Vehicle Exit Button
    do
        local vBtn = MainMenuBarVehicleLeaveButton
        if vBtn then
            blizzOrder = blizzOrder + 1
            elements[#elements + 1] = {
                key   = "VehicleExit",
                label = "Vehicle Exit",
                group = "Action Bars",
                order = blizzOrder,
                getFrame = function()
                    return vBtn
                end,
                getSize = function()
                    return vBtn:GetWidth(), vBtn:GetHeight()
                end,
                getScale = function() return 1.0 end,
                loadPosition = function()
                    local pos = EAB.db.profile.barPositions["VehicleExit"]
                    if not pos then return nil end
                    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
                end,
                savePosition = function(_, point, relPoint, x, y)
                    if point and x and y then
                        EAB.db.profile.barPositions["VehicleExit"] = {
                            point = point, relPoint = relPoint or point, x = x, y = y,
                        }
                    end
                    -- Apply immediately
                    if not InCombatLockdown() then
                        vBtn:ClearAllPoints()
                        vBtn:SetPoint(point, UIParent, relPoint or point, x, y)
                    end
                end,
                clearPosition = function()
                    EAB.db.profile.barPositions["VehicleExit"] = nil
                end,
                applyPosition = EAB.AnchorVehicleButton,
            }
        end
    end

    EllesmereUI:RegisterUnlockElements(elements)
end

-------------------------------------------------------------------------------
--  Initialization
-------------------------------------------------------------------------------
function EAB:OnInitialize()
    -- Detect first install BEFORE AceDB creates the saved variable.
    -- We use a dedicated flag so "Reset to Defaults" also re-captures.
    local rawDB = EllesmereUIActionBarsDB
    local isFirstInstall = not rawDB or not rawDB.profiles
        or (rawDB.profiles and not next(rawDB.profiles))

    self.db = EllesmereUI.Lite.NewDB("EllesmereUIActionBarsDB", defaults, true)

    -- Migration: move _capturedOnce from per-profile to per-install (SV root).
    -- Check all profiles for the old flag and promote it.
    local sv = self.db.sv
    if not sv._capturedOnce then
        if sv.profiles then
            for _, prof in pairs(sv.profiles) do
                if type(prof) == "table" and prof._capturedOnce then
                    sv._capturedOnce = true
                    break
                end
            end
        end
    end
    -- Strip the old per-profile flag from all profiles
    if sv.profiles then
        for _, prof in pairs(sv.profiles) do
            if type(prof) == "table" then prof._capturedOnce = nil end
        end
    end

    -- Mark whether we need to capture Blizzard layout on first install.
    -- The actual capture is deferred to PLAYER_ENTERING_WORLD when
    -- Edit Mode has fully applied bar positions/sizes.
    -- Uses the per-install flag on the SV root, not per-profile.
    self._needsCapture = not sv._capturedOnce

    -- Migration: convert old settings formats if needed
    local p = self.db.profile
    if p.font and p.font:find("EllesmereUIActionBars") and not p.font:find("\\EllesmereUI\\") then
        -- Old path without EllesmereUI subfolder leave as-is, fonts are at addon root
    end

    -- Migration: convert old boolean visibility flags to unified barVisibility key
    if p.bars then
        for _, s in pairs(p.bars) do
            if type(s) == "table" and s.barVisibility == nil then
                if s.alwaysHidden then
                    s.barVisibility = "never"
                elseif s.mouseoverEnabled then
                    s.barVisibility = "mouseover"
                elseif s.combatHideEnabled then
                    s.barVisibility = "never"  -- hide_combat mapped to in_combat inverse
                elseif s.combatShowEnabled then
                    s.barVisibility = "in_combat"
                else
                    s.barVisibility = "always"
                end
            end
            -- Migration: convert old housingHideEnabled to new visHideHousing
            if type(s) == "table" and s.visHideHousing == nil and s.housingHideEnabled ~= nil then
                s.visHideHousing = s.housingHideEnabled
            end
        end
    end

    -- Slash commands
    -- Expose apply hook for PP scale change re-apply
    _G._EAB_Apply = function()
        ApplyAll()
        if not InCombatLockdown() then RestoreBarPositions() end
    end

    SLASH_ELLESMEREACTIONBARS1 = "/eab"
    SlashCmdList["ELLESMEREACTIONBARS"] = function(msg)
        if EllesmereUI and EllesmereUI.Toggle then
            EllesmereUI:Toggle()
        end
    end

    -- Diagnostic: /eabmouse -- prints all frames under the cursor that have
    -- mouse enabled, so we can identify what is eating clicks.
    SLASH_EABMOUSE1 = "/eabmouse"
    SlashCmdList["EABMOUSE"] = function()
        local focus = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
        print("|cff00ccff[EAB Mouse Debug]|r Frames under cursor:")
        if not focus or #focus == 0 then
            print("  (none)")
            return
        end
        for i, f in ipairs(focus) do
            local name = f:GetName() or tostring(f)
            local pName = f:GetParent() and (f:GetParent():GetName() or tostring(f:GetParent())) or "nil"
            local shown = f:IsShown() and "shown" or "hidden"
            local mouse = f:IsMouseEnabled() and "mouse=ON" or "mouse=off"
            local w, h = f:GetSize()
            local strata = f:GetFrameStrata()
            local level = f:GetFrameLevel()
            print(("  %d: %s [%s, %s] size=%.0fx%.0f strata=%s level=%d parent=%s"):format(
                i, name, shown, mouse, w or 0, h or 0, strata, level, pName))
        end
        -- Also check specific suspect frames
        local suspects = {
            { "ExtraAbilityContainer", ExtraAbilityContainer },
            { "ExtraActionBarFrame", ExtraActionBarFrame },
            { "ExtraActionButton1", _G["ExtraActionButton1"] },
            { "PlayerPowerBarAlt", PlayerPowerBarAlt },
            { "UIWidgetPowerBarContainerFrame", UIWidgetPowerBarContainerFrame },
            { "UIParentBottomManagedFrameContainer", UIParentBottomManagedFrameContainer },
        }
        print("|cff00ccff[EAB Mouse Debug]|r Suspect frames:")
        for _, s in ipairs(suspects) do
            local sName, sFrame = s[1], s[2]
            if sFrame then
                local shown = sFrame:IsShown() and "shown" or "hidden"
                local mouse = sFrame:IsMouseEnabled() and "mouse=ON" or "mouse=off"
                local pName = sFrame:GetParent() and (sFrame:GetParent():GetName() or tostring(sFrame:GetParent())) or "nil"
                local vis = sFrame:IsVisible() and "visible" or "not-visible"
                local w, h = sFrame:GetSize()
                print(("  %s: [%s, %s, %s] size=%.0fx%.0f parent=%s"):format(
                    sName, shown, vis, mouse, w or 0, h or 0, pName))
            else
                print(("  %s: nil"):format(sName))
            end
        end
    end

end

function EAB:OnEnable()
    -- If this is a first install (or reset), we need to capture Blizzard's
    -- Edit Mode layout BEFORE hiding bars. Defer the full setup to
    -- PLAYER_ENTERING_WORLD so Edit Mode has applied positions.
    if self._needsCapture then
        self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnFirstLogin")
    else
        self:FinishSetup()
    end
end

-- Called on PLAYER_ENTERING_WORLD for first-install only.
-- At this point Edit Mode has applied bar positions/sizes/rows.
function EAB:OnFirstLogin()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    -- Capture Blizzard layout while bars are still visible
    local captured = CaptureBlizzardDefaults()
    for barKey, data in pairs(captured) do
        local s = self.db.profile.bars[barKey]
        if s and data then
            if data.numIcons then s.overrideNumIcons = data.numIcons end
            if data.numRows then s.overrideNumRows = data.numRows end
            if data.orientation then s.orientation = data.orientation end
            if data.blizzIconScale then
                s.barScale = data.blizzIconScale
            end
            if data.alwaysShowButtons ~= nil then
                s.alwaysShowButtons = data.alwaysShowButtons
            end
            -- Visibility: 3=Hidden set alwaysHidden
            -- 1=InCombat combatShowEnabled, 2=OutOfCombat combatHideEnabled
            if data.visibility then
                if data.visibility == 3 then
                    s.alwaysHidden = true
                elseif data.visibility == 1 then
                    s.combatShowEnabled = true
                elseif data.visibility == 2 then
                    s.combatHideEnabled = true
                end
            end
            if data.point then
                -- Divide position offsets by the bar's scale so that when
                -- WoW applies SetScale() the on-screen position matches
                -- the original Blizzard Edit Mode position exactly.
                local scale = s.barScale or 1.0
                if scale < 0.1 then scale = 1.0 end
                self.db.profile.barPositions[barKey] = {
                    point = data.point, relPoint = data.relPoint,
                    x = data.x / scale, y = data.y / scale,
                }
            end
        end
    end

    -- Mark capture as done so we never read Edit Mode again (per-install flag)
    self.db.sv._capturedOnce = true
    self._needsCapture = false

    -- Stance bar visibility must always be "Always" it manages its own
    -- show/hide based on shapeshift form availability.
    local sb = self.db.profile.bars["StanceBar"]
    if sb then
        sb.alwaysHidden       = false
        sb.combatShowEnabled  = false
        sb.combatHideEnabled  = false
    end

    -- Now proceed with normal setup
    self:FinishSetup()
end

-- The actual bar creation, positioning, and event registration.
function EAB:FinishSetup()
    -- Prepare secure handler refs (must happen before any setup path)
    SecureSetupHandler_PrepareRefs()

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
                self:ApplyScaleForBar(info.key)
                LayoutBar(info.key)
            end
            RestoreBarPositions()
            EAB.AnchorVehicleButton()
            -- Set up MainBar paging
            local mainFrame = barFrames["MainBar"]
            if mainFrame then
                local curOffset = mainFrame:GetAttribute("actionOffset") or 0
                local mainBtns = barButtons["MainBar"]
                if mainBtns then
                    for i, btn in ipairs(mainBtns) do
                        if btn then
                            btn:SetAttribute("index", i)
                            btn:SetAttribute("_childupdate-offset", [[
                                local offset = message or 0
                                local id = self:GetAttribute("index") + offset
                                if self:GetAttribute("action") ~= id then
                                    self:SetAttribute("action", id)
                                end
                            ]])
                            btn:SetAttribute("action", i + curOffset)
                        end
                    end
                end
            end
        else
            -- Combat reload: non-protected setup only; secure handler does the rest.
            -- Unregister Blizzard bar events (non-protected)
            for _, name in ipairs(BLIZZARD_BARS_TO_HIDE) do
                local bar = _G[name]
                if bar then bar:UnregisterAllEvents() end
            end
            if MainActionBarController then MainActionBarController:UnregisterAllEvents() end
            if not (EAB.db and EAB.db.profile.useBlizzardDataBars) then
                if StatusTrackingBarManager then
                    StatusTrackingBarManager:UnregisterAllEvents()
                end
            end
            if MainMenuBarPageNumber then MainMenuBarPageNumber:Hide() end
            if ActionBarParent then
                RegisterAttributeDriver(ActionBarParent, "state-visibility", "[vehicleui][overridebar] show; hide")
            end
            if OverrideActionBar then
                RegisterAttributeDriver(OverrideActionBar, "state-visibility", "[vehicleui][overridebar] show; hide")
            end
            C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_1", "1")
            C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_2", "1")
            C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_3", "1")
            C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_4", "1")

            -- Create bar frames and register button refs (no protected ops)
            for _, info in ipairs(BAR_CONFIG) do
                SetupBar(info, true)
                self:ApplyScaleForBar(info.key)
            end

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
                                -- so the secure snippet can set up _childupdate-offset paging
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

        -- Visual styling: defer visuals to out-of-combat if needed.
        local combatReloaded = InCombatLockdown()
        local function DoVisuals()
            ApplyAll()
            ApplyKeyDownCVar()
            self:HookProcGlow()
            self:ScanExistingProcs()
            EAB.AnchorVehicleButton()
        end

        if InCombatLockdown() then
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_REGEN_ENABLED")
            f:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                C_Timer_After(0.1, DoVisuals)
            end)
        else
            C_Timer_After(0.1, DoVisuals)
        end
    end

    DoSetupSecure()
    -- Attach hover hooks for mouseover
    for _, info in ipairs(BAR_CONFIG) do
        AttachHoverHooks(info.key)
    end

    -- When a spell flyout closes, fade out any bars that were kept visible by it
    do
        local flyFrame = EABFlyout:GetFrame()
        if flyFrame then
            flyFrame:HookScript("OnHide", function()
                for key, state in pairs(hoverStates) do
                    if not state.isHovered then
                        local s = EAB.db.profile.bars[key]
                        if s and s.mouseoverEnabled and state.fadeDir ~= "out" then
                            state.fadeDir = "out"
                            FadeTo(state.frame, 0, s.mouseoverSpeed or 0.15)
                        end
                    end
                end
            end)
        end
    end

    -- When UIParent's scale changes, the coordinate space shifts. Re-save
    -- all bar positions from their current frame anchors (which WoW has
    -- already adjusted) so the DB stays in sync with the new scale.
    do
        local _scaleFrame = CreateFrame("Frame")
        _scaleFrame:RegisterEvent("UI_SCALE_CHANGED")
        _scaleFrame:SetScript("OnEvent", function()
            if InCombatLockdown() then return end
            local positions = EAB.db.profile.barPositions
            if not positions then return end
            for _, info in ipairs(BAR_CONFIG) do
                local key = info.key
                local frame = barFrames[key]
                if frame and positions[key] then
                    local pt, _, rpt, px, py = frame:GetPoint(1)
                    if pt then
                        positions[key].point    = pt
                        positions[key].relPoint = rpt
                        positions[key].x        = px
                        positions[key].y        = py
                    end
                end
            end
        end)
    end

    -- Register events
    local _bindDeferFrame
    self:RegisterEvent("UPDATE_BINDINGS", function()
        if InCombatLockdown() then
            if not _bindDeferFrame then
                _bindDeferFrame = CreateFrame("Frame")
                _bindDeferFrame:SetScript("OnEvent", function(self)
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    UpdateKeybinds()
                end)
            end
            _bindDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            UpdateKeybinds()
        end
        self:ApplyFonts()
    end)

    self:RegisterEvent("ACTIONBAR_SHOWGRID", OnGridChange)
    -- Pet actions fire their own grid events when dragging pet spells
    self:RegisterEvent("PET_BAR_SHOWGRID", OnGridChange)

    -- Re-apply useOnKeyDown when the "Press and Hold Casting" CVar changes.
    self:RegisterEvent("CVAR_UPDATE", function(_, cvarName)
        if cvarName == "ActionButtonUseKeyDown" then
            ApplyKeyDownCVar()
        end
    end)

    -- Detect bar-to-bar drags (CURSOR_CHANGED) and clear grid state on drop.
    -- Also show mouseover-faded bars while dragging so the player can drop
    -- spells/items onto them.  Purely visual -- no secure frame access.
    local DRAG_TYPES = {
        spell = true, item = true, macro = true,
        petaction = true, mount = true, companion = true,
    }
    _dragVisible = false
    _dragStrataCache = {}  -- [frame] = originalStrata
    local function ResetDragState()
        -- Force-restore all strata and clear drag visibility without the
        -- guard check, so stale state from spec changes etc. is always cleaned.
        _dragVisible = false
        for frame, orig in pairs(_dragStrataCache) do
            if not InCombatLockdown() then
                frame:SetFrameStrata(orig)
            end
        end
        wipe(_dragStrataCache)
    end
    local function SetDragVisible(show)
        if _dragVisible == show then return end
        _dragVisible = show
        for _, info in ipairs(ALL_BARS) do
            local key = info.key
            local s = self.db.profile.bars[key]
            if not s then break end
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
                        if not _dragStrataCache[frame] then
                            _dragStrataCache[frame] = frame:GetFrameStrata()
                        end
                        frame:SetFrameStrata("HIGH")
                    end
                    -- Show mouseover-faded bars
                    if s.mouseoverEnabled then
                        StopFade(frame)
                        frame:SetAlpha(s.mouseoverAlpha or 1)
                        if state then state.fadeDir = "in" end
                    end
                else
                    -- Restore original strata (only if we changed it)
                    if not InCombatLockdown() then
                        local orig = _dragStrataCache[frame]
                        if orig then
                            frame:SetFrameStrata(orig)
                            _dragStrataCache[frame] = nil
                        end
                    end
                    -- Fade back out if mouseover-enabled and not hovered
                    if s.mouseoverEnabled then
                        if not (state and state.isHovered) then
                            StopFade(frame)
                            FadeTo(frame, 0, s.mouseoverSpeed or 0.15)
                            if state then state.fadeDir = "out" end
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
                if not gridShown then
                    OnGridChange()
                end
            end
        else
            SetDragVisible(false)
            if gridShown then
                gridShown = false
                C_Timer_After(0, function()
                    for _, info in ipairs(BAR_CONFIG) do
                        self:ApplyAlwaysShowButtons(info.key)
                    end
                end)
            end
        end
    end)

    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        -- Re-apply anything that was deferred during combat
        ApplyAll()
        -- Restore any strata changes that couldn't be done in combat
        ResetDragState()
    end)

    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        -- After any loading screen (teleport, instance, etc.), reset vehicle/
        -- housing keybind flags and re-apply bindings.  WoW can briefly report
        -- vehicleui/overridebar during zone transitions, which clears our
        -- override bindings.  If the restore races with InCombatLockdown()
        -- the bindings stay cleared forever.  This catches that.
        ResetDragState()
        C_Timer_After(0.2, function()
            if InCombatLockdown() then return end
            -- Reset stale flags -- if we're not actually in a vehicle/housing
            -- the flags should be false
            local inVehicle = (UnitInVehicle and UnitInVehicle("player"))
                              or (HasVehicleActionBar and HasVehicleActionBar())

            if not inVehicle and _vehicleBindsCleared then
                _vehicleBindsCleared = false
            end
            local inHousing = IsHouseEditorActive and IsHouseEditorActive()
            if not inHousing and _housingBindsCleared then
                _housingBindsCleared = false
            end
            UpdateKeybinds()
        end)
    end)

    -- Vehicle enter/exit: clear our override bindings so Blizzard's vehicle bar
    -- receives keybinds. Restore them when the player exits the vehicle.
    -- Use a raw frame for unit events since Ace3 RegisterEvent doesn't support them.
    local _vehicleEventFrame = CreateFrame("Frame")
    _vehicleEventFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    _vehicleEventFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    _vehicleEventFrame:SetScript("OnEvent", function(self, event)
        if event == "UNIT_ENTERED_VEHICLE" then
            ClearKeybindsForVehicle()
            -- Block Edit Mode while on a vehicle to avoid taint from our
            -- hidden/reparented Blizzard bars causing it to silently close.
            if EditModeManagerFrame then
                EditModeManagerFrame:BlockEnteringEditMode(self)
            end
        elseif event == "UNIT_EXITED_VEHICLE" then
            RestoreKeybindsAfterVehicle()
            if EditModeManagerFrame then
                EditModeManagerFrame:UnblockEnteringEditMode(self)
            end
        end
    end)

    local function QueueAlwaysShowButtonsRefresh()
        -- During drag, skip. OnGridChange already shows everything, and
        -- HIDEGRID / CURSOR_CHANGED will restore afterwards.
        if gridShown then return end
        if _buttonVisibilityPending then return end
        _buttonVisibilityPending = true
        C_Timer_After(0, function()
            _buttonVisibilityPending = false
            if gridShown then return end
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

    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
        self:UpdateHousingVisibility()
    end)

    -- Visibility option events: mounted, target, group changes
    self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", function()
        self:UpdateHousingVisibility()
    end)
    self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
        self:UpdateHousingVisibility()
    end)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        self:UpdateHousingVisibility()
    end)

    -- Grid hide: restore empty slot visibility
    local function OnGridHide()
        gridShown = false
        for _, info in ipairs(BAR_CONFIG) do
            self:ApplyAlwaysShowButtons(info.key)
        end
    end
    self:RegisterEvent("ACTIONBAR_HIDEGRID", OnGridHide)
    self:RegisterEvent("PET_BAR_HIDEGRID", OnGridHide)

    -- Spell updates: refresh button icons and visibility
    -- Also re-layout the stance bar since GetNumShapeshiftForms() may have changed
    self:RegisterEvent("SPELLS_CHANGED", function()
        if _spellsChangedPending then return end
        _spellsChangedPending = true
        C_Timer_After(0, function()
            _spellsChangedPending = false
            LayoutBar("StanceBar")
            for _, info in ipairs(BAR_CONFIG) do
                self:ApplyAlwaysShowButtons(info.key)
            end
        end)
    end)

    -- Slot changed: update visibility when a spell is placed/removed from a slot.
    -- This can fire per-slot (12+ times during a bar page swap), so use the
    -- shared debounced visibility queue.
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", QueueAlwaysShowButtonsRefresh)

    -- Pet bar: re-layout and refresh visibility when the pet's action bar
    -- changes. PET_BAR_UPDATE covers ability changes; PET_UI_UPDATE covers
    -- summoning/dismissal; UNIT_PET covers pet swaps. PLAYER_ENTERING_WORLD
    -- ensures button state is populated on login (PetActionBar was
    -- unregistered from all events, so Blizzard's own update never fires).
    local function UpdatePetBar(_, event)
        C_Timer_After(0, function()
            if event == "PET_BAR_UPDATE_COOLDOWN" then
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
            -- Full update path: only safe out of combat.
            if InCombatLockdown() then return end
            if gridShown then
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
            if PetActionBar and PetActionBar.Update then
                PetActionBar:Update()
            end
            LayoutBar("PetBar")
            self:ApplyAlwaysShowButtons("PetBar")
            -- Re-register the state driver so the [pet] condition is always
            -- current after a pet summon, swap, or dismissal.
            local petInfo = BAR_LOOKUP["PetBar"]
            local petFrame = barFrames["PetBar"]
            local petS = self.db.profile.bars["PetBar"]
            if petInfo and petFrame and petS and not petS.alwaysHidden then
                RegisterAttributeDriver(petFrame, "state-visibility", BuildVisibilityString(petInfo, petS))
            end
        end)
    end
    local _petEventFrame = CreateFrame("Frame")
    _petEventFrame:RegisterEvent("PET_BAR_UPDATE")
    _petEventFrame:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
    _petEventFrame:RegisterEvent("PET_UI_UPDATE")
    _petEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _petEventFrame:RegisterUnitEvent("UNIT_PET", "player")
    _petEventFrame:SetScript("OnEvent", UpdatePetBar)


    -- Talent changes can cause Blizzard to re-show hidden bars.
    -- Re-run the hider and re-unregister events on the affected frames.
    self:RegisterEvent("PLAYER_TALENT_UPDATE", function()
        if InCombatLockdown() then return end
        for _, name in ipairs(BLIZZARD_BARS_TO_HIDE) do
            local bar = _G[name]
            if bar then
                bar:UnregisterAllEvents()
                bar:SetParent(hiddenParent)
                bar:Hide()
            end
        end
        if MainActionBarController then
            MainActionBarController:UnregisterAllEvents()
        end
    end)

    -- Hook Show on the Blizzard bars so they can never re-appear regardless
    -- of what fires them (talent changes, spec swaps, zone transitions, etc.)
    for _, name in ipairs(BLIZZARD_BARS_TO_HIDE) do
        local bar = _G[name]
        if bar then
            bar:HookScript("OnShow", function(self)
                self:Hide()
            end)
        end
    end

    -- Register with unlock mode (deferred to ensure EllesmereUI is loaded)
    C_Timer_After(0.5, RegisterWithUnlockMode)
end

-------------------------------------------------------------------------------
--  Data Bars (XP Bar, Reputation Bar)
-------------------------------------------------------------------------------
-- dataBarFrames is forward-declared near barFrames at the top of the file
ns.dataBarFrames = dataBarFrames

-- XP bar colors
local XP_COLOR_RESTED    = { r = 0.00, g = 0.44, b = 0.87 }  -- shaman blue (XP when rested)
local XP_COLOR_NO_REST   = { r = 0.60, g = 0.40, b = 0.85 }  -- purple (XP when no rested)
local XP_RESTED_COLOR    = { r = 0.15, g = 0.30, b = 0.60 }  -- dark blue (rested overlay)

-- Reputation standing colors (1=Hated through 8=Exalted, 9=Paragon, 10=Renown)
local REP_COLORS = {
    [1] = { r = 0.80, g = 0.20, b = 0.20 },  -- Hated
    [2] = { r = 0.75, g = 0.30, b = 0.15 },  -- Hostile
    [3] = { r = 0.75, g = 0.45, b = 0.15 },  -- Unfriendly
    [4] = { r = 0.80, g = 0.70, b = 0.20 },  -- Neutral
    [5] = { r = 0.30, g = 0.70, b = 0.25 },  -- Friendly
    [6] = { r = 0.25, g = 0.65, b = 0.50 },  -- Honored
    [7] = { r = 0.25, g = 0.50, b = 0.75 },  -- Revered
    [8] = { r = 0.35, g = 0.30, b = 0.80 },  -- Exalted
    [9] = { r = 0.80, g = 0.65, b = 0.20 },  -- Paragon
    [10] = { r = 0.20, g = 0.70, b = 0.85 }, -- Renown
}

local function ApplyDataBarLayout(barKey)
    local frame = dataBarFrames[barKey]
    if not frame then return end
    local s = EAB.db.profile.bars[barKey]
    if not s then return end
    local w = s.width or 400
    local h = s.height or 18
    local orient = s.orientation or "HORIZONTAL"

    -- Preserve center position when resizing so growth is centered
    local oldW, oldH = frame:GetWidth(), frame:GetHeight()
    local cx, cy
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top then
        cx = left + oldW * 0.5
        cy = top - oldH * 0.5
    end

    local PP = EllesmereUI and EllesmereUI.PP
    if PP then
        PP.Size(frame, w, h)
    else
        frame:SetSize(w, h)
    end

    frame._bar:SetOrientation(orient)
    frame._bar:SetRotatesTexture(orient ~= "HORIZONTAL")
    if frame._restedBar then
        frame._restedBar:SetOrientation(orient)
        frame._restedBar:SetRotatesTexture(orient ~= "HORIZONTAL")
    end

    -- Re-center after resize if we had a valid position
    if cx and cy then
        local newHalfW = frame:GetWidth() * 0.5
        local newHalfH = frame:GetHeight() * 0.5
        local uiH = UIParent:GetHeight()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cx - newHalfW, cy + newHalfH - uiH)
    end

    if frame._updateFunc then frame._updateFunc() end
end
ns.ApplyDataBarLayout = ApplyDataBarLayout

local function CreateDataBarFrame(barKey, updateFunc)
    local holder = CreateFrame("Frame", "EllesmereEAB_" .. barKey, UIParent)
    holder:SetSize(400, 18)
    holder:SetClampedToScreen(true)

    -- Pixel-perfect background
    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.06, 0.06, 0.08, 0.85)
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then
        PP.SetInside(bg, holder, 1, 1)
    else
        bg:SetPoint("TOPLEFT", 1, -1)
        bg:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    holder._bg = bg

    -- Pixel-perfect 1px border via MakeBorder
    if EllesmereUI and EllesmereUI.MakeBorder then
        holder._border = EllesmereUI.MakeBorder(holder, 0, 0, 0, 1)
    end

    local bar = CreateFrame("StatusBar", "EllesmereEAB_" .. barKey .. "_Bar", holder)
    bar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
    if PP then
        PP.SetInside(bar, holder, 1, 1)
    else
        bar:SetPoint("TOPLEFT", 1, -1)
        bar:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 4)

    local text = bar:CreateFontString(nil, "OVERLAY")
    text:SetFont(FONT_PATH, 9, GetEABOutline())
    if GetEABUseShadow() then text:SetShadowOffset(1, -1) end
    text:SetPoint("CENTER")
    text:SetTextColor(1, 1, 1, 1)

    holder._bar = bar
    holder._text = text
    holder._updateFunc = updateFunc

    dataBarFrames[barKey] = holder
    return holder
end

-------------------------------------------------------------------------------
--  XP Bar
-------------------------------------------------------------------------------
local function UpdateXPBar()
    local frame = dataBarFrames["XPBar"]
    if not frame then return end
    if EAB.db.profile.useBlizzardDataBars then frame:Hide(); return end
    local s = EAB.db.profile.bars["XPBar"]
    if not s then return end
    if s.alwaysHidden then frame:Hide(); return end

    local bar = frame._bar
    local text = frame._text

    -- Hide at max level (or XP disabled)
    if (IsLevelAtEffectiveMaxLevel and IsLevelAtEffectiveMaxLevel(UnitLevel("player")))
        or (IsXPUserDisabled and IsXPUserDisabled()) then
        frame:Hide()
        return
    end

    frame:Show()

    local currentXP = UnitXP("player")
    local maxXP = UnitXPMax("player")
    if maxXP <= 0 then maxXP = 1 end
    local restedXP = GetXPExhaustion() or 0

    bar:SetMinMaxValues(0, maxXP)
    bar:SetValue(currentXP)

    -- Rested XP overlay
    local restedBar = frame._restedBar
    if restedXP > 0 then
        bar:SetStatusBarColor(XP_COLOR_RESTED.r, XP_COLOR_RESTED.g, XP_COLOR_RESTED.b)
        restedBar:SetMinMaxValues(0, maxXP)
        restedBar:SetValue(min(currentXP + restedXP, maxXP))
        restedBar:SetStatusBarColor(XP_RESTED_COLOR.r, XP_RESTED_COLOR.g, XP_RESTED_COLOR.b, 0.5)
        restedBar:Show()
    else
        bar:SetStatusBarColor(XP_COLOR_NO_REST.r, XP_COLOR_NO_REST.g, XP_COLOR_NO_REST.b)
        restedBar:Hide()
    end

    local pct = (currentXP / maxXP) * 100
    if restedXP > 0 then
        local restedPct = (restedXP / maxXP) * 100
        text:SetText(format("%.1f%% (Rested: %.1f%%)", pct, restedPct))
    else
        text:SetText(format("%.1f%%", pct))
    end
end

local function CreateXPBar()
    local holder = CreateDataBarFrame("XPBar", UpdateXPBar)
    holder:SetPoint("TOP", UIParent, "TOP", 0, -100)

    -- Rested XP overlay bar (behind main bar)
    local restedBar = CreateFrame("StatusBar", "EllesmereEAB_XPBar_Rested", holder)
    restedBar:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then
        PP.SetInside(restedBar, holder, 1, 1)
    else
        restedBar:SetPoint("TOPLEFT", 1, -1)
        restedBar:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    restedBar:SetMinMaxValues(0, 1)
    restedBar:SetValue(0)
    restedBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 2)
    restedBar:Hide()
    holder._restedBar = restedBar

    -- Tooltip
    holder:EnableMouse(true)
    holder:SetScript("OnEnter", function(self)
        if (IsLevelAtEffectiveMaxLevel and IsLevelAtEffectiveMaxLevel(UnitLevel("player")))
            or (IsXPUserDisabled and IsXPUserDisabled()) then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        local currentXP = UnitXP("player")
        local maxXP = UnitXPMax("player")
        if maxXP <= 0 then maxXP = 1 end
        local restedXP = GetXPExhaustion() or 0
        local pct = (currentXP / maxXP) * 100
        local remain = maxXP - currentXP
        GameTooltip:AddLine("Experience", 1, 1, 1)
        GameTooltip:AddDoubleLine("Level", tostring(UnitLevel("player")), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("XP", format("%s / %s (%.1f%%)", BreakUpLargeNumbers(currentXP), BreakUpLargeNumbers(maxXP), pct), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Remaining", BreakUpLargeNumbers(remain), 1, 1, 1, 1, 1, 1)
        if restedXP > 0 then
            GameTooltip:AddDoubleLine("Rested", format("+%s (%.1f%%)", BreakUpLargeNumbers(restedXP), (restedXP / maxXP) * 100), 1, 1, 1, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    holder:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Events
    local evFrame = CreateFrame("Frame")
    evFrame:RegisterEvent("PLAYER_XP_UPDATE")
    evFrame:RegisterEvent("PLAYER_LEVEL_UP")
    evFrame:RegisterEvent("UPDATE_EXHAUSTION")
    evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evFrame:SetScript("OnEvent", UpdateXPBar)

    ApplyDataBarLayout("XPBar")
    UpdateXPBar()
end

-------------------------------------------------------------------------------
--  Reputation Bar
-------------------------------------------------------------------------------
local function UpdateRepBar()
    local frame = dataBarFrames["RepBar"]
    if not frame then return end
    if EAB.db.profile.useBlizzardDataBars then frame:Hide(); return end
    local s = EAB.db.profile.bars["RepBar"]
    if not s then return end
    if s.alwaysHidden then frame:Hide(); return end

    local bar = frame._bar
    local text = frame._text

    local data = C_Reputation and C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
    if not data or not data.name then
        frame:Hide()
        return
    end

    frame:Show()

    local name = data.name
    local reaction = data.reaction or 4
    local factionID = data.factionID
    local currentStanding = data.currentStanding or 0
    local currentReactionThreshold = data.currentReactionThreshold or 0
    local nextReactionThreshold = data.nextReactionThreshold or 1
    local standing

    -- Friendship handling (check first friendships override normal standing)
    local isFriendship = false
    if factionID then
        local friendInfo = C_GossipInfo and C_GossipInfo.GetFriendshipReputation and C_GossipInfo.GetFriendshipReputation(factionID)
        if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
            isFriendship = true
            standing = friendInfo.reaction
            currentReactionThreshold = friendInfo.reactionThreshold or 0
            nextReactionThreshold = friendInfo.nextThreshold or math.huge
            currentStanding = friendInfo.standing or 1
        end
    end

    -- Paragon handling (check before renown max-renown factions become paragon)
    local isParagon = false
    if factionID and C_Reputation.IsFactionParagonForCurrentPlayer and C_Reputation.IsFactionParagonForCurrentPlayer(factionID) then
        local paragonVal, paragonThreshold = C_Reputation.GetFactionParagonInfo(factionID)
        if paragonVal and paragonThreshold then
            isParagon = true
            standing = "Paragon"
            currentStanding = paragonVal % paragonThreshold
            currentReactionThreshold = 0
            nextReactionThreshold = paragonThreshold
            reaction = 9
        end
    end

    -- Renown handling (only if not already paragon or friendship)
    if not isParagon and not isFriendship and factionID and C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(factionID) then
        local majorData = C_MajorFactions and C_MajorFactions.GetMajorFactionData and C_MajorFactions.GetMajorFactionData(factionID)
        if majorData then
            local hasMax = C_MajorFactions.HasMaximumRenown and C_MajorFactions.HasMaximumRenown(factionID)
            if hasMax then
                frame:Hide()
                return
            end
            reaction = 10
            standing = "Renown"
            currentReactionThreshold = 0
            nextReactionThreshold = majorData.renownLevelThreshold
            currentStanding = majorData.renownReputationEarned or 0
        end
    end

    if not standing then
        standing = _G["FACTION_STANDING_LABEL" .. reaction] or ""
    end

    local color = REP_COLORS[reaction] or REP_COLORS[4]
    bar:SetStatusBarColor(color.r, color.g, color.b)

    -- Hide capped / maxed factions (Exalted with no paragon, max friendship, etc.)
    if nextReactionThreshold == math.huge or currentReactionThreshold == nextReactionThreshold then
        frame:Hide()
        return
    end

    local current = currentStanding - currentReactionThreshold
    local maximum = nextReactionThreshold - currentReactionThreshold
    if maximum <= 0 then maximum = 1 end

    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(current)

    local pct = (current / maximum) * 100
    text:SetText(format("%s: %.0f%% [%s]", name, pct, standing))

    -- Auto-size text if bar is too narrow
    local barW = frame:GetWidth()
    if text:GetStringWidth() > barW - 4 then
        text:SetText(format("%.0f%%", pct))
    end
end

local function CreateRepBar()
    local holder = CreateDataBarFrame("RepBar", UpdateRepBar)
    holder:SetPoint("TOP", UIParent, "TOP", 0, -84)

    -- Tooltip
    holder:EnableMouse(true)
    holder:SetScript("OnEnter", function(self)
        local data = C_Reputation and C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
        if not data or not data.name then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(data.name, 1, 1, 1)
        local reaction = data.reaction or 4
        local standing = _G["FACTION_STANDING_LABEL" .. reaction] or ""
        GameTooltip:AddDoubleLine("Standing", standing, 1, 1, 1, 1, 1, 1)
        local current = (data.currentStanding or 0) - (data.currentReactionThreshold or 0)
        local maximum = (data.nextReactionThreshold or 1) - (data.currentReactionThreshold or 0)
        if maximum <= 0 then maximum = 1 end
        local pct = (current / maximum) * 100
        GameTooltip:AddDoubleLine("Reputation", format("%s / %s (%.1f%%)", BreakUpLargeNumbers(current), BreakUpLargeNumbers(maximum), pct), 1, 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    holder:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Events
    local evFrame = CreateFrame("Frame")
    evFrame:RegisterEvent("UPDATE_FACTION")
    evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evFrame:RegisterEvent("QUEST_FINISHED")
    if C_MajorFactions then
        evFrame:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
        evFrame:RegisterEvent("MAJOR_FACTION_UNLOCKED")
    end
    evFrame:SetScript("OnEvent", UpdateRepBar)

    ApplyDataBarLayout("RepBar")
    UpdateRepBar()
end

-------------------------------------------------------------------------------
--  Register Data Bars with Unlock Mode
--  Uses the same pattern as action bars and blizzard movable frames:
--  savePosition / loadPosition / applyPosition / clearPosition callbacks.
-------------------------------------------------------------------------------
local function RegisterDataBarsWithUnlockMode()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local elements = {}
    local orderBase = 300  -- after action bars (200+)
    for idx, info in ipairs(EXTRA_BARS) do
        if info.isDataBar then
            local bk = info.key
            elements[#elements + 1] = {
                key   = bk,
                label = info.label,
                group = "Action Bars",
                order = orderBase + idx,
                getFrame = function()
                    return dataBarFrames[bk]
                end,
                getSize = function()
                    local frame = dataBarFrames[bk]
                    if frame then return frame:GetWidth(), frame:GetHeight() end
                    return 400, 18
                end,
                getScale = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    return pos and pos.scale or 1.0
                end,
                loadPosition = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    if not pos then return nil end
                    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y, scale = pos.scale }
                end,
                savePosition = function(_, point, relPoint, x, y, scale)
                    if point and x and y then
                        EAB.db.profile.barPositions[bk] = {
                            point = point, relPoint = relPoint or point, x = x, y = y,
                            scale = scale,
                        }
                    end
                    local frame = dataBarFrames[bk]
                    if frame and point and x and y then
                        frame:ClearAllPoints()
                        frame:SetPoint(point, UIParent, relPoint or point, x, y)
                        if scale then frame:SetScale(scale) end
                    end
                end,
                clearPosition = function()
                    EAB.db.profile.barPositions[bk] = nil
                end,
                applyPosition = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    local frame = dataBarFrames[bk]
                    if not frame then return end
                    frame:ClearAllPoints()
                    if pos and pos.point then
                        frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
                        if pos.scale then frame:SetScale(pos.scale) end
                    else
                        -- Default positions
                        if bk == "XPBar" then
                            frame:SetPoint("TOP", UIParent, "TOP", 0, -100)
                        elseif bk == "RepBar" then
                            frame:SetPoint("TOP", UIParent, "TOP", 0, -84)
                        end
                    end
                end,
            }
        end
    end
    EllesmereUI:RegisterUnlockElements(elements)
end

local function SetupDataBars()
    -- Skip creating custom bars entirely if user wants Blizzard to control them
    if EAB.db.profile.useBlizzardDataBars then return end

    CreateXPBar()
    CreateRepBar()

    -- Apply visibility settings (mouseover, combat, etc.)
    for _, info in ipairs(EXTRA_BARS) do
        if info.isDataBar then
            local frame = dataBarFrames[info.key]
            if frame then
                local s = EAB.db.profile.bars[info.key]
                if s then
                    -- Apply click-through setting
                    if s.clickThrough then
                        SafeEnableMouse(frame, false)
                    end
                    if s.mouseoverEnabled then
                        local state = { isHovered = false, fadeDir = nil }
                        frame:HookScript("OnEnter", function()
                            state.isHovered = true
                            if state.fadeDir ~= "in" then
                                state.fadeDir = "in"
                                FadeTo(frame, 1, s.mouseoverSpeed or 0.15)
                            end
                        end)
                        frame:HookScript("OnLeave", function()
                            state.isHovered = false
                            C_Timer_After(0.1, function()
                                if state.isHovered then return end
                                if state.fadeDir ~= "out" then
                                    state.fadeDir = "out"
                                    FadeTo(frame, 0, s.mouseoverSpeed or 0.15)
                                end
                            end)
                        end)
                        frame:SetAlpha(0)
                    end
                end
            end
        end
    end

    -- Apply saved positions
    local positions = EAB.db.profile.barPositions
    if positions then
        for _, info in ipairs(EXTRA_BARS) do
            if info.isDataBar then
                local pos = positions[info.key]
                local frame = dataBarFrames[info.key]
                if pos and frame and pos.point then
                    frame:ClearAllPoints()
                    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
                end
            end
        end
    end

    -- Register data bars with unlock mode (frames exist now)
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        RegisterDataBarsWithUnlockMode()
    else
        C_Timer_After(1, function()
            if EllesmereUI and EllesmereUI.RegisterUnlockElements then
                RegisterDataBarsWithUnlockMode()
            end
        end)
    end

    -- Combat show/hide for data bars (can't use RegisterAttributeDriver on non-secure frames)
    local combatFrame = CreateFrame("Frame")
    combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatFrame:SetScript("OnEvent", function(_, event)
        local inCombat = (event == "PLAYER_REGEN_DISABLED")
        for _, info in ipairs(EXTRA_BARS) do
            if info.isDataBar then
                local frame = dataBarFrames[info.key]
                local s = EAB.db.profile.bars[info.key]
                if frame and s and not s.alwaysHidden then
                    if s.combatShowEnabled then
                        if inCombat then frame:Show() else frame:Hide() end
                    elseif s.combatHideEnabled then
                        if inCombat then frame:Hide() else frame:Show() end
                    end
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Blizzard Movable Frames (Extra Action Button, Encounter Bar)
--  Creates non-secure holder frames, reparents Blizzard frames into them,
--  and disables Blizzard's layout management so we can reposition freely.
--  Overlay sizes are hardcoded (don't affect actual Blizzard frame rendering).
-------------------------------------------------------------------------------
local _blizzMovablePendingOOC = {} -- deferred reparents for when combat ends

-- Silence a frame's layout participation and mouse interaction permanently.
-- Does NOT nil OnShow/OnHide -- those drive child frame visibility.
-- Only kills the OnUpdate repositioning loop and layout system membership.
local function DisableLayoutFrame(f)
    if not f then return end
    f.ignoreInLayout = true
    f.ignoreFramePositionManager = true
    f.IsLayoutFrame = nil
    if f.SetIsLayoutFrame then pcall(f.SetIsLayoutFrame, f, false) end
    f:SetScript("OnUpdate", nil)
    f.OnUpdate = nil
    f:EnableMouse(false)
end

local function SetupBlizzardMovableFrame(barKey)
    local holder = CreateFrame("Frame", "EllesmereEAB_" .. barKey, UIParent)
    holder:SetClampedToScreen(true)
    holder:EnableMouse(false)
    blizzMovableHolders[barKey] = holder

    local ov = BLIZZ_MOVABLE_OVERLAY[barKey]
    holder:SetSize(ov and ov.w or 50, ov and ov.h or 50)

    -- Identify which Blizzard frames to manage for this bar key.
    -- extraFrames = all frames that get reparented into the holder.
    local primaryFrame   -- the frame we read position from before reparenting
    local extraFrames = {}

    if barKey == "ExtraActionButton" then
        -- ExtraAbilityContainer is the layout container Blizzard's Edit Mode
        -- positions. It parents ExtraActionBarFrame and ZoneAbilityFrame.
        -- We take ownership of the whole container.
        if ExtraAbilityContainer then
            primaryFrame = ExtraAbilityContainer
            extraFrames[#extraFrames + 1] = ExtraAbilityContainer
        end
        -- ExtraActionBarFrame mouse is disabled in the container setup below.
    elseif barKey == "EncounterBar" then
        -- PlayerPowerBarAlt is the classic encounter power bar.
        -- UIWidgetPowerBarContainerFrame is used by newer mechanics.
        if PlayerPowerBarAlt then
            primaryFrame = PlayerPowerBarAlt
            extraFrames[#extraFrames + 1] = PlayerPowerBarAlt
        end
        if UIWidgetPowerBarContainerFrame then
            if not primaryFrame then primaryFrame = UIWidgetPowerBarContainerFrame end
            extraFrames[#extraFrames + 1] = UIWidgetPowerBarContainerFrame
        end
    end

    if #extraFrames == 0 then
        holder:Hide()
        return
    end

    -- Restore saved position BEFORE reparenting so we can still read the
    -- original Blizzard-placed position if no save exists yet.
    local pos = EAB.db.profile.barPositions[barKey]
    if pos and pos.point then
        holder:ClearAllPoints()
        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        -- Try to capture Blizzard's current Edit Mode position immediately.
        -- If the frame has no valid bounds yet, defer via OnUpdate.
        local src = primaryFrame
        local function TryCapturePosition(self)
            local bL, bT = src:GetLeft(), src:GetTop()
            local bR, bB = src:GetRight(), src:GetBottom()
            if bL and bT and bR and bB and (bR - bL) > 1 then
                local bS = src:GetEffectiveScale()
                local uS = UIParent:GetEffectiveScale()
                local cx = (bL + bR) * 0.5 * bS / uS
                local cy = (bT + bB) * 0.5 * bS / uS - UIParent:GetHeight()
                EAB.db.profile.barPositions[barKey] = { point = "CENTER", relPoint = "TOPLEFT", x = cx, y = cy }
                holder:ClearAllPoints()
                holder:SetPoint("CENTER", UIParent, "TOPLEFT", cx, cy)
                if self then self:SetScript("OnUpdate", nil) end
                return true
            end
            return false
        end
        if not TryCapturePosition(nil) then
            holder:ClearAllPoints()
            holder:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
            local attempts = 0
            local captureFrame = CreateFrame("Frame")
            captureFrame:SetScript("OnUpdate", function(self)
                attempts = attempts + 1
                if TryCapturePosition(self) or attempts > 300 then
                    self:SetScript("OnUpdate", nil)
                end
            end)
        end
    end

    -- Reparent all managed frames into the holder, centered.
    -- Safe to call multiple times; guards against combat lockdown.
    local function ReparentIntoHolder()
        if InCombatLockdown() then
            _blizzMovablePendingOOC[barKey] = true
            return
        end
        for _, f in ipairs(extraFrames) do
            f.ignoreInLayout = true
            f.ignoreFramePositionManager = true
            if f.SetIsLayoutFrame then pcall(f.SetIsLayoutFrame, f, false) end
            f:SetParent(holder)
            f:ClearAllPoints()
            f:SetPoint("CENTER", holder, "CENTER", 0, 0)
        end
    end

    -- Extra Action Button: disable the container's layout-driven repositioning
    -- and reparent it into our holder. Keep OnShow/OnHide nil'd on the
    -- container so Blizzard's layout code cannot fire, but leave the child
    -- frames (ExtraActionBarFrame, ZoneAbilityFrame) untouched so they show
    -- and hide normally.
    if barKey == "ExtraActionButton" and ExtraAbilityContainer then
        -- Disable mouse on ExtraActionBarFrame so it cannot absorb clicks
        -- when no extra action bar is active.
        if ExtraActionBarFrame and not InCombatLockdown() and ExtraActionBarFrame:IsMouseEnabled() then
            ExtraActionBarFrame:EnableMouse(false)
        end

        -- Nil container OnShow/OnHide so Blizzard's layout code
        -- (UpdateManagedFramePositions) cannot fire when the container shows.
        ExtraAbilityContainer:SetScript("OnShow", nil)
        ExtraAbilityContainer:SetScript("OnHide", nil)

        -- Hook AddFrame so newly added ability buttons stay clickable.
        if ExtraAbilityContainer.AddFrame then
            hooksecurefunc(ExtraAbilityContainer, "AddFrame", function(_, frame)
                if frame and frame.EnableMouse then
                    frame:EnableMouse(true)
                end
            end)
        end

        -- Reposition the container into our holder.
        local function RepositionExtraContainer()
            if InCombatLockdown() then return end
            local container = ExtraAbilityContainer
            container:SetParent(holder)
            if container.ClearAllPointsBase then
                container:ClearAllPointsBase()
                container:SetPointBase("CENTER", holder)
            else
                container:ClearAllPoints()
                container:SetPoint("CENTER", holder)
            end
        end
        RepositionExtraContainer()

        -- Re-reparent when Edit Mode tries to reposition the container.
        if ExtraAbilityContainer.ApplySystemAnchor then
            hooksecurefunc(ExtraAbilityContainer, "ApplySystemAnchor", function()
                local _, relFrame = ExtraAbilityContainer:GetPoint()
                if relFrame ~= holder then
                    RepositionExtraContainer()
                end
                if UIParentBottomManagedFrameContainer then
                    UIParentBottomManagedFrameContainer.showingFrames[ExtraAbilityContainer] = nil
                end
            end)
        end

        -- Re-reparent after Blizzard's OnShow repositions the container.
        -- (We nil'd the script, but hooksecurefunc still fires on Show.)
        hooksecurefunc(ExtraAbilityContainer, "Show", function()
            if ExtraAbilityContainer:GetParent() ~= holder then
                RepositionExtraContainer()
            end
        end)
    end

    -- Encounter Bar: reparent into holder, mark as user-placed so Blizzard's
    -- position manager leaves it alone, and hook setup functions to re-reparent.
    if barKey == "EncounterBar" then
        local ppb = PlayerPowerBarAlt
        if ppb then
            ppb:SetMovable(true)
            ppb:SetUserPlaced(true)
            ppb:SetDontSavePosition(true)

            ppb:ClearAllPoints()
            ppb:SetParent(holder)
            ppb:SetPoint("CENTER", holder)

            if type(ppb.SetupPlayerPowerBarPosition) == "function" then
                hooksecurefunc(ppb, "SetupPlayerPowerBarPosition", function(bar)
                    if bar:GetParent() ~= holder then
                        ReparentIntoHolder()
                    end
                end)
            end

            if type(UnitPowerBarAlt_SetUp) == "function" then
                hooksecurefunc("UnitPowerBarAlt_SetUp", function(bar)
                    if bar.isPlayerBar and bar:GetParent() ~= holder then
                        ReparentIntoHolder()
                    end
                end)
            end

            ppb:HookScript("OnSizeChanged", function(self)
                local w, h = self:GetSize()
                if w > 1 and h > 1 then holder:SetSize(w, h) end
            end)
        end

        local uwb = UIWidgetPowerBarContainerFrame
        if uwb then
            DisableLayoutFrame(uwb)
            uwb:HookScript("OnSizeChanged", function(self)
                local w, h = self:GetSize()
                if w > 1 and h > 1 then
                    local hw, hh = holder:GetSize()
                    holder:SetSize(max(hw, w), max(hh, h))
                end
            end)
        end
    end

    -- Initial reparent.
    ReparentIntoHolder()

    -- Hook SetParent on every managed frame so we re-reparent immediately if
    -- Blizzard or another addon steals the frame back.
    for _, f in ipairs(extraFrames) do
        hooksecurefunc(f, "SetParent", function(self, newParent)
            if newParent ~= holder then
                ReparentIntoHolder()
            end
        end)
    end

    -- Apply visibility settings
    local s = EAB.db.profile.bars[barKey]
    if s and s.alwaysHidden then holder:Hide() end

    return holder
end

-- Deferred reparent handler: fires when combat ends.
local _blizzMovableCombatFrame = CreateFrame("Frame")
_blizzMovableCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
_blizzMovableCombatFrame:SetScript("OnEvent", function()
    if InCombatLockdown() then return end
    for barKey in pairs(_blizzMovablePendingOOC) do
        local holder = blizzMovableHolders[barKey] or extraBarHolders[barKey]
        if not holder then
            for _, info in ipairs(EXTRA_BARS) do
                if info.key == barKey then
                    holder = extraBarHolders[barKey]
                    break
                end
            end
        end
        if barKey == "ExtraActionButton" and holder and ExtraAbilityContainer then
            ExtraAbilityContainer.ignoreInLayout = true
            ExtraAbilityContainer.ignoreFramePositionManager = true
            if ExtraAbilityContainer.SetIsLayoutFrame then
                pcall(ExtraAbilityContainer.SetIsLayoutFrame, ExtraAbilityContainer, false)
            end
            ExtraAbilityContainer:SetParent(holder)
            ExtraAbilityContainer:ClearAllPoints()
            ExtraAbilityContainer:SetPoint("CENTER", holder, "CENTER", 0, 0)
        elseif barKey == "EncounterBar" and holder then
            for _, f in ipairs({ PlayerPowerBarAlt, UIWidgetPowerBarContainerFrame }) do
                if f then
                    f.ignoreInLayout = true
                    f.ignoreFramePositionManager = true
                    if f.SetIsLayoutFrame then pcall(f.SetIsLayoutFrame, f, false) end
                    f:SetParent(holder)
                    f:ClearAllPoints()
                    f:SetPoint("CENTER", holder, "CENTER", 0, 0)
                end
            end
        elseif holder then
            for _, info in ipairs(EXTRA_BARS) do
                if info.key == barKey and info.frameName then
                    local f = _G[info.frameName]
                    if f then
                        f.ignoreInLayout = true
                        if f.SetIsLayoutFrame then pcall(f.SetIsLayoutFrame, f, false) end
                        f:SetParent(holder)
                        f:ClearAllPoints()
                        f:SetPoint("CENTER", holder, "CENTER", 0, 0)
                    end
                    break
                end
            end
        end
    end
    wipe(_blizzMovablePendingOOC)

    -- Re-disable mouse on ExtraActionBarFrame after combat ends.
    -- Blizzard's secure code re-enables mouse on protected frames during combat.
    if ExtraActionBarFrame and ExtraActionBarFrame:IsMouseEnabled() then
        ExtraActionBarFrame:EnableMouse(false)
    end
end)

-- Revert UserPlaced on logout so Blizzard doesn't persist our stale position.
local _blizzMovableLogoutFrame = CreateFrame("Frame")
_blizzMovableLogoutFrame:RegisterEvent("PLAYER_LOGOUT")
_blizzMovableLogoutFrame:SetScript("OnEvent", function()
    if PlayerPowerBarAlt then
        PlayerPowerBarAlt:SetUserPlaced(false)
    end
end)

local function SetupBlizzardMovableFrames()
    for _, info in ipairs(EXTRA_BARS) do
        if info.isBlizzardMovable then
            SetupBlizzardMovableFrame(info.key)
        end
    end
end

-------------------------------------------------------------------------------
--  Extra Bar Holders (MicroBar, BagBar) positioning via holder frames
--  Reparents Blizzard frames into holder frames so unlock mode can position them.
-------------------------------------------------------------------------------
AttachExtraBarHoverHooks = function(info)
    -- Idempotent: only attach once per bar key
    if hoverStates[info.key] then return end

    local blizzFrame = _G[info.frameName]
    if not blizzFrame then return end
    local holder = extraBarHolders[info.key]

    -- Fade the Blizzard frame directly rather than the holder.
    -- The holder is for positioning only; fading it can be overridden by
    -- Blizzard's own layout code calling SetAlpha on the child frame.
    local fadeTarget = blizzFrame

    local state = { isHovered = false, fadeDir = nil, frame = fadeTarget }
    hoverStates[info.key] = state

    local function OnEnter()
        state.isHovered = true
        local bs = EAB.db.profile.bars[info.key]
        if bs and bs.mouseoverEnabled and state.fadeDir ~= "in" then
            state.fadeDir = "in"
            StopFade(fadeTarget)
            FadeTo(fadeTarget, 1, bs.mouseoverSpeed or 0.15)
        end
    end
    local function OnLeave()
        state.isHovered = false
        C_Timer_After(0.1, function()
            if state.isHovered then return end
            local bs = EAB.db.profile.bars[info.key]
            if bs and bs.mouseoverEnabled and state.fadeDir ~= "out" then
                state.fadeDir = "out"
                FadeTo(fadeTarget, 0, bs.mouseoverSpeed or 0.15)
            end
        end)
    end

    blizzFrame:HookScript("OnEnter", OnEnter)
    blizzFrame:HookScript("OnLeave", OnLeave)
    local hoverFrame = info.hoverFrame and _G[info.hoverFrame]
    if hoverFrame and hoverFrame ~= blizzFrame then
        hoverFrame:HookScript("OnEnter", OnEnter)
        hoverFrame:HookScript("OnLeave", OnLeave)
    end

    -- Recurse into child frames to hook all interactive buttons, including
    -- those nested inside sub-containers (e.g. MicroMenu inside MicroMenuContainer).
    local function HookChildren(parent, depth)
        depth = depth or 0
        if depth > 3 then return end
        for _, child in ipairs({ parent:GetChildren() }) do
            if child:IsObjectType("Button") or child:IsObjectType("CheckButton") or child:IsObjectType("ItemButton") then
                child:HookScript("OnEnter", OnEnter)
                child:HookScript("OnLeave", OnLeave)
            else
                -- Recurse into non-button containers
                HookChildren(child, depth + 1)
            end
        end
    end
    HookChildren(blizzFrame)
    if hoverFrame and hoverFrame ~= blizzFrame then
        HookChildren(hoverFrame)
    end
end

local function SetupExtraBarHolder(barKey, frameName)
    local blizzFrame = _G[frameName]
    if not blizzFrame then return end

    local holder = CreateFrame("Frame", "EllesmereEAB_" .. barKey, UIParent)
    holder:SetClampedToScreen(true)
    extraBarHolders[barKey] = holder

    -- Size the holder to match the Blizzard frame
    local w, h = blizzFrame:GetWidth(), blizzFrame:GetHeight()
    if w and w > 1 and h and h > 1 then
        holder:SetSize(w, h)
    else
        holder:SetSize(200, 40)
    end

    -- Restore saved position or capture current Blizzard position
    local pos = EAB.db.profile.barPositions[barKey]
    if pos and pos.point then
        holder:ClearAllPoints()
        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
    else
        local bL, bT = blizzFrame:GetLeft(), blizzFrame:GetTop()
        local bR, bB = blizzFrame:GetRight(), blizzFrame:GetBottom()
        if bL and bT and bR and bB and (bR - bL) > 1 then
            local bS = blizzFrame:GetEffectiveScale()
            local uiS = UIParent:GetEffectiveScale()
            local cx = (bL + bR) * 0.5 * bS / uiS
            local cy = (bT + bB) * 0.5 * bS / uiS - UIParent:GetHeight()
            EAB.db.profile.barPositions[barKey] = {
                point = "CENTER", relPoint = "TOPLEFT", x = cx, y = cy,
            }
            holder:ClearAllPoints()
            holder:SetPoint("CENTER", UIParent, "TOPLEFT", cx, cy)
        else
            -- Defer capture
            holder:ClearAllPoints()
            holder:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
            local attempts = 0
            local captureFrame = CreateFrame("Frame")
            captureFrame:SetScript("OnUpdate", function(self)
                attempts = attempts + 1
                local cL, cT = blizzFrame:GetLeft(), blizzFrame:GetTop()
                local cR, cB = blizzFrame:GetRight(), blizzFrame:GetBottom()
                if cL and cT and cR and cB and (cR - cL) > 1 then
                    local cS = blizzFrame:GetEffectiveScale()
                    local uS = UIParent:GetEffectiveScale()
                    local ccx = (cL + cR) * 0.5 * cS / uS
                    local ccy = (cT + cB) * 0.5 * cS / uS - UIParent:GetHeight()
                    EAB.db.profile.barPositions[barKey] = {
                        point = "CENTER", relPoint = "TOPLEFT", x = ccx, y = ccy,
                    }
                    holder:ClearAllPoints()
                    holder:SetPoint("CENTER", UIParent, "TOPLEFT", ccx, ccy)
                    self:SetScript("OnUpdate", nil)
                elseif attempts > 300 then
                    self:SetScript("OnUpdate", nil)
                end
            end)
        end
    end

    -- Reparent Blizzard frame into holder
    local _recentering = false
    local function ReparentIntoHolder()
        if InCombatLockdown() then
            _blizzMovablePendingOOC[barKey] = true
            return
        end
        _recentering = true
        blizzFrame:SetParent(holder)
        blizzFrame:ClearAllPoints()
        blizzFrame:SetPoint("CENTER", holder, "CENTER", 0, 0)
        _recentering = false
    end

    -- Prevent Blizzard layout system from repositioning
    blizzFrame.ignoreInLayout = true
    if blizzFrame.SetIsLayoutFrame then
        blizzFrame:SetIsLayoutFrame(false)
    end
    blizzFrame.IsLayoutFrame = nil

    ReparentIntoHolder()

    -- Re-reparent if Blizzard steals the frame back
    hooksecurefunc(blizzFrame, "SetParent", function(self, newParent)
        if newParent ~= holder then
            C_Timer_After(0, function()
                if self:GetParent() ~= holder then
                    ReparentIntoHolder()
                end
            end)
        end
    end)

    -- Keep centered in holder if Blizzard repositions
    hooksecurefunc(blizzFrame, "SetPoint", function(self)
        if _recentering or self:GetParent() ~= holder then return end
        C_Timer_After(0, function()
            if _recentering or self:GetParent() ~= holder or InCombatLockdown() then return end
            local pt = self:GetPoint(1)
            if pt ~= "CENTER" then
                _recentering = true
                self:ClearAllPoints()
                self:SetPoint("CENTER", holder, "CENTER", 0, 0)
                _recentering = false
            end
        end)
    end)

    return holder
end

local function SetupExtraBarHolders()
    for _, info in ipairs(EXTRA_BARS) do
        if not info.isDataBar and not info.isBlizzardMovable and info.frameName then
            SetupExtraBarHolder(info.key, info.frameName)
        end
    end
end

local function RegisterExtraBarsWithUnlockMode()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local elements = {}
    local orderBase = 350
    for idx, info in ipairs(EXTRA_BARS) do
        if not info.isDataBar and not info.isBlizzardMovable and info.frameName then
            local bk = info.key
            elements[#elements + 1] = {
                key   = bk,
                label = info.label,
                group = "Action Bars",
                order = orderBase + idx,
                isHidden = function()
                    local s = EAB.db.profile.bars[bk]
                    return s and s.alwaysHidden
                end,
                getFrame = function()
                    return extraBarHolders[bk]
                end,
                getSize = function()
                    local holder = extraBarHolders[bk]
                    if holder then return holder:GetWidth(), holder:GetHeight() end
                    return 200, 40
                end,
                getScale = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    return pos and pos.scale or 1.0
                end,
                loadPosition = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    if not pos then return nil end
                    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y, scale = pos.scale }
                end,
                savePosition = function(_, point, relPoint, x, y, scale)
                    if point and x and y then
                        EAB.db.profile.barPositions[bk] = {
                            point = point, relPoint = relPoint or point, x = x, y = y,
                            scale = scale,
                        }
                    end
                    local holder = extraBarHolders[bk]
                    if holder and point and x and y then
                        holder:ClearAllPoints()
                        holder:SetPoint(point, UIParent, relPoint or point, x, y)
                        if scale then holder:SetScale(scale) end
                    end
                end,
                clearPosition = function()
                    EAB.db.profile.barPositions[bk] = nil
                end,
                applyPosition = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    local holder = extraBarHolders[bk]
                    if not holder then return end
                    holder:ClearAllPoints()
                    if pos and pos.point then
                        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
                        if pos.scale then holder:SetScale(pos.scale) end
                    else
                        holder:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
                    end
                end,
            }
        end
    end
    EllesmereUI:RegisterUnlockElements(elements)
end

-------------------------------------------------------------------------------
--  Extra Bars (MicroBar, BagBar) visibility-only management
--  These use Blizzard's existing frames, we just manage visibility.
-------------------------------------------------------------------------------
local function SetupExtraBars()
    if not EAB.db then return end

    -- Setup Blizzard movable frames (Extra Action Button, Encounter Bar)
    SetupBlizzardMovableFrames()

    -- Setup extra bar holders (MicroBar, BagBar) for positioning
    SetupExtraBarHolders()

    for _, info in ipairs(EXTRA_BARS) do
        if not info.isDataBar and not info.isBlizzardMovable then
            local blizzFrame = _G[info.frameName]
            if blizzFrame then
                local s = EAB.db.profile.bars[info.key]
                if s then
                    local holder = extraBarHolders[info.key]
                    if s.alwaysHidden then
                        blizzFrame:Hide()
                        if holder then holder:Hide() end
                    end
                    AttachExtraBarHoverHooks(info)
                end
            end
        end  -- not isDataBar/isBlizzardMovable
    end

    -- Register extra bars with unlock mode
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        RegisterExtraBarsWithUnlockMode()
    else
        C_Timer_After(1, function()
            if EllesmereUI and EllesmereUI.RegisterUnlockElements then
                RegisterExtraBarsWithUnlockMode()
            end
        end)
    end

    -- Setup data bars (XP, Rep)
    SetupDataBars()

    -- Apply correct initial alpha now that holders exist.
    -- RefreshMouseover ran at OnEnable before holders were created, so
    -- bars with mouseoverEnabled never got their alpha set to 0.
    EAB:RefreshMouseover()
end

-- Setup extra bars after a short delay to ensure frames exist
local extraBarFrame = CreateFrame("Frame")
extraBarFrame:RegisterEvent("PLAYER_LOGIN")
extraBarFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer_After(0.5, SetupExtraBars)
end)
