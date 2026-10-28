if EUI_CLIENT_BLOCKED then return end if (select(2, ...)).slcInert then return end



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil
local slcLocale = addon.Locale
local EUI = EllesmereUI


local rejectedKeys = {}
local function Checked(key, plural)
    local text = EUI.L(key)
    if type(key) ~= "string" or type(text) ~= "string" or text == key then return key, false end
    local ok, reason = slcLocale.ValidTranslation(key, text, plural)
    if ok then return text, true end
    if not rejectedKeys[key] then
        rejectedKeys[key] = true
        slcLocale.rejected[#slcLocale.rejected + 1] = {
            key = key, reason = tostring(reason) .. " for " .. key,
        }
    end
    return key, true
end

local marked = slcLocale.Text
local checkedText = {}
slcLocale.Text = setmetatable({}, {
    __index = function(_, key)
        local wrapped = marked[key]
        if slcLocale.IsPseudo() then return wrapped end
        local text = checkedText[key]
        if text then return text end
        local settled
        text, settled = Checked(key, false)
        if settled then checkedText[key] = text end
        return text
    end,
})



local pseudoPlural = slcLocale.Plural
local checkedPlurals = {}
function slcLocale.Plural(forms)
    if slcLocale.IsPseudo() then return pseudoPlural(forms) end
    if type(forms) ~= "table" or type(forms.other) ~= "string" then return forms end
    local cached = checkedPlurals[forms.other]
    if cached and cached.one == forms.one and cached.few == forms.few and cached.many == forms.many then
        return cached.translated
    end
    local translated
    for name, form in pairs(forms) do
        if type(form) == "string" then
            local text = Checked(form, true)
            if text ~= form then
                if not translated then
                    translated = {}
                    for k, v in pairs(forms) do translated[k] = v end
                end
                translated[name] = text
            end
        end
    end
    if not translated then return forms end
    checkedPlurals[forms.other] = { one = forms.one, few = forms.few, many = forms.many,
        translated = translated }
    return translated
end
