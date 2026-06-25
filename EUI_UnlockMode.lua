-------------------------------------------------------------------------------
--  EUI_UnlockMode.lua
--  Full-featured Unlock Mode for EllesmereUI
--  Animated transition, grid overlay, draggable bar movers, snap guides,
--  position memory, and a polished return-to-options flow.
--  Supports elements from any addon via EllesmereUI:RegisterUnlockElements().
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local EAB = ns.EAB  -- may be nil if loaded by a non-ActionBars addon

-------------------------------------------------------------------------------
--  Registration API  –  lives on the EllesmereUI global so ALL addons share
--  the same table regardless of which copy of this file runs.
-------------------------------------------------------------------------------
if not EllesmereUI._unlockRegisteredElements then
    EllesmereUI._unlockRegisteredElements = {}
    EllesmereUI._unlockRegisteredOrder    = {}
    EllesmereUI._unlockRegistrationDirty  = true
end

if not EllesmereUI.RegisterUnlockElements then
    -- Normalize short field names (savePos, loadPos, etc.) to the long
    -- names used throughout unlock mode (savePosition, loadPosition, etc.)
    local FIELD_ALIASES = {
        savePos      = "savePosition",
        loadPos      = "loadPosition",
        clearPos     = "clearPosition",
        applyPos     = "applyPosition",
    }
    function EllesmereUI:RegisterUnlockElements(elements, folder)
        for _, elem in ipairs(elements) do
            for short, long in pairs(FIELD_ALIASES) do
                if elem[short] and not elem[long] then
                    elem[long] = elem[short]
                end
            end
            -- Stamp the owning addon folder (canonical/suite folder name). Used by
            -- the profile export/import system to attribute each unlock element --
            -- and the anchor/size-match relationships keyed by element -- to a
            -- module, so layout can be exported per-module. A per-element folder
            -- (if a call ever sets one) wins; otherwise the call-site folder is used.
            if folder and not elem.folder then elem.folder = folder end
            self._unlockRegisteredElements[elem.key] = elem
        end
        self._unlockRegistrationDirty = true
    end
end

if not EllesmereUI.UnregisterUnlockElement then
    function EllesmereUI:UnregisterUnlockElement(key)
        self._unlockRegisteredElements[key] = nil
        self._unlockRegistrationDirty = true
    end
end

-- If this file was already fully loaded by another addon, bail out.
-- The registration API above is safe to re-run (idempotent), but the
-- rest of the file (state, frames, animations) must only exist once.
if EllesmereUI._unlockModeLoaded then return end
EllesmereUI._unlockModeLoaded = true

-------------------------------------------------------------------------------
--  Lightweight anchor reapply stub (pre-EnsureLoaded)
--  Allows child addons (CDM, etc.) to reposition anchored elements on login
--  before the full unlock mode body has been loaded. The deferred block
--  replaces this with the full implementation.
-------------------------------------------------------------------------------
if not EllesmereUI.ReapplyOwnAnchor then
    EllesmereUI.ReapplyOwnAnchor = function(key)
        if not EllesmereUIDB or not EllesmereUIDB.unlockAnchors then return end
        local info = EllesmereUIDB.unlockAnchors[key]
        if not info or not info.target then return end

        -- Resolve child and target frames via registered elements
        local elems = EllesmereUI._unlockRegisteredElements
        local childElem = elems and elems[key]
        local targetElem = elems and elems[info.target]
        local childBar = childElem and childElem.getFrame and childElem.getFrame(key)
        local targetBar = targetElem and targetElem.getFrame and targetElem.getFrame(info.target)
        if not childBar or not targetBar then return end
        if not targetBar:GetLeft() then return end

        local side = info.side
        local uiS = UIParent:GetEffectiveScale()
        local tS = targetBar:GetEffectiveScale()
        local cS = childBar:GetEffectiveScale()

        local tL = (targetBar:GetLeft() or 0) * tS / uiS
        local tR = (targetBar:GetRight() or 0) * tS / uiS
        local tT = (targetBar:GetTop() or 0) * tS / uiS
        local tB = (targetBar:GetBottom() or 0) * tS / uiS
        local tCX = (tL + tR) / 2
        local tCY = (tT + tB) / 2

        local cW = (childBar:GetWidth() or 50) * cS / uiS
        local cH = (childBar:GetHeight() or 50) * cS / uiS

        local cx, cy
        if info.offsetX and info.offsetY then
            if side == "LEFT" then
                cx = tL + info.offsetX - cW / 2
                cy = tCY + info.offsetY
            elseif side == "RIGHT" then
                cx = tR + info.offsetX + cW / 2
                cy = tCY + info.offsetY
            elseif side == "TOP" then
                cx = tCX + info.offsetX
                cy = tT + info.offsetY + cH / 2
            elseif side == "BOTTOM" then
                cx = tCX + info.offsetX
                cy = tB + info.offsetY - cH / 2
            else
                cx = tCX + info.offsetX
                cy = tCY + info.offsetY
            end
        else
            if side == "LEFT" then
                cx = tL - cW / 2; cy = tCY
            elseif side == "RIGHT" then
                cx = tR + cW / 2; cy = tCY
            elseif side == "TOP" then
                cx = tCX; cy = tT + cH / 2
            elseif side == "BOTTOM" then
                cx = tCX; cy = tB - cH / 2
            else
                cx = tCX; cy = tCY
            end
        end

        local uiW, uiH = UIParent:GetSize()
        local centerX = cx - uiW / 2
        local centerY = cy - uiH / 2

        -- No explicit snap: the center was computed from pixel-aligned target
        -- edges and pixel-aligned child dimensions. Snapping here introduces
        -- 1px drift from floating-point dust in the conversions.
        pcall(function()
            childBar:ClearAllPoints()
            childBar:SetPoint("CENTER", UIParent, "CENTER", centerX, centerY)
        end)
    end
end

-------------------------------------------------------------------------------
--  Early stub: NotifyElementResized
--  Handles grow-direction-aware repositioning before unlock mode fully loads.
--  The deferred block overwrites this with the full implementation.
-------------------------------------------------------------------------------
if not EllesmereUI.NotifyElementResized then
    EllesmereUI.NotifyElementResized = function(key)
        if not EllesmereUIDB then return end
        -- Skip if anchored (early ReapplyOwnAnchor handles those)
        local anchors = EllesmereUIDB.unlockAnchors
        if anchors and anchors[key] and anchors[key].target then return end

        -- Read grow direction from the bar's per-profile settings
        local growDir
        if key == "EQT_Tracker" then growDir = "DOWN"
        elseif key:sub(1, 4) == "CDM_" then
            local rawKey = key:sub(5)
            local cdm = EllesmereUI.Lite and EllesmereUI.Lite.GetAddon and EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
            local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
            if cdmBars and cdmBars.bars then
                for _, bar in ipairs(cdmBars.bars) do
                    if bar.key == rawKey then
                        local g = bar.growDirection
                        if g then growDir = g end
                        break
                    end
                end
            end
        else
            local eab = EllesmereUI.Lite and EllesmereUI.Lite.GetAddon and EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
            local s = eab and eab.db and eab.db.profile and eab.db.profile.bars and eab.db.profile.bars[key]
            if s then
                local g = (s.growDirection or "up"):upper()
                if g ~= "UP" then growDir = g end
            end
        end
        if not growDir or growDir == "CENTER" then return end

        -- Find the frame via registered elements
        local elems = EllesmereUI._unlockRegisteredElements
        local elem = elems and elems[key]
        local frame = elem and elem.getFrame and elem.getFrame(key)
        if not frame or not frame:GetCenter() then return end

        -- Load saved position
        local pos
        if elem and elem.loadPosition then
            pos = elem.loadPosition(key)
        else
            local eab = EllesmereUI.Lite and EllesmereUI.Lite.GetAddon and EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
            local db = eab and eab.db and eab.db.profile and eab.db.profile.barPositions
            pos = db and db[key]
        end
        if not pos or pos.point ~= "CENTER" or pos.relPoint ~= "CENTER" then return end

        local cx, cy = pos.x or 0, pos.y or 0
        local fw = frame:GetWidth() or 0
        local fh = frame:GetHeight() or 0
        -- Use raw fw/2 and fh/2 (not floor) so odd-pixel-height/width frames
        -- with integer + 0.5 center coords reverse exactly to integer pixel
        -- edges. floor() loses the .5 and causes a 1px drift on save & exit.
        local anchor, adjX, adjY
        if growDir == "RIGHT" then
            anchor = "LEFT"; adjX = cx - fw / 2; adjY = cy
        elseif growDir == "LEFT" then
            anchor = "RIGHT"; adjX = cx + fw / 2; adjY = cy
        elseif growDir == "DOWN" then
            anchor = "TOP"; adjX = cx; adjY = cy + fh / 2
        elseif growDir == "UP" then
            anchor = "BOTTOM"; adjX = cx; adjY = cy - fh / 2
        else
            return
        end

        -- No explicit snap: the edge offset is derived from a stored CENTER
        -- value that was computed from pixel-aligned edges. The derivation
        -- cx +/- dim/2 reproduces the original edge within floating-point
        -- epsilon. Snapping here can round that epsilon the wrong way,
        -- causing 1px drift on every reload.
        pcall(function()
            frame:ClearAllPoints()
            frame:SetPoint(anchor, UIParent, "CENTER", adjX, adjY)
        end)
    end
end

-- Early stub: IsUnlockAnchored
-- Returns true if the given unlock key has an anchor target in the DB.
-- The deferred block overwrites this with the full implementation.
if not EllesmereUI.IsUnlockAnchored then
    EllesmereUI.IsUnlockAnchored = function(unlockKey)
        if not EllesmereUIDB or not EllesmereUIDB.unlockAnchors then return false end
        local ai = EllesmereUIDB.unlockAnchors[unlockKey]
        return ai and ai.target and true or false
    end
end

-- Authoritative position pass fallback: when CDM is loaded it owns this pass
-- (fires from CollectAndReanchor after async icon population settles). When
-- CDM is NOT loaded, nobody triggers EnsureLoaded or the final layout pass,
-- so registered-element positions, width/height matches, and anchor chains
-- never get applied. This fallback detects the missing CDM and fires the
-- same pass from the parent addon instead.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        C_Timer.After(1.5, function()
            -- CDM already ran EnsureLoaded and will fire the authoritative
            -- pass itself -- nothing to do here.
            if EllesmereUI._applySavedPositions then return end
            -- CDM is not loaded. Load the full deferred block and fire
            -- the same authoritative pass CDM would have.
            EllesmereUI:EnsureLoaded()
            if EllesmereUI.ApplyAllWidthHeightMatches then
                EllesmereUI.ApplyAllWidthHeightMatches()
            end
            if EllesmereUI._applySavedPositions then
                EllesmereUI._applySavedPositions()
            end
            if EllesmereUI.ReapplyAllUnlockAnchorsForced then
                EllesmereUI.ReapplyAllUnlockAnchorsForced()
            end
        end)
    end)
end

-- DEFERRED: heavy body (4900+ lines) runs on first EnsureLoaded() call.
EllesmereUI._deferredInits[#EllesmereUI._deferredInits + 1] = function()
local floor = math.floor
local abs   = math.abs
local min   = math.min
local max   = math.max
local sqrt  = math.sqrt
local sin   = math.sin

-- IEEE 754 branchless round-to-nearest-even (avoids -0 from half-pixel centers)
local function round(num)
    return num + (2^52 + 2^51) - (2^52 + 2^51)
end

-- Pixel-perfect snap: round a value to the nearest physical pixel boundary.
local PP = EllesmereUI and EllesmereUI.PP
local function pxSnap(x)
    if not PP then return round(x) end
    local m = PP.mult or 1
    if m == 1 then return round(x) end
    return round(x / m) * m
end

-- WaitForSize(frame, callback)
-- Defers callback to the next frame so the layout engine has flushed.
local function WaitForSize(frame, callback)
    C_Timer.After(0, callback)
end

-- DeferMoverSync(moverFrame, syncFn, barFrame)
-- Syncs the mover immediately (no blink), then again next frame
-- to catch any position changes from the layout engine flush.
-- Hides the actual bar frame during the transition to prevent visual jump.
local function DeferMoverSync(m, syncFn, barFrame)
    if not m then return end
    if barFrame then barFrame:SetAlpha(0) end
    syncFn(m)
    C_Timer.After(0, function()
        if m then syncFn(m) end
        if barFrame then barFrame:SetAlpha(1) end
    end)
end

-- RepositionBarToMover(barKey)
-- During unlock mode, after a setWidth/setHeight triggers an addon rebuild
-- that snaps the bar frame back to its stored position, this function
-- re-positions the bar frame to match the mover's current screen position.
-- Without this, resizing in unlock mode causes the bar to jump.
-- Stored on EllesmereUI to avoid adding an upvalue to CreateMover (Lua 5.1 limit: 60).
function EllesmereUI.RepositionBarToMover(barKey)
    if not isUnlocked then return end
    local m = movers[barKey]
    if not m then return end
    local bar = GetBarFrame(barKey)
    if not bar then return end
    local mL, mT = m:GetLeft(), m:GetTop()
    if not mL or not mT then return end
    -- GetLeft/GetTop return in UIParent coordinate space.
    -- SetPoint TOPLEFT relative to UIParent TOPLEFT uses the same space.
    -- Y offset from UIParent TOPLEFT is negative (top of screen = 0).
    pcall(function()
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", mL, mT - UIParent:GetHeight())
    end)
end

-- RecenterBarAnchor is defined after its dependencies (isUnlocked, movers,
-- registeredElements, GetBarFrame, GetBarGrowDirActual) are declared below.

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local FONT_PATH   = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras"))
    or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

-- At very low UI scales the unlock overlays/top bar get hard to read, so we
-- nudge them up. The "is the global UI scale below 0.6" check is inlined at each
-- use site as `UIParent:GetEffectiveScale() < 0.6` rather than via a helper,
-- because the overlay-builder functions are already at Lua 5.1's 60-upvalue
-- limit and referencing a file-local helper would add an upvalue. UIParent is a
-- global, so inlining costs no upvalue.
local LOCK_INNER  = "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-inner-2.png"
local LOCK_OUTER  = "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-outer-2.png"
local LOCK_TOP    = "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-top-2.png"
local GRID_SPACING = 32          -- pixels between grid lines
local SNAP_THRESH  = 6            -- px distance to trigger snap-to-element
local MOVER_ALPHA  = 0.55        -- resting alpha for mover overlays
local MOVER_HOVER  = 0.85        -- hover alpha
local MOVER_DRAG   = 0.95        -- dragging alpha
local TRANSITION_DUR = 0.35      -- seconds for the open/close fade-in
local GEAR_ROTATION  = math.pi / 4  -- 45 deg rotation for gear effect

-- Bar keys that can be moved (action bars + stance + micro + bag)
-- These are populated by EAB if it's loaded; otherwise empty.
local BAR_LOOKUP    = ns.BAR_LOOKUP or {}
local ALL_BAR_ORDER = ns.BAR_DROPDOWN_ORDER or {}
local VISIBILITY_ONLY = ns.VISIBILITY_ONLY or {}

local function GetVisibilityOnly()
    -- Read lazily so child addons have time to populate ns.VISIBILITY_ONLY
    return ns.VISIBILITY_ONLY or VISIBILITY_ONLY
end

-- Local aliases for the shared registration tables
local registeredElements = EllesmereUI._unlockRegisteredElements
local registeredOrder    = EllesmereUI._unlockRegisteredOrder

local function RebuildRegisteredOrder()
    if not EllesmereUI._unlockRegistrationDirty then return end
    wipe(registeredOrder)
    for key, _ in pairs(registeredElements) do
        registeredOrder[#registeredOrder + 1] = key
    end
    -- Sort by order field (lower first), then alphabetically
    table.sort(registeredOrder, function(a, b)
        local oa = registeredElements[a].order or 1000
        local ob = registeredElements[b].order or 1000
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    EllesmereUI._unlockRegistrationDirty = false
end

-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
local unlockFrame          -- the full-screen overlay
local gridFrame            -- grid line container
local guidePool = {}       -- reusable alignment guide lines
local movers = {}          -- { [barKey] = moverFrame }
local isUnlocked = false
function EllesmereUI.IsUnlockModeActive() return isUnlocked end
local gridMode = "dimmed"  -- "disabled", "dimmed", "bright"
local snapEnabled = true   -- magnet/snap state (runtime) — must be before SnapPosition
local lockAnimFrame        -- lock assembly animation (close)
local openAnimFrame        -- lock animation frame (open)
local logoFadeFrame        -- the 2s logo+title fade-out timer frame
local pendingPositions = {}   -- { [barKey] = {point,relPoint,x,y} } -- unsaved changes
local snapshotPositions = {}  -- original positions captured when unlock mode opens
local snapshotAnchors = {}    -- original anchor data captured when unlock mode opens
local snapshotSizes = {}      -- original sizes captured when unlock mode opens
local snapshotWidthMatch = {} -- original width match DB captured when unlock mode opens
local snapshotHeightMatch = {} -- original height match DB captured when unlock mode opens
local snapshotGrowDirs = {}   -- original growth directions captured when unlock mode opens
local hasChanges = false      -- true if user dragged anything this session
local snapHighlightKey = nil   -- barKey of mover currently showing snap highlight border
local snapHighlightAnim = nil  -- OnUpdate frame for the pulsing border
local combatSuspended = false  -- true if unlock mode was auto-closed by combat
local objTrackerWasVisible = false  -- track objective tracker state for restore

-- Grid mode helpers
local GRID_ALPHA_DIMMED = 0.15
local GRID_ALPHA_BRIGHT = 0.30
local GRID_CENTER_DIMMED = 0.25
local GRID_CENTER_BRIGHT = 0.50
local GRID_HUD_BRIGHT = 0.60   -- matches HUD_ON_ALPHA
local GRID_HUD_DIMMED = 0.45
local GRID_HUD_OFF    = 0.30   -- matches HUD_OFF_ALPHA

local function GridBaseAlpha()
    return gridMode == "bright" and GRID_ALPHA_BRIGHT or GRID_ALPHA_DIMMED
end
local function GridCenterAlpha()
    return gridMode == "bright" and GRID_CENTER_BRIGHT or GRID_CENTER_DIMMED
end
local function GridHudAlpha()
    if gridMode == "bright" then return GRID_HUD_BRIGHT end
    if gridMode == "dimmed" then return GRID_HUD_DIMMED end
    return GRID_HUD_OFF
end
local function GridLabelText()
    if gridMode == "bright" then return "Grid Lines\nBright" end
    if gridMode == "dimmed" then return "Grid Lines\nDimmed" end
    return "Grid Lines\nDisabled"
end
local function CycleGridMode()
    if gridMode == "dimmed" then gridMode = "bright"
    elseif gridMode == "bright" then gridMode = "disabled"
    else gridMode = "dimmed" end
end
local flashlightEnabled = false  -- cursor flashlight toggle
local hoverBarEnabled = false   -- show-bar-on-hover toggle
local darkOverlaysEnabled = true  -- dark overlay backgrounds on movers
local coordsEnabled = false     -- show coordinates for all elements at all times
local _blizzOwnedOverlays = {}  -- info overlays for Blizzard-controlled elements
local unlockTipFrame           -- one-time "how to use" tip frame
local pendingAfterClose        -- callback to run after DoClose completes
local selectedMover            -- currently selected mover frame (for arrow key nudging)
local arrowKeyFrame            -- invisible frame that captures arrow key input
local selectElementPicker      -- mover currently in "Select Element" pick mode (nil = off)
local _overlayFadeFrame         -- tiny OnUpdate driver for select-element dimmer fade
local SELECT_ELEMENT_ALPHA = 0.50  -- overlay alpha during select-element pick mode
local SELECT_ELEMENT_FADE  = 0.50  -- seconds for the fade transition

-- Maps barKey → settings location for "Element Options" navigation.
-- module = folder name used by RegisterModule
-- page   = page tab name (PAGE_* constant value)
-- sectionName = exact string passed to SectionHeader()
-- preSelectFn = optional function to set the dropdown before page build
-- Stored on EllesmereUI to avoid adding an upvalue to CreateMover (Lua 5.1 limit: 60).
local function SelectActionBar(key)
    return function()
        -- Direct setter (if the options module already built) + pending flag
        -- (consumed when the Bar Display page builds). Mirrors the unit-frame path.
        if EllesmereUI._setActionBarKey then EllesmereUI._setActionBarKey(key) end
        EllesmereUI._pendingActionBarSelect = key
    end
end
local function SelectUnitFrame(unit)
    return function()
        -- Direct setter (if init already ran) + pending flag (consumed at page build)
        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit(unit) end
        EllesmereUI._pendingUnitSelect = unit
    end
end
-- Mini-frame pre-select factory. Stored on EllesmereUI (not a file-local) to
-- avoid adding a local to this limit-sensitive deferred function. Mini frames
-- (ToT/FoT/Pet/Boss) live on the "Mini Frames" page with their own dropdown.
EllesmereUI._SelectMiniUnit = function(unit)
    return function()
        if EllesmereUI._setMiniUnit then EllesmereUI._setMiniUnit(unit) end
        EllesmereUI._pendingMiniSelect = unit
    end
end
EllesmereUI._ELEMENT_SETTINGS_MAP = {
    -- Main frames: "Main Frames" page; dropdown pre-selected to the unit.
    ["player"]       = { module = "EllesmereUIUnitFrames",       page = "Main Frames",   sectionName = "HEALTH BAR",       preSelectFn = SelectUnitFrame("player"),                   highlightText = "Bar Height" },
    ["target"]       = { module = "EllesmereUIUnitFrames",       page = "Main Frames",   sectionName = "HEALTH BAR",       preSelectFn = SelectUnitFrame("target"),                   highlightText = "Bar Height" },
    ["focus"]        = { module = "EllesmereUIUnitFrames",       page = "Main Frames",   sectionName = "HEALTH BAR",       preSelectFn = SelectUnitFrame("focus"),                    highlightText = "Bar Height" },
    -- Mini frames: "Mini Frames" page; mini dropdown pre-selected to the unit.
    ["pet"]          = { module = "EllesmereUIUnitFrames",       page = "Mini Frames",   sectionName = "HEALTH BAR",       preSelectFn = EllesmereUI._SelectMiniUnit("pet"),          highlightText = "Bar Height" },
    ["targettarget"] = { module = "EllesmereUIUnitFrames",       page = "Mini Frames",   sectionName = "HEALTH BAR",       preSelectFn = EllesmereUI._SelectMiniUnit("targettarget"), highlightText = "Bar Height" },
    ["focustarget"]  = { module = "EllesmereUIUnitFrames",       page = "Mini Frames",   sectionName = "HEALTH BAR",       preSelectFn = EllesmereUI._SelectMiniUnit("focustarget"),  highlightText = "Bar Height" },
    -- Boss frames live on their own "Boss Frames" page (no unit dropdown).
    ["boss"]         = { module = "EllesmereUIUnitFrames",       page = "Boss Frames",   sectionName = "HEALTH BAR",       highlightText = "Bar Height" },
    ["classPower"]   = { module = "EllesmereUIUnitFrames",       page = "Main Frames",   sectionName = "CLASS RESOURCE",   preSelectFn = SelectUnitFrame("player"),                   highlightText = "Enable Class Resource" },

    -- Unit-frame cast bars (configured on the Main Frames page, CAST BAR section, per selected unit)
    ["playerCastbar"] = { module = "EllesmereUIUnitFrames",      page = "Main Frames",   sectionName = "CAST BAR",         preSelectFn = SelectUnitFrame("player"),                   highlightText = "Show Cast Bar" },
    ["targetCastbar"] = { module = "EllesmereUIUnitFrames",      page = "Main Frames",   sectionName = "CAST BAR",         preSelectFn = SelectUnitFrame("target"),                   highlightText = "Show Cast Bar" },
    ["focusCastbar"]  = { module = "EllesmereUIUnitFrames",      page = "Main Frames",   sectionName = "CAST BAR",         preSelectFn = SelectUnitFrame("focus"),                    highlightText = "Show Cast Bar" },

    -- Resource Bars (no dropdown — each bar has its own section)
    ["ERB_Health"]        = { module = "EllesmereUIResourceBars",       page = "Class, Power and Health Bars", sectionName = "HEALTH BAR",           highlightText = "Bar Height" },
    ["ERB_Power"]         = { module = "EllesmereUIResourceBars",       page = "Class, Power and Health Bars", sectionName = "POWER BAR",            highlightText = "Bar Height" },
    ["ERB_ClassResource"] = { module = "EllesmereUIResourceBars",       page = "Class, Power and Health Bars", sectionName = "CLASS RESOURCE BAR",   highlightText = "Bar Height" },
    ["ERB_CastBar"]       = { module = "EllesmereUIResourceBars",       page = "Cast Bar",                     sectionName = "BAR DISPLAY",          highlightText = "Bar Height" },

    -- Action Bars (all share "Bar Display" page; dropdown pre-selected to correct bar)
    ["MainBar"]   = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("MainBar"),   highlightText = "Icon Size" },
    ["Bar2"]      = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("Bar2"),      highlightText = "Icon Size" },
    ["Bar3"]      = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("Bar3"),      highlightText = "Icon Size" },
    ["Bar4"]      = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("Bar4"),      highlightText = "Icon Size" },
    ["Bar5"]      = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("Bar5"),      highlightText = "Icon Size" },
    ["Bar6"]      = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("Bar6"),      highlightText = "Icon Size" },
    ["Bar7"]      = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("Bar7"),      highlightText = "Icon Size" },
    ["Bar8"]      = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("Bar8"),      highlightText = "Icon Size" },
    ["StanceBar"] = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("StanceBar"), highlightText = "Icon Size" },
    ["PetBar"]    = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("PetBar"),    highlightText = "Icon Size" },
    ["XPBar"]     = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("XPBar"),     highlightText = "Icon Size" },
    ["RepBar"]    = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("RepBar"),    highlightText = "Icon Size" },

    -- Action Bars — visibility-only (dropdown pre-selected, scroll to top)
    ["MicroBar"] = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "GENERAL", preSelectFn = SelectActionBar("MicroBagBars") },
    ["BagBar"]   = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "GENERAL", preSelectFn = SelectActionBar("MicroBagBars") },

    -- Aura Buff Reminders
    ["EABR_Reminders"] = { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables", sectionName = "DISPLAY" },

    -- Quality of Life (FPS + Secondary Stats live on the QoL page's EXTRAS section)
    ["EUI_FPS"]            = { module = "EllesmereUIQoL", page = "Quality of Life", sectionName = "EXTRAS", highlightText = "Show FPS Counter" },
    ["EUI_SecondaryStats"] = { module = "EllesmereUIQoL", page = "Quality of Life", sectionName = "EXTRAS", highlightText = "Secondary Stat Display" },

    -- Battle Res + Bloodlust (Keys, Logs & Brez page)
    ["EUI_BattleRes"]      = { module = "EllesmereUIQoL",             page = "Keys, Logs & Brez", sectionName = "BATTLE RES",        highlightText = "Enable BattleRes Icon" },
    ["EUI_Bloodlust"]      = { module = "EllesmereUIQoL",             page = "Keys, Logs & Brez", sectionName = "BLOODLUST TRACKER", highlightText = "Enable Bloodlust Icon" },

    -- Mythic+ Timer
    ["EMT_MythicTimer"]    = { module = "EllesmereUIMythicTimer",     page = "Mythic+ Timer",     sectionName = "DISPLAY",           highlightText = "Scale" },

    -- Raid + Party Frames (separate registered pages/tabs)
    ["RF_RaidFrames"]      = { module = "EllesmereUIRaidFrames",      page = "Raid",              sectionName = "FRAME SIZES",       highlightText = "20 Man Frame Width" },
    ["RF_PartyFrames"]     = { module = "EllesmereUIRaidFrames",      page = "Party",             sectionName = "FRAMES",            highlightText = "Frame Width" },

    -- Cooldown Manager dynamic bars: real per-bar keys are "CDM_<key>" / "TBB_<idx>",
    -- resolved to these shared tab entries by the prefix fallback at the cog lookup site.
    -- No sectionName/preSelectFn: lands at the top of the tab (user request: don't differentiate bars).
    ["CDM_"]               = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
    ["TBB_"]               = { module = "EllesmereUICooldownManager", page = "Tracking Bars" },
}

-- Width Match / Height Match / Anchor To pick modes
-- Only one pick mode can be active at a time. The active picker mover is stored here.
local pickMode = nil           -- nil, "widthMatch", "heightMatch", "anchorTo"
local pickModeMover = nil      -- the mover that initiated the pick mode
local hoveredMover  = nil      -- the currently expanded mover (only one at a time)
local cogHoveredMover = nil    -- the mover whose cog button is currently hovered
local anchorDropdownFrame = nil -- lazy-created dropdown for anchor direction selection
local anchorDropdownCatcher = nil -- click-catcher behind anchor dropdown
local growDropdownFrame = nil -- lazy-created dropdown for grow direction selection
local growDropdownCatcher = nil -- click-catcher behind grow dropdown
local _mouseHeld = false       -- true while left mouse button is held down anywhere

-- Cursor speed tracking for hover intent detection (stored on EllesmereUI to avoid upvalue pressure)
EllesmereUI._unlockCursorX     = 0
EllesmereUI._unlockCursorY     = 0
EllesmereUI._unlockCursorSpeed = 0   -- pixels/sec at UIParent scale
EllesmereUI._unlockHoverSpeedThresh = 80 * 80 -- squared px/sec threshold (avoids sqrt each frame)
EllesmereUI._unlockHoverIntentDelay = 0.12 -- seconds to wait after settling before expanding

-------------------------------------------------------------------------------
--  Anchor / Match DB helpers
--  Stored in EllesmereUIDB.unlockAnchors = { [childKey] = { target=key, side="LEFT"|"RIGHT"|"TOP"|"BOTTOM" } }
--  Width/height matches are applied immediately and saved to the element's
--  own settings — no persistent "match" relationship is stored.
-------------------------------------------------------------------------------
-- Forward declarations for functions defined later but referenced by anchor helpers
local GetBarFrame
local GetBarLabel
local PropagateAnchorChain
local SaveBarPosition
local ApplyAnchorPosition
local ApplyCenterPosition
local GetPositionDB

-------------------------------------------------------------------------------
--  Actual grow direction -- always returns the real direction (never nil).
--  Used for position calculations where we need the true anchor edge.
-------------------------------------------------------------------------------
local function GetBarGrowDirActual(barKey)
    if barKey == "EQT_Tracker" then return "DOWN" end
    if barKey:sub(1, 4) == "CDM_" then
        local rawKey = barKey:sub(5)
        local cdm = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
        local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
        if cdmBars and cdmBars.bars then
            for _, bar in ipairs(cdmBars.bars) do
                if bar.key == rawKey then
                    return bar.growDirection or "CENTER"
                end
            end
        end
        return "CENTER"
    else
        local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
        local s = eab and eab.db and eab.db.profile and eab.db.profile.bars
                  and eab.db.profile.bars[barKey]
        if s then
            return (s.growDirection or "up"):upper()
        end
        return "CENTER"
    end
end

-------------------------------------------------------------------------------
--  Grow direction helper -- reads from the bar's per-profile settings
--  Returns the uppercase grow direction string, or nil if default/unset.
--  Action bar default is "UP", CDM default is nil (centered).
-------------------------------------------------------------------------------
local function GetBarGrowDir(barKey)
    if barKey == "EQT_Tracker" then return "DOWN" end
    if barKey:sub(1, 4) == "CDM_" then
        local rawKey = barKey:sub(5)
        local cdm = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
        local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
        if cdmBars and cdmBars.bars then
            for _, bar in ipairs(cdmBars.bars) do
                if bar.key == rawKey then
                    local g = bar.growDirection
                    if g and g ~= "CENTER" then return g end
                    return nil
                end
            end
        end
        return nil
    else
        local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
        local s = eab and eab.db and eab.db.profile and eab.db.profile.bars
                  and eab.db.profile.bars[barKey]
        if s then
            local g = (s.growDirection or "up"):upper()
            if g == "CENTER" then return nil end
            -- UP is the default for horizontal bars (no indicator needed)
            -- but a meaningful choice for vertical bars (show indicator)
            if g == "UP" and (s.orientation or "horizontal") ~= "vertical" then return nil end
            return g
        end
        return nil
    end
end

local function GetAnchorDB()
    if not EllesmereUIDB then return nil end
    if not EllesmereUIDB.unlockAnchors then
        EllesmereUIDB.unlockAnchors = {}
    end
    return EllesmereUIDB.unlockAnchors
end

local function GetAnchorInfo(barKey)
    local db = GetAnchorDB()
    if not db then return nil end
    return db[barKey]
end

-- RecenterBarAnchor(barKey)
-- Re-applies the grow-direction-aware anchor to the bar frame after a resize
-- so the fixed edge stays put. Must be synchronous (no C_Timer.After) to
-- avoid a visible flicker frame.
-- Defined here (after isUnlocked, movers, registeredElements, GetBarFrame,
-- GetBarGrowDirActual are all in scope) so the closure captures the correct
-- local upvalues.
function EllesmereUI.RecenterBarAnchor(barKey)
    if not isUnlocked then return end
    local elem = registeredElements[barKey]
    if elem and elem.isAnchored and elem.isAnchored() then return end
    local b = GetBarFrame(barKey)
    if not b then return end

    local s = b:GetEffectiveScale()
    local uiS = UIParent:GetEffectiveScale()
    local elemScale = s / uiS

    local bL = b:GetLeft()
    local bT = b:GetTop()
    if not bL or not bT then return end

    local w = (b:GetWidth() or 0) * elemScale
    local h = (b:GetHeight() or 0) * elemScale
    if w < 1 or h < 1 then return end

    -- Center in UIParent-BOTTOMLEFT space
    local uiCX = bL * elemScale + w * 0.5
    local uiCY = bT * elemScale - h * 0.5

    -- Pick anchor based on grow direction so the fixed edge stays put
    local growDir = GetBarGrowDirActual(barKey)
    local anchor, aX, aY
    if growDir == "RIGHT" then
        anchor = "LEFT"
        aX = bL * elemScale
        aY = uiCY
    elseif growDir == "LEFT" then
        anchor = "RIGHT"
        aX = (bL * elemScale) + w
        aY = uiCY
    elseif growDir == "DOWN" then
        anchor = "TOP"
        aX = uiCX
        aY = bT * elemScale
    elseif growDir == "UP" then
        anchor = "BOTTOM"
        aX = uiCX
        aY = bT * elemScale - h
    else
        anchor = "CENTER"
        aX = uiCX
        aY = uiCY
    end

    -- Convert to CENTER-relative (the unlock mode system's standard format)
    local uiW, uiH = UIParent:GetSize()
    local cRelX = aX - uiW / 2
    local cRelY = aY - uiH / 2

    -- Snap to physical pixel grid to prevent subpixel coordinates from
    -- persisting into pendingPositions -> CommitPositions -> SavedVariables.
    local PPr = PP or (EllesmereUI and EllesmereUI.PP)
    if PPr then
        if anchor == "CENTER" then
            cRelX = PPr.SnapCenterForDim(cRelX, w, uiS)
            cRelY = PPr.SnapCenterForDim(cRelY, h, uiS)
        else
            cRelX = PPr.SnapForES(cRelX, uiS)
            cRelY = PPr.SnapForES(cRelY, uiS)
        end
    end

    pcall(function()
        b:ClearAllPoints()
        b:SetPoint(anchor, UIParent, "CENTER", cRelX, cRelY)
    end)

    -- Keep mover's stored center in sync so drag/snap logic stays consistent
    local m = movers[barKey]
    if m and m._setCenterXY then
        m._setCenterXY(uiCX, uiCY - uiH)
    end
end

local function SetAnchorInfo(childKey, targetKey, side, offsetX, offsetY)
    local db = GetAnchorDB()
    if not db then return end
    db[childKey] = { target = targetKey, side = side, offsetX = offsetX, offsetY = offsetY }
end

local function ClearAnchorInfo(childKey)
    local db = GetAnchorDB()
    if not db then return end
    db[childKey] = nil
end

local function IsAnchored(barKey)
    local info = GetAnchorInfo(barKey)
    if info ~= nil then return true end
    local elem = registeredElements[barKey]
    return elem and elem.isAnchored and elem.isAnchored() or false
end

-- Width/Height match persistent links
local MatchH = {}

function MatchH.GetWidthMatchDB()
    if not EllesmereUIDB then return nil end
    if not EllesmereUIDB.unlockWidthMatch then
        EllesmereUIDB.unlockWidthMatch = {}
    end
    return EllesmereUIDB.unlockWidthMatch
end


function MatchH.GetHeightMatchDB()
    if not EllesmereUIDB then return nil end
    if not EllesmereUIDB.unlockHeightMatch then
        EllesmereUIDB.unlockHeightMatch = {}
    end
    return EllesmereUIDB.unlockHeightMatch
end

function MatchH.GetWidthMatchInfo(barKey)
    local db = MatchH.GetWidthMatchDB()
    return db and db[barKey] or nil
end

function MatchH.GetHeightMatchInfo(barKey)
    local db = MatchH.GetHeightMatchDB()
    return db and db[barKey] or nil
end

-- Detect cycles: walk the chain from targetKey and check if we'd
-- reach childKey, which would create an infinite loop.
function MatchH.WouldCreateCycle(db, childKey, targetKey)
    local visited = {}
    local current = targetKey
    while current do
        if current == childKey then return true end
        if visited[current] then return false end
        visited[current] = true
        current = db[current]
    end
    return false
end

function MatchH.SetWidthMatch(childKey, targetKey)
    local db = MatchH.GetWidthMatchDB()
    if not db then return end
    if MatchH.WouldCreateCycle(db, childKey, targetKey) then
        -- Break the cycle: clear the link that targetKey has, then set ours
        db[targetKey] = nil
    end
    db[childKey] = targetKey
end

function MatchH.SetHeightMatch(childKey, targetKey)
    local db = MatchH.GetHeightMatchDB()
    if not db then return end
    if MatchH.WouldCreateCycle(db, childKey, targetKey) then
        db[targetKey] = nil
    end
    db[childKey] = targetKey
end

function MatchH.ClearWidthMatch(childKey)
    local db = MatchH.GetWidthMatchDB()
    if not db then return end
    -- Persist current width so elements with "0 = match parent" defaults
    -- don't revert on reload. The element's setWidth saves to its own DB.
    local elem = registeredElements[childKey]
    if elem and elem.setWidth then
        local frame = GetBarFrame(childKey)
        if frame then
            local curW = frame:GetWidth()
            if curW and curW > 0 then
                pcall(elem.setWidth, childKey, curW)
            end
        end
    end
    db[childKey] = nil
end

function MatchH.ClearHeightMatch(childKey)
    local db = MatchH.GetHeightMatchDB()
    if not db then return end
    local elem = registeredElements[childKey]
    if elem and elem.setHeight then
        local frame = GetBarFrame(childKey)
        if frame then
            local curH = frame:GetHeight()
            if curH and curH > 0 then
                pcall(elem.setHeight, childKey, curH)
            end
        end
    end
    db[childKey] = nil
end

-------------------------------------------------------------------------------
--  Public API: query width/height match state from any addon
-------------------------------------------------------------------------------
function EllesmereUI.GetWidthMatchTarget(barKey)
    local db = MatchH.GetWidthMatchDB()
    return db and db[barKey] or nil
end

function EllesmereUI.GetHeightMatchTarget(barKey)
    local db = MatchH.GetHeightMatchDB()
    return db and db[barKey] or nil
end

-- Returns (disabled_fn, tooltip_fn, rawTooltip) for use on width/height sliders.
-- Composes with an optional existing disabled/tooltip so both conditions work.
-- rawTooltip=true tells the widget system to skip DisabledTooltip wrapping.
function EllesmereUI.MatchGuard(barKey, axis, existingDisabled, existingTooltip)
    local isWidth = (axis == "Width" or axis == "width")
    local getFn = isWidth and EllesmereUI.GetWidthMatchTarget or EllesmereUI.GetHeightMatchTarget
    local disabled = function()
        if getFn(barKey) then return true end
        if existingDisabled then return existingDisabled() end
        return false
    end
    local tooltip = function()
        local target = getFn(barKey)
        if target then
            local name = (EllesmereUI.GetBarLabel and EllesmereUI.GetBarLabel(target)) or target
            return axis .. " matched to " .. name .. ". Unmatch in Unlock Mode to edit."
        end
        if existingTooltip then
            return type(existingTooltip) == "function" and existingTooltip() or existingTooltip
        end
        return ""
    end
    local rawTooltip = function()
        return getFn(barKey) ~= nil
    end
    return disabled, tooltip, rawTooltip
end

-------------------------------------------------------------------------------
--  PruneStaleLinks -- removes all anchor/match relationships for a key,
--  both where the key is the child AND where it is the target.
--  Call when an element is unregistered so nothing points to a ghost key.
-------------------------------------------------------------------------------
local function PruneStaleLinks(key)
    if not EllesmereUIDB then return end

    -- Anchors: key as child
    local anchors = EllesmereUIDB.unlockAnchors
    if anchors then
        anchors[key] = nil
        -- key as target -- scan all children
        for childKey, info in pairs(anchors) do
            if info and info.target == key then
                anchors[childKey] = nil
            end
        end
    end

    -- Width matches: key as child or target
    local wm = EllesmereUIDB.unlockWidthMatch
    if wm then
        wm[key] = nil
        for childKey, targetKey in pairs(wm) do
            if targetKey == key then wm[childKey] = nil end
        end
    end

    -- Height matches: key as child or target
    local hm = EllesmereUIDB.unlockHeightMatch
    if hm then
        hm[key] = nil
        for childKey, targetKey in pairs(hm) do
            if targetKey == key then hm[childKey] = nil end
        end
    end
end
EllesmereUI.PruneStaleLinks = PruneStaleLinks

-- Override UnregisterUnlockElement so cleanup runs whenever an element
-- is removed (e.g. a custom CDM bar is deleted).
function EllesmereUI:UnregisterUnlockElement(key)
    self._unlockRegisteredElements[key] = nil
    self._unlockRegistrationDirty = true
    PruneStaleLinks(key)
end

-- Validate all stored relationships against currently registered elements.
-- Removes any that point to an element that no longer exists.
-- Runs once on load so stale data from a previous session is cleaned up.
local function ValidateStoredLinks()
    if not EllesmereUIDB then return end
    local elems = EllesmereUI._unlockRegisteredElements

    local anchors = EllesmereUIDB.unlockAnchors
    if anchors then
        for childKey, info in pairs(anchors) do
            if not elems[childKey] or (info and not elems[info.target]) then
                anchors[childKey] = nil
            end
        end
    end

    local wm = EllesmereUIDB.unlockWidthMatch
    if wm then
        for childKey, targetKey in pairs(wm) do
            if not elems[childKey] or not elems[targetKey] then
                wm[childKey] = nil
            elseif (elems[childKey].noResize and not elems[childKey].allowMatchSource)
                or elems[targetKey].noResize then
                wm[childKey] = nil
            end
        end
    end

    local hm = EllesmereUIDB.unlockHeightMatch
    if hm then
        for childKey, targetKey in pairs(hm) do
            if not elems[childKey] or not elems[targetKey] then
                hm[childKey] = nil
            elseif (elems[childKey].noResize and not elems[childKey].allowMatchSource)
                or elems[targetKey].noResize then
                hm[childKey] = nil
            end
        end
    end
end

-- Apply width/height match: sync source size from target
-- _propagatingMatch prevents re-entrant loops: setWidth triggers OnSizeChanged
-- which calls NotifyElementResized which would call PropagateWidthMatch again.
-- Exposed on EllesmereUI so child addons' setWidth can detect match propagation.
local _propagatingMatch = false
EllesmereUI._propagatingMatch = false

function MatchH.ApplyWidthMatch(sourceKey, targetKey)
    local targetElem = registeredElements[targetKey]
    local targetBar = GetBarFrame(targetKey)
    local targetW
    if targetElem and targetElem.getSize then
        targetW = targetElem.getSize(targetKey)
    elseif targetBar then
        targetW = targetBar:GetWidth()
    end
    if targetW and targetW > 0 then
        -- Snap to physical pixel grid (round-to-nearest, not truncate).
        -- PP.Scale truncates, which drops a pixel on boundary values due
        -- to floating point. SnapForES uses floor(x/px + 0.5) which is safe.
        local PPm = EllesmereUI and EllesmereUI.PP
        if PPm and PPm.SnapForES and targetBar then
            targetW = PPm.SnapForES(targetW, targetBar:GetEffectiveScale())
        else
            targetW = floor(targetW + 0.5)
        end
        -- Convert target width to source's coordinate space if scales differ
        local sourceBar = GetBarFrame(sourceKey)
        if targetBar and sourceBar then
            local tES = targetBar:GetEffectiveScale()
            local sES = sourceBar:GetEffectiveScale()
            if math.abs(tES - sES) > 0.001 then
                targetW = targetW * tES / sES
            end
        end
        local sourceElem = registeredElements[sourceKey]
        if sourceElem and sourceElem.setWidth then
            if isUnlocked then
                local sb = GetBarFrame(sourceKey)
                local savedAlpha = sb and EllesmereUI._GetFFD(sb).restoreAlpha
                if sb and not savedAlpha then sb:SetAlpha(0) end
                _propagatingMatch = true; EllesmereUI._propagatingMatch = true
                pcall(sourceElem.setWidth, sourceKey, targetW)
                _propagatingMatch = false; EllesmereUI._propagatingMatch = false
                EllesmereUI.RecenterBarAnchor(sourceKey)
                if sb and not savedAlpha then
                    C_Timer.After(0, function() sb:SetAlpha(1) end)
                end
                local m = movers[sourceKey]
                if m then m:SyncSize() end
            else
                _propagatingMatch = true; EllesmereUI._propagatingMatch = true
                pcall(sourceElem.setWidth, sourceKey, targetW)
                _propagatingMatch = false; EllesmereUI._propagatingMatch = false
                if sourceElem.loadPosition then
                    local pos = sourceElem.loadPosition(sourceKey)
                    if pos and pos.point == "CENTER" and pos.relPoint == "CENTER" then
                        ApplyCenterPosition(sourceKey, pos)
                    end
                end
            end
        end
    end
end

function MatchH.ApplyHeightMatch(sourceKey, targetKey)
    local targetElem = registeredElements[targetKey]
    local targetBar = GetBarFrame(targetKey)
    local _, targetH
    if targetElem and targetElem.getSize then
        _, targetH = targetElem.getSize(targetKey)
    elseif targetBar then
        targetH = targetBar:GetHeight()
    end
    if targetH and targetH > 0 then
        local PPm = EllesmereUI and EllesmereUI.PP
        if PPm and PPm.SnapForES and targetBar then
            targetH = PPm.SnapForES(targetH, targetBar:GetEffectiveScale())
        else
            targetH = floor(targetH + 0.5)
        end
        local sourceElem = registeredElements[sourceKey]
        if sourceElem and sourceElem.setHeight then
            if isUnlocked then
                local sb = GetBarFrame(sourceKey)
                local savedAlpha = sb and EllesmereUI._GetFFD(sb).restoreAlpha
                if sb and not savedAlpha then sb:SetAlpha(0) end
                _propagatingMatch = true; EllesmereUI._propagatingMatch = true
                pcall(sourceElem.setHeight, sourceKey, targetH)
                _propagatingMatch = false; EllesmereUI._propagatingMatch = false
                EllesmereUI.RecenterBarAnchor(sourceKey)
                if sb and not savedAlpha then
                    C_Timer.After(0, function() sb:SetAlpha(1) end)
                end
                local m = movers[sourceKey]
                if m then m:SyncSize() end
            else
                _propagatingMatch = true; EllesmereUI._propagatingMatch = true
                pcall(sourceElem.setHeight, sourceKey, targetH)
                _propagatingMatch = false; EllesmereUI._propagatingMatch = false
                if sourceElem.loadPosition then
                    local pos = sourceElem.loadPosition(sourceKey)
                    if pos and pos.point == "CENTER" and pos.relPoint == "CENTER" then
                        ApplyCenterPosition(sourceKey, pos)
                    end
                end
            end
        end
    end
end

-- Pending anchor propagation keys -- batched into a single deferred frame
local _pendingAnchorKeys = {}
local _anchorBatchScheduled = false

local function ScheduleAnchorBatch()
    if _anchorBatchScheduled then return end
    _anchorBatchScheduled = true
    C_Timer.After(0, function()
        _anchorBatchScheduled = false
        if isUnlocked then return end  -- unlock mode handles its own saves
        local keys = _pendingAnchorKeys
        _pendingAnchorKeys = {}
        -- During profile swap, skip AB bars entirely. LayoutBar already
        -- positioned them from the new profile; stale resize events would
        -- move them to wrong spots. CDM bars pass through (need post-settle).
        local abSkip = EllesmereUI._abAnchorSuppressed and EllesmereUI._abBarKeys
        for k, axis in pairs(keys) do
            if abSkip and abSkip[k] then
                -- skip: AB bar during profile swap
            else
            -- If this element itself is anchored, re-apply its own position
            -- first (handles the case where the element resized and needs to
            -- reposition relative to its anchor target).
            -- Skip AB growth bars: their position from LayoutBar/applyPos is
            -- authoritative. The center-based offset gives wrong edge when
            -- width changed, and repositioning causes visual drift.
            local anchorDB = GetAnchorDB()
            if anchorDB then
                local ownInfo = anchorDB[k]
                if ownInfo and ownInfo.target then
                    -- Skip AB bars: their position from LayoutBar/applyPos is
                    -- authoritative. Reapplying from the offset causes drift
                    -- (stale offset from previous direction or width change).
                    -- Skip AB bars: their position from LayoutBar/applyPos is
                    -- authoritative. Reapplying from the offset causes drift
                    -- (stale offset from previous direction or width change).
                    local isAB = EllesmereUI._abBarKeys and EllesmereUI._abBarKeys[k]
                    if not isAB then
                        ApplyAnchorPosition(k, ownInfo.target, ownInfo.side)
                    end
                end
            end
            -- Propagate with axis filter (nil = all axes)
            local propagateAxis = (axis == "all") and nil or axis
            PropagateAnchorChain(k, nil, propagateAxis)
            end -- abSkip else
        end
        -- No position persistence here. Positions are only saved by
        -- unlock mode's Save & Exit (CommitPositions). The anchor chain
        -- repositioned frames in-place; no DB write needed.
        wipe(pendingPositions)
    end)
end

-- Settle re-apply debounce: anchored CDM bars and their anchor targets resize
-- several times on login (icon population + the 1/3/6s refresh ladder + trinket
-- retries) with no single reliable "done" signal. Rather than guess a fixed
-- delay, watch for QUIESCENCE: every real resize (NotifyElementResized) restarts
-- this short cancelable timer, and only after no resize for the quiet window do
-- we force ONE full anchor re-apply against the now-final chain. Re-arming makes
-- an early fire harmless (the next resize restarts it) and means rapid resize
-- churn never actually fires -- it only lands during a lull. The 0.25s window
-- must exceed the 0.2s resize throttle so a burst of throttled reanchors keeps
-- the timer alive instead of mis-firing between them. Phase 1: the re-apply
-- still pins CDM growth bars to their absolute saved edge (no follow), so this
-- only eliminates residual login drift and changes nothing the user sees.
function EllesmereUI.ScheduleSettleReapply()
    if isUnlocked then return end                            -- unlock owns positioning
    if EllesmereUI._settleReapplyInProgress then return end  -- never re-arm from our own pass
    if EllesmereUI._settleTimer then EllesmereUI._settleTimer:Cancel() end
    EllesmereUI._settleTimer = C_Timer.NewTimer(0.25, function()
        EllesmereUI._settleTimer = nil
        if isUnlocked then return end
        -- Chain has settled: from here the absolute pin may pick up the target-
        -- follow delta (Phase 2). Flipping it now -- only after true quiescence --
        -- guarantees the anchor target is at its settled position, so the first
        -- follow-aware pass computes a ~0 delta on a same-spec login and the
        -- pin->follow handoff produces no visible jump.
        EllesmereUI._anchorFollowReady = true
        if EllesmereUI.ReapplyAllUnlockAnchorsForced then
            EllesmereUI._settleReapplyInProgress = true
            pcall(EllesmereUI.ReapplyAllUnlockAnchorsForced)
            EllesmereUI._settleReapplyInProgress = false
        end
    end)
end

function EllesmereUI.PropagateWidthMatch(key)
    local db = MatchH.GetWidthMatchDB()
    if not db then return end
    -- Push width to any elements that match this key, then recurse
    -- so chained matches (A -> B -> C) propagate fully.
    local visited = { [key] = true }
    local function pushChildren(parentKey)
        for childKey, tKey in pairs(db) do
            if tKey == parentKey and not visited[childKey] then
                visited[childKey] = true
                MatchH.ApplyWidthMatch(childKey, parentKey)
                _pendingAnchorKeys[childKey] = "width"
                pushChildren(childKey)
            end
        end
    end
    pushChildren(key)
    ScheduleAnchorBatch()
end

function EllesmereUI.PropagateHeightMatch(key)
    local db = MatchH.GetHeightMatchDB()
    if not db then return end
    local visited = { [key] = true }
    local function pushChildren(parentKey)
        for childKey, tKey in pairs(db) do
            if tKey == parentKey and not visited[childKey] then
                visited[childKey] = true
                MatchH.ApplyHeightMatch(childKey, parentKey)
                _pendingAnchorKeys[childKey] = "height"
                pushChildren(childKey)
            end
        end
    end
    pushChildren(key)
    ScheduleAnchorBatch()
end

-- DEBUG: confirm propagation functions are defined at file-load time
-------------------------------------------------------------------------------
--  Centralized resize notification
--  Any addon can call EllesmereUI.NotifyElementResized(key) after changing
--  a frame's size. This propagates width/height matches and anchor chains
--  so all dependent elements update automatically.
--  Additionally, OnSizeChanged hooks on registered element frames call this
--  automatically, so most addons don't need to call it manually.
-------------------------------------------------------------------------------
local _resizeNotifyThrottle = {}  -- [key] = GetTime() of last notify
local _resizeLastSize = {}  -- [key] = { w = ..., h = ... }
local RESIZE_THROTTLE_SEC = 0.05 -- ignore rapid-fire size changes within 50ms

-- Flag set by LayoutBar (action bars) to suppress position re-application
-- during SetSize. LayoutBar handles its own edge re-anchoring.
EllesmereUI._layoutBarResizing = nil

function EllesmereUI.NotifyElementResized(key)
    if isUnlocked then return end  -- unlock mode owns positioning
    -- Skip if we're inside a width/height match propagation to avoid loops:
    -- setWidth/setHeight -> rebuild -> OnSizeChanged -> NotifyElementResized
    if _propagatingMatch then return end
    -- When LayoutBar is handling positioning (custom grow directions), skip
    -- only the position re-application below but still run width/height match
    -- propagation and anchor chains.
    local layoutBarHandled = (EllesmereUI._layoutBarResizing == key)
    -- Suppression scope (spec swap / zone transition):
    --   The guard exists because CDM bar icon counts fluctuate during these
    --   windows as Blizzard recycles viewer frames, and a transient empty
    --   width could be propagated to a width-MATCHED sibling, corrupting it
    --   until the user manually re-matches.
    --
    --   Anchor propagation has no equivalent risk: it only repositions
    --   children to follow wherever the target currently is, which is always
    --   visually correct -- worst case a child re-anchors twice in quick
    --   succession (once with transient target size, once with final), and
    --   the second pass corrects to the final position.
    --
    --   So we only suppress the WIDTH/HEIGHT MATCH block below, not the
    --   anchor cascade. Without this split, spec-swap-induced resizes on
    --   one element (e.g. Class Resource shrinking 1px on the new spec's
    --   pip count) leave anchored children stranded at the old position
    --   with no event ever firing to re-cascade them.
    local suppressMatchProp = EllesmereUI._specProfileSwitching
                           or EllesmereUI._zoneTransitionActive
    -- Throttle: skip if we just processed this key
    local now = GetTime()
    if _resizeNotifyThrottle[key] and (now - _resizeNotifyThrottle[key]) < RESIZE_THROTTLE_SEC then
        return
    end
    _resizeNotifyThrottle[key] = now

    -- Detect which axis changed by comparing to last known size
    local bar = GetBarFrame(key)
    local curW = bar and bar:GetWidth() or 0
    local curH = bar and bar:GetHeight() or 0
    local prev = _resizeLastSize[key]
    local widthChanged = not prev or math.abs(curW - prev.w) > 0.5
    local heightChanged = not prev or math.abs(curH - prev.h) > 0.5

    _resizeLastSize[key] = { w = curW, h = curH }

    -- Reapply own anchor first (if this element is anchored to something,
    -- its position may need adjusting after its own size changed).
    -- For unanchored elements, re-apply the stored CENTER position so the
    -- WoW anchor stays CENTER after addon rebuilds that may use TOPLEFT.
    -- Skip when LayoutBar already positioned the bar from its captured edge
    -- to avoid CENTER->edge->CENTER round-trip drift.
    -- During profile swap, skip AB bar position re-apply. LayoutBar already
    -- positioned them from the new profile; re-applying here uses stale
    -- offsets and causes a 1-frame blink. CDM bars are not suppressed.
    local abSwapSkip = EllesmereUI._abAnchorSuppressed
        and EllesmereUI._abBarKeys and EllesmereUI._abBarKeys[key]
    if not layoutBarHandled and not abSwapSkip then
        local anchorDB = GetAnchorDB()
        local ownAnchor = anchorDB and anchorDB[key]
        if ownAnchor and ownAnchor.target then
            if EllesmereUI.ReapplyOwnAnchor then
                EllesmereUI.ReapplyOwnAnchor(key)
            end
        else
            -- Unanchored: re-apply stored CENTER position
            local elem = registeredElements[key]
            local pos
            if elem and elem.loadPosition then
                pos = elem.loadPosition(key)
            else
                local db = GetPositionDB()
                pos = db and db[key]
            end
            if pos and pos.point == "CENTER" and pos.relPoint == "CENTER" then
                ApplyCenterPosition(key, pos)
            end
        end
    end

    -- Propagate width/height matches to dependents.
    -- Suppressed during spec-swap / zone-transition because transient CDM
    -- icon counts can momentarily produce wrong widths that would corrupt
    -- width-matched siblings (see suppressMatchProp comment above).
    if not suppressMatchProp then
        local wdb = MatchH.GetWidthMatchDB()
        if wdb then
            local hasChildren = false
            for childKey, tKey in pairs(wdb) do
                if tKey == key then hasChildren = true; break end
            end
            if hasChildren then
                EllesmereUI.PropagateWidthMatch(key)
            end
            -- Re-pull from own target if this element is a width-match child
            local ownTarget = wdb[key]
            if ownTarget and widthChanged then
                MatchH.ApplyWidthMatch(key, ownTarget)
            end
        end
        local hdb = MatchH.GetHeightMatchDB()
        if hdb then
            local hasChildren = false
            for childKey, tKey in pairs(hdb) do
                if tKey == key then hasChildren = true; break end
            end
            if hasChildren then
                EllesmereUI.PropagateHeightMatch(key)
            end
            -- Re-pull from own target if this element is a height-match child
            local ownHTarget = hdb[key]
            if ownHTarget and heightChanged then
                MatchH.ApplyHeightMatch(key, ownHTarget)
            end
        end
    end

    -- Propagate anchor chain to children anchored to this element
    -- Use detected axis so children on the unaffected axis don't move
    local axis
    if widthChanged and heightChanged then
        axis = "all"
    elseif widthChanged then
        axis = "width"
    elseif heightChanged then
        axis = "height"
    end
    if axis then
        local existing = _pendingAnchorKeys[key]
        if existing and existing ~= axis then
            _pendingAnchorKeys[key] = "all"
        else
            _pendingAnchorKeys[key] = axis
        end
        ScheduleAnchorBatch()
        -- Arm the settle debounce so a forced full re-apply lands once the whole
        -- chain stops resizing -- catches the late login/spec-swap resizes the
        -- one-shot reanchor misses. See ScheduleSettleReapply.
        if EllesmereUI.ScheduleSettleReapply then EllesmereUI.ScheduleSettleReapply() end
    end
end

-------------------------------------------------------------------------------
--  Apply ALL width/height matches globally (used on login/reload)
-------------------------------------------------------------------------------
-- Break any circular chains in a match DB before applying.
-- Walks each chain; if a cycle is found, removes the last link
-- that closes the loop.
function MatchH.BreakMatchCycles(db)
    if not db then return end
    local safe = {}  -- keys confirmed cycle-free
    for childKey in pairs(db) do
        if not safe[childKey] then
            local visited = {}
            local current = childKey
            while current and db[current] do
                if visited[current] then
                    -- current closes the cycle; break it
                    db[current] = nil
                    break
                end
                visited[current] = true
                current = db[current]
            end
            -- Mark all visited keys as safe
            for k in pairs(visited) do safe[k] = true end
        end
    end
end

-- Apply every entry in a width/height match DB in dependency order
-- (roots first, then their children, then grandchildren). This is
-- required for chains like A -> B -> C: if C is processed before B,
-- C reads B's stale width and ends up wrong even if B updates after.
-- BreakMatchCycles runs before this, so the graph is guaranteed acyclic;
-- the visited guard is defensive belt-and-suspenders.
local function ApplyMatchesInDependencyOrder(db, applyFn)
    if not db then return end
    local depth = {}
    local function GetDepth(k, visiting)
        if depth[k] ~= nil then return depth[k] end
        if visiting[k] then return 0 end
        visiting[k] = true
        local target = db[k]
        if target and db[target] then
            depth[k] = 1 + GetDepth(target, visiting)
        else
            depth[k] = 0
        end
        visiting[k] = nil
        return depth[k]
    end
    local order = {}
    for childKey in pairs(db) do
        GetDepth(childKey, {})
        order[#order + 1] = childKey
    end
    table.sort(order, function(a, b) return depth[a] < depth[b] end)
    for _, childKey in ipairs(order) do
        applyFn(childKey, db[childKey])
    end
end

local function ApplyAllWidthHeightMatches()
    -- Skip while CDM is mid-rebuild. CDM bars set this flag during their
    -- own rebuild flow (login, spec swap, talent reconcile, etc.) and clear
    -- it after CollectAndReanchor finishes populating cdmBarIcons. Width
    -- matching that fires inside this window would read STALE bar widths
    -- (sized for the previous spec's icon count) and propagate them as
    -- the new target width. CDM itself fires ApplyAllWidthHeightMatches
    -- at the end of its rebuild via _pendingApplyOnReanchor, so skipping
    -- here is safe -- the right pass runs immediately after.
    -- _cdmRebuilding guard removed: CDM's own ApplyAllWidthHeightMatches
    -- call at the end of CollectAndReanchor corrects any transient widths.
    -- The guard was blocking unrelated UF height matches during spec swap.
    -- Break any circular chains from old data before applying
    MatchH.BreakMatchCycles(MatchH.GetWidthMatchDB())
    MatchH.BreakMatchCycles(MatchH.GetHeightMatchDB())
    -- Width matches (dependency-sorted: roots first)
    ApplyMatchesInDependencyOrder(MatchH.GetWidthMatchDB(), MatchH.ApplyWidthMatch)
    -- Height matches (dependency-sorted)
    ApplyMatchesInDependencyOrder(MatchH.GetHeightMatchDB(), MatchH.ApplyHeightMatch)
end

-------------------------------------------------------------------------------
--  OnSizeChanged hook for registered element frames
--  Automatically fires NotifyElementResized when a frame changes size,
--  so dependent elements (width-matched, anchored) update without the
--  source addon needing to call anything.
-------------------------------------------------------------------------------
local _sizeHookedFrames = {}  -- [frame] = true
local _pointHookedFrames = {} -- [frame] = true

-- Last-seen screen position per key. NotifyElementMoved compares current
-- GetLeft/GetTop to these to detect real position changes (SetPoint can be
-- called many times in a frame as part of ClearAllPoints + SetPoint pairs).
local _lastScreenPos = {}  -- [key] = { l = ..., t = ... }
local _moveCheckScheduled = {}  -- [key] = true (dedupes same-frame checks)

-- Fires the anchor cascade for `key` if its frame actually moved on screen
-- since last check. Deferred to end-of-frame so a ClearAllPoints + SetPoint
-- pair coalesces into a single check against the final position.
--
-- WHY THIS EXISTS: NotifyElementResized only fires from OnSizeChanged, and
-- session 31's Fix 6 cascade only triggers from ApplyAnchorPosition. Pure
-- position changes that happen through an addon's own SetPoint call (e.g.
-- ERB re-applying sp.unlockPos on every Class Resource rebuild) hit neither
-- emitter, so anchored children never got the "your target moved" signal.
-- This closes that gap by detecting position changes at the SetPoint hook.
local function NotifyElementMoved(key)
    if isUnlocked then return end  -- unlock mode owns positioning
    if _moveCheckScheduled[key] then return end
    _moveCheckScheduled[key] = true
    C_Timer.After(0, function()
        _moveCheckScheduled[key] = nil
        if isUnlocked then return end
        local bar = GetBarFrame(key)
        if not bar then return end
        local l, t = bar:GetLeft(), bar:GetTop()
        if not l or not t then return end
        local prev = _lastScreenPos[key]
        if prev and math.abs(l - prev.l) < 0.5 and math.abs(t - prev.t) < 0.5 then
            return  -- position unchanged (within half a physical pixel)
        end
        _lastScreenPos[key] = { l = l, t = t }
        -- Convergence: ApplyAnchorPosition's idempotent guard (session 31
        -- Fix 3) skips SetPoint when the child is already within 0.5px of
        -- its computed target, so the cascade drains in a bounded number
        -- of passes. Each ApplyAnchorPosition call re-enters this hook on
        -- the child, but the position check above returns early when the
        -- frame has settled, stopping further queueing.
        if EllesmereUI.PropagateAnchorChain then
            EllesmereUI.PropagateAnchorChain(key, "all")
        end
    end)
end

local function HookFrameSizeChanged(key)
    -- Skip all hooks on chat frames: ChatFrame1 is docked inside
    -- Blizzard's secure FCF_OpenTemporaryWindow chain, and any addon
    -- code in OnSizeChanged/SetPoint hooks taints the execution context.
    -- Chat handles its own position and size persistence.
    if key and key:find("^ECHAT_") then return end
    local bar = GetBarFrame(key)
    if not bar then return end
    if not _sizeHookedFrames[bar] then
        _sizeHookedFrames[bar] = true
        bar:HookScript("OnSizeChanged", function()
            if isUnlocked then return end
            EllesmereUI.NotifyElementResized(key)
        end)
    end
    if not _pointHookedFrames[bar] then
        _pointHookedFrames[bar] = true
        hooksecurefunc(bar, "SetPoint", function()
            NotifyElementMoved(key)
        end)
    end
end

-- Wrap RegisterUnlockElements so newly registered elements get OnSizeChanged
-- hooks installed automatically (handles late registrations like CDM bars).
do
    local origRegister = EllesmereUI.RegisterUnlockElements
    function EllesmereUI:RegisterUnlockElements(elements, folder)
        origRegister(self, elements, folder)
        -- Defer hook installation so the frame has time to be created/sized
        C_Timer.After(0.1, function()
            for _, elem in ipairs(elements) do
                if elem.key then
                    HookFrameSizeChanged(elem.key)
                end
            end
        end)
    end
end

-- Smoothly fade the background overlay between normal and select-element alpha
local function FadeOverlayForSelectElement(entering)
    if not unlockFrame or not unlockFrame._overlay then return end
    local startA = entering and (unlockFrame._overlayMaxAlpha or 0.20) or SELECT_ELEMENT_ALPHA
    local endA   = entering and SELECT_ELEMENT_ALPHA or (unlockFrame._overlayMaxAlpha or 0.20)
    if not _overlayFadeFrame then
        _overlayFadeFrame = CreateFrame("Frame")
    end
    local elapsed = 0
    _overlayFadeFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = math.min(elapsed / SELECT_ELEMENT_FADE, 1)
        local a = startA + (endA - startA) * t
        unlockFrame._overlay:SetColorTexture(0.02, 0.03, 0.04, a)
        if t >= 1 then self:SetScript("OnUpdate", nil) end
    end)
end

-- Cancel any active pick mode (width match, height match, anchor to, or snap select)
-- Restores overlay text and screen brightness
local function CancelPickMode()
    if pickModeMover then
        local m = pickModeMover
        -- Restore overlay text visibility only if still hovered
        if m._hidePickText then m._hidePickText() end
        if m:IsMouseOver() then
            if m._showOverlayText then m._showOverlayText() end
        else
            if m._hideOverlayText then m._hideOverlayText() end
        end
        pickMode = nil
        pickModeMover = nil
        FadeOverlayForSelectElement(false)
    end
    -- Also cancel snap select-element picker if active
    if selectElementPicker then
        local picker = selectElementPicker
        picker._snapTarget = picker._preSelectTarget
        picker._preSelectTarget = nil
        if picker._updateSnapLabel then picker._updateSnapLabel() end
        selectElementPicker = nil
        FadeOverlayForSelectElement(false)
    end
    -- Hide anchor dropdown if open
    if anchorDropdownFrame then anchorDropdownFrame:Hide() end
    if anchorDropdownCatcher then anchorDropdownCatcher:Hide() end
    if growDropdownFrame then growDropdownFrame:Hide() end
    if growDropdownCatcher then growDropdownCatcher:Hide() end
end

-- Red border flash animation for error feedback (e.g. trying to drag an anchored element)
local function FlashRedBorder(m)
    if not m or not m._brd then return end
    -- Create a dedicated red border overlay if not yet created
    if not m._redFlashBrd then
        m._redFlashBrd = EllesmereUI.MakeBorder(m, 1, 0.2, 0.2, 0)
        m._redFlashBrd._frame:SetFrameLevel(m:GetFrameLevel() + 4)
        local PP = EllesmereUI and EllesmereUI.PP
        if PP then PP.SetBorderSize(m._redFlashBrd._frame, 2) end
    end
    local brd = m._redFlashBrd
    local elapsed = 0
    if not m._redFlashFrame then
        m._redFlashFrame = CreateFrame("Frame")
    end
    m._redFlashFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.8 then
            local a = 0.5 + 0.5 * math.sin(elapsed * 10)
            brd:SetColor(1, 0.2, 0.2, a)
        elseif elapsed < 1.5 then
            brd:SetColor(1, 0.2, 0.2, math.max(0, 1 - (elapsed - 0.8) / 0.7))
        else
            brd:SetColor(1, 0.2, 0.2, 0)
            self:SetScript("OnUpdate", nil)
        end
    end)
end

local RejectH = {}
function RejectH.ShowTooltip(text)
    if not RejectH._anchor then
        RejectH._anchor = CreateFrame("Frame", nil, UIParent)
        RejectH._anchor:SetSize(1, 1)
        RejectH._timer = CreateFrame("Frame")
    end
    local sc = UIParent:GetEffectiveScale()
    local mx, my = GetCursorPosition()
    RejectH._anchor:ClearAllPoints()
    RejectH._anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", mx / sc, my / sc)
    EllesmereUI.ShowWidgetTooltip(RejectH._anchor, text, {})
    local elapsed = 0
    RejectH._timer:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= 3 then
            EllesmereUI.HideWidgetTooltip()
            self:SetScript("OnUpdate", nil)
            return
        end
        local s = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        RejectH._anchor:ClearAllPoints()
        RejectH._anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / s, cy / s)
    end)
end
function RejectH.IsActionBar(barKey)
    if barKey == "MainBar" then return true end
    if barKey:sub(1, 3) == "Bar" then
        local n = tonumber(barKey:sub(4))
        return n and n >= 2 and n <= 8
    end
    return false
end

-- Apply an anchor relationship: position the child element relative to the target
-- side: "LEFT", "RIGHT", "TOP", "BOTTOM" -- child is placed on that side of the target
-- offsetX/offsetY: if present, position child relative to the anchor edge
ApplyAnchorPosition = function(childKey, targetKey, side, noMark, noMove, fromCascade)
    local childBar = GetBarFrame(childKey)
    local targetBar = GetBarFrame(targetKey)
    if not childBar or not targetBar then return end
    -- Skip protected child frames during combat (action bars). Reading
    -- target bounds is safe even if the target is protected (e.g. oUF
    -- unit frames) -- we only call SetPoint on the child, not the target.
    if InCombatLockdown() and childBar:IsProtected() then return end
    -- Addon owns this element's position (e.g. a grouped Tracking Bar member
    -- chained to its group anchor) -- never generically reposition it, so its
    -- relative SetPoint to the anchor is never clobbered (in or out of combat).
    local cElem = registeredElements[childKey]
    if cElem and cElem.isAnchored and cElem.isAnchored(childKey) then return end


    -- If the target frame has no valid screen bounds (hidden / not yet laid out),
    -- bail to avoid computing garbage coordinates that cause oscillation.
    if not targetBar:GetLeft() then return end
    -- Same for the child when we need to read its actual position
    if noMove and not childBar:GetLeft() then return end

    local uiS = UIParent:GetEffectiveScale()
    local tS = targetBar:GetEffectiveScale()
    local cS = childBar:GetEffectiveScale()

    -- Get target center in UIParent space
    local tL = (targetBar:GetLeft() or 0) * tS / uiS
    local tR = (targetBar:GetRight() or 0) * tS / uiS
    local tT = (targetBar:GetTop() or 0) * tS / uiS
    local tB = (targetBar:GetBottom() or 0) * tS / uiS
    local tCX = (tL + tR) / 2
    local tCY = (tT + tB) / 2

    -- Get child size in UIParent space
    local cW = (childBar:GetWidth() or 50) * cS / uiS
    local cH = (childBar:GetHeight() or 50) * cS / uiS

    -- Compute child center
    local cx, cy
    local ai = GetAnchorInfo(childKey)
    if ai and ai.offsetX ~= nil and ai.offsetY ~= nil then
        -- Edge-to-edge offset mode: offset is stored from the child's
        -- near edge to the target's anchor edge. This means when the
        -- child resizes, the near edge stays fixed relative to the target.
        local edgeX, edgeY
        if side == "LEFT" then
            edgeX = tL; edgeY = tCY
            cx = edgeX + ai.offsetX - cW / 2
            cy = edgeY + ai.offsetY
        elseif side == "RIGHT" then
            edgeX = tR; edgeY = tCY
            cx = edgeX + ai.offsetX + cW / 2
            cy = edgeY + ai.offsetY
        elseif side == "TOP" then
            edgeX = tCX; edgeY = tT
            cx = edgeX + ai.offsetX
            cy = edgeY + ai.offsetY + cH / 2
        elseif side == "BOTTOM" then
            edgeX = tCX; edgeY = tB
            cx = edgeX + ai.offsetX
            cy = edgeY + ai.offsetY - cH / 2
        else
            edgeX = tCX; edgeY = tCY
            cx = edgeX + ai.offsetX
            cy = edgeY + ai.offsetY
        end
    else
        -- Side-snap mode (initial placement or legacy)
        if side == "LEFT" then
            cx = tL - cW / 2
            cy = tCY
        elseif side == "RIGHT" then
            cx = tR + cW / 2
            cy = tCY
        elseif side == "TOP" then
            cx = tCX
            cy = tT + cH / 2
        elseif side == "BOTTOM" then
            cx = tCX
            cy = tB - cH / 2
        else
            cx = tCX
            cy = tCY
        end
        -- Store the computed offset as edge-to-edge, snapped to pixel grid.
        -- Skip if valid offsets already exist -- recomputing from live frame
        -- bounds introduces floating point drift that accumulates on each login.
        if ai and (ai.offsetX == nil or ai.offsetY == nil) then
            local snap = (EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.Snap) or function(v) return math.floor(v + 0.5) end
            local edgeX, edgeY
            if side == "LEFT" then
                edgeX = tL; edgeY = tCY
                ai.offsetX = snap((cx + cW / 2) - edgeX)
                ai.offsetY = snap(cy - edgeY)
            elseif side == "RIGHT" then
                edgeX = tR; edgeY = tCY
                ai.offsetX = snap((cx - cW / 2) - edgeX)
                ai.offsetY = snap(cy - edgeY)
            elseif side == "TOP" then
                edgeX = tCX; edgeY = tT
                ai.offsetX = snap(cx - edgeX)
                ai.offsetY = snap((cy - cH / 2) - edgeY)
            elseif side == "BOTTOM" then
                edgeX = tCX; edgeY = tB
                ai.offsetX = snap(cx - edgeX)
                ai.offsetY = snap((cy + cH / 2) - edgeY)
            else
                edgeX = tCX; edgeY = tCY
                ai.offsetX = snap(cx - edgeX)
                ai.offsetY = snap(cy - edgeY)
            end
        end
    end

    -- For CDM/AB bars with a non-CENTER growth direction, use edge-based
    -- SetPoint so SetSize grows naturally from the fixed edge.
    -- Edge preservation (overriding cx/cy with saved/live edge) only applies
    -- to UNANCHORED bars whose own size changed. Anchored bars always use
    -- the target-computed cx/cy -- the target's bounds + offsets are
    -- authoritative and saved-edge data may be stale.
    local cdmEdgeAnchor
    local isCdmOrAB = childKey:sub(1, 4) == "CDM_"
        or (EllesmereUI._abBarKeys and EllesmereUI._abBarKeys[childKey])
    local isCDM = childKey:sub(1, 4) == "CDM_"
    -- The edge-anchor / edge-preservation path is normally suppressed in unlock
    -- mode so movers capture the user's live (center-based) drag positions. The
    -- _reapplyForceEdgePreserve flag is a narrow exception: the shift-unapply
    -- reapply on unlock entry (see OpenUnlockMode) repositions anchored bars to
    -- their TRUE saved positions, and a custom-growth bar's true position is its
    -- fixed growth edge -- without this, those bars paint centered for the whole
    -- unlock session. The flag is set only around that one reapply, so manual
    -- drag/drop positioning is unaffected.
    if isCdmOrAB and (not isUnlocked or EllesmereUI._reapplyForceEdgePreserve)
       and (isCDM or childKey == "StanceBar" or not EllesmereUI._applyingSavedPositions) then
        local growDir = GetBarGrowDirActual(childKey)
        if growDir and growDir ~= "CENTER" then
            -- Always set cdmEdgeAnchor so SetPoint uses the fixed edge
            if growDir == "RIGHT" then cdmEdgeAnchor = "LEFT"
            elseif growDir == "LEFT" then cdmEdgeAnchor = "RIGHT"
            elseif growDir == "DOWN" then cdmEdgeAnchor = "TOP"
            elseif growDir == "UP" then cdmEdgeAnchor = "BOTTOM" end
            -- Edge preservation: override cx/cy with the saved/live edge so the
            -- fixed growth edge stays put when the bar's OWN width changes (e.g.
            -- a class with a different number of stance buttons / cooldowns).
            --
            -- It is skipped ONLY on a runtime cascade -- i.e. when this call was
            -- triggered by the TARGET moving/resizing (PropagateAnchorChain passes
            -- fromCascade=true). There the bar must follow its target via the
            -- center offset; the absolute saved edge is stale once the target
            -- relocates. This is the case v7.9.4 fixed and we preserve it.
            --
            -- On init, the bar's own resize, and the Save & Exit reapply (all
            -- fromCascade=nil) the whole chain is at its saved positions, so the
            -- width-independent saved edge is authoritative. Honoring it keeps the
            -- growth edge fixed when the bar's width differs across characters
            -- (different icon/stance counts) and stops the dw/2 layout nudge from
            -- shifting the bar on save/reload.
            --
            -- The StanceBar anchors to the player frame (fixed position), so its
            -- saved edge is never stale even on cascade -- always honor it.
            local anchorDB2 = GetAnchorDB()
            local hasAnchorTarget = anchorDB2 and anchorDB2[childKey] and anchorDB2[childKey].target
            -- Force the clean target-relative offset (skip live-edge preservation)
            -- not only on a runtime cascade, but also whenever a temporary anchor-
            -- target shift is active for this child. Otherwise the own-re-apply
            -- (fromCascade=nil at the :1148 anchored-children pass) reads the
            -- already-shifted live bounds and the injection below adds the shift a
            -- second time -> continuous drift.
            -- True whenever a temporary anchor-target shift is active for this
            -- child's target (ERB "Shift Elements if No Resource"/"No Power").
            -- The provider returns 0 for any non-shift target, so this stays a
            -- no-op outside those features.
            local shiftActive = not isUnlocked
                and EllesmereUI._GetAnchorTargetShiftDir
                and EllesmereUI._GetAnchorTargetShiftDir(targetKey, childKey) ~= 0
            -- Anchored CDM growth bars are positioned from their absolute saved
            -- growth edge (savedEdge.x/.y, the override block below). On login this
            -- is a PURE absolute pin -- rock-solid by construction, reading nothing
            -- live -- because the follow delta (Phase 2, dTX/dTY below) is held at 0
            -- until _anchorFollowReady flips, which only happens at the post-settle
            -- debounce (ScheduleSettleReapply) once the chain has stopped resizing.
            -- After that flip the absolute edge is shifted by how far the anchor
            -- target has moved since save (the delta), so the bar FOLLOWS a target
            -- that relocates at runtime (e.g. a spec change sliding the player
            -- frame). Same-spec login computes a ~0 delta at the flip, so the
            -- pin->follow handoff is invisible. ERB-shift bars use the follow center
            -- (+ the shift injection below); StanceBar and unanchored bars keep
            -- their own absolute-edge path; AB growth bars keep their cascade-follow
            -- via the `not isCDM` clause; all of those compute delta 0.
            local skipEdgePreserve = (hasAnchorTarget and childKey ~= "StanceBar")
                and (shiftActive or (fromCascade and not isCDM))
            if not skipEdgePreserve then
                local cScale = childBar:GetEffectiveScale()
                local ratio = cScale / uiS
                local savedEdge
                if isCDM and EllesmereUI._cdmBarPositions then
                    local sp = EllesmereUI._cdmBarPositions[childKey:sub(5)]
                    if sp then savedEdge = sp end
                elseif childKey == "StanceBar" and EllesmereUI._abBarPositions then
                    local sp = EllesmereUI._abBarPositions[childKey]
                    if sp then savedEdge = sp end
                end
                -- Phase 2 follow: shift the absolute saved growth edge by how far
                -- the anchor target has moved/resized SINCE this bar was saved.
                -- When the anchor side aligns with this bar's own growth direction
                -- (e.g. anchored to the target's RIGHT side while itself growing
                -- RIGHT), the saved growth edge IS the near edge facing the target,
                -- so the saved target edge can be recovered as
                -- (savedNearEdge - ai.offsetX/Y) and diffed against the target's
                -- CURRENT edge. This tracks the target both moving AND resizing --
                -- e.g. a different character's main CDM bar having a different
                -- icon count/width, which a center-delta can't detect (the center
                -- doesn't move when a CENTER-anchored bar only changes width).
                -- Misaligned anchors (or no ai.offsetX/Y yet) fall back to the
                -- original center-delta, which is correct for non-resizing targets
                -- (unit frames, ERB bars). Gated on _anchorFollowReady (false until
                -- the post-settle flip, so the whole login is a pure absolute pin)
                -- and on a saved baseline existing (only bars re-saved since this
                -- shipped). CDM growth bars only; StanceBar, ERB-shift bars, and
                -- unlock mode keep the pure absolute pin (delta 0).
                local uw, uh = UIParent:GetSize()
                local dTX, dTY = 0, 0
                if isCDM and childKey ~= "StanceBar" and not shiftActive
                   and not isUnlocked and EllesmereUI._anchorFollowReady and savedEdge then
                    -- Corner-follow is scoped to CDM bars anchored to ANOTHER CDM
                    -- bar (the only target that resizes by icon count). Any other
                    -- target keeps the original center-delta path untouched.
                    local targetIsCDM = targetKey and targetKey:sub(1, 4) == "CDM_"
                    if ai and ai.offsetX ~= nil and savedEdge.x then
                        local childEdgeX = (uw / 2 + savedEdge.x) * ratio
                        if side == "RIGHT" and growDir == "RIGHT" then
                            dTX = tR - (childEdgeX - ai.offsetX)
                        elseif side == "LEFT" and growDir == "LEFT" then
                            dTX = tL - (childEdgeX - ai.offsetX)
                        elseif targetIsCDM and (side == "TOP" or side == "BOTTOM")
                               and (growDir == "RIGHT" or growDir == "LEFT")
                               and savedEdge.tgtL and savedEdge.tgtR and savedEdge.tgtx then
                            -- Corner case: anchored to the target's TOP/BOTTOM edge
                            -- while growing horizontally. Hold the bar against the
                            -- target's NEAR horizontal edge (chosen by which side of
                            -- the target center the bar sits) so it keeps its corner
                            -- when the target's WIDTH changes -- a center delta is 0
                            -- for a center-anchored resize. Idempotent: reads only
                            -- saved data + the target's live edge, never the child's
                            -- own position, so it cannot drift.
                            if childEdgeX < savedEdge.tgtx then
                                dTX = tL - savedEdge.tgtL
                            else
                                dTX = tR - savedEdge.tgtR
                            end
                        elseif savedEdge.tgtx then
                            dTX = tCX - savedEdge.tgtx
                        end
                    elseif savedEdge.tgtx then
                        dTX = tCX - savedEdge.tgtx
                    end
                    if ai and ai.offsetY ~= nil and savedEdge.y then
                        local childEdgeY = (uh / 2 + savedEdge.y) * ratio
                        if side == "TOP" and growDir == "UP" then
                            dTY = tT - (childEdgeY - ai.offsetY)
                        elseif side == "BOTTOM" and growDir == "DOWN" then
                            dTY = tB - (childEdgeY - ai.offsetY)
                        elseif targetIsCDM and (side == "LEFT" or side == "RIGHT")
                               and (growDir == "UP" or growDir == "DOWN")
                               and savedEdge.tgtT and savedEdge.tgtB and savedEdge.tgty then
                            -- Corner case: anchored to the target's LEFT/RIGHT edge
                            -- while growing vertically. Hold the bar against the
                            -- target's NEAR vertical edge so it keeps its corner when
                            -- the target's HEIGHT changes. Same idempotent guarantee.
                            if childEdgeY < savedEdge.tgty then
                                dTY = tB - savedEdge.tgtB
                            else
                                dTY = tT - savedEdge.tgtT
                            end
                        elseif savedEdge.tgty then
                            dTY = tCY - savedEdge.tgty
                        end
                    elseif savedEdge.tgty then
                        dTY = tCY - savedEdge.tgty
                    end
                end
                if growDir == "RIGHT" then
                    if savedEdge and savedEdge.point == "LEFT" and savedEdge.x then
                        cx = (uw / 2 + savedEdge.x) * ratio + cW / 2 + dTX
                    else
                        local fL = childBar:GetLeft()
                        if fL then cx = fL * ratio + cW / 2 end
                    end
                elseif growDir == "LEFT" then
                    if savedEdge and savedEdge.point == "RIGHT" and savedEdge.x then
                        cx = (uw / 2 + savedEdge.x) * ratio - cW / 2 + dTX
                    else
                        local fR = childBar:GetRight()
                        if fR then cx = fR * ratio - cW / 2 end
                    end
                elseif growDir == "DOWN" then
                    if savedEdge and savedEdge.point == "TOP" and savedEdge.y then
                        cy = (uh / 2 + savedEdge.y) * ratio - cH / 2 + dTY
                    else
                        local fT = childBar:GetTop()
                        if fT then cy = fT * ratio - cH / 2 end
                    end
                elseif growDir == "UP" then
                    if savedEdge and savedEdge.point == "BOTTOM" and savedEdge.y then
                        cy = (uh / 2 + savedEdge.y) * ratio + cH / 2 + dTY
                    else
                        local fB = childBar:GetBottom()
                        if fB then cy = fB * ratio + cH / 2 end
                    end
                end
            end
        end
    end

    -- Temporary per-target visual shift (e.g. ResourceBars "Shift Elements if
    -- No Resource"). Applied to the final computed center only -- never written
    -- to the saved ai.offsetX/offsetY (those are resolved above). Magnitude is
    -- the target's live UIParent-space height (tT - tB) so it stays scale-
    -- correct. The provider returns 0 while unlock mode is active, so this is a
    -- no-op when unlocked (and stays nil/0 until a feature opts in).
    if not isUnlocked and EllesmereUI._GetAnchorTargetShiftDir then
        -- extraY (optional 2nd return) tunes the shift magnitude by N pixels in
        -- the shift direction. nil/0 keeps the bar-height-only behavior.
        local dir, extraY = EllesmereUI._GetAnchorTargetShiftDir(targetKey, childKey)
        if dir ~= 0 then cy = cy + dir * ((tT - tB) + (extraY or 0)) end
    end

    -- Convert child center to CENTER-relative offset for centralized positioning
    local uiW, uiH = UIParent:GetSize()
    local centerX = cx - uiW / 2
    local centerY = cy - uiH / 2

    -- Only move the actual bar frame when noMove is not set
    if not noMove then
        local acRatio = uiS / cS

        if cdmEdgeAnchor then
            -- Non-CENTER-grow bar: position at the growth edge directly so
            -- SetSize grows naturally without any post-resize re-anchoring.
            local bEdgeX, bEdgeY
            if cdmEdgeAnchor == "LEFT" then
                bEdgeX = (centerX - (cW / 2)) * acRatio
                bEdgeY = centerY * acRatio
            elseif cdmEdgeAnchor == "RIGHT" then
                bEdgeX = (centerX + (cW / 2)) * acRatio
                bEdgeY = centerY * acRatio
            elseif cdmEdgeAnchor == "TOP" then
                bEdgeX = centerX * acRatio
                bEdgeY = (centerY + (cH / 2)) * acRatio
            elseif cdmEdgeAnchor == "BOTTOM" then
                bEdgeX = centerX * acRatio
                bEdgeY = (centerY - (cH / 2)) * acRatio
            end
            -- Snap edge to physical pixel grid
            local PPa = EllesmereUI and EllesmereUI.PP
            if PPa and PPa.SnapForES then
                bEdgeX = PPa.SnapForES(bEdgeX, cS)
                bEdgeY = PPa.SnapForES(bEdgeY, cS)
            end
            local skip = false
            local okPt, point, relTo, relPoint, curX, curY = pcall(childBar.GetPoint, childBar, 1)
            if okPt and point == cdmEdgeAnchor and relPoint == "CENTER" and relTo == UIParent then
                local onePx = ((PP and PP.perfect) or 1) / cS
                local tol = onePx * 1.5
                if curX and curY
                   and math.abs(curX - bEdgeX) <= tol
                   and math.abs(curY - bEdgeY) <= tol then
                    skip = true
                end
            end
            if not skip then
                pcall(function()
                    childBar:ClearAllPoints()
                    childBar:SetPoint(cdmEdgeAnchor, UIParent, "CENTER", bEdgeX, bEdgeY)
                end)
                _pendingAnchorKeys[childKey] = "all"
                ScheduleAnchorBatch()
            end
        else
            -- Standard CENTER positioning for all other elements
            local bCenterX = centerX * acRatio
            local bCenterY = centerY * acRatio
            -- Idempotent guard: if the bar is already at this exact position
            -- (within sub-physical-pixel tolerance), skip the SetPoint. This
            -- eliminates visible flicker when multiple cascade passes compute
            -- the same answer (the common case in steady state).
            local skip = false
            local okPt, point, relTo, relPoint, curX, curY = pcall(childBar.GetPoint, childBar, 1)
            if okPt and point == "CENTER" and relPoint == "CENTER" and relTo == UIParent then
                local onePx = ((PP and PP.perfect) or 1) / cS
                local tol = onePx * 0.5
                if curX and curY
                   and math.abs(curX - bCenterX) < tol
                   and math.abs(curY - bCenterY) < tol then
                    skip = true
                end
            end
            if not skip then
                -- Snap center to physical pixel grid (dim-aware for odd-pixel frames).
                -- Use child's own coordinate-space dimensions, not UIParent-space cW/cH.
                local PPa = EllesmereUI and EllesmereUI.PP
                if PPa and PPa.SnapCenterForDim then
                    local childW = childBar:GetWidth() or 0
                    local childH = childBar:GetHeight() or 0
                    bCenterX = PPa.SnapCenterForDim(bCenterX, childW, cS)
                    bCenterY = PPa.SnapCenterForDim(bCenterY, childH, cS)
                end
                pcall(function()
                    childBar:ClearAllPoints()
                    childBar:SetPoint("CENTER", UIParent, "CENTER", bCenterX, bCenterY)
                end)
                _pendingAnchorKeys[childKey] = "all"
                ScheduleAnchorBatch()
            end
        end
    else
        -- noMove: bar stays put, but resync ai.offsetX/offsetY from the bar's
        -- actual current screen position so future propagation uses correct offsets
        local bS = childBar:GetEffectiveScale()
        local bL = (childBar:GetLeft() or 0) * bS / uiS
        local bR = (childBar:GetRight() or 0) * bS / uiS
        local bT = (childBar:GetTop() or 0) * bS / uiS
        local bB = (childBar:GetBottom() or 0) * bS / uiS
        local actualCX = (bL + bR) / 2
        local actualCY = (bT + bB) / 2
        -- Skip offset recomputation if valid offsets already exist --
        -- recomputing from live bounds introduces floating point drift.
        if ai and (ai.offsetX == nil or ai.offsetY == nil) then
            local actualHW = (bR - bL) / 2
            local actualHH = (bT - bB) / 2
            local snap = (EllesmereUI and EllesmereUI.PP and EllesmereUI.PP.Snap) or function(v) return math.floor(v + 0.5) end
            if side == "LEFT" then
                ai.offsetX = snap((actualCX + actualHW) - tL)
                ai.offsetY = snap(actualCY - tCY)
            elseif side == "RIGHT" then
                ai.offsetX = snap((actualCX - actualHW) - tR)
                ai.offsetY = snap(actualCY - tCY)
            elseif side == "TOP" then
                ai.offsetX = snap(actualCX - tCX)
                ai.offsetY = snap((actualCY - actualHH) - tT)
            elseif side == "BOTTOM" then
                ai.offsetX = snap(actualCX - tCX)
                ai.offsetY = snap((actualCY + actualHH) - tB)
            else
                ai.offsetX = snap(actualCX - tCX)
                ai.offsetY = snap(actualCY - tCY)
            end
        end
    end

    -- Update mover position to match (CENTER anchor so hover-expand stays symmetric)
    local m = movers[childKey]
    if m then
        local mX, mY
        if noMove then
            -- Bar is already in its correct position -- read its actual screen coords
            local bS = childBar:GetEffectiveScale()
            local bL = (childBar:GetLeft() or 0) * bS / uiS
            local bR = (childBar:GetRight() or 0) * bS / uiS
            local bT = (childBar:GetTop() or 0) * bS / uiS
            local bB = (childBar:GetBottom() or 0) * bS / uiS
            mX = (bL + bR) / 2
            mY = ((bT + bB) / 2) - UIParent:GetHeight()
        else
            mX = cx
            mY = cy - UIParent:GetHeight()
        end
        local PPp = EllesmereUI and EllesmereUI.PP
        if PPp then mX = PPp.Scale(mX); mY = PPp.Scale(mY) end
        m:ClearAllPoints()
        m:SetPoint("CENTER", UIParent, "TOPLEFT", mX, mY)
        if m._setCenterXY then m._setCenterXY(mX, mY) end
        -- Re-anchor mover to bar for pixel-perfect alignment
        if m.ReanchorToBar then m:ReanchorToBar() end
    end

    -- Store in pending positions only during unlock mode (skip at login
    -- so anchor-computed positions don't pollute saved positions)
    if not noMove and EllesmereUI._unlockActive then
        -- CDM/AB bars with growth direction store edge-format positions.
        -- Writing CENTER coords here would overwrite the correct edge
        -- data on Save & Exit. Mark as anchored so CommitPositions uses
        -- snapshot/loadPos (which returns the correct edge format).
        local growSkip = false
        if isCdmOrAB then
            local gd = GetBarGrowDirActual(childKey)
            if gd and gd ~= "CENTER" then growSkip = true end
        end
        if growSkip then
            pendingPositions[childKey] = { _anchored = true }
        else
            pendingPositions[childKey] = {
                point = "CENTER", relPoint = "CENTER",
                x = bCenterX, y = bCenterY,
            }
        end
    end
    if not noMark then hasChanges = true end
end

-- Re-apply all saved anchor positions (called on open and after target moves)
local function ReapplyAllAnchors()
    local db = GetAnchorDB()
    if not db then return end
    for childKey, info in pairs(db) do
        if movers[childKey] and movers[info.target] then
            ApplyAnchorPosition(childKey, info.target, info.side, true, true)
        end
    end
end

-- Recursively propagate anchor repositioning from a moved parent down the chain.
-- visited guards against circular anchor loops.
-- changedAxis: "width", "height", or nil (nil = propagate all axes, e.g. from drag)
PropagateAnchorChain = function(parentKey, visited, changedAxis)
    visited = visited or {}
    if visited[parentKey] then return end
    visited[parentKey] = true
    local anchorDB = GetAnchorDB()
    if not anchorDB then return end
    for childKey, info in pairs(anchorDB) do
        if info.target == parentKey then
            -- Axis isolation: skip children on the unaffected axis
            local dominated = false
            if changedAxis == "width" then
                dominated = (info.side == "TOP" or info.side == "BOTTOM")
            elseif changedAxis == "height" then
                dominated = (info.side == "LEFT" or info.side == "RIGHT")
            end
            if not dominated then
                ApplyAnchorPosition(childKey, info.target, info.side, nil, nil, true)
                -- Do NOT call Sync() here -- ApplyAnchorPosition already positions
                -- the mover correctly, and Sync() reads stale screen coords before
                -- WoW's layout pass, which corrupts moverCX/moverCY.
                PropagateAnchorChain(childKey, visited, changedAxis)
            end
        end
    end
end

-- Expose so child addons (CDM) can trigger anchor updates after resize.
-- changedAxis: "width", "height", or nil (nil = propagate all axes)
EllesmereUI.PropagateAnchorChain = function(key, changedAxis)
    local newAxis = changedAxis or "all"
    local existing = _pendingAnchorKeys[key]
    -- Merge axes: if different axes are pending, escalate to "all"
    if existing and existing ~= newAxis then
        _pendingAnchorKeys[key] = "all"
    else
        _pendingAnchorKeys[key] = newAxis
    end
    ScheduleAnchorBatch()
end

-- Check if a given element key has an anchor relationship.
-- Used by ReloadFrames to skip positioning anchored frames (the anchor
-- system is the sole authority for their position).
EllesmereUI.IsAnchored = function(key)
    local adb = GetAnchorDB()
    if not adb then return false end
    local info = adb[key]
    return info and info.target and true or false
end

-- Synchronous self-anchor reapply: if this element is anchored to something,
-- reposition it immediately (no deferred frame). Eliminates the one-frame
-- blink when a bar resizes and needs to snap back to its anchor edge.
EllesmereUI.ReapplyOwnAnchor = function(key)
    -- Skip if this element's mover is currently being dragged -- the drag
    -- OnUpdate owns positioning and reapplying would snap the bar back.
    local m = movers[key]
    if m and m._dragging then return end
    local anchorDB = GetAnchorDB()
    if not anchorDB then return end
    local info = anchorDB[key]
    if info and info.target then
        ApplyAnchorPosition(key, info.target, info.side)
    end
end

-- Reapply ALL unlock-mode anchors. Called when a target frame moves so
-- anchored children follow. Computes positions from anchor offsets.
EllesmereUI.ReapplyAllUnlockAnchors = function()
    local adb = GetAnchorDB()
    if not adb then return end

    -- Apply in dependency order (roots first, then their children, then
    -- grandchildren). pairs() is non-deterministic and a chain like
    -- A -> B -> C could otherwise process C before B, leaving C reading
    -- B's stale edges. Same fix pattern as ApplyMatchesInDependencyOrder.
    local depth = {}
    local function GetDepth(k, visiting)
        if depth[k] ~= nil then return depth[k] end
        if visiting[k] then depth[k] = 0; return 0 end  -- cycle guard
        visiting[k] = true
        local info = adb[k]
        if info and info.target and adb[info.target] then
            depth[k] = 1 + GetDepth(info.target, visiting)
        else
            depth[k] = 0  -- target is a root (not in adb) or missing
        end
        visiting[k] = nil
        return depth[k]
    end

    local order = {}
    for childKey in pairs(adb) do
        GetDepth(childKey, {})
        order[#order + 1] = childKey
    end
    table.sort(order, function(a, b) return depth[a] < depth[b] end)

    for _, childKey in ipairs(order) do
        local info = adb[childKey]
        if info and info.target
           and GetBarFrame(childKey) and GetBarFrame(info.target) then
            ApplyAnchorPosition(childKey, info.target, info.side)
        end
    end

    -- No position persistence here. Positions are only saved by
    -- unlock mode's Save & Exit (CommitPositions).
    wipe(pendingPositions)
end

-- Forced version of ReapplyAllUnlockAnchors: clears each child's points
-- before re-applying so the idempotent guard inside ApplyAnchorPosition
-- can't perma-skip a stale cached answer.
--
-- WHY THIS EXISTS: occasionally an anchored child (e.g. a CDM bar anchored
-- to Class Resource) settles at a 1px-off position because some upstream
-- emission read transient bounds. Once the cascade converges to that
-- wrong-by-1px answer, the idempotent guard sees "current matches stored"
-- and never corrects. Manual un-anchor + re-anchor in the UI fixes it
-- because clearing the anchor info forces a fresh evaluation against
-- current (settled) target bounds. This function does the same thing
-- programmatically without disturbing the anchor DB.
--
-- Wired into the CDM authoritative-pass trigger (ns._spellsReadyForApply
-- in EllesmereUICdmHooks.lua) so it fires once at the same known-good
-- moment we already use to retrigger width matches. Same dependency-sorted
-- order. Skips combat-protected children automatically.
EllesmereUI.ReapplyAllUnlockAnchorsForced = function()
    local adb = GetAnchorDB()
    if not adb then return end

    local depth = {}
    local function GetDepth(k, visiting)
        if depth[k] ~= nil then return depth[k] end
        if visiting[k] then depth[k] = 0; return 0 end
        visiting[k] = true
        local info = adb[k]
        if info and info.target and adb[info.target] then
            depth[k] = 1 + GetDepth(info.target, visiting)
        else
            depth[k] = 0
        end
        visiting[k] = nil
        return depth[k]
    end

    local order = {}
    for childKey in pairs(adb) do
        GetDepth(childKey, {})
        order[#order + 1] = childKey
    end
    table.sort(order, function(a, b) return depth[a] < depth[b] end)

    local inCombat = InCombatLockdown()
    for _, childKey in ipairs(order) do
        local info = adb[childKey]
        if info and info.target then
            local childBar = GetBarFrame(childKey)
            local targetBar = GetBarFrame(info.target)
            local rcElem = registeredElements[childKey]
            if childBar and targetBar
               and not (inCombat and childBar:IsProtected())
               and not (rcElem and rcElem.isAnchored and rcElem.isAnchored(childKey)) then
                -- AB bars with growth direction: skip entirely. Their position
                -- is set authoritatively by applyPos from barPositions (edge
                -- format, width-independent, updated on every LayoutBar).
                local isABGrow = false
                if EllesmereUI._abBarKeys and EllesmereUI._abBarKeys[childKey]
                   and childKey ~= "StanceBar" then
                    local gd = GetBarGrowDirActual(childKey)
                    isABGrow = gd and gd ~= "CENTER"
                end
                if not isABGrow then
                    pcall(childBar.ClearAllPoints, childBar)
                    ApplyAnchorPosition(childKey, info.target, info.side, true)
                end
            end
        end
    end

    -- No position persistence here. Positions are only saved by
    -- unlock mode's Save & Exit (CommitPositions).
    wipe(pendingPositions)
end

-- UIParent-space center (x, y) of childKey's current anchor target, computed
-- identically to ApplyAnchorPosition's tCX/tCY so a value captured here is
-- directly comparable to the runtime target center. CDM savePos stores this as
-- the follow baseline (sp.tgtx/.tgty). Returns nil if there is no anchor target
-- or it has no screen bounds yet.
function EllesmereUI.GetAnchorTargetCenterUI(childKey)
    local adb = GetAnchorDB()
    local info = adb and adb[childKey]
    if not info or not info.target then return nil end
    local targetBar = GetBarFrame(info.target)
    if not targetBar or not targetBar:GetLeft() then return nil end
    local uiS = UIParent:GetEffectiveScale()
    local tS = targetBar:GetEffectiveScale()
    local tL = (targetBar:GetLeft() or 0) * tS / uiS
    local tR = (targetBar:GetRight() or 0) * tS / uiS
    local tT = (targetBar:GetTop() or 0) * tS / uiS
    local tB = (targetBar:GetBottom() or 0) * tS / uiS
    return (tL + tR) / 2, (tT + tB) / 2
end

-- UIParent-space edges (left, right, top, bottom) of childKey's anchor target,
-- computed identically to ApplyAnchorPosition's tL/tR/tT/tB. Returned ONLY when
-- the target is ANOTHER CDM bar -- this baseline exists purely for the corner-
-- follow of CDM-anchored-to-CDM bars; nothing else reads it. CDM savePos stores
-- these as sp.tgtL/.tgtR/.tgtT/.tgtB. Returns nil if there is no CDM anchor
-- target or it has no screen bounds yet.
function EllesmereUI.GetAnchorTargetEdgesUI(childKey)
    local adb = GetAnchorDB()
    local info = adb and adb[childKey]
    if not info or not info.target then return nil end
    if info.target:sub(1, 4) ~= "CDM_" then return nil end
    local targetBar = GetBarFrame(info.target)
    if not targetBar or not targetBar:GetLeft() then return nil end
    local uiS = UIParent:GetEffectiveScale()
    local tS = targetBar:GetEffectiveScale()
    local tL = (targetBar:GetLeft() or 0) * tS / uiS
    local tR = (targetBar:GetRight() or 0) * tS / uiS
    local tT = (targetBar:GetTop() or 0) * tS / uiS
    local tB = (targetBar:GetBottom() or 0) * tS / uiS
    return tL, tR, tT, tB
end

-- Resync anchor offsets from actual frame positions. Called AFTER a profile
-- import/switch once all frames are at their correct absolute positions
-- (from db.profile.positions). This does NOT move any frames -- it reads
-- their current screen positions and recomputes the anchor offsets so the
-- anchor relationships stay correct for future drag operations.
-- Resync anchor offsets from actual frame positions. Called after profile
-- import/switch. Skips rewriting offsets that already have valid values
-- from unlock mode, since reading live bounds introduces floating-point
-- noise from the SetPoint->GetLeft round-trip, causing 1px drift.
EllesmereUI.ResyncAnchorOffsets = function()
    local adb = GetAnchorDB()
    if not adb then return end
    for childKey, info in pairs(adb) do
        if info.target and GetBarFrame(childKey) and GetBarFrame(info.target) then
            -- Only resync offsets if they're missing (legacy data or first setup).
            -- Existing offsets from unlock mode are authoritative.
            if info.offsetX == nil or info.offsetY == nil then
                ApplyAnchorPosition(childKey, info.target, info.side, true, true)
            end
        end
    end
    wipe(pendingPositions)
end

-------------------------------------------------------------------------------
--  Saved position helpers
-------------------------------------------------------------------------------
GetPositionDB = function()
    if not EAB or not EAB.db then return nil end
    if not EAB.db.profile.barPositions then
        EAB.db.profile.barPositions = {}
    end
    return EAB.db.profile.barPositions
end

-------------------------------------------------------------------------------
--  Centralized grow-direction position system
--  All elements store positions as CENTER/CENTER (offset from UIParent center).
--  On apply, the system picks the correct SetPoint anchor based on whether
--  the element has an unlock-mode anchor relationship.
-------------------------------------------------------------------------------

-- Convert any anchor-point position to CENTER/CENTER format.
-- Reads the frame's actual screen bounds for accuracy; falls back to
-- arithmetic conversion using the supplied coords + element size.
local function ConvertToCenterPos(barKey, point, relPoint, x, y)
    local elem = registeredElements[barKey]
    local frame = GetBarFrame(barKey)
    local uiW, uiH = UIParent:GetSize()
    local halfW, halfH = uiW / 2, uiH / 2

    -- If already CENTER/CENTER, pass through
    if point == "CENTER" and relPoint == "CENTER" then
        return "CENTER", "CENTER", x or 0, y or 0
    end

    -- Try to read center from live frame (most accurate)
    if frame and frame:GetLeft() and frame:GetRight() and frame:GetTop() and frame:GetBottom() then
        local uiS = UIParent:GetEffectiveScale()
        local fS = frame:GetEffectiveScale()
        local ratio = fS / uiS
        local fL = frame:GetLeft() * ratio
        local fR = frame:GetRight() * ratio
        local fT = frame:GetTop() * ratio
        local fB = frame:GetBottom() * ratio
        local cx = (fL + fR) / 2 - halfW
        local cy = (fT + fB) / 2 - halfH
        return "CENTER", "CENTER", cx, cy
    end

    -- Arithmetic fallback: convert from the given anchor point
    -- Get element size for offset calculation
    local ew, eh = 0, 0
    if elem and elem.getSize then
        ew, eh = elem.getSize(barKey)
    elseif frame then
        ew = frame:GetWidth() or 0
        eh = frame:GetHeight() or 0
    end
    local hw, hh = (ew or 0) / 2, (eh or 0) / 2

    -- Convert stored coords to center-of-element in UIParent space
    local cx, cy
    if point == "TOPLEFT" and (relPoint == "TOPLEFT" or relPoint == point) then
        -- x,y are TOPLEFT offsets from UIParent TOPLEFT
        -- center = (x + hw, y - hh) in TOPLEFT space
        -- convert to CENTER space: subtract halfW, add halfH (Y is inverted)
        cx = x + hw - halfW
        cy = y - hh + halfH
    elseif point == "LEFT" and relPoint == "CENTER" then
        -- CDM format: x is left-edge offset from center, y is center-Y offset
        cx = x + hw
        cy = y
    elseif point == "RIGHT" and relPoint == "CENTER" then
        cx = x - hw
        cy = y
    elseif point == "TOP" and relPoint == "CENTER" then
        cx = x
        cy = y - hh
    elseif point == "BOTTOM" and relPoint == "CENTER" then
        cx = x
        cy = y + hh
    elseif relPoint == "CENTER" then
        -- Generic CENTER-relative: just use as-is for CENTER point
        cx = x
        cy = y
    else
        -- Unknown format: best-effort TOPLEFT assumption
        cx = (x or 0) + hw - halfW
        cy = (y or 0) - hh + halfH
    end

    return "CENTER", "CENTER", cx or 0, cy or 0
end

-- Apply a CENTER/CENTER position to a frame, choosing the correct SetPoint
-- anchor based on the element's unlock-mode anchor relationship.
-- Unanchored elements use CENTER (grow centered on resize).
-- Anchored elements use the edge opposite their anchor side (grow away from anchor).
ApplyCenterPosition = function(barKey, pos)
    if not pos or pos.point ~= "CENTER" or pos.relPoint ~= "CENTER" then return false end
    local frame = GetBarFrame(barKey)
    if not frame then return false end

    -- Skip elements anchored via the unlock anchor system -- their position
    -- is owned by ApplyAnchorPosition, not by the grow-direction logic here.
    local anchorDB = GetAnchorDB()
    local anchorInfo = anchorDB and anchorDB[barKey]
    if anchorInfo and anchorInfo.target then return true end

    local cx, cy = pos.x or 0, pos.y or 0

    -- Determine grow anchor from unlock-mode anchor relationship
    local anchorInfo = anchorDB and anchorDB[barKey]
    local anchor = "CENTER"
    local adjX, adjY = cx, cy

    if anchorInfo and anchorInfo.target and anchorInfo.side then
        local side = anchorInfo.side
        local fw = (frame:GetWidth() or 0)
        local fh = (frame:GetHeight() or 0)
        -- Use raw half-dimensions (fw/2, fh/2) instead of floor().
        -- For odd-pixel-height frames, the center cy is integer + 0.5
        -- (because edges are integer and (top+bottom)/2 is .5). Using
        -- raw fh/2 = integer + 0.5 means cy +/- fh/2 lands back on integer
        -- pixels. floor(fh/2) = integer would compute a half-pixel-off edge.
        if side == "LEFT" then
            anchor = "RIGHT"
            adjX = cx + fw / 2
        elseif side == "RIGHT" then
            anchor = "LEFT"
            adjX = cx - fw / 2
        elseif side == "TOP" then
            anchor = "BOTTOM"
            adjY = cy + fh / 2
        elseif side == "BOTTOM" then
            anchor = "TOP"
            adjY = cy - fh / 2
        end
    else
        -- No anchor relationship -- use grow direction to pick fixed edge.
        -- Prefer growEdge (width-independent absolute edge offset) when
        -- available. Fall back to CENTER +/- width/2 (width-dependent) only
        -- for legacy positions that predate growEdge.
        local ge = pos.growEdge
        if ge and ge.anchor and ge.x and ge.y then
            anchor = ge.anchor
            adjX = ge.x
            adjY = ge.y
        else
            local growDir = GetBarGrowDirActual(barKey)
            local fw = (frame:GetWidth() or 0)
            local fh = (frame:GetHeight() or 0)
            -- Skip grow-direction conversion if frame has no dimensions yet
            -- (not laid out). Using CENTER avoids wrong edge placement from
            -- zero-size math. The bar will be re-positioned after LayoutBar runs.
            if growDir and growDir ~= "CENTER" and fw >= 1 and fh >= 1 then
                if growDir == "RIGHT" then
                    anchor = "LEFT"
                    adjX = cx - fw / 2
                    adjY = cy
                elseif growDir == "LEFT" then
                    anchor = "RIGHT"
                    adjX = cx + fw / 2
                    adjY = cy
                elseif growDir == "DOWN" then
                    anchor = "TOP"
                    adjY = cy + fh / 2
                    adjX = cx
                elseif growDir == "UP" then
                    anchor = "BOTTOM"
                    adjY = cy - fh / 2
                    adjX = cx
                end
            end
        end
    end

    -- Snap the final position to the physical pixel grid, accounting for
    -- odd-dimension frames that need half-pixel centering.
    local PPap = EllesmereUI and EllesmereUI.PP
    if PPap and PPap.SnapCenterForDim then
        local es = frame:GetEffectiveScale()
        if anchor == "CENTER" then
            adjX = PPap.SnapCenterForDim(adjX, frame:GetWidth() or 0, es)
            adjY = PPap.SnapCenterForDim(adjY, frame:GetHeight() or 0, es)
        elseif PPap.SnapForES then
            adjX = PPap.SnapForES(adjX, es)
            adjY = PPap.SnapForES(adjY, es)
        end
    end

    pcall(function()
        if InCombatLockdown() and frame:IsProtected() then
            -- Store on the frame so repeated calls overwrite instead of stacking
            local ffd = EllesmereUI._GetFFD(frame)
            if not ffd.combatDefer then
                ffd.combatDefer = CreateFrame("Frame")
                ffd.combatDefer:RegisterEvent("PLAYER_REGEN_ENABLED")
                ffd.combatDefer:SetScript("OnEvent", function(self)
                    self:UnregisterAllEvents()
                    local args = self._args
                    if args then
                        pcall(function()
                            args.f:ClearAllPoints()
                            args.f:SetPoint(args.a, UIParent, "CENTER", args.x, args.y)
                        end)
                    end
                    self._args = nil
                end)
            end
            ffd.combatDefer._args = { f = frame, a = anchor, x = adjX, y = adjY }
            return
        end
        frame:ClearAllPoints()
        frame:SetPoint(anchor, UIParent, "CENTER", adjX, adjY)
    end)
    return true
end

-- Expose on EllesmereUI for child addons
EllesmereUI.ConvertToCenterPos = ConvertToCenterPos
EllesmereUI.ApplyCenterPosition = ApplyCenterPosition

SaveBarPosition = function(barKey, point, relPoint, x, y)
    -- Convert to CENTER/CENTER before storing.
    -- ConvertToCenterPos reads the live frame's actual edges and produces an
    -- exact center value: for odd-pixel-height frames the edges are integer
    -- pixels and the center is integer + 0.5 (e.g. 540.5). We DELIBERATELY
    -- do not snap that .5 away here -- the apply path uses raw fh/2 (also
    -- ending in .5 for odd heights) so the round-trip cy +/- fh/2 lands back
    -- on integer pixels. Snapping cy to integer here would force the apply
    -- path to compute a half-pixel edge, causing a 1px drift on save & exit.
    local cp, crp, cx, cy = ConvertToCenterPos(barKey, point, relPoint, x, y)

    -- Registered element?
    local elem = registeredElements[barKey]
    if elem and elem.savePosition then
        elem.savePosition(barKey, cp, crp, cx, cy)
        return
    end
    -- Action bar fallback
    local db = GetPositionDB()
    if not db then return end
    db[barKey] = { point = cp, relPoint = crp, x = cx, y = cy }
end
EllesmereUI.SaveBarPosition = SaveBarPosition

local function LoadBarPosition(barKey)
    -- Registered element?
    local elem = registeredElements[barKey]
    if elem and elem.loadPosition then
        return elem.loadPosition(barKey)
    end
    -- Action bar fallback
    local db = GetPositionDB()
    if not db or not db[barKey] then return nil end
    return db[barKey]
end

local function ClearBarPosition(barKey)
    -- Registered element?
    local elem = registeredElements[barKey]
    if elem and elem.clearPosition then
        elem.clearPosition(barKey)
        return
    end
    -- Action bar fallback
    local db = GetPositionDB()
    if db then db[barKey] = nil end
end

-------------------------------------------------------------------------------
--  Bar frame resolution  (works for both action bars and registered elements)
-------------------------------------------------------------------------------
GetBarFrame = function(barKey)
    -- Registered element?
    local elem = registeredElements[barKey]
    if elem and elem.getFrame then
        return elem.getFrame(barKey)
    end
    -- Action bars (BAR_LOOKUP has frameName + fallbackFrame)
    local info = BAR_LOOKUP[barKey]
    if info then
        local f = _G[info.frameName]
        if not f and info.fallbackFrame then f = _G[info.fallbackFrame] end
        return f
    end
    -- Extra bars (MicroBar, BagBar — not in BAR_LOOKUP)
    if barKey == "MicroBar"   then return _G["MicroMenuContainer"] or _G["MicroMenu"] end
    if barKey == "BagBar"     then return _G["BagsBar"] end
    return nil
end

GetBarLabel = function(barKey)
    -- Registered element?
    local elem = registeredElements[barKey]
    if elem and elem.label then
        return elem.label
    end
    local vals = ns.BAR_DROPDOWN_VALUES
    return vals and vals[barKey] or barKey
end
EllesmereUI.GetBarLabel = GetBarLabel

-------------------------------------------------------------------------------
--  Apply saved positions on login / reload
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--  Lazy migration: convert positions to CENTER/CENTER format on the fly.
--  Works per-profile -- no global flag needed. Positions are converted
--  when first applied, then saved back in CENTER format.
-------------------------------------------------------------------------------
local function MigrateAndApplyPosition(barKey, pos, frame)
    if not pos or not pos.point then return false end
    -- CENTER/CENTER: apply with grow-direction-aware positioning
    if pos.point == "CENTER" and pos.relPoint == "CENTER" then
        return ApplyCenterPosition(barKey, pos)
    end
    -- Non-CENTER format (edge position from DB): apply directly.
    -- No write-back to DB -- positions are only saved by unlock mode's
    -- Save & Exit flow (CommitPositions). The edge anchor is correct as stored.
    if frame then
        local px, py = pos.x or 0, pos.y or 0
        local PPa = EllesmereUI and EllesmereUI.PP
        if PPa and PPa.SnapForES then
            local es = frame:GetEffectiveScale()
            px = PPa.SnapForES(px, es)
            py = PPa.SnapForES(py, es)
        end
        pcall(function()
            frame:ClearAllPoints()
            frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, px, py)
        end)
    end
    return true
end

local function ApplySavedPositions()
    EllesmereUI._applyingSavedPositions = true
    local inCombat = InCombatLockdown()

    -- Action bars: apply from barPositions DB with lazy migration
    -- Skip during combat (action bar frames use SecureHandlerStateTemplate
    -- and are genuinely protected -- SetPoint is blocked by combat lockdown).
    local db = GetPositionDB()
    if db and not inCombat then
        for barKey, pos in pairs(db) do
            local bar = GetBarFrame(barKey)
            MigrateAndApplyPosition(barKey, pos, bar)
        end
    end
    -- Hook all known action bar frames for auto-propagation on resize
    for barKey in pairs(BAR_LOOKUP) do
        HookFrameSizeChanged(barKey)
    end
    -- Registered elements: let each addon apply its own positions first
    -- (some addons like CDM need applyPosition to build/initialize frames),
    -- then override with centralized grow-direction-aware positioning.
    RebuildRegisteredOrder()
    for _, key in ipairs(registeredOrder) do
        local elem = registeredElements[key]
        if elem then
            -- Chat frames manage their own position and must not be touched
            -- by the init loop: any hook or SetPoint on ChatFrame1 taints
            -- FCF_OpenTemporaryWindow's secure chain.
            if elem.noInitHook then
                -- skip applyPosition, MigrateAndApplyPosition, HookFrameSizeChanged
            elseif true then
            -- Let addon initialize/build (e.g. CDM's BuildAllCDMBars)
            -- Skip protected frames during combat to avoid ADDON_ACTION_BLOCKED
            if elem.applyPosition then
                local apFrame = elem.getFrame and elem.getFrame(key)
                if not inCombat or not apFrame or not apFrame:IsProtected() then
                    pcall(elem.applyPosition, key)
                end
            end
            -- Skip centralized override for addon-internally-anchored elements
            -- (e.g. Resource Bars anchored to each other via anchorTo setting)
            local addonAnchored = elem.isAnchored and elem.isAnchored(key)
            -- Also skip elements anchored via the unlock mode anchor system
            local unlockAnchored = false
            if not addonAnchored then
                local adb = GetAnchorDB()
                local ai = adb and adb[key]
                if ai and ai.target then unlockAnchored = true end
            end
            if not addonAnchored and not unlockAnchored then
                -- Override position with centralized grow-direction logic
                local pos = elem.loadPosition and elem.loadPosition(key)
                if pos then
                    local frame = GetBarFrame(key)
                    if not inCombat or not frame or not frame:IsProtected() then
                        MigrateAndApplyPosition(key, pos, frame)
                    end
                end
            end
        end -- elseif true
        end -- if elem
        -- Install OnSizeChanged hook so future resizes auto-propagate
        HookFrameSizeChanged(key)
    end

    -- Apply all width/height matches now that positions are set
    ApplyAllWidthHeightMatches()

    -- Reapply all anchor positions sorted by dependency depth.
    -- Parents must be positioned before children so children read correct bounds.
    local adb = GetAnchorDB()
    if adb then
        -- Build dependency-sorted list: elements with no anchored parent first
        local sorted = {}
        local visited = {}
        local function addWithDeps(childKey, info, depth)
            if visited[childKey] then return end
            if depth > 20 then return end  -- circular guard
            visited[childKey] = true
            -- If our target is also anchored, process it first
            local targetInfo = adb[info.target]
            if targetInfo and targetInfo.target and not visited[info.target] then
                addWithDeps(info.target, targetInfo, depth + 1)
            end
            sorted[#sorted + 1] = { key = childKey, info = info }
        end
        for childKey, info in pairs(adb) do
            if info.target then
                addWithDeps(childKey, info, 0)
            end
        end

        local unresolved = {}
        for _, entry in ipairs(sorted) do
            local childKey, info = entry.key, entry.info
            local childFrame = GetBarFrame(childKey)
            local targetFrame = GetBarFrame(info.target)
            -- Apply now if both frames exist and target has bounds. Otherwise
            -- queue for retry. Previously a missing child or target frame
            -- caused the anchor to be silently dropped (never retried), which
            -- left bars at their fallback CENTER/CENTER position when an
            -- addon's unlock element registration raced with this apply call.
            if childFrame and targetFrame and targetFrame:GetLeft() then
                ApplyAnchorPosition(childKey, info.target, info.side)
            else
                unresolved[childKey] = info
            end
        end
        if next(unresolved) then
            local retries = 0
            local function RetryAnchors()
                retries = retries + 1
                local still = {}
                for childKey, info in pairs(unresolved) do
                    local childFrame = GetBarFrame(childKey)
                    local target = GetBarFrame(info.target)
                    if childFrame and target and target:GetLeft() then
                        ApplyAnchorPosition(childKey, info.target, info.side)
                    else
                        still[childKey] = info
                    end
                end
                unresolved = still
                if next(unresolved) and retries < 20 then
                    C_Timer.After(0.1, RetryAnchors)
                end
            end
            C_Timer.After(0, RetryAnchors)
        end
    end

    EllesmereUI._applyingSavedPositions = false
    EllesmereUI._abAnchorSuppressed = false

    -- If we skipped protected frames, re-run once combat drops
    if inCombat then
        local reapplyFrame = CreateFrame("Frame")
        reapplyFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        reapplyFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            ApplySavedPositions()
        end)
    end
end

-- Expose for profile import/switch (called from EllesmereUI_Profiles.lua)
EllesmereUI._applySavedPositions = ApplySavedPositions

-- Expose so child addons (CDM, resource bars) can re-apply matches after
-- their bars finish populating and have correct dimensions.
EllesmereUI.ApplyAllWidthHeightMatches = ApplyAllWidthHeightMatches

-- Global check: is this unlock key anchored to another element?
-- Any addon can call this to decide whether to skip positioning in BuildBars.
function EllesmereUI.IsUnlockAnchored(unlockKey)
    local adb = GetAnchorDB()
    local ai = adb and adb[unlockKey]
    return ai and ai.target and true or false
end


-------------------------------------------------------------------------------
--  frame so that when Blizzard's Edit Mode tries to reposition a bar we
--  have a custom position for, the original method is skipped entirely.
--  This prevents the visual "jump" because the bar never moves to the
--  wrong position in the first place.
--
--  IMPORTANT: We use hooksecurefunc (post-hook) instead of replacing the
--  method outright.  Replacing ApplySystemAnchor taints the bar frame,
--  which propagates to child action buttons and causes
--  ADDON_ACTION_BLOCKED on SetShown().  A post-hook lets Blizzard's
--  secure code run first, then we re-position the bar in a deferred
--  timer so our addon code never executes inside the secure call chain.
-------------------------------------------------------------------------------
local anchorGuardedBars = {}  -- { [barFrame] = true }

local function InstallAnchorGuard(bar, barKey)
    if anchorGuardedBars[bar] then return end
    if not bar.ApplySystemAnchor then return end
    anchorGuardedBars[bar] = true
    hooksecurefunc(bar, "ApplySystemAnchor", function(self)
        local db = GetPositionDB()
        if db and db[barKey] and db[barKey].point then
            -- Defer so we don't taint the secure execution context
            C_Timer.After(0, function()
                if InCombatLockdown() then return end
                -- Use centralized apply for grow-direction-aware positioning
                if not ApplyCenterPosition(barKey, db[barKey]) then
                    pcall(function()
                        self:ClearAllPoints()
                        self:SetPoint(db[barKey].point, UIParent, db[barKey].relPoint,
                                      db[barKey].x, db[barKey].y)
                    end)
                end
            end)
        end
    end)
end

local function InstallAllAnchorGuards()
    local db = GetPositionDB()
    if not db then return end
    for barKey, _ in pairs(db) do
        local bar = GetBarFrame(barKey)
        if bar then
            InstallAnchorGuard(bar, barKey)
        end
    end
end

-- Hook into the addon's ApplyAll chain (action bars only)
if EAB then
    local _origApplyAll = EAB.ApplyAll
    if _origApplyAll then
        function EAB:ApplyAll()
            _origApplyAll(self)
            -- Install anchor guards on first ApplyAll (bars exist by now)
            InstallAllAnchorGuards()
            C_Timer.After(0.6, ApplySavedPositions)
        end
    end

    -- Called by EllesmereUIActionBars when Blizzard's Edit Mode saves or exits.
    function EAB:OnEditModeLayoutReapply()
        InstallAllAnchorGuards()
        ApplySavedPositions()
        C_Timer.After(0.3, function() self:ApplyAll() end)
    end

    -- Install anchor guards as early as possible — right after the DB is
    -- initialized — so Blizzard's very first layout pass can't move bars
    -- we have custom positions for.
    local _origOnInit = EAB.OnInitialize
    if _origOnInit then
        function EAB:OnInitialize()
            _origOnInit(self)
            InstallAllAnchorGuards()
            ApplySavedPositions()
        end
    end
end

-- Fallback: when action bars is disabled, ApplySavedPositions never runs
-- because it is only hooked into EAB.ApplyAll / OnInitialize. Register a
-- Zone transition guard: suppress width/height match propagation during
-- loading screens. CDM icon counts fluctuate as Blizzard recycles viewer
-- frames, causing transient sizes that would corrupt matched elements.
do
    local ztFrame = CreateFrame("Frame")
    ztFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    ztFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
    ztFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LEAVING_WORLD" then
            EllesmereUI._zoneTransitionActive = true
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Keep the guard up for 2 seconds after zone-in so CDM/ERB
            -- have time to finish rebuilding with final icon counts.
            C_Timer.After(2, function()
                EllesmereUI._zoneTransitionActive = false
            end)
        end
    end)
end

-- PLAYER_ENTERING_WORLD listener: applies saved positions + initial
-- anchor pass once child addons have had time to register their unlock
-- elements. Subsequent corrections are event-driven via NotifyElementResized
-- (auto-fired by OnSizeChanged on every registered frame), NOT by retries.
--
-- Architecture: the cascade machinery (NotifyElementResized -> width-match
-- propagation -> anchor children) handles every legitimate size change as
-- it happens. The single safety sweep at +5s is a true safety net: every
-- call inside it is idempotent (ApplyAnchorPosition skips SetPoint when
-- the computed position already matches the current position), so if the
-- event-driven path worked it produces zero visible effect. If something
-- missed an emission, this is the only retry.
if not EAB then
    local _posFrame = CreateFrame("Frame")
    _posFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _posFrame:SetScript("OnEvent", function(self)
        -- IMPORTANT: do NOT unregister. PEW also fires on every zone change
        -- (city -> instance, M+ portal, phasing). Keeping the listener live
        -- re-runs the initial sequence after every zone.
        --
        -- 1s delay: addons need time to register their unlock elements
        -- (RegisterUnlockElements is called from OnEnable / first PEW
        -- handler). After 1s every element should be registered and have
        -- valid bounds, so the initial position+anchor pass can run.
        -- After this single pass, all further repositioning is event-driven
        -- via NotifyElementResized -> dependency-sorted ReapplyAll cascade.
        -- No safety sweep timer -- if a real source change is missed, we
        -- want to find and fix the missing emission, not paper over it
        -- with periodic re-applies that themselves cause visible shifts.
        C_Timer.After(1, function()
            ApplySavedPositions()
            if EllesmereUI.ReapplyAllUnlockAnchors then
                EllesmereUI.ReapplyAllUnlockAnchors()
            end
        end)
    end)
end

-------------------------------------------------------------------------------
--  Accent color helper (reads live from EllesmereUI)
-------------------------------------------------------------------------------
local function GetAccent()
    local eg = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    if eg then return eg.r, eg.g, eg.b end
    return 12/255, 210/255, 157/255
end

-------------------------------------------------------------------------------
--  Grid overlay
-------------------------------------------------------------------------------
local function CreateGrid(parent)
    if gridFrame then return gridFrame end
    -- Grid lives on its own BACKGROUND-strata frame so it renders
    -- BEHIND the actual game UI elements (action bars, unit frames, etc.)
    gridFrame = CreateFrame("Frame", nil, UIParent)
    gridFrame:SetFrameStrata("BACKGROUND")
    gridFrame:SetAllPoints(UIParent)
    gridFrame:SetFrameLevel(1)
    gridFrame._lines = {}

    function gridFrame:Rebuild()
        for _, tex in ipairs(self._lines) do tex:Hide() end
        local idx = 0
        local w, h = UIParent:GetWidth(), UIParent:GetHeight()
        local ar, ag, ab = GetAccent()
        local baseA = GridBaseAlpha()
        local centerA = GridCenterAlpha()

        -- Pixel-perfect: use PP.mult so lines are exactly 1 physical pixel
        -- and spacing aligns to the physical pixel grid.
        local mult = PP and PP.mult or 1
        local lineW = mult
        local spacing = GRID_SPACING * mult

        -- Snap helper: round a UI coordinate to the nearest physical pixel
        local function snap(v) return floor(v / mult + 0.5) * mult end

        local centerX = snap(w / 2)
        local centerY = snap(h / 2)

        local function MakeLine(isVert, pos)
            idx = idx + 1
            local tex = self._lines[idx]
            if not tex then
                tex = self:CreateTexture(nil, "BACKGROUND", nil, -7)
                if tex.SetSnapToPixelGrid then
                    tex:SetSnapToPixelGrid(false)
                    tex:SetTexelSnappingBias(0)
                end
                self._lines[idx] = tex
            end
            tex:SetColorTexture(ar, ag, ab, baseA)
            tex._baseAlpha = baseA
            tex._isWhite = false
            tex._isVert = isVert
            tex._pos = pos
            tex:ClearAllPoints()
            if isVert then
                tex:SetSize(lineW, h)
                tex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos, 0)
            else
                tex:SetSize(w, lineW)
                tex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -pos)
            end
            tex:Show()
        end

        -- Vertical lines extending outward from center
        local x = centerX - spacing
        while x > 0 do MakeLine(true, snap(x)); x = x - spacing end
        x = centerX + spacing
        while x < w do MakeLine(true, snap(x)); x = x + spacing end

        -- Horizontal lines extending outward from center
        local y = centerY - spacing
        while y > 0 do MakeLine(false, snap(y)); y = y - spacing end
        y = centerY + spacing
        while y < h do MakeLine(false, snap(y)); y = y + spacing end

        -- Center crosshair: full-length accent lines at screen center
        -- Center crosshair: full-length accent lines at screen center
        for _, axis in ipairs({"V", "H"}) do
            idx = idx + 1
            local tex = self._lines[idx]
            if not tex then
                tex = self:CreateTexture(nil, "BACKGROUND", nil, -6)
                if tex.SetSnapToPixelGrid then
                    tex:SetSnapToPixelGrid(false)
                    tex:SetTexelSnappingBias(0)
                end
                self._lines[idx] = tex
            end
            tex:SetColorTexture(ar, ag, ab, centerA)
            tex._baseAlpha = centerA
            tex._isWhite = false
            tex._isVert = (axis == "V")
            tex._pos = 0
            tex:ClearAllPoints()
            if axis == "V" then
                tex:SetSize(lineW, h)
                tex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", centerX, 0)
            else
                tex:SetSize(w, lineW)
                tex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -centerY)
            end
            tex:Show()
        end

        -- White crosshair pip at dead center (short lines forming a + shape)
        -- Always 50% alpha regardless of grid brightness mode
        local CROSS_ARM = 20
        local CROSS_ALPHA = 0.5
        for _, axis in ipairs({"V", "H"}) do
            idx = idx + 1
            local tex = self._lines[idx]
            if not tex then
                tex = self:CreateTexture(nil, "BACKGROUND", nil, -5)
                if tex.SetSnapToPixelGrid then
                    tex:SetSnapToPixelGrid(false)
                    tex:SetTexelSnappingBias(0)
                end
                self._lines[idx] = tex
            end
            tex:SetColorTexture(1, 1, 1, CROSS_ALPHA)
            tex._baseAlpha = CROSS_ALPHA
            tex._isWhite = true
            tex._isVert = (axis == "V")
            tex._pos = 0
            tex:ClearAllPoints()
            if axis == "V" then
                tex:SetSize(lineW, CROSS_ARM * 2)
                tex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", centerX, -(centerY - CROSS_ARM))
            else
                tex:SetSize(CROSS_ARM * 2, lineW)
                tex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", centerX - CROSS_ARM, -centerY)
            end
            tex:Show()
        end

        self._lineCount = idx
    end

    -- Cache accent color; refreshed when grid is rebuilt
    local cachedAR, cachedAG, cachedAB = GetAccent()

    local origRebuild = gridFrame.Rebuild
    function gridFrame:Rebuild()
        origRebuild(self)
        cachedAR, cachedAG, cachedAB = GetAccent()
    end

    -- Cursor flashlight: highlights grid lines near the cursor.
    -- Uses a radial gradient texture for soft ambient glow, plus
    -- per-line segments with 2D distance-based alpha for crisp line highlights.
    local LIGHT_RADIUS   = 220
    local LIGHT_DIAMETER = LIGHT_RADIUS * 2
    local LIGHT_BOOST    = 0.55
    local NUM_SEGS       = 5
    local FLASH_PATH = "Interface\\AddOns\\EllesmereUI\\media\\unlock-flash.png"

    -- Ambient glow texture (soft circle behind lines)
    local flashTex = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    flashTex:SetTexture(FLASH_PATH)
    flashTex:SetSize(LIGHT_DIAMETER, LIGHT_DIAMETER)
    flashTex:SetBlendMode("ADD")
    flashTex:SetVertexColor(1, 1, 1, 0.03)
    flashTex:Hide()

    -- Line highlight segments
    gridFrame._glows = {}
    local glowIdx = 0

    local function GetGlow(idx)
        local g = gridFrame._glows[idx]
        if not g then
            g = gridFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
            gridFrame._glows[idx] = g
        end
        return g
    end

    gridFrame:SetScript("OnUpdate", function(self, dt)
        if not self:IsShown() then
            flashTex:Hide()
            return
        end

        if not flashlightEnabled then
            flashTex:Hide()
            for j = 1, #self._glows do
                if self._glows[j] then self._glows[j]:Hide() end
            end
            return
        end

        local scale = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx = cx / scale
        cy = cy / scale
        local screenH = UIParent:GetHeight()
        local screenW = UIParent:GetWidth()
        local cyFromTop = screenH - cy

        -- Position ambient glow
        flashTex:ClearAllPoints()
        flashTex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        flashTex:Show()

        -- Highlight line segments
        glowIdx = 0
        local R2 = LIGHT_RADIUS * LIGHT_RADIUS
        local lineCount = self._lineCount or #self._lines

        for i = 1, lineCount do
            local tex = self._lines[i]
            if tex and tex:IsShown() and tex._baseAlpha then
                local perpDist
                if tex._isVert then
                    perpDist = abs(tex._pos - cx)
                else
                    perpDist = abs(tex._pos - cyFromTop)
                end

                if perpDist < LIGHT_RADIUS then
                    local halfSpan = sqrt(R2 - perpDist * perpDist)
                    local segSize = (halfSpan * 2) / NUM_SEGS
                    local isW = tex._isWhite

                    if tex._isVert then
                        local spanStart = max(0, cy - halfSpan)
                        local spanEnd = min(screenH, cy + halfSpan)
                        local segY = spanStart
                        while segY < spanEnd do
                            local segEnd = min(segY + segSize, spanEnd)
                            local midY = (segY + segEnd) * 0.5
                            local dy = midY - cy
                            local dx = tex._pos - cx
                            local d2 = dx * dx + dy * dy
                            if d2 < R2 then
                                local t = 1 - sqrt(d2) / LIGHT_RADIUS
                                local alpha = LIGHT_BOOST * t * t
                                if alpha > 0.003 then
                                    glowIdx = glowIdx + 1
                                    local g = GetGlow(glowIdx)
                                    if isW then
                                        g:SetColorTexture(1, 1, 1, alpha)
                                    else
                                        g:SetColorTexture(cachedAR, cachedAG, cachedAB, alpha)
                                    end
                                    g:ClearAllPoints()
                                    g:SetSize(1, segEnd - segY)
                                    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", tex._pos, segY)
                                    g:Show()
                                end
                            end
                            segY = segEnd
                        end
                    else
                        local spanStart = max(0, cx - halfSpan)
                        local spanEnd = min(screenW, cx + halfSpan)
                        local segX = spanStart
                        while segX < spanEnd do
                            local segEnd = min(segX + segSize, spanEnd)
                            local midX = (segX + segEnd) * 0.5
                            local dx = midX - cx
                            local dy = tex._pos - cyFromTop
                            local d2 = dx * dx + dy * dy
                            if d2 < R2 then
                                local t = 1 - sqrt(d2) / LIGHT_RADIUS
                                local alpha = LIGHT_BOOST * t * t
                                if alpha > 0.003 then
                                    glowIdx = glowIdx + 1
                                    local g = GetGlow(glowIdx)
                                    if isW then
                                        g:SetColorTexture(1, 1, 1, alpha)
                                    else
                                        g:SetColorTexture(cachedAR, cachedAG, cachedAB, alpha)
                                    end
                                    g:ClearAllPoints()
                                    g:SetSize(segEnd - segX, 1)
                                    g:SetPoint("TOPLEFT", UIParent, "TOPLEFT", segX, -tex._pos)
                                    g:Show()
                                end
                            end
                            segX = segEnd
                        end
                    end
                end
            end
        end

        for j = glowIdx + 1, #self._glows do
            if self._glows[j] then self._glows[j]:Hide() end
        end
    end)

    return gridFrame
end

-------------------------------------------------------------------------------
--  Alignment guide lines + measurement labels (snap guides between bars)
-------------------------------------------------------------------------------
local activeGuides = {}
local measurePool = {}   -- pool of { frame, line, label } for distance markers

local function GetGuide(idx)
    if guidePool[idx] then return guidePool[idx] end
    local tex = unlockFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    tex:SetColorTexture(1, 1, 1, 1)
    guidePool[idx] = tex
    return tex
end

local function GetMeasure(idx)
    if measurePool[idx] then return measurePool[idx] end
    -- Each measurement marker: a small frame with a line + label
    local f = CreateFrame("Frame", nil, unlockFrame)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    -- Background pill for the label
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.85, 0.15, 0.85, 0.85)
    f._bg = bg
    -- Distance text
    local fs = f:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT_PATH, 9, "OUTLINE, SLUG")
    fs:SetTextColor(1, 1, 1, 1)
    f._label = fs
    -- Connector line (magenta)
    local line = f:CreateTexture(nil, "OVERLAY", nil, 5)
    line:SetColorTexture(0.85, 0.15, 0.85, 0.7)
    f._line = line
    -- Arrow caps (small triangles simulated with tiny textures)
    local arrowA = f:CreateTexture(nil, "OVERLAY", nil, 6)
    arrowA:SetColorTexture(0.85, 0.15, 0.85, 0.85)
    f._arrowA = arrowA
    local arrowB = f:CreateTexture(nil, "OVERLAY", nil, 6)
    arrowB:SetColorTexture(0.85, 0.15, 0.85, 0.85)
    f._arrowB = arrowB
    measurePool[idx] = f
    return f
end

-- Snap highlight: pulsing white border layered ON TOP of the green border.
-- Each mover gets a lazy-created _snapBrd (a second MakeBorder at a higher
-- frame level) so the green accent border stays visible underneath.
local snapHighlightElapsed = 0

local function GetOrCreateSnapBorder(m)
    if m._snapBrd then return m._snapBrd end
    local brd = EllesmereUI.MakeBorder(m, 1, 1, 1, 0)
    -- Raise above the accent border
    brd._frame:SetFrameLevel(m:GetFrameLevel() + 3)
    m._snapBrd = brd
    return brd
end

local SNAP_BG_R = 0.075 * 1.4
local SNAP_BG_G = 0.113 * 1.4
local SNAP_BG_B = 0.141 * 1.4

local function ClearSnapHighlight()
    if snapHighlightKey and movers[snapHighlightKey] then
        local m = movers[snapHighlightKey]
        if m._snapBrd then m._snapBrd:SetColor(1, 1, 1, 0) end
        -- Restore normal overlay brightness
        if darkOverlaysEnabled and m._bg then
            m._bg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
        end
    end
    snapHighlightKey = nil
    snapHighlightElapsed = 0
    if snapHighlightAnim then
        snapHighlightAnim:SetScript("OnUpdate", nil)
        snapHighlightAnim:Hide()
    end
end

local function ShowSnapHighlight(targetKey)
    if targetKey == snapHighlightKey then return end
    -- Hide old highlight
    if snapHighlightKey and movers[snapHighlightKey] then
        local old = movers[snapHighlightKey]
        if old._snapBrd then old._snapBrd:SetColor(1, 1, 1, 0) end
        if darkOverlaysEnabled and old._bg then
            old._bg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
        end
    end
    local m = movers[targetKey]
    if not m then
        ClearSnapHighlight()
        return
    end
    snapHighlightKey = targetKey
    snapHighlightElapsed = 0
    GetOrCreateSnapBorder(m)
    -- Brighten overlay by 25%
    if darkOverlaysEnabled and m._bg then
        m._bg:SetColorTexture(SNAP_BG_R, SNAP_BG_G, SNAP_BG_B, 0.95)
    end
    if not snapHighlightAnim then
        snapHighlightAnim = CreateFrame("Frame")
    end
    snapHighlightAnim:SetScript("OnUpdate", function(self, dt)
        snapHighlightElapsed = snapHighlightElapsed + dt
        local target = movers[snapHighlightKey]
        if not target or not target._snapBrd then
            ClearSnapHighlight()
            return
        end
        local alpha = 0.45 + 0.45 * sin(snapHighlightElapsed * 9.42)
        target._snapBrd:SetColor(1, 1, 1, alpha * 0.9)
    end)
    snapHighlightAnim:Show()
end

local function HideAllGuides()
    for _, tex in ipairs(guidePool) do tex:Hide() end
    for _, m in ipairs(measurePool) do m:Hide() end
    wipe(activeGuides)
end

-- Full cleanup including snap highlight (used when drag stops)
local function HideAllGuidesAndHighlight()
    HideAllGuides()
    ClearSnapHighlight()
end

-- Show a vertical measurement marker between two Y positions at a given X
-- yTop > yBot in screen coords (bottom-left origin)
local function ShowVerticalMeasure(idx, xPos, yBot, yTop, dist)
    local f = GetMeasure(idx)
    local gap = yTop - yBot
    if gap < 2 then f:Hide(); return idx end
    f:SetSize(1, 1)
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    f:SetAllPoints(UIParent)
    -- Connector line
    f._line:ClearAllPoints()
    f._line:SetSize(1, gap)
    f._line:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", xPos, yBot)
    f._line:Show()
    -- Arrow caps (small horizontal bars at each end)
    f._arrowA:ClearAllPoints()
    f._arrowA:SetSize(5, 1)
    f._arrowA:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", xPos, yBot)
    f._arrowA:Show()
    f._arrowB:ClearAllPoints()
    f._arrowB:SetSize(5, 1)
    f._arrowB:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", xPos, yTop)
    f._arrowB:Show()
    -- Label
    local text = floor(dist + 0.5) .. " px"
    f._label:SetText(EllesmereUI.L(text))
    local tw = f._label:GetStringWidth() + 8
    local th = f._label:GetStringHeight() + 4
    f._bg:ClearAllPoints()
    f._bg:SetSize(tw, th)
    local midY = (yBot + yTop) / 2
    f._bg:SetPoint("LEFT", UIParent, "BOTTOMLEFT", xPos + 4, midY)
    f._label:ClearAllPoints()
    f._label:SetPoint("CENTER", f._bg, "CENTER", 0, 0)
    f._bg:Show()
    f._label:Show()
    f:Show()
    return idx
end

-- Show a horizontal measurement marker between two X positions at a given Y
local function ShowHorizontalMeasure(idx, yPos, xLeft, xRight, dist)
    local f = GetMeasure(idx)
    local gap = xRight - xLeft
    if gap < 2 then f:Hide(); return idx end
    f:SetSize(1, 1)
    f:ClearAllPoints()
    f:SetAllPoints(UIParent)
    -- Connector line
    f._line:ClearAllPoints()
    f._line:SetSize(gap, 1)
    f._line:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", xLeft, yPos)
    f._line:Show()
    -- Arrow caps
    f._arrowA:ClearAllPoints()
    f._arrowA:SetSize(1, 5)
    f._arrowA:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", xLeft, yPos - 2)
    f._arrowA:Show()
    f._arrowB:ClearAllPoints()
    f._arrowB:SetSize(1, 5)
    f._arrowB:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", xRight, yPos - 2)
    f._arrowB:Show()
    -- Label
    local text = floor(dist + 0.5) .. " px"
    f._label:SetText(EllesmereUI.L(text))
    local tw = f._label:GetStringWidth() + 8
    local th = f._label:GetStringHeight() + 4
    f._bg:ClearAllPoints()
    f._bg:SetSize(tw, th)
    local midX = (xLeft + xRight) / 2
    f._bg:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", midX, yPos + 4)
    f._label:ClearAllPoints()
    f._label:SetPoint("CENTER", f._bg, "CENTER", 0, 0)
    f._bg:Show()
    f._label:Show()
    f:Show()
    return idx
end

-------------------------------------------------------------------------------
--  ShowAlignmentGuides — draws full-screen guide lines at snap positions
--  and measurement markers for equal-spacing snaps.
--  Called from the drag OnUpdate; snapInfo is populated by SnapPosition.
-------------------------------------------------------------------------------
local lastSnapInfo = {}  -- written by SnapPosition, read by ShowAlignmentGuides
-- Expose whether each axis has an active edge snap so OnUpdate can skip
-- SnapForES on that axis (the unsnapped value already matches the target edge).
EllesmereUI._snapAxisLocked = function() return lastSnapInfo.lockX, lastSnapInfo.lockY end

local function ShowAlignmentGuides(dragKey)
    HideAllGuides()
    if not lastSnapInfo then return end

    local ar, ag, ab = GetAccent()
    local guideIdx = 0
    local screenW = UIParent:GetWidth()
    local screenH = UIParent:GetHeight()

    -- Edge/center snap guide lines (1 physical pixel wide)
    local PPg = EllesmereUI and EllesmereUI.PP
    local onePx = PPg and PPg.mult or 1
    if lastSnapInfo.snapXPos then
        guideIdx = guideIdx + 1
        local g = GetGuide(guideIdx)
        g:SetColorTexture(ar, ag, ab, 0.5)
        g:ClearAllPoints()
        g:SetSize(onePx, screenH)
        g:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", lastSnapInfo.snapXPos, 0)
        g:Show()
        activeGuides[guideIdx] = g
    end
    if lastSnapInfo.snapYPos then
        guideIdx = guideIdx + 1
        local g = GetGuide(guideIdx)
        g:SetColorTexture(ar, ag, ab, 0.5)
        g:ClearAllPoints()
        g:SetSize(screenW, onePx)
        g:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, lastSnapInfo.snapYPos)
        g:Show()
        activeGuides[guideIdx] = g
    end

    -- Snap highlight: pulse the border of the element being snapped to
    local dragMover = movers[dragKey]
    local hasSpecificTarget = dragMover and dragMover._snapTarget
        and dragMover._snapTarget ~= "_disable_"
        and dragMover._snapTarget ~= "_select_"
    if hasSpecificTarget and movers[dragMover._snapTarget] then
        ShowSnapHighlight(dragMover._snapTarget)
    elseif lastSnapInfo.closestKey then
        ShowSnapHighlight(lastSnapInfo.closestKey)
    else
        ClearSnapHighlight()
    end
end

-------------------------------------------------------------------------------
--  Snap-to-element helper
--  1) Find the single closest mover (by minimum edge-to-edge distance).
--     Only consider movers within SNAP_PROXIMITY px.
--  2) Check 9 X-axis pairs + 9 Y-axis pairs against that one mover.
--  Populates lastSnapInfo for ShowAlignmentGuides to read.
-------------------------------------------------------------------------------

local function SnapPosition(dragKey, cx, cy, halfW, halfH)
    wipe(lastSnapInfo)
    if not snapEnabled then return cx, cy end

    local dL = cx - halfW
    local dR = cx + halfW
    local dT = cy + halfH
    local dB = cy - halfH

    -- Step 1: find snap target mover
    -- If this mover has a specific snap target, use it; otherwise find closest
    local closestKey = nil
    local dragMover = movers[dragKey]
    local perMoverTarget = dragMover and dragMover._snapTarget
    -- "_disable_" = snapping disabled for this specific mover
    if perMoverTarget == "_disable_" then return cx, cy end
    if perMoverTarget and perMoverTarget ~= dragKey and movers[perMoverTarget] and movers[perMoverTarget]:IsShown() then
        closestKey = perMoverTarget
    else
        -- Find closest by true 2D edge-to-edge distance (no limit)
        local closestMinDist = math.huge
        -- Build a set of keys to exclude from snap: all descendants (children,
        -- grandchildren, etc.) and siblings (anchored to the same parent).
        -- The direct parent IS allowed for snapping.
        local dragExcluded = {}
        local anchorDB = GetAnchorDB()
        if anchorDB then
            -- Recursively exclude all descendants
            local function ExcludeDescendants(parentKey)
                for childKey, info in pairs(anchorDB) do
                    if info.target == parentKey and not dragExcluded[childKey] then
                        dragExcluded[childKey] = true
                        ExcludeDescendants(childKey)
                    end
                end
            end
            ExcludeDescendants(dragKey)
            -- Exclude siblings (share the same anchor parent)
            local myInfo = anchorDB[dragKey]
            if myInfo and myInfo.target then
                for sibKey, sibInfo in pairs(anchorDB) do
                    if sibKey ~= dragKey and sibInfo.target == myInfo.target then
                        dragExcluded[sibKey] = true
                    end
                end
            end
        end
        for key, mover in pairs(movers) do
            if key ~= dragKey and not dragExcluded[key] and mover:IsShown() then
                local oL = mover:GetLeft()   or 0
                local oR = mover:GetRight()  or 0
                local oT = mover:GetTop()    or 0
                local oB = mover:GetBottom() or 0
                -- Signed axis distances (negative = overlapping on that axis)
                local gapX = 0
                if dR < oL then gapX = oL - dR
                elseif dL > oR then gapX = dL - oR end
                local gapY = 0
                if dB > oT then gapY = dB - oT
                elseif dT < oB then gapY = oB - dT end
                -- 2D edge-to-edge distance (0 if overlapping)
                local edgeDist = sqrt(gapX * gapX + gapY * gapY)
                if edgeDist < closestMinDist then
                    closestMinDist = edgeDist
                    closestKey = key
                end
            end
        end
    end

    lastSnapInfo.closestKey = closestKey
    local bestDX, bestDistX = 0, SNAP_THRESH
    local bestDY, bestDistY = 0, SNAP_THRESH
    local snapXLinePos, snapYLinePos = nil, nil

    -- Step 2: 9+9 edge pairs against closest mover
    if closestKey then
        local m = movers[closestKey]
        local oL = m:GetLeft()   or 0
        local oR = m:GetRight()  or 0
        local oT = m:GetTop()    or 0
        local oB = m:GetBottom() or 0
        local oCX = (oL + oR) * 0.5
        local oCY = (oT + oB) * 0.5

        -- X-axis: dragged {left, center, right} vs target {left, center, right}
        local dragXEdges = { dL, cx, dR }
        local targXEdges = { oL, oCX, oR }
        local snapXEdgeIdx = nil
        for di, de in ipairs(dragXEdges) do
            for _, te in ipairs(targXEdges) do
                local dx = de - te
                local adx = abs(dx)
                if adx < bestDistX then
                    bestDistX = adx
                    bestDX = dx
                    snapXLinePos = te
                    snapXEdgeIdx = di
                end
            end
        end

        -- Y-axis: dragged {top, center, bottom} vs target {top, center, bottom}
        local dragYEdges = { dT, cy, dB }
        local targYEdges = { oT, oCY, oB }
        local snapYEdgeIdx = nil
        for di, de in ipairs(dragYEdges) do
            for _, te in ipairs(targYEdges) do
                local dy = de - te
                local ady = abs(dy)
                if ady < bestDistY then
                    bestDistY = ady
                    bestDY = dy
                    snapYLinePos = te
                    snapYEdgeIdx = di
                end
            end
        end
    end

    -- Apply edge/center snap
    local snapX = cx
    local snapY = cy
    if bestDistX < SNAP_THRESH then snapX = cx - bestDX end
    if bestDistY < SNAP_THRESH then snapY = cy - bestDY end

    -- Record guide line positions for ShowAlignmentGuides
    if bestDistX < SNAP_THRESH and snapXLinePos then
        lastSnapInfo.snapXPos = snapXLinePos
        lastSnapInfo.xEdge = snapXEdgeIdx
        lastSnapInfo.lockX = true  -- skip SnapForES on X axis
    end
    if bestDistY < SNAP_THRESH and snapYLinePos then
        lastSnapInfo.snapYPos = snapYLinePos
        lastSnapInfo.yEdge = snapYEdgeIdx
        lastSnapInfo.lockY = true  -- skip SnapForES on Y axis
    end

    return snapX, snapY
end

-------------------------------------------------------------------------------
--  Selection + Arrow Key Nudge System
-------------------------------------------------------------------------------
-- Selection highlight: a low-opacity white fill over the selected element's
-- overlay background, so the currently-selected element (the one arrow keys
-- move) is clearly marked, like the snap-target highlight shown during drag.
local function SetSelectionHighlight(m, on)
    if not m then return end
    if on then
        if not m._selHl then
            local hl = m:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 1)
            m._selHl = hl
        end
        m._selHl:SetAlpha(0.10)
        m._selHl:Show()
    elseif m._selHl then
        m._selHl:Hide()
    end
end

local function SelectMover(m)
    local ar, ag, ab = GetAccent()
    -- Deselect previous
    if selectedMover and selectedMover ~= m then
        selectedMover._selected = false
        SetSelectionHighlight(selectedMover, false)
        if not selectedMover._dragging and not selectedMover:IsMouseOver() then
            selectedMover:SetFrameLevel(selectedMover._baseLevel)
            if not darkOverlaysEnabled then selectedMover:SetAlpha(MOVER_ALPHA) end
            selectedMover._brd:SetColor(ar, ag, ab, 0.6)
            -- Collapse overlay on old selection
            if selectedMover._hideOverlayText then selectedMover._hideOverlayText() end
        end
        -- Hide action buttons on old selection
        if selectedMover._hideCogAfterDelay then selectedMover._hideCogAfterDelay() end
        -- Hide coordinates on old selection (keep if coords-always-on)
        if selectedMover._coordFS and not coordsEnabled then selectedMover._coordFS:Hide() end
    end
    selectedMover = m
    if m then
        m._selected = true
        SetSelectionHighlight(m, true)
        m:SetFrameLevel(m._raisedLevel)
        if not darkOverlaysEnabled then m:SetAlpha(MOVER_HOVER) end
        m._brd:SetColor(1, 1, 1, 0.9)

        -- Update coordinates on selection (expansion is hover-only)
        if m.UpdateCoordText then m:UpdateCoordText() end

        -- Pulse the snap target if this mover has a specific one assigned
        local tgt = m._snapTarget
        if tgt and tgt ~= "_disable_" and tgt ~= "_select_" and movers[tgt] then
            ShowSnapHighlight(tgt)
        else
            ClearSnapHighlight()
        end
    end
end

local function DeselectMover()
    if selectedMover then
        local ar, ag, ab = GetAccent()
        selectedMover._selected = false
        SetSelectionHighlight(selectedMover, false)
        if not selectedMover._dragging then
            if not selectedMover:IsMouseOver() then
                selectedMover:SetFrameLevel(selectedMover._baseLevel)
                if not darkOverlaysEnabled then selectedMover:SetAlpha(MOVER_ALPHA) end
                selectedMover._brd:SetColor(ar, ag, ab, 0.6)
                if selectedMover._hideOverlayText then selectedMover._hideOverlayText() end
            end
        end
        -- Restore settings widgets to base level
        -- Hide coordinates (keep visible if coords-always-on mode is active)
        if selectedMover._coordFS and not coordsEnabled then selectedMover._coordFS:Hide() end
        -- Clear snap highlight
        ClearSnapHighlight()
        -- Cancel select-element pick mode if this mover was the picker — restore previous target
        if selectElementPicker == selectedMover then
            selectedMover._snapTarget = selectedMover._preSelectTarget
            selectedMover._preSelectTarget = nil
            if selectedMover._updateSnapLabel then selectedMover._updateSnapLabel() end
            selectElementPicker = nil
            FadeOverlayForSelectElement(false)
        end
        -- Cancel width/height/anchor pick mode if this mover was the picker
        if pickModeMover == selectedMover then
            CancelPickMode()
        end
    end
    selectedMover = nil
end

-- Apply dark overlay state to all movers
local function ApplyDarkOverlays()
    for _, m in pairs(movers) do
        if darkOverlaysEnabled then
            m._bg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
            if m._label then m._label:SetAlpha(1); m._label:Show() end
            if m._coordFS then m._coordFS:SetAlpha(1) end
            -- Action row is hover-only now, don't show it here
            if not m._dragging then m:SetAlpha(1) end
        else
            m._bg:SetColorTexture(0, 0, 0, 0)
            if m._label then m._label:Hide() end
            -- When coords-always-on is active, show coords for all movers; otherwise hide
            if m._coordFS then
                if coordsEnabled then
                    if m.UpdateCoordText then m:UpdateCoordText() end
                else
                    m._coordFS:Hide()
                end
            end
            -- Hide action row text
            if m._hideOverlayText then m._hideOverlayText() end
            -- Restore normal alpha behavior
            if not m._dragging and not m._selected and not m:IsMouseOver() then
                m:SetAlpha(MOVER_ALPHA)
            end
        end
    end
end
local function NudgeMover(dx, dy, targetMover, skipCollapse)
    local m = targetMover or selectedMover
    if not m or InCombatLockdown() then return end

    -- Read bar's current position, add dx/dy, reposition.
    local bar = GetBarFrame(m._barKey)
    if not bar then return end

    local ai = GetAnchorInfo(m._barKey)
    if ai and ai.target then
        -- Anchored: adjust offset relative to target frame (not UIParent).
        -- Reading GetPoint(1) on an anchored element returns args relative to
        -- the target frame — applying those to UIParent teleports the bar.
        ai.offsetX = (ai.offsetX or 0) + dx
        ai.offsetY = (ai.offsetY or 0) + dy
        ApplyAnchorPosition(m._barKey, ai.target, ai.side)
        -- Capture the bar's resulting position so CommitPositions saves the real
        -- (nudged) location. ApplyAnchorPosition always anchors the bar to
        -- UIParent, so GetPoint(1) is UIParent-relative and safe to store.
        -- A coordless {_anchored=true} marker would make CommitPositions fall
        -- back to the pre-edit snapshot, reverting bars that read their saved
        -- edge back on exit/reload (StanceBar, anchored CDM growth bars).
        local bpt, brelTo, brp, bx, by = bar:GetPoint(1)
        if bpt and brelTo == UIParent and bx ~= nil and by ~= nil then
            pendingPositions[m._barKey] = { point = bpt, relPoint = brp, x = bx, y = by }
        else
            pendingPositions[m._barKey] = { _anchored = true }
        end
    else
        -- Unanchored: read current position, add dx/dy
        local pt, _, relPt, offX, offY = bar:GetPoint(1)
        if not pt then return end
        pcall(function()
            bar:ClearAllPoints()
            bar:SetPoint(pt, UIParent, relPt, offX + dx, offY + dy)
        end)
        pendingPositions[m._barKey] = {
            point = pt, relPoint = relPt,
            x = offX + dx, y = offY + dy,
        }
    end
    hasChanges = true

    -- Reanchor mover to bar
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)

    -- Update stored mover center from bar's new position
    local bL, bR = bar:GetLeft(), bar:GetRight()
    local bT, bB = bar:GetTop(), bar:GetBottom()
    if bL and bR and bT and bB then
        local s = bar:GetEffectiveScale()
        local uiS = UIParent:GetEffectiveScale()
        local ratio = s / uiS
        local cx = (bL + bR) * 0.5 * ratio
        local cy = (bT + bB) * 0.5 * ratio - UIParent:GetHeight()
        if m._setCenterXY then m._setCenterXY(cx, cy) end
    end

    -- Propagate to anchored children
    PropagateAnchorChain(m._barKey)

    -- Update coordinate readout
    if m.UpdateCoordText then m:UpdateCoordText() end

    -- Collapse the mover while nudging (arrow keys only). Typed cog edits pass
    -- skipCollapse so the open cog menu, which is anchored to the mover, does
    -- not jump or shrink while the user is typing in it.
    if not skipCollapse then
        if m._forceCollapse then m._forceCollapse() end
        m._nudgeCollapsed = true
    end
end

-- Exposed so the cog X/Y edit boxes can drive the SAME pixel-exact move the
-- arrow keys use. Calling through the namespace table (already an upvalue in
-- CreateMover) avoids adding NudgeMover as a new upvalue to that large closure.
EllesmereUI._unlockNudge = NudgeMover

-- Arrow key nudge: single press only, no hold-to-repeat
local function SetupArrowKeyFrame()
    if arrowKeyFrame then return end
    arrowKeyFrame = CreateFrame("Frame", nil, UIParent)
    arrowKeyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    arrowKeyFrame:SetFrameLevel(500)
    arrowKeyFrame:EnableKeyboard(true)
    arrowKeyFrame:SetPropagateKeyboardInput(true)
    arrowKeyFrame:Hide()

    local ARROW_DIRS = {
        UP    = { 0,  1 },
        DOWN  = { 0, -1 },
        LEFT  = { -1, 0 },
        RIGHT = { 1,  0 },
    }

    arrowKeyFrame:SetScript("OnKeyDown", function(self, key)
        if not selectedMover or not isUnlocked then return end
        local dir = ARROW_DIRS[key]
        if not dir then return end
        self:SetPropagateKeyboardInput(false)
        -- Scale by physical pixel size so each press moves exactly 1px
        local PPn = EllesmereUI and EllesmereUI.PP
        local pxStep = PPn and PPn.mult or 1
        local step = IsShiftKeyDown() and (100 * pxStep) or pxStep
        -- When this element's cog/snap menu is open, keep the mover expanded
        -- (skipCollapse) so the open menu does not jump, then reanchor to the bar
        -- and refresh the cog X/Y boxes so they track the nudge.
        local m = selectedMover
        local menuOpen = m._menuOpen
        NudgeMover(dir[1] * step, dir[2] * step, nil, menuOpen)
        if menuOpen then
            if m.ReanchorToBar then m:ReanchorToBar() end
            if m._syncCogPos then m._syncCogPos() end
        end
    end)

    arrowKeyFrame:SetScript("OnKeyUp", function(self, key)
        self:SetPropagateKeyboardInput(true)
    end)
end

-------------------------------------------------------------------------------
--  Action bar visual size helper
--  Computes the actual visual size of an action bar accounting for
--  overrideNumIcons, overrideNumRows, padding, and per-button scale.
--  Returns w, h in UIParent-relative pixels, or nil if not applicable.
-------------------------------------------------------------------------------
local function GetActionBarVisualSize(barKey)
    if not EAB or not EAB.db then return nil end
    local info = BAR_LOOKUP[barKey]
    if not info then return nil end
    local s = EAB.db.profile.bars[lookupKey]
    if not s then return nil end

    -- Use standard button size (45x45) — our LayoutBar uses this for MainBar
    -- and reads from the button for others.
    local btnW, btnH = 45, 45
    local btn1 = _G[info.buttonPrefix .. "1"]
    if btn1 and lookupKey ~= "MainBar" then
        local bw = btn1:GetWidth()
        if bw and bw > 1 then btnW, btnH = bw, btn1:GetHeight() end
    end

    local numVisible = s.overrideNumIcons or s.numIcons or info.count
    if numVisible < 1 then numVisible = info.count end
    local numRows = s.overrideNumRows or s.numRows or 1
    if numRows < 1 then numRows = 1 end

    local pad = s.buttonPadding or 2

    -- Use explicit button dimensions if set
    local bwOverride = (s.buttonWidth and s.buttonWidth > 0) and s.buttonWidth or nil
    local bhOverride = (s.buttonHeight and s.buttonHeight > 0) and s.buttonHeight or nil
    if bwOverride then btnW = bwOverride end
    if bhOverride then btnH = bhOverride end

    local shape = s.buttonShape or "none"
    if shape ~= "none" and shape ~= "cropped" then
        btnW = btnW + (ns.SHAPE_BTN_EXPAND or 10)
        btnH = btnH + (ns.SHAPE_BTN_EXPAND or 10)
    end
    if shape == "cropped" then
        btnH = btnH * 0.80
    end

    local isVert = (s.orientation == "vertical")
    local stride = math.ceil(numVisible / numRows)

    local gridW, gridH
    if isVert then
        gridW = numRows * btnW + (numRows - 1) * pad
        gridH = stride * btnH + (stride - 1) * pad
    else
        gridW = stride * btnW + (stride - 1) * pad
        gridH = numRows * btnH + (numRows - 1) * pad
    end

    return gridW, gridH
end

-------------------------------------------------------------------------------
--  Mover overlay creation
-------------------------------------------------------------------------------

-- Sort movers by area so smaller elements render on top of larger ones.
-- Called after all movers are created and synced.
local function SortMoverFrameLevels()
    if not unlockFrame then return end
    local BASE = unlockFrame:GetFrameLevel() + 20
    local sorted = {}
    for key, m in pairs(movers) do
        local area = (m:GetWidth() or 100) * (m:GetHeight() or 100)
        sorted[#sorted + 1] = { key = key, mover = m, area = area }
    end
    -- Largest area first -> lowest frame level
    table.sort(sorted, function(a, b) return a.area > b.area end)
    for i, entry in ipairs(sorted) do
        local lvl = BASE + i
        entry.mover._baseLevel = lvl
        entry.mover._raisedLevel = lvl + #sorted + 5
        entry.mover:SetFrameLevel(lvl)
    end
end

-------------------------------------------------------------------------------
--  Blizzard-Owned Info Overlays
--  Visual overlays shown during unlock mode on elements whose position is
--  controlled by Blizzard Edit Mode (chat, micro menu, bags, encounter bar).
--  Not draggable. Hover shows accent-colored "Move via Blizz Edit Mode"
--  text with the same animation as regular mover links. Clicking the text
--  closes unlock mode and opens Blizzard's Edit Mode.
-------------------------------------------------------------------------------
local BLIZZ_OWNED_OVERLAY_DEFS = {
    { label = "Chat", frame = function()
          if not EllesmereUI._chatCFD then return nil end
          return ChatFrame1
      end,
      anchor = function(ov, cf)
          -- Span sidebar + bg + tabs for the full chat region.
          -- Detect sidebar side by comparing screen positions.
          local cfd = EllesmereUI._chatCFD and EllesmereUI._chatCFD(cf)
          local bg = cfd and cfd.bg
          local sidebar = cfd and cfd.sidebar
          if not bg then
              ov:SetAllPoints(cf)
              return
          end
          local sidebarRight = false
          if sidebar and bg and sidebar.GetLeft and bg.GetLeft then
              local sl = sidebar:GetLeft() or 0
              local bl = bg:GetLeft() or 0
              sidebarRight = sl > bl
          end
          ov:ClearAllPoints()
          if sidebarRight then
              ov:SetPoint("TOPLEFT", bg, "TOPLEFT", 0, 0)
              ov:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
          else
              ov:SetPoint("TOPLEFT", sidebar or bg, "TOPLEFT", 0, 0)
              ov:SetPoint("BOTTOMRIGHT", bg, "BOTTOMRIGHT", 0, 0)
          end
          -- Extend top to cover tabs (they sit above the bg)
          local tab1 = _G.ChatFrame1Tab
          if tab1 and tab1:IsShown() then
              local topAnchor = sidebarRight and bg or (sidebar or bg)
              ov:SetPoint("TOPLEFT", topAnchor, "TOPLEFT", 0, tab1:GetHeight() + 2)
          end
      end },
    { label = "Micro Menu",    frame = function() return _G.MicroMenuContainer end },
    { label = "Bags",          frame = function() return _G.BagsBar end },
    { label = "Encounter Bar", frame = function() return _G.PlayerPowerBarAlt end, showAlways = true, fallbackW = 240, fallbackH = 36, yOffset = 44 },
    { label = "Buffs",         frame = function() return _G.BuffFrame end },
    { label = "Debuffs",       frame = function() return _G.DebuffFrame end },
}

local function CreateBlizzOwnedOverlay(def, parent)
    local ar, ag, ab = GetAccent()
    local ov = CreateFrame("Frame", nil, parent)
    ov:EnableMouse(true)
    -- Background: same as regular movers
    local bg = ov:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
    -- Border: accent at idle, white on hover
    local brd = EllesmereUI.MakeBorder(ov, ar, ag, ab, 0.6)
    ov._brd = brd
    -- Label (always visible, same style as mover labels)
    local nameFs = ov:CreateFontString(nil, "OVERLAY")
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(nameFs, true) end
    nameFs:SetFont(FONT_PATH, 10 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
    nameFs:SetPoint("CENTER", ov, "CENTER", 0, 0)
    nameFs:SetTextColor(1, 1, 1, 0.75)
    nameFs:SetText(EllesmereUI.L(def.label))
    nameFs:SetWordWrap(false)
    ov._nameFs = nameFs
    -- Action text (hidden at idle, fades in on hover)
    local actionFs = ov:CreateFontString(nil, "OVERLAY")
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(actionFs, true) end
    actionFs:SetFont(FONT_PATH, 9 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
    actionFs:SetPoint("TOP", nameFs, "BOTTOM", 0, -2)
    actionFs:SetTextColor(ar, ag, ab, 0.9)
    actionFs:SetText(EllesmereUI.L("Move via Blizz Edit Mode"))
    actionFs:SetAlpha(0)
    ov._actionFs = actionFs
    -- Clickable button sized to the action text only
    local actionBtn = CreateFrame("Button", nil, ov)
    actionBtn:SetFrameLevel(ov:GetFrameLevel() + 2)
    actionBtn:SetPoint("TOPLEFT", actionFs, "TOPLEFT", -4, 2)
    actionBtn:SetPoint("BOTTOMRIGHT", actionFs, "BOTTOMRIGHT", 4, -2)
    actionBtn:Hide()
    -- Hover animation state
    local hoverT = 0
    local hoverTarget = 0
    local animFrame = CreateFrame("Frame")
    local function ApplyHover(t)
        actionFs:SetAlpha(t)
        if t > 0.01 then actionBtn:Show() else actionBtn:Hide() end
        -- Shift label up to make room for action text
        local yOff = t * 5
        nameFs:SetPoint("CENTER", ov, "CENTER", 0, yOff)
    end
    animFrame:SetScript("OnUpdate", function(self, dt)
        local dir = hoverTarget > hoverT and 1 or -1
        hoverT = hoverT + dir * (dt / 0.15)
        if (dir == 1 and hoverT >= hoverTarget) or (dir == -1 and hoverT <= hoverTarget) then
            hoverT = hoverTarget
            if hoverT == 0 then self:Hide() end
        end
        ApplyHover(hoverT)
    end)
    animFrame:Hide()
    -- Hover handlers on the overlay frame
    local function OnEnter()
        hoverTarget = 1
        ov._brd:SetColor(1, 1, 1, 0.9)
        animFrame:Show()
    end
    local function OnLeave()
        if actionBtn:IsShown() and actionBtn:IsMouseOver() then return end
        if ov:IsMouseOver() then return end
        hoverTarget = 0
        ov._brd:SetColor(ar, ag, ab, 0.6)
        animFrame:Show()
    end
    ov:SetScript("OnEnter", OnEnter)
    ov:SetScript("OnLeave", OnLeave)
    -- Action button hover: brighten text, keep overlay hovered
    actionBtn:SetScript("OnEnter", function()
        actionFs:SetTextColor(1, 1, 1, 1)
        OnEnter()
    end)
    actionBtn:SetScript("OnLeave", function()
        actionFs:SetTextColor(ar, ag, ab, 0.9)
        OnLeave()
    end)
    -- Click: close unlock mode, open Blizzard Edit Mode
    actionBtn:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        if EditModeManagerFrame then
            ns.RequestClose(false, function()
                ShowUIPanel(EditModeManagerFrame)
            end)
        end
    end)
    ov._forceCollapse = function()
        hoverT = 0; hoverTarget = 0
        animFrame:Hide()
        ApplyHover(0)
        ov._brd:SetColor(ar, ag, ab, 0.6)
    end
    return ov
end

local function ShowBlizzOwnedOverlays(parent)
    for _, def in ipairs(BLIZZ_OWNED_OVERLAY_DEFS) do
        local anchorFrame = def.frame()
        if not anchorFrame then
            -- frame doesn't exist at all, skip
        elseif anchorFrame:IsShown() and anchorFrame:GetWidth() > 1 then
            -- Visible frame: anchor directly
            local ov = _blizzOwnedOverlays[def.label]
            if not ov then
                ov = CreateBlizzOwnedOverlay(def, parent)
                _blizzOwnedOverlays[def.label] = ov
            end
            -- Same strata as the regular movers (FULLSCREEN_DIALOG) but a lower level
            -- (movers sit at unlockFrame+20), so non-Blizzard overlays always render
            -- above these Blizzard Edit Mode overlays. Still above the dimmer (+1).
            ov:SetFrameStrata("FULLSCREEN_DIALOG")
            ov:SetFrameLevel(parent:GetFrameLevel() + 15)
            ov:ClearAllPoints()
            if def.anchor then
                def.anchor(ov, anchorFrame)
            else
                ov:SetAllPoints(anchorFrame)
            end
            ov._forceCollapse()
            ov:Show()
        elseif def.showAlways then
            -- Hidden frame but showAlways: position at frame's location with fallback size
            local ov = _blizzOwnedOverlays[def.label]
            if not ov then
                ov = CreateBlizzOwnedOverlay(def, parent)
                _blizzOwnedOverlays[def.label] = ov
            end
            -- FULLSCREEN_DIALOG (below movers at +20, above the dimmer at +1) so
            -- non-Blizzard overlays always render above Blizzard Edit Mode overlays.
            ov:SetFrameStrata("FULLSCREEN_DIALOG")
            ov:SetFrameLevel(parent:GetFrameLevel() + 15)
            ov:ClearAllPoints()
            ov:SetSize(def.fallbackW or 200, def.fallbackH or 40)
            -- Read the frame's current anchor or fall back to bottom center
            local pt, rel, rpt, ox, oy = anchorFrame:GetPoint(1)
            local yAdj = def.yOffset or 0
            if pt and rel then
                ov:SetPoint(pt, rel, rpt or pt, ox or 0, (oy or 0) + yAdj)
            else
                ov:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200 + yAdj)
            end
            ov._forceCollapse()
            ov:Show()
        end
    end
end

local function HideBlizzOwnedOverlays()
    for _, ov in pairs(_blizzOwnedOverlays) do
        if ov._forceCollapse then ov._forceCollapse() end
        ov:Hide()
    end
end

local function CreateMover(barKey)
    local elem = registeredElements[barKey]
    local existing = movers[barKey]

    -- Skip elements that are intentionally hidden or currently anchored.
    if elem and ((elem.isHidden and elem.isHidden()) or (elem.isAnchored and elem.isAnchored())) then
        if existing then existing:Hide() end
        return nil
    end

    if existing then return existing end

    local bar = GetBarFrame(barKey)
    if not bar then return nil end

    local ar, ag, ab = GetAccent()
    local label = GetBarLabel(barKey)
    local cogBtn  -- forward declaration; assigned later in CreateMover

    local mover = CreateFrame("Button", nil, unlockFrame)
    -- Party Frames always render above Raid Frames in unlock mode
    local MOVER_LEVEL_BUMP = (barKey == "RF_PartyFrames") and 10 or 0
    local MOVER_BASE_LEVEL = unlockFrame:GetFrameLevel() + 20 + MOVER_LEVEL_BUMP
    local MOVER_RAISED_LEVEL = MOVER_BASE_LEVEL + 5
    mover:SetFrameLevel(MOVER_BASE_LEVEL)
    mover._baseLevel = MOVER_BASE_LEVEL
    mover._raisedLevel = MOVER_RAISED_LEVEL
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:RegisterForDrag("LeftButton")
    mover:EnableMouse(true)
    mover:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then _mouseHeld = true end
    end)
    -- OnMouseUp is set later (after link buttons are created) to also handle link drag forwarding

    -- Background (matches cogwheel dark color at 75% opacity)
    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if darkOverlaysEnabled then
        bg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
    else
        bg:SetColorTexture(0, 0, 0, 0)
    end
    mover._bg = bg

    -- Pixel-perfect border (accent colored, uses shared MakeBorder)
    local brd = EllesmereUI.MakeBorder(mover, ar, ag, ab, 0.6)
    mover._brd = brd

    -- Label — on a higher-level frame so it renders above the border
    local labelFrame = CreateFrame("Frame", nil, mover)
    labelFrame:SetAllPoints()
    labelFrame:SetClipsChildren(true)
    labelFrame:SetFrameLevel(mover:GetFrameLevel() + 3)
    local nameFS = labelFrame:CreateFontString(nil, "OVERLAY")
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(nameFS, true) end
    nameFS:SetFont(FONT_PATH, 10 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
    nameFS:SetText(EllesmereUI.L(label))
    nameFS:SetTextColor(1, 1, 1, 0.75)
    nameFS:SetWordWrap(false)
    nameFS:SetNonSpaceWrap(false)
    nameFS:SetPoint("CENTER", mover, "CENTER")
    mover._label = nameFS
    if not darkOverlaysEnabled then nameFS:Hide() end

    -- Coordinate readout (shows during drag and selection, top-left of mover)
    local coordFS = labelFrame:CreateFontString(nil, "OVERLAY")
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(coordFS, true) end
    coordFS:SetFont(FONT_PATH, 9 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
    coordFS:SetTextColor(1, 1, 1, 0.7)
    coordFS:SetPoint("TOPLEFT", mover, "TOPLEFT", 3, -2)
    coordFS:Hide()
    mover._coordFS = coordFS

    ---------------------------------------------------------------------------
    --  W Match | H Match | Anchor | Grow  (centered below the name)
    --  Also: "Anchored" text and pick-mode instruction text
    ---------------------------------------------------------------------------
    -- Action link text labels
    local WM_TEXT = "W Match"
    local HM_TEXT = "H Match"
    local AT_TEXT = "Anchor"
    local GD_TEXT = "Grow"

    -- Clickable buttons for each action (parented to labelFrame for correct level)
    local wmBtn = CreateFrame("Button", nil, labelFrame)
    wmBtn:SetFrameLevel(labelFrame:GetFrameLevel() + 2)
    wmBtn:RegisterForClicks("LeftButtonUp")
    wmBtn:EnableMouse(true)
    wmBtn:Hide()

    local hmBtn = CreateFrame("Button", nil, labelFrame)
    hmBtn:SetFrameLevel(labelFrame:GetFrameLevel() + 2)
    hmBtn:RegisterForClicks("LeftButtonUp")
    hmBtn:EnableMouse(true)
    hmBtn:Hide()

    local atBtn = CreateFrame("Button", nil, labelFrame)
    atBtn:SetFrameLevel(labelFrame:GetFrameLevel() + 2)
    atBtn:RegisterForClicks("LeftButtonUp")
    atBtn:EnableMouse(true)
    atBtn:Hide()

    local gdBtn = CreateFrame("Button", nil, labelFrame)
    gdBtn:SetFrameLevel(labelFrame:GetFrameLevel() + 2)
    gdBtn:RegisterForClicks("LeftButtonUp")
    gdBtn:EnableMouse(true)
    gdBtn:Hide()

    -- Store link buttons on mover so OnLeave can check if any are hovered
    mover._linkBtns = { wmBtn, hmBtn, atBtn, gdBtn }

    -- Font strings inside each button (accent colored, drop shadow)
    local wmFS = wmBtn:CreateFontString(nil, "OVERLAY")
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(wmFS, true) end
    wmFS:SetFont(FONT_PATH, 9, "")
    wmFS:SetTextColor(ar, ag, ab, 0.85)
    wmFS:SetText(EllesmereUI.L(WM_TEXT))
    wmFS:SetPoint("CENTER")

    local hmFS = hmBtn:CreateFontString(nil, "OVERLAY")
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(hmFS, true) end
    hmFS:SetFont(FONT_PATH, 9, "")
    hmFS:SetTextColor(ar, ag, ab, 0.85)
    hmFS:SetText(EllesmereUI.L(HM_TEXT))
    hmFS:SetPoint("CENTER")

    local atFS = atBtn:CreateFontString(nil, "OVERLAY")
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(atFS, true) end
    atFS:SetFont(FONT_PATH, 9, "")
    atFS:SetTextColor(ar, ag, ab, 0.85)
    atFS:SetText(EllesmereUI.L(AT_TEXT))
    atFS:SetPoint("CENTER")

    local gdFS = gdBtn:CreateFontString(nil, "OVERLAY")
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(gdFS, true) end
    gdFS:SetFont(FONT_PATH, 9, "")
    gdFS:SetTextColor(ar, ag, ab, 0.85)
    gdFS:SetText(EllesmereUI.L(GD_TEXT))
    gdFS:SetPoint("CENTER")

    -- 1px pixel-perfect divider lines between action links
    local PP = EllesmereUI and EllesmereUI.PP
    local divPx = PP and PP.mult or 1

    local div1 = labelFrame:CreateTexture(nil, "OVERLAY")
    div1:SetColorTexture(1, 1, 1, 0.25)
    div1:SetWidth(divPx)
    div1:SetHeight(10)
    if div1.SetSnapToPixelGrid then div1:SetSnapToPixelGrid(false); div1:SetTexelSnappingBias(0) end
    div1:Hide()

    local div2 = labelFrame:CreateTexture(nil, "OVERLAY")
    div2:SetColorTexture(1, 1, 1, 0.25)
    div2:SetWidth(divPx)
    div2:SetHeight(10)
    if div2.SetSnapToPixelGrid then div2:SetSnapToPixelGrid(false); div2:SetTexelSnappingBias(0) end
    div2:Hide()

    local div3 = labelFrame:CreateTexture(nil, "OVERLAY")
    div3:SetColorTexture(1, 1, 1, 0.25)
    div3:SetWidth(divPx)
    div3:SetHeight(10)
    if div3.SetSnapToPixelGrid then div3:SetSnapToPixelGrid(false); div3:SetTexelSnappingBias(0) end
    div3:Hide()

    -- Determine if this element supports resizing
    local canResize = not (elem and elem.noResize)
    -- Determine if this element can be anchored to other elements
    local canAnchorTo = not (elem and elem.noAnchorTo)

    -- Grow direction: action bars 1-8 and CDM bars (both horizontal and vertical)
    local _GROW_KEYS = {
        MainBar = true, Bar2 = true, Bar3 = true, Bar4 = true,
        Bar5 = true, Bar6 = true, Bar7 = true, Bar8 = true,
        StanceBar = true, PetBar = true,
    }
    local canGrow = _GROW_KEYS[barKey] or barKey:sub(1, 4) == "CDM_"

    -- Match-source capability: the width/height MATCH buttons may appear even when
    -- drag/manual resize is disabled (noResize), if the element opts in via
    -- allowMatchSource. (TBB tracking bars size via their own CDM sliders, so their
    -- resize inputs stay off, but they may still size-MATCH to another element.)
    local canMatchSource = canResize or (elem and elem.allowMatchSource) or false

    -- Single source of truth for which action-row link buttons are active, in
    -- left-to-right order. The layout, the hover show/hide, and the hover-box
    -- width calc all read this so they never drift apart. `fb` = fallback width.
    local function ActiveLinks()
        local t = {}
        if canMatchSource then
            t[#t + 1] = { btn = wmBtn, fs = wmFS, fb = 50 }
            t[#t + 1] = { btn = hmBtn, fs = hmFS, fb = 55 }
        end
        if canAnchorTo then
            t[#t + 1] = { btn = atBtn, fs = atFS, fb = 45 }
        end
        if canGrow then
            t[#t + 1] = { btn = gdBtn, fs = gdFS, fb = 30 }
        end
        return t
    end

    -- Layout: position action link buttons + dividers centered below name.
    -- Unified dynamic layout: lay out exactly the buttons ActiveLinks() reports,
    -- with one divider between each adjacent pair. This renders the existing
    -- cases pixel-identically and naturally handles match-buttons-without-resize.
    local function LayoutActionRow()
        local gap = 8
        local items = ActiveLinks()
        if #items == 0 then return end
        local divs = { div1, div2, div3 }
        local totalW = 0
        for i, it in ipairs(items) do
            it.w = it.fs:GetStringWidth() or it.fb
            totalW = totalW + it.w
            if i < #items then totalW = totalW + gap + 1 + gap end
        end
        local x = -totalW / 2
        for i, it in ipairs(items) do
            it.btn:SetSize(it.w + 4, 14); it.btn:ClearAllPoints()
            it.btn:SetPoint("TOP", nameFS, "BOTTOM", x + it.w / 2, -4)
            x = x + it.w
            if i < #items and divs[i] then
                divs[i]:ClearAllPoints()
                divs[i]:SetPoint("TOP", nameFS, "BOTTOM", x + gap + 0.5, -6)
                x = x + gap + 1 + gap
            end
        end
    end

    -- Anchored indicator: name label turns orange when anchored
    -- No separate font string needed
    local anchoredFS = nil
    mover._anchoredFS = nil

    -- Pick mode instruction text (shown when in pick mode, replaces all other text)
    local pickFS = labelFrame:CreateFontString(nil, "OVERLAY")
    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(pickFS, true) end
    pickFS:SetFont(FONT_PATH, 10 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
    pickFS:SetTextColor(1, 1, 1, 0.85)
    pickFS:SetPoint("CENTER", mover, "CENTER")
    pickFS:SetJustifyH("CENTER")
    pickFS:SetWordWrap(true)
    pickFS:Hide()
    mover._pickFS = pickFS

    ---------------------------------------------------------------------------
    --  Hover animation state
    --  0 = idle (name centered, action row hidden)
    --  1 = hovered (name shifted up, action row visible + faded in)
    ---------------------------------------------------------------------------
    local LABEL_Y_NORMAL  = 0
    local LABEL_Y_SHIFTED = 7
    local ANIM_DUR        = 0.15
    local hoverState      = 0
    local hoverTarget     = 0
    local isAnchored      = false
    local baseW, baseH    = 0, 0   -- real element size (set by Sync)
    local moverCX, moverCY = 0, 0  -- stored center in UIParent-TOPLEFT coords (set by Sync)
    mover._setCenterXY = function(cx, cy) moverCX = cx; moverCY = cy end
    mover._getCenterXY = function() return moverCX, moverCY end

    -- Re-anchor the mover directly to the bar frame so both share the
    -- exact same screen position with zero coordinate math (pixel-perfect).
    -- The bar's CENTER anchor is already applied synchronously by RecenterBarAnchor
    -- before this fires, so we just update mover size and re-attach to bar TOPLEFT.
    -- Deferred one frame so the bar's layout has flushed after a move/resize.
    function mover:ReanchorToBar()
        local bk = self._barKey
        local self2 = self
        C_Timer.After(0, function()
            if self2._dragging then return end
            local b = GetBarFrame(bk)
            if not b then return end
            local s = b:GetEffectiveScale()
            local uiS = UIParent:GetEffectiveScale()
            local elemScale = s / uiS
            -- Update size from bar (+ any below-frame extra, e.g. boss castbar).
            local elem = registeredElements[bk]
            local extra = (elem and elem.getBottomExtra and (elem.getBottomExtra(bk) or 0) or 0) * elemScale
            local w = (b:GetWidth() or 50) * elemScale
            local h = (b:GetHeight() or 50) * elemScale + extra
            if w > 10 then baseW = w end
            if h > 10 then baseH = h end
            self2:SetSize(baseW, baseH)
            -- Recompute moverCX/moverCY from bar's current center. Shift the
            -- stored center DOWN by half the extra so the box stays top-pinned
            -- to the frame and grows downward over the extra region.
            local bcx, bcy = b:GetCenter()
            if bcx and bcy then
                moverCX = bcx * elemScale
                moverCY = bcy * elemScale - UIParent:GetHeight() - extra * 0.5
            end
            -- Anchor mover to bar TOPLEFT for pixel-perfect overlay
            self2:ClearAllPoints()
            self2:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        end)
    end

    -- Refresh link button text/color based on active matches
    local function RefreshLinkStates()
        local wm = MatchH.GetWidthMatchInfo(barKey)
        local hm = MatchH.GetHeightMatchInfo(barKey)
        local ai = GetAnchorInfo(barKey)
        -- For linkedDimensions elements, one active match blocks the other
        local wmBlocked = elem and elem.linkedDimensions and hm ~= nil
        local hmBlocked = elem and elem.linkedDimensions and wm ~= nil
        if wm then
            wmFS:SetText(EllesmereUI.L("W Matched"))
            wmFS:SetTextColor(1, 0.7, 0.3, 0.85)
        elseif wmBlocked then
            wmFS:SetText(EllesmereUI.L("W Match"))
            wmFS:SetTextColor(ar, ag, ab, 0.35)
        else
            wmFS:SetText(EllesmereUI.L("W Match"))
            wmFS:SetTextColor(ar, ag, ab, 0.85)
        end
        if hm then
            hmFS:SetText(EllesmereUI.L("H Matched"))
            hmFS:SetTextColor(1, 0.7, 0.3, 0.85)
        elseif hmBlocked then
            hmFS:SetText(EllesmereUI.L("H Match"))
            hmFS:SetTextColor(ar, ag, ab, 0.35)
        else
            hmFS:SetText(EllesmereUI.L("H Match"))
            hmFS:SetTextColor(ar, ag, ab, 0.85)
        end
        if ai then
            atFS:SetText(EllesmereUI.L("Anchored"))
            atFS:SetTextColor(1, 0.7, 0.3, 0.85)
        else
            atFS:SetText(EllesmereUI.L("Anchor"))
            atFS:SetTextColor(ar, ag, ab, 0.85)
        end
        gdFS:SetText(EllesmereUI.L("Grow"))
        gdFS:SetTextColor(1, 0.7, 0.3, 0.85)
    end

    -- Update the name label color based on anchor state
    local function RefreshAnchoredIdle()
        local ai = GetAnchorInfo(barKey)
        isAnchored = ai ~= nil
        nameFS:SetText(EllesmereUI.L(label))
        if isAnchored then
            nameFS:SetTextColor(1, 0.7, 0.3, 0.85)
        else
            nameFS:SetTextColor(1, 1, 1, 0.75)
        end
    end

    local animFrame = CreateFrame("Frame", nil, labelFrame)

    local function ApplyHoverState(s)
        -- Name shifts up on hover to make room for action links below
        local labelShift = LABEL_Y_NORMAL + s * (LABEL_Y_SHIFTED - LABEL_Y_NORMAL)
        labelShift = labelShift + 2 - s
        -- Update the existing anchor offset instead of ClearAllPoints to avoid
        -- layout thrash that causes the label to jitter during animation.
        nameFS:SetPoint("CENTER", mover, "CENTER", 0, labelShift)
        -- Smoothly interpolate text width from constrained to unconstrained
        -- to avoid a hard snap when the animation starts.
        if baseW > 0 then
            local constrainedW = baseW
            local targetW = mover._cachedNameStrW or constrainedW
            local curTextW = constrainedW + (targetW - constrainedW) * s
            nameFS:SetWidth(curTextW)
        end

        -- Action links: show on hover. Visibility is built from the same
        -- ActiveLinks() list as the layout, so match buttons appear for
        -- allowMatchSource elements and the dividers always match the buttons.
        local links = ActiveLinks()
        local activeBtn = {}
        for _, it in ipairs(links) do activeBtn[it.btn] = true end
        local function _linkVis(btn)
            if activeBtn[btn] then
                btn:SetAlpha(s)
                if s > 0.01 then btn:Show() else btn:Hide() end
            else
                btn:Hide()
            end
        end
        _linkVis(wmBtn); _linkVis(hmBtn); _linkVis(atBtn); _linkVis(gdBtn)
        local nDivs = #links > 0 and (#links - 1) or 0
        local divsV = { div1, div2, div3 }
        for i = 1, 3 do
            if i <= nDivs then
                divsV[i]:SetAlpha(s)
                if s > 0.01 then divsV[i]:Show() else divsV[i]:Hide() end
            else
                divsV[i]:Hide()
            end
        end

        -- Cog: same show/hide as links
        if cogBtn then
            cogBtn:SetAlpha(s)
            if s > 0.01 then cogBtn:Show() else cogBtn:Hide() end
        end

        -- Animate-expand the mover only on hover (idle = raw element size)
        if baseW > 0 and baseH > 0 then
            local PAD = 5
            -- Use cached hover dimensions (computed once in ShowOverlayText)
            -- to avoid calling GetStringWidth every frame during animation.
            local hoverW = mover._cachedHoverW or baseW
            local hoverH = mover._cachedHoverH or baseH
            local curW = baseW + (hoverW - baseW) * s
            local curH = baseH + (hoverH - baseH) * s
            -- Expand symmetrically from the mover's stored center (set by Sync).
            -- This avoids reading GetLeft/GetTop from the bar frame, which can
            -- shift after a resize and cause the mover to teleport.
            local hasCenterXY = (moverCX ~= 0 or moverCY ~= 0)
            if hasCenterXY then
                local tx = moverCX - curW * 0.5
                local ty = moverCY + curH * 0.5
                mover:ClearAllPoints()
                mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", tx, ty)
            else
                -- Fallback: Sync hasn't run yet, read from bar frame
                local bk2 = mover._barKey
                local b2 = GetBarFrame(bk2)
                if b2 then
                    local s2 = b2:GetEffectiveScale()
                    local uiS2 = UIParent:GetEffectiveScale()
                    local bL2 = b2:GetLeft()
                    local bT2 = b2:GetTop()
                    if bL2 and bT2 then
                        local tx = bL2 * s2 / uiS2 - (curW - baseW) * 0.5
                        local ty = bT2 * s2 / uiS2 - UIParent:GetHeight() + (curH - baseH) * 0.5
                        mover:ClearAllPoints()
                        mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", tx, ty)
                    end
                end
            end
            mover:SetSize(curW, curH)
        end
    end

    local function AnimateHoverTo(target)
        if target == hoverTarget and not animFrame:GetScript("OnUpdate")
           and math.abs(hoverState - target) < 0.01 then return end
        hoverTarget = target
        animFrame:SetScript("OnUpdate", function(self, dt)
            local dir = hoverTarget > hoverState and 1 or -1
            hoverState = hoverState + dir * (dt / ANIM_DUR)
            if (dir == 1 and hoverState >= hoverTarget) or (dir == -1 and hoverState <= hoverTarget) then
                hoverState = hoverTarget
                self:SetScript("OnUpdate", nil)
                -- Snap back to bar anchor when fully collapsed
                if hoverState == 0 and mover.ReanchorToBar then
                    mover:ReanchorToBar()
                end
                -- Show coordinates when fully expanded
                if hoverState == 1 and mover._coordFS then
                    if mover.UpdateCoordText then mover:UpdateCoordText() end
                end
            end
            ApplyHoverState(hoverState)
        end)
    end

    -- Show/hide overlay text helpers
    local function ShowOverlayText()
        mover._hoverConfirmed = true
        if darkOverlaysEnabled then
            nameFS:SetAlpha(1); nameFS:Show()
        end
        RefreshAnchoredIdle()
        -- Cache hover dimensions once so ApplyHoverState avoids per-frame GetStringWidth
        if baseW > 0 and baseH > 0 then
            local PAD = 5
            local nameW = nameFS:GetStringWidth() or 0
            local nameH = nameFS:GetStringHeight() or 10
            local rowW = 0
            do
                local links = ActiveLinks()
                local gap = 8
                for i, it in ipairs(links) do
                    rowW = rowW + (it.fs:GetStringWidth() or it.fb)
                    if i < #links then rowW = rowW + gap + 1 + gap end
                end
            end
            local contentW = math.max(nameW, rowW)
            local contentH = nameH + 4 + 14
            mover._cachedHoverW = math.max(baseW, contentW + PAD * 2 + 6)
            mover._cachedHoverH = math.max(baseH, contentH + PAD * 2 + 2)
        end
        -- Cache unconstrained name width for smooth text width interpolation
        local nsw = nameFS:GetStringWidth() or baseW
        mover._cachedNameStrW = math.max(nsw + 4, baseW)
        -- Skip RefreshLinkStates if a link button is currently hovered (would reset its white color)
        local linkHovered = false
        if mover._linkBtns then
            for _, b in ipairs(mover._linkBtns) do
                if b:IsMouseOver() then linkHovered = true; break end
            end
        end
        if not linkHovered then RefreshLinkStates() end
        LayoutActionRow()
        AnimateHoverTo(1)
        pickFS:Hide()
    end

    local function HideOverlayText()
        mover._hoverConfirmed = false
        -- Hide coordinates when collapsing (unless coords-always-on)
        if mover._coordFS and not coordsEnabled then mover._coordFS:Hide() end
        AnimateHoverTo(0)
    end

    local function ShowPickText(text)
        wmBtn:Hide(); hmBtn:Hide(); atBtn:Hide(); gdBtn:Hide()
        div1:Hide(); div2:Hide(); div3:Hide()
        hoverState = 0; hoverTarget = 0
        animFrame:SetScript("OnUpdate", nil)
        nameFS:ClearAllPoints()
        nameFS:SetPoint("CENTER", mover, "CENTER", 0, LABEL_Y_NORMAL)
        nameFS:SetAlpha(0)
        pickFS:SetText(EllesmereUI.L(text))
        pickFS:Show()
    end

    local function HidePickText()
        pickFS:Hide()
        if darkOverlaysEnabled then
            nameFS:SetAlpha(1)
        end
    end

    mover._showOverlayText = ShowOverlayText
    mover._hideOverlayText = HideOverlayText
    mover._showPickText = ShowPickText
    mover._hidePickText = HidePickText

    -- Snap-collapse: instantly reset hover state without animation.
    -- Used by DoClose to guarantee no mover is stuck expanded on re-enter.
    mover._forceCollapse = function()
        hoverState = 0
        hoverTarget = 0
        mover._hoverConfirmed = false
        if mover._coordFS and not coordsEnabled then mover._coordFS:Hide() end
        animFrame:SetScript("OnUpdate", nil)
        ApplyHoverState(0)
        if mover.ReanchorToBar then mover:ReanchorToBar() end
    end

    -- Refresh the anchored text (called after anchor changes)
    function mover:RefreshAnchoredText()
        RefreshAnchoredIdle()
        RefreshLinkStates()
        -- If not hovered, apply idle state to show/hide anchored text
        if not self:IsMouseOver() then
            ApplyHoverState(hoverState)
        end
    end

    -- Hover effects for action buttons (brighten to white on hover, keep mover highlighted)
    local function BtnEnter(btn, fs, matchType)
        EllesmereUI.HideWidgetTooltip()
        -- Check if this button is blocked by linkedDimensions
        local isBlocked = false
        if elem and elem.linkedDimensions then
            if matchType == "width" and MatchH.GetHeightMatchInfo(barKey) ~= nil and MatchH.GetWidthMatchInfo(barKey) == nil then
                isBlocked = true
            elseif matchType == "height" and MatchH.GetWidthMatchInfo(barKey) ~= nil and MatchH.GetHeightMatchInfo(barKey) == nil then
                isBlocked = true
            end
        end
        if isBlocked then
            EllesmereUI.ShowWidgetTooltip(btn, "This element doesn't support both Height and Width matching")
            return
        end
        fs:SetTextColor(1, 1, 1, 1)
        mover:SetFrameLevel(mover._raisedLevel + 100)
        mover._brd:SetColor(1, 1, 1, 0.9)
        -- Show tooltip for active matches
        local tipText
        if matchType == "width" then
            local target = MatchH.GetWidthMatchInfo(barKey)
            if target then
                tipText = GetBarLabel(target) or target
            end
        elseif matchType == "height" then
            local target = MatchH.GetHeightMatchInfo(barKey)
            if target then
                tipText = GetBarLabel(target) or target
            end
        elseif matchType == "anchor" then
            local info = GetAnchorInfo(barKey)
            if info then
                tipText = GetBarLabel(info.target) or info.target
            end
        elseif matchType == "grow" then
            local gd = GetBarGrowDir(barKey)
            if gd then
                tipText = "Grow " .. gd:sub(1,1) .. gd:sub(2):lower()
            end
        end
        if tipText then
            EllesmereUI.ShowWidgetTooltip(btn, tipText)
        end
    end
    local function BtnLeave(btn, fs, matchType)
        EllesmereUI.HideWidgetTooltip()
        -- Restore correct color based on active/blocked state
        local isActive = false
        local isBlocked = false
        if matchType == "width" then
            isActive = MatchH.GetWidthMatchInfo(barKey) ~= nil
            isBlocked = elem and elem.linkedDimensions and not isActive and MatchH.GetHeightMatchInfo(barKey) ~= nil
        elseif matchType == "height" then
            isActive = MatchH.GetHeightMatchInfo(barKey) ~= nil
            isBlocked = elem and elem.linkedDimensions and not isActive and MatchH.GetWidthMatchInfo(barKey) ~= nil
        elseif matchType == "anchor" then
            isActive = GetAnchorInfo(barKey) ~= nil
        elseif matchType == "grow" then
            isActive = true
        end
        if isActive then
            fs:SetTextColor(1, 0.7, 0.3, 0.85)
        elseif isBlocked then
            fs:SetTextColor(ar, ag, ab, 0.35)
        else
            fs:SetTextColor(ar, ag, ab, 0.85)
        end
        -- Restore frame level/border only -- mover OnLeave owns the collapse
        C_Timer.After(0.05, function()
            if not mover:IsMouseOver() then
                local overChild = mover._cogBtn and mover._cogBtn:IsMouseOver()
                if not overChild and mover._linkBtns then
                    for _, b in ipairs(mover._linkBtns) do
                        if b:IsMouseOver() then overChild = true; break end
                    end
                end
                if not overChild then
                    mover:SetFrameLevel(mover._baseLevel)
                    if mover._cogBtn then mover._cogBtn:SetFrameLevel(mover._baseLevel + 10) end
                    mover._brd:SetColor(ar, ag, ab, 0.6)
                end
            end
        end)
    end
    wmBtn:SetScript("OnEnter", function(self) BtnEnter(self, wmFS, "width") end)
    wmBtn:SetScript("OnLeave", function(self) BtnLeave(self, wmFS, "width") end)
    hmBtn:SetScript("OnEnter", function(self) BtnEnter(self, hmFS, "height") end)
    hmBtn:SetScript("OnLeave", function(self) BtnLeave(self, hmFS, "height") end)
    atBtn:SetScript("OnEnter", function(self) BtnEnter(self, atFS, "anchor") end)
    atBtn:SetScript("OnLeave", function(self) BtnLeave(self, atFS, "anchor") end)

    -- Forward drag from link buttons to the mover using OnMouseDown/Up instead of
    -- WoW's drag system. RegisterForDrag fires OnDragStop as soon as the button
    -- moves (which happens when the hover row collapses on drag start), breaking
    -- the drag immediately. OnMouseDown/Up bypass that entirely.
    --
    -- To avoid collapsing the action row on a plain click, we defer drag start
    -- until the cursor has moved at least 3px from the mousedown position.
    local linkDragPending = false
    local linkDragStartX, linkDragStartY = 0, 0

    local function LinkMouseDown(btn, button)
        if button ~= "LeftButton" then return end
        local sc = UIParent:GetEffectiveScale()
        linkDragStartX, linkDragStartY = GetCursorPosition()
        linkDragStartX = linkDragStartX / sc
        linkDragStartY = linkDragStartY / sc
        linkDragPending = true
        -- Poll for movement threshold before committing to drag
        mover:SetScript("OnUpdate", function(s)
            if not linkDragPending then return end
            local sc2 = UIParent:GetEffectiveScale()
            local mx, my = GetCursorPosition()
            mx = mx / sc2; my = my / sc2
            if abs(mx - linkDragStartX) > 1 or abs(my - linkDragStartY) > 1 then
                linkDragPending = false
                -- Now fire the real drag start
                local script = mover:GetScript("OnDragStart")
                if script then script(mover) end
            end
        end)
    end
    local function LinkMouseUp(btn, button)
        if button ~= "LeftButton" then return end
        linkDragPending = false
        if mover._dragging then
            local script = mover:GetScript("OnDragStop")
            if script then script(mover) end
        else
            -- No drag committed — clear the pending OnUpdate
            mover:SetScript("OnUpdate", nil)
        end
    end
    wmBtn:SetScript("OnMouseDown", LinkMouseDown)
    wmBtn:SetScript("OnMouseUp",   LinkMouseUp)
    hmBtn:SetScript("OnMouseDown", LinkMouseDown)
    hmBtn:SetScript("OnMouseUp",   LinkMouseUp)
    atBtn:SetScript("OnMouseDown", LinkMouseDown)
    atBtn:SetScript("OnMouseUp",   LinkMouseUp)
    -- Also catch mouse release on the mover itself during a link-initiated drag.
    -- When the user drags far from the link button, the release happens over the
    -- mover (or nowhere), so the link button's OnMouseUp never fires.
    mover:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            _mouseHeld = false
            if linkDragPending or self._dragging then
                LinkMouseUp(self, button)
            end
        end
    end)

    -- Click handlers for Width Match / Height Match / Anchor To
    -- Toggle: if already matched, clear it; otherwise enter pick mode
    wmBtn:SetScript("OnClick", function()
        EllesmereUI.HideWidgetTooltip()
        -- Block if linkedDimensions and height match is already active
        if elem and elem.linkedDimensions and MatchH.GetHeightMatchInfo(barKey) ~= nil and MatchH.GetWidthMatchInfo(barKey) == nil then
            return
        end
        if MatchH.GetWidthMatchInfo(barKey) then
            MatchH.ClearWidthMatch(barKey)
            hasChanges = true
            RefreshLinkStates()
            LayoutActionRow()
            return
        end
        CancelPickMode()
        pickMode = "widthMatch"
        pickModeMover = mover
        ShowPickText("Click any element\nto match its width")
        FadeOverlayForSelectElement(true)
    end)

    hmBtn:SetScript("OnClick", function()
        EllesmereUI.HideWidgetTooltip()
        -- Block if linkedDimensions and width match is already active
        if elem and elem.linkedDimensions and MatchH.GetWidthMatchInfo(barKey) ~= nil and MatchH.GetHeightMatchInfo(barKey) == nil then
            return
        end
        if MatchH.GetHeightMatchInfo(barKey) then
            MatchH.ClearHeightMatch(barKey)
            hasChanges = true
            RefreshLinkStates()
            LayoutActionRow()
            return
        end
        CancelPickMode()
        pickMode = "heightMatch"
        pickModeMover = mover
        ShowPickText("Click any element\nto match its height")
        FadeOverlayForSelectElement(true)
    end)

    atBtn:SetScript("OnClick", function()
        EllesmereUI.HideWidgetTooltip()
        if GetAnchorInfo(barKey) then
            ClearAnchorInfo(barKey)
            -- Capture current screen position so Save & Exit persists it.
            -- Without this, the old cdmBarPositions (from when anchored)
            -- would be used on /reload, snapping the bar to the wrong spot.
            local bar = GetBarFrame(barKey)
            if bar then
                local pt, _, rpt, bx, by = bar:GetPoint(1)
                if pt then
                    pendingPositions[barKey] = {
                        point = pt, relPoint = rpt, x = bx, y = by,
                    }
                end
            end
            hasChanges = true
            RefreshAnchoredIdle()
            RefreshLinkStates()
            LayoutActionRow()
            if movers[barKey] and movers[barKey].RefreshAnchoredText then
                movers[barKey]:RefreshAnchoredText()
            end
            return
        end
        CancelPickMode()
        pickMode = "anchorTo"
        pickModeMover = mover
        ShowPickText("Click any element\nto anchor to it")
        FadeOverlayForSelectElement(true)
    end)

    gdBtn:SetScript("OnClick", function()
        EllesmereUI.HideWidgetTooltip()
        -- Build and show the grow direction dropdown
        if not growDropdownFrame then
            growDropdownFrame = CreateFrame("Frame", nil, unlockFrame)
            growDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            growDropdownFrame:SetFrameLevel(260)
            growDropdownFrame:SetClampedToScreen(true)
            growDropdownFrame:EnableMouse(true)
        end
        if not growDropdownCatcher then
            growDropdownCatcher = CreateFrame("Button", nil, unlockFrame)
            growDropdownCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            growDropdownCatcher:SetFrameLevel(259)
            growDropdownCatcher:SetAllPoints(UIParent)
            growDropdownCatcher:RegisterForClicks("AnyUp")
            growDropdownCatcher:SetScript("OnClick", function()
                growDropdownFrame:Hide()
                growDropdownCatcher:Hide()
            end)
        end
        -- Rebuild dropdown content
        for _, child in ipairs({growDropdownFrame:GetChildren()}) do child:Hide(); child:SetParent(nil) end
        for _, tex in ipairs({growDropdownFrame:GetRegions()}) do if tex.Hide then tex:Hide() end end

        local DD_ITEM_H = 24
        local DD_WIDTH = 160
        growDropdownFrame:SetSize(DD_WIDTH, 10)
        growDropdownFrame:ClearAllPoints()
        local scale = UIParent:GetEffectiveScale()
        local curX, curY = GetCursorPosition()
        curX = curX / scale
        curY = curY / scale - UIParent:GetHeight()
        growDropdownFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", curX, curY)

        local ddBg = growDropdownFrame:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints()
        ddBg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
        EllesmereUI.MakeBorder(growDropdownFrame, 1, 1, 1, 0.20)

        local ddY = -4
        local titleFS = growDropdownFrame:CreateFontString(nil, "OVERLAY")
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(titleFS, true) end
        titleFS:SetFont(FONT_PATH, 10, "")
        titleFS:SetTextColor(1, 1, 1, 0.40)
        titleFS:SetJustifyH("LEFT")
        titleFS:SetPoint("TOPLEFT", growDropdownFrame, "TOPLEFT", 10, ddY - 4)
        titleFS:SetText(EllesmereUI.L("Grow Direction"))
        ddY = ddY - 18
        local titleDiv = growDropdownFrame:CreateTexture(nil, "ARTWORK")
        titleDiv:SetHeight(1)
        titleDiv:SetColorTexture(1, 1, 1, 0.10)
        titleDiv:SetPoint("TOPLEFT", growDropdownFrame, "TOPLEFT", 1, ddY - 2)
        titleDiv:SetPoint("TOPRIGHT", growDropdownFrame, "TOPRIGHT", -1, ddY - 2)
        ddY = ddY - 5

        -- Read orientation dynamically (not from closure) so the dropdown
        -- shows the correct options if orientation changed after mover creation.
        local isVert = false
        if barKey:sub(1, 4) == "CDM_" then
            local cdm3 = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
            local cb3 = cdm3 and cdm3.db and cdm3.db.profile and cdm3.db.profile.cdmBars
            if cb3 and cb3.bars then
                for _, b3 in ipairs(cb3.bars) do
                    if b3.key == barKey:sub(5) then isVert = b3.verticalOrientation == true; break end
                end
            end
        else
            local eab3 = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
            local s3 = eab3 and eab3.db and eab3.db.profile and eab3.db.profile.bars and eab3.db.profile.bars[barKey]
            if s3 then isVert = (s3.orientation == "vertical") end
        end
        local growDirs = {
            { label = "Grow Centered", val = "CENTER" },
        }
        if isVert then
            growDirs[#growDirs + 1] = { label = "Grow Up",   val = "UP"   }
            growDirs[#growDirs + 1] = { label = "Grow Down", val = "DOWN" }
        else
            growDirs[#growDirs + 1] = { label = "Grow Left",  val = "LEFT"  }
            growDirs[#growDirs + 1] = { label = "Grow Right", val = "RIGHT" }
        end
        -- Read actual grow direction directly (GetBarGrowDir filters defaults)
        local currentVal = "CENTER"
        if barKey:sub(1, 4) == "CDM_" then
            local cdm4 = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
            local cb4 = cdm4 and cdm4.db and cdm4.db.profile and cdm4.db.profile.cdmBars
            if cb4 and cb4.bars then
                for _, b4 in ipairs(cb4.bars) do
                    if b4.key == barKey:sub(5) then currentVal = b4.growDirection or "CENTER"; break end
                end
            end
        else
            local eab4 = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
            local s4 = eab4 and eab4.db and eab4.db.profile and eab4.db.profile.bars
                       and eab4.db.profile.bars[barKey]
            if s4 then currentVal = (s4.growDirection or "up"):upper() end
        end

        for _, entry in ipairs(growDirs) do
            local isDisabled = false
            local isCurrent = (entry.val == currentVal)

            local item = CreateFrame("Button", nil, growDropdownFrame)
            item:SetHeight(DD_ITEM_H)
            item:SetPoint("TOPLEFT", growDropdownFrame, "TOPLEFT", 1, ddY)
            item:SetPoint("TOPRIGHT", growDropdownFrame, "TOPRIGHT", -1, ddY)
            item:SetFrameLevel(growDropdownFrame:GetFrameLevel() + 2)
            item:RegisterForClicks("AnyUp")
            local hl = item:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0)
            local lbl = item:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(lbl, true) end
            lbl:SetFont(FONT_PATH, 11, "")
            lbl:SetJustifyH("LEFT")
            lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
            lbl:SetText(EllesmereUI.L(entry.label))
            if isDisabled then
                lbl:SetTextColor(0.4, 0.4, 0.4, 0.5)
                local tipText = "Deselect a grow direction to return to centered"
                item:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(item, tipText)
                end)
                item:SetScript("OnLeave", function()
                    EllesmereUI.HideWidgetTooltip()
                end)
            else
                local baseR, baseG, baseB, baseA = isCurrent and 1 or 0.75, isCurrent and 0.7 or 0.75, isCurrent and 0.3 or 0.75, isCurrent and 0.9 or 0.9
                lbl:SetTextColor(baseR, baseG, baseB, baseA)
                item:SetScript("OnEnter", function()
                    hl:SetColorTexture(1, 1, 1, 0.08)
                    lbl:SetTextColor(1, 1, 1, 1)
                end)
                item:SetScript("OnLeave", function()
                    hl:SetColorTexture(1, 1, 1, 0)
                    lbl:SetTextColor(baseR, baseG, baseB, baseA)
                end)
                local sideVal = entry.val
                item:SetScript("OnClick", function()
                    growDropdownFrame:Hide()
                    growDropdownCatcher:Hide()

                    -- If already on this direction, just close the popup
                    if sideVal == currentVal then return end

                    hasChanges = true

                    -- Capture the bar's visual center before changing grow
                    local barFrame = GetBarFrame(barKey)
                    local preCX, preCY
                    if barFrame then
                        preCX, preCY = barFrame:GetCenter()
                    end

                    -- Write to the bar's actual settings DB and rebuild layout
                    if barKey:sub(1, 4) == "CDM_" then
                        local rawKey = barKey:sub(5)
                        local cdm = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
                        local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
                        if cdmBars and cdmBars.bars then
                            for _, bar in ipairs(cdmBars.bars) do
                                if bar.key == rawKey then
                                    bar.growDirection = sideVal
                                    break
                                end
                            end
                        end
                        if EllesmereUI.LayoutCDMBar then
                            EllesmereUI.LayoutCDMBar(rawKey)
                        end
                        EllesmereUI.RecenterBarAnchor(barKey)
                    else
                        local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
                        if eab and eab.SetGrowDirectionForBar then
                            eab:SetGrowDirectionForBar(barKey, sideVal)
                        end
                    end

                    -- Restore the bar's visual center so it doesn't jump,
                    -- then re-anchor based on the new growth direction.
                    if barFrame and preCX and preCY then
                        local postCX, postCY = barFrame:GetCenter()
                        if postCX and postCY then
                            local dx = preCX - postCX
                            local dy = preCY - postCY
                            if math.abs(dx) > 0.5 or math.abs(dy) > 0.5 then
                                local pt, relTo, relPt, offX, offY = barFrame:GetPoint(1)
                                if pt then
                                    barFrame:ClearAllPoints()
                                    barFrame:SetPoint(pt, relTo, relPt, offX + dx, offY + dy)
                                end
                            end
                        end
                    end
                    EllesmereUI.RecenterBarAnchor(barKey)
                    -- Store in pending (committed on Save & Exit)
                    if barFrame then
                        local pt2, relTo2, relPt2, offX2, offY2 = barFrame:GetPoint(1)
                        if pt2 then
                            pendingPositions[barKey] = {
                                point = pt2, relPoint = relPt2, x = offX2, y = offY2,
                            }
                            hasChanges = true
                        end
                    end

                    -- Sync the mover to the bar's new position
                    if movers[barKey] and movers[barKey].Sync then
                        movers[barKey]:Sync()
                    end

                    RefreshLinkStates()
                end)
            end
            ddY = ddY - DD_ITEM_H
        end

        growDropdownFrame:SetHeight(-ddY + 4)
        growDropdownFrame:Show()
        growDropdownCatcher:Show()
    end)
    gdBtn:SetScript("OnEnter", function(self) BtnEnter(self, gdFS, "grow") end)
    gdBtn:SetScript("OnLeave", function(self) BtnLeave(self, gdFS, "grow") end)

    -- Helper: update coordinate readout from mover's current position
    function mover:UpdateCoordText()
        local fs = self._coordFS
        if not fs then return end
        local bk = self._barKey
        local PPi = EllesmereUI and EllesmereUI.PP
        local toPx = (PPi and PPi.ToPixels) or round
        -- Derive from the bar's LIVE geometry using the exact same formula and
        -- physical-pixel units as the cog X/Y boxes, so the overlay always agrees
        -- with the cog and updates immediately (no waiting for a commit).
        local b = GetBarFrame(bk)
        if b then
            local bL, bR = b:GetLeft(), b:GetRight()
            local bT, bB = b:GetTop(), b:GetBottom()
            if bL and bR and bT and bB then
                local ratio = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
                local sw = UIParent:GetWidth()
                local sh = UIParent:GetHeight()
                fs:SetText(format("%.0f, %.0f",
                    toPx(((bL + bR) * 0.5 * ratio) - sw * 0.5),
                    toPx(((bT + bB) * 0.5 * ratio) - sh * 0.5)))
                fs:Show()
                return
            end
        end
        -- Fallback (frameless elements): saved CENTER position, same pixel units.
        local elem = registeredElements[bk]
        local pos = elem and elem.loadPosition and elem.loadPosition(bk)
        if not pos then
            pos = LoadBarPosition(bk)
        end
        if pos and pos.x and pos.y then
            fs:SetText(format("%.0f, %.0f", toPx(pos.x), toPx(pos.y)))
            fs:Show()
            return
        end
        -- Last resort: derive from mover bounds.
        local l, r, t, b2 = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
        if not l or not t then fs:Hide(); return end
        local screenW = UIParent:GetWidth()
        local screenH = UIParent:GetHeight()
        fs:SetText(format("%.0f, %.0f",
            toPx(((l + r) * 0.5) - screenW * 0.5),
            toPx(((t + b2) * 0.5) - screenH * 0.5)))
        fs:Show()
    end

    mover._barKey = barKey
    mover:SetAlpha(darkOverlaysEnabled and 1 or MOVER_ALPHA)

    -- Initialize anchored text and link states, then apply idle state
    RefreshAnchoredIdle()
    RefreshLinkStates()
    ApplyHoverState(0)

    -- Sync size/position to the real bar (or registered element)
    function mover:Sync()
        local bk = self._barKey
        local b = GetBarFrame(bk)
        local elem = registeredElements[bk]

        -- Stale / intentionally-hidden registrations (e.g. a deleted CDM tracking
        -- bar whose TBB_<idx> element is never unregistered, or a grouped non-anchor
        -- bar) must NOT be shown. Mirror the CreateMover guard so the blanket
        -- `for _, m in pairs(movers) do m:Sync() end` loops (open fade-in, combat
        -- resume) can't re-show a mover that CreateMover intentionally hid. Action
        -- bars resolve elem == nil (they live in BAR_LOOKUP), so this is a no-op
        -- for them; isHidden is read live, so an un-hidden element still syncs.
        if elem and ((elem.isHidden and elem.isHidden())
                  or (elem.isAnchored and elem.isAnchored())) then
            self:Hide()
            return
        end

        -- For registered elements without a live frame, use getSize + loadPosition
        if not b and elem then
            local w, h = 100, 30
            local centerYOff = 0
            if elem.getSize then
                local gw, gh, gyOff = elem.getSize(bk)
                w, h = gw, gh
                centerYOff = gyOff or 0
            end
            if w < 10 then w = 100 end
            if h < 10 then h = 30 end
            baseW, baseH = w, h
            self:SetSize(w, h)
            if self._label then self._label:SetWidth(w * 0.95) end
            local pos = elem.loadPosition and elem.loadPosition(bk)
            if pos then
                self:ClearAllPoints()
                self:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, (pos.y or 0) + centerYOff)
            else
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "CENTER", 0, centerYOff)
            end
            self:Show()
            ApplyHoverState(hoverState)
            return
        end

        if not b then self:Hide(); return end
        -- Show mover even for hidden bars (mouseover/alwaysHidden) so user can reposition
        -- Only skip if the bar frame truly doesn't exist
        local s = b:GetEffectiveScale()
        local uiS = UIParent:GetEffectiveScale()
        local w, h
        local elemScale = s / uiS
        -- Read size directly from the bar frame. Since the mover is anchored
        -- to the bar, we need the size in the mover's coordinate space.
        -- elemScale converts from bar space to UIParent (mover parent) space.
        w = (b:GetWidth() or 50) * elemScale
        h = (b:GetHeight() or 50) * elemScale
        -- For action bars, compute visual size from button grid (accounts for
        -- shape overrides, padding, and per-button scale)
        -- Only use this as a fallback when the frame has no size yet (first load).
        if w < 10 or h < 10 then
            local abW, abH = GetActionBarVisualSize(bk)
            if abW and abH then
                w, h = abW, abH
            end
        end
        local isTinyAnchor = (w < 10)
        local centerYOff = 0
        if isTinyAnchor then
            -- Frame exists but has no size yet — use getSize fallback
            if elem and elem.getSize then
                local gw, gh, gyOff = elem.getSize(bk)
                w, h = gw, gh
                centerYOff = gyOff or 0
            end
        end
        -- Extend the overlay downward to wrap an element's below-frame extra
        -- (e.g. the boss castbar). Inflating h here flows into SetSize and the
        -- center math below, keeping the top pinned and growing the box down.
        if elem and elem.getBottomExtra then
            h = h + (elem.getBottomExtra(bk) or 0) * elemScale
        end
        baseW, baseH = w, h
        self:SetSize(w, h)
        if self._label then self._label:SetWidth(w * 0.95) end

        -- Position: convert bar's screen position to UIParent-relative
        -- Center the mover on the bar's visual center for pixel-perfect alignment.
        local bL = b:GetLeft()
        local bT = b:GetTop()
        if bL and bT then
            local PP = EllesmereUI and EllesmereUI.PP
            if isTinyAnchor and elem then
                -- Dynamic bar (1x1 when empty): anchor is CENTER-positioned.
                -- Compute TOPLEFT from GetCenter() to avoid layout-flush timing
                -- issues where GetLeft()/GetTop() still reflect the old 1x1 size.
                local cx, cy
                local bCX, bCY = b:GetCenter()
                if bCX and bCY then
                    cx = bCX * s / uiS - w * 0.5
                    cy = bCY * s / uiS - UIParent:GetHeight() + h * 0.5 + centerYOff
                elseif bL and bT then
                    cx = bL * s / uiS
                    cy = bT * s / uiS - UIParent:GetHeight()
                else
                    -- No screen position yet -- fall back to saved pos
                    local pos = elem.loadPosition and elem.loadPosition(bk)
                    if pos and pos.point == "CENTER" then
                        local uiW = UIParent:GetWidth()
                        local uiH = UIParent:GetHeight()
                        cx = uiW * 0.5 + (pos.x or 0) - w * 0.5
                        cy = -(uiH * 0.5) + (pos.y or 0) + h * 0.5
                    else
                        cx = 0; cy = -UIParent:GetHeight() * 0.5
                    end
                end
                if PP then cx = PP.Scale(cx); cy = PP.Scale(cy) end
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cx, cy)
                moverCX, moverCY = cx + w * 0.5, cy - h * 0.5
            else
                -- Anchor mover directly to the bar frame so both share the
                -- exact same screen position with zero coordinate math.
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
                -- Compute moverCX/moverCY for snap/drag logic
                local cx = bL * elemScale
                local cy = bT * elemScale - UIParent:GetHeight()
                moverCX, moverCY = cx + w * 0.5, cy - h * 0.5
            end
        else
            -- Bar has no position yet (not shown), place at center
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            moverCX, moverCY = 0, -UIParent:GetHeight() * 0.5
        end
        self:Show()
        -- Re-apply hover state so mover size reflects current animation state
        ApplyHoverState(hoverState)
    end

    -- Lightweight size-only sync: updates baseW/baseH and re-applies hover state
    -- without repositioning the mover. Used after width/height match changes.
    function mover:SyncSize()
        local bk = self._barKey
        local elem = registeredElements[bk]
        if elem and elem.getSize then
            local gw, gh = elem.getSize(bk)
            -- Use the raw value from getSize without rounding. The layout
            -- function (LayoutCDMBar, LayoutBar, etc.) already snapped
            -- dimensions to the physical pixel grid. Re-rounding to the
            -- nearest integer shifts values off the pixel grid when
            -- PP.mult != 1.0 (e.g. 214.4 -> 214 instead of staying 214.4
            -- which is exactly 402 physical pixels at mult=0.533).
            if gw and gw > 0 then baseW = gw end
            if gh and gh > 0 then baseH = gh end
        else
            local b = GetBarFrame(bk)
            if b then
                local s = b:GetEffectiveScale()
                local uiS = UIParent:GetEffectiveScale()
                baseW = (b:GetWidth() or baseW) * s / uiS
                baseH = (b:GetHeight() or baseH) * s / uiS
            end
        end
        -- moverCX/moverCY are already updated by RecenterBarAnchor (called before
        -- SyncSize). Do NOT recompute from GetLeft/GetTop here -- the mover may
        -- still be anchored to the bar's old TOPLEFT position at this point, which
        -- would produce a wrong center and cause a one-frame visual jump.
        ApplyHoverState(hoverState)
        -- Re-anchor to bar for pixel-perfect alignment after size change
        self:ReanchorToBar()
    end

    -- Drag handlers: manual cursor-based positioning for live snap + live bar movement
    mover:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        -- Anchored bars can be dragged -- the offset from parent is updated on drop
        SelectMover(self)
        self:SetAlpha(darkOverlaysEnabled and 1 or MOVER_DRAG)
        self._dragging = true
        self._hoverPending = false  -- cancel pending expand animation
        self._shiftAxis = nil  -- nil = not locked, "X" or "Y" once determined
        -- Cache centerYOff for tiny-anchor elements (used in OnUpdate and OnDragStop)
        local elem = registeredElements[self._barKey]
        if elem and elem.getSize then
            local _, _, gyOff = elem.getSize(self._barKey)
            self._dragCenterYOff = gyOff or 0
        else
            self._dragCenterYOff = 0
        end
        -- Snap links away instantly during drag (no animation -- it fights with drag positioning)
        hoverState = 0
        hoverTarget = 0
        animFrame:SetScript("OnUpdate", nil)
        ApplyHoverState(0)

        -- Record offset from cursor to mover center at drag start
        -- Use stored moverCX/moverCY (base-size center) so expanding/collapsing
        -- hover state does not corrupt the offset when dragging from a link button
        local scale = UIParent:GetEffectiveScale()
        local curX, curY = GetCursorPosition()
        curX = curX / scale
        curY = curY / scale
        local cx = (moverCX ~= 0 or moverCY ~= 0) and moverCX or (self:GetLeft() + self:GetRight()) / 2
        local cy = (moverCX ~= 0 or moverCY ~= 0) and moverCY or (self:GetTop() + self:GetBottom()) / 2 - UIParent:GetHeight()
        cy = cy + UIParent:GetHeight()  -- convert back to screen-space Y for drag math
        self._dragOffX = cx - curX
        self._dragOffY = cy - curY
        self._dragStartCX = cx
        self._dragStartCY = cy

        -- Snap mover to cursor immediately so there's no one-frame lag
        local halfW0 = self:GetWidth() / 2
        local halfH0 = self:GetHeight() / 2
        self._dragHalfW = halfW0
        self._dragHalfH = halfH0
        local snap0X, snap0Y = SnapPosition(self._barKey, cx, cy, halfW0, halfH0)
        local bar0 = GetBarFrame(self._barKey)
        if bar0 and not InCombatLockdown() then
            local uiS0 = UIParent:GetEffectiveScale()
            local bS0 = bar0:GetEffectiveScale()
            local ratio0 = uiS0 / bS0
            local barHW0 = (bar0:GetWidth() or 0) * 0.5
            local barHH0 = (bar0:GetHeight() or 0) * 0.5
            local barX0 = snap0X * ratio0 - barHW0
            local barY0 = (snap0Y - UIParent:GetHeight() - (self._dragCenterYOff or 0)) * ratio0 + barHH0
            local PPd = EllesmereUI and EllesmereUI.PP
            if PPd and PPd.SnapForES then
                local lockX, lockY = EllesmereUI._snapAxisLocked()
                if not lockX then barX0 = PPd.SnapForES(barX0, bS0) end
                if not lockY then barY0 = PPd.SnapForES(barY0, bS0) end
            end
            pcall(function()
                bar0:ClearAllPoints()
                bar0:SetPoint("TOPLEFT", UIParent, "TOPLEFT", barX0, barY0)
            end)
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", bar0, "TOPLEFT", 0, 0)
        else
            local f0X = snap0X - halfW0
            local f0Y = snap0Y + halfH0 - UIParent:GetHeight()
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", f0X, f0Y)
        end

        -- OnUpdate: move mover + real bar to cursor position with snap
        self:SetScript("OnUpdate", function(s)
            local sc = UIParent:GetEffectiveScale()
            local mx, my = GetCursorPosition()
            mx = mx / sc
            my = my / sc

            -- Raw center = cursor + offset
            local rawCX = mx + s._dragOffX
            local rawCY = my + s._dragOffY

            -- Shift-axis-lock: constrain to one axis based on initial drag direction
            if IsShiftKeyDown() then
                if not s._shiftAxis then
                    local adx = abs(rawCX - s._dragStartCX)
                    local ady = abs(rawCY - s._dragStartCY)
                    -- Determine axis once movement exceeds 3px threshold
                    if adx > 3 or ady > 3 then
                        s._shiftAxis = (adx >= ady) and "X" or "Y"
                    end
                end
                if s._shiftAxis == "X" then
                    rawCY = s._dragStartCY
                elseif s._shiftAxis == "Y" then
                    rawCX = s._dragStartCX
                end
            else
                s._shiftAxis = nil  -- release shift = unlock axis
            end

            local halfW = s._dragHalfW
            local halfH = s._dragHalfH

            -- Apply snap
            local snapCX, snapCY = SnapPosition(s._barKey, rawCX, rawCY, halfW, halfH)

            -- Clamp to screen edges
            local screenW = UIParent:GetWidth()
            local screenH = UIParent:GetHeight()
            snapCX = max(halfW, min(screenW - halfW, snapCX))
            snapCY = max(halfH, min(screenH - halfH, snapCY))

            -- Move the real bar live first, then anchor the mover to it so
            -- the overlay stays pixel-perfect regardless of scale differences.
            local bar = GetBarFrame(s._barKey)
            if bar and not InCombatLockdown() then
                local uiS = UIParent:GetEffectiveScale()
                local bS = bar:GetEffectiveScale()
                local ratio = uiS / bS
                -- bar:GetWidth/Height are in the bar's local (unscaled) space.
                -- Convert snapCX/snapCY (UIParent screen coords) into the bar's
                -- local space first, then subtract the unscaled half-size to get TOPLEFT.
                local barHW = (bar:GetWidth() or 0) * 0.5
                local barHH = (bar:GetHeight() or 0) * 0.5
                local barX = snapCX * ratio - barHW
                local barY = (snapCY - UIParent:GetHeight() - (s._dragCenterYOff or 0)) * ratio + barHH
                local PPd = EllesmereUI and EllesmereUI.PP
                if PPd and PPd.SnapForES then
                    -- When an edge snap is active, skip SnapForES on that axis.
                    -- The unsnapped barX/barY already matches the target's edge
                    -- exactly. Re-snapping would shift it to a different pixel.
                    local lockX, lockY = EllesmereUI._snapAxisLocked()
                    if not lockX then barX = PPd.SnapForES(barX, bS) end
                    if not lockY then barY = PPd.SnapForES(barY, bS) end
                end
                pcall(function()
                    bar:ClearAllPoints()
                    bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", barX, barY)
                end)
                -- Anchor mover directly to bar TOPLEFT for pixel-perfect overlay
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            else
                -- No live bar -- position mover in UIParent space
                local finalX = snapCX - halfW
                local finalY = snapCY + halfH - UIParent:GetHeight()
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", UIParent, "TOPLEFT", finalX, finalY)
            end

            -- Show live coordinates during drag (only on elements >= 20px tall).
            -- Physical-pixel counts, matching the cog X/Y boxes and the overlay.
            if s._coordFS and s:GetHeight() >= 12 then
                local PPc = EllesmereUI and EllesmereUI.PP
                local toPx = (PPc and PPc.ToPixels) or round
                s._coordFS:SetText(format("%.0f, %.0f", toPx(snapCX - screenW * 0.5), toPx(snapCY - screenH * 0.5)))
                s._coordFS:Show()
            end

            -- Anchor chain: propagate recursively down the chain
            local anchorDB = GetAnchorDB()
            if anchorDB then
                PropagateAnchorChain(s._barKey)
            end

            local elem = registeredElements[s._barKey]
            if elem and elem.onLiveMove then
                pcall(elem.onLiveMove, s._barKey)
            end

            ShowAlignmentGuides(s._barKey)

            -- Safety net: if mouse button was released outside any button frame
            -- (e.g. during a link-initiated drag), stop the drag now.
            if not IsMouseButtonDown("LeftButton") then
                local stopScript = s:GetScript("OnDragStop")
                if stopScript then stopScript(s) end
            end
        end)
    end)

    mover:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self._dragging = false
        _mouseHeld = false
        self:SetAlpha(darkOverlaysEnabled and 1 or MOVER_HOVER)
        -- Convert back to CENTER anchor so hover-expand stays symmetric
        local mL, mR = self:GetLeft(), self:GetRight()
        local mT, mB = self:GetTop(), self:GetBottom()
        if mL and mR and mT and mB then
            local cx = (mL + mR) * 0.5
            local cy = (mT + mB) * 0.5 - UIParent:GetHeight()
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "TOPLEFT", cx, cy)
            moverCX, moverCY = cx, cy
        end
        -- Update coords to final position (stays visible if selected or coords-always-on)
        if self._selected and self.UpdateCoordText then
            self:UpdateCoordText()
        elseif coordsEnabled and self.UpdateCoordText then
            self:UpdateCoordText()
        else
            self._coordFS:Hide()
        end
        HideAllGuidesAndHighlight()
        -- Re-show links after drag if still hovered
        if self:IsMouseOver() then
            if self._showOverlayText then self._showOverlayText() end
        end
        -- Re-anchor toolbar in case mover moved near/away from screen top
        if self._anchorToolbar then self._anchorToolbar() end

        -- Check if the mover actually moved (avoids false dirty flag from
        -- click-and-hold without movement)
        local cxL, cxR = self:GetLeft(), self:GetRight()
        local cyT, cyB = self:GetTop(), self:GetBottom()
        if not cxL or not cxR or not cyT or not cyB then return end
        local cx = (cxL + cxR) / 2
        local cy = (cyT + cyB) / 2
        local startCX = self._dragStartCX or cx
        local startCY = self._dragStartCY or cy
        local moved = (abs(cx - startCX) > 0.5) or (abs(cy - startCY) > 0.5)
        if not moved then return end

        -- Store position in pending table (NOT saved until user clicks Save & Exit)

        local bar = GetBarFrame(self._barKey)
        if not InCombatLockdown() then
            local uiS = UIParent:GetEffectiveScale()

            -- If this bar is anchored, the offset was already updated live during drag.
            -- No need to recompute here -- using mover screen coords would introduce
            -- sub-pixel drift vs the cursor-based offset set in OnUpdate.

            local dragCYOff = self._dragCenterYOff or 0
            if bar then
                -- Read the bar's actual TOPLEFT from its current SetPoint rather
                -- than recomputing from the mover center. The OnUpdate already
                -- positioned the bar with exact edge alignment (no SnapForES drift).
                local _, _, _, barX, barY = bar:GetPoint(1)
                if not barX or not barY then
                    local bS = bar:GetEffectiveScale()
                    local ratio = uiS / bS
                    local barHW = (bar:GetWidth() or 0) * 0.5
                    local barHH = (bar:GetHeight() or 0) * 0.5
                    barX = cx * ratio - barHW
                    barY = (cy - UIParent:GetHeight() - dragCYOff) * ratio + barHH
                    local PPd = EllesmereUI and EllesmereUI.PP
                    if PPd and PPd.SnapForES then
                        barX = PPd.SnapForES(barX, bS)
                        barY = PPd.SnapForES(barY, bS)
                    end
                end
                pendingPositions[self._barKey] = {
                    point = "TOPLEFT", relPoint = "TOPLEFT",
                    x = barX, y = barY,
                }
            else
                -- No live frame (e.g. unit frame not spawned) -- store in UIParent coords
                local halfW = (baseW > 0 and baseW or self:GetWidth()) / 2
                local halfH = (baseH > 0 and baseH or self:GetHeight()) / 2
                pendingPositions[self._barKey] = {
                    point = "TOPLEFT", relPoint = "TOPLEFT",
                    x = cx - halfW, y = cy + halfH - UIParent:GetHeight() - dragCYOff,
                }
            end
            hasChanges = true
        end

        -- If this element is anchored to a parent, update the stored offset
        -- so the parent's future moves don't snap this child back.
        -- Read actual child edges directly instead of computing from center+half
        -- to avoid floating-point dust from (top+bottom)/2 - height/2 != bottom.
        local ai = GetAnchorInfo(self._barKey)
        if ai then
            local targetBar = GetBarFrame(ai.target)
            if targetBar then
                local tS = targetBar:GetEffectiveScale()
                local uiScale = UIParent:GetEffectiveScale()
                local tL = targetBar:GetLeft()
                local tR = targetBar:GetRight()
                local tT = targetBar:GetTop()
                local tB = targetBar:GetBottom()
                if tL and tR and tT and tB then
                    tL = tL * tS / uiScale
                    tR = tR * tS / uiScale
                    tT = tT * tS / uiScale
                    tB = tB * tS / uiScale
                    local tCX = (tL + tR) / 2
                    local tCY = (tT + tB) / 2
                    -- Read child edges from the actual bar frame for accuracy
                    local childBar = GetBarFrame(self._barKey)
                    local cL, cR, cT, cB
                    if childBar and childBar:GetLeft() then
                        local cS = childBar:GetEffectiveScale()
                        cL = childBar:GetLeft() * cS / uiScale
                        cR = childBar:GetRight() * cS / uiScale
                        cT = childBar:GetTop() * cS / uiScale
                        cB = childBar:GetBottom() * cS / uiScale
                    else
                        local halfW = baseW > 0 and baseW / 2 or (self:GetWidth() / 2)
                        local halfH = baseH > 0 and baseH / 2 or (self:GetHeight() / 2)
                        cL = cx - halfW; cR = cx + halfW
                        cT = cy + halfH; cB = cy - halfH
                    end
                    local cCX = (cL + cR) / 2
                    local cCY = (cT + cB) / 2
                    local sd = ai.side
                    if sd == "LEFT" then
                        ai.offsetX = cR - tL
                        ai.offsetY = cCY - tCY
                    elseif sd == "RIGHT" then
                        ai.offsetX = cL - tR
                        ai.offsetY = cCY - tCY
                    elseif sd == "TOP" then
                        ai.offsetX = cCX - tCX
                        ai.offsetY = cB - tT
                    elseif sd == "BOTTOM" then
                        ai.offsetX = cCX - tCX
                        ai.offsetY = cT - tB
                    else
                        ai.offsetX = cCX - tCX
                        ai.offsetY = cCY - tCY
                    end
                end
            end
        end

        -- Anchor chain: propagate recursively down the chain
        PropagateAnchorChain(self._barKey)

        local elem = registeredElements[self._barKey]
        if elem and elem.onLiveMove then
            pcall(elem.onLiveMove, self._barKey)
        end

        -- Keep the mover selected after drag so arrow keys can nudge it.
        -- Drop frame level back to normal so it doesn't block other movers.
        if self._selected then
            self:SetFrameLevel(self._baseLevel or self:GetFrameLevel())
        end

        -- Re-anchor mover to bar for pixel-perfect alignment
        self:ReanchorToBar()
    end)

    -- Hover effects
    mover:SetScript("OnEnter", function(self)
        if not self._dragging then
            if _mouseHeld and not self._dragging then return end
            -- Collapse any other expanded mover before expanding this one
            if hoveredMover and hoveredMover ~= self and not hoveredMover._dragging then
                if hoveredMover._hideOverlayText then hoveredMover._hideOverlayText() end
                hoveredMover = nil
            end
            -- Collapse selected mover's overlay if hovering a different one
            if selectedMover and selectedMover ~= self and not selectedMover._dragging then
                if selectedMover._hideOverlayText then selectedMover._hideOverlayText() end
            end
            hoveredMover = self
            -- Raise above all other movers
            self:SetFrameLevel(self._raisedLevel + 100)
            if self._cogBtn then self._cogBtn:SetFrameLevel(self:GetFrameLevel() + 10) end
            -- Select Element mode: white border highlight on hover targets
            if selectElementPicker and selectElementPicker ~= self then
                self._brd:SetColor(1, 1, 1, 0.9)
                if not darkOverlaysEnabled then self:SetAlpha(MOVER_HOVER) end
                return
            end
            -- Pick mode (width/height match, anchor to): white border on hover targets
            if pickModeMover and pickModeMover ~= self and pickMode then
                self._brd:SetColor(1, 1, 1, 0.9)
                if not darkOverlaysEnabled then self:SetAlpha(MOVER_HOVER) end
                return
            end
            if not darkOverlaysEnabled then self:SetAlpha(MOVER_HOVER) end
            self._brd:SetColor(1, 1, 1, 0.9)
            -- Don't show links if this mover is the pick mode source
            if pickModeMover == self and pickMode then
                -- Already showing pick text, don't override
            else
                -- Wait the intent delay, then expand if still hovered and cursor has settled.
                -- If cursor is still fast at fire time, allow one retry after a short pause.
                self._hoverPending = true
                local m = self
                C_Timer.After(EllesmereUI._unlockHoverIntentDelay, function()
                    if not m._hoverPending then return end
                    if not m:IsMouseOver() and not (m._cogBtn and m._cogBtn:IsMouseOver()) then
                        local overLink = false
                        if m._linkBtns then for _, b in ipairs(m._linkBtns) do if b:IsMouseOver() then overLink = true; break end end end
                        if not overLink then m._hoverPending = false; return end
                    end
                    local function DoExpand()
                        if not m._hoverPending then return end
                        m._hoverPending = false
                        local stillOver = m:IsMouseOver() or (m._cogBtn and m._cogBtn:IsMouseOver())
                        if not stillOver and m._linkBtns then
                            for _, b in ipairs(m._linkBtns) do if b:IsMouseOver() then stillOver = true; break end end
                        end
                        if stillOver and m._showOverlayText then
                            -- Collapse any other mover still animating open
                            if hoveredMover and hoveredMover ~= m and not hoveredMover._dragging then
                                if hoveredMover._hideOverlayText then hoveredMover._hideOverlayText() end
                                hoveredMover = nil
                            end
                            hoveredMover = m
                            m._showOverlayText()
                        end
                    end
                    if EllesmereUI._unlockCursorSpeed > EllesmereUI._unlockHoverSpeedThresh then
                        C_Timer.After(0.08, DoExpand)
                    else
                        DoExpand()
                    end
                end)
            end
        end
    end)
    mover:SetScript("OnLeave", function(self)
        if not self._dragging then
            -- Delay so hovering child buttons (cog, link buttons) doesn't flicker
            C_Timer.After(0.12, function()
                if self._dragging then return end
                if self:IsMouseOver() then
                    self:SetFrameLevel(self._raisedLevel + 100)
                    self._brd:SetColor(1, 1, 1, 0.9)
                    if not darkOverlaysEnabled then self:SetAlpha(MOVER_HOVER) end
                    return
                end
                if self._cogBtn and self._cogBtn:IsMouseOver() then
                    self:SetFrameLevel(self._raisedLevel + 100)
                    self._brd:SetColor(1, 1, 1, 0.9)
                    if not darkOverlaysEnabled then self:SetAlpha(MOVER_HOVER) end
                    return
                end
                if self._linkBtns then
                    for _, btn in ipairs(self._linkBtns) do
                        if btn:IsMouseOver() then
                            self:SetFrameLevel(self._raisedLevel + 100)
                            self._brd:SetColor(1, 1, 1, 0.9)
                            if not darkOverlaysEnabled then self:SetAlpha(MOVER_HOVER) end
                            return
                        end
                    end
                end
                -- Truly left the element -- cancel any pending expand and collapse
                self._hoverPending = false
                if self._hideOverlayText then self._hideOverlayText() end
                if hoveredMover == self then hoveredMover = nil end
                -- Keep highlight border and raised level if selected (arrow keys)
                if not self._selected then
                    self:SetFrameLevel(self._baseLevel)
                    if not darkOverlaysEnabled then self:SetAlpha(MOVER_ALPHA) end
                    self._brd:SetColor(ar, ag, ab, 0.6)
                end
            end)
        end
    end)

    -- Left-click to select
    mover:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            -- Width Match / Height Match / Anchor To pick mode handling
            -- Clicking the source mover itself cancels the pick mode
            if pickModeMover and pickModeMover == self and pickMode then
                CancelPickMode()
                return
            end
            if pickModeMover and pickModeMover ~= self and pickMode then
                local sourceMover = pickModeMover
                local sourceKey = sourceMover._barKey
                local targetKey = self._barKey

                if pickMode == "widthMatch" then
                    local tEl = registeredElements[targetKey]
                    if tEl and tEl.noSizeMatchTarget then
                        CancelPickMode()
                        FlashRedBorder(self)
                        local tLabel = GetBarLabel(targetKey) or targetKey
                        RejectH.ShowTooltip("Elements cannot size match to\n" .. tLabel)
                        return
                    end
                    if RejectH.IsActionBar(sourceKey) and not RejectH.IsActionBar(targetKey) then
                        CancelPickMode()
                        FlashRedBorder(self)
                        RejectH.ShowTooltip("Action Bars can only width match\nto other Action Bars")
                        return
                    end
                    local wdb = MatchH.GetWidthMatchDB()
                    if wdb and MatchH.WouldCreateCycle(wdb, sourceKey, targetKey) then
                        CancelPickMode()
                        FlashRedBorder(self)
                        RejectH.ShowTooltip("This would create a circular width match")
                        return
                    end
                    MatchH.SetWidthMatch(sourceKey, targetKey)
                    MatchH.ApplyWidthMatch(sourceKey, targetKey)
                    hasChanges = true
                    CancelPickMode()
                    local sm = movers[sourceKey]
                    if sm then
                        sm:SyncSize()
                        if sm.RefreshAnchoredText then sm:RefreshAnchoredText() end
                    end
                    local ai = GetAnchorInfo(sourceKey)
                    if ai then ApplyAnchorPosition(sourceKey, ai.target, ai.side, true) end
                    EllesmereUI.PropagateWidthMatch(sourceKey)
                    PropagateAnchorChain(sourceKey)
                    return

                elseif pickMode == "heightMatch" then
                    local tEl = registeredElements[targetKey]
                    if tEl and tEl.noSizeMatchTarget then
                        CancelPickMode()
                        FlashRedBorder(self)
                        local tLabel = GetBarLabel(targetKey) or targetKey
                        RejectH.ShowTooltip("Elements cannot size match to\n" .. tLabel)
                        return
                    end
                    local hdb = MatchH.GetHeightMatchDB()
                    if hdb and MatchH.WouldCreateCycle(hdb, sourceKey, targetKey) then
                        CancelPickMode()
                        FlashRedBorder(self)
                        RejectH.ShowTooltip("This would create a circular height match")
                        return
                    end
                    MatchH.SetHeightMatch(sourceKey, targetKey)
                    MatchH.ApplyHeightMatch(sourceKey, targetKey)
                    hasChanges = true
                    CancelPickMode()
                    local sm = movers[sourceKey]
                    if sm then
                        sm:SyncSize()
                        if sm.RefreshAnchoredText then sm:RefreshAnchoredText() end
                    end
                    local ai = GetAnchorInfo(sourceKey)
                    if ai then ApplyAnchorPosition(sourceKey, ai.target, ai.side, true) end
                    EllesmereUI.PropagateHeightMatch(sourceKey)
                    PropagateAnchorChain(sourceKey)
                    return

                elseif pickMode == "anchorTo" then
                    -- Show anchor direction dropdown near the clicked target
                    local pm = pickModeMover
                    local pmKey = pm._barKey

                    -- Reject elements marked as non-anchorable (e.g. buff bars
                    -- whose icon count changes dynamically with auras).
                    local targetEl = registeredElements[targetKey]
                    if targetEl and targetEl.noAnchorTarget then
                        CancelPickMode()
                        FlashRedBorder(self)
                        local targetLabel = GetBarLabel(targetKey) or targetKey
                        RejectH.ShowTooltip("Elements cannot be anchored to\n" .. targetLabel)
                        return
                    end

                    local circular = false
                    local visited = { [pmKey] = true }
                    local walk = targetKey
                    while walk do
                        if visited[walk] then circular = true; break end
                        visited[walk] = true
                        local info = GetAnchorInfo(walk)
                        walk = info and info.target or nil
                    end
                    if circular then
                        CancelPickMode()
                        FlashRedBorder(self)
                        RejectH.ShowTooltip("This would create a circular anchor")
                        return
                    end

                    -- Ancestor depth check: prevent anchoring to a grandparent
                    -- or higher. Only direct parent (depth 1) or unrelated
                    -- elements are valid targets.
                    local ancestorDepth = 0
                    local aWalk = pmKey
                    while aWalk do
                        local aInfo = GetAnchorInfo(aWalk)
                        if not aInfo or not aInfo.target then break end
                        ancestorDepth = ancestorDepth + 1
                        if aInfo.target == targetKey and ancestorDepth >= 2 then
                            CancelPickMode()
                            FlashRedBorder(self)
                            RejectH.ShowTooltip("This would create a circular anchor")
                            return
                        end
                        aWalk = aInfo.target
                    end

                    CancelPickMode()
                    -- Build and show the anchor direction dropdown
                    if not anchorDropdownFrame then
                        anchorDropdownFrame = CreateFrame("Frame", nil, unlockFrame)
                        anchorDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                        anchorDropdownFrame:SetFrameLevel(260)
                        anchorDropdownFrame:SetClampedToScreen(true)
                        anchorDropdownFrame:EnableMouse(true)
                    end
                    -- Click catcher behind dropdown
                    if not anchorDropdownCatcher then
                        anchorDropdownCatcher = CreateFrame("Button", nil, unlockFrame)
                        anchorDropdownCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
                        anchorDropdownCatcher:SetFrameLevel(259)
                        anchorDropdownCatcher:SetAllPoints(UIParent)
                        anchorDropdownCatcher:RegisterForClicks("AnyUp")
                        anchorDropdownCatcher:SetScript("OnClick", function()
                            anchorDropdownFrame:Hide()
                            anchorDropdownCatcher:Hide()
                        end)
                    end
                    -- Rebuild dropdown content
                    for _, child in ipairs({anchorDropdownFrame:GetChildren()}) do child:Hide(); child:SetParent(nil) end
                    for _, tex in ipairs({anchorDropdownFrame:GetRegions()}) do if tex.Hide then tex:Hide() end end

                    local DD_ITEM_H = 24
                    local DD_WIDTH = 160
                    anchorDropdownFrame:SetSize(DD_WIDTH, 10)
                    anchorDropdownFrame:ClearAllPoints()
                    local scale = UIParent:GetEffectiveScale()
                    local curX, curY = GetCursorPosition()
                    curX = curX / scale
                    curY = curY / scale - UIParent:GetHeight()
                    anchorDropdownFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", curX, curY)

                    local ddBg = anchorDropdownFrame:CreateTexture(nil, "BACKGROUND")
                    ddBg:SetAllPoints()
                    ddBg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
                    EllesmereUI.MakeBorder(anchorDropdownFrame, 1, 1, 1, 0.20)

                    local ddY = -4
                    -- Title
                    local titleFS = anchorDropdownFrame:CreateFontString(nil, "OVERLAY")
                    titleFS:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
                    titleFS:SetTextColor(1, 1, 1, 0.40)
                    titleFS:SetJustifyH("LEFT")
                    titleFS:SetPoint("TOPLEFT", anchorDropdownFrame, "TOPLEFT", 10, ddY - 4)
                    titleFS:SetText(EllesmereUI.L("Anchor Direction"))
                    ddY = ddY - 18
                    local titleDiv = anchorDropdownFrame:CreateTexture(nil, "ARTWORK")
                    titleDiv:SetHeight(1)
                    titleDiv:SetColorTexture(1, 1, 1, 0.10)
                    titleDiv:SetPoint("TOPLEFT", anchorDropdownFrame, "TOPLEFT", 1, ddY - 2)
                    titleDiv:SetPoint("TOPRIGHT", anchorDropdownFrame, "TOPRIGHT", -1, ddY - 2)
                    ddY = ddY - 5

                    local sides = { "Left", "Right", "Top", "Bottom" }
                    for _, sideName in ipairs(sides) do
                        local sideVal = string.upper(sideName)
                        local item = CreateFrame("Button", nil, anchorDropdownFrame)
                        item:SetHeight(DD_ITEM_H)
                        item:SetPoint("TOPLEFT", anchorDropdownFrame, "TOPLEFT", 1, ddY)
                        item:SetPoint("TOPRIGHT", anchorDropdownFrame, "TOPRIGHT", -1, ddY)
                        item:SetFrameLevel(anchorDropdownFrame:GetFrameLevel() + 2)
                        item:RegisterForClicks("AnyUp")
                        local hl = item:CreateTexture(nil, "ARTWORK")
                        hl:SetAllPoints()
                        hl:SetColorTexture(1, 1, 1, 0)
                        local lbl = item:CreateFontString(nil, "OVERLAY")
                        lbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
                        lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                        lbl:SetJustifyH("LEFT")
                        lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                        lbl:SetText(EllesmereUI.Lf("Anchor to %1$s", sideName))
                        item:SetScript("OnEnter", function()
                            hl:SetColorTexture(1, 1, 1, 0.08)
                            lbl:SetTextColor(1, 1, 1, 1)
                        end)
                        item:SetScript("OnLeave", function()
                            hl:SetColorTexture(1, 1, 1, 0)
                            lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                        end)
                        item:SetScript("OnClick", function()
                            anchorDropdownFrame:Hide()
                            anchorDropdownCatcher:Hide()
                            -- Default grow direction to match the anchor side
                            -- (orientation-aware: cross-axis sides map to CENTER)
                            local isVert = false
                            if pmKey:sub(1, 4) == "CDM_" then
                                local rawCdmKey = pmKey:sub(5)
                                local cdmAddon = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
                                local cdmBars = cdmAddon and cdmAddon.db and cdmAddon.db.profile and cdmAddon.db.profile.cdmBars
                                if cdmBars and cdmBars.bars then
                                    for _, bar in ipairs(cdmBars.bars) do
                                        if bar.key == rawCdmKey then
                                            isVert = bar.verticalOrientation == true
                                            local map = isVert
                                                and { TOP = "UP", BOTTOM = "DOWN", LEFT = "CENTER", RIGHT = "CENTER" }
                                                or  { LEFT = "LEFT", RIGHT = "RIGHT", TOP = "CENTER", BOTTOM = "CENTER" }
                                            bar.growDirection = map[sideVal] or "CENTER"
                                            break
                                        end
                                    end
                                end
                            else
                                local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
                                local abBars = eab and eab.db and eab.db.profile and eab.db.profile.bars
                                local abCfg = abBars and abBars[pmKey]
                                if abCfg then
                                    isVert = (abCfg.orientation == "vertical")
                                    local map = isVert
                                        and { TOP = "up", BOTTOM = "down", LEFT = "center", RIGHT = "center" }
                                        or  { LEFT = "left", RIGHT = "right", TOP = "center", BOTTOM = "center" }
                                    abCfg.growDirection = map[sideVal] or "center"
                                end
                            end
                            -- Set anchor relationship
                            SetAnchorInfo(pmKey, targetKey, sideVal)
                            -- Apply the anchor position
                            ApplyAnchorPosition(pmKey, targetKey, sideVal)
                            -- Propagate to children after layout flushes so
                            -- they read the correct bounds from the newly-anchored parent
                            C_Timer.After(0, function() PropagateAnchorChain(pmKey) end)
                            hasChanges = true
                            -- Refresh the anchored mover's text
                            if movers[pmKey] and movers[pmKey].RefreshAnchoredText then
                                movers[pmKey]:RefreshAnchoredText()
                            end
                            -- Sync mover position to follow the element after anchor placement
                            DeferMoverSync(movers[pmKey], function(m) m:Sync() end, GetBarFrame(pmKey))
                        end)
                        ddY = ddY - DD_ITEM_H
                    end

                    -- "Remove Anchor" option if already anchored
                    if IsAnchored(pmKey) then
                        local divR = anchorDropdownFrame:CreateTexture(nil, "ARTWORK")
                        divR:SetHeight(1)
                        divR:SetColorTexture(1, 1, 1, 0.10)
                        divR:SetPoint("TOPLEFT", anchorDropdownFrame, "TOPLEFT", 1, ddY - 4)
                        divR:SetPoint("TOPRIGHT", anchorDropdownFrame, "TOPRIGHT", -1, ddY - 4)
                        ddY = ddY - 9

                        local removeItem = CreateFrame("Button", nil, anchorDropdownFrame)
                        removeItem:SetHeight(DD_ITEM_H)
                        removeItem:SetPoint("TOPLEFT", anchorDropdownFrame, "TOPLEFT", 1, ddY)
                        removeItem:SetPoint("TOPRIGHT", anchorDropdownFrame, "TOPRIGHT", -1, ddY)
                        removeItem:SetFrameLevel(anchorDropdownFrame:GetFrameLevel() + 2)
                        removeItem:RegisterForClicks("AnyUp")
                        local rHl = removeItem:CreateTexture(nil, "ARTWORK")
                        rHl:SetAllPoints()
                        rHl:SetColorTexture(1, 1, 1, 0)
                        local rLbl = removeItem:CreateFontString(nil, "OVERLAY")
                        rLbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
                        rLbl:SetTextColor(0.9, 0.3, 0.3, 0.9)
                        rLbl:SetJustifyH("LEFT")
                        rLbl:SetPoint("LEFT", removeItem, "LEFT", 10, 0)
                        rLbl:SetText(EllesmereUI.L("Remove Anchor"))
                        removeItem:SetScript("OnEnter", function()
                            rHl:SetColorTexture(1, 1, 1, 0.08)
                            rLbl:SetTextColor(1, 0.4, 0.4, 1)
                        end)
                        removeItem:SetScript("OnLeave", function()
                            rHl:SetColorTexture(1, 1, 1, 0)
                            rLbl:SetTextColor(0.9, 0.3, 0.3, 0.9)
                        end)
                        removeItem:SetScript("OnClick", function()
                            anchorDropdownFrame:Hide()
                            anchorDropdownCatcher:Hide()
                            ClearAnchorInfo(pmKey)
                            hasChanges = true
                            if movers[pmKey] and movers[pmKey].RefreshAnchoredText then
                                movers[pmKey]:RefreshAnchoredText()
                            end
                        end)
                        ddY = ddY - DD_ITEM_H
                    end

                    anchorDropdownFrame:SetHeight(-ddY + 4)
                    anchorDropdownFrame:Show()
                    anchorDropdownCatcher:Show()
                    return
                end
            end

            -- Select Element pick mode: clicking a different mover sets it as snap target
            if selectElementPicker and selectElementPicker ~= self then
                local picker = selectElementPicker
                picker._snapTarget = self._barKey
                picker._preSelectTarget = nil
                selectElementPicker = nil
                FadeOverlayForSelectElement(false)
                -- Restore this mover's normal colors
                self._brd:SetColor(ar, ag, ab, 0.6)
                if not darkOverlaysEnabled then self:SetAlpha(MOVER_ALPHA) end
                -- Update the picker's dropdown label
                if picker._updateSnapLabel then picker._updateSnapLabel() end
                return
            end
            -- Toggle: clicking the already-selected mover deselects it
            if selectedMover == self then
                DeselectMover()
            else
                SelectMover(self)
            end
        elseif button == "RightButton" then
            if selectElementPicker then return end
            SelectMover(self)
            if self._openCogMenu then self._openCogMenu() end
        end
    end)
    mover:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    ---------------------------------------------------------------------------
    --  Action toolbar: cog settings button only
    --  Cog is flush with mover's top-right corner.
    ---------------------------------------------------------------------------
    local ICON_PATH = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
    local ARROW_ICON  = ICON_PATH .. "eui-arrow.png"
    local ARROW_RIGHT_ICON = ICON_PATH .. "right-arrow.png"
    local COGS_ICON   = EllesmereUI.COGS_ICON or (ICON_PATH .. "cogs-3.png")
    local ACT_SZ = 22       -- cog button size
    local ACT_PAD = 3       -- gap between cog and dropdown
    local DD_W = 150        -- dropdown width

    -- Cog settings button (opens a dropdown with Reset / Center / Orientation)
    cogBtn = CreateFrame("Button", nil, unlockFrame)
    cogBtn:SetFrameLevel(mover:GetFrameLevel() + 10)
    cogBtn:RegisterForClicks("AnyUp")
    cogBtn:EnableMouse(true)
    cogBtn:SetSize(ACT_SZ, ACT_SZ)
    do
        local bg = cogBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
        cogBtn._bg = bg
        local brd = EllesmereUI.MakeBorder(cogBtn, 1, 1, 1, 0.20)
        cogBtn._brd = brd
        local icon = cogBtn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("CENTER")
        icon:SetTexture(COGS_ICON)
        icon:SetAlpha(0.7)
        cogBtn._icon = icon
        cogBtn:SetScript("OnEnter", function(self)
            self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
            self._brd:SetColor(1, 1, 1, 0.30)
            self._icon:SetAlpha(1)
            mover:SetFrameLevel(mover._raisedLevel + 100)
            mover._brd:SetColor(1, 1, 1, 0.9)
            if not darkOverlaysEnabled then mover:SetAlpha(MOVER_HOVER) end
        end)
        cogBtn:SetScript("OnLeave", function(self)
            self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
            self._brd:SetColor(1, 1, 1, 0.20)
            self._icon:SetAlpha(0.7)
        end)
    end
    cogBtn:Hide()

    -- Cog visibility is now tied to the hover animation.
    -- Show/hide helpers are simple wrappers.
    local function ShowCogForHover() end
    local function HideCogAfterDelay() end
    local function HideCogImmediate() end

    mover._showCogForHover = ShowCogForHover
    mover._hideCogAfterDelay = HideCogAfterDelay
    mover._hideCogImmediate = HideCogImmediate

    -- Re-set cogBtn hover scripts now that fade helpers are in scope
    cogBtn:SetScript("OnEnter", function(self)
        self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
        self._brd:SetColor(1, 1, 1, 0.30)
        self._icon:SetAlpha(1)
        -- Restore mover highlight immediately (mover:OnLeave resets it when mouse moves to cog)
        mover:SetFrameLevel(mover._raisedLevel + 100)
        mover._brd:SetColor(1, 1, 1, 0.9)
        if not darkOverlaysEnabled then mover:SetAlpha(MOVER_HOVER) end
    end)
    cogBtn:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
        self._brd:SetColor(1, 1, 1, 0.20)
        self._icon:SetAlpha(0.7)
    end)

    ---------------------------------------------------------------------------
    --  Snap-to dropdown (custom styled, per-mover memory)
    ---------------------------------------------------------------------------
    local snapDD = CreateFrame("Button", nil, unlockFrame)
    snapDD:SetFrameLevel(mover:GetFrameLevel() + 10)
    snapDD:RegisterForClicks("AnyUp")
    snapDD:EnableMouse(true)
    snapDD:SetSize(DD_W, 30)
    local snapDDBg = snapDD:CreateTexture(nil, "BACKGROUND")
    snapDDBg:SetAllPoints()
    snapDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
    snapDD._bg = snapDDBg
    local snapDDBrd = EllesmereUI.MakeBorder(snapDD, 1, 1, 1, 0.20)
    snapDD._brd = snapDDBrd
    local snapDDLbl = snapDD:CreateFontString(nil, "OVERLAY")
    snapDDLbl:SetFont(FONT_PATH, 12, "OUTLINE, SLUG")
    snapDDLbl:SetTextColor(1, 1, 1, 0.50)
    snapDDLbl:SetJustifyH("LEFT")
    snapDDLbl:SetWordWrap(false)
    snapDDLbl:SetMaxLines(1)
    snapDDLbl:SetPoint("LEFT", snapDD, "LEFT", 8, 0)
    snapDDLbl:SetText(EllesmereUI.L("Snap to: Auto"))
    local snapDDArrow = EllesmereUI.MakeDropdownArrow(snapDD, 12)
    snapDDLbl:SetPoint("RIGHT", snapDDArrow, "LEFT", -5, 0)
    snapDD:SetScript("OnEnter", function(self)
        if not snapEnabled then
            -- Grayed out: show tooltip explaining why
            EllesmereUI.ShowWidgetTooltip(self, "This feature requires Snap Elements to be enabled")
            return
        end
        self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
        self._brd:SetColor(1, 1, 1, 0.30)
        snapDDLbl:SetTextColor(1, 1, 1, 0.60)
    end)
    snapDD:SetScript("OnLeave", function(self)
        EllesmereUI.HideWidgetTooltip()
        if not snapEnabled then return end
        self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
        self._brd:SetColor(1, 1, 1, 0.20)
        snapDDLbl:SetTextColor(1, 1, 1, 0.50)
    end)
    snapDD:Hide()

    -- Helper: apply grayed-out or normal visual state to the dropdown
    local function RefreshSnapDDState()
        if not snapEnabled then
            snapDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.50)
            snapDDBrd:SetColor(1, 1, 1, 0.07)
            snapDDLbl:SetTextColor(1, 1, 1, 0.20)
            snapDDArrow:SetAlpha(0.10)
        else
            snapDDBg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
            snapDDBrd:SetColor(1, 1, 1, 0.20)
            snapDDLbl:SetTextColor(1, 1, 1, 0.50)
            snapDDArrow:SetAlpha(1)
        end
    end
    mover._refreshSnapDD = RefreshSnapDDState

    -- Snap dropdown menu frame (lazy-created, shared across this mover)
    local snapMenu
    local regSubMenus = {}

    local function CloseSnapMenu()
        if snapMenu then snapMenu:Hide() end
        for _, rs in pairs(regSubMenus) do
            if rs and rs.Hide then rs:Hide() end
        end
    end

    local function UpdateSnapLabel()
        local tgt = mover._snapTarget
        if tgt == "_disable_" then
            snapDDLbl:SetText(EllesmereUI.L("Snap to: None"))
        elseif tgt == "_select_" then
            snapDDLbl:SetText(EllesmereUI.L("Snap to: Select Element"))
        elseif tgt then
            local lbl = GetBarLabel(tgt)
            snapDDLbl:SetText(EllesmereUI.Lf("Snap to: %1$s", lbl or tgt))
        else
            snapDDLbl:SetText(EllesmereUI.L("Snap to: All Elements"))
        end
        -- Update snap highlight to match new target
        if mover._selected then
            if tgt and tgt ~= "_disable_" and tgt ~= "_select_" and movers[tgt] then
                ShowSnapHighlight(tgt)
            else
                ClearSnapHighlight()
            end
        end
    end

    local function BuildSnapMenu()
        if snapMenu then
            -- Rebuild items
            for _, child in ipairs({snapMenu:GetChildren()}) do child:Hide(); child:SetParent(nil) end
            for _, tex in ipairs({snapMenu:GetRegions()}) do if tex.Hide then tex:Hide() end end
        end
        snapMenu = snapMenu or CreateFrame("Frame", nil, unlockFrame)
        snapMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        snapMenu:SetFrameLevel(250)
        snapMenu:SetClampedToScreen(true)
        snapMenu:SetSize(DD_W, 10)
        snapMenu:SetPoint("TOPLEFT", mover, "TOPRIGHT", 4, 0)

        -- Background + border
        local menuBg = snapMenu:CreateTexture(nil, "BACKGROUND")
        menuBg:SetAllPoints()
        menuBg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
        EllesmereUI.MakeBorder(snapMenu, 1, 1, 1, 0.20)

        local ITEM_H = 24
        local yOff = -4
        local items = {}

        -- Title: "Snap Target"
        local titleLbl = snapMenu:CreateFontString(nil, "OVERLAY")
        titleLbl:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
        titleLbl:SetTextColor(1, 1, 1, 0.40)
        titleLbl:SetJustifyH("LEFT")
        titleLbl:SetPoint("TOPLEFT", snapMenu, "TOPLEFT", 10, yOff - 4)
        titleLbl:SetText(EllesmereUI.L("Snap Target"))
        yOff = yOff - 18

        -- Title divider
        local titleDiv = snapMenu:CreateTexture(nil, "ARTWORK")
        titleDiv:SetHeight(1)
        titleDiv:SetColorTexture(1, 1, 1, 0.10)
        titleDiv:SetPoint("TOPLEFT", snapMenu, "TOPLEFT", 1, yOff - 2)
        titleDiv:SetPoint("TOPRIGHT", snapMenu, "TOPRIGHT", -1, yOff - 2)
        yOff = yOff - 5

        local function MakeItem(parent, text, onClick, isSelected)
            local item = CreateFrame("Button", nil, parent)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, yOff)
            item:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -1, yOff)
            item:SetFrameLevel(parent:GetFrameLevel() + 2)
            item:RegisterForClicks("AnyUp")
            local hl = item:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0)
            local lbl = item:CreateFontString(nil, "OVERLAY")
            lbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
            lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            lbl:SetJustifyH("LEFT")
            lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
            lbl:SetText(EllesmereUI.L(text))
            if isSelected then
                hl:SetColorTexture(1, 1, 1, 0.04)
                lbl:SetTextColor(1, 1, 1, 1)
            end
            item:SetScript("OnEnter", function()
                hl:SetColorTexture(1, 1, 1, 0.08)
                lbl:SetTextColor(1, 1, 1, 1)
            end)
            item:SetScript("OnLeave", function()
                if isSelected then
                    hl:SetColorTexture(1, 1, 1, 0.04)
                else
                    hl:SetColorTexture(1, 1, 1, 0)
                end
                lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            end)
            item:SetScript("OnClick", function()
                onClick()
                CloseSnapMenu()
                UpdateSnapLabel()
            end)
            items[#items + 1] = item
            yOff = yOff - ITEM_H
            return item
        end

        local curTarget = mover._snapTarget

        -- All Elements
        MakeItem(snapMenu, "All Elements", function()
            mover._snapTarget = nil
        end, not curTarget)

        -- None (per-mover snap disable)
        MakeItem(snapMenu, "None", function()
            mover._snapTarget = "_disable_"
        end, curTarget == "_disable_")

        -- Divider before element groups
        local div = snapMenu:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetColorTexture(1, 1, 1, 0.10)
        div:SetPoint("TOPLEFT", snapMenu, "TOPLEFT", 1, yOff - 4)
        div:SetPoint("TOPRIGHT", snapMenu, "TOPRIGHT", -1, yOff - 4)
        yOff = yOff - 9

        -- Registered element groups (Unit Frames, Action Bars, Resource Bars, etc.)
        RebuildRegisteredOrder()
        local regGroups = {}   -- { groupName = { {key,label}, ... } }
        local regGroupOrder = {} -- preserve first-seen order
        for _, rk in ipairs(registeredOrder) do
            if rk ~= barKey and movers[rk] and movers[rk]:IsShown() then
                local elem = registeredElements[rk]
                local gName = elem.group or "Other"
                if not regGroups[gName] then
                    regGroups[gName] = {}
                    regGroupOrder[#regGroupOrder + 1] = gName
                end
                regGroups[gName][#regGroups[gName] + 1] = { key = rk, label = elem.label or rk }
            end
        end
        -- Add visibility-only bars (MicroBar, BagBar) to "Other" group
        for _, bk in ipairs(ALL_BAR_ORDER) do
            if GetVisibilityOnly()[bk] and bk ~= barKey and movers[bk] and movers[bk]:IsShown() then
                if not regGroups["Other"] then
                    regGroups["Other"] = {}
                    regGroupOrder[#regGroupOrder + 1] = "Other"
                end
                regGroups["Other"][#regGroups["Other"] + 1] = { key = bk, label = GetBarLabel(bk) }
            end
        end
        wipe(regSubMenus)
        for _, gName in ipairs(regGroupOrder) do
            local gElems = regGroups[gName]
            local rgItem = CreateFrame("Button", nil, snapMenu)
            rgItem:SetHeight(ITEM_H)
            rgItem:SetPoint("TOPLEFT", snapMenu, "TOPLEFT", 1, yOff)
            rgItem:SetPoint("TOPRIGHT", snapMenu, "TOPRIGHT", -1, yOff)
            rgItem:SetFrameLevel(snapMenu:GetFrameLevel() + 2)
            rgItem:RegisterForClicks("AnyUp")
            local rgHl = rgItem:CreateTexture(nil, "ARTWORK")
            rgHl:SetAllPoints()
            rgHl:SetColorTexture(1, 1, 1, 0)
            local rgLbl = rgItem:CreateFontString(nil, "OVERLAY")
            rgLbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
            rgLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            rgLbl:SetJustifyH("LEFT")
            rgLbl:SetPoint("LEFT", rgItem, "LEFT", 10, 0)
            rgLbl:SetText(EllesmereUI.L(gName))
            local rgArrow = rgItem:CreateTexture(nil, "ARTWORK")
            rgArrow:SetSize(10, 10)
            rgArrow:SetPoint("RIGHT", rgItem, "RIGHT", -8, 0)
            rgArrow:SetTexture(ARROW_RIGHT_ICON)
            rgArrow:SetAlpha(0.7)
            yOff = yOff - ITEM_H

            local regSub
            local function ShowRegSub()
                -- Close any other open leaf sub-menus first
                for otherName, rs in pairs(regSubMenus) do
                    if otherName ~= gName and rs and rs:IsShown() then rs:Hide() end
                end
                if regSub then
                    for _, child in ipairs({regSub:GetChildren()}) do child:Hide(); child:SetParent(nil) end
                    for _, tex in ipairs({regSub:GetRegions()}) do if tex.Hide then tex:Hide() end end
                end
                regSub = regSub or CreateFrame("Frame", nil, unlockFrame)
                regSub:SetFrameStrata("FULLSCREEN_DIALOG")
                regSub:SetFrameLevel(260)
                regSub:SetClampedToScreen(true)
                regSub:SetSize(DD_W, 10)
                regSub:SetPoint("TOPLEFT", rgItem, "TOPRIGHT", 2, 0)
                local rsBg = regSub:CreateTexture(nil, "BACKGROUND")
                rsBg:SetAllPoints()
                rsBg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
                EllesmereUI.MakeBorder(regSub, 1, 1, 1, 0.20)
                local rsYOff = -4
                for _, eInfo in ipairs(gElems) do
                    local ek, eLbl = eInfo.key, eInfo.label
                    local isSel = (curTarget == ek)
                    local si = CreateFrame("Button", nil, regSub)
                    si:SetHeight(ITEM_H)
                    si:SetPoint("TOPLEFT", regSub, "TOPLEFT", 1, rsYOff)
                    si:SetPoint("TOPRIGHT", regSub, "TOPRIGHT", -1, rsYOff)
                    si:SetFrameLevel(regSub:GetFrameLevel() + 2)
                    si:RegisterForClicks("AnyUp")
                    local sHl = si:CreateTexture(nil, "ARTWORK")
                    sHl:SetAllPoints()
                    sHl:SetColorTexture(1, 1, 1, isSel and 0.04 or 0)
                    local sLbl = si:CreateFontString(nil, "OVERLAY")
                    sLbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
                    sLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    sLbl:SetJustifyH("LEFT")
                    sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                    sLbl:SetText(EllesmereUI.L(eLbl))
                    if isSel then sLbl:SetTextColor(1, 1, 1, 1) end
                    si:SetScript("OnEnter", function()
                        sHl:SetColorTexture(1, 1, 1, 0.08)
                        sLbl:SetTextColor(1, 1, 1, 1)
                    end)
                    si:SetScript("OnLeave", function()
                        sHl:SetColorTexture(1, 1, 1, isSel and 0.04 or 0)
                        sLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    end)
                    si:SetScript("OnClick", function()
                        mover._snapTarget = ek
                        CloseSnapMenu()
                        UpdateSnapLabel()
                    end)
                    rsYOff = rsYOff - ITEM_H
                end
                regSub:SetHeight(-rsYOff + 4)
                -- Width: fit the widest label + left padding (10) + right spacing (10) + border (2)
                local rsMaxW = DD_W
                for _, eInfo in ipairs(gElems) do
                    local tw = (EllesmereUI.MeasureText and EllesmereUI.MeasureText(eInfo.label, FONT_PATH, 11)) or 0
                    local needed = 10 + tw + 10 + 2
                    if needed > rsMaxW then rsMaxW = needed end
                end
                regSub:SetWidth(rsMaxW)
                regSub:EnableMouse(true)
                regSub:SetScript("OnLeave", function(self)
                    C_Timer.After(0.05, function()
                        if self:IsShown() and not self:IsMouseOver() and not rgItem:IsMouseOver() then
                            self:Hide()
                        end
                    end)
                end)
                regSub:Show()
                regSubMenus[gName] = regSub
            end

            rgItem:SetScript("OnEnter", function()
                rgHl:SetColorTexture(1, 1, 1, 0.08)
                rgLbl:SetTextColor(1, 1, 1, 1)
                rgArrow:SetAlpha(0.9)
                ShowRegSub()
            end)
            rgItem:SetScript("OnLeave", function()
                rgHl:SetColorTexture(1, 1, 1, 0)
                rgLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                rgArrow:SetAlpha(0.5)
                C_Timer.After(0.05, function()
                    local rs = regSubMenus[gName]
                    if rs and rs:IsShown() and not rs:IsMouseOver() and not rgItem:IsMouseOver() then
                        rs:Hide()
                    end
                end)
            end)
        end

        snapMenu:SetHeight(-yOff + 4)
        snapMenu:Show()
    end

    -- Click-catcher: full-screen invisible frame that closes the menu when clicking elsewhere
    local snapClickCatcher
    local function ShowClickCatcher()
        if not snapClickCatcher then
            snapClickCatcher = CreateFrame("Button", nil, unlockFrame)
            snapClickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            snapClickCatcher:SetFrameLevel(249)  -- just below snapMenu (250)
            snapClickCatcher:SetAllPoints(UIParent)
            snapClickCatcher:RegisterForClicks("AnyUp")
            snapClickCatcher:SetScript("OnClick", function()
                CloseSnapMenu()
            end)
        end
        snapClickCatcher:Show()
    end
    local function HideClickCatcher()
        if snapClickCatcher then snapClickCatcher:Hide() end
    end

    local origCloseSnapMenu = CloseSnapMenu
    CloseSnapMenu = function()
        origCloseSnapMenu()
        HideClickCatcher()
        mover._menuOpen = false
    end

    snapDD:SetScript("OnClick", function()
        -- Block opening when global snap is disabled
        if not snapEnabled then return end
        if snapMenu and snapMenu:IsShown() then
            CloseSnapMenu()
        else
            mover._menuOpen = true
            BuildSnapMenu()
            ShowClickCatcher()
        end
    end)

    -- Also close menu when dropdown hides (e.g. mover deselected)
    snapDD:SetScript("OnHide", CloseSnapMenu)

    ---------------------------------------------------------------------------
    --  Layout: cog flush with mover top-right (flips below if near screen top)
    ---------------------------------------------------------------------------
    local TOOLBAR_FLIP_THRESHOLD = 50  -- px from screen top to flip toolbar below

    local function IsNearScreenTop()
        local mTop = mover:GetTop()
        if not mTop then return false end
        local uiS = UIParent:GetEffectiveScale()
        local mS = mover:GetEffectiveScale()
        local screenTop = UIParent:GetHeight()
        local moverTopUI = mTop * mS / uiS
        return (screenTop - moverTopUI) < TOOLBAR_FLIP_THRESHOLD
    end
    mover._isNearScreenTop = IsNearScreenTop

    local function AnchorToolbarToMover()
        cogBtn:ClearAllPoints()
        cogBtn:SetPoint("TOPRIGHT", mover, "TOPRIGHT", -1, -1)
    end
    mover._anchorToolbar = AnchorToolbarToMover
    AnchorToolbarToMover()

    -- Hide orientation button for visibility-only bars or bars without layout support
    local isVisOnly = (GetVisibilityOnly()[barKey]) or not (BAR_LOOKUP and BAR_LOOKUP[barKey])

    mover._cogBtn = cogBtn
    mover._actionBtns = { cogBtn }

    -- Open snap menu helper (called from right-click handler)
    mover._openSnapMenu = function()
        mover._menuOpen = true
        BuildSnapMenu()
        ShowClickCatcher()
    end
    mover._isVisOnly = isVisOnly
    mover._snapTarget = nil  -- per-mover snap target (nil = auto)
    mover._updateSnapLabel = UpdateSnapLabel
    RefreshSnapDDState()  -- apply initial grayed-out state if snap is disabled

    ---------------------------------------------------------------------------
    --  Cog settings menu (Reset / Center / Orientation)
    ---------------------------------------------------------------------------
    local cogMenu
    local cogClickCatcher

    local function CloseCogMenu()
        if cogMenu then cogMenu:Hide() end
        if cogClickCatcher then cogClickCatcher:Hide() end
        mover._menuOpen = false
        mover._syncCogPos = nil
    end

    local function BuildCogMenu()
        if cogMenu then
            for _, child in ipairs({cogMenu:GetChildren()}) do child:Hide(); child:SetParent(nil) end
            for _, tex in ipairs({cogMenu:GetRegions()}) do if tex.Hide then tex:Hide() end end
        end
        cogMenu = cogMenu or CreateFrame("Frame", nil, unlockFrame)
        cogMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        cogMenu:SetFrameLevel(250)
        cogMenu:SetClampedToScreen(true)
        cogMenu:SetSize(DD_W + 60, 10)
        cogMenu:SetPoint("TOPLEFT", cogBtn, "BOTTOMLEFT", 0, -2)
        cogMenu:EnableMouse(true)

        local menuBg = cogMenu:CreateTexture(nil, "BACKGROUND")
        menuBg:SetAllPoints()
        menuBg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
        EllesmereUI.MakeBorder(cogMenu, 1, 1, 1, 0.20)

        local ITEM_H = 24
        local yOff = -4

        -- Arrow-key hint at the very top (centered). Shown for every element since
        -- arrow keys nudge the selected element 1px in any direction.
        do
            local hintFS = cogMenu:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(hintFS, true) end
            hintFS:SetFont(FONT_PATH, 10, "")
            hintFS:SetTextColor(0.7, 0.7, 0.7, 0.85)
            hintFS:SetJustifyH("CENTER")
            hintFS:SetWordWrap(true)
            hintFS:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 8, yOff - 4)
            hintFS:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -8, yOff - 4)
            hintFS:SetText(EllesmereUI.L("Use arrow keys to move selected element 1px any direction"))
            local hintH = hintFS:GetStringHeight()
            if not hintH or hintH < 1 then hintH = 28 end
            yOff = yOff - (hintH + 10)

            -- Divider below the hint
            local hintDiv = cogMenu:CreateTexture(nil, "ARTWORK")
            local hintDivPx = PP and PP.mult or 1
            hintDiv:SetHeight(hintDivPx)
            if hintDiv.SetSnapToPixelGrid then hintDiv:SetSnapToPixelGrid(false); hintDiv:SetTexelSnappingBias(0) end
            hintDiv:SetColorTexture(1, 1, 1, 0.10)
            hintDiv:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff - 4)
            hintDiv:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff - 4)
            yOff = yOff - 9
        end

        -- "Element Options" — navigate to this element's settings page (top of menu)
        local settingsMapping = EllesmereUI._ELEMENT_SETTINGS_MAP[barKey]
        -- Cooldown Manager bars use dynamic per-bar keys ("CDM_<key>" / "TBB_<idx>"),
        -- so they miss the exact lookup; resolve them to their shared tab entry by prefix.
        if not settingsMapping then
            if barKey:sub(1, 4) == "CDM_" then
                settingsMapping = EllesmereUI._ELEMENT_SETTINGS_MAP["CDM_"]
            elseif barKey:sub(1, 4) == "TBB_" then
                settingsMapping = EllesmereUI._ELEMENT_SETTINGS_MAP["TBB_"]
            end
        end
        -- Queue Status is a Blizzard-owned element with no EUI settings page; its
        -- "Element Options" opens Blizzard Edit Mode instead of navigating to a tab
        -- (the same action as clicking a Blizzard Edit Mode overlay in unlock mode).
        local opensEditMode = (barKey == "QueueStatus")
        if settingsMapping or opensEditMode then
            local optItem = CreateFrame("Button", nil, cogMenu)
            optItem:SetHeight(ITEM_H)
            optItem:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
            optItem:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
            optItem:SetFrameLevel(cogMenu:GetFrameLevel() + 2)
            optItem:RegisterForClicks("AnyUp")
            local optHl = optItem:CreateTexture(nil, "ARTWORK")
            optHl:SetAllPoints()
            optHl:SetColorTexture(1, 1, 1, 0)
            local optLbl = optItem:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(optLbl, true) end
            optLbl:SetFont(FONT_PATH, 11, "")
            optLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            optLbl:SetJustifyH("LEFT")
            optLbl:SetPoint("LEFT", optItem, "LEFT", 10, 0)
            optLbl:SetText(EllesmereUI.L("Element Options"))
            optItem:SetScript("OnEnter", function()
                optHl:SetColorTexture(1, 1, 1, 0.08)
                optLbl:SetTextColor(1, 1, 1, 1)
            end)
            optItem:SetScript("OnLeave", function()
                optHl:SetColorTexture(1, 1, 1, 0)
                optLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            end)
            optItem:SetScript("OnClick", function()
                CloseCogMenu()
                if opensEditMode then
                    -- Open Blizzard Edit Mode, exactly as the Blizz-owned overlays do.
                    if InCombatLockdown() then return end
                    if EditModeManagerFrame then
                        ns.RequestClose(false, function()
                            ShowUIPanel(EditModeManagerFrame)
                        end)
                    end
                else
                    ns.RequestClose(true, function()
                        EllesmereUI:NavigateToElementSettings(
                            settingsMapping.module,
                            settingsMapping.page,
                            settingsMapping.sectionName,
                            settingsMapping.preSelectFn,
                            settingsMapping.highlightText
                        )
                    end)
                end
            end)
            yOff = yOff - ITEM_H

            -- Divider after Element Options
            local optDiv = cogMenu:CreateTexture(nil, "ARTWORK")
            local optDivPx = PP and PP.mult or 1
            optDiv:SetHeight(optDivPx)
            if optDiv.SetSnapToPixelGrid then optDiv:SetSnapToPixelGrid(false); optDiv:SetTexelSnappingBias(0) end
            optDiv:SetColorTexture(1, 1, 1, 0.10)
            optDiv:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff - 4)
            optDiv:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff - 4)
            yOff = yOff - 9
        end

        -- Width / Height input fields (only for resizable elements)
        -- CDM bars skip width/height here; size is driven by icon count/size in the options panel
        local isCDMBar = barKey:sub(1, 4) == "CDM_"
        if canResize and elem then
            local INPUT_W = 50
            local INPUT_H = 18
            local ROW_H = 22
            local curW, curH = 0, 0
            if elem.getSize then curW, curH = elem.getSize(barKey) end

            -- Create both boxes upfront so each OnEnterPressed can update the other
            local wBox, hBox

            local function MakeSizeRow(axis, initVal)
                local rowFrame = CreateFrame("Frame", nil, cogMenu)
                rowFrame:SetHeight(ROW_H)
                rowFrame:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
                rowFrame:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
                rowFrame:SetFrameLevel(cogMenu:GetFrameLevel() + 2)

                local lbl = rowFrame:CreateFontString(nil, "OVERLAY")
                if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(lbl, true) end
                lbl:SetFont(FONT_PATH, 11, "")
                lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                lbl:SetJustifyH("LEFT")
                lbl:SetPoint("LEFT", rowFrame, "LEFT", 10, 0)
                lbl:SetText(axis)

                local box = CreateFrame("EditBox", nil, rowFrame)
                box:SetSize(INPUT_W, INPUT_H)
                box:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
                box:SetFrameLevel(cogMenu:GetFrameLevel() + 3)
                box:SetFont(FONT_PATH, 10, "")
                box:SetTextColor(1, 1, 1, 0.9)
                box:SetJustifyH("CENTER")
                local boxBg = box:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                boxBg:SetColorTexture(0, 0, 0, 0.4)
                box:SetAutoFocus(false)
                box:SetNumeric(true)
                box:SetMaxLetters(5)
                -- Display the element's native size (UI coords), matching getSize/setWidth
                -- and the options sliders. (Previously shown in physical pixels via ToPixels,
                -- which diverged from the actual setting at non-1.0 UI scales.)
                box:SetNumber(floor((initVal or 0) + 0.5))

                -- Disable if this element is width/height matched
                local isWidth = (axis == "Width")
                local matchTarget = isWidth and EllesmereUI.GetWidthMatchTarget(barKey) or (not isWidth and EllesmereUI.GetHeightMatchTarget(barKey))
                if matchTarget then
                    box:Disable()
                    box:SetTextColor(0.4, 0.4, 0.4, 0.7)
                    local targetName = GetBarLabel(matchTarget) or matchTarget
                    box:SetScript("OnEnter", function()
                        EllesmereUI.ShowWidgetTooltip(box,
                            axis .. " matched to " .. targetName .. ". Unmatch to edit.")
                    end)
                    box:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                end

                box:SetScript("OnEnterPressed", function(self)
                    -- Value is in the element's native UI coords (no physical-pixel conversion)
                    local val = math.max(1, math.floor(self:GetNumber() + 0.5))
                    local sb = GetBarFrame(barKey)
                    local savedAlpha = sb and EllesmereUI._GetFFD(sb).restoreAlpha
                    if sb and not savedAlpha then sb:SetAlpha(0) end
                    if axis == "Width" then
                        if elem.setWidth then elem.setWidth(barKey, val) end
                        for childKey, targetKey in pairs(MatchH.GetWidthMatchDB() or {}) do
                            if targetKey == barKey then MatchH.ApplyWidthMatch(childKey, barKey) end
                        end
                    else
                        if elem.setHeight then elem.setHeight(barKey, val) end
                        for childKey, targetKey in pairs(MatchH.GetHeightMatchDB() or {}) do
                            if targetKey == barKey then MatchH.ApplyHeightMatch(childKey, barKey) end
                        end
                    end
                    hasChanges = true
                    self:ClearFocus()
                    EllesmereUI.RecenterBarAnchor(barKey)
                    if sb and not savedAlpha then
                        C_Timer.After(0, function() sb:SetAlpha(1) end)
                    end
                    local bm = movers[barKey]
                    if bm then bm:SyncSize() end
                    for childKey, _ in pairs(movers) do
                        if movers[childKey] and movers[childKey].SyncSize then
                            local wm = MatchH.GetWidthMatchInfo(childKey)
                            local hm = MatchH.GetHeightMatchInfo(childKey)
                            if wm == barKey or hm == barKey then
                                movers[childKey]:SyncSize()
                            end
                        end
                    end
                    -- Refresh both input boxes to reflect actual post-resize dimensions
                    if elem.getSize then
                        local nw, nh = elem.getSize(barKey)
                        if wBox then wBox:SetNumber(floor((nw or 0) + 0.5)) end
                        if hBox then hBox:SetNumber(floor((nh or 0) + 0.5)) end
                    end
                    PropagateAnchorChain(barKey)
                end)
                box:SetScript("OnEscapePressed", function(self)
                    self:ClearFocus()
                    if elem.getSize then
                        local w2, h2 = elem.getSize(barKey)
                        self:SetNumber(floor((axis == "Width" and (w2 or 0) or (h2 or 0)) + 0.5))
                    end
                end)
                yOff = yOff - ROW_H
                return box
            end

            if not isCDMBar then
                wBox = MakeSizeRow("Width",  curW)
                hBox = MakeSizeRow("Height", curH)
            end

            -- X Position / Y Position rows (screen coords from center)
            do
                local sw = UIParent:GetWidth()
                local sh = UIParent:GetHeight()
                -- Current value of an axis as a physical-pixel COUNT, read from the
                -- bar's LIVE geometry. Displaying pixel counts (not raw UIParent
                -- units) makes +1 in the box equal exactly one physical pixel, i.e.
                -- one arrow-key nudge; PP.mult is only 1 at pixel-perfect UI scale.
                local function AxisToPx(ax)
                    local b = GetBarFrame(barKey)
                    local PPi = EllesmereUI and EllesmereUI.PP
                    if not b or not PPi or not PPi.ToPixels then return nil end
                    local bL, bR = b:GetLeft(), b:GetRight()
                    local bT, bB = b:GetTop(), b:GetBottom()
                    if not (bL and bR and bT and bB) then return nil end
                    local ratio = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    if ax == "X" then
                        return PPi.ToPixels(((bL + bR) * 0.5 * ratio) - sw * 0.5)
                    end
                    return PPi.ToPixels(((bT + bB) * 0.5 * ratio) - sh * 0.5)
                end

                local function MakePosRow(axis, initVal)
                    local rowFrame = CreateFrame("Frame", nil, cogMenu)
                    rowFrame:SetHeight(ROW_H)
                    rowFrame:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
                    rowFrame:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
                    rowFrame:SetFrameLevel(cogMenu:GetFrameLevel() + 2)

                    local lbl = rowFrame:CreateFontString(nil, "OVERLAY")
                    if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(lbl, true) end
                    lbl:SetFont(FONT_PATH, 11, "")
                    lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    lbl:SetJustifyH("LEFT")
                    lbl:SetPoint("LEFT", rowFrame, "LEFT", 10, 0)
                    lbl:SetText(axis == "X" and EllesmereUI.L("X Position") or EllesmereUI.L("Y Position"))

                    local box = CreateFrame("EditBox", nil, rowFrame)
                    box:SetSize(INPUT_W, INPUT_H)
                    box:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
                    box:SetFrameLevel(cogMenu:GetFrameLevel() + 3)
                    box:SetFont(FONT_PATH, 10, "")
                    box:SetTextColor(1, 1, 1, 0.9)
                    box:SetJustifyH("CENTER")
                    local boxBg = box:CreateTexture(nil, "BACKGROUND")
                    boxBg:SetAllPoints()
                    boxBg:SetColorTexture(0, 0, 0, 0.4)
                    box:SetAutoFocus(false)
                    box:SetNumeric(false)
                    box:SetMaxLetters(6)
                    box:SetText(tostring(initVal))

                    box:SetScript("OnEnterPressed", function(self)
                        local val = tonumber(self:GetText())
                        self:ClearFocus()
                        if not val then return end
                        local PPi = EllesmereUI and EllesmereUI.PP
                        if InCombatLockdown() or not PPi then return end
                        -- Current value from LIVE geometry (never the stale moverCX).
                        local curPx = AxisToPx(axis)
                        if not curPx then return end
                        local deltaPx = val - curPx
                        if deltaPx ~= 0 then
                            -- One physical pixel == PP.mult UIParent units. Apply an
                            -- exact integer-pixel delta through the SAME primitive the
                            -- arrow keys use, so anchored/unanchored handling, the
                            -- pending-save capture, and the mover-center re-sync all
                            -- match the proven path: no second snap, no lost move.
                            local stepUnits = PPi.FromPixels(deltaPx)
                            if axis == "X" then
                                EllesmereUI._unlockNudge(stepUnits, 0, mover, true)
                            else
                                EllesmereUI._unlockNudge(0, stepUnits, mover, true)
                            end
                        end
                        if mover.ReanchorToBar then mover:ReanchorToBar() end
                        -- Re-sync the text to where the bar ACTUALLY landed so it can
                        -- never snap back to the old number.
                        local landed = AxisToPx(axis)
                        if landed then self:SetText(tostring(landed)) end
                    end)
                    box:SetScript("OnEscapePressed", function(self)
                        self:ClearFocus()
                        -- Discard typed text; show the bar's actual current value.
                        local cur = AxisToPx(axis)
                        self:SetText(tostring(cur or initVal))
                    end)
                    yOff = yOff - ROW_H
                    return box
                end

                local xBox = MakePosRow("X", AxisToPx("X") or 0)
                local yBox = MakePosRow("Y", AxisToPx("Y") or 0)
                -- Let arrow-key nudges (while the cog is open) refresh these boxes
                -- so they stay in lockstep with the element and the floating overlay.
                mover._syncCogPos = function()
                    if xBox then local px = AxisToPx("X"); if px then xBox:SetText(tostring(px)) end end
                    if yBox then local py = AxisToPx("Y"); if py then yBox:SetText(tostring(py)) end end
                end
            end

            -- Divider after size/position inputs
            local sizeDiv = cogMenu:CreateTexture(nil, "ARTWORK")
            local sizeDivPx = PP and PP.mult or 1
            sizeDiv:SetHeight(sizeDivPx)
            if sizeDiv.SetSnapToPixelGrid then sizeDiv:SetSnapToPixelGrid(false); sizeDiv:SetTexelSnappingBias(0) end
            sizeDiv:SetColorTexture(1, 1, 1, 0.10)
            sizeDiv:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff - 4)
            sizeDiv:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff - 4)
            yOff = yOff - 9
        end
        -- Snap Target: enter pick mode or clear existing target
        local selElemItem = CreateFrame("Button", nil, cogMenu)
        selElemItem:SetHeight(ITEM_H)
        selElemItem:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
        selElemItem:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
        selElemItem:SetFrameLevel(cogMenu:GetFrameLevel() + 2)
        selElemItem:RegisterForClicks("AnyUp")
        local selElemHl = selElemItem:CreateTexture(nil, "ARTWORK")
        selElemHl:SetAllPoints()
        selElemHl:SetColorTexture(1, 1, 1, 0)
        local selElemLbl = selElemItem:CreateFontString(nil, "OVERLAY")
        if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(selElemLbl, true) end
        selElemLbl:SetFont(FONT_PATH, 11, "")
        selElemLbl:SetJustifyH("LEFT")
        selElemLbl:SetPoint("LEFT", selElemItem, "LEFT", 10, 0)
        local curTgt = mover._snapTarget
        local hasTarget = curTgt and curTgt ~= "_disable_" and curTgt ~= "_select_"
        if hasTarget then
            local tgtName = GetBarLabel(curTgt) or curTgt
            selElemLbl:SetText(EllesmereUI.Lf("Snap Target: %1$s", "|cFF0CD29D" .. tgtName .. "|r"))
            selElemLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
        else
            selElemLbl:SetText(EllesmereUI.L("Select Snap Target"))
            selElemLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
        end
        selElemItem:SetScript("OnEnter", function()
            selElemHl:SetColorTexture(1, 1, 1, 0.08)
            selElemLbl:SetTextColor(1, 1, 1, 1)
        end)
        selElemItem:SetScript("OnLeave", function()
            selElemHl:SetColorTexture(1, 1, 1, 0)
            selElemLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
        end)
        selElemItem:SetScript("OnClick", function()
            if hasTarget then
                mover._snapTarget = nil
                UpdateSnapLabel()
                CloseCogMenu()
            else
                mover._preSelectTarget = mover._snapTarget
                mover._snapTarget = "_select_"
                selectElementPicker = mover
                FadeOverlayForSelectElement(true)
                UpdateSnapLabel()
                CloseCogMenu()
            end
        end)
        yOff = yOff - ITEM_H

        -- Helper: menu action item
        local function MakeActionItem(text, onClick)
            local item = CreateFrame("Button", nil, cogMenu)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
            item:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
            item:SetFrameLevel(cogMenu:GetFrameLevel() + 2)
            item:RegisterForClicks("AnyUp")
            local hl = item:CreateTexture(nil, "ARTWORK")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0)
            local lbl = item:CreateFontString(nil, "OVERLAY")
            if EllesmereUI and EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(lbl, true) end
            lbl:SetFont(FONT_PATH, 11, "")
            lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            lbl:SetJustifyH("LEFT")
            lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
            lbl:SetText(EllesmereUI.L(text))
            item:SetScript("OnEnter", function()
                hl:SetColorTexture(1, 1, 1, 0.08)
                lbl:SetTextColor(1, 1, 1, 1)
            end)
            item:SetScript("OnLeave", function()
                hl:SetColorTexture(1, 1, 1, 0)
                lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            end)
            item:SetScript("OnClick", function()
                CloseCogMenu()
                onClick()
            end)
            yOff = yOff - ITEM_H
            return item
        end

        -- Center on Screen
        MakeActionItem("Center on Screen", function()
            if InCombatLockdown() then return end
            local bk = mover._barKey
            local screenCX = UIParent:GetWidth() * 0.5
            local mT = mover:GetTop()
            local mB = mover:GetBottom()
            if not mT or not mB then return end
            -- Center mover horizontally, keep vertical position
            local cx = screenCX
            local cy = (mT + mB) * 0.5 - UIParent:GetHeight()
            mover:ClearAllPoints()
            mover:SetPoint("CENTER", UIParent, "TOPLEFT", cx, cy)
            moverCX = cx
            moverCY = cy
            local b = GetBarFrame(bk)
            if b then
                -- Use same formula as drag-stop: cx/cy are mover center coords.
                -- cx is screen-space X. cy is UIParent-TOPLEFT Y (negative).
                local uiS = UIParent:GetEffectiveScale()
                local bS = b:GetEffectiveScale()
                local ratio = uiS / bS
                local barHW = (b:GetWidth() or 0) * 0.5
                local barHH = (b:GetHeight() or 0) * 0.5
                -- Strip centerYOff so Sync() doesn't double-apply it
                local centerYOff = 0
                local elem = registeredElements[bk]
                if elem and elem.getSize then
                    local _, _, gyOff = elem.getSize(bk)
                    centerYOff = gyOff or 0
                end
                local barX = cx * ratio - barHW
                local barY = (cy - centerYOff) * ratio + barHH
                local PPc = EllesmereUI and EllesmereUI.PP
                if PPc and PPc.SnapForES then
                    barX = PPc.SnapForES(barX, bS)
                    barY = PPc.SnapForES(barY, bS)
                end
                pcall(function()
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", barX, barY)
                end)
                pendingPositions[bk] = {
                    point = "TOPLEFT", relPoint = "TOPLEFT",
                    x = barX, y = barY,
                }
                hasChanges = true
            end
            -- Update coordinate readout after centering
            if mover.UpdateCoordText then mover:UpdateCoordText() end
            -- Re-anchor mover to bar for pixel-perfect alignment
            mover:ReanchorToBar()
            -- Move anchored children with us
            PropagateAnchorChain(bk)
            -- Collapse the mover if the mouse moved away during centering
            C_Timer.After(0.15, function()
                if not mover:IsMouseOver() and not (mover._cogBtn and mover._cogBtn:IsMouseOver()) then
                    if mover._hideOverlayText then mover._hideOverlayText() end
                    if hoveredMover == mover then hoveredMover = nil end
                    mover._hoverPending = false
                    if not mover._selected then
                        mover:SetFrameLevel(mover._baseLevel)
                    end
                end
            end)
        end)

        -- Toggle Orientation (hidden for vis-only bars)
        if not isVisOnly then
            MakeActionItem("Toggle Orientation", function()
                if InCombatLockdown() then return end
                if not EAB then return end
                EAB:ToggleOrientationForBar(mover._barKey)
                hasChanges = true
                DeferMoverSync(movers[mover._barKey], function(m) m:Sync() end, GetBarFrame(mover._barKey))
            end)
        end

        cogMenu:SetHeight(-yOff + 4)
        cogMenu:Show()
    end

    -- Click-catcher for cog menu
    local function ShowCogClickCatcher()
        if not cogClickCatcher then
            cogClickCatcher = CreateFrame("Button", nil, unlockFrame)
            cogClickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            cogClickCatcher:SetFrameLevel(249)
            cogClickCatcher:SetAllPoints(UIParent)
            cogClickCatcher:RegisterForClicks("AnyUp")
            cogClickCatcher:SetScript("OnClick", function()
                CloseCogMenu()
            end)
        end
        cogClickCatcher:Show()
    end

    cogBtn:SetScript("OnClick", function()
        if cogMenu and cogMenu:IsShown() then
            CloseCogMenu()
        else
            SelectMover(mover)
            mover._menuOpen = true
            BuildCogMenu()
            ShowCogClickCatcher()
        end
    end)
    cogBtn:SetScript("OnHide", CloseCogMenu)

    -- Expose cog menu opener on the mover (used by right-click handler)
    mover._openCogMenu = function()
        if cogMenu and cogMenu:IsShown() then
            CloseCogMenu()
        else
            SelectMover(mover)
            mover._menuOpen = true
            BuildCogMenu()
            ShowCogClickCatcher()
        end
    end

    movers[barKey] = mover
    return mover
end

-- Override RegisterUnlockElements so that late-registering addons (e.g. CDM
-- registering after a 0.5s timer) get movers spawned immediately if unlock
-- mode is already open when they call in.
do
    local _origRegister = EllesmereUI.RegisterUnlockElements
    function EllesmereUI:RegisterUnlockElements(elements, folder)
        _origRegister(self, elements, folder)
        if not isUnlocked then return end
        -- Unlock mode is open -- spawn movers for any newly registered keys,
        -- and hide existing movers whose element is now intentionally hidden.
        local spawned = false
        for _, elem in ipairs(elements) do
            local key = elem.key
            if movers[key] then
                -- Re-registration: hide mover if element is now hidden
                if elem.isHidden and elem.isHidden() then
                    movers[key]:Hide()
                end
            else
                local m = CreateMover(key)
                if m then
                    m:Sync()
                    m:SetAlpha(darkOverlaysEnabled and 1 or MOVER_ALPHA)
                    m:Show()
                    spawned = true
                end
            end
        end
        if spawned then
            SortMoverFrameLevels()
            ReapplyAllAnchors()
        end
    end
end

-------------------------------------------------------------------------------
--  Top Banner Bar
--  Single pre-rendered banner image (eui-unlocked-banner.png, 1144x120).
--  Displayed pixel-perfect at native resolution, flush with top of screen.
--  Grid + magnet toggle icons overlaid on top.
--  Slides down from above screen during the SHACKLE animation phase.
-------------------------------------------------------------------------------
local GRID_ICON       = "Interface\\AddOns\\EllesmereUI\\media\\icons\\grid.png"
local MAGNET_ICON     = "Interface\\AddOns\\EllesmereUI\\media\\icons\\magnet.png"
local FLASHLIGHT_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\flashlight.png"
local HOVER_ICON      = "Interface\\AddOns\\EllesmereUI\\media\\icons\\hover.png"
local DARK_OVERLAY_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\dark-overlay.png"
local COORD_ICON      = "Interface\\AddOns\\EllesmereUI\\media\\icons\\coordinates.png"
local BANNER_TEX      = "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-banner-2.png"

local HUD_ON_ALPHA  = 0.60
local HUD_OFF_ALPHA = 0.30
local HUD_ICON_SZ   = 20

-- Banner native pixel dimensions
local BANNER_PX_W = 1144
local BANNER_PX_H = 120

local hudFrame

local function CreateHUD(parent)
    if hudFrame then return hudFrame end

    local ar, ag, ab = GetAccent()

    -- Load saved settings
    if EllesmereUIDB then
        if EllesmereUIDB.unlockGridMode == nil then EllesmereUIDB.unlockGridMode = "dimmed" end
        if EllesmereUIDB.unlockSnapEnabled == nil then EllesmereUIDB.unlockSnapEnabled = true end
    end
    gridMode = (EllesmereUIDB and EllesmereUIDB.unlockGridMode) or "dimmed"
    snapEnabled = (EllesmereUIDB and EllesmereUIDB.unlockSnapEnabled ~= false) or true

    -- Pixel-perfect scale: 1 frame unit = 1 physical screen pixel
    local physW = (GetPhysicalScreenSize())
    local uiScale = GetScreenWidth() / physW
    -- At very low UI scales the top bar gets too small to read; enlarge it 15%.
    -- Bumping the base here propagates through every downstream scale use
    -- (initial scale, user banner scale, slide-in offsets read GetScale()).
    if UIParent:GetEffectiveScale() < 0.6 then uiScale = uiScale * 1.08 end

    hudFrame = CreateFrame("Frame", nil, parent)
    hudFrame:SetFrameStrata("TOOLTIP")
    hudFrame:SetFrameLevel(900)
    hudFrame:SetSize(BANNER_PX_W, BANNER_PX_H)
    hudFrame:SetScale(uiScale)
    hudFrame:EnableMouse(false)  -- background only, clicks pass through
    -- Start off-screen above
    hudFrame:SetPoint("TOP", UIParent, "TOP", 0, (BANNER_PX_H + 10) * uiScale)

    -- Banner image at native resolution
    local bannerTex = hudFrame:CreateTexture(nil, "ARTWORK")
    bannerTex:SetTexture(BANNER_TEX)
    bannerTex:SetSize(BANNER_PX_W, BANNER_PX_H)
    bannerTex:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", 0, 0)
    if bannerTex.SetSnapToPixelGrid then bannerTex:SetSnapToPixelGrid(false); bannerTex:SetTexelSnappingBias(0) end
    hudFrame._bannerTex = bannerTex

    -- Icons at native 28x28 resolution (banner frame is already pixel-perfect scaled)
    -- Vertically centered within the 58px visible banner area, shifted up 1px
    local iconSz = 28
    local BANNER_VIS_H = 58
    local iconCenterY = -(BANNER_VIS_H / 2) + 1  -- -28px from top (centered + 1px up)

    -- Helper: shared hover/click behavior for icon+label wrapper buttons
    local function SetupToggleBtn(wrapper, iconTex, labelFS, getState, setState)
        wrapper:SetScript("OnClick", function() setState() end)
        wrapper:SetScript("OnEnter", function()
            iconTex:SetAlpha(0.9)
            labelFS:SetTextColor(1, 1, 1, 0.9)
        end)
        wrapper:SetScript("OnLeave", function()
            local a = getState() and HUD_ON_ALPHA or HUD_OFF_ALPHA
            iconTex:SetAlpha(a)
            labelFS:SetTextColor(1, 1, 1, a)
        end)
    end

    ---------------------------------------------------------------
    --  Grid toggle (left of center): label LEFT of icon
    ---------------------------------------------------------------
    local gridBtn = CreateFrame("Button", nil, hudFrame)
    -- Size will be set after label is created to encompass icon + gap + label
    gridBtn:SetPoint("RIGHT", hudFrame, "TOP", -80 + iconSz / 2, iconCenterY)

    local gridTex = gridBtn:CreateTexture(nil, "OVERLAY")
    gridTex:SetSize(iconSz, iconSz)
    gridTex:SetPoint("RIGHT", gridBtn, "RIGHT", 0, 0)
    gridTex:SetTexture(GRID_ICON)
    gridTex:SetAlpha(GridHudAlpha())
    gridBtn._tex = gridTex

    local gridLabel = gridBtn:CreateFontString(nil, "OVERLAY")
    gridLabel:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
    gridLabel:SetJustifyH("RIGHT")
    gridLabel:SetPoint("RIGHT", gridTex, "LEFT", -5, 0)
    gridLabel:SetTextColor(1, 1, 1, GridHudAlpha())
    gridLabel:SetText(GridLabelText())
    gridBtn._label = gridLabel

    -- Size wrapper to fit label + gap + icon
    local gridLabelW = gridLabel:GetStringWidth() or 80
    gridBtn:SetSize(gridLabelW + 5 + iconSz, max(iconSz, 24))

    -- Custom 3-state toggle (not using SetupToggleBtn)
    gridBtn:SetScript("OnClick", function()
        CycleGridMode()
        if EllesmereUIDB then EllesmereUIDB.unlockGridMode = gridMode end
        local a = GridHudAlpha()
        gridTex:SetAlpha(a)
        gridLabel:SetTextColor(1, 1, 1, a)
        gridLabel:SetText(GridLabelText())
        if gridFrame then
            if gridMode ~= "disabled" then
                gridFrame:Rebuild()
                gridFrame:Show()
            else
                gridFrame:Hide()
            end
        end
    end)
    gridBtn:SetScript("OnEnter", function()
        gridTex:SetAlpha(0.9)
        gridLabel:SetTextColor(1, 1, 1, 0.9)
    end)
    gridBtn:SetScript("OnLeave", function()
        local a = GridHudAlpha()
        gridTex:SetAlpha(a)
        gridLabel:SetTextColor(1, 1, 1, a)
    end)
    hudFrame._gridBtn = gridBtn

    ---------------------------------------------------------------
    --  Dark Overlays toggle (left of grid): label LEFT of icon
    ---------------------------------------------------------------
    local darkOverlayBtn = CreateFrame("Button", nil, hudFrame)
    darkOverlayBtn:SetPoint("RIGHT", gridBtn, "LEFT", -20, 0)

    local darkOverlayTex = darkOverlayBtn:CreateTexture(nil, "OVERLAY")
    darkOverlayTex:SetSize(iconSz, iconSz)
    darkOverlayTex:SetPoint("RIGHT", darkOverlayBtn, "RIGHT", 0, 0)
    darkOverlayTex:SetTexture(DARK_OVERLAY_ICON)
    darkOverlayTex:SetAlpha(darkOverlaysEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    darkOverlayBtn._tex = darkOverlayTex

    local darkOverlayLabel = darkOverlayBtn:CreateFontString(nil, "OVERLAY")
    darkOverlayLabel:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
    darkOverlayLabel:SetJustifyH("RIGHT")
    darkOverlayLabel:SetPoint("RIGHT", darkOverlayTex, "LEFT", -5, 0)
    darkOverlayLabel:SetTextColor(1, 1, 1, darkOverlaysEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    darkOverlayLabel:SetText(darkOverlaysEnabled and EllesmereUI.L("Dark Overlays\nEnabled") or EllesmereUI.L("Dark Overlays\nDisabled"))
    darkOverlayBtn._label = darkOverlayLabel

    local darkOverlayLabelW = darkOverlayLabel:GetStringWidth() or 80
    darkOverlayBtn:SetSize(darkOverlayLabelW + 5 + iconSz, max(iconSz, 24))

    SetupToggleBtn(darkOverlayBtn, darkOverlayTex, darkOverlayLabel,
        function() return darkOverlaysEnabled end,
        function()
            darkOverlaysEnabled = not darkOverlaysEnabled
            darkOverlayTex:SetAlpha(darkOverlaysEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            darkOverlayLabel:SetTextColor(1, 1, 1, darkOverlaysEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            darkOverlayLabel:SetText(darkOverlaysEnabled and EllesmereUI.L("Dark Overlays\nEnabled") or EllesmereUI.L("Dark Overlays\nDisabled"))
            ApplyDarkOverlays()
        end)
    hudFrame._darkOverlayBtn = darkOverlayBtn

    ---------------------------------------------------------------
    --  Flashlight toggle (left of grid): label LEFT of icon
    ---------------------------------------------------------------
    local flashBtn = CreateFrame("Button", nil, hudFrame)
    flashBtn:SetPoint("RIGHT", darkOverlayBtn, "LEFT", -20, 0)

    local flashTex = flashBtn:CreateTexture(nil, "OVERLAY")
    flashTex:SetSize(iconSz, iconSz)
    flashTex:SetPoint("RIGHT", flashBtn, "RIGHT", 0, 0)
    flashTex:SetTexture(FLASHLIGHT_ICON)
    flashTex:SetAlpha(flashlightEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    flashBtn._tex = flashTex

    local flashLabel = flashBtn:CreateFontString(nil, "OVERLAY")
    flashLabel:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
    flashLabel:SetJustifyH("RIGHT")
    flashLabel:SetPoint("RIGHT", flashTex, "LEFT", -5, 0)
    flashLabel:SetTextColor(1, 1, 1, flashlightEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    flashLabel:SetText(flashlightEnabled and EllesmereUI.L("Cursor Light\nEnabled") or EllesmereUI.L("Cursor Light\nDisabled"))
    flashBtn._label = flashLabel

    local flashLabelW = flashLabel:GetStringWidth() or 80
    flashBtn:SetSize(flashLabelW + 5 + iconSz, max(iconSz, 24))

    SetupToggleBtn(flashBtn, flashTex, flashLabel,
        function() return flashlightEnabled end,
        function()
            flashlightEnabled = not flashlightEnabled
            flashTex:SetAlpha(flashlightEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            flashLabel:SetTextColor(1, 1, 1, flashlightEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            flashLabel:SetText(flashlightEnabled and EllesmereUI.L("Cursor Light\nEnabled") or EllesmereUI.L("Cursor Light\nDisabled"))
        end)
    hudFrame._flashBtn = flashBtn

    ---------------------------------------------------------------
    --  Magnet/Snap toggle (right of center): label RIGHT of icon
    ---------------------------------------------------------------
    local magnetBtn = CreateFrame("Button", nil, hudFrame)
    magnetBtn:SetPoint("LEFT", hudFrame, "TOP", 76 - iconSz / 2, iconCenterY)

    local magnetTex = magnetBtn:CreateTexture(nil, "OVERLAY")
    magnetTex:SetSize(iconSz, iconSz)
    magnetTex:SetPoint("LEFT", magnetBtn, "LEFT", 0, 0)
    magnetTex:SetTexture(MAGNET_ICON)
    magnetTex:SetAlpha(snapEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    magnetBtn._tex = magnetTex

    local magnetLabel = magnetBtn:CreateFontString(nil, "OVERLAY")
    magnetLabel:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
    magnetLabel:SetJustifyH("LEFT")
    magnetLabel:SetPoint("LEFT", magnetTex, "RIGHT", 5, 0)
    magnetLabel:SetTextColor(1, 1, 1, snapEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    magnetLabel:SetText(snapEnabled and EllesmereUI.L("Snap Elements\nEnabled") or EllesmereUI.L("Snap Elements\nDisabled"))
    magnetBtn._label = magnetLabel

    local magnetLabelW = magnetLabel:GetStringWidth() or 100
    magnetBtn:SetSize(iconSz + 5 + magnetLabelW, max(iconSz, 24))

    SetupToggleBtn(magnetBtn, magnetTex, magnetLabel,
        function() return snapEnabled end,
        function()
            snapEnabled = not snapEnabled
            if EllesmereUIDB then EllesmereUIDB.unlockSnapEnabled = snapEnabled end
            magnetTex:SetAlpha(snapEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            magnetLabel:SetTextColor(1, 1, 1, snapEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            magnetLabel:SetText(snapEnabled and EllesmereUI.L("Snap Elements\nEnabled") or EllesmereUI.L("Snap Elements\nDisabled"))
            -- Refresh all movers' snap dropdown visual state
            for _, m in pairs(movers) do
                if m._refreshSnapDD then m._refreshSnapDD() end
            end
        end)
    hudFrame._magnetBtn = magnetBtn

    ---------------------------------------------------------------
    --  Coordinates toggle (right of snap): label RIGHT of icon
    ---------------------------------------------------------------
    local coordBtn = CreateFrame("Button", nil, hudFrame)
    coordBtn:SetPoint("LEFT", magnetBtn, "RIGHT", 7, 0)

    local coordTex = coordBtn:CreateTexture(nil, "OVERLAY")
    coordTex:SetSize(iconSz, iconSz)
    coordTex:SetPoint("LEFT", coordBtn, "LEFT", 0, 0)
    coordTex:SetTexture(COORD_ICON)
    coordTex:SetAlpha(coordsEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    coordBtn._tex = coordTex

    local coordLabel = coordBtn:CreateFontString(nil, "OVERLAY")
    coordLabel:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
    coordLabel:SetJustifyH("LEFT")
    coordLabel:SetPoint("LEFT", coordTex, "RIGHT", 1, 0)
    coordLabel:SetTextColor(1, 1, 1, coordsEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    coordLabel:SetText(coordsEnabled and EllesmereUI.L("Coordinates\nEnabled") or EllesmereUI.L("Coordinates\nDisabled"))
    coordBtn._label = coordLabel

    local coordLabelW = coordLabel:GetStringWidth() or 110
    coordBtn:SetSize(iconSz + 5 + coordLabelW, max(iconSz, 24))

    SetupToggleBtn(coordBtn, coordTex, coordLabel,
        function() return coordsEnabled end,
        function()
            coordsEnabled = not coordsEnabled
            coordTex:SetAlpha(coordsEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            coordLabel:SetTextColor(1, 1, 1, coordsEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            coordLabel:SetText(coordsEnabled and EllesmereUI.L("Coordinates\nEnabled") or EllesmereUI.L("Coordinates\nDisabled"))
            -- Show or hide coords for all movers based on new state
            for _, m in pairs(movers) do
                if m._coordFS then
                    if coordsEnabled then
                        if m.UpdateCoordText then m:UpdateCoordText() end
                    else
                        -- Only keep visible on the currently selected mover
                        if not m._selected then
                            m._coordFS:Hide()
                        end
                    end
                end
            end
        end)
    hudFrame._coordBtn = coordBtn

    ---------------------------------------------------------------
    --  Hover toggle (right of coords): label RIGHT of icon
    ---------------------------------------------------------------
    local hoverBtn = CreateFrame("Button", nil, hudFrame)
    hoverBtn:SetPoint("LEFT", coordBtn, "RIGHT", 2, 0)

    local hoverTex = hoverBtn:CreateTexture(nil, "OVERLAY")
    hoverTex:SetSize(iconSz, iconSz)
    hoverTex:SetPoint("LEFT", hoverBtn, "LEFT", 0, 0)
    hoverTex:SetTexture(HOVER_ICON)
    hoverTex:SetAlpha(hoverBarEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    hoverBtn._tex = hoverTex

    local hoverLabel = hoverBtn:CreateFontString(nil, "OVERLAY")
    hoverLabel:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
    hoverLabel:SetJustifyH("LEFT")
    hoverLabel:SetPoint("LEFT", hoverTex, "RIGHT", 5, 0)
    hoverLabel:SetTextColor(1, 1, 1, hoverBarEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    hoverLabel:SetText(hoverBarEnabled and EllesmereUI.L("Hover Top Bar\nEnabled") or EllesmereUI.L("Hover Top Bar\nDisabled"))
    hoverBtn._label = hoverLabel

    local hoverLabelW = hoverLabel:GetStringWidth() or 110
    hoverBtn:SetSize(iconSz + 5 + hoverLabelW, max(iconSz, 24))

    SetupToggleBtn(hoverBtn, hoverTex, hoverLabel,
        function() return hoverBarEnabled end,
        function()
            hoverBarEnabled = not hoverBarEnabled
            hoverTex:SetAlpha(hoverBarEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            hoverLabel:SetTextColor(1, 1, 1, hoverBarEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            hoverLabel:SetText(hoverBarEnabled and EllesmereUI.L("Hover Top Bar\nEnabled") or EllesmereUI.L("Hover Top Bar\nDisabled"))
        end)
    hudFrame._hoverBtn = hoverBtn

    ---------------------------------------------------------------
    --  Exit (left) and Save & Exit (right) buttons
    --  Vertically centered in the 58px visible banner area.
    --  Positioned ~50px from left/right edges of the banner.
    ---------------------------------------------------------------
    local BTN_H = 26
    local BTN_FONT = 10
    local btnCenterY = iconCenterY  -- same vertical center as icons

    -- Exit button (left side, 90px from left edge)
    local exitBtn = CreateFrame("Button", nil, hudFrame)
    exitBtn:SetSize(60, BTN_H)
    exitBtn:SetPoint("LEFT", hudFrame, "TOPLEFT", 85, btnCenterY)
    EllesmereUI.MakeStyledButton(exitBtn, "Exit", BTN_FONT,
        EllesmereUI.RB_COLOURS, function() ns.RequestClose(false) end)
    hudFrame._exitBtn = exitBtn

    -- Save & Exit button (right side, 50px from right edge, green "Done" style)
    do
        local btn = CreateFrame("Button", nil, hudFrame)
        btn:SetSize(90, BTN_H)
        btn:SetPoint("RIGHT", hudFrame, "TOPRIGHT", -85, btnCenterY)
        btn:SetFrameLevel(hudFrame:GetFrameLevel() + 2)

        local eg = EllesmereUI.ELLESMERE_GREEN or { r = 12/255, g = 210/255, b = 157/255 }
        EllesmereUI.MakeBorder(btn, eg.r, eg.g, eg.b, 0.7)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.08, 0.10, 0.92)

        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT_PATH, BTN_FONT, "OUTLINE, SLUG")
        lbl:SetPoint("CENTER")
        lbl:SetText(EllesmereUI.L("Save & Exit"))
        lbl:SetTextColor(eg.r, eg.g, eg.b, 0.7)

        local FADE_DUR = 0.1
        local progress, target = 0, 0
        local function lerp(a, b, t) return a + (b - a) * t end
        local function Apply(t)
            local c = EllesmereUI.ELLESMERE_GREEN or eg
            lbl:SetTextColor(c.r, c.g, c.b, lerp(0.7, 1, t))
        end
        local function OnUpdate(self, elapsed)
            local dir = (target == 1) and 1 or -1
            progress = progress + dir * (elapsed / FADE_DUR)
            if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                progress = target; self:SetScript("OnUpdate", nil)
            end
            Apply(progress)
        end
        btn:SetScript("OnEnter", function(self) target = 1; self:SetScript("OnUpdate", OnUpdate) end)
        btn:SetScript("OnLeave", function(self) target = 0; self:SetScript("OnUpdate", OnUpdate) end)
        btn:SetScript("OnClick", function() ns.RequestClose(true) end)
        hudFrame._saveBtn = btn
    end

    ---------------------------------------------------------------
    --  Banner Scale +/- Buttons
    --  Positioned at the far left (-) and far right (+) of the
    --  banner.  Scale range: 100% to 150% in 10% steps.
    --  Saved to EllesmereUIDB.unlockBannerScale.
    ---------------------------------------------------------------
    do
        local SCALE_MIN = 1.0
        local SCALE_MAX = 1.5
        local SCALE_STEP = 0.1
        local DISABLED_R, DISABLED_G, DISABLED_B = 0.35, 0.35, 0.35
        local NORMAL_R, NORMAL_G, NORMAL_B = 1, 1, 1
        local HOVER_R, HOVER_G, HOVER_B = 1, 1, 1
        local NORMAL_A = 0.50
        local HOVER_A  = 0.90
        local FONT_SZ  = 26

        -- Load saved banner scale
        local bannerUserScale = 1.0
        if EllesmereUIDB and EllesmereUIDB.unlockBannerScale then
            bannerUserScale = EllesmereUIDB.unlockBannerScale
            if bannerUserScale < SCALE_MIN then bannerUserScale = SCALE_MIN end
            if bannerUserScale > SCALE_MAX then bannerUserScale = SCALE_MAX end
        end

        -- Apply initial scale (uiScale * userScale)
        hudFrame:SetScale(uiScale * bannerUserScale)

        local minusBtn, plusBtn  -- forward refs for cross-refresh

        local function RefreshScaleBtns()
            local atMin = bannerUserScale <= SCALE_MIN + 0.001
            local atMax = bannerUserScale >= SCALE_MAX - 0.001
            -- Minus
            if atMin then
                minusBtn._shadow:SetTextColor(DISABLED_R, DISABLED_G, DISABLED_B, NORMAL_A * 0.6)
                minusBtn._label:SetTextColor(DISABLED_R, DISABLED_G, DISABLED_B, NORMAL_A)
                minusBtn:EnableMouse(true)  -- still catch hover for tooltip
                minusBtn._isDisabled = true
            else
                minusBtn._shadow:SetTextColor(0, 0, 0, NORMAL_A)
                minusBtn._label:SetTextColor(NORMAL_R, NORMAL_G, NORMAL_B, NORMAL_A)
                minusBtn._isDisabled = false
            end
            -- Plus
            if atMax then
                plusBtn._shadow:SetTextColor(DISABLED_R, DISABLED_G, DISABLED_B, NORMAL_A * 0.6)
                plusBtn._label:SetTextColor(DISABLED_R, DISABLED_G, DISABLED_B, NORMAL_A)
                plusBtn:EnableMouse(true)
                plusBtn._isDisabled = true
            else
                plusBtn._shadow:SetTextColor(0, 0, 0, NORMAL_A)
                plusBtn._label:SetTextColor(NORMAL_R, NORMAL_G, NORMAL_B, NORMAL_A)
                plusBtn._isDisabled = false
            end
        end

        local function ApplyBannerScale(newScale)
            newScale = max(SCALE_MIN, min(SCALE_MAX, newScale))
            bannerUserScale = newScale
            if EllesmereUIDB then EllesmereUIDB.unlockBannerScale = newScale end
            hudFrame:SetScale(uiScale * newScale)
            -- Keep flush with top of screen
            hudFrame:ClearAllPoints()
            hudFrame:SetPoint("TOP", UIParent, "TOP", 0, 0)
            -- Resize hover zone to match new scale
            if hudFrame._hoverZone then
                hudFrame._hoverZone:SetHeight(60 * uiScale * newScale)
            end
            RefreshScaleBtns()
        end

        -- Helper: create a text button with drop shadow
        local function MakeScaleBtn(text, anchorPoint, anchorTo, anchorRel, xOff, yOff)
            local btn = CreateFrame("Button", nil, hudFrame)
            btn:SetSize(30, 30)
            btn:SetPoint(anchorPoint, anchorTo, anchorRel, xOff, yOff)
            btn:SetFrameLevel(hudFrame:GetFrameLevel() + 3)

            -- Drop shadow (offset 1px down-right)
            local shadow = btn:CreateFontString(nil, "ARTWORK")
            shadow:SetFont(FONT_PATH, FONT_SZ, "")
            shadow:SetPoint("CENTER", btn, "CENTER", 1, -1)
            shadow:SetText(EllesmereUI.L(text))
            shadow:SetTextColor(0, 0, 0, NORMAL_A)
            btn._shadow = shadow

            -- Main text
            local label = btn:CreateFontString(nil, "OVERLAY")
            label:SetFont(FONT_PATH, FONT_SZ, "")
            label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            label:SetText(EllesmereUI.L(text))
            label:SetTextColor(NORMAL_R, NORMAL_G, NORMAL_B, NORMAL_A)
            btn._label = label

            btn._isDisabled = false

            btn:SetScript("OnEnter", function(self)
                if self._isDisabled then return end
                self._shadow:SetTextColor(0, 0, 0, HOVER_A)
                self._label:SetTextColor(HOVER_R, HOVER_G, HOVER_B, HOVER_A)
            end)
            btn:SetScript("OnLeave", function(self)
                if self._isDisabled then return end
                self._shadow:SetTextColor(0, 0, 0, NORMAL_A)
                self._label:SetTextColor(NORMAL_R, NORMAL_G, NORMAL_B, NORMAL_A)
            end)

            return btn
        end

        -- Minus button (10px left of the Exit button, outer side)
        minusBtn = MakeScaleBtn("\226\128\147", "RIGHT", exitBtn, "LEFT", -10, 0)
        minusBtn:SetScript("OnClick", function(self)
            if self._isDisabled then return end
            ApplyBannerScale(bannerUserScale - SCALE_STEP)
        end)

        -- Plus button (10px right of the Save & Exit button, outer side)
        plusBtn = MakeScaleBtn("+", "LEFT", hudFrame._saveBtn, "RIGHT", 10, 0)
        plusBtn:SetScript("OnClick", function(self)
            if self._isDisabled then return end
            ApplyBannerScale(bannerUserScale + SCALE_STEP)
        end)

        hudFrame._minusBtn = minusBtn
        hudFrame._plusBtn = plusBtn
        hudFrame._applyBannerScale = ApplyBannerScale

        RefreshScaleBtns()
    end

    ---------------------------------------------------------------
    --  Hover-bar logic: when hoverBarEnabled, the banner + all
    --  children fade out unless the cursor is in a 1144x60 zone
    --  at the top of the screen. Fade duration = 0.5s.
    ---------------------------------------------------------------
    local HOVER_ZONE_H = 60
    local HOVER_FADE = 0.5
    local hoverAlpha = 1  -- current fade alpha (1 = fully visible)

    -- Invisible hover detection zone (parented to UIParent, not hudFrame,
    -- so it's always accessible even when hudFrame alpha is 0)
    local hoverZone = CreateFrame("Frame", nil, parent)
    hoverZone:SetFrameStrata("FULLSCREEN_DIALOG")
    hoverZone:SetFrameLevel(parent:GetFrameLevel() + 56)
    hoverZone:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    hoverZone:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    hoverZone:SetHeight(HOVER_ZONE_H * (hudFrame:GetScale() or uiScale))
    hoverZone:EnableMouse(false)  -- doesn't block clicks
    hoverZone:Hide()
    hudFrame._hoverZone = hoverZone

    hudFrame:SetScript("OnUpdate", function(self, dt)
        if not hoverBarEnabled then
            -- Not in hover mode — ensure full alpha
            if hoverAlpha < 1 then
                hoverAlpha = 1
                self:SetAlpha(1)
            end
            hoverZone:Hide()
            return
        end

        hoverZone:Show()

        -- Check if cursor is within the hover zone (top of screen)
        local scale = UIParent:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        cy = cy / scale
        local screenH = UIParent:GetHeight()
        local zoneBot = screenH - (HOVER_ZONE_H * (hudFrame:GetScale() or uiScale))
        local inZone = (cy >= zoneBot)

        if inZone then
            hoverAlpha = min(1, hoverAlpha + dt / HOVER_FADE)
        else
            hoverAlpha = max(0, hoverAlpha - dt / HOVER_FADE)
        end
        self:SetAlpha(hoverAlpha)
    end)

    hudFrame:Hide()
    return hudFrame
end

-------------------------------------------------------------------------------
--  Save / Revert / Close helpers
-------------------------------------------------------------------------------

-- Snapshot current bar positions when entering unlock mode
local function SnapshotPositions()
    wipe(snapshotPositions)
    -- Action bars: capture from barPositions DB
    local db = GetPositionDB()
    if db then
        for barKey, pos in pairs(db) do
            snapshotPositions[barKey] = { point = pos.point, relPoint = pos.relPoint, x = pos.x, y = pos.y }
        end
    end
    -- Action bars: for any bar that has NO saved position, capture its live position
    for _, barKey in ipairs(ALL_BAR_ORDER) do
        if not snapshotPositions[barKey] then
            local bar = GetBarFrame(barKey)
            if bar then
                local nPts = bar:GetNumPoints()
                if nPts and nPts > 0 then
                    local point, _, relPoint, x, y = bar:GetPoint(1)
                    if point then
                        snapshotPositions[barKey] = { point = point, relPoint = relPoint, x = x, y = y }
                    end
                end
            end
        end
    end
    -- Registered elements: snapshot via loadPosition or live frame position
    RebuildRegisteredOrder()
    for _, key in ipairs(registeredOrder) do
        if not snapshotPositions[key] then
            local elem = registeredElements[key]
            if elem then
                local pos = elem.loadPosition and elem.loadPosition(key)
                if pos then
                    snapshotPositions[key] = { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
                else
                    local fr = elem.getFrame and elem.getFrame(key)
                    if fr then
                        local nPts = fr:GetNumPoints()
                        if nPts and nPts > 0 then
                            local point, _, relPoint, x, y = fr:GetPoint(1)
                            if point then
                                -- relPoint may be a frame object here (not a string) if the bar
                                -- is anchored to a parent frame rather than UIParent. Mark this
                                -- snapshot so RevertPositions skips writing it to SavedVariables.
                                snapshotPositions[key] = { point = point, relPoint = relPoint, x = x, y = y, _fromLiveFrame = true }
                            end
                        end
                    end
                end
            end
        end
    end

    -- Snapshot anchor data so we can revert on discard
    wipe(snapshotAnchors)
    local anchorDB = GetAnchorDB()
    if anchorDB then
        for childKey, info in pairs(anchorDB) do
            snapshotAnchors[childKey] = { target = info.target, side = info.side, offsetX = info.offsetX, offsetY = info.offsetY }
        end
    end

    -- Snapshot element sizes so we can revert width/height changes on discard
    wipe(snapshotSizes)
    for _, key in ipairs(registeredOrder) do
        local elem = registeredElements[key]
        if elem and elem.getSize then
            local w, h = elem.getSize(key)
            if w and h then
                snapshotSizes[key] = { w = w, h = h }
            end
        end
    end

    -- Snapshot width/height match DBs so we can revert on discard
    wipe(snapshotWidthMatch)
    wipe(snapshotHeightMatch)
    local wmDB = MatchH.GetWidthMatchDB()
    if wmDB then
        for k, v in pairs(wmDB) do snapshotWidthMatch[k] = v end
    end
    local hmDB = MatchH.GetHeightMatchDB()
    if hmDB then
        for k, v in pairs(hmDB) do snapshotHeightMatch[k] = v end
    end

    -- Snapshot growth directions so we can revert on discard
    wipe(snapshotGrowDirs)
    local cdm = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
    local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
    if cdmBars and cdmBars.bars then
        for _, bar in ipairs(cdmBars.bars) do
            snapshotGrowDirs["CDM_" .. bar.key] = bar.growDirection or false
        end
    end
    local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
    local abBars = eab and eab.db and eab.db.profile and eab.db.profile.bars
    if abBars then
        local abGrowKeys = { MainBar=1, Bar2=1, Bar3=1, Bar4=1, Bar5=1, Bar6=1, Bar7=1, Bar8=1 }
        for bk, cfg in pairs(abBars) do
            if abGrowKeys[bk] then
                snapshotGrowDirs[bk] = cfg.growDirection or false
            end
        end
    end
end

-- Commit pending positions to SavedVariables
local function CommitPositions()
    -- Suppress per-save rebuilds (e.g. CDM's BuildAllCDMBars) so that
    -- all positions are written first, then a single rebuild runs at the end.
    EllesmereUI._propagatingSave = true
    for barKey, pos in pairs(pendingPositions) do
        if pos == "RESET" then
            ClearBarPosition(barKey)
        else
            local elem = registeredElements[barKey]
            local pt, rpt, px, py = pos.point, pos.relPoint, pos.x, pos.y
            -- If position wasn't dragged, fill from snapshot
            if elem and not pt then
                local snap = snapshotPositions[barKey]
                if snap then
                    pt, rpt, px, py = snap.point, snap.relPoint or snap.point, snap.x, snap.y
                else
                    -- Fallback: read from loadPosition
                    local lp = elem.loadPosition and elem.loadPosition(barKey)
                    if lp then
                        pt, rpt, px, py = lp.point, lp.relPoint or lp.point, lp.x, lp.y
                    end
                end
            end
            SaveBarPosition(barKey, pt, rpt, px, py)
            -- Install anchor guard for action bar positions
            if not elem then
                local bar = GetBarFrame(barKey)
                if bar then InstallAnchorGuard(bar, barKey) end
            end
        end
    end
    EllesmereUI._propagatingSave = false

    -- Force edge-preservation across the save rebuild + reapply below. These run
    -- while isUnlocked is still true (DoClose clears it only AFTER CommitPositions
    -- returns), so without this flag ApplyAnchorPosition skips its absolute saved-
    -- edge branch and places anchored custom-growth CDM bars from the anchor offset
    -- + live width instead. When the rebuild changed a bar's width, the growth edge
    -- then lands off the freshly-saved edge and the bar visibly snaps back until
    -- /reload (which uses the saved edge). Setting the flag makes both passes read
    -- cdmBarPositions exactly like the login/reload apply, so Save matches reload.
    -- Mirrors the unlock-entry reapply (OpenUnlockMode); the reapply is pcall-wrapped
    -- and the flag is reset in all cases so it can never leak.
    EllesmereUI._reapplyForceEdgePreserve = true

    -- Single rebuild now that all positions are committed.
    -- CDM savePos normally calls BuildAllCDMBars per save, but we
    -- suppressed that above to avoid partial-state rebuilds.
    for barKey in pairs(pendingPositions) do
        if type(barKey) == "string" and barKey:sub(1, 4) == "CDM_" then
            local elem = registeredElements[barKey]
            if elem and elem.applyPosition then
                pcall(elem.applyPosition, barKey)
            end
            break  -- one rebuild is enough, it rebuilds all bars
        end
    end

    -- Reapply anchor positions for all anchored bars so they move from
    -- the stale CENTER coords (saved by CommitPositions) to their correct
    -- anchor-relative position immediately. Without this, anchored bars
    -- sit at stale coords until a deferred ScheduleAnchorBatch corrects
    -- them, causing a visible jump on the next resize.
    if EllesmereUI.ReapplyAllUnlockAnchorsForced then
        pcall(EllesmereUI.ReapplyAllUnlockAnchorsForced)
    end

    EllesmereUI._reapplyForceEdgePreserve = false

    -- Persist unlock layout into the active profile so it survives reloads
    -- without requiring a manual profile switch.
    if EllesmereUIDB and EllesmereUI.GetProfilesDB then
        local pdb = EllesmereUI.GetProfilesDB()
        local activeName = pdb.activeProfile or "Default"
        local profileData = pdb.profiles and pdb.profiles[activeName]
        if profileData then
            profileData.unlockLayout = {
                anchors       = CopyTable(EllesmereUIDB.unlockAnchors     or {}),
                widthMatch    = CopyTable(EllesmereUIDB.unlockWidthMatch  or {}),
                heightMatch   = CopyTable(EllesmereUIDB.unlockHeightMatch or {}),
                phantomBounds = CopyTable(EllesmereUIDB.phantomBounds     or {}),
            }
        end
    end
end

-- Revert bars to their snapshot positions (discard all pending changes)
local function RevertPositions()
    if InCombatLockdown() then return end

    -- 1) Restore all DB state from snapshots (suppress rebuilds)
    EllesmereUI._propagatingSave = true

    local db = GetPositionDB()
    if db then
        for barKey, _ in pairs(pendingPositions) do
            if not registeredElements[barKey] then
                local snap = snapshotPositions[barKey]
                if snap then
                    db[barKey] = { point = snap.point, relPoint = snap.relPoint, x = snap.x, y = snap.y }
                else
                    db[barKey] = nil
                end
            end
        end
    end

    for barKey, _ in pairs(pendingPositions) do
        local elem = registeredElements[barKey]
        if elem and elem.savePosition then
            local snap = snapshotPositions[barKey]
            if snap and not snap._fromLiveFrame then
                elem.savePosition(barKey, snap.point, snap.relPoint or snap.point, snap.x, snap.y)
            end
        end
    end

    EllesmereUI._propagatingSave = false

    -- 2) Restore anchor data before repositioning
    local anchorDB = GetAnchorDB()
    if anchorDB then
        wipe(anchorDB)
        for childKey, info in pairs(snapshotAnchors) do
            anchorDB[childKey] = { target = info.target, side = info.side, offsetX = info.offsetX, offsetY = info.offsetY }
        end
    end

    -- 3) Restore element sizes
    for key, snap in pairs(snapshotSizes) do
        local elem = registeredElements[key]
        if elem then
            if elem.setWidth and snap.w then
                pcall(elem.setWidth, key, snap.w)
            end
            if elem.setHeight and snap.h then
                pcall(elem.setHeight, key, snap.h)
            end
        end
    end

    -- 4) Restore width/height match DBs
    local wmDB = MatchH.GetWidthMatchDB()
    if wmDB then
        wipe(wmDB)
        for k, v in pairs(snapshotWidthMatch) do wmDB[k] = v end
    end
    local hmDB = MatchH.GetHeightMatchDB()
    if hmDB then
        wipe(hmDB)
        for k, v in pairs(snapshotHeightMatch) do hmDB[k] = v end
    end

    -- 5) Restore growth directions
    for key, snapGrow in pairs(snapshotGrowDirs) do
        local val = snapGrow == false and nil or snapGrow
        if key:sub(1, 4) == "CDM_" then
            local rawKey = key:sub(5)
            local cdmA = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
            local cdmB = cdmA and cdmA.db and cdmA.db.profile and cdmA.db.profile.cdmBars
            if cdmB and cdmB.bars then
                for _, bar in ipairs(cdmB.bars) do
                    if bar.key == rawKey then bar.growDirection = val; break end
                end
            end
        else
            local eabA = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
            local abB = eabA and eabA.db and eabA.db.profile and eabA.db.profile.bars
            if abB and abB[key] then abB[key].growDirection = val end
        end
    end

    -- 6) Rebuild CDM bars so they read the restored DB and position correctly.
    -- Without this, CDM bars revert to wrong positions (CENTER vs edge mismatch).
    local didCDMRebuild = false
    for barKey in pairs(pendingPositions) do
        if not didCDMRebuild and type(barKey) == "string" and barKey:sub(1, 4) == "CDM_" then
            local elem = registeredElements[barKey]
            if elem and elem.applyPosition then
                pcall(elem.applyPosition, barKey)
            end
            didCDMRebuild = true
        end
    end

    -- 6) Reposition unanchored elements through normal path.
    -- Skip anchored elements — step 7 handles them via ApplyAnchorPosition.
    for barKey, _ in pairs(pendingPositions) do
        local ai = anchorDB and anchorDB[barKey]
        if not (ai and ai.target) then
            local bar = GetBarFrame(barKey)
            if bar then
                local snap = snapshotPositions[barKey]
                if snap and not snap._fromLiveFrame then
                    if not ApplyCenterPosition(barKey, snap) then
                        pcall(function()
                            bar:ClearAllPoints()
                            bar:SetPoint(snap.point, UIParent, snap.relPoint, snap.x, snap.y)
                        end)
                    end
                elseif bar.UpdateGridLayout then
                    pcall(bar.UpdateGridLayout, bar)
                end
            end
        end
    end

    -- 7) Reapply anchor positions for anchored elements
    if anchorDB then
        for childKey, info in pairs(anchorDB) do
            if info.target and GetBarFrame(childKey) and GetBarFrame(info.target) then
                ApplyAnchorPosition(childKey, info.target, info.side)
            end
        end
    end
end

-- Internal close (actually hides everything and returns to options)
local function DoClose()
    if not isUnlocked then return end
    isUnlocked = false
    EllesmereUI._unlockActive = false
    EllesmereUI._unlockModeActive = false

    -- Notify action bars to restore Blizzard-owned frame anchors
    if _G._EAB_UnlockModeClose then pcall(_G._EAB_UnlockModeClose) end
    -- Notify damage meters
    if _G._EDM_UnlockModeClose then pcall(_G._EDM_UnlockModeClose) end

    -- Recalculate action bar flyout directions after positions are finalized
    if _G._EAB_RecalcFlyouts then pcall(_G._EAB_RecalcFlyouts) end

    -- Notify beacon reminders to restore (if follow-mouse is active)
    if _G._EABR_BeaconRefresh then pcall(_G._EABR_BeaconRefresh) end

    -- Restore expandIfNoResource after unlock mode finishes
    if _G._ERB_RestoreExpand then pcall(_G._ERB_RestoreExpand) end
    -- Re-apply the anchor-target shift after unlock mode finishes. Independent of
    -- expand restore (which early-returns when expand was never suppressed); runs
    -- after _unlockActive is cleared above so the provider returns non-zero and
    -- PropagateAnchorChain is no longer a no-op. Gated so None = no work.
    if _G._ERB_RestoreShift then pcall(_G._ERB_RestoreShift) end

    -- Restore unit frame buffs/debuffs
    local UF_FRAME_NAMES = {
        "EllesmereUIUnitFrames_Player", "EllesmereUIUnitFrames_Target",
        "EllesmereUIUnitFrames_Focus", "EllesmereUIUnitFrames_Pet",
        "EllesmereUIUnitFrames_TargetTarget", "EllesmereUIUnitFrames_FocusTarget",
    }
    for i = 1, 8 do UF_FRAME_NAMES[#UF_FRAME_NAMES + 1] = "EllesmereUIUnitFrames_Boss" .. i end
    for _, name in ipairs(UF_FRAME_NAMES) do
        local f = _G[name]
        if f then
            if f.Buffs and f.Buffs._unlockWasShown then
                f.Buffs:Show()
                f.Buffs._unlockWasShown = nil
            end
            if f.Debuffs and f.Debuffs._unlockWasShown then
                f.Debuffs:Show()
                f.Debuffs._unlockWasShown = nil
            end
        end
    end

    -- Restore objective tracker
    if objTrackerWasVisible then
        local objTracker = _G.ObjectiveTrackerFrame
        if objTracker then
            objTracker:SetAlpha(1)
            local wasEnabled = objTracker._eabMouseWasEnabled
            if objTracker.EnableMouse then
                pcall(objTracker.EnableMouse, objTracker, wasEnabled and true or false)
            end
        end
        objTrackerWasVisible = false
    end
    -- Restore EllesmereUI QT background
    local qtBg = _G.EllesmereUIQTBackground
    if qtBg then qtBg:SetAlpha(1) end
    -- Re-apply user visibility setting (handles "never" mode for both tracker + bg)
    if _G.EllesmereUIQuestTracker and _G.EllesmereUIQuestTracker.UpdateVisibility then
        _G.EllesmereUIQuestTracker.UpdateVisibility()
    end

    if not unlockFrame then return end

    unlockFrame:SetScript("OnUpdate", nil)
    if logoFadeFrame then logoFadeFrame:SetScript("OnUpdate", nil); logoFadeFrame:Hide() end
    if openAnimFrame then openAnimFrame:Hide() end
    if lockAnimFrame then lockAnimFrame:Hide() end
    if gridFrame then gridFrame:SetScript("OnUpdate", nil); gridFrame:Hide() end
    if hudFrame then hudFrame:Hide() end
    if unlockTipFrame then unlockTipFrame:SetScript("OnUpdate", nil); unlockTipFrame:Hide() end
    if unlockFrame._anchorLineDriver then unlockFrame._anchorLineDriver:Hide() end
    if unlockFrame._anchorLineFrame  then unlockFrame._anchorLineFrame:Hide() end
    if unlockFrame._clearAnchorLineAnim then unlockFrame._clearAnchorLineAnim() end
    DeselectMover()
    -- Collapse any expanded mover so it doesn't stay stuck on re-enter
    hoveredMover    = nil
    cogHoveredMover = nil
    EllesmereUI._unlockCursorSpeed = 0
    for _, m in pairs(movers) do
        m._snapTarget   = nil
        m._dragging     = false
        m._shiftAxis    = nil
        m._hoverPending = false
        -- Snap-collapse hover state so mover isn't stuck expanded on re-enter
        if m._forceCollapse then m._forceCollapse() end
        m:SetScript("OnUpdate", nil)
        m:Hide()
    end
    HideAllGuidesAndHighlight()
    HideBlizzOwnedOverlays()
    unlockFrame:Hide()
    unlockFrame:SetAlpha(1)

    -- Clean up arrow key nudge state
    selectedMover = nil
    selectElementPicker = nil
    if arrowKeyFrame then arrowKeyFrame:Hide() end

    -- Reset session state
    wipe(pendingPositions)
    wipe(snapshotPositions)
    wipe(snapshotAnchors)
    wipe(snapshotGrowDirs)
    hasChanges = false

    -- Clean up pick mode / anchor dropdown state
    pickMode = nil
    pickModeMover = nil
    if anchorDropdownFrame then anchorDropdownFrame:Hide() end
    if anchorDropdownCatcher then anchorDropdownCatcher:Hide() end
    if growDropdownFrame then growDropdownFrame:Hide() end
    if growDropdownCatcher then growDropdownCatcher:Hide() end

    -- Restore action bar alpha from saved settings
    if EAB and EAB.RefreshMouseover and not InCombatLockdown() then
        EAB:RefreshMouseover()
    end

    -- Restore CDM bar visibility (unlock forced all bars visible)
    if _G._ECME_ApplyVisibility then _G._ECME_ApplyVisibility() end

    -- Restore panel scale and show options
    local panelRealScale
    do
        local physW = (GetPhysicalScreenSize())
        local baseScale = GetScreenWidth() / physW
        local userScale = (EllesmereUIDB and EllesmereUIDB.panelScale) or 1.0
        panelRealScale = baseScale * userScale
    end
    local panel = EllesmereUI and EllesmereUI._mainFrame
    if panel then panel:SetScale(panelRealScale); panel:SetAlpha(1) end
    -- If there's a pending after-close callback, skip the default panel restore
    -- (the callback will handle opening the panel to the right page)
    if not pendingAfterClose then
        if EllesmereUI then
            -- Restore the module + page that were active before unlock mode opened.
            -- These are captured by SelectPage("Unlock Mode") in EllesmereUI.lua.
            -- IMPORTANT: We do NOT show the panel yet — SelectModule/SelectPage
            -- cause Hide→Show cycles on the page wrapper via HideAllChildren.
            -- Showing the panel first would add extra cycles that leave EditBox
            -- text blank.  Instead we set up the correct page while the panel is
            -- still hidden, then show it once at the end.
            local restoreModule = EllesmereUI._unlockReturnModule
            local restorePage   = EllesmereUI._unlockReturnPage
            EllesmereUI._unlockReturnPage = nil
            EllesmereUI._unlockReturnModule = nil
            if restoreModule then
                if EllesmereUI.SelectModule then
                    EllesmereUI:SelectModule(restoreModule)
                end
                if restorePage and EllesmereUI.SelectPage then
                    local currentPage = EllesmereUI.GetActivePage and EllesmereUI:GetActivePage()
                    if currentPage ~= restorePage then
                        EllesmereUI:SelectPage(restorePage)
                    end
                end
                -- NOW show the panel — one clean Show, no prior cycling.
                if EllesmereUI.Toggle then EllesmereUI:Toggle() end
            end
        end
    end

    -- Fire any pending after-close callback (e.g. from slash commands)
    if pendingAfterClose then
        EllesmereUI._unlockReturnPage = nil
        EllesmereUI._unlockReturnModule = nil
        local fn = pendingAfterClose
        pendingAfterClose = nil
        fn()
    end
end

-- Public close request: save=true commits, save=false may prompt
-- Optional afterFn runs after close completes (for slash command chaining)
function ns.RequestClose(save, afterFn)
    if afterFn then pendingAfterClose = afterFn end
    if save then
        CommitPositions()
        DoClose()
        return
    end
    -- No changes → just exit
    if not hasChanges then
        DoClose()
        return
    end
    -- Has unsaved changes → show confirm popup
    EllesmereUI:ShowConfirmPopup({
        title = "Unsaved Changes",
        message = "You have unsaved position changes.\nWhat would you like to do?",
        cancelText  = "Exit Without Saving",
        confirmText = "Save & Exit",
        onCancel = function()
            RevertPositions()
            DoClose()
        end,
        onConfirm = function()
            CommitPositions()
            DoClose()
        end,
        -- Dismiss (ESC / click-off) does nothing -- user stays in unlock mode,
        -- and any pending close callback is cleared since the close was abandoned
        onDismiss = function() pendingAfterClose = nil end,
    })
end

-------------------------------------------------------------------------------
--  Smooth easing function (ease-in-out cubic)
-------------------------------------------------------------------------------
local function EaseInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local f = 2 * t - 2
        return 0.5 * f * f * f + 1
    end
end

-------------------------------------------------------------------------------
--  Open / Close Unlock Mode
-------------------------------------------------------------------------------
local function CreateUnlockFrame()
    if unlockFrame then return unlockFrame end

    unlockFrame = CreateFrame("Frame", "EllesmereUnlockMode", UIParent)
    unlockFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    unlockFrame:SetAllPoints(UIParent)
    unlockFrame:EnableMouse(false)  -- let clicks pass through to game world
    unlockFrame:EnableKeyboard(true)

    -- Dark overlay background — on a dedicated sub-frame so movers render ABOVE it
    local overlayFrame = CreateFrame("Frame", nil, unlockFrame)
    overlayFrame:SetFrameLevel(unlockFrame:GetFrameLevel() + 1)
    overlayFrame:SetAllPoints(UIParent)
    local overlay = overlayFrame:CreateTexture(nil, "BACKGROUND")
    overlay:SetAllPoints()
    overlay:SetColorTexture(0.02, 0.03, 0.04, 0.20)
    unlockFrame._overlay = overlay
    unlockFrame._overlayMaxAlpha = 0.20

    -- Anchor connector lines: accent-colored lines drawn center-to-center
    -- between each anchored child and its parent, rendered behind all elements.
    local anchorLinePool = {}
    local anchorPulsePool = {}
    local anchorLineFrame = CreateFrame("Frame", nil, UIParent)
    anchorLineFrame:SetFrameStrata("BACKGROUND")
    anchorLineFrame:SetFrameLevel(1)
    anchorLineFrame:SetAllPoints(UIParent)
    anchorLineFrame:EnableMouse(false)

    local function GetAnchorLine(idx)
        if anchorLinePool[idx] then return anchorLinePool[idx] end
        local line = anchorLineFrame:CreateLine(nil, "ARTWORK", nil, 1)
        line:SetThickness(3)
        line:SetSnapToPixelGrid(false)
        line:SetTexelSnappingBias(0)
        line:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\textures\\soft-line")
        anchorLinePool[idx] = line
        return line
    end

    local function GetAnchorPulse(idx)
        if anchorPulsePool[idx] then return anchorPulsePool[idx] end
        local line = anchorLineFrame:CreateLine(nil, "ARTWORK", nil, 2)
        line:SetThickness(3)
        line:SetSnapToPixelGrid(false)
        line:SetTexelSnappingBias(0)
        line:SetTexture("Interface\\AnimaChannelingDevice\\AnimaChannelingDeviceLineVerticalMask")
        anchorPulsePool[idx] = line
        return line
    end

    -- Per-line animation state keyed by "childKey:targetKey"
    local anchorLineAnim = {}
    local ANCHOR_LINE_DUR = 0.5
    local PULSE_CYCLE = 2.5
    local PULSE_SWEEP = 0.56  -- fraction of cycle spent sweeping (rest is pause)

    local function UpdateAnchorLines()
        local db = GetAnchorDB()
        local idx = 0
        local now = GetTime()
        if db and isUnlocked then
            for childKey, info in pairs(db) do
                local cm = movers[childKey]
                local tm = movers[info.target]
                if cm and tm and cm:IsShown() and tm:IsShown() then
                    -- Use _hoverConfirmed so lines wait for hover intent
                    local cmActive = cm._hoverConfirmed or cm._dragging
                    local tmActive = tm._hoverConfirmed or tm._dragging
                    local pairKey = childKey .. ":" .. info.target
                    if cmActive or tmActive then
                        -- Start or continue animation
                        if not anchorLineAnim[pairKey] then
                            anchorLineAnim[pairKey] = now
                        end
                        local elapsed = now - anchorLineAnim[pairKey]
                        local t = elapsed / ANCHOR_LINE_DUR
                        if t > 1 then t = 1 end
                        -- Ease-out for smooth deceleration
                        local ease = 1 - (1 - t) * (1 - t)

                        idx = idx + 1
                        local line = GetAnchorLine(idx)
                        -- Child center (line origin)
                        local x1 = ((cm:GetLeft() or 0) + (cm:GetRight()  or 0)) * 0.5
                        local y1 = ((cm:GetBottom() or 0) + (cm:GetTop()  or 0)) * 0.5
                        -- Parent center (line destination)
                        local x2 = ((tm:GetLeft() or 0) + (tm:GetRight()  or 0)) * 0.5
                        local y2 = ((tm:GetBottom() or 0) + (tm:GetTop()  or 0)) * 0.5
                        -- Partial endpoint based on animation progress
                        local ex = x1 + (x2 - x1) * ease
                        local ey = y1 + (y2 - y1) * ease
                        line:SetStartPoint("BOTTOMLEFT", UIParent, x1, y1)
                        line:SetEndPoint("BOTTOMLEFT", UIParent, ex, ey)
                        line:SetVertexColor(1, 0.7, 0.3, 0.75 * ease)
                        line:Show()

                        -- Pulse overlay: streak that sweeps child->parent, loops every 3s
                        local pulse = GetAnchorPulse(idx)
                        if ease >= 1 then
                            local pulseAge = now - anchorLineAnim[pairKey] - 0.3
                            local cycleT = (pulseAge % PULSE_CYCLE) / PULSE_CYCLE
                            local sweepEnd = PULSE_SWEEP
                            if cycleT <= sweepEnd then
                                local st = cycleT / sweepEnd
                                -- Smooth ease-in-out motion, overshooting to 3x line length
                                local smoothT = st * st * (3 - 2 * st)
                                local headT = smoothT * 2.0
                                local tailT = math.max(0, headT - 1.0)
                                -- Clamp endpoints to the actual line
                                local clampHead = math.min(1, headT)
                                local clampTail = math.min(1, tailT)
                                -- Fade in/out
                                local fadeA = 1
                                if smoothT < 0.1 then
                                    fadeA = smoothT / 0.1
                                elseif smoothT > 0.7 then
                                    fadeA = (1 - smoothT) / 0.3
                                end
                                if fadeA < 0 then fadeA = 0 end
                                if clampHead <= clampTail then
                                    pulse:Hide()
                                else
                                    local px1 = x1 + (x2 - x1) * clampTail
                                    local py1 = y1 + (y2 - y1) * clampTail
                                    local px2 = x1 + (x2 - x1) * clampHead
                                    local py2 = y1 + (y2 - y1) * clampHead
                                    pulse:SetStartPoint("BOTTOMLEFT", UIParent, px1, py1)
                                    pulse:SetEndPoint("BOTTOMLEFT", UIParent, px2, py2)
                                    pulse:SetVertexColor(1, 0.89, 0.625, 0.5 * fadeA)
                                    pulse:Show()
                                end
                            else
                                pulse:Hide()
                            end
                        else
                            pulse:Hide()
                        end
                    else
                        -- Not active, clear animation state
                        anchorLineAnim[pairKey] = nil
                    end
                end
            end
        end
        -- Hide unused lines and clean stale anim entries
        for i = idx + 1, #anchorLinePool do
            anchorLinePool[i]:Hide()
        end
        for i = idx + 1, #anchorPulsePool do
            anchorPulsePool[i]:Hide()
        end
    end

    -- Drive line updates every frame while unlock mode is open
    local anchorLineDriver = CreateFrame("Frame")
    anchorLineDriver:SetScript("OnUpdate", UpdateAnchorLines)
    anchorLineDriver:Hide()
    unlockFrame._anchorLineDriver = anchorLineDriver
    unlockFrame._anchorLineFrame  = anchorLineFrame
    unlockFrame._clearAnchorLineAnim = function() wipe(anchorLineAnim) end

    -- Click-to-deselect is handled by toggle behavior on movers themselves
    -- (clicking the selected mover again deselects it), so no full-screen
    -- catcher is needed — world interaction (targeting, camera) stays unblocked.

    -- ESC to close (skip if confirm popup is already showing)
    unlockFrame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            -- If the confirm popup is visible, let it handle ESC instead
            local dimmer = _G["EUIConfirmDimmer"]
            if dimmer and dimmer:IsShown() then
                self:SetPropagateKeyboardInput(true)
                return
            end
            -- If anchor dropdown is open, close it instead of closing unlock mode
            if anchorDropdownFrame and anchorDropdownFrame:IsShown() then
                self:SetPropagateKeyboardInput(false)
                anchorDropdownFrame:Hide()
                if anchorDropdownCatcher then anchorDropdownCatcher:Hide() end
                return
            end
            -- If in width/height/anchor pick mode, cancel it instead of closing
            if pickModeMover and pickMode then
                self:SetPropagateKeyboardInput(false)
                CancelPickMode()
                return
            end
            -- If in select-element pick mode, cancel it instead of closing
            if selectElementPicker then
                self:SetPropagateKeyboardInput(false)
                local picker = selectElementPicker
                picker._snapTarget = picker._preSelectTarget
                picker._preSelectTarget = nil
                if picker._updateSnapLabel then picker._updateSnapLabel() end
                selectElementPicker = nil
                FadeOverlayForSelectElement(false)
                return
            end
            self:SetPropagateKeyboardInput(false)
            ns.CloseUnlockMode()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    unlockFrame:Hide()
    return unlockFrame
end

-------------------------------------------------------------------------------
--  Open lock animation frame (panel shrink → gear rotate → shackle unlock)
--  Uses a container frame + SetScale for guaranteed uniform aspect ratio.
--  Each texture is set to its NATIVE pixel dimensions so proportions are
--  preserved exactly as designed in Photoshop.
-------------------------------------------------------------------------------
-- Native pixel dimensions of each PNG (from Photoshop)
local INNER_W, INNER_H = 253, 253
local OUTER_W, OUTER_H = 368, 353
local TOP_W,   TOP_H   = 412, 412

-- Container size = largest piece so everything fits
local CONTAINER_SZ = 412
-- The "icon size" we want the logo to appear at on screen (in UI pixels)
local ICON_SZ = 100
-- Base scale to shrink native-res textures down to icon size
local BASE_SCALE = ICON_SZ / CONTAINER_SZ

local SHACKLE_LIFT = 62  -- how far the shackle lifts (in container-space pixels)
local OUTER_Y_OFFSET = -7  -- outer ring sits 7px lower than center

local function CreateOpenAnimFrame(parent)
    if openAnimFrame then return openAnimFrame end

    openAnimFrame = CreateFrame("Frame", nil, parent)
    openAnimFrame:SetFrameLevel(50)  -- above movers (~20), below confirm popup (100)
    openAnimFrame:SetAllPoints(UIParent)

    -- Container frame: sized to hold the largest texture at native res.
    -- SetScale on this frame handles ALL sizing uniformly.
    local container = CreateFrame("Frame", nil, openAnimFrame)
    container:SetSize(CONTAINER_SZ, CONTAINER_SZ)
    container:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    container:SetScale(BASE_SCALE)
    openAnimFrame._container = container

    -- Each texture at its NATIVE pixel dimensions, centered in container
    -- Disable pixel snapping for smooth sub-pixel animation
    local outer = container:CreateTexture(nil, "ARTWORK", nil, 1)
    outer:SetTexture(LOCK_OUTER)
    outer:SetSize(OUTER_W, OUTER_H)
    outer:SetPoint("CENTER", container, "CENTER", 0, OUTER_Y_OFFSET)
    if outer.SetSnapToPixelGrid then outer:SetSnapToPixelGrid(false); outer:SetTexelSnappingBias(0) end
    openAnimFrame._outer = outer

    local inner = container:CreateTexture(nil, "ARTWORK", nil, 2)
    inner:SetTexture(LOCK_INNER)
    inner:SetSize(INNER_W, INNER_H)
    inner:SetPoint("CENTER", container, "CENTER", 0, 0)
    if inner.SetSnapToPixelGrid then inner:SetSnapToPixelGrid(false); inner:SetTexelSnappingBias(0) end
    openAnimFrame._inner = inner

    local top = container:CreateTexture(nil, "ARTWORK", nil, 3)
    top:SetTexture(LOCK_TOP)
    top:SetSize(TOP_W, TOP_H)
    top:SetPoint("CENTER", container, "CENTER", 0, 0)
    if top.SetSnapToPixelGrid then top:SetSnapToPixelGrid(false); top:SetTexelSnappingBias(0) end
    openAnimFrame._top = top

    -- Sweep shine: tightly clipped to logo center (lives inside container)
    local sweepClip = CreateFrame("Frame", nil, container)
    sweepClip:SetSize(CONTAINER_SZ * 0.75, CONTAINER_SZ * 0.75)
    sweepClip:SetPoint("CENTER", container, "CENTER", 0, 0)
    sweepClip:SetFrameLevel(container:GetFrameLevel() + 5)
    sweepClip:SetClipsChildren(true)
    openAnimFrame._sweepClip = sweepClip

    local sweep = sweepClip:CreateTexture(nil, "OVERLAY", nil, 7)
    sweep:SetColorTexture(1, 1, 1, 0.30)
    sweep:SetSize(12, 120)
    sweep:SetRotation(math.rad(20))
    sweep:ClearAllPoints()
    sweep:SetPoint("CENTER", sweepClip, "LEFT", -20, 0)
    sweep:Hide()
    openAnimFrame._sweep = sweep

    openAnimFrame:Hide()
    return openAnimFrame
end

-------------------------------------------------------------------------------
--  One-time "How to use" tip — shows below the banner on first ever open.
--  Saved to EllesmereUIDB.unlockTipSeen so it never shows again.
-------------------------------------------------------------------------------

function ns.ShowUnlockTip()
    if EllesmereUIDB and EllesmereUIDB.unlockTipSeen then return end
    if unlockTipFrame and unlockTipFrame:IsShown() then return end

    if not unlockTipFrame then
        local TIP_W, TIP_H = 450, 175
        local ar, ag, ab = GetAccent()

        local tip = CreateFrame("Frame", nil, UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetFrameLevel(900)
        tip:SetSize(TIP_W, TIP_H)
        tip:EnableMouse(true)

        -- Pixel-perfect scale (match banner)
        local physW = (GetPhysicalScreenSize())
        local ppScale = GetScreenWidth() / physW
        tip:SetScale(ppScale)

        -- Position 100px from the top of the screen
        tip:SetPoint("TOP", UIParent, "TOP", 0, -100 / ppScale)

        -- Background
        local bg = tip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.08, 0.10, 0.95)

        -- Border
        EllesmereUI.MakeBorder(tip, ar, ag, ab, 0.25)

        -- Smooth arrow pointing up — rotated squares for clean diagonal edges.
        -- Smooth arrow pointing up — uses SetClipsChildren to show only the
        -- top half of the diamond (above the popup top edge). No mask needed.
        local ARROW_SZ = 16  -- diamond size
        -- Clip frame: sits above the popup top edge, clips to show only top half
        -- Shifted up 2px so the arrow appears 2px higher
        local arrowClip = CreateFrame("Frame", nil, tip)
        arrowClip:SetFrameStrata("TOOLTIP")
        arrowClip:SetFrameLevel(tip:GetFrameLevel() + 10)
        arrowClip:SetClipsChildren(true)
        -- Clip region: tall enough for the top half of the diamond
        local clipH = ARROW_SZ
        arrowClip:SetSize(ARROW_SZ * 2, clipH)
        arrowClip:SetPoint("BOTTOM", tip, "TOP", 0, -1)

        -- The actual diamond frame inside the clip, positioned so its center
        -- (widest point) is exactly at the clip's bottom edge
        local arrowFrame = CreateFrame("Frame", nil, arrowClip)
        arrowFrame:SetFrameLevel(arrowClip:GetFrameLevel() + 1)
        arrowFrame:SetSize(ARROW_SZ + 4, ARROW_SZ + 4)
        arrowFrame:SetPoint("CENTER", arrowClip, "BOTTOM", 0, 0)

        -- Border diamond (accent, slightly larger for 1px border effect)
        -- Alpha slightly lower than popup border (0.25) to compensate for
        -- anti-aliased rotated edges appearing brighter than crisp 1px lines
        local arrowBorder = arrowFrame:CreateTexture(nil, "ARTWORK", nil, 7)
        arrowBorder:SetSize(ARROW_SZ + 2, ARROW_SZ + 2)
        arrowBorder:SetPoint("CENTER")
        arrowBorder:SetColorTexture(ar, ag, ab, 0.18)
        arrowBorder:SetRotation(math.rad(45))
        if arrowBorder.SetSnapToPixelGrid then arrowBorder:SetSnapToPixelGrid(false); arrowBorder:SetTexelSnappingBias(0) end

        -- Fill diamond (same bg as popup: 0.06, 0.08, 0.10, 0.95)
        local arrowFill = arrowFrame:CreateTexture(nil, "OVERLAY", nil, 6)
        arrowFill:SetSize(ARROW_SZ, ARROW_SZ)
        arrowFill:SetPoint("CENTER")
        arrowFill:SetColorTexture(0.06, 0.08, 0.10, 0.95)
        arrowFill:SetRotation(math.rad(45))
        if arrowFill.SetSnapToPixelGrid then arrowFill:SetSnapToPixelGrid(false); arrowFill:SetTexelSnappingBias(0) end

        -- Message
        local msg = tip:CreateFontString(nil, "OVERLAY")
        msg:SetFont(FONT_PATH, 12, "OUTLINE, SLUG")
        msg:SetTextColor(1, 1, 1, 0.85)
        msg:SetPoint("TOP", tip, "TOP", 0, -17)
        msg:SetWidth(TIP_W - 30)
        msg:SetJustifyH("CENTER")
        msg:SetSpacing(6)
        msg:SetText(EllesmereUI.L("This is where you can control the settings of Unlock Mode.\n\nElements can be repositioned by dragging or arrow keys (+shift)\nAnchor, Height Match, or Width match any element.\nSnapping is based on closest element, but you can snap only to\n a specific element via right click or the settings icon."))

        -- Okay button
        local okBtn = CreateFrame("Button", nil, tip)
        okBtn:SetSize(80, 24)
        okBtn:SetPoint("BOTTOM", tip, "BOTTOM", 0, 15)
        EllesmereUI.MakeStyledButton(okBtn, "Okay", 10,
            EllesmereUI.RB_COLOURS, function()
                tip:Hide()
                if EllesmereUIDB then EllesmereUIDB.unlockTipSeen = true end
            end)

        unlockTipFrame = tip
    end

    unlockTipFrame:SetAlpha(0)
    unlockTipFrame:Show()

    -- Fade in over 0.3s
    local fadeIn = 0
    unlockTipFrame:SetScript("OnUpdate", function(self, dt)
        fadeIn = fadeIn + dt
        if fadeIn >= 0.3 then
            self:SetAlpha(1)
            self:SetScript("OnUpdate", nil)
            return
        end
        self:SetAlpha(fadeIn / 0.3)
    end)
end

function ns.OpenUnlockMode()
    if isUnlocked then return end
    if InCombatLockdown() then
        print("|cffff6060[EllesmereUI]|r Cannot enter Unlock Mode during combat.")
        return
    end
    -- Disable expandIfNoResource before _unlockActive is set so the
    -- Rebuild inside runs in normal gameplay state and the power bar
    -- is at its true stored height before movers capture positions.
    if _G._ERB_SuppressExpand then pcall(_G._ERB_SuppressExpand) end

    isUnlocked = true
    EllesmereUI._unlockActive = true
    EllesmereUI._unlockModeActive = true

    -- Notify action bars to flip Blizzard-owned frame anchors for drag
    if _G._EAB_UnlockModeOpen then pcall(_G._EAB_UnlockModeOpen) end
    -- Notify damage meters
    if _G._EDM_UnlockModeOpen then pcall(_G._EDM_UnlockModeOpen) end
    -- Notify raid frames to fade out overlay previews
    if _G._ERF_UnlockModeOpen then pcall(_G._ERF_UnlockModeOpen) end

    -- Remove any stale anchor/match relationships before entering unlock mode.
    -- By this point all elements are registered, so anything not in the registry
    -- is genuinely gone (e.g. a custom CDM bar that was deleted).
    ValidateStoredLinks()

    -- Notify beacon reminders to hide (if follow-mouse is active)
    if _G._EABR_BeaconRefresh then pcall(_G._EABR_BeaconRefresh) end

    -- Hide unit frame buffs/debuffs so they don't clutter the movers
    local UF_FRAME_NAMES = {
        "EllesmereUIUnitFrames_Player", "EllesmereUIUnitFrames_Target",
        "EllesmereUIUnitFrames_Focus", "EllesmereUIUnitFrames_Pet",
        "EllesmereUIUnitFrames_TargetTarget", "EllesmereUIUnitFrames_FocusTarget",
    }
    for i = 1, 8 do UF_FRAME_NAMES[#UF_FRAME_NAMES + 1] = "EllesmereUIUnitFrames_Boss" .. i end
    for _, name in ipairs(UF_FRAME_NAMES) do
        local f = _G[name]
        if f then
            if f.Buffs and f.Buffs:IsShown() then
                f.Buffs._unlockWasShown = true
                f.Buffs:Hide()
            end
            if f.Debuffs and f.Debuffs:IsShown() then
                f.Debuffs._unlockWasShown = true
                f.Debuffs:Hide()
            end
        end
    end

    -- Hide objective tracker (alpha only -- no :Hide() to avoid taint).
    -- Hook SetAlpha to suppress Blizzard re-showing it during unlock
    -- (mounting, quest updates, etc. call SetAlpha(1) on their own).
    local objTracker = _G.ObjectiveTrackerFrame
    if objTracker and objTracker:IsShown() then
        objTrackerWasVisible = true
        objTracker._eabMouseWasEnabled = objTracker:IsMouseEnabled()
        objTracker:SetAlpha(0)
        if objTracker.EnableMouse then pcall(objTracker.EnableMouse, objTracker, false) end
        if not objTracker._eabUnlockAlphaHooked then
            objTracker._eabUnlockAlphaHooked = true
            hooksecurefunc(objTracker, "SetAlpha", function(self, a)
                if isUnlocked and a > 0 then
                    self:SetAlpha(0)
                end
            end)
        end
    else
        objTrackerWasVisible = false
    end
    -- Also hide EllesmereUI QT background (separate UIParent child)
    local qtBg = _G.EllesmereUIQTBackground
    if qtBg then
        qtBg:SetAlpha(0)
        if not qtBg._eabUnlockAlphaHooked then
            qtBg._eabUnlockAlphaHooked = true
            hooksecurefunc(qtBg, "SetAlpha", function(self, a)
                if isUnlocked and a > 0 then
                    self:SetAlpha(0)
                end
            end)
        end
    end

    -- Reset session state and snapshot current positions
    wipe(pendingPositions)
    hasChanges = false
    selectedMover = nil
    -- Strip any temporary anchor-target shift (e.g. ResourceBars "Shift Elements
    -- if No Resource") so movers snapshot TRUE saved positions. _unlockActive is
    -- already true above, so the shift provider returns 0 and this re-apply snaps
    -- shifted children back to their real positions. Gated so non-shift profiles
    -- do no extra work on unlock entry.
    if _G._ERB_ShiftWantsApply and _G._ERB_ShiftWantsApply()
       and EllesmereUI.ReapplyAllUnlockAnchors then
        -- Force edge-preservation for this reapply so custom-growth anchored bars
        -- snap to their fixed growth edge (their true saved position), not the
        -- center-offset position. Reset in all cases (pcall) so the flag can't leak.
        EllesmereUI._reapplyForceEdgePreserve = true
        pcall(EllesmereUI.ReapplyAllUnlockAnchors)
        EllesmereUI._reapplyForceEdgePreserve = false
    end
    SnapshotPositions()

    -- Setup and show arrow key frame for nudge support
    SetupArrowKeyFrame()
    arrowKeyFrame:Show()

    -- Play unlock sound
    PlaySound(201528, "Master")

    -- Create frames
    CreateUnlockFrame()
    CreateGrid(unlockFrame)
    CreateHUD(unlockFrame)
    CreateOpenAnimFrame(unlockFrame)

    -- Capture the options panel frame for the shrink animation
    local panel = EllesmereUI and EllesmereUI._mainFrame
    local panelStartW, panelStartH
    if panel and panel:IsShown() then
        panelStartW = panel:GetWidth()
        panelStartH = panel:GetHeight()
    end
    panelStartW = panelStartW or 600
    panelStartH = panelStartH or 400
    -- Use the larger dimension for the scale factor
    local panelStartSz = max(panelStartW, panelStartH)
    -- startScale: how big the container needs to be so it appears panel-sized
    -- BASE_SCALE makes the container appear as ICON_SZ on screen,
    -- so to appear as panelStartSz we need: BASE_SCALE * (panelStartSz / ICON_SZ)
    local startScale = BASE_SCALE * (panelStartSz / ICON_SZ) * 0.6

    -- Show overlay, hide grid/toolbar/movers
    unlockFrame:Show()
    unlockFrame:SetAlpha(1)
    if gridFrame then gridFrame:Hide() end
    if hudFrame then hudFrame:Hide() end
    for _, m in pairs(movers) do m:Hide() end

    local container = openAnimFrame._container
    local outerTex  = openAnimFrame._outer
    local innerTex  = openAnimFrame._inner
    local topTex    = openAnimFrame._top

    if openAnimFrame._sweep then openAnimFrame._sweep:Hide() end

    -- Container starts at panel-sized scale, textures stay at native dims always
    local TOTAL_GEAR_ROT = GEAR_ROTATION * 4

    -- Reset textures anchored to container center — ONCE
    -- (sizes are already set to native dims at creation, never change them)
    outerTex:ClearAllPoints()
    outerTex:SetPoint("CENTER", container, "CENTER", 0, OUTER_Y_OFFSET)
    outerTex:SetAlpha(0)
    outerTex:SetRotation(TOTAL_GEAR_ROT)

    innerTex:ClearAllPoints()
    innerTex:SetPoint("CENTER", container, "CENTER", 0, 0)
    innerTex:SetAlpha(0)
    innerTex:SetRotation(-TOTAL_GEAR_ROT)

    topTex:ClearAllPoints()
    topTex:SetPoint("CENTER", container, "CENTER", 0, 0)
    topTex:SetAlpha(0)
    topTex:SetRotation(0)

    -- Container starts at panel scale
    container:SetScale(startScale)

    openAnimFrame:Show()
    openAnimFrame:SetAlpha(1)

    -- Start overlay at 0 alpha, will fade in during animation
    if unlockFrame._overlay then
        unlockFrame._overlay:SetColorTexture(0.02, 0.03, 0.04, 0)
    end

    -- Phase timings
    local MORPH     = 0.50  -- panel shrinks + lock appears simultaneously
    local IDLE_SPIN = 1.00  -- gears keep spinning at icon size
    local OVERLAP   = 0.75  -- shackle starts this much BEFORE idle spin ends
    local SHACKLE   = 0.75  -- shackle lifts + sweep duration (slowed)

    -- Gear rotation: one continuous motion across MORPH + IDLE_SPIN
    local SPIN_DUR = MORPH + IDLE_SPIN  -- total time gears rotate
    -- Shackle/HUD start time (0.75s before scaling/spinning stops)
    local SHACKLE_START = MORPH + IDLE_SPIN - OVERLAP

    local panelHidden = false
    local panelRealScale = panel and panel:GetScale() or 1
    local elapsed = 0
    local fadeInSynced = false

    -- Grid glitch starts immediately and lasts 0.75s
    local GLITCH_DUR = 0.75
    local GRID_START = 0  -- grid begins immediately
    local gridStarted = false

    -- Reset cursor speed so the first hover isn't blocked by a stale value
    EllesmereUI._unlockCursorSpeed = 0

    unlockFrame:SetScript("OnUpdate", function(self, dt)
        -- Sample cursor position and compute speed for hover intent detection
        do
            local scale = UIParent:GetEffectiveScale()
            local nx, ny = GetCursorPosition()
            nx = nx / scale; ny = ny / scale
            if dt > 0 then
                local dx = nx - EllesmereUI._unlockCursorX
                local dy = ny - EllesmereUI._unlockCursorY
                -- Store squared speed to avoid sqrt; TryExpand compares against squared threshold
                EllesmereUI._unlockCursorSpeed = (dx * dx + dy * dy) / (dt * dt)

                -- After arrow-key nudge collapsed a mover, re-expand it
                -- once the cursor moves and is still hovering the mover.
                if selectedMover and selectedMover._nudgeCollapsed then
                    local moved = (dx ~= 0 or dy ~= 0)
                    if moved then
                        selectedMover._nudgeCollapsed = nil
                        if selectedMover:IsMouseOver() then
                            if selectedMover._showOverlayText then
                                selectedMover._showOverlayText()
                                hoveredMover = selectedMover
                            end
                        end
                    end
                end
            end
            EllesmereUI._unlockCursorX = nx; EllesmereUI._unlockCursorY = ny
        end

        -- Re-expand selected mover when no other mover is being hovered
        if selectedMover and not selectedMover._hoverConfirmed and not hoveredMover then
            if not selectedMover._dragging and selectedMover._showOverlayText then
                selectedMover._showOverlayText()
            end
        end

        elapsed = elapsed + dt

        ---------------------------------------------------------------
        --  Background overlay fade: 0 → full alpha over 0.75 seconds
        --  (synced with grid glitch duration)
        ---------------------------------------------------------------
        local OVERLAY_FADE_DUR = 0.75
        if unlockFrame._overlay then
            local oa = min(1, elapsed / OVERLAY_FADE_DUR) * (unlockFrame._overlayMaxAlpha or 0.20)
            unlockFrame._overlay:SetColorTexture(0.02, 0.03, 0.04, oa)
        end

        ---------------------------------------------------------------
        --  Grid glitch overlay — runs independently of lock phases
        --  Starts at GRID_START (beginning of idle spin, 1s earlier)
        ---------------------------------------------------------------
        if elapsed >= GRID_START then
            if not gridStarted then
                gridStarted = true
                if gridFrame then
                    gridFrame:Rebuild()
                    if gridMode ~= "disabled" then gridFrame:Show() end
                    gridFrame:SetAlpha(0)
                end
                if hudFrame then
                    hudFrame:Show()
                    hudFrame:SetAlpha(1)
                    -- Position off-screen (will slide down during shackle)
                    hudFrame:ClearAllPoints()
                    local ppS = hudFrame:GetScale() or 1
                    hudFrame:SetPoint("TOP", UIParent, "TOP", 0, (BANNER_PX_H + 10) * ppS)
                end
                for _, barKey in ipairs(ALL_BAR_ORDER) do
                    -- Skip bars that have a registered element (avoids duplicates)
                    if not registeredElements[barKey] then
                        local m = CreateMover(barKey)
                        if m then m:Sync(); m:SetAlpha(0) end
                    end
                end
                -- Registered elements (unit frames, etc.)
                RebuildRegisteredOrder()
                for _, key in ipairs(registeredOrder) do
                    local m = CreateMover(key)
                    if m then m:Sync(); m:SetAlpha(0) end
                end
                -- Sort frame levels: smaller movers render on top
                SortMoverFrameLevels()
                -- Re-apply saved anchor positions and refresh anchored mover text
                ReapplyAllAnchors()
                wipe(pendingPositions)
                for bk, _ in pairs(movers) do
                    if movers[bk].RefreshAnchoredText then
                        movers[bk]:RefreshAnchoredText()
                    end
                end

                -- Info overlays on Blizzard-owned elements (chat, micro, bags, encounter)
                -- Start at alpha 0; the mover fade-in loop below handles them.
                ShowBlizzOwnedOverlays(unlockFrame)
                for _, bov in pairs(_blizzOwnedOverlays) do
                    bov:SetAlpha(0)
                end

                -- Retry ticker: some addons (CDM) may not have their bar
                -- frames ready yet. Poll briefly to catch late arrivals.
                local retryAttempts = 0
                local retryTicker
                retryTicker = C_Timer.NewTicker(0.5, function()
                    retryAttempts = retryAttempts + 1
                    if not isUnlocked then retryTicker:Cancel(); return end
                    -- Ask addons to re-register elements they may not have
                    -- registered yet (CDM bars that were still building, etc.)
                    if EllesmereUI._unlockRegistrationDirty or retryAttempts <= 3 then
                        if _G._ECME_RegisterUnlock then _G._ECME_RegisterUnlock() end
                        if _G._ECME_RegisterTBBUnlock then _G._ECME_RegisterTBBUnlock() end
                    end
                    RebuildRegisteredOrder()
                    local spawned = false
                    local missing = false
                    for _, rk in ipairs(registeredOrder) do
                        if not movers[rk] then
                            local rm = CreateMover(rk)
                            if rm then
                                rm:Sync()
                                rm:SetAlpha(darkOverlaysEnabled and 1 or MOVER_ALPHA)
                                rm:Show()
                                spawned = true
                            else
                                missing = true
                            end
                        elseif not movers[rk]:IsShown() then
                            -- Mover exists but bar frame was not ready on
                            -- first Sync -- re-sync now that it may be available
                            local re = registeredElements[rk]
                            if not (re and re.isHidden and re.isHidden()) then
                                local rm = movers[rk]
                                rm:Sync()
                                if rm:IsShown() then
                                    rm:SetAlpha(darkOverlaysEnabled and 1 or MOVER_ALPHA)
                                    spawned = true
                                else
                                    missing = true
                                end
                            end
                        end
                    end
                    if spawned then
                        SortMoverFrameLevels()
                        ReapplyAllAnchors()
                    end
                    -- Stop once every mover is visible, or after timeout
                    if not missing or retryAttempts >= 20 then
                        retryTicker:Cancel()
                    end
                end)
            end

            local glitchT = elapsed - GRID_START
            local glitchProgress = min(1, glitchT / GLITCH_DUR)

            -- (Banner slides down during shackle phase, not here)

            -- Movers fade in over 0.75s, delayed by 0.5s
            local MOVER_DELAY = 0.50
            local moverFadeT = glitchT - MOVER_DELAY
            for _, m in pairs(movers) do
                if m:IsShown() then
                    if moverFadeT > 0 then
                        -- Re-sync once right as movers begin fading in so any
                        -- frames that were nil at initial sync are now ready.
                        if not fadeInSynced then
                            fadeInSynced = true
                            for _, rm in pairs(movers) do rm:Sync() end
                        end
                        m:SetAlpha((darkOverlaysEnabled and 1 or MOVER_ALPHA) * min(1, moverFadeT / GLITCH_DUR))
                    else
                        m:SetAlpha(0)
                    end
                end
            end
            -- Blizzard-owned overlays fade in on the same curve
            for _, bov in pairs(_blizzOwnedOverlays) do
                if bov:IsShown() then
                    if moverFadeT > 0 then
                        bov:SetAlpha(min(1, moverFadeT / GLITCH_DUR))
                    else
                        bov:SetAlpha(0)
                    end
                end
            end

            -- Grid glitch effect
            if gridFrame and gridFrame:IsShown() then
                local baseA = glitchProgress
                local flicker = 0
                if glitchProgress < 0.9 then
                    local intensity = (1 - glitchProgress) * 0.7
                    local t1 = glitchT * 37.3
                    local t2 = glitchT * 13.7
                    local t3 = glitchT * 71.1
                    flicker = (sin(t1) * 0.4 + sin(t2) * 0.35 + sin(t3) * 0.25) * intensity
                    if sin(glitchT * 5.3) > 0.85 and glitchProgress < 0.6 then
                        flicker = flicker - 0.5
                    end
                end
                gridFrame:SetAlpha(max(0, min(1, baseA + flicker)))
            end
        end

        -------------------------------------------------------------------
        --  Continuous gear rotation: one smooth ease-out across MORPH +
        --  IDLE_SPIN combined. Rotation goes from TOTAL_GEAR_ROT → 0.
        -------------------------------------------------------------------
        local gearRot = 0
        -- Extended taper with quintic ease-out for imperceptible final frames
        local SPIN_TAPER = SPIN_DUR + 0.5
        if elapsed < SPIN_TAPER then
            local spinT = elapsed / SPIN_TAPER
            -- Quintic ease-out: (1-t)^5 — extremely gradual deceleration
            local inv = 1 - spinT
            local eased = 1 - inv * inv * inv * inv * inv
            gearRot = TOTAL_GEAR_ROT * (1 - eased)
        end
        outerTex:SetRotation(gearRot)
        innerTex:SetRotation(-gearRot)

        -------------------------------------------------------------------
        --  Phase 1: Panel shrinks + fades while lock container scales down
        --           from startScale → BASE_SCALE over MORPH seconds.
        --           After MORPH, container stays at BASE_SCALE (no hard snap).
        -------------------------------------------------------------------
        if elapsed < MORPH then
            local t = EaseInOutCubic(elapsed / MORPH)
            local sc = startScale + (BASE_SCALE - startScale) * t

            -- Panel scales down, slides to center, and fades out
            -- Panel scales down + fades out (relative to its real scale)
            if panel and not panelHidden then
                local s = panelRealScale * max(0.01, 1 - t)
                panel:SetScale(s)
                -- Alpha fades to 0 in 0.25s (twice as fast as the scale)
                local alphaT = min(1, elapsed / 0.25)
                panel:SetAlpha(1 - alphaT)
                if t > 0.95 then
                    panelHidden = true
                    panel:SetScale(panelRealScale)
                    panel:SetAlpha(1)
                    if EllesmereUI and EllesmereUI.Hide then
                        EllesmereUI:Hide()
                    end
                end
            end

            -- Scale the container uniformly
            container:SetScale(sc)

            -- Fade textures in: delayed 0.25s, then 0→1 over remaining 0.25s
            -- Top stays hidden until shackle phase
            local LOGO_FADE_DELAY = 0.15
            local logoAlpha = 0
            if elapsed > LOGO_FADE_DELAY then
                logoAlpha = min(1, (elapsed - LOGO_FADE_DELAY) / (MORPH - LOGO_FADE_DELAY))
            end
            outerTex:SetAlpha(logoAlpha)
            innerTex:SetAlpha(logoAlpha)
            topTex:SetAlpha(0)
            return
        end

        -- Ensure panel is hidden (one-time cleanup, no visual snap)
        if not panelHidden then
            panelHidden = true
            if panel then panel:SetScale(panelRealScale); panel:SetAlpha(1) end
            if EllesmereUI and EllesmereUI.Hide then EllesmereUI:Hide() end
        end

        -- Post-morph: container at final scale, inner/outer fully visible
        -- (these are already at their final values from the last morph frame,
        --  but we set them once cleanly without causing a visual snap)
        container:SetScale(BASE_SCALE)

        -------------------------------------------------------------------
        --  Shackle + HUD: starts at SHACKLE_START (0.25s before spin ends)
        --  Overlaps the final gear deceleration.
        -------------------------------------------------------------------
        local shackleT = elapsed - SHACKLE_START
        if shackleT >= 0 and shackleT < SHACKLE then
            local t = EaseInOutCubic(shackleT / SHACKLE)
            -- Top piece fades from 0→100% over 0.5s, delayed 0.2s from shackle start
            -- (movement still starts immediately, only alpha is delayed)
            local TOP_FADE_IN = 0.25
            local TOP_FADE_DELAY = 0.20
            local topAlphaT = shackleT - TOP_FADE_DELAY
            if topAlphaT > 0 then
                topTex:SetAlpha(min(1, topAlphaT / TOP_FADE_IN))
            else
                topTex:SetAlpha(0)
            end
            topTex:ClearAllPoints()
            topTex:SetPoint("CENTER", container, "CENTER", 0, SHACKLE_LIFT * t)

            -- Banner slides down from off-screen, synced with shackle
            if hudFrame and hudFrame:IsShown() then
                local ppS = hudFrame:GetScale() or 1
                local offScreen = (BANNER_PX_H + 10) * ppS
                local bannerY = offScreen * (1 - t)
                hudFrame:ClearAllPoints()
                hudFrame:SetPoint("TOP", UIParent, "TOP", 0, bannerY)
            end

            -- Sweep runs during shackle phase
            local sweepTex = openAnimFrame._sweep
            if sweepTex then
                if not sweepTex:IsShown() then sweepTex:Show() end
                local st = min(1, shackleT / SHACKLE)
                local clipW = openAnimFrame._sweepClip:GetWidth()
                local xPos = -20 + (clipW + 40) * st
                sweepTex:ClearAllPoints()
                sweepTex:SetPoint("CENTER", openAnimFrame._sweepClip, "LEFT", xPos, 0)
                local sweepAlpha
                if st < 0.15 then sweepAlpha = st / 0.15
                elseif st > 0.85 then sweepAlpha = (1 - st) / 0.15
                else sweepAlpha = 1 end
                sweepTex:SetAlpha(0.30 * sweepAlpha)
            end
        end

        -- After shackle completes, settle top piece and hide sweep
        if shackleT >= SHACKLE then
            topTex:SetAlpha(1)
            topTex:ClearAllPoints()
            topTex:SetPoint("CENTER", container, "CENTER", 0, SHACKLE_LIFT)
            if openAnimFrame._sweep then openAnimFrame._sweep:Hide() end
        end

        -- Still in idle spin phase (before shackle or during overlap), keep waiting
        if elapsed < SPIN_DUR and shackleT < SHACKLE then
            return
        end

        -- If shackle hasn't finished yet, keep going
        if shackleT < SHACKLE then
            return
        end

        -------------------------------------------------------------------
        --  Done — logo stays at full alpha, grid fully visible,
        --  banner is at final position (flush with top of screen)
        -------------------------------------------------------------------
        openAnimFrame:SetAlpha(1)
        outerTex:SetRotation(0)
        innerTex:SetRotation(0)
        if gridFrame then gridFrame:SetAlpha(1) end
        if hudFrame then
            hudFrame:ClearAllPoints()
            hudFrame:SetPoint("TOP", UIParent, "TOP", 0, 0)
        end
        self:SetScript("OnUpdate", nil)

        -- Start anchor connector line updates now that movers are visible
        if unlockFrame._anchorLineDriver then
            unlockFrame._anchorLineDriver:Show()
        end
        if unlockFrame._anchorLineFrame then
            unlockFrame._anchorLineFrame:Show()
        end

        -- ReapplyAllAnchors during open sets hasChanges; reset ONLY if
        -- the user hasn't already interacted (e.g. dragged during animation).
        if not next(pendingPositions) then
            hasChanges = false
        end

        -- Auto-select a mover if requested (e.g. from cog popup link)
        if EllesmereUI._unlockAutoSelectKey then
            local autoKey = EllesmereUI._unlockAutoSelectKey
            EllesmereUI._unlockAutoSelectKey = nil
            C_Timer.After(0.6, function()
                if movers[autoKey] then
                    SelectMover(movers[autoKey])
                end
            end)
        end

        -- Fade ONLY the lock logo to 0% over 2 seconds, after 1s hold.
        -- Banner stays visible permanently (it has functional toggles).
        local LOGO_HOLD = 1.0
        local LOGO_FADE_DUR = 2.0
        local fadeElapsed = 0
        if not logoFadeFrame then
            logoFadeFrame = CreateFrame("Frame", nil, UIParent)
        end
        logoFadeFrame:Show()
        logoFadeFrame:SetScript("OnUpdate", function(ff, fdt)
            fadeElapsed = fadeElapsed + fdt
            if fadeElapsed < LOGO_HOLD then return end
            local ft = fadeElapsed - LOGO_HOLD
            if ft >= LOGO_FADE_DUR then
                if openAnimFrame then openAnimFrame:SetAlpha(0) end
                ff:SetScript("OnUpdate", nil)
                ff:Hide()
                return
            end
            local t = ft / LOGO_FADE_DUR
            if openAnimFrame then
                openAnimFrame:SetAlpha(1 - t)
            end
        end)

        -- Show one-time toolbar tip (after animation settles)
        ns.ShowUnlockTip()
    end)
end

-------------------------------------------------------------------------------
--  Close Unlock Mode — routes through save/discard logic
-------------------------------------------------------------------------------
function ns.CloseUnlockMode(afterFn)
    if not isUnlocked then
        if afterFn then afterFn() end
        return
    end
    ns.RequestClose(false, afterFn)  -- triggers popup if there are unsaved changes
end

-- Expose for the options page BuildUnlockPage
-- ns.OpenUnlockMode and ns.CloseUnlockMode are already defined above as
-- function ns.OpenUnlockMode() and function ns.CloseUnlockMode()
ns.CloseUnlockMode = ns.CloseUnlockMode

-- Expose on the global EllesmereUI so SelectPage can intercept "Unlock Mode"
if EllesmereUI then
    EllesmereUI._openUnlockMode = ns.OpenUnlockMode
end

-- Toggle helper + active flag alias used by options pages
if EllesmereUI and not EllesmereUI.ToggleUnlockMode then
    function EllesmereUI:ToggleUnlockMode()
        if isUnlocked then
            ns.CloseUnlockMode()
        else
            ns.OpenUnlockMode()
        end
    end
    -- Alias so options pages can read the state
    -- (isUnlocked is local; _unlockActive is set by Open/Close above)
    -- _unlockModeActive is a getter-style property via metatable isn't
    -- practical in Lua 5.1, so we just keep it in sync.
end

-- When the options panel tries to show while unlock mode is active,
-- close unlock mode first (with save flow), then re-show the panel after.
if EllesmereUI and EllesmereUI.RegisterOnShow then
    EllesmereUI:RegisterOnShow(function()
        if isUnlocked then
            -- Hide the panel immediately — it shouldn't show during unlock mode
            local panel = EllesmereUI._mainFrame
            if panel then panel:Hide() end
            -- Close unlock mode, then re-open the panel after
            ns.CloseUnlockMode(function()
                if EllesmereUI.Toggle then EllesmereUI:Toggle() end
            end)
        end
    end)
end


-------------------------------------------------------------------------------
--  Combat auto-suspend / resume
--  Entering combat hides unlock mode UI but preserves all pending changes.
--  Leaving combat re-opens unlock mode with the same state.
-------------------------------------------------------------------------------
local function SuspendForCombat()
    if not isUnlocked then return end
    combatSuspended = true

    -- Restore objective tracker
    if objTrackerWasVisible then
        local objTracker = _G.ObjectiveTrackerFrame
        if objTracker then
            objTracker:SetAlpha(1)
            local wasEnabled = objTracker._eabMouseWasEnabled
            if objTracker.EnableMouse then
                pcall(objTracker.EnableMouse, objTracker, wasEnabled and true or false)
            end
        end
    end
    -- Re-apply user visibility setting (handles "never" mode for both tracker + bg)
    if _G.EllesmereUIQuestTracker and _G.EllesmereUIQuestTracker.UpdateVisibility then
        _G.EllesmereUIQuestTracker.UpdateVisibility()
    end

    -- Notify beacon reminders to restore
    if _G._EABR_BeaconRefresh then pcall(_G._EABR_BeaconRefresh) end

    -- Hide unlock UI without clearing state
    isUnlocked = false
    EllesmereUI._unlockActive = false
    EllesmereUI._unlockModeActive = false

    if unlockFrame then
        unlockFrame:SetScript("OnUpdate", nil)
        unlockFrame:Hide()
    end
    if logoFadeFrame then logoFadeFrame:SetScript("OnUpdate", nil); logoFadeFrame:Hide() end
    if openAnimFrame then openAnimFrame:Hide() end
    if lockAnimFrame then lockAnimFrame:Hide() end
    if gridFrame then gridFrame:Hide() end
    if hudFrame then hudFrame:Hide() end
    if unlockTipFrame then unlockTipFrame:SetScript("OnUpdate", nil); unlockTipFrame:Hide() end
    DeselectMover()
    for _, m in pairs(movers) do m:Hide() end
    HideAllGuidesAndHighlight()
    HideBlizzOwnedOverlays()
    if arrowKeyFrame then arrowKeyFrame:Hide() end
    selectedMover = nil
    selectElementPicker = nil

    -- Restore action bar alpha from saved settings (so bars are usable during combat)
    if EAB and EAB.RefreshMouseover then
        EAB:RefreshMouseover()
    end
end

local function ResumeAfterCombat()
    if not combatSuspended then return end
    combatSuspended = false
    if InCombatLockdown() then return end  -- safety check

    -- Re-enter unlock mode but skip snapshot/reset since we preserved state
    isUnlocked = true
    EllesmereUI._unlockActive = true
    EllesmereUI._unlockModeActive = true

    -- Re-hide objective tracker
    local objTracker = _G.ObjectiveTrackerFrame
    if objTracker and objTracker:IsShown() then
        objTrackerWasVisible = true
        objTracker:SetAlpha(0)
        if objTracker.EnableMouse then pcall(objTracker.EnableMouse, objTracker, false) end
    end
    local qtBg = _G.EllesmereUIQTBackground
    if qtBg then qtBg:SetAlpha(0) end

    -- Notify beacon reminders to hide
    if _G._EABR_BeaconRefresh then pcall(_G._EABR_BeaconRefresh) end

    -- Re-show unlock UI
    if arrowKeyFrame then arrowKeyFrame:Show() end
    if unlockFrame then unlockFrame:Show(); unlockFrame:SetAlpha(1) end
    if gridFrame and gridMode ~= "disabled" then gridFrame:Show() end
    if hudFrame then hudFrame:Show() end

    -- Strip any temporary anchor-target shift (e.g. ResourceBars "Shift Elements
    -- if No Resource") that may have re-applied during the combat-suspend window
    -- (when _unlockActive was false). _unlockActive is true again above, so the
    -- provider returns 0 and this snaps shifted children back BEFORE the movers
    -- re-sync below capture their positions. Gated so non-shift profiles do
    -- nothing. Mirrors the OpenUnlockMode entry strip.
    if _G._ERB_ShiftWantsApply and _G._ERB_ShiftWantsApply()
       and EllesmereUI.ReapplyAllUnlockAnchors then
        -- Force edge-preservation so custom-growth anchored bars snap to their
        -- fixed growth edge, not the center-offset position. Reset via pcall so
        -- the flag can't leak. Mirrors the OpenUnlockMode entry strip.
        EllesmereUI._reapplyForceEdgePreserve = true
        pcall(EllesmereUI.ReapplyAllUnlockAnchors)
        EllesmereUI._reapplyForceEdgePreserve = false
    end

    -- Re-sync all movers (Sync shows live ones and hides stale/hidden ones).
    for _, m in pairs(movers) do
        m:Sync()
        if m:IsShown() then
            m:SetAlpha(darkOverlaysEnabled and 1 or MOVER_ALPHA)
        end
    end
    SortMoverFrameLevels()
    if unlockFrame and unlockFrame._anchorLineDriver then
        unlockFrame._anchorLineDriver:Show()
    end
    if unlockFrame and unlockFrame._anchorLineFrame then
        unlockFrame._anchorLineFrame:Show()
    end
    -- Deferred: re-apply CENTER anchor to all bar frames so resizes grow
    -- symmetrically from center rather than from whatever corner anchor
    -- was left by a previous drag or addon rebuild.
    C_Timer.After(0, function()
        for bk, m in pairs(movers) do
            if not m._dragging then
                EllesmereUI.RecenterBarAnchor(bk)
            end
        end
    end)
end

do
    local combatFrame = CreateFrame("Frame")
    combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            SuspendForCombat()
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Small delay to let combat lockdown fully clear
            C_Timer.After(0.5, ResumeAfterCombat)
        end
    end)
end
end  -- end deferred init
