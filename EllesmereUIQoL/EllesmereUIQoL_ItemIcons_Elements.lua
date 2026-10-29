if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ItemIcons_Elements.lua
--  Item Icons providers for the overlays EUI drew before Item Icons: item
--  level, upgrade rank, stack count, BoE / WuE, equipment set name, crafting
--  quality, junk coin, quest starter, keystone level and dungeon; and the
--  upgrade arrow. Insets match the EUI Bags overlays. The element contract and
--  the item and out fields: EllesmereUIQoL_ItemIcons.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local II = EllesmereUI.ItemIcons
local Register = II.RegisterElement

local GetItemInfo, GetItemInfoInstant = C_Item.GetItemInfo, C_Item.GetItemInfoInstant
local GetUpgradeTrack, GetCraftedTrackColor = EllesmereUI.GetUpgradeTrack, EllesmereUI.GetCraftedTrackColor
-- The overlay rules EUI Bags draws by (EllesmereUI.lua)
local AbbrevDungeon, BindLabel = EllesmereUI.AbbrevDungeon, EllesmereUI.BindLabel
local ParseKeystoneLink, ItemLevelRGB = EllesmereUI.ParseKeystoneLink, EllesmereUI.ItemLevelRGB
local JUNK_BADGE = EllesmereUI.JUNK_BADGE
local WEAPON, ARMOR = Enum.ItemClass.Weapon, Enum.ItemClass.Armor
local POOR, BIND_ON_EQUIP = Enum.ItemQuality.Poor, Enum.ItemBind.OnEquip
-- WoW Forever: no number under 10,000 abbreviates (EllesmereUI_NumberFormat.lua)
local AbbreviateNumbers = (EllesmereUI.IS_FOREVER and EllesmereUI.ForeverAbbreviateNumbers) or AbbreviateNumbers

-------------------------------------------------------------------------------
--  Item facts, memoized on the item for one paint
-------------------------------------------------------------------------------
-- The item's location while it still holds the item
local function Location(item)
    local v = item._loc
    if v == nil then
        local loc = item.location
        v = loc and loc:IsValid() and C_Item.DoesItemExist(loc) and loc or false
        item._loc = v
    end
    return v or nil
end

-- True once GetItemInfo answers (quality, sell price and bind type kept);
-- false and pending while the item's data loads
local function Info(item)
    local v = item._info
    if v == nil then
        local name, _, quality, _, _, _, _, _, _, _, sellPrice, _, _, bindType = GetItemInfo(item.link)
        v = name ~= nil
        if v then
            item._quality, item._sell, item._bind = quality, sellPrice, bindType
        else
            item.pending = true
        end
        item._info = v
    end
    return v
end

local function Quality(item)
    local q = item.quality
    if q ~= nil then return q end
    q = item._q
    if q == nil then
        local loc = Location(item)
        if loc then q = C_Item.GetItemQuality(loc) end
        if q == nil and Info(item) then q = item._quality end
        item._q = q or false
    end
    return q or nil
end

-- Weapons and armor, as EUI Bags tells gear apart
local function IsGear(item)
    local f = item.facts
    if f and f.isGear ~= nil then return f.isGear end
    local v = item._gear
    if v == nil then
        local _, _, _, _, _, classID = GetItemInfoInstant(item.link)
        v = classID == WEAPON or classID == ARMOR
        item._gear = v
    end
    return v
end

-- The item's level, else nil (pending while its data loads)
local function ItemLevel(item)
    local v = item._ilvl
    if v == nil then
        local f = item.facts
        v = f and f.itemLevel
        if v == nil then
            local loc = Location(item)
            if loc then v = C_Item.GetCurrentItemLevel(loc) end
            if not v or v <= 0 then v = C_Item.GetDetailedItemLevelInfo(item.link) end
            if not v or v <= 0 then
                Info(item)
                v = false
            end
        end
        item._ilvl = v
    end
    return v or nil
end

-- The item's upgrade level while it is on an upgrade track, else false
local function UpgradeLevel(item)
    local v = item._upgradeLevel
    if v == nil then
        local _, level, maxLevel = EllesmereUI.GetUpgradeTrackKey(item.link)
        v = level and maxLevel and maxLevel > 0 and level or false
        item._upgradeLevel = v
    end
    return v
end

-- The upgrade track hue, else the crafted-crest hue, as EUI Bags colors item
-- levels
local function TrackColor(item)
    local f = item.facts
    local c = f and f.trackColor
    if c ~= nil then return c or nil end
    c = item._trackColor
    if c == nil then
        local text, color = GetUpgradeTrack(item.link)
        if text ~= "" then
            c = color or false
        else
            c = GetCraftedTrackColor(item.link) or false
        end
        item._trackColor = c
    end
    return c or nil
end

-- Item level and upgrade rank color: Custom Colored, else Default Colors (track,
-- crafted crest, then quality), as EUI Bags colors item levels
local function SetLevelColor(item, out)
    local style = item.styles.itemLevel
    local custom = style.colorMode == "custom" and style.customColor
    local track = not custom and TrackColor(item)
    -- Read only when it decides the color: an uncached item would wait for its data
    local quality = not (custom or track) and Quality(item) or nil
    out.r, out.g, out.b = ItemLevelRGB(custom, track, quality)
end

-- Mythic Keystone level (and _ksMap, its challenge map) from the link; false
-- for any other item
local function Keystone(item)
    local level = item._ksLevel
    if level == nil then
        level, item._ksMap = ParseKeystoneLink(item.link)
        level = level or false
        item._ksLevel = level
    end
    return level
end

-------------------------------------------------------------------------------
--  Elements
-------------------------------------------------------------------------------
Register("itemLevel", {
    kind = "text",
    Apply = function(item, _, out)
        if not IsGear(item) then return false end
        local level = ItemLevel(item)
        if not level then return false end
        out.text = level
        SetLevelColor(item, out)
        return true
    end,
})

Register("upgradeRank", {
    kind = "text", insetX = 2, insetY = 2,
    Apply = function(item, _, out)
        if not IsGear(item) then return false end
        local f = item.facts
        local level = f and f.upgradeLevel
        if level == nil then level = UpgradeLevel(item) end
        if not level then return false end
        out.text = level
        SetLevelColor(item, out)
        return true
    end,
})

Register("stackCount", {
    kind = "text", insetX = 2, insetY = 2,
    Apply = function(item, _, out)
        local n = item.count
        if type(n) ~= "number" or n <= 1 then return false end
        out.text = n > 9999 and AbbreviateNumbers(n) or n
        return true
    end,
})

-- Unbound Binds when Equipped or Warbound until Equipped gear, labelled as EUI
-- Bags labels it (EllesmereUI.BindLabel)
Register("bindType", {
    kind = "text", insetX = 1, insetY = 2,
    Apply = function(item, _, out)
        if not IsGear(item) then return false end
        local f = item.facts
        local bound = f and f.isBound
        if bound == nil then
            local loc = Location(item)
            bound = loc and C_Item.IsBound(loc) or false
        end
        if bound then return false end
        local wue = f and f.isWuE
        if wue == nil then
            local loc = Location(item)
            if loc then
                wue = C_Item.IsBoundToAccountUntilEquip(loc)
            else
                wue = C_Item.IsItemBindToAccountUntilEquip(item.link)
            end
        end
        local bind
        if not wue then
            bind = f and f.bindType
            if bind == nil then bind = Info(item) and item._bind end
        end
        -- The quality only colors a BoE label: an uncached item would wait for its data
        local text, c = BindLabel(wue, bind, not wue and bind == BIND_ON_EQUIP and Quality(item) or nil)
        if not text then return false end
        out.text = text
        if c then out.r, out.g, out.b = c.r, c.g, c.b end
        return true
    end,
})

Register("setName", {
    kind = "text", insetX = 1, insetY = 2, fitWidth = true,
    Apply = function(item, _, out)
        local f = item.facts
        local name = f and f.setName
        if name == nil then
            local bag, slot = item.bag, item.slot
            if not (bag and slot) then return false end
            local inSet, list = C_Container.GetContainerItemEquipmentSetInfo(bag, slot)
            -- The list names every set holding the item; the first one shows
            name = inSet and list and (list:match("^(.-), ") or list)
        end
        if not name or name == "" then return false end
        out.text = name
        return true
    end,
})

Register("craftingQuality", {
    kind = "icon", insetX = -3, insetY = -2,
    Apply = function(item, _, out)
        -- Reagent quality first, then crafted, as Blizzard's item buttons ask
        local link = item.link
        local info = C_TradeSkillUI.GetItemReagentQualityInfo(link)
            or C_TradeSkillUI.GetItemCraftedQualityInfo(link)
        if not info then return false end
        out.atlas = info.iconInventory
        return true
    end,
})

-- EUI Bags' junk badge for Poor quality with a sell price, or for the Junk
-- Marker's verdict when EUI Bags passes it
Register("junkCoin", {
    kind = "icon", insetX = -3, insetY = -3,
    texCoord = JUNK_BADGE.texCoord, mask = JUNK_BADGE.mask,
    Apply = function(item, _, out)
        local f = item.facts
        local junk = f and f.isJunk
        if junk == nil then
            junk = Quality(item) == POOR and Info(item) and (item._sell or 0) > 0
        end
        if not junk then return false end
        out.texture = JUNK_BADGE.texture
        return true
    end,
})

-- An item that starts a quest not yet accepted
Register("questMarker", {
    kind = "icon", insetX = -3, insetY = 2,
    Apply = function(item, _, out)
        local f = item.facts
        local starter = f and f.questStarter
        if starter == nil then
            local bag, slot = item.bag, item.slot
            if not (bag and slot) then return false end
            local info = C_Container.GetContainerItemQuestInfo(bag, slot)
            starter = info.questID ~= nil and not info.isActive
        end
        if not starter then return false end
        out.atlas = "Crosshair_Quest_64"
        return true
    end,
})

Register("keystoneLevel", {
    kind = "text",
    Apply = function(item, _, out)
        local level = Keystone(item)
        if not level then return false end
        out.text = level
        local c = C_ChallengeMode.GetKeystoneLevelRarityColor(level)
        out.r, out.g, out.b = c.r, c.g, c.b
        return true
    end,
})

Register("keystoneDungeon", {
    kind = "text", insetX = 1, insetY = 2,
    Apply = function(item, _, out)
        if not Keystone(item) or not item._ksMap then return false end
        local abbr = AbbrevDungeon(item._ksMap)
        if abbr == "" then return false end
        out.text = abbr
        return true
    end,
})

-------------------------------------------------------------------------------
--  Upgrade arrow: gear the current spec can use whose item level beats the
--  lowest level equipped in the slots it fills (an empty slot counts as 0)
-------------------------------------------------------------------------------
local MH, OH = INVSLOT_MAINHAND, INVSLOT_OFFHAND
-- WoW Forever keeps ranged weapons in their own slot; retail in the main hand
local RANGED = EllesmereUI.IS_FOREVER and INVSLOT_RANGED or MH
local EQUIP_SLOTS = {
    INVTYPE_HEAD = { INVSLOT_HEAD }, INVTYPE_NECK = { INVSLOT_NECK }, INVTYPE_SHOULDER = { INVSLOT_SHOULDER },
    INVTYPE_CLOAK = { INVSLOT_BACK }, INVTYPE_CHEST = { INVSLOT_CHEST }, INVTYPE_ROBE = { INVSLOT_CHEST },
    INVTYPE_WRIST = { INVSLOT_WRIST }, INVTYPE_HAND = { INVSLOT_HAND }, INVTYPE_WAIST = { INVSLOT_WAIST },
    INVTYPE_LEGS = { INVSLOT_LEGS }, INVTYPE_FEET = { INVSLOT_FEET },
    INVTYPE_FINGER = { INVSLOT_FINGER1, INVSLOT_FINGER2 }, INVTYPE_TRINKET = { INVSLOT_TRINKET1, INVSLOT_TRINKET2 },
    INVTYPE_WEAPON = { MH, OH }, INVTYPE_2HWEAPON = { MH }, INVTYPE_WEAPONMAINHAND = { MH },
    INVTYPE_WEAPONOFFHAND = { OH }, INVTYPE_SHIELD = { OH }, INVTYPE_HOLDABLE = { OH },
    INVTYPE_RANGED = { RANGED }, INVTYPE_RANGEDRIGHT = { RANGED }, INVTYPE_THROWN = { RANGED },
    INVTYPE_RELIC = { RANGED },
}
-- Main-hand items that leave the off hand empty
local BOTH_HANDS = { INVTYPE_2HWEAPON = true, INVTYPE_RANGED = RANGED == MH, INVTYPE_RANGEDRIGHT = RANGED == MH }
local equippedLoc = ItemLocation:CreateEmpty()
local classID

-- The level of the item equipped in slot; 0 for an empty slot
local function EquippedLevel(slot)
    equippedLoc:SetEquipmentSlot(slot)
    if not C_Item.DoesItemExist(equippedLoc) then return 0 end
    return C_Item.GetCurrentItemLevel(equippedLoc) or 0
end

-- The lowest level among the slots the item fills. A one-hander fills the off
-- hand only for a class that dual wields; an off-hand item replaces the
-- two-hander that leaves the off hand empty.
local function ReplacedLevel(equipLoc, slots)
    local lowest
    for i = 1, #slots do
        local slot = slots[i]
        if slot ~= OH or equipLoc ~= "INVTYPE_WEAPON" or CanDualWield() then
            local level = EquippedLevel(slot)
            if slot == OH and level == 0 then
                local mainID = GetInventoryItemID("player", MH)
                if mainID and BOTH_HANDS[select(4, GetItemInfoInstant(mainID))] then level = EquippedLevel(MH) end
            end
            if not lowest or level < lowest then lowest = level end
        end
    end
    return lowest
end

Register("upgradeArrow", {
    kind = "icon",
    Apply = function(item, _, out)
        -- Gear already equipped, or another player's, is no upgrade for you
        local frameKey = item.frameKey
        if frameKey == "charsheet" or frameKey == "inspect" or not IsGear(item) then return false end
        local itemID, _, _, equipLoc = GetItemInfoInstant(item.link)
        local slots = EQUIP_SLOTS[equipLoc]
        if not slots then return false end
        local level = ItemLevel(item)
        if not level or not C_PlayerInfo.CanUseItem(itemID) then return false end
        if not classID then classID = select(3, UnitClass("player")) end
        if not C_Item.DoesItemContainSpec(item.link, classID, EllesmereUI._specID or 0) then return false end
        if level <= ReplacedLevel(equipLoc, slots) then return false end
        out.atlas = "bags-greenarrow"
        return true
    end,
})

-- Equipping gear or changing spec moves the arrows: every managed frame
-- repaints. Registered only while the arrow is placed and Item Icons is on
local arrowEvents = CreateFrame("Frame")
arrowEvents:SetScript("OnEvent", function() II.RequestRefresh(nil) end)
II.Subscribe(function()
    if II.IsEnabled() and II.IsElementPlaced("upgradeArrow") then
        arrowEvents:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        arrowEvents:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    else
        arrowEvents:UnregisterAllEvents()
    end
end)
