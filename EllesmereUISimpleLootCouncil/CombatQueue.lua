if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

addon.CombatQueue = EllesmereUI.NewCombatQueue(CreateFrame("Frame"))
