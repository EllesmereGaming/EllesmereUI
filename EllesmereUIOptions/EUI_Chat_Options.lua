if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_Chat_Options.lua
--
--  Options page for EllesmereUI Chat: visibility, background opacity/color,
--  top accent line.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIChat"]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page
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
        -- Reset Profile wipes the bubble settings too; without this the feature keeps
        -- running with Blizzard's CVars still suppressed against settings that are gone.
        if ns.ChatBubbles then ns.ChatBubbles.Refresh() end
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
        local isBubbles = pageName == "Chat Bubbles"

        -- Stock styles (Blizzard Style / Classic WoW UI) reveal Blizzard's own
        -- chat frame art and input box: the panel background, panel border and
        -- input layout rows only apply to the EllesmereUI look and hide there.
        -- Blizzard Style also shows Blizzard's own tabs (no Tabs page; a deep
        -- link lands on the banner alone); Classic keeps the tab typography.
        local BS = EllesmereUI.BlizzStyle
        local STOCK = BS and BS.Get("chat")
        if isTabs and STOCK then
            y = BS.Note(parent, y, "chat")
            if BS.Active("chat") == "blizzard" then isTabs = false end
        end

        if isChat then

        -- Chat position is an EUI unlock element now; the old Edit Mode
        -- reposition banner and its Force Chat on Screen link are gone.

        -- -- DISPLAY -----------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h
        if BS then y = BS.Note(parent, y, "chat") end

        -- Row 1: Visibility (one control; no mouseover for chat frames) | Lock Main Chat Size
        _, h = EllesmereUI.BuildVisibilityRow(W, parent, y,
            { getStore = DB, legacyKey = "visibility",
              caps = { partyIncludesRaid = false, noMouseover = true, luaDragonriding = true },
              onChanged = function()
                  if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
                  if ECHAT.ApplyIdleFadeHoverMotion then ECHAT.ApplyIdleFadeHoverMotion() end
                  RefreshAll()
              end,
              onOptionChanged = RefreshAll },
            { type="toggle", text="Lock Main Chat Size",
              tooltip="Hides the resize handle on the main chat frame, preventing accidental resizing.",
              getValue=function() return Cfg("lockChatSize") or false end,
              setValue=function(v)
                  Set("lockChatSize", v)
                  if ECHAT.ApplyLockChatSize then ECHAT.ApplyLockChatSize() end
              end })
        y = y - h

        -- Row 2: Background Opacity (+ inline color swatch) | Background
        -- Texture (Unit Frames bar texture catalogue incl. SharedMedia, with
        -- per-item texture preview backgrounds). Stock styles: Blizzard's own
        -- background (its tab menu's Background swatch sets it).
        if not STOCK then
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
        if not EllesmereUI._prebuilding then
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
        end -- not STOCK

        -- Row 3: Font (+ cog: Outline Mode) | Font Size
        do
            local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
            local fontRow
            fontRow, h = W:DualRow(parent, y,
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
                          reload      = true,
                      })
                  end },
                { type="slider", text="Font Size",
                  tooltip="Applies one text size to every chat window, saved with your profile. Individual windows can still be adjusted from their tab's right-click menu until the next login re-applies the profile size.",
                  min = 8, max = 27, step = 1,
                  getValue=function()
                      if Cfg("chatFontSize") then return Cfg("chatFontSize") end
                      local cf = _G.ChatFrame1
                      if cf and cf.GetFont then
                          local _, fh = cf:GetFont()
                          if fh and fh > 0 then return math.floor(fh + 0.5) end
                      end
                      return 14
                  end,
                  setValue=function(v)
                      Set("chatFontSize", v)
                      if ECHAT.ApplyChatFontSize then ECHAT.ApplyChatFontSize(v) end
                  end })
            -- Cog for Outline Mode
            if not EllesmereUI._prebuilding then
                local rrgn = fontRow._leftRegion
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
                                  reload      = true,
                              })
                          end },
                    },
                })
                EllesmereUI.MakeCogBtn(rrgn, cogShow)
            end
        end
        y = y - h

        -- Outer panel border. Without the extended background, visible tabs get
        -- matching individual borders instead of outlining empty tab-strip space.
        -- Stock styles: Blizzard's own frame border.
        if not STOCK then
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
                      -- A style pick lands on the style's default step, so an exact
                      -- pixel size paired with the old step is cleared (false, not
                      -- nil: the clear must travel through mirror sync).
                      if Cfg("panelBorderThicknessPx") then Set("panelBorderThicknessPx", false) end
                      local defSize = EllesmereUI.GetBorderDefaultSize("chat", v)
                          or EllesmereUI.GetBorderTextureDefaultThickness(v)
                      -- Unregistered SharedMedia borders default to the NUMBER 1; this key stores labels.
                      if type(defSize) == "number" then defSize = EllesmereUI.BORDER_LABEL_OF_STEP[defSize] or "thin" end
                      if defSize then Set("panelBorderThickness", defSize) end
                      if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                      -- Rebuild: the offset row below exists only for a textured style.
                      EllesmereUI:RefreshPage(true)
                  end },
                EllesmereUI.BorderPxSliderCfg{ text="Border Size",
                  -- The step the panel renders with: its label as a step, anything unknown = thin.
                  getStep=function() return EllesmereUI.BORDER_STEP_OF_LABEL[Cfg("panelBorderThickness") or "none"] or 1 end,
                  setStep=function(step) Set("panelBorderThickness", EllesmereUI.BORDER_LABEL_OF_STEP[step]) end,
                  getTex=function() return Cfg("panelBorderTexture") or "solid" end,
                  getPx=function() return Cfg("panelBorderThicknessPx") end,
                  setPx=function(v) Set("panelBorderThicknessPx", v) end,
                  apply=function()
                      if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                  end })
            y = y - h

            -- Width Offset | Height Offset: a textured style's outward offsets in their
            -- own row (Solid has none). Same registry row the panel renders with:
            -- "chat" + the thickness label as sizeKey.
            do
                local pTex = Cfg("panelBorderTexture")
                if pTex and pTex ~= "" and pTex ~= "solid" then
                    local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs{
                        addonKey = "chat",
                        getTex=function() return Cfg("panelBorderTexture") or "solid" end,
                        getStep=function() return EllesmereUI.BORDER_STEP_OF_LABEL[Cfg("panelBorderThickness") or "none"] or 1 end,
                        getSizeKey=function() return Cfg("panelBorderThickness") or "none" end,
                        getPx=function() return Cfg("panelBorderThicknessPx") end,
                        getX=function() return Cfg("panelBorderOffsetX") end,
                        setX=function(v) Set("panelBorderOffsetX", v) end,
                        getY=function() return Cfg("panelBorderOffsetY") end,
                        setY=function(v) Set("panelBorderOffsetY", v) end,
                        apply=function()
                            if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                        end }
                    _, h = W:DualRow(parent, y, ocfgL, ocfgR)
                    y = y - h
                end
            end

            -- Border options cog on Border Style (Show Behind, shifts).
            do
                local rgn = borderRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Border Options",
                    captureRegion = rgn,
                    rows = {
                        { type="toggle", label="Show Behind",
                          get=function() return Cfg("panelBorderBehind") or false end,
                          set=function(v)
                              Set("panelBorderBehind", v)
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
                EllesmereUI.MakeCogBtn(rgn, cogShow, rgn._control, EllesmereUI.DIRECTIONS_ICON)
            end

            -- Accent, custom, and class-color selectors beside Border Size.
            if not EllesmereUI._prebuilding then
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
        end -- not STOCK

        -- -- IDLE FADE ---------------------------------------------------------
        _, h = W:SectionHeader(parent, "IDLE FADE", y); y = y - h

        -- Row 1: Enable Idle Fade | Fade Delay
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Idle Fade",
              getValue=function() return Cfg("idleFadeEnabled") ~= false end,
              setValue=function(v)
                  Set("idleFadeEnabled", v)
                  if ECHAT.ResetIdleTimer then ECHAT.ResetIdleTimer() end
                  if ECHAT.ApplyIdleFadeHoverMotion then ECHAT.ApplyIdleFadeHoverMotion() end
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
        if STOCK then y = BS.Note(parent, y, "chat") end

        -- Row 1: Sidebar Visibility (+ cog) | Sidebar Background
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
            -- Classic WoW UI draws nothing behind the column; Blizzard
            -- Style's column backdrop follows this toggle.
            (function(cfg)
                if STOCK and BS.Active("chat") == "classic" then BS.Gate("chat", cfg) end
                return cfg
            end)({ type="toggle", text="Hide Sidebar Background",
              getValue=function() return Cfg("hideSidebarBg") or false end,
              setValue=function(v)
                  Set("hideSidebarBg", v)
                  if ECHAT.ApplySidebarBackground then ECHAT.ApplySidebarBackground() end
              end }))
        -- Cog for Sidebar Visibility
        if not EllesmereUI._prebuilding then
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
            EllesmereUI.MakeCogBtn(lrgn, cogShow)
        end
        y = y - h

        local sidebarLayoutRow
        sidebarLayoutRow, h = W:DualRow(parent, y,
            { type="slider", text="Sidebar Width", min=30, max=100, step=1,
              getValue=function()
                  return Cfg("sidebarWidth") or (ECHAT.SidebarWidthDefault and ECHAT.SidebarWidthDefault() or 40)
              end,
              setValue=function(v)
                  Set("sidebarWidth", v)
                  if ECHAT.ApplySidebarWidth then ECHAT.ApplySidebarWidth() end
              end },
            { type="toggle", text="Separate Sidebar",
              tooltip="Separates the sidebar from the chat panel and gives it its own background and border.",
              getValue=function() return Cfg("sidebarSeparate") or false end,
              setValue=function(v)
                  Set("sidebarSeparate", v)
                  if ECHAT.ApplySidebarPosition then ECHAT.ApplySidebarPosition() end
                  if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                  EllesmereUI:RefreshPage()
              end })
        if not EllesmereUI._prebuilding then
            local lrgn = sidebarLayoutRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title="Separate Sidebar",
                rows={
                    { type="slider", pixel=true, label="Sidebar Spacing",
                      min=0, max=30, step=1,
                      get=function() return Cfg("sidebarSeparateSpacing") or 8 end,
                      set=function(v)
                          Set("sidebarSeparateSpacing", v)
                          if ECHAT.ApplySidebarPosition then ECHAT.ApplySidebarPosition() end
                          if ECHAT.ApplyExtendedBackground then ECHAT.ApplyExtendedBackground() end
                      end },
                },
            })
            EllesmereUI.MakeCogBtn(lrgn, cogShow, nil, nil, function() return not Cfg("sidebarSeparate") end)
        end
        y = y - h

        _, h = W:SectionHeader(parent, "ICONS", y); y = y - h

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
        local iconOptionsRow
        iconOptionsRow, h = W:DualRow(parent, y,
            -- The stock styles keep the stock column art (no tint).
            EllesmereUI.BlizzStyle.Gate("chat", { type="multiSwatch", text="Sidebar Icons Color",
              swatches = MakeIconColorSwatches() }),
            { type="dropdown", text="Sidebar Icons",
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end })
        if not EllesmereUI._prebuilding then
            local rightRgn = iconOptionsRow._rightRegion
            if rightRgn._control then rightRgn._control:Hide() end
            local pendingIconReload = false
            local cbDD, cbDDRefresh = EllesmereUI.BuildReorderCBDropdown(
                rightRgn, 210, rightRgn:GetFrameLevel() + 2,
                sidebarIconItems,
                function(k) return Cfg(k) ~= false end,
                function(k, v)
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
                    end,
                    onClose = function(orderChanged)
                        if not orderChanged and not pendingIconReload then return end
                        pendingIconReload = false
                        EllesmereUI:ShowConfirmPopup({
                            title="Reload Required",
                            message="A UI reload is needed to apply your sidebar icon changes.",
                            confirmText="Reload Now", cancelText="Later",
                            reload = true,
                        })
                    end,
                })
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
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
        if not EllesmereUI._prebuilding then
            local lrgn = sizeRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Icon Settings",
                rows = {
                    -- The stock styles keep their own spacing (the visible
                    -- gap between button art; Blizzard's packing by default).
                    { type="slider", pixel=true, label="Icon Spacing",
                      min = 0, max = 30, step = 1,
                      get=function()
                          if STOCK then return Cfg("stockIconSpacing") or 4 end
                          return Cfg("sidebarIconSpacing") or 10
                      end,
                      set=function(v)
                          Set(STOCK and "stockIconSpacing" or "sidebarIconSpacing", v)
                          if ECHAT.ApplySidebarIcons then ECHAT.ApplySidebarIcons() end
                      end },
                },
            })
            EllesmereUI.MakeCogBtn(lrgn, cogShow)
        end
        -- "Reset" label next to the Free Move Icons toggle (only visible when enabled)
        if not EllesmereUI._prebuilding then
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

        -- Row 4: Scroll Button on Chat Panel | (empty)
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Scroll Button on Chat Panel",
              tooltip="Anchors the Scroll to Bottom button to the bottom-right corner of the chat panel instead of the sidebar.",
              getValue=function() return Cfg("scrollButtonOnChat") == true end,
              setValue=function(v)
                  Set("scrollButtonOnChat", v)
                  if ECHAT.ApplySidebarIcons then ECHAT.ApplySidebarIcons() end
                  if ECHAT.ApplySidebarVisibility then ECHAT.ApplySidebarVisibility() end
              end },
            { type="label", text="" });  y = y - h

        end -- isSidebar

        if isTabs then
            -- Classic WoW UI paints the vanilla tab sheet at Blizzard's tab
            -- geometry: only the TYPOGRAPHY section applies there.
            if not STOCK then
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
                      if Cfg("extendBgBehindTabs") then return "This option requires Tabs Inside Chat Panel to be disabled" end
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
                  disabledTooltip="Tabs Inside Chat Panel", requireState="disabled",
                  getValue=function() return Cfg("tabSpacing") or 1 end,
                  setValue=function(v)
                      Set("tabSpacing", v)
                      if ECHAT.ApplyTabSpacing then ECHAT.ApplyTabSpacing() end
                  end },
                { type="slider", text="Bottom Spacing to Panel", min=0, max=20, step=1,
                  disabled=function() return Cfg("extendBgBehindTabs") == true end,
                  disabledTooltip="Tabs Inside Chat Panel", requireState="disabled",
                  getValue=function() return Cfg("tabPadding") or 0 end,
                  setValue=function(v)
                      Set("tabPadding", v)
                      if ECHAT.ApplyTabPadding then ECHAT.ApplyTabPadding() end
                  end })
            y = y - h

            local tabSizeRow
            tabSizeRow, h = W:DualRow(parent, y,
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
            -- Cog on Inner Padding X: Tab Offset X (applies in both tab modes)
            if not EllesmereUI._prebuilding then
                local rrgn = tabSizeRow._rightRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title = "Tab Layout",
                    rows = {
                        { type="slider", label="Tab Offset X",
                          min = -100, max = 100, step = 1,
                          get=function() return Cfg("tabOffsetX") or 0 end,
                          set=function(v)
                              Set("tabOffsetX", v)
                              if ECHAT.ApplyTabPadding then ECHAT.ApplyTabPadding() end
                          end },
                    },
                })
                EllesmereUI.MakeCogBtn(rrgn, cogShow)
            end
            y = y - h
            end -- not STOCK (LAYOUT)

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
                if active then
                    local function SetMode(mode)
                        Set("tabFontColorActiveMode", mode)
                        if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                        EllesmereUI:RefreshPage()
                    end
                    return {
                        { tooltip="Custom Color", hasAlpha=true,
                          getValue=function()
                              local c=Cfg(key) or fallback
                              return c.r,c.g,c.b,c.a == nil and fallback.a or c.a
                          end,
                          setValue=function(r,g,b,a)
                              Set(key,{r=r,g=g,b=b,a=a})
                              Set("tabFontColorActiveMode","custom")
                              if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                          end,
                          onClick=function(self)
                              if (Cfg("tabFontColorActiveMode") or "custom") ~= "custom" then
                                  SetMode("custom"); return
                              end
                              if self._eabOrigClick then self._eabOrigClick(self) end
                          end,
                          refreshAlpha=function()
                              return (Cfg("tabFontColorActiveMode") or "custom") == "custom" and 1 or .3
                          end },
                        { tooltip="Accent Color", hasAlpha=false,
                          getValue=function() return EllesmereUI.GetAccentColor() end,
                          setValue=function() end,
                          onClick=function() SetMode("accent") end,
                          refreshAlpha=function()
                              return (Cfg("tabFontColorActiveMode") or "custom") == "accent" and 1 or .3
                          end },
                        { tooltip="Class Color", hasAlpha=false,
                          getValue=function()
                              local _,class=UnitClass("player")
                              local c=class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                              return c and c.r or 1,c and c.g or 1,c and c.b or 1
                          end,
                          setValue=function() end,
                          onClick=function() SetMode("class") end,
                          refreshAlpha=function()
                              return (Cfg("tabFontColorActiveMode") or "custom") == "class" and 1 or .3
                          end },
                    }
                end
                local function SetMode(mode)
                    Set("tabFontColorMode", mode)
                    if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                    EllesmereUI:RefreshPage()
                end
                return {
                    { tooltip="Custom Color", hasAlpha=true,
                      getValue=function()
                          local c=Cfg(key) or fallback
                          return c.r,c.g,c.b,c.a == nil and fallback.a or c.a
                      end,
                      setValue=function(r,g,b,a)
                          Set(key,{r=r,g=g,b=b,a=a})
                          Set("tabFontColorMode","custom")
                          if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                      end,
                      onClick=function(self)
                          if (Cfg("tabFontColorMode") or "custom") ~= "custom" then
                              SetMode("custom"); return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha=function()
                          return (Cfg("tabFontColorMode") or "custom") == "custom" and 1 or .3
                      end },
                    { tooltip="Accent Color", hasAlpha=false,
                      getValue=function() return EllesmereUI.GetAccentColor() end,
                      setValue=function() end,
                      onClick=function() SetMode("accent") end,
                      refreshAlpha=function()
                          return (Cfg("tabFontColorMode") or "custom") == "accent" and 1 or .3
                      end },
                    { tooltip="Class Color", hasAlpha=false,
                      getValue=function()
                          local _,class=UnitClass("player")
                          local c=class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                          return c and c.r or 1,c and c.g or 1,c and c.b or 1
                      end,
                      setValue=function() end,
                      onClick=function() SetMode("class") end,
                      refreshAlpha=function()
                          return (Cfg("tabFontColorMode") or "custom") == "class" and 1 or .3
                      end },
                }
            end
            _, h = W:DualRow(parent, y,
                { type="multiSwatch", text="Tab Font Color", swatches=FontColorSwatch(false) },
                { type="multiSwatch", text="Tab Font Color Active", swatches=FontColorSwatch(true) })
            y = y - h

            if not STOCK then
            _, h = W:SectionHeader(parent, "APPEARANCE", y); y = y - h
            -- The inactive background is a single custom color picker. The
            -- active background uses the common Custom, Accent, Class order;
            -- both reuse the existing color tables without new defaults.
            local TAB_BG_FALLBACK = {
                [false] = { r=.03, g=.045, b=.05, a=.44 },
                [true]  = { r=.03, g=.045, b=.05, a=.65 },
            }
            local function InactiveTabBgSwatches()
                local fallback = TAB_BG_FALLBACK[false]
                return {
                    { tooltip="Custom Color", hasAlpha=false,
                      getValue=function()
                          local c=Cfg("tabBackgroundColor") or fallback
                          return c.r,c.g,c.b,c.a == nil and fallback.a or c.a
                      end,
                      setValue=function(r,g,b)
                          local c=Cfg("tabBackgroundColor") or fallback
                          local a=c.a == nil and fallback.a or c.a
                          Set("tabBackgroundColor",{r=r,g=g,b=b,a=a})
                          if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                      end },
                }
            end
            local function ActiveTabBgSwatches()
                local key = "tabBackgroundColorActive"
                local modeKey = "tabBackgroundColorActiveMode"
                local fallback = TAB_BG_FALLBACK[true]
                local function SetMode(mode)
                    Set(modeKey, mode)
                    if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                    EllesmereUI:RefreshPage()
                end
                return {
                    { tooltip="Custom Color", hasAlpha=false,
                      getValue=function()
                          local c=Cfg(key) or fallback
                          return c.r,c.g,c.b,c.a == nil and fallback.a or c.a
                      end,
                      setValue=function(r,g,b)
                          local c=Cfg(key) or fallback
                          local a=c.a == nil and fallback.a or c.a
                          Set(key,{r=r,g=g,b=b,a=a}); Set(modeKey,"custom")
                          if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                      end,
                      onClick=function(self)
                          if (Cfg(modeKey) or "custom") ~= "custom" then
                              SetMode("custom"); return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha=function()
                          return (Cfg(modeKey) or "custom") == "custom" and 1 or .3
                      end },
                    { tooltip="Accent Color", hasAlpha=false,
                      getValue=function() return EllesmereUI.GetAccentColor() end,
                      setValue=function() end,
                      onClick=function() SetMode("accent") end,
                      refreshAlpha=function()
                          return (Cfg(modeKey) or "custom") == "accent" and 1 or .3
                      end },
                    { tooltip="Class Color", hasAlpha=false,
                      getValue=function()
                          local _,class=UnitClass("player")
                          local c=class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                          return c and c.r or 1,c and c.g or 1,c and c.b or 1
                      end,
                      setValue=function() end,
                      onClick=function() SetMode("class") end,
                      refreshAlpha=function()
                          return (Cfg(modeKey) or "custom") == "class" and 1 or .3
                      end },
                }
            end
            local tabBgRow
            tabBgRow, h = W:DualRow(parent, y,
                { type="multiSwatch", text="Tab Background Color",
                  swatches=InactiveTabBgSwatches() },
                { type="multiSwatch", text="Tab Background Color Active",
                  swatches=ActiveTabBgSwatches() })
            local function AttachTabBgOpacityCog(rgn, active)
                local key = active and "tabBackgroundColorActive" or "tabBackgroundColor"
                local fallback = TAB_BG_FALLBACK[active]
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title=active and "Active Tab Background" or "Tab Background",
                    captureRegion=rgn,
                    rows={
                        { type="slider", label="Opacity", min=0, max=100, step=1,
                          get=function()
                              local c=Cfg(key) or fallback
                              local a=c.a == nil and fallback.a or c.a
                              return math.floor(a*100+0.5)
                          end,
                          set=function(v)
                              local c=Cfg(key) or fallback
                              Set(key,{r=c.r,g=c.g,b=c.b,a=v/100})
                              if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                          end },
                    },
                })
                EllesmereUI.MakeCogBtn(rgn, cogShow)
            end
            if not EllesmereUI._prebuilding then
            AttachTabBgOpacityCog(tabBgRow._leftRegion, false)
            AttachTabBgOpacityCog(tabBgRow._rightRegion, true)
            end
            y = y - h

            local function UnderlineMode()
                local mode = Cfg("activeUnderlineColorMode") or "accent"
                -- Legacy "border" profiles render and display as Custom,
                -- without rewriting the saved profile during initialization.
                return mode == "border" and "custom" or mode
            end
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
                          if UnderlineMode() ~= "custom" then
                              Set("activeUnderlineColorMode","custom")
                              if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                              EllesmereUI:RefreshPage(); return
                          end
                          if self._eabOrigClick then self._eabOrigClick(self) end
                      end,
                      refreshAlpha=function() return UnderlineMode() == "custom" and 1 or .3 end },
                    { tooltip="Accent Color", hasAlpha=false,
                      getValue=function() return EllesmereUI.GetAccentColor() end,
                      setValue=function() end,
                      onClick=function()
                          Set("activeUnderlineColorMode","accent")
                          if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                          EllesmereUI:RefreshPage()
                      end,
                      refreshAlpha=function() return UnderlineMode() == "accent" and 1 or .3 end },
                    { tooltip="Class Color", hasAlpha=false,
                      getValue=function()
                          local _,cl=UnitClass("player")
                          local c=cl and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cl]
                          return c and c.r or 1,c and c.g or 1,c and c.b or 1
                      end,
                      setValue=function() end,
                      onClick=function()
                          Set("activeUnderlineColorMode","class")
                          if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                          EllesmereUI:RefreshPage()
                      end,
                      refreshAlpha=function() return UnderlineMode() == "class" and 1 or .3 end },
                }
            end

            -- Texture belongs to the tab appearance controls, alongside the
            -- combined underline toggle and its inline color choices.
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
                    background = function(key) return texLookup[key] end,
                }
            end
            local underlineRow
            underlineRow, h = W:DualRow(parent, y,
                { type="toggle", text="Active Underline",
                  getValue=function() return Cfg("activeUnderline") ~= false end,
                  setValue=function(v)
                      Set("activeUnderline",v)
                      if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                  end },
                { type="dropdown", text="Tab Texture",
                  tooltip="Texture drawn over the tab background colors.",
                  values=btValues, order=btOrder,
                  getValue=function() return Cfg("tabBackgroundTexture") or "none" end,
                  setValue=function(v)
                      Set("tabBackgroundTexture", v)
                      if ECHAT.ApplyTabAppearance then ECHAT.ApplyTabAppearance() end
                  end })
            if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineSwatches(
                underlineRow._leftRegion, UnderlineSwatches())
            end
            y = y - h

            -- (No tab idle-fade section: the per-tab fade layer was removed
            -- 2026-07-20 -- Blizzard's own tab alpha machinery always won and
            -- the setting visibly did nothing. Tabs fade with the chat panel
            -- via the dock; see the tab-alpha note in EllesmereUIChat.lua.)

            _, h = W:SectionHeader(parent, "BORDER", y); y = y - h
            _, h = W:DualRow(parent, y,
                { type="toggle", text="Sync Border with Chat Panel",
                  tooltip="For tabs outside the chat panel, uses the chat panel's border style and color instead of separate tab border settings.",
                  disabled=function() return Cfg("extendBgBehindTabs") == true end,
                  disabledTooltip="Tabs Inside Chat Panel",
                  requireState="disabled",
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
            local borderRow
            borderRow, h = W:DualRow(parent, y,
                { type="dropdown", text="Border Style",
                  disabled=tabBordersDisabled, disabledTooltip=TabBorderDisabledTip, requireState="disabled",
                  values=texValues, order=texOrder,
                  getValue=function() return Cfg("tabBorderTexture") or "solid" end,
                  setValue=function(v)
                      Set("tabBorderTexture", v)
                      Set("tabBorderOffsetX", nil); Set("tabBorderOffsetY", nil)
                      Set("tabBorderShiftX", nil); Set("tabBorderShiftY", nil)
                      -- A style pick lands on the style's default step, so an exact
                      -- pixel size paired with the old step is cleared (false, not
                      -- nil: the clear must travel through mirror sync).
                      if Cfg("tabBorderThicknessPx") then Set("tabBorderThicknessPx", false) end
                      local def = EllesmereUI.GetBorderDefaultSize("chat", v)
                          or EllesmereUI.GetBorderTextureDefaultThickness(v)
                      -- Unregistered SharedMedia borders default to the NUMBER 1; this key stores labels.
                      if type(def) == "number" then def = EllesmereUI.BORDER_LABEL_OF_STEP[def] or "thin" end
                      if def then Set("tabBorderThickness", def) end
                      if ECHAT.ApplyTabBorders then ECHAT.ApplyTabBorders() end
                      -- Rebuild: the offset row below exists only for a textured style.
                      EllesmereUI:RefreshPage(true)
                  end },
                EllesmereUI.BorderPxSliderCfg{ text="Border Size",
                  disabled=tabBordersDisabled, disabledTooltip=TabBorderDisabledTip, requireState="disabled",
                  -- The step a tab renders with from its own keys: its label as a step, anything unknown = thin.
                  getStep=function() return EllesmereUI.BORDER_STEP_OF_LABEL[Cfg("tabBorderThickness") or "none"] or 1 end,
                  setStep=function(step) Set("tabBorderThickness", EllesmereUI.BORDER_LABEL_OF_STEP[step]) end,
                  getTex=function() return Cfg("tabBorderTexture") or "solid" end,
                  getPx=function() return Cfg("tabBorderThicknessPx") end,
                  setPx=function(v) Set("tabBorderThicknessPx", v) end,
                  apply=function()
                      if ECHAT.ApplyTabBorders then ECHAT.ApplyTabBorders() end
                  end })
            y = y - h

            -- Width Offset | Height Offset: a textured tab style's outward offsets in
            -- their own row (Solid has none). Same registry row a tab renders with
            -- from its own keys: "chat" + the thickness label as sizeKey. Disabled
            -- exactly like the Border Size slot.
            do
                local tTex = Cfg("tabBorderTexture")
                if tTex and tTex ~= "" and tTex ~= "solid" then
                    local ocfgL, ocfgR = EllesmereUI.BorderOffsetRowCfgs{
                        addonKey = "chat",
                        disabled=tabBordersDisabled, disabledTooltip=TabBorderDisabledTip, requireState="disabled",
                        getTex=function() return Cfg("tabBorderTexture") or "solid" end,
                        getStep=function() return EllesmereUI.BORDER_STEP_OF_LABEL[Cfg("tabBorderThickness") or "none"] or 1 end,
                        getSizeKey=function() return Cfg("tabBorderThickness") or "none" end,
                        getPx=function() return Cfg("tabBorderThicknessPx") end,
                        getX=function() return Cfg("tabBorderOffsetX") end,
                        setX=function(v) Set("tabBorderOffsetX", v) end,
                        getY=function() return Cfg("tabBorderOffsetY") end,
                        setY=function(v) Set("tabBorderOffsetY", v) end,
                        apply=function()
                            if ECHAT.ApplyTabBorders then ECHAT.ApplyTabBorders() end
                        end }
                    _, h = W:DualRow(parent, y, ocfgL, ocfgR)
                    y = y - h
                end
            end

            do
                local rgn = borderRow._leftRegion
                local _, cogShow = EllesmereUI.BuildCogPopup({
                    title="Tab Border Options", captureRegion=rgn,
                    rows={
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
                EllesmereUI.MakeCogBtn(rgn, cogShow, rgn._control, EllesmereUI.DIRECTIONS_ICON, tabBordersDisabled, TabBorderDisabledTip)
            end

            if not EllesmereUI._prebuilding then
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

            -- Row: Active Tab Border (+ inline color swatch)
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
                { type="label", text="" })
            if not EllesmereUI._prebuilding then
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
            end -- not STOCK (APPEARANCE, BORDER)
        end -- isTabs

        if isChat then
        -- -- INPUT FIELD -------------------------------------------------------
        _, h = W:SectionHeader(parent, "INPUT FIELD", y); y = y - h

        -- Stock styles keep Blizzard's own input box, its height and place.
        if not STOCK then
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Input on Top",
              getValue=function() return Cfg("inputOnTop") or false end,
              setValue=function(v)
                  Set("inputOnTop", v)
                  if ECHAT.ApplyInputPosition then ECHAT.ApplyInputPosition() end
              end },
            { type="slider", text="Edit Box Height", min=10, max=60, step=1,
              getValue=function() return Cfg("editBoxHeight") or 23 end,
              setValue=function(v)
                  Set("editBoxHeight", v)
                  if ECHAT.ApplyInputPosition then ECHAT.ApplyInputPosition() end
              end })
        y = y - h
        end -- not STOCK

        do
            local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
            fontValues.__chat = "Chat Font"
            table.insert(fontOrder, 1, "__chat")
            _, h = W:DualRow(parent, y,
                { type="dropdown", text="Edit Box Font",
                  values=fontValues, order=fontOrder,
                  getValue=function() return Cfg("editBoxFont") or "__chat" end,
                  setValue=function(v)
                      Set("editBoxFont", v)
                      if ECHAT.ApplyFonts then ECHAT.ApplyFonts() end
                  end },
                { type="slider", text="Edit Box Font Size", min=8, max=24, step=1,
                  getValue=function()
                      if Cfg("editBoxFontSize") then return Cfg("editBoxFontSize") end
                      local size
                      if FCF_GetChatWindowInfo then size = select(2, FCF_GetChatWindowInfo(1)) end
                      return size or 12
                  end,
                  setValue=function(v)
                      Set("editBoxFontSize", v)
                      if ECHAT.ApplyFonts then ECHAT.ApplyFonts() end
                  end })
            y = y - h
        end

        -- -- EXTRAS ------------------------------------------------------------
        _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

        -- Row 1: Remember Last Chat Lines (+ cog: Max Lines) | Hide Tooltip on Hover
        local histRow
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
        if not EllesmereUI._prebuilding then
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
            EllesmereUI.MakeCogBtn(lrgn, cogShow)
        end
        y = y - h

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

        -- Row 2: Hide Borders (+ inline inner-border swatches) | Whisper Sound
        -- Stock styles draw none of these borders (Blizzard's frame border
        -- is the border), so the toggle and its swatches are blocked there.
        local hideBordersCfg = { type="toggle", text="Hide Borders",
              getValue=function() return Cfg("hideBorders") or false end,
              setValue=function(v)
                  Set("hideBorders", v)
                  if ECHAT.ApplyBorders then ECHAT.ApplyBorders() end
                  EllesmereUI:RefreshPage()
              end }
        if BS then BS.Gate("chat", hideBordersCfg) end
        local extrasBorderRow
        extrasBorderRow, h = W:DualRow(parent, y,
            hideBordersCfg,
            { type="dropdown", text="Whisper Sound",
              values=whisperSoundValues, order=whisperSoundOrder,
              getValue=function() return Cfg("whisperSoundKey") or "none" end,
              setValue=function(v) Set("whisperSoundKey", v) end })
        if not EllesmereUI._prebuilding then
            local rgn = extrasBorderRow._leftRegion
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
                local off = Cfg("hideBorders") or STOCK
                local mode = Cfg("innerBorderColorMode") or "custom"
                swatch:SetAlpha(off and 0.3 or (mode == "custom" and 1 or 0.3))
                accentSw:SetAlpha(off and 0.3 or (mode == "accent" and 1 or 0.3))
            end
            EllesmereUI.RegisterWidgetRefresh(RefreshInner)
            RefreshInner()
            if BS then
                BS.BlockInline("chat", swatch)
                BS.BlockInline("chat", accentSw)
            end
        end
        y = y - h

        -- Row 3: Timestamp All Messages | Timestamps
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
                { type="toggle", text="Timestamp All Messages",
                  tooltip="Adds timestamps to system messages, loot, achievements, and addon messages, not just player chat.",
                  disabled=function() return (Cfg("timestampFormat") or "%I:%M ") == "none" end,
                  disabledTooltip="Set a Timestamps format first",
                  getValue=function() return Cfg("timestampAll") == true end,
                  setValue=function(v)
                      Set("timestampAll", v)
                      if ECHAT.ApplyTimestampCVar then ECHAT.ApplyTimestampCVar() end
                      if ECHAT.EngineQueueRebuildAll then ECHAT.EngineQueueRebuildAll() end
                  end },
                { type="dropdown", text="Timestamps",
                  values=tsValues, order=tsOrder,
                  getValue=function() return Cfg("timestampFormat") or "%I:%M " end,
                  setValue=function(v)
                      Set("timestampFormat", v)
                      if ECHAT.ApplyTimestampCVar then ECHAT.ApplyTimestampCVar() end
                      EllesmereUI:RefreshPage()
                  end })
        end
        y = y - h

        -- Row 4: Shortened Channel Names (+ Use Letters cog) | Class Colored Names
        local abbrevRow
        abbrevRow, h = W:DualRow(parent, y,
            { type="toggle", text="Shortened Channel Names",
              tooltip="Abbreviates channel prefixes, like [Party] to [P] and [Guild] to [G]; world channels show their number.",
              getValue=function() return Cfg("abbreviateChannels") == true end,
              setValue=function(v)
                  Set("abbreviateChannels", v)
                  if ECHAT.EngineSetChannelAbbrev then ECHAT.EngineSetChannelAbbrev(v) end
                  if ECHAT.EngineQueueRebuildAll then ECHAT.EngineQueueRebuildAll() end
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Class Colored Names",
              tooltip="Colors group and raid member names by their class when they appear in the text of Say, Yell, Party, and Raid messages.",
              getValue=function() return Cfg("classColorNames") == true end,
              setValue=function(v)
                  Set("classColorNames", v)
                  if ECHAT.ApplyClassColorNames then ECHAT.ApplyClassColorNames(v) end
                  if ECHAT.EngineQueueRebuildAll then ECHAT.EngineQueueRebuildAll() end
              end })
        if not EllesmereUI._prebuilding then
            -- Cog: world channels as letters (the old Ge / T / LD / WD / LFG)
            -- instead of their numbers. Dimmed and inert while the toggle is off.
            local lrgn = abbrevRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Shortened Channel Names",
                rows = {
                    { type="toggle", label="Use Letters",
                      tooltip="Shows General, Trade, Local Defense, World Defense and LFG as letters instead of their channel numbers.",
                      get=function() return Cfg("abbreviateChannelLetters") == true end,
                      set=function(v)
                          Set("abbreviateChannelLetters", v)
                          if ECHAT.EngineSetChannelAbbrevLetters then ECHAT.EngineSetChannelAbbrevLetters(v) end
                          if ECHAT.EngineQueueRebuildAll then ECHAT.EngineQueueRebuildAll() end
                      end },
                },
            })
            EllesmereUI.MakeCogBtn(lrgn, cogShow, nil, nil, function() return Cfg("abbreviateChannels") ~= true end)
        end
        y = y - h

        end -- isChat

        if isBubbles then

        local function BBDB() return ECHAT.BubblesDB and ECHAT.BubblesDB() end
        -- Same defaults table the renderer reads, so a widget can never offer a value the
        -- bubble would not actually draw. Falling back per key also keeps a slider off nil
        -- if a profile predates the setting and the merge has not run for it yet.
        local function CBVal(key)
            local db = BBDB()
            local v = db and db[key]
            if v ~= nil then return v end
            local d = ECHAT.BubbleDefaults and ECHAT.BubbleDefaults()
            return d and d[key]
        end
        -- Structural write: can change whether we draw at all, or which of Blizzard's
        -- CVars we hold down, so it runs the renderer's full pass.
        local function CBSet(key, v)
            local db = BBDB()
            if not db then return end
            db[key] = v
            if ns.ChatBubbles then ns.ChatBubbles.Refresh() end
        end
        -- Appearance write: nothing here can move a channel or one of Blizzard's CVars, so
        -- it only re-styles what is already on screen. Worth the split because a slider
        -- fires this per STEP while it is dragged, and the full pass re-diffs every event
        -- registration and round-trips Blizzard's three switches every time.
        local function CBSetStyle(key, v)
            local db = BBDB()
            if not db then return end
            db[key] = v
            local cb = ns.ChatBubbles
            if not cb then return end
            if cb.RefreshStyle then cb.RefreshStyle() else cb.Refresh() end
        end
        local function CBColor(key)
            local c = CBVal(key)
            if not c then return 1, 1, 1, 1 end
            return c.r, c.g, c.b, c.a or 1
        end
        local function Off() return CBVal("enabled") ~= true end
        local GATE = "Enable Chat Bubbles Customization"
        -- The toggle's own label reads as an instruction; DisabledTooltip wraps whatever it
        -- is handed in "This option requires %1$s to be enabled", which needs a plain noun.
        local GATE_REQ = "Chat Bubbles"

        -- Red warning banner: NOT a section header for what follows -- our own bubbles
        -- never show inside instances, unconditionally, and that has to be visible before
        -- the player reads any option below it, not styled as their category label.
        -- Skipped while the search index prebuilds the page off screen: the banner carries
        -- no setting to index and parent:GetWidth() is not meaningful there. The height
        -- still comes off y in both passes, so everything below lands identically.
        if not EllesmereUI._prebuilding then
            local warnFrame = CreateFrame("Frame", nil, parent)
            PP.Size(warnFrame, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, 30)
            PP.Point(warnFrame, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
            local warnFS = EllesmereUI.MakeFont(warnFrame, 14, "", 1, 0.25, 0.25, 1)
            warnFS:SetPoint("LEFT", warnFrame, "LEFT", 0, 0)
            warnFS:SetText(EllesmereUI.L("Only works outside of Instances"))
        end
        y = y - 30

        _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

        local channelsRow
        channelsRow, h = W:DualRow(parent, y,
            { type="toggle", text=GATE,
              tooltip="Restyle Blizzard's chat bubbles for the channels you pick beside this.\n\nEllesmereUI keeps Blizzard's bubbles switched on and draws over them, so every bubble stays where the game put it, including the one over your own head. Nameplates are not involved and do not need to be visible.\n\nChannels you leave off keep Blizzard's own look.",
              getValue=function() return CBVal("enabled") == true end,
              setValue=function(v)
                if not v then
                    CBSet("enabled", false)
                    EllesmereUI:RefreshPage()
                    return
                end
                local message = "EllesmereUI restyles Blizzard's chat bubbles and turns on the switches it needs. Party and Raid keep your current setting, and everything is put back when you turn this off."
                EllesmereUI:ShowConfirmPopup({
                    title = GATE,
                    message = message,
                    confirmText = "Enable",
                    cancelText = "Cancel",
                    onConfirm = function()
                        CBSet("enabled", true)
                        EllesmereUI:RefreshPage()
                    end,
                    onCancel = function() EllesmereUI:RefreshPage() end,
                })
              end },
            { type="dropdown", text="Channels",
              rawTooltip = true,
              tooltip="Choose which channels get a bubble.\n\nSay, Yell, NPCs and Emotes share one Blizzard switch. It is turned on while at least one of the four is ticked, and put back the way you had it once you clear the last one. Party and Raid have switches of their own and start out matching what you already had, so no group bubbles turn up in a chat that had none.\n\nGuild is not offered: Blizzard draws no bubble for guild chat, and there is nothing for us to restyle.",
              disabled = Off, disabledTooltip = GATE_REQ,
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end });  y = y - h

        if not EllesmereUI._prebuilding then
            local rgn = channelsRow._rightRegion
            if rgn._control then rgn._control:Hide() end
            local channelItems = {
                { key="say",   label="Say" },
                { key="yell",  label="Yell" },
                { key="party", label="Party",
                  tooltip="Uses Blizzard's own party switch, independent of the other channels. Instance chat, the one an LFG or LFR group talks in, is covered here too." },
                { key="raid",  label="Raid",
                  tooltip="Uses Blizzard's own raid switch, which it ships off. Ticking this turns that switch on, and it is put back the way you had it when you untick it or switch the feature off." },
                { key="npc",   label="NPCs" },
                { key="emote", label="Emotes" },
            }
            local chDD, chDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 240, rgn:GetFrameLevel() + 2,
                channelItems,
                function(k) return CBVal(k) == true end,
                function(k, v) CBSet(k, v) end)
            PP.Point(chDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = chDD
            rgn._lastInline = nil

            local chBlock = CreateFrame("Frame", nil, chDD)
            chBlock:SetAllPoints()
            chBlock:SetFrameLevel(chDD:GetFrameLevel() + 20)
            chBlock:EnableMouse(true)
            chBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(chDD, EllesmereUI.DisabledTooltip(GATE_REQ))
            end)
            chBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function chUpdateDisabled()
                if Off() then chDD:SetAlpha(0.4); chBlock:Show()
                else chDD:SetAlpha(1); chBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(chDDRefresh)
            EllesmereUI.RegisterWidgetRefresh(chUpdateDisabled)
            chUpdateDisabled()
        end

        -- Structural, not appearance: it decides which of Blizzard's switches we hold and at
        -- what value, so it takes the full pass. Half-empty right slot is allowed here because
        -- this is the last row of its section.
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Hide Chat Bubbles in Instances",
              tooltip="Switch Blizzard's chat bubbles off for as long as you are inside a dungeon, raid, scenario or battleground, and back on the way out.\n\nEllesmereUI never restyles bubbles inside an instance: the game's bubble frames are off limits to addons there. This decides whether Blizzard's own are visible at all.",
              getValue=function() return CBVal("hideInInstances") == true end,
              setValue=function(v) CBSet("hideInInstances", v) end,
              disabled = Off, disabledTooltip = GATE_REQ },
            { type="label", text="" });  y = y - h

        _, h = W:SectionHeader(parent, "APPEARANCE", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="slider", text="Padding", min=2, max=24, step=1,
              tooltip="Space between the text and the edge of the bubble.",
              getValue=function() return CBVal("padding") end,
              setValue=function(v) CBSetStyle("padding", v) end,
              disabled = Off, disabledTooltip = GATE_REQ },
            { type="slider", text="Maximum Width", min=120, max=500, step=10,
              getValue=function() return CBVal("maxWidth") end,
              setValue=function(v) CBSetStyle("maxWidth", v) end,
              disabled = Off, disabledTooltip = GATE_REQ });  y = y - h

        local fontBorderRow
        fontBorderRow, h = W:DualRow(parent, y,
            { type="slider", text="Font", min=8, max=24, step=1,
              tooltip="Font size.",
              getValue=function() return CBVal("fontSize") end,
              setValue=function(v) CBSetStyle("fontSize", v) end,
              disabled = Off, disabledTooltip = GATE_REQ },
            { type="slider", text="Border", min=0, max=4, step=1,
              tooltip="Border size. Set to 0 for no border.",
              getValue=function() return CBVal("borderSize") end,
              setValue=function(v) CBSetStyle("borderSize", v) end,
              disabled = Off, disabledTooltip = GATE_REQ });  y = y - h

        -- BuildInlineSwatches, not a hand-rolled BuildColorSwatch: it is the house form for
        -- a swatch riding on a slider half (see the Chat page's own font row above). It
        -- anchors through PP.Point, registers the swatch's refresh so a profile switch
        -- repaints it, and builds the greyed-out block plus tooltip from opts.disabled.
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineSwatches(fontBorderRow._leftRegion, {
                { getValue = function() local r, g, b = CBColor("textColor"); return r, g, b, 1 end,
                  setValue = function(r, g, b) CBSetStyle("textColor", { r=r, g=g, b=b }) end,
                  -- Two reasons this swatch can be dead, so the tip is resolved per reason:
                  -- the wrapper sentence fits the gate, but not "something else owns this".
                  disabled = function() return Off() or CBVal("followBlizzardColor") == true end,
                  disabledTooltip = function()
                      if Off() then return GATE_REQ end
                      return "Blizzard's own color is in use. Turn Follow Blizzard Default Color off in the cog to pick your own."
                  end,
                  rawTooltip = function() return not Off() end },
            }, { disabled = Off, disabledTooltip = GATE_REQ })

            -- Built AFTER the swatch on purpose: BuildInlineSwatches chains _lastInline, so a
            -- cog made afterwards lands to its left rather than on top of it.
            local _, colorCogShow = EllesmereUI.BuildCogPopup({
                title = "Text Color",
                rows = {
                    { type = "toggle", label = "Follow Blizzard Default Color",
                      get = function() return CBVal("followBlizzardColor") == true end,
                      set = function(v)
                          CBSetStyle("followBlizzardColor", v)
                          EllesmereUI:RefreshPage()
                      end },
                },
            })
            local colorRgn = fontBorderRow._leftRegion
            EllesmereUI.MakeCogBtn(colorRgn, colorCogShow, nil, nil, Off)

            EllesmereUI.BuildInlineSwatches(fontBorderRow._rightRegion, {
                { getValue = function() return CBColor("borderColor") end,
                  setValue = function(r, g, b, a) CBSetStyle("borderColor", { r=r, g=g, b=b, a=a }) end,
                  hasAlpha = true },
            }, { disabled = Off, disabledTooltip = GATE_REQ })
        end

        local bgRow
        bgRow, h = W:DualRow(parent, y,
            { type="toggle", text="Background",
              tooltip="Draw a filled background behind the text and border. Off draws the text and border on their own.",
              getValue=function() return CBVal("background") ~= false end,
              setValue=function(v) CBSetStyle("background", v); EllesmereUI:RefreshPage() end,
              disabled = Off, disabledTooltip = GATE_REQ },
            { type="slider", text="Vertical Offset", min=-80, max=80, step=2,
              tooltip="Nudge the bubble up or down from where the game put it. Zero sits exactly on Blizzard's own position, which is already over the speaker's head.",
              getValue=function() return CBVal("offsetY") end,
              setValue=function(v) CBSetStyle("offsetY", v) end,
              disabled = Off, disabledTooltip = GATE_REQ });  y = y - h

        -- Colour and opacity are one swatch but two stored keys, so the write goes straight
        -- to the DB rather than through CBSetStyle. rawTooltip keeps the sentence as written
        -- instead of running it through DisabledTooltip's "This option requires" wrapper:
        -- there is nothing to colour while the background is off, or the feature is.
        if not EllesmereUI._prebuilding then
            EllesmereUI.BuildInlineSwatches(bgRow._leftRegion, {
                { getValue = function()
                      local r, g, b = CBColor("bgColor")
                      return r, g, b, CBVal("bgAlpha")
                  end,
                  setValue = function(r, g, b, a)
                      local db = BBDB(); if not db then return end
                      db.bgColor = { r=r, g=g, b=b }
                      db.bgAlpha = a
                      local cb = ns.ChatBubbles
                      if not cb then return end
                      if cb.RefreshStyle then cb.RefreshStyle() else cb.Refresh() end
                  end,
                  hasAlpha = true,
                  disabled = function() return Off() or CBVal("background") == false end,
                  disabledTooltip = "Turn Background on to set a color.",
                  rawTooltip = true },
            })
        end

        end -- isBubbles

        return math.abs(y)
    end

    _G._EBS_BuildChatPage = BuildPage

    -- The bubble page is offered only while the module can both STORE and DRAW its settings.
    -- The store alone is not enough: a .toc that lost the renderer's load line (an addon
    -- update replacing the folder is all it takes) leaves every setting readable and nothing
    -- listening to them, so the page would look healthy and do absolutely nothing.
    -- Blizzard Style shows Blizzard's own chat tabs, which take none of the
    -- Tabs page's settings, so the page is not offered there.
    local blizzTabsStyle = EllesmereUI.BlizzStyle and EllesmereUI.BlizzStyle.Active("chat") == "blizzard"
    local chatPages = blizzTabsStyle and { "Chat", "Sidebar" } or { "Chat", "Tabs", "Sidebar" }
    if ECHAT.BubblesDB and ECHAT.BubbleDefaults and ns.ChatBubbles then
        chatPages[#chatPages + 1] = "Chat Bubbles"
    end

    EllesmereUI:RegisterModule("EllesmereUIChat", {
        title       = "Chat",
        description = "Chat frame reskin, clickable URLs, copy chat, sidebar icons.",
        pages       = chatPages,
        buildPage   = function(pageName, p, yOffset) return BuildPage(pageName, p, yOffset) end,
        searchTerms = "chat tabs border spacing background sidebar friends voice url copy whisper channel abbreviate shortened class color names timestamps timestamp all messages font size bubbles bubble speech balloon nameplate",
        onReset = function()
            local d = _G._ECHAT_DB
            if d and d.ResetProfile then d:ResetProfile() end
            RefreshAll()
            EllesmereUI:InvalidatePageCache()
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
