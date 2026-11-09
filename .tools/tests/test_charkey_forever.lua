-- Stub harness: EllesmereUI.CharKey keys WoW Forever characters by GUID and
-- moves what older builds filed under "Name<sep>Ruleset" / "Name<sep>Realm";
-- retail keys stay "Name<sep>Realm". Also checks that the Cooldown Manager
-- hands all three of its per-character stores to CharKey.
--   lua .tools/tests/test_charkey_forever.lua [EllesmereUI.lua] [EUI_CDM_Spec.lua]
local MAIN = (arg and arg[1]) or "EllesmereUI.lua"
local SPEC = (arg and arg[2]) or "EllesmereUICooldownManager/EUI_CDM_Spec.lua"

local function Read(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a")
    fh:close()
    return (s:gsub("\r\n", "\n"))
end

-- The text from the line holding `startPat` to the first column-0 "end" after it.
local function Cut(src, startPat, what)
    local s = src:find(startPat)
    assert(s, what .. ": start not found")
    s = src:sub(1, s):match(".*()\n") or 1
    local e = select(2, src:find("\nend\n", s))
    assert(e, what .. ": end not found")
    return src:sub(s, e)
end

local MAIN_SRC = Read(MAIN)
local ADOPT = Cut(MAIN_SRC, "local function AdoptCharEntry", "AdoptCharEntry")
local CHARKEY = Cut(MAIN_SRC, "function EllesmereUI%.CharKey", "CharKey")
local GETKEY = Cut(Read(SPEC), "function ns%.GetCharKey", "ns.GetCharKey")

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-- A fresh CharKey over its own stubs.
local function Load(o)
    local env = setmetatable({
        EllesmereUI = {
            IS_FOREVER = o.forever,
            RealmGroupName = function() return o.group end,
        },
        UnitName = function() return o.name, o.surname end,
        UnitGUID = function() return o.guid end,
        GetRealmName = function() return o.realm end,
        issecretvalue = function(v) return v ~= nil and v == o.secret end,
    }, { __index = _G })
    local fn = assert(loadstring(ADOPT .. CHARKEY, "@CharKey"))
    setfenv(fn, env)
    fn()
    return env.EllesmereUI.CharKey
end

local function Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local A, B = "Player-4-0AAAAAAA", "Player-4-0BBBBBBB"
local function Fv(guid) return { forever = true, name = "Bob", surname = "Smith", group = "Normal", realm = "Dreamscythe", guid = guid } end

-- 1. Retail: "Name<sep>Realm", and the store is never touched.
do
    local CharKey = Load({ forever = false, name = "Bob", group = "Silvermoon", realm = "Silvermoon", guid = A })
    local store = { ["Bob - Normal"] = 1, ["Bob - Silvermoon"] = 2 }
    check(CharKey(" - ", store) == "Bob - Silvermoon", "retail key is not Name - Realm")
    check(store["Bob - Normal"] == 1 and store["Bob - Silvermoon"] == 2 and Count(store) == 2, "retail touched the store")
end

-- 2. Forever: the GUID, and the first-name ruleset entry moves to it.
local shared = { ["Bob - Normal"] = "merged" }
do
    local CharKey = Load(Fv(A))
    check(CharKey(" - ", shared) == A, "Forever key is not the GUID")
    check(shared[A] == "merged" and shared["Bob - Normal"] == nil and Count(shared) == 1,
        "the first-name entry did not move to the GUID")
end

-- 3. A second character with the same first name gets its own GUID and takes
-- nothing from the first one; the first one keeps its entry on later calls.
do
    local CharKey = Load(Fv(B))
    check(CharKey(" - ", shared) == B, "second character's key is not its GUID")
    check(shared[A] == "merged" and shared[B] == nil and Count(shared) == 1, "second character touched the first one's entry")
    CharKey = Load(Fv(A))
    check(CharKey(" - ", shared) == A and shared[A] == "merged" and Count(shared) == 1, "repeat call changed the entry")
end

-- 4. The older realm-name entry moves too.
do
    local store = { ["Bob-Dreamscythe"] = "old" }
    check(Load(Fv(A))("-", store) == A and store[A] == "old" and Count(store) == 1, "the realm-name entry did not move")
end

-- 5. Both old entries: the newer ruleset one wins, both old keys go.
do
    local store = { ["Bob-Normal"] = "newer", ["Bob-Dreamscythe"] = "older" }
    Load(Fv(A))("-", store)
    check(store[A] == "newer" and Count(store) == 1, "both old entries: wrong winner or a leftover key")
end

-- 6. An entry already under the GUID stays; old keys still go.
do
    local store = { [A] = "mine", ["Bob-Normal"] = "stale" }
    Load(Fv(A))("-", store)
    check(store[A] == "mine" and Count(store) == 1, "an existing GUID entry was replaced or the old key stayed")
end

-- 7. Several stores in one call; nil stores are skipped.
do
    local s1, s3 = { ["Bob-Normal"] = 1 }, { ["Bob-Normal"] = 3 }
    check(Load(Fv(A))("-", s1, nil, s3) == A, "several stores: wrong key")
    check(s1[A] == 1 and s3[A] == 3 and Count(s1) == 1 and Count(s3) == 1, "several stores: not every store moved")
    check(Load(Fv(A))("-") == A, "no stores: wrong key")
end

-- 8. An unreadable or secret GUID gives no key and changes nothing.
do
    local store = { ["Bob-Normal"] = 1 }
    check(Load(Fv(nil))("-", store) == nil and store["Bob-Normal"] == 1 and Count(store) == 1, "nil GUID: key or move")
    local o = Fv(A)
    o.secret = A
    check(Load(o)("-", store) == nil and store["Bob-Normal"] == 1 and Count(store) == 1, "secret GUID: key or move")
end

-- 9. The Cooldown Manager passes its three stores, "-" as the separator, and
-- falls back to "Unknown-Unknown".
do
    local got
    local env = setmetatable({
        ns = {},
        EllesmereUIDB = { cdmCachedBarSizes = {}, cdmRepopulatePending = {}, cdmRepopulateDone = {} },
        EllesmereUI = { CharKey = function(...) got = { n = select("#", ...), ... }; return A end },
    }, { __index = _G })
    local fn = assert(loadstring(GETKEY, "@GetCharKey"))
    setfenv(fn, env)
    fn()
    local db = env.EllesmereUIDB
    check(env.ns.GetCharKey() == A, "GetCharKey did not return CharKey's key")
    check(got and got[1] == "-" and got[2] == db.cdmCachedBarSizes and got[3] == db.cdmRepopulatePending
        and got[4] == db.cdmRepopulateDone, "GetCharKey does not pass the three CDM stores")
    env.EllesmereUI.CharKey = function() return nil end
    check(env.ns.GetCharKey() == "Unknown-Unknown", "GetCharKey fallback")
    env.EllesmereUIDB = nil
    env.EllesmereUI.CharKey = function(...) got = { n = select("#", ...), ... }; return A end
    check(env.ns.GetCharKey() == A, "GetCharKey without a DB")
end

if fails > 0 then error(fails .. " check(s) failed") end
print("PASS test_charkey_forever")
