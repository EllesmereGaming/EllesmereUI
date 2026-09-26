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
--  talent config, the same one the filter reads, and conditions are stored per
--  spec, so what the popup shows is exactly what decides the icon.
--
--  Frames are built on first open and reused; nothing exists until then.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUICooldownManager"]
if not ns then return end

local PP = EllesmereUI.PP

local POPUP_W, POPUP_H = 940, 620
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

local CLASS_HALF, SPEC_HALF = 1, 2
local EMPTY = {}

local function FontPath()
    return (EllesmereUI.GetFontPath("cdm"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
end
local Outline = EllesmereUI.GetFontOutlineFlag

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
    local taken = false
    if (info.activeRank or 0) > 0 then
        taken = (info.activeEntry and info.activeEntry.entryID) or true
    end
    return {
        nodeID = nodeID,
        x = info.posX or 0,
        y = info.posY or 0,
        entries = entries,
        choice = (info.type == Enum.TraitNodeType.Selection) and #entries > 1,
        edges = info.visibleEdges,
        taken = taken,   -- current build: active entryID, true, or false
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
local dimmer, popup, titleFS, statusFS
-- [half] = { frame, label, area, empty, lines = {}, buttons = {}, used = 0 }. Each panel
-- keeps its own button pool so a button never changes parent (its border's frame level
-- is fixed when it is built).
local panels = {}
local pending = {}     -- nodeID -> { nodeID, entryID, spellID, taken }
local offTree = {}     -- saved conditions on nodes the current tree does not show; kept as-is
local onConfirm

local RepaintAll, UpdateStatus

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

local function ButtonOnLeave()
    GameTooltip:Hide()
end

-- Taken > Not Taken > cleared. On a choice node the condition names one side,
-- so clicking the other half moves it there (starting again at Taken).
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
    RepaintAll()
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
--  Frames (built once, on first open)
-------------------------------------------------------------------------------
local function MakeButton(parent, text, accent)
    local ar, ag, ab = EllesmereUI.GetAccentColor()
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(90, 28)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(FontPath(), 12, Outline())
    lbl:SetPoint("CENTER")
    lbl:SetText(text)
    local r, g, b, a
    if accent then
        bg:SetColorTexture(ar, ag, ab, 0.15)
        EllesmereUI.MakeBorder(btn, ar, ag, ab, 0.3, PP)
        r, g, b, a = ar, ag, ab, 0.9
    else
        bg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
        EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.10, PP)
        r, g, b, a = 0.7, 0.7, 0.7, 0.8
    end
    lbl:SetTextColor(r, g, b, a)
    btn:SetScript("OnEnter", function() lbl:SetTextColor(1, 1, 1, 1) end)
    btn:SetScript("OnLeave", function() lbl:SetTextColor(r, g, b, a) end)
    return btn
end

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
    label:SetFont(FontPath(), 12, Outline())
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", AREA_PAD, -6)
    label:SetTextColor(0.85, 0.85, 0.85, 1)

    local area = CreateFrame("Frame", nil, frame)
    area:SetSize(AREA_W, AREA_H)
    area:SetPoint("TOPLEFT", frame, "TOPLEFT", AREA_PAD, -PANEL_LABEL_H)

    local empty = frame:CreateFontString(nil, "OVERLAY")
    empty:SetFont(FontPath(), 11, Outline())
    empty:SetPoint("CENTER")
    empty:SetTextColor(0.6, 0.6, 0.6, 0.8)
    empty:SetText(EllesmereUI.L("Talent data is not available right now."))
    empty:Hide()

    panels[half] = { frame = frame, label = label, area = area, empty = empty,
                     lines = {}, buttons = {}, used = 0 }
end

local function Close()
    GameTooltip:Hide()
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
    -- Clamped: two trees side by side are wide, and the dimmer eats every click
    -- behind it, so an overflowing popup would strand its buttons off-screen.
    dimmer, popup = EllesmereUI.BuildPopupShell("EUI_CDM_TalentConditions", {
        w = POPUP_W, h = POPUP_H, dimAlpha = 0.25, clamp = true,
        onEscape = Close, onDimmerDown = Close,
    })
    dimmer:Hide()

    titleFS = popup:CreateFontString(nil, "OVERLAY")
    titleFS:SetFont(FontPath(), 14, Outline())
    titleFS:SetPoint("TOP", popup, "TOP", 0, -16)
    titleFS:SetTextColor(1, 1, 1, 1)

    local hint = popup:CreateFontString(nil, "OVERLAY")
    hint:SetFont(FontPath(), 11, Outline())
    hint:SetPoint("TOP", titleFS, "BOTTOM", 0, -6)
    hint:SetTextColor(0.7, 0.7, 0.7, 0.85)
    hint:SetText(EllesmereUI.L("Click a talent to require it: Taken, then Not Taken, then cleared. Every condition must hold for the icon to show."))

    MakePanel(CLASS_HALF)
    MakePanel(SPEC_HALF)

    statusFS = popup:CreateFontString(nil, "OVERLAY")
    statusFS:SetFont(FontPath(), 11, Outline())
    statusFS:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", SIDE_PAD, 22)
    statusFS:SetPoint("RIGHT", popup, "RIGHT", -330, 0)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetWordWrap(false)

    local saveBtn = MakeButton(popup, EllesmereUI.L("Save"), true)
    saveBtn:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -SIDE_PAD, 14)
    saveBtn:SetScript("OnClick", Commit)

    local cancelBtn = MakeButton(popup, EllesmereUI.L("Cancel"), false)
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
    cancelBtn:SetScript("OnClick", Close)

    local clearBtn = MakeButton(popup, EllesmereUI.L("Clear All"), false)
    clearBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -8, 0)
    clearBtn:SetScript("OnClick", function()
        wipe(pending)
        wipe(offTree)
        RepaintAll()
        UpdateStatus()
    end)

    dimmer:SetScript("OnHide", function() onConfirm = nil end)
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
-- they hold, red while they do not. state nil hides it. Built on first use.
function ns.PaintTalentCondMark(slot, state)
    local mark = slot._tcMark
    if not state then
        if mark then mark:Hide() end
        return
    end
    if not mark then
        mark = CreateFrame("Frame", nil, slot)
        mark:SetFrameLevel(slot:GetFrameLevel() + 6)
        mark:EnableMouse(false)
        mark._tex = mark:CreateTexture(nil, "OVERLAY")
        mark._tex:SetAllPoints()
        EllesmereUI.MakeBorder(mark, 0, 0, 0, 1, EllesmereUI.PanelPP)
        slot._tcMark = mark
    end
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
    GameTooltip:Hide()

    local spellName = C_Spell.GetSpellName(spellID) or tostring(spellID)
    titleFS:SetText(EllesmereUI.Lf("Talent Conditions: %1$s", spellName))

    local halves, specName = ReadTree()
    panels[CLASS_HALF].label:SetText((UnitClass("player")) or "")
    panels[SPEC_HALF].label:SetText(specName or "")
    LayoutHalf(panels[CLASS_HALF], halves and halves[CLASS_HALF])
    LayoutHalf(panels[SPEC_HALF], halves and halves[SPEC_HALF])

    -- Seed the edit copy. A condition on a node this tree does not show (a
    -- talent a patch removed) cannot be clicked here; it is kept untouched
    -- unless Clear All drops it.
    wipe(pending)
    wipe(offTree)
    local shown = {}
    for _, panel in ipairs(panels) do
        for i = 1, panel.used do shown[panel.buttons[i].node.nodeID] = true end
    end
    for _, c in ipairs(type(conds) == "table" and conds or EMPTY) do
        if type(c) == "table" and c.nodeID then
            local copy = { nodeID = c.nodeID, entryID = c.entryID, spellID = c.spellID, taken = c.taken ~= false }
            if shown[c.nodeID] and not pending[c.nodeID] then
                pending[c.nodeID] = copy
            else
                offTree[#offTree + 1] = copy
            end
        end
    end

    onConfirm = confirm
    RepaintAll()
    UpdateStatus()
    dimmer:Show()
end
