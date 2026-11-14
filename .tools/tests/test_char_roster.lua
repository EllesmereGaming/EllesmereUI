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

    -- WoW Forever: the Mail card's surname joins the name; the ruleset is the mail key
    env.EllesmereUI.IS_FOREVER = true
    local fv = {
        mailAltRoster = { ["Player-7"] = { name = "Ann", surname = "Vale", realm = "PvP", realmKey = "PvP" } },
        timePlayedChars = { ["Player-8"] = { total = 1, name = "Cy Dorn", realm = "Normal" } },
    }
    spec.body({ db = fv })
    check(fv.chars["Player-7"].name == "Ann Vale" and fv.chars["Player-7"].surname == nil, "Forever name with surname")
    check(fv.chars["Player-8"].realmKey == "Normal", "Forever realmKey is the ruleset")
    env.EllesmereUI.IS_FOREVER = nil
end

-- 8. the once-a-session adoption waits for a real name: before login, the game's placeholder for a name it
--    has not loaded moves nothing and the next read tries again; after login a name is the character's own
do
    UNKNOWNOBJECT = "Unknown"
    local loggedIn = false
    IsLoggedIn = function() return loggedIn end
    EllesmereUIDB = { chars = { ["Bob-Realm"] = { xpBar = { gained = 4 } }, ["Unknown-Realm"] = { xpBar = { gained = 9 } } } }
    local EUI, o = Fresh({ guid = "Player-9", name = "Unknown" })
    check(EUI.CharData("xpBar") == nil and EllesmereUIDB.chars["Bob-Realm"] ~= nil and EllesmereUIDB.chars["Unknown-Realm"] ~= nil,
        "before login a name the game has not loaded moves nothing")
    o.name = "Bob"
    check(EUI.CharData("xpBar") ~= nil and EUI.CharData("xpBar").gained == 4 and EllesmereUIDB.chars["Bob-Realm"] == nil,
        "once the name reads, the character's entries move")
    check(EllesmereUIDB.chars["Unknown-Realm"] ~= nil, "an entry under the placeholder is nobody's")
    EllesmereUIDB = { chars = { ["Unknown-Realm"] = { xpBar = { gained = 9 } } } }
    loggedIn = true
    local EUI2 = Fresh({ guid = "Player-8", name = "Unknown" })
    check(EUI2.CharData("xpBar") ~= nil and EUI2.CharData("xpBar").gained == 9, "after login a name equal to the placeholder is the character's own")
    UNKNOWNOBJECT, IsLoggedIn = nil, nil
end

-- 9. the quest tracker's per-character sets (both accessors, cut from their files): while the GUID is unread
--    the table handed out has the same sets, is not kept and is stored nowhere; once it reads, the roster's
do
    local function ReadFile(p)
        local f = assert(io.open(p, "rb"))
        local s = f:read("*a"):gsub("\r\n", "\n")
        f:close()
        return s
    end
    local TAIL = "\n    return sv\nend\n"
    for _, case in ipairs({
        { "EllesmereUIQuestTracker/EllesmereUIQuestTracker_Custom.lua", "local charDB\nlocal function CharDB()", "questTracker",
          { "ctUntracked", "ctCollapsed", "ctDoneOpen", "ctPinned" } },
        { "EllesmereUIQuestTracker/EllesmereUIQuestTracker_Forever.lua", 'local CHAR_SETS = { "hidden", "exempt", "auto", "declined" }', "questWatch",
          { "hidden", "exempt", "auto", "declined" } },
    }) do
        local file, field, sets = case[1], case[3], case[4]
        local src = ReadFile(file)
        local a = assert(src:find(case[2], 1, true), file .. ": the accessor was not found")
        local b = assert(src:find(TAIL, a, true), file .. ": the accessor's end was not found")
        EllesmereUIDB = {}
        local EUI, o = Fresh({})
        local CharDB = setfenv(assert(loadstring(src:sub(a, b + #TAIL - 1) .. "\nreturn CharDB", "=" .. file)),
            setmetatable({ EllesmereUI = EUI }, { __index = _G }))()
        local function HasSets(t)
            for _, k in ipairs(sets) do
                if type(t[k]) ~= "table" then return false end
            end
            return true
        end
        local t1 = CharDB()
        check(type(t1) == "table" and HasSets(t1), file .. ": the sets are missing while the GUID is unread")
        check(CharDB() ~= t1, file .. ": the table handed out while the GUID is unread is kept")
        check(Count(EllesmereUIDB.chars or {}) == 0, file .. ": something was stored while the GUID is unread")
        o.guid = "Player-1"
        local t2 = CharDB()
        check(t2 ~= t1 and HasSets(t2) and EllesmereUIDB.chars["Player-1"][field] == t2, file .. ": once the GUID reads, the table is not the roster's")
        o.guid = nil
        check(CharDB() == t2, file .. ": the roster's table is not kept once read")
    end
end

-- 10. per-character data never rides a full export: the roster, and the one per-character store kept outside
--     it (the Kick Tracker's markers of the group's current instance)
do
    local fh = assert(io.open("EllesmereUI_Profiles.lua", "rb"))
    local src = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    local a = assert(src:find("local FULL_EXPORT_EXCLUDED = {", 1, true), "the export exclusions were not found")
    local b = assert(src:find("\n}\n", a, true), "the end of the export exclusions was not found")
    local excluded = assert(loadstring(src:sub(a, b + 2) .. "\nreturn FULL_EXPORT_EXCLUDED", "=the export exclusions"))()
    check(excluded.chars == true, "the roster rides a full export")
    check(excluded.kickMarkers == true, "the Kick Tracker's per-character markers ride a full export")
end

-- 11. a module that calls a roster helper names it in its stale-parent guard (an older parent has none of
--     them): every Lua file a module's TOC lists is read for the helpers it calls
do
    local HELPERS = { "CharGUID", "Chars", "CharEntry", "CharData", "CharFieldMap", "ForgetCharField", "ClearCharField" }
    local MODULES = { "ActionBars", "AuraBuffReminders", "Bags", "BlizzardSkin", "Chat", "CooldownManager", "DamageMeters",
        "DataBars", "ForeverEssentials", "Friends", "GroupFinder", "LoadoutManager", "Minimap", "MythicTimer", "Nameplates",
        "QoL", "QuestTracker", "Quickdraw", "RaidFrames", "ResourceBars", "SimpleLootCouncil", "UnitFrames" }
    local function Read(p)
        local f = io.open(p, "rb")
        if not f then return nil end
        local s = f:read("*a"):gsub("\r\n", "\n")
        f:close()
        return s
    end
    local users = 0
    for _, short in ipairs(MODULES) do
        local folder = "EllesmereUI" .. short
        local toc = Read(folder .. "/" .. folder .. ".toc") or Read(folder .. "/" .. folder .. "_Camelot.toc")
        check(toc ~= nil, folder .. ": no TOC found")
        if toc then
            local used = {}
            for line in toc:gmatch("[^\n]+") do
                local path = line:match("^%s*([^#%s][^%[]-%.lua)%s*%[?")
                if path and not path:find("..", 1, true) then
                    local src = Read(folder .. "/" .. path:gsub("\\", "/"))
                    if src then
                        for _, name in ipairs(HELPERS) do
                            if src:find("EllesmereUI%." .. name .. "%f[^%w_]") or src:find("%f[%w_]EUI%." .. name .. "%f[^%w_]") then
                                used[name] = true
                            end
                        end
                    end
                end
            end
            if next(used) then
                users = users + 1
                local main = Read(folder .. "/" .. folder .. ".lua") or ""
                local guard
                for line in main:gmatch("[^\n]+") do
                    if line:find("stale-parent guard", 1, true) then guard = line:match("^(.-)%) then EUI_CLIENT_BLOCKED") break end
                end
                check(guard ~= nil, folder .. ": calls the roster but has no stale-parent guard")
                for _, name in ipairs(HELPERS) do
                    if used[name] then
                        check(guard ~= nil and (guard .. " "):find("EllesmereUI%." .. name .. "%f[^%w_]") ~= nil,
                            folder .. ": calls EllesmereUI." .. name .. " without naming it in its stale-parent guard")
                    end
                end
            end
        end
    end
    check(users >= 10, "only " .. users .. " modules were found calling the roster (the scan reads too little)")
end

if fails > 0 then
    print(fails .. " failure(s)")
    os.exit(1)
end
print("ok")
