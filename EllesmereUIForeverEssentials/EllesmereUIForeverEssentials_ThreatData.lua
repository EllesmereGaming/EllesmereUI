if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if not (EllesmereUI and EllesmereUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  EllesmereUIForeverEssentials_ThreatData.lua  (WoW Forever only)
--  Threat data for the threat meter (drawn by the ThreatMeter file after this
--  one): the mob whose threat is shown, the group's threat on it read from
--  prebuilt unit tokens, the pull aggro line and the sort. Forever hands the
--  threat API over readable (C_Secrets.ShouldUnitThreatValuesBeSecret is false
--  there); a value that does come back secret skips that unit.
-------------------------------------------------------------------------------
local _, module = ...
module.ThreatMeter = module.ThreatMeter or {}
local ns = module.ThreatMeter

-- The secret test comes first: comparing a secret, even to nil, is an error.
local function Readable(v)
    return not issecretvalue(v) and v ~= nil
end

-- Every group token the meter reads, built once: Collect walks the lists and
-- the threat-situation filter looks tokens up in the sets. PET_OWNER maps a pet
-- token to its owner's, so a pet row takes its owner's class.
local RAID_UNITS, RAID_PETS, PARTY_UNITS, PARTY_PETS = {}, {}, {}, {}
local MEMBER_UNITS, PET_UNITS, PET_OWNER = { player = true }, { pet = true }, { pet = "player" }
for i = 1, 40 do
    local u, p = "raid" .. i, "raidpet" .. i
    RAID_UNITS[i], RAID_PETS[i], MEMBER_UNITS[u], PET_UNITS[p], PET_OWNER[p] = u, p, true, true, u
end
for i = 1, 4 do
    local u, p = "party" .. i, "partypet" .. i
    PARTY_UNITS[i], PARTY_PETS[i], MEMBER_UNITS[u], PET_UNITS[p], PET_OWNER[p] = u, p, true, true, u
end
ns.MEMBER_UNITS, ns.PET_UNITS = MEMBER_UNITS, PET_UNITS

-- What a tracked unit is fighting, as a prebuilt token.
local TARGET_OF = { target = "targettarget", focus = "focustarget" }

-- The mob whose threat table is shown: the tracked unit when you can attack it,
-- otherwise what it is fighting (a healer targeting the tank).
function ns.ResolveSource(unit)
    if UnitExists(unit) and UnitCanAttack("player", unit) then return unit end
    local mob = TARGET_OF[unit]
    if mob and UnitExists(mob) and UnitCanAttack("player", mob) then return mob end
end

-------------------------------------------------------------------------------
--  Roster memos: the player's own raid token and each token's class. Both are
--  functions of the roster alone, so GROUP_ROSTER_UPDATE (RosterChanged) is
--  their one invalidation; rosterGen also stamps the meter's painted rows.
-------------------------------------------------------------------------------
ns.rosterGen = 0
local classMemo = {}
local selfToken, selfGen

function ns.RosterChanged()
    ns.rosterGen = ns.rosterGen + 1
    wipe(classMemo)
end

local function SelfToken(inRaid)
    if not inRaid then return "player" end
    if selfGen ~= ns.rosterGen then
        selfToken = nil
        for i = 1, GetNumGroupMembers() do
            local same = UnitIsUnit(RAID_UNITS[i], "player")
            if not issecretvalue(same) and same then selfToken = RAID_UNITS[i]; break end
        end
        -- Only a found token is kept: an early roster read retries next pass.
        if selfToken then selfGen = ns.rosterGen end
    end
    return selfToken
end

-- Class file of a unit token; a pet token answers with its owner's class.
function ns.ClassOf(unit)
    local class = classMemo[unit]
    if class then return class end
    local _, file = UnitClass(PET_OWNER[unit] or unit)
    if not issecretvalue(file) and file then
        classMemo[unit] = file
        return file
    end
end

-------------------------------------------------------------------------------
--  Collect: one plain threat read per group token, into pooled entries.
--  Entry fields: key (row identity: the unit token, "pull", or a preview
--  sample), unit, raw (threat value), scaled (percent of your own pull line,
--  100 = you pull aggro), rawPct (percent of the tank's threat), tanking, own,
--  isPet, pull, order (stable tie-break).
-------------------------------------------------------------------------------
local entries, list = {}, {}
ns.list = list
local count = 0

local function Add(unit, mob, isPet)
    if not UnitExists(unit) then return end
    local tanking, _, scaled, rawPct, raw = UnitDetailedThreatSituation(unit, mob)
    if not (Readable(raw) and Readable(scaled) and Readable(tanking)) or raw <= 0 then return end
    count = count + 1
    local e = entries[count]
    if not e then e = {}; entries[count] = e end
    e.key, e.unit, e.raw, e.scaled, e.tanking = unit, unit, raw, scaled, tanking
    e.rawPct = Readable(rawPct) and rawPct or nil
    e.isPet, e.pull, e.own, e.order = isPet, false, false, count
    list[#list + 1] = e
end

-- Fills the list for `mob`; returns your own entry and the tank's raw threat
-- (nil when nobody in the group holds aggro).
function ns.Collect(mob, pets)
    count = 0
    for i = #list, 1, -1 do list[i] = nil end
    local inRaid = IsInRaid()
    if inRaid then
        for i = 1, GetNumGroupMembers() do
            Add(RAID_UNITS[i], mob, false)
            if pets then Add(RAID_PETS[i], mob, true) end
        end
    else
        Add("player", mob, false)
        if pets then Add("pet", mob, true) end
        for i = 1, GetNumSubgroupMembers() do
            Add(PARTY_UNITS[i], mob, false)
            if pets then Add(PARTY_PETS[i], mob, true) end
        end
    end
    local own = SelfToken(inRaid)
    local me, tankRaw
    for i = 1, #list do
        local e = list[i]
        if e.unit == own then e.own = true; me = e end
        if e.tanking then tankRaw = e.raw end
    end
    return me, tankRaw
end

-- Where you pull aggro: scaled percent is threat against your own pull line
-- (100 = you take it), so the line is your threat scaled up to 100. That keeps
-- the API's melee/ranged distance rule without guessing it. Nothing while you
-- tank. rawPct is the line as a percent of the tank's threat.
function ns.FillPullEntry(e, me, tankRaw)
    if not (me and not me.tanking and me.scaled > 0) then return nil end
    local raw = me.raw * 100 / me.scaled
    e.key, e.unit, e.pull, e.raw, e.scaled = "pull", nil, true, raw, 100
    e.rawPct = (tankRaw and tankRaw > 0) and raw * 100 / tankRaw or nil
    e.tanking, e.own, e.isPet, e.order = false, false, false, 0
    return e
end

local pullEntry = {}

function ns.AddPullEntry(me, tankRaw)
    if ns.FillPullEntry(pullEntry, me, tankRaw) then list[#list + 1] = pullEntry end
end

-- Highest raw threat first, the pull line sorted in with everyone.
local function ByThreat(a, b)
    if a.raw ~= b.raw then return a.raw > b.raw end
    return a.order < b.order
end
ns.ByThreat = ByThreat

function ns.Sort()
    table.sort(list, ByThreat)
end
