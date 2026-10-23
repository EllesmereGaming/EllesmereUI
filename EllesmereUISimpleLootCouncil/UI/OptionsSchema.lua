if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local Schema = {}
UI.OptionsSchema = Schema

Schema.MAX_RESPONSES = 7
Schema.MAX_RESPONSE_LETTERS = 16

Schema.RANK_MAX_ROWS = 10

Schema.SESSION_KINDS = { run = true, award = true, item = true }


local LOCK_EVENTS = { "HandlingChanged", "SharedConfigChanged", "LootMasterChanged",
    "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" }
local RUN_EVENTS = { "SessionChanged", "RunStarted", "RunEnded", "RunRecovered" }






function Schema.LeaderLockReason()
    return addon.Locale.Format(
        T["Set by the group leader while SLC is active. Yours applies when you lead."])
end


local function LeaderLock(effective)
    return function()
        if not addon.Config:LeaderDictates() then return nil end
        return effective(), Schema.LeaderLockReason()
    end
end


local function OtherLootMaster()
    return IsInGroup() and addon.Loot.handling and not addon.PlayerIsMasterLooter() and true or false
end
local MASTER_EVENTS = { "PARTY_LEADER_CHANGED", "HandlingChanged", "LootMasterChanged" }



local function Setting(row)
    row.tooltip = row.help
    if row.disabled then
        local disabled = row.disabled
        row.disabledTooltip = function() return disabled() end

        row.rawTooltip = true
    end
    return row
end

local function SwitchRow(id, text, help, get, set, extra)
    local row = { id = id, type = "toggle", text = text, help = help,
        getValue = get, setValue = set }
    for k, v in pairs(extra or {}) do row[k] = v end
    return Setting(row)
end

local function Chat(prefix, text)
    local say = prefix == "error" and addon.Chat.Error or prefix == "warn" and addon.Chat.Warn or addon.Chat.Print
    say(text)
end

local function WishlistChanged()
    addon.Wishlist:Invalidate()
    addon.Callbacks:Invalidate("council")
    addon.Callbacks:Invalidate("voter")
end







local function NextResponseID()
    local used = {}
    for _, entry in ipairs(addon.db.responses) do
        if entry.id then used[entry.id] = true end
    end
    local n = 1
    while used["CUSTOM" .. n] do n = n + 1 end
    return "CUSTOM" .. n
end



local function DeleteRequirement()
    if addon.Session:IsRunning() then
        return addon.Locale.Format(T["Requires no loot run in progress."])
    end
    if #addon.db.responses <= 1 then
        return addon.Locale.Format(T["Requires at least one other response."])
    end
    return nil
end

local function Responses()
    return {
        id = "responses", custom = true, grows = true,
        max = Schema.MAX_RESPONSES, maxLetters = Schema.MAX_RESPONSE_LETTERS,
        refreshOn = RUN_EVENTS,

        nameLabel = T["Button %d"], addText = T["Add response"],
        list = function() return addon.db.responses end,
        entry = function(index) return addon.db.responses[index] end,

        add = function(r, g, b)
            local responses = addon.db.responses
            if #responses >= Schema.MAX_RESPONSES then return nil end
            local index = #responses + 1
            responses[index] = {
                id = NextResponseID(), text = T["New response"],
                r = r, g = g, b = b, sort = index,
            }
            addon.Council:RequestBroadcast()
            return index
        end,
        deleteRequirement = DeleteRequirement,
        confirmDelete = function()
            return { title = T["Delete response"],
                body = T["Would you like to delete this response button?"],
                accept = T["Delete"] }
        end,

        remove = function(index)
            local refused = DeleteRequirement()
            if refused then
                Chat("accent", addon.Locale.Format(T["not deleted. %s"], refused))
                return false
            end
            local responses = addon.db.responses
            if not responses[index] then return false end
            table.remove(responses, index)
            for i, entry in ipairs(responses) do entry.sort = i end
            addon.Council:RequestBroadcast()
            return true
        end,

        setName = function(index, text)
            local entry = addon.db.responses[index]
            text = text:trim()
            if not entry or text == "" then return false end
            entry.text = text
            addon.Council:RequestBroadcast()
            return true
        end,


        setColour = function(entry, r, g, b)
            entry.r, entry.g, entry.b = r, g, b
            addon.Council:RequestBroadcast()
        end,
    }
end



function Schema.CouncilStatusText(state, leader, good, warn)
    local name = leader and Ambiguate(leader, "short")
    if state == "leader" then
        return addon.Locale.Format(T["%sIn force|r - you lead this group."], good)
    elseif state == "solo" then
        return addon.Locale.Format(T["%sIn force|r - you are not in a group."], good)
    elseif not name then
        return addon.Locale.Format(T["%sNot in force|r - another player leads this group."], warn)
    elseif state == "follower" then
        return addon.Locale.Format(
            T["%sNot in force|r - %s leads this group, so their council is used."], warn, name)
    end
    return addon.Locale.Format(
        T["%sNot in force|r - %s leads this group, and no council has arrived from them yet."],
        warn, name)
end



function Schema.SuggestionRows(found, members, limit)
    local byGuid, byKey = {}, {}
    for _, member in ipairs(members or {}) do
        if member.guid then byGuid[member.guid] = true end
        local identity = member.fullName
        if not identity and member.identity and not addon.Player:IsGUID(member.identity) then
            identity = member.identity
        end
        local key = identity and addon.Player:NameKey(identity)
        if key then byKey[key] = true end
    end

    local rows = {}
    for _, entry in ipairs(found or {}) do
        local key = addon.Player:NameKey(entry.fullName or entry.name)
        if not (entry.guid and byGuid[entry.guid]) and not (key and byKey[key]) then
            rows[#rows + 1] = entry
            if #rows >= limit then break end
        end
    end
    return rows
end


function Schema.SuggestionText(entry)
    if addon.IsForever then return entry.name end
    return entry.fullName or entry.name
end



function Schema.QualifiedName(fullName, colourOf)
    fullName = addon.Player:CanonicalName(fullName) or fullName
    local character, realm = fullName:match("^([^-]+)(%-.*)$")
    character = character or fullName

    local record = addon.Player:Get(fullName)
    local colour = record and record.classFile and colourOf(record.classFile)


    if not colour and addon.History and addon.History.ClassesFor then
        for _, historicalClass in ipairs(addon.History:ClassesFor(fullName) or {}) do
            colour = colourOf(historicalClass:upper())
            if colour then break end
        end
    end
    return character, realm or "", colour
end


local function CouncilEntries()
    local entries = {}
    for _, member in ipairs(addon.Council:GetConfigured()) do
        member.kind = "player"
        entries[#entries + 1] = member
    end

    local covered = {}
    for _, rankName in pairs(addon.Council:RankMembers()) do
        covered[rankName] = (covered[rankName] or 0) + 1
    end
    for _, rank in ipairs(addon.Council:GetConfiguredRanks()) do
        entries[#entries + 1] = {
            kind = "rank", name = rank.name, known = rank.known,
            present = covered[rank.name] or 0,
        }
    end
    return entries
end



local function DescribeCouncilEntry(entry, present)

    if entry.kind == "rank" then
        local known = entry.known
        return T["Council Rank"], {
            { text = entry.name },
            { text = known and T["Guild rank"] or T["Not a rank in this guild"],
                tone = known and "good" or "accent" },
            { text = known
                and T["Everyone in your group holding this guild rank can vote. Nobody is added to the list, so a promotion grants a vote and a demotion takes it away with no edit here."]
                or T["Your guild has no rank called this - it was renamed or removed. It confers nothing until a rank of this name exists again."],
                wrap = true },
            { text = T["In your group now"], value = tostring(entry.present or 0) },
        }
    end
    local pending = entry.pending
    return T["Council Member"], {
        { text = entry.fullName or entry.identity or "?" },
        { text = pending and T["Not confirmed"] or T["Confirmed"], tone = pending and "accent" or "good" },
        { text = pending
            and T["Stored by name, so it is matched as typed. The next time this player is in your group it becomes a permanent id and survives a rename or a realm transfer."]
            or T["Seen in your group and stored by player id, so a rename or a realm transfer will not lose them."],
            wrap = true },

        { text = T["In your group now"], value = present and T["yes"] or T["no"] },
    }
end

local function Council()
    return {
        id = "council", custom = true, column = 1,
        refreshOn = { "CouncilChanged", "RaidTeamChanged", "GROUP_ROSTER_UPDATE",
            "PARTY_LEADER_CHANGED", "HandlingChanged", "LootMasterChanged" },


        locked = OtherLootMaster,
        lockedText = T["Your loot council may only be edited while you are Loot Master."],

        hint = function()
            return addon.IsForever and T["A character name, then Enter."]
                or T["Name-Realm, then Enter. Full realm names and compact forms both work."]
        end,
        addText = function() return T["Add"] end,
        emptyText = function() return T["Nobody on the council yet."] end,
        entries = CouncilEntries,

        authorship = function() return addon.Council:Authorship() end,
        statusText = Schema.CouncilStatusText,

        suggest = function(text, limit)
            if not (addon.RaidTeam and addon.RaidTeam.Suggest) then return {} end
            return Schema.SuggestionRows(addon.RaidTeam:Suggest(text, limit),
                addon.Council:GetConfigured(), limit)
        end,
        suggestionText = Schema.SuggestionText,

        present = function(entry) return addon.GetCandidates()[entry.fullName] and true or false end,
        describe = DescribeCouncilEntry,

        add = function(name)
            local ok, err = addon.Council:Add(name)
            if ok then
                addon.Council:RequestBroadcast()
                return true
            end
            Chat("warn", tostring(err or T["could not add"]))
            return false
        end,

        remove = function(entry)
            if entry.kind == "rank" then
                addon.Council:SetRankEmpowered(entry.name, false)
            else
                addon.Council:Remove(entry.identity or entry.fullName or entry.guid or "?")
            end
            addon.Council:RequestBroadcast()
        end,
    }
end

local function CouncilRanks()
    return {
        id = "councilRanks", custom = true, column = 2, heading = T["Guild Rank"],
        maxRows = Schema.RANK_MAX_ROWS,
        refreshOn = { "CouncilChanged", "RaidTeamChanged" },
        hints = function()
            return {
                T["Selected ranks join your council automatically. Selections are per guild. If a rank is renamed, select its new name."],
            }
        end,
        ranks = function() return addon.RaidTeam and addon.RaidTeam:GetRanks() or {} end,
        isEmpowered = function(name) return addon.Council:IsRankEmpowered(name) end,

        setEmpowered = function(name, value)
            addon.Council:SetRankEmpowered(name, value)
            addon.Council:RequestBroadcast()
        end,

        empty = function()
            if not (addon.RaidTeam and addon.RaidTeam:GetGuildName()) then
                return T["You are not in a guild, so there are no ranks to choose from."]
            end
            local ranks = addon.RaidTeam:GetRanks() or {}
            if #ranks == 0 then
                return T["No ranks could be read yet - reopen this window in a moment."]
            end
            return nil
        end,
    }
end

local function CurrentMain()
    local character = addon.Player:GetFullName("player")
    if not character then return nil end
    return addon.Player:Main(character)
end

local function Alts()
    return {
        id = "alts", custom = true, grows = true,
        refreshOn = { "MainsChanged", "RaidTeamChanged" },
        prefix = T["Alts"],
        designateText = T["Designate another main"],
        addText = T["Add alts"],
        addButton = T["Add"],
        hint = function()
            return addon.IsForever and T["A character name, then Enter."] or T["Name-Realm, then enter."]
        end,
        unknownText = T["unknown"],
        main = CurrentMain,
        nameParts = Schema.QualifiedName,

        alts = function(main)
            local alts = main and addon.Player:Alts(main) or {}
            table.sort(alts, function(a, b)
                return addon.Locale.Fold(a) < addon.Locale.Fold(b)
            end)
            return alts
        end,

        addAlt = function(alt)
            alt = alt:trim()
            if alt == "" then return nil end
            local main = CurrentMain()
            if not main then
                Chat("warn", T["could not identify this character."])
                return nil
            end
            local ok, reason = addon.Player:SetMain(alt, main)
            if not ok then Chat("warn", tostring(reason or T["could not add alt"])) end
            return ok and true or false
        end,
        designateMain = function(main)
            main = main:trim()
            if main == "" then return nil end
            local character = addon.Player:GetFullName("player")
            if not character then
                Chat("warn", T["could not identify this character."])
                return nil
            end
            local ok, reason = addon.Player:SetMain(character, main)
            if not ok then Chat("warn", tostring(reason or T["could not designate main"])) end
            return ok and true or false
        end,
        confirmRemove = function()
            return { title = T["Remove alt?"],
                body = T["Do you want to remove this character as an alt?"],
                accept = T["Remove"] }
        end,
        removeAlt = function(alt) addon.Player:ClearMain(alt) end,

        showAlts = SwitchRow("teamShowAlts", T["Show alts in Raid Team loot"], nil,
            function() return addon.db.teamShowAlts end,
            function(v)
                addon.db.teamShowAlts = v
                addon.Callbacks:Fire("TeamShowAltsChanged")
            end),
    }
end






local function ActiveReason()
    if not IsInRaid() then
        return addon.Locale.Format(T["Requires you to be in a raid."])
    end
    if not addon.PlayerIsMasterLooter() then
        return addon.Locale.Format(T["Requires you to be the Loot Master."])
    end
end



local function Declined()
    return IsInGroup() and not addon.PlayerIsMasterLooter()
        and addon.Loot.handling and addon.Loot.funnelArmed
        and addon.Loot:GetDecision() == false
end



local function OpensCouncil()
    return addon.PlayerIsMasterLooter()
        or addon.Council:Contains(addon.Player:GetFullName("player"))
end

local function InSession()
    return addon.Session:IsRunning() and not addon.Session:HasEnded() and not addon.Session:Settled()
end

local function StatusTags()
    return {
        id = "statusTags", custom = true,
        refreshOn = { "HandlingChanged", "LootMasterChanged", "SessionChanged",
            "RunStarted", "RunEnded", "RunRecovered" },

        heading = T["Status"],
        activeText = T["SLC ACTIVE"],
        liveText = T["LIVE"],
        activeReason = ActiveReason,
        declined = Declined,
        opensCouncil = OpensCouncil,
        live = InSession,

        activeShown = function()
            return Declined() or (addon.Loot and addon.Loot.handling) and true or false
        end,

        activeTone = function()
            if Declined() then return "warn" end
            return "accent"
        end,

        activeTooltip = function()
            if Declined() then
                return T["SLC ACTIVE"], "warn", {
                    T["You declined to take part in this SLC group, so your group-loot funnel is off."],
                    T["Left click to take part"],
                }
            end
            local on = addon.Loot.handling
            local lines = {}
            if IsInGroup() and not addon.PlayerIsMasterLooter() then
                lines[1] = T["Only the Loot Master can change the active state of SLC"]
            else
                lines[1] = on and T["SLC is currently active"] or T["SLC is currently inactive"]

                lines[2] = ActiveReason()
            end
            return on and T["SLC ACTIVE"] or T["Inactive"], on and "accent" or "textMuted", lines
        end,
        liveTooltip = function()
            if addon.PlayerIsMasterLooter() then
                return T["Live"], "good", {
                    T["Left click to open council voting frame"],
                    T["Right click to end the current loot session"],
                }
            elseif OpensCouncil() then

                return T["Live"], "good", { T["Left click to open the council voting frame"] }
            end
            return T["Live"], "good", { T["Left click to open the loot response frame"] }
        end,

        clickActive = function()
            if Declined() then
                addon.UI.RaidPrompt:AskToEnableFunnel()
                return true
            end
            if ActiveReason() then return false end
            if addon.Loot.handling then
                addon.UI.RaidPrompt:AskToDeactivate()
            else
                addon.UI.RaidPrompt:AskToActivate()
            end
            return true
        end,

        clickLive = function(button)
            if not addon.Session:IsRunning() then return false end
            if button == "LeftButton" then
                if OpensCouncil() then
                    addon.UI.MLFrame:Toggle()
                elseif not addon.UI.VoterFrame:Toggle() then
                    Chat("accent", T["nothing in this run is waiting for your answer."])
                end
            elseif button == "RightButton" and addon.PlayerIsMasterLooter() then
                addon.UI.MLFrame:ConfirmEndRun()
            end
            return true
        end,
    }
end

local function LootMaster()
    return {
        id = "lootMaster", custom = true,
        refreshOn = { "LootMasterChanged", "HandlingChanged" },
        heading = T["LOOT MASTER"],
        activeText = T["SLC ACTIVE"],
        active = function() return addon.Loot.handling == true end,
        canDeactivate = function()
            return addon.Loot.handling == true and addon.PlayerIsMasterLooter() and true or false
        end,
        deactivate = function() addon.UI.RaidPrompt:Deactivate() end,
        deactivateTip = T["Click to turn SLC off for this raid."],

        line = T["Loot Master: %s, %s"],
        command = "/slc lootmaster",
        name = function() return tostring(addon.GetMasterLooter() or T["unknown"]) end,
        fullName = function() return addon.GetMasterLooter() end,
        unknown = T["unknown"],
        role = function()
            return addon.IsLootDelegated() and T["delegated for this raid"] or T["group leader"]
        end,
    }
end




local function CouncilInForceEntries(name, rank)
    local active = addon.Council:GetActive()
    local byRank = addon.Council:GetActiveByRank()
    local rankDetailsKnown = addon.Council:HasActiveRankDetails()
    local master = addon.GetMasterLooter()
    local names, membersByRank, entries = {}, {}, {}
    local voters = 0
    for fullName in pairs(active) do
        voters = voters + 1
        local rankName = byRank[fullName]
        if rankDetailsKnown and type(rankName) == "string" and fullName ~= master then
            membersByRank[rankName] = membersByRank[rankName] or {}
            table.insert(membersByRank[rankName], fullName)
        else
            names[#names + 1] = fullName
        end
    end
    table.sort(names, function(a, b)
        if a == master then return b ~= master end
        if b == master then return false end
        return a < b
    end)
    for _, fullName in ipairs(names) do
        entries[#entries + 1] = { text = name(fullName), master = fullName == master or nil }
    end
    for _, rankName in ipairs(addon.Council:GetActiveRanks()) do
        local members = membersByRank[rankName]
        if members or not rankDetailsKnown then
            local tooltip = {}
            if members then
                table.sort(members)
                for _, fullName in ipairs(members) do
                    tooltip[#tooltip + 1] = name(fullName)
                end
            else
                tooltip[1] = T["Membership by rank is unavailable."]
            end
            entries[#entries + 1] = {
                text = rank(rankName), rank = true,
                count = members and tostring(#members) or "?",
                tooltip = tooltip,
            }
        end
    end
    return entries, voters
end

local function CouncilInForce()
    return {
        id = "councilInForce", custom = true,
        refreshOn = { "CouncilChanged" },
        heading = T["COUNCIL IN FORCE"],
        line = T["Council in force: %s"],
        entries = CouncilInForceEntries,
        emptyText = T["Nobody yet"],
        othersEmpty = T["No other council members."],
    }
end


local function MainButtons()
    local Live = InSession
    return {
        id = "mainButtons", custom = true,
        refreshOn = { "LootMasterChanged", "CouncilChanged", "SessionChanged", "RunStarted", "RunEnded",
            "RunRecovered" },
        live = Live,
        openText = T["Open Loot"],
        openDesc = function()
            if OpensCouncil() then
                return Live() and T["Session running - open the council window."]
                    or T["Open the council window."]
            end
            return Live() and T["Session running - answer for your loot."]
                or T["No loot session running."]
        end,

        openLoot = function()
            if OpensCouncil() then
                addon.UI.MLFrame:Open()
                return true
            end
            if addon.UI.VoterFrame:Open() then return true end
            Chat("accent", Live() and T["nothing in this run is waiting for your answer."]
                or T["no loot session is running."])
            return false
        end,
        historyText = T["Loot History"],
        historyDesc = T["Every award, and the loot each raider has had."],
        openHistory = function() addon.UI.HistoryFrame:Open() end,
    }
end





local sections, chrome, actions, byId

local function Build()
    local db = function() return addon.db end

    sections = {
        { id = "lootHandling", title = T["Loot handling"], rows = {
            SwitchRow("useSLC", T["Use SLC in this raid"],
                T["As the Loot Master, turns Simple Loot Council on or off for this raid. Anyone else takes part in it: this addon passes your group-loot rolls for the council to distribute."],
                function()
                    if addon.PlayerIsMasterLooter() then return addon.Loot.handling and true or false end
                    return addon.Loot.handling and addon.Loot:GetDecision() == true or false
                end,
                function(v)
                    if addon.PlayerIsMasterLooter() then
                        if v then addon.UI.RaidPrompt:Activate() else addon.UI.RaidPrompt:Deactivate() end
                    else
                        addon.UI.RaidPrompt:SetTakingPart(v)
                    end
                end,
                { refreshOn = { "HandlingChanged", "LootMasterChanged", "GROUP_ROSTER_UPDATE" },
                    disabled = function()
                        if not IsInRaid() then
                            return addon.Locale.Format(T["Requires you to be in a raid."])
                        end
                        if not addon.PlayerIsMasterLooter() and not addon.Loot.handling then
                            return addon.Locale.Format(T["Requires the Loot Master to use SLC for this raid."])
                        end
                    end }),


            Setting({ id = "guildGroupOnly", type = "dropdown", danger = true,
                text = T["Loot funnel in which groups?"],
                help = T["When do you want to auto-pass on boss loot?"],
                values = { all = T["All Groups"], guild = T["Guild Groups"], never = T["Never"] },
                order = { "all", "guild", "never" },
                getValue = function()
                    if db().funnel.never then return "never" end
                    return db().funnel.guildGroupOnly and "guild" or "all"
                end,
                setValue = function(value)
                    local funnel = db().funnel
                    funnel.never = value == "never"
                    if value ~= "never" then funnel.guildGroupOnly = value == "guild" end

                    if value == "guild" then addon.Loot:KeepGuard() end
                    if addon.UI.RaidPrompt then addon.UI.RaidPrompt:Evaluate() end
                end }),


            SwitchRow("masterAutoLoot", T["Auto-loot to bags as Master Looter"],
                T["As the group's Master Looter, a boss's whole corpse goes to your bags. In a raid, so do trash items at the loot threshold."],
                function() return db().masterAutoLoot end,
                function(v) db().masterAutoLoot = v end,
                { hidden = function() return not addon.Loot.MasterLootAvailable() end }),

            SwitchRow("autoJoin", T["Automatically join SLC sessions?"],
                T["Skip the question about taking part and join as soon as the Loot Master starts using Simple Loot Council. You are still told in chat. Never applies while you are the Loot Master."],
                function() return db().raidPrompt.silence end,
                function(v)
                    db().raidPrompt.silence = v
                    addon.UI.RaidPrompt:SyncSilence()
                    if addon.UI.RaidPrompt and addon.UI.RaidPrompt.Evaluate then addon.UI.RaidPrompt:Evaluate() end
                end),
        } },

        { id = "master", title = T["Loot Master"],
            locked = OtherLootMaster, refreshOn = MASTER_EVENTS,
            lockedText = T["Your Loot Master settings may only be edited while you are Loot Master."],
            rows = {
            SwitchRow("neverLead", T["Never prompt to lead SLC groups?"],
                T["Never ask to run an SLC group when you are group leader"],
                function() return db().raidPrompt.neverLead end,
                function(v)
                    db().raidPrompt.neverLead = v
                    if addon.UI.RaidPrompt then addon.UI.RaidPrompt:Evaluate() end
                end),

            SwitchRow("autoHandover", T["Keep SLC active when you are passed lead?"],
                T["When lead or Loot Master passes to you in a group already using Simple Loot Council, carry on without asking. You are still told in chat. A group not using it asks as normal."],
                function() return db().raidPrompt.autoHandover end,
                function(v)
                    db().raidPrompt.autoHandover = v
                    if v and addon.UI.RaidPrompt then addon.UI.RaidPrompt:Evaluate() end
                end),

            SwitchRow("dropDelegationOnLead", T["Drop prior Loot Master delegation when passed lead"],
                T["Become the Loot Master yourself when made group leader. Off: the previous leader's delegate keeps loot until you run /slc lootmaster clear."],
                function() return db().raidPrompt.dropDelegationOnLead end,
                function(v) db().raidPrompt.dropDelegationOnLead = v end),

            Setting({ id = "announce", type = "checks", text = T["Chat Announcements"],
                help = T["What you post in raid chat as the Loot Master."],
                items = {
                    { key = "awards", label = T["Loot awards"],
                        tooltip = T["The Loot Master posts one line when an award is made, changed or withdrawn."] },
                    { key = "trades", label = T["Loot trades"],
                        tooltip = T["Posts when the awarded item is physically handed over."] },
                    { key = "rolls", label = T["Roll requests"],
                        tooltip = T["Posts when the council asks the whole group to roll. This is the only way a raider whose addon is not working can take part: their popup never opens, so the line in chat is the request."] },
                },
                getValue = function(key) return db().announce[key] and true or false end,
                setValue = function(key, v) db().announce[key] = v and true or false end }),

            Setting({ id = "sessionLength", type = "slider", text = T["Session Length (seconds)"],
                help = T["How long the countdown on a loot session's items runs. 0 = no timer. The countdown is display only: running out never closes a session or rejects a response."],
                min = 0, max = addon.Config.SESSION_LENGTH_MAX, step = addon.Config.SESSION_LENGTH_STEP,
                valueSnap = addon.Config.SnapSessionLength,
                getValue = function() return addon.Config:SessionLength() end,
                setValue = function(value)
                    local seconds = addon.Config.SnapSessionLength(value)
                    db().timer.enabled = seconds > 0
                    if seconds > 0 then db().timer.duration = seconds end
                end }),

            SwitchRow("autoStart", T["Automatically start session on boss kill"],
                T["When a boss dies, a loot session starts with its drops. Off: start sessions yourself from the Loot queue tab."],
                function() return db().autoStart ~= false end,
                function(v)
                    db().autoStart = v and true or false
                    if addon.AutoStart then addon.AutoStart:Refresh() end
                end),
        } },

        { id = "session", title = T["Session"], rows = {
            SwitchRow("autopass", T["Auto-pass on unusable items in SLC sessions"],
                T["Acts only on definite class or armour restrictions."],
                function() return db().autopass end,
                function(v) db().autopass = v end),

            SwitchRow("autopassTransmog", T["Don't auto-pass on transmog"],
                T["Prevents auto-pass when this source would teach you a new appearance, whatever its armour type."],
                function() return db().autopassTransmog end,
                function(v) db().autopassTransmog = v end,
                { hidden = function() return addon.IsForever end }),
            SwitchRow("whispers", T["Allow whispered loot responses"],
                T["Allow loot responses to be sent to you via whisper during a session."],
                function() return db().whispers.enabled end,
                function(v) db().whispers.enabled = v end),
            SwitchRow("responseTab", T["Add loot response frame as a tab in Loot Council frame?"],
                T["When you are the Loot Master or on the loot council, your loot response is a tab in the Loot Council window. Off: it keeps its own window."],
                function() return db().responseTab ~= false end,
                function(v)
                    db().responseTab = v and true or false
                    addon.Callbacks:Invalidate("voter")
                    addon.Callbacks:Invalidate("council")
                end),
            Setting({ id = "windowOpacity", type = "slider", text = T["Window Opacity"],
                help = T["How see-through every Simple Loot Council window is."],
                min = math.floor(addon.Style.WINDOW_ALPHA_MIN * 100 + 0.5), max = 100, step = 5,
                getValue = function() return math.floor(addon.Style.WindowAlpha() * 100 + 0.5) end,
                setValue = function(value) addon.Style.SetWindowAlpha(value / 100) end }),
        } },

        { id = "council", title = T["Loot council"], rows = { Council(), CouncilRanks() } },

        { id = "voting", title = T["Voting"], rows = {
            Setting({ id = "councilMay", type = "checks", text = T["Council Members May Vote For:"],
                help = T["How council members may vote."],
                items = {
                    { key = "selfVote", label = T["Themselves"],
                        tooltip = T["Off: a member cannot vote on their own row."] },
                    { key = "multiVote", label = T["Multiple Candidates"],
                        tooltip = T["Off: one candidate per item, per member."] },
                },
                getValue = function(key) return db().vote[key] and true or false end,
                setValue = function(key, v)
                    db().vote[key] = v and true or false
                    addon.Council:RequestBroadcast()
                end,
                locked = LeaderLock(function() return true end),
                lockedValue = function(key) return addon.Config:Vote()[key] and true or false end,
                refreshOn = LOCK_EVENTS }),
            SwitchRow("hideVotes", T["Hide vote counts until you vote"],
                T["Display guard only - every client still holds the voter list."],
                function() return db().vote.hideVotes end,
                function(v)
                    db().vote.hideVotes = v
                    addon.Council:RequestBroadcast()
                end,
                { locked = LeaderLock(function() return addon.Config:Vote().hideVotes end),
                    refreshOn = LOCK_EVENTS }),

            SwitchRow("shareCouncilBags", T["View loot in council members' bags"],
                T["Lists each council member's tradeable loot under their name, after the Loot Master's, in the Loot Queue bags panel. Queue it like your own."],
                function() return db().shareCouncilBags end,
                function(v)
                    db().shareCouncilBags = v
                    addon.Council:RequestBroadcast()
                    addon.Callbacks:Fire("BagShareChanged")
                    if v then addon.BagShare:Request() end
                end,
                { locked = LeaderLock(function() return addon.Config:CouncilBagsShared() end),
                    refreshOn = LOCK_EVENTS }),
        } },

        { id = "responses", title = T["Response buttons"], rows = { Responses() } },

        { id = "history", title = T["Data & history"], rows = {
            SwitchRow("recordHistory", T["Record award history"],
                T["Keeps a local award log and applies the configured retention period."],
                function() return db().recordHistory end,
                function(v)
                    db().recordHistory = v

                    addon.Callbacks:Fire("HistoryChanged", "setting")
                end),
            SwitchRow("shareHistory", T["Share history with the group"],
                T["Broadcasts awards so each raider keeps an auditable copy."],
                function() return db().shareHistory end,
                function(v) db().shareHistory = v end),
            SwitchRow("recordAttendance", T["Record group attendance"],
                T["While you are running loot, records who was in the group at the end of every pull and shares it with the raid. Receiving and applying attendance from someone else running loot is unaffected by this."],
                function() return db().recordAttendance end,
                function(v)
                    db().recordAttendance = v
                    addon.Attendance:SetEnabled(v)
                end),
            Setting({ id = "historyPruneDays", type = "input", numeric = true, inputWidth = 78,
                text = T["Keep award history for (days, 0 = always)"],
                help = T["Older entries are removed at login. Imported history is not affected. Bonus rolls are always removed after 90 days."],
                getValue = function() return tostring(db().historyPruneDays or 0) end,
                setValue = function(text)
                    local value = tonumber(text) or db().historyPruneDays or 0

                    db().historyPruneDays = math.max(0, math.min(36500, math.floor(value)))
                end }),

            SwitchRow("wishlistEnabled", T["Use imported Wishlist and Sim data?"],
                T["Fills the council's Wishlist and Sim columns from the addon chosen below."],
                function() return db().wishlistEnabled ~= false end,
                function(v)
                    db().wishlistEnabled = v
                    WishlistChanged()
                end,
                { hidden = function() return addon.IsForever end }),
            Setting({ id = "wishlistSource", type = "dropdown",
                text = T["Wishlist and Sim source"],
                help = T["The addon whose imported wishlists and sims the council reads."],
                values = { wowutils = "WowUtils", gow = "Guilds of WoW", wowaudit = "wowaudit" },
                order = { "wowutils", "gow", "wowaudit" },
                hidden = function() return addon.IsForever end,
                dependsOn = "wishlistEnabled",
                disabled = function()
                    if db().wishlistEnabled ~= false then return nil end
                    return addon.Locale.Format(T["Requires imported Wishlist and Sim data to be in use."])
                end,
                getValue = function() return addon.Wishlist:Source() end,
                setValue = function(value)
                    db().wishlistSource = value
                    WishlistChanged()
                end }),
        } },

        { id = "diagnostics", title = T["Diagnostics"], rows = {
            SwitchRow("chatWarnings", T["Show warnings and errors in chat"],
                T["Each distinct one once. Off: they are still recorded in /slc log. Log to chat shows everything either way."],
                function() return db().chatWarnings ~= false end,
                function(v) db().chatWarnings = v addon.Log:SetChatWarnings(v) end),
            SwitchRow("debug", T["Log to chat"],
                T["Echoes the diagnostic log while reproducing a problem."],
                function() return db().debug end,
                function(v) db().debug = v addon.Log:SetEcho(v) end),
            Setting({ id = "logDetail", type = "dropdown",
                text = T["Detail level of logging"],
                help = T["Quiet records warnings and errors; Normal adds main events; Verbose records everything."],
                values = { quiet = T["Quiet"], normal = T["Normal"], verbose = T["Verbose"] },
                order = { "quiet", "normal", "verbose" },
                getValue = function() return addon.Log:GetDetail() end,
                setValue = function(value) db().logDetail = addon.Log:SetDetail(value) end }),
        } },

        { id = "alts", title = T["Alts"], rows = { Alts() } },
    }

    chrome = { StatusTags(), LootMaster(), CouncilInForce(), MainButtons() }


    actions = {
        { id = "sendConfig", text = T["Send config"], primary = true,

            onClick = function() addon.UI.ConfigShareFrame:ToggleSend() end },
        { id = "attendance", text = T["Attendance"],
            onClick = function() addon.UI.AttendanceFrame:Toggle() end },
        { id = "versions", text = T["Raid versions"],
            onClick = function() addon.UI.VersionFrame:Toggle() end },
        { id = "csv", text = T["Export CSV"],
            onClick = function() addon.ShowHistoryCSV() end },
    }

    byId = {}
    for _, section in ipairs(sections) do
        for _, row in ipairs(section.rows) do byId[row.id] = row end
    end
    for _, row in ipairs(chrome) do byId[row.id] = row end
end


function Schema.Sections()
    if not sections then Build() end
    return sections
end


function Schema.Chrome()
    if not sections then Build() end
    return chrome
end

function Schema.Actions()
    if not sections then Build() end
    return actions
end


function Schema.Row(id)
    if not sections then Build() end
    return byId[id]
end


function Schema.Events()
    if not sections then Build() end
    local seen, events = {}, {}
    local function collect(row)
        for _, event in ipairs(row.refreshOn or {}) do
            if not seen[event] then
                seen[event] = true
                events[#events + 1] = event
            end
        end
    end
    for _, section in ipairs(sections) do
        collect(section)
        for _, row in ipairs(section.rows) do collect(row) end
    end
    for _, row in ipairs(chrome) do collect(row) end
    table.sort(events)
    return events
end
