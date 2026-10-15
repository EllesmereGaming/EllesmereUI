if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Autopass = {}
addon.Autopass = Autopass


local ARMOUR_CLASSES = {
    [Enum.ItemArmorSubclass.Cloth] = {
        MAGE = true, PRIEST = true, WARLOCK = true,
    },
    [Enum.ItemArmorSubclass.Leather] = {
        DRUID = true, ROGUE = true, MONK = true, DEMONHUNTER = true,
    },
    [Enum.ItemArmorSubclass.Mail] = {
        HUNTER = true, SHAMAN = true, EVOKER = true,
    },
    [Enum.ItemArmorSubclass.Plate] = {
        WARRIOR = true, PALADIN = true, DEATHKNIGHT = true,
    },
    [Enum.ItemArmorSubclass.Shield] = {
        WARRIOR = true, PALADIN = true, SHAMAN = true,
    },
}



local CAN_WEAR_FOREVER = {
    [Enum.ItemArmorSubclass.Leather] = {
        WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true,
        SHAMAN = true, DRUID = true,
    },
    [Enum.ItemArmorSubclass.Mail] = {
        WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true,
    },
    [Enum.ItemArmorSubclass.Plate] = {
        WARRIOR = true, PALADIN = true,
    },
    [Enum.ItemArmorSubclass.Shield] = {
        WARRIOR = true, PALADIN = true, SHAMAN = true,
    },
}








local function HasClassRestriction(link, Tooltip)
    if not Enum.TooltipDataLineType.UsageRequirement then return false end

    local data = Tooltip()
    if not data or not data.lines then return false end

    local restricted = false
    for _, line in ipairs(data.lines) do
        if line.type == Enum.TooltipDataLineType.UsageRequirement
            and line.requirementType == Enum.TooltipDataUsageRequirementType.RaceClass then
            local barred = line.usable == false

            addon.Log:D("Autopass", "RaceClass line", link,
                ("leftText=%s requirementType=%s type=%s usable=%s"):format(
                    tostring(line.leftText), tostring(line.requirementType),
                    tostring(line.type), tostring(line.usable)),
                barred and "-> restricted" or "-> not a restriction")
            if barred then restricted = true end
        end
    end
    return restricted
end


local UNIVERSAL_SLOTS = {
    INVTYPE_CLOAK = true,
    INVTYPE_FINGER = true,
    INVTYPE_NECK = true,
    INVTYPE_TRINKET = true,
    INVTYPE_BODY = true,
    INVTYPE_TABARD = true,
    INVTYPE_HOLDABLE = true,
}







local function IsUnusableWeaponType(link, Tooltip, armour)
    local _, _, _, equipLoc, _, classID = C_Item.GetItemInfoInstant(link)
    if classID ~= (armour and Enum.ItemClass.Armor or Enum.ItemClass.Weapon) then return false end
    if armour and UNIVERSAL_SLOTS[equipLoc or ""] then return false end
    if not Enum.TooltipDataLineType.EquipSlot then return false end

    local data = Tooltip()
    if not data or not data.lines then return false end

    local barred = false
    for _, line in ipairs(data.lines) do
        if line.type == Enum.TooltipDataLineType.EquipSlot then
            local unusable = line.isValidItemType == false
                or (line.isValidInvSlot == false and equipLoc == "INVTYPE_2HWEAPON")
            addon.Log:D("Autopass", "EquipSlot line", link,
                ("leftText=%s rightText=%s isValidItemType=%s isValidInvSlot=%s"):format(
                    tostring(line.leftText), tostring(line.rightText),
                    tostring(line.isValidItemType), tostring(line.isValidInvSlot)),
                unusable and "-> restricted" or "-> not a restriction")
            if unusable then barred = true end
        end
    end
    return barred
end

local function IsWrongArmourType(link)
    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(link)
    if classID ~= Enum.ItemClass.Armor then return false end



    if equipLoc and UNIVERSAL_SLOTS[equipLoc] then return false end

    local allowed = (addon.IsForever and CAN_WEAR_FOREVER or ARMOUR_CLASSES)[subClassID]
    if not allowed then return false end

    local _, classFile = UnitClass("player")
    if not classFile then return false end
    return not allowed[classFile]
end



local function IsTrinketForOtherClasses(link)
    if addon.IsForever then return false end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    if equipLoc ~= "INVTYPE_TRINKET" then return false end
    if not C_Item.GetItemSpecInfo then return false end

    local specs = C_Item.GetItemSpecInfo(link)
    local barred = type(specs) == "table" and next(specs) == nil
    local ids = {}
    for _, specID in pairs(type(specs) == "table" and specs or {}) do
        ids[#ids + 1] = tostring(specID)
    end
    addon.Log:D("Autopass", "trinket specs", link,
        type(specs) == "table" and (#ids .. " of this class: " .. table.concat(ids, ",")) or "no answer",
        barred and "-> restricted" or "-> not a restriction")
    return barred
end








local function TeachesNewAppearance(link)

    if addon.IsForever or not C_TransmogCollection then return false end


    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(link)
    if not appearanceID or not sourceID then return false end


    if C_TransmogCollection.PlayerHasTransmogItemModifiedAppearance(sourceID) then
        return false
    end


    local hasItemData, canCollect = C_TransmogCollection.PlayerCanCollectSource(sourceID)
    if not hasItemData then
        addon.Log:D("Autopass", "appearance data not ready", link)
        return nil
    end

    return canCollect and true or false
end


local function Restriction(link)
    local read, data = false, nil
    local function Tooltip()
        if not read then
            read, data = true, C_TooltipInfo.GetHyperlink(link)
        end
        return data
    end

    if HasClassRestriction(link, Tooltip) then return "class" end
    if IsUnusableWeaponType(link, Tooltip) then return "weapon" end

    if addon.IsForever and IsUnusableWeaponType(link, Tooltip, true) then
        return "unusable"
    end
    if IsWrongArmourType(link) then
        return addon.IsForever and "unusable" or "armour"
    end
    if IsTrinketForOtherClasses(link) then return "trinket" end
    return nil
end




function Autopass:Check(link)
    if not link then return false, nil, true, false end


    if not C_Item.GetItemInfoInstant(link) then return false, nil, false, false end



    local itemName, _, _, _, _, _, _, _, _, _, _, _, _, bindType =
        C_Item.GetItemInfo(link)
    if not itemName then
        addon.Log:D("Autopass", "item not cached yet, not passing", link)
        return false, nil, false, false
    end
    if bindType == Enum.ItemBind.OnEquip then return false, nil, true, false end

    local reason = Restriction(link)
    if not reason then return false, nil, true, false end



    local appearance = TeachesNewAppearance(link)
    if addon.db.autopassTransmog and appearance ~= false then
        addon.Log:D("Autopass", "uncollected appearance, not passing", link, reason)
        return false, reason, appearance ~= nil, appearance == true
    end
    return true, reason, appearance ~= nil, appearance == true
end


function Autopass:ShouldPass(link)
    if not addon.db.autopass then return false end
    local should, reason = Autopass:Check(link)
    if not should then return false end
    return true, reason
end



local verdicts = {}

function Autopass:WouldPass(link)
    if not link then return false, nil, true, false end
    local known = verdicts[link]
    if known then return known.should, known.reason, true, known.appearance end
    local should, reason, judged, appearance = Autopass:Check(link)
    if judged then
        verdicts[link] = { should = should, reason = reason, appearance = appearance }
    end
    return should, reason, judged, appearance
end









Autopass.AUTO_PREFIX = "auto: "

local REASON_TEXT = addon.Locale.Texts{
    class  = T["class restricted"],
    weapon = T["wrong weapon type"],
    armour = T["wrong armour type"],
    unusable = T["this class cannot use it"],
    trinket = T["a trinket for other classes"],
}


function Autopass.IsAutoNote(note)
    if type(note) ~= "string" then return false end
    return note:sub(1, #Autopass.AUTO_PREFIX) == Autopass.AUTO_PREFIX
end


function Autopass.AutoCode(note)
    if not Autopass.IsAutoNote(note) then return nil end
    return note:sub(#Autopass.AUTO_PREFIX + 1)
end


function Autopass.AutoReason(note)
    local code = Autopass.AutoCode(note)
    if not code then return nil end
    return REASON_TEXT[code] or code
end


function Autopass.NoteText(note)
    local reason = Autopass.AutoReason(note)
    if not reason then return note end
    return addon.Locale.Format(T["Automatic pass: %s."], reason)
end



local CARD_TEXT = addon.Locale.Texts{
    class  = T["Wrong class"],
    weapon = T["Wrong weapon type"],
    armour = T["Wrong armor type"],
    unusable = T["Unusable by your class"],
    trinket = T["Wrong class stat"],
}

function Autopass.CardReason(code)
    if not code then return nil end
    return CARD_TEXT[code] or REASON_TEXT[code] or code
end



local DECIDED = { RESPONDED = true, PASS = true, AWARDED = true }


local blockedRun




local SLICE_MS = 3



local job
local driver



local function ApplyItem(item, me, work)
    if not item then return true end


    local mine = me and item.candidates and item.candidates[me]
    local answered = mine and DECIDED[mine.status] or false
    if item.awarded or item.removed or answered then return true end
    local should, reason = Autopass:ShouldPass(item.link)
    if not should then return true end
    if addon.Session:Respond(item.session, nil, Autopass.AUTO_PREFIX .. reason) then
        work.passed = work.passed + 1
        addon.Log:D("Autopass", item.session, item.link, reason)
        return true
    end
    if addon.Restrictions:IsBlocked() then
        blockedRun = work.runId
        addon.Log:D("Autopass", item.session, item.link,
            "refused by the blackout - retrying when it lifts")
        return false
    end
    return true
end

local function Finish(work)
    if job == work then job = nil end
    if driver then driver:Hide() end
    addon.Log:D("Autopass", ("checked the run in %d frame(s), %.1f ms, worst frame %.1f ms"):format(
        work.frames, work.ms, work.worst))
    local passed = work.passed
    if passed > 0 then
        addon.Log:I("Autopass", "passed on", passed, "unusable items")
        if not addon.db.silentAutopass then
            print(addon.Log.CHAT_PREFIX.accent .. addon.Locale.Format(addon.Locale.Plural{
                one = "automatically passed on %d item your class cannot use.",
                other = "automatically passed on %d items your class cannot use.",
            }, passed, passed))
        end
    end
end



local function Step()
    local work = job
    if not work then
        if driver then driver:Hide() end
        return
    end
    if addon.Session:GetRunId() ~= work.runId then
        addon.Log:D("Autopass", "stopped, run moved on", tostring(work.runId))
        job = nil
        if driver then driver:Hide() end
        return
    end
    local clock = debugprofilestop
    local started = clock and clock() or 0
    local me = addon.Player:GetFullName("player")
    local blocked = false
    repeat
        local item = table.remove(work.queue, 1)
        if not ApplyItem(item, me, work) then blocked = true end
    until blocked or #work.queue == 0
        or (clock and driver and clock() - started >= SLICE_MS)
    local spent = clock and (clock() - started) or 0
    work.frames, work.ms = work.frames + 1, work.ms + spent
    if spent > work.worst then work.worst = spent end
    if blocked or #work.queue == 0 then
        Finish(work)
    elseif driver then
        driver:Show()
    end
end

function Autopass:Apply(indices, runId)
    if not addon.db.autopass then return end
    if runId and addon.Session:GetRunId() ~= runId then return end
    runId = runId or addon.Session:GetRunId()

    local items = addon.Session:GetItems()
    local queue = {}
    if type(indices) == "table" then
        for _, index in ipairs(indices) do queue[#queue + 1] = items[index] end
    else
        for _, item in ipairs(items) do queue[#queue + 1] = item end
    end

    if job and job.runId == runId then
        for _, item in ipairs(queue) do job.queue[#job.queue + 1] = item end
    else
        job = { runId = runId, queue = queue, passed = 0, frames = 0, worst = 0, ms = 0 }
    end

    Step()
end

function Autopass:Init()


    if not driver then
        driver = CreateFrame("Frame")
        driver:Hide()
        driver:SetScript("OnUpdate", Step)
    end

    local function Schedule(indices, runId)


        C_Timer.After(0.5, function()
            if addon.Session:GetRunId() ~= runId then
                addon.Log:D("Autopass", "skipped, run moved on", tostring(runId))
                return
            end
            Autopass:Apply(indices, runId)
        end)
    end

    addon.Callbacks:Register("RunStarted", function()

        verdicts = {}
        Schedule(nil, addon.Session:GetRunId())
    end)

    addon.Callbacks:Register("ItemsAdded", function(indices, runId)
        Schedule(indices, runId)
    end)



    addon.Restrictions:OnChange(function(isBlocked)
        if isBlocked or not blockedRun then return end
        local runId = blockedRun
        blockedRun = nil
        Schedule(nil, runId)
    end)

    addon.Log:I("Autopass", "ready",
        addon.db.autopass and "enabled" or "disabled")
end
