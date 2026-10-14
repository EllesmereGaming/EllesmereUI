if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 



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

Schema.SESSION_KINDS = { run = true }


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
    print(addon.Log.CHAT_PREFIX[prefix] .. text)
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

        hints = function()
            local hints = {
                T["Enter to save. Up to seven, plus Pass; names up to 16 letters."],
                T["The right-hand box is the whisper keys for that button - extra words a raider may send you, comma separated. The label always works."],
            }

            if addon.Config:HasShared() then
                hints[#hints + 1] = T["The Loot Master's buttons are in use for this raid. These are yours, and apply when you run loot."]
            end
            return hints
        end,

        nameLabel = T["Button %d"], keysLabel = T["Whisper keys"], addText = T["Add response"],
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
            addon.Council:Broadcast()
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
            addon.Council:Broadcast()
            return true
        end,

        setName = function(index, text)
            local entry = addon.db.responses[index]
            text = text:trim()
            if not entry or text == "" then return false end
            entry.text = text
            addon.Council:Broadcast()
            return true
        end,

        setKeys = function(index, text)
            local entry = addon.db.responses[index]
            if not entry then return end
            text = text:trim()
            entry.whisper = text ~= "" and text or nil
            addon.Council:Broadcast()
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


    if not colour and addon.History and addon.History.GetForWinner then
        for _, entry in ipairs(addon.History:GetForWinner(fullName)) do
            local historicalClass = entry and entry.class
            if type(historicalClass) == "string" then
                colour = colourOf(historicalClass:upper())
                if colour then break end
            end
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
            "PARTY_LEADER_CHANGED" },

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
                addon.Council:Broadcast()
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
            addon.Council:Broadcast()
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
                T["Selected ranks join your council automatically. Members are included by rank, without adding their names."],
                T["Saved per guild. If a rank is renamed, select its new name."],
            }
        end,
        ranks = function() return addon.RaidTeam and addon.RaidTeam:GetRanks() or {} end,
        isEmpowered = function(name) return addon.Council:IsRankEmpowered(name) end,

        setEmpowered = function(name, value)
            addon.Council:SetRankEmpowered(name, value)
            addon.Council:Broadcast()
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

local function BoEReason()
    return {
        id = "boeReason", custom = true,
        text = T["...and for that reason"],
        buttonText = function()
            local rule = addon.db.boeRoute
            local entry = rule.reason and addon.db.awardReasons
                and addon.db.awardReasons[rule.reason]
            return entry and entry.text or T["Choose a reason"]
        end,
        menuTitle = T["Award reason"],

        current = function() return addon.db.boeRoute.reason end,
        placeholder = T["Choose a reason"],

        offText = T["Off - set both a recipient and a reason to enable one-click BoE awards."],
        emptyText = T["(none configured)"],
        reasons = function() return addon.db.awardReasons or {} end,
        choose = function(index) addon.db.boeRoute.reason = index end,

        status = function()
            local rule = addon.db.boeRoute
            local _, requirement = addon.BoERoute.RouteFor(nil, rule, nil, nil)
            if requirement then return requirement, "accent" end
            if not rule.winner and not rule.reason then
                return T["Off - set both a recipient and a reason to enable one-click BoE awards."]
            end
            local reasonEntry = addon.db.awardReasons and addon.db.awardReasons[rule.reason]
            return addon.Locale.Format(T["Live: routes Bind-on-Equip items to %s (%s)."],
                Ambiguate(rule.winner, "short"), reasonEntry and reasonEntry.text or "?"), "good"
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
    if not IsInGroup() then
        return addon.Locale.Format(T["Requires you to be in a group."])
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

local function StatusTags()
    return {
        id = "statusTags", custom = true,
        refreshOn = { "HandlingChanged", "LootMasterChanged", "SessionChanged",
            "RunStarted", "RunEnded", "RunRecovered" },

        heading = T["Status"],
        activeText = T["Active"],
        liveText = T["LIVE"],
        activeReason = ActiveReason,
        declined = Declined,
        opensCouncil = OpensCouncil,
        live = function() return addon.Session:IsRunning() and not addon.Session:HasEnded() end,

        activeTone = function()
            if Declined() then return "warn" end
            return addon.Loot and addon.Loot.handling and "accent" or "textFaint"
        end,

        activeTooltip = function()
            if Declined() then
                return T["Active"], "warn", {
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
            return on and T["Active"] or T["Inactive"], on and "accent" or "textMuted", lines
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
        refreshOn = { "LootMasterChanged" },
        heading = T["LOOT MASTER"],

        line = T["Loot Master: %s, %s"],
        command = "/slc lootmaster",
        name = function() return tostring(addon.GetMasterLooter() or T["unknown"]) end,
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
        entries[#entries + 1] = { text = name(fullName) }
    end
    for _, rankName in ipairs(addon.Council:GetActiveRanks()) do
        local members = membersByRank[rankName] or {}
        table.sort(members)
        local tooltip = {}
        for _, fullName in ipairs(members) do
            tooltip[#tooltip + 1] = name(fullName)
        end
        if #tooltip == 0 then
            tooltip[1] = rankDetailsKnown and T["No members here through this rank."]
                or T["Membership by rank is unavailable."]
        end
        entries[#entries + 1] = {
            text = rank(rankName), rank = true,
            count = rankDetailsKnown and tostring(#members) or "?",
            tooltip = tooltip,
        }
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
    }
end





local sections, chrome, actions, byId

local function Build()
    local db = function() return addon.db end

    sections = {
        { id = "voting", title = T["Voting"], rows = {
            SwitchRow("selfVote", T["Council may vote for themselves"],
                T["Off: a member cannot vote on their own row."],
                function() return db().vote.selfVote end,
                function(v)
                    db().vote.selfVote = v
                    addon.Council:RequestBroadcast()
                end,
                { locked = LeaderLock(function() return addon.Config:Vote().selfVote end),
                    refreshOn = LOCK_EVENTS }),
            SwitchRow("multiVote", T["Allow voting for several candidates"],
                T["Off: one candidate per item, per member."],
                function() return db().vote.multiVote end,
                function(v)
                    db().vote.multiVote = v
                    addon.Council:RequestBroadcast()
                end,
                { locked = LeaderLock(function() return addon.Config:Vote().multiVote end),
                    refreshOn = LOCK_EVENTS }),
            SwitchRow("hideVotes", T["Hide vote counts until you have voted"],
                T["Display guard only - every client still holds the voter list."],
                function() return db().vote.hideVotes end,
                function(v)
                    db().vote.hideVotes = v
                    addon.Council:RequestBroadcast()
                end,
                { locked = LeaderLock(function() return addon.Config:Vote().hideVotes end),
                    refreshOn = LOCK_EVENTS }),
            SwitchRow("allowStartRequests", T["Council may request a run start"],
                T["Allows council members to request a run. Approval is required unless Council members may start runs themselves is enabled."],
                function() return db().allowStartRequests end,
                function(v)
                    db().allowStartRequests = v
                    if not v then db().councilMayStartRuns = false end
                    addon.Council:RequestBroadcast()
                    addon.StartRequest:Refresh()
                end,
                { locked = LeaderLock(function() return addon.Config:StartRequestsAllowed() end),
                    refreshOn = LOCK_EVENTS }),
            SwitchRow("councilMayStartRuns", T["Council members may start runs themselves"],
                T["Starts requested runs immediately, without Loot Master approval. Requires Council may request a run start."],
                function() return db().allowStartRequests and db().councilMayStartRuns end,
                function(v)
                    db().councilMayStartRuns = db().allowStartRequests and v or false
                    addon.Council:RequestBroadcast()
                end,
                { dependsOn = "allowStartRequests",
                    disabled = function()
                        if db().allowStartRequests then return nil end
                        return addon.Locale.Format(T["Requires Council may request a run start."])
                    end,
                    locked = LeaderLock(function() return addon.Config:CouncilMayStartRuns() end),
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

        { id = "lootHandling", title = T["Loot handling"], rows = {
            SwitchRow("autopass", T["Auto-pass on unusable items"],
                T["Acts only on definite class or armour restrictions."],
                function() return db().autopass end,
                function(v) db().autopass = v end),

            SwitchRow("autopassTransmog", T["Don't auto pass on items you can gain an appearance from"],
                T["Prevents auto-pass when this source would teach you a new appearance, whatever its armour type."],
                function() return db().autopassTransmog end,
                function(v) db().autopassTransmog = v end,
                { hidden = function() return addon.IsForever end }),
            SwitchRow("masterAutoLoot", T["Auto-loot to bags as Master Looter"],
                T["As the group's Master Looter, a boss's whole corpse goes to your bags. In a raid, so do trash items at the loot threshold."],
                function() return db().masterAutoLoot end,
                function(v) db().masterAutoLoot = v end,
                { hidden = function() return not addon.Loot.MasterLootAvailable() end }),


            SwitchRow("guildGroupOnly", T["Guild loot funnel guard"],
                T["Asks before passing your loot when this is not a guild group or the Loot Master is not in your guild."],
                function() return db().funnel.guildGroupOnly end,
                function(v)
                    db().funnel.guildGroupOnly = v

                    if v then addon.Loot:KeepGuard()
                    elseif addon.UI.RaidPrompt then addon.UI.RaidPrompt:Evaluate() end
                end,
                { danger = true,

                    status = function()
                        if not db().funnel.guildGroupOnly or not IsInGroup() then
                            return T["Asks before passing your loot when this is not a guild group or the Loot Master is not in your guild."]
                        end
                        if addon.Loot.IsGuildGroup() then
                            if addon.Loot:GuardReason() == "guild" then
                                return T["The Loot Master is not in your guild."], "accent"
                            end
                            return T["This is a guild group - the funnel can act."]
                        end

                        local present, required = addon.Loot:GetGuildPartyCounts()
                        if not required then
                            return T["Waiting for the game to report this group."], "accent"
                        end
                        return addon.Locale.Format(T["Not a guild group: %d in guild, %d needed."],
                            present, required), "accent"
                    end }),


            SwitchRow("inGroups", T["Use SLC in groups?"],
                T["Enable this to use SLC in groups instead of only raids"],
                function() return db().raidPrompt.inGroups end,
                function(v)
                    db().raidPrompt.inGroups = v
                    if v and addon.UI.RaidPrompt then addon.UI.RaidPrompt:Evaluate() end
                end),


            Setting({ id = "boeWinner", type = "input", text = T["Route BoE items to"],
                help = T["One-click award target for a Bind-on-Equip item, once a reason is chosen below too. This never awards anything by itself - it only pre-fills the Award button on this player's row, and the Loot Master still has to click it."],
                inputWidth = 160, repaints = { "boeReason" },
                getValue = function() return db().boeRoute.winner or "" end,
                setValue = function(text)
                    text = text:trim()
                    if text == "" then
                        db().boeRoute.winner = nil
                        return
                    end
                    local record = addon.Player:Get(text)
                    local nameKey = addon.Player:NameKey(text)
                    if not record.guid and not nameKey then
                        Chat("warn", addon.Player:NameHint())
                        return
                    end
                    db().boeRoute.winner = addon.Player:Qualify(text)
                end }),
            BoEReason(),

            SwitchRow("autoJoin", T["Automatically join SLC sessions in groups you join?"],
                T["Skip the question about taking part and join as soon as the Loot Master starts using Simple Loot Council. You are still told in chat. Never applies while you are the Loot Master."],
                function() return db().raidPrompt.silence end,
                function(v)
                    db().raidPrompt.silence = v
                    addon.UI.RaidPrompt:SyncSilence()
                end),

            SwitchRow("autoHandover", T["Automatically keep SLC active when lead or Loot Master changes?"],
                T["When lead or Loot Master passes to you in a group already using Simple Loot Council, carry on without asking. You are still told in chat. A group not using it asks as normal."],
                function() return db().raidPrompt.autoHandover end,
                function(v)
                    db().raidPrompt.autoHandover = v
                    if v and addon.UI.RaidPrompt then addon.UI.RaidPrompt:Evaluate() end
                end),

            SwitchRow("dropDelegationOnLead", T["Don't maintain prior Loot Master delegations when receiving group leader"],
                T["Become the Loot Master yourself when made group leader. Off: the previous leader's delegate keeps loot until you run /slc lootmaster clear."],
                function() return db().raidPrompt.dropDelegationOnLead end,
                function(v) db().raidPrompt.dropDelegationOnLead = v end),
        } },

        { id = "session", title = T["Session"], rows = {
            SwitchRow("whispers", T["Allow whispered loot responses"],
                T["Allow loot responses to be sent to you via whisper during a session."],
                function() return db().whispers.enabled end,
                function(v) db().whispers.enabled = v end),
            SwitchRow("showMoreInfo", T["Show the council hover panel"],
                T["Shows recent awards and other winners for the hovered item."],
                function() return db().showMoreInfo end,
                function(v) db().showMoreInfo = v end),
            SwitchRow("sessionFrame", T["Show the session frame"],
                T["Display the session frame to the left of the options panel during a session."],
                function() return db().sessionFrame end,
                function(v)
                    db().sessionFrame = v

                    addon.UI.SessionPanel:SetDocked(v)
                end),
            SwitchRow("timer", T["Session timer"],
                T["Display only; expiry never closes a run or rejects a response."],
                function() return db().timer.enabled end,
                function(v) db().timer.enabled = v end),
            Setting({ id = "timerDuration", type = "input", numeric = true, inputWidth = 78,
                text = T["Session timer length (seconds)"],
                help = T["Clamped to 10 seconds - 1 hour."],
                dependsOn = "timer",
                disabled = function()
                    if db().timer.enabled then return nil end
                    return addon.Locale.Format(T["Requires the session timer."])
                end,
                getValue = function() return tostring(db().timer.duration or 120) end,
                setValue = function(text)
                    local value = tonumber(text) or db().timer.duration
                    db().timer.duration = math.max(10, math.min(3600, math.floor(value)))
                end }),
        } },

        { id = "announcements", title = T["Announcements"], rows = {
            SwitchRow("announceAwards", T["Announce awards in raid chat"],
                T["The Loot Master posts one line when an item is awarded."],
                function() return db().announce.awards end,
                function(v) db().announce.awards = v end),
            SwitchRow("announceTrades", T["Announce trades in raid chat"],
                T["Posts when the awarded item is physically handed over."],
                function() return db().announce.trades end,
                function(v) db().announce.trades = v end),
            SwitchRow("announceRolls", T["Announce roll requests in raid chat"],
                T["Posts when the council asks the whole group to roll. This is the only way a raider whose addon is not working can take part: their popup never opens, so the line in chat is the request."],
                function() return db().announce.rolls end,
                function(v) db().announce.rolls = v end),
        } },

        { id = "responses", title = T["Response buttons"], rows = { Responses() } },

        { id = "council", title = T["Loot council"], rows = { Council(), CouncilRanks() } },

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
                help = T["Older entries are removed at login. Imported history is not affected."],
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
                values = { wowutils = "WowUtils", gow = "Guilds of WoW" },
                order = { "wowutils", "gow" },
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
        } },

        { id = "alts", title = T["Alts"], rows = { Alts() } },
    }

    chrome = { StatusTags(), LootMaster(), CouncilInForce() }


    actions = {
        { id = "sendConfig", text = T["Send config"], primary = true,

            onClick = function() addon.UI.ConfigShareFrame:ToggleSend() end },
        { id = "versions", text = T["Raid versions"],
            onClick = function() addon.UI.VersionFrame:Toggle() end },
        { id = "history", text = T["Loot history"],
            onClick = function() addon.UI.HistoryFrame:Toggle() end },
        { id = "attendance", text = T["Attendance"],
            onClick = function() addon.UI.AttendanceFrame:Toggle() end },
        { id = "team", text = T["Raid team loot"],
            onClick = function() addon.UI.RaidTeamFrame:Toggle() end },
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
        for _, row in ipairs(section.rows) do collect(row) end
    end
    for _, row in ipairs(chrome) do collect(row) end
    table.sort(events)
    return events
end
