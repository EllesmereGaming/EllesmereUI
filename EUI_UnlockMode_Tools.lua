if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_UnlockMode_Tools.lua
--  Unlock Mode tools: accent color, grid overlay, alignment guides, snap,
--  selection and arrow-key nudge, action bar visual size, mover overlay
--  helpers, Blizzard-owned info overlays.
--  Loaded after EUI_UnlockMode.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, EUI_NS = ...
EUI_NS = EUI_NS.__euiCoreNS or EUI_NS  -- standalone builds: the core's own table (EllesmereUI.lua)
EUI_NS.unlockParts = EUI_NS.unlockParts or {}
EUI_NS.unlockParts.Tools = function(UM)
local ns, EAB, floor, abs = EUI_NS, UM.EAB, UM.floor, UM.abs
local min, max, sqrt, sin = UM.min, UM.max, UM.sqrt, UM.sin
local PP, FONT_PATH, GRID_SPACING, SNAP_THRESH = UM.PP, UM.FONT_PATH, UM.GRID_SPACING, UM.SNAP_THRESH
local MOVER_ALPHA, MOVER_HOVER, BAR_LOOKUP, registeredElements = UM.MOVER_ALPHA, UM.MOVER_HOVER, UM.BAR_LOOKUP, UM.registeredElements
local guidePool, movers, pendingPositions, GridBaseAlpha = UM.guidePool, UM.movers, UM.pendingPositions, UM.GridBaseAlpha
local GridCenterAlpha, _blizzOwnedOverlays, GetAnchorDB, GetAnchorInfo = UM.GridCenterAlpha, UM._blizzOwnedOverlays, UM.GetAnchorDB, UM.GetAnchorInfo
local FadeOverlayForSelectElement, CancelPickMode, LoadBarPosition = UM.FadeOverlayForSelectElement, UM.CancelPickMode, UM.LoadBarPosition

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
    if UM.gridFrame then return UM.gridFrame end
    -- Grid lives on its own BACKGROUND-strata frame so it renders BEHIND the
    -- real game UI elements (action bars, unit frames).
    UM.gridFrame = CreateFrame("Frame", nil, UIParent)
    UM.gridFrame:SetFrameStrata("BACKGROUND")
    UM.gridFrame:SetAllPoints(UIParent)
    UM.gridFrame:SetFrameLevel(1)
    UM.gridFrame._lines = {}

    function UM.gridFrame:Rebuild()
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

        -- White crosshair pip at dead center (short lines forming a +), always
        -- 50% alpha regardless of grid brightness mode
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

    local origRebuild = UM.gridFrame.Rebuild
    function UM.gridFrame:Rebuild()
        origRebuild(self)
        cachedAR, cachedAG, cachedAB = GetAccent()
    end

    -- Cursor flashlight: highlights grid lines near the cursor via a radial
    -- gradient texture (soft ambient glow) plus per-line segments with 2D
    -- distance-based alpha for crisp line highlights.
    local LIGHT_RADIUS   = 220
    local LIGHT_DIAMETER = LIGHT_RADIUS * 2
    local LIGHT_BOOST    = 0.55
    local NUM_SEGS       = 5
    local FLASH_PATH = "Interface\\AddOns\\EllesmereUI\\media\\unlock-flash.png"

    -- Ambient glow texture (soft circle behind lines)
    local flashTex = UM.gridFrame:CreateTexture(nil, "BACKGROUND", nil, -8)
    flashTex:SetTexture(FLASH_PATH)
    flashTex:SetSize(LIGHT_DIAMETER, LIGHT_DIAMETER)
    flashTex:SetBlendMode("ADD")
    flashTex:SetVertexColor(1, 1, 1, 0.03)
    flashTex:Hide()

    -- Line highlight segments
    UM.gridFrame._glows = {}
    local glowIdx = 0

    local function GetGlow(idx)
        local g = UM.gridFrame._glows[idx]
        if not g then
            g = UM.gridFrame:CreateTexture(nil, "BACKGROUND", nil, -6)
            UM.gridFrame._glows[idx] = g
        end
        return g
    end

    UM.gridFrame:SetScript("OnUpdate", function(self, dt)
        if not self:IsShown() then
            flashTex:Hide()
            return
        end

        if not UM.flashlightEnabled then
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

    return UM.gridFrame
end

-------------------------------------------------------------------------------
--  Alignment guide lines (snap guides between bars)
-------------------------------------------------------------------------------
local activeGuides = {}

local function GetGuide(idx)
    if guidePool[idx] then return guidePool[idx] end
    local tex = UM.unlockFrame:CreateTexture(nil, "OVERLAY", nil, 6)
    tex:SetColorTexture(1, 1, 1, 1)
    guidePool[idx] = tex
    return tex
end

-- Snap highlight: a pulsing white border layered ON TOP of the green one. Each
-- mover gets a lazy _snapBrd (a second MakeBorder at a higher frame level) so the
-- green accent border stays visible underneath.
local snapHighlightKey = nil   -- barKey of mover currently showing snap highlight border
local snapHighlightAnim = nil  -- OnUpdate frame for the pulsing border
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
        -- Restore normal overlay brightness
        if UM.darkOverlaysEnabled and m._bg then
            m._bg:SetColorTexture(m._bgR or 0.075, m._bgG or 0.113, m._bgB or 0.141, 0.95)
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
        if UM.darkOverlaysEnabled and old._bg then
            old._bg:SetColorTexture(old._bgR or 0.075, old._bgG or 0.113, old._bgB or 0.141, 0.95)
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
    -- Brighten the mover's base color
    if UM.darkOverlaysEnabled and m._bg then
        m._bg:SetColorTexture((m._bgR or 0.075) * 1.4, (m._bgG or 0.113) * 1.4, (m._bgB or 0.141) * 1.4, 0.95)
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
    wipe(activeGuides)
end

-- Full cleanup including snap highlight (used when drag stops)
local function HideAllGuidesAndHighlight()
    HideAllGuides()
    ClearSnapHighlight()
end

-------------------------------------------------------------------------------
--  ShowAlignmentGuides: draws full-screen guide lines at snap positions.
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
--  Snap-to-element helper: 1) find the single closest mover (min edge-to-edge
--  distance, within SNAP_PROXIMITY px). 2) check 9 X-axis + 9 Y-axis pairs against
--  that one mover. Populates lastSnapInfo for ShowAlignmentGuides to read.
-------------------------------------------------------------------------------

local function SnapPosition(dragKey, cx, cy, halfW, halfH)
    wipe(lastSnapInfo)
    if not UM.snapEnabled then return cx, cy end

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
        -- Exclude from snap: all descendants (children, grandchildren, etc.) and
        -- siblings (anchored to the same parent). The direct parent IS allowed.
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
    -- Selecting a mover releases any selected fallback ghost (one arrow-key
    -- target at a time)
    if EllesmereUI._DeselectFallbackGhosts then EllesmereUI._DeselectFallbackGhosts() end
    if EllesmereUI._DeselectOverrideGhosts then EllesmereUI._DeselectOverrideGhosts() end
    -- Deselect previous
    if UM.selectedMover and UM.selectedMover ~= m then
        UM.selectedMover._selected = false
        SetSelectionHighlight(UM.selectedMover, false)
        if not UM.selectedMover._dragging and not UM.selectedMover:IsMouseOver() then
            UM.selectedMover:SetFrameLevel(UM.selectedMover._baseLevel)
            if not UM.darkOverlaysEnabled then UM.selectedMover:SetAlpha(MOVER_ALPHA) end
            UM.selectedMover._brd:SetColor(ar, ag, ab, 0.6)
            -- Collapse overlay on old selection
            if UM.selectedMover._hideOverlayText then UM.selectedMover._hideOverlayText() end
        end
        -- Hide action buttons on old selection
        if UM.selectedMover._hideCogAfterDelay then UM.selectedMover._hideCogAfterDelay() end
        -- Hide coordinates on old selection (keep if coords-always-on)
        if UM.selectedMover._coordFS and not UM.coordsEnabled then UM.selectedMover._coordFS:Hide() end
    end
    UM.selectedMover = m
    if m then
        m._selected = true
        SetSelectionHighlight(m, true)
        m:SetFrameLevel(m._raisedLevel)
        if not UM.darkOverlaysEnabled then m:SetAlpha(MOVER_HOVER) end
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
    if UM.selectedMover then
        local ar, ag, ab = GetAccent()
        UM.selectedMover._selected = false
        SetSelectionHighlight(UM.selectedMover, false)
        if not UM.selectedMover._dragging then
            if not UM.selectedMover:IsMouseOver() then
                UM.selectedMover:SetFrameLevel(UM.selectedMover._baseLevel)
                if not UM.darkOverlaysEnabled then UM.selectedMover:SetAlpha(MOVER_ALPHA) end
                UM.selectedMover._brd:SetColor(ar, ag, ab, 0.6)
                if UM.selectedMover._hideOverlayText then UM.selectedMover._hideOverlayText() end
            end
        end
        -- Restore settings widgets to base level
        -- Hide coordinates (keep visible if coords-always-on mode is active)
        if UM.selectedMover._coordFS and not UM.coordsEnabled then UM.selectedMover._coordFS:Hide() end
        -- Clear snap highlight
        ClearSnapHighlight()
        -- Cancel select-element pick mode if this mover was the picker -- restore previous target
        if UM.selectElementPicker == UM.selectedMover then
            UM.selectedMover._snapTarget = UM.selectedMover._preSelectTarget
            UM.selectedMover._preSelectTarget = nil
            if UM.selectedMover._updateSnapLabel then UM.selectedMover._updateSnapLabel() end
            UM.selectElementPicker = nil
            FadeOverlayForSelectElement(false)
        end
        -- Cancel width/height/anchor pick mode if this mover was the picker
        if UM.pickModeMover == UM.selectedMover then
            CancelPickMode()
        end
    end
    UM.selectedMover = nil
    if EllesmereUI._DeselectFallbackGhosts then EllesmereUI._DeselectFallbackGhosts() end
    if EllesmereUI._DeselectOverrideGhosts then EllesmereUI._DeselectOverrideGhosts() end
end

-- Namespace bridge so the fallback ghost overlays (defined earlier in the
-- file) can release a selected mover when a ghost is clicked.
EllesmereUI._DeselectSelectedMover = DeselectMover

-- Apply dark overlay state to all movers
local function ApplyDarkOverlays()
    for _, m in pairs(movers) do
        if UM.darkOverlaysEnabled then
            m._bg:SetColorTexture(m._bgR or 0.075, m._bgG or 0.113, m._bgB or 0.141, 0.95)
            if m._label then m._label:SetAlpha(1); m._label:Show() end
            if m._subtitle then m._subtitle:SetAlpha(1); m._subtitle:Show() end
            if m._coordFS then m._coordFS:SetAlpha(1) end
            -- Action row is hover-only now, don't show it here
            if not m._dragging then m:SetAlpha(1) end
        else
            m._bg:SetColorTexture(0, 0, 0, 0)
            if m._label then m._label:Hide() end
            if m._subtitle then m._subtitle:Hide() end
            -- When coords-always-on is active, show coords for all movers; otherwise hide
            if m._coordFS then
                if UM.coordsEnabled then
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
-- Attach a mover to its bar's TOPLEFT, inset by il/-it (UIParent units). An
-- element whose frame carries a forbidden layout aspect (a Blizzard Style unit
-- cast bar riding its frame's aura stack, created with Blizzard's
-- DisableUntrustedLayoutScriptsTemplate) refuses dependents that lack the
-- aspect, so its mover takes the same screen spot by absolute anchor instead
-- (elem.detachedMover); every sync and apply path re-runs this, so it keeps
-- up outside of drags.
local function AttachMoverToBar(m, bar, key, il, it)
    m:ClearAllPoints()
    local elem = registeredElements[key]
    if elem and elem.detachedMover then
        local bL, bT = bar:GetLeft(), bar:GetTop()
        if not (issecretvalue and (issecretvalue(bL) or issecretvalue(bT))) and bL and bT then
            local r = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
            m:SetPoint("TOPLEFT", UIParent, "TOPLEFT", bL * r + (il or 0), bT * r - UIParent:GetHeight() - (it or 0))
        else
            -- No readable rect yet: park at the screen centre (the bar's own
            -- anchor is the one this element refuses) until the next sync.
            m:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        return
    end
    m:SetPoint("TOPLEFT", bar, "TOPLEFT", il or 0, -(it or 0))
end
-- CreateMover is at Lua's 60-upvalue cap: its closures call this through the
-- namespace table (already an upvalue there), like NudgeMover below.
EllesmereUI._unlockAttachMover = AttachMoverToBar

local function NudgeMover(dx, dy, targetMover, skipCollapse)
    local m = targetMover or UM.selectedMover
    if not m or InCombatLockdown() then return end
    if ns.IsMoverPosLocked(m._barKey) then return end

    -- Read bar's current position, add dx/dy, reposition.
    local bar = UM.GetBarFrame(m._barKey)
    if not bar then return end

    -- An element that places itself (ownsPosition) moves like an unanchored one:
    -- its links are inert.
    local elem = registeredElements[m._barKey]
    local ai = not (elem and elem.ownsPosition) and GetAnchorInfo(m._barKey) or nil
    if ai and ai.target then
        -- Anchored: adjust offset relative to target frame (not UIParent). Reading
        -- GetPoint(1) on an anchored element returns args relative to the target frame -- applying those to UIParent teleports the bar.
        ai.offsetX = (ai.offsetX or 0) + dx
        ai.offsetY = (ai.offsetY or 0) + dy
        -- The growth-edge pin rides the same nudge on its axis.
        if ai.edgeOffX ~= nil then ai.edgeOffX = ai.edgeOffX + dx end
        if ai.edgeOffY ~= nil then ai.edgeOffY = ai.edgeOffY + dy end
        -- An axis held by the cross-axis screen edge takes the nudge there, or the
        -- next apply overwrites it from the untouched edge offset.
        if ai.edge and ai.edge.key then
            local nAxis = EllesmereUI._ScreenEdgeAxis(ai.edge.key)
            if nAxis == "X" then ai.edge.offset = (ai.edge.offset or 0) + dx
            elseif nAxis == "Y" then ai.edge.offset = (ai.edge.offset or 0) + dy end
        end
        UM.ApplyAnchorPosition(m._barKey, ai.target, ai.side)
        -- Capture the bar's resulting position so CommitPositions saves the real
        -- (nudged) location. ApplyAnchorPosition always anchors the bar to UIParent,
        -- so GetPoint(1) is UIParent-relative and safe to store. A coordless
        -- {_anchored=true} marker would make CommitPositions fall back to the
        -- pre-edit snapshot, reverting bars that read their saved edge on exit/reload.
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
            EllesmereUI.ClearFramePoints(bar)
            EllesmereUI.SetFramePoint(bar, pt, UIParent, relPt, offX + dx, offY + dy)
        end)
        -- Keep the LOGICAL pending value exact for CENTER/CENTER elements: previous
        -- pending/stored value + the exact delta, never a live geometry read-back.
        -- Odd-pixel-dimension frames apply with a half-pixel physical center, so
        -- reading the frame back here would bake that half pixel (and its rounding) into the saved value -- "nudged to -368, saves back as -369".
        local prev = pendingPositions[m._barKey]
        if type(prev) ~= "table" or prev._anchored or not prev.point then
            local elemN = registeredElements[m._barKey]
            prev = elemN and elemN.loadPosition and elemN.loadPosition(m._barKey) or nil
            if not prev then prev = LoadBarPosition(m._barKey) end
        end
        if type(prev) == "table" and prev.point == "CENTER"
           and (prev.relPoint or "CENTER") == "CENTER"
           and prev.x and prev.y then
            pendingPositions[m._barKey] = {
                point = "CENTER", relPoint = "CENTER",
                x = prev.x + dx, y = prev.y + dy,
            }
        else
            pendingPositions[m._barKey] = {
                point = pt, relPoint = relPt,
                x = offX + dx, y = offY + dy,
            }
        end
    end
    -- Same element follow-up the drag gives after each placement (main chat
    -- restores its size corner), before the mover and the anchor chain read
    -- the frame's rect.
    if elem and elem.onLiveMove then
        pcall(elem.onLiveMove, m._barKey)
    end
    UM.hasChanges = true

    -- Reanchor mover to bar, inside the element's visual insets (see Sync).
    local nIL, nIR, nIT, nIB = 0, 0, 0, 0
    if elem and elem.getInsets then
        local l, r, t, bt = elem.getInsets(m._barKey)
        if l then
            local es = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
            nIL, nIR, nIT, nIB = l * es, (r or 0) * es, (t or 0) * es, (bt or 0) * es
        end
    end
    AttachMoverToBar(m, bar, m._barKey, nIL, nIT)

    -- Update stored mover center from bar's new position
    local bL, bR = bar:GetLeft(), bar:GetRight()
    local bT, bB = bar:GetTop(), bar:GetBottom()
    if bL and bR and bT and bB then
        local s = bar:GetEffectiveScale()
        local uiS = UIParent:GetEffectiveScale()
        local ratio = s / uiS
        local cx = (bL + bR) * 0.5 * ratio + (nIL - nIR) * 0.5
        local cy = (bT + bB) * 0.5 * ratio - UIParent:GetHeight() + (nIB - nIT) * 0.5
        if m._setCenterXY then m._setCenterXY(cx, cy) end
    end

    -- Propagate to anchored children
    UM.PropagateAnchorChain(m._barKey)

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

-- Grow-direction change for a growth bar in unlock mode, the cog's Grow row in
-- one call: write the module's setting and relayout, put the bar's visual center
-- back where it was (a relayout can shift the frame around its new fixed edge),
-- re-anchor by the new growth edge and record the position for Save & Exit.
-- Shared with the anchor picker's corner rows, which set the direction AFTER
-- placing the bar flush so the growth-edge hold captures from where it sits.
-- On the namespace table like the nudge: CreateMover is at the upvalue cap.
EllesmereUI._unlockSetGrowDirection = function(barKey, val)
    UM.hasChanges = true

    -- Capture the bar's visual center before changing grow
    local barFrame = UM.GetBarFrame(barKey)
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
                    bar.growDirection = val
                    break
                end
            end
        end
        if EllesmereUI.LayoutCDMBar then
            EllesmereUI.LayoutCDMBar(rawKey)
        end
        EllesmereUI.RecenterBarAnchor(barKey)
    elseif barKey == "ERB_TotemBar" then
        local erb = EllesmereUI.Lite.GetAddon("EllesmereUIResourceBars", true)
        local tb = erb and erb.db and erb.db.profile and erb.db.profile.totemBar
        if tb then tb.growDirection = val end
        if EllesmereUI.LayoutTotemBar then EllesmereUI.LayoutTotemBar() end
        EllesmereUI.RecenterBarAnchor(barKey)
    elseif barKey == "EABR_Reminders" then
        if EllesmereUI.SetAuraBuffGrowDir then EllesmereUI.SetAuraBuffGrowDir(val) end
        EllesmereUI.RecenterBarAnchor(barKey)
    elseif barKey:sub(1, 4) == "PAB_" then
        local euf = EllesmereUI.Lite.GetAddon("EllesmereUIUnitFrames", true)
        if euf and euf.SetGrowDirectionForBar then
            euf:SetGrowDirectionForBar(barKey, val)
        end
    else
        local eab = EllesmereUI.Lite.GetAddon("EllesmereUIActionBars", true)
        if eab and eab.SetGrowDirectionForBar then
            eab:SetGrowDirectionForBar(barKey, val)
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
                    EllesmereUI.ClearFramePoints(barFrame)
                    EllesmereUI.SetFramePoint(barFrame, pt, relTo, relPt, offX + dx, offY + dy)
                end
            end
        end
    end
    EllesmereUI.RecenterBarAnchor(barKey)
    -- Anchored bars: hold the new growth edge from where the bar sits NOW, the
    -- way the drag-stop path does after a drop. Left to the lazy capture, the
    -- next apply would read the rect BEFORE the move it was asked to make (a
    -- first nudge, a first drag of the target) and stamp that stale hold; and a
    -- hold left over from an earlier direction would be trusted again the day
    -- that direction comes back. Centered growth keeps no hold.
    local ai = GetAnchorInfo(barKey)
    if ai and ai.target then
        ai.refFor, ai.refX, ai.refY, ai.edgeOffX, ai.edgeOffY = nil, nil, nil, nil, nil
        if EllesmereUI._unlockCaptureGrowPin then
            EllesmereUI._unlockCaptureGrowPin(barKey, ai, ai.side)
        end
    end
    -- Store in pending (committed on Save & Exit)
    if barFrame then
        local pt2, relTo2, relPt2, offX2, offY2 = barFrame:GetPoint(1)
        if pt2 then
            pendingPositions[barKey] = {
                point = pt2, relPoint = relPt2, x = offX2, y = offY2,
            }
            UM.hasChanges = true
        end
    end

    -- Sync the mover to the bar's new position
    if movers[barKey] and movers[barKey].Sync then
        movers[barKey]:Sync()
    end
end

-- Arrow key nudge: single press only, no hold-to-repeat
local function SetupArrowKeyFrame()
    if UM.arrowKeyFrame then return end
    UM.arrowKeyFrame = CreateFrame("Frame", nil, UIParent)
    UM.arrowKeyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    UM.arrowKeyFrame:SetFrameLevel(500)
    UM.arrowKeyFrame:EnableKeyboard(true)
    UM.arrowKeyFrame:SetPropagateKeyboardInput(true)
    UM.arrowKeyFrame:Hide()

    local ARROW_DIRS = {
        UP    = { 0,  1 },
        DOWN  = { 0, -1 },
        LEFT  = { -1, 0 },
        RIGHT = { 1,  0 },
    }

    UM.arrowKeyFrame:SetScript("OnKeyDown", function(self, key)
        if not UM.isUnlocked then return end
        local dir = ARROW_DIRS[key]
        if not dir then return end
        -- A selected fallback ghost answers the arrow keys with the exact
        -- same step math as movers (1 physical pixel; shift = 100).
        if not UM.selectedMover and EllesmereUI._NudgeSelectedFallbackGhost then
            local PPg = EllesmereUI and EllesmereUI.PP
            local gStep = PPg and PPg.mult or 1
            local gs = IsShiftKeyDown() and (100 * gStep) or gStep
            if EllesmereUI._NudgeSelectedFallbackGhost(dir[1] * gs, dir[2] * gs) then
                self:SetPropagateKeyboardInput(false)
                return
            end
        end
        -- A selected override-anchor ghost answers the same way.
        if not UM.selectedMover and EllesmereUI._NudgeSelectedOverrideGhost then
            local PPo = EllesmereUI and EllesmereUI.PP
            local oStep = PPo and PPo.mult or 1
            local os = IsShiftKeyDown() and (100 * oStep) or oStep
            if EllesmereUI._NudgeSelectedOverrideGhost(dir[1] * os, dir[2] * os) then
                self:SetPropagateKeyboardInput(false)
                return
            end
        end
        if not UM.selectedMover then return end
        self:SetPropagateKeyboardInput(false)
        -- Scale by physical pixel size so each press moves exactly 1px
        local PPn = EllesmereUI and EllesmereUI.PP
        local pxStep = PPn and PPn.mult or 1
        local step = IsShiftKeyDown() and (100 * pxStep) or pxStep
        -- When this element's cog/snap menu is open, keep the mover expanded
        -- (skipCollapse) so the open menu does not jump, then reanchor to the bar
        -- and refresh the cog X/Y boxes so they track the nudge.
        local m = UM.selectedMover
        local menuOpen = m._menuOpen
        NudgeMover(dir[1] * step, dir[2] * step, nil, menuOpen)
        if menuOpen then
            if m.ReanchorToBar then m:ReanchorToBar() end
            if m._syncCogPos then m._syncCogPos() end
        end
    end)

    UM.arrowKeyFrame:SetScript("OnKeyUp", function(self, key)
        self:SetPropagateKeyboardInput(true)
    end)
end

-------------------------------------------------------------------------------
--  Action bar visual size helper: computes the actual visual size of an action bar
--  accounting for overrideNumIcons, overrideNumRows, padding, and per-button scale.
--  Returns w, h in UIParent-relative pixels, or nil if not applicable.
-------------------------------------------------------------------------------
local function GetActionBarVisualSize(barKey)
    if not EAB or not EAB.db then return nil end
    local info = BAR_LOOKUP[barKey]
    if not info then return nil end
    local s = EAB.db.profile.bars[lookupKey]
    if not s then return nil end

    -- Use standard button size (45x45) -- our LayoutBar uses this for MainBar
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
    if not UM.unlockFrame then return end
    local BASE = UM.unlockFrame:GetFrameLevel() + 20
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
--  Blizzard-Owned Info Overlays: visual overlays shown during unlock mode on
--  elements whose position is controlled by Blizzard Edit Mode (chat, micro menu,
--  bags, encounter bar). Not draggable. Hover shows accent-colored "Move via Blizz
--  Edit Mode" text with the same animation as regular mover links; clicking closes unlock mode and opens Blizzard's Edit Mode.
-------------------------------------------------------------------------------
local BLIZZ_OWNED_OVERLAY_DEFS = {
    -- Chat is NOT here anymore: it is a REAL unlock element registered by
    -- EllesmereUIChat (position genesis-captured from Edit Mode's last spot,
    -- then enforced against Edit Mode via the chat module's anchor guard).
    { label = "Micro Menu",    frame = function() return _G.MicroMenuContainer end },
    { label = "Bags",          frame = function() return _G.BagsBar end },
    { label = "Encounter Bar", frame = function() return _G.PlayerPowerBarAlt end, showAlways = true, fallbackW = 240, fallbackH = 36, yOffset = 44 },
    { label = "Buffs",         frame = function() return _G.BuffFrame end },
    { label = "Debuffs",       frame = function() return _G.DebuffFrame end },
    -- Blizzard Edit Mode's default tooltip anchor. EUI permanently owns the default
    -- tooltip position (fixed anchor in EllesmereUIBlizzardSkin, a real draggable
    -- mover) and Anchor to Cursor pins it to the mouse -- either way this read-only
    -- overlay steps aside. Only shows with "Reskin Tooltip" off, where Blizzard's
    -- position genuinely applies. Container is small/idle when no tooltip is up, so use the showAlways fallback like the Encounter Bar.
    { label = "Tooltip",       frame = function()
          if not (EllesmereUIDB and EllesmereUIDB.customTooltips == false) then return nil end
          return _G.GameTooltipDefaultContainer
      end, showAlways = true, fallbackW = 280, fallbackH = 165 },
}

local function CreateBlizzOwnedOverlay(def, parent)
    local ar, ag, ab = GetAccent()
    local ov = CreateFrame("Frame", nil, parent)
    ov:EnableMouse(true)
    -- Background: same as regular movers
    local bg = ov:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.103, 0.095, 0.088, 0.95)
    -- Border: accent at idle, white on hover
    local brd = EllesmereUI.MakeBorder(ov, ar, ag, ab, 0.6)
    ov._brd = brd
    -- Label (always visible, same style as mover labels)
    local nameFs = ov:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(nameFs, true)
    nameFs:SetFont(FONT_PATH, 10 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
    nameFs:SetPoint("CENTER", ov, "CENTER", 0, 0)
    nameFs:SetTextColor(1, 1, 1, 0.75)
    nameFs:SetText(EllesmereUI.L(def.label))
    nameFs:SetWordWrap(false)
    ov._nameFs = nameFs
    -- Action text (hidden at idle, fades in on hover)
    local actionFs = ov:CreateFontString(nil, "OVERLAY")
    EllesmereUI.PrimeFontShadow(actionFs, true)
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
    -- Shift+Right Click temporarily hides this overlay for the current unlock
    -- session (matches the regular mover behavior). The _tempHidden flag is
    -- cleared on the next unlock entry so the overlay reappears then. Purely a
    -- visual toggle on the info overlay -- it never touches the Blizzard frame.
    local function TempHide(_, button)
        if button == "RightButton" and IsShiftKeyDown() then
            ov._tempHidden = true
            ov._forceCollapse()
            ov:Hide()
        end
    end
    ov:SetScript("OnMouseUp", TempHide)
    -- The hover action strip (a child button) swallows mouse events over itself,
    -- so wire the same handler there to catch a Shift+Right Click landing on it.
    actionBtn:SetScript("OnMouseUp", TempHide)
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

UM.GetAccent, UM.CreateGrid, UM.ClearSnapHighlight, UM.ShowSnapHighlight = GetAccent, CreateGrid, ClearSnapHighlight, ShowSnapHighlight
UM.HideAllGuidesAndHighlight, UM.ShowAlignmentGuides, UM.SnapPosition, UM.SelectMover = HideAllGuidesAndHighlight, ShowAlignmentGuides, SnapPosition, SelectMover
UM.DeselectMover, UM.ApplyDarkOverlays, UM.SetupArrowKeyFrame, UM.GetActionBarVisualSize = DeselectMover, ApplyDarkOverlays, SetupArrowKeyFrame, GetActionBarVisualSize
UM.SortMoverFrameLevels, UM.ShowBlizzOwnedOverlays, UM.HideBlizzOwnedOverlays = SortMoverFrameLevels, ShowBlizzOwnedOverlays, HideBlizzOwnedOverlays
end
