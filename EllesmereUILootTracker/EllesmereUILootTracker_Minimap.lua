local _, ns = ...
if not (EllesmereUI and ns) then return end

local BUTTON_NAME = "EllesmereUILootTrackerMinimapButton"
local ICON = "Interface\\Icons\\INV_Misc_TreasureChest04b"
local refreshQueued

local function SuiteVersion()
    local getter = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = getter and getter("EllesmereUI", "Version")
    return tostring(version or "unknown")
end

local function CreateMinimapButton()
    local existing = _G[BUTTON_NAME]
    if existing then return existing end
    if not Minimap then return end

    local button = CreateFrame("Button", BUTTON_NAME, Minimap)
    button:SetSize(32, 32)
    button:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", 2, 2)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:SetClampedToScreen(true)
    button:RegisterForClicks("LeftButtonUp")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
    icon:SetTexture(ICON)
    icon:SetTexCoord(6 / 64, 58 / 64, 6 / 64, 58 / 64)
    icon:SetVertexColor(0.85, 0.85, 0.85, 1)
    button.icon = icon

    button:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(EllesmereUI.L("Loot Tracker"), 0.05, 0.82, 0.62)
        GameTooltip:AddLine(EllesmereUI.L("Left-click to open the Loot Tracker"), 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.85, 0.85, 0.85, 1)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end)
    button:SetScript("OnMouseDown", function(self)
        self.icon:SetVertexColor(0.65, 0.65, 0.65, 1)
    end)
    button:SetScript("OnMouseUp", function(self)
        local value = self:IsMouseOver() and 1 or 0.85
        self.icon:SetVertexColor(value, value, value, 1)
    end)
    button:SetScript("OnClick", function()
        if GameTooltip:GetOwner() == button then GameTooltip:Hide() end
        if ns.Open then ns.Open("Overview") end
    end)
    return button
end

local function DefaultToDirectButton()
    local trackerProfile = ns.GetProfile and ns.GetProfile()
    local minimapDB = _G._EMM_DB
    local minimapProfile = minimapDB and minimapDB.profile and minimapDB.profile.minimap
    if not trackerProfile or not minimapProfile then return end

    minimapProfile.ungroupedButtons = minimapProfile.ungroupedButtons or {}
    local suiteVersion = SuiteVersion()
    local needsVersionRepair = trackerProfile.minimapIntegrationVersion ~= suiteVersion
    if minimapProfile.ungroupedButtons[BUTTON_NAME] == nil
        and (not trackerProfile.minimapButtonSetup or needsVersionRepair) then
        local maxOrder = 0
        for _, order in pairs(minimapProfile.ungroupedButtons) do
            if type(order) == "number" and order > maxOrder then maxOrder = order end
        end
        minimapProfile.ungroupedButtons[BUTTON_NAME] = maxOrder + 1
    end
    trackerProfile.minimapButtonSetup = true
    trackerProfile.minimapIntegrationVersion = suiteVersion
end

local function RefreshMinimapIntegration()
    CreateMinimapButton()
    DefaultToDirectButton()
    if _G._EMM_FullRebuildMinimap then _G._EMM_FullRebuildMinimap() end
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = nil
        RefreshMinimapIntegration()
    end)
end

CreateMinimapButton()
QueueRefresh()

local events = CreateFrame("Frame")
if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUIMinimap")) then
    events:RegisterEvent("ADDON_LOADED")
end
if not (IsLoggedIn and IsLoggedIn()) then events:RegisterEvent("PLAYER_LOGIN") end
events:SetScript("OnEvent", function(self, event, addonName)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        QueueRefresh()
    elseif event == "ADDON_LOADED" and addonName == "EllesmereUIMinimap" then
        self:UnregisterEvent("ADDON_LOADED")
        QueueRefresh()
    end
end)
