if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Korean world object names exactly as the game shows them: game data, never reworded.
-- Read only by koKR game clients, whatever the EUI Options Language.

local G = EllesmereUI.RegisterGameNames("koKR")
if not G then return end

-- Ore nodes (WoW Forever gathering skill tooltips)
G["Copper Vein"] = "구리 광맥"
G["Tin Vein"] = "주석 광맥"
G["Incendicite Mineral Vein"] = "발연 광맥"
G["Silver Vein"] = "은 광맥"
G["Ooze Covered Silver Vein"] = "진흙으로 덮인 은 광맥"
G["Lesser Bloodstone Deposit"] = "저급 혈석 광맥"
G["Iron Deposit"] = "철 광맥"
G["Indurium Mineral Vein"] = "인듀리움 광맥"
G["Gold Vein"] = "금 광맥"
G["Ooze Covered Gold Vein"] = "진흙으로 덮인 금 광맥"
G["Mithril Deposit"] = "미스릴 광맥"
G["Ooze Covered Mithril Deposit"] = "진흙으로 덮인 미스릴 광맥"
G["Truesilver Deposit"] = "진은 광맥"
G["Ooze Covered Truesilver Deposit"] = "진흙으로 덮인 진은 광맥"
G["Dark Iron Deposit"] = "검은무쇠 광맥"
G["Small Thorium Vein"] = "작은 토륨 광맥"
G["Ooze Covered Thorium Vein"] = "진흙으로 덮인 토륨 광맥"
G["Rich Thorium Vein"] = "풍부한 토륨 광맥"
G["Ooze Covered Rich Thorium Vein"] = "진흙으로 덮인 풍부한 토륨 광맥"
G["Hakkari Thorium Vein"] = "학카리 토륨 광맥"

-- Herb nodes named unlike their herb (WoW Forever gathering skill tooltips)
G["Silverleaf"] = "은엽수 덤불"
G["Mageroyal"] = "마법초"
