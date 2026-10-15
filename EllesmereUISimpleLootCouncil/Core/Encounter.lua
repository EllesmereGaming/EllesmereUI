if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 






SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Encounter = {}
addon.Encounter = Encounter


local GRACE = 10 * 60


local TRADE_WINDOW = 2 * 60 * 60


local MAX_LOG = 40


local RETENTION = TRADE_WINDOW + GRACE

local active = nil







local function Log()
    addon.db.encounterLog = addon.db.encounterLog or {}

    local log = addon.db.encounterLog
    local cutoff = GetServerTime() - RETENTION
    local dropped = 0

    while #log > 0 do
        local entry = log[1]
        if entry == active then break end
        if (entry.endedAt or entry.startedAt or 0) >= cutoff then break end
        table.remove(log, 1)
        dropped = dropped + 1
    end

    if dropped > 0 then
        addon.Log:D("Encounter", "pruned", dropped, "entries past the trade window")
    end

    return log
end

local function Trim(log)
    while #log > MAX_LOG do table.remove(log, 1) end
end


local function Now()
    return GetServerTime()
end

function Encounter:OnStart(encounterID, encounterName, difficultyID)
    local log = Log()
    active = {
        id = encounterID,
        name = encounterName,
        difficultyID = difficultyID,
        startedAt = Now(),
    }
    log[#log + 1] = active
    Trim(log)
    addon.Log:I("Encounter", "started", tostring(encounterName))
end

function Encounter:OnEnd(encounterID, encounterName, difficultyID, success)
    local log = Log()


    local entry = active
    if not entry or entry.id ~= encounterID then
        entry = nil
        for i = #log, 1, -1 do
            if log[i].id == encounterID and not log[i].endedAt then
                entry = log[i]
                break
            end
        end
    end

    if not entry then

        entry = {
            id = encounterID,
            name = encounterName,
            difficultyID = difficultyID,
            startedAt = Now(),
        }
        log[#log + 1] = entry
        Trim(log)
    end

    entry.endedAt = Now()
    entry.success = success == 1
    active = nil
    addon.Log:I("Encounter", "ended", tostring(encounterName),
        entry.success and "(kill)" or "(wipe)")


    if addon.Callbacks then addon.Callbacks:Fire("EncounterEnded", entry) end
end





local issecretvalue = issecretvalue
local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end



local FOREVER_BOSSES = {

    [644] = { "Rhahk'Zor", 2741 },
    [3586] = { "Miner Johnson", 3676 },
    [643] = { "Sneed", 2742 },
    [1763] = { "Gilnid", 2743 },
    [646] = { "Mr. Smite", 2745 },
    [647] = { "Captain Greenskin", 2744 },
    [639] = { "Edwin VanCleef", 2747 },
    [645] = { "Cookie", 2746 },


    [3669] = { "Lord Cobrahn", 586 },
    [3671] = { "Lady Anacondra", 585 },
    [3653] = { "Kresh", 587 },
    [3670] = { "Lord Pythas", 588 },
    [3674] = { "Skum", 589 },
    [3673] = { "Lord Serpentis", 590 },
    [5775] = { "Verdan the Everliving", 591 },
    [3654] = { "Mutanus the Devourer", 592 },


    [3914] = { "Rethilgore", 2748 },
    [3886] = { "Razorclaw the Butcher", 2749 },
    [3887] = { "Baron Silverlaine", 2750 },
    [4278] = { "Commander Springvale", 2751 },
    [4279] = { "Odo the Blindwatcher", 2752 },
    [4274] = { "Fenrus the Devourer", 2753 },
    [3927] = { "Wolf Master Nandos", 2754 },
    [4275] = { "Archmage Arugal", 2755 },


    [4887] = { "Ghamoo-ra", 2916 },
    [4831] = { "Lady Sarevess", 2915 },
    [6243] = { "Geilhast", 2914 },
    [4832] = { "Twilight Lord Kelris", 2911 },
    [4830] = { "Old Serra'kis", 2912 },
    [4829] = { "Aku'mai", 2910 },


    [4424] = { "Aggem Thorncurse", 2774 },
    [4428] = { "Death Speaker Jargba", 2775 },
    [4420] = { "Overlord Ramtusk", 2776 },
    [4422] = { "Agathelos the Raging", 2777 },
    [4421] = { "Charlga Razorflank", 2778 },


    [3983] = { "Interrogator Vishas", 444 },
    [4543] = { "Bloodmage Thalnos", 2779 },
    [3974] = { "Houndmaster Loksey", 446 },
    [6487] = { "Arcanist Doan", 447 },
    [3975] = { "Herod", 448 },
    [4542] = { "High Inquisitor Fairbanks", 449 },
    [3976] = { "Scarlet Commander Mograine", nil },
    [3977] = { "High Inquisitor Whitemane", 450 },


    [6109] = { "Azuregos", 3027 },
    [12397] = { "Lord Kazzak", 3026 },
    [14888] = { "Lethon", 3112 },
    [14889] = { "Emeriss", 3111 },
    [14890] = { "Taerar", 3113 },
    [14887] = { "Ysondre", 3114 },


    [12118] = { "Lucifron", 663 },
    [11982] = { "Magmadar", 664 },
    [12259] = { "Gehennas", 665 },
    [12057] = { "Garr", 666 },
    [12264] = { "Shazzrah", 667 },
    [12056] = { "Baron Geddon", 668 },
    [11988] = { "Golemagg the Incinerator", 670 },
    [12098] = { "Sulfuron Harbinger", 669 },
    [12018] = { "Majordomo Executus", 671 },
    [11502] = { "Ragnaros", 672 },


    [10184] = { "Onyxia", 1084 },


    [14517] = { "High Priestess Jeklik", 785 },
    [14507] = { "High Priest Venoxis", 784 },
    [14510] = { "High Priestess Mar'li", 786 },
    [11382] = { "Bloodlord Mandokir", 787 },
    [15082] = { "Edge of Madness", 788 },
    [15083] = { "Edge of Madness", 788 },
    [15084] = { "Edge of Madness", 788 },
    [15085] = { "Edge of Madness", 788 },
    [15114] = { "Gahz'ranka", 790 },
    [14509] = { "High Priest Thekal", 789 },
    [14515] = { "High Priestess Arlokk", 791 },
    [11380] = { "Jin'do the Hexxer", 792 },
    [14834] = { "Hakkar", 793 },


    [12435] = { "Razorgore the Untamed", 610 },
    [13020] = { "Vaelastrasz the Corrupt", 611 },
    [12017] = { "Broodlord Lashlayer", 612 },
    [11983] = { "Firemaw", 613 },
    [14601] = { "Ebonroc", 614 },
    [11981] = { "Flamegor", 615 },
    [14020] = { "Chromaggus", 616 },
    [11583] = { "Nefarian", 617 },


    [15348] = { "Kurinnaxx", 718 },
    [15341] = { "General Rajaxx", 719 },
    [15340] = { "Moam", 720 },
    [15370] = { "Buru the Gorger", 721 },
    [15369] = { "Ayamiss the Hunter", 722 },
    [15339] = { "Ossirian the Unscarred", 723 },


    [15263] = { "The Prophet Skeram", 709 },
    [15543] = { "Silithid Royalty", 710 },
    [15544] = { "Silithid Royalty", 710 },
    [15511] = { "Silithid Royalty", 710 },
    [15516] = { "Battleguard Sartura", 711 },
    [15510] = { "Fankriss the Unyielding", 712 },
    [15299] = { "Viscidus", 713 },
    [15509] = { "Princess Huhuran", 714 },
    [15275] = { "Twin Emperors", 715 },
    [15276] = { "Twin Emperors", 715 },
    [15517] = { "Ouro", 716 },
    [15727] = { "C'thun", 717 },


    [15956] = { "Anub'Rekhan", 1107 },
    [15953] = { "Grand Widow Faerlina", 1110 },
    [15952] = { "Maexxna", 1116 },
    [15954] = { "Noth the Plaguebringer", 1117 },
    [15936] = { "Heigan the Unclean", 1112 },
    [16011] = { "Loatheb", 1115 },
    [16061] = { "Instructor Razuvious", 1113 },
    [16060] = { "Gothik the Harvester", 1109 },
    [16064] = { "The Four Horsemen", 1121 },
    [16065] = { "The Four Horsemen", 1121 },
    [16062] = { "The Four Horsemen", 1121 },
    [16063] = { "The Four Horsemen", 1121 },
    [16028] = { "Patchwerk", 1118 },
    [15931] = { "Grobbulus", 1111 },
    [15932] = { "Gluth", 1108 },
    [15928] = { "Thaddius", 1120 },
    [15989] = { "Sapphiron", 1119 },
    [15990] = { "Kel'Thuzad", 1114 },
}


local FOREVER_BOSS_OBJECTS = {
    [179703] = { "Majordomo Executus", 671 },
}



local function BossForGUID(guid)
    if type(guid) ~= "string" or IsSecret(guid) then return nil end
    local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-")
    local boss
    if kind == "Creature" or kind == "Vehicle" then
        boss = FOREVER_BOSSES[tonumber(id)]
    elseif kind == "GameObject" then
        boss = FOREVER_BOSS_OBJECTS[tonumber(id)]

        if not boss and select(2, GetInstanceInfo()) == "raid" then
            addon.Log:D("Encounter", "unlisted loot object in a raid", guid)
        end
    end
    if boss then return boss[1], boss[2] end
    return nil
end


function Encounter:BossForLootSource(guid)
    if not addon.IsForever then return nil end
    return BossForGUID(guid)
end



function Encounter:RecordLootSource(guid)
    local name, encounterID = BossForGUID(guid)
    if not name then return nil end

    local log = Log()
    local now = Now()
    for i = #log, 1, -1 do
        local entry = log[i]
        if entry.guid == guid then

            entry.endedAt = now
            return entry
        end
        local same = Encounter.SameBoss(entry.name, entry.id, name, encounterID)
            or entry.name == name
        if same and not entry.looted
            and (entry == active or (entry.endedAt and now - entry.endedAt <= GRACE)) then
            addon.Log:D("Encounter", "corpse of", name, "already covered by",
                tostring(entry.name), "encounter", tostring(entry.id))
            return nil
        end
    end

    local _, instanceType, difficultyID = GetInstanceInfo()
    local entry = {
        id = encounterID,
        name = name,
        difficultyID = (instanceType == "raid" or instanceType == "party")
            and difficultyID or nil,
        startedAt = now,
        endedAt = now,
        success = true,
        looted = true,
        guid = guid,
    }
    log[#log + 1] = entry
    Trim(log)
    addon.Log:D("Encounter", "corpse looted", name, "encounter", tostring(encounterID),
        "difficulty", tostring(entry.difficultyID), guid)
    return entry
end



local function RecordSources(seen, ...)
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "string" and not IsSecret(value) and not seen[value] then
            seen[value] = true
            Encounter:RecordLootSource(value)
        end
    end
end

local function OnLootReady()
    if not GetLootSourceInfo then return end
    local count = GetNumLootItems() or 0
    if IsSecret(count) then return end
    local seen = {}
    for slot = 1, count do
        RecordSources(seen, GetLootSourceInfo(slot))
    end
end






function Encounter:GetLog()
    return Log()
end










function Encounter.SameBoss(nameA, idA, nameB, idB)
    if idA and idB then return tonumber(idA) == tonumber(idB) end
    return nameA ~= nil and nameA == nameB
end


function Encounter:DisplayName(bossName, encounterID)
    encounterID = tonumber(encounterID)
    if encounterID then
        local log = Log()
        for i = #log, 1, -1 do
            if log[i].id == encounterID and log[i].name then return log[i].name end
        end
    end
    return bossName
end


function Encounter:Current()
    if active then return active.name, active.id end

    local log = Log()
    local last = log[#log]
    if last and last.endedAt and (Now() - last.endedAt) <= GRACE then
        return last.name, last.id
    end
    return nil
end



function Encounter:AtTime(when)
    if not when then return nil end

    local log = Log()
    for i = #log, 1, -1 do
        local entry = log[i]

        local from = (entry.startedAt or 0) - 60
        local to = (entry.endedAt or entry.startedAt or 0) + GRACE
        if when >= from and when <= to then
            return entry.name, entry.id
        end
    end
    return nil
end




function Encounter:DifficultyFor(bossName, encounterID)
    if bossName or encounterID then
        local log = Log()
        for i = #log, 1, -1 do
            if log[i].difficultyID
                and Encounter.SameBoss(log[i].name, log[i].id, bossName, encounterID) then
                return log[i].difficultyID
            end
        end
    end

    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType == "raid" or instanceType == "party" then
        return difficultyID
    end
    return nil
end



function Encounter:ForTradeableItem(secondsLeft)
    if not secondsLeft or secondsLeft <= 0 then

        return Encounter:Current()
    end
    local elapsed = TRADE_WINDOW - secondsLeft
    if elapsed < 0 then elapsed = 0 end
    return Encounter:AtTime(Now() - elapsed)
end







function Encounter:KnownBossNames()
    local names, seen = {}, {}
    local function add(name)
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            names[#names + 1] = name
        end
    end
    for _, entry in ipairs(Log()) do add(entry.name) end
    if addon.History and addon.History.EachEntry then
        addon.History.EachEntry(function(entry) add(entry.boss) end)
    end
    table.sort(names)
    return names
end



function Encounter:EncounterIDFor(name)
    if type(name) ~= "string" or name == "" then return nil end
    local log = Log()
    for i = #log, 1, -1 do
        if log[i].name == name and log[i].id then return log[i].id end
    end
    local found
    if addon.History and addon.History.EachEntry then
        addon.History.EachEntry(function(entry)
            if not found and entry.boss == name and entry.encounterID then
                found = entry.encounterID
            end
        end)
    end
    return found
end




function Encounter.MatchBossName(known, text)
    local Fold = addon.Locale.Fold
    text = (Fold(tostring(text or "")):gsub("^%s+", ""):gsub("%s+$", ""))
    if text == "" then return nil, {} end

    local exact, prefix, within, seen = nil, {}, {}, {}
    for _, name in ipairs(known or {}) do
        local lower = Fold(name)
        if not seen[lower] then
            seen[lower] = true
            if lower == text then
                exact = exact or name
            elseif lower:sub(1, #text) == text then
                prefix[#prefix + 1] = name
            elseif lower:find(text, 1, true) then
                within[#within + 1] = name
            end
        end
    end

    if exact then return exact end
    if #prefix == 1 then return prefix[1] end
    if #prefix > 1 then return nil, prefix end
    if #within == 1 then return within[1] end
    return nil, within
end









local TRACK_DIFFICULTY_BY_ID = {
    [972] = 17, [973] = 14, [974] = 15, [978] = 16,
}
local TRACK_DIFFICULTY = {
    veteran = 17, champion = 14, hero = 15, myth = 16,
}
function Encounter.DifficultyForTrack(trackString, trackStringID)
    local byID = TRACK_DIFFICULTY_BY_ID[tonumber(trackStringID) or false]
    if byID then return byID end
    if type(trackString) ~= "string" then return nil end
    return TRACK_DIFFICULTY[(trackString:lower():gsub("^%s+", ""):gsub("%s+$", ""))]
end


function Encounter:TrackForLink(itemLink)

    if addon.IsForever then return nil, nil end
    local upgrade = itemLink and C_Item.GetItemUpgradeInfo
        and C_Item.GetItemUpgradeInfo(itemLink)
    local track = upgrade and upgrade.trackString
    local trackID = upgrade and upgrade.trackStringID
    addon.Log:D("Encounter", "upgrade track", tostring(track), "id",
        tostring(trackID), tostring(itemLink))

    if type(track) ~= "string" or track == "" then return nil, nil end
    return Encounter.DifficultyForTrack(track, trackID), track
end




local EJ_STYPE_ITEM = 0
local SEARCH_TICK, SEARCH_TICKS = 0.1, 50
local searchQueue, searching = {}, false





local function ScanSearchResults(itemID)
    for i = 1, EJ_GetNumSearchResults() do
        local id, stype, difficultyID, instanceID, journalEncounterID = EJ_GetSearchResult(i)
        local lootInfo = stype == EJ_STYPE_ITEM and C_EncounterJournal
            and C_EncounterJournal.GetLootInfo and C_EncounterJournal.GetLootInfo(id)
        local resultItemID = lootInfo and lootInfo.itemID
        addon.Log:D("Encounter", "journal result", i, "id", tostring(id),
            "stype", tostring(stype), "itemID", tostring(resultItemID),
            "difficulty", tostring(difficultyID), "instance", tostring(instanceID),
            "encounter", tostring(journalEncounterID))
        if stype == EJ_STYPE_ITEM and (resultItemID == itemID or id == itemID) then
            local journalEncounter = journalEncounterID
                or (lootInfo and lootInfo.encounterID)
            if journalEncounter then
                local name, _, _, _, _, _, dungeonEncounterID =
                    EJ_GetEncounterInfo(journalEncounter)
                if type(name) == "string" and name ~= "" then
                    return name, journalEncounter, tonumber(dungeonEncounterID)
                end
            end
        end
    end
    return nil
end

local RunNextSearch
RunNextSearch = function()
    if searching or #searchQueue == 0 then return end
    local job = table.remove(searchQueue, 1)
    searching = true



    local done = false
    local function finish(boss, detail, encounterID)
        done = true
        if EJ_ClearSearch then pcall(EJ_ClearSearch) end
        searching = false
        addon.Log:D("Encounter", "journal search for", job.link, "->",
            tostring(boss), tostring(detail), "encounter", tostring(encounterID))
        local ok, err = pcall(job.callback, boss, detail, encounterID)
        if not ok then
            addon.Log:Bug("Encounter", ("journal lookup callback for %s failed: %s")
                :format(tostring(job.link), tostring(err)))
        end
        RunNextSearch()
    end



    local function poll(ticker, ticks)
        if EJ_IsSearchFinished() then
            ticker:Cancel()
            local boss, journalID, encounterID = ScanSearchResults(job.itemID)
            if boss then
                finish(boss, addon.Locale.Format(T["journal encounter %d"], journalID), encounterID)
            else
                finish(nil, addon.Locale.Format(T["%d result(s), none for item %d (search size %d)"],
                    EJ_GetNumSearchResults(), job.itemID, EJ_GetSearchSize()))
            end
        elseif ticks >= SEARCH_TICKS then
            ticker:Cancel()
            finish(nil, addon.Locale.Format(T["search did not finish in %.1fs (search size %d)"],
                SEARCH_TICK * SEARCH_TICKS, EJ_GetSearchSize()))
        end
    end

    local function fail(ticker, err)
        if ticker then ticker:Cancel() end


        if not done then
            finish(nil, addon.Locale.Format(T["journal search raised: %s"],
                tostring(err)))
        end
    end

    local ok, err = pcall(EJ_SetSearch, job.name)
    if not ok then
        fail(nil, err)
        return
    end
    local ticks = 0
    C_Timer.NewTicker(SEARCH_TICK, function(ticker)
        ticks = ticks + 1
        local pollOk, pollErr = pcall(poll, ticker, ticks)
        if not pollOk then fail(ticker, pollErr) end
    end, SEARCH_TICKS)
end

function Encounter:JournalBossForLink(itemLink, callback)

    if addon.IsForever then
        callback(nil, T["WoW: Forever has no Adventure Guide loot to search"])
        return
    end
    local itemID = addon.Storage and addon.Storage.ItemID(itemLink)
    local name = itemLink and (C_Item.GetItemInfo(itemLink) or itemLink:match("%[(.-)%]"))
    if not itemID or not name or not EJ_SetSearch then
        callback(nil, T["no item id or name to search for"])
        return
    end
    searchQueue[#searchQueue + 1] = {
        itemID = itemID, name = name, link = itemLink, callback = callback,
    }
    RunNextSearch()
end





function Encounter:Init()
    addon.db.encounterLog = addon.db.encounterLog or {}


    Log()

    local f = CreateFrame("Frame")
    f:RegisterEvent("ENCOUNTER_START")
    f:RegisterEvent("ENCOUNTER_END")
    f:SetScript("OnEvent", function(_, event, encounterID, encounterName,
            difficultyID, _, success)
        if event == "ENCOUNTER_START" then
            Encounter:OnStart(encounterID, encounterName, difficultyID)
        else
            Encounter:OnEnd(encounterID, encounterName, difficultyID, success)
        end
    end)


    if addon.IsForever then
        local corpses = CreateFrame("Frame")
        corpses:RegisterEvent("LOOT_READY")
        corpses:SetScript("OnEvent", function()
            local ok, err = pcall(OnLootReady)
            if not ok then addon.Log:Bug("Encounter", tostring(err)) end
        end)
    end

    addon.Log:I("Encounter", "ready", #addon.db.encounterLog, "logged")
end
