if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Loot = {}
addon.Loot = Loot



local ROLL_PASS, ROLL_NEED, ROLL_GREED, ROLL_TRANSMOG = 0, 1, 2, 4



local slotCache = {}


local cleared = {}




local viaRoll = {}
local VIA_ROLL_TTL = 120

local function MarkViaRoll(link)
    local now = GetTime()
    for other, at in pairs(viaRoll) do
        if now - at > VIA_ROLL_TTL then viaRoll[other] = nil end
    end
    viaRoll[link] = now
end

local function WasViaRoll(link)
    local at = viaRoll[link]
    return at ~= nil and (GetTime() - at) <= VIA_ROLL_TTL
end










local MIN_QUALITY = Enum.ItemQuality.Rare




local TIER_TOKENS = {


    [249347] = true, [249348] = true, [249349] = true, [249350] = true,

    [249351] = true, [249352] = true, [249353] = true, [249354] = true,

    [249355] = true, [249356] = true, [249357] = true, [249358] = true,

    [249359] = true, [249360] = true, [249361] = true, [249362] = true,

    [249363] = true, [249364] = true, [249365] = true, [249366] = true,




    [270910] = true, [270911] = true, [270912] = true, [270913] = true,

    [270914] = true, [270915] = true, [270916] = true, [270917] = true,

    [270918] = true, [270919] = true, [270920] = true, [270921] = true,

    [270922] = true, [270923] = true, [270924] = true, [270925] = true,

    [270926] = true, [270927] = true, [270928] = true, [270929] = true,
}



function Loot:IsTierToken(itemID)
    return TIER_TOKENS[itemID] == true
end



local FOREVER_ITEMS = {}
for _, id in ipairs({
    17204, 18563, 18564, 17203, 19017, 18703,
    18423, 18422, 18705,
    19003, 19002, 18562,
    19802,
    21220, 20884, 20888, 20885, 20889, 20886, 20890,
    20928, 20932, 20926, 20930, 20927, 20931, 20929, 20933,
    21221, 21232, 21237,
    22726, 22520,
}) do FOREVER_ITEMS[id] = true end
for id = 19716, 19724 do FOREVER_ITEMS[id] = true end
for id = 22349, 22372 do FOREVER_ITEMS[id] = true end

function Loot:IsForeverItem(itemID)
    return addon.IsForever and FOREVER_ITEMS[itemID] == true
end


local EQUIP_LOCS = {
    INVTYPE_HEAD = true,
    INVTYPE_NECK = true,
    INVTYPE_SHOULDER = true,
    INVTYPE_CHEST = true,
    INVTYPE_ROBE = true,
    INVTYPE_WAIST = true,
    INVTYPE_LEGS = true,
    INVTYPE_FEET = true,
    INVTYPE_WRIST = true,
    INVTYPE_HAND = true,
    INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true,
    INVTYPE_CLOAK = true,
    INVTYPE_WEAPON = true,
    INVTYPE_SHIELD = true,
    INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_HOLDABLE = true,
    INVTYPE_RANGED = true,
    INVTYPE_RANGEDRIGHT = true,
}



local ARMOR_SUBCLASSES = {
    [Enum.ItemArmorSubclass.Generic] = true,
    [Enum.ItemArmorSubclass.Cloth] = true,
    [Enum.ItemArmorSubclass.Leather] = true,
    [Enum.ItemArmorSubclass.Mail] = true,
    [Enum.ItemArmorSubclass.Plate] = true,
    [Enum.ItemArmorSubclass.Shield] = true,
}


local WEAPON_SUBCLASSES = {
    [Enum.ItemWeaponSubclass.Axe1H] = true,
    [Enum.ItemWeaponSubclass.Axe2H] = true,
    [Enum.ItemWeaponSubclass.Bows] = true,
    [Enum.ItemWeaponSubclass.Guns] = true,
    [Enum.ItemWeaponSubclass.Mace1H] = true,
    [Enum.ItemWeaponSubclass.Mace2H] = true,
    [Enum.ItemWeaponSubclass.Polearm] = true,
    [Enum.ItemWeaponSubclass.Sword1H] = true,
    [Enum.ItemWeaponSubclass.Sword2H] = true,
    [Enum.ItemWeaponSubclass.Warglaive] = true,
    [Enum.ItemWeaponSubclass.Staff] = true,
    [Enum.ItemWeaponSubclass.Unarmed] = true,
    [Enum.ItemWeaponSubclass.Dagger] = true,
    [Enum.ItemWeaponSubclass.Crossbow] = true,
    [Enum.ItemWeaponSubclass.Wand] = true,
}


if addon.IsForever then
    EQUIP_LOCS.INVTYPE_RELIC = true
    EQUIP_LOCS.INVTYPE_THROWN = true
    ARMOR_SUBCLASSES[Enum.ItemArmorSubclass.Libram] = true
    ARMOR_SUBCLASSES[Enum.ItemArmorSubclass.Idol] = true
    ARMOR_SUBCLASSES[Enum.ItemArmorSubclass.Totem] = true
    WEAPON_SUBCLASSES[Enum.ItemWeaponSubclass.Thrown] = true
end

local function IsEquippable(equipLoc, classID, subClassID, isCosmetic)


    if isCosmetic ~= false then return false end
    if EQUIP_LOCS[equipLoc] ~= true then return false end

    if classID == Enum.ItemClass.Armor then
        return ARMOR_SUBCLASSES[subClassID] == true
    end
    if classID == Enum.ItemClass.Weapon then
        return WEAPON_SUBCLASSES[subClassID] == true
    end
    return false
end

local function IsAllowedKind(itemID, equipLoc, classID, subClassID, isCosmetic)

    if IsEquippable(equipLoc, classID, subClassID, isCosmetic) then return true end



    if classID == Enum.ItemClass.Reagent
        and subClassID == Enum.ItemReagentSubclass.ContextToken then
        return true
    end



    return Loot:IsTierToken(itemID) or Loot:IsForeverItem(itemID)
end

function Loot:IsCouncilItem(link)
    if not link then return false end

    local _, _, quality = C_Item.GetItemInfo(link)


    if quality == nil or quality < MIN_QUALITY then return false end

    local itemID, _, _, equipLoc, _, classID, subClassID =
        C_Item.GetItemInfoInstant(link)
    if not itemID or classID == nil or subClassID == nil then return false end

    local isCosmetic = C_Item.IsCosmeticItem(link)
    if not IsAllowedKind(itemID, equipLoc, classID, subClassID, isCosmetic) then
        return false
    end


    for _, ignored in ipairs(addon.db.ignoredItems or {}) do
        if addon.Storage.ItemsMatch(link, ignored) then return false end
    end

    return true
end







local function ReportIfTradeable(link)
    addon.Storage:WatchForItem(link, function(bag, slot, secondsLeft)
        if not bag then
            addon.Log:D("Loot", "never found in bags", link)
            return
        end

        if not secondsLeft or secondsLeft <= 0 then
            addon.Log:D("Loot", "not tradeable, ignoring", link)
            return
        end

        addon.Log:I("Loot", "tradeable", link, secondsLeft .. "s")



        local boss, encounterID = addon.Encounter:ForTradeableItem(secondsLeft)
        addon.Comms:Send("tradeable", {
            link = link,
            secondsLeft = secondsLeft,
            boss = boss,
            encounterID = encounterID,
        }, nil, true)
    end)
end





local function CacheLootSlots()
    wipe(slotCache)
    wipe(cleared)

    local count = GetNumLootItems() or 0
    for slot = 1, count do
        if GetLootSlotType(slot) == Enum.LootSlotType.Item then
            local link = GetLootSlotLink(slot)
            if link then
                slotCache[slot] = link
            end
        end
    end
end

local function OnSlotCleared(slot)
    if cleared[slot] then

        return
    end
    cleared[slot] = true

    local link = slotCache[slot]
    if not link then return end
    if WasViaRoll(link) then return end
    if not Loot:IsCouncilItem(link) then return end


    C_Timer.After(2, function() ReportIfTradeable(link) end)
end








local function ScanRollFrames()
    local ended, open = {}, 0
    local container = GroupLootContainer
    if not container or type(container.rollFrames) ~= "table" then return ended, open end

    for _, rollFrame in pairs(container.rollFrames) do
        if type(rollFrame) == "table" and rollFrame.rollID and rollFrame.IsShown
            and rollFrame:IsShown() then
            if GetLootRollItemInfo(rollFrame.rollID) or rollFrame.NeedRollAnimFinishedCallback then
                open = open + 1
            else
                ended[#ended + 1] = rollFrame
            end
        end
    end
    return ended, open
end




function Loot:ClearRollFrames()
    if InCombatLockdown() then return nil, "combat" end

    local ended = ScanRollFrames()
    for _, rollFrame in ipairs(ended) do
        addon.Log:I("Loot", "clearing roll frame", rollFrame.rollID)
        GroupLootFrame_Remove(rollFrame)
    end


    local _, open = ScanRollFrames()
    addon.Log:I("Loot", "clearframe:", #ended, "cleared,", open, "still open")
    return #ended, open
end









local NEVER_FUNNEL = {
    [209035] = "Hearthstone of the Flame",
    [236687] = "Explosive Hearthstone",
    [246565] = "Cosmic Hearthstone",
    [264672] = "Cosmic Ritual Stone",
    [264313] = "Madcap Redcap",
    [264367] = "Mycomancer's Hearthspore",
    [268280] = "Sporelord's Shroom Cap",
}





local inGuildParty = false


local guildPresent, guildRequired = nil, nil


local issecretvalue = issecretvalue

local function ReadGuildParty()
    if type(InGuildParty) ~= "function" then return nil end
    local ok, isGuildGroup, present, required = pcall(InGuildParty)
    if not ok then return nil end

    if issecretvalue and (issecretvalue(isGuildGroup) or issecretvalue(present)
        or issecretvalue(required)) then
        return nil
    end
    present, required = tonumber(present), tonumber(required)




    if not required or required <= 0 then return isGuildGroup and true or false end

    return isGuildGroup and true or false, present, required
end


local guildChangePending = false
local function GuildStateChanged()
    if guildChangePending then return end
    guildChangePending = true
    C_Timer.After(0.5, function()
        guildChangePending = false
        if addon.Callbacks then addon.Callbacks:Fire("GuildGroupChanged") end
    end)
end


local function RefreshGuildParty()
    local isGuildGroup, present, required = ReadGuildParty()
    if isGuildGroup == nil then return end

    guildPresent, guildRequired = present, required
    if inGuildParty ~= isGuildGroup then
        inGuildParty = isGuildGroup
        addon.Log:I("Loot", "guild group is now", tostring(inGuildParty),
            "(read directly)", tostring(present), "of", tostring(required))
        GuildStateChanged()
    end
end


local function IsGuildGroup()
    return inGuildParty and true or false
end
Loot.IsGuildGroup = IsGuildGroup



function Loot:GetGuildPartyCounts()
    RefreshGuildParty()
    return guildPresent, guildRequired
end



local lootMasterGuild = {}


function Loot:SharesLootMasterGuild()
    local lootMaster = addon.GetMasterLooter()
    if not lootMaster then return nil end
    if addon.Player:IsSelf(lootMaster) then return true end
    if not IsInGuild() then return false end
    local mine, _, _, myRealm = GetGuildInfo("player")
    if not mine or (issecretvalue and (issecretvalue(mine) or issecretvalue(myRealm))) then
        return nil
    end
    local unit = addon.Player:UnitFor(lootMaster)
    local theirs, theirRealm
    if unit then theirs, _, _, theirRealm = GetGuildInfo(unit) end
    if issecretvalue and (issecretvalue(theirs) or issecretvalue(theirRealm)) then theirs = nil end
    if not theirs then
        local known = lootMasterGuild[lootMaster]
        if not known then return nil end
        theirs, theirRealm = known.name, known.realm
    else
        lootMasterGuild[lootMaster] = { name = theirs, realm = theirRealm }
    end
    return theirs == mine and (theirRealm or "") == (myRealm or "")
end



function Loot:GuardReason()
    if not addon.db.funnel or not addon.db.funnel.guildGroupOnly then return nil end
    if not IsGuildGroup() then return "group" end
    if Loot:SharesLootMasterGuild() ~= true then return "guild" end
    return nil
end


local function FunnelRole()
    if not addon.Loot.handling then return nil end
    if not addon.Loot.funnelArmed then return nil end
    if not IsInGroup() then return nil end

    if Loot:UsesMasterLoot() then return nil end
    if addon.PlayerIsMasterLooter() then return "need" end

    if Loot:GetDecision() ~= true then return nil end

    if Loot:GuardReason() then return nil end
    return "pass"
end



local deferredRolls = {}

local function OnStartLootRoll(rollID, resumed)

    local role = FunnelRole()
    if not role then

        local guard = addon.Loot.handling and IsInGroup() and Loot:GetDecision() == true
            and Loot:GuardReason()
        if guard then
            addon.Log:I("Loot", "funnel idle: guild loot funnel guard holds -", guard)
        else
            addon.Log:D("Loot", "funnel idle: no role (not handling, not taking part, or solo)")
        end
        return
    end

    local link = GetLootRollItemLink(rollID)
    if not link then
        addon.Log:W("Loot", "funnel: roll", rollID, "has no item link")
        return
    end


    local builtIn = NEVER_FUNNEL[addon.Storage.ItemID(link)]
    if builtIn then
        addon.Log:I("Loot", "funnel skipping built-in exception", builtIn, link)
        return
    end

    for _, ignored in ipairs(addon.db.funnel.ignore or {}) do
        if addon.Storage.ItemsMatch(link, ignored) then
            addon.Log:I("Loot", "funnel skipping exception item", link)
            return
        end
    end





    if not C_Item.IsItemDataCachedByID(link) and resumed then
        addon.Log:W("Loot", "funnel: item data still not cached after one wait, giving up", link)
        return
    end
    if not C_Item.IsItemDataCachedByID(link) and not deferredRolls[rollID] then
        deferredRolls[rollID] = link
        addon.Log:D("Loot", "funnel: item data not cached, waiting", link)
        Item:CreateFromItemLink(link):ContinueOnItemLoad(function()
            local pending = deferredRolls[rollID]
            deferredRolls[rollID] = nil
            if pending ~= link then return end
            if GetLootRollItemLink(rollID) ~= link then
                addon.Log:D("Loot", "funnel: roll", rollID, "gone before item data loaded")
                return
            end
            local ok, err = pcall(OnStartLootRoll, rollID, true)
            if not ok then addon.Log:Bug("Loot", tostring(err)) end
        end)
        return
    end
    deferredRolls[rollID] = nil

    if not Loot:IsCouncilItem(link) then

        local _, _, quality = C_Item.GetItemInfo(link)
        local itemID, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
        addon.Log:I("Loot", "funnel skipping non-council item", link,
            "id", tostring(itemID),
            "class", tostring(classID), "subclass", tostring(subClassID),
            "quality", tostring(quality))
        return
    end

    local _, _, _, _, _, canNeed, canGreed, _, _, _, _, _, canTransmog =
        GetLootRollItemInfo(rollID)

    local rollType
    if role == "pass" then
        rollType = ROLL_PASS
    elseif canNeed then
        rollType = ROLL_NEED
    elseif canTransmog then

        rollType = ROLL_TRANSMOG
    elseif canGreed then
        rollType = ROLL_GREED
    else

        addon.Log:W("Loot", "funnel: no roll type available for", link,
            "need", tostring(canNeed), "greed", tostring(canGreed),
            "transmog", tostring(canTransmog))
        return
    end

    MarkViaRoll(link)



    C_Timer.After(0.05, function()
        addon.Log:I("Loot", "funnel roll", role, rollType, link)
        RollOnLoot(rollID, rollType)
    end)
end






function Loot.MasterLootAvailable()
    local lootMethod = Enum.LootMethod and Enum.LootMethod.Masterlooter
    if not lootMethod or not C_PartyInfo or not C_PartyInfo.IsLootMethodAvailable then
        return false
    end
    return C_PartyInfo.IsLootMethodAvailable(lootMethod) == true
end


function Loot:UsesMasterLoot()
    return addon.GroupOnMasterLoot ~= nil and addon.GroupOnMasterLoot()
end



local function FunnelWanted()
    return not Loot:UsesMasterLoot()
end







function Loot:RearmFunnel()
    if not addon.PlayerIsMasterLooter() or not Loot.handling then return end
    local armed = FunnelWanted()
    addon.Comms:Send("handling", { on = true, funnel = armed }, nil, true)

    Loot:ApplyHandling(true, addon.Player:GetFullName("player"), armed, true)
end

function Loot:SetHandling(on, runId)
    if not addon.PlayerIsMasterLooter() then return end



    local wanted = on and true or false

    Loot:RecordDecision(wanted, runId)
    local armed = wanted and FunnelWanted()
    addon.Comms:Send("handling", { on = wanted, funnel = armed and true or false }, nil, true)
    Loot:ApplyHandling(wanted, addon.Player:GetFullName("player"), armed)
end











function Loot:DecisionKey()
    if not IsInGroup() then return nil end
    return IsInRaid() and "raid" or "party"
end


function Loot:RecordDecision(answer, runId)
    if not addon.db or not addon.db.raidPrompt then return end
    local key = Loot:DecisionKey()
    local lootMaster = addon.GetMasterLooter()
    if not key or not lootMaster then return end

    addon.db.raidPrompt.handover = nil
    addon.db.raidPrompt.decision = {
        key = key, lootMaster = lootMaster, leader = addon.GetGroupLeader(),
        answer = answer and true or false, run = runId,
    }
    addon.Log:I("Loot", "group decision", tostring(answer), "in a", key,
        "under", tostring(lootMaster), runId and ("for run " .. tostring(runId)) or "")
end



function Loot:HandedOverActive()
    local handover = addon.db and addon.db.raidPrompt and addon.db.raidPrompt.handover
    if type(handover) ~= "table" then return false end
    if handover.key ~= Loot:DecisionKey() then return false end
    local lootMaster = addon.GetMasterLooter()
    if not lootMaster or not addon.Player:IsSame(handover.lootMaster, lootMaster) then
        return false
    end
    if handover.leader and not addon.Player:IsSame(handover.leader, addon.GetGroupLeader()) then
        return false
    end
    return true
end


function Loot:DecisionRun()
    if Loot:GetDecision() == nil then return nil end
    return addon.db.raidPrompt.decision.run
end


function Loot:KeepGuard()
    if Loot:GetDecision() ~= true then return end
    addon.db.raidPrompt.decision.guardKept = true
    addon.Log:I("Loot", "guild loot funnel guard kept for this group")
end

function Loot:GuardKept()
    return Loot:GetDecision() == true and addon.db.raidPrompt.decision.guardKept == true
end



function Loot:GetDecision()
    local decision = addon.db and addon.db.raidPrompt and addon.db.raidPrompt.decision
    if type(decision) ~= "table" then return nil end
    local key = Loot:DecisionKey()
    if not key then return nil end
    if decision.key == "party" and key == "raid" and not addon.db.raidPrompt.inGroups then
        return nil
    end
    local lootMaster = addon.GetMasterLooter()
    if not lootMaster or not addon.Player:IsSame(decision.lootMaster, lootMaster) then
        return nil
    end
    if decision.leader and not addon.Player:IsSame(decision.leader, addon.GetGroupLeader()) then
        return nil
    end
    return decision.answer and true or false
end

local function ForgetDecision(why)
    local store = addon.db and addon.db.raidPrompt
    if not store then return end


    store.handover = nil
    if store.decision == nil then return end
    store.decision = nil
    addon.Log:I("Loot", "group decision forgotten -", why)
end

function Loot:ApplyHandling(on, sender, armed, quiet)
    local next = on and true or false
    local nextArmed = next and armed == true



    if not next and not addon.PlayerIsMasterLooter() then
        ForgetDecision("SLC deactivated")
    end



    if Loot.handling == next and Loot.funnelArmed == nextArmed then return end

    Loot.handling = next
    Loot.funnelArmed = nextArmed
    addon.Log:I("Loot", "handling", Loot.handling, "funnel", Loot.funnelArmed,
        "per", tostring(sender))


    if addon.Callbacks then addon.Callbacks:Fire("HandlingChanged", Loot.handling) end



    if not quiet and Loot.handling and FunnelRole() == "pass" then

        print(addon.Log.CHAT_PREFIX.accent .. addon.Locale.Format(T["loot council is active - this addon will PASS group loot rolls on your behalf, and %s will collect them for the council to distribute."],
            tostring(addon.GetMasterLooter())))
    elseif not quiet and Loot.handling and FunnelRole() == "need" then
        print(addon.Log.CHAT_PREFIX.accent .. T["you are collecting loot for the council - this addon will roll Need on group loot for you."])
    end
end









local HANDLING_COOLDOWN = 10
local MAX_HANDLING_ASKS = 5
local lastHandlingAsk, handlingAsks = 0, 0
local handlingRetryPending = false

local handlingAskHeld = false

local function ResetHandlingAsks()
    lastHandlingAsk, handlingAsks, handlingRetryPending, handlingAskHeld = 0, 0, false, false
end


local function RetryHandlingAsk()
    local remaining = HANDLING_COOLDOWN - (GetTime() - lastHandlingAsk)
    if remaining > 0 then
        C_Timer.After(remaining + 0.5, RetryHandlingAsk)
        return
    end
    handlingRetryPending = false

    Loot:EnsureHandling()
end


function Loot:EnsureHandling(why)
    if not IsInGroup() then return end
    if addon.PlayerIsMasterLooter() then return end
    if Loot.handling ~= nil then return end
    if handlingAskHeld then return end

    if handlingAsks >= MAX_HANDLING_ASKS then return end
    local now = GetTime()
    if lastHandlingAsk > 0 and now - lastHandlingAsk < HANDLING_COOLDOWN then return end
    lastHandlingAsk, handlingAsks = now, handlingAsks + 1

    addon.Log:I("Loot", "handling unknown -", tostring(why or "no answer"),
        "- asking the loot master", handlingAsks .. "/" .. MAX_HANDLING_ASKS)


    addon.Comms:Send("handling_request", {}, nil, true)
    if addon.Restrictions and addon.Restrictions:IsBlocked() then handlingAskHeld = true end

    if not handlingRetryPending then
        handlingRetryPending = true
        C_Timer.After(HANDLING_COOLDOWN + 0.5, RetryHandlingAsk)
    end
end


function Loot:PushHandling(why)
    if not addon.PlayerIsMasterLooter() then return end
    if not Loot.handling then return end
    addon.Log:D("Loot", "re-sending handling -", tostring(why))
    addon.Comms:Send("handling", { on = true, funnel = Loot.funnelArmed == true }, nil, true)
end


local function ForgetHandling(why)
    if Loot.handling == nil then return end
    Loot.handling = nil
    Loot.funnelArmed = nil
    addon.Log:I("Loot", "handling forgotten -", why)
    if addon.Callbacks then addon.Callbacks:Fire("HandlingChanged", nil) end
end



local seenGroupThisLoad = false








local knownLootMaster, knownLeader = nil, nil

function Loot:CheckLootMaster(why)
    if not addon.db then return end
    if not IsInGroup() then
        knownLootMaster, knownLeader = nil, nil
        return
    end


    local current = addon.GetMasterLooter(true)
    local leader = addon.GetGroupLeader()


    if not current or not leader then return end

    local previous, previousLeader = knownLootMaster, knownLeader
    local lootMasterMoved = previous and not addon.Player:IsSame(previous, current)
    local leaderMoved = previousLeader and not addon.Player:IsSame(previousLeader, leader)
    if previous and previousLeader and not lootMasterMoved and not leaderMoved then return end
    knownLootMaster, knownLeader = current, leader

    if lootMasterMoved or leaderMoved then
        addon.Log:I("Loot", "loot master / leader changed -", tostring(why), "-",
            tostring(previous), "->", tostring(current), "leader",
            tostring(previousLeader), "->", tostring(leader))
        ResetHandlingAsks()


        local pending = addon.db.raidPrompt and type(addon.db.raidPrompt.handover) == "table"
            and addon.db.raidPrompt.handover.key == Loot:DecisionKey()


        local decision = addon.db.raidPrompt and addon.db.raidPrompt.decision
        if type(decision) == "table"
            and ((lootMasterMoved and addon.Player:IsSame(decision.lootMaster, previous))
                or (leaderMoved and addon.Player:IsSame(decision.leader, previousLeader))) then
            ForgetDecision(leaderMoved and "group leader changed" or "loot master changed")
        end



        if addon.db.raidPrompt then
            addon.db.raidPrompt.handover = (Loot.handling == true or pending) and {
                key = Loot:DecisionKey(), lootMaster = current, leader = leader,
            } or nil
        end


        ForgetHandling(leaderMoved and "group leader changed" or "loot master changed")

        Loot:EnsureHandling(why)
    end
    if addon.Callbacks then addon.Callbacks:Fire("LootMasterChanged", current, previous) end
end



function Loot:OnRosterChanged(why, gained, leaderChanged)
    if not IsInGroup() then
        ForgetHandling("left the group")
        if seenGroupThisLoad then ForgetDecision("left the group") end
        ResetHandlingAsks()
        knownLootMaster, knownLeader = nil, nil
        return
    end
    seenGroupThisLoad = true




    Loot:CheckLootMaster(why)
    if gained then Loot:PushHandling(why) end
    Loot:EnsureHandling(why)
end



Loot.ResetHandlingAsks = ResetHandlingAsks






function Loot.OnRestrictionChange(isBlocked)
    if isBlocked or not handlingAskHeld then return end
    handlingAskHeld, lastHandlingAsk = false, GetTime()
    if not handlingRetryPending then
        handlingRetryPending = true
        C_Timer.After(HANDLING_COOLDOWN + 0.5, RetryHandlingAsk)
    end
end

function Loot:Init()
    if addon.Restrictions then addon.Restrictions:OnChange(Loot.OnRestrictionChange) end



    local function GroupChanged(atLogin)


        if not IsInGroup() then
            inGuildParty = false
            guildPresent, guildRequired = nil, nil
            wipe(lootMasterGuild)
            if atLogin then

                C_Timer.After(3, function()
                    if not IsInGroup() then
                        ForgetDecision("not in a group at login")
                    end
                end)
            end
            return
        end
        seenGroupThisLoad = true

        if IsInGuild() then
            RequestGuildPartyState()
            RefreshGuildParty()
        end
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("LOOT_READY")
    f:RegisterEvent("LOOT_OPENED")
    f:RegisterEvent("LOOT_SLOT_CLEARED")
    f:RegisterEvent("LOOT_CLOSED")
    f:RegisterEvent("START_LOOT_ROLL")

    f:RegisterEvent("GUILD_PARTY_STATE_UPDATED")

    f:RegisterEvent("PLAYER_GUILD_UPDATE")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "GUILD_PARTY_STATE_UPDATED" then
            local was = inGuildParty
            inGuildParty = arg1 and true or false
            if was ~= inGuildParty then
                addon.Log:I("Loot", "guild group is now", tostring(inGuildParty))
                GuildStateChanged()
            end


            local _, present, required = ReadGuildParty()
            guildPresent, guildRequired = present, required
            return
        elseif event == "PLAYER_ENTERING_WORLD" then
            GroupChanged(true)
            return
        elseif event == "PLAYER_GUILD_UPDATE" then
            if Loot.handling and addon.db.funnel and addon.db.funnel.guildGroupOnly then
                GuildStateChanged()
            end
            return
        end

        if event == "LOOT_READY" or event == "LOOT_OPENED" then
            CacheLootSlots()
        elseif event == "LOOT_SLOT_CLEARED" then
            OnSlotCleared(arg1)
        elseif event == "LOOT_CLOSED" then
            wipe(slotCache)
        elseif event == "START_LOOT_ROLL" then
            local ok, err = pcall(OnStartLootRoll, arg1)
            if not ok then addon.Log:Bug("Loot", tostring(err)) end
        end
    end)


    addon.Callbacks:Register("RosterChanged", function() GroupChanged(false) end)

    addon.Callbacks:Register("LootMethodChanged", function() Loot:RearmFunnel() end)
    if addon.MasterLoot then addon.MasterLoot:Init() end



    addon.Comms:Register("tradeable", "any", function(args, sender)
        if not addon.PlayerIsMasterLooter() then return end
        if not args or not args.link then return end

        local owner = addon.Player:Get(sender).fullName
        addon.Log:I("Loot", "reported by", tostring(owner), args.link)


    end)

    addon.Comms:Register("handling", "ml", function(args, sender)

        if addon.Player:IsSelf(sender) then return end


        ResetHandlingAsks()
        Loot:ApplyHandling(args and args.on, sender, args and args.funnel)
    end)



    addon.Comms:Register("handling_request", "any", function(_, sender)
        if not addon.PlayerIsMasterLooter() then return end

        if Loot.handling == nil and Loot:GetDecision() == true then
            addon.Log:D("Loot", "handling requested by", tostring(sender),
                "- held until the remembered Yes re-arms")
            return
        end
        addon.Log:D("Loot", "handling requested by", tostring(sender))
        addon.Comms:Send("handling", {
            on = Loot.handling and true or false,
            funnel = Loot.funnelArmed == true,
        }, nil, true)
    end)


    local seeded, present, required = ReadGuildParty()
    if seeded == nil then
        addon.Log:W("Loot", "InGuildParty unavailable - guild-group state will",
            "wait for GUILD_PARTY_STATE_UPDATED")
    else
        inGuildParty = seeded
        guildPresent, guildRequired = present, required
        addon.Log:I("Loot", "guild group at login", tostring(seeded),
            required and ("%s of %s"):format(tostring(present), tostring(required))
                or "(no counts)")
    end

    addon.Log:I("Loot", "ready", "guild loot funnel guard",
        (addon.db.funnel and addon.db.funnel.guildGroupOnly) and "on" or "off")
end
