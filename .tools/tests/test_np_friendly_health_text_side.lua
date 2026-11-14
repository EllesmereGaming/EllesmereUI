-- Stub harness: Nameplates, Show Health Percent on the friendly health bar plates.
-- The dropdown (None / Right / Left / Center) is a view over two saved keys:
-- friendlyHideHealthText (true = None) and friendlyHealthTextPos ("left" or "center"; unset,
-- or anything else, = the right). Driven here, all real code cut from the module:
--   the placer (ns.NP_PlaceFriendlyHealthText), which the options samples share;
--   a plate's own sync (SyncHealthTextSide): placed when the plate is made, again only when
--     the side changed, also for a pooled plate that is handed a unit;
--   the options' refresh (ns.RefreshFriendlyHealthText) and a profile or override flip
--     (ns.NP_SyncFriendlyHealthTextSide, from ns.RefreshAllSettings);
--   the text itself (FriendlyFrame:UpdateHealth): nothing while hidden, the percent otherwise.
--   lua .tools/tests/test_np_friendly_health_text_side.lua        (from the repository root)
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
        if fails <= 20 then print("  FAIL: " .. msg) end
    end
    return cond
end
local function eq(got, want, msg)
    return check(got == want, msg .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end

local SRC = ReadSource("EllesmereUINameplates/EllesmereUINameplatesFriendly.lua")
local POOL = ReadSource("EllesmereUINameplates/EUI_Nameplates_PlatePool.lua")
local MAIN = ReadSource("EllesmereUINameplates/EllesmereUINameplates.lua")

local profile                                   -- the saved settings (nil: no profile yet)
local function FP() return profile end
local ns = {}

-- A font string that records its points (and how often it was placed) and its text.
local function NewText()
    local fs = { points = {}, clears = 0, sets = 0 }
    function fs:ClearAllPoints() self.points = {}; self.clears = self.clears + 1 end
    function fs:SetPoint(point, rel, relPoint, x, y)
        self.points[#self.points + 1] = { point, rel, relPoint, x, y }
        self.sets = self.sets + 1
    end
    function fs:SetText(t) self.text = t end
    function fs:SetFormattedText(f, ...) self.text = f:format(...) end
    return fs
end
local function NewBar()
    local bar = {}
    function bar:SetMinMaxValues(a, b) self.min, self.max = a, b end
    function bar:SetValue(v) self.value = v end
    return bar
end
local function At(fs, health)
    local p = fs.points[#fs.points]
    return #fs.points .. " point: " .. tostring(p and p[1]) .. "," .. tostring(p and p[2] == health) .. "," .. tostring(p and p[3])
        .. "," .. tostring(p and p[4]) .. "," .. tostring(p and p[5])
end
local RIGHT, LEFT, CENTER = "1 point: RIGHT,true,RIGHT,-2,0", "1 point: LEFT,true,LEFT,2,0", "1 point: CENTER,true,CENTER,0,0"

-------------------------------------------------------------------------------
-- 1. the placer: one point on the bar, by the saved side
-------------------------------------------------------------------------------
local SyncHealthTextSide = assert(loadstring("local ns, FP = ...\n"
    .. Cut(SRC, "local HP_TEXT_SIDE = {", "\nlocal pairs, ipairs = pairs, ipairs", "the placer and a plate's sync")
    .. "\nreturn SyncHealthTextSide", "=EllesmereUINameplatesFriendly.lua"))(ns, FP)
check(type(ns.NP_PlaceFriendlyHealthText) == "function" and type(SyncHealthTextSide) == "function", "the placer or the plate's sync is not where the test cuts it")
do
    local fs, health = NewText(), NewBar()
    for _, c in ipairs({ { nil, RIGHT }, { "right", RIGHT }, { "left", LEFT }, { "center", CENTER }, { "top", RIGHT }, { false, RIGHT },
                         { 3, RIGHT }, { "LEFT", RIGHT } }) do
        ns.NP_PlaceFriendlyHealthText(fs, health, c[1])
        eq(At(fs, health), c[2], "the text's place for a saved side of " .. tostring(c[1]))
    end
    -- a new place takes the old one's point away first
    eq(fs.clears, 8, "the placer's ClearAllPoints calls over eight placements")
    eq(fs.sets, 8, "the placer's SetPoint calls over eight placements")
end

-------------------------------------------------------------------------------
-- 2. a plate's own sync: placed once, again only when the side changed
-------------------------------------------------------------------------------
do
    local function NewPlate() return { hpText = NewText(), health = NewBar() } end
    -- a plate made before any profile is read sits on the right
    profile = nil
    local plate = NewPlate()
    SyncHealthTextSide(plate)
    eq(At(plate.hpText, plate.health), RIGHT, "a new plate's text with no profile")
    eq(plate.hpText.sets, 1, "placements of a new plate's text")
    -- nothing changed: not placed again, through a profile with no side saved too
    SyncHealthTextSide(plate)
    profile = {}
    SyncHealthTextSide(plate)
    profile = { friendlyHideHealthText = true }
    SyncHealthTextSide(plate)
    eq(plate.hpText.sets, 1, "placements while the side did not change (no profile, none saved, hidden)")
    -- every change of side places it once
    local sets = 1
    for _, c in ipairs({ { "left", LEFT }, { "center", CENTER }, { nil, RIGHT }, { "center", CENTER }, { "left", LEFT } }) do
        profile = { friendlyHealthTextPos = c[1] }
        SyncHealthTextSide(plate)
        sets = sets + 1
        eq(At(plate.hpText, plate.health), c[2], "the text's place after the side became " .. tostring(c[1]))
        SyncHealthTextSide(plate)
        SyncHealthTextSide(plate)
        eq(plate.hpText.sets, sets, "placements after the side became " .. tostring(c[1]) .. " and two more syncs")
    end
    -- a new plate under a saved side is placed there at once
    profile = { friendlyHealthTextPos = "center" }
    local second = NewPlate()
    SyncHealthTextSide(second)
    check(At(second.hpText, second.health) == CENTER and second.hpText.sets == 1, "a new plate under a saved side is not placed there once")
    -- the plate is made and handed its unit through the sync, never through a point of its own
    local made = Cut(SRC, '    plate.hpText = plate.health:CreateFontString(nil, "OVERLAY")', "\n    -- Blizzard Style: above the deselected overlay", "the text's creation")
    check(made:find("\n    SyncHealthTextSide(plate)", 1, true) and not made:find("SetPoint", 1, true), "a new plate's text is not placed by the sync")
    local setUnit = Cut(SRC, "function FriendlyFrame:SetUnit(unit, nameplate)", "\nfunction FriendlyFrame:ClearUnit()", "SetUnit")
    local a, b = setUnit:find("\n    SyncHealthTextSide(self)\n", 1, true), setUnit:find("\n    self:UpdateHealth()\n", 1, true)
    check(a and b and a < b, "a pooled plate handed a unit is not synced before its health is painted")
    local n = 0
    for _ in SRC:gmatch("hpText:SetPoint") do n = n + 1 end
    eq(n, 0, "points set on a plate's health text outside the placer")
    -- the health event paints the text and never places it
    local update = Cut(SRC, "function FriendlyFrame:UpdateHealth()", "\nfunction FriendlyFrame:UpdateName()", "UpdateHealth")
    check(not update:find("SyncHealthTextSide", 1, true) and not update:find("SetPoint", 1, true) and not update:find("friendlyHealthTextPos", 1, true),
        "the health event places the text")
end

-------------------------------------------------------------------------------
-- 3. the options' refresh and a profile or override flip, over the live plates
-------------------------------------------------------------------------------
do
    local friendlyPlates = {}
    local updates = 0
    local function NewPlate()
        local plate = { hpText = NewText(), health = NewBar() }
        function plate:UpdateHealth() updates = updates + 1; self.updatedAt = self.hpText.sets end
        return plate
    end
    assert(loadstring("local ns, friendlyPlates, SyncHealthTextSide, pairs = ...\n"
        .. Cut(SRC, "function ns.RefreshFriendlyHealthText()", "\n-- Repaints every live full plate's bar and name", "the refreshes"),
        "=EllesmereUINameplatesFriendly.lua"))(ns, friendlyPlates, SyncHealthTextSide, pairs)
    check(type(ns.RefreshFriendlyHealthText) == "function" and type(ns.NP_SyncFriendlyHealthTextSide) == "function", "the refreshes are not where the test cuts them")
    profile = {}
    for i = 1, 3 do
        friendlyPlates["nameplate" .. i] = NewPlate()
        SyncHealthTextSide(friendlyPlates["nameplate" .. i])
    end
    -- the options' refresh: every plate placed on the new side, then painted
    profile = { friendlyHealthTextPos = "left" }
    ns.RefreshFriendlyHealthText()
    eq(updates, 3, "health paints by the options' refresh over three plates")
    for unit, plate in pairs(friendlyPlates) do
        check(At(plate.hpText, plate.health) == LEFT and plate.hpText.sets == 2 and plate.updatedAt == 2,
            "the options' refresh does not place " .. unit .. " on the new side before painting it")
    end
    -- the same refresh with nothing changed paints and places nothing again
    ns.RefreshFriendlyHealthText()
    eq(updates, 6, "health paints by a second refresh")
    for unit, plate in pairs(friendlyPlates) do eq(plate.hpText.sets, 2, "placements of " .. unit .. " after a refresh that changed no side") end
    -- a profile or override flip: placed, not painted; one compare while nothing changed
    profile = { friendlyHealthTextPos = "center" }
    ns.NP_SyncFriendlyHealthTextSide()
    ns.NP_SyncFriendlyHealthTextSide()
    eq(updates, 6, "health paints by a settings re-read")
    for unit, plate in pairs(friendlyPlates) do
        check(At(plate.hpText, plate.health) == CENTER and plate.hpText.sets == 3, "a settings re-read does not place " .. unit .. " once on the new side")
    end
    -- with no friendly plate up the two do nothing
    for unit in pairs(friendlyPlates) do friendlyPlates[unit] = nil end
    ns.RefreshFriendlyHealthText()
    ns.NP_SyncFriendlyHealthTextSide()
    eq(updates, 6, "health paints with no friendly plate up")
    -- every settings re-read reaches it
    local reread = Cut(POOL, "function ns.RefreshAllSettings()", "\nend\n", "RefreshAllSettings")
    check(reread:find("\n    if ns.NP_SyncFriendlyHealthTextSide then ns.NP_SyncFriendlyHealthTextSide() end", 1, true),
        "a profile or override flip does not reach the live plates' health text")
end

-------------------------------------------------------------------------------
-- 4. the text: nothing while Show Health Percent is None, the percent otherwise
-------------------------------------------------------------------------------
do
    local dead, pct = false, 57
    local env = setmetatable({
        UnitHealthMax = function() return 100 end, UnitHealth = function() return pct end,
        UnitIsDeadOrGhost = function() return dead end,
        UnitHealthPercent = function() return pct end, CurveConstants = { ScaleTo100 = {} },
    }, { __index = _G })
    local FriendlyFrame = {}
    setfenv(assert(loadstring("local FriendlyFrame, FP = ...\n"
        .. Cut(SRC, "function FriendlyFrame:UpdateHealth()", "\nfunction FriendlyFrame:UpdateName()", "UpdateHealth"),
        "=EllesmereUINameplatesFriendly.lua")), env)(FriendlyFrame, FP)
    local plate = { unit = "nameplate1", hpText = NewText(), health = NewBar(), UpdateHealth = FriendlyFrame.UpdateHealth }
    for _, c in ipairs({ { nil, "57%" }, { {}, "57%" }, { { friendlyHideHealthText = false }, "57%" }, { { friendlyHideHealthText = true }, "" },
                         { { friendlyHideHealthText = true, friendlyHealthTextPos = "left" }, "" },
                         { { friendlyHealthTextPos = "left" }, "57%" }, { { friendlyHealthTextPos = "center" }, "57%" } }) do
        profile = c[1]
        plate.hpText.text = "?"
        plate:UpdateHealth()
        eq(plate.hpText.text, c[2], "the text with friendlyHideHealthText=" .. tostring(c[1] and c[1].friendlyHideHealthText)
            .. ", friendlyHealthTextPos=" .. tostring(c[1] and c[1].friendlyHealthTextPos))
    end
    eq(plate.hpText.sets, 0, "placements by the health event")
    check(plate.health.max == 100 and plate.health.value == 57, "the bar's value")
end

-------------------------------------------------------------------------------
-- 5. the saved keys: no default for the side (unset = the right), the switch as it was
-------------------------------------------------------------------------------
check(not MAIN:find("friendlyHealthTextPos", 1, true), "the side has a default (unset is the right)")
do
    local OPT = ReadSource("EllesmereUIOptions/Nameplates_Options/FriendlyPage_Options.lua")
    local row = Cut(OPT, '            { type="dropdown", text="Show Health Percent",', "\n              end });", "the dropdown")
    check(row:find('values={ none="None", right="Right", left="Left", center="Center" },', 1, true)
        and row:find('order={ "none", "right", "left", "center" },', 1, true), "the dropdown's entries")
    check(row:find('db.friendlyHealthTextPos = (v ~= "right") and v or nil', 1, true), "the right is not saved as no side")
    check(OPT:find('ns.NP_PlaceFriendlyHealthText', 1, true) == nil, "the options page places a text itself")
    local PV = ReadSource("EllesmereUIOptions/Nameplates_Options/FriendlyPreview_Options.lua")
    check(PV:find('ns.NP_PlaceFriendlyHealthText(s.hpText, health, DBVal("friendlyHealthTextPos"))', 1, true), "the samples do not place their text through the runtime's placer")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_np_friendly_health_text_side (%d checks)"):format(count))
