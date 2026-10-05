if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CDM_Bars.lua
--
--  Bar position helpers, BuildCDMBar, LayoutCDMBar and the tooltip state.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, ns = ...
local I = ns._internals
-- The main file or an earlier CDM file failed to load.
if not I or I.broken then return end
I.broken = true

local floor = math.floor

local ECME, FC, IsPlaceholderRenderHidden = I.ECME, I.FC, I.IsPlaceholderRenderHidden
local SnapForScale, _cdmMouseState, _ecmeFC = I.SnapForScale, I._cdmMouseState, I._ecmeFC
local _getFD, barDataByKey, cdmBarFrames = I._getFD, I.barDataByKey, I.cdmBarFrames
local cdmBarIcons = I.cdmBarIcons

local BuildCDMBar, LayoutCDMBar

local _CDMApplyVisibility
I.SetCDMApplyVisibility = function(fn) _CDMApplyVisibility = fn end

-------------------------------------------------------------------------------
--  CDM Bar Position Helpers
-------------------------------------------------------------------------------

-- Resolve the frame anchor point for a bar from its growth direction and optional row growth direction.
--
-- Without rowGrowDirection: the single growth edge (RIGHT -> LEFT, DOWN -> TOP, ...) so the
-- fixed edge stays put as the bar resizes along its growth axis; the perpendicular axis stays
-- unpinned (centered), which is why a horizontal bar re-centers vertically when it grows a
-- second row. rowGrowDirection applies the same growth->opposite-edge mapping to the
-- PERPENDICULAR axis, yielding a corner/edge anchor (e.g. TOPLEFT): horizontal bars take "DOWN"
-- (pin TOP) or "UP" (pin BOTTOM); vertical bars take "RIGHT" (pin LEFT) or "LEFT" (pin RIGHT);
-- nil keeps centered growth. Icons lay out from the frame's TOPLEFT, so "UP"/"LEFT" also need
-- LayoutCDMBar's visual row reversal to keep the pinned row's icons from jumping when a row
-- spills in/out. ns.* fields rather than file-scope locals: Lua 5.1's 200-local main-chunk ceiling.
--
-- ignoreRowGrow: resolve the plain growth edge even when a row growth direction is set -- for
-- unlock-snapped bars, whose saved-edge consumers (ApplyAnchorPosition edge preservation/target follow) only understand single-edge points.
function ns.ResolveGrowAnchorPoint(barData, ignoreRowGrow)
    local grow = (barData and barData.growDirection) or "CENTER"
    local horiz, vert  -- "LEFT"/"RIGHT" and "TOP"/"BOTTOM" components
    if grow == "RIGHT" then
        horiz = "LEFT"
    elseif grow == "LEFT" then
        horiz = "RIGHT"
    elseif grow == "DOWN" then
        vert = "TOP"
    elseif grow == "UP" then
        vert = "BOTTOM"
    end
    local rowGrow = barData and barData.rowGrowDirection
    if rowGrow and not ignoreRowGrow then
        -- Same opposite-edge mapping applied to the perpendicular axis. The orientation guards keep a value left stale by an orientation flip from clobbering the main-axis component.
        if barData.verticalOrientation then
            if rowGrow == "RIGHT" then
                horiz = horiz or "LEFT"
            elseif rowGrow == "LEFT" then
                horiz = horiz or "RIGHT"
            end
        else
            if rowGrow == "DOWN" then
                vert = vert or "TOP"
            elseif rowGrow == "UP" then
                vert = vert or "BOTTOM"
            end
        end
    end
    local pt = (vert or "") .. (horiz or "")
    if pt == "" then
        return "CENTER"
    end
    return pt
end

-- Convert a frame CENTER coord to the coord for anchor point `pt`. An axis with no LEFT/RIGHT
-- (or TOP/BOTTOM) component keeps the center; a zero-extent frame yields a zero offset, so this is safe for empty bars.
function ns.CenterToAnchorCoord(pt, x, y, fw, fh)
    local sx, sy = x, y
    if pt:find("LEFT", 1, true) then
        sx = x - fw / 2
    elseif pt:find("RIGHT", 1, true) then
        sx = x + fw / 2
    end
    if pt:find("TOP", 1, true) then
        sy = y + fh / 2
    elseif pt:find("BOTTOM", 1, true) then
        sy = y - fh / 2
    end
    return sx, sy
end

-- Inverse of CenterToAnchorCoord: recover the frame CENTER coord from a stored anchor-point coord. Round-trips losslessly for edges, corners, and CENTER.
function ns.AnchorCoordToCenter(pt, sx, sy, fw, fh)
    local x, y = sx, sy
    if pt:find("LEFT", 1, true) then
        x = sx + fw / 2
    elseif pt:find("RIGHT", 1, true) then
        x = sx - fw / 2
    end
    if pt:find("TOP", 1, true) then
        y = sy - fh / 2
    elseif pt:find("BOTTOM", 1, true) then
        y = sy + fh / 2
    end
    return x, y
end

-- "Additional Bar Offset" (bd.addOffsetX/Y; ADDITIONAL BAR OFFSET options
-- section): a render-only displacement stacked on top of whatever positioned
-- the bar -- saved position, module anchor (party/player/ERB), or the shared
-- unlock anchor system (which folds it through _anchorExtraOffset instead of
-- this helper). Suppressed while unlock mode is active so movers show and save
-- TRUE positions; the shift-provider lifecycle hooks strip it on unlock entry
-- and re-apply it on exit. nil/0 = zero work and zero movement (purely
-- additive feature). On ns: this file is at the 200-local cap.
ns.CDMAddOffset = function(bd)
    if not bd then return 0, 0 end
    local ox = bd.addOffsetX or 0
    local oy = bd.addOffsetY or 0
    if ox == 0 and oy == 0 then return 0, 0 end
    if EllesmereUI._unlockActive then return 0, 0 end
    return ox, oy
end

local function ApplyBarPositionCentered(frame, pos, barKey)
    if not pos or not pos.point then return end
    local fw = frame:GetWidth() or 0
    local fh = frame:GetHeight() or 0
    local px, py = pos.x or 0, pos.y or 0
    local anchor = pos.point
    local bd = barKey and barDataByKey[barKey]

    -- Corner-capable re-derivation, taken ONLY when a row growth direction is in play (or the
    -- stored point is a leftover corner): recover the frame center from the stored anchor coord,
    -- then re-project onto the anchor resolved from the bar's CURRENT growth + row growth.
    -- Lossless round-trip -- the bar does not move, only the pinned edge/corner changes. Bars without a row growth direction take the conversion below. No persistence: positions are only saved by unlock mode's Save & Exit.
    local storedIsCorner = (anchor:find("TOP", 1, true) or anchor:find("BOTTOM", 1, true))
        and (anchor:find("LEFT", 1, true) or anchor:find("RIGHT", 1, true))
    if (bd and bd.rowGrowDirection) or storedIsCorner then
        local cx, cy = ns.AnchorCoordToCenter(anchor, px, py, fw, fh)
        anchor = ns.ResolveGrowAnchorPoint(bd)
        px, py = ns.CenterToAnchorCoord(anchor, cx, cy, fw, fh)
    elseif anchor == "CENTER" and barKey then
        -- Runtime conversion: a non-CENTER-grow bar with a CENTER position (legacy data,
        -- Blizzard import) converts to edge format for SetPoint so it grows from the correct edge.
        local grow = bd and bd.growDirection or "CENTER"
        if grow ~= "CENTER" then
            if grow == "RIGHT" and fw > 0 then
                anchor = "LEFT"; px = px - fw / 2
            elseif grow == "LEFT" and fw > 0 then
                anchor = "RIGHT"; px = px + fw / 2
            elseif grow == "DOWN" and fh > 0 then
                anchor = "TOP"; py = py + fh / 2
            elseif grow == "UP" and fh > 0 then
                anchor = "BOTTOM"; py = py - fh / 2
            end
        end
    end

    -- Additional Bar Offset: applied PRE-snap so the sum lands on the pixel
    -- grid; a zero offset is a guaranteed no-op.
    local aox, aoy = ns.CDMAddOffset(bd)
    px, py = px + aox, py + aoy

    -- Snap to physical pixel grid. CENTER anchor: SnapCenterForDim preserves the +0.5 offset
    -- odd-pixel-dim frames need for whole-pixel edges. Single-edge anchors: the growth-axis
    -- coord is an EDGE (whole-pixel snap) but the perpendicular coord is the frame's CENTER on
    -- that axis -- parity-aware snap keeps whole-pixel edges there too. Corner anchors (row growth pin) are edges on BOTH axes.
    local PPa = EllesmereUI and EllesmereUI.PP
    if PPa then
        local es = frame:GetEffectiveScale()
        if anchor == "CENTER" and PPa.SnapCenterForDim then
            px = PPa.SnapCenterForDim(px, fw, es)
            py = PPa.SnapCenterForDim(py, fh, es)
        elseif PPa.SnapForES then
            if PPa.SnapCenterForDim and (anchor == "LEFT" or anchor == "RIGHT") then
                px = PPa.SnapForES(px, es)
                py = PPa.SnapCenterForDim(py, fh, es)
            elseif PPa.SnapCenterForDim and (anchor == "TOP" or anchor == "BOTTOM") then
                px = PPa.SnapCenterForDim(px, fw, es)
                py = PPa.SnapForES(py, es)
            else
                px = PPa.SnapForES(px, es)
                py = PPa.SnapForES(py, es)
            end
        end
    end

    frame:ClearAllPoints()
    frame:SetPoint(anchor, UIParent, pos.relPoint or anchor, px, py)
end

local function SaveCDMBarPosition(barKey, frame)
    if not frame then return end
    local p = ECME.db.profile
    local scale = frame:GetScale() or 1
    local uiScale = UIParent:GetEffectiveScale()
    local fScale = frame:GetEffectiveScale()
    local uiW, uiH = UIParent:GetSize()
    local ratio = fScale / uiScale

    -- Anchor point from grow + row growth direction, so the bar's fixed edge/corner stays put when icon count changes (spec swaps, combat buff churn, a row spilling in/out).
    local bd = barDataByKey[barKey]
    local pt = ns.ResolveGrowAnchorPoint(bd)

    -- Read each axis from the matching frame edge (corner points pin both).
    local cx, cy = frame:GetCenter()
    if not cx or not cy then return end
    local ax, ay
    if pt:find("LEFT", 1, true) then
        local lx = frame:GetLeft()
        if not lx then return end
        ax = lx * ratio
    elseif pt:find("RIGHT", 1, true) then
        local rx = frame:GetRight()
        if not rx then return end
        ax = rx * ratio
    else
        ax = cx * ratio
    end
    if pt:find("TOP", 1, true) then
        local ty = frame:GetTop()
        if not ty then return end
        ay = ty * ratio
    elseif pt:find("BOTTOM", 1, true) then
        local by = frame:GetBottom()
        if not by then return end
        ay = by * ratio
    else
        ay = cy * ratio
    end

    -- Store relative to UIParent CENTER so offset math is consistent.
    -- Additional Bar Offset: live geometry includes the render-only offset
    -- while out of unlock mode -- subtract it so the SAVED position is always
    -- the BASE (else the Row Growth recapture bakes it in and the bar drifts
    -- by one offset per edit). In unlock mode both terms are already base:
    -- the frame carries no offset and CDMAddOffset returns 0.
    local aox, aoy = ns.CDMAddOffset(bd)
    p.cdmBarPositions[barKey] = {
        point = pt, relPoint = "CENTER",
        x = (ax - uiW / 2) / scale - aox,
        y = (ay - uiH / 2) / scale - aoy,
    }
end

-- Re-persist a bar's saved position in its CURRENT anchor format from live geometry. Needed
-- when the row growth direction changes: a stored center/single-edge position can't pin the
-- row edge across row changes (only a stored corner can), so recapture the corner from where
-- the bar sits now. Free-standing bars only -- snapped bars are owned by the unlock anchor system, which reads unlockAnchors, not cdmBarPositions.
function ns.RecaptureBarAnchor(barKey)
    local frame = cdmBarFrames[barKey]
    if not frame then return end
    -- anchorTo bars (cursor, party/player frame, ERB, another bar) are positioned by their
    -- anchor, not cdmBarPositions -- saving live geometry would overwrite the free-standing position with the anchored spot.
    local bd = barDataByKey[barKey]
    if bd and bd.anchorTo and bd.anchorTo ~= "none" then return end
    if EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored("CDM_" .. barKey) then return end
    if not frame:GetLeft() then return end
    SaveCDMBarPosition(barKey, frame)
end

-------------------------------------------------------------------------------
--  Frame anchor point for a CDM bar: the near-edge center (the edge facing away
--  from the target). RIGHT -> LEFT, LEFT -> RIGHT, DOWN -> TOP, UP -> BOTTOM.
-------------------------------------------------------------------------------
local function CDMFrameAnchorPoint(anchorSide, grow, centered)

    if grow == "RIGHT" then return "LEFT"   end
    if grow == "LEFT"  then return "RIGHT"  end
    if grow == "DOWN"  then return "TOP"    end
    if grow == "UP"    then return "BOTTOM" end
    if grow == "CENTER" then return "CENTER" end
    return "CENTER"
end

-------------------------------------------------------------------------------
--  Recursive click-through helper -- disables/restores mouse on a frame tree
-------------------------------------------------------------------------------
local function SetFrameClickThrough(frame, clickThrough)
    if not frame then return end
    if clickThrough then
        if _cdmMouseState[frame] == nil then
            _cdmMouseState[frame] = frame:IsMouseEnabled()
        end
        frame:EnableMouse(false)
        if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
    else
        if _cdmMouseState[frame] ~= nil then
            frame:EnableMouse(_cdmMouseState[frame])
            _cdmMouseState[frame] = nil
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        SetFrameClickThrough(child, clickThrough)
    end
end

-------------------------------------------------------------------------------
--  Build a single CDM bar frame
-------------------------------------------------------------------------------
BuildCDMBar = function(barIndex)
    local p = ECME.db.profile
    local bars = p.cdmBars.bars
    local barData = bars[barIndex]
    if not barData then return end

    local key = barData.key
    local frame = cdmBarFrames[key]

    if not frame then
        frame = CreateFrame("Frame", "ECME_CDMBar_" .. key, UIParent)
        -- Per-bar Bar Strata (Extras); MEDIUM = the historical hardcoded value.
        frame:SetFrameStrata(barData.barStrata or "MEDIUM")
        frame:SetFrameLevel(5)
        if frame.SetSnapToPixelGrid then frame:SetSnapToPixelGrid(false) end
        if frame.SetTexelSnappingBias then frame:SetTexelSnappingBias(0) end
        if frame.EnableMouseClicks then frame:EnableMouseClicks(false) end
        -- Containers NEVER capture mouse motion: the rect spans the bar's full layout area and a
        -- motion-enabled frame with no unit steals mouseover focus from unit frames underneath. Hover is managed per-icon, gated on the bar's tooltip setting.
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
        frame._barKey = key
        frame._barIndex = barIndex
        cdmBarFrames[key] = frame
        cdmBarIcons[key] = {}
    end

    if not barData.enabled then
        if frame._mouseTrack then
            frame:SetScript("OnUpdate", nil)
            if EllesmereUI.Mouse then
                EllesmereUI.Mouse.UnsubscribeFrame("cdmCursor:" .. tostring(key))
                EllesmereUI.Mouse.UnsubscribeTick("cdmCursor:" .. tostring(key) .. ":watch")
            end
            frame._mouseResume = nil
            frame._mouseTrack = nil
            if frame._preMousePos and not p.cdmBarPositions[key] then
                p.cdmBarPositions[key] = frame._preMousePos
            end
            frame._preMousePos = nil
            SetFrameClickThrough(frame, false)
            if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
        end
        EllesmereUI.SetElementVisibility(frame, false)
        return
    end

    -- All sizing is width/height based; scale stays 1.
    if not InCombatLockdown() then frame:SetScale(1) end

    -- Restore configured strata/level (cursor-anchored uses TOOLTIP/9980)
    if not frame._mouseTrack then
        frame:SetFrameStrata(barData.barStrata or "MEDIUM")
        frame:SetFrameLevel(5)
    end

    -- Clear any previous mouse-tracking subscriptions
    if frame._mouseTrack then
        frame:SetScript("OnUpdate", nil)
        if EllesmereUI.Mouse then
            EllesmereUI.Mouse.UnsubscribeFrame("cdmCursor:" .. tostring(key))
            EllesmereUI.Mouse.UnsubscribeTick("cdmCursor:" .. tostring(key) .. ":watch")
        end
        frame._mouseResume = nil
        frame._mouseTrack = nil
        -- Restore position/strata/mouse from before the cursor anchor
        if frame._preMousePos and not p.cdmBarPositions[key] then
            p.cdmBarPositions[key] = frame._preMousePos
        end
        frame._preMousePos = nil
        frame:SetFrameStrata(barData.barStrata or "MEDIUM")
        frame:SetFrameLevel(5)
        SetFrameClickThrough(frame, false)
        if frame.EnableMouseMotion then frame:EnableMouseMotion(false) end
    end
    frame._mouseGrow = nil

    -- FocusKick bar is exclusively owned by ApplyFocusKickAnchor: skipping the generic position
    -- block keeps the else-branch default from snapping it to UIParent CENTER 0,0 between a rebuild and the next nameplate event. Literal key: FOCUSKICK_BAR_KEY is declared later and would be nil here.
    if key == "focuskick" then
        frame:Show()
        return
    end

    -- Cursor-anchored bar already tracking and still configured for mouse: skip the
    -- teardown+rebuild cycle. It is already repositioning correctly, and tearing it down blinks to BOTTOMLEFT 0,0 on every FullCDMRebuild.
    if frame._mouseTrack and barData.anchorTo == "mouse" then
        frame:Show()
        return
    end

    -- Position
    local anchorKey = barData.anchorTo
    if anchorKey == "mouse" then
        -- Stash saved position for restore on unanchor
        if p.cdmBarPositions[key] then
            frame._preMousePos = p.cdmBarPositions[key]
        end
        -- Anchor position acts as build direction for cursor tracking
        local anchorPos = barData.anchorPosition or "right"
        local oX = barData.anchorOffsetX or 0
        local oY = barData.anchorOffsetY or 0
        -- SetPoint anchor + 15px directional nudge
        local pointFrom, baseOX, baseOY, forceGrow
        if anchorPos == "left" then
            pointFrom = "RIGHT"; forceGrow = "LEFT"
            baseOX = -15 + oX; baseOY = oY
        elseif anchorPos == "right" then
            pointFrom = "LEFT"; forceGrow = "RIGHT"
            baseOX = 15 + oX; baseOY = oY
        elseif anchorPos == "top" then
            pointFrom = "BOTTOM"; forceGrow = "UP"
            baseOX = oX; baseOY = 15 + oY
        elseif anchorPos == "bottom" then
            pointFrom = "TOP"; forceGrow = "DOWN"
            baseOX = oX; baseOY = -15 + oY
        else
            pointFrom = "LEFT"; forceGrow = "RIGHT"
            baseOX = 15 + oX; baseOY = oY
        end
        frame._mouseGrow = forceGrow
        frame._mousePoint = pointFrom  -- park/heal sites outside this closure need it
        -- TOOLTIP strata so the bar renders above all UI; fully click-through (frame + children) while following the cursor.
        frame:SetFrameStrata("TOOLTIP")
        frame:SetFrameLevel(9980)
        SetFrameClickThrough(frame, true)
        local lastMX, lastMY
        frame:ClearAllPoints()
        frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", 0, 0)
        frame._mouseTrack = true
        frame._mouseHiddenByPanel = false
        -- Cursor glue rides the suite Mouse service (EllesmereUI_Mouse.lua): per render frame
        -- while the cursor MOVES (position must track raw -- easing/deferral shows cadence
        -- stepping), parked by the service while still or mouselooking, re-armed within one 20 Hz
        -- watch interval of the first moved pixel. The 0.15s CursorWatch below owns panel/unlock/visibility state, so the glue body is position-only.
        local glueKey = "cdmCursor:" .. tostring(key)
        local Mouse = EllesmereUI.Mouse
        local glueActive = false
        local function CursorGlue(cx, cy)
            if cx ~= lastMX or cy ~= lastMY then
                local firstMove = lastMX == nil
                lastMX, lastMY = cx, cy
                local s = UIParent:GetEffectiveScale()
                if firstMove then frame:ClearAllPoints() end
                frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT",
                    floor(cx / s + 0.5) + baseOX, floor(cy / s + 0.5) + baseOY)
            end
        end
        frame._mouseResume = function()
            lastMX, lastMY = nil, nil
            frame._mouseParked = false
            glueActive = true
            Mouse.SubscribeFrame(glueKey, CursorGlue, true)
        end
        local function GlueOff()
            if glueActive then
                glueActive = false
                Mouse.UnsubscribeFrame(glueKey)
            end
        end
        local function CursorWatch()
            -- Hide while the EUI options panel or unlock mode is open
            local panelOpen = (EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown())
                or EllesmereUI._unlockActive
            if panelOpen then
                GlueOff()
                frame._mouseHiddenByPanel = true
                if frame:GetAlpha() > 0 then frame:SetAlpha(0) end
                local icons = cdmBarIcons[key]
                if icons then
                    for ii = 1, #icons do
                        if icons[ii] and icons[ii]:GetFrameStrata() == "TOOLTIP" then
                            icons[ii]:SetFrameStrata(barData.barStrata or "MEDIUM")
                            icons[ii]:SetFrameLevel(5 + ii)
                        end
                    end
                end
                return
            elseif frame._mouseHiddenByPanel then
                -- Panel just closed: restore visibility and icon strata
                frame._mouseHiddenByPanel = false
                local icons = cdmBarIcons[key]
                if icons then
                    for ii = 1, #icons do
                        if icons[ii] then
                            icons[ii]:SetFrameStrata("TOOLTIP")
                            icons[ii]:SetFrameLevel(9980 + ii)
                        end
                    end
                end
                _CDMApplyVisibility()
            end
            -- Visibility-hidden: park the bar offscreen instead of tracking the cursor. Alpha
            -- alone CANNOT keep icons invisible -- the engine re-raises item alpha through paths
            -- no hook sees (SetAlphaFromBoolean, alpha animations) on cooldown/aura state changes,
            -- so a hidden bar flashes back mid-screen riding the cursor (same lesson as the
            -- unclaimed-frame park in EllesmereUICdmHooks). Icons anchor to this container so the park carries them, immune to every alpha path. Movers-while-parked heal via ns._parkEdges + the LayoutCDMBar guard -- no patrol.
            if frame._visHidden then
                GlueOff()
                if not frame._mouseParked or (frame:GetLeft() or 0) > -9000 then
                    frame._mouseParked = true
                    lastMX, lastMY = nil, nil
                    frame:ClearAllPoints()
                    frame:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", -10000, -10000)
                end
                return
            end
            -- Visible and unobstructed: ensure the glue rides the service (covers the visibility show edge and setup re-runs; resume snaps to the cursor via the lastMX reset).
            if frame._mouseParked or not glueActive then
                frame._mouseResume()
            end
            -- Mouse-through re-assert: the Decorate/Show/Cooldown path can re-enable mouse on
            -- icons mid-session, and an icon riding the cursor with mouse enabled intermittently
            -- kills [@mouseover] hovercast keys. MUST live here (0.15s, motion-independent) not in the glue: cooldown repaints re-enable mouse with the cursor perfectly still. Cheap no-op when state is clean.
            local icons = cdmBarIcons[key]
            if icons then
                for ii = 1, #icons do
                    local ic = icons[ii]
                    if ic then
                        if ic:IsMouseEnabled() then ic:EnableMouse(false) end
                        if ic.IsMouseMotionEnabled and ic:IsMouseMotionEnabled() then
                            ic:EnableMouseMotion(false)
                        end
                    end
                end
            end
        end
        Mouse.SubscribeTick(glueKey .. ":watch", 0.15, CursorWatch)
        CursorWatch()
    elseif anchorKey == "partyframe" then
        local partyFrame = EllesmereUI.FindPlayerPartyFrame()
        if partyFrame then
            frame:ClearAllPoints()
            local side = barData.partyFrameSide or "LEFT"
            local oX = barData.partyFrameOffsetX or 0
            local oY = barData.partyFrameOffsetY or 0
            do -- Additional Bar Offset stacks on the anchor's own offsets
                local aox, aoy = ns.CDMAddOffset(barData)
                oX, oY = oX + aox, oY + aoy
            end
            local PPa = EllesmereUI and EllesmereUI.PP
            if PPa and PPa.SnapForES then
                local es = frame:GetEffectiveScale()
                oX = PPa.SnapForES(oX, es)
                oY = PPa.SnapForES(oY, es)
            end
            local grow = barData.growDirection or "CENTER"
            local centered = barData.growCentered ~= false
            local fp = CDMFrameAnchorPoint(side, grow, centered)
            frame._anchorSide = side:upper()
            if side == "LEFT" then
                frame:SetPoint(fp, partyFrame, "LEFT", oX, oY)
            elseif side == "RIGHT" then
                frame:SetPoint(fp, partyFrame, "RIGHT", oX, oY)
            elseif side == "TOP" then
                frame:SetPoint(fp, partyFrame, "TOP", oX, oY)
            elseif side == "BOTTOM" then
                frame:SetPoint(fp, partyFrame, "BOTTOM", oX, oY)
            end
        else
            -- No party frame: fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, key)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey == "playerframe" then
        local playerFrame = EllesmereUI.FindPlayerUnitFrame()
        if playerFrame then
            frame:ClearAllPoints()
            local side = barData.playerFrameSide or "LEFT"
            local oX = barData.playerFrameOffsetX or 0
            local oY = barData.playerFrameOffsetY or 0
            do -- Additional Bar Offset stacks on the anchor's own offsets
                local aox, aoy = ns.CDMAddOffset(barData)
                oX, oY = oX + aox, oY + aoy
            end
            local PPa = EllesmereUI and EllesmereUI.PP
            if PPa and PPa.SnapForES then
                local es = frame:GetEffectiveScale()
                oX = PPa.SnapForES(oX, es)
                oY = PPa.SnapForES(oY, es)
            end
            local grow = barData.growDirection or "CENTER"
            local centered = barData.growCentered ~= false
            local fp = CDMFrameAnchorPoint(side, grow, centered)
            frame._anchorSide = side:upper()
            if side == "LEFT" then
                frame:SetPoint(fp, playerFrame, "LEFT", oX, oY)
            elseif side == "RIGHT" then
                frame:SetPoint(fp, playerFrame, "RIGHT", oX, oY)
            elseif side == "TOP" then
                frame:SetPoint(fp, playerFrame, "TOP", oX, oY)
            elseif side == "BOTTOM" then
                frame:SetPoint(fp, playerFrame, "BOTTOM", oX, oY)
            end
        else
            -- No player frame: fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, key)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    elseif anchorKey == "erb_castbar" or anchorKey == "erb_powerbar" or anchorKey == "erb_classresource" then
        -- Anchor to Resource Bars frames
        local erbFrameNames = {
            erb_castbar = "ERB_CastBarFrame",
            erb_powerbar = "ERB_PrimaryBar",
            erb_classresource = "ERB_SecondaryFrame",
        }
        local erbFrame = _G[erbFrameNames[anchorKey]]
        if erbFrame then
            local anchorPos = barData.anchorPosition or "left"
            frame:ClearAllPoints()
            local gap = barData.spacing or 2
            local oX = barData.anchorOffsetX or 0
            local oY = barData.anchorOffsetY or 0
            do -- Additional Bar Offset stacks on the anchor's own offsets
                local aox, aoy = ns.CDMAddOffset(barData)
                oX, oY = oX + aox, oY + aoy
            end
            local PPa = EllesmereUI and EllesmereUI.PP
            if PPa and PPa.SnapForES then
                local es = frame:GetEffectiveScale()
                gap = PPa.SnapForES(gap, es)
                oX = PPa.SnapForES(oX, es)
                oY = PPa.SnapForES(oY, es)
            end
            local grow = barData.growDirection or "CENTER"
            local centered = barData.growCentered ~= false
            local fp = CDMFrameAnchorPoint(anchorPos:upper(), grow, centered)
            frame._anchorSide = anchorPos:upper()
            local ok
            if anchorPos == "left" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "LEFT", -gap + oX, oY)
            elseif anchorPos == "right" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "RIGHT", gap + oX, oY)
            elseif anchorPos == "top" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "TOP", oX, gap + oY)
            elseif anchorPos == "bottom" then
                ok = pcall(frame.SetPoint, frame, fp, erbFrame, "BOTTOM", oX, -gap + oY)
            end
            -- Circular anchor: fall back to center
            if not ok then
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        else
            -- ERB frame unavailable: fall back to saved position
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, key)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
    else
        -- Unlock-anchored and already positioned: DO NOT touch the position. ApplyAnchorPosition/
        -- PropagateAnchorChain are authoritative there. A rebuild falling into the "no saved pos"
        -- branch below would teleport the bar to a hardcoded default (e.g. CENTER 0,-275), and if
        -- the anchor target is temporarily unavailable (hidden frame, pre-layout race) the later re-anchor bails and the bar stays stuck at that fallback.
        local unlockKey = "CDM_" .. key
        local anchored = EllesmereUI.IsUnlockAnchored and EllesmereUI.IsUnlockAnchored(unlockKey)
        if anchored and frame:GetLeft() then
            -- Unlock-anchored and already has bounds: leave position alone.
        else
            local pos = p.cdmBarPositions[key]
            if pos and pos.point then
                ApplyBarPositionCentered(frame, pos, key)
            elseif not anchored then
                -- Defaults: only for truly un-anchored bars with no saved pos.
                frame:ClearAllPoints()
                if key == "cooldowns" then
                    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -275)
                elseif key == "utility" then
                    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -320)
                elseif key == "buffs" then
                    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -365)
                else
                    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                end
            end
            -- Anchored with no bounds yet: NO fallback position. ReapplyOwnAnchor runs
            -- after BuildAllCDMBars and places the frame once the target is available.
        end
    end

    -- Always Show() so layout/children work; _CDMApplyVisibility is the single
    -- authority for alpha/hiding.
    frame:Show()
end

-- True when this bar renders data rows in REVERSED visual order: row growth "UP" (horizontal)/
-- "LEFT" (vertical) pins the trailing edge (BOTTOM/RIGHT), so the base (first data) row hugs it
-- and extra rows grow away. Shared by the layout and the options preview so both agree. ns.* field: 200-local cap.
function ns.CDMRowsReversed(barData)
    if not barData then return false end
    local grow = barData.growDirection or "CENTER"
    local isHoriz = (grow == "RIGHT" or grow == "LEFT"
        or (grow == "CENTER" and not barData.verticalOrientation))
    if isHoriz then return barData.rowGrowDirection == "UP" end
    return barData.rowGrowDirection == "LEFT"
end

-- Stride respecting the custom row-count override (numRows == 2 only). Two MUTUALLY EXCLUSIVE
-- overrides both resolve to the BASE row count -- the first DATA row: it fills first and is the
-- row a Row Growth pin keeps in place (on top normally, bottom/right when the visual row order is reversed):
--   * Custom Base Row Count -> topRowCount icons on the base row.
--   * Custom Bottom Row Count (UI removed) -> bottomRowCount icons on the second row; the base row gets the remainder.
-- Mutual exclusivity is enforced in options; if both are set, base wins.
local function ComputeTopRowStride(barData, count)
    local numRows = barData.numRows or 1
    if numRows < 1 then numRows = 1 end
    if numRows == 2 then
        local topCount
        if barData.customTopRowEnabled and barData.topRowCount and barData.topRowCount > 0 then
            topCount = math.min(barData.topRowCount, count)
        elseif barData.customBottomRowEnabled and barData.bottomRowCount and barData.bottomRowCount > 0 then
            topCount = count - math.min(barData.bottomRowCount, count)
        end
        if topCount then
            if topCount < 0 then topCount = 0 end
            local bottomCount = count - topCount
            -- Custom-row mode uses a second row only once BOTH rows are non-empty; until then report ONE effective row so the bar doesn't reserve or lay out an empty row.
            if bottomCount <= 0 or topCount <= 0 then
                return count, 1, count
            end
            return math.max(topCount, bottomCount), numRows, topCount
        end
    end
    local stride = math.ceil(count / numRows)
    local topCount = count - (numRows - 1) * stride
    if topCount < 0 then topCount = 0 end
    return stride, numRows, topCount
end

-- Minimum Bar Size, counted in icon slots along the GROWTH axis. That axis is ALWAYS the `stride`
-- term of the size formulas (width on horizontal bars, height on vertical), so one rule covers both
-- orientations. Returns the stride the CONTAINER reserves; the LAYOUT stride is never replaced --
-- grid wrapping (col = idx % stride) and per-row centering keep using the real icon count, and the
-- reserved surplus becomes a single centering offset. nil/0 (the default) is a straight passthrough.
local function ReserveStride(barData, stride)
    local minN = barData.minSizeIcons
    if minN and minN > stride then return minN end
    return stride
end

-- Empty custom bars still need a stable footprint so unlock mode can keep a visible mover and convert drag positions correctly before any icons exist.
local EMPTY_CDM_BAR_SIZE = { 100, 36 }

-- Count spell entries contributing real icon slots. Unlock mode uses this to estimate a footprint before the live frame has been laid out (common for freshly created Misc bars).
local function CountCDMBarSpells(barKey)
    local count = 0
    local sd = ns.GetBarSpellData(barKey)
    if not sd or not sd.assignedSpells then return 0 end
    for _, sid in ipairs(sd.assignedSpells) do
        if sid and sid ~= 0 then count = count + 1 end
    end
    return count
end

local function ComputeCDMBarSize(barData, count)
    -- Raw coord values -- see LayoutCDMBar for why we never pre-snap here.
    local iW = barData.iconSize or 36
    local iH = iW
    if (barData.iconShape or "none") == "cropped" then
        iH = math.floor((barData.iconSize or 36) * ns.CdmCropFactor(barData) + 0.5)
    end
    local sp = barData.spacing or 2
    -- EFFECTIVE row count from ComputeTopRowStride: collapses to 1 while a
    -- custom top-row split's second row is empty, so no empty row is reserved.
    local stride, rows = ComputeTopRowStride(barData, count)
    if rows < 1 then rows = 1 end
    -- Minimum Bar Size reserves extra growth-axis slots (no-op when unset). Unlike LayoutCDMBar
    -- there is no match gate here: this is the pre-layout footprint estimate, and a matched bar's live frame rect (checked first by GetStableCDMBarSize) always wins over it.
    local resStride = ReserveStride(barData, stride)
    local grow = barData.growDirection or "CENTER"
    local isH = (grow == "RIGHT" or grow == "LEFT" or grow == "CENTER")
    if isH then
        return resStride * iW + (resStride - 1) * sp,
               rows * iH + (rows - 1) * sp
    end
    return rows * iW + (rows - 1) * sp,
           resStride * iH + (resStride - 1) * sp
end

-- Authoritative footprint for unlock mode: live frame when it has bounds, else derived from bar config, else the stable empty-bar placeholder.
local function GetStableCDMBarSize(barKey, frame, barData)
    if frame then
        local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
        if w > 1 and h > 1 then
            return w, h
        end
    end

    local count = CountCDMBarSpells(barKey)
    if barData and count > 0 then
        return ComputeCDMBarSize(barData, count)
    end

    -- Buff-family/custom-buff bars have no assigned spells (icons are auras added live), so
    -- before the first aura count is 0. Size from one icon's configured dimensions so the empty frame -- and the unlock overlay mirroring it -- reflect icon size, not the generic placeholder.
    if barData and ((ns.IsBarBuffFamily and ns.IsBarBuffFamily(barData)) or barData.barType == "custom_buff") then
        return ComputeCDMBarSize(barData, 1)
    end

    return EMPTY_CDM_BAR_SIZE[1], EMPTY_CDM_BAR_SIZE[2]
end

-- A width/height match target that draws inside a larger box (getInsets:
-- Blizzard Style unit frames) matches by its visible art, converted into the
-- bar's scale, as the unlock-mode match does. nil for every other target (the
-- raw frame read stands).
function ns.CdmMatchInsetSize(targetKey, targetFrame, bar)
    local elems = EllesmereUI._unlockRegisteredElements
    local elem = elems and elems[targetKey]
    if not (elem and elem.getInsets) then return nil end
    local l, r, t, b = elem.getInsets(targetKey)
    if not l then return nil end
    local k = targetFrame:GetEffectiveScale() / bar:GetEffectiveScale()
    return (targetFrame:GetWidth() - l - r) * k, (targetFrame:GetHeight() - t - b) * k
end

-- "CDM_" .. barKey, built once per bar key, so the layout and pad paths look a
-- bar's unlock element up without building a string each pass.
ns._cdmUKey = setmetatable({}, { __index = function(t, k)
    local v = "CDM_" .. k
    t[k] = v
    return v
end })

-- The width and height a CDM bar's own textured icon border draws OUTSIDE the
-- bar frame, in bar units, from exactly the arguments the icon border renderer
-- passes (bar-level size, texture, offsets and shifts, the "cdm" registry keyed
-- by the thickness label, the exact px, the colour's alpha). The outer icons sit
-- flush with the bar's edges, so their reach is the bar's. The renderer
-- normalizes the icon's scale away (UIParent / icon), so in bar units the ratio
-- is UIParent / bar. nil for buff-family bars (never in a match), the stock
-- looks (no EUI border), custom shapes (the ring sits inside the icon) and a
-- border that draws nothing outside. Reads settings and scales only.
function ns.CdmBarMatchPad(barKey)
    local bd = barDataByKey[barKey]
    local f = cdmBarFrames[barKey]
    if not bd or not f or not EllesmereUI.BorderMatchPad then return nil end
    local tex = bd.borderTexture or "solid"
    if tex == "solid" then return nil end
    if ns.IsBarBuffFamily(bd) or bd.barType == "custom_buff" then return nil end
    if ns.CdmBlizzIcons() then return nil end
    local shape = bd.iconShape or "none"
    if shape ~= "none" and shape ~= "cropped" then return nil end
    local es, uiES = f:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local ratio = 1
    if es and es > 0.01 and uiES and uiES > 0 then ratio = uiES / es end
    local sz = bd.borderSize or 1
    return EllesmereUI.BorderMatchPad(sz, tex, bd.borderTextureOffset, bd.borderTextureOffsetY,
        bd.borderTextureShiftX, bd.borderTextureShiftY, "cdm", bd.borderThickness or "thin",
        EllesmereUI.BorderPx(bd.borderSizePx, sz, tex), ratio, bd.borderA or 1)
end

-- Border-aware CDM match, added to LayoutCDMBar's raw target read in the same
-- units: what the target draws outside its own rect (its getMatchPad on this
-- axis; 0 when its inset art was read, which already is the visible size) minus
-- what this bar's own icon border draws outside. Only positive pads count, as in
-- the unlock-mode match. Exactly 0 when neither side has one.
function ns.CdmMatchAdj(barKey, targetKey, isWidth, insetUsed)
    local t, o = 0, 0
    if not insetUsed then
        local elems = EllesmereUI._unlockRegisteredElements
        local elem = elems and elems[targetKey]
        if elem and elem.getMatchPad then
            local pw, ph = elem.getMatchPad(targetKey)
            local v
            if isWidth then v = pw else v = ph end
            if v and v > 0 then t = v end
        end
    end
    local ow, oh = ns.CdmBarMatchPad(barKey)
    local v
    if isWidth then v = ow else v = oh end
    if v and v > 0 then o = v end
    return t - o
end

-------------------------------------------------------------------------------
--  Layout icons within a CDM bar
-------------------------------------------------------------------------------
LayoutCDMBar = function(barKey)
    local frame = cdmBarFrames[barKey]
    local icons = cdmBarIcons[barKey]
    if not frame or not icons then return end

    local barData = barDataByKey[barKey]
    if not barData or not barData.enabled then return end
    local blizzIcons = ns.CdmBlizzIcons()

    -- A visibility-hidden cursor bar must NEVER be laid back on-screen: its glue is parked and
    -- cannot re-glue it. Park here instead; the visibility show edge re-runs LayoutCDMBar via its deferred call.
    if frame._mouseTrack and frame._visHidden then
        frame._mouseParked = true
        frame:ClearAllPoints()
        frame:SetPoint(frame._mousePoint or "LEFT", UIParent, "BOTTOMLEFT", -10000, -10000)
        return
    end

    -- Shift-Icons cd-state modes: shift-hidden icons are dropped from the layout entirely, so
    -- later icons close the gap and the bar resizes as if the icon were removed. Everything
    -- below (sizing, match math, slot positions) derives from this one array, so the filter IS
    -- the whole feature. Flags set by the cd-state evaluators (ns.SetCdStateShiftHidden) and by
    -- the buff route's Show When Missing active-hide (_missingActiveHidden);
    -- bars without either pay one field read per icon and never build the filtered table. Skipped frames keep their last point at alpha 0.
    do
        local filtered
        for i = 1, #icons do
            local sfc = _ecmeFC[icons[i]]
            if sfc and (sfc._cdStateShiftHidden or sfc._missingActiveHidden) then
                if not filtered then
                    filtered = {}
                    for j = 1, i - 1 do filtered[j] = icons[j] end
                end
            elseif filtered then
                filtered[#filtered + 1] = icons[i]
            end
        end
        if filtered then icons = filtered end
    end

    local grow = frame._mouseGrow or barData.growDirection or "CENTER"
    -- Row count comes from ComputeTopRowStride's EFFECTIVE rows (effRows, below), which
    -- collapses a custom top-row split to one row until its second row is populated.
    local isHoriz = (grow == "RIGHT" or grow == "LEFT" or (grow == "CENTER" and not barData.verticalOrientation))
    -- spacing is a raw coord value; the per-frame conversion below (spacingPx = floor(spacing /
    -- onePx + 0.5)) rounds to nearest whole physical pixel. Do NOT pre-snap with SnapForScale:
    -- PP.Scale truncates and can lose a pixel where PP.mult > 1 (spacing=2 -> 1.0667 coord = 1 px instead of 2).
    local spacing = barData.spacing or 2

    -- Width/height match: derive iconSize live from the SOURCE bar's current width on every
    -- layout pass. The source bar IS the truth, so reading it live auto-corrects across spec swaps, source resizes, etc. NOTHING is persisted, so cross-spec corruption is impossible.
    local extraPixels = 0
    local extraPixelsH = 0
    local widthMatchTarget = EllesmereUI.GetWidthMatchTarget
        and EllesmereUI.GetWidthMatchTarget("CDM_" .. barKey) or nil
    local heightMatchTarget = EllesmereUI.GetHeightMatchTarget
        and EllesmereUI.GetHeightMatchTarget("CDM_" .. barKey) or nil
    local PP = EllesmereUI.PP
    local onePx = PP.mult
    local iconW
    -- True ONLY when the width-match math below produces an iconW. Gates the cropped-height-from-matched-width path so non-matched and height-matched bars stay byte-identical.
    local widthMatchApplied = false
    -- Matched cropped height in physical px, set ONLY when the height-match math succeeds: a
    -- cropped height-matched bar's per-icon height then uses that (not the stored iconSize), staying in lockstep with the container's extraPixelsH leftover distribution.
    local heightMatchIconHPx = nil
    -- Width-axis dim (icons spanning the width). Effective row count, so a not-yet-populated second row doesn't widen the match math.
    local function CurWidthDim()
        local s, r = ComputeTopRowStride(barData, #icons)
        return isHoriz and s or r
    end
    -- Height-axis dim (icons spanning the height)
    local function CurHeightDim()
        local s, r = ComputeTopRowStride(barData, #icons)
        return isHoriz and r or s
    end
    -- Resolve a width/height match target unlock key to a live frame. The match DB stores keys like "CDM_cooldowns" or "MainBar"; the registered unlock element provides a getFrame() callback.
    local function GetMatchTargetFrame(targetKey)
        if not targetKey then return nil end
        local elems = EllesmereUI._unlockRegisteredElements
        local elem = elems and elems[targetKey]
        if elem and elem.getFrame then return elem.getFrame(targetKey) end
        return nil
    end
    if widthMatchTarget and #icons > 0 then
        local targetFrame = GetMatchTargetFrame(widthMatchTarget)
        local targetW = targetFrame and targetFrame:GetWidth() or 0
        if targetFrame then
            local artW = ns.CdmMatchInsetSize(widthMatchTarget, targetFrame, frame)
            if artW then targetW = artW end
            -- Border-aware match (ns.CdmMatchAdj). Skipped at 0 (no textured
            -- border on either side, or equal ones cancelling); never moves the
            -- targetW > 1 gate below either way.
            if targetW > 1 then
                local adj = ns.CdmMatchAdj(barKey, widthMatchTarget, true, artW ~= nil)
                if math.abs(adj) > 1e-6 and targetW + adj > 1 then targetW = targetW + adj end
            end
        end
        local curDim = CurWidthDim()
        if targetW > 1 and curDim and curDim > 0 then
            local physTarget = math.floor(targetW / onePx + 0.5)
            -- The match's Extra Width: whole physical px on the floored target,
            -- so no second rounding. nil = none stored.
            local mx = EllesmereUI.GetMatchExtra and EllesmereUI.GetMatchExtra("w", ns._cdmUKey[barKey])
            if mx then physTarget = physTarget + mx end
            local physSp = math.floor(spacing / onePx + 0.5)
            local rawPhysIcon = (physTarget - (curDim - 1) * physSp) / curDim
            if rawPhysIcon < 8 then rawPhysIcon = 8 end
            local basePhysIcon = math.floor(rawPhysIcon)
            iconW = basePhysIcon * onePx
            widthMatchApplied = true
            local idealPhys = curDim * basePhysIcon + (curDim - 1) * physSp
            local extra = physTarget - idealPhys
            if extra > 0 and extra <= curDim then extraPixels = extra end
        end
    elseif heightMatchTarget and #icons > 0 then
        local targetFrame = GetMatchTargetFrame(heightMatchTarget)
        local targetH = targetFrame and targetFrame:GetHeight() or 0
        if targetFrame then
            local _, artH = ns.CdmMatchInsetSize(heightMatchTarget, targetFrame, frame)
            if artH then targetH = artH end
            -- Border-aware match, as for width.
            if targetH > 1 then
                local adj = ns.CdmMatchAdj(barKey, heightMatchTarget, false, artH ~= nil)
                if math.abs(adj) > 1e-6 and targetH + adj > 1 then targetH = targetH + adj end
            end
        end
        local curDim = CurHeightDim()
        if targetH > 1 and curDim and curDim > 0 then
            local shape = barData.iconShape or "none"
            local cropFactor = (shape == "cropped") and ns.CdmCropFactor(barData) or 1.0
            local physTarget = math.floor(targetH / onePx + 0.5)
            -- The match's Extra Height, as for width.
            local mx = EllesmereUI.GetMatchExtra and EllesmereUI.GetMatchExtra("h", ns._cdmUKey[barKey])
            if mx then physTarget = physTarget + mx end
            local physSp = math.floor(spacing / onePx + 0.5)
            local rawPhysIcon = (physTarget - (curDim - 1) * physSp) / curDim / cropFactor
            if rawPhysIcon < 8 then rawPhysIcon = 8 end
            local basePhysIcon = math.floor(rawPhysIcon)
            iconW = basePhysIcon * onePx
            local basePhysIconH = math.floor(basePhysIcon * cropFactor)
            heightMatchIconHPx = basePhysIconH
            local idealPhys = curDim * basePhysIconH + (curDim - 1) * physSp
            local extra = physTarget - idealPhys
            if extra > 0 and extra <= curDim then extraPixelsH = extra end
        end
    end
    if not iconW then
        -- Not matched, or the target frame couldn't be read (early build, before the source bar
        -- exists): use the stored iconSize, a raw coord value rounded to whole physical px below. Do NOT pre-snap (see spacing).
        iconW = barData.iconSize or 36
    end

    local iconH = iconW
    local shape = barData.iconShape or "none"
    if shape == "cropped" then
        if widthMatchApplied then
            -- Width-matched: cropped height from the MATCHED icon width, so the icon keeps the
            -- same crop aspect as the non-matched path. Computed in physical px to stay on the
            -- pixel grid (matched iconW is already a clean pixel multiple). Aspect intent, not exact value: the non-matched branch rounds the crop factor in coord space, so the two can differ 1px at non-perfect scales.
            local wPx = math.floor(iconW / onePx + 0.5)
            iconH = math.floor(wPx * ns.CdmCropFactor(barData) + 0.5) * onePx
        elseif heightMatchIconHPx then
            -- Height-matched: the EXACT basePhysIconH the height-match math computed. MUST match precisely so per-icon height stays in lockstep with the container's extraPixelsH distribution.
            iconH = heightMatchIconHPx * onePx
        else
            iconH = math.floor((barData.iconSize or 36) * ns.CdmCropFactor(barData) + 0.5)
        end
    end

    -- ALL icons in the array, not just IsShown: CollectAndReanchor already filtered to frames we claimed, and Blizzard toggles IsShown independently -- we position everything we own.
    local visibleIcons = icons
    local count = #visibleIcons
    -- Icon count is the sole sizing authority. The count==0 early return below preserves the last known size during transients (spec swap, pool churn).
    local sizeCount = count
    if count == 0 then
        -- The bar's rect stays deliberately stale here (transient
        -- protection), so tell the aura-custom tail the TRUE content extent
        -- is zero and let it re-anchor (it centers on the bar's position
        -- instead of appending to the frozen edge).
        frame._acLiveW, frame._acLiveH = 0, 0
        if ns._AuraCustomPoke then ns._AuraCustomPoke(barKey) end
        local curW = frame:GetWidth() or 0
        local curH = frame:GetHeight() or 0
        if curW <= 1 or curH <= 1 then
            local fallbackW, fallbackH = GetStableCDMBarSize(barKey, nil, barData)
            -- EMPTY_CDM_BAR_SIZE is a raw coord-space placeholder; without snapping, often-empty buff-family bars render at non-pixel-aligned heights (43.20 px vs 43) at non-perfect UI scales.
            fallbackW = SnapForScale(fallbackW, 1)
            fallbackH = SnapForScale(fallbackH, 1)
            frame:SetSize(fallbackW, fallbackH)
            frame._prevLayoutW = fallbackW
            frame._prevLayoutH = fallbackH
        end
        -- NEVER permanently hide containers on a transient count=0 (spec swaps, viewer pool churn): the next reanchor refills the bar, and hiding would need an explicit re-show that nothing guarantees.
        if frame._barBg then frame._barBg:Hide() end
        return
    end

    -- effRows is the EFFECTIVE row count: 1 while a custom top-row split's second row is empty, so the container never grows a blank row.
    local stride, effRows, customTopCount = ComputeTopRowStride(barData, sizeCount)

    -- Container size: compute in integer physical pixels, convert to coord at the end. Multiplying
    -- in coord space then snapping loses 1 phys px to float dust (3 * 21.6666... floors to 81 instead of 82), leaving the bottom icon protruding past the bar frame.
    local PP = EllesmereUI.PP
    local onePx = PP.mult
    local iconWPx  = math.floor(iconW  / onePx + 0.5)
    local iconHPx  = math.floor(iconH  / onePx + 0.5)
    local spacingPx = math.floor(spacing / onePx + 0.5)
    -- Lock iconW/iconH/spacing to exact physical pixel multiples. Positioning (stepW, stepH) uses
    -- these coord values while the width-match math uses the iconWPx/spacingPx integers; out of
    -- lockstep, icons drift sub-pixel as col index grows -- spacing appears to "shrink" and the final icon undershoots the width-match target by 1 px.
    iconW   = iconWPx  * onePx
    iconH   = iconHPx  * onePx
    spacing = spacingPx * onePx

    -- Per-row icon size offset (Number of Rows == 2, non-matched only): one row takes an Icon
    -- Scale pixel offset, the other keeps the base size. The match target is re-checked here (not
    -- just at the options gate) so a bar matched AFTER the toggle stays uniform. Rows are centered against each other; the larger row defines the bar's growth-axis extent.
    local perRowActive = false
    local rowWPx = { iconWPx, iconWPx }   -- [1] = top row, [2] = bottom row
    local rowHPx = { iconHPx, iconHPx }
    if effRows == 2 and not widthMatchTarget and not heightMatchTarget
       and customTopCount > 0 and (sizeCount - customTopCount) > 0
       and (barData.customTopRowSizeEnabled or barData.customBottomRowSizeEnabled) then
        local base = barData.iconSize or 36
        local function RowSizePx(sz)
            if sz < 16 then sz = 16 end          -- clamp to the Icon Scale minimum
            local wpx = math.floor(sz / onePx + 0.5)
            local hCoord = (shape == "cropped") and math.floor(sz * ns.CdmCropFactor(barData) + 0.5) or sz
            local hpx = math.floor(hCoord / onePx + 0.5)
            return wpx, hpx
        end
        if barData.customTopRowSizeEnabled then
            rowWPx[1], rowHPx[1] = RowSizePx(base + (barData.topRowSizeOffset or 0))
        else
            rowWPx[2], rowHPx[2] = RowSizePx(base + (barData.bottomRowSizeOffset or 0))
        end
        perRowActive = true
    end

    -- Minimum Bar Size: reserve growth-axis room for at least minSizeIcons icon slots so a bar that
    -- loses icons (spec/talent swap, shift-hidden cooldowns) keeps its footprint -- everything
    -- matching its width or anchored to its edges then stays put, and the icons still present are
    -- centered in the surplus. SKIPPED while the GROWTH axis is match-owned: that axis measures
    -- exactly what the match target dictates and padding it would overshoot. A match on the
    -- PERPENDICULAR axis is fine -- the growth axis still varies with icon count there.
    local growMatched
    if isHoriz then growMatched = widthMatchTarget else growMatched = heightMatchTarget end
    local resStride = growMatched and stride or ReserveStride(barData, stride)
    -- What resStride real icons measure at the BASE icon size, spacing included. Integer physical px like every other term here, so both bar edges stay on the pixel grid.
    local reservedPx = 0
    if resStride > stride then
        local basePx = isHoriz and iconWPx or iconHPx
        reservedPx = resStride * basePx + (resStride - 1) * spacingPx
    end
    -- Offset that centers the real icon block inside the surplus (uniform layout only; the per-row branch centers each row inside the total already).
    local padOffsetPx = 0

    local totalWPx, totalHPx
    if perRowActive then
        -- Two rows, independent icon sizes. Top row = customTopCount icons, the bottom takes the
        -- remainder. The bar spans the LARGER row along the growth axis and the SUM of both bands along the perpendicular axis.
        local topN = customTopCount
        local botN = sizeCount - topN
        if isHoriz then
            local topRowW = topN * rowWPx[1] + math.max(0, topN - 1) * spacingPx
            local botRowW = botN * rowWPx[2] + math.max(0, botN - 1) * spacingPx
            totalWPx = math.max(topRowW, botRowW)
            -- No pad offset needed: both rows are centered against totalWPx below, so growing it IS the centering.
            if reservedPx > totalWPx then totalWPx = reservedPx end
            totalHPx = rowHPx[1] + rowHPx[2] + spacingPx
        else
            local topColH = topN * rowHPx[1] + math.max(0, topN - 1) * spacingPx
            local botColH = botN * rowHPx[2] + math.max(0, botN - 1) * spacingPx
            totalHPx = math.max(topColH, botColH)
            if reservedPx > totalHPx then totalHPx = reservedPx end
            totalWPx = rowWPx[1] + rowWPx[2] + spacingPx
        end
    elseif isHoriz then
        totalWPx = stride  * iconWPx + (stride  - 1) * spacingPx + extraPixels
        totalHPx = effRows * iconHPx + (effRows - 1) * spacingPx + extraPixelsH
        if reservedPx > totalWPx then
            padOffsetPx = math.floor((reservedPx - totalWPx) / 2 + 0.5)
            totalWPx = reservedPx
        end
    else
        totalWPx = effRows * iconWPx + (effRows - 1) * spacingPx + extraPixels
        totalHPx = stride  * iconHPx + (stride  - 1) * spacingPx + extraPixelsH
        if reservedPx > totalHPx then
            padOffsetPx = math.floor((reservedPx - totalHPx) / 2 + 0.5)
            totalHPx = reservedPx
        end
    end

    -- Do NOT force an even totalWPx for CENTER grow: SnapCenterForDim (used by ApplyBarPositionCentered
    -- for CENTER-anchored frames) puts the center on a half-pixel grid for odd dimensions, so both
    -- edges already land on whole physical pixels. A forced +1 pads the frame 1 px wider than the icon layout -- visible as the unlock overlay overhanging the last icon.

    local totalW = totalWPx * onePx
    local totalH = totalHPx * onePx
    frame._acLiveW, frame._acLiveH = totalW, totalH
    -- Poke the aura-custom tail EVERY pass: an empty->occupied transition
    -- can land on the SAME total size (1 buff returning to a 1-wide stale
    -- rect), which fires no size/point event -- the tail would stay in its
    -- empty-centered mode underneath the returning real icon.
    if ns._AuraCustomPoke then ns._AuraCustomPoke(barKey) end

    -- SetSize is deferred to AFTER icon positioning (below) so icons and bar resize land on the
    -- same rendered frame. Positioning first is safe: icons use absolute offsets from TOPLEFT, not the frame's current dimensions.
    local unlockKey = "CDM_" .. barKey
    -- Freeze buff-family bar size during unlock mode so the mover overlay stays in sync (it doesn't dynamically resize with buff count).
    local skipResize = EllesmereUI._unlockActive and ns.IsBarBuffFamily(barData)


    -- Bar background
    if barData.barBgEnabled then
        if not frame._barBg then
            frame._barBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        end
        frame._barBg:ClearAllPoints()
        frame._barBg:SetPoint("TOPLEFT", 0, 0)
        frame._barBg:SetPoint("BOTTOMRIGHT", 0, 0)
        frame._barBg:SetColorTexture(barData.barBgR or 0, barData.barBgG or 0, barData.barBgB or 0, barData.barBgA or 0.5)
        frame._barBg:Show()
    elseif frame._barBg then
        frame._barBg:Hide()
    end

    -- Row growth "UP" (horizontal)/"LEFT" (vertical): reverse the VISUAL row order so the base
    -- (first data) row hugs the pinned trailing edge (BOTTOM/RIGHT) and extra rows grow away.
    -- Data-row semantics (fill order, per-row centering, icon counts, per-row sizes) are untouched
    -- -- only the perpendicular-axis offset flips. "DOWN"/"RIGHT" need no reversal: the TOPLEFT layout already keeps the pinned leading edge's row still.
    local rowsReversed = ns.CDMRowsReversed(barData)

    if perRowActive then
        -- Two-row layout with a per-row icon size offset: each row laid out at its own icon size,
        -- centered along the growth axis; the perpendicular axis stacks the two bands. No match extras -- gated off when matched.
        local isMouseBar = barData.anchorTo == "mouse"
        local topN = customTopCount
        for i, icon in ipairs(visibleIcons) do
            local iconScale = icon:GetScale() or 1
            if iconScale < 0.01 then iconScale = 1 end
            local iS = 1 / iconScale

            local rowIdx   = (i <= topN) and 1 or 2        -- 1 = top, 2 = bottom
            local idxInRow = (rowIdx == 1) and (i - 1) or (i - topN - 1)
            local rowN     = (rowIdx == 1) and topN or (sizeCount - topN)
            local wPx, hPx = rowWPx[rowIdx], rowHPx[rowIdx]

            FC(icon).matchExpanded = nil
            icon:SetSize(wPx * onePx * iS, hPx * onePx * iS)
            if blizzIcons then ns.CdmApplyBlizzIconArt(icon) end

            if isMouseBar then
                icon:SetFrameStrata("TOOLTIP")
                icon:SetFrameLevel(9980 + i)
            else
                icon:SetFrameStrata(barData.barStrata or "MEDIUM")
                icon:SetFrameLevel(5 + i)
            end
            icon:ClearAllPoints()

            local anchorX, anchorY
            if isHoriz then
                -- Growth axis = width (center the row within the bar width);
                -- perpendicular = height (top band, then bottom band).
                local rowMainPx = rowN * wPx + math.max(0, rowN - 1) * spacingPx
                local offMainPx = math.floor((totalWPx - rowMainPx) / 2 + 0.5)
                local xPx = offMainPx + idxInRow * (wPx + spacingPx)
                -- Reversed when rows grow upward: rowIdx 2 on top, 1 below.
                local yPx
                if rowsReversed then
                    yPx = (rowIdx == 2) and 0 or (rowHPx[2] + spacingPx)
                else
                    yPx = (rowIdx == 1) and 0 or (rowHPx[1] + spacingPx)
                end
                anchorX = (xPx * onePx) * iS
                anchorY = -(yPx * onePx) * iS
            else
                -- Growth axis = height (center the row within the bar height);
                -- perpendicular = width (left band, then right band).
                local rowMainPx = rowN * hPx + math.max(0, rowN - 1) * spacingPx
                local offMainPx = math.floor((totalHPx - rowMainPx) / 2 + 0.5)
                local yPx = offMainPx + idxInRow * (hPx + spacingPx)
                -- Reversed when columns grow leftward: rowIdx 2 at the left.
                local xPx
                if rowsReversed then
                    xPx = (rowIdx == 2) and 0 or (rowWPx[2] + spacingPx)
                else
                    xPx = (rowIdx == 1) and 0 or (rowWPx[1] + spacingPx)
                end
                anchorX = (xPx * onePx) * iS
                anchorY = -(yPx * onePx) * iS
            end

            local fd = _getFD(icon)
            if fd then
                fd._cdmAnchor = { "TOPLEFT", frame, "TOPLEFT", anchorX, anchorY }
            end
            icon:SetPoint("TOPLEFT", frame, "TOPLEFT", anchorX, anchorY)
        end
    else

    -- Uniform icon size: every bar except the 2-row per-row-size case above.
    local stepW = iconW + spacing
    local stepH = iconH + spacing
    -- Minimum Bar Size surplus in coord space: shifts the whole icon block along the GROWTH axis so it sits centered in the reserved footprint. 0 whenever the reservation is off or already filled.
    local padOffset = padOffsetPx * onePx

    local topRowCount = customTopCount
    if topRowCount < 0 then topRowCount = 0 end
    local bottomRowCount = #visibleIcons - topRowCount
    if bottomRowCount < 0 then bottomRowCount = 0 end

    -- Per-row centering: rows with fewer icons than stride get centered.
    local function RowIconCount(row)
        if row == 0 then return topRowCount end
        return bottomRowCount
    end

    -- Cursor-anchored bars need explicit icon strata: icons aren't parented to
    -- the container, so they don't inherit its TOOLTIP strata.
    local isMouseBar = barData.anchorTo == "mouse"

    -- Position each icon: fill bottom-up so bottom rows are full and the top row gets the
    -- remainder. "col"/"row" run along the bar's GROWTH axis -- horizontal: col = width-axis,
    -- row = height-axis; vertical: swapped. extraPixels expand iconW along the width axis for the
    -- first N icons; extraPixelsH expand iconH along the height axis. Only one match can be active, but the math handles both for symmetry.
    -- growthW = extras along the GROWTH axis (col index); growthH = extras along
    -- the PERPENDICULAR axis (row index).
    local growthW = isHoriz and extraPixels or extraPixelsH
    local growthH = isHoriz and extraPixelsH or extraPixels
    for i, icon in ipairs(visibleIcons) do
        -- Compensate for Blizzard's per-icon scale so visual size matches.
        local iconScale = icon:GetScale() or 1
        if iconScale < 0.01 then iconScale = 1 end
        local iS = 1 / iconScale

        -- Sequential index -> bottom-up grid position. Icons 1..topRowCount fill the top row (visual row 0); the rest fill rows 1..effRows-1.
        local col, row
        if i <= topRowCount then
            col = i - 1
            row = 0
        else
            local bottomIdx = i - topRowCount - 1
            col = bottomIdx % stride
            row = 1 + math.floor(bottomIdx / stride)
        end
        -- Visual row == data row unless row growth reverses the visual order (data row 0 renders on the pinned trailing edge). Data-row logic below (RowIconCount, expansion flags) keeps `row`.
        local vRow = rowsReversed and (effRows - 1 - row) or row

        -- +1 physical pixel on expanded icons: horizontal bars expand the WIDTH axis (iconW),
        -- vertical bars (col = height-axis) expand HEIGHT (iconH). Keeps icons square on the perpendicular axis.
        local onePx = PP.mult
        local expandedCol = (growthW > 0 and col < growthW)
        local expandedRow = (growthH > 0 and row < growthH)
        local thisIconW, thisIconH
        if isHoriz then
            thisIconW = expandedCol and (iconW + onePx) or iconW
            thisIconH = expandedRow and (iconH + onePx) or iconH
        else
            -- Vertical: col is the height-axis index, so col-extras expand iconH
            thisIconH = expandedCol and (iconH + onePx) or iconH
            thisIconW = expandedRow and (iconW + onePx) or iconW
        end
        FC(icon).matchExpanded = (expandedCol or expandedRow) or nil
        icon:SetSize(thisIconW * iS, thisIconH * iS)
        if blizzIcons then ns.CdmApplyBlizzIconArt(icon) end

        -- Cumulative offsets: each prior expanded icon shifts later icons by 1 physical pixel on
        -- the same axis (extraBefore = growth axis/col; extraBeforeR = perpendicular axis/row).
        -- extraBeforeR counts expanded rows VISUALLY before this one: expanded rows are data rows
        -- < growthH, so normal order has min(row, growthH) above, and reversed order has data rows in (row, effRows-1] above, of which max(0, min(growthH, effRows) - row - 1) are expanded.
        local extraBefore  = math.min(col, growthW) * onePx
        local extraBeforeR
        if rowsReversed then
            extraBeforeR = math.max(0, math.min(growthH, effRows) - row - 1) * onePx
        else
            extraBeforeR = math.min(row, growthH) * onePx
        end

        if isMouseBar then
            icon:SetFrameStrata("TOOLTIP")
            icon:SetFrameLevel(9980 + i)
        else
            icon:SetFrameStrata(barData.barStrata or "MEDIUM")
            icon:SetFrameLevel(5 + i)
        end
        icon:ClearAllPoints()

        local rowCount = RowIconCount(row)
        local rowHasLess = (rowCount > 0 and rowCount < stride)

        -- Offsets as absolute parent-space integers, divided by iconScale for SetPoint. NO per-position snapping: dividing integers by the same constant produces mathematically uniform gaps.
        local posX = col * stepW + extraBefore
        local posY = vRow * stepH

        -- Resolve anchor params first, then stamp fd._cdmAnchor BEFORE SetPoint: the SetPoint hook
        -- fires AFTER SetPoint and compares relativeTo against fd._cdmAnchor[2]; updated after, it
        -- reads a stale anchor (the previous bar) and snaps the icon ~50px wrong when moving a
        -- spell between bars. All growth directions use the same TOPLEFT icon layout; growth only affects which FRAME edge stays fixed during resize, never icon order.
        local anchorPt, anchorRelPt, anchorX, anchorY
        local rowOffset = 0
        if isHoriz then
            if rowHasLess then
                rowOffset = math.floor((stride - rowCount) * stepW / 2 + 0.5)
            end
            anchorPt, anchorRelPt = "TOPLEFT", "TOPLEFT"
            anchorX = (posX + rowOffset + padOffset) * iS
            anchorY = -(posY + extraBeforeR) * iS
        else
            if rowHasLess then
                rowOffset = math.floor((stride - rowCount) * stepH / 2 + 0.5)
            end
            anchorPt, anchorRelPt = "TOPLEFT", "TOPLEFT"
            anchorX = (vRow * stepW + extraBeforeR) * iS
            anchorY = -(col * stepH + extraBefore + rowOffset + padOffset) * iS
        end

        if anchorPt then
            -- Stamp BEFORE SetPoint so the synchronous hook sees the new anchor and treats our own SetPoint as a no-op.
            local fd = _getFD(icon)
            if fd then
                fd._cdmAnchor = { anchorPt, frame, anchorRelPt, anchorX, anchorY }
            end
            icon:SetPoint(anchorPt, frame, anchorRelPt, anchorX, anchorY)
        end
    end
    end  -- perRowActive vs uniform layout branch

    -- SetSize AFTER icon positioning: bar resize and icon placement land on the same rendered frame (no 1-frame size mismatch).
    if not skipResize then
        local oldW = frame:GetWidth() or 0
        local oldH = frame:GetHeight() or 0
        -- Pre-resize center in UIParent space, captured BEFORE SetSize (an edge-pointed frame
        -- moves its center when resized); the anchor offset upkeep below validates against it.
        -- Captured only when that upkeep can run (bar has an unlockAnchors entry): measuring a bar
        -- whose rect derives from a restricted tree HARD-ERRORS (FocusKick anchored to a nameplate
        -- in a locked instance), and such bars have no entry. pcall covers the residual case; an unknown center skips the upkeep.
        local oldCX, oldCY
        if EllesmereUIDB and EllesmereUIDB.unlockAnchors
           and EllesmereUIDB.unlockAnchors[unlockKey] then
            local ok, c1, c2 = pcall(frame.GetCenter, frame)
            if ok and c1 and c2 then
                local r = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
                oldCX, oldCY = c1 * r, c2 * r
            end
        end
        EllesmereUI._layoutBarResizing = unlockKey
        pcall(frame.SetSize, frame, totalW, totalH)
        EllesmereUI._layoutBarResizing = nil
        -- Anchor offset maintenance: a growth-direction resize shifts the center by delta/2 while
        -- the fixed edge stays put, so adjust the center-based anchor offset to keep the
        -- relationship on /reload. NOT a position write (positions save only via Save & Exit).
        -- Self-validating gate: the compensation is only correct when the PRE-resize center
        -- actually sat at the anchor-derived position (target center + stored offset on that
        -- axis). During a profile apply the bar still holds the OUTGOING profile's position while
        -- unlockAnchors carries the INCOMING offsets -- compensating that corrupts offsets
        -- cumulatively per swap, and layout passes can land before/inside/after any suppression
        -- window, so the position check is the only ordering-proof guard. A falsely skipped compensation costs at most one dw/2 nudge, fixed by the next reapply.
        local grow = barData.growDirection
        if grow and grow ~= "CENTER"
           and not EllesmereUI._unlockActive
           and not EllesmereUI._abAnchorSuppressed
           and (oldW >= 1 or oldH >= 1) then
            local adb = EllesmereUIDB and EllesmereUIDB.unlockAnchors
            local ai = adb and adb[unlockKey]
            if ai then
                local side = ai.side
                local PPo = EllesmereUI and EllesmereUI.PP
                local uiES = PPo and UIParent:GetEffectiveScale()
                local tCX, tCY
                if EllesmereUI.GetAnchorTargetCenterUI then
                    tCX, tCY = EllesmereUI.GetAnchorTargetCenterUI(unlockKey)
                end
                local TOL = 2  -- UI px; pixel-snap noise stays well under 1
                -- Width/height-matched bars: the match owns that axis, so the bar never
                -- legitimately self-resizes there. Any resize on a matched axis is the match
                -- (re)asserting the target's size -- the saved offset already corresponds to it, and compensating corrupts the offset by dw/2 per profile swap.
                local wMatched = EllesmereUIDB.unlockWidthMatch and EllesmereUIDB.unlockWidthMatch[unlockKey]
                local hMatched = EllesmereUIDB.unlockHeightMatch and EllesmereUIDB.unlockHeightMatch[unlockKey]
                -- Horizontal growth: adjust offsetX on TOP/BOTTOM anchors
                local dw = totalW - oldW
                if math.abs(dw) > 0.1 and (side == "TOP" or side == "BOTTOM")
                   and not wMatched
                   and oldCX and tCX
                   and math.abs(oldCX - (tCX + (ai.offsetX or 0))) <= TOL then
                    if grow == "RIGHT" then
                        ai.offsetX = ai.offsetX + dw / 2
                    elseif grow == "LEFT" then
                        ai.offsetX = ai.offsetX - dw / 2
                    end
                    if PPo and uiES then ai.offsetX = PPo.SnapForES(ai.offsetX, uiES) end
                end
                -- Vertical growth: adjust offsetY on LEFT/RIGHT anchors
                local dh = totalH - oldH
                if math.abs(dh) > 0.1 and (side == "LEFT" or side == "RIGHT")
                   and not hMatched
                   and oldCY and tCY
                   and math.abs(oldCY - (tCY + (ai.offsetY or 0))) <= TOL then
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

    -- FocusKick: re-anchor against the focus nameplate after every layout pass so the bar tracks size/icon-count changes from the options panel.
    if barKey == FOCUSKICK_BAR_KEY and ns.ApplyFocusKickAnchor then
        ns.ApplyFocusKickAnchor()
    end
end

-- Shift-Icons cd-state modes: write the per-frame shift-hidden flag (on the external FC table,
-- NEVER the Blizzard frame) and, ONLY on a value change, relayout that bar so remaining icons
-- close the gap. Deferred to a clean execution context: callers run inside SetDesaturated hooks/
-- the Fake-Active poll, where LayoutCDMBar's SetSize/SetPoint could propagate taint (same pattern
-- as the _visHidden relayout in _CDMApplyVisibility). Coalesced per bar; steady-state calls return immediately.
--
-- Growth-edge preservation is LOCAL to this relayout call: capture the fixed growth edge before
-- LayoutCDMBar and, if the resize moved it, translate the frame back through whatever point it
-- already has (offset-only SetPoint on the existing point/relTo -- no ClearAllPoints, no DB
-- writes, no anchor-system calls). A non-CENTER-grow bar's persistent point normally IS its fixed
-- growth edge (delta 0, frame untouched); this only corrects bars whose point is center/corner-
-- based at that moment (anchored bars mid-cascade, first-row corner pins, legacy CENTER
-- positions). Anchored bars still get their deferred anchor batch reapply afterwards (OnSizeChanged fired during LayoutCDMBar), which remains authoritative.
ns._cdShiftLayoutPending = {}
function ns.SetCdStateShiftHidden(fc, shiftHidden)
    shiftHidden = shiftHidden or false
    if (fc._cdStateShiftHidden or false) == shiftHidden then return end
    fc._cdStateShiftHidden = shiftHidden
    -- Overflow-diverted frames render on the target bar, so the gap-close relayout must hit the
    -- bar the frame is actually laid out on. Normally unreachable for diverted frames (Phase 3b's no-op rule), but a one-reanchor window exists after a shift effect is first configured.
    local bk = fc._overflowLayoutBar or fc.barKey
    if not bk or ns._cdShiftLayoutPending[bk] then return end
    ns._cdShiftLayoutPending[bk] = true
    C_Timer.After(0, function()
        ns._cdShiftLayoutPending[bk] = nil
        local frame = cdmBarFrames[bk]
        local bd = barDataByKey[bk]
        local grow = bd and bd.growDirection or "CENTER"
        local fixedEdge
        if frame and grow ~= "CENTER"
           and not frame._mouseTrack and bk ~= ns.FOCUSKICK_BAR_KEY
           and not EllesmereUI._unlockActive
           and frame:GetNumPoints() == 1 then
            if grow == "LEFT" then fixedEdge = frame:GetRight()
            elseif grow == "RIGHT" then fixedEdge = frame:GetLeft()
            elseif grow == "UP" then fixedEdge = frame:GetBottom()
            elseif grow == "DOWN" then fixedEdge = frame:GetTop() end
        end
        LayoutCDMBar(bk)
        if fixedEdge then
            local newEdge
            if grow == "LEFT" then newEdge = frame:GetRight()
            elseif grow == "RIGHT" then newEdge = frame:GetLeft()
            elseif grow == "UP" then newEdge = frame:GetBottom()
            else newEdge = frame:GetTop() end
            local d = newEdge and (newEdge - fixedEdge)
            if d and (d > 0.25 or d < -0.25) then
                local point, relTo, relPoint, x, y = frame:GetPoint(1)
                if point then
                    if grow == "LEFT" or grow == "RIGHT" then
                        x = (x or 0) - d
                    else
                        y = (y or 0) - d
                    end
                    frame:SetPoint(point, relTo or frame:GetParent(), relPoint, x, y)
                end
            end
        end
    end)
end

-------------------------------------------------------------------------------
--  Toggle Blizzard CDM Settings. Hides the EllesmereUI options panel first so
--  the Blizzard UI is visible. NEVER call SetCurrentCategories /
--  SetDisplayMode / ClearDisplayCategories after opening -- those taint the
--  CDM frame pool (so isBuff cannot actually select a tab).
-------------------------------------------------------------------------------
local function OpenBlizzardCDMTab(isBuff)
    if not CooldownViewerSettings then return end
    if EllesmereUI._mainFrame and EllesmereUI._mainFrame:IsShown() then
        EllesmereUI._mainFrame:Hide()
    end
    if CooldownViewerSettings:IsShown() then
        CooldownViewerSettings:Hide()
    else
        CooldownViewerSettings:Show()
    end
end
ns.OpenBlizzardCDMTab = OpenBlizzardCDMTab

-------------------------------------------------------------------------------
--  CDM Tooltip System
--  No OnUpdate polling: Blizzard viewer frames handle their own tooltips via
--  native OnEnter; custom injected frames (item presets, racials, custom
--  spells) get OnEnter/OnLeave scripts in DecorateFrame / preset creation.
-------------------------------------------------------------------------------
local _tooltipBars = {}  -- [barKey] = true for bars with tooltips enabled
local _tooltipFrame = CreateFrame("Frame")
_tooltipFrame:Hide()

local function ApplyCDMTooltipState(barKey)
    local bd = barDataByKey[barKey]
    local enabled = bd and bd.showTooltip
    if enabled then
        _tooltipBars[barKey] = true
    else
        _tooltipBars[barKey] = nil
        -- Clear a tooltip showing for an icon on this bar
        if _tooltipCurrentIcon then
            local sfc = _ecmeFC[_tooltipCurrentIcon]
            if sfc and sfc.barKey == barKey then
                GameTooltip:Hide()
                _tooltipCurrentIcon = nil
            end
        end
    end
    -- Mouse-motion follows the tooltip setting. A motion-enabled icon with no unit becomes the
    -- mouseover-focus frame and steals hover from unit frames underneath (raid frame hover
    -- highlight and [@mouseover] casts die wherever a bar overlaps them), so icons may ONLY
    -- capture the mouse when tooltips are on. Cursor-anchored bars stay fully mouse-through
    -- (SetFrameClickThrough owns their state); vis-hidden bars stay inert. Mouse calls on Blizzard CDM frames are blocked in combat.
    if not InCombatLockdown() then
        local frame = cdmBarFrames[barKey]
        local wantHover = (enabled and frame and not frame._mouseTrack
            and not frame._visHidden) and true or false
        local icons = cdmBarIcons[barKey]
        if icons then
            for i = 1, #icons do
                local ic = icons[i]
                if ic and ic.EnableMouseMotion then
                    -- Invisible placeholders and Empty Slots are excluded even with
                    -- tooltips on: a slot with no art has nothing to hover, so
                    -- capturing here would only take mouseover away from whatever
                    -- the bar sits over.
                    ic:EnableMouseMotion(wantHover and not ic._isEmptySlotFrame
                        and not IsPlaceholderRenderHidden(ic, bd))
                end
            end
        end
    end
    -- Global tooltip frame follows whether ANY bar wants tooltips
    if next(_tooltipBars) then
        _tooltipFrame:Show()
    else
        _tooltipFrame:Hide()
    end
end
ns.ApplyCDMTooltipState = ApplyCDMTooltipState

I.ApplyBarPositionCentered = ApplyBarPositionCentered
I.ApplyCDMTooltipState, I.BuildCDMBar = ApplyCDMTooltipState, BuildCDMBar
I.ComputeTopRowStride, I.GetStableCDMBarSize = ComputeTopRowStride, GetStableCDMBarSize
I.LayoutCDMBar, I.ReserveStride = LayoutCDMBar, ReserveStride
I.SaveCDMBarPosition = SaveCDMBarPosition
I.OpenBlizzardCDMTab = OpenBlizzardCDMTab
I.broken = false
