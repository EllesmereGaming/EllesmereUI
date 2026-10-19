if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not EllesmereUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
-- EllesmereUIQuestTracker_Custom.lua  (WoW Forever only)
--
-- Our own quest tracker frame, used instead of ObjectiveTrackerFrame when the
-- Custom Quest Tracker option is on. Blizzard's tracker is muted (alpha 0,
-- click-through, see EQT.MuteBlizzardTracker) and never skinned or fed watch
-- list edits. This file only reads the quest log and watch list: untracking,
-- zone auto-track, filters and sorting all live in our own list (the
-- Forever file's quest tools, read-only).
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT
local function Cfg(k) return EQT.Cfg(k) end

-- Defaults, merged into the module's table before its DB is made at login.
do
    local qt = ns.QT_DEFAULTS.profile.questTracker
    qt.customTracker           = false  -- reload-gated; position in customPos
    qt.customGroupByZone       = true
    qt.customDifficultyColor   = true
    qt.customWidth             = 260
    qt.customMaxHeight         = 450
    qt.customCollapseCompleted = false
    qt.customZoneFontSize      = 13
    qt.customQuestSpacing      = 4
    qt.customObjSpacing        = 1
    qt.customFocusClick        = false     -- focus buttons + menu entry
    qt.customWrapTitles        = true      -- off: one line, cut with "..."
    qt.customWrapObjectives    = true
    qt.customScrollbar         = "always"  -- always / hover / hidden
    qt.customBgHover           = false     -- background + top line only while hovered
    qt.customBgFade            = true      -- fade it in and out
    qt.customItemButtons       = false     -- quest item buttons beside titles
    qt.customFlashUpdates      = false     -- flash objectives that just changed
end

local PAD      = 8
local HEADER_H = 24
local BAR_W    = 3    -- scrollbar track width
local BAR_GAP  = 6    -- space kept for the track right of the text
local OBJ_IND  = 10   -- objective indent
local FOCUS_GAP = 4   -- focus button to title
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
    if not EllesmereUIDB then EllesmereUIDB = {} end
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
-- Stable sort of order by rank(questID), lowest first.
local function StableSortBy(rank)
    local pos = {}
    for i, questID in ipairs(order) do pos[questID] = i end
    table.sort(order, function(a, b)
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        return pos[a] < pos[b]
    end)
end

local function BuildList()
    wipe(order); wipe(zoneOf); wipe(seen)
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
    EQT.QuestLogSnapshot()
    local auto = EQT.AutoTrackOn()
    local zone
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHeader then
            zone = info.title
        elseif info and info.questID then
            local questID = info.questID
            zoneOf[questID] = zone
            if pinned[questID] or (auto and EQT.QuestInArea(info, zone)) then
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
        StableSortBy(function(q) return pinned[q] and 0 or 1 end)
    end
    if not Cfg("customGroupByZone") then return end
    -- Zones in order of their first quest.
    local zoneRank, n = {}, 0
    for _, questID in ipairs(order) do
        local z = zoneOf[questID] or ""
        if not zoneRank[z] then n = n + 1; zoneRank[z] = n end
    end
    StableSortBy(function(q) return zoneRank[zoneOf[q] or ""] end)
end

-------------------------------------------------------------------------------
-- Lines: one pooled Button per row (zone header, quest title, objective).
-------------------------------------------------------------------------------
local OnLineClick, OnLineEnter, OnLineLeave, ToggleFocus, SyncItems  -- defined below

-- Outline and shadow follow the Fonts page's Module Outline.
local function StyleText(fs, size)
    EllesmereUI.PrimeFontShadow(fs, EllesmereUI.GetFontUseShadow("questTracker") and true or false)
    local flag = EllesmereUI.GetFontOutlineFlag("questTracker")
    if not pcall(fs.SetFont, fs, EQT.GetFont(), size, flag) then
        fs:SetFont("Fonts/FRIZQT__.TTF", size, flag)
    end
end

local SIZE_KEY = { zone = "customZoneFontSize", quest = "titleFontSize", obj = "objectiveFontSize" }
local SIZE_DEF = { zone = 13, quest = 12, obj = 10 }

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
    end
    l.id = id
    if l.flash and l.key ~= key then l.flash:Stop() end
    l.key = key
    if l.focus then l.focus:Hide() end
    l:EnableMouse(kind ~= "obj")
    l.text:SetWordWrap(Cfg(kind == "obj" and "customWrapObjectives" or "customWrapTitles") ~= false)
    l.text:SetWidth(width)
    l.text:SetText(text)
    local h = math.ceil(l.text:GetStringHeight())
    l:SetSize(width, h)
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", child, "TOPLEFT", x, -y)
    l:Show()
    return l, h
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
    if Cfg("customDifficultyColor") ~= false then
        local c = GetDifficultyColor(C_PlayerInfo.GetContentDifficultyQuestForPlayer(questID))
        if c then return c.r, c.g, c.b end
    end
    return EQT.GetTitleRGB()
end

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
local function QuestTitle(questID)
    local title = C_QuestLog.GetTitleForQuestID(questID) or ""
    local prefix = QuestUtilsOverrides.GetQuestTitlePrefix({
        questID = questID, difficultyLevel = C_QuestLog.GetQuestDifficultyLevel(questID) })
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
    b:Show()
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
            l, h = AcquireLine("obj", questID, "- " .. text, x, y, w, questID .. ":" .. i)
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
-- Quest item buttons (customItemButtons). Secure, so they live on their own
-- layer under UIParent and are placed by screen position, never anchored to
-- our frame (which must stay free to move and hide in combat). In combat a
-- layout change waits for combat to end; buttons keep their spot and item.
-------------------------------------------------------------------------------
local itemLayer
local items, itemWant = {}, {}
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
    if not itemLayer or (#items == 0 and #itemWant == 0) then return end
    if InCombatLockdown() then
        ns.CombatQueue.Defer("EQT_CustomItems", SyncItems)
        return
    end
    local n = 0
    local top, bottom = scroll:GetTop(), scroll:GetBottom()
    if frame:IsVisible() and top then
        for _, w in ipairs(itemWant) do
            local l = w.line
            local lt, lr = l:GetTop(), l:GetRight()
            if lt and lt <= top + 0.5 and lt - w.size >= bottom - 0.5 then
                n = n + 1
                local b = ItemButton(n)
                local s = l:GetEffectiveScale() / b:GetEffectiveScale()
                b:SetSize(w.size * s, w.size * s)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (lr + 4) * s, lt * s)
                b:SetAttribute("item", "item:" .. w.itemID)
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

local function Render()
    pending = false
    if not frame then return end
    if not frame:IsShown() then stale = true; return end
    stale = false
    frame:SetMouseMotionEnabled(HoverWanted() and true or false)
    if not Cfg("customFlashUpdates") then wipe(prevObj) end
    wipe(itemWant)
    BuildList()
    local collapsed = CharDB().ctCollapsed
    local width = (Cfg("customWidth") or 260) - PAD * 2 - BAR_GAP
    child:SetWidth(width)
    used = 0
    local y = 0
    local itemSize = Cfg("customItemButtons") and (Cfg("titleFontSize") or 12) + 12
    if not collapsed.all then
        local group = Cfg("customGroupByZone")
        -- Focus buttons take a column left of the titles.
        local focusSize = Cfg("customFocusClick") and (Cfg("titleFontSize") or 12) + 6 or 0
        -- The art overhangs the button by 0.3x each side; keep it off the clip edge.
        local titleX = focusSize > 0 and focusSize * 1.3 + FOCUS_GAP or 0
        local objX = math.max(OBJ_IND, titleX)
        local collapseDone = Cfg("customCollapseCompleted")
        local doneOpen = CharDB().ctDoneOpen
        local lastZone
        local hr, hg, hb = EQT.GetHeaderRGB()
        for _, questID in ipairs(order) do
            local zone = zoneOf[questID] or OTHER or "Other"
            if group and zone ~= lastZone then
                lastZone = zone
                if y > 0 then y = y + 6 end
                local mark = collapsed["z:" .. zone] and "+ " or ""
                local l, h = AcquireLine("zone", zone, mark .. zone, 0, y, width)
                l.text:SetTextColor(hr, hg, hb, 1)
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
                        item = { itemID = itemID, tex = tex, charges = charges,
                                 questID = questID, size = itemSize }
                    end
                end
                local itemW = item and itemSize + 8 or 0
                local top = y
                local l, h = AcquireLine("quest", questID, QuestTitle(questID), titleX, y, width - titleX - itemW)
                l.text:SetTextColor(TitleRGB(questID, complete))
                if focusSize > 0 then ShowFocusButton(l, questID, complete, focusSize) end
                if item then item.line = l; itemWant[#itemWant + 1] = item end
                y = y + h + 2
                local shut
                if complete and collapseDone then
                    shut = not doneOpen[questID]
                else
                    shut = collapsed[questID]
                end
                if not shut then y = AddObjectives(questID, y, width, objX) end
                if item then y = math.max(y, top + itemSize + 2) end
                y = y + (Cfg("customQuestSpacing") or 4)
            end
        end
    end
    for i = used + 1, #lines do lines[i]:Hide() end

    local _, numQuests = C_QuestLog.GetNumQuestLogEntries()
    header.count:SetText((numQuests or 0) .. "/" .. C_QuestLog.GetMaxNumQuestsCanAccept())
    header.toggle:SetText(collapsed.all and "+" or "-")

    contentH = y
    child:SetHeight(math.max(y, 1))
    local maxH = Cfg("customMaxHeight") or 450
    local body = y > 0 and (y + PAD) or 0
    local h = math.min(HEADER_H + body, maxH)
    viewH = math.max(h - HEADER_H - PAD, 0)
    frame:SetHeight(h)
    UpdateThumb()
    if (itemSize and true or false) ~= cdRegistered then
        cdRegistered = not cdRegistered
        if cdRegistered then evt:RegisterEvent("BAG_UPDATE_COOLDOWN") else evt:UnregisterEvent("BAG_UPDATE_COOLDOWN") end
    end
    SyncItems()
end

local function Queue()
    if pending then return end
    pending = true
    C_Timer.After(0, Render)
end
EQT.RefreshCustom = Queue

-------------------------------------------------------------------------------
-- Interaction. Nothing here touches Blizzard's tracker, the watch list, the
-- super-track or the world map (opening it from addon code taints its pins:
-- SetPassThroughButtons blocked in combat, tested 2026-10-17).
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

local function ShowMenu(owner, questID)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(C_QuestLog.GetTitleForQuestID(questID) or "")
        if Cfg("customFocusClick") then
            local focused = C_SuperTrack.GetSuperTrackedQuestID() == questID
            root:CreateButton(focused and STOP_SUPER_TRACK_QUEST or SUPER_TRACK_QUEST,
                function() ToggleFocus(questID) end)
        end
        root:CreateButton(CharDB().ctPinned[questID] and "Unpin" or "Pin to Top",
            function() TogglePin(questID) end)
        root:CreateButton(OBJECTIVES_STOP_TRACKING, function() Untrack(questID) end)
        if IsInGroup() and C_QuestLog.IsPushableQuest(questID) then
            root:CreateButton(SHARE_QUEST, function()
                QuestLogPushQuest(C_QuestLog.GetLogIndexForQuestID(questID))
            end)
        end
        root:CreateButton(ABANDON_QUEST_ABBREV, function() Abandon(questID) end)
    end)
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
        if Cfg("customCollapseCompleted") and C_QuestLog.IsComplete(id) then
            local open = CharDB().ctDoneOpen
            open[id] = not open[id] or nil
            Queue()
        else
            ToggleCollapsed(id)
        end
    end
end

-- One icon line per reward; Blizzard's tooltip helper shows one item, no choices.
-- Uncached items redraw the tooltip once loaded, if owner still holds it.
local function AddRewardLine(name, texture, count, quality, itemID, owner)
    if not name then
        local item = itemID and Item:CreateFromItemID(itemID)
        if item and not item:IsItemEmpty() and not item:IsItemDataCached() then
            item:ContinueOnItemLoad(function()
                if GameTooltip:IsOwned(owner) then OnLineEnter(owner) end
            end)
        end
        return
    end
    local text = count and count > 1
        and BONUS_OBJECTIVE_REWARD_WITH_COUNT_FORMAT:format(texture, HIGHLIGHT_FONT_COLOR:WrapTextInColorCode(count), name)
        or BONUS_OBJECTIVE_REWARD_FORMAT:format(texture, name)
    local c = quality and ColorManager.GetColorDataForItemQuality(quality)
    if c then GameTooltip:AddLine(text, c.r, c.g, c.b) else GameTooltip:AddLine(text, 1, 1, 1) end
end

local function AddRewards(questID, owner)
    if not C_QuestLog.ShouldShowQuestRewards(questID) then return end
    local xp = GetQuestLogRewardXP(questID)
    local money = GetQuestLogRewardMoney(questID)
    local currencies = C_QuestLog.GetQuestRewardCurrencies(questID)
    local numItems = GetNumQuestLogRewards(questID)
    local numChoices = GetNumQuestLogChoices(questID)
    if xp <= 0 and money <= 0 and #currencies == 0 and numItems == 0 and numChoices == 0 then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(QUEST_REWARDS, NORMAL_FONT_COLOR:GetRGB())
    if xp > 0 then GameTooltip:AddLine(BONUS_OBJECTIVE_EXPERIENCE_FORMAT:format(xp), 1, 1, 1) end
    if money > 0 then GameTooltip:AddLine(GetMoneyString(money), 1, 1, 1) end
    for _, cur in ipairs(currencies) do
        AddRewardLine(cur.name, cur.texture, cur.totalRewardAmount, cur.quality)
    end
    for i = 1, numItems do
        local name, texture, count, quality, _, itemID = GetQuestLogRewardInfo(i, questID)
        AddRewardLine(name, texture, count, quality, itemID, owner)
    end
    if numChoices > 0 then
        GameTooltip:AddLine(REWARD_CHOICES, NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b, true)
        for i = 1, numChoices do
            local name, texture, count, quality, _, itemID = GetQuestLogChoiceInfo(i, questID)
            AddRewardLine(name, texture, count, quality, itemID, owner)
        end
    end
end

function OnLineEnter(self)
    UpdateHover()
    if self.kind ~= "quest" then return end
    GameTooltip:SetOwner(self, TooltipSide())
    if IsInGroup() then
        GameTooltip:SetQuestPartyProgress(self.id)
    else
        GameTooltip:SetHyperlink(GetQuestLink(self.id))
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

-- Anchor fractions per point, for re-anchoring a saved position by its top.
local HX = { LEFT = 0, CENTER = 0.5, RIGHT = 1, TOP = 0.5, BOTTOM = 0.5,
             TOPLEFT = 0, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 1 }
local VY = { TOP = 1, CENTER = 0.5, BOTTOM = 0, LEFT = 0.5, RIGHT = 0.5,
             TOPLEFT = 1, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 0 }

-- Same spot, anchored by the frame's top edge so height changes grow down.
-- Unlock mode hands back CENTER points; the current size places the top.
local function TopAnchored(p)
    local point, rel = p.point, p.relPoint or p.point
    if VY[point] == 1 or not (HX[point] and HX[rel]) then return p end
    local px = UIParent:GetWidth() * HX[rel] + (p.x or 0)
    local py = UIParent:GetHeight() * VY[rel] + (p.y or 0)
    return { point = "TOPLEFT", relPoint = "BOTTOMLEFT",
             x = px - frame:GetWidth() * HX[point],
             y = py + frame:GetHeight() * (1 - VY[point]) }
end

local function Place()
    local p = TopAnchored(SavedPos())
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    SyncItems()
end

local function BuildFrame()
    frame = CreateFrame("Frame", "EUI_CustomQuestTracker", UIParent)
    frame:SetFrameStrata("LOW")
    frame:SetWidth(Cfg("customWidth") or 260)
    frame:SetHeight(HEADER_H)
    frame:SetClampedToScreen(Cfg("forceOnScreen") == true)
    frame:SetScript("OnShow", function()
        itemLayer:SetAlpha(frame:GetAlpha())
        if stale then Render() else SyncItems() end
    end)
    -- Alpha first: in combat the hide itself waits for combat to end.
    frame:SetScript("OnHide", function() itemLayer:SetAlpha(0); SyncItems() end)
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

    Place()
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
        return Cfg("hideInRaidMode") == "always" or inEncounter
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
}

evt:SetScript("OnEvent", function(_, event, questID, added)
    if event == "BAG_UPDATE_COOLDOWN" then
        for _, b in ipairs(items) do
            if b:IsShown() then UpdateItemCooldown(b) end
        end
        return
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
        inEncounter = event == "ENCOUNTER_START"
        UpdateVisibility()
    end
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

    for _, e in ipairs(EVENTS) do evt:RegisterEvent(e) end
    EllesmereUI.RegisterVisibilityUpdater(UpdateVisibility)
    EllesmereUI.RegisterMouseoverTarget(frame, function()
        return not Blocked() and EllesmereUI.VisWantsMouseover(EQT.DB(), "visibility")
    end)
    if EllesmereUI.RegAccent then
        EllesmereUI.RegAccent({ type = "callback", fn = EQT.RestyleAll })
    end

    EllesmereUI:RegisterUnlockElements({ EllesmereUI.MakeUnlockElement({
        key      = "EQT_CustomTracker",
        label    = "Quest Tracker",
        getFrame = function() return frame end,
        getSize  = function() return frame:GetWidth(), frame:GetHeight() end,
        setWidth = function(_, w)
            EQT.Set("customWidth", math.max(150, math.floor(w + 0.5)))
            frame:SetWidth(EQT.Cfg("customWidth"))
            Queue()
        end,
        setHeight = function(_, h)
            EQT.Set("customMaxHeight", math.max(HEADER_H * 2, math.floor(h + 0.5)))
            Queue()
        end,
        savePos  = function(_, point, relPoint, x, y)
            if not point then return end
            EQT.Set("customPos", TopAnchored({ point = point, relPoint = relPoint, x = x, y = y }))
            if not EllesmereUI._unlockActive then Place() end
        end,
        loadPos  = SavedPos,
        clearPos = function() EQT.Set("customPos", nil); Place() end,
        applyPos = Place,
    }) }, "EllesmereUIQuestTracker")

    UpdateVisibility()
    Queue()
end
