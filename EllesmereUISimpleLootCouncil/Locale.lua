if EUI_CLIENT_BLOCKED then return end 


SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local slcLocale = addon.Locale
local EUI = EllesmereUI


local marked = slcLocale.Text
slcLocale.Text = setmetatable({}, {
    __index = function(_, key)
        local wrapped = marked[key]
        if slcLocale.IsPseudo() then return wrapped end
        return EUI.L(key)
    end,
})



local pseudoPlural = slcLocale.Plural
function slcLocale.Plural(forms)
    if slcLocale.IsPseudo() then return pseudoPlural(forms) end
    if type(forms) ~= "table" or type(forms.other) ~= "string" then return forms end
    local translated, changed = {}, false
    for name, form in pairs(forms) do
        local text = type(form) == "string" and EUI.L(form) or form
        if text ~= form then changed = true end
        translated[name] = text
    end
    return changed and translated or forms
end
