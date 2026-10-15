if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local Options = {}
UI.Options = Options

local MODULE = "EllesmereUISimpleLootCouncil"


local function PageShown()
    return EllesmereUI ~= nil and EllesmereUI.IsShown ~= nil
        and EllesmereUI:IsShown() and EllesmereUI:GetActiveModule() == MODULE
end



function Options:Toggle()
    if not (EllesmereUI and EllesmereUI.ShowModule) then return end
    if PageShown() then
        EllesmereUI:Hide()
        return
    end
    if InCombatLockdown() then
        print(addon.Log.CHAT_PREFIX.accent .. T["the settings cannot open during combat."])
        return
    end
    EllesmereUI:ShowModule(MODULE)
end


function Options:Refresh()
    addon.Callbacks:Invalidate("options")
end

function Options:Init()

    Options.view = addon.Callbacks:RegisterView("options", {
        shown = PageShown,
        paint = function()
            EllesmereUI:RefreshPage()
        end,
    })

    local function Live() addon.Callbacks:Invalidate("options") end
    addon.Callbacks:Register("SessionChanged", function(_, kind)
        if kind == nil or kind == "run" then Live() end
    end)
    for _, event in ipairs({
        "HandlingChanged", "SharedConfigChanged", "RunStarted", "RunEnded", "RunRecovered",
        "LootMasterChanged", "CouncilChanged", "RaidTeamChanged", "MainsChanged",
    }) do
        addon.Callbacks:Register(event, Live)
    end

    addon.Log:I("UI", "options ready (EllesmereUI page)")
end
