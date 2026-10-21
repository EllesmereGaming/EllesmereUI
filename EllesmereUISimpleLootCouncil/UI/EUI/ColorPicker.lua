if EUI_CLIENT_BLOCKED then return end 



SimpleLootCouncil = SimpleLootCouncil or {}
local addon = SimpleLootCouncil

local UI = addon.UI or {}
addon.UI = UI

local ColorPicker = {}
UI.ColorPicker = ColorPicker

local EUI = EllesmereUI



local SWATCH = 19
local SWATCH_GAP = 4
local ROW_GAP = 8
local LABEL_GAP = 3


local presets

local baseHeight

local opening = false
local hooked = false
local ShowPresets

local MODULE = "EllesmereUISimpleLootCouncil"


local function Popup()
    return type(EUI.ShowColorPicker) == "function" and EUI._colorPickerPopup or nil
end

local function ClassPresets()
    local list = {}
    local count = GetNumClasses and GetNumClasses() or 0
    for classID = 1, count do
        local info = C_CreatureInfo.GetClassInfo(classID)
        local colour = info and C_ClassColor.GetClassColor(info.classFile)
        if colour then
            local r, g, b = colour:GetRGB()
            list[#list + 1] = { name = info.className, r = r, g = g, b = b }
        end
    end
    return list
end

local function QualityPresets()
    local T = addon.Locale.Text
    local names = {
        [0] = T["Poor"], [1] = T["Common"], [2] = T["Uncommon"], [3] = T["Rare"],
        [4] = T["Epic"], [5] = T["Legendary"], [6] = T["Artifact"], [7] = T["Heirloom"],
    }
    local list = {}
    for quality = 0, 7 do
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then
            list[#list + 1] = { name = names[quality], r = r, g = g, b = b }
        end
    end
    return list
end

local function Hex(r, g, b)
    local function byte(v) return math.floor(math.max(0, math.min(1, v)) * 255 + 0.5) end
    return string.format("%02X%02X%02X", byte(r), byte(g), byte(b))
end


local function RecentRow(popup)
    for _, child in ipairs({ popup:GetChildren() }) do
        if child._label and child._isFavorites == false then return child end
    end
end


local function HexBox(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == "EditBox" and child:GetMaxLetters() == 6 then
            return child
        end
        local found = HexBox(child)
        if found then return found end
    end
end


local function Label(host, like, text)
    local label = host:CreateFontString(nil, "OVERLAY")
    label:SetFont(like:GetFont())
    label:SetTextColor(like:GetTextColor())
    label:SetShadowColor(like:GetShadowColor())
    label:SetShadowOffset(like:GetShadowOffset())
    label:SetAlpha(like:GetAlpha())
    label:SetText(text)
    return label
end



local function Swatch(host, hexBox, preset)
    local btn = CreateFrame("Button", nil, host)
    btn:SetSize(SWATCH, SWATCH)
    btn:SetFrameLevel(host:GetFrameLevel() + 2)
    local fill = btn:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    fill:SetColorTexture(preset.r, preset.g, preset.b, 1)
    local hex = Hex(preset.r, preset.g, preset.b)
    btn:SetScript("OnEnter", function(self)
        EUI.ShowWidgetTooltip(self, "|cff" .. hex .. preset.name .. "|r\n#" .. hex)
    end)
    btn:SetScript("OnLeave", function() EUI.HideWidgetTooltip() end)
    btn:SetScript("OnClick", function()
        local enter = hexBox:GetScript("OnEnterPressed")
        if not enter then return end
        hexBox:SetText(hex)
        enter(hexBox)
    end)
    return btn
end



local function PresetRow(host, above, like, title, list, width)
    local label = Label(host, like, title)
    label:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -ROW_GAP)
    local perRow = math.max(1, math.floor((width + SWATCH_GAP) / (SWATCH + SWATCH_GAP)))
    local hexBox = host.hexBox
    local last
    for i, preset in ipairs(list) do
        local col, line = (i - 1) % perRow, math.floor((i - 1) / perRow)
        local swatch = Swatch(host, hexBox, preset)
        swatch:SetPoint("TOPLEFT", label, "BOTTOMLEFT", col * (SWATCH + SWATCH_GAP),
            -(LABEL_GAP + line * (SWATCH + SWATCH_GAP)))
        if col == 0 then last = swatch end
    end
    local lines = math.max(1, math.ceil(#list / perRow))
    local labelH = math.max(label:GetStringHeight() or 0, 10)
    return last or label, ROW_GAP + labelH + LABEL_GAP + lines * (SWATCH + SWATCH_GAP) - SWATCH_GAP
end

local function Build(popup)
    local recent = type(popup.GetChildren) == "function" and RecentRow(popup)
    local hexBox = recent and HexBox(popup)
    if not (recent and hexBox and type(EUI.ShowWidgetTooltip) == "function") then
        addon.Log:W("UI", "the EllesmereUI color picker has changed: no preset colors")
        return false
    end
    local T = addon.Locale.Text
    local host = CreateFrame("Frame", nil, popup)
    host:SetAllPoints()
    host:SetFrameLevel(popup:GetFrameLevel() + 1)
    host.hexBox = hexBox
    local width = recent:GetWidth()
    local classLast, classH = PresetRow(host, recent, recent._label, T["Class Colors"],
        ClassPresets(), width)
    local _, qualityH = PresetRow(host, classLast, recent._label, T["Item Rarity Colors"],
        QualityPresets(), width)
    host.extra = classH + qualityH
    host:Hide()

    baseHeight = popup:GetHeight()

    popup:HookScript("OnHide", function() ShowPresets(popup, false) end)
    return host
end




local function KeepAboveCursor(popup, grownBy)
    local top, left = popup:GetTop(), popup:GetLeft()
    if not (top and left) or grownBy == 0 then return end
    local _, cursorY = GetCursorPosition()
    if top - (popup:GetHeight() - grownBy) <= cursorY / popup:GetEffectiveScale() then return end
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top + grownBy)
end

ShowPresets = function(popup, show)
    if presets == nil then
        if not show then return end
        presets = Build(popup)
    end
    if not presets then return end
    local before = popup:GetHeight()
    presets:SetShown(show)
    popup:SetHeight(baseHeight + (show and presets.extra or 0))
    if show then KeepAboveCursor(popup, popup:GetHeight() - before) end
end


local function OnOptionsPage(anchor)
    if not (anchor and type(EUI.GetActiveModule) == "function"
        and EUI:GetActiveModule() == MODULE and EUI:IsShown()) then
        return false
    end
    local main = EUI._mainFrame
    local frame = anchor
    while frame do
        if frame == main then return true end
        frame = frame:GetParent()
    end
    return main == nil
end


local function Hook()
    if hooked or type(EUI.ShowColorPicker) ~= "function" or not hooksecurefunc then return end
    hooked = true
    hooksecurefunc(EUI, "ShowColorPicker", function(_, _, anchor)
        local popup = Popup()
        if popup and type(popup.GetChildren) == "function" then
            ShowPresets(popup, opening or OnOptionsPage(anchor))
        end
    end)
end


Hook()
if not hooked and type(EUI.EnsureLoaded) == "function" and hooksecurefunc then
    hooksecurefunc(EUI, "EnsureLoaded", Hook)
end



function ColorPicker:Open(options)
    if type(EUI.ShowColorPicker) ~= "function" then
        addon.Log:W("UI", "the EllesmereUI color picker is not loaded yet")
        return
    end
    Hook()


    local cancelled = false
    opening = true
    EUI:ShowColorPicker({
        r = options.r or 1, g = options.g or 1, b = options.b or 1,
        swatchFunc = function()
            local shown = Popup()
            if shown and options.onChange then options.onChange(shown:GetColorRGB()) end
        end,
        cancelFunc = function()
            if cancelled then return end
            cancelled = true
            if options.onCancel then options.onCancel() end
        end,
    }, options.anchor)
    opening = false
end

function ColorPicker:IsShown()
    local popup = Popup()
    return popup ~= nil and popup:IsShown()
end
