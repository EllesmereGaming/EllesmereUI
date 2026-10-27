if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end



local _, private = ...
local held = private.wowauditHeld
private.wowauditHeld = nil


local function Usable(file)
    return type(file) == "table" and type(file.wowauditTimestamp) == "number"
        and type(file.wishlistData) == "table"
end

local own = _G.SLC_WoWAuditSimData
_G.SLC_WoWAuditSimData = nil

if held then
    local file = {}
    for _, name in ipairs(held.names) do
        file[name] = _G[name]
        _G[name] = held.values[name]
    end

    if not private.slcInert then
        local best
        if Usable(file) then
            file.origin = "RCLootCouncil_wowaudit db.lua"
            best = file
        end
        if Usable(own) and (not best or own.wowauditTimestamp >= best.wowauditTimestamp) then
            own.origin = "SLC_WoWAuditSimData.lua"
            best = own
        end
        if best then
            SimpleLootCouncil = SimpleLootCouncil or {}
            SimpleLootCouncil.WowauditFile = best
        end
    end
end
