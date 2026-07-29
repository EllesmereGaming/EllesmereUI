-------------------------------------------------------------------------------
--  EUI_PartyMode_Options.lua
--  Party Mode options page for EllesmereUI
--  Shared across all EllesmereUI addons — only the first to load runs.
--  DEFERRED: body runs on first EllesmereUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
if _G._EllesmereUIPartyModeOptionsLoaded then return end
_G._EllesmereUIPartyModeOptionsLoaded = true

local EllesmereUI = _G.EllesmereUI
EllesmereUI._deferredInits[#EllesmereUI._deferredInits + 1] = function()

-- EnsureLoaded runs after PLAYER_LOGIN, so execute the init body directly.
do

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PanelPP

    local PAGE_PARTY = "Party Mode"

    ---------------------------------------------------------------------------
    --  Build the Party Mode page
    ---------------------------------------------------------------------------
    local function BuildPartyModePage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        -------------------------------------------------------------------
        --  Activate / Deactivate button
        -------------------------------------------------------------------
        local activateBtnFrame, activateBtnLbl
        activateBtnFrame, h = W:WideButton(parent,
            (EllesmereUIDB and EllesmereUIDB.partyMode) and "Deactivate Party Mode" or "Activate Party Mode",
            y,
            function()
                if EllesmereUI_TogglePartyMode then EllesmereUI_TogglePartyMode() end
                -- Update label after toggle
                if activateBtnLbl then
                    activateBtnLbl:SetText(
                        (EllesmereUIDB and EllesmereUIDB.partyMode) and EllesmereUI.L("Deactivate Party Mode") or EllesmereUI.L("Activate Party Mode")
                    )
                end
            end
        );  y = y - h
        -- Grab the label FontString from the button child
        do
            local btn = select(1, activateBtnFrame:GetChildren())
            if btn then
                for i = 1, btn:GetNumRegions() do
                    local rgn = select(i, btn:GetRegions())
                    if rgn and rgn.GetText and rgn:GetText() then
                        activateBtnLbl = rgn
                        break
                    end
                end
            end
        end
        -- Keep label in sync if toggled via keybind while panel is open
        if activateBtnLbl then
            EllesmereUI.RegisterWidgetRefresh(function()
                activateBtnLbl:SetText(
                    (EllesmereUIDB and EllesmereUIDB.partyMode) and EllesmereUI.L("Deactivate Party Mode") or EllesmereUI.L("Activate Party Mode")
                )
            end)
        end

        -------------------------------------------------------------------
        --  PARTY MODE (disco lights overlay)
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "PARTY MODE", y);  y = y - h

        -- Row 1: Toggle Keybind (full-width custom row)
        do
            local ROW_H = 50
            local SIDE_PAD = 20
            local kbFrame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            PP.Size(kbFrame, totalW, ROW_H)
            PP.Point(kbFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
            EllesmereUI.RowBg(kbFrame, parent)

            local label = EllesmereUI.MakeFont(kbFrame, 14, nil, EllesmereUI.TEXT_WHITE_R, EllesmereUI.TEXT_WHITE_G, EllesmereUI.TEXT_WHITE_B)
            PP.Point(label, "LEFT", kbFrame, "LEFT", SIDE_PAD, 0)
            label:SetText(EllesmereUI.L("Toggle On/Off Keybind"))

            local KB_W, KB_H = 140, 30
            local kbBtn = CreateFrame("Button", nil, kbFrame)
            PP.Size(kbBtn, KB_W, KB_H)
            PP.Point(kbBtn, "RIGHT", kbFrame, "RIGHT", -SIDE_PAD, 0)
            kbBtn:SetFrameLevel(kbFrame:GetFrameLevel() + 2)
            kbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local kbBg = EllesmereUI.SolidTex(kbBtn, "BACKGROUND", EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            kbBg:SetAllPoints()
            kbBtn._border = EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, EllesmereUI.PanelPP)
            local kbLbl = EllesmereUI.MakeFont(kbBtn, 13, nil, 1, 1, 1)
            kbLbl:SetAlpha(EllesmereUI.DD_TXT_A)
            kbLbl:SetPoint("CENTER")

            local function FormatKey(key)
                if not key then return "Not Bound" end
                local parts = {}
                for mod in key:gmatch("(%u+)%-") do
                    parts[#parts + 1] = mod:sub(1, 1) .. mod:sub(2):lower()
                end
                local actualKey = key:match("[^%-]+$") or key
                parts[#parts + 1] = actualKey
                return table.concat(parts, " + ")
            end

            local function RefreshLabel()
                local key = EllesmereUIDB and EllesmereUIDB.partyModeKey
                kbLbl:SetText(FormatKey(key))
            end
            RefreshLabel()

            local listening = false

            kbBtn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if listening then
                        listening = false
                        self:EnableKeyboard(false)
                    end
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    if EllesmereUIDB.partyModeKey then
                        ClearOverrideBindings(EllesmereUIPartyModeBindBtn)
                    end
                    EllesmereUIDB.partyModeKey = nil
                    RefreshLabel()
                    return
                end
                if listening then return end
                listening = true
                kbLbl:SetText(EllesmereUI.L("Press a key..."))
                kbBtn:EnableKeyboard(true)
            end)

            kbBtn:SetScript("OnKeyDown", function(self, key)
                if not listening then
                    self:SetPropagateKeyboardInput(true)
                    return
                end
                if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
                   or key == "LALT" or key == "RALT" then
                    self:SetPropagateKeyboardInput(true)
                    return
                end
                self:SetPropagateKeyboardInput(false)
                if key == "ESCAPE" then
                    listening = false
                    self:EnableKeyboard(false)
                    RefreshLabel()
                    return
                end
                local mods = ""
                if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                if IsControlKeyDown() then mods = mods .. "CTRL-" end
                if IsAltKeyDown() then mods = mods .. "ALT-" end
                local fullKey = mods .. key

                if not EllesmereUIDB then EllesmereUIDB = {} end
                ClearOverrideBindings(EllesmereUIPartyModeBindBtn)
                SetOverrideBindingClick(EllesmereUIPartyModeBindBtn, true, fullKey, "EllesmereUIPartyModeBindBtn")
                EllesmereUIDB.partyModeKey = fullKey

                listening = false
                self:EnableKeyboard(false)
                RefreshLabel()
            end)

            kbBtn:SetScript("OnEnter", function(self)
                kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
                if kbBtn._border and kbBtn._border.SetColor then
                    kbBtn._border:SetColor(1, 1, 1, 0.3)
                end
                EllesmereUI.ShowWidgetTooltip(self, "Left-click to set a keybind.\nRight-click to unbind.")
            end)
            kbBtn:SetScript("OnLeave", function()
                if listening then return end
                kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                if kbBtn._border and kbBtn._border.SetColor then
                    kbBtn._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
                end
                EllesmereUI.HideWidgetTooltip()
            end)

            EllesmereUI.RegisterWidgetRefresh(RefreshLabel)

            kbFrame:SetScript("OnHide", function()
                if listening then
                    listening = false
                    kbBtn:EnableKeyboard(false)
                    RefreshLabel()
                end
            end)

            y = y - ROW_H
        end

        -- Row 2: Brightness slider (full-width)
        do
            local ROW_H = 50
            local SIDE_PAD = 20
            local frame = CreateFrame("Frame", nil, parent)
            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            PP.Size(frame, totalW, ROW_H)
            PP.Point(frame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
            EllesmereUI.RowBg(frame, parent)

            local label = EllesmereUI.MakeFont(frame, 14, nil, EllesmereUI.TEXT_WHITE_R, EllesmereUI.TEXT_WHITE_G, EllesmereUI.TEXT_WHITE_B)
            PP.Point(label, "LEFT", frame, "LEFT", SIDE_PAD, 0)
            label:SetText(EllesmereUI.L("Brightness"))

            local function briGet()
                local db = EllesmereUIDB
                local v = db and db.partyModeBrightness
                if v == nil then v = 0.65 end
                return math.floor(v * 100 + 0.5)
            end
            local function briSet(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.partyModeBrightness = v / 100
            end

            local trackFrame, valBox = EllesmereUI.BuildSliderCore(frame, 160, 4, 14, 40, 26, 13, EllesmereUI.SL_INPUT_A,
                0, 100, 1, briGet, briSet, false)
            PP.Point(valBox, "RIGHT", frame, "RIGHT", -SIDE_PAD, 0)
            PP.Point(trackFrame, "RIGHT", valBox, "LEFT", -12, 0)

            y = y - ROW_H
        end

        -- Row 3: Dim the Lights While Active (toggle)
        _, h = W:Toggle(parent, "Dim the Lights While Active", y,
            function() return EllesmereUIDB and (EllesmereUIDB.partyModeDimLights ~= false) end,
            function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.partyModeDimLights = v
                -- Live apply/restore if party mode is currently active
                if EllesmereUIDB.partyMode then
                    if v and not EllesmereUI_IsDimLightsActive() then
                        EllesmereUI_ApplyDimLights()
                    elseif not v and EllesmereUI_IsDimLightsActive() then
                        EllesmereUI_RestoreDimLights()
                    end
                end
            end,
            nil
        );  y = y - h

        -------------------------------------------------------------------
        --  CELEBRATION TRIGGERS
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CELEBRATION TRIGGERS", y);  y = y - h

        -- Helper: set a trigger DB key and refresh widgets
        local function TriggerSet(key)
            return function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB[key] = v
                local rl = EllesmereUI._widgetRefreshList
                if rl then for i = 1, #rl do rl[i]() end end
            end
        end
        local function TriggerGet(key)
            return function() return EllesmereUIDB and EllesmereUIDB[key] or false end
        end

        -- Row 1: Randomly | Timed Keystone | Mythic Boss Kill
        local CB_SPLITS = { 0.333, 0.333, 0.334, rowHeight = 36 }
        _, h = W:TripleRow(parent, y,
            { type = "checkbox", text = "Randomly",           getValue = TriggerGet("partyModeTriggerRandom"),     setValue = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.partyModeTriggerRandom = v
                if v then
                    EllesmereUI_StartRandomTrigger()
                else
                    EllesmereUI_StopRandomTrigger()
                end
                local rl = EllesmereUI._widgetRefreshList
                if rl then for i = 1, #rl do rl[i]() end end
            end },
            { type = "checkbox", text = "Timed Keystone",     getValue = TriggerGet("partyModeTriggerKeystone"),   setValue = TriggerSet("partyModeTriggerKeystone") },
            { type = "checkbox", text = "Mythic Boss Kill",   getValue = TriggerGet("partyModeTriggerMythicBoss"), setValue = TriggerSet("partyModeTriggerMythicBoss") },
            CB_SPLITS
        );  y = y - h

        -- Row 2: Rated Arena Win | Rated BG Win | Heroic Boss Kill
        _, h = W:TripleRow(parent, y,
            { type = "checkbox", text = "Rated Arena Win",    getValue = TriggerGet("partyModeTriggerRatedArena"), setValue = TriggerSet("partyModeTriggerRatedArena") },
            { type = "checkbox", text = "Rated BG Win",       getValue = TriggerGet("partyModeTriggerRatedBG"),    setValue = TriggerSet("partyModeTriggerRatedBG") },
            { type = "checkbox", text = "Heroic Boss Kill",   getValue = TriggerGet("partyModeTriggerHeroicBoss"), setValue = TriggerSet("partyModeTriggerHeroicBoss") },
            CB_SPLITS
        );  y = y - h

        -- Row 3: Normal Boss Kill | Raid Finder Boss Kill | Mythic 0 Completion
        _, h = W:TripleRow(parent, y,
            { type = "checkbox", text = "Normal Boss Kill",       getValue = TriggerGet("partyModeTriggerNormalBoss"),  setValue = TriggerSet("partyModeTriggerNormalBoss") },
            { type = "checkbox", text = "Raid Finder Boss Kill",  getValue = TriggerGet("partyModeTriggerLFRBoss"),     setValue = TriggerSet("partyModeTriggerLFRBoss") },
            { type = "checkbox", text = "Mythic 0 Completion",    getValue = TriggerGet("partyModeTriggerMythic0"),     setValue = TriggerSet("partyModeTriggerMythic0") },
            CB_SPLITS
        );  y = y - h

        -- Row 4: Bloodlust (debuff-triggered, hardcoded 40s; intentionally NOT
        -- wired into the Auto Celebration Duration slider, so it has its own
        -- setValue rather than the shared TriggerSet).
        _, h = W:TripleRow(parent, y,
            { type = "checkbox", text = "Bloodlust",
              getValue = TriggerGet("partyModeTriggerBloodlust"),
              setValue = function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.partyModeTriggerBloodlust = v
                  if EllesmereUI_UpdatePartyModeLustListener then EllesmereUI_UpdatePartyModeLustListener() end
                  local rl = EllesmereUI._widgetRefreshList
                  if rl then for i = 1, #rl do rl[i]() end end
              end },
            nil,
            nil,
            CB_SPLITS
        );  y = y - h

        -- Bottom border for the checkbox grid (matches SectionHeader separator style)
        -- Placed 1px above current y so the next row's background doesn't cover it
        do
            local totalW = parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2
            local sep = parent:CreateTexture(nil, "ARTWORK", nil, 7)
            sep:SetColorTexture(EllesmereUI.BORDER_R, EllesmereUI.BORDER_G, EllesmereUI.BORDER_B, 0.02)
            PP.Size(sep, totalW, 1)
            PP.Point(sep, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y + 1)
        end

        -- Celebration Trigger Duration slider (conditionally enabled)
        local durFrame
        do
            local function AnyCelebrationTriggerEnabled()
                if not EllesmereUIDB then return false end
                return EllesmereUIDB.partyModeTriggerKeystone
                    or EllesmereUIDB.partyModeTriggerMythicBoss
                    or EllesmereUIDB.partyModeTriggerHeroicBoss
                    or EllesmereUIDB.partyModeTriggerNormalBoss
                    or EllesmereUIDB.partyModeTriggerLFRBoss
                    or EllesmereUIDB.partyModeTriggerMythic0
                    or EllesmereUIDB.partyModeTriggerRatedBG
                    or EllesmereUIDB.partyModeTriggerRatedArena
                    or EllesmereUIDB.partyModeTriggerRandom
                    or false
            end

            durFrame, h = W:Slider(parent, "Auto Celebration Duration", y, 10, 60, 1,
                function()
                    local db = EllesmereUIDB
                    local v = db and db.partyModeMPlusDuration
                    if v == nil then v = 30 end
                    return v
                end,
                function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.partyModeMPlusDuration = v
                end,
                nil
            );  y = y - h

            -- Add "(seconds)" suffix in smaller, dimmer text
            do
                local suffix = durFrame:CreateFontString(nil, "OVERLAY")
                suffix:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
                suffix:SetTextColor(1, 1, 1, 0.35)
                local durLabel
                for i = 1, durFrame:GetNumRegions() do
                    local reg = select(i, durFrame:GetRegions())
                    if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Auto Celebration Duration" then
                        durLabel = reg
                        break
                    end
                end
                if durLabel then
                    -- Anchor to the END OF THE TEXT, not the region's right
                    -- edge: ClampRowLabel stretches full-width row labels to
                    -- the slider track, so "RIGHT" sits at the track edge.
                    suffix:SetPoint("LEFT", durLabel, "LEFT", durLabel:GetStringWidth() + 5, 0)
                else
                    suffix:SetPoint("LEFT", durFrame, "LEFT", 250, 0)
                end
                suffix:SetText(EllesmereUI.L("(seconds)"))
            end

            local function RefreshDurDisabled()
                local enabled = AnyCelebrationTriggerEnabled()
                durFrame:SetAlpha(enabled and 1 or 0.35)
                durFrame:EnableMouse(enabled)
            end
            RefreshDurDisabled()
            EllesmereUI.RegisterWidgetRefresh(RefreshDurDisabled)

            -- Disabled tooltip for duration slider (split: label zone + control zone)
            do
                -- Find the label and slider control regions
                local durLabel, durControl
                for i = 1, durFrame:GetNumRegions() do
                    local reg = select(i, durFrame:GetRegions())
                    if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Auto Celebration Duration" then
                        durLabel = reg
                        break
                    end
                end

                -- Label hit zone (left half)
                local durHitLabel = CreateFrame("Frame", nil, durFrame)
                durHitLabel:SetFrameLevel(durFrame:GetFrameLevel() + 10)
                durHitLabel:EnableMouse(false)
                if durLabel then
                    durHitLabel:SetPoint("TOPLEFT", durFrame, "TOPLEFT", 0, 0)
                    durHitLabel:SetPoint("BOTTOMLEFT", durFrame, "BOTTOMLEFT", 0, 0)
                    durHitLabel:SetWidth(durFrame:GetWidth() * 0.5)
                end
                durHitLabel:SetScript("OnEnter", function(self)
                    if not AnyCelebrationTriggerEnabled() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("at least one Celebration Trigger"))
                    end
                end)
                durHitLabel:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                -- Control hit zone (right half)
                local durHitControl = CreateFrame("Frame", nil, durFrame)
                durHitControl:SetFrameLevel(durFrame:GetFrameLevel() + 10)
                durHitControl:EnableMouse(false)
                durHitControl:SetPoint("TOPRIGHT", durFrame, "TOPRIGHT", 0, 0)
                durHitControl:SetPoint("BOTTOMRIGHT", durFrame, "BOTTOMRIGHT", 0, 0)
                durHitControl:SetWidth(durFrame:GetWidth() * 0.5)
                durHitControl:SetScript("OnEnter", function(self)
                    if not AnyCelebrationTriggerEnabled() then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("at least one Celebration Trigger"))
                    end
                end)
                durHitControl:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                local function UpdateDurHit()
                    local dis = not AnyCelebrationTriggerEnabled()
                    durHitLabel:EnableMouse(dis)
                    durHitControl:EnableMouse(dis)
                end
                UpdateDurHit()
                EllesmereUI.RegisterWidgetRefresh(UpdateDurHit)
            end

            -- Random cooldown slider (grayed out unless random trigger is enabled)
            local cdFrame
            cdFrame, h = W:Slider(parent, "Random Celebrations Minimum Cooldown", y, 1, 30, 1,
                function()
                    local db = EllesmereUIDB
                    local v = db and db.partyModeRandomCooldown
                    if v == nil then v = 10 end
                    return v
                end,
                function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.partyModeRandomCooldown = v
                end,
                nil
            );  y = y - h

            -- Add "(minutes)" suffix in smaller, dimmer text
            do
                local suffix = cdFrame:CreateFontString(nil, "OVERLAY")
                suffix:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
                suffix:SetTextColor(1, 1, 1, 0.35)
                local cdLabel
                for i = 1, cdFrame:GetNumRegions() do
                    local reg = select(i, cdFrame:GetRegions())
                    if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Random Celebrations Minimum Cooldown" then
                        cdLabel = reg
                        break
                    end
                end
                if cdLabel then
                    -- Same text-end anchoring as the duration suffix above.
                    suffix:SetPoint("LEFT", cdLabel, "LEFT", cdLabel:GetStringWidth() + 5, 0)
                else
                    suffix:SetPoint("LEFT", cdFrame, "LEFT", 350, 0)
                end
                suffix:SetText(EllesmereUI.L("(minutes)"))
            end

            local function RefreshCdDisabled()
                local enabled = EllesmereUIDB and EllesmereUIDB.partyModeTriggerRandom or false
                cdFrame:SetAlpha(enabled and 1 or 0.35)
                cdFrame:EnableMouse(enabled)
            end
            RefreshCdDisabled()
            EllesmereUI.RegisterWidgetRefresh(RefreshCdDisabled)

            -- Disabled tooltip for cooldown slider (split: label zone + control zone)
            do
                local cdLabel
                for i = 1, cdFrame:GetNumRegions() do
                    local reg = select(i, cdFrame:GetRegions())
                    if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Random Celebrations Minimum Cooldown" then
                        cdLabel = reg
                        break
                    end
                end

                -- Label hit zone (left half)
                local cdHitLabel = CreateFrame("Frame", nil, cdFrame)
                cdHitLabel:SetFrameLevel(cdFrame:GetFrameLevel() + 10)
                cdHitLabel:EnableMouse(false)
                if cdLabel then
                    cdHitLabel:SetPoint("TOPLEFT", cdFrame, "TOPLEFT", 0, 0)
                    cdHitLabel:SetPoint("BOTTOMLEFT", cdFrame, "BOTTOMLEFT", 0, 0)
                    cdHitLabel:SetWidth(cdFrame:GetWidth() * 0.5)
                end
                cdHitLabel:SetScript("OnEnter", function(self)
                    local enabled = EllesmereUIDB and EllesmereUIDB.partyModeTriggerRandom or false
                    if not enabled then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("the Randomly trigger"))
                    end
                end)
                cdHitLabel:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                -- Control hit zone (right half)
                local cdHitControl = CreateFrame("Frame", nil, cdFrame)
                cdHitControl:SetFrameLevel(cdFrame:GetFrameLevel() + 10)
                cdHitControl:EnableMouse(false)
                cdHitControl:SetPoint("TOPRIGHT", cdFrame, "TOPRIGHT", 0, 0)
                cdHitControl:SetPoint("BOTTOMRIGHT", cdFrame, "BOTTOMRIGHT", 0, 0)
                cdHitControl:SetWidth(cdFrame:GetWidth() * 0.5)
                cdHitControl:SetScript("OnEnter", function(self)
                    local enabled = EllesmereUIDB and EllesmereUIDB.partyModeTriggerRandom or false
                    if not enabled then
                        EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("the Randomly trigger"))
                    end
                end)
                cdHitControl:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

                local function UpdateCdHit()
                    local enabled = EllesmereUIDB and EllesmereUIDB.partyModeTriggerRandom or false
                    cdHitLabel:EnableMouse(not enabled)
                    cdHitControl:EnableMouse(not enabled)
                end
                UpdateCdHit()
                EllesmereUI.RegisterWidgetRefresh(UpdateCdHit)
            end
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIPartyMode", {
        title       = "Party Mode",
        description = "Disco lights overlay for celebrations.",
        pages       = { PAGE_PARTY },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_PARTY then
                return BuildPartyModePage(pageName, parent, yOffset)
            end
        end,
        onReset     = function()
            -- Stop party mode (restores CVars if dimmed)
            if EllesmereUIDB and EllesmereUIDB.partyMode then
                EllesmereUIDB.partyMode = false
                EllesmereUI_StopPartyMode()
            end
            if EllesmereUIDB then
                EllesmereUIDB.partyMode = nil
                EllesmereUIDB.partyModeKey = nil
                EllesmereUIDB.partyModeMPlus = nil
                EllesmereUIDB.partyModeMPlusDuration = nil
                EllesmereUIDB.partyModeBrightness = nil
                EllesmereUIDB.partyModeTriggerKeystone = nil
                EllesmereUIDB.partyModeTriggerMythicBoss = nil
                EllesmereUIDB.partyModeTriggerHeroicBoss = nil
                EllesmereUIDB.partyModeTriggerNormalBoss = nil
                EllesmereUIDB.partyModeTriggerLFRBoss = nil
                EllesmereUIDB.partyModeTriggerMythic0 = nil
                EllesmereUIDB.partyModeTriggerBloodlust = nil
                EllesmereUIDB.partyModeTriggerRatedBG = nil
                EllesmereUIDB.partyModeTriggerRatedArena = nil
                EllesmereUIDB.partyModeTriggerRandom = nil
                EllesmereUIDB.partyModeRandomCooldown = nil
                EllesmereUIDB.partyModeDimLights = nil
            end
            -- Stop random trigger timer
            EllesmereUI_StopRandomTrigger()
            -- Clear any override bindings
            if EllesmereUIPartyModeBindBtn then
                ClearOverrideBindings(EllesmereUIPartyModeBindBtn)
            end
            EllesmereUI:SelectPage(PAGE_PARTY)
        end,
    })
end  -- end do block
end  -- end deferred init
