if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EllesmereUIQoL_CombatTextScroll.lua
-- The scrolling text display Self Combat Text and Target Combat Text share:
-- settings table in the QoL profile, font and animation settings, message
-- pool, stagger and the unlock mode element. Each feature keeps its own events.
--
-- ns.NewCombatTextScroll(spec) returns an inert object; nothing is created
-- until :Build(). spec: dbKey (QoL profile field), defaults, unlockKey, label,
-- order, place(anchor) (position while nothing is saved).
-- Values reach only C formatters and FontString setters, so secret amounts
-- pass through untouched. Messages scroll on engine animation groups.
-------------------------------------------------------------------------------
local _, ns = ...
local EllesmereUI = _G.EllesmereUI
-- WoW Forever: no number under 10,000 abbreviates (EllesmereUI_NumberFormat.lua)
local AbbreviateNumbers = (EllesmereUI.IS_FOREVER and EllesmereUI.ForeverAbbreviateNumbers) or AbbreviateNumbers

local POOL_SIZE  = 12
local FADE_FRAC  = 0.3   -- fade over the last 30% of the scroll
local BOX_W, BOX_H = 200, 30
local LINE_H   = 1.15    -- a message's line height per point of font size
local LINE_GAP = 2       -- px kept between staggered messages

-- Fountain arc: quarter circle of radius 1, x toward the side, y along the scroll
local ARC = { { 0.134, 0.5 }, { 0.5, 0.866 }, { 1, 1 } }

local db
-- The QoL profile (the shared EllesmereUIQoLDB; no defaults are merged in:
-- Get falls back to the feature's defaults).
local function Profile()
    if not db then db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB") end
    return db.profile
end

local Scroll = {}
Scroll.__index = Scroll

function Scroll:Get(k)
    local t = Profile()[self.spec.dbKey]
    local v = t and t[k]
    if v == nil then return self.spec.defaults[k] end
    return v
end

function Scroll:Settings()
    local p, key = Profile(), self.spec.dbKey
    local t = p[key]
    if not t then t = {}; p[key] = t end
    return t
end

-- Every setting back to its default, the anchor link dropped.
function Scroll:ResetSettings()
    Profile()[self.spec.dbKey] = nil
    if EllesmereUIDB.unlockAnchors then EllesmereUIDB.unlockAnchors[self.spec.unlockKey] = nil end
end

-- The settings both features share, into self.S. The font follows the
-- settings only: a global or QoL font change asks for a reload.
function Scroll:ReadStyle()
    local S = self.S
    local key = self:Get("font")
    if key == "__global" then
        S.font = EllesmereUI.GetFontPath("extras")
    elseif key ~= "__combat" then
        S.font = EllesmereUI.ResolveFontName(key)
    else
        local f = _G.CombatTextFont
        S.font = f and f:GetFont() or STANDARD_TEXT_FONT
    end
    local outline = self:Get("outline")
    S.flags = (outline == "OUTLINE" and EllesmereUI.SlugFlag("OUTLINE, SLUG"))
        or (outline == "THICKOUTLINE" and EllesmereUI.SlugFlag("THICKOUTLINE, SLUG")) or ""
    S.shadow = self:Get("shadow") == true
    S.size = self:Get("size")
    S.critSize = S.size * self:Get("critScale")
    S.fontVer = S.fontVer + 1
    S.anim, S.rise, S.duration = self:Get("anim"), self:Get("rise"), self:Get("duration")
    S.dy = self:Get("direction") == "down" and -S.rise or S.rise
    S.stagger, S.abbreviate = self:Get("stagger"), self:Get("abbreviate")
end

-------------------------------------------------------------------------------
--  Position (unlock mode owns it once saved)
-------------------------------------------------------------------------------
function Scroll:ApplyPos()
    local anchor = self.anchor
    if not anchor then return end
    local pos = self:Get("pos")
    anchor:ClearAllPoints()
    if pos then
        anchor:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x, pos.y)
        return
    end
    self.spec.place(anchor)
end

local function RegisterMover(self)
    local spec = self.spec
    EllesmereUI:RegisterUnlockElements({ EllesmereUI.MakeUnlockElement({
        key = spec.unlockKey, label = spec.label, group = "Quality of Life", order = spec.order,
        noResize = true,
        isHidden = function() return self:Get("enabled") ~= true end,
        getFrame = function() return self.active and self.anchor or nil end,
        getSize  = function() return BOX_W, BOX_H end,
        savePos = function(_, point, relPoint, x, y)
            if not point then return end
            self:Settings().pos = { point = point, relPoint = relPoint or point, x = x, y = y }
            if not EllesmereUI._unlockActive then self:ApplyPos() end
        end,
        loadPos = function()
            local pos = self:Get("pos")
            if not pos then return nil end
            return { point = pos.point, relPoint = pos.relPoint or pos.point, x = pos.x, y = pos.y }
        end,
        clearPos = function()
            local t = Profile()[spec.dbKey]
            if t then t.pos = nil end
            self:ApplyPos()
        end,
        applyPos = function() self:ApplyPos() end,
    }) }, "EllesmereUIQoL")
end

-------------------------------------------------------------------------------
--  Message pool
-------------------------------------------------------------------------------
function Scroll:ApplyAnim()
    local S, pool = self.S, self.pool
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

function Scroll:Build()
    local anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(BOX_W, BOX_H)
    anchor:SetFrameStrata("HIGH")
    self.anchor = anchor
    local pool = self.pool
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
    self:ApplyPos()
    RegisterMover(self)
end

-- Stops every message (a new target's hits must not scroll on the last one's).
function Scroll:ClearAll()
    local pool = self.pool
    for i = 1, #pool do
        local fs = pool[i]
        fs.ag:Stop()
        fs:Hide()
        fs.live = nil
    end
end

-- How far along its scroll a message is at `now`, as a fraction of the
-- distance: linear for Straight, the arc's height for Fountain (its control
-- points are evenly spaced in time), none for Static.
local function Travel(S, m, now)
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
local function ClearLane(self, lane, h)
    local S, pool = self.S, self.pool
    local now, dur, dy = GetTime(), S.duration, S.dy
    local s = dy < 0 and -1 or 1
    local near, nearD
    for i = 1, POOL_SIZE do
        local m = pool[i]
        if m.live and m.lane == lane and now - m.t0 < dur then
            local d = s * (m.y0 + dy * Travel(S, m, now))
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
            m:SetPoint("BOTTOM", self.anchor, "BOTTOM", 0, m.y0)
        end
    end
end

-- Round-robin pool: a burst past POOL_SIZE restarts the oldest message.
-- pt: the font size; `label` is an optional, never secret, second format argument.
function Scroll:Emit(fmt, value, c, pt, label)
    local S = self.S
    self.nextIdx = self.nextIdx % POOL_SIZE + 1
    local fs = self.pool[self.nextIdx]
    fs.ag:Stop()
    fs.live = nil
    local lane = 0
    if S.anim == "fountain" then
        -- Alternate sides, like Blizzard's fountain
        local xDir = -self.xDir
        self.xDir, lane = xDir, xDir
        local rise, sy = S.rise, S.dy
        for j = 1, #ARC do
            fs.cps[j]:SetOffset(xDir * ARC[j][1] * rise, ARC[j][2] * sy)
        end
    end
    local h = pt * LINE_H
    if S.stagger then ClearLane(self, lane, h) end
    fs.t0, fs.y0, fs.h, fs.lane, fs.live = GetTime(), 0, h, lane, true
    fs:ClearAllPoints()
    fs:SetPoint("BOTTOM", self.anchor, "BOTTOM", 0, 0)
    -- A pooled string's font changes only with the settings or its size.
    if fs.fontVer ~= S.fontVer or fs.fontPt ~= pt then
        fs.fontVer, fs.fontPt = S.fontVer, pt
        EllesmereUI.PrimeFontShadow(fs, S.shadow)
        fs:SetFont(S.font, pt, S.flags)
    end
    fs:SetTextColor(c.r, c.g, c.b)
    if label then
        fs:SetFormattedText(fmt, value, label)
    else
        fs:SetFormattedText(fmt, value)
    end
    fs:SetAlpha(1)
    fs:Show()
    fs.ag:Play()
end

-- Both formatters are C-side and accept secret numbers
function Scroll:FormatAmount(n)
    if self.S.abbreviate then return AbbreviateNumbers(n) end
    return BreakUpLargeNumbers(n)
end

function ns.NewCombatTextScroll(spec)
    return setmetatable({
        spec = spec, S = { fontVer = 0 }, pool = {}, nextIdx = 0, xDir = 1, active = false,
    }, Scroll)
end
