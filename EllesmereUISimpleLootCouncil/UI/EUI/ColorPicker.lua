if EUI_CLIENT_BLOCKED then return end if select(2, ...).slcInert then return end 


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local UI = addon.UI or {}
addon.UI = UI

local ColorPicker = {}
UI.ColorPicker = ColorPicker

local EUI = EllesmereUI


local function Popup()
    return type(EUI.ShowColorPicker) == "function" and EUI._colorPickerPopup or nil
end



function ColorPicker:Open(options)
    if type(EUI.ShowColorPicker) ~= "function" then
        addon.Log:W("UI", "the EllesmereUI color picker is not loaded yet")
        return
    end


    local cancelled = false
    EUI:ShowColorPicker({
        r = options.r or 1, g = options.g or 1, b = options.b or 1,
        swatchFunc = function()
            local popup = Popup()
            if popup and options.onChange then options.onChange(popup:GetColorRGB()) end
        end,
        cancelFunc = function()
            if cancelled then return end
            cancelled = true
            if options.onCancel then options.onCancel() end
        end,
    }, options.anchor)
end

function ColorPicker:IsShown()
    local popup = Popup()
    return popup ~= nil and popup:IsShown()
end
