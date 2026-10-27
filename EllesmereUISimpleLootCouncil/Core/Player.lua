if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end





SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Player = {}
addon.Player = Player



local cache = {}
local ownRealm
local realmNames
local byName, byBare, missedNames = {}, {}, {}



local CACHE_TTL = 2 * 24 * 60 * 60



local RECORD_SHAPE = 2



local SEED_RETRY = 30





local IsSecret = addon.IsSecret



if addon.EDITION == "eui" and EllesmereUI then
    Player.IS_FOREVER = EllesmereUI.IS_FOREVER == true
else
    local interface = GetBuildInfo and select(4, GetBuildInfo())
    Player.IS_FOREVER = type(interface) == "number" and interface < 20000
end
addon.IsForever = Player.IS_FOREVER



local function UnitNameParts(name, second)
    if Player.IS_FOREVER and type(name) == "string" and type(second) == "string"
        and second ~= "" and not name:find(" ", 1, true)
        and not second:find(" ", 1, true) then
        return name .. " " .. second, nil
    end
    return name, second
end
Player.UnitNameParts = UnitNameParts



local UNIT_BASES = {
    player = true, target = true, focus = true, pet = true, mouseover = true, vehicle = true,
    npc = true, none = true, questnpc = true, softenemy = true, softfriend = true,
    softinteract = true, anyenemy = true, anyfriend = true, anyinteract = true,
}
local tokenMemo = { n = 0, of = {} }

local function IsUnitToken(short)
    if type(short) ~= "string" or short == "" or IsSecret(short) then return false end
    local known = tokenMemo.of[short]
    if known ~= nil then return known end
    local token = false
    if not short:find("[^A-Za-z0-9]") then
        local base = short:lower()
        if base:find("[0-9]") then
            token = true
        else
            while base ~= "" do
                if UNIT_BASES[base] then token = true break end
                local cut = base:match("^(.+)target$") or base:match("^(.+)pet$")
                if not cut then break end
                base = cut
            end
        end
    end
    if tokenMemo.n >= 512 then tokenMemo.of, tokenMemo.n = {}, 0 end
    tokenMemo.of[short] = token
    tokenMemo.n = tokenMemo.n + 1
    return token
end
Player.IsUnitToken = IsUnitToken

local function GroupUnitNamed(short)
    if type(short) ~= "string" or short == "" or IsSecret(short) then return nil end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name = GetRaidRosterInfo(i)
            if name and not IsSecret(name) and name == short then return "raid" .. i end
        end
        return nil
    end
    local count = IsInGroup() and GetNumGroupMembers() or 1
    for i = 0, count - 1 do
        local unit = i == 0 and "player" or ("party" .. i)
        local name, realm = UnitName(unit)
        if name and not IsSecret(name, realm) and UnitIsPlayer(unit) then
            local joined = Player.IS_FOREVER and (UnitNameParts(name, realm)) or nil
            if name == short and (realm == nil or realm == "") or joined == short then
                return unit
            end
        end
    end
    return nil
end
Player.GroupUnitNamed = GroupUnitNamed

local function NamedUnit(short)
    if type(short) ~= "string" or short == "" then return nil end
    if IsUnitToken(short) then return GroupUnitNamed(short) end
    if UnitExists(short) then return short end
    return nil
end



local function LooksLikeGUID(s)
    return type(s) == "string"
        and (s:match("^Player%-%d+%-%x+$") ~= nil or s:match("^%d+%-%x+$") ~= nil)
end

local function NormaliseGUID(s)
    if s:match("^Player%-") then return s end
    return "Player-" .. s
end


local function Qualify(name, realm)
    if not name or name == "" then return nil end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name .. "-" .. (ownRealm or "")
end





local function RealmKey(realm)
    if type(realm) ~= "string" or realm == "" or IsSecret(realm) then return nil end
    local key = addon.Locale.Fold(realm):gsub("\226\128\153", ""):gsub("[%s%p]", "")
    return key ~= "" and key or nil
end

local function RealmDisplay(realm)
    realm = realm:gsub("^%s*(.-)%s*$", "%1")
    realm = realm:gsub("(%a)(%d)", "%1-%2")
    return (realm:gsub("%s+(%d)", "-%1"))
end

local function AddRealmName(names, realm)
    local key = RealmKey(realm)
    if key and not names[key] then names[key] = RealmDisplay(realm) end
end

local function CanonicalRealm(realm)
    local key = RealmKey(realm)
    if not key then return nil end

    if not realmNames then
        realmNames = {}
        if GetRealmName then AddRealmName(realmNames, GetRealmName()) end
        if C_AutoComplete and C_AutoComplete.GetAutoCompleteRealms then
            local realms = C_AutoComplete.GetAutoCompleteRealms()
            for index = 1, #realms do AddRealmName(realmNames, realms[index]) end
        end
        AddRealmName(realmNames, ownRealm)
    end

    return realmNames[key] or RealmDisplay(realm)
end



local function CharacterDisplay(name)
    name = name:gsub("^%s*(.-)%s*$", "%1"):gsub("%s+", " ")
    return (name:gsub("[^ ]+", function(word)
        local first, rest = word:match("^([%z\1-\127\194-\244][\128-\191]*)(.*)$")
        if not first then return addon.Locale.Lower(word) end
        return addon.Locale.Upper(first) .. addon.Locale.Lower(rest)
    end))
end



local function NameKey(input)
    if type(input) ~= "string" or input == "" or IsSecret(input) then return nil end


    local name, realm = input:match("^%s*([^%-]-)%s*%-%s*(.-)%s*$")

    if Player.IS_FOREVER then

        if LooksLikeGUID(input) then return nil end
        name = name or input:match("^%s*(.-)%s*$")
        if name == "" then return nil end
        return addon.Locale.Fold((name:gsub("%s+", " ")))
    end

    if not name or name == "" or realm == "" or name:find("%s") then return nil end

    local compactRealm = RealmKey(realm)
    if not compactRealm then return nil end

    return addon.Locale.Fold((name:gsub("%s+", " "))) .. "-" .. compactRealm
end

local function IndexRecord(record)
    if not record or not record.guid then return end
    local key = NameKey(record.fullName)
    if key then byName[key] = record.guid end
    if record.name and not IsSecret(record.name) then
        byBare[addon.Locale.Fold(record.name)] = record.guid
    end
end



local function CompactQualifiedName(input)
    if type(input) ~= "string" or input == "" or IsSecret(input) then return nil end
    local name, realm = input:match("^([^-]+)-(.+)$")
    if not name or not realm then return nil end
    realm = realm:gsub("[%s%-]", "")
    if realm == "" then return nil end
    return name .. "-" .. realm
end







local function NilPlayer(hint)
    return {
        guid = nil,
        name = hint or "?",
        fullName = hint or "?",
        unresolved = true,
        nobody = hint == nil or nil,
    }
end

local function BuildRecord(guid)


    local localizedClass, classFile, _, _, _, name, realm = GetPlayerInfoByGUID(guid)

    if IsSecret(name, realm, classFile) then
        addon.Log:WLogOnly("Player", "secret identity for guid", guid)

        return nil
    end
    name, realm = UnitNameParts(name, realm)

    if not name or name == "" then
        return nil
    end

    return {
        guid = guid,
        name = name,
        realm = (realm ~= "" and realm) or ownRealm,
        fullName = Qualify(name, realm),
        class = localizedClass,
        classFile = classFile,
        cachedAt = time(),
        shape = RECORD_SHAPE,
    }
end







function Player:Get(input)
    if input == nil then return NilPlayer() end



    if IsSecret(input) then
        addon.Log:WLogOnly("Player", "Get called with a secret value")
        return NilPlayer()
    end


    if type(input) == "table" then
        if input.guid or input.unresolved then return input end
        return NilPlayer()
    end

    if type(input) ~= "string" or input == "" then
        return NilPlayer()
    end


    if LooksLikeGUID(input) then
        local guid = NormaliseGUID(input)
        local cached = cache[guid]
        if cached and cached.shape == RECORD_SHAPE
            and (time() - (cached.cachedAt or 0) < CACHE_TTL or cached.isCouncil)
            and not (cached.seeded and time() - cached.seeded >= SEED_RETRY) then
            return cached
        end
        if cached and cached.seeded then cached.seeded = time() end
        local record = BuildRecord(guid)
        if record then
            if cached then cached.seeded = nil end


            if cached then
                local oldKey = NameKey(cached.fullName)
                if oldKey and oldKey ~= NameKey(record.fullName) then byName[oldKey] = nil end
                local oldBare = cached.name and addon.Locale.Fold(cached.name)
                if oldBare and oldBare ~= addon.Locale.Fold(record.name) then
                    byBare[oldBare] = nil
                end
                for k, v in pairs(record) do cached[k] = v end
                IndexRecord(cached)
                return cached
            end
            cache[guid] = record
            IndexRecord(record)
            return record
        end
        return cached or NilPlayer(guid)
    end


    local short = Player.IS_FOREVER and self:WhisperTarget(input) or Ambiguate(input, "none")
    local unit = NamedUnit(short)
    if unit then
        local guid = UnitGUID(unit)
        if guid and not IsSecret(guid) then
            return self:Get(guid)
        end
    end


    local Fold = addon.Locale.Fold
    local wanted = Fold(input)
    local wantedKey = NameKey(input)
    local guid = wantedKey and byName[wantedKey] or byBare[wanted]
    if guid and cache[guid] then return cache[guid] end


    local missKey = wantedKey or wanted
    if not missedNames[missKey] then
        missedNames[missKey] = true
        addon.Log:D("Player", "could not resolve", input)
    end
    return NilPlayer(input)
end



function Player:Peek(input)
    if type(input) ~= "string" or input == "" or IsSecret(input) then return nil end
    if LooksLikeGUID(input) then return cache[NormaliseGUID(input)] end

    local short = Player.IS_FOREVER and self:WhisperTarget(input) or Ambiguate(input, "none")
    local unit = NamedUnit(short)
    if unit then
        local guid = UnitGUID(unit)
        if guid and not IsSecret(guid) then
            local record = self:Get(guid)
            if record.guid then return record end
        end
    end

    local wantedKey = NameKey(input)
    local guid = wantedKey and byName[wantedKey] or byBare[addon.Locale.Fold(input)]
    return guid and cache[guid] or nil
end



function Player:Remember(guid, fullName, classFile, className)
    if type(guid) ~= "string" or type(fullName) ~= "string" or IsSecret(guid, fullName)
        or not LooksLikeGUID(guid) then
        return nil
    end
    local known = self:Get(guid)
    if known.guid then return known end

    local name, realm = fullName:match("^([^-]+)-(.+)$")
    local record = {
        guid = NormaliseGUID(guid),
        name = name or fullName,
        realm = realm or ownRealm,
        fullName = Qualify(name or fullName, realm),
        class = className,
        classFile = classFile,
        cachedAt = time(),
        shape = RECORD_SHAPE,
        seeded = time(),
    }
    cache[record.guid] = record
    IndexRecord(record)
    return record
end


function Player:NameHint()
    return Player.IS_FOREVER and T["use the character's whole two-word name"]
        or T["use a player and realm, for example Name-Area 52"]
end



function Player:WhisperTarget(name)
    if not Player.IS_FOREVER or type(name) ~= "string" or IsSecret(name) then return name end
    return name:match("^%s*([^%-]-)%s*%-") or name
end



function Player:FromChat(sender)
    if not Player.IS_FOREVER or type(sender) ~= "string" or sender == ""
        or IsSecret(sender) or sender:find("-", 1, true) then return sender end
    local record = self:Get(sender)
    return record.guid and record.fullName or Qualify(sender, nil)
end



function Player:GetFullName(unit)


    if Player.IS_FOREVER then
        local guid = UnitGUID(unit)
        if type(guid) == "string" and not IsSecret(guid) and guid:match("^Player%-") then
            local record = self:Get(guid)
            if record.guid and record.fullName then return record.fullName end
        end
    end
    local name, realm = UnitFullName(unit)
    if IsSecret(name, realm) then return nil end
    return Qualify(UnitNameParts(name, realm))
end


function Player:UnitFor(input)
    local record = self:Get(input)
    if not record.guid then return nil end

    return addon.Roster and addon.Roster:UnitForGUID(record.guid) or nil
end



function Player:Qualify(input)
    if type(input) ~= "string" or input == "" then return nil end
    if IsSecret(input) then return nil end


    if Player.IS_FOREVER then
        local guid = byName[NameKey(input) or ""]
        local known = guid and cache[guid]
        if known and known.fullName then return known.fullName end
    end

    local name, realm = input:match("^([^-]+)-(.+)$")
    if name then return Qualify(name, realm) end
    return Qualify(input, nil)
end



function Player:CanonicalName(input)
    if type(input) ~= "string" or input == "" or IsSecret(input) then return nil end

    input = input:gsub("^%s*(.-)%s*$", "%1")
    local name, realm = input:match("^([^-]+)-(.+)$")
    name = name or input
    realm = realm or ownRealm
    if not name or name == "" or not realm or realm == "" then return nil end


    local record = self:Get(Qualify(name, realm))
    if record and record.guid and record.name and record.realm then
        return Qualify(record.name, CanonicalRealm(record.realm))
    end

    return Qualify(CharacterDisplay(name), CanonicalRealm(realm))
end


local function SideScore(side)
    local score = 0
    local realm = side:match("^[^%-]*%-(.+)$")
    if realm then
        local key = RealmKey(realm)
        CanonicalRealm(realm)
        if key and realmNames and realmNames[key] then score = score + 1 end
    end
    if byName[NameKey(side) or ""] then score = score + 1 end
    return score
end


local function TwoWords(side)
    return side:match("^%s*[^%s%-]+%s[^%s%-]+%s*%-") ~= nil
end



function Player:SplitPair(text)
    if type(text) ~= "string" or IsSecret(text) then return nil, "shape" end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")

    local left, right = text:match("^([^,>]-)%s*[,>]%s*(.+)$")
    if left then
        if NameKey(left) and NameKey(right) then return left, right end
        return nil, "shape"
    end


    local best, bestScore, tied
    for at in text:gmatch("()%s+") do
        left = text:sub(1, at - 1)
        right = text:sub(at):gsub("^%s+", "")
        if NameKey(left) and right:match("^[^%-%d]") and NameKey(right)
            and (not Player.IS_FOREVER or (TwoWords(left) and TwoWords(right))) then
            local score = SideScore(left) + SideScore(right)
            if not best or score > bestScore then
                best, bestScore, tied = { left, right }, score, false
            elseif score == bestScore then
                tied = true
            end
        end
    end
    if not best then return nil, "shape" end
    if tied then return nil, "ambiguous" end
    return best[1], best[2]
end



function Player:IsGUID(input)
    return LooksLikeGUID(input)
end



function Player:NameKey(input)
    return NameKey(input)
end


function Player:IsSame(a, b)
    local pa, pb = self:Get(a), self:Get(b)
    if pa.nobody or pb.nobody then return false end
    if pa.guid and pb.guid then return pa.guid == pb.guid end
    if Player.IS_FOREVER then
        local ka, kb = NameKey(pa.fullName), NameKey(pb.fullName)
        if ka and kb then return ka == kb end
    end
    if pa.fullName and pb.fullName then return pa.fullName == pb.fullName end
    return false
end

function Player:IsSelf(input)
    return self:IsSame(input, UnitGUID("player"))
end


local flagged = {}


function Player:SetCouncil(guid, isCouncil)
    local record = self:Get(guid)
    if not record.guid then return end
    record.isCouncil = isCouncil and true or nil
    flagged[record.guid] = record.isCouncil and record or nil
end

function Player:ClearAllCouncilFlags()
    for _, record in pairs(flagged) do record.isCouncil = nil end
    flagged = {}
end


function Player:ForTransmit(input)
    local record = self:Get(input)
    if not record.guid then return nil end

    return (record.guid:gsub("^Player%-", ""))
end










function Player:Main(input)
    local qualified = self:Qualify(input)
    if not qualified then return input end

    local mains = addon.db and addon.db.mains
    local wanted = NameKey(qualified)
    if mains and wanted then
        for alt, main in pairs(mains) do
            if NameKey(alt) == wanted then
                return CompactQualifiedName(main) or main
            end
        end
    end
    return CompactQualifiedName(qualified) or qualified
end


function Player:Alts(input)
    local qualified = self:Qualify(input)
    local alts = {}
    local mains = addon.db and addon.db.mains
    if not qualified or not mains then return alts end

    local wanted = NameKey(qualified)
    for alt, main in pairs(mains) do
        if wanted and NameKey(main) == wanted then
            alts[#alts + 1] = CompactQualifiedName(alt) or alt
        end
    end
    return alts
end


function Player:SetMain(altInput, mainInput)
    local alt = self:CanonicalName(altInput)
    local main = self:CanonicalName(mainInput)
    if not alt or not main then
        return false, self:NameHint()
    end
    local altKey, mainKey = NameKey(alt), NameKey(main)
    if altKey == mainKey then
        return false, T["a character cannot be their own main"]
    end

    addon.db.mains = addon.db.mains or {}
    local mains = addon.db.mains


    for existingAlt, existingMain in pairs(mains) do
        if NameKey(existingAlt) == mainKey then
            return false, addon.Locale.Format(T["%s is itself recorded as an alt of %s"],
                main, existingMain)
        end
    end

    for existingAlt, existingMain in pairs(mains) do
        if NameKey(existingMain) == altKey then
            return false, addon.Locale.Format(T["%s is already recorded as a main, for %s"],
                alt, existingAlt)
        end
    end

    mains[alt] = main
    addon.Log:I("Player", "linked", alt, "as an alt of", main)
    if addon.Callbacks then addon.Callbacks:Fire("MainsChanged") end
    return true
end



function Player:ClearMain(altInput)
    local alt = self:CanonicalName(altInput)
    local mains = addon.db and addon.db.mains
    if not alt or not mains then return false end

    local wanted = NameKey(alt)
    local storedAlt
    for existingAlt in pairs(mains) do
        if wanted and NameKey(existingAlt) == wanted then
            storedAlt = existingAlt
            break
        end
    end
    if not storedAlt then return false end

    mains[storedAlt] = nil
    addon.Log:I("Player", "unlinked", storedAlt, "from its main")
    if addon.Callbacks then addon.Callbacks:Fire("MainsChanged") end
    return true
end





function Player:Init(db)
    db.playerCache = db.playerCache or {}
    cache = db.playerCache
    byName, byBare, missedNames = {}, {}, {}



    local _, realm = UnitFullName("player")

    if Player.IS_FOREVER then realm = GetNormalizedRealmName and GetNormalizedRealmName() end
    ownRealm = (realm and not IsSecret(realm)) and realm or nil
    realmNames = nil



    local selfGUID = UnitGUID and UnitGUID("player")
    if selfGUID and not IsSecret(selfGUID) then self:Get(selfGUID) end



    if db.mains then
        local canonical = {}
        for alt, main in pairs(db.mains) do
            local canonicalAlt = self:CanonicalName(alt)
            local canonicalMain = self:CanonicalName(main)
            if canonicalAlt and canonicalMain and canonicalAlt ~= canonicalMain then
                canonical[canonicalAlt] = canonicalMain
            end
        end
        db.mains = canonical
    end



    local linked = {}
    for alt, main in pairs(db.mains or {}) do
        local altKey, mainKey = NameKey(alt), NameKey(main)
        if altKey then linked[altKey] = true end
        if mainKey then linked[mainKey] = true end
    end


    local now = time()
    local pruned, kept = 0, 0
    flagged = {}
    for guid, record in pairs(cache) do
        if type(record) == "table" and record.isCouncil then flagged[guid] = record end
        local isLinked = record.fullName and linked[NameKey(record.fullName) or ""]
        if not record.isCouncil and not isLinked
            and (now - (record.cachedAt or 0)) > CACHE_TTL then
            cache[guid] = nil
            pruned = pruned + 1
        else
            kept = kept + 1
            if type(record) == "table" then IndexRecord(record) end
        end
    end



    addon.Log:I("Player", "cache ready", ("%d entries, pruned %d, realm %s")
        :format(kept, pruned, tostring(ownRealm)))

    if addon.Roster and addon.Roster.Init then addon.Roster:Init() end
end
