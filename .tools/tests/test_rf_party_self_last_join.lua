-- Stub harness: Raid & Party Frames, where your own party frame stands (ns._PositionPartySlots in
-- EUI_RaidFrames_Party.lua), under Show Self Last and Show Self First.
-- Your frame is a button of its own beside the party header. A secure frame cannot be moved in combat,
-- so under Show Self Last it hangs off the header's far edge: the game's own header pass resizes the
-- header as members come and go, in combat too, and your frame is carried along. Before, it stood on a
-- slot worked out before the fight, and a member who joined mid-fight landed on top of it.
-- The real function, cut out of the file by its first and last lines, runs over a small anchor model:
-- frames with one anchor point each, and the game's group header pass reduced to one column (it chains
-- the shown children from the header's own point and sizes the header to them, or to 0.1 along the
-- growth axis when it shows none). The model cannot prove what the engine does in combat.
--   lua .tools/tests/test_rf_party_self_last_join.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. msg)
    end
end

local PX = 768 / 1440     -- a physical pixel in UI units
local function PixelSnap(v)
    if v == 0 then return 0 end
    return math.floor(v / PX + 0.5 + 0.001) * PX
end

local FX = { TOPLEFT = 0, TOP = 0.5, TOPRIGHT = 1, LEFT = 0, CENTER = 0.5, RIGHT = 1, BOTTOMLEFT = 0, BOTTOM = 0.5, BOTTOMRIGHT = 1 }
local FY = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5, BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }

local function NewFrame(name)
    local f = { name = name, w = 0, h = 0, attrs = {} }
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:SetWidth(w) self.w = w end
    function f:SetHeight(h) self.h = h end
    function f:ClearAllPoints() self.pt = nil end
    function f:SetPoint(p, rel, rp, x, y)
        assert(not self.pt, name .. " got a second point")
        self.pt = { p, rel, rp, x or 0, y or 0 }
    end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:GetAttribute(k) return self.attrs[k] end
    function f:SetAttribute(k, v) self.attrs[k] = v end
    return f
end
-- left, bottom, width, height
local function Rect(f)
    if f.fixed then return f.fixed[1], f.fixed[2], f.w, f.h end
    assert(f.pt, f.name .. " has no point")
    local p, rel, rp, x, y = f.pt[1], f.pt[2], f.pt[3], f.pt[4], f.pt[5]
    local rl, rb, rw, rh = Rect(rel)
    return rl + FX[rp] * rw + x - FX[p] * f.w, rb + FY[rp] * rh + y - FY[p] * f.h, f.w, f.h
end

-- The game's header pass, one column: n children shown
local REL = { TOP = { "BOTTOM", 0, -1 }, BOTTOM = { "TOP", 0, 1 }, LEFT = { "RIGHT", 1, 0 }, RIGHT = { "LEFT", -1, 0 } }
local function HeaderPass(hdr, n)
    local point = hdr:GetAttribute("point")
    local relativePoint, xOffsetMult, yOffsetMult = REL[point][1], REL[point][2], REL[point][3]
    local xMultiplier, yMultiplier = math.abs(xOffsetMult), math.abs(yOffsetMult)
    local xOffset, yOffset = hdr:GetAttribute("xOffset"), hdr:GetAttribute("yOffset")
    local anchor = hdr
    for i = 1, 5 do
        local c = hdr[i]
        c:ClearAllPoints()
        if i <= n then
            if i == 1 then c:SetPoint(point, anchor, point, 0, 0)
            else c:SetPoint(point, anchor, relativePoint, xMultiplier * xOffset, yMultiplier * yOffset) end
            c:Show()
            anchor = c
        else
            c:Hide()
        end
    end
    local uw, uh = hdr[1].w, hdr[1].h
    if n > 0 then
        hdr:SetWidth(xMultiplier * (n - 1) * uw + ((n - 1) * (xOffset * xOffsetMult)) + uw)
        hdr:SetHeight(yMultiplier * (n - 1) * uh + ((n - 1) * (yOffset * yOffsetMult)) + uh)
    else
        hdr:SetWidth(math.max(yMultiplier * uw, 0.1))
        hdr:SetHeight(math.max(xMultiplier * uh, 0.1))
    end
end

-- The real function over the names it reads
local NUM, IN_GROUP = 2, true
local Position
do
    local f = assert(io.open(ROOT .. "/EllesmereUIRaidFrames/EUI_RaidFrames_Party.lua", "rb"))
    local src = f:read("*a"):gsub("\r\n", "\n")
    f:close()
    local a = assert(src:find("ns._PositionPartySlots = function(bw, bh, cs, unitGrowth)\n", 1, true), "the function's first line not found")
    local b = assert(src:find("\nend\n", a, true), "the function's last line not found")
    Position = assert(loadstring("local ns, db, PixelSnap, IsInGroup, InCombatLockdown, GetNumGroupMembers = ...\n" .. src:sub(a, b + 4),
        "=EUI_RaidFrames_Party.lua"))
end

local HDR = { DOWN = { "TOP", 0, -1 }, UP = { "BOTTOM", 0, 1 }, RIGHT = { "LEFT", 1, 0 }, LEFT = { "RIGHT", -1, 0 } }
local EPS = 1e-9

-- A party of n (you included) under one growth direction. o: selfLast, centered, solo
local function Scene(growth, n, o)
    NUM, IN_GROUP = n, not o.solo
    local ns, db = {}, { profile = { partySelfLast = o.selfLast or false, partyShowSelfFirst = not o.selfLast,
        partyFlipGrowth = o.centered and "centered" or nil } }
    Position(ns, db, PixelSnap, function() return IN_GROUP end, function() return false end, function() return NUM end)
    local bw, bh, cs = PixelSnap(72), PixelSnap(46), PixelSnap(2)
    local c = NewFrame("container")
    if growth == "RIGHT" or growth == "LEFT" then c.w, c.h = 5 * bw + 4 * cs, bh else c.w, c.h = bw, 5 * bh + 4 * cs end
    c.fixed = { 0, 0 }
    local hdr = NewFrame("header")
    hdr:SetAttribute("point", HDR[growth][1])
    hdr:SetAttribute("xOffset", HDR[growth][2] * cs)
    hdr:SetAttribute("yOffset", HDR[growth][3] * cs)
    for i = 1, 5 do hdr[i] = NewFrame("child" .. i); hdr[i]:SetSize(bw, bh) end
    local sb = NewFrame("self")
    ns._partyHeader, ns._partyContainerFrame, ns._partySelfButton = hdr, c, sb
    ns._RFVisWanted = function() return nil, true end
    ns._PartyInRaid = function() return false end
    ns._FsPartyMode = function() return false end
    ns.PF_ReAnchor = function() end

    local stepX, stepY, base = 0, 0, "TOPLEFT"
    if growth == "RIGHT" then stepX = bw + cs
    elseif growth == "LEFT" then stepX = -(bw + cs); base = "TOPRIGHT"
    elseif growth == "UP" then stepY = bh + cs; base = "BOTTOMLEFT"
    else stepY = -(bh + cs) end
    local S = { ns = ns, hdr = hdr, sb = sb, bw = bw, bh = bh, cs = cs }
    -- the rect of slot i (0 = the first), moved `along` further in the growth direction
    function S.Slot(i, members, along)
        local shift = 0
        if o.centered then shift = (5 - math.min(members or NUM, 5)) / 2 end
        if o.solo and o.centered then shift = 2 end
        local dx = stepX ~= 0 and (stepX > 0 and 1 or -1) * (along or 0) or 0
        local dy = stepY ~= 0 and (stepY > 0 and 1 or -1) * (along or 0) or 0
        local probe = NewFrame("slot" .. i)
        probe:SetSize(bw, bh)
        probe:SetPoint(base, c, base, PixelSnap(stepX * i) + PixelSnap(stepX * shift) + dx, PixelSnap(stepY * i) + PixelSnap(stepY * shift) + dy)
        return Rect(probe)
    end
    function S.At(f, i, members, along)
        local l, b = S.Slot(i, members, along)
        local fl, fb, fw, fh = Rect(f)
        return math.abs(fl - l) < EPS and math.abs(fb - b) < EPS and math.abs(fw - bw) < EPS and math.abs(fh - bh) < EPS,
            ("stands at (%.4f, %.4f), the slot at (%.4f, %.4f)"):format(fl, fb, l, b)
    end
    function S.Layout() return ns._PositionPartySlots(bw, bh, cs, growth) end
    -- the header's own pass for the roster (solo it shows you; in a group the other members), then our
    -- layout pass, as after a roster update out of combat
    HeaderPass(hdr, o.solo and 1 or math.max(n - 1, 0))
    S.useSelf = S.Layout()
    return S
end
-- how deep two frames cover each other (0 when they do not)
local function Covered(a, b)
    local al, ab, aw, ah = Rect(a)
    local bl, bb, bw, bh = Rect(b)
    local x = math.min(al + aw, bl + bw) - math.max(al, bl)
    local y = math.min(ab + ah, bb + bh) - math.max(ab, bb)
    if x <= EPS or y <= EPS then return 0 end
    return math.min(x, y)
end

local GROWTHS = { "DOWN", "UP", "RIGHT", "LEFT" }

-------------------------------------------------------------------------------
-- 1. Show Self Last, a party of 2 to 5
-------------------------------------------------------------------------------
for _, growth in ipairs(GROWTHS) do
    for _, centered in ipairs({ false, true }) do
        for n = 2, 5 do
            local tag = ("%s%s, party of %d"):format(growth, centered and " centered" or "", n)
            local S = Scene(growth, n, { selfLast = true, centered = centered })
            check(S.useSelf == true and S.sb.shown == true, tag .. ": your own frame is not used")
            -- out of combat: the members on slots 0 .. n-2, you after them
            local ok, where = S.At(S.sb, n - 1)
            check(ok, tag .. ": your frame is not on the last slot: " .. where)
            for i = 1, n - 1 do
                ok, where = S.At(S.hdr[i], i - 1)
                check(ok, tag .. ": member " .. i .. " is not on its slot: " .. where)
            end
            -- the header's next pass for the same roster moves nothing
            local w, h = S.hdr.w, S.hdr.h
            HeaderPass(S.hdr, n - 1)
            check(math.abs(S.hdr.w - w) < EPS and math.abs(S.hdr.h - h) < EPS, tag .. ": the header was sized otherwise than its own pass sizes it")
            check(S.At(S.sb, n - 1), tag .. ": the header's own pass moved your frame")
            -- a member joins in combat: only the header's pass runs
            if n < 5 then
                HeaderPass(S.hdr, n)
                check(Covered(S.sb, S.hdr[n]) == 0, tag .. ": the member who joined in combat covers your frame")
                ok, where = S.At(S.sb, n, n)
                check(ok, tag .. ": after a join in combat your frame is not one slot along: " .. where)
                HeaderPass(S.hdr, n - 1)
                check(S.At(S.sb, n - 1), tag .. ": your frame is not back after that member left again")
            end
            -- a member leaves in combat
            if n > 2 then
                HeaderPass(S.hdr, n - 2)
                ok, where = S.At(S.sb, n - 2, n)
                check(ok, tag .. ": after a leave in combat your frame is not one slot back: " .. where)
            else
                -- the only other member leaves in combat: the header is 0.1 long, your frame the spacing past it
                HeaderPass(S.hdr, 0)
                ok, where = S.At(S.sb, 0, n, S.cs + 0.1)
                check(ok, tag .. ": alone after a leave in combat your frame is not the spacing past the first slot: " .. where)
            end
        end
    end
end

-------------------------------------------------------------------------------
-- 2. Show Self Last in a group that counts nobody but you (an invite not yet
--    answered): exactly on the first slot, and still pushed along by a join
-------------------------------------------------------------------------------
for _, growth in ipairs(GROWTHS) do
    for _, centered in ipairs({ false, true }) do
        local tag = ("%s%s, a group of one"):format(growth, centered and " centered" or "")
        local S = Scene(growth, 1, { selfLast = true, centered = centered })
        check(S.useSelf == true, tag .. ": your own frame is not used")
        local ok, where = S.At(S.sb, 0)
        check(ok, tag .. ": your frame is not exactly on the first slot: " .. where)
        local horizontal = growth == "RIGHT" or growth == "LEFT"
        check(math.abs(S.hdr.w - (horizontal and 0.1 or S.bw)) < EPS and math.abs(S.hdr.h - (horizontal and S.bh or 0.1)) < EPS,
            ("%s: the empty header is %.3f x %.3f"):format(tag, S.hdr.w, S.hdr.h))
        -- the header's own pass: the same size, your frame stays
        HeaderPass(S.hdr, 0)
        check(math.abs(S.hdr.w - (horizontal and 0.1 or S.bw)) < EPS and math.abs(S.hdr.h - (horizontal and S.bh or 0.1)) < EPS,
            tag .. ": the header's own pass sizes it otherwise")
        ok, where = S.At(S.sb, 0)
        check(ok, tag .. ": the header's own pass moved your frame off the first slot: " .. where)
        -- the first member joins in combat: on the first slot, you pushed along (all but the spacing and the 0.1)
        HeaderPass(S.hdr, 1)
        check(S.At(S.hdr[1], 0, 1), tag .. ": the member who joined in combat is not on the first slot")
        check(Covered(S.sb, S.hdr[1]) <= 0.1 + EPS, ("%s: the member who joined in combat covers your frame by %.3f"):format(tag, Covered(S.sb, S.hdr[1])))
        ok, where = S.At(S.sb, 1, 1, -(S.cs + 0.1))
        check(ok, tag .. ": after the first join in combat your frame is not a slot along (less the spacing and 0.1): " .. where)
        -- combat ends: the layout pass for the party of two puts you exactly on the second slot
        NUM = 2
        S.Layout()
        ok, where = S.At(S.sb, 1, 2)
        check(ok, tag .. ": after combat your frame is not exactly on the second slot: " .. where)
        check(S.At(S.hdr[1], 0, 2), tag .. ": after combat the member is not on the first slot")
    end
end

-------------------------------------------------------------------------------
-- 3. Show Self First: you on the first slot, the members after you
-------------------------------------------------------------------------------
for _, growth in ipairs(GROWTHS) do
    for _, centered in ipairs({ false, true }) do
        for n = 1, 5 do
            local tag = ("%s%s, Self First, party of %d"):format(growth, centered and " centered" or "", n)
            local S = Scene(growth, n, { selfLast = false, centered = centered })
            check(S.useSelf == true, tag .. ": your own frame is not used")
            local ok, where = S.At(S.sb, 0)
            check(ok, tag .. ": your frame is not on the first slot: " .. where)
            HeaderPass(S.hdr, n - 1)
            for i = 1, n - 1 do
                ok, where = S.At(S.hdr[i], i)
                check(ok, tag .. ": member " .. i .. " is not on the slot after yours: " .. where)
            end
            -- a join in combat never touches your frame
            if n < 5 then
                HeaderPass(S.hdr, n)
                check(S.At(S.sb, 0) and Covered(S.sb, S.hdr[n]) == 0, tag .. ": a join in combat moved or covered your frame")
            end
        end
    end
end

-------------------------------------------------------------------------------
-- 4. Solo: no frame of your own; the header shows you from the first slot
--    (the middle one under centered growth)
-------------------------------------------------------------------------------
for _, growth in ipairs(GROWTHS) do
    for _, centered in ipairs({ false, true }) do
        local tag = ("%s%s, solo"):format(growth, centered and " centered" or "")
        local S = Scene(growth, 0, { selfLast = true, centered = centered, solo = true })
        check(S.useSelf == false and S.sb.shown == false, tag .. ": your own frame is used while solo")
        local ok, where = S.At(S.hdr[1], 0)
        check(ok, tag .. ": the header's first frame is not where a solo player's stands: " .. where)
    end
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print("PASS test_rf_party_self_last_join (" .. count .. " checks)")
