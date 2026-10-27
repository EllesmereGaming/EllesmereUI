if EUI_CLIENT_BLOCKED then return end if (select(2, ...)).slcInert then return end


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local T = addon.Locale.Text

local UI = addon.UI or {}
addon.UI = UI

local Options = {}
UI.Options = Options

local MODULE = "EllesmereUISimpleLootCouncil"


local function PageShown()
    return EllesmereUI:IsShown() and EllesmereUI:GetActiveModule() == MODULE
end



function Options:Toggle()
    if PageShown() then
        EllesmereUI:Hide()
        return
    end
    if InCombatLockdown() then
        addon.Chat.Print(T["the settings cannot open during combat."])
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
    EllesmereUI:RegisterOnShow(function() addon.Callbacks:PaintNow("options") end)

    addon.Log:I("UI", "options ready (EllesmereUI page)")
end
