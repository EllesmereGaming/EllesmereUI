if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not EllesmereUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_Details.lua  (WoW Forever only)
--
-- Our own quest details window, opened from the custom tracker. Built only
-- from quest log reads keyed by quest ID, so no Blizzard quest or map code
-- runs from it: opening Blizzard's map or quest popup from addon code taints
-- the map's pins (SetPassThroughButtons blocked in combat). Works in combat.
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT

local W, H     = 360, 480
local PAD      = 14
local HEADER_H = 52   -- title, meta line, divider
local FOOTER_H = 50   -- divider, button row
local BTN_H    = 24
local TILE     = 34
local GAP      = 6
local WHEEL    = 40
local CHECK    = "Interface\\RaidFrame\\ReadyCheck-Ready"
local CLOSE    = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png"

-- EllesmereUI panel look (see EllesmereUI_Popups.lua).
local BG       = { 0.077, 0.068, 0.058, 0.97 }
local TILE_BG  = { 0.11, 0.10, 0.09, 1 }

-------------------------------------------------------------------------------
-- Rewards: XP, money, then one entry per currency, item and choice.
-- Entry: name, texture, count, quality, itemID, type ("reward" / "choice"),
-- index (for the quest log tooltip calls), currency. Nil when none.
-------------------------------------------------------------------------------
function EQT.QuestRewards(questID)
    if not C_QuestLog.ShouldShowQuestRewards(questID) then return end
    local r = { xp = GetQuestLogRewardXP(questID), money = GetQuestLogRewardMoney(questID),
                rewards = {}, choices = {} }
    for i, cur in ipairs(C_QuestLog.GetQuestRewardCurrencies(questID)) do
        r.rewards[#r.rewards + 1] = { name = cur.name, texture = cur.texture, count = cur.totalRewardAmount,
            quality = cur.quality, type = "reward", index = i, currency = true }
    end
    for i = 1, GetNumQuestLogRewards(questID) do
        local name, texture, count, quality, _, itemID = GetQuestLogRewardInfo(i, questID)
        r.rewards[#r.rewards + 1] = { name = name, texture = texture, count = count, quality = quality,
            itemID = itemID, type = "reward", index = i }
    end
    for i = 1, GetNumQuestLogChoices(questID) do
        local name, texture, count, quality, _, itemID = GetQuestLogChoiceInfo(i, questID)
        r.choices[#r.choices + 1] = { name = name, texture = texture, count = count, quality = quality,
            itemID = itemID, type = "choice", index = i }
    end
    if r.xp <= 0 and r.money <= 0 and #r.rewards == 0 and #r.choices == 0 then return end
    return r
end

-- Calls fn once an entry's uncached item loads.
function EQT.OnRewardLoad(e, fn)
    local item = e.itemID and Item:CreateFromItemID(e.itemID)
    if item and not item:IsItemEmpty() and not item:IsItemDataCached() then
        item:ContinueOnItemLoad(fn)
    end
end

-------------------------------------------------------------------------------
-- Window
-------------------------------------------------------------------------------
local win, scroll, child, title, meta
local texts, tiles, marks = {}, {}, {}
local usedTexts, usedTiles, usedMarks = 0, 0, 0
local questID
local moved = false   -- dragged by the player: stop following the tracker

local function Accent()
    local g = EllesmereUI.ELLESMERE_GREEN
    return g.r, g.g, g.b
end

local function Dim()
    local d = EllesmereUI.TEXT_DIM
    return d.r, d.g, d.b, d.a
end

local function StyleText(fs, size)
    local flag = EllesmereUI.GetFontOutlineFlag("questTracker")
    if not pcall(fs.SetFont, fs, EQT.GetFont(), size, flag) then
        fs:SetFont("Fonts/FRIZQT__.TTF", size, flag)
    end
end

local function ContentWidth() return W - PAD * 2 end

-- Wrapped text at (x, y); returns its height.
local function AddText(text, x, y, size, r, g, b, a)
    usedTexts = usedTexts + 1
    local fs = texts[usedTexts]
    if not fs then
        fs = child:CreateFontString(nil, "OVERLAY")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        texts[usedTexts] = fs
    end
    StyleText(fs, size)
    fs:SetSpacing(2)
    fs:SetWidth(ContentWidth() - x)
    fs:SetTextColor(r, g, b, a or 1)
    fs:SetText(text)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
    fs:Show()
    return math.ceil(fs:GetStringHeight())
end

-- Section header: small accent capitals over a hairline.
local function AddSection(text, y)
    local r, g, b = Accent()
    local h = AddText(text:upper(), 0, y, 11, r, g, b)
    return h + 6
end

-- Objective marker: a check when finished, else a small accent square.
local function AddMark(done, y)
    usedMarks = usedMarks + 1
    local m = marks[usedMarks]
    if not m then
        m = child:CreateTexture(nil, "ARTWORK")
        marks[usedMarks] = m
    end
    m:ClearAllPoints()
    if done then
        m:SetTexture(CHECK)
        m:SetVertexColor(1, 1, 1, 1)
        m:SetSize(12, 12)
        m:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    else
        local r, g, b = Accent()
        m:SetColorTexture(r, g, b, 0.9)
        m:SetSize(4, 4)
        m:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -(y + 5))
    end
    m:Show()
end

local function TileEnter(self)
    local r, g, b = Accent()
    self.frame:SetColor(r, g, b, 0.6)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.entry.currency then
        GameTooltip:SetQuestLogCurrency(self.entry.type, self.entry.index, questID)
    else
        GameTooltip:SetQuestLogItem(self.entry.type, self.entry.index, questID)
    end
    GameTooltip:Show()
end

local function TileRest(t)
    local c = EllesmereUI.BORDER_COLOR
    t.frame:SetColor(c.r, c.g, c.b, 0.15)
end

local function TileLeave(self)
    TileRest(self)
    GameTooltip:Hide()
end

local function AddTile(e, x, y, w)
    usedTiles = usedTiles + 1
    local t = tiles[usedTiles]
    if not t then
        t = CreateFrame("Button", nil, child)
        local bg = t:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(TILE_BG[1], TILE_BG[2], TILE_BG[3], TILE_BG[4])
        t.frame = EllesmereUI.MakeBorder(t, 1, 1, 1, 0.15)
        local holder = CreateFrame("Frame", nil, t)
        holder:SetSize(TILE - 8, TILE - 8)
        holder:SetPoint("LEFT", 4, 0)
        t.icon = holder:CreateTexture(nil, "ARTWORK")
        t.icon:SetAllPoints()
        t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        t.quality = EllesmereUI.MakeBorder(holder, 0, 0, 0, 1)
        t.count = holder:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        t.count:SetPoint("BOTTOMRIGHT", 1, 0)
        t.name = t:CreateFontString(nil, "OVERLAY")
        t.name:SetPoint("LEFT", holder, "RIGHT", 6, 0)
        t.name:SetPoint("RIGHT", -4, 0)
        t.name:SetJustifyH("LEFT")
        t.name:SetMaxLines(2)
        t:SetScript("OnEnter", TileEnter)
        t:SetScript("OnLeave", TileLeave)
        tiles[usedTiles] = t
    end
    t.entry = e
    t:SetSize(w, TILE)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
    local c = e.quality and ColorManager.GetColorDataForItemQuality(e.quality)
    if c then t.quality:SetColor(c.r, c.g, c.b, 1) else t.quality:SetColor(0, 0, 0, 1) end
    t.icon:SetTexture(e.texture)
    t.count:SetText((e.count and e.count > 1) and e.count or "")
    StyleText(t.name, 11)
    t.name:SetText(e.name or RETRIEVING_DATA)
    if c then t.name:SetTextColor(c.r, c.g, c.b) else t.name:SetTextColor(1, 1, 1) end
    TileRest(t)
    t:Show()
end

-- Two columns of tiles; returns the height used.
local function AddTiles(list, y)
    local w = (ContentWidth() - GAP) / 2
    for i, e in ipairs(list) do
        local col = (i - 1) % 2
        AddTile(e, col * (w + GAP), y + math.floor((i - 1) / 2) * (TILE + GAP), w)
    end
    local rows = math.ceil(#list / 2)
    return rows * TILE + math.max(0, rows - 1) * GAP
end

-- Level (difficulty colored) and quest type, e.g. "Level 12  Elite".
local function MetaText()
    local level = C_QuestLog.GetQuestDifficultyLevel(questID)
    local parts = {}
    if level and level > 0 then
        local c = GetQuestDifficultyColor(level)
        parts[1] = CreateColor(c.r, c.g, c.b):WrapTextInColorCode(LEVEL .. " " .. level)
    end
    local tag = C_QuestLog.GetQuestTagInfo(questID)
    if tag and tag.tagName then parts[#parts + 1] = tag.tagName end
    if C_QuestLog.IsComplete(questID) then parts[#parts + 1] = COMPLETE end
    return table.concat(parts, "   ")
end

local Refresh

local function SetButtonEnabled(b, on)
    b:SetEnabled(on)
    b:SetAlpha(on and 1 or 0.35)
end

-- Sharing a quest is refused in combat (a blocked action from addon code), so Share is
-- off there. inCombat: the combat events pass their own edge; every other caller asks
-- the game.
local function UpdateButtons(inCombat)
    if inCombat == nil then inCombat = InCombatLockdown() end
    local focused = C_SuperTrack.GetSuperTrackedQuestID() == questID
    win.focus.label:SetText(focused and STOP_SUPER_TRACK_QUEST or SUPER_TRACK_QUEST)
    SetButtonEnabled(win.share, not inCombat and IsInGroup() and C_QuestLog.IsPushableQuest(questID))
    SetButtonEnabled(win.abandon, C_QuestLog.CanAbandonQuest(questID))
end

function Refresh()
    if not (win and win:IsShown() and questID) then return end
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
    if not logIndex then win:Hide(); return end
    usedTexts, usedTiles, usedMarks = 0, 0, 0
    local dr, dg, db, da = Dim()
    title:SetText(C_QuestLog.GetTitleForQuestID(questID) or "")
    meta:SetText(MetaText())
    win.bar:SetColorTexture(Accent())

    local description, objectivesText = GetQuestLogQuestText(logIndex)
    local y = 0
    local objectives = C_QuestLog.GetQuestObjectives(questID) or {}
    if #objectives > 0 or (objectivesText and objectivesText ~= "") then
        y = y + AddSection(QUEST_OBJECTIVES, y)
        for _, o in ipairs(objectives) do
            if o.text and o.text ~= "" then
                AddMark(o.finished, y)
                if o.finished then
                    y = y + AddText(o.text, 18, y, 12, dr, dg, db, da) + 4
                else
                    y = y + AddText(o.text, 18, y, 12, 1, 1, 1) + 4
                end
            end
        end
        if objectivesText and objectivesText ~= "" then
            y = y + 4 + AddText(objectivesText, 0, y + 4, 12, dr, dg, db, da)
        end
        y = y + 16
    end
    if description and description ~= "" then
        y = y + AddSection(QUEST_DESCRIPTION, y)
        y = y + AddText(description, 0, y, 12, 0.9, 0.9, 0.9) + 16
    end

    local r = EQT.QuestRewards(questID)
    if r then
        y = y + AddSection(QUEST_REWARDS, y)
        if r.xp > 0 then
            y = y + AddText(BONUS_OBJECTIVE_EXPERIENCE_FORMAT:format(r.xp), 0, y, 12, 1, 1, 1) + 4
        end
        if r.money > 0 then y = y + AddText(GetMoneyString(r.money), 0, y, 12, 1, 1, 1) + 4 end
        if #r.rewards > 0 then y = y + 4 + AddTiles(r.rewards, y + 4) + 4 end
        if #r.choices > 0 then
            y = y + 8
            y = y + AddText(REWARD_CHOICES, 0, y, 12, dr, dg, db, da) + 6
            y = y + AddTiles(r.choices, y)
        end
        -- Uncached items: redraw once each loads, if still on this quest.
        local shown = questID
        for _, list in ipairs({ r.rewards, r.choices }) do
            for _, e in ipairs(list) do
                if not e.name then
                    EQT.OnRewardLoad(e, function() if questID == shown then Refresh() end end)
                end
            end
        end
    end

    for i = usedTexts + 1, #texts do texts[i]:Hide() end
    for i = usedTiles + 1, #tiles do tiles[i]:Hide() end
    for i = usedMarks + 1, #marks do marks[i]:Hide() end
    child:SetSize(ContentWidth(), math.max(1, y))
    local maxScroll = math.max(0, y - scroll:GetHeight())
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), maxScroll))
    UpdateButtons()
end

-- Beside the tracker, on the side facing the screen centre.
local function Place()
    if moved then return end
    local tracker = _G.EUI_CustomQuestTracker
    win:ClearAllPoints()
    local cx = tracker and tracker:GetCenter()
    if not cx then win:SetPoint("CENTER", UIParent, "CENTER", 0, 50); return end
    if cx * tracker:GetEffectiveScale() > UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2 then
        win:SetPoint("TOPRIGHT", tracker, "TOPLEFT", -8, 0)
    else
        win:SetPoint("TOPLEFT", tracker, "TOPRIGHT", 8, 0)
    end
end

local function Button(text, onClick)
    local b = CreateFrame("Button", nil, win)
    b:SetSize((W - PAD * 2 - GAP * 3) / 4, BTN_H)
    local _, _, lbl = EllesmereUI.MakeStyledButton(b, text, 11, EllesmereUI.WB_COLOURS, onClick)
    lbl:SetWidth(b:GetWidth() - 6)
    lbl:SetWordWrap(false)
    b.label = lbl
    return b
end

local function Divider(y, fromBottom)
    local c = EllesmereUI.BORDER_COLOR
    local t = win:CreateTexture(nil, "BORDER")
    t:SetColorTexture(c.r, c.g, c.b, 0.15)
    t:SetHeight(1)
    local point = fromBottom and "BOTTOM" or "TOP"
    t:SetPoint(point .. "LEFT", PAD, y)
    t:SetPoint(point .. "RIGHT", -PAD, y)
end

local function Build()
    win = CreateFrame("Frame", "EUI_QuestDetails", UIParent)
    win:SetSize(W, H)
    win:SetFrameStrata("MEDIUM")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); moved = true end)
    win:Hide()

    local bg = win:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(BG[1], BG[2], BG[3], BG[4])
    local c = EllesmereUI.BORDER_COLOR
    EllesmereUI.MakeBorder(win, c.r, c.g, c.b, 0.15)

    -- Header: accent bar, title, meta line.
    win.bar = win:CreateTexture(nil, "ARTWORK")
    win.bar:SetSize(2, 32)
    win.bar:SetPoint("TOPLEFT", PAD, -PAD + 2)
    title = win:CreateFontString(nil, "OVERLAY")
    StyleText(title, 15)
    title:SetTextColor(1, 1, 1)
    title:SetPoint("TOPLEFT", win.bar, "TOPRIGHT", 8, 0)
    title:SetPoint("RIGHT", -34, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    meta = win:CreateFontString(nil, "OVERLAY")
    StyleText(meta, 11)
    meta:SetTextColor(Dim())
    meta:SetPoint("BOTTOMLEFT", win.bar, "BOTTOMRIGHT", 8, 0)
    meta:SetJustifyH("LEFT")
    Divider(-HEADER_H)

    local close = CreateFrame("Button", nil, win)
    close:SetSize(12, 12)
    close:SetPoint("TOPRIGHT", -PAD, -PAD)
    close.icon = close:CreateTexture(nil, "OVERLAY")
    close.icon:SetAllPoints()
    close.icon:SetTexture(CLOSE)
    close.icon:SetAlpha(0.7)
    close:SetScript("OnEnter", function() close.icon:SetAlpha(1) end)
    close:SetScript("OnLeave", function() close.icon:SetAlpha(0.7) end)
    close:SetScript("OnClick", function() win:Hide() end)

    scroll = CreateFrame("ScrollFrame", nil, win)
    scroll:SetPoint("TOPLEFT", PAD, -HEADER_H - 12)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, FOOTER_H + 8)
    scroll:SetClipsChildren(true)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, child:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScroll() - delta * WHEEL, max)))
    end)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(ContentWidth(), 1)
    scroll:SetScrollChild(child)

    -- Footer: one row of buttons.
    Divider(FOOTER_H, true)
    local a = EQT.CustomQuestActions
    win.focus = Button(SUPER_TRACK_QUEST, function() a.Focus(questID) end)
    win.focus:SetPoint("BOTTOMLEFT", PAD, PAD)
    win.untrack = Button(UNTRACK_QUEST_ABBREV, function() a.Untrack(questID) end)
    win.untrack:SetPoint("LEFT", win.focus, "RIGHT", GAP, 0)
    win.share = Button(SHARE_QUEST_ABBREV, function()
        if InCombatLockdown() then return end
        QuestLogPushQuest(C_QuestLog.GetLogIndexForQuestID(questID))
    end)
    win.share:SetPoint("LEFT", win.untrack, "RIGHT", GAP, 0)
    win.abandon = Button(ABANDON_QUEST_ABBREV, function() a.Abandon(questID) end)
    win.abandon:SetPoint("LEFT", win.share, "RIGHT", GAP, 0)

    win:SetScript("OnEvent", function(_, event, id)
        if event == "QUEST_REMOVED" then
            if id == questID then win:Hide() end
        elseif event == "PLAYER_REGEN_DISABLED" then
            UpdateButtons(true)
        elseif event == "PLAYER_REGEN_ENABLED" then
            UpdateButtons(false)
        elseif event == "SUPER_TRACKING_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
            UpdateButtons()
        else
            Refresh()
        end
    end)
    win:SetScript("OnShow", function(self)
        self:RegisterEvent("QUEST_LOG_UPDATE")
        self:RegisterEvent("QUEST_REMOVED")
        self:RegisterEvent("SUPER_TRACKING_CHANGED")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        -- Share follows combat
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
    end)
    win:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        questID = nil
    end)
    EllesmereUI.RegisterEscapeClose(win)
end

-- Toggles the window for a quest; a second click on the same quest closes it.
function EQT.ShowQuestDetails(id)
    if not win then Build() end
    if win:IsShown() and questID == id then win:Hide(); return end
    questID = id
    scroll:SetVerticalScroll(0)
    Place()
    win:Show()
    Refresh()
end
