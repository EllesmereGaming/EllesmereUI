-- Loads the real character roster (EllesmereUI.Chars, CharGUID, CharEntry,
-- CharData, CharFieldMap, ForgetCharField, ClearCharField) from
-- EllesmereUI.lua onto a test's EllesmereUI stub.
--   dofile(".tools/tests/char_roster_stub.lua")(EllesmereUI, { guid = "Player-1" })
-- o: guid, name, surname, realm, group (RealmGroupName), class, race, level,
-- faction, now (time()), secret (a value issecretvalue flags). Fields can
-- change between calls; the roster reads them live. o.fire(event, ...) runs
-- the identity recorder's event handler.
-- Stubbed helpers (PlainString, WithSurname, RealmGroupName) are only set
-- when the test's EllesmereUI lacks them.
return function(EUI, o, path)
    local fh = assert(io.open(path or "EllesmereUI.lua", "rb"))
    local src = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    local s = assert(src:find("%-%-  Per%-character data: EllesmereUIDB%.chars"), "roster section not found")
    s = src:sub(1, s):match(".*()\n") or 1
    local e = assert(src:find("\n%-%- \"Name%-Realm\" whisper/invite target%.", s), "roster section end not found")
    o = o or {}
    -- rawget: a test's EllesmereUI may answer every missing field with a stub
    EUI.RealmGroupName = rawget(EUI, "RealmGroupName") or function() return o.group or o.realm or "Realm" end
    EUI.PlainString = rawget(EUI, "PlainString") or function(v)
        if type(v) == "string" and v ~= o.secret and v ~= "" then return v end
    end
    EUI.WithSurname = rawget(EUI, "WithSurname") or function(n, s) return s and (n .. " " .. s) or n end
    local handler
    local env = setmetatable({
        CreateFrame = function()
            return { RegisterEvent = function() end, SetScript = function(_, _, fn) handler = fn end }
        end,
        UnitNameUnmodified = function() return o.name or "Tester", o.surname end,
        UnitClass = function() return "Mage", o.class or "MAGE" end,
        UnitRace = function() return "Undead", o.race or "Scourge" end,
        UnitLevel = function() return o.level or 10 end,
        UnitFactionGroup = function() return o.faction or "Alliance" end,
        time = function() return o.now or 1000 end,
        EllesmereUI = EUI,
        UnitGUID = function() return o.guid end,
        UnitName = function() return o.name or "Tester" end,
        GetRealmName = function() return o.realm or "Realm" end,
        GetNormalizedRealmName = function() return (o.realm or "Realm"):gsub("[%s%-]", "") end,
        issecretvalue = function(v) return v ~= nil and v == o.secret end,
    }, { __index = _G })
    local fn = assert(loadstring(src:sub(s, e), "@roster"))
    setfenv(fn, env)
    fn()
    o.fire = function(event, ...) handler(nil, event, ...) end
    return o
end
