if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 


local ADDON_NAME = ...


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text


addon.VERSION = addon.VERSION or "dev"


addon.DEV_TOOLS = false






local pendingNotices = {}




local OnAddOnLoaded, OnPlayerLogin

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
local loggedIn = false
boot:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        OnAddOnLoaded()

        if not loggedIn and IsLoggedIn() then
            loggedIn = true
            self:UnregisterEvent("PLAYER_LOGIN")
            OnPlayerLogin()
        end
    elseif event == "PLAYER_LOGIN" and not loggedIn then
        loggedIn = true
        self:UnregisterEvent("PLAYER_LOGIN")
        OnPlayerLogin()
    end
end)

function OnAddOnLoaded()
    SimpleLootCouncilDB = SimpleLootCouncilDB or {}
    local db = SimpleLootCouncilDB



    if db.pseudoLocale then addon.Locale.Pseudo(true) end


    pendingNotices = addon.RunMigrations(db)
    addon.ApplyDefaults(db, addon.defaults)

    addon.db = db


    addon.Log:Init(db)
    addon.Log:I("Core", "loaded", addon.VERSION, "schema", db.schemaVersion)
    for _, rejected in ipairs(addon.Locale.rejected) do
        addon.Log:W("Locale", "rejected", rejected.key, rejected.reason)
    end
end

function OnPlayerLogin()


    addon.Player:Init(addon.db)


    addon.Restrictions:Init()
    addon.Comms:Init()


    addon.Version:Init()


    addon.Gear:Init()


    addon.Council:Init()
    addon.ConfigShare:Init()
    addon.Session:Init()
    addon.SimC:Init()

    addon.Roll:Init()



    addon.Storage:Init()

    addon.Encounter:Init()

    addon.Attendance:Init()

    addon.BonusRoll:Init()


    addon.Wishlist:Init()
    addon.Loot:Init()
    addon.Trade:Init()

    addon.BagShare:Init()


    addon.History:Init()


    addon.Snapshot:Init()

    addon.Announce:Init()


    addon.Whisper:Init()
    addon.Autopass:Init()

    addon.Specs:Init(addon.db)

    addon.RaidTeam:Init()


    addon.Perf:Init()


    addon.Pixel:Init()


    if not addon.Style.rounded then
        addon.Log:W("UI", "rounded corner art did not load; frames will be square")
    end

    if not addon.Style.logo.loaded then
        addon.Log:W("UI", "logo art did not load; settings will show a text title")
    end

    if addon.db and addon.db.pride and not addon.Style.logoPride.loaded then
        addon.Log:W("UI", "pride wordmark did not load; settings keeps the default")
    end


    addon.UI.VoterFrame:Init()
    addon.UI.MLFrame:Init()
    addon.UI.QueueFrame:Init()
    addon.StartRequest:Init()
    addon.UI.StartRequestFrame:Init()
    addon.UI.TradeQueueFrame:Init()
    addon.UI.HistoryFrame:Init()
    addon.UI.RaidTeamFrame:Init()
    addon.UI.AttendanceFrame:Init()
    addon.UI.RaidPrompt:Init()
    addon.UI.VersionFrame:Init()
    addon.UI.ConfigShareFrame:Init()
    addon.UI.SessionPanel:Init()
    addon.UI.Options:Init()




    if IsInGroup() then
        C_Timer.After(2, function()
            addon.Council:EnsureShared("login")

            addon.Loot:EnsureHandling("login")
        end)
    end


    print(addon.Locale.Format(T["|cff478cebSimpleLootCouncil|r v%s loaded.  |cff73716C/slc|r for options."],
        tostring(addon.VERSION)))

    for _, notice in ipairs(pendingNotices) do
        print(addon.Log.CHAT_PREFIX.accent .. notice)
    end
    pendingNotices = {}



    if addon.Locale.IsPseudo() then
        print(addon.Log.CHAT_PREFIX.error .. T["the pseudo-locale test mode is ON - every string is wrapped in guillemets, announcements included. /slc pseudo off turns it off."])
    end
end









local AutoClose = {}
addon.AutoClose = AutoClose

local sweepGeneration, sweeping = 0, false

function AutoClose:OnEvent(event)


    if event == "PLAYER_CONTROL_LOST" and UnitOnTaxi("player") then return end
    sweepGeneration = sweepGeneration + 1
    sweeping = true
    C_Timer.After(0, function() sweeping = false end)
end



function AutoClose:AfterHide(decide)
    local swept, generation = sweeping, sweepGeneration
    C_Timer.After(0, function()
        decide(swept or sweepGeneration ~= generation)
    end)
end

do
    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PLAYER_CONTROL_LOST")
    watcher:SetScript("OnEvent", function(_, event) AutoClose:OnEvent(event) end)
end







addon.Comms:Register("ping", "any", function(args, sender)
    local size = args and args.size or 0
    print((addon.Log.CHAT_PREFIX.accent .. "ping from %s, %d bytes intact=%s")
        :format(tostring(sender), size,
            tostring(args and args.blob and #args.blob == size)))
end)






local function DumpValue(value, indent, seen)
    indent = indent or ""
    seen = seen or {}

    local t = type(value)
    if t == "string" then
        return ("%q"):format(value)
    elseif t == "number" then

        if value == math.huge then return "math.huge" end
        if value == -math.huge then return "-math.huge" end
        return tostring(value)
    elseif t ~= "table" then
        return tostring(value)
    end

    if seen[value] then return '"<cycle>"' end
    seen[value] = true

    local inner = indent .. "    "
    local parts = {}


    local count = #value
    for i = 1, count do
        parts[#parts + 1] = inner .. DumpValue(value[i], inner, seen)
    end
    local keys = {}
    for k in pairs(value) do
        if not (type(k) == "number" and k >= 1 and k <= count and k % 1 == 0) then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        parts[#parts + 1] = ("%s[%s] = %s")
            :format(inner, ("%q"):format(tostring(k)), DumpValue(value[k], inner, seen))
    end

    seen[value] = nil
    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

local dumpFrame

local function ShowDump(title, text)
    if not dumpFrame then
        local S, P = addon.Style, addon.Pixel
        local f = S.Window("SimpleLootCouncilDumpFrame", "dump", 700, 480, title)
        local content = f.Content
        local barW = S.size.SCROLLBAR_W + S.size.SCROLLBAR_GAP


        f.hint = S.Label(content, S.fontHint, "LEFT", 2)
        P.Point(f.hint, "TOPLEFT", content, "TOPLEFT", 0, 0)
        P.Size(f.hint, content.slcWidth, 2 * S.size.COUNT_H)
        f.hint:SetText(T["Ctrl+A, Ctrl+C to copy  -  Hold shift to scroll instantly"])

        local close = S.Button(content, T["Close"])
        P.Point(close, "BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
        close:SetScript("OnClick", function() f:Hide() end)

        local holder = CreateFrame("Frame", nil, content)
        P.Point(holder, "TOPLEFT", f.hint, "BOTTOMLEFT", 0, -S.size.ITEM_GAP)
        P.Point(holder, "BOTTOMRIGHT", close, "TOPRIGHT", 0, S.size.GAP)

        local scroll = CreateFrame("ScrollFrame", nil, holder)
        scroll:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -barW, 0)
        local bar = S.AttachScrollBar(scroll, holder, 20)
        bar:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
        bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)

        local wheel = S.ScrollWheel(bar, 20)
        local function JumpWheel(self, delta)
            if not IsShiftKeyDown() then return wheel(self, delta) end
            local _, maximum = bar:GetMinMaxValues()
            bar:SetValue(delta > 0 and 0 or maximum)
        end
        scroll:SetScript("OnMouseWheel", JumpWheel)
        bar:SetScript("OnMouseWheel", JumpWheel)

        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(S.fontInput)
        P.Size(edit, content.slcWidth - barW, nil)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() f:Hide() end)
        scroll:SetScrollChild(edit)
        f.edit = edit

        dumpFrame = f
    end

    dumpFrame.Title:SetText(title)
    addon.Pixel.AfterLayout(dumpFrame.ClampTitle)
    dumpFrame.edit:SetText(text)
    if not dumpFrame:IsShown() then dumpFrame:RestorePosition() end
    dumpFrame:Show()
end

local function Print(msg)
    print(addon.Log.CHAT_PREFIX.accent .. msg)
end



function addon.ShowHistoryCSV(scope)
    local count = addon.History:CountForScope(scope)
    if count == 0 then
        Print(scope == "slc"
            and T["no history recorded by this addon to export"]
            or T["no history to export"])
        return
    end
    local title = scope == "slc"
        and addon.Locale.Plural{
            one = "History CSV - %d row, this addon only",
            other = "History CSV - %d rows, this addon only",
        }
        or addon.Locale.Plural{
            one = "History CSV - %d row",
            other = "History CSV - %d rows",
        }
    ShowDump(addon.Locale.Format(title, count, count),
        addon.History:ToCSV(scope))
end

SLASH_SIMPLELOOTCOUNCIL1 = "/slc"
SLASH_SIMPLELOOTCOUNCIL2 = "/glc"




local function SyntheticRecoverySnapshot(candidateCount, itemCount)
    local names, items = {}, {}
    for c = 1, candidateCount do
        names[c] = ("Tester%02d-Area52"):format(c)
    end
    for s = 1, itemCount do
        local candidates = {}
        for c, name in ipairs(names) do
            local voters = {}
            for v = 1, math.min(5, candidateCount) do
                voters[names[(c + v - 1) % candidateCount + 1]] = true
            end
            candidates[name] = {
                status = c % 6 == 0 and "PASS" or "RESPONDED",
                response = c % 6 == 0 and nil or (c % 3 + 1),
                note = ("Upgrade for spec %d; current piece from boss %d; item %d")
                    :format(c % 4 + 1, (c + s) % 9 + 1, s),
                voters = voters,
                gear1 = ("|cffa335ee|Hitem:%d::::::::90:262::35:5:12801:13440:6652:13668:12699::::::|h[Equipped %d]|h|r")
                    :format(220000 + c * 31 + s, c),
                gear2 = ("|cffa335ee|Hitem:%d::::::::90:262::35:5:12801:13440:6652:13668:12699::::::|h[Second %d]|h|r")
                    :format(225000 + c * 29 + s, c),
                diff = (c * 7 + s) % 28,
                ilvl = 680 + (c + s) % 25,
                roll = (c * 43 + s * 17) % 100 + 1,
                rollBy = "player",
                rollSeq = 1,
            }
        end
        items[s] = {
            id = ("measure-%d-%d"):format(s, 230000 + s),
            session = s,
            link = ("|cffa335ee|Hitem:%d::::::::90:262::35:5:12801:13440:6652:13668:12699::::::|h[Recovery Item %d]|h|r")
                :format(230000 + s, s),
            owner = names[(s - 1) % candidateCount + 1],
            boss = addon.Locale.Format(T["The Measured Boss %d"], (s - 1) % 8 + 1),
            awarded = s % 4 == 0 and names[(s + 2) % candidateCount + 1] or nil,
            awardSeq = s % 4 == 0 and 1 or nil,
            delivered = false,
            rollRound = 1,
            rollAskAll = 1,
            candidates = candidates,
        }
    end
    return {
        snapshotVersion = 1,
        runId = "synthetic-size-measurement",
        items = items,
        lootMaster = names[1],
        groupKey = table.concat(names, "\0"),
        timer = 60,
        expiresAt = GetServerTime() + 30,
        savedAt = GetServerTime(),
        coins = {},
    }, names[1], names[2]
end



local HELP_TITLE = "|cff478cebSimpleLootCouncil|r %s"
local HELP_HEADER = "|cff96c2fa%s|r"
local HELP_LINE = "  |cff478ceb%s|r - %s"

local function HelpSections(dev)
    if dev then
        return {
            { T["Testing"],
                { T["test [<count> / <link> [from [heroic] <boss>], ...]"], addon.IsForever
                    and addon.Locale.Format(
                        T["simulated run; a count of 1-%d draws at random from %d rare dungeon boss drops, no argument gives 3; a link is attributed to the boss 'from' names"],
                        addon.TestLoot.MAX, addon.TestLoot:Count())
                    or addon.Locale.Format(
                        T["simulated run; a count of 1-%d draws at random from %d classic raid items, no argument gives 3; a link is attributed to its boss and difficulty from the Adventure Guide and its upgrade track, 'from' overrides (any case, partial name)"],
                        addon.TestLoot.MAX, addon.TestLoot:Count()) },
                { T["ftest [<count>]"], addon.Locale.Format(
                    T["simulated run of 1-%d items from %d rare dungeon boss drops that WoW: Forever serves; no argument gives 3"],
                    addon.TestLoot.MAX, addon.TestLoot:DungeonCount()) },
                { T["testcoin [Name-Realm] [session]"], T["fake a coin result"], retailOnly = true },
                { T["stress [<raiders> [<items> [<seconds>]] / stop]"], T["replay a raid's answers"] },
                { T["pseudo [on / off]"], T["localisation test mode"] },
            },
            { T["State"],
                { "show", T["current run state"] },
                { "status", T["restrictions, queue depth, leader"] },
                { "boss", T["current boss and encounter log"] },
                { "coins", T["recent bonus-roll results"], retailOnly = true },
                { "guild", T["the guild-group gate"] },
                { "names", T["what the name APIs return here"] },
                { T["item <link>"], T["why the funnel takes an item"] },
                { "set", T["equipped set facts"] },
                { "taint", T["blocked-action counts"] },
            },
            { T["Comms and logs"],
                { T["ping [bytes]"], T["comms round-trip test"], devTools = true },
                { T["comms [reset]"], T["addon message counters"], devTools = true },
                { T["snapshotsize <candidates> <items>"], T["recovery sizes"], devTools = true },
                { T["perf [start [label] / stop / all]"], T["CPU profiler"] },
                { T["log history"], T["the log across sessions"] },
                { "dump", T["saved variables as Lua"] },
                { "debug", T["toggle log echo to chat"] },
            },
        }
    end
    return {
        { T["Setup"],
            { "/slc", T["open settings (alt. config, options)"] },
            { T["on / off"], T["use SLC for this group, or stop"] },
            { T["council [add / remove <name>]"], T["manage the council"] },
            { "resend", T["push the council and settings again"] },
            { T["lootmaster [<name> / clear]"], T["delegate loot (alt. lm)"] },
            { T["alt [<alt> <main> / remove <alt>]"], T["link an alt to its main"] },
        },
        { T["Running loot"],
            { T["additem <link>"], T["queue an item"] },
            { "queue", T["staging window (alt. q)"] },
            { "start", T["start a run on the queued items"] },
            { "vote", T["reopen the council window (alt. v)"] },
            { "response", T["reopen your response window (alt. r)"] },
            { "session", T["your view of the run (alt. sess)"] },
            { T["roll [ask / random / clear]"], T["rolls on unawarded items"] },
            { T["whisper [text]"], T["the whisper fallback (alt. w)"] },
            { "end", T["end the run"] },
            { "clear", T["discard the staged items"] },
            { T["test [<count>]"], T["simulated run; /slc help dev for more"] },
        },
        { T["Trades and history"],
            { T["bags [add <n> / add all]"], T["your tradeable items"] },
            { "held", T["items you owe or hold"] },
            { T["trade [name]"], T["trade someone you owe"] },
            { "trades", T["the Loot to Trade window"] },
            { "history", T["loot history browser (alt. h)"] },
            { T["import [addon]"], T["import another addon's history"] },
            { T["csv [slc] [comma / semicolon]"], T["export history"] },
            { T["team [season [date / clear]]"], T["raid team loot (alt. t)"] },
            { T["attendance [name / nights]"], T["attendance (alt. att)"] },
            { "version", T["who runs which build (alt. ver)"] },
            { "log", T["the diagnostic log, copyable"] },
        },
    }
end

local function HelpLine(command, text)
    print(HELP_LINE:format(command, text))
end

local function PrintHelp(dev)
    local version = addon.Locale.Format(dev and T["v%s - developer commands"] or T["v%s"], addon.VERSION)
    print(HELP_TITLE:format(version))
    for _, section in ipairs(HelpSections(dev)) do
        print(HELP_HEADER:format(section[1]))
        for i = 2, #section do

            if not (addon.IsForever and section[i].retailOnly)
                and (addon.DEV_TOOLS or not section[i].devTools) then
                HelpLine(section[i][1], section[i][2])
            end
        end
    end
    if not dev then
        print(" ")
        HelpLine(T["help dev"], T["developer and diagnostic commands"])
    end
end

SlashCmdList["SIMPLELOOTCOUNCIL"] = function(input)
    local cmd = (input or ""):lower():match("^(%S*)")
    if not addon.DEV_TOOLS and (cmd == "ping" or cmd == "comms" or cmd == "snapshotsize") then
        Print(addon.Locale.Format(T["unknown command '%s' - /slc help for the list"], cmd))
        return
    end

    if cmd == "log" then

        local wantAll = input:lower():find("history") or input:lower():find("all")
        local entries = wantAll and addon.Log:GetEntries()
            or addon.Log:GetSessionEntries()

        if #entries == 0 then
            Print("log is empty.")
            return
        end

        if wantAll then
            ShowDump("Log - full history", table.concat(entries, "\n"))
        else
            ShowDump(("Log - this session (%d lines, /slc log history for all)")
                :format(#entries), table.concat(entries, "\n"))
        end

    elseif cmd == "dump" then
        ShowDump("SavedVariables", "SimpleLootCouncilDB = " .. DumpValue(addon.db))

    elseif cmd == "debug" then
        addon.db.debug = not addon.db.debug
        addon.Log:SetEcho(addon.db.debug)
        Print(addon.Locale.Format(addon.db.debug
            and T["debug chat output on"] or T["debug chat output off"]))

    elseif cmd == "pseudo" then

        local arg = input:lower():match("^%S+%s+(%S+)")
        local on
        if arg == "on" then on = true
        elseif arg == "off" then on = false
        elseif arg == nil then on = not addon.Locale.IsPseudo()
        else
            Print(T["usage: /slc pseudo [on||off]"])
            return
        end
        if on == addon.Locale.IsPseudo() then
            Print(on and T["pseudo-locale test mode is already on."]
                or T["pseudo-locale test mode is already off."])
            return
        end
        addon.Locale.Pseudo(on)
        C_UI.Reload()

    elseif cmd == "ping" then

        local size = tonumber(input:match("%s(%d+)")) or 1200
        local chars = {}
        for i = 1, size do
            chars[i] = string.char(math.random(33, 126))
        end
        local blob = table.concat(chars)
        local sent = addon.Comms:Send("ping", { size = size, blob = blob })
        if not sent then
            local reason = addon.Restrictions:GetBlockReason()
            Print("ping not sent" .. (reason and (": " .. reason) or
                " - see /slc log"))
        else
            Print(("ping sent, %d bytes"):format(size))
        end

    elseif cmd == "snapshotsize" then
        local n, m = input:match("^%S+%s+(%d+)%s+(%d+)%s*$")
        n, m = tonumber(n), tonumber(m)
        if not n or not m or n < 1 or n > 40 or m < 1 or m > 32 then
            Print("usage: /slc snapshotsize <candidates 1-40> <items 1-32>")
            return
        end
        local full, me, requester = SyntheticRecoverySnapshot(n, m)
        local own = {}
        for index, item in ipairs(full.items) do
            own[index] = {
                id = item.id, session = item.session, link = item.link,
                owner = item.owner, boss = item.boss, awarded = item.awarded,
                awardSeq = item.awardSeq, delivered = item.delivered,
                rollRound = item.rollRound, rollAskAll = item.rollAskAll,
                candidates = { [me] = item.candidates[me] },
            }
        end
        local thin = {}
        for key, value in pairs(full) do thin[key] = value end
        thin.items = own
        thin.candidateOnly = me
        local fullBytes, fullChunks = addon.Comms:Measure("run_start", full)
        local ownBytes, ownChunks = addon.Comms:Measure("run_start", thin)
        local replyBytes, replyChunks = addon.Comms:Measure("run_reply", thin)
        if not fullBytes or not ownBytes or not replyBytes then
            Print("snapshot encoding failed - see /slc log")
            return
        end
        Print(("v%s synthetic snapshot %d candidates x %d items: full %d bytes, %d chunks; raider %d bytes, %d chunks; holder reply %d bytes, %d chunks")
            :format(addon.VERSION, n, m, fullBytes, fullChunks,
                ownBytes, ownChunks, replyBytes, replyChunks))


        if n < 3 then
            Print("split recovery: needs 3 or more candidates - the loot master, the council member who reloads, and a raider to send a part")
            return
        end
        local split = addon.Session.Split.Measure(full, requester)
        if not split then
            Print("split recovery encoding failed - see /slc log")
            return
        end
        Print(("v%s split recovery %d candidates x %d items: skeleton %d bytes, %d chunks; largest part %d bytes, %d chunks; %d parts, %d bytes, %d chunks in all")
            :format(addon.VERSION, n, m, split.skeletonBytes, split.skeletonFrames,
                split.largestBytes, split.largestFrames, split.parts, split.bytes, split.frames))

        local raider
        for name in pairs(full.items[1].candidates) do
            if name ~= me and name ~= requester and (not raider or name < raider) then
                raider = name
            end
        end
        local copy = addon.Session.RunCopy.Measure(full, requester, raider)
        if not copy then
            Print("saved-copy encoding failed - see /slc log")
            return
        end
        local council, own = copy.council, copy.raider
        Print(("v%s saved copy %d candidates x %d items: council ask %d bytes, %d chunks; nothing changed %d bytes, %d chunks; one item changed %d bytes, %d chunks; raider ask %d bytes, %d chunks; one item changed %d bytes, %d chunks")
            :format(addon.VERSION, n, m, council.ask.bytes, council.ask.frames,
                council.same.bytes, council.same.frames, council.one.bytes, council.one.frames,
                own.ask.bytes, own.ask.frames, own.one.bytes, own.one.frames))


    elseif cmd == "perf" then
        addon.Perf:PerfCommand(input:match("^%S+%s*(.*)$"))

    elseif cmd == "comms" then
        addon.Perf:CommsCommand(input:match("^%S+%s*(.*)$"))

    elseif cmd == "stress" then
        addon.Perf:StressCommand(input:match("^%S+%s*(.*)$"))

    elseif cmd == "council" then

        local action, who = input:match("^%S+%s+(%S+)%s+(.+)$")
        if action == "add" and who then
            local ok, reason = addon.Council:Add(who)
            if ok then
                addon.Council:Broadcast()
                Print(addon.Locale.Format(T["added %s"], who))
            else
                Print(addon.Locale.Format(T["could not add %s: %s"], who,
                    reason or T["unknown"]))
            end
        elseif action == "remove" and who then
            if addon.Council:Remove(who) then
                addon.Council:Broadcast()
                Print(addon.Locale.Format(T["removed %s"], who))
            else
                Print(addon.Locale.Format(T["%s is not on the council."], who))
            end
        else
            local configured = addon.Council:GetConfigured()
            local ranks = addon.Council:GetConfiguredRanks()
            Print(addon.Locale.Format(T["council: %d configured, %d guild rank(s), %d active this session"],
                #configured, #ranks, addon.Council:GetCount()))
            for _, record in ipairs(configured) do

                Print(addon.Locale.Format(record.pending
                    and T["  %s  (not confirmed)"] or T["  %s"],
                    tostring(record.fullName)))
            end


            local covered = {}
            for _, rankName in pairs(addon.Council:RankMembers()) do
                covered[rankName] = (covered[rankName] or 0) + 1
            end
            for _, rank in ipairs(ranks) do
                Print(addon.Locale.Format(T["  %s  (%s)"], rank.name, rank.known
                    and addon.Locale.Format(T["guild rank, %d here"],
                        covered[rank.name] or 0)
                    or T["no such rank in your guild"]))
            end


            Print(addon.IsForever and T["usage: /slc council add||remove <Name>"]
                or T["usage: /slc council add||remove <Name-Realm>"])

            Print(addon.EDITION == "eui" and T["guild ranks are chosen on the Simple Loot Council page of the EllesmereUI settings"]
                or T["guild ranks are chosen in the settings window"])
        end

    elseif cmd == "resend" then


        if addon.Council:Broadcast(true) then
            Print(T["council and settings re-sent"])
        else
            Print(T["not sent. Requires you to be the group leader or the Loot Master."])
        end

    elseif cmd == "alt" then

        local rest = input:match("^%S+%s+(.+)$")
        if not rest then
            local mains = addon.db.mains or {}
            local any = false
            for alt, main in pairs(mains) do
                any = true
                Print(addon.Locale.Format(T["  %s -> %s"], alt, main))
            end
            if not any then Print(T["no alts linked"]) end
            Print(T["usage: /slc alt <Alt-Realm> <Main-Realm>  ||  /slc alt remove <Alt-Realm>"])
        else
            local removeWho = rest:match("^remove%s+(.+)$")
            if removeWho then
                local ok = addon.Player:ClearMain(removeWho)
                Print(addon.Locale.Format(ok and T["removed the alt link for %s"]
                    or T["no alt link found for %s"], removeWho))
            else
                local alt, main = addon.Player:SplitPair(rest)
                if main == "ambiguous" then
                    Print(T["could not tell where the alt's name ends - put a comma between the two: /slc alt <Alt-Realm>, <Main-Realm>"])
                elseif not alt then
                    Print(T["usage: /slc alt <Alt-Realm> <Main-Realm>  ||  /slc alt remove <Alt-Realm>"])
                else
                    local ok, reason = addon.Player:SetMain(alt, main)
                    if ok then
                        Print(addon.Locale.Format(T["linked %s as an alt of %s"],
                            addon.Player:CanonicalName(alt),
                            addon.Player:CanonicalName(main)))
                    else
                        Print(addon.Locale.Format(T["could not link %s to %s: %s"],
                            alt, main, reason or T["unknown"]))
                    end
                end
            end
        end

    elseif cmd == "lootmaster" or cmd == "lm" or cmd == "ml" then
        local who = input:match("^%S+%s+(.+)$")

        if not who then
            local current = addon.GetMasterLooter()

            Print(addon.Locale.Format(addon.GetGameMasterLooter()
                and T["Loot Master: %s (the group's Master Looter)"]
                or addon.IsLootDelegated() and T["Loot Master: %s (delegated)"]
                or T["Loot Master: %s (group leader)"], tostring(current)))
            Print(addon.IsForever and T["usage: /slc lootmaster <Name>  ||  /slc lootmaster clear"]
                or T["usage: /slc lootmaster <Name-Realm>  ||  /slc lootmaster clear"])
            Print(T["a delegation lasts for this raid - it is forgotten when you leave the group"])
            return
        end

        if not addon.CanAssignMasterLooter() then
            Print(T["only the group leader can set the Loot Master"])
            return
        end


        local onMasterLoot = addon.GetGameMasterLooter() ~= nil
        local function HandGameMasterLoot(unit, name)
            if addon.SetGameMasterLooter(unit) then
                Print(addon.Locale.Format(T["%s is now the group's Master Looter."], name))
            else
                Print(addon.Locale.Format(T["could not make %s the group's Master Looter - set it from your portrait's Loot Method menu."], name))
            end
        end

        if who:lower() == "clear" then
            addon.db.lootMaster = nil
            addon.InvalidateMasterLooter()
            if onMasterLoot then
                HandGameMasterLoot("player", addon.Player:GetFullName("player") or "?")
            end
            addon.Council:Broadcast()
            Print(addon.Locale.Format(T["Loot Master reset to the group leader: %s"],
                tostring(addon.Player:GetFullName("player") or addon.GetMasterLooter())))
            return
        end

        local record = addon.Player:Get(who)
        if not record.guid then
            Print(addon.Locale.Format(addon.IsForever
                and T["could not resolve %s - they must be in your group"]
                or T["could not resolve %s - use Name-Realm, and they must be in your group"],
                who))
            return
        end


        if not addon.GetCandidates()[record.fullName] then
            Print(addon.Locale.Format(T["%s is not in your group"], record.fullName))
            return
        end

        addon.db.lootMaster = record.guid
        addon.InvalidateMasterLooter()
        addon.Council:Broadcast()
        Print(addon.Locale.Format(T["Loot Master set to %s for this raid"],
            record.fullName))
        if onMasterLoot then
            HandGameMasterLoot(addon.Player:UnitFor(record.guid), record.fullName)
        end

    elseif cmd == "additem" then


        local itemString = input:match("|H(item:[^|]*)")
        if not itemString then
            Print(T["shift-click an item into the command: /slc additem <link>"])
            return
        end


        local _, canonical = C_Item.GetItemInfo(itemString)
        local link = canonical or input:match("(|c[^|]*|Hitem:.-|h.-|h|r)") or itemString



        if addon.Session:IsRunning() and not addon.PlayerIsMasterLooter() then
            Print(addon.Locale.Format(
                T["could not queue %s - a run is in progress, and only the Loot Master can add to it."],
                link))
            return
        end



        local boss, encounterID = addon.Encounter:Current()
        local index = addon.Session:AddItem(link, addon.Player:GetFullName("player"),
            boss, encounterID)
        Print(index and (boss
            and addon.Locale.Format(T["added as session %d: %s (boss: %s)"],
                index, link, boss)
            or addon.Locale.Format(
                T["added as session %d: %s (no encounter in progress - asking the Adventure Guide)"],
                index, link)) or T["could not add"])

    elseif cmd == "start" then
        local started, why = addon.Session:Start()
        if started then
            local count = #addon.Session:GetItems()
            Print(addon.Locale.Format(addon.Locale.Plural{
                one = "run started with %d item", other = "run started with %d items",
            }, count, count))
        elseif why == "empty" then
            Print(T["nothing to start - the staging queue is empty."])
        elseif why ~= "emptied" then

            Print(T["could not start - see /slc log"])
        end

    elseif cmd == "test" then
        local args = input:match("^%S+%s*(.*)$") or ""
        local links, sources, anySource = {}, {}, false




        local DIFFICULTY_WORDS = { lfr = 17, normal = 14, heroic = 15, mythic = 16 }
        local LINK = "|c[^|]*|Hitem:[^|]*|h.-|h|r"


        local known = addon.Encounter:KnownBossNames()
        local pos = 1
        while true do
            local s, e = args:find(LINK, pos)
            if not s then break end
            links[#links + 1] = args:sub(s, e)

            local nextStart = args:find(LINK, e + 1)
            local tail = args:sub(e + 1, (nextStart or (#args + 1)) - 1)
            tail = tail:gsub("^[%s,]+", ""):gsub("[%s,]+$", "")
            if tail ~= "" then
                local spec = tail:match("^[Ff][Rr][Oo][Mm]%s+(.+)$")
                if not spec then
                    Print(T["usage: /slc test <item link> [from [heroic] <boss>], ..."])
                    Print(addon.Locale.Format(
                        T["  after a link, only 'from <boss>' is understood - got: %s"],
                        tail))
                    return
                end
                local word, rest = spec:match("^(%a+)%s+(.+)$")
                local difficultyID = word and DIFFICULTY_WORDS[word:lower()]
                local typed = difficultyID and rest or spec

                local boss, matches = addon.Encounter.MatchBossName(known, typed)
                if not boss then
                    if #matches > 1 then
                        Print(addon.Locale.Format(T["'%s' could be any of: %s"],
                            typed, table.concat(matches, ", ")))
                        return
                    end
                    boss = typed
                    Print(addon.Locale.Format(T["no recorded boss matches '%s' - using it as typed"], typed))
                end


                sources[#links] = { boss = boss, difficultyID = difficultyID,
                    encounterID = addon.Encounter:EncounterIDFor(boss) }
                anySource = true
            end
            pos = e + 1
        end




        local origin, wanting = {}, {}
        for i, link in ipairs(links) do
            local given = sources[i] or {}
            if not given.difficultyID then
                given.difficultyID, given.track = addon.Encounter:TrackForLink(link)
            end
            if not given.boss then wanting[#wanting + 1] = i end
            if given.boss or given.difficultyID then
                sources[i] = given
                anySource = true
            end
        end


        local count
        if #links == 0 and args:match("%S") then
            count = tonumber(args:match("^%s*(%d+)%s*$"))
            if not count then
                Print(T["usage: /slc test [<count>] or /slc test <item link>, ..."])
                return
            end

            if count < 1 or count > addon.TestLoot.MAX then
                Print(addon.Locale.Format(T["pick between 1 and %d items: /slc test %d"],
                    addon.TestLoot.MAX, addon.TestLoot.MAX))
                return
            end
        end

        local function StartNow()
            local ok, countOrWhy = addon.Session:StartTest(links, count,
                anySource and sources or nil)
            if not ok then
                Print(addon.Locale.Format(T["could not start simulated run - %s"],
                    tostring(countOrWhy)))
                return
            end
            Print(addon.Locale.Format(addon.Locale.Plural{
                one = "simulated run started with %d item; awards will not be saved or traded",
                other = "simulated run started with %d items; awards will not be saved or traded",
            }, countOrWhy, countOrWhy))
            for i = 1, #links do
                local source = sources[i]
                if source then


                    local difficulty = source.difficultyID
                        and (source.track
                            and addon.Locale.Format(T["(difficulty %d, %s track)"],
                                source.difficultyID, source.track)
                            or addon.Locale.Format(T["(difficulty %d)"],
                                source.difficultyID))
                        or T["(difficulty unknown)"]
                    local boss = source.boss or T["boss unknown"]
                    if origin[i] then
                        Print(addon.Locale.Format(T["  item %d: %s %s - %s"], i,
                            boss, difficulty, origin[i]))
                    else
                        Print(addon.Locale.Format(T["  item %d: %s %s"], i,
                            boss, difficulty))
                    end
                else
                    Print(addon.Locale.Format(T["  item %d: no source - the Adventure Guide had no answer and no 'from' was given"], i))
                end
            end
        end

        if #wanting == 0 or addon.IsForever then
            StartNow()
            return
        end


        if addon.Session:IsRunning() then
            Print(T["could not start simulated run - a run is already active"])
            return
        end

        Print(addon.Locale.Format(addon.Locale.Plural{
            one = "looking up %d item in the Adventure Guide...",
            other = "looking up %d items in the Adventure Guide...",
        }, #wanting, #wanting))
        local outstanding = #wanting
        for _, i in ipairs(wanting) do
            addon.Encounter:JournalBossForLink(links[i], function(boss, detail, encounterID)
                if boss then
                    sources[i] = sources[i] or {}
                    sources[i].boss = boss
                    sources[i].encounterID = encounterID
                    origin[i] = T["from the Adventure Guide"]
                    anySource = true
                else
                    origin[i] = addon.Locale.Format(
                        T["the Adventure Guide had no answer: %s"], tostring(detail))
                end
                outstanding = outstanding - 1
                if outstanding == 0 then StartNow() end
            end)
        end


    elseif cmd == "vote" or cmd == "v" then
        if not addon.Session:IsRunning() then
            Print(T["no run is active."])
            return
        end
        local me = addon.Player:GetFullName("player")
        if not addon.PlayerIsMasterLooter() and not addon.Council:Contains(me) then
            Print(T["you are not on the council for this run - /slc response reopens your loot response window."])
            return
        end
        addon.UI.MLFrame:Open()



    elseif cmd == "response" or cmd == "r" then
        if not addon.Session:IsRunning() then
            Print(T["no run is active."])
            return
        end
        if not addon.UI.VoterFrame:Open() then
            Print(T["nothing in this run is waiting for your answer."])
        end




    elseif cmd == "whisper" or cmd == "w" then
        local text = input:match("^%S*%s+(.*)$")
        if not text or text:trim() == "" then
            Print(T["what a raider is told when they whisper you 'help':"])
            for _, line in ipairs(addon.Whisper:HelpLines()) do
                Print("  " .. line)
            end
            if not addon.db.whispers.enabled then
                Print(T["  (whispered answers are currently switched OFF in settings)"])
            end
            return
        end
        for _, line in ipairs(addon.Whisper:Describe(text)) do
            Print(line)
        end

    elseif cmd == "show" then
        local items = addon.Session:GetItems()
        if #items == 0 then Print("no items") return end
        for _, item in ipairs(items) do
            Print(("[%d] %s  owner=%s awarded=%s"):format(
                item.session, tostring(item.link), tostring(item.owner),
                tostring(item.awarded or "-")))
            for name, candidate in pairs(item.candidates) do
                Print(("     %-24s %-12s votes=%d note=%s"):format(
                    name, candidate.status,
                    addon.Session:GetVoteCount(item.session, name),
                    tostring(candidate.note or "-")))
            end
        end

    elseif cmd == "roll" then


        if not addon.Session:IsRunning() then
            Print(T["no run is active."])
            return
        end

        local verb = input:lower():match("^%S+%s+(%S+)")
        local sessions = addon.Roll.UnawardedSessions()

        if verb == "ask" then
            if #sessions == 0 then Print(T["everything is awarded."]) return end
            if addon.Roll:Ask(sessions, nil) then
                Print(addon.Locale.Format(addon.Locale.Plural{
                    one = "asked everyone to roll on %d item.",
                    other = "asked everyone to roll on %d items.",
                }, #sessions, #sessions))
            else
                Print(T["only the Loot Master can ask for a roll."])
            end

        elseif verb == "random" then
            if #sessions == 0 then Print(T["everything is awarded."]) return end
            if addon.Roll:Random(sessions) then
                Print(addon.Locale.Format(addon.Locale.Plural{
                    one = "generated rolls for %d item.",
                    other = "generated rolls for %d items.",
                }, #sessions, #sessions))
            else
                Print(T["only the Loot Master can generate rolls."])
            end

        elseif verb == "clear" then
            if addon.Roll:Clear(addon.Roll.UnawardedSessions()) then
                Print(T["rolls cleared."])
            else
                Print(T["only the Loot Master can clear rolls."])
            end

        else


            local any = false
            for _, item in ipairs(addon.Session:GetItems()) do
                local named = item.rollAsk and next(item.rollAsk) ~= nil
                if item.rollAskAll or named or item.rollRound then
                    any = true
                    Print(addon.Locale.Format("[%d] %s  round=%d  asked=%s",
                        item.session, tostring(item.link), item.rollRound or 0,
                        item.rollAskAll and "everyone"
                            or (named and "some" or "nobody")))
                    for name, candidate in pairs(item.candidates) do
                        if candidate.roll then
                            Print(addon.Locale.Format("     %-24s %3d  %s", name,
                                candidate.roll, candidate.rollBy or "?"))
                        elseif addon.Roll.IsAsked(item, name) then
                            Print(addon.Locale.Format("     %-24s   -  waiting", name))
                        end
                    end
                end
            end
            if not any then
                Print(T["no rolls asked for. /slc roll ask||random||clear"])
            end
        end

    elseif cmd == "end" then
        if not addon.Session:IsRunning() then
            Print(T["no run is active."])
            return
        end
        if addon.Session:End() then

            Print(T["run ended - undo an award from Loot to Trade if you need to."])
        else
            Print(T["only the Loot Master can end the run."])
        end


    elseif cmd == "clear" then
        if addon.Session:IsRunning() then
            Print(addon.PlayerIsMasterLooter()
                and T["a run is active - /slc end ends it for everyone first."]
                or T["a run is active - only the Loot Master can end it."])
            return
        end
        addon.Session:Clear()
        Print(T["cleared"])



    elseif cmd == "on" or cmd == "off" then
        if not IsInGroup() then
            Print(T["you are not in a group."])
            return
        end
        if not addon.PlayerIsMasterLooter() then
            Print(T["only the Loot Master can turn Simple Loot Council on or off."])
            return
        end
        if cmd == "on" then
            if addon.UI.RaidPrompt:Activate(true) then
                Print(T["SLC is now active for this group"])
            end
        else
            if addon.UI.RaidPrompt:Deactivate(true) then
                Print(T["SLC has been deactivated for this group"])
            end
        end

    elseif cmd == "bags" then


        local items = addon.Storage:GetTradeableItems()


        local eligible, filtered, owed = {}, {}, {}
        for _, entry in ipairs(items) do
            if not entry.eligible then
                filtered[#filtered + 1] = entry
            elseif entry.owed then
                owed[#owed + 1] = entry
            else
                eligible[#eligible + 1] = entry
            end
        end

        local arg = input:match("^%S+%s+(.+)$")
        local wantAdd = arg and arg:lower():match("^add%s*(.*)$")

        if wantAdd then
            if not addon.PlayerIsMasterLooter() then
                Print(T["only the Loot Master can add items"])
                return
            end
            if #eligible == 0 then
                Print(#owed > 0
                    and T["nothing eligible in bags - every eligible copy is already owed to a winner in Loot to Trade."]
                    or T["nothing eligible in bags"])
                return
            end


            local count
            if wantAdd == "all" then
                count = #eligible
            else
                count = tonumber(wantAdd)
                if not count or count < 1 then
                    Print(T["usage: /slc bags add <number>  ||  /slc bags add all"])
                    return
                end
                count = math.min(count, #eligible)
            end

            local me = addon.Player:GetFullName("player")
            local links, bosses, encounterIDs = {}, {}, {}
            for i = 1, count do
                links[i] = eligible[i].link

                bosses[i], encounterIDs[i] =
                    addon.Encounter:ForTradeableItem(eligible[i].secondsLeft)
            end

            local added = #addon.Session:AddItems(links, me, bosses, encounterIDs)

            if #filtered > 0 then
                Print(addon.Locale.Format(addon.Locale.Plural{
                    one = "added %d item to the queue, skipped %d filtered",
                    other = "added %d items to the queue, skipped %d filtered",
                }, added, added, #filtered))
            else
                Print(addon.Locale.Format(addon.Locale.Plural{
                    one = "added %d item to the queue",
                    other = "added %d items to the queue",
                }, added, added))
            end
            if #owed > 0 then
                Print(addon.Locale.Format(addon.Locale.Plural{
                    one = "skipped %d copy already owed to a winner in Loot to Trade - click it in the bags panel to queue it anyway.",
                    other = "skipped %d copies already owed to winners in Loot to Trade - click one in the bags panel to queue it anyway.",
                }, #owed, #owed))
            end
            if addon.UI.QueueFrame then addon.UI.QueueFrame:Refresh() end
            return
        end

        if #items == 0 then Print(T["no tradeable items in bags"]) return end



        Print(addon.Locale.Format(addon.Locale.Plural{
            one = "%d tradeable item, newest first:",
            other = "%d tradeable items, newest first:",
        }, #eligible, #eligible))
        for i, entry in ipairs(eligible) do
            Print(addon.Locale.Format(T["  %d. %s  |cff808080%dm left|r"],
                i, entry.link, math.floor(entry.secondsLeft / 60)))
        end
        for _, entry in ipairs(owed) do
            Print(addon.Locale.Format(T["  -  %s  |cff73716C%dm left, owed to %s|r"],
                entry.link, math.floor(entry.secondsLeft / 60),
                entry.owedTo and Ambiguate(entry.owedTo, "short") or T["unknown"]))
        end
        for _, entry in ipairs(filtered) do
            Print(addon.Locale.Format(T["  -  %s  |cff73716C%dm left, filtered out|r"],
                entry.link, math.floor(entry.secondsLeft / 60)))
        end
        if #eligible > 0 then
            Print(T["/slc bags add <n>  or  /slc bags add all"])
        end

    elseif cmd == "history" or cmd == "h" then

        local rest = input:lower():match("^%S*%s+(%S+)")
        if rest == "text" or rest == "print" then
            local count = addon.History:Count()
            local imported = addon.HistoryImport:Count()
            Print(addon.Locale.Format(T["%d entries recorded, %d imported"], count, imported))
            if count + imported == 0 then return end
            local mine = addon.History:GetForWinner(addon.Player:GetFullName("player"))
            Print(addon.Locale.Format(T["%d awarded to you"], #mine))
            Print(T["/slc csv for the full log"])
        else
            addon.UI.HistoryFrame:Toggle()
        end


    elseif cmd == "team" or cmd == "t" then

        local rest = input:match("^%S+%s+(.+)$")
        local verb = rest and rest:lower():match("^(%S+)")

        if verb == "season" then
            local value = rest:match("^%S+%s+(.+)$")

            if not value then
                local start = addon.RaidTeam:GetSeasonStart()
                local season = tostring(addon.db.raidTeam and addon.db.raidTeam.seasonId)
                Print(start
                    and addon.Locale.Format(T["season %s, started %s"],
                        season, date("!%Y/%m/%d", start))
                    or addon.Locale.Format(
                        T["season %s, |cffE57373start date not known|r - the raid team view counts everything until it is"],
                        season))
                Print(T["  /slc team season 2026-08-01  - set it"])
                Print(T["  /slc team season clear       - forget it"])
                return
            end

            if value:lower():match("^clear") or value:lower():match("^none") then
                addon.RaidTeam:SetSeasonStart(nil)
                Print(T["season start forgotten - the raid team view now counts everything"])
                return
            end

            local epoch = addon.RaidTeam:ParseDate(value)
            if not epoch then
                Print(T["could not read that date - use 2026-08-01"])
                return
            end

            if epoch > GetServerTime() then
                Print(T["that date is in the future - nothing would be counted"])
                return
            end

            addon.RaidTeam:SetSeasonStart(epoch)
            Print(addon.Locale.Format(T["season start set to %s"],
                date("!%Y/%m/%d", epoch)))
            return
        end

        addon.UI.RaidTeamFrame:Toggle()

    elseif cmd == "set" then
        local rows, summary = addon.Gear.CurrentSetDiagnostic()
        Print("equipped set scan (cached, setID, hasBonus):")
        for _, row in ipairs(rows) do
            Print(("  slot %d  %s  %s, %s, %s"):format(
                row.slot, row.link or "empty", tostring(row.cached),
                tostring(row.setID), tostring(row.hasBonus)))
        end
        Print(summary and ("SetSummary: setID=%s count=%d"):format(
            tostring(summary.setID), summary.count) or "SetSummary: nil")

    elseif cmd == "item" or cmd == "why" then


        local links = {}
        for link in input:gmatch("(|c[^|]*|Hitem:[^|]*|h%[.-%]|h|r)") do
            links[#links + 1] = link
        end
        if #links == 0 then
            for link in input:gmatch("(|Hitem:[^|]*|h%[.-%]|h)") do
                links[#links + 1] = link
            end
        end
        if #links == 0 then
            Print("shift-click an item into the command: /slc item <link>")
            return
        end

        for _, link in ipairs(links) do
            local name, _, quality = C_Item.GetItemInfo(link)
            local itemID, _, _, equipLoc, _, classID, subClassID =
                C_Item.GetItemInfoInstant(link)

            local className = classID and C_Item.GetItemClassInfo(classID)
            local subName = classID and subClassID
                and C_Item.GetItemSubClassInfo(classID, subClassID)

            Print(("%s"):format(name or link))
            Print(("  id %s   quality %s   class %s (%s)   subclass %s (%s)"):format(
                tostring(itemID), tostring(quality),
                tostring(classID), tostring(className),
                tostring(subClassID), tostring(subName)))
            Print(("  equip slot: %s   cosmetic: %s"):format(tostring(equipLoc),
                tostring(C_Item.IsCosmeticItem(link))))

            local council = addon.Loot:IsCouncilItem(link)
            Print(("  council loot: %s"):format(
                council and "|cff66BB6Ayes|r" or "|cffE57373NO|r"))
            if not council then
                Print("  |cff73716Cthe funnel will not roll on it and it will never reach a session|r")
            end
        end


    elseif cmd == "boss" then
        local current = addon.Encounter:Current()
        Print("current boss: " .. (current or "|cff73716Cnone|r"))


        local log = addon.Encounter:GetLog()
        if #log == 0 then
            Print("no encounters within the trade window")
            return
        end
        Print(("%d encounter(s) still attributable, newest last:"):format(#log))
        for i = math.max(1, #log - 9), #log do
            local e = log[i]
            local ended = e.endedAt
                and ("%ds ago"):format(GetServerTime() - e.endedAt)
                or "|cffE57373in progress|r"
            Print(("  %s (encounter %s)  %s  %s"):format(
                tostring(e.name), tostring(e.id),
                e.endedAt and (e.looted and "looted"
                    or e.success and "kill" or "wipe") or "-",
                ended))
        end


    elseif cmd == "attendance" or cmd == "att" then
        local rest = input:match("^%S+%s+(.+)$")
        local verb = rest and rest:lower():match("^(%S+)")

        if verb == "nights" then
            local nights = addon.Attendance:GetNights()
            if #nights == 0 then
                Print(T["no raids recorded"])
                return
            end
            Print(addon.Locale.Format(T["%d night(s) recorded, newest last:"], #nights))
            for i = math.max(1, #nights - 19), #nights do
                local n = nights[i]
                Print(addon.Locale.Format(T["  %s  %d pull(s), %d kill(s)"],
                    date("!%Y/%m/%d", n.startedAt or 0), n.pulls or 0, n.kills or 0))
            end
            return
        end



        local target = rest or addon.Player:GetFullName("player")
        local record = addon.Player:Get(target)
        local name = record.fullName or target
        local since = addon.RaidTeam:GetSeasonStart()
        local att = addon.Attendance:For(name, since)

        if att.nights == 0 then
            Print(addon.Locale.Format(T["%s: no raids recorded"], Ambiguate(name, "short")))
            return
        end
        Print(addon.Locale.Format(since
            and T["%s: %d/%d nights this season (%d/%d pulls), first seen %s"]
            or T["%s: %d/%d nights (%d/%d pulls), first seen %s"],
            Ambiguate(name, "short"), att.attended, att.nights,
            att.pullsAttended, att.pulls,
            date("!%Y/%m/%d", att.firstSeen or 0)))



    elseif cmd == "coins" then
        local now = GetServerTime()
        local printed = 0
        local function PrintCoin(entry)
            printed = printed + 1
            local name = C_Item.GetItemInfo(entry.link) or entry.link
            Print(("  %-24s %s  %s (encounter %s)  %ds ago"):format(
                Ambiguate(entry.name, "short"), tostring(name),
                tostring(entry.boss or "?"), tostring(entry.encounterID or "?"),
                now - (entry.epoch or now)))
        end

        Print("pre-run buffer (last " .. addon.BonusRoll.RECENT_WINDOW / 60
            .. " minutes):")
        for _, entry in ipairs(addon.BonusRoll:GetRecent()) do PrintCoin(entry) end

        if addon.Session:IsRunning() then
            local coins = addon.Session:GetCoins()
            if #coins > 0 then
                Print("this run:")
                for _, entry in ipairs(coins) do PrintCoin(entry) end
            end
        end

        if printed == 0 then
            Print("no bonus roll results reported.")
        end


    elseif cmd == "ftest" then
        local args = input:match("^%S+%s*(.*)$") or ""
        local count = 3
        if args:match("%S") then
            count = tonumber(args:match("^%s*(%d+)%s*$"))
            if not count then
                Print(T["usage: /slc ftest [<count>]"])
                return
            end
            if count < 1 or count > addon.TestLoot.MAX then
                Print(addon.Locale.Format(T["pick between 1 and %d items: /slc ftest %d"],
                    addon.TestLoot.MAX, addon.TestLoot.MAX))
                return
            end
        end
        local links, sources = addon.TestLoot:PickDungeon(count)
        local ok, countOrWhy = addon.Session:StartTest(links, nil, sources)
        if not ok then
            Print(addon.Locale.Format(T["could not start simulated run - %s"],
                tostring(countOrWhy)))
            return
        end
        Print(addon.Locale.Format(addon.Locale.Plural{
            one = "simulated run started with %d item; awards will not be saved or traded",
            other = "simulated run started with %d items; awards will not be saved or traded",
        }, countOrWhy, countOrWhy))


    elseif cmd == "testcoin" then
        if addon.IsForever then
            Print(T["WoW: Forever has no bonus rolls."])
            return
        end


        local args = (input:match("^%S+%s*(.*)$") or ""):trim()
        local who, session = addon.BonusRoll:ParseTestCoinArgs(args)

        local item = addon.Session:GetItems()[session]
        if not item then
            Print(addon.Locale.Format(T["no item at session %d - /slc test first, or pass a session number: /slc testcoin [Name-Realm] [session]"], session))
            return
        end

        local name = who or addon.Player:GetFullName("player")
        if not name then
            Print(addon.Locale.Format(T["could not resolve %s"], tostring(who)))
            return
        end



        local ok, boss, candidate = addon.BonusRoll:TestCoin(name, session)
        if not ok then
            if boss == "candidate" then
                Print(addon.Locale.Format(T["could not match %s to a candidate on item %d; use the Name-Realm shown in the council table."],
                    tostring(name), session))
            else
                Print(T["only the Loot Master can simulate a coin in an active run."])
            end
            return
        end
        Print(addon.Locale.Format(T["simulated: %s coined %s from %s (not recorded to history)"],
            Ambiguate(candidate, "short"), item.link, tostring(boss)))

    elseif cmd == "guild" then

        Print("in a group: " .. tostring(IsInGroup())
            .. ", in a guild: " .. tostring(IsInGuild()))
        Print("gate says guild group: "
            .. tostring(addon.Loot.IsGuildGroup())
            .. " (funnel.guildGroupOnly is "
            .. ((addon.db.funnel and addon.db.funnel.guildGroupOnly)
                and "on" or "off") .. ")")
        Print("loot master shares our guild: " .. tostring(addon.Loot:SharesLootMasterGuild())
            .. ", guard holds: " .. tostring(addon.Loot:GuardReason()))



        if type(InGuildParty) ~= "function" then
            Print("|cffE57373InGuildParty() is not available on this build|r")
            return
        end

        local present, required = addon.Loot:GetGuildPartyCounts()
        if not present or not required then

            Print(IsInGroup()
                and "InGuildParty(): no counts yet - the game has not answered, or the values are restricted"
                or "InGuildParty(): no counts, and none are meaningful solo")
            return
        end
        Print(("InGuildParty(): %d of %d present are guild members, %d required"):format(present, GetNumGroupMembers(), required))

    elseif cmd == "import" then

        local Import = addon.HistoryImport


        local want = input:match("^%S+%s+(%S+)")
        local keys = {}
        if want then
            keys[1] = want:lower()
        else
            for _, source in ipairs(Import:Available()) do keys[#keys + 1] = source.key end
        end
        if #keys == 0 then
            local names = {}
            for _, source in ipairs(Import.SOURCES) do
                names[#names + 1] = addon.Locale.Format(T["%s (%s)"], source.label, source.key)
            end
            Print(addon.Locale.Format(
                T["No supported loot addon's history is loaded. Supported: %s."],
                table.concat(names, ", ")))
        else
            for _, result in ipairs(Import:FromSources(keys)) do
                Print(addon.Locale.Format(T["%s: %s"], result.label,
                    result.stats and Import:Describe(result.stats)
                        or (result.error or T["import failed"])))
            end
        end

    elseif cmd == "csv" then


        local lowered = input:lower()


        local scope = lowered:find("%f[%w]slc%f[%W]", 4) and "slc" or nil


        for word in pairs(addon.History.DELIMITERS) do
            if lowered:find("%f[%w]" .. word .. "%f[%W]", 4) then
                addon.db.csvDelimiter = word
            end
        end
        addon.ShowHistoryCSV(scope)


    elseif cmd == "queue" or cmd == "q" then
        addon.UI.QueueFrame:Toggle()


    elseif cmd == "session" or cmd == "sess" then

        local result = addon.UI.SessionPanel:Toggle()
        if result == "norun" then

            if addon.Session:IsRunning() then
                Print(T["you are not in this run - there is nothing to show you."])
            else
                Print(T["no run is active."])
            end
        end


    elseif cmd == "trades" then


        addon.UI.TradeQueueFrame:Toggle()

    elseif cmd == "config" or cmd == "options" then
        addon.UI.Options:Toggle()

    elseif cmd == "trade" then
        local who = input:match("^%S+%s+(.+)$")
        if not who then


            for _, entry in ipairs(addon.Storage:GetAll(addon.Storage.TO_TRADE)) do
                if not entry.untradeable and entry.args and entry.args.recipient then
                    who = entry.args.recipient
                    break
                end
            end
            if not who then Print(T["nothing owed to anyone"]) return end
        end
        addon.Trade:Initiate(who)

    elseif cmd == "held" then
        local held = addon.Storage:GetAll()
        if #held == 0 then Print(T["nothing held"]) return end

        local clocks = addon.Storage:Clocks(held)
        for _, entry in ipairs(held) do
            local remaining = clocks[entry]
            local recipient = entry.category == addon.Storage.TO_TRADE
                and entry.args and entry.args.recipient

            local state = not recipient and T["held"]
                or entry.untradeable and addon.Locale.Format(
                    T["owed to %s, no longer tradeable"], Ambiguate(recipient, "short"))
                or addon.Locale.Format(T["owed to %s"], Ambiguate(recipient, "short"))
            Print(addon.Locale.Format(T["%s  %s  %s"], entry.link, state,
                remaining and addon.Locale.Format(T["%dm left"],
                    math.floor(remaining / 60)) or T["no timer"]))
        end


    elseif cmd == "names" then
        local P = addon.Player
        local function show(...)
            local parts = {}
            for i = 1, select("#", ...) do
                local v = select(i, ...)
                parts[i] = (issecretvalue and issecretvalue(v)) and "<secret>"
                    or ("'" .. tostring(v) .. "'")
            end
            return table.concat(parts, ", ")
        end
        local function line(text)
            Print(text)
            addon.Log:I("Names", text)
        end
        line(("build %s  forever=%s  realm %s  normalized %s"):format(
            show(GetBuildInfo()), tostring(P.IS_FOREVER),
            show(GetRealmName()), show(GetNormalizedRealmName and GetNormalizedRealmName())))
        local units = { "player", "target", "NPC" }
        for i = 1, GetNumGroupMembers() do
            units[#units + 1] = IsInRaid() and ("raid" .. i) or (i < 5 and ("party" .. i)) or nil
        end
        for _, unit in ipairs(units) do
            if UnitExists(unit) then
                local guid = UnitGUID(unit)
                local full = P:GetFullName(unit)
                local short = full and Ambiguate(full, "none")
                line(("%s  UnitName %s  UnitFullName %s  GetUnitName %s"):format(unit,
                    show(UnitName(unit)), show(UnitFullName(unit)), show(GetUnitName(unit, true))))
                line(("  byGUID %s  slc %s  Ambiguate %s  UnitExists(that) %s  Get=same %s"):format(
                    show(select(6, GetPlayerInfoByGUID(guid))), show(full), show(short),
                    tostring(short and UnitExists(short)),
                    tostring(full ~= nil and P:Get(full).guid == guid)))
            end
        end
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                line(("raid roster %d  %s"):format(i, show((GetRaidRosterInfo(i)))))
            end
        end
        line("now /slc ping: its 'ping from' line is the addon-message sender as received")

    elseif cmd == "status" then
        Print(("restricted=%s  queue=%d  leader=%s  lootmaster=%s%s  isML=%s  candidates=%d")
            :format(tostring(addon.Restrictions:IsBlocked()),
                addon.Restrictions:GetQueueDepth(),
                tostring(addon.GetGroupLeader()),
                tostring(addon.GetMasterLooter()),
                addon.IsLootDelegated() and " (delegated)" or "",
                tostring(addon.PlayerIsMasterLooter()),
                (function()
                    local n = 0
                    for _ in pairs(addon.GetCandidates()) do n = n + 1 end
                    return n
                end)()))

    elseif cmd == "version" or cmd == "ver" then

        addon.Version:Poll()

        Print(addon.Locale.Format(T["you are on v%s; newest seen in the group is v%s"],
            addon.Version.OWN, addon.Version:Highest()))

        local rows = addon.Version:Survey()
        if #rows == 0 then
            Print(T["no candidates resolved yet."])
        end
        for _, row in ipairs(rows) do
            local short = Ambiguate(row.name, "short")
            if not row.version then

                Print(addon.Locale.Format(T["  %s - |cff808080no reply yet|r"], short))
            elseif row.behind then
                Print(addon.Locale.Format(T["  %s - |cffff8040v%s (behind)|r"], short, row.version))
            else
                Print(addon.Locale.Format(T["  %s - v%s"], short, row.version))
            end
        end

    elseif cmd == "taint" then
        local counts = addon.Log:GetBlockedCounts()
        local any = false
        for key, count in pairs(counts) do
            Print(addon.Locale.Format(T["blocked x%d  %s"], count, tostring(key):gsub("|", "||")))
            any = true
        end
        if not any then Print(T["no blocked actions recorded."]) end

    elseif cmd == "" then


        addon.UI.Options:Toggle()


    elseif cmd == "help" then
        PrintHelp(input:lower():match("^%S+%s+(%S+)") == "dev")

    else
        Print(addon.Locale.Format(T["unknown command '%s' - /slc help for the list"],
            (cmd:gsub("|", "||"))))
    end
end
