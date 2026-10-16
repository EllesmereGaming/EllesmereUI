if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text
local Request = {}
addon.StartRequest = Request
local pending



local DECLINE_TEXT = addon.Locale.Texts{
    lm_changed  = T["Start request declined: the Loot Master changed."],
    permission  = T["Start request declined: the start permission changed."],
    declined    = T["The Loot Master declined your start request."],
    not_started = T["Start request declined: the queue is empty or the council is not present."],
    disabled    = T["Start request declined: the Loot Master has not enabled start requests."],
    not_council = T["Start request declined: you are not on the council."],
    running     = T["Start request declined: a run is already in progress."],
    busy        = T["Start request declined: another start request is awaiting approval."],
    empty       = T["Start request declined: the queue is empty."],
    no_council  = T["Start request declined: the council is not present."],
    expired     = T["Start request declined: the approval request expired. Please request again."],
    cleared     = T["Start request declined: the queue was cleared."],
}



function Request.DeclineText(why)
    if why == nil then return T["Start request declined. No reason was given."] end
    return DECLINE_TEXT[why]
        or addon.Locale.Format(T["Start request declined (%s)."], tostring(why))
end

local function Reply(who, ok, why)
    addon.Comms:Send("start_ack", { ok = ok, why = why }, who)
end



local function StartRefusal()
    if addon.Session:IsRunning() then return "running" end
    if not addon.PlayerIsMasterLooter() then return "lm_changed" end
    if #addon.Session:GetItems() == 0 then return "empty" end
    if addon.Council:GetCount() == 0 then return "no_council" end
    return "not_started"
end



local PROPOSAL_MAX = 32
local MAX_LINK_LENGTH = 512


local function Sanitise(proposed, who)
    local items = {}
    if type(proposed) ~= "table" then return items end
    if #proposed > PROPOSAL_MAX then
        addon.Log:D("StartRequest", "proposal from", tostring(who), "cut from", #proposed, "to", PROPOSAL_MAX)
    end
    for index, entry in ipairs(proposed) do
        if index > PROPOSAL_MAX then break end
        if type(entry) == "table" and type(entry.l) == "string"
            and #entry.l <= MAX_LINK_LENGTH and entry.l:find("|Hitem:", 1, true) then
            items[#items + 1] = {
                link = entry.l,
                owner = type(entry.o) == "string" and entry.o or who,
                boss = type(entry.b) == "string" and entry.b or nil,


                encounterID = tonumber(entry.e),
            }
        end
    end
    return items
end


local function Merge(items)
    local seen = {}
    local added = 0
    for _, entry in ipairs(items) do
        local id = addon.Storage.ItemID(entry.link)
        local key = id and (id .. "|" .. tostring(entry.owner)) or entry.link
        seen[key] = (seen[key] or 0) + 1
        if addon.Session:CountQueued(entry.link, entry.owner) < seen[key] then
            addon.Session:AddItem(entry.link, entry.owner, entry.boss, entry.encounterID)
            added = added + 1
        end
    end
    return added
end

function Request:GetPending()
    return pending
end

local function Close(ok, why)
    local old = pending
    if not old then return end
    pending = nil
    addon.Callbacks:Fire("StartRequestChanged")
    Reply(old.who, ok, why)
end



function Request:Refresh()
    if not pending then return end
    if not addon.PlayerIsMasterLooter() then Close(false, "lm_changed") return end
    if addon.Session:IsRunning() then Close(true) return end
    if not addon.Config:StartRequestsAllowed() or not addon.Council:Contains(pending.who) then
        Close(false, "permission")
        return
    end
end

function Request:Resolve(expected, accept)
    if not pending or pending ~= expected then return false end
    Request:Refresh()
    if pending ~= expected then return false end

    if not accept then

        Close(false, "declined")
        return true
    end

    Merge(expected.items)
    local started = addon.Session:Start()
    if pending == expected then
        Close(started, not started and StartRefusal() or nil)
    end
    return started
end

function Request:Request(sender, proposed)
    if not addon.PlayerIsMasterLooter() then return end
    local who = addon.Player:Get(sender).fullName or sender
    if not addon.Config:StartRequestsAllowed() then
        Reply(who, false, "disabled")
        return
    end
    if not addon.Council:Contains(who) then Reply(who, false, "not_council") return end
    if addon.Session:IsRunning() then Reply(who, false, "running") return end
    if pending then

        if not addon.Player:IsSame(pending.who, who) then
            Reply(who, false, "busy")
        end
        return
    end

    local items = Sanitise(proposed, who)
    if #items == 0 and #addon.Session:GetItems() == 0 then
        Reply(who, false, "empty")
        return
    end

    if addon.Config:CouncilMayStartRuns() then
        Merge(items)
        local started = addon.Session:Start()
        Reply(who, started, not started and StartRefusal() or nil)
        return
    end

    pending = { who = who, items = items }
    local current = pending
    addon.Callbacks:Fire("StartRequestChanged")
    C_Timer.After(120, function()
        if pending == current then Close(false, "expired") end
    end)
end


Request.Merge = Merge
Request.Sanitise = Sanitise

function Request:Init()
    addon.Callbacks:Register("SessionChanged", function() Request:Refresh() end)
    addon.Callbacks:Register("CouncilChanged", function() Request:Refresh() end)
    addon.Callbacks:Register("RunStarted", function() Request:Refresh() end)
    addon.Callbacks:Register("RunEnded", function() Close(false, "cleared") end)
end
