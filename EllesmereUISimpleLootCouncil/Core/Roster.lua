if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local IsSecret = addon.IsSecret

local Roster = {}
addon.Roster = Roster
local epoch, members, inGroup = 0, {}, false


local memberKeys, aliases, selfKey = {}, {}, nil
local unitByGUID = {}



local slotName, slotFull, slotUnit = {}, {}, {}
local slotCount, slotMode = 0, nil
local unitOfName = {}
local leaderCached, leaderValue = false, nil
local snapshotLeader
local pending, initialised = false, false
local cachedML, cachedAt = nil, 0

local membersGen, buildGen = nil, 0

function Roster:Epoch() return epoch end




local guidOfUnit, unitStamp, stamp = {}, {}, 0

local function NoteUnit(unit)
    local guid = UnitGUID and UnitGUID(unit)
    if not guid or IsSecret(guid) then guid = nil end
    unitStamp[unit] = stamp
    local old = guidOfUnit[unit]
    if old == guid then return end
    if old and unitByGUID[old] == unit then unitByGUID[old] = nil end
    guidOfUnit[unit] = guid
    if guid then unitByGUID[guid] = unit end
end

function Roster:RebuildUnitCache()
    stamp = stamp + 1
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    if IsInRaid and IsInRaid() then
        for i = 1, count do NoteUnit("raid" .. i) end
    else
        NoteUnit("player")
        for i = 1, math.max(0, count - 1) do NoteUnit("party" .. i) end
    end
    for unit, seen in pairs(unitStamp) do
        if seen ~= stamp then
            local old = guidOfUnit[unit]
            if old and unitByGUID[old] == unit then unitByGUID[old] = nil end
            guidOfUnit[unit], unitStamp[unit] = nil, nil
        end
    end
end

function Roster:UnitForGUID(guid)
    local unit = unitByGUID[guid]
    local current = unit and UnitGUID and UnitGUID(unit)
    if current and not IsSecret(current) and current == guid then return unit end
    return nil
end



local function FindLeader()
    local function FromUnit(unit)
        local name, realm = UnitFullName(unit)

        if IsSecret(name) or IsSecret(realm) or not name or name == ""
            or name == UNKNOWNOBJECT then return nil end
        return addon.Player:GetFullName(unit)
    end
    if not IsInGroup() then return FromUnit("player") end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if not IsSecret(name) and not IsSecret(rank) and rank == 2 and name
                and name ~= "" and name ~= UNKNOWNOBJECT then
                if slotMode == "raid" and slotName[i] == name and slotFull[i] then
                    return slotFull[i]
                end
                local record = addon.Player:Get(name)
                return record.guid and record.fullName or nil
            end
        end
        return nil
    end
    if UnitIsGroupLeader("player") then
        return FromUnit("player")
    end
    for i = 1, GetNumGroupMembers() - 1 do
        local unit = "party" .. i
        if UnitExists(unit) and UnitIsGroupLeader(unit) then
            return FromUnit(unit)
        end
    end
    return nil
end



function addon.GetGroupLeader()
    if leaderCached then return leaderValue end
    local leader = FindLeader()
    leaderValue, leaderCached = leader, leader ~= nil
    return leader
end


local indexedSet

local function MemberSet()
    local set = addon.GetCandidates()
    if set ~= indexedSet then
        indexedSet, memberKeys, aliases = set, {}, {}
        for name in pairs(set) do
            local key = addon.Player:NameKey(name)
            if key then memberKeys[key] = true end
        end
    end
    return set
end




function Roster:IsMember(name)
    if IsSecret(name) or type(name) ~= "string" or name == "" then return false end
    if MemberSet()[name] or aliases[name] then return true end
    local key = addon.Player:NameKey(name)
    if key then
        selfKey = selfKey or addon.Player:NameKey(addon.Player:GetFullName("player"))
        if memberKeys[key] or key == selfKey then
            aliases[name] = true
            return true
        end
    end
    if not (IsInGroup and IsInGroup()) or not Ambiguate then return false end
    local unit = Ambiguate(name, "none")
    if addon.Player.IsUnitToken and addon.Player.IsUnitToken(unit) then
        return addon.Player.GroupUnitNamed(unit) ~= nil
    end
    local index = UnitInRaid and UnitInRaid(unit)
    if IsSecret(index) then return false end
    if index then return true end
    local here = UnitInParty and UnitInParty(unit)
    if IsSecret(here) then return false end
    return here and true or false
end

local function Rebuild(immediate)
    if not initialised then return end
    Roster:RebuildUnitCache()
    local nowInGroup = IsInGroup() and true or false
    local current = nowInGroup and addon.GetCandidates() or {}
    local joined, left = {}, {}

    if not (nowInGroup and inGroup and membersGen == buildGen) then
        for name in pairs(current) do
            if not members[name] then joined[name] = true end
        end
        for name in pairs(members) do
            if not current[name] then left[name] = true end
        end
    end
    local oldLeader = snapshotLeader
    leaderCached = false
    local newLeader = addon.GetGroupLeader()
    local leaderChanged = oldLeader ~= newLeader
    snapshotLeader = newLeader
    local wasInGroup = inGroup
    members, inGroup = current, nowInGroup
    membersGen = nowInGroup and buildGen or nil
    if next(joined) or next(left) or leaderChanged or wasInGroup ~= nowInGroup then
        addon.Callbacks:Fire("RosterChanged", {
            joined = joined, left = left, leaderChanged = leaderChanged,
            inGroup = nowInGroup, wasInGroup = wasInGroup,
            immediate = immediate and true or false,
        })
    end
end

function Roster:Init()
    initialised = true
    self:RebuildUnitCache()
    inGroup = IsInGroup() and true or false
    members = inGroup and addon.GetCandidates() or {}
    membersGen = inGroup and buildGen or nil
    selfKey = addon.Player:NameKey(addon.Player:GetFullName("player"))
    leaderCached = false
    snapshotLeader = addon.GetGroupLeader()
end


local rosterFrame = CreateFrame("Frame")
rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
rosterFrame:RegisterEvent("PARTY_LEADER_CHANGED")
rosterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")


if addon.IsForever then pcall(rosterFrame.RegisterEvent, rosterFrame, "PARTY_LOOT_METHOD_CHANGED") end
rosterFrame:SetScript("OnEvent", function(_, event)
    if not initialised then return end
    epoch = epoch + 1
    leaderCached = false
    cachedML, cachedAt = nil, 0
    if event == "PARTY_LOOT_METHOD_CHANGED" then
        if addon.Loot and addon.Loot.CheckLootMaster then
            addon.Loot:CheckLootMaster("loot method changed")
        end
        addon.Callbacks:Fire("LootMethodChanged")
        return
    end
    if event == "PARTY_LEADER_CHANGED" then addon.GetGroupLeader() end


    if event ~= "PLAYER_ENTERING_WORLD" and inGroup and not IsInGroup() then
        pending = false
        Rebuild(true)
        return
    end
    if pending then return end
    pending = true
    C_Timer.After(0.25, function()
        if not pending then return end
        pending = false
        Rebuild(false)
    end)
end)











local ML_TTL = 0.2



function addon.GroupOnMasterLoot()
    if not IsInGroup() then return false end
    if not (C_PartyInfo and C_PartyInfo.GetLootMethod and Enum.LootMethod) then return false end
    local method = C_PartyInfo.GetLootMethod()
    return not IsSecret(method) and method == Enum.LootMethod.Masterlooter
end


function addon.GetGameMasterLooter()
    if not addon.IsForever or not addon.GroupOnMasterLoot() then return nil end
    local _, partyID, raidID = C_PartyInfo.GetLootMethod()
    if IsSecret(partyID) or IsSecret(raidID) then return nil end
    local unit
    if IsInRaid() then
        unit = raidID and ("raid" .. raidID)
    elseif partyID == 0 then
        unit = "player"
    elseif partyID then
        unit = "party" .. partyID
    end
    if not unit or not UnitExists(unit) then return nil end
    return addon.Player:GetFullName(unit)
end



function addon.SetGameMasterLooter(unit)
    if not addon.GetGameMasterLooter() or not unit or not UnitExists(unit) then return false end
    local name = GetUnitName(unit, true)
    if not name or IsSecret(name) then return false end
    return C_PartyInfo.SetLootMethod(Enum.LootMethod.Masterlooter, name) and true or false
end



function addon.GetMasterLooter(fresh)
    local now = GetTime()
    if not fresh and cachedML ~= nil and (now - cachedAt) < ML_TTL then
        return cachedML or nil
    end


    local result = addon.GetGameMasterLooter()

    local delegate = not result and addon.Config and addon.Config:LootMaster()
    if delegate then
        local record = addon.Player:Get(delegate)
        if record.fullName then


            local candidates = addon.GetCandidates()
            if candidates[record.fullName] then
                result = record.fullName
            end
        end
    end

    result = result or addon.GetGroupLeader()


    cachedML, cachedAt = result or false, now
    return result
end


function addon.InvalidateMasterLooter()
    cachedML, cachedAt = nil, 0
    if addon.Loot and addon.Loot.CheckLootMaster then
        addon.Loot:CheckLootMaster("delegation changed")
    end
end



function addon.IsMasterLooter(who)
    local leader = addon.GetGroupLeader()
    if leader and addon.Player:IsSame(who, leader) then return true end

    local delegate = addon.Config and addon.Config:LootMaster()
    if delegate and addon.Player:IsSame(who, delegate) then return true end

    local game = addon.GetGameMasterLooter()
    if game and addon.Player:IsSame(who, game) then return true end

    return false
end



function addon.IsLootDelegated()
    local current = addon.GetMasterLooter()
    local leader = addon.GetGroupLeader()
    if not current or not leader then return false end
    return not addon.Player:IsSame(current, leader)
end



function addon.CanAssignMasterLooter()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") and true or false
end




local groupTest = false
function addon.GroupTestActive()
    if groupTest and (not IsInGroup() or IsInRaid()) then groupTest = false end
    return groupTest
end
function addon.SetGroupTest(on)
    groupTest = on and true or false
end

function addon.PlayerIsMasterLooter()
    if not IsInGroup() then return true end
    local current = addon.GetMasterLooter()
    if not current then return false end
    return addon.Player:IsSame(current, addon.Player:GetFullName("player"))
end


local function SettleBuild(mode, count, changed, complete)
    if mode ~= slotMode or count ~= slotCount then changed = true end
    for i = count + 1, slotCount do slotName[i], slotFull[i], slotUnit[i] = nil, nil, nil end
    slotMode, slotCount = mode, count
    if changed or not complete then
        buildGen = buildGen + 1
        for name in pairs(unitOfName) do unitOfName[name] = nil end
        for i = 1, count do
            if slotFull[i] then unitOfName[slotFull[i]] = slotUnit[i] end
        end
    end
end


local function PartySlot(k, unit)
    local full = addon.Player:GetFullName(unit)
    local moved = slotFull[k] ~= full or slotUnit[k] ~= unit
    slotFull[k], slotUnit[k] = full, unit
    return full, moved
end


local function BuildCandidates()
    local candidates, complete, changed = {}, true, false

    if not IsInGroup() then
        local full, moved = PartySlot(1, "player")
        if full then candidates[full] = true else complete = false end
        SettleBuild("solo", 1, moved, complete)
        return candidates, complete
    end

    if IsInRaid() then
        local count = GetNumGroupMembers()
        local reuse = slotMode == "raid"
        for i = 1, count do
            local name = GetRaidRosterInfo(i)
            if not IsSecret(name) and name and name ~= "" and name ~= UNKNOWNOBJECT then
                local full = reuse and slotName[i] == name and slotFull[i]
                if full then
                    candidates[full] = true
                else
                    changed = true
                    local record = addon.Player:Get(name)
                    if record.fullName and not record.unresolved then
                        slotName[i], slotFull[i], slotUnit[i] = name, record.fullName, "raid" .. i
                    else
                        slotName[i], slotFull[i], slotUnit[i] = nil, nil, nil
                        complete = false
                    end
                    if record.fullName then candidates[record.fullName] = true end
                end
            else
                changed = changed or slotFull[i] ~= nil
                slotName[i], slotFull[i], slotUnit[i] = nil, nil, nil
                complete = false
            end
        end
        SettleBuild("raid", count, changed, complete)
        return candidates, complete
    end

    local full, moved = PartySlot(1, "player")
    changed = moved
    if full then candidates[full] = true else complete = false end
    local count = GetNumGroupMembers()
    for i = 1, count - 1 do
        local unit = "party" .. i
        if UnitExists(unit) then
            full, moved = PartySlot(i + 1, unit)
            changed = changed or moved
            if full then candidates[full] = true else complete = false end
        else
            changed = changed or slotFull[i + 1] ~= nil
            slotName[i + 1], slotFull[i + 1], slotUnit[i + 1] = nil, nil, nil
        end
    end
    SettleBuild("party", math.max(count, 1), changed, complete)
    return candidates, complete
end



local candidateSet, candidateEpoch = nil, nil


function addon.GetCandidates()
    if initialised and candidateSet and candidateEpoch == epoch then return candidateSet end
    local candidates, complete = BuildCandidates()
    if not complete then epoch = epoch + 1 end
    if initialised and complete then
        candidateSet, candidateEpoch = candidates, epoch
    else
        candidateSet = nil
    end
    return candidates
end


function Roster:UnitForName(fullName)
    addon.GetCandidates()
    if not (candidateSet and candidateEpoch == epoch) then return nil end
    return unitOfName[fullName]
end
