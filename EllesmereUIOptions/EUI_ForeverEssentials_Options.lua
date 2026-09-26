if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_ForeverEssentials_Options.lua
--  Registers the Forever Essentials sidebar addon (WoW Forever only) with its
--  tabs:
--    * Travel -- flight timer (built by EUI_ForeverEssentials_Travel_Options.lua)
--    * Threat -- threat meter (built by EUI_ForeverEssentials_Threat_Options.lua)
-------------------------------------------------------------------------------
-- Page names are DEEP-LINK IDENTIFIERS: every NavigateToElementSettings tuple
-- and What's New nav carries them as strings and fails SILENTLY on a mismatch.
if not EllesmereUI._ModuleNS["EllesmereUIForeverEssentials"] then return end  -- module disabled: no options page

local PAGE_TRAVEL = "Travel"
local PAGE_THREAT = "Threat"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    EllesmereUI:RegisterModule("EllesmereUIForeverEssentials", {
        title       = "Forever Essentials",
        description = "Essential tools for WoW Forever.",
        pages       = { PAGE_TRAVEL, PAGE_THREAT },
        searchTerms = { "flight timer", "flight path", "threat", "threat meter", "aggro" },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_TRAVEL and _G._EUI_BuildFlightTimerPage then
                return _G._EUI_BuildFlightTimerPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_THREAT and _G._EUI_BuildThreatMeterPage then
                return _G._EUI_BuildThreatMeterPage(pageName, parent, yOffset)
            end
        end,
        onReset = function()
            if EllesmereUIDB then
                EllesmereUIDB.flightTimer = nil
                EllesmereUIDB.threatMeter = nil
                if EllesmereUIDB.unlockAnchors then
                    EllesmereUIDB.unlockAnchors.EUI_FlightTimer = nil
                    EllesmereUIDB.unlockAnchors.EUI_ThreatMeter = nil
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
            EllesmereUI:InvalidatePageCache()
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
