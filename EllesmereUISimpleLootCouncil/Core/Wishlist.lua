if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Wishlist = {}
addon.Wishlist = Wishlist




local function TierColour(priorityId)
    local S = addon.Style
    if priorityId == 1 then return S.color.accent end
    if priorityId == 2 then return S.color.good end
    if priorityId == 3 then return S.color.accentPale end
    if priorityId == 4 then return S.color.textMuted end
    if priorityId == 5 then return S.color.textFaint end


    return S.color.text
end


local DIFFICULTY_ALIASES = {
    [233] = 16,
}

local function Canonical(difficultyID)
    if not difficultyID then return nil end
    return DIFFICULTY_ALIASES[difficultyID] or difficultyID
end






local SOURCE_ADDON = {
    wowutils = "wowutils",
    gow = "GuildsOfWoW",
    wowaudit = "RCLootCouncil_wowaudit",
}


function Wishlist:Source()
    local source = addon.db and addon.db.wishlistSource
    return SOURCE_ADDON[source] and source or "wowutils"
end


local function GoWModule()
    local gow = type(GuildsOfWow) == "table" and GuildsOfWow.Wishlists
    if type(gow) == "table" and type(gow.state) == "table" then return gow end
    return nil
end




local function WowauditData()
    local file = addon.WowauditFile
    if type(wowauditDataPresent) == "function" and type(_G.wishlistData) == "table" then
        local stamp = type(_G.wowauditTimestamp) == "number" and _G.wowauditTimestamp or 0
        if not (file and file.wowauditTimestamp > stamp) then
            return _G.wishlistData, "addon"
        end
    end
    if file then return file.wishlistData, file.origin or "file" end
    return nil
end


function Wishlist:IsAvailable()

    if addon.IsForever then return false end
    if addon.db and addon.db.wishlistEnabled == false then return false end
    local source = self:Source()
    if source == "gow" then return GoWModule() ~= nil end
    if source == "wowaudit" then return WowauditData() ~= nil end
    return type(WowUtilsAPI) == "table"
        and type(WowUtilsAPI.GetWishlist) == "function"
        and type(WowUtilsAPI.GetDroptimizers) == "function"
end



local iconCache = {}

function Wishlist:SourceIcon()
    local source = self:Source()
    local cached = iconCache[source]
    if cached == nil then
        cached = false
        local get = C_AddOns and C_AddOns.GetAddOnMetadata
        local ok, path = false, nil
        if get then ok, path = pcall(get, SOURCE_ADDON[source], "IconTexture") end
        if ok and type(path) == "string" and path ~= "" then cached = path end
        iconCache[source] = cached
    end
    return cached or nil
end








local TTL = 3
local cache = {}


function Wishlist:Invalidate()
    cache = {}
end




local function Cached(kind, name, item, build)
    local byItem = cache[kind]
    if not byItem then
        byItem = {}
        cache[kind] = byItem
    end
    local byName = byItem[item.link]
    if not byName then
        byName = {}
        byItem[item.link] = byName
    end
    local hit = byName[name]
    local now = GetTime()
    if hit and (now - hit.at) < TTL then return hit.value end

    local value = build(name, item)

    if hit then
        hit.at, hit.value = now, value or false
    else
        byName[name] = { at = now, value = value or false }
    end
    return value
end








local function DifficultyOf(item)
    if not item then return nil end
    return Canonical(item.difficultyID
        or addon.Encounter:DifficultyFor(item.boss, item.encounterID))
end




local function BestPick(picks, wantId, difficultyID)
    local best
    for _, pick in pairs(picks) do
        if pick.itemId == wantId then
            local pickDif = Canonical(pick.difficultyId)
            if difficultyID then
                if pickDif == difficultyID then
                    best = pick
                    break
                end
            elseif not best or (pickDif or 0) > (Canonical(best.difficultyId) or 0) then


                best = pick
            end
        end
    end
    return best
end


local function AsEntryArray(entries)
    if type(entries) ~= "table" then return nil end
    if entries.gain or entries.gainPercent or entries.difficultyId then
        return { entries }
    end
    return entries
end




local function PiecesForToken(name, tokenId)
    local ok, data = pcall(WowUtilsAPI.GetDroptimizers, name)
    if not (ok and type(data) == "table" and type(data.specs) == "table") then
        return nil
    end

    local pieces
    for _, sims in pairs(data.specs) do
        for _, sim in pairs(sims) do
            if type(sim) == "table" and type(sim.items) == "table" then
                for pieceId, rawEntries in pairs(sim.items) do
                    local entries = AsEntryArray(rawEntries)
                    if entries then
                        for _, entry in ipairs(entries) do
                            if type(entry) == "table" and entry.sourceItem
                                and entry.sourceItem.itemId == tokenId
                                and not entry.sourceItem.catalyst then
                                pieces = pieces or {}
                                pieces[pieceId] = true
                            end
                        end
                    end
                end
            end
        end
    end
    return pieces
end






local GOW_RANK = { BIS = 1, NEED = 2, GREED = 3, MINOR = 4, OFFSPEC = 5, TRANSMOG = 6 }
local GOW_LABEL = addon.Locale.Texts{
    BIS = T["BiS"],
    NEED = T["Need"],
    GREED = T["Greed"],
    MINOR = T["Minor"],
    OFFSPEC = T["Offspec"],
    TRANSMOG = T["Transmog"],
}


local GOW_DIFFICULTY_ID = { Normal = 14, Heroic = 15, Mythic = 16, LFR = 17 }
local GOW_DIFFICULTY = {}
for name, id in pairs(GOW_DIFFICULTY_ID) do GOW_DIFFICULTY[id] = name end


local gowIndex, gowIndexOf

local function GoWEntriesFor(name)
    local gow = GoWModule()
    if not gow then return nil end

    local data = gow.state.guildWishlistData
    local lists = type(data) == "table" and type(data.wishlists) == "table" and data.wishlists
    if lists and gowIndexOf ~= lists then
        gowIndex, gowIndexOf = {}, lists
        for _, char in ipairs(lists) do
            if type(char) == "table" and char.name and type(char.wishlist) == "table" then
                local key = addon.Player:NameKey(char.name .. "-" .. (char.realmNameNormalized or ""))
                if key then gowIndex[key] = char.wishlist end
            end
        end
    end

    local found = lists and gowIndex[addon.Player:NameKey(name) or ""]
    if found then return found end

    if addon.Player:IsSelf(name) and type(gow.state.allItems) == "table" then
        return gow.state.allItems
    end
    return nil
end



local function GoWMatches(name, item)
    local entries = GoWEntriesFor(name)
    local itemID = entries and addon.Storage.ItemID(item.link)
    if not itemID then return nil end

    local want = GOW_DIFFICULTY[DifficultyOf(item) or 0]
    local matches
    for _, e in ipairs(entries) do
        if type(e) == "table" and not e.isObtained
                and (e.itemId == itemID or e.sourceItemId == itemID)
                and (not want or e.difficulty == want) then
            matches = matches or {}
            matches[#matches + 1] = e
        end
    end
    return matches, itemID, want ~= nil
end


local function GoWPercent(e)
    local pct = type(e.gain) == "table" and tonumber(e.gain.percent)
    if not pct or (pct == 0 and (tonumber(e.gain.stat) or 0) == 0) then return nil end
    return pct
end


local function GoWBetter(a, b, exact)
    if not exact then
        local da = GOW_DIFFICULTY_ID[a.difficulty] or 0
        local db = GOW_DIFFICULTY_ID[b.difficulty] or 0
        if da ~= db then return da > db end
    end
    local ra = GOW_RANK[a.tag] or math.huge
    local rb = GOW_RANK[b.tag] or math.huge
    if ra ~= rb then return ra < rb end
    return (GoWPercent(a) or -math.huge) > (GoWPercent(b) or -math.huge)
end

local function GoWFor(name, item)
    local matches, itemID, exact = GoWMatches(name, item)
    if not matches then return nil end
    local best = matches[1]
    for i = 2, #matches do
        if GoWBetter(matches[i], best, exact) then best = matches[i] end
    end

    local rank = GOW_RANK[best.tag]
    return {
        label = GOW_LABEL[best.tag] or best.tag,
        priorityId = rank,

        colour = TierColour(rank and math.min(rank, 5)),
        difficultyID = GOW_DIFFICULTY_ID[best.difficulty],
        exact = exact,
        viaPiece = best.itemId ~= itemID and best.itemId or nil,
    }
end


local function GoWSimFor(name, item)
    local matches, itemID = GoWMatches(name, item)
    if not matches then return nil end
    local best
    for _, e in ipairs(matches) do
        local pct = GoWPercent(e)
        if pct and (not best or best.pct < pct) then
            best = { pct = pct, gain = tonumber(e.gain.stat),
                viaPiece = e.itemId ~= itemID and e.itemId or nil }
        end
    end
    return best
end






local WA_DIFFICULTY = { [17] = "R", [14] = "N", [15] = "H", [16] = "M" }
local WA_ORDER = { "M", "H", "N", "R" }
local WA_DIFFICULTY_ID = { R = 17, N = 14, H = 15, M = 16 }



local WA_STATUS_RANK = { b = 1, n = 2, o = 4 }
local WA_LEVEL_RANK = { huge = 1, big = 2, small = 3, tiny = 4 }
local WA_LABEL = addon.Locale.Texts{
    b = T["BiS"],
    n = T["Not BiS"],
    o = T["Outdated"],
    huge = T["Huge"],
    big = T["Big"],
    small = T["Small"],
    tiny = T["Tiny"],
}


local waIndex, waIndexOf

local function WowauditEntriesFor(name)
    local data = WowauditData()
    if not data then return nil end
    if waIndexOf ~= data then
        waIndex, waIndexOf = {}, data
        for character, diffs in pairs(data) do
            local key = type(character) == "string" and addon.Player:NameKey(character)
            if key and type(diffs) == "table" then waIndex[key] = diffs end
        end
    end
    return waIndex[addon.Player:NameKey(name) or ""]
end


local function WaNumber(raw)
    local kind = type(raw)
    if kind == "string" then return tonumber((raw:gsub("%%", ""))) end
    return kind == "number" and raw or nil
end


local function WaRead(wish)
    local level = wish.l or wish.level
    level = type(level) == "string" and level:lower() or nil
    local value, pct = wish.v or wish.value, wish.p or wish.percent
    if not WA_LEVEL_RANK[level] and type(value) == "string" and WA_LEVEL_RANK[value:lower()] then
        level = value:lower()
    end
    if level and WA_LEVEL_RANK[level] then
        return WA_LEVEL_RANK[level], level, nil
    end
    local status = wish.s or wish.status
    local sim
    local p = WaNumber(pct)
    if p then sim = { pct = p, gain = type(value) == "number" and value or nil } end
    return WA_STATUS_RANK[status], WA_STATUS_RANK[status] and status or nil, sim
end



local function WowauditMatches(name, item)
    local diffs = WowauditEntriesFor(name)
    local itemID = diffs and addon.Storage.ItemID(item.link)
    if not itemID then return nil end

    local want = WA_DIFFICULTY[DifficultyOf(item) or 0]
    for _, letter in ipairs(WA_ORDER) do
        local wishes = (not want or want == letter) and diffs[letter]
        if type(wishes) == "table" then
            local matches
            for _, wish in ipairs(wishes) do
                if type(wish) == "table" and tonumber(wish.id) == itemID then
                    matches = matches or {}
                    matches[#matches + 1] = wish
                end
            end
            if matches then return matches, letter, want ~= nil end
        end
    end
    return nil
end

local function WowauditFor(name, item)
    local matches, letter, exact = WowauditMatches(name, item)
    if not matches then return nil end
    local best, bestRank, bestKey, bestPct
    for _, wish in ipairs(matches) do
        local rank, key, sim = WaRead(wish)
        local pct = sim and sim.pct or -math.huge
        if key and (not best or rank < bestRank or (rank == bestRank and pct > bestPct)) then
            best, bestRank, bestKey, bestPct = wish, rank, key, pct
        end
    end
    if not best then return nil end
    return {
        label = WA_LABEL[bestKey],
        priorityId = bestRank,
        colour = TierColour(bestRank),
        difficultyID = WA_DIFFICULTY_ID[letter],
        exact = exact,
    }
end


local function WowauditSimFor(name, item)
    local matches = WowauditMatches(name, item)
    if not matches then return nil end
    local best
    for _, wish in ipairs(matches) do
        local _, _, sim = WaRead(wish)
        if sim and (not best or best.pct < sim.pct) then best = sim end
    end
    return best
end




local function WowUtilsFor(name, item)
    local itemID = addon.Storage.ItemID(item.link)
    if not itemID then return nil end

    local difficultyID = DifficultyOf(item)
    local isToken = addon.Loot and addon.Loot:IsTierToken(itemID)

    local ok, picks = pcall(WowUtilsAPI.GetWishlist, name)
    if not (ok and type(picks) == "table") then return nil end

    local best, viaPiece
    if isToken then
        local pieces = PiecesForToken(name, itemID)
        if pieces then
            for pieceId in pairs(pieces) do
                local pick = BestPick(picks, pieceId, difficultyID)
                if pick and (not best
                    or (pick.priorityId or math.huge) < (best.priorityId or math.huge)) then
                    best, viaPiece = pick, pieceId
                end
            end
        end
    else
        best = BestPick(picks, itemID, difficultyID)
    end

    if not best then return nil end
    return {
        label = best.priority,
        priorityId = best.priorityId,
        colour = TierColour(best.priorityId),

        difficultyID = Canonical(best.difficultyId),
        exact = difficultyID ~= nil,


        viaPiece = viaPiece,
    }
end

function Wishlist:For(name, item)
    if not (self:IsAvailable() and name and item and item.link) then return nil end
    local source = self:Source()
    if source == "gow" then return Cached("gw", name, item, GoWFor) end
    if source == "wowaudit" then return Cached("aw", name, item, WowauditFor) end
    return Cached("w", name, item, WowUtilsFor)
end




local function Percent(sim, entry)
    if sim.baseline and sim.baseline ~= 0 and entry.gain then
        return (entry.gain / sim.baseline) * 100, entry.gain
    end
    if entry.gainPercent then return entry.gainPercent, nil end
    return nil
end






local function BestOfSim(sim, itemID, difficultyID, wantSourceItemId)
    local entries = AsEntryArray(type(sim.items) == "table" and sim.items[itemID])
    if not entries then return nil end

    local direct, viaSource
    for _, entry in ipairs(entries) do


        if type(entry) == "table" and (not difficultyID
                or Canonical(entry.difficultyId) == difficultyID) then
            if wantSourceItemId then
                if entry.sourceItem and entry.sourceItem.itemId == wantSourceItemId
                        and not entry.sourceItem.catalyst then
                    local pct, gain = Percent(sim, entry)
                    if pct and (not viaSource or viaSource.pct < pct) then
                        viaSource = { pct = pct, gain = gain }
                    end
                end
            else
                local pct, gain = Percent(sim, entry)
                if pct then
                    if entry.sourceItem then
                        if not viaSource or viaSource.pct < pct then
                            viaSource = { pct = pct, gain = gain }
                        end
                    elseif not direct or direct.pct < pct then
                        direct = { pct = pct, gain = gain }
                    end
                end
            end
        end
    end


    return direct or viaSource
end


local function BestTokenSim(sim, tokenId, difficultyID)
    if type(sim.items) ~= "table" then return nil end

    local best, bestPiece
    for pieceId in pairs(sim.items) do
        local result = BestOfSim(sim, pieceId, difficultyID, tokenId)
        if result and (not best or best.pct < result.pct) then
            best, bestPiece = result, pieceId
        end
    end
    if best then best.viaPiece = bestPiece end
    return best
end




local function WowUtilsSimFor(name, item)
    local itemID = addon.Storage.ItemID(item.link)
    if not itemID then return nil end

    local difficultyID = DifficultyOf(item)
    local isToken = addon.Loot and addon.Loot:IsTierToken(itemID)

    local ok, data = pcall(WowUtilsAPI.GetDroptimizers, name)
    if not (ok and type(data) == "table" and type(data.specs) == "table") then
        return nil
    end

    local best, exact
    for _, sims in pairs(data.specs) do
        for simKey, sim in pairs(sims) do
            local result
            if type(sim) == "table" then
                if isToken then
                    result = BestTokenSim(sim, itemID, difficultyID)
                else
                    result = BestOfSim(sim, itemID, difficultyID)
                end
            end
            if result then


                local key = tostring(simKey):lower()
                if key:match("patchwerk%-1$") or key:match("0%-1$") then
                    if not exact or exact.pct < result.pct then exact = result end
                elseif not best or best.pct < result.pct then
                    best = result
                end
            end
        end
    end

    return exact or best
end

function Wishlist:SimFor(name, item)
    if not (self:IsAvailable() and name and item and item.link) then return nil end
    local source = self:Source()
    if source == "gow" then return Cached("gs", name, item, GoWSimFor) end
    if source == "wowaudit" then return Cached("as", name, item, WowauditSimFor) end
    return Cached("s", name, item, WowUtilsSimFor)
end


function Wishlist.GainColour(pct)
    local S = addon.Style
    if not pct then return S.color.textFaint end
    if pct > 0.5 then return S.color.good end
    if pct > 0 then return S.color.accent end
    if pct < -0.5 then return S.color.bad end
    return S.color.textMuted
end


function Wishlist.FormatGain(sim)
    if not sim then return nil end
    if sim.gain then
        return addon.Locale.Format(T["%+.2f%%  (%+.0f)"], sim.pct or 0, sim.gain)
    end
    return ("%+.2f%%"):format(sim.pct or 0)
end


function Wishlist.FormatPct(sim)
    if not sim then return nil end
    return ("%+.2f%%"):format(sim.pct or 0)
end


function Wishlist.FormatAbs(sim)
    if not sim or not sim.gain then return nil end
    return ("%+.0f"):format(sim.gain)
end







local function Usable(file)
    return type(file) == "table" and type(file.wowauditTimestamp) == "number"
        and type(file.wishlistData) == "table"
end

function Wishlist.ReconcileFile()
    local db = addon.db
    if not db then return end
    local file, saved = addon.WowauditFile, db.wowauditCopy
    if Usable(file) and (not Usable(saved) or file.wowauditTimestamp > saved.wowauditTimestamp) then
        db.wowauditCopy = file
    elseif Usable(saved) and (not Usable(file) or saved.wowauditTimestamp > file.wowauditTimestamp) then
        local copy = {}
        for k, v in pairs(saved) do copy[k] = v end
        copy.origin = "saved_copy"
        addon.WowauditFile = copy
    end
end

function Wishlist:Init()
    Wishlist.ReconcileFile()


    local source = self:Source()
    if addon.db and addon.db.wishlistEnabled == false then
        addon.Log:I("Wishlist", "imported wishlist data switched off, wishlist columns hidden")
    elseif self:IsAvailable() then
        local _, from = WowauditData()
        addon.Log:I("Wishlist", source, "detected, wishlist and sim columns enabled",
            source == "wowaudit" and ("read from " .. from) or "")
    else
        addon.Log:I("Wishlist", source, "not installed, wishlist columns hidden")
    end


    addon.Callbacks:Register("RunStarted", function() Wishlist:Invalidate() end)
    addon.Callbacks:Register("RunEnded", function() Wishlist:Invalidate() end)
end
