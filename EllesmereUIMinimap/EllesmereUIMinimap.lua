-------------------------------------------------------------------------------
--  EllesmereUIMinimap.lua
--  Custom minimap skin and layout for EllesmereUI.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

local EBS = EllesmereUI.Lite.NewAddon("EllesmereUIMinimap")

local PP = EllesmereUI.PP

-- Per-size offset/shift defaults for the textured border styles, registered
-- with the shared border engine (same values as the unit frames).
do
    local ALL_SIZES = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true }
    local function AllSizes(ox, oy, sx, sy)
        local t = {}
        for k in pairs(ALL_SIZES) do t[k] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy } end
        return t
    end
    EllesmereUI.RegisterBorderDefaults("minimap", {
        ["glow"] = {
            defaultSize = 1,
            sizes = AllSizes(0, 0, 0, 0),
        },
        ["blizz"] = {
            defaultSize = 4,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 3, offsetY = 1, shiftX = 1, shiftY = 0 },
                [3] = { offsetX = 4, offsetY = 2, shiftX = 2, shiftY = 0 },
                [4] = { offsetX = 5, offsetY = 3, shiftX = 2, shiftY = 0 },
            },
        },
        ["dialog"] = {
            defaultSize = 2,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 2, offsetY = 2, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 2, offsetY = 2, shiftX = 0, shiftY = 0 },
                [3] = { offsetX = 4, offsetY = 4, shiftX = 0, shiftY = 0 },
                [4] = { offsetX = 8, offsetY = 8, shiftX = 0, shiftY = 0 },
            },
        },
        ["sm:Blizzard Achievement Wood"] = {
            defaultSize = 1,
            sizes = AllSizes(1, 1, 0, 0),
        },
    })
end

local EG = EllesmereUI.ELLESMERE_GREEN

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD = setmetatable({}, { __mode = "k" })
local function GetFFD(frame)
    local d = FFD[frame]
    if not d then d = {}; FFD[frame] = d end
    return d
end

-- TEMP_DISABLED kept for call-site compat with helper functions that still
-- reference it. Minimap module is never force-disabled here.
local TEMP_DISABLED = {}

local defaults = {
    profile = {
        minimap = {
            enabled       = true,
            shape         = "square",
            rotateMinimap = false,
            borderSize    = 1,
            showCoords    = false,
            coordPrecision = 0,
            -- Coordinates display: mode (never/hover/always) + anchor position.
            -- Existing users are migrated from the legacy coordsBelow toggle
            -- (minimap_coords_mode_position_v1): true -> always/belowMap,
            -- false -> hover/topLeft.
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
            -- Show Instance Difficulty as Text: replaces the Blizzard
            -- difficulty flag with a compact "20M"-style readout.
            diffTextEnabled   = false,
            diffTextPosition  = "topLeft",
            diffTextSize      = 12,
            diffTextOffsetX   = 0,
            diffTextOffsetY   = 0,
            -- Accented Text: which Text-section elements colour their
            -- description parts (clock AM/PM key is fpsColorClockAMPM).
            -- diffTextReactive colours the difficulty letter by TIER instead
            -- of the flat accent/custom colour; mutually exclusive with
            -- diffTextAccent.
            fpsColorSuffix    = true,
            diffTextAccent    = false,
            diffTextReactive  = false,
            borderR       = 0, borderG = 0, borderB = 0, borderA = 1,
            useClassColor = false,
            -- Location/clock display: none | inside (on the map) | edge (boxed
            -- on the map edge). Existing users are migrated from the legacy
            -- zoneInside/clockInside toggles and the removed Show Blizzard
            -- Elements Zone/Clock checkboxes (minimap_clock_location_mode_v2).
            locationMode  = "inside",
            locationPosition = "bottom",
            zoneReactiveColor = false,  -- tint zone text by the zone's PvP ruleset
            zoneShowSubZone   = false,  -- prefer the subzone name (zone fallback)
            scrollZoom    = true,
            openMicroMenuOnMiddleClick = true,
            savedZoom     = 0,
            -- false = Zoom +/- Icons checked in Show Blizzard Elements (the
            -- buttons hover-show as usual). The old true default was inert on
            -- Midnight (it targeted the pre-Midnight global button names), so
            -- flipping it changes nobody's visual state.
            hideZoomButtons      = false,
            hideTrackingButton   = true,
            hideGameTime         = false,
            hideMail             = false,
            -- Mail indicator: "button" = in the element row; or a map corner
            -- (TOPLEFT/TOPRIGHT/BOTTOMLEFT/BOTTOMRIGHT), pinned like the
            -- Omnium Folio corner option, nudged by the X/Y offsets.
            mailPosition         = "button",
            mailOffsetX          = 0,
            mailOffsetY          = 0,
            hideRaidDifficulty   = false,
            hideCraftingOrder    = false,
            friendsMaxRows       = 0,   -- 0 = no cap; else cap per section, show "...and N more"
            hideExtraBtns        = { greatVault = false, portals = false, friendsOnline = false, groupButton = false },
            mouseoverExtraBtns   = false,  -- extra buttons only show on minimap mouseover
            greatVaultExtraInfo  = true,
            hideAddonCompartment = false,
            -- Expansion landing page button: never | hover | always. Existing
            -- users are migrated from the legacy showOmniumFolio toggle
            -- (minimap_omnium_folio_mode_v1).
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
        -- Flag name is legacy ("useClassColor") but both minimap and friends
        -- now use the live EllesmereUI accent color when it's set. The flag
        -- name is kept as-is for backwards compat with stored SV data.
        return EG.r, EG.g, EG.b, 1
    end
    return cfg.borderR, cfg.borderG, cfg.borderB, cfg.borderA or 1
end

-- Map BORDER colour, driven by the three Border Size swatches: class colour >
-- accent (legacy useClassColor flag) > custom (borderColor, set by the swatch
-- or style select) > legacy borderR/G/B fallback, so pre-style users keep
-- their existing border colour until they touch the new controls. The
-- clock/zone edge boxes follow the same colour.
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

-------------------------------------------------------------------------------
--  Combat safety
-------------------------------------------------------------------------------
local pendingApply = false
local ApplyAll  -- forward declaration

local function QueueApplyAll()
    if pendingApply then return end
    pendingApply = true
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if pendingApply then
        pendingApply = false
        ApplyAll()
    end
end)

-------------------------------------------------------------------------------
--  Minimap Skin
-------------------------------------------------------------------------------
local minimapDecorations = {
    "MinimapBorder",
    "MinimapBorderTop",
    "MinimapBackdrop",
    "MinimapNorthTag",
    "MinimapCompassTexture",
    "TimeManagerClockButton",
}

local minimapButtonMap = {
    -- Zoom buttons are handled in ApplyMinimap (hideZoomButtons reparents
    -- Minimap.ZoomIn/ZoomOut to the hidden frame), not via this name map.
    { key = "hideTrackingButton",   names = { "MiniMapTrackingButton" } },
    { key = "hideGameTime",         names = { "GameTimeFrame" } },
    { key = "hideMail",             names = { "MiniMapMailFrame" } },
    { key = "hideRaidDifficulty",   names = { "MiniMapInstanceDifficulty", "GuildInstanceDifficulty" } },
    { key = "hideCraftingOrder",    names = { "MiniMapCraftingOrderFrame" } },
    { key = "hideAddonCompartment", names = { "AddonCompartmentFrame" } },
}

local minimapButtonHooks = {}

local function HideMinimapButton(name)
    local btn = _G[name]
    if not btn then return end
    btn:Hide()
    btn:SetAlpha(0)
    if not minimapButtonHooks[name] then
        hooksecurefunc(btn, "Show", function(self)
            if InCombatLockdown() then return end
            local mp = EBS.db and EBS.db.profile.minimap
            if not mp then return end
            for _, entry in ipairs(minimapButtonMap) do
                for _, btnName in ipairs(entry.names) do
                    if btnName == name and mp[entry.key] then
                        self:SetAlpha(0)
                        return
                    end
                end
            end
        end)
        minimapButtonHooks[name] = true
    end
end

local function ShowMinimapButton(name)
    local btn = _G[name]
    if not btn then return end
    btn:SetAlpha(1)
    btn:EnableMouse(true)
    btn:Show()
end

-- Forward declarations for flyout system
local addonButtonPoll = nil
local cachedAddonButtons = {}
local _addonVisible = {}       -- persistent: tracks whether each addon WANTS its button visible
local _suppressVisTrack = false -- flag to suppress tracking during our own Show/Hide calls
local flyoutOwnedFrames = {}

-- Mouseover Extra Buttons: re-evaluator, assigned by the controller further down.
-- Forward-declared here so the flyout panels (created earlier than the
-- controller) can trigger a re-evaluate from their OnShow/OnHide hooks.
local MO_Evaluate

-- Map-region hover reveal: EBS._HVRevealMapHover, defined next to the folio
-- code further down (namespace-scoped, not a local -- this file is close to
-- the 200-local main-chunk cap). Child elements created earlier in the file
-- (mail indicator etc.) fire it from their OnEnter -- entering the map
-- directly onto a mouse-enabled child never fires the minimap's own OnEnter.

-------------------------------------------------------------------------------
--  Minimap Button Flyout
-------------------------------------------------------------------------------
local flyoutToggle = nil   -- the square trigger button
local flyoutPanel  = nil   -- the popup grid container
local flyoutSavedParents = {}  -- original parent/point data for restore
local flyoutSavedRegions = {}  -- original region states for restore

local FLYOUT_BTN_SIZE = 24
local FLYOUT_PADDING  = 4
local FLYOUT_COLS     = 4

-- Textures that are decorative borders/backgrounds on minimap buttons
local MINIMAP_BTN_JUNK = {
    [136467] = true,  -- UI-Minimap-Background
    [136430] = true,  -- MiniMap-TrackingBorder
    [136477] = true,  -- UI-Minimap-ZoomButton-Highlight (used on some buttons)
}
local MINIMAP_BTN_JUNK_PATH = {
    ["Interface\\Minimap\\MiniMap%-TrackingBorder"] = true,
    ["Interface\\Minimap\\UI%-Minimap%-Background"] = true,
    ["Interface\\Minimap\\UI%-Minimap%-ZoomButton%-Highlight"] = true,
}

local function IsJunkTexture(region)
    if not region or not region.IsObjectType or not region:IsObjectType("Texture") then
        return false
    end
    local texID = region.GetTextureFileID and region:GetTextureFileID()
    if texID and MINIMAP_BTN_JUNK[texID] then return true end
    local texPath = region:GetTexture()
    if texPath and type(texPath) == "string" then
        for pattern in pairs(MINIMAP_BTN_JUNK_PATH) do
            if texPath:match(pattern) then return true end
        end
    end
    return false
end

local function StripButtonDecorations(btn)
    -- Only snapshot original state once; subsequent calls just re-hide
    if not flyoutSavedRegions[btn] then
        local saved = { junk = {} }
        for _, region in ipairs({ btn:GetRegions() }) do
            if IsJunkTexture(region) then
                saved.junk[#saved.junk + 1] = { region = region, alpha = region:GetAlpha(), shown = region:IsShown() }
            end
        end
        local hl = btn.GetHighlightTexture and btn:GetHighlightTexture()
        if hl and IsJunkTexture(hl) then
            saved.junk[#saved.junk + 1] = { region = hl, alpha = hl:GetAlpha(), shown = hl:IsShown() }
        end
        -- Snapshot icon anchors/texcoord so we can restore native layout
        local icon = btn.icon or btn.Icon
        if icon then
            local nPts = icon:GetNumPoints()
            local pts = {}
            for i = 1, nPts do
                pts[i] = { icon:GetPoint(i) }
            end
            saved.icon = icon
            saved.iconPoints = pts
            saved.iconTC = { icon:GetTexCoord() }
        end
        -- Snapshot native button size
        saved.btnW, saved.btnH = btn:GetWidth(), btn:GetHeight()
        flyoutSavedRegions[btn] = saved
    end
    -- Hide junk textures (runs every call)
    for _, info in ipairs(flyoutSavedRegions[btn].junk) do
        info.region:SetAlpha(0)
        info.region:Hide()
    end
end

local function RestoreButtonDecorations(btn)
    local saved = flyoutSavedRegions[btn]
    if not saved then return end
    for _, info in ipairs(saved.junk) do
        info.region:SetAlpha(info.alpha)
        if info.shown then info.region:Show() end
    end
    -- Restore icon anchors and texcoord
    if saved.icon and saved.iconPoints then
        saved.icon:ClearAllPoints()
        for _, pt in ipairs(saved.iconPoints) do
            saved.icon:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5])
        end
        if saved.iconTC and #saved.iconTC >= 8 then
            saved.icon:SetTexCoord(unpack(saved.iconTC))
        end
    end
    -- Restore native button size
    if saved.btnW and saved.btnH then
        btn:SetSize(saved.btnW, saved.btnH)
    end
    flyoutSavedRegions[btn] = nil
end

local function IsUngrouped(btn)
    local mp = EBS.db and EBS.db.profile.minimap
    if not mp or not mp.ungroupedButtons then return false end
    local name = btn:GetName()
    return name and mp.ungroupedButtons[name]
end

local function GetMinimapButtonLabel(btn)
    local name = btn:GetName() or ""
    return name:gsub("^LibDBIcon10_", ""):gsub("^Lib_GPI_Minimap_", ""):gsub("MinimapButton$", ""):gsub("_MinimapButton$", "")
end

local function CollectFlyoutButtons()
    -- Return only buttons the addon wants visible and not ungrouped
    local collected = {}
    for _, btn in ipairs(cachedAddonButtons) do
        if _addonVisible[btn] ~= false and not IsUngrouped(btn) then
            collected[#collected + 1] = btn
        end
    end
    table.sort(collected, function(a, b)
        return GetMinimapButtonLabel(a):lower() < GetMinimapButtonLabel(b):lower()
    end)
    return collected
end

local function GetAddonBtnSize()
    local mp = EBS.db and EBS.db.profile.minimap
    return mp and mp.addonBtnSize or FLYOUT_BTN_SIZE
end

local function LayoutFlyoutButtons()
    if not flyoutPanel then return end
    local buttons = CollectFlyoutButtons()
    local count = #buttons
    if count == 0 then
        flyoutPanel:SetSize(1, 1)
        return
    end

    local btnSize = GetAddonBtnSize()
    -- Outer breathing room; gaps between buttons stay FLYOUT_PADDING. The
    -- ring overlay overhangs each button by 3px, so 8 leaves 5px of VISIBLE
    -- clearance between the rings and the panel edge.
    local margin = 8
    local cols = math.min(count, FLYOUT_COLS)
    local rows = math.ceil(count / cols)
    local pw = margin * 2 + cols * btnSize + (cols - 1) * FLYOUT_PADDING
    local ph = margin * 2 + rows * btnSize + (rows - 1) * FLYOUT_PADDING
    flyoutPanel:SetSize(pw, ph)

    for i, btn in ipairs(buttons) do
        -- Save original parent/points for restore
        if not flyoutSavedParents[btn] then
            local p1, rel, p2, ox, oy = btn:GetPoint(1)
            flyoutSavedParents[btn] = {
                parent = btn:GetParent(),
                strata = btn:GetFrameStrata(),
                point = p1, relTo = rel, relPoint = p2, x = ox, y = oy,
            }
        end

        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local xOff = margin + col * (btnSize + FLYOUT_PADDING)
        local yOff = -(margin + row * (btnSize + FLYOUT_PADDING))

        btn:SetParent(flyoutPanel)
        -- Unlock fixed strata/level first (LibDBIcon locks these)
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
        btn:SetFrameStrata("DIALOG")
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(true) end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", flyoutPanel, "TOPLEFT", xOff, yOff)
        btn:SetSize(btnSize, btnSize)
        _suppressVisTrack = true
        btn:SetAlpha(1)
        btn:Show()
        _suppressVisTrack = false
        btn:SetFrameLevel(flyoutPanel:GetFrameLevel() + 5)
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(true) end
        -- Strip decorative border/background textures
        StripButtonDecorations(btn)
        -- Hide ungrouped overlays left over from a previous ungroup cycle
        if GetFFD(btn).ungroupBg then GetFFD(btn).ungroupBg:Hide() end
        if btn._ungroupRing then btn._ungroupRing:Hide() end
        -- Also force all child frames up to the same strata/level
        for _, child in ipairs({ btn:GetChildren() }) do
            child:SetFrameStrata("DIALOG")
            child:SetFrameLevel(flyoutPanel:GetFrameLevel() + 6)
        end
        -- Normalize icon region to fill the button cleanly
        local icon = btn.icon or btn.Icon
        if not icon then
            for _, region in ipairs({ btn:GetRegions() }) do
                if region:IsObjectType("Texture") and region:IsShown()
                   and region:GetAlpha() > 0 and not IsJunkTexture(region) then
                    icon = region
                    break
                end
            end
        end
        if icon then
            icon:ClearAllPoints()
            icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
            icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
            pcall(icon.SetTexCoord, icon, 0.05, 0.95, 0.05, 0.95)
            -- Foreign button icon: SetTexCoord was its only snap trigger and
            -- that hook is no longer global, so disable snap on it once here.
            if EllesmereUI.PP then EllesmereUI.PP.DisablePixelSnap(icon) end
        end
        -- Add atlas ring border overlay
        if not GetFFD(btn).flyoutRing then
            local ring = btn:CreateTexture(nil, "OVERLAY", nil, 7)
            ring:SetAtlas("AdventureMap-combatally-ring")
            ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -3, 3)
            ring:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -3)
            GetFFD(btn).flyoutRing = ring
        end
        GetFFD(btn).flyoutRing:Show()
    end
end

local function RestoreFlyoutButtons()
    for btn, saved in pairs(flyoutSavedParents) do
        RestoreButtonDecorations(btn)
        if GetFFD(btn).flyoutRing then GetFFD(btn).flyoutRing:Hide() end
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
        btn:SetParent(saved.parent)
        btn:SetFrameStrata(saved.strata)
        btn:ClearAllPoints()
        if saved.point and saved.relTo then
            btn:SetPoint(saved.point, saved.relTo, saved.relPoint, saved.x, saved.y)
        end
        -- Re-hide on the minimap surface
        _suppressVisTrack = true
        btn:Hide()
        btn:SetAlpha(0)
        _suppressVisTrack = false
    end
    wipe(flyoutSavedParents)
end

-- Grow Tooltip/Popup: which way the popups (M+ portals flyout, button group
-- flyout) and the custom tooltips open out from their buttons. All consumers
-- share one direction. Auto follows Button Row Position: vertical rows
-- (columns on the left/right edges) open left, horizontal rows (above/below
-- the map) open down. Namespace-scoped (EBS field, not locals) -- this file
-- is close to the 200-local main-chunk cap.
-- edge = anchor tuples (tooltip point, anchor point, x, y) hanging the popup
-- from a corner of its anchor (friends/calendar tooltips, flyouts); center =
-- centered on the facing edge (vault tooltip); tt = named sides for the small
-- ShowWidgetTooltip labels (anything besides left/right/below anchors above).
EBS._Grow = {
    edge = {
        left  = { "TOPRIGHT",   "TOPLEFT",    -4, 0 },
        right = { "TOPLEFT",    "TOPRIGHT",    4, 0 },
        up    = { "BOTTOMLEFT", "TOPLEFT",     0, 4 },
        down  = { "TOPLEFT",    "BOTTOMLEFT",  0, -4 },
    },
    center = {
        left  = { "RIGHT",  "LEFT",   -4, 0 },
        right = { "LEFT",   "RIGHT",   4, 0 },
        up    = { "BOTTOM", "TOP",     0, 4 },
        down  = { "TOP",    "BOTTOM",  0, -4 },
    },
    tt = { left = "left", right = "right", up = "above", down = "below" },
}

function EBS._Grow.Dir()
    local mp = EBS.db and EBS.db.profile.minimap
    local g = (mp and mp.flyoutGrowDir) or "auto"
    if g ~= "auto" then return g end
    local rp = (mp and mp.btnRowPosition) or "blUp"
    if rp == "blUp" or rp == "tlDown" or rp == "brUp" or rp == "trDown" then
        return "left"
    end
    return "down"
end

function EBS._Grow.TT()
    return EBS._Grow.tt[EBS._Grow.Dir()] or "left"
end

local _flyoutBuilt = false

local function EnsureFlyoutPanel()
    if not flyoutPanel then
        flyoutPanel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        flyoutPanel:SetFrameStrata("DIALOG")
        flyoutPanel:SetBackdrop({
            bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 1,
        })
        flyoutPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        flyoutPanel:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        -- Anchored per Grow Tooltip/Popup on every open (see ShowFlyoutPanel)
        flyoutPanel:SetClampedToScreen(true)
        flyoutOwnedFrames[flyoutPanel] = true
        -- Keep the mouseover stack in sync while this flyout opens/closes.
        flyoutPanel:HookScript("OnShow", function() if MO_Evaluate then MO_Evaluate() end end)
        flyoutPanel:HookScript("OnHide", function() if MO_Evaluate then MO_Evaluate() end end)
        -- Start hidden: frames are created SHOWN, and OnShow only fires on a
        -- real hide->show transition -- without this the first open of the
        -- session never installs the click-away watcher below.
        flyoutPanel:Hide()
        -- Click-away dismiss (same pattern as the options-panel dropdowns):
        -- while shown, close on any left press outside the grid and its
        -- toggle. IsMouseButtonDown reads raw input state -- polling it never
        -- captures the click, so world/UI clicks still land where they were
        -- headed. Clicks on the toggle are excluded so its own OnClick
        -- handles the close without a close/reopen race.
        flyoutPanel:HookScript("OnShow", function(self)
            self:SetScript("OnUpdate", function(m)
                if IsMouseButtonDown("LeftButton")
                   and not m:IsMouseOver()
                   and not (flyoutToggle and flyoutToggle:IsMouseOver()) then
                    m:Hide()
                end
            end)
        end)
        flyoutPanel:HookScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)
    end
end

-- Build the flyout contents once. Buttons are reparented into the grid
-- and stay there permanently. Only rebuilds when the button list changes
-- (new addon loaded, button ungrouped, etc).
local function BuildFlyoutContents()
    EnsureFlyoutPanel()
    LayoutFlyoutButtons()
    _flyoutBuilt = true
end

-- Force a rebuild on next show (called when button list changes)
local function InvalidateFlyout()
    _flyoutBuilt = false
end

-- Profile-swap refresh: re-show buttons in the flyout and invalidate
-- so the next open rebuilds with new settings. Also re-asserts alpha
-- on buttons that may have been hidden by re-initialization.
_G._EMIN_RefreshFlyout = function()
    InvalidateFlyout()
    if flyoutPanel and flyoutPanel:IsShown() then
        BuildFlyoutContents()
    end
    -- Re-assert alpha on buttons in the flyout (profile swap may have
    -- re-hidden them via HideMinimapChild during re-init)
    for _, btn in ipairs(cachedAddonButtons) do
        if btn:GetParent() == flyoutPanel then
            btn:SetAlpha(1)
            btn:Show()
        end
    end
end

local function ShowFlyoutPanel()
    EnsureFlyoutPanel()
    -- Re-anchor per Grow Tooltip/Popup on every open (the setting or Auto's
    -- underlying row position can change between opens). Left/right keep the
    -- toggle's bottom edge; up/down keep its left edge. 2px gap.
    local dir = EBS._Grow.Dir()
    flyoutPanel:ClearAllPoints()
    if dir == "right" then
        flyoutPanel:SetPoint("BOTTOMLEFT", flyoutToggle, "BOTTOMRIGHT", 2, 0)
    elseif dir == "up" then
        flyoutPanel:SetPoint("BOTTOMLEFT", flyoutToggle, "TOPLEFT", 0, 2)
    elseif dir == "down" then
        flyoutPanel:SetPoint("TOPLEFT", flyoutToggle, "BOTTOMLEFT", 0, -2)
    else
        flyoutPanel:SetPoint("BOTTOMRIGHT", flyoutToggle, "BOTTOMLEFT", -2, 0)
    end
    -- Show the panel BEFORE layout so the Show hook on addon buttons
    -- sees flyoutPanel:IsShown() == true and skips the alpha-zero path.
    flyoutPanel:Show()
    if not _flyoutBuilt then
        BuildFlyoutContents()
    end
end

local function HideFlyoutPanel()
    if flyoutPanel then
        flyoutPanel:Hide()
        -- Do NOT restore buttons or wipe saved parents.
        -- Buttons stay parented to the flyout panel permanently.
    end
end

local function ToggleFlyoutPanel()
    if flyoutPanel and flyoutPanel:IsShown() then
        HideFlyoutPanel()
    else
        ShowFlyoutPanel()
    end
end

local function GetInteractableBtnSize()
    local mp = EBS.db and EBS.db.profile.minimap
    return mp and mp.interactableBtnSize or 22
end

-- Button/element row modes, named by the MAP corner the row starts from plus
-- the direction it grows. Vertical growth hugs the OUTSIDE of the left/right
-- edge (blUp = left edge from the bottom corner upward -- the original button
-- row); horizontal growth runs above/below the map. point/rel = per-button
-- anchor (its point -> map point), dirX/dirY = growth vector, awayX/awayY =
-- Distance from Map push. Rows place buttons with a running cursor in snapped
-- physical-pixel steps (see PlaceRowButton/PlaceElement), keeping icons flush
-- at 0 spacing and every gap identical.
local BTN_ROW_MODES = {
    -- Left edge (vertical)
    blUp    = { point = "BOTTOMRIGHT", rel = "BOTTOMLEFT",  dirX = 0,  dirY = 1,  awayX = -1, awayY = 0 },
    tlDown  = { point = "TOPRIGHT",    rel = "TOPLEFT",     dirX = 0,  dirY = -1, awayX = -1, awayY = 0 },
    -- Right edge (vertical)
    brUp    = { point = "BOTTOMLEFT",  rel = "BOTTOMRIGHT", dirX = 0,  dirY = 1,  awayX = 1,  awayY = 0 },
    trDown  = { point = "TOPLEFT",     rel = "TOPRIGHT",    dirX = 0,  dirY = -1, awayX = 1,  awayY = 0 },
    -- Above the map (horizontal)
    tlRight = { point = "BOTTOMLEFT",  rel = "TOPLEFT",     dirX = 1,  dirY = 0,  awayX = 0,  awayY = 1 },
    trLeft  = { point = "BOTTOMRIGHT", rel = "TOPRIGHT",    dirX = -1, dirY = 0,  awayX = 0,  awayY = 1 },
    -- Below the map (horizontal)
    blRight = { point = "TOPLEFT",     rel = "BOTTOMLEFT",  dirX = 1,  dirY = 0,  awayX = 0,  awayY = -1 },
    brLeft  = { point = "TOPRIGHT",    rel = "BOTTOMRIGHT", dirX = -1, dirY = 0,  awayX = 0,  awayY = -1 },
}

local function GetBtnRowMode(mp)
    return BTN_ROW_MODES[mp and mp.btnRowPosition or "blUp"] or BTN_ROW_MODES.blUp
end

-- Blizzard element row (tracking, calendar, mail, crafting) -- same mode
-- table; square shape only (the circle layout wraps around the clock).
local function GetElementRowMode(mp)
    return BTN_ROW_MODES[mp and mp.elementRowPosition or "tlDown"] or BTN_ROW_MODES.tlDown
end

-- Distance from Map push for a row: left/right rows move horizontally,
-- above/below rows vertically. Icon Spacing is applied per link at placement,
-- where the row cursor runs in snapped physical-pixel steps.
local function GetRowBase(mode, distance)
    local d = distance or 0
    return d * mode.awayX, d * mode.awayY
end

-- Scale for the custom tooltips shown by the unique minimap buttons (Great
-- Vault, friends, calendar, mail, tracking, crafting, flyout toggle, portals).
local function GetCustomTooltipScale()
    local mp = EBS.db and EBS.db.profile.minimap
    return mp and mp.customTooltipScale or 1.0
end

local function CreateFlyoutToggle()
    if flyoutToggle then
        -- Re-apply the current accent to the existing textures so a later
        -- ApplyAll (e.g. at PLAYER_ENTERING_WORLD, after EllesmereUI's theme
        -- resolution has mutated ELLESMERE_GREEN) picks up the right color.
        local EG2 = EllesmereUI.ELLESMERE_GREEN
        if flyoutToggle._norm   then flyoutToggle._norm:SetVertexColor(EG2.r, EG2.g, EG2.b, 1)   end
        if flyoutToggle._pushed then flyoutToggle._pushed:SetVertexColor(EG2.r, EG2.g, EG2.b, 1) end
        if flyoutToggle._hl     then flyoutToggle._hl:SetVertexColor(EG2.r, EG2.g, EG2.b, 1)     end
        return flyoutToggle
    end

    local btn = CreateFrame("Button", nil, Minimap)
    local iconSize = GetInteractableBtnSize()
    btn:SetSize(iconSize, iconSize)
    btn:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMLEFT", 0, 0)
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 10)

    local norm = btn:CreateTexture(nil, "ARTWORK")
    norm:SetAllPoints()
    norm:SetAtlas("Map-Filter-Button")
    norm:SetDesaturated(true)
    norm:SetVertexColor(EG.r, EG.g, EG.b, 1)
    btn:SetNormalTexture(norm)
    btn._norm = norm

    local pushed = btn:CreateTexture(nil, "ARTWORK")
    pushed:SetAllPoints()
    pushed:SetAtlas("Map-Filter-Button-down")
    pushed:SetDesaturated(true)
    pushed:SetVertexColor(EG.r, EG.g, EG.b, 1)
    btn:SetPushedTexture(pushed)
    btn._pushed = pushed

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetAtlas("Map-Filter-Button")
    hl:SetDesaturated(true)
    hl:SetVertexColor(EG.r, EG.g, EG.b, 1)
    hl:SetAlpha(0.3)
    btn:SetHighlightTexture(hl)
    btn._hl = hl

    -- Keep the three textures in sync with the accent color.
    -- Vertex alpha stays at 1; the highlight's SetAlpha(0.3) still applies
    -- on top since the two multiply.
    EllesmereUI.RegAccent({ type = "vertex", obj = norm })
    EllesmereUI.RegAccent({ type = "vertex", obj = pushed })
    EllesmereUI.RegAccent({ type = "vertex", obj = hl })

    -- Black background to match indicator icons
    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)
    btn._bg = bg

    btn:SetScript("OnClick", function(self)
        if GetFFD(self).freeMoveJustDragged then return end
        -- Opening the grid replaces the label tooltip (same as M+ Portals)
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip(true) end
        ToggleFlyoutPanel()
    end)
    btn:SetScript("OnEnter", function(self)
        if flyoutPanel and flyoutPanel:IsShown() then return end
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Addon Buttons", { anchor = EBS._Grow.TT(), scale = GetCustomTooltipScale() })
        end
    end)
    btn:SetScript("OnLeave", function(self)
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)

    -- Safety: ensure mouse stays enabled. Some Blizzard code or addon hooks
    -- on minimap children can disable mouse input. Re-assert on every Show.
    btn:HookScript("OnShow", function(self)
        if not self:IsMouseEnabled() then
            self:EnableMouse(true)
        end
    end)

    flyoutToggle = btn
    flyoutOwnedFrames[btn] = true
    return btn
end

local coordFrame, coordTicker
local clockFrame, clockTicker, clockBg
local locationFrame, locationBg
local fpsBg
local diffTextFrame

local function GetMinimapFont()
    local path = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("minimap") or STANDARD_TEXT_FONT
    local flag = EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("minimap") or "OUTLINE, SLUG"
    return path, flag
end

local function ApplyMinimapFont(fs, size)
    local path, flag = GetMinimapFont()
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, EllesmereUI.GetFontUseShadow and EllesmereUI.GetFontUseShadow("minimap")) end
    fs:SetFont(path, size, flag)
end

-- Description-text colour for the minimap texts (clock AM/PM, the "fps"/"ms"
-- suffixes): the custom fpsColor swatch or the live accent. The dynamic
-- values themselves stay white. Returns r, g, b plus the escape-code hex.
local function GetDescColor(mp)
    local r, g, b
    if mp and mp.fpsUseAccent then
        r, g, b = EG.r, EG.g, EG.b
    else
        local c = mp and mp.fpsColor
        if c then r, g, b = c.r or 1, c.g or 1, c.b or 1 else r, g, b = 1, 1, 1 end
    end
    return r, g, b, format("%02x%02x%02x",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Cache clock CVars so we don't read them every second
local cachedUse24h, cachedUseLocal
local function RefreshClockCVars()
    cachedUse24h = GetCVar("timeMgrUseMilitaryTime") == "1"
    cachedUseLocal = GetCVar("timeMgrUseLocalTime") == "1"
end

local function UpdateClock()
    if not clockFrame then return end
    if cachedUse24h == nil then RefreshClockCVars() end
    local h, m
    if cachedUseLocal then
        local t = date("*t")
        h, m = t.hour, t.min
    else
        h, m = GetGameTime()
    end
    if cachedUse24h then
        clockFrame:SetText(format("%02d:%02d", h, m))
    else
        -- Unpadded hour in 12-hour mode (1:03, not 01:03), matching the
        -- Blizzard clock. 24-hour mode keeps the pad, also matching Blizzard.
        -- The AM/PM suffix only takes the description colour when opted in
        -- (Accented Text > Clock); digits always stay white.
        local ampm = h >= 12 and "PM" or "AM"
        h = h % 12
        if h == 0 then h = 12 end
        local mp = EBS.db and EBS.db.profile.minimap
        if mp and mp.fpsColorClockAMPM then
            local _, _, _, hex = GetDescColor(mp)
            clockFrame:SetFormattedText("%d:%02d |cff%s%s|r", h, m, hex, ampm)
        else
            clockFrame:SetFormattedText("%d:%02d %s", h, m, ampm)
        end
    end
end

-- Coordinates mode/position with legacy fallback: data imported from a
-- pre-dropdown export carries only coordsBelow (true = always-on below the
-- map; otherwise hover-only at the top left).
local function GetCoordsModePos(mp)
    if not mp then return "always", "topLeft" end
    local mode = mp.coordsMode or (mp.coordsBelow and "always") or "always"
    local pos = mp.coordsPosition or (mp.coordsBelow and "belowMap") or "topLeft"
    return mode, pos
end

-- Clock/location display mode with legacy fallback: pre-dropdown data carries
-- the clockInside/zoneInside toggles (clockInside defaulted ON, zoneInside
-- defaulted OFF) plus the removed Show Blizzard Elements Zone/Clock
-- checkboxes (showClock == false / hideZoneText == true meant hidden).
local function GetElementModes(mp)
    if not mp then return "inside", "inside" end
    local clockMode = mp.clockMode
    if clockMode == nil then
        if mp.showClock == false then
            clockMode = "none"
        else
            clockMode = (mp.clockInside == false) and "edge" or "inside"
        end
    end
    local locationMode = mp.locationMode
    if locationMode == nil then
        if mp.hideZoneText == true then
            locationMode = "none"
        else
            locationMode = mp.zoneInside and "inside" or "edge"
        end
    end
    return clockMode, locationMode
end

-- position key -> element point, minimap relPoint, base X, base Y (inside
-- flavor). Shared by the coordinates, clock, and zone text elements.
local MAP_POS_ANCHORS = {
    belowMap    = { "TOP",         "BOTTOM",       0, -5 },
    aboveMap    = { "BOTTOM",      "TOP",          0,  5 },
    topLeft     = { "TOPLEFT",     "TOPLEFT",      4, -4 },
    top         = { "TOP",         "TOP",          0, -4 },
    topRight    = { "TOPRIGHT",    "TOPRIGHT",    -4, -4 },
    left        = { "LEFT",        "LEFT",         4,  0 },
    right       = { "RIGHT",       "RIGHT",       -4,  0 },
    bottomLeft  = { "BOTTOMLEFT",  "BOTTOMLEFT",   4,  4 },
    bottom      = { "BOTTOM",      "BOTTOM",       0,  4 },
    bottomRight = { "BOTTOMRIGHT", "BOTTOMRIGHT", -4,  4 },
}

-- Anchor for the clock/zone text bar. Inside style keeps the 4px map inset;
-- edge style flips the inset so the box straddles the map border (7px out on
-- square maps, 3px in on circles -- the round mask curves away from the frame
-- edge). Above/Below Map float fully outside in both styles.
local function ResolveElementAnchor(pos, style, isCircle)
    local a = MAP_POS_ANCHORS[pos] or MAP_POS_ANCHORS.top
    local x, y = a[3], a[4]
    if style == "edge" and pos ~= "belowMap" and pos ~= "aboveMap" then
        if x ~= 0 then x = isCircle and (x > 0 and 3 or -3) or (x > 0 and -7 or 7) end
        if y ~= 0 then y = isCircle and (y > 0 and 3 or -3) or (y > 0 and -7 or 7) end
    end
    return a[1], a[2], x, y
end

-- Cache coord format string so we don't rebuild it every 0.5s
local cachedCoordPrec, cachedCoordFmt
local function UpdateCoords()
    if not coordFrame then return end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then coordFrame:SetText(""); return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then coordFrame:SetText(""); return end
    local x, y = pos:GetXY()
    local p = EBS.db and EBS.db.profile.minimap
    local prec = p and p.coordPrecision or 1
    if prec ~= cachedCoordPrec then
        cachedCoordPrec = prec
        cachedCoordFmt = format("%%.%df, %%.%df", prec, prec)
    end
    coordFrame:SetText(format(cachedCoordFmt, x * 100, y * 100))
end

-- Reactive zone coloring: tint by the current zone's PvP ruleset (friendly
-- green, hostile/arena/combat red, sanctuary blue, contested/unknown yellow).
local function GetZoneReactionColor()
    local pvpType = C_PvP and C_PvP.GetZonePVPInfo and C_PvP.GetZonePVPInfo()
    if pvpType == "friendly" then
        return 0.05, 0.85, 0.03
    elseif pvpType == "sanctuary" then
        return 0.035, 0.58, 0.84
    elseif pvpType == "arena" or pvpType == "hostile" or pvpType == "combat" then
        return 0.84, 0.03, 0.03
    end
    return 0.9, 0.85, 0.05
end

local lastLocationText
local function UpdateLocation()
    if not locationFrame then return end
    if InCombatLockdown() then return end
    -- Color before the text dedup below so a settings toggle or a ruleset
    -- change within the same zone name still repaints.
    local mp = EBS.db and EBS.db.profile.minimap
    if mp and mp.zoneReactiveColor then
        local r, g, b = GetZoneReactionColor()
        locationFrame:SetTextColor(r, g, b, 0.9)
    else
        locationFrame:SetTextColor(1, 1, 1, 0.9)
    end
    local text
    if mp and mp.zoneShowSubZone then
        local sub = GetSubZoneText()
        text = (sub and sub ~= "") and sub or (GetZoneText() or "")
    else
        text = GetZoneText() or ""
    end
    if text == lastLocationText then return end
    lastLocationText = text
    locationFrame:SetText(text)
    if locationBg then
        local tw = locationFrame:GetStringWidth() or 0
        locationBg:SetSize(tw + 20, 18)
    end
end

-------------------------------------------------------------------------------
--  Free Move Button System
--  When freeMoveBtns is enabled, shift+click any minimap-area button to drag
--  it. Positions are stored as offsets in DB.profile.minimap.btnPositions
--  keyed by a stable identifier string.
-------------------------------------------------------------------------------
local function GetBtnPosKey(frame)
    -- Custom indicator buttons store their key directly
    if frame._indicatorKey then return frame._indicatorKey end
    local name = frame:GetName()
    if name then return name end
    if frame == flyoutToggle then return "_flyoutToggle" end
    return nil
end

local function GetBtnOffset(key)
    local mp = EBS.db and EBS.db.profile.minimap
    if not mp or not mp.freeMoveBtns or not mp.btnPositions then return 0, 0 end
    local pos = mp.btnPositions[key]
    if not pos then return 0, 0 end
    return pos.x or 0, pos.y or 0
end

local function SaveBtnOffset(key, x, y)
    local mp = EBS.db and EBS.db.profile.minimap
    if not mp then return end
    if not mp.btnPositions then mp.btnPositions = {} end
    mp.btnPositions[key] = { x = x, y = y }
end

local _freeMoveHooked = {}  -- [frame] = true, one-time hook guard

local function EnableFreeMove(frame)
    if not frame or _freeMoveHooked[frame] then return end
    _freeMoveHooked[frame] = true

    local key = GetBtnPosKey(frame)
    if not key then return end

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Guard third-party buttons (LibDBIcon, etc.) that have their own OnClick.
    -- Wrap their handler so the drag flag blocks click-through.
    if not frame._indicatorKey and frame ~= flyoutToggle then
        local origClick = frame:GetScript("OnClick")
        if origClick then
            frame:SetScript("OnClick", function(self, ...)
                if GetFFD(self).freeMoveJustDragged then return end
                origClick(self, ...)
            end)
        end
    end

    local isDragging = false
    local startX, startY, origOffX, origOffY

    local origPoint, origRel, origRelPoint, origX, origY

    local function FreeMoveOnUpdate(self)
        if not IsMouseButtonDown("LeftButton") then
            isDragging = false
            self:SetScript("OnUpdate", nil)
            -- Clear the drag flag on the next frame (set in OnMouseDown)
            C_Timer.After(0, function() GetFFD(self).freeMoveJustDragged = nil end)
            -- Save final offset and re-layout once on release
            local es = self:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / es, cy / es
            local dx, dy = cx - startX, cy - startY
            SaveBtnOffset(key, origOffX + dx, origOffY + dy)
            if ApplyMinimap then ApplyMinimap() end
            return
        end
        -- Move the button directly during drag (no full relayout)
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / es, cy / es
        local dx, dy = cx - startX, cy - startY
        if origPoint then
            self:ClearAllPoints()
            self:SetPoint(origPoint, origRel, origRelPoint, origX + origOffX + dx, origY + origOffY + dy)
        end
    end

    frame:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if not IsShiftKeyDown() then return end
        local mp = EBS.db and EBS.db.profile.minimap
        if not mp or not mp.freeMoveBtns then return end
        isDragging = true
        -- Block click actions immediately so OnClick can never fire during a drag,
        -- regardless of WoW's event ordering. Cleared on the frame after release.
        GetFFD(self).freeMoveJustDragged = true
        local es = self:GetEffectiveScale()
        startX, startY = GetCursorPosition()
        startX, startY = startX / es, startY / es
        origOffX, origOffY = GetBtnOffset(key)
        -- Snapshot the button's current anchor (before any offset)
        origPoint, origRel, origRelPoint, origX, origY = self:GetPoint(1)
        -- Subtract current offset to get the base anchor position
        origX = (origX or 0) - origOffX
        origY = (origY or 0) - origOffY
        self:SetScript("OnUpdate", FreeMoveOnUpdate)
    end)

    frame:HookScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not isDragging then return end
        isDragging = false
        self:SetScript("OnUpdate", nil)
        local es = self:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / es, cy / es
        local dx, dy = cx - startX, cy - startY
        SaveBtnOffset(key, origOffX + dx, origOffY + dy)
        -- Clear the drag flag on the next frame (set in OnMouseDown)
        C_Timer.After(0, function() GetFFD(frame).freeMoveJustDragged = nil end)
        if ApplyMinimap then ApplyMinimap() end
    end)

end

-- Apply saved offset to a button (called during layout)
local function ApplyBtnOffset(frame)
    if not frame then return end
    local key = GetBtnPosKey(frame)
    if not key then return end
    local ox, oy = GetBtnOffset(key)
    if ox == 0 and oy == 0 then return end
    local p1, rel, p2, x, y = frame:GetPoint(1)
    if p1 then
        frame:SetPoint(p1, rel, p2, (x or 0) + ox, (y or 0) + oy)
    end
end

local function SaveZoomLevel()
    local p = EBS.db and EBS.db.profile.minimap
    if not p then return end
    p.savedZoom = Minimap:GetZoom()
end

-- Blizzard structural frames that should NOT go into the flyout
local flyoutBlacklist = {
    MinimapZoomIn    = true,
    MinimapZoomOut   = true,
    MinimapBackdrop  = true,
    GameTimeFrame    = true,
    -- Core Blizzard feature button (expansion/landing page); keep it on the
    -- minimap surface instead of sweeping it into the addon-button flyout.
    ExpansionLandingPageMinimapButton = true,
}

-- Persistently hide a minimap button via Show hook
local addonButtonHooks = {}

local function HideMinimapChild(btn)
    _suppressVisTrack = true
    btn:Hide()
    btn:SetAlpha(0)
    _suppressVisTrack = false
    if not addonButtonHooks[btn] then
        -- Track addon-intended visibility via Show/Hide hooks
        hooksecurefunc(btn, "Show", function(self)
            if not _suppressVisTrack then
                -- Don't track addon Show() while flyout is open: the button
                -- is already visible in our grid, and tracking would let a
                -- subsequent Hide() mark it as unwanted.
                if not (flyoutPanel and flyoutPanel:IsShown()) then
                    _addonVisible[self] = true
                end
            end
            if InCombatLockdown() then return end
            -- Never zero alpha while the flyout is open -- addon buttons
            -- are visible in the grid and periodic Show() calls from
            -- LibDBIcon/addons would make them disappear mid-view.
            if flyoutPanel and flyoutPanel:IsShown() then return end
            -- Allow ungrouped buttons to stay visible
            if IsUngrouped(self) then return end
            local mp = EBS.db and EBS.db.profile.minimap
            if mp and mp.enabled and not flyoutOwnedFrames[self] then
                self:SetAlpha(0)
            end
        end)
        hooksecurefunc(btn, "Hide", function(self)
            if not _suppressVisTrack then
                -- Freeze visibility tracking while the flyout is open.
                -- LibDBIcon and addons periodically call Hide() during
                -- internal refreshes; letting that mark _addonVisible=false
                -- causes buttons to vanish from the open flyout grid.
                if flyoutPanel and flyoutPanel:IsShown() then
                    self:Show()
                    return
                end
                _addonVisible[self] = false
            end
        end)
        addonButtonHooks[btn] = true
    end
end

local function ShowMinimapChild(btn)
    _suppressVisTrack = true
    btn:SetAlpha(1)
    btn:EnableMouse(true)
    btn:Show()
    _suppressVisTrack = false
end

-- Pin/POI frame patterns to exclude from the flyout (HandyNotes, TomTom, etc.)
local flyoutPinPatterns = {
    "^HandyNotes",
    "^TomTom",
    "^HereBeDragons",
    "^Questie",
    "^GatherMate",
    "^pin",
    "^Pin",
}

local function IsPinFrame(name)
    if not name then return false end
    for _, pat in ipairs(flyoutPinPatterns) do
        if name:match(pat) then return true end
    end
    return false
end

-- Third-party addon buttons show a game tooltip from their OnEnter: LibDBIcon
-- buttons use the lib's own LibDBIconTooltip frame (anchored by screen half,
-- which is what put tooltips BELOW the icons), everything else the global
-- GameTooltip. Post-hook each collected button so whichever tooltip the
-- button owns follows Grow Tooltip/Popup: by the time the hook runs, the
-- addon's handler has already owned, anchored, and shown it, so re-pointing
-- here wins. Namespace-scoped (200-local cap).
do
    local hooked = {}
    local function repoint(tt, btn)
        if tt and tt:IsShown() and tt:GetOwner() == btn then
            local gpt = EBS._Grow.edge[EBS._Grow.Dir()] or EBS._Grow.edge.left
            tt:ClearAllPoints()
            tt:SetPoint(gpt[1], btn, gpt[2], gpt[3], gpt[4])
        end
    end
    function EBS._HookAddonBtnTT(btn)
        if hooked[btn] then return end
        hooked[btn] = true
        btn:HookScript("OnEnter", function(self)
            repoint(_G.GameTooltip, self)
            repoint(_G.LibDBIconTooltip, self)
        end)
    end
end

-- Gather all minimap buttons (Blizzard + addon) into cachedAddonButtons
local function GatherMinimapButtons()
    wipe(cachedAddonButtons)
    if not Minimap then return end
    -- Also scan flyout panel children (buttons we already reparented)
    local sources = { Minimap }
    if flyoutPanel then sources[2] = flyoutPanel end
    for _, source in ipairs(sources) do
        for _, child in ipairs({ source:GetChildren() }) do
            if not flyoutOwnedFrames[child] then
                local name = child:GetName()
                if flyoutBlacklist[name] then
                    -- skip
                elseif IsPinFrame(name) then
                    -- skip pin/POI frames
                elseif child:IsObjectType("Button") and name
                    and not name:match("%d+$") then
                    local w = child:GetWidth() or 0
                    -- Width gate only for first discovery; once a button is
                    -- tracked in _addonVisible it is always re-collected so
                    -- our own SetSize (e.g. slider < 20) can't permanently
                    -- drop it from the list.
                    if w >= 20 or _addonVisible[child] ~= nil then
                        if _addonVisible[child] == nil then
                            _addonVisible[child] = child:IsShown()
                        end
                        cachedAddonButtons[#cachedAddonButtons + 1] = child
                        EBS._HookAddonBtnTT(child)
                    end
                elseif not child:IsObjectType("Button") and name and name:match("^LibDBIcon10_") then
                    if _addonVisible[child] == nil then
                        _addonVisible[child] = child:IsShown()
                    end
                    cachedAddonButtons[#cachedAddonButtons + 1] = child
                    EBS._HookAddonBtnTT(child)
                end
            end
        end
    end
end

-- Expose for options UI
_G._EBS_CachedAddonButtons = cachedAddonButtons
_G._EBS_AddonVisible = _addonVisible

-- Hide all collected minimap buttons from the map surface
-- Ungrouped buttons are left alone (positioned by LayoutIndicatorFrames)
-- Buttons currently displayed inside the open flyout are also skipped --
-- HideMinimapChild uses _suppressVisTrack which bypasses the force-show
-- protection in the Hide hook, so calling it on flyout buttons while the
-- panel is visible would silently zero their alpha with no recovery.
local function HideAllMinimapButtons()
    GatherMinimapButtons()
    local flyoutOpen = flyoutPanel and flyoutPanel:IsShown()
    for _, btn in ipairs(cachedAddonButtons) do
        if not IsUngrouped(btn) then
            if flyoutOpen and btn:GetParent() == flyoutPanel then
                -- Button is visible in the flyout grid; leave it alone
            else
                HideMinimapChild(btn)
            end
        end
    end
end

local function ShowAllMinimapButtons()
    for _, btn in ipairs(cachedAddonButtons) do
        ShowMinimapChild(btn)
    end
    wipe(cachedAddonButtons)
end

-------------------------------------------------------------------------------
--  Minimap Indicator Buttons (custom replacements for Blizzard's reparented frames)
--  Each is our own Button with a black bg, icon texture, and simple click handler.
--  No Blizzard frame reparenting = no taint, no layout fights.
-------------------------------------------------------------------------------
local indicatorBg = nil  -- combined bg strip for square mode (legacy, still used when free move is off)
local _customIndicators = {}  -- { tracking, calendar, mail, crafting }

-- Native atlas aspect ratios (width / height) and per-icon scale multipliers
local INDICATOR_ATLAS_RATIO = {
    ["UI-HUD-Minimap-Tracking-Up"]           = 15 / 14,
    ["UI-HUD-Minimap-Tracking-Mouseover"]    = 15 / 14,
    ["UI-HUD-Minimap-Tracking-Down"]         = 16 / 15,
    ["UI-HUD-Minimap-Mail-Up"]               = 19.5 / 15,
    ["UI-HUD-Minimap-Mail-Mouseover"]        = 19.5 / 15,
    ["UI-HUD-Minimap-CraftingOrder-Up-2x"]   = 17 / 16,
    ["UI-HUD-Minimap-CraftingOrder-Over-2x"] = 17 / 16,
    ["UI-HUD-Minimap-CraftingOrder-Down-2x"] = 17 / 16,
}
local INDICATOR_ATLAS_SCALE = {}
-- Calendar atlases: all 31 days share the same ratio/scale
for day = 1, 31 do
    local prefix = "UI-HUD-Calendar-" .. day
    INDICATOR_ATLAS_RATIO[prefix .. "-Up"]        = 21 / 19
    INDICATOR_ATLAS_RATIO[prefix .. "-Mouseover"] = 21 / 19
    INDICATOR_ATLAS_RATIO[prefix .. "-Down"]      = 21 / 19
    INDICATOR_ATLAS_SCALE[prefix .. "-Up"]        = 1.25
    INDICATOR_ATLAS_SCALE[prefix .. "-Mouseover"] = 1.25
    INDICATOR_ATLAS_SCALE[prefix .. "-Down"]      = 1.25
end
-- Per-icon pixel offset from center { x, y }
local INDICATOR_ATLAS_OFFSET = {
    _gameTime = { 2, -2 },
    _mail     = { 1, -1 },
}

local function CreateIndicatorBtn(name, parent, upAtlas, overAtlas, downAtlas, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(GetInteractableBtnSize(), GetInteractableBtnSize())
    btn:SetFrameLevel(parent:GetFrameLevel() + 20)
    btn:EnableMouse(true)

    -- Black background
    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)
    btn._bg = bg

    -- Icon: sized to preserve atlas aspect ratio within the button
    local icon = btn:CreateTexture(nil, "ARTWORK")
    local inset = 3
    local ratio = upAtlas and INDICATOR_ATLAS_RATIO[upAtlas]
    if ratio then
        local btnSz = GetInteractableBtnSize()
        local avail = btnSz - inset * 2
        local scale = INDICATOR_ATLAS_SCALE[upAtlas] or 1
        local iconW, iconH
        if ratio >= 1 then
            iconW = avail * scale
            iconH = (avail / ratio) * scale
        else
            iconH = avail * scale
            iconW = (avail * ratio) * scale
        end
        icon:SetSize(iconW, iconH)
        local off = INDICATOR_ATLAS_OFFSET[name]
        icon:SetPoint("CENTER", btn, "CENTER", off and off[1] or 0, off and off[2] or 0)
    else
        icon:SetPoint("TOPLEFT", btn, "TOPLEFT", inset, -inset)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -inset, inset)
    end
    if upAtlas then icon:SetAtlas(upAtlas) end
    btn._icon = icon
    btn._upAtlas = upAtlas
    btn._overAtlas = overAtlas
    btn._downAtlas = downAtlas
    btn._indicatorKey = name

    -- Hover/push states
    btn:SetScript("OnEnter", function(self)
        if self._overAtlas and self._icon then self._icon:SetAtlas(self._overAtlas) end
    end)
    btn:SetScript("OnLeave", function(self)
        if self._upAtlas and self._icon then self._icon:SetAtlas(self._upAtlas) end
    end)
    btn:SetScript("OnMouseDown", function(self)
        if self._downAtlas and self._icon then self._icon:SetAtlas(self._downAtlas) end
    end)
    btn:SetScript("OnMouseUp", function(self)
        local over = self:IsMouseOver()
        local atlas = over and self._overAtlas or self._upAtlas
        if atlas and self._icon then self._icon:SetAtlas(atlas) end
    end)

    if onClick then
        btn:SetScript("OnClick", function(self)
            if GetFFD(self).freeMoveJustDragged then return end
            onClick(self)
        end)
    end

    return btn
end

-- Great Vault button. Lives at the top of the ungrouped-button stack above
-- the flyout toggle. Single "whole" atlas scaled to fit the button.
local _greatVaultBtn = nil
local GREAT_VAULT_WHOLE_ATLAS = "greatVault-whole-normal"

local function RegisterVaultEscClose()
    local wrf = _G.WeeklyRewardsFrame
    if not wrf or not EllesmereUI.RegisterEscapeClose then return end
    EllesmereUI.RegisterEscapeClose(wrf)
end

local function ColorizeVaultText(text, r, g, b)
    r = math.floor(math.max(0, math.min(1, r or 1)) * 255 + 0.5)
    g = math.floor(math.max(0, math.min(1, g or 1)) * 255 + 0.5)
    b = math.floor(math.max(0, math.min(1, b or 1)) * 255 + 0.5)
    return ("|cff%02x%02x%02x%s|r"):format(r, g, b, tostring(text or ""))
end

local function GetOrderedWeeklyActivities(activityType)
    if not C_WeeklyRewards or not C_WeeklyRewards.GetActivities then return nil end

    local activities = C_WeeklyRewards.GetActivities(activityType)
    if type(activities) ~= "table" or #activities == 0 then
        return nil
    end

    local ordered = {}
    for i = 1, #activities do
        ordered[i] = activities[i]
    end

    table.sort(ordered, function(a, b)
        local aIndex = a and a.index or 0
        local bIndex = b and b.index or 0
        if aIndex == bIndex then
            return (a and a.threshold or 0) < (b and b.threshold or 0)
        end
        return aIndex < bIndex
    end)

    return ordered
end

local function GetVaultTokenColor(state)
    if state == "done" then
        return 0.176, 0.796, 0.349
    elseif state == "partial" then
        return 0.812, 0.592, 0.212
    end

    return 0.58, 0.58, 0.58
end

local function FormatVaultToken(text, state)
    local r, g, b = GetVaultTokenColor(state)
    return ColorizeVaultText(text, r, g, b)
end

-- Build vault row data: { label, isRaid, tokens = { {text, state}, ... } }
local function BuildVaultRowData(label, activityType, isRaid)
    local activities = GetOrderedWeeklyActivities(activityType)
    local tokens = {}
    for i = 1, 3 do
        local info = activities and activities[i]
        if not info then
            tokens[i] = { text = "-", state = "empty" }
        else
            local progress = math.max(0, tonumber(info.progress) or 0)
            local threshold = math.max(0, tonumber(info.threshold) or 0)
            local level = math.max(0, tonumber(info.level) or 0)
            if threshold <= 0 then
                tokens[i] = { text = "-", state = "empty" }
            elseif progress >= threshold then
                if isRaid then
                    tokens[i] = { text = ("%d/%d"):format(progress, threshold), state = "done" }
                elseif level > 0 then
                    tokens[i] = { text = "+" .. level, state = "done" }
                else
                    tokens[i] = { text = ("%d/%d"):format(progress, threshold), state = "done" }
                end
            else
                tokens[i] = { text = ("%d/%d"):format(progress, threshold), state = progress > 0 and "partial" or "empty" }
            end
        end
    end
    return { label = label, tokens = tokens }
end

-- Custom multi-column vault tooltip (pixel-aligned columns via FontStrings)
local _vaultTT
local _vaultTTRows = {}  -- [row][col] = FontString
local VAULT_COL_GAP = 8
local VAULT_ROW_H = 14
local VAULT_PAD = 6

local function GetVaultTooltip()
    if _vaultTT then return _vaultTT end
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeSize = 1 })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.90)
    f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:Hide()

    -- Fade animations (matches ShowWidgetTooltip/HideWidgetTooltip)
    local fadeInAG = f:CreateAnimationGroup()
    local fadeIn = fadeInAG:CreateAnimation("Alpha")
    fadeIn:SetDuration(0.25); fadeIn:SetSmoothing("OUT")
    fadeInAG:SetScript("OnFinished", function() f:SetAlpha(1) end)
    f._fadeInAG = fadeInAG; f._fadeIn = fadeIn

    local fadeOutAG = f:CreateAnimationGroup()
    local fadeOut = fadeOutAG:CreateAnimation("Alpha")
    fadeOut:SetDuration(0.25); fadeOut:SetSmoothing("IN")
    fadeOutAG:SetScript("OnFinished", function() f:SetAlpha(0); f:Hide() end)
    f._fadeOutAG = fadeOutAG; f._fadeOut = fadeOut

    -- Title row (font set at show-time)
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 11, "")  -- placeholder, updated on show
    title:SetTextColor(0.80, 0.80, 0.80, 1)
    title:SetPoint("TOP", f, "TOP", 0, -VAULT_PAD)
    title:SetText(EllesmereUI.L("Great Vault"))
    f._title = title

    -- 3 data rows x 4 columns (label + 3 tokens)
    for row = 1, 3 do
        _vaultTTRows[row] = {}
        for col = 0, 3 do
            local fs = f:CreateFontString(nil, "OVERLAY")
            fs:SetFont("Fonts\\FRIZQT__.TTF", 11, "")  -- placeholder, updated on show
            fs:SetJustifyH("LEFT")
            _vaultTTRows[row][col] = fs
        end
    end

    _vaultTT = f
    return f
end

local function ShowVaultTooltip(anchor)
    local raidType = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Raid) or 3
    local dungeonType = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Activities) or 1
    local worldType = (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.World) or 6

    local rows = {
        BuildVaultRowData(EllesmereUI.L("Raids"), raidType, true),
        BuildVaultRowData(EllesmereUI.L("Mythic+"), dungeonType, false),
        BuildVaultRowData(EllesmereUI.L("World"), worldType, false),
    }

    local tt = GetVaultTooltip()
    -- Scale the whole tooltip to the user's Custom Tooltip Size (re-applied each show).
    tt:SetScale(GetCustomTooltipScale())

    -- Apply user's current font to all FontStrings
    local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("minimap")) or "Fonts\\FRIZQT__.TTF"
    local fontFlags = (EllesmereUI.GetFontOutlineFlag and EllesmereUI.GetFontOutlineFlag("minimap")) or ""
    tt._title:SetFont(fontPath, 11, fontFlags)
    for r = 1, 3 do
        _vaultTTRows[r][0]:SetFont(fontPath, 11, fontFlags)
        for c = 1, 3 do
            _vaultTTRows[r][c]:SetFont(fontPath, 10, fontFlags)
        end
    end

    -- Populate text and measure column widths
    local colWidths = { 0, 0, 0, 0 }
    for r = 1, 3 do
        local rd = rows[r]
        local labelFS = _vaultTTRows[r][0]
        labelFS:SetText(rd.label)
        labelFS:SetTextColor(0.812, 0.592, 0.212, 1)
        local w = labelFS:GetStringWidth() or 0
        if w > colWidths[1] then colWidths[1] = w end

        for c = 1, 3 do
            local tk = rd.tokens[c]
            local fs = _vaultTTRows[r][c]
            fs:SetText(tk.text)
            local tr, tg, tb = GetVaultTokenColor(tk.state)
            fs:SetTextColor(tr, tg, tb, 1)
            local tw = fs:GetStringWidth() or 0
            if tw > colWidths[c + 1] then colWidths[c + 1] = tw end
        end
    end

    -- Position columns at measured offsets
    local titleTop = VAULT_PAD + (tt._title:GetStringHeight() or 14) + 4
    local colX = { VAULT_PAD }
    for c = 2, 4 do
        colX[c] = colX[c - 1] + colWidths[c - 1] + VAULT_COL_GAP
    end
    local totalW = colX[4] + colWidths[4] + VAULT_PAD

    for r = 1, 3 do
        local y = -(titleTop + (r - 1) * VAULT_ROW_H)
        for c = 0, 3 do
            _vaultTTRows[r][c]:ClearAllPoints()
            _vaultTTRows[r][c]:SetPoint("TOPLEFT", tt, "TOPLEFT", colX[c + 1], y)
        end
    end

    local totalH = titleTop + 3 * VAULT_ROW_H + VAULT_PAD
    tt:SetSize(totalW, totalH)
    tt:ClearAllPoints()
    local gpt = EBS._Grow.center[EBS._Grow.Dir()] or EBS._Grow.center.left
    tt:SetPoint(gpt[1], anchor, gpt[2], gpt[3], gpt[4])

    -- Fade in
    tt._fadeOutAG:Stop()
    tt._fadeInAG:Stop()
    tt:SetAlpha(0)
    tt:Show()
    tt._fadeIn:SetFromAlpha(0)
    tt._fadeIn:SetToAlpha(1)
    tt._fadeInAG:Play()
end

local function HideVaultTooltip()
    if not _vaultTT or not _vaultTT:IsShown() then return end
    _vaultTT._fadeInAG:Stop()
    _vaultTT._fadeOutAG:Stop()
    _vaultTT._fadeOut:SetFromAlpha(_vaultTT:GetAlpha())
    _vaultTT._fadeOut:SetToAlpha(0)
    _vaultTT._fadeOutAG:Play()
end

local function ToggleGreatVault()
    local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    local Load     = (C_AddOns and C_AddOns.LoadAddOn)     or _G.LoadAddOn
    if Load and IsLoaded and not IsLoaded("Blizzard_WeeklyRewards") then
        Load("Blizzard_WeeklyRewards")
    end
    RegisterVaultEscClose()
    if WeeklyRewardsFrame then
        WeeklyRewardsFrame:SetShown(not WeeklyRewardsFrame:IsShown())
    end
end

local function SizeGreatVaultBtn(btn, showBg)
    local btnSz = GetInteractableBtnSize()
    btn:SetSize(btnSz, btnSz)
    if btn._bg then btn._bg:SetShown(showBg ~= false) end
    local inset = 3
    local avail = btnSz - inset * 2
    -- Whole is 105x108: height is the limiting dimension. Fit by height.
    local wholeH = avail
    local wholeW = wholeH * (105 / 108)
    btn._whole:SetSize(wholeW, wholeH)
    btn._whole:ClearAllPoints()
    btn._whole:SetPoint("CENTER", btn, "CENTER", 0, 0)
end

local function CreateGreatVaultBtn(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(GetInteractableBtnSize(), GetInteractableBtnSize())
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)
    btn:EnableMouse(true)

    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)
    btn._bg = bg

    local whole = btn:CreateTexture(nil, "ARTWORK")
    whole:SetAtlas(GREAT_VAULT_WHOLE_ATLAS)
    btn._whole = whole

    SizeGreatVaultBtn(btn)

    btn:SetScript("OnEnter", function(self)
        self._whole:SetVertexColor(1, 1, 1, 1)
        ShowVaultTooltip(self)
    end)
    btn:SetScript("OnLeave", function(self)
        self._whole:SetVertexColor(0.85, 0.85, 0.85, 1)
        HideVaultTooltip()
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._whole:SetVertexColor(0.7, 0.7, 0.7, 1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        local over = self:IsMouseOver()
        local v = over and 1 or 0.85
        self._whole:SetVertexColor(v, v, v, 1)
    end)
    btn:SetScript("OnClick", function(self)
        if GetFFD(self).freeMoveJustDragged then return end
        ToggleGreatVault()
    end)

    -- Resting tint matches OnLeave state
    whole:SetVertexColor(0.85, 0.85, 0.85, 1)

    btn._indicatorKey = "_greatVault"

    return btn
end

-------------------------------------------------------------------------------
-- M+ Portal button. Identical flyout as Chat sidebar but anchored to minimap.
-------------------------------------------------------------------------------
-- Built from the shared season list (EllesmereUI.SEASON_PORTALS) -- one
-- place to update per season.
local PORTAL_SPELLS, PORTAL_SHORT = {}, {}
for _, e in ipairs(EllesmereUI.SEASON_PORTALS) do
    PORTAL_SPELLS[#PORTAL_SPELLS + 1] = e.spellID
    PORTAL_SHORT[e.spellID] = e.short
end

local _portalBtn = nil
local _portalFlyout, _portalFlyoutBtns

local function RefreshMinimapPortalButtons()
    if not _portalFlyoutBtns then return end
    for _, btn in ipairs(_portalFlyoutBtns) do
        local spellID = btn.spellID
        local known = IsPlayerSpell(spellID)
        if btn._lastKnown ~= known then
            btn._lastKnown = known
            btn.icon:SetDesaturated(not known)
            btn.icon:SetAlpha(known and 1 or 0.4)
        end
        if known then
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
                btn.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
            else
                btn.cooldown:Clear()
            end
        else
            btn.cooldown:Clear()
        end
    end
end

local function CreateMinimapPortalFlyout()
    if _portalFlyout then return _portalFlyout end

    local BTN_SIZE = 32
    local SPACING = 1
    local PADDING = 2
    local COLS = 4
    local ROWS = math.ceil(#PORTAL_SPELLS / COLS)

    local portalW = PADDING * 2 + BTN_SIZE * COLS + SPACING * (COLS - 1)
    local flyH = PADDING * 2 + BTN_SIZE * ROWS + SPACING * (ROWS - 1)
    local HS_COUNT = 3
    local HS_H = math.floor((flyH - PADDING * 2 - SPACING * (HS_COUNT - 1)) / HS_COUNT)
    local hsX = PADDING + COLS * BTN_SIZE + (COLS - 1) * SPACING + SPACING
    local flyW = hsX + HS_H + PADDING

    local flyout = CreateFrame("Frame", "EUIMinimapPortalFlyout", UIParent)
    flyout:SetSize(flyW, flyH)
    flyout:SetFrameStrata("DIALOG")
    flyout:SetFrameLevel(100)
    flyout:SetClampedToScreen(true)
    flyout:Hide()

    local bg = flyout:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.04, 0.06, 0.95)

    local PP = EllesmereUI and EllesmereUI.PP
    if PP and PP.CreateBorder then
        PP.CreateBorder(flyout, 1, 1, 1, 0.06, 1, "OVERLAY", 7)
    end

    local guard = CreateFrame("Frame")
    guard:RegisterEvent("PLAYER_REGEN_DISABLED")
    guard:SetScript("OnEvent", function() flyout:Hide() end)

    _portalFlyoutBtns = {}
    for i, spellID in ipairs(PORTAL_SPELLS) do
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)

        local btn = CreateFrame("Button", "EUIMinimapPortal" .. i, flyout, "SecureActionButtonTemplate")
        btn:SetSize(BTN_SIZE, BTN_SIZE)
        btn:SetPoint("TOPLEFT", flyout, "TOPLEFT",
            PADDING + col * (BTN_SIZE + SPACING),
            -(PADDING + row * (BTN_SIZE + SPACING)))

        btn.spellID = spellID

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo then icon:SetTexture(spellInfo.iconID) end
        btn.icon = icon

        if PP and PP.CreateBorder then
            PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end

        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetHideCountdownNumbers(true)
        cd:SetDrawSwipe(true)
        cd:SetDrawBling(false)
        cd:SetDrawEdge(false)
        btn.cooldown = cd

        local short = PORTAL_SHORT[spellID]
        if short then
            local fontPath = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("minimap")) or "Fonts\\FRIZQT__.TTF"
            local labelFrame = CreateFrame("Frame", nil, btn)
            labelFrame:SetAllPoints()
            labelFrame:SetFrameLevel(cd:GetFrameLevel() + 2)
            local label = labelFrame:CreateFontString(nil, "OVERLAY", nil)
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(label, true) end
            label:SetFont(fontPath, 8, "OUTLINE")
            label:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
            label:SetTextColor(1, 1, 1, 0.9)
            label:SetText((EllesmereUI and EllesmereUI.L and EllesmereUI.L(short)) or short)
        end

        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.20)

        local castHL = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        castHL:SetAllPoints()
        castHL:SetColorTexture(1, 1, 1, 0.4)
        castHL:Hide()
        btn._castHL = castHL

        btn:RegisterForClicks("AnyUp", "AnyDown")
        btn:SetAttribute("type", "spell")
        btn:SetAttribute("spell", spellID)

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellID)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        _portalFlyoutBtns[i] = btn
    end

    -- Hearthstone column: 3 icons stacked vertically as a 5th column
    local _hearthBtns = {}
    for i = 1, HS_COUNT do
        local btn = CreateFrame("Button", "EUIMinimapHearth" .. i, flyout, "SecureActionButtonTemplate")
        btn:SetSize(HS_H, HS_H)
        btn:SetPoint("TOPLEFT", flyout, "TOPLEFT",
            hsX,
            -(PADDING + (i - 1) * (HS_H + SPACING)))

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
        btn.icon = icon

        if PP and PP.CreateBorder then
            PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7)
        end

        local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetHideCountdownNumbers(true)
        cd:SetDrawSwipe(true)
        cd:SetDrawBling(false)
        cd:SetDrawEdge(false)
        btn.cooldown = cd

        local hover = btn:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(1, 1, 1, 0.20)

        btn:RegisterForClicks("AnyUp", "AnyDown")

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self._hsType == "spell" then
                GameTooltip:SetSpellByID(self._hsID)
            elseif self._hsType == "item" then
                if self._hsID ~= 6948 and PlayerHasToy and PlayerHasToy(self._hsID) then
                    GameTooltip:SetToyByItemID(self._hsID)
                else
                    GameTooltip:SetItemByID(self._hsID)
                end
            elseif self._hsType == "housing" then
                GameTooltip:AddLine(EllesmereUI.L("Housing Dashboard"))
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local castHL = btn:CreateTexture(nil, "OVERLAY", nil, 1)
        castHL:SetAllPoints()
        castHL:SetColorTexture(1, 1, 1, 0.4)
        castHL:Hide()
        btn._castHL = castHL

        btn:HookScript("PostClick", function(self)
            if self._hsType == "housing" then
                if HousingFramesUtil and HousingFramesUtil.ToggleHousingDashboard then
                    HousingFramesUtil.ToggleHousingDashboard()
                end
                if _portalFlyout then _portalFlyout:Hide() end
            else
                self._castHL:Show()
            end
        end)

        _hearthBtns[i] = btn
    end


    local function RefreshHearthCooldowns()
        for _, btn in ipairs(_hearthBtns) do
            local aType, id = btn._hsType, btn._hsID
            if aType == "spell" and C_Spell and C_Spell.GetSpellCooldown then
                local cdInfo = C_Spell.GetSpellCooldown(id)
                if cdInfo and cdInfo.startTime and cdInfo.duration and cdInfo.duration > 0 then
                    btn.cooldown:SetCooldown(cdInfo.startTime, cdInfo.duration)
                else
                    btn.cooldown:Clear()
                end
            elseif aType == "item" and GetItemCooldown then
                local ok, start, dur = pcall(GetItemCooldown, id)
                if ok and start and dur and dur > 0 then
                    btn.cooldown:SetCooldown(start, dur)
                else
                    btn.cooldown:Clear()
                end
            else
                btn.cooldown:Clear()
            end
        end
    end

    local function ResolveHearthButtons()
        if InCombatLockdown() then return end
        local EUI = EllesmereUI
        local resolvers = {
            EUI.ResolveHearthSlot,
            EUI.ResolveDalaranSlot,
            EUI.ResolveHousingSlot,
        }
        for i, btn in ipairs(_hearthBtns) do
            local aType, id, iconTex = resolvers[i]()
            btn._hsType = aType
            btn._hsID = id
            btn.icon:SetTexture(iconTex)
            btn.icon:SetTexCoord(aType == "housing" and 0 or 6/64,
                                 aType == "housing" and 1 or 58/64,
                                 aType == "housing" and 0 or 6/64,
                                 aType == "housing" and 1 or 58/64)
            if aType == "housing" then
                btn:SetAttribute("type", nil)
                btn:SetAttribute("macrotext", nil)
            elseif aType == "spell" then
                btn:SetAttribute("type", "macro")
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(id)
                local name = info and info.name or ""
                btn:SetAttribute("macrotext", "/cast " .. name)
            else
                btn:SetAttribute("type", "macro")
                if id == 6948 then
                    btn:SetAttribute("macrotext", "/use item:" .. id)
                else
                    local toyName
                    if C_ToyBox and C_ToyBox.GetToyInfo then
                        local _, tn = C_ToyBox.GetToyInfo(id)
                        toyName = tn
                    end
                    btn:SetAttribute("macrotext", toyName and ("/use " .. toyName) or ("/use item:" .. id))
                end
            end
        end
        RefreshHearthCooldowns()
    end

    flyout:SetScript("OnShow", function(self)
        self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        self:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        self:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        RefreshMinimapPortalButtons()
        ResolveHearthButtons()
    end)
    flyout:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        for _, btn in ipairs(_portalFlyoutBtns) do
            if btn._castHL then btn._castHL:Hide() end
        end
        for _, btn in ipairs(_hearthBtns) do
            if btn._castHL then btn._castHL:Hide() end
        end
    end)
    flyout:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
        if event == "SPELL_UPDATE_COOLDOWN" then
            RefreshMinimapPortalButtons()
            RefreshHearthCooldowns()
        elseif unit == "player" then
            local casting = (event == "UNIT_SPELLCAST_START") and spellID or nil
            for _, btn in ipairs(_portalFlyoutBtns) do
                if btn._castHL then
                    btn._castHL:SetShown(casting and casting == btn.spellID)
                end
            end
            if not casting then
                for _, btn in ipairs(_hearthBtns) do
                    if btn._castHL then btn._castHL:Hide() end
                end
            end
        end
    end)

    EllesmereUI.RegisterEscapeClose(flyout)

    -- Keep the mouseover stack shown while this flyout is open; re-evaluate when
    -- it closes so the stack can hide if the mouse has already moved away.
    flyout:HookScript("OnShow", function() if MO_Evaluate then MO_Evaluate() end end)
    flyout:HookScript("OnHide", function() if MO_Evaluate then MO_Evaluate() end end)

    _portalFlyout = flyout
    return flyout
end

local function ToggleMinimapPortalFlyout(anchorBtn)
    if InCombatLockdown() then return end
    local flyout = CreateMinimapPortalFlyout()
    -- Scale to the user's M+ Portals Scale. Safe (combat early-returns
    -- above; secure children). Set before the anchor math so GetEffectiveScale
    -- below reflects it.
    local _mp = EBS.db and EBS.db.profile.minimap
    flyout:SetScale(_mp and _mp.extraFlyoutScale or 1.0)
    if flyout:IsShown() then
        flyout:Hide()
    else
        -- Open in the Grow Tooltip/Popup direction. Anchoring goes through
        -- UIParent in effective-scale space so the flyout's own scale never
        -- shifts it off the button. 4px gap on the facing edge; the other
        -- axis keeps the button's top/left edge (nudged 4px, matching the
        -- original leftward placement).
        local bs = anchorBtn:GetEffectiveScale()
        local fs = flyout:GetEffectiveScale()
        local bTop    = anchorBtn:GetTop()    * bs
        local bBottom = anchorBtn:GetBottom() * bs
        local bLeft   = anchorBtn:GetLeft()   * bs
        local bRight  = anchorBtn:GetRight()  * bs
        local dir = EBS._Grow.Dir()
        flyout:ClearAllPoints()
        if dir == "right" then
            flyout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (bRight + 4) / fs, (bTop + 4) / fs)
        elseif dir == "up" then
            flyout:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fs, (bTop + 4) / fs)
        elseif dir == "down" then
            flyout:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fs, (bBottom - 4) / fs)
        else
            flyout:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", (bLeft - 4) / fs, (bTop + 4) / fs)
        end
        flyout:Show()
    end
end

local function SizePortalBtn(btn, showBg)
    local btnSz = GetInteractableBtnSize()
    btn:SetSize(btnSz, btnSz)
    if btn._bg then btn._bg:SetShown(showBg ~= false) end
    local inset = 4
    local avail = btnSz - inset * 2
    btn._icon:SetSize(avail, avail)
    btn._icon:ClearAllPoints()
    btn._icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
end

local function CreatePortalBtn(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(GetInteractableBtnSize(), GetInteractableBtnSize())
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)
    btn:EnableMouse(true)

    local bg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
    bg:SetBackdropColor(0, 0, 0, 0.8)
    bg:SetAllPoints(btn)
    bg:SetFrameLevel(btn:GetFrameLevel() - 1)
    btn._bg = bg

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_PortalDalaran")
    icon:SetTexCoord(6/64, 58/64, 6/64, 58/64)
    btn._icon = icon

    SizePortalBtn(btn)

    btn:SetScript("OnEnter", function(self)
        self._icon:SetVertexColor(1, 1, 1, 1)
        if _portalFlyout and _portalFlyout:IsShown() then return end
        if EllesmereUI.ShowWidgetTooltip then EllesmereUI.ShowWidgetTooltip(self, "M+ Portals", { anchor = EBS._Grow.TT(), scale = GetCustomTooltipScale() }) end
    end)
    btn:SetScript("OnLeave", function(self)
        self._icon:SetVertexColor(0.85, 0.85, 0.85, 1)
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)
    btn:SetScript("OnMouseDown", function(self)
        self._icon:SetVertexColor(0.7, 0.7, 0.7, 1)
    end)
    btn:SetScript("OnMouseUp", function(self)
        local over = self:IsMouseOver()
        local v = over and 1 or 0.85
        self._icon:SetVertexColor(v, v, v, 1)
    end)
    btn:SetScript("OnClick", function(self)
        if GetFFD(self).freeMoveJustDragged then return end
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip(true) end
        ToggleMinimapPortalFlyout(self)
    end)

    icon:SetVertexColor(0.85, 0.85, 0.85, 1)

    btn._indicatorKey = "_portals"

    return btn
end

-------------------------------------------------------------------------------
--  Friends Online indicator
--  Gathers guild, BNet favorites, and BNet/character friends on hover.
--  Zero background work -- all data is read live when the tooltip opens.
-------------------------------------------------------------------------------
local FRIENDS_ATLAS = "housefinder_neighborhood-friends-icon"

local function GatherOnlineFriends()
    local guild, favorites, friends = {}, {}, {}
    local seenBNet = {}
    local myName = UnitName("player")

    -- Guild members (exclude self)
    if IsInGuild and IsInGuild() then
        local total = GetNumGuildMembers() or 0
        for i = 1, total do
            local name, _, _, level, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
            if online and name then
                local short = name:match("^([^%-]+)") or name
                if short ~= myName then
                    guild[#guild + 1] = { name = short, full = name, class = classFile, zone = zone or "", level = level, kind = "guild" }
                end
            end
        end
    end

    -- BNet friends (favorites first, then others)
    local numBNet = BNGetNumFriends and BNGetNumFriends() or 0
    for i = 1, numBNet do
        local acct = C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(i)
        if acct then
            local gameInfo = acct.gameAccountInfo
            if gameInfo and gameInfo.isOnline and gameInfo.clientProgram == "WoW" then
                local charName = gameInfo.characterName
                local classFile = gameInfo.className and gameInfo.className:upper():gsub(" ", "")
                -- Resolve classFile from class ID if available
                if gameInfo.classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
                    local ci = C_CreatureInfo.GetClassInfo(gameInfo.classID)
                    if ci and ci.classFile then classFile = ci.classFile end
                end
                local zone = gameInfo.areaName or ""
                local realm = gameInfo.realmName
                local full = charName
                if charName and realm and realm ~= "" then
                    full = charName .. "-" .. realm
                end
                -- Battle tag without the #discriminator (fall back to accountName/RealID)
                local rawTag = acct.battleTag or acct.accountName
                local tagName = rawTag and rawTag:match("^([^#]+)") or rawTag
                local entry = {
                    name = charName or tagName or "???",
                    full = full,
                    class = classFile,
                    zone = zone,
                    level = gameInfo.characterLevel,
                    bnetTag = tagName,
                    bnetName = acct.accountName or acct.battleTag,
                    bnetID = acct.bnetAccountID,
                    isFavorite = acct.isFavorite,
                    note = acct.note,
                    kind = "bnet",
                }
                if charName then seenBNet[charName] = true end
                if acct.isFavorite then
                    favorites[#favorites + 1] = entry
                else
                    friends[#friends + 1] = entry
                end
            end
        end
    end

    -- Character-level friends (skip if already in BNet list)
    local numChar = C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
    for i = 1, numChar do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.connected then
            local charName = info.name
            if charName and not seenBNet[charName] then
                friends[#friends + 1] = {
                    name = charName:match("^([^%-]+)") or charName,
                    full = charName,
                    class = info.className and info.className:upper():gsub(" ", ""),
                    zone = info.area or "",
                    level = info.level,
                    note = info.notes,
                    kind = "char",
                }
            end
        end
    end

    -- Remove guild members from friends list to avoid duplicates
    local guildSet = {}
    for _, g in ipairs(guild) do guildSet[g.name] = true end
    for i = #friends, 1, -1 do
        if guildSet[friends[i].name] then table.remove(friends, i) end
    end
    for i = #favorites, 1, -1 do
        if guildSet[favorites[i].name] then table.remove(favorites, i) end
    end

    -- Sort by zone (empty zones last), then name -- groups same-location together
    local function byZone(a, b)
        local az, bz = a.zone or "", b.zone or ""
        if (az == "") ~= (bz == "") then return az ~= "" end
        if az ~= bz then return az < bz end
        return (a.name or "") < (b.name or "")
    end
    -- Friends/favorites sort A-Z by battle tag (fall back to name); guild stays grouped by zone
    local function byTag(a, b)
        return (a.bnetTag or a.name or ""):lower() < (b.bnetTag or b.name or ""):lower()
    end
    table.sort(guild, byZone)
    table.sort(favorites, byTag)
    table.sort(friends, byTag)

    return guild, favorites, friends
end

-- Custom two-column friends tooltip (same pattern as M+ death tooltip).
-- FTT_FONT stays file-scope (it is shared with the calendar/vault tooltips below).
-- Everything else lives in the do-block so its locals are released at the matching
-- end and do not consume main-chunk local slots -- this file is at the Lua 5.1
-- 200-local cap. Only ShowFriendsTooltip / HideFriendsTooltip are used outside the
-- block (the minimap hover handlers), so they are forward-declared here.
local function FTT_FONT()
    return (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("minimap")) or EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
end
local ShowFriendsTooltip, HideFriendsTooltip
do
local _friendsTT
local _friendsTTRows = {}
local _friendsTTHeaders = {}
local _friendsTTDividers = {}
local FTT_PAD     = 8
local FTT_ROW_H   = 14
local FTT_HDR_H   = 16
local FTT_GAP     = 2
local FTT_DIV_PAD = 5   -- padding above and below the divider line

-- Hover-stable hide: small grace period so cursor can travel from button to tooltip
local _fttHideToken = 0
local _fttMenuOpen = false
local function CancelFTTHide()
    _fttHideToken = _fttHideToken + 1
end
local function ScheduleFTTHide()
    _fttHideToken = _fttHideToken + 1
    if _fttMenuOpen then return end
    local mine = _fttHideToken
    C_Timer.After(0.15, function()
        if mine ~= _fttHideToken then return end
        if _fttMenuOpen then return end
        if _friendsTT then _friendsTT:Hide() end
    end)
end

-- THE RULE: "protected content" = anywhere the chat / whisper system carries
-- secret values and a whisper action can taint Blizzard's chat code -- i.e. a
-- Mythic+ run (the entire run), raid combat, and rated / instanced PvP combat.
-- This is exactly EllesmereUI.InProtectedInstance() (defined in EllesmereUI.lua),
-- the canonical EUI guard for taint-sensitive operations. Whispering is suppressed
-- entirely in this state; invites are still allowed (they touch no chat code).
local function FTTInProtectedContent()
    return EllesmereUI.InProtectedInstance and EllesmereUI.InProtectedInstance() or false
end

-- Open a whisper. BNet friends are whispered via their Battle.net account
-- (reaches them on any character / faction / realm); everyone else by character
-- name. Passing an explicit chat frame skips ChatFrame_SendTell's
-- FCF_OpenTemporaryWindow path -- that path drives the now-secret window list in
-- 12.0 and tainted all of chat (the SetTellTarget / windowList /
-- MessageEventHandler cascade). A "/w" macro can't open the editbox, only send.
local function FTTOpenWhisper(charName, bnetName)
    -- Suppress whispers wherever chat is taint-sensitive: (1) protected content,
    -- and (2) while /euidev is on -- it forces addonChallengeModeRestrictionsForced,
    -- i.e. the same secret-value restricted environment as a real Mythic+, so chat
    -- would taint there too. InProtectedInstance() does NOT see the forced CVar, so
    -- the dev-mode check is separate.
    local blocked
    if EllesmereUI.IsDevModeActive and EllesmereUI.IsDevModeActive() then
        blocked = "This action is protected while dev mode (/euidev) is on."
    elseif FTTInProtectedContent() then
        blocked = "This action is protected in Mythic+ and raid combat."
    end
    if blocked then
        if UIErrorsFrame then UIErrorsFrame:AddMessage(blocked, 1.0, 0.3, 0.3, 1.0) end
        return
    end
    if bnetName and bnetName ~= "" then
        local sendBN = (ChatFrameUtil and ChatFrameUtil.SendBNetTell) or ChatFrame_SendBNetTell
        if sendBN then sendBN(bnetName, DEFAULT_CHAT_FRAME); return end
    end
    if charName and charName ~= "" then
        local sendTell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
        if sendTell then sendTell(charName, DEFAULT_CHAT_FRAME) end
    end
end

-- Reusable right-click menu: plain buttons. Whisper -> FTTOpenWhisper (frame-scoped,
-- no FCF taint); Invite -> C_PartyInfo.InviteUnit (taint-safe, opens no chat window;
-- the same call our Friends search-results rows use).
local _fttMenu
local function GetFTTMenu()
    if _fttMenu then return _fttMenu end
    local PAD, RH, MW = 4, 18, 96
    local m = CreateFrame("Frame", nil, UIParent)
    m:SetFrameStrata("TOOLTIP")
    m:SetFrameLevel(500)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m:SetSize(MW, PAD * 2 + RH * 2)
    m:Hide()
    local bg = m:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
    EllesmereUI.MakeBorder(m, 1, 1, 1, 0.15, EllesmereUI.PanelPP)

    local function MakeItem(text, yOff, onClick)
        local b = CreateFrame("Button", nil, m)
        b:RegisterForClicks("AnyUp")
        b:SetPoint("TOPLEFT", m, "TOPLEFT", PAD, yOff)
        b:SetPoint("TOPRIGHT", m, "TOPRIGHT", -PAD, yOff)
        b:SetHeight(RH)
        local hl = b:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.10); hl:Hide()
        b:SetScript("OnEnter", function() hl:Show() end)
        b:SetScript("OnLeave", function() hl:Hide() end)
        b:SetScript("OnClick", function()
            onClick(m._target, m._bnet)
            m:Hide()
        end)
        local fs = b:CreateFontString(nil, "OVERLAY")
        fs:SetFont(FTT_FONT(), 11, "")
        fs:SetJustifyH("LEFT")
        fs:SetPoint("LEFT", b, "LEFT", 6, 0)
        fs:SetText(text)
    end

    -- Whisper(charName, bnetName); Invite always uses the character name.
    MakeItem("Whisper", -PAD, FTTOpenWhisper)
    MakeItem("Invite", -PAD - RH, function(target)
        if target and target ~= "" and C_PartyInfo and C_PartyInfo.InviteUnit then
            C_PartyInfo.InviteUnit(target)
        end
    end)

    m:SetScript("OnLeave", function(self)
        if not self:IsMouseOver() then self:Hide() end
    end)
    m:SetScript("OnHide", function()
        _fttMenuOpen = false
        ScheduleFTTHide()
    end)
    _fttMenu = m
    return m
end

local function FTTShowRowMenu(rowBtn)
    local target = rowBtn and rowBtn._fttTarget
    local bnet = rowBtn and rowBtn._fttBnet
    if (not target or target == "") and (not bnet or bnet == "") then return end
    local m = GetFTTMenu()
    m._target = target
    m._bnet = bnet
    _fttMenuOpen = true
    CancelFTTHide()
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", rowBtn, "TOPRIGHT", 0, 0)
    m:Show()
end

local function GetFriendsTT()
    if _friendsTT then return _friendsTT end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(200)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetScript("OnEnter", CancelFTTHide)
    f:SetScript("OnLeave", ScheduleFTTHide)
    f:HookScript("OnHide", function() if _fttMenu then _fttMenu:Hide() end end)
    f:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.067, 0.067, 0.067, 0.92)
    EllesmereUI.MakeBorder(f, 1, 1, 1, 0.15, EllesmereUI.PanelPP)
    -- Mouseover Extra Buttons: hovering this tooltip counts as hovering the
    -- button stack, so crossing onto it must not hide the extra buttons.
    -- MO_OverAny reads the frame via EBS (this local is do-block scoped) and
    -- the hooks re-evaluate when the tooltip opens/closes -- without the
    -- OnHide one, nothing would re-run the fade-out after it closes.
    EBS._friendsTT = f
    f:HookScript("OnShow", function() if MO_Evaluate then MO_Evaluate() end end)
    f:HookScript("OnHide", function() if MO_Evaluate then MO_Evaluate() end end)
    _friendsTT = f
    return f
end

local function EnsureFTTRow(idx)
    if _friendsTTRows[idx] then return _friendsTTRows[idx] end
    local tt = GetFriendsTT()
    local btn = CreateFrame("Button", nil, tt)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")
    btn:SetHeight(FTT_ROW_H)
    local hl = btn:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    hl:Hide()
    btn._hl = hl
    btn:SetScript("OnEnter", function(self)
        CancelFTTHide()
        if self._entry then self._hl:Show() end
    end)
    btn:SetScript("OnLeave", function(self)
        self._hl:Hide()
        ScheduleFTTHide()
    end)
    -- Left-click whispers (frame-scoped, no FCF taint); right-click opens the menu.
    btn:SetScript("OnClick", function(self, mouseButton)
        if not self._entry then return end
        if mouseButton == "RightButton" then
            FTTShowRowMenu(self)
        elseif mouseButton == "LeftButton" then
            FTTOpenWhisper(self._fttTarget, self._fttBnet)
            CancelFTTHide()
            if _friendsTT then _friendsTT:Hide() end
        end
    end)
    local nameFS = btn:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(FTT_FONT(), 10, "")
    nameFS:SetJustifyH("LEFT")
    nameFS:SetPoint("LEFT", btn, "LEFT", 0, 0)
    local zoneFS = btn:CreateFontString(nil, "OVERLAY")
    zoneFS:SetFont(FTT_FONT(), 10, "")
    zoneFS:SetJustifyH("RIGHT")
    zoneFS:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
    _friendsTTRows[idx] = { button = btn, name = nameFS, zone = zoneFS }
    return _friendsTTRows[idx]
end

-- Store the whisper/invite targets on a row (read by its OnClick and the menu).
-- target = character name (invite + character whisper); bnet = Battle.net account
-- (preferred for whisper when set).
local function FTTSetRowTarget(btn, target, bnet)
    btn._fttTarget = target
    btn._fttBnet = bnet
end

local function EnsureFTTHeader(idx)
    if _friendsTTHeaders[idx] then return _friendsTTHeaders[idx] end
    local tt = GetFriendsTT()
    local fs = tt:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FTT_FONT(), 12, "")
    fs:SetJustifyH("CENTER")
    fs:SetTextColor(1, 1, 1, 0.9)
    _friendsTTHeaders[idx] = fs
    return fs
end

local function EnsureFTTDivider(idx)
    if _friendsTTDividers[idx] then return _friendsTTDividers[idx] end
    local tt = GetFriendsTT()
    local tex = tt:CreateTexture(nil, "ARTWORK")
    tex:SetColorTexture(1, 1, 1, 0.12)
    local PP = EllesmereUI.PP
    if PP and PP.Snap then
        tex:SetHeight(PP.Snap(1))
    else
        tex:SetHeight(1)
    end
    _friendsTTDividers[idx] = tex
    return tex
end

function ShowFriendsTooltip(anchor)
    CancelFTTHide()
    local guild, favorites, friends = GatherOnlineFriends()
    local tt = GetFriendsTT()
    -- Scale the whole tooltip to the user's Custom Tooltip Size (re-applied each show).
    tt:SetScale(GetCustomTooltipScale())
    local total = #guild + #favorites + #friends

    local mp = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    local maxRows = mp and tonumber(mp.friendsMaxRows) or 0
    if maxRows and maxRows < 0 then maxRows = 0 end
    -- Hard cap: never more than 30 rows per section, even at 0 ("no cap")
    -- or stale values above the slider's current max -- big guilds otherwise
    -- build enormous tooltips. Overflow still gets the "...and N more" row.
    if maxRows == 0 or maxRows > 30 then maxRows = 30 end

    -- Refresh fonts to match current global font setting
    local font = FTT_FONT()
    for i = 1, #_friendsTTRows do
        _friendsTTRows[i].name:SetFont(font, 10, "")
        _friendsTTRows[i].zone:SetFont(font, 10, "")
    end
    for i = 1, #_friendsTTHeaders do
        _friendsTTHeaders[i]:SetFont(font, 12, "")
    end

    -- Hide all pooled elements and clear stale entry refs
    for i = 1, #_friendsTTRows do
        local r = _friendsTTRows[i]
        r.name:Hide()
        r.zone:Hide()
        if r.button then
            r.button:Hide()
            r.button._entry = nil
            FTTSetRowTarget(r.button, nil)
            if r.button._hl then r.button._hl:Hide() end
        end
    end
    for i = 1, #_friendsTTHeaders do _friendsTTHeaders[i]:Hide() end
    for i = 1, #_friendsTTDividers do _friendsTTDividers[i]:Hide() end

    if total == 0 then
        local row = EnsureFTTRow(1)
        row.name:SetFont(font, 10, "")
        row.name:SetText("|cff888888No friends online|r")
        row.zone:SetText("")
        tt:SetSize(FTT_PAD * 2 + 140, FTT_PAD + FTT_ROW_H + FTT_PAD)
        row.button:ClearAllPoints()
        row.button:SetPoint("TOPLEFT", tt, "TOPLEFT", FTT_PAD, -FTT_PAD)
        row.button:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -FTT_PAD, -FTT_PAD)
        row.button._entry = nil
        FTTSetRowTarget(row.button, nil)
        row.button:Show()
        row.name:Show()
        tt:ClearAllPoints()
        local gpt = EBS._Grow.edge[EBS._Grow.Dir()] or EBS._Grow.edge.left
        tt:SetPoint(gpt[1], anchor, gpt[2], gpt[3], gpt[4])
        tt:Show()
        return total
    end

    local sections = {}
    if #favorites > 0 then sections[#sections + 1] = { title = "Favorites", list = favorites } end
    if #guild > 0 then sections[#sections + 1] = { title = "Guild", list = guild } end
    if #friends > 0 then sections[#sections + 1] = { title = "Friends", list = friends } end

    local rowIdx = 0
    local hdrIdx = 0
    local divIdx = 0
    local maxNameW, maxZoneW = 0, 0
    local curY = -FTT_PAD

    for si, sec in ipairs(sections) do
        -- Divider line between sections (not before the first)
        if si > 1 then
            curY = curY - FTT_DIV_PAD
            divIdx = divIdx + 1
            local div = EnsureFTTDivider(divIdx)
            div:ClearAllPoints()
            div:SetPoint("TOPLEFT", tt, "TOPLEFT", FTT_PAD, curY)
            div:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -FTT_PAD, curY)
            div:Show()
            curY = curY - div:GetHeight() - FTT_DIV_PAD
        end

        -- Section header (centered, white title, accent count, 12px)
        curY = curY - 5  -- spacing above header
        hdrIdx = hdrIdx + 1
        local hdr = EnsureFTTHeader(hdrIdx)
        hdr:SetFont(font, 12, "")
        local ac = EllesmereUI.ELLESMERE_GREEN or EllesmereUI._accentColor
        local acHex = ac and format("%02x%02x%02x", (ac.r or 0.05) * 255, (ac.g or 0.82) * 255, (ac.b or 0.62) * 255) or "0cd29f"
        hdr:SetText(EllesmereUI.L(sec.title) .. " (|cff" .. acHex .. #sec.list .. "|r)")
        hdr:ClearAllPoints()
        hdr:SetPoint("TOP", tt, "TOP", 0, curY)
        hdr:Show()
        curY = curY - FTT_HDR_H - 5  -- spacing below header

        local shown = #sec.list
        if maxRows > 0 and shown > maxRows then shown = maxRows end
        for i = 1, shown do
            local e = sec.list[i]
            rowIdx = rowIdx + 1
            local row = EnsureFTTRow(rowIdx)
            row.name:SetFont(font, 10, "")
            row.zone:SetFont(font, 10, "")

            local cc = e.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[e.class]
            local colored = cc and cc:WrapTextInColorCode(e.name) or e.name
            -- BNet friends: show battle tag before the in-game name, e.g. "Bigmacz (Unholyftw)"
            if e.bnetTag then
                colored = "|cffffd100" .. e.bnetTag .. "|r (" .. colored .. ")"
            end
            -- Level to the right of the in-game name, e.g. "Unholyftw 80"
            local lvl = tonumber(e.level)
            if lvl and lvl > 0 then
                colored = colored .. " |cffb0b0b0" .. lvl .. "|r"
            end
            row.name:SetText(colored)
            row.name:SetTextColor(1, 1, 1, 0.85)

            local zone = e.zone or ""
            if zone ~= "" then
                row.zone:SetText("|cff888888" .. zone .. "|r")
            else
                row.zone:SetText("")
            end

            row.button._entry = e
            FTTSetRowTarget(row.button, e.full or e.name, e.bnetName)
            row.button:ClearAllPoints()
            row.button:SetPoint("TOPLEFT", tt, "TOPLEFT", FTT_PAD, curY)
            row.button:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -FTT_PAD, curY)
            row.button:Show()
            row.name:Show()
            row.zone:Show()

            local nw = row.name:GetStringWidth() or 0
            local zw = row.zone:GetStringWidth() or 0
            if nw > maxNameW then maxNameW = nw end
            if zw > maxZoneW then maxZoneW = zw end

            curY = curY - (FTT_ROW_H + FTT_GAP)
        end

        if maxRows > 0 and #sec.list > maxRows then
            rowIdx = rowIdx + 1
            local row = EnsureFTTRow(rowIdx)
            row.name:SetFont(font, 10, "")
            row.name:SetText("|cff888888...and " .. (#sec.list - maxRows) .. " more|r")
            row.zone:SetText("")
            row.button._entry = nil
            FTTSetRowTarget(row.button, nil)
            row.button:ClearAllPoints()
            row.button:SetPoint("TOPLEFT", tt, "TOPLEFT", FTT_PAD, curY)
            row.button:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -FTT_PAD, curY)
            row.button:Show()
            row.name:Show()
            curY = curY - (FTT_ROW_H + FTT_GAP)
        end
    end

    local contentW = FTT_PAD + maxNameW + 16 + maxZoneW + FTT_PAD
    local ttW = math.max(contentW, 160)
    local ttH = -curY + FTT_PAD

    tt:SetSize(ttW, ttH)
    tt:ClearAllPoints()
    local gpt = EBS._Grow.edge[EBS._Grow.Dir()] or EBS._Grow.edge.left
    tt:SetPoint(gpt[1], anchor, gpt[2], gpt[3], gpt[4])
    tt:Show()
    -- Off-screen protection is SetClampedToScreen on the frame (handles all
    -- four edges for every Grow Tooltip/Popup direction).
    return total
end

function HideFriendsTooltip()
    ScheduleFTTHide()
end
end  -- friends tooltip do-block

-- Custom calendar tooltip with right-aligned kill counts and server/reset footer.
local _calendarTT
local _calendarTTTitle
local _calendarTTRows = {}
local _calendarTTFooters = {}
local CTT_PAD = 8
local CTT_ROW_H = 14
local CTT_TITLE_H = 16
local CTT_GAP = 6

local function GetCalendarTT()
    if _calendarTT then return _calendarTT end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(200)
    f:SetClampedToScreen(true)
    f:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.067, 0.067, 0.067, 0.92)
    EllesmereUI.MakeBorder(f, 1, 1, 1, 0.15, EllesmereUI.PanelPP)
    _calendarTT = f
    return f
end

local function EnsureCalendarTTRow(idx)
    if _calendarTTRows[idx] then return _calendarTTRows[idx] end
    local tt = GetCalendarTT()
    local leftFS = tt:CreateFontString(nil, "OVERLAY")
    leftFS:SetFont(FTT_FONT(), 10, "")
    leftFS:SetJustifyH("LEFT")
    local rightFS = tt:CreateFontString(nil, "OVERLAY")
    rightFS:SetFont(FTT_FONT(), 10, "")
    rightFS:SetJustifyH("RIGHT")
    _calendarTTRows[idx] = { left = leftFS, right = rightFS }
    return _calendarTTRows[idx]
end

local function EnsureCalendarTTFooter(idx)
    if _calendarTTFooters[idx] then return _calendarTTFooters[idx] end
    local tt = GetCalendarTT()
    local leftFS = tt:CreateFontString(nil, "OVERLAY")
    leftFS:SetFont(FTT_FONT(), 10, "")
    leftFS:SetJustifyH("LEFT")
    leftFS:SetTextColor(1, 1, 1, 0.65)
    local rightFS = tt:CreateFontString(nil, "OVERLAY")
    rightFS:SetFont(FTT_FONT(), 10, "")
    rightFS:SetJustifyH("RIGHT")
    rightFS:SetTextColor(1, 1, 1, 0.80)
    _calendarTTFooters[idx] = { left = leftFS, right = rightFS }
    return _calendarTTFooters[idx]
end

local function EnsureCalendarTTTitle()
    if _calendarTTTitle then return _calendarTTTitle end
    local tt = GetCalendarTT()
    local fs = tt:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FTT_FONT(), 12, "")
    fs:SetJustifyH("CENTER")
    fs:SetTextColor(1, 1, 1, 0.90)
    _calendarTTTitle = fs
    return fs
end

local function GetServerTimeText()
    local h, m = GetGameTime()
    local use24h = GetCVar("timeMgrUseMilitaryTime") == "1"
    if use24h then
        return format("%02d:%02d", h, m)
    end
    local ampm = h >= 12 and "PM" or "AM"
    h = h % 12
    if h == 0 then h = 12 end
    return format("%d:%02d %s", h, m, ampm)
end

local function GetWeeklyResetText()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and SecondsToTime then
        local secs = C_DateAndTime.GetSecondsUntilWeeklyReset()
        if secs then
            return SecondsToTime(secs, true, nil, 3)
        end
    end
    return ""
end

local function HideCalendarTooltip()
    if _calendarTT then _calendarTT:Hide() end
end

local function ShowCalendarTooltip(anchor, lockoutEntries)
    local tt = GetCalendarTT()
    -- Scale the whole tooltip to the user's Custom Tooltip Size (re-applied each show).
    tt:SetScale(GetCustomTooltipScale())
    local font = FTT_FONT()

    for i = 1, #_calendarTTRows do
        _calendarTTRows[i].left:Hide()
        _calendarTTRows[i].right:Hide()
    end
    for i = 1, #_calendarTTFooters do
        _calendarTTFooters[i].left:Hide()
        _calendarTTFooters[i].right:Hide()
    end

    local title = EnsureCalendarTTTitle()
    title:SetFont(font, 12, "")
    title:SetText(EllesmereUI.L("Calendar"))

    local footerData = {
        { left = EllesmereUI.L("Server Time"), right = GetServerTimeText() },
        { left = format("%s %s", WEEKLY or "Weekly", RESET or "Reset"), right = GetWeeklyResetText() },
    }

    local maxLeftW, maxRightW = 0, 0
    local curY = -CTT_PAD

    title:ClearAllPoints()
    title:SetPoint("TOP", tt, "TOP", 0, curY)
    title:Show()
    curY = curY - CTT_TITLE_H - CTT_GAP

    for i, entry in ipairs(lockoutEntries) do
        local row = EnsureCalendarTTRow(i)
        row.left:SetFont(font, 10, "")
        row.right:SetFont(font, 10, "")
        row.left:SetText(entry.left)
        row.right:SetText(entry.right or "")
        row.left:ClearAllPoints()
        row.left:SetPoint("TOPLEFT", tt, "TOPLEFT", CTT_PAD, curY)
        row.right:ClearAllPoints()
        row.right:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -CTT_PAD, curY)
        row.left:Show()
        if entry.right and entry.right ~= "" then row.right:Show() end

        local lw = row.left:GetStringWidth() or 0
        local rw = row.right:GetStringWidth() or 0
        if lw > maxLeftW then maxLeftW = lw end
        if rw > maxRightW then maxRightW = rw end

        curY = curY - CTT_ROW_H
    end

    curY = curY - CTT_GAP

    for i, fd in ipairs(footerData) do
        local footer = EnsureCalendarTTFooter(i)
        footer.left:SetFont(font, 10, "")
        footer.right:SetFont(font, 10, "")
        footer.left:SetText(fd.left)
        footer.right:SetText(fd.right)
        footer.left:ClearAllPoints()
        footer.left:SetPoint("TOPLEFT", tt, "TOPLEFT", CTT_PAD, curY)
        footer.right:ClearAllPoints()
        footer.right:SetPoint("TOPRIGHT", tt, "TOPRIGHT", -CTT_PAD, curY)
        footer.left:Show()
        footer.right:Show()

        local lw = footer.left:GetStringWidth() or 0
        local rw = footer.right:GetStringWidth() or 0
        if lw > maxLeftW then maxLeftW = lw end
        if rw > maxRightW then maxRightW = rw end

        curY = curY - CTT_ROW_H
    end

    local contentW = CTT_PAD + maxLeftW + 16 + maxRightW + CTT_PAD
    local ttW = math.max(contentW, 180)
    local ttH = -curY + CTT_PAD

    tt:SetSize(ttW, ttH)
    tt:ClearAllPoints()
    local gpt = EBS._Grow.edge[EBS._Grow.Dir()] or EBS._Grow.edge.left
    tt:SetPoint(gpt[1], anchor, gpt[2], gpt[3], gpt[4])
    tt:Show()
    -- Off-screen protection is SetClampedToScreen on the frame.
end

-- Saved instance lockouts for the calendar tooltip.
local LOCKOUT_DIFFICULTIES = {
    [2] = true,   -- heroic
    [23] = true,  -- mythic
    [148] = true,
    [174] = true,
    [185] = true,
    [198] = true,
    [201] = true,
    [215] = true,
}
local LFR_DIFFICULTIES = {
    [7] = true,
    [17] = true,
}

local function GetCalendarLockoutEntries()
    if not GetNumSavedInstances or not GetSavedInstanceInfo then return end

    if RequestRaidInfo then RequestRaidInfo() end

    local entries = {}
    for i = 1, GetNumSavedInstances() do
        local name, _, _, difficulty, locked, extended, _, isRaid, _, difficultyName, numEncounters, encounterProgress =
            GetSavedInstanceInfo(i)
        if name and (locked or extended) and (isRaid or LOCKOUT_DIFFICULTIES[difficulty]) then
            local diffLabel = difficultyName
            local _, _, isHeroic, _, displayHeroic, displayMythic
            if GetDifficultyInfo and difficulty then
                diffLabel, _, isHeroic, _, displayHeroic, displayMythic = GetDifficultyInfo(difficulty)
            end
            diffLabel = diffLabel or ""

            local isLFR = LFR_DIFFICULTIES[difficulty]
            local sortTier
            if displayMythic then
                sortTier = "4"
            elseif isHeroic or displayHeroic then
                sortTier = "3"
            elseif isLFR then
                sortTier = "1"
            else
                sortTier = "2"
            end
            local sortKey = name .. "\t" .. sortTier

            local leftText = name
            local rightText = diffLabel
            if numEncounters and numEncounters > 0 and encounterProgress and encounterProgress >= 0 then
                rightText = format("%s %d/%d", diffLabel, encounterProgress, numEncounters)
            end
            entries[#entries + 1] = { sortKey = sortKey, left = leftText, right = rightText }
        end
    end

    table.sort(entries, function(a, b) return a.sortKey < b.sortKey end)

    if #entries == 0 then return end

    local result = {}
    for ei = 1, #entries do
        result[#result + 1] = { left = entries[ei].left, right = entries[ei].right }
    end
    return result
end

local function BuildCustomIndicators(minimap)
    if _customIndicators.tracking then
        -- Re-apply the current accent to the friends icon so a later ApplyAll
        -- (e.g. at PLAYER_ENTERING_WORLD, after EllesmereUI's theme resolution
        -- has mutated ELLESMERE_GREEN) picks up the right color -- same
        -- pattern as CreateFlyoutToggle. The create-once path below reads the
        -- accent only at creation time, which can race the theme resolution.
        local fi = _customIndicators.friends and _customIndicators.friends._icon
        if fi then
            local EG2 = EllesmereUI.ELLESMERE_GREEN
            fi:SetVertexColor(EG2.r, EG2.g, EG2.b, 1)
        end
        return
    end

    -- Tracking
    _customIndicators.tracking = CreateIndicatorBtn("_tracking", minimap,
        "UI-HUD-Minimap-Tracking-Up", "UI-HUD-Minimap-Tracking-Mouseover", "UI-HUD-Minimap-Tracking-Down",
        function(self)
            local blizBtn = MinimapCluster and MinimapCluster.Tracking and MinimapCluster.Tracking.Button
            if not blizBtn or not blizBtn.OpenMenu then return end

            -- Toggle: close if already open
            if blizBtn.menu and blizBtn.menu:IsShown() then
                blizBtn.menu:Hide()
                return
            end

            -- Position hidden Blizzard button at our custom button
            blizBtn:ClearAllPoints()
            blizBtn:SetPoint("CENTER", self, "CENTER", 0, 0)
            blizBtn:SetAlpha(0)
            blizBtn:EnableMouse(false)
            blizBtn:OpenMenu()

            -- Reposition menu so its top aligns with our button's top
            if blizBtn.menu then
                blizBtn.menu:ClearAllPoints()
                blizBtn.menu:SetPoint("TOPRIGHT", self, "TOPLEFT", -4, 0)
            end
        end)
    local trackBaseEnter = _customIndicators.tracking:GetScript("OnEnter")
    local trackBaseLeave = _customIndicators.tracking:GetScript("OnLeave")
    _customIndicators.tracking:SetScript("OnEnter", function(self)
        if trackBaseEnter then trackBaseEnter(self) end
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Tracking", { anchor = EBS._Grow.TT(), scale = GetCustomTooltipScale() })
        end
    end)
    _customIndicators.tracking:SetScript("OnLeave", function(self)
        if trackBaseLeave then trackBaseLeave(self) end
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)

    -- Calendar (day-of-month atlas)
    local calDay = tonumber(date("%d")) or 1
    local calPrefix = "UI-HUD-Calendar-" .. calDay
    _customIndicators.calendar = CreateIndicatorBtn("_gameTime", minimap,
        calPrefix .. "-Up", calPrefix .. "-Mouseover", calPrefix .. "-Down",
        function()
            if ToggleCalendar then ToggleCalendar() end
        end)
    _customIndicators.calendar._calDay = calDay
    local calBaseEnter = _customIndicators.calendar:GetScript("OnEnter")
    local calBaseLeave = _customIndicators.calendar:GetScript("OnLeave")
    _customIndicators.calendar:SetScript("OnEnter", function(self)
        if calBaseEnter then calBaseEnter(self) end
        if GetFFD(self).freeMoveJustDragged then return end
        local lockoutEntries
        if not (EllesmereUI.InProtectedInstance and EllesmereUI.InProtectedInstance()) then
            lockoutEntries = GetCalendarLockoutEntries()
        end
        if lockoutEntries then
            ShowCalendarTooltip(self, lockoutEntries)
        elseif EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, "Calendar", { anchor = EBS._Grow.TT(), scale = GetCustomTooltipScale() })
        end
    end)
    _customIndicators.calendar:SetScript("OnLeave", function(self)
        if calBaseLeave then calBaseLeave(self) end
        HideCalendarTooltip()
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)

    -- Mail (informational, tooltip on hover, with hover atlas)
    _customIndicators.mail = CreateIndicatorBtn("_mail", minimap,
        "UI-HUD-Minimap-Mail-Up", "UI-HUD-Minimap-Mail-Mouseover", nil, nil)
    local mailBaseEnter = _customIndicators.mail:GetScript("OnEnter")
    local mailBaseLeave = _customIndicators.mail:GetScript("OnLeave")
    _customIndicators.mail:SetScript("OnEnter", function(self)
        if EBS._HVRevealMapHover then EBS._HVRevealMapHover() end
        if mailBaseEnter then mailBaseEnter(self) end
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            EllesmereUI.ShowWidgetTooltip(self, HAVE_MAIL or "New Mail", { anchor = EBS._Grow.TT(), scale = GetCustomTooltipScale() })
        end
    end)
    _customIndicators.mail:SetScript("OnLeave", function(self)
        if mailBaseLeave then mailBaseLeave(self) end
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)

    -- Crafting Order (informational, tooltip on hover, with hover atlas)
    _customIndicators.crafting = CreateIndicatorBtn("_crafting", minimap,
        "UI-HUD-Minimap-CraftingOrder-Up-2x", "UI-HUD-Minimap-CraftingOrder-Over-2x", "UI-HUD-Minimap-CraftingOrder-Down-2x", nil)
    local craftBaseEnter = _customIndicators.crafting:GetScript("OnEnter")
    local craftBaseLeave = _customIndicators.crafting:GetScript("OnLeave")
    _customIndicators.crafting:SetScript("OnEnter", function(self)
        if craftBaseEnter then craftBaseEnter(self) end
        if not GetFFD(self).freeMoveJustDragged and EllesmereUI.ShowWidgetTooltip then
            local label = "Crafting Orders"
            if C_CraftingOrders and C_CraftingOrders.GetPersonalOrdersInfo then
                local infos = C_CraftingOrders.GetPersonalOrdersInfo()
                if type(infos) == "table" then
                    local lines = {}
                    for _, info in ipairs(infos) do
                        local count = tonumber(info.numPersonalOrders) or 0
                        if count > 0 then
                            local name = tostring(info.professionName or info.profession or "Unknown")
                            lines[#lines + 1] = count .. " " .. name .. " Order" .. (count > 1 and "s" or "")
                        end
                    end
                    if #lines > 0 then
                        label = label .. "\n" .. table.concat(lines, "\n")
                    end
                end
            end
            EllesmereUI.ShowWidgetTooltip(self, label, { anchor = EBS._Grow.TT(), scale = GetCustomTooltipScale() })
        end
    end)
    _customIndicators.crafting:SetScript("OnLeave", function(self)
        if craftBaseLeave then craftBaseLeave(self) end
        if EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
    end)

    -- Friends Online button
    _customIndicators.friends = CreateIndicatorBtn("_friends", minimap,
        FRIENDS_ATLAS, FRIENDS_ATLAS, nil,
        function()
            if InCombatLockdown() then
                UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.3, 0.3, 1.0)
                return
            end
            ToggleFriendsFrame()
        end)
    -- Atlas is not in INDICATOR_ATLAS_RATIO so icon uses inset anchoring
    -- (TOPLEFT/BOTTOMRIGHT). Desaturate slightly for idle state.
    if _customIndicators.friends._icon then
        _customIndicators.friends._icon:SetDesaturated(true)
        EllesmereUI.RegAccent({ type = "vertex", obj = _customIndicators.friends._icon })
        -- Apply current accent immediately (initial accent pass already ran)
        local g = EllesmereUI.ELLESMERE_GREEN
        if g then
            _customIndicators.friends._icon:SetVertexColor(g.r, g.g, g.b, 1)
        end
        _customIndicators.friends._icon:SetAlpha(0.85)
    end
    local friendsBtnEnter = _customIndicators.friends:GetScript("OnEnter")
    local friendsBtnLeave = _customIndicators.friends:GetScript("OnLeave")
    _customIndicators.friends:SetScript("OnEnter", function(self)
        if friendsBtnEnter then friendsBtnEnter(self) end
        if self._icon then self._icon:SetAlpha(1) end
        if GetFFD(self).freeMoveJustDragged then return end
        ShowFriendsTooltip(self)
    end)
    _customIndicators.friends:SetScript("OnLeave", function(self)
        if friendsBtnLeave then friendsBtnLeave(self) end
        if self._icon then self._icon:SetAlpha(0.85) end
        HideFriendsTooltip()
    end)

    -- Great Vault button (built once, anchored later in LayoutIndicatorFrames)
    _greatVaultBtn = CreateGreatVaultBtn(minimap)

    -- M+ Portal button (built once, anchored later in LayoutIndicatorFrames)
    _portalBtn = CreatePortalBtn(minimap)
end

-- Hide the Blizzard originals so they never render or intercept clicks
local function HideBlizzardIndicators()
    local tracking = MinimapCluster and MinimapCluster.Tracking
    if tracking then tracking:SetAlpha(0); tracking:EnableMouse(false) end
    local gameTime = _G.GameTimeFrame
    if gameTime then gameTime:SetAlpha(0); gameTime:EnableMouse(false) end
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if indicator then
        if indicator.MailFrame then indicator.MailFrame:SetAlpha(0); indicator.MailFrame:EnableMouse(false) end
        if indicator.CraftingOrderFrame then indicator.CraftingOrderFrame:SetAlpha(0); indicator.CraftingOrderFrame:EnableMouse(false) end
    end
end

-- Sync visibility of custom mail/crafting indicators with Blizzard state
local function SyncIndicatorVisibility()
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if _customIndicators.mail then
        local hasMail = false
        if HasNewMail then
            local raw = HasNewMail()
            if not issecretvalue or not issecretvalue(raw) then
                hasMail = raw or false
            end
        end
        _customIndicators.mail:SetShown(hasMail)
    end
    if _customIndicators.crafting then
        local blizCraft = indicator and indicator.CraftingOrderFrame
        local hasCraft = blizCraft and blizCraft:IsShown()
        _customIndicators.crafting:SetShown(hasCraft or false)
    end
end

-------------------------------------------------------------------------------
--  Mouseover Extra Buttons
--  When enabled, the extra buttons (Great Vault, M+ Portals, Friends Online,
--  Group Button) only show while the mouse is over the minimap or one of the
--  buttons. Either flyout being open keeps the stack shown until it closes.
--  Event-driven: minimap + button OnEnter/OnLeave drive it, with a small
--  deferred hide so crossing the tiny gaps between frames doesn't flicker.
-------------------------------------------------------------------------------
local _moActive  = false   -- mouseover mode currently engaged
local _moButtons = {}      -- extra buttons under control this layout
local _moHooked  = {}      -- frames whose OnEnter/OnLeave we've already hooked
local _moHideTimer = nil

local function MO_OverAny()
    if Minimap and Minimap:IsMouseOver() then return true end
    if _portalFlyout and _portalFlyout:IsShown() then return true end
    if flyoutPanel and flyoutPanel:IsShown() then return true end
    -- The friends tooltip hangs off its button and is interactive (whisper/
    -- invite rows); while it is open the stack stays shown, same as a flyout.
    -- It hides itself once the cursor truly leaves it, and its OnHide hook
    -- re-evaluates so the stack fades then.
    local ftt = EBS._friendsTT
    if ftt and ftt:IsShown() then return true end
    for i = 1, #_moButtons do
        local b = _moButtons[i]
        if b:IsShown() and b:IsMouseOver() then return true end
    end
    return false
end

local function MO_Apply(show)
    local a = show and 1 or 0
    for i = 1, #_moButtons do _moButtons[i]:SetAlpha(a) end
end

local function MO_CancelHide()
    if _moHideTimer then _moHideTimer:Cancel(); _moHideTimer = nil end
end

-- Assign the forward-declared upvalue so the flyout OnShow/OnHide hooks above
-- (defined earlier in the file) can drive a re-evaluate.
MO_Evaluate = function()
    if not _moActive then return end
    MO_CancelHide()
    if MO_OverAny() then
        MO_Apply(true)
    else
        -- Brief delay bridges the gap between adjacent frames (minimap -> button,
        -- button -> button) so crossing it doesn't flash the stack off and on.
        _moHideTimer = C_Timer.NewTimer(0.12, function()
            _moHideTimer = nil
            if _moActive and not MO_OverAny() then MO_Apply(false) end
        end)
    end
end

local function MO_HookFrame(frame)
    if not frame or _moHooked[frame] then return end
    _moHooked[frame] = true
    frame:HookScript("OnEnter", function()
        if _moActive then MO_CancelHide(); MO_Apply(true) end
    end)
    frame:HookScript("OnLeave", function()
        if _moActive then MO_Evaluate() end
    end)
end

-- Rebuild the managed-button list from the current profile + hide state, hook
-- the minimap/buttons (once), and set the initial alpha. Called at the end of
-- every indicator layout so the list reflects current visibility.
local function MO_Refresh(p)
    wipe(_moButtons)
    local heb = (p and p.hideExtraBtns) or {}
    if p and p.mouseoverExtraBtns then
        if _greatVaultBtn and not heb.greatVault then _moButtons[#_moButtons + 1] = _greatVaultBtn end
        if _customIndicators.friends and not heb.friendsOnline then _moButtons[#_moButtons + 1] = _customIndicators.friends end
        if _portalBtn and not heb.portals then _moButtons[#_moButtons + 1] = _portalBtn end
        if flyoutToggle and not heb.groupButton then _moButtons[#_moButtons + 1] = flyoutToggle end
        -- Ungrouped addon buttons count as extra buttons for this setting too.
        for _, btn in ipairs(cachedAddonButtons) do
            if _addonVisible[btn] ~= false and IsUngrouped(btn) then
                _moButtons[#_moButtons + 1] = btn
            end
        end
    end
    _moActive = (#_moButtons > 0)
    if _moActive then
        MO_HookFrame(Minimap)
        for i = 1, #_moButtons do MO_HookFrame(_moButtons[i]) end
        MO_Evaluate()
        -- Diagnostic for "stack stuck visible" reports: dumps the mouseover
        -- state so a stuck screenshot can tell us WHICH mechanism failed
        -- (our state says shown vs a foreign alpha write, what OverAny sees).
        if not SlashCmdList.EUIMO then
            SLASH_EUIMO1 = "/euimo"
            SlashCmdList.EUIMO = function()
                print(format("EUI MO: active=%s overAny=%s mapOver=%s hideTimer=%s",
                    tostring(_moActive), tostring(MO_OverAny()),
                    tostring(Minimap and Minimap:IsMouseOver()),
                    tostring(_moHideTimer ~= nil)))
                for i = 1, #_moButtons do
                    local b = _moButtons[i]
                    print(format("  %d. %s shown=%s alpha=%.2f over=%s",
                        i, b:GetName() or "(unnamed)", tostring(b:IsShown()),
                        b:GetAlpha() or 0, tostring(b:IsMouseOver())))
                end
            end
        end
    else
        MO_CancelHide()
        -- Restore full alpha (harmless on buttons hidden by hideExtraBtns).
        if _greatVaultBtn then _greatVaultBtn:SetAlpha(1) end
        if _customIndicators.friends then _customIndicators.friends:SetAlpha(1) end
        if _portalBtn then _portalBtn:SetAlpha(1) end
        if flyoutToggle then flyoutToggle:SetAlpha(1) end
        -- Restore ungrouped addon buttons we may have dimmed.
        for _, btn in ipairs(cachedAddonButtons) do
            if IsUngrouped(btn) then btn:SetAlpha(1) end
        end
    end
end

local MAIL_CORNER_POINTS = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }

local function LayoutIndicatorFrames(minimap, p, circleMode)
    local flvl = minimap:GetFrameLevel() + 10

    -- Build our custom buttons once, hide Blizzard originals
    BuildCustomIndicators(minimap)
    HideBlizzardIndicators()
    SyncIndicatorVisibility()

    local ci = _customIndicators
    local sz = GetInteractableBtnSize()
    local showBg = p.btnBackgrounds ~= false
    -- Mail Position: "button" keeps the mail indicator in the element row; a
    -- corner pins it to that map corner (same anchoring as the Omnium Folio
    -- corner option).
    local mailCorner = MAIL_CORNER_POINTS[p.mailPosition] and p.mailPosition or nil
    -- Resize buttons and update icon aspect ratios
    local inset = 3
    local avail = sz - inset * 2
    local function ResizeIndicator(btn)
        if not btn then return end
        btn:SetSize(sz, sz)
        if btn._bg then btn._bg:SetShown(showBg) end
        local ratio = btn._upAtlas and INDICATOR_ATLAS_RATIO[btn._upAtlas]
        if ratio and btn._icon then
            local scale = INDICATOR_ATLAS_SCALE[btn._upAtlas] or 1
            local iconW, iconH
            if ratio >= 1 then iconW = avail * scale; iconH = (avail / ratio) * scale
            else iconH = avail * scale; iconW = (avail * ratio) * scale end
            btn._icon:ClearAllPoints()
            btn._icon:SetSize(iconW, iconH)
            local off = btn._indicatorKey and INDICATOR_ATLAS_OFFSET[btn._indicatorKey]
            btn._icon:SetPoint("CENTER", btn, "CENTER", off and off[1] or 0, off and off[2] or 0)
        end
    end
    ResizeIndicator(ci.tracking)
    -- Update calendar day if it changed (midnight rollover)
    if ci.calendar then
        local today = tonumber(date("%d")) or 1
        if ci.calendar._calDay ~= today then
            ci.calendar._calDay = today
            local prefix = "UI-HUD-Calendar-" .. today
            ci.calendar._upAtlas = prefix .. "-Up"
            ci.calendar._overAtlas = prefix .. "-Mouseover"
            ci.calendar._downAtlas = prefix .. "-Down"
            if ci.calendar._icon then ci.calendar._icon:SetAtlas(ci.calendar._upAtlas) end
        end
    end
    ResizeIndicator(ci.calendar)
    ResizeIndicator(ci.mail)
    ResizeIndicator(ci.crafting)
    -- Corner-pinned mail renders bare: no black box, just the mail icon
    if mailCorner and ci.mail and ci.mail._bg then
        ci.mail._bg:SetShown(false)
    end
    if flyoutToggle then
        flyoutToggle:SetSize(sz, sz)
        if flyoutToggle._bg then flyoutToggle._bg:SetShown(showBg) end
        -- Reset to base anchor so free-move offsets don't accumulate across relayouts
        local rowMode = GetBtnRowMode(p)
        local rowBaseX, rowBaseY = GetRowBase(rowMode, p.btnRowDistance)
        local resES = minimap:GetEffectiveScale()
        flyoutToggle:ClearAllPoints()
        flyoutToggle:SetPoint(rowMode.point, minimap, rowMode.rel,
            PP.SnapForES(rowBaseX, resES), PP.SnapForES(rowBaseY, resES))
    end

    -- Calendar visibility
    if ci.calendar then ci.calendar:SetShown(not p.hideGameTime) end

    -- Difficulty flag (instance type/size indicator)
    local diffFrame = (MinimapCluster and MinimapCluster.InstanceDifficulty) or _G.MiniMapInstanceDifficulty
    if diffFrame then
        diffFrame:SetParent(minimap)
        diffFrame:SetFrameLevel(flvl + 2)
        diffFrame:ClearAllPoints()
        diffFrame:SetPoint("TOPRIGHT", minimap, "TOPRIGHT", 2, 1)
        -- Text mode overrides the Show Blizzard Elements choice: the flag is
        -- always suppressed while the difficulty text is enabled.
        if p.hideRaidDifficulty or p.diffTextEnabled then
            diffFrame:SetAlpha(0)
        else
            diffFrame:SetAlpha(1)
        end
    end
    if not minimap.Layout then minimap.Layout = function() end end

    if circleMode then
        -- Circle layout: horizontal row around the clock
        if ci.tracking and not p.hideTrackingButton then
            ci.tracking:ClearAllPoints()
            if clockBg and clockBg:IsShown() then
                ci.tracking:SetPoint("RIGHT", clockBg, "LEFT", 0, 0)
            else
                ci.tracking:SetPoint("TOP", minimap, "TOP", -20, -3)
            end
            ci.tracking:Show()
        elseif ci.tracking then
            ci.tracking:Hide()
        end

        if ci.calendar and not p.hideGameTime then
            ci.calendar:ClearAllPoints()
            if clockBg and clockBg:IsShown() then
                ci.calendar:SetPoint("LEFT", clockBg, "RIGHT", 0, 0)
            else
                ci.calendar:SetPoint("TOP", minimap, "TOP", 20, -3)
            end
        end

        if ci.mail and ci.mail:IsShown() then
            ci.mail:ClearAllPoints()
            if mailCorner then
                ci.mail:SetPoint(mailCorner, minimap, mailCorner, p.mailOffsetX or 0, p.mailOffsetY or 0)
            else
                ci.mail:SetPoint("RIGHT", ci.tracking, "LEFT", 0, 0)
            end
        end

        if ci.crafting and ci.crafting:IsShown() then
            ci.crafting:ClearAllPoints()
            -- Corner-pinned mail is out of the row, so crafting chains to tracking
            local anchor = (ci.mail and ci.mail:IsShown() and not mailCorner) and ci.mail or ci.tracking
            ci.crafting:SetPoint("RIGHT", anchor, "LEFT", 0, 0)
        end

        if indicatorBg then indicatorBg:Hide() end

    else
        -- Square layout: element row (corner + growth from Element Row Position).
        -- Same running-total placement as the button row: the cursor advances
        -- per element by its own size floored to whole physical pixels plus
        -- the snapped spacing, so icons stay flush at 0 spacing and gaps
        -- render identically. Using each element's real width also keeps
        -- horizontal rows flush despite the varying indicator atlas ratios.
        local rowMode = GetElementRowMode(p)
        local baseX, baseY = GetRowBase(rowMode, p.elementRowDistance)
        local elES = minimap:GetEffectiveScale()
        local elPx = PP.perfect / elES
        local elGap = PP.SnapForES(p.elementRowSpacing or 0, elES)
        local elX = PP.SnapForES(baseX, elES)
        local elY = PP.SnapForES(baseY, elES)
        local function PlaceElement(btn)
            btn:ClearAllPoints()
            btn:SetPoint(rowMode.point, minimap, rowMode.rel, elX, elY)
            local adv = (rowMode.dirX ~= 0) and btn:GetWidth() or btn:GetHeight()
            adv = math.floor(adv / elPx + 0.001) * elPx + elGap
            elX = elX + adv * rowMode.dirX
            elY = elY + adv * rowMode.dirY
        end

        if ci.tracking and not p.hideTrackingButton then
            PlaceElement(ci.tracking)
            ci.tracking:Show()
        elseif ci.tracking then
            ci.tracking:Hide()
        end

        if ci.calendar and not p.hideGameTime then
            PlaceElement(ci.calendar)
        end

        if ci.mail and ci.mail:IsShown() then
            if mailCorner then
                ci.mail:ClearAllPoints()
                ci.mail:SetPoint(mailCorner, minimap, mailCorner, p.mailOffsetX or 0, p.mailOffsetY or 0)
            else
                PlaceElement(ci.mail)
            end
        end

        if ci.crafting and ci.crafting:IsShown() then
            PlaceElement(ci.crafting)
        end

        if indicatorBg then indicatorBg:Hide() end
    end

    -- Position ungrouped buttons along the button row (the flyout toggle is
    -- the row's first slot; corner + growth come from Button Row Position)
    if flyoutToggle then
        local rowMode = GetBtnRowMode(p)
        local rowBaseX, rowBaseY = GetRowBase(rowMode, p.btnRowDistance)
        local ungroupBtnSize = GetInteractableBtnSize()
        -- Running-total placement: the row cursor starts at the snapped
        -- Distance from Map and advances per button by its own size FLOORED
        -- to whole physical pixels (rounding up would open hairline seams
        -- between flush icons at 0 spacing; flooring can only overlap-flush)
        -- plus the snapped Icon Spacing. Every anchor lands on the physical
        -- pixel grid and every gap renders identically.
        local rowES = minimap:GetEffectiveScale()
        local rowPx = PP.perfect / rowES
        local rowGap = PP.SnapForES(p.btnRowSpacing or 0, rowES)
        local rowX = PP.SnapForES(rowBaseX, rowES)
        local rowY = PP.SnapForES(rowBaseY, rowES)
        local function PlaceRowButton(btn)
            btn:SetPoint(rowMode.point, minimap, rowMode.rel, rowX, rowY)
            local adv = (rowMode.dirX ~= 0) and btn:GetWidth() or btn:GetHeight()
            adv = math.floor(adv / rowPx + 0.001) * rowPx + rowGap
            rowX = rowX + adv * rowMode.dirX
            rowY = rowY + adv * rowMode.dirY
        end
        flyoutToggle:ClearAllPoints()
        local flyoutVisible = flyoutToggle:IsShown()
        if flyoutVisible then
            PlaceRowButton(flyoutToggle)
        else
            flyoutToggle:SetPoint(rowMode.point, minimap, rowMode.rel, rowX, rowY)
        end
        local mp = EBS.db and EBS.db.profile.minimap
        local ungrouped = {}
        for _, btn in ipairs(cachedAddonButtons) do
            if _addonVisible[btn] ~= false and IsUngrouped(btn) then
                local name = btn:GetName()
                local order = mp and mp.ungroupedButtons and mp.ungroupedButtons[name] or 999
                if type(order) == "boolean" then order = 999 end
                ungrouped[#ungrouped + 1] = { btn = btn, order = order }
            end
        end
        table.sort(ungrouped, function(a, b) return a.order < b.order end)
        for idx, entry in ipairs(ungrouped) do
            local btn = entry.btn
            -- Restore from flyout if needed
            if flyoutSavedParents[btn] then
                if GetFFD(btn).flyoutRing then GetFFD(btn).flyoutRing:Hide() end
                if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(false) end
                if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(false) end
                flyoutSavedParents[btn] = nil
            end
            btn:SetParent(minimap)
            btn:SetFrameLevel(minimap:GetFrameLevel() + 11)
            btn:ClearAllPoints()
            if showBg then
                -- Strip BEFORE resize so the snapshot captures the real
                -- native size, not our modified ungroupBtnSize.
                StripButtonDecorations(btn)
                btn:SetSize(ungroupBtnSize, ungroupBtnSize)
            end
            PlaceRowButton(btn)
            btn:SetMovable(false)
            btn:RegisterForDrag()
            btn:SetScript("OnDragStart", nil)
            btn:SetScript("OnDragStop", nil)
            if showBg then
                local icon = btn.icon or btn.Icon
                if not icon then
                    for _, region in ipairs({ btn:GetRegions() }) do
                        if region:IsObjectType("Texture") and region:IsShown()
                           and region:GetAlpha() > 0 and not IsJunkTexture(region)
                           and region ~= GetFFD(btn).ungroupBg then
                            icon = region
                            break
                        end
                    end
                end
                if icon then
                    icon:ClearAllPoints()
                    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
                    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
                    pcall(icon.SetTexCoord, icon, 0.05, 0.95, 0.05, 0.95)
                    -- Foreign button icon: SetTexCoord was its only snap trigger
                    -- and that hook is no longer global, so disable snap once here.
                    if EllesmereUI.PP then EllesmereUI.PP.DisablePixelSnap(icon) end
                end
                -- Black square background
                if not GetFFD(btn).ungroupBg then
                    local ubg = CreateFrame("Frame", nil, btn, "BackdropTemplate")
                    ubg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
                    ubg:SetBackdropColor(0, 0, 0, 0.8)
                    ubg:SetAllPoints(btn)
                    GetFFD(btn).ungroupBg = ubg
                end
                -- Re-assert strata/level every layout; the flyout child-loop
                -- bumps all children to DIALOG which would render the bg
                -- above the icon after ungrouping.
                local ubg = GetFFD(btn).ungroupBg
                ubg:SetFrameStrata(btn:GetFrameStrata())
                ubg:SetFrameLevel(btn:GetFrameLevel() - 1)
                ubg:Show()
                if btn._ungroupRing then btn._ungroupRing:Hide() end
            else
                -- No backgrounds: restore native appearance, hide our overlays.
                -- Do NOT override button size — native ring textures have fixed
                -- anchors that only look correct at the button's original size.
                RestoreButtonDecorations(btn)
                if GetFFD(btn).ungroupBg then GetFFD(btn).ungroupBg:Hide() end
                if btn._ungroupRing then btn._ungroupRing:Hide() end
            end
            _suppressVisTrack = true
            btn:SetAlpha(1)
            btn:Show()
            _suppressVisTrack = false
        end

        -- Extra buttons: Great Vault, M+ Portals, Friends Online
        -- Visibility controlled by hideExtraBtns table
        local heb = p.hideExtraBtns or {}

        -- Extra buttons: Great Vault, Friends Online, M+ Portals. Visibility
        -- from hideExtraBtns; row order from extraBtnOrder (drag-to-reorder
        -- in options; nil = default order in the fallback list below).
        local function PlaceExtraButton(key)
            if key == "greatVault" then
                if _greatVaultBtn then
                    if heb.greatVault then
                        _greatVaultBtn:Hide()
                    else
                        SizeGreatVaultBtn(_greatVaultBtn, showBg)
                        _greatVaultBtn:SetParent(minimap)
                        _greatVaultBtn:SetFrameLevel(minimap:GetFrameLevel() + 11)
                        _greatVaultBtn:ClearAllPoints()
                        PlaceRowButton(_greatVaultBtn)
                        _greatVaultBtn:Show()
                    end
                end
            elseif key == "friendsOnline" then
                if ci.friends then
                    if heb.friendsOnline then
                        ci.friends:Hide()
                    else
                        ci.friends:SetSize(sz, sz)
                        if ci.friends._bg then ci.friends._bg:SetShown(showBg) end
                        ci.friends:SetParent(minimap)
                        ci.friends:SetFrameLevel(minimap:GetFrameLevel() + 11)
                        ci.friends:ClearAllPoints()
                        PlaceRowButton(ci.friends)
                        ci.friends:Show()
                    end
                end
            elseif key == "portals" then
                if _portalBtn then
                    if heb.portals then
                        _portalBtn:Hide()
                    else
                        SizePortalBtn(_portalBtn, showBg)
                        _portalBtn:SetParent(minimap)
                        _portalBtn:SetFrameLevel(minimap:GetFrameLevel() + 11)
                        _portalBtn:ClearAllPoints()
                        PlaceRowButton(_portalBtn)
                        _portalBtn:Show()
                    end
                end
            end
        end
        local placedExtra = {}
        if type(p.extraBtnOrder) == "table" then
            for _, key in ipairs(p.extraBtnOrder) do
                if not placedExtra[key] then placedExtra[key] = true; PlaceExtraButton(key) end
            end
        end
        -- Safety net: place anything a stale saved order is missing
        for _, key in ipairs({ "greatVault", "friendsOnline", "portals" }) do
            if not placedExtra[key] then placedExtra[key] = true; PlaceExtraButton(key) end
        end

        -- Flyout toggle (EUI group button for addon icons)
        if flyoutToggle and heb.groupButton then
            flyoutToggle:Hide()
        end
    end

    -- Free Move: hook shift+drag on all indicator buttons and apply saved offsets
    local heb = p.hideExtraBtns or {}
    local freeMove = p.freeMoveBtns
    local fmTargets = {}
    if ci.tracking and not p.hideTrackingButton then fmTargets[#fmTargets + 1] = ci.tracking end
    if ci.calendar and not p.hideGameTime then fmTargets[#fmTargets + 1] = ci.calendar end
    if ci.mail then fmTargets[#fmTargets + 1] = ci.mail end
    if ci.crafting then fmTargets[#fmTargets + 1] = ci.crafting end
    if flyoutToggle then fmTargets[#fmTargets + 1] = flyoutToggle end
    if _greatVaultBtn and not heb.greatVault then fmTargets[#fmTargets + 1] = _greatVaultBtn end
    if _portalBtn and not heb.portals then fmTargets[#fmTargets + 1] = _portalBtn end
    if ci.friends and not heb.friendsOnline then fmTargets[#fmTargets + 1] = ci.friends end
    -- Include ungrouped addon buttons
    for _, btn in ipairs(cachedAddonButtons) do
        if _addonVisible[btn] ~= false and IsUngrouped(btn) then
            fmTargets[#fmTargets + 1] = btn
        end
    end
    for _, frame in ipairs(fmTargets) do
        EnableFreeMove(frame)
        if freeMove then
            ApplyBtnOffset(frame)
        end
    end

    -- Mouseover Extra Buttons: apply after layout so the managed-button list and
    -- their alpha reflect the current shown/hidden state.
    MO_Refresh(p)
end

local function RestoreIndicatorFrames()
    -- Hide our custom indicator buttons
    for _, btn in pairs(_customIndicators) do
        if btn and btn.Hide then btn:Hide() end
    end
    -- Restore Blizzard originals
    local tracking = MinimapCluster and MinimapCluster.Tracking
    if tracking then tracking:SetAlpha(1); tracking:EnableMouse(true) end
    local gameTime = _G.GameTimeFrame
    if gameTime then gameTime:SetAlpha(1); gameTime:EnableMouse(true) end
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if indicator then
        if indicator.MailFrame then indicator.MailFrame:SetAlpha(1); indicator.MailFrame:EnableMouse(true) end
        if indicator.CraftingOrderFrame then indicator.CraftingOrderFrame:SetAlpha(1); indicator.CraftingOrderFrame:EnableMouse(true) end
    end
    if indicatorBg then indicatorBg:Hide() end
end

-------------------------------------------------------------------------------
-- Snapshot Blizzard minimap size and position on first install.
-- Captures the native size and center position so our module starts matching
-- whatever the user had via Edit Mode. Only runs once per profile.
-------------------------------------------------------------------------------
local function CaptureBlizzardMinimap()
    local minimap = Minimap
    if not minimap then return end
    local p = EBS.db.profile.minimap
    if p._capturedOnce then return end

    local uiScale = UIParent:GetEffectiveScale()
    local mScale  = minimap:GetEffectiveScale()
    local ratio   = mScale / uiScale

    -- Capture size (use the larger dimension to keep it square)
    local w, h = minimap:GetWidth(), minimap:GetHeight()
    if w and w > 10 then
        local sz = math.floor(math.max(w, h) * ratio + 0.5)
        p.mapSize = sz
    end

    -- Capture center position as CENTER/CENTER offset from UIParent
    local cx, cy = minimap:GetCenter()
    if cx and cy then
        local uiW, uiH = UIParent:GetSize()
        cx = cx * ratio
        cy = cy * ratio
        p.position = {
            point = "CENTER", relPoint = "CENTER",
            x = cx - (uiW / 2), y = cy - (uiH / 2),
        }
    end

    p._capturedOnce = true
end

-- Expansion landing page button ("Omnium Folio"). Kept off the addon-button
-- flyout (see flyoutBlacklist); we anchor it to the minimap's bottom-left and
-- raise it above the minimap. We do NOT force it visible -- Blizzard controls
-- when the current landing page button appears (so we never display a stale
-- old-expansion button). The setting only HIDES it when off.
-- It is a plain (non-secure) Blizzard button, so SetParent/SetPoint are safe.
local _omniumFolioHooked = false

-- Folio visibility mode with legacy fallback: pre-dropdown data carries the
-- showOmniumFolio toggle (default ON; only false is ever stored).
local function GetOmniumFolioMode(mp)
    if not mp then return "always" end
    if mp.omniumFolioMode then return mp.omniumFolioMode end
    if mp.showOmniumFolio == false then return "never" end
    return "always"
end

-- Re-entrancy guard: PositionOmniumFolio calls SetParent/SetScale/SetPoint, all
-- of which we hook below. The guard stops our own writes from recursing.
local _omniumFolioApplying = false
local function PositionOmniumFolio(btn)
    if not btn or not Minimap then return end
    local mp = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if not mp then return end
    _omniumFolioApplying = true
    if btn:GetParent() ~= Minimap then btn:SetParent(Minimap) end
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10)
    btn:SetScale(mp.omniumFolioScale or 0.75)
    btn:ClearAllPoints()
    -- Anchor the button's chosen corner to the minimap's same corner; X/Y nudge from
    -- there (positive X = right, positive Y = up, regardless of corner).
    local corner = mp.omniumFolioCorner or "BOTTOMLEFT"
    btn:SetPoint(corner, Minimap, corner, mp.omniumFolioX or 0, mp.omniumFolioY or 0)
    _omniumFolioApplying = false
end

-- True while the cursor is over the map region OR the hover-mode folio
-- itself: the folio (anchored to a map corner at reduced scale) can overhang
-- the minimap rect, and treating that sliver as "left the map" let the exit
-- watcher hide the button under the cursor -- after which re-entry via the
-- folio's own OnEnter no-oped on the same rect check.
-- The 4px slop matters: OnEnter fires the instant the ENGINE's focus test
-- passes -- cursor at the exact edge pixel -- while this Lua-side rect test
-- converts cursor coords through effective scale and can round the other
-- way by a sub-pixel right at the boundary (resolution/scale dependent,
-- which is why it repros on some machines only). Expanding the test rect
-- makes "engine says entered" always imply "this test passes".
function EBS._HoverStillOver(minimap)
    if minimap:IsMouseOver(4, -4, -4, 4) then return true end
    local b = _G.ExpansionLandingPageMinimapButton
    if b and b:IsShown() and b:IsMouseOver(4, -4, -4, 4) then return true end
    return false
end

-- Immediate hide for the map-region hover elements (zoom buttons, hover-mode
-- folio and coordinates): fired straight from the minimap's OnLeave on a real
-- exit so everything disappears the same instant Blizzard's own zoom fade
-- starts, and from the exit watcher for exits ACROSS a child element (which
-- never fire a second minimap OnLeave). Cancels the watcher itself.
function EBS._HVHideNow()
    local minimap = Minimap
    if not minimap then return end
    local ffd = GetFFD(minimap)
    if ffd.hvWatcher then
        ffd.hvWatcher:Cancel()
        ffd.hvWatcher = nil
    end
    local zi, zo = minimap.ZoomIn, minimap.ZoomOut
    if zi then zi:Hide() end
    if zo then zo:Hide() end
    local m2 = EBS.db and EBS.db.profile.minimap
    if m2 then
        if GetOmniumFolioMode(m2) == "hover" then
            local b = _G.ExpansionLandingPageMinimapButton
            if b then b:Hide() end
        end
        if GetCoordsModePos(m2) == "hover" then
            if coordFrame then coordFrame:Hide() end
            if coordTicker then coordTicker:Hide() end
        end
    end
    -- Mouseover Extra Buttons hide in the SAME instant as the rest: the
    -- 0.12s deferral bridges gap-crossings BETWEEN stack frames mid-hover,
    -- but on a true region exit there is nothing to bridge. If the cursor
    -- is still over part of the stack (a row button, the open flyouts, the
    -- friends tooltip), OverAny keeps it shown via the normal path.
    if _moActive then
        if MO_OverAny() then
            if MO_Evaluate then MO_Evaluate() end
        else
            MO_CancelHide()
            MO_Apply(false)
        end
    end
end

-- Central map-region hover reveal (declared as an EBS field at the top of the
-- file). Fired from the minimap's OnEnter/OnLeave AND from over-map child
-- elements' OnEnter (clock, FPS text, corner mail, the folio itself): no-ops
-- unless the cursor is over the map region, reveals the zoom buttons and the
-- hover-mode folio, and runs one self-cancelling watcher (kept on the
-- minimap's FFD data) that hides them again once the cursor truly leaves --
-- including exits FROM a child, which never fire a second minimap OnLeave.
function EBS._HVRevealMapHover()
    local minimap = Minimap
    if not minimap then return end
    local ffd = GetFFD(minimap)
    if not ffd.active then return end
    if not EBS._HoverStillOver(minimap) then
        -- OnEnter is SINGLE-SHOT per hover: if this check fails at the
        -- boundary, nothing ever re-attempts the reveal for the whole
        -- hover (slow entries dwell at the boundary, so they failed
        -- consistently). Retry briefly -- a slow cursor is measurably
        -- inside within a tick or two; self-cancels when clearly gone.
        if not ffd.hvRetry then
            local tries = 0
            ffd.hvRetry = C_Timer.NewTicker(0.1, function()
                tries = tries + 1
                if EBS._HoverStillOver(minimap) then
                    ffd.hvRetry:Cancel(); ffd.hvRetry = nil
                    EBS._HVRevealMapHover()
                elseif tries >= 8 then
                    ffd.hvRetry:Cancel(); ffd.hvRetry = nil
                end
            end)
        end
        return
    end
    if ffd.hvRetry then ffd.hvRetry:Cancel(); ffd.hvRetry = nil end
    local mp = EBS.db and EBS.db.profile.minimap
    if not mp then return end
    local function raiseZoom()
        local zi, zo = minimap.ZoomIn, minimap.ZoomOut
        if UIFrameFadeRemoveFrame then
            if zi then UIFrameFadeRemoveFrame(zi) end
            if zo then UIFrameFadeRemoveFrame(zo) end
        end
        if zi then zi:SetAlpha(1); zi:Show() end
        if zo then zo:SetAlpha(1); zo:Show() end
    end
    if not mp.hideZoomButtons then
        raiseZoom()
    end
    if GetOmniumFolioMode(mp) == "hover" then
        local b = _G.ExpansionLandingPageMinimapButton
        if b then
            PositionOmniumFolio(b)
            if not b:IsShown() and b.RefreshButton then b:RefreshButton(true) end
        end
    end
    if GetCoordsModePos(mp) == "hover" then
        if coordFrame then coordFrame:Show() end
        if coordTicker then coordTicker:Show() end
        UpdateCoords()
    end
    -- Mouseover Extra Buttons share the same "map region hovered" notion;
    -- MO_Evaluate self-guards when that feature is off.
    if MO_Evaluate then MO_Evaluate() end
    if ffd.hvWatcher then return end
    ffd.hvWatcher = C_Timer.NewTicker(0.2, function()
        if EBS._HoverStillOver(minimap) then
            -- Still over the map region: keep defeating Blizzard's fader,
            -- which may have been re-armed by an intervening OnLeave.
            local m2 = EBS.db and EBS.db.profile.minimap
            if m2 and not m2.hideZoomButtons then
                raiseZoom()
            end
            return
        end
        EBS._HVHideNow()
    end)
end

local function ApplyOmniumFolio()
    local btn = _G.ExpansionLandingPageMinimapButton
    if not btn or not Minimap then return end
    local mp = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if not mp then return end

    -- One-time persistent hooks. Blizzard re-anchors/re-scales/re-parents this
    -- button after loading screens (RefreshButton, edit-mode relayout, etc.),
    -- often WITHOUT calling Show(), so a Show-only hook lets it drift back to
    -- Blizzard's default TOPLEFT anchor inside the alpha-0 MinimapCluster --
    -- which reads as "wrong position/scale" or "missing button" until /reload.
    -- Re-assert our state on every parent/point/scale change as well as Show.
    if not _omniumFolioHooked then
        _omniumFolioHooked = true
        local function reassert(self)
            if _omniumFolioApplying then return end
            local m = EBS.db and EBS.db.profile and EBS.db.profile.minimap
            if not m then return end
            local mode = GetOmniumFolioMode(m)
            -- Same boundary-tolerant check as the reveal path: RefreshButton
            -- Hide()/Show()s the button, and a raw IsMouseOver here could
            -- veto that Show at the exact edge for the same rounding reason.
            if mode == "never"
               or (mode == "hover" and not (Minimap and EBS._HoverStillOver(Minimap))) then
                self:Hide()
            else
                PositionOmniumFolio(self)
            end
        end
        hooksecurefunc(btn, "Show", reassert)
        hooksecurefunc(btn, "SetParent", reassert)
        hooksecurefunc(btn, "SetPoint", reassert)
        hooksecurefunc(btn, "SetScale", reassert)
        -- Hovering the folio itself counts as hovering the map region: keep
        -- the hover-reveal elements alive (the reveal path also handles the
        -- case where the cursor ENTERS the map directly on the folio).
        btn:HookScript("OnEnter", function() EBS._HVRevealMapHover() end)
    end

    local mode = GetOmniumFolioMode(mp)
    if mode == "never" then
        btn:Hide()
        return
    end
    if mode == "hover" and not Minimap:IsMouseOver() then
        btn:Hide()
        return
    end
    -- Enabled: position/raise, then make sure it's actually visible. Blizzard
    -- Shows this button itself when the ExpansionLandingPage overlay applies,
    -- but that "OverlayChanged" event can fire before the button registers its
    -- callback (seen after /reload and zoning), leaving it stuck at its XML
    -- hidden default even though it exists and is allowed. When it's hidden,
    -- nudge Blizzard's own RefreshButton: it re-runs the real show/hide decision
    -- (hides when ShouldShow is false or in an empty Garrison) and repaints the
    -- CURRENT expansion icon, so this never forces a stale button -- unlike a
    -- raw Show(). The Show() it issues re-fires our reposition hook.
    PositionOmniumFolio(btn)
    if not btn:IsShown() and btn.RefreshButton then
        btn:RefreshButton(true)
    end
end

local function ApplyMinimap()
    if TEMP_DISABLED.minimap then return end
    if InCombatLockdown() then QueueApplyAll(); return end

    local p = EBS.db.profile.minimap
    p.enabled = true

    -- Rotate Minimap: enforce the CVar to match our setting. Default off keeps
    -- it at 0; turning it on sets 1. Runs out of combat (ApplyMinimap defers).
    SetCVar("rotateMinimap", p.rotateMinimap and "1" or "0")

    local minimap = Minimap
    if not minimap then return end

    if not p.enabled then
        -- If we never touched the minimap this session, do absolutely nothing.
        -- This ensures zero interference with other minimap addons.
        if not GetFFD(minimap).active then return end
        -- Module was active but is now disabled; a reload is required to
        -- cleanly hand control back to Blizzard. The options toggle handles
        -- prompting the user for a reload.
        return
    end

    -- Ensure Blizzard_TimeManager is loaded so GameTimeFrame (calendar) exists
    if not _G.GameTimeFrame and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_TimeManager")
    end

    -- Snapshot Blizzard's native size/position before we modify anything
    CaptureBlizzardMinimap()

    -- Reparent minimap to UIParent so MinimapCluster layout cannot override our size.
    -- Deferred via C_Timer.After(0) to avoid tainting the secure frame environment
    -- when ApplyMinimap fires during a ShowUIPanel/World Map open sequence, which
    -- would cause ADDON_ACTION_BLOCKED when Blizzard's dungeon pin data provider
    -- later calls the protected SetPropagateMouseClicks() on map pins.
    local needsReparent = minimap:GetParent() ~= UIParent
    local needsClusterHide = MinimapCluster and MinimapCluster:IsShown()
    if needsReparent or needsClusterHide then
        C_Timer.After(0, function()
            if InCombatLockdown() then return end
            if needsReparent and minimap:GetParent() ~= UIParent then
                minimap:SetParent(UIParent)
            end
            if needsClusterHide and MinimapCluster then
                MinimapCluster:SetAlpha(0)
                MinimapCluster:EnableMouse(false)
            end
        end)
    end
    -- Guard reparent: Blizzard reparents the minimap during housing transitions
    -- and other events. Hook SetParent to force it back to UIParent.
    if not GetFFD(minimap).parentGuard then
        GetFFD(minimap).parentGuard = true
        hooksecurefunc(minimap, "SetParent", function()
            if minimap:GetParent() ~= UIParent then
                if not InCombatLockdown() then
                    minimap:SetParent(UIParent)
                end
            end
        end)
        -- Lock strata/level so Blizzard can't change them during transitions
        if minimap.SetFixedFrameStrata then minimap:SetFixedFrameStrata(true) end
        if minimap.SetFixedFrameLevel then minimap:SetFixedFrameLevel(true) end
    end
    -- Visibility-aware terminal: an unconditional Show() here force-showed
    -- the minimap for a frame on EVERY rebuild (visible blink for users with
    -- visibility "never"/mouseover -- e.g. settings-override transitions run
    -- this as the module refresher), with the corrective Hide only arriving
    -- via the deferred visibility sweep. Render the profile's visibility
    -- directly instead.
    do
        local vis = EllesmereUI.EvalVisibility and p and EllesmereUI.EvalVisibility(p)
        if not EllesmereUI.EvalVisibility or vis == true then
            minimap:SetAlpha(1)
            minimap:Show()
        elseif vis == "mouseover" then
            minimap:SetAlpha(0)
            minimap:Show()
        elseif vis then
            minimap:SetAlpha(1)
            minimap:Show()
        else
            minimap:Hide()
        end
    end

    -- Middle-click interceptor: prevent minimap ping on middle-click,
    -- route middle-click to our micro menu instead.
    -- Transparent frame on top of minimap that passes left/right clicks through
    -- but intercepts middle-click. Zero taint risk.
    -- It is also the SQUARE mouse surface: the Minimap's own hit region stays
    -- circular, so wheel zoom handled on the Minimap dies in the square skin's
    -- corners -- the overlay covers the full rect and handles the wheel there.
    if not GetFFD(minimap).pingBlocker then
        local blocker = CreateFrame("Frame", nil, minimap)
        blocker:SetAllPoints()
        blocker:SetFrameLevel(minimap:GetFrameLevel() + 10)
        blocker:SetPassThroughButtons("LeftButton", "RightButton")
        blocker:SetPropagateMouseMotion(true)
        blocker:SetScript("OnMouseUp", function(_, btn)
            if btn == "MiddleButton" and EBS._ToggleMicroMenu then
                -- Gated by the "Open Micro Menu on Middle Click" toggle (read live)
                local mp = EBS.db and EBS.db.profile and EBS.db.profile.minimap
                if mp and mp.openMicroMenuOnMiddleClick == false then return end
                EBS._ToggleMicroMenu()
            end
        end)
        blocker:SetScript("OnMouseWheel", function(_, delta)
            local mp = EBS.db and EBS.db.profile.minimap
            if not mp or not mp.scrollZoom then return end
            local zoom = minimap:GetZoom()
            if delta > 0 then
                zoom = min(zoom + 1, 5)
            else
                zoom = max(zoom - 1, 0)
            end
            minimap:SetZoom(zoom)
            SaveZoomLevel()
        end)
        -- Map-region hover reveal, entry-path-proof: the Minimap's own
        -- motion focus follows its CIRCULAR hit region, so entering the
        -- square skin through a corner (or directly onto an unhooked child)
        -- never fires the Minimap's OnEnter -- the reveal simply had no
        -- caller on those paths. This overlay covers the FULL square rect
        -- and, with SetPropagateMouseMotion, receives enter/leave while
        -- still passing motion through -- one hook here covers every entry.
        -- _HVRevealMapHover self-guards (region check + watcher dedupe).
        blocker:HookScript("OnEnter", function()
            if EBS._HVRevealMapHover then EBS._HVRevealMapHover() end
        end)
        GetFFD(minimap).pingBlocker = blocker
    end

    -- Hide default decorations
    for _, name in ipairs(minimapDecorations) do
        local frame = _G[name]
        if frame then frame:Hide() end
    end
    -- Hide AddonCompartmentFrame by reparenting to a hidden frame
    local compartment = _G.AddonCompartmentFrame
    if compartment then
        if not EBS._hiddenFrame then
            EBS._hiddenFrame = CreateFrame("Frame")
            EBS._hiddenFrame:Hide()
        end
        GetFFD(compartment).origParent = GetFFD(compartment).origParent or compartment:GetParent()
        compartment:SetParent(EBS._hiddenFrame)
    end

    local isCircle = (p.shape == "circle" or p.shape == "textured_circle")

    -- Hide background (no black bg behind minimap)
    if GetFFD(minimap).bg then GetFFD(minimap).bg:SetAlpha(0) end

    -- Border
    local r, g, b, borderA = GetBorderStyleColor(p)
    -- Hide the circular quest area ring on square minimaps
    if minimap.SetArchBlobRingScalar then
        minimap:SetArchBlobRingScalar(isCircle and 1 or 0)
    end
    if minimap.SetQuestBlobRingScalar then
        minimap:SetQuestBlobRingScalar(isCircle and 1 or 0)
    end

    if p.shape == "square" then
        -- Square: shared border-style engine (solid = PP strips, textured =
        -- BackdropTemplate) on a dedicated host frame -- the engine shows and
        -- hides the host freely, so it must never be the Minimap itself.
        local bs = p.borderSize or 1
        local host = GetFFD(minimap).borderHost
        if not host then
            host = CreateFrame("Frame", nil, minimap)
            host:SetAllPoints(minimap)
            host:EnableMouse(false)
            GetFFD(minimap).borderHost = host
        end
        -- Same level as the minimap keeps the border under all child buttons
        -- (matching the old strips-on-minimap rendering); Show Behind drops it
        -- under the map surface for the Shadow style.
        host:SetFrameLevel(p.borderBehind and math.max(0, minimap:GetFrameLevel() - 1) or minimap:GetFrameLevel())
        host:SetAlpha(1)
        EllesmereUI.ApplyBorderStyle(host, bs, r, g, b, borderA,
            p.borderTexture or "solid",
            p.borderTextureOffset, p.borderTextureOffsetY,
            p.borderTextureShiftX, p.borderTextureShiftY,
            "minimap", bs)
        if GetFFD(minimap).circBorder then GetFFD(minimap).circBorder:Hide() end
        if GetFFD(minimap).texCircBorder then GetFFD(minimap).texCircBorder:Hide() end
    elseif p.shape == "circle" then
        -- Circle: solid colored disc behind the minimap, slightly larger = border ring
        if GetFFD(minimap).borderHost then GetFFD(minimap).borderHost:Hide() end
        if not GetFFD(minimap).circBorder then
            local disc = CreateFrame("Frame", nil, minimap)
            disc:SetFrameLevel(minimap:GetFrameLevel() - 1)
            local tex = disc:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints(disc)
            tex:SetTexture("Interface\\Common\\CommonMaskCircle")
            disc._tex = tex
            GetFFD(minimap).circBorder = disc
        end
        local bs = p.borderSize or 1
        local circBorder = GetFFD(minimap).circBorder
        circBorder:ClearAllPoints()
        circBorder:SetPoint("TOPLEFT", minimap, "TOPLEFT", -bs, bs)
        circBorder:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", bs, -bs)
        circBorder._tex:SetVertexColor(r, g, b, 1)
        circBorder:Show()
        if GetFFD(minimap).texCircBorder then GetFFD(minimap).texCircBorder:Hide() end
    elseif p.shape == "textured_circle" then
        -- Textured Circle: void ring border, hide the solid circle border
        if GetFFD(minimap).borderHost then GetFFD(minimap).borderHost:Hide() end
        if GetFFD(minimap).circBorder then GetFFD(minimap).circBorder:Hide() end
        if not GetFFD(minimap).texCircBorder then
            local ring = minimap:CreateTexture(nil, "OVERLAY", nil, 7)
            ring:SetAtlas("wowlabs_minimapvoid-ring-single")
            GetFFD(minimap).texCircBorder = ring
        end
        local inset = 2
        local texCircBorder = GetFFD(minimap).texCircBorder
        texCircBorder:ClearAllPoints()
        texCircBorder:SetPoint("TOPLEFT", minimap, "TOPLEFT", -inset, inset)
        texCircBorder:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", inset, -inset)
        texCircBorder:SetVertexColor(r, g, b, 1)
        texCircBorder:Show()
    end

    -- Live-update border when accent color changes. Only applies while the
    -- border actually resolves to the accent (accent swatch active, no class
    -- colour override).
    if p.useClassColor and not p.borderUseClassColor then
        if not GetFFD(minimap).accentBorderCB then
            GetFFD(minimap).accentBorderCB = function(ar, ag, ab)
                -- Registration outlives mode switches: re-check that the
                -- border still resolves to the accent before recoloring.
                local mp = EBS.db and EBS.db.profile.minimap
                if not mp or not mp.useClassColor or mp.borderUseClassColor then return end
                local host = GetFFD(minimap).borderHost
                if host and host:IsShown() then
                    EllesmereUI.SetBorderStyleColor(host, ar, ag, ab, 1)
                end
                local cb = GetFFD(minimap).circBorder
                if cb and cb:IsShown() then
                    cb._tex:SetVertexColor(ar, ag, ab, 1)
                end
                local tcb = GetFFD(minimap).texCircBorder
                if tcb and tcb:IsShown() then
                    tcb:SetVertexColor(ar, ag, ab, 1)
                end
            end
        end
        EllesmereUI.RegAccent({ type = "callback", fn = GetFFD(minimap).accentBorderCB })
    end

    -- Size
    minimap:SetScale(1.0)
    local mapSize = p.mapSize or 140
    minimap:SetSize(mapSize, mapSize)
    -- Shape mask
    local maskID = isCircle and 186178 or 130937
    minimap:SetMaskTexture(maskID)
    -- Custom housing overlay: our own texture behind the minimap that shows
    -- the housing indoor map when Blizzard hides the real minimap content.
    -- Fully owned by us, no Blizzard frame manipulation.
    if not GetFFD(minimap).housingTex then
        local frame = CreateFrame("Frame", nil, minimap)
        frame:SetAllPoints(minimap)
        frame:SetFrameLevel(minimap:GetFrameLevel() + 1)
        local tex = frame:CreateTexture(nil, "ARTWORK")
        if isCircle then
            local inset = -mapSize * 0.10
            tex:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
            tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        else
            tex:SetAllPoints(frame)
        end
        if isCircle then
            local mask = frame:CreateMaskTexture()
            mask:SetAllPoints(frame)
            mask:SetTexture(maskID)
            tex:AddMaskTexture(mask)
            frame._mask = mask
        end
        frame._isCircle = isCircle
        frame._tex = tex
        frame:Hide()
        GetFFD(minimap).housingFrame = frame
        GetFFD(minimap).housingTex = tex
        -- Watch for MinimapBackdrop atlas changes to detect housing
        local backdrop = _G.MinimapBackdrop
        if backdrop then
            local function CheckHousing()
                local housingAtlas
                for ri = 1, backdrop:GetNumRegions() do
                    local rgn = select(ri, backdrop:GetRegions())
                    if rgn and rgn.GetAtlas then
                        local atlas = rgn:GetAtlas()
                        if atlas and atlas:find("housing") then
                            housingAtlas = atlas
                            break
                        end
                    end
                end
                if housingAtlas then
                    if frame._isCircle then
                        tex:SetAtlas(housingAtlas)
                    else
                        tex:SetTexture("Interface\\AddOns\\EllesmereUIMinimap\\Media\\housing-minimap.png")
                    end
                    frame:Show()
                else
                    frame:Hide()
                end
            end
            -- Check on zone transitions
            if not GetFFD(minimap).housingZoneHook then
                GetFFD(minimap).housingZoneHook = true
                local zf = CreateFrame("Frame")
                zf:RegisterEvent("PLAYER_ENTERING_WORLD")
                zf:RegisterEvent("ZONE_CHANGED_NEW_AREA")
                zf:RegisterEvent("ZONE_CHANGED_INDOORS")
                zf:SetScript("OnEvent", function()
                    C_Timer.After(0.5, CheckHousing)
                end)
            end
        end
    else
        -- Update existing housing frame on reapply
        local frame = GetFFD(minimap).housingFrame
        if frame then
            frame:SetFrameLevel(minimap:GetFrameLevel() + 1)
            if frame._mask then
                frame._mask:SetTexture(maskID)
            elseif not isCircle and frame._mask then
                -- Switched to square, remove mask
            end
        end
    end
    -- Clamp to screen so the border never extends off-screen
    minimap:SetClampedToScreen(true)
    local bInset = isCircle and (p.borderSize or 1) or 0
    minimap:SetClampRectInsets(-bInset, bInset, bInset, -bInset)
    -- Force the minimap engine to re-render at the new size.
    -- Nudge zoom to a different value then immediately restore (same frame).
    local curZoom = minimap:GetZoom()
    minimap:SetZoom(curZoom > 0 and 0 or 1)
    minimap:SetZoom(curZoom)

    -- Reposition zoom buttons to bottom-right corner of the minimap.
    -- Parent to minimap, raise frame level above the map surface, and
    -- hook SetPoint to prevent Blizzard from re-anchoring them.
    -- Midnight uses Minimap.ZoomIn/ZoomOut (not global MinimapZoomIn).
    -- With Zoom +/- Icons unchecked (hideZoomButtons), the buttons live under
    -- the hidden frame instead, so Blizzard's hover show/fade never renders
    -- them; re-checking reparents them back to the minimap.
    local zoomIn = minimap.ZoomIn or _G.MinimapZoomIn
    local zoomOut = minimap.ZoomOut or _G.MinimapZoomOut
    local hideZoom = p.hideZoomButtons
    if hideZoom and (zoomIn or zoomOut) and not EBS._hiddenFrame then
        EBS._hiddenFrame = CreateFrame("Frame")
        EBS._hiddenFrame:Hide()
    end
    if zoomIn then
        zoomIn:SetParent(hideZoom and EBS._hiddenFrame or minimap)
        zoomIn:SetFrameLevel(minimap:GetFrameLevel() + 10)
        zoomIn:ClearAllPoints()
        zoomIn:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", -2, 20)
        zoomIn:EnableMouse(true)
        zoomIn:SetAlpha(1)
        -- Start in Blizzard's between-hovers state (hidden; its hover
        -- handlers Show/Hide on map enter/leave) so the button is not
        -- visible from /reload until hovered.
        zoomIn:SetShown(minimap:IsMouseOver())
        if not GetFFD(zoomIn).hooked then
            hooksecurefunc(zoomIn, "SetPoint", function(self)
                if GetFFD(self).inHook then return end
                GetFFD(self).inHook = true
                self:ClearAllPoints()
                self:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", -2, 20)
                GetFFD(self).inHook = false
            end)
            GetFFD(zoomIn).hooked = true
        end
    end
    if zoomOut then
        zoomOut:SetParent(hideZoom and EBS._hiddenFrame or minimap)
        zoomOut:SetFrameLevel(minimap:GetFrameLevel() + 10)
        zoomOut:ClearAllPoints()
        zoomOut:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", -2, 2)
        zoomOut:EnableMouse(true)
        zoomOut:SetAlpha(1)
        -- Same between-hovers start as ZoomIn above
        zoomOut:SetShown(minimap:IsMouseOver())
        if not GetFFD(zoomOut).hooked then
            hooksecurefunc(zoomOut, "SetPoint", function(self)
                if GetFFD(self).inHook then return end
                GetFFD(self).inHook = true
                self:ClearAllPoints()
                self:SetPoint("BOTTOMRIGHT", minimap, "BOTTOMRIGHT", -2, 2)
                GetFFD(self).inHook = false
            end)
            GetFFD(zoomOut).hooked = true
        end
    end

    -- Map-region hover reveal (zoom buttons + hover-mode folio). Blizzard's
    -- fader hides the zoom buttons on the Minimap's OnLeave, which also fires
    -- when the mouse moves onto one of the map's mouse-enabled child elements
    -- (clock, FPS text, folio, buttons) -- and the OnEnter never fires at all
    -- when the cursor ENTERS the map region directly on such a child. Both
    -- scripts route through EBS._HVRevealMapHover, which no-ops unless the cursor
    -- is over the map region and runs one self-cancelling exit watcher; the
    -- hooked children's own OnEnter covers the direct-entry case.
    if not GetFFD(minimap).hoverRevealHooked then
        GetFFD(minimap).hoverRevealHooked = true
        minimap:HookScript("OnEnter", function() EBS._HVRevealMapHover() end)
        -- Real exits hide instantly (matching Blizzard's own zoom fade);
        -- moving onto a child over the map keeps the reveal alive and the
        -- watcher covers the eventual exit from there.
        minimap:HookScript("OnLeave", function(self)
            if EBS._HoverStillOver(self) then
                EBS._HVRevealMapHover()
            else
                EBS._HVHideNow()
            end
        end)
    end

    -- Save zoom level when zoom buttons are clicked
    if zoomIn and not GetFFD(zoomIn).zoomSaveHooked then
        zoomIn:HookScript("OnClick", function() SaveZoomLevel() end)
        GetFFD(zoomIn).zoomSaveHooked = true
    end
    if zoomOut and not GetFFD(zoomOut).zoomSaveHooked then
        zoomOut:HookScript("OnClick", function() SaveZoomLevel() end)
        GetFFD(zoomOut).zoomSaveHooked = true
    end

    -- Mark zoom buttons so GatherMinimapButtons skips them
    if zoomIn then flyoutOwnedFrames[zoomIn] = true end
    if zoomOut then flyoutOwnedFrames[zoomOut] = true end

    -- Flyout toggle button (bottom-left corner) -- create before hiding children
    CreateFlyoutToggle()

    -- Hide ALL minimap child frames from the map surface
    HideAllMinimapButtons()

    -- Show/hide flyout toggle based on whether any grouped buttons exist
    local groupedButtons = CollectFlyoutButtons()
    local mp2 = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    local hideGroupBtn = mp2 and mp2.hideExtraBtns and mp2.hideExtraBtns.groupButton
    if #groupedButtons > 0 and not hideGroupBtn then
        flyoutToggle:Show()
    else
        flyoutToggle:Hide()
    end

    -- Poll for late-loading addons that attach buttons after ADDON_LOADED
    if not addonButtonPoll then
        addonButtonPoll = CreateFrame("Frame")
        addonButtonPoll:RegisterEvent("ADDON_LOADED")
        local pollPending = false
        addonButtonPoll:SetScript("OnEvent", function()
            if pollPending then return end
            pollPending = true
            C_Timer.After(0.1, function()
                pollPending = false
                HideAllMinimapButtons()
                -- New buttons may have appeared; force flyout rebuild on
                -- next open so they get picked up by the grid.
                InvalidateFlyout()
                -- If the flyout is already open, rebuild immediately so
                -- newly-discovered buttons appear without closing/reopening.
                if flyoutPanel and flyoutPanel:IsShown() then
                    BuildFlyoutContents()
                end
            end)
        end)
    end
    addonButtonPoll:Show()

    -- Force the flyout to rebuild on next open so it picks up any
    -- changes to the button list (ungroup, new addon, profile swap, etc.)
    -- and re-shows buttons that HideAllMinimapButtons just hid.
    InvalidateFlyout()
    -- Close the flyout if it was open (layout may have changed)
    HideFlyoutPanel()

    -- Hide Blizzard zone text (we use our own location bar)
    local zoneBtn = MinimapZoneTextButton
    if zoneBtn then zoneBtn:Hide() end
    if MinimapCluster and MinimapCluster.ZoneTextButton then
        MinimapCluster.ZoneTextButton:Hide()
    end
    if MinimapZoneText then MinimapZoneText:Hide() end

    -- Refresh cached clock CVars when settings are applied
    RefreshClockCVars()

    -- Clock -- none, inside the map, or boxed on the map edge
    local clockMode, locationMode = GetElementModes(p)
    if clockMode ~= "none" then
        if not clockBg then
            clockBg = CreateFrame("Button", nil, minimap, "BackdropTemplate")
            clockBg:SetSize(80, 16)
            clockBg:SetPoint("TOP", minimap, "TOP", 0, 7)
            clockBg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
            clockBg:SetFrameLevel(minimap:GetFrameLevel() + 5)
            clockBg:RegisterForClicks("AnyUp")
            clockBg:SetScript("OnClick", function()
                -- With the Great Vault hover tooltip assigned, clicking the
                -- clock opens the vault (same as the Great Vault button)
                -- instead of the Blizzard clock config.
                local mp = EBS.db and EBS.db.profile.minimap
                if mp and mp.clockHoverTooltip == "vault" then
                    ToggleGreatVault()
                    return
                end
                if ToggleTimeManager then ToggleTimeManager() end
            end)
        end
        if not clockFrame then
            clockFrame = clockBg:CreateFontString(nil, "OVERLAY")
            ApplyMinimapFont(clockFrame, 10)
            clockFrame:SetPoint("CENTER", clockBg, "CENTER", 0, 0)
            clockFrame:SetTextColor(1, 1, 1, 0.9)
        end
        -- Background style + anchor position
        local cxOff = p.clockOffsetX or 0
        local cyOff = p.clockOffsetY or 0
        if clockMode == "inside" then
            clockBg:SetBackdropColor(0, 0, 0, 0)
        else
            local ar, ag, ab = GetBorderStyleColor(p)
            clockBg:SetBackdropColor(ar, ag, ab, 1)
        end
        local cpt, crel, cbx, cby = ResolveElementAnchor(p.clockPosition or "top", clockMode, isCircle)
        clockBg:ClearAllPoints()
        clockBg:SetPoint(cpt, minimap, crel, cbx + cxOff, cby + cyOff)
        -- Align the TEXT edge with the anchor so it lands exactly where the
        -- coordinates text would: inside style pins the text to the same
        -- corner of the wrapper that the wrapper pins to the map (the wrapper
        -- is wider than the text, so a centered text would drift toward the
        -- middle); edge style keeps it centered in the box.
        clockFrame:ClearAllPoints()
        if clockMode == "inside" then
            clockFrame:SetPoint(cpt, clockBg, cpt, 0, 0)
        else
            clockFrame:SetPoint("CENTER", clockBg, "CENTER", 0, 0)
        end
        local cs = p.clockScale or 1.15
        clockBg:SetScale(cs)
        _G._EBS_ClockBg = clockBg
        clockBg:Show()
        clockFrame:Show()
        if not clockTicker then
            clockTicker = CreateFrame("Frame")  -- kept for CVar event + Show/Hide API
            clockTicker._ticker = nil
            clockTicker.Show = function(self)
                if self._ticker then return end
                self._ticker = C_Timer.NewTicker(10, function()
                    UpdateClock()
                end)
            end
            clockTicker.Hide = function(self)
                if self._ticker then self._ticker:Cancel(); self._ticker = nil end
            end
            clockTicker:RegisterEvent("CVAR_UPDATE")
            clockTicker:SetScript("OnEvent", function(_, _, cvarName)
                if cvarName == "timeMgrUseMilitaryTime" or cvarName == "timeMgrUseLocalTime" then
                    RefreshClockCVars()
                    UpdateClock()
                end
            end)
        end
        clockTicker:Show()
        UpdateClock()
        -- Hover tooltip (Show on Clock Hover): instance lockouts or Great
        -- Vault, both reuse the calendar/vault custom tooltips (and their
        -- Custom Tooltip Size scaling). Mode is read live on each hover.
        if not clockBg._euiHoverHooked then
            clockBg._euiHoverHooked = true
            clockBg:SetScript("OnEnter", function(self)
                EBS._HVRevealMapHover()
                local mp = EBS.db and EBS.db.profile.minimap
                local mode = (mp and mp.clockHoverTooltip) or "none"
                if mode == "lockouts" then
                    if EllesmereUI.InProtectedInstance and EllesmereUI.InProtectedInstance() then return end
                    local entries = GetCalendarLockoutEntries()
                    if entries then ShowCalendarTooltip(self, entries) end
                elseif mode == "vault" then
                    ShowVaultTooltip(self)
                end
            end)
            clockBg:SetScript("OnLeave", function()
                HideCalendarTooltip()
                HideVaultTooltip()
            end)
        end
    else
        if clockBg then clockBg:Hide() end
        if clockFrame then clockFrame:Hide() end
        if clockTicker then clockTicker:Hide() end
    end

    -- Indicator frames (tracking, calendar, mail, crafting)
    LayoutIndicatorFrames(minimap, p, isCircle)

    -- Hook Blizzard mail/crafting Show/Hide to sync our custom indicator visibility
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    local mailFrame = indicator and indicator.MailFrame
    local craftingFrame = indicator and indicator.CraftingOrderFrame
    if mailFrame and not GetFFD(mailFrame).visHooked then
        GetFFD(mailFrame).visHooked = true
        local function onMailChange()
            local mp = EBS.db and EBS.db.profile.minimap
            if not mp or not mp.enabled then return end
            SyncIndicatorVisibility()
            LayoutIndicatorFrames(minimap, mp, (mp.shape or "square") ~= "square")
        end
        hooksecurefunc(mailFrame, "Show", onMailChange)
        hooksecurefunc(mailFrame, "Hide", onMailChange)
    end
    if craftingFrame and not GetFFD(craftingFrame).visHooked then
        GetFFD(craftingFrame).visHooked = true
        local function onCraftChange()
            local mp = EBS.db and EBS.db.profile.minimap
            if not mp or not mp.enabled then return end
            SyncIndicatorVisibility()
            LayoutIndicatorFrames(minimap, mp, (mp.shape or "square") ~= "square")
        end
        hooksecurefunc(craftingFrame, "Show", onCraftChange)
        hooksecurefunc(craftingFrame, "Hide", onCraftChange)
    end

    -- Location bar -- none, inside the map, or boxed on the map edge
    if locationMode ~= "none" then
        if not locationBg then
            locationBg = CreateFrame("Frame", nil, minimap, "BackdropTemplate")
            locationBg:SetSize(120, 18)
            locationBg:SetPoint("BOTTOM", minimap, "BOTTOM", 0, -7)
            locationBg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
            locationBg:SetFrameLevel(minimap:GetFrameLevel() + 5)
            locationBg:RegisterEvent("ZONE_CHANGED")
            locationBg:RegisterEvent("ZONE_CHANGED_INDOORS")
            locationBg:RegisterEvent("ZONE_CHANGED_NEW_AREA")
            locationBg:RegisterEvent("PLAYER_REGEN_ENABLED")
            locationBg:SetScript("OnEvent", function() UpdateLocation() end)
        end
        if not locationFrame then
            locationFrame = locationBg:CreateFontString(nil, "OVERLAY")
            ApplyMinimapFont(locationFrame, 10)
            locationFrame:SetPoint("CENTER", locationBg, "CENTER", 0, 0)
            locationFrame:SetTextColor(1, 1, 1, 0.9)
        end
        -- Background style + anchor position
        local lxOff = p.locationOffsetX or 0
        local lyOff = p.locationOffsetY or 0
        if locationMode == "inside" then
            locationBg:SetBackdropColor(0, 0, 0, 0)
        else
            local ar, ag, ab = GetBorderStyleColor(p)
            locationBg:SetBackdropColor(ar, ag, ab, 1)
        end
        local lpt, lrel, lbx, lby = ResolveElementAnchor(p.locationPosition or "bottom", locationMode, isCircle)
        locationBg:ClearAllPoints()
        locationBg:SetPoint(lpt, minimap, lrel, lbx + lxOff, lby + lyOff)
        -- Align the TEXT edge with the anchor (see the clock block above):
        -- inside style pins the text to the wrapper corner matching the map
        -- anchor; edge style keeps it centered in the box.
        locationFrame:ClearAllPoints()
        if locationMode == "inside" then
            locationFrame:SetPoint(lpt, locationBg, lpt, 0, 0)
        else
            locationFrame:SetPoint("CENTER", locationBg, "CENTER", 0, 0)
        end
        local ls = p.locationScale or 1.15
        locationBg:SetScale(ls)
        _G._EBS_LocationBg = locationBg
        locationBg:Show()
        locationFrame:Show()
        UpdateLocation()
    else
        if locationBg then locationBg:Hide() end
        if locationFrame then locationFrame:Hide() end
    end

    -- Coordinates -- mode (never/hover/always) + anchor position around the map
    if not coordFrame then
        coordFrame = minimap:CreateFontString(nil, "OVERLAY")
        ApplyMinimapFont(coordFrame, 11)
        coordFrame:SetTextColor(1, 1, 1, 0.9)
    end
    local coordsMode, coordsPos = GetCoordsModePos(p)
    local cpAnchor = MAP_POS_ANCHORS[coordsPos] or MAP_POS_ANCHORS.topLeft
    local cpx = p and p.coordsBelowOffsetX or 0
    local cpy = p and p.coordsBelowOffsetY or 0
    coordFrame:ClearAllPoints()
    coordFrame:SetPoint(cpAnchor[1], minimap, cpAnchor[2], cpAnchor[3] + cpx, cpAnchor[4] + cpy)
    coordFrame:SetScale(p and p.coordsScale or 1.0)
    _G._EBS_CoordFrame = coordFrame
    if not coordTicker then
        coordTicker = CreateFrame("Frame")  -- kept for Show/Hide API
        coordTicker._ticker = nil
        coordTicker.Show = function(self)
            if self._ticker then return end
            self._ticker = C_Timer.NewTicker(0.5, function()
                UpdateCoords()
            end)
        end
        coordTicker.Hide = function(self)
            if self._ticker then self._ticker:Cancel(); self._ticker = nil end
        end
    end
    if coordsMode == "always" then
        coordFrame:Show()
        coordTicker:Show()
        UpdateCoords()
    else
        coordFrame:Hide()
        coordTicker:Hide()
    end
    -- Hover mode (coords ticker only runs while the map region is hovered)
    -- is driven by EBS._HVRevealMapHover via the shared hover-reveal hooks
    -- installed in the zoom-button section above.

    -- FPS/MS -- optional performance readout (Text section); same format and
    -- options as the Quality of Life FPS counter, hosted on the minimap
    if p.showFPS then
        if not fpsBg then
            fpsBg = CreateFrame("Frame", nil, minimap)
            fpsBg:SetSize(60, 20)
            fpsBg:SetFrameLevel(minimap:GetFrameLevel() + 5)
            fpsBg:EnableMouse(false)
            local function MakeFS(size)
                local fs = fpsBg:CreateFontString(nil, "OVERLAY")
                ApplyMinimapFont(fs, size)
                fs:SetTextColor(1, 1, 1, 1)
                return fs
            end
            local DIV_W = (PP.Snap and PP.Snap(1)) or 1
            local DIV_H = 10
            local DIV_PAD = 6
            local function MakeDivider()
                local d = fpsBg:CreateTexture(nil, "OVERLAY")
                d:SetColorTexture(1, 1, 1, 1)
                d:SetSize(DIV_W, DIV_H)
                return d
            end
            -- One FontString per SEGMENT ("58 FPS"): number and suffix render
            -- in a single rasterization pass, so their spacing can never
            -- wobble sub-pixel like two separately snapped strings could.
            -- The suffix colour rides an inline escape (Accented Text);
            -- SetFormattedText keeps each tick's formatting C-side with no
            -- template string rebuilds. Only the dividers stay separate.
            local fsFps, fsWorld, fsLocal = MakeFS(12), MakeFS(12), MakeFS(12)
            fpsBg._fsAll = { fsFps, fsWorld, fsLocal }
            local divWorld = MakeDivider()
            local divLocal = MakeDivider()

            local floor = math.floor
            local function UpdateFPS(self)
                local mp = EBS.db and EBS.db.profile.minimap
                -- Numbers render white; the "FPS"/"MS" suffixes take the
                -- description colour while FPS/MS is checked in Accented
                -- Text (default on).
                local hex = "ffffff"
                if (mp and mp.fpsColorSuffix) ~= false then
                    local _, _, _, h = GetDescColor(mp)
                    hex = h
                end

                local fps = floor(GetFramerate() + 0.5)
                local showWorld = mp and mp.fpsShowWorldMS
                local _localMS = mp and mp.fpsShowLocalMS
                local showLocal = (_localMS == nil) and true or _localMS
                local _, _, latHome, latWorld = GetNetStats()

                fsFps:ClearAllPoints()
                fsFps:SetPoint("LEFT", self, "LEFT", 0, 0)
                fsFps:SetFormattedText("%d |cff%sFPS|r", fps, hex)
                local totalW = fsFps:GetStringWidth() or 0
                local anchor = fsFps

                if showWorld then
                    divWorld:ClearAllPoints()
                    divWorld:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                    divWorld:Show()
                    fsWorld:ClearAllPoints()
                    fsWorld:SetPoint("LEFT", divWorld, "RIGHT", DIV_PAD, 0)
                    fsWorld:SetFormattedText("%d |cff%sMS|r", latWorld, hex)
                    fsWorld:Show()
                    totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + (fsWorld:GetStringWidth() or 0)
                    anchor = fsWorld
                else
                    divWorld:Hide(); fsWorld:Hide()
                end

                if showLocal then
                    divLocal:ClearAllPoints()
                    divLocal:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                    divLocal:Show()
                    fsLocal:ClearAllPoints()
                    fsLocal:SetPoint("LEFT", divLocal, "RIGHT", DIV_PAD, 0)
                    fsLocal:SetFormattedText("%d |cff%sMS|r", latHome, hex)
                    fsLocal:Show()
                    totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + (fsLocal:GetStringWidth() or 0)
                else
                    divLocal:Hide(); fsLocal:Hide()
                end

                self:SetSize(totalW + 4, 20)
            end

            local elapsed = 0
            fpsBg:SetScript("OnUpdate", function(self, dt)
                elapsed = elapsed + dt
                if elapsed < (self._interval or 3) then return end
                elapsed = 0
                UpdateFPS(self)
            end)
            fpsBg._updateNow = function() elapsed = 0; UpdateFPS(fpsBg) end

            -- Hover tooltip (Show on FPS/MS Hover): same dispatch as the clock
            fpsBg:SetScript("OnEnter", function(self)
                EBS._HVRevealMapHover()
                local mp = EBS.db and EBS.db.profile.minimap
                local mode = (mp and mp.fpsHoverTooltip) or "none"
                if mode == "lockouts" then
                    if EllesmereUI.InProtectedInstance and EllesmereUI.InProtectedInstance() then return end
                    local entries = GetCalendarLockoutEntries()
                    if entries then ShowCalendarTooltip(self, entries) end
                elseif mode == "vault" then
                    ShowVaultTooltip(self)
                end
            end)
            fpsBg:SetScript("OnLeave", function()
                HideCalendarTooltip()
                HideVaultTooltip()
            end)
            -- With the Great Vault hover tooltip assigned, clicking the
            -- readout opens the vault (same as the Great Vault button). Mouse
            -- is only enabled while a hover tooltip is assigned, so this never
            -- intercepts clicks otherwise.
            fpsBg:SetScript("OnMouseUp", function(_, button)
                if button ~= "LeftButton" then return end
                local mp = EBS.db and EBS.db.profile.minimap
                if mp and mp.fpsHoverTooltip == "vault" then
                    ToggleGreatVault()
                end
            end)
        end
        local fsz = p.fpsTextSize or 12
        for _, fs in ipairs(fpsBg._fsAll) do
            ApplyMinimapFont(fs, fsz)
        end
        fpsBg._interval = p.fpsUpdateInterval or 3
        local fAnchor = MAP_POS_ANCHORS[p.fpsPosition or "bottomLeft"] or MAP_POS_ANCHORS.bottomLeft
        -- The row is one evenly spaced chain at natural widths; the anchored
        -- corner is the stable edge and the whole row breathes from there.
        fpsBg:ClearAllPoints()
        fpsBg:SetPoint(fAnchor[1], minimap, fAnchor[2],
            fAnchor[3] + (p.fpsOffsetX or 0), fAnchor[4] + (p.fpsOffsetY or 0))
        fpsBg:SetScale(p.fpsScale or 1.0)
        _G._EBS_FpsBg = fpsBg
        -- Mouse only while a hover tooltip is assigned, so the readout never
        -- blocks map clicks otherwise
        fpsBg:EnableMouse((p.fpsHoverTooltip or "none") ~= "none")
        fpsBg:Show()
        fpsBg._updateNow()
    else
        if fpsBg then fpsBg:Hide() end
    end

    -- Instance Difficulty as Text (Text section): compact "20M"-style readout
    -- on the map replacing the Blizzard difficulty flag (suppressed above
    -- while this is enabled). Event-driven; zero cost while disabled. Player
    -- count renders white, the difficulty letter follows the description
    -- color (same accent/custom system as the FPS/MS suffixes).
    if p.diffTextEnabled then
        if not diffTextFrame then
            diffTextFrame = CreateFrame("Frame", nil, minimap)
            local fs = minimap:CreateFontString(nil, "OVERLAY")
            fs:SetTextColor(1, 1, 1, 1)
            diffTextFrame._text = fs
            -- Difficulty ID -> suffix letter; count prefix rules alongside.
            local SUFFIX = {
                [1] = "N", [2] = "H", [23] = "M",                         -- dungeons
                [14] = "N", [15] = "H", [16] = "M", [233] = "M",          -- raids
                [3] = "N", [4] = "N", [5] = "H", [6] = "H",               -- legacy raids
                [9] = "N", [148] = "N", [173] = "N", [174] = "H",
                [7] = "LFR", [17] = "LFR", [205] = "F",
            }
            local FLEX = { [14] = true, [15] = true, [233] = true }       -- size = current group
            local NOCOUNT = { [205] = true }                              -- letter only
            local TW   = { [24] = true, [33] = true, [151] = true }
            local EVT  = { [18] = true, [19] = true, [30] = true }
            local PVP  = { [25] = true, [29] = true, [32] = true, [34] = true, [45] = true }
            local SCEN = { [12] = "S", [38] = "S", [11] = "HS", [39] = "HS", [40] = "MS" }
            local GARRISON = {
                [1152] = true, [1153] = true, [1154] = true, [1158] = true,
                [1159] = true, [1160] = true, [1330] = true, [1331] = true,
            }
            -- Difficulty (Reactive): letter colours by tier (normal and
            -- scenarios bronze like delves, heroic blue, mythic purple,
            -- keystones legendary orange).
            local REACTIVE_HEX = {
                N = "c69b6d", H = "0070dd", M = "a335ee",
                S = "c69b6d", HS = "0070dd", MS = "a335ee",
                LFR = "9d9d9d", F = "9d9d9d",
                TW = "00ccff", EVT = "ffffff", PvP = "ffffff",
            }
            diffTextFrame._update = function(self)
                local out = self._text
                local mp2 = EBS.db and EBS.db.profile.minimap
                if not (mp2 and mp2.diffTextEnabled) then out:SetText("") return end
                local _, instanceType, diffID, _, maxPlayers, _, _, instanceID, groupSize = GetInstanceInfo()
                if not diffID or diffID == 0 or instanceType == "none" or GARRISON[instanceID] then
                    out:SetText("")
                    return
                end
                -- Letter colour follows Accented Text: Difficulty (Reactive)
                -- colours by tier, Difficulty by the flat accent/custom
                -- colour, neither = plain white matching the count. Reactive
                -- wins if both keys are somehow set (stale import).
                local reactive = mp2.diffTextReactive
                local hex = "ffffff"
                if not reactive and mp2.diffTextAccent then
                    local _, _, _, h = GetDescColor(mp2)
                    hex = h
                end
                if diffID == 8 then
                    -- Active keystone: key level after the colored M+
                    if reactive then hex = "ff8000" end
                    local lvl = C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo
                        and C_ChallengeMode.GetActiveKeystoneInfo()
                    out:SetFormattedText("|cff%sM+|r%s", hex, (lvl and lvl > 0) and lvl or "")
                    return
                end
                if diffID == 208 then
                    -- Delve: tier number from the scenario header widget
                    if reactive then hex = "c69b6d" end
                    local tier
                    local ok, info = pcall(C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo, 6183)
                    if ok and info and info.tierText then
                        tier = tostring(info.tierText):match("%d+")
                    end
                    out:SetFormattedText("|cff%sT|r%s", hex, tier or "")
                    return
                end
                local letter
                if TW[diffID] then letter = "TW"
                elseif EVT[diffID] then letter = "EVT"
                elseif PVP[diffID] then letter = "PvP"
                elseif SCEN[diffID] then letter = SCEN[diffID]
                else letter = SUFFIX[diffID] end
                if not letter then out:SetText("") return end
                if reactive then hex = REACTIVE_HEX[letter] or "ffffff" end
                local count
                if SUFFIX[diffID] and not NOCOUNT[diffID] then
                    count = FLEX[diffID] and groupSize or maxPlayers
                end
                out:SetFormattedText("%s|cff%s%s|r", (count and count > 0) and count or "", hex, letter)
            end
            diffTextFrame:SetScript("OnEvent", function(self) self._update(self) end)
        end
        local fs = diffTextFrame._text
        ApplyMinimapFont(fs, p.diffTextSize or 12)
        local a = MAP_POS_ANCHORS[p.diffTextPosition or "topLeft"] or MAP_POS_ANCHORS.topLeft
        fs:ClearAllPoints()
        fs:SetPoint(a[1], minimap, a[2], a[3] + (p.diffTextOffsetX or 0), a[4] + (p.diffTextOffsetY or 0))
        fs:Show()
        diffTextFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        diffTextFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        diffTextFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
        diffTextFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        diffTextFrame:RegisterEvent("CHALLENGE_MODE_START")
        diffTextFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        diffTextFrame:RegisterEvent("CHALLENGE_MODE_RESET")
        diffTextFrame._update(diffTextFrame)
    elseif diffTextFrame then
        diffTextFrame:UnregisterAllEvents()
        diffTextFrame._text:Hide()
    end

    -- Mousewheel zoom: handled on the square overlay (the Minimap's own hit
    -- region is circular, which left the square skin's corners wheel-dead).
    -- With Scroll to Zoom off, both stay wheel-disabled so the wheel falls
    -- through to the world (camera zoom) as before.
    do
        local blocker = GetFFD(minimap).pingBlocker
        if blocker then blocker:EnableMouseWheel(p.scrollZoom and true or false) end
        minimap:EnableMouseWheel(false)
    end

    -- Restore saved zoom level on first activation
    if not GetFFD(minimap).active then
        local saved = p.savedZoom or 0
        if saved >= 0 and saved <= minimap:GetZoomLevels() then
            minimap:SetZoom(saved)
        end
    end

    -- Position: only set on first activation; after that, unlock mode owns positioning.
    if not GetFFD(minimap).active then
        minimap:ClearAllPoints()
        if p.position then
            local px, py = p.position.x, p.position.y
            local PPa = EllesmereUI and EllesmereUI.PP
            if PPa and px and py then
                local es = minimap:GetEffectiveScale()
                local isCenterAnchor = (p.position.point == "CENTER")
                    and (p.position.relPoint == "CENTER" or p.position.relPoint == nil)
                if isCenterAnchor and PPa.SnapCenterForDim then
                    px = PPa.SnapCenterForDim(px, minimap:GetWidth() or 0, es)
                    py = PPa.SnapCenterForDim(py, minimap:GetHeight() or 0, es)
                elseif PPa.SnapForES then
                    px = PPa.SnapForES(px, es)
                    py = PPa.SnapForES(py, es)
                end
            end
            minimap:SetPoint(p.position.point, UIParent, p.position.relPoint, px, py)
        else
            minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, -10)
        end
    end

    -- Mark module as active so persistent hooks know they can fire
    GetFFD(minimap).active = true

    ApplyOmniumFolio()
end


-------------------------------------------------------------------------------
--  Visibility (registered with the shared EllesmereUI visibility dispatcher)
-------------------------------------------------------------------------------
local function UpdateMinimapVisibility()
    local p = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if not p or not p.enabled then return end
    -- Minimap:Show()/Hide() are protected in combat lockdown. Bail and let
    -- PLAYER_REGEN_ENABLED re-trigger the visibility dispatcher.
    if InCombatLockdown() then return end
    local vis = EllesmereUI.EvalVisibility(p)
    local minimap = Minimap
    if not minimap then return end
    if vis == "mouseover" then
        minimap:SetAlpha(0)
        minimap:Show()
    elseif vis then
        minimap:SetAlpha(1)
        minimap:Show()
    else
        minimap:Hide()
    end
end

-------------------------------------------------------------------------------
--  Apply All
-------------------------------------------------------------------------------
ApplyAll = function()
    ApplyMinimap()
    if EllesmereUI.RequestVisibilityUpdate then
        C_Timer.After(0, EllesmereUI.RequestVisibilityUpdate)
    end
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--  Minimap Micro Menu (middle-click popup, taint-free)
--  SecureActionButtonTemplate buttons with click passthrough to Blizzard
--  MicroButtons via RegisterStateDriver (secure environment activation).
--  NEVER call EnableMouse/SetAlpha on the secure buttons from addon code
--  after creation -- that breaks the secure trust chain.
--  Show/hide is done by moving the parent frame offscreen.
-------------------------------------------------------------------------------
do
    local menuFrame
    local menuOpen    = false
    local MENU_WIDTH  = 160
    local BUTTON_H    = 20
    local PADDING     = 6
    local DIVIDER_H   = 9

    local menuItems = {
        { text = "Character",       microButton = "CharacterMicroButton" },
        { text = "Talents",         microButton = "PlayerSpellsMicroButton" },
        { text = "Professions",     microButton = "ProfessionMicroButton" },
        { divider = true },
        { text = "Group Finder",    microButton = "LFDMicroButton" },
        { text = "Adventure Guide", microButton = "EJMicroButton" },
        { text = "Achievements",    microButton = "AchievementMicroButton" },
        { text = "Collections",     microButton = "CollectionsMicroButton" },
        { text = "Quest Log",       microButton = "QuestLogMicroButton" },
        { divider = true },
        { text = "Friends",         microButton = "QuickJoinToastButton" },
        { text = "Guild",           microButton = "GuildMicroButton" },
        { text = "Housing",         microButton = "HousingMicroButton" },
        { text = "Calendar",        fn = function() if ToggleCalendar then ToggleCalendar() end end },
        { divider = true },
        { text = "Game Menu",       fn = function() ToggleFrame(GameMenuFrame) end },
        { text = "Shop",            microButton = "StoreMicroButton" },
        { text = "Support",         microButton = "HelpMicroButton" },
    }

    local function SetMenuVisible(visible)
        if not menuFrame then return end
        menuOpen = visible
        menuFrame:ClearAllPoints()
        if visible then
            menuFrame:SetClampedToScreen(true)
            menuFrame:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -4, 0)
        else
            menuFrame:SetClampedToScreen(false)
            menuFrame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", 10000, 0)
        end
    end

    local function CreateMenuFrame()
        menuFrame = CreateFrame("Frame", "EllesmereUIMicroMenu", UIParent, "BackdropTemplate")
        menuFrame:SetFrameStrata("TOOLTIP")
        menuFrame:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        menuFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
        menuFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        menuFrame:EnableMouse(true)

        -- Close when clicking elsewhere
        menuFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
        menuFrame:SetScript("OnEvent", function(self, event)
            if event == "GLOBAL_MOUSE_DOWN" and menuOpen then
                if not self:IsMouseOver() then SetMenuVisible(false) end
            end
        end)

        local y = -PADDING
        for _, item in ipairs(menuItems) do
            if item.divider then
                local div = menuFrame:CreateTexture(nil, "ARTWORK")
                div:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 8, y - 4)
                div:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -8, y - 4)
                div:SetHeight(1)
                div:SetColorTexture(0.3, 0.3, 0.3, 0.6)
                y = y - DIVIDER_H
            elseif item.fn then
                -- Plain button (no secure template needed)
                local btn = CreateFrame("Button", nil, menuFrame)
                btn:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, y)
                btn:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, y)
                btn:SetHeight(BUTTON_H)

                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.08)

                local label = btn:CreateFontString(nil, "OVERLAY")
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(label, true) end
                label:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
                label:SetPoint("LEFT", btn, "LEFT", 10, 0)
                label:SetTextColor(0.9, 0.9, 0.9)
                label:SetText(item.text)

                local itemFn = item.fn
                btn:SetScript("OnClick", function()
                    SetMenuVisible(false)
                    itemFn()
                end)

                y = y - BUTTON_H
            else
                -- Secure click passthrough to a Blizzard MicroButton
                local microRef = item.microButton and _G[item.microButton]
                local btnName = "EUI_MicroMenu_" .. item.text:gsub("%s", "")
                local btn = CreateFrame("Button", btnName, menuFrame, "SecureActionButtonTemplate,SecureHandlerStateTemplate")
                btn:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, y)
                btn:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, y)
                btn:SetHeight(BUTTON_H)

                -- 12.1: "/click <name>" macro transport (the 12.1 "click"
                -- secure action crashes on a Blizzard typo, SecureTemplates
                -- :564; MicroButtons are globally named so the macro reaches
                -- them directly). 12.0 keeps the proven click transport.
                local secureType = EllesmereUI.IS_121 and "macro" or "click"
                if microRef then
                    if EllesmereUI.IS_121 then
                        btn:SetAttribute("*macrotext1", "/click " .. item.microButton)
                    else
                        btn:SetAttribute("*clickbutton1", microRef)
                    end
                end
                btn:SetAttribute("useOnKeyDown", false)
                btn:SetAttribute("*type1", secureType)
                btn:EnableMouse(true)
                btn:RegisterForClicks("AnyUp")

                -- Activate secure click from the restricted secure environment.
                -- Without this, addon-set attributes are not trusted.
                -- The restore branch MUST match the transport set above --
                -- restoring a mismatched type silently reverts the 12.1
                -- macro transport on the first combat exit.
                RegisterStateDriver(btn, "combatlock", "[combat] combat; nocombat")
                btn:SetAttribute("_onstate-combatlock", ([[
                    if newstate == 'combat' then
                        self:SetAttribute('*type1', nil)
                        self:EnableMouse(false)
                    else
                        self:SetAttribute('*type1', '%s')
                        self:EnableMouse(true)
                    end
                ]]):format(secureType))

                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.08)

                local label = btn:CreateFontString(nil, "OVERLAY")
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(label, true) end
                label:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
                label:SetPoint("LEFT", btn, "LEFT", 10, 0)
                label:SetTextColor(0.9, 0.9, 0.9)
                label:SetText(item.text)

                btn:HookScript("OnClick", function() C_Timer.After(0, function() SetMenuVisible(false) end) end)

                y = y - BUTTON_H
            end
        end

        menuFrame:SetSize(MENU_WIDTH, -y + PADDING)
        menuFrame:Show()
        SetMenuVisible(false)
    end

    local function ToggleMicroMenu()
        if InCombatLockdown() then
            UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT, 1.0, 0.3, 0.3, 1.0)
            return
        end
        if not menuFrame then CreateMenuFrame() end
        SetMenuVisible(not menuOpen)
    end
    EBS._ToggleMicroMenu = ToggleMicroMenu

    local hookFrame = CreateFrame("Frame")
    hookFrame:RegisterEvent("PLAYER_LOGIN")
    hookFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        CreateMenuFrame()
    end)
end

-- Debug: /euiblock -- after 3 seconds, print every click-enabled frame under
-- the cursor, INCLUDING motion-disabled ones that /fstack cannot see (those
-- are the invisible click-blockers).
SLASH_EUIBLOCK1 = "/euiblock"
SlashCmdList.EUIBLOCK = function()
    print("|cff0cd29fEllesmereUI:|r hover the blocked spot -- scanning in 3 seconds...")
    -- Frame state on protected frames comes back as secret booleans in
    -- Midnight and boolean-testing those throws, so each frame's probe runs
    -- under pcall and secret/forbidden frames are simply skipped.
    local function Probe(fr)
        if fr:IsForbidden() or not fr:IsVisible() or not fr:IsMouseOver() then return end
        if not (fr.IsMouseClickEnabled and fr:IsMouseClickEnabled()) then return end
        return (fr:GetDebugName() or "?"), tostring(fr:IsMouseMotionEnabled())
    end
    C_Timer.After(3, function()
        print("|cff0cd29fEllesmereUI:|r click-enabled frames under the cursor:")
        local f = EnumerateFrames()
        local n = 0
        while f do
            local okc, name, motion = pcall(Probe, f)
            if okc and name then
                n = n + 1
                print(format("  %s  (motion: %s)", name, motion))
            end
            f = EnumerateFrames(f)
        end
        print(format("|cff0cd29fEllesmereUI:|r %d frame(s).", n))
    end)
end

-- Debug: /euimap -- dump every direct Minimap child with its size, state and
-- the atlases of its Default-state regions, to identify anonymous Blizzard
-- widgets (like the guild banner) that need suppression.
SLASH_EUIMAP1 = "/euimap"
SlashCmdList.EUIMAP = function()
    print("|cff0cd29fEllesmereUI:|r Minimap children:")
    for i, child in ipairs({ Minimap:GetChildren() }) do
        local okc, line = pcall(function()
            local d = child.Default
            local a1 = d and d.Background and d.Background.GetAtlas and d.Background:GetAtlas()
            local a2 = d and d.Border and d.Border.GetAtlas and d.Border:GetAtlas()
            local w, h = child:GetSize()
            return format("  %d. %s  %.0fx%.0f  shown:%s click:%s  atlas:%s / %s",
                i, child:GetDebugName() or "?", w or 0, h or 0,
                tostring(child:IsShown()),
                tostring(child.IsMouseClickEnabled and child:IsMouseClickEnabled()),
                tostring(a1), tostring(a2))
        end)
        if okc and line then print(line) end
    end
end

function EBS:OnInitialize()
    EBS.db = EllesmereUI.Lite.NewDB("EllesmereUIMinimapDB", defaults)

    -- Migrate legacy hideGreatVault/hidePortals into hideExtraBtns table
    local mp = EBS.db and EBS.db.profile and EBS.db.profile.minimap
    if mp then
        if mp.hideGreatVault ~= nil or mp.hidePortals ~= nil then
            if not mp.hideExtraBtns then mp.hideExtraBtns = {} end
            if mp.hideGreatVault ~= nil then
                mp.hideExtraBtns.greatVault = mp.hideGreatVault
                mp.hideGreatVault = nil
            end
            if mp.hidePortals ~= nil then
                mp.hideExtraBtns.portals = mp.hidePortals
                mp.hidePortals = nil
            end
        end
    end

    -- Full rebuild: wipes cached button state so the next ApplyMinimap
    -- re-snapshots native button sizes/textures from scratch (as if /reload).
    -- Called when toggling btnBackgrounds or ungrouping a button.
    local function FullRebuildMinimap()
        wipe(flyoutSavedRegions)
        -- ApplyAll, not bare ApplyMinimap: visibility runs through the shared
        -- EllesmereUI visibility dispatcher and only re-evaluates on request.
        -- Without it, a visibility change applied programmatically (settings
        -- override transitions use this as the module refresher) updates the
        -- stored setting but the minimap never actually hides/shows.
        ApplyAll()
    end

    -- Global bridge for options <-> main communication
    _G._EMM_DB           = EBS.db
    _G._EMM_ApplyMinimap = ApplyMinimap
    _G._EMM_FullRebuildMinimap = FullRebuildMinimap

    -- Register visibility updater + mouseover target
    if EllesmereUI.RegisterVisibilityUpdater then
        EllesmereUI.RegisterVisibilityUpdater(UpdateMinimapVisibility)
    end
    if EllesmereUI.RegisterMouseoverTarget and Minimap then
        EllesmereUI.RegisterMouseoverTarget(Minimap, function()
            -- Minimap is the one mouseover target that is a raw protected
            -- Blizzard frame (every other module registers an addon-owned
            -- proxy). The shared poll calls frame:Show()/Hide() when active,
            -- which is blocked in combat lockdown -- the second trigger of
            -- issue #639. Report inactive during combat: the poll then only
            -- resets its bookkeeping (no Show/Hide), and the visibility
            -- dispatcher re-applies the correct state on PLAYER_REGEN_ENABLED.
            if InCombatLockdown() then return false end
            local p = EBS.db and EBS.db.profile and EBS.db.profile.minimap
            if not (p and p.enabled) then return false end
            -- Hover-gated sets only reveal while their conditions pass;
            -- a legacy single "mouseover" behaves exactly as before.
            return EllesmereUI.VisWantsMouseover(p, "visibility")
        end)
    end
end

function EBS:OnEnable()
    ApplyAll()

    -- Re-apply after PLAYER_ENTERING_WORLD so accent colors from the theme
    -- system (which updates ELLESMERE_GREEN at PLAYER_LOGIN) are picked up.
    local loginRefresh = CreateFrame("Frame")
    loginRefresh:RegisterEvent("PLAYER_ENTERING_WORLD")
    loginRefresh:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        C_Timer.After(0, ApplyAll)
    end)

    -- The Omnium Folio (expansion landing page) button must be re-asserted after
    -- EVERY loading screen, not just the first. Blizzard can leave it hidden on a
    -- zone-in (RefreshButton's early-out path), and another minimap-button addon
    -- can re-grab its parent/position -- the one-shot loginRefresh above won't
    -- catch later transitions, which is the "button gone after a loading screen,
    -- /reload fixes it" report. This persistent watcher re-runs ApplyOmniumFolio,
    -- which is idempotent when the button is already shown and correctly placed
    -- (it only nudges RefreshButton when the button is hidden). Deferred a frame
    -- so Blizzard's own PLAYER_ENTERING_WORLD handling runs first.
    local folioRefresh = CreateFrame("Frame")
    folioRefresh:RegisterEvent("PLAYER_ENTERING_WORLD")
    folioRefresh:SetScript("OnEvent", function()
        C_Timer.After(0, ApplyOmniumFolio)
    end)

    -- If GameTimeFrame still doesn't exist, watch for Blizzard_TimeManager to load
    if not _G.GameTimeFrame then
        local tmWatcher = CreateFrame("Frame")
        tmWatcher:RegisterEvent("ADDON_LOADED")
        tmWatcher:SetScript("OnEvent", function(self, _, addon)
            if addon == "Blizzard_TimeManager" then
                self:UnregisterAllEvents()
                if EBS.db.profile.minimap.enabled then
                    C_Timer.After(0, ApplyMinimap)
                end
            end
        end)
    end

    -- Register minimap with unlock mode
    if EllesmereUI and EllesmereUI.RegisterUnlockElements then
        local MK = EllesmereUI.MakeUnlockElement
        local function MDB() return EBS.db and EBS.db.profile.minimap end
        EllesmereUI:RegisterUnlockElements({
            MK({
                key   = "EBS_Minimap",
                label = "Minimap",
                group = "Minimap",
                order = 500,
                noResize = true,
                noAnchorTo = true,
                getFrame = function() return Minimap end,
                getSize  = function()
                    return Minimap:GetWidth(), Minimap:GetHeight()
                end,
                isHidden = function()
                    local m = MDB()
                    return not m or not m.enabled
                end,
                savePos = function(_, point, relPoint, x, y)
                    local m = MDB(); if not m then return end
                    m.position = { point = point, relPoint = relPoint, x = x, y = y }
                    if not EllesmereUI._unlockActive then
                        ApplyMinimap()
                    end
                end,
                loadPos = function()
                    local m = MDB()
                    if not m or not m.enabled then return nil end
                    return m.position
                end,
                clearPos = function()
                    local m = MDB(); if not m then return end
                    m.position = nil
                end,
                applyPos = function()
                    local m = MDB()
                    if not m or not m.enabled then return end
                    ApplyMinimap()
                end,
            }),
        })
    end
end

-------------------------------------------------------------------------------
--  FarmHud Compatibility
--  When FarmHud is active, keep the minimap centered in its frame and
--  hide EllesmereUI border/background elements so they don't overlap.
--  Credit: Discord user DnL (original concept), PR #293 by jonathanfernandezfm.
-------------------------------------------------------------------------------
do
    local _fhLock = false

    local fhFix = CreateFrame("Frame")
    fhFix:RegisterEvent("PLAYER_ENTERING_WORLD")
    fhFix:SetScript("OnEvent", function(self)
        if not FarmHud then return end
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

        -- Keep the minimap centered in the FarmHud frame whenever
        -- FarmHud or another addon repositions / reparents it.
        hooksecurefunc(Minimap, "SetPoint", function(mm)
            if FarmHud:IsShown() and not _fhLock then
                _fhLock = true
                mm:ClearAllPoints()
                mm:SetPoint("CENTER", FarmHud, "CENTER", 0, 0)
                _fhLock = false
            end
        end)

        hooksecurefunc(Minimap, "SetParent", function(mm, parent)
            if FarmHud:IsShown() and parent ~= FarmHud and not _fhLock then
                _fhLock = true
                mm:SetParent(FarmHud)
                _fhLock = false
            end
        end)

        -- Hide / restore EllesmereUI minimap borders
        local function ToggleMinimapBorders(show)
            local alpha = show and 1 or 0

            -- Circle border
            if GetFFD(Minimap).circBorder then GetFFD(Minimap).circBorder:SetAlpha(alpha) end
            -- Textured circle border
            if GetFFD(Minimap).texCircBorder then GetFFD(Minimap).texCircBorder:SetAlpha(alpha) end

            -- Square border host (solid strips or textured backdrop)
            local host = GetFFD(Minimap).borderHost
            if host then host:SetAlpha(alpha) end
        end

        FarmHud:HookScript("OnShow", function() ToggleMinimapBorders(false) end)
        FarmHud:HookScript("OnHide", function() ToggleMinimapBorders(true) end)
    end)
end
