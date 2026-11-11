-- Stub harness: the Data Bars Gold block's tooltip roster groups each character
-- under the realm it was recorded on (its ruleset on WoW Forever), realms A-Z
-- and richest first within one, keeping the row cap (the live character always
-- shows, Shift shows everyone). Cuts GoldRosterByRealm out of
-- EllesmereUIDataBars/Blocks/Gold.lua and drives it; source checks pin the
-- tooltip to it.
--   lua .tools/tests/test_db_gold_roster_realms.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

local SRC = ReadSource("EllesmereUIDataBars/Blocks/Gold.lua")
local a = assert(SRC:find("local function GoldRosterByRealm(", 1, true), "GoldRosterByRealm missing")
local e = assert(SRC:find("\nend\n", a, true), "GoldRosterByRealm end missing")
local chunk = assert(loadstring(SRC:sub(a, e + 4) .. "\nreturn GoldRosterByRealm\n", "=roster"))
setfenv(chunk, setmetatable({ tsort = table.sort }, { __index = _G }))
local Roster = chunk()

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end
local function same(t, u)
    if #t ~= #u then return false end
    for i = 1, #t do if t[i] ~= u[i] then return false end end
    return true
end

-- The owner's report: one character per ruleset, seen from either character.
do
    local store = {
        magus = { realm = "Normal", money = 1849 },
        bane  = { realm = "PvP RP", money = 424 },
    }
    for _, selfKey in ipairs({ "magus", "bane" }) do
        local realms, byRealm, hidden = Roster(store, { "magus", "bane" }, false, selfKey, 10)
        check(same(realms, { "Normal", "PvP RP" }), "1: both rulesets head their own character (self " .. selfKey .. ")")
        check(byRealm["Normal"] and same(byRealm["Normal"], { "magus" }), "1: Normal lists Magus alone")
        check(byRealm["PvP RP"] and same(byRealm["PvP RP"], { "bane" }), "1: PvP RP lists Banetusk alone")
        check(hidden == 0, "1: nothing left out")
    end
end

-- Realms A-Z whatever the money order; richest first kept within a realm.
do
    local store = {
        z1 = { realm = "Zul'jin", money = 900 },
        a1 = { realm = "Area 52", money = 500 },
        z2 = { realm = "Zul'jin", money = 300 },
        a2 = { realm = "Area 52", money = 100 },
    }
    local realms, byRealm = Roster(store, { "z1", "a1", "z2", "a2" }, false, "a2", 10)
    check(same(realms, { "Area 52", "Zul'jin" }), "2: realms A-Z")
    check(same(byRealm["Area 52"], { "a1", "a2" }), "2: richest first within Area 52")
    check(same(byRealm["Zul'jin"], { "z1", "z2" }), "2: richest first within Zul'jin")
end

-- The row cap: ten rows, the live character always shows, Shift shows everyone.
do
    local store, keys = {}, {}
    for i = 1, 12 do
        local k = "c" .. i
        store[k] = { realm = (i % 2 == 0) and "B" or "A", money = 100 - i }
        keys[#keys + 1] = k
    end
    local realms, byRealm, hidden = Roster(store, keys, false, "c1", 10)
    local shown = #(byRealm.A or {}) + #(byRealm.B or {})
    check(shown == 10 and hidden == 2, "3: ten rows shown, two left out (" .. shown .. " / " .. hidden .. ")")
    realms, byRealm, hidden = Roster(store, keys, false, "c12", 10)
    shown = #(byRealm.A or {}) + #(byRealm.B or {})
    local selfShown = false
    for _, k in ipairs(byRealm.B or {}) do if k == "c12" then selfShown = true end end
    check(selfShown and shown == 11 and hidden == 1, "3: the live character past the cap still shows")
    realms, byRealm, hidden = Roster(store, keys, true, "c1", 10)
    shown = #(byRealm.A or {}) + #(byRealm.B or {})
    check(shown == 12 and hidden == 0, "3: Shift shows every character")
end

-- An entry with no realm goes under "?".
do
    local store = { x = { money = 5 }, y = { realm = "Normal", money = 1 } }
    local realms, byRealm = Roster(store, { "x", "y" }, false, "y", 10)
    check(same(realms, { "?", "Normal" }) and same(byRealm["?"], { "x" }), "4: a realm-less entry sits under ?")
end

-- The tooltip uses the grouping, not the current realm's name as one header.
do
    check(SRC:find("GoldRosterByRealm(store, charList, all, selfKey, 10)", 1, true) ~= nil, "5: the tooltip builds its roster through GoldRosterByRealm")
    check(SRC:find("Tip_AddLine(EllesmereUI.RealmGroupName()", 1, true) == nil, "5: no single current-realm header")
    check(SRC:find("ns.Tip_AddLine(realm, 0.5, 0.78, 1)", 1, true) ~= nil, "5: each realm gets its header")
    check(SRC:find('if realmCount > 1 then ns.Tip_AddLine(" ") end', 1, true) ~= nil, "5: the Warbank stands apart under several realms")
end

if fails > 0 then
    error(fails .. " check(s) failed")
end
print("test_db_gold_roster_realms: all checks passed")
