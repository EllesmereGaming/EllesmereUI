if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Announce = {}
addon.Announce = Announce






local function Channel()
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end






local queue = {}
local ticker
local SPACING = 0.7



local lastSent = 0

local function Pump()
    local message = table.remove(queue, 1)
    if not message then
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        return
    end

    local channel = Channel()

    if channel then
        C_ChatInfo.SendChatMessage(message, channel)
        lastSent = GetTime()
    end
end

local function Send(message)
    if not message or message == "" then return end
    if not Channel() then return end

    queue[#queue + 1] = message


    if not ticker and (GetTime() - lastSent) >= SPACING then
        Pump()
    end


    if #queue > 0 and not ticker then
        ticker = C_Timer.NewTicker(SPACING, Pump)
    end
end







local function Who(name)
    if not name then return T["someone"] end
    return Ambiguate(name, "short")
end

local function ResponseText(session, winner)
    local item = addon.Session:GetItem(session)
    local candidate = item and item.candidates and item.candidates[winner]
    if not candidate then return nil end
    if type(candidate.boe) == "table" then return candidate.boe.t end

    local index = candidate.realResponse or candidate.response
    local response = index and addon.Config:Responses()[index]
    if response then return response.text end

    local status = candidate.realStatus or candidate.status
    local known = status and addon.Session.STATUS[status]
    return known and known.text or nil
end





function Announce:Init()


    addon.Callbacks:Register("ItemAwarded", function(session, winner, item)
        if item and item.simulated then return end
        if not addon.db.announce or not addon.db.announce.awards then return end
        if not addon.PlayerIsMasterLooter() then return end
        if not item or not item.link then return end


        local why = item.reasonText or ResponseText(session, winner)
        if why then
            Send(addon.Locale.Format(T["%s awarded to %s (%s)"],
                item.link, Who(winner), why))
        else
            Send(addon.Locale.Format(T["%s awarded to %s"], item.link, Who(winner)))
        end
    end)


    addon.Callbacks:Register("ItemDelivered", function(session, winner, item)
        if not addon.db.announce or not addon.db.announce.trades then
            addon.Log:D("Announce", "trade not announced: disabled in settings")
            return
        end
        if not addon.PlayerIsMasterLooter() then
            addon.Log:D("Announce", "trade not announced: not the loot master")
            return
        end
        if not item or not item.link then
            addon.Log:WLogOnly("Announce", "trade not announced: no item for session",
                tostring(session))
            return
        end
        if not Channel() then
            addon.Log:D("Announce", "trade not announced: not in a group")
            return
        end

        addon.Log:I("Announce", "trade", item.link, "to", tostring(winner))
        Send(addon.Locale.Format(T["%s traded to %s"], item.link, Who(winner)))
    end)



    addon.Callbacks:Register("RollRequested", function(sessions, names)
        if not addon.db.announce or not addon.db.announce.rolls then return end
        if not addon.PlayerIsMasterLooter() then return end
        if names ~= nil then return end
        if not sessions or #sessions == 0 then return end


        local NAMED = 3



        local links = {}
        for _, session in ipairs(sessions) do
            local item = addon.Session:GetItem(session)
            if item and item.link and not item.simulated then
                links[#links + 1] = item.link
            end
        end
        if #links == 0 then return end

        if #links <= NAMED then
            for _, link in ipairs(links) do
                Send(addon.Locale.Format(T["%s - please roll (/roll)"], link))
            end
        else
            Send(addon.Locale.Format(addon.Locale.Plural{
                one = "The council has asked everyone to roll on %d item - /roll once per item.",
                other = "The council has asked everyone to roll on %d items - /roll once per item.",
            }, #links, #links))
        end
    end)

    addon.Log:I("Announce", "ready")
end
