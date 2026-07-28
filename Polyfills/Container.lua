-- C_Container
if not C_Container then
    C_Container = {}

    C_Container.GetContainerNumSlots = function(bag)
        return GetContainerNumSlots(bag)
    end

    C_Container.GetContainerItemInfo = function(bag, slot)
        local texture, itemCount, locked, quality, readable, lootable, itemLink = GetContainerItemInfo(bag, slot)
        if texture then
            local itemID = itemLink and tonumber(itemLink:match("item:(%d+)"))
            return {
                iconFileID = texture,
                stackCount = itemCount,
                isLocked = locked == 1 or locked == true,
                quality = quality,
                isReadable = readable == 1 or readable == true,
                itemLink = itemLink,
                itemID = itemID,
                isFiltered = false,
                hasNoValue = false,
                isBound = IsItemBound(bag, slot)
            }
        end
        return nil
    end

    C_Container.GetContainerItemLink = function(bag, slot)
        return GetContainerItemLink(bag, slot)
    end

    C_Container.GetContainerItemCooldown = function(bag, slot)
        return GetContainerItemCooldown(bag, slot)
    end

    C_Container.PickupContainerItem = function(bag, slot)
        return PickupContainerItem(bag, slot)
    end

    C_Container.ContainerIDToInventoryID = function(bag)
        return ContainerIDToInventoryID(bag)
    end

    C_Container.GetContainerNumFreeSlots = function(bag)
        return GetContainerNumFreeSlots(bag)
    end

    C_Container.SetItemSearch = function(text)
        -- No-op fallback
    end

    C_Container.SortBags = function()
        -- No-op fallback
    end

    C_Container.SortBank = function()
        -- No-op fallback
    end

    C_Container.GetContainerItemQuestInfo = function(bag, slot)
        local isQuestItem, questId, isActive = GetContainerItemQuestInfo(bag, slot)
        if isQuestItem or questId then
            return {
                isQuestItem = isQuestItem == 1 or isQuestItem == true,
                questID = questId,
                isActive = isActive == 1 or isActive == true,
            }
        end
        return nil
    end
end
