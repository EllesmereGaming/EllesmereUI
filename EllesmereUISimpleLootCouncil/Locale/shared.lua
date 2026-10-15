if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 

SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local entries = {}


local english = addon.Locale.clientLocale:match("^en") ~= nil
local function add(key, value)
    if type(value) == "string" and (not english or value == key) then
        entries[key] = value
    end
end

add("Close", CLOSE)
add("Cancel", CANCEL)
add("Yes", YES)
add("No", NO)
add("Accept", ACCEPT)
add("Delete", DELETE)
add("OK", OKAY)

addon.Locale.RegisterShared(entries)
