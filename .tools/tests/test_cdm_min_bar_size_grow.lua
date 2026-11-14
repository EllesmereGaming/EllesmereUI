-- Stub harness: Cooldown Manager, Minimum Bar Size and the bar's grow direction (EUI_CDM_Bars.lua).
-- A bar with a Minimum Width / Height keeps room for that many icon slots along its growth axis.
-- While it shows fewer icons, the room left over follows the grow direction: Right and Down keep
-- the icons at the start of the bar, Left and Up at its end, Center splits it evenly.
-- Rules checked here:
--   - the reserved room is the minimum's slots at the bar's base icon size, and only while the
--     bar shows fewer icons; with no minimum, or at or above it, the bar is as long as its icons;
--   - the icons sit at the edge the bar grows from, or centred under Center grow;
--   - a two-row bar with its own top-row icon size keeps its rows centred against each other,
--     and the pair follows the same rule; under Center each row is centred in the whole bar with
--     ONE rounding, so the narrower row never lands a pixel off the centre;
--   - no function is made per layout pass for it.
-- Driven here: the real layout pass, cut out of the file by its first and last lines, over
-- recording frames and icons.
--   lua .tools/tests/test_cdm_min_bar_size_grow.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
-- From the first line through the last line, both kept.
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local _, e = src:find(last, a, true)
    assert(e, what .. ": last line not found")
    return src:sub(a, e)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local SRC = ReadSource("EllesmereUICooldownManager/EUI_CDM_Bars.lua")
assert(loadstring(SRC, "=EUI_CDM_Bars.lua"), "the bars file does not compile")
local Layout = assert(loadstring(
    "local ns, cdmBarFrames, cdmBarIcons, barDataByKey, _ecmeFC, FC, _getFD, EllesmereUI, GetStableCDMBarSize, SnapForScale = ...\n"
    .. "local LayoutCDMBar\n"
    .. Cut(SRC, "function ns.CDMRowsReversed(barData)", "    return barData.rowGrowDirection == \"LEFT\"\nend\n", "the row order") .. "\n"
    .. Cut(SRC, "local function ComputeTopRowStride(barData, count)", "    return stride, numRows, topCount\nend\n", "the stride") .. "\n"
    .. Cut(SRC, "local function ReserveStride(barData, stride)", "    return stride\nend\n", "the reserved stride") .. "\n"
    .. Cut(SRC, "LayoutCDMBar = function(barKey)", "        ns.ReapplyFocusKick()\n    end\nend\n", "the layout pass") .. "\n"
    .. "return LayoutCDMBar\n", "=EUI_CDM_Bars.lua (layout)"))

issecretvalue = function() return false end
UIParent = { GetEffectiveScale = function() return 1 end }
EllesmereUIDB = nil

local function NewFrame()
    local f = { w = 0, h = 0 }
    function f:GetWidth() return self.w end
    function f:GetHeight() return self.h end
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:GetEffectiveScale() return 1 end
    function f:GetCenter() return 0, 0 end
    return f
end
local function NewIcon()
    local ic = {}
    function ic:GetScale() return 1 end
    function ic:SetSize(w, h) self.w, self.h = w, h end
    function ic:SetFrameStrata() end
    function ic:SetFrameLevel() end
    function ic:ClearAllPoints() end
    function ic:SetPoint(p, rel, rp, x, y) self.x, self.y = x, y end
    return ic
end
-- One layout pass of a bar with n icons; mult = the physical pixel size in UI units.
local function Run(barData, n, mult)
    local ns = {
        CdmBlizzIcons = function() return false end,
        CdmCropFactor = function() return 0.75 end,
        IsBarBuffFamily = function() return false end,
        RequestLootPlacement = function() end,
        _cdmUKey = {},
        FOCUSKICK_BAR_KEY = "focuskick",
    }
    local frame = NewFrame()
    local icons = {}
    for i = 1, n do icons[i] = NewIcon() end
    local fcT, fdT = {}, {}
    local pass = Layout(ns, { b = frame }, { b = icons }, { b = barData }, {},
        function(x) fcT[x] = fcT[x] or {} return fcT[x] end,
        function(x) fdT[x] = fdT[x] or {} return fdT[x] end,
        { PP = { mult = mult or 1 }, IsPointAnchored = function() return false end },
        function() return 100, 36 end, function(v) return v end)
    pass("b")
    return frame, icons
end
local function Bar(t)
    local b = { enabled = true, iconSize = 36, spacing = 2, numRows = 1 }
    for k, v in pairs(t) do b[k] = v end
    return b
end
-- Along the growth axis, from the bar's start: where the icons [from..to] begin and end, the
-- size of one of them, and the bar's length.
local function Span(frame, icons, horiz, from, to)
    local lo, hi = math.huge, -math.huge
    for i = from or 1, to or #icons do
        local ic = icons[i]
        local a = horiz and ic.x or -ic.y
        local s = horiz and ic.w or ic.h
        if a < lo then lo = a end
        if a + s > hi then hi = a + s end
    end
    local one = icons[from or 1]
    return lo, hi, horiz and one.w or one.h, horiz and frame.w or frame.h
end
local function Half(v) return math.floor(v / 2 + 0.5) end
local GROWS = {
    { "RIGHT", false, 0 }, { "LEFT", false, 2 }, { "CENTER", false, 1 },
    { "DOWN", true, 0 }, { "UP", true, 2 }, { "CENTER", true, 1 },
}

-------------------------------------------------------------------------------
-- 1. One row: the room a minimum reserves, and where the icons sit in it
-------------------------------------------------------------------------------
for _, g in ipairs(GROWS) do
    local grow, vert, lead = g[1], g[2], g[3]
    local what = grow .. (vert and " (vertical)" or "")
    for _, sp in ipairs({ 0, 2, 3 }) do
        for minN = 2, 5 do
            for n = 1, 6 do
                local frame, icons = Run(Bar({ growDirection = grow, verticalOrientation = vert or nil, minSizeIcons = minN, spacing = sp }), n)
                local lo, hi, size, total = Span(frame, icons, not vert)
                local content = n * size + (n - 1) * sp
                local want = (minN > n) and (minN * size + (minN - 1) * sp) or content
                local tag = what .. ", " .. n .. " of " .. minN .. " icons, spacing " .. sp
                check(total == want, tag .. ": the bar is " .. total .. " long, expected " .. want)
                check(hi - lo == content, tag .. ": the icons span " .. (hi - lo) .. ", expected " .. content)
                local surplus = want - content
                local wantLead = (lead == 0 and 0) or (lead == 2 and surplus) or Half(surplus)
                check(lo == wantLead, tag .. ": the icons start at " .. lo .. ", expected " .. wantLead)
            end
        end
    end
    -- no minimum: the bar is its icons
    local frame, icons = Run(Bar({ growDirection = grow, verticalOrientation = vert or nil }), 2)
    local lo, hi, _, total = Span(frame, icons, not vert)
    check(lo == 0 and hi == total, what .. ", no minimum: the bar is longer than its icons")
end
-- a known case in numbers: three slots of 36 with 2 between them are 112 long
do
    local frame, icons = Run(Bar({ growDirection = "RIGHT", minSizeIcons = 3 }), 1)
    local lo, hi, size, total = Span(frame, icons, true)
    check(size == 36 and total == 112 and lo == 0 and hi == 36, "Right grow, 1 of 3 icons: not one icon at the start of a 112 long bar")
    frame, icons = Run(Bar({ growDirection = "LEFT", minSizeIcons = 3 }), 1)
    lo, hi, _, total = Span(frame, icons, true)
    check(total == 112 and lo == 76 and hi == 112, "Left grow, 1 of 3 icons: not one icon at the end of a 112 long bar")
    frame, icons = Run(Bar({ growDirection = "CENTER", minSizeIcons = 3 }), 1)
    lo, hi = Span(frame, icons, true)
    check(lo == 38 and hi == 74, "Center grow, 1 of 3 icons: the icon is not in the middle")
end
-- at a UI scale where a pixel is not a unit: the same edges
do
    local mult = 0.7111111
    for _, g in ipairs(GROWS) do
        local frame, icons = Run(Bar({ growDirection = g[1], verticalOrientation = g[2] or nil, minSizeIcons = 4 }), 2, mult)
        local lo, hi, _, total = Span(frame, icons, not g[2])
        local what = g[1] .. (g[2] and " (vertical)" or "") .. " at a fractional pixel size"
        if g[3] == 0 then
            check(math.abs(lo) < 1e-6 and total - hi > 1, what .. ": the icons are not at the start")
        elseif g[3] == 2 then
            check(math.abs(total - hi) < 1e-6 and lo > 1, what .. ": the icons are not at the end")
        else
            check(math.abs(lo - (total - hi)) <= mult + 1e-6, what .. ": the icons are more than a pixel off the middle")
        end
    end
end

-------------------------------------------------------------------------------
-- 2. Two rows with their own top-row icon size
-------------------------------------------------------------------------------
local function PerRow(grow, vert, n, minN, topN, off, sp)
    local frame, icons = Run(Bar({ growDirection = grow, verticalOrientation = vert or nil,
        numRows = 2, customTopRowEnabled = true, topRowCount = topN,
        customTopRowSizeEnabled = true, topRowSizeOffset = off, spacing = sp, minSizeIcons = minN }), n)
    local lo1, hi1, _, total = Span(frame, icons, not vert, 1, topN)
    local lo2, hi2 = Span(frame, icons, not vert, topN + 1, n)
    return total, lo1, hi1 - lo1, lo2, hi2 - lo2
end
do
    -- a known case in numbers: rows of two 41s and one 36, six slots reserved (226 long)
    local total, lo1, len1, lo2, len2 = PerRow("RIGHT", false, 3, 6, 2, 5, 2)
    check(total == 226 and len1 == 84 and len2 == 36, "two rows, 3 of 6 icons: the bar or its rows are not 226 / 84 / 36 long")
    check(lo1 == 0 and lo2 == 24, "Right grow, two rows: the wider row is not at the start with the other centred under it")
    total, lo1, len1, lo2, len2 = PerRow("LEFT", false, 3, 6, 2, 5, 2)
    check(lo1 == 142 and lo2 == 166, "Left grow, two rows: the wider row is not at the end with the other centred under it")
    total, lo1, len1, lo2, len2 = PerRow("CENTER", false, 3, 6, 2, 5, 2)
    check(lo1 == 71 and lo2 == 95, "Center grow, two rows: the rows are not centred in the bar")
end
local tried, minimums = 0, 0
for _, g in ipairs(GROWS) do
    local grow, vert, lead = g[1], g[2], g[3]
    local what = grow .. (vert and " (vertical)" or "") .. ", two rows"
    for off = 1, 6 do
        for sp = 1, 3 do
            for _, minN in ipairs({ 0, 3, 4, 5, 6 }) do
                for n = 3, 5 do
                    for topN = 1, n - 1 do
                        local total, lo1, len1, lo2, len2 = PerRow(grow, vert, n, minN > 0 and minN or nil, topN, off, sp)
                        local content = math.max(len1, len2)
                        local surplus = total - content
                        tried = tried + 1
                        if surplus > 0 then minimums = minimums + 1 end
                        local tag = what .. " (" .. topN .. " + " .. (n - topN) .. " icons, minimum " .. minN .. ", +" .. off .. ", spacing " .. sp .. ")"
                        check(surplus >= 0 and (minN > 0 or surplus == 0), tag .. ": the bar is " .. total .. " long around rows of " .. len1 .. " and " .. len2)
                        -- one rounding per row: the row's share of the surplus and its own centring together
                        local w1 = Half(lead * surplus + content - len1)
                        local w2 = Half(lead * surplus + content - len2)
                        check(lo1 == w1 and lo2 == w2, tag .. ": the rows start at " .. lo1 .. " and " .. lo2 .. ", expected " .. w1 .. " and " .. w2)
                        if lead == 1 then
                            -- centred in the whole bar, to the pixel
                            check(lo1 == Half(total - len1) and lo2 == Half(total - len2), tag .. ": a row is off the bar's centre")
                        end
                    end
                end
            end
        end
    end
end
check(tried == 4860 and minimums > 2000 and minimums < tried, "the two-row cases did not cover bars under and over their minimum (" .. minimums .. " of " .. tried .. ")")

-------------------------------------------------------------------------------
-- 3. Nothing is made per pass for the lead
-------------------------------------------------------------------------------
do
    local pass = Cut(SRC, "LayoutCDMBar = function(barKey)", "        ns.ReapplyFocusKick()\n    end\nend\n", "the layout pass")
    check(not pass:find("local function PadLead", 1, true), "the layout pass makes a function for the lead on every pass")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_cdm_min_bar_size_grow (%d checks)"):format(count))
