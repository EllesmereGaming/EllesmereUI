-------------------------------------------------------------------------------
--  EUI_QoL_MovementAlert_Options.lua
--  Options page for Movement Alert (registered as a page under the
--  EllesmereUIQoL module by EUI_QoL_Options.lua). Builds four sections:
--    MOVEMENT COOLDOWN ALERT, TRACKED SPELLS, TIME SPIRAL, GATEWAY SHARD.
--  Position/size for all three on-screen trackers is controlled entirely
--  through EUI's Unlock Mode (registered in EllesmereUIQoL_MovementAlert.lua)
--  rather than in-page sliders, matching how Combat Alert/BattleRes work.
-------------------------------------------------------------------------------

local function DB()
    local fn = _G._EUI_MovementAlert_DB
    return fn and fn() or nil
end

local function MA()
    local d = DB()
    return d and d.profile and d.profile.movementAlert
end

local function Refresh()
    if EllesmereUI._applyMovementAlert then EllesmereUI._applyMovementAlert() end
    if EllesmereUI._applyTimeSpiral then EllesmereUI._applyTimeSpiral() end
    if EllesmereUI._applyGateway then EllesmereUI._applyGateway() end
    if EllesmereUI._UpdateMovementAlertEvents then EllesmereUI._UpdateMovementAlertEvents() end
    if EllesmereUI._CheckMovementCooldown then EllesmereUI._CheckMovementCooldown() end
    if EllesmereUI._CheckGatewayUsable then EllesmereUI._CheckGatewayUsable() end
end

local DISPLAY_MODE_VALUES = { text = "Text", icon = "Icon", bar = "Bar" }
local DISPLAY_MODE_ORDER  = { "text", "icon", "bar" }

local CLASS_ORDER = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER",
    "MAGE", "MONK", "PALADIN", "PRIEST", "ROGUE",
    "SHAMAN", "WARLOCK", "WARRIOR",
}

-- Reuses EllesmereUI._groupDeathSoundPaths/_groupDeathSoundNames/_groupDeathSoundOrder
-- (built by EllesmereUIQoL.lua, merged with every LibSharedMedia-3.0 "sound"
-- entry at login via EllesmereUI.AppendSharedMediaSounds) instead of
-- querying LSM directly a second time -- one sound-list implementation in
-- the addon, not two. Values can be a file path (string) or a Blizzard
-- SoundKitID (number, most LSM-registered SOUNDKIT.* entries); PlayLSMSound
-- (shared from EllesmereUIQoL_MovementAlert.lua, which loads first per the
-- .toc order) routes preview playback by type.
local function PlayLSMSound(value)
    if EllesmereUI._PlayLSMSound then
        EllesmereUI._PlayLSMSound(value)
        return
    end
    if not value or value == 1 then return end
    if type(value) == "number" then
        PlaySound(value, "Master")
    else
        PlaySoundFile(value, "Master")
    end
end

local function SoundDropdownValues()
    local paths = EllesmereUI._groupDeathSoundPaths or {}
    local names = EllesmereUI._groupDeathSoundNames or { none = "None" }
    local order = EllesmereUI._groupDeathSoundOrder or { "none" }
    local values = {}
    for k, v in pairs(names) do values[k] = v end
    values._menuOpts = {
        itemHeight = 26,
        maxTextWidthPct = 0.8,
        searchable = true,
        iconAtlas = function(key)
            if key == "none" or not paths[key] then return nil end
            return "common-icon-sound"
        end,
        iconPressedAtlas = function(key)
            if key == "none" or not paths[key] then return nil end
            return "common-icon-sound-pressed"
        end,
        iconOnClick = function(key)
            PlayLSMSound(paths[key])
        end,
        iconTooltip = function() return "Preview Sound" end,
    }
    return values, order
end

-- Voices are enumerated live from C_VoiceChat rather than a static list --
-- availability varies by client/OS. Falls back to a single "Default" entry
-- (voiceID 0) if the API or voice list isn't available.
local function TTSVoiceDropdownValues()
    local values, order = { [0] = "Default" }, { 0 }
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
        local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
        if ok and voices then
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
        iconAtlas = function() return "common-icon-sound" end,
        iconPressedAtlas = function() return "common-icon-sound-pressed" end,
        iconOnClick = function(key)
            if C_VoiceChat and C_VoiceChat.SpeakText then
                pcall(C_VoiceChat.SpeakText, key, "This is a voice preview", 1, 100, true)
            end
        end,
        iconTooltip = function() return "Preview Voice" end,
    }
    return values, order
end

-------------------------------------------------------------------------------
--  "Add Spell" popup -- small modal for adding a custom tracked spell by ID,
--  styled after the CDM "Custom Buff ID" popup
--  (EllesmereUICooldownManager\EUI_CooldownManager_Options.lua).
-------------------------------------------------------------------------------
local addSpellPopup
local function ShowAddSpellPopup(onAdded)
    local PP = EllesmereUI.PanelPP
    local FONT = EllesmereUI._font or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"

    if not addSpellPopup then
        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:Hide()
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)

        local popup = CreateFrame("Frame", nil, dimmer)
        popup:SetSize(240, 150)
        popup:SetPoint("CENTER", EllesmereUI._mainFrame or UIParent, "CENTER", 0, 60)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        popup:EnableMouse(true)
        local bg = popup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.08, 0.10, 1)
        EllesmereUI.MakeBorder(popup, 1, 1, 1, 0.15, PP)

        local title = popup:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 14, "")
        title:SetPoint("TOP", popup, "TOP", 0, -18)
        title:SetTextColor(1, 1, 1, 1)
        title:SetText(EllesmereUI.L("Add Spell"))

        local sidLbl = popup:CreateFontString(nil, "OVERLAY")
        sidLbl:SetFont(FONT, 11, "")
        sidLbl:SetPoint("TOPLEFT", popup, "TOPLEFT", 24, -52)
        sidLbl:SetTextColor(0.7, 0.7, 0.7, 1)
        sidLbl:SetText(EllesmereUI.L("Spell ID"))

        local sidBox = CreateFrame("EditBox", nil, popup)
        sidBox:SetSize(192, 28)
        sidBox:SetPoint("TOPLEFT", sidLbl, "BOTTOMLEFT", 0, -4)
        sidBox:SetAutoFocus(false)
        sidBox:SetNumeric(true)
        sidBox:SetMaxLetters(7)
        sidBox:SetFont(FONT, 13, "")
        sidBox:SetTextColor(1, 1, 1, 0.9)
        sidBox:SetJustifyH("LEFT")
        sidBox:SetTextInsets(6, 6, 0, 0)
        local sidBg = sidBox:CreateTexture(nil, "BACKGROUND")
        sidBg:SetAllPoints(); sidBg:SetColorTexture(0.04, 0.06, 0.08, 1)
        EllesmereUI.MakeBorder(sidBox, 1, 1, 1, 0.12, PP)
        popup._sidBox = sidBox

        local status = popup:CreateFontString(nil, "OVERLAY")
        status:SetFont(FONT, 11, "")
        status:SetPoint("TOP", sidBox, "BOTTOM", 0, -8)
        status:SetTextColor(1, 0.3, 0.3, 1)
        popup._status = status

        local ar, ag, ab = EllesmereUI.GetAccentColor()
        local addBtn = CreateFrame("Button", nil, popup)
        addBtn:SetSize(80, 26)
        addBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 16)
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints(); addBg:SetColorTexture(ar, ag, ab, 0.15)
        EllesmereUI.MakeBorder(addBtn, ar, ag, ab, 0.4, PP)
        local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
        addLbl:SetFont(FONT, 12, "")
        addLbl:SetPoint("CENTER")
        addLbl:SetTextColor(ar, ag, ab, 1)
        addLbl:SetText(EllesmereUI.L("Add"))

        local function TryAdd()
            local id = tonumber(sidBox:GetText())
            if not id or id <= 0 then
                popup._status:SetText(EllesmereUI.L("Enter a valid spell ID"))
                return
            end
            sidBox:SetText("")
            dimmer:Hide()
            if popup._onAdded then popup._onAdded(id) end
        end
        addBtn:SetScript("OnClick", TryAdd)
        sidBox:SetScript("OnEnterPressed", TryAdd)
        sidBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        dimmer:SetScript("OnMouseDown", function(self)
            if not popup:IsMouseOver() then self:Hide() end
        end)

        popup._dimmer = dimmer
        addSpellPopup = popup
    end

    addSpellPopup._status:SetText("")
    addSpellPopup._sidBox:SetText("")
    addSpellPopup._onAdded = onAdded
    addSpellPopup._dimmer:Show()
    addSpellPopup._sidBox:SetFocus()
end

-------------------------------------------------------------------------------
--  Page builder
-------------------------------------------------------------------------------
local function BuildMovementAlertPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local FONT = EllesmereUI._font or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"
    local EG = EllesmereUI.ELLESMERE_GREEN or { r = 0.05, g = 0.82, b = 0.62 }
    local ma = MA()
    if not ma then return 0 end
    local y = yOffset
    local _, h

    parent._showRowDivider = true

    _, h = W:Spacer(parent, y, 12);  y = y - h

    -------------------------------------------------------------------------
    --  MOVEMENT COOLDOWN ALERT
    -------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "MOVEMENT COOLDOWN ALERT", y);  y = y - h

    local function maOff() return not ma.enabled end

    local moveRow
    moveRow, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Movement Cooldown Alert",
          tooltip="Shows your class mobility spell(s) counting down on cooldown. Use Unlock Mode to reposition/resize.",
          getValue=function() return ma.enabled == true end,
          setValue=function(v)
              ma.enabled = v
              if EllesmereUI._UpdateMovementAlertEvents then EllesmereUI._UpdateMovementAlertEvents() end
              Refresh()
              EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Combat Only",
          tooltip="Only show the alert while in combat.",
          disabled=maOff, disabledTooltip="Enable Movement Cooldown Alert first", rawTooltip=true,
          getValue=function() return ma.combatOnly == true end,
          setValue=function(v) ma.combatOnly = v; Refresh() end }
    );  y = y - h

    -- Cog on the master toggle: display mode, sizing, color, poll rate, format
    do
        local leftRgn = moveRow._leftRegion
        local values, order = DISPLAY_MODE_VALUES, DISPLAY_MODE_ORDER
        local sndValues, sndOrder = SoundDropdownValues()
        local ttsValues, ttsOrder = TTSVoiceDropdownValues()
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Movement Cooldown Alert Settings",
            minWidth = 300,
            rows = {
                { type="dropdown", label="Display Mode", values=values, order=order,
                  get=function() return ma.displayMode or "text" end,
                  set=function(v) ma.displayMode = v; Refresh() end },
                { type="slider", label="Text Size", min=10, max=72, step=1,
                  get=function() return ma.textSize or 24 end,
                  set=function(v) ma.textSize = v; Refresh() end },
                { type="slider", label="Poll Rate (ms)", min=50, max=500, step=50,
                  get=function() return ma.pollRate or 100 end,
                  set=function(v) ma.pollRate = v end },
                { type="slider", label="Decimal Precision", min=0, max=2, step=1,
                  get=function() return ma.precision or 1 end,
                  set=function(v) ma.precision = v end },
                { type="input", label="Text Format",
                  disabled=function() return ma.displayMode == "icon" end,
                  get=function() return ma.textFormat or "%t\\nNo %a" end,
                  set=function(v) ma.textFormat = v; Refresh() end },
                { type="colorpicker", label="Text Color",
                  disabled=function() return ma.textColorUseClass end,
                  disabledTooltip="Disable Class Color to pick a custom color.",
                  get=function() return ma.textColorR or 1, ma.textColorG or 1, ma.textColorB or 1 end,
                  set=function(r, g, b) ma.textColorR, ma.textColorG, ma.textColorB = r, g, b; Refresh() end },
                { type="toggle", label="Use Class Color",
                  get=function() return ma.textColorUseClass == true end,
                  set=function(v) ma.textColorUseClass = v; Refresh() end },
                { type="toggle", label="Show Icon on Bar",
                  disabled=function() return ma.displayMode ~= "bar" end,
                  get=function() return ma.barShowIcon ~= false end,
                  set=function(v) ma.barShowIcon = v; Refresh() end },
                { type="dropdown", label="Sound", values=sndValues, order=sndOrder,
                  disabled=function() return ma.maTtsEnabled == true end,
                  disabledTooltip="Text-to-Speech is enabled below and takes priority over Sound.", rawTooltip=true,
                  get=function() return ma.maSoundKey or "none" end,
                  set=function(v) ma.maSoundKey = v end },
                { type="toggle", label="Use Text-to-Speech",
                  tooltip="Speaks once, right when a tracked spell comes off cooldown -- not a running countdown.",
                  get=function() return ma.maTtsEnabled == true end,
                  set=function(v) ma.maTtsEnabled = v end },
                { type="dropdown", label="TTS Voice", values=ttsValues, order=ttsOrder,
                  disabled=function() return not ma.maTtsEnabled end,
                  disabledTooltip="Enable Text-to-Speech first", rawTooltip=true,
                  get=function() return ma.maTtsVoiceID or 0 end,
                  set=function(v) ma.maTtsVoiceID = v end },
                { type="input", label="TTS Message (%a = ability name)", inputWidth=110,
                  disabled=function() return not ma.maTtsEnabled end,
                  disabledTooltip="Enable Text-to-Speech first", rawTooltip=true,
                  get=function() return ma.maTtsMessage or "%a ready" end,
                  set=function(v) ma.maTtsMessage = v end },
                { type="slider", label="TTS Volume", min=0, max=100, step=5,
                  disabled=function() return not ma.maTtsEnabled end,
                  get=function() return ma.maTtsVolume or 100 end,
                  set=function(v) ma.maTtsVolume = v end },
            },
            footer = { unlockKey = "EUI_MovementAlert" },
        })
        local cogBtn = CreateFrame("Button", nil, leftRgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
        leftRgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(maOff() and 0.15 or 0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(maOff() and 0.15 or 0.4) end)
        cogBtn:SetScript("OnClick", function(self) cogShow(self) end)

        local cogBlock = CreateFrame("Frame", nil, cogBtn)
        cogBlock:SetAllPoints()
        cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10)
        cogBlock:EnableMouse(true)
        cogBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Movement Cooldown Alert"))
        end)
        cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = maOff()
            cogBtn:SetAlpha(off and 0.15 or 0.4)
            if off then cogBlock:Show() else cogBlock:Hide() end
        end)
        if maOff() then cogBlock:Show() else cogBlock:Hide() end
    end

    -- Class filter grid (3 columns)
    do
        local hdrFS = parent:CreateFontString(nil, "OVERLAY")
        hdrFS:SetFont(FONT, 13, "")
        hdrFS:SetTextColor(1, 1, 1, 0.55)
        hdrFS:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, y - 8)
        hdrFS:SetText(EllesmereUI.L("Track on these classes:"))
        EllesmereUI.RegisterWidgetRefresh(function() hdrFS:SetAlpha(maOff() and 0.3 or 1) end)
        hdrFS:SetAlpha(maOff() and 0.3 or 1)
        y = y - 26

        if not ma.disabledClasses then ma.disabledClasses = {} end
        for i = 1, #CLASS_ORDER, 3 do
            local c1, c2, c3 = CLASS_ORDER[i], CLASS_ORDER[i + 1], CLASS_ORDER[i + 2]
            local function ClassCfg(classToken)
                if not classToken then return nil end
                local classColor = C_ClassColor.GetClassColor(classToken)
                local localizedName = LOCALIZED_CLASS_NAMES_MALE[classToken] or classToken
                local coloredName = classColor and classColor:WrapTextInColorCode(localizedName) or localizedName
                return { type="toggle", text=coloredName, disabled=maOff,
                    getValue=function() return not ma.disabledClasses[classToken] end,
                    setValue=function(v)
                        if v then ma.disabledClasses[classToken] = nil else ma.disabledClasses[classToken] = true end
                        Refresh()
                    end }
            end
            _, h = W:TripleRow(parent, y, ClassCfg(c1), ClassCfg(c2), ClassCfg(c3));  y = y - h
        end
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h

    -------------------------------------------------------------------------
    --  TRACKED SPELLS
    -------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "TRACKED SPELLS", y);  y = y - h
    y = y - 6

    do
        local playerClass = select(2, UnitClass("player"))
        local classAbilities = EllesmereUI.MOVEMENT_ABILITIES and EllesmereUI.MOVEMENT_ABILITIES[playerClass]
        local spells, seen = {}, {}
        if classAbilities then
            for key, value in pairs(classAbilities) do
                if type(key) == "number" and type(value) == "table" then
                    for _, spellId in ipairs(value) do
                        if not seen[spellId] then
                            seen[spellId] = true
                            spells[#spells + 1] = { spellId = spellId, isDefault = true }
                        end
                    end
                end
            end
        end
        for spellId, override in pairs(ma.spellOverrides or {}) do
            if not seen[spellId] and override.class == playerClass then
                seen[spellId] = true
                spells[#spells + 1] = { spellId = spellId, isDefault = false }
            end
        end

        local ROW_H = 34
        local ROW_W = parent:GetWidth() - 68

        if #spells == 0 then
            local txt = parent:CreateFontString(nil, "OVERLAY")
            txt:SetFont(FONT, 12, "")
            txt:SetTextColor(1, 1, 1, 0.4)
            txt:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, y)
            txt:SetText(EllesmereUI.L("No mobility spells known for your current spec yet -- add one below."))
            y = y - 24
        else
            for _, spellData in ipairs(spells) do
                local spellId = spellData.spellId
                local spellInfo = C_Spell and C_Spell.GetSpellInfo(spellId)
                local spellName = (spellInfo and spellInfo.name) or ("Spell " .. spellId)
                local spellIcon = spellInfo and spellInfo.iconID
                local override = ma.spellOverrides[spellId]
                local isEnabled = not override or override.enabled ~= false
                local customText = (override and override.customText) or ""

                local row = CreateFrame("Frame", nil, parent)
                row:SetSize(ROW_W, ROW_H)
                row:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, y)
                local rowBg = row:CreateTexture(nil, "BACKGROUND")
                rowBg:SetAllPoints(); rowBg:SetColorTexture(1, 1, 1, 0.03)

                if spellIcon then
                    local icon = row:CreateTexture(nil, "ARTWORK")
                    icon:SetSize(22, 22)
                    icon:SetPoint("LEFT", 4, 0)
                    icon:SetTexture(spellIcon)
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end

                -- Enabled checkbox
                local box = CreateFrame("Button", nil, row)
                box:SetSize(16, 16)
                box:SetPoint("LEFT", 32, 0)
                local boxBg = box:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints(); boxBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                local boxBorder = EllesmereUI.MakeBorder(box, 0.4, 0.4, 0.4, 0.6, PP)
                local check = box:CreateTexture(nil, "ARTWORK")
                check:SetPoint("TOPLEFT", 3, -3); check:SetPoint("BOTTOMRIGHT", -3, 3)
                check:SetColorTexture(EG.r, EG.g, EG.b, 1)
                check:SetShown(isEnabled)

                local nameFS = row:CreateFontString(nil, "OVERLAY")
                nameFS:SetFont(FONT, 12, "")
                nameFS:SetTextColor(1, 1, 1, 0.85)
                nameFS:SetPoint("LEFT", box, "RIGHT", 8, 0)
                nameFS:SetWidth(150)
                nameFS:SetJustifyH("LEFT")
                nameFS:SetText(spellName .. "  |cff888888(" .. spellId .. ")|r")

                box:SetScript("OnClick", function()
                    ma.spellOverrides[spellId] = ma.spellOverrides[spellId] or {}
                    isEnabled = not isEnabled
                    ma.spellOverrides[spellId].enabled = isEnabled
                    check:SetShown(isEnabled)
                    if EllesmereUI._RebuildMovementSpellLookup then EllesmereUI._RebuildMovementSpellLookup() end
                    if EllesmereUI._CacheMovementSpells then EllesmereUI._CacheMovementSpells() end
                    Refresh()
                end)

                -- Custom text input
                local ctBox = CreateFrame("EditBox", nil, row)
                ctBox:SetSize(150, 22)
                ctBox:SetPoint("LEFT", nameFS, "RIGHT", 10, 0)
                ctBox:SetAutoFocus(false)
                ctBox:SetMaxLetters(40)
                ctBox:SetFont(FONT, 11, "")
                ctBox:SetTextColor(1, 1, 1, 0.9)
                ctBox:SetJustifyH("LEFT")
                ctBox:SetTextInsets(6, 6, 0, 0)
                local ctBg = ctBox:CreateTexture(nil, "BACKGROUND")
                ctBg:SetAllPoints(); ctBg:SetColorTexture(0.04, 0.06, 0.08, 1)
                EllesmereUI.MakeBorder(ctBox, 1, 1, 1, 0.12, PP)
                ctBox:SetText(customText)
                local function CommitCustomText(self)
                    ma.spellOverrides[spellId] = ma.spellOverrides[spellId] or {}
                    local txt = self:GetText()
                    ma.spellOverrides[spellId].customText = (txt ~= "") and txt or nil
                    if EllesmereUI._CacheMovementSpells then EllesmereUI._CacheMovementSpells() end
                    Refresh()
                end
                ctBox:SetScript("OnEnterPressed", function(self) CommitCustomText(self); self:ClearFocus() end)
                ctBox:SetScript("OnEditFocusLost", CommitCustomText)
                ctBox:SetScript("OnEscapePressed", function(self) self:SetText(customText); self:ClearFocus() end)

                if not spellData.isDefault then
                    local removeBtn = CreateFrame("Button", nil, row)
                    removeBtn:SetSize(16, 16)
                    removeBtn:SetPoint("LEFT", ctBox, "RIGHT", 8, 0)
                    local rmBg = removeBtn:CreateTexture(nil, "BACKGROUND")
                    rmBg:SetAllPoints(); rmBg:SetColorTexture(0.6, 0.1, 0.1, 0.8)
                    EllesmereUI.MakeBorder(removeBtn, 0.8, 0.2, 0.2, 1, PP)
                    local xTex = removeBtn:CreateFontString(nil, "OVERLAY")
                    xTex:SetFont(FONT, 11, "")
                    xTex:SetPoint("CENTER"); xTex:SetText("X"); xTex:SetTextColor(1, 1, 1)
                    removeBtn:SetScript("OnClick", function()
                        ma.spellOverrides[spellId] = nil
                        if EllesmereUI._RebuildMovementSpellLookup then EllesmereUI._RebuildMovementSpellLookup() end
                        if EllesmereUI._CacheMovementSpells then EllesmereUI._CacheMovementSpells() end
                        Refresh()
                        EllesmereUI:RefreshPage(true)
                    end)
                end

                y = y - (ROW_H + 3)
            end
        end

        -- Add-by-ID button
        local ar, ag, ab = EllesmereUI.GetAccentColor()
        local addBtn = CreateFrame("Button", nil, parent)
        addBtn:SetSize(110, 24)
        addBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, y - 4)
        local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
        addBg:SetAllPoints(); addBg:SetColorTexture(ar, ag, ab, 0.12)
        EllesmereUI.MakeBorder(addBtn, ar, ag, ab, 0.35, PP)
        local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
        addLbl:SetFont(FONT, 12, "")
        addLbl:SetPoint("CENTER")
        addLbl:SetTextColor(ar, ag, ab, 1)
        addLbl:SetText(EllesmereUI.L("+ Add Spell"))
        addBtn:SetScript("OnClick", function()
            ShowAddSpellPopup(function(spellId)
                ma.spellOverrides[spellId] = ma.spellOverrides[spellId] or { enabled = true, class = playerClass }
                if EllesmereUI._RebuildMovementSpellLookup then EllesmereUI._RebuildMovementSpellLookup() end
                if EllesmereUI._CacheMovementSpells then EllesmereUI._CacheMovementSpells() end
                Refresh()
                EllesmereUI:RefreshPage(true)
            end)
        end)
        y = y - 34
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h

    -------------------------------------------------------------------------
    --  TIME SPIRAL
    -------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "TIME SPIRAL", y);  y = y - h

    local function tsOff() return not ma.tsEnabled end

    local tsRow
    tsRow, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Time Spiral Tracker",
          tooltip="Flashes a banner whenever a tracked mobility spell's cooldown is proc-reset. Use Unlock Mode to reposition/resize.",
          getValue=function() return ma.tsEnabled == true end,
          setValue=function(v)
              ma.tsEnabled = v
              if EllesmereUI._UpdateMovementAlertEvents then EllesmereUI._UpdateMovementAlertEvents() end
              Refresh()
              EllesmereUI:RefreshPage()
          end },
        { type="label", text="" }
    );  y = y - h

    do
        local leftRgn = tsRow._leftRegion
        local sndValues, sndOrder = SoundDropdownValues()
        local ttsValues, ttsOrder = TTSVoiceDropdownValues()
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Time Spiral Settings",
            minWidth = 300,
            rows = {
                { type="input", label="Text Format",
                  get=function() return ma.tsTextFormat or "FREE MOVEMENT\\n%.1f" end,
                  set=function(v) ma.tsTextFormat = v; Refresh() end },
                { type="colorpicker", label="Color",
                  disabled=function() return ma.tsColorUseClass end,
                  disabledTooltip="Disable Class Color to pick a custom color.",
                  get=function() return ma.tsColorR or 0.53, ma.tsColorG or 1, ma.tsColorB or 0 end,
                  set=function(r, g, b) ma.tsColorR, ma.tsColorG, ma.tsColorB = r, g, b; Refresh() end },
                { type="toggle", label="Use Class Color",
                  get=function() return ma.tsColorUseClass == true end,
                  set=function(v) ma.tsColorUseClass = v; Refresh() end },
                { type="dropdown", label="Sound", values=sndValues, order=sndOrder,
                  disabled=function() return ma.tsTtsEnabled == true end,
                  disabledTooltip="Text-to-Speech is enabled below and takes priority over Sound.", rawTooltip=true,
                  get=function() return ma.tsSoundKey or "none" end,
                  set=function(v) ma.tsSoundKey = v end },
                { type="toggle", label="Use Text-to-Speech",
                  get=function() return ma.tsTtsEnabled == true end,
                  set=function(v) ma.tsTtsEnabled = v end },
                { type="dropdown", label="TTS Voice", values=ttsValues, order=ttsOrder,
                  disabled=function() return not ma.tsTtsEnabled end,
                  disabledTooltip="Enable Text-to-Speech first", rawTooltip=true,
                  get=function() return ma.tsTtsVoiceID or 0 end,
                  set=function(v) ma.tsTtsVoiceID = v end },
                { type="input", label="TTS Message",
                  disabled=function() return not ma.tsTtsEnabled end,
                  disabledTooltip="Enable Text-to-Speech first", rawTooltip=true,
                  get=function() return ma.tsTtsMessage or "Free movement" end,
                  set=function(v) ma.tsTtsMessage = v end },
                { type="slider", label="TTS Volume", min=0, max=100, step=5,
                  disabled=function() return not ma.tsTtsEnabled end,
                  get=function() return ma.tsTtsVolume or 100 end,
                  set=function(v) ma.tsTtsVolume = v end },
            },
            footer = { unlockKey = "EUI_TimeSpiralAlert" },
        })
        local cogBtn = CreateFrame("Button", nil, leftRgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
        leftRgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(tsOff() and 0.15 or 0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(tsOff() and 0.15 or 0.4) end)
        cogBtn:SetScript("OnClick", function(self) cogShow(self) end)

        local cogBlock = CreateFrame("Frame", nil, cogBtn)
        cogBlock:SetAllPoints()
        cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10)
        cogBlock:EnableMouse(true)
        cogBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Time Spiral Tracker"))
        end)
        cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = tsOff()
            cogBtn:SetAlpha(off and 0.15 or 0.4)
            if off then cogBlock:Show() else cogBlock:Hide() end
        end)
        if tsOff() then cogBlock:Show() else cogBlock:Hide() end
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h

    -------------------------------------------------------------------------
    --  GATEWAY SHARD
    -------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "GATEWAY SHARD", y);  y = y - h

    local function gwOff() return not ma.gwEnabled end

    local gwRow
    gwRow, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Gateway Shard Alert",
          tooltip="Warlock only. Alerts when your Gateway Control Shard is usable. Use Unlock Mode to reposition/resize.",
          getValue=function() return ma.gwEnabled == true end,
          setValue=function(v)
              ma.gwEnabled = v
              if EllesmereUI._UpdateMovementAlertEvents then EllesmereUI._UpdateMovementAlertEvents() end
              Refresh()
              EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Combat Only",
          tooltip="Only show the alert while in combat.",
          disabled=gwOff, disabledTooltip="Enable Gateway Shard Alert first", rawTooltip=true,
          getValue=function() return ma.gwCombatOnly == true end,
          setValue=function(v) ma.gwCombatOnly = v; Refresh() end }
    );  y = y - h

    do
        local leftRgn = gwRow._leftRegion
        local sndValues, sndOrder = SoundDropdownValues()
        local ttsValues, ttsOrder = TTSVoiceDropdownValues()
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Gateway Shard Settings",
            minWidth = 300,
            rows = {
                { type="input", label="Text",
                  get=function() return ma.gwText or "GATEWAY READY" end,
                  set=function(v) ma.gwText = v; Refresh() end },
                { type="colorpicker", label="Color",
                  disabled=function() return ma.gwColorUseClass end,
                  disabledTooltip="Disable Class Color to pick a custom color.",
                  get=function() return ma.gwColorR or 0.7, ma.gwColorG or 0, ma.gwColorB or 1 end,
                  set=function(r, g, b) ma.gwColorR, ma.gwColorG, ma.gwColorB = r, g, b; Refresh() end },
                { type="toggle", label="Use Class Color",
                  get=function() return ma.gwColorUseClass == true end,
                  set=function(v) ma.gwColorUseClass = v; Refresh() end },
                { type="dropdown", label="Sound", values=sndValues, order=sndOrder,
                  disabled=function() return ma.gwTtsEnabled == true end,
                  disabledTooltip="Text-to-Speech is enabled below and takes priority over Sound.", rawTooltip=true,
                  get=function() return ma.gwSoundKey or "none" end,
                  set=function(v) ma.gwSoundKey = v end },
                { type="toggle", label="Use Text-to-Speech",
                  get=function() return ma.gwTtsEnabled == true end,
                  set=function(v) ma.gwTtsEnabled = v end },
                { type="dropdown", label="TTS Voice", values=ttsValues, order=ttsOrder,
                  disabled=function() return not ma.gwTtsEnabled end,
                  disabledTooltip="Enable Text-to-Speech first", rawTooltip=true,
                  get=function() return ma.gwTtsVoiceID or 0 end,
                  set=function(v) ma.gwTtsVoiceID = v end },
                { type="input", label="TTS Message",
                  disabled=function() return not ma.gwTtsEnabled end,
                  disabledTooltip="Enable Text-to-Speech first", rawTooltip=true,
                  get=function() return ma.gwTtsMessage or "Gateway ready" end,
                  set=function(v) ma.gwTtsMessage = v end },
                { type="slider", label="TTS Volume", min=0, max=100, step=5,
                  disabled=function() return not ma.gwTtsEnabled end,
                  get=function() return ma.gwTtsVolume or 100 end,
                  set=function(v) ma.gwTtsVolume = v end },
            },
            footer = { unlockKey = "EUI_GatewayShardAlert" },
        })
        local cogBtn = CreateFrame("Button", nil, leftRgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
        leftRgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(gwOff() and 0.15 or 0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(gwOff() and 0.15 or 0.4) end)
        cogBtn:SetScript("OnClick", function(self) cogShow(self) end)

        local cogBlock = CreateFrame("Frame", nil, cogBtn)
        cogBlock:SetAllPoints()
        cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10)
        cogBlock:EnableMouse(true)
        cogBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Enable Gateway Shard Alert"))
        end)
        cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = gwOff()
            cogBtn:SetAlpha(off and 0.15 or 0.4)
            if off then cogBlock:Show() else cogBlock:Hide() end
        end)
        if gwOff() then cogBlock:Show() else cogBlock:Hide() end
    end

    _, h = W:Spacer(parent, y, 20);  y = y - h

    return math.abs(y)
end

_G._EUI_BuildMovementAlertPage = BuildMovementAlertPage
