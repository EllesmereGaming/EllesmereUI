-- Run from the repository root: lua .tools/tests/test_bags_forever_style_default.lua
-- WoW Forever: Bags' WoW Forever style (PR #3212) follows the look most of a
-- profile's modules use while the profile has no Bags style picked (owner
-- 2026-11-09). EllesmereUI.ForeverLookMajority counts the loaded modules'
-- styleable surfaces (STYLE_FLAGS) on the WoW Forever look, the Classic flag
-- winning and a surface with no variant of its own read by its Forever sibling
-- flag; a pick (true or false) wins over it; the Bags latch, the Style page row
-- and the profile switch's reload check read the same rule, and the row saves a
-- pick either way. Off the Forever client nothing follows.
EUI_CLIENT_BLOCKED = false

local fails = 0
local function check(cond, msg)
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

local function Read(path)
    local fh = assert(io.open(path, "rb"))
    local s = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    return s
end
local function Cut(src, head, tail)
    local s = assert(src:find(head, 1, true), head .. " not found")
    local t = assert(src:find(tail, s, true), tail .. " not found")
    local _, e = src:find("\nend\n", t, true)
    return src:sub(s, e)
end

-------------------------------------------------------------------------------
-- The parent's flag list, reload check and majority, cut from the profiles file
-------------------------------------------------------------------------------
local PROF = Read("EllesmereUI_Profiles.lua")
local CHUNK = Cut(PROF, "local STYLE_FLAGS = {", "function EllesmereUI.ForeverLookMajority(")
    .. "return STYLE_FLAGS\n"

local ACTIVE
EllesmereUI = {
    IS_FOREVER = true, _ModuleNS = {},
    GetActiveProfileData = function() return ACTIVE end,
    Lite = { IsDBReady = function() return true end },
}
local STYLE_FLAGS = assert(loadstring(CHUNK, "@Profiles"))()
local E = EllesmereUI

-- Loaded on WoW Forever: every styleable module but the Friends List (it never
-- loads there); Blizzard Skins+ loads but its Skyriding surface is retail-only.
local NOT_LOADED = { EllesmereUIFriends = true }
for _, f in ipairs(STYLE_FLAGS) do
    if not NOT_LOADED[f.folder] then E._ModuleNS[f.folder] = E._ModuleNS[f.folder] or {} end
end
local COUNTED = {}
for _, f in ipairs(STYLE_FLAGS) do
    if E._ModuleNS[f.folder] and not f.retailOnly then COUNTED[#COUNTED + 1] = f end
end
check(#COUNTED >= 10, "too few counted surfaces: " .. #COUNTED)

local function Surface(addons, f)
    local key = f.data or f.folder
    addons[key] = addons[key] or {}
    local t = addons[key]
    if f.sub then t[f.sub] = t[f.sub] or {}; t = t[f.sub] end
    return t
end
local function SetLook(addons, f, look)
    local t = Surface(addons, f)
    t[f.key] = (look == "blizzard" or look == "forever") or nil
    t[f.classic] = (look == "classic") or nil
    t[f.forever or (f.key:gsub("Blizzard", "Forever", 1))] = (look == "forever") or nil
end
-- The first n counted surfaces on `look`, the rest on the EllesmereUI style.
local function Profile(n, look, rest)
    local addons = {}
    for i, f in ipairs(COUNTED) do SetLook(addons, f, i <= n and (look or "forever") or rest or "eui") end
    return addons
end
local N = #COUNTED
local HALF_UP = math.floor(N / 2) + 1     -- the fewest that make a majority

-- 1. The majority itself
check(E.ForeverLookMajority(Profile(N)), "every surface on WoW Forever is a majority")
check(E.ForeverLookMajority(Profile(HALF_UP)), "just over half is a majority")
check(not E.ForeverLookMajority(Profile(HALF_UP - 1)), "half or fewer is not")
check(not E.ForeverLookMajority(Profile(N, "blizzard")), "plain Blizzard Style is not WoW Forever")
do
    local a = Profile(N)
    for i = 1, N - HALF_UP + 1 do
        local t = Surface(a, COUNTED[i])
        t[COUNTED[i].classic] = true
    end
    check(not E.ForeverLookMajority(a), "the Classic flag wins over the Forever pair")
end
do
    -- A surface with no variant of its own counts by its Forever sibling flag.
    local plain = 0
    for i = 1, HALF_UP do if not COUNTED[i].forever then plain = plain + 1 end end
    check(plain > 0, "the case needs a surface with no variant of its own among the majority")
end
do
    -- A module that is not loaded has no vote, whatever its saved data says.
    local a = Profile(HALF_UP)
    for _, f in ipairs(STYLE_FLAGS) do
        if NOT_LOADED[f.folder] then SetLook(a, f, "eui") end
    end
    check(E.ForeverLookMajority(a), "an unloaded module does not vote")
end
do
    -- Skyriding is retail-only: its surface never votes on WoW Forever.
    local a = Profile(HALF_UP - 1)
    local ret
    for _, f in ipairs(STYLE_FLAGS) do if f.retailOnly then ret = f end end
    check(ret ~= nil, "the case needs a retail-only surface")
    if ret then
        E._ModuleNS[ret.folder] = E._ModuleNS[ret.folder] or {}
        SetLook(a, ret, "forever")
        check(not E.ForeverLookMajority(a), "a retail-only surface does not vote")
    end
end
do
    -- A tie is no majority: with an odd count, a module with one surface goes
    -- unloaded so the count is even, and half of what is left is on WoW Forever.
    local folder, saved
    if N % 2 == 1 then
        for i = N, 1, -1 do
            local f, n = COUNTED[i], 0
            for _, g in ipairs(COUNTED) do if g.folder == f.folder then n = n + 1 end end
            if n == 1 then folder = f.folder; break end
        end
        check(folder ~= nil, "the tie case needs a module with one surface")
        saved = E._ModuleNS[folder]
        E._ModuleNS[folder] = nil
    end
    local even = folder and N - 1 or N
    local a, k = {}, 0
    for _, f in ipairs(COUNTED) do
        if f.folder ~= folder then
            k = k + 1
            SetLook(a, f, k <= even / 2 and "forever" or "eui")
        end
    end
    check(not E.ForeverLookMajority(a), "a tie is no majority")
    if folder then E._ModuleNS[folder] = saved end
end
ACTIVE = { addons = Profile(N) }
check(E.ForeverLookMajority(), "no table reads the active profile")
check(not E.ForeverLookMajority({}), "an empty profile is no majority")

-------------------------------------------------------------------------------
-- 2. The Bags rule and its latch
-------------------------------------------------------------------------------
local function LoadBags(bagsProfile)
    E._bagsDB = { profile = bagsProfile }
    local ns = {}
    assert(loadfile("EllesmereUIBags/EUI_Bags_Style.lua"))("EllesmereUIBags", ns)
    E._ModuleNS.EllesmereUIBags = ns
    return ns
end
local ns = LoadBags({})
local MAJ, MIN = Profile(N), Profile(HALF_UP - 1)
check(ns.BagsForeverWanted({}, MAJ) == true, "unset follows a WoW Forever majority")
check(ns.BagsForeverWanted({}, MIN) == false, "unset follows a majority on other looks")
check(ns.BagsForeverWanted({ useForeverStyle = true }, MIN) == true, "a WoW Forever pick wins over the majority")
check(ns.BagsForeverWanted({ useForeverStyle = false }, MAJ) == false, "an EllesmereUI pick wins over the majority")
check(ns.BagsForeverWanted(nil, MAJ) == true, "no Bags table follows the majority")

ACTIVE = { addons = Profile(N) }
ns = LoadBags({})
check(ns.BagsForever() == true, "an untouched profile on the WoW Forever look latches the style")
ACTIVE = { addons = Profile(0) }
check(ns.BagsForever() == true, "the latch holds for the session")
ns = LoadBags({})
check(ns.BagsForever() == false, "an untouched profile on other looks latches the EllesmereUI style")
ns = LoadBags({ useForeverStyle = true })
check(ns.BagsForever() == true, "a pick latches whatever the majority")

-------------------------------------------------------------------------------
-- 3. The profile switch's reload check
-------------------------------------------------------------------------------
ACTIVE = { addons = Profile(0) }
ns = LoadBags({})                                 -- this session: EllesmereUI style
check(ns.BagsForever() == false, "setup: EllesmereUI style this session")
local function Incoming(addons, bags)
    addons.EllesmereUIBags = bags
    return { addons = addons }
end
check(E.ProfileChangesStyle(Incoming(Profile(N), nil)), "an untouched profile on WoW Forever asks for the reload")
check(not E.ProfileChangesStyle(Incoming(Profile(N), { useForeverStyle = false })),
    "an incoming EllesmereUI pick needs no reload")
check(E.ProfileChangesStyle(Incoming(Profile(0), { useForeverStyle = true })), "an incoming WoW Forever pick asks")
check(not E.ProfileChangesStyle(Incoming(Profile(0), {})), "an untouched profile on other looks needs none")
ACTIVE = { addons = Profile(N) }
ns = LoadBags({})                                 -- this session: WoW Forever style
check(E.ProfileChangesStyle(Incoming(Profile(0), nil)), "leaving the WoW Forever majority asks for the reload")

-------------------------------------------------------------------------------
-- 4. The Style page row
-------------------------------------------------------------------------------
local OPT = Read("EllesmereUIOptions/EUI_Style_Options.lua")
local ROW = Cut(OPT, "if IS_FOREVER then\n    local function BagsProfile()", "BY_KEY.bags = bags")
local fn = assert(loadstring("local MODULES, BY_KEY = {}, {}\nlocal IS_FOREVER = true\n"
    .. "local function NS(folder) return EllesmereUI._ModuleNS and EllesmereUI._ModuleNS[folder] end\n"
    .. ROW .. "return BY_KEY.bags\n", "@StyleOptions"))
local row = fn()
local bp = {}
ACTIVE = { addons = Profile(N) }
ns = LoadBags(bp)
check(row.get() == "forever", "the row reads an untouched profile's majority")
row.set("eui")
check(bp.useForeverStyle == false and row.get() == "eui", "an EllesmereUI pick is saved as false and holds")
row.set("forever")
check(bp.useForeverStyle == true and row.get() == "forever", "a WoW Forever pick is saved as true")
ACTIVE = { addons = Profile(0) }
bp.useForeverStyle = nil
check(row.get() == "eui", "the row reads a majority on other looks")
row.set("forever")
check(bp.useForeverStyle == true and row.get() == "forever", "a WoW Forever pick holds against that majority")

-------------------------------------------------------------------------------
-- 5. Off WoW Forever
-------------------------------------------------------------------------------
E.IS_FOREVER = false
check(not E.ForeverLookMajority(Profile(N)), "no majority off WoW Forever")
ns = LoadBags({ useForeverStyle = true })
check(ns.BagsForever() == false, "no WoW Forever style off WoW Forever")

if fails > 0 then error(fails .. " check(s) failed") end
print("test_bags_forever_style_default: all checks passed (" .. N .. " counted surfaces)")
