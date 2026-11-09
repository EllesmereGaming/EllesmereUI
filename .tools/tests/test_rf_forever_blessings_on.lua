-- Stub harness: the WoW Forever Missing Buffs blessing settings
-- (EUI_RaidFrames_ForeverMissingBuffs.lua). Cuts Choice / TakesOne / BlessingsOn
-- out of the real file, with the blessing keys read from its own FAMILIES table,
-- and checks when blessings count as on: a role or class exception list counts
-- only while it holds a blessing the indicator knows, so a saved key it skips
-- (Blessing of Light, which the game removed; a saved "salvation") never keeps
-- the blessing watch running with nothing to show.
--   lua .tools/tests/test_rf_forever_blessings_on.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local SRC = ReadSource("EllesmereUIRaidFrames/EUI_RaidFrames_ForeverMissingBuffs.lua")

-- The blessing keys, as the file's FAMILIES table declares them.
local BLESS_INDEX, n = {}, 0
for key in SRC:gmatch('{ key = "([%w_]+)",%s+class = "PALADIN", blessing = true') do
    n = n + 1
    BLESS_INDEX[key] = n
end
assert(BLESS_INDEX.might and BLESS_INDEX.wisdom and BLESS_INDEX.kings, "the blessing families are missing")
assert(not BLESS_INDEX.light, "Blessing of Light is still a blessing family")
assert(not BLESS_INDEX.salvation, "Salvation became a blessing family")

local a = assert(SRC:find("local BLESS_KEY = {", 1, true), "BLESS_KEY missing")
local f = assert(SRC:find("local function BlessingsOn(s)", a, true), "BlessingsOn missing")
local e = assert(SRC:find("\nend\n", f, true), "end of BlessingsOn missing")
local BLOCK = SRC:sub(a, e + 4)

local function Build(block)
    local chunk = assert(loadstring("local ns, BLESS_INDEX = ...\n" .. block .. "\nreturn BlessingsOn, Choice",
        "=EUI_RaidFrames_ForeverMissingBuffs.lua"))
    return chunk({}, BLESS_INDEX)
end

local function Scenarios(BlessingsOn)
    local function Expect(s, want, what)
        assert(BlessingsOn(s) == want, what .. ": blessings read " .. tostring(not want))
    end
    Expect({}, true, "unset (the role defaults)")
    Expect({ missingBuffsBlessing = false }, false, "the retired switch off")
    Expect({ missingBuffsBlessingTank = "light", missingBuffsBlessingHealer = "light",
             missingBuffsBlessingDPS = "light" }, false, "a stale single key")
    Expect({ missingBuffsBlessingTank = { "light" }, missingBuffsBlessingHealer = { "light" },
             missingBuffsBlessingDPS = { "light", "salvation" } }, false, "stale keys in every list")
    Expect({ missingBuffsBlessingTank = { "light", "kings" }, missingBuffsBlessingHealer = {},
             missingBuffsBlessingDPS = {} }, true, "a real blessing after a stale one")
    local none = { missingBuffsBlessingTank = {}, missingBuffsBlessingHealer = {}, missingBuffsBlessingDPS = {} }
    Expect(none, false, "every list empty")
    none.missingBuffsBlessingExDPS = { PRIEST = {} }
    Expect(none, false, "an empty class exception")
    none.missingBuffsBlessingExDPS = { PRIEST = { "light" } }
    Expect(none, false, "a stale class exception")
    none.missingBuffsBlessingExHealer = { MAGE = { "wisdom" } }
    Expect(none, true, "a real class exception")
end

local BlessingsOn = Build(BLOCK)
Scenarios(BlessingsOn)

-- Mutant: any non-empty list counts again.
local from = "if BLESS_INDEX[list[i]] then return true end"
local s1, s2 = BLOCK:find(from, 1, true)
assert(s1, "mutant text not found")
local mutant = BLOCK:sub(1, s1 - 1) .. "return true" .. BLOCK:sub(s2 + 1)
assert(not pcall(Scenarios, (Build(mutant))), "mutant survived: a stale key counts as a blessing")

print("PASS: blessings on only with a known blessing; stale light / salvation keys and empty lists stay off")
