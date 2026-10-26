if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local AutoStart = {}
addon.AutoStart = AutoStart


local MAX_KILLS = 4

local kills = {}
local queued = {}
local frame
local listening = false
local flushPending = false
local toldCouncil = false
local warnedFor


local function IsHost()
    return IsInRaid() and addon.PlayerIsMasterLooter() and addon.Loot.handling == true
end

local function Enabled()
    return not addon.db or addon.db.autoStart ~= false
end

local function SyncEvents()
    local want = #kills > 0
    if want == listening then return end
    listening = want
    if want then
        frame:RegisterEvent("LOOT_HISTORY_UPDATE_ENCOUNTER")
        frame:RegisterEvent("LOOT_HISTORY_UPDATE_DROP")
        frame:RegisterEvent("LOOT_HISTORY_CLEAR_HISTORY")
    else
        frame:UnregisterEvent("LOOT_HISTORY_UPDATE_ENCOUNTER")
        frame:UnregisterEvent("LOOT_HISTORY_UPDATE_DROP")
        frame:UnregisterEvent("LOOT_HISTORY_CLEAR_HISTORY")
    end
end

local function Forget(why)
    if #kills == 0 and #queued == 0 then return end
    wipe(kills)
    wipe(queued)
    toldCouncil = false
    SyncEvents()
    addon.Log:D("AutoStart", "boss loot no longer followed -", why)
end

local function FindKill(encounterID)
    for _, kill in ipairs(kills) do
        if kill.id == encounterID then return kill end
    end
    return nil
end



local function Finished()
    for _, item in ipairs(addon.Session:GetItems()) do
        if not item.simulated and not item.awarded and not item.removed
            and (not item.gone or item.gone == "pending") then
            return false
        end
    end
    return true
end

local function WinnerName(winner)
    local name = winner and winner.playerName
    if type(name) ~= "string" or addon.IsSecret(name) or name == "" then return nil end
    return Ambiguate(name, "short")
end



local function Settle(kill, listID, drop)
    local id = kill.items[listID]
    if not id then return end
    local winner = drop.winner
    local lost = drop.allPassed == true or (winner ~= nil and winner.isSelf ~= true)
    if not lost and not winner then return end
    kill.items[listID] = nil
    if not addon.Session:DropSettled(id, not lost) or not lost then return end
    local name = not drop.allPassed and WinnerName(winner)
    if name then
        addon.Chat.Warn(addon.Locale.Format(
            T["%s went to %s in the loot roll, so the council cannot award it. Right-click it in the council list to remove it from the run."],
            drop.itemHyperlink, name))
    else
        addon.Chat.Warn(addon.Locale.Format(
            T["%s did not come to you in the loot roll, so the council cannot award it. Right-click it in the council list to remove it from the run."],
            drop.itemHyperlink))
    end
end



local Flush

local function FlushSoon()
    if flushPending or #queued == 0 then return end
    flushPending = true
    C_Timer.After(0, function()
        flushPending = false
        Flush()
    end)
end

Flush = function()
    if #queued == 0 then return end
    if not IsHost() then
        Forget("no longer running the loot")
        return
    end
    if not Enabled() then
        Forget("automatic start turned off")
        return
    end
    if addon.Restrictions:IsBlocked() then return end
    local Session = addon.Session
    if Session:IsRunning() and Finished() then
        addon.Log:I("AutoStart", "every item of the open run is settled - ending it for the new loot")
        Session:End()
    end
    if not Session:IsRunning() and addon.Council:GetCount() == 0 then
        if not toldCouncil then
            toldCouncil = true
            addon.Chat.Print(addon.Locale.Format(T["could not start the run: %s"],
                T["the council is not ready"]))
        end
        return
    end
    toldCouncil = false

    local batch = queued
    queued = {}
    local links, bosses, encounterIDs = {}, {}, {}
    for i, entry in ipairs(batch) do
        links[i], bosses[i], encounterIDs[i] = entry.link, entry.kill.name, entry.kill.id
    end
    local running = Session:IsRunning()
    local indices = Session:AddDrops(links, bosses, encounterIDs)
    local items = Session:GetItems()
    for i, entry in ipairs(batch) do
        local item = indices[i] and items[indices[i]]
        if item then entry.kill.items[entry.listID] = item.id end
    end
    addon.Log:I("AutoStart", #indices, "boss drop(s) added",
        running and "to the open run" or "- starting a run")
    if not running then Session:Start() end

    for _, entry in ipairs(batch) do
        local drop = C_LootHistory.GetSortedInfoForDrop(entry.kill.id, entry.listID)
        if drop then Settle(entry.kill, entry.listID, drop) end
    end
end



local function Consider(kill, drop)
    local listID, link = drop.lootListID, drop.itemHyperlink
    if not listID or type(link) ~= "string" then return end
    local taken = kill.taken[listID]
    if taken then
        Settle(kill, listID, drop)
        return
    end
    if taken == false then return end

    local winner = drop.winner
    if drop.allPassed == true or (winner ~= nil and winner.isSelf ~= true) then
        kill.taken[listID] = false
        return
    end
    if not C_Item.IsItemDataCachedByID(link) then
        if kill.loading[listID] then return end
        kill.loading[listID] = true
        Item:CreateFromItemLink(link):ContinueOnItemLoad(function()
            kill.loading[listID] = nil
            if FindKill(kill.id) ~= kill then return end
            local fresh = C_LootHistory.GetSortedInfoForDrop(kill.id, listID)
            if fresh then Consider(kill, fresh) end
        end)
        return
    end
    taken = addon.Loot:Collects(link)
    kill.taken[listID] = taken
    if not taken then return end
    queued[#queued + 1] = { kill = kill, listID = listID, link = link }
    FlushSoon()
end

local function Scan(kill)
    local drops = C_LootHistory.GetSortedDropsForEncounter(kill.id)
    if type(drops) ~= "table" then return end
    for _, drop in ipairs(drops) do Consider(kill, drop) end
end



local function WarnMissingHost()
    if not IsInRaid() or not addon.Comms.InHomeGroup() then return end
    if addon.PlayerIsMasterLooter() or addon.Loot.handling ~= nil
        or addon.Config:HasShared() then
        return
    end
    local master = addon.GetMasterLooter()
    if not master or addon.Version:Knows(master) then return end
    if warnedFor and addon.Player:IsSame(warnedFor, master) then return end
    warnedFor = master
    local leader = addon.GetGroupLeader()
    addon.Chat.Warn(addon.Locale.Format(leader and addon.Player:IsSame(leader, master)
        and T["no loot session can start: the raid leader, %s, does not have Simple Loot Council."]
        or T["no loot session can start: the Loot Master, %s, does not have Simple Loot Council."],
        Ambiguate(master, "short")))
end

local function OnEncounterEnded(entry)
    if type(entry) ~= "table" or not entry.success or not entry.id then return end
    if not IsHost() then
        WarnMissingHost()
        return
    end
    if not Enabled() then return end
    local kill = FindKill(entry.id)
    if not kill then
        kill = { id = entry.id, name = entry.name, taken = {}, items = {}, loading = {} }
        kills[#kills + 1] = kill
        if #kills > MAX_KILLS then table.remove(kills, 1) end
        SyncEvents()
        addon.Log:I("AutoStart", "following the loot of", tostring(entry.name))
    end
    Scan(kill)
end

local function OnEvent(_, event, encounterID, lootListID)
    if event == "LOOT_HISTORY_CLEAR_HISTORY" then
        Forget("loot history cleared")
        return
    end
    local kill = FindKill(encounterID)
    if not kill then return end
    if event == "LOOT_HISTORY_UPDATE_DROP" and lootListID then
        local drop = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID)
        if drop then Consider(kill, drop) end
        return
    end
    Scan(kill)
end



function AutoStart:Refresh()
    if not Enabled() then Forget("automatic start turned off") end
end



function AutoStart:Init()
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", OnEvent)
    addon.Callbacks:Register("EncounterEnded", OnEncounterEnded)
    local function HostCheck()
        if not IsHost() then Forget("no longer running the loot") end
    end
    addon.Callbacks:Register("HandlingChanged", HostCheck)
    addon.Callbacks:Register("LootMasterChanged", HostCheck)
    addon.Callbacks:Register("RosterChanged", HostCheck)
    addon.Callbacks:Register("CouncilChanged", FlushSoon)
    addon.Restrictions:OnChange(function(isBlocked)
        if not isBlocked then FlushSoon() end
    end)
    addon.Log:I("AutoStart", "ready")
end
