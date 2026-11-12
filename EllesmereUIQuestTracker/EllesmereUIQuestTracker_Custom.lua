if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not EllesmereUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_Custom.lua  (WoW Forever only)
--
-- Our own quest tracker frame, used instead of ObjectiveTrackerFrame when the
-- Custom Quest Tracker option is on. Blizzard's tracker is muted (alpha 0,
-- click-through, see EQT.MuteBlizzardTracker) and never skinned or fed watch
-- list edits. This file only reads the quest log, the watch list and the
-- tracked recipes: untracking, zone auto-track, filters and sorting all live
-- in our own list (the Forever file's quest tools, read-only).
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT
local IsSecret = EllesmereUI.IsSecret
local function Cfg(k) return EQT.Cfg(k) end

-- The tracker's width, and the height it grows to before it scrolls: the
-- values a new profile starts on, and the range a user can set.
local DEF_WIDTH, DEF_HEIGHT = 260, 450
local WIDTH_MIN, WIDTH_MAX = 150, 600
local HEIGHT_MIN, HEIGHT_MAX = 100, 1200
-- Its Unlock Mode element: the key Blizzard's tracker has when this one is off.
local UNLOCK_KEY = "EQT_Tracker"

-- Defaults, merged into the module's table before its DB is made at login.
-- Whether this tracker is used at all has no default here: the loader's
-- ns.CustomTrackerWanted decides it from the profile's style and pick.
-- Its spot is customPos (none until one is taken or saved).
do
    local qt = ns.QT_DEFAULTS.profile.questTracker
    qt.customGroupByZone       = true
    qt.customWidth             = DEF_WIDTH
    qt.customMaxHeight         = DEF_HEIGHT
    qt.customGrowUp            = false     -- grows up from its bottom edge
    qt.customCollapseCompleted = false
    qt.customZoneFontSize      = 13
    qt.customQuestSpacing      = 4
    qt.customObjSpacing        = 1
    qt.customFocusClick        = true      -- focus buttons + menu entry
    qt.customWrapTitles        = true      -- off: one line, cut with "..."
    qt.customWrapObjectives    = true
    qt.customScrollbar         = "always"  -- always / hover / hidden
    qt.customBgHover           = false     -- background + top line only while hovered
    qt.customBgFade            = true      -- fade it in and out
    qt.customItemButtons       = false     -- quest item buttons beside titles
    qt.customFlashUpdates      = false     -- flash objectives that just changed
    qt.customClickAction       = "collapse"  -- collapse / map / details
end

local PAD      = 8
local HEADER_H = 24
local BAR_W    = 3    -- scrollbar track width
local BAR_GAP  = 6    -- space kept for the track right of the text
local OBJ_IND  = 10   -- objective indent
local FOCUS_GAP = 6   -- focus button to title
local WHEEL    = 40

-- Inert until InitCustom registers events (zero cost while off).
local evt = CreateFrame("Frame")

local frame, header, scroll, child, track, thumb
local lines, used = {}, 0
local order, zoneOf, seen = {}, {}, {}
local pending = false
local stale = false   -- skipped a render while hidden
local fontGen = 1
local inEncounter = false
local prevObj = {}    -- questID -> objective texts last shown (update flashes)
local rowHooks, hookW = {}, 0  -- public row hooks; hookW: width they reserve
local TITLE_MIN_W = 40         -- the narrowest a quest title gets, whatever the hooks reserve

-------------------------------------------------------------------------------
-- Per-character state: untracked = removed from our list by the player,
-- collapsed = questID / "z:<zone>" / "all", doneOpen = completed quests
-- expanded while Collapse Completed Quests is on, pinned = kept listed and
-- sorted first. Kept per character in the
-- account DB, as the Forever file keeps its watch sets.
-------------------------------------------------------------------------------
local charDB
local function CharDB()
    if charDB then return charDB end
    local all = EllesmereUIDB.questTrackerChars
    if type(all) ~= "table" then all = {}; EllesmereUIDB.questTrackerChars = all end
    local guid = UnitGUID("player")
    local sv = all[guid]
    if type(sv) ~= "table" then sv = {}; all[guid] = sv end
    if type(sv.ctUntracked) ~= "table" then sv.ctUntracked = {} end
    if type(sv.ctCollapsed) ~= "table" then sv.ctCollapsed = {} end
    if type(sv.ctDoneOpen) ~= "table" then sv.ctDoneOpen = {} end
    if type(sv.ctPinned) ~= "table" then sv.ctPinned = {} end
    charDB = sv
    return sv
end

-------------------------------------------------------------------------------
-- Quest list: watched quests in watch order (Blizzard's order), then quests
-- under the current zone header when zone auto-track is on, then pinned ones.
-------------------------------------------------------------------------------
local listPos, listRank, zoneRank = {}, {}, {}

local function ByRank(a, b)
    local ra, rb = listRank[a], listRank[b]
    if ra ~= rb then return ra < rb end
    return listPos[a] < listPos[b]
end

-- Stable sort of order by listRank, lowest first.
local function SortByRank()
    wipe(listPos)
    for i, questID in ipairs(order) do listPos[questID] = i end
    table.sort(order, ByRank)
end

local function BuildList()
    wipe(order); wipe(seen); wipe(listRank)
    local db = CharDB()
    local untracked, pinned = db.ctUntracked, db.ctPinned
    local watched = seen
    for i = 1, C_QuestLog.GetNumQuestWatches() do
        local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(i)
        if questID then
            watched[questID] = true
            if not untracked[questID] then order[#order + 1] = questID end
        end
    end
    -- One log snapshot per pass; filters and sort keys read it too.
    local log
    log, zoneOf = EQT.QuestLogSnapshot()
    local auto = EQT.AutoTrackOn()
    for _, info in ipairs(log) do
        local questID = info.questID
        if questID and not info.isHeader then
            if pinned[questID] or (auto and EQT.QuestInArea(info, zoneOf[questID])) then
                if not watched[questID] and not untracked[questID]
                   and not info.isHidden and not info.isTask and not info.isBounty then
                    order[#order + 1] = questID
                end
            elseif untracked[questID] and not watched[questID] then
                -- An auto-tracked quest untracked here: free again once out of the zone.
                untracked[questID] = nil
            end
        end
    end
    for i = #order, 1, -1 do
        if EQT.IsQuestFiltered(order[i]) then table.remove(order, i) end
    end
    EQT.SortQuestList(order)
    if next(pinned) then
        for _, questID in ipairs(order) do listRank[questID] = pinned[questID] and 0 or 1 end
        SortByRank()
    end
    if not Cfg("customGroupByZone") then return end
    -- Zones in order of their first quest.
    wipe(zoneRank)
    local n = 0
    for _, questID in ipairs(order) do
        local z = zoneOf[questID] or ""
        if not zoneRank[z] then n = n + 1; zoneRank[z] = n end
        listRank[questID] = zoneRank[z]
    end
    SortByRank()
end

-------------------------------------------------------------------------------
-- Lines: one pooled Button per row (zone header, quest title, objective).
-------------------------------------------------------------------------------
local OnLineClick, OnLineEnter, OnLineLeave, ToggleFocus, SyncItems, HideOverlay, Queue  -- defined below

-- Outline and shadow follow the Fonts page's Module Outline.
local function StyleText(fs, size)
    EllesmereUI.PrimeFontShadow(fs, EllesmereUI.GetFontUseShadow("questTracker") and true or false)
    local flag = EllesmereUI.GetFontOutlineFlag("questTracker")
    if not pcall(fs.SetFont, fs, EQT.GetFont(), size, flag) then
        fs:SetFont("Fonts/FRIZQT__.TTF", size, flag)
    end
end

local SIZE_KEY = { zone = "customZoneFontSize", quest = "titleFontSize", recipe = "titleFontSize", obj = "objectiveFontSize" }
local SIZE_DEF = { zone = 13, quest = 12, recipe = 12, obj = 10 }

-- key: objective identity, so a flash survives re-renders of the same row.
local function AcquireLine(kind, id, text, x, y, width, key)
    used = used + 1
    local l = lines[used]
    if not l then
        l = CreateFrame("Button", nil, child)
        l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        l.text = l:CreateFontString(nil, "OVERLAY")
        l.text:SetPoint("TOPLEFT")
        l.text:SetJustifyH("LEFT")
        l:SetScript("OnClick", OnLineClick)
        l:SetScript("OnEnter", OnLineEnter)
        l:SetScript("OnLeave", OnLineLeave)
        lines[used] = l
    end
    if l.kind ~= kind or l.gen ~= fontGen then
        l.kind, l.gen = kind, fontGen
        StyleText(l.text, Cfg(SIZE_KEY[kind]) or SIZE_DEF[kind])
        l:EnableMouse(kind ~= "obj")
        l.lastText = nil
        l.dashW = nil  -- a timer bar's indent, measured in this font
    end
    l.id = id
    if l.flash and l.key ~= key then l.flash:Stop() end
    l.key = key
    if l.focus and kind ~= "quest" then l.focus:Hide() end
    if l.slots and kind ~= "quest" then
        for _, s in ipairs(l.slots) do s:Hide() end
    end
    if l.bar then l.bar:Hide() end
    -- Only a changed row is measured or moved.
    local wrap = Cfg(kind == "obj" and "customWrapObjectives" or "customWrapTitles") ~= false
    if l.lastText ~= text or l.lastWidth ~= width or l.lastWrap ~= wrap then
        l.lastText, l.lastWidth, l.lastWrap = text, width, wrap
        l.text:SetWordWrap(wrap)
        l.text:SetWidth(width)
        l.text:SetText(text)
        l.lastH = math.ceil(l.text:GetStringHeight())
        -- Font not ready: measure again next pass.
        if l.lastH <= 0 then l.lastText = nil end
        l:SetSize(width, l.lastH)
    end
    if l.lastX ~= x or l.lastY ~= y then
        l.lastX, l.lastY = x, y
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
    end
    l:Show()
    return l, l.lastH
end

-- Update flash: a white band that fades in and out behind the row.
local function Flash(l)
    local f = l.flash
    if not f then
        local tex = l:CreateTexture(nil, "BACKGROUND")
        tex:SetPoint("TOPLEFT", -2, 1)
        tex:SetPoint("BOTTOMRIGHT", 2, -1)
        tex:SetColorTexture(1, 1, 1)
        tex:SetBlendMode("ADD")
        tex:SetAlpha(0)
        f = l:CreateAnimationGroup()
        local a = f:CreateAnimation("Alpha")
        a:SetTarget(tex); a:SetFromAlpha(0); a:SetToAlpha(0.3); a:SetDuration(0.15); a:SetOrder(1)
        a = f:CreateAnimation("Alpha")
        a:SetTarget(tex); a:SetFromAlpha(0.3); a:SetToAlpha(0); a:SetDuration(0.85); a:SetOrder(2)
        l.flash = f
    end
    f:Stop()
    f:Play()
end

-------------------------------------------------------------------------------
-- Colors
-------------------------------------------------------------------------------
local OBJ_RGB = OBJECTIVE_TRACKER_COLOR and OBJECTIVE_TRACKER_COLOR.Normal or { r = 0.8, g = 0.8, b = 0.8 }
local DONE_RGB = OBJECTIVE_TRACKER_COLOR and OBJECTIVE_TRACKER_COLOR.Complete or { r = 0.6, g = 0.6, b = 0.6 }

local function TitleRGB(questID, complete)
    if questID == C_SuperTrack.GetSuperTrackedQuestID() then return EQT.GetFocusRGB() end
    if complete then return EQT.GetCompletedRGB() end
    -- Title Difficulty Colors: the game's own option (EQT.TitleDifficultyOn)
    if EQT.TitleDifficultyOn() then
        local r, g, b = EQT.QuestDifficultyRGB(questID)
        if r then return r, g, b end
    end
    return EQT.GetTitleRGB()
end

-- Zone headers: the colour picked on Group Quests by Zone (the accent or a
-- custom colour); with no pick, the Header Color. The fourth return is true
-- while that colour is the accent.
local function ZoneRGB()
    local c = EQT.DB()
    local accent = c.customZoneUseAccent
    if accent == nil then
        local r, g, b = EQT.GetHeaderRGB()
        return r, g, b, not (c.headerShowClassColor or c.headerUseAccent == false)
    end
    if accent then
        local a = EllesmereUI.ELLESMERE_GREEN
        return a.r, a.g, a.b, true
    end
    return c.customZoneR or 1, c.customZoneG or 1, c.customZoneB or 1, false
end
EQT.CustomZoneRGB = ZoneRGB

local function ObjectiveRGBA(obj)
    local r, g, b = OBJ_RGB.r, OBJ_RGB.g, OBJ_RGB.b
    if obj.finished then r, g, b = DONE_RGB.r, DONE_RGB.g, DONE_RGB.b end
    if Cfg("objProgressColor") then
        local req = obj.numRequired
        if obj.finished then
            r, g, b = EQT.ProgressRGB(1)
        elseif type(req) == "number" and req > 0 then
            r, g, b = EQT.ProgressRGB(math.min((obj.numFulfilled or 0) / req, 1))
        end
    end
    local a = (obj.finished and Cfg("objDimCompleted")) and (Cfg("objDimAlpha") or 45) / 100 or 1
    return r, g, b, a
end

-- "[12+] Title (Elite)", as Blizzard's Forever tracker writes it.
local titleInfo = {}

local function QuestTitle(questID)
    local title = C_QuestLog.GetTitleForQuestID(questID) or ""
    titleInfo.questID, titleInfo.difficultyLevel = questID, C_QuestLog.GetQuestDifficultyLevel(questID)
    local prefix = QuestUtilsOverrides.GetQuestTitlePrefix(titleInfo)
    local tag = QuestUtilsOverrides.GetQuestTagText(questID)
    return (prefix or "") .. title .. (tag and (" " .. tag) or "")
end

-------------------------------------------------------------------------------
-- Scrollbar: shown only while the list is taller than the frame.
-------------------------------------------------------------------------------
local contentH, viewH = 0, 0

local function MaxScroll() return math.max(0, contentH - viewH) end

-- Scrollbar mode; the wheel scrolls in every mode. A drag in progress
-- keeps a hover-mode bar up.
local function BarMode() return Cfg("customScrollbar") or "always" end

local function Hovered() return frame:IsMouseOver() or thumb:GetScript("OnUpdate") ~= nil end
local function HoverWanted() return BarMode() == "hover" or Cfg("customBgHover") end

local function BarVisible()
    local mode = BarMode()
    if mode == "hidden" then return false end
    if mode == "hover" then return Hovered() end
    return true
end

-- Background (+ top line) shown: always, or only while hovered, faded by an
-- alpha animation on their holder (no OnUpdate). A reversal mid-fade starts
-- from the alpha reached so far.
local FADE_TIME = 0.2

local function ShowBackground(instant)
    local h = frame.bgHolder
    frame.topLine:SetShown(Cfg("showTopLine") ~= false)
    local target = (not Cfg("customBgHover") or Hovered()) and 1 or 0
    if instant or not Cfg("customBgFade") then
        h.fade:Stop()
        h.target = target
        h:SetAlpha(target)
        return
    end
    if h.target == target then return end
    h.target = target
    local cur = h:GetAlpha()
    if h.fade:IsPlaying() then
        cur = h.from + (h.to - h.from) * h.anim:GetSmoothProgress()
        h.fade:Stop()
    end
    h.from, h.to = cur, target
    h.anim:SetFromAlpha(cur)
    h.anim:SetToAlpha(target)
    h.anim:SetDuration(math.max(FADE_TIME * math.abs(target - cur), 0.01))
    h.fade:Play()
end

local function UpdateHover()
    if not HoverWanted() then return end
    if BarMode() == "hover" and MaxScroll() > 0 then track:SetShown(BarVisible()) end
    if Cfg("customBgHover") then ShowBackground() end
end

local function UpdateThumb()
    local range = MaxScroll()
    if range <= 0 then
        track:Hide()
        scroll:SetVerticalScroll(0)
        return
    end
    track:SetShown(BarVisible())
    local cur = math.min(scroll:GetVerticalScroll(), range)
    scroll:SetVerticalScroll(cur)
    local thumbH = math.max(20, viewH * viewH / contentH)
    thumb:SetHeight(thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -(viewH - thumbH) * cur / range)
end

local function ScrollTo(v)
    scroll:SetVerticalScroll(math.max(0, math.min(v, MaxScroll())))
    HideOverlay()
    UpdateThumb()
    SyncItems()
end

-------------------------------------------------------------------------------
-- Render
-------------------------------------------------------------------------------
-- Focus button: Blizzard's quest POI art, beside the title.
local function FocusOnEnter(self)
    EllesmereUI.ShowWidgetTooltip(self, self.id == C_SuperTrack.GetSuperTrackedQuestID()
        and STOP_SUPER_TRACK_QUEST or SUPER_TRACK_QUEST)
end

local function FocusButton(line)
    local b = line.focus
    if b then return b end
    b = CreateFrame("Button", nil, line)
    b.glow = b:CreateTexture(nil, "BACKGROUND")
    b.glow:SetPoint("CENTER")
    b.glow:SetAtlas("UI-QuestPoi-OuterGlow")
    -- Blizzard draws 32px art on a 20px button: the atlases carry padding.
    b.ring = b:CreateTexture(nil, "ARTWORK")
    b.ring:SetPoint("CENTER")
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetPoint("CENTER")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("CENTER")
    hl:SetAtlas("UI-QuestPoi-InnerGlow")
    b.hl = hl
    hl:SetBlendMode("ADD")
    b:SetScript("OnClick", function(self) ToggleFocus(self.id) end)
    b:SetScript("OnEnter", function(self) UpdateHover(); FocusOnEnter(self) end)
    b:SetScript("OnLeave", function() UpdateHover(); EllesmereUI.HideWidgetTooltip() end)
    line.focus = b
    return b
end

local function ShowFocusButton(line, questID, complete, size)
    local b = FocusButton(line)
    local focused = questID == C_SuperTrack.GetSuperTrackedQuestID()
    b.id = questID
    b:Show()
    if b.lastSize == size and b.lastFocused == focused and b.lastComplete == complete then return end
    b.lastSize, b.lastFocused, b.lastComplete = size, focused, complete
    b:SetSize(size, size)
    local art = size * 1.6
    b.ring:SetSize(art, art)
    b.hl:SetSize(art, art)
    b:ClearAllPoints()
    b:SetPoint("TOPRIGHT", line, "TOPLEFT", -FOCUS_GAP, (size - (Cfg("titleFontSize") or 12)) / 2)
    if complete then
        b.ring:SetAtlas("UI-QuestIcon-TurnIn-Normal")
        b.icon:Hide()
    else
        b.ring:SetAtlas(focused and "UI-QuestPoi-QuestNumber-SuperTracked" or "UI-QuestPoi-QuestNumber")
        b.icon:SetAtlas(focused and "Quest-In-Progress-Icon-Brown" or "Quest-In-Progress-Icon-yellow")
        b.icon:SetSize(size * 0.75, size * 0.75)
        b.icon:Show()
    end
    b.glow:SetSize(art * 1.25, art * 1.25)
    b.glow:SetShown(focused)
end

local function AddObjectives(questID, y, width, x)
    local gap = Cfg("customObjSpacing") or 1
    local w = width - x
    local l, h
    if C_QuestLog.IsFailed(questID) then
        l, h = AcquireLine("obj", questID, "- " .. FAILED, x, y, w)
        l.text:SetTextColor(DIM_RED_FONT_COLOR.r, DIM_RED_FONT_COLOR.g, DIM_RED_FONT_COLOR.b, 1)
        return y + h + gap
    end
    if C_QuestLog.IsComplete(questID) then
        local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
        local text = logIndex and GetQuestLogCompletionText(logIndex)
            or C_QuestLog.GetNextWaypointText(questID) or QUEST_WATCH_QUEST_READY
        l, h = AcquireLine("obj", questID, "- " .. text, x, y, w)
        local r, g, b = EQT.GetCompletedRGB()
        l.text:SetTextColor(r, g, b, 1)
        return y + h + gap
    end
    local objectives = C_QuestLog.GetQuestObjectives(questID)
    if not objectives then return y end
    -- First sight of a quest records its texts without flashing.
    local prev = Cfg("customFlashUpdates") and prevObj[questID]
    if Cfg("customFlashUpdates") and not prev then prev = {}; prevObj[questID] = prev end
    for i, obj in ipairs(objectives) do
        local text = obj.text
        if text and text ~= "" then
            if obj.type == "progressbar" then
                text = text .. " (" .. math.floor(GetQuestProgressBarPercent(questID) or 0) .. "%)"
            end
            l, h = AcquireLine("obj", questID, "- " .. text, x, y, w, questID * 100 + i)
            l.text:SetTextColor(ObjectiveRGBA(obj))
            if prev then
                if prev[i] and prev[i] ~= text then Flash(l) end
                prev[i] = text
            end
            y = y + h + gap
        end
    end
    return y
end

-------------------------------------------------------------------------------
-- Quest timers. Blizzard shows them in QuestTimerFrame, a child of its muted
-- tracker, so they went with it. Render puts a timer line under each listed
-- quest with a running timer, collapsed or complete included, and a bar under
-- the text when the quest's total time is known; while one shows, a tick
-- repaints only those lines, just after each displayed second changes.
-------------------------------------------------------------------------------
local timerEnd = {}                -- questID -> GetTime() its timer runs out at
local timerLines, timerN = {}, 0   -- the timer lines the last render placed
local tickArmed = false
local TimerTick                    -- defined below
local BAR_H = 5
-- Fill: gold, red under a third of the time left (the skin's timer colours).
local TIMER_FILL, TIMER_LOW = { 1, 0.82, 0.2 }, { 1, 0.3, 0.3 }

-- Blizzard's timer ramp: white, yellow under two thirds left, red under one.
local function TimerRGB(pct)
    if pct > 0.66 then return 1, 1, 1 end
    if pct > 0.33 then return 1, 1, (pct - 0.33) / 0.33 end
    return 1, pct / 0.33, 0
end

local function TimerText(left)
    return "- " .. TIME_REMAINING .. " " .. SecondsToClock(left)
end

-- The bar under a timer line: a track in the shared pixel border, made once
-- per line (AcquireLine hides it).
local function TimerBar(l)
    local bar = l.bar
    if bar then return bar end
    bar = CreateFrame("StatusBar", nil, l)
    bar:SetHeight(BAR_H)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
    EllesmereUI.PP.CreateBorder(bar, 0, 0, 0, 0.9, 1, "OVERLAY", 1)
    l.bar = bar
    return bar
end

-- Repaints one timer line. False when its new text no longer fits the row it
-- was laid out in: a full render places it again.
local function PaintTimer(l, now)
    local left = timerEnd[l.timerQuest] - now
    if left < 0 then left = 0 end
    local text = TimerText(left)
    if l.lastText ~= text then
        l.text:SetText(text)
        l.lastText = text
        if math.ceil(l.text:GetStringHeight()) ~= l.lastH then return false end
    end
    local total = l.timerTotal
    local pct = total and math.min(left / total, 1) or 1
    l.text:SetTextColor(TimerRGB(pct))
    local bar = total and l.bar
    if bar then
        bar:SetWidth(math.max(l.text:GetStringWidth() - l.dashW, 1))
        bar:SetValue(pct)
        local c = pct > 0.33 and TIMER_FILL or TIMER_LOW
        bar:SetStatusBarColor(c[1], c[2], c[3])
    end
    return true
end

-- The next tick lands just after the soonest displayed second changes
-- (SecondsToClock floors).
local function ArmTick(now)
    if tickArmed or timerN == 0 then return end
    local wait = 1
    for i = 1, timerN do
        local left = timerEnd[timerLines[i].timerQuest] - now
        if left > 0 then
            local frac = left - math.floor(left)
            if frac < wait then wait = frac end
        end
    end
    tickArmed = true
    C_Timer.After(wait + 0.02, TimerTick)
end

TimerTick = function()
    tickArmed = false
    if timerN == 0 or not frame then return end
    -- Hidden: stop; the show renders again and the tick comes back with it.
    if not frame:IsShown() then stale = true; return end
    local now = GetTime()
    for i = 1, timerN do
        if not PaintTimer(timerLines[i], now) then Queue(); return end
    end
    ArmTick(now)
end

local function AddTimer(questID, y, width, x)
    local ends = timerEnd[questID]
    if not ends then return y end
    local now = GetTime()
    local l, h = AcquireLine("obj", questID, TimerText(math.max(ends - now, 0)), x, y, width - x)
    y = y + h + (Cfg("customObjSpacing") or 1)
    local total = C_QuestLog.GetTimeAllowed(questID)
    l.timerQuest = questID
    l.timerTotal = (total and total > 0) and total or nil
    timerN = timerN + 1
    timerLines[timerN] = l
    if l.timerTotal then
        local bar = TimerBar(l)
        if not l.dashW then
            -- The "- " prefix's width in the line's font: the bar starts under the text.
            l.text:SetText("- ")
            l.dashW = l.text:GetStringWidth()
            l.text:SetText(l.lastText)
        end
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", l, "BOTTOMLEFT", l.dashW, -1)
        bar:Show()
        y = y + BAR_H + 2
    end
    PaintTimer(l, now)
    return y
end

-------------------------------------------------------------------------------
-- Tracked recipes. Blizzard lists them in its tracker's Professions module,
-- muted with the rest of that tracker, so they follow the quests here under a
-- Professions header: each recipe with its required reagents, written as
-- Blizzard writes them. A click on a recipe goes to its block in Blizzard's
-- tracker through the header overlay below (out of combat), so Blizzard's own
-- code opens the recipe, untracks it or opens its menu.
-------------------------------------------------------------------------------
local RECIPE_KEY = "@recipes"                 -- the header's id, never a zone name
local RECIPE_COLLAPSED = "z:" .. RECIPE_KEY   -- its key in the collapsed set
local reagentState = {}     -- a reagent line's progress, for ObjectiveRGBA
local recipeEvents = false  -- bag and currency events: while a recipe is listed
local nameAsked = {}        -- itemID -> true once its name was asked for, false if it never loads
local nameWait, nameListen = false, false  -- a reagent name is loading; ITEM_DATA_LOAD_RESULT registered
local schematics = {}       -- recipe id (negative: recraft) -> its schematic, until the tracked recipes change

-- One required reagent slot: "- 2/4 Linen Cloth". A reagent whose item name
-- has not loaded is left out, asked for once; its load renders the list again.
local function AddReagent(id, slot, y, width, x)
    local r = slot.reagents and slot.reagents[1]
    if not r then return y end
    local name
    if ProfessionsUtil.IsReagentSlotBasicRequired(slot) then
        if r.itemID then
            name = C_Item.GetItemNameByID(r.itemID)
            if not name and nameAsked[r.itemID] ~= false then
                nameWait = true
                if not nameAsked[r.itemID] then
                    nameAsked[r.itemID] = true
                    C_Item.RequestLoadItemDataByID(r.itemID)
                end
            end
        elseif r.currencyID then
            local info = C_CurrencyInfo.GetCurrencyInfo(r.currencyID)
            name = info and info.name
        end
    elseif ProfessionsUtil.IsReagentSlotModifyingRequired(slot) and slot.slotInfo then
        name = slot.slotInfo.slotText
    end
    if not name then return y end
    local text
    if slot:IsVariableQuantityReagent(r) then
        text = PROFESSIONS_TRACKER_REAGENT_RANGE_FORMAT:format(slot:GetVariableQuantityRange(r))
        reagentState.finished, reagentState.numRequired = false, 0
    else
        local need = slot:GetQuantityRequired(r)
        local have = ProfessionsUtil.AccumulateReagentsInPossession(slot.reagents)
        text = PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT:format(have, need)
        reagentState.finished, reagentState.numFulfilled, reagentState.numRequired = have >= need, have, need
    end
    local l, h = AcquireLine("obj", id, "- " .. PROFESSIONS_TRACKER_REAGENT_FORMAT:format(text, name), x, y, width - x)
    l.text:SetTextColor(ObjectiveRGBA(reagentState))
    return y + h + (Cfg("customObjSpacing") or 1)
end

-- id: the recipe, negative for a recraft, as Blizzard keys its blocks.
local function AddRecipeList(list, isRecraft, y, width, titleX, objX)
    for _, recipeID in ipairs(list) do
        local id = isRecraft and -recipeID or recipeID
        -- A recipe's schematic is game data: read once and kept until the
        -- tracked recipes change (names and counts are read on every pass).
        local schematic = schematics[id]
        if not schematic then
            schematic = ProfessionsUtil.GetRecipeSchematic(recipeID, isRecraft)
            schematics[id] = schematic
        end
        local name = schematic.name or ""
        if isRecraft then name = PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER:format(name) end
        local l, h = AcquireLine("recipe", id, name, titleX, y, math.max(TITLE_MIN_W, width - titleX))
        l.text:SetTextColor(EQT.GetTitleRGB())
        y = y + h + 2
        -- Modifying reagent slots first, as Blizzard lists them.
        local slots = schematic.reagentSlotSchematics
        for _, slot in ipairs(slots) do
            if ProfessionsUtil.IsReagentSlotModifyingRequired(slot) then
                y = AddReagent(id, slot, y, width, objX)
            end
        end
        for _, slot in ipairs(slots) do
            if ProfessionsUtil.IsReagentSlotRequired(slot) and not ProfessionsUtil.IsReagentSlotModifyingRequired(slot) then
                y = AddReagent(id, slot, y, width, objX)
            end
        end
        y = y + (Cfg("customQuestSpacing") or 4)
    end
    return y
end

-- The Professions section, after the quests. Its bag and currency events
-- (reagent counts) are registered only while a recipe is tracked.
local function AddRecipes(y, width, titleX, objX, collapsed, zr, zg, zb)
    local list, recrafts = C_TradeSkillUI.GetRecipesTracked(false), C_TradeSkillUI.GetRecipesTracked(true)
    local any = (list[1] or recrafts[1]) ~= nil
    if any ~= recipeEvents then
        recipeEvents = any
        if any then
            evt:RegisterEvent("BAG_UPDATE_DELAYED")
            evt:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
        else
            evt:UnregisterEvent("BAG_UPDATE_DELAYED")
            evt:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
        end
    end
    nameWait = false
    if any then
        if y > 0 then y = y + 6 end
        local shut = collapsed[RECIPE_COLLAPSED]
        local l, h = AcquireLine("zone", RECIPE_KEY, (shut and "+ " or "") .. PROFESSIONS_TRACKER_HEADER_PROFESSION, 0, y, width)
        l.text:SetTextColor(zr, zg, zb, 1)
        y = y + h + 3
        if not shut then
            y = AddRecipeList(list, false, y, width, titleX, objX)
            y = AddRecipeList(recrafts, true, y, width, titleX, objX)
        end
    end
    if nameWait ~= nameListen then
        nameListen = nameWait
        if nameWait then evt:RegisterEvent("ITEM_DATA_LOAD_RESULT") else evt:UnregisterEvent("ITEM_DATA_LOAD_RESULT") end
    end
    return y
end

-------------------------------------------------------------------------------
-- Quest item buttons (customItemButtons). Secure, so they live on their own
-- layer under UIParent and are placed by screen position, never anchored to
-- our frame (which must stay free to move and hide in combat). In combat a
-- layout change waits for combat to end; buttons keep their spot and item.
-------------------------------------------------------------------------------
local itemLayer
local items, itemWant, itemN = {}, {}, 0  -- itemWant: pooled, first itemN in use
local cdRegistered = false

-- Tooltip side facing the screen centre, away from the edge.
local function TooltipSide()
    local cx = frame:GetCenter()
    local onLeft = cx and cx * frame:GetEffectiveScale() < UIParent:GetWidth() * UIParent:GetEffectiveScale() / 2
    return onLeft and "ANCHOR_RIGHT" or "ANCHOR_LEFT"
end

-- Log index looked up per use: it shifts as quests come and go.
local function UpdateItemCooldown(b)
    local logIndex = C_QuestLog.GetLogIndexForQuestID(b.questID)
    if not logIndex then return end
    local start, duration, enable = GetQuestLogSpecialItemCooldown(logIndex)
    if start then CooldownFrame_Set(b.cd, start, duration, enable) end
end

local function ItemButton(i)
    local b = items[i]
    if b then return b end
    b = CreateFrame("Button", nil, itemLayer, "SecureActionButtonTemplate")
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("type", "item")
    b:SetAttribute("useOnKeyDown", false)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnEnter", function(self)
        UpdateHover()
        GameTooltip:SetOwner(self, TooltipSide())
        local logIndex = C_QuestLog.GetLogIndexForQuestID(self.questID)
        if logIndex then GameTooltip:SetQuestLogSpecialItem(logIndex) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() UpdateHover(); GameTooltip:Hide() end)
    items[i] = b
    return b
end

-- Shows a button for each wanted item whose title row is fully in view.
function SyncItems()
    if not itemLayer or (#items == 0 and itemN == 0) then return end
    if InCombatLockdown() then
        ns.CombatQueue.Defer("EQT_CustomItems", SyncItems)
        return
    end
    local n = 0
    local top, bottom = scroll:GetTop(), scroll:GetBottom()
    if frame:IsVisible() and top then
        for i = 1, itemN do
            local w = itemWant[i]
            local l = w.line
            local lt, lr = l:GetTop(), l:GetRight()
            if lt and lt <= top + 0.5 and lt - w.size >= bottom - 0.5 then
                n = n + 1
                local b = ItemButton(n)
                local s = l:GetEffectiveScale() / b:GetEffectiveScale()
                local x, y, size = (lr + hookW + 4) * s, lt * s, w.size * s
                if b.lastX ~= x or b.lastY ~= y or b.lastSize ~= size then
                    b.lastX, b.lastY, b.lastSize = x, y, size
                    b:SetSize(size, size)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
                end
                if b.itemID ~= w.itemID then
                    b.itemID = w.itemID
                    b:SetAttribute("item", "item:" .. w.itemID)
                end
                b.questID = w.questID
                b.icon:SetTexture(w.tex)
                b.count:SetText((w.charges and w.charges > 1) and w.charges or "")
                UpdateItemCooldown(b)
                b:Show()
            end
        end
    end
    for i = n + 1, #items do items[i]:Hide() end
end

-------------------------------------------------------------------------------
-- Row hooks (public, EllesmereUI.RegisterQuestTrackerRow): other addons add
-- their own icons or buttons to quest title rows. Each hook gets its own slot
-- frame per row, right of the title, its reserved width wide. Developer
-- guide: PLUGINS_API.md.
-------------------------------------------------------------------------------
local function RunRowHooks(l, questID)
    local slots = l.slots
    if not slots then slots = {}; l.slots = slots end
    for i, h in ipairs(rowHooks) do
        local s = slots[i]
        if not s then
            s = CreateFrame("Frame", nil, l)
            s:SetPoint("TOPLEFT", l, "TOPRIGHT", h.x, 0)
            s:SetPoint("BOTTOMLEFT", l, "BOTTOMRIGHT", h.x, 0)
            s:SetWidth(h.width)
            slots[i] = s
        end
        s:Show()
        local ok, err = pcall(h.fn, s, questID, l.text)
        if not ok then geterrorhandler()(err) end
    end
end

local function Render()
    pending = false
    if not frame then return end
    if not frame:IsShown() then stale = true; return end
    stale = false
    HideOverlay()
    frame:SetMouseMotionEnabled(HoverWanted() and true or false)
    if not Cfg("customFlashUpdates") then wipe(prevObj) end
    itemN = 0
    wipe(timerEnd)
    timerN = 0
    local timers = C_QuestLog.GetQuestTimers()
    if timers then
        local now = GetTime()
        for _, t in ipairs(timers) do
            if t.questID and t.questTimer then timerEnd[t.questID] = now + t.questTimer end
        end
    end
    BuildList()
    local collapsed = CharDB().ctCollapsed
    local width = (Cfg("customWidth") or DEF_WIDTH) - PAD * 2 - BAR_GAP
    child:SetWidth(width)
    used = 0
    local y = 0
    local itemSize = Cfg("customItemButtons") and (Cfg("titleFontSize") or 12) + 12
    if not collapsed.all then
        local group = Cfg("customGroupByZone")
        -- Focus buttons take a column left of the titles.
        local titleSize = Cfg("titleFontSize") or 12
        local focusSize = Cfg("customFocusClick") and titleSize + 6 or 0
        -- The art overhangs the button by 0.3x each side; keep it off the clip edge, less 2
        -- (the ring's outer edge is the atlas padding).
        local titleX = focusSize > 0 and focusSize * 1.3 - 2 + FOCUS_GAP or 0
        -- It also rises above its title: the button sits (size - font) / 2 higher and the
        -- focused glow reaches 0.5x past it. A quest on the first row starts that far down.
        local focusRise = focusSize > 0 and math.ceil((focusSize - titleSize) / 2 + focusSize * 0.5) or 0
        local objX = math.max(OBJ_IND, titleX)
        local collapseDone = Cfg("customCollapseCompleted")
        local doneOpen = CharDB().ctDoneOpen
        local lastZone
        local zr, zg, zb = ZoneRGB()
        for _, questID in ipairs(order) do
            local zone = zoneOf[questID] or OTHER or "Other"
            if group and zone ~= lastZone then
                lastZone = zone
                if y > 0 then y = y + 6 end
                local mark = collapsed["z:" .. zone] and "+ " or ""
                local l, h = AcquireLine("zone", zone, mark .. zone, 0, y, width)
                l.text:SetTextColor(zr, zg, zb, 1)
                y = y + h + 3
            end
            if not (group and collapsed["z:" .. zone]) then
                local complete = C_QuestLog.IsComplete(questID) == true
                local item
                if itemSize then
                    local logIndex = C_QuestLog.GetLogIndexForQuestID(questID)
                    local link, tex, charges, showDone
                    if logIndex then link, tex, charges, showDone = GetQuestLogSpecialItemInfo(logIndex) end
                    local itemID = link and tonumber(link:match("item:(%d+)"))
                    if itemID and (not complete or showDone) then
                        itemN = itemN + 1
                        item = itemWant[itemN]
                        if not item then item = {}; itemWant[itemN] = item end
                        item.itemID, item.tex, item.charges = itemID, tex, charges
                        item.questID, item.size = questID, itemSize
                    end
                end
                local itemW = item and itemSize + 8 or 0
                if y == 0 then y = focusRise end
                local top = y
                local l, h = AcquireLine("quest", questID, QuestTitle(questID), titleX, y,
                    math.max(TITLE_MIN_W, width - titleX - itemW - hookW))
                l.text:SetTextColor(TitleRGB(questID, complete))
                if rowHooks[1] then RunRowHooks(l, questID) end
                if focusSize > 0 then
                    ShowFocusButton(l, questID, complete, focusSize)
                elseif l.focus then
                    l.focus:Hide()
                end
                if item then item.line = l end
                y = y + h + 2
                local shut
                if complete and collapseDone then
                    shut = not doneOpen[questID]
                else
                    shut = collapsed[questID]
                end
                if not shut then y = AddObjectives(questID, y, width, objX) end
                y = AddTimer(questID, y, width, objX)
                if item then y = math.max(y, top + itemSize + 2) end
                y = y + (Cfg("customQuestSpacing") or 4)
            end
        end
        y = AddRecipes(y, width, titleX, objX, collapsed, zr, zg, zb)
    end
    for i = used + 1, #lines do lines[i]:Hide() end

    local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
    header.count:SetText((numQuests or 0) .. "/" .. C_QuestLog.GetMaxNumQuestsCanAccept())
    header.toggle:SetText(collapsed.all and "+" or "-")

    contentH = y
    child:SetHeight(math.max(y, 1))
    local maxH = Cfg("customMaxHeight") or DEF_HEIGHT
    local body = y > 0 and (y + PAD) or 0
    -- Unlock Mode shows the whole area the tracker may grow into, so its
    -- mover and Height row match what is being set.
    local h = EllesmereUI._unlockActive and maxH or math.min(HEADER_H + body, maxH)
    viewH = math.max(h - HEADER_H - PAD, 0)
    frame:SetHeight(h)
    -- An Unlock Mode link places the tracker by its centre, from its height:
    -- back onto it in the render that changed the height, as Unlock Mode's own
    -- resize notice is throttled and can skip the last change of a burst (a
    -- quest in a new zone arrives over several renders).
    if h ~= frame.renderH then
        frame.renderH = h
        if not EllesmereUI._unlockActive then EllesmereUI.ReapplyOwnAnchor(UNLOCK_KEY) end
    end
    UpdateThumb()
    if (itemSize and true or false) ~= cdRegistered then
        cdRegistered = not cdRegistered
        if cdRegistered then evt:RegisterEvent("BAG_UPDATE_COOLDOWN") else evt:UnregisterEvent("BAG_UPDATE_COOLDOWN") end
    end
    SyncItems()
    ArmTick(GetTime())
end

function Queue()
    if pending then return end
    pending = true
    C_Timer.After(0, Render)
end
EQT.RefreshCustom = Queue

-- Public: fn(slot, questID, titleFontString) runs for each quest title row on
-- every render. width (0-64, default 0) is kept free right of the title.
local HOOK_MAX_W = 64
function EllesmereUI.RegisterQuestTrackerRow(id, fn, width)
    if type(id) ~= "string" or id == "" or type(fn) ~= "function" then return false end
    for _, h in ipairs(rowHooks) do
        if h.id == id then return false end
    end
    width = Clamp(math.floor(tonumber(width) or 0), 0, HOOK_MAX_W)
    rowHooks[#rowHooks + 1] = { id = id, fn = fn, width = width, x = hookW }
    hookW = hookW + width
    Queue()
    return true
end

-- Public: re-render the tracker, for a hook whose own state changed.
EllesmereUI.RefreshQuestTrackerRows = Queue

-------------------------------------------------------------------------------
-- Interaction. Nothing here touches Blizzard's tracker, the watch list, the
-- super-track or the world map (opening it from addon code taints its pins:
-- SetPassThroughButtons blocked in combat, tested 2026-10-17). Untrack is our
-- list's own; a modified click that untracks reaches Blizzard's own quest header
-- through the secure overlay below, whose code edits the watch list.
-------------------------------------------------------------------------------
local function Untrack(questID)
    local db = CharDB()
    db.ctUntracked[questID] = true
    db.ctPinned[questID] = nil
    Queue()
end

local function TogglePin(questID)
    local pinned = CharDB().ctPinned
    pinned[questID] = not pinned[questID] or nil
    Queue()
end

local function Abandon(questID)
    EllesmereUI:ShowConfirmPopup({
        title       = ABANDON_QUEST,
        message     = ABANDON_QUEST_CONFIRM:format(C_QuestLog.GetTitleForQuestID(questID) or ""),
        confirmText = ACCEPT,
        cancelText  = CANCEL,
        onConfirm   = function()
            C_QuestLog.SetSelectedQuest(questID)
            C_QuestLog.SetAbandonQuest()
            C_QuestLog.AbandonQuest()
        end,
    })
end

-- Focus (customFocusClick): sets the super-track straight from our click.
-- Skin.lua dropped this on retail for tainting the world map's pins; on WoW
-- Forever taint logs stayed clean, focusing in combat and using map pins.
function ToggleFocus(questID)
    local cur = C_SuperTrack.GetSuperTrackedQuestID()
    C_SuperTrack.SetSuperTrackedQuestID(cur == questID and 0 or questID)
end

-- For the details window (Details.lua).
EQT.CustomQuestActions = { Focus = ToggleFocus, Untrack = Untrack, Abandon = Abandon }

local function Disabled() return true end
local MENU_OPTS = { fontKey = "questTracker" }

-- The quest's title heads the menu as a disabled row.
local function ShowMenu(owner, questID)
    local items = { { text = C_QuestLog.GetTitleForQuestID(questID) or "", noLoc = true, isDisabled = Disabled } }
    if Cfg("customFocusClick") then
        local focused = C_SuperTrack.GetSuperTrackedQuestID() == questID
        items[#items + 1] = { text = focused and STOP_SUPER_TRACK_QUEST or SUPER_TRACK_QUEST, noLoc = true,
            onClick = function() ToggleFocus(questID) end }
    end
    items[#items + 1] = { noLoc = true,
        text = CharDB().ctPinned[questID] and EllesmereUI.L("Unpin") or EllesmereUI.L("Pin to Top"),
        onClick = function() TogglePin(questID) end }
    items[#items + 1] = { text = OBJECTIVES_STOP_TRACKING, noLoc = true, onClick = function() Untrack(questID) end }
    if IsInGroup() and C_QuestLog.IsPushableQuest(questID) then
        items[#items + 1] = { text = SHARE_QUEST, noLoc = true, onClick = function()
            QuestLogPushQuest(C_QuestLog.GetLogIndexForQuestID(questID))
        end }
    end
    items[#items + 1] = { text = ABANDON_QUEST_ABBREV, noLoc = true, onClick = function() Abandon(questID) end }
    -- Wowhead Quest Links: the entry Blizzard's tracker menu gets, after a divider
    -- as there (QuestLinks.lua).
    if EQT.WowheadQuestOK(questID) then
        items[#items + 1] = "---"
        items[#items + 1] = { text = EllesmereUI.L("Wowhead Link"), noLoc = true,
            onClick = function() EQT.ShowWowheadLink(questID) end }
    end
    EllesmereUI.ShowContextMenu(owner, items, MENU_OPTS)
end

local function ToggleCollapsed(key)
    local collapsed = CharDB().ctCollapsed
    collapsed[key] = not collapsed[key] or nil
    Queue()
end

function OnLineClick(self, button)
    local id = self.id
    if self.kind == "zone" then
        ToggleCollapsed("z:" .. id)
    elseif self.kind == "quest" then
        if button == "RightButton" then ShowMenu(self, id); return end
        if IsModifiedClick("CHATLINK") and ChatFrameUtil.TryInsertQuestLinkForQuestID(id) then return end
        if IsModifiedClick("QUESTWATCHTOGGLE") then Untrack(id); return end
        local action = Cfg("customClickAction") or "collapse"
        if action ~= "collapse" and not IsModifierKeyDown() then
            if action == "details" then EQT.ShowQuestDetails(id) end
            -- map: the overlay's job; reached only in combat, where it is off.
            return
        end
        if Cfg("customCollapseCompleted") and C_QuestLog.IsComplete(id) then
            local open = CharDB().ctDoneOpen
            open[id] = not open[id] or nil
            Queue()
        else
            ToggleCollapsed(id)
        end
    end
end

-------------------------------------------------------------------------------
-- Blizzard header overlay. One secure button over the hovered quest line clicks
-- the quest's block in Blizzard's muted tracker, so Blizzard's own header click
-- does what addon code cannot do cleanly: with Open Quest Log (customClickAction
-- "map") a plain left click opens the map (from addon code it taints the map's
-- pins, SetPassThroughButtons blocked in combat, and a macro /run carries
-- ForceTaint_Strong into them), and on every setting the untrack modifier
-- (QUESTWATCHTOGGLE, Shift by default) untracks the quest in the game's own watch
-- list, so the quest log follows (or, with the chat box open, puts its link in
-- chat). Over a tracked recipe it takes every left and right click to the
-- recipe's block, whose own code opens the recipe, untracks it, links it or
-- opens its menu. Only for a quest or recipe Blizzard's tracker lists; placed by
-- screen position like the item buttons; out of combat only: it hides when
-- combat starts, and a click then takes our own path (none for a recipe). Open
-- Quest Details uses our own window (Details.lua).
-------------------------------------------------------------------------------
local QUEST_MODULES = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }
-- The untrack modifier as a secure attribute prefix (a single-modifier binding)
local UNTRACK_PREFIX = { SHIFT = "shift-", CTRL = "ctrl-", ALT = "alt-" }
local overlay

-- The header button of Blizzard's block for the quest, if it has one.
local function BlizzardHeader(questID)
    for _, name in ipairs(QUEST_MODULES) do
        local module = _G[name]
        local block = module and module.GetExistingBlock and module:GetExistingBlock(questID)
        if block and block.HeaderButton then return block.HeaderButton end
    end
end

-- The header button of Blizzard's block for a tracked recipe (id: negative
-- for a recraft, as Blizzard keys its blocks), if it has one.
local function RecipeHeader(id)
    local module = _G.ProfessionsRecipeTracker
    local block = module and module.GetExistingBlock and module:GetExistingBlock(id)
    return block and block.HeaderButton
end

local function Overlay()
    if overlay then return overlay end
    overlay = CreateFrame("Button", nil, itemLayer, "SecureActionButtonTemplate")
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- The clicks set per line (ShowOverlay) go to Blizzard's header; the rest
    -- go to PostClick, our own line click.
    overlay:SetAttribute("useOnKeyDown", false)
    overlay:SetScript("PostClick", function(self, button)
        -- A recipe: Blizzard's recipe block took the click.
        if self.line.kind == "recipe" then return end
        if button == "LeftButton" then
            local prefix = SecureButton_GetModifierPrefix(self)
            if self:GetAttribute(prefix .. "type1") == "click" then
                -- Blizzard's header took it. A quest it untracked also leaves our
                -- list for good, or zone auto-track would list it again.
                if prefix ~= "" and not C_QuestLog.GetQuestWatchType(self.line.id) then
                    Untrack(self.line.id)
                end
                return
            end
        end
        OnLineClick(self.line, button)
    end)
    overlay:SetScript("OnEnter", function(self) OnLineEnter(self.line) end)
    overlay:SetScript("OnLeave", function()
        OnLineLeave()
        HideOverlay()
    end)
    return overlay
end

function HideOverlay()
    if overlay and not InCombatLockdown() then overlay:Hide() end
end

-- Covers the part of the line inside the scroll view.
local function ShowOverlay(l)
    if InCombatLockdown() then return end
    local recipe = l.kind == "recipe"
    local header
    if recipe then header = RecipeHeader(l.id) else header = BlizzardHeader(l.id) end
    if not header then return end
    local top, bottom = math.min(l:GetTop(), scroll:GetTop()), math.max(l:GetBottom(), scroll:GetBottom())
    if top <= bottom then return end
    local o = Overlay()
    local s = l:GetEffectiveScale() / o:GetEffectiveScale()
    o:ClearAllPoints()
    o:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l:GetLeft() * s, top * s)
    o:SetSize(l:GetWidth() * s, (top - bottom) * s)
    -- Plain left click: Open Quest Log only. The untrack modifier: always.
    -- A recipe: every left and right click.
    local map = recipe or Cfg("customClickAction") == "map"
    o:SetAttribute("type1", map and "click" or nil)
    o:SetAttribute("clickbutton1", map and header or nil)
    local untrack = UNTRACK_PREFIX[GetModifiedClick("QUESTWATCHTOGGLE") or ""]
    for _, prefix in pairs(UNTRACK_PREFIX) do
        local on = recipe or prefix == untrack
        o:SetAttribute(prefix .. "type1", on and "click" or nil)
        o:SetAttribute(prefix .. "clickbutton1", on and header or nil)
    end
    o:SetAttribute("type2", recipe and "click" or nil)
    o:SetAttribute("clickbutton2", recipe and header or nil)
    o.line = l
    o:Show()
end

-- One icon line per reward; Blizzard's tooltip helper shows one item, no choices.
-- Uncached items redraw the tooltip once loaded, if owner still holds it.
local function AddRewardLine(e, owner)
    if not e.name then
        EQT.OnRewardLoad(e, function()
            if GameTooltip:IsOwned(owner) then OnLineEnter(owner) end
        end)
        return
    end
    local text = e.count and e.count > 1
        and BONUS_OBJECTIVE_REWARD_WITH_COUNT_FORMAT:format(e.texture, HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(e.count), e.name)
        or BONUS_OBJECTIVE_REWARD_FORMAT:format(e.texture, e.name)
    local c = e.quality and ColorManager.GetColorDataForItemQuality(e.quality)
    if c then GameTooltip:AddLine(text, c.r, c.g, c.b) else GameTooltip:AddLine(text, 1, 1, 1) end
end

local function AddRewards(questID, owner)
    local r = EQT.QuestRewards(questID)
    if not r then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(QUEST_REWARDS, NORMAL_FONT_COLOR:GetRGB())
    if r.xp > 0 then GameTooltip:AddLine(BONUS_OBJECTIVE_EXPERIENCE_FORMAT:format(r.xp), 1, 1, 1) end
    if r.money > 0 then GameTooltip:AddLine(GetMoneyString(r.money), 1, 1, 1) end
    for _, e in ipairs(r.rewards) do AddRewardLine(e, owner) end
    if #r.choices > 0 then
        GameTooltip:AddLine(REWARD_CHOICES, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
        for _, e in ipairs(r.choices) do AddRewardLine(e, owner) end
    end
end

function OnLineEnter(self)
    UpdateHover()
    -- A recipe: only the overlay that takes its clicks to Blizzard's block.
    if self.kind == "recipe" then ShowOverlay(self); return end
    if self.kind ~= "quest" then return end
    ShowOverlay(self)
    GameTooltip:SetOwner(self, TooltipSide())
    if IsInGroup() then
        GameTooltip:SetQuestPartyProgress(self.id)
    else
        local link = GetQuestLink(self.id)
        if link then
            GameTooltip:SetHyperlink(link)
        else
            GameTooltip:SetText(C_QuestLog.GetTitleForQuestID(self.id) or "")
        end
    end
    AddRewards(self.id, self)
    GameTooltip:Show()
end

function OnLineLeave()
    UpdateHover()
    GameTooltip:Hide()
end

-------------------------------------------------------------------------------
-- Frame
-------------------------------------------------------------------------------
local function ApplyBackground()
    if not frame then return end
    local c = EQT.DB()
    frame.bg:SetColorTexture(c.bgR or 0, c.bgG or 0, c.bgB or 0, c.bgAlpha or 0.5)
    frame.topLine:SetColorTexture(EQT.GetLineRGB())
    ShowBackground(true)
    local hr, hg, hb = EQT.GetHeaderRGB()
    header.text:SetTextColor(hr, hg, hb)
    header.toggle:SetTextColor(hr, hg, hb)
end

local function RefreshFonts()
    if not frame then return end
    fontGen = fontGen + 1
    local size = Cfg("headerFontSize") or 13
    StyleText(header.text, size)
    StyleText(header.toggle, size)
    StyleText(header.count, Cfg("objectiveFontSize") or 10)
    header.text:SetText(TRACKER_HEADER_QUESTS)
    Queue()
end

local function SavedPos()
    local p = Cfg("customPos")
    return p and p.point and p or { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -80, y = -280 }
end

-- Anchor fractions per point, for re-anchoring a saved position by the edge
-- the tracker keeps in place.
local HX = { LEFT = 0, CENTER = 0.5, RIGHT = 1, TOP = 0.5, BOTTOM = 0.5,
             TOPLEFT = 0, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 1 }
local VY = { TOP = 1, CENTER = 0.5, BOTTOM = 0, LEFT = 0.5, RIGHT = 0.5,
             TOPLEFT = 1, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 0 }
-- The same horizontal point on the other vertical edge.
local OTHER_EDGE = { TOPLEFT = "BOTTOMLEFT", TOP = "BOTTOM", TOPRIGHT = "BOTTOMRIGHT",
                     BOTTOMLEFT = "TOPLEFT", BOTTOM = "TOP", BOTTOMRIGHT = "TOPRIGHT" }

-- Grow Direction: the tracker keeps its top edge and grows down, or keeps its
-- bottom edge and grows up.
local function GrowsUp() return Cfg("customGrowUp") == true end

-- Same spot, anchored by the edge the tracker keeps, so a height change grows
-- away from it. A spot on the other edge is that edge of the same area (the
-- width by the max height): both directions fill one box, from opposite
-- ends. Unlock Mode hands back CENTER points; the current size places the edge.
local function Anchored(p)
    local point, rel = p.point, p.relPoint or p.point
    local up = GrowsUp()
    local vy = VY[point]
    if vy == (up and 0 or 1) or not (HX[point] and HX[rel]) then return p end
    if OTHER_EDGE[point] then
        local maxH = Cfg("customMaxHeight") or DEF_HEIGHT
        return { point = OTHER_EDGE[point], relPoint = rel,
                 x = p.x or 0, y = (p.y or 0) + (up and -maxH or maxH) }
    end
    if not frame then return p end
    local px = UIParent:GetWidth() * HX[rel] + (p.x or 0)
    local py = UIParent:GetHeight() * VY[rel] + (p.y or 0)
    local left = px - frame:GetWidth() * HX[point]
    if up then
        return { point = "BOTTOMLEFT", relPoint = "BOTTOMLEFT", x = left, y = py - frame:GetHeight() * vy }
    end
    return { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = left, y = py + frame:GetHeight() * (1 - vy) }
end

-- The saved spot by the edge the tracker keeps: what Unlock Mode reads and
-- places it by at login.
local function GrowSpot() return Anchored(SavedPos()) end

local function Place()
    local p = GrowSpot()
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    -- Linked to another element in Unlock Mode: back onto that link.
    EllesmereUI.ReapplyOwnAnchor(UNLOCK_KEY)
    SyncItems()
end

-------------------------------------------------------------------------------
-- Starting place. With no spot saved, the tracker takes the place and size of
-- Blizzard's tracker, which it replaces (muted, but still placed by Edit
-- Mode), so turning it on does not move the quest list. Under the EllesmereUI
-- look that tracker's background ran from 6 left of it (19 with Blizzard's
-- quest icons shown) to 11 right of it, and began under the master header
-- while that header was hidden; a stock style showed the tracker's own box.
-------------------------------------------------------------------------------
local SKIN_LEFT, SKIN_LEFT_ICONS, SKIN_RIGHT = 6, 19, 11
local SEED_TRIES = 10    -- then the fallback spot stands until the next login
local seedWait = false   -- a spot is still to be taken from Blizzard's tracker
local seedTries, seedQueued = 0, false
local worldReady = false -- the first PLAYER_ENTERING_WORLD has come

-- Blizzard's tracker stands where it will stay: the world has loaded (at
-- login the right-side frames are still settling before that) and Edit Mode
-- has placed its systems.
local function BlizzardPlaced()
    local otf = _G.ObjectiveTrackerFrame
    return worldReady and otf ~= nil and (not otf.IsInitialized or otf:IsInitialized())
end

-- Left, top, width and height of that panel in UIParent units; nothing until
-- Edit Mode has placed Blizzard's tracker, or while its rect cannot be read.
local function BlizzardPanel()
    if not BlizzardPlaced() then return end
    local otf = _G.ObjectiveTrackerFrame
    local left, top, w, h = otf:GetLeft(), otf:GetTop(), otf:GetWidth(), otf:GetHeight()
    local scale, ui = otf:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (left and top and w and h and scale and ui) then return end
    if IsSecret(left) or IsSecret(top) or IsSecret(w) or IsSecret(h) or IsSecret(scale) then return end
    if w < 1 or h < 1 or ui <= 0 then return end
    local s = scale / ui
    if EQT.Blizz() then return left * s, top * s, w * s, h * s end
    local padLeft = Cfg("showQuestIcons") and SKIN_LEFT_ICONS or SKIN_LEFT
    local panelTop = top
    local header = otf.HeaderMenu or otf.Header
    if header and EQT.ShouldHideMasterHeader() then
        local bottom = header:GetBottom()
        if bottom and not IsSecret(bottom) and bottom < top then panelTop = bottom end
    end
    return (left - padLeft) * s, panelTop * s, (w + padLeft + SKIN_RIGHT) * s, (h - (top - panelTop)) * s
end

-- Takes the spot from Blizzard's tracker, and its width and height while ours
-- are still the ones a new profile starts on. False while it has no place.
local function TakeBlizzardSpot()
    local left, top, w, h = BlizzardPanel()
    if not left then return false end
    local c = EQT.DB()
    if (c.customWidth or DEF_WIDTH) == DEF_WIDTH then
        c.customWidth = Clamp(math.floor(w + 0.5), WIDTH_MIN, WIDTH_MAX)
    end
    if (c.customMaxHeight or DEF_HEIGHT) == DEF_HEIGHT then
        c.customMaxHeight = Clamp(math.floor(h + 0.5), HEIGHT_MIN, HEIGHT_MAX)
    end
    -- The panel's top edge; growing up, the bottom edge of the same area.
    c.customPos = Anchored({ point = "TOPLEFT", relPoint = "BOTTOMLEFT",
                             x = math.floor(left + 0.5), y = math.floor(top + 0.5) })
    return true
end

-- The profile's spot and width, the spot taken from Blizzard's tracker first
-- when the profile has none. Until that tracker is placed (it is not yet at
-- login) the frame sits at the fallback spot; Edit Mode's layout event, heard
-- only while a spot is still to be taken, moves it once (SeedSoon).
local function ApplySpot()
    local wait = Cfg("customPos") == nil and not TakeBlizzardSpot()
    if wait ~= seedWait then
        seedWait = wait
        if wait then
            seedTries = 0
            evt:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        else
            evt:UnregisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        end
    end
    frame:SetWidth(Cfg("customWidth") or DEF_WIDTH)
    if EllesmereUI._unlockActive then
        frame:SetHeight(Cfg("customMaxHeight") or DEF_HEIGHT)
    else
        Place()
    end
    Queue()
end

-- Edit Mode has placed its systems, or the world or the quest log has loaded:
-- one more try a frame later, once every handler of that event has run. A
-- placed tracker whose rect still cannot be read stops the tries after a
-- few; the fallback spot then stands until the next login.
local function SeedSoon()
    if not seedWait or seedQueued then return end
    seedQueued = true
    C_Timer.After(0, function()
        seedQueued = false
        if not seedWait then return end
        ApplySpot()
        if seedWait and BlizzardPlaced() then
            seedTries = seedTries + 1
            if seedTries >= SEED_TRIES then
                seedWait = false
                evt:UnregisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
            end
        end
    end)
end

local function BuildFrame()
    frame = CreateFrame("Frame", "EUI_CustomQuestTracker", UIParent)
    frame:SetFrameStrata("LOW")
    frame:SetWidth(Cfg("customWidth") or DEF_WIDTH)
    frame:SetHeight(HEADER_H)
    frame:SetClampedToScreen(Cfg("forceOnScreen") == true)
    frame:SetScript("OnShow", function()
        itemLayer:SetAlpha(frame:GetAlpha())
        if stale then Render() else SyncItems() end
    end)
    -- Alpha first: in combat the hide itself waits for combat to end.
    frame:SetScript("OnHide", function() itemLayer:SetAlpha(0); SyncItems(); HideOverlay() end)
    -- Item buttons sit outside our frame: they follow its alpha (mouseover fade).
    itemLayer = CreateFrame("Frame", nil, UIParent)
    itemLayer:SetFrameStrata("LOW")
    itemLayer:SetFrameLevel(frame:GetFrameLevel() + 20)
    hooksecurefunc(frame, "SetAlpha", function(_, a) itemLayer:SetAlpha(a) end)
    -- Hover modes only: motion (no clicks) so hover sees the cursor over gaps.
    frame:SetMouseClickEnabled(false)
    frame:SetScript("OnEnter", UpdateHover)
    frame:SetScript("OnLeave", UpdateHover)
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetAllPoints()
    holder:SetFrameLevel(frame:GetFrameLevel())
    holder.fade = holder:CreateAnimationGroup()
    holder.fade:SetToFinalAlpha(true)
    holder.anim = holder.fade:CreateAnimation("Alpha")
    frame.bgHolder = holder
    frame.bg = holder:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.topLine = holder:CreateTexture(nil, "BORDER")
    frame.topLine:SetPoint("TOPLEFT")
    frame.topLine:SetPoint("TOPRIGHT")
    frame.topLine:SetHeight(1)

    header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_H)
    header.text = header:CreateFontString(nil, "OVERLAY")
    header.text:SetPoint("LEFT", PAD, 0)
    header.toggle = header:CreateFontString(nil, "OVERLAY")
    header.toggle:SetPoint("RIGHT", -PAD, 0)
    header.count = header:CreateFontString(nil, "OVERLAY")
    header.count:SetPoint("RIGHT", header.toggle, "LEFT", -8, 0)
    header.count:SetTextColor(1, 1, 1, 0.5)
    header:SetScript("OnClick", function() ToggleCollapsed("all") end)
    header:SetScript("OnEnter", UpdateHover)
    header:SetScript("OnLeave", UpdateHover)

    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", PAD, -HEADER_H)
    scroll:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    scroll:SetClipsChildren(true)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        ScrollTo(self:GetVerticalScroll() - delta * WHEEL)
    end)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)

    track = CreateFrame("Frame", nil, frame)
    track:SetWidth(BAR_W)
    track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 0, 0)
    track.bg = track:CreateTexture(nil, "BACKGROUND")
    track.bg:SetAllPoints()
    track.bg:SetColorTexture(1, 1, 1, 0.05)
    track:Hide()

    -- Draggable thumb; OnUpdate only while dragging.
    thumb = CreateFrame("Frame", nil, track)
    thumb:SetWidth(BAR_W)
    thumb:EnableMouse(true)
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetAllPoints()
    thumb.tex:SetColorTexture(1, 1, 1, 0.3)
    local function OnDrag(self)
        local _, cy = GetCursorPosition()
        local dy = (self.startY - cy) / self:GetEffectiveScale()
        local free = viewH - self:GetHeight()
        if free > 0 then ScrollTo(self.startScroll + dy * MaxScroll() / free) end
    end
    thumb:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        self.startY, self.startScroll = cy, scroll:GetVerticalScroll()
        self:SetScript("OnUpdate", OnDrag)
    end)
    thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil); UpdateHover() end)

    ApplySpot()
    ApplyBackground()
    RefreshFonts()
end

-------------------------------------------------------------------------------
-- Visibility: the module's visibility rules, raid / arena auto-hide and
-- cross-module suppression, on our own frame.
-------------------------------------------------------------------------------
local function AutoHidden()
    local _, instanceType = IsInInstance()
    if instanceType == "arena" then return true end
    if instanceType == "raid" then
        local mode = Cfg("hideInRaidMode")
        return mode == "always" or (mode ~= "never" and inEncounter)
    end
    return false
end

-- Visibility options that cannot change during a fight.
local FIGHT_STATIC = {
    visOnlyInstances = true, visHideInstances = true,
    visOnlyDungeons  = true, visHideDungeons  = true,
    visOnlyHousing   = true, visHideHousing   = true,
    visOnlyResting   = true, visHideResting   = true,
}

-- The tracker can hide mid-fight: Hide When In Raid (unless Never), a combat or
-- group rule, or any other visibility option (target, mounted, vehicle, Party Mode).
local function CanHideInCombat()
    local _, instanceType = IsInInstance()
    if instanceType == "raid" and Cfg("hideInRaidMode") ~= "never" then return true end
    local db = EQT.DB()
    if EllesmereUI.VisDependsOnCombat(db, "visibility") then return true end
    local sel = EllesmereUI.GetVisibilitySelection(db, "visibility")
    if sel.in_raid or sel.in_party or sel.solo then return true end
    for _, k in ipairs(EllesmereUI.VIS_OPT_KEYS) do
        if db[k] and not FIGHT_STATIC[k] then return true end
    end
    return false
end

local function Blocked()
    return Cfg("enabled") == false or EQT.IsSuppressed() or AutoHidden()
end

local function UpdateVisibility()
    if not frame then return end
    local vis = not Blocked() and EllesmereUI.EvalVisibility(EQT.DB())
    if not vis then frame:Hide(); return end
    frame:Show()
    frame:SetAlpha(vis == "mouseover" and 0 or 1)
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local EVENTS = {
    "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "QUEST_ACCEPTED", "QUEST_REMOVED",
    "SUPER_TRACKING_CHANGED", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "ENCOUNTER_START", "ENCOUNTER_END",
    "PLAYER_REGEN_DISABLED", "TRACKED_RECIPE_UPDATE",
}

evt:SetScript("OnEvent", function(_, event, questID, added)
    if event == "PLAYER_REGEN_DISABLED" then
        -- InCombatLockdown() is already true here, but protected writes stay
        -- legal until this handler returns: last chance to hide secure buttons,
        -- which would otherwise stay clickable on a hidden tracker.
        if overlay then overlay:Hide() end
        if CanHideInCombat() then
            for _, b in ipairs(items) do b:Hide() end
            ns.CombatQueue.Defer("EQT_CustomItems", SyncItems)
        end
        return
    elseif event == "BAG_UPDATE_COOLDOWN" then
        for _, b in ipairs(items) do
            if b:IsShown() then UpdateItemCooldown(b) end
        end
        return
    elseif event == "EDIT_MODE_LAYOUTS_UPDATED" then
        SeedSoon()
        return
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        -- A reagent name the recipe list asked for (questID is the item here,
        -- added whether it loaded); any other item load is not ours.
        if not nameAsked[questID] then return end
        if not added then nameAsked[questID] = false end
    elseif event == "TRACKED_RECIPE_UPDATE" then
        wipe(schematics)
    elseif event == "QUEST_WATCH_LIST_CHANGED" then
        -- Tracking it again in the quest log brings it back.
        if questID and added then CharDB().ctUntracked[questID] = nil end
    elseif event == "QUEST_REMOVED" and questID then
        local db = CharDB()
        db.ctUntracked[questID] = nil
        db.ctCollapsed[questID] = nil
        db.ctDoneOpen[questID] = nil
        db.ctPinned[questID] = nil
        prevObj[questID] = nil
    elseif event == "ENCOUNTER_START" or event == "ENCOUNTER_END" or event == "PLAYER_ENTERING_WORLD" then
        if event == "PLAYER_ENTERING_WORLD" then worldReady = true end
        inEncounter = event == "ENCOUNTER_START"
        UpdateVisibility()
    end
    if seedWait then SeedSoon() end
    Queue()
end)

-------------------------------------------------------------------------------
-- Entry point (loader, custom mode only). Takes over the EQT entry points the
-- options page and profile refresh call, so none of them reach Blizzard's
-- tracker.
-------------------------------------------------------------------------------
local function Noop() end

function EQT.InitCustom()
    EQT.MuteBlizzardTracker()
    BuildFrame()

    EQT.UpdateVisibility    = UpdateVisibility
    EQT.RefreshStateDriver  = UpdateVisibility
    EQT.ApplyBackground     = ApplyBackground
    EQT.RefreshFonts        = RefreshFonts
    EQT.RestyleAll          = function() ApplyBackground(); RefreshFonts() end
    EQT.ApplyForceOnScreen  = function() frame:SetClampedToScreen(Cfg("forceOnScreen") == true) end
    EQT.ApplyMasterHeaderVisibility = Noop
    EQT.QueueResize         = Noop
    EQT.ResizeBGToContent   = Noop
    -- Profile swap, and the options page's Width and Max Height: the
    -- profile's width, height and spot.
    EQT.SyncPosition        = ApplySpot

    for _, e in ipairs(EVENTS) do evt:RegisterEvent(e) end
    EllesmereUI.RegisterVisibilityUpdater(UpdateVisibility)
    EllesmereUI.RegisterMouseoverTarget(frame, function()
        return not Blocked() and EllesmereUI.VisWantsMouseover(EQT.DB(), "visibility")
    end)
    EllesmereUI.RegAccent({ type = "callback", fn = EQT.RestyleAll })

    -- Unlock Mode keeps the edge the tracker grows away from: its own answer
    -- in place of the one Blizzard's tracker has under this key.
    EllesmereUI.GetQuestTrackerGrowDir = function() return GrowsUp() and "UP" or "DOWN" end

    EllesmereUI:RegisterUnlockElements({ EllesmereUI.MakeUnlockElement({
        key      = UNLOCK_KEY,
        label    = "Quest Tracker",
        group    = "Quest Tracker",
        order    = 560,
        getFrame = function() return frame end,
        isHidden = function() return not Cfg("enabled") end,
        -- One spot for every spec, like Blizzard's tracker under this key.
        noSpecLayout = true,
        -- Width, and the height the tracker may grow to: in Unlock Mode the
        -- frame fills that whole area (Render), so the mover outlines it.
        getSize  = function()
            return Cfg("customWidth") or DEF_WIDTH, Cfg("customMaxHeight") or DEF_HEIGHT
        end,
        -- Unlock Mode also calls these with no size, to lay the element out again.
        setWidth = function(_, w)
            if w then EQT.Set("customWidth", Clamp(math.floor(w + 0.5), WIDTH_MIN, WIDTH_MAX)) end
            frame:SetWidth(Cfg("customWidth") or DEF_WIDTH)
            Queue()
        end,
        setHeight = function(_, h)
            if h then EQT.Set("customMaxHeight", Clamp(math.floor(h + 0.5), HEIGHT_MIN, HEIGHT_MAX)) end
            if EllesmereUI._unlockActive then frame:SetHeight(Cfg("customMaxHeight") or DEF_HEIGHT) end
            Queue()
        end,
        savePos  = function(_, point, relPoint, x, y)
            if not point then return end
            EQT.Set("customPos", Anchored({ point = point, relPoint = relPoint, x = x, y = y }))
            if not EllesmereUI._unlockActive then Place() end
        end,
        loadPos  = GrowSpot,
        -- Back to its starting place: where Blizzard's tracker sits.
        clearPos = function() EQT.Set("customPos", nil); ApplySpot(); Place() end,
        applyPos = Place,
    }) }, "EllesmereUIQuestTracker")

    -- Unlock Mode outlines the whole area the tracker may fill; a closed
    -- session takes it back to the height of its quests. A drag leaves the
    -- frame on Unlock Mode's own anchor, so it first goes back onto the edge
    -- it keeps.
    EllesmereUI:RegisterUnlockModeListener("EllesmereUIQuestTracker", function(active)
        if active then
            frame:SetHeight(Cfg("customMaxHeight") or DEF_HEIGHT)
        else
            Place()
        end
        Render()
    end)

    UpdateVisibility()
    Queue()
end

-- The options page's sliders: the width and height a user can set.
function EQT.CustomSizeRange()
    return WIDTH_MIN, WIDTH_MAX, HEIGHT_MIN, HEIGHT_MAX
end

-- The options page's Grow Direction. The saved spot moves to the other edge
-- of the same area, so the tracker fills the box it had from its other end,
-- and a later Max Height change leaves the edge it keeps where it is.
function EQT.SetCustomGrowUp(up)
    up = up and true or false
    if GrowsUp() == up then return end
    EQT.Set("customGrowUp", up)
    local p = Cfg("customPos")
    if p and p.point then EQT.Set("customPos", Anchored(p)) end
    if frame then ApplySpot() end
end
