if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Bags_Sidebar.lua
--
--  The sidebar: drag-to-reorder, CreateSidebar, the category context
--  menu and BuildSidebarButtons.
--  Reads the earlier Bags files through ns and ns._bagsInternals.
-------------------------------------------------------------------------------
local ns = select(2, ...)
local I = ns._bagsInternals
-- EllesmereUIBags.lua or an earlier EUI_Bags_*.lua file failed to load.
if not I or I.broken then return end
I.broken = true

local GetItemInfo = C_Item.GetItemInfo
local EUI = EllesmereUI

local BP, GetAccentRGB, GetDefaultBagType = I.BP, I.GetAccentRGB, I.GetDefaultBagType
local GetFont, IsItemPinned, NormalizePinKey = I.GetFont, I.IsItemPinned, I.NormalizePinKey
local SetBagFont, ClearGroupOrder, HEADER_H = I.SetBagFont, I.ClearGroupOrder, I.HEADER_H
local ResortAfterGroupChange, SIDEBAR_BTN_H = I.ResortAfterGroupChange, I.SIDEBAR_BTN_H
local SIDEBAR_ICON_SIZE, SIDEBAR_INDENT = I.SIDEBAR_ICON_SIZE, I.SIDEBAR_INDENT
local SIDEBAR_PAD, SIDEBAR_W_COLLAPSED = I.SIDEBAR_PAD, I.SIDEBAR_W_COLLAPSED
local SIDEBAR_W_EXPANDED = I.SIDEBAR_W_EXPANDED
local SetSelectedCategoryIndex = I.SetSelectedCategoryIndex
local SetSelectedGroupName = I.SetSelectedGroupName

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._bagsInternals, which hands the value to every copy.
local selectedCategoryIndex = I.selectedCategoryIndex
I.categoryIndexSetters[#I.categoryIndexSetters + 1] = function(v) selectedCategoryIndex = v end
local selectedGroupName
I.groupNameSetters[#I.groupNameSetters + 1] = function(v) selectedGroupName = v end

-------------------------------------------------------------------------------
--  Sidebar
-------------------------------------------------------------------------------
local _sidebarBtns = {}  -- array of sidebar button frames

-- 0 while collapsed under Hide Sidebar Icons When Collapsed (default off): the
-- sidebar hides and its expand arrow sits left of the window title.
local function GetSidebarWidth()
    local p = BP()
    if not p.bagSidebarCollapsed then return SIDEBAR_W_EXPANDED end
    return p.bagHideSidebarIconsCollapsed == true and 0 or SIDEBAR_W_COLLAPSED
end

-------------------------------------------------------------------------------
--  Sidebar drag-to-reorder (iOS-style: ghost + insert line + source fade)
-------------------------------------------------------------------------------
local _dragGhost         -- floating ghost frame (scaled 0.5x, 70% opacity)
local _dragFromCatIdx    -- category index being dragged (1-based into bagCategoryDefs)
local _dragSourceBtn     -- the button frame being dragged (to restore alpha)
local _dragInsertLine    -- accent-colored insertion line
local _dragGroupHL       -- accent-colored group highlight overlay
local _dragLastTarget    -- last computed insert target (avoid redundant updates)
local _dragLastMode      -- "above", "below", "group"
local _dragLastBtn       -- last target button (avoid redundant updates)
local _dragDropMode      -- current drop mode for StopSidebarDrag
local _dragDropTarget    -- current drop target catIdx
local _dragTargetIsHeader -- true when resolved target came from a group header button
local _dragInsertGroup    -- group name when insert position is inside a group

local function EnsureDragGhost()
    if _dragGhost then return _dragGhost end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetFrameStrata("TOOLTIP")
    g:SetSize(SIDEBAR_W_EXPANDED, SIDEBAR_BTN_H)
    g:SetAlpha(0.7)
    g:SetScale(0.5)
    g:EnableMouse(false)
    g.bg = g:CreateTexture(nil, "BACKGROUND")
    g.bg:SetAllPoints()
    g.bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)
    g.icon = g:CreateTexture(nil, "ARTWORK")
    g.icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
    g.icon:SetPoint("LEFT", 8, 0)
    g.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    g.label = g:CreateFontString(nil, "OVERLAY")
    SetBagFont(g.label, 11)
    g.label:SetPoint("LEFT", g.icon, "RIGHT", 6, 0)
    g.label:SetTextColor(1, 1, 1)
    g:Hide()
    _dragGhost = g
    return g
end

local function EnsureInsertLine()
    if _dragInsertLine then return _dragInsertLine end
    local sidebar = EUI_Bags._sidebar
    if not sidebar then return nil end
    local eg = EUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.616 }
    local line = sidebar:CreateTexture(nil, "OVERLAY", nil, 7)
    line:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    line:SetHeight(px * 2)
    line:Hide()
    _dragInsertLine = line
    return line
end

local function EnsureGroupHighlight()
    if _dragGroupHL then return _dragGroupHL end
    local sidebar = EUI_Bags._sidebar
    if not sidebar then return nil end
    local eg = EUI.ELLESMERE_GREEN or { r = 0.047, g = 0.824, b = 0.616 }
    local hl = CreateFrame("Frame", nil, sidebar)
    hl:SetFrameLevel(sidebar:GetFrameLevel() + 10)
    hl.bg = hl:CreateTexture(nil, "OVERLAY", nil, 6)
    hl.bg:SetAllPoints()
    hl.bg:SetColorTexture(eg.r, eg.g, eg.b, 0.15)
    -- Accent border
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    local function MakeLine(point1, rel1, point2, rel2, w, h)
        local t = hl:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(eg.r, eg.g, eg.b, 0.6)
        t:SetPoint(point1, hl, rel1, 0, 0)
        t:SetPoint(point2, hl, rel2, 0, 0)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        return t
    end
    MakeLine("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", nil, px)
    MakeLine("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", nil, px)
    MakeLine("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", px, nil)
    MakeLine("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", px, nil)
    hl:Hide()
    _dragGroupHL = hl
    return hl
end

-- Compute insert position from cursor Y relative to visible sidebar buttons (skips hidden/empty categories).
local function ComputeDropTarget()
    local sidebar = EUI_Bags._sidebar
    if not sidebar then return nil end
    local scale = sidebar:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    local sidebarTop = sidebar:GetTop() * scale
    local localY = (sidebarTop - cy) / scale

    -- Offset past sidebar header + "All Items" + "OneBag" + "MultiBag" buttons
    localY = localY - 24 - 3 * (SIDEBAR_BTN_H + SIDEBAR_PAD)

    if localY < 0 then return 1 end

    -- Walk visible category buttons to find which slot the cursor is over
    local cats = EUI_CategoryManager:GetCategories()
    local visIdx = 0
    local lastVisibleCatIdx = 1
    for i = 1, #cats do
        local isVisible = false
        for _, btn in ipairs(_sidebarBtns) do
            if btn:IsShown() and btn._catIdx == i then
                isVisible = true
                break
            end
        end
        if isVisible then
            visIdx = visIdx + 1
            lastVisibleCatIdx = i
            local slotTop = (visIdx - 1) * (SIDEBAR_BTN_H + SIDEBAR_PAD)
            local slotMid = slotTop + (SIDEBAR_BTN_H + SIDEBAR_PAD) / 2
            if localY < slotMid then return i end
        end
    end
    return lastVisibleCatIdx
end

-- Compute drop zone: which button the cursor is over and which zone (above/group/below).
-- Returns: targetCatIdx, mode ("above", "below", "group"), targetBtn
local function ComputeDropZone()
    -- Sidebar buttons carry the sidebar's effective scale, so divide the cursor by that
    -- (not UIParent's) to match btn:GetTop()/GetBottom() -- UIParent math picks the wrong row at scale != 100%. Mirrors ComputeDropTarget above.
    local sidebar = EUI_Bags._sidebar
    local scale = (sidebar and sidebar:GetEffectiveScale()) or UIParent:GetEffectiveScale()
    local _, cy = GetCursorPosition()
    local cursorY = cy / scale

    local GROUP_ZONE = 4  -- pixels from center that count as "group" zone

    -- Walk visible sidebar buttons to find which one cursor is over
    for _, btn in ipairs(_sidebarBtns) do
        if btn:IsShown() and btn._catIdx and btn._catIdx > 0 then
            local top = btn:GetTop()
            local bot = btn:GetBottom()
            if top and bot and cursorY <= top and cursorY >= bot then
                local mid = (top + bot) / 2
                local distFromMid = math.abs(cursorY - mid)
                if distFromMid <= GROUP_ZONE then
                    return btn._catIdx, "group", btn
                elseif cursorY > mid then
                    return btn._catIdx, "above", btn
                else
                    return btn._catIdx, "below", btn
                end
            end
        end
    end
    -- Fallback: find nearest category button by Y distance
    local bestIdx, bestDist, bestBtn, bestMode = 1, math.huge, nil, "above"
    for _, btn in ipairs(_sidebarBtns) do
        if btn:IsShown() and btn._catIdx and btn._catIdx > 0 then
            local top = btn:GetTop()
            local bot = btn:GetBottom()
            if top and bot then
                local mid = (top + bot) / 2
                local dist = math.abs(cursorY - mid)
                if dist < bestDist then
                    bestDist = dist
                    bestIdx = btn._catIdx
                    bestBtn = btn
                    bestMode = cursorY > mid and "above" or "below"
                end
            end
        end
    end
    return bestIdx, bestMode, bestBtn
end

-- Compute insert line Y position for a given category target index
local function GetInsertLineY(targetCatIdx)
    -- Offset: header (24) + 3 fixed buttons (All Items + OneBag + MultiBag)
    local topOffset = 24 + 3 * (SIDEBAR_BTN_H + SIDEBAR_PAD)
    local visSlot = 0
    local cats = EUI_CategoryManager:GetCategories()
    for i = 1, #cats do
        local isVisible = false
        for _, btn in ipairs(_sidebarBtns) do
            if btn:IsShown() and btn._catIdx == i then
                isVisible = true
                break
            end
        end
        if isVisible then
            visSlot = visSlot + 1
            if i == targetCatIdx then
                return -topOffset - ((visSlot - 1) * (SIDEBAR_BTN_H + SIDEBAR_PAD))
            end
        end
    end
    return -topOffset - (visSlot * (SIDEBAR_BTN_H + SIDEBAR_PAD))
end

local StartSidebarDrag  -- forward declaration (defined below)

-- Shared drag-detect frame for sidebar buttons (hidden when not dragging)
local _sidebarDragDetect = CreateFrame("Frame")
_sidebarDragDetect:Hide()
_sidebarDragDetect._btn = nil
_sidebarDragDetect:SetScript("OnUpdate", function(self)
    local btn = self._btn
    if not btn or not btn._dragPending then self:Hide(); return end
    local _, cy = GetCursorPosition()
    if math.abs(cy - (btn._dragStartY or cy)) > 4 then
        btn._dragPending = false
        btn._didDrag = true
        self:Hide()
        StartSidebarDrag(btn, btn._catIdx, btn._catName, btn._catIcon, btn._catIsAtlas)
    end
end)

local _dragUpdateFrame = CreateFrame("Frame")
_dragUpdateFrame:Hide()
_dragUpdateFrame:SetScript("OnUpdate", function()
    if not _dragFromCatIdx then _dragUpdateFrame:Hide(); return end

    local ghost = _dragGhost
    if ghost and ghost:IsShown() then
        local cx, cy = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale()
        local gs = ghost:GetScale() or 1
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx / (sc * gs), cy / (sc * gs))
    end

    local target, mode, targetBtn = ComputeDropZone()

    if target ~= _dragLastTarget or mode ~= _dragLastMode or targetBtn ~= _dragLastBtn then
        _dragLastTarget = target
        _dragLastMode = mode
        _dragLastBtn = targetBtn
        local line = EnsureInsertLine()
        local hl = EnsureGroupHighlight()

        -- Don't group with self
        if mode == "group" and target == _dragFromCatIdx then mode = "above" end

        local cats = EUI_CategoryManager:GetCategories()

        -- Block drops onto/above special entries (Pinned Items, Recent Items) -- nothing drags above the divider.
        local targetCatCheck = cats[target]
        if targetCatCheck and (targetCatCheck.isPinned or targetCatCheck.isRecent) then
            line:Hide(); hl:Hide()
            _dragDropMode = nil; _dragDropTarget = nil
            return
        end
        -- Can't group with or from a noGroup category (e.g. Reagent Bag)
        if mode == "group" and cats[target] and cats[target].noGroup then mode = "below" end
        if mode == "group" and cats[_dragFromCatIdx] and cats[_dragFromCatIdx].noGroup then mode = "above" end

        local fromCat = cats[_dragFromCatIdx]
        local targetCat = cats[target]
        -- Can't group with a grouped member (but CAN group with a group header to join that group)
        if mode == "group" and targetCat and targetCat.groupName and not (targetBtn and targetBtn._isGroupHeader) then
            mode = "above"
        end
        -- Can't group something already in a group with an ungrouped category (would nest groups)
        if mode == "group" and fromCat and fromCat.groupName and not (targetBtn and targetBtn._isGroupHeader) then
            mode = "above"
        end

        if mode == "group" and targetBtn then
            if line then line:Hide() end
            hl:ClearAllPoints()
            hl:SetPoint("TOPLEFT", targetBtn, "TOPLEFT", 2, 0)
            hl:SetPoint("BOTTOMRIGHT", targetBtn, "BOTTOMRIGHT", -2, 0)
            hl:Show()
            _dragDropMode = "group"
            _dragDropTarget = target
        else
            if hl then hl:Hide() end
            _dragDropMode = "insert"

            -- Resolve actual target index: "above N" = N, "below N" = N+1
            -- Exception: "below header" = same gap as "above first member" = N (not N+1)
            local resolvedTarget = target
            if mode == "below" then
                if targetBtn and targetBtn._isGroupHeader then
                    resolvedTarget = target
                else
                    resolvedTarget = target + 1
                end
            end

            -- Set children are a contiguous runtime block re-anchored on rebuild:
            -- an insert between them would not actually land there, so suppress
            -- the line instead of promising a position the drop can't keep.
            if targetBtn and targetBtn._isEquipSet then
                if line then line:Hide() end
                _dragDropTarget = nil
                _dragInsertGroup = nil
                return
            end

            -- Determine if insert position is inside a group
            local insideGroup = nil
            local fromNoGroup = cats[_dragFromCatIdx] and cats[_dragFromCatIdx].noGroup
            local posInGroup = targetBtn and targetCat and targetCat.groupName
                and (targetBtn._isGroupMember or (targetBtn._isGroupHeader and mode == "below"))
            if posInGroup then
                if fromNoGroup then
                    -- noGroup categories can't enter groups; suppress line entirely
                    if line then line:Hide() end
                    _dragDropTarget = nil
                    _dragInsertGroup = nil
                    return
                end
                insideGroup = targetCat.groupName
            end

            -- No-op check: skip if same position AND group membership isn't changing
            local fromCatGroup = cats[_dragFromCatIdx] and cats[_dragFromCatIdx].groupName
            local groupChanges = (insideGroup or false) ~= (fromCatGroup or false)
            local isNoOp = not groupChanges
                and (resolvedTarget == _dragFromCatIdx or resolvedTarget == _dragFromCatIdx + 1)

            if isNoOp then
                if line then line:Hide() end
                _dragDropTarget = nil
                _dragInsertGroup = nil
            else
                _dragDropTarget = resolvedTarget
                _dragTargetIsHeader = targetBtn and targetBtn._isGroupHeader or false
                _dragInsertGroup = insideGroup

                if target and line then
                    -- Position line in the gap between buttons (centered in SIDEBAR_PAD)
                    local gapOff = math.floor(SIDEBAR_PAD / 2)
                    local leftOff = insideGroup and (4 + SIDEBAR_INDENT) or 4
                    if mode == "below" and targetBtn then
                        line:ClearAllPoints()
                        line:SetPoint("TOPLEFT", targetBtn, "BOTTOMLEFT", leftOff, -gapOff)
                        line:SetPoint("TOPRIGHT", targetBtn, "BOTTOMRIGHT", -4, -gapOff)
                    elseif targetBtn then
                        line:ClearAllPoints()
                        line:SetPoint("TOPLEFT", targetBtn, "TOPLEFT", leftOff, gapOff)
                        line:SetPoint("TOPRIGHT", targetBtn, "TOPRIGHT", -4, gapOff)
                    else
                        local sidebar = EUI_Bags._sidebar
                        local lineY = GetInsertLineY(target)
                        line:ClearAllPoints()
                        line:SetPoint("TOPLEFT", sidebar, "TOPLEFT", leftOff, lineY)
                        line:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -4, lineY)
                    end
                    line:Show()
                end
            end
        end
    end
end)

StartSidebarDrag = function(btnSelf, catIdx, catName, catIcon, catIsAtlas)
    _dragFromCatIdx = catIdx
    _dragSourceBtn = btnSelf
    _dragLastTarget = nil
    _dragLastMode = nil
    _dragLastBtn = nil
    _dragDropMode = nil
    _dragDropTarget = nil

    local ghost = EnsureDragGhost()
    ghost:SetSize(GetSidebarWidth(), SIDEBAR_BTN_H)
    if catIsAtlas then
        ghost.icon:SetAtlas(catIcon or "")
        ghost.icon:SetTexCoord(0, 1, 0, 1)
    else
        ghost.icon:SetTexture(EllesmereUI.ClientIcon(catIcon or 134400))
        ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    ghost.label:SetText(catName or "?")
    local collapsed = BP().bagSidebarCollapsed
    if collapsed then ghost.label:Hide() else ghost.label:Show() end
    ghost:Show()

    -- Source button: fade to 30% (iOS lift effect)
    btnSelf:SetAlpha(0.3)

    EnsureInsertLine()
    _dragUpdateFrame:Show()
end

local function StopSidebarDrag()
    if not _dragFromCatIdx then return end

    if _dragSourceBtn then _dragSourceBtn:SetAlpha(1) end

    -- Capture selected category by reference so we can re-find its index after reorder
    local cats = EUI_CategoryManager:GetCategories()
    local selectedCatRef = (selectedCategoryIndex > 0) and cats[selectedCategoryIndex] or nil
    local savedGroupName = selectedGroupName

    local fromCat = cats[_dragFromCatIdx]
    local fromGroup = fromCat and fromCat.groupName
    local isHeader = _dragSourceBtn and _dragSourceBtn._isGroupHeader
    local dropMode = _dragDropMode
    local dropTarget = _dragDropTarget

    if dropMode == "group" and dropTarget and dropTarget ~= _dragFromCatIdx then
        -- GROUP MODE: merge dragged category with target
        local targetCat = cats[dropTarget]
        local targetGroup = targetCat and targetCat.groupName

        if targetCat then
            -- Group-to-group is always allowed (old group may disband, that's fine)
            if fromGroup then
                EUI_CategoryManager:UngroupCategory(_dragFromCatIdx)
                ClearGroupOrder(fromGroup)
            end

            if targetGroup then
                -- Move to bottom of group
                local groupMembers = EUI_CategoryManager:GetGroupMembers(targetGroup)
                local lastMemberIdx = groupMembers[#groupMembers]
                local curFromIdx
                for i, cat in ipairs(cats) do
                    if cat == fromCat then curFromIdx = i; break end
                end
                if curFromIdx and lastMemberIdx then
                    local dest = lastMemberIdx + 1
                    if dest > #cats + 1 then dest = #cats + 1 end
                    if curFromIdx ~= dest then
                        EUI_CategoryManager:ReorderCategory(curFromIdx, dest)
                    end
                end
                -- Add to group (already in position); re-find index after the move
                for i, cat in ipairs(cats) do
                    if cat == fromCat then
                        EUI_CategoryManager:AddToGroup(i, targetGroup)
                        break
                    end
                end
            else
                -- Create new group: move dragged category to right after target first
                local curFromIdx
                for i, cat in ipairs(cats) do
                    if cat == fromCat then curFromIdx = i; break end
                end
                local curTargetIdx
                for i, cat in ipairs(cats) do
                    if cat == targetCat then curTargetIdx = i; break end
                end
                if curFromIdx and curTargetIdx and curFromIdx ~= curTargetIdx then
                    -- Place after target so target stays first in the new group
                    local dest = curTargetIdx + 1
                    if dest > #cats then dest = #cats end
                    EUI_CategoryManager:ReorderCategory(curFromIdx, dest)
                end
                -- Re-find indices after move
                local idx1, idx2
                for i, cat in ipairs(cats) do
                    if cat == targetCat then idx1 = i end
                    if cat == fromCat then idx2 = i end
                end
                if idx1 and idx2 then
                    EUI_CategoryManager:GroupCategories({ idx1, idx2 })
                end
            end
        end
    elseif dropMode == "insert" and dropTarget then
        local target = dropTarget

        local fromGroupName = fromCat and fromCat.groupName
        local dropGroupChanges = (_dragInsertGroup or false) ~= (fromGroupName or false)
        if target ~= _dragFromCatIdx or dropGroupChanges then
            if isHeader and fromGroup then
                -- Group header drag: move ALL members as a block, using raw dropTarget (not the -1 adjusted target).
                local rawTarget = dropTarget
                local members = EUI_CategoryManager:GetGroupMembers(fromGroup)
                local minIdx = members[1]
                local blockSize = #members
                if rawTarget < minIdx or rawTarget > minIdx + blockSize - 1 then
                    local removed = {}
                    for m = #members, 1, -1 do
                        removed[#removed + 1] = table.remove(cats, members[m])
                    end
                    local ordered = {}
                    for r = #removed, 1, -1 do ordered[#ordered + 1] = removed[r] end
                    local insertAt
                    if rawTarget > minIdx then
                        insertAt = rawTarget - blockSize
                    else
                        insertAt = rawTarget
                    end
                    if insertAt < 1 then insertAt = 1 end
                    if insertAt > #cats + 1 then insertAt = #cats + 1 end
                    -- Junk stays last (as in ReorderCategory)
                    if cats[#cats] and cats[#cats].isJunk and insertAt > #cats then insertAt = #cats end
                    for b = #ordered, 1, -1 do
                        table.insert(cats, insertAt, ordered[b])
                    end
                    -- Persist the block move; without this it reverts on the next
                    -- rebuild (equip-set groups rebuild on every set change).
                    EUI_CategoryManager:SaveState()
                end
            elseif fromGroup then
                -- Grouped member dragged to insert position
                local members = EUI_CategoryManager:GetGroupMembers(fromGroup)
                local minIdx, maxIdx = members[1], members[#members]

                local inGroup = (_dragInsertGroup == fromGroup)
                    or (not _dragInsertGroup and target >= minIdx and target <= maxIdx)
                if inGroup and target ~= _dragFromCatIdx then
                    -- Check if trying to move above the group (target == minIdx from the header button, not the first member)
                    if target == minIdx and _dragFromCatIdx ~= minIdx and #members >= 2 and _dragTargetIsHeader then
                        -- Ungroup and place above the group
                        EUI_CategoryManager:UngroupCategory(_dragFromCatIdx)
                        ClearGroupOrder(fromGroup)
                        local newIdx
                        for i, cat in ipairs(cats) do
                            if cat == fromCat then newIdx = i; break end
                        end
                        if newIdx then
                            EUI_CategoryManager:ReorderCategory(newIdx, minIdx)
                        end
                    else
                        -- Normal intra-group reorder
                        EUI_CategoryManager:ReorderCategory(_dragFromCatIdx, target)
                    end
                    if not EUI_CategoryManager:IsGroupNameCustom(fromGroup) then
                        EUI_CategoryManager:RegenerateGroupName(fromGroup)
                    end
                else
                    -- Drag out of group
                    if #members >= 1 then
                        EUI_CategoryManager:UngroupCategory(_dragFromCatIdx)
                        ClearGroupOrder(fromGroup)
                        -- Re-find index after ungroup may have shifted things
                        local newIdx
                        for i, cat in ipairs(cats) do
                            if cat == fromCat then newIdx = i; break end
                        end
                        if newIdx then
                            -- Check if destination is inside another group -- auto-join it
                            local destGroup = _dragInsertGroup
                            if destGroup == fromGroup then destGroup = nil end
                            if destGroup then
                                EUI_CategoryManager:ReorderCategory(newIdx, target)
                                -- Re-find after move
                                for i, cat in ipairs(cats) do
                                    if cat == fromCat then
                                        EUI_CategoryManager:AddToGroup(i, destGroup)
                                        break
                                    end
                                end
                                if not EUI_CategoryManager:IsGroupNameCustom(destGroup) then
                                    EUI_CategoryManager:RegenerateGroupName(destGroup)
                                end
                            else
                                EUI_CategoryManager:ReorderCategory(newIdx, target)
                            end
                        end
                    end
                end
            else
                -- Check if insert position is inside a group -- auto-join that group
                local destGroup = _dragInsertGroup
                if destGroup then
                    EUI_CategoryManager:ReorderCategory(_dragFromCatIdx, target)
                    for i, cat in ipairs(cats) do
                        if cat == fromCat then
                            EUI_CategoryManager:AddToGroup(i, destGroup)
                            break
                        end
                    end
                    if not EUI_CategoryManager:IsGroupNameCustom(destGroup) then
                        EUI_CategoryManager:RegenerateGroupName(destGroup)
                    end
                else
                    EUI_CategoryManager:ReorderCategory(_dragFromCatIdx, target)
                end
            end
        end
    end

    -- Re-sort any categories affected by group membership changes
    local newFromCat = nil
    for i, cat in ipairs(cats) do if cat == fromCat then newFromCat = cat; break end end
    local oldGroup = fromGroup
    local newGroup = newFromCat and newFromCat.groupName
    if oldGroup ~= newGroup then
        local resortCats = {}
        -- Find the moved category's current index
        for i, cat in ipairs(cats) do
            if cat == fromCat then resortCats[#resortCats + 1] = i; break end
        end
        if oldGroup then
            local oldMembers = EUI_CategoryManager:GetGroupMembers(oldGroup)
            if oldMembers then
                for _, mi in ipairs(oldMembers) do resortCats[#resortCats + 1] = mi end
            end
        end
        if newGroup then
            local newMembers = EUI_CategoryManager:GetGroupMembers(newGroup)
            if newMembers then
                for _, mi in ipairs(newMembers) do resortCats[#resortCats + 1] = mi end
            end
        end
        ResortAfterGroupChange(resortCats, newGroup or oldGroup)
        if oldGroup and newGroup and oldGroup ~= newGroup then
            ResortAfterGroupChange({}, oldGroup)
        end
    end

    -- Restore selection by reference (index may have shifted during reorder)
    if selectedCatRef then
        for i, cat in ipairs(cats) do
            if cat == selectedCatRef then SetSelectedCategoryIndex(i); break end
        end
    end
    SetSelectedGroupName(savedGroupName)

    _dragFromCatIdx = nil
    _dragSourceBtn = nil
    _dragLastTarget = nil
    _dragLastMode = nil
    _dragLastBtn = nil
    _dragDropMode = nil
    _dragDropTarget = nil
    _dragTargetIsHeader = nil
    _dragInsertGroup = nil
    _dragUpdateFrame:Hide()
    if _dragGhost then _dragGhost:Hide() end
    if _dragInsertLine then _dragInsertLine:Hide() end
    if _dragGroupHL then _dragGroupHL:Hide() end
    if EUI_Bags._unlockSort then EUI_Bags._unlockSort() end
    EUI_Bags:RefreshInventory()
end

local function CreateSidebar()
    if EUI_Bags._sidebar then return end

    local sidebar = CreateFrame("Frame", nil, EUI_Bags)
    sidebar:SetPoint("TOPLEFT", EUI_Bags, "TOPLEFT", 0, -(HEADER_H))
    sidebar:SetPoint("BOTTOMLEFT", EUI_Bags.Footer, "TOPLEFT", 0, 0)
    sidebar:SetWidth(GetSidebarWidth())
    sidebar.bg = sidebar:CreateTexture(nil, "BACKGROUND", nil, 2)
    sidebar.bg:SetAllPoints()
    sidebar.bg:SetColorTexture(0, 0, 0, 0.25)

    -- Right-edge separator
    local PP = EUI and EUI.PP
    local px = (PP and PP.mult) or 1
    sidebar.sep = sidebar:CreateTexture(nil, "ARTWORK")
    sidebar.sep:SetWidth(px)
    sidebar.sep:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", 0, 0)
    sidebar.sep:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebar.sep:SetColorTexture(0.15, 0.15, 0.15, 1)

    -- Sidebar header: "Categories" label + collapse arrow
    local sidebarHdr, collapseBtn, UpdateCollapseArrow = ns.CreateSidebarHeader(sidebar, EllesmereUI.L("Categories"), "bagSidebarCollapsed")

    -- The expand arrow left of the window title, shown while a collapsed
    -- sidebar hides (Hide Sidebar Icons When Collapsed; BuildSidebarButtons)
    local titleArrow = ns.SidebarArrowButton(EUI_Bags.Header, "Expand Sidebar")
    titleArrow:SetPoint("LEFT", EUI_Bags.Header, "LEFT", 8, 0)
    titleArrow._icon:SetRotation(math.pi)
    titleArrow:Hide()

    local function ToggleSidebar()
        local center = EUI_Bags:GetCenter()
        local screenW = UIParent:GetWidth()
        local onRightSide = center and screenW and (center > screenW / 2)
        local oldRight = onRightSide and EUI_Bags:GetRight() or nil
        local oldTop = onRightSide and EUI_Bags:GetTop() or nil

        BP().bagSidebarCollapsed = not BP().bagSidebarCollapsed
        UpdateCollapseArrow()
        sidebar:SetWidth(GetSidebarWidth())
        EUI_Bags:RefreshInventory()

        if onRightSide and oldRight and oldTop then
            local left = oldRight - EUI_Bags:GetWidth()
            EUI_Bags:ClearAllPoints()
            EUI_Bags:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, oldTop)
            BP().bagsPosition = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = oldTop }
        end
    end
    collapseBtn:SetScript("OnClick", ToggleSidebar)
    titleArrow:SetScript("OnClick", function()
        EUI.HideWidgetTooltip()
        ToggleSidebar()
    end)

    -- Sidebar scroll frame (below header, above footer)
    local sidebarSF = CreateFrame("ScrollFrame", nil, sidebar)
    sidebarSF:SetPoint("TOPLEFT", sidebarHdr, "BOTTOMLEFT", 0, 0)
    sidebarSF:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarSF:EnableMouseWheel(true)
    local sidebarChild = CreateFrame("Frame", nil, sidebarSF)
    sidebarChild:SetWidth(GetSidebarWidth())
    sidebarSF:SetScrollChild(sidebarChild)

    local SIDEBAR_SCROLL_STEP = 28
    sidebarSF:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = sidebarChild:GetHeight() - self:GetHeight()
        if maxScroll <= 0 then return end
        local cur = self:GetVerticalScroll()
        local newVal = math.max(0, math.min(maxScroll, cur - delta * SIDEBAR_SCROLL_STEP))
        self:SetVerticalScroll(newVal)
    end)

    EUI_Bags._sidebar = sidebar
    EUI_Bags._sidebarHdr = sidebarHdr
    EUI_Bags._sidebarSF = sidebarSF
    EUI_Bags._sidebarChild = sidebarChild
    EUI_Bags._collapseBtn = collapseBtn
    EUI_Bags._titleArrow = titleArrow
end

-- One-time tip on the sidebar's categories: they can be dragged to reorder.
-- New users only (an account that ran Bags before it starts with it seen:
-- bags_category_tip_existing_seen_v1 in EllesmereUI_Migration.lua). Shown
-- whenever the bags open with the sidebar showing, until its Okay is
-- clicked (EllesmereUIDB.bagCategoryTipSeen); a sidebar that hides takes it
-- down until the next time. Its arrow points at the first category that can
-- be dragged (past the fixed views and the unmovable Pinned / Recent rows),
-- re-anchored on every sidebar build. It never first shows in combat (the box
-- takes the mouse over the grid), and it waits while its row is scrolled out
-- of the list's view.
function ns.ShowCategoryTip()
    if EllesmereUIDB.bagCategoryTipSeen then return end
    local sidebar, sf = EUI_Bags._sidebar, EUI_Bags._sidebarSF
    if not (sidebar and sidebar:IsShown() and EUI_Bags:IsShown()) then return end
    local tip = EUI_Bags._catTip
    if InCombatLockdown() and not (tip and tip:IsShown()) then return end
    if not EUI_Bags._catTipScrollHooked then
        EUI_Bags._catTipScrollHooked = true
        sf:HookScript("OnVerticalScroll", function()
            if not EllesmereUIDB.bagCategoryTipSeen then ns.ShowCategoryTip() end
        end)
    end
    local target
    for i = 1, #_sidebarBtns do
        local b = _sidebarBtns[i]
        if b:IsShown() and (b._catIdx or 0) >= 1 and not b._noMove then target = b; break end
    end
    if not target then return end
    local _, cy = target:GetCenter()
    local top, bottom = sf:GetTop(), sf:GetBottom()
    if not (cy and top and bottom and cy <= top and cy >= bottom) then
        if tip then tip:Hide() end
        return
    end
    if not tip then
        -- The panel tips' metrics (the CDM tip's), the height fitted to the text
        tip = EllesmereUI.BuildTipCallout(EUI_Bags, {
            width = 250, arrow = "left",
            text = EllesmereUI.L("Categories can be dragged\nto reorder them."),
            strata = false, level = EUI_Bags:GetFrameLevel() + 60,
            font = EUI.GetFontPath("bags"), fontSize = 12, spacing = 4,
            textTop = 15, gap = 12, btnBottom = 12,
            onOkay = function() EllesmereUIDB.bagCategoryTipSeen = true end,
        })
        EUI_Bags._catTip = tip
    end
    -- Drawn at the options panel's density (GetPopupScale on UIParent: one unit
    -- = one physical pixel x Window Scale) whatever the bag window's and the
    -- UI's scale, so it matches the panel's tips; built with PanelPP for that.
    tip:SetScale(UIParent:GetEffectiveScale() * EllesmereUI.GetPopupScale() / EUI_Bags:GetEffectiveScale())
    tip:ClearAllPoints()
    tip:SetPoint("LEFT", target, "RIGHT", 12, 0)
    if not tip:IsShown() then EllesmereUI.ShowTipCallout(tip) end
end

-- Controller cursor: a pad has no middle click and no drag, so while one is in
-- use the category menu also offers unpinning, removing assigned items and
-- moving the entry one place up or down. A move runs the drag's own drop
-- path (StopSidebarDrag) with the neighbour the sidebar shows.
local function PadCategoryEntries(root, btn, cat, catIdx, isGroupHeader, isGroupMember)
    local rows = {}

    -- Pinned Items: every pinned item in the bags, once per pin key.
    if cat.isPinned then
        local pinned = EllesmereUIDB and EllesmereUIDB.bagPinnedItems
        local seen
        for bag = 0, 5 do
            for slot = 1, (pinned and C_Container.GetContainerNumSlots(bag) or 0) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local link = info and info.itemID and C_Container.GetContainerItemLink(bag, slot)
                if info and info.itemID and IsItemPinned(pinned, link, info.itemID) then
                    local key = NormalizePinKey(link, info.itemID)
                    seen = seen or {}
                    if key and not seen[key] then
                        seen[key] = true
                        local itemID = info.itemID
                        rows[#rows + 1] = { text = link or tostring(itemID), fn = function()
                            local p = EllesmereUIDB and EllesmereUIDB.bagPinnedItems
                            if p then p[key] = nil; p[itemID] = nil end
                            EUI_Bags:RefreshInventory()
                        end }
                    end
                end
            end
        end
        rows.title = EllesmereUI.L("Unpin Item")
    -- A category items can be assigned to: every item assigned to it.
    elseif not isGroupHeader and EUI_CategoryManager:CanAssignToCategory(catIdx) then
        local assignments = EllesmereUIDB and EllesmereUIDB.bagItemAssignments
        local catKey = cat._defaultName
        if assignments and catKey then
            for itemID, aKey in pairs(assignments) do
                if aKey == catKey then
                    local name, link = GetItemInfo(itemID)
                    rows[#rows + 1] = { text = link or name or ("item:" .. itemID), sort = name or "", fn = function()
                        EUI_CategoryManager:UnassignItem(itemID)
                        EUI_Bags:RefreshInventory()
                    end }
                end
            end
            table.sort(rows, function(a, b) return a.sort < b.sort end)
        end
        rows.title = EllesmereUI.L("Remove Assigned Item")
    end

    -- Move Up / Move Down against the neighbouring sidebar rows.
    local me
    for i = 1, #_sidebarBtns do
        if _sidebarBtns[i] == btn and btn:IsShown() then me = i; break end
    end
    local function Row(j)
        local b = _sidebarBtns[j]
        if b and b:IsShown() then return b end
    end
    local upTarget, downTarget, moveGroup
    -- Junk stays last: it never moves (ReorderCategory keeps the rest above it)
    if me and not cat.noMove and not btn._noMove and not cat.isJunk then
        local group = cat.groupName
        if isGroupMember and group then
            -- Within its own group only (set children are skipped).
            local j = me - 1
            while Row(j) and Row(j)._isEquipSet do j = j - 1 end
            local q = Row(j)
            if q and q._isGroupMember and q._groupName == group then upTarget = q._catIdx end
            j = me + 1
            while Row(j) and Row(j)._isEquipSet do j = j + 1 end
            q = Row(j)
            if q and q._isGroupMember and q._groupName == group then downTarget = q._catIdx + 1 end
            moveGroup = group
        else
            -- A plain category, or a group header moving its whole block past
            -- the neighbouring entry (a whole group counts as one entry).
            local j = me - 1
            while Row(j) and (Row(j)._isEquipSet or Row(j)._isGroupMember) do j = j - 1 end
            local q = Row(j)
            if q and q._catIdx > 0 and not q._noMove then upTarget = q._catIdx end
            j = me + 1
            while Row(j) and (Row(j)._isEquipSet or (isGroupHeader and Row(j)._isGroupMember and Row(j)._groupName == group)) do
                j = j + 1
            end
            q = Row(j)
            if q and q._catIdx > 0 and not q._noMove then
                if q._isGroupHeader and q._groupName then
                    local members = EUI_CategoryManager:GetGroupMembers(q._groupName)
                    if #members > 0 then downTarget = members[#members] + 1 end
                else
                    local nextCat = EUI_CategoryManager:GetCategories()[q._catIdx]
                    if not (nextCat and nextCat.isJunk) then downTarget = q._catIdx + 1 end
                end
            end
        end
    end
    local function Move(target)
        -- The sidebar may have been rebuilt while the menu was open: act only
        -- when the same row still shows the same category.
        if EUI_CategoryManager:GetCategories()[catIdx] ~= cat or btn._catIdx ~= catIdx or not btn:IsShown()
            or (btn._isGroupHeader or false) ~= (isGroupHeader or false) then
            return
        end
        _dragFromCatIdx = catIdx
        _dragSourceBtn = btn
        _dragDropMode = "insert"
        _dragDropTarget = target
        _dragInsertGroup = moveGroup
        _dragTargetIsHeader = false
        StopSidebarDrag()
    end

    if #rows == 0 and not upTarget and not downTarget then return end
    root:CreateDivider()
    if upTarget then root:CreateButton(EllesmereUI.L("Move Up"), function() Move(upTarget) end) end
    if downTarget then root:CreateButton(EllesmereUI.L("Move Down"), function() Move(downTarget) end) end
    if #rows > 0 then
        local sub = root:CreateButton(rows.title)
        -- A long list scrolls inside the menu instead of running off screen.
        if #rows > 20 then sub:SetScrollMode(20 * 20) end
        for _, r in ipairs(rows) do sub:CreateButton(r.text, r.fn) end
    end
end

-- Show context menu for grouping categories
local function ShowCategoryContextMenu(btn, catIdx, isGroupHeader, isGroupMember)
    local cats = EUI_CategoryManager:GetCategories()
    local cat = cats[catIdx]
    if not cat then return end
    -- Set children have no menu actions (rename/group/hide all N/A): no empty menu
    if cat.isEquipSet then return end

    MenuUtil.CreateContextMenu(btn, function(_, rootDescription)
        local myGroup = cat.groupName

        if not BP().bagHiddenInAllItems then BP().bagHiddenInAllItems = {} end
        local hiddenSet = BP().bagHiddenInAllItems

        if isGroupHeader and myGroup then
            rootDescription:CreateButton(EllesmereUI.L("Rename"), function()
                if not EUI.ShowInputPopup then return end
                EUI:ShowInputPopup({
                    title = "Rename Group",
                    message = EllesmereUI.L("Enter a new name for this group:"),
                    placeholder = myGroup,
                    confirmText = "Rename",
                    cancelText = "Cancel",
                    onConfirm = function(newName)
                        newName = newName and strtrim(newName) or ""
                        if newName == "" or newName == myGroup then return end
                        EUI_CategoryManager:RenameGroup(myGroup, newName)
                        EUI_CategoryManager:SetGroupNameCustom(newName, true)
                        if selectedGroupName == myGroup then SetSelectedGroupName(newName) end
                        EUI_Bags:RefreshInventory()
                    end,
                })
            end)
            rootDescription:CreateButton(EllesmereUI.L("Disband Group"), function()
                ClearGroupOrder(myGroup)
                EUI_CategoryManager:DisbandGroup(myGroup)
                if selectedGroupName == myGroup then SetSelectedGroupName(nil); SetSelectedCategoryIndex(0) end
                EUI_Bags:RefreshInventory()
            end)
            local groupHidden = hiddenSet[myGroup]
            rootDescription:CreateButton(groupHidden and EllesmereUI.L("Show in All Items") or EllesmereUI.L("Hide in All Items"), function()
                hiddenSet[myGroup] = not groupHidden or nil
                EUI_Bags:RefreshInventory()
            end)
        elseif isGroupMember and myGroup then
            rootDescription:CreateButton(EllesmereUI.L("Rename"), function()
                if not EUI.ShowInputPopup then return end
                EUI:ShowInputPopup({
                    title = "Rename Category",
                    message = EllesmereUI.Lf("Enter a new name for \"%1$s\":", cat.name),
                    placeholder = cat.name,
                    confirmText = "Rename",
                    cancelText = "Cancel",
                    onConfirm = function(newName)
                        newName = newName and strtrim(newName) or ""
                        if newName == "" or newName == cat.name then return end
                        EUI_CategoryManager:RenameCategory(catIdx, newName)
                        EUI_Bags:RefreshInventory()
                    end,
                })
            end)
            rootDescription:CreateButton(EllesmereUI.Lf("Ungroup %1$s", cat.name), function()
                ClearGroupOrder(myGroup)
                EUI_CategoryManager:UngroupCategory(catIdx)
                EUI_Bags:RefreshInventory()
            end)
        else
            -- Equip-set categories are named by the set; renames would not persist
            if not cat.isEquipSet then
            rootDescription:CreateButton(EllesmereUI.L("Rename"), function()
                if not EUI.ShowInputPopup then return end
                EUI:ShowInputPopup({
                    title = "Rename Category",
                    message = EllesmereUI.Lf("Enter a new name for \"%1$s\":", cat.name),
                    placeholder = cat.name,
                    confirmText = "Rename",
                    cancelText = "Cancel",
                    onConfirm = function(newName)
                        newName = newName and strtrim(newName) or ""
                        if newName == "" or newName == cat.name then return end
                        EUI_CategoryManager:RenameCategory(catIdx, newName)
                        EUI_Bags:RefreshInventory()
                    end,
                })
            end)
            end

            if not cat.noGroup then
                local groupSub = rootDescription:CreateButton(EllesmereUI.L("Create Group With"))
                local hasOptions = false
                for ci, other in ipairs(cats) do
                    if ci ~= catIdx and not other.groupName and not other.noGroup then
                        hasOptions = true
                        groupSub:CreateButton(other.name, function()
                            EUI_CategoryManager:GroupCategories({ catIdx, ci })
                            EUI_Bags:RefreshInventory()
                        end)
                    end
                end

                local groupNames = EUI_CategoryManager:GetGroupNames()
                if #groupNames > 0 then
                    local addSub = rootDescription:CreateButton(EllesmereUI.L("Add to Group"))
                    for _, gn in ipairs(groupNames) do
                        addSub:CreateButton(gn, function()
                            EUI_CategoryManager:AddToGroup(catIdx, gn)
                            EUI_Bags:RefreshInventory()
                        end)
                    end
                end
            end

            -- Equip-set children don't render standalone in All Items (they fold
            -- into their anchor's section), so hide/show doesn't apply to them.
            if not cat.noMove and not cat.isEquipSet then
                local catKey = cat._defaultName
                local catHidden = hiddenSet[catKey]
                rootDescription:CreateButton(catHidden and EllesmereUI.L("Show in All Items") or EllesmereUI.L("Hide in All Items"), function()
                    hiddenSet[catKey] = not catHidden or nil
                    EUI_Bags:RefreshInventory()
                end)
            end
        end

        -- Controller cursor: unpin / remove / move entries (no middle click or drag on a pad).
        if EUI.PadInUse() then
            PadCategoryEntries(rootDescription, btn, cat, catIdx, isGroupHeader, isGroupMember)
        end
    end)
end

local function BuildSidebarButtons(categoryCounts, totalCount)
    local sidebar = EUI_Bags._sidebar
    if not sidebar then return end
    local collapsed = BP().bagSidebarCollapsed
    local sidebarW = GetSidebarWidth()
    sidebar:SetWidth(sidebarW)
    -- A collapsed sidebar with no icon strip hides; its expand arrow sits left
    -- of the window title meanwhile (the tip on the categories waits for it)
    local hidden = sidebarW == 0
    if EUI_Bags._sidebarHidden ~= hidden then
        EUI_Bags._sidebarHidden = hidden
        sidebar:SetShown(not hidden)
        local hdr = EUI_Bags.Header
        EUI_Bags._titleArrow:SetShown(hidden)
        hdr.title:ClearAllPoints()
        hdr.title:SetPoint("LEFT", hdr, "LEFT", hidden and 24 or 8, 0)
        if hidden and EUI_Bags._catTip then EUI_Bags._catTip:Hide() end
    end
    -- Nothing to paint on a hidden sidebar: un-hiding comes back through here
    if hidden then return end

    if EUI_Bags._sidebarHdr then
        if collapsed then EUI_Bags._sidebarHdr._label:Hide()
        else EUI_Bags._sidebarHdr._label:Show() end
    end

    local cats = EUI_CategoryManager and EUI_CategoryManager:GetCategories() or {}

    -- Build display list: { catIdx, name, icon, count, isGroupHeader, groupName, indent }
    local displayList = {}
    -- Three fixed views; the configured default type first, then canonical order.
    local _fixedViews = {
        all      = { catIdx = 0,  name = EllesmereUI.L("All Items"), icon = 133633, count = totalCount },
        onebag   = { catIdx = -1, name = EllesmereUI.L("OneBag"),    icon = 133634, count = totalCount },
        multibag = { catIdx = -2, name = EllesmereUI.L("MultiBag"),  icon = 133635, count = totalCount },
    }
    local _dbt = GetDefaultBagType()
    displayList[#displayList + 1] = _fixedViews[_dbt] or _fixedViews.all
    for _, _k in ipairs({ "all", "onebag", "multibag" }) do
        if _k ~= _dbt then displayList[#displayList + 1] = _fixedViews[_k] end
    end

    -- Split-mode set children: rendered nested under the "Item Set Gear" anchor
    -- wherever it sits (plain or inside a group), skipped by the main loop.
    -- Scan gated on split mode: zero extra work while it's off.
    local setChildren, setChildTotal = nil, 0
    if BP().bagSplitSetGearBySet then
        for i, c in ipairs(cats) do
            if c.isEquipSet then
                setChildren = setChildren or {}
                setChildren[#setChildren + 1] = i
                setChildTotal = setChildTotal + (categoryCounts and categoryCounts[i] or 0)
            end
        end
    end
    local function EmitSetChildren(level)
        if not setChildren or collapsed then return end
        for _, sci in ipairs(setChildren) do
            local sc = cats[sci]
            displayList[#displayList + 1] = {
                catIdx = sci, name = sc.name, icon = sc.icon or 134400,
                count = categoryCounts and categoryCounts[sci] or 0,
                indent = level, isEquipSet = true,
            }
        end
    end
    local function IsSetAnchor(c) return c and c.isSetGear and not c.isEquipSet end

    local renderedGroups = {}
    for ci, cat in ipairs(cats) do
        if cat.groupName then
            if not renderedGroups[cat.groupName] then
                renderedGroups[cat.groupName] = true
                -- Group header: sum counts of all members (+ set children on the anchor)
                local members = EUI_CategoryManager:GetGroupMembers(cat.groupName)
                local groupCount = 0
                for _, mi in ipairs(members) do
                    groupCount = groupCount + (categoryCounts and categoryCounts[mi] or 0)
                    if IsSetAnchor(cats[mi]) then groupCount = groupCount + setChildTotal end
                end
                -- Use first member's icon for group
                local firstCat = cats[members[1]]
                local groupIcon = firstCat and firstCat.icon or 134400
                local groupIsAtlas = firstCat and firstCat.isAtlas
                -- Check if any member is user-created (keep group visible if so)
                local groupHasUserCreated = false
                for _, mi in ipairs(members) do
                    if cats[mi] and cats[mi].isUserCreated then groupHasUserCreated = true; break end
                end
                displayList[#displayList + 1] = {
                    catIdx = members[1], name = cat.groupName, icon = groupIcon, isAtlas = groupIsAtlas,
                    count = groupCount, isGroupHeader = true, groupName = cat.groupName,
                    isUserCreated = groupHasUserCreated,
                }
                -- Indented members (hidden when collapsed)
                if not collapsed then
                    for _, mi in ipairs(members) do
                        local mc = cats[mi]
                        local anchor = IsSetAnchor(mc)
                        displayList[#displayList + 1] = {
                            catIdx = mi, name = mc.name, icon = mc.icon or 134400, isAtlas = mc.isAtlas,
                            count = (categoryCounts and categoryCounts[mi] or 0) + (anchor and setChildTotal or 0),
                            indent = true, groupName = cat.groupName, isGroupMember = true,
                            isUserCreated = mc.isUserCreated,
                        }
                        -- Set children: third level under a grouped anchor
                        if anchor then EmitSetChildren(2) end
                    end
                end
            end
        elseif cat.isEquipSet then
            -- Emitted by EmitSetChildren under the anchor
        else
            local anchor = IsSetAnchor(cat)
            local count = (categoryCounts and categoryCounts[ci] or 0) + (anchor and setChildTotal or 0)
            local isUserCreated = not cat.isCatchAll and (not cat.types or #cat.types == 0)
            -- Skip Pinned/Recent Items if disabled
            if cat.isPinned and BP().bagShowPinnedItems == false then
                -- skip
            elseif cat.isRecent and BP().bagShowRecentItems == false then
                -- skip
            else
                displayList[#displayList + 1] = { catIdx = ci, name = cat.name, icon = cat.icon or 134400, isAtlas = cat.isAtlas, count = count, noMove = cat.noMove, isPinned = cat.isPinned, isRecent = cat.isRecent, isUserCreated = cat.isUserCreated }
                if anchor then EmitSetChildren(1) end
            end
        end
    end

    -- Hide empty categories (sidebar-only visual, does not affect grouping)
    local hideEmpty = BP().bagHideEmptyCategories ~= false
    if hideEmpty then
        local filtered = {}
        for _, entry in ipairs(displayList) do
            local keep = true
            if entry.count == 0 then
                -- Always keep: All Items, OneBag, noMove (Pinned/Recent), user-created
                if entry.catIdx >= 1 and not entry.noMove and not entry.isUserCreated then
                    if entry.isGroupHeader then
                        -- Hide group header if all members are 0
                        keep = false
                    elseif entry.isGroupMember then
                        keep = false
                    else
                        keep = false
                    end
                end
            end
            if keep then filtered[#filtered + 1] = entry end
        end
        displayList = filtered
    end

    for i = 1, #displayList do
        if not _sidebarBtns[i] then
            local btn = CreateFrame("Button", nil, EUI_Bags._sidebarChild or sidebar)
            btn:SetHeight(SIDEBAR_BTN_H)
            btn._indicator = btn:CreateTexture(nil, "OVERLAY")
            local PP = EUI and EUI.PP
            local px = (PP and PP.mult) or 1
            btn._indicator:SetWidth(px * 2)
            btn._indicator:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
            btn._indicator:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
            btn._bg = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
            btn._bg:SetAllPoints()
            btn._bg:SetColorTexture(1, 1, 1, 0)
            btn._icon = btn:CreateTexture(nil, "ARTWORK")
            btn._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
            btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._label = btn:CreateFontString(nil, "OVERLAY")
            SetBagFont(btn._label, 11)
            btn._label:SetJustifyH("LEFT")
            btn._label:SetWordWrap(false)
            btn._label:SetPoint("LEFT", btn._icon, "RIGHT", 6, 0)
            btn._label:SetPoint("RIGHT", btn, "RIGHT", -30, 0)
            btn._count = btn:CreateFontString(nil, "OVERLAY")
            SetBagFont(btn._count, 10)
            btn._count:SetJustifyH("RIGHT")
            btn._count:SetTextColor(0.5, 0.5, 0.5)
            btn._count:SetPoint("RIGHT", btn, "RIGHT", -6, 0)

            btn:SetScript("OnEnter", function(self)
                if _dragFromCatIdx then return end
                local isSel = (self._isGroupHeader and self._groupName == selectedGroupName)
                    or (not self._isGroupHeader and self._catIdx == selectedCategoryIndex and not selectedGroupName)
                if not isSel then self._bg:SetColorTexture(1, 1, 1, 0.06) end
                if (BP().bagSidebarCollapsed) and EUI.ShowWidgetTooltip then
                    EUI.ShowWidgetTooltip(self, (self._catName or "?") .. " (" .. (self._catCount or 0) .. ")")
                end
            end)
            btn:SetScript("OnLeave", function(self)
                local isSel = (self._isGroupHeader and self._groupName == selectedGroupName)
                    or (not self._isGroupHeader and self._catIdx == selectedCategoryIndex and not selectedGroupName)
                if not isSel then self._bg:SetColorTexture(1, 1, 1, 0) end
                EUI.HideWidgetTooltip()
            end)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if self._catIdx > 0 then ShowCategoryContextMenu(self, self._catIdx, self._isGroupHeader, self._isGroupMember) end
                    return
                end
                -- Drag-to-sidebar: if the cursor holds an item, assign it to this category
                if self._catIdx and self._catIdx > 0 then
                    local cursorType, cursorItemID = GetCursorInfo()
                    if cursorType == "item" and cursorItemID then
                        if EUI_CategoryManager and EUI_CategoryManager:CanAssignToCategory(self._catIdx) then
                            local cats = EUI_CategoryManager:GetCategories()
                            local cat = cats[self._catIdx]
                            if cat then
                                EUI_CategoryManager:AssignItem(cursorItemID, cat._defaultName)
                                ClearCursor()
                                EUI_Bags:RefreshInventory()
                                return
                            end
                        end
                    end
                end
                if self._didDrag then self._didDrag = false; return end
                if self._isGroupHeader and self._groupName then
                    SetSelectedGroupName(self._groupName)
                    SetSelectedCategoryIndex(0)
                elseif self._isGroupMember and self._groupName then
                    SetSelectedGroupName(nil)
                    SetSelectedCategoryIndex(self._catIdx)
                else
                    SetSelectedGroupName(nil)
                    SetSelectedCategoryIndex(self._catIdx)
                end
                if EUI_Bags._scrollFrame then EUI_Bags._scrollFrame:SetVerticalScroll(0) end
                EUI_Bags:RefreshInventory()
            end)
            btn:SetScript("OnMouseDown", function(self, button)
                if button ~= "LeftButton" then return end
                -- Equip-set cats and Junk: ReorderCategory rejects them; don't start the drag either
                if self._catIdx <= 0 or self._noMove or self._isEquipSet then return end
                local dragCat = EUI_CategoryManager:GetCategories()[self._catIdx]
                if dragCat and dragCat.isJunk then return end
                self._didDrag = false
                local _, startY = GetCursorPosition()
                self._dragStartY = startY
                self._dragPending = true
                _sidebarDragDetect._btn = self
                _sidebarDragDetect:Show()
            end)
            btn:SetScript("OnMouseUp", function(self, button)
                if button ~= "LeftButton" then return end
                self._dragPending = false
                _sidebarDragDetect:Hide()
                if self._didDrag then StopSidebarDrag() end
            end)


            _sidebarBtns[i] = btn
        end
    end

    for i = #displayList + 1, #_sidebarBtns do _sidebarBtns[i]:Hide() end

    local sidebarChild = EUI_Bags._sidebarChild

    -- Separator line between All Items/OneBag and categories
    if not sidebar._catDivider then
        local PP = EUI and EUI.PP
        local px = (PP and PP.mult) or 1
        local div = (sidebarChild or sidebar):CreateTexture(nil, "ARTWORK")
        div:SetHeight(px)
        div:SetColorTexture(0.2, 0.2, 0.2, 1)
        sidebar._catDivider = div
    end

    -- Position and populate (buttons go in the scroll child)
    if sidebarChild then sidebarChild:SetWidth(sidebarW) end
    local y = 0
    local ar, ag, ab = GetAccentRGB()
    local INDENT = SIDEBAR_INDENT

    for i, entry in ipairs(displayList) do
        local btn = _sidebarBtns[i]
        local isSelected
        if entry.isGroupHeader then
            isSelected = (entry.groupName == selectedGroupName)
        else
            isSelected = (not selectedGroupName and entry.catIdx == selectedCategoryIndex)
        end

        btn._catIdx = entry.catIdx
        btn._catName = entry.name
        btn._catIcon = entry.icon
        btn._catIsAtlas = entry.isAtlas
        btn._catCount = entry.count
        btn._isGroupHeader = entry.isGroupHeader or false
        btn._isGroupMember = entry.isGroupMember or false
        btn._groupName = entry.groupName
        btn._noMove = entry.noMove or false
        btn._isEquipSet = entry.isEquipSet or false
        btn._isPinned = entry.isPinned or false

        btn:SetParent(sidebarChild or sidebar)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", sidebarChild or sidebar, "TOPLEFT", 0, y)
        btn:SetWidth(sidebarW)

        -- entry.indent: true = 1 level (legacy group members), or a number of levels
        local indentLv = (entry.indent == true and 1) or entry.indent or 0
        local leftPad = (indentLv ~= 0 and not collapsed) and (8 + INDENT * indentLv) or 8
        btn._icon:ClearAllPoints()
        if collapsed then
            btn._icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
        else
            btn._icon:SetPoint("LEFT", btn, "LEFT", leftPad, 0)
        end
        if entry.isAtlas then
            btn._icon:SetAtlas(entry.icon)
            btn._icon:SetTexCoord(0, 1, 0, 1)
        else
            -- Through the client icon map: a default the Forever client
            -- cannot draw takes its vanilla-era stand-in there.
            btn._icon:SetTexture(EllesmereUI.ClientIcon(entry.icon))
            btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        btn._icon:SetAlpha(isSelected and 1 or 0.75)
        -- Smaller icon for indented members
        if entry.indent then
            btn._icon:SetSize(SIDEBAR_ICON_SIZE - 2, SIDEBAR_ICON_SIZE - 2)
        else
            btn._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
        end

        if collapsed then
            btn._label:Hide()
            btn._count:Hide()
        else
            btn._label:Show()
            btn._label:SetText(entry.name)
            btn._label:SetTextColor(1, 1, 1, isSelected and 1 or 0.75)

            btn._count:Show()
            btn._count:SetText(tostring(entry.count))
        end

        if isSelected then
            btn._indicator:SetColorTexture(ar, ag, ab, 1)
            btn._indicator:Show()
            btn._bg:SetColorTexture(ar, ag, ab, 0.1)
        else
            btn._indicator:Hide()
            btn._bg:SetColorTexture(1, 1, 1, 0)
        end

        btn:Show()
        y = y - SIDEBAR_BTN_H - SIDEBAR_PAD

        -- Divider after the last special entry (Pinned or Recent)
        local isLastSpecial = entry.isPinned or entry.isRecent
        local nextEntry = displayList[i + 1]
        local nextIsRegular = nextEntry and not nextEntry.isPinned and not nextEntry.isRecent
        if isLastSpecial and nextIsRegular and sidebar._catDivider then
            y = y - 4  -- spacing above line
            local div = sidebar._catDivider
            div:SetParent(sidebarChild or sidebar)
            div:ClearAllPoints()
            local inset = math.floor(sidebarW * 0.08)
            div:SetPoint("TOPLEFT", sidebarChild or sidebar, "TOPLEFT", inset, y)
            div:SetPoint("TOPRIGHT", sidebarChild or sidebar, "TOPRIGHT", -inset, y)
            div:Show()
            y = y - (div:GetHeight() or 1) - 4  -- spacing below line
        end
    end

    -- "+Add Category" button at the bottom of the sidebar
    local hideAddCat = BP().bagHideAddCategory
    if not collapsed and not hideAddCat then
        if not sidebar._addCatBtn then
            local btn = CreateFrame("Button", nil, sidebarChild or sidebar)
            btn:SetHeight(SIDEBAR_BTN_H)
            btn._bg = btn:CreateTexture(nil, "BACKGROUND", nil, 2)
            btn._bg:SetAllPoints()
            btn._bg:SetColorTexture(1, 1, 1, 0)
            btn._icon = btn:CreateTexture(nil, "ARTWORK")
            btn._icon:SetSize(SIDEBAR_ICON_SIZE, SIDEBAR_ICON_SIZE)
            btn._icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
            btn._icon:SetTexture(134400)
            btn._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn._icon:SetAlpha(0.5)
            btn._label = btn:CreateFontString(nil, "OVERLAY")
            SetBagFont(btn._label, 11)
            btn._label:SetJustifyH("LEFT")
            btn._label:SetWordWrap(false)
            btn._label:SetPoint("LEFT", btn._icon, "RIGHT", 6, 0)
            btn._label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            btn._label:SetText(EllesmereUI.L("Add Category"))
            btn._label:SetTextColor(1, 1, 1, 0.4)
            btn:SetScript("OnEnter", function(self)
                self._bg:SetColorTexture(1, 1, 1, 0.06)
                self._label:SetTextColor(1, 1, 1, 0.8)
                self._icon:SetAlpha(0.8)
            end)
            btn:SetScript("OnLeave", function(self)
                self._bg:SetColorTexture(1, 1, 1, 0)
                self._label:SetTextColor(1, 1, 1, 0.4)
                self._icon:SetAlpha(0.5)
            end)
            btn:SetScript("OnClick", function(self)
                local popup = EUI_Bags._newCatPopup
                if popup and popup:IsShown() then popup:Hide(); return end
                if not popup then
                    popup = CreateFrame("Frame", nil, EUI_Bags)
                    popup:SetFrameStrata("DIALOG")
                    popup:SetSize(240, 230)
                    popup:EnableMouse(true)
                    local bg = popup:CreateTexture(nil, "BACKGROUND")
                    bg:SetAllPoints()
                    bg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
                    local PP = EUI and EUI.PP
                    if PP and PP.CreateBorder then PP.CreateBorder(popup, 0.2, 0.2, 0.2, 1) end

                    local title = popup:CreateFontString(nil, "OVERLAY")
                    SetBagFont(title, 13)
                    title:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -10)
                    title:SetTextColor(1, 1, 1, 0.9)
                    title:SetText(EllesmereUI.L("New Custom Category"))

                    local eb = CreateFrame("EditBox", nil, popup)
                    eb:SetSize(220, 22)
                    eb:SetPoint("TOPLEFT", popup, "TOPLEFT", 10, -30)
                    eb:SetAutoFocus(false)
                    eb:SetFont(GetFont(), 12, "")
                    eb:SetTextColor(1, 1, 1, 1)
                    eb:SetTextInsets(6, 6, 0, 0)
                    eb:SetMaxLetters(30)
                    local ebBg = eb:CreateTexture(nil, "BACKGROUND")
                    ebBg:SetAllPoints()
                    ebBg:SetColorTexture(0.1, 0.1, 0.1, 1)
                    if PP and PP.CreateBorder then PP.CreateBorder(eb, 0.15, 0.15, 0.15, 1) end
                    eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
                    eb:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
                    popup._nameEB = eb

                    local iconLbl = popup:CreateFontString(nil, "OVERLAY")
                    SetBagFont(iconLbl, 11)
                    iconLbl:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -8)
                    iconLbl:SetTextColor(0.7, 0.7, 0.7, 1)
                    iconLbl:SetText(EllesmereUI.L("Icon:"))

                    -- Forever does not include the newer icon files used by the
                    -- Midnight picker. Keep its choices to long-standing client
                    -- icons, including a profession icon.
                    local ICON_IDS = EUI_CLIENT_FOREVER and {
                        134400, 132996, 136240, 136241, 136242, 136244, 136245,
                        136246, 136247, 136248, 136249, 132485, 132640, 134332,
                    } or {
                        7514178, 7548926, 7427980, 7548966, 2143125,
                        6025441, 7451177, 7548901, 7501337, 7704166,
                        7549083, 7549010, 7136579, 7549012,
                    }
                    popup._iconIDs = ICON_IDS
                    local ICON_SZ = 28
                    local ICON_PAD = 4
                    local ICONS_PER_ROW = 7
                    local iconBtns = {}
                    popup._selectedIcon = ICON_IDS[1]
                    popup._customMode = false

                    local ar, ag, ab = GetAccentRGB()
                    local bPx = (PP and PP.mult or 1) * 2

                    -- Helper: update selection highlight across grid + custom
                    local function UpdateSelection()
                        for _, ob in ipairs(iconBtns) do ob._border:Hide() end
                        if popup._customBorder then popup._customBorder:Hide() end
                        if popup._customMode then
                            if popup._customBorder then popup._customBorder:Show() end
                        else
                            for _, ob in ipairs(iconBtns) do
                                if ob._iconID == popup._selectedIcon then
                                    ob._border:Show(); break
                                end
                            end
                        end
                    end
                    popup._updateSelection = UpdateSelection

                    for idx, iconID in ipairs(ICON_IDS) do
                        local ib = CreateFrame("Button", nil, popup)
                        ib:SetSize(ICON_SZ, ICON_SZ)
                        local col = (idx - 1) % ICONS_PER_ROW
                        local row = math.floor((idx - 1) / ICONS_PER_ROW)
                        ib:SetPoint("TOPLEFT", iconLbl, "BOTTOMLEFT", col * (ICON_SZ + ICON_PAD), -(4 + row * (ICON_SZ + ICON_PAD)))
                        local tex = ib:CreateTexture(nil, "ARTWORK")
                        tex:SetAllPoints()
                        tex:SetTexture(iconID)
                        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        ib._tex = tex
                        ib._iconID = iconID
                        -- Accent-colored 2px border for selection
                        local border = CreateFrame("Frame", nil, ib)
                        border:SetPoint("TOPLEFT", -bPx, bPx)
                        border:SetPoint("BOTTOMRIGHT", bPx, -bPx)
                        border:SetFrameLevel(ib:GetFrameLevel() + 2)
                        local bTop = border:CreateTexture(nil, "OVERLAY"); bTop:SetColorTexture(ar, ag, ab, 1)
                        bTop:SetPoint("TOPLEFT"); bTop:SetPoint("TOPRIGHT"); bTop:SetHeight(bPx)
                        local bBot = border:CreateTexture(nil, "OVERLAY"); bBot:SetColorTexture(ar, ag, ab, 1)
                        bBot:SetPoint("BOTTOMLEFT"); bBot:SetPoint("BOTTOMRIGHT"); bBot:SetHeight(bPx)
                        local bLeft = border:CreateTexture(nil, "OVERLAY"); bLeft:SetColorTexture(ar, ag, ab, 1)
                        bLeft:SetPoint("TOPLEFT"); bLeft:SetPoint("BOTTOMLEFT"); bLeft:SetWidth(bPx)
                        local bRight = border:CreateTexture(nil, "OVERLAY"); bRight:SetColorTexture(ar, ag, ab, 1)
                        bRight:SetPoint("TOPRIGHT"); bRight:SetPoint("BOTTOMRIGHT"); bRight:SetWidth(bPx)
                        border:Hide()
                        ib._border = border
                        ib:SetScript("OnClick", function(s)
                            popup._selectedIcon = s._iconID
                            popup._customMode = false
                            popup._prevTex:SetTexture(s._iconID)
                            UpdateSelection()
                        end)
                        ib:SetScript("OnEnter", function(s) s._tex:SetAlpha(1) end)
                        ib:SetScript("OnLeave", function(s) s._tex:SetAlpha(0.85) end)
                        ib._tex:SetAlpha(0.85)
                        iconBtns[idx] = ib
                    end
                    popup._iconBtns = iconBtns

                    -- Custom icon ID label + preview + editbox
                    local lastRow = math.ceil(#ICON_IDS / ICONS_PER_ROW)
                    local customLbl = popup:CreateFontString(nil, "OVERLAY")
                    SetBagFont(customLbl, 11)
                    customLbl:SetPoint("TOPLEFT", iconLbl, "BOTTOMLEFT", 0, -(4 + lastRow * (ICON_SZ + ICON_PAD) + 6))
                    customLbl:SetTextColor(0.7, 0.7, 0.7, 1)
                    customLbl:SetText(EllesmereUI.L("Custom Icon ID:"))

                    local preview = CreateFrame("Frame", nil, popup)
                    preview:SetSize(22, 22)
                    preview:SetPoint("TOPLEFT", customLbl, "BOTTOMLEFT", 0, -4)
                    local prevTex = preview:CreateTexture(nil, "ARTWORK")
                    prevTex:SetAllPoints()
                    prevTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    prevTex:SetTexture(ICON_IDS[1])
                    popup._prevTex = prevTex
                    -- Accent border on the preview (for custom mode)
                    local cBorder = CreateFrame("Frame", nil, preview)
                    cBorder:SetPoint("TOPLEFT", -bPx, bPx)
                    cBorder:SetPoint("BOTTOMRIGHT", bPx, -bPx)
                    cBorder:SetFrameLevel(preview:GetFrameLevel() + 2)
                    local cbTop = cBorder:CreateTexture(nil, "OVERLAY"); cbTop:SetColorTexture(ar, ag, ab, 1)
                    cbTop:SetPoint("TOPLEFT"); cbTop:SetPoint("TOPRIGHT"); cbTop:SetHeight(bPx)
                    local cbBot = cBorder:CreateTexture(nil, "OVERLAY"); cbBot:SetColorTexture(ar, ag, ab, 1)
                    cbBot:SetPoint("BOTTOMLEFT"); cbBot:SetPoint("BOTTOMRIGHT"); cbBot:SetHeight(bPx)
                    local cbLeft = cBorder:CreateTexture(nil, "OVERLAY"); cbLeft:SetColorTexture(ar, ag, ab, 1)
                    cbLeft:SetPoint("TOPLEFT"); cbLeft:SetPoint("BOTTOMLEFT"); cbLeft:SetWidth(bPx)
                    local cbRight = cBorder:CreateTexture(nil, "OVERLAY"); cbRight:SetColorTexture(ar, ag, ab, 1)
                    cbRight:SetPoint("TOPRIGHT"); cbRight:SetPoint("BOTTOMRIGHT"); cbRight:SetWidth(bPx)
                    cBorder:Hide()
                    popup._customBorder = cBorder

                    local customEB = CreateFrame("EditBox", nil, popup)
                    customEB:SetSize(80, 22)
                    customEB:SetPoint("LEFT", preview, "RIGHT", 8, 0)
                    customEB:SetAutoFocus(false)
                    customEB:SetFont(GetFont(), 11, "")
                    customEB:SetTextColor(1, 1, 1, 1)
                    customEB:SetTextInsets(4, 4, 0, 0)
                    customEB:SetNumeric(true)
                    local cBg = customEB:CreateTexture(nil, "BACKGROUND")
                    cBg:SetAllPoints()
                    cBg:SetColorTexture(0.1, 0.1, 0.1, 1)
                    if PP and PP.CreateBorder then PP.CreateBorder(customEB, 0.15, 0.15, 0.15, 1) end
                    customEB:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
                    customEB:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
                    customEB:SetScript("OnTextChanged", function(s)
                        local txt = s:GetText()
                        local id = tonumber(txt)
                        if txt and txt ~= "" and id and id > 0 then
                            popup._selectedIcon = id
                            popup._customMode = true
                            prevTex:SetTexture(id)
                        else
                            popup._customMode = false
                        end
                        UpdateSelection()
                    end)
                    popup._customEB = customEB

                    local createBtn = CreateFrame("Button", nil, popup)
                    createBtn:SetSize(220, 26)
                    createBtn:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 10, 10)
                    local cBtnBg = createBtn:CreateTexture(nil, "BACKGROUND")
                    cBtnBg:SetAllPoints()
                    cBtnBg:SetColorTexture(0.15, 0.15, 0.15, 1)
                    if PP and PP.CreateBorder then PP.CreateBorder(createBtn, 0.25, 0.25, 0.25, 1) end
                    local cBtnLbl = createBtn:CreateFontString(nil, "OVERLAY")
                    SetBagFont(cBtnLbl, 12)
                    cBtnLbl:SetPoint("CENTER")
                    cBtnLbl:SetTextColor(1, 1, 1, 0.9)
                    cBtnLbl:SetText(EllesmereUI.L("Create"))
                    createBtn:SetScript("OnEnter", function() cBtnBg:SetColorTexture(0.2, 0.2, 0.2, 1) end)
                    createBtn:SetScript("OnLeave", function() cBtnBg:SetColorTexture(0.15, 0.15, 0.15, 1) end)
                    -- Red flash validation for empty fields
                    local function MakeFlashBorder(parent)
                        local fb = CreateFrame("Frame", nil, parent)
                        fb:SetPoint("TOPLEFT", -1, 1)
                        fb:SetPoint("BOTTOMRIGHT", 1, -1)
                        fb:SetFrameLevel(parent:GetFrameLevel() + 5)
                        local edges = {}
                        local function MakeEdge(p1, p2, isHoriz)
                            local t = fb:CreateTexture(nil, "OVERLAY")
                            t:SetColorTexture(0.9, 0.15, 0.15, 0)
                            if isHoriz then
                                t:SetPoint(p1); t:SetPoint(p2); t:SetHeight(1)
                            else
                                t:SetPoint(p1); t:SetPoint(p2); t:SetWidth(1)
                            end
                            edges[#edges + 1] = t
                        end
                        MakeEdge("TOPLEFT", "TOPRIGHT", true)
                        MakeEdge("BOTTOMLEFT", "BOTTOMRIGHT", true)
                        MakeEdge("TOPLEFT", "BOTTOMLEFT", false)
                        MakeEdge("TOPRIGHT", "BOTTOMRIGHT", false)
                        fb._edges = edges
                        fb._elapsed = 0
                        fb._active = false
                        fb:SetScript("OnUpdate", function(self, dt)
                            if not self._active then self:Hide(); return end
                            self._elapsed = self._elapsed + dt
                            if self._elapsed >= 0.7 then
                                self._active = false
                                for _, e in ipairs(self._edges) do e:SetColorTexture(0.9, 0.15, 0.15, 0) end
                                self:Hide()
                                return
                            end
                            local t = self._elapsed / 0.7
                            local a = 0.7 * (1 - t)
                            for _, e in ipairs(self._edges) do e:SetColorTexture(0.9, 0.15, 0.15, a) end
                        end)
                        fb:Hide()
                        fb.Flash = function(self)
                            self._elapsed = 0
                            self._active = true
                            for _, e in ipairs(self._edges) do e:SetColorTexture(0.9, 0.15, 0.15, 0.7) end
                            self:Show()
                        end
                        return fb
                    end
                    local nameFlash = MakeFlashBorder(eb)
                    popup._nameFlash = nameFlash

                    createBtn:SetScript("OnClick", function()
                        local name = popup._nameEB:GetText()
                        if not name or name == "" then
                            popup._nameFlash:Flash()
                            popup._nameEB:SetFocus()
                            return
                        end
                        local icon = popup._selectedIcon or 134400
                        local idx = EUI_CategoryManager:AddCustomCategory(name)
                        if idx then
                            local cats = EUI_CategoryManager:GetCategories()
                            if cats[idx] then
                                cats[idx].icon = icon
                                cats[idx].isAtlas = nil
                            end
                            EUI_CategoryManager:SaveState()
                        end
                        popup:Hide()
                        EUI_Bags:RefreshInventory()
                    end)

                    -- EnableKeyboard and SetPropagateKeyboardInput are protected in
                    -- combat: the popup takes the keyboard as it shows out of combat
                    -- (below) and stands aside in it, keys reaching the game.
                    popup:SetScript("OnKeyDown", function(s, key)
                        if InCombatLockdown() then return end
                        if key == "ESCAPE" then s:Hide(); s:SetPropagateKeyboardInput(false)
                        else s:SetPropagateKeyboardInput(true) end
                    end)
                    -- Controller cursor: Cancel finds Add Category, which toggles the popup closed.
                    if EUI.PadCP() then popup.CloseButton = self end

                    EUI_Bags._newCatPopup = popup
                end
                popup._nameEB:SetText("")
                popup._customEB:SetText("")
                popup._selectedIcon = popup._iconIDs[1]
                popup._customMode = false
                popup._prevTex:SetTexture(popup._iconIDs[1])
                popup._updateSelection()
                popup:ClearAllPoints()
                popup:SetPoint("BOTTOMLEFT", self, "BOTTOMRIGHT", 4, 0)
                if not InCombatLockdown() then
                    popup:EnableKeyboard(true)
                    popup:SetPropagateKeyboardInput(true)
                end
                popup:Show()
                popup._nameEB:SetFocus()
            end)
            sidebar._addCatBtn = btn
        end
        local addBtn = sidebar._addCatBtn
        addBtn:SetParent(sidebarChild or sidebar)
        addBtn:ClearAllPoints()
        addBtn:SetPoint("TOPLEFT", sidebarChild or sidebar, "TOPLEFT", 0, y - 4)
        addBtn:SetWidth(sidebarW)
        addBtn:Show()
        y = y - SIDEBAR_BTN_H - 4
    elseif sidebar._addCatBtn then
        sidebar._addCatBtn:Hide()
    end

    if sidebarChild then
        sidebarChild:SetHeight(math.abs(y) + 4)
    end

    -- The one-time "categories can be dragged" tip follows its category row
    if not EllesmereUIDB.bagCategoryTipSeen then ns.ShowCategoryTip() end
end

I.BuildSidebarButtons, I.CreateSidebar = BuildSidebarButtons, CreateSidebar
I.GetSidebarWidth = GetSidebarWidth
I.broken = false
