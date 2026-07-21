-------------------------------------------------------------------------------
--  EllesmereUIActionBars.lua  Custom Action Bars
--
--  Creates its own secure action bar frames AND buttons. All action bar
--  buttons are our own EABButton frames (ActionBarButtonTemplate), eliminating
--  the taint surface from reusing Blizzard's protected buttons.
--  Stance and Pet bars still reuse Blizzard buttons (own secure handling).
--
--  Keybind dispatch: SetOverrideBindingClick for all bars.
--  Paging: RegisterStateDriver + _childupdate-eab-page with explicit action attrs.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EAB = EllesmereUI.Lite.NewAddon(ADDON_NAME)
ns.EAB = EAB

local PP = EllesmereUI.PP

-- Cold-path helper table for module-level behavior that benefits from a
-- shared dispatch surface without adding more direct top-level helpers.
local EAB_VTABLE = {
    ExtraBars = {},
    CooldownFonts = {},
    Hover = {},
    MainBarPageSync = {},
}
ns.EAB_VTABLE = EAB_VTABLE

EAB.VisibilityCompat = EAB.VisibilityCompat or {}


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

-- External weak-keyed lookup for per-frame state (avoids writing custom
-- properties onto Blizzard-owned frame tables, which causes taint).
-- Stored on ns to avoid consuming file-scope local slots (200 cap).
ns._eabFD = setmetatable({}, { __mode = "k" })
function ns.EFD(frame)
    local d = ns._eabFD[frame]
    if not d then d = {}; ns._eabFD[frame] = d end
    return d
end

-- Local alias for hot-path EFD access (replaces removed _eabHookedBars)
local EFD = ns.EFD
local RegisterStateDriver = RegisterStateDriver
local RegisterAttributeDriver = RegisterAttributeDriver
local GetBindingKey = GetBindingKey
local NUM_ACTIONBAR_BUTTONS = NUM_ACTIONBAR_BUTTONS or 12

-------------------------------------------------------------------------------
--  Bar configuration
-------------------------------------------------------------------------------
local BAR_CONFIG = {
    -- nativeMainBar: MainBar buttons keep their native IDs (1-12) and derive
    -- action via CalculateAction path 1. The bar frame's _onstate-page handler
    -- sets actionpage from the restricted env for form/vehicle/override paging.
    -- Keyboard input flows through Blizzard's native
    -- ActionButtonDown/Up → GetActionButtonForID → _G["ActionButton"..id].
    { key = "MainBar",   label = "Action Bar 1 (Main)", barID = 1,  count = 12, blizzBtnPrefix = "ActionButton",              blizzFrame = "MainMenuBar", nativeMainBar = true },
    -- nativeActionPage: the Blizzard actionpage for this bar's slot range.
    -- Buttons keep their native IDs and derive the action via
    --   CalculateAction path 1: action = ID + (page - 1) * 12.
    -- Keyboard input flows through Blizzard's native MultiActionButtonDown/Up
    -- so UseAction receives isKeyPress=true (required for press-and-hold casting).
    { key = "Bar2",      label = "Action Bar 2",        barID = 2,  count = 12, blizzBtnPrefix = "MultiBarBottomLeftButton",   blizzFrame = "MultiBarBottomLeft",  nativeActionPage = 6 },
    { key = "Bar3",      label = "Action Bar 3",        barID = 3,  count = 12, blizzBtnPrefix = "MultiBarBottomRightButton",  blizzFrame = "MultiBarBottomRight", nativeActionPage = 5 },
    { key = "Bar4",      label = "Action Bar 4",        barID = 4,  count = 12, blizzBtnPrefix = "MultiBarRightButton",        blizzFrame = "MultiBarRight",       nativeActionPage = 3 },
    { key = "Bar5",      label = "Action Bar 5",        barID = 5,  count = 12, blizzBtnPrefix = "MultiBarLeftButton",         blizzFrame = "MultiBarLeft",        nativeActionPage = 4 },
    { key = "Bar6",      label = "Action Bar 6",        barID = 6,  count = 12, blizzBtnPrefix = "MultiBar5Button",          blizzFrame = "MultiBar5",           nativeActionPage = 13 },
    { key = "Bar7",      label = "Action Bar 7",        barID = 7,  count = 12, blizzBtnPrefix = "MultiBar6Button",          blizzFrame = "MultiBar6",           nativeActionPage = 14 },
    { key = "Bar8",      label = "Action Bar 8",        barID = 8,  count = 12, blizzBtnPrefix = "MultiBar7Button",          blizzFrame = "MultiBar7",           nativeActionPage = 15 },
    -- Bar9 / Bar10: extra bars with NO native Blizzard frame. They use our own
    -- EABButton<slot> buttons and page identically to Bars 2-8 via the
    -- explicit-action + _childupdate-eab-page system. Bar9 maps to action page 2
    -- (slots 13-24) so converts see those spells appear (already
    -- in the per-character action slots, no re-placing) once Bar9 is enabled.
    -- Bar10 maps to action page 10 (slots 109-120). The only native-specific
    -- difference is keybinds: these pages have no Blizzard binding commands, so
    -- their keys route through SetOverrideBindingClick using the EUI_BAR9/10_BUTTON
    -- commands defined in Bindings.xml. customPage = the action page these slots
    -- live on.
    { key = "Bar9",      label = "Action Bar 9",        barID = 0,  count = 12, customPage = 2 },
    { key = "Bar10",     label = "Action Bar 10",       barID = 0,  count = 12, customPage = 10 },
    { key = "StanceBar", label = "Stance Bar",          barID = 0,  count = 10, blizzBtnPrefix = "StanceButton",               blizzFrame = "StanceBar", isStance = true },
    { key = "PetBar",    label = "Pet Bar",             barID = 0,  count = 10, blizzBtnPrefix = "PetActionButton",            blizzFrame = "PetActionBar", isPetBar = true },
}

-- Aliases for the options file (which references these field names)
for _, info in ipairs(BAR_CONFIG) do
    info.buttonPrefix = info.blizzBtnPrefix
    info.frameName    = info.blizzFrame
    info.fallbackFrame = nil
end

local EXTRA_BARS = {
    { key = "MicroBar", label = "Micro Menu Bar", frameName = "MicroMenuContainer", hoverFrame = "MicroMenu", visibilityOnly = true, blizzOwnedVisibility = true },
    { key = "BagBar",   label = "Bag Bar",        frameName = "BagsBar", visibilityOnly = true, blizzOwnedVisibility = true },
    { key = "QueueStatus", label = "Queue Status", frameName = "QueueStatusButton", visibilityOnly = true, blizzOwnedVisibility = true, noManagedVisibility = true },
    { key = "XPBar",    label = "XP Bar",         visibilityOnly = true, isDataBar = true },
    { key = "RepBar",   label = "Reputation Bar",  visibilityOnly = true, isDataBar = true },
    { key = "FavorBar", label = "House Favor Bar", visibilityOnly = true, isDataBar = true },
    { key = "ExtraActionButton", label = "Extra Action Button", visibilityOnly = true, isBlizzardMovable = true },
    { key = "EncounterBar",      label = "Encounter Bar",         visibilityOnly = true, isBlizzardMovable = true },
}

local ALL_BARS = {}
for _, info in ipairs(BAR_CONFIG) do ALL_BARS[#ALL_BARS + 1] = info end
for _, info in ipairs(EXTRA_BARS) do ALL_BARS[#ALL_BARS + 1] = info end

local BAR_LOOKUP = {}
for _, info in ipairs(BAR_CONFIG) do BAR_LOOKUP[info.key] = info end
for _, info in ipairs(EXTRA_BARS) do BAR_LOOKUP[info.key] = info end

-- Expose AB bar keys immediately so the unlock mode's ApplyAnchorPosition can
-- gate edge logic to CDM/AB without waiting for deferred RegisterWithUnlockMode.
if not EllesmereUI._abBarKeys then EllesmereUI._abBarKeys = {} end
for _, info in ipairs(BAR_CONFIG) do EllesmereUI._abBarKeys[info.key] = true end

local BAR_DROPDOWN_VALUES = {}
local BAR_DROPDOWN_ORDER = {}
do
    local _DROPDOWN_EXCLUDE = { ExtraActionButton = true, EncounterBar = true, QueueStatus = true }
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

function EAB.VisibilityCompat.ApplyMode(settings, mode)
    if not settings then return "always" end

    mode = mode or "always"
    settings.barVisibility = mode
    settings.alwaysHidden = (mode == "never")

    local wasMouseover = settings.mouseoverEnabled
    settings.mouseoverEnabled = (mode == "mouseover")
    if mode == "mouseover" then
        if not settings._savedBarAlpha then
            settings._savedBarAlpha = settings.mouseoverAlpha or 1
        end
        settings.mouseoverAlpha = 0
    elseif wasMouseover and settings._savedBarAlpha then
        settings.mouseoverAlpha = settings._savedBarAlpha
        settings._savedBarAlpha = nil
    end

    settings.combatHideEnabled = (mode == "out_of_combat")
    settings.combatShowEnabled = (mode == "in_combat")
    return mode
end

function EAB.VisibilityCompat.Normalize(settings)
    if not settings then return "always" end
    if settings.barVisibility then
        return EAB.VisibilityCompat.ApplyMode(settings, settings.barVisibility)
    end
    if settings.alwaysHidden then
        return EAB.VisibilityCompat.ApplyMode(settings, "never")
    end
    if settings.mouseoverEnabled then
        return EAB.VisibilityCompat.ApplyMode(settings, "mouseover")
    end
    if settings.combatShowEnabled then
        return EAB.VisibilityCompat.ApplyMode(settings, "in_combat")
    end
    if settings.combatHideEnabled then
        return EAB.VisibilityCompat.ApplyMode(settings, "out_of_combat")
    end
    return EAB.VisibilityCompat.ApplyMode(settings, "always")
end

function EAB.VisibilityCompat.Copy(dst, src, dstNoGroupModes)
    if not dst or not src then return end

    local mode = EAB.VisibilityCompat.Normalize(src)
    EAB.VisibilityCompat.ApplyMode(dst, mode)

    if mode == "mouseover" then
        dst._savedBarAlpha = src._savedBarAlpha or src.mouseoverAlpha or 1
        dst.mouseoverAlpha = 0
    else
        dst.mouseoverAlpha = src.mouseoverAlpha
        dst._savedBarAlpha = nil
    end

    -- Per-bar Show During Drag travels with the visibility copy (inert unless
    -- the target's mode is Never).
    dst.dragShow = src.dragShow

    -- Multi-select set travels with the copy (after ApplyMode, so the
    -- scalar/set pair stays consistent). Group-axis items are stripped for
    -- targets that cannot express them (Pet Bar); the stripped selection
    -- re-normalizes through the shared setter, which routes the scalar back
    -- through ApplyMode to keep the legacy booleans synced.
    if EllesmereUI and EllesmereUI.VisCopySelection then
        EllesmereUI.VisCopySelection(dst, src, "barVisibility",
            dstNoGroupModes and EllesmereUI.VIS_CAPS_NO_GROUP or nil,
            EAB.VisibilityCompat.ApplyMode)
    else
        dst.visibilityModes = nil
    end
end

-------------------------------------------------------------------------------
--  Media paths
-------------------------------------------------------------------------------
local MEDIA_DIR = "Interface\\AddOns\\EllesmereUIActionBars\\Media\\"
local FONT_PATH = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("actionBars"))
    or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local function GetEABOutline()
    return (EllesmereUI and EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("actionBars")) or "OUTLINE, SLUG"
end
local function GetEABUseShadow()
    return not EllesmereUI or not EllesmereUI.GetFontUseShadow or EllesmereUI.GetFontUseShadow("actionBars")
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
ns.SHAPE_ICON_EXPAND_OFFSETS = SHAPE_ICON_EXPAND_OFFSETS
ns.SHAPE_INSETS = SHAPE_INSETS

-- Per-shape edge scale so the circular edge path stays inside the mask.
local SHAPE_EDGE_SCALES = {
    circle = 0.75, csquare = 0.75, diamond = 0.70,
    hexagon = 0.65, portrait = 0.70, shield = 0.65, square = 0.75,
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

-- Per-addon border texture defaults (central registry)
do
    local ALL_SIZES = { "none", "thin", "normal", "heavy", "strong" }
    local function AllSizes(ox, oy, sx, sy)
        local t = {}
        for _, k in ipairs(ALL_SIZES) do t[k] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy } end
        return t
    end
    EllesmereUI.RegisterBorderDefaults("actionbars", {
        ["glow"] = {
            defaultSize = "normal",
            sizes = AllSizes(0, 0, 0, 0),
        },
        ["blizz"] = {
            defaultSize = "heavy",
            sizes = {
                none   = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                thin   = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
                normal = { offsetX = 3, offsetY = 2, shiftX = 0, shiftY = 0 },
                heavy  = { offsetX = 4, offsetY = 2, shiftX = 1, shiftY = 0 },
                strong = { offsetX = 4, offsetY = 2, shiftX = 2, shiftY = 0 },
            },
        },
        ["dialog"] = {
            defaultSize = "normal",
            sizes = AllSizes(4, 4, 0, 0),
        },
        ["sm:Blizzard Achievement Wood"] = {
            defaultSize = "thin",
            sizes = AllSizes(1, 1, 0, 0),
        },
    })
end

-------------------------------------------------------------------------------
--  Defaults
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        squareIcons = true,
        iconZoom = 5.5,
        selectedBar = "MainBar",
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
        showCastHighlight = true,
        -- Show the recharge countdown on charge spells while a charge is still
        -- banked (mirrors the "Show numbers for cooldowns" CVar onto the recharge
        -- timer). Off = Blizzard default (recharge number only at 0 charges).
        showChargeRechargeNumbers = true,
        desaturateOnCooldown = false,
        -- Alpha when on CD: 100 = disabled (zero cost). Below 100 dims the icon to
        -- that opacity while on a real cooldown, using the same detection as
        -- Desaturate on Cooldown.
        alphaWhenOnCD = 100,
        -- Cooldown swipe (radial sweep) colour + opacity. Defaults mirror the
        -- Blizzard look (black, 80%) so applying them is a no-op until customized.
        cdSwipeColor = { r = 0, g = 0, b = 0 },
        cdSwipeAlpha = 80,
        procGlowType = 1,
        procGlowColor = { r = 1, g = 0.776, b = 0.376 },
        procGlowUseClassColor = false,
        procGlowScale = 1.0,
        procGlowEnabled = false,
        useBlizzardStyle = false,
        showBlizzIconBg = false,
        blizzIconBgAlpha = 1,
        hideCastingAnimations = true,
        mouseoverShowAll = false,
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
        borderTexture = "solid",
        borderThickness = "thin",
        borderBehind = false,
        buttonPadding = 2,
        buttonWidth = 0,
        buttonHeight = 0,
        mouseoverEnabled = false,
        mouseoverAlpha = 1,
        combatShowEnabled = false,
        combatHideEnabled = false,
        housingHideEnabled = false,
        barVisibility = "always",
        dragShow = false,
        visHideHousing = false,
        visOnlyInstances = false,
        visHideMounted = false,
        visHideNoTarget = false,
        visHideNoEnemy = false,
        hideKeybind = false,
        keybindFontSize = 12,
        keybindFontColor = { r = 1, g = 1, b = 1 },
        hideMacroText = false,
        macroFontSize = 12,
        macroFontColor = { r = 1, g = 1, b = 1 },
        countFontSize = 12,
        countFontColor = { r = 1, g = 1, b = 1 },
        alwaysHidden = false,
        mouseoverSpeed = 0.15,
        clickThrough = false,
        overrideNumIcons = nil,
        overrideNumRows  = nil,
        growDirection    = "up",
        -- Legacy flag, superseded by iconOrder. iconOrder deliberately has
        -- no default: nil means "derive from reverseIconOrder" so profiles
        -- saved before it existed keep their exact layout.
        reverseIconOrder = false,
        alwaysShowButtons = true,
        showPagingArrows = false,
        pagingArrowsRight = false,
        paging = {},
        bgEnabled = false,
        bgColor = { r = 0, g = 0, b = 0, a = 0.5 },
        bgBorderColor = { r = 0, g = 0, b = 0, a = 1 },
        bgBorderTexture = "solid",
        bgBorderBehind = false,
        bgBorderSize = 1,
        bgBorderThickness = "none",
        bgMultiplierX = 1,
        bgMultiplierY = 1,
        bgExpandDirectionX = "right",
        bgExpandDirectionY = "up",
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
        macroOffsetX = 0,
        macroOffsetY = 0,
        countOffsetX = 0,
        countOffsetY = 0,
        cooldownFontSize = 12,
        cooldownTextXOffset = 0,
        cooldownTextYOffset = 0,
        cooldownTextColor = { r = 1, g = 1, b = 1 },
        disableTooltips = false,
        showRankIcon = false,
        orientation = "horizontal",
        numIcons = 12,
        numRows = 1,
        targetWidth = 0,
        targetHeight = 0,
    }
end

-- Bar9/Bar10 are optional extra bars -- default to the "Hidden" visibility mode
-- (barVisibility = "never" + alwaysHidden, exactly what the Visibility dropdown's
-- Hidden option sets) so they never show for users who don't use them. The user
-- switches Visibility to "Always" (or any mode) to surface them.
for _, k in ipairs({ "Bar9", "Bar10" }) do
    local b = defaults.profile.bars[k]
    if b then
        b.barVisibility = "never"
        b.alwaysHidden  = true
    end
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
-- House Favor bar ships opt-in: hidden until the user turns it on.
if defaults.profile.bars.FavorBar then
    defaults.profile.bars.FavorBar.alwaysHidden = true
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

-- Drag visibility state (file-scope so ApplyAll can reset strata on spec change)
local _dragState = { visible = false, strataCache = {} }

-- Grid show/hide state (show empty slots during spell drag)
local _gridState = { shown = false, visPending = false, spellsPending = false }
local _quickKeybindState = { open = false, closePending = false, art = {}, FinishClose = nil }
local EAB_UpdateQuickKeybindButtons -- forward-declared for early event hooks

-- Set of frames we own (bar frames, not Blizzard frames).
-- Blizzard-owned frames use the _extraFadeQueue path to avoid taint.
local _ownedFrames = {}

local function ShouldQuickKeybindSurfaceBar(s)
    if not _quickKeybindState.open or not s or s.enabled == false then
        return false
    end

    -- QuickKeybind should surface bars hidden by transient runtime rules,
    -- but explicit "Never" visibility remains authoritative.
    local vis = s.barVisibility or "always"
    return not s.alwaysHidden and vis ~= "never"
end

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
    -- Specific NUMPAD keys must be handled before the generic NUMPAD prefix,
    -- or the prefix replacement makes them unmatchable (N. showed as NDECIMAL).
    text = text:gsub("NUMPADDECIMAL", "N.")
    text = text:gsub("NUMPADPLUS", "N+")
    text = text:gsub("NUMPADMINUS", "N-")
    text = text:gsub("NUMPADMULTIPLY", "N*")
    text = text:gsub("NUMPADDIVIDE", "N/")
    text = text:gsub("NUMPAD", "N")
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

-- Force-paint a Blizzard-native button's cooldown swipe/text from its current
-- action state, instead of waiting on the next ACTIONBAR_UPDATE_COOLDOWN
-- broadcast. We kill the stock cooldown broadcasters at load, so buttons we
-- don't rebuild (OverrideActionBarButton1-6, ExtraActionButton1) otherwise show
-- no swipe/number for an ability already on cooldown the instant they appear,
-- until mouseover or combat forces a refresh. Reads the slot via
-- GetAttribute("action"), never btn.action (protected -- reading it during
-- combat taints). Clears when no active duration is resolvable so a stale swipe
-- from a prior state is never left behind.
local function ForceCooldownPaint(btn)
    if not btn then return end
    local cd = btn.cooldown
    local action = btn:GetAttribute("action")
    if cd and action and HasAction(action) and C_ActionBar and C_ActionBar.GetActionCooldown then
        local cdInfo = C_ActionBar.GetActionCooldown(action)
        local durObj = cdInfo and cdInfo.isActive and C_ActionBar.GetActionCooldownDuration
            and C_ActionBar.GetActionCooldownDuration(action)
        if durObj then
            cd:SetCooldownFromDurationObject(durObj)
        else
            cd:Clear()
        end
    end
end
ns.ForceCooldownPaint = ForceCooldownPaint

-- Stock bar frames to disable. Each entry carries flags for how to handle it:
--   retainEvents  = true  -> do NOT unregister events (needed for override state)
local STOCK_BAR_DISPOSAL = {
    { name = "MainActionBar",       retainEvents = true },
    { name = "MainMenuBar" },
    { name = "MultiBarBottomLeft" },
    { name = "MultiBarBottomRight" },
    { name = "MultiBarRight" },
    { name = "MultiBarLeft" },
    { name = "MultiBar5" },
    { name = "MultiBar6" },
    { name = "MultiBar7" },
    { name = "StanceBar" },
    { name = "PetActionBar" },
}

-------------------------------------------------------------------------------
--  Hidden Dump Frame
--  Off-screen dump frame. Reparenting stock frames here is safer than
--  calling :Hide() directly, which can trigger taint chains in protected
--  code paths. Full-size so reparented frames keep valid rect queries.
-------------------------------------------------------------------------------
local hiddenParent = CreateFrame("Frame", "EABHiddenParent", UIParent)
hiddenParent:SetAllPoints(UIParent)
hiddenParent:Hide()

-- Kill Blizzard's event broadcasters at file-load time, before any
-- ActionBarButtonTemplate buttons are created. Both frames dispatch events
-- to ALL registered buttons causing mass redraws. Our central dispatcher
-- handles all needed events with HasAction() filtering.
-- GCD swipes are driven by ACTIONBAR_UPDATE_COOLDOWN (central dispatcher).
-- Re-registered during vehicle/override so Blizzard's OverrideActionBar
-- buttons (which we don't replace) get their cooldown updates.
if ActionBarButtonEventsFrame then ActionBarButtonEventsFrame:UnregisterAllEvents() end
if ActionBarActionEventsFrame then ActionBarActionEventsFrame:UnregisterAllEvents() end
do
    local _abefEvents = {
        "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_STATE",
        "ACTIONBAR_UPDATE_USABLE", "ACTIONBAR_SLOT_CHANGED",
        -- Spell-typed extra-action buttons (some delve abilities) carry no
        -- action slot, so their cooldown fires SPELL_UPDATE_COOLDOWN, not
        -- ACTIONBAR_UPDATE_COOLDOWN. Needed so the broadcaster repaints them.
        "SPELL_UPDATE_COOLDOWN",
        "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD",
    }
    local _aaefEvents = {
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP",
        "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED",
        "UNIT_SPELLCAST_INTERRUPTED",
    }
    -- The native broadcaster is killed at load; re-enable it only while
    -- something that needs it is active. Two independent needs, ref-counted so
    -- one turning off never strands the other: the vehicle/override bar
    -- (OverrideActionBarButton1-6) and the extra action button
    -- (ExtraActionButton1 -- its spell-typed delve abilities have no action
    -- slot, so our own dispatch can't paint their cooldown; only Blizzard's
    -- native update, driven by this broadcaster, can).
    local _vehNeed, _extraNeed, _broadcasterActive = false, false, false
    local function ApplyBroadcaster()
        local want = _vehNeed or _extraNeed
        if want == _broadcasterActive then return end
        _broadcasterActive = want
        if want then
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
        else
            if ActionBarButtonEventsFrame then ActionBarButtonEventsFrame:UnregisterAllEvents() end
            if ActionBarActionEventsFrame then ActionBarActionEventsFrame:UnregisterAllEvents() end
        end
    end
    -- Recompute both needs from ground truth -- the actual visibility of the
    -- buttons that depend on the broadcaster -- and apply. We poll visibility on
    -- a broad set of events (below) instead of tracking enter/exit precisely,
    -- because the triggering events proved unreliable: the extra action button's
    -- own OnShow doesn't fire on delve entry, and the vehicle enter events don't
    -- reliably fire/keep state either. Visibility is the ground truth.
    local function RefreshBroadcasterNeeds()
        _vehNeed = (OverrideActionBarButton1 and OverrideActionBarButton1:IsShown()) and true or false
        _extraNeed = (ExtraActionButton1 and ExtraActionButton1:IsShown()) and true or false
        ApplyBroadcaster()
    end
    -- Exposed for the extra action button's Show-hook refresh in
    -- SetupBlizzardMovableFrame (a reliable trigger for delve entry).
    ns.RefreshBroadcaster = RefreshBroadcasterNeeds
    local barFrame = CreateFrame("Frame")
    barFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
    barFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    barFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
    barFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
    barFrame:RegisterEvent("UPDATE_EXTRA_ACTIONBAR")
    barFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    barFrame:SetScript("OnEvent", function(_, event, unit)
        -- Deferred so IsShown reflects Blizzard's post-event state.
        C_Timer.After(0, RefreshBroadcasterNeeds)
        -- On vehicle/override entry, force-paint the OverrideActionBar buttons'
        -- cooldowns immediately -- the broadcaster only catches the NEXT change,
        -- so an ability already on cooldown when the bar appears needs an
        -- initial paint (see ForceCooldownPaint).
        if (event == "UNIT_ENTERED_VEHICLE" or event == "UPDATE_VEHICLE_ACTIONBAR"
            or event == "UPDATE_OVERRIDE_ACTIONBAR") and not (unit and unit ~= "player") then
            C_Timer.After(0, function()
                for i = 1, 6 do
                    local btn = _G["OverrideActionBarButton" .. i]
                    if btn then
                        if btn.UpdateAction then btn:UpdateAction() end
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
--  Early Blizzard Bar Disposal (file load time)
--  Runs at addon load before combat state is restored, so protected calls
--  (Hide, SetParent) execute cleanly without tainting Blizzard's
--  ActionBarController call chain.
-------------------------------------------------------------------------------
do
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

            (frame.HideBase or frame.Hide)(frame)
            -- MainActionBar stays in Blizzard's parent chain so pet battle
            -- restoration of MicroMenu works. All others safely reparent.
            if frameName ~= "MainActionBar" then
                frame:SetParent(hiddenParent)
            else
                -- Keep MainActionBar invisible when Blizzard re-shows it on
                -- spec / zone / vehicle / bonus-bar transitions WITHOUT touching
                -- its protected shown state. Calling Hide() (or any *Base shown
                -- setter) from this insecure hook taints MainActionBar, and
                -- Blizzard's ValidateActionBarTransition then hits
                -- ADDON_ACTION_BLOCKED on MainActionBar:SetShownBase the next time
                -- it shows the bar in combat. (Repro: a quest bonus bar in Azshara
                -- shows the frame out of combat -> the old Hide() tainted it ->
                -- one-shotting a mob triggered a brief combat transition that then
                -- blocked SetShownBase.) SetAlpha is unprotected, inherits to all
                -- children, and works in combat, so the bar stays hidden taint-free.
                hooksecurefunc(frame, "Show", function(self)
                    self:SetAlpha(0)
                end)
                -- Disable mouse on MainActionBar so it never eats clicks.
                -- During combat, Blizzard can Show() this frame (mount/dismount
                -- transitions). At alpha 0 and frame level 50 it would invisibly
                -- intercept all clicks above our EABButtons.
                frame:EnableMouse(false)
                if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
                if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
                -- Hide Edit Mode selection/mover frame
                if frame.Selection then frame.Selection:Hide(); frame.Selection:SetAlpha(0) end
                -- Hide artwork children (gryphons/endcaps/border)
                if frame.EndCaps then frame.EndCaps:Hide() end
                if frame.BorderArt then frame.BorderArt:Hide() end
                frame:SetAlpha(0)
            end

            if frame.actionButtons and type(frame.actionButtons) == "table" then
                for _, button in pairs(frame.actionButtons) do
                    button:UnregisterAllEvents()
                    button:SetAttributeNoHandler("statehidden", true)
                    button:Hide()
                end
            end
        end
    end

    -- Hide ActionBarParent (the top-level container for stock action bars).
    -- All individual bar frames are already reparented above, so this is
    -- purely cosmetic (hides any leftover chrome). OverrideActionBar is
    -- parented to UIParent, not ActionBarParent, so it is unaffected.
    -- Done here at file-load time instead of via RegisterAttributeDriver
    -- to avoid tainting Blizzard's protected frame state.
    if ActionBarParent then
        ActionBarParent:Hide()
        ActionBarParent:SetParent(hiddenParent)
    end
end

-------------------------------------------------------------------------------
--  Central Action Button Controller
--  A SecureHandlerAttributeTemplate that manages ALL action buttons.
--  Tracks button-to-action mappings in a secure table, implements bitwise
--  showgrid, and uses a deferred visibility flush so rapid state changes
--  batch into a single update pass.
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

-- Secure method: SetShowGrid (bitwise flag toggle)
-- Restricted Lua has no bit library, so we use modular arithmetic to
-- test and flip individual flag bits in the showgrid bitmask.
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

-- Deferred visibility: setting "flush" to 0 marks it dirty. The attribute
-- driver resets it to 1 after ~200ms, at which point we apply pending
-- visibility changes in one batch instead of per-attribute-change.
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

-- When a drag starts over a button, forward the drag kind so the post-handler
-- can refresh visibility for the affected action slot.
local BTN_ON_RECEIVE_DRAG_BEFORE = [[
    if kind then return "message", kind end
]]

local BTN_ON_RECEIVE_DRAG_AFTER = [[
    control:RunAttribute("ForActionSlot", self:GetAttribute("action"), "UpdateShown")
]]

-- Re-evaluate visibility whenever a button is shown or hidden to catch
-- delayed state changes from the secure environment.
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

    -- On /reload, Lua locals reset but frames survive. If the button
    -- already has our secure snippets from a previous session, skip
    -- the WrapScript + Execute calls to avoid tainting the restricted
    -- environment during combat. Just restore the Lua-side registry.
    if btn:GetAttribute("_eabControllerRegistered") then
        _controllerButtons[btn] = true
        return
    end

    ActionButtonController:WrapScript(btn, "OnAttributeChanged", BTN_ON_ATTRIBUTE_CHANGED)
    ActionButtonController:WrapScript(btn, "PostClick", BTN_POST_CLICK)
    ActionButtonController:WrapScript(btn, "OnReceiveDrag", BTN_ON_RECEIVE_DRAG_BEFORE, BTN_ON_RECEIVE_DRAG_AFTER)
    ActionButtonController:WrapScript(btn, "OnShow", BTN_ON_SHOW_HIDE)
    ActionButtonController:WrapScript(btn, "OnHide", BTN_ON_SHOW_HIDE)

    -- Per-button showgrid: toggle the flag bit and update visibility
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
            local vis = (cur > 0 or HasAction(self:GetAttribute("action") or 0))
                and not self:GetAttribute("statehidden")
            if vis then self:Show(true) else self:Hide(true) end
        end
    ]])

    -- Visibility evaluation: show if grid is active or action exists,
    -- unless the button is explicitly state-hidden.
    btn:SetAttributeNoHandler("UpdateShown", [[
        local grid = (self:GetAttribute("showgrid") or 0) > 0
        local hasAct = HasAction(self:GetAttribute("action") or 0)
        local hidden = self:GetAttribute("statehidden")
        if (grid or hasAct) and not hidden then
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
    if InCombatLockdown() then return end
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
--  Override Controller
--  Monitors vehicle/override/possess/form/petbattle states via attribute
--  drivers and propagates state changes to all registered bar frames.
--  Parented to UIParent -- never parent addon frames to OverrideActionBar
--  as that taints its child hierarchy and blocks BeginActionBarTransition.
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

    -- Register attribute drivers for all relevant state conditions.
    -- overrideui driven by [overridebar][vehicleui] instead of parenting
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

-- Add a bar frame to the override controller's watch list
local function RegisterBarWithOverrideController(frame)
    OverrideController:SetFrameRef("add", frame)
    OverrideController:Execute([[ table.insert(_eabBarFrames, self:GetFrameRef("add")) ]])

    -- Initialize state on the frame
    frame:SetAttribute("state-overrideui", tonumber(OverrideController:GetAttribute("overrideui")) == 1)
    frame:SetAttribute("state-petbattleui", tonumber(OverrideController:GetAttribute("petbattleui")) == 1)
    frame:SetAttribute("state-overridepage", OverrideController:GetAttribute("overridepage") or 0)
end

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
-- Forward declaration: populated in the Button Creation section below.
-- Needed here because SecureSetupHandler_PrepareRefs references it.
local barButtons = {}
ns.barButtons = barButtons

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
    -- Fully hide all Blizzard action buttons. We create our own buttons
    -- instead, so these are parented to a hidden frame and silenced.
    -- Stance and Pet buttons are still reused, so only hide action buttons.
    for _, info in ipairs(BAR_CONFIG) do
        if info.blizzBtnPrefix and not info.isStance and not info.isPetBar then
            for i = 1, info.count do
                local btn = _G[info.blizzBtnPrefix .. i]
                if btn then
                    btn:UnregisterAllEvents()
                    btn:SetAttributeNoHandler("statehidden", true)
                    btn:SetParent(hiddenParent)
                    btn:Hide()
                end
            end
        end
    end
    -- Hide stock bar frames. MainMenuBar, StanceBar, PetActionBar need
    -- EAB.db to be ready, so they are handled here rather than at file load.
    local remainingBars = { "MainMenuBar", "StanceBar", "PetActionBar" }
    for _, name in ipairs(remainingBars) do
        local bar = _G[name]
        if bar then
            bar:UnregisterAllEvents()
            local safeHide = bar.HideBase or bar.Hide
            safeHide(bar)
            bar:SetParent(hiddenParent)
            -- Prevent Blizzard from re-showing (spell transforms like
            -- Ascendance can trigger ValidateActionBarTransition which
            -- re-shows and repositions, creating invisible dead zones)
            bar:HookScript("OnShow", function(self)
                self:Hide()
            end)
            if bar.actionButtons and type(bar.actionButtons) == "table" then
                for _, child in pairs(bar.actionButtons) do
                    child:UnregisterAllEvents()
                    child:SetAttributeNoHandler("statehidden", true)
                    child:Hide()
                end
            end
        end
    end
    -- ActionBarController retains all events so Blizzard's vehicle/override
    -- transition system (ValidateActionBarTransition) works correctly.
    if MainMenuBarPageNumber then MainMenuBarPageNumber:Hide() end

    -- Replace ActionBar_PageUp / ActionBar_PageDown with versions that
    -- read the current page from our state driver. The stock versions
    -- call ChangeActionBarPage (a C function) which uses
    -- GetActionBarPage() internally. Something in the stock pipeline
    -- resets the page back to 1 after each change because we disabled
    -- MainMenuBar. Our replacements read state-page from the MainBar
    -- frame and call SetActionBarPage directly.
    ActionBar_PageUp = function()
        local mainFrame = barFrames and barFrames["MainBar"]
        local curPage
        if mainFrame then
            curPage = tonumber(mainFrame:GetAttribute("state-page")) or 1
        else
            curPage = EAB_VTABLE.GetActionBarPage()
        end
        local maxPages = NUM_ACTIONBAR_PAGES or 6
        local newPage = curPage + 1
        if newPage > maxPages then newPage = 1 end
        ChangeActionBarPage(newPage)
    end
    ActionBar_PageDown = function()
        local mainFrame = barFrames and barFrames["MainBar"]
        local curPage
        if mainFrame then
            curPage = tonumber(mainFrame:GetAttribute("state-page")) or 1
        else
            curPage = EAB_VTABLE.GetActionBarPage()
        end
        local maxPages = NUM_ACTIONBAR_PAGES or 6
        local newPage = curPage - 1
        if newPage < 1 then newPage = maxPages end
        ChangeActionBarPage(newPage)
    end

    -- Hide status tracking bar manager (unless user wants Blizzard data bars)
    if not (EAB.db and EAB.db.profile.useBlizzardDataBars) then
        if StatusTrackingBarManager then
            StatusTrackingBarManager:UnregisterAllEvents()
            StatusTrackingBarManager:Hide()
        end
    end
    -- ActionBarParent is hidden at file-load time (early disposal).
    -- OverrideActionBar visibility is fully owned by Blizzard's
    -- ValidateActionBarTransition() in ActionBarController.lua.
    -- No RegisterAttributeDriver calls on Blizzard-owned frames — those
    -- risk tainting protected state (actionpage, action attributes) that
    -- OverrideActionBar buttons inherit.
    -- Force all Blizzard action bars to be "enabled" via CVars so buttons work
    C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_1", "1")
    C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_2", "1")
    C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_3", "1")
    C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_4", "1")

end

-------------------------------------------------------------------------------
--  Button Creation
--  All action bar buttons (slots 1-180) are our own EABButton frames.
--  Stance/Pet bars still reuse Blizzard buttons.
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
    Bar9 = 12,      -- slots 13-24   (action page 2 -- custom bar)
    Bar10 = 108,    -- slots 109-120 (action page 10 -- custom bar, no native frame)
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
    -- Bar9/Bar10 have no native binding commands; these custom commands are
    -- defined in Bindings.xml and routed via SetOverrideBindingClick (the keypress
    -- clicks our button, which reads the paged "action" attr).
    Bar9 = "EUI_BAR9_BUTTON",
    Bar10 = "EUI_BAR10_BUTTON",
    StanceBar = "SHAPESHIFTBUTTON",
    PetBar = "BONUSACTIONBUTTON",
}

-- Readable labels for the custom Bar9/Bar10 binding commands declared in
-- Bindings.xml. Global writes only (no file-scope locals). The keybind UI reads
-- BINDING_HEADER_<header> for the section title and BINDING_NAME_<command> per row.
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

-- Forward declaration -- defined fully in the keybind section below.
-- Allows SetupBar to eagerly create bind buttons while out of combat.
-- (bind-button forward declaration removed: all action bars use native dispatch)
-------------------------------------------------------------------------------
--  Re-register events on action buttons after HideBlizzardBars unregistered
--  them. These are the events that Blizzard's button mixins need for
--  real-time icon, cooldown, usability, and state updates.
-------------------------------------------------------------------------------
local BUTTON_EVENT_LISTS = {
    action = {
        "ACTIONBAR_UPDATE_STATE",
        "ACTIONBAR_UPDATE_USABLE",
        "ACTIONBAR_UPDATE_COOLDOWN",
        -- ACTIONBAR_SLOT_CHANGED is deliberately NOT registered per button.
        -- Mouseover-conditional macros re-resolve on every mouseover flip and
        -- fire it dozens of times per second; dispatching that to the mixin
        -- OnEvent of every button burned whole frames (profiled: ~7s CPU per
        -- 10s of sweeping the cursor across nameplates). The central
        -- dispatcher runs UpdateAction for the matching slot and clears stale
        -- count text -- everything the mixin's handler did.
        "PLAYER_ENTERING_WORLD",
        "UPDATE_SHAPESHIFT_FORM",
        "SPELL_UPDATE_CHARGES",
        "UPDATE_INVENTORY_ALERTS",
        "PLAYER_EQUIPMENT_CHANGED",
        "LOSS_OF_CONTROL_ADDED",
        "LOSS_OF_CONTROL_UPDATE",
        -- Native per-button usability updates: each button reacts via
        -- Blizzard's C-side ActionButton OnEvent dispatcher, replacing
        -- the old global usableFrame polling.
        "PLAYER_TARGET_CHANGED",
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

-- Get or create an action button for a given slot.
-- Action bars (1-8) always create our own buttons (ActionBarButtonTemplate
-- already includes SecureActionButtonTemplate). This eliminates the taint
-- surface: Blizzard's protected buttons are never reused, so cross-addon
-- taint can never propagate to SetShown/Show/Hide on action bar buttons.
-- Stance bar still reuses Blizzard StanceButtons (own secure handling).
-- Pet bar is set up separately in SetupBar.
--
-- skipProtected: if true, skip SetParent/Show (used during combat reload;
-- the secure handler will perform those operations instead)
local function GetOrCreateButton(slot, parent, info, index, skipProtected)
    if allButtons[slot] then
        if not skipProtected then
            allButtons[slot]:SetParent(parent)
        end
        return allButtons[slot]
    end

    local btn
    if info.isStance then
        -- Stance bar: reuse Blizzard buttons (own secure stance handling)
        btn = _G["StanceButton" .. index]
        if btn and not skipProtected then
            btn:SetAttributeNoHandler("statehidden", nil)
            ReRegisterButtonEvents(btn, "stance")
            btn:SetParent(parent)
            btn:Show()
        end
    else
        -- Action bars: create our own button. ActionBarButtonTemplate
        -- inherits SecureActionButtonTemplate, so click dispatch, drag-and-
        -- drop, and the full visual mixin (icon, cooldown, border) all work.
        -- Frames persist across /reload; reuse if already in _G.
        local name = "EABButton" .. slot
        btn = _G[name]
        if not btn then
            btn = CreateFrame("CheckButton", name, parent, "ActionBarButtonTemplate, SecureActionButtonTemplate")
            -- Neuter UpdateButtonArt: the mixin resets NormalTexture/PushedTexture
            -- atlases on every call. With 96 buttons this causes mass GPU redraws.
            -- We handle button art ourselves in MakeButtonSquare/ApplyPushedTextures.
            btn.UpdateButtonArt = function() end
        end
        -- 12.1's template OnLoad self-registers ACTIONBAR_SLOT_CHANGED on the
        -- button. The central dispatcher owns that event (see the
        -- BUTTON_EVENT_LISTS note): the mixin's own handler runs Update()
        -- under our execution taint (the UpdateButtonArt neuter above is a
        -- tainted field in that chain) and errors on secret cooldown args,
        -- plus blocked SetAttribute from UpdatePressAndHoldAction in combat.
        -- No-op on 12.0, where the event is never self-registered.
        btn:UnregisterEvent("ACTIONBAR_SLOT_CHANGED")
        -- The template OnLoad also registered this button with Blizzard's
        -- ActionBarButtonEventsFrame broadcaster. That tinsert ran under OUR
        -- execution, so the stored entry is a tainted value: while the
        -- broadcaster is re-enabled for the vehicle/extra button (see
        -- ApplyBroadcaster), its dispatch loop reads the entry and the
        -- button's whole mixin OnEvent runs tainted -- blocked SetAttribute
        -- from UpdatePressAndHoldAction (ACTIONBAR_SLOT_CHANGED) and secret
        -- SetCooldown rejections (ACTIONBAR_UPDATE_COOLDOWN) in combat.
        -- UnregisterEvent cannot stop that path (it calls OnEvent directly),
        -- and wrapping btn.OnEvent would be worse: the template wires
        -- <OnEvent method="OnEvent"/>, so the engine's per-button dispatch
        -- resolves the method at fire time -- a replacement function of ours
        -- is a tainted value and would taint EVERY per-button event dispatch
        -- (per-button cooldown updates only work because they start secure).
        -- Instead, remove our entry from the broadcaster's list: nil it out
        -- in place (never tremove -- shifting would rewrite later
        -- Blizzard-owned entries as tainted values). The button loses
        -- nothing: every event it needs is self-registered
        -- (BUTTON_EVENT_LISTS) or handled by the central dispatcher.
        if ActionBarButtonEventsFrame and type(ActionBarButtonEventsFrame.frames) == "table" then
            for k, f in pairs(ActionBarButtonEventsFrame.frames) do
                if f == btn then ActionBarButtonEventsFrame.frames[k] = nil end
            end
        end
        -- Desaturate-on-cooldown / on-CD alpha: re-evaluate the icon's visual
        -- state the moment the main cooldown display completes. The
        -- SetDesaturation/SetAlpha writes are static between events, so
        -- without this edge the icon only recovered at the NEXT cooldown
        -- event -- and a charge spell's recharge end (at 0 charges the
        -- recharge IS the main cooldown) is exactly such an edge. The handler
        -- re-evaluates from live data rather than blind-clearing, so a GCD
        -- display completing on a banked-charge spell is a no-op. HookScript
        -- (never SetScript): the template's own charge/LoC handling may own
        -- the script slot. Guarded: bar rebuilds reuse these frames and
        -- HookScript stacks.
        if btn.cooldown and not EFD(btn).cdDoneHooked then
            EFD(btn).cdDoneHooked = true
            btn.cooldown:HookScript("OnCooldownDone", function(cd)
                if EAB._RefreshCooldownVisuals then
                    EAB._RefreshCooldownVisuals(cd:GetParent())
                end
            end)
        end
        -- When the pickup modifier is held (shift-click to move abilities),
        -- temporarily disable useOnKeyDown so the action doesn't fire on
        -- mouse down. The pickup happens before the up event, so the
        -- action is consumed by the drag rather than cast. Restore in post.
        if not btn:GetAttribute("eabPickupWrap") and not InCombatLockdown() then
            btn:SetAttribute("eabPickupWrap", true)
            SecureHandlerWrapScript(btn, "OnClick", btn, [[
                if IsModifiedClick("PICKUPACTION") then
                    local cur = self:GetAttribute("useOnKeyDown")
                    if cur ~= false then
                        self:SetAttribute("eabKeyDownBackup", cur or true)
                        self:SetAttribute("useOnKeyDown", false)
                    end
                end
            ]], [[
                if self:GetAttribute("eabKeyDownBackup") then
                    self:SetAttribute("useOnKeyDown", self:GetAttribute("eabKeyDownBackup"))
                    self:SetAttribute("eabKeyDownBackup", nil)
                end
            ]])
        end
        if not skipProtected then
            btn:SetParent(parent)
            btn:SetID(0)
            btn:SetAttribute("action", slot)
        end
    end

    RegisterButtonWithController(btn)
    allButtons[slot] = btn
    return btn
end

local NUM_AB_PAGES = NUM_ACTIONBAR_PAGES or 6

-- Hybrid keybind routing: empower spells use SetOverrideBindingClick so our
-- buttons' pressAndHoldAction/typerelease handle hold-and-release. Non-empower
-- spells use SetOverrideBinding to native commands for press-and-hold repeat.

-- Safe API wrappers: 12.0.5 may move these globals to C_ActionBar.
-- Stored on EAB_VTABLE to avoid 200-local Lua 5.1 limit.
do
    local V = EAB_VTABLE
    V.GetOverrideBarIndex = GetOverrideBarIndex or (C_ActionBar and C_ActionBar.GetOverrideBarIndex) or function() return 14 end
    V.GetVehicleBarIndex = GetVehicleBarIndex or (C_ActionBar and C_ActionBar.GetVehicleBarIndex) or function() return 12 end
    V.GetActionBarPage = GetActionBarPage or (C_ActionBar and C_ActionBar.GetActionBarPage) or function() return 1 end
    V.HasVehicleActionBar = HasVehicleActionBar or (C_ActionBar and C_ActionBar.HasVehicleActionBar) or function() return false end
    V.HasOverrideActionBar = HasOverrideActionBar or (C_ActionBar and C_ActionBar.HasOverrideActionBar) or function() return false end
    V.HasTempShapeshiftActionBar = HasTempShapeshiftActionBar or (C_ActionBar and C_ActionBar.HasTempShapeshiftActionBar) or function() return false end
end

-------------------------------------------------------------------------------
--  Configurable Paging System
--  Allows per-bar paging based on modifier keys and class forms/stances.
--  When paging config is empty, bars behave exactly as before (zero impact).
-------------------------------------------------------------------------------

-- All paging data stored on EAB_VTABLE to avoid 200-local Lua 5.1 limit.
EAB_VTABLE.BAR_KEY_TO_PAGE = {
    MainBar = 1,  Bar2 = 6,  Bar3 = 5,  Bar4 = 3,
    Bar5 = 4,     Bar6 = 13, Bar7 = 14, Bar8 = 15,
    Bar9 = 2,     Bar10 = 10,
}
EAB_VTABLE.PAGING_STATES = {
    modifier = {
        { id = "alt",   macro = "[mod:alt]",   label = "Alt" },
        { id = "shift", macro = "[mod:shift]", label = "Shift" },
        { id = "ctrl",  macro = "[mod:ctrl]",  label = "Ctrl" },
    },
    target = {
        { id = "help",  macro = "[help]",      label = "Friendly Target" },
        { id = "harm",  macro = "[harm]",      label = "Hostile Target" },
    },
    class = {
        DRUID = {
            { id = "prowl",   macro = "[bonusbar:1,stealth]", label = "Prowl" },
            { id = "cat",     macro = "[bonusbar:1]",         label = "Cat Form" },
            { id = "tree",    macro = "[bonusbar:2]",         label = "Tree of Life" },
            { id = "bear",    macro = "[bonusbar:3]",         label = "Bear Form" },
            { id = "moonkin", macro = "[bonusbar:4]",         label = "Moonkin Form" },
        },
        ROGUE = {
            { id = "stealth", macro = "[bonusbar:1]", label = "Stealth" },
        },
        WARRIOR = {
            { id = "battle",    macro = "[bonusbar:1]", label = "Battle Stance" },
            { id = "defensive", macro = "[bonusbar:2]", label = "Defensive Stance" },
        },
        EVOKER = {
            { id = "soar", macro = "[bonusbar:1]", label = "Soar" },
        },
    },
}

function EAB_VTABLE.BuildPagingConditions(barKey, pagingConfig, defaultPage)
    if not pagingConfig or not next(pagingConfig) then return nil end
    local PG = EAB_VTABLE.PAGING_STATES
    local _, class = UnitClass("player")
    local parts = {}
    if barKey == "MainBar" then
        if EAB_VTABLE.GetOverrideBarIndex then
            parts[#parts + 1] = "[overridebar] " .. EAB_VTABLE.GetOverrideBarIndex()
        end
        if EAB_VTABLE.GetVehicleBarIndex then
            parts[#parts + 1] = "[vehicleui][possessbar] " .. EAB_VTABLE.GetVehicleBarIndex()
        end
    end
    for _, state in ipairs(PG.modifier) do
        local page = pagingConfig[state.id]
        if page then
            parts[#parts + 1] = state.macro .. " " .. page
        end
    end
    -- Class defaults: MainBar falls back to hardcoded form pages for
    -- unconfigured (nil) states so setting a modifier doesn't break forms.
    -- false = explicitly disabled by user ("None"), nil = unconfigured.
    local CLASS_DEFAULTS = {
        DRUID  = { prowl = 7, cat = 7, tree = 8, bear = 9, moonkin = 10 },
        ROGUE  = { stealth = 7 },
    }
    local classStates = PG.class[class]
    if classStates then
        local defs = barKey == "MainBar" and CLASS_DEFAULTS[class]
        for _, state in ipairs(classStates) do
            local page = pagingConfig[state.id]
            if page then
                parts[#parts + 1] = state.macro .. " " .. page
            elseif page == nil and defs and defs[state.id] then
                parts[#parts + 1] = state.macro .. " " .. defs[state.id]
            end
            -- page == false: explicitly disabled, skip
        end
    end
    if barKey == "MainBar" then
        parts[#parts + 1] = "[bonusbar:5] 11"
        for i = 2, NUM_AB_PAGES do
            parts[#parts + 1] = "[bar:" .. i .. "] " .. i
        end
    end
    -- Target conditions come after bonusbar/bar so dragonriding and manual
    -- page switches always take priority over target-based switching.
    if PG.target then
        for _, state in ipairs(PG.target) do
            local page = pagingConfig[state.id]
            if page then
                parts[#parts + 1] = state.macro .. " " .. page
            end
        end
    end
    parts[#parts + 1] = tostring(defaultPage or 1)
    return table.concat(parts, "; ")
end

-------------------------------------------------------------------------------
--  Paging State Conditions (class-specific, hardcoded fallback)
--  Used when no custom paging is configured. Produces the exact same
--  conditional string as the original implementation for zero impact.
--  Format: "[condition] pageNumber; ..."
-------------------------------------------------------------------------------
local function GetClassPagingConditions()
    local _, class = UnitClass("player")
    local conditions = ""

    -- Override bar (soft vehicle / quest abilities) and possess bar: remap bar 1
    -- to show those action slots so our buttons stay visible and keybinds work.
    if EAB_VTABLE.GetOverrideBarIndex then
        conditions = conditions .. "[overridebar] " .. EAB_VTABLE.GetOverrideBarIndex() .. "; "
    end
    if EAB_VTABLE.GetVehicleBarIndex then
        conditions = conditions .. "[vehicleui][possessbar] " .. EAB_VTABLE.GetVehicleBarIndex() .. "; "
    end

    -- Class-specific paging
    if class == "DRUID" then
        conditions = conditions .. "[bonusbar:1,stealth] 7; [bonusbar:1] 7; [bonusbar:3] 9; [bonusbar:4] 10; "
    elseif class == "ROGUE" then
        conditions = conditions .. "[bonusbar:1] 7; "
    end

    -- Dragonriding (all classes)
    conditions = conditions .. "[bonusbar:5] 11; "

    -- Manual page switching (pages 2-6)
    -- [bar:N] responds to WoW's internal page set by ChangeActionBarPage().
    -- The built-in keybinds and our paging arrows trigger this securely.
    for i = 2, NUM_AB_PAGES do
        conditions = conditions .. "[bar:" .. i .. "] " .. i .. "; "
    end

    -- Default: page 1
    conditions = conditions .. "1"

    return conditions
end

-------------------------------------------------------------------------------
--  Action Bar 1 Paging Arrows + Page Number
-------------------------------------------------------------------------------
local _pagingFrame    -- forward ref
local LayoutPagingFrame  -- forward ref (used inside SetupPagingFrame closure)

-- The paging frame is parented to the MainBar frame (see LayoutPagingFrame), so
-- it inherits the bar's mouseover-fade alpha AND its secure show/hide visibility
-- automatically. Keep its own alpha at 1 so the parent governs it solely (no
-- double-fade). Kept as a function so the many existing call sites stay valid.
local function SyncPagingAlpha()
    if _pagingFrame then _pagingFrame:SetAlpha(1) end
end

-- Paging arrows and keybind buttons use SecureActionButtonTemplate with
-- type "macro". The macro uses [bar:N] conditionals to cycle through
-- pages statically, so no dynamic attribute changes are needed.
-- This runs in the protected execution path on hardware click.
local _macroNext = "/changeactionbar [bar:6] 1"
local _macroPrev = "/changeactionbar [bar:1] 6"
for i = 1, NUM_AB_PAGES - 1 do
    _macroNext = _macroNext .. "; [bar:" .. i .. "] " .. (i + 1)
    _macroPrev = _macroPrev .. "; [bar:" .. (i + 1) .. "] " .. i
end

local function WireSecurePagingButton(btn, delta)
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", delta > 0 and _macroNext or _macroPrev)
end

local function InitPagingQuickKeybindButton(btn, atlas)
    if not btn then return end

    if not btn.QuickKeybindHighlightTexture then
        local tex = btn:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints(btn)
        tex:SetAtlas(atlas)
        tex:SetAlpha(0.8)
        tex:Hide()
        btn.QuickKeybindHighlightTexture = tex
    end

    if EFD(btn).quickKeybindInit or not QuickKeybindButtonTemplateMixin then
        return
    end

    Mixin(btn, QuickKeybindButtonTemplateMixin)
    btn:HookScript("OnShow", btn.QuickKeybindButtonOnShow)
    btn:HookScript("OnHide", btn.QuickKeybindButtonOnHide)
    btn:HookScript("OnClick", btn.QuickKeybindButtonOnClick)
    btn:HookScript("OnEnter", btn.QuickKeybindButtonOnEnter)
    btn:HookScript("OnLeave", btn.QuickKeybindButtonOnLeave)
    EFD(btn).quickKeybindInit = true
    -- Do NOT call btn:QuickKeybindButtonOnShow() eagerly here. It registers
    -- persistent EventRegistry callbacks that fire UpdateMouseWheelHandler
    -- (and thus SetScript) on a SecureActionButtonTemplate frame on every
    -- QKB mode change. The HookScript("OnShow") handles runtime visibility.
end

local function SetupPagingFrame()
    if _pagingFrame then return _pagingFrame end

    local f = CreateFrame("Frame", "EABPagingFrame", UIParent)
    f:SetSize(20, 52)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(10)

    -- Page number text
    local pageText = f:CreateFontString(nil, "OVERLAY")
    pageText:SetFont(STANDARD_TEXT_FONT, 12, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
    pageText:SetTextColor(1, 1, 1, 0.9)
    pageText:SetText("1")
    f._pageText = pageText

    -- Up arrow (clicks Blizzard's ActionBarUpButton securely)
    local upBtn = CreateFrame("Button", "EABPagingUp", f, "SecureActionButtonTemplate")
    upBtn:SetSize(18, 18)
    upBtn:RegisterForClicks("AnyUp", "AnyDown")
    upBtn:SetNormalAtlas("UI-HUD-ActionBar-PageUpArrow-Up")
    upBtn:SetPushedAtlas("UI-HUD-ActionBar-PageUpArrow-Down")
    upBtn:SetDisabledAtlas("UI-HUD-ActionBar-PageUpArrow-Disabled")
    upBtn:SetHighlightAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover")
    f._upBtn = upBtn
    InitPagingQuickKeybindButton(upBtn, "UI-HUD-ActionBar-PageUpArrow-Mouseover")

    -- Down arrow (clicks Blizzard's ActionBarDownButton securely)
    local downBtn = CreateFrame("Button", "EABPagingDown", f, "SecureActionButtonTemplate")
    downBtn:SetSize(18, 18)
    downBtn:RegisterForClicks("AnyUp", "AnyDown")
    downBtn:SetNormalAtlas("UI-HUD-ActionBar-PageDownArrow-Up")
    downBtn:SetPushedAtlas("UI-HUD-ActionBar-PageDownArrow-Down")
    downBtn:SetDisabledAtlas("UI-HUD-ActionBar-PageDownArrow-Disabled")
    downBtn:SetHighlightAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover")
    f._downBtn = downBtn
    InitPagingQuickKeybindButton(downBtn, "UI-HUD-ActionBar-PageDownArrow-Mouseover")

    -- Update page text and handle combat visibility / vehicle state
    f:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    f:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    f:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
    f:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event)
        if event == "UPDATE_OVERRIDE_ACTIONBAR" or event == "UPDATE_VEHICLE_ACTIONBAR" then
            LayoutPagingFrame()
            -- Trigger page sync (replaces CallMethod in _onstate-page).
            -- During combat the Queue callback early-returns, so the sync
            -- only runs out of combat -- same as the old CallMethod path.
            EAB_VTABLE.MainBarPageSync.Queue()
            return
        end
        if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
            local s = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars["MainBar"]
            if s and not InCombatLockdown() then
                local inCombat = (event == "PLAYER_REGEN_DISABLED")
                if s.combatShowEnabled then
                    if inCombat then f:Show() else f:Hide() end
                elseif s.combatHideEnabled then
                    if inCombat then f:Hide() else f:Show() end
                end
            end
            return
        end
        local page = EAB_VTABLE.GetActionBarPage()
        pageText:SetText(tostring(page))
        -- Trigger page sync for manual page changes, form changes, etc.
        EAB_VTABLE.MainBarPageSync.Queue()
    end)

    -- Initial text
    local initPage = EAB_VTABLE.GetActionBarPage()
    pageText:SetText(tostring(initPage))

    -- Wire arrow buttons to cycle pages via secure macro
    WireSecurePagingButton(upBtn, 1)
    WireSecurePagingButton(downBtn, -1)
    upBtn.commandName = "NEXTACTIONPAGE"
    downBtn.commandName = "PREVIOUSACTIONPAGE"

    _pagingFrame = f
    return f
end

LayoutPagingFrame = function()
    local f = _pagingFrame
    if not f then return end
    if InCombatLockdown() then return end
    local mainFrame = barFrames and barFrames["MainBar"]
    if not mainFrame then f:Hide(); return end

    local s = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars["MainBar"]
    if not s then f:Hide(); return end

    -- Parent the paging frame to the MainBar frame so it inherits the bar's
    -- secure show/hide (visibility settings like combat-only, hide-no-target,
    -- etc.) and mouseover-fade alpha. Reparenting secure children is blocked in
    -- combat, so this is gated by the InCombatLockdown check above; once parented
    -- the secure visibility driver on the MainBar propagates to these arrows
    -- automatically, including in combat.
    if f:GetParent() ~= mainFrame then
        f:SetParent(mainFrame)
        f:SetFrameStrata("MEDIUM")
        f:SetFrameLevel((mainFrame:GetFrameLevel() or 1) + 5)
        f:SetAlpha(1)
    end

    if s.alwaysHidden or s.enabled == false or not s.showPagingArrows then
        f:Hide()
        return
    end

    -- Hide during vehicle/override (paging doesn't apply)
    local overridePage = mainFrame:GetAttribute("state-overridepage") or 0
    if overridePage > 0 then
        f:Hide()
        return
    end

    local isVertical = (s.orientation == "vertical")
    local base = barBaseSize and barBaseSize["MainBar"]
    local btnH = (s.buttonHeight and s.buttonHeight > 0) and s.buttonHeight or (base and base.h or 45)
    local arrowSize = math.max(14, math.floor(btnH * 0.4))
    local textSize = math.max(10, math.floor(arrowSize * 0.7))
    local gap = 2

    f._upBtn:SetSize(arrowSize, arrowSize)
    f._downBtn:SetSize(arrowSize, arrowSize)
    f._pageText:SetFont(STANDARD_TEXT_FONT, textSize, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")

    f._upBtn:ClearAllPoints()
    f._downBtn:ClearAllPoints()
    f._pageText:ClearAllPoints()

    local onRight = s.pagingArrowsRight

    if isVertical then
        local totalW = arrowSize + gap + textSize * 2 + gap + arrowSize
        f:SetSize(totalW, arrowSize)
        f:ClearAllPoints()
        if onRight then
            f:SetPoint("TOP", mainFrame, "BOTTOM", 0, -4)
        else
            f:SetPoint("BOTTOM", mainFrame, "TOP", 0, 4)
        end
        f._downBtn:SetPoint("LEFT", f, "LEFT", 0, 0)
        f._pageText:SetPoint("CENTER", f, "CENTER", 0, 0)
        f._upBtn:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    else
        local totalH = arrowSize + gap + textSize + gap + arrowSize
        f:SetSize(arrowSize, totalH)
        f:ClearAllPoints()
        if onRight then
            f:SetPoint("LEFT", mainFrame, "RIGHT", 4, 0)
        else
            f:SetPoint("RIGHT", mainFrame, "LEFT", -4, 0)
        end
        f._upBtn:SetPoint("TOP", f, "TOP", 0, 0)
        f._pageText:SetPoint("CENTER", f, "CENTER", 0, 0)
        f._downBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
    end

    f:Show()
end
ns.LayoutPagingFrame = LayoutPagingFrame

-- Secure snippet appended to each button's _childupdate-eab-page handler (and
-- reused as the _childupdate-eab-empower handler): after the action attr changes
-- on a page swap, re-evaluate pressAndHoldAction/typerelease for empowered /
-- hold-release spells. IsPressHoldReleaseSpell and GetActionInfo are available
-- in the restricted environment even though they are gone from _G.
-- Stored on ns (not a file local) to stay clear of Lua's 200-local chunk cap.
ns._eabEmpowerSnippet = [[
    local slot = self:GetAttribute('action')
    if slot and IsPressHoldReleaseSpell then
        local actionType, id, subType = GetActionInfo(slot)
        local spellID = nil
        if actionType == 'spell' then
            spellID = id
        elseif actionType == 'macro' and subType == 'spell' then
            spellID = id
        end
        if spellID and IsPressHoldReleaseSpell(spellID) then
            self:SetAttribute('pressAndHoldAction', true)
            self:SetAttribute('typerelease', 'actionrelease')
        else
            self:SetAttribute('pressAndHoldAction', false)
            if self:GetAttribute('typerelease') then
                self:SetAttribute('typerelease', nil)
            end
        end
    end
]]

-- Build the _childupdate-eab-page snippet for a button at the given 1-based bar
-- index. On a page change: action = baseIndex + (page-1)*12, then re-check
-- hold-release. ALL install sites (SetupBar, RebuildBarPaging) call this so the
-- handler is byte-identical everywhere -- the page change rewrites the secure
-- "action" attribute (our buttons are ID=0, so actionpage is never consulted).
function ns._eabBuildPageChildSnippet(baseIndex)
    return ("local page = tonumber(message) or 1; self:SetAttribute('action', %d + (page - 1) * 12)"):format(baseIndex) .. ns._eabEmpowerSnippet
end

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
    -- Bar frames never need to intercept mouse clicks; only buttons do.
    -- Motion is enabled later by the hover system for OnEnter/OnLeave.
    if frame.SetMouseClickEnabled then
        frame:SetMouseClickEnabled(false)
    end
    frame._barKey = key
    frame._barInfo = info

    if key == "MainBar" then
        -- MainBar paging: the state driver evaluates conditions (forms,
        -- vehicle, override, possess, bonus bars, modifiers). The
        -- _onstate-page handler calls ChildUpdate("eab-page", page) which
        -- recalculates each button's explicit action attribute via
        -- _childupdate-eab-page: action = baseIndex + (page-1) * 12.
        local barSettings = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars[key]
        local customPaging = barSettings and barSettings.paging
        local pagingConditions
        if customPaging and next(customPaging) then
            pagingConditions = EAB_VTABLE.BuildPagingConditions("MainBar", customPaging, 1)
        else
            -- No custom paging: use hardcoded class defaults (zero impact)
            pagingConditions = GetClassPagingConditions()
        end

        -- Mark MainBar as the override bar target so the override controller
        -- propagates vehicle/override/petbattle state changes.
        frame:SetAttribute("state-overridebar", true)

        -- Propagate the page state to actionpage on this bar frame. Runs in the
        -- restricted environment so the attribute is untainted. Buttons with
        -- useparent-actionpage=true inherit it via SecureButton_GetModifiedAttribute.
        --
        -- The secure ChildUpdate restores Blizzard's missing second half of the
        -- paging contract for our custom parent frame: each ActionButton gets an
        -- attribute change so its normal OnAttributeChanged -> UpdateAction path
        -- re-evaluates the derived slot even during combat.
        -- CallMethod was removed to prevent taint: during vehicle/override
        -- transitions, the macro conditional system evaluates all registered
        -- state drivers in one pass. CallMethod exits to insecure Lua during
        -- this secure pass, tainting the evaluation context. Blizzard's
        -- ActionBarController state drivers fire in the same pass, inherit
        -- the taint, and OverrideActionBar:Show() gets ADDON_ACTION_BLOCKED.
        -- The page sync is now triggered by ACTIONBAR_PAGE_CHANGED events
        -- instead (see paging frame OnEvent below).
        frame:SetAttributeNoHandler("_onstate-page", [[
            local page = tonumber(newstate) or 1
            self:SetAttribute("actionpage", page)
            self:ChildUpdate("eab-page", page)
        ]])

        RegisterStateDriver(frame, "page", pagingConditions)
    end

    -- Bars 2-8 (nativeActionPage) and Bars 9-10 (customPage): buttons have static
    -- action attributes set in SetupBar that already point at the bar's default
    -- page. When custom paging is configured, a state driver + ChildUpdate
    -- recalculates each button's action attr on page change -- identical machinery
    -- for native and custom bars (the only difference is the default page source).
    local defaultPage = info.nativeActionPage or info.customPage
    if defaultPage then
        frame:Execute(("self:SetAttribute('actionpage', %d)"):format(defaultPage))

        -- Configurable paging: when the user has set up paging conditions
        -- (modifier keys, form swaps), install a state driver on top of the
        -- default page. When no conditions match, the fallback is the bar's
        -- default page (identical to current behavior).
        local barSettings = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars[key]
        local customPaging = barSettings and barSettings.paging
        if customPaging and next(customPaging) then
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

    -- Empower re-check: when addon code sets "eab-empower-trigger", dispatch
    -- ChildUpdate to re-evaluate pressAndHoldAction on all child buttons.
    frame:SetAttributeNoHandler("_onattributechanged", [[
        if name == "eab-empower-trigger" then
            self:ChildUpdate("eab-empower", "")
        end
    ]])

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

    -- Register with the override controller so vehicle/override/petbattle
    -- state changes propagate to this bar frame.
    RegisterBarWithOverrideController(frame)

    -- Register with secure handler so it can reparent buttons to this frame
    SecureSetupHandler_RegisterBarFrame(key, frame)
    _ownedFrames[frame] = true
    return frame
end

-- Rebuild the paging state driver for a bar after settings change.
-- Called from the options panel when the user modifies paging config.
-- Must be called out of combat.
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
        if customPaging and next(customPaging) then
            pagingConditions = EAB_VTABLE.BuildPagingConditions("MainBar", customPaging, 1)
        else
            pagingConditions = GetClassPagingConditions()
        end
        -- Force re-evaluation by unregistering first
        UnregisterStateDriver(frame, "page")
        RegisterStateDriver(frame, "page", pagingConditions)
    elseif info.nativeActionPage or info.customPage then
        local defaultPage = info.nativeActionPage or info.customPage
        if customPaging and next(customPaging) then
            -- Install handler if not already present
            if not frame._eabPagingInstalled then
                frame:SetAttributeNoHandler("_onstate-page", [[
                    local page = tonumber(newstate) or 1
                    self:SetAttribute("actionpage", page)
                    self:ChildUpdate("eab-page", page)
                ]])
                frame._eabPagingInstalled = true
                -- Install button handlers for ChildUpdate. Must set the secure
                -- "action" attr (our buttons are ID=0, so "actionpage" is never
                -- consulted by CalculateAction). Same builder as SetupBar so a
                -- bar that gets paging added live behaves identically to one
                -- configured at login -- no /reload needed.
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
end


-------------------------------------------------------------------------------
--  Bar Setup creates frames and buttons for each bar
-------------------------------------------------------------------------------
local function SetupBar(info, skipProtected)
    -- Shrinks a button's clickable area to better match a custom visual shape,
    -- so clicks land where the shape is (previously the square hit rect made
    -- edge buttons steal clicks from diamond/circle/etc. neighbours). Insets are
    -- a fraction of the button size; "none" resets to the full square. Only ever
    -- called out of combat (SetHitRectInsets on a protected button is unsafe in
    -- combat), gated behind the same not-skipProtected guard as SetParent.
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
    local frame = CreateBarFrame(info)
    local buttons = {}
    local buttonShape = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars[key]
        and EAB.db.profile.bars[key].buttonShape or "none"

    if info.isStance then
        -- Stance bar: reuse StanceButton1-N
        for i = 1, info.count do
            local btn = _G["StanceButton" .. i]
            if btn then
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
        -- Action bars (never stance/pet in this branch): our own EABButtons.
        local slotOffset = BAR_SLOT_OFFSETS[key] or 0
        for i = 1, info.count do
            local slot = slotOffset + i
            local btn = GetOrCreateButton(slot, frame, info, i, skipProtected)
            if btn then
                local bindPrefix = BINDING_MAP[key]
                if not skipProtected then
                    ApplyShapeHitRects(btn, buttonShape)
                    -- All our buttons use explicit action attributes.
                    -- CalculateAction sees the non-zero action attr and
                    -- returns it directly (path 2).
                    btn:SetAttribute("action", slot)
                    if bindPrefix then
                        btn:SetAttributeNoHandler("binding", bindPrefix .. i)
                    end
                    -- Force visual refresh (icon, cooldown swipe, usable state).
                    -- Events are handled by the central dispatcher; per-button
                    -- registration (96 buttons) caused mass OnEvent->UpdateAction
                    -- calls per tick (screen blink).
                    if btn.UpdateAction then btn:UpdateAction() end
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
                -- The bar header's _onattributechanged dispatches ChildUpdate
                -- when addon code sets "eab-empower-trigger" on slot change.
                if not btn:GetAttribute("_childupdate-eab-empower") then
                    btn:SetAttributeNoHandler("_childupdate-eab-empower", ns._eabEmpowerSnippet)
                end
                buttons[i] = btn
                buttonToBar[btn] = { barKey = key, index = i }
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
--  Central Event Dispatcher
--  Registers action bar events on a SINGLE frame and dispatches to all
--  buttons. Avoids the per-button registration that caused 96 separate
--  OnEvent calls per tick (visible as screen-wide black blink).
-------------------------------------------------------------------------------

-- Usable-tint mirror for ForceButtonRefresh, hoisted to a named function so
-- the pcall passes args instead of allocating a closure per call (this runs
-- in the ACTIONBAR_SLOT_CHANGED storm path). On ns: file at the 200-local cap.
ns._TintUsableIcon = function(icon, action)
    local isUsable, noMana
    if C_ActionBar and C_ActionBar.IsUsableAction then
        isUsable, noMana = C_ActionBar.IsUsableAction(action)
    elseif IsUsableAction then
        isUsable, noMana = IsUsableAction(action)
    end
    if isUsable then
        icon:SetVertexColor(1, 1, 1)
    elseif noMana then
        icon:SetVertexColor(0.5, 0.5, 1.0)
    elseif isUsable ~= nil then
        icon:SetVertexColor(0.4, 0.4, 0.4)
    end
end

-- Full per-button visual refresh for slot CONTENT changes (spec swap,
-- drag-drop: slot numbers stay, contents change -- force-less UpdateAction
-- short-circuits on that exact case).
-- NEVER route this through the mixin's UpdateAction/Update from our context,
-- on EITHER client: Update() runs UpdatePressAndHoldAction -> SetAttribute
-- (protected write, ADDON_ACTION_BLOCKED in combat -- exists on 12.0.7 too)
-- and ActionButton_ApplyCooldown with SECRET start/duration (rejected during
-- tainted execution), and its writes to mixin state poison later secure
-- OnShow/driver executions of the same button. Refresh directly with
-- secret-tolerant setters instead: icon (SetTexture accepts secrets), count,
-- and the cooldown swipe via the same duration-object API the dispatcher's
-- ACTIONBAR_UPDATE_COOLDOWN branch uses.
function EAB_VTABLE.ForceButtonRefresh(btn, action)
    if not action then return end
    local icon = btn.icon or btn.Icon
    if icon then
        icon:SetTexture(GetActionTexture(action))
        -- The mixin's Update() HIDES the icon region for empty slots and only
        -- re-Shows it in its filled branch. A slot that was empty before this
        -- content change still has a hidden icon region, so painting the new
        -- texture alone renders nothing (spec swap: spells invisible until a
        -- hover ran Blizzard's secure Update). Gate on HasAction -- a clean
        -- boolean -- never on the texture value, which can be secret.
        icon:SetShown(HasAction(action))
        -- Saturated baseline on every content change: desaturation is
        -- otherwise event/hover-managed and survives the slot being emptied,
        -- so whatever lands next inherited a stale desat until mouseover.
        -- The recompute below re-applies a genuine on-CD desat when the
        -- feature is on.
        if icon.SetDesaturation then
            icon:SetDesaturation(0)
        elseif icon.SetDesaturated then
            icon:SetDesaturated(false)
        end
        -- Usable tint is a separate stale channel (vertex color): a slot
        -- whose item hit zero quantity renders grey, and the grey survives
        -- the content change exactly like the desat did -- usability events
        -- only fire on usability CHANGES, so nothing repaints until hover.
        -- Mirror Blizzard's UpdateUsable coloring (live ActionButton.lua);
        -- pcall-guarded in case the usability booleans are restricted, in
        -- which case the tint is left for the usable-event path.
        pcall(ns._TintUsableIcon, icon, action)
    end
    if btn.Count and C_ActionBar and C_ActionBar.GetActionDisplayCount then
        local display = C_ActionBar.GetActionDisplayCount(action)
        btn.Count:SetText(display or "")
    end
    -- Macro / action text. The mixin's Update() maintains this normally, but
    -- we suppress its per-button events, so a moved macro leaves its name
    -- stuck on the old slot (and the new slot stays blank) until a hover runs
    -- Blizzard's secure Update. Mirror that logic here: set the name only for
    -- slots that use action text, clear it otherwise.
    if btn.Name and C_ActionBar and C_ActionBar.UsesActionText then
        if C_ActionBar.UsesActionText(action) then
            local nm = C_ActionBar.GetActionText and C_ActionBar.GetActionText(action)
            btn.Name:SetText(nm or "")
        else
            btn.Name:SetText("")
        end
    end
    local cd = btn.cooldown
    if cd and C_ActionBar and C_ActionBar.GetActionCooldown then
        local cdInfo = C_ActionBar.GetActionCooldown(action)
        if cdInfo and cdInfo.isActive then
            local dur = C_ActionBar.GetActionCooldownDuration(action)
            if dur and cd.SetCooldownFromDurationObject then
                cd:SetCooldownFromDurationObject(dur)
            end
        else
            cd:Clear()
        end
    end
    -- Desaturation / on-CD alpha are otherwise only recomputed by cooldown
    -- events, and Blizzard's secure Update only runs on hover. A persistent
    -- EABButton keeps its last desaturated state through being emptied, so
    -- content moved onto it rendered desaturated until mouseover. Recompute
    -- from live cooldown data now that the slot's contents changed.
    if EAB._RefreshCooldownVisuals then
        EAB._RefreshCooldownVisuals(btn)
    end
end

do
    local _dispatcherSetup = false
    local _empowerReroutePending = false
    function EAB:SetupEventDispatcher()
        if _dispatcherSetup then return end
        _dispatcherSetup = true
        local dispatcher = CreateFrame("Frame")
        -- Desaturation curves: secret-safe duration -> 0/1 via EvaluateRemainingDuration,
        -- so we never compare secret cooldown/charge numbers ourselves.
        --   desatCurveAny  : 1 for any active cooldown (normal spells; GCD filtered via isOnGCD)
        --   desatCurveReal : 1 only when the cooldown is longer than the GCD. Used for charge
        --                    spells -- a banked charge shows only a GCD-length cooldown on the
        --                    main cooldown so it stays colored; at 0 charges the longer recharge
        --                    drives the main cooldown and it desaturates.
        local desatCurveAny, desatCurveReal
        if C_CurveUtil and C_CurveUtil.CreateCurve then
            desatCurveAny = C_CurveUtil.CreateCurve()
            desatCurveAny:SetType(Enum.LuaCurveType.Step)
            desatCurveAny:AddPoint(0, 0)
            desatCurveAny:AddPoint(0.001, 1)
            desatCurveReal = C_CurveUtil.CreateCurve()
            desatCurveReal:SetType(Enum.LuaCurveType.Step)
            desatCurveReal:AddPoint(0, 0)
            desatCurveReal:AddPoint(1.6, 1)
        end
        -- On-CD alpha curve for charge spells / items: keyed on TOTAL
        -- duration like desatCurveReal (GCD-length cooldown = full alpha,
        -- real cooldown = the user's dim value). Rebuilt only when the
        -- user's alpha setting changes.
        local cdAlphaCurve, cdAlphaCurveFor
        local function GetCdAlphaCurve(cdAlpha)
            if cdAlphaCurveFor ~= cdAlpha and C_CurveUtil and C_CurveUtil.CreateCurve then
                cdAlphaCurve = C_CurveUtil.CreateCurve()
                cdAlphaCurve:SetType(Enum.LuaCurveType.Step)
                cdAlphaCurve:AddPoint(0, 1)
                cdAlphaCurve:AddPoint(1.6, cdAlpha / 100)
                cdAlphaCurveFor = cdAlpha
            end
            return cdAlphaCurve
        end
        -- Desaturation + on-CD alpha for ONE button, from live cooldown data.
        -- Called from the cooldown event loop (data prefetched; false = known
        -- absent) and from each button's OnCooldownDone edge + the infrequent
        -- full-update path (nil = fetched fresh here). Early-outs before any
        -- API call when both features are off.
        -- Why TOTAL duration for charge spells and items: the desat/alpha
        -- writes are static, and the old code evaluated the 1.6s "real
        -- cooldown" step against the REMAINING duration -- correct at
        -- cooldown start, but any cooldown event landing in the final 1.6s
        -- (in combat every cast fires one) read 0 and re-saturated the icon
        -- early. The TOTAL duration never decays, so the classification
        -- holds for the cooldown's entire life; the OnCooldownDone edge then
        -- restores the icon the moment the cooldown actually completes.
        local function RefreshCooldownVisuals(btn, action, cdInfo, durObj, chargeInfo)
            local desatOn = EAB.db.profile.desaturateOnCooldown
            local cdAlpha = EAB.db.profile.alphaWhenOnCD or 100
            local alphaOn = cdAlpha ~= 100
            if not desatOn and not alphaOn then return end
            local icon = btn.icon
            if not icon then return end
            if not action then
                action = btn:GetAttribute("action")
                if not action or not HasAction(action) then return end
            end
            if cdInfo == nil then
                cdInfo = C_ActionBar.GetActionCooldown(action)
                if cdInfo and cdInfo.isActive then
                    durObj = C_ActionBar.GetActionCooldownDuration(action)
                end
            end
            if chargeInfo == nil then
                chargeInfo = C_ActionBar.GetActionCharges(action)
            end
            local useRealCurve = chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1
            if not useRealCurve and GetActionInfo(action) == "item" then
                useRealCurve = true
            end
            local active = cdInfo and cdInfo.isActive and durObj
            if desatOn then
                local val = 0
                if active then
                    if useRealCurve then
                        if durObj.EvaluateTotalDuration and desatCurveReal then
                            val = durObj:EvaluateTotalDuration(desatCurveReal, 0)
                        elseif durObj.EvaluateRemainingDuration and desatCurveReal then
                            -- Client without the total evaluator: remaining is
                            -- start-accurate and the Done edge fixes the tail.
                            val = durObj:EvaluateRemainingDuration(desatCurveReal, 0)
                        end
                    elseif not cdInfo.isOnGCD then
                        if durObj.EvaluateRemainingDuration and desatCurveAny then
                            val = durObj:EvaluateRemainingDuration(desatCurveAny, 0)
                        end
                    end
                end
                -- val may be SECRET: never compare it; SetDesaturation
                -- accepts secret numbers.
                icon:SetDesaturation(val or 0)
            end
            if alphaOn then
                if active then
                    if useRealCurve and durObj.EvaluateTotalDuration then
                        -- Same total-duration classification as desat. Also
                        -- fixes banked-charge spells dimming during the GCD:
                        -- the old IsZero gate had no real-vs-GCD test for the
                        -- charge/item class.
                        local curve = GetCdAlphaCurve(cdAlpha)
                        if curve then
                            icon:SetAlpha(durObj:EvaluateTotalDuration(curve, 1) or 1)
                        else
                            icon:SetAlpha(1)
                        end
                    elseif icon.SetAlphaFromBoolean and durObj.IsZero
                       and (useRealCurve or not cdInfo.isOnGCD) then
                        -- IsZero() is a secret boolean; SetAlphaFromBoolean
                        -- consumes it without any Lua comparison.
                        icon:SetAlphaFromBoolean(durObj:IsZero(), 1, cdAlpha / 100)
                    else
                        icon:SetAlpha(1)
                    end
                else
                    icon:SetAlpha(1)
                end
            end
        end
        -- Exposed for the per-button OnCooldownDone edge hooks (installed at
        -- button creation).
        EAB._RefreshCooldownVisuals = function(btn)
            if btn and btn.GetAttribute then RefreshCooldownVisuals(btn) end
        end
        dispatcher:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        dispatcher:RegisterEvent("ACTIONBAR_UPDATE_STATE")
        dispatcher:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
        dispatcher:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        dispatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        dispatcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        dispatcher:RegisterEvent("SPELL_UPDATE_CHARGES")
        dispatcher:RegisterEvent("SPELL_UPDATE_ICON")
        dispatcher:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
        dispatcher:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
        dispatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
        dispatcher:RegisterEvent("CVAR_UPDATE")  -- "Show numbers for cooldowns" toggled -> re-apply charge recharge numbers
        -- Direct API calls bypass the mixin's OnEvent dispatch, which
        -- triggers UpdateButtonArt (noop + hook), icon bg hook, and other
        -- per-button overhead. With 60 populated buttons, the mixin path
        -- caused visible frame drops on high-frequency events.
        dispatcher:SetScript("OnEvent", function(_, event, arg1)
            -- Assisted shine follows slot contents; coalesced (storm-safe),
            -- and belt-and-braces vs. the OnActionChanged callback -- an
            -- in-combat Update() abort dies before Blizzard's TriggerEvent.
            if event == "ACTIONBAR_SLOT_CHANGED" and ns.QueueAssistRescan then
                ns.QueueAssistRescan()
            end
            for _, info in ipairs(BAR_CONFIG) do
                if not info.isStance and not info.isPetBar then
                    local btns = barButtons[info.key]
                    if btns then
                        if event == "ACTIONBAR_SLOT_CHANGED" then
                            for _, btn in ipairs(btns) do
                                local action = btn:GetAttribute("action")
                                if action and (arg1 == 0 or arg1 == action) then
                                    -- Slot CONTENTS changed while the slot number
                                    -- stayed (spec swap, drag-drop): needs the forced
                                    -- refresh path (see ForceButtonRefresh).
                                    EAB_VTABLE.ForceButtonRefresh(btn, action)
                                    -- Slot emptied: the refresh leaves stale count
                                    -- text behind (buttons no longer receive
                                    -- ACTIONBAR_SLOT_CHANGED themselves).
                                    local filled = HasAction(action)
                                    if btn.Count and not filled then
                                        btn.Count:SetText("")
                                    end
                                    -- Blizzard icon background follows slot
                                    -- contents; same reason as the count text --
                                    -- the per-button OnEvent hook that used to
                                    -- sync it never sees this event now, so a
                                    -- vacated slot kept its background hidden.
                                    -- Raw read (not EFD()): don't allocate
                                    -- per-button state when the option never
                                    -- built a clip.
                                    local bfd = ns._eabFD[btn]
                                    local clip = bfd and bfd.iconBgClip
                                    if clip then
                                        local p2 = EAB.db and EAB.db.profile
                                        clip:SetShown((p2 and p2.showBlizzIconBg or false) and not filled)
                                    end
                                end
                            end
                        elseif event == "ACTIONBAR_UPDATE_COOLDOWN" then
                            -- Use duration object API (12.0+) to avoid secret
                            -- values. Opaque duration objects pass straight to
                            -- the C-side SetCooldownFromDurationObject without
                            -- any Lua comparisons on timing values.
                            for _, btn in ipairs(btns) do
                                local action = btn:GetAttribute("action")
                                if action and HasAction(action) then
                                    local cd = btn.cooldown
                                    local cdInfo, durObj
                                    if cd then
                                        cdInfo = C_ActionBar.GetActionCooldown(action)
                                        if cdInfo and cdInfo.isActive then
                                            durObj = C_ActionBar.GetActionCooldownDuration(action)
                                            if durObj then cd:SetCooldownFromDurationObject(durObj) end
                                        else
                                            cd:Clear()
                                        end
                                    end
                                    -- Charges fetched once here and reused by both the
                                    -- desaturation and charge-cooldown updates below, so the
                                    -- desaturation fix adds no redundant per-button API calls.
                                    local chargeInfo = C_ActionBar.GetActionCharges(action)
                                    -- Desaturate and/or dim on a real cooldown, but NOT on the
                                    -- GCD (and NOT while a charge spell has a charge banked).
                                    -- Full rules + the total-duration rationale live on
                                    -- RefreshCooldownVisuals; `or false` marks known-absent data
                                    -- so the shared function never re-fetches here.
                                    RefreshCooldownVisuals(btn, action, cdInfo or false, durObj, chargeInfo or false)
                                    -- Update count text (charges, item stacks, etc.)
                                    -- C_ActionBar.GetActionDisplayCount handles both
                                    -- charged spells and consumable items correctly.
                                    if btn.Count and C_ActionBar.GetActionDisplayCount then
                                        local display = C_ActionBar.GetActionDisplayCount(action)
                                        btn.Count:SetText(display or "")
                                    end
                                    -- Update charge cooldown (chargeInfo fetched once above)
                                    if chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1 then
                                        local chargeCd = btn.chargeCooldown
                                        if chargeCd then
                                            -- Extend the WoW "Show numbers for cooldowns" setting to
                                            -- recharging charge spells. Blizzard hides the countdown
                                            -- number on the charge (recharge) cooldown unconditionally,
                                            -- so a number normally only shows at 0 charges (the main
                                            -- cooldown). Mirror the "Show numbers for cooldowns" CVar
                                            -- here: un-hide the recharge timer only when the setting is
                                            -- on, hide it when off. Cached per-frame so we only call on a
                                            -- state change; CVAR_UPDATE re-applies it live on toggle.
                                            if chargeCd.SetHideCountdownNumbers then
                                                -- Show recharge numbers only when the feature is on
                                                -- AND Blizzard's cooldown-numbers CVar is on.
                                                local hideNums = (EAB.db.profile.showChargeRechargeNumbers == false)
                                                    or (not GetCVarBool("countdownForCooldowns"))
                                                if EFD(chargeCd).rechargeNumbersHidden ~= hideNums then
                                                    EFD(chargeCd).rechargeNumbersHidden = hideNums
                                                    chargeCd:SetHideCountdownNumbers(hideNums)
                                                end
                                            end
                                            if chargeInfo.isActive then
                                                local chargeDur = C_ActionBar.GetActionChargeDuration(action)
                                                if chargeDur then chargeCd:SetCooldownFromDurationObject(chargeDur) end
                                            else
                                                chargeCd:Clear()
                                            end
                                        end
                                    elseif btn.chargeCooldown then
                                        btn.chargeCooldown:Clear()
                                    end
                                end
                            end
                        elseif event == "CVAR_UPDATE" then
                            -- "Show numbers for cooldowns" toggled: re-apply the recharge-number
                            -- visibility to every charge cooldown immediately (the main cooldown
                            -- numbers update natively; this keeps the recharge timer consistent).
                            -- Cached per chargeCd, so unrelated CVAR_UPDATEs are near-free.
                            local hideNums = (EAB.db.profile.showChargeRechargeNumbers == false)
                                or (not GetCVarBool("countdownForCooldowns"))
                            for _, btn in ipairs(btns) do
                                local chargeCd = btn.chargeCooldown
                                if chargeCd and chargeCd.SetHideCountdownNumbers
                                   and EFD(chargeCd).rechargeNumbersHidden ~= hideNums then
                                    EFD(chargeCd).rechargeNumbersHidden = hideNums
                                    chargeCd:SetHideCountdownNumbers(hideNums)
                                end
                            end
                        elseif event == "ACTIONBAR_UPDATE_USABLE" then
                            for _, btn in ipairs(btns) do
                                -- Skip buttons with active range tint -- the
                                -- range system owns vertex color for those.
                                if not EFD(btn).rangeTinted then
                                local action = btn:GetAttribute("action")
                                if action and HasAction(action) then
                                    local isUsable, notEnoughMana = IsUsableAction(action)
                                    local icon = btn.icon
                                    if icon then
                                        if isUsable then
                                            icon:SetVertexColor(1.0, 1.0, 1.0)
                                        elseif notEnoughMana then
                                            icon:SetVertexColor(0.5, 0.5, 1.0)
                                        else
                                            icon:SetVertexColor(0.4, 0.4, 0.4)
                                        end
                                    end
                                end
                                end
                            end
                        elseif event == "ACTIONBAR_UPDATE_STATE" then
                            for _, btn in ipairs(btns) do
                                local action = btn:GetAttribute("action")
                                if action and HasAction(action) then
                                    btn:SetChecked(IsCurrentAction(action) or IsAutoRepeatAction(action))
                                end
                            end
                        elseif event == "SPELL_UPDATE_ICON" then
                            -- Spell overrides change icon without changing
                            -- the slot. UpdateAction + explicit icon refresh
                            -- since UpdateButtonArt is nooped.
                            for _, btn in ipairs(btns) do
                                local action = btn:GetAttribute("action")
                                if action and HasAction(action) then
                                    if btn.UpdateAction then btn:UpdateAction() end
                                    local tex = GetActionTexture(action)
                                    if tex and btn.icon then
                                        btn.icon:SetTexture(tex)
                                    end
                                end
                            end
                        else
                            -- Infrequent events: full update + usable refresh.
                            -- UpdateAction runs the mixin path but UpdateButtonArt
                            -- is nooped, so desaturation may not update. Explicit
                            -- usable refresh ensures correct visual state after
                            -- form/stance/talent changes.
                            local canSetAttr = not InCombatLockdown()
                            for _, btn in ipairs(btns) do
                                if btn.UpdateAction then btn:UpdateAction() end
                                -- Covers SPELL_UPDATE_CHARGES (previously never
                                -- re-evaluated desat: a regained charge only
                                -- resaturated at the next cooldown event) plus
                                -- form/stance/world entries. Early-outs when
                                -- both features are off. Target changes share
                                -- this branch but cannot change cooldown
                                -- state -- skip them (tab-target spam).
                                if event ~= "PLAYER_TARGET_CHANGED" then
                                    RefreshCooldownVisuals(btn)
                                end
                                if not EFD(btn).rangeTinted then
                                local action = btn:GetAttribute("action")
                                if action and HasAction(action) then
                                    local isUsable, notEnoughMana = IsUsableAction(action)
                                    local icon = btn.icon
                                    if icon then
                                        if isUsable then
                                            icon:SetVertexColor(1.0, 1.0, 1.0)
                                        elseif notEnoughMana then
                                            icon:SetVertexColor(0.5, 0.5, 1.0)
                                        else
                                            icon:SetVertexColor(0.4, 0.4, 0.4)
                                        end
                                    end
                                end
                                end
                            end
                        end
                    end
                end
            end
            -- Re-evaluate keybind routing when any slot changes (spec swap,
            -- spell drag, etc.) so empower slots use click bindings and
            -- non-empower slots use native commands. Debounced because
            -- page swaps fire 12+ ACTIONBAR_SLOT_CHANGED events.
            if event == "ACTIONBAR_SLOT_CHANGED" and not _empowerReroutePending then
                _empowerReroutePending = true
                C_Timer_After(0, function()
                    _empowerReroutePending = false
                    if InCombatLockdown() then return end
                    -- UpdateKeybinds returns false when the routing signature is
                    -- unchanged (mouseover-conditional macro storms re-fire
                    -- ACTIONBAR_SLOT_CHANGED every mouseover flip without changing
                    -- any binding or empower state). Skip the secure empower
                    -- re-trigger in that case: rebuilding bindings and running the
                    -- ChildUpdate snippet on every bar every frame is what tanked
                    -- FPS while hovering across nameplates.
                    if _G._EAB_UpdateKeybinds and _G._EAB_UpdateKeybinds() then
                        for _, info in ipairs(BAR_CONFIG) do
                            local frame = barFrames[info.key]
                            if frame then
                                frame:SetAttribute("eab-empower-trigger", GetTime())
                            end
                        end
                    end
                end)
            end

            -- ExtraActionButton1 is a Blizzard button outside our barButtons.
            -- It relied on ActionBarButtonEventsFrame for cooldown updates,
            -- which we killed. Dispatch cooldown + slot events to it directly.
            if event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "ACTIONBAR_SLOT_CHANGED" then
                local eab1 = ExtraActionButton1
                if eab1 and eab1:IsShown() then
                    if event == "ACTIONBAR_SLOT_CHANGED" then
                        local action = eab1:GetAttribute("action")
                        if action and (arg1 == 0 or arg1 == action) then
                            -- Content changes keep the slot number (see the
                            -- main SLOT_CHANGED branch / ForceButtonRefresh).
                            EAB_VTABLE.ForceButtonRefresh(eab1, action)
                        end
                    else
                        ForceCooldownPaint(eab1)
                    end
                end
            end

            -- Blizzard's own refresh paths reset HotKey's text color: the
            -- infrequent-events else-branch (target change, shapeshift,
            -- charges, vehicle/override) and SPELL_UPDATE_ICON run the mixin
            -- UpdateAction, and slot repaints can do the same from the C
            -- side. Re-assert any custom keybind color with one deferred
            -- color-only pass per burst. The cooldown and check-state
            -- branches never touch text color -- skip those.
            if event ~= "ACTIONBAR_UPDATE_COOLDOWN" and event ~= "ACTIONBAR_UPDATE_STATE" then
                EAB:QueueHotkeyColorReassert()
            end
        end)
    end
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
            -- MainBar: use MainActionBar for Edit Mode settings
            -- and position. Early disposal reparents the bar to
            -- hiddenParent (which is full-screen), so GetCenter
            -- still returns valid screen coordinates.
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
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then return PP.Scale(x) end
    return math.floor(x + 0.5)
end

-- Grow direction for icon layout + fixed-edge resize (on EAB to avoid adding
-- another file-scope local; Lua caps the main chunk at 200 locals).
-- When unlock-anchored to another EAB bar with the same orientation, use the
-- anchor target's *effective* grow (recurse the chain). Otherwise a bar in the
-- middle can inherit from its parent visually while its DB still holds the old
-- grow, and bars anchored to it would read that stale value instead of the chain.
function EAB:ResolveGrowDirectionForLayout(key, s, depth)
    return (s.growDirection or "up"):upper()
end

-- Resolve a bar's icon order setting into abstract order parts.
-- iconOrder supersedes the legacy reverseIconOrder boolean; profiles
-- saved before iconOrder existed have it nil and fall back to the
-- boolean, so existing layouts render unchanged with zero migration.
-- Returns: flowFlip (reverse button flow along the fill axis), plus
-- hAnchor ("LEFT"/"RIGHT") and vAnchor ("TOP"/"BOTTOM") for the corner
-- modes (both nil in the two legacy modes).
-- Wrapped in do-end and reached via ns so no file-scope local slots
-- are consumed (this file is at the Lua 5.1 200-local cap).
do
    local function ResolveIconOrder(s)
        local order = s.iconOrder
        if order == nil then
            order = s.reverseIconOrder and "reversed" or "default"
        end
        if order == "reversed" then
            return true, nil, nil
        elseif order == "TOPLEFT" then
            return false, "LEFT", "TOP"
        elseif order == "TOPRIGHT" then
            return false, "RIGHT", "TOP"
        elseif order == "BOTTOMLEFT" then
            return false, "LEFT", "BOTTOM"
        elseif order == "BOTTOMRIGHT" then
            return false, "RIGHT", "BOTTOM"
        end
        return false, nil, nil
    end

    -- Convert the resolved icon order into concrete index flips for a
    -- bar's button grid. Corner modes place button 1 in that corner of
    -- the existing grid purely by permuting indexes -- the bar frame, its
    -- size and the grid geometry never change. rowsUpward is only
    -- meaningful for horizontal bars.
    -- Third return (cornerFill): true in the four corner modes. On
    -- vertical bars those fill ACROSS the columns first and wrap down to
    -- the next row, matching the classic anchor-point behavior the
    -- corners mirror; Default/Reversed keep the legacy down-each-column
    -- fill. Horizontal bars already fill row-first, so callers ignore
    -- it there.
    function ns.GetOrderFlips(s, isVertical, rowsUpward)
        local flowFlip, hAnchor, vAnchor = ResolveIconOrder(s)
        local colFlip, rowFlip = false, false
        if isVertical then
            rowFlip = flowFlip or (vAnchor == "BOTTOM")
            colFlip = (hAnchor == "RIGHT")
        else
            colFlip = flowFlip or (hAnchor == "RIGHT")
            if vAnchor then
                rowFlip = ((vAnchor == "TOP") == rowsUpward)
            end
        end
        return colFlip, rowFlip, (hAnchor ~= nil)
    end
end

-- Compute layout for a bar and return a table of per-button data.
-- Returns: { [i] = { x, y, w, h, show } }, frameW, frameH
local function ComputeBarLayout(key)
    local info = BAR_LOOKUP[key]
    if not info then return {}, 1, 1 end
    local buttons = barButtons[key]
    if not buttons then return {}, 1, 1 end

    local s = EAB.db.profile.bars[key]
    local numIcons = s.overrideNumIcons or s.numIcons or info.count
    if numIcons < 1 then numIcons = info.count end
    if numIcons > info.count then numIcons = info.count end
    if info.isStance then numIcons = GetNumShapeshiftForms() or info.count end
    if numIcons < 1 then numIcons = 1 end

    local numRows = s.overrideNumRows or s.numRows or 1
    if numRows < 1 then numRows = 1 end
    local stride = ceil(numIcons / numRows)
    numRows = ceil(numIcons / stride)
    -- Raw coord values -- do NOT pre-snap with SnapForScale (PP.Scale
    -- truncates, which loses a pixel at UI scales where PP.mult > 1).
    -- Pixel-lock happens below after shape adjustments.
    local padding = s.buttonPadding or 2
    local isVertical = (s.orientation == "vertical")
    local growDir = EAB:ResolveGrowDirectionForLayout(key, s)
    local shape = s.buttonShape or "none"

    local base = barBaseSize[key]
    local baseW = base and base.w or 45
    local baseH = base and base.h or 45
    local btnW = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth or baseW
    local btnH = (s.buttonHeight and s.buttonHeight > 0) and s.buttonHeight or baseH
    if shape ~= "none" and shape ~= "cropped" then
        btnW = btnW + SHAPE_BTN_EXPAND
        btnH = btnH + SHAPE_BTN_EXPAND
    end
    if shape == "cropped" then btnH = btnH * 0.80 end
    local PPc = EllesmereUI and EllesmereUI.PP
    local onePxC = PPc and PPc.mult or 1
    -- Lock btnW / btnH / padding to exact physical pixel multiples so
    -- positioning (stepW, stepH) and the frame-size math below use the
    -- same pixel grid as the width-match extras (onePxC). Without this,
    -- raw coord values drift sub-pixel as col index grows, shrinking
    -- spacing and making the last button undershoot the match target.
    local btnWPxC    = math.floor(btnW    / onePxC + 0.5)
    local btnHPxC    = math.floor(btnH    / onePxC + 0.5)
    local paddingPxC = math.floor(padding / onePxC + 0.5)
    btnW    = btnWPxC    * onePxC
    btnH    = btnHPxC    * onePxC
    padding = paddingPxC * onePxC
    local stepW = btnW + padding
    local stepH = btnH + padding
    local extraWC = s._matchExtraPixels or 0
    local extraHC = s._matchExtraPixelsH or 0

    local showEmpty = s.alwaysShowButtons
    if showEmpty == nil then showEmpty = true end
    if info.isStance then showEmpty = false end

    -- Icon order flips are constant for the whole grid.
    local rowsUpward = not isVertical and (growDir == "UP" or growDir == "CENTER")
    local colFlip, rowFlip, cornerFill = ns.GetOrderFlips(s, isVertical, rowsUpward)

    local result = {}
    for i = 1, info.count do
        local btn = buttons[i]
        if not btn then break end
        if i > numIcons then
            result[i] = { x = 0, y = 0, w = btnW, h = btnH, show = false }
        else
            local col, row
            if isVertical then
                if cornerFill then
                    -- Corner modes fill across the columns first, then wrap
                    -- down to the next row (numRows = the column count on
                    -- vertical bars).
                    col = (i - 1) % numRows
                    row = floor((i - 1) / numRows)
                else
                    col = floor((i - 1) / stride)
                    row = (i - 1) % stride
                end
            else
                col = (i - 1) % stride
                row = floor((i - 1) / stride)
            end
            -- Icon order flips first so the width/height-match extras
            -- below derive from the final visual position.
            if colFlip then col = (isVertical and numRows or stride) - 1 - col end
            if rowFlip then row = (isVertical and stride or numRows) - 1 - row end
            local thisBtnW = (extraWC > 0 and col < extraWC) and (btnW + onePxC) or btnW
            local thisBtnH = (extraHC > 0 and row < extraHC) and (btnH + onePxC) or btnH
            local extraBeforeW = math.min(col, extraWC) * onePxC
            local extraBeforeH = math.min(row, extraHC) * onePxC
            local xOff = col * stepW + extraBeforeW
            local yOff
            if rowsUpward then
                yOff = row * stepH + extraBeforeH
            else
                yOff = -(row * stepH + extraBeforeH)
            end
            local show = true
            if not showEmpty and not (_gridState.shown or ShouldQuickKeybindSurfaceBar(s)) and not ButtonHasAction(btn, info.blizzBtnPrefix) then
                show = false
            end
            result[i] = { x = xOff, y = yOff, w = thisBtnW, h = thisBtnH, show = show }
        end
    end

    -- Frame size in integer physical pixels, then back to coord. btnW /
    -- btnH / padding are already locked to exact pixel multiples above,
    -- so these multiplies produce exact pixel counts without floating-
    -- point dust or 1px truncation loss.
    local totalCols = isVertical and numRows or stride
    local totalRows = isVertical and stride or numRows
    local frameWPx = totalCols * btnWPxC + (totalCols - 1) * paddingPxC + extraWC
    local frameHPx = totalRows * btnHPxC + (totalRows - 1) * paddingPxC + extraHC
    local frameW = frameWPx * onePxC
    local frameH = frameHPx * onePxC
    return result, max(frameW, 1), max(frameH, 1)
end

local function HideSlotArt(btn)
    if not btn.SlotArt then return end
    if EllesmereUI and EllesmereUI._hiddenParent then
        btn.SlotArt:SetParent(EllesmereUI._hiddenParent)
    else
        btn.SlotArt:Hide()
        btn.SlotArt:SetAlpha(0)
    end
end

-- Declared here (before LayoutBar) so it's in scope as an upvalue.
-- ApplyAll sets this to true during full rebuilds to prevent LayoutBar's
-- edge preservation from saving stale positions into the new profile.
local _isApplyingAll = false

local function LayoutBar(key)
    if InCombatLockdown() then return end
    local info = BAR_LOOKUP[key]
    if not info then return end
    local frame = barFrames[key]
    local buttons = barButtons[key]
    if not frame or not buttons then return end

    local s = EAB.db.profile.bars[key]
    local numIcons = s.overrideNumIcons or s.numIcons or info.count
    if numIcons < 1 then numIcons = info.count end
    if numIcons > info.count then numIcons = info.count end
    if info.isStance then numIcons = GetNumShapeshiftForms() or info.count end
    if numIcons < 1 then numIcons = 1 end

    local numRows = s.overrideNumRows or s.numRows or 1
    if numRows < 1 then numRows = 1 end

    local stride = ceil(numIcons / numRows)
    if stride < 1 then stride = 1 end
    -- Recalculate actual rows needed (avoids empty trailing rows)
    numRows = ceil(numIcons / stride)
    -- Raw coord values -- do NOT pre-snap with SnapForScale (PP.Scale
    -- truncates, which loses a pixel at UI scales where PP.mult > 1).
    -- Pixel-lock happens below after shape adjustments.
    local padding = s.buttonPadding or 2
    local isVertical = (s.orientation == "vertical")
    local growDir = EAB:ResolveGrowDirectionForLayout(key, s)
    local shape = s.buttonShape or "none"

    -- Button size: use explicit width/height if set, otherwise base size.
    local base = barBaseSize[key]
    local baseW = base and base.w or 45
    local baseH = base and base.h or 45
    local btnW = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth or baseW
    local btnH = (s.buttonHeight and s.buttonHeight > 0) and s.buttonHeight or baseH

    -- Shape expansion
    if shape ~= "none" and shape ~= "cropped" then
        btnW = btnW + SHAPE_BTN_EXPAND
        btnH = btnH + SHAPE_BTN_EXPAND
    end
    if shape == "cropped" then
        btnH = btnH * 0.80
    end

    -- Width/height match: distribute extra physical pixels across buttons
    local PP = EllesmereUI and EllesmereUI.PP
    local onePx = PP and PP.mult or 1
    -- Lock btnW / btnH / padding to exact physical pixel multiples so
    -- positioning (stepW) and width-match +1px extras share the same
    -- pixel grid. Prevents sub-pixel drift that shrinks visible spacing
    -- at UI scales with PP.mult > 1.
    local btnWPx    = math.floor(btnW    / onePx + 0.5)
    local btnHPx    = math.floor(btnH    / onePx + 0.5)
    local paddingPx = math.floor(padding / onePx + 0.5)
    btnW    = btnWPx    * onePx
    btnH    = btnHPx    * onePx
    padding = paddingPx * onePx
    local stepW = btnW + padding
    local stepH = btnH + padding

    local extraW = s._matchExtraPixels or 0
    local extraH = s._matchExtraPixelsH or 0

    -- Show empty slots (stance bar always forces this off)
    local showEmpty = s.alwaysShowButtons
    if showEmpty == nil then showEmpty = true end
    if info.isStance then showEmpty = false end

    -- Growth direction affects which edge is fixed during resize.
    -- UP and CENTER on horizontal bars stack rows upward (2nd row
    -- above 1st) matching the original default behavior. Icon order
    -- flips permute indexes within that fixed grid.
    local rowsUpward = not isVertical and (growDir == "UP" or growDir == "CENTER")
    local colFlip, rowFlip, cornerFill = ns.GetOrderFlips(s, isVertical, rowsUpward)

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
                if cornerFill then
                    -- Corner modes fill across the columns first, then wrap
                    -- down to the next row (numRows = the column count on
                    -- vertical bars).
                    col = (i - 1) % numRows
                    row = floor((i - 1) / numRows)
                else
                    col = floor((i - 1) / stride)
                    row = (i - 1) % stride
                end
            else
                col = (i - 1) % stride
                row = floor((i - 1) / stride)
            end

            -- Icon order flips first so the width/height-match extras
            -- below derive from the final visual position.
            if colFlip then col = (isVertical and numRows or stride) - 1 - col end
            if rowFlip then row = (isVertical and stride or numRows) - 1 - row end

            -- Width/height match: first N columns/rows get +1 physical pixel.
            -- Only the matched axis expands -- height stays constant so all
            -- buttons in a row are the same height (no 1px jagged edge).
            local thisBtnW = (extraW > 0 and col < extraW) and (btnW + onePx) or btnW
            local thisBtnH = (extraH > 0 and row < extraH) and (btnH + onePx) or btnH
            -- Cumulative offset from expanded buttons before this one
            local extraBeforeW = math.min(col, extraW) * onePx
            local extraBeforeH = math.min(row, extraH) * onePx

            btn:ClearAllPoints()
            local xOff = col * stepW + extraBeforeW
            local yOff, anchor
            if rowsUpward then
                yOff = row * stepH + extraBeforeH
                anchor = "BOTTOMLEFT"
            else
                yOff = -(row * stepH + extraBeforeH)
                anchor = "TOPLEFT"
            end
            EFD(btn).barKey = key
            if EAB.db.profile.useBlizzardStyle then
                local base = barBaseSize[key]
                local nativeW = base and base.w or 45
                local nativeH = base and base.h or 45
                local sc = thisBtnW / nativeW
                btn:SetScale(sc)
                btn:SetSize(nativeW, nativeH)
                btn:SetPoint(anchor, frame, anchor, xOff / sc, yOff / sc)
            else
                btn:SetPoint(anchor, frame, anchor, xOff, yOff)
                btn:SetSize(thisBtnW, thisBtnH)
            end
            HideSlotArt(btn)

            -- Blizzard style: counter-scale SpellActivationAlert so
            -- the native proc glow renders at screen size despite
            -- the button's SetScale.
            if EAB.db.profile.useBlizzardStyle and btn.SpellActivationAlert then
                local base = barBaseSize[key]
                local nativeW = base and base.w or 45
                local sc = thisBtnW / nativeW
                if sc > 0 then
                    btn.SpellActivationAlert:SetScale(1 / sc)
                end
            end

            -- Resize the autocast overlay to match the button size
            if btn.AutoCastOverlay then
                btn.AutoCastOverlay:SetAllPoints(btn)
            end

            -- Scale TargetReticleAnimFrame proportionally. Blizzard
            -- designed it at 128x128 for the default 45x45 button.
            -- Scaling by btnW/45 keeps the same visual proportions.
            if btn.TargetReticleAnimFrame then
                btn.TargetReticleAnimFrame:SetScale(btnW / 45)
            end

            -- Scale AssistedCombat frames proportionally.
            -- Blizzard creates these lazily at default 45x45 size and
            -- anchors at CENTER. Scale them to match our button size.
            if btn.AssistedCombatHighlightFrame then
                btn.AssistedCombatHighlightFrame:SetScale(btnW / 45)
            end
            if btn.AssistedCombatRotationFrame then
                btn.AssistedCombatRotationFrame:SetScale(btnW / 45)
            end

            -- Pin SpellActivationAlert to button bounds when using custom proc
            -- glows. When custom glows are off or Blizzard style is on, leave
            -- Blizzard's alert completely untouched.
            if btn.SpellActivationAlert and EAB.db.profile.procGlowEnabled and not EAB.db.profile.useBlizzardStyle then
                btn.SpellActivationAlert:SetAllPoints(btn)
                btn.SpellActivationAlert:SetScale(1)
            end

            -- Profession quality diamond overlays (added in Dragonflight):
            -- EAB paints its own rank icon (the quality scan in OnEnable).
            -- Blizzard's overlay is created lazily inside the secure button
            -- Update, which our buttons no longer receive events for, so it
            -- only ever appeared after a mouseover -- and forcing the update
            -- from addon code writes the lazily-created frame onto the
            -- secure button's table (tainted field). Blizzard's overlay
            -- therefore stays permanently hidden so nothing double-draws.
            if btn.ProfessionQualityOverlayFrame then
                btn.ProfessionQualityOverlayFrame:SetShown(false)
                if not EFD(btn).qualityHooked then
                    btn.ProfessionQualityOverlayFrame:HookScript("OnShow", function(self)
                        self:SetShown(false)
                    end)
                    EFD(btn).qualityHooked = true
                end
            end
            if EAB._QueueRankScan then EAB._QueueRankScan() end

            if not showEmpty and not (_gridState.shown or ShouldQuickKeybindSurfaceBar(s)) and not ButtonHasAction(btn, info.blizzBtnPrefix) then
                btn:SetAlpha(0)
            else
                if not s.mouseoverEnabled then
                    btn:SetAlpha(1)
                end
            end
        end
    end

    -- Size the bar frame to encompass all visible buttons (including extra px)
    local totalCols = isVertical and numRows or stride
    local totalRows = isVertical and stride or numRows
    local frameW = totalCols * btnW + (totalCols - 1) * padding + extraW * onePx
    local frameH = totalRows * btnH + (totalRows - 1) * padding + extraH * onePx

    -- Sync frame anchor with barPositions before SetSize so the frame grows
    -- from the correct edge (or center). Skip anchored bars: their position
    -- is owned by the anchor chain, not barPositions.
    local isAnchored = EllesmereUI.IsUnlockAnchored
        and EllesmereUI.IsUnlockAnchored(key)
    if not isAnchored then
        local curPt = ({frame:GetPoint(1)})[1]
        local pos = EAB.db.profile.barPositions and EAB.db.profile.barPositions[key]
        if pos and pos.point and pos.relPoint == "CENTER" and curPt ~= pos.point then
            local PPa = EllesmereUI and EllesmereUI.PP
            local px, py = pos.x or 0, pos.y or 0
            if pos.point == "CENTER" and curPt and curPt ~= "CENTER" then
                -- Switching from edge to CENTER: read live center so the bar
                -- stays at its current visual position. Stored CENTER coords
                -- may be from a different width (stale after resize).
                local fCx, fCy = frame:GetCenter()
                if fCx and fCy then
                    local uiS = UIParent:GetEffectiveScale()
                    local fS = frame:GetEffectiveScale()
                    local ratio = fS / uiS
                    local uiW, uiH = UIParent:GetSize()
                    px = fCx * ratio - uiW / 2
                    py = fCy * ratio - uiH / 2
                end
                if PPa and PPa.SnapCenterForDim then
                    local es = frame:GetEffectiveScale()
                    px = PPa.SnapCenterForDim(px, frame:GetWidth() or 0, es)
                    py = PPa.SnapCenterForDim(py, frame:GetHeight() or 0, es)
                end
            elseif PPa and PPa.SnapForES then
                local es = frame:GetEffectiveScale()
                px = PPa.SnapForES(px, es)
                py = PPa.SnapForES(py, es)
            end
            frame:ClearAllPoints()
            frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px, py)
        end
    end
    -- Pre-resize center in UIParent space, captured BEFORE SetSize (an
    -- edge-pointed frame moves its center when resized). The anchor offset
    -- upkeep below validates against it.
    local preCX, preCY
    do
        local c1, c2 = frame:GetCenter()
        if c1 and c2 then
            local r = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
            preCX, preCY = c1 * r, c2 * r
        end
    end
    EllesmereUI._layoutBarResizing = key
    frame:SetSize(max(frameW, 1), max(frameH, 1))
    EllesmereUI._layoutBarResizing = nil
    -- Anchor offset maintenance: when a growth-direction bar resizes, the
    -- center shifts by delta/2 but the fixed edge stays put. Adjust the
    -- center-based anchor offset so the relationship stays consistent.
    -- Use _eabPrevLayout* to distinguish real resizes from init/reload sizing.
    do
        local newW = max(frameW, 1)
        local newH = max(frameH, 1)
        local prevW = frame._eabPrevLayoutW
        local prevH = frame._eabPrevLayoutH
        frame._eabPrevLayoutW = newW
        frame._eabPrevLayoutH = newH
        -- Self-validating gate: the dw/2 compensation is only correct when the
        -- bar's PRE-resize center actually sat at the anchor-derived position
        -- (target center + stored offset on the compensated axis). During a
        -- profile apply the bar still holds the OUTGOING profile's position
        -- while unlockAnchors already carries the INCOMING profile's offsets;
        -- compensating that mismatch corrupts the offsets cumulatively on every
        -- swap. Layout passes can land before, inside, or after the
        -- _abAnchorSuppressed window (e.g. extra bars built on a timer), so the
        -- position check is the only ordering-proof guard.
        if (prevW or prevH)
           and not EllesmereUI._unlockActive
           and not EllesmereUI._abAnchorSuppressed
           and not _isApplyingAll then
            local s = EAB.db.profile.bars[key]
            local grow = s and s.growDirection
            if grow then
                grow = grow:upper()
                if grow ~= "CENTER" then
                    local adb = EllesmereUIDB and EllesmereUIDB.unlockAnchors
                    local ai = adb and adb[key]
                    if ai then
                        local side = ai.side
                        local PPo = EllesmereUI and EllesmereUI.PP
                        local uiES = PPo and UIParent:GetEffectiveScale()
                        local tCX, tCY
                        if EllesmereUI.GetAnchorTargetCenterUI then
                            tCX, tCY = EllesmereUI.GetAnchorTargetCenterUI(key)
                        end
                        local TOL = 2  -- UI px; pixel-snap noise stays well under 1
                        -- Width/height-matched bars: the match owns that axis;
                        -- any resize there is the match asserting the target's
                        -- size, which the saved offset already corresponds to.
                        -- Compensating would corrupt the offset (see the CDM
                        -- twin of this block).
                        local wMatched = EllesmereUIDB and EllesmereUIDB.unlockWidthMatch and EllesmereUIDB.unlockWidthMatch[key]
                        local hMatched = EllesmereUIDB and EllesmereUIDB.unlockHeightMatch and EllesmereUIDB.unlockHeightMatch[key]
                        -- Horizontal growth (LEFT/RIGHT): adjust offsetX on TOP/BOTTOM anchors
                        if prevW and math.abs(newW - prevW) > 0.1
                           and (side == "TOP" or side == "BOTTOM")
                           and not wMatched
                           and preCX and tCX
                           and math.abs(preCX - (tCX + (ai.offsetX or 0))) <= TOL then
                            local dw = newW - prevW
                            if grow == "RIGHT" then
                                ai.offsetX = ai.offsetX + dw / 2
                            elseif grow == "LEFT" then
                                ai.offsetX = ai.offsetX - dw / 2
                            end
                            if PPo and uiES then ai.offsetX = PPo.SnapForES(ai.offsetX, uiES) end
                        end
                        -- Vertical growth (UP/DOWN): adjust offsetY on LEFT/RIGHT anchors
                        if prevH and math.abs(newH - prevH) > 0.1
                           and (side == "LEFT" or side == "RIGHT")
                           and not hMatched
                           and preCY and tCY
                           and math.abs(preCY - (tCY + (ai.offsetY or 0))) <= TOL then
                            local dh = newH - prevH
                            if grow == "DOWN" then
                                ai.offsetY = ai.offsetY - dh / 2
                            elseif grow == "UP" then
                                ai.offsetY = ai.offsetY + dh / 2
                            end
                            if PPo and uiES then ai.offsetY = PPo.SnapForES(ai.offsetY, uiES) end
                        end
                    end
                end
            end
        end
    end

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
        if btn then
            -- Ensure the button has GetPopupDirection for Blizzard's SpellFlyout system
            -- (must be available on all buttons, regardless of squareIcons setting)
            if not btn.GetPopupDirection then
                btn.GetPopupDirection = function(self)
                    return self:GetAttribute("flyoutDirection") or "UP"
                end
            end
            if not InCombatLockdown() then
                btn:SetAttribute("flyoutDirection", flyDir)
            end
        end
    end

    -- Notify the position system for width/height match propagation and
    -- anchor chains. For anchored bars with growth direction, skip the
    -- explicit notify/propagate (which would queue a deferred
    -- ApplyAnchorPosition that overrides edge positioning). The
    -- OnSizeChanged hook handles propagation to dependents automatically.
    local skipNotify = EllesmereUI.IsUnlockAnchored
        and EllesmereUI.IsUnlockAnchored(key)
        and growDir ~= "CENTER" and growDir ~= "UP"
    if not skipNotify then
        if EllesmereUI.NotifyElementResized then
            EllesmereUI.NotifyElementResized(key)
        end
        if EllesmereUI.PropagateAnchorChain then
            EllesmereUI.PropagateAnchorChain(key)
        end
    end

    -- Position paging arrows after MainBar layout
    if key == "MainBar" then
        if not _pagingFrame then SetupPagingFrame() end
        LayoutPagingFrame()
        -- Set up secure paging keybind overrides (once, out of combat).
        -- Redirects NEXTACTIONPAGE / PREVIOUSACTIONPAGE to hidden secure
        -- buttons so page cycling works in combat without taint.
        if _pagingFrame and not _pagingFrame._pageBindsSet and not InCombatLockdown() then
            _pagingFrame._pageBindsSet = true
            local nextBtn = CreateFrame("Button", "EABPageNext", UIParent, "SecureActionButtonTemplate")
            nextBtn:SetSize(1, 1)
            nextBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 200)
            nextBtn:SetAlpha(0)
            nextBtn:RegisterForClicks("AnyUp", "AnyDown")
            WireSecurePagingButton(nextBtn, 1)

            local prevBtn = CreateFrame("Button", "EABPagePrev", UIParent, "SecureActionButtonTemplate")
            prevBtn:SetSize(1, 1)
            prevBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -200, 200)
            prevBtn:SetAlpha(0)
            prevBtn:RegisterForClicks("AnyUp", "AnyDown")
            WireSecurePagingButton(prevBtn, -1)

            local function ApplyPageBindings()
                if InCombatLockdown() then return end
                ClearOverrideBindings(_pagingFrame)
                local nextKeys = { GetBindingKey("NEXTACTIONPAGE") }
                local prevKeys = { GetBindingKey("PREVIOUSACTIONPAGE") }
                for _, k in ipairs(nextKeys) do
                    SetOverrideBindingClick(_pagingFrame, true, k, "EABPageNext")
                end
                for _, k in ipairs(prevKeys) do
                    SetOverrideBindingClick(_pagingFrame, true, k, "EABPagePrev")
                end
            end
            ApplyPageBindings()
            -- Re-apply if user changes keybinds
            _pagingFrame:RegisterEvent("UPDATE_BINDINGS")
            local origOnEvent = _pagingFrame:GetScript("OnEvent")
            _pagingFrame:SetScript("OnEvent", function(self, event, ...)
                if event == "UPDATE_BINDINGS" then
                    if not InCombatLockdown() then ApplyPageBindings() end
                    return
                end
                if origOnEvent then origOnEvent(self, event, ...) end
            end)
        end
    end
end

-------------------------------------------------------------------------------
--  Visual Customization Button Appearance
-------------------------------------------------------------------------------
local function HideSelfDeferred(self)
    -- Reuse a cached closure per frame to avoid allocation on every OnShow
    local fd = EFD(self)
    if not fd.hideFn then
        fd.hideFn = function()
            if self and not self:IsForbidden() then self:Hide() end
        end
    end
    C_Timer_After(0, fd.hideFn)
end

local function HideBorder(button)
    if button.NormalTexture then
        button.NormalTexture:Hide()
        button.NormalTexture:SetAlpha(0)
    end
    if button.Border then
        button.Border:Hide()
        button.Border:SetAlpha(0)
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

_quickKeybindState.art.ApplyButtonHighlight = function(btn)
    local tex = btn and btn.QuickKeybindHighlightTexture
    if not tex then return end

    local p = EAB and EAB.db and EAB.db.profile
    local useCC = p and p.highlightUseClassColor
    local customC = (p and p.highlightCustomColor) or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
    local cr, cg, cb = customC.r, customC.g, customC.b
    if useCC then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then
                cr, cg, cb = cc.r, cc.g, cc.b
            end
        end
    end

    -- QuickKeybind manages hover/idle opacity itself. We only replace the
    -- Blizzard atlas with EUI's square highlight art and matching color.
    SetSquareTexture(tex, HIGHLIGHT_TEXTURES[1])
    tex:SetVertexColor(cr, cg, cb, 1)
end

_quickKeybindState.art.RefreshButton = function(btn, show)
    if not btn or btn:IsForbidden() then return end
    _quickKeybindState.art.ApplyButtonHighlight(btn)
    if show ~= nil then
        _quickKeybindState.art.ApplyButtonHighlightAlpha(btn, show)
    end
end

_quickKeybindState.art.InitializeButton = function(btn, show)
    _quickKeybindState.art.RefreshButton(btn, show)
    _quickKeybindState.art.HookButton(btn)
end

_quickKeybindState.art.HookButton = function(btn)
    if not btn or btn:IsForbidden() or EFD(btn).quickKeybindArtHooked then return end
    if btn.QuickKeybindHighlightTexture and btn.DoModeChange then
        hooksecurefunc(btn, "DoModeChange", function(self, isInQuickbindMode)
            _quickKeybindState.art.RefreshButton(self, isInQuickbindMode)
        end)
        EFD(btn).quickKeybindArtHooked = true
    end
end

_quickKeybindState.art.ApplyButtonHighlightAlpha = function(btn, show)
    local tex = btn and btn.QuickKeybindHighlightTexture
    if not tex then return end

    if show then
        local idleAlpha = 0.5
        if btn.IsMouseOver and btn:IsMouseOver() then
            tex:SetAlpha(1)
        else
            tex:SetAlpha(idleAlpha)
        end
    else
        tex:SetAlpha(1)
    end
end

_quickKeybindState.art.ForEachSpecialButton = function(fn)
    if not fn then return end
    if ExtraActionButton1 then
        fn(ExtraActionButton1)
    end
end

_quickKeybindState.ReassertButtonsAfterCombatChange = function()
    if not _quickKeybindState.open then return end
    C_Timer_After(0, function()
        if _quickKeybindState.open and EAB_UpdateQuickKeybindButtons then
            EAB_UpdateQuickKeybindButtons(true)
        end
    end)
end

local function HideTexture(texture)
    if not texture then return end
    texture:SetAlpha(0)
end

function EAB_VTABLE.HideRegionDeferred(region, resetAlpha)
    if not region then return end
    local fd = EFD(region)
    if not fd.hideFn then
        fd.hideFn = function()
            if region and not region:IsForbidden() then
                region:Hide()
                if resetAlpha then
                    region:SetAlpha(resetAlpha)
                end
            end
        end
    end
    C_Timer_After(0, fd.hideFn)
end

local function MakeButtonSquare(btn)
    if EFD(btn).squared then return end
    -- Always hide SlotBackground regardless of style (our own icon
    -- background toggle controls slot backgrounds for all bars).
    HideSlotArt(btn)
    -- Skip the rest of Blizzard texture stripping for Blizzard style
    local _p = EAB.db and EAB.db.profile
    if _p and _p.useBlizzardStyle then return end
    HideBorder(btn)
    -- Ensure the button has GetPopupDirection for Blizzard's SpellFlyout system.
    -- ActionBarButtonTemplate may not always inherit this from FlyoutButtonMixin.
    if not btn.GetPopupDirection then
        btn.GetPopupDirection = function(self)
            return self:GetAttribute("flyoutDirection") or "UP"
        end
    end
    local fd = EFD(btn)
    if btn.NormalTexture and not fd.ntHooked then
        btn.NormalTexture:HookScript("OnShow", HideSelfDeferred)
        fd.ntHooked = true
    end
    if not fd.showHooked then
        -- Cache the deferred closure per button to avoid allocation on every OnShow
        local hideBorderFn = function()
            if btn and not btn:IsForbidden() then HideBorder(btn) end
        end
        btn:HookScript("OnShow", function() C_Timer_After(0, hideBorderFn) end)
        fd.showHooked = true
    end
    -- Hook UpdateButtonArt to re-neutralize IconMask after Blizzard re-adds it
    -- (fires on combat transitions, bar page changes, bonus bar swaps, etc.)
    -- Deferred via C_Timer to avoid tainting Blizzard's secure call chains.
    if not fd.artHooked and btn.UpdateButtonArt then
        hooksecurefunc(btn, "UpdateButtonArt", function(self)
            local sfd = EFD(self)
            -- Coalesce: UpdateAction storms (mouseover-conditional macros) call
            -- this many times per frame; one deferred HideBorder covers them all.
            if sfd.artPending then return end
            sfd.artPending = true
            if not sfd.artFn then
                sfd.artFn = function()
                    sfd.artPending = nil
                    if self and not self:IsForbidden() then
                        HideBorder(self)
                    end
                end
            end
            C_Timer_After(0, sfd.artFn)
        end)
        fd.artHooked = true
    end
    -- Hook UpdateAssistedCombatRotationFrame to scale the rotation frame
    -- when Blizzard creates it lazily (default 45x45, needs our button size).
    if not fd.rotHooked and btn.UpdateAssistedCombatRotationFrame then
        hooksecurefunc(btn, "UpdateAssistedCombatRotationFrame", function(self)
            if self.AssistedCombatRotationFrame and EFD(self).squared then
                local w = self:GetWidth() or 45
                self.AssistedCombatRotationFrame:SetScale(w / 45)
            end
        end)
        fd.rotHooked = true
    end
    SetSquareTexture(btn.HighlightTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(btn.NewActionTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(btn.PushedTexture, HIGHLIGHT_TEXTURES[2])
    SetSquareTexture(btn.Flash, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(btn.CheckedTexture, HIGHLIGHT_TEXTURES[1])
    SetSquareTexture(btn.Border, HIGHLIGHT_TEXTURES[1])
    _quickKeybindState.art.InitializeButton(btn)
    HideTexture(btn.FlyoutBorderShadow)
    if btn.BorderShadow then
        if EllesmereUI and EllesmereUI._hiddenParent then
            btn.BorderShadow:SetParent(EllesmereUI._hiddenParent)
        else
            HideTexture(btn.BorderShadow)
        end
    end
    if btn.cooldown then
        btn.cooldown:ClearAllPoints()
        btn.cooldown:SetAllPoints(btn)
    end
    -- Cast-anim suppression (SpellCastAnimFrame + InterruptDisplay): hide the
    -- ANIMATED frame synchronously. Its animation group re-drives the frame
    -- alpha on the next render tick, so SetAlpha(0) plus a one-frame-deferred
    -- Hide leaks a one-frame "blink" of the cast sweep; a hidden frame renders
    -- no animations. The deferred Hide stays as a fallback reset. Runs in the
    -- insecure UNIT_SPELLCAST/OnShow context and is IsForbidden-guarded.
    if (btn.SpellCastAnimFrame and not fd.castHooked)
       or (btn.InterruptDisplay and not fd.intHooked) then
        local hideCastAnim = function(self)
            local prof = EAB.db and EAB.db.profile
            if not prof then return end
            local bfd = EFD(btn)
            if not prof.hideCastingAnimations and not bfd.shapeApplied and not bfd.cropped then return end
            self:SetAlpha(0)
            if not self:IsForbidden() then self:Hide() end
            EAB_VTABLE.HideRegionDeferred(self, 1)
        end
        if btn.SpellCastAnimFrame and not fd.castHooked then
            btn.SpellCastAnimFrame:HookScript("OnShow", hideCastAnim)
            fd.castHooked = true
        end
        if btn.InterruptDisplay and not fd.intHooked then
            btn.InterruptDisplay:HookScript("OnShow", hideCastAnim)
            fd.intHooked = true
        end
    end
    if btn.SlotBackground then
        btn.SlotBackground:SetAlpha(0)
        if not fd.slotBgHooked then
            fd.slotBgHooked = true
            hooksecurefunc(btn.SlotBackground, "SetAlpha", function(self, a)
                if a ~= 0 then self:SetAlpha(0) end
            end)
        end
    end
    if not fd.slotBG then
        local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
        bg:SetAllPoints(btn)
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
        fd.slotBG = bg
    end
    if btn.SlotArt then
        btn.SlotArt:SetAlpha(0)
        if not fd.slotArtHooked then
            fd.slotArtHooked = true
            hooksecurefunc(btn.SlotArt, "SetAlpha", function(self, a)
                if a ~= 0 then self:SetAlpha(0) end
            end)
        end
    end
    -- Hook Border to suppress Blizzard's item quality overlay (Dragonflight+).
    -- Blizzard calls Border:SetAtlas()/Show() on various refreshes. EAB owns
    -- the visible border entirely, so the Blizzard overlay must stay hidden.
    if btn.Border and not fd.borderHooked then
        hooksecurefunc(btn.Border, "SetAtlas", function(self)
            self:SetAlpha(0)
            EAB_VTABLE.HideRegionDeferred(self)
        end)
        hooksecurefunc(btn.Border, "Show", function(self)
            self:SetAlpha(0)
            EAB_VTABLE.HideRegionDeferred(self)
        end)
        fd.borderHooked = true
    end
    fd.squared = true
end

local function EnsureBorders(btn)
    local fd = EFD(btn)
    if fd.borders then return fd.borders end
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then
        PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 2)
        fd.borders = PP.GetBorders(btn)
        -- Reparent the flyout arrow INTO the border frame and lift it above the
        -- border strips. The strips sit at OVERLAY sublevel 2 (the PP.CreateBorder
        -- call above); sharing the frame isn't enough -- without a higher sublevel
        -- the arrow still draws underneath them.
        if btn.Arrow then
            btn.Arrow:SetParent(fd.borders)
            if btn.Arrow.SetDrawLayer then
                btn.Arrow:SetDrawLayer("OVERLAY", 7)
            elseif btn.Arrow.SetFrameLevel then
                btn.Arrow:SetFrameLevel(fd.borders:GetFrameLevel() + 1)
            end
        end
    end
    return fd.borders
end

local function ApplyButtonBorders(btn, on, cr, cg, cb, ca, sz, zoom, textureKey, texOffset, texOffsetY, shiftX, shiftY, addonKey, sizeKey, behind)
    MakeButtonSquare(btn)
    local PP = EllesmereUI and EllesmereUI.PP
    local fd = EFD(btn)
    if not on then
        if fd.borders then
            PP.HideBorder(btn)
        end
        -- Also hide textured border if present
        if EllesmereUI._bdBorderData then
            local bdFrame = EllesmereUI._bdBorderData[btn]
            if bdFrame then bdFrame:Hide() end
        end
        fd.borderKey = nil
    else
        local texKey = textureKey or "solid"
        if texKey ~= "solid" then
            -- Textured borders: always apply (cheap SetBackdropBorderColor call)
            fd.borderKey = nil
        else
            -- Solid borders: cache to avoid redundant PP updates
            local es = btn:GetEffectiveScale()
            local stateKey = cr * 1000000 + cg * 10000 + cb * 100 + ca + sz * 0.001 + zoom * 10000000 + es * 0.0001
            if fd.borderKey == stateKey and fd.borderTexKey == texKey then return end
            fd.borderKey = stateKey
        end
        fd.borderTexKey = texKey
        if texKey == "solid" then
            EnsureBorders(btn)
        elseif fd.borders then
            -- Switching from solid to textured: hide existing PP borders
            PP.HideBorder(btn)
            local ppC = PP.GetBorders(btn)
            if ppC then
                if ppC._top then ppC._top:SetAlpha(0) end
                if ppC._bottom then ppC._bottom:SetAlpha(0) end
                if ppC._left then ppC._left:SetAlpha(0) end
                if ppC._right then ppC._right:SetAlpha(0) end
            end
        end
        EllesmereUI.ApplyBorderStyle(btn, sz, cr, cg, cb, ca, textureKey, texOffset, texOffsetY, shiftX, shiftY, addonKey, sizeKey)
        -- "Show Behind": textured border frame is a child of btn; equal level draws
        -- in front of the icon, level-1 draws behind it. Solid borders unaffected.
        if texKey ~= "solid" and EllesmereUI._bdBorderData then
            local bdFrame = EllesmereUI._bdBorderData[btn]
            if bdFrame then
                local lvl = btn:GetFrameLevel()
                bdFrame:SetFrameLevel(behind and math.max(0, lvl - 1) or lvl)
            end
        end
        if fd.borders and fd.shapeMask and fd.shapeMask:IsShown() then
            PP.HideBorder(btn)
            if EllesmereUI._bdBorderData then
                local bdFrame = EllesmereUI._bdBorderData[btn]
                if bdFrame then bdFrame:Hide() end
            end
        end
    end
    if zoom > 0 then
        local icon = btn.icon or btn.Icon
        if icon and icon.SetTexCoord and not (fd.shapeMask and fd.shapeMask:IsShown()) and not fd.cropped then
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
    _quickKeybindState.art.RefreshButton(btn)
    local fd = EFD(btn)

    if shape == "none" or shape == "cropped" then
        -- Remove shape mask if previously applied
        if fd.shapeMask then
            local mask = fd.shapeMask
            local icon = btn.icon or btn.Icon
            if icon then pcall(icon.RemoveMaskTexture, icon, mask) end
            -- Unmask slot BG and icon BG from main mask
            if fd.slotBG then pcall(fd.slotBG.RemoveMaskTexture, fd.slotBG, mask) end
            if fd.iconBg then pcall(fd.iconBg.RemoveMaskTexture, fd.iconBg, mask) end
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
        if fd.overlayMask then
            local omask = fd.overlayMask
            if btn.HighlightTexture then pcall(btn.HighlightTexture.RemoveMaskTexture, btn.HighlightTexture, omask) end
            if btn.PushedTexture then pcall(btn.PushedTexture.RemoveMaskTexture, btn.PushedTexture, omask) end
            if btn.CheckedTexture then pcall(btn.CheckedTexture.RemoveMaskTexture, btn.CheckedTexture, omask) end
            if btn.NewActionTexture then pcall(btn.NewActionTexture.RemoveMaskTexture, btn.NewActionTexture, omask) end
            if btn.Flash then pcall(btn.Flash.RemoveMaskTexture, btn.Flash, omask) end
            if btn.QuickKeybindHighlightTexture then pcall(btn.QuickKeybindHighlightTexture.RemoveMaskTexture, btn.QuickKeybindHighlightTexture, omask) end
            if btn.Border then pcall(btn.Border.RemoveMaskTexture, btn.Border, omask) end
            local nt = btn.NormalTexture or btn:GetNormalTexture()
            if nt then pcall(nt.RemoveMaskTexture, nt, omask) end
            if btn.SpellActivationAlert then
                UnmaskFrameTextures(btn.SpellActivationAlert, omask)
                EFD(btn.SpellActivationAlert).shapeMasked = nil
            end
            omask:SetTexture(nil)
            omask:ClearAllPoints()
            omask:SetSize(0.001, 0.001)
            omask:Hide()
        elseif fd.shapeMask then
            -- Overlays were on the main mask (no border case) clean them off
            local mask = fd.shapeMask
            if btn.HighlightTexture then pcall(btn.HighlightTexture.RemoveMaskTexture, btn.HighlightTexture, mask) end
            if btn.PushedTexture then pcall(btn.PushedTexture.RemoveMaskTexture, btn.PushedTexture, mask) end
            if btn.CheckedTexture then pcall(btn.CheckedTexture.RemoveMaskTexture, btn.CheckedTexture, mask) end
            if btn.NewActionTexture then pcall(btn.NewActionTexture.RemoveMaskTexture, btn.NewActionTexture, mask) end
            if btn.Flash then pcall(btn.Flash.RemoveMaskTexture, btn.Flash, mask) end
            if btn.QuickKeybindHighlightTexture then pcall(btn.QuickKeybindHighlightTexture.RemoveMaskTexture, btn.QuickKeybindHighlightTexture, mask) end
            if btn.Border then pcall(btn.Border.RemoveMaskTexture, btn.Border, mask) end
            local nt = btn.NormalTexture or btn:GetNormalTexture()
            if nt then pcall(nt.RemoveMaskTexture, nt, mask) end
            if btn.SpellActivationAlert then
                UnmaskFrameTextures(btn.SpellActivationAlert, mask)
                EFD(btn.SpellActivationAlert).shapeMasked = nil
            end
        end
        -- Clean up glow wrapper mask
        if fd.glowWrapper then
            local mask = fd.shapeMask
            if mask then UnmaskFrameTextures(fd.glowWrapper, mask) end
            local wfd = EFD(fd.glowWrapper)
            if wfd.ownMask then
                UnmaskFrameTextures(fd.glowWrapper, wfd.ownMask)
                wfd.ownMask:Hide()
            end
        end
        if fd.shapeBorder then
            fd.shapeBorder:Hide()
            EFD(fd.shapeBorder).wantsShow = false
            fd.shapeBorder:SetTexture(nil)
        end
        -- Clear shape tracking flags
        fd.shapeApplied = nil
        fd.shapeName = nil
        fd.shapeMaskPath = nil
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
                fd.cropped = true
            else
                fd.cropped = false
                if zoom and zoom > 0 then
                    icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                else
                    icon:SetTexCoord(0, 1, 0, 1)
                end
            end
        end
        -- Show square borders only if border is enabled
        if fd.borders and brdOn then
            -- Re-apply border style to restore correct type (PP or textured)
            local barKey = fd.barKey
            local texKey = barKey and EAB.db and EAB.db.profile.bars[barKey] and EAB.db.profile.bars[barKey].borderTexture or "solid"
            if texKey ~= "solid" then
                local s = EAB.db.profile.bars[barKey]
                local c = s and s.borderColor or { r=0, g=0, b=0, a=1 }
                local sz = ResolveBorderThickness(s)
                local thKey = s.borderThickness or "thin"
                EllesmereUI.ApplyBorderStyle(btn, sz, c.r, c.g, c.b, c.a or 1, texKey, s.borderTextureOffset, s.borderTextureOffsetY, s.borderTextureShiftX, s.borderTextureShiftY, "actionbars", thKey)
                if EllesmereUI._bdBorderData then
                    local bdFrame = EllesmereUI._bdBorderData[btn]
                    if bdFrame then
                        local lvl = btn:GetFrameLevel()
                        bdFrame:SetFrameLevel(s.borderBehind and math.max(0, lvl - 1) or lvl)
                    end
                end
            else
                PP.ShowBorder(btn)
            end
        elseif fd.borders then
            PP.HideBorder(btn)
            if EllesmereUI._bdBorderData then
                local bdFrame = EllesmereUI._bdBorderData[btn]
                if bdFrame then bdFrame:Hide() end
            end
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

    if not fd.shapeMask then
        fd.shapeMask = btn:CreateMaskTexture()
    end
    local mask = fd.shapeMask
    mask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:Show()

    local icon = btn.icon or btn.Icon

    -- Always remove existing mask references before re-adding
    -- (AddMaskTexture is additive; stale references cause shape-inside-shape)
    if icon then pcall(icon.RemoveMaskTexture, icon, mask) end
    if fd.slotBG then pcall(fd.slotBG.RemoveMaskTexture, fd.slotBG, mask) end
    if fd.iconBg then pcall(fd.iconBg.RemoveMaskTexture, fd.iconBg, mask) end
    if btn.cooldown and not btn.cooldown:IsForbidden() then
        pcall(btn.cooldown.RemoveMaskTexture, btn.cooldown, mask)
    end
    if btn.chargeCooldown and not btn.chargeCooldown:IsForbidden() then
        pcall(btn.chargeCooldown.RemoveMaskTexture, btn.chargeCooldown, mask)
    end
    do
        -- Remove overlay textures from whichever mask they were on
        local omask = fd.overlayMask or mask
        if btn.HighlightTexture then pcall(btn.HighlightTexture.RemoveMaskTexture, btn.HighlightTexture, omask) end
        if btn.PushedTexture then pcall(btn.PushedTexture.RemoveMaskTexture, btn.PushedTexture, omask) end
        if btn.CheckedTexture then pcall(btn.CheckedTexture.RemoveMaskTexture, btn.CheckedTexture, omask) end
        if btn.NewActionTexture then pcall(btn.NewActionTexture.RemoveMaskTexture, btn.NewActionTexture, omask) end
        if btn.Flash then pcall(btn.Flash.RemoveMaskTexture, btn.Flash, omask) end
        if btn.QuickKeybindHighlightTexture then pcall(btn.QuickKeybindHighlightTexture.RemoveMaskTexture, btn.QuickKeybindHighlightTexture, omask) end
        if btn.Border then pcall(btn.Border.RemoveMaskTexture, btn.Border, omask) end
        local nt2 = btn.NormalTexture or btn:GetNormalTexture()
        if nt2 then pcall(nt2.RemoveMaskTexture, nt2, omask) end
        if btn.SpellActivationAlert then
            UnmaskFrameTextures(btn.SpellActivationAlert, omask)
            EFD(btn.SpellActivationAlert).shapeMasked = nil
        end
        -- Also clean from main mask if overlay mask was separate
        if fd.overlayMask and fd.overlayMask ~= mask then
            if btn.HighlightTexture then pcall(btn.HighlightTexture.RemoveMaskTexture, btn.HighlightTexture, mask) end
            if btn.PushedTexture then pcall(btn.PushedTexture.RemoveMaskTexture, btn.PushedTexture, mask) end
            if btn.CheckedTexture then pcall(btn.CheckedTexture.RemoveMaskTexture, btn.CheckedTexture, mask) end
            if btn.NewActionTexture then pcall(btn.NewActionTexture.RemoveMaskTexture, btn.NewActionTexture, mask) end
            if btn.Flash then pcall(btn.Flash.RemoveMaskTexture, btn.Flash, mask) end
            if btn.QuickKeybindHighlightTexture then pcall(btn.QuickKeybindHighlightTexture.RemoveMaskTexture, btn.QuickKeybindHighlightTexture, mask) end
            if btn.Border then pcall(btn.Border.RemoveMaskTexture, btn.Border, mask) end
            if nt2 then pcall(nt2.RemoveMaskTexture, nt2, mask) end
        end
        if fd.glowWrapper then
            UnmaskFrameTextures(fd.glowWrapper, mask)
            local wfd = EFD(fd.glowWrapper)
            if wfd.ownMask then
                UnmaskFrameTextures(fd.glowWrapper, wfd.ownMask)
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
        if not fd.overlayMask then
            fd.overlayMask = btn:CreateMaskTexture()
        end
        overlayMask = fd.overlayMask
        overlayMask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        overlayMask:ClearAllPoints()
        local inset = 3
        PP.Point(overlayMask, "TOPLEFT", btn, "TOPLEFT", inset, -inset)
        PP.Point(overlayMask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
        overlayMask:Show()
    else
        -- No border overlays share the main mask, hide overlay mask if it exists
        if fd.overlayMask then fd.overlayMask:Hide() end
        overlayMask = mask
    end

    -- Apply overlay mask to all button overlay textures
    if btn.HighlightTexture then pcall(btn.HighlightTexture.AddMaskTexture, btn.HighlightTexture, overlayMask) end
    if btn.PushedTexture then pcall(btn.PushedTexture.AddMaskTexture, btn.PushedTexture, overlayMask) end
    if btn.CheckedTexture then pcall(btn.CheckedTexture.AddMaskTexture, btn.CheckedTexture, overlayMask) end
    if btn.NewActionTexture then pcall(btn.NewActionTexture.AddMaskTexture, btn.NewActionTexture, overlayMask) end
    if btn.Flash then pcall(btn.Flash.AddMaskTexture, btn.Flash, overlayMask) end
    if btn.QuickKeybindHighlightTexture then pcall(btn.QuickKeybindHighlightTexture.AddMaskTexture, btn.QuickKeybindHighlightTexture, overlayMask) end
    -- Hide Blizzard's item quality border (Dragonflight+) for custom shapes
    -- it uses a round atlas that doesn't match non-square shapes.
    if btn.Border then
        btn.Border:Hide()
    end
    if fd.slotBG then pcall(fd.slotBG.AddMaskTexture, fd.slotBG, mask) end
    if fd.iconBg then pcall(fd.iconBg.AddMaskTexture, fd.iconBg, mask) end
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

    -- Hide square borders (both PP and textured)
    if fd.borders then
        PP.HideBorder(btn)
        if EllesmereUI._bdBorderData then
            local bdFrame = EllesmereUI._bdBorderData[btn]
            if bdFrame then bdFrame:Hide() end
        end
    end

    -- Shape border texture
    if not fd.shapeBorder then
        fd.shapeBorder = btn:CreateTexture(nil, "OVERLAY", nil, 6)
    end
    local borderTex = fd.shapeBorder
    pcall(borderTex.RemoveMaskTexture, borderTex, mask)
    borderTex:ClearAllPoints()
    borderTex:SetAllPoints(btn)
    local btfd = EFD(borderTex)
    if brdOn and SHAPE_BORDERS[shape] then
        borderTex:SetTexture(SHAPE_BORDERS[shape])
        borderTex:SetVertexColor(brdR, brdG, brdB, brdA)
        borderTex:Show()
        btfd.wantsShow = true
    else
        borderTex:Hide()
        btfd.wantsShow = false
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
        EFD(btn.SpellActivationAlert).shapeMasked = true
    end
    if fd.glowWrapper then
        local w = fd.glowWrapper
        local wfd = EFD(w)
        if not wfd.ownMask then
            wfd.ownMask = w:CreateMaskTexture()
        end
        wfd.ownMask:ClearAllPoints()
        PP.Point(wfd.ownMask, "TOPLEFT", btn, "TOPLEFT", 1, -1)
        PP.Point(wfd.ownMask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        wfd.ownMask:SetTexture(maskTex, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        wfd.ownMask:Show()
        MaskFrameTextures(w, wfd.ownMask)
    end

    -- Store shape tracking flags for cooldown edge system
    fd.shapeApplied = true
    fd.shapeName = shape
    fd.shapeMaskPath = maskTex

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

    fd.cropped = false
end

-------------------------------------------------------------------------------
--  EAB Methods Apply functions called by the options UI
-------------------------------------------------------------------------------
function EAB:ApplyBordersForBar(barKey)
    if not self.db then return end
    if not self.db.profile.squareIcons then return end
    if self.db.profile.useBlizzardStyle then return end
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
    local textureKey = s.borderTexture or "solid"
    local texOffset = s.borderTextureOffset
    local texOffsetY = s.borderTextureOffsetY
    local texShiftX = s.borderTextureShiftX
    local texShiftY = s.borderTextureShiftY
    local thicknessKey = s.borderThickness or "thin"
    local behind = s.borderBehind
    local buttons = barButtons[barKey]
    if not buttons then return end
    for i = 1, #buttons do
        local btn = buttons[i]
        if btn then
            EFD(btn).barKey = barKey
            ApplyButtonBorders(btn, on, cr, cg, cb, ca, sz, zoom, textureKey, texOffset, texOffsetY, texShiftX, texShiftY, "actionbars", thicknessKey, behind)
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
    if self.db.profile.useBlizzardStyle then return end
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

function EAB:ApplyPaddingForBar(barKey)
    LayoutBar(barKey)
end

function EAB:ApplyButtonSizeForBar(barKey)
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
    -- In mouseover mode the hover system owns alpha (0 when unhovered,
    -- mouseoverAlpha when hovered). Don't override it here.
    if not s.mouseoverEnabled then
        frame:SetAlpha(s.mouseoverAlpha or 1)
        if barKey == "MainBar" then SyncPagingAlpha(s.mouseoverAlpha or 1) end
    end
end

function EAB:BarSupportsOrientation(barKey)
    local info = BAR_LOOKUP[barKey]
    return info and info.count ~= nil or false
end

function EAB:GetOrientationForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return true end
    return s.orientation ~= "vertical"
end

function EAB:LayoutAnchoredBarsFrom(targetKey, depth)
    if not targetKey or (depth or 0) > 12 then return end
    local adb = _G.EllesmereUIDB and _G.EllesmereUIDB.unlockAnchors
    if not adb then return end
    local nextDepth = (depth or 0) + 1
    for childKey, ai in pairs(adb) do
        if ai.target == targetKey and childKey ~= targetKey
            and self.db.profile.bars[childKey] and barFrames[childKey] then
            LayoutBar(childKey)
            self:LayoutAnchoredBarsFrom(childKey, nextDepth)
        end
    end
end

function EAB:SetOrientationForBar(barKey, isHorizontal)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    s.orientation = isHorizontal and "horizontal" or "vertical"
    -- Reset growth direction to orientation-appropriate default when switching
    local g = (s.growDirection or "up"):upper()
    if isHorizontal then
        -- Switching to horizontal: if current growth is vertical-only, reset
        if g == "UP" or g == "DOWN" then s.growDirection = "center" end
    else
        -- Switching to vertical: if current growth is horizontal-only, reset
        if g == "LEFT" or g == "RIGHT" then s.growDirection = "up" end
    end
    LayoutBar(barKey)
    self:LayoutAnchoredBarsFrom(barKey, 0)
end

function EAB:SetGrowDirectionForBar(barKey, dir)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    s.growDirection = dir or "up"
    LayoutBar(barKey)
    self:LayoutAnchoredBarsFrom(barKey, 0)
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
    local hideMacro = s.hideMacroText
    local macroSize = s.macroFontSize or 12
    if info and (info.isStance or info.isPetBar) then macroSize = max(macroSize - 2, 6) end
    local macroColor = s.macroFontColor or { r=1, g=1, b=1 }
    local macroOX = s.macroOffsetX or 0
    local macroOY = s.macroOffsetY or 0
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
                EllesmereUI.ApplyIconTextFont(hk, fontPath, kbSize, "actionBars")
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
            EllesmereUI.ApplyIconTextFont(ct, fontPath, ctSize, "actionBars")
            ct:SetTextColor(ctColor.r, ctColor.g, ctColor.b)
            ct:ClearAllPoints()
            ct:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1 + ctOX, 4 + ctOY)
        end

        -- Macro name text
        local nm = btn.Name
        if nm then
            if hideMacro then
                nm:SetAlpha(0)
            else
                nm:SetAlpha(1)
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(nm, false) end
                nm:SetFont(fontPath, macroSize, (EllesmereUI and EllesmereUI.SlugFlag and EllesmereUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
                nm:SetTextColor(macroColor.r, macroColor.g, macroColor.b)
                nm:ClearAllPoints()
                nm:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1 + macroOX, 4 + macroOY)
                nm:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1 + macroOX, 4 + macroOY)
                nm:SetJustifyH("CENTER")
            end
        end
    end
end

function EAB:ApplyFonts()
    for _, info in ipairs(BAR_CONFIG) do
        self:ApplyFontsForBar(info.key)
    end
    self:ApplyCooldownFonts()
end

-- Color-only re-assert for custom keybind text colors. Blizzard's own
-- button refreshes (mixin UpdateAction / UpdateHotkeys and the usable-state
-- recolor) reset HotKey's text color, so a custom color reverted to white
-- on target change, combat transitions, drag-and-drop and usability flips
-- until the next full ApplyFonts pass. This walks our buttons and
-- re-applies ONLY the color -- no fonts, no anchors -- and does no button
-- work at all for bars on the default white.
function EAB:ReapplyHotkeyColors()
    local bars = self.db and self.db.profile and self.db.profile.bars
    if not bars then return end
    for barKey, buttons in pairs(barButtons) do
        local s = bars[barKey]
        local c = s and not s.hideKeybind and s.keybindFontColor
        if c and (c.r ~= 1 or c.g ~= 1 or c.b ~= 1) then
            for i = 1, #buttons do
                local hk = buttons[i] and buttons[i].HotKey
                if hk then hk:SetTextColor(c.r, c.g, c.b) end
            end
        end
    end
end

-- One deferred color pass per event burst. Storm-safe by design: the
-- dispatcher can see dozens of ACTIONBAR_SLOT_CHANGED per second while
-- mouseover-conditional macros re-resolve, and the pending flag coalesces
-- an entire burst into a single next-frame color pass. State lives on EAB
-- (this file is at the Lua 200-local chunk cap).
function EAB:QueueHotkeyColorReassert()
    if self._kbColorPending then return end
    self._kbColorPending = true
    self._kbColorRunner = self._kbColorRunner or function()
        EAB._kbColorPending = false
        EAB:ReapplyHotkeyColors()
    end
    C_Timer_After(0, self._kbColorRunner)
end

-------------------------------------------------------------------------------
--  Cooldown Countdown Font Override
-------------------------------------------------------------------------------
function EAB_VTABLE.CooldownFonts.GetSettings(s)
    return (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("actionBars")) or FONT_PATH,
        s.cooldownFontSize or 12,
        s.cooldownTextXOffset or 0,
        s.cooldownTextYOffset or 0,
        s.cooldownTextColor or { r = 1, g = 1, b = 1 }
end

function EAB_VTABLE.CooldownFonts.ApplyToFrame(cdFrame, fontPath, cdSize, cdOX, cdOY, cdColor)
    if not cdFrame then return false end

    -- Skip if these exact settings were already applied to this frame
    local cdfd = EFD(cdFrame)
    local stamp = cdfd.cdFontStamp
    local cr, cg, cb = cdColor.r, cdColor.g, cdColor.b
    if stamp and stamp[1] == fontPath and stamp[2] == cdSize
       and stamp[3] == cdOX and stamp[4] == cdOY
       and stamp[5] == cr and stamp[6] == cg and stamp[7] == cb then
        return true
    end

    for ri = 1, cdFrame:GetNumRegions() do
        local region = select(ri, cdFrame:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
            EllesmereUI.ApplyIconTextFont(region, fontPath, cdSize, "actionBars")
            region:SetTextColor(cr, cg, cb)
            region:ClearAllPoints()
            region:SetPoint("CENTER", cdFrame, "CENTER", cdOX, cdOY)
            cdfd.cdFontStamp = { fontPath, cdSize, cdOX, cdOY, cr, cg, cb }
            return true
        end
    end

    return false
end

function EAB_VTABLE.CooldownFonts.ApplyToButton(btn, fontPath, cdSize, cdOX, cdOY, cdColor)
    if not btn then return end

    local applied = EAB_VTABLE.CooldownFonts.ApplyToFrame(btn.cooldown, fontPath, cdSize, cdOX, cdOY, cdColor)
    EAB_VTABLE.CooldownFonts.ApplyToFrame(btn.chargeCooldown, fontPath, cdSize, cdOX, cdOY, cdColor)
    if applied then return end

    -- Some cooldown frames create their countdown FontString lazily on the
    -- first update after SetCooldown(). Retry once on the next frame.
    C_Timer_After(0, function()
        EAB_VTABLE.CooldownFonts.ApplyToFrame(btn.cooldown, fontPath, cdSize, cdOX, cdOY, cdColor)
        EAB_VTABLE.CooldownFonts.ApplyToFrame(btn.chargeCooldown, fontPath, cdSize, cdOX, cdOY, cdColor)
    end)
end

function EAB:ApplyCooldownFontsForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local buttons = barButtons[barKey]
    if not buttons then return end
    local fontPath, cdSize, cdOX, cdOY, cdColor = EAB_VTABLE.CooldownFonts.GetSettings(s)

    C_Timer.After(0, function()
        for i = 1, #buttons do
            local btn = buttons[i]
            if not btn then break end
            EAB_VTABLE.CooldownFonts.ApplyToButton(btn, fontPath, cdSize, cdOX, cdOY, cdColor)
        end
    end)
end

function EAB:ApplyCooldownFonts()
    EAB_VTABLE.CooldownFonts.HookAll()
    for _, info in ipairs(BAR_CONFIG) do
        self:ApplyCooldownFontsForBar(info.key)
    end
end

-- Re-apply "Alpha when on CD" across every action button. Used on setting change
-- (immediate feedback + a clean restore to full alpha when set back to 100) and on
-- the main apply. Reuses the exact same secret-safe curve detection as the live
-- ACTIONBAR_UPDATE_COOLDOWN handler.
function EAB:ApplyCDAlphaAll()
    local pdb = self.db and self.db.profile
    local cdAlpha = (pdb and pdb.alphaWhenOnCD) or 100
    local on = cdAlpha ~= 100
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local btns = barButtons[info.key]
            if btns then
                for _, btn in ipairs(btns) do
                    local icon = btn and btn.icon
                    if icon then
                        local applied = false
                        if on then
                            local action = btn:GetAttribute("action")
                            if action and HasAction(action) and icon.SetAlphaFromBoolean then
                                local cdInfo = C_ActionBar.GetActionCooldown(action)
                                if cdInfo and cdInfo.isActive then
                                    local durObj = C_ActionBar.GetActionCooldownDuration(action)
                                    if durObj and durObj.IsZero then
                                        -- Secret-safe: never compare the remaining duration; feed
                                        -- IsZero() into SetAlphaFromBoolean. Same real-CD gating as
                                        -- the live handler (GCD excluded for plain spells).
                                        local chargeInfo = C_ActionBar.GetActionCharges(action)
                                        local realCd = (chargeInfo and chargeInfo.maxCharges and chargeInfo.maxCharges > 1)
                                            or (GetActionInfo(action) == "item")
                                            or (not cdInfo.isOnGCD)
                                        if realCd then
                                            icon:SetAlphaFromBoolean(durObj:IsZero(), 1, cdAlpha / 100)
                                            applied = true
                                        end
                                    end
                                end
                            end
                        end
                        if not applied then icon:SetAlpha(1) end
                    end
                end
            end
        end
    end
end

-- Apply the custom cooldown-swipe colour + opacity to every button's cooldown.
-- Cheap and idempotent (SetSwipeColor persists on the frame), so it runs on the
-- main apply and on setting change. Defaults mirror the Blizzard look, so a
-- default profile is visually unchanged.
function EAB:ApplyCooldownSwipeColor()
    local pdb = self.db and self.db.profile
    if not pdb then return end
    local c = pdb.cdSwipeColor or { r = 0, g = 0, b = 0 }
    local a = (pdb.cdSwipeAlpha or 80) / 100
    for _, info in ipairs(BAR_CONFIG) do
        local btns = barButtons[info.key]
        if btns then
            for _, btn in ipairs(btns) do
                local cd = btn and btn.cooldown
                if cd and cd.SetSwipeColor then
                    pcall(cd.SetSwipeColor, cd, c.r or 0, c.g or 0, c.b or 0, a)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Bar Background
-------------------------------------------------------------------------------
local barBackgrounds = {}  -- [barKey] = { fill = Texture, border = Frame }

function EAB:ApplyBackgroundForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end
    local frame = barFrames[barKey]
    if not frame then return end

    if not s.bgEnabled then
        local background = barBackgrounds[barKey]
        if background then
            background.fill:Hide()
            if EllesmereUI and EllesmereUI.ApplyBorderStyle then
                EllesmereUI.ApplyBorderStyle(background.border, 0, 0, 0, 0, s.bgBorderTexture or "solid")
            else
                background.border:Hide()
            end
        end
        return
    end

    local background = barBackgrounds[barKey]
    if not background then
        local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        border:EnableMouse(false)
        border:SetFrameLevel(math.max(0, frame:GetFrameLevel()))
        background = { fill = fill, border = border }
        barBackgrounds[barKey] = background
    end

    local c = s.bgColor or { r=0, g=0, b=0, a=0.5 }
    local alpha = s.bgOpacity ~= nil and s.bgOpacity / 100 or c.a
    background.fill:SetColorTexture(c.r, c.g, c.b, alpha)
    -- bgPadX/bgPadY are retained as fallbacks for profiles made before the
    -- unified spacing control was introduced.
    local padding = s.bgPadding
    local padX = padding ~= nil and padding or (s.bgPadX or 0)
    local padY = padding ~= nil and padding or (s.bgPadY or 0)
    local multiplierX = math.max(1, math.min(4, math.floor((s.bgMultiplierX or 1) + 0.5)))
    local multiplierY = math.max(1, math.min(4, math.floor((s.bgMultiplierY or 1) + 0.5)))
    local directionX = s.bgExpandDirectionX or "right"
    local directionY = s.bgExpandDirectionY or "up"
    local iconPadding = s.buttonPadding or 0
    local growX = (multiplierX - 1) * ((frame:GetWidth() or 0) + iconPadding)
    local growY = (multiplierY - 1) * ((frame:GetHeight() or 0) + iconPadding)
    local left, right, top, bottom = -padX, padX, padY, -padY
    if directionX == "left" then left = left - growX else right = right + growX end
    if directionY == "down" then bottom = bottom - growY else top = top + growY end
    background.fill:ClearAllPoints()
    background.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top)
    background.fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, bottom)
    background.fill:Show()

    local border = background.border
    border:SetFrameLevel(s.bgBorderBehind and math.max(0, frame:GetFrameLevel() - 1) or frame:GetFrameLevel())
    border:ClearAllPoints()
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", left, top)
    border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", right, bottom)
    if EllesmereUI and EllesmereUI.ApplyBorderStyle then
        local bc = s.bgBorderColor or { r=0, g=0, b=0, a=1 }
        local thicknessKey = s.bgBorderThickness or "none"
        local thickness = ns.BORDER_THICKNESS and ns.BORDER_THICKNESS[thicknessKey]
        local borderSize = thickness and thickness.regular or 0
        EllesmereUI.ApplyBorderStyle(border, borderSize,
            bc.r, bc.g, bc.b, bc.a or 1, s.bgBorderTexture or "solid",
            s.bgBorderOffsetX, s.bgBorderOffsetY,
            s.bgBorderShiftX, s.bgBorderShiftY,
            "actionbars", thicknessKey)
    else
        border:Hide()
    end
end

-------------------------------------------------------------------------------
--  Blizzard Icon Background (per-button slot texture)
-------------------------------------------------------------------------------
function EAB:ApplyIconBackgroundForBar(barKey)
    local pr = self.db.profile
    local buttons = barButtons[barKey]
    if not buttons then return end
    local show = pr.showBlizzIconBg or false
    local alpha = pr.blizzIconBgAlpha or 1
    local blizzStyle = pr.useBlizzardStyle
    local inset = blizzStyle and 0 or 4
    for i = 1, #buttons do
        local btn = buttons[i]
        if not btn then break end
        -- Only show icon background on empty slots
        local hasAction = btn.HasAction and pcall(btn.HasAction, btn) and btn:HasAction()
        local showThis = show and not hasAction
        local bfd = EFD(btn)
        if not bfd.iconBgClip then
            local clip = CreateFrame("Frame", nil, btn)
            clip:SetAllPoints(btn)
            clip:SetClipsChildren(true)
            clip:SetFrameLevel(math.max(1, btn:GetFrameLevel() - 1))
            clip:EnableMouse(false)
            local bg = clip:CreateTexture(nil, "BACKGROUND", nil, -1)
            bg:SetAtlas("UI-HUD-ActionBar-IconFrame-Slot")
            bfd.iconBgClip = clip
            bfd.iconBg = bg
            -- Auto-update on button events. ACTIONBAR_SLOT_CHANGED is not
            -- delivered to buttons (central dispatcher owns it and syncs the
            -- clip there); this hook covers the remaining per-button events.
            btn:HookScript("OnEvent", function(self)
                local sfd = EFD(self)
                local c = sfd.iconBgClip
                if c then
                    local p2 = EAB.db and EAB.db.profile
                    local on = p2 and p2.showBlizzIconBg or false
                    local ha = self.HasAction and pcall(self.HasAction, self) and self:HasAction()
                    c:SetShown(on and not ha)
                end
            end)
        end
        bfd.iconBg:ClearAllPoints()
        bfd.iconBg:SetPoint("TOPLEFT", btn, "TOPLEFT", -inset, inset)
        bfd.iconBg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", inset, -inset)
        bfd.iconBg:SetAlpha(alpha)
        -- Apply custom shape mask if active (shapes run before this)
        if bfd.shapeMask and bfd.shapeApplied then
            pcall(bfd.iconBg.AddMaskTexture, bfd.iconBg, bfd.shapeMask)
        end
        bfd.iconBgClip:SetShown(showThis)
    end
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

    -- Update the SHOWGRID.ALWAYS flag on managed action buttons
    if not InCombatLockdown() and not info.isStance and not info.isPetBar then
        for _, btn in ipairs(buttons) do
            if btn then
                SetShowGridInsecure(btn, showEmpty, SHOWGRID.ALWAYS)
            end
        end
    end

    -- During a spell drag, we leave the controller's secure visibility path
    -- alone. QuickKeybind still needs the normal visibility refresh so its
    -- dedicated KEYBOUND flag can show empty slots on EAB-owned bars.
    if _gridState.shown and not _quickKeybindState.open then return end

    -- Respect icon cutoff
    local numIcons = s.overrideNumIcons or s.numIcons or info.count
    if numIcons < 1 then numIcons = info.count end
    if numIcons > info.count then numIcons = info.count end
    if info.isStance then numIcons = GetNumShapeshiftForms() or info.count end
    if numIcons < 1 then numIcons = 1 end

    local quickKeybindVisible = ShouldQuickKeybindSurfaceBar(s)
    local clickable = quickKeybindVisible or not s.clickThrough
    local lastVisible = 0
    for i = 1, numIcons do
        local btn = buttons[i]
        if btn then
            if info.nativeMainBar then
                EAB_VTABLE.MainBarPageSync.SetButtonConfig(btn, true, showEmpty)
            end
            local hasAction = ButtonHasAction(btn, info.blizzBtnPrefix)
            local visible = showEmpty or hasAction or quickKeybindVisible

            local bfd = EFD(btn)
            if bfd.slotBG then
                bfd.slotBG:SetShown(visible)
            end
            if bfd.borders and not (bfd.shapeMask and bfd.shapeMask:IsShown()) then
                bfd.borders:SetShown(visible)
            end
            if bfd.shapeBorder then
                bfd.shapeBorder:SetShown(visible and EFD(bfd.shapeBorder).wantsShow == true)
            end

            if not visible then
                btn:SetAlpha(0)
                -- Invisible empty slots should not catch mouse events.
                -- Set statehidden so the secure UpdateShown snippet
                -- keeps the button hidden instead of re-showing it.
                SafeEnableMouse(btn, false)
                if not InCombatLockdown() then
                    btn:SetAttributeNoHandler("statehidden", true)
                    btn:Hide()
                end
            else
                if not InCombatLockdown() then
                    btn:SetAttributeNoHandler("statehidden", nil)
                    btn:SetAttribute("showgrid", 1)
                    btn:Show()
                end
                -- Always restore button alpha to 1. The bar frame's own
                -- alpha (via mouseover fade) handles overall visibility.
                btn:SetAlpha(1)
                -- Restore mouse state based on bar's click-through setting.
                -- When click-through is on but mouseover is enabled, keep
                -- mouse motion so OnEnter/OnLeave still fire for hover fade.
                if clickable then
                    SafeEnableMouse(btn, true)
                elseif s.mouseoverEnabled then
                    SafeEnableMouseMotionOnly(btn, true)
                else
                    SafeEnableMouse(btn, false)
                end
                lastVisible = i
            end
        end
    end
    -- Hide buttons beyond cutoff
    for i = numIcons + 1, #buttons do
        local btn = buttons[i]
        if btn then
            if info.nativeMainBar then
                EAB_VTABLE.MainBarPageSync.SetButtonConfig(btn, false, showEmpty)
            end
            btn:SetAlpha(0)
            SafeEnableMouse(btn, false)
            if not InCombatLockdown() then
                btn:SetAttributeNoHandler("statehidden", true)
                btn:Hide()
            end
        end
    end

    -- Note: frame size is left as-is from LayoutBar.  The mouseover
    -- OnEnter handler already checks cursor proximity to visible buttons,
    -- so shrinking the frame is unnecessary and can misposition bars
    -- whose anchor point isn't TOPLEFT.
end

-------------------------------------------------------------------------------
--  Main Bar Page Sync
--  EAB owns MainBar paging through a custom secure parent frame, so Blizzard's
--  stock ActionBarController no longer runs its usual "set actionpage, then
--  refresh every button" sequence for ActionButton1-12.  We restore that
--  contract here by:
--    1. tracking page-sensitive visibility inputs on the buttons, and
--    2. using a secure child-update from the MainBar frame to trigger the
--       buttons' normal OnAttributeChanged -> UpdateAction path in combat.
-------------------------------------------------------------------------------
function EAB_VTABLE.MainBarPageSync.SetButtonConfig(btn, withinCutoff, showEmpty)
    if not btn or InCombatLockdown() then return end
    btn:SetAttributeNoHandler("eab-withincutoff", withinCutoff and 1 or 0)
    btn:SetAttributeNoHandler("eab-showempty", showEmpty and 1 or 0)
end

function EAB_VTABLE.MainBarPageSync.Queue()
    local state = EAB_VTABLE.MainBarPageSync
    if state.pending then return end
    state.pending = true
    C_Timer_After(0, function()
        state.pending = false
        if InCombatLockdown() or not EAB or not EAB.db then return end
        EAB:ApplyAlwaysShowButtons("MainBar")
    end)
end

function EAB_VTABLE.MainBarPageSync.InstallAll()
    if InCombatLockdown() then return end
    local buttons = barButtons["MainBar"]
    if not buttons then return end
    for _, btn in ipairs(buttons) do
        EAB_VTABLE.MainBarPageSync.InstallButton(btn)
    end
end

function EAB_VTABLE.MainBarPageSync.InstallButton(btn)
    if not btn or btn:GetAttribute("_eabPageSyncInstalled") or InCombatLockdown() then return end

    -- Bake the base index directly into the snippet as a literal so it
    -- doesn't depend on attribute reads in the restricted environment.
    local info = buttonToBar[btn]
    local baseIdx = info and info.index or 1

    btn:SetAttributeNoHandler("_childupdate-eab-page", ([[
        local page = tonumber(message) or 1
        local slot = %d + (page - 1) * %d
        self:SetAttribute("action", slot)
        local visible = self:GetAttribute("eab-withincutoff") ~= 0

        if visible and self:GetAttribute("eab-showempty") == 0 then
            visible = HasAction(slot)
        end

        local hidden = self:GetAttribute("statehidden")
        local changed = false

        if visible then
            if hidden then
                self:SetAttribute("statehidden", nil)
                changed = true
            end
            self:Show(true)
        else
            if not hidden then
                self:SetAttribute("statehidden", true)
                changed = true
            end
            self:Hide(true)
        end

        if not changed then
            local token = self:GetAttribute("eab-pagesync-token") or 0
            self:SetAttribute("eab-pagesync-token", token == 0 and 1 or 0)
        end
    ]]):format(baseIdx, NUM_ACTIONBAR_BUTTONS))

    btn:SetAttributeNoHandler("_eabPageSyncInstalled", true)
end

-------------------------------------------------------------------------------
--  Out-of-Range Icon Coloring
--
--  Uses the retail ACTION_RANGE_CHECK_UPDATE event to tint action button
--  icons when the target is out of range.  Each slot is opted-in via
--  C_ActionBar.EnableActionRangeCheck so the client fires the event only
--  for slots we care about.
-------------------------------------------------------------------------------
local _range = {
    slots = {},           -- [actionSlot] = true  (slots with range checking enabled)
    outOfRange = {},      -- [actionSlot] = true  (currently out of range)
    eventFrame = nil,     -- lazy-created event frame
    slotPending = false,  -- debounce for per-slot range re-enable
}

-- Resolve the action slot for a button without reading btn.action.
-- btn.action is a protected attribute (secret value in Midnight) and
-- reading it during combat causes taint. Instead we use a lookup table
-- populated at setup time. MainBar reads actionpage from the bar frame
-- (set by _onstate-page) to compute the current page offset dynamically.
local function GetButtonActionSlot(btn)
    local info = buttonToBar[btn]
    if not info then return nil end
    local offset = BAR_SLOT_OFFSETS[info.barKey]
    if not offset then return nil end
    if info.barKey == "MainBar" then
        -- Read the current page from the bar frame's actionpage attribute,
        -- which is set by the _onstate-page handler in the restricted env.
        -- This correctly reflects vehicle/override/form pages, unlike
        -- C_ActionBar.GetActionBarPage() which only tracks the manual page.
        local frame = barFrames["MainBar"]
        local page = frame and tonumber(frame:GetAttribute("actionpage")) or EAB_VTABLE.GetActionBarPage()
        offset = (page - 1) * NUM_ACTIONBAR_BUTTONS
    end
    return offset + info.index
end

-- Apply or remove the range tint on a single button
local function ApplyRangeTint(btn, outOfRange, barSettings)
    local ico = btn.icon or btn.Icon
    if not ico then return end
    local rfd = EFD(btn)
    if outOfRange and barSettings.outOfRangeColoring then
        local c = barSettings.outOfRangeColor or { r = 0.7, g = 0.2, b = 0.2 }
        ico:SetVertexColor(c.r, c.g, c.b)
        rfd.rangeTinted = true
    elseif rfd.rangeTinted then
        rfd.rangeTinted = nil
        -- Let Blizzard's UpdateUsable set the correct color (may be dimmed
        -- for insufficient resources) instead of forcing full white.
        if btn.UpdateUsable then
            btn:UpdateUsable()
        else
            ico:SetVertexColor(1, 1, 1)
        end
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
        if slot and not _range.slots[slot] then
            _range.slots[slot] = true
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
        if slot and _range.slots[slot] then
            _range.slots[slot] = nil
            _range.outOfRange[slot] = nil
            if C_ActionBar and C_ActionBar.EnableActionRangeCheck then
                pcall(C_ActionBar.EnableActionRangeCheck, slot, false)
            end
        end
        local rfd = EFD(btn)
        if rfd.rangeTinted then
            rfd.rangeTinted = nil
            if btn.UpdateUsable then
                btn:UpdateUsable()
            else
                local ico = btn.icon or btn.Icon
                if ico then ico:SetVertexColor(1, 1, 1) end
            end
        end
    end
end

-- Recompute a bar's flyout direction from its current screen position.
function EAB:RecalcFlyoutDirection(barKey)
    if InCombatLockdown() then return end
    local frame = barFrames[barKey]
    local btns = barButtons[barKey]
    local s = self.db.profile.bars[barKey]
    if not frame or not btns or not s then return end
    local isVert = (s.orientation == "vertical")
    local cx, cy = frame:GetCenter()
    if not cx or not cy then return end
    local uiW = UIParent:GetWidth()
    local uiH = UIParent:GetHeight()
    local uiScale = UIParent:GetEffectiveScale()
    local fScale  = frame:GetEffectiveScale()
    cx = cx * fScale / uiScale
    cy = cy * fScale / uiScale
    local thirdW = uiW / 3
    local thirdH = uiH / 3
    local dir
    if isVert then
        dir = (cx > thirdW * 2) and "LEFT" or "RIGHT"
    else
        dir = (cy > thirdH * 2) and "DOWN" or "UP"
    end
    for _, btn in ipairs(btns) do
        btn:SetAttribute("flyoutDirection", dir)
    end
end

function EAB:ApplyRangeColoring()
    -- Set up the event listener BEFORE enabling range checks so any
    -- immediate ACTION_RANGE_CHECK_UPDATE events are caught.
    if not _range.eventFrame then
        -- No offset snapshot needed: GetButtonActionSlot reads the bar
        -- frame's actionpage attribute dynamically for MainBar.
        _range.eventFrame = CreateFrame("Frame")
        _range.eventFrame:RegisterEvent("ACTION_RANGE_CHECK_UPDATE")
        _range.eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        _range.eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
        _range.eventFrame:RegisterEvent("ACTION_USABLE_CHANGED")
        _range.eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        _range.eventFrame:SetScript("OnEvent", function(_, event, slot, inRange, checksRange)
            if event == "ACTION_RANGE_CHECK_UPDATE" then
                if not _range.slots[slot] then return end
                local wasOut = _range.outOfRange[slot]
                local isOut = checksRange and not inRange
                local changed = false
                if isOut and not wasOut then
                    _range.outOfRange[slot] = true
                    changed = true
                elseif not isOut and wasOut then
                    _range.outOfRange[slot] = nil
                    changed = true
                end
                if not changed then return end
                local bars = EAB.db.profile.bars
                for _, info in ipairs(BAR_CONFIG) do
                    local btns = barButtons[info.key]
                    local s = bars[info.key]
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
                if slot and _range.slots[slot] then
                    if _range.outOfRange[slot] then
                        _range.outOfRange[slot] = nil
                        local bars2 = EAB.db.profile.bars
                        for _, info2 in ipairs(BAR_CONFIG) do
                            local btns2 = barButtons[info2.key]
                            local s2 = bars2[info2.key]
                            if btns2 and s2 then
                                for _, btn2 in ipairs(btns2) do
                                    if GetButtonActionSlot(btn2) == slot then
                                        ApplyRangeTint(btn2, false, s2)
                                    end
                                end
                            end
                        end
                    end
                    if C_ActionBar and C_ActionBar.EnableActionRangeCheck then
                        pcall(C_ActionBar.EnableActionRangeCheck, slot, true)
                    end
                end
                -- Debounce the full re-enable pass so 12+ per-slot fires
                -- during a bar page swap collapse into one deferred call
                if not _range.slotPending then
                    _range.slotPending = true
                    C_Timer_After(0, function()
                        _range.slotPending = false
                        for _, info in ipairs(BAR_CONFIG) do
                            local s = EAB.db.profile.bars[info.key]
                            if s and s.outOfRangeColoring then
                                EnableRangeCheckForBar(info.key)
                            end
                        end
                    end)
                end
            elseif event == "ACTIONBAR_PAGE_CHANGED" then
                -- No offset update needed: GetButtonActionSlot reads the bar
                -- frame's actionpage attribute dynamically for MainBar.
                -- Page changed: clear all range state and re-enable for new slots
                wipe(_range.outOfRange)
                for _, info in ipairs(BAR_CONFIG) do
                    local s = EAB.db.profile.bars[info.key]
                    if s and s.outOfRangeColoring then
                        local btns = barButtons[info.key]
                        if btns then
                            for _, btn in ipairs(btns) do
                                local rfd = EFD(btn)
                                if rfd.rangeTinted then
                                    local ico = btn.icon or btn.Icon
                                    if ico then ico:SetVertexColor(1, 1, 1) end
                                    rfd.rangeTinted = nil
                                end
                            end
                        end
                        EnableRangeCheckForBar(info.key)
                    end
                end
            elseif event == "ACTION_USABLE_CHANGED" then
                -- Blizzard resets icon vertex colors on usability changes;
                -- re-apply range tint on any out-of-range buttons.
                -- Bail fast when nothing is out of range (common case).
                if not next(_range.outOfRange) then return end
                for _, info in ipairs(BAR_CONFIG) do
                    local btns = barButtons[info.key]
                    local s = EAB.db.profile.bars[info.key]
                    if btns and s and s.outOfRangeColoring then
                        for _, btn in ipairs(btns) do
                            if EFD(btn).rangeTinted then
                                ApplyRangeTint(btn, true, s)
                            end
                        end
                    end
                end
            elseif event == "UPDATE_SHAPESHIFT_FORM" then
                -- Form shifts can cause ACTION_RANGE_CHECK_UPDATE to fire
                -- with stale data before Blizzard settles. Defer a manual
                -- IsActionInRange poll to correct any wrong tints.
                C_Timer_After(0, function()
                    local bars = EAB.db.profile.bars
                    for _, info in ipairs(BAR_CONFIG) do
                        local s = bars[info.key]
                        if s and s.outOfRangeColoring then
                            local btns = barButtons[info.key]
                            if btns then
                                for _, btn in ipairs(btns) do
                                    local sl = GetButtonActionSlot(btn)
                                    if sl and HasAction(sl) then
                                        local inRange = IsActionInRange(sl)
                                        local isOut = (inRange == false)
                                        _range.outOfRange[sl] = isOut or nil
                                        ApplyRangeTint(btn, isOut, s)
                                    else
                                        if sl then _range.outOfRange[sl] = nil end
                                        ApplyRangeTint(btn, false, s)
                                    end
                                end
                            end
                        end
                    end
                end)
            end
        end)
    end

    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local s = self.db.profile.bars[key]
        if s and s.outOfRangeColoring then
            EnableRangeCheckForBar(key)
            -- Immediate sweep: apply tint for slots already out of range
            -- since EnableActionRangeCheck does not fire an initial event.
            local btns = barButtons[key]
            if btns then
                for _, btn in ipairs(btns) do
                    local slot = GetButtonActionSlot(btn)
                    if slot and HasAction(slot) then
                        local inRange = IsActionInRange(slot)
                        if inRange == false then
                            _range.outOfRange[slot] = true
                            ApplyRangeTint(btn, true, s)
                        else
                            _range.outOfRange[slot] = nil
                            ApplyRangeTint(btn, false, s)
                        end
                    elseif slot and _range.outOfRange[slot] then
                        -- Slot lost its action (e.g., talent swap). Clear stale tint.
                        _range.outOfRange[slot] = nil
                        ApplyRangeTint(btn, false, s)
                    end
                end
            end
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
                if not EFD(btn).rangeHooked and btn.UpdateUsable then
                    EFD(btn).rangeHooked = true
                    hooksecurefunc(btn, "UpdateUsable", function(self)
                        if not EFD(self).rangeTinted then return end
                        local slot = GetButtonActionSlot(self)
                        if slot and _range.outOfRange[slot] then
                            local bInfo = buttonToBar[self]
                            local s = bInfo and EAB.db.profile.bars[bInfo.barKey]
                            if s and s.outOfRangeColoring then
                                ApplyRangeTint(self, true, s)
                            end
                        end
                    end)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Mouseover Fade System
-------------------------------------------------------------------------------
local hoverStates = {}  -- shared by action bars, data bars, and extra bars
local AttachExtraBarHoverHooks  -- forward declaration; defined near SetupExtraBarHolder

-- Every mouseover-enabled bar follows the same state machine: entering marks
-- the bar hovered and fades it in, leaving schedules a guarded fade-out on the
-- next frame. The per-bar attach functions only provide the edge-case policies
-- that differ between action bars, data bars, and Blizzard-owned extra bars.
function EAB_VTABLE.Hover.GetSettings(barKey)
    return EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars[barKey]
end

function EAB_VTABLE.Hover.GetState(barKey, frame)
    local state = hoverStates[barKey]
    if not state then
        state = { frame = frame, isHovered = false, fadeDir = nil }
        hoverStates[barKey] = state
    else
        state.frame = frame or state.frame
    end
    return state
end

ns._broadcastingMouseover = false

function EAB_VTABLE.Hover.FadeIn(barKey, state)
    local s = EAB_VTABLE.Hover.GetSettings(barKey)
    if s and s.mouseoverEnabled and state and state.fadeDir ~= "in" then
        local targetAlpha = s._savedBarAlpha or 1
        state.fadeDir = "in"
        StopFade(state.frame)
        FadeTo(state.frame, targetAlpha, s.mouseoverSpeed or 0.15)
        if barKey == "MainBar" then SyncPagingAlpha(targetAlpha) end
        -- Broadcast to all other mouseover-enabled bars
        if not ns._broadcastingMouseover and EAB.db.profile.mouseoverShowAll then
            ns._broadcastingMouseover = true
            for otherKey, otherState in pairs(hoverStates) do
                if otherKey ~= barKey then
                    EAB_VTABLE.Hover.FadeIn(otherKey, otherState)
                end
            end
            ns._broadcastingMouseover = false
        end
    end
end

function EAB_VTABLE.Hover.FadeOut(barKey, state)
    if _gridState.shown then return end  -- keep bars visible during spell drag
    local s = EAB_VTABLE.Hover.GetSettings(barKey)
    if s and s.mouseoverEnabled and state and state.fadeDir ~= "out" then

        state.fadeDir = "out"
        StopFade(state.frame)
        FadeTo(state.frame, 0, s.mouseoverSpeed or 0.15)
        if barKey == "MainBar" then SyncPagingAlpha(0) end
    end
end

-- Check if any mouseover-enabled bar is currently hovered.
function ns.AnyMouseoverBarHovered()
    for otherKey, otherState in pairs(hoverStates) do
        if otherState.isHovered then
            local os = EAB_VTABLE.Hover.GetSettings(otherKey)
            if os and os.mouseoverEnabled then return true end
        end
    end
    return false
end

function EAB_VTABLE.Hover.ScheduleFadeOut(barKey, state, opts)
    opts = opts or {}

    C_Timer_After(0.1, function()
        if opts.isStillHovered and opts.isStillHovered(state) then
            if opts.markHoveredWhileActive then
                state.isHovered = true
            end
            return
        end
        if state.isHovered then return end
        if _quickKeybindState.open then return end
        if opts.blockFadeOut and opts.blockFadeOut(state) then return end
        -- When showing all bars together, keep visible while any bar is hovered
        if EAB.db.profile.mouseoverShowAll and ns.AnyMouseoverBarHovered() then return end
        EAB_VTABLE.Hover.FadeOut(barKey, state)
        -- Broadcast fade-out to all other mouseover bars
        if EAB.db.profile.mouseoverShowAll then
            for otherKey, otherState in pairs(hoverStates) do
                if otherKey ~= barKey and not otherState.isHovered then
                    EAB_VTABLE.Hover.FadeOut(otherKey, otherState)
                end
            end
        end
    end)
end

function EAB_VTABLE.Hover.BuildHandlers(barKey, state, opts)
    opts = opts or {}

    local function OnEnter(self)
        if opts.canEnter and not opts.canEnter(self, state) then return end
        state.isHovered = true
        EAB_VTABLE.Hover.FadeIn(barKey, state)
    end

    local function OnLeave()
        state.isHovered = false
        EAB_VTABLE.Hover.ScheduleFadeOut(barKey, state, opts)
    end

    return OnEnter, OnLeave
end

local function AttachDataBarHoverHooks(barKey)
    if hoverStates[barKey] then return end

    local frame = dataBarFrames[barKey]
    if not frame then return end

    local state = EAB_VTABLE.Hover.GetState(barKey, frame)
    local OnEnter, OnLeave = EAB_VTABLE.Hover.BuildHandlers(barKey, state)

    frame:HookScript("OnEnter", OnEnter)
    frame:HookScript("OnLeave", OnLeave)
end

local function AttachHoverHooks(barKey)
    local frame = barFrames[barKey]
    local buttons = barButtons[barKey]
    if not frame or not buttons then return end

    local state = EAB_VTABLE.Hover.GetState(barKey, frame)

    local function CanEnter(self)
        -- Skip hidden empty buttons (alwaysShowButtons off)
        local s = EAB.db.profile.bars[barKey]
        if s then
            local showEmpty = s.alwaysShowButtons
            if showEmpty == nil then showEmpty = true end
            if not showEmpty then
                if self ~= frame then
                    -- Individual button: skip if it's hidden (no action)
                    if self.GetAlpha and self:GetAlpha() < 0.01 then
                        return false
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
                    if not nearVisible then return false end
                end
            end
        end
        return true
    end

    local OnEnter, OnLeave = EAB_VTABLE.Hover.BuildHandlers(barKey, state, {
        canEnter = CanEnter,
        blockFadeOut = function()
            -- Keep bar visible while a spell flyout spawned from this bar is open.
            return GetEABFlyout():IsVisible() and GetEABFlyout():IsMouseOver()
        end,
    })

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
        if s then
            local frame = barFrames[key] or (info.isDataBar and dataBarFrames[key]) or (info.isBlizzardMovable and blizzMovableHolders[key]) or (extraBarHolders[key]) or (info.visibilityOnly and _G[info.frameName])
            if frame then
                -- For extra bars (MicroBar, BagBar), fade the Blizzard frame directly
                -- since that's what AttachExtraBarHoverHooks targets.
                if info.visibilityOnly and not info.isDataBar and not info.isBlizzardMovable then
                    local blizzFrame = _G[info.frameName]
                    if blizzFrame then frame = blizzFrame end
                end
                if info.noManagedVisibility then
                    -- Position-only Blizzard-owned eye (QueueStatus): EUI no longer
                    -- controls its visibility, so never fade or alpha-hide it --
                    -- force full opacity regardless of stale mouseover settings.
                    StopFade(frame)
                    frame:SetAlpha(1)
                elseif s.mouseoverEnabled then
                    if info.isDataBar then
                        AttachDataBarHoverHooks(key)
                    end
                    -- Ensure extra bars have hover hooks attached (may not have been
                    -- set up at load time if mouseover was disabled then)
                    if info.visibilityOnly and not info.isDataBar and not info.isBlizzardMovable then
                        AttachExtraBarHoverHooks(info)
                    end
                    StopFade(frame)
                    frame:SetAlpha(0)
                    local state = hoverStates[key]
                    if state then state.fadeDir = "out" end
                    if key == "MainBar" then SyncPagingAlpha(0) end
                else
                    StopFade(frame)
                    frame:SetAlpha(s.mouseoverAlpha or 1)
                    local state = hoverStates[key]
                    if state then state.fadeDir = nil end
                    if key == "MainBar" then SyncPagingAlpha(s.mouseoverAlpha or 1) end
                end
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
-- Multi-select visibility compiler: thin delegates to the shared secure
-- driver compiler in EllesmereUI_Visibility.lua (one grammar for Action
-- Bars and Unit Frames). EAB table fields, not locals -- this file sits at
-- Lua 5.1's 200-local-per-chunk cap.
function EAB.BuildVisModeConjuncts(vm)
    return EllesmereUI.BuildVisModeConjuncts(vm)
end

function EAB.BuildVisibilityStringMulti(hidePrefix, vm)
    return EllesmereUI.BuildVisibilityDriverString(hidePrefix, vm)
end

local function BuildVisibilityString(info, s, visOverride)
    local key = info.key
    local vis = visOverride or s.barVisibility or "always"

    if info.isStance and (GetNumShapeshiftForms() or 0) == 0 then
        return "hide" -- classes/specs with no forms have no stance bar to show
    end

    -- Build visibility-option hide clauses that can be expressed as macro
    -- conditionals. These run inside the secure state driver so they work
    -- even in combat without taint.
    local visOptHide = ""
    if s.visHideMounted then visOptHide = visOptHide .. "[mounted] hide; " end
    if s.visHideNoTarget then visOptHide = visOptHide .. "[noexists] hide; " end
    if s.visHideNoEnemy then visOptHide = visOptHide .. "[noharm] hide; " end

    -- Authoritative multi-select set. Explicit overrides (toggle keybind,
    -- QuickKeybind, grid drag) substitute the whole mode term exactly as
    -- they do for single modes, so they keep the legacy path.
    local vm
    if not visOverride and EllesmereUI.GetActiveVisibilityModes then
        vm = EllesmereUI.GetActiveVisibilityModes(s, "barVisibility")
    end

    -- Pet bar has unique logic: it only shows when a pet is active and
    -- the player is not in a vehicle/override/possess state.
    if info.isPetBar then
        if vm then
            -- Multi path: combat/dragon conjuncts join the pet wrapper
            -- bracket (AND); group modes are structurally unsupported here
            -- (locked in the UI, stripped by sync copies).
            local conj, negGate = EAB.BuildVisModeConjuncts(vm)
            local bracket = "[novehicleui,pet,nooverridebar,nopossessbar"
            if conj ~= "" then bracket = bracket .. "," .. conj:sub(1, -2) end
            bracket = bracket .. "]"
            return "[petbattle] hide; " .. visOptHide .. negGate .. bracket .. " show; hide"
        end
        local petShow
        if vis == "in_combat" then
            petShow = "[combat] show; hide"
        elseif vis == "out_of_combat" then
            petShow = "[nocombat] show; hide"
        elseif vis == "show_dragonriding" then
            petShow = "[advflyable,flying] show; hide"
        elseif vis == "show_not_dragonriding" then
            petShow = "[advflyable,flying] hide; show"
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

    -- Multi-select set: compiled tail; the legacy single-mode chain below
    -- stays byte-identical for every scalar value.
    if vm then
        return EAB.BuildVisibilityStringMulti(hidePrefix, vm)
    end

    -- Append visibility mode conditions
    if vis == "never" then
        return hidePrefix .. "hide"
    elseif vis == "in_combat" then
        return hidePrefix .. "[combat] show; hide"
    elseif vis == "out_of_combat" then
        return hidePrefix .. "[nocombat] show; hide"
    elseif vis == "in_raid" then
        return hidePrefix .. "[group:raid] show; hide"
    elseif vis == "in_party" then
        return hidePrefix .. "[group:party] show; [group:raid] show; hide"
    elseif vis == "solo" then
        return hidePrefix .. "[nogroup] show; hide"
    elseif vis == "show_dragonriding" then
            -- No "mounted": Druid Flight Form is a shapeshift, not a mount, so it
            -- would never match. This covers skyriding mounts and
            -- Flight Form (advflyable excludes ordinary flying)
        return hidePrefix .. "[advflyable,flying] show; hide"
    elseif vis == "show_not_dragonriding" then
            -- Exact inverse of show_dragonriding: hide while dragonriding,
            -- show otherwise. hidePrefix still force-hides in pet battle/vehicle.
        return hidePrefix .. "[advflyable,flying] hide; show"
    end
    return hidePrefix .. "show"
end

-------------------------------------------------------------------------------
--  Managed Non-Secure Visibility
--  XP/Rep bars and extra bars such as Micro/Bag/QueueStatus are not secure
--  bar headers, so they need an explicit runtime visibility pass whenever the
--  player's combat/group/target/mount state changes.
-------------------------------------------------------------------------------
function EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info)
    if not info then return false end
    if info.noManagedVisibility then return false end
    return info.isDataBar or (info.visibilityOnly and not info.isBlizzardMovable)
end

function EAB_VTABLE.ExtraBars.GetManagedNonSecureFrame(info)
    if not EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then return nil end
    if info.isDataBar then
        return dataBarFrames[info.key]
    end
    return info.frameName and _G[info.frameName] or nil
end

function EAB_VTABLE.ExtraBars.GetManagedNonSecureVisibilityState()
    local inCombat = EAB_VTABLE.ExtraBars._managedNonSecureInCombat
    if inCombat == nil then
        inCombat = InCombatLockdown()
    end
    local inRaid = IsInRaid and IsInRaid() or false
    local inGroup = IsInGroup and IsInGroup() or false
    return {
        inCombat = inCombat,
        inRaid = inRaid,
        inParty = inGroup and not inRaid,
    }
end

function EAB_VTABLE.ExtraBars.ShouldShowManagedNonSecureBar(s)
    if not s then return false end
    local vis = EAB.VisibilityCompat.Normalize(s)
    if C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() then
        return false
    end
    if s.enabled == false or s.alwaysHidden then return false end
    if EllesmereUI and EllesmereUI.CheckVisibilityOptions and EllesmereUI.CheckVisibilityOptions(s) then
        return false
    end
    local state = EAB_VTABLE.ExtraBars.GetManagedNonSecureVisibilityState()
    -- Multi-select path (nil = legacy single mode below; the dragonriding
    -- scalar also routes here, same predicate CheckVisibilityMode uses)
    if EllesmereUI and EllesmereUI.EvalVisibilityExtended then
        local ext = EllesmereUI.EvalVisibilityExtended(s, "barVisibility", state, EllesmereUI.VIS_CAPS_INCLUSIVE)
        if ext ~= nil then return ext end
    end
    if EllesmereUI and EllesmereUI.CheckVisibilityMode then
        return EllesmereUI.CheckVisibilityMode(vis, state)
    end
    return vis ~= "never"
end

function EAB_VTABLE.ExtraBars.SetManagedBlizzOwnedSuppressed(frame, reason, suppressed)
    if not frame then return end

    local ffd = EFD(frame)
    local suppressKey = (reason == "petbattle") and "suppressedByPetBattle" or "suppressedByVisibility"
    local shownKey = (reason == "petbattle") and "wasShownBeforePetBattle" or "wasShownBeforeVisibility"

    if suppressed then
        if not ffd[suppressKey] then
            ffd[shownKey] = frame:IsShown()
        end
        ffd[suppressKey] = true
        frame:Hide()
        return
    end

    if ffd[suppressKey] then
        local wasShown = ffd[shownKey]
        ffd[suppressKey] = nil
        ffd[shownKey] = nil
        if wasShown then
            frame:Show()
        end
    end
end

function EAB_VTABLE.ExtraBars.ApplyManagedNonSecureAlpha(info, frame, s)
    if not frame or not s or not frame:IsShown() then return end

    local hstate = hoverStates[info.key]
    if s.mouseoverEnabled then
        if hstate and hstate.isHovered then
            frame:SetAlpha(1)
            hstate.fadeDir = "in"
        else
            frame:SetAlpha(0)
            if hstate then hstate.fadeDir = "out" end
        end
    else
        frame:SetAlpha(s.mouseoverAlpha or 1)
        if hstate then hstate.fadeDir = nil end
    end
end

function EAB_VTABLE.ExtraBars.ApplyManagedMouse(frame, blizzOwnedVisibility, s, shouldShow)
    if not frame or not s then return end

    shouldShow = (shouldShow ~= false)
    -- Blizzard-owned frames (QueueStatusButton) manage their own mouse
    -- state; overriding it disables clicking/hovering after every
    -- visibility refresh.
    if blizzOwnedVisibility then
        return
    elseif s.mouseoverEnabled and s.clickThrough then
        SafeEnableMouseMotionOnly(frame, shouldShow)
    else
        SafeEnableMouse(frame, shouldShow and not s.clickThrough)
    end
end

function EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(info, frame, s, shouldShow, allowShow)
    if not frame or not s then return end

    -- Show/hide the holder BEFORE the Blizzard frame so the parent has
    -- valid screen coordinates when the child's Show() triggers Blizzard
    -- Layout callbacks that call GetCenter().
    if not info.isDataBar then
        local holder = extraBarHolders[info.key]
        if holder then
            if shouldShow then holder:Show() else holder:Hide() end
        end
    end

    if info.blizzOwnedVisibility then
        EAB_VTABLE.ExtraBars.SetManagedBlizzOwnedSuppressed(frame, "visibility", not shouldShow)
    elseif shouldShow then
        if allowShow ~= false then
            frame:Show()
        end
    else
        frame:Hide()
    end

    if shouldShow then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecureAlpha(info, frame, s)
    end
    EAB_VTABLE.ExtraBars.ApplyManagedMouse(frame, info.blizzOwnedVisibility, s, shouldShow)
end

function EAB_VTABLE.ExtraBars.ApplyManagedNonSecureVisibility(info)
    if not EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then return false, nil, nil end

    local s = EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars[info.key]
    local frame = EAB_VTABLE.ExtraBars.GetManagedNonSecureFrame(info)
    if not s or not frame then return false, frame, s end

    local shouldShow = EAB_VTABLE.ExtraBars.ShouldShowManagedNonSecureBar(s)

    -- Data bars always route through their update func: the hidden path ends
    -- in the same presentation call via BeginManagedDataBarUpdate, and bars
    -- with event arming (House Favor) need the call to disarm when hidden.
    if info.isDataBar and frame._updateFunc then
        frame._updateFunc()
    else
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(info, frame, s, shouldShow, not info.isDataBar)
    end

    return shouldShow, frame, s
end

function EAB_VTABLE.ExtraBars.RefreshManagedNonSecureVisibility()
    for _, info in ipairs(EXTRA_BARS) do
        if EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then
            EAB_VTABLE.ExtraBars.ApplyManagedNonSecureVisibility(info)
        end
    end
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
                if info.noManagedVisibility then
                    -- skip
                else
                local key = info.key
                local s = EAB.db and EAB.db.profile.bars[key]
                if s and not s.alwaysHidden then
                    local frame
                    if EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then
                        frame = EAB_VTABLE.ExtraBars.GetManagedNonSecureFrame(info)
                    elseif info.isBlizzardMovable then
                        frame = blizzMovableHolders[key]
                    else
                        frame = _G[info.frameName]
                    end
                    if frame then
                        if shouldHide then
                            if info.blizzOwnedVisibility then
                                EAB_VTABLE.ExtraBars.SetManagedBlizzOwnedSuppressed(frame, "petbattle", true)
                            else
                                frame:Hide()
                            end
                        else
                            if info.blizzOwnedVisibility then
                                EAB_VTABLE.ExtraBars.SetManagedBlizzOwnedSuppressed(frame, "petbattle", false)
                            end
                            if EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then
                                EAB_VTABLE.ExtraBars.ApplyManagedNonSecureVisibility(info)
                            else
                                frame:Show()
                            end
                        end
                    end
                end
            end -- if s
            end -- if not noManagedVisibility
        end
    end
    -- Register the state driver: hide during pet battle, show otherwise
    RegisterStateDriver(_extraBarVisProxy, "extravis", "[petbattle] hide; show")
end

--  Combat Show/Hide, Runtime Visibility, Click-Through, Housing
-------------------------------------------------------------------------------
function EAB:ApplyCombatVisibility()
    if InCombatLockdown() then return end
    for _, info in ipairs(ALL_BARS) do
        local key = info.key
        local s = self.db.profile.bars[key]
        if s then
            local frame = barFrames[key] or (info.isDataBar and dataBarFrames[key]) or (info.isBlizzardMovable and blizzMovableHolders[key]) or (extraBarHolders[key]) or (info.visibilityOnly and _G[info.frameName])
            if frame and not info.visibilityOnly then
                local newStr
                if s.alwaysHidden then
                    newStr = "hide"
                elseif EllesmereUI.CheckVisibilityOptionsNonMacro and EllesmereUI.CheckVisibilityOptionsNonMacro(s) then
                    newStr = "hide"
                else
                    newStr = BuildVisibilityString(info, s)
                end
                -- Skip re-registration if driver string is unchanged (avoids blink from re-evaluation)
                if frame._eabLastVisStr ~= newStr then

                    frame._eabLastVisStr = newStr
                    RegisterAttributeDriver(frame, "state-visibility", newStr)
                end
            end
        end
    end
    -- Apply pet battle / vehicle hiding for extra bars (MicroBar, BagBar,
    -- data bars).  These use a dedicated secure proxy since they are not
    -- SecureHandlerStateTemplate frames themselves.
    self:ApplyExtraBarVisibility()
end

-- True when at least one bar uses "Hide when No Target". The soft-target poll is
-- gated on this so it costs nothing for users who don't use the feature. Cheap
-- (early-exits on the first match); recomputed on every visibility refresh below
-- and once at setup, so it can never desync from the bar settings.
function EAB:_RefreshSoftTargetGate()
    local any = false
    for _, info in ipairs(ALL_BARS) do
        local s = self.db.profile.bars[info.key]
        if s and s.visHideNoTarget then any = true; break end
    end
    self._anyHideNoTarget = any
end

function EAB:RefreshRuntimeVisibility()
    self:_RefreshSoftTargetGate()
    for _, info in ipairs(ALL_BARS) do
        local key = info.key
        local s = self.db.profile.bars[key]
        if not s then -- skip bars without settings (not yet initialized)
        elseif EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then
            EAB_VTABLE.ExtraBars.ApplyManagedNonSecureVisibility(info)
        else
        local frame = barFrames[key] or (info.isDataBar and dataBarFrames[key]) or (info.isBlizzardMovable and blizzMovableHolders[key]) or (extraBarHolders[key]) or (info.visibilityOnly and _G[info.frameName])
        if frame then
            local vis = s.barVisibility or "always"
            local isHidden = (vis == "never") or s.alwaysHidden
            -- Runtime "Toggle Action Bar" override (keybind-driven, NOT persisted):
            -- flips a bar between always-shown and hidden without touching the saved
            -- barVisibility. Only ever set for bars whose saved mode is always/never.
            local _visToggleOv = EAB._visOverride and EAB._visOverride[key]
            if _visToggleOv then
                vis = _visToggleOv
                isHidden = (_visToggleOv == "never")
            end
            if ShouldQuickKeybindSurfaceBar(s) and barFrames[key] and frame == barFrames[key] then
                if not InCombatLockdown() then
                    RegisterAttributeDriver(frame, "state-visibility", "show")
                    -- Keep the cache in sync (see EAB_UpdateQuickKeybindVisibility):
                    -- a stale cache makes QKB exit skip restoring the real driver.
                    frame._eabLastVisStr = "show"
                    frame:Show()
                    SafeEnableMouseMotionOnly(frame, true)
                end
                -- QuickKeybind temporarily surfaces managed action bars when
                -- runtime conditions hide them, but not when the user chose
                -- an explicit "Never" visibility mode.
            elseif isHidden then
                if not info.visibilityOnly and not InCombatLockdown() then
                    if frame._eabLastVisStr ~= "hide" then

                        frame._eabLastVisStr = "hide"
                        RegisterAttributeDriver(frame, "state-visibility", "hide")
                    end
                elseif info.visibilityOnly then
                    frame:Hide()
                    if info.blizzOwnedVisibility then
                        local bf = _G[info.frameName]
                        if bf then bf:Hide() end
                    end
                end
                if not InCombatLockdown() then
                    SafeEnableMouse(frame, false)
                end
            else
                if not info.visibilityOnly and not InCombatLockdown() then
                    local newStr
                    if _visToggleOv == "always" then
                        -- Forced-show via the toggle keybind: ignore the saved mode
                        -- (which may be "never") and any non-macro hide options.
                        newStr = BuildVisibilityString(info, s, "always")
                    elseif EllesmereUI.CheckVisibilityOptionsNonMacro and EllesmereUI.CheckVisibilityOptionsNonMacro(s) then
                        newStr = "hide"
                    else
                        newStr = BuildVisibilityString(info, s)
                    end
                    if frame._eabLastVisStr ~= newStr then

                        frame._eabLastVisStr = newStr
                        RegisterAttributeDriver(frame, "state-visibility", newStr)
                    end
                end
                if not InCombatLockdown() then
                    if vis ~= "in_combat" and vis ~= "out_of_combat" and not s.combatShowEnabled then
                        -- Only Show frames without a state-visibility driver.
                        -- Frames with a driver (any _eabLastVisStr) are managed by the driver.
                        if not info.isBlizzardMovable and not info.blizzOwnedVisibility and not frame._eabLastVisStr then
                            frame:Show()
                        end
                    end
                    if barFrames[key] and frame == barFrames[key] then
                        SafeEnableMouseMotionOnly(frame, not s.clickThrough or s.mouseoverEnabled)
                    elseif info.noManagedVisibility then
                        -- skip: Blizzard owns mouse state (e.g. QueueStatusButton)
                    elseif info.isBlizzardMovable or info.blizzOwnedVisibility then
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
end

-------------------------------------------------------------------------------
--  Myslot compatibility
--  Myslot exports settings by automating a PickupAction + PlaceAction on every
--  populated action slot (60+ in a row). With bars/buttons that hide empty
--  slots or use conditional visibility, each pickup/place forces a costly
--  secure show/hide pass; back-to-back that stalls the client for many seconds.
--
--  The user-confirmed cure is the "Visibility: Always + Always Show Buttons"
--  config, so while Myslot's window is open we apply exactly that to every bar
--  (the same change the options toggles make). To do it SAFELY we back each
--  bar's real visibility settings up to the saved variables BEFORE overwriting,
--  then restore on close. Because the backup is persisted, a /reload (or
--  logout) with the window still open can never strand the user on "always":
--  EAB:OnInitialize calls RestoreMyslotBackup unconditionally on the next
--  login, before any bar is built, so the swap is always undone.
-------------------------------------------------------------------------------
-- Settings swapped to force a bar fully visible. Listed once so backup and
-- overwrite stay in sync. Wrapped in do/end (with the two methods below) so
-- this stays a block upvalue, not a chunk-level local -- this file sits at
-- Lua 5.1's 200-local-per-chunk cap.
do
local MYSLOT_VIS_FIELDS = {
    "barVisibility", "alwaysHidden", "mouseoverEnabled", "mouseoverAlpha",
    "_savedBarAlpha", "combatShowEnabled", "combatHideEnabled", "alwaysShowButtons",
    -- Multi-select set: backed up by reference (the shared setter assigns a
    -- fresh table on every write, so the captured table never mutates) and
    -- restored/cleared like any other field.
    "visibilityModes",
}

-- Restore real visibility settings from the persisted backup, then clear it.
-- Safe to call anytime (no-op if no backup). NOT gated on Myslot being enabled,
-- so it self-heals even if Myslot was disabled since the backup was written.
function EAB:RestoreMyslotBackup()
    local backup = self.db and self.db.profile and self.db.profile._myslotVisBackup
    if not backup then return false end
    for key, saved in pairs(backup) do
        local s = self.db.profile.bars[key]
        if s then
            for _, f in ipairs(MYSLOT_VIS_FIELDS) do s[f] = saved[f] end
        end
    end
    self.db.profile._myslotVisBackup = nil
    return true
end

function EAB:SetMyslotForceShow(on)
    on = not not on
    -- The persisted backup's presence IS the "are we forcing" state, so this
    -- survives /reload without a separate flag.
    local forcing = self.db.profile._myslotVisBackup ~= nil
    if on == forcing then return end

    if on then
        -- Capture real values and PERSIST the backup BEFORE overwriting, so the
        -- backup always exists if any field was changed (crash/reload-safe).
        local backup = {}
        for _, info in ipairs(BAR_CONFIG) do
            local s = self.db.profile.bars[info.key]
            if s then
                local saved = {}
                for _, f in ipairs(MYSLOT_VIS_FIELDS) do saved[f] = s[f] end
                backup[info.key] = saved
            end
        end
        self.db.profile._myslotVisBackup = backup
        -- Overwrite to "always" + "always show buttons" (mirrors the options'
        -- ApplyVisibilityKey("always"), incl. restoring a mouseover bar's real
        -- alpha so it doesn't stay faded).
        for _, info in ipairs(BAR_CONFIG) do
            local s = self.db.profile.bars[info.key]
            if s then
                local wasMouseover = s.mouseoverEnabled
                s.barVisibility = "always"
                -- A lingering multi-select set would stay authoritative over
                -- the forced "always"; the backup above already captured it.
                s.visibilityModes = nil
                s.alwaysHidden = false
                s.mouseoverEnabled = false
                if wasMouseover and s._savedBarAlpha then
                    s.mouseoverAlpha = s._savedBarAlpha
                    s._savedBarAlpha = nil
                end
                s.combatShowEnabled = false
                s.combatHideEnabled = false
                s.alwaysShowButtons = true
            end
        end
    else
        self:RestoreMyslotBackup()
    end

    -- Re-apply -- the same calls the options "Visibility"/"Always Show Buttons"
    -- toggles make, now that the real settings reflect the desired state.
    if not InCombatLockdown() then
        self:RefreshRuntimeVisibility()
        self:RefreshMouseover()
        self:ApplyCombatVisibility()
        for _, info in ipairs(BAR_CONFIG) do
            self:ApplyAlwaysShowButtons(info.key)
        end
    end
    if EllesmereUI and EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
end
end -- do: MYSLOT_VIS_FIELDS scope

do
    -- Only wire up the integration when the user has Myslot enabled. When it is
    -- not, the watcher is never created and SetMyslotForceShow never runs, so no
    -- settings are ever swapped. (The OnInitialize restore still runs regardless,
    -- so a leftover backup from when Myslot was enabled always self-heals.)
    local function MyslotEnabled()
        if C_AddOns and C_AddOns.GetAddOnEnableState then
            return C_AddOns.GetAddOnEnableState("Myslot") > 0
        end
        return true
    end
    if MyslotEnabled() then
        -- Myslot exposes its main window via LibStub("Myslot-5.0").MainFrame.
        -- Hook its show/hide to toggle the force-show override. No-op if Myslot
        -- exposes no frame.
        local hooked = false
        local function TryHookMyslot()
            if hooked or not LibStub then return hooked end
            local lib = LibStub:GetLibrary("Myslot-5.0", true)
            local frame = lib and lib.MainFrame
            if not frame then return false end
            hooked = true
            frame:HookScript("OnShow", function() EAB:SetMyslotForceShow(true) end)
            frame:HookScript("OnHide", function() EAB:SetMyslotForceShow(false) end)
            if frame:IsShown() then EAB:SetMyslotForceShow(true) end
            return true
        end
        local watcher = CreateFrame("Frame")
        watcher:RegisterEvent("PLAYER_LOGIN")
        watcher:RegisterEvent("ADDON_LOADED")
        watcher:SetScript("OnEvent", function()
            if TryHookMyslot() then watcher:UnregisterAllEvents() end
        end)
    end
end

-------------------------------------------------------------------------------
--  "Toggle Action Bar" visibility keybind
--  A per-bar keybind that flips a bar between always-shown and hidden at RUNTIME
--  only -- the saved barVisibility is never written, so the toggle does not
--  persist across sessions (a /reload restores the saved state). Only meaningful
--  when the bar's saved visibility is "always" or "never", and only out of combat
--  (changing a secure frame's state-visibility driver is combat-blocked).
--  The keybind itself IS saved per-bar (s.toggleVisKey) and re-applied on login.
--
--  Bindings are keyed by the PRESSED KEY, not the bar, so a single key assigned
--  to several bars toggles them all as a synced group: one press hides every
--  bound bar that is currently shown, the next press shows them all.
-------------------------------------------------------------------------------

-- Toggle every bar bound to `key` as a group. If any participant is currently
-- shown, hide them all; otherwise show them all. Only bars whose saved mode is
-- "always"/"never" participate. Runtime-only -- never writes barVisibility.
function EAB:ToggleVisKey(key)
    if InCombatLockdown() or not key then return end
    local participants, anyShown = {}, false
    for _, info in ipairs(ALL_BARS) do
        local s = self.db.profile.bars[info.key]
        if s and s.toggleVisKey == key then
            local saved = s.barVisibility or "always"
            if saved == "always" or saved == "never" then
                participants[#participants + 1] = info.key
                local eff = (self._visOverride and self._visOverride[info.key]) or saved
                if eff == "always" then anyShown = true end
            end
        end
    end
    if #participants == 0 then return end
    local target = anyShown and "never" or "always"
    self._visOverride = self._visOverride or {}
    for _, bk in ipairs(participants) do
        self._visOverride[bk] = target
    end
    self:RefreshRuntimeVisibility()
end

-- Drop a bar's runtime toggle override so its saved visibility takes effect
-- again (called when the visibility dropdown changes in options).
function EAB:ClearVisToggleOverride(barKey)
    if self._visOverride then self._visOverride[barKey] = nil end
end

-- Rebuild override bindings from the saved per-bar keys: one pooled button per
-- UNIQUE key (so a key shared by several bars drives all of them). A key is only
-- bound if at least one bar using it has a saved always/never mode, so a shared
-- key never dead-overrides the player's normal binding. Binding APIs are
-- combat-protected, so defer to PLAYER_REGEN_ENABLED in combat.
function EAB:RebuildVisToggleBindings()
    if InCombatLockdown() then
        if not self._visToggleCombatFrame then
            local f = CreateFrame("Frame")
            f:SetScript("OnEvent", function(self2)
                self2:UnregisterEvent("PLAYER_REGEN_ENABLED")
                EAB:RebuildVisToggleBindings()
            end)
            self._visToggleCombatFrame = f
        end
        self._visToggleCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    -- Unique keys that have at least one participating (always/never) bar.
    local keys, seen = {}, {}
    for _, info in ipairs(ALL_BARS) do
        local s = self.db.profile.bars[info.key]
        local k = s and s.toggleVisKey
        if k and k ~= "" and not seen[k] then
            local saved = s.barVisibility or "always"
            if saved == "always" or saved == "never" then
                seen[k] = true
                keys[#keys + 1] = k
            end
        end
    end
    -- Clear every pooled button's binding, then (re)assign one per unique key.
    self._visToggleBtnPool = self._visToggleBtnPool or {}
    for _, btn in ipairs(self._visToggleBtnPool) do
        ClearOverrideBindings(btn)
    end
    for i, k in ipairs(keys) do
        local btn = self._visToggleBtnPool[i]
        if not btn then
            btn = CreateFrame("Button", "EUIVisToggleKeyBtn" .. i, UIParent)
            btn:Hide()
            self._visToggleBtnPool[i] = btn
        end
        local thisKey = k
        btn:SetScript("OnClick", function() EAB:ToggleVisKey(thisKey) end)
        SetOverrideBindingClick(btn, true, k, btn:GetName())
    end
end

function EAB:ApplyClickThroughForBar(barKey)
    local s = self.db.profile.bars[barKey]
    if not s then return end

    -- Data bars
    local dataFrame = dataBarFrames[barKey]
    if dataFrame then
        EAB_VTABLE.ExtraBars.ApplyManagedMouse(dataFrame, false, s, dataFrame:IsShown())
        return
    end

    -- Extra bars (MicroBar, BagBar, QueueStatus)
    for _, info in ipairs(EXTRA_BARS) do
        if info.key == barKey and not info.isDataBar and not info.isBlizzardMovable then
            if info.blizzOwnedVisibility then
                local holder = extraBarHolders[barKey]
                if holder then SafeEnableMouse(holder, false) end
                local bf = _G[info.frameName]
                if bf then SafeEnableMouse(bf, true) end
            else
                local frame = _G[info.frameName]
                if frame then SafeEnableMouse(frame, not s.clickThrough) end
            end
            return
        end
    end

    -- Action bars
    local frame = barFrames[barKey]
    if not frame then return end
    local buttons = barButtons[barKey]
    if not buttons then return end

    local enable = ShouldQuickKeybindSurfaceBar(s) or not s.clickThrough
    -- When click-through is on but mouseover is enabled, keep mouse motion
    -- so OnEnter/OnLeave still fire for hover fade.
    local motionOnly = not enable and s.mouseoverEnabled
    -- Bar frame only needs mouse motion (for hover detection); clicks pass through
    -- to the buttons or to frames behind the bar.
    SafeEnableMouseMotionOnly(frame, enable or motionOnly)
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
                if enable then
                    SafeEnableMouse(btn, true)
                elseif motionOnly then
                    SafeEnableMouseMotionOnly(btn, true)
                else
                    SafeEnableMouse(btn, false)
                end
            end
        end
    end
end

function EAB:UpdateHousingVisibility()
    -- Defer to next frame to avoid taint from secure execution paths
    -- (e.g. CameraOrSelectOrMoveStop triggering PLAYER_MOUNT_DISPLAY_CHANGED)
    C_Timer.After(0, function()
        if InCombatLockdown() then return end
        if _quickKeybindState.open then return end
        -- Check non-macro visibility options here. Secure frames still use the
        -- state driver for target/enemy conditions, but mounted-like druid
        -- forms are also handled here to cover cases [mounted] does not match.
        local function ShouldHideNonMacro(s)
            if not s then return false end
            if s.visHideNoTarget then
                -- [noexists] in the state driver handles the basic
                -- has-target check even in combat. Out of combat, we
                -- additionally hide when a soft target is the only
                -- "target". Macro conditionals treat soft-interact/
                -- softenemy/softfriend as "target exists" but
                -- UnitExists("target") does not, so check the soft
                -- unit tokens directly.
                if not UnitExists("target") and (UnitExists("softinteract") or UnitExists("softenemy") or UnitExists("softfriend")) then return true end
            end
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
                if C_Housing and C_Housing.IsInsideHouseOrPlot and C_Housing.IsInsideHouseOrPlot() then
                    return true
                end
            end
            if s.visHideMounted then
                -- Regular mounts are handled entirely by the secure "[mounted]
                -- hide" clause in the state driver, which self-updates even in
                -- combat -- so the bar reappears the instant the player is
                -- dazed/knocked off a mount. Clobbering the driver with a
                -- literal "hide" here would freeze it hidden until combat ends,
                -- because this handler bails during InCombatLockdown and the
                -- dismount event (PLAYER_MOUNT_DISPLAY_CHANGED) can no longer
                -- re-evaluate a dead constant string. Only druid travel/flight
                -- forms need this non-secure fallback, since [mounted] does not
                -- match shapeshift forms.
                if not (IsMounted and IsMounted())
                    and EllesmereUI and EllesmereUI.IsPlayerMountedLike and EllesmereUI.IsPlayerMountedLike() then
                    return true
                end
            end
            return false
        end

        for _, info in ipairs(ALL_BARS) do
            local key = info.key
            local s = self.db.profile.bars[key]
            if s then
                if EAB_VTABLE.ExtraBars.IsManagedNonSecureBar(info) then
                    EAB_VTABLE.ExtraBars.ApplyManagedNonSecureVisibility(info)
                else
                    local frame = barFrames[key] or (info.isDataBar and dataBarFrames[key]) or (info.isBlizzardMovable and blizzMovableHolders[key]) or (extraBarHolders[key]) or (info.visibilityOnly and _G[info.frameName])
                if frame then
                    -- Secure action bar frames use the state driver for
                    -- target/enemy options; mounted-like druid forms are
                    -- additionally handled in ShouldHideNonMacro().
                    -- Non-secure frames (data bars, extra bars, visibility-only)
                    -- need the full check since they have no state driver.
                    local isSecure = not info.visibilityOnly and not info.isDataBar and not info.isBlizzardMovable and barFrames[key]
                    local shouldHide = isSecure and ShouldHideNonMacro(s) or (not isSecure and EllesmereUI.CheckVisibilityOptions(s))
                    -- Runtime "Toggle Action Bar" keybind override wins over the saved
                    -- mode and the non-macro hide checks, exactly as RefreshRuntimeVisibility
                    -- does. Without these two branches any event routed through here
                    -- (target change, group/mount/housing) re-applies the saved visibility
                    -- and re-shows a bar the player toggled off with its keybind. Secure
                    -- managed bars only (the override is never set for other frame types).
                    local _visToggleOv = isSecure and self._visOverride and self._visOverride[key]
                    if _visToggleOv == "never" then
                        if frame._eabLastVisStr ~= "hide" then
                            frame._eabLastVisStr = "hide"
                            RegisterAttributeDriver(frame, "state-visibility", "hide")
                        end
                    elseif _visToggleOv == "always" then
                        local ovStr = BuildVisibilityString(info, s, "always")
                        if frame._eabLastVisStr ~= ovStr then
                            frame._eabLastVisStr = ovStr
                            RegisterAttributeDriver(frame, "state-visibility", ovStr)
                        end
                    elseif shouldHide then
                        if isSecure then
                            if frame._eabLastVisStr ~= "hide" then

                                frame._eabLastVisStr = "hide"
                                RegisterAttributeDriver(frame, "state-visibility", "hide")
                            end
                        elseif info.blizzOwnedVisibility then
                            local bf = _G[info.frameName]
                            if bf then
                                EFD(bf).visWasShown = bf:IsShown()
                                bf:Hide()
                            end
                        else
                            frame:Hide()
                        end
                    elseif not s.alwaysHidden and (s.barVisibility or "always") ~= "never" then
                        if isSecure then
                            local newStr = BuildVisibilityString(info, s)
                            if frame._eabLastVisStr ~= newStr then

                                frame._eabLastVisStr = newStr
                                RegisterAttributeDriver(frame, "state-visibility", newStr)
                            end
                        elseif info.blizzOwnedVisibility then
                            local bf = _G[info.frameName]
                            if bf and EFD(bf).visWasShown then
                                bf:Show()
                            end
                            if bf then EFD(bf).visWasShown = nil end
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

do
local function _setupBorderEdges(btn, storeKey, driverTex)
    -- Edge state lives in EFD, never on the button table: StanceBar/PetBar
    -- flow through here with BLIZZARD-owned buttons (StanceButton/
    -- PetActionButton), which must never receive custom keys.
    local edges = EFD(btn)[storeKey]
    if not edges then
        edges = {}
        for j = 1, 4 do
            local t = btn:CreateTexture(nil, "OVERLAY", nil, 2)
            t:SetColorTexture(1, 1, 1, 1)
            t:Hide()
            edges[j] = t
        end
        EFD(btn)[storeKey] = edges
        if driverTex then
            hooksecurefunc(driverTex, "Show", function()
                if not edges._active then return end
                for j = 1, 4 do edges[j]:Show() end
            end)
            hooksecurefunc(driverTex, "Hide", function()
                for j = 1, 4 do edges[j]:Hide() end
            end)
        end
    end
    return edges
end

local function _applyBorderEdges(edges, btn, brdSize, cr, cg, cb)
    edges._active = true
    local anchor = btn.icon or btn.Icon or btn
    local PP = EllesmereUI.PP
    for j = 1, 4 do edges[j]:SetVertexColor(cr, cg, cb, 1) end
    edges[1]:ClearAllPoints(); edges[1]:SetPoint("TOPLEFT", anchor); edges[1]:SetPoint("TOPRIGHT", anchor)
    if PP then PP.Height(edges[1], brdSize) else edges[1]:SetHeight(brdSize) end
    edges[2]:ClearAllPoints(); edges[2]:SetPoint("BOTTOMLEFT", anchor); edges[2]:SetPoint("BOTTOMRIGHT", anchor)
    if PP then PP.Height(edges[2], brdSize) else edges[2]:SetHeight(brdSize) end
    edges[3]:ClearAllPoints(); edges[3]:SetPoint("TOPLEFT", edges[1], "BOTTOMLEFT"); edges[3]:SetPoint("BOTTOMLEFT", edges[2], "TOPLEFT")
    if PP then PP.Width(edges[3], brdSize) else edges[3]:SetWidth(brdSize) end
    edges[4]:ClearAllPoints(); edges[4]:SetPoint("TOPRIGHT", edges[1], "BOTTOMRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT", edges[2], "TOPRIGHT")
    if PP then PP.Width(edges[4], brdSize) else edges[4]:SetWidth(brdSize) end
end

local function _hideBorderEdges(btn, storeKey)
    local edges = EFD(btn)[storeKey]
    if not edges then return end
    edges._active = false
    for j = 1, 4 do edges[j]:Hide() end
end
ns._setupBorderEdges = _setupBorderEdges
ns._applyBorderEdges = _applyBorderEdges
ns._hideBorderEdges  = _hideBorderEdges
end

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
                    if p.useBlizzardStyle then
                        btn.PushedTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Down", true)
                        btn.PushedTexture:SetDrawLayer("OVERLAY", 7)
                        btn.PushedTexture:ClearAllPoints()
                        btn.PushedTexture:SetAllPoints(btn)
                        btn.PushedTexture:SetVertexColor(1, 1, 1, 1)
                        btn.PushedTexture:SetAlpha(1)
                        ns._hideBorderEdges(btn, "_pushedBorder")
                    elseif pType == 6 then
                        btn.PushedTexture:SetAlpha(0)
                        ns._hideBorderEdges(btn, "_pushedBorder")
                    elseif pType == 5 then
                        btn.PushedTexture:SetAlpha(0)
                        local edges = ns._setupBorderEdges(btn, "_pushedBorder", btn.PushedTexture)
                        ns._applyBorderEdges(edges, btn, brdSize, cr, cg, cb)
                    else
                        btn.PushedTexture:SetAlpha(1)
                        ns._hideBorderEdges(btn, "_pushedBorder")
                        if pType <= 3 then
                            SetSquareTexture(btn.PushedTexture, HIGHLIGHT_TEXTURES[pType] or HIGHLIGHT_TEXTURES[2])
                            btn.PushedTexture:SetVertexColor(cr, cg, cb, 1)
                        elseif pType == 4 then
                            btn.PushedTexture:SetColorTexture(cr, cg, cb, 0.35)
                        end
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Pushed-State Flash
--  SetOverrideBinding routes keybinds to native engine commands (ACTIONBUTTON1
--  etc.) so the engine fires the action directly without clicking our buttons.
--  Our buttons never enter PUSHED state from keyboard.  Fix: hook UseAction
--  to show PushedTexture, global keyup watcher to hide all active textures.
-------------------------------------------------------------------------------
do
    local _pushedHooked = false
    local _activePushed = {}  -- btn -> true
    local _activePushedN = 0
    local _btnKeys = {}       -- btn -> { k1, k2 } (reused, no alloc per press)
    local _pollFrame
    function EAB:HookPushedFlash()
        if _pushedHooked then return end
        _pushedHooked = true
        _pollFrame = CreateFrame("Frame")
        _pollFrame:SetScript("OnUpdate", function()
            if _activePushedN == 0 then
                _pollFrame:Hide()
                return
            end
            for btn in pairs(_activePushed) do
                local keys = _btnKeys[btn]
                local held = false
                if keys then
                    for i = 1, #keys do
                        if IsKeyDown(keys[i]) then held = true; break end
                    end
                end
                if not held then
                    if btn.PushedTexture then btn.PushedTexture:Hide() end
                    _activePushed[btn] = nil
                    _activePushedN = _activePushedN - 1
                end
            end
            if _activePushedN == 0 then _pollFrame:Hide() end
        end)
        _pollFrame:Hide()
        -- ActionButtonDown fires on key press regardless of "cast on key down"
        -- CVar. This ensures pushed texture shows while the key is held for
        -- both key-down and key-up casting modes.
        -- Extract base key from compound binding (e.g. "SHIFT-1" → "1",
        -- "CTRL-Q" → "Q"). IsKeyDown only accepts raw key names.
        local function BaseKey(binding)
            if not binding then return nil end
            return binding:match("[^%-]+$")
        end
        local function ShowPushedForSlot(slot)
            local prof = EAB.db and EAB.db.profile
            if not prof then return end
            if not prof.useBlizzardStyle and (prof.pushedTextureType or 2) == 6 then return end
            local btn = allButtons[slot]
            if not btn or not btn.PushedTexture then return end
            local cmd = btn.commandName
            if not cmd then return end
            local k1, k2 = GetBindingKey(cmd)
            if not k1 then return end
            local keys = _btnKeys[btn]
            if not keys then keys = {}; _btnKeys[btn] = keys end
            keys[1] = BaseKey(k1); keys[2] = BaseKey(k2); keys[3] = nil
            btn.PushedTexture:Show()
            if not _activePushed[btn] then
                _activePushed[btn] = true
                _activePushedN = _activePushedN + 1
            end
            _pollFrame:Show()
        end
        -- ActionButtonDown/MultiActionButtonDown fire on key press regardless
        -- of "cast on key down" CVar. This ensures pushed texture shows while
        -- the key is held for both key-down and key-up casting modes.
        hooksecurefunc("ActionButtonDown", function(id) ShowPushedForSlot(id) end)
        if MultiActionButtonDown then
            local multiBarPage = {
                MultiBarBottomLeft  = 6,
                MultiBarBottomRight = 5,
                MultiBarRight       = 3,
                MultiBarLeft        = 4,
                MultiBar5           = 13,
                MultiBar6           = 14,
                MultiBar7           = 15,
            }
            hooksecurefunc("MultiActionButtonDown", function(barName, id)
                local page = multiBarPage[barName]
                if not page then return end
                local slot = (page - 1) * 12 + id
                ShowPushedForSlot(slot)
            end)
        end
    end
end

function EAB:ApplyHighlightTextures()
    local p = self.db.profile
    local hType = p.highlightTextureType or 2
    local useCC = p.highlightUseClassColor
    local customC = p.highlightCustomColor or { r=0.973, g=0.839, b=0.604, a=1 }
    local brdSize = p.highlightBorderSize or 4

    local cr, cg, cb = customC.r, customC.g, customC.b
    if useCC then
        local _, ct = UnitClass("player")
        if ct then local cc = RAID_CLASS_COLORS[ct]; if cc then cr, cg, cb = cc.r, cc.g, cc.b end end
    end

    for _, info in ipairs(BAR_CONFIG) do
        if p.useBlizzardStyle then
            -- skip -- let Blizzard handle highlight textures
        else
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and btn.HighlightTexture then
                    if hType == 6 then
                        btn.HighlightTexture:SetAlpha(0)
                        ns._hideBorderEdges(btn, "_highlightBorder")
                    elseif hType == 5 then
                        btn.HighlightTexture:SetAlpha(0)
                        local edges = ns._setupBorderEdges(btn, "_highlightBorder")
                        ns._applyBorderEdges(edges, btn, brdSize, cr, cg, cb)
                        if not EFD(btn).hlBorderHooked then
                            EFD(btn).hlBorderHooked = true
                            btn:HookScript("OnEnter", function(self)
                                local be = EFD(self)._highlightBorder
                                if be and be._active then for j = 1, 4 do be[j]:Show() end end
                            end)
                            btn:HookScript("OnLeave", function(self)
                                local be = EFD(self)._highlightBorder
                                if be then for j = 1, 4 do be[j]:Hide() end end
                            end)
                        end
                    else
                        btn.HighlightTexture:SetAlpha(1)
                        ns._hideBorderEdges(btn, "_highlightBorder")
                        if hType <= 3 then
                            SetSquareTexture(btn.HighlightTexture, HIGHLIGHT_TEXTURES[hType] or HIGHLIGHT_TEXTURES[1])
                            btn.HighlightTexture:SetVertexColor(cr, cg, cb, 1)
                        elseif hType == 4 then
                            btn.HighlightTexture:SetColorTexture(cr, cg, cb, 0.35)
                        end
                    end
                end
                _quickKeybindState.art.RefreshButton(btn)
            end
        end
        end -- useBlizzardStyle
    end

    -- Blizzard-owned special buttons do not flow through the standard bar
    -- button setup, but QuickKeybind still resets their overlay atlas.
    -- Keep their QuickKeybind highlight aligned with the EUI button art too.
    _quickKeybindState.art.ForEachSpecialButton(_quickKeybindState.art.InitializeButton)
end

-------------------------------------------------------------------------------
--  Custom Proc Glow (FlipBook-based, no LibCustomGlow)
--  Hooks Blizzard's SpellActivationAlert to reconfigure the FlipBook
--  textures/animations with user-selected glow styles.
-------------------------------------------------------------------------------

-- Loop glow types: atlas-based Blizzard FlipBook styles + procedural engines
local LOOP_GLOW_TYPES = {
    { name = "Pixel Glow",           procedural = true },
    { name = "Custom Proc Glow",     buttonGlow = true },
    { name = "Auto-Cast Shine",      autocast = true },
    { name = "Shape Glow",           shapeGlow = true },
    { name = "GCD",                  atlas = "RotationHelper_Ants_Flipbook", texPadding = 1.6 },
    { name = "Modern WoW Glow",      atlas = "UI-HUD-ActionBar-Proc-Loop-Flipbook", texPadding = 1.4 },
    { name = "Classic WoW Glow",     texture = "Interface\\SpellActivationOverlay\\IconAlertAnts",
      rows = 5, columns = 5, frames = 25, duration = 0.3, frameW = 48, frameH = 48, texPadding = 1.25 },
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
local _G_Glows = EllesmereUI.Glows
ns.Glows = _G_Glows

local function StopAllProceduralGlows(wrapper)
    _G_Glows.StopAllGlows(wrapper)
end

local _procState = { hooked = false, active = {} }

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
    local fd = EFD(btn)
    if region and fd.shapeMask and fd.shapeApplied and not EFD(region).shapeMasked then
        for _, tex in ipairs({region:GetRegions()}) do
            if tex and tex.AddMaskTexture then
                pcall(tex.AddMaskTexture, tex, fd.shapeMask)
            end
        end
        EFD(region).shapeMasked = true
    end

    local p = EAB.db and EAB.db.profile
    if not p then return end

    -- Resolve button size from profile settings rather than btn:GetWidth().
    -- On initial login the button frame may not have been sized yet by
    -- LayoutBar, so GetWidth returns the default 45.  Profile values are
    -- always correct.  Replicates LayoutBar's shape expansion / cropped
    -- logic so the ratio matches the actual rendered size.
    local _ufBtnW, _ufBtnH
    do
        local bk = fd.barKey
        if not bk then
            local bi = buttonToBar[btn]
            if bi then bk = bi.barKey end
        end
        local resolved
        if bk and p.bars and p.bars[bk] then
            local s = p.bars[bk]
            local base = barBaseSize[bk]
            local bW = base and base.w or 45
            local bH = base and base.h or 45
            local w = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth or bW
            local h = (s.buttonHeight and s.buttonHeight > 0) and s.buttonHeight or bH
            local shape = s.buttonShape or "none"
            if shape ~= "none" and shape ~= "cropped" then
                w = w + SHAPE_BTN_EXPAND
                h = h + SHAPE_BTN_EXPAND
            end
            if shape == "cropped" then
                h = h * 0.80
            end
            _ufBtnW, _ufBtnH = w, h
            resolved = true
        end
        if not resolved then
            _ufBtnW = btn:GetWidth() or 45
            _ufBtnH = btn:GetHeight() or 45
        end
    end

    if not p.procGlowEnabled then
        -- "Default" glow: use our glow library with Modern WoW Glow (#6)
        if not (fd.shapeMask and fd.shapeApplied) then
            if not fd.glowWrapper then
                local wrapper = CreateFrame("Frame", nil, btn:GetParent() or btn)
                wrapper:SetAllPoints(btn)
                wrapper:SetAlpha(0)
                fd.glowWrapper = wrapper
            end
            local wrapper = fd.glowWrapper
            wrapper:SetFrameLevel(btn:GetFrameLevel() + 10)
            _G_Glows.StopAllGlows(wrapper)
            wrapper:SetAlpha(1)
            wrapper:Show()
            _G_Glows.StartGlow(wrapper, 6, _ufBtnW, 1, 0.788, 0.137, nil, _ufBtnH)
            if region then region:SetAlpha(0) end
            fd.customizedFlipbook = true
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
    if fd.shapeMask and fd.shapeApplied then
        for si, entry in ipairs(LOOP_GLOW_TYPES) do
            if entry.shapeGlow then loopIdx = si; break end
        end
    end
    local loopEntry = LOOP_GLOW_TYPES[loopIdx]

    if not fd.glowWrapper then
        local wrapper = CreateFrame("Frame", nil, btn:GetParent() or btn)
        wrapper:SetAllPoints(btn)
        fd.glowWrapper = wrapper
    end
    local wrapper = fd.glowWrapper
    wrapper:SetFrameLevel(btn:GetFrameLevel() + 10)

    local wfd = EFD(wrapper)
    if fd.shapeMask and fd.shapeApplied and fd.shapeMaskPath then
        if not wfd.ownMask then
            wfd.ownMask = wrapper:CreateMaskTexture()
        end
        wfd.ownMask:ClearAllPoints()
        PP.Point(wfd.ownMask, "TOPLEFT", btn, "TOPLEFT", 1, -1)
        PP.Point(wfd.ownMask, "BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        wfd.ownMask:SetTexture(fd.shapeMaskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        wfd.ownMask:Show()
    elseif wfd.ownMask then
        wfd.ownMask:Hide()
    end

    if loopEntry.procedural or loopEntry.buttonGlow or loopEntry.autocast or loopEntry.shapeGlow then
        fd.customizedFlipbook = true
        -- Suppress Blizzard's native flipbook visuals (hide textures, not durations)
        if region then region:SetAlpha(0) end

        StopAllProceduralGlows(wrapper)
        wrapper:Show()

        local bW, bH = _ufBtnW, _ufBtnH

        if loopEntry.procedural then
            local N = 8
            local th = 2
            local period = 4
            local lineLen = floor((bW + bH) * (2 / N - 0.1))
            lineLen = min(lineLen, min(bW, bH))
            if lineLen < 1 then lineLen = 1 end
            _G_Glows.StartProceduralAnts(wrapper, N, th, period, lineLen, cr, cg, cb, bW, bH)
        elseif loopEntry.buttonGlow then
            _G_Glows.StartButtonGlow(wrapper, bW, cr, cg, cb, nil, bH)
        elseif loopEntry.autocast then
            _G_Glows.StartAutoCastShine(wrapper, bW, cr, cg, cb, 1.0, bH)
        elseif loopEntry.shapeGlow then
            local maskPath = fd.shapeMaskPath or SHAPE_MASKS[fd.shapeName or ""]
            local borderPath = SHAPE_BORDERS[fd.shapeName or ""]
            _G_Glows.StartShapeGlow(wrapper, min(bW, bH), cr, cg, cb, 1.20, {
                maskPath    = maskPath,
                borderPath  = borderPath,
                shapeMask   = fd.shapeMask,
                anchorFrame = btn,
            })
        end
        if wfd.ownMask then
            MaskFrameTextures(wrapper, wfd.ownMask)
        end
    else
        -- FlipBook styles: render on our own wrapper (SetAllPoints on btn)
        -- so the glow matches the button size with no scale math.
        -- Suppress Blizzard's native flipbook visuals.
        fd.customizedFlipbook = true
        if region then region:SetAlpha(0) end

        _G_Glows.StopAllGlows(wrapper)
        wrapper:Show()
        _G_Glows.StartFlipBookGlow(wrapper, _ufBtnW, loopEntry, cr, cg, cb, _ufBtnH)
        if wfd.ownMask then
            MaskFrameTextures(wrapper, wfd.ownMask)
        end
    end

    if region and fd.shapeMask and fd.shapeApplied then
        MaskFrameTextures(region, fd.shapeMask)
        EFD(region).shapeMasked = true
    end
end

-- Resolve the spellID for a button.
-- Stored on _procState to avoid adding a top-level local (200 limit).
_procState.GetButtonSpellID = function(btn)
    local slot = GetButtonActionSlot(btn)
    if not slot or not HasAction or not HasAction(slot) then return nil end
    local actionType, id, subType = GetActionInfo(slot)
    if actionType == "spell" then
        return id
    elseif actionType == "macro" then
        if subType == "spell" then
            return id
        elseif subType == "item" then
            return nil
        end
        local macroName = GetActionText(slot)
        local macroIndex = macroName and GetMacroIndexByName(macroName)
        if macroIndex and macroIndex > 0 then
            if GetMacroItem and GetMacroItem(macroIndex) then
                return nil
            end
            return GetMacroSpell(macroIndex)
        end
    end
    return nil
end

-- Proc glow via SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE events.
-- Loops all buttons to find matches by spellID.
function EAB:HookProcGlow()
    if _procState.hooked then return end
    _procState.hooked = true

    local function IsBlizzStyle()
        local _p3 = EAB.db and EAB.db.profile
        return _p3 and _p3.useBlizzardStyle
    end

    local function ShowGlow(btn)
        _procState.active[btn] = true
        UpdateFlipbook(btn)
    end

    local function HideGlow(btn)
        _procState.active[btn] = nil
        local gw = EFD(btn).glowWrapper
        if gw then
            StopAllProceduralGlows(gw)
            gw:Hide()
        end
        local sa = btn.SpellActivationAlert
        if sa then sa:SetAlpha(1); sa:Hide() end
    end
    local GetButtonSpellID = _procState.GetButtonSpellID

    -- Check IsSpellOverlayed ground truth for a single button.
    -- Also checks base/override variants for spell transforms.
    -- Match LAB: only check IsSpellOverlayed on the button's current spell.
    -- No base/override fallback -- that caused false positives (e.g. Tempest
    -- glowing because its base spell Lightning Bolt was overlayed by Stormkeeper).
    local function UpdateOverlayGlow(btn)
        local spellID = GetButtonSpellID(btn)
        if not spellID then
            if _procState.active[btn] then HideGlow(btn) end
            return
        end
        local ISO = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
        if not ISO then return end
        if ISO(spellID) then
            ShowGlow(btn)
        elseif _procState.active[btn] then
            HideGlow(btn)
        end
    end

    local glowFrame = CreateFrame("Frame")
    glowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    glowFrame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    glowFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    glowFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    glowFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    glowFrame:RegisterEvent("SPELL_UPDATE_ICON")
    -- Deferred full re-scan, coalesced: mouseover-conditional macros re-resolve
    -- on every mouseover flip and fire ACTIONBAR_SLOT_CHANGED storms (dozens per
    -- second sweeping across nameplates). One pending scan covers the whole burst.
    local _glowRescanPending = false
    local function GlowRescan()
        _glowRescanPending = false
        -- Clear glows that no longer match, add new ones
        for btn in pairs(_procState.active) do
            local id = GetButtonSpellID(btn)
            if not id or not C_SpellActivationOverlay.IsSpellOverlayed(id) then
                HideGlow(btn)
            end
        end
        local blizz = IsBlizzStyle()
        for _, info in ipairs(BAR_CONFIG) do
            local buttons = barButtons[info.key]
            if buttons then
                for _, btn in ipairs(buttons) do
                    if btn and (EFD(btn).squared or blizz) and not _procState.active[btn] then
                        UpdateOverlayGlow(btn)
                    end
                end
            end
        end
    end
    glowFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" or event == "SPELL_UPDATE_ICON" then
            -- Defer re-scan: the bar may not have finished paging yet
            -- when the event fires, so slot->spell mappings are stale.
            if not _glowRescanPending then
                _glowRescanPending = true
                C_Timer_After(0, GlowRescan)
            end
            return
        end
        local isShow = (event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
        if not isShow then
            -- HIDE: only need to check buttons with active glows (small set).
            -- Collect first to avoid modifying _procState.active during iteration.
            local toHide
            for btn in pairs(_procState.active) do
                local id = GetButtonSpellID(btn)
                if (id and id == arg1) or not id or not C_SpellActivationOverlay.IsSpellOverlayed(id) then
                    if not toHide then toHide = {} end
                    toHide[#toHide + 1] = btn
                end
            end
            if toHide then
                for i = 1, #toHide do HideGlow(toHide[i]) end
            end
        else
            -- SHOW: scan all buttons for the matching spellID.
            local blizz2 = IsBlizzStyle()
            for _, info in ipairs(BAR_CONFIG) do
                local buttons = barButtons[info.key]
                if buttons then
                    for _, btn in ipairs(buttons) do
                        if btn and (EFD(btn).squared or blizz2) then
                            local id = GetButtonSpellID(btn)
                            if id and id == arg1 then
                                ShowGlow(btn)
                            end
                        end
                    end
                end
            end
        end
    end)

    -- Suppress Blizzard's native SpellActivationAlert on our buttons
    -- since we render our own glow via UpdateFlipbook.
    -- Skip when our custom glow is active (both use SpellActivationAlert).
    -- Skip for Blizzard-styled bars so native glows show normally.
    if ActionButtonSpellAlertManager and ActionButtonSpellAlertManager.ShowAlert then
        hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, btn)
            if btn and EFD(btn).squared and not IsBlizzStyle()
               and not _procState.active[btn]
               and btn.SpellActivationAlert then
                btn.SpellActivationAlert:SetAlpha(0)
            end
        end)
    end
end

-- Per-button usability updates are handled natively by Blizzard's
-- ActionButton OnEvent: UNIT_POWER_FREQUENT and PLAYER_TARGET_CHANGED
-- are now in BUTTON_EVENT_LISTS.action so each button reacts on its own
-- via Blizzard's C-side dispatcher. The old global usableFrame polling
-- pass that iterated all 144 buttons on every fire was removed.

-- Hook AssistedCombatManager to scale highlight/rotation frames when Blizzard
-- creates them lazily on first use.
do
    local function ScaleAssistedFrames()
        for _, info in ipairs(BAR_CONFIG) do
            local buttons = barButtons[info.key]
            if buttons then
                for i = 1, #buttons do
                    local btn = buttons[i]
                    if btn and EFD(btn).squared then
                        local w = btn:GetWidth() or 45
                        local s = w / 45
                        if btn.AssistedCombatHighlightFrame then
                            btn.AssistedCombatHighlightFrame:SetScale(s)
                        end
                        if btn.AssistedCombatRotationFrame then
                            btn.AssistedCombatRotationFrame:SetScale(s)
                        end
                    end
                end
            end
        end
    end
    if AssistedCombatManager then
        if AssistedCombatManager.UpdateAllAssistedHighlightFramesForSpell then
            hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", ScaleAssistedFrames)
        end
        if AssistedCombatManager.UpdateAllAssistedCombatRotationFrames then
            hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedCombatRotationFrames", ScaleAssistedFrames)
        end
    end
end

-------------------------------------------------------------------------------
--  Assisted Combat Highlight (self-painted)
--  Our action buttons are EABButton frames permanently removed from
--  ActionBarButtonEventsFrame.frames (the taint fix), so Blizzard's
--  AssistedCombatManager never builds them into its highlight-candidate list
--  (it walks .frames once at activation). The result: the shine appeared only
--  on a button after a mouseover (native OnActionChanged re-adds that one
--  button to the candidate map) and never survived a reload or a mid-session
--  CVar toggle. We paint our own shine, driven by the same AssistedCombatManager
--  events the CDM module uses, so it is immune to that candidate-list timing.
--  Blizzard may still show its own frame on a hovered button (candidate re-add);
--  we defer to it there to avoid stacking two identical shines.
-------------------------------------------------------------------------------
do
    local _assistGlowed = {}   -- btn -> true while showing our shine
    local _assistInCombat = false
    local _assistHookInstalled = false

    local function AssistCVarOn()
        return GetCVarBool and GetCVarBool("assistedCombatHighlight")
    end

    local function AssistCreate(btn)
        local ok, hf = pcall(CreateFrame, "Frame", nil, btn, "ActionBarButtonAssistedCombatHighlightTemplate")
        if not ok or not hf then return nil end
        hf:SetPoint("CENTER")
        -- Above the cooldown swipe, border frame, glowOverlay (+6) and proc
        -- alerts -- same margin the CDM twin uses.
        hf:SetFrameLevel(btn:GetFrameLevel() + 15)
        -- Freeze on a single flipbook frame until we actually animate (in combat).
        if hf.Flipbook and hf.Flipbook.Anim then
            hf.Flipbook.Anim:Play()
            hf.Flipbook.Anim:Stop()
        end
        hf:Hide()
        return hf
    end

    local function AssistHide(btn)
        local hf = EFD(btn).assistHL
        if not hf then return end
        if hf.Flipbook and hf.Flipbook.Anim then hf.Flipbook.Anim:Stop() end
        hf:Hide()
    end

    local function AssistShow(btn)
        local fd = EFD(btn)
        local hf = fd.assistHL
        if not hf then
            hf = AssistCreate(btn)
            if not hf then return end
            fd.assistHL = hf
        end
        local w = btn:GetWidth() or 45
        hf:SetScale(w / 45)
        -- Re-assert: bar layout can change the button's frame level after create.
        hf:SetFrameLevel(btn:GetFrameLevel() + 15)
        hf:Show()
        if hf.Flipbook and hf.Flipbook.Anim then
            if _assistInCombat then hf.Flipbook.Anim:Play() else hf.Flipbook.Anim:Stop() end
        end
    end

    -- The (spell) id a button currently represents, mirroring Blizzard's
    -- AssistedCombatManager:GetActionButtonSpellForAssistedHighlight.
    -- Attribute first: the secure paging writes the "action" attribute and it
    -- is the authoritative slot (see ForceCooldownPaint's note); btn.action is
    -- a derived mirror.
    local function ButtonSpell(btn)
        local action = btn.GetAttribute and btn:GetAttribute("action")
        if action == nil then action = btn.action end
        if action == nil then return nil end
        local atype, id, subType = GetActionInfo(action)
        if atype == "spell" and subType ~= "assistedcombat" then
            return id
        elseif atype == "macro" and subType == "spell" then
            return id
        end
        return nil
    end

    local function UpdateAssistHighlights()
        if not AssistCVarOn() then
            for btn in pairs(_assistGlowed) do
                AssistHide(btn)
                _assistGlowed[btn] = nil
            end
            return
        end
        local suggested = C_AssistedCombat and C_AssistedCombat.GetNextCastSpell
            and C_AssistedCombat.GetNextCastSpell()
        local newSet = {}
        if suggested then
            -- Match base ids in both directions (button or suggestion may hold
            -- either the base or an override), same as the CDM side. sid > 0
            -- guards item/macro pseudo-ids out of GetBaseSpell.
            local GetBaseSpell = C_Spell and C_Spell.GetBaseSpell
            local suggestedBase = (GetBaseSpell and GetBaseSpell(suggested)) or suggested
            for _, info in ipairs(BAR_CONFIG) do
                if not info.isStance and not info.isPetBar then
                    local buttons = barButtons[info.key]
                    if buttons then
                        for i = 1, #buttons do
                            local btn = buttons[i]
                            if btn and btn:IsShown() then
                                local sid = ButtonSpell(btn)
                                if sid then
                                    local match = (sid == suggested) or (sid == suggestedBase)
                                    if not match and GetBaseSpell and sid > 0 then
                                        match = GetBaseSpell(sid) == suggestedBase
                                    end
                                    if match then
                                        local bf = btn.AssistedCombatHighlightFrame
                                        if bf and bf:IsShown() then
                                            AssistHide(btn)  -- Blizzard's covers it
                                        else
                                            AssistShow(btn)
                                        end
                                        newSet[btn] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        for btn in pairs(_assistGlowed) do
            if not newSet[btn] then AssistHide(btn) end
        end
        _assistGlowed = newSet
    end
    ns.UpdateAssistHighlights = UpdateAssistHighlights

    -- Coalesced re-run: OnActionChanged fires per button on page swaps and
    -- SLOT_CHANGED storms dozens of times per second (mouseover-conditional
    -- macros re-resolving); one pending flag collapses a burst into a single
    -- next-frame pass.
    local _assistRescanPending = false
    local function QueueAssistRescan()
        if _assistRescanPending then return end
        _assistRescanPending = true
        C_Timer.After(0, function()
            _assistRescanPending = false
            UpdateAssistHighlights()
        end)
    end
    ns.QueueAssistRescan = QueueAssistRescan

    local function SyncAssistCombat()
        _assistInCombat = (InCombatLockdown() or UnitAffectingCombat("player")) and true or false
        for btn in pairs(_assistGlowed) do
            local hf = EFD(btn).assistHL
            if hf and hf:IsShown() and hf.Flipbook and hf.Flipbook.Anim then
                if _assistInCombat then
                    if not hf.Flipbook.Anim:IsPlaying() then hf.Flipbook.Anim:Play() end
                else
                    if hf.Flipbook.Anim:IsPlaying() then hf.Flipbook.Anim:Stop() end
                end
            end
        end
    end

    local function InstallAssistHook()
        if _assistHookInstalled then return end
        _assistHookInstalled = true
        SyncAssistCombat()
        if EventRegistry and EventRegistry.RegisterCallback then
            -- No hooksecurefunc on UpdateAllAssistedHighlightFramesForSpell:
            -- the manager calls it then fires this event right after, so a
            -- hook would run the full walk twice per suggestion change.
            EventRegistry:RegisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", function()
                QueueAssistRescan()
            end, "EAB_AssistHighlight")
            -- Fires when the assistedCombatHighlight CVar is toggled at runtime.
            EventRegistry:RegisterCallback("AssistedCombatManager.OnSetUseAssistedHighlight", function()
                QueueAssistRescan()
            end, "EAB_AssistHighlight_CVar")
            -- Page swaps / drags / hover re-candidacy: the suggestion may not
            -- change, but which button holds it (or whether Blizzard shows its
            -- own frame on a hovered button) does. Same signal Blizzard uses.
            EventRegistry:RegisterCallback("ActionButton.OnActionChanged", function()
                QueueAssistRescan()
            end, "EAB_AssistHighlight_Action")
        end
        local cf = CreateFrame("Frame")
        cf:RegisterEvent("PLAYER_REGEN_ENABLED")
        cf:RegisterEvent("PLAYER_REGEN_DISABLED")
        cf:RegisterEvent("PLAYER_ENTERING_WORLD")
        cf:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_ENTERING_WORLD" then
                SyncAssistCombat()
                UpdateAssistHighlights()
            else
                SyncAssistCombat()
            end
        end)
        UpdateAssistHighlights()
    end
    InstallAssistHook()
end

function EAB:RefreshProcGlows()
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and _procState.active[btn] then
                    UpdateFlipbook(btn)
                end
            end
        end
    end
end

function EAB:ScanExistingProcs()
    local found = 0
    local total = 0
    local blizz = self.db and self.db.profile and self.db.profile.useBlizzardStyle
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and (EFD(btn).squared or blizz) then
                    total = total + 1
                    local spellID = _procState.GetButtonSpellID(btn)
                    local ISO = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
                    local overlayed = spellID and ISO and ISO(spellID)
                    if not overlayed and spellID and ISO then
                        if C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                            local ovr = C_SpellBook.FindSpellOverrideByID(spellID)
                            if ovr and ovr > 0 and ovr ~= spellID then overlayed = ISO(ovr) end
                        end
                        if not overlayed and C_Spell and C_Spell.GetBaseSpell then
                            local base = C_Spell.GetBaseSpell(spellID)
                            if base and base > 0 and base ~= spellID then overlayed = ISO(base) end
                        end
                    end
                    if overlayed then
                        found = found + 1
                        _procState.active[btn] = true
                        UpdateFlipbook(btn)
                    end
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
    local efd = EFD(btn)
    if not btn or not efd.shapeApplied then return end
    local shapeName = efd.shapeName
    if not shapeName then return end
    local edgeScale = SHAPE_EDGE_SCALES[shapeName] or 0.60
    local useCircular = (shapeName ~= "square" and shapeName ~= "csquare")
    EnforceShapeEdgeSingle(btn.cooldown, edgeScale, useCircular)
    EnforceShapeEdgeSingle(btn.chargeCooldown, edgeScale, useCircular)
end

local function ApplyButtonCooldownEdge(btn, edgeSize, cr, cg, cb, ca)
    -- Square/csquare use the user's edge size; other shapes force 1.0
    -- since EnforceShapeEdge will override with per-shape scale anyway.
    local efd = EFD(btn)
    local sn = efd.shapeApplied and efd.shapeName
    local sz = edgeSize
    if sn and sn ~= "square" and sn ~= "csquare" then sz = 1.0 end
    ApplySingleCooldownEdge(btn.cooldown, sz, cr, cg, cb, ca)
    ApplySingleCooldownEdge(btn.chargeCooldown, sz, cr, cg, cb, ca)
    EnforceShapeEdge(btn)
end

-- Hook to re-apply edge settings whenever Blizzard resets a cooldown.

-- Per-button hooks avoid tainting the secure execution path.
local _cdEdge = {
    hooked = false,
    pending = {},       -- reusable { [cdFrame] = btn, ... }
    pendingCount = 0,
    timerScheduled = false,
}

local function _FlushCDPatch()
    _cdEdge.timerScheduled = false
    local p = EAB.db and EAB.db.profile
    if not p then wipe(_cdEdge.pending); _cdEdge.pendingCount = 0; return end
    local cr, cg, cb, ca = ResolveCooldownEdgeColor(p)
    local baseSz = p.cooldownEdgeSize or 2.1
    for cdFrame, btn in pairs(_cdEdge.pending) do
        if cdFrame and not cdFrame:IsForbidden() then
            local sz = baseSz
            local bfd = EFD(btn)
            local sn = bfd.shapeApplied and bfd.shapeName
            if sn and sn ~= "square" and sn ~= "csquare" then sz = 1.0 end
            ApplySingleCooldownEdge(cdFrame, sz, cr, cg, cb, ca)
            if bfd.shapeMaskPath and bfd.shapeApplied then
                local mask = bfd.shapeMask
                if mask then
                    pcall(cdFrame.RemoveMaskTexture, cdFrame, mask)
                    pcall(cdFrame.AddMaskTexture, cdFrame, mask)
                end
                if cdFrame.SetSwipeTexture then
                    pcall(cdFrame.SetSwipeTexture, cdFrame, bfd.shapeMaskPath)
                end
            end
            EnforceShapeEdge(btn)
            EFD(cdFrame).edgeDone = true
        end
    end
    wipe(_cdEdge.pending)
    _cdEdge.pendingCount = 0
end

local function HookButtonCooldownEdge(btn)
    if not btn or not EFD(btn).squared then return end
    if EFD(btn).cdEdgeHooked then return end
    EFD(btn).cdEdgeHooked = true

    local function OnSetCooldown(cdFrame)
        -- Cooldown edge patch (skip if edge was already applied to this frame)
        if cdFrame and not EFD(cdFrame).edgeDone then
            if not _cdEdge.pending[cdFrame] then
                _cdEdge.pendingCount = _cdEdge.pendingCount + 1
            end
            _cdEdge.pending[cdFrame] = btn
            if not _cdEdge.timerScheduled then
                _cdEdge.timerScheduled = true
                C_Timer_After(0, _FlushCDPatch)
            end
        end
        -- Cooldown font patch (shared hook to avoid double hooksecurefunc).
        -- Skip if fonts were already applied to this button's cooldown frame
        -- (stamp is set by ApplyToFrame and cleared on settings change).
        if not (btn.cooldown and EFD(btn.cooldown).cdFontStamp) then
            EAB_VTABLE.CooldownFonts.pending[btn] = true
            if not EAB_VTABLE.CooldownFonts.timerScheduled then
                EAB_VTABLE.CooldownFonts.timerScheduled = true
                C_Timer_After(0, EAB_VTABLE.CooldownFonts.FlushPatch)
            end
        end
    end

    if btn.cooldown and btn.cooldown.SetCooldown then
        hooksecurefunc(btn.cooldown, "SetCooldown", OnSetCooldown)
    end
    if btn.chargeCooldown and btn.chargeCooldown.SetCooldown then
        hooksecurefunc(btn.chargeCooldown, "SetCooldown", OnSetCooldown)
    end
end

EAB_VTABLE.CooldownFonts.pending = {}
EAB_VTABLE.CooldownFonts.timerScheduled = false

function EAB_VTABLE.CooldownFonts.FlushPatch()
    EAB_VTABLE.CooldownFonts.timerScheduled = false

    for btn in pairs(EAB_VTABLE.CooldownFonts.pending) do
        local info = buttonToBar[btn]
        local barKey = info and info.barKey
        local s = barKey and EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars[barKey]
        if s then
            local fontPath, cdSize, cdOX, cdOY, cdColor = EAB_VTABLE.CooldownFonts.GetSettings(s)
            EAB_VTABLE.CooldownFonts.ApplyToButton(btn, fontPath, cdSize, cdOX, cdOY, cdColor)
        end
        EAB_VTABLE.CooldownFonts.pending[btn] = nil
    end
end

function EAB_VTABLE.CooldownFonts.HookButton(btn)
    if not btn or EFD(btn).cdFontsHooked then return end
    EFD(btn).cdFontsHooked = true
    -- Piggyback on the cooldown edge hook instead of adding a second
    -- hooksecurefunc on the same SetCooldown method. HookButtonCooldownEdge
    -- already fires on every SetCooldown; we just need to also queue the
    -- font patch from the same callback. See HookButtonCooldownEdge above.
    -- If edge hook hasn't run yet, it will pick up fonts when it does.
end

local function HookCooldownEdge()
    if _cdEdge.hooked then return end
    _cdEdge.hooked = true
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and EFD(btn).squared then
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
                if btn and EFD(btn).squared then
                    -- Clear edge cache so the hook re-applies on next cooldown
                    if btn.cooldown then EFD(btn.cooldown).edgeDone = nil end
                    if btn.chargeCooldown then EFD(btn.chargeCooldown).edgeDone = nil end
                    ApplyButtonCooldownEdge(btn, sz, cr, cg, cb, ca)
                end
            end
        end
    end
end

function EAB_VTABLE.CooldownFonts.HookAll()
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn then
                    EAB_VTABLE.CooldownFonts.HookButton(btn)
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
                if btn and EFD(btn).squared then
                    -- Do NOT color CheckedTexture or Border Blizzard uses
                    -- these for item rarity borders (green/blue/purple) on
                    -- active trinkets / equipped items.
                    if btn.NewActionTexture then btn.NewActionTexture:SetDesaturated(true); btn.NewActionTexture:SetVertexColor(cr, cg, cb, ca) end
                end
            end
        end
    end

    -- ActionBarActionEventsFrame is killed at file-load time (top of file).
    -- Spellcast events are no longer re-registered here -- our central
    -- dispatcher + ACTIONBAR_UPDATE_COOLDOWN handles cooldown/GCD swipes.
end

-- "Show Highlight on Spell Cast": the CheckedTexture is the highlight that
-- appears when a spell is the current/active action. When the option is off
-- we drive the CheckedTexture alpha to 0 (same hide-via-alpha pattern the
-- "none" pushed/highlight types use). This is the single source of truth so
-- every site that sets CheckedTexture alpha stays consistent.
function EAB:GetCheckedAlpha()
    return (self.db.profile.showCastHighlight == false) and 0 or 1
end

function EAB:ApplyCheckedTextures()
    local a = self:GetCheckedAlpha()
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for i = 1, #buttons do
                local btn = buttons[i]
                if btn and btn.CheckedTexture then
                    btn.CheckedTexture:SetAlpha(a)
                end
            end
        end
    end
end

-- Re-apply charge-spell recharge-number visibility across all buttons. Same
-- logic the dispatcher's per-tick + CVAR_UPDATE paths use; called when the
-- "Show Cooldown Numbers" cog toggle flips so the change is immediate (a DB
-- toggle does not fire CVAR_UPDATE). Cached per chargeCd, so it is near-free.
function EAB:RefreshChargeRechargeNumbers()
    local hideNums = (self.db.profile.showChargeRechargeNumbers == false)
        or (not GetCVarBool("countdownForCooldowns"))
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local buttons = barButtons[info.key]
            if buttons then
                for _, btn in ipairs(buttons) do
                    local chargeCd = btn.chargeCooldown
                    if chargeCd and chargeCd.SetHideCountdownNumbers
                       and EFD(chargeCd).rechargeNumbersHidden ~= hideNums then
                        EFD(chargeCd).rechargeNumbersHidden = hideNums
                        chargeCd:SetHideCountdownNumbers(hideNums)
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Keybind System
--  Hybrid routing: empower/flyout slots use SetOverrideBindingClick so our
--  buttons' pressAndHoldAction/typerelease handle hold-and-release. All other
--  slots use SetOverrideBinding to native commands (ACTIONBUTTON1, etc.) so
--  the engine handles press-and-hold repeat casting natively.
-------------------------------------------------------------------------------
local _bindState = { housingCleared = false }

-- Binding owner frame: single frame owns all override bindings so they
-- can be cleared/reapplied as a unit. Bindings route to native commands
-- (ACTIONBUTTON1, etc.) so the engine's hold-to-cast and empowered spell
-- systems work natively without pressAndHoldAction/typerelease attrs.
local _eabBindOwner = CreateFrame("Frame", "EAB_BindOwner", UIParent)

-- Returns true when the override bindings were (re)applied, false when the
-- routing signature was unchanged and the rebuild was skipped.
--
-- The signature cache exists because rebuilding is expensive: it clears and
-- re-registers up to two override bindings per button (engine binding-table
-- rebuilds), plus GetActionInfo/IsPressHoldReleaseSpell per slot. The empower
-- reroute calls this on ACTIONBAR_SLOT_CHANGED, which storms dozens of times
-- per second while sweeping the mouse across nameplates with
-- mouseover-conditional macros on the bars (each flip re-resolves the macros).
-- Slot contents changing does NOT change the bindings themselves (keys map to
-- native commands or button names, not to actions), so the rebuild only needs
-- to run when a routing decision, a bound key, or a button's empower state
-- actually changes.
local function UpdateKeybinds()
    if InCombatLockdown() then return false end
    -- While the house editor is active our override bindings are cleared so
    -- Blizzard's housing hotkeys work (see Housing Editor Keybind Clearing).
    -- The editor registers its OWN override bindings after ours are cleared,
    -- and that registration fires UPDATE_BINDINGS -- which routes right back
    -- here. Without this guard the rebuild re-applied all ~200 of our
    -- overrides on top of the editor's, stomping the housing hotkeys until
    -- the editor re-applied them on the next mode change. Rebuild resumes on
    -- editor close (housingCleared reset -> UpdateKeybinds; sigValid stays
    -- false while cleared, so that rebuild is never skipped).
    if _bindState.housingCleared then return false end
    -- Pass 1: compute per-button routing signature (k1, k2, useClick, isPH)
    -- and compare against the last applied build.
    local sig = _bindState.sig
    if not sig then sig = {}; _bindState.sig = sig end
    local n = 0
    local changed = not _bindState.sigValid
    for _, info in ipairs(BAR_CONFIG) do
        local prefix = BINDING_MAP[info.key]
        local btns = barButtons[info.key]
        if prefix and btns then
            -- Custom modifier/form paging lives only in our private secure
            -- state driver, which never moves Blizzard's GetActionBarPage().
            -- Native engine commands (ACTIONBUTTONn / MULTIACTIONBARxBUTTONn)
            -- resolve against Blizzard's page, so on a custom-paged bar the
            -- keybind would fire the un-paged slot while the icon (our explicit
            -- "action" attr) repages. Route those bars' keybinds through the
            -- button (SetOverrideBindingClick) so the keypress reads our paged
            -- "action" attr -- exactly what empower/flyout already do, and what
            -- ElvUI/Bartender do for every button via LibActionButton.
            local bs = EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars[info.key]
            local barHasCustomPaging = (bs and bs.paging and next(bs.paging) ~= nil) and true or false
            if not barHasCustomPaging and info.key == "MainBar" then
                local _, cls = UnitClass("player")
                if cls == "DRUID" or cls == "ROGUE" then
                    barHasCustomPaging = true
                end
            end
            for i, btn in ipairs(btns) do
                if btn then
                    local cmd = prefix .. i
                    local k1, k2 = GetBindingKey(cmd)
                    -- Empower spells need SetOverrideBindingClick so our
                    -- button's pressAndHoldAction/typerelease handle the
                    -- hold-and-release. Non-empower spells use native
                    -- SetOverrideBinding for press-and-hold repeat casting --
                    -- EXCEPT on custom-paged bars (see above), which must also
                    -- route through the button so the keybind tracks the page.
                    local slot = btn:GetAttribute("action")
                    -- Custom bars (Bar9/Bar10) have no native binding command, so
                    -- their keys MUST route through the button (SetOverrideBindingClick);
                    -- SetOverrideBinding to a non-existent command would do nothing.
                    -- isPH tracks empower/flyout separately from useClick: on a
                    -- custom-paged bar useClick is always true, but the secure
                    -- empower snippet still needs a re-trigger when a slot's
                    -- press-and-hold state flips.
                    local isPH = false
                    if slot and HasAction(slot) then
                        local actionType, id, subType = GetActionInfo(slot)
                        if actionType == "flyout" then
                            isPH = true
                        elseif C_Spell and C_Spell.IsPressHoldReleaseSpell then
                            local spellID
                            if actionType == "spell" then
                                spellID = id
                            elseif actionType == "macro" and subType == "spell" then
                                spellID = id
                            end
                            if spellID and not (issecretvalue and issecretvalue(spellID))
                               and C_Spell.IsPressHoldReleaseSpell(spellID) then
                                isPH = true
                            end
                        end
                    end
                    local useClick = isPH or barHasCustomPaging or (info.customPage ~= nil)
                    k1 = k1 or false
                    k2 = k2 or false
                    if sig[n + 1] ~= k1 or sig[n + 2] ~= k2
                       or sig[n + 3] ~= useClick or sig[n + 4] ~= isPH then
                        changed = true
                    end
                    sig[n + 1], sig[n + 2], sig[n + 3], sig[n + 4] = k1, k2, useClick, isPH
                    n = n + 4
                end
            end
        end
    end
    if _bindState.sigN ~= n then changed = true; _bindState.sigN = n end
    if not changed then return false end
    _bindState.sigValid = true
    -- Pass 2: apply. Reads the routing decisions computed above.
    ClearOverrideBindings(_eabBindOwner)
    local j = 0
    for _, info in ipairs(BAR_CONFIG) do
        local prefix = BINDING_MAP[info.key]
        local btns = barButtons[info.key]
        if prefix and btns then
            for i, btn in ipairs(btns) do
                if btn then
                    local k1, k2, useClick = sig[j + 1], sig[j + 2], sig[j + 3]
                    j = j + 4
                    if useClick then
                        local btnName = btn:GetName()
                        if k1 and btnName then
                            SetOverrideBindingClick(_eabBindOwner, false, k1, btnName)
                        end
                        if k2 and btnName then
                            SetOverrideBindingClick(_eabBindOwner, false, k2, btnName)
                        end
                    else
                        local cmd = prefix .. i
                        if k1 then
                            SetOverrideBinding(_eabBindOwner, false, k1, cmd)
                        end
                        if k2 then
                            SetOverrideBinding(_eabBindOwner, false, k2, cmd)
                        end
                    end
                end
            end
        end
    end
    return true
end
_G._EAB_UpdateKeybinds = UpdateKeybinds




-- Update useOnKeyDown on all action buttons to match the CVar.
-- RegisterForClicks is always ("AnyDown", "AnyUp") so empower spells
-- receive key-down even in key-up mode. Only the attribute changes.
-- Must be called out of combat (SetAttribute on secure buttons).
local function ApplyClickRegistration()
    local keyDown = GetCVarBool("ActionButtonUseKeyDown")
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local btns = barButtons[info.key]
            if btns then
                for _, btn in ipairs(btns) do
                    if btn then
                        btn:SetAttribute("useOnKeyDown", keyDown)
                    end
                end
            end
        end
    end
end

-- Called when ActionButtonUseKeyDown CVar changes. Defers to out-of-combat.
local _keyDownDeferFrame
local function ApplyKeyDownCVar()
    if InCombatLockdown() then
        if not _keyDownDeferFrame then
            _keyDownDeferFrame = CreateFrame("Frame")
            _keyDownDeferFrame:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                ApplyClickRegistration()
                UpdateKeybinds()
            end)
        end
        _keyDownDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    ApplyClickRegistration()
    UpdateKeybinds()
end


-------------------------------------------------------------------------------
--  Vehicle Exit Button
--  Reparent to UIParent so it stays visible when ActionBarParent is hidden.
--  Position and visibility are fully Blizzard-owned (no unlock mode, no
--  SetPoint hook). ActionBarController is disabled above, so Blizzard's
--  transition system won't reposition it.
-------------------------------------------------------------------------------
do
    local btn = MainMenuBarVehicleLeaveButton
    if btn then
        btn:SetParent(UIParent)
        local vehVis = CreateFrame("Frame")
        vehVis:RegisterEvent("UNIT_ENTERED_VEHICLE")
        vehVis:RegisterEvent("UNIT_EXITED_VEHICLE")
        vehVis:RegisterEvent("PLAYER_ENTERING_WORLD")
        vehVis:RegisterEvent("PLAYER_REGEN_ENABLED")
        vehVis:SetScript("OnEvent", function(self, event, unit)
            if event == "PLAYER_REGEN_ENABLED" then
                local show = CanExitVehicle and CanExitVehicle()
                btn:SetShown(show or false)
                return
            end
            if unit and unit ~= "player" then return end
            -- Protected instances (M+/raid) block SetShown during combat
            if InCombatLockdown() and EllesmereUI.InProtectedInstance and EllesmereUI.InProtectedInstance() then return end
            local show = CanExitVehicle and CanExitVehicle()
            btn:SetShown(show or false)
        end)
    end
end

-------------------------------------------------------------------------------
--  Vehicle Highlight Fix
--  During vehicle/override paging, empty MainBar buttons can retain a stale
--  "checked" state from the normal bar. The CheckedTexture uses the same
--  texture as HighlightTexture, so it looks like a permanent highlight.
--  The inverted mouseover behavior (hides on enter, returns on leave) is
--  WoW's native CheckButton behavior when the button is checked.
--
--  Fix: after a page change, clear the checked state and hide the
--  CheckedTexture on MainBar buttons that have no action on the new page.
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
                        if ct then ct:SetAlpha(EAB:GetCheckedAlpha()) end
                    end
                else
                    -- Normal page: restore alpha on all buttons so checked
                    -- state renders correctly when spells are dragged in
                    -- (honors the Show Highlight on Spell Cast setting).
                    if ct then ct:SetAlpha(EAB:GetCheckedAlpha()) end
                end
            end
        end
    end

    local function QueueVehicleHighlightFix()
        if _vehHighlightPending then return end
        _vehHighlightPending = true
        C_Timer_After(0, FixVehicleHighlights)
    end

    local vehHighlightFrame = CreateFrame("Frame")
    vehHighlightFrame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
    vehHighlightFrame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
    vehHighlightFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    vehHighlightFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    vehHighlightFrame:SetScript("OnEvent", QueueVehicleHighlightFix)
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
            -- House editor closed restore our override bindings
            if not _bindState.housingCleared then return end
            _bindState.housingCleared = false
            if not InCombatLockdown() then
                UpdateKeybinds()
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Grid Show/Hide (show empty slots during spell drag)
-------------------------------------------------------------------------------

local function OnGridChange()
    if InCombatLockdown() then return end
    -- Throttle: bag addons fire ACTIONBAR_SHOWGRID hundreds of times
    -- per sort pass via PickupContainerItem, causing "script ran too long".
    local now = GetTime()
    if _gridState.shown and _gridState._lastTime and (now - _gridState._lastTime) < 0.1 then return end
    _gridState._lastTime = now
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
                    -- Make hidden empty buttons visible during drag
                    btn:Show()
                    if btn:GetAlpha() < 0.01 then
                        btn:SetAlpha(1)
                    end
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
-- cursor drag (see the CURSOR_CHANGED handler). Idempotent -- safe from every
-- drag-end path. Clears only the overrides the drag itself planted, so a
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
end

-------------------------------------------------------------------------------
--  Apply All orchestrates full visual application
-------------------------------------------------------------------------------
local function ApplyAll()
    _isApplyingAll = true

    -- Restore any strata raised during a drag that wasn't cleaned up
    if _dragState.visible then
        _dragState.visible = false
        for frame, orig in pairs(_dragState.strataCache) do
            frame:SetFrameStrata(orig)
        end
        wipe(_dragState.strataCache)
    end

    local inCombat = InCombatLockdown()

    if not inCombat then
        EAB_VTABLE.MainBarPageSync.InstallAll()
    end

    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local s = EAB.db.profile.bars[key]
        local frame = barFrames[key]

        -- Bar enabled/disabled toggle (protected frames can't be shown/hidden in combat)
        if frame and s and not inCombat then
            if s.enabled == false then
                frame:Hide()
            elseif not s.alwaysHidden then
                -- Skip Show if a state-visibility driver is managing this frame
                -- (the driver handles show/hide; calling Show() causes a one-frame blink)
                if not frame._eabLastVisStr then
                    frame:Show()
                end
            end
        end

        if not inCombat then
            LayoutBar(key)
        end
        if not inCombat then EAB:ApplyBordersForBar(key) end
        if not inCombat then EAB:ApplyShapesForBar(key) end
        EAB:ApplyFontsForBar(key)
        EAB:ApplyBackgroundForBar(key)
        EAB:ApplyIconBackgroundForBar(key)
        if not inCombat then EAB:ApplyAlwaysShowButtons(key) end
        if not inCombat then EAB:ApplyClickThroughForBar(key) end
    end

    EAB:ApplyPushedTextures()
    EAB:HookPushedFlash()
    EAB:ApplyHighlightTextures()
    EAB:ApplyCooldownFonts()
    EAB:ApplyCooldownSwipeColor()
    -- Gated so it's zero-touch at the default (100); the live handler + setValue
    -- own the rest.
    if EAB.db and EAB.db.profile and EAB.db.profile.alphaWhenOnCD ~= 100 then
        EAB:ApplyCDAlphaAll()
    end
    EAB:ApplyCooldownEdge()
    EAB:ApplyMiscTextures()
    EAB:ApplyCheckedTextures()
    if not inCombat then EAB:ApplyCombatVisibility() end
    if not inCombat then EAB:RefreshRuntimeVisibility() end
    EAB:RefreshMouseover()
    EAB:RefreshProcGlows()
    EAB:ApplyRangeColoring()

    _isApplyingAll = false
end

-------------------------------------------------------------------------------
--  Position Save/Restore
-------------------------------------------------------------------------------
-- Convert CENTER position to edge for non-CENTER-grow bars (same pattern as CDM).
-- Stored on EAB to avoid consuming local slots (200-local Lua 5.1 cap).
function EAB:ConvertCenterToEdge(barKey, point, x, y)
    if point ~= "CENTER" then return point, x, y end
    local cfg = self.db and self.db.profile and self.db.profile.bars and self.db.profile.bars[barKey]
    local grow = cfg and cfg.growDirection
    if not grow then return point, x, y end
    grow = grow:upper()
    if grow == "CENTER" then return point, x, y end
    local frame = barFrames[barKey]
    if not frame then return point, x, y end
    local fw = frame:GetWidth() or 0
    local fh = frame:GetHeight() or 0
    if grow == "RIGHT" and fw > 0 then return "LEFT", x - fw / 2, y
    elseif grow == "LEFT" and fw > 0 then return "RIGHT", x + fw / 2, y
    elseif grow == "DOWN" and fh > 0 then return "TOP", x, y + fh / 2
    elseif grow == "UP" and fh > 0 then return "BOTTOM", x, y - fh / 2
    end
    return point, x, y
end

function EAB:ConvertEdgeToCenter(barKey, pos)
    if not pos or not pos.point then return pos end
    local pt = pos.point
    if pt == "CENTER" then return pos end
    if pt ~= "LEFT" and pt ~= "RIGHT" and pt ~= "TOP" and pt ~= "BOTTOM" then return pos end
    local frame = barFrames[barKey]
    if not frame then return pos end
    local fw = frame:GetWidth() or 0
    local fh = frame:GetHeight() or 0
    local cx, cy = pos.x or 0, pos.y or 0
    if pt == "LEFT" then cx = cx + fw / 2
    elseif pt == "RIGHT" then cx = cx - fw / 2
    elseif pt == "TOP" then cy = cy - fh / 2
    elseif pt == "BOTTOM" then cy = cy + fh / 2
    end
    return { point = "CENTER", relPoint = pos.relPoint, x = cx, y = cy }
end

local function SaveBarPosition(barKey)
    local frame = barFrames[barKey]
    if not frame then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if point then
        -- Pixel-perfect snapping can produce sub-pixel offsets (e.g. 0.5)
        -- on CENTER-anchored bars. Re-snapping on restore drifts by 1px at
        -- certain UI scales. Clamp near-zero CENTER offsets to exactly 0 so
        -- the restore-skip at RestoreBarPositions fires correctly.
        if point == "CENTER" and relPoint == "CENTER" then
            local es = frame:GetEffectiveScale() or 1
            local PPa = EllesmereUI and EllesmereUI.PP
            local onePx = PPa and PPa.perfect and (PPa.perfect / es) or 1
            if math.abs(x) < onePx then x = 0 end
            if math.abs(y) < onePx then y = 0 end
        end
        EAB.db.profile.barPositions[barKey] = {
            point = point, relPoint = relPoint, x = x, y = y,
        }
    end
end

local function RestoreBarPositions()
    local positions = EAB.db.profile.barPositions
    if not positions then return end
    local PPa = EllesmereUI and EllesmereUI.PP
    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local pos = positions[key]
        local frame = barFrames[key]
        if pos and frame then
            -- Skip bars owned by the unlock anchor system -- their position
            -- is computed from the anchor chain, not from saved barPositions.
            local anchored = EllesmereUI and EllesmereUI.IsUnlockAnchored
                             and EllesmereUI.IsUnlockAnchored(key)
            if anchored then
                -- skip: anchor system owns this bar's position
            else
            local pt = pos.point or "CENTER"
            local rpt = pos.relPoint or pt
            local px = pos.x or 0
            local py = pos.y or 0
            -- Skip CENTER 0,0: this is never an intentional position.
            -- Anchored bars save 0,0 as a placeholder; their real position
            -- comes from the anchor chain which resolves later.
            if pt == "CENTER" and rpt == "CENTER" and px == 0 and py == 0 then
                -- skip
            else
                -- Snap to physical pixel grid. For CENTER-anchored bars use
                -- SnapCenterForDim with the frame's actual size so odd-pixel
                -- dimensions get the +0.5 center offset they need (plain
                -- SnapForES drifts by 1px on save & exit for odd dimensions).
                if PPa then
                    local es = frame:GetEffectiveScale()
                    local isCenterAnchor = (pt == "CENTER" and rpt == "CENTER")
                    if isCenterAnchor and PPa.SnapCenterForDim then
                        px = PPa.SnapCenterForDim(px, frame:GetWidth() or 0, es)
                        py = PPa.SnapCenterForDim(py, frame:GetHeight() or 0, es)
                    elseif PPa.SnapForES then
                        px = PPa.SnapForES(px, es)
                        py = PPa.SnapForES(py, es)
                    end
                end
                frame:ClearAllPoints()
                frame:SetPoint(pt, UIParent, rpt, px, py)
            end
            end -- anchored else
        end
    end
    -- Note: anchored bars are handled later in RegisterWithUnlockMode
    -- (0.5s deferred) via ReapplyOwnAnchor, after elements are registered.
end



-------------------------------------------------------------------------------
--  Unlock Mode Integration
--  Register bars with EUI_UnlockMode for positioning.
-------------------------------------------------------------------------------
local function RegisterWithUnlockMode()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement

    local elements = {}
    local orderBase = 200

    for idx, info in ipairs(BAR_CONFIG) do
        local key = info.key
        elements[#elements + 1] = MK({
            key   = key,
            label = info.label,
            group = "Action Bars",
            order = orderBase + idx,
            isHidden = function()
                local s = EAB.db.profile.bars[info.key]
                return s and s.alwaysHidden
            end,
            getFrame = function() return barFrames[info.key] end,
            getSize = function()
                local frame = barFrames[info.key]
                if not frame then return 1, 1 end
                return frame:GetWidth(), frame:GetHeight()
            end,
            linkedDimensions = true,
            -- Blizzard Style: EUI does not control bar sizing (the options
            -- Icon Size slider is disabled for the same reason), so refuse
            -- new width/height matches and never let a match apply or an
            -- unmatch width-persist write buttonWidth/_matchExtraPixels
            -- junk into the EUI-style settings.
            matchUnavailable = function()
                if EAB.db.profile.useBlizzardStyle then
                    return EllesmereUI.L("Size matching is unavailable with Blizzard Style Action Bars.")
                end
            end,
            setWidth = function(_, w)
                local s = EAB.db.profile.bars[info.key]
                if not s then return end
                if EAB.db.profile.useBlizzardStyle then return end
                -- Reverse-engineer square button size from total bar width
                -- using physical pixel math to distribute remainder pixels.
                local numIcons = s.overrideNumIcons or s.numIcons or info.count
                local numRows  = s.overrideNumRows  or s.numRows  or 1
                if numRows < 1 then numRows = 1 end
                local stride   = math.ceil(numIcons / numRows)
                if stride < 1 then stride = 1 end
                local isVert   = (s.orientation == "vertical")
                local pad      = s.buttonPadding or 2
                local shape    = s.buttonShape or "none"
                local cols     = isVert and numRows or stride
                local PP = EllesmereUI and EllesmereUI.PP
                local onePx = PP and PP.mult or 1
                local physTarget = math.floor(w / onePx + 0.5)
                local physPad = math.floor(pad / onePx + 0.5)
                local rawPhysBtn = (physTarget - (cols - 1) * physPad) / cols
                if shape ~= "none" and shape ~= "cropped" then
                    rawPhysBtn = rawPhysBtn - math.floor((SHAPE_BTN_EXPAND or 10) / onePx + 0.5)
                end
                if rawPhysBtn < 8 then rawPhysBtn = 8 end
                local basePhysBtn = math.floor(rawPhysBtn)
                s.buttonWidth  = basePhysBtn * onePx
                s.buttonHeight = s.buttonWidth
                -- Compute remainder pixels to distribute across columns
                local shapePhys = 0
                if shape ~= "none" and shape ~= "cropped" then
                    shapePhys = math.floor((SHAPE_BTN_EXPAND or 10) / onePx + 0.5)
                end
                local idealPhys = cols * (basePhysBtn + shapePhys) + (cols - 1) * physPad
                local extra = physTarget - idealPhys
                if extra > 0 and extra <= cols then
                    s._matchExtraPixels = extra
                else
                    s._matchExtraPixels = nil
                end
                LayoutBar(info.key)
            end,
            setHeight = function(_, h)
                local s = EAB.db.profile.bars[info.key]
                if not s then return end
                if EAB.db.profile.useBlizzardStyle then return end
                -- Reverse-engineer square button size from total bar height
                -- using physical pixel math to distribute remainder pixels.
                local numIcons = s.overrideNumIcons or s.numIcons or info.count
                local numRows  = s.overrideNumRows  or s.numRows  or 1
                if numRows < 1 then numRows = 1 end
                local stride   = math.ceil(numIcons / numRows)
                if stride < 1 then stride = 1 end
                local isVert   = (s.orientation == "vertical")
                local pad      = s.buttonPadding or 2
                local shape    = s.buttonShape or "none"
                local rows     = isVert and stride or numRows
                local PP = EllesmereUI and EllesmereUI.PP
                local onePx = PP and PP.mult or 1
                local physTarget = math.floor(h / onePx + 0.5)
                local physPad = math.floor(pad / onePx + 0.5)
                local rawPhysBtn = (physTarget - (rows - 1) * physPad) / rows
                if shape ~= "none" and shape ~= "cropped" then
                    rawPhysBtn = rawPhysBtn - math.floor((SHAPE_BTN_EXPAND or 10) / onePx + 0.5)
                elseif shape == "cropped" then
                    rawPhysBtn = rawPhysBtn / 0.80
                end
                if rawPhysBtn < 8 then rawPhysBtn = 8 end
                local basePhysBtn = math.floor(rawPhysBtn)
                s.buttonWidth  = basePhysBtn * onePx
                s.buttonHeight = s.buttonWidth
                -- Compute remainder pixels to distribute across rows
                local shapePhys = 0
                if shape ~= "none" and shape ~= "cropped" then
                    shapePhys = math.floor((SHAPE_BTN_EXPAND or 10) / onePx + 0.5)
                end
                local croppedH = basePhysBtn + shapePhys
                if shape == "cropped" then
                    croppedH = math.floor(basePhysBtn * 0.80)
                end
                local idealPhys = rows * croppedH + (rows - 1) * physPad
                local extra = physTarget - idealPhys
                if extra > 0 and extra <= rows then
                    s._matchExtraPixelsH = extra
                else
                    s._matchExtraPixelsH = nil
                end
                LayoutBar(info.key)
            end,
            savePos = function(_, point, relPoint, x, y)
                if point and x and y then
                    local sp, sx, sy = EAB:ConvertCenterToEdge(info.key, point, x, y)
                    EAB.db.profile.barPositions[info.key] = {
                        point = sp, relPoint = relPoint or point, x = sx, y = sy,
                    }
                else
                    SaveBarPosition(info.key)
                end
                -- Follow baseline: capture the anchor target's geometry at save
                -- time so ApplyAnchorPosition can shift the absolute saved growth
                -- edge by the target's displacement when the target moves or
                -- resizes at runtime (e.g. an anchored bar whose target gains an
                -- icon). Applies to every growth-direction bar (Stance Bar and
                -- the main/extra action bars) so a perpendicular corner anchor to
                -- a resizing chain target can follow. nil for unanchored/CENTER-
                -- grow bars, so the follow stays off and the pure pin is unchanged.
                do
                    local entry = EAB.db.profile.barPositions[info.key]
                    local s = EAB.db.profile.bars[info.key]
                    local gd = s and (s.growDirection or "up"):upper()
                    if entry and gd and gd ~= "CENTER"
                       and EllesmereUI.GetAnchorTargetCenterUI then
                        entry.tgtx, entry.tgty = EllesmereUI.GetAnchorTargetCenterUI(info.key)
                        if EllesmereUI.GetAnchorTargetEdgesUI then
                            entry.tgtL, entry.tgtR, entry.tgtT, entry.tgtB =
                                EllesmereUI.GetAnchorTargetEdgesUI(info.key)
                        end
                    end
                end
            end,
            loadPos = function()
                return EAB:ConvertEdgeToCenter(info.key, EAB.db.profile.barPositions[info.key])
            end,
            clearPos = function()
                EAB.db.profile.barPositions[info.key] = nil
            end,
            applyPos = function()
                EAB:RecalcFlyoutDirection(info.key)
                -- Anchored bars: position owned by anchor system. But bars
                -- with growth direction need edge bounds applied first so the
                -- live-edge reading in ApplyAnchorPosition has correct data.
                if EllesmereUI and EllesmereUI.IsUnlockAnchored
                   and EllesmereUI.IsUnlockAnchored(info.key) then
                    local s = EAB.db.profile.bars[info.key]
                    local gd = s and (s.growDirection or "up"):upper()
                    if gd and gd ~= "CENTER" and gd ~= "UP" then
                        local pos = EAB.db.profile.barPositions[info.key]
                        local frame = barFrames[info.key]
                        if pos and frame then
                            local pt = pos.point or "CENTER"
                            local px, py = pos.x or 0, pos.y or 0
                            -- Convert CENTER to edge (like CDM's ApplyBarPositionCentered)
                            if pt == "CENTER" then
                                local fw = frame:GetWidth() or 0
                                local fh = frame:GetHeight() or 0
                                if gd == "RIGHT" and fw > 0 then
                                    pt = "LEFT"; px = px - fw / 2
                                elseif gd == "LEFT" and fw > 0 then
                                    pt = "RIGHT"; px = px + fw / 2
                                elseif gd == "DOWN" and fh > 0 then
                                    pt = "TOP"; py = py + fh / 2
                                end
                            end
                            if pt ~= "CENTER" then
                                local PPa = EllesmereUI and EllesmereUI.PP
                                if PPa and PPa.SnapForES then
                                    local es = frame:GetEffectiveScale()
                                    px = PPa.SnapForES(px, es)
                                    py = PPa.SnapForES(py, es)
                                end
                                frame:ClearAllPoints()
                                frame:SetPoint(pt, UIParent, pos.relPoint or "CENTER", px, py)
                            end
                        end
                    end
                    return
                end
                local pos = EAB.db.profile.barPositions[info.key]
                local frame = barFrames[info.key]
                if pos and frame then
                    local pt = pos.point
                    local px, py = pos.x, pos.y
                    local PPa = EllesmereUI and EllesmereUI.PP
                    if PPa and px and py then
                        local es = frame:GetEffectiveScale()
                        local isCenterAnchor = (pt == "CENTER")
                            and (pos.relPoint == "CENTER" or pos.relPoint == nil)
                        if isCenterAnchor and PPa.SnapCenterForDim then
                            px = PPa.SnapCenterForDim(px, frame:GetWidth() or 0, es)
                            py = PPa.SnapCenterForDim(py, frame:GetHeight() or 0, es)
                        elseif PPa.SnapForES then
                            px = PPa.SnapForES(px, es)
                            py = PPa.SnapForES(py, es)
                        end
                    end
                    frame:ClearAllPoints()
                    frame:SetPoint(pt, UIParent, pos.relPoint or pt, px, py)
                end
            end,
        })
    end

    -- Blizzard movable frames (Extra Action Button, Encounter Bar)
    local blizzOrder = orderBase + #BAR_CONFIG
    for _, info in ipairs(EXTRA_BARS) do
        if info.isBlizzardMovable then
            blizzOrder = blizzOrder + 1
            local bk = info.key
            elements[#elements + 1] = MK({
                key   = bk,
                label = info.label,
                group = "Action Bars",
                order = blizzOrder,
                noResize = true,
                getFrame = function() return blizzMovableHolders[bk] end,
                getSize = function()
                    local ov = BLIZZ_MOVABLE_OVERLAY[bk]
                    if ov then return ov.w, ov.h end
                    return 50, 50
                end,
                savePos = function(_, point, relPoint, x, y)
                    if point and x and y then
                        EAB.db.profile.barPositions[bk] = {
                            point = point, relPoint = relPoint or point, x = x, y = y,
                        }
                    end
                    if not EllesmereUI._unlockActive then
                        local holder = blizzMovableHolders[bk]
                        if holder and point and x and y and not InCombatLockdown() then
                            holder:ClearAllPoints()
                            holder:SetPoint(point, UIParent, relPoint or point, x, y)
                        end
                    end
                end,
                loadPos = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    if not pos then return nil end
                    local pt = pos.point
                    return { point = pt, relPoint = pos.relPoint or pt, x = pos.x, y = pos.y }
                end,
                clearPos = function()
                    EAB.db.profile.barPositions[bk] = nil
                end,
                applyPos = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    local holder = blizzMovableHolders[bk]
                    if not holder or InCombatLockdown() then return end
                    holder:ClearAllPoints()
                    if pos then
                        local pt = pos.point
                        local px, py = pos.x, pos.y
                        local PPa = EllesmereUI and EllesmereUI.PP
                        if PPa and px and py then
                            local es = holder:GetEffectiveScale()
                            local isCenterAnchor = (pt == "CENTER")
                                and (pos.relPoint == "CENTER" or pos.relPoint == nil)
                            if isCenterAnchor and PPa.SnapCenterForDim then
                                px = PPa.SnapCenterForDim(px, holder:GetWidth() or 0, es)
                                py = PPa.SnapCenterForDim(py, holder:GetHeight() or 0, es)
                            elseif PPa.SnapForES then
                                px = PPa.SnapForES(px, es)
                                py = PPa.SnapForES(py, es)
                            end
                        end
                        holder:SetPoint(pt, UIParent, pos.relPoint or pt, px, py)
                    else
                        holder:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
                    end
                end,
            })
        end
    end


    EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIActionBars")

    -- Reapply anchors now that elements are registered. RestoreBarPositions
    -- ran before registration (too early for ReapplyOwnAnchor to resolve
    -- frames), so anchored bars are still at their unresolved position.
    -- Skip bars with growth direction: they're pre-positioned at edge by
    -- applyPos and the authoritative pass preserves that via live-edge reading.
    if EllesmereUI.ReapplyOwnAnchor then
        for _, info in ipairs(BAR_CONFIG) do
            if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(info.key) then
                local s = EAB.db.profile.bars[info.key]
                local gd = s and (s.growDirection or "up"):upper()
                if not gd or gd == "CENTER" or gd == "UP" then
                    EllesmereUI.ReapplyOwnAnchor(info.key)
                end
            end
        end
    end
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
    -- Expose for ApplyAnchorPosition's growth-direction edge read.
    EllesmereUI._abBarPositions = self.db.profile.barPositions

    -- Myslot safety net: if a previous session ended while Myslot's window was
    -- open (e.g. /reload), the real bar visibility settings were swapped to
    -- "always". Restore them now -- before any bar is built -- so the swap can
    -- never persist. Unconditional (see EAB:SetMyslotForceShow).
    self:RestoreMyslotBackup()

    -- Mark whether we need to capture Blizzard layout on first install.
    -- The actual capture is deferred to PLAYER_ENTERING_WORLD when
    -- Edit Mode has fully applied bar positions/sizes.
    -- Uses the per-install flag on the SV root, not per-profile.
    local sv = self.db.sv
    self._needsCapture = not sv._capturedOnce_EAB

    -- Slash commands
    -- Expose apply hook for PP scale change re-apply
    _G._EAB_RecalcFlyouts = function()
        for _, info in ipairs(BAR_CONFIG) do
            EAB:RecalcFlyoutDirection(info.key)
        end
    end

    -- MicroBar position is fully Blizzard-owned (Edit Mode). No anchor
    -- flipping needed. Stubs kept so callers don't error.
    _G._EAB_UnlockModeOpen = function() end
    _G._EAB_UnlockModeClose = function() end

    _G._EAB_ApplyKeyDown = function() ApplyKeyDownCVar() end
    _G._EAB_Apply = function()
        -- Re-point the exposed barPositions view at the active profile's
        -- table. Profile swaps replace db.profile wholesale, and the unlock
        -- system reads saved growth edges and follow baselines through this
        -- reference; a stale pointer would read and write another profile's
        -- saved positions.
        if EAB.db and EAB.db.profile and EAB.db.profile.barPositions then
            EllesmereUI._abBarPositions = EAB.db.profile.barPositions
        end
        ApplyAll()
        if not InCombatLockdown() then
            RestoreBarPositions()
            -- Recalculate flyout directions now that bars are at their
            -- final positions. LayoutBar (inside ApplyAll) runs before
            -- RestoreBarPositions, so it computed directions from the
            -- default position, not the user's saved position.
            C_Timer_After(0, function()
                for _, info in ipairs(BAR_CONFIG) do
                    EAB:RecalcFlyoutDirection(info.key)
                end
            end)
        end
    end


    -- Rank (crafted quality) icons: EAB paints its own overlay texture per
    -- button. Blizzard's ProfessionQualityOverlayFrame is created lazily
    -- inside the secure button Update; our buttons no longer receive
    -- ACTIONBAR_SLOT_CHANGED (central dispatcher owns it), so Blizzard's
    -- overlay only ever appeared after a mouseover -- and forcing
    -- UpdateProfessionQuality() from addon code writes the lazily-created
    -- frame onto the secure button's table (tainted field on a protected
    -- frame). Self-painting from EFD sidesteps both: no button-table
    -- writes, no reliance on Blizzard's update timing. Blizzard's overlay
    -- stays hidden everywhere (apply pass + scan + OnShow hook) so the two
    -- renderers never double-draw. Coalesced: ACTIONBAR_SLOT_CHANGED storms
    -- (mouseover-conditional macros re-resolving) collapse into one
    -- deferred scan per frame.
    do
        local qf = CreateFrame("Frame")
        local _qPending = false
        local _rankAtlas = {}       -- quality -> atlas name (false = none found)
        local QueueQualityScan

        local function RankAtlasFor(q)
            local hit = _rankAtlas[q]
            if hit ~= nil then return hit or nil end
            local probe = C_Texture and C_Texture.GetAtlasInfo
            local names = {
                "Professions-Icon-Quality-Tier" .. q .. "-Inv-Small",
                "Professions-Icon-Quality-Tier" .. q .. "-Small",
                "Professions-Icon-Quality-Tier" .. q,
            }
            for i = 1, #names do
                if probe and probe(names[i]) then
                    _rankAtlas[q] = names[i]
                    return names[i]
                end
            end
            _rankAtlas[q] = false
            return nil
        end

        local function SetRankShown(btn, atlas)
            local fd = EFD(btn)
            if not atlas then
                if fd.rankIconTex then fd.rankIconTex:Hide() end
                return
            end
            local tex = fd.rankIconTex
            if not tex then
                -- First paint creates the holder. A new cosmetic child frame
                -- writes nothing onto the secure button's table; skip only
                -- in combat lockdown (next out-of-combat scan paints it).
                if InCombatLockdown() then return end
                local holder = CreateFrame("Frame", nil, btn)
                holder:SetAllPoints(btn)
                holder:SetFrameLevel((btn:GetFrameLevel() or 1) + 18)
                holder:EnableMouse(false)
                tex = holder:CreateTexture(nil, "OVERLAY", nil, 7)
                fd.rankIconHolder = holder
                fd.rankIconTex = tex
            end
            if fd.rankIconAtlas ~= atlas then
                fd.rankIconAtlas = atlas
                -- The atlas name comes straight from Blizzard's quality info
                -- (or the probe-verified fallback), but guard anyway: an
                -- unknown atlas must read as no-rank, not an error.
                if not pcall(tex.SetAtlas, tex, atlas, true) then
                    fd.rankIconAtlas = nil
                    tex:Hide()
                    return
                end
                if EllesmereUI._RANKDEBUG then
                    print("|cff33ff99[Rank]|r atlas", atlas)
                end
            end
            -- Mirror Blizzard's overlay anchor: its template centers an
            -- atlas-sized texture on a point 14,-14 from the button's
            -- TOPLEFT (designed against the default 45px button; scale with
            -- the button so custom sizes keep the proportions).
            local sc = (btn:GetWidth() or 45) / 45
            tex:ClearAllPoints()
            tex:SetPoint("CENTER", btn, "TOPLEFT", 14 * sc, -14 * sc)
            tex:SetScale(sc)
            tex:Show()
            fd.rankIconHolder:Show()
        end

        local function QualityScan()
            _qPending = false
            local bars = EAB.db and EAB.db.profile and EAB.db.profile.bars
            if not bars then return end
            for _, info in ipairs(BAR_CONFIG) do
                local btns = barButtons[info.key]
                local s = bars[info.key]
                if btns and s then
                    local featureOn = s.showRankIcon and true or false
                    for _, btn in ipairs(btns) do
                        local rankAtlas
                        if featureOn then
                            local action = btn:GetAttribute("action") or 0
                            if action > 0 then
                                -- Blizzard's own source, from live
                                -- ActionButton.lua UpdateProfessionQuality: a
                                -- dedicated action API that returns the
                                -- overlay atlas directly. Every other surface
                                -- is dead from an action slot on live
                                -- (verified via in-game debug 2026-07-19):
                                -- C_TradeSkillUI reads off the bare itemID
                                -- are nil (the reagent one returns a flat 2
                                -- for every ranked item), GetActionLink
                                -- returns nil, and the tooltip's name line
                                -- carries no quality markup.
                                local ab = C_ActionBar
                                if ab and ab.GetProfessionQualityInfo
                                   and (not ab.IsItemAction or ab.IsItemAction(action)) then
                                    local qi = ab.GetProfessionQualityInfo(action)
                                    rankAtlas = qi and qi.iconInventory
                                end
                                -- Older-client fallback: crafted quality by
                                -- itemID, mapped through the atlas probe.
                                if not rankAtlas and GetActionInfo then
                                    local aType, aID = GetActionInfo(action)
                                    if aType == "item" and aID then
                                        local ts = C_TradeSkillUI
                                        local q = ts and ts.GetItemCraftedQualityByItemInfo
                                            and ts.GetItemCraftedQualityByItemInfo(aID)
                                        if type(q) == "number" and q >= 1 and q <= 5 then
                                            rankAtlas = RankAtlasFor(q)
                                        end
                                    end
                                end
                                if EllesmereUI._RANKDEBUG and rankAtlas ~= nil then
                                    pcall(function()
                                        print("|cff33ff99[Rank]|r action", action,
                                            "atlas", tostring(rankAtlas))
                                    end)
                                end
                            end
                        end
                        SetRankShown(btn, rankAtlas)
                        -- Blizzard's overlay must never draw over ours: it can
                        -- pre-exist this fix or get shown by a hover-driven
                        -- lazy creation. Hide + install the permanent OnShow
                        -- hide for overlays born after the apply pass ran.
                        local ov = btn.ProfessionQualityOverlayFrame
                        if ov then
                            if ov:IsShown() then ov:SetShown(false) end
                            if not EFD(btn).qualityHooked then
                                ov:HookScript("OnShow", function(self2)
                                    self2:SetShown(false)
                                end)
                                EFD(btn).qualityHooked = true
                            end
                        end
                    end
                end
            end
        end

        QueueQualityScan = function()
            if not _qPending then
                _qPending = true
                C_Timer_After(0, QualityScan)
            end
        end
        EAB._QueueRankScan = QueueQualityScan

        qf:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        -- Loadout/spec swap changes slot CONTENTS but does not reliably fire
        -- ACTIONBAR_SLOT_CHANGED for our EABButtons (same reason the spell
        -- refresh sweep exists), so a rank icon from the old spec's item can
        -- persist on a slot the new spec leaves empty or fills with a spell.
        -- SPELLS_CHANGED covers that swap; the macro name is handled by the
        -- ForceButtonRefresh sweep on the same event.
        qf:RegisterEvent("SPELLS_CHANGED")
        qf:SetScript("OnEvent", QueueQualityScan)
        -- A hover is what makes Blizzard lazily CREATE its overlay (and shows
        -- it in the same breath) -- and no slot event fires from hovering, so
        -- the suppression + our repaint would otherwise lag until the next
        -- slot change. Re-scan off the tooltip hook (coalesced, deferred to a
        -- clean context; same GameTooltip hook pattern as tooltip
        -- suppression). Also converges anything the hover's item-data load
        -- just made resolvable.
        if GameTooltip then
            hooksecurefunc(GameTooltip, "SetAction", QueueQualityScan)
        end
        -- Initial paint (login / reload): bars applied before this block ran.
        QueueQualityScan()
    end

    SLASH_ELLESMEREACTIONBARS1 = "/eab"
    SlashCmdList["ELLESMEREACTIONBARS"] = function(msg)
        if EllesmereUI and EllesmereUI.ShowModule then
            EllesmereUI:ShowModule("EllesmereUIActionBars")
        end
    end

    SLASH_EABQUICKKEYBIND1 = "/kb"
    SlashCmdList["EABQUICKKEYBIND"] = function(msg)
        if InCombatLockdown() then return end
        if not C_AddOns.IsAddOnLoaded("Blizzard_QuickKeybind") then
            C_AddOns.LoadAddOn("Blizzard_QuickKeybind")
        end
        if QuickKeybindFrame then
            QuickKeybindFrame:Show()
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
                -- Convert Blizzard's icon scale to explicit button dimensions.
                -- barBaseSize isn't populated yet (SetupBar runs later), so
                -- read the base size directly from the first Blizzard button.
                local info = BAR_LOOKUP[barKey]
                local baseW, baseH = 45, 45
                if info and info.blizzBtnPrefix then
                    local btn1 = _G[info.blizzBtnPrefix .. "1"]
                    if btn1 then
                        baseW = math.floor((btn1:GetWidth() or 45) + 0.5)
                        baseH = math.floor((btn1:GetHeight() or 45) + 0.5)
                    end
                end
                s.buttonWidth = math.floor(baseW * data.blizzIconScale + 0.5)
                s.buttonHeight = math.floor(baseH * data.blizzIconScale + 0.5)
            end
            if data.alwaysShowButtons ~= nil then
                s.alwaysShowButtons = data.alwaysShowButtons
            end
            -- Visibility: 3=Hidden, 1=InCombat, 2=OutOfCombat, 0=Always
            -- Keep barVisibility and boolean flags in sync so the
            -- options dropdown reflects the actual state.
            if data.visibility then
                if data.visibility == 3 then
                    EAB.VisibilityCompat.ApplyMode(s, "never")
                elseif data.visibility == 1 then
                    EAB.VisibilityCompat.ApplyMode(s, "in_combat")
                elseif data.visibility == 2 then
                    EAB.VisibilityCompat.ApplyMode(s, "out_of_combat")
                else
                    EAB.VisibilityCompat.ApplyMode(s, "always")
                end
            end
            if data.point then
                self.db.profile.barPositions[barKey] = {
                    point = data.point, relPoint = data.relPoint,
                    x = data.x, y = data.y,
                }
            end
        end
    end

    -- Mark capture as done so we never read Edit Mode again (per-install flag)
    self.db.sv._capturedOnce_EAB = true
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

-------------------------------------------------------------------------------
--  Edit Mode Icon Count Sync
--  When EUI's configured icon count for a bar exceeds Edit Mode's setting,
--  update the Edit Mode layout data via C_EditMode.SaveLayouts so Blizzard's
--  own code applies the higher count (untainted). This avoids writing
--  numButtonsShowable directly from addon code which causes taint.
-------------------------------------------------------------------------------
local function SyncEditModeIconCounts()
    if InCombatLockdown() then return end
    if not C_EditMode or not C_EditMode.GetLayouts or not C_EditMode.SaveLayouts then return end

    local ok, layoutInfo = pcall(C_EditMode.GetLayouts)
    if not ok or type(layoutInfo) ~= "table" or type(layoutInfo.layouts) ~= "table" then return end

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

    -- Check ALL layouts so switching never reverts to fewer icons.
    for _, layout in ipairs(layoutInfo.layouts) do
        if type(layout.systems) == "table" then
            for _, sysInfo in ipairs(layout.systems) do
                if sysInfo.system == 0 and sysInfo.systemIndex and type(sysInfo.settings) == "table" then
                    local want = desired[sysInfo.systemIndex]
                    for _, s in ipairs(sysInfo.settings) do
                        if want and s.setting == ICON_COUNT_SETTING and s.value < want then
                            s.value = want
                            changed = true
                        end
                        if HIDE_BAR_ART_SETTING and s.setting == HIDE_BAR_ART_SETTING and s.value ~= 1 then
                            s.value = 1
                            changed = true
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
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(self)
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            self:SetScript("OnEvent", nil)
            SyncEditModeIconCounts()
        end)
        return
    end
    SyncEditModeIconCounts()
end

-- The actual bar creation, positioning, and event registration.
function EAB:FinishSetup()
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
            -- Both broadcasters are killed at file-load time (top of file).
            -- Central dispatcher handles all events.
            EAB:SetupEventDispatcher()
            -- Register secure handler refs now that buttons exist
            SecureSetupHandler_PrepareRefs()
            -- Apply the current page to MainBar buttons. The state driver
            -- evaluated during CreateBarFrame (before buttons existed), so
            -- buttons still have their initial action=slot from GetOrCreateButton.
            -- Recalculate using the actual current page.
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
            local vBtn = MainMenuBarVehicleLeaveButton
            if vBtn and barFrames["MainBar"] then
                vBtn:ClearAllPoints()
                vBtn:SetPoint("BOTTOM", barFrames["MainBar"], "TOPRIGHT", -15, 2)
            end
        else
            -- Combat reload: non-protected setup only; secure handler does the rest.
            -- Stock bar disposal (including ActionBarParent) already happened at
            -- file load time. OverrideActionBar is fully Blizzard-owned.
            C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_1", "1")
            C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_2", "1")
            C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_3", "1")
            C_CVar.SetCVar("SHOW_MULTI_ACTIONBAR_4", "1")

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

        -- Visual styling: defer visuals to out-of-combat if needed.
        local function DoVisuals()
            ApplyAll()
            -- Reapply unlock-mode positions + anchor chains now that bars exist.
            -- (The EUI_UnlockMode hook on EAB.ApplyAll doesn't fire because
            -- ApplyAll is a local function, not on the addon table.)
            if EllesmereUI._applySavedPositions then
                -- NOTE: C_Timer callbacks do not run during the loading
                -- screen, so on a combat reload this fires after lockdown
                -- has re-engaged. The in-window pass lives in
                -- EUI_UnlockMode's synchronous PLAYER_LOGIN handler; this
                -- delayed pass is the settle correction once element sizes
                -- stabilize.
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
            -- fresh EABButton frames (a per-button listener here dispatched
            -- every slot-change storm event to every button); the UpdateCount
            -- hook covers Blizzard buttons that receive events natively.
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

    -- Set override keybindings immediately at load time, before combat
    -- state is restored. This ensures keybinds work on /reload in combat.
    UpdateKeybinds()

    -- Re-apply saved "Toggle Action Bar" visibility keybinds.
    EAB:RebuildVisToggleBindings()

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
        if InCombatLockdown() then return end
        -- If something is still on the cursor (spell swap), don't restore yet
        if GetCursorInfo() then return end
        for key in pairs(_gridSurfacedBars) do
            local info = BAR_LOOKUP[key]
            local s = EAB.db.profile.bars[key]
            local frame = barFrames[key]
            if info and s and frame then
                local vis = s.barVisibility or "always"
                if vis ~= "always" and vis ~= "never" then
                    RegisterAttributeDriver(frame, "state-visibility", BuildVisibilityString(info, s))
                end
                if s.mouseoverEnabled then
                    -- The drag has fully ended (cursor cleared, checked above). If
                    -- the cursor is still over this bar, the spell was dropped here
                    -- (or you're just hovering it), so keep it shown and let the
                    -- normal OnLeave fade it on real exit. Otherwise hide as before.
                    local state = hoverStates[key]
                    StopFade(frame)
                    if frame:IsMouseOver() then
                        if state then state.isHovered = true; state.fadeDir = "in" end
                        frame:SetAlpha(s._savedBarAlpha or 1)
                        if key == "MainBar" then SyncPagingAlpha(s._savedBarAlpha or 1) end
                    else
                        if state then state.isHovered = false; state.fadeDir = "out" end
                        frame:SetAlpha(0)
                        if key == "MainBar" then SyncPagingAlpha(0) end
                    end
                end
            end
        end
        wipe(_gridSurfacedBars)
    end
    -- 12.1: registering events on a frame stamps it with the EventRegistrations
    -- forbidden aspect, and the restricted environment refuses frames carrying
    -- any aspect. The controller wraps buttons and executes snippets, so its
    -- events must live on a plain sidecar listener, never on the controller.
    EAB._abcEvents = CreateFrame("Frame")
    EAB._abcEvents:SetScript("OnEvent", function(_, event)
        if event == "ACTIONBAR_SHOWGRID" then
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
                        if s and frame and not s.alwaysHidden then
                            local vis = s.barVisibility or "always"
                            local hasCondition = vis ~= "always" and vis ~= "never"
                                or s.visHideNoTarget or s.visHideNoEnemy
                                or s.visHideMounted or s.visOnlyInstances
                            if hasCondition then
                                _gridSurfacedBars[info.key] = true
                                RegisterAttributeDriver(frame, "state-visibility", "show")
                                frame:Show()
                            end
                            -- Mouseover bars: force alpha to 1 during drag
                            if s.mouseoverEnabled then
                                _gridSurfacedBars[info.key] = true
                                StopFade(frame)
                                frame:SetAlpha(1)
                            end
                        end
                    end
                end
            end
        elseif event == "ACTIONBAR_HIDEGRID" or event == "PET_BAR_HIDEGRID" then
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
        elseif event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
            -- Force visibility update on all managed buttons
            if not InCombatLockdown() then
                for btn in pairs(_controllerButtons) do
                    local showgrid = btn:GetAttribute("showgrid") or 0
                    local hasAction = btn.HasAction and btn:HasAction()
                    local hidden = btn:GetAttribute("statehidden")
                    if not hidden and (showgrid > 0 or hasAction) then
                        if not btn:IsShown() then
                            btn:Show()
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

    -- Attach hover hooks for mouseover
    for _, info in ipairs(BAR_CONFIG) do
        AttachHoverHooks(info.key)
    end

    -- When a spell flyout closes, fade out any bars that were kept visible by it
    do
        local flyFrame = GetEABFlyout():GetFrame()
        if flyFrame then
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
                        StopFade(frame)
                        local fullAlpha = s._savedBarAlpha or 1
                        frame:SetAlpha(fullAlpha)
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
                if not _gridState.shown then
                    OnGridChange()
                end
                -- Force mouseover bars visible during real cursor drags
                _gridState._mouseoverForced = true
                for _, info in ipairs(BAR_CONFIG) do
                    local s = EAB.db.profile.bars[info.key]
                    if s and s.mouseoverEnabled then
                        local frame = barFrames[info.key]
                        if frame then
                            StopFade(frame)
                            frame:SetAlpha(1)
                            if info.key == "MainBar" then SyncPagingAlpha(1) end
                        end
                    end
                end
                -- Show During Drag (per-bar opt-in, s.dragShow): surface bars
                -- saved as Never so the drag can be dropped onto them.
                -- Surgical -- every other visibility mode already shows
                -- during a drag (the mouseover forcing above, conditional
                -- drivers). Reuses the runtime _visOverride slot (never
                -- persisted) and skips bars the toggle keybind already
                -- overrides. Secure driver swaps are combat-blocked, so
                -- combat drags leave Never bars hidden.
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
            if _gridState.shown then
                _gridState.shown = false
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
        -- Quick Keybind buttons may need reassertion after combat transitions
        _quickKeybindState.ReassertButtonsAfterCombatChange()
    end)

    self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        _quickKeybindState.ReassertButtonsAfterCombatChange()
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
                              or EAB_VTABLE.HasVehicleActionBar()

            local inHousing = IsHouseEditorActive and IsHouseEditorActive()
            if not inHousing and _bindState.housingCleared then
                _bindState.housingCleared = false
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
    -- Immediate soft-target override: when the only "target" is a soft-
    -- interact NPC (dialogue in view cone), the [noexists] state driver
    -- instantly shows the bar. Override to "hide" in the same frame so
    -- the bar never visibly flashes. The deferred UpdateHousingVisibility
    -- that follows handles the general case and will restore the normal
    -- driver string when the soft target clears.
    local function ImmediateSoftTargetCheck()
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
            if s and s.visHideNoTarget and not (self._visOverride and self._visOverride[info.key]) then
                local frame = barFrames[info.key]
                if frame then
                    if softOnly then
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
    -- Polling fallback: some soft-target transitions (notably Action Targeting
    -- walking into range) do not reliably fire the dedicated soft-target events
    -- on every client/patch. Check the soft-target unit tokens every 0.1s and
    -- sync visibility only when the state actually changes.
    --
    -- Gated on _anyHideNoTarget: for users with no "Hide when No Target" bar this
    -- is a single flag check that then returns, so the machinery costs nothing.
    -- The state token is four cached booleans (no per-tick string allocation) and
    -- the refresh only runs when a soft-target token actually flips.
    self:_RefreshSoftTargetGate()
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
    -- Combat exit: synchronously restore all visHideNoTarget bar state drivers.
    -- During combat, ImmediateSoftTargetCheck and UpdateHousingVisibility are
    -- blocked by InCombatLockdown. If a bar's driver was overridden to "hide"
    -- (soft-target override) before combat started, it stays stuck the entire
    -- fight. The shared visibility dispatcher uses a double-deferred path that
    -- can miss rapid combat re-entry. This handler runs at the exact frame
    -- lockdown lifts, with no deferral, guaranteeing restoration.
    do
        local regenFrame = CreateFrame("Frame")
        regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        regenFrame:SetScript("OnEvent", function()
            for _, info in ipairs(ALL_BARS) do
                local s = self.db.profile.bars[info.key]
                if s and s.visHideNoTarget and not (self._visOverride and self._visOverride[info.key]) then
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
    self:RegisterEvent("ACTIONBAR_HIDEGRID", OnGridHide)
    self:RegisterEvent("PET_BAR_HIDEGRID", OnGridHide)

    -- Spell updates: refresh button icons and visibility
    -- Also re-layout the stance bar since GetNumShapeshiftForms() may have changed
    self:RegisterEvent("SPELLS_CHANGED", function()
        if _gridState.spellsPending then return end
        _gridState.spellsPending = true
        C_Timer_After(0, function()
            _gridState.spellsPending = false
            LayoutBar("StanceBar")
            self:RefreshRuntimeVisibility() -- form count may have changed; re-eval stance bar show/hide
            for _, info in ipairs(BAR_CONFIG) do
                self:ApplyAlwaysShowButtons(info.key)
            end
            -- Force visual refresh on all action buttons. Spec swap
            -- changes which spells occupy each slot; the C-side
            -- ACTIONBAR_SLOT_CHANGED handler may not fire UpdateAction
            -- on our EABButton frames (double-template). Without this,
            -- cooldown swipes (including GCD) can disappear after swap.
            -- A spec swap changes slot CONTENTS while the slot numbers stay
            -- identical, so this needs the forced refresh path (see
            -- ForceButtonRefresh; also handles the 12.1 secret-safe variant).
            for _, info in ipairs(BAR_CONFIG) do
                if not info.isStance and not info.isPetBar then
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
    -- shared debounced visibility queue.
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", QueueAlwaysShowButtonsRefresh)

    -- Pet bar: re-layout and refresh visibility when the pet's action bar
    -- changes. PET_BAR_UPDATE covers ability changes; PET_UI_UPDATE covers
    -- summoning/dismissal; UNIT_PET covers pet swaps. PLAYER_ENTERING_WORLD
    -- ensures button state is populated on login (PetActionBar was
    -- unregistered from all events, so Blizzard's own update never fires).
    -- PET_BAR_UPDATE_USABLE fires when action usability changes (energy/focus
    -- state, etc.) so icon dimming stays current. UNIT_AURA "pet" fires when
    -- an aura on the pet changes, which can also affect ability usability.
    local _petUpdateQueued = false
    local function UpdatePetBar(_, event)
        -- UNIT_AURA fires very frequently; throttle to one update per frame
        if event == "UNIT_AURA" or event == "PET_BAR_UPDATE_USABLE" then
            if _petUpdateQueued then return end
            _petUpdateQueued = true
        end
        C_Timer_After(0, function()
            _petUpdateQueued = false
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
            if InCombatLockdown() then
                -- Combat-safe path: update textures and visual state per-button
                -- without touching protected frame operations (Show/Hide/SetParent).
                -- This allows pet abilities to appear when summoning a pet mid-combat.
                local hasPetBar = PetHasActionBar()
                for i = 1, NUM_PET_ACTION_SLOTS do
                    local btn = _G["PetActionButton" .. i]
                    if btn then
                        local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled = GetPetActionInfo(i)
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
                        local ctA = EAB:GetCheckedAlpha()
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
    _petEventFrame:RegisterEvent("PET_BAR_UPDATE_USABLE")
    _petEventFrame:RegisterEvent("PET_UI_UPDATE")
    _petEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _petEventFrame:RegisterUnitEvent("UNIT_PET", "player")
    _petEventFrame:RegisterUnitEvent("UNIT_AURA", "pet")
    _petEventFrame:SetScript("OnEvent", UpdatePetBar)

    -- Stance bar GCD / cooldown swipe.
    --
    -- Blizzard drives the shapeshift cooldown swipe exclusively through the
    -- StanceBar frame's UPDATE_SHAPESHIFT_COOLDOWN -> StanceBarMixin:UpdateState.
    -- HideBlizzardBars() unregisters all events on the StanceBar frame, so that
    -- path is dead. The swipe only ever appeared by accident: a bar transition
    -- (form change, Ascendance, etc.) makes ValidateActionBarTransition re-Show()
    -- StanceBar, whose OnShow -> Update -> UpdateState sets the cooldown on the
    -- (reparented but identical) StanceButton frames before our OnShow hook
    -- re-hides the now-empty bar. A plain GCD from a spell that does NOT change
    -- form fires UPDATE_SHAPESHIFT_COOLDOWN with no transition, so nothing ran
    -- and the form-lockout swipe was invisible.
    --
    -- Mirror Blizzard's cooldown update directly on our reused StanceButtons.
    -- Visual-only (CooldownFrame_Set touches no protected state), so it is safe
    -- during combat, same as the pet PET_BAR_UPDATE_COOLDOWN path above.
    local function UpdateStanceCooldowns()
        local numForms = GetNumShapeshiftForms()
        for i = 1, numForms do
            local btn = _G["StanceButton" .. i]
            if btn and btn.cooldown then
                local start, duration, enable = GetShapeshiftFormCooldown(i)
                CooldownFrame_Set(btn.cooldown, start, duration, enable)
            end
        end
    end
    local _stanceEventFrame = CreateFrame("Frame")
    _stanceEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN")
    _stanceEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    _stanceEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _stanceEventFrame:SetScript("OnEvent", UpdateStanceCooldowns)


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
                bar:SetParent(hiddenParent)
                bar:Hide()
            end
        end
        -- Both event broadcasters are killed at file-load time (top of file).
        -- Redundant kill here as safety net in case Blizzard re-creates them.
        if _G.ActionBarButtonEventsFrame then _G.ActionBarButtonEventsFrame:UnregisterAllEvents() end
        if _G.ActionBarActionEventsFrame then _G.ActionBarActionEventsFrame:UnregisterAllEvents() end
    end)

    -- Hook Show on stock bars so they can never re-appear regardless
    -- of what fires them (talent changes, spec swaps, zone transitions, etc.)
    -- Guarded with InCombatLockdown: calling Hide() on a protected frame
    -- from addon code during combat is blocked (ADDON_ACTION_BLOCKED).
    -- Since these bars are reparented to hiddenParent, they are invisible
    -- regardless of their shown state, so skipping Hide() in combat is safe.
    for _, entry in ipairs(STOCK_BAR_DISPOSAL) do
        local bar = _G[entry.name]
        if bar then
            bar:HookScript("OnShow", function(self)
                if not InCombatLockdown() then
                    self:Hide()
                end
            end)
        end
    end

    -- Register with unlock mode immediately. FinishSetup runs at
    -- PLAYER_LOGIN, inside the pre-lockdown window on a combat reload, so
    -- registering now (instead of on a timer) lets the position pass in
    -- DoVisuals resolve anchored elements before lockdown re-engages.
    -- (EllesmereUI is a hard dependency, so it is always loaded here.)
    RegisterWithUnlockMode()

    -- Apply visibility drivers now, for the same reason: the real
    -- conditional driver strings (e.g. the PetBar's [pet]-gated visibility)
    -- must register before combat lockdown re-engages -- the secure state
    -- engine then evaluates them correctly even IN combat. The ApplyAll
    -- visibility pass is skipped while in combat, so without this call a
    -- combat reload left bars on their placeholder "show" driver (petless
    -- PetBar visible) until combat dropped. Idempotent out of combat: the
    -- _eabLastVisStr cache skips unchanged re-registrations, so the later
    -- ApplyAll pass is a no-op for these. Extra bars (built on a later
    -- timer) are nil-skipped here, exactly as on a normal login.
    self:ApplyCombatVisibility()
end

-------------------------------------------------------------------------------
--  Data Bars (XP Bar, Reputation Bar)
-------------------------------------------------------------------------------
-- dataBarFrames is forward-declared near barFrames at the top of the file
ns.dataBarFrames = dataBarFrames

-- Data bar colors
local DATA_BAR_COLORS = {
    xpRested   = { r = 0.00, g = 0.44, b = 0.87 },  -- shaman blue (XP when rested)
    xpNoRest   = { r = 0.60, g = 0.40, b = 0.85 },  -- purple (XP when no rested)
    xpRestedBG = { r = 0.15, g = 0.30, b = 0.60 },  -- dark blue (rested overlay)
    favor = { r = 0.85, g = 0.64, b = 0.22 },   -- warm gold (house favor)
    rep = {
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
    },
}

-- Data bar textures: the suite's built-in bar texture set + SharedMedia.
-- ns-hosted (no new file-scope locals; the chunk is at the 200-local cap).
do
    local base = "Interface\\AddOns\\EllesmereUI\\media\\textures\\"
    local lookup = {
        ["none"]          = nil,
        ["melli"]         = base .. "melli.tga",
        ["beautiful"]     = base .. "beautiful.tga",
        ["plating"]       = base .. "plating.tga",
        ["atrocity"]      = base .. "atrocity.tga",
        ["divide"]        = base .. "divide.tga",
        ["glass"]         = base .. "glass.tga",
        ["fade-right"]    = base .. "fade-right.tga",
        ["thin-line-top"] = base .. "thin-line-top.tga",
        ["thin-line-bottom"] = base .. "thin-line-bottom.tga",
        ["fade"]          = base .. "fade.tga",
        ["gradient-lr"]   = base .. "gradient-lr.tga",
        ["gradient-rl"]   = base .. "gradient-rl.tga",
        ["gradient-bt"]   = base .. "gradient-bt.tga",
        ["gradient-tb"]   = base .. "gradient-tb.tga",
        ["matte"]         = base .. "matte.tga",
        ["sheer"]         = base .. "sheer.tga",
    }
    local names = {
        ["none"]          = "None",
        ["melli"]         = "Melli (ElvUI)",
        ["beautiful"]     = "Beautiful",
        ["plating"]       = "Plating",
        ["atrocity"]      = "Atrocity",
        ["divide"]        = "Divide",
        ["glass"]         = "Glass",
        ["fade-right"]    = "Fade Right",
        ["thin-line-top"] = "Thin Line Top",
        ["thin-line-bottom"] = "Thin Line Bottom",
        ["fade"]          = "Fade",
        ["gradient-lr"]   = "Gradient Right",
        ["gradient-rl"]   = "Gradient Left",
        ["gradient-bt"]   = "Gradient Up",
        ["gradient-tb"]   = "Gradient Down",
        ["matte"]         = "Matte",
        ["sheer"]         = "Sheer",
    }
    local order = {
        "none", "melli", "atrocity",
        "fade", "fade-right",
        "thin-line-top", "thin-line-bottom",
        "beautiful", "plating",
        "divide", "glass",
        "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
        "matte", "sheer",
    }
    if EllesmereUI.AppendSharedMediaTextures then
        EllesmereUI.AppendSharedMediaTextures(names, order, nil, lookup)
    end
    ns.dataBarTextures = lookup
    ns.dataBarTextureNames = names
    ns.dataBarTextureOrder = order
end

function ns.ResolveDataBarTexture(key)
    if key and key ~= "none" then
        local path = EllesmereUI and EllesmereUI.ResolveTexturePath
            and EllesmereUI.ResolveTexturePath(ns.dataBarTextures, key, nil)
        if path then return path end
    end
    return "Interface\\BUTTONS\\WHITE8X8"
end

-- Color mode per bar: nil/reactive = state-driven defaults, "accent" = live
-- accent color, "custom" = stored custom color.
function ns.ResolveDataBarColor(s, r, g, b)
    local mode = s and s.colorMode
    if mode == "accent" then
        local EG = EllesmereUI.ELLESMERE_GREEN
        if EG then return EG.r or r, EG.g or g, EG.b or b end
    elseif mode == "custom" then
        local c = s.customColor
        if c then return c.r or 1, c.g or 1, c.b or 1 end
        return 1, 1, 1
    end
    return r, g, b
end

-- Accent-mode bars repaint live when the user changes the accent color.
if EllesmereUI.RegAccent then
    EllesmereUI.RegAccent({ type = "callback", fn = function()
        for _, bk in ipairs({ "XPBar", "RepBar", "FavorBar" }) do
            local f = dataBarFrames[bk]
            if f and f._updateFunc then f._updateFunc() end
        end
    end })
end

local function ApplyDataBarLayout(barKey)
    local frame = dataBarFrames[barKey]
    if not frame then return end
    local s = EAB.db.profile.bars[barKey]
    if not s then return end
    local w = s.width or 400
    local h = s.height or 18
    local orient = s.orientation or "HORIZONTAL"

    -- Centered growth on resize is handled by the centralized unlock mode
    -- position system (NotifyElementResized re-applies CENTER anchor).
    local PP = EllesmereUI and EllesmereUI.PP
    if PP then
        PP.Size(frame, w, h)
    else
        frame:SetSize(w, h)
    end

    local texPath = ns.ResolveDataBarTexture(s.barTexture)
    frame._bar:SetStatusBarTexture(texPath)
    frame._bar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 4)
    if frame._restedBar then
        frame._restedBar:SetStatusBarTexture(texPath)
        frame._restedBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 2)
    end

    frame._bar:SetOrientation(orient)
    frame._bar:SetRotatesTexture(orient ~= "HORIZONTAL")
    if frame._restedBar then
        frame._restedBar:SetOrientation(orient)
        frame._restedBar:SetRotatesTexture(orient ~= "HORIZONTAL")
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
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(text, GetEABUseShadow()) end
    text:SetFont(FONT_PATH, 9, GetEABOutline())
    text:SetPoint("CENTER")
    text:SetTextColor(1, 1, 1, 1)

    holder._bar = bar
    holder._text = text
    holder._updateFunc = updateFunc

    dataBarFrames[barKey] = holder
    return holder
end

-- Data bars own their content updates, but visibility is shared with the
-- generic non-secure visibility system above. Guard each update callback so a
-- later XP/reputation event cannot re-show a bar that runtime conditions have
-- already hidden (for example `solo` while grouped).
function EAB_VTABLE.ExtraBars.BeginManagedDataBarUpdate(barKey)
    local frame = dataBarFrames[barKey]
    if not frame then return nil, nil end
    local info = BAR_LOOKUP[barKey]
    if EAB.db.profile.useBlizzardDataBars then
        if info then
            EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(info, frame, EAB.db.profile.bars[barKey], false, true)
        else
            frame:Hide()
        end
        return nil, nil
    end

    local s = EAB.db.profile.bars[barKey]
    if not s then return nil, nil end
    if s.alwaysHidden or not EAB_VTABLE.ExtraBars.ShouldShowManagedNonSecureBar(s) then
        if info then
            EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(info, frame, s, false, true)
        else
            frame:Hide()
        end
        return nil, s
    end

    return frame, s
end

function EAB_VTABLE.ExtraBars.FinishManagedDataBarUpdate(barKey, frame, s)
    if not frame or not s then return end

    local info = BAR_LOOKUP[barKey]
    if info then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(info, frame, s, true, true)
    else
        frame:Show()
    end
end

-------------------------------------------------------------------------------
--  XP Bar
-------------------------------------------------------------------------------
-- Max-level check with layered fallbacks. The Is* helpers are nil-guarded, so
-- client API churn can silently disable them -- a plain numeric compare
-- against the expansion max level backstops the check so the bar can never
-- show for a max-level character.
function ns.XPBarAtMaxLevel()
    local level = UnitLevel("player") or 0
    if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then return true end
    if IsLevelAtEffectiveMaxLevel and IsLevelAtEffectiveMaxLevel(level) then return true end
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
        or (GetMaxPlayerLevel and GetMaxPlayerLevel())
    return (maxLevel and level >= maxLevel) or false
end

local function UpdateXPBar()
    local frame, s = EAB_VTABLE.ExtraBars.BeginManagedDataBarUpdate("XPBar")
    if not frame then return end

    local bar = frame._bar
    local text = frame._text

    -- Hide at max level (or XP disabled)
    if ns.XPBarAtMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled()) then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["XPBar"], frame, s, false, true)
        return
    end

    local currentXP = UnitXP("player")
    local maxXP = UnitXPMax("player")
    if maxXP <= 0 then maxXP = 1 end
    local restedXP = GetXPExhaustion() or 0
    local level = UnitLevel("player")

    bar:SetMinMaxValues(0, maxXP)
    bar:SetValue(currentXP)

    -- Rested XP overlay
    local restedBar = frame._restedBar
    if restedXP > 0 then
        bar:SetStatusBarColor(ns.ResolveDataBarColor(s, DATA_BAR_COLORS.xpRested.r, DATA_BAR_COLORS.xpRested.g, DATA_BAR_COLORS.xpRested.b))
        restedBar:SetMinMaxValues(0, maxXP)
        restedBar:SetValue(min(currentXP + restedXP, maxXP))
        restedBar:SetStatusBarColor(DATA_BAR_COLORS.xpRestedBG.r, DATA_BAR_COLORS.xpRestedBG.g, DATA_BAR_COLORS.xpRestedBG.b, 0.5)
        restedBar:Show()
    else
        bar:SetStatusBarColor(ns.ResolveDataBarColor(s, DATA_BAR_COLORS.xpNoRest.r, DATA_BAR_COLORS.xpNoRest.g, DATA_BAR_COLORS.xpNoRest.b))
        restedBar:Hide()
    end

    local config = (EAB and EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars["XPBar"]) or {}
    local showLevel = config.showLevel
    local showRawValues = config.showRawValues

    local strLevel = ""
    local strXP = ""
    local strRested = ""

    if showLevel then
        strLevel = format("%s %d - ", LEVEL, level)
    end

    if showRawValues then
        strXP = format("%s / %s", AbbreviateLargeNumbers(currentXP), AbbreviateLargeNumbers(maxXP))
    else
        local pct = (currentXP / maxXP) * 100
        strXP = format("%.1f%%", pct)
    end

    if restedXP > 0 then
        if showRawValues then
            strRested = format(" (Rested: %s)", AbbreviateLargeNumbers(restedXP))
        else
            local restedPct = (restedXP / maxXP) * 100
            strRested = format(" (Rested: %.1f%%)", restedPct)
        end
    end

    text:SetText(strLevel .. strXP .. strRested)

    EAB_VTABLE.ExtraBars.FinishManagedDataBarUpdate("XPBar", frame, s)
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
        if ns.XPBarAtMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled()) then return end
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
    local frame, s = EAB_VTABLE.ExtraBars.BeginManagedDataBarUpdate("RepBar")
    if not frame then return end

    local bar = frame._bar
    local text = frame._text

    local data = C_Reputation and C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
    if not data or not data.name then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["RepBar"], frame, s, false, true)
        return
    end

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
                EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["RepBar"], frame, s, false, true)
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

    local color = DATA_BAR_COLORS.rep[reaction] or DATA_BAR_COLORS.rep[4]
    bar:SetStatusBarColor(ns.ResolveDataBarColor(s, color.r, color.g, color.b))

    -- Hide capped / maxed factions (Exalted with no paragon, max friendship, etc.)
    if nextReactionThreshold == math.huge or currentReactionThreshold == nextReactionThreshold then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["RepBar"], frame, s, false, true)
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

    EAB_VTABLE.ExtraBars.FinishManagedDataBarUpdate("RepBar", frame, s)
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
--  House Favor Bar
--  Blizzard's "Show as Experience Bar" favor watch renders through
--  StatusTrackingBarManager, which the custom data bars replace -- this bar
--  is the house-favor equivalent. The favor API is asynchronous:
--  GetPlayerOwnedHouses() -> PLAYER_HOUSE_LIST_UPDATED (house list) ->
--  GetCurrentHouseLevelFavor(guid) -> HOUSE_LEVEL_FAVOR_UPDATED (level +
--  favor payload); GetHouseLevelFavorForLevel(n) is the only sync read.
-------------------------------------------------------------------------------
-- do-end scoped + ns export: the file-scope local budget is nearly at the
-- Lua 5.1 200 cap.
do
local favorState  -- { level, displayLevel, favor, needed } from the last payload
local favorEv, favorArmed
local ArmFavorEvents  -- forward: mutual recursion with UpdateFavorBar

-- No favor requests or repaints inside an active keystone or a raid
-- instance.
local function FavorBlocked()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive() then
        return true
    end
    local inInst, instType = IsInInstance()
    return (inInst and instType == "raid") and true or false
end

-- Zero cost while hidden: events stay unregistered unless the bar can
-- actually show.
local function FavorWanted()
    if not (C_Housing and C_Housing.GetPlayerOwnedHouses) then return false end
    local p = EAB.db and EAB.db.profile
    if not p or p.useBlizzardDataBars then return false end
    local s = p.bars and p.bars.FavorBar
    return (s and not s.alwaysHidden) and true or false
end

local function UpdateFavorBar()
    if ArmFavorEvents then ArmFavorEvents() end
    local frame, s = EAB_VTABLE.ExtraBars.BeginManagedDataBarUpdate("FavorBar")
    if not frame then return end

    local bar = frame._bar
    local text = frame._text

    -- No house / no data yet / max house level (no next-level requirement).
    local st = favorState
    if not st or not st.needed or st.needed <= 0 then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["FavorBar"], frame, s, false, true)
        return
    end

    local current = st.favor or 0
    if current > st.needed then current = st.needed end
    bar:SetMinMaxValues(0, st.needed)
    bar:SetValue(current)
    bar:SetStatusBarColor(ns.ResolveDataBarColor(s, DATA_BAR_COLORS.favor.r, DATA_BAR_COLORS.favor.g, DATA_BAR_COLORS.favor.b))

    local pct = (current / st.needed) * 100
    text:SetText(format("House Level %d: %d / %d", st.displayLevel or 1, current, st.needed))

    -- Auto-size text if bar is too narrow
    local barW = frame:GetWidth()
    if text:GetStringWidth() > barW - 4 then
        text:SetText(format("%.0f%%", pct))
    end

    EAB_VTABLE.ExtraBars.FinishManagedDataBarUpdate("FavorBar", frame, s)
end

local function OnFavorEvent(_, event, arg1)
    if FavorBlocked() then return end
    if not (C_Housing and C_Housing.GetPlayerOwnedHouses) then return end
    if event == "PLAYER_ENTERING_WORLD" then
        C_Housing.GetPlayerOwnedHouses()
    elseif event == "PLAYER_HOUSE_LIST_UPDATED" then
        local info = type(arg1) == "table" and arg1[1]
        local guid = info and info.houseGUID
        if guid and C_Housing.GetCurrentHouseLevelFavor then
            C_Housing.GetCurrentHouseLevelFavor(guid)
        else
            favorState = nil
            UpdateFavorBar()
        end
    elseif event == "HOUSE_LEVEL_FAVOR_UPDATED" then
        if type(arg1) == "table" and arg1.houseLevel ~= nil then
            local level = arg1.houseLevel or 0
            local needed = C_Housing.GetHouseLevelFavorForLevel
                and C_Housing.GetHouseLevelFavorForLevel(level + 1)
            favorState = {
                level = level,
                displayLevel = level + 1,
                favor = arg1.houseFavor or 0,
                needed = needed or 0,
            }
        else
            favorState = nil
        end
        UpdateFavorBar()
    end
end

ArmFavorEvents = function()
    local want = FavorWanted()
    if want and not favorArmed then
        favorArmed = true
        if not favorEv then
            favorEv = CreateFrame("Frame")
            favorEv:SetScript("OnEvent", OnFavorEvent)
        end
        favorEv:RegisterEvent("PLAYER_ENTERING_WORLD")
        favorEv:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
        favorEv:RegisterEvent("HOUSE_LEVEL_FAVOR_UPDATED")
        -- Kick the async chain now; if inside blocked content the next
        -- world-enter re-kicks instead.
        if not FavorBlocked() then
            C_Housing.GetPlayerOwnedHouses()
        end
    elseif not want and favorArmed then
        favorArmed = false
        if favorEv then favorEv:UnregisterAllEvents() end
    end
end

local function CreateFavorBar()
    local holder = CreateDataBarFrame("FavorBar", UpdateFavorBar)
    holder:SetPoint("TOP", UIParent, "TOP", 0, -68)

    -- Tooltip
    holder:EnableMouse(true)
    holder:SetScript("OnEnter", function(self)
        local st = favorState
        if not st or not st.needed or st.needed <= 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("House Favor", 1, 1, 1)
        GameTooltip:AddDoubleLine("House Level", tostring(st.displayLevel or 1), 1, 1, 1, 1, 1, 1)
        local current = math.min(st.favor or 0, st.needed)
        local pct = (current / st.needed) * 100
        GameTooltip:AddDoubleLine("Favor", format("%s / %s (%.1f%%)", BreakUpLargeNumbers(current), BreakUpLargeNumbers(st.needed), pct), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine("Remaining", BreakUpLargeNumbers(st.needed - current), 1, 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    holder:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Event registration is handled by ArmFavorEvents (via UpdateFavorBar):
    -- nothing is registered while the bar is hidden.
    ApplyDataBarLayout("FavorBar")
    UpdateFavorBar()
end

ns._CreateFavorBar = CreateFavorBar
end

-------------------------------------------------------------------------------
--  Register Data Bars with Unlock Mode
--  Uses the same pattern as action bars and blizzard movable frames:
--  savePosition / loadPosition / applyPosition / clearPosition callbacks.
-------------------------------------------------------------------------------
local function RegisterDataBarsWithUnlockMode()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    local elements = {}
    local orderBase = 300
    for idx, info in ipairs(EXTRA_BARS) do
        if info.isDataBar then
            local bk = info.key
            elements[#elements + 1] = MK({
                key   = bk,
                label = info.label,
                group = "Action Bars",
                order = orderBase + idx,
                getFrame = function() return dataBarFrames[bk] end,
                getSize = function()
                    -- Return stored DB values so cog menu shows what the
                    -- user typed, not the pixel-snapped frame size.
                    local s = EAB.db.profile.bars[bk]
                    if s then return s.width or 400, s.height or 18 end
                    return 400, 18
                end,
                setWidth = function(_, w)
                    local s = EAB.db.profile.bars[bk]
                    local PPab = EllesmereUI and EllesmereUI.PP
                    if s then s.width = PPab and PPab.Snap(w) or math.floor(w + 0.5) end
                    ApplyDataBarLayout(bk)
                end,
                setHeight = function(_, h)
                    local s = EAB.db.profile.bars[bk]
                    local PPab = EllesmereUI and EllesmereUI.PP
                    if s then s.height = PPab and PPab.Snap(h) or math.floor(h + 0.5) end
                    ApplyDataBarLayout(bk)
                end,
                savePos = function(_, point, relPoint, x, y)
                    if point and x and y then
                        EAB.db.profile.barPositions[bk] = {
                            point = point, relPoint = relPoint or point, x = x, y = y,
                        }
                    end
                    if not EllesmereUI._unlockActive then
                        local frame = dataBarFrames[bk]
                        if frame and point and x and y then
                            frame:ClearAllPoints()
                            frame:SetPoint(point, UIParent, relPoint or point, x, y)
                        end
                    end
                end,
                loadPos = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    if not pos then return nil end
                    local pt = pos.point
                    return { point = pt, relPoint = pos.relPoint or pt, x = pos.x, y = pos.y }
                end,
                clearPos = function()
                    EAB.db.profile.barPositions[bk] = nil
                end,
                applyPos = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    local frame = dataBarFrames[bk]
                    if not frame then return end
                    frame:ClearAllPoints()
                    if pos and pos.point then
                        local pt, rpt = pos.point, pos.relPoint or pos.point
                        local px, py = pos.x, pos.y
                        local PPa = EllesmereUI and EllesmereUI.PP
                        if PPa and px and py then
                            local es = frame:GetEffectiveScale()
                            local isCenterAnchor = (pt == "CENTER") and (rpt == "CENTER")
                            if isCenterAnchor and PPa.SnapCenterForDim then
                                px = PPa.SnapCenterForDim(px, frame:GetWidth() or 0, es)
                                py = PPa.SnapCenterForDim(py, frame:GetHeight() or 0, es)
                            elseif PPa.SnapForES then
                                px = PPa.SnapForES(px, es)
                                py = PPa.SnapForES(py, es)
                            end
                        end
                        frame:SetPoint(pt, UIParent, rpt, px or 0, py or 0)
                    else
                        if bk == "XPBar" then
                            frame:SetPoint("TOP", UIParent, "TOP", 0, -100)
                        elseif bk == "RepBar" then
                            frame:SetPoint("TOP", UIParent, "TOP", 0, -84)
                        elseif bk == "FavorBar" then
                            frame:SetPoint("TOP", UIParent, "TOP", 0, -68)
                        end
                    end
                end,
            })
        end
    end
    EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIActionBars")
end

function EAB_VTABLE.ExtraBars.CreateManagedDataBarFrames()
    CreateXPBar()
    CreateRepBar()
    if ns._CreateFavorBar then ns._CreateFavorBar() end
end

function EAB_VTABLE.ExtraBars.InitializeDataBarHoverState()
    for _, info in ipairs(EXTRA_BARS) do
        if info.isDataBar then
            AttachDataBarHoverHooks(info.key)
        end
    end
end

function EAB_VTABLE.ExtraBars.RestoreSavedDataBarPositions()
    local positions = EAB.db.profile.barPositions
    if not positions then return end

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

function EAB_VTABLE.ExtraBars.RegisterDataBarsWithUnlockModeWhenReady()
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        RegisterDataBarsWithUnlockMode()
        return
    end

    C_Timer_After(1, function()
        if EllesmereUI and EllesmereUI.RegisterUnlockElements then
            RegisterDataBarsWithUnlockMode()
        end
    end)
end

function EAB_VTABLE.ExtraBars.EnsureManagedDataBarRuntimeState()
    -- Apply the current combat/group/mouseover state now that every managed
    -- non-secure frame exists. ApplyAll runs earlier in startup before these
    -- holders/data bars are created.
    EAB_VTABLE.ExtraBars._managedNonSecureInCombat = InCombatLockdown()
    EAB_VTABLE.ExtraBars.RefreshManagedNonSecureVisibility()

    if EAB_VTABLE.ExtraBars._managedDataBarCombatFrame then return end

    -- Managed non-secure bars need a runtime combat refresh because secure
    -- state drivers are not available for these frames.
    EAB_VTABLE.ExtraBars._managedDataBarCombatFrame = CreateFrame("Frame")
    EAB_VTABLE.ExtraBars._managedDataBarCombatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    EAB_VTABLE.ExtraBars._managedDataBarCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    EAB_VTABLE.ExtraBars._managedDataBarCombatFrame:SetScript("OnEvent", function(_, event)
        -- Rely on the combat event direction here instead of sampling
        -- `InCombatLockdown()` during the transition. That keeps the managed
        -- non-secure bars in sync with the same edge that triggered the event.
        EAB_VTABLE.ExtraBars._managedNonSecureInCombat = (event == "PLAYER_REGEN_DISABLED")
        EAB_VTABLE.ExtraBars.RefreshManagedNonSecureVisibility()
    end)
end

local function SetupDataBars()
    -- Skip creating custom bars entirely if user wants Blizzard to control them
    if EAB.db.profile.useBlizzardDataBars then return end

    -- Phase 1: create the frames and their update callbacks.
    EAB_VTABLE.ExtraBars.CreateManagedDataBarFrames()

    -- Phase 2: attach hover handling now that the holders exist.
    EAB_VTABLE.ExtraBars.InitializeDataBarHoverState()

    -- Phase 3: restore saved positions onto the live holders.
    EAB_VTABLE.ExtraBars.RestoreSavedDataBarPositions()

    -- Phase 4: register the frames with Unlock Mode once the shared shell is ready.
    EAB_VTABLE.ExtraBars.RegisterDataBarsWithUnlockModeWhenReady()

    -- Phase 5: apply the current runtime visibility state and keep it in sync.
    EAB_VTABLE.ExtraBars.EnsureManagedDataBarRuntimeState()
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
                local uiW, uiH = UIParent:GetSize()
                local cx = (bL + bR) * 0.5 * bS / uS - uiW / 2
                local cy = (bT + bB) * 0.5 * bS / uS - uiH / 2
                EAB.db.profile.barPositions[barKey] = { point = "CENTER", relPoint = "CENTER", x = cx, y = cy }
                holder:ClearAllPoints()
                holder:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
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
        -- Hide the Edit Mode selection overlay so it doesn't appear in
        -- Blizzard's Edit Mode (we own this frame's position via unlock).
        local eacSel = ExtraAbilityContainer.Selection
        if eacSel then
            eacSel:SetAlpha(0)
            eacSel:EnableMouse(false)
            if not EllesmereUI._GetFFD(eacSel).showHooked then
                EllesmereUI._GetFFD(eacSel).showHooked = true
                hooksecurefunc(eacSel, "Show", function(self)
                    self:SetAlpha(0)
                    self:EnableMouse(false)
                end)
            end
        end

        -- Disable mouse on ExtraActionBarFrame so it cannot absorb clicks
        -- when no extra action bar is active.
        if ExtraActionBarFrame and not InCombatLockdown() and ExtraActionBarFrame:IsMouseEnabled() then
            ExtraActionBarFrame:EnableMouse(false)
        end

        -- Nil container OnShow/OnHide so Blizzard's layout code
        -- (UpdateManagedFramePositions) cannot fire when the container shows.
        ExtraAbilityContainer:SetScript("OnShow", nil)
        ExtraAbilityContainer:SetScript("OnHide", nil)

        -- Refresh ExtraActionButton1's keybind text and cooldown swipe. The
        -- broadcaster kill at load prevents Blizzard's UPDATE_BINDINGS and
        -- cooldown updates from reaching this button, so we drive both here.
        -- UpdateAction runs first; the keybind is set after it so Blizzard's own
        -- UpdateHotkeys (which hides the key when GetBindingKey is momentarily
        -- nil) can't clobber our text. Unlike the cooldown -- which recovers via
        -- the ACTIONBAR_UPDATE_COOLDOWN dispatcher -- the keybind has no such
        -- fallback, so every path that can reveal the button refreshes it.
        local function RefreshExtraActionButton()
            local eab1 = ExtraActionButton1
            if not eab1 then return end
            if eab1.UpdateAction then eab1:UpdateAction() end
            local hk = eab1.HotKey
            if hk then
                local key1 = GetBindingKey("EXTRAACTIONBUTTON1")
                if key1 then
                    hk:SetText(FormatHotkeyText(key1))
                    hk:Show()
                end
            end
            ForceCooldownPaint(eab1)
            -- Re-evaluate the broadcaster need now: this container Show/AddFrame
            -- refresh is a reliable delve-entry signal (the button's own OnShow
            -- doesn't fire then), and RefreshBroadcaster reads the button's
            -- actual visibility to decide.
            if ns.RefreshBroadcaster then
                ns.RefreshBroadcaster()
            end
        end

        -- Hook AddFrame so newly added ability buttons stay clickable, and
        -- refresh the extra action button. When the container is already shown
        -- (e.g. a zone ability is active) and the extra action button then
        -- becomes active, that fires AddFrame but not the container's Show hook,
        -- so this is the only refresh signal for that path. Deferred one frame so
        -- Blizzard has finished assigning the button's action before we read it.
        if ExtraAbilityContainer.AddFrame then
            hooksecurefunc(ExtraAbilityContainer, "AddFrame", function(_, frame)
                if frame and frame.EnableMouse and not InCombatLockdown() then
                    frame:EnableMouse(true)
                end
                C_Timer_After(0, RefreshExtraActionButton)
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
                -- Do NOT write to UIParentBottomManagedFrameContainer.showingFrames here.
                -- Writing into that Blizzard-owned table from this insecure hook taints the
                -- managed-frame-position system; a later in-combat layout pass (e.g. leaving
                -- a queued/follower instance while in combat) then blocks the protected
                -- ClearAllPoints on the managed containers (ADDON_ACTION_BLOCKED naming this
                -- addon). ExtraAbilityContainer already carries ignoreFramePositionManager and
                -- ignoreInLayout, so Blizzard excludes it from layout without us touching
                -- showingFrames.
            end)
        end

        -- Re-reparent after Blizzard's OnShow repositions the container.
        -- (We nil'd the script, but hooksecurefunc still fires on Show.)
        hooksecurefunc(ExtraAbilityContainer, "Show", function()
            if ExtraAbilityContainer:GetParent() ~= holder then
                RepositionExtraContainer()
            end
            RefreshExtraActionButton()
        end)

        -- Quick-reload catch-up: if the button is already showing, its Show (and
        -- AddFrame) fired before this deferred setup registered the hooks above,
        -- so we missed them. Refresh now so the keybind isn't left blank until
        -- the next show -- the cooldown recovers on its own via the dispatcher,
        -- the keybind has no such fallback.
        if ExtraActionButton1 and ExtraActionButton1:IsShown() then
            RefreshExtraActionButton()
        end
    end

    -- Encounter Bar: reparent into holder, mark as user-placed so Blizzard's
    -- position manager leaves it alone, and hook setup functions to re-reparent.
    -- SetPoint hooks intercept any Blizzard repositioning (EditMode, layout
    -- passes, encounter setup) and force the frame back to the holder.
    if barKey == "EncounterBar" then
        -- Hook SetPoint on encounter frames: if anything positions them away
        -- from our holder, force them back. The hook fires after the original
        -- SetPoint so the second call (ours) sees relativeTo == holder and
        -- exits cleanly with no recursion.
        local function HookEncounterSetPoint(frame)
            hooksecurefunc(frame, "SetPoint", function(self, _, relativeTo)
                if relativeTo ~= holder then
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", holder, "CENTER", 0, 0)
                end
            end)
        end

        local ppb = PlayerPowerBarAlt
        if ppb then
            ppb:SetMovable(true)
            ppb:SetUserPlaced(true)
            ppb:SetDontSavePosition(true)

            ppb:ClearAllPoints()
            ppb:SetParent(holder)
            ppb:SetPoint("CENTER", holder)

            HookEncounterSetPoint(ppb)

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
            -- Kill the container's Layout method so Blizzard's widget
            -- system can't reposition it when children are added/removed.
            if uwb.Layout then uwb.Layout = function() end end
            if uwb.MarkDirty then uwb.MarkDirty = function() end end
            HookEncounterSetPoint(uwb)
            uwb:HookScript("OnSizeChanged", function(self)
                local w, h = self:GetSize()
                if w > 1 and h > 1 then
                    local hw, hh = holder:GetSize()
                    holder:SetSize(max(hw, w), max(hh, h))
                end
            end)
        end

        -- Re-anchor on Show: Blizzard may reposition encounter frames
        -- while hidden (zone change, encounter setup), and our SetPoint
        -- hook only catches explicit SetPoint calls, not inherited
        -- position from a pre-show layout pass.
        for _, f in ipairs(extraFrames) do
            f:HookScript("OnShow", function(self)
                if self:GetParent() ~= holder then
                    ReparentIntoHolder()
                else
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", holder, "CENTER", 0, 0)
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
    if PlayerPowerBarAlt and PlayerPowerBarAlt:IsMovable() then
        PlayerPowerBarAlt:SetUserPlaced(false)
    end
end)

local function SetupBlizzardMovableFrames()
    for _, info in ipairs(EXTRA_BARS) do
        if info.isBlizzardMovable then
            -- EncounterBar: position fully owned by Blizzard Edit Mode.
            if info.key == "EncounterBar" then
                -- no-op: let Blizzard own position entirely
            else
                SetupBlizzardMovableFrame(info.key)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Extra Bar Holders (MicroBar, BagBar) positioning via holder frames
--  Reparents Blizzard frames into holder frames so unlock mode can position them.
-------------------------------------------------------------------------------
AttachExtraBarHoverHooks = function(info)
    -- Position-only Blizzard-owned bars (the QueueStatus eye) never get mouseover
    -- fade hooks -- EUI controls only their position now, not visibility. Without
    -- this, a stale "mouseover" setting would fade the eye to alpha 0 on leave.
    if info.noManagedVisibility then return end
    -- Idempotent: only attach once per bar key
    if hoverStates[info.key] then return end

    local blizzFrame = _G[info.frameName]
    if not blizzFrame then return end
    local holder = extraBarHolders[info.key]
    local hoverFrame = info.hoverFrame and _G[info.hoverFrame]

    -- Fade the Blizzard frame directly rather than the holder.
    -- The holder is for positioning only; fading it can be overridden by
    -- Blizzard's own layout code calling SetAlpha on the child frame.
    local fadeTarget = blizzFrame
    local hoverRoot = hoverFrame or blizzFrame

    local state = EAB_VTABLE.Hover.GetState(info.key, fadeTarget)

    local function IsChildOfHoverRoot(frame)
        while frame do
            if frame == hoverRoot then
                return true
            end
            frame = frame.GetParent and frame:GetParent() or nil
        end
        return false
    end

    local function IsHoverRootActive()
        local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
        if foci then
            for _, focus in ipairs(foci) do
                if focus and IsChildOfHoverRoot(focus) then
                    return true
                end
            end
        end

        return hoverRoot:IsMouseOver()
    end

    local OnEnter, OnLeave = EAB_VTABLE.Hover.BuildHandlers(info.key, state, {
        canEnter = function()
            return IsHoverRootActive()
        end,
        isStillHovered = function()
            return IsHoverRootActive()
        end,
        markHoveredWhileActive = true,
    })

    hoverRoot:HookScript("OnEnter", OnEnter)
    hoverRoot:HookScript("OnLeave", OnLeave)

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
    HookChildren(hoverRoot)
end

function EAB_VTABLE.ExtraBars.AttachFrameToHolder(barKey, blizzFrame, holder, opts)
    opts = opts or {}

    local recentering = false

    local function SyncHolderSize()
        local fw, fh = blizzFrame:GetWidth(), blizzFrame:GetHeight()
        if fw and fw > 1 and fh and fh > 1 then
            holder:SetSize(fw, fh)
        end
    end

    local function ReparentIntoHolder()
        if InCombatLockdown() then
            _blizzMovablePendingOOC[barKey] = true
            return
        end

        recentering = true
        blizzFrame:SetParent(holder)
        blizzFrame:ClearAllPoints()
        blizzFrame:SetPoint("CENTER", holder, "CENTER", 0, 0)
        recentering = false
        SyncHolderSize()
    end

    blizzFrame:HookScript("OnSizeChanged", SyncHolderSize)

    if opts.disableLayoutFrame then
        blizzFrame.ignoreInLayout = true
        if blizzFrame.SetIsLayoutFrame then
            blizzFrame:SetIsLayoutFrame(false)
        end
        blizzFrame.IsLayoutFrame = nil
    end

    ReparentIntoHolder()

    hooksecurefunc(blizzFrame, "SetParent", function(self, newParent)
        if newParent ~= holder then
            C_Timer_After(0, function()
                if self:GetParent() ~= holder then
                    ReparentIntoHolder()
                end
            end)
        end
    end)

    if opts.repairOnShow then
        blizzFrame:HookScript("OnShow", function()
            C_Timer_After(0, function()
                if recentering or InCombatLockdown() then return end
                ReparentIntoHolder()
            end)
        end)
    end

    hooksecurefunc(blizzFrame, "SetPoint", function(self)
        if recentering or self:GetParent() ~= holder then return end
        C_Timer_After(0, function()
            if recentering or self:GetParent() ~= holder or InCombatLockdown() then return end
            if opts.recenterOnlyWhenMoved and self:GetPoint(1) == "CENTER" then return end
            ReparentIntoHolder()
        end)
    end)

    if opts.hookUpdatePosition and type(blizzFrame.UpdatePosition) == "function" then
        hooksecurefunc(blizzFrame, "UpdatePosition", function()
            if recentering or blizzFrame:GetParent() ~= holder then return end
            C_Timer_After(0, function()
                if recentering or blizzFrame:GetParent() ~= holder or InCombatLockdown() then return end
                ReparentIntoHolder()
            end)
        end)
    end

    return SyncHolderSize, ReparentIntoHolder
end

local function SetupExtraBarHolder(barKey, frameName, barInfo)
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

    -- MicroBar/BagBar: position fully owned by Blizzard Edit Mode.
    -- Don't save or restore positions -- passive-follow handles it.
    -- Early return skips all position capture/restore code below.
    if barKey == "MicroBar" or barKey == "BagBar" then
        EAB.db.profile.barPositions[barKey] = nil
        local function SyncFollow()
            local fw, fh = blizzFrame:GetWidth(), blizzFrame:GetHeight()
            if fw and fw > 1 and fh and fh > 1 then
                holder:SetSize(fw, fh)
            end
            holder:ClearAllPoints()
            holder:SetPoint("CENTER", blizzFrame, "CENTER", 0, 0)
        end
        SyncFollow()
        blizzFrame:HookScript("OnSizeChanged", function() SyncFollow() end)
        if blizzFrame.ApplySystemAnchor then
            hooksecurefunc(blizzFrame, "ApplySystemAnchor", function()
                C_Timer_After(0, SyncFollow)
            end)
        end
        return holder
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
            local uiW, uiH = UIParent:GetSize()
            local cx = (bL + bR) * 0.5 * bS / uiS - uiW / 2
            local cy = (bT + bB) * 0.5 * bS / uiS - uiH / 2
            EAB.db.profile.barPositions[barKey] = {
                point = "CENTER", relPoint = "CENTER", x = cx, y = cy,
            }
            holder:ClearAllPoints()
            holder:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
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
                    local uiW, uiH = UIParent:GetSize()
                    local ccx = (cL + cR) * 0.5 * cS / uS - uiW / 2
                    local ccy = (cT + cB) * 0.5 * cS / uS - uiH / 2
                    EAB.db.profile.barPositions[barKey] = {
                        point = "CENTER", relPoint = "CENTER", x = ccx, y = ccy,
                    }
                    holder:ClearAllPoints()
                    holder:SetPoint("CENTER", UIParent, "CENTER", ccx, ccy)
                    self:SetScript("OnUpdate", nil)
                elseif attempts > 300 then
                    self:SetScript("OnUpdate", nil)
                end
            end)
        end
    end

    -- QueueStatusButton: reparent to UIParent so micro menu visibility
    -- (mouseover/combat hide) doesn't affect the eye. Remove from layout
    -- so micro menu doesn't shift. Hook UpdatePosition to prevent snap-back.
    if barKey == "QueueStatus" then
        SafeEnableMouse(holder, false)

        -- Remove from MicroMenuContainer layout flow (no micro menu shift)
        blizzFrame.ignoreInLayout = true
        if blizzFrame.SetIsLayoutFrame then
            blizzFrame:SetIsLayoutFrame(false)
        end
        blizzFrame.IsLayoutFrame = nil

        -- Reparent to UIParent (independent of micro menu visibility)
        local function EnsureQueueParent()
            if blizzFrame:GetParent() ~= UIParent and not InCombatLockdown() then
                blizzFrame:SetParent(UIParent)
                if MicroMenuContainer and MicroMenuContainer.Layout then
                    C_Timer_After(0, function()
                        if MicroMenuContainer and MicroMenuContainer.Layout then
                            MicroMenuContainer:Layout()
                        end
                    end)
                end
            end
        end
        EnsureQueueParent()

        local function SyncQueueHolderSize()
            local fw, fh = blizzFrame:GetWidth(), blizzFrame:GetHeight()
            if fw and fw > 1 and fh and fh > 1 then
                holder:SetSize(fw, fh)
            end
        end

        local function RepositionQueue()
            blizzFrame:ClearAllPoints()
            blizzFrame:SetPoint("CENTER", holder, "CENTER", 0, 0)
        end

        RepositionQueue()
        SyncQueueHolderSize()
        blizzFrame:HookScript("OnSizeChanged", SyncQueueHolderSize)

        -- Prevent Blizzard from snapping the eye back or reparenting away
        local _upGuard = false
        if type(blizzFrame.UpdatePosition) == "function" then
            hooksecurefunc(blizzFrame, "UpdatePosition", function()
                if _upGuard then return end
                _upGuard = true
                RepositionQueue()
                EnsureQueueParent()
                _upGuard = false
            end)
        end

        -- Recover from external Hide() calls (other addons, stale state).
        -- When Blizzard updates the queue display, re-check parent and
        -- force Show() if the player is actually in a queue.
        if type(blizzFrame.UpdateDisplay) == "function" then
            hooksecurefunc(blizzFrame, "UpdateDisplay", function()
                EnsureQueueParent()
            end)
        end

        -- Safety net: on LFG_UPDATE, re-parent and let Blizzard show the eye
        local queueWatcher = CreateFrame("Frame")
        queueWatcher:RegisterEvent("LFG_UPDATE")
        queueWatcher:RegisterEvent("LFG_QUEUE_STATUS_UPDATE")
        queueWatcher:RegisterEvent("LFG_ROLE_CHECK_UPDATE")
        queueWatcher:RegisterEvent("LFG_PROPOSAL_UPDATE")
        queueWatcher:SetScript("OnEvent", function()
            EnsureQueueParent()
            RepositionQueue()
        end)

        return holder
    end
    -- All current extra bars (MicroBar, BagBar, QueueStatus) return above;
    -- nothing reaches here.
end

local function SetupExtraBarHolders()
    for _, info in ipairs(EXTRA_BARS) do
        if not info.isDataBar and not info.isBlizzardMovable and info.frameName then
            SetupExtraBarHolder(info.key, info.frameName, info)
        end
    end
end

local function RegisterExtraBarsWithUnlockMode()
    if not EllesmereUI or not EllesmereUI.RegisterUnlockElements then return end
    local MK = EllesmereUI.MakeUnlockElement
    local elements = {}
    local orderBase = 350
    for idx, info in ipairs(EXTRA_BARS) do
        if not info.isDataBar and not info.isBlizzardMovable and info.frameName then
            local bk = info.key
            -- MicroBar, BagBar: position fully owned by Blizzard Edit Mode.
            -- Skip unlock registration entirely.
            if bk == "MicroBar" or bk == "BagBar" then
                -- no-op: visibility-only holder, no unlock mover
            else
            local isBlizzOwned = (bk == "QueueStatus")
            elements[#elements + 1] = MK({
                key   = bk,
                label = info.label,
                group = "Action Bars",
                order = orderBase + idx,
                noResize = true,
                noAnchorTo = isBlizzOwned,
                noAnchorTarget = isBlizzOwned,
                isHidden = function()
                    local s = EAB.db.profile.bars[bk]
                    return s and s.alwaysHidden
                end,
                getFrame = function() return extraBarHolders[bk] end,
                getSize = function()
                    local holder = extraBarHolders[bk]
                    if holder then return holder:GetWidth(), holder:GetHeight() end
                    return 200, 40
                end,
                savePos = function(_, point, relPoint, x, y)
                    if point and x and y then
                        EAB.db.profile.barPositions[bk] = {
                            point = point, relPoint = relPoint or point, x = x, y = y,
                        }
                    end
                    if not EllesmereUI._unlockActive then
                        local holder = extraBarHolders[bk]
                        if holder and point and x and y then
                            holder:ClearAllPoints()
                            holder:SetPoint(point, UIParent, relPoint or point, x, y)
                        end
                    end
                end,
                loadPos = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    if not pos then return nil end
                    return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
                end,
                clearPos = function()
                    EAB.db.profile.barPositions[bk] = nil
                end,
                applyPos = function()
                    local pos = EAB.db.profile.barPositions[bk]
                    local holder = extraBarHolders[bk]
                    if not holder then return end
                    -- MicroBar/BagBar: Blizzard owns position, never move
                    if bk == "MicroBar" or bk == "BagBar" then return end
                    holder:ClearAllPoints()
                    if pos and pos.point then
                        holder:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
                    else
                        holder:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
                    end
                end,
            })
            end -- else (not MicroBar/BagBar)
        end
    end
    EllesmereUI:RegisterUnlockElements(elements, "EllesmereUIActionBars")
end


-------------------------------------------------------------------------------
--  Extra Bars (MicroBar, BagBar) visibility-only management
--  These use Blizzard's existing frames, we just manage visibility.
-------------------------------------------------------------------------------
local function SetupExtraBars()
    if not EAB.db then return end

    -- Setup Blizzard movable frames (Extra Action Button, Encounter Bar)
    SetupBlizzardMovableFrames()

    -- Setup extra bar holders (MicroBar, BagBar) for visibility/mouseover
    SetupExtraBarHolders()

    for _, info in ipairs(EXTRA_BARS) do
        if not info.isDataBar and not info.isBlizzardMovable then
            local blizzFrame = _G[info.frameName]
            if blizzFrame then
                local s = EAB.db.profile.bars[info.key]
                if s then
                    local holder = extraBarHolders[info.key]
                    if s.alwaysHidden and not info.blizzOwnedVisibility then
                        blizzFrame:Hide()
                        if holder then holder:Hide() end
                    end
                    AttachExtraBarHoverHooks(info)
                end
            end
        end  -- not isDataBar/isBlizzardMovable
    end

    _quickKeybindState.art.ForEachSpecialButton(_quickKeybindState.art.InitializeButton)

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


-------------------------------------------------------------------------------
--  QuickKeybind compatibility
--  Modern QuickKeybind works off visible buttons' `commandName` plus
--  `DoModeChange(...)`. Blizzard's stock helpers only know about their own
--  named bar buttons, so only EAB-owned buttons and the custom paging arrows need
--  an explicit mode toggle here.
-------------------------------------------------------------------------------
local function EAB_SetQuickKeybindEffects(btn, show)
    if not btn or btn:IsForbidden() then return end
    if btn.DoModeChange then
        btn:DoModeChange(show)
    elseif btn.QuickKeybindHighlightTexture then
        btn.QuickKeybindHighlightTexture:SetShown(show)
    end
    -- Suppress/restore the secure action so spells don't fire during QKB.
    -- Only action buttons (those with an action attr) need this.
    if not InCombatLockdown() and btn.commandName and btn:GetAttribute("action") then
        if show then
            btn:SetAttribute("type", nil)
        else
            btn:SetAttribute("type", "action")
        end
    end
    _quickKeybindState.art.ApplyButtonHighlightAlpha(btn, show)
    if btn.UpdateMouseWheelHandler then
        btn:UpdateMouseWheelHandler()
    end
end

EAB_UpdateQuickKeybindButtons = function(show)
    for _, info in ipairs(BAR_CONFIG) do
        local buttons = barButtons[info.key]
        if buttons then
            for _, btn in ipairs(buttons) do
                if btn and btn.commandName then
                    EAB_SetQuickKeybindEffects(btn, show)
                end
            end
        end
    end
    if _pagingFrame then
        if _pagingFrame._upBtn then
            EAB_SetQuickKeybindEffects(_pagingFrame._upBtn, show)
        end
        if _pagingFrame._downBtn then
            EAB_SetQuickKeybindEffects(_pagingFrame._downBtn, show)
        end
    end
end

_quickKeybindState.macroButtons = setmetatable({}, { __mode = "k" })

-- Macro quick-keybind uses our OWN capture overlay instead of Blizzard's
-- QuickKeybindButtonTemplateMixin. Driving Blizzard's secure input path from
-- addon code (the old QuickKeybindFrame:OnKeyDown call) tainted it, so any key
-- Blizzard passes through during capture -- e.g. F11 = SCREENSHOT, which it RUNs
-- via the protected RunBinding -- threw ADDON_ACTION_FORBIDDEN. Capturing on a
-- plain frame we own consumes the key before Blizzard's input handler sees it,
-- so every key (including system/function keys) binds cleanly with no taint.

_quickKeybindState.GetMacroBindingContext = function(command)
    return C_KeyBindings and C_KeyBindings.GetBindingContextForAction
        and C_KeyBindings.GetBindingContextForAction(command)
end

_quickKeybindState.SetOutput = function(text)
    if QuickKeybindFrame and QuickKeybindFrame.SetOutputText then
        QuickKeybindFrame:SetOutputText(text)
    end
end

_quickKeybindState.NormalizeMacroBindInput = function(input)
    input = GetConvertedKeyOrButton and GetConvertedKeyOrButton(input) or input
    if IsKeyPressIgnoredForBinding and IsKeyPressIgnoredForBinding(input) then return end
    return input
end

_quickKeybindState.SetMacroButtonTooltip = function(button)
    if not button or not button.commandName or not QuickKeybindTooltip then return end
    QuickKeybindTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip_AddHighlightLine(QuickKeybindTooltip, GetBindingName(button.commandName))

    local key1 = GetBindingKeyForAction(button.commandName)
    if key1 then
        GameTooltip_AddInstructionLine(QuickKeybindTooltip, key1)
        GameTooltip_AddNormalLine(QuickKeybindTooltip, ESCAPE_TO_UNBIND)
    else
        GameTooltip_AddErrorLine(QuickKeybindTooltip, NOT_BOUND)
        GameTooltip_AddNormalLine(QuickKeybindTooltip, PRESS_KEY_TO_BIND)
    end

    QuickKeybindTooltip:Show()
end

_quickKeybindState.BindMacroInput = function(input)
    -- Rebinding during combat is unsafe and the rest of QKB is combat-gated, so
    -- match that here even though our capture frame is insecure.
    if InCombatLockdown() then return end
    local button = _quickKeybindState.hoveredMacroButton
    if not button then return end

    _quickKeybindState.UpdateMacroButtonCommand(button)
    local command = button.commandName
    if not command then return end

    local context = _quickKeybindState.GetMacroBindingContext(command)
    local old1, old2 = GetBindingKey(command, nil, context)

    if input == "ESCAPE" then
        -- Full unbind: clear EVERY key bound to this macro, matching the rebind
        -- path below (which clears both old keys before setting the new one).
        if old1 then SetBinding(old1, nil, context) end
        if old2 then SetBinding(old2, nil, context) end
        _quickKeybindState.SetOutput(KEY_UNBOUND)
        _quickKeybindState.SetMacroButtonTooltip(button)
        return
    end

    local key = _quickKeybindState.NormalizeMacroBindInput(input)
    if not key then return end

    local newKey = CreateKeyChordStringUsingMetaKeyState and CreateKeyChordStringUsingMetaKeyState(key) or key
    if old1 then SetBinding(old1, nil, context) end
    if old2 then SetBinding(old2, nil, context) end
    SetBinding(newKey, nil, context)

    if SetBinding(newKey, command, context) then
        _quickKeybindState.SetOutput(KEY_BOUND)
    else
        if old1 then SetBinding(old1, command, context) end
        if old2 then SetBinding(old2, command, context) end
    end

    _quickKeybindState.SetMacroButtonTooltip(button)
end

_quickKeybindState.GetMacroBindFrame = function()
    if _quickKeybindState.macroBindFrame then return _quickKeybindState.macroBindFrame end

    -- A plain (insecure) frame we fully own -- never a secure template. Capturing
    -- input on it consumes the keypress, so it never reaches Blizzard's secure
    -- input path (no SetPropagateKeyboardInput, default = consume).
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(1000)
    frame:EnableMouse(true)
    frame:EnableKeyboard(true)
    frame:EnableMouseWheel(true)
    frame:Hide()

    frame:SetScript("OnLeave", function(self)
        local button = self.button
        self.button = nil
        _quickKeybindState.hoveredMacroButton = nil
        self:Hide()
        if QuickKeybindTooltip then QuickKeybindTooltip:Hide() end
        if button then _quickKeybindState.RefreshMacroButton(button) end
    end)
    frame:SetScript("OnKeyDown", function(_, key)
        _quickKeybindState.BindMacroInput(key)
    end)
    frame:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton ~= "LeftButton" and mouseButton ~= "RightButton" then
            _quickKeybindState.BindMacroInput(mouseButton)
        end
    end)
    frame:SetScript("OnMouseWheel", function(_, delta)
        _quickKeybindState.BindMacroInput(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN")
    end)

    _quickKeybindState.macroBindFrame = frame
    return frame
end

_quickKeybindState.HideMacroBindFrame = function()
    local frame = _quickKeybindState.macroBindFrame
    if not frame then return end

    local button = frame.button
    frame.button = nil
    _quickKeybindState.hoveredMacroButton = nil
    frame:Hide()
    if QuickKeybindTooltip then QuickKeybindTooltip:Hide() end
    if button then _quickKeybindState.RefreshMacroButton(button, false) end
end

_quickKeybindState.UpdateMacroButtonCommand = function(button)
    if not button or not MacroFrame or not MacroFrame.GetMacroDataIndex or not GetMacroInfo then return end

    local index
    if (button == MacroFrameSelectedMacroButton or button == MacroFrame.SelectedMacroButton)
        and MacroFrame.GetSelectedIndex then
        local selected = MacroFrame:GetSelectedIndex()
        if selected then index = MacroFrame:GetMacroDataIndex(selected) end
    elseif button.GetElementData then
        local data = button:GetElementData()
        if data then index = MacroFrame:GetMacroDataIndex(data) end
    end

    local name = index and GetMacroInfo(index)
    button.commandName = name and ("MACRO " .. name) or nil
end

_quickKeybindState.RefreshMacroButton = function(button, show)
    if not button then return end
    _quickKeybindState.UpdateMacroButtonCommand(button)
    if show == nil then
        show = _quickKeybindState.open
    end
    EAB_SetQuickKeybindEffects(button, show and button:IsShown())
end

-- On hover (in QKB mode) park the capture overlay over the macro button and arm
-- its tooltip, so the next key/mouse/wheel press binds to THIS macro.
_quickKeybindState.SelectMacroButton = function(button)
    if not _quickKeybindState.open then return end
    _quickKeybindState.UpdateMacroButtonCommand(button)
    if not button.commandName then return end

    _quickKeybindState.hoveredMacroButton = button

    local frame = _quickKeybindState.GetMacroBindFrame()
    frame.button = button
    frame:ClearAllPoints()
    frame:SetAllPoints(button)
    frame:Show()

    _quickKeybindState.RefreshMacroButton(button, true)
    if button.QuickKeybindHighlightTexture then
        button.QuickKeybindHighlightTexture:SetAlpha(1)
    end
    _quickKeybindState.SetMacroButtonTooltip(button)
end

_quickKeybindState.InitMacroButton = function(button)
    if not button or EFD(button).qkbMacroHooked or not QuickKeybindButtonTemplateMixin then return end

    -- No Mixin / QuickKeybindButton* method calls: those invoke Blizzard's secure
    -- input path from addon code and taint it. Our own capture overlay (above)
    -- handles all key/mouse/wheel input; these hooks only manage hover + visuals.
    -- Do NOT EnableMouseWheel on the Blizzard button -- with no wheel handler it
    -- would swallow scroll and break the macro list; the overlay owns the wheel.
    if not button.QuickKeybindHighlightTexture then
        local tex = button:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints(button)
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0.5)
        tex:Hide()
        button.QuickKeybindHighlightTexture = tex
    end

    button:HookScript("OnShow", function(self)
        _quickKeybindState.RefreshMacroButton(self)
    end)
    button:HookScript("OnHide", function(self)
        _quickKeybindState.RefreshMacroButton(self, false)
    end)
    button:HookScript("OnClick", function(self)
        _quickKeybindState.UpdateMacroButtonCommand(self)
        if _quickKeybindState.open then
            _quickKeybindState.SetMacroButtonTooltip(self)
        end
    end)
    button:HookScript("OnEnter", function(self)
        _quickKeybindState.SelectMacroButton(self)
    end)
    button:HookScript("OnLeave", function(self)
        -- The overlay sits over the button, so the button's OnLeave fires the
        -- instant we park it. Ignore that case; the overlay's own OnLeave tears
        -- down when the cursor truly leaves.
        local frame = _quickKeybindState.macroBindFrame
        if frame and frame:IsShown() and frame.button == self then return end
        if _quickKeybindState.hoveredMacroButton == self then
            _quickKeybindState.hoveredMacroButton = nil
        end
        if QuickKeybindTooltip then QuickKeybindTooltip:Hide() end
        _quickKeybindState.RefreshMacroButton(self)
    end)

    local fd = EFD(button)
    fd.qkbMacroHooked = true
    _quickKeybindState.macroButtons[button] = true
    _quickKeybindState.RefreshMacroButton(button)
end

_quickKeybindState.UpdateMacroButtons = function(show)
    if show == false then
        _quickKeybindState.HideMacroBindFrame()
    end
    for button in pairs(_quickKeybindState.macroButtons) do
        _quickKeybindState.RefreshMacroButton(button, show)
    end
end

_quickKeybindState.InitMacroFrame = function()
    if _quickKeybindState.macroFrameHooked or not MacroFrame or not QuickKeybindButtonTemplateMixin then return end

    _quickKeybindState.InitMacroButton(MacroFrameSelectedMacroButton or MacroFrame.SelectedMacroButton)

    local scrollBox = MacroFrame.MacroSelector and MacroFrame.MacroSelector.ScrollBox
    if not scrollBox or not scrollBox.ForEachFrame then return end

    _quickKeybindState.macroScrollUpdate = function(frame)
        if not frame or not frame.GetView or not frame:GetView() then return end
        frame:ForEachFrame(_quickKeybindState.InitMacroButton)
        _quickKeybindState.UpdateMacroButtons(_quickKeybindState.open)
    end
    C_Timer_After(0, function()
        _quickKeybindState.macroScrollUpdate(scrollBox)
    end)
    hooksecurefunc(scrollBox, "Update", _quickKeybindState.macroScrollUpdate)

    _quickKeybindState.macroFrameHooked = true
    _quickKeybindState.UpdateMacroButtons(_quickKeybindState.open)
end

local function EAB_UpdateQuickKeybindVisibility(show)
    if InCombatLockdown() then return end

    for _, info in ipairs(BAR_CONFIG) do
        local key = info.key
        local s = EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars[key]
        local frame = barFrames[key]

        if show and frame and ShouldQuickKeybindSurfaceBar(s) then
            RegisterAttributeDriver(frame, "state-visibility", "show")
            -- Keep the visibility cache in sync with the driver we just set.
            -- Otherwise RefreshRuntimeVisibility on QKB exit sees the stale
            -- pre-QKB string still equal to the recomputed real string and skips
            -- re-registering, leaving conditionally-hidden bars (notably the Pet
            -- Bar on non-pet classes) stuck on "show" until reload.
            frame._eabLastVisStr = "show"
            frame:Show()
            SafeEnableMouseMotionOnly(frame, true)
        end

        local buttons = barButtons[key]
        if buttons then
            for _, btn in ipairs(buttons) do
                if btn then
                    _quickKeybindState.art.ApplyButtonHighlightAlpha(btn, show)
                end
            end
        end

        if not info.isStance and not info.isPetBar then
            if buttons then
                for _, btn in ipairs(buttons) do
                    if btn then
                        SetShowGridInsecure(btn, show, SHOWGRID.KEYBOUND)
                    end
                end
            end
        end
    end

    _quickKeybindState.art.ForEachSpecialButton(function(btn)
        _quickKeybindState.art.ApplyButtonHighlightAlpha(btn, show)
    end)

    if show then
        for _, info in ipairs(BAR_CONFIG) do
            local key = info.key
            local s = EAB.db and EAB.db.profile and EAB.db.profile.bars and EAB.db.profile.bars[key]
            local frame = barFrames[key]
            local state = hoverStates[key]
            if frame and ShouldQuickKeybindSurfaceBar(s) and s.mouseoverEnabled then
                StopFade(frame)
                frame:SetAlpha(1)
                if state then state.fadeDir = "in" end
                if key == "MainBar" then SyncPagingAlpha(1) end
            end
            EAB:ApplyAlwaysShowButtons(key)
            EAB:ApplyClickThroughForBar(key)
        end
    else
        EAB:ApplyCombatVisibility()
        EAB:RefreshRuntimeVisibility()
        for _, info in ipairs(BAR_CONFIG) do
            EAB:ApplyAlwaysShowButtons(info.key)
            EAB:ApplyClickThroughForBar(info.key)
        end
        EAB:RefreshMouseover()
    end

    if _pagingFrame then
        LayoutPagingFrame()
    end
end

local _qkbHookFrame

_quickKeybindState.FinishClose = function()
    _quickKeybindState.closePending = false
    -- Restore action type on buttons that were suppressed during QKB mode.
    -- This handles the deferred-close-during-combat case where SetAttribute
    -- was blocked earlier.
    EAB_UpdateQuickKeybindButtons(false)
    EAB_UpdateQuickKeybindVisibility(false)
    -- Restore bar strata if HideDim couldn't (combat-deferred close)
    if _quickKeybindState.strataCache and not InCombatLockdown() then
        for frame, orig in pairs(_quickKeybindState.strataCache) do
            frame:SetFrameStrata(orig)
        end
        _quickKeybindState.strataCache = nil
    end
end

-- One-time initialization: hook QKB scripts on all action buttons so mouse
-- binding works. ActionBarButtonTemplate provides the mixin methods but
-- Blizzard only wires the OnClick/OnEnter/OnLeave scripts on buttons it
-- knows by name (ActionButton1-12, MultiBar*, etc.). Our custom EABButtons
-- need explicit hookup for mouse-button binding to communicate with QKB.
_quickKeybindState.InitButtons = function()
    if _quickKeybindState.buttonsInit then return end
    if not QuickKeybindButtonTemplateMixin then return end
    _quickKeybindState.buttonsInit = true
    local PP = EllesmereUI and EllesmereUI.PP
    local EG = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    for _, info in ipairs(BAR_CONFIG) do
        if not info.isStance and not info.isPetBar then
            local buttons = barButtons[info.key]
            if buttons then
                for _, btn in ipairs(buttons) do
                    if btn and btn.commandName then
                        if not btn.QuickKeybindButtonOnClick then
                            Mixin(btn, QuickKeybindButtonTemplateMixin)
                        end
                        local fd = EFD(btn)
                        if not fd.qkbClickHooked and btn.QuickKeybindButtonOnClick then
                            btn:HookScript("OnClick", btn.QuickKeybindButtonOnClick)
                            btn:HookScript("OnEnter", btn.QuickKeybindButtonOnEnter)
                            btn:HookScript("OnLeave", btn.QuickKeybindButtonOnLeave)
                            -- Accent border + highlight color on hover during QKB
                            btn:HookScript("OnEnter", function(self)
                                if not _quickKeybindState.open then return end
                                if not EG then return end
                                local fd = EFD(self)
                                if fd.borders and PP then
                                    PP.UpdateBorder(self, nil, EG.r, EG.g, EG.b, 0.9)
                                    fd.borderKey = nil
                                end
                                local hl = self.HighlightTexture
                                if hl then hl:SetVertexColor(EG.r, EG.g, EG.b, 1) end
                                fd.qkbHoverActive = true
                            end)
                            btn:HookScript("OnLeave", function(self)
                                local fd = EFD(self)
                                if not fd.qkbHoverActive then return end
                                fd.qkbHoverActive = nil
                                fd.borderKey = nil
                                local bk = fd.barKey
                                if bk and PP then
                                    EAB:ApplyBordersForBar(bk)
                                end
                                local hl = self.HighlightTexture
                                if hl then
                                    local p = EAB and EAB.db and EAB.db.profile
                                    local useCC = p and p.highlightUseClassColor
                                    local cc = (p and p.highlightCustomColor) or { r = 0.973, g = 0.839, b = 0.604, a = 1 }
                                    local hr, hg, hb = cc.r, cc.g, cc.b
                                    if useCC then
                                        local _, ct = UnitClass("player")
                                        local c2 = ct and RAID_CLASS_COLORS[ct]
                                        if c2 then hr, hg, hb = c2.r, c2.g, c2.b end
                                    end
                                    hl:SetVertexColor(hr, hg, hb, 1)
                                end
                                local bk = EFD(self).barKey
                                local s = bk and EAB.db and EAB.db.profile
                                    and EAB.db.profile.bars and EAB.db.profile.bars[bk]
                                if s and PP then
                                    local c = s.borderColor or { r = 0, g = 0, b = 0, a = 1 }
                                    local cr, cg, cb, ca = c.r, c.g, c.b, c.a or 1
                                    if s.borderClassColor then
                                        local _, ct = UnitClass("player")
                                        local cc = ct and RAID_CLASS_COLORS[ct]
                                        if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                                    end
                                    local sz = ResolveBorderThickness(s)
                                    if sz > 0 then
                                        PP.UpdateBorder(self, sz, cr, cg, cb, ca)
                                    else
                                        PP.HideBorder(self)
                                    end
                                end
                            end)
                            fd.qkbClickHooked = true
                        end
                    end
                end
            end
        end
    end
end

-- Dim overlay: darkens the rest of the UI while Quick Keybind mode is active.
-- Action bars are raised above it so they remain visually prominent.
_quickKeybindState.GetDimOverlay = function()
    if _quickKeybindState.dimFrame then return _quickKeybindState.dimFrame end
    local dim = CreateFrame("Frame", nil, UIParent)
    dim:SetFrameStrata("HIGH")
    dim:SetFrameLevel(0)
    dim:SetAllPoints(UIParent)
    dim:EnableMouse(false)
    dim:SetMouseClickEnabled(false)
    dim:SetMouseMotionEnabled(false)
    local tex = dim:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(0, 0, 0, 0.40)
    dim:SetAlpha(0)
    dim:Hide()
    _quickKeybindState.dimFrame = dim
    return dim
end

_quickKeybindState.ShowDim = function()
    local dim = _quickKeybindState.GetDimOverlay()
    dim:Show()
    UIFrameFadeIn(dim, 0.2, dim:GetAlpha(), 1)
    -- Raise action bar frames above the dim
    for _, info in ipairs(BAR_CONFIG) do
        local frame = barFrames[info.key]
        if frame and not InCombatLockdown() then
            if not _quickKeybindState.strataCache then
                _quickKeybindState.strataCache = {}
            end
            if not _quickKeybindState.strataCache[frame] then
                _quickKeybindState.strataCache[frame] = frame:GetFrameStrata()
            end
            frame:SetFrameStrata("DIALOG")
        end
    end
    if _pagingFrame and not InCombatLockdown() then
        if not _quickKeybindState.strataCache then _quickKeybindState.strataCache = {} end
        if not _quickKeybindState.strataCache[_pagingFrame] then
            _quickKeybindState.strataCache[_pagingFrame] = _pagingFrame:GetFrameStrata()
        end
        _pagingFrame:SetFrameStrata("DIALOG")
    end
end

_quickKeybindState.HideDim = function()
    local dim = _quickKeybindState.dimFrame
    if not dim then return end
    UIFrameFadeOut(dim, 0.2, dim:GetAlpha(), 0)
    C_Timer_After(0.2, function()
        if dim:GetAlpha() < 0.01 then dim:Hide() end
    end)
    -- Restore bar strata
    if _quickKeybindState.strataCache and not InCombatLockdown() then
        for frame, orig in pairs(_quickKeybindState.strataCache) do
            frame:SetFrameStrata(orig)
        end
        _quickKeybindState.strataCache = nil
    end
end

_quickKeybindState.Open = function()
    if _quickKeybindState.open then return end
    if InCombatLockdown() then return end
    _quickKeybindState.closePending = false
    _quickKeybindState.open = true
    _quickKeybindState.InitButtons()
    _quickKeybindState.InitMacroFrame()
    EAB_UpdateQuickKeybindButtons(true)
    _quickKeybindState.UpdateMacroButtons(true)
    EAB_UpdateQuickKeybindVisibility(true)
    _quickKeybindState.ShowDim()
end

local function EAB_QuickKeybindClose()
    if not _quickKeybindState.open and not _quickKeybindState.closePending then return end
    _quickKeybindState.HideDim()
    if InCombatLockdown() then
        -- Drop the visual bind overlays immediately so Bar 1 does not look
        -- stuck in QuickKeybind mode, then defer the protected visibility
        -- cleanup until combat ends.
        _quickKeybindState.open = false
        _quickKeybindState.closePending = true
        EAB_UpdateQuickKeybindButtons(false)
        _quickKeybindState.UpdateMacroButtons(false)
        -- Mouseover fading is alpha-only and already operates during combat,
        -- so restore that presentation immediately even though secure
        -- visibility drivers still have to wait until combat ends.
        EAB:RefreshMouseover()
        _qkbHookFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    _quickKeybindState.open = false
    EAB_UpdateQuickKeybindButtons(false)
    _quickKeybindState.UpdateMacroButtons(false)
    _quickKeybindState.FinishClose()
end

-- Defer hook until QuickKeybindFrame exists (it loads after PLAYER_LOGIN).
_qkbHookFrame = CreateFrame("Frame")
_qkbHookFrame:RegisterEvent("PLAYER_LOGIN")
_qkbHookFrame:RegisterEvent("ADDON_LOADED")
_qkbHookFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        C_Timer_After(1, function()
            local qkb = QuickKeybindFrame
            if qkb then
                if _pagingFrame then
                    InitPagingQuickKeybindButton(_pagingFrame._upBtn, "UI-HUD-ActionBar-PageUpArrow-Mouseover")
                    InitPagingQuickKeybindButton(_pagingFrame._downBtn, "UI-HUD-ActionBar-PageDownArrow-Mouseover")
                end
                -- Install a stable frame-owned wrapper once, then update the
                -- target callbacks each session so /reload never stacks stale
                -- closures that still point at an old Lua chunk.
                local qfd = EFD(qkb)
                if not qfd.quickKeybindShowHook then
                    qfd.quickKeybindShowHook = function(frame)
                        local ffd = EFD(frame)
                        if ffd.quickKeybindOnShow then
                            ffd.quickKeybindOnShow()
                        end
                    end
                    qfd.quickKeybindHideHook = function(frame)
                        local ffd = EFD(frame)
                        if ffd.quickKeybindOnHide then
                            ffd.quickKeybindOnHide()
                        end
                    end
                    qkb:HookScript("OnShow", qfd.quickKeybindShowHook)
                    qkb:HookScript("OnHide", qfd.quickKeybindHideHook)
                end
                qfd.quickKeybindOnShow = _quickKeybindState.Open
                qfd.quickKeybindOnHide = EAB_QuickKeybindClose
                _quickKeybindState.InitMacroFrame()
                if _quickKeybindState.macroFrameHooked then
                    self:UnregisterEvent("ADDON_LOADED")
                end
            end
        end)
    elseif event == "ADDON_LOADED" and (addonName == "Blizzard_MacroUI" or addonName == "Blizzard_QuickKeybind") then
        _quickKeybindState.InitMacroFrame()
        if _quickKeybindState.macroFrameHooked then
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if _quickKeybindState.closePending then
            _quickKeybindState.FinishClose()
        elseif _quickKeybindState.open
            and not (QuickKeybindFrame and QuickKeybindFrame:IsShown()) then
            EAB_QuickKeybindClose()
        end
    end
end)

-------------------------------------------------------------------------------
--  Swiftmend Brightness Fix (action bar scan)
--  Scans all EABButton slots for Swiftmend by matching icon file ID.
--  Re-scans on slot changes so bar rearrangement is covered.
-------------------------------------------------------------------------------
;(function()
    local function ScanABSwiftmend()
        local _, cls = UnitClass("player")
        if cls ~= "DRUID" then return end
        local hook   = EllesmereUI and EllesmereUI._HookSwiftmendIcon
        local iconID = EllesmereUI and EllesmereUI._SWIFTMEND_ICON
        if not hook or not iconID then return end
        for slot = 1, 180 do
            local btn = _G["EABButton" .. slot]
            if btn and btn.icon then
                local t = btn.icon:GetTexture()
                if not issecretvalue(t) and t == iconID then hook(btn.icon) end
            end
        end
    end
    _G._EAB_ScanSwiftmend = ScanABSwiftmend
    -- The scan is druid-only (it bails on class), so non-druids get no
    -- listener at all: class never changes within a session.
    local _, _playerCls = UnitClass("player")
    if _playerCls ~= "DRUID" then return end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    -- Coalesced: one 0.5s rescan window at a time. ACTIONBAR_SLOT_CHANGED can
    -- storm (mouseover-conditional macros re-resolving on every mouseover flip);
    -- scheduling a timer per event ran the full scan dozens of times per second.
    local _smPending = false
    local function SwiftmendRescan()
        _smPending = false
        ScanABSwiftmend()
    end
    f:SetScript("OnEvent", function()
        if not _smPending then
            _smPending = true
            C_Timer.After(0.5, SwiftmendRescan)
        end
    end)
end)()
