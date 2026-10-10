if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CooldownManager_Options\LivePreview_Options.lua
--  Cooldown Manager options: the interactive bar preview in the content header
--  of the CDM Bars page (BuildCDMLivePreview). Definitions only; the shared
--  helpers come from ns._CDMO_OptEnv (filled by EUI_CooldownManager_Options.lua).
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
if not ns then return end  -- module disabled: no options page

--- Build the live CDM bar preview in the content header (interactive)
local function BuildCDMLivePreview(parent, yOff)
    local env = ns._CDMO_OptEnv
    local _cdmActivePreviewOn, DB, FONT_PATH, GetCDMOptOutline = env._cdmActivePreviewOn, env.DB, env.FONT_PATH, env.GetCDMOptOutline
    local NormalizeToBase, optState, PP, Refresh = env.NormalizeToBase, env.optState, env.PP, env.Refresh
    local RefreshCDPreview, ResolveIconArt, ResolveToLive, SelectedCDMBar = env.RefreshCDPreview, env.ResolveIconArt, env.ResolveToLive, env.SelectedCDMBar
    local SetPVFont, StartActiveStatePreview, StopActiveStatePreview, UpdateCDMPreviewAndResize = env.SetPVFont, env.StartActiveStatePreview, env.StopActiveStatePreview, env.UpdateCDMPreviewAndResize
    local p = DB()
    if not p or not p.cdmBars then return 0 end

    local barData = SelectedCDMBar()
    if not barData then return 0 end

    local barKey = barData.key
    local PAD = EllesmereUI.CONTENT_PAD or 10

    -- Create preview container scale to match real in-game icon sizes
    local previewScale = UIParent:GetEffectiveScale() / parent:GetEffectiveScale()
    local localParentW = (parent:GetWidth() - PAD * 2) / previewScale
    local initH = (barData.iconSize or 36) + 10

    -- Max visible height for the preview area (in parent-space pixels)
    local PREVIEW_MAX_H = 200

    -- Wrapper frame at parent scale; holds the scroll frame and scrollbar
    local wrapper = CreateFrame("Frame", nil, parent)
    wrapper:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, yOff)
    wrapper:SetSize(parent:GetWidth() - PAD * 2, PREVIEW_MAX_H)
    wrapper:SetClipsChildren(true)

    local pf = CreateFrame("Frame", nil, parent)
    pf:SetClipsChildren(false)
    pf:SetScale(previewScale)
    pf:SetSize(localParentW, initH)

    local sf = CreateFrame("ScrollFrame", nil, wrapper)
    sf:SetAllPoints()
    sf:SetScrollChild(pf)
    sf:EnableMouseWheel(true)

    local UpdatePVThumb = EllesmereUI.AttachSmoothScrollbar(sf, {
        step = 40, thumbMin = 20, trackParent = wrapper, topInset = 2, level = 5, panelWheel = true })

    -- Store refs for height management after Update()
    pf._wrapper = wrapper
    pf._scrollFrame = sf
    pf._previewScale = previewScale
    pf._PREVIEW_MAX_H = PREVIEW_MAX_H
    pf._updatePVThumb = UpdatePVThumb

    -- Pixel-snap helper for the preview's effective scale
    local function Snap(val)
        local s = pf:GetEffectiveScale()
        return math.floor(val * s + 0.5) / s
    end

    -- Bar background texture (shown when barBgEnabled)
    local pvBarBg = pf:CreateTexture(nil, "BACKGROUND", nil, -8)
    pvBarBg:SetColorTexture(0, 0, 0, 0.4)  -- default; updated in refresh
    if pvBarBg.SetSnapToPixelGrid then pvBarBg:SetSnapToPixelGrid(false); pvBarBg:SetTexelSnappingBias(0) end
    pvBarBg:Hide()

    -- Interactive preview icon slots
    local MAX_PREVIEW_ICONS = 30
    local previewSlots = {}

    -- Display-only dedupe for buff bars. assignedSpells can hold a LEGACY  -- eui-style: allow comment-budget
    -- duplicate: the SAME tracked buff stored under two different spell ids (e.g.
    -- its spellID and one of its linkedSpellIDs). They are NOT base/override
    -- variants -- the link is that both ids resolve to the same Blizzard
    -- cooldownID. BOTH ids must stay in the data (routing depends on them), so
    -- collapse them in the PREVIEW only: one slot per cooldownID, remembering which
    -- assignedSpells index/indices each slot covers (for edit + remove). With no
    -- dupes this is the raw list 1:1. spellID -> cooldownID depends only on
    -- talents, so it is stable per spec: build ONCE per spec from the static
    -- category sets (spellID + overrideSpellID + linkedSpellIDs, covering buffs
    -- currently down) and reuse across refreshes. Private local fed ONLY into the
    -- dedupe -- nothing writes assignedSpells, the route map, or live frames, and
    -- the scan never runs during gameplay (pf.Update only runs with options open).
    local _buffIdToCd, _buffIdToCdSpec = nil, nil
    local function GetBuffIdToCdid()
        local specKey = (ns.GetActiveSpecKey and ns.GetActiveSpecKey()) or "?"
        if _buffIdToCdSpec == specKey then return _buffIdToCd end
        _buffIdToCdSpec = specKey
        local map
        local gcs = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
        local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
        if gcs and gci then
            -- 0-8 covers every Midnight CooldownViewerCategory value; the
            -- Hidden pseudo-categories are negative and excluded by the range.
            for cat = 0, 8 do
                local ids = gcs(cat, true)
                if ids then
                    for _, cdID in ipairs(ids) do
                        local info = gci(cdID)
                        if info then
                            map = map or {}
                            if type(info.spellID) == "number" and info.spellID > 0 then map[info.spellID] = cdID end
                            if type(info.overrideSpellID) == "number" and info.overrideSpellID > 0 then map[info.overrideSpellID] = cdID end
                            if info.linkedSpellIDs then
                                for _, l in ipairs(info.linkedSpellIDs) do
                                    if type(l) == "number" and l > 0 then map[l] = cdID end
                                end
                            end
                        end
                    end
                end
            end
        end
        _buffIdToCd = map
        return map
    end

    local function BuildBuffDisplayDedup(raw)
        local idToCd = GetBuffIdToCdid()
        local dispList, dispGroups, slotOf = {}, {}, {}
        for rawIdx = 1, #raw do
            local sid = raw[rawIdx]
            -- Group by cooldownID when the id maps to a tracked buff; otherwise the
            -- entry stands alone (its own slot, keyed by the spell id).
            local cd = idToCd and idToCd[sid]
            local key = cd or ("s" .. tostring(sid))
            local at = slotOf[key]
            if at then
                local g = dispGroups[at]; g[#g + 1] = rawIdx
            else
                dispList[#dispList + 1] = sid
                dispGroups[#dispList] = { rawIdx }
                slotOf[key] = #dispList
            end
        end
        return dispList, dispGroups
    end

    -- Preview display index -> underlying assignedSpells index for buff bars
    -- that collapsed a duplicate (identity when there are no dupes / not a buff bar).
    local function BuffDataIdx(displayIdx)
        local g = pf._buffDispGroups and pf._buffDispGroups[displayIdx]
        return (g and g[1]) or displayIdx
    end

    -- Drag state
    local dragSlot, dragIdx, dragGhost
    local insertIdx = nil
    local lastInsertIdx = nil
    local dragMode = nil      -- "swap" or "insert"
    local swapTargetIdx = nil -- index of icon being swapped with
    local dragEndTime = 0 -- GetTime() when drag finished, suppresses OnClick

    local function EnsureDragGhost()
        if dragGhost then return dragGhost end
        local g = CreateFrame("Frame", nil, UIParent)
        g:SetFrameStrata("TOOLTIP")
        g:SetSize(36, 36)
        g:SetAlpha(0.7)
        local tex = g:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        g._icon = tex
        g:Hide()
        dragGhost = g
        return g
    end

    -- Insertion line indicator (vertical accent line between icons)
    local insertLine = pf:CreateTexture(nil, "OVERLAY", nil, 7)
    local eg = EllesmereUI.ELLESMERE_GREEN
    insertLine:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
    insertLine:SetWidth(2)
    insertLine:Hide()

    -- Animation: each slot has _targetOffX, _currentOffX; lerped inside drag OnUpdate
    local ANIM_SPEED = 48
    local animRunning = false

    local function StopAnimTicker()
        animRunning = false
    end

    local function StartAnimTicker()
        animRunning = true
    end

    local function TickAnimation(dt)
        if not animRunning then return end
        local allDone = true
        for i = 1, MAX_PREVIEW_ICONS do
            local s = previewSlots[i]
            if s and s._targetOffX and s._currentOffX then
                local diff = s._targetOffX - s._currentOffX
                if math.abs(diff) < 0.3 then
                    s._currentOffX = s._targetOffX
                else
                    s._currentOffX = s._currentOffX + diff * math.min(ANIM_SPEED * dt, 1)
                    allDone = false
                end
                if s._baseX then
                    s:ClearAllPoints()
                    PP.Point(s, "TOPLEFT", pf, "TOPLEFT", s._baseX + s._currentOffX, s._baseY)
                end
            end
        end
        if allDone then animRunning = false end
    end

    local function ClearInsertIndicator()
        insertLine:Hide()
        insertIdx = nil
        lastInsertIdx = nil
        -- Clear swap highlight
        if swapTargetIdx then
            local s = previewSlots[swapTargetIdx]
            if s and s._hlBrd then
                s._hlBrd:Hide()
            end
            swapTargetIdx = nil
        end
        dragMode = nil
        -- Reset all slot offsets (snap, no animation)
        StopAnimTicker()
        for i = 1, MAX_PREVIEW_ICONS do
            local s = previewSlots[i]
            if s and s._baseX then
                s._targetOffX = 0
                s._currentOffX = 0
                s:ClearAllPoints()
                PP.Point(s, "TOPLEFT", pf, "TOPLEFT", s._baseX, s._baseY)
            end
        end
    end

    --- Find drag target: swap (centered on icon) or insert (between icons)
    --- Returns mode ("swap"/"insert"), targetIdx
    --- cx, cy are in screen units (GetCursorPosition / UIParent:GetEffectiveScale)
    local function FindDragTarget(cx, cy, slotCount, fromIdx)
        local bd = SelectedCDMBar()
        if not bd then return nil, nil end
        local iconSz = bd.iconSize or 36
        -- Match the preview render: width-matched bars use a fixed icon size.
        if EllesmereUI.GetWidthMatchTarget and EllesmereUI.GetWidthMatchTarget("CDM_" .. bd.key) then iconSz = 36 end
        local spacing = bd.spacing or 2
        -- Preview always renders left-to-right regardless of bar growDirection,
        -- so drag logic must also use left-to-right ordering.
        local growLeft = false

        -- Convert cursor from screen units to pf-local units
        local pfES = pf:GetEffectiveScale()
        local uiES = UIParent:GetEffectiveScale()
        local rawCX = cx * uiES
        local rawCY = cy * uiES
        local rawPfL = pf:GetLeft() * pfES
        local rawPfT = pf:GetTop() * pfES
        local localX = (rawCX - rawPfL) / pfES
        local localY = -((rawPfT - rawCY) / pfES)

        -- Group slots into rows by _baseY
        local bestRowStart, bestRowEnd, bestRowDist = 1, slotCount, math.huge
        local rowsByY = {}
        for i = 1, slotCount do
            local s = previewSlots[i]
            if s and s:IsShown() and s._baseY then
                local yKey = math.floor(s._baseY * 10 + 0.5)
                if not rowsByY[yKey] then rowsByY[yKey] = { y = s._baseY, startIdx = i, endIdx = i }
                else rowsByY[yKey].endIdx = i end
            end
        end
        for _, row in pairs(rowsByY) do
            local rowCenterY = row.y - iconSz / 2
            local d = math.abs(localY - rowCenterY)
            if d < bestRowDist then
                bestRowDist = d; bestRowStart = row.startIdx; bestRowEnd = row.endIdx
            end
        end

        -- Check Y range
        local refSlot = previewSlots[bestRowStart]
        if not refSlot or not refSlot:IsShown() or not refSlot._baseY then return nil, nil end
        if localY > refSlot._baseY + iconSz * 0.5 or localY < refSlot._baseY - iconSz * 1.5 then return nil, nil end

        -- Build a list of slots in this row sorted by visual X (left to right on screen).
        -- With growLeft, slot indices are reversed relative to screen X order.
        local rowSlots = {}
        for i = bestRowStart, bestRowEnd do
            local s = previewSlots[i]
            if s and s:IsShown() and s._baseX then
                rowSlots[#rowSlots + 1] = { slot = s, idx = i }
            end
        end
        -- Sort by _baseX ascending (left to right on screen)
        table.sort(rowSlots, function(a, b) return a.slot._baseX < b.slot._baseX end)

        local swapZone = iconSz * 0.2
        local blankSwapZone = iconSz * 0.45

        -- If cursor is before the leftmost slot on screen, insert at the logical start of that side
        local firstEntry = rowSlots[1]
        if firstEntry and localX < firstEntry.slot._baseX - spacing * 0.5 then
            if growLeft then
                return "insert", firstEntry.idx + 1
            else
                return "insert", firstEntry.idx
            end
        end

        for vi = 1, #rowSlots do
            local entry = rowSlots[vi]
            local s = entry.slot
            local i = entry.idx
            local slotL = s._baseX
            local slotR = slotL + iconSz
            local slotCX = slotL + iconSz / 2
            local isBlank = not s._icon or not s._icon:GetTexture()
            local zone = isBlank and blankSwapZone or swapZone
            if localX >= slotL - spacing * 0.5 and localX < slotR + spacing * 0.5 then
                if i ~= fromIdx and math.abs(localX - slotCX) < zone then
                    return "swap", i
                elseif localX < slotCX then
                    -- Cursor in the left half of this slot: insert before it logically
                    if growLeft then
                        return "insert", i + 1
                    else
                        return "insert", i
                    end
                else
                    -- Cursor in the right half of this slot: insert after it logically
                    if growLeft then
                        return "insert", i
                    else
                        return "insert", i + 1
                    end
                end
            end
        end

        -- Past the rightmost slot on screen: insert at the logical end of that side
        local lastEntry = rowSlots[#rowSlots]
        if lastEntry then
            if growLeft then
                return "insert", lastEntry.idx
            else
                return "insert", lastEntry.idx + 1
            end
        end
        return "insert", bestRowEnd + 1
    end

    --- Apply visual feedback for drag: shift icons for insert, highlight for swap
    local function ApplyDragFeedback(mode, targetIdx, fromIdx, slotCount)
        local bd = SelectedCDMBar()
        -- Preview always renders left-to-right; drag feedback must match.
        local growLeft = false

        if mode == "swap" then
            insertLine:Hide()
            if swapTargetIdx and swapTargetIdx ~= targetIdx then
                local s = previewSlots[swapTargetIdx]
                if s and s._hlBrd then s._hlBrd:Hide() end
            end
            if lastInsertIdx then
                for i = 1, slotCount do
                    local s = previewSlots[i]
                    if s and s._baseX then
                        s._targetOffX = 0
                        if not s._currentOffX then s._currentOffX = 0 end
                        if i ~= fromIdx then s:SetAlpha(1) end
                    end
                end
                StartAnimTicker()
                lastInsertIdx = nil
            end
            swapTargetIdx = targetIdx
            local s = previewSlots[targetIdx]
            if s and s._hlBrd then s._hlBrd:Show() end
            return
        end

        -- Insert mode: clear swap highlight first
        if swapTargetIdx then
            local s = previewSlots[swapTargetIdx]
            if s and s._hlBrd then s._hlBrd:Hide() end
            swapTargetIdx = nil
        end

        if targetIdx == lastInsertIdx then return end
        lastInsertIdx = targetIdx

        if not bd then return end
        local iconSz = bd.iconSize or 36
        -- Match the preview render: width-matched bars use a fixed icon size.
        if EllesmereUI.GetWidthMatchTarget and EllesmereUI.GetWidthMatchTarget("CDM_" .. bd.key) then iconSz = 36 end
        local spacing = bd.spacing or 2
        local nudge = math.floor((iconSz + spacing) * 0.15)

        -- With growLeft, higher index = further left on screen.
        -- Flip nudge direction so slots shift away from the gap correctly.
        local shiftTowardEnd   =  nudge
        local shiftTowardStart = -nudge
        if growLeft then
            shiftTowardEnd   = -nudge
            shiftTowardStart =  nudge
        end

        -- Determine which row the target belongs to (by _baseY).
        -- Only shift slots on that row; other rows stay still.
        local targetRowY = nil
        if targetIdx >= 1 and targetIdx <= slotCount then
            local ts = previewSlots[targetIdx]
            if ts and ts._baseY then targetRowY = ts._baseY end
        end
        -- Fallback: check the slot just before targetIdx (insert at end of row)
        if not targetRowY and targetIdx > 1 and targetIdx - 1 <= slotCount then
            local ts = previewSlots[targetIdx - 1]
            if ts and ts._baseY then targetRowY = ts._baseY end
        end

        for i = 1, slotCount do
            local s = previewSlots[i]
            if not s or not s._baseX then
                if s then s:SetAlpha(i == fromIdx and 0.3 or 1) end
            elseif i == fromIdx then
                s:SetAlpha(0.3)
                s._targetOffX = 0
                if not s._currentOffX then s._currentOffX = 0 end
            else
                -- Only shift slots on the same row as the target
                local onTargetRow = targetRowY and s._baseY and math.abs(s._baseY - targetRowY) < 1
                if not onTargetRow then
                    s._targetOffX = 0
                    if not s._currentOffX then s._currentOffX = 0 end
                    s:SetAlpha(1)
                else
                    local virtualPos = i
                    if i > fromIdx then virtualPos = i - 1 end
                    local virtualInsert = targetIdx
                    if targetIdx > fromIdx then virtualInsert = targetIdx - 1 end

                    local offX = 0
                    if virtualPos >= virtualInsert then
                        offX = shiftTowardEnd
                    else
                        offX = shiftTowardStart
                    end

                    s._targetOffX = offX
                    if not s._currentOffX then s._currentOffX = 0 end
                    s:SetAlpha(1)
                end
            end
        end
        StartAnimTicker()

        -- Position the insertion line between the two logical neighbors
        if targetIdx and targetIdx >= 1 then
            local iconSz2 = iconSz
            local leftSlot, rightSlot  -- screen-left, screen-right
            if growLeft then
                -- With growLeft, slot targetIdx is to the right on screen, slot targetIdx-1 is to the left
                if targetIdx > 1 and targetIdx <= slotCount then
                    rightSlot = previewSlots[targetIdx]
                    leftSlot  = previewSlots[targetIdx - 1]
                    if targetIdx == fromIdx and targetIdx + 1 <= slotCount then
                        rightSlot = previewSlots[targetIdx + 1]
                    elseif targetIdx - 1 == fromIdx and targetIdx - 2 >= 1 then
                        leftSlot = previewSlots[targetIdx - 2]
                    end
                elseif targetIdx <= 1 then
                    rightSlot = previewSlots[1]
                elseif targetIdx > slotCount then
                    leftSlot = previewSlots[slotCount]
                end
            else
                if targetIdx > 1 and targetIdx <= slotCount then
                    leftSlot  = previewSlots[targetIdx - 1]
                    rightSlot = previewSlots[targetIdx]
                    if targetIdx - 1 == fromIdx and targetIdx - 2 >= 1 then
                        leftSlot = previewSlots[targetIdx - 2]
                    elseif targetIdx == fromIdx and targetIdx + 1 <= slotCount then
                        rightSlot = previewSlots[targetIdx + 1]
                    end
                elseif targetIdx <= 1 then
                    rightSlot = previewSlots[1]
                elseif targetIdx > slotCount and slotCount > 0 then
                    leftSlot = previewSlots[slotCount]
                end
            end

            local lineX, lineY
            if leftSlot and leftSlot:IsShown() and leftSlot._baseX
               and rightSlot and rightSlot:IsShown() and rightSlot._baseX then
                local leftRight = leftSlot._baseX + iconSz2 - nudge
                local rightLeft = rightSlot._baseX + nudge
                lineX = (leftRight + rightLeft) / 2
                lineY = rightSlot._baseY
            elseif rightSlot and rightSlot:IsShown() and rightSlot._baseX then
                lineX = rightSlot._baseX + nudge - math.floor(spacing / 2) - 1
                lineY = rightSlot._baseY
            elseif leftSlot and leftSlot:IsShown() and leftSlot._baseX then
                lineX = leftSlot._baseX + iconSz2 - nudge + math.floor(spacing / 2) + 1
                lineY = leftSlot._baseY
            end

            if lineX and lineY then
                insertLine:ClearAllPoints()
                PP.Point(insertLine, "TOP", pf, "TOPLEFT", lineX, lineY)
                PP.Point(insertLine, "BOTTOM", pf, "TOPLEFT", lineX, lineY - iconSz2)
                insertLine:Show()
            else
                insertLine:Hide()
            end
        else
            insertLine:Hide()
        end
    end

    local function CreatePreviewSlot(idx)
        local slot = CreateFrame("Button", nil, pf)
        slot:SetSize(1, 1)
        slot:RegisterForClicks("LeftButtonUp", "RightButtonDown", "MiddleButtonDown")
        -- Expand hit area so small icons are easier to click/drag
        slot:SetHitRectInsets(-6, -6, -6, -6)
        slot:Hide()

        local sBg = slot:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints(); sBg:SetColorTexture(0.08, 0.08, 0.08, 0.6)
        if sBg.SetSnapToPixelGrid then sBg:SetSnapToPixelGrid(false); sBg:SetTexelSnappingBias(0) end
        slot._bg = sBg

        local sIcon = slot:CreateTexture(nil, "ARTWORK")
        sIcon:SetAllPoints()
        if sIcon.SetSnapToPixelGrid then sIcon:SetSnapToPixelGrid(false); sIcon:SetTexelSnappingBias(0) end
        slot._icon = sIcon
        slot._tex = sIcon  -- alias for shape system compatibility

        local sEdges = {}
        local PP = EllesmereUI and EllesmereUI.PP
        if PP then PP.CreateBorder(slot, 0, 0, 0, 1, 1, "OVERLAY", 7) end
        slot._edges = sEdges  -- empty; borders managed by PP

        -- Hosted-buff marker border: gold (same color as the buff "+" add button), same 2px
        -- geometry as the hover highlight, always ON for buff icons hosted on this CD/utility
        -- bar so they read apart from the cooldowns at a glance. Level +1 -- UNDER the hover highlight (+2), so hovering still shows the accent border on top.
        local slotPP = EllesmereUI and EllesmereUI.PP
        local slotHostCont = CreateFrame("Frame", nil, slot)
        slotHostCont:SetAllPoints()
        slotHostCont:SetFrameLevel(slot:GetFrameLevel() + 1)
        local hostBrd = slotPP and slotPP.CreateBorder(slotHostCont, 1, 0.82, 0.25, 1, 2, "OVERLAY", 7)
        if hostBrd then hostBrd:Hide() end
        slot._hostBrd = hostBrd
        -- Hover highlight (2px accent border, child container avoids conflict with existing PP border)
        local eg = EllesmereUI.ELLESMERE_GREEN
        local slotHlCont = CreateFrame("Frame", nil, slot)
        slotHlCont:SetAllPoints()
        slotHlCont:SetFrameLevel(slot:GetFrameLevel() + 2)
        local slotBrd = slotPP and slotPP.CreateBorder(slotHlCont, eg.r, eg.g, eg.b, 1, 2, "OVERLAY", 7)
        if slotBrd then slotBrd:Hide() end
        slot._hlBrd = slotBrd
        -- Text overlay (renders above border)
        local pvTextOvr = CreateFrame("Frame", nil, slot)
        pvTextOvr:SetAllPoints(slot)
        -- +5: the keybind badge sits two levels under this overlay (+3/+4),
        -- above the slot border (+1) and the hosted-buff marker (+2).
        pvTextOvr:SetFrameLevel(slot:GetFrameLevel() + 5)
        pvTextOvr:EnableMouse(false)
        slot._pvTextOverlay = pvTextOvr

        slot._stackText = pvTextOvr:CreateFontString(nil, "OVERLAY")
        SetPVFont(slot._stackText, FONT_PATH, 11)
        slot._stackText:SetPoint("BOTTOMRIGHT", pvTextOvr, "BOTTOMRIGHT", 0, 2)
        slot._stackText:SetJustifyH("RIGHT")
        slot._stackText:Hide()
        local stackTxt = slot._stackText

        -- Keybind text (mirrors _keybindText on real CDM icons)
        local kbTxt = pvTextOvr:CreateFontString(nil, "OVERLAY")
        SetPVFont(kbTxt, FONT_PATH, 9)
        kbTxt:SetPoint("TOPLEFT", pvTextOvr, "TOPLEFT", 2, -2)
        kbTxt:SetJustifyH("LEFT")
        kbTxt:Hide()
        slot._keybindText = kbTxt

        slot:SetScript("OnEnter", function()
            if dragSlot then return end
            local bdHov = SelectedCDMBar()
            -- Custom shapes: tint the shape border instead of square edges
            if slot._shapeBorder and slot._shapeBorder:IsShown() then
                slot._shapeBorder:SetVertexColor(eg.r, eg.g, eg.b, 1)
            else
                if slotBrd then slotBrd:Show() end
            end
        end)
        slot:SetScript("OnLeave", function()
            if dragSlot then return end
            local bdHov = SelectedCDMBar()
            if slot._shapeBorder and slot._shapeBorder:IsShown() then
                if slot._previewHostedBuff then
                    -- Hosted buff: restore the persistent gold tint, not
                    -- the bar border color.
                    slot._shapeBorder:SetVertexColor(1, 0.82, 0.25, 1)
                else
                    local bR, bG, bB = 0, 0, 0
                    if bdHov then
                        bR, bG, bB = bdHov.borderR or 0, bdHov.borderG or 0, bdHov.borderB or 0
                        if bdHov.borderClassColor then
                            local _, ct = UnitClass("player")
                            if ct then
                                local cc = RAID_CLASS_COLORS[ct]
                                if cc then bR, bG, bB = cc.r, cc.g, cc.b end
                            end
                        end
                    end
                    slot._shapeBorder:SetVertexColor(bR, bG, bB, 1)
                end
            else
                if slotBrd then slotBrd:Hide() end
            end
        end)

        slot._slotIdx = idx

        -- Right-click: spell picker to replace; Middle-click: remove
        -- Default buff bar: no interaction (Blizzard controls the list)
        slot:SetScript("OnClick", function(self, button)
            if GetTime() - dragEndTime < 0.2 then
                return
            end
            -- Override editing sessions: per-spell settings and spell
            -- placement are never part of the override system -- refuse
            -- the interaction with an explanatory tooltip.
            if EllesmereUI.SpecOverrides_EditSessionActive() then
                EllesmereUI.ShowWidgetTooltip(self,
                    "Per-spell settings are not part of the override system.")
                return
            end
            local bd = SelectedCDMBar()
            if not bd then return end
            local isDefaultBuffs = (bd.key == "buffs")

            if button == "MiddleButton" then
                local si = self._slotIdx
                -- A per-icon settings dropdown may be open (anchored to this or
                -- another slot). A remove reshuffles the preview slots, so any
                -- open dropdown is about to point at the wrong spell -- close it.
                if optState._spellPickerMenu and optState._spellPickerMenu:IsShown() then
                    optState._spellPickerMenu:Hide()
                end
                if isDefaultBuffs then
                    -- Custom item slot (negative -itemID marker): remove it
                    -- directly. slotIndex maps to the mixed preview list, so
                    -- key off the marker, not assignedSpells[si].
                    if self._previewItemID then
                        ns.RemoveSpellFromBar(bd.key, -self._previewItemID)
                        if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                        if ns.QueueReanchor then ns.QueueReanchor() end
                        RefreshCDPreview()
                        return
                    end
                    -- Main buffs bar: only injected custom/preset buffs can be deleted
                    -- (Blizzard-tracked buffs are managed in Blizzard's CDM). Remove by spellID since slotIndex maps to the mixed preview list (Blizzard buffs + customs), not assignedSpells.
                    local sid = self._previewSpellID
                    if not sid then return end
                    local sdMid = ns.GetBarSpellData(bd.key)
                    local isInj = sdMid and (
                        (sdMid.spellDurations and (sdMid.spellDurations[sid] or 0) > 0)
                        or (sdMid.customSpellIDs and sdMid.customSpellIDs[sid]))
                    if not isInj then return end
                    ns.RemoveSpellFromBar(bd.key, sid)
                    if sdMid.spellDurations then sdMid.spellDurations[sid] = nil end
                    if ns.RebuildSpellRouteMap then ns.RebuildSpellRouteMap() end
                    if ns.QueueReanchor then ns.QueueReanchor() end
                    RefreshCDPreview()
                    return
                end
                local sdMid = ns.CDMO_EnsureAssignedSpells(bd.key)
                if not sdMid or not sdMid.assignedSpells then return end
                local t = sdMid.assignedSpells
                -- Remove every assignedSpells entry collapsed into this preview slot. A legacy
                -- duplicate buff maps >1 stored id to one slot; a normal slot maps exactly one (plain remove). Highest index first keeps the lower indices valid across removes.
                local grp = (pf._buffDispGroups and pf._buffDispGroups[si]) or { si }
                local order = {}
                for _, v in ipairs(grp) do order[#order + 1] = v end
                table.sort(order, function(a, b) return a > b end)
                local removedAny = false
                for _, idx in ipairs(order) do
                    if t[idx] and t[idx] ~= 0 then
                        ns.RemoveTrackedSpell(bd.key, idx)
                        removedAny = true
                    end
                end
                if not removedAny then return end
                RefreshCDPreview()
            elseif button == "RightButton" or button == "LeftButton" then
                local si = self._slotIdx
                -- Custom item slots (default buffs bar) have no per-icon settings and don't
                -- map to assignedSpells[si]; middle-click removes them. Ignore left/right-click to avoid a mis-indexed settings menu.
                if isDefaultBuffs and self._previewItemID then return end
                -- Translate the preview slot to its underlying assignedSpells index (identity
                -- unless this buff slot collapsed a duplicate).
                local dataIdx = BuffDataIdx(si)
                -- A slot is configurable if it maps to an assignedSpells entry OR (default
                -- buffs bar mirror) exposes a live spellID. The per-icon settings menu keys off whichever is present.
                local sdClick = ns.GetBarSpellData(bd.key)
                local hasAssigned = sdClick and sdClick.assignedSpells
                    and sdClick.assignedSpells[dataIdx] and sdClick.assignedSpells[dataIdx] ~= 0
                if not hasAssigned and not self._previewSpellID then return end

                -- Show remove-only dropdown (per-icon settings + Remove)
                ns.CDMO_ShowSpellPicker(self, bd.key, dataIdx, {}, function()
                    -- onSelect unused -- remove is handled inside ShowSpellPicker
                end, true)  -- removeOnly flag
            end
        end)

        -- Manual drag detection: bypasses WoW's large built-in drag threshold
        local DRAG_THRESHOLD = 3  -- pixels of mouse movement before drag starts
        local pendingDragSlot, pendingStartX, pendingStartY

        -- After a drag ends, refresh hover highlights based on current cursor position
        local function RefreshHoverHighlight()
            local bd = SelectedCDMBar()
            local bR, bG, bB = 0, 0, 0
            if bd then
                bR, bG, bB = bd.borderR or 0, bd.borderG or 0, bd.borderB or 0
                if bd.borderClassColor then
                    local _, ct = UnitClass("player")
                    if ct then
                        local cc = RAID_CLASS_COLORS[ct]
                        if cc then bR, bG, bB = cc.r, cc.g, cc.b end
                    end
                end
            end
            for i = 1, MAX_PREVIEW_ICONS do
                local s = previewSlots[i]
                if s then
                    local hovered = s:IsShown() and s:IsMouseOver()
                    local hasShape = s._shapeBorder and s._shapeBorder:IsShown()
                    if hasShape then
                        if hovered then
                            s._shapeBorder:SetVertexColor(eg.r, eg.g, eg.b, 1)
                        else
                            s._shapeBorder:SetVertexColor(bR, bG, bB, 1)
                        end
                    elseif s._hlBrd then
                        if hovered then
                            s._hlBrd:Show()
                        else
                            s._hlBrd:Hide()
                        end
                    end
                end
            end
        end

        -- Drop handler: called when mouse is released during a drag
        local function FinishDrag()
            if not dragSlot then return end
            local self = dragSlot
            local bd = SelectedCDMBar()
            if dragGhost then dragGhost:Hide() end
            self:SetAlpha(1)
            self:SetFrameLevel(pf:GetFrameLevel() + 1)
            local didChange = false
            if insertIdx and bd then
                local oldPos = {}
                for i = 1, MAX_PREVIEW_ICONS do
                    local s = previewSlots[i]
                    if s and s:IsShown() and s._baseX then
                        local tex = s._icon and s._icon:GetTexture()
                        if tex then oldPos[tex] = s._baseX + (s._currentOffX or 0) end
                    end
                end

                -- Default buffs bar reorders a dedicated display-order array (canon ids)
                -- instead of assignedSpells, which it shares with routing/custom injection. Seed it from the rendered order on the first drag so index-based moves line up with the preview.
                local isDefBuffs = (bd.key == "buffs")
                if isDefBuffs then
                    local sdBuf = ns.GetBarSpellData("buffs")
                    if sdBuf and not (sdBuf.buffDisplayOrder and #sdBuf.buffDisplayOrder > 0) then
                        local snap = pf._buffTrackedOrder
                        if snap and #snap > 0 then
                            local copy = {}
                            for i = 1, #snap do copy[i] = snap[i] end
                            sdBuf.buffDisplayOrder = copy
                        end
                    end
                end
                -- Resolved index refuses the commit when out of range (drag snaps back, no
                -- write). Cd-claimed collided-buff slots carry a real assignedSpells index (a cd-claim marker, see ns.CdClaimMarker) same as any other entry, so no special-casing needed here.
                local function SafeDataIdx(dispIdx)
                    local di = BuffDataIdx(dispIdx)
                    local sdChk = ns.GetBarSpellData and ns.GetBarSpellData(bd.key)
                    local n = sdChk and sdChk.assignedSpells and #sdChk.assignedSpells or 0
                    if di < 1 or di > n then return nil end
                    return di
                end
                if dragMode == "swap" then
                    if insertIdx ~= dragIdx then
                        if isDefBuffs then
                            -- Slot -> stable-key translation: buffDisplayOrder
                            -- keeps absent (talent-gapped) keys in place, so
                            -- slot indices cannot address it directly.
                            local sk = pf._buffSlotKeys
                            if sk and ns.SwapBuffDisplayKeys
                               and ns.SwapBuffDisplayKeys(sk[dragIdx], sk[insertIdx]) then
                                didChange = true
                            end
                        else
                            local a, b = SafeDataIdx(dragIdx), SafeDataIdx(insertIdx)
                            if a and b then
                                ns.SwapTrackedSpells(bd.key, a, b)
                                didChange = true
                            end
                        end
                    end
                else
                    local toIdx = insertIdx
                    if toIdx > dragIdx then toIdx = toIdx - 1 end
                    if toIdx ~= dragIdx then
                        if isDefBuffs then
                            local sk = pf._buffSlotKeys
                            if sk and ns.MoveBuffDisplayKey then
                                -- Final rendered position toIdx = insert before
                                -- the key at toIdx among the OTHER rendered keys
                                -- (nil past the end = append after everything).
                                local rk, n = {}, 0
                                for i = 1, #sk do
                                    if i ~= dragIdx then n = n + 1; rk[n] = sk[i] end
                                end
                                if ns.MoveBuffDisplayKey(sk[dragIdx], rk[toIdx]) then
                                    didChange = true
                                end
                            end
                        else
                            local a, b = SafeDataIdx(dragIdx), SafeDataIdx(toIdx)
                            if a and b then
                                ns.MoveTrackedSpell(bd.key, a, b)
                                didChange = true
                            end
                        end
                    end
                end

                if didChange then
                    local droppedIdx
                    if dragMode == "swap" then
                        droppedIdx = insertIdx
                    else
                        local toIdx = insertIdx
                        if toIdx > dragIdx then toIdx = toIdx - 1 end
                        droppedIdx = toIdx
                    end

                    insertLine:Hide()
                    if swapTargetIdx then
                        local sw = previewSlots[swapTargetIdx]
                        if sw and sw._hlBrd then sw._hlBrd:Hide() end
                        swapTargetIdx = nil
                    end

                    for i = 1, MAX_PREVIEW_ICONS do
                        local s = previewSlots[i]
                        if s then s._targetOffX = nil; s._currentOffX = nil end
                    end
                    animRunning = false

                    Refresh()
                    if pf.Update then pf:Update() end
                    UpdateCDMPreviewAndResize()

                    for i = 1, MAX_PREVIEW_ICONS do
                        local s = previewSlots[i]
                        if s and s:IsShown() and s._baseX then
                            if i == droppedIdx then
                                s._currentOffX = 0
                                s._targetOffX = 0
                            else
                                local tex = s._icon and s._icon:GetTexture()
                                if tex and oldPos[tex] then
                                    local diff = oldPos[tex] - s._baseX
                                    if math.abs(diff) > 0.5 then
                                        s._currentOffX = diff
                                        s._targetOffX = 0
                                    else
                                        s._currentOffX = 0
                                        s._targetOffX = 0
                                    end
                                else
                                    s._currentOffX = 0
                                    s._targetOffX = 0
                                end
                            end
                        end
                    end
                    animRunning = true
                    pf:SetScript("OnUpdate", function(_, dt)
                        TickAnimation(dt)
                        if not animRunning then
                            pf:SetScript("OnUpdate", nil)
                        end
                    end)
                    dragSlot = nil; dragIdx = nil; insertIdx = nil; dragMode = nil
                    dragEndTime = GetTime()
                    RefreshHoverHighlight()
                    return
                end
            end
            ClearInsertIndicator()
            dragSlot = nil; dragIdx = nil; insertIdx = nil; dragMode = nil
            dragEndTime = GetTime()
            pf:SetScript("OnUpdate", nil)
            RefreshHoverHighlight()
        end

        local function BeginDrag(self)
            local bd = SelectedCDMBar()
            if not bd then return end
            local sdDrag = ns.GetBarSpellData(bd.key)
            local si = self._slotIdx
            if bd.key == "buffs" then
                -- Default bar: a slot is draggable if it renders a buff
                -- (_previewSpellID / a rendered stable key). buffDisplayOrder
                -- is NOT indexed by slot -- it keeps absent keys in place.
                if not self._previewSpellID
                   and not (pf._buffSlotKeys and pf._buffSlotKeys[si]) then return end
            else
                local t = sdDrag and sdDrag.assignedSpells or {}
                local di = BuffDataIdx(si)
                if not t[di] or t[di] == 0 then return end
            end
            dragSlot = self; dragIdx = si
            -- Clear hover highlight on the dragged slot
            if self._shapeBorder and self._shapeBorder:IsShown() then
                local bd2 = SelectedCDMBar()
                local bR2, bG2, bB2 = 0, 0, 0
                if bd2 then
                    bR2, bG2, bB2 = bd2.borderR or 0, bd2.borderG or 0, bd2.borderB or 0
                    if bd2.borderClassColor then
                        local _, ct = UnitClass("player")
                        if ct then
                            local cc = RAID_CLASS_COLORS[ct]
                            if cc then bR2, bG2, bB2 = cc.r, cc.g, cc.b end
                        end
                    end
                end
                self._shapeBorder:SetVertexColor(bR2, bG2, bB2, 1)
            elseif self._hlBrd then
                self._hlBrd:Hide()
            end
            local ghost = EnsureDragGhost()
            local iSz = bd.iconSize or 36
            ghost:SetSize(iSz, iSz)
            ghost._icon:SetTexture(self._icon:GetTexture())
            local zm = bd.iconZoom or 0.08
            ghost._icon:SetTexCoord(zm, 1 - zm, zm, 1 - zm)
            ghost:SetScale(0.5)
            ghost:Show()
            self:SetAlpha(0.3)
            self:SetFrameLevel(pf:GetFrameLevel())
            -- Start cursor tracking + mouse-up detection
            pf:SetScript("OnUpdate", function(_, dt)
                -- Detect mouse release
                if not IsMouseButtonDown("LeftButton") then
                    pf:SetScript("OnUpdate", nil)
                    FinishDrag()
                    return
                end
                if not dragGhost or not dragGhost:IsShown() then return end
                local cx, cy = GetCursorPosition()
                local sc = UIParent:GetEffectiveScale()
                cx, cy = cx / sc, cy / sc
                local gs = dragGhost:GetScale() or 1
                dragGhost:ClearAllPoints()
                dragGhost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / gs, cy / gs)
                TickAnimation(dt)
                local tBd = SelectedCDMBar()
                local tCount = 0
                if tBd then
                    local sdT = ns.GetBarSpellData(tBd.key)
                    if tBd.key == "buffs" then
                        -- Rendered slot count, NOT #buffDisplayOrder: the stored
                        -- order keeps absent keys and can exceed what is shown.
                        if pf._buffSlotKeys then tCount = #pf._buffSlotKeys end
                    elseif sdT and sdT.assignedSpells then
                        tCount = #sdT.assignedSpells
                    end
                end
                local visCount = pf._gridSlots or tCount
                local newMode, newTarget = FindDragTarget(cx, cy, visCount, dragIdx)
                if newMode and newTarget then
                    local isNoop = false
                    if newMode == "insert" then
                        local effTo = newTarget
                        if effTo > dragIdx then effTo = effTo - 1 end
                        if effTo == dragIdx then isNoop = true end
                    elseif newMode == "swap" and newTarget == dragIdx then
                        isNoop = true
                    end
                    if isNoop then
                        ClearInsertIndicator()
                    else
                        dragMode = newMode
                        ApplyDragFeedback(newMode, newTarget, dragIdx, visCount)
                        insertIdx = newTarget
                    end
                else
                    ClearInsertIndicator()
                end
            end)
        end

        slot:SetScript("OnMouseDown", function(self, button)
            if button ~= "LeftButton" then return end
            -- Override editing sessions: spell placement never overrides.
            if EllesmereUI.SpecOverrides_EditSessionActive() then
                EllesmereUI.ShowWidgetTooltip(self,
                    "Per-spell settings are not part of the override system.")
                return
            end
            -- Buff-family drag-reorder: extra/custom buff bars reorder via
            -- assignedSpells (1:1 preview), the default buffs bar via its
            -- dedicated buffDisplayOrder (stable cooldownID-keyed, reconciled
            -- from the live viewer pool). Only FocusKick stays locked -- its
            -- icon order is driven by nameplate state, not user order.
            local bdDrag = SelectedCDMBar()
            if bdDrag and bdDrag.key == ns.FOCUSKICK_BAR_KEY then return end
            local cx, cy = GetCursorPosition()
            pendingDragSlot = self
            pendingStartX = cx
            pendingStartY = cy
            -- Use a lightweight OnUpdate to detect threshold
            self:SetScript("OnUpdate", function()
                if not pendingDragSlot then self:SetScript("OnUpdate", nil); return end
                local nx, ny = GetCursorPosition()
                local dx = nx - pendingStartX
                local dy = ny - pendingStartY
                if dx * dx + dy * dy >= DRAG_THRESHOLD * DRAG_THRESHOLD then
                    local s = pendingDragSlot
                    pendingDragSlot = nil
                    self:SetScript("OnUpdate", nil)
                    BeginDrag(s)
                end
            end)
        end)

        slot:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and pendingDragSlot then
                -- Mouse released before threshold not a drag, let OnClick handle it
                pendingDragSlot = nil
                self:SetScript("OnUpdate", nil)
            end
        end)

        return slot
    end

    for i = 1, MAX_PREVIEW_ICONS do
        previewSlots[i] = CreatePreviewSlot(i)
    end

    -- "+" button to add new spells
    local addBtn = CreateFrame("Button", nil, pf)
    PP.Size(addBtn, 36, 36); addBtn:Hide()
    local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
    addBg:SetAllPoints(); addBg:SetColorTexture(0.08, 0.08, 0.08, 0.6)
    if addBg.SetSnapToPixelGrid then addBg:SetSnapToPixelGrid(false); addBg:SetTexelSnappingBias(0) end
    if PP then PP.CreateBorder(addBtn, 0.3, 0.3, 0.3, 0.5, 1, "OVERLAY", 7) end
    local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
    addLbl:SetFont(FONT_PATH, 22, GetCDMOptOutline())
    addLbl:SetPoint("CENTER", 0, 1)
    addLbl:SetText("+")

    -- Hover highlight for add button (2px accent border, same as slots)
    local eg = EllesmereUI.ELLESMERE_GREEN
    local addHlCont = CreateFrame("Frame", nil, addBtn)
    addHlCont:SetAllPoints()
    addHlCont:SetFrameLevel(addBtn:GetFrameLevel() + 1)
    local addPP = EllesmereUI and EllesmereUI.PP
    local addBrd = addPP and addPP.CreateBorder(addHlCont, eg.r, eg.g, eg.b, 1, 2, "OVERLAY", 7)
    if addBrd then addBrd:Hide() end

    addBtn:SetScript("OnEnter", function()
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        addLbl:SetTextColor(ar, ag, ab, 1)
        if addBrd then addBrd:Show() end
        if EllesmereUI.ShowWidgetTooltip then
            -- This same button adds buffs on buff-family bars, so the tip
            -- follows the selected bar rather than hard-coding CD/Utility.
            local bdHov = SelectedCDMBar()
            local tip
            if bdHov and ns.IsBarBuffFamily(bdHov) then
                tip = "Add a Buff Spell"
            else
                tip = "Add a CD/Utility Spell"
            end
            EllesmereUI.ShowWidgetTooltip(addBtn, EllesmereUI.L(tip))
        end
    end)
    addBtn:SetScript("OnLeave", function()
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        addLbl:SetTextColor(ar, ag, ab, 0.6)
        if addBrd then addBrd:Hide() end
        EllesmereUI.HideWidgetTooltip()
    end)
    addBtn:SetScript("OnClick", function(self)
        local bd = SelectedCDMBar()
        if not bd then return end

        -- Shared post-add finalization for ALL families (buff + CD/util). Forces an
        -- immediate reanchor so source bars (where the spell got auto-removed from) re-render without waiting for the throttled queue. Then schedules a +0.05s preview refresh.
        local function FinalizeAdd()
            if ns.CollectAndReanchor then ns.CollectAndReanchor() end
            C_Timer.After(0.05, function()
                if ns.CDMApplyVisibility then ns.CDMApplyVisibility() end
                if pf.Update then pf:Update() end
                UpdateCDMPreviewAndResize()
            end)
        end

        if ns.IsBarBuffFamily(bd) then
            -- Buff bars use ShowBuffBarPicker (walks the BuffIcon viewer pool). Click routes
            -- AddTrackedSpell -- the family sweep removes the spell from every other buff-family bar (including the ghost hidden bar, the "unhide" step) before claiming it for bd.key.
            ns.CDMO_ShowBuffBarPicker(self, bd.key, function(newSpellID, newCdID)
                if newSpellID then
                    -- Collided pair (two viewer slots, one shared spellID) or tracked trinket row:
                    -- claim by cooldownID so each slot is addable on its own. Other buffs keep the sid path -- spellID identity survives talent swaps, cooldownIDs drift.
                    if ns.ClaimBuffByCdID(newSpellID, newCdID) then
                        ns.AddTrackedBuffByCdID(bd.key, newCdID, newSpellID)
                    else
                        ns.AddTrackedSpell(bd.key, newSpellID)
                    end
                end
                FinalizeAdd()
            end)
        else
            -- CD/utility bars use ShowSpellPicker.
            local sdAdd = ns.CDMO_EnsureAssignedSpells(bd.key)
            local excl = {}
            local _FindOvr = C_SpellBook and C_SpellBook.FindSpellOverrideByID
            if sdAdd and sdAdd.assignedSpells then
                for _, sid in ipairs(sdAdd.assignedSpells) do
                    excl[sid] = true
                    -- Also exclude override forms so transformed spells
                    -- (e.g. Lay on Hands 633 -> 471195) are recognized.
                    if _FindOvr and sid > 0 then
                        local ovr = _FindOvr(sid)
                        if ovr and ovr > 0 then excl[ovr] = true end
                    end
                end
            end
            ns.CDMO_ShowSpellPicker(self, bd.key, nil, excl, function(newSpellID, isExtra)
                ns.AddTrackedSpell(bd.key, newSpellID, isExtra)
                FinalizeAdd()
            end)
        end
    end)

    -- Second "+" button: add a BUFF to this CD/utility bar (buff-family bars keep the single
    -- "+" above). A buff placed here renders as a regular CD/utility icon whose gold Active
    -- State is driven by its aura. Gold-tinted so it reads apart from the standard add button; shown for CD/util only.
    local BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B = 1, 0.82, 0.25
    local buffAddBtn = CreateFrame("Button", nil, pf)
    PP.Size(buffAddBtn, 36, 36); buffAddBtn:Hide()
    local buffAddBg = buffAddBtn:CreateTexture(nil, "BACKGROUND")
    buffAddBg:SetAllPoints(); buffAddBg:SetColorTexture(0.08, 0.08, 0.08, 0.6)
    if buffAddBg.SetSnapToPixelGrid then buffAddBg:SetSnapToPixelGrid(false); buffAddBg:SetTexelSnappingBias(0) end
    -- Resting border matches the standard add button (neutral gray, not gold) -- the gold "+" glyph alone marks this as the buff-add button.
    if PP then PP.CreateBorder(buffAddBtn, 0.3, 0.3, 0.3, 0.5, 1, "OVERLAY", 7) end
    local buffAddLbl = buffAddBtn:CreateFontString(nil, "OVERLAY")
    buffAddLbl:SetFont(FONT_PATH, 22, GetCDMOptOutline())
    buffAddLbl:SetPoint("CENTER", 0, 1)
    buffAddLbl:SetText("+")
    buffAddLbl:SetTextColor(BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B, 0.7)

    local buffAddHlCont = CreateFrame("Frame", nil, buffAddBtn)
    buffAddHlCont:SetAllPoints()
    buffAddHlCont:SetFrameLevel(buffAddBtn:GetFrameLevel() + 1)
    local buffAddBrd = EllesmereUI and EllesmereUI.PP
        and EllesmereUI.PP.CreateBorder(buffAddHlCont, BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B, 1, 2, "OVERLAY", 7)
    if buffAddBrd then buffAddBrd:Hide() end

    buffAddBtn:SetScript("OnEnter", function()
        buffAddLbl:SetTextColor(BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B, 1)
        if buffAddBrd then buffAddBrd:Show() end
        EllesmereUI.ShowWidgetTooltip(buffAddBtn, EllesmereUI.L("Add a Buff Spell"))
    end)
    buffAddBtn:SetScript("OnLeave", function()
        buffAddLbl:SetTextColor(BUFF_ADD_R, BUFF_ADD_G, BUFF_ADD_B, 0.7)
        if buffAddBrd then buffAddBrd:Hide() end
        EllesmereUI.HideWidgetTooltip()
    end)
    buffAddBtn:SetScript("OnClick", function(self)
        local bd = SelectedCDMBar()
        if not bd then return end
        -- CD/utility bars only (defensive: the button is hidden elsewhere).
        if ns.IsBarBuffFamily(bd) or bd.barType == "custom_buff" then return end
        ns.CDMO_ShowBuffToCDPicker(self, bd.key, function()
            if ns.CollectAndReanchor then ns.CollectAndReanchor() end
            -- The buff-mirror walk (10Hz) binds to the freshly-created icon on
            -- its own next tick; no re-arm needed.
            C_Timer.After(0.05, function()
                if ns.CDMApplyVisibility then ns.CDMApplyVisibility() end
                if pf.Update then pf:Update() end
                UpdateCDMPreviewAndResize()
            end)
        end)
    end)

    -- Update: mirrors tracked spells with interactive slots
    pf.Update = function(self)
        local bd = SelectedCDMBar()
        if not bd then
            for i = 1, MAX_PREVIEW_ICONS do previewSlots[i]:Hide() end
            addBtn:Hide(); buffAddBtn:Hide(); self:SetHeight(1); return
        end

        local iconSize = bd.iconSize or 36
        -- Width-matched bars derive their real icon size from the matched target, so
        -- bd.iconSize (the disabled Icon Scale value) is ignored at runtime. Show a neutral fixed size in the preview rather than the stale scale value.
        if EllesmereUI.GetWidthMatchTarget and EllesmereUI.GetWidthMatchTarget("CDM_" .. bd.key) then iconSize = 36 end
        local iconH = iconSize
        local pvShape = bd.iconShape or "none"
        if pvShape == "cropped" then
            iconH = math.floor(iconSize * ns.CdmCropFactor(bd) + 0.5)
        end
        local spacing  = bd.spacing or 2
        local zoom     = bd.iconZoom or 0.08
        local grow     = bd.growDirection or "RIGHT"
        local numRows  = bd.numRows or 1
        if numRows < 1 then numRows = 1 end

        local isBuffBar = ns.IsBarBuffFamily(bd)
        local isCustomBuffBar = (bd.barType == "custom_buff")
        local isFocusKick = (bd.key == "focuskick")

        -- All bars read from assignedSpells (user intent). The DEFAULT buff bar enumerates
        -- the viewer pool directly so the preview shows every tracked buff regardless of active state, minus spells diverted to other buff-family bars.
        local tracked
        -- Parallel to `tracked` for the default buffs bar: the stable viewer cooldownID for
        -- each Blizzard-tracked buff (nil for custom/injected entries). Per-icon buff settings MUST key off the cooldownID-derived stable spellID, never the live aura GetSpellID (secret/variant-drift).
        local trackedCd
        pf._buffDispGroups = nil
        pf._buffSlotKeys = nil
        if bd.key == "buffs" then
            if ns.ReconcileBuffDisplayOrder then ns.ReconcileBuffDisplayOrder() end
            local entries = ns.CollectDefaultBuffTrackEntries
                and ns.CollectDefaultBuffTrackEntries() or {}
            tracked = {}
            trackedCd = {}
            local sdBuf = ns.GetBarSpellData("buffs")
            local order = sdBuf and sdBuf.buffDisplayOrder
            local byKey = {}
            for _, e in ipairs(entries) do byKey[e.key] = e end
            local finalKeys = {}
            if order and #order > 0 then
                for _, key in ipairs(order) do finalKeys[#finalKeys + 1] = key end
            else
                for _, e in ipairs(entries) do finalKeys[#finalKeys + 1] = e.key end
            end
            -- Rendered slot i <-> stable key map for the drag/reorder code: absent
            -- (talent-gapped) keys stay in buffDisplayOrder but render no slot, so slot indices cannot address the array directly.
            local slotKeys = {}
            for _, key in ipairs(finalKeys) do
                local e = byKey[key]
                if e then
                    tracked[#tracked + 1] = e.sid
                    trackedCd[#tracked] = e.cdID
                    slotKeys[#tracked] = key
                end
            end
            pf._buffSlotKeys = slotKeys
            local snap = {}
            for i = 1, #finalKeys do snap[i] = finalKeys[i] end
            pf._buffTrackedOrder = snap
        else
            local sdUpd = ns.CDMO_EnsureAssignedSpells(bd.key)
            local raw = sdUpd and sdUpd.assignedSpells or {}
            if isBuffBar then
                -- Collapse legacy duplicate buff ids in the PREVIEW only (stored data is left
                -- intact so routing is untouched).
                tracked, pf._buffDispGroups = BuildBuffDisplayDedup(raw)
                -- Resolve cooldownID-level claims (collided buffs tracked by slot, a cd-claim
                -- marker embedded in assignedSpells -- see ns.CdClaimMarker) to their display
                -- sid IN PLACE, at the marker's own position in `tracked`, so the claim's
                -- preview slot -- and therefore its drag/reorder position -- falls directly out of its assignedSpells index, same as any other entry.
                for i = 1, #tracked do
                    local cdID = ns.CdClaimMarkerToCdID(tracked[i])
                    if cdID then
                        local csid = ns._cdmCleanSidByCDID and ns._cdmCleanSidByCDID[cdID]
                        if not (type(csid) == "number" and csid > 0) then
                            -- Clean cache not primed yet (fresh login, buff
                            -- active since): fall back to cooldownInfo. Each
                            -- field is vetted on its own -- never `or`-chain
                            -- possibly-secret values (truthiness taints).
                            local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                            local info = gci and gci(cdID)
                            local raw2 = info and info.overrideSpellID
                            if not (type(raw2) == "number"
                                    and not (issecretvalue and issecretvalue(raw2))
                                    and raw2 > 0) then
                                raw2 = info and info.spellID
                            end
                            if type(raw2) == "number"
                               and not (issecretvalue and issecretvalue(raw2))
                               and raw2 > 0 then
                                csid = raw2
                            end
                        end
                        if type(csid) == "number" and csid > 0 then
                            tracked[i] = csid
                            trackedCd = trackedCd or {}
                            trackedCd[i] = cdID
                        end
                    end
                end
            else
                tracked = raw
            end
        end
        -- Tracked-but-unlearned spells (assigned or materialized) render
        -- desaturated so it's obvious they aren't currently talented.
        -- CD/utility bars only: buff-family lists come from live pools
        -- (always learned), and custom-buff / focuskick ids are arbitrary
        -- spell ids IsPlayerSpell can't vouch for.
        local unlearnedSet
        -- Talent Conditions (same CD/utility gate): assigned id -> "on" (conditions
        -- hold) / "off" (not met: renders dimmed like an unlearned spell, so it can
        -- still be right-clicked). nil for non-users and on WoW Forever (no menu row there).
        local tcSet
        if bd.key ~= "buffs" and not isBuffBar and not isCustomBuffBar
           and not isFocusKick and IsPlayerSpell then
            if ns._cdmAnyTalentCond and not EllesmereUI.IS_FOREVER then
                tcSet = ns.TalentCondPreviewSet(bd.key, tracked)
            end
            local sdUn = ns.GetBarSpellData(bd.key)
            local customUn  = sdUn and sdUn.customSpellIDs
            local cdursUn   = sdUn and sdUn.customSpellDurations
            local sdursUn   = sdUn and sdUn.spellDurations
            local groupsUn  = sdUn and sdUn.customSpellGroups
            local racialsUn = ns._myRacialsSet
            for _, id in ipairs(tracked) do
                if type(id) == "number" and id > 0
                   and not (customUn and customUn[id])
                   and not (racialsUn and racialsUn[id])
                   and not (cdursUn and cdursUn[id])
                   and not (sdursUn and sdursUn[id])
                   and not (groupsUn and groupsUn[id])
                   and not (IsPlayerSpell(id)
                        or IsPlayerSpell(NormalizeToBase(id))
                        or IsPlayerSpell(ResolveToLive(id))) then
                    unlearnedSet = unlearnedSet or {}
                    unlearnedSet[id] = true
                end
            end
        end
        -- WoW Forever: a stored spell this client cannot see (not known
        -- and not listed anywhere in its Cooldown Manager catalogue: a
        -- retail-only spell a retail layout carried in) keeps its place in
        -- the store but gets no preview slot. The display groups map every
        -- remaining slot back onto its assignedSpells index (drag, remove
        -- and the per-icon menu read them). Same exemptions as the
        -- unlearned test above; the catalogue set is built only once a
        -- candidate shows up.
        if EllesmereUI.IS_FOREVER and bd.key ~= "buffs" and not isBuffBar
           and not isCustomBuffBar and not isFocusKick then
            local sdFv = ns.GetBarSpellData(bd.key)
            local customFv  = sdFv and sdFv.customSpellIDs
            local cdursFv   = sdFv and sdFv.customSpellDurations
            local sdursFv   = sdFv and sdFv.spellDurations
            local groupsFv  = sdFv and sdFv.customSpellGroups
            local racialsFv = ns._myRacialsSet
            local known = C_SpellBook.IsSpellKnown
            local listedFv, keptFv, dispFv
            for i = 1, #tracked do
                local id = tracked[i]
                local unseen = false
                if type(id) == "number" and id > 0
                   and not (customFv and customFv[id])
                   and not (racialsFv and racialsFv[id])
                   and not (cdursFv and cdursFv[id])
                   and not (sdursFv and sdursFv[id])
                   and not (groupsFv and groupsFv[id]) then
                    local base, live = NormalizeToBase(id), ResolveToLive(id)
                    if not (known(id) or known(base) or known(live)) then
                        if listedFv == nil then listedFv = ns.CDMForeverListedSet() or false end
                        unseen = listedFv and not (listedFv[id] or listedFv[base] or listedFv[live]) or false
                    end
                end
                if unseen then
                    if not keptFv then
                        -- First cut: the kept list starts with the slots before it.
                        keptFv, dispFv = {}, {}
                        for j = 1, i - 1 do keptFv[j] = tracked[j]; dispFv[j] = { j } end
                    end
                elseif keptFv then
                    keptFv[#keptFv + 1] = id
                    dispFv[#keptFv] = { i }
                end
            end
            if keptFv then tracked, pf._buffDispGroups = keptFv, dispFv end
        end
        local count = #tracked

        -- Use the same stride logic as the runtime (ComputeTopRowStride).
        -- Top and Bottom custom-row overrides are mutually exclusive; the
        -- Bottom override is the flip (pick the bottom count, top gets rest).
        local stride, topRowCount
        local customTop
        if numRows == 2 then
            if bd.customTopRowEnabled and bd.topRowCount and bd.topRowCount > 0 then
                customTop = math.min(bd.topRowCount, count)
            elseif bd.customBottomRowEnabled and bd.bottomRowCount and bd.bottomRowCount > 0 then
                customTop = count - math.min(bd.bottomRowCount, count)
            end
        end
        if customTop ~= nil then
            if customTop < 0 then customTop = 0 end
            topRowCount = customTop
            local bottomCount = count - topRowCount
            if bottomCount <= 0 or topRowCount <= 0 then
                -- Match the runtime: collapse to one row until BOTH rows hold
                -- an icon. This also keeps the "+" button on the single row.
                numRows = 1
                topRowCount = count
                stride = math.max(count, 1)
            else
                stride = math.max(topRowCount, bottomCount)
            end
        else
            stride = math.ceil(count / numRows)
            if stride < 1 then stride = 1 end
            topRowCount = count - (numRows - 1) * stride
            if topRowCount < 0 then topRowCount = 0 end
        end
        local gridSlots = (count > 0) and (stride * numRows) or 0
        self._stride = stride
        self._numRows = numRows
        self._gridSlots = gridSlots

        local bottomRowCount = count - topRowCount
        if bottomRowCount < 0 then bottomRowCount = 0 end

        -- Per-row icon count for centering
        local function RowIconCount(row)
            if row == 0 then return topRowCount end
            return bottomRowCount
        end

        -- Mirror the live bar's visual row order: with reversed row growth the base
        -- (first data) row renders on the bottom/right (see ns.CDMRowsReversed /
        -- LayoutCDMBar). Data-row logic (RowIconCount, slot indices, drag mapping)
        -- keeps data rows; only the perpendicular placement offset flips.
        local pvReversed = ns.CDMRowsReversed and ns.CDMRowsReversed(bd) or false

        -- Total dimensions: spell grid + 1 extra slot for the "+" button
        local isVert = (grow == "DOWN" or grow == "UP")
        local totalW, totalH
        if isVert then
            local totalCols = numRows + 1
            totalW = (totalCols * iconSize) + ((totalCols - 1) * spacing)
            totalH = (stride * iconH) + ((stride - 1) * spacing)
        else
            local totalCols = stride + 1
            totalW = (totalCols * iconSize) + ((totalCols - 1) * spacing)
            totalH = (numRows * iconH) + ((numRows - 1) * spacing)
        end

        -- CDM preview: no scale-to-fit -- SetClipsChildren on the content
        -- header clips any overflow so icon scale remains accurate.
        local curParentW = (parent:GetWidth() - PAD * 2) / previewScale
        if curParentW > 0 then
            self:SetWidth(curParentW)
        end
        local startX = math.floor((curParentW - totalW) / 2)
        local startY = -5

        -- Position helper: places frame at grid position (col, row).
        -- Center any row that has fewer icons than stride. `row` is the
        -- DATA row; the visual row flips when pvReversed.
        local function PosAtGrid(frame, col, row)
            PP.Size(frame, iconSize, iconH); frame:ClearAllPoints()
            local rowCount = RowIconCount(row)
            local rowHasLess = (rowCount > 0 and rowCount < stride)
            local vRow = pvReversed and (numRows - 1 - row) or row
            local rowOffset = 0
            if isVert then
                if rowHasLess then
                    rowOffset = math.floor((stride - rowCount) * (iconH + spacing) / 2)
                end
                local px = startX + vRow * (iconSize + spacing)
                local py = startY - col * (iconH + spacing) - rowOffset
                PP.Point(frame, "TOPLEFT", self, "TOPLEFT", px, py)
                frame._baseX = px
                frame._baseY = py
            else
                if rowHasLess then
                    rowOffset = math.floor((stride - rowCount) * (iconSize + spacing) / 2)
                end
                local px = startX + col * (iconSize + spacing) + rowOffset
                local py = startY - vRow * (iconH + spacing)
                PP.Point(frame, "TOPLEFT", self, "TOPLEFT", px, py)
                frame._baseX = px
                frame._baseY = py
            end
        end

        -- Border color
        local bR, bG, bB = bd.borderR or 0, bd.borderG or 0, bd.borderB or 0
        if bd.borderClassColor then
            local _, ct = UnitClass("player")
            if ct then
                local cc = RAID_CLASS_COLORS[ct]
                if cc then bR, bG, bB = cc.r, cc.g, cc.b end
            end
        end

        local shape = bd.iconShape or "none"

        -- Layout: fill bottom-up. Icons 1..topRowCount go to top row (row 0),
        -- remaining icons fill rows 1..numRows-1 (full bottom rows).
        for i = 1, math.min(gridSlots, MAX_PREVIEW_ICONS) do
            local slot = previewSlots[i]
            slot._slotIdx = i
            -- The assignedSpells indices this slot covers (a legacy-duplicate
            -- buff slot covers >1); nil when nothing was collapsed. Used by the
            -- settings popup's "Remove Spell" so it clears the whole duplicate.
            slot._dataGroup = pf._buffDispGroups and pf._buffDispGroups[i] or nil

            -- Map sequential index to bottom-up grid position
            local col, row
            if i <= topRowCount then
                col = i - 1
                row = 0
            else
                local bottomIdx = i - topRowCount - 1
                col = bottomIdx % stride
                row = 1 + math.floor(bottomIdx / stride)
            end
            PosAtGrid(slot, col, row)

            if i <= count then
                -- Spell slot
                local id = tracked[i]
                slot._previewSpellID = nil  -- reset each update
                slot._previewCdID = trackedCd and trackedCd[i] or nil
                slot._previewItemID = nil
                slot._previewHostedBuff = nil
                slot._previewIsEmptySlot = nil
                if id then
                    local tex
                    local cdClaim = ns.CdClaimMarkerToCdID and ns.CdClaimMarkerToCdID(id)
                    local hostedSid = (not cdClaim) and ns.HostedBuffMarkerToSpell
                        and ns.HostedBuffMarkerToSpell(id)
                    if cdClaim then
                        -- Cd-claimed slot (a collided pair, e.g. Diabolist
                        -- Demonic Art vs Diabolic Ritual, or a tracked trinket
                        -- row; a buff bar's unresolved claim lands here too).
                        -- On a CD/util bar `tracked` ALIASES sd.assignedSpells (the buff-bar
                        -- branch above builds a fresh dedup list), so resolve
                        -- the marker to a display sid IN THIS RENDER STEP
                        -- ONLY -- never write back into `id`/`tracked[i]`
                        -- (that corrupts the saved marker). Same clean-cache
                        -- + cooldownInfo fallback as the buff-bar preview.
                        local csid = ns._cdmCleanSidByCDID and ns._cdmCleanSidByCDID[cdClaim]
                        if not (type(csid) == "number" and csid > 0) then
                            local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                            local info = gci and gci(cdClaim)
                            local raw2 = info and info.overrideSpellID
                            if not (type(raw2) == "number"
                                    and not (issecretvalue and issecretvalue(raw2))
                                    and raw2 > 0) then
                                raw2 = info and info.spellID
                            end
                            if type(raw2) == "number"
                               and not (issecretvalue and issecretvalue(raw2))
                               and raw2 > 0 then
                                csid = raw2
                            end
                        end
                        if type(csid) == "number" and csid > 0 then
                            local displayID = ResolveIconArt(csid, cdClaim)
                            tex = C_Spell.GetSpellTexture(displayID)
                            if not tex and displayID ~= csid then
                                tex = C_Spell.GetSpellTexture(csid)
                            end
                            slot._previewSpellID = csid
                            slot._previewCdID = cdClaim
                            slot._previewHostedBuff = true
                        else
                            -- Tracked trinket row with its buff down reads no
                            -- spellID: show the item worn in that slot.
                            local gci = C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo
                            local info = gci and gci(cdClaim)
                            local eqSlot = info and info.equipSlot
                            if type(eqSlot) == "number" and not issecretvalue(eqSlot) then
                                local itemID = GetInventoryItemID("player", eqSlot)
                                tex = itemID and C_Item.GetItemIconByID(itemID) or nil
                            end
                        end
                    elseif hostedSid then
                        -- Hosted-buff marker: previews as its spell, flagged so
                        -- the per-icon menu takes the buff branch while the same
                        -- id's cooldown slot keeps the cd/util one.
                        local displayID = ResolveIconArt(hostedSid)
                        tex = C_Spell.GetSpellTexture(displayID)
                        if not tex and displayID ~= hostedSid then
                            tex = C_Spell.GetSpellTexture(hostedSid)
                        end
                        slot._previewSpellID = hostedSid
                        slot._previewHostedBuff = true
                    elseif ns.IsEmptySlotMarker(id) then
                        -- Empty Slot: blank placeholder, no icon/tooltip identity.
                        slot._previewIsEmptySlot = true
                    elseif id <= -100 then
                        -- On-use bag item: negated itemID
                        tex = C_Item.GetItemIconByID(-id)
                        slot._previewItemID = -id
                    elseif id < 0 then
                        -- Trinket slot: get icon from equipped item
                        local itemID = GetInventoryItemID("player", -id)
                        tex = itemID and C_Item.GetItemIconByID(itemID) or nil
                    else
                        -- Resolve to live override for texture lookup.
                        local displayID = ResolveIconArt(id, slot._previewCdID)
                        tex = C_Spell.GetSpellTexture(displayID)
                        if not tex and displayID ~= id then
                            tex = C_Spell.GetSpellTexture(id)
                        end
                        slot._previewSpellID = id
                    end
                    if tex then
                        slot._icon:SetTexture(tex)
                        slot._icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                        local pvUnlearned = (unlearnedSet and unlearnedSet[id])
                            or (tcSet and tcSet[id] == "off") or false
                        slot._icon:SetDesaturated(pvUnlearned)
                        slot._icon:SetAlpha(pvUnlearned and 0.55 or 1)
                    else slot._icon:SetTexture(nil) end
                else slot._icon:SetTexture(nil) end
            else
                -- Blank slot (empty grid filler)
                slot._icon:SetTexture(nil)
                slot._previewSpellID = nil
                slot._previewCdID = nil
                slot._previewItemID = nil
                slot._previewHostedBuff = nil
                slot._previewIsEmptySlot = nil
            end

            local bSz = bd.borderSize or 1
            -- The art inset follows an exact Solid size (borderSizePx) so the border keeps sitting outside the art here.
            local bTex = bd.borderTexture or "solid"
            local bPx = EllesmereUI.BorderPx(bd.borderSizePx, bSz, bTex)
            if bPx and bTex == "solid" then bSz = bPx end
            slot._icon:ClearAllPoints()
            PP.Point(slot._icon, "TOPLEFT", slot, "TOPLEFT", bSz, -bSz)
            PP.Point(slot._icon, "BOTTOMRIGHT", slot, "BOTTOMRIGHT", -bSz, bSz)
            slot._icon:Show()

            if PP.GetBorders(slot) then
                PP.SetBorderColor(slot, bR, bG, bB, 1)
                PP.SetBorderSize(slot, bSz)
            end
            slot._bg:SetColorTexture(bd.bgR or 0.08, bd.bgG or 0.08, bd.bgB or 0.08, bd.bgA or 0.6)
            if slot._bg.SetSnapToPixelGrid then slot._bg:SetSnapToPixelGrid(false); slot._bg:SetTexelSnappingBias(0) end

            ns.ApplyShapeToCDMIcon(slot, shape, bd)
            -- Blizzard Style: no EUI border or background; the live art pass
            -- adds the viewer's rounded mask and ring to the slot exactly as
            -- it does to a bar's own icons. The preview's overlays (text,
            -- hover and hosted-buff borders, glow) move above the ring, at
            -- the levels their live counterparts use.
            if EllesmereUI.BlizzStyle.Get("cdmicons") and ns.CdmApplyBlizzIconArt then
                if PP.GetBorders(slot) then PP.HideBorder(slot) end
                slot._bg:Hide()
                ns.CdmApplyBlizzIconArt(slot)
                local lvl = slot:GetFrameLevel()
                if slot._pvTextOverlay then slot._pvTextOverlay:SetFrameLevel(lvl + 23) end
                if slot._hlBrd then slot._hlBrd:GetParent():SetFrameLevel(lvl + 17) end
                if slot._hostBrd then slot._hostBrd:GetParent():SetFrameLevel(lvl + 16) end
                if slot._glowOverlay then slot._glowOverlay:SetFrameLevel(lvl + 16) end
            end
            -- Talent Conditions corner mark (built on first use; slots are shared across bars, so always
            -- repainted once it exists). After the style pass: it sits just under the text overlay's level.
            if tcSet or slot._tcMark then
                ns.PaintTalentCondMark(slot, tcSet and i <= count and tcSet[tracked[i]] or nil)
            end
            -- For custom shapes, ensure the square highlight border stays hidden
            -- (ApplyShapeToCDMIcon hides the slot's own PP border but not _hlBrd)
            -- (Blizzard Style forces shape none, whatever the profile carries.)
            if slot._hlBrd and shape ~= "square" and shape ~= "csquare" and shape ~= "none"
               and not EllesmereUI.BlizzStyle.Get("cdmicons") then
                slot._hlBrd:Hide()
            end
            -- Hosted-buff gold border: always on for a buff icon hosted on
            -- this CD/utility bar. Square-family shapes use the dedicated
            -- gold strips; masked shapes tint the shape border instead
            -- (their square strips are hidden, like the hover highlight).
            if slot._hostBrd then
                if slot._previewHostedBuff
                   and not (slot._shapeBorder and slot._shapeBorder:IsShown()) then
                    slot._hostBrd:Show()
                else
                    slot._hostBrd:Hide()
                end
            end
            if slot._previewHostedBuff and slot._shapeBorder and slot._shapeBorder:IsShown() then
                slot._shapeBorder:SetVertexColor(1, 0.82, 0.25, 1)
            end

            -- Stack count preview text
            if slot._stackText then
                if i <= count then
                    -- Show charge count for charge-based spells (default: on)
                    -- Match real bar styling exactly (RefreshCDMIconAppearance)
                    local scFont = ns.GetCDMFont and ns.GetCDMFont() or FONT_PATH
                    local scSize = bd.stackCountSize or 11
                    local scR = bd.stackCountR or 1
                    local scG = bd.stackCountG or 1
                    local scB = bd.stackCountB or 1
                    local scX = bd.stackCountX or 0
                    local scY = bd.stackCountY or 0
                    local scPoint = bd.stackCountPosition or "bottomright"
                    if scPoint == "bottomleft" then scPoint = "BOTTOMLEFT"; scY = scY + 2
                    elseif scPoint == "bottom" then scPoint = "BOTTOM"; scY = scY + 2
                    elseif scPoint == "topright" then scPoint = "TOPRIGHT"
                    elseif scPoint == "top" then scPoint = "TOP"
                    elseif scPoint == "topleft" then scPoint = "TOPLEFT"
                    elseif scPoint == "center" then scPoint = "CENTER"
                    elseif scPoint == "left" then scPoint = "LEFT"
                    elseif scPoint == "right" then scPoint = "RIGHT"
                    else scPoint = "BOTTOMRIGHT"; scY = scY + 2 end
                    EllesmereUI.ApplyIconTextFont(slot._stackText, scFont, scSize, "cdm")
                    slot._stackText:SetTextColor(scR, scG, scB)
                    slot._stackText:ClearAllPoints()
                    slot._stackText:SetPoint(scPoint, slot, scPoint, scX, scY)
                    local sid = slot._previewSpellID
                    local chargeInfo = sid and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(sid)
                    local maxC = chargeInfo and chargeInfo.maxCharges
                    if (bd.showCharges ~= false) and maxC and maxC > 1 then
                        slot._stackText:SetText(tostring(maxC))
                        slot._stackText:Show()
                    elseif slot._previewItemID and (bd.showItemCount ~= false) then
                        -- Preset potions/healthstones: fake item count so users can
                        -- preview and style the count text (mirrors charge preview).
                        slot._stackText:SetText("5")
                        slot._stackText:Show()
                    else
                        slot._stackText:Hide()
                    end
                else
                    slot._stackText:Hide()
                end
            end

            -- Use the live renderer so font, anchors and badge alpha agree.
            if slot._keybindText then
                ns.StyleCDMKeybind(slot._keybindText, bd, slot, 1, FONT_PATH)
                local sid = slot._previewSpellID
                if bd.showKeybind and sid then
                    -- The live icons' lookup: id, override, base, then name.
                    local key = ns.ResolveCDMKeybind(sid)
                    if key then
                        slot._keybindText:SetText(key)
                        slot._keybindText:Show()
                    else
                        slot._keybindText:Hide()
                    end
                else
                    slot._keybindText:Hide()
                end
                -- StyleCDMKeybind above already styled the badge: visibility only.
                ns.ShowCDMKeybindBadge(slot._keybindText, bd)
            end

            if i <= count then
                slot:Show()
            else
                slot:Hide()
            end
        end

        for i = gridSlots + 1, MAX_PREVIEW_ICONS do previewSlots[i]:Hide() end

        -- "+" button: placed right after the last icon on the bottom row (always full,
        -- or the only row). For empty bars (count=0), the "+" is the only visible element.
        local addPx, addPy
        if count == 0 then
            -- No spells: center the "+" button alone
            addPx = math.floor((curParentW - iconSize) / 2)
            addPy = startY
        elseif isVert then
            -- Vertical: "+" goes in the next column to the right, at the bottom
            addPx = startX + numRows * (iconSize + spacing)
            addPy = startY - (stride - 1) * (iconH + spacing)
        else
            -- Horizontal: "+" goes right after the last column on the bottom row
            local lastRow = numRows - 1
            addPx = startX + stride * (iconSize + spacing)
            addPy = startY - lastRow * (iconH + spacing)
        end
        PP.Size(addBtn, iconSize, iconH); addBtn:ClearAllPoints()
        PP.Point(addBtn, "TOPLEFT", self, "TOPLEFT", addPx, addPy)
        if PP.GetBorders(addBtn) then PP.SetBorderSize(addBtn, 1) end
        local ar, ag, ab = EllesmereUI.GetAccentColor()

        addLbl:SetTextColor(ar, ag, ab, 0.6)
        addBtn:Show()

        -- Second "+" (buff) button sits one slot right of the standard "+", on CD/utility bars only (buff-family/custom_buff/focuskick bars track buffs their own way).
        if not isBuffBar and not isCustomBuffBar and not isFocusKick then
            PP.Size(buffAddBtn, iconSize, iconH); buffAddBtn:ClearAllPoints()
            PP.Point(buffAddBtn, "TOPLEFT", self, "TOPLEFT", addPx + iconSize + spacing, addPy)
            if PP.GetBorders(buffAddBtn) then PP.SetBorderSize(buffAddBtn, 1) end
            buffAddBtn:Show()
        else
            buffAddBtn:Hide()
        end

        -- Bar background covers spell grid only (not the + column)
        local spellW, spellH
        if isVert then
            spellW = (numRows * iconSize) + ((numRows - 1) * spacing)
            spellH = (stride * iconH) + ((stride - 1) * spacing)
        else
            spellW = (stride * iconSize) + ((stride - 1) * spacing)
            spellH = totalH
        end
        if bd.barBgEnabled then
            pvBarBg:ClearAllPoints()
            pvBarBg:SetPoint("TOPLEFT", startX, startY)
            pvBarBg:SetPoint("BOTTOMRIGHT", pf, "TOPLEFT", startX + spellW, startY - spellH)
            pvBarBg:SetColorTexture(bd.barBgR or 0, bd.barBgG or 0, bd.barBgB or 0, bd.barBgA or 0.5)
            if pvBarBg.SetSnapToPixelGrid then pvBarBg:SetSnapToPixelGrid(false); pvBarBg:SetTexelSnappingBias(0) end
            pvBarBg:Show()
        else
            pvBarBg:Hide()
        end

        self:SetAlpha(1)

        -- Buff bar info text
        if not self._buffInfoText then
            local infoFS = self:CreateFontString(nil, "OVERLAY")
            infoFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            infoFS:SetJustifyH("CENTER")
            infoFS:SetWordWrap(true)
            infoFS:SetTextColor(0.6, 0.6, 0.6, 0.9)
            self._buffInfoText = infoFS
        end
        -- Reorder/per-icon hint shown directly below the preview icons. Buff bars and
        -- CD/utility bars get different wording; FocusKick has its own info text instead and is not user-reorderable.
        if not self._reorderHintText then
            local rh = self:CreateFontString(nil, "OVERLAY")
            rh:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            rh:SetJustifyH("CENTER")
            rh:SetWordWrap(true)
            rh:SetTextColor(0.62, 0.62, 0.62, 0.9)
            self._reorderHintText = rh
        end
        local function ShowReorderHint(text)
            local rh = self._reorderHintText
            rh:SetText(EllesmereUI.L(text))
            rh:ClearAllPoints()
            rh:SetPoint("TOP", self, "TOPLEFT", self:GetWidth() / 2, -(totalH + 14))
            rh:SetWidth(self:GetWidth() - 20)
            rh:Show()
            self:SetHeight(totalH + 10 + rh:GetStringHeight() + 20)
        end

        if isBuffBar then
            if self._buffInfoText then self._buffInfoText:Hide() end
            if self._buffInfoClick then self._buffInfoClick:Hide() end
            -- Hide any stale hidden rows
            if self._hiddenRows then
                for _, hr in ipairs(self._hiddenRows) do hr:Hide() end
            end
            if self._hiddenHeader then self._hiddenHeader:Hide() end
            if self._focusKickInfoText then self._focusKickInfoText:Hide() end
            ShowReorderHint("Drag to Reorder. Click to override display settings and add custom effects per icon")
        elseif isFocusKick then
            if self._buffInfoText then self._buffInfoText:Hide() end
            if self._buffInfoClick then self._buffInfoClick:Hide() end
            if self._reorderHintText then self._reorderHintText:Hide() end
            if not self._focusKickInfoText then
                local fkFS = self:CreateFontString(nil, "OVERLAY")
                fkFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                fkFS:SetJustifyH("CENTER")
                fkFS:SetWordWrap(true)
                fkFS:SetTextColor(1, 1, 1, 1)
                self._focusKickInfoText = fkFS
            end
            local fkFS = self._focusKickInfoText
            -- Wording must track the "Show on Target" toggle -- otherwise this text keeps promising focus-tracking even when the bar is configured to follow the current target instead.
            if bd.focusKickUseTarget then
                fkFS:SetText(EllesmereUI.L("This bar will always be attached to your current target's nameplate"))
            else
                fkFS:SetText(EllesmereUI.L("This bar will always be attached to your focus target's nameplate"))
            end
            fkFS:ClearAllPoints()
            fkFS:SetPoint("TOP", self, "TOPLEFT", self:GetWidth() / 2, -(totalH + 14))
            fkFS:SetWidth(self:GetWidth() - 20)
            fkFS:Show()
            self:SetHeight(totalH + 10 + fkFS:GetStringHeight() + 20)
        else
            if self._buffInfoText then self._buffInfoText:Hide() end
            if self._buffInfoClick then self._buffInfoClick:Hide() end
            if self._focusKickInfoText then self._focusKickInfoText:Hide() end
            ShowReorderHint("Drag to Reorder. Click to add custom glows, active/cooldown state effects and more.")
        end

        -- Resize wrapper to min(content, max) and toggle scrollbar
        local parentH = self:GetHeight() * (self._previewScale or 1)
        local maxH = self._PREVIEW_MAX_H or 200
        if parentH > maxH then
            -- Add bottom padding so info text is fully visible when scrolled down
            self:SetHeight(self:GetHeight() + 30)
            -- If the cap would slice into the icon grid itself, snap the viewport to
            -- a whole row instead -- cropping into the hint text below is harmless,
            -- cropping an icon row in half isn't.
            local stackRows = isVert and stride or numRows
            local topInset = 5
            local rowStep = iconH + spacing
            local gridBottomLocal = topInset + stackRows * iconH + (stackRows - 1) * spacing
            if gridBottomLocal * self._previewScale > maxH then
                local visibleRows = math.max(1, math.floor((maxH / self._previewScale - topInset + spacing) / rowStep + 0.001))
                visibleRows = math.min(visibleRows, stackRows)
                local cappedLocalH = topInset + visibleRows * iconH + (visibleRows - 1) * spacing
                self._wrapper:SetHeight(math.min(maxH, cappedLocalH * self._previewScale))
            else
                self._wrapper:SetHeight(maxH)
            end
        else
            self._wrapper:SetHeight(parentH)
            if self._scrollFrame then self._scrollFrame:SetVerticalScroll(0) end
        end
        if self._updatePVThumb then self._updatePVThumb() end

        -- Restart active state preview on first icon if toggled on
        if _cdmActivePreviewOn then
            StopActiveStatePreview()
            StartActiveStatePreview()
        end
    end

    pf._previewSlots = previewSlots
    optState._cdmPreview = pf
    pf:Update()
    EllesmereUI._contentHeaderPreview = pf
    -- Start active state preview if toggled on
    if _cdmActivePreviewOn then
        StartActiveStatePreview()
    end
    -- Return wrapper height (already capped by Update's resize logic)
    return wrapper:GetHeight()
end

-- Used by BarsPage_Options.lua
ns.CDMO_BuildCDMLivePreview = BuildCDMLivePreview
