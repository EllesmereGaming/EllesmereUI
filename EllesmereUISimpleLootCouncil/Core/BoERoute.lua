if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local BoERoute = {}
addon.BoERoute = BoERoute



function BoERoute.BindTypeFor(link)
    if not link then return nil end
    local itemName, _, _, _, _, _, _, _, _, _, _, _, _, bindType =
        C_Item.GetItemInfo(link)
    if not itemName then return nil end
    return bindType
end



function BoERoute.RouteFor(item, rule, candidates, bindTypeReader)
    if not rule then return nil end

    local hasWinner = type(rule.winner) == "string" and rule.winner ~= ""
    local hasReason = rule.reason ~= nil


    if not hasWinner and not hasReason then return nil end
    if not hasWinner then return nil, addon.Locale.Format(T["Requires a recipient."]) end
    if not hasReason then
        return nil, addon.Locale.Format(T["Requires a reason to be chosen."])
    end

    if not item or not item.link then return nil end

    local bindType = bindTypeReader and bindTypeReader(item.link)

    if bindType == nil then return nil end
    if bindType ~= Enum.ItemBind.OnEquip then return nil end

    local present = false
    if candidates then
        for name in pairs(candidates) do
            if addon.Player:IsSame(name, rule.winner) then
                present = true
                break
            end
        end
    end

    if not present then
        return { state = "absent", winner = rule.winner, reason = rule.reason }
    end
    return { state = "routed", winner = rule.winner, reason = rule.reason }
end



function BoERoute:For(item)
    return BoERoute.RouteFor(item, addon.db.boeRoute, addon.GetCandidates(),
        BoERoute.BindTypeFor)
end
