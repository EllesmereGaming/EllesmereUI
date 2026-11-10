-- Stub harness: the Debuff Manager's tooltip-modifier eater ("Shown on
-- Modifier") stays on its own unit button.
-- Cuts EnsureEater (and what it calls next to it) from the Raid Frames Debuff
-- Manager file and drives it over a model of frames with rects.
--   the eater is a secure unit button: no part of it may lie outside the unit
--     button it serves, or hover and clicks there act on this unit over empty
--     space (the debuff row pushed outside the frame, web report #243) or
--     over a neighbouring frame
--   a footprint inside the frame is placed exactly as before and still follows
--     the corner of the bar it is pinned to
--   a footprint wholly off the unit makes no eater, and parks one it had
--   before positions can be read the footprint is placed as before, and the
--     next pass measures again
--   in combat nothing is written; an unchanged pass writes nothing
-- The model is this file's reading of the client, not the client.
--   lua .tools/tests/test_rf_tip_eater_on_unit.lua   (from the repository root)
local DM = RF_DM_PATH or "EllesmereUIRaidFrames/EUI_RaidFrames_DebuffManager.lua"

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local function Read(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    if s:sub(1, 3) == "\239\187\191" then s = s:sub(4) end
    return s
end

-- The text from `from` up to (not including) `to`.
local function CutBefore(src, what, from, to)
    local a = assert(src:find(from, 1, true), what .. ": start not found")
    local b = assert(src:find(to, a, true), what .. ": end not found")
    return src:sub(a, b - 1)
end

local SRC = CutBefore(Read(DM), "eater ensure", "local tipEaterCount = 0",
    "-- Per-unit ensure, called from the containers reload loop")

-------------------------------------------------------------------------------
--  The world
-------------------------------------------------------------------------------
local combat = false
local writes = 0
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

local function Share(p)
    local sx, sy = 0.5, 0.5
    if p:find("LEFT", 1, true) then sx = 0 elseif p:find("RIGHT", 1, true) then sx = 1 end
    if p:find("BOTTOM", 1, true) then sy = 0 elseif p:find("TOP", 1, true) then sy = 1 end
    return sx, sy
end

-- A placed frame: its rect is given (left, bottom, w, h), or derived from one
-- anchor point and its size (the eater).
local Frame = {}
Frame.__index = Frame
local function NewFrame(r)
    return setmetatable({ r = r, lvl = 1, shown = true, attrs = {}, scripts = {} }, Frame)
end
function Frame:Rect()
    if self.r then
        if self.r.noPos then return nil end
        return self.r.left, self.r.bottom, self.r.w, self.r.h
    end
    local p = self.pt
    if not p then return nil end
    local rl, rb, rw, rh = p.rel:Rect()
    if not rl then return nil end
    local sx, sy = Share(p.relPoint)
    local ax, ay = rl + sx * rw + p.x, rb + sy * rh + p.y
    local qx, qy = Share(p.point)
    return ax - qx * self.w, ay - qy * self.h, self.w, self.h
end
function Frame:GetLeft()
    if self.r and self.r.secret then return SECRET end
    local l = self:Rect(); return l
end
function Frame:GetBottom()
    if self.r and self.r.secret then return SECRET end
    local _, b = self:Rect(); return b
end
function Frame:GetRight()
    if self.r and self.r.secret then return SECRET end
    local l, _, w = self:Rect(); return l and l + w
end
function Frame:GetTop()
    if self.r and self.r.secret then return SECRET end
    local _, b, _, h = self:Rect(); return b and b + h
end
function Frame:GetSize()
    if self.r then return self.r.w, self.r.h end
    return self.w or 0, self.h or 0
end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetFrameLevel() return self.lvl end
function Frame:SetFrameLevel(v) writes = writes + 1; self.lvl = v end
function Frame:ClearAllPoints() writes = writes + 1; self.pt = nil; self.npts = 0 end
function Frame:SetPoint(point, rel, relPoint, x, y)
    writes = writes + 1
    self.npts = (self.npts or 0) + 1
    self.pt = { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
end
function Frame:SetSize(w, h) writes = writes + 1; self.w, self.h = w, h end
function Frame:Show() writes = writes + 1; self.shown = true end
function Frame:Hide() writes = writes + 1; self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:RegisterForClicks() end
function Frame:SetAttribute(k, v) self.attrs[k] = v end
function Frame:HookScript(k, f) self.scripts[k] = f end

local created = {}
local ENV = setmetatable({
    CreateFrame = function(kind, name, parent, template)
        assert(not combat, "a frame was made in combat")
        local f = NewFrame(nil)
        f.kind, f.name, f.parent, f.template = kind, name, parent, template
        created[#created + 1] = f
        return f
    end,
    InCombatLockdown = function() return combat end,
    EllesmereUI = {
        AttachSecureUnitMenu = function() end,
        IsSecret = function(v) return v == SECRET end,
    },
}, { __index = _G })

local parked = 0
local function ParkEater(e)
    parked = parked + 1
    e._euiActive = false
    e:Hide()
end
local function Noop() end
local NS = {}

local chunk = assert(loadstring("local ParkEater, ForwardEnter, ForwardLeave, tipModEaters, ns = ...\n"
    .. SRC .. "\nreturn EnsureEater\n", "=EnsureEater"))
setfenv(chunk, ENV)
local EnsureEater = chunk(ParkEater, Noop, Noop, setmetatable({}, { __mode = "k" }), NS)

-- One party member: a 200 x 60 button, the health bar on its top 48, the power bar below.
local function NewUnit()
    local host = NewFrame({ left = 100, bottom = 400, w = 200, h = 60 })
    local health = NewFrame({ left = 100, bottom = 412, w = 200, h = 48 })
    local container = NewFrame(nil)
    container.lvl = 20
    return host, health, container, {}
end

local function EaterOf(d) return d.tipModEaters and d.tipModEaters.base end

local EPS = 0.011
local function Inside(e, host)
    local l, b, w, h = e:Rect()
    local hl, hb, hw, hh = host:Rect()
    if not l then return false end
    return l >= hl - EPS and b >= hb - EPS and l + w <= hl + hw + EPS and b + h <= hb + hh + EPS
end
local function RectIs(e, l0, b0, w0, h0)
    local l, b, w, h = e:Rect()
    if not l then return false end
    return math.abs(l - l0) < EPS and math.abs(b - b0) < EPS
        and math.abs(w - w0) < EPS and math.abs(h - h0) < EPS
end
local function RectStr(e)
    local l, b, w, h = e:Rect()
    if not l then return "no rect" end
    return string.format("%.2f,%.2f %.2fx%.2f", l, b, w, h)
end

-- Debuff row: Size 36, Max Debuffs 4, Spacing 1 -> footprint 147 x 36.
local W4, H1 = 4 * 36 + 3, 36

-------------------------------------------------------------------------------
print("1. Top Right, Growth Right, Offset X 37 (the report): nothing off the unit")
do
    local host, health, container, d = NewUnit()
    EnsureEater(d, "base", host, container, true, health, "TOPRIGHT", "TOPRIGHT", 37, 0, W4, H1)
    local e = EaterOf(d)
    check(e and e.shown, "the eater shows over the part of the footprint on the frame")
    if e then
        check(Inside(e, host), "eater stays on its unit button (" .. RectStr(e) .. ")")
        check(RectIs(e, 190, 424, 110, 36), "eater = footprint cut to the button (" .. RectStr(e) .. ")")
    end
end

print("2. Bottom Right, Growth Left, no offset: placed as before and follows the bar")
do
    local host, health, container, d = NewUnit()
    EnsureEater(d, "base", host, container, true, health, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0, 56, 18)
    local e = EaterOf(d)
    check(e and e.shown, "eater made and shown")
    if e then
        check(RectIs(e, 244, 412, 56, 18), "rect as before (" .. RectStr(e) .. ")")
        check(e.pt and e.pt.rel == health, "anchored to the health bar's corner")
        -- The power bar hides for this occupant: the health bar takes the full height.
        health.r.bottom, health.r.h = 400, 60
        check(RectIs(e, 244, 400, 56, 18), "eater follows the moved corner (" .. RectStr(e) .. ")")
    end
end

print("3. Footprint wholly off the frame: no eater")
do
    local host, health, container, d = NewUnit()
    EnsureEater(d, "base", host, container, true, health, "TOPRIGHT", "TOPLEFT", -1, 0, 56, 18)
    local e = EaterOf(d)
    check(not (e and e.shown), "no eater shown for a footprint off the unit")
    check(e == nil, "no eater made")
end

print("4. Offset Y up into the frame above: cut at the top edge, stays there")
do
    local host, health, container, d = NewUnit()
    EnsureEater(d, "base", host, container, true, health, "TOPRIGHT", "TOPRIGHT", 0, 30, 56, H1)
    local e = EaterOf(d)
    check(e and e.shown, "eater shown over the part on the frame")
    if e then
        check(Inside(e, host), "eater stays on its unit button (" .. RectStr(e) .. ")")
        check(RectIs(e, 244, 454, 56, 6), "eater = footprint cut to the button (" .. RectStr(e) .. ")")
        health.r.bottom, health.r.h = 400, 60
        check(Inside(e, host), "still on the button after the bar resizes (" .. RectStr(e) .. ")")
    end
end

print("5. No position yet: placed as before, measured again on the next pass")
do
    local host, health, container, d = NewUnit()
    host.r.noPos = true
    EnsureEater(d, "base", host, container, true, health, "TOPRIGHT", "TOPRIGHT", 37, 0, W4, H1)
    local e = EaterOf(d)
    check(e and e.shown, "eater made before positions exist")
    host.r.noPos = nil
    if e then
        check(RectIs(e, 190, 424, 147, 36), "placed unclipped, as before (" .. RectStr(e) .. ")")
        EnsureEater(d, "base", host, container, true, health, "TOPRIGHT", "TOPRIGHT", 37, 0, W4, H1)
        check(Inside(e, host), "next pass keeps it on the button (" .. RectStr(e) .. ")")
    end
end

print("6. A position the client keeps secret is never computed with")
do
    local host, health, container, d = NewUnit()
    host.r.secret = true
    local ok, err = pcall(EnsureEater, d, "base", host, container, true, health,
        "TOPRIGHT", "TOPRIGHT", 37, 0, W4, H1)
    check(ok, "no arithmetic on a secret position: " .. tostring(err))
    local e = EaterOf(d)
    check(e and e.shown, "eater still made")
end

print("7. An unchanged pass writes nothing; combat writes nothing")
do
    local host, health, container, d = NewUnit()
    EnsureEater(d, "base", host, container, true, health, "TOPRIGHT", "TOPRIGHT", 0, 30, 56, H1)
    local e = EaterOf(d)
    writes = 0
    EnsureEater(d, "base", host, container, true, health, "TOPRIGHT", "TOPRIGHT", 0, 30, 56, H1)
    check(writes == 0, "unchanged pass: " .. writes .. " writes")
    combat = true
    writes = 0
    EnsureEater(d, "base", host, container, true, health, "TOPRIGHT", "TOPRIGHT", 0, 60, 56, H1)
    check(writes == 0, "combat: " .. writes .. " writes")
    check(d.rfcBmPending == true, "combat latches the regen reload")
    combat = false
    d.rfcBmPending = nil
    -- The footprint moves wholly off the unit: the eater it had parks.
    local p0 = parked
    EnsureEater(d, "base", host, container, true, health, "TOPRIGHT", "TOPRIGHT", 0, 60, 56, H1)
    check(e and not e.shown and e._euiActive == false, "eater off the unit parks")
    check(parked == p0 + 1, "parked once")
    -- And comes back when the footprint returns.
    EnsureEater(d, "base", host, container, true, health, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0, 56, 18)
    check(e and e.shown and RectIs(e, 244, 412, 56, 18), "eater back in place (" .. (e and RectStr(e) or "") .. ")")
    check(EaterOf(d) == e, "the same eater is reused")
end

print("8. The button moves (a re-sort): the next pass writes nothing, the eater moves with it")
do
    local host, health, container, d = NewUnit()
    EnsureEater(d, "base", host, container, true, health, "TOPRIGHT", "TOPRIGHT", 37, 0, W4, H1)
    local e = EaterOf(d)
    host.r.left, host.r.bottom = 400.37, 123.71
    health.r.left, health.r.bottom = 400.37, 135.71
    writes = 0
    EnsureEater(d, "base", host, container, true, health, "TOPRIGHT", "TOPRIGHT", 37, 0, W4, H1)
    check(writes == 0, "same unit layout, new spot: " .. writes .. " writes")
    check(e and Inside(e, host), "still on the moved button (" .. (e and RectStr(e) or "") .. ")")
end

print("9. A Y offset edit inside the frame moves the eater")
do
    local host, health, container, d = NewUnit()
    EnsureEater(d, "base", host, container, true, health, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0, 56, 18)
    local e = EaterOf(d)
    EnsureEater(d, "base", host, container, true, health, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 4, 56, 18)
    check(e and RectIs(e, 244, 416, 56, 18), "eater follows the new offsets (" .. (e and RectStr(e) or "") .. ")")
end

print(string.format("%d checks, %d failed", count, fails))
if fails > 0 then error(fails .. " check(s) failed") end
