-- Run from the repository root: lua .tools/tests/test_rez_forever_druid.lua
-- WoW Forever Dynamic Rez: a Druid casts Revive out of combat and Rebirth only
-- in combat, in Click Casting (BuildRezLines over its Forever rez lists, every
-- rank listed) and in Quickdraw (a Forever rez list of its own, rank lists
-- read through RezKit's Known), under any rank in the book. A Forever Warlock
-- has no Dynamic Rez in Quickdraw. Retail is unchanged.
EUI_CLIENT_BLOCKED = false

local NAMES = {
    [437138] = "Revive", [1237948] = "Revive", [1237949] = "Revive", [1237950] = "Revive", [1237951] = "Revive",
    [20484] = "Rebirth", [20739] = "Rebirth", [20742] = "Rebirth", [20747] = "Rebirth", [20748] = "Rebirth",
    [2006] = "Resurrection", [2010] = "Resurrection", [10880] = "Resurrection", [10881] = "Resurrection",
    [20770] = "Resurrection",
    [50769] = "Revive",
}
local KNOWN, CLASS = {}, "DRUID"
local function Knows(...)
    KNOWN = {}
    for i = 1, select("#", ...) do KNOWN[select(i, ...)] = true end
end

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

-------------------------------------------------------------------------------
-- Click Casting: the rez lists and BuildRezLines, cut from the file
-------------------------------------------------------------------------------
local fh = assert(io.open("EllesmereUIRaidFrames/EUI_RaidFrames_ClickCast.lua", "rb"))
local SRC = fh:read("*a"):gsub("\r\n", "\n")
fh:close()
local s1 = assert(SRC:find("local REZ_BY_CLASS = {", 1, true), "REZ_BY_CLASS not found")
local fv = assert(SRC:find("if EllesmereUI.IS_FOREVER then\n    DISPEL_SPELLS = {", s1, true), "the Forever lists not found")
local _, e1 = SRC:find("\nend\n", fv, true)
local s2 = assert(SRC:find("local rezItemID = nil", e1, true), "rezItemID not found")
local f2 = assert(SRC:find("local function BuildRezLines(", s2, true), "BuildRezLines not found")
local _, e2 = SRC:find("\nend\n", f2, true)
local CHUNK = SRC:sub(s1, e1) .. SRC:sub(s2, e2) .. "return BuildRezLines\n"

local function LoadCC(forever)
    local env = setmetatable({
        EllesmereUI = { IS_FOREVER = forever },
        UnitClass = function() return CLASS, CLASS end,
        Enum = { SpellBookSpellBank = { Player = 0 } },
        C_SpellBook = { IsSpellInSpellBook = function(id) return KNOWN[id] == true end },
        C_Spell = { GetSpellName = function(id) return NAMES[id] end },
    }, { __index = _G })
    local fn = assert(loadstring(CHUNK, "@ClickCast"))
    setfenv(fn, env)
    return fn()
end
local function Lines(build)
    local lines = build({}, "", true)
    return lines and table.concat(lines, " | ") or "nil"
end

local BOTH = "/cast [@mouseover,help,dead,combat] Rebirth | /cast [@mouseover,help,dead,nocombat] Revive"
local Build = LoadCC(true)
CLASS = "DRUID"
Knows(437138, 20484)
check(Lines(Build) == BOTH, "click cast: a Forever Druid casts Rebirth only in combat: " .. Lines(Build))
Knows(1237950, 20747)
check(Lines(Build) == BOTH, "click cast: higher ranks alone in the book: " .. Lines(Build))
Knows(437138)
check(Lines(Build) == "/cast [@mouseover,help,dead,nocombat] Revive",
    "click cast: Revive before Rebirth is learned: " .. Lines(Build))
Knows()
check(Lines(Build) == "", "click cast: a Druid with no rez yet casts nothing: " .. Lines(Build))
CLASS = "WARLOCK"
check(Lines(Build) == "nil", "click cast: a Forever Warlock has no rez: " .. Lines(Build))

Build = LoadCC(false)
CLASS = "DRUID"
Knows(50769, 20484)
check(Lines(Build) == BOTH, "click cast: retail Druid unchanged: " .. Lines(Build))

-------------------------------------------------------------------------------
-- Quickdraw: the Dynamic Rez macro
-------------------------------------------------------------------------------
local stub = function() end
local any = setmetatable({}, { __call = stub })
getmetatable(any).__index = function() return any end
setmetatable(_G, { __index = function() return any end })
UnitClass = function() return CLASS, CLASS end
Enum = { SpellBookSpellBank = { Player = 0 } }
C_SpellBook = { IsSpellInSpellBook = function(id) return KNOWN[id] == true end }
C_Spell = { GetSpellName = function(id) return NAMES[id] end }
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local function LoadQD(forever)
    EllesmereUI = { IS_FOREVER = forever }
    local I = setmetatable({ broken = false, QUESTION_MARK = 134400 }, { __index = function() return stub end })
    local ns = { _qdInternals = I }
    assert(loadfile("EllesmereUIQuickdraw/EUI_Quickdraw_Actions.lua"))("test", ns)
    assert(ns.ResolveAction and ns.HasRezKit, "EUI_Quickdraw_Actions.lua did not load")
    return ns
end
local function Macro(ns)
    local _, _, text = ns.ResolveAction({ kind = "dynamicrez" })
    return text or "nil"
end

local qd = LoadQD(true)
CLASS = "DRUID"
Knows(437138, 20484)
check(Macro(qd) == "/cast [combat] Rebirth; [@target,help,dead] Revive; Revive",
    "quickdraw: a Forever Druid casts Rebirth only in combat: " .. Macro(qd))
Knows(1237951, 20748)
check(Macro(qd) == "/cast [combat] Rebirth; [@target,help,dead] Revive; Revive",
    "quickdraw: higher ranks alone in the book: " .. Macro(qd))
Knows(437138)
check(Macro(qd) == "/cast [@target,help,dead] Revive; Revive", "quickdraw: Revive before Rebirth: " .. Macro(qd))
Knows()
check(Macro(qd) == "nil", "quickdraw: a Druid with no rez yet has no macro: " .. Macro(qd))
CLASS = "PRIEST"
Knows(10880)
check(Macro(qd) == "/cast [@target,help,dead] Resurrection; Resurrection",
    "quickdraw: a Forever Priest's rank list: " .. Macro(qd))
CLASS = "WARLOCK"
check(not qd.HasRezKit(), "quickdraw: a Forever Warlock has no Dynamic Rez")

qd = LoadQD(false)
CLASS = "DRUID"
Knows(50769, 20484)
check(Macro(qd) == "/cast [combat] Rebirth; [@target,help,dead] Revive; Revive",
    "quickdraw: retail Druid unchanged: " .. Macro(qd))
CLASS = "WARLOCK"
check(qd.HasRezKit(), "quickdraw: a retail Warlock keeps Dynamic Rez")

if fails > 0 then error(fails .. " check(s) failed") end
print("test_rez_forever_druid: all checks passed")
