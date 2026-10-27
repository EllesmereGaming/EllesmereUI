if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end





SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local RaidPrompt = {}
UI.RaidPrompt = RaidPrompt

local S, L
local frame, questionText, sectionText, bodyText, silenceRow, buttonRow
local onAccept, onDecline



local askedFor = nil

local guardAskedFor = nil
local showing = nil

local function AskedKey(groupKey)
    return groupKey .. "|" .. tostring(addon.GetMasterLooter())
        .. "|" .. tostring(addon.GetGroupLeader())
end



local open = false

local function Retire()
    open, showing = false, nil
    if frame and frame:IsShown() then frame:Hide() end
end





local function Build()
    frame = S.Window("SimpleLootCouncilRaidPrompt", "raidPrompt", 470, 200,
        T["Simple Loot Council"])


    local content = frame.Content
    local cursor = addon.Layout.Cursor(content)


    questionText = cursor:Add(L.Paragraph, "", S.fontButton)
    sectionText = cursor:Add(L.Paragraph, "", S.fontNotice)
    cursor:Gap(12)
    bodyText = cursor:Add(L.Paragraph, "", S.fontSmall)
    bodyText:SetTextColor(S.Unpack(S.color.textFaint))

    silenceRow = addon.Layout.Row(content, 0, cursor.width, 0, S.size.ROW_H)
    silenceRow.Box = S.Checkbox(silenceRow, S.size.CTRL_H, function() end)
    addon.Pixel.Point(silenceRow.Box, "LEFT", silenceRow, "LEFT", 0, 0)
    silenceRow:AdoptHover(silenceRow.Box)

    silenceRow.LabelText = S.Label(silenceRow, S.fontSmall, "LEFT")
    silenceRow.LabelText:SetText(T["Don't ask again - just take part"])
    addon.Pixel.Point(silenceRow.LabelText, "LEFT", silenceRow.Box, "RIGHT", S.size.GAP, 0)
    addon.Pixel.Point(silenceRow.LabelText, "RIGHT", silenceRow, "RIGHT", 0, 0)


    silenceRow:SetScript("OnMouseUp", function()
        silenceRow.Box:SetChecked(not silenceRow.Box:GetChecked())
    end)

    local half = (cursor.width - S.size.GAP) / 2
    buttonRow = addon.Layout.ButtonRow(content, 0, cursor.width, 0, {
        {
            key = "Yes", text = T["Yes"], opts = { primary = true, width = half },
            onClick = function()
                if silenceRow:IsShown() then
                    addon.db.raidPrompt.silence = silenceRow.Box:GetChecked()
                        and true or false


                    addon.UI.Options:Refresh()
                end
                Retire()
                if onAccept then onAccept() end
            end,
        },
        {
            key = "No", text = T["No"], opts = { width = half },
            onClick = function()
                Retire()
                if onDecline then onDecline() end
            end,
        },
    })

    frame:HookScript("OnHide", function()
        if not open then return end
        local kind, decline = showing, onDecline
        addon.AutoClose:AfterHide(function(swept)


            if not open or frame:IsShown() then return end


            if swept and IsInGroup() then
                addon.Log:D("UI", "raid prompt closed by the game - asking again")
                frame:Show()
            else
                open, showing = false, nil
                if not swept and kind == "raider" and decline then
                    addon.Log:I("UI", "raid prompt closed without an answer - counted as No")
                    decline()
                end
            end
        end)
    end)
end


local reflowing = false
local reflowSilence, reflowSection

local function TextHeight(text, fallback)
    local height = text:GetStringHeight()
    if issecretvalue and issecretvalue(height) then height = nil end
    if type(height) ~= "number" or height <= 0 then return fallback end
    return math.ceil(height)
end

local function Reflow(allowSilence, showSection, settled)
    local content = frame.Content
    local cursor = addon.Layout.Cursor(content)


    questionText:SetWidth(addon.Pixel.Snap(cursor.width))
    addon.Pixel.Point(questionText, "TOPLEFT", content, "TOPLEFT", 0, cursor:Y())
    cursor.y = cursor.y - TextHeight(questionText, 18)

    sectionText:SetShown(showSection and true or false)
    if showSection then
        cursor:Gap(6)
        sectionText:SetWidth(addon.Pixel.Snap(cursor.width))
        addon.Pixel.Point(sectionText, "TOPLEFT", content, "TOPLEFT", 0, cursor:Y())
        cursor.y = cursor.y - TextHeight(sectionText, 18)
    end

    cursor:Gap(12)

    bodyText:SetWidth(addon.Pixel.Snap(cursor.width))
    addon.Pixel.Point(bodyText, "TOPLEFT", content, "TOPLEFT", 0, cursor:Y())
    cursor.y = cursor.y - TextHeight(bodyText, 42)

    cursor:Gap(S.size.SECTION)

    silenceRow:SetShown(allowSilence and true or false)
    if allowSilence then
        addon.Pixel.Point(silenceRow, "TOPLEFT", content, "TOPLEFT", 0, cursor:Y())
        cursor:Gap(S.size.ROW_H)
        cursor:Gap(S.size.ITEM_GAP)
    end

    addon.Pixel.Point(buttonRow, "TOPLEFT", content, "TOPLEFT", 0, cursor:Y())
    cursor:Gap(S.size.BTN_H)



    frame:SetHeight(addon.Pixel.Snap(
        frame.HeaderHeight + S.size.PAD + cursor:Consumed() + S.size.PAD))


    reflowSilence, reflowSection = allowSilence, showSection
    if not settled and not reflowing then
        reflowing = true
        addon.Pixel.AfterLayout(function()
            reflowing = false
            if frame and frame:IsShown() then
                Reflow(reflowSilence, reflowSection, true)
            end
        end)
    end
end



local function Ask(kind, question, section, body, allowSilence, accept, decline, atCursor)
    if not frame then Build() end

    questionText:SetText(question)
    sectionText:SetText(section or "")
    sectionText:SetTextColor(S.Unpack(S.color.bad))
    bodyText:SetText(body)
    onAccept, onDecline = accept, decline

    silenceRow.Box:SetChecked(addon.db.raidPrompt.silence and true or false)
    Reflow(allowSilence, section ~= nil)
    if atCursor then frame:PlaceAtCursor() else frame:RestorePosition() end

    open, showing = true, kind
    frame:Show()
end





local function DeclinedMessage()
    addon.Chat.Print(addon.Locale.Format(
        T["you declined to take part in Simple Loot Council for this raid."]))
end

local function AskLootMaster(atCursor)
    local masterLoot = addon.Loot:UsesMasterLoot()
    Ask("lootMaster", addon.Locale.Format(T["Use Simple Loot Council for this raid?"]),
        not masterLoot and T["Accepting also activates the group-loot funnel."] or nil,
        masterLoot
            and T["This enables Simple Loot Council for the group on Master Looter: nobody's rolls are passed. Loot items to yourself, and the council distributes what lands in your bags."]
            or T["You roll Need on group loot, everyone taking part passes, and the council distributes what lands in your bags."],
        false,
        function() RaidPrompt:Activate() end,
        function()

            if addon.Loot.handling then
                addon.Loot:SetHandling(false)
            else
                addon.Loot:RecordDecision(false)
            end
            DeclinedMessage()
        end, atCursor)
end


local function CollectorName()
    local collector = addon.GetMasterLooter()
    return collector and Ambiguate(collector, "short") or "?"
end


local function AnnounceJoined()
    local passing = not addon.Loot:GuardReason()
    addon.Chat.Print(addon.Locale.Format(
        passing and T["Simple Loot Council is active for this raid - %s is collecting the loot, and this addon passes your group-loot rolls for the council to distribute."]
            or T["Simple Loot Council is active for this raid - %s is collecting the loot for the council."],
        CollectorName()))
end

local function AskRaider()
    local collector = addon.GetMasterLooter()
    local question
    if collector then
        question = addon.Locale.Format(T["%s is running Simple Loot Council for this raid."],
            Ambiguate(collector, "short"))
    else
        question = addon.Locale.Format(
            T["The Loot Master is running Simple Loot Council for this raid."])
    end
    Ask("raider", question,
        T["Accepting also activates your group-loot funnel."],
        T["Taking part means this addon passes your group-loot rolls on your behalf, so the council can distribute the item instead. You still respond and can still be awarded it."],
        true,
        function()
            addon.Loot:RecordDecision(true)
            AnnounceJoined()
            addon.Callbacks:Invalidate("options")

            RaidPrompt:Evaluate()
        end,
        function()
            addon.Loot:RecordDecision(false)
            DeclinedMessage()
            addon.Callbacks:Invalidate("options")
        end)
end



local function AskGuard()
    local reason = addon.Loot:GuardReason()
    local name = CollectorName()
    Ask("guard", T["Disable your guild loot funnel guard?"],
        reason == "group" and T["This is not a guild group."]
            or addon.Locale.Format(T["%s is not in your guild."], name),
        addon.Locale.Format(T["While the guard is on, this addon does not pass your group-loot rolls to %s. Disable it to take part in the funnel, or keep it and roll on group loot yourself. You still respond to the council either way."], name),
        false,
        function()
            addon.db.funnel.guildGroupOnly = false
            addon.Log:I("Loot", "guild loot funnel guard disabled from the prompt -", tostring(reason))
            if addon.UI.Options then addon.UI.Options:Refresh() end
            addon.Chat.Print(addon.Locale.Format(
                T["guild loot funnel guard disabled - this addon now passes your group-loot rolls to %s for the council."], name))
        end,
        function()
            addon.Loot:KeepGuard()
            addon.Chat.Print(addon.Locale.Format(
                T["guild loot funnel guard kept - you roll on group loot yourself while %s collects for the council."], name))
        end)
end







function RaidPrompt:AskToActivate()
    local key = addon.Loot:DecisionKey()
    if not key or not addon.PlayerIsMasterLooter() then return end
    askedFor = AskedKey(key)
    AskLootMaster(true)
end



function RaidPrompt:AskToDeactivate()
    if not addon.PlayerIsMasterLooter() or not addon.Loot.handling then return end
    Ask("deactivate", T["Disable SLC?"], nil,
        T["Are you sure you want to disable SLC for this run?"],
        false,
        function() RaidPrompt:Deactivate() end,
        nil, true)
end



function RaidPrompt:AskToEnableFunnel()
    if addon.PlayerIsMasterLooter() or not addon.Loot.handling
        or addon.Loot:GetDecision() ~= false or addon.Loot:FunnelNever() then
        return
    end
    Ask("enable", T["Enable Funnel"], nil, T["Take part in the active SLC group?"], false,
        function()
            addon.Loot:RecordDecision(true)
            AnnounceJoined()
            addon.Callbacks:Invalidate("options")
            RaidPrompt:Evaluate()
        end,
        nil, true)
end



function RaidPrompt:SetTakingPart(on)
    if addon.PlayerIsMasterLooter() or not addon.Loot.handling then return end
    if showing == "raider" or showing == "enable" then Retire() end
    addon.Loot:RecordDecision(on and true or false)
    if on then
        AnnounceJoined()
    else
        DeclinedMessage()
    end
    addon.Callbacks:Invalidate("options")
    if on then RaidPrompt:Evaluate() end
end


function RaidPrompt:Activate(skipChat)
    if not IsInRaid() or not addon.PlayerIsMasterLooter() then return false end
    Retire()
    if not skipChat then
        addon.Chat.Print(T["SLC is now active for this group"])
    end
    addon.Loot:SetHandling(true)
    return true
end


function RaidPrompt:Deactivate(skipChat)
    if not IsInGroup() or not addon.PlayerIsMasterLooter() then return false end
    Retire()
    if not skipChat then
        addon.Chat.Print(T["SLC has been deactivated for this group"])
    end
    addon.Loot:SetHandling(false, addon.Session:GetRunId())
    return true
end







function RaidPrompt:Evaluate()
    if not IsInGroup() then return end
    local key = addon.Loot:DecisionKey()
    if not key then
        Retire()
        askedFor, guardAskedFor = nil, nil
        if addon.Loot.handling and addon.PlayerIsMasterLooter() then
            addon.Loot:SetHandling(false)
        end
        return
    end
    local asked = AskedKey(key)

    if addon.PlayerIsMasterLooter() then



        addon.Session:RecoverPersisted()


        local runMaster = addon.Session:GetRunLootMaster()
        if runMaster and addon.Player:IsSame(runMaster, addon.Player:GetFullName("player")) then
            Retire()
            askedFor = asked

            local runId = addon.Session:GetRunId()
            if runId ~= nil and addon.Loot:GetDecision() == false
                and addon.Loot:DecisionRun() == runId then
                return
            end
            if not addon.Loot.handling or addon.Loot:GetDecision() ~= true then
                addon.Loot:SetHandling(true)
            end
            return
        end



        local decision = addon.Loot:GetDecision()
        if decision ~= nil then
            Retire()
            askedFor = asked
            if decision and not addon.Loot.handling then
                addon.Chat.Print(addon.Locale.Format(
                    T["still active for this raid - you said yes earlier."]))
                addon.Loot:SetHandling(true)
            end
            return
        end


        if addon.db.raidPrompt.autoHandover and addon.Loot:HandedOverActive() then
            askedFor = asked
            addon.Chat.Print(addon.Locale.Format(
                T["SLC stays active for this raid - you were handed loot while it was in use."]))
            RaidPrompt:Activate(true)
            return
        end


        if addon.db.raidPrompt.neverLead then
            if showing == "lootMaster" then Retire() end
            return
        end
        if askedFor == asked then return end
        askedFor = asked
        AskLootMaster()
        return
    end



    if not addon.Loot.handling or not addon.Loot.funnelArmed or addon.Loot:FunnelNever() then
        Retire()
        askedFor, guardAskedFor = nil, nil
        return
    end


    local decision = addon.Loot:GetDecision()
    if decision == nil then
        if not addon.db.raidPrompt.silence then
            if askedFor == asked then return end
            askedFor = asked
            AskRaider()
            return
        end

        if showing == "raider" then Retire() end
        addon.Loot:RecordDecision(true)
        AnnounceJoined()
        decision = true
    end
    if decision ~= true then return end



    if not addon.Loot:GuardReason() or addon.Loot:GuardKept() then

        if showing == "guard" then Retire() end
        guardAskedFor = nil
        return
    end
    if guardAskedFor == asked then return end
    guardAskedFor = asked
    AskGuard()
end


function RaidPrompt:SyncSilence()
    if silenceRow then
        silenceRow.Box:SetChecked(addon.db.raidPrompt.silence and true or false)
    end
end

function RaidPrompt:Init()
    S = addon.Style
    L = addon.Layout



    local wasRaid = nil
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(3, function() RaidPrompt:Evaluate() end)
            return
        end
        local isRaid = IsInRaid() and true or false
        if wasRaid ~= nil and isRaid ~= wasRaid then
            wasRaid = isRaid
            C_Timer.After(1, function() RaidPrompt:Evaluate() end)
            return
        end
        wasRaid = isRaid
    end)


    addon.Callbacks:Register("HandlingChanged", function()
        RaidPrompt:Evaluate()
    end)

    addon.Callbacks:Register("GuildGroupChanged", function()
        RaidPrompt:Evaluate()
    end)
    addon.Callbacks:Register("RunRecovered", function()
        RaidPrompt:Evaluate()
    end)


    addon.Callbacks:Register("LootMasterChanged", function()
        Retire()

        askedFor, guardAskedFor = nil, nil
        RaidPrompt:Evaluate()
    end)

    addon.Log:I("UI", "raid prompt ready")
end
