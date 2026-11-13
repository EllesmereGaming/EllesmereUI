if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- French world object names exactly as the game shows them: game data, never reworded.
-- Read only by frFR game clients, whatever the EUI Options Language.

local G = EllesmereUI.RegisterGameNames("frFR")
if not G then return end

-- Ore nodes (WoW Forever gathering skill tooltips)
G["Copper Vein"] = "Filon de cuivre"
G["Tin Vein"] = "Filon d'étain"
G["Incendicite Mineral Vein"] = "Filon d'incendicite"
G["Silver Vein"] = "Filon d'argent"
G["Ooze Covered Silver Vein"] = "Filon d'argent couvert de limon"
G["Lesser Bloodstone Deposit"] = "Gisement de pierre de sang inférieure"
G["Iron Deposit"] = "Gisement de fer"
G["Indurium Mineral Vein"] = "Filon d'indurium"
G["Gold Vein"] = "Filon d'or"
G["Ooze Covered Gold Vein"] = "Filon d'or couvert de limon"
G["Mithril Deposit"] = "Gisement de mithril"
G["Ooze Covered Mithril Deposit"] = "Gisement de mithril couvert de vase"
G["Truesilver Deposit"] = "Gisement de vrai-argent"
G["Ooze Covered Truesilver Deposit"] = "Gisement de vrai-argent couvert de vase"
G["Dark Iron Deposit"] = "Gisement de sombrefer"
G["Small Thorium Vein"] = "Petit filon de thorium"
G["Ooze Covered Thorium Vein"] = "Filon de thorium couvert de limon"
G["Rich Thorium Vein"] = "Riche filon de thorium"
G["Ooze Covered Rich Thorium Vein"] = "Riche filon de thorium couvert de limon"
G["Hakkari Thorium Vein"] = "Filon de thorium Hakkari"
