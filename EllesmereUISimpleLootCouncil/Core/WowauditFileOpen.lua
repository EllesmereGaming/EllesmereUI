if EUI_CLIENT_BLOCKED then return end if ... == "SimpleLootCouncil" and SimpleLootCouncil and SimpleLootCouncil.EDITION == "eui" then return end if (select(2, ...)).slcInert then return end




local _, private = ...


local NAMES = { "wowauditTimestamp", "teamID", "difficulties", "wishlistData",
    "bonusRollTargets", "trinketPriorities" }

local held = {}
for _, name in ipairs(NAMES) do
    held[name] = _G[name]
    _G[name] = nil
end
private.wowauditHeld = { names = NAMES, values = held }
