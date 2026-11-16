if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Russian world object names exactly as the game shows them: game data, never reworded.
-- Read only by ruRU game clients, whatever the EUI Options Language.

local G = EllesmereUI.RegisterGameNames("ruRU")
if not G then return end

-- Ore nodes (WoW Forever gathering skill tooltips)
G["Copper Vein"] = "Медная жила"
G["Tin Vein"] = "Оловянная жила"
G["Incendicite Mineral Vein"] = "Ароматитовая жила"
G["Silver Vein"] = "Серебряная жила"
G["Ooze Covered Silver Vein"] = "Покрытая слизью серебряная жила"
G["Lesser Bloodstone Deposit"] = "Малое месторождение кровавого камня"
G["Iron Deposit"] = "Залежи железа"
G["Indurium Mineral Vein"] = "Индарилиевая жила"
G["Gold Vein"] = "Золотая жила"
G["Ooze Covered Gold Vein"] = "Покрытая слизью золотая жила"
G["Mithril Deposit"] = "Мифриловые залежи"
G["Ooze Covered Mithril Deposit"] = "Покрытые слизью мифриловые залежи"
G["Truesilver Deposit"] = "Залежи истинного серебра"
G["Ooze Covered Truesilver Deposit"] = "Покрытые слизью залежи истинного серебра"
G["Dark Iron Deposit"] = "Залежи черного железа"
G["Small Thorium Vein"] = "Малая ториевая жила"
G["Ooze Covered Thorium Vein"] = "Покрытая слизью ториевая жила"
G["Rich Thorium Vein"] = "Богатая ториевая жила"
G["Ooze Covered Rich Thorium Vein"] = "Покрытая слизью богатая ториевая жила"
G["Hakkari Thorium Vein"] = "Ториевая жила Хаккари"
