if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end




SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local SimC = {}
addon.SimC = SimC




local SLOT = {
    INVTYPE_HEAD = "head",
    INVTYPE_NECK = "neck",
    INVTYPE_SHOULDER = "shoulder",
    INVTYPE_BODY = "shirt",
    INVTYPE_CHEST = "chest",
    INVTYPE_ROBE = "chest",
    INVTYPE_WAIST = "waist",
    INVTYPE_LEGS = "legs",
    INVTYPE_FEET = "feet",
    INVTYPE_WRIST = "wrist",
    INVTYPE_HAND = "hands",
    INVTYPE_FINGER = "finger1",
    INVTYPE_TRINKET = "trinket1",
    INVTYPE_CLOAK = "back",
    INVTYPE_TABARD = "tabard",
    INVTYPE_SHIELD = "off_hand",
    INVTYPE_HOLDABLE = "off_hand",
    INVTYPE_WEAPONOFFHAND = "off_hand",
    INVTYPE_WEAPONMAINHAND = "main_hand",
    INVTYPE_WEAPON = "main_hand",
    INVTYPE_2HWEAPON = "main_hand",
    INVTYPE_RANGED = "main_hand",
    INVTYPE_RANGEDRIGHT = "main_hand",
    INVTYPE_RANGEDLEFT = "main_hand",
    INVTYPE_THROWN = "main_hand",
    INVTYPE_RELIC = "main_hand",
}

local function Fields(itemString)
    local body = type(itemString) == "string" and itemString:match("^item:(.*)$")
    if not body then return nil end

    local fields = {}
    for field in (body .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = tonumber(field) or 0
    end
    return fields
end

local function Values(fields, first, count)
    local values = {}
    for index = first, first + count - 1 do
        local value = fields[index] or 0
        if value > 0 then values[#values + 1] = value end
    end
    return values
end

local function Gems(fields)
    local last = 2
    for index = 3, 6 do
        if (fields[index] or 0) > 0 then last = index end
    end

    local gems = {}
    for index = 3, last do
        gems[#gems + 1] = fields[index] or 0
    end
    return gems
end





function SimC.Line(itemString, equipLoc)
    local slot = SLOT[equipLoc]
    if equipLoc == nil then
        return nil, T["item information is not cached yet"]
    end
    if not slot then return nil, T["SimC cannot place this item type"] end

    local fields = Fields(itemString)
    local itemID = fields and fields[1]
    if not itemID or itemID <= 0 then return nil, T["item string is invalid"] end

    local options = { ",id=" .. itemID }
    if fields[2] and fields[2] > 0 then options[#options + 1] = "enchant_id=" .. fields[2] end

    local gems = Gems(fields)
    if #gems > 0 then options[#options + 1] = "gem_id=" .. table.concat(gems, "/") end

    local bonusCount = fields[13] or 0
    local bonuses = Values(fields, 14, bonusCount)
    if #bonuses > 0 then options[#options + 1] = "bonus_id=" .. table.concat(bonuses, "/") end

    local modifierOffset = 14 + bonusCount
    local pairCount = fields[modifierOffset] or 0
    local crafted = {}
    for index = 1, pairCount do
        local offset = modifierOffset + 1 + (index - 1) * 2
        local kind, value = fields[offset] or 0, fields[offset + 1] or 0
        if kind == 9 then
            options[#options + 1] = "drop_level=" .. value
        elseif kind == 28 then
            options[#options + 1] = "content_tuning=" .. value
        elseif kind == 29 or kind == 30 then
            crafted[#crafted + 1] = value
        elseif kind == 64 then
            options[#options + 1] = "redirected_base_stats=" .. value
        end
    end
    if #crafted > 0 then options[#options + 1] = "crafted_stats=" .. table.concat(crafted, "/") end

    local gemBonusOffset = modifierOffset + pairCount * 2 + 2
    local gemBonuses = Values(fields, gemBonusOffset + 1, fields[gemBonusOffset] or 0)
    if #gemBonuses > 0 then
        options[#options + 1] = "gem_bonus_id=" .. table.concat(gemBonuses, "/")
    end

    return slot .. "=" .. table.concat(options, ",")
end

local function SessionLines()
    local lines = {}
    for _, item in ipairs(addon.Session:GetItems()) do
        local itemString = addon.Gear.ItemString(item.link)
        local _, _, _, equipLoc = C_Item.GetItemInfoInstant(item.link)
        local line, reason = SimC.Line(itemString, equipLoc)
        if line then
            lines[#lines + 1] = "# " .. line
        else
            lines[#lines + 1] = "# Skipped " .. tostring(item.link) .. ": " .. reason
        end
    end
    return lines
end

function SimC:ExportText()
    if addon.IsForever then return nil, T["SimC export is not available on this client"] end
    local items = addon.Session and addon.Session:GetItems()
    if type(items) ~= "table" or #items == 0 then
        return nil, T["there are no items in the current loot session"]
    end
    local lines = SessionLines()
    if #lines == 0 then return nil, T["there are no items in the current loot session"] end
    return "### SimpleLootCouncil: items in the current loot session\n"
        .. table.concat(lines, "\n") .. "\n"
end

function SimC:Init()
end
