if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_Widgets_PageParts.lua
--  Shared page parts: unlock placeholder, max duration and sound dropdown
--  data, the Global Settings rows and module card, and the manager-page
--  parts. Read at load by the Fonts and Textures options files, so it
--  loads before them.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
-- Page reuse: the frames this file builds go through the options frame pool
-- (EllesmereUI_FramePool.lua, loaded first in this addon), which hands a kept
-- page its previous build's frames back reset to new; on any other parent it
-- creates as before.
local CreateFrame = EllesmereUI._Pool.CreateFrame

local ttsTextPopup
local ttsPopupOnHideRegistered
local function CDMTTSProfile()
    local cdm = EllesmereUI._ModuleNS and EllesmereUI._ModuleNS.EllesmereUICooldownManager
    return cdm and cdm.ECME and cdm.ECME.db and cdm.ECME.db.profile, cdm
end

function EllesmereUI.ShowTTSTextPopup(title, initial, defaultText, onSave, onPreview)
    if not ttsTextPopup then
        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetAllPoints(UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetFrameLevel(700)
        dimmer:EnableMouse(true)
        local shade = dimmer:CreateTexture(nil, "BACKGROUND")
        shade:SetAllPoints(); shade:SetColorTexture(0, 0, 0, 0.55)

        local popup = CreateFrame("Frame", nil, dimmer)
        popup:SetSize(300, 232)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 2)
        popup:EnableMouse(true)
        local bg = popup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.077, 0.068, 0.058, 1)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.18, EllesmereUI.PanelPP)

        local font = EllesmereUI._font or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
        local heading = popup:CreateFontString(nil, "OVERLAY")
        heading:SetFont(font, 14, "")
        heading:SetPoint("TOP", popup, "TOP", 0, -16)
        heading:SetTextColor(1, 1, 1, 1)
        popup._heading = heading

        local hint = popup:CreateFontString(nil, "OVERLAY")
        hint:SetFont(font, 10, "")
        hint:SetPoint("TOPLEFT", popup, "TOPLEFT", 20, -43)
        hint:SetText(EllesmereUI.L("Leave empty to use the default announcement"))
        hint:SetTextColor(0.7, 0.7, 0.7, 1)

        local box = CreateFrame("EditBox", nil, popup)
        box:SetSize(260, 30)
        box:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -5)
        box:SetAutoFocus(false)
        box:SetMaxLetters(120)
        box:SetFont(font, 12, "")
        box:SetTextColor(1, 1, 1, 0.95)
        box:SetTextInsets(6, 6, 0, 0)
        box:SetJustifyH("LEFT")
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints(); boxBg:SetColorTexture(0.06, 0.05, 0.04, 1)
        EllesmereUI.MakeBorder(box, 1, 1, 1, 0.14, EllesmereUI.PanelPP)
        popup._box = box

        local voiceBtn = CreateFrame("Button", nil, popup)
        voiceBtn:SetSize(260, 24)
        voiceBtn:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -8)
        local voiceLabel = voiceBtn:CreateFontString(nil, "OVERLAY")
        voiceLabel:SetFont(font, 11, "")
        voiceLabel:SetPoint("LEFT", voiceBtn, "LEFT", 6, 0)
        voiceLabel:SetJustifyH("LEFT")
        voiceLabel:SetWordWrap(false)
        voiceLabel:SetMaxLines(1)
        voiceLabel:SetTextColor(1, 1, 1, 0.9)
        local voiceArrow = EllesmereUI.MakeDropdownArrow(voiceBtn, 12, EllesmereUI.PanelPP)
        voiceArrow:SetPoint("RIGHT", voiceBtn, "RIGHT", -4, 0)
        voiceLabel:SetPoint("RIGHT", voiceArrow, "LEFT", -6, 0)
        local voiceMenu, refreshVoice
        local voiceValues, voiceOrder = EllesmereUI.BuildTTSVoiceDropdownValues(function(voiceID)
            local _, cdm = CDMTTSProfile()
            if cdm and cdm.SpeakTTS then
                cdm.SpeakTTS("This is a voice preview", voiceID, ttsTextPopup._ttsPrefsVolume)
            end
        end)
        voiceValues._menuOpts.parent = popup
        local function CurrentVoice()
            return ttsTextPopup._ttsPrefsVoiceID or 0
        end
        local function RefreshVoice()
            if refreshVoice then refreshVoice() end
            voiceLabel:SetText(EllesmereUI.L("TTS Voice") .. ": " .. (voiceValues[CurrentVoice()] or voiceValues[0]))
        end
        popup._refreshVoice = RefreshVoice
        popup._voiceLabel = voiceLabel
        voiceBtn:SetScript("OnClick", function()
            if not voiceMenu then
                voiceMenu, _, refreshVoice = EllesmereUI.BuildDropdownMenu(voiceBtn, 260,
                    voiceOrder, voiceValues, CurrentVoice, function(value)
                        ttsTextPopup._ttsPrefsVoiceID = value
                        RefreshVoice()
                    end, voiceLabel, "regular")
                voiceMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                voiceMenu:SetFrameLevel(popup:GetFrameLevel() + 10)
            end
            if voiceMenu:IsShown() then voiceMenu:Hide()
            else RefreshVoice(); voiceMenu:Show() end
        end)
        popup._getVoiceMenu = function() return voiceMenu end
        local function CloseTTSPopupStep()
            if voiceMenu and voiceMenu:IsShown() then
                voiceMenu:Hide()
            else
                dimmer:Hide()
            end
        end
        if EllesmereUI.RegisterEscapeClose then
            EllesmereUI.RegisterEscapeClose(dimmer, {
                notOwned = true,
                onEscape = CloseTTSPopupStep,
            })
        end
        if EllesmereUI.RegisterOnHide and not ttsPopupOnHideRegistered then
            EllesmereUI:RegisterOnHide(function()
                if ttsTextPopup then ttsTextPopup._dimmer:Hide() end
            end)
            ttsPopupOnHideRegistered = true
        end

        local volumeLabel = popup:CreateFontString(nil, "OVERLAY")
        volumeLabel:SetFont(font, 11, "")
        volumeLabel:SetPoint("TOPLEFT", voiceBtn, "BOTTOMLEFT", 0, -5)
        volumeLabel:SetTextColor(1, 1, 1, 0.9)
        local volumeSlider = CreateFrame("Slider", nil, popup)
        volumeSlider:SetSize(165, 14)
        volumeSlider:SetPoint("LEFT", volumeLabel, "RIGHT", 8, 0)
        volumeSlider:SetOrientation("HORIZONTAL")
        volumeSlider:SetMinMaxValues(0, 100)
        volumeSlider:SetValueStep(5)
        volumeSlider:SetObeyStepOnDrag(true)
        volumeSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        local track = volumeSlider:CreateTexture(nil, "BACKGROUND")
        track:SetColorTexture(0.1, 0.1, 0.1, 1)
        track:SetPoint("LEFT", volumeSlider, "LEFT", 0, 0)
        track:SetPoint("RIGHT", volumeSlider, "RIGHT", 0, 0)
        track:SetHeight(4)
        popup._initializingVolume = false
        volumeSlider:SetScript("OnValueChanged", function(_, value)
            local rounded = math.floor(value + 0.5)
            if not popup._initializingVolume then popup._ttsPrefsVolume = rounded end
            volumeLabel:SetText(EllesmereUI.L("TTS Volume") .. ": " .. rounded)
        end)
        popup._volumeSlider = volumeSlider
        popup._volumeLabel = volumeLabel

        local function Button(label, x, click, accent)
            local b = CreateFrame("Button", nil, popup)
            b:SetSize(78, 25)
            b:SetPoint("BOTTOM", popup, "BOTTOM", x, 13)
            local ar, ag, ab = EllesmereUI.GetAccentColor()
            local c = accent and { ar, ag, ab } or { 1, 1, 1 }
            local texture = b:CreateTexture(nil, "BACKGROUND")
            texture:SetAllPoints(); texture:SetColorTexture(c[1], c[2], c[3], accent and 0.14 or 0.04)
            EllesmereUI.MakeBorder(b, c[1], c[2], c[3], accent and 0.45 or 0.15, EllesmereUI.PanelPP)
            local labelFS = b:CreateFontString(nil, "OVERLAY")
            labelFS:SetFont(font, 11, "")
            labelFS:SetPoint("CENTER")
            labelFS:SetText(EllesmereUI.L(label))
            labelFS:SetTextColor(c[1], c[2], c[3], 1)
            b:SetScript("OnClick", click)
            return b
        end
        Button("Preview", -88, function()
            local text = box:GetText()
            local voiceID = popup._ttsPrefsVoiceID or 0
            local volume = popup._ttsPrefsVolume or 100
            if popup._onPreview then
                popup._onPreview(text ~= "" and text or popup._defaultText, voiceID, volume)
            else
                local _, cdm = CDMTTSProfile()
                if cdm and cdm.SpeakTTS then
                    cdm.SpeakTTS(text ~= "" and text or popup._defaultText, voiceID, volume)
                else
                    EllesmereUI.SpeakText(text ~= "" and text or popup._defaultText, voiceID, volume)
                end
            end
        end, false)
        Button("Cancel", 0, function() dimmer:Hide() end, false)
        local function CommitTTSPrefs()
            local profile = popup._ttsPrefsProfile
            if profile then
                profile.ttsVoiceID = popup._ttsPrefsVoiceID
                profile.ttsVolume = popup._ttsPrefsVolume
            end
        end
        Button("Save", 88, function()
            CommitTTSPrefs()
            dimmer:Hide()
            if popup._onSave then popup._onSave(box:GetText() or "") end
        end, true)
        box:SetScript("OnEnterPressed", function()
            CommitTTSPrefs()
            dimmer:Hide()
            if popup._onSave then popup._onSave(box:GetText() or "") end
        end)
        box:SetScript("OnEscapePressed", CloseTTSPopupStep)
        dimmer:SetScript("OnMouseDown", function(self)
            local menu = popup._getVoiceMenu and popup._getVoiceMenu()
            if not popup:IsMouseOver() and not (menu and menu:IsMouseOver()) then self:Hide() end
        end)
        dimmer:SetScript("OnHide", function()
            local menu = popup._getVoiceMenu and popup._getVoiceMenu()
            if menu then menu:Hide() end
        end)
        popup._dimmer = dimmer
        ttsTextPopup = popup
    end
    ttsTextPopup._heading:SetText(title or "")
    ttsTextPopup._box:SetText(initial or "")
    ttsTextPopup._defaultText = defaultText or ""
    ttsTextPopup._onSave = onSave
    ttsTextPopup._onPreview = onPreview
    local profile = CDMTTSProfile()
    ttsTextPopup._ttsPrefsProfile = profile
    ttsTextPopup._ttsPrefsVoiceID = profile and profile.ttsVoiceID or nil
    ttsTextPopup._ttsPrefsVolume = profile and profile.ttsVolume or nil
    ttsTextPopup._initializingVolume = true
    if profile then
        ttsTextPopup._volumeSlider:SetValue(profile.ttsVolume or 100)
    end
    ttsTextPopup._initializingVolume = false
    ttsTextPopup._volumeLabel:SetText(EllesmereUI.L("TTS Volume") .. ": " .. ((profile and profile.ttsVolume) or 100))
    ttsTextPopup._refreshVoice()
    ttsTextPopup._dimmer:Show()
    local voiceMenu = ttsTextPopup._getVoiceMenu()
    if voiceMenu and voiceMenu:IsShown() then voiceMenu:Hide() end
    ttsTextPopup._box:SetFocus()
end

-------------------------------------------------------------------------------
--  BuildUnlockPlaceholder
--  Reusable overlay that mirrors the unlock mode mover style. Shows accent-colored text (default "Move in
--  Unlock Mode") and opens unlock mode on click.
--  opts = {
--      parent   = frame,          -- parent frame to overlay
--      text     = "...",          -- optional, defaults to "Move in Unlock Mode"
--      level    = number,         -- optional frame level override
--      onClick  = function,       -- optional custom click handler (default: toggle unlock mode)
--  }
--  Returns the placeholder frame.
-------------------------------------------------------------------------------
function EllesmereUI.BuildUnlockPlaceholder(opts)
    local parent = opts.parent
    local eg = EllesmereUI.ELLESMERE_GREEN
    local ar, ag, ab = eg.r, eg.g, eg.b

    local f = CreateFrame("Button", nil, parent)
    f:SetAllPoints(parent)
    if opts.level then
        f:SetFrameLevel(opts.level)
    else
        f:SetFrameLevel(parent:GetFrameLevel() + 10)
    end
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp")

    -- Dark background matching unlock mode movers
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.103, 0.095, 0.088, 0.95)
    f._bg = bg

    -- Accent border at 60% alpha
    f._brd = EllesmereUI.MakeBorder(f, ar, ag, ab, 0.6)

    -- White centered label matching unlock mode mover style
    local fontPath = (EllesmereUI.GetFontPath("extras"))
        or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetFont(fontPath, 10, "OUTLINE, SLUG")
    label:SetText(EllesmereUI.L(opts.text or "Move in Unlock Mode"))
    label:SetTextColor(1, 1, 1, 0.9)
    label:SetPoint("CENTER")
    f._label = label

    -- Hover: accent text + brighten border
    local brd = f._brd
    f:SetScript("OnEnter", function()
        label:SetTextColor(ar, ag, ab, 1)
        if brd then brd:SetColor(ar, ag, ab, 0.85) end
    end)
    f:SetScript("OnLeave", function()
        label:SetTextColor(1, 1, 1, 0.9)
        if brd then brd:SetColor(ar, ag, ab, 0.6) end
    end)

    -- Click: open unlock mode (or custom handler)
    f:SetScript("OnClick", opts.onClick or function()
        if EllesmereUI.ToggleUnlockMode then
            EllesmereUI:ToggleUnlockMode()
        end
    end)

    return f
end

-- Debuff "Max Duration" dropdown spec for a DualRow slot: Unlimited (nil, the
-- consumer adds nothing to its candidate filters) or Custom, which opens the
-- standard input popup for a whole number of seconds and then reads back as
-- "Custom (Ns)". get/set move the stored seconds (nil = unlimited); apply
-- re-drives the display. Shared by the Raid Frames Debuff Manager (base grid
-- and grid tiles) and Player Aura Bars debuff bars.
function EllesmereUI.MaxDurationDropdown(get, set, apply)
    local L = EllesmereUI.L
    local cur = get()
    local values = {
        unlimited = L("Unlimited"),
        custom = cur and (L("Custom") .. " (" .. tostring(cur) .. "s)") or (L("Custom") .. "..."),
    }
    return {
        type = "dropdown", text = "Max Duration",
        tooltip = "Only show debuffs whose full duration is at most this many seconds. Combines with the filters; Unlimited applies no cap.",
        values = values, order = { "unlimited", "custom" },
        getValue = function() return get() and "custom" or "unlimited" end,
        setValue = function(v)
            if v == "unlimited" then
                if get() ~= nil then
                    set(nil)
                    if apply then apply() end
                end
                EllesmereUI:RefreshPage(true)
                return
            end
            local now = get()
            EllesmereUI:ShowInputPopup({
                title = L("Max Duration"),
                message = L("Enter the maximum debuff duration in seconds:"),
                placeholder = now and tostring(now) or "30",
                confirmText = L("Apply"),
                cancelText = L("Cancel"),
                onConfirm = function(text)
                    local n = tonumber(text or "")
                    if n and n > 0 then
                        n = math.floor(n)
                        if n ~= get() then
                            set(n)
                            if apply then apply() end
                        end
                    end
                    EllesmereUI:RefreshPage(true)
                end,
                onCancel = function() EllesmereUI:RefreshPage(true) end,
            })
        end,
    }
end

-- Sound dropdown data for a DualRow slot or a cog row: a fresh values table
-- (a click-to-preview speaker icon on every playable row) and the order list.
-- paths / names / order are a catalogue from BuildAlertSoundTables(); left out,
-- they are the Quality of Life alert-sound catalogue (just "None" while it is
-- absent). A path is a sound file or a SoundKit id.
-- Sound preview icon for every sound picker and play button. WoW Forever has no
-- common-icon-sound atlases; its dropdown speaker stands in for both states.
EllesmereUI.SOUND_ICON_ATLAS = C_Texture.GetAtlasInfo("common-icon-sound")
    and "common-icon-sound" or "common-dropdown-icon-sound-on"
EllesmereUI.SOUND_ICON_PRESSED_ATLAS = C_Texture.GetAtlasInfo("common-icon-sound-pressed")
    and "common-icon-sound-pressed" or EllesmereUI.SOUND_ICON_ATLAS

function EllesmereUI.BuildSoundDropdownValues(paths, names, order)
    paths = paths or EllesmereUI._groupDeathSoundPaths or {}
    names = names or EllesmereUI._groupDeathSoundNames or { none = "None" }
    order = order or EllesmereUI._groupDeathSoundOrder or { "none" }
    local values = {}
    for k, v in pairs(names) do values[k] = v end
    values._menuOpts = {
        itemHeight = 26,
        maxTextWidthPct = 0.8,
        searchable = true,
        iconAtlas = function(key)
            if key == "none" or not paths[key] then return nil end
            return EllesmereUI.SOUND_ICON_ATLAS
        end,
        iconPressedAtlas = function(key)
            if key == "none" or not paths[key] then return nil end
            return EllesmereUI.SOUND_ICON_PRESSED_ATLAS
        end,
        iconOnClick = function(key) EllesmereUI.PlaySoundPath(paths[key]) end,
        iconTooltip = function() return "Preview Sound" end,
    }
    return values, order
end

-- Voice ids vary by client and installed speech engines, so enumerate them
-- live. Keep the default voice available when the API or voice list is absent.
function EllesmereUI.BuildTTSVoiceDropdownValues(onPreview)
    local values, order = { [0] = "Default" }, { 0 }
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
        if ok and type(voices) == "table" then
            for _, voice in ipairs(voices) do
                if voice.voiceID and voice.voiceID ~= 0 and voice.name then
                    values[voice.voiceID] = voice.name
                    order[#order + 1] = voice.voiceID
                end
            end
        end
    end
    values._menuOpts = {
        itemHeight = 26,
        maxTextWidthPct = 0.8,
        iconAtlas = function() return EllesmereUI.SOUND_ICON_ATLAS end,
        iconPressedAtlas = function() return EllesmereUI.SOUND_ICON_PRESSED_ATLAS end,
        iconOnClick = function(key)
            if onPreview then
                onPreview(key)
            else
                EllesmereUI.SpeakText("This is a voice preview", key, 100)
            end
        end,
        iconTooltip = function() return "Preview Voice" end,
    }
    return values, order
end

-------------------------------------------------------------------------------
--  Global Settings > Fonts / Textures: shared row helpers and module card
-------------------------------------------------------------------------------

-- Fresh table per call: DualRow configs must never be shared across rows.
function EllesmereUI.BlankRowCfg() return { type = "label", text = "" } end

function EllesmereUI.ModuleNS(folder) return EllesmereUI._ModuleNS and EllesmereUI._ModuleNS[folder] end

-- Custom link row: label on the left, an Open Settings button on the right,
-- jumping to the module page that owns a selection-bound settings family.
function EllesmereUI.BuildLinkRow(parent, y, label, module, page, section, highlight)
    local PP = EllesmereUI.PanelPP
    local ROW_H = 40
    local row = CreateFrame("Frame", nil, parent)
    PP.Size(row, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, ROW_H)
    PP.Point(row, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    row._skipRowDivider = true
    EllesmereUI.RowBg(row, parent)

    local lbl = EllesmereUI.MakeFont(row, 13, nil, 1, 1, 1)
    lbl:SetAlpha(0.9)
    lbl:SetPoint("LEFT", row, "LEFT", 20, 0)
    lbl:SetText(EllesmereUI.L(label))

    local btn = CreateFrame("Button", nil, row)
    PP.Size(btn, 122, 26)
    btn:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    btn:SetFrameLevel(row:GetFrameLevel() + 2)
    EllesmereUI.MakeStyledButton(btn, "Open Settings", 11, EllesmereUI.WB_COLOURS, function()
        EllesmereUI:NavigateToElementSettings(module, page, section, nil, highlight)
    end)

    return y - ROW_H
end

-- A row of action cards across the page (icon, title, a short description;
-- the whole card is the click). cards[i] = { icon, title, desc, onClick,
-- accent, hero, iconSize, sizeAlso, pulse } -- accent { r, g, b } tints the icon
-- (and a box's top edge), the theme accent when nil; iconSize (px) draws art
-- that fills more of its canvas smaller, centred in the same slot (the text
-- never moves). By default the cards are equal boxes side by side across
-- opts.width (a fraction of the content width, centred). opts.inline lays
-- them out in ONE line instead: plain text buttons with a thin divider
-- between items, each as wide as its text (sizeAlso { title, desc } also fits
-- the other text a card can switch to), the texts shrinking together when the
-- line would not fit opts.width, centred; a hero card there is a button in
-- the equal cards' boxed look. opts.footer (px, inline) leaves that much free
-- under the line for the caller (a link). Returns the new y and the card
-- buttons (in cards order); card:SetCardContent(icon, title, desc) swaps all
-- three in place. An equal card built with pulse = true also takes
-- card:SetPulse(on): a breathing accent outline for an action that wants
-- attention now, animated only while the card shows.
local function BuildInlineRow(parent, y, cards, availW, fullW, footer)
    local PP = EllesmereUI.PanelPP
    local L  = EllesmereUI.L
    local ROW_H, ICON, DIV_GAP, DIV_H = 60, 26, 24, 40
    local TITLE_SZ, DESC_SZ, DESC_GAP = 13, 11, 4
    -- Plain items, and the boxed hero in the equal cards' values (left pad,
    -- icon-to-text gap, right pad, alphas, outline).
    local GAP, ICON_A, TITLE_A, DESC_A = 14, 0.75, 0.9, 0.45
    local BOX_L, BOX_GAP, BOX_R, BOX_ICON_A, BOX_DESC_A, BOX_BRD_A = 24, 20, 14, 0.6, 0.35, 0.12
    local n = #cards
    local blockH = ROW_H + (footer or 0)
    local rowFrame = CreateFrame("Frame", nil, parent)

    -- Build each item and measure its text: the wider of its two lines, over
    -- every text it can show.
    local parts, built, sumText, fixed = {}, {}, 0, (n - 1) * (DIV_GAP * 2 + 1)
    for i = 1, n do
        local spec = cards[i]
        local boxed = spec.hero and true or false
        local p = { boxed = boxed,
            padL = boxed and BOX_L or 0, gap = boxed and BOX_GAP or GAP, padR = boxed and BOX_R or 0,
            iconA = boxed and BOX_ICON_A or ICON_A, descA = boxed and BOX_DESC_A or DESC_A }
        local card = CreateFrame("Button", nil, rowFrame)
        card:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
        local icon = card:CreateTexture(nil, "ARTWORK")
        if icon.SetSnapToPixelGrid then icon:SetSnapToPixelGrid(false); icon:SetTexelSnappingBias(0) end
        icon:SetAlpha(p.iconA)
        local titleFs = EllesmereUI.MakeFont(card, TITLE_SZ, nil, 1, 1, 1, TITLE_A)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        local descFs = EllesmereUI.MakeFont(card, DESC_SZ, nil, 1, 1, 1, p.descA)
        descFs:SetJustifyH("LEFT")
        descFs:SetWordWrap(true)
        descFs:SetMaxLines(2)
        function card:SetCardContent(iconPath, cardTitle, cardDesc)
            icon:SetTexture(iconPath)
            titleFs:SetText(L(cardTitle))
            descFs:SetText(L(cardDesc))
        end
        local w = 0
        local function Measure(t, d)
            titleFs:SetText(L(t))
            descFs:SetText(L(d))
            w = math.max(w, math.ceil(titleFs:GetStringWidth()), math.ceil(descFs:GetStringWidth()))
        end
        if spec.sizeAlso then Measure(spec.sizeAlso[1], spec.sizeAlso[2]) end
        Measure(spec.title, spec.desc)
        card:SetCardContent(spec.icon, spec.title, spec.desc)
        p.card, p.icon, p.titleFs, p.descFs, p.textW = card, icon, titleFs, descFs, w
        parts[i] = p
        sumText = sumText + w
        fixed = fixed + p.padL + ICON + p.gap + p.padR
        built[i] = card
    end

    local scale = 1
    if sumText > 0 and fixed + sumText > availW then
        scale = math.max(0, availW - fixed) / sumText
    end
    local totalW = fixed
    for i = 1, n do
        parts[i].textW = math.floor(parts[i].textW * scale)
        totalW = totalW + parts[i].textW
    end
    PP.Size(rowFrame, totalW, blockH)
    PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT",
        EllesmereUI.CONTENT_PAD + math.floor((fullW - totalW) / 2), y)

    local x = 0
    for i = 1, n do
        local spec, p = cards[i], parts[i]
        local card, icon, titleFs, descFs, boxed = p.card, p.icon, p.titleFs, p.descFs, p.boxed
        if i > 1 then
            local div = rowFrame:CreateTexture(nil, "ARTWORK")
            div:SetColorTexture(1, 1, 1, 0.10)
            div:SetWidth(1)
            div:SetHeight(DIV_H)
            PP.Point(div, "TOPLEFT", rowFrame, "TOPLEFT", x + DIV_GAP, -math.floor((ROW_H - DIV_H) / 2))
            x = x + DIV_GAP * 2 + 1
        end
        local w = p.padL + ICON + p.gap + p.textW + p.padR
        PP.Size(card, w, ROW_H)
        PP.Point(card, "TOPLEFT", rowFrame, "TOPLEFT", x, 0)
        x = x + w

        local iconSz = spec.iconSize or ICON
        icon:SetSize(iconSz, iconSz)
        PP.Point(icon, "LEFT", card, "LEFT", p.padL + math.floor((ICON - iconSz) / 2), 0)
        PP.Point(titleFs, "TOPLEFT", card, "LEFT", p.padL + ICON + p.gap, ICON / 2 + 2)
        titleFs:SetWidth(p.textW)
        PP.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -DESC_GAP)
        descFs:SetWidth(p.textW)

        -- The equal cards' box: dark fill, thin outline, an accent top edge.
        local bg, brd, accentLine
        if boxed then
            bg = card:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            brd = EllesmereUI.MakeBorder(card, 1, 1, 1, BOX_BRD_A, PP)
            accentLine = card:CreateTexture(nil, "ARTWORK", nil, 7)
            PP.Point(accentLine, "TOPLEFT", card, "TOPLEFT", 1, -1)
            PP.Point(accentLine, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
            accentLine:SetHeight(2)
            if accentLine.SetSnapToPixelGrid then accentLine:SetSnapToPixelGrid(false); accentLine:SetTexelSnappingBias(0) end
        end
        -- The accent is read at paint time, so an accent change repaints it.
        local function Paint(hover)
            local ac = spec.accent or EllesmereUI.ELLESMERE_GREEN
            icon:SetVertexColor(ac.r, ac.g, ac.b)
            if boxed then
                accentLine:SetColorTexture(ac.r, ac.g, ac.b, 0.6)
                if hover then bg:SetColorTexture(0.119, 0.111, 0.104, 0.50)
                else bg:SetColorTexture(0.077, 0.068, 0.058, 0.50) end
                brd:SetColor(1, 1, 1, hover and (BOX_BRD_A + 0.10) or BOX_BRD_A)
            end
        end
        Paint(false)
        if not spec.accent then
            EllesmereUI.RegisterWidgetRefresh(function() Paint(card:IsMouseOver()) end)
        end
        -- The labels' resting alpha is their text colour's (MakeFont), so the
        -- hover moves that alpha, never the region's: a leave puts back exactly
        -- the look a new card has.
        card:SetScript("OnEnter", function()
            Paint(true)
            icon:SetAlpha(boxed and (BOX_ICON_A + 0.25) or 1)
            titleFs:SetTextColor(1, 1, 1, 1)
            if not boxed then descFs:SetTextColor(1, 1, 1, DESC_A + 0.15) end
        end)
        card:SetScript("OnLeave", function()
            Paint(false)
            icon:SetAlpha(p.iconA)
            titleFs:SetTextColor(1, 1, 1, TITLE_A)
            descFs:SetTextColor(1, 1, 1, p.descA)
        end)
        if spec.onClick then card:SetScript("OnClick", spec.onClick) end
    end
    return y - blockH, built
end

function EllesmereUI.BuildActionCardRow(parent, y, cards, opts)
    local PP = EllesmereUI.PanelPP
    local L  = EllesmereUI.L
    local n = #cards
    local fullW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
    local totalW = (opts and opts.width) and math.floor(fullW * opts.width) or fullW
    if opts and opts.inline then
        return BuildInlineRow(parent, y, cards, totalW, fullW, opts.footer)
    end

    local CARD_H, CARD_GAP = 66, 14
    local M = { icon = 26, iconX = 24, title = 13, titleGap = 20, titleY = 2,
                desc = 11, descGap = 4, descA = 0.35, pad = 14 }
    local left = EllesmereUI.CONTENT_PAD + math.floor((fullW - totalW) / 2)
    local cardW = math.floor((totalW - CARD_GAP * (n - 1)) / n)

    local rowFrame = CreateFrame("Frame", nil, parent)
    PP.Size(rowFrame, totalW, CARD_H)
    PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", left, y)

    local built = {}
    for i = 1, n do
        local spec = cards[i]
        local ac = spec.accent or EllesmereUI.ELLESMERE_GREEN
        local card = CreateFrame("Button", nil, rowFrame)
        PP.Size(card, cardW, CARD_H)
        PP.Point(card, "TOPLEFT", rowFrame, "TOPLEFT", (i - 1) * (cardW + CARD_GAP), 0)
        card:SetFrameLevel(rowFrame:GetFrameLevel() + 2)

        local bg = card:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.077, 0.068, 0.058, 0.50)
        local BRD_A = 0.12
        local brd = EllesmereUI.MakeBorder(card, 1, 1, 1, BRD_A, PP)

        -- Accent top edge
        local accentLine = card:CreateTexture(nil, "ARTWORK", nil, 7)
        accentLine:SetColorTexture(ac.r, ac.g, ac.b, 0.6)
        PP.Point(accentLine, "TOPLEFT", card, "TOPLEFT", 1, -1)
        PP.Point(accentLine, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
        accentLine:SetHeight(2)
        if accentLine.SetSnapToPixelGrid then accentLine:SetSnapToPixelGrid(false); accentLine:SetTexelSnappingBias(0) end

        local ICON_A, TITLE_A = 0.6, 0.9
        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetVertexColor(ac.r, ac.g, ac.b)
        icon:SetAlpha(ICON_A)
        if icon.SetSnapToPixelGrid then icon:SetSnapToPixelGrid(false); icon:SetTexelSnappingBias(0) end

        -- Icon on the left, title and description to its right.
        local iconSz = spec.iconSize or M.icon
        icon:SetSize(iconSz, iconSz)
        PP.Point(icon, "LEFT", card, "LEFT", M.iconX + math.floor((M.icon - iconSz) / 2), 0)
        local titleFs = EllesmereUI.MakeFont(card, M.title, nil, 1, 1, 1, TITLE_A)
        -- Off the icon slot, not the icon, so every card's text lines up.
        PP.Point(titleFs, "TOPLEFT", card, "LEFT", M.iconX + M.icon + M.titleGap, M.icon / 2 + M.titleY)
        PP.Point(titleFs, "RIGHT", card, "RIGHT", -M.pad, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        local descFs = EllesmereUI.MakeFont(card, M.desc, nil, 1, 1, 1, M.descA)
        PP.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -M.descGap)
        PP.Point(descFs, "RIGHT", card, "RIGHT", -M.pad, 0)
        descFs:SetJustifyH("LEFT")
        -- Two lines at most: a narrow card is short of room in longer languages.
        descFs:SetWordWrap(true)
        descFs:SetMaxLines(2)

        function card:SetCardContent(iconPath, cardTitle, cardDesc)
            icon:SetTexture(iconPath)
            titleFs:SetText(L(cardTitle))
            descFs:SetText(L(cardDesc))
        end
        card:SetCardContent(spec.icon, spec.title, spec.desc)

        -- The pulse outline is built with the card whenever it is asked for,
        -- so a kept page hands it back in order; it stays hidden until
        -- SetPulse turns it on, and its fade plays only while it shows.
        local pulse
        if spec.pulse then
            pulse = CreateFrame("Frame", nil, card)
            pulse:SetAllPoints(card)
            pulse:SetFrameLevel(card:GetFrameLevel() + 3)
            pulse:EnableMouse(false)
            pulse:Hide()
            PP.CreateBorder(pulse, ac.r, ac.g, ac.b, 1, 2, "OVERLAY", 7)
            local breathe = pulse:CreateAnimationGroup()
            breathe:SetLooping("BOUNCE")
            local fade = breathe:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0.2)
            fade:SetDuration(0.9)
            fade:SetSmoothing("IN_OUT")
            pulse:SetScript("OnShow", function() breathe:Play() end)
            pulse:SetScript("OnHide", function() breathe:Stop() end)
        end
        function card:SetPulse(on)
            if not pulse then return end
            if on then
                local live = spec.accent or EllesmereUI.ELLESMERE_GREEN
                PP.SetBorderColor(pulse, live.r, live.g, live.b, 1)
            end
            pulse:SetShown(on and true or false)
        end

        -- The title's resting alpha is its text colour's (as BuildInlineRow's).
        card:SetScript("OnEnter", function()
            bg:SetColorTexture(0.119, 0.111, 0.104, 0.50)
            brd:SetColor(1, 1, 1, BRD_A + 0.10)
            titleFs:SetTextColor(1, 1, 1, 1)
            icon:SetAlpha(ICON_A + 0.25)
        end)
        card:SetScript("OnLeave", function()
            bg:SetColorTexture(0.077, 0.068, 0.058, 0.50)
            brd:SetColor(1, 1, 1, BRD_A)
            titleFs:SetTextColor(1, 1, 1, TITLE_A)
            icon:SetAlpha(ICON_A)
        end)
        if spec.onClick then card:SetScript("OnClick", spec.onClick) end
        built[i] = card
    end
    return y - CARD_H, built
end

-- Note row: a dim aside (inside a card when its module is disabled, under a
-- row). opts.banner: the section banner look (row background, brighter text,
-- up to two lines), for a note the player must read before the rows below.
function EllesmereUI.BuildNoteRow(parent, y, text, opts)
    local banner = opts and opts.banner
    local ROW_H = banner and 40 or 34
    -- The search prebuild only indexes rows: same y advance, no frames.
    if EllesmereUI._prebuilding then return y - ROW_H end
    local PP = EllesmereUI.PanelPP
    local row = CreateFrame("Frame", nil, parent)
    PP.Size(row, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, ROW_H)
    PP.Point(row, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    row._skipRowDivider = true
    if banner then EllesmereUI.RowBg(row, parent) end
    local lbl = EllesmereUI.MakeFont(row, 12, nil, 1, 1, 1)
    lbl:SetAlpha(banner and 0.6 or 0.45)
    lbl:SetPoint("LEFT", row, "LEFT", 20, 0)
    if banner then
        lbl:SetPoint("RIGHT", row, "RIGHT", -20, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(true)
        lbl:SetMaxLines(2)
    end
    lbl:SetText(EllesmereUI.L(text))
    return y - ROW_H
end

local MC_ARROW_DOWN = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
local MC_ARROW_UP   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-up3.png"
local MC_HEADER_H   = 54
local MC_CARD_GAP   = 14

-- One expandable module card (adapted from the Window Skins card). opts:
-- enabled, expanded (session table keyed by tile.key), descW,
-- glyph(hdr, enabled) builds the left glyph, headerDD(hdr) -> dd or nil,
-- searchDesc: what search indexes (and the header's section name carries) in
-- place of tile.desc, for a card whose description is live (a count);
-- noSearch: the header is no search entry (a card that holds no settings).
-- A disabled module's card is inert: dimmed header, tag and tooltip only.
-- Sets tile._hdr and tile._descFS (the header and its description line)
-- before tile.buildContent runs, for content that updates the header.
function EllesmereUI.BuildModuleCard(parent, y, W, tile, opts)
    local PP = EllesmereUI.PanelPP
    local EG = EllesmereUI.ELLESMERE_GREEN
    local L  = EllesmereUI.L
    local enabled = opts.enabled
    local expanded = enabled and opts.expanded[tile.key]
    local cardTop = y
    local brd

    -- Explicit size + single TOPLEFT anchor (the widget contract; see the
    -- Window Skins card for why a second point would zero the width).
    local cardW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
    local hdr = CreateFrame("Button", nil, parent)
    PP.Size(hdr, cardW, MC_HEADER_H)
    PP.Point(hdr, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
    hdr:SetFrameLevel(parent:GetFrameLevel() + 3)

    -- The header is its own pseudo-section, so searching the module name
    -- lands on the card; each page's deep-link pre-hook expands cards first.
    local sDesc = opts.searchDesc
    if sDesc == nil then sDesc = tile.desc or "" end
    local searchName = tile.display .. " " .. sDesc
    if not opts.noSearch then
        hdr._isSectionHeader = true
        hdr._sectionName = searchName
        local searchNameLoc = L(tile.display) .. " " .. L(sDesc)
        if searchNameLoc ~= searchName then hdr._sectionNameLoc = searchNameLoc end
    end
    if EllesmereUI._RegisterSearchEntry and not opts.noSearch then
        local titleLoc = L(tile.display)
        local descSearch = sDesc
        local descLoc = L(sDesc)
        if descLoc ~= descSearch then descSearch = descSearch .. " " .. descLoc end
        EllesmereUI._RegisterSearchEntry(tile.display,
            titleLoc ~= tile.display and titleLoc or nil,
            descSearch,
            EllesmereUI._buildingModule, EllesmereUI._buildingPage,
            searchName, nil, nil, true)
    end

    local hbg = EllesmereUI.SolidTex(hdr, "BACKGROUND", 0, 0, 0, 0)
    hbg:SetAllPoints()

    opts.glyph(hdr, enabled)

    local title = EllesmereUI.MakeFont(hdr, 14, nil, 1, 1, 1, 0.9)
    PP.Point(title, "TOPLEFT", hdr, "TOPLEFT", 50, -12)
    title:SetText(L(tile.display))

    local desc = EllesmereUI.MakeFont(hdr, 11, nil, 1, 1, 1, 0.42)
    PP.Point(desc, "TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetWidth(opts.descW)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(false)
    desc:SetText(L(tile.desc or ""))
    tile._hdr, tile._descFS = hdr, desc

    if not enabled then
        title:SetAlpha(0.4)
        desc:SetAlpha(0.22)
    end

    local chev
    if enabled then
        chev = hdr:CreateTexture(nil, "OVERLAY")
        PP.Size(chev, 16, 16)
        PP.Point(chev, "RIGHT", hdr, "RIGHT", -16, 0)
        chev:SetTexture(expanded and MC_ARROW_UP or MC_ARROW_DOWN)
        chev:SetAlpha(0.45)
        if expanded then chev:SetVertexColor(EG.r, EG.g, EG.b) end
    end

    local dd = enabled and opts.headerDD and opts.headerDD(hdr)

    local strip
    -- The title's resting alpha is its text colour's (MakeFont), so the hover
    -- moves that alpha: a leave puts back exactly the look a new card has.
    local function ApplyHeaderHover()
        hbg:SetColorTexture(1, 1, 1, 0.05)
        title:SetTextColor(1, 1, 1, 1)
        if chev then chev:SetAlpha(0.85) end
        if brd then brd:SetColor(1, 1, 1, 0.22) end
    end
    local function ClearHeaderHover()
        if hdr:IsMouseOver() then return end
        hbg:SetColorTexture(0, 0, 0, 0)
        title:SetTextColor(1, 1, 1, 0.9)
        if chev then chev:SetAlpha(0.45) end
        if brd then brd:SetColor(1, 1, 1, expanded and 0.16 or 0.12) end
    end
    if enabled then
        hdr:SetScript("OnEnter", ApplyHeaderHover)
        hdr:SetScript("OnLeave", ClearHeaderHover)
        if dd then
            dd:HookScript("OnEnter", ApplyHeaderHover)
            dd:HookScript("OnLeave", ClearHeaderHover)
        end
        hdr:SetScript("OnClick", function()
            opts.expanded[tile.key] = not opts.expanded[tile.key]
            EllesmereUI:RefreshPage(true)
        end)
    else
        local tag = EllesmereUI.MakeFont(hdr, 11, nil, 1, 1, 1)
        tag:SetAlpha(0.3)
        PP.Point(tag, "RIGHT", hdr, "RIGHT", -16, 0)
        tag:SetText(L("Module Disabled"))
        hdr:SetScript("OnEnter", function(self)
            EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.Lf("Enable %1$s to edit these settings.", L(tile.display)))
        end)
        hdr:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
    end

    y = y - MC_HEADER_H

    if expanded then
        local div = hdr:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(1, 1, 1, 0.07)
        div:SetHeight(1)
        PP.Point(div, "BOTTOMLEFT", hdr, "BOTTOMLEFT", 1, 0)
        PP.Point(div, "BOTTOMRIGHT", hdr, "BOTTOMRIGHT", -1, 0)
        PP.DisablePixelSnap(div)

        y = y - 8
        y = tile.buildContent(parent, y, W, tile)
        y = y - 8
    end

    -- Card background + border spanning header and expanded content (header
    -- child so inline search re-flows it with the header; see WS card notes).
    local bg = CreateFrame("Frame", nil, hdr)
    bg:SetFrameLevel(parent:GetFrameLevel())
    PP.Size(bg, cardW, cardTop - y)
    PP.Point(bg, "TOPLEFT", hdr, "TOPLEFT", 0, 0)
    local fill = EllesmereUI.SolidTex(bg, "BACKGROUND", 0.077, 0.068, 0.058, 0.5)
    fill:SetAllPoints()
    brd = EllesmereUI.MakeBorder(bg, 1, 1, 1, expanded and 0.16 or 0.12, PP)

    strip = bg:CreateTexture(nil, "ARTWORK")
    strip:SetWidth(2)
    if enabled then
        strip:SetColorTexture(EG.r, EG.g, EG.b, 0.7)
    else
        strip:SetColorTexture(1, 1, 1, 0.10)
    end
    PP.Point(strip, "TOPLEFT", hdr, "TOPLEFT", 1, -1)
    PP.Point(strip, "BOTTOMLEFT", hdr, "BOTTOMLEFT", 1, 1)
    if strip.SetSnapToPixelGrid then strip:SetSnapToPixelGrid(false); strip:SetTexelSnappingBias(0) end
    -- The accent parts follow a live accent change (it refreshes the shown page).
    if enabled then
        EllesmereUI.RegisterWidgetRefresh(function()
            strip:SetColorTexture(EG.r, EG.g, EG.b, 0.7)
            if chev and expanded then chev:SetVertexColor(EG.r, EG.g, EG.b) end
        end)
    end

    return y - MC_CARD_GAP
end

-------------------------------------------------------------------------------
--  Manager-page parts (Buff Manager, Debuff Manager, Player Aura Bars)
-------------------------------------------------------------------------------
-- Sidebar tile. opts: width, fontPath, title, subtitle | subtitleFn, icon | iconFn
-- (the Fn forms re-read on every page widget refresh) | iconApply(tex) (paints
-- the icon itself, no crop), statusDot ({ r, g, b }: 8px dot, top right, left of
-- the toggle pill when shown), posText, selected,
-- enabled, showToggle, dimmed, inheritedTooltip,
-- onSelect(), onToggle(newState), onDelete(), onEdit(), onContext(tile),
-- height (66), textRight (-52), titleUnclamped, editSize (16), editTooltip,
-- editSnap (keep pixel snapping on the pencil). Returns height, tile.
function EllesmereUI.BuildManagerTile(parentFrame, y, opts)
    local fontPath = opts.fontPath
    local PP = EllesmereUI.PanelPP
    local TILE_H = opts.height or 66
    local IR, IG, IB = 0.55, 0.72, 1
    local tile = CreateFrame("Button", nil, parentFrame)
    tile:SetSize(opts.width, TILE_H)
    tile:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, y)
    tile:SetFrameLevel(parentFrame:GetFrameLevel() + 1)

    local bg = tile:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, opts.selected and 0.06 or 0)

    if opts.selected then
        local accent = tile:CreateTexture(nil, "ARTWORK", nil, 2)
        accent:SetSize(2, TILE_H)
        accent:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
        if opts.inheritedTooltip then
            accent:SetColorTexture(IR, IG, IB, 1)
        else
            local ac = EllesmereUI.ELLESMERE_GREEN
            accent:SetColorTexture(ac.r, ac.g, ac.b, 1)
        end
    elseif opts.inheritedTooltip then
        local edge = tile:CreateTexture(nil, "ARTWORK", nil, 2)
        edge:SetSize(2, TILE_H)
        edge:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
        edge:SetColorTexture(IR, IG, IB, 0.45)
    end

    local textX = 12
    local titleY = -10
    -- A status dot beside the toggle pill pushes the text further in.
    local textRight = opts.textRight or ((opts.showToggle and opts.statusDot) and -60 or -52)

    if opts.icon or opts.iconFn or opts.iconApply then
        local ICON_SZ = 36
        local iconFrame = CreateFrame("Frame", nil, tile)
        iconFrame:SetSize(ICON_SZ, ICON_SZ)
        iconFrame:SetPoint("TOPLEFT", tile, "TOPLEFT", 8, -8)
        iconFrame:SetFrameLevel(tile:GetFrameLevel() + 1)
        local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        if opts.iconApply then
            opts.iconApply(iconTex)
        else
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            iconTex:SetTexture(opts.iconFn and opts.iconFn() or opts.icon)
        end
        if opts.iconFn then
            EllesmereUI.RegisterWidgetRefresh(function() iconTex:SetTexture(opts.iconFn()) end)
        end
        local iconBdr = CreateFrame("Frame", nil, iconFrame)
        iconBdr:SetAllPoints()
        iconBdr:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
        PP.CreateBorder(iconBdr, 0, 0, 0, 0.6, 1)
        textX = 8 + ICON_SZ + 8
        titleY = -8
    end

    local title = tile:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 13, "")
    title:SetPoint("TOPLEFT", tile, "TOPLEFT", textX, titleY)
    if not opts.posText and not opts.titleUnclamped then
        title:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
    end
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText(opts.title or "")
    if opts.inheritedTooltip then
        title:SetTextColor(IR, IG, IB)
    else
        title:SetTextColor(1, 1, 1)
    end

    if opts.posText then
        local posFS = tile:CreateFontString(nil, "OVERLAY")
        posFS:SetPoint("LEFT", title, "RIGHT", 4, 0)
        posFS:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
        posFS:SetFont(fontPath, 11, "")
        posFS:SetJustifyH("LEFT")
        posFS:SetWordWrap(false)
        posFS:SetText(opts.posText)
        posFS:SetTextColor(0.75, 0.75, 0.75, 0.65)
    end

    if opts.subtitle or opts.subtitleFn then
        local sub = tile:CreateFontString(nil, "OVERLAY")
        sub:SetFont(fontPath, 11, "")
        sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        sub:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
        sub:SetJustifyH("LEFT")
        sub:SetWordWrap(false)
        sub:SetText(opts.subtitleFn and opts.subtitleFn() or opts.subtitle)
        if opts.inheritedTooltip then
            sub:SetTextColor(IR, IG, IB, 0.55)
        else
            sub:SetTextColor(0.4, 0.4, 0.4)
        end
        -- Re-read on every non-force RefreshPage (a full rebuild would close
        -- an open checkbox dropdown in the detail pane).
        if opts.subtitleFn then
            EllesmereUI.RegisterWidgetRefresh(function() sub:SetText(opts.subtitleFn()) end)
        end
    end

    tile:SetScript("OnEnter", function()
        if not opts.selected then bg:SetColorTexture(1, 1, 1, 0.04) end
        if opts.inheritedTooltip then
            EllesmereUI.ShowWidgetTooltip(tile, opts.inheritedTooltip)
        end
    end)
    tile:SetScript("OnLeave", function()
        bg:SetColorTexture(1, 1, 1, opts.selected and 0.06 or 0)
        if opts.inheritedTooltip then
            EllesmereUI.HideWidgetTooltip()
        end
    end)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tile:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" then
            if opts.onContext then opts.onContext(tile) end
            return
        end
        if opts.onSelect then opts.onSelect() end
    end)

    if opts.showToggle then
        local toggleH = 16
        local toggleBtn = CreateFrame("Button", nil, tile)
        toggleBtn:SetSize(32, toggleH)
        toggleBtn:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -8, -8)
        toggleBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        -- Inherited rows: the pill is the per-spec control and stays
        -- full-brightness when the row dims.
        if opts.inheritedTooltip and toggleBtn.SetIgnoreParentAlpha then
            toggleBtn:SetIgnoreParentAlpha(true)
        end
        local toggleBg = toggleBtn:CreateTexture(nil, "BACKGROUND")
        toggleBg:SetAllPoints()
        local toggleKnob = toggleBtn:CreateTexture(nil, "ARTWORK")
        toggleKnob:SetSize(toggleH - 4, toggleH - 4)
        if opts.enabled then
            local acr, acg, acb = EllesmereUI.ResolveActiveAccent()
            toggleBg:SetColorTexture(acr, acg, acb, 1)
            toggleKnob:SetPoint("RIGHT", toggleBtn, "RIGHT", -2, 0)
            toggleKnob:SetColorTexture(1, 1, 1, 1)
        else
            toggleBg:SetColorTexture(0.25, 0.25, 0.25, 1)
            toggleKnob:SetPoint("LEFT", toggleBtn, "LEFT", 2, 0)
            toggleKnob:SetColorTexture(0.5, 0.5, 0.5, 1)
        end
        toggleBtn:SetScript("OnClick", function()
            if opts.onToggle then opts.onToggle(not opts.enabled) end
        end)
    end

    local delBtn
    if opts.onDelete then
        delBtn = CreateFrame("Button", nil, tile)
        delBtn:SetSize(16, 16)
        delBtn:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 6)
        delBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        local delTex = delBtn:CreateTexture(nil, "OVERLAY")
        delTex:SetAllPoints()
        EllesmereUI.SetDeleteIcon(delTex)
        delTex:SetDesaturated(true)
        delTex:SetVertexColor(0.75, 0.75, 0.75)
        delBtn:SetAlpha(0.5)
        delBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
        delBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
        delBtn:SetScript("OnClick", function() opts.onDelete() end)
    end

    -- Rename pencil beside the trash.
    if opts.onEdit then
        local editSize = opts.editSize or 16
        local editBtn = CreateFrame("Button", nil, tile)
        editBtn:SetSize(editSize, editSize)
        if delBtn then
            editBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
        else
            editBtn:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 6)
        end
        editBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        local editTex = editBtn:CreateTexture(nil, "OVERLAY")
        editTex:SetAllPoints()
        if not opts.editSnap and editTex.SetSnapToPixelGrid then
            editTex:SetSnapToPixelGrid(false); editTex:SetTexelSnappingBias(0)
        end
        editTex:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-edit.png")
        editBtn:SetAlpha(0.5)
        local tip = opts.editTooltip
        editBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.9)
            if tip then EllesmereUI.ShowWidgetTooltip(self, tip) end
        end)
        editBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.5)
            if tip then EllesmereUI.HideWidgetTooltip() end
        end)
        editBtn:SetScript("OnClick", function() opts.onEdit() end)
    end

    local sep = tile:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(1, 1, 1, 0.04)

    if opts.statusDot then
        local dot = tile:CreateTexture(nil, "ARTWORK")
        PP.Size(dot, 8, 8)
        -- Left of the toggle pill when the tile has one.
        PP.Point(dot, "TOPRIGHT", tile, "TOPRIGHT", opts.showToggle and -46 or -12, -14)
        dot:SetTexture("Interface\\Common\\CommonMaskCircle")
        dot:SetVertexColor(opts.statusDot[1], opts.statusDot[2], opts.statusDot[3], 1)
    end

    if opts.dimmed then tile:SetAlpha(0.55) end

    return TILE_H, tile
end

-- Full-page cover over a manager page (override-session notice or the PAB
-- enable prompt). opts: fontPath, width, title, text, sub, buttonLabel.
-- Returns ov, btn (btn only with buttonLabel; the caller sets its OnClick).
function EllesmereUI.BuildActivationOverlay(outerRoot, opts)
    local fontPath = opts.fontPath
    local ov = CreateFrame("Frame", nil, outerRoot)
    ov:SetAllPoints(outerRoot)
    ov:SetFrameLevel(outerRoot:GetFrameLevel() + 60)
    ov:EnableMouse(true)
    ov._searchIgnore = true
    local bg = ov:CreateTexture(nil, "OVERLAY")
    bg:SetAllPoints()
    bg:SetColorTexture(17/255, 15/255, 12/255, 0.98)
    local title = ov:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontPath, 15, "")
    title:SetPoint("CENTER", ov, "CENTER", 0, 60)
    title:SetTextColor(1, 1, 1, 0.9)
    title:SetText(opts.title)
    local body = ov:CreateFontString(nil, "OVERLAY")
    body:SetFont(fontPath, 13, "")
    body:SetPoint("TOP", title, "BOTTOM", 0, -14)
    body:SetWidth(math.floor(opts.width * 0.7))
    body:SetJustifyH("CENTER")
    body:SetTextColor(1, 1, 1, 0.56)
    body:SetText(opts.text or "")
    local sub
    if opts.sub then
        sub = ov:CreateFontString(nil, "OVERLAY")
        sub:SetFont(fontPath, 12, "")
        sub:SetPoint("TOP", body, "BOTTOM", 0, -8)
        sub:SetWidth(math.floor(opts.width * 0.7))
        sub:SetJustifyH("CENTER")
        sub:SetTextColor(1, 1, 1, 0.45)
        sub:SetText(opts.sub)
    end
    if not opts.buttonLabel then return ov end
    local btn = CreateFrame("Button", nil, ov)
    btn:SetSize(240, 28)
    btn:SetPoint("TOP", sub or body, "BOTTOM", 0, -22)
    EllesmereUI.SolidTex(btn, "BACKGROUND", 0.10, 0.10, 0.11, 0.9):SetAllPoints(btn)
    local brd = EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.22)
    local lbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1, 0.85)
    lbl:SetPoint("CENTER")
    lbl:SetText(opts.buttonLabel)
    local eg = EllesmereUI.ELLESMERE_GREEN
    btn:SetScript("OnEnter", function() brd:SetColor(eg.r, eg.g, eg.b, 0.9) end)
    btn:SetScript("OnLeave", function() brd:SetColor(1, 1, 1, 0.22) end)
    return ov, btn
end

-- Filter-editor popup button (dark bg, 1px border, accent border on hover).
function EllesmereUI.BuildPopupButton(parent, w, h, label, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)
    btn:SetFrameLevel(parent:GetFrameLevel() + 2)
    local bg = EllesmereUI.SolidTex(btn, "BACKGROUND", 0, 0, 0, 0.5); bg:SetAllPoints()
    local brd = EllesmereUI.MakeBorder(btn, 1, 1, 1, 0.25)
    local lbl = EllesmereUI.MakeFont(btn, 12, nil, 1, 1, 1)
    lbl:SetAlpha(0.6)
    lbl:SetPoint("CENTER")
    lbl:SetText(EllesmereUI.L(label))
    local ar, ag, ab = EllesmereUI.GetAccentColor()
    btn:SetScript("OnEnter", function() lbl:SetAlpha(0.9); brd:SetColor(ar, ag, ab, 0.6) end)
    btn:SetScript("OnLeave", function() lbl:SetAlpha(0.6); brd:SetColor(1, 1, 1, 0.25) end)
    btn:SetScript("OnClick", onClick)
    return btn
end
