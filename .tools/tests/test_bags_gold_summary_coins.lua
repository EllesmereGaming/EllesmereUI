-- Stub harness: Bags, the coins of the gold summary (EUI_Bags_Footer.lua, the Bags defaults and
-- the Bags options page). Hovering the gold in the bags footer lists every character's money,
-- the warband bank's and the total. Show Coins (the profile's bagGoldCoins, in the cog on Gold
-- Tracking and History) picks the coin columns: Only Gold, Gold and Silver, or Gold, Silver and
-- Copper. Rules checked here:
--   - Only Gold is the summary as it was before the setting: same texts, anchors and size;
--   - the default is Only Gold, and Gold and Silver on WoW Forever;
--   - each coin column is right-aligned and as wide as its widest text, the last one ending at
--     the summary's right edge; the widths start over with every summary;
--   - every shown coin of a row takes the row's colour;
--   - the silver and copper texts are made the first time their column shows, and a column no
--     longer shown is hidden on every row;
--   - a stored value the list does not know reads as Only Gold.
-- Driven here: the summary's own code, cut from the footer file, over recording frames; the
-- defaults line; the real cog block of the options page.
--   lua .tools/tests/test_bags_gold_summary_coins.lua        (from the repository root)
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
        if fails <= 14 then print("  FAIL: " .. msg) end
    end
end

local FOOTER = ReadSource("EllesmereUIBags/EUI_Bags_Footer.lua")
local DEFAULTS = ReadSource("EllesmereUIBags/EllesmereUIBags_DB.lua")
local OPTIONS = ReadSource("EllesmereUIOptions/EUI_Bags_Options.lua")
for name, src in pairs({ footer = FOOTER, defaults = DEFAULTS, options = OPTIONS }) do
    assert(loadstring(src, "=" .. name), "the " .. name .. " file does not compile")
end

-------------------------------------------------------------------------------
--  Recording frames. A text is 6 wide per letter and 14 per inline icon; colour
--  codes take no room.
-------------------------------------------------------------------------------
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:14|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:14|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:14|t"
local function TextWidth(text)
    local icons
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text, icons = text:gsub("|T.-|t", "")
    return #text * 6 + icons * 14
end

local made = 0
local function NewFontString()
    made = made + 1
    local fs = { shown = true, points = {} }
    function fs:SetFont(path, size, flags) self.font = { path, size, flags } end
    function fs:SetJustifyH(j) self.justify = j end
    function fs:SetText(t)
        assert(self.font, "a text was set on a font string with no font")
        self.text = t
    end
    function fs:GetText() return self.text end
    function fs:SetTextColor(r, g, b, a) self.color = { r, g, b, a } end
    function fs:Show() self.shown = true end
    function fs:Hide() self.shown = false end
    function fs:GetStringWidth() return TextWidth(self.text or "") end
    function fs:GetStringHeight() return self.font and self.font[2] or 0 end
    function fs:ClearAllPoints() self.points = {} end
    function fs:SetPoint(...) self.points[#self.points + 1] = { ... } end
    return fs
end
local NOOP = { __index = function() return function() end end }
local function NewGroup()
    local g = setmetatable({}, NOOP)
    function g:CreateAnimation() return setmetatable({}, NOOP) end
    return g
end
local TT
function CreateFrame()
    local f = setmetatable({ shown = true, points = {} }, NOOP)
    function f:CreateFontString() return NewFontString() end
    function f:CreateAnimationGroup() return NewGroup() end
    function f:SetSize(w, h) self.w, self.h = w, h end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:GetAlpha() return 1 end
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    TT = f
    return f
end
UIParent = {}
RAID_CLASS_COLORS = { MAGE = { r = 1, g = 0, b = 0 }, PRIEST = { r = 1, g = 1, b = 1 } }

-------------------------------------------------------------------------------
--  The summary's code, cut from the footer file
-------------------------------------------------------------------------------
local LEDGER = { tracking = true, chars = {}, warband = nil }
local GoldLedger = {
    IsTracking = function() return LEDGER.tracking end,
    Data = function() return LEDGER end,
    Chars = function() return LEDGER.chars end,
    Money = function() return 0 end,
}
local PROFILE = {}
-- The Bags font of the Fonts page
local FONT = "Fonts\\Bags.ttf"
local EUI = {
    GetGoldLedger = function() return GoldLedger end,
    L = function(s) return s end,
    GetFontPath = function() return FONT end,
    GetFontOutlineFlag = function() return "OUTLINE" end,
}
local chunk = "local EllesmereUI, BP = ...\n"
    .. Cut(FOOTER, "local GoldLedger = EllesmereUI.GetGoldLedger()\n", "local function PositionBagMoney(inset)\n", "the gold summary")
    .. "\nreturn ShowGoldTooltip, HideGoldTooltip, _goldTTRows, COIN_COLS\n"
local Show, Hide, ROWS, COIN_COLS = assert(loadstring(chunk, "=EUI_Bags_Footer.lua (gold summary)"))(EUI, function() return PROFILE end)
check(type(COIN_COLS) == "table" and COIN_COLS.gold == 1 and COIN_COLS.silver == 2 and COIN_COLS.copper == 3,
    "the three Show Coins values do not stand for one, two and three coin columns")
do
    local n = 0
    for _ in pairs(COIN_COLS or {}) do n = n + 1 end
    check(n == 3, "Show Coins knows " .. n .. " values, not three")
end

-------------------------------------------------------------------------------
--  What the summary should hold, worked out here on its own
-------------------------------------------------------------------------------
local function Commas(n)
    local s = tostring(math.floor(n))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
local ICONS = { GOLD, SILVER, COPPER }
local function Coins(money)
    return { Commas(money / 10000) .. GOLD, math.floor(money / 100) % 100 .. SILVER, money % 100 .. COPPER }
end
local HINT_W = TextWidth("Ctrl + Right-Click: Reset all data")
-- The rows in order (characters by name, the warband bank when it holds money, the total),
-- then the size and the right edge of every coin column for `cols` columns.
local function Expect(cols)
    local rows, total = {}, 0
    local ids = {}
    for id in pairs(LEDGER.chars) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return (LEDGER.chars[a].name or a) < (LEDGER.chars[b].name or b) end)
    for _, id in ipairs(ids) do
        local c = LEDGER.chars[id]
        local cc = RAID_CLASS_COLORS[c.class] or { r = 1, g = 1, b = 1 }
        rows[#rows + 1] = {
            name = ("|cff%02x%02x%02x"):format(cc.r * 255, cc.g * 255, cc.b * 255) .. (c.name or id) .. "|r",
            coins = Coins(c.money), color = { 1, 1, 1 },
        }
        total = total + c.money
    end
    local bank = LEDGER.warband and LEDGER.warband.money
    if bank and bank > 0 then
        rows[#rows + 1] = { name = "|cffffcc80Warbank|r", coins = Coins(bank), color = { 1, 0.8, 0.5 } }
        total = total + bank
    end
    rows[#rows + 1] = { name = "|cffffcc80Total|r", coins = Coins(total), color = { 1, 1, 0.5 }, total = true }
    local nameW, colW = 0, { 0, 0, 0 }
    for _, row in ipairs(rows) do
        nameW = math.max(nameW, TextWidth(row.name))
        for c = 1, cols do colW[c] = math.max(colW[c], TextWidth(row.coins[c])) end
    end
    local e = { rows = rows, right = {} }
    local w = 8 + nameW + 20
    for c = 1, cols do w = w + colW[c] + (c > 1 and 6 or 0) end
    e.w = math.max(w + 8, HINT_W + 16)
    local right = -8
    for c = cols, 1, -1 do
        e.right[c] = right
        right = right - colW[c] - 6
    end
    e.hintY = 8 + 11 + 6 + (#rows - 1) * 14 + 4 + 14 + 6
    e.h = e.hintY + 10 + 8
    return e
end

local anchor = {}
local function Point(fs, n) return fs.points[n] or {} end
-- Shows the summary under Show Coins = `mode` and checks every text of it against Expect.
local function Run(mode, cols, what)
    PROFILE.bagGoldCoins = mode
    Show(anchor)
    local e = Expect(cols)
    check(TT and TT.shown, what .. ": the summary is not shown")
    check(TT.w == e.w and TT.h == e.h, what .. ": the summary is " .. tostring(TT.w) .. " x " .. tostring(TT.h)
        .. ", expected " .. e.w .. " x " .. e.h)
    local p = Point(TT, 1)
    check(#TT.points == 1 and p[1] == "BOTTOMRIGHT" and p[2] == anchor and p[3] == "TOPRIGHT" and p[4] == 0 and p[5] == 4,
        what .. ": the summary does not hang over the footer's gold")
    check(TT._title.font[1] == FONT and TT._title.font[2] == 11 and TT._hint.font[1] == FONT and TT._hint.font[2] == 10,
        what .. ": the title or the hint is not in the Bags font")
    p = Point(TT._hint, 1)
    check(p[1] == "TOPLEFT" and p[4] == 8 and p[5] == -e.hintY, what .. ": the reset hint is not under the rows")
    for r, row in ipairs(e.rows) do
        local got = ROWS[r]
        local y = -(25 + (r - 1) * 14) - (row.total and 4 or 0)
        local name = got and got[0]
        check(name and name.shown and name.text == row.name, what .. ": row " .. r .. " is not " .. row.name)
        p = name and Point(name, 1) or {}
        check(name and #name.points == 1 and p[1] == "TOPLEFT" and p[2] == TT and p[3] == "TOPLEFT" and p[4] == 8 and p[5] == y,
            what .. ": row " .. r .. "'s name is not at the left edge of its line")
        check(name and name.justify == "LEFT" and name.font and name.font[1] == FONT and name.font[2] == 11
            and name.font[3] == "OUTLINE", what .. ": row " .. r .. "'s name is not in the Bags font, left-aligned")
        for c = 1, 3 do
            local fs = got and got[c]
            if c <= cols then
                check(fs and fs.shown and fs.text == row.coins[c], what .. ": row " .. r .. " coin " .. c .. " reads "
                    .. tostring(fs and fs.text) .. ", expected " .. row.coins[c])
                p = fs and Point(fs, 1) or {}
                check(fs and #fs.points == 1 and p[1] == "TOPRIGHT" and p[2] == TT and p[3] == "TOPRIGHT" and p[4] == e.right[c]
                    and p[5] == y, what .. ": row " .. r .. " coin " .. c .. " ends at " .. tostring(p[4]) .. ", expected "
                    .. tostring(e.right[c]))
                local col = fs and fs.color or {}
                check(col[1] == row.color[1] and col[2] == row.color[2] and col[3] == row.color[3] and col[4] == 1,
                    what .. ": row " .. r .. " coin " .. c .. " is not in the row's colour")
                check(fs and fs.justify == "RIGHT" and fs.font and fs.font[1] == FONT and fs.font[2] == 11,
                    what .. ": row " .. r .. " coin " .. c .. " is not in the Bags font, right-aligned")
            else
                check(not fs or not fs.shown, what .. ": row " .. r .. " still shows coin " .. c)
            end
        end
    end
    for r = #e.rows + 1, #ROWS do
        for c = 0, 3 do
            local fs = ROWS[r][c]
            check(not fs or not fs.shown, what .. ": the unused row " .. r .. " still shows text " .. c)
        end
    end
    return e
end
local function Texts()
    local n = 0
    for _, row in ipairs(ROWS) do
        for c = 0, 3 do
            if row[c] then n = n + 1 end
        end
    end
    return n
end

-------------------------------------------------------------------------------
--  1. Only Gold: the summary as it was before the setting
-------------------------------------------------------------------------------
LEDGER.chars = {
    a = { name = "Zephyrinathesilverhandpaladin", class = "MAGE", money = 12345678 },     -- 1,234g 56s 78c
    b = { name = "Aureliusthelongnamedbankalt", class = "PRIEST", money = 98765432199 },  -- 9,876,543g 21s 99c
    c = { name = "Mid", class = "NONE", money = 505 },                                    -- 0g 5s 5c
}
LEDGER.warband = { money = 70000 }
local base = made
local e = Run("gold", 1, "Only Gold")
-- its width is the names, 20 of room, the gold column and 8 on each side: the summary before the setting
check(e.w == 8 + TextWidth("Zephyrinathesilverhandpaladin") + 20 + TextWidth("9,876,543" .. GOLD) + 8 and e.w == 278
    and e.w > HINT_W + 16, "the wide ledger's own expectation is off")
check(e.rows[1].coins[1] == "9,876,543" .. GOLD and e.rows[2].coins[1] == "0" .. GOLD and e.rows[3].coins[1] == "1,234" .. GOLD,
    "the characters are not listed by name with their gold in thousands groups")
check(e.rows[4].name == "|cffffcc80Warbank|r" and e.rows[5].coins[1] == "9,877,784" .. GOLD, "the warband bank or the total is off")
-- two texts per row, no more: the silver and copper texts do not exist yet
check(Texts() == 10 and made - base == 12, "Only Gold made " .. (made - base) .. " texts for five rows (12 with the title and the hint)")
for r = 1, 5 do check(ROWS[r][2] == nil and ROWS[r][3] == nil, "Only Gold made a silver or copper text on row " .. r) end

-------------------------------------------------------------------------------
--  2. Gold and Silver, then Gold, Silver and Copper: the texts are made once
-------------------------------------------------------------------------------
e = Run("silver", 2, "Gold and Silver")
check(e.rows[1].coins[2] == "21" .. SILVER and e.rows[2].coins[2] == "5" .. SILVER and e.rows[3].coins[2] == "56" .. SILVER,
    "the silver of a character is not what is left under a gold, in whole silver")
check(e.right[2] == -8 and e.right[1] == -8 - TextWidth("56" .. SILVER) - 6, "the gold column does not end 6 before the silver column")
check(Texts() == 15 and made - base == 17, "Gold and Silver did not add exactly one text per row")
for r = 1, 5 do check(ROWS[r][3] == nil, "Gold and Silver made a copper text on row " .. r) end
e = Run("copper", 3, "Gold, Silver and Copper")
check(e.rows[1].coins[3] == "99" .. COPPER and e.rows[2].coins[3] == "5" .. COPPER and e.rows[3].coins[3] == "78" .. COPPER,
    "the copper of a character is not what is left under a silver")
check(e.right[3] == -8 and e.right[2] == -8 - TextWidth("99" .. COPPER) - 6
    and e.right[1] == e.right[2] - TextWidth("56" .. SILVER) - 6, "the three columns are not set right to left, 6 apart")
check(Texts() == 20 and made - base == 22, "Gold, Silver and Copper did not add exactly one text per row")
-- shown again, and back down: nothing new is made, the columns no longer shown hide
Run("copper", 3, "Gold, Silver and Copper again")
Run("silver", 2, "back to Gold and Silver")
Run("gold", 1, "back to Only Gold")
check(made - base == 22, "showing the summary again made new texts")

-------------------------------------------------------------------------------
--  3. Fewer characters: the unused rows hide whole, and the column widths start over
-------------------------------------------------------------------------------
Run("copper", 3, "the wide ledger once more")
LEDGER.chars = { c = { name = "Mid", class = "NONE", money = 505 } }
LEDGER.warband = { money = 0 }
e = Run("copper", 3, "one character, an empty warband bank")
check(#e.rows == 2 and e.w == HINT_W + 16, "one poor character: the summary is not as wide as its hint")
check(e.right[2] == -8 - TextWidth("5" .. COPPER) - 6 and e.right[1] == e.right[2] - TextWidth("5" .. SILVER) - 6,
    "the column widths of the last summary were kept")
-- another font picked on the Fonts page reaches the texts made earlier
FONT = "Fonts\\Other.ttf"
Run("gold", 1, "one character, Only Gold")
LEDGER.warband = nil
Run("silver", 2, "no warband bank at all")
-- more characters than ever: the new rows get the shown columns only
LEDGER.chars = {}
for i = 1, 7 do LEDGER.chars["k" .. i] = { name = "Char" .. i, class = "MAGE", money = i * 1010101 } end
local before = made
Run("silver", 2, "seven characters")
check(made - before == 3 * 3, "three new rows in Gold and Silver made " .. (made - before) .. " texts, not nine")

-------------------------------------------------------------------------------
--  4. A value the list does not know, and tracking off
-------------------------------------------------------------------------------
Run(nil, 1, "no value stored")
Run("platinum", 1, "an unknown value")
Run(true, 1, "a value of the wrong kind")
LEDGER.tracking = false
TT.shown = false
Show(anchor)
check(TT.shown == false, "the summary showed with gold tracking off")
LEDGER.tracking = true
LEDGER.chars = {}
Show(anchor)
check(TT.shown == false, "the summary showed with no character recorded")

-------------------------------------------------------------------------------
--  5. The default: Only Gold, and Gold and Silver on WoW Forever
-------------------------------------------------------------------------------
do
    local expr = DEFAULTS:match("\n%s*bagGoldCoins%s*=%s*(.-),\n")
    check(expr ~= nil, "the Bags defaults hold no bagGoldCoins")
    local f = expr and loadstring("local EllesmereUI = ... return " .. expr, "=bagGoldCoins")
    check(f and f({ IS_FOREVER = true }) == "silver", "on WoW Forever the default is not Gold and Silver")
    check(f and f({ IS_FOREVER = false }) == "gold" and f({}) == "gold", "off WoW Forever the default is not Only Gold")
    for _, src in pairs({ FOOTER, DEFAULTS, OPTIONS }) do
        check(not src:find("bagGoldShowSilverCopper", 1, true), "the yes / no key of the first build is still read or written")
    end
end

-------------------------------------------------------------------------------
--  6. The options: the cog on Gold Tracking and History holds the Show Coins dropdown
-------------------------------------------------------------------------------
do
    local block = Cut(OPTIONS, "                EllesmereUI.BuildInlineCog(iconsRow._rightRegion, {\n", "\n            end\n", "the Gold Tracking cog")
    local cog, region
    local tracking = true
    local db = { profile = { bagGoldCoins = "silver" } }
    local OEUI = {
        BuildInlineCog = function(rgn, opts) region, cog = rgn, opts end,
        GetGoldLedger = function() return { IsTracking = function() return tracking end } end,
    }
    local iconsRow = { _rightRegion = {} }
    assert(loadstring("local EllesmereUI, iconsRow, db = ...\n" .. block, "=the Gold Tracking cog"))(OEUI, iconsRow, db)
    check(cog and region == iconsRow._rightRegion, "the cog is not on the Gold Tracking and History half")
    cog = cog or {}
    check(cog.title == "Gold Tracking Options" and cog.disabledTooltip == "Gold Tracking and History",
        "the cog's title or its requirement text changed")
    check(cog.disabled and cog.disabled() == false, "the cog is locked with gold tracking on")
    tracking = false
    check(cog.disabled and cog.disabled() == true, "the cog is live with gold tracking off")
    local rows = cog.rows or {}
    local row = rows[1] or {}
    check(#rows == 1 and row.type == "dropdown" and row.label == "Show Coins", "the cog's one row is not the Show Coins dropdown")
    local values, order = row.values or {}, row.order or {}
    check(values.gold == "Only Gold" and values.silver == "Gold and Silver" and values.copper == "Gold, Silver and Copper",
        "the three choices do not read Only Gold, Gold and Silver, and Gold, Silver and Copper")
    check(#order == 3 and order[1] == "gold" and order[2] == "silver" and order[3] == "copper", "the choices are not listed from gold down")
    local n = 0
    for key in pairs(values) do
        n = n + 1
        check(COIN_COLS[key] ~= nil, "the summary does not know the choice " .. tostring(key))
    end
    check(n == 3, "the dropdown offers " .. n .. " choices")
    check(type(row.tooltip) == "string" and #row.tooltip > 0 and (row.ddWidth or 0) >= 180, "the dropdown has no tooltip, or is too narrow for its longest choice")
    check(row.get and row.get() == "silver", "the dropdown does not read the profile's value")
    if row.set then row.set("copper") end
    check(db.profile.bagGoldCoins == "copper", "a pick is not written to the profile")
    -- the toggle refreshes the page: its cog greys out with it
    local toggle = Cut(OPTIONS, '{ type="toggle", text="Gold Tracking and History",', "); y = y - h", "the Gold Tracking toggle")
    check(toggle:find("SetTracking(v)", 1, true) and toggle:find("EllesmereUI:RefreshPage()", 1, true),
        "the Gold Tracking and History toggle does not refresh the page")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("bags gold summary coins harness: %d checks, ok"):format(count))
