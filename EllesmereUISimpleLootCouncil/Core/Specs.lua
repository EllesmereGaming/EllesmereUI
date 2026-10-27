if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end






SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local Specs = {}
addon.Specs = Specs



local cache = {}



local CACHE_TTL = 30 * 24 * 60 * 60
local MAX_RECORDS = 300

local TRIM_SLACK = 50
local count = 0





local IsSecret = addon.IsSecret



local infoCache = {}

local MAX_SPEC_ID = 100000

local function ValidSpec(specID)
    return type(specID) == "number" and not IsSecret(specID) and specID == specID
        and specID > 0 and specID < MAX_SPEC_ID and math.floor(specID) == specID
end
Specs.Valid = ValidSpec

function Specs:Info(specID)
    if not ValidSpec(specID) then return nil end

    local cached = infoCache[specID]
    if cached ~= nil then
        return cached or nil
    end

    if not GetSpecializationInfoByID then
        infoCache[specID] = false
        return nil
    end

    local id, name, _, icon, role, classFile = GetSpecializationInfoByID(specID)
    if not id or IsSecret(name) then
        infoCache[specID] = false
        return nil
    end

    local info = { id = id, name = name, icon = icon, role = role, classFile = classFile }
    infoCache[specID] = info
    return info
end





local function Normalise(guid)
    if type(guid) ~= "string" or IsSecret(guid) then return nil end
    if guid:match("^Player%-") then return guid end
    if guid:match("^%d+%-%x+$") then return "Player-" .. guid end
    return nil
end

function Specs:Get(guid)
    local key = Normalise(guid)
    if not key then return nil end
    local record = cache[key]
    local spec = record and record.spec
    return ValidSpec(spec) and spec or nil
end



function Specs:Set(guid, specID, via)
    local key = Normalise(guid)
    if not key then return false end
    if not ValidSpec(specID) then return false end

    local record = cache[key]
    if record and record.spec == specID then


        record.at = time()
        return false
    end

    if not record then count = count + 1 end
    cache[key] = { spec = specID, at = time(), via = via }
    if count > MAX_RECORDS + TRIM_SLACK then Specs:Prune() end
    addon.Log:D("Specs", "learned", specID, "for", key, "via", tostring(via))
    addon.Callbacks:Fire("SpecsChanged")
    return true
end

function Specs:Count()
    local n = 0
    for _ in pairs(cache) do n = n + 1 end
    return n
end





local function OwnSpec()

    if addon.IsForever then return nil end
    local index = C_SpecializationInfo.GetSpecialization()
    if IsSecret(index) or not index then return nil end
    local id = C_SpecializationInfo.GetSpecializationInfo(index)
    if IsSecret(id) or not id then return nil end
    return id
end

function Specs:OwnSpec() return OwnSpec() end

local function LearnSelf()
    local id = OwnSpec()
    if not id then return nil end
    Specs:Set(UnitGUID("player"), id, "self")
    return id
end










function Specs:Prune()
    local now, removed, kept = time(), 0, {}
    local own = UnitGUID and UnitGUID("player")
    for guid, record in pairs(cache) do
        if type(record) ~= "table" or not ValidSpec(record.spec)
            or (now - (record.at or 0)) > CACHE_TTL then
            cache[guid] = nil
            removed = removed + 1
        elseif guid ~= own then
            kept[#kept + 1] = guid
        end
    end
    if #kept > MAX_RECORDS then
        table.sort(kept, function(a, b) return (cache[a].at or 0) > (cache[b].at or 0) end)
        for i = MAX_RECORDS + 1, #kept do
            cache[kept[i]] = nil
            removed = removed + 1
        end
    end
    count = 0
    for _ in pairs(cache) do count = count + 1 end
    return removed
end





function Specs:Init(db)
    db.specs = db.specs or {}
    cache = db.specs

    local pruned = Specs:Prune()

    if addon.IsForever then return end
    LearnSelf()


    addon.Comms:Register("spec", "any", function(args, sender)
        if not args or type(args.s) ~= "number" then return end
        local record = addon.Player:Get(sender)
        if record and record.guid then
            Specs:Set(record.guid, args.s, "comms")
        end
    end)

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    f:RegisterEvent("INSPECT_READY")
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_SPECIALIZATION_CHANGED" then


            if arg1 and arg1 ~= "player" then return end
            if LearnSelf() and addon.Version then
                addon.Version:RequestAnnounce(0.1)
            end

        elseif event == "INSPECT_READY" then
            local guid = arg1
            if not guid or IsSecret(guid) then return end



            local unit = addon.Roster and addon.Roster:UnitForGUID(guid)
            if unit then
                local id = C_SpecializationInfo.GetInspectSpecialization(unit)

                if not IsSecret(id) and id and id > 0 then
                    Specs:Set(guid, id, "inspect")
                end
            end



        end
    end)

    addon.Log:I("Specs", "ready", Specs:Count(), "known, pruned", pruned)
end
