if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnlockMode.lua
--  Unlock Mode: animated transition, grid overlay, draggable movers, snap
--  guides, position memory, return-to-options flow. Elements from any addon
--  register via EllesmereUI:RegisterUnlockElements().
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...
ns = ns.__euiCoreNS or ns  -- standalone builds: the core's own table (EllesmereUI.lua)
local EAB = ns.EAB  -- may be nil if loaded by a non-ActionBars addon

-------------------------------------------------------------------------------
--  Registration API -- on the EllesmereUI global so ALL addons share one
--  table regardless of which copy of this file runs.
-------------------------------------------------------------------------------
if not EllesmereUI._unlockRegisteredElements then
    EllesmereUI._unlockRegisteredElements = {}
    EllesmereUI._unlockRegisteredOrder    = {}
    EllesmereUI._unlockRegistrationDirty  = true
end

if not EllesmereUI.RegisterUnlockElements then
    -- Normalize short field aliases (savePos) to the long names used
    -- throughout unlock mode (savePosition).
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
            -- Stamp the owning folder (per-element wins over call-site): export/import
            -- attributes the element and its anchor/match links to a module for per-module layout export.
            if folder and not elem.folder then elem.folder = folder end
            self._unlockRegisteredElements[elem.key] = elem
        end
        self._unlockRegistrationDirty = true
        -- Fresh registration flushes spec-override unlock layers' deferred writes
        -- for late/conditional registrants (party/raid containers, CDM bars).
        if EllesmereUI.SpecOverrides_UnlockPokeFlush then
            EllesmereUI.SpecOverrides_UnlockPokeFlush()
        end
    end
end

if not EllesmereUI.UnregisterUnlockElement then
    function EllesmereUI:UnregisterUnlockElement(key)
        self._unlockRegisteredElements[key] = nil
        self._unlockRegistrationDirty = true
    end
end

-- Cross-addon listeners fire on real session open/close only; close passes
-- "exit"/"save"/"discard" as arg 2. Combat suspension does not end the session.
if not EllesmereUI._unlockModeListeners then
    EllesmereUI._unlockModeListeners = {}
end

if not EllesmereUI.RegisterUnlockModeListener then
    function EllesmereUI:RegisterUnlockModeListener(owner, listener)
        self._unlockModeListeners[owner] = listener
        if self._unlockModeSessionActive then
            pcall(listener, true)
        end
    end

    function EllesmereUI:UnregisterUnlockModeListener(owner)
        self._unlockModeListeners[owner] = nil
    end

    function EllesmereUI:IsUnlockModeActive()
        return self._unlockModeSessionActive == true
    end

    function EllesmereUI:_NotifyUnlockModeListeners(active, closeAction)
        self._unlockModeSessionActive = active == true
        for _, listener in pairs(self._unlockModeListeners) do
            pcall(listener, self._unlockModeSessionActive, closeAction)
        end
    end
end

-- Already loaded by another addon: bail (registration API above is idempotent;
-- state/frames/animations below must exist only once).
if EllesmereUI._unlockModeLoaded then return end
EllesmereUI._unlockModeLoaded = true

-------------------------------------------------------------------------------
--  Anchor reapply stub (pre-EnsureLoaded): lets child addons (CDM) reposition
--  anchored elements at login before the full body loads; deferred block replaces it.
-------------------------------------------------------------------------------
if not EllesmereUI.ReapplyOwnAnchor then
    EllesmereUI.ReapplyOwnAnchor = function(key)
        if not EllesmereUIDB or not EllesmereUIDB.unlockAnchors then return end
        local info = EllesmereUIDB.unlockAnchors[key]
        if not info or not info.target then return end

        local elems = EllesmereUI._unlockRegisteredElements
        local childElem = elems and elems[key]
        if childElem and childElem.ownsPosition then return end
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

        -- No explicit snap: center came from pixel-aligned target edges/dims; snapping here adds 1px drift from float dust.
        pcall(function()
            EllesmereUI.ClearFramePoints(childBar)
            EllesmereUI.SetFramePoint(childBar, "CENTER", UIParent, "CENTER", centerX, centerY)
        end)
    end
end

-------------------------------------------------------------------------------
--  Early stub: NotifyElementResized -- grow-direction-aware repositioning before
--  unlock mode fully loads; deferred block overwrites it.
-------------------------------------------------------------------------------
if not EllesmereUI.NotifyElementResized then
    EllesmereUI.NotifyElementResized = function(key)
        if not EllesmereUIDB then return end
        -- Skip if anchored (early ReapplyOwnAnchor handles those)
        local anchors = EllesmereUIDB.unlockAnchors
        if anchors and anchors[key] and anchors[key].target then return end

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

        local elems = EllesmereUI._unlockRegisteredElements
        local elem = elems and elems[key]
        local frame = elem and elem.getFrame and elem.getFrame(key)
        if not frame or not frame:GetCenter() then return end

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
        -- Raw fw/2, fh/2 (not floor): odd-dimension frames with integer+0.5 centers
        -- reverse to exact pixel edges; floor() loses the .5 (1px drift).
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

        -- No explicit snap: cx +/- dim/2 reproduces the pixel-aligned edge within float epsilon; snapping can round the wrong way (1px drift/reload).
        pcall(function()
            EllesmereUI.ClearFramePoints(frame)
            EllesmereUI.SetFramePoint(frame, anchor, UIParent, "CENTER", adjX, adjY)
        end)
    end
end

-- Early stub: IsUnlockAnchored -- true if the key has an anchor target in the DB; deferred block overwrites it.
if not EllesmereUI.IsUnlockAnchored then
    EllesmereUI.IsUnlockAnchored = function(unlockKey)
        if not EllesmereUIDB or not EllesmereUIDB.unlockAnchors then return false end
        local ai = EllesmereUIDB.unlockAnchors[unlockKey]
        return ai and ai.target and true or false
    end
end

-- Authoritative position pass fallback: CDM owns this pass when loaded (fires from
-- CollectAndReanchor once async icon population settles). Without CDM nobody
-- triggers EnsureUnlockCore or the final layout pass, so fire it from here.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        C_Timer.After(1.5, function()
            -- CDM already ran EnsureUnlockCore and fires the pass itself.
            if EllesmereUI._applySavedPositions then return end
            -- No CDM: run the deferred block and fire the same pass.
            EllesmereUI:EnsureUnlockCore()
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

-- Synchronous handler at PLAYER_LOGIN, never a timer: on a combat reload, lockdown
-- is not yet re-engaged during PLAYER_LOGIN dispatch, but a timer scheduled here
-- would fire after the loading screen with lockdown back on. Must live in this
-- non-deferred header -- the deferred body only runs via EnsureUnlockCore() during
-- this dispatch (CDM) or later (fallback above), so a handler inside it would miss
-- the in-flight event. Created after Lite's lifecycle frame so every module's
-- OnEnable already ran (bars positioned, frames spawned, elements registered),
-- letting protected children (oUF) anchor before lockdown re-engages; later
-- builders (CDM at PEW) fall through to the retry loop/regen park. The unlock-core
-- cost is paid at PEW anyway -- doing it here just hides it in the loading screen.
-- Deliberately NOT EnsureLoaded: that would pull the whole LoadOnDemand options
-- addon into every login.
do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        EllesmereUI:EnsureUnlockCore()
        if EllesmereUI._applySavedPositions then
            EllesmereUI._applySavedPositions()
        end
    end)
end

-- Screen-edge anchor targets: invisible 1-unit strips just outside each of the
-- four screen edges, so their inner edge IS the screen edge and a link's
-- edge-to-edge offset counts from it. Registered in this non-deferred header so the
-- early ReapplyOwnAnchor stub resolves them at login. isHidden = no mover (never
-- dragged or picked); the no-op savePosition keeps SaveBarPosition's action bar
-- fallback from ever writing these keys.
do
    -- anchor, relative point, anchor, relative point, label, thin axis
    local EDGES = {
        SCREEN_LEFT   = { "TOPRIGHT",   "TOPLEFT",    "BOTTOMRIGHT", "BOTTOMLEFT",  "Left Screen Edge",   "W" },
        SCREEN_RIGHT  = { "TOPLEFT",    "TOPRIGHT",   "BOTTOMLEFT",  "BOTTOMRIGHT", "Right Screen Edge",  "W" },
        SCREEN_TOP    = { "BOTTOMLEFT", "TOPLEFT",    "BOTTOMRIGHT", "TOPRIGHT",    "Top Screen Edge",    "H" },
        SCREEN_BOTTOM = { "TOPLEFT",    "BOTTOMLEFT", "TOPRIGHT",    "BOTTOMRIGHT", "Bottom Screen Edge", "H" },
    }
    function EllesmereUI.IsScreenEdgeKey(key)
        return EDGES[key] ~= nil
    end

    local strips = {}
    local function GetStrip(key) return strips[key] end
    local function IsHidden() return true end
    local function NoSave() end

    local elements = {}
    for key, def in pairs(EDGES) do
        local f = CreateFrame("Frame", nil, UIParent)
        if def[6] == "W" then f:SetWidth(1) else f:SetHeight(1) end
        f:SetPoint(def[1], UIParent, def[2], 0, 0)
        f:SetPoint(def[3], UIParent, def[4], 0, 0)
        strips[key] = f
        elements[#elements + 1] = {
            key = key, label = def[5],
            getFrame = GetStrip, savePosition = NoSave, isHidden = IsHidden,
            noAnchorTo = true, noResize = true, noSizeMatchTarget = true,
        }
    end
    EllesmereUI:RegisterUnlockElements(elements)

    -- Linked children sit at absolute offsets from UIParent's center, so any change
    -- of UIParent's size in units (aspect ratio, window size, UI scale) leaves them
    -- stale. This frame follows UIParent's size and re-runs every edge's chain
    -- (batched into one pass per frame).
    local watch = CreateFrame("Frame", nil, UIParent)
    watch:SetAllPoints(UIParent)
    watch:SetScript("OnSizeChanged", function()
        local propagate = EllesmereUI.PropagateAnchorChain
        if not propagate then return end
        for key in pairs(EDGES) do propagate(key) end
    end)
end

-- DEFERRED: heavy body (4900+ lines) runs on first EnsureUnlockCore() call
-- (PLAYER_LOGIN / CDM setup / unlock-mode open / EnsureLoaded). Own slot, not
-- _deferredInits: login must run this WITHOUT loading the options addon.
EllesmereUI._unlockCoreInit = function()
local UM = {}  -- unlock state and late-bound functions shared across the unlock files
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

-- WaitForSize: defer callback one frame so the layout engine has flushed.
local function WaitForSize(frame, callback)
    C_Timer.After(0, callback)
end

-- Blank or restore a bar frame's alpha around a resize. Action Bars tracks the
-- alpha of the bars it fades instead of reading it back, so it is told.
function EllesmereUI._UnlockSetBarAlpha(frame, a)
    frame:SetAlpha(a)
    local note = EllesmereUI._EABNoteAlpha
    if note then note(frame, a) end
end

-- DeferMoverSync: sync now (no blink) and again next frame to catch layout-engine
-- flush moves; hides the bar frame meanwhile to prevent a visual jump.
local function DeferMoverSync(m, syncFn, barFrame)
    if not m then return end
    if barFrame then EllesmereUI._UnlockSetBarAlpha(barFrame, 0) end
    syncFn(m)
    C_Timer.After(0, function()
        if m then syncFn(m) end
        if barFrame then EllesmereUI._UnlockSetBarAlpha(barFrame, 1) end
    end)
end

-- After a setWidth/setHeight rebuild snaps the bar to its stored position mid-unlock,
-- re-place it at the mover's current screen position (else resizing makes it jump).
-- On EllesmereUI to avoid an upvalue in CreateMover (Lua 5.1 limit: 60).
function EllesmereUI.RepositionBarToMover(barKey)
    if not UM.isUnlocked then return end
    local m = UM.movers[barKey]
    if not m then return end
    local bar = UM.GetBarFrame(barKey)
    if not bar then return end
    local mX, mY = m:GetCenter()
    local barScale = bar:GetEffectiveScale()
    if not mX or not mY or not barScale or barScale <= 0 then return end
    -- Pin center to center: the mover still has the old size here, so a corner
    -- pin would shift the element by half the size change. The mover center is
    -- converted into the bar's own scale (SetPoint offsets use the bar's scale).
    local ratio = m:GetEffectiveScale() / barScale
    pcall(function()
        EllesmereUI.ClearFramePoints(bar)
        EllesmereUI.SetFramePoint(bar, "CENTER", UIParent, "BOTTOMLEFT", mX * ratio, mY * ratio)
    end)
end

-- RecenterBarAnchor is defined below, after its dependencies (isUnlocked, movers, registeredElements, GetBarFrame, GetBarGrowDirActual).

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local FONT_PATH   = (EllesmereUI.GetFontPath("extras"))
    or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"

-- At very low UI scale the overlays/top bar are hard to read, so they're nudged up.
-- The `UIParent:GetEffectiveScale() < 0.6` test is inlined at each use site (not a
-- helper) because overlay builders are already at Lua 5.1's 60-upvalue limit.
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

-- Movable bar keys (action bars + stance + micro + bag); populated by EAB if loaded, else empty.
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
UM.unlockFrame = nil       -- the full-screen overlay
UM.gridFrame = nil         -- grid line container
local guidePool = {}       -- reusable alignment guide lines
local movers = {}          -- { [barKey] = moverFrame }
UM.isUnlocked = false
function EllesmereUI.IsUnlockModeActive() return UM.isUnlocked end
UM.gridMode = "dimmed"     -- "disabled", "dimmed", "bright"
UM.snapEnabled = true      -- magnet/snap state (runtime); must precede SnapPosition
local lockAnimFrame        -- lock assembly animation (close)
UM.openAnimFrame = nil     -- lock animation frame (open)
UM.logoFadeFrame = nil     -- the 2s logo+title fade-out timer frame
local pendingPositions = {}   -- { [barKey] = {point,relPoint,x,y} } -- unsaved changes
local snapshotPositions = {}  -- original positions captured when unlock mode opens
local snapshotAnchors = {}    -- original anchor data captured when unlock mode opens
local snapshotSizes = {}      -- original sizes captured when unlock mode opens
local snapshotWidthMatch = {} -- original width match DB captured when unlock mode opens
local snapshotHeightMatch = {} -- original height match DB captured when unlock mode opens
local snapshotGrowDirs = {}   -- original growth directions captured when unlock mode opens
-- Spec-override banner refresh = EllesmereUI._unlockRefreshSpecOvMarks (namespace
-- field, not local: deferred-init function is at Lua 5.1's 200-local cap). Layer
-- banking is a wholesale harvest at CommitPositions.
UM.hasChanges = false         -- true if user dragged anything this session
local combatSuspended = false  -- true if unlock mode was auto-closed by combat
UM.objTrackerWasVisible = false     -- track objective tracker state for restore

-- Grid mode helpers
local GRID_ALPHA_DIMMED = 0.15
local GRID_ALPHA_BRIGHT = 0.30
local GRID_CENTER_DIMMED = 0.25
local GRID_CENTER_BRIGHT = 0.50
local GRID_HUD_BRIGHT = 0.60   -- matches HUD_ON_ALPHA
local GRID_HUD_DIMMED = 0.45
local GRID_HUD_OFF    = 0.30   -- matches HUD_OFF_ALPHA

local function GridBaseAlpha()
    return UM.gridMode == "bright" and GRID_ALPHA_BRIGHT or GRID_ALPHA_DIMMED
end
local function GridCenterAlpha()
    return UM.gridMode == "bright" and GRID_CENTER_BRIGHT or GRID_CENTER_DIMMED
end
local function GridHudAlpha()
    if UM.gridMode == "bright" then return GRID_HUD_BRIGHT end
    if UM.gridMode == "dimmed" then return GRID_HUD_DIMMED end
    return GRID_HUD_OFF
end
local function GridLabelText()
    if UM.gridMode == "bright" then return "Grid Lines\nBright" end
    if UM.gridMode == "dimmed" then return "Grid Lines\nDimmed" end
    return "Grid Lines\nDisabled"
end
local function CycleGridMode()
    if UM.gridMode == "dimmed" then UM.gridMode = "bright"
    elseif UM.gridMode == "bright" then UM.gridMode = "disabled"
    else UM.gridMode = "dimmed" end
end
UM.flashlightEnabled = false     -- cursor flashlight toggle
UM.darkOverlaysEnabled = true     -- dark overlay backgrounds on movers
UM.coordsEnabled = false        -- show coordinates for all elements at all times
local _blizzOwnedOverlays = {}  -- info overlays for Blizzard-controlled elements
UM.unlockTipFrame = nil        -- one-time "how to use" tip frame
UM.selectedMover = nil         -- currently selected mover frame (for arrow key nudging)
UM.arrowKeyFrame = nil         -- invisible frame that captures arrow key input
UM.selectElementPicker = nil   -- mover currently in "Select Element" pick mode (nil = off)
local SELECT_ELEMENT_ALPHA = 0.50  -- overlay alpha during select-element pick mode
local SELECT_ELEMENT_FADE  = 0.50  -- seconds for the fade transition

-- Maps barKey -> settings location for "Element Options" nav: module =
-- RegisterModule folder; page = page tab (PAGE_* value); sectionName = string
-- passed to SectionHeader(); preSelectFn = optional dropdown-setter run before
-- the page builds. On EllesmereUI to dodge CreateMover's 60-upvalue cap.
local function SelectActionBar(key)
    return function()
        -- Direct setter (if options module already built) + pending flag consumed
        -- at Bar Display page build. Mirrors the unit-frame path.
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
-- Mini-frame pre-select factory (ToT/FoT/Pet/Boss live on "Mini Frames" with
-- their own dropdown). On EllesmereUI, not file-local, to avoid a local in this limit-sensitive deferred function.
EllesmereUI._SelectMiniUnit = function(unit)
    return function()
        if EllesmereUI._setMiniUnit then EllesmereUI._setMiniUnit(unit) end
        EllesmereUI._pendingMiniSelect = unit
    end
end
-- Capture entries registered before this deferred body runs (DataBars writes
-- per-bar EDB_ keys at PLAYER_LOGIN, which fires first); merged back below so this
-- assignment never wipes them. Namespace-stashed: function is at its local/upvalue cap.
EllesmereUI._elemMapPre = EllesmereUI._ELEMENT_SETTINGS_MAP
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

    -- Resource Bars (no dropdown -- each bar has its own section)
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
    ["Bar9"]      = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("Bar9"),      highlightText = "Icon Size" },
    ["Bar10"]     = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("Bar10"),     highlightText = "Icon Size" },
    ["StanceBar"] = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("StanceBar"), highlightText = "Icon Size" },
    ["PetBar"]    = { module = "EllesmereUIActionBars",          page = "Bar Display",                  sectionName = "LAYOUT",  preSelectFn = SelectActionBar("PetBar"),    highlightText = "Icon Size" },

    -- Action Bars -- data bars, micro menu and bags (their own tabs, no bar dropdown)
    ["XPBar"]    = { module = "EllesmereUIActionBars",          page = "XP Bar",                       sectionName = "CORE",              highlightText = "Width" },
    ["RepBar"]   = { module = "EllesmereUIActionBars",          page = "Menu, Bags & Rep Bars",        sectionName = "REPUTATION BAR",    highlightText = "Width" },
    ["FavorBar"] = { module = "EllesmereUIActionBars",          page = "Menu, Bags & Rep Bars",        sectionName = "HOUSE FAVOR BAR",   highlightText = "Width" },
    ["MicroBar"] = { module = "EllesmereUIActionBars",          page = "Menu, Bags & Rep Bars",        sectionName = "MICRO MENU & BAGS" },
    ["BagBar"]   = { module = "EllesmereUIActionBars",          page = "Menu, Bags & Rep Bars",        sectionName = "MICRO MENU & BAGS" },

    -- Aura Buff Reminders
    ["EABR_Reminders"] = { module = "EllesmereUIAuraBuffReminders", page = "Auras, Buffs & Consumables", sectionName = "DISPLAY" },

    -- Quality of Life (FPS + Secondary Stats live on the QoL page's EXTRAS section)
    ["EUI_FPS"]            = { module = "EllesmereUIQoL", page = "QoL", sectionName = "EXTRAS", highlightText = "Show FPS Counter" },
    ["EUI_SecondaryStats"] = { module = "EllesmereUIQoL", page = "QoL", sectionName = "EXTRAS", highlightText = "Secondary Stat Display" },

    -- Battle Res + Bloodlust (bottom of the Quality of Life page)
    ["EUI_Alerts"]         = { module = "EllesmereUIQoL",             page = "QoL",   sectionName = "ALERTS",            highlightText = "Combat Alert" },
    ["EUI_BattleRes"]      = { module = "EllesmereUIQoL",             page = "QoL",   sectionName = "BATTLE RES",        highlightText = "Enable BattleRes Icon" },
    ["EUI_Bloodlust"]      = { module = "EllesmereUIQoL",             page = "QoL",   sectionName = "BLOODLUST TRACKER", highlightText = "Enable Bloodlust Icon" },

    -- Mythic+ Tools
    ["EMT_MythicTimer"]    = { module = "EllesmereUIMythicTimer",     page = "Mythic+ Timer",     sectionName = "DISPLAY",           highlightText = "Scale" },
    ["EMT_TargetedSpellBars"] = { module = "EllesmereUIMythicTimer",  page = "Targeted Spell Bars", sectionName = "TARGETED SPELL BARS", highlightText = "Enable Targeted Spell Bars" },
    ["EMT_TargetCastBar"]  = { module = "EllesmereUIMythicTimer",     page = "Target/Focus Bars", sectionName = "TARGET CAST BAR",   highlightText = "Enable Target Cast Bar" },
    ["EMT_FocusCastBar"]   = { module = "EllesmereUIMythicTimer",     page = "Target/Focus Bars", sectionName = "FOCUS CAST BAR",    highlightText = "Enable Focus Cast Bar" },

    -- Dragon Riding HUD (Blizz UI Enhanced > Dragon Riding page)
    ["EDR_Cluster"]        = { module = "EllesmereUIBlizzardSkin",    page = "Dragon Riding",     sectionName = "GENERAL",           highlightText = "Enable Skyriding Bar" },

    -- Fixed-position tooltip anchor (Blizz UI Enhanced > Tooltips, Menus & Popups)
    ["EUI_TooltipAnchor"]  = { module = "EllesmereUIBlizzardSkin",    page = "Tooltips, Menus & Popups", sectionName = "BLIZZARD TOOLTIP", highlightText = "Anchor to Cursor" },

    -- Minimap
    ["EBS_Minimap"]        = { module = "EllesmereUIMinimap",         page = "Minimap",           sectionName = "DISPLAY",           highlightText = "Size" },

    -- Damage Meters: windows use dynamic "EDM_Win<i>" keys and resolve to the shared
    -- "EDM_Win" entry via the cog lookup's prefix fallback (top of the tab, like CDM_).
    ["EDM_Win"]            = { module = "EllesmereUIDamageMeters",    page = "Damage Meters" },
    ["EDM_CombatTimer"]    = { module = "EllesmereUIDamageMeters",    page = "Damage Meters",     sectionName = "STANDALONE COMBAT TIMER", highlightText = "Standalone Combat Timer" },
    ["EDM_IconHistory"]    = { module = "EllesmereUIDamageMeters",    page = "Spell History",     sectionName = "ICON HISTORY",      highlightText = "Enable Icon History" },

    -- Raid + Party Frames (separate registered pages/tabs)
    ["RF_RaidFrames"]      = { module = "EllesmereUIRaidFrames",      page = "Raid",              sectionName = "FRAME SIZES",       highlightText = "20 Man Frame Width" },
    ["RF_PartyFrames"]     = { module = "EllesmereUIRaidFrames",      page = "Party",             sectionName = "FRAMES",            highlightText = "Frame Width" },

    -- CDM dynamic bars: "CDM_<key>"/"TBB_<idx>" resolve to these shared tab entries
    -- via the cog lookup's prefix fallback; no sectionName/preSelectFn so bars land
    -- at the top of the tab (deliberately undifferentiated).
    ["CDM_"]               = { module = "EllesmereUICooldownManager", page = "CDM Bars" },
    ["TBB_"]               = { module = "EllesmereUICooldownManager", page = "Tracking Bars" },
}
if EllesmereUI._elemMapPre then
    for k, v in pairs(EllesmereUI._elemMapPre) do
        if EllesmereUI._ELEMENT_SETTINGS_MAP[k] == nil then
            EllesmereUI._ELEMENT_SETTINGS_MAP[k] = v
        end
    end
    EllesmereUI._elemMapPre = nil
end

-- Width Match / Height Match / Anchor To pick modes: only one active at a time; picker mover stored here.
UM.pickMode = nil              -- nil, "widthMatch", "heightMatch", "anchorTo"
UM.pickModeMover = nil         -- the mover that initiated the pick mode
UM.hoveredMover = nil          -- the currently expanded mover (only one at a time)
UM.anchorDropdownFrame = nil    -- lazy-created dropdown for anchor direction selection
UM.anchorDropdownCatcher = nil    -- click-catcher behind anchor dropdown
UM.growDropdownFrame = nil    -- lazy-created dropdown for grow direction selection
UM.growDropdownCatcher = nil    -- click-catcher behind grow dropdown

-- Cursor speed tracking for hover intent detection (stored on EllesmereUI to avoid upvalue pressure)
EllesmereUI._unlockCursorX     = 0
EllesmereUI._unlockCursorY     = 0
EllesmereUI._unlockCursorSpeed = 0   -- pixels/sec at UIParent scale
EllesmereUI._unlockHoverSpeedThresh = 80 * 80 -- squared px/sec threshold (avoids sqrt each frame)
EllesmereUI._unlockHoverIntentDelay = 0.12 -- seconds to wait after settling before expanding

-------------------------------------------------------------------------------
--  Split parts (EUI_UnlockMode_*.lua): share the stable names above through
--  UM, then run the parts here, in their original order. The parts sit in
--  the addon's private namespace and take it from their own file, never
--  through UM: a public slot would let another addon wrap a part and reach it.
-------------------------------------------------------------------------------
UM.EAB, UM.floor, UM.abs = EAB, floor, abs
UM.min, UM.max, UM.sqrt, UM.sin = min, max, sqrt, sin
UM.round, UM.PP, UM.DeferMoverSync, UM.FONT_PATH = round, PP, DeferMoverSync, FONT_PATH
UM.LOCK_INNER, UM.LOCK_OUTER, UM.LOCK_TOP, UM.GRID_SPACING = LOCK_INNER, LOCK_OUTER, LOCK_TOP, GRID_SPACING
UM.SNAP_THRESH, UM.MOVER_ALPHA, UM.MOVER_HOVER, UM.MOVER_DRAG = SNAP_THRESH, MOVER_ALPHA, MOVER_HOVER, MOVER_DRAG
UM.GEAR_ROTATION, UM.BAR_LOOKUP, UM.ALL_BAR_ORDER, UM.GetVisibilityOnly = GEAR_ROTATION, BAR_LOOKUP, ALL_BAR_ORDER, GetVisibilityOnly
UM.registeredElements, UM.registeredOrder, UM.RebuildRegisteredOrder, UM.guidePool = registeredElements, registeredOrder, RebuildRegisteredOrder, guidePool
UM.movers, UM.lockAnimFrame, UM.pendingPositions, UM.snapshotPositions = movers, lockAnimFrame, pendingPositions, snapshotPositions
UM.snapshotAnchors, UM.snapshotSizes, UM.snapshotWidthMatch, UM.snapshotHeightMatch = snapshotAnchors, snapshotSizes, snapshotWidthMatch, snapshotHeightMatch
UM.snapshotGrowDirs, UM.GridBaseAlpha, UM.GridCenterAlpha, UM.GridHudAlpha = snapshotGrowDirs, GridBaseAlpha, GridCenterAlpha, GridHudAlpha
UM.GridLabelText, UM.CycleGridMode, UM._blizzOwnedOverlays, UM.SELECT_ELEMENT_ALPHA = GridLabelText, CycleGridMode, _blizzOwnedOverlays, SELECT_ELEMENT_ALPHA
UM.SELECT_ELEMENT_FADE = SELECT_ELEMENT_FADE
ns.unlockParts.Anchors(UM)
ns.unlockParts.Positions(UM)
ns.unlockParts.Tools(UM)
ns.unlockParts.Movers(UM)
ns.unlockParts.Session(UM)
local HideAllGuidesAndHighlight, DeselectMover = UM.HideAllGuidesAndHighlight, UM.DeselectMover
local SortMoverFrameLevels, HideBlizzOwnedOverlays = UM.SortMoverFrameLevels, UM.HideBlizzOwnedOverlays

-------------------------------------------------------------------------------
--  Close Unlock Mode -- routes through save/discard logic
-------------------------------------------------------------------------------
function ns.CloseUnlockMode(afterFn)
    if not UM.isUnlocked then
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
    function EllesmereUI:OpenUnlockMode()
        ns.OpenUnlockMode()
    end
end

-- Toggle helper + active flag alias used by options pages
if EllesmereUI and not EllesmereUI.ToggleUnlockMode then
    function EllesmereUI:ToggleUnlockMode()
        if UM.isUnlocked then
            ns.CloseUnlockMode()
        else
            ns.OpenUnlockMode()
        end
    end
    -- Options pages read _unlockActive (set by Open/Close above) since isUnlocked is local.
end

-- When the options panel tries to show while unlock mode is active,
-- close unlock mode first (with save flow), then re-show the panel after.
if EllesmereUI and EllesmereUI.RegisterOnShow then
    EllesmereUI:RegisterOnShow(function()
        if UM.isUnlocked then
            -- Hide the panel immediately -- it shouldn't show during unlock mode
            local panel = EllesmereUI._mainFrame
            if panel then panel:Hide() end
            -- Close unlock mode, then re-open the panel after
            ns.CloseUnlockMode(function()
                EllesmereUI:Toggle()
            end)
        end
    end)
end


-------------------------------------------------------------------------------
--  Combat auto-suspend / resume: entering combat hides unlock mode UI but
--  preserves all pending changes; leaving combat re-opens with the same state.
-------------------------------------------------------------------------------
local function SuspendForCombat()
    if not UM.isUnlocked then return end
    combatSuspended = true
    if EllesmereUI._HideFallbackGhosts then EllesmereUI._HideFallbackGhosts() end
    if EllesmereUI._HideOverrideGhosts then EllesmereUI._HideOverrideGhosts() end

    -- Restore objective tracker
    if UM.objTrackerWasVisible then
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
    UM.isUnlocked = false
    EllesmereUI._unlockActive = false
    EllesmereUI._unlockModeActive = false

    -- Override anchors re-engage for the fight (isUnlocked is false now);
    -- ResumeAfterCombat's sweep releases them again for editing.
    if EllesmereUI._ReapplyOverrideAnchors then EllesmereUI._ReapplyOverrideAnchors() end

    -- Re-check Dragon Riding's real visibility (it force-shows while
    -- _unlockActive is true so it can be edited off-mount; must run AFTER
    -- _unlockActive is cleared above, or UpdateVisibility() still hits that
    -- force-show branch and this call is a no-op).
    if _G._EDR_UpdateVisibility then pcall(_G._EDR_UpdateVisibility) end

    if UM.unlockFrame then
        UM.unlockFrame:SetScript("OnUpdate", nil)
        UM.unlockFrame:Hide()
    end
    if UM.logoFadeFrame then UM.logoFadeFrame:SetScript("OnUpdate", nil); UM.logoFadeFrame:Hide() end
    if UM.openAnimFrame then UM.openAnimFrame:Hide() end
    if lockAnimFrame then lockAnimFrame:Hide() end
    if UM.gridFrame then UM.gridFrame:Hide() end
    if UM.hudFrame then UM.hudFrame:Hide() end
    if UM.unlockTipFrame then UM.unlockTipFrame:SetScript("OnUpdate", nil); UM.unlockTipFrame:Hide() end
    DeselectMover()
    for _, m in pairs(movers) do m:Hide() end
    HideAllGuidesAndHighlight()
    HideBlizzOwnedOverlays()
    if UM.arrowKeyFrame then UM.arrowKeyFrame:Hide() end
    UM.selectedMover = nil
    UM.selectElementPicker = nil

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
    UM.isUnlocked = true
    EllesmereUI._unlockActive = true
    EllesmereUI._unlockModeActive = true
    if EllesmereUI._RefreshFallbackGhosts then EllesmereUI._RefreshFallbackGhosts() end
    -- Release override anchors back to baseline for editing (isUnlocked true).
    if EllesmereUI._ReapplyOverrideAnchors then EllesmereUI._ReapplyOverrideAnchors() end
    if EllesmereUI._RefreshOverrideGhosts then EllesmereUI._RefreshOverrideGhosts() end

    -- Re-check Dragon Riding's visibility now that _unlockActive is true again:
    -- SuspendForCombat's re-check hid the HUD for a dismounted player, and without
    -- this mirror call the force-show branch never re-evaluates on resume -- the
    -- element would stay invisible (and uneditable) until a mount/dismount re-runs UpdateVisibility.
    if _G._EDR_UpdateVisibility then pcall(_G._EDR_UpdateVisibility) end

    -- Re-hide objective tracker
    local objTracker = _G.ObjectiveTrackerFrame
    if objTracker and objTracker:IsShown() then
        UM.objTrackerWasVisible = true
        objTracker:SetAlpha(0)
        if objTracker.EnableMouse then pcall(objTracker.EnableMouse, objTracker, false) end
    end
    local qtBg = _G.EllesmereUIQTBackground
    if qtBg then qtBg:SetAlpha(0) end

    -- Notify beacon reminders to hide
    if _G._EABR_BeaconRefresh then pcall(_G._EABR_BeaconRefresh) end

    -- Re-show unlock UI
    if UM.arrowKeyFrame then UM.arrowKeyFrame:Show() end
    if UM.unlockFrame then UM.unlockFrame:Show(); UM.unlockFrame:SetAlpha(1) end
    if UM.gridFrame and UM.gridMode ~= "disabled" then UM.gridFrame:Show() end
    if UM.hudFrame then UM.hudFrame:Show() end

    -- Mirrors the OpenUnlockMode entry strip: provider enter hooks first (CDM's
    -- Additional Bar Offset may have re-applied to un-anchored bars during the
    -- combat-suspend window)...
    EllesmereUI.RunAnchorShiftEnters()
    -- ...then strip any temporary anchor-target shift (e.g. "Shift Elements if
    -- No Resource"/"...if No Bars") that may have re-applied while
    -- _unlockActive was false. _unlockActive is true again above, so the
    -- providers return 0 and this snaps shifted children back BEFORE the movers
    -- re-sync below capture their positions.
    if EllesmereUI.AnchorShiftWantsApply()
       and EllesmereUI.ReapplyAllUnlockAnchors then
        -- Force edge-preservation so custom-growth anchored bars snap to their fixed
        -- growth edge, not the center-offset position. Reset via pcall so it can't leak.
        EllesmereUI._reapplyForceEdgePreserve = true
        pcall(EllesmereUI.ReapplyAllUnlockAnchors)
        EllesmereUI._reapplyForceEdgePreserve = false
    end

    -- Re-sync all movers (Sync shows live ones and hides stale/hidden ones).
    for _, m in pairs(movers) do
        m:Sync()
        if m:IsShown() then
            m:SetAlpha(UM.darkOverlaysEnabled and 1 or MOVER_ALPHA)
        end
    end
    SortMoverFrameLevels()
    if UM.unlockFrame and UM.unlockFrame._anchorLineDriver then
        UM.unlockFrame._anchorLineDriver:Show()
    end
    if UM.unlockFrame and UM.unlockFrame._anchorLineFrame then
        UM.unlockFrame._anchorLineFrame:Show()
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
