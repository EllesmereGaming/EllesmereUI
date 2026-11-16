-- Stub harness: Nameplates, the room a name has in the Top text slot (TopNameWidth in
-- EUI_Nameplates_Name.lua) and its mirror in the options preview (NameplatePreview_Options.lua).
-- The raid marker, the Rare/Quest indicator, the Quest Objective Text and the faction badge take
-- room from a Top name only while they show ON THE NAME'S ROW: in Top or a top corner. In Left,
-- Right or Bottom they stand elsewhere, and a marker under the cast bar used to cut the name short
-- all the same. The preview must give the name the room live plates give it.
-- Both pieces are cut out of the real files by their first and last lines (a moved line fails here
-- by name) and run over stubs, for every combination of slots and of what shows.
--   lua .tools/tests/test_np_top_name_width.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 12 then print("  FAIL: " .. msg) end
    end
end

local NAME = ReadSource("EllesmereUINameplates/EUI_Nameplates_Name.lua")
local PREVIEW = ReadSource("EllesmereUIOptions/Nameplates_Options/NameplatePreview_Options.lua")

-- sizes: the raid marker, the Rare/Quest icon, the Quest Objective Text's width, the faction badge
local RM, CL, QT, FAC, BAR = 24, 22, 24, 20, 150
local S, P, CORNER = {}, {}, { textSlotTopLeft = 0, textSlotTopRight = 0 }

-- The live function over the names it reads
local ns = {
    NP_TopCornerTextWidth = function(key) return CORNER[key] end,
    NP_GetQuestTextSlot = function() return S.qt end,
    NP_GetFactionSlot = function()
        if P.classificationIncludeFaction then return S.cl end
        return S.fac
    end,
    NP_GetFactionIconSize = function() return FAC end,
    NP_ElementSize = function(elem) assert(elem == "faction"); return FAC end,
}
local LiveWidth = assert(loadstring(
    "local ns, p, GetRaidMarkerPos, GetRaidMarkerSize, GetClassificationSlot, GetRareEliteIconSize = ...\n" ..
    Cut(NAME, "function ns.NP_OnNameRow(slot)\n", "ns.NP_TopNameWidth = TopNameWidth", "the live width") ..
    "\nreturn TopNameWidth\n", "=EUI_Nameplates_Name.lua"))(ns, P,
    function() return S.rm end, function() return RM end, function() return S.cl end, function() return CL end)
check(type(ns.NP_OnNameRow) == "function", "the row test is not published for the options preview")

local function Frame(shown, extra)
    local f = extra or {}
    f.IsShown = function() return shown end
    return f
end
local function Plate(rm, cl, qt, fac)
    return { raidFrame = Frame(rm), classFrame = Frame(cl, { _npSz = CL }), questTextFrame = Frame(qt, { _npW = QT }), factionFrame = Frame(fac) }
end

-- The preview's lines over the names they read; returns the width it gives the name
local PreviewWidth = assert(loadstring(
    "local barW, pvNameMarkerReserve, ns, DB, rmPos, showRM, rmSize, classIcon, clPos, reIconSz, pf, factionIcon, fcCombined, fcPos, nameFS, pvNameWPct = ...\n" ..
    Cut(PREVIEW, "            local nameW = barW - pvNameMarkerReserve - 2 * math.max(", "            nameFS:SetTextColor(topC.r, topC.g, topC.b, 1)", "the preview's width") ..
    "\n", "=NameplatePreview_Options.lua"))

local ROW = { top = true, topleft = true, topright = true }
local SLOTS = { "none", "top", "topleft", "topright", "left", "right", "bottom" }

-------------------------------------------------------------------------------
-- 1. the reported layout: the marker under the bar, the Quest Objective Text
--    beside it: the name keeps the whole bar
-------------------------------------------------------------------------------
S.rm, S.cl, S.qt, S.fac = "bottom", "topleft", "left", "none"
check(LiveWidth(Plate(true, false, true, false), BAR) == BAR, "a marker in Bottom and a Quest Objective Text in Left still take room from the name")
-- each element alone, on the row and off it
for _, slot in ipairs(SLOTS) do
    local on = ROW[slot] or false
    S.rm, S.cl, S.qt, S.fac = slot, "none", "none", "none"
    check(LiveWidth(Plate(true, false, false, false), BAR) == BAR - (on and (2 * (RM - 2) + 7) or 0), "the raid marker in " .. slot)
    S.rm, S.cl = "none", slot
    check(LiveWidth(Plate(false, true, false, false), BAR) == BAR - (on and (CL + 4) or 0), "the Rare/Quest indicator in " .. slot)
    S.cl, S.qt = "none", slot
    check(LiveWidth(Plate(false, false, true, false), BAR) == BAR - (on and (QT + 4) or 0), "the Quest Objective Text in " .. slot)
    S.qt, S.fac = "none", slot
    check(LiveWidth(Plate(false, false, false, true), BAR) == BAR - (on and (FAC + 4) or 0), "the faction badge in " .. slot)
end
-- a hidden element takes nothing wherever it is set
S.rm, S.cl, S.qt, S.fac = "top", "topleft", "topright", "top"
check(LiveWidth(Plate(false, false, false, false), BAR) == BAR, "hidden elements take room")
-- the wider top corner text is kept clear on both sides
CORNER.textSlotTopLeft, CORNER.textSlotTopRight = 10, 25
check(LiveWidth(Plate(false, false, false, false), BAR) == BAR - 50, "the top corner texts")
CORNER.textSlotTopLeft, CORNER.textSlotTopRight = 0, 0

-------------------------------------------------------------------------------
-- 2. every combination: the live width is the bar less exactly what shows on
--    the name's row, and the options preview gives the name the same
-------------------------------------------------------------------------------
local combos, previewed = 0, 0
for _, combined in ipairs({ false, true }) do
    P.classificationIncludeFaction = combined or nil
    for _, rm in ipairs(SLOTS) do for _, cl in ipairs(SLOTS) do for _, qt in ipairs(SLOTS) do for _, fac in ipairs(SLOTS) do
        S.rm, S.cl, S.qt, S.fac = rm, cl, qt, fac
        local facSlot = ns.NP_GetFactionSlot()
        for mask = 0, 15 do
            local a, b, c, d = mask % 2 == 1, math.floor(mask / 2) % 2 == 1, math.floor(mask / 4) % 2 == 1, math.floor(mask / 8) % 2 == 1
            local want = BAR
            if a and ROW[rm] then want = want - (2 * (RM - 2) + 7) end
            if b and ROW[cl] then want = want - (CL + 4) end
            if c and ROW[qt] then want = want - (QT + 4) end
            if d and not (combined and b) and ROW[facSlot] then want = want - (FAC + 4) end
            local live = LiveWidth(Plate(a, b, c, d), BAR)
            combos = combos + 1
            if live ~= want then
                check(false, ("live: marker %s, Rare/Quest %s, Quest Objective Text %s, faction %s%s, shown %d: %s, not %s"):format(
                    rm, cl, qt, fac, combined and " (with Rare/Quest)" or "", mask, tostring(live), tostring(want)))
            end
            -- the preview draws the marker and the Rare/Quest icon only where a slot is set, and the faction
            -- badge wherever its slot is set: the states it can show
            if (not a or rm ~= "none") and (not b or cl ~= "none") and (d == (facSlot ~= "none")) then
                local got
                PreviewWidth(BAR, 0, ns, function() return {} end, rm, a, RM, Frame(b), cl, CL,
                    { _qt = { shown = c, pos = qt, w = QT } }, Frame(d), combined, facSlot,
                    { SetWidth = function(_, w) got = w end }, 100)
                previewed = previewed + 1
                if got ~= math.max(live, 20) then
                    check(false, ("preview: marker %s, Rare/Quest %s, Quest Objective Text %s, faction %s%s, shown %d: %s, live plates %s"):format(
                        rm, cl, qt, fac, combined and " (with Rare/Quest)" or "", mask, tostring(got), tostring(math.max(live, 20))))
                end
            end
        end
    end end end end
end
check(combos == 76832 and previewed > 10000, ("combinations walked: %d live, %d in the preview"):format(combos, previewed))

-------------------------------------------------------------------------------
-- 3. an element that changes slot refreshes the name's width (it may have come
--    onto the name's row or left it while staying shown)
-------------------------------------------------------------------------------
check(NAME:find("    if not wasShown or lastW ~= w or lastSlot ~= slot then self:UpdateNameWidth() end\n", 1, true) ~= nil,
    "the Quest Objective Text changing slot does not refresh the name's width")
check(NAME:find("    if not wasShown or lastSlot ~= slot then self:UpdateNameWidth() end\n", 1, true) ~= nil,
    "the faction badge changing slot does not refresh the name's width")

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_np_top_name_width (%d checks; %d slot and visibility combinations, %d of them in the preview)"):format(count, combos, previewed))
