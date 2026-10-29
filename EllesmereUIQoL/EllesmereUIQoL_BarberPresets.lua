if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
if EllesmereUI and EllesmereUI.IS_FOREVER then return end -- the options row is not built on WoW Forever and the reader nil-guards _applyBarberPresets
-------------------------------------------------------------------------------
--  EllesmereUIQoL_BarberPresets.lua
--  Save and re-apply named appearance presets at the barber shop. A small
--  panel is parented to BarberShopFrame (the barber hides UIParent), so it
--  shows and hides with the barber and needs no events of its own.
--
--  Presets are account-wide, keyed by race, body type and the model being
--  edited (character, altered form or a customizable mount), so a preset only
--  lists where its options exist. Applying a preset only previews choices;
--  nothing is bought until the player presses Blizzard's Accept.
-------------------------------------------------------------------------------
local EUI = EllesmereUI
local PP  = EUI and EUI.PP

local MAX_PRESETS = 12
local PANEL_W     = 220
local PAD         = 10
local TITLE_H     = 27
local ROW_H       = 22
local ROW_GAP     = 4
local INPUT_H     = 24
local SAVE_W      = 50

local function Enabled()
    return EllesmereUIDB and EllesmereUIDB.barberPresetsEnabled == true
end

local function Store()
    EllesmereUIDB.barberPresets = EllesmereUIDB.barberPresets or {}
    return EllesmereUIDB.barberPresets
end

local panel, nameBox, saveBtn, emptyFS
local rows = {}
local pendingDelete

-------------------------------------------------------------------------------
--  Barber data
-------------------------------------------------------------------------------
local function CurrentKey()
    local data = C_BarberShop.GetCurrentCharacterData()
    if not data or not data.fileName then return end
    local key = data.fileName .. ":" .. tostring(data.sex)
    local model = C_BarberShop.GetViewingChrModel()
    if model then return key .. ":m" .. model end
    if C_BarberShop.IsViewingAlteredForm() then key = key .. ":alt" end
    return key
end

-- optionID -> { current = choiceID, valid = { [choiceID] = true } }
local function ReadOptions()
    local cats = C_BarberShop.GetAvailableCustomizations()
    if not cats then return end
    local out = {}
    for _, cat in ipairs(cats) do
        for _, opt in ipairs(cat.options or {}) do
            local entry = { valid = {} }
            for i, choice in ipairs(opt.choices or {}) do
                if not choice.isLocked and not choice.ineligibleChoice then
                    entry.valid[choice.id] = true
                end
                if i == opt.currentChoiceIndex then entry.current = choice.id end
            end
            out[opt.id] = entry
        end
    end
    return out
end

local function KeyPresets(create)
    local key = CurrentKey()
    if not key then return end
    local store = Store()
    if create and not store[key] then store[key] = {} end
    return store[key]
end

local function SavePreset(name)
    local list = KeyPresets(true)
    local opts = list and ReadOptions()
    if not opts then return end
    local choices = {}
    for optionID, entry in pairs(opts) do
        if entry.current then choices[#choices + 1] = { o = optionID, c = entry.current } end
    end
    for _, p in ipairs(list) do
        if p.name == name then p.choices = choices; return end
    end
    if #list >= MAX_PRESETS then return end
    list[#list + 1] = { name = name, choices = choices }
end

-- A choice can force a dependent option to change (style -> colour), so the
-- set runs twice: the second pass restores anything the first knocked off.
local function ApplyPreset(preset)
    for _ = 1, 2 do
        local opts = ReadOptions()
        if not opts then return end
        for _, sel in ipairs(preset.choices) do
            local entry = opts[sel.o]
            if entry and entry.current ~= sel.c and entry.valid[sel.c] then
                C_BarberShop.SetCustomizationChoice(sel.o, sel.c)
            end
        end
    end
    -- Same refresh Blizzard runs after its own choice change; the barber has
    -- no protected frames or actions.
    if BarberShopFrame and BarberShopFrame.UpdateCharCustomizationFrame then
        BarberShopFrame:UpdateCharCustomizationFrame()
    end
end

-------------------------------------------------------------------------------
--  Panel
-------------------------------------------------------------------------------
local function ResolveFont()
    return (EUI.GetFontPath("extras")) or "Fonts\\FRIZQT__.TTF"
end

local function MakeLabel(parent, size, r, g, b, a)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local flags = (EUI.GetFontOutlineFlag("extras")) or ""
    EUI.PrimeFontShadow(fs, flags == "")
    fs:SetFont(ResolveFont(), size, flags)
    fs:SetTextColor(r, g, b, a or 1)
    return fs
end

local function MakeButton(parent, w, h)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.044, 0.034, 0.026, 0.9)
    if PP and PP.CreateBorder then PP.CreateBorder(btn, 0, 0, 0, 1, 1, "OVERLAY", 7) end
    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.12)
    btn._label = MakeLabel(btn, 11, 1, 1, 1, 0.9)
    btn._label:SetPoint("LEFT", 8, 0)
    btn._label:SetPoint("RIGHT", -8, 0)
    btn._label:SetWordWrap(false)
    return btn
end

local Refresh

local function GetRow(i)
    if rows[i] then return rows[i] end
    local row = MakeButton(panel, PANEL_W - PAD * 2 - ROW_H - ROW_GAP, ROW_H)
    row._label:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self)
        pendingDelete = nil
        ApplyPreset(self._preset)
        Refresh()
    end)

    -- Delete takes two clicks: the first arms it and turns it red.
    local del = MakeButton(panel, ROW_H, ROW_H)
    del:SetPoint("LEFT", row, "RIGHT", ROW_GAP, 0)
    del._label:ClearAllPoints()
    del._label:SetPoint("CENTER")
    del._label:SetText("x")
    del:SetScript("OnClick", function()
        local preset = row._preset
        if pendingDelete ~= preset then
            pendingDelete = preset
        else
            pendingDelete = nil
            local list = KeyPresets()
            for j = #(list or {}), 1, -1 do
                if list[j] == preset then table.remove(list, j) end
            end
        end
        Refresh()
    end)
    row._del = del
    rows[i] = row
    return row
end

local function TrySave()
    local name = strtrim(nameBox:GetText() or "")
    if name == "" then nameBox:SetFocus(); return end
    SavePreset(name)
    nameBox:SetText("")
    nameBox:ClearFocus()
    Refresh()
end

Refresh = function()
    if not panel then return end
    local list = KeyPresets() or {}
    local y = TITLE_H + PAD + INPUT_H + PAD
    for i, preset in ipairs(list) do
        local row = GetRow(i)
        row._preset = preset
        row._label:SetText(preset.name)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y)
        row:Show()
        row._del:Show()
        local armed = pendingDelete == preset
        row._del._label:SetTextColor(1, armed and 0.3 or 1, armed and 0.3 or 1, armed and 1 or 0.6)
        y = y + ROW_H + ROW_GAP
    end
    for i = #list + 1, #rows do
        rows[i]:Hide()
        rows[i]._del:Hide()
    end
    emptyFS:SetShown(#list == 0)
    if #list == 0 then y = y + ROW_H end
    local full = #list >= MAX_PRESETS
    saveBtn:SetEnabled(not full)
    saveBtn._label:SetAlpha(full and 0.4 or 1)
    panel:SetHeight(y + PAD - ROW_GAP)
end

local function SavePosition()
    local p, _, rp, x, yo = panel:GetPoint()
    if p then Store().pos = { p = p, rp = rp, x = x, y = yo } end
end

local function BuildPanel()
    if panel or not BarberShopFrame then return end

    panel = CreateFrame("Frame", "EUIBarberPresets", BarberShopFrame)
    panel:SetWidth(PANEL_W)
    panel:SetFrameLevel(BarberShopFrame:GetFrameLevel() + 50)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); SavePosition() end)

    local pos = Store().pos
    if pos and pos.p then
        panel:SetPoint(pos.p, BarberShopFrame, pos.rp or pos.p, pos.x or 0, pos.y or 0)
    else
        panel:SetPoint("TOPLEFT", BarberShopFrame, "TOPLEFT", 40, -90)
    end

    local bg = panel:CreateTexture(nil, "BACKGROUND", nil, 0)
    bg:SetAllPoints()
    bg:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    bg:SetTexCoord(0.25, 1, 0, 0.75)
    local overlay = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    overlay:SetAllPoints()
    overlay:SetColorTexture(0, 0, 0, 0.55)
    if PP and PP.CreateBorder then PP.CreateBorder(panel, 0.1, 0.1, 0.1, 1, 1, "OVERLAY", 7) end

    local hdrBg = panel:CreateTexture(nil, "BORDER")
    hdrBg:SetColorTexture(0, 0, 0, 0.25)
    hdrBg:SetPoint("TOPLEFT", 1, -1); hdrBg:SetPoint("TOPRIGHT", -1, 0); hdrBg:SetHeight(TITLE_H)
    local title = MakeLabel(panel, 11, 1, 1, 1, 1)
    title:SetPoint("TOPLEFT", PAD, -8)
    title:SetText(EllesmereUI.L("Appearance Presets"))

    local input = CreateFrame("Frame", nil, panel)
    input:SetPoint("TOPLEFT", PAD, -(TITLE_H + PAD))
    input:SetSize(PANEL_W - PAD * 2 - SAVE_W - ROW_GAP, INPUT_H)
    local iBg = input:CreateTexture(nil, "BACKGROUND")
    iBg:SetAllPoints()
    iBg:SetColorTexture(0, 0, 0, 0.5)
    if PP and PP.CreateBorder then PP.CreateBorder(input, 1, 1, 1, 0.2, 1, "OVERLAY", 7) end

    nameBox = CreateFrame("EditBox", nil, input)
    nameBox:SetPoint("TOPLEFT", 8, -1)
    nameBox:SetPoint("BOTTOMRIGHT", -8, 1)
    nameBox:SetFont(ResolveFont(), 11, "")
    nameBox:SetTextColor(1, 1, 1, 0.9)
    nameBox:SetAutoFocus(false)
    nameBox:SetMaxLetters(30)
    local placeholder = MakeLabel(nameBox, 11, 1, 1, 1, 0.35)
    placeholder:SetPoint("LEFT")
    placeholder:SetText(EllesmereUI.L("Preset name"))
    nameBox:SetScript("OnTextChanged", function(s) placeholder:SetShown(s:GetText() == "") end)
    nameBox:SetScript("OnEnterPressed", TrySave)
    nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)

    saveBtn = MakeButton(panel, SAVE_W, INPUT_H)
    saveBtn:SetPoint("LEFT", input, "RIGHT", ROW_GAP, 0)
    saveBtn._label:SetJustifyH("CENTER")
    saveBtn._label:SetText(EllesmereUI.L("Save"))
    saveBtn:SetScript("OnClick", TrySave)

    emptyFS = MakeLabel(panel, 10, 0.6, 0.6, 0.6, 1)
    emptyFS:SetPoint("TOPLEFT", PAD, -(TITLE_H + PAD + INPUT_H + PAD + 5))
    emptyFS:SetText(EllesmereUI.L("No presets for this look yet."))

    panel:SetScript("OnShow", function() pendingDelete = nil; Refresh() end)
    Refresh()
end

-------------------------------------------------------------------------------
--  Enable / disable
-------------------------------------------------------------------------------
-- Switching body type, altered form or mount changes the preset list.
local function HookBarber()
    if not BarberShopFrame then return end
    local function Changed() if panel and panel:IsShown() then pendingDelete = nil; Refresh() end end
    hooksecurefunc(BarberShopFrame, "UpdateSex", Changed)
    hooksecurefunc(BarberShopFrame, "SetViewingAlteredForm", Changed)
    hooksecurefunc(BarberShopFrame, "SetViewingChrModel", Changed)
end

local hooked = false
local function Spawn()
    if not Enabled() then return end
    if not hooked then hooked = true; HookBarber() end
    BuildPanel()
    if panel then panel:Show() end
end

EUI._applyBarberPresets = function()
    if Enabled() then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_BarbershopUI", Spawn)
    elseif panel then
        panel:Hide()
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    EUI._applyBarberPresets()
end)
