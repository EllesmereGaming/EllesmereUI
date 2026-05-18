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
        local y = yOffset
        local row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true


        local alignValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
        local alignOrder  = { "LEFT", "CENTER", "RIGHT" }
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
              disabledTooltip="Module is disabled",
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
              disabledTooltip="Module is disabled",
              min=0.5, max=2.0, step=0.01, isPercent=false,
              getValue=function() return Cfg("scale") or 1.0 end,
              setValue=function(v) Set("scale", v); Refresh() end },
            { type="slider", text="Background Opacity",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
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
                      local ar, ag, ab = EllesmereUI.ResolveThemeColor(EllesmereUI.GetActiveTheme())
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

        row, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Title Color",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              swatches = _MakeAccentSwatches("titleUseAccent", "titleColor", 1, 1, 1) },
            { type="toggle", text="Show Affix",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showAffixes") ~= false end,
              setValue=function(v) Set("showAffixes", v); Refresh() end })
        y = y - h

        -- Inline RESIZE cog: Title Size on Title Color (left), Affix Size on Show Affix (right)
        do
            local PP = EllesmereUI.PP
            local function _attachCog(rgn, popupTitle, sliderLabel, sliderMin, sliderMax, getKey, defaultV, isDisabled)
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = popupTitle,
                    rows = {
                        { type="slider", label=sliderLabel, min=sliderMin, max=sliderMax, step=1,
                          get=function() return Cfg(getKey) or defaultV end,
                          set=function(v) Set(getKey, v); Refresh() end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                PP.Point(cogBtn, "RIGHT", rgn._control or rgn, "LEFT", -6, 0)
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
                local function UpdateCogAlpha()
                    cogBtn:SetAlpha(isDisabled() and 0.15 or 0.4)
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogAlpha)
                UpdateCogAlpha()
                cogBtn:SetScript("OnClick", function(self)
                    if not isDisabled() then cogShow(self) end
                end)
                cogBtn:SetScript("OnEnter", function(self)
                    if not isDisabled() then self:SetAlpha(0.75) end
                end)
                cogBtn:SetScript("OnLeave", function(self) UpdateCogAlpha() end)
            end
            _attachCog(row._leftRegion,  "Title Size", "Size", 8, 24, "titleSize", 16,
                function() return Cfg("enabled") == false end)
            _attachCog(row._rightRegion, "Affix Size", "Size", 6, 20, "affixSize", 12,
                function() return Cfg("enabled") == false or Cfg("showAffixes") == false end)
        end

        row, h = W:DualRow(parent, y,
            { type="slider", text="Bar Width",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              min=120, max=420, step=1, isPercent=false,
              getValue=function() return Cfg("barWidth") or 210 end,
              setValue=function(v) Set("barWidth", v); Refresh() end },
            { type="slider", text="Bar Height",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              min=4, max=30, step=1, isPercent=false,
              getValue=function() return Cfg("barHeight") or 8 end,
              setValue=function(v) Set("barHeight", v); Refresh() end })

        -- Inline cog on Bar Height: extra "Expanded Height" slider that
        -- controls the bar height when "Timer Inside Bar" is active.
        do
            local PP = EllesmereUI.PP
            local rightRgn = row._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Bar Height Options",
                rows = {
                    { type="slider", label="Expanded Height",
                      min=8, max=40, step=1,
                      get=function() return Cfg("barHeightExpanded") or 22 end,
                      set=function(v) Set("barHeightExpanded", v); Refresh() end },
                    { type="slider", label="Expanded Fill",
                      min=0, max=1, step=0.05,
                      get=function() return Cfg("barFillAlphaExpanded") or 0.85 end,
                      set=function(v) Set("barFillAlphaExpanded", v); Refresh() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rightRgn)
            cogBtn:SetSize(26, 26)
            PP.Point(cogBtn, "RIGHT", rightRgn._control or rightRgn, "LEFT", -6, 0)
            cogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            local function UpdateCogAlpha()
                cogBtn:SetAlpha(Cfg("enabled") == false and 0.15 or 0.4)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogAlpha)
            UpdateCogAlpha()
            cogBtn:SetScript("OnClick", function(self)
                if Cfg("enabled") ~= false then cogShow(self) end
            end)
            cogBtn:SetScript("OnEnter", function(self)
                if Cfg("enabled") ~= false then self:SetAlpha(0.75) end
            end)
            cogBtn:SetScript("OnLeave", function() UpdateCogAlpha() end)
        end
        y = y - h

        -- ── TIMER ────────────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "TIMER", y); y = y - h

        local timerDisplayValues = {
            REMAINING       = "11:37",
            REMAINING_TOTAL = "11:37 / 33:00",
            ELAPSED         = "21:23",
            ELAPSED_DETAIL  = "21:23 (11:37 / 33:00)",
        }
        local timerDisplayOrder = { "REMAINING", "REMAINING_TOTAL", "ELAPSED", "ELAPSED_DETAIL" }

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show Timer Bar",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showTimerBar") ~= false end,
              setValue=function(v)
                  Set("showTimerBar", v)
                  if not v and Cfg("timerInBar") then
                      Set("timerInBar", false)
                  end
                  Refresh(); EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Timer Format",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              values=timerDisplayValues,
              order=timerDisplayOrder,
              getValue=function() return Cfg("timerDisplayMode") or "REMAINING_TOTAL" end,
              setValue=function(v) Set("timerDisplayMode", v); Refresh() end })
        y = y - h

        -- Inline RESIZE cog on Timer Format: Timer Text Size
        do
            local PP = EllesmereUI.PP
            local rightRgn = row._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Timer Text",
                rows = {
                    { type="slider", label="Size", min=10, max=32, step=1,
                      get=function() return Cfg("timerTextSize") or 20 end,
                      set=function(v) Set("timerTextSize", v); Refresh() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rightRgn)
            cogBtn:SetSize(26, 26)
            PP.Point(cogBtn, "RIGHT", rightRgn._control or rightRgn, "LEFT", -6, 0)
            cogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
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

        if IsAdvanced() then
            local PP = EllesmereUI.PP
            row, h = W:DualRow(parent, y,
                { type="toggle", text="Timer Inside Bar",
                  disabled=function() return Cfg("enabled") == false or Cfg("showTimerBar") == false end,
                  disabledTooltip=function() if Cfg("showTimerBar") == false then return "Enable Show Timer Bar" end return "Module is disabled" end,
                  getValue=function() return Cfg("timerInBar") == true end,
                  setValue=function(v) Set("timerInBar", v); Refresh(); EllesmereUI:RefreshPage() end },
                { type="toggle", text="+2 / +3 Threshold Text",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  getValue=function()
                      return Cfg("showPlusTwoTimer") ~= false or Cfg("showPlusThreeTimer") ~= false
                  end,
                  setValue=function(v)
                      Set("showPlusTwoTimer", v)
                      Set("showPlusThreeTimer", v)
                      Refresh()
                  end })
            y = y - h

            -- Inline color swatch on Timer Inside Bar (left)
            do
                local rgn = row._leftRegion
                local ctrl = rgn._control
                local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, row:GetFrameLevel() + 3,
                    function()
                        local c = Cfg("timerBarTextColor")
                        if c then return c.r or 1, c.g or 1, c.b or 1, 1 end
                        return 1, 1, 1, 1
                    end,
                    function(r, g, b)
                        Set("timerBarTextColor", { r = r, g = g, b = b })
                        Refresh()
                    end,
                    false, 20)
                PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
                local block = CreateFrame("Frame", nil, swatch)
                block:SetAllPoints(); block:SetFrameLevel(swatch:GetFrameLevel() + 10)
                block:EnableMouse(true)
                block:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, EllesmereUI.DisabledTooltip("Timer Inside Bar"))
                end)
                block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
                local function UpdateSwatchState()
                    local off = Cfg("enabled") == false or Cfg("timerInBar") ~= true
                    if off then swatch:SetAlpha(0.3); block:Show()
                    else swatch:SetAlpha(1); block:Hide() end
                end
                EllesmereUI.RegisterWidgetRefresh(function() updateSwatch(); UpdateSwatchState() end)
                UpdateSwatchState()

                -- Inline cog beside the swatch with extra Timer Inside Bar
                -- options (Left Text aligns the timer to bar's LEFT edge
                -- with a 5px inset instead of being centered).
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Timer Inside Bar Options",
                    rows = {
                        { type="toggle", label="Left Text",
                          get=function() return Cfg("timerInBarLeftText") == true end,
                          set=function(v) Set("timerInBarLeftText", v); Refresh() end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                PP.Point(cogBtn, "RIGHT", swatch, "LEFT", -6, 0)
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.COGS_ICON)
                local function UpdateCogAlpha()
                    local off = Cfg("enabled") == false or Cfg("timerInBar") ~= true
                    cogBtn:SetAlpha(off and 0.15 or 0.4)
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogAlpha)
                UpdateCogAlpha()
                cogBtn:SetScript("OnClick", function(self)
                    if Cfg("enabled") ~= false and Cfg("timerInBar") == true then
                        cogShow(self)
                    end
                end)
                cogBtn:SetScript("OnEnter", function(self)
                    if Cfg("enabled") ~= false and Cfg("timerInBar") == true then
                        self:SetAlpha(0.75)
                    end
                end)
                cogBtn:SetScript("OnLeave", function() UpdateCogAlpha() end)
            end

            -- Inline RESIZE cog: threshold text size, anchored to the toggle on the RIGHT side
            do
                local rightRgn = row._rightRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "+2 / +3 Threshold Size",
                    rows = {
                        { type="slider", label="Size", min=6, max=20, step=1,
                          get=function() return Cfg("thresholdSize") or 12 end,
                          set=function(v) Set("thresholdSize", v); Refresh() end },
                        { type="slider", label="Tick Opacity",
                          min=0, max=1, step=0.05,
                          get=function() return Cfg("tickAlpha") or 1 end,
                          set=function(v) Set("tickAlpha", v); Refresh() end },
                        { type="toggle", label="White Ticks",
                          get=function() return Cfg("tickWhite") == true end,
                          set=function(v) Set("tickWhite", v); Refresh() end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, rightRgn)
                cogBtn:SetSize(26, 26)
                PP.Point(cogBtn, "RIGHT", rightRgn._control or rightRgn, "LEFT", -6, 0)
                cogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
                local function UpdateCogAlpha()
                    cogBtn:SetAlpha(Cfg("enabled") == false and 0.15 or 0.4)
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogAlpha)
                UpdateCogAlpha()
                cogBtn:SetScript("OnClick", function(self)
                    if Cfg("enabled") ~= false then cogShow(self) end
                end)
                cogBtn:SetScript("OnEnter", function(self)
                    if Cfg("enabled") ~= false then self:SetAlpha(0.75) end
                end)
                cogBtn:SetScript("OnLeave", function(self) UpdateCogAlpha() end)
            end
        end

        -- ── OBJECTIVES ───────────────────────────────────────────────────
        _, h = W:SectionHeader(parent, "OBJECTIVES", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="slider", text="Objectives Size",
              disabled=function() return Cfg("enabled") == false or Cfg("showObjectives") == false end,
              disabledTooltip=function()
                  if Cfg("enabled") == false then return "the module" end
                  return "Show Boss Objectives"
              end,
              min=8, max=20, step=1, isPercent=false,
              getValue=function() return Cfg("objectivesSize") or 12 end,
              setValue=function(v) Set("objectivesSize", v); Refresh() end },
            { type="toggle", text="Show Boss Objectives",
              disabled=function() return Cfg("enabled") == false end,
              disabledTooltip="Module is disabled",
              getValue=function() return Cfg("showObjectives") ~= false end,
              setValue=function(v) Set("showObjectives", v); Refresh(); EllesmereUI:RefreshPage() end })
        y = y - h

        -- Inline COGS cog: Show Objective Times toggle, anchored to Show Boss Objectives toggle
        do
            local PP = EllesmereUI.PP
            local rightRgn = row._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Boss Objectives",
                rows = {
                    { type="toggle", label="Show Objective Times",
                      get=function() return Cfg("showObjectiveTimes") ~= false end,
                      set=function(v) Set("showObjectiveTimes", v); Refresh() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rightRgn)
            cogBtn:SetSize(26, 26)
            PP.Point(cogBtn, "RIGHT", rightRgn._control or rightRgn, "LEFT", -6, 0)
            cogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            local function isDisabled()
                return Cfg("enabled") == false or Cfg("showObjectives") == false
            end
            local function UpdateCogAlpha()
                cogBtn:SetAlpha(isDisabled() and 0.15 or 0.4)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogAlpha)
            UpdateCogAlpha()
            cogBtn:SetScript("OnClick", function(self)
                if not isDisabled() then cogShow(self) end
            end)
            cogBtn:SetScript("OnEnter", function(self)
                if not isDisabled() then self:SetAlpha(0.75) end
            end)
            cogBtn:SetScript("OnLeave", function(self) UpdateCogAlpha() end)
        end

        if IsAdvanced() then
            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Enemy Text Format",
                  disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
                  disabledTooltip="Requires Show Enemy Forces",
                  values=forcesTextValues,
                  order=forcesTextOrder,
                  getValue=function() return Cfg("enemyForcesTextFormat") or "PERCENT" end,
                  setValue=function(v) Set("enemyForcesTextFormat", v); Refresh() end },
                { type="multiSwatch", text="Enemy Bar Color",
                  disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
                  disabledTooltip="Requires Show Enemy Forces",
                  swatches = {
                      { tooltip = "Custom Color",
                        hasAlpha = false,
                        getValue = function()
                            local c = Cfg("enemyBarColor")
                            if c then return c.r or 0.35, c.g or 0.55, c.b or 0.8 end
                            return 0.35, 0.55, 0.8
                        end,
                        setValue = function(r, g, b)
                            Set("enemyBarColor", { r = r, g = g, b = b })
                            Refresh()
                        end,
                        onClick = function(self)
                            if Cfg("enemyBarUseAccent") ~= false then
                                Set("enemyBarUseAccent", false)
                                Refresh(); EllesmereUI:RefreshPage()
                                return
                            end
                            if self._eabOrigClick then self._eabOrigClick(self) end
                        end,
                        refreshAlpha = function()
                            if Cfg("enabled") == false or Cfg("showEnemyBar") == false then return 0.15 end
                            return Cfg("enemyBarUseAccent") ~= false and 0.3 or 1
                        end },
                      { tooltip = "Accent Color",
                        hasAlpha = false,
                        getValue = function()
                            local ar, ag, ab = EllesmereUI.ResolveThemeColor(EllesmereUI.GetActiveTheme())
                            return ar, ag, ab
                        end,
                        setValue = function() end,
                        onClick = function()
                            Set("enemyBarUseAccent", true)
                            Refresh(); EllesmereUI:RefreshPage()
                        end,
                        refreshAlpha = function()
                            if Cfg("enabled") == false or Cfg("showEnemyBar") == false then return 0.15 end
                            return Cfg("enemyBarUseAccent") ~= false and 1 or 0.3
                        end },
                  } })
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="dropdown", text="Enemy Forces %",
                  disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
                  disabledTooltip="Requires Show Enemy Forces",
                  values={ LABEL = "In Label Text", BAR = "In Bar", BESIDE = "Beside Bar" },
                  order={ "LABEL", "BAR", "BESIDE" },
                  getValue=function() return Cfg("enemyForcesPctPos") or "LABEL" end,
                  setValue=function(v) Set("enemyForcesPctPos", v); Refresh() end },
                { type="dropdown", text="Enemy Forces Position",
                  disabled=function() return Cfg("enabled") == false or Cfg("showEnemyBar") == false end,
                  disabledTooltip="Requires Show Enemy Forces",
                  values={ BOTTOM = "Bottom", UNDER_BAR = "Under Timer Bar" },
                  order={ "BOTTOM", "UNDER_BAR" },
                  getValue=function() return Cfg("enemyForcesPos") or "BOTTOM" end,
                  setValue=function(v) Set("enemyForcesPos", v); Refresh() end })

            -- Inline cog on the Enemy Forces % dropdown: extra options
            -- (currently just Hide Label).
            do
                local PP = EllesmereUI.PP
                local leftRgn = row._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Enemy Forces % Options",
                    rows = {
                        { type="toggle", label="Hide Label",
                          get=function() return Cfg("hideEnemyForcesLabel") == true end,
                          set=function(v) Set("hideEnemyForcesLabel", v); Refresh() end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, leftRgn)
                cogBtn:SetSize(26, 26)
                PP.Point(cogBtn, "RIGHT", leftRgn._control or leftRgn, "LEFT", -6, 0)
                cogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.COGS_ICON)
                local function UpdateCogAlpha()
                    local off = Cfg("enabled") == false or Cfg("showEnemyBar") == false
                    cogBtn:SetAlpha(off and 0.15 or 0.4)
                end
                EllesmereUI.RegisterWidgetRefresh(UpdateCogAlpha)
                UpdateCogAlpha()
                cogBtn:SetScript("OnClick", function(self)
                    if Cfg("enabled") ~= false and Cfg("showEnemyBar") ~= false then
                        cogShow(self)
                    end
                end)
                cogBtn:SetScript("OnEnter", function(self)
                    if Cfg("enabled") ~= false and Cfg("showEnemyBar") ~= false then
                        self:SetAlpha(0.75)
                    end
                end)
                cogBtn:SetScript("OnLeave", function() UpdateCogAlpha() end)
            end
            y = y - h

            row, h = W:DualRow(parent, y,
                { type="slider", text="Objective Spacing",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  min=0, max=12, step=1, isPercent=false,
                  getValue=function() return Cfg("objectiveGap") or 4 end,
                  setValue=function(v) Set("objectiveGap", v); Refresh() end },
                { type="dropdown", text="Split Compare",
                  disabled=function() return Cfg("enabled") == false end,
                  disabledTooltip="Module is disabled",
                  values=compareModeValues,
                  order=compareModeOrder,
                  getValue=function() return Cfg("objectiveCompareMode") or "NONE" end,
                  setValue=function(v) Set("objectiveCompareMode", v); Refresh() end })
            y = y - h

        end

        _, h = W:Spacer(parent, y, 20); y = y - h

        parent:SetHeight(math.abs(y - yOffset))
    end

    -- RegisterModule
    EllesmereUI:RegisterModule("EllesmereUIMythicTimer", {
        title       = "Mythic+ Timer",
        description = "Track Mythic+ run time, key thresholds, and dungeon objectives.",
        icon_on  = "Interface\\AddOns\\EllesmereUI\\media\\icons\\sidebar\\mplus-ig-on.png",
        icon_off = "Interface\\AddOns\\EllesmereUI\\media\\icons\\sidebar\\mplus-ig.png",
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
