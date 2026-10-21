if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Restrictions = {}
addon.Restrictions = Restrictions


local active = 0


local BLOCKING = {
    [Enum.AddOnRestrictionType.Encounter] = true,
    [Enum.AddOnRestrictionType.ChallengeMode] = true,
    [Enum.AddOnRestrictionType.Chat] = true,
}



local queue = {}



local MAX_QUEUE = 500

local listeners = {}





function Restrictions:IsBlocked()
    for restrictionType in pairs(BLOCKING) do
        if bit.band(active, bit.lshift(1, restrictionType)) ~= 0 then
            return true
        end
    end
    return false
end


function Restrictions:GetBlockReason()
    if bit.band(active, bit.lshift(1, Enum.AddOnRestrictionType.Encounter)) ~= 0 then
        return T["not possible during a boss encounter"]
    end
    if bit.band(active, bit.lshift(1, Enum.AddOnRestrictionType.ChallengeMode)) ~= 0 then
        return T["not possible inside a mythic keystone run"]
    end
    if bit.band(active, bit.lshift(1, Enum.AddOnRestrictionType.Chat)) ~= 0 then
        return T["not possible while addon messages are restricted"]
    end
    return nil
end

function Restrictions:OnChange(callback)
    listeners[#listeners + 1] = callback
end









function Restrictions:Enqueue(entry)
    queue[#queue + 1] = entry

    if #queue > MAX_QUEUE then
        local excess = #queue - MAX_QUEUE
        for _ = 1, excess do table.remove(queue, 1) end
        addon.Log:E("Restrictions", "deferred queue overflowed - dropped", excess,
            "of the oldest sends; peers may be missing state")
    end

    addon.Log:D("Restrictions", "queued while blocked", entry.command, "depth", #queue)
end

function Restrictions:GetQueueDepth()
    return #queue
end

local function Flush()
    if #queue == 0 then return end

    local pending = queue
    queue = {}

    addon.Log:I("Restrictions", "flushing", #pending, "deferred sends")

    for _, entry in ipairs(pending) do

        addon.Comms:Send(entry.command, entry.args, entry.target, entry.guaranteed)
    end
end


Restrictions.Flush = function(_) Flush() end





function Restrictions:Init()


    for _, restrictionType in pairs(Enum.AddOnRestrictionType) do
        if C_RestrictedActions.IsAddOnRestrictionActive(restrictionType) then
            active = bit.bor(active, bit.lshift(1, restrictionType))
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    f:SetScript("OnEvent", function(_, _, restrictionType, state)
        local wasBlocked = Restrictions:IsBlocked()


        local nowOn = (state == Enum.AddOnRestrictionState.Active
            or state == Enum.AddOnRestrictionState.Activating)

        if nowOn then
            active = bit.bor(active, bit.lshift(1, restrictionType))
        else
            active = bit.band(active, bit.bnot(bit.lshift(1, restrictionType)))
        end

        local isBlocked = Restrictions:IsBlocked()


        if BLOCKING[restrictionType] or wasBlocked ~= isBlocked then
            addon.Log:D("Restrictions", "state change", restrictionType, state,
                "blocked", isBlocked)
        end

        if wasBlocked ~= isBlocked then
            for _, callback in ipairs(listeners) do
                local ok, err = pcall(callback, isBlocked)
                if not ok then addon.Log:Bug("Restrictions", tostring(err)) end
            end
            if not isBlocked then

                C_Timer.After(0.5, Flush)
            end
        end
    end)

    addon.Log:I("Restrictions", "ready", "blocked", Restrictions:IsBlocked())
end
