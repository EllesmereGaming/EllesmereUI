if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_LevelUp.lua  (WoW Forever only)
--  Level Up Toast: on level up, a toast in the loot feed's EUI look (accent
--  bar on a fading dark plate) that completes the game's own level-up toast
--  rather than repeating it: the level in large accent digits, the health,
--  power and stats gained ("Health: +52"), new talent points, what the
--  class trainer teaches at the new level as icons (TrainerData.lua) and,
--  last, the time the last level took. It sits under the game's toast by
--  default and shows with it: a read-only hook on the game's toast display
--  releases it as the game's fades in, with a one-shot fallback should the
--  game's never come.
--  It slides in with an accent sheen, fades out after a while, and hovering
--  holds it. Unlock mode places and sizes it. Show in Chat also writes it
--  to the chat, the abilities as spell links. Everything moves through
--  animation groups on frames of our own.
-------------------------------------------------------------------------------
local _, module = ...

-- Settings live in EllesmereUIDB.levelUpToast; unset keys read these.
-- gains, abilities, time: which parts the toast (and the chat) shows.
local F = module.Feature("levelUpToast", { enabled = false, chat = false, width = 340, duration = 6,
    gains = true, abilities = true, time = true },
    { point = "TOP", relPoint = "TOP", x = 0, y = -340 })
local Get, Enabled = F.Get, F.Enabled

local BAR = 3          -- the accent bar on the left edge
local NUMBER_W = 58    -- the level digits' column
local PAD = 12
local ICON = 26        -- an ability's icon
local ROW_H = 17       -- a stat line
local BASE_H = 64      -- the plate's height before its lines
local TALENT = { 0.78, 0.55, 1 }  -- the talents' color, as in the Training Book
local FADE_IN, FADE_OUT, SLIDE = 0.35, 0.8, 10

-- PLAYER_LEVEL_UP payload: the stat deltas' positions and their names.
local STATS = {
    { 6, "SPELL_STAT1_NAME" },  -- strength
    { 7, "SPELL_STAT2_NAME" },  -- agility
    { 8, "SPELL_STAT3_NAME" },  -- stamina
    { 9, "SPELL_STAT4_NAME" },  -- intellect
}

local anchor, toast, events

local function Accent()
    local c = EllesmereUI.ELLESMERE_GREEN
    if c then return c.r, c.g, c.b end
    return 0.05, 0.82, 0.62
end

local function Font(fs, size)
    EllesmereUI.ApplyModuleFont(fs, nil, size, "essentials")
end

local function Text(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    Font(fs, size)
    return fs
end

-- The mouse is on the toast or one of its icons, not just over its area
-- (a window above it, the options panel, holds no hover).
local function Hovered()
    local focus = GetMouseFoci()[1]
    return focus and (focus == toast or focus:GetParent() == toast)
end

-- Waits Duration, fades out, hides; hovering holds it.
local function ArmFade()
    if toast.show:IsPlaying() then return end
    toast.fade:Stop()
    toast:SetAlpha(1)
    if not Hovered() then toast.fade:Play() end
end

-- An ability's tooltip: the spell's own.
local function AbilityEnter(b)
    toast.fade:Stop()
    toast:SetAlpha(1)
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetSpellByID(b.spellID)
    GameTooltip:Show()
end

local function AbilityLeave(b)
    if GameTooltip:IsOwned(b) then GameTooltip:Hide() end
    ArmFade()
end

local function AbilityIcon(i)
    local b = toast.icons[i]
    if b then return b end
    b = CreateFrame("Frame", nil, toast)
    b:SetSize(ICON, ICON)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    EllesmereUI.PP.CreateBorder(b, 0, 0, 0, 1, 1, "OVERLAY", 1)
    b:EnableMouseMotion(true)
    b:SetScript("OnEnter", AbilityEnter)
    b:SetScript("OnLeave", AbilityLeave)
    toast.icons[i] = b
    return b
end

-- A stat line of the two-column list.
local function Cell(i)
    local fs = toast.cells[i]
    if not fs then
        fs = Text(toast, 12)
        toast.cells[i] = fs
    end
    return fs
end

local function Anim(g, kind, order, secs, smoothing)
    local a = g:CreateAnimation(kind)
    a:SetOrder(order)
    a:SetDuration(secs)
    if smoothing then a:SetSmoothing(smoothing) end
    return a
end

-- The accent follows the theme: painted again at each show.
local function Paint()
    local r, g, b = Accent()
    toast.bar:SetColorTexture(r, g, b, 1)
    toast.rule:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.9), CreateColor(r, g, b, 0))
    toast.sheen:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.35))
    toast.number:SetTextColor(r, g, b)
    toast.levelLabel:SetTextColor(r, g, b, 0.8)
end

local function ApplyStyle()
    if not anchor then return end
    anchor:SetSize(Get("width"), BASE_H)
    toast:SetWidth(Get("width"))
end

local function Build()
    if anchor then return end
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetFrameStrata("MEDIUM")
    F.Place(anchor)

    -- The plate hangs from the anchor's top and grows down with its lines.
    toast = CreateFrame("Frame", nil, anchor)
    toast:SetPoint("TOP")
    toast:SetClipsChildren(true)
    toast:Hide()
    local bg = toast:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 1)
    bg:SetGradient("HORIZONTAL", CreateColor(0.05, 0.05, 0.05, 0.92), CreateColor(0.05, 0.05, 0.05, 0.35))
    toast.bar = toast:CreateTexture(nil, "ARTWORK")
    toast.bar:SetPoint("TOPLEFT")
    toast.bar:SetPoint("BOTTOMLEFT")
    toast.bar:SetWidth(BAR)
    toast.rule = toast:CreateTexture(nil, "ARTWORK")
    toast.rule:SetColorTexture(1, 1, 1, 1)
    toast.rule:SetPoint("TOPLEFT", BAR, 0)
    toast.rule:SetPoint("TOPRIGHT")
    toast.rule:SetHeight(1)
    -- The sheen sweeps across once as the toast comes in.
    toast.sheen = toast:CreateTexture(nil, "ARTWORK", nil, 1)
    toast.sheen:SetColorTexture(1, 1, 1, 1)
    toast.sheen:SetPoint("TOPRIGHT", toast, "TOPLEFT")
    toast.sheen:SetPoint("BOTTOMRIGHT", toast, "BOTTOMLEFT")
    toast.sheen:SetWidth(80)
    toast.sheen:SetBlendMode("ADD")

    -- "Lvl" over the level, in the left column.
    toast.levelLabel = toast:CreateFontString(nil, "OVERLAY")
    Font(toast.levelLabel, 11)
    toast.levelLabel:SetJustifyH("CENTER")
    toast.levelLabel:SetPoint("TOPLEFT", BAR, -PAD)
    toast.levelLabel:SetWidth(NUMBER_W)
    toast.levelLabel:SetText(EllesmereUI.L("Lvl"))
    toast.number = toast:CreateFontString(nil, "OVERLAY")
    Font(toast.number, 30)
    toast.number:SetJustifyH("CENTER")
    toast.number:SetPoint("TOP", toast.levelLabel, "BOTTOM", 0, -1)
    toast.number:SetWidth(NUMBER_W)
    toast.cells, toast.icons = {}, {}
    toast.talents = Text(toast, 12)
    toast.learn = Text(toast, 12)
    toast.learn:SetTextColor(1, 1, 1)
    toast.talentList = Text(toast, 12)
    toast.talentList:SetTextColor(TALENT[1], TALENT[2], TALENT[3])
    toast.time = Text(toast, 11)
    toast.time:SetTextColor(0.7, 0.7, 0.7)

    toast:EnableMouseMotion(true)
    toast:SetScript("OnEnter", function()
        if not toast.show:IsPlaying() then
            toast.fade:Stop()
            toast:SetAlpha(1)
        end
    end)
    toast:SetScript("OnLeave", ArmFade)

    -- In: up SLIDE px at once, then down into place while it fades in.
    toast.show = toast:CreateAnimationGroup()
    Anim(toast.show, "Translation", 1, 0):SetOffset(0, SLIDE)
    local drop = Anim(toast.show, "Translation", 2, FADE_IN, "OUT")
    drop:SetOffset(0, -SLIDE)
    local appear = Anim(toast.show, "Alpha", 2, FADE_IN, "OUT")
    appear:SetFromAlpha(0)
    appear:SetToAlpha(1)
    toast.show:SetScript("OnFinished", ArmFade)
    toast.sweep = toast.sheen:CreateAnimationGroup()
    toast.sweep.move = Anim(toast.sweep, "Translation", 1, 0.9, "IN_OUT")
    toast.sweep:SetScript("OnFinished", function() toast.sheen:Hide() end)
    toast.fade = toast:CreateAnimationGroup()
    toast.fade.alpha = Anim(toast.fade, "Alpha", 1, FADE_OUT, "IN_OUT")
    toast.fade.alpha:SetFromAlpha(1)
    toast.fade.alpha:SetToAlpha(0)
    toast.fade:SetScript("OnFinished", function() toast:Hide() end)
    ApplyStyle()
end

-- What the class trainer teaches up to level and the player does not know
-- yet, the new level's first, from the trainer data (TrainerData.lua):
-- neither the game's level-up display nor Forever's spellbook lists it. A
-- talent's own spell comes with the talent and a higher rank is taught only to
-- a player who has the talent: those the player lacks are the second list,
-- the new level's alone. only: that level's alone (the sample).
local function LevelAbilities(level, only)
    local out, talents = {}, {}
    local _, class = UnitClass("player")
    local data = module.TrainerSpells(class)
    for l = level, only and level or 1, -1 do
        local spells = data[l] or {}
        for i = 1, #spells do
            local id = spells[i]
            if not IsPlayerSpell(id) then
                local entry = { icon = C_Spell.GetSpellTexture(id), spellID = id }
                if not module.SpellIsTalent(class, id) or module.TalentRankOpen(class, id) then
                    out[#out + 1] = entry
                elseif l == level then
                    talents[#talents + 1] = entry
                end
            end
        end
    end
    return out, talents
end

-- The toast's lines in the chat.
local function ToChat(level, timeLevel, timeSecs, stats, talents, abilities, talentSpells, hex)
    local brand = EllesmereUI.COLOR_CODES.BRAND .. "EllesmereUI:|r "
    local parts = {}
    for i = 1, #stats do
        parts[#parts + 1] = EllesmereUI.Lf("%1$s: %2$s", stats[i][1], ("%s+%d|r"):format(hex, stats[i][2]))
    end
    if talents > 0 then
        parts[#parts + 1] = EllesmereUI.Lf("%1$s: %2$s", EllesmereUI.L("Talent points"), ("%s+%d|r"):format(hex, talents))
    end
    EllesmereUI.Print(brand .. hex .. EllesmereUI.Lf("Level %d", level) .. "|r  " .. table.concat(parts, ", "))
    if #abilities > 0 then
        local links = {}
        for i = 1, #abilities do
            links[#links + 1] = C_Spell.GetSpellLink(abilities[i].spellID) or ""
        end
        EllesmereUI.Print(brand .. EllesmereUI.Lf("To learn now (%d):", #abilities) .. " " .. table.concat(links, " "))
    end
    if #talentSpells > 0 then
        local links = {}
        for i = 1, #talentSpells do
            links[#links + 1] = C_Spell.GetSpellLink(talentSpells[i].spellID) or ""
        end
        EllesmereUI.Print(brand .. EllesmereUI.Lf("Talents (%d):", #talentSpells) .. " " .. table.concat(links, " "))
    end
    if timeSecs and SecondsToTime then
        EllesmereUI.Print(brand .. EllesmereUI.Lf("Time at level %d: %s", timeLevel, SecondsToTime(math.floor(timeSecs), true)))
    end
end

-- What the level brought, top to bottom: health, power and stats on two
-- columns ("Health: +52"); talent points; what can be trained now as icons
-- (two rows at most, the count in the label); the time the last level took
-- (timeLevel, timeSecs; nil: not known). sampleOnly: the sample's level alone.
local sampleOnly = false
local MAX_ICON_ROWS = 2

local function Show(level, timeLevel, timeSecs, health, power, talents, ...)
    Build()
    Paint()
    local hex = EllesmereUI.HexColor(Accent())
    local deltas = { ... }
    local stats = {}
    if Get("gains") then
        if health > 0 then stats[#stats + 1] = { HEALTH, health } end
        local _, token = UnitPowerType("player")
        if power > 0 then stats[#stats + 1] = { _G[token] or token, power } end
        for i = 1, #STATS do
            local d = deltas[STATS[i][1] - 5]
            if d and d > 0 then stats[#stats + 1] = { _G[STATS[i][2]], d } end
        end
    else
        talents = 0
    end
    if not Get("time") then timeSecs = nil end

    toast.number:SetText(level)
    local left = BAR + NUMBER_W
    local colW = (Get("width") - left - PAD) / 2
    local y = PAD
    for i = 1, #stats do
        local fs, col = Cell(i), (i - 1) % 2
        fs:SetText(EllesmereUI.Lf("%1$s: %2$s", stats[i][1], ("%s+%d|r"):format(hex, stats[i][2])))
        fs:SetWidth(colW - 6)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", left + col * colW, -(y + math.floor((i - 1) / 2) * ROW_H))
        fs:Show()
    end
    for i = #stats + 1, #toast.cells do toast.cells[i]:Hide() end
    y = y + math.ceil(#stats / 2) * ROW_H

    toast.talents:SetShown(talents > 0)
    if talents > 0 then
        y = y + 2
        toast.talents:SetText(EllesmereUI.Lf("%1$s: %2$s", EllesmereUI.L("Talent points"), ("%s+%d|r"):format(hex, talents)))
        toast.talents:ClearAllPoints()
        toast.talents:SetPoint("TOPLEFT", left, -y)
        y = y + ROW_H
    end

    local abilities, talentSpells = {}, {}
    if Get("abilities") then abilities, talentSpells = LevelAbilities(level, sampleOnly) end
    local perRow = math.max(1, math.floor((Get("width") - left - PAD + 4) / (ICON + 4)))
    local shown = 0
    toast.learn:SetShown(#abilities > 0)
    if #abilities > 0 then
        y = y + 4
        toast.learn:SetText(EllesmereUI.Lf("To learn now (%d):", #abilities))
        toast.learn:ClearAllPoints()
        toast.learn:SetPoint("TOPLEFT", left, -y)
        y = y + ROW_H + 2
        shown = math.min(#abilities, perRow * MAX_ICON_ROWS)
        for i = 1, shown do
            local a, b = abilities[i], AbilityIcon(i)
            b.icon:SetTexture(a.icon)
            b.spellID = a.spellID
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", left + ((i - 1) % perRow) * (ICON + 4), -(y + math.floor((i - 1) / perRow) * (ICON + 4)))
            b:Show()
        end
        y = y + math.ceil(shown / perRow) * (ICON + 4)
    end

    -- The talents of the new level the player does not have, one row at most.
    local shownTalents = 0
    toast.talentList:SetShown(#talentSpells > 0)
    if #talentSpells > 0 then
        y = y + 4
        toast.talentList:SetText(EllesmereUI.Lf("Talents (%d):", #talentSpells))
        toast.talentList:ClearAllPoints()
        toast.talentList:SetPoint("TOPLEFT", left, -y)
        y = y + ROW_H + 2
        shownTalents = math.min(#talentSpells, perRow)
        for i = 1, shownTalents do
            local a, b = talentSpells[i], AbilityIcon(shown + i)
            b.icon:SetTexture(a.icon)
            b.spellID = a.spellID
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", left + (i - 1) * (ICON + 4), -y)
            b:Show()
        end
        y = y + ICON + 4
    end
    for i = shown + shownTalents + 1, #toast.icons do toast.icons[i]:Hide() end

    local showTime = timeSecs and SecondsToTime
    toast.time:SetShown(showTime and true or false)
    if showTime then
        y = y + 4
        toast.time:SetText(EllesmereUI.Lf("Time at level %d: %s", timeLevel, SecondsToTime(math.floor(timeSecs), true)))
        toast.time:ClearAllPoints()
        toast.time:SetPoint("TOPLEFT", left, -y)
        y = y + ROW_H
    end
    toast:SetHeight(math.max(BASE_H, y + PAD))
    if Get("chat") then ToChat(level, timeLevel, timeSecs, stats, talents, abilities, talentSpells, hex) end

    toast.fade.alpha:SetStartDelay(Get("duration"))
    toast.fade:Stop()
    toast:SetAlpha(0)
    toast:Show()
    toast.show:Play()
    toast.sweep.move:SetOffset(Get("width") + 80, 0)
    toast.sheen:Show()
    toast.sweep:Stop()
    toast.sweep:Play()
end

-------------------------------------------------------------------------------
--  Time at a level, per character: chars[player GUID] = { level, seconds, full }.
--  Counted on events only: the session's time goes into the record at logout
--  and level up. full: counted since the level began, or set by the game's
--  own /played (TIME_PLAYED_MSG, never requested here: it prints in chat).
--  While not full, the toast shows no time.
-------------------------------------------------------------------------------
local sessionStart  -- GetTime() the running count started from; nil: not counting

local function Record(create)
    local guid = UnitGUID("player")
    if not guid then return nil end
    local cfg = create and F.Cfg() or F.Read()
    if create then
        cfg.chars = cfg.chars or {}
        cfg.chars[guid] = cfg.chars[guid] or {}
    end
    return cfg.chars and cfg.chars[guid]
end

-- Seconds at a level so far, or nil while not known.
local function LevelSeconds(level)
    local t = Record()
    if not (t and t.full and t.level == level and sessionStart) then return nil end
    return (t.seconds or 0) + (GetTime() - sessionStart)
end

-- A record that is not about this level starts again, not full: its start
-- was not seen.
local function StartCounting()
    sessionStart = GetTime()
    local t, level = Record(true), UnitLevel("player")
    if t.level ~= level then t.level, t.seconds, t.full = level, 0, false end
end

-- Off: the gap will not be counted, so the record stops being full.
local function StopCounting()
    local t = Record()
    if t then t.full = false end
    sessionStart = nil
end

-- The payload after the level: health, power, talents, PvP talent slots, then
-- the stat deltas; Show skips the PvP slots.
local function ShowPayload(level, timeLevel, timeSecs, health, power, talents, _, ...)
    Show(level, timeLevel, timeSecs, health, power, talents, ...)
end

-- A level up waits for the game's level-up toast.
local pending, hooked
local FALLBACK = 8      -- seconds before it shows on its own
local AFTER_GAME = 0.2   -- seconds after the game's toast starts fading in

local function ShowPending()
    local p = pending
    pending = nil
    if p then ShowPayload(unpack(p, 1, p.n)) end
end

-- The game's toast fades in after its show animation's start delay (read,
-- never changed): ours waits as long, once, and a beat more (AFTER_GAME).
local function OnGameToast(manager)
    local shown = pending and manager.currentDisplayingToast
    local info = shown and shown.toastInfo
    if not (info and info.eventType == Enum.EventToastEventType.LevelUp) then return end
    local anim = shown.showAnim and shown.showAnim.anim1
    local p = pending
    C_Timer.After((anim and anim:GetStartDelay() or 0) + AFTER_GAME, function()
        if pending == p then ShowPending() end
    end)
end

local function OnEvent(_, event, ...)
    if event == "PLAYER_LEVEL_UP" then
        local level = ...
        local secs = LevelSeconds(level - 1)
        local t = Record(true)
        t.level, t.seconds, t.full = level, 0, true
        sessionStart = GetTime()
        local p = { level, level - 1, secs, select(2, ...) }
        p.n = select("#", ...) + 2
        pending = p
        if not hooked then
            hooked = true
            hooksecurefunc(EventToastManagerFrame, "DisplayToast", OnGameToast)
        end
        C_Timer.After(FALLBACK, function()
            if pending == p then ShowPending() end
        end)
    elseif event == "TIME_PLAYED_MSG" then
        local _, levelTime = ...
        local t = Record(true)
        t.level, t.seconds, t.full = UnitLevel("player"), levelTime, true
        sessionStart = GetTime()
    elseif event == "PLAYER_LOGOUT" then
        local t = Record()
        if t and sessionStart then t.seconds = (t.seconds or 0) + (GetTime() - sessionStart) end
    end
end

local function Apply()
    if not Enabled() then
        if events then events:UnregisterAllEvents() end
        pending = nil
        if sessionStart then StopCounting() end
        if toast then toast:Hide() end
        return
    end
    Build()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:RegisterEvent("PLAYER_LEVEL_UP")
    events:RegisterEvent("TIME_PLAYED_MSG")
    events:RegisterEvent("PLAYER_LOGOUT")
    if not sessionStart then StartCounting() end
end

-- Options-page entry points.
EllesmereUI._LevelUpToast = {
    Get = Get,
    Cfg = F.Cfg,
    Apply = Apply,
    -- A sample: the last level, with what that level teaches and typical
    -- gains.
    Preview = function()
        local max = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion() or 60
        sampleOnly = true
        Show(max, max - 1, 8040, 52, 38, 1, 1, 0, 2, 1)
        sampleOnly = false
    end,
}

F.Start(Apply, {
    key = "EUI_LevelUpToast", label = "Level Up Toast", order = 733, minWidth = 280,
    frame = function(build)
        if build then Build() end
        return anchor
    end,
    height = function() return BASE_H end,
    applyStyle = ApplyStyle,
})
