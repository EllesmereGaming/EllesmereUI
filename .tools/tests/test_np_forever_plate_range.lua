-- Stub harness: the range nameplates show at on WoW Forever.
--   lua .tools/tests/test_np_forever_plate_range.lua        (from the repository root)
-- WoW Forever caps nameplateMaxDistance at its own default, and a value above the
-- cap shortens the range instead of being clamped.
--   1. The module's write: the real EUI_Nameplates_CastState.lua is loaded whole per
--      client and its CVar setup run: the setting goes to 45 on WoW Forever and to 60
--      on retail, once, under the module's name, and every other CVar it writes is
--      the same on both clients.
--   2. The value an older build left with a player whose Nameplates module is off:
--      the real EllesmereUI_Uninstall.lua is loaded whole per case and its login pass
--      run. On WoW Forever the setting goes back to the game's default, once, while
--      it still reads EllesmereUI's value and that is above the default; a value the
--      player set, another client, another setting, a module that is on (here, or
--      for another character where the setting is shared) and a refused write all
--      leave it alone.
local fails, count = 0, 0
local function check(cond, msg)
    count = count + 1
    if not cond then
        fails = fails + 1
        if fails <= 40 then print("  FAIL: " .. tostring(msg)) end
    end
    return cond
end
local function eq(a, b, msg)
    return check(a == b, tostring(msg) .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

local MODULE = "EllesmereUINameplates"

-------------------------------------------------------------------------------
-- 1. The module's write
-------------------------------------------------------------------------------
local function ModuleWrites(forever)
    local writes = {}
    EUI_CLIENT_BLOCKED = nil
    CreateFrame = function()
        return setmetatable({}, { __index = function() return function() end end })
    end
    C_NamePlate = {}
    NamePlateConstants, Enum = nil, nil
    NamePlateDriverFrame, NamePlateFriendlyFrameOptions = nil, nil
    InCombatLockdown = function() return false end
    hooksecurefunc = function() end
    EllesmereUIDB = nil
    EllesmereUI = {
        IS_FOREVER = forever,
        SetCVar = function(name, value, owner)
            writes[#writes + 1] = { name = name, value = value, owner = owner }
            return true
        end,
        SetCVarBitfield = function() return true end,
    }
    local ns = { RefreshStackingMotion = function() end, RefreshHitboxSize = function() end }
    local I = { defaults = {}, GetHealthBarWidth = function() return 150 end, profileSetters = {} }
    ns._npInternals = I
    assert(loadfile("EllesmereUINameplates/EUI_Nameplates_CastState.lua"))(MODULE, ns)
    assert(I.broken == false, "EUI_Nameplates_CastState.lua did not load to its end")
    I.SetupAuraCVars()
    return writes
end

local function Others(writes)
    local out = {}
    for _, w in ipairs(writes) do
        if w.name ~= "nameplateMaxDistance" then
            out[#out + 1] = w.name .. "=" .. tostring(w.value) .. "/" .. tostring(w.owner)
        end
    end
    return table.concat(out, ";")
end

do
    local retail = ModuleWrites(false)
    local others = Others(retail)
    for _, c in ipairs({ { "retail", false, 60 }, { "a client with no flag", nil, 60 }, { "WoW Forever", true, 45 } }) do
        local writes = ModuleWrites(c[2])
        local n, got, owner = 0, nil, nil
        for _, w in ipairs(writes) do
            if w.name == "nameplateMaxDistance" then n, got, owner = n + 1, w.value, w.owner end
        end
        eq(n, 1, c[1] .. ": writes of nameplateMaxDistance")
        eq(got, c[3], c[1] .. ": the nameplate range written")
        eq(type(got), "number", c[1] .. ": the type of the range written")
        eq(owner, MODULE, c[1] .. ": the module the write is recorded under")
        eq(Others(writes), others, c[1] .. ": the other CVars the setup writes, with their values, as on retail")
        check(#writes > 15, c[1] .. ": the setup wrote " .. #writes .. " CVars only")
    end
end

-------------------------------------------------------------------------------
-- 2. The login pass of the settings recorder
-------------------------------------------------------------------------------
local GUID = "Player-1-0000ABCD"
local KEY = "nameplatemaxdistance"

-- One login. o: forever, addon (the loading addon's name), cvars / defaults (by lower-case
-- name), perChar (set of per-character CVars), acct / char (the recorded CVars of the
-- account and of this character), loaded (set of loaded modules), enabled (set of modules
-- on for some character), combat, refuse (set of CVars whose write the game refuses).
local function Login(o)
    local cvars, sets, deferred, frames, hook = {}, {}, {}, {}, nil
    for k, v in pairs(o.cvars or {}) do cvars[k] = v end
    local defaults, perChar, refuse = o.defaults or {}, o.perChar or {}, o.refuse or {}
    local loaded, enabled = o.loaded or {}, o.enabled or {}
    EUI_CLIENT_BLOCKED = nil
    Enum = { AddOnEnableState = { None = 0, Some = 1, All = 2 } }
    C_CVar = {
        GetCVar = function(name) return cvars[name:lower()] end,
        SetCVar = function(name, value)
            name = name:lower()
            if refuse[name] then return false end
            sets[#sets + 1] = name .. "=" .. tostring(value)
            cvars[name] = tostring(value)
            return true
        end,
        GetCVarBitfield = function() return nil end,
        SetCVarBitfield = function() return true end,
        GetCVarInfo = function(name) return cvars[name:lower()], defaults[name:lower()], false, perChar[name:lower()] == true end,
        GetCVarDefault = function(name) return defaults[name:lower()] end,
    }
    C_AddOns = {
        IsAddOnLoaded = function(n) return loaded[n] == true end,
        DoesAddOnExist = function() return true end,
        GetAddOnEnableState = function(n) return (loaded[n] or enabled[n]) and 2 or 0 end,
    }
    UnitGUID = function() return GUID end
    InCombatLockdown = function() return o.combat == true end
    CreateFrame = function()
        local f = { events = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterAllEvents() self.events = {} end
        function f:SetScript(name, fn) self[name] = fn end
        frames[#frames + 1] = f
        return f
    end
    local record = { cvar = o.acct, chars = o.char and { [GUID] = { cvar = o.char } } or nil }
    EllesmereUIDB = { restoreOnUninstall = record, profiles = { Default = { addons = { [MODULE] = { x = 1 } } } } }
    EllesmereUI = {
        IS_FOREVER = o.forever,
        Lite = { OnSavedVariablesLoaded = function(fn) hook = fn end, StoreFromBeforeLoad = function() return false end },
        CombatQueue = { Defer = function(_, fn) deferred[#deferred + 1] = fn end },
    }
    assert(loadfile("EllesmereUI_Uninstall.lua"))(o.addon or "EllesmereUI", {})
    hook()
    for _, f in ipairs(frames) do
        if f.events.PLAYER_LOGIN and f.OnEvent then f.OnEvent(f, "PLAYER_LOGIN") end
    end
    local w = { cvars = cvars, sets = sets, deferred = deferred, record = record }
    function w.Acct(key) return record.cvar and record.cvar[key] end
    function w.Char(key)
        local c = record.chars and record.chars[GUID]
        return c and c.cvar and c.cvar[key]
    end
    return w
end

local function Left(a, b, owner) return { a = a, b = b, o = owner or MODULE } end
local function Sets(w) return table.concat(w.sets, ";") end
local D45 = { [KEY] = "45" }

-- the case itself: the module off for every character, EllesmereUI's 60 still set, no
-- snapshot to go back to
do
    local w = Login({ forever = true, cvars = { [KEY] = "60" }, defaults = D45, acct = { [KEY] = Left("60") } })
    eq(w.cvars[KEY], "45", "WoW Forever, module off: the range goes back to the game's default")
    eq(Sets(w), KEY .. "=45", "WoW Forever, module off: the CVars written")
    eq(w.Acct(KEY), nil, "WoW Forever, module off: the record is dropped once the value is back")
    -- the next login finds no record: a 60 the player sets by hand afterwards is theirs
    local again = Login({ forever = true, cvars = { [KEY] = "60" }, defaults = D45 })
    eq(again.cvars[KEY] .. "|" .. Sets(again), "60|", "a 60 with no record of ours is left alone")
end
-- the default is read from the game, not written as a number of ours
do
    local w = Login({ forever = true, cvars = { [KEY] = "60" }, defaults = { [KEY] = "50" }, acct = { [KEY] = Left("60") } })
    eq(w.cvars[KEY] .. "|" .. Sets(w), "50|" .. KEY .. "=50", "the value put back is the game's own default")
    eq(w.Acct(KEY), nil, "another default: the record is dropped")
end
-- any value of ours above the default; none at or below it
do
    local w = Login({ forever = true, cvars = { [KEY] = "50" }, defaults = D45, acct = { [KEY] = Left("50") } })
    eq(w.cvars[KEY] .. "|" .. Sets(w), "45|" .. KEY .. "=45", "a value of ours above the default goes back")
    for _, v in ipairs({ "45", "40" }) do
        w = Login({ forever = true, cvars = { [KEY] = v }, defaults = D45, acct = { [KEY] = Left(v) } })
        eq(w.cvars[KEY] .. "|" .. Sets(w), v .. "|", "a value of ours of " .. v .. " (not above the default) stays")
        check(w.Acct(KEY) ~= nil and w.Acct(KEY).a == v, "a value of ours of " .. v .. ": its record stays for Uninstall")
    end
end
-- a value the player set since is theirs, above the default or not
for _, v in ipairs({ "30", "55", "100" }) do
    local w = Login({ forever = true, cvars = { [KEY] = v }, defaults = D45, acct = { [KEY] = Left("60") } })
    eq(w.cvars[KEY] .. "|" .. Sets(w), v .. "|", "the player's own " .. v .. " is left alone")
    eq(w.Acct(KEY), nil, "the player's own " .. v .. ": the record of our value is dropped")
end
-- a snapshot decides as before: back to it, and a snapshot of 60 means the 60 was there
-- before EllesmereUI's first write
do
    local w = Login({ forever = true, cvars = { [KEY] = "60" }, defaults = D45, acct = { [KEY] = Left("60", "45") } })
    eq(w.cvars[KEY] .. "|" .. Sets(w), "45|" .. KEY .. "=45", "with a snapshot the value goes back to the snapshot")
    w = Login({ forever = true, cvars = { [KEY] = "60" }, defaults = D45, acct = { [KEY] = Left("60", "50") } })
    eq(w.cvars[KEY] .. "|" .. Sets(w), "50|" .. KEY .. "=50", "a snapshot above the default is still what the value goes back to")
    w = Login({ forever = true, cvars = { [KEY] = "60" }, defaults = D45, acct = { [KEY] = Left("60", "60") } })
    eq(w.cvars[KEY] .. "|" .. Sets(w), "60|", "a 60 that was there before EllesmereUI's first write stays")
    eq(w.Acct(KEY), nil, "a snapshot equal to our value: the record is dropped as before")
end
-- no other client
for _, flag in ipairs({ false, "nil" }) do
    local forever = flag ~= "nil" and flag or nil
    local w = Login({ forever = forever, cvars = { [KEY] = "60" }, defaults = D45, acct = { [KEY] = Left("60") } })
    eq(w.cvars[KEY] .. "|" .. Sets(w), "60|", "retail (flag " .. tostring(flag) .. "): the value stays")
    check(w.Acct(KEY) ~= nil, "retail (flag " .. tostring(flag) .. "): the record stays for Uninstall")
end
-- no other setting, whatever its value against its default
do
    local w = Login({ forever = true,
        cvars = { nameplatemaxalphadistance = "40", nameplateminalpha = "0.6", [KEY] = "45" },
        defaults = { nameplatemaxalphadistance = "10", nameplateminalpha = "0.5", [KEY] = "45" },
        acct = { nameplatemaxalphadistance = Left("40"), nameplateminalpha = Left("0.6") } })
    eq(w.cvars.nameplatemaxalphadistance .. "|" .. w.cvars.nameplateminalpha .. "|" .. Sets(w), "40|0.6|", "other settings a module left are not touched")
    check(w.Acct("nameplatemaxalphadistance") ~= nil and w.Acct("nameplateminalpha") ~= nil, "other settings: their records stay for Uninstall")
end
-- the module is on: its own write decides
do
    local w = Login({ forever = true, cvars = { [KEY] = "60" }, defaults = D45, acct = { [KEY] = Left("60") }, loaded = { [MODULE] = true } })
    eq(w.cvars[KEY] .. "|" .. Sets(w), "60|", "the module is loaded: the pass leaves its value")
    check(w.Acct(KEY) ~= nil, "the module is loaded: its record stays")
end
-- a setting every character shares, the module on for another character
do
    local w = Login({ forever = true, cvars = { [KEY] = "60" }, defaults = D45, acct = { [KEY] = Left("60") }, enabled = { [MODULE] = true } })
    eq(w.cvars[KEY] .. "|" .. Sets(w), "60|", "a shared setting while the module is on for another character stays")
    check(w.Acct(KEY) ~= nil, "a shared setting, module on elsewhere: its record stays")
end
-- a per-character setting: the module off for this character is enough
do
    local w = Login({ forever = true, cvars = { [KEY] = "60" }, defaults = D45, perChar = { [KEY] = true }, char = { [KEY] = Left("60") },
        enabled = { [MODULE] = true } })
    eq(w.cvars[KEY] .. "|" .. Sets(w), "45|" .. KEY .. "=45", "a per-character setting goes back while the module is off for this character")
    eq(w.Char(KEY), nil, "a per-character setting: the record is dropped")
    eq(w.record.chars[GUID], nil, "a per-character setting: the character's empty record goes")
end
-- a default the game does not give, or one that is no number
for _, def in ipairs({ "none", "high" }) do
    local w = Login({ forever = true, cvars = { [KEY] = "60" }, defaults = { [KEY] = def ~= "none" and def or nil }, acct = { [KEY] = Left("60") } })
    eq(w.cvars[KEY] .. "|" .. Sets(w), "60|", "a default of " .. def .. ": the value stays")
    check(w.Acct(KEY) ~= nil, "a default of " .. def .. ": the record stays")
end
-- a write the game refuses: the record stays, so the next login tries again
do
    local w = Login({ forever = true, cvars = { [KEY] = "60" }, defaults = D45, acct = { [KEY] = Left("60") }, refuse = { [KEY] = true } })
    eq(w.cvars[KEY] .. "|" .. Sets(w), "60|", "a refused write changes nothing")
    check(w.Acct(KEY) ~= nil and w.Acct(KEY).a == "60", "a refused write: the record stays for the next login")
end
-- a login in combat: the pass waits for the combat queue
do
    local w = Login({ forever = true, cvars = { [KEY] = "60" }, defaults = D45, acct = { [KEY] = Left("60") }, combat = true })
    eq(w.cvars[KEY] .. "|" .. Sets(w) .. "|" .. #w.deferred, "60||1", "a login in combat: nothing is written before combat ends")
    w.deferred[1]()
    eq(w.cvars[KEY] .. "|" .. Sets(w), "45|" .. KEY .. "=45", "a login in combat: the pass runs once combat ends")
end
-- a standalone runs no module pass
do
    local w = Login({ forever = true, addon = "EllesmereUINameplatesStandalone", cvars = { [KEY] = "60" }, defaults = D45, acct = { [KEY] = Left("60") } })
    eq(w.cvars[KEY] .. "|" .. Sets(w) .. "|" .. #w.deferred, "60||0", "a standalone build runs no module pass")
end

if fails > 0 then error(fails .. " of " .. count .. " check(s) failed") end
print(("PASS test_np_forever_plate_range (%d checks)"):format(count))
