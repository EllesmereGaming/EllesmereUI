-- Stub harness: on WoW Forever the Click Casting Dispels key casts only the
-- first dispel in its class's priority list that the character knows (a
-- vanilla dispel casts with nothing to remove and starts the GCD, so a second
-- line could never fire); retail keeps every usable entry. The macro, the icon,
-- the spell picker's already-bound marks and the rebuild signature all read
-- that one list.
--   lua .tools/tests/test_cc_forever_dispel_first.lua [EUI_RaidFrames_ClickCast.lua]
local PATH = (arg and arg[1]) or "EllesmereUIRaidFrames/EUI_RaidFrames_ClickCast.lua"

local fh = assert(io.open(PATH, "rb"))
local SRC = fh:read("*a"):gsub("\r\n", "\n")
fh:close()

local s = SRC:find("local DISPEL_SPELLS = {", 1, true)
assert(s, "DISPEL_SPELLS not found")
local fv = SRC:find("if EllesmereUI.IS_FOREVER then\n    DISPEL_SPELLS = {", s, true)
assert(fv, "the Forever list not found")
local _, e = SRC:find("\nend\n", fv, true)
local CHUNK = SRC:sub(s, e) .. "return DispelPresetSpells\n"

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

local KNOWN = {}
local function Load(forever)
    local env = setmetatable({
        EllesmereUI = { IS_FOREVER = forever },
        C_SpellBook = { IsSpellInSpellBook = function(id) return KNOWN[id] == true end },
        Enum = { SpellBookSpellBank = { Player = 0 } },
    }, { __index = _G })
    local fn = assert(loadstring(CHUNK, "@ClickCast"))
    setfenv(fn, env)
    return fn()
end
local function Ids(list)
    local out = {}
    for i = 1, #list do out[i] = tostring(list[i].id) end
    return table.concat(out, ",")
end
local function Knows(...)
    KNOWN = {}
    for i = 1, select("#", ...) do KNOWN[select(i, ...)] = true end
end

-- 1. WoW Forever: the first dispel the character knows, and only that one.
local Dispels = Load(true)
local cases = {
    { "PRIEST",  { 528 },             "528",   "a Priest before Dispel Magic keeps Cure Disease" },
    { "PRIEST",  { 527, 552, 528 },   "527",   "a Priest with every dispel gets Dispel Magic alone" },
    { "PRIEST",  {},                  "527",   "a Priest whose book is not in yet gets the list's first" },
    { "DRUID",   { 8946 },            "8946",  "a Druid before Remove Curse keeps Cure Poison" },
    { "DRUID",   { 2782, 2893, 8946 }, "2782", "a Druid with every dispel gets Remove Curse alone" },
    { "SHAMAN",  { 526, 2870 },       "526",   "a Shaman gets Cure Poison alone" },
    { "PALADIN", { 1152 },            "1152",  "a Paladin before Cleanse keeps Purify" },
    { "PALADIN", { 4987, 1152 },      "4987",  "a Paladin with Cleanse gets Cleanse alone" },
    { "MAGE",    { 475 },             "475",   "a Mage gets Remove Lesser Curse" },
    { "WARLOCK", {},                  "19505", "a Warlock gets the Felhunter's Devour Magic" },
}
for _, c in ipairs(cases) do
    Knows(unpack(c[2]))
    local got = Ids(Dispels(c[1]))
    check(got == c[3], c[4] .. " (got " .. got .. ")")
end

-- 2. Retail keeps every usable entry of the class.
local Retail = Load(false)
Knows(527, 213634)
check(Ids(Retail("PRIEST")) == "527,213634", "retail lost a usable dispel")
Knows(527)
check(Ids(Retail("PRIEST")) == "527", "retail kept an unknown dispel")

-- 3. Every reader goes through the one list, and the rebuild signature carries it.
local function count(text)
    local n, at = 0, 1
    while true do
        local f = SRC:find(text, at, true)
        if not f then return n end
        n, at = n + 1, f + #text
    end
end
check(count("ClassPresetSpells(DISPEL_SPELLS") == 1, "a reader of the dispel list bypasses DispelPresetSpells")
check(count('local spells = binding.type == "dispel" and DispelPresetSpells(pClass)') == 1,
    "the Dispels macro does not read DispelPresetSpells")
check(count("for _, sp in ipairs(DispelPresetSpells(pc)) do") == 1, "the Dispels icon does not read DispelPresetSpells")
check(count("for _, sp in ipairs(DispelPresetSpells(pClass)) do") == 1,
    "the spell picker's already-bound marks do not read DispelPresetSpells")
check(count('if hasDispel and EllesmereUI.IS_FOREVER then\n        local sp = DispelPresetSpells(select(2, UnitClass("player")))[1]\n        sigParts[#sigParts + 1] = "|d" .. (sp and sp.id or 0)') == 1,
    "the rebuild signature does not carry the Forever dispel")

if fails > 0 then error(fails .. " check(s) failed") end
print("PASS test_cc_forever_dispel_first")
