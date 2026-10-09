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

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    EllesmereUI:RegisterModule("EllesmereUIForeverEssentials", {
        title       = "Forever Essentials",
        description = "Essential tools for WoW Forever.",
        pages       = { PAGE_GENERAL, PAGE_TRAVEL, PAGE_THREAT, PAGE_LOOT, PAGE_MACROS },
        searchTerms = { "flight timer", "flight path", "threat", "threat meter", "aggro", "loot", "loot feed", "reputation", "currency", "uprank", "spell rank", "macro", "macros", "macro manager", "ammo", "hunter ammo", "arrows", "bullets", "ammo counter" },
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
            if pageName == PAGE_MACROS then
                local MM = EllesmereUI._MacroManager
                if MM and MM.Enabled() then return _G._EUI_MacrosHeaderBuilder end
            end
        end,
        onReset = function()
            if EllesmereUIDB then
                EllesmereUIDB.flightTimer = nil
                EllesmereUIDB.threatMeter = nil
                EllesmereUIDB.lootFeed = nil
                EllesmereUIDB.spellUprank = nil
                -- The stored builder models are user data: only the switch resets.
                if EllesmereUIDB.macroManager then EllesmereUIDB.macroManager.enabled = nil end
                if EllesmereUIDB.unlockAnchors then
                    EllesmereUIDB.unlockAnchors.EUI_FlightTimer = nil
                    EllesmereUIDB.unlockAnchors.EUI_ThreatMeter = nil
                    EllesmereUIDB.unlockAnchors.EUI_LootFeed = nil
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
            EllesmereUI:InvalidatePageCache()
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
