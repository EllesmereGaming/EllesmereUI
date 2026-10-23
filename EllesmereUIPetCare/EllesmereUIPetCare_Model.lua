if EUI_CLIENT_BLOCKED then return end
local _, ns = ...
local M = {}
ns.Model = M

function M.IsItemID(id)
    return type(id) == "number" and id >= 1 and id <= 2147483647 and id == math.floor(id)
end

function M.ParseIDs(text)
    local list, seen = {}, {}
    for word in (text or ""):gmatch("[^,%s]+") do
        local id = tonumber(word)
        if not M.IsItemID(id) then return nil end
        if not seen[id] then list[#list + 1] = id; seen[id] = true end
    end
    return list
end

function M.Diet(foodNames, dietNames)
    local allowed = {}
    for _, name in ipairs(dietNames or {}) do
        for kind, translated in ipairs(foodNames) do
            if name == translated then allowed[kind] = true end
        end
    end
    return allowed
end

function M.Candidates(stacks, cfg, diet, petLevel, database)
    local byID, list, priority = {}, {}, {}
    for rank, id in ipairs(cfg.preferred or {}) do priority[id] = rank end
    for _, stack in ipairs(stacks) do
        local id = stack.id
        local custom = cfg.customFoods and cfg.customFoods[id]
        local data = custom or database[id]
        local excluded = cfg.blacklist and cfg.blacklist[id]
        if data and not excluded and not stack.locked and not stack.quest
            and stack.count > 0 and diet[data[1]] and data[2] >= petLevel - 30
            and (not cfg.preferredOnly or priority[id]) then
            local source = data[3] or 2
            local permitted = custom or priority[id] or source == 1
                or (source == 2 and cfg.cooked) or (source == 3 and cfg.rawMeat)
                or (source == 4 and cfg.rawFish)
            if permitted then
                local entry = byID[id]
                if entry then
                    entry.count = entry.count + stack.count
                else
                    entry = { id = id, count = stack.count, level = data[2], diet = data[1],
                        bag = stack.bag, slot = stack.slot, priority = priority[id] or math.huge }
                    byID[id] = entry
                    list[#list + 1] = entry
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        if cfg.order == "level" and a.level ~= b.level then return a.level > b.level end
        if a.count ~= b.count then
            if cfg.order == "least" then return a.count < b.count end
            return a.count > b.count
        end
        if a.level ~= b.level then return a.level > b.level end
        return a.id < b.id
    end)
    return list
end

function M.Select(list, selectedID, advance)
    if #list == 0 then return nil end
    for index, entry in ipairs(list) do
        if entry.id == selectedID then
            return advance and list[index % #list + 1] or entry
        end
    end
    return list[1]
end
