-------------------------------------------------------------------------------
--  EUI_MythicTimer_Options.lua  —  Settings page for M+ Timer
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_DISPLAY = "Mythic+ Timer"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local db
    C_Timer.After(0, function() db = _G._EMT_AceDB end)

    local function DB()
        if not db then db = _G._EMT_AceDB end
        return db and db.profile
    end

    local function Cfg(key)
        local p = DB()
        return p and p[key]
    end

    local function Set(key, val)
        local p = DB()
        if p then p[key] = val end
    end

    -- Advanced-mode toggle removed: every option is always shown so the
    -- page can be trimmed deliberately. Guard kept as a stub so existing
    -- "if IsAdvanced() then ... end" blocks render unconditionally.
    local function IsAdvanced() return true end

    local function Refresh()
        if _G._EMT_Apply then _G._EMT_Apply() end
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
    end

    local function RebuildPage()
        if _G._EMT_Apply then _G._EMT_Apply() end
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage(true) end
    end

    local function BuildBarTexDropdown()
        if ns.AppendSharedMediaBarTextures then
            ns.AppendSharedMediaBarTextures()
        end

        local values, order = {}, {}
        local names = ns.barTextureNames or {}
        local textureOrder = ns.barTextureOrder or {}
        for _, key in ipairs(textureOrder) do
            if key ~= "---" then
                values[key] = names[key] or key
                order[#order + 1] = key
            end
        end

        local textureLookup = ns.barTextures or {}
        values._menuOpts = {
            itemHeight = 28,
            background = function(key)
                return textureLookup[key]
            end,
        }
        return values, order
    end

    -- Build Page
    -- Toggle preview + sync the Quest Tracker suppression so it doesn't sit
    -- on top of the M+ Timer preview frame.
    local function _setPreview(v)
        Set("showPreview", v)
        Refresh()
        if _G._EQT_SetSuppressed then
            _G._EQT_SetSuppressed("MTimerPreview", v == true)
        end
    end

    -- Auto-disable Show Preview when the EUI options window closes, so the
    -- preview frame doesn't linger after the user is done configuring.
    -- Installed once, the first time the M+ Timer page is built (which
    -- guarantees EllesmereUIFrame exists).
    local function _installPreviewAutoOff()
        local mf = _G.EllesmereUIFrame
        if not mf or mf._eMTPreviewHook then return end
        mf._eMTPreviewHook = true
        mf:HookScript("OnHide", function()
            if Cfg("showPreview") == true then
                _setPreview(false)
                EllesmereUI:RefreshPage()  -- update toggle visual immediately
            end
        end)
    end

    local function BuildPage(pageName, parent, yOffset)
        _installPreviewAutoOff()

        local W = EllesmereUI.Widgets
        local PP = EllesmereUI.PP
        local y = yOffset
        local row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        local function ApplyBorder() if ns.ApplyBorder then ns.ApplyBorder() end end

        local alignValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
        local alignOrder  = { "LEFT", "CENTER", "RIGHT" }
        local titleAffixPositionValues = {
            ABOVE_TIMER = "Above Timer",
            BELOW_TIMER = "Below Timer",
        }
        local titleAffixPositionOrder = { "ABOVE_TIMER", "BELOW_TIMER" }
        local objectiveTimePositionValues = { RIGHT = "Right", LEFT = "Left" }
        local objectiveTimePositionOrder = { "RIGHT", "LEFT" }
        local compareModeValues = {
          NONE = "None",
          DUNGEON = "Per Dungeon",
          LEVEL = "Per Dungeon + Level",
          LEVEL_AFFIX = "Per Dungeon + Level + Affixes",
        }
        local compareModeOrder = { "NONE", "DUNGEON", "LEVEL", "LEVEL_AFFIX" }
        local forcesTextValues = {
          PERCENT = "Percent",
          COUNT = "Count / Total",
          COUNT_PERCENT = "Count / Total + %",
          REMAINING = "Remaining Count",
        }
        local forcesTextOrder = { "PERCENT", "COUNT", "COUNT_PERCENT", "REMAINING" }

        -- ── DISPLAY ──────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

        local alignAllValues = { LEFT = "Left", RIGHT = "Right" }
        local alignAllOrder  = { "LEFT", "RIGHT" }

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Preview",
              getValue=function() return Cfg("showPreview") == true end,
              setValue=function(v) _setPreview(v) end },
            { type="dropdown", text="Text Align",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="the module",
              values=alignAllValues,
              order=alignAllOrder,
              getValue=function() return Cfg("alignAllText") or "RIGHT" end,
              setValue=function(v)
                  Set("alignAllText", v)
                  if _G._EMT_RebuildStandalone then _G._EMT_RebuildStandalone() end
                  Refresh()
              end })
        y = y - h

        -- Scale + Background Opacity: side-by-side dual row.
        local scaleRow
        scaleRow, h = W:DualRow(parent, y,
            { type="slider", text="Scale",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="the module",
              min=0.5, max=2.0, step=0.01, isPercent=false,
              getValue=function() return Cfg("scale") or 1.0 end,
              setValue=function(v) Set("scale", v); Refresh() end },
            { type="slider", text="Background Opacity",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="the module",
              min=0, max=100, step=5, isPercent=false,
              -- Stored 0..1 internally; displayed 0..100 to the user.
              getValue=function() return (Cfg("standaloneAlpha") or 0) * 100 end,
              setValue=function(v) Set("standaloneAlpha", v / 100); Refresh() end })
        y = y - h

        -- Inline RESIZE cog on Scale: Frame Width slider
        do
            local PP = EllesmereUI.PP
            local leftRgn = scaleRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Frame Width",
                rows = {
                    { type="slider", label="Width", min=180, max=420, step=1,
                      get=function() return Cfg("frameWidth") or 260 end,
                      set=function(v) Set("frameWidth", v); Refresh() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, leftRgn)
            cogBtn:SetSize(26, 26)
            PP.Point(cogBtn, "RIGHT", leftRgn._control or leftRgn, "LEFT", -6, 0)
            cogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            local function isDisabled() return Cfg("enabled") == false end
            local function UpdateAlpha() cogBtn:SetAlpha(isDisabled() and 0.15 or 0.4) end
            EllesmereUI.RegisterWidgetRefresh(UpdateAlpha)
            UpdateAlpha()
            cogBtn:SetScript("OnClick", function(self)
                if not isDisabled() then cogShow(self) end
            end)
            cogBtn:SetScript("OnEnter", function(self)
                if not isDisabled() then self:SetAlpha(0.75) end
            end)
            cogBtn:SetScript("OnLeave", function(self) UpdateAlpha() end)
        end

        local function _MakeAccentSwatches(useAccentKey, colorKey, defR, defG, defB)
            return {
                { tooltip = "Custom Color",
                  hasAlpha = false,
                  getValue = function()
                      local c = Cfg(colorKey)
                      if c then return c.r or defR, c.g or defG, c.b or defB end
                      return defR, defG, defB
                  end,
                  setValue = function(r, g, b)
                      Set(colorKey, { r = r, g = g, b = b })
                      Refresh()
                  end,
                  onClick = function(self)
                      if Cfg(useAccentKey) ~= false then
                          Set(useAccentKey, false)
                          Refresh(); EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      if Cfg("enabled") == false then return 0.15 end
                      return Cfg(useAccentKey) ~= false and 0.3 or 1
                  end },
                { tooltip = "Accent Color",
                  hasAlpha = false,
                  getValue = function()
                      local ar, ag, ab = EllesmereUI.ResolveActiveAccent()
                      return ar, ag, ab
                  end,
                  setValue = function() end,
                  onClick = function()
                      Set(useAccentKey, true)
                      Refresh(); EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      if Cfg("enabled") == false then return 0.15 end
                      return Cfg(useAccentKey) ~= false and 1 or 0.3
                  end },
            }
        end

        local function _MakeColorSwatch(colorKey, defR, defG, defB, afterSet)
            return {
                { tooltip = "Color",
                  hasAlpha = false,
                  getValue = function()
                      local c = Cfg(colorKey)
                      if c then return c.r or defR, c.g or defG, c.b or defB end
                      return defR, defG, defB
                  end,
                  setValue = function(r, g, b)
                      Set(colorKey, { r = r, g = g, b = b })
                      if afterSet then afterSet(r, g, b) end
                      Refresh()
                  end },
            }
        end

        local function _AttachPopupButton(rgn, icon, popupTitle, rows, isDisabled)
            local PP = EllesmereUI.PP
            local _, popupShow = EllesmereUI.BuildCogPopup({ title = popupTitle, rows = rows })
            local btn = CreateFrame("Button", nil, rgn)
            btn:SetSize(26, 26)
            -- Chain off any inline widget already on this region (swatch / earlier cog)
            -- so multiple inline controls sit side by side instead of overlapping.
            PP.Point(btn, "RIGHT", rgn._lastInline or rgn._control or rgn, "LEFT", -6, 0)
            rgn._lastInline = btn
            btn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local tex = btn:CreateTexture(nil, "OVERLAY")
            tex:SetAllPoints()
            tex:SetTexture(icon)
            local function UpdateAlpha()
                btn:SetAlpha(isDisabled() and 0.15 or 0.4)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateAlpha)
            UpdateAlpha()
            btn:SetScript("OnClick", function(self)
                if not isDisabled() then popupShow(self) end
            end)
            btn:SetScript("OnEnter", function(self)
                if not isDisabled() then self:SetAlpha(0.75) end
            end)
            btn:SetScript("OnLeave", function() UpdateAlpha() end)
        end

        -- Inline color swatch attached to a DualRow region (left of the control,
        -- chaining off rgn._lastInline so it coexists with an inline cog). Blocked
        -- + dimmed via overlay when isDisabled() is true, mirroring the cog pattern.
        local function _AttachInlineSwatch(rgn, colorKey, defR, defG, defB, afterSet, isDisabled, disabledTip)
            local PP = EllesmereUI.PP
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, rgn:GetFrameLevel() + 5,
                function()
                    local c = Cfg(colorKey)
                    if c then return c.r or defR, c.g or defG, c.b or defB, 1 end
                    return defR, defG, defB, 1
                end,
                function(r, g, b)
                    Set(colorKey, { r = r, g = g, b = b })
                    if afterSet then afterSet(r, g, b) end
                    Refresh()
                end,
                false, 18)
            PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control or rgn, "LEFT", -8, 0)
            rgn._lastInline = swatch
            local block = CreateFrame("Frame", nil, swatch)
            block:SetAllPoints()
            block:SetFrameLevel(swatch:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip(disabledTip or "the module"))
            end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateState()
                if updateSwatch then updateSwatch() end
                if isDisabled and isDisabled() then
                    swatch:SetAlpha(0.3); block:Show()
                else
                    swatch:SetAlpha(1); block:Hide()
                end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateState)
            UpdateState()
            return swatch
        end

        -- Attach the accent + custom colour pair (same behaviour as
        -- _MakeAccentSwatches) as two INLINE swatches on a DualRow region, chaining
        -- off rgn._lastInline. Click the accent swatch to follow the theme accent;
        -- click the custom swatch to switch to a custom colour (opens the picker).
        -- The inactive swatch dims to 0.3; both are blocked + dimmed with the
        -- requirement tooltip while isDisabled() is true (mirrors _AttachInlineSwatch).
        local function _AttachInlineAccentSwatches(rgn, useAccentKey, colorKey, defR, defG, defB, isDisabled, disabledTip)
            local PP = EllesmereUI.PP

            -- Accent swatch (nearest the control): live theme accent.
            local accentSwatch, updateAccent = EllesmereUI.BuildColorSwatch(
                rgn, rgn:GetFrameLevel() + 5,
                function()
                    local ar, ag, ab = EllesmereUI.ResolveActiveAccent()
                    return ar, ag, ab, 1
                end,
                function() end, false, 18)
            accentSwatch:SetScript("OnClick", function()
                Set(useAccentKey, true); Refresh(); EllesmereUI:RefreshPage()
            end)
            PP.Point(accentSwatch, "RIGHT", rgn._lastInline or rgn._control or rgn, "LEFT", -8, 0)
            rgn._lastInline = accentSwatch

            -- Custom-colour swatch (to the left of accent): the stored custom colour.
            local customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(
                rgn, rgn:GetFrameLevel() + 5,
                function()
                    local c = Cfg(colorKey)
                    if c then return c.r or defR, c.g or defG, c.b or defB, 1 end
                    return defR, defG, defB, 1
                end,
                function(r, g, b)
                    Set(colorKey, { r = r, g = g, b = b }); Refresh()
                end, false, 18)
            -- Preserve BuildColorSwatch's picker click, but while accent mode is on a
            -- click just switches back to custom mode (accent turns off) instead.
            local openPicker = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self)
                if Cfg(useAccentKey) ~= false then
                    Set(useAccentKey, false); Refresh(); EllesmereUI:RefreshPage()
                    return
                end
                if openPicker then openPicker(self) end
            end)
            PP.Point(customSwatch, "RIGHT", rgn._lastInline or rgn._control or rgn, "LEFT", -8, 0)
            rgn._lastInline = customSwatch

            -- Per-swatch hover tooltip (colour name when enabled) + disabled block.
            local function AddBlock(sw, enterTip)
                sw:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(sw, enterTip) end)
                sw:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local block = CreateFrame("Frame", nil, sw)
                block:SetAllPoints(); block:SetFrameLevel(sw:GetFrameLevel() + 10); block:EnableMouse(true)
                block:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(sw, EllesmereUI.DisabledTooltip(disabledTip or "the module"))
                end)
                block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                sw._block = block
            end
            AddBlock(accentSwatch, "Accent Color")
            AddBlock(customSwatch, "Custom Color")

            local function UpdateState()
                if updateAccent then updateAccent() end
                if updateCustom then updateCustom() end
                local disabled = isDisabled and isDisabled()
                local useAccent = Cfg(useAccentKey) ~= false
                if disabled then
                    accentSwatch:SetAlpha(0.15); accentSwatch._block:Show()
                    customSwatch:SetAlpha(0.15); customSwatch._block:Show()
                else
                    accentSwatch:SetAlpha(useAccent and 1 or 0.3); accentSwatch._block:Hide()
                    customSwatch:SetAlpha(useAccent and 0.3 or 1); customSwatch._block:Hide()
                end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateState)
            UpdateState()
        end

        local timerDisplayValues = {
            REMAINING       = "11:37",
            REMAINING_TOTAL = "11:37 / 33:00",
            ELAPSED         = "21:23",
            ELAPSED_DETAIL  = "21:23 (11:37 / 33:00)",
        }
        local timerDisplayOrder = { "REMAINING", "REMAINING_TOTAL", "ELAPSED", "ELAPSED_DETAIL" }
        local timerBarStyleValues = { TICKS = "Ticks", SEGMENTS = "Gaps" }
        local timerBarStyleOrder = { "TICKS", "SEGMENTS" }
        local texValues, texOrder = BuildBarTexDropdown()

        _, h = W:SectionHeader(parent, "TITLE", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Title",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="the module",
              getValue=function() return Cfg("showTitle") ~= false end,
              setValue=function(v) Set("showTitle", v); Refresh() end },
            { type="slider", text="Title Size", min=8, max=24, step=1, trackWidth=130,
              disabled=function() return Cfg("enabled") == false or Cfg("showTitle") == false end,
              disabledTooltip="Show Title",
              getValue=function() return Cfg("titleSize") or 16 end,
              setValue=function(v) Set("titleSize", v); Refresh() end })
        -- Regular-cog settings popup on Show Title: Show Dungeon Name (default on;
        -- when off the title shows only the +key level, not the dungeon name).
        _AttachPopupButton(row._leftRegion, EllesmereUI.COGS_ICON, "Title", {
            { type="toggle", label="Show Dungeon Name",
              get=function() return Cfg("showDungeonName") ~= false end,
              set=function(v) Set("showDungeonName", v); Refresh() end },
            -- Moves the lone "+key" title down onto the timer line as "+21  |  timer".
            -- Only meaningful when the dungeon name is hidden, so it is gated on that.
            { type="toggle", label="Show Key Level on Timer",
              disabled=function() return Cfg("showDungeonName") ~= false end,
              disabledTooltip="Show Dungeon Name", requireState="disabled",
              get=function() return Cfg("showKeyLevelOnTimer") == true end,
              set=function(v) Set("showKeyLevelOnTimer", v); Refresh() end },
            { type="slider", pixel=true, label="Spacing", min=0, max=40, step=1,
              disabled=function() return Cfg("showKeyLevelOnTimer") ~= true end,
              disabledTooltip="Show Key Level on Timer",
              get=function() return Cfg("keyLevelTimerSpacing") or 8 end,
              set=function(v) Set("keyLevelTimerSpacing", v); Refresh() end },
        }, function() return Cfg("enabled") == false or Cfg("showTitle") == false end)
        -- Inline accent + custom colour swatches on the Title Size slider.
        _AttachInlineAccentSwatches(row._rightRegion, "titleUseAccent", "titleColor", 1, 1, 1,
            function() return Cfg("enabled") == false or Cfg("showTitle") == false end, "Show Title")
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Affix",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="the module",
              getValue=function() return Cfg("showAffixes") ~= false end,
              setValue=function(v) Set("showAffixes", v); Refresh() end },
            { type="dropdown", text="Position",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="the module",
              values=titleAffixPositionValues,
              order=titleAffixPositionOrder,
              getValue=function() return Cfg("titleAffixPosition") or "ABOVE_TIMER" end,
              setValue=function(v) Set("titleAffixPosition", v); Refresh(); EllesmereUI:RefreshPage() end })
        -- Inline Affix Color swatch on Show Affix (swatch before cog), then Affix Size cog
        _AttachInlineSwatch(row._leftRegion, "affixTextColor", 1, 1, 1, nil,
            function() return Cfg("enabled") == false or Cfg("showAffixes") == false end, "Show Affix")
        _AttachPopupButton(row._leftRegion, EllesmereUI.RESIZE_ICON, "Affix Size", {
            { type="slider", label="Size", min=6, max=20, step=1,
              get=function() return Cfg("affixSize") or 12 end,
              set=function(v) Set("affixSize", v); Refresh() end },
        }, function() return Cfg("enabled") == false or Cfg("showAffixes") == false end)
        -- Title/Affix Spacing cog on Position (now the right-side widget)
        _AttachPopupButton(row._rightRegion, EllesmereUI.RESIZE_ICON, "Title/Affix Spacing", {
            { type="slider", pixel=true, label="Death Gap", min=-10, max=30, step=1,
              disabled=function() return (Cfg("titleAffixPosition") or "ABOVE_TIMER") == "BELOW_TIMER" end,
              disabledTooltip="Above Timer",
              get=function() return Cfg("titleAffixDeathGap") or 11 end,
              set=function(v) Set("titleAffixDeathGap", v); Refresh() end },
            { type="slider", pixel=true, label="Timer Gap", min=-10, max=30, step=1,
              disabled=function() return (Cfg("titleAffixPosition") or "ABOVE_TIMER") ~= "BELOW_TIMER" end,
              disabledTooltip="Below Timer",
              get=function() return Cfg("titleAffixTimerGap") or Cfg("titleAffixSandwichGap") or 6 end,
              set=function(v) Set("titleAffixTimerGap", v); Refresh() end },
            { type="slider", pixel=true, label="Bar Gap", min=-10, max=30, step=1,
              disabled=function() return (Cfg("titleAffixPosition") or "ABOVE_TIMER") ~= "BELOW_TIMER" end,
              disabledTooltip="Below Timer",
              get=function() return Cfg("titleAffixBarGap") or Cfg("titleAffixSandwichGap") or 6 end,
              set=function(v) Set("titleAffixBarGap", v); Refresh() end },
        }, function() return Cfg("enabled") == false end)
        y = y - h

        _, h = W:SectionHeader(parent, "TIMER", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="slider", text="Timer Size",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="the module",
              min=10, max=32, step=1, isPercent=false,
              getValue=function() return Cfg("timerTextSize") or 20 end,
              setValue=function(v) Set("timerTextSize", v); Refresh() end },
            { type="dropdown", text="Timer Format",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="the module",
              values=timerDisplayValues,
              order=timerDisplayOrder,
              getValue=function() return Cfg("timerDisplayMode") or "REMAINING_TOTAL" end,
              setValue=function(v) Set("timerDisplayMode", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Timer Bar",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="the module",
              getValue=function() return Cfg("showTimerBar") ~= false end,
              setValue=function(v)
                  Set("showTimerBar", v)
                  if not v and Cfg("timerInBar") then Set("timerInBar", false) end
                  Refresh(); EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Move Timer Inside Bar",
              disabled=function() return Cfg("enabled") == false or Cfg("showTimerBar") == false end,
              disabledTooltip=function() if Cfg("showTimerBar") == false then return "Show Timer Bar" end return "the module" end,
              getValue=function() return Cfg("timerInBar") == true end,
              setValue=function(v) Set("timerInBar", v); Refresh(); EllesmereUI:RefreshPage() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="slider", text="Bar Height",
              disabled=function() return Cfg("enabled") == false or Cfg("showTimerBar") == false end,
              disabledTooltip="Show Timer Bar",
              min=4, max=30, step=1, isPercent=false,
              getValue=function() return Cfg("barHeight") or 8 end,
              setValue=function(v) Set("barHeight", v); Refresh() end },
            { type="slider", text="Bar Width",
              disabled=function() return Cfg("enabled") == false or Cfg("showTimerBar") == false end,
              disabledTooltip="Show Timer Bar",
              min=120, max=420, step=1, isPercent=false,
              getValue=function() return Cfg("barWidth") or 210 end,
              setValue=function(v) Set("barWidth", v); Refresh() end })
        _AttachPopupButton(row._leftRegion, EllesmereUI.RESIZE_ICON, "Bar Height Options", {
            { type="slider", label="Expanded Height", min=8, max=40, step=1,
              get=function() return Cfg("barHeightExpanded") or 22 end,
              set=function(v) Set("barHeightExpanded", v); Refresh() end },
            { type="slider", label="Expanded Fill", min=0, max=1, step=0.05,
              get=function() return Cfg("barFillAlphaExpanded") or 0.85 end,
              set=function(v) Set("barFillAlphaExpanded", v); Refresh() end },
            { type="toggle", label="Left Text",
              get=function() return Cfg("timerInBarLeftText") == true end,
              set=function(v) Set("timerInBarLeftText", v); Refresh() end },
        }, function() return Cfg("enabled") == false or Cfg("showTimerBar") == false end)
        y = y - h

        local timerFontValues, timerFontOrder = EllesmereUI.BuildFontDropdownData()
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Bar Texture",
              disabled=function() return Cfg("enabled") == false or Cfg("showTimerBar") == false end,
              disabledTooltip="Show Timer Bar",
              values=texValues,
              order=texOrder,
              getValue=function() return Cfg("barTexture") or "none" end,
              setValue=function(v) Set("barTexture", v); Refresh() end },
            { type="dropdown", text="Timer Font",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="the module",
              values=timerFontValues,
              order=timerFontOrder,
              getValue=function() return Cfg("timerFont") or "__global" end,
              setValue=function(v) Set("timerFont", v); Refresh() end })
        -- Inline cog on Bar Texture: the bar's background texture
        _AttachPopupButton(row._leftRegion, EllesmereUI.COGS_ICON, "Bar Texture", {
            { type="dropdown", label="Background Texture",
              values=texValues, order=texOrder,
              get=function() return Cfg("barBgTexture") or "none" end,
              set=function(v) Set("barBgTexture", v); Refresh() end },
            { type="toggle", label="Custom Border Style",
              tooltip="Show the border style and size controls for the timer bars.",
              get=function() return Cfg("customBorderStyle") == true end,
              set=function(v) Set("customBorderStyle", v); ApplyBorder(); EllesmereUI:RefreshPage(true) end },
        }, function() return Cfg("enabled") == false or Cfg("showTimerBar") == false end)
        y = y - h

        --Border Style (+ cog) | Border Size (+ inline swatch)
        -- Only built when "Custom Border Style" (in the Bar Texture cog above)
        -- is on, so the whole row plus its offset cog and colour swatch stay
        -- hidden by default and reclaim their space when off.
        if Cfg("customBorderStyle") then
        -- Distinct local names on purpose: this border-texture list must NOT
        -- shadow the bar-texture "texValues"/"texOrder" (declared above), which
        -- the Forces bar Texture + Background Texture dropdowns further down
        -- still reference. Shadowing them fed border textures into those bar
        -- dropdowns and let a border key get written into the shared barTexture.
        local borderTexValues, borderTexOrder = EllesmereUI.GetBorderTextureDropdown()
        borderTexValues.shadow = nil
        for i = #borderTexOrder, 1, -1 do
            if borderTexOrder[i] == "shadow" then table.remove(borderTexOrder, i) end
        end

        local bsRow
        bsRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style",
                values=borderTexValues, order=borderTexOrder,
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
                    local defSz = EllesmereUI.GetBorderDefaultSize("MythicPlus", v)
                    if defSz then Set("borderSize", defSz) end
                    ApplyBorder(); EllesmereUI:RefreshPage()
                end },
            { type="slider", text="Border Size",
                min=0, max=4, step=1,
                getValue=function() return Cfg("borderSize") or 1 end,
                setValue=function(v) Set("borderSize", v); ApplyBorder(); EllesmereUI:RefreshPage() end })
            y = y - h
            -- Inline cog for border offset (left region)
            do
                local rgn = bsRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Options",
                    rows = {
                        { type = "toggle", label = "Apply to Forces Bar",
                            get = function() return Cfg("borderApplyToForces") ~= false end,
                            set = function(v) Set("borderApplyToForces", v); ApplyBorder() end },
                        { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                            get = function()
                                local v = Cfg("borderTextureOffset")
                                if v then return v end
                                local tex = Cfg("borderTexture") or "solid"
                                local sz = Cfg("borderSize") or 1
                                local dox = EllesmereUI.GetBorderDefaults("MythicPlus", tex, sz)
                                return dox
                            end,
                            set = function(v) Set("borderTextureOffset", v); ApplyBorder() end },
                        { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                            get = function()
                                local v = Cfg("borderTextureOffsetY")
                                if v then return v end
                                local tex = Cfg("borderTexture") or "solid"
                                local sz = Cfg("borderSize") or 1
                                local _, doy = EllesmereUI.GetBorderDefaults("MythicPlus", tex, sz)
                                return doy
                            end,
                            set = function(v) Set("borderTextureOffsetY", v); ApplyBorder() end },
                        { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                            get = function()
                                local v = Cfg("borderTextureShiftX")
                                if v then return v end
                                local tex = Cfg("borderTexture") or "solid"
                                local sz = Cfg("borderSize") or 1
                                local _, _, dsx = EllesmereUI.GetBorderDefaults("MythicPlus", tex, sz)
                                return dsx
                            end,
                            set = function(v) Set("borderTextureShiftX", v == 0 and nil or v); ApplyBorder() end },
                        { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                            get = function()
                                local v = Cfg("borderTextureShiftY")
                                if v then return v end
                                local tex = Cfg("borderTexture") or "solid"
                                local sz = Cfg("borderSize") or 1
                                local _, _, _, dsy = EllesmereUI.GetBorderDefaults("MythicPlus", tex, sz)
                                return dsy
                            end,
                            set = function(v) Set("borderTextureShiftY", v == 0 and nil or v); ApplyBorder() end },
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
                end
                -- Inline color swatch on Border Size (right region)
                do
                    local rgn = bsRow._rightRegion
                    local ctrl = rgn._control
                    local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                        rgn, rgn:GetFrameLevel() + 3,
                        function()
                            return Cfg("borderR") or 0, Cfg("borderG") or 0, Cfg("borderB") or 0, Cfg("borderA") or 1
                        end,
                        function(r, g, b, a)
                            Set("borderR", r); Set("borderG", g); Set("borderB", b); Set("borderA", a)
                            ApplyBorder()
                        end,
                        true, 20)
                    PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
                    EllesmereUI.RegisterWidgetRefresh(function() updateSwatch() end)
                end
        end

        -- Builds a threshold toggle config plus an attach() that hangs the inline
        -- RESIZE cog (white text / size / x / y) and the colour swatch onto a given
        -- DualRow region, so two thresholds can share one dual row.
        local function _ThresholdWidget(label, barColorKey, showKey, sizeKey, offsetXKey, offsetYKey, whiteKey, defR, defG, defB, afterBarSet)
            local function IsTimerTextShown()
                if showKey == "showThreshRemaining" then
                    return Cfg(showKey) == true
                end
                return Cfg(showKey) ~= false
            end

            local cfg = { type="toggle", text="Show " .. label .. " Timer Text",
                  tooltip="Show Timer Text",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="the module",
                  getValue=IsTimerTextShown,
                  setValue=function(v) Set(showKey, v); Refresh() end }

            local function attach(rgn)
                -- Inline colour swatch (the +N threshold / segment colour) first so it
                -- sits adjacent to the control, before the cog (swatch-before-cog rule).
                _AttachInlineSwatch(rgn, barColorKey, defR, defG, defB, afterBarSet,
                    function() return Cfg("enabled") == false end, "the module")
                -- Inline RESIZE cog (white text / size / x / y) on the toggle
                _AttachPopupButton(rgn, EllesmereUI.RESIZE_ICON, label .. " Timer Text", {
                    { type="toggle", label="White Text",
                      get=function() return Cfg(whiteKey) == true end,
                      set=function(v) Set(whiteKey, v); Refresh() end },
                    { type="slider", label="Text Size", min=6, max=20, step=1,
                      get=function() return Cfg(sizeKey) or Cfg("thresholdSize") or 12 end,
                      set=function(v) Set(sizeKey, v); Refresh() end },
                    { type="slider", label="Text X", min=-80, max=80, step=1,
                      get=function() return Cfg(offsetXKey) or Cfg("thresholdTextOffsetX") or 0 end,
                      set=function(v) Set(offsetXKey, v); Refresh() end },
                    { type="slider", label="Text Y", min=-40, max=40, step=1,
                      get=function() return Cfg(offsetYKey) or Cfg("thresholdTextOffsetY") or 0 end,
                      set=function(v) Set(offsetYKey, v); Refresh() end },
                }, function() return Cfg("enabled") == false or not IsTimerTextShown() end)
            end

            return cfg, attach
        end

        _, h = W:SectionHeader(parent, "THRESHOLDS", y); y = y - h

        local p3cfg, p3attach = _ThresholdWidget("+3 Threshold", "timerSegment1Color", "showPlusThreeTimer", "thresholdPlusThreeSize", "thresholdPlusThreeTextOffsetX", "thresholdPlusThreeTextOffsetY", "thresholdPlusThreeTextWhite", 0.4, 1, 0.4,
            function(r, g, b) Set("timerPlusThreeColor", { r = r, g = g, b = b }) end)
        local p2cfg, p2attach = _ThresholdWidget("+2 Threshold", "timerSegment2Color", "showPlusTwoTimer", "thresholdPlusTwoSize", "thresholdPlusTwoTextOffsetX", "thresholdPlusTwoTextOffsetY", "thresholdPlusTwoTextWhite", 0.3, 0.8, 1,
            function(r, g, b) Set("timerPlusTwoColor", { r = r, g = g, b = b }) end)
        local p1cfg, p1attach = _ThresholdWidget("+1 Threshold", "timerSegment3Color", "showThreshRemaining", "thresholdPlusOneSize", "thresholdPlusOneTextOffsetX", "thresholdPlusOneTextOffsetY", "thresholdPlusOneTextWhite", 0.69, 0.35, 0.8)

        -- Row 1: Ticks / Gaps (style + inline Tick Color swatch + cog) | +3 Threshold
        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Ticks / Gaps",
              disabled=function() return Cfg("enabled") == false or Cfg("showTimerBar") == false end,
              disabledTooltip="Show Timer Bar",
              values=timerBarStyleValues,
              order=timerBarStyleOrder,
              getValue=function() return Cfg("timerBarStyle") or "TICKS" end,
              setValue=function(v) Set("timerBarStyle", v); Refresh(); EllesmereUI:RefreshPage() end },
            p3cfg)
        -- Inline Tick Color swatch (TICKS style only) first so it sits adjacent to
        -- the control, before the cog (swatch-before-cog rule).
        _AttachInlineSwatch(row._leftRegion, "timerTickColor", 1, 1, 1, nil,
            function() return Cfg("enabled") == false or Cfg("showTimerBar") == false or (Cfg("timerBarStyle") or "TICKS") ~= "TICKS" end, "Ticks")
        _AttachPopupButton(row._leftRegion, EllesmereUI.COGS_ICON, "Ticks / Gaps", {
            { type="slider", label="Tick Opacity", min=0, max=1, step=0.05,
              disabled=function() return (Cfg("timerBarStyle") or "TICKS") ~= "TICKS" end,
              disabledTooltip="Ticks",
              get=function() return Cfg("tickAlpha") or 1 end,
              set=function(v) Set("tickAlpha", v); Refresh() end },
            { type="slider", pixel=true, label="Gap Size", min=0, max=12, step=1,
              disabled=function() return (Cfg("timerBarStyle") or "TICKS") ~= "SEGMENTS" end,
              disabledTooltip="Gaps",
              get=function() return Cfg("timerBarSegmentGap") or 2 end,
              set=function(v) Set("timerBarSegmentGap", v); Refresh() end },
        }, function() return Cfg("enabled") == false or Cfg("showTimerBar") == false end)
        p3attach(row._rightRegion)
        y = y - h

        -- Row 2: +2 Threshold | +1 Threshold
        row, h = W:DualRow(parent, y, p2cfg, p1cfg)
        p2attach(row._leftRegion)
        p1attach(row._rightRegion)
        y = y - h

        _, h = W:SectionHeader(parent, "FORCES", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Enemy Forces",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="the module",
              getValue=function() return Cfg("showEnemyBar") ~= false end,
              setValue=function(v) Set("showEnemyBar", v); Refresh(); EllesmereUI:RefreshPage() end },
            { type="dropdown", text="Enemy Text Format",
              disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
              disabledTooltip="Show Enemy Forces",
              values=forcesTextValues,
              order=forcesTextOrder,
              getValue=function() return Cfg("enemyForcesTextFormat") or "PERCENT" end,
              setValue=function(v) Set("enemyForcesTextFormat", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Enemy Forces %",
              disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
              disabledTooltip="Show Enemy Forces",
              values={ LABEL = "In Label Text", BAR = "In Bar", BESIDE = "Beside Bar" },
              order={ "LABEL", "BAR", "BESIDE" },
              getValue=function() return Cfg("enemyForcesPctPos") or "LABEL" end,
              setValue=function(v) Set("enemyForcesPctPos", v); Refresh() end },
            { type="dropdown", text="Enemy Forces Position",
              disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
              disabledTooltip="Show Enemy Forces",
              values={ BOTTOM = "Bottom", UNDER_BAR = "Under Timer Bar" },
              order={ "BOTTOM", "UNDER_BAR" },
              getValue=function() return Cfg("enemyForcesPos") or "BOTTOM" end,
              setValue=function(v) Set("enemyForcesPos", v); Refresh() end })
        _AttachPopupButton(row._leftRegion, EllesmereUI.RESIZE_ICON, "Enemy Forces Text", {
            { type="toggle", label="Hide Label",
              get=function() return Cfg("hideEnemyForcesLabel") == true end,
              set=function(v) Set("hideEnemyForcesLabel", v); Refresh() end },
            { type="slider", label="Text Size", min=8, max=24, step=1,
              get=function() return Cfg("enemyForcesTextSize") or Cfg("objectivesSize") or 12 end,
              set=function(v) Set("enemyForcesTextSize", v); Refresh() end },
            { type="slider", label="Text X", min=-80, max=80, step=1,
              get=function() return Cfg("enemyForcesTextOffsetX") or 0 end,
              set=function(v) Set("enemyForcesTextOffsetX", v); Refresh() end },
            { type="slider", label="Text Y", min=-40, max=40, step=1,
              get=function() return Cfg("enemyForcesTextOffsetY") or 0 end,
              set=function(v) Set("enemyForcesTextOffsetY", v); Refresh() end },
        }, function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end)
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Bar Texture",
              disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
              disabledTooltip="Show Enemy Forces",
              values=texValues,
              order=texOrder,
              getValue=function() return Cfg("enemyBarTexture") or "none" end,
              setValue=function(v) Set("enemyBarTexture", v); Refresh() end },
            { type="multiSwatch", text="Enemy Bar Color",
              disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
              disabledTooltip="Show Enemy Forces",
              swatches = _MakeAccentSwatches("enemyBarUseAccent", "enemyBarColor", 0.35, 0.55, 0.8) })
        -- Inline cog on Bar Texture: the bar's background texture
        _AttachPopupButton(row._leftRegion, EllesmereUI.COGS_ICON, "Bar Texture", {
            { type="dropdown", label="Background Texture",
              values=texValues, order=texOrder,
              get=function() return Cfg("enemyBarBgTexture") or "none" end,
              set=function(v) Set("enemyBarBgTexture", v); Refresh() end },
        }, function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end)
        y = y - h

        _, h = W:SectionHeader(parent, "BOSS OBJECTIVES", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="dropdown", text="Split Times",
              disabled=function() return Cfg("enabled") == false or Cfg("showObjectives") == false end,
              disabledTooltip="Show Boss Objectives",
              values=objectiveTimePositionValues,
              order=objectiveTimePositionOrder,
              getValue=function() return Cfg("objectiveTimePosition") or "RIGHT" end,
              setValue=function(v) Set("objectiveTimePosition", v); Refresh() end },
            { type="toggle", text="Show Objective Times",
              disabled=function() return Cfg("enabled") == false or Cfg("showObjectives") == false end,
              disabledTooltip="Show Boss Objectives",
              getValue=function() return Cfg("showObjectiveTimes") ~= false end,
              setValue=function(v) Set("showObjectiveTimes", v); Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Boss Objectives",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="the module",
              getValue=function() return Cfg("showObjectives") ~= false end,
              setValue=function(v) Set("showObjectives", v); Refresh(); EllesmereUI:RefreshPage() end },
            { type="slider", text="Objectives Size",
              disabled=function() return Cfg("enabled") == false or Cfg("showObjectives") == false end,
              disabledTooltip="Show Boss Objectives",
              min=8, max=20, step=1, isPercent=false,
              getValue=function() return Cfg("objectivesSize") or 12 end,
              setValue=function(v) Set("objectivesSize", v); Refresh() end })
        _AttachPopupButton(row._leftRegion, EllesmereUI.RESIZE_ICON, "Boss Position", {
            { type="slider", label="Boss X", min=-80, max=80, step=1,
              get=function() return Cfg("objectiveTextOffsetX") or 0 end,
              set=function(v) Set("objectiveTextOffsetX", v); Refresh() end },
            { type="slider", label="Boss Y", min=-40, max=40, step=1,
              get=function() return Cfg("objectiveTextOffsetY") or 0 end,
              set=function(v) Set("objectiveTextOffsetY", v); Refresh() end },
        }, function() return Cfg("enabled") == false or Cfg("showObjectives") == false end)
        y = y - h

        row, h = W:DualRow(parent, y,
            { type="slider", pixel=true, text="Objective Spacing",
              disabled=function() return Cfg("enabled") == false or Cfg("showObjectives") == false end,
              disabledTooltip="Show Boss Objectives",
              min=0, max=12, step=1, isPercent=false,
              getValue=function() return Cfg("objectiveGap") or 4 end,
              setValue=function(v) Set("objectiveGap", v); Refresh() end },
            { type="dropdown", text="Split Compare",
              disabled=function() return Cfg("enabled") == false or Cfg("showObjectives") == false end,
              disabledTooltip="Show Boss Objectives",
              values=compareModeValues,
              order=compareModeOrder,
              getValue=function() return Cfg("objectiveCompareMode") or "NONE" end,
              setValue=function(v) Set("objectiveCompareMode", v); Refresh() end })
        y = y - h

        _, h = W:Spacer(parent, y, 20); y = y - h

        parent:SetHeight(math.abs(y - yOffset))
    end

    -- RegisterModule
    EllesmereUI:RegisterModule("EllesmereUIMythicTimer", {
        title       = "Mythic+ Timer",
        description = "Track Mythic+ run time, key thresholds, and dungeon objectives.",
        pages    = { PAGE_DISPLAY },
        buildPage = BuildPage,
        onReset  = function()
            -- Lite DB stores data at EllesmereUIDB.profiles[X].addons.EllesmereUIMythicTimer
            if EllesmereUIDB and EllesmereUIDB.profiles then
                local profile = EllesmereUIDB.activeProfile or "Default"
                local p = EllesmereUIDB.profiles[profile]
                if p and p.addons and p.addons.EllesmereUIMythicTimer then
                    wipe(p.addons.EllesmereUIMythicTimer)
                end
            end
        end,
    })
end)
