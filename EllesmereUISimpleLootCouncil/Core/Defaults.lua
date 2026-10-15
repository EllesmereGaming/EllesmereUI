if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text




addon.SCHEMA_VERSION = 9


local interface = GetBuildInfo and select(4, GetBuildInfo())
local forever = type(interface) == "number" and interface < 20000





addon.defaults = {
    schemaVersion = addon.SCHEMA_VERSION,



    debug = false,


    chatWarnings = true,


    logMaxEntries = 10000,




    lootMaster = nil,


    council = {},



    councilRanks = {},





    responses = {
        { id = "MAINSPEC", text = "Mainspec",  r = 0.20, g = 0.80, b = 0.20, sort = 1 },
        { id = "OFFSPEC",  text = "Offspec",   r = 1.00, g = 0.60, b = 0.10, sort = 2 },
        not forever and
            { id = "TRANSMOG", text = "Transmog",  r = 0.30, g = 0.75, b = 0.85, sort = 3 }
            or nil,
    },



    noteMaxLength = 64,



    whispers = {
        enabled = true,
    },




    awardReasons = {
        { id = "DISENCHANT", text = "Disenchant", log = true },
        { id = "BANK",       text = "Guild bank", log = true },
        { id = "FREE",       text = "Free",       log = false },
    },



    boeRoute = {},


    timer = {
        enabled = false,
        duration = 120,
    },


    vote = {
        selfVote = true,
        multiVote = true,
        hideVotes = false,
    },



    allowStartRequests = false,
    councilMayStartRuns = false,


    shareCouncilBags = true,


    itemStorage = {},



    owedByOthers = {},


    activeRun = {},


    runCopy = {},



    perfRuns = {},


    funnel = {


        guildGroupOnly = true,



        ignore = {},
    },




    raidPrompt = {
        silence = false,
        inGroups = false,


        neverLead = false,

        autoHandover = false,

        dropDelegationOnLead = false,
    },



    ignoredItems = {},


    suppressTradeWarnings = true,



    announce = {
        awards = true,
        trades = true,
        rolls = true,
    },


    encounterLog = {},


    attendance = { nights = {} },


    recordAttendance = true,


    history = {},
    recordHistory = true,

    shareHistory = true,


    historyPruneDays = 0,


    csvDelimiter = nil,




    historyFilter = {},



    historySnapshots = {},


    imported = {},


    importMaxDays = 365,



    showMoreInfo = true,


    teamShowAlts = true,


    sessionFrame = true,


    wishlistEnabled = true,
    wishlistSource = "wowutils",


    autopass = true,
    silentAutopass = false,




    autopassTransmog = true,



    masterAutoLoot = true,


    autoOpenQueue = true,

    autoAddBags = false,


    specs = {},


    raidTeam = {
        ranks = {},
    },


    mains = {},


    windows = {},


    mlCompact = false,


    voterCompact = false,


    windowAlpha = 1,


    pride = false,
}






addon.migrations = addon.Locale.Texts{
    {
        version = 2,
        name = "de-duplicate history and the item ledger",
        notify = T["Duplicate award history entries have been merged. They were caused by a bug that recorded every award twice."],
        func = function(db)


            local WINDOW = 3

            if type(db.history) == "table" then
                local seen, removed = {}, 0


                local ids = {}
                for id in pairs(db.history) do ids[#ids + 1] = id end
                table.sort(ids, function(a, b)
                    local ea = tonumber(db.history[a] and db.history[a].epoch) or 0
                    local eb = tonumber(db.history[b] and db.history[b].epoch) or 0
                    if ea ~= eb then return ea < eb end
                    return tostring(a) < tostring(b)
                end)

                for _, id in ipairs(ids) do
                    local entry = db.history[id]
                    if type(entry) == "table" then
                        local key = table.concat({
                            tostring(entry.link), tostring(entry.winner),
                            tostring(entry.owner), tostring(entry.responseText),
                        }, "\0")
                        local previous = seen[key]
                        local epoch = tonumber(entry.epoch) or 0
                        if previous and math.abs(epoch - previous) <= WINDOW then
                            db.history[id] = nil
                            removed = removed + 1
                        else
                            seen[key] = epoch
                        end
                    end
                end
                db.migrationRemovedHistory = removed
            end


            if type(db.itemStorage) == "table" then
                local seen, kept = {}, {}
                for _, entry in ipairs(db.itemStorage) do
                    local args = entry.args or {}
                    local key = table.concat({
                        tostring(entry.link), tostring(entry.category),
                        tostring(args.recipient), tostring(args.session),
                    }, "\0")
                    if not seen[key] then
                        seen[key] = true
                        kept[#kept + 1] = entry
                    end
                end
                db.itemStorage = kept
            end
        end,
    },
    {
        version = 3,
        name = "clear table-valued boss fields from history",
        func = function(db)



            local cleared = 0
            for _, store in ipairs({ db.history, db.imported }) do
                if type(store) == "table" then
                    for _, entry in pairs(store) do
                        if type(entry) == "table" and entry.boss ~= nil
                            and type(entry.boss) ~= "string" then
                            entry.boss = nil
                            cleared = cleared + 1
                        end
                    end
                end
            end
            db.migrationClearedBoss = cleared
        end,
    },
    {
        version = 4,
        name = "initialise active-run persistence",
        func = function(db)

            if db.activeRun ~= nil and type(db.activeRun) ~= "table" then
                db.activeRun = nil
            end
        end,
    },
    {
        version = 5,
        name = "keep award history by default",
        func = function(db)


            if db.historyPruneDays == 180 then db.historyPruneDays = 0 end
        end,
    },
    {
        version = 6,
        name = "keep a longer diagnostic log",
        func = function(db)

            if db.logMaxEntries == 2000 then db.logMaxEntries = 10000 end
        end,
    },
    {
        version = 7,
        name = "funnel with SLC; guild loot funnel guard off",
        notify = T["The group-loot funnel now runs whenever Simple Loot Council is active, so its switch is gone. The guild loot funnel guard is now off; switch it on in Settings to be asked before your loot is passed outside your guild."],
        func = function(db)

            if type(db.funnel) ~= "table" then return false end
            db.funnel.enabled = nil
            db.funnel.guildGroupOnly = false
        end,
    },
    {
        version = 8,
        name = "BoE route reason as text",
        func = function(db)

            local rule = db.boeRoute
            if type(rule) ~= "table" then return end
            local index = rule.reason
            rule.reason = nil
            if type(index) ~= "number" or rule.reasonText ~= nil then return end
            local entry = type(db.awardReasons) == "table" and db.awardReasons[index]
            if type(entry) ~= "table" or type(entry.text) ~= "string" then return end
            if entry.id == "BANK" or entry.text:lower() == "guild bank" then return end
            rule.reasonText = entry.text
        end,
    },
    {
        version = 9,
        name = "guild loot funnel guard on",
        notify = T["The loot funnel now runs in guild groups only by default: you are asked before your loot is passed outside your guild. Set \"Loot funnel in which groups?\" to All Groups in Settings if you would rather not be asked."],
        func = function(db)

            if type(db.funnel) ~= "table" or db.funnel.guildGroupOnly == true then return false end
            db.funnel.guildGroupOnly = true
        end,
    },
}







function addon.ApplyDefaults(db, src)
    for k, v in pairs(src) do
        if db[k] == nil then
            db[k] = (type(v) == "table") and CopyTable(v) or v
        elseif type(v) == "table" and #v == 0 and type(db[k]) == "table" then


            addon.ApplyDefaults(db[k], v)
        end
    end
    return db
end



function addon.RunMigrations(db)
    local notices = {}



    local from = db.schemaVersion
    if from == nil then
        db.schemaVersion = addon.SCHEMA_VERSION
        return notices
    end
    if from >= addon.SCHEMA_VERSION then
        return notices
    end

    for _, m in ipairs(addon.migrations) do
        if from < m.version then
            local ok, err = pcall(m.func, db)
            if ok then

                if m.notify and err ~= false then notices[#notices + 1] = m.notify end
            else
                notices[#notices + 1] =
                    addon.Locale.Format(T["Migration %q failed: %s"],
                        tostring(m.name), tostring(err))
            end
        end
    end

    db.schemaVersion = addon.SCHEMA_VERSION
    db.migratedFrom = from
    return notices
end
