if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_TargetHelper.lua  (WoW Forever only)
--  A bar of target buttons for quest mobs and farm targets (the list comes
--  from the TargetHelperData file, listed before this one):
--    left click   targets the mob and puts the row's raid marker on it
--                 (secure macro)
--    right click  marker, area, category and remove menu (out of combat)
--  Rows are grouped under category headers that fold on click. A dot shows
--  that a nameplate of the mob is visible, an accent border marks the row of
--  the current target.
--  The secure buttons can't change in combat: a change in combat only updates
--  the rows' looks and the full rebuild runs once combat ends.
-------------------------------------------------------------------------------
local _, module = ...
local TH = module.TargetHelper
local F = TH.F
local Get, Cfg, Enabled = F.Get, F.Cfg, F.Enabled
local Plain, Read, Tbl = TH.Plain, TH.Read, TH.Tbl
local PP = EllesmereUI.PP

local HEADER_H, ROW_H, CAT_H, PAD, GAP = 22, 20, 16, 2, 1
local MAX_ROWS = 15
local MEDIA = "Interface\\AddOns\\EllesmereUIForeverEssentials\\Media\\"
local ARROW = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local ICON_ALPHA, ICON_HOVER_ALPHA = 0.4, 0.9
local QUEST_C = { 0.88, 0.72, 0.31 }
local FARM_C = { 0.44, 0.66, 0.86 }
local NEAR_C = { 0.40, 0.85, 0.50 }
local DANGER_C = { 0.90, 0.30, 0.30 }

local anchor, bar, header, title, countText, emptyText, foldBtn, events
local rows, cats = {}, {}
local pendingRefresh, pendingApply
local nearby = {}   -- [name] = visible nameplates of that name
local plates = {}   -- [unit] = name
local ownMarks = {} -- [GUID] = marker we set ourselves
local pendingMark   -- marker of the last row click, until the client reports it

local Refresh

local function Accent()
    local c = EllesmereUI.ELLESMERE_GREEN
    return c.r, c.g, c.b
end

local function Font(fs, size)
    EllesmereUI.ApplyModuleFont(fs, nil, size, "essentials")
end

local function Text(parent, size, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Font(fs, size)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function NotInCombat()
    if not InCombatLockdown() then return true end
    EllesmereUI.Print(EllesmereUI.L("Not possible in combat."))
end

local function TargetName()
    return UnitExists("target") and TH.UnitNameOf("target") or nil
end

-------------------------------------------------------------------------------
--  Picking a free mob (out of combat only: it sets secure attributes)
--  Among the visible nameplates with the row's name, dead mobs, mobs tagged
--  by other players and mobs a group member marked are skipped. A mob with
--  our own marker comes first, then mobs in interact range, then the one
--  nearest the middle of the screen. Without a usable nameplate (or with a
--  hidden marker) the button falls back to /targetexact. Runs right before
--  the click (PreClick); combat start switches every button back to
--  /targetexact, as nameplate tokens get reused.
-------------------------------------------------------------------------------
local function PlateScore(unit)
    local score = Plain(CheckInteractDistance(unit, 4)) and 0 or 100000
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local x, y = plate and plate:GetCenter()
    if Plain(x) and Plain(y) then
        local sx, sy = UIParent:GetCenter()
        score = score + math.abs(x - sx) + math.abs(y - sy * 0.8)
    end
    return score
end

-- "free" | "own" | "other" | "secret"
local function MarkState(unit, marker)
    local m = GetRaidTargetIndex(unit)
    if issecretvalue(m) then return "secret" end
    if not m then return "free" end
    local guid = Plain(UnitGUID(unit))
    if guid then return ownMarks[guid] == m and "own" or "other" end
    return m == marker and "own" or "other"
end

local function Tapped(unit)
    return Get("skipTapped") and Plain(UnitIsTapDenied(unit)) == true
end

local function Usable(unit, state)
    return not Tapped(unit) and (state ~= "other" or not Get("skipMarked"))
end

-- "keep" | unit | "none" | nil (nil: /targetexact)
local function PickFor(name, marker)
    if not Get("skipMarked") and not Get("skipTapped") then return nil end
    if TargetName() == name and not UnitIsDead("target") then
        local state = MarkState("target", marker)
        if state ~= "secret" and Usable("target", state) then return "keep" end
    end
    local best, bestScore, seen
    for unit, n in pairs(plates) do
        if n == name and UnitExists(unit) and not UnitIsDead(unit) then
            seen = true
            local state = MarkState(unit, marker)
            if state == "secret" then return nil end
            if Usable(unit, state) then
                local score = PlateScore(unit)
                if state == "own" then score = score - 1000000 end
                if not bestScore or score < bestScore then best, bestScore = unit, score end
            end
        end
    end
    if best then return best end
    if seen then return "none" end
end

local function SetMacro(row, text)
    if text ~= row.macro then
        row.macro = text
        row:SetAttribute("macrotext1", text)
    end
end

local function UpdateRowMacro(row)
    local e = row.entry
    if not e or InCombatLockdown() then return end
    local pick = PickFor(e.name, e.marker)
    row.pick = pick
    if pick == "keep" then
        SetMacro(row, TH.MacroKeep(e.marker))
    elseif pick == "none" then
        SetMacro(row, "")
    elseif pick then
        SetMacro(row, TH.MacroForUnit(pick, e.marker))
    else
        SetMacro(row, TH.MacroFor(e.name, e.marker))
    end
end

local function ResetMacros()
    for _, row in ipairs(rows) do
        if row.entry then
            row.pick = nil
            SetMacro(row, TH.MacroFor(row.entry.name, row.entry.marker))
        end
    end
end

-- The target carries the marker we asked for: remember it as ours (a marker
-- exists once, so older mobs with it are forgotten).
local function RecordOwnMark()
    local marker = pendingMark
    if not marker or marker <= 0 or not UnitExists("target") then return end
    local guid = Plain(UnitGUID("target"))
    if not guid or Plain(GetRaidTargetIndex("target")) ~= marker then return end
    pendingMark = nil
    for g, m in pairs(ownMarks) do
        if m == marker then ownMarks[g] = nil end
    end
    ownMarks[guid] = marker
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------
local function UpdateRowState(row)
    local e = row.entry
    if not e then return end
    row.dot:SetShown((nearby[e.name] or 0) > 0)
    if TargetName() == e.name then
        local r, g, b = Accent()
        PP.SetBorderColor(row, r, g, b, 1)
        PP.ShowBorder(row)
    else
        PP.HideBorder(row)
    end
end

local function UpdateAllStates()
    for _, row in ipairs(rows) do
        if row:IsShown() then UpdateRowState(row) end
    end
end

-- A small 3D head of the mob. The NPC id is learned from the GUID whenever
-- such a mob is seen and kept account-wide, unknown mobs show a "?".
local function UpdatePortrait(row, e)
    local show = Get("showPortraits")
    row.portrait:SetShown(show)
    row.name:SetPoint("LEFT", show and row.portrait or row.marker, "RIGHT", 5, 0)
    if not show then return end
    local id = Read("npcIds")[e.name]
    if id then
        if row.portraitId ~= id then
            row.portraitId = id
            row.model:ClearModel()
            row.model:SetCreature(id)
            row.model:SetPortraitZoom(1)
        end
        row.model:Show()
        row.unknown:Hide()
    else
        row.portraitId = nil
        row.model:Hide()
        row.unknown:Show()
    end
end

local function UpdateRowLook(row, e)
    row.entry = e
    UpdatePortrait(row, e)
    local tex = TH.MarkerTexture(e.marker)
    row.marker:SetTexture(tex or TH.NO_MARKER)
    row.marker:SetVertexColor(1, 1, 1, tex and 1 or 0.5)
    row.name:SetText(e.name)
    local c = e.quests[1] and QUEST_C or FARM_C
    row.stripe:SetColorTexture(c[1], c[2], c[3], 0.9)
    local q = e.quests[1]
    row.progress:SetText(q and q.have and q.need and q.need > 0 and (q.have .. "/" .. q.need) or "")
    row:SetAlpha(e.done and 0.35 or 1)
    UpdateRowState(row)
end

local function Hex(c)
    return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

local function RowTooltip(row)
    local e = row.entry
    if not e then return end
    local lines = { e.name }
    for _, q in ipairs(e.quests) do
        local prog = (q.have and q.need) and (" |cffffffff" .. q.have .. "/" .. q.need .. "|r") or ""
        lines[#lines + 1] = Hex(QUEST_C) .. q.title .. "|r" .. prog
    end
    if e.farm then
        local f = TH.FarmEntry(e.name)
        local sub = f and f.sub
        lines[#lines + 1] = Hex(FARM_C) .. (sub and EllesmereUI.Lf("Farm target, only in %s", sub) or EllesmereUI.L("Farm target")) .. "|r"
    end
    if e.marker and e.marker > 0 then
        lines[#lines + 1] = EllesmereUI.Lf("Marker: %s", _G["RAID_TARGET_" .. e.marker])
    end
    if row.pick == "none" then
        lines[#lines + 1] = Hex(DANGER_C) .. EllesmereUI.L("All visible ones are marked or tagged") .. "|r"
    end
    if (nearby[e.name] or 0) > 0 then
        lines[#lines + 1] = Hex(NEAR_C) .. EllesmereUI.L("Nearby") .. "|r"
    end
    lines[#lines + 1] = EllesmereUI.COLOR_CODES.DIM .. EllesmereUI.L("Left-click: target and mark") .. "|r"
    lines[#lines + 1] = EllesmereUI.COLOR_CODES.DIM .. EllesmereUI.L("Right-click: marker, area, category") .. "|r"
    EllesmereUI.ShowWidgetTooltip(row, table.concat(lines, "\n"), { anchor = "left", justify = "LEFT" })
end

local function RowMenu(row)
    local e = row.entry
    if not e or not NotInCombat() then return end
    local items = { TH.MarkerMenu(e.marker, function(m) TH.SetMarker(e.name, m) end) }
    if e.quests[1] then
        items[#items + 1] = { text = EllesmereUI.L("Hide for This Quest"), onClick = function()
            for _, q in ipairs(e.quests) do TH.SetQuestHidden(q.key, true) end
        end }
    end
    if e.farm then TH.FarmMenuItems(e.name, items) end
    EllesmereUI.ShowContextMenu(row, items, { below = true })
end

local function CreateRow(i)
    local row = CreateFrame("Button", "EUI_TargetHelperButton" .. i, bar, "SecureActionButtonTemplate")
    row:SetHeight(ROW_H)
    row:RegisterForClicks("AnyUp", "AnyDown")
    row:SetAttribute("type1", "macro")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0, 0, 0, i % 2 == 0 and 0.2 or 0.1)

    row.stripe = row:CreateTexture(nil, "ARTWORK")
    row.stripe:SetPoint("TOPLEFT")
    row.stripe:SetPoint("BOTTOMLEFT")
    row.stripe:SetWidth(2)

    row.marker = row:CreateTexture(nil, "ARTWORK")
    row.marker:SetSize(14, 14)
    row.marker:SetPoint("LEFT", 6, 0)

    row.portrait = CreateFrame("Frame", nil, row)
    row.portrait:SetSize(16, 16)
    row.portrait:SetPoint("LEFT", row.marker, "RIGHT", 4, 0)
    local pbg = row.portrait:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0, 0, 0, 0.5)
    row.model = CreateFrame("PlayerModel", nil, row.portrait)
    row.model:SetAllPoints()
    row.model:EnableMouse(false)
    row.unknown = row.portrait:CreateTexture(nil, "ARTWORK")
    row.unknown:SetAllPoints()
    row.unknown:SetTexture(QUESTION)
    row.unknown:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.unknown:SetAlpha(0.4)

    row.dot = row:CreateTexture(nil, "OVERLAY")
    row.dot:SetSize(5, 5)
    row.dot:SetPoint("RIGHT", -5, 0)
    row.dot:SetColorTexture(NEAR_C[1], NEAR_C[2], NEAR_C[3], 1)

    row.progress = Text(row, 10, "RIGHT")
    row.progress:SetPoint("RIGHT", -14, 0)
    row.progress:SetTextColor(1, 1, 1, 0.53)

    row.name = Text(row, 11)
    row.name:SetPoint("RIGHT", row.progress, "LEFT", -4, 0)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    PP.CreateBorder(row, 1, 1, 1, 1, 1, "OVERLAY", 2)
    PP.HideBorder(row)

    row:SetScript("PreClick", function(self, button)
        if button == "LeftButton" then UpdateRowMacro(self) end
    end)
    row:SetScript("PostClick", function(self, button, down)
        local e = self.entry
        if not e then return end
        if button == "LeftButton" then
            if self.pick == "none" and not down then
                EllesmereUI.Print(EllesmereUI.Lf("No free %s nearby (all marked or tagged).", e.name))
            end
            pendingMark = e.marker
            RecordOwnMark()
        elseif button == "RightButton" and not down then
            RowMenu(self)
        end
    end)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

    rows[i] = row
    return row
end

-------------------------------------------------------------------------------
--  Category headers (insecure, fold on click out of combat)
-------------------------------------------------------------------------------
local function PaintCat(h, hovered)
    local c = h.isQuest and QUEST_C or FARM_C
    h.label:SetTextColor(c[1], c[2], c[3], hovered and 1 or 0.8)
    h.arrow:SetAlpha(hovered and ICON_HOVER_ALPHA or ICON_ALPHA)
end

local function CreateCat(i)
    local h = CreateFrame("Button", nil, bar)
    h:SetHeight(CAT_H)
    h.arrow = h:CreateTexture(nil, "ARTWORK")
    h.arrow:SetTexture(ARROW)
    h.arrow:SetSize(10, 10)
    h.arrow:SetPoint("LEFT", 4, 0)
    h.count = Text(h, 10, "RIGHT")
    h.count:SetPoint("RIGHT", -4, 0)
    h.count:SetTextColor(1, 1, 1, 0.53)
    h.label = Text(h, 10)
    h.label:SetPoint("LEFT", 18, 0)
    h.label:SetPoint("RIGHT", h.count, "LEFT", -4, 0)
    h:SetScript("OnClick", function(self)
        if not NotInCombat() then return end
        local folded = Tbl("folded")
        folded[self.cat] = (not folded[self.cat]) or nil
        Refresh()
    end)
    h:SetScript("OnEnter", function(self) PaintCat(self, true) end)
    h:SetScript("OnLeave", function(self) PaintCat(self, false) end)
    cats[i] = h
    return h
end

-------------------------------------------------------------------------------
--  Refresh
-------------------------------------------------------------------------------
-- In combat: refresh the rows already shown and dim targets no longer
-- needed; the rebuild runs after combat.
local function SoftRefresh(list)
    local byName = {}
    for _, e in ipairs(list) do byName[e.name] = e end
    for _, row in ipairs(rows) do
        local old = row:IsShown() and row.entry
        if old then
            local e = byName[old.name]
            if e then
                e.marker = old.marker -- the macro still sets the old one
                UpdateRowLook(row, e)
            else
                old.done = true
                row:SetAlpha(0.35)
            end
        end
    end
end

Refresh = function()
    if not bar or not Enabled() then return end
    local list = TH.BuildTargets()
    if InCombatLockdown() then
        pendingRefresh = true
        SoftRefresh(list)
        return
    end
    pendingRefresh = false
    anchor:SetWidth(Get("width"))

    local perCat = {}
    for _, e in ipairs(list) do perCat[e.cat] = (perCat[e.cat] or 0) + 1 end

    local barFolded, folded = Get("collapsed"), Read("folded")
    local showCats = Get("showCategories")
    local y = HEADER_H + PAD
    local nRow, nCat, lastCat = 0, 0, nil
    local function Place(f, h)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD, -y)
        f:SetPoint("RIGHT", bar, "RIGHT", -PAD, 0)
        y = y + h + GAP
    end

    if not barFolded then
        for _, e in ipairs(list) do
            local catFolded = showCats and folded[e.cat]
            if showCats and e.cat ~= lastCat then
                lastCat = e.cat
                nCat = nCat + 1
                local h = cats[nCat] or CreateCat(nCat)
                h.cat, h.isQuest = e.cat, e.quests[1] ~= nil
                h.label:SetText(e.cat)
                h.arrow:SetRotation(catFolded and math.pi / 2 or 0)
                h.count:SetText(catFolded and perCat[e.cat] or "")
                PaintCat(h, false)
                h:Show()
                Place(h, CAT_H)
            end
            if not catFolded and nRow < MAX_ROWS then
                nRow = nRow + 1
                local row = rows[nRow] or CreateRow(nRow)
                row.macro = nil
                UpdateRowLook(row, e)
                SetMacro(row, TH.MacroFor(e.name, e.marker))
                row:Show()
                Place(row, ROW_H)
            end
        end
    end
    for i = nRow + 1, #rows do
        rows[i].entry = nil
        rows[i]:Hide()
    end
    for i = nCat + 1, #cats do cats[i]:Hide() end

    emptyText:SetShown(#list == 0 and not barFolded)
    countText:SetText(#list > 0 and #list or "")
    foldBtn.icon:SetRotation(barFolded and math.pi / 2 or 0)
    if barFolded then
        y = HEADER_H
    elseif #list == 0 then
        y = y + 30
    else
        y = y - GAP + PAD
    end
    bar:SetHeight(y)
end

local function ToggleBar()
    if not bar or not NotInCombat() then return end
    Cfg().collapsed = not Get("collapsed") or nil
    Refresh()
end

-------------------------------------------------------------------------------
--  Nameplates ("nearby" dot) and NPC ids (portraits)
-------------------------------------------------------------------------------
local function LearnNpc(unit)
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local name = TH.UnitNameOf(unit)
    if not name or Read("npcIds")[name] then return end
    local guid = Plain(UnitGUID(unit))
    if not guid then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    id = tonumber(id)
    if id and (kind == "Creature" or kind == "Vehicle") then
        Tbl("npcIds")[name] = id
        for _, row in ipairs(rows) do
            if row:IsShown() and row.entry and row.entry.name == name then UpdatePortrait(row, row.entry) end
        end
    end
end

local function PlateAdded(unit)
    local name = TH.UnitNameOf(unit)
    if not name then return end
    plates[unit] = name
    nearby[name] = (nearby[name] or 0) + 1
end

local function PlateRemoved(unit)
    local name = plates[unit]
    if not name then return end
    plates[unit] = nil
    nearby[name] = (nearby[name] or 1) - 1
    if nearby[name] <= 0 then nearby[name] = nil end
end

-------------------------------------------------------------------------------
--  Frame
-------------------------------------------------------------------------------
local function Glyph(parent, size, file, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    if file then b.icon:SetTexture(file) end
    b.icon:SetVertexColor(1, 1, 1, ICON_ALPHA)
    b:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(1, 1, 1, ICON_HOVER_ALPHA)
        if tip then EllesmereUI.ShowWidgetTooltip(self, tip) end
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(1, 1, 1, ICON_ALPHA)
        if tip then EllesmereUI.HideWidgetTooltip() end
    end)
    b:SetScript("OnClick", onClick)
    return b
end

-- A "+" drawn from two bars, so it stays crisp at any size.
local function PlusGlyph(parent, onClick, tip)
    local b = Glyph(parent, 14, nil, onClick, tip)
    b.icon:ClearAllPoints()
    b.icon:SetPoint("CENTER")
    b.icon:SetSize(9, 1)
    b.icon:SetColorTexture(1, 1, 1, 1)
    local v = b:CreateTexture(nil, "ARTWORK")
    v:SetPoint("CENTER")
    v:SetSize(1, 9)
    v:SetColorTexture(1, 1, 1, 1)
    v:SetVertexColor(1, 1, 1, ICON_ALPHA)
    b:HookScript("OnEnter", function() v:SetVertexColor(1, 1, 1, ICON_HOVER_ALPHA) end)
    b:HookScript("OnLeave", function() v:SetVertexColor(1, 1, 1, ICON_ALPHA) end)
    return b
end

local function PaintTitle()
    if title then title:SetTextColor(Accent()) end
end

local function OnEvent(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        ResetMacros()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingApply then
            pendingApply = nil
            TH.Apply()
        elseif pendingRefresh then
            Refresh()
        end
    elseif event == "RAID_TARGET_UPDATE" then
        RecordOwnMark()
    elseif event == "PLAYER_TARGET_CHANGED" then
        LearnNpc("target")
        UpdateAllStates()
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        LearnNpc("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        LearnNpc(unit)
        PlateAdded(unit)
        UpdateAllStates()
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        PlateRemoved(unit)
        UpdateAllStates()
    elseif event == "PLAYER_ENTERING_WORLD" then
        wipe(nearby)
        wipe(plates)
        UpdateAllStates()
    end
end

local BAR_EVENTS = {
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "RAID_TARGET_UPDATE", "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_ENTERING_WORLD",
}

local function Create()
    if anchor then return end
    -- Unlock mode places the header-sized anchor; the list hangs below it.
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(Get("width"), HEADER_H)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetClampedToScreen(true)
    F.Place(anchor)

    bar = CreateFrame("Frame", "EUI_TargetHelper", anchor)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(HEADER_H)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(16 / 255, 16 / 255, 16 / 255, 0.75)

    header = CreateFrame("Frame", nil, bar)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    header:EnableMouse(true)
    local hbg = header:CreateTexture(nil, "BORDER")
    hbg:SetAllPoints()
    hbg:SetColorTexture(0.106, 0.106, 0.106, 1)
    header:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ToggleBar() end
    end)

    foldBtn = Glyph(header, 12, ARROW, ToggleBar, EllesmereUI.L("Fold or unfold the list. Also: right-click the header."))
    foldBtn:SetPoint("LEFT", 6, 0)

    local cog = Glyph(header, 16, MEDIA .. "dm_settings.png", function()
        EllesmereUI:NavigateToElementSettings("EllesmereUIForeverEssentials", "Targets")
    end, EllesmereUI.L("Settings"))
    cog:SetPoint("RIGHT", -4, 0)
    local add = PlusGlyph(header, TH.AddCurrentTarget, EllesmereUI.L("Add your current target to the farm list."))
    add:SetPoint("RIGHT", cog, "LEFT", -2, 0)

    title = Text(header, 11)
    title:SetPoint("LEFT", foldBtn, "RIGHT", 5, 0)
    title:SetText(EllesmereUI.L("Target Helper"))
    PaintTitle()
    countText = Text(header, 10)
    countText:SetPoint("LEFT", title, "RIGHT", 6, 0)
    countText:SetTextColor(1, 1, 1, 0.53)

    emptyText = Text(bar, 10)
    emptyText:SetPoint("TOPLEFT", 8, -(HEADER_H + 6))
    emptyText:SetPoint("RIGHT", -8, 0)
    emptyText:SetWordWrap(true)
    emptyText:SetTextColor(1, 1, 1, 0.53)
    emptyText:SetText(EllesmereUI.L("No targets in this zone. Target a mob and click +."))

    EllesmereUI.RegAccent({ type = "callback", fn = function()
        PaintTitle()
        UpdateAllStates()
    end })
end

-- Builds the bar on first enable; nothing exists while the helper is off.
function TH.Apply()
    if InCombatLockdown() then
        -- The secure rows can't be shown or hidden now.
        pendingApply = true
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if not Enabled() then
        if events then events:UnregisterAllEvents() end
        TH.SetActive(false)
        if anchor then anchor:Hide() end
        -- Key bindings click the buttons even while hidden.
        for _, row in ipairs(rows) do
            row.entry = nil
            SetMacro(row, "")
        end
        wipe(nearby)
        wipe(plates)
        return
    end
    Create()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    for _, e in ipairs(BAR_EVENTS) do events:RegisterEvent(e) end
    anchor:Show()
    TH.SetActive(true)
    Refresh()
end

TH.OnChange(function() Refresh() end)

-- Key bindings (Bindings.xml).
_G.BINDING_HEADER_EUI_TARGETHELPER = EllesmereUI.L("EllesmereUI Target Helper")
for i = 1, 6 do
    _G["BINDING_NAME_CLICK EUI_TargetHelperButton" .. i .. ":LeftButton"] = EllesmereUI.Lf("Target and Mark Row %d", i)
end
_G.BINDING_NAME_EUI_TARGETHELPER_ADD = EllesmereUI.L("Add Current Target to Farm List")
_G.BINDING_NAME_EUI_TARGETHELPER_TOGGLE = EllesmereUI.L("Fold or Unfold the Target List")

-- Options-page and binding entry points.
EllesmereUI._TargetHelper = {
    Get = Get,
    Cfg = Cfg,
    Read = Read,
    Tbl = Tbl,
    Apply = TH.Apply,
    Refresh = function() Refresh() end,
    ApplyPosition = function()
        if not InCombatLockdown() then F.Place(anchor) end
    end,
    ToggleBar = function()
        if Enabled() then ToggleBar() end
    end,
    AddCurrentTarget = function()
        if Enabled() then TH.AddCurrentTarget() end
    end,
    TH = TH,
}

F.Start(TH.Apply, {
    key = "EUI_TargetHelper", label = "Target Helper", order = 733, minWidth = 150,
    frame = function(build)
        if build then Create() end
        return anchor
    end,
    -- Unlock mode moves the header; the list grows down from it.
    height = function() return HEADER_H end,
    applyStyle = function() Refresh() end,
})
