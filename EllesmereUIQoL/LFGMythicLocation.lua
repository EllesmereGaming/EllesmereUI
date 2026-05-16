-- Main table for the addon
-- Changelog:
-- 2026-05-16: Added QoL options toggle for the Mythic LFG Location module.
--              The toggle now enables/disables event handling and prevents /lfgtest output when disabled.
local LFGML = {
    Name = "LFGMythicLocation",
    Prefix = "|cff00ff00[LFG-Memo]|r"
}

-- Create the event frame
local Frame = CreateFrame("Frame")
Frame:RegisterEvent("ADDON_LOADED")
Frame:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")

-- Function to display the data with the correct layout
local function ShowDungeonInfo(dungeon, leader, title, details)
    -- Separate prints ensure clean newlines and use the short [LFG-Memo] prefix
    print(" ")
    print(LFGML.Prefix .. " ---------------------------------------------")
    print(LFGML.Prefix .. " ** INVITE ACCEPTED **")
    print(LFGML.Prefix .. " Destination: |cffffffff" .. dungeon .. "|r")
    print(LFGML.Prefix .. " Group Leader: |cff00ccff" .. leader .. "|r")

    -- Print Title if available (this contains things like "+7 main 3.2k rio")
    if title and title ~= "" then
        print(LFGML.Prefix .. " Title: |cffffd100" .. title .. "|r")
    end

    -- Print Details/Comment if available
    if details and details ~= "" then
        print(LFGML.Prefix .. " Details: |cffb3b3b3" .. details .. "|r")
    end
    print(LFGML.Prefix .. " ---------------------------------------------")
    print(" ")

    PlaySound(8960, "Master")
end

-- Returns true when the feature is enabled in the QoL options.
local function IsEnabled()
    return not (EllesmereUIDB and EllesmereUIDB.lfgMythicLocation == false)
end

-- Keep the event frame enabled only when the option is active.
local function UpdateEventRegistration()
    if IsEnabled() then
        Frame:RegisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
    else
        Frame:UnregisterEvent("LFG_LIST_APPLICATION_STATUS_UPDATED")
    end
end

-- Exposed for the QoL options toggle to refresh this module's event registration.
_G.EUI_LFGMythicLocation_UpdateState = UpdateEventRegistration

-- Event handler logic
Frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == LFGML.Name then
            print(LFGML.Prefix .. " System ready. Use /lfgtest for a preview.")
            UpdateEventRegistration()
            self:UnregisterEvent("ADDON_LOADED")
        end

    elseif event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
        local searchResultID, newStatus = ...
        
        if newStatus == "inviteaccepted" then
            local data = C_LFGList.GetSearchResultInfo(searchResultID)
            
            if data then
                local activityInfo = C_LFGList.GetActivityInfoTable(data.activityIDs[1])
                
                if activityInfo and activityInfo.categoryID == 2 then
                    local dungeonName = activityInfo.fullName or "Unknown Dungeon"
                    local leaderName = data.leaderName or "Unknown Leader"
                    
                    -- Extract the protected strings (Title and Comment/Details)
                    local groupTitle = data.name or ""
                    local groupDetails = data.comment or ""
                    
                    ShowDungeonInfo(dungeonName, leaderName, groupTitle, groupDetails)
                end
            end
        end
    end
end)

-- Slash Command for manual testing
SLASH_LFGTEST1 = "/lfgtest"
SlashCmdList["LFGTEST"] = function()
    if not IsEnabled() then
        print(LFGML.Prefix .. " Mythic LFG Location is disabled.")
        return
    end

    -- Dynamically gets the name of the testing character
    local currentCharacterName = UnitName("player") or "Katzenhirn"
    
    -- Simulates the exact layout output with your current character as leader
    ShowDungeonInfo("Mythic Dungeon", currentCharacterName, "+7 main 3.2k rio", "Checking raider.io, bring big DPS!")
end