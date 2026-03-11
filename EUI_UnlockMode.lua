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
    function EllesmereUI:RegisterUnlockElements(elements)
        for _, elem in ipairs(elements) do
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

-------------------------------------------------------------------------------
--  Constants
-------------------------------------------------------------------------------
local FONT_PATH   = (EllesmereUI and EllesmereUI.GetFontPath and EllesmereUI.GetFontPath("extras"))
    or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
local LOCK_INNER  = "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-inner-2.png"
local LOCK_OUTER  = "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-outer-2.png"
local LOCK_TOP    = "Interface\\AddOns\\EllesmereUI\\media\\eui-unlocked-top-2.png"
local GRID_SPACING = 32          -- pixels between grid lines
local SNAP_THRESH  = 6            -- px distance to trigger snap-to-element
local MOVER_ALPHA  = 0.55        -- resting alpha for mover overlays
local MOVER_HOVER  = 0.85        -- hover alpha
local MOVER_DRAG   = 0.95        -- dragging alpha
local TRANSITION_DUR = 0.35      -- seconds for the open/close fade-in
local GEAR_ROTATION  = math.pi / 4  -- 45° rotation for gear effect

-- Bar keys that can be moved (action bars + stance + micro + bag)
-- These are populated by EAB if it's loaded; otherwise empty.
local BAR_LOOKUP    = ns.BAR_LOOKUP or {}
local ALL_BAR_ORDER = ns.BAR_DROPDOWN_ORDER or {}
local VISIBILITY_ONLY = ns.VISIBILITY_ONLY or {}

local function GetVisibilityOnly()
    -- Read lazily so child addons have time to populate ns.VISIBILITY_ONLY
    return ns.VISIBILITY_ONLY or VISIBILITY_ONLY
end

-- Blizzard-owned frames we can move but cannot scale (SetScale causes taint)
local NO_SCALE_BARS = {
    MicroBar            = true,
    BagBar              = true,
    ExtraActionButton   = true,
    EncounterBar        = true,
}
local function IsNoScaleBar(barKey)
    return NO_SCALE_BARS[barKey] == true
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
local gridMode = "dimmed"  -- "disabled", "dimmed", "bright"
local snapEnabled = true   -- magnet/snap state (runtime) — must be before SnapPosition
local lockAnimFrame        -- lock assembly animation (close)
local openAnimFrame        -- lock animation frame (open)
local logoFadeFrame        -- the 2s logo+title fade-out timer frame
local pendingPositions = {}   -- { [barKey] = {point,relPoint,x,y} } — unsaved changes
local snapshotPositions = {}  -- original positions captured when unlock mode opens
local snapshotAnchors = {}    -- original anchor data captured when unlock mode opens
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
local flashlightEnabled = true  -- cursor flashlight toggle
local hoverBarEnabled = false   -- show-bar-on-hover toggle
local darkOverlaysEnabled = true  -- dark overlay backgrounds on movers
local coordsEnabled = false     -- show coordinates for all elements at all times
local unlockTipFrame           -- one-time "how to use" tip frame
local pendingAfterClose        -- callback to run after DoClose completes
local selectedMover            -- currently selected mover frame (for arrow key nudging)
local arrowKeyFrame            -- invisible frame that captures arrow key input
local selectElementPicker      -- mover currently in "Select Element" pick mode (nil = off)
local _overlayFadeFrame         -- tiny OnUpdate driver for select-element dimmer fade
local SELECT_ELEMENT_ALPHA = 0.50  -- overlay alpha during select-element pick mode
local SELECT_ELEMENT_FADE  = 0.50  -- seconds for the fade transition

-- Width Match / Height Match / Anchor To pick modes
-- Only one pick mode can be active at a time. The active picker mover is stored here.
local pickMode = nil           -- nil, "widthMatch", "heightMatch", "anchorTo"
local pickModeMover = nil      -- the mover that initiated the pick mode
local anchorDropdownFrame = nil -- lazy-created dropdown for anchor direction selection
local anchorDropdownCatcher = nil -- click-catcher behind anchor dropdown

-------------------------------------------------------------------------------
--  Anchor / Match DB helpers
--  Stored in EllesmereUIDB.unlockAnchors = { [childKey] = { target=key, side="LEFT"|"RIGHT"|"TOP"|"BOTTOM" } }
--  Width/height matches are applied immediately and saved to the element's
--  own settings — no persistent "match" relationship is stored.
-------------------------------------------------------------------------------
-- Forward declarations for functions defined later but referenced by anchor helpers
local GetBarFrame
local GetBarLabel

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

local function SetAnchorInfo(childKey, targetKey, side)
    local db = GetAnchorDB()
    if not db then return end
    db[childKey] = { target = targetKey, side = side }
end

local function ClearAnchorInfo(childKey)
    local db = GetAnchorDB()
    if not db then return end
    db[childKey] = nil
end

local function IsAnchored(barKey)
    local info = GetAnchorInfo(barKey)
    return info ~= nil
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
        -- Restore overlay text visibility
        if m._showOverlayText then m._showOverlayText() end
        if m._hidePickText then m._hidePickText() end
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
end

-- Red border flash animation for error feedback (e.g. trying to drag an anchored element)
local function FlashRedBorder(m)
    if not m or not m._brd then return end
    -- Create a dedicated red border overlay if not yet created
    if not m._redFlashBrd then
        m._redFlashBrd = EllesmereUI.MakeBorder(m, 1, 0.2, 0.2, 0)
        m._redFlashBrd._frame:SetFrameLevel(m:GetFrameLevel() + 4)
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

-- Apply an anchor relationship: position the child element relative to the target
-- side: "LEFT", "RIGHT", "TOP", "BOTTOM" — child is placed on that side of the target
local function ApplyAnchorPosition(childKey, targetKey, side, noMark)
    local childBar = GetBarFrame(childKey)
    local targetBar = GetBarFrame(targetKey)
    if not childBar or not targetBar then return end
    if InCombatLockdown() then return end

    local uiS = UIParent:GetEffectiveScale()
    local tS = targetBar:GetEffectiveScale()
    local cS = childBar:GetEffectiveScale()

    -- Get target bounds in UIParent space
    local tL = (targetBar:GetLeft() or 0) * tS / uiS
    local tR = (targetBar:GetRight() or 0) * tS / uiS
    local tT = (targetBar:GetTop() or 0) * tS / uiS
    local tB = (targetBar:GetBottom() or 0) * tS / uiS

    -- Get child size in UIParent space
    local cW = (childBar:GetWidth() or 50) * cS / uiS
    local cH = (childBar:GetHeight() or 50) * cS / uiS

    -- Compute child center in UIParent space based on anchor side
    local cx, cy
    local tCX = (tL + tR) / 2
    local tCY = (tT + tB) / 2
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
    end

    -- Convert to child's local space for TOPLEFT anchor
    local ratio = uiS / cS
    local barHW = (childBar:GetWidth() or 0) * 0.5
    local barHH = (childBar:GetHeight() or 0) * 0.5
    local barX = cx * ratio - barHW
    local barY = (cy - UIParent:GetHeight()) * ratio + barHH

    pcall(function()
        childBar:ClearAllPoints()
        childBar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", barX, barY)
    end)

    -- Update mover position to match
    local m = movers[childKey]
    if m then
        local mHW = m:GetWidth() / 2
        local mHH = m:GetHeight() / 2
        m:ClearAllPoints()
        m:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cx - mHW, cy + mHH - UIParent:GetHeight())
    end

    -- Store in pending positions
    pendingPositions[childKey] = {
        point = "TOPLEFT", relPoint = "TOPLEFT",
        x = barX, y = barY,
    }
    local prevScale = type(pendingPositions[childKey]) == "table" and pendingPositions[childKey].scale or nil
    if prevScale then pendingPositions[childKey].scale = prevScale end
    if not noMark then hasChanges = true end
end

-- Re-apply all saved anchor positions (called on open and after target moves)
local function ReapplyAllAnchors()
    local db = GetAnchorDB()
    if not db then return end
    for childKey, info in pairs(db) do
        if movers[childKey] and movers[info.target] then
            ApplyAnchorPosition(childKey, info.target, info.side, true)
        end
    end
end

-------------------------------------------------------------------------------
--  Saved position helpers  (action bars — legacy path)
-------------------------------------------------------------------------------
local function GetPositionDB()
    if not EAB or not EAB.db then return nil end
    if not EAB.db.profile.barPositions then
        EAB.db.profile.barPositions = {}
    end
    return EAB.db.profile.barPositions
end

local function SaveBarPosition(barKey, point, relPoint, x, y, scale)
    -- Registered element?
    local elem = registeredElements[barKey]
    if elem and elem.savePosition then
        elem.savePosition(barKey, point, relPoint, x, y, scale)
        return
    end
    -- Legacy action bar path
    local db = GetPositionDB()
    if not db then return end
    db[barKey] = { point = point, relPoint = relPoint, x = x, y = y, scale = scale }
end

local function LoadBarPosition(barKey)
    -- Registered element?
    local elem = registeredElements[barKey]
    if elem and elem.loadPosition then
        return elem.loadPosition(barKey)
    end
    -- Legacy action bar path
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
    -- Legacy action bar path
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

-------------------------------------------------------------------------------
--  Apply saved positions on login / reload
-------------------------------------------------------------------------------
local function ApplySavedPositions()
    if InCombatLockdown() then return end
    -- Action bars: apply from barPositions DB
    local db = GetPositionDB()
    if db then
        for barKey, pos in pairs(db) do
            local bar = GetBarFrame(barKey)
            if bar and pos.point then
                pcall(function()
                    bar:ClearAllPoints()
                    bar:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
                    if pos.scale and pos.scale ~= 1 then bar:SetScale(pos.scale) end
                end)
            end
        end
    end
    -- Registered elements: each addon applies its own positions
    RebuildRegisteredOrder()
    for _, key in ipairs(registeredOrder) do
        local elem = registeredElements[key]
        if elem and elem.applyPosition then
            pcall(elem.applyPosition, key)
        end
    end
end

-------------------------------------------------------------------------------
--  Edit Mode anchor guard — hooks ApplySystemAnchor on each Blizzard bar
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
                pcall(function()
                    self:ClearAllPoints()
                    self:SetPoint(db[barKey].point, UIParent, db[barKey].relPoint,
                                  db[barKey].x, db[barKey].y)
                    if db[barKey].scale and db[barKey].scale ~= 1 then self:SetScale(db[barKey].scale) end
                end)
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

        -- Vertical lines (centered on screen center, extending outward)
        local centerX = floor(w / 2)
        local centerY = floor(h / 2)
        -- Lines left of center
        local x = centerX - GRID_SPACING
        while x > 0 do
            idx = idx + 1
            local tex = self._lines[idx]
            if not tex then
                tex = self:CreateTexture(nil, "BACKGROUND", nil, -7)
                self._lines[idx] = tex
            end
            tex:SetColorTexture(ar, ag, ab, baseA)
            tex._baseAlpha = baseA
            tex._isWhite = false
            tex._isVert = true
            tex._pos = x
            tex:ClearAllPoints()
            tex:SetSize(1, h)
            tex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, 0)
            tex:Show()
            x = x - GRID_SPACING
        end
        -- Lines right of center
        x = centerX + GRID_SPACING
        while x < w do
            idx = idx + 1
            local tex = self._lines[idx]
            if not tex then
                tex = self:CreateTexture(nil, "BACKGROUND", nil, -7)
                self._lines[idx] = tex
            end
            tex:SetColorTexture(ar, ag, ab, baseA)
            tex._baseAlpha = baseA
            tex._isWhite = false
            tex._isVert = true
            tex._pos = x
            tex:ClearAllPoints()
            tex:SetSize(1, h)
            tex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, 0)
            tex:Show()
            x = x + GRID_SPACING
        end

        -- Horizontal lines (centered on screen center, extending outward)
        -- Note: y is distance from top
        local y = centerY - GRID_SPACING
        while y > 0 do
            idx = idx + 1
            local tex = self._lines[idx]
            if not tex then
                tex = self:CreateTexture(nil, "BACKGROUND", nil, -7)
                self._lines[idx] = tex
            end
            tex:SetColorTexture(ar, ag, ab, baseA)
            tex._baseAlpha = baseA
            tex._isWhite = false
            tex._isVert = false
            tex._pos = y
            tex:ClearAllPoints()
            tex:SetSize(w, 1)
            tex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -y)
            tex:Show()
            y = y - GRID_SPACING
        end
        y = centerY + GRID_SPACING
        while y < h do
            idx = idx + 1
            local tex = self._lines[idx]
            if not tex then
                tex = self:CreateTexture(nil, "BACKGROUND", nil, -7)
                self._lines[idx] = tex
            end
            tex:SetColorTexture(ar, ag, ab, baseA)
            tex._baseAlpha = baseA
            tex._isWhite = false
            tex._isVert = false
            tex._pos = y
            tex:ClearAllPoints()
            tex:SetSize(w, 1)
            tex:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -y)
            tex:Show()
            y = y + GRID_SPACING
        end

        -- Center crosshair: full-length accent lines at screen center
        for _, axis in ipairs({"V", "H"}) do
            idx = idx + 1
            local tex = self._lines[idx]
            if not tex then
                tex = self:CreateTexture(nil, "BACKGROUND", nil, -6)
                self._lines[idx] = tex
            end
            tex:SetColorTexture(ar, ag, ab, centerA)
            tex._baseAlpha = centerA
            tex._isWhite = false
            tex._isVert = (axis == "V")
            tex._pos = 0
            tex:ClearAllPoints()
            if axis == "V" then
                tex:SetSize(1, h)
                tex:SetPoint("TOP", UIParent, "TOP", 0, 0)
            else
                tex:SetSize(w, 1)
                tex:SetPoint("LEFT", UIParent, "LEFT", 0, 0)
            end
            tex:Show()
        end

        -- White crosshair pip at dead center (short lines forming a + shape)
        -- Always 50% alpha regardless of grid brightness mode
        local CROSS_ARM = 20  -- pixels per arm from center
        local CROSS_ALPHA = 0.5
        for _, axis in ipairs({"V", "H"}) do
            idx = idx + 1
            local tex = self._lines[idx]
            if not tex then
                tex = self:CreateTexture(nil, "BACKGROUND", nil, -5)
                self._lines[idx] = tex
            end
            tex:SetColorTexture(1, 1, 1, CROSS_ALPHA)
            tex._baseAlpha = CROSS_ALPHA
            tex._isWhite = true
            tex._isVert = (axis == "V")
            tex._pos = 0
            tex:ClearAllPoints()
            if axis == "V" then
                tex:SetSize(1, CROSS_ARM * 2)
                tex:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            else
                tex:SetSize(CROSS_ARM * 2, 1)
                tex:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
            tex:Show()
        end

        self._lineCount = idx
    end

    -- Cursor flashlight: radial glow around the cursor.
    -- Each nearby grid line is split into small segments, each segment's
    -- alpha is based on its TRUE 2D distance from the cursor, giving a
    -- smooth circular falloff like a real flashlight.
    local LIGHT_RADIUS = 220   -- px radius of the flashlight circle
    local LIGHT_BOOST  = 0.70  -- max alpha boost at cursor center
    local SEG_SIZE     = 8     -- px length of each mini-segment

    -- Pool of mini glow-segment textures
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

    -- Cache accent color; refreshed when grid is rebuilt
    local cachedAR, cachedAG, cachedAB = GetAccent()

    local origRebuild = gridFrame.Rebuild
    function gridFrame:Rebuild()
        origRebuild(self)
        cachedAR, cachedAG, cachedAB = GetAccent()
    end

    gridFrame:SetScript("OnUpdate", function(self, dt)
        -- Early-out: hide all glows and skip work when grid is not visible
        if not self:IsShown() then return end

        -- If flashlight is disabled, just hide all glows and reset base alphas
        if not flashlightEnabled then
            for j = 1, #self._glows do
                if self._glows[j] then self._glows[j]:Hide() end
            end
            return
        end

        local scale = UIParent:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx = cx / scale
        cy = cy / scale
        local cyFromTop = UIParent:GetHeight() - cy

        glowIdx = 0
        local R2 = LIGHT_RADIUS * LIGHT_RADIUS
        local lineCount = self._lineCount or #self._lines

        for i = 1, lineCount do
            local tex = self._lines[i]
            if tex and tex:IsShown() and tex._baseAlpha then
                if tex._isWhite then
                    tex:SetColorTexture(1, 1, 1, tex._baseAlpha)
                else
                    tex:SetColorTexture(cachedAR, cachedAG, cachedAB, tex._baseAlpha)
                end

                -- Perpendicular distance from cursor to this line
                local perpDist
                if tex._isVert then
                    perpDist = abs(tex._pos - cx)
                else
                    perpDist = abs(tex._pos - cyFromTop)
                end

                -- Skip lines too far away (no part can be within radius)
                if perpDist < LIGHT_RADIUS then
                    -- How far along the line we can reach within the radius
                    local halfSpan = sqrt(R2 - perpDist * perpDist)

                    if tex._isVert then
                        -- Vertical line: segments along Y axis
                        local startY = cy - halfSpan
                        local endY   = cy + halfSpan
                        local segY = startY
                        while segY < endY do
                            local segEnd = min(segY + SEG_SIZE, endY)
                            local midY = (segY + segEnd) / 2
                            -- 2D distance from cursor to segment midpoint
                            local dx = tex._pos - cx
                            local dy = midY - cy
                            local d2 = dx * dx + dy * dy
                            if d2 < R2 then
                                local t = 1 - sqrt(d2) / LIGHT_RADIUS
                                local alpha = LIGHT_BOOST * t * t
                                if alpha > 0.003 then
                                    glowIdx = glowIdx + 1
                                    local g = GetGlow(glowIdx)
                                    if tex._isWhite then
                                        g:SetColorTexture(1, 1, 1, alpha)
                                    else
                                        g:SetColorTexture(cachedAR, cachedAG, cachedAB, alpha)
                                    end
                                    g:ClearAllPoints()
                                    g:SetSize(1, segEnd - segY)
                                    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", tex._pos, max(0, segY))
                                    g:Show()
                                end
                            end
                            segY = segEnd
                        end
                    else
                        -- Horizontal line: segments along X axis
                        local startX = cx - halfSpan
                        local endX   = cx + halfSpan
                        local segX = startX
                        while segX < endX do
                            local segEnd = min(segX + SEG_SIZE, endX)
                            local midX = (segX + segEnd) / 2
                            local dx = midX - cx
                            local dy = tex._pos - cyFromTop
                            local d2 = dx * dx + dy * dy
                            if d2 < R2 then
                                local t = 1 - sqrt(d2) / LIGHT_RADIUS
                                local alpha = LIGHT_BOOST * t * t
                                if alpha > 0.003 then
                                    glowIdx = glowIdx + 1
                                    local g = GetGlow(glowIdx)
                                    if tex._isWhite then
                                        g:SetColorTexture(1, 1, 1, alpha)
                                    else
                                        g:SetColorTexture(cachedAR, cachedAG, cachedAB, alpha)
                                    end
                                    g:ClearAllPoints()
                                    g:SetSize(segEnd - segX, 1)
                                    g:SetPoint("TOPLEFT", UIParent, "TOPLEFT", max(0, segX), -tex._pos)
                                    g:Show()
                                end
                            end
                            segX = segEnd
                        end
                    end
                end
            end
        end

        -- Hide unused glow segments
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
    fs:SetFont(FONT_PATH, 9, "OUTLINE")
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

local function ClearSnapHighlight()
    if snapHighlightKey and movers[snapHighlightKey] then
        local m = movers[snapHighlightKey]
        if m._snapBrd then m._snapBrd:SetColor(1, 1, 1, 0) end
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
    end
    local m = movers[targetKey]
    if not m then
        ClearSnapHighlight()
        return
    end
    snapHighlightKey = targetKey
    snapHighlightElapsed = 0
    GetOrCreateSnapBorder(m)
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
    f._label:SetText(text)
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
    f._label:SetText(text)
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

local function ShowAlignmentGuides(dragKey)
    HideAllGuides()
    if not lastSnapInfo then return end

    local ar, ag, ab = GetAccent()
    local guideIdx = 0
    local screenW = UIParent:GetWidth()
    local screenH = UIParent:GetHeight()

    -- Edge/center snap guide lines
    if lastSnapInfo.snapXPos then
        guideIdx = guideIdx + 1
        local g = GetGuide(guideIdx)
        g:SetColorTexture(ar, ag, ab, 0.5)
        g:ClearAllPoints()
        g:SetSize(1, screenH)
        g:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", lastSnapInfo.snapXPos, 0)
        g:Show()
        activeGuides[guideIdx] = g
    end
    if lastSnapInfo.snapYPos then
        guideIdx = guideIdx + 1
        local g = GetGuide(guideIdx)
        g:SetColorTexture(ar, ag, ab, 0.5)
        g:ClearAllPoints()
        g:SetSize(screenW, 1)
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
        for key, mover in pairs(movers) do
            if key ~= dragKey and mover:IsShown() then
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
        for _, de in ipairs(dragXEdges) do
            for _, te in ipairs(targXEdges) do
                local dx = de - te
                local adx = abs(dx)
                if adx < bestDistX then
                    bestDistX = adx
                    bestDX = dx
                    snapXLinePos = te
                end
            end
        end

        -- Y-axis: dragged {top, center, bottom} vs target {top, center, bottom}
        local dragYEdges = { dT, cy, dB }
        local targYEdges = { oT, oCY, oB }
        for _, de in ipairs(dragYEdges) do
            for _, te in ipairs(targYEdges) do
                local dy = de - te
                local ady = abs(dy)
                if ady < bestDistY then
                    bestDistY = ady
                    bestDY = dy
                    snapYLinePos = te
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
    end
    if bestDistY < SNAP_THRESH and snapYLinePos then
        lastSnapInfo.snapYPos = snapYLinePos
    end

    return snapX, snapY
end

-------------------------------------------------------------------------------
--  Selection + Arrow Key Nudge System
-------------------------------------------------------------------------------
local function SelectMover(m)
    local ar, ag, ab = GetAccent()
    -- Deselect previous
    if selectedMover and selectedMover ~= m then
        selectedMover._selected = false
        selectedMover:SetFrameLevel(selectedMover._baseLevel)
        if not selectedMover._dragging and not selectedMover:IsMouseOver() then
            if not darkOverlaysEnabled then selectedMover:SetAlpha(MOVER_ALPHA) end
            selectedMover._brd:SetColor(ar, ag, ab, 0.6)
        end
        -- Hide action buttons on old selection
        if selectedMover._hideCogAfterDelay then selectedMover._hideCogAfterDelay() end
        -- Hide coordinates on old selection (keep if coords-always-on)
        if selectedMover._coordFS and not coordsEnabled then selectedMover._coordFS:Hide() end
    end
    selectedMover = m
    if m then
        m._selected = true
        m:SetFrameLevel(m._raisedLevel)
        if not darkOverlaysEnabled then m:SetAlpha(MOVER_HOVER) end
        m._brd:SetColor(1, 1, 1, 0.9)

        -- Raise settings widgets to match the raised mover level
        local settingsLevel = m._raisedLevel + 10
        if m._cogBtn then m._cogBtn:SetFrameLevel(settingsLevel) end
        if m._scaleBtn then m._scaleBtn:SetFrameLevel(settingsLevel) end
        if m._scaleTrack then m._scaleTrack:SetFrameLevel(settingsLevel) end
        if m._scaleValBox then m._scaleValBox:SetFrameLevel(settingsLevel) end

        -- Show coordinates on selection
        if m.UpdateCoordText then m:UpdateCoordText() end

        -- Show action buttons
        if m._showCogForHover then m._showCogForHover() end

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
        selectedMover:SetFrameLevel(selectedMover._baseLevel)
        if not selectedMover._dragging and not selectedMover:IsMouseOver() then
            if not darkOverlaysEnabled then selectedMover:SetAlpha(MOVER_ALPHA) end
            selectedMover._brd:SetColor(ar, ag, ab, 0.6)
        end
        -- Restore settings widgets to base level
        local baseSettingsLevel = selectedMover._baseLevel + 10
        if selectedMover._cogBtn then selectedMover._cogBtn:SetFrameLevel(baseSettingsLevel) end
        if selectedMover._scaleBtn then selectedMover._scaleBtn:SetFrameLevel(baseSettingsLevel) end
        if selectedMover._scaleTrack then selectedMover._scaleTrack:SetFrameLevel(baseSettingsLevel) end
        if selectedMover._scaleValBox then selectedMover._scaleValBox:SetFrameLevel(baseSettingsLevel) end
        -- Hide action buttons
        if selectedMover._hideCogAfterDelay then selectedMover._hideCogAfterDelay() end
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
            -- Show action row text (width/height match, anchor to)
            if m._showOverlayText then m._showOverlayText() end
            -- Lock frame alpha to 1 so bg/text stay at full opacity
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
local function NudgeMover(dx, dy)
    local m = selectedMover
    if not m or InCombatLockdown() then return end

    local mL, mT = m:GetLeft(), m:GetTop()
    if not mL or not mT then return end

    local newX = mL + dx
    local newY = mT + dy - UIParent:GetHeight()
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", UIParent, "TOPLEFT", newX, newY)

    -- Move the real bar
    local bar = GetBarFrame(m._barKey)
    if bar then
        local uiS = UIParent:GetEffectiveScale()
        local bS = bar:GetEffectiveScale()
        local ratio = uiS / bS
        pcall(function()
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", newX * ratio, newY * ratio)
        end)
        local _prevScale = type(pendingPositions[m._barKey]) == "table" and pendingPositions[m._barKey].scale or nil
        pendingPositions[m._barKey] = {
            point = "TOPLEFT", relPoint = "TOPLEFT",
            x = newX * ratio, y = newY * ratio,
        }
        if _prevScale then pendingPositions[m._barKey].scale = _prevScale end
        hasChanges = true
    end
    -- Update coordinate readout after nudge
    if m.UpdateCoordText then m:UpdateCoordText() end

    -- Anchor chain: reposition any elements anchored to this one
    local anchorDB = GetAnchorDB()
    if anchorDB then
        for childKey, info in pairs(anchorDB) do
            if info.target == m._barKey then
                ApplyAnchorPosition(childKey, info.target, info.side)
                if movers[childKey] then movers[childKey]:Sync() end
            end
        end
    end
end

-- Arrow key repeat state
local NUDGE_INITIAL_DELAY = 0.35   -- seconds before repeat starts
local NUDGE_INITIAL_RATE  = 0.08   -- seconds per repeat at start
local NUDGE_MIN_RATE      = 0.015  -- fastest repeat rate
local NUDGE_ACCEL_TIME    = 2.0    -- seconds to reach max speed

local arrowHeld = {}  -- { key = { elapsed, repeatAccum, repeating } }

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
        -- Shift+arrow = 100px jump (no repeat)
        if IsShiftKeyDown() then
            NudgeMover(dir[1] * 100, dir[2] * 100)
            return
        end
        if not arrowHeld[key] then
            -- First press: immediate single nudge
            NudgeMover(dir[1], dir[2])
            arrowHeld[key] = { elapsed = 0, repeatAccum = 0, repeating = false }
        end
    end)

    arrowKeyFrame:SetScript("OnKeyUp", function(self, key)
        if arrowHeld[key] then
            arrowHeld[key] = nil
            -- Re-enable propagation if no arrows held
            local anyHeld = false
            for _ in pairs(arrowHeld) do anyHeld = true; break end
            if not anyHeld then
                self:SetPropagateKeyboardInput(true)
            end
        end
    end)

    arrowKeyFrame:SetScript("OnUpdate", function(self, dt)
        if not selectedMover or not isUnlocked then
            wipe(arrowHeld)
            self:SetPropagateKeyboardInput(true)
            return
        end
        local ARROW_DIRS = { UP = {0,1}, DOWN = {0,-1}, LEFT = {-1,0}, RIGHT = {1,0} }
        for key, state in pairs(arrowHeld) do
            state.elapsed = state.elapsed + dt
            if not state.repeating then
                if state.elapsed >= NUDGE_INITIAL_DELAY then
                    state.repeating = true
                    state.repeatAccum = 0
                end
            else
                -- Accelerate: lerp from initial rate to min rate over ACCEL_TIME
                local holdTime = state.elapsed - NUDGE_INITIAL_DELAY
                local t = min(holdTime / NUDGE_ACCEL_TIME, 1)
                local rate = NUDGE_INITIAL_RATE + (NUDGE_MIN_RATE - NUDGE_INITIAL_RATE) * t
                state.repeatAccum = state.repeatAccum + dt
                while state.repeatAccum >= rate do
                    state.repeatAccum = state.repeatAccum - rate
                    local dir = ARROW_DIRS[key]
                    if dir then NudgeMover(dir[1], dir[2]) end
                end
            end
        end
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
    local barScale = s.barScale or 1

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

    return gridW * barScale, gridH * barScale
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
    -- Largest area first → lowest frame level
    table.sort(sorted, function(a, b) return a.area > b.area end)
    for i, entry in ipairs(sorted) do
        local lvl = BASE + i
        entry.mover._baseLevel = lvl
        entry.mover._raisedLevel = lvl + #sorted + 5
        entry.mover:SetFrameLevel(lvl)
    end
end

local function CreateMover(barKey)
    if movers[barKey] then return movers[barKey] end

    -- Skip elements that are intentionally hidden (e.g. alwaysHidden action bars)
    local elem = registeredElements[barKey]
    if elem and elem.isHidden and elem.isHidden() then return nil end
    if elem and elem.isAnchored and elem.isAnchored() then return nil end

    local bar = GetBarFrame(barKey)
    if not bar then return nil end

    local ar, ag, ab = GetAccent()
    local label = GetBarLabel(barKey)

    local mover = CreateFrame("Button", nil, unlockFrame)
    local MOVER_BASE_LEVEL = unlockFrame:GetFrameLevel() + 20
    local MOVER_RAISED_LEVEL = MOVER_BASE_LEVEL + 5
    mover:SetFrameLevel(MOVER_BASE_LEVEL)
    mover._baseLevel = MOVER_BASE_LEVEL
    mover._raisedLevel = MOVER_RAISED_LEVEL
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:RegisterForDrag("LeftButton")
    mover:EnableMouse(true)

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
    labelFrame:SetFrameLevel(mover:GetFrameLevel() + 3)
    local nameFS = labelFrame:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont(FONT_PATH, 10, "OUTLINE")
    nameFS:SetText(label)
    nameFS:SetTextColor(1, 1, 1, 0.75)
    nameFS:SetWordWrap(false)
    nameFS:SetNonSpaceWrap(false)
    nameFS:SetPoint("CENTER", mover, "CENTER")
    mover._label = nameFS
    if not darkOverlaysEnabled then nameFS:Hide() end

    -- Coordinate readout (shows during drag and selection, top-left of mover)
    local coordFS = labelFrame:CreateFontString(nil, "OVERLAY")
    coordFS:SetFont(FONT_PATH, 9, "OUTLINE")
    coordFS:SetTextColor(1, 1, 1, 0.7)
    coordFS:SetPoint("TOPLEFT", mover, "TOPLEFT", 3, -2)
    coordFS:Hide()
    mover._coordFS = coordFS

    ---------------------------------------------------------------------------
    --  Width Match | Height Match | Anchor To  (centered below the name)
    --  Also: "Anchored to: X" text and pick-mode instruction text
    ---------------------------------------------------------------------------
    -- Container for the action links (centered below name)
    local actionRow = labelFrame:CreateFontString(nil, "OVERLAY")
    actionRow:SetFont(FONT_PATH, 8, "OUTLINE")
    actionRow:SetTextColor(1, 1, 1, 0.45)
    actionRow:SetPoint("TOP", nameFS, "BOTTOM", 0, -2)
    actionRow:SetJustifyH("CENTER")
    actionRow:SetWordWrap(false)
    actionRow:Hide()

    -- We use three invisible click buttons overlaid on the text regions
    local WM_TEXT = "Width Match"
    local HM_TEXT = "Height Match"
    local AT_TEXT = "Anchor To"
    local SEP = "  |cff555555|  |r"

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

    -- Font strings inside each button for hover coloring
    local wmFS = wmBtn:CreateFontString(nil, "OVERLAY")
    wmFS:SetFont(FONT_PATH, 8, "OUTLINE")
    wmFS:SetTextColor(1, 1, 1, 0.45)
    wmFS:SetText(WM_TEXT)
    wmFS:SetPoint("CENTER")

    local sep1FS = labelFrame:CreateFontString(nil, "OVERLAY")
    sep1FS:SetFont(FONT_PATH, 8, "OUTLINE")
    sep1FS:SetTextColor(0.33, 0.33, 0.33, 1)
    sep1FS:SetText("|")
    sep1FS:Hide()

    local hmFS = hmBtn:CreateFontString(nil, "OVERLAY")
    hmFS:SetFont(FONT_PATH, 8, "OUTLINE")
    hmFS:SetTextColor(1, 1, 1, 0.45)
    hmFS:SetText(HM_TEXT)
    hmFS:SetPoint("CENTER")

    local sep2FS = labelFrame:CreateFontString(nil, "OVERLAY")
    sep2FS:SetFont(FONT_PATH, 8, "OUTLINE")
    sep2FS:SetTextColor(0.33, 0.33, 0.33, 1)
    sep2FS:SetText("|")
    sep2FS:Hide()

    local atFS = atBtn:CreateFontString(nil, "OVERLAY")
    atFS:SetFont(FONT_PATH, 8, "OUTLINE")
    atFS:SetTextColor(1, 1, 1, 0.45)
    atFS:SetText(AT_TEXT)
    atFS:SetPoint("CENTER")

    -- Layout: [Width Match] | [Height Match] | [Anchor To] centered below name
    local function LayoutActionRow()
        local wmW = wmFS:GetStringWidth() or 50
        local hmW = hmFS:GetStringWidth() or 55
        local atW = atFS:GetStringWidth() or 45
        local sepW = 10  -- approximate separator width
        local totalW = wmW + sepW + hmW + sepW + atW
        local startX = -totalW / 2

        wmBtn:SetSize(wmW + 4, 14)
        wmBtn:ClearAllPoints()
        wmBtn:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW / 2, -2)

        sep1FS:ClearAllPoints()
        sep1FS:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + sepW / 2, -2)

        hmBtn:SetSize(hmW + 4, 14)
        hmBtn:ClearAllPoints()
        hmBtn:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + sepW + hmW / 2, -2)

        sep2FS:ClearAllPoints()
        sep2FS:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + sepW + hmW + sepW / 2, -2)

        atBtn:SetSize(atW + 4, 14)
        atBtn:ClearAllPoints()
        atBtn:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + sepW + hmW + sepW + atW / 2, -2)
    end

    -- "Anchored to: X" text (shown when this element is anchored)
    local anchoredFS = labelFrame:CreateFontString(nil, "OVERLAY")
    anchoredFS:SetFont(FONT_PATH, 8, "OUTLINE")
    anchoredFS:SetTextColor(1, 0.7, 0.3, 0.7)
    anchoredFS:SetPoint("BOTTOM", mover, "BOTTOM", 0, 3)
    anchoredFS:SetJustifyH("CENTER")
    anchoredFS:SetWordWrap(false)
    anchoredFS:Hide()
    mover._anchoredFS = anchoredFS

    -- Pick mode instruction text (shown when in pick mode, replaces all other text)
    local pickFS = labelFrame:CreateFontString(nil, "OVERLAY")
    pickFS:SetFont(FONT_PATH, 10, "OUTLINE")
    pickFS:SetTextColor(1, 1, 1, 0.85)
    pickFS:SetPoint("CENTER", mover, "CENTER")
    pickFS:SetJustifyH("CENTER")
    pickFS:SetWordWrap(true)
    pickFS:Hide()
    mover._pickFS = pickFS

    -- Show/hide overlay text helpers
    local function ShowOverlayText()
        if darkOverlaysEnabled then
            nameFS:SetAlpha(1); nameFS:Show()
        end
        -- TEMPORARILY DISABLED: match/anchor UI not ready for release
        -- LayoutActionRow()
        -- wmBtn:Show(); hmBtn:Show(); atBtn:Show()
        -- sep1FS:Show(); sep2FS:Show()
        -- local anchorInfo = GetAnchorInfo(barKey)
        -- if anchorInfo then
        --     local targetLabel = GetBarLabel(anchorInfo.target) or anchorInfo.target
        --     anchoredFS:SetText("Anchored to: " .. targetLabel)
        --     anchoredFS:Show()
        --     wmBtn:Hide(); hmBtn:Hide(); atBtn:Hide()
        --     sep1FS:Hide(); sep2FS:Hide()
        -- else
        --     anchoredFS:Hide()
        -- end
        pickFS:Hide()
    end

    local function HideOverlayText()
        nameFS:Hide()
        wmBtn:Hide(); hmBtn:Hide(); atBtn:Hide()
        sep1FS:Hide(); sep2FS:Hide()
        anchoredFS:Hide()
    end

    local function ShowPickText(text)
        HideOverlayText()
        pickFS:SetText(text)
        pickFS:Show()
    end

    local function HidePickText()
        pickFS:Hide()
    end

    mover._showOverlayText = ShowOverlayText
    mover._hideOverlayText = HideOverlayText
    mover._showPickText = ShowPickText
    mover._hidePickText = HidePickText

    -- Refresh the anchored text (called after anchor changes)
    function mover:RefreshAnchoredText()
        -- TEMPORARILY DISABLED: match/anchor UI not ready for release
        -- local anchorInfo = GetAnchorInfo(self._barKey)
        -- if anchorInfo then
        --     local targetLabel = GetBarLabel(anchorInfo.target) or anchorInfo.target
        --     anchoredFS:SetText("Anchored to: " .. targetLabel)
        --     if darkOverlaysEnabled then anchoredFS:Show() end
        --     wmBtn:Hide(); hmBtn:Hide(); atBtn:Hide()
        --     sep1FS:Hide(); sep2FS:Hide()
        -- else
        --     anchoredFS:Hide()
        --     if darkOverlaysEnabled then
        --         LayoutActionRow()
        --         wmBtn:Show(); hmBtn:Show(); atBtn:Show()
        --         sep1FS:Show(); sep2FS:Show()
        --     end
        -- end
    end

    -- Hover effects for action buttons
    wmBtn:SetScript("OnEnter", function() wmFS:SetTextColor(1, 1, 1, 0.85) end)
    wmBtn:SetScript("OnLeave", function() wmFS:SetTextColor(1, 1, 1, 0.45) end)
    hmBtn:SetScript("OnEnter", function() hmFS:SetTextColor(1, 1, 1, 0.85) end)
    hmBtn:SetScript("OnLeave", function() hmFS:SetTextColor(1, 1, 1, 0.45) end)
    atBtn:SetScript("OnEnter", function() atFS:SetTextColor(1, 1, 1, 0.85) end)
    atBtn:SetScript("OnLeave", function() atFS:SetTextColor(1, 1, 1, 0.45) end)

    -- Click handlers for Width Match / Height Match / Anchor To
    wmBtn:SetScript("OnClick", function()
        CancelPickMode()
        pickMode = "widthMatch"
        pickModeMover = mover
        ShowPickText("Click any element\nto match its width")
        FadeOverlayForSelectElement(true)
    end)

    hmBtn:SetScript("OnClick", function()
        CancelPickMode()
        pickMode = "heightMatch"
        pickModeMover = mover
        ShowPickText("Click any element\nto match its height")
        FadeOverlayForSelectElement(true)
    end)

    atBtn:SetScript("OnClick", function()
        CancelPickMode()
        pickMode = "anchorTo"
        pickModeMover = mover
        ShowPickText("Click any element\nto anchor to it")
        FadeOverlayForSelectElement(true)
    end)

    -- Helper: update coordinate readout from mover's current position
    function mover:UpdateCoordText()
        local fs = self._coordFS
        if not fs then return end
        local l, r, t, b2 = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
        if not l or not t then fs:Hide(); return end
        local cx = round((l + r) / 2)
        local cy = round((t + b2) / 2)
        local screenW = UIParent:GetWidth()
        local screenH = UIParent:GetHeight()
        fs:SetText(format("%.0f, %.0f", cx - screenW * 0.5, cy - screenH * 0.5))
        fs:Show()
    end

    mover._barKey = barKey
    mover:SetAlpha(darkOverlaysEnabled and 1 or MOVER_ALPHA)

    -- Show action row text on creation if dark overlays are enabled
    if darkOverlaysEnabled and mover._showOverlayText then
        mover._showOverlayText()
    end

    -- Sync size/position to the real bar (or registered element)
    function mover:Sync()
        local bk = self._barKey
        local b = GetBarFrame(bk)
        local elem = registeredElements[bk]

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
            return
        end

        if not b then self:Hide(); return end
        -- Show mover even for hidden bars (mouseover/alwaysHidden) so user can reposition
        -- Only skip if the bar frame truly doesn't exist
        local s = b:GetEffectiveScale()
        local uiS = UIParent:GetEffectiveScale()
        local w, h
        -- For registered elements, prefer getSize (authoritative DB values)
        -- over frame dimensions which may be mid-animation or stale.
        -- Multiply by the frame's effective scale ratio to account for SetScale.
        if elem and elem.getSize then
            local gw, gh = elem.getSize(bk)
            local elemScale = s / uiS
            w = (gw or 50) * elemScale
            h = (gh or 50) * elemScale
        else
            w = (b:GetWidth() or 50) * s / uiS
            h = (b:GetHeight() or 50) * s / uiS
        end
        -- For action bars, compute visual size from button grid (accounts for
        -- shape overrides, padding, and per-button scale)
        local abW, abH = GetActionBarVisualSize(bk)
        if abW and abH then
            w, h = abW, abH
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
        -- Pixel-perfect: mover matches the actual element size exactly.
        -- Label text overflows for small elements — no width constraint.
        self:SetSize(w, h)
        if self._label then
            self._label:SetWidth(0)
            self._label:SetWordWrap(false)
        end

        -- Position: convert bar's screen position to UIParent-relative
        -- Center the mover on the bar's visual center for pixel-perfect alignment.
        local bL = b:GetLeft()
        local bT = b:GetTop()
        if bL and bT then
            if isTinyAnchor and elem then
                -- Tiny anchor (1×1): center the mover on the anchor's center
                local bR = b:GetRight() or bL
                local bB = b:GetBottom() or bT
                local cx = (bL + bR) * 0.5 * s / uiS
                local cy = (bT + bB) * 0.5 * s / uiS - UIParent:GetHeight() + centerYOff
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "TOPLEFT", cx, cy)
            else
                -- Center mover on the bar's visual center
                local bR = b:GetRight() or bL
                local bB = b:GetBottom() or bT
                local cx = (bL + bR) * 0.5 * s / uiS
                local cy = (bT + bB) * 0.5 * s / uiS - UIParent:GetHeight()
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "TOPLEFT", cx, cy)
            end
        else
            -- Bar has no position yet (not shown), place at center
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        self:Show()
    end

    -- Drag handlers: manual cursor-based positioning for live snap + live bar movement
    mover:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        -- Block dragging for anchored elements — flash red border instead
        if IsAnchored(self._barKey) then
            FlashRedBorder(self)
            return
        end
        SelectMover(self)
        self:SetAlpha(darkOverlaysEnabled and 1 or MOVER_DRAG)
        self._dragging = true
        self._shiftAxis = nil  -- nil = not locked, "X" or "Y" once determined
        -- Hide action buttons during drag
        if self._hideCogImmediate then self._hideCogImmediate() end

        -- Record offset from cursor to mover center at drag start
        local scale = UIParent:GetEffectiveScale()
        local curX, curY = GetCursorPosition()
        curX = curX / scale
        curY = curY / scale
        local cx = (self:GetLeft() + self:GetRight()) / 2
        local cy = (self:GetTop() + self:GetBottom()) / 2
        self._dragOffX = cx - curX
        self._dragOffY = cy - curY
        self._dragStartCX = cx
        self._dragStartCY = cy

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

            local halfW = round(s:GetWidth() / 2)
            local halfH = round(s:GetHeight() / 2)

            -- Apply snap
            local snapCX, snapCY = SnapPosition(s._barKey, rawCX, rawCY, halfW, halfH)

            -- Clamp to screen edges
            local screenW = UIParent:GetWidth()
            local screenH = UIParent:GetHeight()
            snapCX = max(halfW, min(screenW - halfW, snapCX))
            snapCY = max(halfH, min(screenH - halfH, snapCY))

            -- Position mover
            local finalX = snapCX - halfW
            local finalY = snapCY + halfH - UIParent:GetHeight()
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", UIParent, "TOPLEFT", finalX, finalY)

            -- Show live coordinates during drag (only on elements >= 20px tall)
            if s._coordFS and s:GetHeight() >= 20 then
                s._coordFS:SetText(format("%.0f, %.0f", round(snapCX - screenW * 0.5), round(snapCY - screenH * 0.5)))
                s._coordFS:Show()
            end

            -- Move the real bar live
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
                local barY = (snapCY - UIParent:GetHeight()) * ratio + barHH
                pcall(function()
                    bar:ClearAllPoints()
                    bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", barX, barY)
                end)
            end

            -- Anchor chain: live-reposition any elements anchored to this one
            local anchorDB = GetAnchorDB()
            if anchorDB then
                for childKey, info in pairs(anchorDB) do
                    if info.target == s._barKey then
                        ApplyAnchorPosition(childKey, info.target, info.side)
                        if movers[childKey] then movers[childKey]:Sync() end
                    end
                end
            end

            ShowAlignmentGuides(s._barKey)
        end)
    end)

    mover:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self._dragging = false
        self:SetAlpha(darkOverlaysEnabled and 1 or MOVER_HOVER)
        -- Update coords to final position (stays visible if selected or coords-always-on)
        if self._selected and self.UpdateCoordText then
            self:UpdateCoordText()
        elseif coordsEnabled and self.UpdateCoordText then
            self:UpdateCoordText()
        else
            self._coordFS:Hide()
        end
        HideAllGuidesAndHighlight()
        -- Re-show action buttons after drag
        if self._selected and self._showCogForHover then self._showCogForHover() end
        -- Re-anchor toolbar in case mover moved near/away from screen top
        if self._anchorToolbar then self._anchorToolbar() end

        -- Check if the mover actually moved (avoids false dirty flag from
        -- click-and-hold without movement)
        local cx = (self:GetLeft() + self:GetRight()) / 2
        local cy = (self:GetTop() + self:GetBottom()) / 2
        local startCX = self._dragStartCX or cx
        local startCY = self._dragStartCY or cy
        local moved = (abs(cx - startCX) > 0.5) or (abs(cy - startCY) > 0.5)
        if not moved then return end

        -- Store position in pending table (NOT saved until user clicks Save & Exit)

        local bar = GetBarFrame(self._barKey)
        if not InCombatLockdown() then
            local uiS = UIParent:GetEffectiveScale()
            if bar then
                local bS = bar:GetEffectiveScale()
                local ratio = uiS / bS
                local barHW = (bar:GetWidth() or 0) * 0.5
                local barHH = (bar:GetHeight() or 0) * 0.5
                local barX = cx * ratio - barHW
                local barY = (cy - UIParent:GetHeight()) * ratio + barHH
                local _prevScale = type(pendingPositions[self._barKey]) == "table" and pendingPositions[self._barKey].scale or nil
                pendingPositions[self._barKey] = {
                    point = "TOPLEFT", relPoint = "TOPLEFT",
                    x = barX, y = barY,
                }
                if _prevScale then pendingPositions[self._barKey].scale = _prevScale end
            else
                -- No live frame (e.g. unit frame not spawned) — store in UIParent coords
                local halfW = self:GetWidth() / 2
                local halfH = self:GetHeight() / 2
                local _prevScale = type(pendingPositions[self._barKey]) == "table" and pendingPositions[self._barKey].scale or nil
                pendingPositions[self._barKey] = {
                    point = "TOPLEFT", relPoint = "TOPLEFT",
                    x = cx - halfW, y = cy + halfH - UIParent:GetHeight(),
                }
                if _prevScale then pendingPositions[self._barKey].scale = _prevScale end
            end
            hasChanges = true
        end

        -- Anchor chain: reposition any elements anchored to this one
        local anchorDB = GetAnchorDB()
        if anchorDB then
            for childKey, info in pairs(anchorDB) do
                if info.target == self._barKey then
                    ApplyAnchorPosition(childKey, info.target, info.side)
                    if movers[childKey] then movers[childKey]:Sync() end
                end
            end
        end
    end)

    -- Hover effects
    mover:SetScript("OnEnter", function(self)
        if not self._dragging then
            self:SetFrameLevel(self._raisedLevel)
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
            if self._showCogForHover then self._showCogForHover() end
        end
    end)
    mover:SetScript("OnLeave", function(self)
        if not self._dragging and not self._selected then
            self:SetFrameLevel(self._baseLevel)
            -- Restore normal colors (even if we were showing white highlight)
            if not darkOverlaysEnabled then self:SetAlpha(MOVER_ALPHA) end
            self._brd:SetColor(ar, ag, ab, 0.6)
            if self._hideCogAfterDelay then self._hideCogAfterDelay() end
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
                    -- Get target width and apply to source
                    local targetElem = registeredElements[targetKey]
                    local targetBar = GetBarFrame(targetKey)
                    local targetW
                    if targetElem and targetElem.getSize then
                        targetW = targetElem.getSize(targetKey)
                    elseif targetBar then
                        targetW = targetBar:GetWidth()
                    end
                    if targetW and targetW > 0 then
                        local sourceElem = registeredElements[sourceKey]
                        if sourceElem and sourceElem.setWidth then
                            sourceElem.setWidth(sourceKey, targetW)
                            hasChanges = true
                        end
                    end
                    CancelPickMode()
                    -- Re-sync movers after size change
                    C_Timer.After(0.15, function()
                        if movers[sourceKey] then movers[sourceKey]:Sync() end
                    end)
                    return

                elseif pickMode == "heightMatch" then
                    -- Get target height and apply to source
                    local targetElem = registeredElements[targetKey]
                    local targetBar = GetBarFrame(targetKey)
                    local _, targetH
                    if targetElem and targetElem.getSize then
                        _, targetH = targetElem.getSize(targetKey)
                    elseif targetBar then
                        targetH = targetBar:GetHeight()
                    end
                    if targetH and targetH > 0 then
                        local sourceElem = registeredElements[sourceKey]
                        if sourceElem and sourceElem.setHeight then
                            sourceElem.setHeight(sourceKey, targetH)
                            hasChanges = true
                        end
                    end
                    CancelPickMode()
                    -- Re-sync movers after size change
                    C_Timer.After(0.15, function()
                        if movers[sourceKey] then movers[sourceKey]:Sync() end
                    end)
                    return

                elseif pickMode == "anchorTo" then
                    -- Show anchor direction dropdown near the clicked target
                    local pm = pickModeMover
                    local pmKey = pm._barKey

                    -- Circular anchor detection: walk the target's anchor chain
                    -- to make sure it doesn't eventually point back to pmKey
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
                        return
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
                    anchorDropdownFrame:SetPoint("TOPLEFT", self, "TOPRIGHT", 4, 0)

                    local ddBg = anchorDropdownFrame:CreateTexture(nil, "BACKGROUND")
                    ddBg:SetAllPoints()
                    ddBg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
                    EllesmereUI.MakeBorder(anchorDropdownFrame, 1, 1, 1, 0.20)

                    local ddY = -4
                    -- Title
                    local titleFS = anchorDropdownFrame:CreateFontString(nil, "OVERLAY")
                    titleFS:SetFont(FONT_PATH, 10, "OUTLINE")
                    titleFS:SetTextColor(1, 1, 1, 0.40)
                    titleFS:SetJustifyH("LEFT")
                    titleFS:SetPoint("TOPLEFT", anchorDropdownFrame, "TOPLEFT", 10, ddY - 4)
                    titleFS:SetText("Anchor Direction")
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
                        lbl:SetFont(FONT_PATH, 11, "OUTLINE")
                        lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                        lbl:SetJustifyH("LEFT")
                        lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                        lbl:SetText("Anchor to " .. sideName)
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
                            -- Set anchor relationship
                            SetAnchorInfo(pmKey, targetKey, sideVal)
                            -- Apply the anchor position
                            ApplyAnchorPosition(pmKey, targetKey, sideVal)
                            hasChanges = true
                            -- Refresh the anchored mover's text
                            if movers[pmKey] and movers[pmKey].RefreshAnchoredText then
                                movers[pmKey]:RefreshAnchoredText()
                            end
                            -- Re-sync mover
                            C_Timer.After(0.15, function()
                                if movers[pmKey] then movers[pmKey]:Sync() end
                            end)
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
                        rLbl:SetFont(FONT_PATH, 11, "OUTLINE")
                        rLbl:SetTextColor(0.9, 0.3, 0.3, 0.9)
                        rLbl:SetJustifyH("LEFT")
                        rLbl:SetPoint("LEFT", removeItem, "LEFT", 10, 0)
                        rLbl:SetText("Remove Anchor")
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
            -- Right-click: open cog settings menu (same as cogwheel)
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
    local cogBtn = CreateFrame("Button", nil, unlockFrame)
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
        end)
        cogBtn:SetScript("OnLeave", function(self)
            self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
            self._brd:SetColor(1, 1, 1, 0.20)
            self._icon:SetAlpha(0.7)
        end)
    end
    cogBtn:Hide()

    -- Scale button (opens a scale slider popup)
    local RESIZE_ICON = ICON_PATH .. "eui-resize-5.png"
    local scaleBtn = CreateFrame("Button", nil, unlockFrame)
    scaleBtn:SetFrameLevel(mover:GetFrameLevel() + 10)
    scaleBtn:RegisterForClicks("AnyUp")
    scaleBtn:EnableMouse(true)
    scaleBtn:SetSize(ACT_SZ, ACT_SZ)
    do
        local bg = scaleBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
        scaleBtn._bg = bg
        local brd = EllesmereUI.MakeBorder(scaleBtn, 1, 1, 1, 0.20)
        scaleBtn._brd = brd
        local icon = scaleBtn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("CENTER")
        icon:SetTexture(RESIZE_ICON)
        icon:SetAlpha(0.7)
        scaleBtn._icon = icon
        scaleBtn:SetScript("OnEnter", function(self)
            self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
            self._brd:SetColor(1, 1, 1, 0.30)
            self._icon:SetAlpha(1)
        end)
        scaleBtn:SetScript("OnLeave", function(self)
            self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
            self._brd:SetColor(1, 1, 1, 0.20)
            self._icon:SetAlpha(0.7)
        end)
    end
    scaleBtn:Hide()

    -- Fade helpers for cog + scale buttons
    local btnFadeTarget = 0
    local btnFadeAlpha = 0
    local BTN_FADE_DUR = 0.25
    local cogHideTimer = nil

    local function BtnFadeTo(targetAlpha)
        btnFadeTarget = targetAlpha
        local btns = mover._actionBtns or { cogBtn, scaleBtn }
        if targetAlpha > 0 then
            for _, btn in ipairs(btns) do btn:Show() end
        end
        cogBtn:SetScript("OnUpdate", function(self, dt)
            if btnFadeAlpha < btnFadeTarget then
                btnFadeAlpha = math.min(btnFadeAlpha + dt / BTN_FADE_DUR, btnFadeTarget)
            elseif btnFadeAlpha > btnFadeTarget then
                btnFadeAlpha = math.max(btnFadeAlpha - dt / BTN_FADE_DUR, btnFadeTarget)
            end
            for _, btn in ipairs(mover._actionBtns or { cogBtn, scaleBtn }) do
                btn:SetAlpha(btnFadeAlpha)
            end
            -- Also fade inline scale elements if open
            if mover._scaleOpen then
                if mover._scaleTrack then mover._scaleTrack:SetAlpha(btnFadeAlpha) end
                if mover._scaleValBox then mover._scaleValBox:SetAlpha(btnFadeAlpha) end
            end
            if btnFadeAlpha == btnFadeTarget then
                self:SetScript("OnUpdate", nil)
                if btnFadeAlpha == 0 then
                    for _, btn in ipairs(mover._actionBtns or { cogBtn, scaleBtn }) do
                        btn:Hide()
                    end
                    -- Also hide inline scale elements
                    if mover._closeScaleInline then mover._closeScaleInline() end
                end
            end
        end)
    end

    local function ShowCogForHover()
        if cogHideTimer then cogHideTimer:Cancel(); cogHideTimer = nil end
        BtnFadeTo(1)
    end

    local function HideCogAfterDelay()
        if cogHideTimer then cogHideTimer:Cancel() end
        cogHideTimer = C_Timer.NewTimer(0.25, function()
            cogHideTimer = nil
            if mover._selected then return end
            -- Don't hide if scale slider is open
            if mover._scaleOpen then return end
            -- Check mouseover on all toolbar elements
            for _, btn in ipairs(mover._actionBtns or { cogBtn, scaleBtn }) do
                if btn:IsShown() and btn:IsMouseOver() then return end
            end
            -- Also check inline scale elements if open
            if mover._scaleOpen then
                if mover._scaleTrack and mover._scaleTrack:IsShown() and mover._scaleTrack:IsMouseOver() then return end
                if mover._scaleValBox and mover._scaleValBox:IsShown() and mover._scaleValBox:IsMouseOver() then return end
            end
            -- Don't hide if a menu is open (cog menu, snap menu)
            if mover._menuOpen then return end
            BtnFadeTo(0)
        end)
    end

    local function HideCogImmediate()
        if cogHideTimer then cogHideTimer:Cancel(); cogHideTimer = nil end
        btnFadeAlpha = 0
        btnFadeTarget = 0
        for _, btn in ipairs(mover._actionBtns or { cogBtn, scaleBtn }) do
            btn:SetAlpha(0)
            btn:Hide()
        end
        if mover._closeScaleInline then mover._closeScaleInline() end
        cogBtn:SetScript("OnUpdate", nil)
    end

    mover._showCogForHover = ShowCogForHover
    mover._hideCogAfterDelay = HideCogAfterDelay
    mover._hideCogImmediate = HideCogImmediate

    -- Re-set cogBtn hover scripts now that fade helpers are in scope
    cogBtn:SetScript("OnEnter", function(self)
        self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
        self._brd:SetColor(1, 1, 1, 0.30)
        self._icon:SetAlpha(1)
        if cogHideTimer then cogHideTimer:Cancel(); cogHideTimer = nil end
    end)
    cogBtn:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
        self._brd:SetColor(1, 1, 1, 0.20)
        self._icon:SetAlpha(0.7)
        if not mover._selected and not mover:IsMouseOver() and not scaleBtn:IsMouseOver() then
            HideCogAfterDelay()
        end
    end)

    -- scaleBtn hover scripts
    scaleBtn:SetScript("OnEnter", function(self)
        self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.98)
        self._brd:SetColor(1, 1, 1, 0.30)
        self._icon:SetAlpha(1)
        if cogHideTimer then cogHideTimer:Cancel(); cogHideTimer = nil end
    end)
    scaleBtn:SetScript("OnLeave", function(self)
        self._bg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
        self._brd:SetColor(1, 1, 1, 0.20)
        self._icon:SetAlpha(0.7)
        if not mover._selected and not mover:IsMouseOver() and not cogBtn:IsMouseOver() then
            HideCogAfterDelay()
        end
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
    snapDDLbl:SetFont(FONT_PATH, 12, "OUTLINE")
    snapDDLbl:SetTextColor(1, 1, 1, 0.50)
    snapDDLbl:SetJustifyH("LEFT")
    snapDDLbl:SetWordWrap(false)
    snapDDLbl:SetMaxLines(1)
    snapDDLbl:SetPoint("LEFT", snapDD, "LEFT", 8, 0)
    snapDDLbl:SetText("Snap to: Auto")
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
            snapDDLbl:SetText("Snap to: None")
        elseif tgt == "_select_" then
            snapDDLbl:SetText("Snap to: Select Element")
        elseif tgt then
            local lbl = GetBarLabel(tgt)
            snapDDLbl:SetText("Snap to: " .. (lbl or tgt))
        else
            snapDDLbl:SetText("Snap to: All Elements")
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
        titleLbl:SetFont(FONT_PATH, 10, "OUTLINE")
        titleLbl:SetTextColor(1, 1, 1, 0.40)
        titleLbl:SetJustifyH("LEFT")
        titleLbl:SetPoint("TOPLEFT", snapMenu, "TOPLEFT", 10, yOff - 4)
        titleLbl:SetText("Snap Target")
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
            lbl:SetFont(FONT_PATH, 11, "OUTLINE")
            lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            lbl:SetJustifyH("LEFT")
            lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
            lbl:SetText(text)
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
            rgLbl:SetFont(FONT_PATH, 11, "OUTLINE")
            rgLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            rgLbl:SetJustifyH("LEFT")
            rgLbl:SetPoint("LEFT", rgItem, "LEFT", 10, 0)
            rgLbl:SetText(gName)
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
                    sLbl:SetFont(FONT_PATH, 11, "OUTLINE")
                    sLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    sLbl:SetJustifyH("LEFT")
                    sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                    sLbl:SetText(eLbl)
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
                    if self:IsShown() and not self:IsMouseOver() and not rgItem:IsMouseOver() then
                        self:Hide()
                    end
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
                local rs = regSubMenus[gName]
                if rs and rs:IsShown() and not rs:IsMouseOver() and not rgItem:IsMouseOver() then
                    rs:Hide()
                end
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
        if IsNearScreenTop() then
            cogBtn:SetPoint("TOPRIGHT", mover, "BOTTOMRIGHT", 0, -2)
        else
            cogBtn:SetPoint("BOTTOMRIGHT", mover, "TOPRIGHT", 0, 2)
        end
        -- Only position scaleBtn for bars that support scaling
        if not IsNoScaleBar(barKey) then
            scaleBtn:ClearAllPoints()
            scaleBtn:SetPoint("RIGHT", cogBtn, "LEFT", -ACT_PAD, 0)
        end
    end
    mover._anchorToolbar = AnchorToolbarToMover
    AnchorToolbarToMover()

    -- Hide orientation button for visibility-only bars or bars without layout support
    local isVisOnly = (GetVisibilityOnly()[barKey]) or not (BAR_LOOKUP and BAR_LOOKUP[barKey])

    mover._cogBtn = cogBtn
    mover._actionBtns = { cogBtn, scaleBtn }  -- track + valBox added after creation below

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

        -- Select Element: enter pick mode to choose a specific snap target by clicking
        local selElemItem = CreateFrame("Button", nil, cogMenu)
        selElemItem:SetHeight(ITEM_H)
        selElemItem:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
        selElemItem:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
        selElemItem:SetFrameLevel(cogMenu:GetFrameLevel() + 2)
        selElemItem:RegisterForClicks("AnyUp")
        local selElemHl = selElemItem:CreateTexture(nil, "ARTWORK")
        selElemHl:SetAllPoints()
        local isSelElem = (mover._snapTarget == "_select_")
        selElemHl:SetColorTexture(1, 1, 1, isSelElem and 0.04 or 0)
        local selElemLbl = selElemItem:CreateFontString(nil, "OVERLAY")
        selElemLbl:SetFont(FONT_PATH, 11, "OUTLINE")
        selElemLbl:SetTextColor(isSelElem and 1 or 0.75, isSelElem and 1 or 0.75, isSelElem and 1 or 0.75, 0.9)
        selElemLbl:SetJustifyH("LEFT")
        selElemLbl:SetPoint("LEFT", selElemItem, "LEFT", 10, 0)
        selElemLbl:SetText("Select Element")
        selElemItem:SetScript("OnEnter", function()
            selElemHl:SetColorTexture(1, 1, 1, 0.08)
            selElemLbl:SetTextColor(1, 1, 1, 1)
        end)
        selElemItem:SetScript("OnLeave", function()
            selElemHl:SetColorTexture(1, 1, 1, isSelElem and 0.04 or 0)
            selElemLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
        end)
        selElemItem:SetScript("OnClick", function()
            mover._preSelectTarget = mover._snapTarget
            mover._snapTarget = "_select_"
            selectElementPicker = mover
            FadeOverlayForSelectElement(true)
            UpdateSnapLabel()
            CloseCogMenu()
        end)
        yOff = yOff - ITEM_H

        -- Snap to: sub-menu item (with arrow)
        local snapItem = CreateFrame("Button", nil, cogMenu)
        snapItem:SetHeight(ITEM_H)
        snapItem:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
        snapItem:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
        snapItem:SetFrameLevel(cogMenu:GetFrameLevel() + 2)
        snapItem:RegisterForClicks("AnyUp")
        local snapHl = snapItem:CreateTexture(nil, "ARTWORK")
        snapHl:SetAllPoints()
        snapHl:SetColorTexture(1, 1, 1, 0)
        local snapLbl = snapItem:CreateFontString(nil, "OVERLAY")
        snapLbl:SetFont(FONT_PATH, 11, "OUTLINE")
        snapLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
        snapLbl:SetJustifyH("LEFT")
        snapLbl:SetPoint("LEFT", snapItem, "LEFT", 10, 0)
        snapLbl:SetWordWrap(false)
        snapLbl:SetMaxLines(1)
        -- Show current snap target in the label
        local curTgt = mover._snapTarget
        local snapText = "All Elements"
        if curTgt == "_disable_" then snapText = "None"
        elseif curTgt == "_select_" then snapText = "Select Element"
        elseif curTgt then snapText = GetBarLabel(curTgt) or curTgt end
        snapLbl:SetText("Snap Target: " .. snapText)
        local snapArrow = snapItem:CreateTexture(nil, "ARTWORK")
        snapArrow:SetSize(10, 10)
        snapArrow:SetPoint("RIGHT", snapItem, "RIGHT", -8, 0)
        snapArrow:SetTexture(ARROW_RIGHT_ICON)
        snapArrow:SetAlpha(0.7)
        snapLbl:SetPoint("RIGHT", snapArrow, "LEFT", -5, 0)
        -- Gray out if snap is globally disabled
        if not snapEnabled then
            snapLbl:SetTextColor(0.75, 0.75, 0.75, 0.35)
            snapArrow:SetAlpha(0.35)
        end
        local cogSnapMenu  -- sub-menu for snap targets inside cog menu
        local function ShowCogSnapSub()
            if not snapEnabled then return end
            if cogSnapMenu then
                for _, child in ipairs({cogSnapMenu:GetChildren()}) do child:Hide(); child:SetParent(nil) end
                for _, tex in ipairs({cogSnapMenu:GetRegions()}) do if tex.Hide then tex:Hide() end end
            end
            cogSnapMenu = cogSnapMenu or CreateFrame("Frame", nil, cogMenu)
            cogSnapMenu:SetFrameStrata("FULLSCREEN_DIALOG")
            cogSnapMenu:SetFrameLevel(260)
            cogSnapMenu:SetClampedToScreen(true)
            cogSnapMenu:SetSize(DD_W, 10)
            cogSnapMenu:SetPoint("TOPLEFT", snapItem, "TOPRIGHT", 2, 0)
            local sBg = cogSnapMenu:CreateTexture(nil, "BACKGROUND")
            sBg:SetAllPoints()
            sBg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
            EllesmereUI.MakeBorder(cogSnapMenu, 1, 1, 1, 0.20)
            local sYOff = -4
            local sITEM_H = 24
            local function MakeSnapItem(text, value, isSel)
                local si = CreateFrame("Button", nil, cogSnapMenu)
                si:SetHeight(sITEM_H)
                si:SetPoint("TOPLEFT", cogSnapMenu, "TOPLEFT", 1, sYOff)
                si:SetPoint("TOPRIGHT", cogSnapMenu, "TOPRIGHT", -1, sYOff)
                si:SetFrameLevel(cogSnapMenu:GetFrameLevel() + 2)
                si:RegisterForClicks("AnyUp")
                local sHl = si:CreateTexture(nil, "ARTWORK")
                sHl:SetAllPoints()
                sHl:SetColorTexture(1, 1, 1, isSel and 0.04 or 0)
                local sLbl = si:CreateFontString(nil, "OVERLAY")
                sLbl:SetFont(FONT_PATH, 11, "OUTLINE")
                sLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                sLbl:SetJustifyH("LEFT")
                sLbl:SetPoint("LEFT", si, "LEFT", 10, 0)
                sLbl:SetText(text)
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
                    if value == "_select_" then
                        mover._preSelectTarget = mover._snapTarget
                    end
                    mover._snapTarget = value
                    if value == "_select_" then
                        selectElementPicker = mover
                        FadeOverlayForSelectElement(true)
                    end
                    UpdateSnapLabel()
                    CloseCogMenu()
                end)
                sYOff = sYOff - sITEM_H
            end
            MakeSnapItem("All Elements", nil, not curTgt)
            MakeSnapItem("None", "_disable_", curTgt == "_disable_")
            -- Divider
            local sDiv = cogSnapMenu:CreateTexture(nil, "ARTWORK")
            sDiv:SetHeight(1)
            sDiv:SetColorTexture(1, 1, 1, 0.10)
            sDiv:SetPoint("TOPLEFT", cogSnapMenu, "TOPLEFT", 1, sYOff - 4)
            sDiv:SetPoint("TOPRIGHT", cogSnapMenu, "TOPRIGHT", -1, sYOff - 4)
            sYOff = sYOff - 9
            -- Registered element groups (Unit Frames, Action Bars, Resource Bars, etc.)
            RebuildRegisteredOrder()
            local cogRegGroups = {}
            local cogRegGroupOrder = {}
            for _, rk in ipairs(registeredOrder) do
                if rk ~= barKey and movers[rk] and movers[rk]:IsShown() then
                    local elem = registeredElements[rk]
                    local gName = elem.group or "Other"
                    if not cogRegGroups[gName] then
                        cogRegGroups[gName] = {}
                        cogRegGroupOrder[#cogRegGroupOrder + 1] = gName
                    end
                    cogRegGroups[gName][#cogRegGroups[gName] + 1] = { key = rk, label = elem.label or rk }
                end
            end
            -- Add visibility-only bars (MicroBar, BagBar) to "Other" group
            for _, bk in ipairs(ALL_BAR_ORDER) do
                if GetVisibilityOnly()[bk] and bk ~= barKey and movers[bk] and movers[bk]:IsShown() then
                    if not cogRegGroups["Other"] then
                        cogRegGroups["Other"] = {}
                        cogRegGroupOrder[#cogRegGroupOrder + 1] = "Other"
                    end
                    cogRegGroups["Other"][#cogRegGroups["Other"] + 1] = { key = bk, label = GetBarLabel(bk) }
                end
            end
            local cogRegSubMenus = {}
            for _, gName in ipairs(cogRegGroupOrder) do
                local gElems = cogRegGroups[gName]
                local crItem = CreateFrame("Button", nil, cogSnapMenu)
                crItem:SetHeight(sITEM_H)
                crItem:SetPoint("TOPLEFT", cogSnapMenu, "TOPLEFT", 1, sYOff)
                crItem:SetPoint("TOPRIGHT", cogSnapMenu, "TOPRIGHT", -1, sYOff)
                crItem:SetFrameLevel(cogSnapMenu:GetFrameLevel() + 2)
                crItem:RegisterForClicks("AnyUp")
                local crHl = crItem:CreateTexture(nil, "ARTWORK")
                crHl:SetAllPoints()
                crHl:SetColorTexture(1, 1, 1, 0)
                local crLbl = crItem:CreateFontString(nil, "OVERLAY")
                crLbl:SetFont(FONT_PATH, 11, "OUTLINE")
                crLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                crLbl:SetJustifyH("LEFT")
                crLbl:SetPoint("LEFT", crItem, "LEFT", 10, 0)
                crLbl:SetText(gName)
                local crArrow = crItem:CreateTexture(nil, "ARTWORK")
                crArrow:SetSize(10, 10)
                crArrow:SetPoint("RIGHT", crItem, "RIGHT", -8, 0)
                crArrow:SetTexture(ARROW_RIGHT_ICON)
                crArrow:SetAlpha(0.7)
                sYOff = sYOff - sITEM_H

                local crSub
                local function ShowCogRegSub()
                    -- Close any other open leaf sub-menus first
                    for otherName, crs in pairs(cogRegSubMenus) do
                        if otherName ~= gName and crs and crs:IsShown() then crs:Hide() end
                    end
                    if crSub then
                        for _, child in ipairs({crSub:GetChildren()}) do child:Hide(); child:SetParent(nil) end
                        for _, tex in ipairs({crSub:GetRegions()}) do if tex.Hide then tex:Hide() end end
                    end
                    crSub = crSub or CreateFrame("Frame", nil, cogMenu)
                    crSub:SetFrameStrata("FULLSCREEN_DIALOG")
                    crSub:SetFrameLevel(270)
                    crSub:SetClampedToScreen(true)
                    crSub:SetSize(DD_W, 10)
                    crSub:SetPoint("TOPLEFT", crItem, "TOPRIGHT", 2, 0)
                    local crsBg = crSub:CreateTexture(nil, "BACKGROUND")
                    crsBg:SetAllPoints()
                    crsBg:SetColorTexture(0.075, 0.113, 0.141, 0.95)
                    EllesmereUI.MakeBorder(crSub, 1, 1, 1, 0.20)
                    local crsYOff = -4
                    for _, eInfo in ipairs(gElems) do
                        local ek, eLbl = eInfo.key, eInfo.label
                        local isSel = (curTgt == ek)
                        local ci = CreateFrame("Button", nil, crSub)
                        ci:SetHeight(sITEM_H)
                        ci:SetPoint("TOPLEFT", crSub, "TOPLEFT", 1, crsYOff)
                        ci:SetPoint("TOPRIGHT", crSub, "TOPRIGHT", -1, crsYOff)
                        ci:SetFrameLevel(crSub:GetFrameLevel() + 2)
                        ci:RegisterForClicks("AnyUp")
                        local cHl = ci:CreateTexture(nil, "ARTWORK")
                        cHl:SetAllPoints()
                        cHl:SetColorTexture(1, 1, 1, isSel and 0.04 or 0)
                        local cLbl = ci:CreateFontString(nil, "OVERLAY")
                        cLbl:SetFont(FONT_PATH, 11, "OUTLINE")
                        cLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                        cLbl:SetJustifyH("LEFT")
                        cLbl:SetPoint("LEFT", ci, "LEFT", 10, 0)
                        cLbl:SetText(eLbl)
                        if isSel then cLbl:SetTextColor(1, 1, 1, 1) end
                        ci:SetScript("OnEnter", function()
                            cHl:SetColorTexture(1, 1, 1, 0.08)
                            cLbl:SetTextColor(1, 1, 1, 1)
                        end)
                        ci:SetScript("OnLeave", function()
                            cHl:SetColorTexture(1, 1, 1, isSel and 0.04 or 0)
                            cLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                        end)
                        ci:SetScript("OnClick", function()
                            mover._snapTarget = ek
                            UpdateSnapLabel()
                            CloseCogMenu()
                        end)
                        crsYOff = crsYOff - sITEM_H
                    end
                    crSub:SetHeight(-crsYOff + 4)
                    -- Width: fit the widest label
                    local crsMaxW = DD_W
                    for _, eInfo in ipairs(gElems) do
                        local tw = (EllesmereUI.MeasureText and EllesmereUI.MeasureText(eInfo.label, FONT_PATH, 11)) or 0
                        local needed = 10 + tw + 10 + 2
                        if needed > crsMaxW then crsMaxW = needed end
                    end
                    crSub:SetWidth(crsMaxW)
                    crSub:EnableMouse(true)
                    crSub:SetScript("OnLeave", function(self)
                        if self:IsShown() and not self:IsMouseOver() and not crItem:IsMouseOver() then
                            self:Hide()
                        end
                    end)
                    crSub:Show()
                    cogRegSubMenus[gName] = crSub
                end

                crItem:SetScript("OnEnter", function()
                    crHl:SetColorTexture(1, 1, 1, 0.08)
                    crLbl:SetTextColor(1, 1, 1, 1)
                    crArrow:SetAlpha(0.9)
                    ShowCogRegSub()
                end)
                crItem:SetScript("OnLeave", function()
                    crHl:SetColorTexture(1, 1, 1, 0)
                    crLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    crArrow:SetAlpha(0.5)
                    local crs = cogRegSubMenus[gName]
                    if crs and crs:IsShown() and not crs:IsMouseOver() and not crItem:IsMouseOver() then
                        crs:Hide()
                    end
                end)
            end
            cogSnapMenu:SetHeight(-sYOff + 4)
            cogSnapMenu:EnableMouse(true)
            cogSnapMenu:SetScript("OnLeave", function(self)
                if self:IsShown() and not self:IsMouseOver() and not snapItem:IsMouseOver() then
                    for _, crs in pairs(cogRegSubMenus) do
                        if crs and crs:IsShown() and crs:IsMouseOver() then return end
                    end
                    for _, crs in pairs(cogRegSubMenus) do
                        if crs then crs:Hide() end
                    end
                    self:Hide()
                end
            end)
            cogSnapMenu:Show()
        end
        snapItem:SetScript("OnEnter", function()
            if not snapEnabled then
                EllesmereUI.ShowWidgetTooltip(snapItem, "Snap Elements is disabled")
                return
            end
            snapHl:SetColorTexture(1, 1, 1, 0.08)
            snapLbl:SetTextColor(1, 1, 1, 1)
            snapArrow:SetAlpha(0.9)
            ShowCogSnapSub()
        end)
        snapItem:SetScript("OnLeave", function()
            EllesmereUI.HideWidgetTooltip()
            snapHl:SetColorTexture(1, 1, 1, 0)
            if not snapEnabled then return end
            snapLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            snapArrow:SetAlpha(0.5)
            C_Timer.After(0.05, function()
                if cogSnapMenu and cogSnapMenu:IsShown() and not cogSnapMenu:IsMouseOver() and not snapItem:IsMouseOver() then
                    cogSnapMenu:Hide()
                end
            end)
        end)
        yOff = yOff - ITEM_H

        -- Divider
        local div = cogMenu:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetColorTexture(1, 1, 1, 0.10)
        div:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff - 4)
        div:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff - 4)
        yOff = yOff - 9

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
            lbl:SetFont(FONT_PATH, 11, "OUTLINE")
            lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            lbl:SetJustifyH("LEFT")
            lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
            lbl:SetText(text)
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

        -- Reset Position
        MakeActionItem("Reset Position", function()
            if InCombatLockdown() then return end
            local bk = mover._barKey
            pendingPositions[bk] = "RESET"
            hasChanges = true
            ClearBarPosition(bk)
            -- Clear any anchor relationship on this element
            if IsAnchored(bk) then
                ClearAnchorInfo(bk)
                if mover.RefreshAnchoredText then mover:RefreshAnchoredText() end
            end
            local snap = snapshotPositions[bk]
            local b = GetBarFrame(bk)
            if b then
                -- For action bars, reset scale via EAB profile
                local elem = registeredElements[bk]
                if EAB and EAB.db and EAB.db.profile.bars[bk] then
                    EAB.db.profile.bars[bk].barScale = 1
                    if not InCombatLockdown() then
                        EAB:ApplyScaleForBar(bk)
                    end
                end
                if snap then
                    pcall(function()
                        b:ClearAllPoints()
                        b:SetPoint(snap.point, UIParent, snap.relPoint, snap.x, snap.y)
                        if elem then b:SetScale(1) end
                    end)
                else
                    if elem then pcall(function() b:SetScale(1) end) end
                    if b.UpdateGridLayout then pcall(b.UpdateGridLayout, b) end
                end
            end
            C_Timer.After(0.15, function()
                if movers[bk] then movers[bk]:Sync() end
            end)
        end)

        -- Center on Screen
        MakeActionItem("Center on Screen", function()
            if InCombatLockdown() then return end
            local bk = mover._barKey
            local screenCX = UIParent:GetWidth() * 0.5
            local mW = mover:GetWidth()
            local mH = mover:GetHeight()
            local mT = mover:GetTop()
            local mB = mover:GetBottom()
            if not mT or not mB then return end
            -- Center mover horizontally, keep vertical position
            local newX = screenCX - mW / 2
            local newY = mT - UIParent:GetHeight()
            mover:ClearAllPoints()
            mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", newX, newY)
            local b = GetBarFrame(bk)
            if b then
                -- Use same formula as drag-stop: cx/cy = mover center
                local cx = screenCX
                local cy = (mT + mB) / 2
                local uiS = UIParent:GetEffectiveScale()
                local bS = b:GetEffectiveScale()
                local ratio = uiS / bS
                local barHW = (b:GetWidth() or 0) * 0.5
                local barHH = (b:GetHeight() or 0) * 0.5
                local barX = cx * ratio - barHW
                local barY = (cy - UIParent:GetHeight()) * ratio + barHH
                pcall(function()
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", barX, barY)
                end)
                local _prevScale = type(pendingPositions[bk]) == "table" and pendingPositions[bk].scale or nil
                pendingPositions[bk] = {
                    point = "TOPLEFT", relPoint = "TOPLEFT",
                    x = barX, y = barY,
                }
                if _prevScale then pendingPositions[bk].scale = _prevScale end
                hasChanges = true
            end
            -- Update coordinate readout after centering
            if mover.UpdateCoordText then mover:UpdateCoordText() end
        end)

        -- Toggle Orientation (hidden for vis-only bars)
        if not isVisOnly then
            MakeActionItem("Toggle Orientation", function()
                if InCombatLockdown() then return end
                if not EAB then return end
                EAB:ToggleOrientationForBar(mover._barKey)
                hasChanges = true
                C_Timer.After(0.15, function()
                    if movers[mover._barKey] then movers[mover._barKey]:Sync() end
                end)
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
                DeselectMover()
            end)
        end
        cogClickCatcher:Show()
    end

    cogBtn:SetScript("OnClick", function()
        if cogMenu and cogMenu:IsShown() then
            CloseCogMenu()
        else
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
            mover._menuOpen = true
            BuildCogMenu()
            ShowCogClickCatcher()
        end
    end

    ---------------------------------------------------------------------------
    --  Inline scale slider + input (no popup, sits in the toolbar row)
    --  Layout: [track] [input "100"] [resize icon] [cog icon]
    ---------------------------------------------------------------------------
    local scaleTrackFrame, scaleValBox
    local scaleCurrentVal = 100
    do
        local ar, ag, ab = GetAccent()
        local TRACK_W = 120
        local TRACK_H = 3
        local THUMB_SZ = 12
        local INPUT_W = 40
        local MIN_VAL = 50
        local MAX_VAL = 200
        local STEP = 1

        -- Input box: same style as resize/cog buttons
        local valBox = CreateFrame("EditBox", nil, unlockFrame)
        valBox:SetSize(INPUT_W, ACT_SZ)
        valBox:SetFrameLevel(mover:GetFrameLevel() + 10)
        valBox:SetAutoFocus(false)
        valBox:SetNumeric(false)
        valBox:SetMaxLetters(4)
        valBox:SetJustifyH("CENTER")
        valBox:SetFont(FONT_PATH, 12, "")
        valBox:SetTextColor(0.776, 0.776, 0.776, 1)
        do
            local bg = valBox:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(0.075, 0.113, 0.141, 0.9)
            EllesmereUI.MakeBorder(valBox, 1, 1, 1, 0.20)
        end
        valBox:SetPoint("RIGHT", scaleBtn, "LEFT", -ACT_PAD, 0)
        valBox:Hide()
        scaleValBox = valBox

        -- Track frame: bare slider, no background
        local trackFrame = CreateFrame("Frame", nil, unlockFrame)
        trackFrame:SetSize(TRACK_W, ACT_SZ)
        trackFrame:SetFrameLevel(mover:GetFrameLevel() + 10)
        trackFrame:SetPoint("RIGHT", valBox, "LEFT", -ACT_PAD - 5, 0)
        trackFrame:Hide()
        scaleTrackFrame = trackFrame

        -- Track line: accent-colored at low alpha
        local trackDark = trackFrame:CreateTexture(nil, "BACKGROUND")
        trackDark:SetSize(TRACK_W, TRACK_H)
        trackDark:SetPoint("CENTER", trackFrame, "CENTER", 0, 0)
        trackDark:SetColorTexture(0.776, 0.776, 0.776, 0.5)
        if trackDark.SetSnapToPixelGrid then trackDark:SetSnapToPixelGrid(false); trackDark:SetTexelSnappingBias(0) end

        -- Accent-colored fill
        local trackFill = trackFrame:CreateTexture(nil, "BORDER")
        trackFill:SetHeight(TRACK_H)
        trackFill:SetPoint("LEFT", trackDark, "LEFT", 0, 0)
        trackFill:SetColorTexture(ar, ag, ab, 0.7)
        if trackFill.SetSnapToPixelGrid then trackFill:SetSnapToPixelGrid(false); trackFill:SetTexelSnappingBias(0) end
        trackFrame._fill = trackFill

        -- Accent-colored thumb
        local thumb = CreateFrame("Button", nil, trackFrame)
        thumb:SetSize(THUMB_SZ, THUMB_SZ)
        thumb:SetFrameLevel(trackFrame:GetFrameLevel() + 2)
        thumb:EnableMouse(true)
        thumb:SetPoint("CENTER", trackFill, "RIGHT", 0, 0)
        local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
        thumbTex:SetAllPoints()
        thumbTex:SetColorTexture(ar, ag, ab, 1)
        if thumbTex.SetSnapToPixelGrid then thumbTex:SetSnapToPixelGrid(false); thumbTex:SetTexelSnappingBias(0) end
        trackFrame._thumb = thumb

        -- Update visual helper
        local function UpdateScaleVisual(val)
            val = max(MIN_VAL, min(MAX_VAL, floor(val + 0.5)))
            local ratio = (val - MIN_VAL) / (MAX_VAL - MIN_VAL)
            trackFill:SetWidth(max(1, floor(TRACK_W * ratio + 0.5)))
            if not valBox:HasFocus() then valBox:SetText(tostring(val)) end
        end
        trackFrame._updateVisual = UpdateScaleVisual

        -- Apply scale to bar
        local function ApplyScale(val)
            val = max(MIN_VAL, min(MAX_VAL, floor(val + 0.5)))
            scaleCurrentVal = val
            UpdateScaleVisual(val)
            local bk = mover._barKey
            local sc = val / 100
            local b = GetBarFrame(bk)
            if b then
                local elem = registeredElements[bk]
                local isActionBar = EAB and EAB.db and EAB.db.profile.bars[bk]
                if isActionBar then
                    local uiS = UIParent:GetEffectiveScale()
                    local oldS = b:GetEffectiveScale()
                    local oldCX = (b:GetLeft() + b:GetRight()) * 0.5 * oldS / uiS
                    local oldCY = (b:GetTop() + b:GetBottom()) * 0.5 * oldS / uiS
                    EAB.db.profile.bars[bk].barScale = sc
                    if not InCombatLockdown() then
                        EAB:ApplyScaleForBar(bk)
                    end
                    local newS = b:GetEffectiveScale()
                    pcall(function()
                        b:ClearAllPoints()
                        -- Re-anchor as TOPLEFT for consistency with drag/save
                        local tlX = oldCX * uiS / newS - b:GetWidth() * 0.5
                        local tlY = (oldCY - UIParent:GetHeight()) * uiS / newS + b:GetHeight() * 0.5
                        b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", tlX, tlY)
                    end)
                elseif elem and b:GetLeft() and b:GetTop() then
                    local uiS = UIParent:GetEffectiveScale()
                    local oldS = b:GetEffectiveScale()
                    local oldCX = (b:GetLeft() + b:GetRight()) * 0.5 * oldS / uiS
                    local oldCY = (b:GetTop() + b:GetBottom()) * 0.5 * oldS / uiS
                    pcall(function() b:SetScale(sc) end)
                    local newS = b:GetEffectiveScale()
                    pcall(function()
                        b:ClearAllPoints()
                        -- Re-anchor as TOPLEFT for consistency with drag/save
                        local tlX = oldCX * uiS / newS - b:GetWidth() * 0.5
                        local tlY = (oldCY - UIParent:GetHeight()) * uiS / newS + b:GetHeight() * 0.5
                        b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", tlX, tlY)
                    end)
                else
                    pcall(function() b:SetScale(sc) end)
                end
            end
            pendingPositions[bk] = pendingPositions[bk] or {}
            if type(pendingPositions[bk]) == "table" then
                pendingPositions[bk].scale = sc
                -- For action bars, update the stored position to match
                -- the bar's new anchor after re-centering, so CommitPositions
                -- saves the correct coordinates for the new scale.
                if EAB and EAB.db and EAB.db.profile.bars[bk] and b then
                    local pt, _, rpt, px, py = b:GetPoint(1)
                    if pt then
                        pendingPositions[bk].point = pt
                        pendingPositions[bk].relPoint = rpt
                        pendingPositions[bk].x = px
                        pendingPositions[bk].y = py
                    end
                elseif registeredElements[bk] and b then
                    -- Same for registered elements — after center-preserving
                    -- reposition, store the new anchor so CommitPositions
                    -- doesn't fall back to stale snapshot coordinates.
                    local pt, _, rpt, px, py = b:GetPoint(1)
                    if pt then
                        pendingPositions[bk].point = pt
                        pendingPositions[bk].relPoint = rpt
                        pendingPositions[bk].x = px
                        pendingPositions[bk].y = py
                    end
                end
            end
            hasChanges = true
            C_Timer.After(0.05, function()
                if movers[bk] then movers[bk]:Sync() end
            end)
        end
        trackFrame._applyScale = ApplyScale

        -- Drag logic
        local isDragging = false
        local rawDragVal = 100

        local function SliderOnUpdate(self)
            if not IsMouseButtonDown("LeftButton") then
                isDragging = false
                self:SetScript("OnUpdate", nil)
                ApplyScale(floor(rawDragVal + 0.5))
                return
            end
            local cursorX = select(1, GetCursorPosition()) / trackFrame:GetEffectiveScale()
            local left = trackDark:GetLeft()
            if not left then return end
            local frac = max(0, min(1, (cursorX - left) / TRACK_W))
            rawDragVal = MIN_VAL + frac * (MAX_VAL - MIN_VAL)
            local snapped = max(MIN_VAL, min(MAX_VAL, floor(rawDragVal / STEP + 0.5) * STEP))
            UpdateScaleVisual(snapped)
            ApplyScale(snapped)
        end

        local function BeginDrag()
            isDragging = true
            local cursorX = select(1, GetCursorPosition()) / trackFrame:GetEffectiveScale()
            local left = trackDark:GetLeft()
            if left then
                local frac = max(0, min(1, (cursorX - left) / TRACK_W))
                rawDragVal = MIN_VAL + frac * (MAX_VAL - MIN_VAL)
                local snapped = max(MIN_VAL, min(MAX_VAL, floor(rawDragVal / STEP + 0.5) * STEP))
                ApplyScale(snapped)
            end
            trackFrame:SetScript("OnUpdate", SliderOnUpdate)
        end

        local function EndDrag()
            isDragging = false
            trackFrame:SetScript("OnUpdate", nil)
            ApplyScale(floor(rawDragVal + 0.5))
        end

        trackFrame:EnableMouse(true)
        trackFrame:RegisterForDrag("LeftButton")
        trackFrame:SetScript("OnDragStart", function() end)
        trackFrame:SetScript("OnDragStop", function() end)
        trackFrame:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then BeginDrag() end end)
        trackFrame:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then EndDrag() end end)

        thumb:RegisterForDrag("LeftButton")
        thumb:SetScript("OnDragStart", function() end)
        thumb:SetScript("OnDragStop", function() end)
        thumb:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then BeginDrag() end end)
        thumb:SetScript("OnMouseUp", function(_, button) if button == "LeftButton" then EndDrag() end end)

        -- Input box enter/escape
        valBox:SetScript("OnEnterPressed", function(self)
            local raw = tonumber(self:GetText())
            if raw then
                raw = max(MIN_VAL, min(MAX_VAL, floor(raw + 0.5)))
                ApplyScale(raw)
            else
                self:SetText(tostring(scaleCurrentVal))
            end
            self:ClearFocus()
        end)
        valBox:SetScript("OnEscapePressed", function(self)
            self:SetText(tostring(scaleCurrentVal))
            self:ClearFocus()
        end)

        -- Mouse wheel on track and input
        trackFrame:EnableMouseWheel(true)
        trackFrame:SetScript("OnMouseWheel", function(_, delta)
            ApplyScale(scaleCurrentVal + delta * 5)
        end)
        valBox:EnableMouseWheel(true)
        valBox:SetScript("OnMouseWheel", function(_, delta)
            ApplyScale(scaleCurrentVal + delta * 5)
        end)

        -- RefreshScaleInline: read current scale and update visuals
        local function RefreshScaleInline()
            local bk = mover._barKey
            local curScale = 100
            local b = GetBarFrame(bk)
            local elem = registeredElements[bk]
            -- Action bars: read from EAB profile
            if not elem and EAB and EAB.db and EAB.db.profile.bars[bk] then
                curScale = floor((EAB.db.profile.bars[bk].barScale or 1) * 100 + 0.5)
            elseif elem and elem.getScale then
                curScale = floor((elem.getScale(bk) or 1) * 100 + 0.5)
            elseif b then
                curScale = floor((b:GetScale() or 1) * 100 + 0.5)
            end
            local pend = pendingPositions[bk]
            if type(pend) == "table" and pend.scale then
                curScale = floor(pend.scale * 100 + 0.5)
            end
            scaleCurrentVal = curScale
            UpdateScaleVisual(curScale)
            valBox:SetText(tostring(curScale))
        end
        mover._refreshScaleInline = RefreshScaleInline
    end -- do block

    -- scaleBtn toggles the inline slider + input visibility
    local function CloseScaleInline()
        scaleTrackFrame:Hide()
        scaleValBox:Hide()
        mover._scaleOpen = false
        -- Re-attach toolbar to mover chain (respecting flip)
        AnchorToolbarToMover()
    end

    scaleBtn:SetScript("OnClick", function()
        if mover._scaleOpen then
            CloseScaleInline()
        else
            -- Close any other mover's open scale inline first
            for _, m in pairs(movers) do
                if m ~= mover and m._scaleOpen and m._closeScaleInline then
                    m._closeScaleInline()
                end
            end
            if mover._refreshScaleInline then mover._refreshScaleInline() end
            -- Detach toolbar from mover: pin cog + resize to fixed screen position
            -- so the slider doesn't move when the element rescales.
            local uiS = UIParent:GetEffectiveScale()
            local cogS = cogBtn:GetEffectiveScale()
            local cogR = cogBtn:GetRight()
            local cogT = cogBtn:GetTop()
            if cogR and cogT then
                local fixR = cogR * cogS / uiS
                local fixT = (cogT * cogS / uiS) - UIParent:GetHeight()
                cogBtn:ClearAllPoints()
                cogBtn:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", fixR, fixT)
            end
            scaleTrackFrame:SetAlpha(btnFadeAlpha)
            scaleValBox:SetAlpha(btnFadeAlpha)
            scaleTrackFrame:Show()
            scaleValBox:Show()
            mover._scaleOpen = true
        end
    end)
    scaleBtn:SetScript("OnHide", CloseScaleInline)
    mover._closeScaleInline = CloseScaleInline
    mover._scaleBtn = scaleBtn
    mover._scaleTrack = scaleTrackFrame
    mover._scaleValBox = scaleValBox

    -- Hide scale button entirely for visibility-only Blizzard bars (MicroBar, BagBar)
    -- because SetScale on protected frames causes taint.
    -- Hide scale button for Blizzard-owned frames that cannot be scaled without taint.
    if IsNoScaleBar(barKey) then
        scaleBtn:SetScript("OnHide", nil)
        scaleBtn:SetScript("OnClick", nil)
        scaleBtn:ClearAllPoints()
        scaleBtn:Hide()
        mover._actionBtns = { cogBtn }
    else
        mover._actionBtns = { scaleBtn, cogBtn }
    end

    movers[barKey] = mover
    return mover
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
        -- Migrate old boolean unlockGridVisible to new unlockGridMode
        if EllesmereUIDB.unlockGridVisible ~= nil and EllesmereUIDB.unlockGridMode == nil then
            if EllesmereUIDB.unlockGridVisible then
                EllesmereUIDB.unlockGridMode = "dimmed"
            else
                EllesmereUIDB.unlockGridMode = "disabled"
            end
            EllesmereUIDB.unlockGridVisible = nil
        end
        if EllesmereUIDB.unlockGridMode == nil then EllesmereUIDB.unlockGridMode = "dimmed" end
        if EllesmereUIDB.unlockSnapEnabled == nil then EllesmereUIDB.unlockSnapEnabled = true end
    end
    gridMode = (EllesmereUIDB and EllesmereUIDB.unlockGridMode) or "dimmed"
    snapEnabled = (EllesmereUIDB and EllesmereUIDB.unlockSnapEnabled ~= false) or true

    -- Pixel-perfect scale: 1 frame unit = 1 physical screen pixel
    local physW = (GetPhysicalScreenSize())
    local uiScale = GetScreenWidth() / physW

    hudFrame = CreateFrame("Frame", nil, parent)
    hudFrame:SetFrameLevel(parent:GetFrameLevel() + 55)
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
    gridLabel:SetFont(FONT_PATH, 10, "OUTLINE")
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
    darkOverlayLabel:SetFont(FONT_PATH, 10, "OUTLINE")
    darkOverlayLabel:SetJustifyH("RIGHT")
    darkOverlayLabel:SetPoint("RIGHT", darkOverlayTex, "LEFT", -5, 0)
    darkOverlayLabel:SetTextColor(1, 1, 1, darkOverlaysEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    darkOverlayLabel:SetText(darkOverlaysEnabled and "Dark Overlays\nEnabled" or "Dark Overlays\nDisabled")
    darkOverlayBtn._label = darkOverlayLabel

    local darkOverlayLabelW = darkOverlayLabel:GetStringWidth() or 80
    darkOverlayBtn:SetSize(darkOverlayLabelW + 5 + iconSz, max(iconSz, 24))

    SetupToggleBtn(darkOverlayBtn, darkOverlayTex, darkOverlayLabel,
        function() return darkOverlaysEnabled end,
        function()
            darkOverlaysEnabled = not darkOverlaysEnabled
            darkOverlayTex:SetAlpha(darkOverlaysEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            darkOverlayLabel:SetTextColor(1, 1, 1, darkOverlaysEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            darkOverlayLabel:SetText(darkOverlaysEnabled and "Dark Overlays\nEnabled" or "Dark Overlays\nDisabled")
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
    flashLabel:SetFont(FONT_PATH, 10, "OUTLINE")
    flashLabel:SetJustifyH("RIGHT")
    flashLabel:SetPoint("RIGHT", flashTex, "LEFT", -5, 0)
    flashLabel:SetTextColor(1, 1, 1, flashlightEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    flashLabel:SetText(flashlightEnabled and "Cursor Light\nEnabled" or "Cursor Light\nDisabled")
    flashBtn._label = flashLabel

    local flashLabelW = flashLabel:GetStringWidth() or 80
    flashBtn:SetSize(flashLabelW + 5 + iconSz, max(iconSz, 24))

    SetupToggleBtn(flashBtn, flashTex, flashLabel,
        function() return flashlightEnabled end,
        function()
            flashlightEnabled = not flashlightEnabled
            flashTex:SetAlpha(flashlightEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            flashLabel:SetTextColor(1, 1, 1, flashlightEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            flashLabel:SetText(flashlightEnabled and "Cursor Light\nEnabled" or "Cursor Light\nDisabled")
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
    magnetLabel:SetFont(FONT_PATH, 10, "OUTLINE")
    magnetLabel:SetJustifyH("LEFT")
    magnetLabel:SetPoint("LEFT", magnetTex, "RIGHT", 5, 0)
    magnetLabel:SetTextColor(1, 1, 1, snapEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    magnetLabel:SetText(snapEnabled and "Snap Elements\nEnabled" or "Snap Elements\nDisabled")
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
            magnetLabel:SetText(snapEnabled and "Snap Elements\nEnabled" or "Snap Elements\nDisabled")
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
    coordLabel:SetFont(FONT_PATH, 10, "OUTLINE")
    coordLabel:SetJustifyH("LEFT")
    coordLabel:SetPoint("LEFT", coordTex, "RIGHT", 1, 0)
    coordLabel:SetTextColor(1, 1, 1, coordsEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    coordLabel:SetText(coordsEnabled and "Coordinates\nEnabled" or "Coordinates\nDisabled")
    coordBtn._label = coordLabel

    local coordLabelW = coordLabel:GetStringWidth() or 110
    coordBtn:SetSize(iconSz + 5 + coordLabelW, max(iconSz, 24))

    SetupToggleBtn(coordBtn, coordTex, coordLabel,
        function() return coordsEnabled end,
        function()
            coordsEnabled = not coordsEnabled
            coordTex:SetAlpha(coordsEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            coordLabel:SetTextColor(1, 1, 1, coordsEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            coordLabel:SetText(coordsEnabled and "Coordinates\nEnabled" or "Coordinates\nDisabled")
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
    hoverLabel:SetFont(FONT_PATH, 10, "OUTLINE")
    hoverLabel:SetJustifyH("LEFT")
    hoverLabel:SetPoint("LEFT", hoverTex, "RIGHT", 5, 0)
    hoverLabel:SetTextColor(1, 1, 1, hoverBarEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
    hoverLabel:SetText(hoverBarEnabled and "Hover Top Bar\nEnabled" or "Hover Top Bar\nDisabled")
    hoverBtn._label = hoverLabel

    local hoverLabelW = hoverLabel:GetStringWidth() or 110
    hoverBtn:SetSize(iconSz + 5 + hoverLabelW, max(iconSz, 24))

    SetupToggleBtn(hoverBtn, hoverTex, hoverLabel,
        function() return hoverBarEnabled end,
        function()
            hoverBarEnabled = not hoverBarEnabled
            hoverTex:SetAlpha(hoverBarEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            hoverLabel:SetTextColor(1, 1, 1, hoverBarEnabled and HUD_ON_ALPHA or HUD_OFF_ALPHA)
            hoverLabel:SetText(hoverBarEnabled and "Hover Top Bar\nEnabled" or "Hover Top Bar\nDisabled")
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
        lbl:SetFont(FONT_PATH, BTN_FONT, "OUTLINE")
        lbl:SetPoint("CENTER")
        lbl:SetText("Save & Exit")
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
            shadow:SetText(text)
            shadow:SetTextColor(0, 0, 0, NORMAL_A)
            btn._shadow = shadow

            -- Main text
            local label = btn:CreateFontString(nil, "OVERLAY")
            label:SetFont(FONT_PATH, FONT_SZ, "")
            label:SetPoint("CENTER", btn, "CENTER", 0, 0)
            label:SetText(text)
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
        local zoneBot = screenH - (HOVER_ZONE_H * (hudFrame:GetScale() or uiScale)) - 10
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
    -- Also snapshot barScale for all action bars
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
        -- Snapshot barScale for revert
        if EAB and EAB.db and EAB.db.profile.bars[barKey] then
            local snap = snapshotPositions[barKey]
            if snap then
                snap.barScale = EAB.db.profile.bars[barKey].barScale
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
        -- Snapshot scale for all registered elements
        local elem = registeredElements[key]
        local snap = snapshotPositions[key]
        if snap and elem then
            -- Action bar elements: snapshot barScale from EAB profile
            if EAB and EAB.db and EAB.db.profile.bars[key] then
                snap.barScale = EAB.db.profile.bars[key].barScale
            else
                -- Non-action-bar elements: snapshot from getScale or frame:GetScale
                if elem.getScale then
                    snap.elemScale = elem.getScale(key)
                else
                    local fr = elem.getFrame and elem.getFrame(key)
                    if fr then snap.elemScale = fr:GetScale() end
                end
            end
        end
    end

    -- Snapshot anchor data so we can revert on discard
    wipe(snapshotAnchors)
    local anchorDB = GetAnchorDB()
    if anchorDB then
        for childKey, info in pairs(anchorDB) do
            snapshotAnchors[childKey] = { target = info.target, side = info.side }
        end
    end
end

-- Commit pending positions to SavedVariables
local function CommitPositions()
    for barKey, pos in pairs(pendingPositions) do
        if pos == "RESET" then
            ClearBarPosition(barKey)
        else
            -- For action bars, scale is saved directly to bars[barKey].barScale
            -- during slider drag, so don't duplicate it in barPositions.
            local elem = registeredElements[barKey]
            local saveScale = elem and pos.scale or nil
            local pt, rpt, px, py = pos.point, pos.relPoint, pos.x, pos.y
            -- If only scale changed (no drag), fill position from snapshot
            -- (live frame may have a CENTER anchor from center-preserving scale)
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
            SaveBarPosition(barKey, pt, rpt, px, py, saveScale)
            -- Install anchor guard for action bar positions
            if not elem then
                local bar = GetBarFrame(barKey)
                if bar then InstallAnchorGuard(bar, barKey) end
            end
        end
    end
end

-- Revert bars to their snapshot positions (discard all pending changes)
local function RevertPositions()
    if InCombatLockdown() then return end
    -- Restore action bar saved DB to snapshot state
    local db = GetPositionDB()
    if db then
        for barKey, _ in pairs(pendingPositions) do
            if not registeredElements[barKey] then
                if snapshotPositions[barKey] then
                    local snap = snapshotPositions[barKey]
                    db[barKey] = { point = snap.point, relPoint = snap.relPoint, x = snap.x, y = snap.y }
                else
                    db[barKey] = nil
                end
            end
        end
    end
    -- Revert action bar scale to snapshot values
    if EAB and EAB.db then
        for barKey, _ in pairs(pendingPositions) do
            -- For action bars, revert barScale to the snapshot value.
            local snap = snapshotPositions[barKey]
            if snap and snap.barScale and EAB.db.profile.bars[barKey] then
                EAB.db.profile.bars[barKey].barScale = snap.barScale
            end
        end
    end
    -- Revert registered elements via their savePosition callback
    for barKey, _ in pairs(pendingPositions) do
        local elem = registeredElements[barKey]
        if elem and elem.savePosition then
            local snap = snapshotPositions[barKey]
            if snap and not snap._fromLiveFrame then
                -- Pass snapshotted scale back to savePosition for non-EAB elements
                local revertScale = snap.elemScale
                elem.savePosition(barKey, snap.point, snap.relPoint or snap.point, snap.x, snap.y, revertScale)
            end
        end
    end
    -- Move all frames back to their original positions and scale
    for barKey, _ in pairs(pendingPositions) do
        local bar = GetBarFrame(barKey)
        if bar then
            local snap = snapshotPositions[barKey]
            if snap then
                -- Revert scale for non-action-bar registered elements
                local elem = registeredElements[barKey]
                if elem and not (EAB and EAB.db and EAB.db.profile.bars[barKey]) and snap.elemScale then
                    pcall(function() bar:SetScale(snap.elemScale) end)
                end
                pcall(function()
                    bar:ClearAllPoints()
                    bar:SetPoint(snap.point, UIParent, snap.relPoint, snap.x, snap.y)
                end)
            elseif bar.UpdateGridLayout then
                pcall(bar.UpdateGridLayout, bar)
            end
        end
    end

    -- Revert anchor data to snapshot state
    local anchorDB = GetAnchorDB()
    if anchorDB then
        wipe(anchorDB)
        for childKey, info in pairs(snapshotAnchors) do
            anchorDB[childKey] = { target = info.target, side = info.side }
        end
    end
end

-- Internal close (actually hides everything and returns to options)
local function DoClose()
    if not isUnlocked then return end
    isUnlocked = false
    EllesmereUI._unlockActive = false
    EllesmereUI._unlockModeActive = false

    -- Notify beacon reminders to restore (if follow-mouse is active)
    if _G._EABR_BeaconRefresh then pcall(_G._EABR_BeaconRefresh) end

    -- Restore objective tracker
    if objTrackerWasVisible then
        local objTracker = _G.ObjectiveTrackerFrame
        if objTracker then
            objTracker:SetAlpha(1)
            if objTracker.EnableMouse then pcall(objTracker.EnableMouse, objTracker, true) end
        end
        objTrackerWasVisible = false
    end

    if not unlockFrame then return end

    unlockFrame:SetScript("OnUpdate", nil)
    if logoFadeFrame then logoFadeFrame:SetScript("OnUpdate", nil); logoFadeFrame:Hide() end
    if openAnimFrame then openAnimFrame:Hide() end
    if lockAnimFrame then lockAnimFrame:Hide() end
    if gridFrame then gridFrame:SetScript("OnUpdate", nil); gridFrame:Hide() end
    if hudFrame then hudFrame:SetScript("OnUpdate", nil); hudFrame:Hide() end
    if unlockTipFrame then unlockTipFrame:SetScript("OnUpdate", nil); unlockTipFrame:Hide() end
    DeselectMover()
    for _, m in pairs(movers) do m._snapTarget = nil; m:Hide() end
    HideAllGuidesAndHighlight()
    unlockFrame:Hide()
    unlockFrame:SetAlpha(1)

    -- Clean up arrow key nudge state
    selectedMover = nil
    selectElementPicker = nil
    if arrowKeyFrame then wipe(arrowHeld); arrowKeyFrame:Hide() end

    -- Reset session state
    wipe(pendingPositions)
    wipe(snapshotPositions)
    wipe(snapshotAnchors)
    hasChanges = false

    -- Clean up pick mode / anchor dropdown state
    pickMode = nil
    pickModeMover = nil
    if anchorDropdownFrame then anchorDropdownFrame:Hide() end
    if anchorDropdownCatcher then anchorDropdownCatcher:Hide() end

    -- Restore action bar alpha and scale (MainBar may have been hidden by OnWorld)
    if EAB and EAB.db and not InCombatLockdown() then
        for _, barKey in ipairs(ALL_BAR_ORDER) do
            local barInfo = BAR_LOOKUP[barKey]
            if barInfo then
                local s = EAB.db.profile.bars[barKey]
                if s and not s.alwaysHidden then
                    local bar = _G[barInfo.frameName]
                    if not bar and barInfo.fallbackFrame then bar = _G[barInfo.fallbackFrame] end
                    if bar and bar:GetAlpha() == 0 and not s.mouseoverEnabled then
                        bar:SetAlpha(1)
                    end
                    -- Also restore parent frame alpha (MainBar has MainMenuBar as parent)
                    if barInfo.fallbackFrame then
                        local pf = _G[barInfo.fallbackFrame]
                        if pf and pf ~= bar and pf:GetAlpha() == 0 and not s.mouseoverEnabled then
                            pf:SetAlpha(1)
                        end
                    end
                end
            end
        end
        if EAB and EAB.ApplyScaleForBar then
            for _, bk in ipairs(ALL_BAR_ORDER) do
                if BAR_LOOKUP[bk] then
                    EAB:ApplyScaleForBar(bk)
                end
            end
        end
    end

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
        -- Dismiss (ESC / click-off) does nothing — user stays in unlock mode,
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
        local TIP_W, TIP_H = 380, 175
        local ar, ag, ab = GetAccent()

        local tip = CreateFrame("Frame", nil, UIParent)
        tip:SetFrameStrata("FULLSCREEN_DIALOG")
        tip:SetFrameLevel(200)
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
        arrowClip:SetFrameStrata("FULLSCREEN_DIALOG")
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
        msg:SetFont(FONT_PATH, 12, "OUTLINE")
        msg:SetTextColor(1, 1, 1, 0.85)
        msg:SetPoint("TOP", tip, "TOP", 0, -17)
        msg:SetWidth(TIP_W - 30)
        msg:SetJustifyH("CENTER")
        msg:SetSpacing(6)
        msg:SetText("This is where you can control the settings of Unlock Mode.\n\nElement repositioning supports dragging,\narrow keys, and shift arrow keys.\nSnapping is based on closest element.\nSnap to a specific element via the cogwheel icon.")

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
    isUnlocked = true
    EllesmereUI._unlockActive = true
    EllesmereUI._unlockModeActive = true

    -- Notify beacon reminders to hide (if follow-mouse is active)
    if _G._EABR_BeaconRefresh then pcall(_G._EABR_BeaconRefresh) end

    -- Hide objective tracker (alpha only — no :Hide() to avoid taint)
    local objTracker = _G.ObjectiveTrackerFrame
    if objTracker and objTracker:IsShown() then
        objTrackerWasVisible = true
        objTracker:SetAlpha(0)
        if objTracker.EnableMouse then pcall(objTracker.EnableMouse, objTracker, false) end
    else
        objTrackerWasVisible = false
    end

    -- Reset session state and snapshot current positions
    wipe(pendingPositions)
    hasChanges = false
    selectedMover = nil
    SnapshotPositions()

    -- Setup and show arrow key frame for nudge support
    SetupArrowKeyFrame()
    wipe(arrowHeld)
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

    -- Grid glitch starts immediately and lasts 0.75s
    local GLITCH_DUR = 0.75
    local GRID_START = 0  -- grid begins immediately
    local gridStarted = false

    unlockFrame:SetScript("OnUpdate", function(self, dt)
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
            end

            local glitchT = elapsed - GRID_START
            local glitchProgress = min(1, glitchT / GLITCH_DUR)

            -- (Banner slides down during shackle phase, not here)

            -- Movers fade in over 0.75s, delayed by 0.5s
            local MOVER_DELAY = 0.50
            for _, m in pairs(movers) do
                if m:IsShown() then
                    local moverT = glitchT - MOVER_DELAY
                    if moverT > 0 then
                        m:SetAlpha((darkOverlaysEnabled and 1 or MOVER_ALPHA) * min(1, moverT / GLITCH_DUR))
                    else
                        m:SetAlpha(0)
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

        -- ReapplyAllAnchors during open sets hasChanges; reset it since
        -- the user hasn't actually changed anything yet.
        hasChanges = false
        wipe(pendingPositions)

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
            if objTracker.EnableMouse then pcall(objTracker.EnableMouse, objTracker, true) end
        end
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
    if arrowKeyFrame then wipe(arrowHeld); arrowKeyFrame:Hide() end
    selectedMover = nil
    selectElementPicker = nil

    -- Restore action bar alpha (so bars are usable during combat)
    if EAB and EAB.db then
        for _, barKey in ipairs(ALL_BAR_ORDER) do
            local barInfo = BAR_LOOKUP[barKey]
            if barInfo then
                local s = EAB.db.profile.bars[barKey]
                if s and not s.alwaysHidden then
                    local bar = _G[barInfo.frameName]
                    if not bar and barInfo.fallbackFrame then bar = _G[barInfo.fallbackFrame] end
                    if bar and bar:GetAlpha() == 0 and not s.mouseoverEnabled then
                        bar:SetAlpha(1)
                    end
                end
            end
        end
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

    -- Notify beacon reminders to hide
    if _G._EABR_BeaconRefresh then pcall(_G._EABR_BeaconRefresh) end

    -- Re-show unlock UI
    if arrowKeyFrame then wipe(arrowHeld); arrowKeyFrame:Show() end
    if unlockFrame then unlockFrame:Show(); unlockFrame:SetAlpha(1) end
    if gridFrame and gridMode ~= "disabled" then gridFrame:Show() end
    if hudFrame then hudFrame:Show() end

    -- Re-sync and show all movers
    for _, m in pairs(movers) do
        m:Sync()
        m:SetAlpha(darkOverlaysEnabled and 1 or MOVER_ALPHA)
        m:Show()
    end
    SortMoverFrameLevels()
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
