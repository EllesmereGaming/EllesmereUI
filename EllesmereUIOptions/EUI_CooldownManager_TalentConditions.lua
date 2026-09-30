if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_CooldownManager_TalentConditions.lua
--  Talent Conditions popup for the CDM per-icon menu (cooldown/utility bars).
--  Draws the current spec's class tree and spec tree side by side, laid out
--  from the game's own node positions, and lets the user mark talents:
--  click cycles Taken > Not Taken > cleared. A choice node is split in two
--  halves so either side can be picked. Hero trees are out of scope.
--
--  Storage, evaluation and the reanchor filter live in the CDM addon
--  (EllesmereUICdmTalentConditions.lua). The tree read here is the ACTIVE
--  talent config's committed build, the same one the filter reads, and
--  conditions are stored per spec, so what the popup shows is exactly what
--  decides the icon. A saved condition no drawn node can show (a talent a
--  patch removed, or a choice side that no longer exists) is listed under the
--  trees with its own remove, since it still decides the icon.
--
--  Frames are built on first open and reused; nothing exists until then.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
if not ns then return end

local PP = EllesmereUI.PP

local POPUP_W, POPUP_H = 940, 620
-- Bump over the dimmer's panel scale: the popup draws at panelScale px per unit, the
-- density of the sibling CDM popups that every size below assumes.
local POPUP_BUMP = 1.2
local HEADER_H, FOOTER_H = 70, 56
local SIDE_PAD, PANEL_GAP = 16, 12
local PANEL_W = (POPUP_W - SIDE_PAD * 2 - PANEL_GAP) / 2
local PANEL_H = POPUP_H - HEADER_H - FOOTER_H
local PANEL_LABEL_H = 24
local AREA_PAD = 12
local AREA_W = PANEL_W - AREA_PAD * 2
local AREA_H = PANEL_H - PANEL_LABEL_H - AREA_PAD
local NODE = 26
local BORDER_PX, MARK_PX = 1, 3
local NOT_TAKEN_R, NOT_TAKEN_G, NOT_TAKEN_B = 0.95, 0.30, 0.30
-- Footer buttons (MakeActionButton rows are 38 tall).
local BTN_W, BTN_GAP, BTN_BOTTOM, BTN_H = 110, 8, 9, 38
-- Off-tree strip: one chip per condition no drawn node shows, four per row.
local OFF_PAD, OFF_LABEL_H = 10, 22
local CHIP_COLS, CHIP_W, CHIP_H, CHIP_GAP_X, CHIP_GAP_Y = 4, 218, 26, 12, 6
local CLOSE_ICON = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"

local CLASS_HALF, SPEC_HALF = 1, 2
local EMPTY = {}

local function SetTCFont(fs, size)
    EllesmereUI.ApplyModuleFont(fs, nil, size, "cdm")
end

-------------------------------------------------------------------------------
--  Tree data (read fresh on every open; talents cannot change while it is up
--  in any way that matters, and a stale read only costs a reopen)
-------------------------------------------------------------------------------
local function ReadNode(configID, nodeID, info)
    local entries = {}
    for _, entryID in ipairs(info.entryIDs or EMPTY) do
        local entry = C_Traits.GetEntryInfo(configID, entryID)
        local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
        local spellID = def and def.spellID
        if spellID then
            entries[#entries + 1] = {
                entryID = entryID,
                spellID = spellID,
                icon = def.overrideIcon or C_Spell.GetSpellTexture(spellID) or 134400,
            }
        end
    end
    if #entries == 0 then return nil end
    -- Committed build only, the same test the reanchor filter uses: a pick the
    -- player has staged but not applied is not taken yet (activeRank already
    -- counts it). A granted rank (activeRank above ranksPurchased) cannot be
    -- staged, so it counts as taken.
    local taken = false
    local committed = info.entryIDsWithCommittedRanks
    if committed and #committed > 0 then
        taken = committed[1]
    elseif (info.activeRank or 0) > (info.ranksPurchased or 0) then
        taken = (info.activeEntry and info.activeEntry.entryID) or true
    end
    return {
        nodeID = nodeID,
        x = info.posX or 0,
        y = info.posY or 0,
        entries = entries,
        choice = (info.type == Enum.TraitNodeType.Selection) and #entries > 1,
        edges = info.visibleEdges,
        taken = taken,   -- current build: committed entryID, true, or false
    }
end

-- Horizontal distance from x to a half's column range (0 inside it).
local function RangeDistance(half, x)
    if not half.minX then return math.huge end
    if x < half.minX then return half.minX - x end
    if x > half.maxX then return x - half.maxX end
    return 0
end

-- The active config's tree for the current spec, split into its class half and
-- spec half: { [CLASS_HALF] = nodes, [SPEC_HALF] = nodes }, plus the spec name.
local function ReadTree()
    local configID = C_ClassTalents.GetActiveConfigID()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if not configID or not specIndex or specIndex == 0 then return nil end
    local specID, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    local treeID = specID and C_ClassTalents.GetTraitTreeForSpec(specID)
    local nodeIDs = treeID and C_Traits.GetTreeNodes(treeID)
    if not nodeIDs then return nil end

    -- Which points a node costs tells the halves apart. The game lists the
    -- class currency first and the spec currency second.
    local currencies = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
    local classCur = currencies and currencies[1] and currencies[1].traitCurrencyID
    local specCur = currencies and currencies[2] and currencies[2].traitCurrencyID

    local halves = { {}, {} }
    local free = {}
    for _, nodeID in ipairs(nodeIDs) do
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        if info and info.isVisible and not info.subTreeID
           and info.type ~= Enum.TraitNodeType.SubTreeSelection then
            local node = ReadNode(configID, nodeID, info)
            if node then
                local half
                for _, cost in ipairs(C_Traits.GetNodeCost(configID, nodeID) or EMPTY) do
                    if cost.ID == specCur then half = SPEC_HALF; break end
                    if cost.ID == classCur then half = CLASS_HALF end
                end
                if half then
                    local h = halves[half]
                    h[#h + 1] = node
                    if not h.minX or node.x < h.minX then h.minX = node.x end
                    if not h.maxX or node.x > h.maxX then h.maxX = node.x end
                else
                    free[#free + 1] = node
                end
            end
        end
    end
    -- The starting talents each tree grants cost nothing: place them by position,
    -- into whichever half's columns they sit nearer to.
    for _, node in ipairs(free) do
        local c = RangeDistance(halves[CLASS_HALF], node.x)
        local s = RangeDistance(halves[SPEC_HALF], node.x)
        local h = halves[(s < c) and SPEC_HALF or CLASS_HALF]
        h[#h + 1] = node
    end
    return halves, specName
end

-------------------------------------------------------------------------------
--  Popup state
-------------------------------------------------------------------------------
local dimmer, popup, titleFS, statusFS, offFrame
-- [half] = { frame, label, area, empty, lines = {}, buttons = {}, used = 0 }. Each panel
-- keeps its own button pool so a button never changes parent (its border's frame level
-- is fixed when it is built).
local panels = {}
local chips = {}       -- off-tree chip pool, [i] shows offTree[i]
local pending = {}     -- nodeID -> { nodeID, entryID, spellID, taken }
local offTree = {}     -- saved conditions no drawn node shows; kept unless removed
local onConfirm
local tipOwner         -- node button that set GameTooltip up (hidden only while it owns it)

local RepaintAll, UpdateStatus, LayoutOffTree

local function ConditionOn(btn)
    local c = pending[btn.node.nodeID]
    if c and c.entryID == btn.entryID then return c end
    return nil
end

local function PaintButton(btn)
    local c = ConditionOn(btn)
    if c then
        if c.taken then
            local ar, ag, ab = EllesmereUI.GetAccentColor()
            PP.SetBorderColor(btn, ar, ag, ab, 1)
        else
            PP.SetBorderColor(btn, NOT_TAKEN_R, NOT_TAKEN_G, NOT_TAKEN_B, 1)
        end
        PP.SetBorderSize(btn, MARK_PX)
    else
        PP.SetBorderColor(btn, 0.35, 0.35, 0.35, 0.9)
        PP.SetBorderSize(btn, BORDER_PX)
    end
    -- Current build at a glance: taken talents in full colour, the rest dimmed.
    local t = btn.node.taken
    local takenNow = t ~= false and (btn.entryID == nil or t == btn.entryID)
    btn.icon:SetDesaturated(not takenNow)
    btn.icon:SetAlpha(takenNow and 1 or 0.45)
end

local function ButtonOnEnter(btn)
    tipOwner = btn
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(btn.spellID)
    GameTooltip:AddLine(" ")
    local c = ConditionOn(btn)
    if not c then
        GameTooltip:AddLine(EllesmereUI.L("Click: show only while this talent is taken"), 0.7, 0.7, 0.7, true)
    elseif c.taken then
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        GameTooltip:AddLine(EllesmereUI.L("Shown only while this talent is taken"), ar, ag, ab, true)
        GameTooltip:AddLine(EllesmereUI.L("Click: show only while it is NOT taken"), 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine(EllesmereUI.L("Shown only while this talent is NOT taken"), NOT_TAKEN_R, NOT_TAKEN_G, NOT_TAKEN_B, true)
        GameTooltip:AddLine(EllesmereUI.L("Click: clear"), 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function ButtonOnLeave(btn)
    if GameTooltip:IsOwned(btn) then GameTooltip:Hide() end
    tipOwner = nil
end

-- Taken > Not Taken > cleared. On a choice node the condition names one side,
-- so clicking the other half moves it there (starting again at Taken). Only
-- this node's buttons can change paint.
local function ButtonOnClick(btn)
    local nodeID = btn.node.nodeID
    local c = ConditionOn(btn)
    if not c then
        pending[nodeID] = { nodeID = nodeID, entryID = btn.entryID, spellID = btn.spellID, taken = true }
    elseif c.taken then
        c.taken = false
    else
        pending[nodeID] = nil
    end
    for _, b in ipairs(btn.node.btns) do PaintButton(b) end
    UpdateStatus()
    ButtonOnEnter(btn)
end

local function AcquireButton(panel)
    panel.used = panel.used + 1
    local btn = panel.buttons[panel.used]
    if not btn then
        btn = CreateFrame("Button", nil, panel.area)
        btn:SetFrameLevel(panel.area:GetFrameLevel() + 2)
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetAllPoints()
        PP.CreateBorder(btn, 0.35, 0.35, 0.35, 0.9, BORDER_PX)
        btn:SetScript("OnEnter", ButtonOnEnter)
        btn:SetScript("OnLeave", ButtonOnLeave)
        btn:SetScript("OnClick", ButtonOnClick)
        panel.buttons[panel.used] = btn
    end
    btn:Show()
    return btn
end

-- True when a drawn button can show a condition on this node side.
local function IsDrawn(nodeID, entryID)
    for _, panel in ipairs(panels) do
        for i = 1, panel.used do
            local b = panel.buttons[i]
            if b.node.nodeID == nodeID and b.entryID == entryID then return true end
        end
    end
    return false
end

RepaintAll = function()
    for _, panel in ipairs(panels) do
        for i = 1, panel.used do PaintButton(panel.buttons[i]) end
    end
end

UpdateStatus = function()
    local count, met = 0, true
    for _, c in pairs(pending) do
        count = count + 1
        if ns.TalentCondIsTaken(c.nodeID, c.entryID) ~= c.taken then met = false end
    end
    for _, c in ipairs(offTree) do
        count = count + 1
        if ns.TalentCondIsTaken(c.nodeID, c.entryID) ~= c.taken then met = false end
    end
    if count == 0 then
        statusFS:SetText(EllesmereUI.L("No conditions: the icon always shows."))
        statusFS:SetTextColor(0.7, 0.7, 0.7, 0.9)
    elseif met then
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        statusFS:SetText(EllesmereUI.Lf("%1$d condition(s), met by your current talents: the icon shows.", count))
        statusFS:SetTextColor(ar, ag, ab, 1)
    else
        statusFS:SetText(EllesmereUI.Lf("%1$d condition(s), not met by your current talents: the icon is hidden.", count))
        statusFS:SetTextColor(NOT_TAKEN_R, NOT_TAKEN_G, NOT_TAKEN_B, 1)
    end
end

-------------------------------------------------------------------------------
--  Layout: one half of the tree into one panel, scaled to fit, centred
-------------------------------------------------------------------------------
local function LayoutHalf(panel, nodes)
    local area = panel.area
    local lines = panel.lines
    local usedLines = 0
    for i = 1, panel.used do panel.buttons[i]:Hide() end
    panel.used = 0

    if nodes and #nodes > 0 then
        local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
        for _, n in ipairs(nodes) do
            if n.x < minX then minX = n.x end
            if n.x > maxX then maxX = n.x end
            if n.y < minY then minY = n.y end
            if n.y > maxY then maxY = n.y end
        end
        local spanX = math.max(maxX - minX, 1)
        local spanY = math.max(maxY - minY, 1)
        local scale = math.min((AREA_W - NODE) / spanX, (AREA_H - NODE) / spanY)
        local offX = (AREA_W - (spanX * scale + NODE)) / 2
        local offY = (AREA_H - (spanY * scale + NODE)) / 2

        for _, n in ipairs(nodes) do
            local left = offX + (n.x - minX) * scale
            local top = offY + (n.y - minY) * scale
            n._cx, n._cy = left + NODE / 2, top + NODE / 2
            local parts = n.choice and 2 or 1
            local w = NODE / parts
            n.btns = {}
            for k = 1, parts do
                local e = n.entries[k]
                local btn = AcquireButton(panel)
                btn:SetSize(w, NODE)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", area, "TOPLEFT", left + (k - 1) * w, -top)
                btn.icon:SetTexture(e.icon)
                if n.choice then
                    btn.icon:SetTexCoord(0.27, 0.73, 0.08, 0.92)
                else
                    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
                btn.node = n
                btn.entryID = n.choice and e.entryID or nil
                btn.spellID = e.spellID
                n.btns[k] = btn
            end
        end

        -- Connections, drawn under the nodes. Only edges whose both ends sit in this half.
        local byID = {}
        for _, n in ipairs(nodes) do byID[n.nodeID] = n end
        for _, n in ipairs(nodes) do
            for _, edge in ipairs(n.edges or EMPTY) do
                local target = edge.targetNode and byID[edge.targetNode]
                if target then
                    usedLines = usedLines + 1
                    local line = lines[usedLines]
                    if not line then
                        line = area:CreateLine(nil, "BACKGROUND")
                        line:SetThickness(1.5)
                        lines[usedLines] = line
                    end
                    line:SetColorTexture(0.45, 0.45, 0.45, 0.6)
                    line:SetStartPoint("TOPLEFT", area, n._cx, -n._cy)
                    line:SetEndPoint("TOPLEFT", area, target._cx, -target._cy)
                    line:Show()
                end
            end
        end
    end

    for i = usedLines + 1, #lines do lines[i]:Hide() end
    panel.empty:SetShown(not nodes or #nodes == 0)
end

-------------------------------------------------------------------------------
--  Off-tree strip: conditions no drawn node shows, each with its own remove
-------------------------------------------------------------------------------
local function ChipOnEnter(chip)
    chip.x:SetAlpha(1)
    local c = offTree[chip.index]
    if not c then return end
    local state = c.taken and EllesmereUI.L("Shown only while this talent is taken")
        or EllesmereUI.L("Shown only while this talent is NOT taken")
    EllesmereUI.ShowWidgetTooltip(chip, state .. "\n" .. EllesmereUI.L("Click: clear"))
end

local function ChipOnLeave(chip)
    chip.x:SetAlpha(0.6)
    EllesmereUI.HideWidgetTooltip()
end

local function ChipOnClick(chip)
    if not offTree[chip.index] then return end
    table.remove(offTree, chip.index)
    EllesmereUI.HideWidgetTooltip(true)
    LayoutOffTree()
    UpdateStatus()
    -- The chip under the cursor now shows the next condition: describe that one.
    if offTree[chip.index] then ChipOnEnter(chip) end
end

local function MakeChip(i)
    local chip = CreateFrame("Button", nil, offFrame)
    chip:SetSize(CHIP_W, CHIP_H)
    local bg = chip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.06, 0.08, 1)
    chip.border = EllesmereUI.MakeBorder(chip, 1, 1, 1, 0.10, PP)
    chip.icon = chip:CreateTexture(nil, "ARTWORK")
    chip.icon:SetSize(CHIP_H - 8, CHIP_H - 8)
    chip.icon:SetPoint("LEFT", chip, "LEFT", 4, 0)
    chip.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    chip.x = chip:CreateTexture(nil, "ARTWORK")
    chip.x:SetSize(10, 10)
    chip.x:SetPoint("RIGHT", chip, "RIGHT", -8, 0)
    if chip.x.SetSnapToPixelGrid then chip.x:SetSnapToPixelGrid(false); chip.x:SetTexelSnappingBias(0) end
    chip.x:SetTexture(CLOSE_ICON)
    chip.x:SetAlpha(0.6)
    chip.label = chip:CreateFontString(nil, "OVERLAY")
    SetTCFont(chip.label, 11)
    chip.label:SetPoint("LEFT", chip.icon, "RIGHT", 6, 0)
    chip.label:SetPoint("RIGHT", chip.x, "LEFT", -6, 0)
    chip.label:SetJustifyH("LEFT")
    chip.label:SetWordWrap(false)
    chip.label:SetTextColor(0.85, 0.85, 0.85, 1)
    chip:SetScript("OnEnter", ChipOnEnter)
    chip:SetScript("OnLeave", ChipOnLeave)
    chip:SetScript("OnClick", ChipOnClick)
    chips[i] = chip
    return chip
end

-- Lays the strip out and sizes the popup to it (no strip: the base size). The
-- scale is re-fitted to the new height, so a long list still fits the screen.
LayoutOffTree = function()
    local n = #offTree
    local h = POPUP_H
    if n > 0 then
        local rows = math.ceil(n / CHIP_COLS)
        local stripH = OFF_LABEL_H + rows * CHIP_H + (rows - 1) * CHIP_GAP_Y
        h = POPUP_H + OFF_PAD + stripH
        offFrame:SetHeight(stripH)
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        for i = 1, n do
            local c = offTree[i]
            local chip = chips[i] or MakeChip(i)
            local col = (i - 1) % CHIP_COLS
            local row = math.floor((i - 1) / CHIP_COLS)
            chip:ClearAllPoints()
            chip:SetPoint("TOPLEFT", offFrame, "TOPLEFT", col * (CHIP_W + CHIP_GAP_X),
                -(OFF_LABEL_H + row * (CHIP_H + CHIP_GAP_Y)))
            chip.index = i
            chip.x:SetAlpha(0.6)
            local sid = type(c.spellID) == "number" and c.spellID or nil
            chip.icon:SetTexture((sid and C_Spell.GetSpellTexture(sid)) or 134400)
            chip.label:SetText((sid and C_Spell.GetSpellName(sid)) or EllesmereUI.L("Unknown talent"))
            if c.taken then
                chip.border:SetColor(ar, ag, ab, 1)
            else
                chip.border:SetColor(NOT_TAKEN_R, NOT_TAKEN_G, NOT_TAKEN_B, 1)
            end
            chip:Show()
        end
        offFrame:Show()
    else
        offFrame:Hide()
    end
    for i = n + 1, #chips do chips[i]:Hide() end
    popup:SetHeight(h)
    popup:SetScale(EllesmereUI.PopupBump(POPUP_BUMP))
    EllesmereUI.ClampPopupToScreen(popup, POPUP_W, h)
end

-------------------------------------------------------------------------------
--  Frames (built once, on first open)
-------------------------------------------------------------------------------
local function MakePanel(half)
    local frame = CreateFrame("Frame", nil, popup)
    frame:SetSize(PANEL_W, PANEL_H)
    frame:SetPoint("TOPLEFT", popup, "TOPLEFT",
        SIDE_PAD + (half - 1) * (PANEL_W + PANEL_GAP), -HEADER_H)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.04, 0.06, 0.08, 1)
    EllesmereUI.MakeBorder(frame, 1, 1, 1, 0.10, PP)

    local label = frame:CreateFontString(nil, "OVERLAY")
    SetTCFont(label, 12)
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", AREA_PAD, -6)
    label:SetTextColor(0.85, 0.85, 0.85, 1)

    local area = CreateFrame("Frame", nil, frame)
    area:SetSize(AREA_W, AREA_H)
    area:SetPoint("TOPLEFT", frame, "TOPLEFT", AREA_PAD, -PANEL_LABEL_H)

    local empty = frame:CreateFontString(nil, "OVERLAY")
    SetTCFont(empty, 11)
    empty:SetPoint("CENTER")
    empty:SetTextColor(0.6, 0.6, 0.6, 0.8)
    empty:SetText(EllesmereUI.L("Talent data is not available right now."))
    empty:Hide()

    panels[half] = { frame = frame, label = label, area = area, empty = empty,
                     lines = {}, buttons = {}, used = 0 }
end

local function Close()
    if tipOwner and GameTooltip:IsOwned(tipOwner) then GameTooltip:Hide() end
    tipOwner = nil
    -- A chip hidden under the cursor never gets OnLeave; the modal dimmer means
    -- only this popup can own the widget tooltip here.
    EllesmereUI.HideWidgetTooltip(true)
    dimmer:Hide()
end

local function Commit()
    local out = {}
    for _, c in pairs(pending) do
        out[#out + 1] = { nodeID = c.nodeID, entryID = c.entryID, spellID = c.spellID, taken = c.taken }
    end
    for _, c in ipairs(offTree) do out[#out + 1] = c end
    table.sort(out, function(a, b) return a.nodeID < b.nodeID end)
    -- Hiding clears onConfirm (dimmer OnHide), so take it first.
    local confirm = onConfirm
    Close()
    if confirm then confirm(#out > 0 and out or nil) end
end

local function Build()
    if popup then return end
    -- Dimmer scaled by the panel scale, the popup by its bump (the sibling CDM popups'
    -- density), and registered so the Panel Scale slider rescales it. Clamped: two
    -- trees side by side are wide, and the dimmer eats every click behind it, so an
    -- overflowing popup would strand its buttons off-screen.
    dimmer, popup = EllesmereUI.BuildPopupShell("EUI_CDM_TalentConditions", {
        w = POPUP_W, h = POPUP_H, bump = POPUP_BUMP, dimAlpha = 0.25, clamp = true,
        onEscape = Close, onDimmerDown = Close,
    })
    dimmer:Hide()
    EllesmereUI._popupFrames[#EllesmereUI._popupFrames + 1] = { popup = popup, dimmer = dimmer }

    titleFS = popup:CreateFontString(nil, "OVERLAY")
    SetTCFont(titleFS, 16)
    titleFS:SetPoint("TOP", popup, "TOP", 0, -16)
    titleFS:SetTextColor(1, 1, 1, 1)

    local hint = popup:CreateFontString(nil, "OVERLAY")
    SetTCFont(hint, 11)
    hint:SetPoint("TOP", titleFS, "BOTTOM", 0, -6)
    hint:SetTextColor(0.7, 0.7, 0.7, 0.85)
    hint:SetText(EllesmereUI.L("Click a talent to require it: Taken, then Not Taken, then cleared. Every condition must hold for the icon to show."))

    MakePanel(CLASS_HALF)
    MakePanel(SPEC_HALF)

    offFrame = CreateFrame("Frame", nil, popup)
    offFrame:SetPoint("TOPLEFT", popup, "TOPLEFT", SIDE_PAD, -(HEADER_H + PANEL_H + OFF_PAD))
    offFrame:SetWidth(POPUP_W - SIDE_PAD * 2)
    offFrame:Hide()
    local offLabel = offFrame:CreateFontString(nil, "OVERLAY")
    SetTCFont(offLabel, 11)
    offLabel:SetPoint("TOPLEFT", offFrame, "TOPLEFT", 0, -2)
    offLabel:SetTextColor(0.7, 0.7, 0.7, 0.85)
    offLabel:SetText(EllesmereUI.L("Conditions on talents not shown above (they still apply):"))

    local font = EllesmereUI.GetFontPath("cdm")
    local ar, ag, ab = EllesmereUI.GetAccentColor()
    local saveBtn = EllesmereUI.MakeActionButton(popup, font, EllesmereUI.L("Save"), ar, ag, ab, { w = BTN_W })
    saveBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -SIDE_PAD, BTN_BOTTOM)
    saveBtn:SetScript("OnClick", Commit)

    local cancelBtn = EllesmereUI.MakeActionButton(popup, font, EllesmereUI.L("Cancel"), 1, 1, 1,
        { w = BTN_W, secondary = true, hoverA = 0.8 })
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -BTN_GAP, 0)
    cancelBtn:SetScript("OnClick", Close)
    popup._cancelBtn = cancelBtn

    local clearBtn = EllesmereUI.MakeActionButton(popup, font, EllesmereUI.L("Clear All"), 1, 1, 1,
        { w = BTN_W, secondary = true, hoverA = 0.8 })
    clearBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -BTN_GAP, 0)
    clearBtn:SetScript("OnClick", function()
        wipe(pending)
        wipe(offTree)
        LayoutOffTree()
        RepaintAll()
        UpdateStatus()
    end)

    -- Status line: left of the buttons, on their centre line.
    local statusY = BTN_BOTTOM + BTN_H / 2
    statusFS = popup:CreateFontString(nil, "OVERLAY")
    SetTCFont(statusFS, 11)
    statusFS:SetPoint("LEFT", popup, "BOTTOMLEFT", SIDE_PAD, statusY)
    statusFS:SetPoint("RIGHT", popup, "BOTTOMRIGHT", -(SIDE_PAD + 3 * BTN_W + 3 * BTN_GAP), statusY)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetWordWrap(false)

    -- Hooked, not set: hide hooks the popup shell or the controller cursor put
    -- on this dimmer must survive (with none, this is its only handler).
    dimmer:HookScript("OnHide", function() onConfirm = nil end)
end

-------------------------------------------------------------------------------
--  Options preview helpers (called from the CDM bar preview; kept here so the
--  preview function, already near Lua 5.1's local cap, gains one local only)
-------------------------------------------------------------------------------

-- For a CD/utility bar's assigned ids: id -> "on" when its conditions hold now,
-- "off" when they do not. nil when no assigned spell has a condition.
function ns.TalentCondPreviewSet(barKey, tracked)
    local store = ns.GetSpellSettingsStore(barKey)
    if not store or type(tracked) ~= "table" then return nil end
    local set
    for _, id in ipairs(tracked) do
        local entry = type(id) == "number" and id > 0 and store[id]
        local conds = type(entry) == "table" and rawget(entry, "talentConditions")
        if type(conds) == "table" and #conds > 0 then
            set = set or {}
            set[id] = ns.TalentConditionsHold(conds) and "on" or "off"
        end
    end
    return set
end

-- Small corner mark on a preview slot whose spell carries conditions: accent while
-- they hold, red while they do not. state nil hides it. Built on first use. Kept under
-- the slot's text overlay (its border strips sit one level above the fill), so keybind
-- and stack text stay readable in every icon style (the overlay's level differs per style).
function ns.PaintTalentCondMark(slot, state)
    local mark = slot._tcMark
    if not state then
        if mark then mark:Hide() end
        return
    end
    if not mark then
        mark = CreateFrame("Frame", nil, slot)
        mark:EnableMouse(false)
        mark._tex = mark:CreateTexture(nil, "ARTWORK")
        mark._tex:SetAllPoints()
        PP.CreateBorder(mark, 0, 0, 0, 1, 1, "OVERLAY", 7)
        slot._tcMark = mark
    end
    mark:SetFrameLevel(slot._pvTextOverlay:GetFrameLevel() - 2)
    local size = math.max(6, math.floor((slot:GetWidth() or 0) * 0.28 + 0.5))
    mark:SetSize(size, size)
    mark:ClearAllPoints()
    mark:SetPoint("TOPLEFT", slot, "TOPLEFT", 3, -3)
    if state == "off" then
        mark._tex:SetColorTexture(NOT_TAKEN_R, NOT_TAKEN_G, NOT_TAKEN_B, 1)
    else
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        mark._tex:SetColorTexture(ar, ag, ab, 1)
    end
    mark:Show()
end

-------------------------------------------------------------------------------
--  Entry point (the per-icon menu's "Talent Conditions" row)
--  conds: the spell's saved list (read only here); confirm(newList or nil).
-------------------------------------------------------------------------------
function ns.ShowCDMTalentConditionsPopup(spellID, conds, confirm)
    Build()

    local spellName = C_Spell.GetSpellName(spellID) or tostring(spellID)
    titleFS:SetText(EllesmereUI.Lf("Talent Conditions: %1$s", spellName))

    local halves, specName = ReadTree()
    panels[CLASS_HALF].label:SetText((UnitClass("player")) or "")
    panels[SPEC_HALF].label:SetText(specName or "")
    LayoutHalf(panels[CLASS_HALF], halves and halves[CLASS_HALF])
    LayoutHalf(panels[SPEC_HALF], halves and halves[SPEC_HALF])

    -- Seed the edit copy. A condition no drawn button can show (a talent a patch
    -- removed, a choice side that no longer exists, or a second condition on one
    -- node) goes to the off-tree strip, where it stays until removed there or by
    -- Clear All.
    wipe(pending)
    wipe(offTree)
    for _, c in ipairs(type(conds) == "table" and conds or EMPTY) do
        if type(c) == "table" and c.nodeID then
            local copy = { nodeID = c.nodeID, entryID = c.entryID, spellID = c.spellID, taken = c.taken ~= false }
            if not pending[c.nodeID] and IsDrawn(c.nodeID, c.entryID) then
                pending[c.nodeID] = copy
            else
                offTree[#offTree + 1] = copy
            end
        end
    end

    onConfirm = confirm
    LayoutOffTree()
    RepaintAll()
    UpdateStatus()
    ns.PadPopupOpen(dimmer, popup, popup._cancelBtn, Close)  -- controller cursor
    dimmer:Show()
end
