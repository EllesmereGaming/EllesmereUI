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
    function EllesmereUI:RegisterUnlockElements(elements)
        for _, elem in ipairs(elements) do
            for short, long in pairs(FIELD_ALIASES) do
                if elem[short] and not elem[long] then
                    elem[long] = elem[short]
                end
            end
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
        if key:sub(1, 4) == "CDM_" then
            local rawKey = key:sub(5)
            local cdm = EllesmereUI.Lite and EllesmereUI.Lite.GetAddon and EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
            local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
            if cdmBars and cdmBars.bars then
                for _, bar in ipairs(cdmBars.bars) do
                    if bar.key == rawKey then
                        local g = bar.growDirection
                        if g and g ~= "RIGHT" then growDir = g end
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

-------------------------------------------------------------------------------
--  Pure-data position migration for profile import
--
--  Converts ALL position fields in a raw profile data table from any legacy
--  format to CENTER/CENTER. Uses only arithmetic on stored values -- no
--  frames, no WoW API beyond UIParent:GetSize(). Safe to call at import
--  time before ReloadUI() and at ADDON_LOADED time for migration.
--
--  Handles:
--    CENTER/CENTER   -> pass through (already correct)
--    CENTER/TOPLEFT  -> subtract uiW/2 from x, add uiH/2 to y
--    TOPLEFT/TOPLEFT -> offset by half element size, then TOPLEFT->CENTER
--    LEFT/CENTER     -> offset by half element width
--    RIGHT/RIGHT     -> convert using uiW and element width
--    RIGHT/CENTER    -> offset by half element width (negative)
--    Any other       -> best-effort TOPLEFT assumption
-------------------------------------------------------------------------------
function EllesmereUI.MigrateProfilePositions(profileData)
    if not profileData or not profileData.addons then return end
    local uiW, uiH = UIParent:GetSize()
    local halfW, halfH = uiW / 2, uiH / 2

    -- Convert a single position table in-place.
    -- ew/eh = estimated element width/height (for TOPLEFT conversion).
    local function ConvertPos(pos, ew, eh)
        if not pos then return end
        -- No point field means it was saved by 5.2.0+ code that only
        -- writes CENTER/CENTER but the field was omitted. Stamp it.
        if not pos.point then
            pos.point = "CENTER"
            pos.relPoint = "CENTER"
            return
        end
        local pt = pos.point
        local rp = pos.relPoint or pt
        -- Already CENTER/CENTER: nothing to do
        if pt == "CENTER" and rp == "CENTER" then return end

        local x, y = pos.x or 0, pos.y or 0
        local cx, cy

        if pt == "CENTER" and rp == "TOPLEFT" then
            cx = x - halfW
            cy = y + halfH
        elseif pt == "TOPLEFT" and rp == "TOPLEFT" then
            local hw, hh = (ew or 0) / 2, (eh or 0) / 2
            cx = x + hw - halfW
            cy = y - hh + halfH
        elseif pt == "LEFT" and rp == "CENTER" then
            cx = x + (ew or 0) / 2
            cy = y
        elseif pt == "RIGHT" and rp == "RIGHT" then
            cx = halfW + x - (ew or 0) / 2
            cy = y
        elseif pt == "RIGHT" and rp == "CENTER" then
            cx = x - (ew or 0) / 2
            cy = y
        elseif rp == "CENTER" then
            cx = x
            cy = y
        else
            local hw, hh = (ew or 0) / 2, (eh or 0) / 2
            cx = x + hw - halfW
            cy = y - hh + halfH
        end

        pos.point = "CENTER"
        pos.relPoint = "CENTER"
        pos.x = cx
        pos.y = cy
    end

    local function EstimateUFSize(ufProfile, unitKey)
        local s = ufProfile[unitKey]
        if not s then return 160, 46 end
        local fw = s.frameWidth or 160
        local hh = s.healthHeight or 34
        local powerPos = s.powerPosition or "below"
        local powerH = 0
        if powerPos == "below" or powerPos == "above" then
            powerH = s.powerHeight or 6
        end
        local btbH = 0
        if s.bottomTextBar then
            local btbPos = s.btbPosition or "bottom"
            if btbPos == "top" or btbPos == "bottom" then
                btbH = s.bottomTextBarHeight or 16
            end
        end
        local totalH = hh + powerH + btbH
        local portraitStyle = ufProfile.portraitStyle or "attached"
        local showPortrait = s.showPortrait ~= false
        local totalW = fw
        if showPortrait and portraitStyle == "attached" then
            totalW = fw + totalH + (s.portraitSize or 0)
        end
        return totalW, totalH
    end

    -- 1. Action bar barPositions
    local ab = profileData.addons["EllesmereUIActionBars"]
    if ab and ab.barPositions then
        for barKey, pos in pairs(ab.barPositions) do
            local ew, eh = 200, 40
            if ab.bars and ab.bars[barKey] then
                local bs = ab.bars[barKey]
                local bw = bs.buttonWidth or bs.buttonHeight or 36
                local bh = bs.buttonHeight or bs.buttonWidth or 36
                local numIcons = bs.overrideNumIcons or 12
                local numRows = bs.overrideNumRows or 1
                local spacing = bs.spacing or 2
                local cols = math.ceil(numIcons / numRows)
                ew = cols * bw + (cols - 1) * spacing
                eh = numRows * bh + (numRows - 1) * spacing
            end
            ConvertPos(pos, ew, eh)
        end
    end

    -- 2. UF positions
    local uf = profileData.addons["EllesmereUIUnitFrames"]
    if uf and uf.positions then
        for unitKey, pos in pairs(uf.positions) do
            local ew, eh = EstimateUFSize(uf, unitKey)
            if unitKey == "boss" then
                ew, eh = EstimateUFSize(uf, "boss")
            elseif unitKey == "playerCastbar" then
                local pw, _ = EstimateUFSize(uf, "player")
                local cbH = uf.player and uf.player.playerCastbarHeight or 14
                if cbH <= 0 then cbH = 14 end
                ew, eh = pw, cbH
            elseif unitKey == "classPower" then
                ew, eh = 120, 14
            end
            ConvertPos(pos, ew, eh)
        end
    end

    -- 3. CDM barPositions
    local cdm = profileData.addons["EllesmereUICooldownManager"]
    if cdm and cdm.cdmBarPositions then
        for barKey, pos in pairs(cdm.cdmBarPositions) do
            local ew = 200
            local eh = 40
            if cdm.cdmBars and cdm.cdmBars.bars then
                for _, bar in ipairs(cdm.cdmBars.bars) do
                    if bar.key == barKey then
                        local iconSz = bar.iconSize or 36
                        local numSpells = bar.trackedSpells and #bar.trackedSpells or 3
                        local numRows = bar.numRows or 1
                        local spacing = bar.spacing or 2
                        local cols = math.ceil(numSpells / numRows)
                        ew = cols * iconSz + (cols - 1) * spacing
                        eh = numRows * iconSz + (numRows - 1) * spacing
                        break
                    end
                end
            end
            ConvertPos(pos, ew, eh)
        end
    end

    -- 4. Resource bar unlockPos
    local rb = profileData.addons["EllesmereUIResourceBars"]
    if rb then
        local sections = { "health", "primary", "castBar" }
        for _, section in ipairs(sections) do
            local s = rb[section]
            if s and s.unlockPos then
                local ew = s.width or 214
                local eh = s.height or 16
                ConvertPos(s.unlockPos, ew, eh)
            end
        end
        if rb.secondary and rb.secondary.unlockPos then
            local s = rb.secondary
            local ew = s.pipWidth or 214
            local eh = s.pipHeight or 20
            ConvertPos(s.unlockPos, ew, eh)
        end
    end

    -- 5. EABR unlockPos
    local eabr = profileData.addons["EllesmereUIAuraBuffReminders"]
    if eabr and eabr.unlockPos then
        local disp = eabr.display or {}
        local scale = disp.scale or 1.0
        local iconSz = math.floor(32 * scale + 0.5)
        local spacing = disp.iconSpacing or 8
        local count = 2
        local ew = count * iconSz + (count - 1) * spacing
        local textH = 0
        if disp.showText then
            textH = (disp.textSize or 11) + math.abs(disp.textYOffset or -2)
        end
        local eh = iconSz + textH
        ConvertPos(eabr.unlockPos, ew, eh)
    end

    -- 6. Cursor unlockPos
    local cursor = profileData.addons["EllesmereUICursor"]
    if cursor and cursor.unlockPos then
        local scale = cursor.scale or 1
        local sz = math.floor(40 * scale + 0.5)
        ConvertPos(cursor.unlockPos, sz, sz)
    end
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

-- RecenterBarAnchor(barKey)
-- Synchronously re-applies a CENTER anchor to the bar frame so it grows
-- symmetrically from its center on the next resize. Must be synchronous
-- (no C_Timer.After) to avoid a visible flicker frame.
--
-- Uses GetLeft()/GetTop() + current GetWidth()/GetHeight() to compute center.
-- These are reliable immediately after SetSize() because GetLeft/GetTop reflect
-- the anchor position (not the rendered position), and GetWidth/GetHeight return
-- the value just set. b:GetCenter() is NOT used -- it can be stale before flush.
--
-- Stored on EllesmereUI to avoid adding upvalues to CreateMover.
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

    pcall(function()
        b:ClearAllPoints()
        b:SetPoint(anchor, UIParent, "BOTTOMLEFT", aX, aY)
    end)

    -- Keep mover's stored center in sync so drag/snap logic stays consistent
    local m = movers[barKey]
    if m and m._setCenterXY then
        m._setCenterXY(uiCX, uiCY - UIParent:GetHeight())
    end
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
        local EAB = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
        if EAB and EAB.db then
            EAB.db.profile.selectedBar = key
        end
    end
end
local function SelectUnitFrame(unit)
    return function()
        -- Direct setter (if init already ran) + pending flag (consumed at page build)
        if EllesmereUI._setUnitFrameUnit then EllesmereUI._setUnitFrameUnit(unit) end
        EllesmereUI._pendingUnitSelect = unit
    end
end
EllesmereUI._ELEMENT_SETTINGS_MAP = {
    -- Unit Frames (all share "Frame Display" page; dropdown pre-selected to correct unit)
    ["player"]       = { module = "EllesmereUIUnitFrames",       page = "Frame Display",                sectionName = "HEALTH BAR",       preSelectFn = SelectUnitFrame("player"),       highlightText = "Bar Height" },
    ["target"]       = { module = "EllesmereUIUnitFrames",       page = "Frame Display",                sectionName = "HEALTH BAR",       preSelectFn = SelectUnitFrame("target"),       highlightText = "Bar Height" },
    ["focus"]        = { module = "EllesmereUIUnitFrames",       page = "Frame Display",                sectionName = "HEALTH BAR",       preSelectFn = SelectUnitFrame("focus"),        highlightText = "Bar Height" },
    ["pet"]          = { module = "EllesmereUIUnitFrames",       page = "Frame Display",                sectionName = "HEALTH BAR",       preSelectFn = SelectUnitFrame("pet"),          highlightText = "Bar Height" },
    ["targettarget"] = { module = "EllesmereUIUnitFrames",       page = "Frame Display",                sectionName = "HEALTH BAR",       preSelectFn = SelectUnitFrame("targettarget"), highlightText = "Bar Height" },
    ["focustarget"]  = { module = "EllesmereUIUnitFrames",       page = "Frame Display",                sectionName = "HEALTH BAR",       preSelectFn = SelectUnitFrame("focustarget"),  highlightText = "Bar Height" },
    ["boss"]         = { module = "EllesmereUIUnitFrames",       page = "Frame Display",                sectionName = "HEALTH BAR",       preSelectFn = SelectUnitFrame("boss"),         highlightText = "Bar Height" },
    ["classPower"]   = { module = "EllesmereUIUnitFrames",       page = "Frame Display",                sectionName = "CLASS RESOURCE",   preSelectFn = SelectUnitFrame("player"),       highlightText = "Enable Class Resource" },

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

    -- General
    ["EUI_FPS"]            = { module = "_EUIGlobal", page = "General", sectionName = "EXTRAS", highlightText = "Show FPS Counter" },
    ["EUI_SecondaryStats"] = { module = "_EUIGlobal", page = "General", sectionName = "EXTRAS", highlightText = "Secondary Stat Display" },
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
    if barKey:sub(1, 4) == "CDM_" then
        local rawKey = barKey:sub(5)
        local cdm = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
        local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
        if cdmBars and cdmBars.bars then
            for _, bar in ipairs(cdmBars.bars) do
                if bar.key == rawKey then
                    return bar.growDirection or "RIGHT"
                end
            end
        end
        return "RIGHT"
    else
        local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
        local s = eab and eab.db and eab.db.profile and eab.db.profile.bars
                  and eab.db.profile.bars[barKey]
        if s then
            return (s.growDirection or "up"):upper()
        end
        return "UP"
    end
end

-------------------------------------------------------------------------------
--  Grow direction helper -- reads from the bar's per-profile settings
--  Returns the uppercase grow direction string, or nil if default/unset.
--  Action bar default is "UP", CDM default is "RIGHT".
-------------------------------------------------------------------------------
local function GetBarGrowDir(barKey)
    if barKey:sub(1, 4) == "CDM_" then
        local rawKey = barKey:sub(5)
        local cdm = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
        local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
        if cdmBars and cdmBars.bars then
            for _, bar in ipairs(cdmBars.bars) do
                if bar.key == rawKey then
                    local g = bar.growDirection
                    if g and g ~= "RIGHT" then return g end
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
            if g ~= "UP" then return g end
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

function MatchH.SetWidthMatch(childKey, targetKey)
    local db = MatchH.GetWidthMatchDB()
    if not db then return end
    db[childKey] = targetKey
end

function MatchH.SetHeightMatch(childKey, targetKey)
    local db = MatchH.GetHeightMatchDB()
    if not db then return end
    db[childKey] = targetKey
end

function MatchH.ClearWidthMatch(childKey)
    local db = MatchH.GetWidthMatchDB()
    if not db then return end
    db[childKey] = nil
end

function MatchH.ClearHeightMatch(childKey)
    local db = MatchH.GetHeightMatchDB()
    if not db then return end
    db[childKey] = nil
end

-- Apply width/height match: sync source size from target
-- _propagatingMatch prevents re-entrant loops: setWidth triggers OnSizeChanged
-- which calls NotifyElementResized which would call PropagateWidthMatch again.
local _propagatingMatch = false

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
        local sourceElem = registeredElements[sourceKey]
        if sourceElem and sourceElem.setWidth then
            if isUnlocked then
                local sb = GetBarFrame(sourceKey)
                local savedAlpha = sb and sb._euiRestoreAlpha
                if sb and not savedAlpha then sb:SetAlpha(0) end
                _propagatingMatch = true
                pcall(sourceElem.setWidth, sourceKey, targetW)
                _propagatingMatch = false
                EllesmereUI.RecenterBarAnchor(sourceKey)
                if sb and not savedAlpha then
                    C_Timer.After(0, function() sb:SetAlpha(1) end)
                end
                local m = movers[sourceKey]
                if m then m:SyncSize() end
            else
                _propagatingMatch = true
                pcall(sourceElem.setWidth, sourceKey, targetW)
                _propagatingMatch = false
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
        local sourceElem = registeredElements[sourceKey]
        if sourceElem and sourceElem.setHeight then
            if isUnlocked then
                local sb = GetBarFrame(sourceKey)
                local savedAlpha = sb and sb._euiRestoreAlpha
                if sb and not savedAlpha then sb:SetAlpha(0) end
                _propagatingMatch = true
                pcall(sourceElem.setHeight, sourceKey, targetH)
                _propagatingMatch = false
                EllesmereUI.RecenterBarAnchor(sourceKey)
                if sb and not savedAlpha then
                    C_Timer.After(0, function() sb:SetAlpha(1) end)
                end
                local m = movers[sourceKey]
                if m then m:SyncSize() end
            else
                _propagatingMatch = true
                pcall(sourceElem.setHeight, sourceKey, targetH)
                _propagatingMatch = false
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
        for k, axis in pairs(keys) do
            -- If this element itself is anchored, re-apply its own position
            -- first (handles the case where the element resized and needs to
            -- reposition relative to its anchor target).
            local anchorDB = GetAnchorDB()
            if anchorDB then
                local ownInfo = anchorDB[k]
                if ownInfo and ownInfo.target then
                    ApplyAnchorPosition(k, ownInfo.target, ownInfo.side)
                end
            end
            -- Propagate with axis filter (nil = all axes)
            local propagateAxis = (axis == "all") and nil or axis
            PropagateAnchorChain(k, nil, propagateAxis)
        end
        -- Persist any positions that were updated by the propagation.
        -- Set a flag so savePos callbacks that trigger full rebuilds
        -- (e.g. CDM's BuildAllCDMBars) can skip the rebuild -- the bar
        -- is already in the correct position from ApplyAnchorPosition.
        EllesmereUI._propagatingSave = true
        for childKey, pos in pairs(pendingPositions) do
            if type(pos) == "table" and pos.point then
                SaveBarPosition(childKey, pos.point, pos.relPoint, pos.x, pos.y)
            end
        end
        EllesmereUI._propagatingSave = false
        wipe(pendingPositions)
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
    -- Skip position re-application if LayoutBar is handling it
    if EllesmereUI._layoutBarResizing == key then return end
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

    -- Propagate width/height matches to dependents
    local wdb = MatchH.GetWidthMatchDB()
    if wdb then
        local hasChildren = false
        for childKey, tKey in pairs(wdb) do
            if tKey == key then hasChildren = true; break end
        end
        if hasChildren then
            EllesmereUI.PropagateWidthMatch(key)
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
    end
end

-------------------------------------------------------------------------------
--  Apply ALL width/height matches globally (used on login/reload)
-------------------------------------------------------------------------------
local function ApplyAllWidthHeightMatches()
    -- Width matches
    local wdb = MatchH.GetWidthMatchDB()
    if wdb then
        for childKey, targetKey in pairs(wdb) do
            MatchH.ApplyWidthMatch(childKey, targetKey)
        end
    end
    -- Height matches
    local hdb = MatchH.GetHeightMatchDB()
    if hdb then
        for childKey, targetKey in pairs(hdb) do
            MatchH.ApplyHeightMatch(childKey, targetKey)
        end
    end
end

-------------------------------------------------------------------------------
--  OnSizeChanged hook for registered element frames
--  Automatically fires NotifyElementResized when a frame changes size,
--  so dependent elements (width-matched, anchored) update without the
--  source addon needing to call anything.
-------------------------------------------------------------------------------
local _sizeHookedFrames = {}  -- [frame] = true

local function HookFrameSizeChanged(key)
    local bar = GetBarFrame(key)
    if not bar or _sizeHookedFrames[bar] then return end
    _sizeHookedFrames[bar] = true
    bar:HookScript("OnSizeChanged", function()
        if isUnlocked then return end
        EllesmereUI.NotifyElementResized(key)
    end)
end

-- Wrap RegisterUnlockElements so newly registered elements get OnSizeChanged
-- hooks installed automatically (handles late registrations like CDM bars).
do
    local origRegister = EllesmereUI.RegisterUnlockElements
    function EllesmereUI:RegisterUnlockElements(elements)
        origRegister(self, elements)
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

-- Apply an anchor relationship: position the child element relative to the target
-- side: "LEFT", "RIGHT", "TOP", "BOTTOM" -- child is placed on that side of the target
-- offsetX/offsetY: if present, position child relative to the anchor edge
ApplyAnchorPosition = function(childKey, targetKey, side, noMark, noMove)
    local childBar = GetBarFrame(childKey)
    local targetBar = GetBarFrame(targetKey)
    if not childBar or not targetBar then return end
    if InCombatLockdown() then return end

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
        -- Store the computed offset as edge-to-edge
        if ai then
            local edgeX, edgeY
            if side == "LEFT" then
                edgeX = tL; edgeY = tCY
                ai.offsetX = (cx + cW / 2) - edgeX
                ai.offsetY = cy - edgeY
            elseif side == "RIGHT" then
                edgeX = tR; edgeY = tCY
                ai.offsetX = (cx - cW / 2) - edgeX
                ai.offsetY = cy - edgeY
            elseif side == "TOP" then
                edgeX = tCX; edgeY = tT
                ai.offsetX = cx - edgeX
                ai.offsetY = (cy - cH / 2) - edgeY
            elseif side == "BOTTOM" then
                edgeX = tCX; edgeY = tB
                ai.offsetX = cx - edgeX
                ai.offsetY = (cy + cH / 2) - edgeY
            else
                edgeX = tCX; edgeY = tCY
                ai.offsetX = cx - edgeX
                ai.offsetY = cy - edgeY
            end
        end
    end

    -- Convert child center to CENTER-relative offset for centralized positioning
    local uiW, uiH = UIParent:GetSize()
    local centerX = cx - uiW / 2
    local centerY = cy - uiH / 2

    -- Only move the actual bar frame when noMove is not set
    if not noMove then
        pcall(function()
            childBar:ClearAllPoints()
            childBar:SetPoint("CENTER", UIParent, "CENTER", centerX, centerY)
        end)
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
        if ai then
            -- Store offset as edge-to-edge (child near edge to target edge)
            local actualHW = (bR - bL) / 2
            local actualHH = (bT - bB) / 2
            if side == "LEFT" then
                ai.offsetX = (actualCX + actualHW) - tL
                ai.offsetY = actualCY - tCY
            elseif side == "RIGHT" then
                ai.offsetX = (actualCX - actualHW) - tR
                ai.offsetY = actualCY - tCY
            elseif side == "TOP" then
                ai.offsetX = actualCX - tCX
                ai.offsetY = (actualCY - actualHH) - tT
            elseif side == "BOTTOM" then
                ai.offsetX = actualCX - tCX
                ai.offsetY = (actualCY + actualHH) - tB
            else
                ai.offsetX = actualCX - tCX
                ai.offsetY = actualCY - tCY
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
        pendingPositions[childKey] = {
            point = "CENTER", relPoint = "CENTER",
            x = centerX, y = centerY,
        }
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
                ApplyAnchorPosition(childKey, info.target, info.side)
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
    for childKey, info in pairs(adb) do
        if info.target and GetBarFrame(childKey) and GetBarFrame(info.target) then
            ApplyAnchorPosition(childKey, info.target, info.side)
        end
    end
    -- Flush pending positions so db.profile.positions stays in sync
    for childKey, pos in pairs(pendingPositions) do
        if type(pos) == "table" and pos.point then
            SaveBarPosition(childKey, pos.point, pos.relPoint, pos.x, pos.y)
        end
    end
    wipe(pendingPositions)
end

-- Resync anchor offsets from actual frame positions. Called AFTER a profile
-- import/switch once all frames are at their correct absolute positions
-- (from db.profile.positions). This does NOT move any frames -- it reads
-- their current screen positions and recomputes the anchor offsets so the
-- anchor relationships stay correct for future drag operations.
EllesmereUI.ResyncAnchorOffsets = function()
    local adb = GetAnchorDB()
    if not adb then return end
    for childKey, info in pairs(adb) do
        if info.target and GetBarFrame(childKey) and GetBarFrame(info.target) then
            ApplyAnchorPosition(childKey, info.target, info.side, true, true)
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
        return "CENTER", "CENTER", x, y
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
        -- No anchor relationship -- use grow direction to pick fixed edge
        local growDir = GetBarGrowDirActual(barKey)
        if growDir and growDir ~= "CENTER" then
            local fw = (frame:GetWidth() or 0)
            local fh = (frame:GetHeight() or 0)
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

    pcall(function()
        if InCombatLockdown() and frame:IsProtected() then
            local deferFrame = CreateFrame("Frame")
            deferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            deferFrame:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                pcall(function()
                    frame:ClearAllPoints()
                    frame:SetPoint(anchor, UIParent, "CENTER", adjX, adjY)
                end)
            end)
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
    -- Convert to CENTER/CENTER before storing
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
    -- Already CENTER/CENTER: apply directly
    if pos.point == "CENTER" and pos.relPoint == "CENTER" then
        return ApplyCenterPosition(barKey, pos)
    end
    -- Legacy format: apply in old format first so frame has valid bounds
    if frame then
        pcall(function()
            frame:ClearAllPoints()
            frame:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
        end)
    end
    -- Convert to CENTER using live frame bounds (most accurate)
    local cp, crp, cx, cy = ConvertToCenterPos(barKey, pos.point, pos.relPoint, pos.x, pos.y)
    -- Save back in CENTER format (suppress rebuilds during migration)
    EllesmereUI._propagatingSave = true
    local elem = registeredElements[barKey]
    if elem and elem.savePosition then
        elem.savePosition(barKey, cp, crp, cx, cy)
    else
        local db = GetPositionDB()
        if db then
            db[barKey] = { point = cp, relPoint = crp, x = cx, y = cy }
        end
    end
    EllesmereUI._propagatingSave = false
    -- Now apply with centralized grow logic
    return ApplyCenterPosition(barKey, { point = cp, relPoint = crp, x = cx, y = cy })
end

local function ApplySavedPositions()
    if InCombatLockdown() then return end

    -- Action bars: apply from barPositions DB with lazy migration
    local db = GetPositionDB()
    if db then
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
            -- Let addon initialize/build (e.g. CDM's BuildAllCDMBars)
            if elem.applyPosition then
                pcall(elem.applyPosition, key)
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
                    MigrateAndApplyPosition(key, pos, frame)
                end
            end
        end
        -- Install OnSizeChanged hook so future resizes auto-propagate
        HookFrameSizeChanged(key)
    end

    -- Apply all width/height matches now that positions are set
    ApplyAllWidthHeightMatches()

    -- Reapply all anchor positions (anchored elements need to follow their targets)
    local adb = GetAnchorDB()
    if adb then
        local unresolved = {}
        for childKey, info in pairs(adb) do
            if info.target and GetBarFrame(childKey) and GetBarFrame(info.target) then
                ApplyAnchorPosition(childKey, info.target, info.side)
                -- Check if it actually resolved (target had valid bounds)
                local target = GetBarFrame(info.target)
                if not target:GetLeft() then
                    unresolved[childKey] = info
                end
            end
        end
        -- Retry unresolved anchors until all targets have valid layout
        if next(unresolved) then
            local retries = 0
            local function RetryAnchors()
                retries = retries + 1
                local still = {}
                for childKey, info in pairs(unresolved) do
                    local target = GetBarFrame(info.target)
                    if target and target:GetLeft() then
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
-- PLAYER_ENTERING_WORLD listener so positions, width/height matches, and
-- anchor chains are still applied for CDM, resource bars, etc.
if not EAB then
    local _posFrame = CreateFrame("Frame")
    _posFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _posFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- Delay so child addons have time to register their unlock elements
        C_Timer.After(1, ApplySavedPositions)
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
        m:SetFrameLevel(m._raisedLevel)
        if not darkOverlaysEnabled then m:SetAlpha(MOVER_HOVER) end
        m._brd:SetColor(1, 1, 1, 0.9)

        -- Expand the mover if not already expanded
        if m._showOverlayText then m._showOverlayText() end

        -- Coordinates will show when expand animation completes

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
        if not selectedMover._dragging and not selectedMover:IsMouseOver() then
            selectedMover:SetFrameLevel(selectedMover._baseLevel)
            if not darkOverlaysEnabled then selectedMover:SetAlpha(MOVER_ALPHA) end
            selectedMover._brd:SetColor(ar, ag, ab, 0.6)
            -- Collapse overlay since no longer selected or hovered
            if selectedMover._hideOverlayText then selectedMover._hideOverlayText() end
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
local function NudgeMover(dx, dy)
    local m = selectedMover
    if not m or InCombatLockdown() then return end

    -- Use stored center (UIParent-TOPLEFT coords) so hover-expand doesn't corrupt position.
    -- moverCX/moverCY are in TOPLEFT space (Y negative downward); convert to screen-space Y.
    local cx0, cy0
    if m._getCenterXY then
        cx0, cy0 = m._getCenterXY()
    end
    if not cx0 then
        -- Fallback: read from frame (only if not hovered/expanded)
        local mL, mT = m:GetLeft(), m:GetTop()
        if not mL or not mT then return end
        cx0 = mL + m:GetWidth() / 2
        cy0 = mT - m:GetHeight() / 2  -- screen-space Y
    else
        cy0 = cy0 + UIParent:GetHeight()  -- convert TOPLEFT-Y to screen-space Y
    end

    local screenW = UIParent:GetWidth()
    local screenH = UIParent:GetHeight()
    -- Use base element half-size for clamping (not expanded hover size).
    -- elem.getSize gives the real element dimensions; fall back to frame size.
    local baseHW, baseHH
    do
        local el = registeredElements[m._barKey]
        local ew, eh
        if el and el.getSize then ew, eh = el.getSize(m._barKey) end
        if not ew or ew < 1 then ew = GetBarFrame(m._barKey) and GetBarFrame(m._barKey):GetWidth() or m:GetWidth() end
        if not eh or eh < 1 then eh = GetBarFrame(m._barKey) and GetBarFrame(m._barKey):GetHeight() or m:GetHeight() end
        baseHW = ew / 2
        baseHH = eh / 2
    end
    local rawCX = cx0 + dx
    local rawCY = cy0 + dy  -- screen-space Y (0 = bottom)
    local clampCX = max(baseHW, min(screenW - baseHW, rawCX))
    local clampCY = max(baseHH, min(screenH - baseHH, rawCY))
    -- Store updated center
    local newCY_topleft = clampCY - UIParent:GetHeight()  -- back to TOPLEFT-Y space
    if m._setCenterXY then m._setCenterXY(clampCX, newCY_topleft) end
    -- Position mover by CENTER anchor so hover-expand stays symmetric
    m:ClearAllPoints()
    m:SetPoint("CENTER", UIParent, "TOPLEFT", clampCX, newCY_topleft)
    local newX = clampCX - baseHW
    local newY = newCY_topleft + baseHH

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

        pendingPositions[m._barKey] = {
            point = "TOPLEFT", relPoint = "TOPLEFT",
            x = newX * ratio, y = newY * ratio,
        }
        hasChanges = true
    end

    -- Update anchor offset if this element is anchored to something
    local ai = GetAnchorInfo(m._barKey)
    if ai and ai.target then
        local targetBar = GetBarFrame(ai.target)
        if targetBar then
            local uiS = UIParent:GetEffectiveScale()
            local tS = targetBar:GetEffectiveScale()
            local tL = (targetBar:GetLeft() or 0) * tS / uiS
            local tR = (targetBar:GetRight() or 0) * tS / uiS
            local tT = (targetBar:GetTop() or 0) * tS / uiS
            local tB = (targetBar:GetBottom() or 0) * tS / uiS
            local tCX = (tL + tR) / 2
            local tCY = (tT + tB) / 2
            -- Store offset as edge-to-edge (child near edge to target edge)
            local sd = ai.side
            if sd == "LEFT" then
                ai.offsetX = (clampCX + baseHW) - tL
                ai.offsetY = clampCY - tCY
            elseif sd == "RIGHT" then
                ai.offsetX = (clampCX - baseHW) - tR
                ai.offsetY = clampCY - tCY
            elseif sd == "TOP" then
                ai.offsetX = clampCX - tCX
                ai.offsetY = (clampCY - baseHH) - tT
            elseif sd == "BOTTOM" then
                ai.offsetX = clampCX - tCX
                ai.offsetY = (clampCY + baseHH) - tB
            else
                ai.offsetX = clampCX - tCX
                ai.offsetY = clampCY - tCY
            end
        end
    end

    -- Update coordinate readout after nudge
    if m.UpdateCoordText then m:UpdateCoordText() end

    -- Anchor chain: propagate recursively down the chain
    PropagateAnchorChain(m._barKey)

    -- Collapse the mover while nudging so the expanded overlay doesn't
    -- obscure the element's movement. Re-expand on next mouse movement
    -- if the cursor is still over the mover.
    if m._forceCollapse then m._forceCollapse() end
    m._nudgeCollapsed = true
end

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
        -- Shift+arrow = 100px jump
        if IsShiftKeyDown() then
            NudgeMover(dir[1] * 100, dir[2] * 100)
        else
            NudgeMover(dir[1], dir[2])
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
    local MOVER_BASE_LEVEL = unlockFrame:GetFrameLevel() + 20
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
    nameFS:SetFont(FONT_PATH, 10, "")
    nameFS:SetShadowOffset(1, -1)
    nameFS:SetShadowColor(0, 0, 0, 0.8)
    nameFS:SetText(label)
    nameFS:SetTextColor(1, 1, 1, 0.75)
    nameFS:SetWordWrap(false)
    nameFS:SetNonSpaceWrap(false)
    nameFS:SetPoint("CENTER", mover, "CENTER")
    mover._label = nameFS
    if not darkOverlaysEnabled then nameFS:Hide() end

    -- Coordinate readout (shows during drag and selection, top-left of mover)
    local coordFS = labelFrame:CreateFontString(nil, "OVERLAY")
    coordFS:SetFont(FONT_PATH, 9, "")
    coordFS:SetShadowOffset(1, -1)
    coordFS:SetShadowColor(0, 0, 0, 0.8)
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
    wmFS:SetFont(FONT_PATH, 9, "")
    wmFS:SetShadowOffset(1, -1)
    wmFS:SetShadowColor(0, 0, 0, 0.8)
    wmFS:SetTextColor(ar, ag, ab, 0.85)
    wmFS:SetText(WM_TEXT)
    wmFS:SetPoint("CENTER")

    local hmFS = hmBtn:CreateFontString(nil, "OVERLAY")
    hmFS:SetFont(FONT_PATH, 9, "")
    hmFS:SetShadowOffset(1, -1)
    hmFS:SetShadowColor(0, 0, 0, 0.8)
    hmFS:SetTextColor(ar, ag, ab, 0.85)
    hmFS:SetText(HM_TEXT)
    hmFS:SetPoint("CENTER")

    local atFS = atBtn:CreateFontString(nil, "OVERLAY")
    atFS:SetFont(FONT_PATH, 9, "")
    atFS:SetShadowOffset(1, -1)
    atFS:SetShadowColor(0, 0, 0, 0.8)
    atFS:SetTextColor(ar, ag, ab, 0.85)
    atFS:SetText(AT_TEXT)
    atFS:SetPoint("CENTER")

    local gdFS = gdBtn:CreateFontString(nil, "OVERLAY")
    gdFS:SetFont(FONT_PATH, 9, "")
    gdFS:SetShadowOffset(1, -1)
    gdFS:SetShadowColor(0, 0, 0, 0.8)
    gdFS:SetTextColor(ar, ag, ab, 0.85)
    gdFS:SetText(GD_TEXT)
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

    -- Grow direction is only relevant for action bars 1-8 and CDM bars
    local _GROW_KEYS = {
        MainBar = true, Bar2 = true, Bar3 = true, Bar4 = true,
        Bar5 = true, Bar6 = true, Bar7 = true, Bar8 = true,
    }
    local canGrow = _GROW_KEYS[barKey] or (barKey:sub(1, 4) == "CDM_")

    -- Layout: position action link buttons + dividers centered below name
    local function LayoutActionRow()
        local gap = 8
        if not canResize then
            if canGrow then
                local atW = atFS:GetStringWidth() or 45
                local gdW = gdFS:GetStringWidth() or 30
                local totalW = atW + gap + 1 + gap + gdW
                local startX = -totalW / 2
                atBtn:SetSize(atW + 4, 14); atBtn:ClearAllPoints()
                atBtn:SetPoint("TOP", nameFS, "BOTTOM", startX + atW / 2, -4)
                div3:ClearAllPoints()
                div3:SetPoint("TOP", nameFS, "BOTTOM", startX + atW + gap + 0.5, -6)
                gdBtn:SetSize(gdW + 4, 14); gdBtn:ClearAllPoints()
                gdBtn:SetPoint("TOP", nameFS, "BOTTOM", startX + atW + gap + 1 + gap + gdW / 2, -4)
            else
                local atW = atFS:GetStringWidth() or 45
                atBtn:SetSize(atW + 4, 14); atBtn:ClearAllPoints()
                atBtn:SetPoint("TOP", nameFS, "BOTTOM", 0, -4)
            end
            return
        end
        local wmW = wmFS:GetStringWidth() or 50
        local hmW = hmFS:GetStringWidth() or 55
        local atW = atFS:GetStringWidth() or 45
        if canGrow then
            local gdW = gdFS:GetStringWidth() or 30
            local totalW = wmW + gap + 1 + gap + hmW + gap + 1 + gap + atW + gap + 1 + gap + gdW
            local startX = -totalW / 2
            wmBtn:SetSize(wmW + 4, 14); wmBtn:ClearAllPoints()
            wmBtn:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW / 2, -4)
            div1:ClearAllPoints()
            div1:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + gap + 0.5, -6)
            hmBtn:SetSize(hmW + 4, 14); hmBtn:ClearAllPoints()
            hmBtn:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + gap + 1 + gap + hmW / 2, -4)
            div2:ClearAllPoints()
            div2:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + gap + 1 + gap + hmW + gap + 0.5, -6)
            atBtn:SetSize(atW + 4, 14); atBtn:ClearAllPoints()
            atBtn:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + gap + 1 + gap + hmW + gap + 1 + gap + atW / 2, -4)
            div3:ClearAllPoints()
            div3:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + gap + 1 + gap + hmW + gap + 1 + gap + atW + gap + 0.5, -6)
            gdBtn:SetSize(gdW + 4, 14); gdBtn:ClearAllPoints()
            gdBtn:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + gap + 1 + gap + hmW + gap + 1 + gap + atW + gap + 1 + gap + gdW / 2, -4)
        else
            local totalW = wmW + gap + 1 + gap + hmW + gap + 1 + gap + atW
            local startX = -totalW / 2
            wmBtn:SetSize(wmW + 4, 14); wmBtn:ClearAllPoints()
            wmBtn:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW / 2, -4)
            div1:ClearAllPoints()
            div1:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + gap + 0.5, -6)
            hmBtn:SetSize(hmW + 4, 14); hmBtn:ClearAllPoints()
            hmBtn:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + gap + 1 + gap + hmW / 2, -4)
            div2:ClearAllPoints()
            div2:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + gap + 1 + gap + hmW + gap + 0.5, -6)
            atBtn:SetSize(atW + 4, 14); atBtn:ClearAllPoints()
            atBtn:SetPoint("TOP", nameFS, "BOTTOM", startX + wmW + gap + 1 + gap + hmW + gap + 1 + gap + atW / 2, -4)
        end
    end

    -- Anchored indicator: name label turns orange when anchored
    -- No separate font string needed
    local anchoredFS = nil
    mover._anchoredFS = nil

    -- Pick mode instruction text (shown when in pick mode, replaces all other text)
    local pickFS = labelFrame:CreateFontString(nil, "OVERLAY")
    pickFS:SetFont(FONT_PATH, 10, "")
    pickFS:SetShadowOffset(1, -1)
    pickFS:SetShadowColor(0, 0, 0, 0.8)
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
            -- Update size from bar
            local w = (b:GetWidth() or 50) * elemScale
            local h = (b:GetHeight() or 50) * elemScale
            if w > 10 then baseW = w end
            if h > 10 then baseH = h end
            self2:SetSize(baseW, baseH)
            -- Recompute moverCX/moverCY from bar's current center
            local bcx, bcy = b:GetCenter()
            if bcx and bcy then
                moverCX = bcx * elemScale
                moverCY = bcy * elemScale - UIParent:GetHeight()
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
            wmFS:SetText("W Matched")
            wmFS:SetTextColor(1, 0.7, 0.3, 0.85)
        elseif wmBlocked then
            wmFS:SetText("W Match")
            wmFS:SetTextColor(ar, ag, ab, 0.35)
        else
            wmFS:SetText("W Match")
            wmFS:SetTextColor(ar, ag, ab, 0.85)
        end
        if hm then
            hmFS:SetText("H Matched")
            hmFS:SetTextColor(1, 0.7, 0.3, 0.85)
        elseif hmBlocked then
            hmFS:SetText("H Match")
            hmFS:SetTextColor(ar, ag, ab, 0.35)
        else
            hmFS:SetText("H Match")
            hmFS:SetTextColor(ar, ag, ab, 0.85)
        end
        if ai then
            atFS:SetText("Anchored")
            atFS:SetTextColor(1, 0.7, 0.3, 0.85)
        else
            atFS:SetText("Anchor")
            atFS:SetTextColor(ar, ag, ab, 0.85)
        end
        local gd = GetBarGrowDir(barKey)
        if ai then
            -- Anchored: grow is disabled
            gdFS:SetText("Grow")
            gdFS:SetTextColor(ar, ag, ab, 0.35)
        elseif gd then
            gdFS:SetText("Grow")
            gdFS:SetTextColor(1, 0.7, 0.3, 0.85)
        else
            gdFS:SetText("Grow")
            gdFS:SetTextColor(ar, ag, ab, 0.85)
        end
    end

    -- Update the name label color based on anchor state
    local function RefreshAnchoredIdle()
        local ai = GetAnchorInfo(barKey)
        isAnchored = ai ~= nil
        nameFS:SetText(label)
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

        -- Action links: show on hover
        if canResize then
            wmBtn:SetAlpha(s); hmBtn:SetAlpha(s)
            div1:SetAlpha(s); div2:SetAlpha(s)
            if s > 0.01 then
                wmBtn:Show(); hmBtn:Show(); div1:Show(); div2:Show()
            else
                wmBtn:Hide(); hmBtn:Hide(); div1:Hide(); div2:Hide()
            end
        else
            wmBtn:Hide(); hmBtn:Hide(); div1:Hide(); div2:Hide()
        end
        atBtn:SetAlpha(s)
        if s > 0.01 then atBtn:Show() else atBtn:Hide() end
        if canGrow then
            gdBtn:SetAlpha(s); div3:SetAlpha(s)
            if s > 0.01 then gdBtn:Show(); div3:Show() else gdBtn:Hide(); div3:Hide() end
        else
            gdBtn:Hide(); div3:Hide()
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
            if canResize then
                local wmW = wmFS:GetStringWidth() or 50
                local hmW = hmFS:GetStringWidth() or 55
                local atW = atFS:GetStringWidth() or 45
                local gdW = gdFS:GetStringWidth() or 30
                local gap = 8
                if canGrow then
                    rowW = wmW + gap + 1 + gap + hmW + gap + 1 + gap + atW + gap + 1 + gap + gdW
                else
                    rowW = wmW + gap + 1 + gap + hmW + gap + 1 + gap + atW
                end
            else
                local atW = atFS:GetStringWidth() or 45
                local gdW = gdFS:GetStringWidth() or 30
                local gap = 8
                if canGrow then
                    rowW = atW + gap + 1 + gap + gdW
                else
                    rowW = atW
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
        pickFS:SetText(text)
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
            if GetAnchorInfo(barKey) then
                EllesmereUI.ShowWidgetTooltip(btn, "Anchored elements auto match their growth to their anchored direction")
                return
            elseif gd then
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
            isActive = GetBarGrowDir(barKey) ~= nil
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
        -- Anchored elements cannot set a grow direction
        if GetAnchorInfo(barKey) then
            EllesmereUI.ShowWidgetTooltip(gdBtn, "Anchored elements auto match their growth to their anchored direction")
            return
        end
        -- If already active, clicking again clears it
        if GetBarGrowDir(barKey) then
            hasChanges = true

            -- Capture center before changing grow direction
            local barFrame = GetBarFrame(barKey)
            local preCX, preCY
            if barFrame then
                preCX, preCY = barFrame:GetCenter()
            end

            -- Reset the bar's actual grow direction to default
            if barKey:sub(1, 4) == "CDM_" then
                local rawKey = barKey:sub(5)
                local cdm = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
                local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
                if cdmBars and cdmBars.bars then
                    for _, bar in ipairs(cdmBars.bars) do
                        if bar.key == rawKey then
                            bar.growDirection = "RIGHT"
                            break
                        end
                    end
                end
                if EllesmereUI.LayoutCDMBar then
                    EllesmereUI.LayoutCDMBar(rawKey)
                end
            else
                local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
                if eab and eab.SetGrowDirectionForBar then
                    eab:SetGrowDirectionForBar(barKey, "up")
                end
            end

            -- Restore visual center so bar doesn't jump
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
                local pt2, relTo2, relPt2, offX2, offY2 = barFrame:GetPoint(1)
                if pt2 then
                    SaveBarPosition(barKey, pt2, relPt2, offX2, offY2)
                end
            end

            if movers[barKey] and movers[barKey].Sync then
                movers[barKey]:Sync()
            end

            RefreshLinkStates()
            return
        end
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
        titleFS:SetFont(FONT_PATH, 10, "")
        titleFS:SetShadowOffset(1, -1)
        titleFS:SetShadowColor(0, 0, 0, 0.8)
        titleFS:SetTextColor(1, 1, 1, 0.40)
        titleFS:SetJustifyH("LEFT")
        titleFS:SetPoint("TOPLEFT", growDropdownFrame, "TOPLEFT", 10, ddY - 4)
        titleFS:SetText("Grow Direction")
        ddY = ddY - 18
        local titleDiv = growDropdownFrame:CreateTexture(nil, "ARTWORK")
        titleDiv:SetHeight(1)
        titleDiv:SetColorTexture(1, 1, 1, 0.10)
        titleDiv:SetPoint("TOPLEFT", growDropdownFrame, "TOPLEFT", 1, ddY - 2)
        titleDiv:SetPoint("TOPRIGHT", growDropdownFrame, "TOPRIGHT", -1, ddY - 2)
        ddY = ddY - 5

        -- Resolve orientation: CDM bars use verticalOrientation bool, action bars use orientation string
        local isVertical = false
        if barKey:sub(1, 4) == "CDM_" then
            local cdm = EllesmereUI.Lite.GetAddon("EllesmereUICooldownManager", true)
            local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
            local rawKey = barKey:sub(5)
            if cdmBars and cdmBars.bars then
                for _, bar in ipairs(cdmBars.bars) do
                    if bar.key == rawKey then
                        isVertical = bar.verticalOrientation == true
                        break
                    end
                end
            end
        else
            local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
            local s = eab and eab.db and eab.db.profile and eab.db.profile.bars and eab.db.profile.bars[barKey]
            if s then isVertical = (s.orientation == "vertical") end
        end

        local growDirs = {
            { label = "Grow Centered", val = "CENTER" },
            { label = "Grow Left",     val = "LEFT"   },
            { label = "Grow Right",    val = "RIGHT"  },
            { label = "Grow Up",       val = "UP"     },
            { label = "Grow Down",     val = "DOWN"   },
        }
        local currentVal = GetBarGrowDir(barKey) or "CENTER"

        for _, entry in ipairs(growDirs) do
            -- Disable directions that don't match the bar's orientation.
            -- CENTER is always disabled (it's the default when no direction is set).
            local isDisabled = false
            if entry.val == "CENTER" then
                isDisabled = false
            elseif isVertical then
                isDisabled = (entry.val == "LEFT" or entry.val == "RIGHT")
            else
                isDisabled = (entry.val == "UP" or entry.val == "DOWN")
            end
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
            lbl:SetFont(FONT_PATH, 11, "")
            lbl:SetShadowOffset(1, -1)
            lbl:SetShadowColor(0, 0, 0, 0.8)
            lbl:SetJustifyH("LEFT")
            lbl:SetPoint("LEFT", item, "LEFT", 10, 0)
            lbl:SetText(entry.label)
            if isDisabled then
                lbl:SetTextColor(0.4, 0.4, 0.4, 0.5)
                local tipText
                if entry.val == "CENTER" then
                    tipText = "Deselect a grow direction to return to centered"
                elseif isVertical then
                    tipText = "Vertical bars can only grow up or down"
                else
                    tipText = "Horizontal bars can only grow left or right"
                end
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

                    -- If already on centered, just close the popup
                    if sideVal == "CENTER" and currentVal == "CENTER" then return end

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
                    else
                        local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
                        if eab and eab.SetGrowDirectionForBar then
                            eab:SetGrowDirectionForBar(barKey, sideVal)
                        end
                    end

                    -- Restore the bar's visual center so it doesn't jump
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
                        -- Re-save position from the corrected frame location
                        local pt2, relTo2, relPt2, offX2, offY2 = barFrame:GetPoint(1)
                        if pt2 then
                            SaveBarPosition(barKey, pt2, relPt2, offX2, offY2)
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

    -- Initialize anchored text and link states, then apply idle state
    RefreshAnchoredIdle()
    RefreshLinkStates()
    ApplyHoverState(0)

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
        local floor = math.floor
        if elem and elem.getSize then
            local gw, gh = elem.getSize(bk)
            if gw and gw > 0 then baseW = floor(gw + 0.5) end
            if gh and gh > 0 then baseH = floor(gh + 0.5) end
        else
            local b = GetBarFrame(bk)
            if b then
                local s = b:GetEffectiveScale()
                local uiS = UIParent:GetEffectiveScale()
                baseW = floor(((b:GetWidth() or baseW) * s / uiS) + 0.5)
                baseH = floor(((b:GetHeight() or baseH) * s / uiS) + 0.5)
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
        local halfW0 = round(self:GetWidth() / 2)
        local halfH0 = round(self:GetHeight() / 2)
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

            -- Show live coordinates during drag (only on elements >= 20px tall)
            if s._coordFS and s:GetHeight() >= 20 then
                s._coordFS:SetText(format("%.0f, %.0f", round(snapCX - screenW * 0.5), round(snapCY - screenH * 0.5)))
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
                local bS = bar:GetEffectiveScale()
                local ratio = uiS / bS
                local barHW = (bar:GetWidth() or 0) * 0.5
                local barHH = (bar:GetHeight() or 0) * 0.5
                local barX = cx * ratio - barHW
                local barY = (cy - UIParent:GetHeight() - dragCYOff) * ratio + barHH
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
                    -- Store offset as edge-to-edge (child near edge to target edge)
                    local halfW = baseW > 0 and baseW / 2 or (self:GetWidth() / 2)
                    local halfH = baseH > 0 and baseH / 2 or (self:GetHeight() / 2)
                    local sd = ai.side
                    if sd == "LEFT" then
                        ai.offsetX = (cx + halfW) - tL
                        ai.offsetY = cy - tCY
                    elseif sd == "RIGHT" then
                        ai.offsetX = (cx - halfW) - tR
                        ai.offsetY = cy - tCY
                    elseif sd == "TOP" then
                        ai.offsetX = cx - tCX
                        ai.offsetY = (cy - halfH) - tT
                    elseif sd == "BOTTOM" then
                        ai.offsetX = cx - tCX
                        ai.offsetY = (cy + halfH) - tB
                    else
                        ai.offsetX = cx - tCX
                        ai.offsetY = cy - tCY
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
            if not self._selected then
                if not darkOverlaysEnabled then self:SetAlpha(MOVER_ALPHA) end
                self._brd:SetColor(ar, ag, ab, 0.6)
            end
            -- Delay so hovering child buttons doesn't flicker
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
                if not self._selected then
                    self:SetFrameLevel(self._baseLevel)
                    if self._hideOverlayText then self._hideOverlayText() end
                    if hoveredMover == self then hoveredMover = nil end
                else
                    -- Selected mover stays expanded, just clear hoveredMover
                    if hoveredMover == self then hoveredMover = nil end
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
                    -- Get target width and apply to source, store persistent link
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
                            local sb = GetBarFrame(sourceKey)
                            local savedAlpha = sb and sb._euiRestoreAlpha
                            -- Hide bar for one frame so the TOPLEFT->CENTER re-anchor
                            -- is invisible. Restore alpha after RecenterBarAnchor runs.
                            if sb and not savedAlpha then sb:SetAlpha(0) end
                            sourceElem.setWidth(sourceKey, targetW)
                            MatchH.SetWidthMatch(sourceKey, targetKey)
                            hasChanges = true
                            EllesmereUI.RecenterBarAnchor(sourceKey)
                            if sb and not savedAlpha then
                                C_Timer.After(0, function() sb:SetAlpha(1) end)
                            end
                        end
                    end
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
                    -- Get target height and apply to source, store persistent link
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
                            local sb = GetBarFrame(sourceKey)
                            local savedAlpha = sb and sb._euiRestoreAlpha
                            if sb and not savedAlpha then sb:SetAlpha(0) end
                            sourceElem.setHeight(sourceKey, targetH)
                            MatchH.SetHeightMatch(sourceKey, targetKey)
                            hasChanges = true
                            EllesmereUI.RecenterBarAnchor(sourceKey)
                            if sb and not savedAlpha then
                                C_Timer.After(0, function() sb:SetAlpha(1) end)
                            end
                        end
                    end
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
                            -- Propagate to children so they follow immediately
                            PropagateAnchorChain(pmKey)
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

        -- "Element Options" — navigate to this element's settings page (top of menu)
        local settingsMapping = EllesmereUI._ELEMENT_SETTINGS_MAP[barKey]
        if settingsMapping then
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
            optLbl:SetFont(FONT_PATH, 11, "")
            optLbl:SetShadowOffset(1, -1)
            optLbl:SetShadowColor(0, 0, 0, 0.8)
            optLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            optLbl:SetJustifyH("LEFT")
            optLbl:SetPoint("LEFT", optItem, "LEFT", 10, 0)
            optLbl:SetText("Element Options")
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
                ns.RequestClose(true, function()
                    EllesmereUI:NavigateToElementSettings(
                        settingsMapping.module,
                        settingsMapping.page,
                        settingsMapping.sectionName,
                        settingsMapping.preSelectFn,
                        settingsMapping.highlightText
                    )
                end)
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
                lbl:SetFont(FONT_PATH, 11, "")
                lbl:SetShadowOffset(1, -1)
                lbl:SetShadowColor(0, 0, 0, 0.8)
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
                box:SetNumber(floor(initVal))
                box:SetScript("OnEnterPressed", function(self)
                    local val = self:GetNumber()
                    if val < 1 then val = 1 end
                    local sb = GetBarFrame(barKey)
                    local savedAlpha = sb and sb._euiRestoreAlpha
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
                        if wBox then wBox:SetNumber(floor(nw or 0)) end
                        if hBox then hBox:SetNumber(floor(nh or 0)) end
                    end
                    PropagateAnchorChain(barKey)
                end)
                box:SetScript("OnEscapePressed", function(self)
                    self:ClearFocus()
                    if elem.getSize then
                        local w2, h2 = elem.getSize(barKey)
                        self:SetNumber(floor(axis == "Width" and (w2 or 0) or (h2 or 0)))
                    end
                end)
                yOff = yOff - ROW_H
                return box
            end

            wBox = MakeSizeRow("Width",  curW)
            hBox = MakeSizeRow("Height", curH)

            -- X Position / Y Position rows (screen coords from center)
            do
                local sw = UIParent:GetWidth()
                local sh = UIParent:GetHeight()
                local initX, initY = 0, 0
                local b0 = GetBarFrame(barKey)
                if b0 then
                    local bL, bR = b0:GetLeft(), b0:GetRight()
                    local bT, bB = b0:GetTop(), b0:GetBottom()
                    if bL and bR and bT and bB then
                        local ratio0 = b0:GetEffectiveScale() / UIParent:GetEffectiveScale()
                        initX = round(((bL + bR) * 0.5 * ratio0) - sw * 0.5)
                        initY = round(((bT + bB) * 0.5 * ratio0) - sh * 0.5)
                    end
                end

                local function MakePosRow(axis, initVal)
                    local rowFrame = CreateFrame("Frame", nil, cogMenu)
                    rowFrame:SetHeight(ROW_H)
                    rowFrame:SetPoint("TOPLEFT", cogMenu, "TOPLEFT", 1, yOff)
                    rowFrame:SetPoint("TOPRIGHT", cogMenu, "TOPRIGHT", -1, yOff)
                    rowFrame:SetFrameLevel(cogMenu:GetFrameLevel() + 2)

                    local lbl = rowFrame:CreateFontString(nil, "OVERLAY")
                    lbl:SetFont(FONT_PATH, 11, "")
                    lbl:SetShadowOffset(1, -1)
                    lbl:SetShadowColor(0, 0, 0, 0.8)
                    lbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    lbl:SetJustifyH("LEFT")
                    lbl:SetPoint("LEFT", rowFrame, "LEFT", 10, 0)
                    lbl:SetText(axis == "X" and "X Position" or "Y Position")

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
                        local val = tonumber(self:GetText()) or 0
                        self:ClearFocus()
                        local screenW = UIParent:GetWidth()
                        local screenH = UIParent:GetHeight()
                        -- moverCX/moverCY are UIParent-TOPLEFT; convert to screen-center
                        local curSX = moverCX - screenW * 0.5
                        local curSY = moverCY + screenH * 0.5
                        local newSX = (axis == "X") and val or curSX
                        local newSY = (axis == "Y") and val or curSY
                        -- Back to UIParent-TOPLEFT center
                        local newCX = newSX + screenW * 0.5
                        local newCY = newSY - screenH * 0.5
                        -- Move bar
                        local b = GetBarFrame(barKey)
                        if b and not InCombatLockdown() then
                            local ratio = UIParent:GetEffectiveScale() / b:GetEffectiveScale()
                            local barHW = (b:GetWidth() or 0) * 0.5
                            local barHH = (b:GetHeight() or 0) * 0.5
                            local barX = newCX * ratio - barHW
                            local barY = newCY * ratio + barHH
                            pcall(function()
                                b:ClearAllPoints()
                                b:SetPoint("TOPLEFT", UIParent, "TOPLEFT", barX, barY)
                            end)
                            pendingPositions[barKey] = {
                                point = "TOPLEFT", relPoint = "TOPLEFT",
                                x = barX, y = barY,
                            }
                        end
                        -- Update mover
                        moverCX, moverCY = newCX, newCY
                        local hw = (baseW > 0 and baseW or mover:GetWidth()) * 0.5
                        local hh = (baseH > 0 and baseH or mover:GetHeight()) * 0.5
                        mover:ClearAllPoints()
                        mover:SetPoint("TOPLEFT", UIParent, "TOPLEFT", newCX - hw, newCY + hh)
                        hasChanges = true
                        PropagateAnchorChain(barKey)
                        mover:ReanchorToBar()
                    end)
                    box:SetScript("OnEscapePressed", function(self)
                        self:ClearFocus()
                        self:SetText(tostring(initVal))
                    end)
                    yOff = yOff - ROW_H
                end

                MakePosRow("X", initX)
                MakePosRow("Y", initY)
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
        selElemLbl:SetFont(FONT_PATH, 11, "")
        selElemLbl:SetShadowOffset(1, -1)
        selElemLbl:SetShadowColor(0, 0, 0, 0.8)
        selElemLbl:SetTextColor(isSelElem and 1 or 0.75, isSelElem and 1 or 0.75, isSelElem and 1 or 0.75, 0.9)
        selElemLbl:SetJustifyH("LEFT")
        selElemLbl:SetPoint("LEFT", selElemItem, "LEFT", 10, 0)
        selElemLbl:SetText("Snap Target: Select Element")
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
        snapLbl:SetFont(FONT_PATH, 11, "")
        snapLbl:SetShadowOffset(1, -1)
        snapLbl:SetShadowColor(0, 0, 0, 0.8)
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
                sLbl:SetFont(FONT_PATH, 11, "")
                sLbl:SetShadowOffset(1, -1)
                sLbl:SetShadowColor(0, 0, 0, 0.8)
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
            local sDivPx = PP and PP.mult or 1
            sDiv:SetHeight(sDivPx)
            if sDiv.SetSnapToPixelGrid then sDiv:SetSnapToPixelGrid(false); sDiv:SetTexelSnappingBias(0) end
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
                crLbl:SetFont(FONT_PATH, 11, "")
                crLbl:SetShadowOffset(1, -1)
                crLbl:SetShadowColor(0, 0, 0, 0.8)
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
                        cLbl:SetFont(FONT_PATH, 11, "")
                        cLbl:SetShadowOffset(1, -1)
                        cLbl:SetShadowColor(0, 0, 0, 0.8)
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
                        C_Timer.After(0.05, function()
                            if self:IsShown() and not self:IsMouseOver() and not crItem:IsMouseOver() then
                                self:Hide()
                            end
                        end)
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
                    C_Timer.After(0.05, function()
                        local crs = cogRegSubMenus[gName]
                        if crs and crs:IsShown() and not crs:IsMouseOver() and not crItem:IsMouseOver() then
                            crs:Hide()
                        end
                    end)
                end)
            end
            cogSnapMenu:SetHeight(-sYOff + 4)
            cogSnapMenu:EnableMouse(true)
            cogSnapMenu:SetScript("OnLeave", function(self)
                C_Timer.After(0.05, function()
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
        local divPx = PP and PP.mult or 1
        div:SetHeight(divPx)
        if div.SetSnapToPixelGrid then div:SetSnapToPixelGrid(false); div:SetTexelSnappingBias(0) end
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
            lbl:SetFont(FONT_PATH, 11, "")
            lbl:SetShadowOffset(1, -1)
            lbl:SetShadowColor(0, 0, 0, 0.8)
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

    movers[barKey] = mover
    return mover
end

-- Override RegisterUnlockElements so that late-registering addons (e.g. CDM
-- registering after a 0.5s timer) get movers spawned immediately if unlock
-- mode is already open when they call in.
do
    local _origRegister = EllesmereUI.RegisterUnlockElements
    function EllesmereUI:RegisterUnlockElements(elements)
        _origRegister(self, elements)
        if not isUnlocked then return end
        -- Unlock mode is open -- spawn movers for any newly registered keys
        local spawned = false
        for _, elem in ipairs(elements) do
            local key = elem.key
            if not movers[key] then
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

    hudFrame = CreateFrame("Frame", nil, parent)
    hudFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    hudFrame:SetFrameLevel(500)
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
    -- Revert action bar scale is no longer needed (scale removed)
    -- Revert registered elements via their savePosition callback
    for barKey, _ in pairs(pendingPositions) do
        local elem = registeredElements[barKey]
        if elem and elem.savePosition then
            local snap = snapshotPositions[barKey]
            if snap and not snap._fromLiveFrame then
                elem.savePosition(barKey, snap.point, snap.relPoint or snap.point, snap.x, snap.y)
            end
        end
    end
    -- Move all frames back to their original positions
    for barKey, _ in pairs(pendingPositions) do
        local bar = GetBarFrame(barKey)
        if bar then
            local snap = snapshotPositions[barKey]
            if snap then
                -- Use centralized apply for CENTER positions
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

    -- Revert anchor data to snapshot state
    local anchorDB = GetAnchorDB()
    if anchorDB then
        wipe(anchorDB)
        for childKey, info in pairs(snapshotAnchors) do
            anchorDB[childKey] = { target = info.target, side = info.side, offsetX = info.offsetX, offsetY = info.offsetY }
        end
    end

    -- Revert element sizes to snapshot state
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

    -- Revert width/height match DBs to snapshot state
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
end

-- Internal close (actually hides everything and returns to options)
local function DoClose()
    if not isUnlocked then return end
    isUnlocked = false
    EllesmereUI._unlockActive = false
    EllesmereUI._unlockModeActive = false

    -- Notify beacon reminders to restore (if follow-mouse is active)
    if _G._EABR_BeaconRefresh then pcall(_G._EABR_BeaconRefresh) end

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
    if EllesmereUI.NeedsBetaReset and EllesmereUI.NeedsBetaReset() then
        if EllesmereUI.ShowWelcomePopup then EllesmereUI:ShowWelcomePopup() end
        return
    end
    isUnlocked = true
    EllesmereUI._unlockActive = true
    EllesmereUI._unlockModeActive = true

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

    -- Hide objective tracker (alpha only -- no :Hide() to avoid taint)
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
            for _, m in pairs(movers) do
                if m:IsShown() then
                    local moverT = glitchT - MOVER_DELAY
                    if moverT > 0 then
                        -- Re-sync once right as movers begin fading in so any
                        -- frames that were nil at initial sync are now ready.
                        if not fadeInSynced then
                            fadeInSynced = true
                            for _, rm in pairs(movers) do rm:Sync() end
                        end
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

        -- Start anchor connector line updates now that movers are visible
        if unlockFrame._anchorLineDriver then
            unlockFrame._anchorLineDriver:Show()
        end
        if unlockFrame._anchorLineFrame then
            unlockFrame._anchorLineFrame:Show()
        end

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

    -- Notify beacon reminders to hide
    if _G._EABR_BeaconRefresh then pcall(_G._EABR_BeaconRefresh) end

    -- Re-show unlock UI
    if arrowKeyFrame then arrowKeyFrame:Show() end
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
