if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-- German (Germany) world object names exactly as the game shows them: game data, never reworded.
-- Read only by deDE game clients, whatever the EUI Options Language.

local G = EllesmereUI.RegisterGameNames("deDE")
if not G then return end

-- Ore nodes (WoW Forever gathering skill tooltips)
G["Copper Vein"] = "Kupfervorkommen"
G["Tin Vein"] = "Zinnvorkommen"
G["Incendicite Mineral Vein"] = "Pyrophor-Mineralvorkommen"
G["Silver Vein"] = "Silbervorkommen"
G["Ooze Covered Silver Vein"] = "Brühschlammbedecktes Silbervorkommen"
G["Lesser Bloodstone Deposit"] = "Geringe Blutsteinablagerung"
G["Iron Deposit"] = "Eisenvorkommen"
G["Indurium Mineral Vein"] = "Indurium-Mineralvorkommen"
G["Gold Vein"] = "Goldvorkommen"
G["Ooze Covered Gold Vein"] = "Brühschlammbedecktes Goldvorkommen"
G["Mithril Deposit"] = "Mithrilvorkommen"
G["Ooze Covered Mithril Deposit"] = "Brühschlammbedeckte Mithrilablagerung"
G["Truesilver Deposit"] = "Echtsilbervorkommen"
G["Ooze Covered Truesilver Deposit"] = "Brühschlammbedeckte Echtsilberablagerung"
G["Dark Iron Deposit"] = "Dunkeleisenvorkommen"
G["Small Thorium Vein"] = "Kleines Thoriumvorkommen"
G["Ooze Covered Thorium Vein"] = "Brühschlammbedecktes Thoriumvorkommen"
G["Rich Thorium Vein"] = "Reiches Thoriumvorkommen"
G["Ooze Covered Rich Thorium Vein"] = "Brühschlammbedecktes reiches Thoriumvorkommen"
G["Hakkari Thorium Vein"] = "Hakkari Thoriumvorkommen"

-- Herb nodes named unlike their herb (WoW Forever gathering skill tooltips)
G["Mountain Silversage"] = "Bergsilbersalbei"
