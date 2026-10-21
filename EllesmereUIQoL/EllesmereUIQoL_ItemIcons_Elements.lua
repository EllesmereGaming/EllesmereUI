if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIQoL_ItemIcons_Elements.lua
--  Item Icons providers for the overlays EUI drew before Item Icons: item
--  level, upgrade rank, stack count, BoE / WuE, equipment set name, crafting
--  quality, junk coin, quest starter, keystone level and dungeon, Pawn arrow.
--  Insets match the EUI Bags overlays. The element contract and the item and
--  out fields: EllesmereUIQoL_ItemIcons.lua.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local Register = EllesmereUI.ItemIcons.RegisterElement

local GetItemInfo, GetItemInfoInstant = C_Item.GetItemInfo, C_Item.GetItemInfoInstant
-- Not proven on WoW Forever: without it a link-only item is never WuE
local IsLinkWuE = C_Item.IsItemBindToAccountUntilEquip
-- Built by the EllesmereUI.lua gate; an older parent may lack them: no track or
-- crafted color then
local GetUpgradeTrack, GetCraftedTrackColor = EllesmereUI.GetUpgradeTrack, EllesmereUI.GetCraftedTrackColor
local WEAPON, ARMOR = Enum.ItemClass.Weapon, Enum.ItemClass.Armor
local POOR, BIND_ON_EQUIP = Enum.ItemQuality.Poor, Enum.ItemBind.OnEquip
-- WoW Forever: no number under 10,000 abbreviates (EllesmereUI_NumberFormat.lua)
local AbbreviateNumbers = (EllesmereUI.IS_FOREVER and EllesmereUI.ForeverAbbreviateNumbers) or AbbreviateNumbers
-- The game's coin icon, cropped round: EUI Bags' junk badge
local JUNK_COIN = 133784
local ROUND_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

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
        local text, color
        if GetUpgradeTrack then text, color = GetUpgradeTrack(item.link) end
        if text and text ~= "" then
            c = color or false
        else
            c = GetCraftedTrackColor and GetCraftedTrackColor(item.link) or false
        end
        item._trackColor = c
    end
    return c or nil
end

-- Item level and upgrade rank color: Custom Colored, else Default Colors (track,
-- crafted crest, then quality)
local function SetLevelColor(item, out)
    local style = item.styles.itemLevel
    local c
    if style.colorMode == "custom" then
        c = style.customColor
    else
        c = TrackColor(item)
        if not c then
            local q = Quality(item)
            if q then out.r, out.g, out.b = C_Item.GetItemQualityColor(q) end
            return
        end
    end
    out.r, out.g, out.b = c.r, c.g, c.b
end

-- Mythic Keystone level (and _ksMap, its challenge map) from the link; false
-- for any other item
local function Keystone(item)
    local level = item._ksLevel
    if level == nil then
        level = false
        local link = item.link
        if link:find("keystone:", 1, true) then
            local map, lvl = link:match("keystone:[^:]*:(%d+):(%d+)")
            if lvl then level, item._ksMap = tonumber(lvl), tonumber(map) end
        end
        item._ksLevel = level
    end
    return level
end

-- Dungeon initials, connector words skipped and the locale's overrides
-- applied, as EUI Bags abbreviates them
local abbrevs = {}
local SKIP_WORDS = {
    ["of"] = true, ["the"] = true, ["a"] = true, ["an"] = true,
    -- ruRU: iz, za, v, na, i, pod, s
    ["\208\184\208\183"] = true, ["\208\183\208\176"] = true, ["\208\178"] = true,
    ["\208\189\208\176"] = true, ["\208\184"] = true, ["\208\191\208\190\208\180"] = true,
    ["\209\129"] = true,
}
local function DungeonAbbrev(mapID)
    local abbr = abbrevs[mapID]
    if abbr then return abbr end
    local name = C_ChallengeMode.GetMapUIInfo(mapID)
    if not name or name == "" then return "" end
    abbr = ""
    for word in name:gmatch("[^%s%-]+") do
        if not SKIP_WORDS[word:lower()] then
            -- The first whole UTF-8 character
            abbr = abbr .. (word:upper():match("^[%z\1-\127\194-\244][\128-\191]*") or "")
        end
    end
    local override = EllesmereUI._dungeonAbbrevOverride
    if override and override[abbr] then abbr = override[abbr] end
    abbrevs[mapID] = abbr
    return abbr
end

-------------------------------------------------------------------------------
--  Elements
-------------------------------------------------------------------------------
Register("itemLevel", {
    kind = "text",
    Apply = function(item, _, out)
        if not IsGear(item) then return false end
        local f = item.facts
        local level = f and f.itemLevel
        if level == nil then
            local loc = Location(item)
            if loc then level = C_Item.GetCurrentItemLevel(loc) end
            if not level or level <= 0 then level = C_Item.GetDetailedItemLevelInfo(item.link) end
            if not level or level <= 0 then
                Info(item)
                return false
            end
        elseif not level then
            return false
        end
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

-- Unbound Binds when Equipped or Warbound until Equipped gear, as EUI Bags shows
-- it. WuE items report OnEquip as their bind type, so WuE is checked first.
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
            elseif IsLinkWuE then
                wue = IsLinkWuE(item.link)
            end
        end
        local c
        if wue then
            out.text = EllesmereUI.L("WuE")
            c = ITEM_QUALITY_COLORS[7]  -- Heirloom: WuE has no quality of its own
        else
            local bind = f and f.bindType
            if bind == nil then bind = Info(item) and item._bind end
            if bind ~= BIND_ON_EQUIP then return false end
            out.text = EllesmereUI.L("BoE")
            local q = Quality(item)
            c = q and ITEM_QUALITY_COLORS[q]
        end
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

-- Poor quality with a sell price, or the Junk Marker's verdict when EUI Bags passes it
Register("junkCoin", {
    kind = "icon", insetX = -3, insetY = -3,
    texCoord = { 0.12, 0.88, 0.12, 0.88 }, mask = ROUND_MASK,
    Apply = function(item, _, out)
        local f = item.facts
        local junk = f and f.isJunk
        if junk == nil then
            junk = Quality(item) == POOR and Info(item) and (item._sell or 0) > 0
        end
        if not junk then return false end
        out.texture = JUNK_COIN
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
        local abbr = DungeonAbbrev(item._ksMap)
        if abbr == "" then return false end
        out.text = abbr
        return true
    end,
})

-- Pawn's bag upgrade advisor (EUI Bags only, while Pawn shows it)
Register("pawnArrow", {
    kind = "icon", frames = { eui_bags = true },
    Apply = function(item, _, out)
        local f = item.facts
        local upgrade = f and f.pawnUpgrade
        if upgrade == nil then
            local check, pawn = _G.PawnShouldItemLinkHaveUpgradeArrow, _G.PawnCommon
            if type(check) ~= "function" or not (pawn and pawn.ShowBagUpgradeAdvisor) then return false end
            upgrade = check(item.link, true)
            -- nil while Pawn lacks the item's data: repaint when it arrives
            if upgrade == nil then
                item.pending = true
                return false
            end
        end
        if not upgrade then return false end
        out.atlas = "bags-greenarrow"
        return true
    end,
})
