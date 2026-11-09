-- Stub harness: Click Casting's macro watch (EUI_RaidFrames_ClickCast.lua).
-- A macro binding copies its macro's body at apply, so the apply watches
-- UPDATE_MACROS while an active binding is a macro, and the event re-applies
-- only when a bound macro now resolves or reads differently (MacroSignature).
-- Cuts GetBindingMacroIndex, MacroSignature, the watch block of
-- ns.CC_ApplyBindings and OnCCEvent out of the real file and drives them over a
-- fake macro store: an edit to an unrelated macro, or to an account macro that
-- shares a bound character macro's name, re-applies nothing.
--   lua .tools/tests/test_cc_macro_watch.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local SRC = ReadSource("EllesmereUIRaidFrames/EUI_RaidFrames_ClickCast.lua")

local function CutFrom(src, from, stop, label)
    local a = assert(src:find(from, 1, true), label .. ": start missing")
    local e = assert(src:find(stop, a, true), label .. ": end missing")
    return src:sub(a, e + #stop - 1)
end
local LOOKUP = CutFrom(SRC, "local function GetBindingMacroIndex(b)", "\nend\n", "GetBindingMacroIndex")
local SIG = CutFrom(SRC, 'local macroSig = ""', "\nend\n", "MacroSignature")
local WATCH = CutFrom(SRC, "    macroSig = MacroSignature(bindings)\n", "\n    end\n", "the apply's macro watch")
local HANDLER = CutFrom(SRC, "local function OnCCEvent(self, event)", "\nend\n", "OnCCEvent")

-------------------------------------------------------------------------------
--  Fake macro store and environment
-------------------------------------------------------------------------------
local MAX_ACCOUNT = 120
local T

local function Reset()
    T = { account = {}, char = {}, loaded = true, combat = false, bindings = {}, events = {}, applies = 0 }
end

local function GetNumMacros()
    if not T.loaded then return 0, 0 end
    return #T.account, #T.char
end
local function MacroAt(i)
    if not T.loaded then return nil end
    if i > MAX_ACCOUNT then return T.char[i - MAX_ACCOUNT] end
    return T.account[i]
end
local function GetMacroInfo(i) local m = MacroAt(i) return m and m.name end
local function GetMacroBody(i) local m = MacroAt(i) return m and m.body end
local function GetMacroIndexByName(name)
    if not T.loaded then return 0 end
    for i, m in ipairs(T.account) do if m.name == name then return i end end
    for i, m in ipairs(T.char) do if m.name == name then return MAX_ACCOUNT + i end end
    return 0
end
local function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local function InCombatLockdown() return T.combat end
local function GetActiveBindings() return T.bindings end
local ccEventFrame = {
    RegisterEvent = function(_, e) T.events[e] = true end,
    UnregisterEvent = function(_, e) T.events[e] = nil end,
}

local function Build(sig, watch, handler)
    local src = table.concat({
        "local GetNumMacros, GetMacroInfo, GetMacroIndexByName, GetMacroBody, MAX_ACCOUNT_MACROS, wipe,",
        "    InCombatLockdown, GetActiveBindings, ccEventFrame, ns, GetClickCastDB = ...",
        "local pendingApply, pendingTipSync, pendingSetEnabled = false, false, nil",
        "local regQueue, unregQueue, ownedFrames = {}, {}, {}",
        "local function SyncTipEaters() end",
        "local function DoRegisterFrame() end",
        "local function DoUnregisterFrame() end",
        LOOKUP, sig,
        "ns.CC_ApplyBindings = function()",
        "    ns.applies = ns.applies + 1",
        "    local bindings = GetActiveBindings()",
        watch,
        "end",
        handler,
        "return OnCCEvent, function() return macroSig, pendingApply end",
    }, "\n")
    local ns = { applies = 0 }
    local OnEvent, State = assert(loadstring(src, "=EUI_RaidFrames_ClickCast.lua"))(
        GetNumMacros, GetMacroInfo, GetMacroIndexByName, GetMacroBody, MAX_ACCOUNT, wipe,
        InCombatLockdown, GetActiveBindings, ccEventFrame, ns, function() return { enabled = true } end)
    return { ns = ns, Event = function(e) OnEvent(nil, e) end, State = State }
end

local function Applies(E) return E.ns.applies end

local function Scenarios(E)
    -- 1. No macro binding: nothing watched.
    Reset()
    T.account = { { name = "Mount", body = "/cast Travel Form" } }
    E.ns.CC_ApplyBindings()
    assert(not T.events.UPDATE_MACROS, "UPDATE_MACROS watched with no macro binding")
    assert(E.State() == "", "a signature with no macro binding")

    -- 2. A bound account macro: watched.
    T.account = { { name = "Heal", body = "/cast Flash Heal" }, { name = "Mount", body = "/cast Travel Form" } }
    T.bindings = { { type = "macro", macroName = "Heal", macroChar = false, key = "BUTTON1" },
                   { type = "spell", spell = "Renew", key = "BUTTON2" } }
    E.ns.CC_ApplyBindings()
    assert(T.events.UPDATE_MACROS, "UPDATE_MACROS not watched with a macro binding")
    local n = Applies(E)

    -- 3. An unrelated macro edited, or the event with nothing changed: no apply.
    T.account[2].body = "/cast Swift Flight Form"
    E.Event("UPDATE_MACROS")
    E.Event("UPDATE_MACROS")
    assert(Applies(E) == n, "an edit to an unbound macro re-applied")

    -- 4. The bound macro's body edited: one apply.
    T.account[1].body = "/cast [@mouseover] Flash Heal"
    E.Event("UPDATE_MACROS")
    assert(Applies(E) == n + 1, "the bound macro's edit did not re-apply")
    E.Event("UPDATE_MACROS")
    assert(Applies(E) == n + 1, "a second event with nothing new re-applied")

    -- 5. Renamed away, then back: both re-apply.
    T.account[1].name = "Heal2"
    E.Event("UPDATE_MACROS")
    assert(Applies(E) == n + 2, "renaming the bound macro away did not re-apply")
    T.account[1].name = "Heal"
    E.Event("UPDATE_MACROS")
    assert(Applies(E) == n + 3, "renaming it back did not re-apply")

    -- 6. A character macro binding with an account namesake: only its own macro counts.
    T.char = { { name = "Heal", body = "/cast Heal" } }
    T.bindings = { { type = "macro", macroName = "Heal", macroChar = true, key = "BUTTON1" } }
    E.ns.CC_ApplyBindings()
    n = Applies(E)
    T.account[1].body = "/cast Power Word: Shield"
    E.Event("UPDATE_MACROS")
    assert(Applies(E) == n, "the account namesake's edit re-applied the character binding")
    T.char[1].body = "/cast [@mouseover] Heal"
    E.Event("UPDATE_MACROS")
    assert(Applies(E) == n + 1, "the character macro's edit did not re-apply")

    -- 7. In combat the change waits for combat to end.
    T.combat = true
    T.char[1].body = "/cast Greater Heal"
    E.Event("UPDATE_MACROS")
    local _, pending = E.State()
    assert(Applies(E) == n + 1 and pending, "a combat edit applied, or did not wait")
    T.combat = false
    E.Event("PLAYER_REGEN_ENABLED")
    assert(Applies(E) == n + 2, "the waiting apply did not run at combat end")

    -- 8. Login: macros not loaded at the first apply, then they load.
    Reset()
    T.loaded = false
    T.account = { { name = "Heal", body = "/cast Flash Heal" } }
    T.bindings = { { type = "macro", macroName = "Heal", key = "BUTTON1" } }
    E.ns.CC_ApplyBindings()
    assert(T.events.UPDATE_MACROS, "a binding whose macro has not loaded is not watched")
    n = Applies(E)
    T.loaded = true
    E.Event("UPDATE_MACROS")
    assert(Applies(E) == n + 1, "macros loading after the first apply did not re-apply")

    -- 9. The macro binding goes (Click Casting off, or another context): unwatched.
    T.bindings = {}
    E.ns.CC_ApplyBindings()
    assert(not T.events.UPDATE_MACROS, "UPDATE_MACROS still watched with no macro binding")
end

Scenarios(Build(SIG, WATCH, HANDLER))

-------------------------------------------------------------------------------
--  Mutants: each must break a scenario
-------------------------------------------------------------------------------
local function Swap(text, from, to)
    local a, b = text:find(from, 1, true)
    assert(a, "mutant text not found: " .. from)
    return text:sub(1, a - 1) .. to .. text:sub(b + 1)
end
local MUTANTS = {
    { "every UPDATE_MACROS re-applies",
      "handler", "if MacroSignature(GetActiveBindings()) ~= macroSig then", "if true then" },
    { "the signature leaves out the body",
      "sig", [[idx and (idx .. "\30" .. (GetMacroBody(idx) or ""))]], "idx and tostring(idx)" },
    { "the watch is never registered",
      "watch", 'ccEventFrame:RegisterEvent("UPDATE_MACROS")', 'ccEventFrame:UnregisterEvent("UPDATE_MACROS")' },
    { "the apply does not store the signature",
      "watch", "    macroSig = MacroSignature(bindings)\n    if macroSig ~=", "    local s = MacroSignature(bindings)\n    if s ~=" },
}
for _, m in ipairs(MUTANTS) do
    local sig, watch, handler = SIG, WATCH, HANDLER
    if m[2] == "sig" then sig = Swap(sig, m[3], m[4]) end
    if m[2] == "watch" then watch = Swap(watch, m[3], m[4]) end
    if m[2] == "handler" then handler = Swap(handler, m[3], m[4]) end
    local ok = pcall(Scenarios, Build(sig, watch, handler))
    assert(not ok, "mutant survived: " .. m[1])
end

print(("PASS: Click Casting macro watch, 9 scenarios, %d mutants killed"):format(#MUTANTS))
