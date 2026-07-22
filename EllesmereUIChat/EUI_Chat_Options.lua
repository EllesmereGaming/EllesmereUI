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

    local function BuildPage(pageName, parent, yOffset)
        local W  = EllesmereUI.Widgets
        local PP = EllesmereUI.PP
        local y  = yOffset
        local h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        local isChat = pageName == "Chat"
        local isTabs = pageName == "Tabs"
        local isSidebar = pageName == "Sidebar"

        if isChat then

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

        -- Row 2: Background Opacity (+ inline color swatch) | Background
        -- Texture (Unit Frames bar texture catalogue incl. SharedMedia, with
        -- per-item texture preview backgrounds)
        if ECHAT.RefreshBgTextureCatalogue then ECHAT.RefreshBgTextureCatalogue() end
        local btValues, btOrder = {}, {}
        do
            local texNames = ns.chatBgTextureNames or {}
            for _, key in ipairs(ns.chatBgTextureOrder or {}) do
                if key ~= "---" then
                    btValues[key] = texNames[key] or key
                    btOrder[#btOrder + 1] = key
                end
            end
            local texLookup = ns.chatBgTextures or {}
            btValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    return texLookup[key]
                end,
            }
        end
        local bgRow
        bgRow, h = W:DualRow(parent, y,
            { type="slider", text="Background Opacity",
              min = 0, max = 1, step = 0.05,
              getValue=function() return Cfg("bgAlpha") or 0.65 end,
              setValue=function(v) Set("bgAlpha", v); RefreshAll() end },
            { type="dropdown", text="Background Texture",
              tooltip="Texture drawn over the chat background color.",
              values=btValues, order=btOrder,
              getValue=function() return Cfg("bgTexture") or "none" end,
              setValue=function(v) Set("bgTexture", v); RefreshAll() end })
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

        -- Row 3: Timestamps | Font (+ cog: Outline Mode)
        do
            local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
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
            local fontRow
            fontRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Timestamps",
                  values=tsValues, order=tsOrder,
                  getValue=function() return Cfg("timestampFormat") or "%I:%M " end,
                  setValue=function(v)
                      Set("timestampFormat", v)
                      if ECHAT.ApplyTimestampCVar then ECHAT.ApplyTimestampCVar() end
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

        -- Outer panel border. Without the extended background, visible tabs get
        -- matching individual borders instead of outlining empty tab-strip space.
            local thicknessValues = {
                none   = { text = "None" },
                thin   = { text = "Thin" },
                normal = { text = "Normal" },
                heavy  = { text = "Heavy" },
                strong = { text = "Strong" },
            }
            local thicknessOrder = { "none", "thin", "normal", "heavy", "strong" }
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local borderRow
            borderRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style",
                  values=texValues, order=texOrder,
                  getValue=function() return Cfg("panelBorderTexture") or "solid" end,
                  setValue=function(v)
                      Set("panelBorderTexture", v)
                      Set("panelBorderOffsetX", nil); Set("panelBorderOffsetY", nil)
                      Set("panelBorderShiftX", nil); Set("panelBorderShiftY", nil)
                      local defSize = EllesmereUI.GetBorderDefaultSize("chat", v)
                          or EllesmereUI.GetBorderTextureDefaultThickness(v)
                      if defSize then Set("panelBorderThickness", defSize) end
                      if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                      EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", text="Border Size",
                  values=thicknessValues, order=thicknessOrder,
                  getValue=function() return Cfg("panelBorderThickness") or "none" end,
                  setValue=function(v)
                      Set("panelBorderThickness", v)
                      if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                  end })
            y = y - h

            -- Border offset dropdown on Border Style.
            do
                local rgn = borderRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Offset",
                    captureRegion = rgn,
                    rows = {
                        { type="toggle", label="Show Behind",
                          get=function() return Cfg("panelBorderBehind") or false end,
                          set=function(v)
                              Set("panelBorderBehind", v)
                              if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                          end },
                        { type="slider", label="Offset X", min=-10, max=10, step=1,
                          get=function()
                              local v = Cfg("panelBorderOffsetX")
                              if v ~= nil then return v end
                              return EllesmereUI.GetBorderDefaults("chat",
                                  Cfg("panelBorderTexture") or "solid",
                                  Cfg("panelBorderThickness") or "none")
                          end,
                          set=function(v)
                              Set("panelBorderOffsetX", v)
                              if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                          end },
                        { type="slider", label="Offset Y", min=-10, max=10, step=1,
                          get=function()
                              local v = Cfg("panelBorderOffsetY")
                              if v ~= nil then return v end
                              local _, value = EllesmereUI.GetBorderDefaults("chat",
                                  Cfg("panelBorderTexture") or "solid",
                                  Cfg("panelBorderThickness") or "none")
                              return value
                          end,
                          set=function(v)
                              Set("panelBorderOffsetY", v)
                              if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                          end },
                        { type="slider", label="Shift X", min=-10, max=10, step=1,
                          get=function()
                              local v = Cfg("panelBorderShiftX")
                              if v ~= nil then return v end
                              local _, _, value = EllesmereUI.GetBorderDefaults("chat",
                                  Cfg("panelBorderTexture") or "solid",
                                  Cfg("panelBorderThickness") or "none")
                              return value
                          end,
                          set=function(v)
                              Set("panelBorderShiftX", v == 0 and nil or v)
                              if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                          end },
                        { type="slider", label="Shift Y", min=-10, max=10, step=1,
                          get=function()
                              local v = Cfg("panelBorderShiftY")
                              if v ~= nil then return v end
                              local _, _, _, value = EllesmereUI.GetBorderDefaults("chat",
                                  Cfg("panelBorderTexture") or "solid",
                                  Cfg("panelBorderThickness") or "none")
                              return value
                          end,
                          set=function(v)
                              Set("panelBorderShiftY", v == 0 and nil or v)
                              if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                          end },
                    },
                })
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
                local function RefreshCog() cogBtn:SetAlpha(0.4) end
                cogBtn:SetScript("OnEnter", function(self)
                    self:SetAlpha(0.7)
                end)
                cogBtn:SetScript("OnLeave", function()
                    EllesmereUI.HideWidgetTooltip()
                    RefreshCog()
                end)
                cogBtn:SetScript("OnClick", function(self)
                    cogShow(self)
                end)
                EllesmereUI.RegisterWidgetRefresh(RefreshCog)
                RefreshCog()
            end

            -- Accent, custom, and class-color selectors beside Border Size.
            do
                local rgn = borderRow._rightRegion
                local ctrl = rgn._control
                local function ApplyMode(mode)
                    Set("panelBorderColorMode", mode)
                    if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                    EllesmereUI:RefreshPage()
                end

                local classSwatch, refreshClass = EllesmereUI.BuildColorSwatch(
                    rgn, borderRow:GetFrameLevel() + 3,
                    function()
                        local _, class = UnitClass("player")
                        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                        return c and c.r or 1, c and c.g or 1, c and c.b or 1
                    end,
                    function() end, false, 20)
                PP.Point(classSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                classSwatch:SetScript("OnClick", function() ApplyMode("class") end)
                classSwatch:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Color")
                end)
                classSwatch:SetScript("OnLeave", EllesmereUI.HideWidgetTooltip)

                local accentSwatch, refreshAccent = EllesmereUI.BuildColorSwatch(
                    rgn, borderRow:GetFrameLevel() + 3,
                    function() return EllesmereUI.GetAccentColor() end,
                    function() end, false, 20)
                PP.Point(accentSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
                accentSwatch:SetScript("OnClick", function() ApplyMode("accent") end)
                accentSwatch:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(accentSwatch, "Accent Color")
                end)
                accentSwatch:SetScript("OnLeave", EllesmereUI.HideWidgetTooltip)

                local customSwatch, refreshCustom = EllesmereUI.BuildColorSwatch(
                    rgn, borderRow:GetFrameLevel() + 3,
                    function()
                        local c = Cfg("panelBorderColor") or { r=1, g=1, b=1 }
                        return c.r, c.g, c.b, Cfg("panelBorderOpacity") or 0.18
                    end,
                    function(r, g, b, a)
                        Set("panelBorderColor", { r=r, g=g, b=b })
                        Set("panelBorderOpacity", a)
                        Set("panelBorderColorMode", "custom")
                        if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                    end,
                    true, 20)
                PP.Point(customSwatch, "RIGHT", accentSwatch, "LEFT", -8, 0)
                local customClick = customSwatch:GetScript("OnClick")
                customSwatch:SetScript("OnClick", function(self, ...)
                    if (Cfg("panelBorderColorMode") or "custom") ~= "custom" then
                        ApplyMode("custom")
                        return
                    end
                    if customClick then customClick(self, ...) end
                end)
                customSwatch:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color")
                end)
                customSwatch:SetScript("OnLeave", EllesmereUI.HideWidgetTooltip)

                local function RefreshBorderSwatches()
                    refreshCustom(); refreshAccent(); refreshClass()
                    local mode = Cfg("panelBorderColorMode") or "custom"
                    customSwatch:SetAlpha(mode == "custom" and 1 or 0.3)
                    accentSwatch:SetAlpha(mode == "accent" and 1 or 0.3)
                    classSwatch:SetAlpha(mode == "class" and 1 or 0.3)
                end
                EllesmereUI.RegisterWidgetRefresh(RefreshBorderSwatches)
                RefreshBorderSwatches()
            end

        -- -- IDLE FADE ---------------------------------------------------------
        _, h = W:SectionHeader(parent, "IDLE FADE", y); y = y - h

        -- Row 1: Enable Idle Fade | Fade Delay
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Idle Fade",
              getValue=function() return Cfg("idleFadeEnabled") ~= false end,
              setValue=function(v)
                  Set("idleFadeEnabled", v)
                  if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Fade Delay",
              min = 5, max = 30, step = 1,
              disabled=function() return Cfg("idleFadeEnabled") == false end,
              disabledTooltip="Enable Idle Fade",
              getValue=function() return Cfg("idleFadeDelay") or 15 end,
              setValue=function(v)
                  Set("idleFadeDelay", v)
                  if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
              end });  y = y - h

        -- Row 2 (odd last slot): Fade Strength | (empty)
        _, h = W:DualRow(parent, y,
            { type="slider", text="Fade Strength",
              min = 0, max = 100, step = 1,
              disabled=function() return Cfg("idleFadeEnabled") == false end,
              disabledTooltip="Enable Idle Fade",
              getValue=function() return Cfg("idleFadeStrength") or 40 end,
              setValue=function(v)
                  Set("idleFadeStrength", v)
                  if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
              end },
            { type="label", text="" });  y = y - h

        end -- isChat

        -- -- SIDEBAR -----------------------------------------------------------
        if isSidebar then
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
            showGuild      = "Guild",
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
            or { "showFriends", "showGuild", "showDurability", "showCopy", "showPortals", "showVoice", "showSettings" }
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

        -- Row 4: Separate Sidebar (+ cog: Sidebar Spacing) | (empty)
        local sepRow
        sepRow, h = W:DualRow(parent, y,
            { type="toggle", text="Separate Sidebar",
              tooltip="Separates the sidebar from the chat panel and gives it its own background and border.",
              getValue=function() return Cfg("sidebarSeparate") or false end,
              setValue=function(v)
                  Set("sidebarSeparate", v)
                  if ECHAT.ApplySidebarPosition then ECHAT.ApplySidebarPosition() end
                  if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                  EllesmereUI:RefreshPage()
              end },
            { type = "label", text = "" })
        do
            local lrgn = sepRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Separate Sidebar",
                rows = {
                    { type="slider", pixel=true, label="Sidebar Spacing",
                      min = 0, max = 30, step = 1,
                      get=function() return Cfg("sidebarSeparateSpacing") or 8 end,
                      set=function(v)
                          Set("sidebarSeparateSpacing", v)
                          if ECHAT.ApplySidebarPosition then ECHAT.ApplySidebarPosition() end
                          if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, lrgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", lrgn._lastInline or lrgn._control, "LEFT", -8, 0)
            lrgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(lrgn:GetFrameLevel() + 5)
            local function UpdateCogAlpha()
                cogBtn:SetAlpha(Cfg("sidebarSeparate") and 0.4 or 0.15)
            end
            UpdateCogAlpha()
            EllesmereUI.RegisterWidgetRefresh(UpdateCogAlpha)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) UpdateCogAlpha() end)
            cogBtn:SetScript("OnClick", function(s)
                if Cfg("sidebarSeparate") then cogShow(s) end
            end)
        end
        y = y - h

        end -- isSidebar

        if isTabs then
            _, h = W:SectionHeader(parent, "LAYOUT", y); y = y - h

            _, h = W:DualRow(parent, y,
                { type="toggle", text="Tabs Inside Chat Panel",
                  tooltip="Places the tabs inside one continuous chat panel background, including the sidebar when visible.",
                  getValue=function() return Cfg("extendBgBehindTabs") or false end,
                  setValue=function(v)
                      Set("extendBgBehindTabs", v)
                      if ECHAT.ApplyTabPadding then ECHAT.ApplyTabPadding() end
                      if ECHAT.ApplyTabSpacing then ECHAT.ApplyTabSpacing() end
                      EllesmereUI:RefreshPage()
                  end },
                { type="toggle", text="Align Tabs to Full Panel",
                  tooltip="Aligns the tab bar to the outer sidebar edge instead of only the chat panel edge.",
                  disabled=function()
                      return Cfg("extendBgBehindTabs") == true
                          or (Cfg("sidebarVisibility") or "always") == "never"
                  end,
                  disabledTooltip=function()
                      if Cfg("extendBgBehindTabs") then return "Tabs Inside Chat Panel" end
                      return "Sidebar Visibility"
                  end,
                  getValue=function() return Cfg("alignTabsToPanel") or false end,
                  setValue=function(v)
                      Set("alignTabsToPanel", v)
                      if ECHAT.ApplyTabPadding then ECHAT.ApplyTabPadding() end
                  end })
            y = y - h

            _, h = W:DualRow(parent, y,
                { type="slider", text="Tab Spacing", min=0, max=10, step=1,
                  disabled=function() return Cfg("extendBgBehindTabs") == true end,
                  disabledTooltip="Tabs Inside Chat Panel",
                  getValue=function() return Cfg("tabSpacing") or 1 end,
                  setValue=function(v)
                      Set("tabSpacing", v)
                      if ECHAT.ApplyTabSpacing then ECHAT.ApplyTabSpacing() end
                  end },
                { type="slider", text="Bottom Spacing to Panel", min=0, max=20, step=1,
                  disabled=function() return Cfg("extendBgBehindTabs") == true end,
                  disabledTooltip="Tabs Inside Chat Panel",
                  getValue=function() return Cfg("tabPadding") or 0 end,
                  setValue=function(v)
                      Set("tabPadding", v)
                      if ECHAT.ApplyTabPadding then ECHAT.ApplyTabPadding() end
                  end })
            y = y - h

            _, h = W:DualRow(parent, y,
                { type="slider", text="Tab Height", min=18, max=40, step=1,
                  getValue=function() return Cfg("tabHeight") or 24 end,
                  setValue=function(v)
                      Set("tabHeight", v)
                      if ECHAT.ApplyTabLayout then ECHAT.ApplyTabLayout() end
                  end },
                { type="slider", text="Inner Padding X", min=0, max=30, step=1,
                  getValue=function() return Cfg("tabInnerPaddingX") or 12 end,
                  setValue=function(v)
                      Set("tabInnerPaddingX", v)
                      if ECHAT.ApplyTabLayout then ECHAT.ApplyTabLayout() end
                  end })
            y = y - h

            _, h = W:SectionHeader(parent, "TYPOGRAPHY", y); y = y - h
            do
                local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
                _, h = W:DualRow(parent, y,
                    { type="dropdown", text="Tab Font",
                      values=fontValues, order=fontOrder,
                      getValue=function() return Cfg("tabFont") or "__global" end,
                      setValue=function(v)
                          Set("tabFont", v)
                          if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                          if ECHAT.ApplyTabLayout then ECHAT.ApplyTabLayout() end
                      end },
                    { type="slider", text="Tab Font Size", min=8, max=24, step=1,
                      getValue=function() return Cfg("tabFontSize") or 11 end,
                      setValue=function(v)
                          Set("tabFontSize", v)
                          if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                          if ECHAT.ApplyTabLayout then ECHAT.ApplyTabLayout() end
                      end })
                y = y - h
            end

            local function FontColorSwatch(active)
                local key = active and "tabFontColorActive" or "tabFontColor"
                local fallback = active and {r=1,g=1,b=1,a=1} or {r=1,g=1,b=1,a=.65}
                return {
                    { tooltip=active and "Active Tab Font Color" or "Tab Font Color", hasAlpha=true,
                      getValue=function()
                          local c=Cfg(key) or fallback
                          return c.r,c.g,c.b,c.a == nil and fallback.a or c.a
                      end,
                      setValue=function(r,g,b,a)
                          Set(key,{r=r,g=g,b=b,a=a})
                          if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                      end },
                }
            end
            _, h = W:DualRow(parent, y,
                { type="multiSwatch", text="Tab Font Color", swatches=FontColorSwatch(false) },
                { type="multiSwatch", text="Tab Font Color Active", swatches=FontColorSwatch(true) })
            y = y - h

            _, h = W:SectionHeader(parent, "APPEARANCE", y); y = y - h
            -- Tab background: opacity slider + inline RGB swatch per state.
            -- Same stored tables as the old picker rows ({r,g,b,a} in
            -- tabBackgroundColor / tabBackgroundColorActive): the slider edits
            -- .a, the swatch edits rgb. No migration -- these keys have only
            -- ever existed in tester builds of PR #841, never in a release.
            local TAB_BG_FALLBACK = {
                [false] = { r=.03, g=.045, b=.05, a=.44 },
                [true]  = { r=.03, g=.045, b=.05, a=.65 },
            }
            local function TabBgSliderCfg(active)
                local key = active and "tabBackgroundColorActive" or "tabBackgroundColor"
                local fallback = TAB_BG_FALLBACK[active]
                return {
                    type="slider",
                    text=active and "Tab Background Color Active" or "Tab Background Color",
                    min=0, max=100, step=1, trackWidth=120,
                    getValue=function()
                        local c = Cfg(key) or fallback
                        local a = c.a == nil and fallback.a or c.a
                        return math.floor(a * 100 + 0.5)
                    end,
                    setValue=function(v)
                        local c = Cfg(key) or fallback
                        Set(key, { r=c.r, g=c.g, b=c.b, a=v/100 })
                        if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                    end,
                }
            end
            local tabBgRow
            tabBgRow, h = W:DualRow(parent, y, TabBgSliderCfg(false), TabBgSliderCfg(true))
            local function AttachTabBgSwatch(rgn, active)
                local key = active and "tabBackgroundColorActive" or "tabBackgroundColor"
                local fallback = TAB_BG_FALLBACK[active]
                local swatch, refresh = EllesmereUI.BuildColorSwatch(
                    rgn, tabBgRow:GetFrameLevel() + 3,
                    function()
                        local c = Cfg(key) or fallback
                        return c.r, c.g, c.b, 1
                    end,
                    function(r, g, b)
                        local c = Cfg(key) or fallback
                        local a = c.a == nil and fallback.a or c.a
                        Set(key, { r=r, g=g, b=b, a=a })
                        if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                    end,
                    false, 20)
                PP.Point(swatch, "RIGHT", rgn._control, "LEFT", -8, 0)
                rgn._lastInline = swatch
                EllesmereUI.RegisterWidgetRefresh(refresh)
            end
            AttachTabBgSwatch(tabBgRow._leftRegion, false)
            AttachTabBgSwatch(tabBgRow._rightRegion, true)
            y = y - h

            local function UnderlineSwatches()
                return {
                    { tooltip="Custom Color", hasAlpha=true,
                      getValue=function()
                          local c=Cfg("activeUnderlineColor") or {r=.05,g=.82,b=.61,a=1}
                          return c.r,c.g,c.b,c.a == nil and 1 or c.a
                      end,
                      setValue=function(r,g,b,a)
                          Set("activeUnderlineColor",{r=r,g=g,b=b,a=a})
                          Set("activeUnderlineColorMode","custom")
                          if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                      end,
                      onClick=function(self)
                          if (Cfg("activeUnderlineColorMode") or "accent") ~= "custom" then
                              Set("activeUnderlineColorMode","custom")
                              if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                              EllesmereUI:RefreshPage(); return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha=function() return (Cfg("activeUnderlineColorMode") or "accent") == "custom" and 1 or .3 end },
                    { tooltip="Accent Color", hasAlpha=false,
                      getValue=function() return EllesmereUI.GetAccentColor() end,
                      setValue=function() end,
                      onClick=function()
                          Set("activeUnderlineColorMode","accent")
                          if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                          EllesmereUI:RefreshPage()
                      end,
                      refreshAlpha=function() return (Cfg("activeUnderlineColorMode") or "accent") == "accent" and 1 or .3 end },
                    { tooltip="Border Color", hasAlpha=false,
                      getValue=function()
                          local mode=Cfg("panelBorderColorMode") or "custom"
                          if mode=="accent" then return EllesmereUI.GetAccentColor() end
                          if mode=="class" then
                              local _,cl=UnitClass("player"); local c=cl and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cl]
                              return c and c.r or 1,c and c.g or 1,c and c.b or 1
                          end
                          local c=Cfg("panelBorderColor") or {r=1,g=1,b=1}; return c.r,c.g,c.b
                      end,
                      setValue=function() end,
                      onClick=function()
                          Set("activeUnderlineColorMode","border")
                          if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                          EllesmereUI:RefreshPage()
                      end,
                      refreshAlpha=function() return (Cfg("activeUnderlineColorMode") or "accent") == "border" and 1 or .3 end },
                }
            end
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Active Underline",
                  getValue=function() return Cfg("activeUnderline") ~= false end,
                  setValue=function(v)
                      Set("activeUnderline",v)
                      if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                  end },
                { type="multiSwatch", text="Underline Color", swatches=UnderlineSwatches() })
            y = y - h

            -- (No tab idle-fade section: the per-tab fade layer was removed
            -- 2026-07-20 -- Blizzard's own tab alpha machinery always won and
            -- the setting visibly did nothing. Tabs fade with the chat panel
            -- via the dock; see the tab-alpha note in EllesmereUIChat.lua.)

            _, h = W:SectionHeader(parent, "BORDER", y); y = y - h
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Sync Border with Chat Panel",
                  disabled=function() return Cfg("extendBgBehindTabs") == true end,
                  disabledTooltip="Tabs Inside Chat Panel",
                  getValue=function() return Cfg("syncTabBorder") ~= false end,
                  setValue=function(v)
                      Set("syncTabBorder", v)
                      if ECHAT.ApplyTabBorders then ECHAT.ApplyTabBorders() end
                      EllesmereUI:RefreshPage()
                  end },
                { type="label", text="" })
            y = y - h
            local syncTabs = function() return Cfg("syncTabBorder") ~= false end
            local tabBordersDisabled = function()
                return Cfg("extendBgBehindTabs") == true or syncTabs()
            end
            local function TabBorderDisabledTip()
                if Cfg("extendBgBehindTabs") then return "Tabs Inside Chat Panel" end
                return "Sync Border with Chat Panel"
            end
            local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
            local thicknessValues = {
                none={text="None"}, thin={text="Thin"}, normal={text="Normal"},
                heavy={text="Heavy"}, strong={text="Strong"},
            }
            local borderRow
            borderRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style",
                  disabled=tabBordersDisabled, disabledTooltip=TabBorderDisabledTip,
                  values=texValues, order=texOrder,
                  getValue=function() return Cfg("tabBorderTexture") or "solid" end,
                  setValue=function(v)
                      Set("tabBorderTexture", v)
                      Set("tabBorderOffsetX", nil); Set("tabBorderOffsetY", nil)
                      Set("tabBorderShiftX", nil); Set("tabBorderShiftY", nil)
                      local def = EllesmereUI.GetBorderDefaultSize("chat", v)
                          or EllesmereUI.GetBorderTextureDefaultThickness(v)
                      if def then Set("tabBorderThickness", def) end
                      if ECHAT.ApplyTabBorders then ECHAT.ApplyTabBorders() end
                      EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", text="Border Size",
                  disabled=tabBordersDisabled, disabledTooltip=TabBorderDisabledTip,
                  values=thicknessValues, order={"none","thin","normal","heavy","strong"},
                  getValue=function() return Cfg("tabBorderThickness") or "none" end,
                  setValue=function(v)
                      Set("tabBorderThickness", v)
                      if ECHAT.ApplyTabBorders then ECHAT.ApplyTabBorders() end
                  end })
            y = y - h

            do
                local rgn = borderRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title="Tab Border Offset", captureRegion=rgn,
                    rows={
                        { type="slider", label="Offset X", min=-10, max=10, step=1,
                          get=function()
                              local v=Cfg("tabBorderOffsetX"); if v~=nil then return v end
                              return EllesmereUI.GetBorderDefaults("chat",Cfg("tabBorderTexture") or "solid",Cfg("tabBorderThickness") or "none")
                          end,
                          set=function(v) Set("tabBorderOffsetX", v); ECHAT.ApplyTabBorders() end },
                        { type="slider", label="Offset Y", min=-10, max=10, step=1,
                          get=function()
                              local v=Cfg("tabBorderOffsetY"); if v~=nil then return v end
                              local _,d=EllesmereUI.GetBorderDefaults("chat",Cfg("tabBorderTexture") or "solid",Cfg("tabBorderThickness") or "none"); return d
                          end,
                          set=function(v) Set("tabBorderOffsetY", v); ECHAT.ApplyTabBorders() end },
                        { type="slider", label="Shift X", min=-10, max=10, step=1,
                          get=function()
                              local v=Cfg("tabBorderShiftX"); if v~=nil then return v end
                              local _,_,d=EllesmereUI.GetBorderDefaults("chat",Cfg("tabBorderTexture") or "solid",Cfg("tabBorderThickness") or "none"); return d
                          end,
                          set=function(v) Set("tabBorderShiftX", v == 0 and nil or v); ECHAT.ApplyTabBorders() end },
                        { type="slider", label="Shift Y", min=-10, max=10, step=1,
                          get=function()
                              local v=Cfg("tabBorderShiftY"); if v~=nil then return v end
                              local _,_,_,d=EllesmereUI.GetBorderDefaults("chat",Cfg("tabBorderTexture") or "solid",Cfg("tabBorderThickness") or "none"); return d
                          end,
                          set=function(v) Set("tabBorderShiftY", v == 0 and nil or v); ECHAT.ApplyTabBorders() end },
                    },
                })
                local btn = CreateFrame("Button", nil, rgn)
                btn:SetSize(26,26); btn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
                btn:SetFrameLevel(rgn:GetFrameLevel()+5)
                local tex = btn:CreateTexture(nil,"OVERLAY"); tex:SetAllPoints(); tex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
                local function Refresh() btn:SetAlpha(tabBordersDisabled() and 0.15 or 0.4) end
                btn:SetScript("OnEnter", function(self)
                    if tabBordersDisabled() then EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip(TabBorderDisabledTip()))
                    else self:SetAlpha(0.7) end
                end)
                btn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip(); Refresh() end)
                btn:SetScript("OnClick", function(self) if not tabBordersDisabled() then cogShow(self) end end)
                EllesmereUI.RegisterWidgetRefresh(Refresh); Refresh()
            end

            do
                local rgn, ctrl = borderRow._rightRegion, borderRow._rightRegion._control
                local function SetMode(mode)
                    if tabBordersDisabled() then return end
                    Set("tabBorderColorMode", mode); ECHAT.ApplyTabBorders(); EllesmereUI:RefreshPage()
                end
                local classSw, refreshClass = EllesmereUI.BuildColorSwatch(rgn, borderRow:GetFrameLevel()+3,
                    function() local _,cl=UnitClass("player"); local c=cl and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cl]; return c and c.r or 1,c and c.g or 1,c and c.b or 1 end,
                    function() end, false, 20)
                PP.Point(classSw,"RIGHT",ctrl,"LEFT",-8,0); classSw:SetScript("OnClick",function() SetMode("class") end)
                local accentSw, refreshAccent = EllesmereUI.BuildColorSwatch(rgn, borderRow:GetFrameLevel()+3,
                    function() return EllesmereUI.GetAccentColor() end, function() end, false, 20)
                PP.Point(accentSw,"RIGHT",classSw,"LEFT",-8,0); accentSw:SetScript("OnClick",function() SetMode("accent") end)
                local customSw, refreshCustom = EllesmereUI.BuildColorSwatch(rgn, borderRow:GetFrameLevel()+3,
                    function() local c=Cfg("tabBorderColor") or {r=1,g=1,b=1}; return c.r,c.g,c.b,Cfg("tabBorderOpacity") or 0.18 end,
                    function(r,g,b,a) Set("tabBorderColor",{r=r,g=g,b=b}); Set("tabBorderOpacity",a); Set("tabBorderColorMode","custom"); ECHAT.ApplyTabBorders() end,
                    true,20)
                PP.Point(customSw,"RIGHT",accentSw,"LEFT",-8,0)
                local orig=customSw:GetScript("OnClick")
                customSw:SetScript("OnClick",function(self,...)
                    if tabBordersDisabled() then return end
                    if (Cfg("tabBorderColorMode") or "custom") ~= "custom" then SetMode("custom") elseif orig then orig(self,...) end
                end)
                local function Refresh()
                    refreshClass(); refreshAccent(); refreshCustom()
                    local off, mode=tabBordersDisabled(), Cfg("tabBorderColorMode") or "custom"
                    customSw:SetAlpha(off and .15 or (mode=="custom" and 1 or .3))
                    accentSw:SetAlpha(off and .15 or (mode=="accent" and 1 or .3))
                    classSw:SetAlpha(off and .15 or (mode=="class" and 1 or .3))
                end
                EllesmereUI.RegisterWidgetRefresh(Refresh); Refresh()
            end

            -- Row: Active Tab Border (+ inline color swatch) | Tab Background Texture
            -- Texture catalogue (same build as the Chat page's Background
            -- Texture dropdown -- that local is scoped to the isChat block).
            if ECHAT.RefreshBgTextureCatalogue then ECHAT.RefreshBgTextureCatalogue() end
            local btValues, btOrder = {}, {}
            do
                local texNames = ns.chatBgTextureNames or {}
                for _, key in ipairs(ns.chatBgTextureOrder or {}) do
                    if key ~= "---" then
                        btValues[key] = texNames[key] or key
                        btOrder[#btOrder + 1] = key
                    end
                end
                local texLookup = ns.chatBgTextures or {}
                btValues._menuOpts = {
                    itemHeight = 28,
                    background = function(key)
                        return texLookup[key]
                    end,
                }
            end
            local activeBorderRow
            activeBorderRow, h = W:DualRow(parent, y,
                { type="toggle", text="Active Tab Border",
                  tooltip="Gives the selected tab its own border color.",
                  disabled=tabBordersDisabled, disabledTooltip=TabBorderDisabledTip,
                  getValue=function() return Cfg("activeTabBorder") ~= false end,
                  setValue=function(v)
                      Set("activeTabBorder", v)
                      if ECHAT.ApplyTabBorders then ECHAT.ApplyTabBorders() end
                      EllesmereUI:RefreshPage()
                  end },
                { type="dropdown", text="Tab Background Texture",
                  tooltip="Texture drawn over the tab background colors.",
                  values=btValues, order=btOrder,
                  disabled=function() return Cfg("syncTabBorder") ~= false end,
                  disabledTooltip="Requires Sync Style with Chat Panel disabled",
                  getValue=function() return Cfg("tabBackgroundTexture") or "none" end,
                  setValue=function(v)
                      Set("tabBackgroundTexture", v)
                      if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                  end })
            do
                local rgn = activeBorderRow._leftRegion
                local swatch, refreshSwatch = EllesmereUI.BuildColorSwatch(
                    rgn, activeBorderRow:GetFrameLevel() + 3,
                    function()
                        local c = Cfg("tabBorderColorActive") or { r=1, g=1, b=1 }
                        return c.r, c.g, c.b, c.a == nil and 0.18 or c.a
                    end,
                    function(r, g, b, a)
                        Set("tabBorderColorActive", { r=r, g=g, b=b, a=a })
                        if ECHAT.ApplyTabBorders then ECHAT.ApplyTabBorders() end
                    end,
                    true, 20)
                PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
                rgn._lastInline = swatch
                swatch:SetScript("OnEnter", function()
                    EllesmereUI.ShowWidgetTooltip(swatch, "Active Border Color")
                end)
                swatch:SetScript("OnLeave", EllesmereUI.HideWidgetTooltip)
                local function RefreshActiveSwatch()
                    refreshSwatch()
                    local off = tabBordersDisabled() or Cfg("activeTabBorder") == false
                    swatch:SetAlpha(off and 0.3 or 1)
                end
                EllesmereUI.RegisterWidgetRefresh(RefreshActiveSwatch)
                RefreshActiveSwatch()
            end
            y = y - h
        end -- isTabs

        -- -- EXTRAS ------------------------------------------------------------
        if isChat then
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
        local extrasBorderRow
        extrasBorderRow, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Tooltip on Hover",
              getValue=function() return Cfg("hideTooltipOnHover") or false end,
              setValue=function(v) Set("hideTooltipOnHover", v) end },
            { type="toggle", text="Hide Borders",
              getValue=function() return Cfg("hideBorders") or false end,
              setValue=function(v)
                  Set("hideBorders", v)
                  if ECHAT.ApplyBorders then ECHAT.ApplyBorders() end
                  EllesmereUI:RefreshPage()
              end })
        do
            local rgn = extrasBorderRow._rightRegion
            local ctrl = rgn._control
            local function SetInnerMode(mode)
                if Cfg("hideBorders") then return end
                Set("innerBorderColorMode", mode)
                if ECHAT.ApplyBorders then ECHAT.ApplyBorders() end
                if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                if ECHAT.ApplyTabSeparators then ECHAT.ApplyTabSeparators() end
                EllesmereUI:RefreshPage()
            end
            local swatch, refreshSwatch = EllesmereUI.BuildColorSwatch(
                rgn, extrasBorderRow:GetFrameLevel() + 3,
                function()
                    local c = Cfg("innerBorderColor") or { r=1, g=1, b=1, a=0.06 }
                    return c.r, c.g, c.b, c.a == nil and 0.06 or c.a
                end,
                function(r, g, b, a)
                    Set("innerBorderColor", { r=r, g=g, b=b, a=a })
                    Set("innerBorderColorMode", "custom")
                    if ECHAT.ApplyBorders then ECHAT.ApplyBorders() end
                    if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                    if ECHAT.ApplyTabSeparators then ECHAT.ApplyTabSeparators() end
                end,
                true, 20)
            PP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
            -- Accent mode swatch sits left of the custom one (select-mode-
            -- first convention, matching the tab border color trio).
            local accentSw, refreshAccent = EllesmereUI.BuildColorSwatch(
                rgn, extrasBorderRow:GetFrameLevel() + 3,
                function() return EllesmereUI.GetAccentColor() end,
                function() end, false, 20)
            PP.Point(accentSw, "RIGHT", swatch, "LEFT", -8, 0)
            accentSw:SetScript("OnClick", function() SetInnerMode("accent") end)
            accentSw:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(accentSw, "Accent Inner Border Color")
            end)
            accentSw:SetScript("OnLeave", EllesmereUI.HideWidgetTooltip)
            local origClick = swatch:GetScript("OnClick")
            swatch:SetScript("OnClick", function(self, ...)
                if Cfg("hideBorders") then return end
                if (Cfg("innerBorderColorMode") or "custom") ~= "custom" then
                    SetInnerMode("custom")
                elseif origClick then
                    origClick(self, ...)
                end
            end)
            swatch:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(swatch, "Inner Border Color")
            end)
            swatch:SetScript("OnLeave", EllesmereUI.HideWidgetTooltip)
            local function RefreshInner()
                refreshSwatch(); refreshAccent()
                local off = Cfg("hideBorders")
                local mode = Cfg("innerBorderColorMode") or "custom"
                swatch:SetAlpha(off and 0.3 or (mode == "custom" and 1 or 0.3))
                accentSw:SetAlpha(off and 0.3 or (mode == "accent" and 1 or 0.3))
            end
            EllesmereUI.RegisterWidgetRefresh(RefreshInner)
            RefreshInner()
        end
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

        end -- isChat

        return math.abs(y)
    end

    _G._EBS_BuildChatPage = BuildPage

    EllesmereUI:RegisterModule("EllesmereUIChat", {
        title       = "Chat",
        description = "Chat frame reskin, clickable URLs, copy chat, sidebar icons.",
        pages       = { "Chat", "Tabs", "Sidebar" },
        buildPage   = function(pageName, p, yOffset) return BuildPage(pageName, p, yOffset) end,
        searchTerms = "chat tabs border spacing background sidebar friends voice url copy whisper",
        onReset = function()
            local d = _G._ECHAT_DB
            if d and d.ResetProfile then d:ResetProfile() end
            RefreshAll()
            EllesmereUI:InvalidatePageCache()
        end,
    })
end)
