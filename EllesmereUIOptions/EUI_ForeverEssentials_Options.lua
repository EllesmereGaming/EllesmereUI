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

local PAGE_GENERAL = "General"
local PAGE_TRAVEL = "Travel"
local PAGE_THREAT = "Threat"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    EllesmereUI:RegisterModule("EllesmereUIForeverEssentials", {
        title       = "Forever Essentials",
        description = "Essential tools for WoW Forever.",
        pages       = { PAGE_GENERAL, PAGE_TRAVEL, PAGE_THREAT },
        searchTerms = { "flight timer", "flight path", "threat", "threat meter", "aggro", "general", "nameplate", "npc difficulty", "color name", "name color", "difficulty color" },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_GENERAL then
                local W = EllesmereUI.Widgets
                local y = yOffset
                local _, h
                parent._showRowDivider = true

                -- "Color nameplate by NPC Difficulty" is a NAMEPLATES setting
                -- (enemyNameTextDifficultyColor) surfaced here on the Forever
                -- Essentials General tab. It reads/writes the live Nameplates
                -- profile directly -- NOT the Forever Essentials DB -- resolving
                -- the profile fresh on every get/set so a profile swap is always
                -- honored, and refreshes the plates via the nameplates module's
                -- global bridge (ns.RefreshAllSettings) so the recolor is instant.
                local function NPProfile()
                    local root = EllesmereUIDB
                    local profiles = root and root.profiles
                    if not profiles then return nil end
                    local pd = profiles[root.activeProfile or "Default"]
                    return pd and pd.addons and pd.addons["EllesmereUINameplates"]
                end

                _, h = W:SectionHeader(parent, "NAMEPLATES", y);  y = y - h

                _, h = W:DualRow(parent, y,
                    { type = "toggle", text = "Color nameplate by NPC Difficulty",
                      tooltip = "Colors the enemy nameplate name text by the unit's level difficulty (grey / green / yellow / orange / red) instead of the Enemy Name Text color. Takes priority over Color Name by Reaction.",
                      getValue = function()
                          local np = NPProfile()
                          return np and np.enemyNameTextDifficultyColor == true
                      end,
                      setValue = function(v)
                          local np = NPProfile()
                          if np then np.enemyNameTextDifficultyColor = v end
                          if _G._ENP_RefreshAllSettings then _G._ENP_RefreshAllSettings() end
                      end },
                    EllesmereUI.BlankRowCfg());  y = y - h

                return math.abs(y)
            end
            if pageName == PAGE_TRAVEL and _G._EUI_BuildFlightTimerPage then
                return _G._EUI_BuildFlightTimerPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_THREAT and _G._EUI_BuildThreatMeterPage then
                return _G._EUI_BuildThreatMeterPage(pageName, parent, yOffset)
            end
        end,
        -- The Threat page's preview lives in the content header; declaring its
        -- builder makes a cached page whose header was dropped rebuild with it.
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_THREAT then return _G._EUI_ThreatHeaderBuilder end
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
