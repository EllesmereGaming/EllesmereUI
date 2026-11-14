if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Traditional Chinese world object names exactly as the game shows them: game data, never reworded.
-- Read only by zhTW game clients, whatever the EUI Options Language.

local G = EllesmereUI.RegisterGameNames("zhTW")
if not G then return end

-- Ore nodes (WoW Forever gathering skill tooltips)
G["Copper Vein"] = "銅礦"
G["Tin Vein"] = "錫礦"
G["Silver Vein"] = "銀礦"
G["Lesser Bloodstone Deposit"] = "次級血石礦脈"
G["Iron Deposit"] = "鐵礦床"
G["Indurium Mineral Vein"] = "精鐵礦脈"
G["Gold Vein"] = "金礦脈"
G["Mithril Deposit"] = "秘銀礦床"
G["Ooze Covered Mithril Deposit"] = "軟泥覆蓋的祕銀礦脈"
G["Truesilver Deposit"] = "真銀礦床"
G["Ooze Covered Truesilver Deposit"] = "軟泥覆蓋的真銀礦脈"
G["Dark Iron Deposit"] = "黑鐵礦床"
G["Small Thorium Vein"] = "瑟銀礦脈"
G["Ooze Covered Thorium Vein"] = "軟泥覆蓋的瑟銀礦脈"
G["Rich Thorium Vein"] = "富瑟銀礦"
G["Ooze Covered Rich Thorium Vein"] = "軟泥覆蓋的富瑟銀礦脈"
G["Hakkari Thorium Vein"] = "哈卡萊瑟銀礦脈"

-- Herb nodes named unlike their herb (WoW Forever gathering skill tooltips)
G["Gromsblood"] = "格羅姆高之血"
