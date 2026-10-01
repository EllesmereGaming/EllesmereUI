-- Independent install adapter. The generated package uses the canonical runtime.
if EUI_CLIENT_BLOCKED then return end
if EllesmereUI.IS_FOREVER then return end

local _, addonRuntime = ...
addonRuntime.keystoneCompanion = true
local initialized, optionsFrame

local function HasIntegratedControls()
    return type(EllesmereUI._applyKeystoneStart) == "function"
end

function addonRuntime.GetOptions()
    if not initialized or HasIntegratedControls() then return end
    return EllesmereUIMythicStartDB
end

local function InitializeOptions()
    if type(EllesmereUIMythicStartDB) ~= "table" then EllesmereUIMythicStartDB = {} end
    local db = EllesmereUIMythicStartDB
    -- Installing this companion opts into manual controls. Automation stays off.
    if db.mythicKeystoneControls == nil then db.mythicKeystoneControls = true end
    for _, key in ipairs({ "autoKeystoneReadyCheck", "autoStartKeystone" }) do
        if db[key] == nil then
            db[key] = type(EllesmereUIDB) == "table" and EllesmereUIDB[key] == true or false
        end
    end
    initialized = true
end

local function ApplyOptions()
    if addonRuntime.Apply then addonRuntime.Apply() end
end

local function CreateOptionsFrame()
    local panel = CreateFrame("Frame", "EllesmereUIMythicStartOptionsFrame", UIParent,
        "BasicFrameTemplateWithInset")
    panel:SetSize(440, 235)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel.TitleText:SetText("EllesmereUI Ready/Pull")
    table.insert(UISpecialFrames, "EllesmereUIMythicStartOptionsFrame")

    local definitions = {
        { "mythicKeystoneControls", "Enable READY and PULL controls" },
        { "autoKeystoneReadyCheck", "Automatically request a ready check" },
        { "autoStartKeystone", "Activate the key when the manual pull ends" },
    }
    local checks = {}
    for i, definition in ipairs(definitions) do
        local key = definition[1]
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetPoint("TOPLEFT", 18, -35 - (i - 1) * 34)
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("LEFT", check, "RIGHT", 2, 0)
        label:SetText(definition[2])
        check:SetScript("OnClick", function(self)
            EllesmereUIMythicStartDB[key] = self:GetChecked() == true
            ApplyOptions()
        end)
        checks[i] = { button = check, key = key }
    end
    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 24, -148)
    help:SetWidth(390)
    help:SetJustifyH("LEFT")
    help:SetText("PULL: left-click = 5 seconds; right-click = 10 seconds.\nClick PULL again with either button to cancel.\nREADY never starts a pull automatically.\nThe countdown and cancellation are shared in group chat.")
    panel:SetScript("OnShow", function()
        for _, check in ipairs(checks) do
            check.button:SetChecked(EllesmereUIMythicStartDB[check.key] == true)
        end
    end)
    panel:Hide()
    return panel
end

SLASH_ELLESMEREUIMYTHICSTART1 = "/euipull"
SlashCmdList.ELLESMEREUIMYTHICSTART = function()
    if not initialized then return end
    if HasIntegratedControls() then
        print("EllesmereUI already provides READY/PULL. Use its Ready/Pull Controls settings.")
        return
    end
    if not optionsFrame then optionsFrame = CreateOptionsFrame() end
    optionsFrame:SetShown(not optionsFrame:IsShown())
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        InitializeOptions()
        ApplyOptions()
    elseif not initialized then
        return
    end
    -- The integrated implementation takes precedence, including a later load.
    if HasIntegratedControls() then
        ApplyOptions()
        if optionsFrame then optionsFrame:Hide() end
        self:UnregisterAllEvents()
    end
end)
