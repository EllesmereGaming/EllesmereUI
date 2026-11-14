-- Stub harness: one character's recorded gold.
--   lua .tools/tests/test_gold_ledger_money_of.lua        (from the repository root)
-- The real EllesmereUI_GoldLedger.lua is loaded whole over the real character roster (cut
-- from EllesmereUI.lua by the roster stub): GL.MoneyOf(key) reads one character's balance
-- from its roster entry, after the ledger has absorbed the stores of older builds, and
-- makes no table. The Bags offline view's gold reader (cut from
-- EllesmereUIBags_OfflineView.lua) shows the viewed character's balance through it: the
-- live balance for this character and for the warband tab, an alt's by its GUID, and by
-- its name key where an older build filed it, without listing every character.
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

local ME = "Player-1-ME"
local live = { money = 500, warband = 9000 }
EUI_CLIENT_BLOCKED = nil
issecretvalue = function() return false end
GetMoney = function() return live.money end
Enum = { BankType = { Account = 2 } }
C_Bank = { FetchDepositedMoney = function() return live.warband end }

-- A fresh account, the ledger and the roster of one session.
local function Session(db)
    EllesmereUIDB = db
    EllesmereUI = {}
    dofile(".tools/tests/char_roster_stub.lua")(EllesmereUI, { guid = ME, name = "Anna", realm = "Area 52" })
    assert(loadfile("EllesmereUI_GoldLedger.lua"))("EllesmereUI", {})
    return EllesmereUI.GetGoldLedger()
end

-------------------------------------------------------------------------------
-- 1. GL.MoneyOf
-------------------------------------------------------------------------------
do
    local GL = Session({ chars = {
        [ME] = { name = "Anna", gold = { money = 123 } },
        ["Player-1-B"] = { name = "Bob", gold = { money = 77, updated = 5 } },
        ["Player-1-Z"] = { name = "Zero", gold = { money = 0 } },
        ["Player-1-N"] = { name = "No Gold" },
        ["Player-1-X"] = { name = "Odd", gold = 55 },
        ["Old-Realm"] = { gold = { money = 31 } },
    } })
    check(type(GL.MoneyOf) == "function", "the ledger has no one-character reader")
    eq(GL.MoneyOf("Player-1-B"), 77, "an alt's balance")
    eq(GL.MoneyOf(ME), 123, "this character's recorded balance (not the live one)")
    eq(GL.MoneyOf("Player-1-Z"), 0, "a balance of nothing is 0, not unknown")
    eq(GL.MoneyOf("Old-Realm"), 31, "a balance an older build filed under the name")
    eq(GL.MoneyOf("Player-1-N"), nil, "a character with no balance recorded")
    eq(GL.MoneyOf("Player-1-X"), nil, "a balance that is no record")
    eq(GL.MoneyOf("Player-none"), nil, "a character the roster does not know")
    eq(GL.MoneyOf(nil), nil, "no key")
    -- it reads the same entries the full list is built from
    local all = GL.Chars()
    check(all["Player-1-B"].money == GL.MoneyOf("Player-1-B") and all["Player-1-Z"].money == 0 and all["Player-1-N"] == nil,
        "the one-character reader and the full list disagree")
    -- nothing is written by a read
    eq(EllesmereUIDB.chars["Player-none"], nil, "a read made a roster entry")
end
-- The balances of older builds are absorbed before the first read, whichever reader comes first.
do
    local GL = Session({ characterGold = { ["Bob-Area 52"] = { gold = 4400, class = "MAGE" } } })
    eq(GL.MoneyOf("Bob-Area 52"), 4400, "a balance still in an older build's store, read first through the one-character reader")
    eq(EllesmereUIDB.characterGold, nil, "the older store after the read")
end
-- No account data: nothing to read, and nothing is created.
do
    local GL = Session(nil)
    eq(GL.MoneyOf(ME), nil, "with no account data")
    eq(EllesmereUIDB, nil, "a read created the account data")
end

-------------------------------------------------------------------------------
-- 2. The offline view's gold
-------------------------------------------------------------------------------
do
    local GL = Session({ chars = {
        [ME] = { name = "Anna", gold = { money = 123 } },
        ["Player-1-B"] = { name = "Bob", gold = { money = 77 } },
        ["Player-1-Z"] = { name = "Zero", gold = { money = 0 } },
        ["Cara-Area 52"] = { gold = { money = 31 } },
        ["Dan-Area 52"] = { gold = { money = 8 } },
        ["Player-1-D"] = { name = "Dan", gold = { money = 64 } },
        ["Zero-Area 52"] = { gold = { money = 99 } },
    } })
    GL.Data().warband = { money = 1 }
    -- the saved inventories: by GUID, and three an older build filed by name (two know their GUID since)
    local saved = {
        [ME] = { guid = ME }, ["Player-1-B"] = { guid = "Player-1-B" }, ["Player-1-Z"] = { guid = "Player-1-Z" },
        ["Cara-Area 52"] = {}, ["Dan-Area 52"] = { guid = "Player-1-D" }, ["Player-1-Q"] = { guid = "Player-1-Q" },
        ["Zero-Area 52"] = { guid = "Player-1-Z" },
    }
    local lists = 0
    local listAll = GL.Chars
    GL.Chars = function(...) lists = lists + 1; return listAll(...) end
    local env = setmetatable({
        EUI = EllesmereUI,
        Offline = { CurrentKey = function() return ME end, Char = function(key) return key and saved[key] end },
        ShownKey = function(v) return v.key or ME end,
        TabKind = function(v) return v.tab end,
    }, { __index = _G })
    local VIEW = ReadSource("EllesmereUIBags/EllesmereUIBags_OfflineView.lua")
    local Gold = setfenv(assert(loadstring(Cut(VIEW, "local function Gold(v)\n", "\n-- everything the grid draws from", "the offline view's gold reader")
        .. "\nreturn Gold", "=the offline view")), env)()

    eq(Gold({ mode = "bags" }), 500, "this character: the live balance")
    eq(Gold({ mode = "bank", tab = "character" }), 500, "this character's own bank: the live balance")
    eq(Gold({ mode = "bank", tab = "warband" }), 9000, "the warband tab: the warband's live balance")
    eq(Gold({ mode = "bags", key = "Player-1-B" }), 77, "an alt, by its GUID")
    eq(Gold({ mode = "bank", tab = "character", key = "Player-1-B" }), 77, "an alt's bank")
    eq(Gold({ mode = "bags", key = "Player-1-Z" }), 0, "an alt with no gold shows 0")
    eq(Gold({ mode = "bags", key = "Cara-Area 52" }), 31, "an alt an older build filed by name")
    eq(Gold({ mode = "bags", key = "Dan-Area 52" }), 64, "an inventory filed by name whose character is known by GUID: the GUID's balance")
    eq(Gold({ mode = "bags", key = "Zero-Area 52" }), 0, "a GUID's balance of nothing still wins over one filed by name")
    eq(Gold({ mode = "bags", key = "Player-1-Q" }), nil, "an alt with no balance recorded")
    eq(Gold({ mode = "bags", key = "Nobody-Realm" }), nil, "a character with no saved inventory and no balance")
    eq(lists, 0, "times the view listed every character to show one balance")
    -- a balance recorded since shows at the next read
    EllesmereUIDB.chars["Player-1-Q"] = { gold = { money = 12 } }
    eq(Gold({ mode = "bags", key = "Player-1-Q" }), 12, "a balance recorded since")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_gold_ledger_money_of (%d checks)"):format(count))
