-- Stub harness: Raid & Party Frames, Party Frames in Small Raids (partySmallRaid)
-- and where it applies. The setting shows group 1 as party frames while a raid
-- holds fewer than 10 players; inside a battleground it stands down (a
-- battleground raid starts under 10 and dips under 10 with every leave), and
-- an arena keeps its own rule (the whole team as party frames).
-- Loads EUI_RaidFrames_Visibility.lua and EUI_RaidFrames_PartyLayout.lua over
-- stubs and checks, for every instance type, group state, setting value and
-- Show When Solo pair (648 states): the gate itself, "party or raid frames",
-- the group-1 limit, both secure visibility macros, that the macros show what
-- the Lua side wants, and the party header's group filter and name list.
--   lua .tools/tests/test_rf_small_raid_battleground.lua   (from the repository root)
local ROOT = arg and arg[1] or "."

local function ReadSource(name)
    local f = assert(io.open(ROOT .. "/" .. name, "rb"))
    local src = f:read("*a")
    f:close()
    return src
end

local S = { inst = "none", raid = false, group = false, n = 0, combat = false }
IsInInstance = function() return S.inst ~= "none", S.inst end
IsInRaid = function() return S.raid end
IsInGroup = function() return S.group end
GetNumGroupMembers = function() return S.n end
InCombatLockdown = function() return S.combat end
UnitExists = function() return false end
UnitIsConnected = function() return true end
UnitIsVisible = function() return true end
UnitIsDeadOrGhost = function() return false end
UnitIsUnit = function() return false end
UnitInRange = function() return true end
C_Timer = {
    NewTicker = function() return { Cancel = function() end } end,
    After = function() end,
    NewTimer = function() return { Cancel = function() end } end,
}
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
EUI_CLIENT_BLOCKED = nil

local registered = 0
RegisterStateDriver = function(frame, kind, macro)
    assert(kind == "visibility", "a driver of another kind was registered")
    frame._drv = macro
    registered = registered + 1
end

local function FakeFrame(name)
    local f = { _name = name, _shown = true, _attrs = {}, _alpha = 1 }
    function f:GetAttribute(k) return self._attrs[k] end
    function f:SetAttribute(k, v) self._attrs[k] = v end
    function f:IsShown() return self._shown end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:SetShown(v) self._shown = v and true or false end
    function f:SetAlpha(a) self._alpha = a end
    function f:GetAlpha() return self._alpha end
    function f:ClearAllPoints() end
    return f
end

-- The module's chain table, with what the two files read from it
local ns = {}
local I = {
    broken = false,
    allButtons = {}, FFD = {}, GetFFD = function() return {} end,
    separatedHdrs = {}, unitToButton = {},
    RebuildUnitMap = function() end, UpdateAllButtons = function() end,
    LayoutGroups = function() end,
    SetRangeUpdate = function() end,
    playerFriendlySpell = false, playerRezSpell = false,
    dbSetters = {}, containerFrameSetters = {}, framesVisibleSetters = {},
    ApplyFont = function() end, eventFrame = FakeFrame("ev"),
    IsPowerBarEnabled = function() return false end,
    PixelSnap = function(v) return v end,
    ResolveHealthTexture = function() end,
    unitTrackers = {}, LayoutTopNameBar = function() end,
    StyleButton = function() end,
}
I.SetFramesVisible = function(v) for i = 1, #I.framesVisibleSetters do I.framesVisibleSetters[i](v) end end
ns._internals = I
ns._partyUnitToButton, ns._xfUnitToButton = {}, {}

for _, name in ipairs({ "EllesmereUIRaidFrames/EUI_RaidFrames_Visibility.lua", "EllesmereUIRaidFrames/EUI_RaidFrames_PartyLayout.lua" }) do
    assert(loadstring(ReadSource(name), "=" .. name:match("[^/]+$")))("EllesmereUIRaidFrames", ns)
    assert(I.broken == false, name .. " left the chain broken")
end

local P = {}
for i = 1, #I.dbSetters do I.dbSetters[i]({ profile = P }) end
local raidContainer = FakeFrame("raidContainer")
for i = 1, #I.containerFrameSetters do I.containerFrameSetters[i](raidContainer) end
ns._partyContainerFrame = FakeFrame("partyContainer")
ns._partyHeader = FakeFrame("partyHeader")

-- what _LayoutPartyFrames calls outside this test's subject
ns.RF_PartyDims = function() return 100, 40, 2 end
ns.PT_AlongPitch = function() return 0 end
ns._PartyGrowth = function() return "DOWN" end
ns._PositionPartySlots = function() return false end
ns._SizePartyContainer = function() end
ns._FrameSortRanks = function() return nil end
ns._BuildArenaNameList = function(_, _, _, _, _, g) return "raidUnits:" .. tostring(g) end
ns._BuildFrameSortRaidPartyNameList = function() return nil end
ns._BuildFrameSortPartyNameList = function() return nil end
ns._BuildPartyClassNameList = function() return nil end
ns.RF_SyncCompact = function() end
ns._PT_Layout = function() end

assert(type(ns._SmallRaidOn) == "function", "the Small Raid gate is gone")

-- A small reader of the visibility macros ("[@unit,exists]" and "[group]"
-- conditions, OR between brackets), over the same group state the stubs give.
local function UnitExistsFor(tok)
    local n = tonumber(tok:match("^raid(%d+)$"))
    if n then return S.raid and n <= S.n end
    if tok == "party1" then return S.group and not S.raid and S.n >= 2 end
    error("a unit this reader does not know: " .. tok)
end
local function Cond(c)
    if c == "group" then return S.group end
    local tok = c:match("^@(%w+),exists$")
    if tok then return UnitExistsFor(tok) end
    error("a condition this reader does not know: " .. c)
end
local function Shows(macro)
    for clause in (macro .. ";"):gmatch("([^;]+);") do
        local conds = {}
        local action = clause:gsub("%[([^%]]*)%]", function(c) conds[#conds + 1] = c; return "" end)
        action = action:gsub("^%s+", ""):gsub("%s+$", "")
        if #conds == 0 then return action == "show" end
        for _, c in ipairs(conds) do
            if Cond(c) then return action == "show" end
        end
    end
    return false
end

local ALL_GROUPS = "1,2,3,4,5,6,7,8"
local M = ns._RF_VIS_MACROS
local insts = { "none", "party", "raid", "scenario", "arena", "pvp" }
local groups = {
    { "solo", false, false, 0 }, { "party of 3", true, false, 3 }, { "party of 5", true, false, 5 },
    { "raid of 1", true, true, 1 }, { "raid of 6", true, true, 6 }, { "raid of 9", true, true, 9 },
    { "raid of 10", true, true, 10 }, { "raid of 15", true, true, 15 }, { "raid of 40", true, true, 40 },
}
local settings = { { true, "on" }, { false, "off" }, { nil, "unset" } }

-- Everything the module decides for the state the stubs hold
local function Read()
    local out = {}
    out.on = ns._SmallRaidOn()
    out.partyInRaid = ns._PartyInRaid()
    out.group = ns._SmallRaidGroup()
    out.wantRaid, out.wantParty = ns._RFVisWanted()
    ns._rfRaidVisMacro, ns._rfPartyVisMacro = nil, nil
    ns._RFSyncVisDrivers()
    out.raidMacro, out.partyMacro = ns._rfRaidVisMacro, ns._rfPartyVisMacro
    ns._partyHeader._attrs = {}
    ns._LayoutPartyFrames()
    out.filter = ns._partyHeader._attrs.groupFilter
    out.names = ns._partyHeader._attrs.nameList
    return out
end

local checked = 0
for _, inst in ipairs(insts) do
    for _, g in ipairs(groups) do
        for _, set in ipairs(settings) do
            for _, solo in ipairs({ true, false }) do
                for _, partySolo in ipairs({ true, false }) do
                    S.inst, S.group, S.raid, S.n = inst, g[2], g[3], g[4]
                    P.partySmallRaid, P.showWhenSolo, P.partyShowWhenSolo = set[1], solo, partySolo
                    local where = ("%s, %s, setting %s, solo %s / %s"):format(inst, g[1], set[2], tostring(solo), tostring(partySolo))
                    local got = Read()
                    checked = checked + 1

                    -- the gate: the setting, everywhere but a battleground
                    local on = set[1] == true and inst ~= "pvp"
                    assert(got.on == on, where .. ": the gate reads " .. tostring(got.on))
                    -- party frames in a raid: the arena, or a gated raid under 10
                    local arena = inst == "arena"
                    local partyInRaid = arena or (on and g[3] and g[4] < 10)
                    assert((got.partyInRaid and true or false) == partyInRaid, where .. ": party frames in a raid read " .. tostring(got.partyInRaid))
                    -- the group-1 limit: Small Raid only, never the arena
                    local limit = (not arena and partyInRaid) and 1 or nil
                    assert(got.group == limit, where .. ": the group limit reads " .. tostring(got.group))
                    -- which set the group state shows
                    local wantRaid, wantParty
                    if not g[2] then wantRaid, wantParty = solo, partySolo
                    elseif g[3] and not partyInRaid then wantRaid, wantParty = true, false
                    else wantRaid, wantParty = false, true end
                    assert(got.wantRaid == wantRaid and got.wantParty == wantParty, where .. ": the wanted sets read "
                        .. tostring(got.wantRaid) .. " / " .. tostring(got.wantParty))
                    -- the macros: by mode, and they show what the Lua side wants
                    local mode = arena and "arena" or (on and "small") or "group"
                    assert(got.raidMacro == M.raid[mode][solo] and got.partyMacro == M.party[mode][partySolo],
                        where .. ": not the " .. mode .. " macros")
                    assert(Shows(got.raidMacro) == wantRaid, where .. ": the raid macro and the Lua side disagree")
                    assert(Shows(got.partyMacro) == wantParty, where .. ": the party macro and the Lua side disagree")
                    -- the party header: a raid-unit name list while party frames
                    -- show a raid, else the native order with the group limit
                    if wantParty and partyInRaid then
                        assert(got.names == "raidUnits:" .. tostring(limit) and got.filter == nil,
                            where .. ": the header's name list reads " .. tostring(got.names) .. ", filter " .. tostring(got.filter))
                    else
                        local filter = (on and not arena) and "1" or ALL_GROUPS
                        assert(got.names == nil and got.filter == filter, where .. ": the header's group filter reads " .. tostring(got.filter))
                    end
                end
            end
        end
    end
end
assert(checked == 648, "states checked: " .. checked)

-- In a battleground the setting changes nothing at all: every answer equals
-- the one with the setting off, at every size a team passes through
S.inst, S.group, S.raid = "pvp", true, true
for _, solo in ipairs({ true, false }) do
    P.showWhenSolo, P.partyShowWhenSolo = solo, solo
    for _, n in ipairs({ 1, 3, 6, 9, 10, 12, 9, 10, 8 }) do
        S.n = n
        P.partySmallRaid = true
        local a = Read()
        P.partySmallRaid = false
        local b = Read()
        for k, v in pairs(a) do assert(b[k] == v, "battleground of " .. n .. ": " .. k .. " differs from the setting off") end
        for k, v in pairs(b) do assert(a[k] == v, "battleground of " .. n .. ": " .. k .. " differs from the setting off") end
        assert(a.wantRaid == true and a.wantParty == false and Shows(a.raidMacro) and not Shows(a.partyMacro),
            "battleground of " .. n .. ": not on the raid frames")
    end
end

-- The macros are registered once (out of combat) and then read the roster by
-- themselves: a battleground's stay on the raid frames as the team grows and
-- shrinks, the open world's switch at 10
P.partySmallRaid, P.showWhenSolo, P.partyShowWhenSolo = true, false, false
S.inst, S.group, S.raid, S.n = "pvp", true, true, 1
ns._rfRaidVisMacro, ns._rfPartyVisMacro = nil, nil
ns._RFSyncVisDrivers()
local before = registered
for _, n in ipairs({ 1, 3, 6, 9, 10, 12, 9, 10, 8 }) do
    S.n = n
    ns._RFSyncVisDrivers()
    assert(Shows(ns._rfRaidVisMacro) and not Shows(ns._rfPartyVisMacro), "a battleground raid of " .. n .. " left the raid frames")
end
assert(registered == before, "an unchanged macro was registered again")
S.inst, S.n = "none", 1
ns._RFSyncVisDrivers()
assert(registered == before + 2, "leaving the battleground did not register the Small Raid macros")
for _, n in ipairs({ 1, 3, 6, 9, 10, 12, 9, 10, 8 }) do
    S.n = n
    assert(Shows(ns._rfRaidVisMacro) == (n >= 10) and Shows(ns._rfPartyVisMacro) == (n < 10),
        "open world raid of " .. n .. ": the switch at 10 moved")
end
-- in combat no macro is registered: the mode waits for the pass after it
S.inst, S.combat = "pvp", true
ns._RFSyncVisDrivers()
assert(registered == before + 2, "a macro was registered in combat")
S.combat = false
ns._RFSyncVisDrivers()
assert(registered == before + 4 and ns._rfRaidVisMacro == M.raid.group[false], "the pass after combat did not take the battleground's macros")

print(("raid frames small raid in battlegrounds harness: %d states, ok"):format(checked))
