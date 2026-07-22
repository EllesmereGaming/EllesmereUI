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

-- The legacy stored "text" value displays and renders as text_dn (its old
-- duration-first default format) -- no migration, the getter maps it.
local DISPLAY_MODE_VALUES = {
    text_nd = "Text: Name Duration",
    text_dn = "Text: Duration Name",
    icon    = "Icon",
    bar     = "Bar",
}
local DISPLAY_MODE_ORDER  = { "text_nd", "text_dn", "icon", "bar" }

-- One-shot guard: the options-close hook that kills the movement preview is
-- registered on first page build, never per rebuild.
local _previewOnHideRegistered = false

local CLASS_ORDER = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER",
    "MAGE", "MONK", "PALADIN", "PRIEST", "ROGUE",
    "SHAMAN", "WARLOCK", "WARRIOR",
}

-- Preset tracked spells for the checkbox grid: the castable mobility ids the
-- tracker (EllesmereUIQoL_MovementAlert.lua MOVEMENT_ABILITIES) actually
-- polls, across ALL classes/specs, curated against the raid-frame Buff
-- Manager movement filter (EllesmereUIRaidFrames\EUI_RaidFrames_BuffManager2.lua,
-- DEFAULT_FILTER_SPELLS.movement) for class coverage and alternate ids --
-- keep the three tables in sync when mobility spells change. ids[1] is the
-- primary (label + checkbox state source); the rest are CASTABLE variant ids
-- the tracker also polls (talent replacements, form casts) whose override
-- state follows the primary's checkbox -- never aura-only ids, which the
-- tracker cannot poll. Ids are never displayed; names resolve live via
-- GetSpellInfo.
local MOVEMENT_PRESETS = {
    { class = "DEATHKNIGHT", ids = { 48265 } },            -- Death's Advance
    { class = "DEATHKNIGHT", ids = { 212552 } },           -- Wraith Walk
    { class = "DEATHKNIGHT", ids = { 444347, 444010 } },   -- Death Charge (both ids share the name)
    { class = "DEMONHUNTER", ids = { 195072 } },           -- Fel Rush
    { class = "DEMONHUNTER", ids = { 189110 } },           -- Infernal Strike
    { class = "DEMONHUNTER", ids = { 1234796 } },
    { class = "DRUID", ids = { 102401, 102417 } },         -- Wild Charge
    { class = "DRUID", ids = { 1850 } },                   -- Dash
    { class = "DRUID", ids = { 252216 } },                 -- Tiger Dash
    { class = "DRUID", ids = { 106898, 77761, 77764 } },   -- Stampeding Roar (base + bear/cat form casts)
    { class = "EVOKER", ids = { 358267 } },                -- Hover
    { class = "HUNTER", ids = { 186257 } },                -- Aspect of the Cheetah
    { class = "HUNTER", ids = { 781 } },                   -- Disengage
    { class = "MAGE", ids = { 1953, 212653 } },            -- Blink / Shimmer
    { class = "MONK", ids = { 109132, 115008 } },          -- Roll / Chi Torpedo
    { class = "MONK", ids = { 119085 } },
    { class = "MONK", ids = { 361138 } },
    { class = "MONK", ids = { 101545 } },                  -- Flying Serpent Kick
    { class = "PALADIN", ids = { 190784 } },               -- Divine Steed
    { class = "PRIEST", ids = { 121536 } },                -- Angelic Feather
    { class = "PRIEST", ids = { 73325 } },                 -- Leap of Faith
    { class = "ROGUE", ids = { 2983 } },                   -- Sprint
    { class = "ROGUE", ids = { 36554 } },                  -- Shadowstep
    { class = "ROGUE", ids = { 195457 } },                 -- Grappling Hook
    { class = "SHAMAN", ids = { 79206 } },                 -- Spiritwalker's Grace
    { class = "SHAMAN", ids = { 192063 } },                -- Gust of Wind
    { class = "SHAMAN", ids = { 58875, 90328 } },          -- Spirit Walk
    { class = "WARLOCK", ids = { 48020 } },                -- Demonic Circle: Teleport
    { class = "WARRIOR", ids = { 6544 } },                 -- Heroic Leap
}

-- Set of every preset id (all variants): any other id in ma.spellOverrides
-- is a user-added custom spell and gets its own deletable grid cell.
local MOVEMENT_PRESET_IDS = {}
for _, e in ipairs(MOVEMENT_PRESETS) do
    for _, id in ipairs(e.ids) do MOVEMENT_PRESET_IDS[id] = true end
end

-- Presets that default to unchecked (backend-owned set, shared so the grid
-- and the tracker read the same truth).
local MOVEMENT_DEFAULT_OFF = EllesmereUI._MovementDefaultOff or {}

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
--  "Custom Text" popup -- right-click on a tracked-spell grid cell. Sets the
--  text the Movement Cooldown Alert shows for that spell instead of the
--  ability name; empty text restores the ability name. Same styling as the
--  Add Spell popup above.
-------------------------------------------------------------------------------
local customTextPopup
local function ShowCustomTextPopup(titleText, initial, onSave)
    local PP = EllesmereUI.PanelPP
    local FONT = EllesmereUI._font or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"

    if not customTextPopup then
        local dimmer = CreateFrame("Frame", nil, UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:Hide()
        local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
        dimTex:SetAllPoints(); dimTex:SetColorTexture(0, 0, 0, 0.25)

        local popup = CreateFrame("Frame", nil, dimmer)
        popup:SetSize(260, 150)
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
        popup._title = title

        local lbl = popup:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(FONT, 11, "")
        lbl:SetPoint("TOPLEFT", popup, "TOPLEFT", 24, -52)
        lbl:SetTextColor(0.7, 0.7, 0.7, 1)
        lbl:SetText(EllesmereUI.L("Custom Alert Text (empty = ability name)"))

        local box = CreateFrame("EditBox", nil, popup)
        box:SetSize(212, 28)
        box:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", 0, -4)
        box:SetAutoFocus(false)
        box:SetMaxLetters(40)
        box:SetFont(FONT, 13, "")
        box:SetTextColor(1, 1, 1, 0.9)
        box:SetJustifyH("LEFT")
        box:SetTextInsets(6, 6, 0, 0)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints(); boxBg:SetColorTexture(0.04, 0.06, 0.08, 1)
        EllesmereUI.MakeBorder(box, 1, 1, 1, 0.12, PP)
        popup._box = box

        local ar, ag, ab = EllesmereUI.GetAccentColor()
        local saveBtn = CreateFrame("Button", nil, popup)
        saveBtn:SetSize(80, 26)
        saveBtn:SetPoint("BOTTOM", popup, "BOTTOM", 0, 16)
        local saveBg = saveBtn:CreateTexture(nil, "BACKGROUND")
        saveBg:SetAllPoints(); saveBg:SetColorTexture(ar, ag, ab, 0.15)
        EllesmereUI.MakeBorder(saveBtn, ar, ag, ab, 0.4, PP)
        local saveLbl = saveBtn:CreateFontString(nil, "OVERLAY")
        saveLbl:SetFont(FONT, 12, "")
        saveLbl:SetPoint("CENTER")
        saveLbl:SetTextColor(ar, ag, ab, 1)
        saveLbl:SetText(EllesmereUI.L("Save"))

        local function Commit()
            dimmer:Hide()
            if popup._onSave then popup._onSave(popup._box:GetText() or "") end
        end
        saveBtn:SetScript("OnClick", Commit)
        box:SetScript("OnEnterPressed", Commit)
        box:SetScript("OnEscapePressed", function() dimmer:Hide() end)

        dimmer:SetScript("OnMouseDown", function(self)
            if not popup:IsMouseOver() then self:Hide() end
        end)

        popup._dimmer = dimmer
        customTextPopup = popup
    end

    customTextPopup._title:SetText(titleText or "")
    customTextPopup._box:SetText(initial or "")
    customTextPopup._onSave = onSave
    customTextPopup._dimmer:Show()
    customTextPopup._box:SetFocus()
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

    -- Activate / Deactivate Movement Preview -- centered wide button matching
    -- the Boss Frames preview button. Loops a fake cooldown through the real
    -- display path using all current settings; the backend self-terminates it
    -- on window close or page/module change (plus the OnHide hook below).
    local previewBtnLbl
    local function PreviewLabel()
        return (EllesmereUI._MovementAlertPreviewActive and EllesmereUI._MovementAlertPreviewActive())
            and EllesmereUI.L("Deactivate Movement Preview")
            or EllesmereUI.L("Activate Movement Preview")
    end
    local previewBtnFrame
    previewBtnFrame, h = W:WideButton(parent, PreviewLabel(), y, function()
        if not EllesmereUI._MovementAlertPreview then return end
        EllesmereUI._MovementAlertPreview(not EllesmereUI._MovementAlertPreviewActive())
        if previewBtnLbl then previewBtnLbl:SetText(PreviewLabel()) end
    end);  y = y - h
    do
        local btn = select(1, previewBtnFrame:GetChildren())
        if btn then
            for i = 1, btn:GetNumRegions() do
                local rgn = select(i, btn:GetRegions())
                if rgn and rgn.GetText and rgn:GetText() then previewBtnLbl = rgn; break end
            end
        end
        -- Keep the label truthful if the preview self-terminated meanwhile.
        EllesmereUI.RegisterWidgetRefresh(function()
            if previewBtnLbl then previewBtnLbl:SetText(PreviewLabel()) end
        end)
    end
    if not _previewOnHideRegistered and EllesmereUI.RegisterOnHide then
        _previewOnHideRegistered = true
        EllesmereUI:RegisterOnHide(function()
            if EllesmereUI._MovementAlertPreview and EllesmereUI._MovementAlertPreviewActive
                and EllesmereUI._MovementAlertPreviewActive() then
                EllesmereUI._MovementAlertPreview(false)
            end
        end)
    end

    _, h = W:Spacer(parent, y, 8);  y = y - h

    -------------------------------------------------------------------------
    --  MOVEMENT COOLDOWN ALERT
    -------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "MOVEMENT COOLDOWN ALERT", y);  y = y - h

    -- Off = no class checked at all (enabledClasses nil), the Totem Bar
    -- convention -- the page stays configurable while ANY class is checked;
    -- the backend additionally gates runtime on the player's own class.
    local function maOff() return not ma.enabledClasses end

    local enableRow
    enableRow, h = W:DualRow(parent, y,
        { type="label", text="Enable Movement Alerts",
          tooltip="Shows the checked classes' mobility spell(s) counting down on cooldown. Nothing checked = feature disabled. Use Unlock Mode to reposition/resize." },
        { type="toggle", text="Combat Only",
          tooltip="Only show the alert while in combat.",
          disabled=maOff, disabledTooltip="Select a class above", rawTooltip=true,
          getValue=function() return ma.combatOnly == true end,
          setValue=function(v) ma.combatOnly = v; Refresh() end }
    );  y = y - h

    -- Enabled-classes checkbox dropdown (same widget/storage convention as
    -- the Resource Bars Totem Bar): nothing checked = zero-cost disabled.
    do
        local leftRgn = enableRow._leftRegion
        local classItems = {}
        for _, cf in ipairs(CLASS_ORDER) do
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf]
            local name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cf])
                or (cf:sub(1, 1):upper() .. cf:sub(2):lower())
            local hex = color and color.colorStr or "ffffffff"
            classItems[#classItems + 1] = { key = cf, label = "|c" .. hex .. name .. "|r" }
        end
        local cbDD, cbDDRefresh
        cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            leftRgn, 210, leftRgn:GetFrameLevel() + 2,
            classItems,
            function(key)
                return ma.enabledClasses and ma.enabledClasses[key] or false
            end,
            function(key, v)
                -- Zero classes checked collapses the set back to nil, which
                -- is THE disabled state: the backend's MovementEnabled()
                -- gate drops every event/cache/poll, same as the old master
                -- toggle being off.
                if not ma.enabledClasses then ma.enabledClasses = {} end
                ma.enabledClasses[key] = v or nil
                if not next(ma.enabledClasses) then ma.enabledClasses = nil end
                local ddMenu = cbDD._ddMenu
                if ddMenu then
                    for _, sf in ipairs({ ddMenu:GetChildren() }) do
                        local sc = sf.GetScrollChild and sf:GetScrollChild()
                        if sc then
                            for _, row in ipairs({ sc:GetChildren() }) do
                                if row._updateCheck then row._updateCheck() end
                            end
                        end
                    end
                end
                if EllesmereUI._UpdateMovementAlertEvents then EllesmereUI._UpdateMovementAlertEvents() end
                Refresh()
                EllesmereUI:RefreshPage()
            end, nil, 8, false)
        PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
        leftRgn._control = cbDD
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- Display/alert settings as page rows (moved out of the old cog popup):
    -- every slot keeps the exact profile keys and side-effects the popup rows
    -- had; RefreshPage() is added only where a value gates another widget's
    -- disabled state.
    local sndValues, sndOrder = SoundDropdownValues()
    local ttsValues, ttsOrder = TTSVoiceDropdownValues()

    -- Bar texture dropdown: identical catalog + SharedMedia merge +
    -- texture-preview rows as the CDM Tracking Bars "Bar Texture" dropdown.
    local barTexValues, barTexOrder = {}, {}
    do
        local mt = EllesmereUI._MovementBarTextures
        if mt then
            if EllesmereUI.AppendSharedMediaTextures then
                EllesmereUI.AppendSharedMediaTextures(mt.names, mt.order, nil, mt.lookup)
            end
            for _, key in ipairs(mt.order) do
                if key ~= "---" then barTexValues[key] = mt.names[key] or key end
                barTexOrder[#barTexOrder + 1] = key
            end
            barTexValues._menuOpts = {
                itemHeight = 28,
                background = function(key) return mt.lookup[key] end,
            }
        end
    end
    -- Movement's voice dropdown doubles as the TTS enable: prepend "None"
    -- (the default) to this section's copy of the voice list and skip the
    -- preview icon for it. (Time Spiral/Gateway build their own copies.)
    ttsValues.NONE = "None"
    table.insert(ttsOrder, 1, "NONE")
    do
        local mo = ttsValues._menuOpts
        local origAtlas, origPressed, origClick = mo.iconAtlas, mo.iconPressedAtlas, mo.iconOnClick
        mo.iconAtlas = function(key)
            if key == "NONE" then return nil end
            return origAtlas and origAtlas(key)
        end
        mo.iconPressedAtlas = function(key)
            if key == "NONE" then return nil end
            return origPressed and origPressed(key)
        end
        mo.iconOnClick = function(key)
            if key == "NONE" then return end
            if origClick then origClick(key) end
        end
    end

    -- Text modes come in two fixed arrangements (the old free-form Text
    -- Format input is gone); the legacy stored "text" value maps to the
    -- duration-first arrangement it used to render.
    local function DMIsText()
        local v = ma.displayMode or "text"
        return v == "text" or v == "text_nd" or v == "text_dn"
    end
    local function DMSwatchesDisabled()
        return maOff() or ma.displayMode == "icon"
    end

    local dmRow
    dmRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Display Mode", values=DISPLAY_MODE_VALUES, order=DISPLAY_MODE_ORDER,
          disabled=maOff, disabledTooltip="Select a class above", rawTooltip=true,
          getValue=function()
              local v = ma.displayMode or "text"
              if v == "text" then v = "text_dn" end
              return v
          end,
          setValue=function(v)
              local wasText = DMIsText()
              ma.displayMode = v
              -- Crossing the text <-> bar/icon boundary re-seeds Text Size
              -- to that family's default (text 24, bar/icon 12).
              local isText = (v == "text_nd" or v == "text_dn")
              if wasText ~= isText then ma.textSize = isText and 24 or 12 end
              Refresh(); EllesmereUI:RefreshPage()
          end },
        { type="dropdown", text="Bar Texture", values=barTexValues, order=barTexOrder,
          disabled=function() return maOff() or ma.displayMode ~= "bar" end,
          disabledTooltip="Requires Bar display mode", rawTooltip=true,
          getValue=function() return ma.barTexture or "none" end,
          setValue=function(v) ma.barTexture = v; Refresh() end }
    );  y = y - h

    -- Bar settings cog on the Bar Texture slot: Show Icon on Bar lives here.
    do
        local rgn = dmRow._rightRegion
        local function BarCogOff() return maOff() or ma.displayMode ~= "bar" end
        local _, barCogShow = EllesmereUI.BuildCogPopup({
            title = "Bar Settings",
            rows = {
                { type="toggle", label="Show Icon on Bar",
                  get=function() return ma.barShowIcon ~= false end,
                  set=function(v) ma.barShowIcon = v; Refresh() end },
                { type="toggle", label="Show Duration Text",
                  get=function() return ma.barShowDuration ~= false end,
                  set=function(v) ma.barShowDuration = v; Refresh() end },
            },
        })
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(BarCogOff() and 0.15 or 0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(BarCogOff() and 0.15 or 0.4) end)
        cogBtn:SetScript("OnClick", function(self) barCogShow(self) end)

        local cogBlock = CreateFrame("Frame", nil, cogBtn)
        cogBlock:SetAllPoints()
        cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10)
        cogBlock:EnableMouse(true)
        cogBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Requires Bar display mode"))
        end)
        cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = BarCogOff()
            cogBtn:SetAlpha(off and 0.15 or 0.4)
            if off then cogBlock:Show() else cogBlock:Hide() end
        end)
        if BarCogOff() then cogBlock:Show() else cogBlock:Hide() end
    end

    -- Inline controls on the Display Mode slot, mirroring the Unit Frames
    -- Health Bar Left/Right Text rows: dropdown at the right, then the
    -- Custom + Class color swatch pair, then the resize cog. The swatches
    -- (the Use Class Color replacement) only apply to Text and Bar modes.
    do
        local leftRgn = dmRow._leftRegion
        local dmAnchor = leftRgn._lastInline or leftRgn._control

        -- Class Colored swatch (nearest the control)
        local dmClassSwatch, dmUpdateClassSwatch = EllesmereUI.BuildColorSwatch(
            leftRgn, leftRgn:GetFrameLevel() + 5,
            function()
                local _, classFile = UnitClass("player")
                local cc = classFile and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
                if cc then return cc.r, cc.g, cc.b end
                return 1, 1, 1
            end,
            function() end, nil, 20)
        PP.Point(dmClassSwatch, "RIGHT", dmAnchor, "LEFT", -8, 0)
        dmClassSwatch:SetScript("OnClick", function()
            if DMSwatchesDisabled() then return end
            ma.textColorUseClass = true; Refresh(); EllesmereUI:RefreshPage()
        end)
        dmClassSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(dmClassSwatch, "Class Colored") end)
        dmClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        -- Custom Colored swatch (left of the class swatch): opens the picker;
        -- clicking while class color is active switches back to custom first.
        local dmSwatch, dmUpdateSwatch = EllesmereUI.BuildColorSwatch(
            leftRgn, leftRgn:GetFrameLevel() + 5,
            function() return ma.textColorR or 1, ma.textColorG or 1, ma.textColorB or 1 end,
            function(r, g, b) ma.textColorR, ma.textColorG, ma.textColorB = r, g, b; Refresh() end,
            nil, 20)
        PP.Point(dmSwatch, "RIGHT", dmClassSwatch, "LEFT", -8, 0)
        leftRgn._lastInline = dmSwatch
        local dmOrigClick = dmSwatch:GetScript("OnClick")
        dmSwatch:SetScript("OnClick", function(self, ...)
            if DMSwatchesDisabled() then return end
            if ma.textColorUseClass then
                ma.textColorUseClass = false; Refresh(); EllesmereUI:RefreshPage(); return
            end
            if dmOrigClick then dmOrigClick(self, ...) end
        end)
        dmSwatch:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(dmSwatch, "Custom Colored") end)
        dmSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        local function UpdateDmSwatches()
            local off = DMSwatchesDisabled()
            local isClass = ma.textColorUseClass == true
            dmSwatch:SetAlpha((off or isClass) and 0.3 or 1)
            dmClassSwatch:SetAlpha((isClass and not off) and 1 or 0.3)
        end
        EllesmereUI.RegisterWidgetRefresh(function() dmUpdateSwatch(); dmUpdateClassSwatch(); UpdateDmSwatches() end)
        UpdateDmSwatches()

        -- Resize cog (leftmost): Text Size / Icon Size, each gated to its mode.
        local _, dmCogShow = EllesmereUI.BuildCogPopup({
            title = "Display Size",
            rows = {
                -- Never disabled: sizes the free text, the bar's number, and
                -- the icon's countdown numbers alike. Re-seeded on text <->
                -- bar/icon display mode switches (24 / 12).
                { type="slider", label="Text Size", min=8, max=72, step=1,
                  get=function() return ma.textSize or 24 end,
                  set=function(v) ma.textSize = v; Refresh() end },
                { type="slider", label="Icon Size", min=16, max=128, step=1,
                  disabled=function() return ma.displayMode ~= "icon" end,
                  disabledTooltip="Requires the Icon display mode", rawTooltip=true,
                  get=function() return ma.iconSize or 40 end,
                  set=function(v) ma.iconSize = v; Refresh() end },
                -- View over the old numeric precision key: on = 1 decimal,
                -- off = whole seconds.
                { type="toggle", label="Show Decimal",
                  disabled=function() return ma.displayMode == "icon" end,
                  disabledTooltip="Not used in Icon display mode", rawTooltip=true,
                  get=function() return (ma.precision or 1) > 0 end,
                  set=function(v) ma.precision = v and 1 or 0; Refresh() end },
            },
        })
        local cogBtn = CreateFrame("Button", nil, leftRgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
        leftRgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(maOff() and 0.15 or 0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(maOff() and 0.15 or 0.4) end)
        cogBtn:SetScript("OnClick", function(self) dmCogShow(self) end)

        local cogBlock = CreateFrame("Frame", nil, cogBtn)
        cogBlock:SetAllPoints()
        cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10)
        cogBlock:EnableMouse(true)
        cogBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Select an Enabled Class"))
        end)
        cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = maOff()
            cogBtn:SetAlpha(off and 0.15 or 0.4)
            if off then cogBlock:Show() else cogBlock:Hide() end
        end)
        if maOff() then cogBlock:Show() else cogBlock:Hide() end
    end

    -- TTS Voice doubles as the TTS enable ("None" = off, the default) -- a
    -- view over the old maTtsEnabled/maTtsVoiceID keys. It speaks the
    -- ability name (or its per-spell Custom Text); volume lives in the cog.
    local ttsRow
    ttsRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Sound", values=sndValues, order=sndOrder,
          disabled=function() return maOff() or ma.maTtsEnabled == true end,
          disabledTooltip="Text-to-Speech is enabled and takes priority over Sound.", rawTooltip=true,
          getValue=function() return ma.maSoundKey or "none" end,
          setValue=function(v) ma.maSoundKey = v end },
        { type="dropdown", text="TTS Voice", values=ttsValues, order=ttsOrder,
          tooltip="Speaks the ability name once, right when it comes off cooldown -- not a running countdown. None = no speech.",
          disabled=maOff, disabledTooltip="Select a class above", rawTooltip=true,
          getValue=function()
              if not ma.maTtsEnabled then return "NONE" end
              return ma.maTtsVoiceID or 0
          end,
          setValue=function(v)
              if v == "NONE" then
                  ma.maTtsEnabled = false
              else
                  ma.maTtsEnabled = true
                  ma.maTtsVoiceID = v
              end
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h

    do
        local leftRgn = ttsRow._rightRegion
        local function TtsCogOff() return maOff() or not ma.maTtsEnabled end
        local _, ttsCogShow = EllesmereUI.BuildCogPopup({
            title = "Text-to-Speech Settings",
            rows = {
                { type="slider", label="TTS Volume", min=0, max=100, step=5,
                  get=function() return ma.maTtsVolume or 100 end,
                  set=function(v) ma.maTtsVolume = v end },
            },
        })
        local cogBtn = CreateFrame("Button", nil, leftRgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
        leftRgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(TtsCogOff() and 0.15 or 0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(TtsCogOff() and 0.15 or 0.4) end)
        cogBtn:SetScript("OnClick", function(self) ttsCogShow(self) end)

        local cogBlock = CreateFrame("Frame", nil, cogBtn)
        cogBlock:SetAllPoints()
        cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10)
        cogBlock:EnableMouse(true)
        cogBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Select a TTS Voice"))
        end)
        cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = TtsCogOff()
            cogBtn:SetAlpha(off and 0.15 or 0.4)
            if off then cogBlock:Show() else cogBlock:Hide() end
        end)
        if TtsCogOff() then cogBlock:Show() else cogBlock:Hide() end
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h

    -------------------------------------------------------------------------
    --  TRACKED SPELLS
    -------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "TRACKED SPELLS", y);  y = y - h
    y = y - 6

    -- 4-column checkbox grid (same visual system as the AuraBuffReminders
    -- Auras section): class-colored spell name left, checkbox right, no ids.
    -- Lists every class's mobility spells (not just the player's), then any
    -- user-added spells (deletable via the X icon), then the + Add Spell
    -- button in the next free slot. Adds/removes rebuild the page so cells
    -- always re-flow sequentially with no gaps.
    do
        local GRID_COLS     = 4
        local GRID_ROW_H    = 50
        local GRID_BOX_SZ   = 18
        local GRID_PAD      = EllesmereUI.CONTENT_PAD or 16
        local GRID_SIDE_PAD = 20
        local playerClass = select(2, UnitClass("player"))
        if not ma.spellOverrides then ma.spellOverrides = {} end

        local function GridChanged()
            if EllesmereUI._RebuildMovementSpellLookup then EllesmereUI._RebuildMovementSpellLookup() end
            if EllesmereUI._CacheMovementSpells then EllesmereUI._CacheMovementSpells() end
            Refresh()
        end

        -- Cell list: presets (all classes), then customs, then the add cell.
        local items = {}
        local byClassName = {}
        for _, preset in ipairs(MOVEMENT_PRESETS) do
            local primary = preset.ids[1]
            local info = C_Spell and C_Spell.GetSpellInfo(primary)
            if info and info.name then
                local dupKey = preset.class .. ":" .. info.name
                local existing = byClassName[dupKey]
                if existing then
                    -- Same display name within a class (Blizzard splits some
                    -- abilities across ids): fold into the earlier cell so
                    -- one checkbox governs every id and no name lists twice.
                    for i = 1, #preset.ids do
                        existing.ids[#existing.ids + 1] = preset.ids[i]
                    end
                else
                    -- Copy the id list: folded duplicates append to it, and
                    -- the shared preset table must never be mutated.
                    local cellIds = {}
                    for i = 1, #preset.ids do cellIds[i] = preset.ids[i] end
                    local item = {
                        label = info.name,
                        classToken = preset.class,
                        spellId = primary,
                        ids = cellIds,
                        getVal = function()
                            local o = ma.spellOverrides[primary]
                            if o and o.enabled ~= nil then return o.enabled ~= false end
                            return not MOVEMENT_DEFAULT_OFF[primary]
                        end,
                        setVal = function(v)
                            for i = 1, #cellIds do
                                local id = cellIds[i]
                                ma.spellOverrides[id] = ma.spellOverrides[id] or {}
                                ma.spellOverrides[id].enabled = v
                            end
                        end,
                    }
                    byClassName[dupKey] = item
                    items[#items + 1] = item
                end
            end
        end
        local customIds = {}
        for spellId in pairs(ma.spellOverrides) do
            if type(spellId) == "number" and not MOVEMENT_PRESET_IDS[spellId] then
                customIds[#customIds + 1] = spellId
            end
        end
        table.sort(customIds)
        for _, spellId in ipairs(customIds) do
            local o = ma.spellOverrides[spellId]
            local info = C_Spell and C_Spell.GetSpellInfo(spellId)
            items[#items + 1] = {
                label = (info and info.name) or EllesmereUI.L("Unknown Spell"),
                classToken = o.class,
                spellId = spellId,
                ids = { spellId },
                custom = true,
                getVal = function()
                    local ov = ma.spellOverrides[spellId]
                    return ov ~= nil and ov.enabled ~= false
                end,
                setVal = function(v)
                    local ov = ma.spellOverrides[spellId]
                    if ov then ov.enabled = v end
                end,
            }
        end
        items[#items + 1] = { addButton = true }

        local totalRows = math.ceil(#items / GRID_COLS)
        local totalW = parent:GetWidth() - GRID_PAD * 2
        local colW = math.floor(totalW / GRID_COLS)

        for row = 0, totalRows - 1 do
            local rowFrame = CreateFrame("Frame", nil, parent)
            PP.Size(rowFrame, totalW, GRID_ROW_H)
            PP.Point(rowFrame, "TOPLEFT", parent, "TOPLEFT", GRID_PAD, y - row * GRID_ROW_H)
            rowFrame._skipRowDivider = true
            EllesmereUI.RowBg(rowFrame, parent)

            for d = 1, GRID_COLS - 1 do
                local div = rowFrame:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(1, 1, 1, 0.06)
                if div.SetSnapToPixelGrid then div:SetSnapToPixelGrid(false); div:SetTexelSnappingBias(0) end
                div:SetWidth(1)
                local xPos = d * colW
                PP.Point(div, "TOP", rowFrame, "TOPLEFT", xPos, 0)
                PP.Point(div, "BOTTOM", rowFrame, "BOTTOMLEFT", xPos, 0)
            end

            for col = 0, GRID_COLS - 1 do
                local idx = row * GRID_COLS + col + 1
                local item = items[idx]
                if not item then break end

                local cell = CreateFrame("Frame", nil, rowFrame)
                cell:SetSize(colW, GRID_ROW_H)
                cell:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", col * colW, 0)

                if item.addButton then
                    -- Keybind-button style (dropdown-look bg/border with the
                    -- hover brighten), centered in its grid slot.
                    local addBtn = CreateFrame("Button", nil, cell)
                    PP.Size(addBtn, 126, 29)
                    addBtn:SetPoint("CENTER", cell, "CENTER", 0, 0)
                    addBtn:SetFrameLevel(cell:GetFrameLevel() + 2)
                    local addBg = EllesmereUI.SolidTex(addBtn, "BACKGROUND",
                        EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                    addBg:SetAllPoints()
                    local addBrd = EllesmereUI.MakeBorder(addBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, EllesmereUI.PanelPP)
                    local addLbl = EllesmereUI.MakeFont(addBtn, 12, nil, 1, 1, 1)
                    addLbl:SetAlpha(EllesmereUI.DD_TXT_A)
                    addLbl:SetPoint("CENTER")
                    addLbl:SetText(EllesmereUI.L("+ Add Spell"))
                    addBtn:SetScript("OnEnter", function()
                        addBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
                        if addBrd and addBrd.SetColor then addBrd:SetColor(1, 1, 1, 0.3) end
                    end)
                    addBtn:SetScript("OnLeave", function()
                        addBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                        if addBrd and addBrd.SetColor then addBrd:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A) end
                    end)
                    addBtn:SetScript("OnClick", function()
                        ShowAddSpellPopup(function(spellId)
                            ma.spellOverrides[spellId] = ma.spellOverrides[spellId] or { enabled = true, class = playerClass }
                            GridChanged()
                            EllesmereUI:RefreshPage(true)
                        end)
                    end)
                else
                    local cr, cg, cb = 1, 1, 1
                    if item.classToken then
                        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.classToken]
                        if cc then cr, cg, cb = cc.r, cc.g, cc.b end
                    end

                    local label = EllesmereUI.MakeFont(cell, 13, nil, cr, cg, cb)
                    label:SetPoint("LEFT", cell, "LEFT", GRID_SIDE_PAD, 0)
                    label:SetWidth(colW - GRID_SIDE_PAD * 2 - GRID_BOX_SZ - 6)
                    label:SetJustifyH("LEFT")
                    label:SetMaxLines(2)
                    label:SetText(item.label)

                    local box = CreateFrame("Frame", nil, cell)
                    box:SetSize(GRID_BOX_SZ, GRID_BOX_SZ)
                    box:SetPoint("RIGHT", cell, "RIGHT", -GRID_SIDE_PAD, 0)
                    local boxBg = box:CreateTexture(nil, "BACKGROUND")
                    boxBg:SetAllPoints()
                    boxBg:SetColorTexture(0.12, 0.12, 0.14, 1)
                    if boxBg.SetSnapToPixelGrid then boxBg:SetSnapToPixelGrid(false); boxBg:SetTexelSnappingBias(0) end
                    local boxBrd = EllesmereUI.MakeBorder(box, 0.25, 0.25, 0.28, 0.6, EllesmereUI.PanelPP)
                    local check = box:CreateTexture(nil, "ARTWORK")
                    check:SetPoint("TOPLEFT", box, "TOPLEFT", 3, -3)
                    check:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -3, 3)
                    check:SetColorTexture(EG.r, EG.g, EG.b, 1)
                    if check.SetSnapToPixelGrid then check:SetSnapToPixelGrid(false); check:SetTexelSnappingBias(0) end

                    local btn = CreateFrame("Button", nil, cell)
                    btn:SetAllPoints(cell)
                    btn:SetFrameLevel(cell:GetFrameLevel() + 2)
                    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

                    -- A cell is disabled while its class is unchecked in the
                    -- Enable Movement Alerts dropdown (tracking can never
                    -- fire for it). The X delete on custom cells stays live
                    -- so stale entries can still be cleaned up.
                    local function CellDisabled()
                        local ec = ma.enabledClasses
                        if not ec then return true end
                        if item.classToken then return not ec[item.classToken] end
                        return false
                    end

                    local function ApplyVisual()
                        local dis = CellDisabled()
                        local on = item.getVal()
                        if on then
                            check:Show()
                            boxBrd:SetColor(EG.r, EG.g, EG.b, 0.15)
                        else
                            check:Hide()
                            boxBrd:SetColor(0.25, 0.25, 0.28, 0.6)
                        end
                        if dis then
                            label:SetAlpha(0.3)
                            box:SetAlpha(0.4)
                        else
                            label:SetAlpha(on and 1 or 0.5)
                            box:SetAlpha(1)
                        end
                    end
                    ApplyVisual()

                    btn:SetScript("OnClick", function(_, mouseButton)
                        if CellDisabled() then return end
                        if mouseButton == "RightButton" then
                            local ov = ma.spellOverrides[item.spellId]
                            ShowCustomTextPopup(item.label, ov and ov.customText or "", function(txt)
                                for i = 1, #item.ids do
                                    local id = item.ids[i]
                                    ma.spellOverrides[id] = ma.spellOverrides[id] or {}
                                    ma.spellOverrides[id].customText = (txt ~= "") and txt or nil
                                end
                                if EllesmereUI._CacheMovementSpells then EllesmereUI._CacheMovementSpells() end
                                Refresh()
                            end)
                            return
                        end
                        item.setVal(not item.getVal())
                        ApplyVisual()
                        GridChanged()
                    end)
                    btn:SetScript("OnEnter", function()
                        if CellDisabled() then
                            EllesmereUI.ShowWidgetTooltip(cell, EllesmereUI.DisabledTooltip("Enable this class above"))
                            return
                        end
                        if not item.getVal() then label:SetAlpha(0.8) end
                        EllesmereUI.ShowWidgetTooltip(cell, EllesmereUI.L("Right-Click to set custom alert text."))
                    end)
                    btn:SetScript("OnLeave", function()
                        ApplyVisual()
                        EllesmereUI.HideWidgetTooltip()
                    end)

                    EllesmereUI.RegisterWidgetRefresh(ApplyVisual)

                    if item.custom then
                        local delBtn = CreateFrame("Button", nil, cell)
                        delBtn:SetSize(12, 12)
                        delBtn:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -4, -4)
                        delBtn:SetFrameLevel(btn:GetFrameLevel() + 2)
                        local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                        delIcon:SetAllPoints()
                        delIcon:SetTexture("Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-close.png")
                        delIcon:SetAlpha(0.4)
                        delBtn:SetScript("OnEnter", function() delIcon:SetAlpha(0.9) end)
                        delBtn:SetScript("OnLeave", function() delIcon:SetAlpha(0.4) end)
                        delBtn:SetScript("OnClick", function()
                            ma.spellOverrides[item.spellId] = nil
                            GridChanged()
                            EllesmereUI:RefreshPage(true)
                        end)
                    end
                end
            end
        end
        y = y - totalRows * GRID_ROW_H
    end

    _, h = W:Spacer(parent, y, 16);  y = y - h

    -------------------------------------------------------------------------
    --  EXTRA TRACKING
    -------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "EXTRA TRACKING", y);  y = y - h

    -- The two sibling trackers' master toggles, each carrying its full
    -- settings cog.
    local function tsOff() return not ma.tsEnabled end
    local function gwOff() return not ma.gwEnabled end

    local extraRow
    extraRow, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Time Spiral Tracker",
          tooltip="Flashes a banner whenever a tracked mobility spell's cooldown is proc-reset. Use Unlock Mode to reposition/resize.",
          getValue=function() return ma.tsEnabled == true end,
          setValue=function(v)
              ma.tsEnabled = v
              if EllesmereUI._UpdateMovementAlertEvents then EllesmereUI._UpdateMovementAlertEvents() end
              Refresh()
              EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Enable Gateway Shard Alert",
          tooltip="Warlock only. Alerts when your Gateway Control Shard is usable. Use Unlock Mode to reposition/resize.",
          getValue=function() return ma.gwEnabled == true end,
          setValue=function(v)
              ma.gwEnabled = v
              if EllesmereUI._UpdateMovementAlertEvents then EllesmereUI._UpdateMovementAlertEvents() end
              Refresh()
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h

    -- Time Spiral settings cog (left slot)
    do
        local leftRgn = extraRow._leftRegion
        local sndValues2, sndOrder2 = SoundDropdownValues()
        local ttsValues2, ttsOrder2 = TTSVoiceDropdownValues()
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
                { type="dropdown", label="Sound", values=sndValues2, order=sndOrder2,
                  disabled=function() return ma.tsTtsEnabled == true end,
                  disabledTooltip="Text-to-Speech is enabled below and takes priority over Sound.", rawTooltip=true,
                  get=function() return ma.tsSoundKey or "none" end,
                  set=function(v) ma.tsSoundKey = v end },
                { type="toggle", label="Use Text-to-Speech",
                  get=function() return ma.tsTtsEnabled == true end,
                  set=function(v) ma.tsTtsEnabled = v end },
                { type="dropdown", label="TTS Voice", values=ttsValues2, order=ttsOrder2,
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

    -- Gateway Shard settings cog (right slot); Combat Only lives in here.
    do
        local rgn = extraRow._rightRegion
        local sndValues2, sndOrder2 = SoundDropdownValues()
        local ttsValues2, ttsOrder2 = TTSVoiceDropdownValues()
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Gateway Shard Settings",
            minWidth = 300,
            rows = {
                { type="toggle", label="Combat Only",
                  tooltip="Only show the alert while in combat.",
                  get=function() return ma.gwCombatOnly == true end,
                  set=function(v) ma.gwCombatOnly = v; Refresh() end },
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
                { type="dropdown", label="Sound", values=sndValues2, order=sndOrder2,
                  disabled=function() return ma.gwTtsEnabled == true end,
                  disabledTooltip="Text-to-Speech is enabled below and takes priority over Sound.", rawTooltip=true,
                  get=function() return ma.gwSoundKey or "none" end,
                  set=function(v) ma.gwSoundKey = v end },
                { type="toggle", label="Use Text-to-Speech",
                  get=function() return ma.gwTtsEnabled == true end,
                  set=function(v) ma.gwTtsEnabled = v end },
                { type="dropdown", label="TTS Voice", values=ttsValues2, order=ttsOrder2,
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
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
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
