if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local MasterLoot = {}
addon.MasterLoot = MasterLoot

local MAX_CANDIDATES = 40

local IsSecret = addon.IsSecret


function MasterLoot:IsActive()
    local game = addon.GetGameMasterLooter and addon.GetGameMasterLooter()
    return game ~= nil and addon.Player:IsSelf(game)
end



function MasterLoot.SourcesOf(slot)
    local sources = {}
    if type(GetLootSourceInfo) ~= "function" then return sources end
    local values = { pcall(GetLootSourceInfo, slot) }
    if not values[1] then return sources end
    for i = 2, #values, 2 do
        local guid = values[i]
        if type(guid) == "string" and guid ~= "" and not IsSecret(guid) then
            sources[#sources + 1] = guid
        end
    end
    return sources
end



function MasterLoot.SelfCandidate(slot)
    local listed = false
    for index = 1, MAX_CANDIDATES do
        local ok, name, second = pcall(GetMasterLootCandidate, slot, index)
        if ok and not IsSecret(name, second) and type(name) == "string" and name ~= "" then
            listed = true
            if addon.Player:IsSelf((addon.Player.UnitNameParts(name, second))) then
                return index, true
            end
        end
    end
    return nil, listed
end

local function IsBossUnit(unit, guid)
    local unitGUID = UnitGUID(unit)
    if not unitGUID or IsSecret(unitGUID) or unitGUID ~= guid then return false end
    local level, class = UnitLevel(unit), UnitClassification(unit)
    if IsSecret(level, class) then return false end
    return class == "worldboss" or level == -1
end



function MasterLoot.IsBossLoot(sources)
    local encounter = addon.Encounter
    for _, guid in ipairs(sources) do
        if encounter.BossForLootSource and encounter:BossForLootSource(guid) then return true end
        if IsBossUnit("target", guid) or IsBossUnit("mouseover", guid) then return true end
    end
    return false
end




function MasterLoot:AutoLoot()
    if not addon.db or not addon.db.masterAutoLoot or not MasterLoot:IsActive() then return end
    local count = GetNumLootItems() or 0
    if count == 0 then return end

    if not (addon.Loot and addon.Loot.handling) then
        addon.Log:D("MasterLoot", "SLC is not active for this group - left to the loot window")
        return
    end
    local sources = {}
    for slot = 1, count do
        for _, guid in ipairs(MasterLoot.SourcesOf(slot)) do sources[#sources + 1] = guid end
    end
    local boss = MasterLoot.IsBossLoot(sources)
    if not boss and not IsInRaid() then
        addon.Log:D("MasterLoot", "not a boss's corpse and not a raid - left to the loot window")
        return
    end
    local given, looted, refused = 0, 0, 0
    for slot = count, 1, -1 do
        local slotType = GetLootSlotType(slot)
        if slotType and slotType ~= Enum.LootSlotType.None then
            local index, listed = MasterLoot.SelfCandidate(slot)
            if index then
                if pcall(GiveMasterLoot, slot, index) then given = given + 1 end
            elseif listed then
                refused = refused + 1
            elseif boss and pcall(LootSlot, slot) then
                looted = looted + 1
            end
        end
    end
    if given == 0 and looted == 0 and refused == 0 then
        addon.Log:D("MasterLoot", "trash corpse with nothing at the threshold - left to the loot window")
        return
    end
    addon.Log:I("MasterLoot", "auto-looted", boss and "boss" or "trash", given, "master-looted and",
        looted, "other slot(s);", refused, "not offered to us")
    if refused > 0 then
        addon.Chat.Error(addon.Locale.Format(addon.Locale.Plural{
            one = "%d item on this corpse was left in the loot window - the game does not offer it to you.",
            other = "%d items on this corpse were left in the loot window - the game does not offer them to you.",
        }, refused, refused))
    end
end

function MasterLoot:Init()
    if not addon.IsForever then return end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("LOOT_OPENED")
    frame:SetScript("OnEvent", function()
        local ok, err = pcall(MasterLoot.AutoLoot, MasterLoot)
        if not ok then addon.Log:Bug("MasterLoot", tostring(err)) end
    end)
end
