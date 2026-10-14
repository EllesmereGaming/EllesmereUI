if EUI_CLIENT_BLOCKED then return end 



local ADDON_NAME, ns = ...

local STANDALONE = "SimpleLootCouncil"


if EUI_CLIENT_BLOCKED then
    ns.slcInert = true
    return
end



local function CharacterKey()
    local forever = (select(4, GetBuildInfo()) or 0) < 20000
    local full = forever and GetUnitName and GetUnitName("player", false)
    return full or UnitName("player")
end



local function StandaloneRuns()
    local api = C_AddOns
    if not (api and api.GetAddOnEnableState) then return false end
    local character = CharacterKey()
    local ok, state = pcall(api.GetAddOnEnableState, STANDALONE, character)
    if not ok or (state or 0) == 0 then return false end
    if api.IsAddOnLoadable then
        local called, loadable = pcall(api.IsAddOnLoadable, STANDALONE, character)
        if called and loadable == false then return false end
    end
    return true
end

if StandaloneRuns() then
    ns.slcInert = true
else

    SimpleLootCouncil = SimpleLootCouncil or {}
    SimpleLootCouncil.EDITION = "eui"
end



if EllesmereUI and EllesmereUI._ModuleNS then
    EllesmereUI._ModuleNS[ADDON_NAME] = ns
end

if not ns.slcInert then

    local done = CreateFrame("Frame")
    done:RegisterEvent("PLAYER_LOGIN")
    done:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        local db = _G.SimpleLootCouncilDB
        if type(db) == "table" then db.euiSwitchPending = nil end
    end)
    return
end







local function Declined()
    local db = _G.SimpleLootCouncilDB
    return type(db) == "table" and db.euiSwitchDeclined == true
end

local function Remember(declined)
    local db = _G.SimpleLootCouncilDB
    if type(db) == "table" then db.euiSwitchDeclined = declined or nil end
end

local function Disable()
    pcall(C_AddOns.DisableAddOn, STANDALONE, CharacterKey())
    local db = _G.SimpleLootCouncilDB
    if type(db) == "table" then db.euiSwitchPending = true end
end



function ns.AskSwitch()
    if not (EllesmereUI and EllesmereUI.ShowConfirmPopup) then return end
    Remember(false)
    EllesmereUI:ShowConfirmPopup({
        title = EllesmereUI.L("Simple Loot Council"),
        message = EllesmereUI.L("Simple Loot Council is installed twice, and the standalone copy is the one running. Switch to the EllesmereUI module? Your council, history and settings carry over."),
        disclaimer = EllesmereUI.L("Keeping the standalone leaves this copy idle. You can switch later from the Simple Loot Council page."),
        confirmText = EllesmereUI.L("Switch & Reload"),
        cancelText = EllesmereUI.L("Keep Standalone"),
        reload = true,
        onConfirm = Disable,
        onCancel = function() Remember(true) end,
    })
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local db = _G.SimpleLootCouncilDB
    if C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(STANDALONE) == false then

        if type(db) == "table" then db.euiSwitchPending = nil end
        print(EllesmereUI.L("Simple Loot Council did not start: the EllesmereUI module expected the standalone copy to load, and it did not. Please report this; turning SimpleLootCouncil on in the AddOns list works around it."))
        return
    end
    if type(db) == "table" and db.euiSwitchPending then

        db.euiSwitchPending = nil
        print(EllesmereUI.L("Simple Loot Council: the standalone copy could not be turned off for you. Turn off SimpleLootCouncil in the AddOns list, then reload."))
        return
    end
    if Declined() then return end

    C_Timer.After(3, ns.AskSwitch)
end)
