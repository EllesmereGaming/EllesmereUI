if EUI_CLIENT_BLOCKED then return end
local EUI = EllesmereUI
-- The player swing event and its enum are supplied by the Forever client.
if not (C_SwingTimer and Enum.PlayerSwingType and C_DurationUtil
    and C_DurationUtil.CreateDurationTextBinding and C_StringUtil) then return end

local defaults = { profile = { swingTimer = {
    enabled = false, mainHand = true, offHand = true, ranged = true,
    combatOnly = true, queueColor = true, width = 240, height = 18,
    gap = 4, fontSize = 11, x = 0, y = -220, texture = "none",
} } }
local db, frame, registered, unlocked
local rows = {}
local labels = { "Main Hand", "Off Hand", "Ranged" }
local keys = { "mainHand", "offHand", "ranged" }
local types = { Enum.PlayerSwingType.MainHand, Enum.PlayerSwingType.OffHand,
    Enum.PlayerSwingType.Ranged }
-- Base spell IDs resolve to localized spell names, including ranked casts.
local queuedSpells = { 78, 845, 6807 }
local queuedNames = {}      -- their localized names, resolved once the bars exist
local lastQueued = false    -- the queued name last painted (false = nothing painted yet)
local textures

local function Plain(value)
    return not (issecretvalue and issecretvalue(value))
end

local function Profile()
    if not db then db = EUI.Lite.NewDB("EllesmereUIQoLDB", defaults, true) end
    return db.profile.swingTimer
end

local function Position()
    local p = Profile()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", p.x, p.y)
end

local function SetDuration(row, duration)
    row.duration:SetTimeFromStart(GetTime(), duration)
    row:SetTimerDuration(row.duration, Enum.StatusBarInterpolation.Immediate,
        Enum.StatusBarTimerDirection.RemainingTime)
    row.binding:SetDuration(row.duration)
end

local function Reset()
    for i = 1, #rows do
        local row = rows[i]
        SetDuration(row, 0)
        row.label:SetText(labels[i])
    end
    lastQueued = false
end

-- Paints the delta only: ACTIONBAR_UPDATE_STATE storms through combat, and
-- the queued attack changes on a few of them, so the rows are touched (and
-- their labels built) only when the queued name differs from the last paint.
local function PaintQueue()
    if not frame then return end
    local p = Profile()
    local queuedName
    if p.queueColor and C_Spell and C_Spell.IsCurrentSpell then
        for i = 1, #queuedNames do
            local current = C_Spell.IsCurrentSpell(queuedNames[i])
            if Plain(current) and current then queuedName = queuedNames[i]; break end
        end
    end
    if queuedName == lastQueued then return end
    lastQueued = queuedName
    local accent = EUI.ELLESMERE_GREEN
    for i = 1, #rows do
        local row = rows[i]
        if queuedName and i < 3 then
            row:SetStatusBarColor(1, 0.70, 0.20, 1)
            row.label:SetText(labels[i] .. " - " .. queuedName)
        else
            row:SetStatusBarColor(accent.r, accent.g, accent.b, 1)
            row.label:SetText(labels[i])
        end
    end
end

-- Fonts and the bar texture: settings work, applied from Apply (every
-- options change arrives through it), never from the event path.
local function Style()
    local p = Profile()
    local font = EUI.GetFontPath("qol")
    local tex = EUI.ResolveTexturePath(textures, p.texture, "Interface\\Buttons\\WHITE8x8")
    for i = 1, #rows do
        local row = rows[i]
        row.label:SetFont(font, p.fontSize, "OUTLINE")
        row.text:SetFont(font, p.fontSize, "OUTLINE")
        row:SetStatusBarTexture(tex)
    end
    -- A fresh fill texture carries no colour: the next paint must run.
    lastQueued = false
end

local function Layout()
    if not frame then return end
    local p = Profile()
    local count = 0
    -- This is a player-visibility decision, not a secure-frame mutation gate.
    -- Match Forever's own Swing Timer, which uses the unit combat predicate.
    local visible = p.enabled and (not p.combatOnly or UnitAffectingCombat("player") or unlocked)
    local main, off, ranged = UnitAttackSpeed("player")
    local speeds = { main, off, ranged }
    for i = 1, #rows do
        local row = rows[i]
        local speed = speeds[i]
        if Plain(speed) then row.available = type(speed) == "number" and speed > 0 end
        row:ClearAllPoints()
        row:SetSize(p.width, p.height)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -count * (p.height + p.gap))
        row.label:SetWidth(math.max(1, p.width - 55))
        local show = p[keys[i]] and row.available
        row:SetShown(show)
        if show then
            count = count + 1
            if visible then row.binding:Enable() else row.binding:Disable() end
        else
            row.binding:Disable()
        end
    end
    frame:SetSize(p.width, math.max(p.height, count * (p.height + p.gap) - p.gap))
    frame:SetShown(visible and count > 0)
    PaintQueue()
end

local function OnEvent(_, event, duration, swingType)
    if event == "PLAYER_SWING" then
        -- Never infer an interval from restricted data or another event's timing.
        if not Plain(duration) or not Plain(swingType) then return end
        if type(duration) ~= "number" or duration ~= duration or duration <= 0
            or duration == math.huge then return end
        for i = 1, #rows do
            if swingType == types[i] then
                SetDuration(rows[i], duration)
                break
            end
        end
        PaintQueue()
    elseif event == "ACTIONBAR_UPDATE_STATE" then
        PaintQueue()
    else
        if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_DEAD"
            or event == "WEAPON_SLOT_CHANGED" then Reset() end
        Layout()
    end
end

local function CreateBars()
    if frame then return end
    frame = CreateFrame("Frame", "EUISwingTimer", UIParent)
    frame:Hide()
    frame:SetScript("OnEvent", OnEvent)
    textures = EUI.BuildBarTextureTables()
    local formatter = C_StringUtil.CreateSecondsFormatter()
    for i = 1, #keys do
        local row = CreateFrame("StatusBar", nil, frame)
        row:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        row:SetMinMaxValues(0, 1)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.035, 0.045, 0.055, 0.95)
        EUI.MakeBorder(row, 0, 0, 0, 1)
        row.label = row:CreateFontString(nil, "OVERLAY")
        row.label:SetPoint("LEFT", row, "LEFT", 5, 0)
        row.label:SetJustifyH("LEFT")
        row.text = row:CreateFontString(nil, "OVERLAY")
        row.text:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        row.duration = C_DurationUtil.CreateDuration()
        row.duration:SetTimeFromStart(GetTime(), 0)
        row:SetTimerDuration(row.duration, Enum.StatusBarInterpolation.Immediate,
            Enum.StatusBarTimerDirection.RemainingTime)
        row.binding = C_DurationUtil.CreateDurationTextBinding()
        row.binding:SetFontString(row.text)
        row.binding:SetDuration(row.duration)
        row.binding:SetFormatter(formatter)
        row.binding:SetExpiredText("Ready")
        row.binding:SetZeroDurationText("Ready")
        row.binding:SetUpdateInterval(0.1)
        -- A player always has a main-hand swing. Off-hand and ranged remain
        -- hidden until a readable attack-speed update confirms they are usable.
        row.available = i == 1
        rows[i] = row
    end
    -- Spell names hold for the session: resolved once, never per event.
    for i = 1, #queuedSpells do
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(queuedSpells[i])
        if Plain(name) and name then queuedNames[#queuedNames + 1] = name end
    end
end

local function Apply()
    local p = Profile()
    if not p.enabled then
        if frame then
            frame:UnregisterAllEvents()
            if EUI.UnregisterUnlockModeListener then EUI:UnregisterUnlockModeListener(frame) end
            unlocked = false
            Reset()
            frame:Hide()
            for i = 1, #rows do rows[i].binding:Disable() end
        end
        return
    end
    CreateBars()
    if EUI.RegisterUnlockModeListener then
        EUI:RegisterUnlockModeListener(frame, function(active)
            unlocked = active
            Layout()
        end)
    end
    frame:RegisterEvent("PLAYER_SWING")
    frame:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_DEAD")
    frame:RegisterEvent("WEAPON_SLOT_CHANGED")
    frame:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
    Position()
    Style()
    Layout()
    if not registered then
        registered = true
        EUI:RegisterUnlockElements({ EUI.MakeUnlockElement({
            key = "EUI_SwingTimer", label = "Swing Timer", group = "Quality of Life", order = 650,
            -- Size comes from the page sliders, but Unlock Mode may still match
            -- either dimension to another element through these same settings.
            noResize = true, allowMatchSource = true, noAnchorTarget = true,
            isHidden = function() return not Profile().enabled end,
            getFrame = function() return frame end,
            getSize = function() return frame:GetWidth(), frame:GetHeight() end,
            setWidth = function(_, width)
                local p = Profile()
                local PP = EUI.PP
                width = PP and PP.Snap and PP.Snap(width) or math.floor(width + 0.5)
                p.width = math.max(100, math.min(600, width))
                Layout()
            end,
            setHeight = function(_, height)
                local p = Profile()
                p.height = math.max(12, math.min(40, math.floor(height + 0.5)))
                Layout()
            end,
            savePos = function(_, _, _, x, y)
                local s = Profile()
                local cx, cy = frame:GetCenter()
                local ux, uy = UIParent:GetCenter()
                if cx and ux then s.x = cx - ux; s.y = cy - uy
                else s.x = x; s.y = y end
            end,
            loadPos = function()
                local s = Profile()
                return { point = "CENTER", relPoint = "CENTER", x = s.x, y = s.y }
            end,
            clearPos = function() local s = Profile(); s.x = 0; s.y = -220 end,
            applyPos = Position,
        }) })
    end
end

_G._EUI_Swing_Profile = Profile
_G._EUI_Swing_Apply = Apply
