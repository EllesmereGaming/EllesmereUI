-------------------------------------------------------------------------------
--  EllesmereUIQoL_Shifter.lua
--  Shift+drag to permanently reposition Blizzard panels.
--  Ctrl+drag for a temporary move that resets when the panel closes.
-------------------------------------------------------------------------------
local GetFFD = EllesmereUI._GetFFD

-- Temporary positions (per-frame, cleared on hide, not persisted)
local tempPos = {}

-------------------------------------------------------------------------------
--  Frame registry
-------------------------------------------------------------------------------
local PRELOADED = {
    "CharacterFrame",
    "FriendsFrame",
    "PVEFrame",
    "DressUpFrame",
    "BankFrame",
    "MailFrame",
    "GossipFrame",
    "MerchantFrame",
    "AddonList",
    "BonusRollFrame",
    "ChatConfigFrame",
    "ItemTextFrame",
    "LFGDungeonReadyDialog",
    "GuildInviteFrame",
    "TabardFrame",
    "GuildRegistrarFrame",
}

local ADDON_FRAMES = {
    ["Blizzard_AchievementUI"]                     = { "AchievementFrame" },
    ["Blizzard_AlliedRacesUI"]                     = { "AlliedRacesFrame" },
    ["Blizzard_ArchaeologyUI"]                     = { "ArchaeologyFrame" },
    ["Blizzard_ArtifactUI"]                        = { "ArtifactFrame" },
    ["Blizzard_AuctionHouseUI"]                    = { "AuctionHouseFrame" },
    ["Blizzard_BlackMarketUI"]                     = { "BlackMarketFrame" },
    ["Blizzard_Calendar"]                          = { "CalendarFrame", "CalendarViewEventFrame" },
    ["Blizzard_ChallengesUI"]                      = { "ChallengesKeystoneFrame" },
    ["Blizzard_ChromieTimeUI"]                     = { "ChromieTimeFrame" },
    ["Blizzard_ClassTalentUI"]                     = { "ClassTalentFrame" },
    ["Blizzard_Collections"]                       = { "CollectionsJournal", "WardrobeFrame" },
    ["Blizzard_Communities"]                       = { "CommunitiesFrame" },
    ["Blizzard_CooldownViewer"]                    = { "CooldownViewerSettings" },
    ["Blizzard_EncounterJournal"]                  = { "EncounterJournal" },
    ["Blizzard_ExpansionLandingPage"]              = { "ExpansionLandingPage" },
    ["Blizzard_FlightMap"]                         = { "FlightMapFrame" },
    ["Blizzard_GenericTraitUI"]                    = { "GenericTraitFrame" },
    ["Blizzard_GuildBankUI"]                       = { "GuildBankFrame" },
    ["Blizzard_GuildControlUI"]                    = { "GuildControlUI" },
    ["Blizzard_InspectUI"]                         = { "InspectFrame" },
    ["Blizzard_ItemInteractionUI"]                 = { "ItemInteractionFrame" },
    ["Blizzard_ItemSocketingUI"]                   = { "ItemSocketingFrame" },
    ["Blizzard_ItemUpgradeUI"]                     = { "ItemUpgradeFrame" },
    ["Blizzard_MacroUI"]                           = { "MacroFrame" },
    ["Blizzard_MajorFactions"]                     = { "MajorFactionRenownFrame" },
    ["Blizzard_PlayerSpells"]                      = { "PlayerSpellsFrame" },
    ["Blizzard_Professions"]                       = { "ProfessionsFrame" },
    ["Blizzard_ProfessionsBook"]                   = { "ProfessionsBookFrame" },
    ["Blizzard_ProfessionsCustomerOrders"]         = { "ProfessionsCustomerOrdersFrame" },
    ["Blizzard_ScrappingMachineUI"]                = { "ScrappingMachineFrame" },
    ["Blizzard_StableUI"]                          = { "StableFrame" },
    ["Blizzard_TokenUI"]                           = { "CurrencyTransferMenu" },
    ["Blizzard_TrainerUI"]                         = { "ClassTrainerFrame" },
    ["Blizzard_TradeSkillUI"]                      = { "TradeSkillFrame" },
    ["Blizzard_Transmog"]                          = { "TransmogFrame" },
    ["Blizzard_WeeklyRewards"]                     = { "WeeklyRewardsFrame" },
    ["Blizzard_WorldMap"]                          = { "WorldMapFrame" },
    -- Midnight Housing
    ["Blizzard_HousingDashboard"]                  = { "HousingDashboardFrame" },
    ["Blizzard_HousingCornerstone"]                = { "HousingCornerstonePurchaseFrame" },
    ["Blizzard_HousingHouseFinder"]                = { "HouseFinderFrame" },
    ["Blizzard_HousingHouseSettings"]              = { "HousingHouseSettingsFrame" },
    ["Blizzard_HousingBulletinBoard"]              = { "HousingBulletinBoardFrame" },
    ["Blizzard_HousingModelPreview"]               = { "HousingModelPreviewFrame" },
    -- Delves
    ["Blizzard_DelvesCompanionConfigurationFrame"] = { "DelvesCompanionConfigurationFrame", "DelvesCompanionAbilityListFrame" },
    ["Blizzard_DelvesDifficultyPicker"]            = { "DelvesDifficultyPickerFrame" },
}

-- For these frames the drag target is a child header element, not the frame
-- itself (avoids fighting model-rotate or interior click regions).
local DRAG_HEADERS = {
    ["AchievementFrame"] = "AchievementFrameHeader",
    ["WorldMapFrame"]    = "WorldMapTitleButton",
}

-------------------------------------------------------------------------------
--  Position helpers
-------------------------------------------------------------------------------
local function IsEnabled()
    return EllesmereUIDB and EllesmereUIDB.shifterEnabled or false
end

local function GetSavedPos(name)
    local db = EllesmereUIDB
    return db and db.shifterPositions and db.shifterPositions[name]
end

local function SavePos(name, point, relPoint, x, y)
    if not EllesmereUIDB then EllesmereUIDB = {} end
    if not EllesmereUIDB.shifterPositions then
        EllesmereUIDB.shifterPositions = {}
    end
    EllesmereUIDB.shifterPositions[name] = {
        point = point, relPoint = relPoint, x = x, y = y,
    }
    if EllesmereUI.RefreshPage then
        EllesmereUI:RefreshPage(true)
    end
end

local function ApplyPosition(frame, name)
    if InCombatLockdown() and frame:IsProtected() then return end
    local pos = tempPos[frame] or GetSavedPos(name)
    if not pos or not pos.point then return end
    GetFFD(frame)._shIgnoreSP = true
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    GetFFD(frame)._shIgnoreSP = false
end

-------------------------------------------------------------------------------
--  Hook a single frame
-------------------------------------------------------------------------------
local function HookFrame(frame, name)
    local ffd = GetFFD(frame)
    if ffd._shHooked then return end
    ffd._shHooked = true

    frame:SetMovable(true)
    frame:SetClampedToScreen(true)

    -- Determine drag target (header child or the frame itself)
    local headerName = DRAG_HEADERS[name]
    local dragTarget = (headerName and _G[headerName]) or frame

    local dragging  -- "save" | "temp" | nil

    dragTarget:HookScript("OnMouseDown", function(_, button)
        if not IsEnabled() then return end
        if button ~= "LeftButton" then return end
        if InCombatLockdown() and frame:IsProtected() then return end
        if IsShiftKeyDown() then
            dragging = "save"
        elseif IsControlKeyDown() then
            dragging = "temp"
        else
            return
        end
        frame:StartMoving()
    end)

    dragTarget:HookScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not dragging then return end
        frame:StopMovingOrSizing()
        frame:SetUserPlaced(false)
        local p, _, rp, x, y = frame:GetPoint(1)
        if p then
            if dragging == "save" then
                SavePos(name, p, rp, x, y)
                tempPos[frame] = nil
            else
                tempPos[frame] = {
                    point = p, relPoint = rp, x = x, y = y,
                }
            end
        end
        dragging = nil
    end)

    frame:HookScript("OnShow", function()
        if not IsEnabled() then return end
        ApplyPosition(frame, name)
    end)

    frame:HookScript("OnHide", function()
        tempPos[frame] = nil
    end)

    hooksecurefunc(frame, "SetPoint", function()
        if not IsEnabled() then return end
        if ffd._shIgnoreSP then return end
        if InCombatLockdown() and frame:IsProtected() then return end
        if tempPos[frame] or GetSavedPos(name) then
            ApplyPosition(frame, name)
        end
    end)

    -- If the frame is already visible, apply saved position now
    if frame:IsVisible() then
        ApplyPosition(frame, name)
    end
end

local function TryHook(name)
    local frame = _G[name]
    if frame and frame.HookScript then HookFrame(frame, name) end
end

-------------------------------------------------------------------------------
--  Event-driven initialization
-------------------------------------------------------------------------------
local pendingAddons = {}
local eventFrame = CreateFrame("Frame")

local function InitShifter()
    for i = 1, #PRELOADED do
        TryHook(PRELOADED[i])
    end
    for addon, frames in pairs(ADDON_FRAMES) do
        if C_AddOns.IsAddOnLoaded(addon) then
            for i = 1, #frames do TryHook(frames[i]) end
        else
            pendingAddons[addon] = frames
        end
    end
    if next(pendingAddons) then
        eventFrame:RegisterEvent("ADDON_LOADED")
    end
end

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if IsEnabled() then InitShifter() end
    elseif event == "ADDON_LOADED" then
        local frames = pendingAddons[arg1]
        if frames then
            pendingAddons[arg1] = nil
            for i = 1, #frames do TryHook(frames[i]) end
            if not next(pendingAddons) then
                self:UnregisterEvent("ADDON_LOADED")
            end
        end
    end
end)

-- Exposed for the options toggle (mid-session enable without /reload)
function EllesmereUI._InitShifter()
    InitShifter()
end

-- Exposed for the options reset button
function EllesmereUI._ResetShifterPositions()
    if EllesmereUIDB then
        EllesmereUIDB.shifterPositions = nil
    end
    wipe(tempPos)
end
