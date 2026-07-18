-------------------------------------------------------------------------------
--  EUI_Chat_Options.lua
--
--  Options page for EllesmereUI Chat: visibility, background opacity/color,
--  top accent line.
-------------------------------------------------------------------------------
local _, ns = ...
local ECHAT = ns.ECHAT

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    if not ECHAT then return end

    local function DB()
        local d = _G._ECHAT_DB
        if d and d.profile and d.profile.chat then
            return d.profile.chat
        end
        return {}
    end
    local function Cfg(k)    return DB()[k]  end
    local function Set(k, v) DB()[k] = v     end

    local function RefreshAll()
        if ECHAT.ApplyBackground  then ECHAT.ApplyBackground()  end
        if ECHAT.ApplyFonts       then ECHAT.ApplyFonts()       end
        if ECHAT.RefreshVisibility then ECHAT.RefreshVisibility() end
    end

    local function BuildPage(_, parent, yOffset)
        local W  = EllesmereUI.Widgets
        local PP = EllesmereUI.PP
        local y  = yOffset
        local h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        -- Edit Mode reposition label + "Reset Chat Position" link
        do
            local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
            local infoFrame = CreateFrame("Frame", nil, parent)
            infoFrame:SetSize(parent:GetWidth(), 20)
            infoFrame:SetPoint("TOP", parent, "TOP", 0, y - 20)
            infoFrame._isSpacer = true
            local infoLabel = infoFrame:CreateFontString(nil, "OVERLAY")
            infoLabel:SetFont(fontPath, 15, "")
            infoLabel:SetTextColor(1, 1, 1, 0.75)
            infoLabel:SetPoint("CENTER")
            infoLabel:SetJustifyH("CENTER")
            infoLabel:SetText(EllesmereUI.L("Reposition this element within Blizzard Edit Mode"))

            -- Accent toggle beneath the label. "Force Chat on Screen" keeps the chat
            -- frame clamped to the screen; clicking again ("Allow Chat to be Moved
            -- Offscreen") releases it so it can be dragged off-screen. The choice is
            -- saved in the chat DB (forceOnScreen) and re-applied at load by
            -- ECHAT.ApplyForceOnScreen(), so it persists through reload/logout. Edit
            -- Mode is opened so the user can reposition the frame after toggling.
            local EG = EllesmereUI.ELLESMERE_GREEN
            local fosBtn = CreateFrame("Button", nil, parent)
            local fosFS = fosBtn:CreateFontString(nil, "OVERLAY")
            fosFS:SetFont(fontPath, 15, "")
            fosFS:SetTextColor(EG.r, EG.g, EG.b, 0.75)
            fosFS:SetPoint("CENTER")
            local function UpdateForceOnScreenLabel()
                local on = Cfg("forceOnScreen") == true
                fosFS:SetText(EllesmereUI.L(on and "Allow Chat to be Moved Offscreen" or "Force Chat on Screen"))
                fosBtn:SetSize(fosFS:GetStringWidth() + 12, 18)
            end
            UpdateForceOnScreenLabel()
            fosBtn:SetPoint("TOP", infoLabel, "BOTTOM", 0, -10)
            fosBtn:SetScript("OnEnter", function() fosFS:SetTextColor(EG.r, EG.g, EG.b, 1) end)
            fosBtn:SetScript("OnLeave", function() fosFS:SetTextColor(EG.r, EG.g, EG.b, 0.75) end)
            fosBtn:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                Set("forceOnScreen", not (Cfg("forceOnScreen") == true))
                if ECHAT.ApplyForceOnScreen then ECHAT.ApplyForceOnScreen() end
                UpdateForceOnScreenLabel()
                if EditModeManagerFrame then ShowUIPanel(EditModeManagerFrame) end
            end)
            y = y - 68
        end

        -- -- DISPLAY -----------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

        -- Row 1: Visibility | Visibility Options (checklist; no mouseover
        -- for chat frames, matching the old filtered dropdown)
        local visRow
        visRow, h = EllesmereUI.BuildVisibilityModeRow(W, parent, y,
            { getStore = DB, legacyKey = "visibility",
              caps = { partyIncludesRaid = false, noMouseover = true, luaDragonriding = true },
              onChanged = function()
                  if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
                  RefreshAll()
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
                function(k, v) Set(k, v); RefreshAll() end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        y = y - h

        -- Row 2: Background Opacity (+ inline color swatch) | Idle Fade Delay
        local bgRow
        bgRow, h = W:DualRow(parent, y,
            { type="slider", text="Background Opacity",
              min = 0, max = 1, step = 0.05,
              getValue=function() return Cfg("bgAlpha") or 0.65 end,
              setValue=function(v) Set("bgAlpha", v); RefreshAll() end },
            { type="slider", text="Idle Fade Delay",
              min = 5, max = 30, step = 1,
              getValue=function() return Cfg("idleFadeDelay") or 15 end,
              setValue=function(v)
                  Set("idleFadeDelay", v)
                  if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
              end })
        do
            local rgn = bgRow._leftRegion
            local ctrl = rgn._control
            local bgSwatch, bgSwatchRefresh = EllesmereUI.BuildColorSwatch(
                rgn, bgRow:GetFrameLevel() + 3,
                function()
                    return (Cfg("bgR") or 0.03), (Cfg("bgG") or 0.045), (Cfg("bgB") or 0.05)
                end,
                function(r, g, b)
                    Set("bgR", r); Set("bgG", g); Set("bgB", b)
                    RefreshAll()
                end,
                false, 20)
            PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(function() bgSwatchRefresh() end)
        end
        y = y - h

        -- Row 3: Idle Fade Strength | Font (+ cog: Outline Mode)
        do
            local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
            local fontRow
            fontRow, h = W:DualRow(parent, y,
                { type="slider", text="Idle Fade Strength",
                  min = 0, max = 100, step = 1,
                  getValue=function() return Cfg("idleFadeStrength") or 40 end,
                  setValue=function(v)
                      Set("idleFadeStrength", v)
                      if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
                  end },
                { type="dropdown", text="Font",
                  values=fontValues, order=fontOrder,
                  getValue=function() return Cfg("font") or "__global" end,
                  setValue=function(v)
                      Set("font", v)
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Font changed. A UI reload is needed to apply the new font.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end })
            -- Cog for Outline Mode
            do
                local rrgn = fontRow._rightRegion
                local outlineValues = {
                    ["__global"] = { text = "EUI Global Default" },
                    ["none"]     = { text = "Drop Shadow" },
                    ["outline"]  = { text = "Outline" },
                    ["thick"]    = { text = "Thick Outline" },
                }
                local outlineOrder = { "__global", "none", "outline", "thick" }
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Font Settings",
                    rows = {
                        { type="dropdown", label="Outline Mode",
                          values=outlineValues, order=outlineOrder,
                          get=function() return Cfg("outlineMode") or "__global" end,
                          set=function(v)
                              Set("outlineMode", v)
                              EllesmereUI:ShowConfirmPopup({
                                  title       = "Reload Required",
                                  message     = "Outline mode changed. A UI reload is needed to apply.",
                                  confirmText = "Reload Now",
                                  cancelText  = "Later",
                                  onConfirm   = function() ReloadUI() end,
                              })
                          end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, rrgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rrgn._lastInline or rrgn._control, "LEFT", -8, 0)
                rrgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rrgn:GetFrameLevel() + 5)
                cogBtn:SetAlpha(0.4)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.COGS_ICON)
                cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
                cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
            end
        end
        y = y - h

        -- Row 4: Timestamps | Extend Background Behind Tabs
        do
            local tsValues = {
                ["__blizzard"]  = { text = "Use Blizzard Setting" },
                ["none"]        = { text = "None" },
                ["%I:%M "]      = { text = "03:27" },
                ["%I:%M:%S "]   = { text = "03:27:32" },
                ["%I:%M %p "]   = { text = "03:27 PM" },
                ["%I:%M:%S %p "] = { text = "03:27:32 PM" },
                ["%H:%M "]      = { text = "15:27" },
                ["%H:%M:%S "]   = { text = "15:27:32" },
            }
            local tsOrder = {
                "__blizzard", "none", "---",
                "%I:%M ", "%I:%M:%S ", "%I:%M %p ", "%I:%M:%S %p ", "---",
                "%H:%M ", "%H:%M:%S ",
            }
            _, h = W:DualRow(parent, y,
                { type="dropdown", text="Timestamps",
                  values=tsValues, order=tsOrder,
                  getValue=function() return Cfg("timestampFormat") or "%I:%M " end,
                  setValue=function(v)
                      Set("timestampFormat", v)
                      if ECHAT.ApplyTimestampCVar then ECHAT.ApplyTimestampCVar() end
                  end },
                { type="toggle", text="Extend Background Behind Tabs",
                  tooltip="Extends the chat background up behind the tabs, and the sidebar to match, for one seamless panel.",
                  getValue=function() return Cfg("extendBgBehindTabs") or false end,
                  setValue=function(v)
                      Set("extendBgBehindTabs", v)
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "A UI reload is needed to apply the extended chat background.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end })
        end
        y = y - h

        -- -- SIDEBAR -----------------------------------------------------------
        _, h = W:SectionHeader(parent, "SIDEBAR", y); y = y - h

        -- Row 1: Sidebar Visibility (+ cog) | Sidebar Icons
        local sidebarVisValues = {
            always    = { text = "Always" },
            mouseover = { text = "Mouseover" },
            never     = { text = "Never" },
        }
        local sidebarVisOrder = { "always", "mouseover", "never" }
        local SIDEBAR_ICON_LABELS = {
            showFriends    = "Friends",
            showDurability = "Durability",
            showCopy       = "Copy Chat",
            showPortals    = "M+ Portals",
            showVoice      = "Voice/Channels",
            showSettings   = "Settings",
        }
        -- Chain icons listed in the user's saved order (drag rows to reorder);
        -- Scroll is pinned to the sidebar bottom, so its row is fixed.
        local sidebarIconItems = {}
        local sidebarOrderedKeys = ECHAT.ResolveSidebarIconOrder and ECHAT.ResolveSidebarIconOrder()
            or { "showFriends", "showDurability", "showCopy", "showPortals", "showVoice", "showSettings" }
        for _, k in ipairs(sidebarOrderedKeys) do
            sidebarIconItems[#sidebarIconItems + 1] = { key = k, label = SIDEBAR_ICON_LABELS[k] }
        end
        sidebarIconItems[#sidebarIconItems + 1] = { key = "showScroll", label = "Scroll to Bottom", fixed = true }
        local sidebarRow
        sidebarRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Sidebar Visibility",
              values=sidebarVisValues, order=sidebarVisOrder,
              getValue=function() return Cfg("sidebarVisibility") or "always" end,
              setValue=function(v)
                  Set("sidebarVisibility", v)
                  if ECHAT.ApplySidebarVisibility then ECHAT.ApplySidebarVisibility() end
              end },
            { type="dropdown", text="Sidebar Icons",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end })
        -- Cog for Sidebar Visibility
        do
            local lrgn = sidebarRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Sidebar Settings",
                rows = {
                    { type="toggle", label="Show Sidebar on Right",
                      get=function() return Cfg("sidebarRight") or false end,
                      set=function(v)
                          Set("sidebarRight", v)
                          if ECHAT.ApplySidebarPosition then ECHAT.ApplySidebarPosition() end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, lrgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", lrgn._lastInline or lrgn._control, "LEFT", -8, 0)
            lrgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(lrgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end
        -- Sidebar Icons checkbox dropdown (drag rows to reorder). Visibility
        -- toggles of already-created icons apply live; a new order -- and
        -- newly-added icons -- take effect on reload, so a single reload
        -- prompt fires when the dropdown closes with pending changes.
        do
            local rightRgn = sidebarRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local pendingIconReload = false
            local cbDD, cbDDRefresh = EllesmereUI.BuildReorderCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                sidebarIconItems,
                function(k) return Cfg(k) ~= false end,
                function(k, v)
                    -- Enabling an icon whose button was not created at login
                    -- (it was disabled then) needs a sidebar rebuild to show it.
                    -- Disabling, or re-enabling an already-created icon, applies
                    -- live with no reload.
                    if v and ECHAT.SidebarIconExists and not ECHAT.SidebarIconExists(k) then
                        pendingIconReload = true
                    end
                    Set(k, v)
                    if ECHAT.ApplySidebarIcons then ECHAT.ApplySidebarIcons() end
                end,
                {
                    hint2 = "Reload required - close dropdown to reload",
                    setOrder = function(orderedKeys)
                        local map = {}
                        for i, key in ipairs(orderedKeys) do map[key] = i end
                        Set("sidebarIconOrder", map)
                        -- Applied at the next reload via the creation-order
                        -- snapshot; nothing re-anchors live.
                    end,
                    onClose = function(orderChanged)
                        if not orderChanged and not pendingIconReload then return end
                        pendingIconReload = false
                        EllesmereUI:ShowConfirmPopup({
                            title       = "Reload Required",
                            message     = "A UI reload is needed to apply your sidebar icon changes.",
                            confirmText = "Reload Now",
                            cancelText  = "Later",
                            onConfirm   = function() ReloadUI() end,
                        })
                    end,
                })
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        y = y - h

        -- Row 2: Sidebar Icons Color | (empty)
        local function MakeIconColorSwatches()
            return {
                { tooltip = "Custom Color",
                  hasAlpha = false,
                  getValue = function()
                      return (Cfg("iconR") or 1), (Cfg("iconG") or 1), (Cfg("iconB") or 1)
                  end,
                  setValue = function(r, g, b)
                      Set("iconR", r); Set("iconG", g); Set("iconB", b)
                      if ECHAT.ApplyIconColor then ECHAT.ApplyIconColor() end
                  end,
                  onClick = function(self)
                      if Cfg("iconUseAccent") then
                          Set("iconUseAccent", false)
                          if ECHAT.ApplyIconColor then ECHAT.ApplyIconColor() end
                          EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return Cfg("iconUseAccent") and 0.3 or 1
                  end },
                { tooltip = "Accent Color",
                  hasAlpha = false,
                  getValue = function()
                      local ar, ag, ab = EllesmereUI.GetAccentColor()
                      return ar, ag, ab
                  end,
                  setValue = function() end,
                  onClick = function()
                      Set("iconUseAccent", true)
                      if ECHAT.ApplyIconColor then ECHAT.ApplyIconColor() end
                      EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return Cfg("iconUseAccent") and 1 or 0.3
                  end },
            }
        end
        _, h = W:DualRow(parent, y,
            { type="multiSwatch", text="Sidebar Icons Color",
              swatches = MakeIconColorSwatches() },
            { type="toggle", text="Hide Sidebar Background",
              getValue=function() return Cfg("hideSidebarBg") or false end,
              setValue=function(v)
                  Set("hideSidebarBg", v)
                  if ECHAT.ApplySidebarBackground then ECHAT.ApplySidebarBackground() end
              end })
        y = y - h

        -- Row 3: Sidebar Icon Size (+ cog: Icon Spacing) | Free Move Icons
        local sizeRow
        sizeRow, h = W:DualRow(parent, y,
            { type="slider", text="Sidebar Icon Size",
              min = 0.5, max = 2.0, step = 0.05,
              getValue=function() return Cfg("sidebarIconScale") or 1.0 end,
              setValue=function(v)
                  Set("sidebarIconScale", v)
                  if ECHAT.ApplySidebarIconScale then ECHAT.ApplySidebarIconScale() end
              end },
            { type="toggle", text="Free Move Icons",
              tooltip="When enabled, Shift+Click any sidebar icon to drag it to a custom position.",
              getValue=function() return Cfg("freeMoveIcons") or false end,
              setValue=function(v)
                  Set("freeMoveIcons", v)
                  if ECHAT.ApplySidebarIcons then ECHAT.ApplySidebarIcons() end
                  EllesmereUI:RefreshPage()
              end })
        do
            local lrgn = sizeRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Settings",
                rows = {
                    { type="slider", pixel=true, label="Icon Spacing",
                      min = 0, max = 30, step = 1,
                      get=function() return Cfg("sidebarIconSpacing") or 10 end,
                      set=function(v)
                          Set("sidebarIconSpacing", v)
                          if ECHAT.ApplySidebarIcons then ECHAT.ApplySidebarIcons() end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, lrgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", lrgn._lastInline or lrgn._control, "LEFT", -8, 0)
            lrgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(lrgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end
        -- "Reset" label next to the Free Move Icons toggle (only visible when enabled)
        do
            local rgn = sizeRow._rightRegion
            local resetFS = rgn:CreateFontString(nil, "OVERLAY")
            resetFS:SetFont(EllesmereUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 12, "")
            resetFS:SetTextColor(1, 1, 1, 0.8)
            resetFS:SetText(EllesmereUI.L("Reset"))
            resetFS:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            local hitBtn = CreateFrame("Button", nil, rgn)
            hitBtn:SetAllPoints(resetFS)
            hitBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            hitBtn:SetScript("OnEnter", function() resetFS:SetTextColor(1, 0.3, 0.3, 1) end)
            hitBtn:SetScript("OnLeave", function() resetFS:SetTextColor(1, 1, 1, 0.8) end)
            hitBtn:SetScript("OnClick", function()
                Set("iconPositions", {})
                if ECHAT.ApplySidebarIcons then ECHAT.ApplySidebarIcons() end
            end)
            local function UpdateResetVis()
                local on = Cfg("freeMoveIcons")
                resetFS:SetShown(on)
                hitBtn:SetShown(on)
            end
            UpdateResetVis()
            EllesmereUI.RegisterWidgetRefresh(UpdateResetVis)
        end
        y = y - h

        -- -- EXTRAS ------------------------------------------------------------
        _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

        -- Row 1: Remember Last Chat Lines (+ cog: Max Lines) | Hide Tooltip on Hover
        -- Chat history disabled for now. Uncomment to re-enable.
        --[[ local histRow
        histRow, h = W:DualRow(parent, y,
            { type="toggle", text="Remember Last Chat Lines",
              tooltip="Saves the most recent lines per chat tab (per character), except Blizzard's combat log window, so they reappear after /reload or relog. Stored separately from layout profiles.",
              getValue=function() return Cfg("persistChatHistory") == true end,
              setValue=function(v)
                  Set("persistChatHistory", v)
                  if ECHAT.OnSessionHistoryToggled then
                      ECHAT.OnSessionHistoryToggled(v)
                  elseif ECHAT.InitChatSessionHistory then
                      ECHAT.InitChatSessionHistory()
                  end
              end },
            { type="toggle", text="Hide Tooltip on Hover",
              getValue=function() return Cfg("hideTooltipOnHover") or false end,
              setValue=function(v) Set("hideTooltipOnHover", v) end })
        do
            local lrgn = histRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Session History",
                rows = {
                    { type="slider", label="Max Lines to Keep",
                      min = 20, max = 300, step = 10,
                      get=function() return Cfg("persistChatHistoryMaxLines") or 100 end,
                      set=function(v) Set("persistChatHistoryMaxLines", v) end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, lrgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", lrgn._lastInline or lrgn._control, "LEFT", -8, 0)
            lrgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(lrgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end
        y = y - h ]]

        -- Row 1: Hide Tooltip on Hover | Hide Borders
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Tooltip on Hover",
              getValue=function() return Cfg("hideTooltipOnHover") or false end,
              setValue=function(v) Set("hideTooltipOnHover", v) end },
            { type="toggle", text="Hide Borders",
              getValue=function() return Cfg("hideBorders") or false end,
              setValue=function(v)
                  Set("hideBorders", v)
                  if ECHAT.ApplyBorders then ECHAT.ApplyBorders() end
              end })
        y = y - h

        -- Row 2: Input on Top | Lock Main Chat Size
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Input on Top",
              getValue=function() return Cfg("inputOnTop") or false end,
              setValue=function(v)
                  Set("inputOnTop", v)
                  if ECHAT.ApplyInputPosition then ECHAT.ApplyInputPosition() end
              end },
            { type="toggle", text="Lock Main Chat Size",
              tooltip="Hides the resize handle on the main chat frame, preventing accidental resizing.",
              getValue=function() return Cfg("lockChatSize") or false end,
              setValue=function(v)
                  Set("lockChatSize", v)
                  if ECHAT.ApplyLockChatSize then ECHAT.ApplyLockChatSize() end
              end })
        y = y - h

        -- Row 3: Whisper Sound | (empty)
        -- Sound dropdown: shallow-copy the runtime tables so _menuOpts
        -- (preview icon) doesn't pollute the shared tables.
        local whisperSoundValues = {}
        local whisperSoundPaths = ECHAT.WHISPER_SOUND_PATHS or {}
        local whisperSoundNames = ECHAT.WHISPER_SOUND_NAMES or { none = "None" }
        local whisperSoundOrder = ECHAT.WHISPER_SOUND_ORDER or { "none" }
        for k, v in pairs(whisperSoundNames) do whisperSoundValues[k] = v end
        whisperSoundValues._menuOpts = {
            itemHeight = 26,
            maxTextWidthPct = 0.8,
            searchable = true,
            iconAtlas = function(key)
                if key == "none" then return nil end
                if not whisperSoundPaths[key] then return nil end
                return "common-icon-sound"
            end,
            iconPressedAtlas = function(key)
                if key == "none" then return nil end
                return "common-icon-sound-pressed"
            end,
            iconOnClick = function(key)
                local path = whisperSoundPaths[key]
                if path then PlaySoundFile(path, "Master") end
            end,
            iconTooltip = function() return "Preview Sound" end,
        }
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Whisper Sound",
              values=whisperSoundValues, order=whisperSoundOrder,
              getValue=function() return Cfg("whisperSoundKey") or "none" end,
              setValue=function(v) Set("whisperSoundKey", v) end },
            { type="label", text="" })
        y = y - h

        return math.abs(y)
    end

    _G._EBS_BuildChatPage = BuildPage

    EllesmereUI:RegisterModule("EllesmereUIChat", {
        title       = "Chat",
        description = "Chat frame reskin, clickable URLs, copy chat, sidebar icons.",
        pages       = { "Chat" },
        buildPage   = function(pageName, p, yOffset) return BuildPage(pageName, p, yOffset) end,
        searchTerms = "chat url copy whisper sidebar friends voice",
        onReset = function()
            local d = _G._ECHAT_DB
            if d and d.ResetProfile then d:ResetProfile() end
            RefreshAll()
            EllesmereUI:InvalidatePageCache()
        end,
    })
end)
