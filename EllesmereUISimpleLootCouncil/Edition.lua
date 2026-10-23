if EUI_CLIENT_BLOCKED then return end 


local ADDON_NAME, ns = ...



local heldBack = EllesmereUI.HELD_BACK_ADDONS
if heldBack and heldBack[ADDON_NAME] then
    ns.slcInert = true
    return
end

local STANDALONE = "SimpleLootCouncil"
local FIRST_STAND_DOWN = { 0, 43, 80 }

local function OlderStandaloneRuns()
    local api = C_AddOns
    if not (api and api.GetAddOnEnableState and api.GetAddOnMetadata) then return false end
    if api.DoesAddOnExist then
        local ok, exists = pcall(api.DoesAddOnExist, STANDALONE)
        if ok and not exists then return false end
    end
    local character = UnitName("player")
    local ok, state = pcall(api.GetAddOnEnableState, STANDALONE, character)
    if not ok or type(state) ~= "number" or state <= 0 then return false end
    if api.IsAddOnLoadable then
        local called, loadable = pcall(api.IsAddOnLoadable, STANDALONE, character)
        if called and loadable == false then return false end
    end
    local read, version = pcall(api.GetAddOnMetadata, STANDALONE, "Version")
    if not read or type(version) ~= "string" then return false end
    local major, minor, patch = version:match("(%d+)%.(%d+)%.(%d+)")
    if not major then return false end
    local parts = { tonumber(major), tonumber(minor), tonumber(patch) }
    for i = 1, 3 do
        if parts[i] ~= FIRST_STAND_DOWN[i] then return parts[i] < FIRST_STAND_DOWN[i] end
    end
    return false
end

if OlderStandaloneRuns() then
    ns.slcInert = true

    function ns.DisableStandalone()
        if C_AddOns and C_AddOns.DisableAddOn then
            pcall(C_AddOns.DisableAddOn, STANDALONE, UnitName("player"))
        end
    end

    EllesmereUI._ModuleNS[ADDON_NAME] = ns

    local notice = CreateFrame("Frame")
    notice:RegisterEvent("PLAYER_LOGIN")
    notice:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        EllesmereUI:ShowConfirmPopup({
            title = EllesmereUI.L("Simple Loot Council"),
            message = EllesmereUI.L("An older SimpleLootCouncil addon is enabled, so the Simple Loot Council module is off until that addon is disabled or updated."),
            confirmText = EllesmereUI.L("Disable and Reload"),
            cancelText = EllesmereUI.L("Not Now"),
            reload = true,
            onConfirm = ns.DisableStandalone,
        })
    end)
    return
end

SimpleLootCouncil = SimpleLootCouncil or {}
SimpleLootCouncil.EDITION = "eui"
SimpleLootCouncil.SAVED_VARIABLES = "EllesmereUISimpleLootCouncilDB"

SimpleLootCouncil.RequestReload = function() EllesmereUI.RequestReload() end

local function ChatSink(line) EllesmereUI.Print(line) end
SimpleLootCouncil.ChatSinkOverride = { Print = ChatSink, Error = ChatSink }

EllesmereUI._ModuleNS[ADDON_NAME] = ns
