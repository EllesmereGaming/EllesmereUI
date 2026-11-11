-- Stub harness: WoW Forever has no Smart Text power text. Drives the one-time
-- migration block (forever_power_text_value_v1 in EllesmereUI_Migration.lua),
-- the format helpers (EllesmereUI.PowerTextFormat / PowerTextFormatOrder in
-- EllesmereUI_SharedHelpers.lua) and the Unit Frames smart rule
-- (EUI_IsSmartPowerPercent in EUI_UnitFrames_Text.lua), each cut from its file.
--   lua .tools/tests/test_forever_power_text_smart.lua   (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end

-- The migration's own do-block: from the "do" line before its FLAG to the
-- first column-0 "end" after it.
local MIG = ReadSource("EllesmereUI_Migration.lua")
local at = assert(MIG:find('local FLAG = "forever_power_text_value_v1"', 1, true), "migration block missing")
local s0 = 1
while true do
    local i = MIG:find("\ndo\n", s0, true)
    if not i or i > at then break end
    s0 = i + 1
end
local e0 = assert(MIG:find("\nend\n", at, true) or (MIG:sub(-4) == "\nend" and #MIG - 3), "block end missing")
local BLOCK = MIG:sub(s0, e0 + 3)
assert(BLOCK:sub(1, 3) == "do\n", "block start")

local HELPERS = ReadSource("EllesmereUI_SharedHelpers.lua")
local h0 = assert(HELPERS:find("function EllesmereUI.PowerTextFormat(", 1, true))
local h1 = assert(HELPERS:find("\nend\n", HELPERS:find("function EllesmereUI.PowerTextFormatOrder(", 1, true), true))
local HELPER_SRC = HELPERS:sub(h0, h1 + 4)

local TEXT = ReadSource("EllesmereUIUnitFrames/EUI_UnitFrames_Text.lua")
local t0 = assert(TEXT:find("local function EUI_IsSmartPowerPercent(", 1, true))
local t1 = assert(TEXT:find("\nns.EUI_IsSmartPowerPercent = ", t0, true))
local SMART_SRC = TEXT:sub(t0, t1) .. "\nreturn EUI_IsSmartPowerPercent\n"

local fails = 0
local function Check(ok, msg)
    if not ok then fails = fails + 1; print("FAIL: " .. msg) end
end

-------------------------------------------------------------------------------
--  1. The migration, on a WoW Forever client
-------------------------------------------------------------------------------
local NIL_SENT = "__SPECOV_NIL__"
local UF_PLAYER = "EllesmereUIUnitFrames\31player\30powerTextFormat"
local UF_BOSS_FORM = "EllesmereUIUnitFrames\31boss\30foreverFormTextFormat"
local RB_POWER = "EllesmereUIResourceBars\31primary\30textFormat"
local RB_FDM = "EllesmereUIResourceBars\31primary\30foreverDruidMana\30textFormat"
local OTHER = "EllesmereUIDataBars\31bars\30travel\30textMode"   -- another setting's own "smart"

local function MakeDB()
    return { profiles = {
        Default = {
            addons = {
                EllesmereUIUnitFrames = {
                    player = { powerTextFormat = "smart", foreverFormTextFormat = "smart" },
                    target = { powerTextFormat = "curpp" },
                    totPet = { powerTextFormat = "smart" },
                    boss = { powerTextFormat = "both" },
                    healthBarTexture = "plating",
                },
                EllesmereUIResourceBars = {
                    primary = { textFormat = "smart", foreverDruidMana = { textFormat = "smart" } },
                    health = { textFormat = "smart" },   -- not a power text: left alone
                },
                EllesmereUIDataBars = { bars = { travel = { textMode = "smart" } } },
            },
            specOverrides = {
                { values = {
                    default = { [UF_PLAYER] = "smart", [RB_POWER] = NIL_SENT, [OTHER] = "smart" },
                    [62] = { [UF_BOSS_FORM] = "smart", [RB_FDM] = "smart", [RB_POWER] = "perpp" },
                    ["cg3"] = { [RB_POWER] = "smart" },
                } },
            },
        },
        Second = { addons = { EllesmereUIUnitFrames = { focus = { powerTextFormat = "smart" } } } },
    } }
end

local function RunBlock(toc, isForever, db)
    local hooks, frames = {}, {}
    local env = setmetatable({
        GetBuildInfo = function() return "1.60.1", "70790", "Nov 1 2026", toc end,
        EllesmereUI = { IS_FOREVER = isForever, Lite = {
            OnSavedVariablesLoaded = function(fn) hooks[#hooks + 1] = fn end } },
        EllesmereUIDB = db,
        CreateFrame = function()
            local f = { events = {} }
            function f:RegisterEvent(e) self.events[e] = true end
            function f:UnregisterAllEvents() self.events = {} end
            function f:SetScript(_, fn) self.onEvent = fn end
            frames[#frames + 1] = f
            return f
        end,
    }, { __index = _G })
    local chunk = assert(loadstring(BLOCK, "=forever_power_text_value_v1"))
    setfenv(chunk, env)
    chunk()
    for i = 1, #hooks do hooks[i]() end
    return env, hooks, frames
end

local db = MakeDB()
local env, hooks = RunBlock(16001, true, db)
Check(#hooks == 1, "the Forever client registers one saved-variables hook")
local d = db.profiles.Default.addons
Check(d.EllesmereUIUnitFrames.player.powerTextFormat == "curpp", "player Power Text smart -> curpp")
Check(d.EllesmereUIUnitFrames.player.foreverFormTextFormat == "curpp", "player Form Power Text smart -> curpp")
Check(d.EllesmereUIUnitFrames.totPet.powerTextFormat == "curpp", "a mini frame's Power Text smart -> curpp")
Check(d.EllesmereUIUnitFrames.target.powerTextFormat == "curpp", "an existing value stays")
Check(d.EllesmereUIUnitFrames.boss.powerTextFormat == "both", "another format stays")
Check(d.EllesmereUIResourceBars.primary.textFormat == "curpp", "Resource Bars Power Text smart -> curpp")
Check(d.EllesmereUIResourceBars.primary.foreverDruidMana.textFormat == "curpp", "Mana Bar Text smart -> curpp")
Check(d.EllesmereUIResourceBars.health.textFormat == "smart", "a key outside the power texts is left alone")
Check(d.EllesmereUIDataBars.bars.travel.textMode == "smart", "another setting's own smart is left alone")
local v = db.profiles.Default.specOverrides[1].values
Check(v.default[UF_PLAYER] == "curpp", "a Spec Override default-layer value moves")
Check(v.default[RB_POWER] == NIL_SENT, "a not-present mark stays")
Check(v.default[OTHER] == "smart", "another setting's override value stays")
Check(v[62][UF_BOSS_FORM] == "curpp", "a spec layer's Form Power Text moves")
Check(v[62][RB_FDM] == "curpp", "a spec layer's Mana Bar Text moves")
Check(v[62][RB_POWER] == "perpp", "a spec layer's other format stays")
Check(v["cg3"][RB_POWER] == "curpp", "a Conditional Overrides layer moves")
Check(db.profiles.Second.addons.EllesmereUIUnitFrames.focus.powerTextFormat == "curpp", "every stored profile moves")
Check(db._migrations and db._migrations.forever_power_text_value_v1 == true, "the account flag is written")

-- Once only: a value saved after the pass is never moved again.
d.EllesmereUIUnitFrames.player.powerTextFormat = "smart"
RunBlock(16001, true, db)
Check(d.EllesmereUIUnitFrames.player.powerTextFormat == "smart", "the pass runs once per account")

-- A brand-new account (no saved data yet) is only marked, at login.
local _, _, frames = RunBlock(16001, true, nil)
Check(#frames == 1 and frames[1].events.PLAYER_LOGIN, "a new account waits for login to be marked")

-------------------------------------------------------------------------------
--  2. Never on retail (no hook, nothing moved), whatever the flag says
-------------------------------------------------------------------------------
local rdb = MakeDB()
local _, rhooks = RunBlock(120105, false, rdb)
Check(#rhooks == 0, "retail registers no hook")
Check(rdb.profiles.Default.addons.EllesmereUIUnitFrames.player.powerTextFormat == "smart", "retail keeps smart")
local _, bhooks = RunBlock(120105, true, MakeDB())
Check(#bhooks == 0, "a retail interface number stops the block even with the Forever flag set")

-------------------------------------------------------------------------------
--  3. The format helpers
-------------------------------------------------------------------------------
local function Helpers(isForever)
    local E = { IS_FOREVER = isForever }
    local chunk = assert(loadstring(HELPER_SRC, "=helpers"))
    setfenv(chunk, setmetatable({ EllesmereUI = E }, { __index = _G }))
    chunk()
    return E
end
local FV, RT = Helpers(true), Helpers(false)
local ORDER = { "none", "---", "custom", "---", "smart", "curpp", "perpp", "both" }
Check(FV.PowerTextFormat("smart") == "curpp", "Forever reads smart as the value")
Check(FV.PowerTextFormat("perpp") == "perpp" and FV.PowerTextFormat(nil) == nil, "Forever keeps other formats")
Check(RT.PowerTextFormat("smart") == "smart", "retail keeps smart")
local fo = FV.PowerTextFormatOrder(ORDER)
Check(#fo == #ORDER - 1 and fo[5] == "curpp", "Forever's list leaves smart out")
for i = 1, #fo do Check(fo[i] ~= "smart", "no smart in Forever's list") end
Check(ORDER[5] == "smart", "the given list is never changed")
Check(RT.PowerTextFormatOrder(ORDER) == ORDER, "retail gets the same list back")

-------------------------------------------------------------------------------
--  4. The Unit Frames smart rule: the value on WoW Forever, by spec on retail
-------------------------------------------------------------------------------
local function SmartRule(isForever, class, spec)
    local chunk = assert(loadstring(SMART_SRC, "=smart rule"))
    setfenv(chunk, setmetatable({
        EllesmereUI = { IS_FOREVER = isForever },
        UnitClass = function() return class, class end,
        UnitPowerType = function() return 0 end,
        GetSpecialization = function() return spec end,
        Enum = { PowerType = { Mana = 0 } },
    }, { __index = _G }))
    return chunk()
end
Check(SmartRule(false, "PALADIN", 1)() == true, "retail Holy paladin: percent")
Check(SmartRule(false, "WARRIOR", 1)() == false, "retail warrior: value")
Check(SmartRule(true, "PALADIN", 1)() == false, "Forever paladin: value")
Check(SmartRule(true, "PRIEST", 1)() == false, "Forever priest: value")
Check(SmartRule(true, "DRUID", 1)(0) == false, "Forever druid on mana: value")

print(fails == 0 and "forever power text smart harness: ok" or ("forever power text smart harness: " .. fails .. " failure(s)"))
if fails > 0 then error("forever power text smart harness failed") end
