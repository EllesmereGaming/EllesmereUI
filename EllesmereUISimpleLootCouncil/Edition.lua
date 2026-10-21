if EUI_CLIENT_BLOCKED then return end 


local ADDON_NAME, ns = ...


SimpleLootCouncil = SimpleLootCouncil or {}
SimpleLootCouncil.EDITION = "eui"
SimpleLootCouncil.SAVED_VARIABLES = "EllesmereUISimpleLootCouncilDB"

SimpleLootCouncil.RequestReload = function() EllesmereUI.RequestReload() end



EllesmereUI._ModuleNS[ADDON_NAME] = ns
