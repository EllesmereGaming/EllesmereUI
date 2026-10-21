if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIMinimap.lua
--  Custom minimap skin and layout for EllesmereUI.
-------------------------------------------------------------------------------
local ADDON_NAME = ...
if not (EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI.NewCombatQueue) then EUI_CLIENT_BLOCKED = true; return end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
local ns = select(2, ...)
EllesmereUI._ModuleNS[ADDON_NAME] = ns  -- LOD options files read this module ns via the registry
ns.CombatQueue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))

local EBS = EllesmereUI.Lite.NewAddon("EllesmereUIMinimap")

local PP = EllesmereUI.PP

-- Per-size offset/shift defaults for the textured border styles (same as unit frames).
EllesmereUI.RegisterBorderDefaults("minimap", EllesmereUI.BORDER_DEFAULTS_FRAMES)

local EG = EllesmereUI.ELLESMERE_GREEN

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-- Call-site compat only; the minimap module is never force-disabled here.
local TEMP_DISABLED = {}

local defaults = {
    profile = {
        minimap = {
            enabled       = true,
            -- Blizzard Style (Global Settings > Style): the stock compass ring,
            -- top border bar and element placement on our map with every EUI
            -- feature intact. Default OFF; reload-gated.
            useBlizzardStyle = false,
            -- Classic WoW UI (Global Settings > Style): the vanilla ring, zone
            -- banner and zoom buttons on our map, the same stock-mode geometry
            -- as Blizzard Style. Default OFF; reload-gated.
            useClassicStyle = false,
            -- The WoW Forever look's Border Style (latched in EBS._MinimapStyle):
            -- "square" = Forever Square, the default there, "circle" = Forever
            -- Circle. Nil on every other client, where nothing reads it.
            foreverBorder = (EllesmereUI.IS_FOREVER == true) and "square" or nil,
            -- Blizzard Style's own Border Style on the Forever client (latched
            -- the same way): "square" = the square map in the slim bronze
            -- line, the default there, "circle" = the round map in Blizzard's
            -- ring. Nil on every other client, where nothing reads it.
            blizzBorder   = (EllesmereUI.IS_FOREVER == true) and "square" or nil,
            shape         = "square",
            rotateMinimap = false,
            borderSize    = 1,
            showCoords    = false,
            coordPrecision = 0,
            -- Coords: mode (never/hover/always) + anchor; migrated from coordsBelow (minimap_coords_mode_position_v1, see GetCoordsModePos).
            coordsMode     = "always",
            coordsPosition = "topLeft",
            coordsScale    = 1.0,
            -- FPS/MS readout (Text section); options mirror the QoL FPS counter
            showFPS           = false,
            fpsTextSize       = 12,
            fpsScale          = 1.0,
            fpsShowLocalMS    = true,
            fpsShowWorldMS    = false,
            fpsUseAccent      = false,  -- description text: accent vs custom fpsColor
            fpsColorClockAMPM = false,  -- also tint the clock's AM/PM suffix
            fpsPosition       = "bottomLeft",
            fpsOffsetX        = 0,
            fpsOffsetY        = 0,
            fpsHoverTooltip   = "none",  -- none | lockouts | vault
            fpsUpdateInterval = 3,       -- seconds between FPS/MS refreshes (1-5)
            clockHoverTooltip = "none",
            -- Instance Difficulty as Text: compact "20M" readout replacing Blizzard's flag.
            diffTextEnabled   = false,
            diffTextPosition  = "topLeft",
            diffTextSize      = 12,
            diffTextOffsetX   = 0,
            diffTextOffsetY   = 0,
            -- Accented Text: which elements colour their descriptions (clock AM/PM =
            -- fpsColorClockAMPM); diffTextReactive (tier) and diffTextAccent (flat) are mutually exclusive.
            fpsColorSuffix    = true,
            diffTextAccent    = false,
            diffTextReactive  = false,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
            useClassColor = false,
            -- Location/clock: none | inside (on the map) | edge (boxed on the map edge); migrated by minimap_clock_location_mode_v2 (see GetElementModes).
            locationMode  = "inside",
            locationPosition = "bottom",
            zoneReactiveColor = false,  -- tint zone text by the zone's PvP ruleset
            zoneShowSubZone   = false,  -- prefer the subzone name (zone fallback)
            scrollZoom    = true,
            openMicroMenuOnMiddleClick = true,
            savedZoom     = 0,
            -- Auto Zoom Reset: seconds of inactivity after a manual zoom change before snapping back to zoom level 0 (max distance). 0 = disabled (default).
            zoomResetSeconds = 0,
            -- false = Zoom +/- Icons checked in Show Blizzard Elements (buttons hover-show). The old true default was inert on Midnight (targeted pre-Midnight global button names), so flipping it changed nobody's visual state.
            hideZoomButtons      = false,
            -- false = Tracking checked in Show Blizzard Elements on both clients (user
            -- decision 2026-09-21); a profile that never touched the row gains the button.
            hideTrackingButton   = false,
            hideGameTime         = false,
            hideMail             = false,
            -- Mail indicator: "button" = element row, or a map corner (TOPLEFT/TOPRIGHT/BOTTOMLEFT/BOTTOMRIGHT) pinned like Omnium Folio's, nudged by X/Y offsets.
            mailPosition         = "button",
            mailOffsetX          = 0,
            mailOffsetY          = 0,
            hideRaidDifficulty   = false,
            hideCraftingOrder    = false,
            friendsMaxRows       = 0,   -- 0 = no cap; else cap per section, show "...and N more"
            friendsShowNotes     = false,  -- guild/friend note on a second line under each row
            hideExtraBtns        = { greatVault = false, portals = false, friendsOnline = false, groupButton = false },
            mouseoverExtraBtns   = false,  -- extra buttons only show on minimap mouseover
            greatVaultExtraInfo  = true,
            -- Addon compartment: Blizzard's button lives in MinimapCluster,
            -- which this module alpha-zeroes -- it is reparented onto our own
            -- Minimap and pinned like the Omnium Folio (corner + X/Y nudge).
            -- Hidden by default (product decision): users opt in via the
            -- Show Addon Compartment toggle.
            hideAddonCompartment    = true,
            addonCompartmentCorner  = "TOPRIGHT",
            addonCompartmentX       = 0,
            addonCompartmentY       = 0,
            addonCompartmentScale   = 0.9,
            -- Expansion landing page button: never | hover | always. Migrated from showOmniumFolio (minimap_omnium_folio_mode_v1).
            omniumFolioMode      = "always",
            omniumFolioCorner    = "BOTTOMLEFT",  -- which minimap corner to anchor to
            omniumFolioX         = 0,
            omniumFolioY         = 0,
            omniumFolioScale     = 0.75,
            hideAddonButtons     = false,
            addonBtnSize         = 24,
            interactableBtnSize  = 21,
            ungroupedButtons     = {},
            freeMoveBtns         = false,
            btnBackgrounds       = true,
            btnPositions         = {},
            btnRowPosition       = "blUp",   -- blUp = original corner + direction
            btnRowSpacing        = 0,
            btnRowDistance       = 0,
            flyoutGrowDir        = "auto",   -- Grow Tooltip/Popup: auto/up/down/left/right
            elementRowPosition   = "tlDown", -- tlDown = original corner + direction
            elementRowSpacing    = 0,
            elementRowDistance   = 0,

            extraFlyoutScale     = 1.0,   -- M+ Portals flyout scale
            customTooltipScale   = 1.0,   -- custom tooltips on the unique minimap buttons
            clockMode     = "inside",
            clockPosition = "top",
            clockFormat   = "12h",
            clockScale    = 1.15,
            clockOffsetX  = 0,
            clockOffsetY  = 0,
            locationScale = 1.15,
            locationOffsetX = 0,
            locationOffsetY = 0,
            lock          = false,
            position      = nil,
            visibility    = "always",
            -- Opacity (Visibility cog), percent 10-100: the alpha of the shown map (EBS._MapAlpha).
            opacity       = 100,
            visOnlyInstances = false,
            visHideHousing   = false,
            visHideMounted   = false,
            visHideNoTarget  = false,
            visHideNoEnemy   = false,
        },
    },
}

-------------------------------------------------------------------------------
--  Utility
-------------------------------------------------------------------------------
local function GetBorderColor(cfg)
    if cfg.useClassColor then
        -- Legacy flag name kept for SV compat; it means "use the live accent color".
        return EG.r, EG.g, EG.b, 1
    end
    return cfg.borderR, cfg.borderG, cfg.borderB, cfg.borderA or 1
end

-- Border colour precedence (3 swatches): borderUseClassColor > useClassColor (legacy) >
-- borderColor > legacy borderR/G/B, so pre-style users keep their colour until they touch the new controls. Clock/zone edge boxes share this precedence.
local function GetBorderStyleColor(cfg)
    if cfg.borderUseClassColor and EllesmereUI.GetClassColor then
        local cc = EllesmereUI.GetClassColor(select(2, UnitClass("player")))
        if cc then return cc.r, cc.g, cc.b, cfg.borderA or 1 end
    end
    if cfg.useClassColor then
        return EG.r, EG.g, EG.b, cfg.borderA or 1
    end
    local c = cfg.borderColor
    if c then return c.r, c.g, c.b, cfg.borderA or 1 end
    return GetBorderColor(cfg)
end

-- The clock and zone Edge Box fill: the border colour above, or black under
-- a square frame on the Forever client (its bronze frame takes no colour, and
-- the border colour rows are hidden there). An EBS field.
function EBS._EdgeBoxColor(cfg)
    if EBS._fvSquare then return 0, 0, 0 end
    return GetBorderStyleColor(cfg)
end

-------------------------------------------------------------------------------
--  Combat safety
-------------------------------------------------------------------------------
local ApplyAll  -- forward declaration

-- Keyed queue entry: repeat requests before regen collapse into one apply.
local function QueueApplyAll()
    ns.CombatQueue.Defer("ApplyAll", ApplyAll)
end

-------------------------------------------------------------------------------
--  Minimap Skin
-------------------------------------------------------------------------------
-- MinimapBackdrop (the frame) is deliberately NOT in this list: hiding the
-- texture regions is enough (its only other art, StaticOverlayTexture, ships
-- hidden; its one child button is managed separately below), and third-party
-- encounter tools read the player's facing from
-- MinimapCompassTexture:GetRotation() -- the instanced-content stand-in for
-- the restricted GetPlayerFacing(). The compass is a REGION of the backdrop:
-- with the parent frame hidden it never renders, the client stops rotating
-- it, and those tools' facing reads freeze. They re-Show the texture
-- themselves (raw metatable Show, at alpha 0), so hiding the TEXTURE here is
-- fully compatible; hiding its PARENT is not.
local minimapDecorations = {
    "MinimapBorder",
    "MinimapBorderTop",
    "MinimapNorthTag",
    "MinimapCompassTexture",
    "TimeManagerClockButton",
}

local cachedAddonButtons = {}
local _addonVisible = {}       -- persistent: tracks whether each addon WANTS its button visible
EBS._suppressVisTrack = false -- flag to suppress tracking during our own Show/Hide calls
local flyoutOwnedFrames = {}

-- EBS._HVRevealMapHover (defined in EUI_Minimap_Layout.lua; namespace-scoped, not a
-- local) is fired by earlier child elements' OnEnter (mail etc.),
-- since entering the map directly onto a mouse-enabled child never fires the minimap's own OnEnter.

-- Main-chunk locals the EUI_Minimap_*.lua files re-import by name.
-- applyAllSetters and the lists beside it: every file that reads one of
-- these keeps its own copy and adds a setter here; a write from another file
-- goes through the Set<Name> function built below, which runs them all.
-- broken: true while an EUI_Minimap_*.lua file loads; a file that fails
-- leaves it set, and the files behind it return at their first lines.
ns._internals = {
    _addonVisible = _addonVisible, ADDON_NAME = ADDON_NAME,
    cachedAddonButtons = cachedAddonButtons, defaults = defaults, EBS = EBS, EG = EG,
    flyoutOwnedFrames = flyoutOwnedFrames, GetBorderStyleColor = GetBorderStyleColor,
    GetFFD = GetFFD, minimapDecorations = minimapDecorations, PP = PP,
    QueueApplyAll = QueueApplyAll, TEMP_DISABLED = TEMP_DISABLED,
    applyAllSetters = { function(v) ApplyAll = v end },
    applyMinimapSetters = {},
    moEvaluateSetters = {}, flyoutToggleSetters = {}, flyoutPanelSetters = {},
    portalFlyoutSetters = {}, coordFrameSetters = {}, coordTickerSetters = {},
    clockFrameSetters = {}, clockBgSetters = {}, locationFrameSetters = {},
    locationBgSetters = {}, mmKeyHiddenSetters = {},
    broken = false,
}
-- Set<Name> hands a new value to every copy registered in <name>Setters.
for setter, listName in pairs({
    SetApplyAll = "applyAllSetters", SetMOEvaluate = "moEvaluateSetters",
    SetFlyoutToggle = "flyoutToggleSetters", SetFlyoutPanel = "flyoutPanelSetters",
    SetPortalFlyout = "portalFlyoutSetters", SetCoordFrame = "coordFrameSetters",
    SetCoordTicker = "coordTickerSetters", SetClockFrame = "clockFrameSetters",
    SetClockBg = "clockBgSetters", SetLocationFrame = "locationFrameSetters",
    SetLocationBg = "locationBgSetters", SetMMKeyHidden = "mmKeyHiddenSetters",
    SetApplyMinimap = "applyMinimapSetters",
}) do
    local list = ns._internals[listName]
    ns._internals[setter] = function(v)
        for i = 1, #list do list[i](v) end
    end
end
-- A re-import of a name this table lacks fails where the part file loads,
-- not later as a nil upvalue inside one of its functions.
setmetatable(ns._internals, { __index = function(_, k)
    error("ns._internals has no entry " .. tostring(k), 2)
end })
