if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local Gear = {}
addon.Gear = Gear

local issecretvalue = issecretvalue

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end








local HANDS = { INVSLOT_MAINHAND, INVSLOT_OFFHAND }



local OFFHAND_ONLY = {
    INVTYPE_SHIELD        = true,
    INVTYPE_HOLDABLE      = true,
    INVTYPE_WEAPONOFFHAND = true,
}


local TWO_HANDED = {
    INVTYPE_2HWEAPON    = true,
    INVTYPE_RANGED      = true,
    INVTYPE_RANGEDRIGHT = true,
    INVTYPE_RANGEDLEFT  = true,
    INVTYPE_THROWN      = true,
}

local EQUIP_SLOTS = {
    INVTYPE_HEAD            = { INVSLOT_HEAD },
    INVTYPE_NECK            = { INVSLOT_NECK },
    INVTYPE_SHOULDER        = { INVSLOT_SHOULDER },
    INVTYPE_BODY            = { INVSLOT_BODY },
    INVTYPE_CHEST           = { INVSLOT_CHEST },
    INVTYPE_ROBE            = { INVSLOT_CHEST },
    INVTYPE_WAIST           = { INVSLOT_WAIST },
    INVTYPE_LEGS            = { INVSLOT_LEGS },
    INVTYPE_FEET            = { INVSLOT_FEET },
    INVTYPE_WRIST           = { INVSLOT_WRIST },
    INVTYPE_HAND            = { INVSLOT_HAND },
    INVTYPE_FINGER          = { INVSLOT_FINGER1, INVSLOT_FINGER2 },
    INVTYPE_TRINKET         = { INVSLOT_TRINKET1, INVSLOT_TRINKET2 },
    INVTYPE_CLOAK           = { INVSLOT_BACK },
    INVTYPE_TABARD          = { INVSLOT_TABARD },
    INVTYPE_SHIELD          = { INVSLOT_OFFHAND },
    INVTYPE_HOLDABLE        = { INVSLOT_OFFHAND },
    INVTYPE_WEAPONOFFHAND   = { INVSLOT_OFFHAND },
    INVTYPE_WEAPONMAINHAND  = { INVSLOT_MAINHAND },

    INVTYPE_WEAPON          = HANDS,

    INVTYPE_2HWEAPON        = HANDS,
    INVTYPE_RANGED          = HANDS,
    INVTYPE_RANGEDRIGHT     = HANDS,

    INVTYPE_RANGEDLEFT      = HANDS,
    INVTYPE_THROWN          = HANDS,
    INVTYPE_RELIC           = HANDS,
}




local function ResolveSlots(equipLoc, linkFor, equipLocFor)
    local slots = EQUIP_SLOTS[equipLoc]
    if not slots then return nil end

    if not OFFHAND_ONLY[equipLoc] then return slots end


    if linkFor(INVSLOT_OFFHAND) then return slots end

    local mainHand = linkFor(INVSLOT_MAINHAND)
    if not mainHand then return slots end


    if not TWO_HANDED[equipLocFor(mainHand) or ""] then return slots end

    return { INVSLOT_MAINHAND }
end
Gear.ResolveSlots = ResolveSlots
Gear.EQUIP_SLOTS = EQUIP_SLOTS



local function For(classes, ...)
    local locs, entry = { ... }, {}
    for class in classes:gmatch("%S+") do entry[class] = locs end
    return entry
end

local function Merge(...)
    local entry = {}
    for i = 1, select("#", ...) do
        for class, locs in pairs((select(i, ...))) do entry[class] = locs end
    end
    return entry
end

local FOREVER_TOKENS = {


    [17204] = For("ANY", "INVTYPE_2HWEAPON"),
    [18563] = For("ANY", "INVTYPE_WEAPON"),
    [18564] = For("ANY", "INVTYPE_WEAPON"),
    [19017] = For("ANY", "INVTYPE_WEAPON"),
    [18703] = For("ANY", "INVTYPE_RANGED", "INVTYPE_2HWEAPON"),

    [18423] = For("ANY", "INVTYPE_NECK", "INVTYPE_FINGER", "INVTYPE_TRINKET"),
    [18422] = For("ANY", "INVTYPE_NECK", "INVTYPE_FINGER", "INVTYPE_TRINKET"),
    [19003] = For("ANY", "INVTYPE_NECK", "INVTYPE_FINGER", "INVTYPE_HOLDABLE"),
    [19002] = For("ANY", "INVTYPE_NECK", "INVTYPE_FINGER", "INVTYPE_HOLDABLE"),
    [18705] = For("ANY", "INVTYPE_RANGED"),

    [19716] = For("PALADIN HUNTER MAGE", "INVTYPE_WRIST"),
    [19717] = For("WARRIOR ROGUE SHAMAN", "INVTYPE_WRIST"),
    [19718] = For("PRIEST WARLOCK DRUID", "INVTYPE_WRIST"),
    [19719] = Merge(For("WARRIOR SHAMAN", "INVTYPE_WAIST"), For("ROGUE", "INVTYPE_SHOULDER")),
    [19720] = Merge(For("PRIEST DRUID", "INVTYPE_WAIST"), For("WARLOCK", "INVTYPE_SHOULDER")),
    [19721] = Merge(For("PALADIN HUNTER", "INVTYPE_WAIST"), For("MAGE", "INVTYPE_SHOULDER")),
    [19722] = For("PALADIN SHAMAN DRUID", "INVTYPE_CHEST"),
    [19723] = For("WARRIOR MAGE WARLOCK", "INVTYPE_CHEST"),
    [19724] = Merge(For("HUNTER PRIEST", "INVTYPE_SHOULDER"), For("ROGUE", "INVTYPE_CHEST")),
    [19802] = For("ANY", "INVTYPE_TRINKET"),

    [21220] = For("ANY", "INVTYPE_NECK"),
    [20884] = For("WARRIOR PALADIN SHAMAN MAGE DRUID", "INVTYPE_FINGER"),
    [20888] = For("HUNTER ROGUE PRIEST WARLOCK", "INVTYPE_FINGER"),
    [20885] = For("WARRIOR ROGUE PRIEST MAGE", "INVTYPE_CLOAK"),
    [20889] = For("PALADIN HUNTER SHAMAN WARLOCK DRUID", "INVTYPE_CLOAK"),
    [20886] = Merge(For("WARRIOR HUNTER ROGUE", "INVTYPE_WEAPON"),
        For("PALADIN SHAMAN", "INVTYPE_WEAPONMAINHAND")),
    [20890] = Merge(For("WARLOCK", "INVTYPE_WEAPON"),
        For("PRIEST MAGE DRUID", "INVTYPE_WEAPONMAINHAND")),

    [20928] = For("WARRIOR HUNTER ROGUE PRIEST", "INVTYPE_SHOULDER", "INVTYPE_FEET"),
    [20932] = For("PALADIN SHAMAN MAGE WARLOCK DRUID", "INVTYPE_SHOULDER", "INVTYPE_FEET"),
    [20926] = For("WARRIOR PRIEST MAGE WARLOCK", "INVTYPE_HEAD"),
    [20930] = For("PALADIN HUNTER ROGUE SHAMAN DRUID", "INVTYPE_HEAD"),
    [20927] = For("WARRIOR ROGUE PRIEST MAGE", "INVTYPE_LEGS"),
    [20931] = For("PALADIN HUNTER SHAMAN WARLOCK DRUID", "INVTYPE_LEGS"),
    [20929] = For("WARRIOR PALADIN HUNTER ROGUE SHAMAN", "INVTYPE_CHEST"),
    [20933] = For("PRIEST MAGE WARLOCK DRUID", "INVTYPE_CHEST"),
    [21221] = For("ANY", "INVTYPE_NECK", "INVTYPE_FINGER", "INVTYPE_CLOAK"),

    [22520] = For("ANY", "INVTYPE_TRINKET"),
}


local DESECRATED = { "INVTYPE_LEGS", "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_WRIST",
    "INVTYPE_WAIST", "INVTYPE_HAND", "INVTYPE_FEET" }
for id = 22349, 22351 do FOREVER_TOKENS[id] = For("ANY", "INVTYPE_CHEST") end
for i, loc in ipairs(DESECRATED) do
    for _, base in ipairs({ 22351, 22358, 22365 }) do
        FOREVER_TOKENS[base + i] = For("ANY", loc)
    end
end



local function TokenSlots(itemID, classFile, linkFor, equipLocFor)
    local entry = itemID and FOREVER_TOKENS[itemID]
    local locs = entry and (entry.ANY or (classFile and entry[classFile]))
    if not locs then return nil end

    local slots, seen = {}, {}
    for _, loc in ipairs(locs) do
        for _, slot in ipairs(ResolveSlots(loc, linkFor, equipLocFor) or {}) do
            if not seen[slot] then
                seen[slot] = true
                slots[#slots + 1] = slot
            end
        end
    end
    return slots[1] and slots or nil
end
Gear.TokenSlots = TokenSlots
Gear.FOREVER_TOKENS = FOREVER_TOKENS



local function WorstTwo(items, levelFor)
    if #items <= 2 then return items end
    local ranked = {}
    for i, item in ipairs(items) do
        ranked[i] = { item = item, level = levelFor(item), order = i }
    end
    table.sort(ranked, function(a, b)
        if a.level and b.level and a.level ~= b.level then return a.level < b.level end
        if (a.level == nil) ~= (b.level == nil) then return a.level ~= nil end
        return a.order < b.order
    end)
    return { ranked[1].item, ranked[2].item }
end
Gear.WorstTwo = WorstTwo







local function ItemString(link)
    if not link or link == "" then return nil end
    return link:match("|H(item:[^|]*)")
end
Gear.ItemString = ItemString







function Gear:Equipped(equipLoc)


    local slots = ResolveSlots(equipLoc, function(slot)
        local link = GetInventoryItemLink("player", slot)
        if not link or IsSecret(link) then return nil end
        return link
    end, function(link)
        return (select(9, C_Item.GetItemInfo(link)))
    end)
    if not slots then return nil, nil end

    local found = {}
    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink("player", slot)

        if link and not IsSecret(link) then
            local itemString = ItemString(link)
            if itemString then found[#found + 1] = itemString end
        end
    end

    return found[1], found[2]
end


local function ItemLevel(item)
    if not item then return nil end
    return (select(4, C_Item.GetItemInfo(item)))
end



function Gear:Diff(itemLink, g1, g2)
    local incoming = ItemLevel(itemLink)
    if not incoming then return nil end

    local a, b = ItemLevel(g1), ItemLevel(g2)
    local worst
    if a and b then
        worst = math.min(a, b)
    else
        worst = a or b
    end
    if not worst then return nil end

    return incoming - worst
end



function Gear:TokenEquipped(itemID, equipLoc)
    local classFile = UnitClassBase("player")
    if IsSecret(classFile) then classFile = nil end
    local slots = TokenSlots(itemID, classFile, function(slot)
        local link = GetInventoryItemLink("player", slot)
        if not link or IsSecret(link) then return nil end
        return link
    end, function(link)
        return (select(9, C_Item.GetItemInfo(link)))
    end)
    addon.Log:D("Gear", "token", tostring(itemID), "equipLoc", tostring(equipLoc),
        "class", tostring(classFile), "slots", slots and table.concat(slots, ",") or "none")
    if not slots then return nil end

    local found = {}
    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink("player", slot)
        local itemString = link and not IsSecret(link) and ItemString(link)
        if itemString then found[#found + 1] = itemString end
    end
    return WorstTwo(found, ItemLevel)
end







function Gear:GetSummary()
    local _, equipped = GetAverageItemLevel()
    if equipped and not IsSecret(equipped) then return math.floor(equipped + 0.5) end
    return nil
end






local ALL_SLOTS = {
    INVSLOT_HEAD, INVSLOT_NECK, INVSLOT_SHOULDER, INVSLOT_CHEST,
    INVSLOT_WAIST, INVSLOT_LEGS, INVSLOT_FEET, INVSLOT_WRIST, INVSLOT_HAND,
    INVSLOT_FINGER1, INVSLOT_FINGER2, INVSLOT_TRINKET1, INVSLOT_TRINKET2,
    INVSLOT_BACK, INVSLOT_MAINHAND, INVSLOT_OFFHAND,
}





function Gear.SetSummary(readers)
    local counts = {}
    for _, slot in ipairs(readers.slots or ALL_SLOTS) do
        local link = readers.linkFor(slot)
        if link then
            local cached, setID, hasBonus = readers.infoFor(link)
            if not cached then return nil end
            if hasBonus and setID then
                counts[setID] = (counts[setID] or 0) + 1
            end
        end
    end

    local bestSetID, bestCount
    for setID, count in pairs(counts) do
        if not bestCount or count > bestCount then
            bestSetID, bestCount = setID, count
        end
    end
    if not bestCount then return nil end
    return { count = bestCount, setID = bestSetID }
end



function Gear.SetProgress(setCount)
    if setCount == nil then return nil end
    local total = setCount + 1
    if total == 2 or total == 4 then
        return addon.Locale.Format(T["+%dset"], total), true
    end
    return addon.Locale.Format(T["%d/4 set"], total), false
end


local function CurrentSetInfo(link)

    local name, _, _, _, _, _, _, _, _, _, _, _, _, _, _, setID =
        C_Item.GetItemInfo(link)
    if not name then return false end
    if not setID then return true, nil, false end

    if addon.IsForever then return true, setID, false end

    local specIndex = C_SpecializationInfo.GetSpecialization()
    if IsSecret(specIndex) or not specIndex then return true, setID, false end
    local specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if IsSecret(specID) or not specID then return true, setID, false end

    local itemID = select(1, C_Item.GetItemInfoInstant(link))
    local spellIDs = itemID
        and C_Item.GetSetBonusesForSpecializationByItemID(specID, itemID)


    if spellIDs == nil then return false end
    return true, setID, type(spellIDs) == "table" and #spellIDs > 0
end

local function CurrentSetLink(slot)
    local link = GetInventoryItemLink("player", slot)
    if not link or IsSecret(link) then return nil end
    return link
end

local function CurrentSetSummary()
    return Gear.SetSummary({
        linkFor = CurrentSetLink,
        infoFor = CurrentSetInfo,
    })
end



function Gear.CurrentSetDiagnostic()
    local rows, facts = {}, {}
    for _, slot in ipairs(ALL_SLOTS) do
        local link = CurrentSetLink(slot)
        local cached, setID, hasBonus
        if link then
            cached, setID, hasBonus = CurrentSetInfo(link)
            facts[link] = { cached = cached, setID = setID, hasBonus = hasBonus }
        end
        rows[#rows + 1] = {
            slot = slot, link = link, cached = cached,
            setID = setID, hasBonus = hasBonus,
        }
    end
    local summary = Gear.SetSummary({
        slots = ALL_SLOTS,
        linkFor = function(slot) return CurrentSetLink(slot) end,
        infoFor = function(link)
            local fact = facts[link]
            if fact then return fact.cached, fact.setID, fact.hasBonus end
            return CurrentSetInfo(link)
        end,
    })
    return rows, summary
end


function Gear:Sockets(itemString)
    if not itemString then return nil end
    local n = C_Item.GetItemNumSockets(itemString)
    return (n and n > 0) and n or nil
end







function Gear:BuildResponsePayload(itemLink)
    if not itemLink then return nil end

    local itemID, _, _, equipLoc = C_Item.GetItemInfoInstant(itemLink)

    local tokenGear = addon.IsForever and not EQUIP_SLOTS[equipLoc or ""]
        and Gear:TokenEquipped(itemID, equipLoc)
    if not tokenGear and (not equipLoc or equipLoc == "") then return nil end

    local g1, g2, diff
    if tokenGear then

        g1, g2 = tokenGear[1], tokenGear[2]
    else
        g1, g2 = Gear:Equipped(equipLoc)
        diff = Gear:Diff(itemLink, g1, g2)
    end
    local ilvl = Gear:GetSummary()
    local setInfo = CurrentSetSummary()
    local k1 = Gear:Sockets(g1)
    local k2 = Gear:Sockets(g2)


    if not (g1 or g2 or ilvl or diff or setInfo or k1 or k2) then return nil end

    return {
        g1 = g1,
        g2 = g2,
        d  = diff,
        il = ilvl,

        t  = setInfo and setInfo.count or nil,
        ts = setInfo and setInfo.setID or nil,


        k1 = k1,
        k2 = k2,
    }
end



local LINK_MAX, ITEM_MAX = 512, 255

local RANGES = {
    diff = { -9999, 9999 }, ilvl = { 0, 9999 }, setCount = { 0, 99 },
    setID = { 0, 2 ^ 31 }, sockets1 = { 0, 9 }, sockets2 = { 0, 9 },
}

local WIRE = { gear1 = "g1", gear2 = "g2", diff = "d", ilvl = "il", setCount = "t",
    setID = "ts", sockets1 = "k1", sockets2 = "k2" }



function Gear.CleanField(field, value)
    if field == "gear1" or field == "gear2" then
        if type(value) ~= "string" or #value > LINK_MAX then return nil end
        local item = value:match("|H(item:[^|]*)") or value:match("^item:[^|]*$")
        return item and #item <= ITEM_MAX and item or nil
    end
    local range = RANGES[field]
    local number = range and tonumber(value)
    if number and number % 1 == 0 and number >= range[1] and number <= range[2] then
        return number
    end
    return nil
end



function Gear:ApplyToCandidate(candidate, payload)
    if not candidate then return end
    if type(payload) ~= "table" then payload = {} end
    for field, key in pairs(WIRE) do
        candidate[field] = Gear.CleanField(field, payload[key])
    end
end





function Gear:Init()
    addon.Log:I("Gear", "ready", "ilvl", tostring(Gear:GetSummary()))
end
