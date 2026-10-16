if EUI_CLIENT_BLOCKED then return end 



local ADDON_NAME, ns = ...

local STANDALONE = "SimpleLootCouncil"


local OWN_DB, STANDALONE_DB = "EllesmereUISimpleLootCouncilDB", "SimpleLootCouncilDB"

local FLAGS = { euiSwitchDeclined = true, euiSwitchPending = true }


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

local function HasData(db)
    if type(db) ~= "table" then return false end
    for key in pairs(db) do
        if not FLAGS[key] then return true end
    end
    return false
end


local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do copy[DeepCopy(k, seen)] = DeepCopy(v, seen) end
    return copy
end



local function Adopt()
    local own, old = _G[OWN_DB], _G[STANDALONE_DB]
    if HasData(own) or not HasData(old) then return end
    for key in pairs(FLAGS) do old[key] = type(own) == "table" and own[key] or nil end
    _G[OWN_DB] = old
    _G[STANDALONE_DB] = nil
end

if StandaloneRuns() then
    ns.slcInert = true
else

    SimpleLootCouncil = SimpleLootCouncil or {}
    SimpleLootCouncil.EDITION = "eui"
    SimpleLootCouncil.SAVED_VARIABLES = OWN_DB
    SimpleLootCouncil.AdoptSavedVariables = Adopt

    if EllesmereUI and EllesmereUI.RequestReload then
        SimpleLootCouncil.RequestReload = function() EllesmereUI.RequestReload() end
    end
end



if EllesmereUI and EllesmereUI._ModuleNS then
    EllesmereUI._ModuleNS[ADDON_NAME] = ns
end

if not ns.slcInert then

    local done = CreateFrame("Frame")
    done:RegisterEvent("PLAYER_LOGIN")
    done:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        local db = _G[OWN_DB]
        if type(db) == "table" then db.euiSwitchPending = nil end
    end)
    return
end







local function OwnDB()
    local db = _G[OWN_DB]
    if type(db) ~= "table" then
        db = {}
        _G[OWN_DB] = db
    end
    return db
end

local function Declined()
    local db = _G[OWN_DB]
    return type(db) == "table" and db.euiSwitchDeclined == true
end

local function Remember(declined)
    OwnDB().euiSwitchDeclined = declined or nil
end



local function Disable()
    pcall(C_AddOns.DisableAddOn, STANDALONE, CharacterKey())
    local own = OwnDB()
    if not HasData(own) and HasData(_G[STANDALONE_DB]) then
        local copy = DeepCopy(_G[STANDALONE_DB], {})
        for key in pairs(FLAGS) do copy[key] = own[key] end
        _G[OWN_DB] = copy
        own = copy
    end
    own.euiSwitchPending = true
end



function ns.AskSwitch()
    if not (EllesmereUI and EllesmereUI.ShowConfirmPopup) then return end
    Remember(false)
    local message = HasData(_G[OWN_DB])
        and EllesmereUI.L("Simple Loot Council is installed twice, and the standalone copy is the one running. Switch to the EllesmereUI module? It keeps the council, history and settings it already has; the standalone copy's own are left as they are.")
        or EllesmereUI.L("Simple Loot Council is installed twice, and the standalone copy is the one running. Switch to the EllesmereUI module? Your council, history and settings carry over.")
    EllesmereUI:ShowConfirmPopup({
        title = EllesmereUI.L("Simple Loot Council"),
        message = message,
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
    local db = _G[OWN_DB]
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
