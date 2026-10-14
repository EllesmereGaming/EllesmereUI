if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Config = {}
addon.Config = Config


local shared = nil






function Config:ApplyShared(config, sender)
    if type(config) ~= "table" then return end

    local next_ = {}
    for key, value in pairs(shared or {}) do next_[key] = value end

    if type(config.responses) == "table" then
        local responses = {}
        for index, entry in ipairs(config.responses) do
            responses[index] = {
                id = "SHARED" .. index,
                text = entry.t or addon.Locale.Format(T["Response %d"], index),
                r = entry.r or 0.8, g = entry.g or 0.8, b = entry.b or 0.8,
                sort = entry.s or index,

                whisper = entry.w,
            }
        end

        if #responses > 0 then next_.responses = responses end
    end

    if type(config.vote) == "table" then

        local vote = {}
        for key, value in pairs((addon.db and addon.db.vote) or {}) do
            vote[key] = value
        end
        for key, value in pairs(next_.vote or {}) do vote[key] = value end
        for key, value in pairs(config.vote) do vote[key] = value end
        next_.vote = vote
    end

    if config.noteMax then next_.noteMax = config.noteMax end

    if config.startRequests ~= nil then
        next_.startRequests = config.startRequests and true or false
    end

    if config.councilMayStartRuns ~= nil then
        next_.councilMayStartRuns = config.councilMayStartRuns == true
    end

    if config.councilBags ~= nil then
        next_.councilBags = config.councilBags == true
    end


    if config.lootMaster ~= nil then
        if config.lootMaster == false then
            next_.lootMaster = nil
        else
            local record = addon.Player:Get(config.lootMaster)
            next_.lootMaster = record.guid or nil
        end
    end

    local previousLM = shared and shared.lootMaster or nil
    shared = next_

    if previousLM ~= next_.lootMaster then
        addon.InvalidateMasterLooter()
        addon.Log:I("Config", "loot master is now",
            tostring(addon.GetMasterLooter()))
    end

    addon.Log:I("Config", "shared contract from", tostring(sender), "-",
        #(next_.responses or (addon.db and addon.db.responses) or {}), "responses")

    if addon.Callbacks then addon.Callbacks:Fire("SharedConfigChanged") end
end


function Config:ClearShared(why)
    if not shared then return end
    local hadDelegate = shared.lootMaster ~= nil
    shared = nil
    addon.Log:I("Config", "shared contract dropped -", tostring(why))
    if hadDelegate then addon.InvalidateMasterLooter() end
    if addon.Callbacks then addon.Callbacks:Fire("SharedConfigChanged") end
end

function Config:HasShared()
    return shared ~= nil
end






function Config:Responses()
    return (shared and shared.responses) or (addon.db and addon.db.responses) or {}
end

function Config:Vote()
    return (shared and shared.vote) or (addon.db and addon.db.vote) or {}
end

function Config:NoteMax()
    return (shared and shared.noteMax) or (addon.db and addon.db.noteMaxLength) or 64
end

function Config:StartRequestsAllowed()
    if shared and shared.startRequests ~= nil then return shared.startRequests end
    return (addon.db and addon.db.allowStartRequests) and true or false
end

function Config:CouncilMayStartRuns()
    if not self:StartRequestsAllowed() then return false end

    if shared then return shared.councilMayStartRuns == true end
    return addon.db and addon.db.councilMayStartRuns == true or false
end


function Config:CouncilBagsShared()

    if shared then return shared.councilBags == true end
    return addon.db and addon.db.shareCouncilBags == true or false
end






local function OwnsDelegation()
    if addon.CanAssignMasterLooter then return addon.CanAssignMasterLooter() end
    return true
end

function Config:LootMaster()
    if shared then return shared.lootMaster end
    if not OwnsDelegation() then return nil end
    return (addon.db and addon.db.lootMaster) or nil
end




function Config:RulesSettled()
    return shared ~= nil or OwnsDelegation()
end



function Config:LeaderDictates()
    if OwnsDelegation() then return false end
    return addon.Loot and addon.Loot.handling and true or false
end
