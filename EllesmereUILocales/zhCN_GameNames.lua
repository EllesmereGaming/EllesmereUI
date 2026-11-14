if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Simplified Chinese world object names exactly as the game shows them: game data, never reworded.
-- Read only by zhCN game clients, whatever the EUI Options Language.

local G = EllesmereUI.RegisterGameNames("zhCN")
if not G then return end

-- Ore nodes (WoW Forever gathering skill tooltips)
G["Copper Vein"] = "铜矿"
G["Tin Vein"] = "锡矿"
G["Incendicite Mineral Vein"] = "火岩矿脉"
G["Silver Vein"] = "银矿"
G["Ooze Covered Silver Vein"] = "软泥覆盖的银矿脉"
G["Lesser Bloodstone Deposit"] = "次级血石矿脉"
G["Iron Deposit"] = "铁矿石"
G["Indurium Mineral Vein"] = "精铁矿脉"
G["Gold Vein"] = "金矿石"
G["Ooze Covered Gold Vein"] = "软泥覆盖的金矿脉"
G["Mithril Deposit"] = "秘银矿脉"
G["Ooze Covered Mithril Deposit"] = "软泥覆盖的秘银矿脉"
G["Truesilver Deposit"] = "真银矿石"
G["Ooze Covered Truesilver Deposit"] = "软泥覆盖的真银矿脉"
G["Dark Iron Deposit"] = "黑铁矿脉"
G["Small Thorium Vein"] = "瑟银矿脉"
G["Ooze Covered Thorium Vein"] = "软泥覆盖的瑟银矿脉"
G["Rich Thorium Vein"] = "富瑟银矿"
G["Ooze Covered Rich Thorium Vein"] = "软泥覆盖的富瑟银矿脉"
G["Hakkari Thorium Vein"] = "哈卡莱瑟银矿脉"
