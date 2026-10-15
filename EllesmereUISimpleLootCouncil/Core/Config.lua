if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Config = {}
addon.Config = Config


local shared = nil





Config.MAX_TEXT = 100
Config.MAX_RESPONSES = 7

local MAX_NOTE = 255
local MAX_WHISPER = 255


function Config.CleanText(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" or #value > Config.MAX_TEXT then return nil end
    return value
end


function Config.CleanChannel(value)
    value = tonumber(value)
    if not value or value ~= value then return nil end
    return math.max(0, math.min(1, value))
end







local malformedLogged, malformedCount = {}, 0
local function Malformed(field, sender)
    local key = field .. "|" .. tostring(sender)
    if malformedLogged[key] then return end
    if malformedCount >= 64 then malformedLogged, malformedCount = {}, 0 end
    malformedLogged[key], malformedCount = true, malformedCount + 1
    addon.Log:WLogOnly("Config", "malformed shared field kept at its last value", field,
        "from", sender)
end


local function SharedChannel(value)
    if value == nil then return 0.8 end
    return Config.CleanChannel(value)
end



local function SharedResponses(list)
    if type(list) ~= "table" then return nil end
    local responses = {}
    for index, entry in ipairs(list) do
        if index > Config.MAX_RESPONSES then break end
        if type(entry) ~= "table" then return nil end
        local text = entry.t == nil and addon.Locale.Format(T["Response %d"], index)
            or Config.CleanText(entry.t)
        local r, g, b = SharedChannel(entry.r), SharedChannel(entry.g), SharedChannel(entry.b)
        local sort = entry.s == nil and index or tonumber(entry.s)
        local whisper = entry.w
        if not text or not r or not g or not b or not sort or sort ~= sort
            or whisper ~= nil and (type(whisper) ~= "string" or #whisper > MAX_WHISPER) then
            return nil
        end
        responses[index] = {
            id = "SHARED" .. index, text = text, r = r, g = g, b = b, sort = sort,

            whisper = whisper,
        }
    end

    return #responses > 0 and responses or nil
end


local VOTE_KEYS = { selfVote = true, multiVote = true, hideVotes = true }


function Config:ApplyShared(config, sender)
    if type(config) ~= "table" then return end

    local next_ = {}
    for key, value in pairs(shared or {}) do next_[key] = value end

    if config.responses ~= nil then
        local responses = SharedResponses(config.responses)
        if responses then next_.responses = responses else Malformed("responses", sender) end
    end

    if config.vote ~= nil then
        if type(config.vote) == "table" then

            local vote = {}
            for key, value in pairs((addon.db and addon.db.vote) or {}) do
                vote[key] = value
            end
            for key, value in pairs(next_.vote or {}) do vote[key] = value end
            for key in pairs(VOTE_KEYS) do
                local value = config.vote[key]
                if type(value) == "boolean" then
                    vote[key] = value
                elseif value ~= nil then
                    Malformed("vote." .. key, sender)
                end
            end
            next_.vote = vote
        else
            Malformed("vote", sender)
        end
    end

    if config.noteMax ~= nil then
        local noteMax = config.noteMax
        if type(noteMax) == "number" and noteMax == math.floor(noteMax)
            and noteMax >= 1 and noteMax <= MAX_NOTE then
            next_.noteMax = noteMax
        else
            Malformed("noteMax", sender)
        end
    end

    for _, field in ipairs({ "startRequests", "councilMayStartRuns", "councilBags" }) do
        local value = config[field]
        if type(value) == "boolean" then
            next_[field] = value
        elseif value ~= nil then
            Malformed(field, sender)
        end
    end


    if config.lootMaster ~= nil then
        if config.lootMaster == false then
            next_.lootMaster = nil
        elseif type(config.lootMaster) == "string" and #config.lootMaster <= Config.MAX_TEXT then
            local record = addon.Player:Get(config.lootMaster)
            next_.lootMaster = record.guid or nil
        else
            Malformed("lootMaster", sender)
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
