if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- Portuguese (Brazil) world object names exactly as the game shows them: game data, never reworded.
-- Read only by ptBR game clients, whatever the EUI Options Language.

local G = EllesmereUI.RegisterGameNames("ptBR")
if not G then return end

-- Ore nodes (WoW Forever gathering skill tooltips)
G["Copper Vein"] = "Veio de Cobre"
G["Tin Vein"] = "Veio de Estanho"
G["Incendicite Mineral Vein"] = "Veio de Incendicita"
G["Silver Vein"] = "Veio de Prata"
G["Ooze Covered Silver Vein"] = "Veio de Prata Coberto de Gosma"
G["Lesser Bloodstone Deposit"] = "Depósito de Pedra-sangrenta Menor"
G["Iron Deposit"] = "Depósito de Ferro"
G["Indurium Mineral Vein"] = "Veio de Indúrio"
G["Gold Vein"] = "Veio de Ouro"
G["Ooze Covered Gold Vein"] = "Veio de Ouro Coberto de Gosma"
G["Mithril Deposit"] = "Depósito de Mithril"
G["Ooze Covered Mithril Deposit"] = "Depósito de Mithril Coberto de Gosma"
G["Truesilver Deposit"] = "Depósito de Veraprata"
G["Ooze Covered Truesilver Deposit"] = "Depósito de Veraprata Coberto de Gosma"
G["Dark Iron Deposit"] = "Depósito de Ferro Negro"
G["Small Thorium Vein"] = "Veio de Tório Escasso"
G["Ooze Covered Thorium Vein"] = "Veio de Tório Coberto de Gosma"
G["Rich Thorium Vein"] = "Veio de Tório Abundante"
G["Ooze Covered Rich Thorium Vein"] = "Veio de Tório Abundante e Coberto de Gosma"
G["Hakkari Thorium Vein"] = "Veio de Tório Hakkari"

-- Herb nodes named unlike their herb (WoW Forever gathering skill tooltips)
G["Grave Moss"] = "Musgo-de-tumba"
G["Khadgar's Whisker"] = "Bigode-de-hadgar"
