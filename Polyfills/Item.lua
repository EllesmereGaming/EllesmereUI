-- C_Item
if not C_Item then
    C_Item = {}

    C_Item.GetItemInfo = function(item)
        return GetItemInfo(item)
    end

    C_Item.GetItemCount = function(item, includeBank, includeReagentBank)
        return GetItemCount(item, includeBank)
    end

    C_Item.GetItemIconByID = function(itemID)
        if not itemID then return nil end
        local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID)
        return itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    C_Item.GetItemSpell = function(item)
        return GetItemSpell(item)
    end

    C_Item.GetItemQualityByID = function(itemLink)
        if not itemLink then return nil end
        return select(3, GetItemInfo(itemLink))
    end

    C_Item.GetItemQualityColor = function(rarity)
        return GetItemQualityColor(rarity)
    end

    C_Item.GetItemStats = function(itemLink)
        if not itemLink then return nil end
        return GetItemStats(itemLink)
    end

    C_Item.GetItemGem = function(itemLink, index)
        if type(itemLink) ~= "string" or not index then return nil end
        local parts = { itemLink:match("item:(%d*):(%d*):(%d*):(%d*):(%d*):(%d*)") }
        local gemID = tonumber(parts[2 + index])
        if gemID and gemID > 0 then
            local gemLink = select(2, GetItemInfo(gemID))
            return nil, gemLink
        end
        return nil
    end

    C_Item.RequestLoadItemDataByID = function(itemID)
        -- No-op fallback
    end

    C_Item.GetItemMaxStackSizeByID = function(itemID)
        if not itemID then return 1 end
        return select(8, GetItemInfo(itemID)) or 1
    end

    C_Item.GetDetailedItemLevelInfo = function(itemLink)
        if not itemLink then return 0 end
        return select(4, GetItemInfo(itemLink)) or 0
    end

    C_Item.GetItemInfoInstant = function(item)
        if not item then return nil end
        local name, link, rarity, level, minLevel, type, subType, stackCount, equipLoc, texture, price, classID, subclassID = GetItemInfo(item)
        local itemID = tonumber(item) or tonumber(tostring(item):match("item:(%d+)"))
        return itemID, type, subType, equipLoc, texture, classID, subclassID
    end

    C_Item.DoesItemExist = function(loc)
        if not loc then return false end
        if loc:IsBagAndSlot() then
            local bag, slot = loc:GetBagAndSlot()
            return GetContainerItemLink(bag, slot) ~= nil
        elseif loc:IsEquipmentSlot() then
            local eqSlot = loc:GetEquipmentSlot()
            return GetInventoryItemLink("player", eqSlot) ~= nil
        end
        return false
    end

    C_Item.GetCurrentItemLevel = function(loc)
        if not loc then return 0 end
        local link
        if loc:IsBagAndSlot() then
            local bag, slot = loc:GetBagAndSlot()
            link = GetContainerItemLink(bag, slot)
        elseif loc:IsEquipmentSlot() then
            local eqSlot = loc:GetEquipmentSlot()
            link = GetInventoryItemLink("player", eqSlot)
        end
        if link then
            return select(4, GetItemInfo(link)) or 0
        end
        return 0
    end

    C_Item.IsLocked = function(loc)
        if not loc then return false end
        if loc:IsBagAndSlot() then
            local bag, slot = loc:GetBagAndSlot()
            return select(3, GetContainerItemInfo(bag, slot)) == true
        elseif loc:IsEquipmentSlot() then
            local eqSlot = loc:GetEquipmentSlot()
            return IsInventoryItemLocked(eqSlot) == true
        end
        return false
    end

    C_Item.IsBoundToAccountUntilEquip = function(loc)
        return false
    end
end

-- Tooltip Scanner for isBound (Soulbound) checking
local tooltipScanner
local function IsItemBound(bag, slot)
    if not tooltipScanner then
        tooltipScanner = CreateFrame("GameTooltip", "EllesmereUITooltipScanner", nil, "GameTooltipTemplate")
        tooltipScanner:SetOwner(WorldFrame, "ANCHOR_NONE")
    end
    tooltipScanner:ClearLines()
    tooltipScanner:SetBagItem(bag, slot)
    for i = 1, tooltipScanner:NumLines() do
        local fontStr = _G["EllesmereUITooltipScannerTextLeft" .. i]
        local text = fontStr and fontStr:GetText()
        if text == ITEM_SOULBOUND then
            return true
        end
    end
    return false
end


-- ItemLocation Object Mock
ItemLocation = ItemLocation or {}
ItemLocation.__index = ItemLocation

function ItemLocation:CreateFromBagAndSlot(bag, slot)
    local obj = setmetatable({}, self)
    obj.bag = bag
    obj.slot = slot
    return obj
end

function ItemLocation:CreateFromEquipmentSlot(slotID)
    local obj = setmetatable({}, self)
    obj.equipmentSlot = slotID
    return obj
end

function ItemLocation:CreateFromGUID(guid)
    local obj = setmetatable({}, self)
    obj.guid = guid
    return obj
end

function ItemLocation:CreateEmpty()
    return setmetatable({}, self)
end

function ItemLocation:IsValid()
    return self:HasAnyLocation()
end

function ItemLocation:HasAnyLocation()
    return self.bag ~= nil or self.equipmentSlot ~= nil or self.guid ~= nil
end

function ItemLocation:Clear()
    self.bag = nil
    self.slot = nil
    self.equipmentSlot = nil
    self.guid = nil
end

function ItemLocation:IsEqualTo(other)
    if not other then return false end
    return self.bag == other.bag and self.slot == other.slot and self.equipmentSlot == other.equipmentSlot and self.guid == other.guid
end

function ItemLocation:GetBagAndSlot()
    return self.bag, self.slot
end

function ItemLocation:GetEquipmentSlot()
    return self.equipmentSlot
end

function ItemLocation:IsEquipmentSlot()
    return self.equipmentSlot ~= nil
end

function ItemLocation:IsBagAndSlot()
    return self.bag ~= nil and self.slot ~= nil
end
