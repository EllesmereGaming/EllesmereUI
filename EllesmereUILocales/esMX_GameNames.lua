if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Spanish (Mexico) world object names exactly as the game shows them: game data, never reworded.
-- Read only by esMX game clients, whatever the EUI Options Language.

local G = EllesmereUI.RegisterGameNames("esMX")
if not G then return end

-- Ore nodes (WoW Forever gathering skill tooltips)
G["Copper Vein"] = "Filón de cobre"
G["Tin Vein"] = "Filón de estaño"
G["Incendicite Mineral Vein"] = "Filón de incendicita"
G["Silver Vein"] = "Filón de plata"
G["Lesser Bloodstone Deposit"] = "Depósito de sangrita inferior"
G["Iron Deposit"] = "Depósito de hierro"
G["Indurium Mineral Vein"] = "Filón de indurio"
G["Gold Vein"] = "Filón de oro"
G["Mithril Deposit"] = "Depósito de mitril"
G["Ooze Covered Mithril Deposit"] = "Depósito de mitril cubierto de moco"
G["Truesilver Deposit"] = "Depósito de veraplata"
G["Dark Iron Deposit"] = "Depósito de hierro negro"
G["Small Thorium Vein"] = "Filón pequeño de torio"
G["Ooze Covered Thorium Vein"] = "Filón de torio cubierto de moco"
G["Rich Thorium Vein"] = "Filón de torio enriquecido"
G["Ooze Covered Rich Thorium Vein"] = "Filón de torio enriquecido cubierto de moco"
