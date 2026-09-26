if EUI_CLIENT_BLOCKED then return end
local _, module = ...
module.ThreatMeter = module.ThreatMeter or {}
local ns = module.ThreatMeter
ns.THREAT_DATA_REV = "essentials-merged-20260925"

local function Secret(v)
    return issecretvalue and issecretvalue(v) or false
end
ns.IsSecret = Secret

local function Number(value)
    if Secret(value) or type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

local function PublicCall(fn, ...)
    if not fn then return nil end
    local ok, value = pcall(fn, ...)
    if ok and not Secret(value) then return value end
end
ns.PublicCall, ns.PublicNumber = PublicCall, Number

-- Scaled threat is relative to this player's pull threshold, including the
-- API's melee/ranged rules. Never guess a fixed 110/130% distance multiplier.
function ns.PullEntry(me, entry)
    if not me or me.holdsAggro then return nil end
    local raw, scaled = Number(me.rawKey), Number(me.scaledKey)
    if not raw or not scaled or raw <= 0 or scaled <= 0 then return nil end
    local threshold = Number(raw * 100 / scaled)
    if not threshold then return nil end
    entry = entry or {}
    entry.pull, entry.name, entry.threat, entry.rawKey = true, "Pull Aggro", threshold, threshold
    entry.displayPercent, entry.percent, entry.scaledKey, entry.pullPercent = 100, 100, 100, true
    return entry
end

local function PetOwnerToken(unit)
    if unit == "pet" then return "player" end
    local party = unit:match("^partypet(%d+)$")
    if party then return "party" .. party end
    local raid = unit:match("^raidpet(%d+)$")
    if raid then return "raid" .. raid end
end

local function PlayerClass(unit)
    if not unit or PublicCall(UnitExists, unit) ~= true or not UnitClass then return nil end
    local ok, _, class = pcall(UnitClass, unit)
    if ok and not Secret(class) and type(class) == "string" then return class end
end

-- A pet's UnitClass often describes the creature, not its owner. Only use a
-- verified roster owner for class art/colors; unowned outsiders get pet art only.
function ns.UnitAppearance(unit, roster)
    local owner = PetOwnerToken(unit)
    if owner then return PlayerClass(owner), true end
    if unit == "player" or unit:match("^party%d+$") or unit:match("^raid%d+$")
        or PublicCall(UnitIsPlayer, unit) == true then return PlayerClass(unit), false end
    for _, token in ipairs(roster or ns.GroupTokens(true)) do
        owner = PetOwnerToken(token)
        if owner and PublicCall(UnitIsUnit, unit, token) == true then
            return PlayerClass(owner), true
        end
    end
    if PublicCall(UnitIsPlayer, unit) == false and PublicCall(UnitPlayerControlled, unit) == true then
        return nil, true
    end
    return nil, false
end

function ns.ResolveSource(source)
    if PublicCall(UnitExists, source) ~= true then return nil end
    if PublicCall(UnitCanAttack, "player", source) == true then return source end
    local nextTarget = source .. "target"
    if PublicCall(UnitCanAssist, "player", source) == true
        and PublicCall(UnitExists, nextTarget) == true
        and PublicCall(UnitCanAttack, "player", nextTarget) == true then return nextTarget end
end

local function CompareThreat(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        -- In mixed-data mode, units stay in comparable groups; unavailable
        -- values do not demote the tank or disable sorting for other players.
        if a.sortTier ~= b.sortTier then return a.sortTier > b.sortTier end
        if a.sortValue ~= b.sortValue then return a.sortValue > b.sortValue end
        return a.order < b.order
end

-- Collect display values separately from public ranking keys. Secret values
-- may reach UI setters, but never the comparator (including via truth tests).
function ns.ReadThreat(tokens, target, api, buffer)
    if buffer then
        buffer.rows, buffer.pool = buffer.rows or {}, buffer.pool or {}
    end
    local rows = buffer and buffer.rows or {}
    for i = #rows, 1, -1 do rows[i] = nil end
    local restricted, hasAggro = false, false
    local allRaw, allRelative, allScaled = true, true, true
    for _, token in ipairs(tokens) do
        local ok, tank, status, scaled, relative, raw = pcall(api, token, target)
        if not ok then tank, status, scaled, relative, raw = nil, nil, nil, nil, nil end
        local publicStatus = Number(status)
        if not publicStatus then publicStatus = Number(PublicCall(UnitThreatSituation, token, target)) end
        local victim = PublicCall(UnitIsUnit, token, target .. "target") == true
        local tanking = not Secret(tank) and tank == true
        local priority = victim and 3 or (tanking and 2 or (publicStatus and publicStatus >= 2 and 1 or 0))
        local hasPercent = type(scaled) == "number" or type(relative) == "number"
        local hasData = hasPercent or type(raw) == "number" or publicStatus ~= nil
        -- A missing API result is not zero threat. The enemy's observed victim
        -- is still meaningful, even before the owner/player joins the fight.
        if hasData or priority > 0 then
            local slot = #rows + 1
            local row = buffer and buffer.pool[slot] or {}
            if buffer then buffer.pool[slot] = row end
            -- Clear optional fields too: pooled rows may switch from a pet or
            -- scaled-only result to a different unit on the next update.
            for key in pairs(row) do row[key] = nil end
            row.unit, row.tank, row.status = token, tank, status
            row.percent, row.relative, row.threat = scaled, relative, raw
            row.order, row.priority, row.holdsAggro = slot, priority, priority > 0
            row.aggroOnly = not hasPercent and type(raw) ~= "number" and priority > 0
            row.rawKey, row.relativeKey, row.scaledKey = Number(raw), Number(relative), Number(scaled)
            if Secret(tank) or Secret(status) or Secret(scaled) or Secret(relative) or Secret(raw) then
                restricted = true
            end
            if row.holdsAggro then hasAggro = true end
            if not row.aggroOnly then
                allRaw = allRaw and row.rawKey ~= nil
                allRelative = allRelative and row.relativeKey ~= nil
                allScaled = allScaled and row.scaledKey ~= nil
            end
            -- Prefer percent of the aggro holder's threat. Scaled percent means
            -- progress toward pulling aggro instead, so the UI labels it separately.
            if row.holdsAggro then row.displayPercent = 100
            elseif type(relative) == "number" then row.displayPercent = relative
            elseif type(scaled) == "number" then row.displayPercent = scaled; row.pullPercent = true end
            rows[#rows + 1] = row
        end
    end
    if buffer then
        for i = #rows + 1, #buffer.pool do
            for key in pairs(buffer.pool[i]) do buffer.pool[i][key] = nil end
        end
    end
    local metric = allRaw and "rawKey" or (allRelative and "relativeKey" or (allScaled and "scaledKey" or nil))
    for _, row in ipairs(rows) do
        if metric then
            row.sortTier, row.sortValue = 1, row[metric] or 0
        elseif row.rawKey ~= nil then row.sortTier, row.sortValue = 3, row.rawKey
        elseif row.relativeKey ~= nil then row.sortTier, row.sortValue = 2, row.relativeKey
        elseif row.scaledKey ~= nil then row.sortTier, row.sortValue = 1, row.scaledKey
        else row.sortTier, row.sortValue = 0, 0 end
    end
    table.sort(rows, CompareThreat)
    -- If the API omitted both percentages, readable raw values still establish
    -- a tank-relative bar. Without a known tank baseline, leave it unknown.
    local baseline = rows[1] and rows[1].holdsAggro and rows[1].rawKey
    if baseline and baseline > 0 then
        for _, row in ipairs(rows) do
            if type(row.displayPercent) ~= "number" and row.rawKey and row.rawKey >= 0 then
                row.displayPercent = Number(row.rawKey / baseline * 100)
            end
        end
    end
    return rows, restricted, metric ~= nil, hasAggro
end

-- The group is not the entire threat roster. Discover outsiders through public
-- unit tokens; never retain a nameplate token after it has been reassigned.
local function AddCandidate(result, pets, token)
    if not token or PublicCall(UnitExists, token) ~= true then return end
    local player = PublicCall(UnitIsPlayer, token)
    if player == nil then return end
    if not player then
        if not pets or PublicCall(UnitPlayerControlled, token) ~= true then return end
    end
    for _, existing in ipairs(result) do
        if existing == token then return end
        local same = PublicCall(UnitIsUnit, existing, token)
        -- Unknown identity cannot safely establish a distinct participant.
        if same == nil or same then return end
    end
    result[#result + 1] = token
end

function ns.ThreatTokens(pets, target, buffer)
    local result = ns.GroupTokens(pets, buffer and buffer.tokens)
    AddCandidate(result, pets, target .. "target")
    AddCandidate(result, pets, "mouseover")
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local candidates = buffer and buffer.candidates or {}
        for i = #candidates, 1, -1 do candidates[i] = nil end
        for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
            local token = plate.namePlateUnitToken
            if type(token) == "string" and not Secret(token) then candidates[#candidates + 1] = token end
        end
        table.sort(candidates)
        for _, token in ipairs(candidates) do
            AddCandidate(result, pets, token)
            AddCandidate(result, pets, token .. "target")
        end
    end
    return result
end

local function AddGroupUnit(result, pets, token, pet)
    if UnitExists(token) then result[#result + 1] = token end
    if pets and UnitExists(pet) then result[#result + 1] = pet end
end
function ns.GroupTokens(pets, result)
    result = result or {}
    for i = #result, 1, -1 do result[i] = nil end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do AddGroupUnit(result, pets, "raid" .. i, "raidpet" .. i) end
    else
        AddGroupUnit(result, pets, "player", "pet")
        for i = 1, GetNumSubgroupMembers() do AddGroupUnit(result, pets, "party" .. i, "partypet" .. i) end
    end
    return result
end
