if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_Options.lua
--  Registers the Forever Essentials sidebar addon (WoW Forever only) with its
--  tabs:
--    * General -- quality of life features (built by EUI_ForeverEssentials_General_Options.lua)
--    * Travel -- flight timer (built by EUI_ForeverEssentials_Travel_Options.lua)
--    * Threat -- threat meter (built by EUI_ForeverEssentials_Threat_Options.lua)
--    * Loot   -- loot feed (built by EUI_ForeverEssentials_Loot_Options.lua)
--    * Macros -- macro manager (built by EUI_ForeverEssentials_Macros_Options.lua)
-------------------------------------------------------------------------------
-- Page names are DEEP-LINK IDENTIFIERS: every NavigateToElementSettings tuple
-- and What's New nav carries them as strings and fails SILENTLY on a mismatch.
if not EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"] then return end  -- module disabled: no options page

local PAGE_GENERAL = "General"
local PAGE_TRAVEL  = "Travel"
local PAGE_THREAT  = "Threat"
local PAGE_LOOT    = "Loot"
local PAGE_MACROS  = "Macros"

-- Page reuse: a frame this file builds goes through the options frame pool
-- (EllesmereUI_FramePool.lua, the options addon's first file), which hands a
-- kept page its previous build's frames back reset to new; on any other
-- parent it is the plain CreateFrame. The buildPage below only hands each
-- tab to its own page file.
local CreateFrame = EllesmereUI._Pool.CreateFrame

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    EllesmereUI:RegisterModule("EllesmereUIForeverEssentials", {
        title       = "Forever Essentials",
        description = "Essential tools for WoW Forever.",
        pages       = { PAGE_GENERAL, PAGE_TRAVEL, PAGE_THREAT, PAGE_LOOT, PAGE_MACROS },
        searchTerms = { "flight timer", "flight path", "threat", "threat meter", "aggro", "loot", "loot feed", "reputation", "currency", "uprank", "spell rank", "junk", "junk items", "macro", "macros", "macro manager", "simplified stats", "item stats", "stat colors", "tooltip stats", "world map", "map", "reveal", "unexplored", "fog of war", "fishing skill", "quest reward", "quest rewards", "sell value", "boat", "zeppelin", "zone exit", "dungeon entrance", "instance" },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_GENERAL and _G._EUI_BuildForeverGeneralPage then
                return _G._EUI_BuildForeverGeneralPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_TRAVEL and _G._EUI_BuildFlightTimerPage then
                return _G._EUI_BuildFlightTimerPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_THREAT and _G._EUI_BuildThreatMeterPage then
                return _G._EUI_BuildThreatMeterPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_LOOT and _G._EUI_BuildLootFeedPage then
                return _G._EUI_BuildLootFeedPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_MACROS and _G._EUI_BuildForeverMacrosPage then
                return _G._EUI_BuildForeverMacrosPage(pageName, parent, yOffset)
            end
        end,
        -- The Travel, Threat, Loot and Macros headers live in the content header; declaring a
        -- page's builder makes a cached page whose header was dropped rebuild with it.
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_TRAVEL then return _G._EUI_TravelHeaderBuilder end
            if pageName == PAGE_THREAT then return _G._EUI_ThreatHeaderBuilder end
            if pageName == PAGE_LOOT then return _G._EUI_LootHeaderBuilder end
            if pageName == PAGE_MACROS and EllesmereUI._MacroManager.Enabled() then return _G._EUI_MacrosHeaderBuilder end
        end,
        resetScope = "account",
        onReset = function()
            if EllesmereUIDB then
                EllesmereUIDB.flightTimer = nil
                EllesmereUIDB.threatMeter = nil
                EllesmereUIDB.lootFeed = nil
                EllesmereUIDB.spellUprank = nil
                EllesmereUIDB.junkList = nil
                EllesmereUIDB.junkListExcluded = nil
                EllesmereUIDB.simplifiedStats = nil
                EllesmereUIDB.activeForm = nil
                EllesmereUIDB.classicSpellbook = nil
                EllesmereUIDB.classicTalents = nil
                EllesmereUIDB.macroManager = nil
                EllesmereUIDB.questRewards = nil
                EllesmereUIDB.zoneLevels = nil
                -- The per-character favorites are the player's picks: only the switch resets.
                if EllesmereUIDB.petSummon then EllesmereUIDB.petSummon.enabled = nil end
                -- The CVars a session holds stay recorded, so Apply can give them back.
                local fi = EllesmereUIDB.fishing
                EllesmereUIDB.fishing = fi and fi.held and { held = fi.held } or nil
                EllesmereUIDB.mapTravel = nil
                -- The game's mapFade from before stays, so Apply can give it back.
                local mf = EllesmereUIDB.worldMapFade
                EllesmereUIDB.worldMapFade = mf and mf.mapFadeWas ~= nil and { mapFadeWas = mf.mapFadeWas } or nil
                EllesmereUIDB.gatherSkill = nil
                if EllesmereUIDB.unlockAnchors then
                    EllesmereUIDB.unlockAnchors.EUI_FlightTimer = nil
                    EllesmereUIDB.unlockAnchors.EUI_ThreatMeter = nil
                    EllesmereUIDB.unlockAnchors.EUI_LootFeed = nil
                    EllesmereUIDB.unlockAnchors.EUI_JunkList = nil
                    EllesmereUIDB.unlockAnchors.EUI_ActiveForm = nil
                end
            end
            local FT = EllesmereUI._FlightTimer
            if FT then
                FT.Apply()
                FT.ApplyStyle()
                FT.ApplyPosition()
            end
            local TM = EllesmereUI._ThreatMeter
            if TM then
                TM.Apply()
                TM.ApplyStyle()
                TM.ApplyPosition()
            end
            local LF = EllesmereUI._LootFeed
            if LF then
                LF.Apply()
                LF.ApplyStyle()
                LF.ApplyPosition()
            end
            if EllesmereUI._SpellUprank then EllesmereUI._SpellUprank.Apply() end
            if EllesmereUI._JunkItems then EllesmereUI._JunkItems.Apply() end
            if EllesmereUI._ActiveForm then EllesmereUI._ActiveForm.Apply() end
            if EllesmereUI._ClassicSpellbook then EllesmereUI._ClassicSpellbook.Apply() end
            if EllesmereUI._ClassicTalents then EllesmereUI._ClassicTalents.Apply() end
            if EllesmereUI._QuestRewards then EllesmereUI._QuestRewards.Apply() end
            if EllesmereUI._ZoneLevels then EllesmereUI._ZoneLevels.Apply() end
            if EllesmereUI._PetSummon then EllesmereUI._PetSummon.Apply() end
            if EllesmereUI._Fishing then EllesmereUI._Fishing.Apply() end
            if EllesmereUI._MapTravel then EllesmereUI._MapTravel.Apply() end
            if EllesmereUI._MapFade then EllesmereUI._MapFade.Apply() end
            if EllesmereUI._GatherSkill then EllesmereUI._GatherSkill.Apply() end
            EllesmereUI:InvalidatePageCache()
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
