if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end




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



BoERoute.REASON_MAX_LETTERS = 16
BoERoute.DEFAULT_COLOUR = { r = 0.90, g = 0.70, b = 0.20 }

function BoERoute.DefaultReason() return T["Guild Bank"] end


function BoERoute.Note() return T["BoE"] end

local function Channel(value, fallback)
    value = tonumber(value)
    if not value then return fallback end
    return math.max(0, math.min(1, value))
end


function BoERoute.ColourFor(rule)
    local d = BoERoute.DEFAULT_COLOUR
    if type(rule) ~= "table" then return d.r, d.g, d.b end
    return Channel(rule.r, d.r), Channel(rule.g, d.g), Channel(rule.b, d.b)
end


function BoERoute.CleanStamp(stamp)
    if type(stamp) ~= "table" or type(stamp.w) ~= "string" or stamp.w == "" then return nil end
    local text = BoERoute.CleanReason(stamp.t)
    if not text then return nil end
    local r, g, b = BoERoute.ColourFor(stamp)
    return { w = stamp.w, t = text, r = r, g = g, b = b }
end


function BoERoute.CleanReason(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("[%c|]", ""):match("^%s*(.-)%s*$")
    text = addon.Locale.Truncate(text, BoERoute.REASON_MAX_LETTERS)
    if text == "" then return nil end
    return text
end


function BoERoute.ReasonFor(rule)
    return rule and BoERoute.CleanReason(rule.reasonText) or BoERoute.DefaultReason()
end



function BoERoute.RouteFor(item, rule, candidates, bindTypeReader)
    if not rule then return nil end

    local hasWinner = type(rule.winner) == "string" and rule.winner ~= ""
    local custom = BoERoute.CleanReason(rule.reasonText) ~= nil



    if not hasWinner then
        if custom then return nil, addon.Locale.Format(T["Requires a recipient."]) end
        return nil
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

    local reason = BoERoute.ReasonFor(rule)
    if not present then
        return { state = "absent", winner = rule.winner, reason = reason }
    end
    local r, g, b = BoERoute.ColourFor(rule)
    return { state = "routed", winner = rule.winner, reason = reason, r = r, g = g, b = b }
end



function BoERoute:For(item)
    return BoERoute.RouteFor(item, addon.db.boeRoute, addon.GetCandidates(),
        BoERoute.BindTypeFor)
end
