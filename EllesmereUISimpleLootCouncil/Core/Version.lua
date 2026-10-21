if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Version = {}
addon.Version = Version







local ADDON_NAME = ...
local OWN = C_AddOns.GetAddOnMetadata(ADDON_NAME, "X-SLC-Version")
    or C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "0.0.0"
Version.OWN = OWN
addon.VERSION = OWN







local function Parts(version)
    if type(version) ~= "string" then return 0, 0, 0 end
    local major, minor, patch = version:match("^(%d*)%.?(%d*)%.?(%d*)")
    return tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0
end


function Version:Compare(a, b)
    local a1, a2, a3 = Parts(a)
    local b1, b2, b3 = Parts(b)
    if a1 ~= b1 then return a1 < b1 and -1 or 1 end
    if a2 ~= b2 then return a2 < b2 and -1 or 1 end
    if a3 ~= b3 then return a3 < b3 and -1 or 1 end
    return 0
end

function Version:IsOlder(a, b) return Version:Compare(a, b) < 0 end






local seen = {}



local highest = OWN



local warned = false

function Version:Record(fullName, version)
    if not fullName or type(version) ~= "string" or version == "" then return end

    local previous = seen[fullName]
    seen[fullName] = { version = version, at = GetTime() }

    if not previous or previous.version ~= version then
        addon.Log:D("Version", fullName, version)
    end

    if Version:IsOlder(highest, version) then
        highest = version
        addon.Log:I("Version", "newest build seen is now", highest)
    end

    Version:WarnIfBehind()
    addon.Callbacks:Fire("VersionChanged")
end



function Version:Knows(fullName)
    return seen[fullName] ~= nil
end

function Version:Get(fullName)
    local record = seen[fullName]
    return record and record.version or nil
end

function Version:Highest() return highest end


function Version:Survey()
    local rows = {}
    for fullName in pairs(addon.GetCandidates()) do
        local record = seen[fullName]
        rows[#rows + 1] = {
            name = fullName,
            version = record and record.version or nil,
            behind = record and Version:IsOlder(record.version, highest) or false,
        }
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows
end

function Version:WarnIfBehind()
    if warned then return end
    if not Version:IsOlder(OWN, highest) then return end
    warned = true
    addon.Chat.Print(addon.Locale.Format(T["you are running %s and someone in your group is on %s. Older builds can silently drop fields from messages - update when you get a chance."], OWN, highest))
    addon.Log:I("Version", "local build", OWN, "is behind", highest)
end





local function Announce()
    local spec = addon.Specs and addon.Specs:OwnSpec()
    addon.Comms:Send("hello", { v = OWN, s = spec })
    local legacy = addon.Comms.LegacyAnnounce
    if legacy then legacy(addon.Comms, OWN) end
    local me = addon.Player:GetFullName("player")
    if me then Version:Record(me, OWN) end
end

local pendingAnnounce = false
function Version:RequestAnnounce(delay)
    if pendingAnnounce then return end
    pendingAnnounce = true
    C_Timer.After(delay or 0.25, function()
        pendingAnnounce = false
        Announce()
    end)
end

local function Digest()
    local entries = {}
    for name in pairs(addon.GetCandidates()) do
        local record = addon.Player:Get(name)
        if record.guid then
            local version = Version:Get(name)
            local spec = addon.Specs and addon.Specs:Get(record.guid)
            if version or spec then
                entries[#entries + 1] = {
                    g = addon.Player:ForTransmit(record), v = version, s = spec,
                }
            end
        end
    end
    return { e = entries }
end

local function OnRosterChanged(diff)
    addon.Callbacks:Fire("VersionChanged")
    if not diff.inGroup then return end

    if not diff.wasInGroup then Version:RequestAnnounce() end
    if not next(diff.joined) then return end
    local me = addon.Player:GetFullName("player")
    local leader = addon.GetGroupLeader()
    if not me or not leader or not addon.Player:IsSame(me, leader) then return end
    local joiners = {}
    for name in pairs(diff.joined) do
        if not addon.Player:IsSame(name, me) then joiners[#joiners + 1] = name end
    end
    if #joiners == 0 then return end
    local digest = Digest()
    if #joiners >= 3 then
        addon.Comms:Send("hello_digest", digest)
    else
        for _, name in ipairs(joiners) do
            addon.Comms:Send("hello_digest", digest, name)
        end
    end
end

function Version:Poll()
    addon.Comms:Send("version_request", {})
end



local POLL_COOLDOWN = 30
local lastPollAnswer, whisperedAt = -math.huge, {}

local function AnswerPoll(sender)
    local now = GetTime()
    if now - lastPollAnswer >= POLL_COOLDOWN then
        lastPollAnswer, whisperedAt = now, {}
        Version:RequestAnnounce(math.random() * 2)
        return
    end
    local key = addon.Player:NameKey(sender) or sender
    if whisperedAt[key] then return end
    whisperedAt[key] = true
    local spec = addon.Specs and addon.Specs:OwnSpec()
    addon.Comms:Send("hello", { v = OWN, s = spec }, sender)
end
Version.AnswerPoll = AnswerPoll

function Version:Init()
    local function RecordHello(args, sender)
        if type(args) ~= "table" then return end
        local record = addon.Player:Get(sender)
        if type(args.v) == "string" then
            Version:Record(record.fullName or sender, args.v)
        end
        if record.guid and addon.Specs then
            addon.Specs:Set(record.guid, args.s, "hello")
        end
    end

    addon.Comms:Register("hello", "any", RecordHello)
    addon.Comms:Register("version", "any", function(args, sender)
        RecordHello(args, sender)
    end)

    addon.Comms:Register("hello_digest", "any", function(args, sender)
        local leader = addon.GetGroupLeader()
        if not leader or not addon.Player:IsSame(sender, leader)
            or type(args) ~= "table" or type(args.e) ~= "table" then return end
        for _, entry in ipairs(args.e) do
            if type(entry) == "table" and type(entry.g) == "string" then
                local record = addon.Player:Get(entry.g)
                if record.guid then
                    if type(entry.v) == "string" then
                        Version:Record(record.fullName, entry.v)
                    end
                    if addon.Specs then addon.Specs:Set(record.guid, entry.s, "digest") end
                end
            end
        end
    end)


    addon.Comms:Register("version_request", "any", function(_, sender)
        if addon.Player:IsSame(sender, addon.Player:GetFullName("player")) then return end
        AnswerPoll(sender)
    end)


    local function Reannounce() Version:RequestAnnounce() end
    addon.Comms:OnResume("hello", Reannounce)
    addon.Comms:OnResume("legacy", Reannounce)
    addon.Comms:OnResume("version_request", function() Version:Poll() end)

    addon.Callbacks:Register("RosterChanged", OnRosterChanged)
    addon.Callbacks:Register("LegacyPeer", function(sender, version)
        local record = addon.Player:Get(sender)
        Version:Record(record.fullName or sender, version)
    end)

    Version:RequestAnnounce(1)
    local leader = IsInGroup() and addon.GetGroupLeader()
    if leader and addon.Player:IsSame(leader, addon.Player:GetFullName("player")) then


        C_Timer.After(2, function()
            local current = IsInGroup() and addon.GetGroupLeader()
            if current and addon.Player:IsSame(current,
                addon.Player:GetFullName("player")) then Version:Poll() end
        end)
    end
    addon.Log:I("Version", "ready", OWN)
end
