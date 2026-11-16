-- Stub harness: Forever Essentials > General > Favorites per Character.
--   lua .tools/tests/test_fe_pet_favorites_row.lua        (from the repository root)
-- The options row and the Auto Summon Pet runtime keep this character's switch in one
-- place, the character roster (EllesmereUI.CharData "petSummon"). The row is cut from
-- EUI_ForeverEssentials_General_Options.lua and run over the real roster (cut from
-- EllesmereUI.lua by the roster stub); what the runtime reads of it (its switch and the
-- character's own favorites) is cut from EllesmereUIForeverEssentials_PetSummon.lua.
local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        print("  FAIL: " .. tostring(msg))
    end
    return cond
end
local function eq(a, b, msg)
    return check(a == b, tostring(msg) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function ReadSource(name)
    local f = assert(io.open(name, "rb"), name .. " is missing")
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local function Cut(src, first, last, what)
    local a = assert(src:find(first, 1, true), what .. ": first line not found")
    local b = assert(src:find(last, a + #first, true), what .. ": last line not found")
    return src:sub(a, b - 1)
end

local GUID = "Player-1-AAAA"
EllesmereUIDB = {}
EllesmereUI = {}
local who = dofile(".tools/tests/char_roster_stub.lua")(EllesmereUI, { guid = GUID, name = "Ann", surname = "Vale" })
-- the game's own reader, which the row called before it read the roster
UnitGUID = function() return who.guid end

-- the feature's account settings, as the options reach them
local cfg, refreshes = { enabled = true }, 0
local PS = {
    Get = function(key) return cfg[key] end,
    Cfg = function() return cfg end,
    RefreshJournal = function() refreshes = refreshes + 1 end,
}

-- the row
local OPTIONS = ReadSource("EllesmereUIOptions/EUI_ForeverEssentials_General_Options.lua")
local rowSrc = Cut(OPTIONS, '{ type = "toggle", text = "Favorites per Character",', "\n        );  y = y - h", "the Favorites per Character row")
local row = setfenv(assert(loadstring("return " .. rowSrc, "=the options row")), setmetatable({ PS = PS }, { __index = _G }))()
check(type(row) == "table" and type(row.getValue) == "function" and type(row.setValue) == "function", "the row has no getter or setter")
eq(row.text, "Favorites per Character", "the row's label")
eq(row.disabledTooltip, "Auto Summon Pet", "the setting the row names while it is greyed")
check(row.disabled() == false, "the row is greyed while Auto Summon Pet is on")
cfg.enabled = false
check(row.disabled() == true, "the row is live while Auto Summon Pet is off")
cfg.enabled = true

-- what the runtime reads
local RUNTIME = ReadSource("EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_PetSummon.lua")
local summonable = {}
local R = setfenv(assert(loadstring(Cut(RUNTIME, "local function CharCfg(create)", "\nlocal ev = CreateFrame(", "the runtime's per-character readers")
    .. "\nreturn { OwnOn = OwnOn, IsOwnFavorite = IsOwnFavorite, SetOwnFavorite = SetOwnFavorite, OwnFavorites = OwnFavorites }", "=the runtime")),
    setmetatable({ C_PetJournal = { PetIsSummonable = function(pet) return summonable[pet] ~= false end } }, { __index = _G }))()

local function Mine() return EllesmereUIDB.chars and EllesmereUIDB.chars[GUID] and EllesmereUIDB.chars[GUID].petSummon end

-- a character that never touched it: off, and the read makes no table
check(row.getValue() == false and R.OwnOn() == false, "a new character reads Favorites per Character as on")
eq(Mine(), nil, "reading the row made this character's table")
eq(refreshes, 0, "a read refreshed the journal")

-- on: the runtime reads it at once, and it is stored on this character's roster entry
row.setValue(true)
check(row.getValue() == true, "ticked, the row still reads off")
check(R.OwnOn() == true, "ticked, the runtime still reads the account's favorites")
check(Mine() ~= nil and Mine().own == true, "the switch is not on this character's roster entry")
eq(cfg.chars, nil, "the switch was written into the feature's account settings")
eq(refreshes, 1, "journal refreshes after ticking")

-- this character's favorites are used while it is on
R.SetOwnFavorite("pet-1", true)
R.SetOwnFavorite("pet-2", true)
summonable["pet-2"] = false
local list = R.OwnFavorites()
check(#list == 1 and list[1] == "pet-1" and R.IsOwnFavorite("pet-2"), "the character's own favorites that can be summoned are not listed")

-- off again: stored as unset, the favorites stay for the next time
row.setValue(false)
check(row.getValue() == false and R.OwnOn() == false, "unticked, the row or the runtime still reads on")
check(Mine() ~= nil and rawget(Mine(), "own") == nil, "unticked, the switch is stored as false instead of unset")
check(Mine().favorites["pet-1"] == true and #R.OwnFavorites() == 0, "unticking dropped the favorites, or they are still used")
eq(refreshes, 2, "journal refreshes after unticking")
row.setValue(true)
eq(#R.OwnFavorites(), 1, "ticked again, the favorites are used again")

-- another character has its own switch
who.guid = "Player-1-BBBB"
check(row.getValue() == false and R.OwnOn() == false, "another character reads this character's switch")
who.guid = GUID
check(row.getValue() == true and R.OwnOn() == true, "back on the first character the switch is gone")

-- what the roster migration leaves: the switch on the roster entry, nothing in the old place
EllesmereUIDB = { chars = { [GUID] = { petSummon = { own = true, favorites = { ["pet-9"] = true } } } } }
cfg.chars = nil
check(row.getValue() == true and R.OwnOn() == true and R.OwnFavorites()[1] == "pet-9",
    "a switch the migration moved to the roster reads off in the options")

-- the character's identity is not readable yet: nothing is read, written or refreshed
local before = refreshes
who.guid = nil
check(row.getValue() == false, "with no character identity the row reads on")
row.setValue(true)
eq(refreshes, before, "with no character identity a tick refreshed the journal")
local n = 0
for _ in pairs(EllesmereUIDB.chars) do n = n + 1 end
check(n == 1 and cfg.chars == nil, "with no character identity a tick was stored somewhere")
who.guid = GUID

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_fe_pet_favorites_row (%d checks)"):format(count))
