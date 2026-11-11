-- Stub harness: the Enemy Buff Filter's two engine groups on enemy nameplates.
-- Cuts the token locals and BuffMode / BuffDispelByMe / BuffFilterGlow /
-- BuffFilterPlain out of the real Nameplates aura file and checks every client,
-- mode and Dispellable By Me setting against every kind of buff: the
-- dispellable (glow) group and the plain remainder never share a buff, and
-- together they show exactly what the mode promises. With Dispellable By Me on
-- (retail), Important and Only Dispellable count only the group's own dispels;
-- Show All and WoW Forever never read it. Also checks that the toggle is a
-- reload input and that its cog greys out for Show All alone.
--   lua .tools/tests/test_np_enemy_buff_filter.lua        (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return (src:gsub("\r\n", "\n"))
end
local SRC = ReadSource("EllesmereUINameplates/EUI_Nameplates_AuraContainers.lua")
local OPT = ReadSource("EllesmereUIOptions/Nameplates_Options/GeneralPage_Options.lua")

local TOKENS = {}
for _, name in ipairs({ "DISPELLABLE", "IMPORTANT", "RAID_DISPELLABLE" }) do
    local line = SRC:match("\nlocal " .. name .. " = AuraUtil and [^\n]*")
    assert(line, "token line missing: " .. name)
    TOKENS[#TOKENS + 1] = line:sub(2)
end
local f0 = assert(SRC:find("local function BuffMode()", 1, true), "BuffMode missing")
local f1 = assert(SRC:find("-- Stale-client fallback only", f0, true), "end of the filter functions missing")
local FUNCS = SRC:sub(f0, f1 - 1)

local PRELUDE = [[
local AuraUtil = { AuraFilters = { Dispellable = "DISPELLABLE", Important = "IMPORTANT",
    RaidPlayerDispellable = "RAID_PLAYER_DISPELLABLE" } }
local EllesmereUI = { IS_FOREVER = false }
local CFG = {}
local function PVal(k) return CFG[k] end
]]
local PROBE = [[
return function(forever, mode, toggle)
    EllesmereUI.IS_FOREVER = forever
    CFG = { npEnemyBuffFilter = mode, npEnemyBuffDispelByMe = toggle }
    return BuffFilterGlow(), BuffFilterPlain()
end
]]

local function Build(funcs, label)
    local src = PRELUDE .. table.concat(TOKENS, "\n") .. "\n" .. funcs .. "\n" .. PROBE
    return assert(loadstring(src, "=" .. label))()
end

-- Swaps one exact piece of text (plain match), failing when it is absent.
local function Swap(text, from, to)
    local s, e = text:find(from, 1, true)
    assert(s, "mutant text not found: " .. from)
    return text:sub(1, s - 1) .. to .. text:sub(e + 1)
end

-------------------------------------------------------------------------------
--  Buff kinds and the engine's filter rules
-------------------------------------------------------------------------------
-- RAID_PLAYER_DISPELLABLE is a subset of DISPELLABLE: someone in the group can
-- dispel it.
local KINDS = {}
for _, important in ipairs({ false, true }) do
    for _, dispellable in ipairs({ false, true }) do
        for _, raid in ipairs({ false, true }) do
            if dispellable or not raid then
                KINDS[#KINDS + 1] = { important = important, dispellable = dispellable, raid = raid }
            end
        end
    end
end

local FIELD = { IMPORTANT = "important", DISPELLABLE = "dispellable", RAID_PLAYER_DISPELLABLE = "raid" }

-- A filter string ANDs its components; a leading "!" negates one (Blizzard's
-- AuraUtil: every component but INCLUDE_NAME_PLATE_ONLY and MAW).
local function Matches(filter, buff)
    if not filter then return false end
    for i = 1, #filter do
        local comp = filter[i]
        local neg = comp:sub(1, 1) == "!"
        local name = neg and comp:sub(2) or comp
        local ok
        if name == "HELPFUL" or name == "INCLUDE_NAME_PLATE_ONLY" then
            assert(not (neg and name == "INCLUDE_NAME_PLATE_ONLY"), "INCLUDE_NAME_PLATE_ONLY cannot be negated")
            ok = true
        else
            local field = assert(FIELD[name], "unknown filter component " .. comp)
            ok = buff[field]
        end
        if neg then ok = not ok end
        if not ok then return false end
    end
    return true
end

local MODES = { "nil", "important", "all", "dispellable", "showall" }

-- What each mode promises: Important = important OR dispellable, Only
-- Dispellable = dispellable, Show All = every buff; the glow group holds the
-- dispellable ones. Dispellable By Me (retail, not Show All) reads
-- "dispellable" as "the group can dispel it".
local function Expected(forever, modeRaw, toggle, buff)
    local mode = (modeRaw == "dispellable" or modeRaw == "showall") and modeRaw or "important"
    local key = (not forever and mode ~= "showall" and toggle == true) and "raid" or "dispellable"
    local glow, shown
    if mode == "important" then
        glow, shown = buff[key], buff.important or buff[key]
    elseif mode == "dispellable" then
        glow, shown = buff[key], buff[key]
    else
        glow, shown = buff.dispellable, true
    end
    return glow, shown and not glow
end

local function Check(probe, quiet)
    local failed = 0
    for _, forever in ipairs({ false, true }) do
        for _, modeRaw in ipairs(MODES) do
            for _, toggle in ipairs({ false, true }) do
                local mode = modeRaw ~= "nil" and modeRaw or nil
                local glowF, plainF = probe(forever, mode, toggle or nil)
                local bad
                for _, buff in ipairs(KINDS) do
                    local g, p = Matches(glowF, buff), Matches(plainF, buff)
                    local eg, ep = Expected(forever, mode, toggle, buff)
                    if (g and p) or g ~= eg or p ~= ep then bad = true end
                end
                if bad then
                    failed = failed + 1
                    if not quiet then
                        print(("  wrong groups: forever=%s mode=%s toggle=%s glow=%s plain=%s"):format(
                            tostring(forever), modeRaw, tostring(toggle),
                            table.concat(glowF or {}, "|"), plainF and table.concat(plainF, "|") or "nil"))
                    end
                end
            end
        end
    end
    return failed
end

-------------------------------------------------------------------------------
--  1. Every client x mode x toggle, on the real functions
-------------------------------------------------------------------------------
local cells = 2 * #MODES * 2
local failed = Check(Build(FUNCS, "filter functions"))
assert(failed == 0, failed .. " of " .. cells .. " cells show the wrong buffs")

-- The narrowing reaches exactly the retail Important and Only Dispellable cells
-- with the toggle on; everything else matches the toggle off.
do
    local probe = Build(FUNCS, "filter functions")
    local function key(g, p) return table.concat(g, "|") .. " / " .. (p and table.concat(p, "|") or "nil") end
    local changed = {}
    for _, forever in ipairs({ false, true }) do
        for _, modeRaw in ipairs(MODES) do
            local mode = modeRaw ~= "nil" and modeRaw or nil
            local off = key(probe(forever, mode, nil))
            local on = key(probe(forever, mode, true))
            if off ~= on then changed[#changed + 1] = (forever and "forever:" or "retail:") .. modeRaw end
        end
    end
    table.sort(changed)
    assert(table.concat(changed, ",") == "retail:all,retail:dispellable,retail:important,retail:nil",
        "the toggle changes: " .. table.concat(changed, ","))
end

-------------------------------------------------------------------------------
--  2. The toggle is a reload input: the container config fingerprint carries it
-------------------------------------------------------------------------------
do
    local c0 = assert(SRC:find("local function CfgFP()", 1, true), "CfgFP missing")
    local c1 = assert(SRC:find("\nend\n", c0, true), "CfgFP end missing")
    assert(SRC:sub(c0, c1):find("BuffDispelByMe()", 1, true), "CfgFP no longer carries BuffDispelByMe()")
end

-------------------------------------------------------------------------------
--  3. The cog greys out for Show All alone (nil and "all" read as Important)
-------------------------------------------------------------------------------
local COG = OPT:match("EllesmereUI%.BuildInlineCog%(dispelGlowRow%._leftRegion, {%s*disabled = (function%(%)[^\n]-end),")
assert(COG, "the Enemy Buff Filter cog's disabled function is missing")
assert(OPT:find("if not EllesmereUI._prebuilding and not EllesmereUI.IS_FOREVER then\n        EllesmereUI.BuildInlineCog(dispelGlowRow._leftRegion", 1, true),
    "the Enemy Buff Filter cog is no longer retail-only")

local function CheckCog(fnText)
    local saved
    local disabled = assert(loadstring("local DBVal = ...\nreturn " .. fnText, "=cog"))(function(k)
        assert(k == "npEnemyBuffFilter", "the cog reads " .. tostring(k)); return saved
    end)
    local wrong = 0
    for _, modeRaw in ipairs(MODES) do
        saved = modeRaw ~= "nil" and modeRaw or nil
        if (disabled() and true or false) ~= (modeRaw == "showall") then wrong = wrong + 1 end
    end
    return wrong
end
assert(CheckCog(COG) == 0, "the cog greys out for the wrong modes")

-------------------------------------------------------------------------------
--  4. Mutants: each one must break a check above
-------------------------------------------------------------------------------
local MUTANTS = {
    { "plain group keeps !DISPELLABLE (an important buff only other classes can dispel vanishes)",
      't[#t + 1] = "!" .. (BuffDispelByMe() and RAID_DISPELLABLE or DISPELLABLE)', 't[#t + 1] = "!" .. DISPELLABLE' },
    { "toggle read in Only Dispellable alone",
      'mode ~= "showall"', 'mode == "dispellable"' },
    { "toggle read in Show All too",
      'mode ~= "showall"', 'mode ~= nil' },
    { "toggle read on WoW Forever",
      "not EllesmereUI.IS_FOREVER and RAID_DISPELLABLE", "RAID_DISPELLABLE" },
    { "glow group keeps DISPELLABLE",
      "t[#t + 1] = BuffDispelByMe() and RAID_DISPELLABLE or DISPELLABLE", "t[#t + 1] = DISPELLABLE" },
}
for _, m in ipairs(MUTANTS) do
    local ok, n = pcall(Check, Build(Swap(FUNCS, m[2], m[3]), "mutant"), true)
    assert(not ok or n > 0, "mutant survived: " .. m[1])
end
assert(CheckCog(Swap(COG, '== "showall"', '~= "dispellable"')) > 0, "mutant survived: cog greyed unless Only Dispellable")

print(("PASS: %d cells x %d buff kinds, %d filter mutants and the cog mutant killed"):format(cells, #KINDS, #MUTANTS))
