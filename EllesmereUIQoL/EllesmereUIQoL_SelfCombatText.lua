if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EllesmereUIQoL_SelfCombatText.lua
-- Self combat text (damage taken, heals received, avoids, combat enter/leave)
-- drawn above the player frame in place of Blizzard's WorldFrame-pinned
-- scrolling text.
--
-- Blizzard's CombatText frame is only hidden, never written to: its OnEvent
-- bails while hidden. Event data from C_CombatText.GetCurrentEventInfo is
-- secret, so values only reach C formatters and FontString setters; nothing
-- here compares or does arithmetic on them. Messages scroll on engine
-- animation groups (no OnUpdate). Off, nothing is created or registered.
--
-- Settings: the QoL profile's selfCombatText table, read into a cache by
-- Refresh. Login (EllesmereUIQoL.lua), profile swaps (RefreshAllAddons) and
-- option changes all route through Refresh. The anchor box is an unlock mode
-- element (EUI_SelfCombatText): unlock mode applies saved positions and
-- anchor links; with nothing saved it sits above the player frame.
-------------------------------------------------------------------------------
local _, ns = ...
local EllesmereUI = _G.EllesmereUI
-- WoW Forever: no number under 10,000 abbreviates (EllesmereUI_NumberFormat.lua)
local AbbreviateNumbers = (EllesmereUI.IS_FOREVER and EllesmereUI.ForeverAbbreviateNumbers) or AbbreviateNumbers

local POOL_SIZE  = 12
local FADE_FRAC  = 0.3   -- fade over the last 30% of the scroll
local UNLOCK_KEY = "EUI_SelfCombatText"
local BOX_W, BOX_H = 200, 30
local LINE_H   = 1.15    -- a message's line height per point of font size
local LINE_GAP = 2       -- px kept between staggered messages

local DEFAULTS = {
    enabled = false,
    size = 16, critScale = 1.5, rise = 80, duration = 1.9,
    stagger = true,
    anim = "straight",     -- straight | fountain | static
    direction = "up",      -- up | down
    font = "__combat",     -- __combat (CombatTextFont), __global (QoL font) or a font key
    outline = "OUTLINE",   -- NONE | OUTLINE | THICKOUTLINE
    shadow = false,
    abbreviate = false,
    damage = true, heal = true, avoid = true, combat = true,
    damageColor = { r = 1,   g = 0.1, b = 0.1 },
    healColor   = { r = 0.1, g = 1,   b = 0.1 },
    avoidColor  = { r = 1,   g = 1,   b = 1   },
    combatColor = { r = 1,   g = 0.1, b = 0.1 },
}

-- type -> isCrit
local DAMAGE = {
    DAMAGE = false, SPELL_DAMAGE = false, DAMAGE_SHIELD = false,
    DAMAGE_CRIT = true, SPELL_DAMAGE_CRIT = true,
}
local HEAL = {
    HEAL = false, PERIODIC_HEAL = false,
    HEAL_CRIT = true, PERIODIC_HEAL_CRIT = true,
}
-- Avoid types; Build fills avoidLabel with their COMBAT_TEXT_* strings.
local AVOID = {
    "MISS", "DODGE", "PARRY", "EVADE", "IMMUNE", "DEFLECT", "REFLECT", "RESIST", "BLOCK", "ABSORB",
}
local avoidLabel = {}

-- Fountain arc: quarter circle of radius 1, x toward the side, y along the scroll
local ARC = { { 0.134, 0.5 }, { 0.5, 0.866 }, { 1, 1 } }

local anchor, ev, db
local pool = {}
local nextIdx = 0
local enabled = false
local xDir = 1
-- Settings as the message path reads them, refilled by Refresh. fontVer tells
-- a pooled string its font is stale.
local S = { fontVer = 0 }

-- The QoL profile (the shared EllesmereUIQoLDB; no defaults are merged in:
-- Get falls back to DEFAULTS).
local function Profile()
    if not db then db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB") end
    return db.profile
end

local function Get(k)
    local t = Profile().selfCombatText
    local v = t and t[k]
    if v == nil then return DEFAULTS[k] end
    return v
end

local function Settings()
    local p = Profile()
    local t = p.selfCombatText
    if not t then t = {}; p.selfCombatText = t end
    return t
end

local function Enabled()
    return Get("enabled") == true
end

-- The font follows the settings only: a global or QoL font change asks for a
-- reload, so nothing else invalidates it.
local function ReadSettings()
    local key = Get("font")
    if key == "__global" then
        S.font = EllesmereUI.GetFontPath("extras")
    elseif key ~= "__combat" then
        S.font = EllesmereUI.ResolveFontName(key)
    else
        local f = _G.CombatTextFont
        S.font = f and f:GetFont() or STANDARD_TEXT_FONT
    end
    local outline = Get("outline")
    S.flags = (outline == "OUTLINE" and EllesmereUI.SlugFlag("OUTLINE, SLUG"))
        or (outline == "THICKOUTLINE" and EllesmereUI.SlugFlag("THICKOUTLINE, SLUG")) or ""
    S.shadow = Get("shadow") == true
    S.size = Get("size")
    S.critSize = S.size * Get("critScale")
    S.fontVer = S.fontVer + 1
    S.anim, S.rise, S.duration = Get("anim"), Get("rise"), Get("duration")
    S.dy = Get("direction") == "down" and -S.rise or S.rise
    S.stagger, S.abbreviate = Get("stagger"), Get("abbreviate")
    S.damage, S.heal, S.avoid, S.combat = Get("damage"), Get("heal"), Get("avoid"), Get("combat")
    S.damageColor, S.healColor = Get("damageColor"), Get("healColor")
    S.avoidColor, S.combatColor = Get("avoidColor"), Get("combatColor")
end

-------------------------------------------------------------------------------
--  Position (unlock mode owns it once saved)
-------------------------------------------------------------------------------
local function ApplyPos()
    if not anchor then return end
    local pos = Get("pos")
    anchor:ClearAllPoints()
    if pos then
        anchor:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
        return
    end
    local pf = _G.EllesmereUIUnitFrames_Player
    if pf then
        anchor:SetPoint("BOTTOM", pf, "TOP", 0, 10)
    else
        anchor:SetPoint("BOTTOM", UIParent, "CENTER", 0, -140)
    end
end

local function RegisterMover()
    EllesmereUI:RegisterUnlockElements({ EllesmereUI.MakeUnlockElement({
        key = UNLOCK_KEY, label = "Self Combat Text", group = "Quality of Life", order = 730,
        noResize = true,
        isHidden = function() return not Enabled() end,
        getFrame = function() return enabled and anchor or nil end,
        getSize  = function() return BOX_W, BOX_H end,
        savePos = function(_, point, relPoint, x, y)
            if not point then return end
            Settings().pos = { point = point, relPoint = relPoint or point, x = x, y = y }
            if not EllesmereUI._unlockActive then ApplyPos() end
        end,
        loadPos = function()
            local pos = Get("pos")
            if not pos then return nil end
            return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
        end,
        clearPos = function()
            local t = Profile().selfCombatText
            if t then t.pos = nil end
            ApplyPos()
        end,
        applyPos = ApplyPos,
    }) }, "EllesmereUIQoL")
end

-------------------------------------------------------------------------------
--  Message pool
-------------------------------------------------------------------------------
local function ApplyAnim()
    local dur, mode = S.duration, S.anim
    for i = 1, POOL_SIZE do
        local fs = pool[i]
        fs.mv:SetOffset(0, mode == "straight" and S.dy or 0)
        fs.mv:SetDuration(dur)
        fs.path:SetDuration(dur)
        if mode ~= "fountain" then
            for j = 1, #ARC do fs.cps[j]:SetOffset(0, 0) end
        end
        fs.fade:SetStartDelay(dur * (1 - FADE_FRAC))
        fs.fade:SetDuration(dur * FADE_FRAC)
    end
end

local function Build()
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(BOX_W, BOX_H)
    anchor:SetFrameStrata("HIGH")
    for i = 1, POOL_SIZE do
        local fs = anchor:CreateFontString(nil, "OVERLAY")
        fs:Hide()
        local ag = fs:CreateAnimationGroup()
        fs.mv = ag:CreateAnimation("Translation")
        fs.path = ag:CreateAnimation("Path")
        fs.path:SetCurveType("SMOOTH")
        fs.cps = {}
        for j = 1, #ARC do
            fs.cps[j] = fs.path:CreateControlPoint(nil, nil, j)
        end
        fs.fade = ag:CreateAnimation("Alpha")
        fs.fade:SetFromAlpha(1)
        fs.fade:SetToAlpha(0)
        ag:SetScript("OnFinished", function() fs:Hide(); fs.live = nil end)
        fs.ag = ag
        pool[i] = fs
    end
    -- The plain and SPELL_ forms of an avoid share Blizzard's label.
    for i = 1, #AVOID do
        local t = AVOID[i]
        local label = _G["COMBAT_TEXT_" .. t]
        avoidLabel[t], avoidLabel["SPELL_" .. t] = label, label
    end
    ev = CreateFrame("Frame")
    ApplyPos()
    RegisterMover()
end

-- How far along its scroll a message is at `now`, as a fraction of the
-- distance: linear for Straight, the arc's height for Fountain (its control
-- points are evenly spaced in time), none for Static.
local function Travel(m, now)
    local mode = S.anim
    if mode == "static" then return 0 end
    local f = (now - m.t0) / S.duration
    if f > 1 then f = 1 end
    if mode ~= "fountain" then return f end
    local seg = f * #ARC
    local i = math.floor(seg)
    if i >= #ARC then return ARC[#ARC][2] end
    local from = i > 0 and ARC[i][2] or 0
    return from + (ARC[i + 1][2] - from) * (seg - i)
end

-- Stagger Hits: before a message of line height h starts at the anchor, push
-- its lane's live messages (the whole stream, or one side of the fountain) on
-- along the scroll until the one nearest the anchor sits clear of it. They all
-- move together, so the spacing holds, and the newest always starts at the
-- anchor; Static stacks the same way.
local function ClearLane(lane, h)
    local now, dur, dy = GetTime(), S.duration, S.dy
    local s = dy < 0 and -1 or 1
    local near, nearD
    for i = 1, POOL_SIZE do
        local m = pool[i]
        if m.live and m.lane == lane and now - m.t0 < dur then
            local d = s * (m.y0 + dy * Travel(m, now))
            if not nearD or d < nearD then near, nearD = m, d end
        end
    end
    if not near then return end
    -- Scrolling up, the new message's top must clear the nearest one's bottom;
    -- scrolling down, the nearest one's top must clear the anchor.
    local need = (s > 0 and h or near.h) + LINE_GAP - nearD
    if need <= 0 then return end
    local shift = s * need
    for i = 1, POOL_SIZE do
        local m = pool[i]
        if m.live and m.lane == lane and now - m.t0 < dur then
            m.y0 = m.y0 + shift
            m:SetPoint("BOTTOM", anchor, "BOTTOM", 0, m.y0)
        end
    end
end

-- Round-robin pool: a burst past POOL_SIZE restarts the oldest message.
local function Emit(fmt, value, c, crit)
    nextIdx = nextIdx % POOL_SIZE + 1
    local fs = pool[nextIdx]
    fs.ag:Stop()
    fs.live = nil
    local lane = 0
    if S.anim == "fountain" then
        -- Alternate sides, like Blizzard's fountain
        xDir = -xDir
        lane = xDir
        local rise, sy = S.rise, S.dy
        for j = 1, #ARC do
            fs.cps[j]:SetOffset(xDir * ARC[j][1] * rise, ARC[j][2] * sy)
        end
    end
    local h = (crit and S.critSize or S.size) * LINE_H
    if S.stagger then ClearLane(lane, h) end
    fs.t0, fs.y0, fs.h, fs.lane, fs.live = GetTime(), 0, h, lane, true
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOM", anchor, "BOTTOM", 0, 0)
    -- A pooled string's font changes only with the settings or between a hit
    -- and a crit.
    local kind = crit and 2 or 1
    if fs.fontVer ~= S.fontVer or fs.fontKind ~= kind then
        fs.fontVer, fs.fontKind = S.fontVer, kind
        EllesmereUI.PrimeFontShadow(fs, S.shadow)
        fs:SetFont(S.font, crit and S.critSize or S.size, S.flags)
    end
    fs:SetTextColor(c.r, c.g, c.b)
    fs:SetFormattedText(fmt, value)
    fs:SetAlpha(1)
    fs:Show()
    fs.ag:Play()
end

-- Both formatters are C-side and accept secret numbers
local function FormatAmount(n)
    if S.abbreviate then return AbbreviateNumbers(n) end
    return BreakUpLargeNumbers(n)
end

local function SetUnit()
    C_CombatText.SetActiveUnit(UnitHasVehicleUI("player") and "vehicle" or "player")
end

local function OnEvent(_, event, arg1, arg2)
    if event == "COMBAT_TEXT_UPDATE" then
        -- data = amount (damage) or source name (heals); arg3 = heal amount
        local crit = DAMAGE[arg1]
        if crit ~= nil then
            if not S.damage then return end
            local data = C_CombatText.GetCurrentEventInfo()
            Emit("-%s", FormatAmount(data), S.damageColor, crit)
            return
        end
        crit = HEAL[arg1]
        if crit ~= nil then
            if not S.heal then return end
            local _, arg3 = C_CombatText.GetCurrentEventInfo()
            Emit("+%s", FormatAmount(arg3), S.healColor, crit)
            return
        end
        local label = S.avoid and avoidLabel[arg1]
        if label then Emit("%s", label, S.avoidColor, false) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        Emit("%s", _G.ENTERING_COMBAT or "+Combat", S.combatColor, false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        Emit("%s", _G.LEAVING_COMBAT or "-Combat", S.combatColor, false)
    elseif event == "UNIT_ENTERED_VEHICLE" then
        C_CombatText.SetActiveUnit(arg2 and "vehicle" or "player")
    elseif event == "UNIT_EXITING_VEHICLE" then
        C_CombatText.SetActiveUnit("player")
    elseif event == "ADDON_LOADED" then
        if arg1 == "Blizzard_CombatText" and _G.CombatText then
            _G.CombatText:Hide()
            ev:UnregisterEvent("ADDON_LOADED")
        end
    end
end

-- Registers only the events the enabled categories need.
local function UpdateEvents()
    if S.damage or S.heal or S.avoid then
        ev:RegisterEvent("COMBAT_TEXT_UPDATE")
        ev:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        ev:RegisterUnitEvent("UNIT_EXITING_VEHICLE", "player")
    else
        ev:UnregisterEvent("COMBAT_TEXT_UPDATE")
        ev:UnregisterEvent("UNIT_ENTERED_VEHICLE")
        ev:UnregisterEvent("UNIT_EXITING_VEHICLE")
    end
    if S.combat then
        ev:RegisterEvent("PLAYER_REGEN_DISABLED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ev:UnregisterEvent("PLAYER_REGEN_DISABLED")
        ev:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end

local function Refresh()
    local want = Enabled()
    if want == enabled then
        if want then
            ReadSettings()
            ApplyAnim()
            UpdateEvents()
        end
        return
    end
    enabled = want
    if want then
        if not anchor then Build() end
        ReadSettings()
        ApplyAnim()
        anchor:Show()
        ev:SetScript("OnEvent", OnEvent)
        UpdateEvents()
        SetUnit()
        if _G.CombatText then
            _G.CombatText:Hide()
        else
            ev:RegisterEvent("ADDON_LOADED")
        end
    else
        ev:UnregisterAllEvents()
        anchor:Hide()
        if _G.CombatText then _G.CombatText:Show() end
    end
end

ns.SCT_Refresh = Refresh
ns.SCT_Get = Get
EllesmereUI._applySelfCombatText = Refresh  -- RefreshAllAddons (profile swaps)

function ns.SCT_Set(k, v)
    Settings()[k] = v
    Refresh()
end

-- QoL page reset: every setting back to its default, the anchor link dropped.
function ns.SCT_Reset()
    Profile().selfCombatText = nil
    if EllesmereUIDB.unlockAnchors then EllesmereUIDB.unlockAnchors[UNLOCK_KEY] = nil end
    Refresh()
    ApplyPos()
end
