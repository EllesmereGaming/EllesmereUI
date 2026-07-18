-------------------------------------------------------------------------------
--  EUI_DamageMeters_Options.lua
--  Options page for EllesmereUI Damage Meters.
--  All settings are live (no Edit Mode, no reload required).
-------------------------------------------------------------------------------
local _, ns = ...
local EDM = ns.EDM

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    if not EDM then return end
    -- Do nothing if the module is disabled / coming soon
    if not _G._EDM_DB then return end

    local function DB()
        local d = _G._EDM_DB
        if d and d.profile and d.profile.dm then return d.profile.dm end
        return {}
    end
    local function Cfg(k)    return DB()[k]  end
    local function Set(k, v) DB()[k] = v     end

    -- All settings are picked up on the next refresh cycle (0.3s combat,
    -- 2s idle). Just Set() and go.

    -- Bar texture dropdown values (same pattern as Resource Bars / Nameplates)
    local dmTexValues = {}
    local dmTexOrder = {}
    do
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(
                _G._EDM_BarTextureNames or {},
                _G._EDM_BarTextureOrder or {},
                nil,
                _G._EDM_BarTextures
            )
        end
        local texNames = _G._EDM_BarTextureNames or {}
        local texOrder2 = _G._EDM_BarTextureOrder or {}
        local texLookup = _G._EDM_BarTextures or {}
        for _, key in ipairs(texOrder2) do
            if key ~= "---" then
                dmTexValues[key] = texNames[key] or key
            end
            dmTexOrder[#dmTexOrder + 1] = key
        end
        dmTexValues._menuOpts = {
            itemHeight = 28,
            background = function(key) return texLookup[key] end,
        }
    end

    -- Variant with "Match Damage Meters" at the top (for breakdown / spell history)
    local matchTexValues = { match = "Match Damage Meters" }
    local matchTexOrder  = { "match", "---" }
    for _, key in ipairs(dmTexOrder) do
        matchTexOrder[#matchTexOrder + 1] = key
        if key ~= "---" then
            matchTexValues[key] = dmTexValues[key]
        end
    end
    matchTexValues._menuOpts = dmTexValues._menuOpts

    local function BuildPage(_, parent, yOffset)
        local W  = EllesmereUI.Widgets
        local PP = EllesmereUI.PP
        local y  = yOffset
        local h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        local function Refresh() if ns.RefreshMeter then ns.RefreshMeter() end end
        local function ApplyHdr() if ns.ApplyHeader then ns.ApplyHeader() end end
        local function ApplyBrd() if ns.ApplyBorder then ns.ApplyBorder() end end
        local function ApplyIconBrd() if ns.ApplyIconBorder then ns.ApplyIconBorder() end end

        -- ── DISPLAY ─────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

        -- Visibility | Visibility Options
        local visRow
        visRow, h = EllesmereUI.BuildVisibilityModeRow(W, parent, y,
            { getStore = DB, legacyKey = "visibility",
              caps = { partyIncludesRaid = false, luaDragonriding = true },
              onChanged = function()
                  if EllesmereUI.RequestVisibilityUpdate then EllesmereUI.RequestVisibilityUpdate() end
              end },
            { type="dropdown", text="Visibility Options",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end })
        do
            local rightRgn = visRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                EllesmereUI.VIS_OPT_ITEMS,
                function(k) return Cfg(k) or false end,
                function(k, v) Set(k, v); if EllesmereUI.RequestVisibilityUpdate then EllesmereUI.RequestVisibilityUpdate() end end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        y = y - h

        -- Background Opacity (+ inline color swatch) | Always Show Player
        local bgRow
        bgRow, h = W:DualRow(parent, y,
            { type="slider", text="Background Opacity",
              min = 0, max = 1, step = 0.01,
              getValue = function() return Cfg("bgAlpha") or 0.75 end,
              setValue = function(v) Set("bgAlpha", v); if ns.ApplyBackground then ns.ApplyBackground() end end },
            { type="toggle", text="Always Show Player",
              tooltip = "This will pin your bar to the window when it is not within the visible area",
              getValue = function() return Cfg("showPinnedSelf") ~= false end,
              setValue = function(v) Set("showPinnedSelf", v); Refresh() end })
        -- Inline color swatch on Background Opacity
        do
            local rgn = bgRow._leftRegion
            local ctrl = rgn._control
            local bgSwatch, bgSwatchRefresh = EllesmereUI.BuildColorSwatch(
                rgn, bgRow:GetFrameLevel() + 3,
                function()
                    return (Cfg("bgR") or 0), (Cfg("bgG") or 0), (Cfg("bgB") or 0)
                end,
                function(r, g, b)
                    Set("bgR", r); Set("bgG", g); Set("bgB", b)
                    if ns.ApplyBackground then ns.ApplyBackground() end
                end,
                false, 20)
            PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(function() bgSwatchRefresh() end)
        end
        y = y - h

        -- Refresh Rate (+ seconds) | Hide Reset Button
        local rrRow
        rrRow, h = W:DualRow(parent, y,
            { type="slider", text="Refresh Rate",
              tooltip = "Increase to improve performance, Decrease to update meters faster",
              min = 0.1, max = 2, step = 0.1,
              getValue = function() return Cfg("refreshRate") or 0.5 end,
              setValue = function(v) Set("refreshRate", v) end,
              fmt = function(v) return format("%.2fs", v) end },
            { type="toggle", text="Hide Reset Button",
              tooltip = "Hide the Reset Data button from the damage meter header.",
              getValue = function() return Cfg("hideResetButton") == true end,
              setValue = function(v) Set("hideResetButton", v); ApplyHdr() end })
        do
            local rgn = rrRow._leftRegion
            local suffix = rgn:CreateFontString(nil, "OVERLAY")
            suffix:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
            suffix:SetTextColor(1, 1, 1, 0.35)
            local rrLabel
            for i = 1, rgn:GetNumRegions() do
                local reg = select(i, rgn:GetRegions())
                if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Refresh Rate" then
                    rrLabel = reg
                    break
                end
            end
            if rrLabel then
                suffix:SetPoint("LEFT", rrLabel, "RIGHT", 5, 0)
            else
                suffix:SetPoint("LEFT", rgn, "LEFT", 150, 0)
            end
            suffix:SetText(EllesmereUI.L("(seconds)"))
        end

        y = y - h

        -- Reset Data Keybind
        local kbRow
        kbRow, h = W:DualRow(parent, y,
            { type="label", text="" },
            { type="label", text="Reset Data Keybind" })

        do
            local rgn = kbRow._rightRegion
            local KB_W, KB_H = 120, 26
            local kbBtn = CreateFrame("Button", nil, rgn)
            PP.Size(kbBtn, KB_W, KB_H)
            PP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -10, 0)
            kbBtn:SetFrameLevel(rgn:GetFrameLevel() + 2)
            kbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local kbBg = EllesmereUI.SolidTex(kbBtn, "BACKGROUND", EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            kbBg:SetAllPoints()
            kbBtn._border = EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, EllesmereUI.PanelPP)
            local kbLbl = EllesmereUI.MakeFont(kbBtn, 12, nil, 1, 1, 1)
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
                kbLbl:SetText(FormatKey(Cfg("resetDataKey")))
            end
            RefreshLabel()

            local listening = false

            kbBtn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if listening then
                        listening = false
                        self:EnableKeyboard(false)
                    end
                    local prev = Cfg("resetDataKey")
                    if prev and _G.EllesmereUIDMResetBindBtn then
                        ClearOverrideBindings(_G.EllesmereUIDMResetBindBtn)
                    end
                    Set("resetDataKey", nil)
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

                if _G.EllesmereUIDMResetBindBtn then
                    ClearOverrideBindings(_G.EllesmereUIDMResetBindBtn)
                    SetOverrideBindingClick(_G.EllesmereUIDMResetBindBtn, true, fullKey, "EllesmereUIDMResetBindBtn")
                end
                Set("resetDataKey", fullKey)

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

            rgn:HookScript("OnHide", function()
                if listening then
                    listening = false
                    kbBtn:EnableKeyboard(false)
                    RefreshLabel()
                end
            end)
        end
        y = y - h

        -- ── HEADER ──────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "HEADER", y); y = y - h

        -- Row 1: Header Height | Opacity (+ inline bg color swatch)
        local hdrRow1
        hdrRow1, h = W:DualRow(parent, y,
            { type="slider", text="Header Height",
              min = 14, max = 40, step = 1,
              getValue = function() return Cfg("hdrHeight") or 22 end,
              setValue = function(v) Set("hdrHeight", v); ApplyHdr(); Refresh() end },
            { type="slider", text="Opacity",
              min = 0, max = 1, step = 0.01,
              getValue = function() return Cfg("hdrBgAlpha") or 1 end,
              setValue = function(v) Set("hdrBgAlpha", v); ApplyHdr() end })
        -- Inline color swatch on Opacity
        do
            local rgn = hdrRow1._rightRegion
            local ctrl = rgn._control
            local hdrSwatch, hdrSwatchRefresh = EllesmereUI.BuildColorSwatch(
                rgn, hdrRow1:GetFrameLevel() + 3,
                function()
                    local c = Cfg("hdrBgColor")
                    if c then return c.r or 0x1B/255, c.g or 0x1B/255, c.b or 0x1B/255 end
                    return 0x1B/255, 0x1B/255, 0x1B/255
                end,
                function(r, g, b)
                    Set("hdrBgColor", { r = r, g = g, b = b })
                    ApplyHdr()
                end,
                false, 20)
            PP.Point(hdrSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(function() hdrSwatchRefresh() end)
        end
        y = y - h

        -- Row 2: Top Text Size (+ inline dual swatches) | Icon Size (+ inline dual swatches)
        local hdrRow2
        hdrRow2, h = W:DualRow(parent, y,
            { type="slider", text="Top Text Size",
              min = 8, max = 18, step = 1, trackWidth = 120,
              getValue = function() return Cfg("hdrFontSize") or 11 end,
              setValue = function(v) Set("hdrFontSize", v); ApplyHdr() end },
            { type="slider", text="Icon Size",
              min = 20, max = 30, step = 1,
              getValue = function() return Cfg("hdrIconSize") or 22 end,
              setValue = function(v) Set("hdrIconSize", v); ApplyHdr() end })
        -- Inline dual swatches on Text Size: right = Custom, left = Accent
        do
            local rgn = hdrRow2._leftRegion
            local ctrl = rgn._control

            local customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(
                rgn, hdrRow2:GetFrameLevel() + 3,
                function()
                    local c = Cfg("hdrTextColor")
                    if c then return c.r or 1, c.g or 1, c.b or 1 end
                    return 1, 1, 1
                end,
                function(r, g, b)
                    Set("hdrTextUseAccent", false)
                    Set("hdrTextColor", { r = r, g = g, b = b })
                    ApplyHdr(); EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(customSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local origHdrTextClick = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self, ...)
                if Cfg("hdrTextUseAccent") ~= false then
                    Set("hdrTextUseAccent", false)
                    ApplyHdr(); EllesmereUI:RefreshPage()
                    return
                end
                if origHdrTextClick then origHdrTextClick(self, ...) end
            end)
            customSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color")
            end)
            customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local accentSwatch, updateAccent = EllesmereUI.BuildColorSwatch(
                rgn, hdrRow2:GetFrameLevel() + 3,
                function()
                    return EllesmereUI.ResolveActiveAccent()
                end,
                function()
                    Set("hdrTextUseAccent", true)
                    ApplyHdr(); EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(accentSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
            accentSwatch:SetScript("OnClick", function()
                Set("hdrTextUseAccent", true)
                ApplyHdr(); EllesmereUI:RefreshPage()
            end)
            accentSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(accentSwatch, "Accent Color")
            end)
            accentSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Inline cog: header text X/Y offset
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Title Position",
                rows = {
                    { type = "slider", label = "X Offset", min = -20, max = 20, step = 1,
                      get = function() return Cfg("hdrTextOffX") or 0 end,
                      set = function(v) Set("hdrTextOffX", v); ApplyHdr() end },
                    { type = "slider", label = "Y Offset", min = -20, max = 20, step = 1,
                      get = function() return Cfg("hdrTextOffY") or 0 end,
                      set = function(v) Set("hdrTextOffY", v); ApplyHdr() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", accentSwatch, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)

            local function refreshHdrText()
                updateCustom(); updateAccent()
                local useAccent = Cfg("hdrTextUseAccent") ~= false
                customSwatch:SetAlpha(useAccent and 0.3 or 1)
                accentSwatch:SetAlpha(useAccent and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(refreshHdrText)
            refreshHdrText()
        end
        -- Inline dual swatches on Icon Size: right = Custom, left = Accent
        do
            local rgn = hdrRow2._rightRegion
            local ctrl = rgn._control

            local customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(
                rgn, hdrRow2:GetFrameLevel() + 3,
                function()
                    local c = Cfg("iconColor")
                    if c then return c.r or 1, c.g or 1, c.b or 1 end
                    return 1, 1, 1
                end,
                function(r, g, b)
                    Set("iconColorUseAccent", false)
                    Set("iconColor", { r = r, g = g, b = b })
                    if ns.ApplyIconColor then ns.ApplyIconColor() end
                    EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(customSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local origIconClick = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self, ...)
                if Cfg("iconColorUseAccent") then
                    Set("iconColorUseAccent", false)
                    if ns.ApplyIconColor then ns.ApplyIconColor() end
                    EllesmereUI:RefreshPage()
                    return
                end
                if origIconClick then origIconClick(self, ...) end
            end)
            customSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color")
            end)
            customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local accentSwatch, updateAccent = EllesmereUI.BuildColorSwatch(
                rgn, hdrRow2:GetFrameLevel() + 3,
                function()
                    return EllesmereUI.ResolveActiveAccent()
                end,
                function()
                    Set("iconColorUseAccent", true)
                    if ns.ApplyIconColor then ns.ApplyIconColor() end
                    EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(accentSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
            accentSwatch:SetScript("OnClick", function()
                Set("iconColorUseAccent", true)
                if ns.ApplyIconColor then ns.ApplyIconColor() end
                EllesmereUI:RefreshPage()
            end)
            accentSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(accentSwatch, "Accent Color")
            end)
            accentSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            -- Inline cog: icon visibility
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Visibility",
                rows = {
                    { type = "toggle", label = "Mouseover Icons",
                      get = function() return Cfg("hdrMouseoverIcons") or false end,
                      set = function(v) Set("hdrMouseoverIcons", v); ApplyHdr() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", accentSwatch, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)

            local function refreshHdrIcon()
                updateCustom(); updateAccent()
                local useAccent = Cfg("iconColorUseAccent")
                customSwatch:SetAlpha(useAccent and 0.3 or 1)
                accentSwatch:SetAlpha(useAccent and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(refreshHdrIcon)
            refreshHdrIcon()
        end
        y = y - h

        -- ── BAR DESIGN ──────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "BARS", y); y = y - h

        -- Bar Texture | Bar Height
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Bar Texture",
              values = dmTexValues, order = dmTexOrder,
              getValue = function() return Cfg("barTexture") or "none" end,
              setValue = function(v) Set("barTexture", v); Refresh(); if ns.ApplySpellHistory then ns.ApplySpellHistory() end end },
            { type="slider", text="Bar Height", min = 8, max = 40, step = 1,
              getValue = function() return Cfg("barHeight") or 18 end,
              setValue = function(v) Set("barHeight", v); Refresh() end })
        y = y - h

        -- Bar Color | Bar Fill Opacity
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Color",
              swatches = {
                  { tooltip = "Class Color",
                    hasAlpha = false,
                    getValue = function()
                        local cc = EllesmereUI._playerClass and EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                        if cc then return cc.r, cc.g, cc.b end
                        return 0.96, 0.55, 0.73
                    end,
                    setValue = function() end,
                    onClick = function()
                        Set("showClassColor", true)
                        Refresh(); EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return Cfg("showClassColor") ~= false and 1 or 0.3
                    end },
                  { tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local c = Cfg("barColor")
                        if c then return c.r or 0.35, c.g or 0.55, c.b or 0.8 end
                        return 0.35, 0.55, 0.8
                    end,
                    setValue = function(r, g, b)
                        Set("barColor", { r = r, g = g, b = b })
                        Set("showClassColor", false); Set("barColorUseAccent", false)
                        Refresh(); EllesmereUI:RefreshPage()
                    end,
                    onClick = function(self)
                        if Cfg("showClassColor") ~= false or Cfg("barColorUseAccent") ~= false then
                            Set("showClassColor", false); Set("barColorUseAccent", false)
                            Refresh(); EllesmereUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        if Cfg("showClassColor") ~= false then return 0.15 end
                        return Cfg("barColorUseAccent") ~= false and 0.3 or 1
                    end },
                  { tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        return EllesmereUI.ResolveActiveAccent()
                    end,
                    setValue = function() end,
                    onClick = function()
                        Set("showClassColor", false); Set("barColorUseAccent", true)
                        Refresh(); EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        if Cfg("showClassColor") ~= false then return 0.15 end
                        return Cfg("barColorUseAccent") ~= false and 1 or 0.3
                    end },
              } },
            { type="slider", text="Opacity",
              min = 0, max = 1, step = 0.01,
              getValue = function() return Cfg("barFillAlpha") or 1 end,
              setValue = function(v) Set("barFillAlpha", v); Refresh() end })
        y = y - h

        -- Bar Spacing | Icon Style
        local iconRow, h = W:DualRow(parent, y,
            { type="slider", pixel=true, text="Spacing", min = -1, max = 10, step = 1,
            getValue = function() return Cfg("barSpacing") or 2 end,
            setValue = function(v) Set("barSpacing", v); Refresh() end },
            { type="dropdown", text="Icon Style",
              values = _G._EDM_IconStyleValues or {},
              order  = _G._EDM_IconStyleOrder or {},
              getValue = function() return Cfg("iconStyle") or "spec" end,
              setValue = function(v) Set("iconStyle", v); ApplyIconBrd(); Refresh(); EllesmereUI:RefreshPage() end })
        y = y - h

        -- Inline cog: Icon Zoom (right region, next to "Icon Style")
        do
            local rgn = iconRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Zoom",
                rows = {
                    { type = "slider", label = "Zoom", min = 0, max = 0.20, step = 0.01,
                    get = function() return Cfg("classIconZoom") or 0.06 end,
                    set = function(v) Set("classIconZoom", v); Refresh() end },
                },
            })
            -- Icon Zoom only affects the Spec + Blizzard icon styles; the sprite
            -- presets are pre-framed art, so grey + block the cog for those (and
            -- for "None", where there is no icon).
            local function zoomOff()
                local s = Cfg("iconStyle") or "spec"
                return s ~= "spec" and s ~= "blizzard"
            end
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(zoomOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self)
                if zoomOff() then
                    EllesmereUI.ShowWidgetTooltip(self, "Icon Zoom only applies to the Spec and Blizzard icon styles.")
                else
                    self:SetAlpha(0.7)
                end
            end)
            cogBtn:SetScript("OnLeave", function(self)
                EllesmereUI.HideWidgetTooltip()
                self:SetAlpha(zoomOff() and 0.15 or 0.4)
            end)
            cogBtn:SetScript("OnClick", function(self) if not zoomOff() then cogShow(self) end end)
            EllesmereUI.RegisterWidgetRefresh(function() cogBtn:SetAlpha(zoomOff() and 0.15 or 0.4) end)
        end

        -- Border Style (+ cog) | Border Size (+ inline swatch)
        -- Shadow (Glow rendered behind) needs Show Behind support, which DM lacks,
        -- so it is excluded from the Damage Meters border-style dropdown.
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        texValues.shadow = nil
        for i = #texOrder, 1, -1 do
            if texOrder[i] == "shadow" then table.remove(texOrder, i) end
        end
        local bsRow
        bsRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style",
              values=texValues, order=texOrder,
              getValue=function() return Cfg("borderTexture") or "solid" end,
              setValue=function(v)
                  Set("borderTexture", v)
                  Set("borderTextureOffset", nil)
                  Set("borderTextureOffsetY", nil)
                  Set("borderTextureShiftX", nil)
                  Set("borderTextureShiftY", nil)
                  if v ~= "solid" then
                      Set("borderR", 1); Set("borderG", 1); Set("borderB", 1); Set("borderA", 1)
                  else
                      Set("borderR", 0); Set("borderG", 0); Set("borderB", 0); Set("borderA", 1)
                  end
                  local defSz = EllesmereUI.GetBorderDefaultSize("damagemeters", v)
                  if defSz then Set("borderSize", defSz) end
                  ApplyBrd(); EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Border Size",
              min=0, max=4, step=1,
              getValue=function() return Cfg("borderSize") or 1 end,
              setValue=function(v) Set("borderSize", v); ApplyBrd() end })
        y = y - h
        -- Inline cog for border offset (left region)
        do
            local rgn = bsRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Border Options",
                rows = {
                    { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                      get = function()
                          local v = Cfg("borderTextureOffset")
                          if v then return v end
                          local tex = Cfg("borderTexture") or "solid"
                          local sz = Cfg("borderSize") or 1
                          local dox = EllesmereUI.GetBorderDefaults("damagemeters", tex, sz)
                          return dox
                      end,
                      set = function(v) Set("borderTextureOffset", v); ApplyBrd() end },
                    { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                      get = function()
                          local v = Cfg("borderTextureOffsetY")
                          if v then return v end
                          local tex = Cfg("borderTexture") or "solid"
                          local sz = Cfg("borderSize") or 1
                          local _, doy = EllesmereUI.GetBorderDefaults("damagemeters", tex, sz)
                          return doy
                      end,
                      set = function(v) Set("borderTextureOffsetY", v); ApplyBrd() end },
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function()
                          local v = Cfg("borderTextureShiftX")
                          if v then return v end
                          local tex = Cfg("borderTexture") or "solid"
                          local sz = Cfg("borderSize") or 1
                          local _, _, dsx = EllesmereUI.GetBorderDefaults("damagemeters", tex, sz)
                          return dsx
                      end,
                      set = function(v) Set("borderTextureShiftX", v == 0 and nil or v); ApplyBrd() end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function()
                          local v = Cfg("borderTextureShiftY")
                          if v then return v end
                          local tex = Cfg("borderTexture") or "solid"
                          local sz = Cfg("borderSize") or 1
                          local _, _, _, dsy = EllesmereUI.GetBorderDefaults("damagemeters", tex, sz)
                          return dsy
                      end,
                      set = function(v) Set("borderTextureShiftY", v == 0 and nil or v); ApplyBrd() end },
                    { type = "toggle", label = "Custom Icon Border",
                      get = function() return Cfg("customIconBorder") or false end,
                      set = function(v)
                          Set("customIconBorder", v)
                          ApplyIconBrd()
                          -- force=true: the row is added/removed at build time,
                          -- so the fast refresh path is not enough
                          EllesmereUI:RefreshPage(true)
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            local ctrl = rgn._control
            if ctrl then
                cogBtn:SetPoint("RIGHT", ctrl, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
            end
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            -- Always visible: the popup hosts the Custom Icon Border toggle,
            -- which must stay reachable for the solid style too (the offset
            -- sliders are harmless no-ops for solid).
        end
        -- Inline color swatch on Border Size (right region)
        do
            local rgn = bsRow._rightRegion
            local ctrl = rgn._control
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, bsRow:GetFrameLevel() + 3,
                function()
                    return Cfg("borderR") or 0, Cfg("borderG") or 0, Cfg("borderB") or 0, Cfg("borderA") or 1
                end,
                function(r, g, b, a)
                    Set("borderR", r); Set("borderG", g); Set("borderB", b); Set("borderA", a)
                    ApplyBrd()
                end,
                true, 20)
            PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(function() updateSwatch() end)
        end

        -- Icon Border row: shown only while "Custom Icon Border" is enabled
        -- (the toggle lives in the Border Style inline cog above). The whole
        -- block is skipped at build time; the toggle's set() rebuilds the page.
        if Cfg("customIconBorder") then
        local ibsRow
        ibsRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Icon Border Style",
            values=texValues, order=texOrder,
            getValue=function() return Cfg("iconBorderTexture") or "solid" end,
            setValue=function(v)
                Set("iconBorderTexture", v)
                Set("iconBorderTextureOffset", nil); Set("iconBorderTextureOffsetY", nil)
                Set("iconBorderTextureShiftX", nil); Set("iconBorderTextureShiftY", nil)
                if v ~= "solid" then
                    Set("iconBorderR", 1); Set("iconBorderG", 1); Set("iconBorderB", 1); Set("iconBorderA", 1)
                else
                    Set("iconBorderR", 0); Set("iconBorderG", 0); Set("iconBorderB", 0); Set("iconBorderA", 1)
                end
                local defSz = EllesmereUI.GetBorderDefaultSize("damagemeters_icon", v)
                if defSz then Set("iconBorderSize", defSz) end
                ApplyIconBrd(); EllesmereUI:RefreshPage()
            end },
            { type="slider", text="Icon Border Size",
            min=0, max=4, step=1,
            getValue=function() return Cfg("iconBorderSize") or 0 end,
            setValue=function(v) Set("iconBorderSize", v); ApplyIconBrd() end })
        y = y - h
        -- Inline cog for border offset (left region)
        do
            local rgn = ibsRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Border Offset",
                rows = {
                    { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                      get = function()
                          local v = Cfg("iconBorderTextureOffset")
                          if v then return v end
                          local tex = Cfg("iconBorderTexture") or "solid"
                          local sz = Cfg("iconBorderSize") or 1
                          local dox = EllesmereUI.GetBorderDefaults("damagemeters_icon", tex, sz)
                          return dox
                      end,
                      set = function(v) Set("iconBorderTextureOffset", v); ApplyIconBrd() end },
                    { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                      get = function()
                          local v = Cfg("iconBorderTextureOffsetY")
                          if v then return v end
                          local tex = Cfg("iconBorderTexture") or "solid"
                          local sz = Cfg("iconBorderSize") or 1
                          local _, doy = EllesmereUI.GetBorderDefaults("damagemeters_icon", tex, sz)
                          return doy
                      end,
                      set = function(v) Set("iconBorderTextureOffsetY", v); ApplyIconBrd() end },
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function()
                          local v = Cfg("iconBorderTextureShiftX")
                          if v then return v end
                          local tex = Cfg("iconBorderTexture") or "solid"
                          local sz = Cfg("iconBorderSize") or 1
                          local _, _, dsx = EllesmereUI.GetBorderDefaults("damagemeters_icon", tex, sz)
                          return dsx
                      end,
                      set = function(v) Set("iconBorderTextureShiftX", v == 0 and nil or v); ApplyIconBrd() end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function()
                          local v = Cfg("iconBorderTextureShiftY")
                          if v then return v end
                          local tex = Cfg("iconBorderTexture") or "solid"
                          local sz = Cfg("iconBorderSize") or 1
                          local _, _, _, dsy = EllesmereUI.GetBorderDefaults("damagemeters_icon", tex, sz)
                          return dsy
                      end,
                      set = function(v) Set("iconBorderTextureShiftY", v == 0 and nil or v); ApplyIconBrd() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            local ctrl = rgn._control
            if ctrl then
                cogBtn:SetPoint("RIGHT", ctrl, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
            end
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local function UpdateCogVis()
                local tex = Cfg("iconBorderTexture") or "solid"
                if tex == "solid" then cogBtn:Hide() else cogBtn:Show() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
        -- Inline color swatch on Border Size (right region)
        do
            local rgn = ibsRow._rightRegion
            local ctrl = rgn._control
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, ibsRow:GetFrameLevel() + 3,
                function()
                    return Cfg("iconBorderR") or 0, Cfg("iconBorderG") or 0, Cfg("iconBorderB") or 0, Cfg("iconBorderA") or 1
                end,
                function(r, g, b, a)
                    Set("iconBorderR", r); Set("iconBorderG", g); Set("iconBorderB", b); Set("iconBorderA", a)
                    ApplyIconBrd()
                end,
                true, 20)
            PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(function() updateSwatch() end)
        end
        end -- if Cfg("customIconBorder")

        -- Show Breakdown on Hover (+ inline cog) | Background (opacity + swatch)
        local bdRow
        bdRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Breakdown on Hover",
              getValue = function() return Cfg("showHoverTooltip") ~= false end,
              setValue = function(v) Set("showHoverTooltip", v) end },
            { type="slider", text="Background",
              min = 0, max = 1, step = 0.01,
              getValue = function() return Cfg("barBgAlpha") or 0 end,
              setValue = function(v) Set("barBgAlpha", v); if ns.ApplyBarBg then ns.ApplyBarBg() end end })
        -- Inline custom + class color swatches on Background (right region).
        -- Custom paints a fixed track color; class tints each bar's track with
        -- that player's class color. Mirrors the Left/Right Text Size swatches.
        do
            local rgn = bdRow._rightRegion
            local ctrl = rgn._control
            local barBgSwatch, barBgSwatchRefresh = EllesmereUI.BuildColorSwatch(
                rgn, bdRow:GetFrameLevel() + 3,
                function()
                    return (Cfg("barBgR") or 0), (Cfg("barBgG") or 0), (Cfg("barBgB") or 0)
                end,
                function(r, g, b)
                    Set("barBgUseClassColor", false)
                    Set("barBgR", r); Set("barBgG", g); Set("barBgB", b)
                    if ns.ApplyBarBg then ns.ApplyBarBg() end
                    EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(barBgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local origClick = barBgSwatch:GetScript("OnClick")
            barBgSwatch:SetScript("OnClick", function(self, ...)
                if Cfg("barBgUseClassColor") then
                    Set("barBgUseClassColor", false)
                    if ns.ApplyBarBg then ns.ApplyBarBg() end
                    EllesmereUI:RefreshPage()
                    return
                end
                if origClick then origClick(self, ...) end
            end)
            barBgSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(barBgSwatch, "Custom Color")
            end)
            barBgSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local barBgClassSwatch, barBgClassRefresh = EllesmereUI.BuildColorSwatch(
                rgn, bdRow:GetFrameLevel() + 3,
                function()
                    local clr = EllesmereUI._playerClass and EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                    if clr then return clr.r, clr.g, clr.b end
                    return 1, 1, 1
                end,
                function()
                    Set("barBgUseClassColor", true)
                    if ns.ApplyBarBg then ns.ApplyBarBg() end
                    EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(barBgClassSwatch, "RIGHT", barBgSwatch, "LEFT", -8, 0)
            barBgClassSwatch:SetScript("OnClick", function()
                Set("barBgUseClassColor", true)
                if ns.ApplyBarBg then ns.ApplyBarBg() end
                EllesmereUI:RefreshPage()
            end)
            barBgClassSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(barBgClassSwatch, "Class Color")
            end)
            barBgClassSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local function refreshBarBg()
                barBgSwatchRefresh(); barBgClassRefresh()
                local useClass = Cfg("barBgUseClassColor")
                barBgSwatch:SetAlpha(useClass and 0.3 or 1)
                barBgClassSwatch:SetAlpha(useClass and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(refreshBarBg)
            refreshBarBg()
        end
        do
            local rgn = bdRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Breakdown Settings",
                rows = {
                    { type = "dropdown", label = "Bar Texture",
                      values = matchTexValues, order = matchTexOrder,
                      get = function() return Cfg("breakdownBarTexture") or "match" end,
                      set = function(v) Set("breakdownBarTexture", v); Refresh() end },
                    { type = "slider", label = "Scale", min = 80, max = 150, step = 1,
                      get = function() return (Cfg("hoverTooltipScale") or 100) end,
                      set = function(v) Set("hoverTooltipScale", v) end },
                    { type = "toggle", label = "Show in Center of Screen",
                      get = function() return Cfg("breakdownAnchorPoint") == "center" end,
                      set = function(v) Set("breakdownAnchorPoint", v and "center" or "row") end },
                    { type = "toggle", label = "Show More Spells",
                      tooltip = "Show top 15 entries instead of 8.",
                      get = function() return Cfg("showAllBreakdownSpells") ~= false end,
                      set = function(v) Set("showAllBreakdownSpells", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end
        y = y - h

        -- ── BAR TEXT ────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "BAR TEXT", y); y = y - h

        -- Number Format | Hide Rank Numbers
        local hnRow
        hnRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Number Format",
              values = { [0] = "DPS", [1] = "Damage", [2] = "Damage (DPS)", [3] = "Damage | DPS" },
              order = { 0, 1, 2, 3 },
              getValue = function() return Cfg("numberFormat") or 2 end,
              setValue = function(v) Set("numberFormat", v); Refresh() end },
            { type="toggle", text="Hide Rank Numbers",
              tooltip = "Hides the rank number (1. 2. 3.) before each player name.",
              getValue = function() return Cfg("hideNumbers") or false end,
              setValue = function(v) Set("hideNumbers", v); Refresh() end })
        do
            local rgn = hnRow._rightRegion
            local suffix = rgn:CreateFontString(nil, "OVERLAY")
            suffix:SetFont(EllesmereUI.EXPRESSWAY, 11, "")
            suffix:SetTextColor(1, 1, 1, 0.35)
            local hnLabel
            for i = 1, rgn:GetNumRegions() do
                local reg = select(i, rgn:GetRegions())
                if reg and reg.GetText and EllesmereUI.EnKey(reg:GetText()) == "Hide Rank Numbers" then
                    hnLabel = reg
                    break
                end
            end
            if hnLabel then
                suffix:SetPoint("LEFT", hnLabel, "RIGHT", 5, 0)
            else
                suffix:SetPoint("LEFT", rgn, "LEFT", 150, 0)
            end
            suffix:SetText("(1, 2, 3)")
        end
        y = y - h

        -- Left Text Size (+ inline custom/class swatches) | Right Text Size (+ inline custom/class swatches)
        local btRow
        btRow, h = W:DualRow(parent, y,
            { type="slider", text="Left Text Size", min = 8, max = 18, step = 1,
              getValue = function() return Cfg("leftFontSize") or Cfg("fontSize") or 11 end,
              setValue = function(v) Set("leftFontSize", v); Refresh() end },
            { type="slider", text="Right Text Size", min = 8, max = 18, step = 1,
              getValue = function() return Cfg("rightFontSize") or Cfg("fontSize") or 11 end,
              setValue = function(v) Set("rightFontSize", v); Refresh() end })
        -- Left text inline swatches
        do
            local rgn = btRow._leftRegion
            local ctrl = rgn._control

            local customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(
                rgn, btRow:GetFrameLevel() + 3,
                function()
                    local c = Cfg("leftTextColor")
                    if c then return c.r or 1, c.g or 1, c.b or 1 end
                    return 1, 1, 1
                end,
                function(r, g, b)
                    Set("leftTextUseClassColor", false)
                    Set("leftTextColor", { r = r, g = g, b = b })
                    Refresh(); EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(customSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local origClick = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self, ...)
                if Cfg("leftTextUseClassColor") then
                    Set("leftTextUseClassColor", false)
                    Refresh(); EllesmereUI:RefreshPage()
                    return
                end
                if origClick then origClick(self, ...) end
            end)
            customSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color")
            end)
            customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local classSwatch, updateClass = EllesmereUI.BuildColorSwatch(
                rgn, btRow:GetFrameLevel() + 3,
                function()
                    local clr = EllesmereUI._playerClass and EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                    if clr then return clr.r, clr.g, clr.b end
                    return 1, 1, 1
                end,
                function()
                    Set("leftTextUseClassColor", true)
                    Refresh(); EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(classSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
            classSwatch:SetScript("OnClick", function()
                Set("leftTextUseClassColor", true)
                Refresh(); EllesmereUI:RefreshPage()
            end)
            classSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Color")
            end)
            classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local function refreshLeft()
                updateCustom(); updateClass()
                local useClass = Cfg("leftTextUseClassColor")
                customSwatch:SetAlpha(useClass and 0.3 or 1)
                classSwatch:SetAlpha(useClass and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(refreshLeft)
            refreshLeft()
        end
        -- Right text inline swatches
        do
            local rgn = btRow._rightRegion
            local ctrl = rgn._control

            local customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(
                rgn, btRow:GetFrameLevel() + 3,
                function()
                    local c = Cfg("rightTextColor")
                    if c then return c.r or 1, c.g or 1, c.b or 1 end
                    return 1, 1, 1
                end,
                function(r, g, b)
                    Set("rightTextUseClassColor", false)
                    Set("rightTextColor", { r = r, g = g, b = b })
                    Refresh(); EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(customSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local origClick = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self, ...)
                if Cfg("rightTextUseClassColor") then
                    Set("rightTextUseClassColor", false)
                    Refresh(); EllesmereUI:RefreshPage()
                    return
                end
                if origClick then origClick(self, ...) end
            end)
            customSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color")
            end)
            customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local classSwatch, updateClass = EllesmereUI.BuildColorSwatch(
                rgn, btRow:GetFrameLevel() + 3,
                function()
                    local clr = EllesmereUI._playerClass and EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                    if clr then return clr.r, clr.g, clr.b end
                    return 1, 1, 1
                end,
                function()
                    Set("rightTextUseClassColor", true)
                    Refresh(); EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(classSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
            classSwatch:SetScript("OnClick", function()
                Set("rightTextUseClassColor", true)
                Refresh(); EllesmereUI:RefreshPage()
            end)
            classSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Color")
            end)
            classSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local function refreshRight()
                updateCustom(); updateClass()
                local useClass = Cfg("rightTextUseClassColor")
                customSwatch:SetAlpha(useClass and 0.3 or 1)
                classSwatch:SetAlpha(useClass and 1 or 0.3)
            end
            EllesmereUI.RegisterWidgetRefresh(refreshRight)
            refreshRight()
        end
        y = y - h

        -- Force English Number Units (K/M/B) | (spacer)
        -- CJK clients only: zhCN/zhTW/koKR group numbers by wan/eok, so this
        -- offers K/M/B instead. Every other locale already gets K/M/B and the
        -- toggle would be a no-op, so the row is skipped for them.
        local clientLocale = GetLocale()
        if clientLocale == "zhCN" or clientLocale == "zhTW" or clientLocale == "koKR" then
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Force English Units (K/M/B)",
                  tooltip = "Always use K/M/B instead of localized units.",
                  getValue = function() return Cfg("forceEnglishUnits") or false end,
                  setValue = function(v)
                      Set("forceEnglishUnits", v)
                      if ns.RebuildNumberFormat then ns.RebuildNumberFormat() end
                      Refresh()
                  end },
                { type="spacer" })
            y = y - h
        end

        -- ── STANDALONE COMBAT TIMER ──────────────────────────────────
        _, h = W:SectionHeader(parent, "STANDALONE COMBAT TIMER", y); y = y - h

        local function ApplySAT() if ns.ApplySATimer then ns.ApplySATimer() end end

        -- Standalone Combat Timer (with inline cog) | Timer Text Color
        local satRow
        satRow, h = W:DualRow(parent, y,
            { type="toggle", text="Standalone Combat Timer",
              getValue = function() return Cfg("standaloneTimer") or false end,
              setValue = function(v)
                  Set("standaloneTimer", v); ApplySAT(); EllesmereUI:RefreshPage()
                  if v and ns.ShowSATimerPreview then ns.ShowSATimerPreview()
                  elseif not v and ns.HideSATimerPreview then ns.HideSATimerPreview() end
              end },
            { type="multiSwatch", text="Timer Text Color",
              disabled = function() return not Cfg("standaloneTimer") end,
              disabledTooltip = "Standalone Combat Timer",
              swatches = {
                  { tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local c = Cfg("standaloneTimerColor")
                        if c then return c.r or 1, c.g or 1, c.b or 1 end
                        return 1, 1, 1
                    end,
                    setValue = function(r, g, b)
                        Set("standaloneTimerColor", { r = r, g = g, b = b })
                        ApplySAT()
                    end,
                    onClick = function(self)
                        if Cfg("standaloneTimerUseAccent") then
                            Set("standaloneTimerUseAccent", false)
                            ApplySAT(); EllesmereUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        if not Cfg("standaloneTimer") then return 0.15 end
                        return Cfg("standaloneTimerUseAccent") and 0.3 or 1
                    end },
                  { tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        return EllesmereUI.ResolveActiveAccent()
                    end,
                    setValue = function() end,
                    onClick = function()
                        Set("standaloneTimerUseAccent", true)
                        ApplySAT(); EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        if not Cfg("standaloneTimer") then return 0.15 end
                        return Cfg("standaloneTimerUseAccent") and 1 or 0.3
                    end },
              } })
        -- Inline cog on Standalone Combat Timer for font size
        do
            local rgn = satRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Standalone Timer Settings",
                rows = {
                    { type = "slider", label = "Font Size", min = 10, max = 40, step = 1,
                      get = function() return Cfg("standaloneTimerSize") or 26 end,
                      set = function(v) Set("standaloneTimerSize", v); ApplySAT() end },
                    { type = "toggle", label = "Align Text Left",
                      disabled = function() return (Cfg("standaloneTimerAnchor") or "free") ~= "free" end,
                      disabledTooltip = "Available only when Anchor to Windows is set to Free Move.",
                      rawTooltip = true,
                      get = function()
                          local anchor = Cfg("standaloneTimerAnchor") or "free"
                          if anchor ~= "free" then
                              return anchor == "topleft" or anchor == "bottomleft"
                          end
                          return Cfg("standaloneTimerAlignLeft") or false
                      end,
                      set = function(v) Set("standaloneTimerAlignLeft", v); ApplySAT() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
        end
        y = y - h

        -- "Hold Shift+Click..." label | Anchor to Windows
        _, h = W:DualRow(parent, y,
            { type="label", text="Hold Shift+Click to Freely Move Standalone Timer" },
            { type="dropdown", text="Anchor to Windows",
              disabled = function() return not Cfg("standaloneTimer") end,
              disabledTooltip = "Standalone Combat Timer",
              values = { free = "Free Move", topleft = "Top Left", topright = "Top Right",
                         bottomleft = "Bottom Left", bottomright = "Bottom Right" },
              order = { "free", "topleft", "topright", "bottomleft", "bottomright" },
              getValue = function() return Cfg("standaloneTimerAnchor") or "free" end,
              setValue = function(v) Set("standaloneTimerAnchor", v); ApplySAT() end })
        y = y - h

        -- ── EXTRAS ───────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Spell Tooltips on Hover",
              tooltip="Show the game's spell tooltip when you hover a spell in a breakdown window.",
              getValue = function() return Cfg("showSpellTooltips") ~= false end,
              setValue = function(v) Set("showSpellTooltips", v) end },
            { type="label", text="" })
        y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Spell History options page
    ---------------------------------------------------------------------------
    local PAGE_SH = "Spell History"

    local function SHDB()
        local d = DB()
        if not d.spellHistory then d.spellHistory = {} end
        return d.spellHistory
    end

    local shGrowValues = {
        LEFT  = "Left",
        RIGHT = "Right",
        UP    = "Up",
        DOWN  = "Down",
    }
    local shGrowOrder = { "LEFT", "RIGHT", "UP", "DOWN" }

    local function RefreshSH()
        if ns.ApplySpellHistory then ns.ApplySpellHistory() end
    end

    local function BuildSpellHistoryPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local PP = EllesmereUI.PP
        local y = yOffset
        local h

        parent._showRowDivider = true

        local iconOff = function() return not SHDB().iconEnabled end
        local barOff = function() return not SHDB().barEnabled end

        -- =====================================================================
        --  ICON HISTORY
        -- =====================================================================
        _, h = W:SectionHeader(parent, "ICON HISTORY", y);  y = y - h

        -- Row 1: Enable Icon History | "Hold Shift+Click..." label
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Icon History",
              tooltip = "Shows a movable strip of recent spell icons. Shift-drag to reposition.",
              getValue = function() return SHDB().iconEnabled end,
              setValue = function(v)
                  SHDB().iconEnabled = v; RefreshSH()
                  EllesmereUI:RefreshPage()
              end },
            { type = "label", text = "Hold Shift+Click to Freely Move Icons" }
        );  y = y - h

        -- Row 2: Grow Direction | Visibility Options
        local SH_ICON_VIS_ITEMS = {
            { key = "iconHideInDungeon",      label = "Hide in Dungeons" },
            { key = "iconHideInRaid",         label = "Hide in Raids" },
            { key = "iconHideOutOfInstance",   label = "Hide out of Instances" },
        }
        local iconVisRow
        iconVisRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Grow Direction",
              tooltip = "Direction the icon strip grows as new spells are cast.",
              disabled = iconOff, disabledTooltip = "Icon History",
              values = shGrowValues, order = shGrowOrder,
              getValue = function() return SHDB().growDirection or "LEFT" end,
              setValue = function(v) SHDB().growDirection = v; RefreshSH() end },
            { type = "dropdown", text = "Visibility Options",
              disabled = iconOff, disabledTooltip = "Icon History",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end }
        );  y = y - h
        do
            local rgn = iconVisRow._rightRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2,
                SH_ICON_VIS_ITEMS,
                function(k) return SHDB()[k] or false end,
                function(k, v) SHDB()[k] = v; RefreshSH() end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Row 3: Icon Size (+ icon zoom cog) | Max Icons
        local shSizeRow
        shSizeRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Icon Size",
              min = 20, max = 60, step = 1,
              disabled = iconOff, disabledTooltip = "Icon History",
              getValue = function() return SHDB().iconSize or 36 end,
              setValue = function(v) SHDB().iconSize = v; RefreshSH() end },
            { type = "slider", text = "Max Icons",
              tooltip = "Maximum number of spell icons to display.",
              min = 1, max = 10, step = 1,
              disabled = iconOff, disabledTooltip = "Icon History",
              getValue = function() return SHDB().iconCount or 5 end,
              setValue = function(v) SHDB().iconCount = v; RefreshSH() end }
        );  y = y - h
        -- Inline cog on Icon Size: Icon Zoom (shared by the icon strip and the
        -- bar window, so it stays usable whenever either display is on).
        do
            local rgn = shSizeRow._leftRegion
            local shZoomOff = function() return iconOff() and barOff() end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Zoom",
                rows = {
                    { type = "slider", label = "Zoom", min = 0, max = 0.20, step = 0.01,
                      get = function() return SHDB().iconZoom or 0.08 end,
                      set = function(v) SHDB().iconZoom = v; RefreshSH() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(shZoomOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) if not shZoomOff() then self:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(shZoomOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) if not shZoomOff() then cogShow(self) end end)
            EllesmereUI.RegisterWidgetRefresh(function() cogBtn:SetAlpha(shZoomOff() and 0.15 or 0.4) end)
        end

        -- Row 4: Icon Spacing | Opacity
        _, h = W:DualRow(parent, y,
            { type = "slider", pixel = true, text = "Icon Spacing",
              min = 0, max = 10, step = 1,
              disabled = iconOff, disabledTooltip = "Icon History",
              getValue = function() return SHDB().iconSpacing or 1 end,
              setValue = function(v) SHDB().iconSpacing = v; RefreshSH() end },
            { type = "slider", text = "Opacity",
              min = 0.1, max = 1, step = 0.01,
              disabled = iconOff, disabledTooltip = "Icon History",
              getValue = function() return SHDB().iconOpacity or 1 end,
              setValue = function(v) SHDB().iconOpacity = v; RefreshSH() end }
        );  y = y - h

        -- Row 5: Animation Style | (empty)
        local shAnimValues = {
            none  = "None",
            slide = "Slide In",
            fly   = "Fly In",
        }
        local shAnimOrder = { "none", "slide", "fly" }
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Animation Style",
              disabled = iconOff, disabledTooltip = "Icon History",
              values = shAnimValues, order = shAnimOrder,
              getValue = function() return SHDB().iconAnimation or "slide" end,
              setValue = function(v) SHDB().iconAnimation = v end },
            { type = "label", text = "" }
        );  y = y - h

        -- =====================================================================
        --  BAR HISTORY
        -- =====================================================================
        _, h = W:SectionHeader(parent, "BAR HISTORY", y);  y = y - h

        -- Row 1: Enable Bar History | Visibility Options
        local SH_BAR_VIS_ITEMS = {
            { key = "barHideInDungeon",      label = "Hide in Dungeons" },
            { key = "barHideInRaid",         label = "Hide in Raids" },
            { key = "barHideOutOfInstance",   label = "Hide out of Instances" },
        }
        local barVisRow
        barVisRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Bar History",
              tooltip = "Shows a standalone window with spell cast history as bars. Matches your Damage Meters styling.",
              getValue = function() return SHDB().barEnabled end,
              setValue = function(v)
                  SHDB().barEnabled = v; RefreshSH()
                  EllesmereUI:RefreshPage()
              end },
            { type = "dropdown", text = "Visibility Options",
              disabled = barOff, disabledTooltip = "Bar History",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end }
        );  y = y - h
        do
            local rgn = barVisRow._rightRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2,
                SH_BAR_VIS_ITEMS,
                function(k) return SHDB()[k] or false end,
                function(k, v) SHDB()[k] = v; RefreshSH() end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Row 2: Background Opacity (+ inline color swatch) | Hide Top Bar
        local bgRow
        bgRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Background Opacity",
              min = 0, max = 1, step = 0.01,
              disabled = barOff, disabledTooltip = "Bar History",
              getValue = function() return SHDB().bgAlpha or 0.25 end,
              setValue = function(v) SHDB().bgAlpha = v; RefreshSH() end },
            { type = "toggle", text = "Hide Top Bar",
              disabled = barOff, disabledTooltip = "Bar History",
              getValue = function() return SHDB().hideTopBar end,
              setValue = function(v) SHDB().hideTopBar = v; RefreshSH() end }
        );  y = y - h
        do
            local rgn = bgRow._leftRegion
            local ctrl = rgn._control
            local swatch, swatchRefresh = EllesmereUI.BuildColorSwatch(
                rgn, bgRow:GetFrameLevel() + 3,
                function()
                    return (SHDB().bgR or 0), (SHDB().bgG or 0), (SHDB().bgB or 0)
                end,
                function(r, g, b)
                    SHDB().bgR = r; SHDB().bgG = g; SHDB().bgB = b; RefreshSH()
                end,
                false, 20)
            PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local block = CreateFrame("Frame", nil, swatch)
            block:SetAllPoints(); block:SetFrameLevel(swatch:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Bar History"))
            end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = barOff()
                swatch:SetAlpha(off and 0.3 or 1)
                if off then block:Show() else block:Hide() end
                swatchRefresh()
            end)
            local initOff = barOff()
            swatch:SetAlpha(initOff and 0.3 or 1)
            if initOff then block:Show() else block:Hide() end
        end

        -- Row 3: Bar Height | Max Bars
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Bar Height",
              min = 12, max = 32, step = 1,
              disabled = barOff, disabledTooltip = "Bar History",
              getValue = function() return SHDB().shBarHeight or 18 end,
              setValue = function(v) SHDB().shBarHeight = v; RefreshSH() end },
            { type = "slider", text = "Max Bars",
              tooltip = "Maximum number of bars to display. Window height adjusts automatically.",
              min = 1, max = 10, step = 1,
              disabled = barOff, disabledTooltip = "Bar History",
              getValue = function() return SHDB().maxBars or 5 end,
              setValue = function(v) SHDB().maxBars = v; RefreshSH() end }
        );  y = y - h

        -- Row 4: Bar Texture | Text Size (+ inline dual swatches)
        local textRow
        textRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Bar Texture",
              disabled = barOff, disabledTooltip = "Bar History",
              values = matchTexValues, order = matchTexOrder,
              getValue = function() return SHDB().spellHistoryBarTexture or "match" end,
              setValue = function(v) SHDB().spellHistoryBarTexture = v; RefreshSH() end },
            { type = "slider", text = "Text Size",
              min = 8, max = 16, step = 1,
              disabled = barOff, disabledTooltip = "Bar History",
              getValue = function() return SHDB().textSize or 11 end,
              setValue = function(v) SHDB().textSize = v; RefreshSH() end }
        );  y = y - h

        -- Row 5: Bar Color | Opacity
        _, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Bar Color",
              disabled = barOff, disabledTooltip = "Bar History",
              swatches = {
                  { tooltip = "Class Color",
                    hasAlpha = false,
                    getValue = function()
                        local cc = EllesmereUI._playerClass and EllesmereUI.GetClassColor(EllesmereUI._playerClass)
                        if cc then return cc.r, cc.g, cc.b end
                        return 0.96, 0.55, 0.73
                    end,
                    setValue = function() end,
                    onClick = function()
                        SHDB().barColorUseClass = true; SHDB().barColorUseAccent = false
                        RefreshSH(); EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        return SHDB().barColorUseClass and 1 or 0.3
                    end },
                  { tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local c = SHDB().barColor
                        if c then return c.r or 0.298, c.g or 0.565, c.b or 0.494 end
                        return 0.298, 0.565, 0.494
                    end,
                    setValue = function(r, g, b)
                        SHDB().barColor = { r = r, g = g, b = b }
                        SHDB().barColorUseClass = false; SHDB().barColorUseAccent = false
                        RefreshSH(); EllesmereUI:RefreshPage()
                    end,
                    onClick = function(self)
                        if SHDB().barColorUseClass or SHDB().barColorUseAccent then
                            SHDB().barColorUseClass = false; SHDB().barColorUseAccent = false
                            RefreshSH(); EllesmereUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        if SHDB().barColorUseClass then return 0.15 end
                        return SHDB().barColorUseAccent and 0.3 or 1
                    end },
                  { tooltip = "Accent Color",
                    hasAlpha = false,
                    getValue = function()
                        return EllesmereUI.ResolveActiveAccent()
                    end,
                    setValue = function() end,
                    onClick = function()
                        SHDB().barColorUseClass = false; SHDB().barColorUseAccent = true
                        RefreshSH(); EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        if SHDB().barColorUseClass then return 0.15 end
                        return SHDB().barColorUseAccent and 1 or 0.3
                    end },
              } },
            { type = "slider", text = "Opacity",
              min = 0.1, max = 1, step = 0.01,
              disabled = barOff, disabledTooltip = "Bar History",
              getValue = function() return SHDB().barOpacity or 1 end,
              setValue = function(v) SHDB().barOpacity = v; RefreshSH() end }
        );  y = y - h

        do
            local rgn = textRow._rightRegion
            local ctrl = rgn._control

            local customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(
                rgn, textRow:GetFrameLevel() + 3,
                function()
                    local c = SHDB().textColor
                    if c then return c.r or 1, c.g or 1, c.b or 1 end
                    return 1, 1, 1
                end,
                function(r, g, b)
                    SHDB().textColorUseAccent = false
                    SHDB().textColor = { r = r, g = g, b = b }
                    RefreshSH(); EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(customSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            local origClick = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self, ...)
                if SHDB().textColorUseAccent then
                    SHDB().textColorUseAccent = false
                    RefreshSH(); EllesmereUI:RefreshPage()
                    return
                end
                if origClick then origClick(self, ...) end
            end)
            customSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color")
            end)
            customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local accentSwatch, updateAccent = EllesmereUI.BuildColorSwatch(
                rgn, textRow:GetFrameLevel() + 3,
                function()
                    return EllesmereUI.ResolveActiveAccent()
                end,
                function()
                    SHDB().textColorUseAccent = true
                    RefreshSH(); EllesmereUI:RefreshPage()
                end,
                false, 20)
            PP.Point(accentSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
            accentSwatch:SetScript("OnClick", function()
                SHDB().textColorUseAccent = true
                RefreshSH(); EllesmereUI:RefreshPage()
            end)
            accentSwatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(accentSwatch, "Accent Color")
            end)
            accentSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local function MakeSwatchBlock(swatch)
                local block = CreateFrame("Frame", nil, swatch)
                block:SetAllPoints(); block:SetFrameLevel(swatch:GetFrameLevel() + 10)
                block:EnableMouse(true)
                block:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Bar History"))
                end)
                block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                return block
            end
            local customBlock = MakeSwatchBlock(customSwatch)
            local accentBlock = MakeSwatchBlock(accentSwatch)

            local function refreshTextSwatches()
                updateCustom(); updateAccent()
                local off = barOff()
                local useAccent = SHDB().textColorUseAccent
                customSwatch:SetAlpha(off and 0.3 or (useAccent and 0.3 or 1))
                accentSwatch:SetAlpha(off and 0.3 or (useAccent and 1 or 0.3))
                if off then customBlock:Show(); accentBlock:Show()
                else customBlock:Hide(); accentBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(refreshTextSwatches)
            refreshTextSwatches()
        end

        return math.abs(y)
    end

    EllesmereUI:RegisterModule("EllesmereUIDamageMeters", {
        title       = "Damage Meters",
        description = "Custom damage meter using Blizzard's built-in combat data.",
        searchTerms = "damage meters dps hps healing interrupts dispels spell history",
        pages       = { "Damage Meters", PAGE_SH },
        buildPage   = function(pageName, p, yOffset)
            -- This unconditionally forces every real damage-meter window
            -- (ns._windows, parented to UIParent) and the standalone timer
            -- preview live and mouse-interactive on screen -- not scoped to
            -- `p`/the hidden pre-build wrapper at all. During an off-screen
            -- search pre-build this would pop the player's real meter windows
            -- onto the screen with no interaction. Skip it; BuildPage/
            -- BuildSpellHistoryPage build purely onto `p`, so still index
            -- normally during the hidden pass.
            if not EllesmereUI._prebuilding then
                ns._optionsOpen = true
                if ns.ShowSATimerPreview and Cfg("standaloneTimer") then ns.ShowSATimerPreview() end
                if ns.ApplySpellHistory then ns.ApplySpellHistory() end
                for _, w in ipairs(ns._windows or {}) do
                    if w.frame then w.frame:SetAlpha(1); w.frame:EnableMouse(true); w.frame:Show() end
                end
            end
            if pageName == PAGE_SH then
                return BuildSpellHistoryPage(pageName, p, yOffset)
            end
            return BuildPage(pageName, p, yOffset)
        end,
        onPageCacheRestore = function()
            ns._optionsOpen = true
            if ns.ShowSATimerPreview and Cfg("standaloneTimer") then ns.ShowSATimerPreview() end
            if ns.ApplySpellHistory then ns.ApplySpellHistory() end
            for _, w in ipairs(ns._windows or {}) do
                if w.frame then w.frame:SetAlpha(1); w.frame:EnableMouse(true); w.frame:Show() end
            end
        end,
        onReset = function()
            local d = _G._EDM_DB
            if d and d.ResetProfile then d:ResetProfile() end
        end,
    })

    -- Show preview when panel opens on DM page, hide when panel closes
    if EllesmereUI.RegisterOnShow then
        EllesmereUI:RegisterOnShow(function()
            if EllesmereUI:GetActiveModule() == "EllesmereUIDamageMeters" then
                if ns.ShowSATimerPreview and Cfg("standaloneTimer") then ns.ShowSATimerPreview() end
                ns._optionsOpen = true
                for _, w in ipairs(ns._windows or {}) do
                    if w.frame then w.frame:SetAlpha(1); w.frame:EnableMouse(true); w.frame:Show() end
                end
                if ns.ApplySpellHistory then ns.ApplySpellHistory() end
            end
        end)
    end
    if EllesmereUI.RegisterOnHide then
        EllesmereUI:RegisterOnHide(function()
            if ns.HideSATimerPreview then ns.HideSATimerPreview() end
            ns._optionsOpen = false
            for _, w in ipairs(ns._windows or {}) do
                if w.UpdateVisibility then w.UpdateVisibility() end
            end
            if ns.ApplySpellHistory then ns.ApplySpellHistory() end
        end)
    end
end)
