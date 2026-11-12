-- Stub harness: the character roster (EllesmereUIDB.chars[guid][field]) and
-- the char_roster_v1 migration that folds the older per-character stores into it.
--   lua .tools/tests/test_char_roster.lua
local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end
local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local install = dofile(".tools/tests/char_roster_stub.lua")
local function Fresh(o)
    local EUI = {}
    o = install(EUI, o)
    return EUI, o
end

-- 1. no GUID, a secret GUID, no account DB: nothing read or made
do
    EllesmereUIDB = {}
    local EUI, o = Fresh({})
    check(EUI.CharGUID() == nil and EUI.CharData("x", true) == nil, "no GUID: nil")
    o.guid, o.secret = "Player-1", "Player-1"
    check(EUI.CharGUID() == nil and EUI.CharEntry(true) == nil, "secret GUID: nil")
    o.secret = nil
    EllesmereUIDB = nil
    check(EUI.Chars() == nil and EUI.CharData("x", true) == nil, "no DB: nil")
end

-- 2. reads make nothing; create builds the entry and the field
do
    EllesmereUIDB = {}
    local EUI = Fresh({ guid = "Player-1" })
    check(EUI.CharData("xpBar") == nil and EUI.CharEntry() == nil, "read: nil")
    check(Count(EllesmereUIDB.chars) == 0, "read: no entry made")
    local d = EUI.CharData("xpBar", true)
    check(type(d) == "table" and EllesmereUIDB.chars["Player-1"].xpBar == d, "create: filed under the GUID")
    check(EUI.CharData("xpBar") == d, "read after create: same table")
    EllesmereUIDB.chars["Player-1"].bad = 5
    check(EUI.CharData("bad") == nil, "a non-table field reads nil")
end

-- 3. name-keyed entries move onto the GUID once; fields already there win
do
    EllesmereUIDB = { chars = {
        ["Player-1"] = { gold = { money = 1 } },
        ["Bob-Normal"] = { gold = { money = 2 }, lastSpec = 62 },
        ["Bob-Silvermoon"] = { horoscope = { month = 3 } },
        ["Ann-Normal"] = { lastSpec = 71 },
    } }
    local EUI = Fresh({ guid = "Player-1", name = "Bob", realm = "Silvermoon", group = "Normal" })
    local mine = EUI.CharEntry()
    check(mine.gold.money == 1, "own field wins over a moved one")
    check(mine.lastSpec == 62 and mine.horoscope.month == 3, "both name keys moved")
    local chars = EllesmereUIDB.chars
    check(chars["Bob-Normal"] == nil and chars["Bob-Silvermoon"] == nil, "name keys dropped")
    check(chars["Ann-Normal"].lastSpec == 71, "another character's name key stays")
end

-- 4. a character with only a name-keyed entry gets one on its GUID
do
    EllesmereUIDB = { chars = { ["Bob-Realm"] = { xpBar = { gained = 4 } } } }
    local EUI = Fresh({ guid = "Player-9", name = "Bob" })
    check(EUI.CharData("xpBar").gained == 4 and EllesmereUIDB.chars["Bob-Realm"] == nil, "moved to a new entry")
end

-- 5. the map, forget and clear
do
    EllesmereUIDB = { chars = {
        ["Player-1"] = { timePlayed = { total = 1 }, gold = { money = 1 } },
        ["Player-2"] = { timePlayed = { total = 2 } },
        ["Player-3"] = { gold = { money = 3 } },
    } }
    local EUI = Fresh({ guid = "Player-1" })
    local map = EUI.CharFieldMap("timePlayed")
    check(Count(map) == 2 and map["Player-2"].total == 2, "map lists the characters holding the field")
    map["Player-2"] = nil
    check(EllesmereUIDB.chars["Player-2"] ~= nil, "the map is a copy of the keys")
    EUI.ForgetCharField("Player-2", "timePlayed")
    check(EllesmereUIDB.chars["Player-2"] == nil, "forget: an emptied entry goes")
    EUI.ClearCharField("gold")
    check(EllesmereUIDB.chars["Player-3"] == nil and EllesmereUIDB.chars["Player-1"].gold == nil
        and EllesmereUIDB.chars["Player-1"].timePlayed.total == 1, "clear: one field from all")
end

-- 6. identity: written at login, level-up and logout; unknown reads keep the stored value
do
    EllesmereUIDB = {}
    local EUI, o = Fresh({ guid = "Player-1", name = "Bob", surname = "Tinker", group = "Normal",
        realm = "Area 52", level = 12, faction = "Horde", now = 50 })
    o.fire("PLAYER_LOGIN")
    local c = EUI.CharEntry()
    check(c.name == "Bob Tinker" and c.realm == "Normal" and c.realmKey == "Area52" and c.class == "MAGE"
        and c.race == "Scourge" and c.level == 12 and c.faction == "Horde" and c.seen == 50, "login records who the character is")
    o.now = 60
    o.fire("PLAYER_LEVEL_UP", 13)
    check(c.level == 13 and c.seen == 60, "level-up records the new level")
    o.level, o.secret, o.now = 0, "Horde", 70
    o.faction = "Horde"
    o.fire("PLAYER_LOGOUT")
    check(c.level == 13 and c.faction == "Horde" and c.seen == 70, "unknown level and secret faction keep the stored values")
    o.guid = nil
    o.fire("PLAYER_LOGOUT")
    check(Count(EllesmereUIDB.chars) == 1, "no GUID: nothing written")
end

-- 7. char_roster_v1 folds every older store
do
    local fh = assert(io.open("EllesmereUI_Migration.lua", "rb"))
    local src = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    local s = assert(src:find("local CHAR_ROSTER_STORES", 1, true), "migration start not found")
    local e = select(2, assert(src:find('id          = "char_roster_v1".-\n}%)\n', s)))
    local spec
    local env = setmetatable({ EllesmereUI = { RegisterMigration = function(t) spec = t end } }, { __index = _G })
    local fn = assert(loadstring(src:sub(s, e), "@char_roster_v1"))
    setfenv(fn, env)
    fn()
    local db = {
        lastSpecByChar = { ["Player-1"] = 1490, ["Moo - Normal"] = 1485 },
        cdmCachedBarSizes = { ["Moo-Normal"] = { [1485] = { cooldowns = 1 } }, ["Unknown-Unknown"] = {} },
        qolUpgradeCalcChars = { ["Moo - Normal"] = { upgradeCalc = { queue = {} } } },
        timePlayedChars = { ["Player-1"] = { total = 5, level = 9, name = "Bob T", realm = "Normal", class = "MAGE" } },
        mailAltRoster = { ["Player-1"] = { name = "Bob", realm = "Normal", realmKey = "Normal", class = "MAGE",
            level = 10, faction = "Horde", seen = 99 } },
        travelHearths = { ["Ann - Normal"] = { name = "Ann", class = "ROGUE", bind = "Inn", readyAt = 0 } },
        mailAltHidden = { ["Player-2"] = true },
        goldLedger = { warband = { money = 0 }, chars = { ["Player-1"] = { money = 7, name = "Bob T", class = "MAGE" },
            ["Player-4"] = { money = 1, updated = 5, name = "Cy", realm = "PvP", class = "PRIEST" } } },
        petSummon = { enabled = true, chars = { ["Player-1"] = { own = true } } },
        groupFinderApps = { dungeon = { account = {}, chars = { ["Moo-Normal"] = { applied = 2 } } } },
        chars = { ["Player-1"] = { lastSpec = 1 } },
    }
    spec.body({ db = db })
    local c = db.chars
    check(c["Player-1"].lastSpec == 1, "an existing roster field wins")
    check(c["Player-1"].timePlayed.total == 5 and c["Player-1"].gold.money == 7
        and c["Player-1"].petSummon.own == true, "GUID keys move as is")
    check(c["Moo-Normal"].lastSpec == 1485 and c["Moo-Normal"].cdmBarSizes[1485].cooldowns == 1
        and c["Moo-Normal"].upgradeCalc.queue ~= nil and c["Moo-Normal"].groupFinderApps.applied == 2,
        "name keys of both separators land on one Name-Realm entry")
    check(c["Player-2"].mailAltHidden == true, "a non-table value moves")
    check(c["Unknown-Unknown"] == nil, "the CDM fallback key is dropped")
    local p1 = c["Player-1"]
    check(p1.name == "Bob" and p1.realm == "Normal" and p1.realmKey == "Normal" and p1.level == 10
        and p1.faction == "Horde" and p1.seen == 99 and p1.mailAlt == nil, "the mail roster entry becomes the identity")
    check(p1.timePlayed.name == nil and p1.timePlayed.realm == nil and p1.timePlayed.level == 9,
        "time played keeps its own level, not the name")
    check(p1.gold.name == nil and p1.gold.class == nil and p1.gold.money == 7, "gold keeps only its balance")
    local p4 = c["Player-4"]
    check(p4.name == "Cy" and p4.realm == "PvP" and p4.class == "PRIEST" and p4.gold.updated == 5,
        "a character only gold knew gets its identity from gold")
    local ann = c["Ann-Normal"]
    check(ann.name == "Ann" and ann.class == "ROGUE" and ann.travelHearth.name == nil
        and ann.travelHearth.bind == "Inn", "travel lifts its name and class")
    check(db.lastSpecByChar == nil and db.timePlayedChars == nil and db.goldLedger.chars == nil
        and db.goldLedger.warband ~= nil and db.petSummon.chars == nil and db.petSummon.enabled == true
        and db.groupFinderApps.dungeon.chars == nil, "old stores dropped, their other keys kept")
    spec.body({ db = db })
    check(c["Player-1"].lastSpec == 1 and c["Moo-Normal"].lastSpec == 1485, "a second run changes nothing")
end

if fails > 0 then
    print(fails .. " failure(s)")
    os.exit(1)
end
print("ok")
