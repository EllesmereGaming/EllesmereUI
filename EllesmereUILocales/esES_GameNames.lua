if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Spanish (Spain) world object names exactly as the game shows them: game data, never reworded.
-- Read only by esES game clients, whatever the EUI Options Language.

local G = EllesmereUI.RegisterGameNames("esES")
if not G then return end

-- Ore nodes (WoW Forever gathering skill tooltips)
G["Copper Vein"] = "Filón de cobre"
G["Tin Vein"] = "Filón de estaño"
G["Incendicite Mineral Vein"] = "Filón de incendicita"
G["Silver Vein"] = "Filón de plata"
G["Ooze Covered Silver Vein"] = "Filón de plata cubierto de moco"
G["Lesser Bloodstone Deposit"] = "Depósito de Petrosangre inferior"
G["Iron Deposit"] = "Depósito de hierro"
G["Indurium Mineral Vein"] = "Filón de indurio"
G["Gold Vein"] = "Filón de oro"
G["Ooze Covered Gold Vein"] = "Filón de oro cubierto de moco"
G["Mithril Deposit"] = "Depósito de mitril"
G["Ooze Covered Mithril Deposit"] = "Depósito de mitril cubierto de moco"
G["Truesilver Deposit"] = "Depósito de veraplata"
G["Ooze Covered Truesilver Deposit"] = "Depósito de veraplata cubierta de moco"
G["Dark Iron Deposit"] = "Depósito de los Hierro Negro"
G["Small Thorium Vein"] = "Filón pequeño de torio"
G["Ooze Covered Thorium Vein"] = "Filón de torio cubierto de moco"
G["Rich Thorium Vein"] = "Filón de torio enriquecido"
G["Ooze Covered Rich Thorium Vein"] = "Filón de torio enriquecido cubierto de moco"
G["Hakkari Thorium Vein"] = "Filon de torio de Hakkari"

-- Herb nodes named unlike their herb (WoW Forever gathering skill tooltips)
G["Khadgar's Whisker"] = "Vibrisa de Khadgar"
G["Firebloom"] = "Flor de fuego"
G["Purple Lotus"] = "Loto cárdeno"
G["Plaguebloom"] = "flor de peste"
