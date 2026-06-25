-------------------------------------------------------------------------------
--  EUI_BlizzardSkin_Options.lua
-------------------------------------------------------------------------------
local _, ns = ...
local PAGE_CHARSHEET     = "Character Sheet"
local PAGE_TOOLTIPS      = "Tooltips, Menus & Popups"
local PAGE_DRAGONRIDING  = "Dragon Riding"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local function BuildTooltipsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        _, h = W:Spacer(parent, y, 20);  y = y - h

        _, h = W:SectionHeader(parent, "BLIZZARD UI ELEMENTS", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Reskin Blizzard Elements",
              tooltip="Reskins Blizzard tooltips, right-click context menus, and popups with a dark, minimal style matching the EUI aesthetic. Requires reload to apply.",
              getValue=function()
                  return not EllesmereUIDB or EllesmereUIDB.customTooltips ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.customTooltips = v
                  if EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Reskin setting requires a UI reload to fully apply.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end
              end },
            { type="toggle", text="Accent Colored Elements",
              tooltip="Recolors headers, arrows, and spell titles in Blizzard tooltips and context menus to match your UI Accent Color.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.accentReskinElements or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.accentReskinElements = v
              end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Player Titles in Tooltips",
              tooltip="Shows a player's RP title on their unit tooltip.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.tooltipPlayerTitles or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.tooltipPlayerTitles = v
              end },
            { type="slider", text="Font Size Scale",
              tooltip="Scales the font size of reskinned Blizzard tooltips, menus, and popups.",
              min=0.7, max=1.5, step=0.05, format="%.0f%%",
              displayMul=100,
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.tooltipFontScale or 1.0
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.tooltipFontScale = v
              end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Detailed Tooltips",
              tooltip="Shows full spell and ability descriptions in tooltips instead of just the name. Only enforced on login after you toggle this setting.",
              getValue=function()
                  return GetCVar("UberTooltips") == "1"
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.uberTooltipsManual = true
                  EllesmereUIDB.uberTooltips = v
                  SetCVar("UberTooltips", v and "1" or "0")
              end },
            { type="toggle", text="Show M+ Score",
              tooltip="Displays a player's Mythic+ score on their unit tooltip, colored by rarity.",
              getValue=function()
                  return not EllesmereUIDB or EllesmereUIDB.tooltipMythicScore ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.tooltipMythicScore = v
              end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Item Level",
              tooltip="Displays a player's equipped item level on their unit tooltip.",
              getValue=function()
                  return not EllesmereUIDB or EllesmereUIDB.tooltipItemLevel ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.tooltipItemLevel = v
              end },
            -- Front-end duplicate of the toggle in Global Settings > Developer;
            -- same EllesmereUIDB.showSpellID key read by the tooltip logic in
            -- EllesmereUI.lua (no separate backend).
            { type="toggle", text="Show Spell ID on Tooltip",
              tooltip="Appends the spell or item ID to tooltips. The same setting as Global Settings > Developer.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.showSpellID or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showSpellID = v
              end }
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        _, h = W:SectionHeader(parent, "BLIZZARD WINDOW RESKINS", y);  y = y - h

        local _eqolLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EnhanceQoL")
        local queueRow
        queueRow, h = W:DualRow(parent, y,
            { type="toggle", text="Reskin Queue Popup",
              tooltip="Reskins the LFG/dungeon queue accept popup with the EUI dark style and adds an accept countdown timer bar.",
              getValue=function()
                  if not EllesmereUIDB then return true end
                  -- One-time seed from master toggle (written by IsQueueReskinOn at runtime)
                  if EllesmereUIDB.reskinQueuePopup == nil then
                      EllesmereUIDB.reskinQueuePopup = (EllesmereUIDB.customTooltips ~= false)
                  end
                  return EllesmereUIDB.reskinQueuePopup
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.reskinQueuePopup = v
                  if not v and EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Disabling queue popup reskin requires a UI reload to restore Blizzard's default style.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end
              end },
            { type="toggle", text="Show Queue Timer",
              tooltip="Shows a countdown bar below the queue accept popup indicating how long you have to accept.",
              getValue=function()
                  return not EllesmereUIDB or EllesmereUIDB.showQueueTimer ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showQueueTimer = v
              end }
        );  y = y - h

        -- Red "!" warning left of the toggle when EnhanceQoL is loaded
        if _eqolLoaded and queueRow and queueRow._leftRegion then
            local rgn = queueRow._leftRegion
            local toggle = rgn._control
            if toggle then
                local fontPath = (EllesmereUI.GetFontPath and EllesmereUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                local warnBtn = CreateFrame("Button", nil, rgn)
                warnBtn:SetSize(28, 28)
                warnBtn:SetPoint("RIGHT", toggle, "LEFT", -4, 0)
                warnBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                local warnFS = warnBtn:CreateFontString(nil, "OVERLAY")
                warnFS:SetFont(fontPath, 28, "")
                warnFS:SetTextColor(1, 0.3, 0.3, 1)
                warnFS:SetText("!")
                warnFS:SetPoint("CENTER")
                warnBtn:SetScript("OnEnter", function(self)
                    EllesmereUI.ShowWidgetTooltip(self, "Enhance QoL's Mover may conflict with this reskin. The reskin is auto-disabled when its mover is active.")
                end)
                warnBtn:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            end
        end

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Reskin Pause Menu",
              tooltip="Reskins the ESC / Game Menu with the EUI dark style, matching fonts, and accent-colored title.",
              getValue=function()
                  if not EllesmereUIDB then return true end
                  if EllesmereUIDB.reskinGameMenu == nil then
                      EllesmereUIDB.reskinGameMenu = (EllesmereUIDB.customTooltips ~= false) and (EllesmereUIDB.reskinQueuePopup ~= false)
                  end
                  return EllesmereUIDB.reskinGameMenu
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.reskinGameMenu = v
                  if EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Changing the pause menu reskin requires a UI reload.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end
              end },
            { type="toggle", text="Reskin Great Vault",
              tooltip="Reskins the Great Vault window with custom tile backgrounds, progress colors, and completion states.",
              getValue=function()
                  if not EllesmereUIDB then return false end
                  if EllesmereUIDB.reskinGreatVault == nil then
                      return EllesmereUIDB.customTooltips ~= false
                  end
                  return EllesmereUIDB.reskinGreatVault
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.reskinGreatVault = v
                  if EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Changing the Great Vault reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end
              end }
        );  y = y - h

        -- TEMP DISABLED: Group Finder reskin + QoL toggles. The feature file is
        -- also commented out of EllesmereUIBlizzardSkin.toc. Revert both by
        -- removing the --[[ and --]] markers here and uncommenting the TOC line.
        --[[
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Reskin LFG Menu",
              tooltip="Reskins the Group Finder / Premade Groups window with the EUI dark style.",
              getValue=function()
                  if not EllesmereUIDB then return false end
                  -- Seed the default ONCE on first read: enabled only if both
                  -- Reskin Blizzard Elements (customTooltips) and Reskin Queue
                  -- Popup are enabled at that moment; stored thereafter so it
                  -- stays fixed regardless of later changes to those toggles.
                  if EllesmereUIDB.reskinLFGMenu == nil then
                      EllesmereUIDB.reskinLFGMenu = (EllesmereUIDB.customTooltips ~= false) and (EllesmereUIDB.reskinQueuePopup ~= false)
                  end
                  return EllesmereUIDB.reskinLFGMenu
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.reskinLFGMenu = v
                  if EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Changing the Group Finder reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end
              end },
            { type="toggle", text="Auto-Refresh Group Search",
              tooltip="Automatically refreshes the Premade Groups list every few seconds while you are browsing, so newly posted groups appear without clicking Refresh.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.lfgAutoRefresh == true
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.lfgAutoRefresh = v
                  if EllesmereUI._GroupFinder_RefreshQoL then EllesmereUI._GroupFinder_RefreshQoL() end
              end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Remember Sign-Up Roles",
              tooltip="Remembers the Tank/Healer/DPS roles you last applied with and restores them the next time you sign up to a premade group (limited to roles your current spec can fill).",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.lfgRememberRoles == true
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.lfgRememberRoles = v
                  if EllesmereUI._GroupFinder_RefreshQoL then EllesmereUI._GroupFinder_RefreshQoL() end
              end },
            { type="label", text="" }
        );  y = y - h
        --]]

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Character Sheet options page
    ---------------------------------------------------------------------------
    local function BuildCharacterSheetPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h
        local PP = EllesmereUI.PanelPP

        parent._showRowDivider = true


        local function themedOff()
            return EllesmereUIDB and EllesmereUIDB.themedCharacterSheet == false
        end

        local function AttachDisabledOverlay(target)
            local block = CreateFrame("Frame", nil, target)
            block:SetAllPoints(target)
            block:SetFrameLevel(target:GetFrameLevel() + 10)
            block:EnableMouse(true)
            local bg = EllesmereUI.SolidTex(block, "BACKGROUND", 0, 0, 0, 0)
            bg:SetAllPoints()
            block:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(block, EllesmereUI.DisabledTooltip("Character Sheet"))
            end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function refresh()
                if themedOff() then block:Show(); target:SetAlpha(0.3)
                else block:Hide(); target:SetAlpha(1) end
            end
            EllesmereUI.RegisterWidgetRefresh(refresh); refresh()
        end

        local function AttachStatSwatch(rgn, dbColorKey, defaultColor, parentEnabledFn, cogOpts)
            local swGet = function()
                local c = EllesmereUIDB and EllesmereUIDB.statCategoryColors and EllesmereUIDB.statCategoryColors[dbColorKey]
                if c then return c.r, c.g, c.b, 1 end
                return defaultColor.r, defaultColor.g, defaultColor.b, 1
            end
            local swSet = function(r, g, b)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                if not EllesmereUIDB.statCategoryColors then EllesmereUIDB.statCategoryColors = {} end
                if not EllesmereUIDB.statCategoryUseColor then EllesmereUIDB.statCategoryUseColor = {} end
                EllesmereUIDB.statCategoryColors[dbColorKey] = { r = r, g = g, b = b }
                EllesmereUIDB.statCategoryUseColor[dbColorKey] = true
                if EllesmereUI._refreshCharacterSheetColors then EllesmereUI._refreshCharacterSheetColors() end
            end
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5, swGet, swSet, false, 20)
            PP.Point(swatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
            rgn._lastInline = swatch
            local function refresh()
                local parentEnabled = parentEnabledFn()
                if themedOff() then
                    swatch:SetAlpha(0.15); swatch:EnableMouse(false)
                else
                    swatch:SetAlpha(parentEnabled and 1 or 0.3)
                    swatch:EnableMouse(parentEnabled)
                end
                updateSwatch()
            end
            EllesmereUI.RegisterWidgetRefresh(refresh); refresh()

            if cogOpts then
                local _, cogShow = EllesmereUI.BuildCogPopup(cogOpts)
                local cogBtn = CreateFrame("Button", nil, rgn)
                cogBtn:SetSize(26, 26)
                cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
                rgn._lastInline = cogBtn
                cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
                local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
                cogTex:SetAllPoints()
                cogTex:SetTexture(EllesmereUI.COGS_ICON)
                cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
                cogBtn:SetScript("OnLeave", function(self)
                    local parentEnabled = parentEnabledFn()
                    self:SetAlpha(themedOff() and 0.15 or (parentEnabled and 0.4 or 0.15))
                end)
                cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
                local function cogRefresh()
                    local parentEnabled = parentEnabledFn()
                    if themedOff() then
                        cogBtn:SetAlpha(0.15); cogBtn:EnableMouse(false)
                    else
                        cogBtn:SetAlpha(parentEnabled and 0.4 or 0.15)
                        cogBtn:EnableMouse(parentEnabled)
                    end
                end
                EllesmereUI.RegisterWidgetRefresh(cogRefresh); cogRefresh()
            end
        end

        local function StatCategoryToggle(text, key, tooltipText)
            return { type="toggle", text=text, tooltip=tooltipText,
                     getValue=function()
                         return EllesmereUIDB and EllesmereUIDB["showStatCategory_"..key] ~= false
                     end,
                     setValue=function(v)
                         if not EllesmereUIDB then EllesmereUIDB = {} end
                         EllesmereUIDB["showStatCategory_"..key] = v
                         if EllesmereUI._updateStatCategoryVisibility then
                             EllesmereUI._updateStatCategoryVisibility()
                         end
                         local sf = CharacterFrame and EllesmereUI._GetFFD and EllesmereUI._GetFFD(CharacterFrame).scrollFrame
                         if sf then sf:SetVerticalScroll(0) end
                         EllesmereUI:RefreshPage()
                     end }
        end
        local function StatCategoryEnabled(key)
            return function()
                return EllesmereUIDB and EllesmereUIDB["showStatCategory_"..key] ~= false
            end
        end

        ---------------------------------------------------------------------------
        --  CORE OPTIONS
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "CORE OPTIONS", y);  y = y - h

        local enableRow
        enableRow, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Character Sheet",
              tooltip="Applies EllesmereUI theme styling to the character sheet window.",
              getValue=function()
                  return not EllesmereUIDB or EllesmereUIDB.themedCharacterSheet ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.themedCharacterSheet = v
                  EllesmereUIDB.themedInspectSheet = v
                  -- Individual feature toggles retain their values.
                  -- The disabled overlay handles the visual disable state.
                  if EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Character Sheet theme setting requires a UI reload to fully apply.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Show Mythic+ Rating",
              tooltip="Display your Mythic+ rating above the item level on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showMythicRating or false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showMythicRating = v
                  if EllesmereUI._updateMythicRatingDisplay then EllesmereUI._updateMythicRatingDisplay() end
              end }
        );  y = y - h

        AttachDisabledOverlay(enableRow._rightRegion)

        local ilvlRow
        ilvlRow, h = W:DualRow(parent, y,
            { type="toggle", text="Item Level",
              tooltip="Toggle visibility of item level text on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showItemLevel ~= false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showItemLevel = v
                  if EllesmereUI._refreshItemLevelVisibility then EllesmereUI._refreshItemLevelVisibility() end
              end },
            { type="toggle", text="Upgrade Track",
              tooltip="Toggle visibility of upgrade track text on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showUpgradeTrack ~= false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showUpgradeTrack = v
                  if EllesmereUI._refreshUpgradeTrackVisibility then EllesmereUI._refreshUpgradeTrackVisibility() end
              end }
        );  y = y - h
        AttachDisabledOverlay(ilvlRow)

        local enchGemRow
        enchGemRow, h = W:DualRow(parent, y,
            { type="toggle", text="Enchants",
              tooltip="Toggle visibility of enchant text on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showEnchants ~= false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showEnchants = v
                  if EllesmereUI._refreshEnchantsVisibility then EllesmereUI._refreshEnchantsVisibility() end
                  -- Refresh so the inline Enchant Settings cog updates its
                  -- disabled state in lockstep with this toggle.
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Show Gems",
              tooltip="Toggle visibility of gem icons inside equipment slots.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showGems ~= false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showGems = v
                  if EllesmereUI._refreshGemsVisibility then EllesmereUI._refreshGemsVisibility() end
              end }
        );  y = y - h
        AttachDisabledOverlay(enchGemRow)

        -- Inline cog on the Enchants toggle: "Show Enchant Names". Disabled
        -- (grayed, non-interactive) while Enchants are hidden, since the name
        -- only replaces the enchant icon when enchants are shown.
        do
            local rgn = enchGemRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Enchant Settings",
                rows = {
                    { type="toggle", label="Show Enchant Names",
                      tooltip="Show each enchant's name as text (colored to match that item's item level) instead of its icon. The name normally appears only when hovering the icon.",
                      get=function() return EllesmereUIDB and EllesmereUIDB.charSheetEnchantNames or false end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.charSheetEnchantNames = v
                          if EllesmereUI._refreshCharSheetSlotLabels then EllesmereUI._refreshCharSheetSlotLabels() end
                      end },
                    { type="slider", label="Text Size", min=6, max=20, step=1,
                      disabled=function() return not (EllesmereUIDB and EllesmereUIDB.charSheetEnchantNames) end,
                      disabledTooltip="Show Enchant Names",
                      get=function() return (EllesmereUIDB and EllesmereUIDB.charSheetEnchantSize) or 9 end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.charSheetEnchantSize = v
                          if EllesmereUI._refreshCharSheetSlotLabels then EllesmereUI._refreshCharSheetSlotLabels() end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY"); cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.COGS_ICON)
            local function enchantsOn() return EllesmereUIDB and EllesmereUIDB.showEnchants ~= false end
            cogBtn:SetScript("OnEnter", function(s) if enchantsOn() then s:SetAlpha(0.7) end end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(enchantsOn() and 0.4 or 0.15) end)
            cogBtn:SetScript("OnClick", function(s) if enchantsOn() then cogShow(s) end end)
            local function cogState()
                local on = enchantsOn()
                cogBtn:SetAlpha(on and 0.4 or 0.15)
                cogBtn:EnableMouse(on)
            end
            EllesmereUI.RegisterWidgetRefresh(cogState); cogState()
        end

        local pvpRow
        pvpRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show PvP Item Level",
              tooltip="Display your PvP item level above the Mythic+ rating on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showPvpItemLevel or false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showPvpItemLevel = v
                  if EllesmereUI._updatePvpIlvlDisplay then EllesmereUI._updatePvpIlvlDisplay() end
              end },
            { type="label", text="" }
        );  y = y - h
        AttachDisabledOverlay(pvpRow)

        _, h = W:Spacer(parent, y, 10);  y = y - h

        ---------------------------------------------------------------------------
        --  STAT DISPLAY
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "STAT DISPLAY", y);  y = y - h

        local secondaryCogOpts = {
            title = "Secondary Stats Settings",
            rows = {
                { type="toggle", label="Show Raw Rating",
                  get=function() return EllesmereUIDB and EllesmereUIDB.showSecondaryRaw or false end,
                  set=function(v)
                      if not EllesmereUIDB then EllesmereUIDB = {} end
                      EllesmereUIDB.showSecondaryRaw = v
                      if v then EllesmereUIDB.showSecondaryBoth = false end
                      if EllesmereUI._refreshStatFormats then EllesmereUI._refreshStatFormats() end
                  end },
                { type="toggle", label="Show % and Raw",
                  get=function() return EllesmereUIDB and EllesmereUIDB.showSecondaryBoth or false end,
                  set=function(v)
                      if not EllesmereUIDB then EllesmereUIDB = {} end
                      EllesmereUIDB.showSecondaryBoth = v
                      if v then EllesmereUIDB.showSecondaryRaw = false end
                      if EllesmereUI._refreshStatFormats then EllesmereUI._refreshStatFormats() end
                  end },
            },
        }
        local tertiaryCogOpts = {
            title = "Tertiary Stats Settings",
            rows = {
                { type="toggle", label="Show Raw Rating",
                  get=function() return EllesmereUIDB and EllesmereUIDB.showTertiaryRaw or false end,
                  set=function(v)
                      if not EllesmereUIDB then EllesmereUIDB = {} end
                      EllesmereUIDB.showTertiaryRaw = v
                      if v then EllesmereUIDB.showTertiaryBoth = false end
                      if EllesmereUI._refreshStatFormats then EllesmereUI._refreshStatFormats() end
                  end },
                { type="toggle", label="Show % and Raw",
                  get=function() return EllesmereUIDB and EllesmereUIDB.showTertiaryBoth or false end,
                  set=function(v)
                      if not EllesmereUIDB then EllesmereUIDB = {} end
                      EllesmereUIDB.showTertiaryBoth = v
                      if v then EllesmereUIDB.showTertiaryRaw = false end
                      if EllesmereUI._refreshStatFormats then EllesmereUI._refreshStatFormats() end
                  end },
            },
        }
        local function crestRow(label, key)
            return { type="toggle", label=label,
                     get=function()
                         return not (EllesmereUIDB and EllesmereUIDB["showCrest_"..key] == false)
                     end,
                     set=function(v)
                         if not EllesmereUIDB then EllesmereUIDB = {} end
                         EllesmereUIDB["showCrest_"..key] = v
                         if EllesmereUI._refreshStatsVisibility then EllesmereUI._refreshStatsVisibility() end
                     end }
        end
        local crestsCogOpts = {
            title = "Crests",
            rows = {
                crestRow("Show Myth",       "Myth"),
                crestRow("Show Hero",       "Hero"),
                crestRow("Show Champion",   "Champion"),
                crestRow("Show Veteran",    "Veteran"),
                crestRow("Show Adventurer", "Adventurer"),
            },
        }

        local statRow1
        statRow1, h = W:DualRow(parent, y,
            StatCategoryToggle("Show Attributes", "Attributes",
                "Toggle visibility of the Attributes stat category."),
            StatCategoryToggle("Show Secondary", "SecondaryStats",
                "Toggle visibility of the Secondary Stats category.")
        );  y = y - h
        AttachDisabledOverlay(statRow1)
        AttachStatSwatch(statRow1._leftRegion, "Attributes",
            { r = 0.047, g = 0.824, b = 0.616 }, StatCategoryEnabled("Attributes"))
        AttachStatSwatch(statRow1._rightRegion, "Secondary Stats",
            { r = 0.471, g = 0.255, b = 0.784 }, StatCategoryEnabled("SecondaryStats"),
            secondaryCogOpts)

        local statRow2
        statRow2, h = W:DualRow(parent, y,
            StatCategoryToggle("Show Tertiary", "Tertiary",
                "Toggle visibility of the Tertiary stat category (Leech, Avoidance, Speed)."),
            StatCategoryToggle("Show Attack", "Attack",
                "Toggle visibility of the Attack stat category.")
        );  y = y - h
        AttachDisabledOverlay(statRow2)
        AttachStatSwatch(statRow2._leftRegion, "Tertiary Stats",
            { r = 0.859, g = 0.325, b = 0.855 }, StatCategoryEnabled("Tertiary"),
            tertiaryCogOpts)
        AttachStatSwatch(statRow2._rightRegion, "Attack",
            { r = 1, g = 0.353, b = 0.122 }, StatCategoryEnabled("Attack"))

        local statRow3
        statRow3, h = W:DualRow(parent, y,
            StatCategoryToggle("Show Defense", "Defense",
                "Toggle visibility of the Defense stat category."),
            StatCategoryToggle("Show Crests", "Crests",
                "Toggle visibility of the Crests stat category.")
        );  y = y - h
        AttachDisabledOverlay(statRow3)
        AttachStatSwatch(statRow3._leftRegion, "Defense",
            { r = 0.247, g = 0.655, b = 1 }, StatCategoryEnabled("Defense"))
        AttachStatSwatch(statRow3._rightRegion, "Crests",
            { r = 1, g = 0.784, b = 0.341 }, StatCategoryEnabled("Crests"),
            crestsCogOpts)

        local statRow4
        statRow4, h = W:DualRow(parent, y,
            StatCategoryToggle("Show PvP", "PvP",
                "Toggle visibility of the PvP stat category (Honor Level, Honor, Conquest)."),
            { type="toggle", text="Show Diminishing Returns",
              tooltip="Add diminishing-returns detail (adjusted rating, wasted rating, and current penalty bracket) to the Secondary and Tertiary stat tooltips.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showAdjustedStats or false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showAdjustedStats = v
              end }
        );  y = y - h
        AttachDisabledOverlay(statRow4)
        AttachStatSwatch(statRow4._leftRegion, "PvP",
            { r = 0.671, g = 0.431, b = 0.349 }, StatCategoryEnabled("PvP"))

        ---------------------------------------------------------------------------
        --  INSPECT SHEET
        ---------------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "INSPECT SHEET", y);  y = y - h

        local themedInspectSheetRow
        themedInspectSheetRow, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Inspect Sheet",
              tooltip="Applies EllesmereUI theme styling to the inspect sheet window.",
              getValue=function()
                  return not EllesmereUIDB or EllesmereUIDB.themedInspectSheet ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.themedInspectSheet = v
                  if EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Inspect Sheet theme setting requires a UI reload to fully apply.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end
                  EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Show Enchants",
              tooltip="Toggle visibility of enchant icons on the inspect sheet.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.inspectShowEnchants ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.inspectShowEnchants = v
                  if EllesmereUI._refreshInspectEnchantsVisibility then
                      EllesmereUI._refreshInspectEnchantsVisibility()
                  end
              end }
        );  y = y - h

        do
            local function themedOff()
                return not (EllesmereUIDB and EllesmereUIDB.themedInspectSheet)
            end

        end

        local itemLevelInspectRow
        itemLevelInspectRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Item Level",
              tooltip="Toggle visibility of item level text on the inspect sheet.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.inspectShowItemLevel ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.inspectShowItemLevel = v
                  if EllesmereUI._refreshInspectItemLevelVisibility then
                      EllesmereUI._refreshInspectItemLevelVisibility()
                  end
              end },
            { type="toggle", text="Show Upgrade Track",
              tooltip="Toggle visibility of upgrade track text on the inspect sheet.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.inspectShowUpgradeTrack ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.inspectShowUpgradeTrack = v
                  if EllesmereUI._refreshInspectUpgradeTrackVisibility then
                      EllesmereUI._refreshInspectUpgradeTrackVisibility()
                  end
              end }
        );  y = y - h

        do
            local function themedOff()
                return not (EllesmereUIDB and EllesmereUIDB.themedInspectSheet)
            end

            local itemLevelInspectBlock = CreateFrame("Frame", nil, itemLevelInspectRow)
            itemLevelInspectBlock:SetAllPoints(itemLevelInspectRow)
            itemLevelInspectBlock:SetFrameLevel(itemLevelInspectRow:GetFrameLevel() + 10)
            itemLevelInspectBlock:EnableMouse(true)
            local itemLevelInspectBg = EllesmereUI.SolidTex(itemLevelInspectBlock, "BACKGROUND", 0, 0, 0, 0)
            itemLevelInspectBg:SetAllPoints()
            itemLevelInspectBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(itemLevelInspectBlock, EllesmereUI.DisabledTooltip("Inspect Sheet"))
            end)
            itemLevelInspectBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                if themedOff() then
                    itemLevelInspectBlock:Show()
                    itemLevelInspectRow:SetAlpha(0.3)
                else
                    itemLevelInspectBlock:Hide()
                    itemLevelInspectRow:SetAlpha(1)
                end
            end)
            if themedOff() then itemLevelInspectBlock:Show() itemLevelInspectRow:SetAlpha(0.3) else itemLevelInspectBlock:Hide() itemLevelInspectRow:SetAlpha(1) end
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h
        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Dragon Riding page
    ---------------------------------------------------------------------------
    local function EDR_DB()
        return ns.edrDB and ns.edrDB.profile
    end
    local function EDR_Cfg(k) local p = EDR_DB(); return p and p[k] end
    local function EDR_Set(k, v) local p = EDR_DB(); if p then p[k] = v end end
    local function EDR_SetField(k, field, v)
        local t = EDR_Cfg(k); if t then t[field] = v end
    end
    local function EDR_Rebuild() if ns.edrRebuild then ns.edrRebuild() end
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
    end
    local function EDR_Redraw() if ns.edrRedraw then ns.edrRedraw() end end

    -------------------------------------------------------------------
    --  Bar texture dropdown tables (shared media path, same as ERB)
    -------------------------------------------------------------------
    local EDR_BAR_TEXTURES = ns.EDR_BAR_TEXTURES
    local EDR_BAR_TEXTURE_ORDER = {
        "none", "melli", "atrocity",
        "fade", "fade-right",
        "thin-line-top", "thin-line-bottom",
        "beautiful", "plating",
        "divide", "glass",
        "gradient-lr", "gradient-rl", "gradient-bt", "gradient-tb",
        "matte", "sheer",
    }
    local EDR_BAR_TEXTURE_NAMES = {
        ["none"]        = "None",
        ["melli"]       = "Melli (ElvUI)",
        ["beautiful"]   = "Beautiful",
        ["plating"]     = "Plating",
        ["atrocity"]    = "Atrocity",
        ["divide"]      = "Divide",
        ["glass"]       = "Glass",
        ["fade-right"]  = "Fade Right",
        ["thin-line-top"]    = "Thin Line Top",
        ["thin-line-bottom"] = "Thin Line Bottom",
        ["fade"]        = "Fade",
        ["gradient-lr"] = "Gradient Right",
        ["gradient-rl"] = "Gradient Left",
        ["gradient-bt"] = "Gradient Up",
        ["gradient-tb"] = "Gradient Down",
        ["matte"]       = "Matte",
        ["sheer"]       = "Sheer",
    }

    local function BuildDragonRidingPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        -- Append SharedMedia textures (safe to call multiple times)
        if EllesmereUI.AppendSharedMediaTextures then
            EllesmereUI.AppendSharedMediaTextures(
                EDR_BAR_TEXTURE_NAMES,
                EDR_BAR_TEXTURE_ORDER,
                nil,
                EDR_BAR_TEXTURES
            )
        end
        local edrTexValues = {}
        local edrTexOrder  = {}
        for _, key in ipairs(EDR_BAR_TEXTURE_ORDER) do
            if key ~= "---" then
                edrTexValues[key] = EDR_BAR_TEXTURE_NAMES[key] or key
                edrTexOrder[#edrTexOrder + 1] = key
            end
        end
        edrTexValues._menuOpts = {
            itemHeight = 28,
            background = function(key) return EDR_BAR_TEXTURES[key] end,
        }

        local justifyValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
        local justifyOrder  = { "LEFT", "CENTER", "RIGHT" }

        _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Dragon Riding Bar",
              getValue = function() return EDR_Cfg("enabled") == true end,
              setValue = function(v) EDR_Set("enabled", v); EDR_Rebuild() end },
            { type = "toggle", text = "Hide in Combat",
              getValue = function() return EDR_Cfg("hideInCombat") == true end,
              setValue = function(v) EDR_Set("hideInCombat", v); EDR_Rebuild() end }
        ); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Width", min = 80, max = 600, step = 1,
              getValue = function() return EDR_Cfg("width") end,
              setValue = function(v) EDR_Set("width", v); EDR_Rebuild() end },
            { type = "slider", text = "Element Spacing", min = 0, max = 12, step = 1,
              getValue = function() return EDR_Cfg("gap") end,
              setValue = function(v) EDR_Set("gap", v); EDR_Rebuild() end }
        ); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Stack Spacing", min = 0, max = 10, step = 1,
              getValue = function() return EDR_Cfg("stackSpacing") end,
              setValue = function(v) EDR_Set("stackSpacing", v); EDR_Rebuild() end },
            { type = "toggle", text = "Show Icon Cooldown Text",
              getValue = function() return EDR_Cfg("whirlingSurgeText") and EDR_Cfg("whirlingSurgeText").enabled ~= false end,
              setValue = function(v) EDR_SetField("whirlingSurgeText", "enabled", v); EDR_Redraw() end }
        ); y = y - h
        local borderRow
        borderRow, h = W:DualRow(parent, y,
            { type = "slider", text = "Border Size", min = 0, max = 4, step = 1,
              getValue = function() return EDR_Cfg("borderThickness") or 0 end,
              setValue = function(v) EDR_Set("borderThickness", v); EDR_Redraw() end },
            { type = "dropdown", text = "Bar Texture",
              values = edrTexValues, order = edrTexOrder,
              getValue = function() return EDR_Cfg("barTexture") or "none" end,
              setValue = function(v) EDR_Set("barTexture", v); EDR_Redraw() end }
        ); y = y - h
        do
            local rgn = borderRow._leftRegion
            local ctrl = rgn._control
            local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
                rgn, borderRow:GetFrameLevel() + 3,
                function() local t = EDR_Cfg("borderColor"); return t.r, t.g, t.b, t.a end,
                function(r, g, b, a) local p = EDR_Cfg("borderColor"); p.r, p.g, p.b, p.a = r, g, b, a; EDR_Redraw() end,
                true, 20)
            EllesmereUI.PanelPP.Point(swatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(updateSwatch)
        end
        _, h = W:Spacer(parent, y, 20); y = y - h

        _, h = W:SectionHeader(parent, "LAYOUT", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Charge Height", min = 2, max = 24, step = 1,
              getValue = function() return EDR_Cfg("skyridingHeight") end,
              setValue = function(v) EDR_Set("skyridingHeight", v); EDR_Rebuild() end },
            { type = "multiSwatch", text = "Charge Color",
              swatches = {
                { text = "Background",
                  getValue = function() local t = EDR_Cfg("skyridingBg"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = EDR_Cfg("skyridingBg"); p.r, p.g, p.b, p.a = r, g, b, a; EDR_Redraw() end,
                  hasAlpha = true,
                  tooltip = "Background" },
                { text = "Stacks",
                  getValue = function() local t = EDR_Cfg("skyridingFilled"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = EDR_Cfg("skyridingFilled"); p.r, p.g, p.b, p.a = r, g, b, a; EDR_Redraw() end,
                  hasAlpha = true,
                  tooltip = "Charges" },
              } }
        ); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Second Wind Height", min = 2, max = 24, step = 1,
              getValue = function() return EDR_Cfg("secondWindHeight") end,
              setValue = function(v) EDR_Set("secondWindHeight", v); EDR_Rebuild() end },
            { type = "multiSwatch", text = "Second Wind Color",
              swatches = {
                { text = "Background",
                  getValue = function() local t = EDR_Cfg("secondWindBg"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = EDR_Cfg("secondWindBg"); p.r, p.g, p.b, p.a = r, g, b, a; EDR_Redraw() end,
                  hasAlpha = true,
                  tooltip = "Background" },
                { text = "Second Wind",
                  getValue = function() local t = EDR_Cfg("secondWindFilled"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = EDR_Cfg("secondWindFilled"); p.r, p.g, p.b, p.a = r, g, b, a; EDR_Redraw() end,
                  hasAlpha = true,
                  tooltip = "Second Wind" },
              } }
        ); y = y - h
        _, h = W:Spacer(parent, y, 20); y = y - h

        _, h = W:SectionHeader(parent, "SPEED BAR", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Height", min = 4, max = 40, step = 1,
              getValue = function() return EDR_Cfg("speedHeight") end,
              setValue = function(v) EDR_Set("speedHeight", v); EDR_Rebuild() end },
            { type = "toggle", text = "Thrill Color Change",
              getValue = function() return EDR_Cfg("thrillColorToggle") == true end,
              setValue = function(v) EDR_Set("thrillColorToggle", v); EDR_Redraw() end }
        ); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Speed Color",
              swatches = {
                { text = "Background",
                  getValue = function() local t = EDR_Cfg("speedBarBg"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = EDR_Cfg("speedBarBg"); p.r, p.g, p.b, p.a = r, g, b, a; EDR_Redraw() end,
                  hasAlpha = true,
                  tooltip = "Background" },
                { text = "Speed",
                  getValue = function() local t = EDR_Cfg("normalColor"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = EDR_Cfg("normalColor"); p.r, p.g, p.b, p.a = r, g, b, a; EDR_Redraw() end,
                  hasAlpha = true,
                  tooltip = "Speed" },
              } },
            { type = "multiSwatch", text = "Thrill Color",
              swatches = {
                { text = "Hash",
                  getValue = function() local t = EDR_Cfg("tickColor"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = EDR_Cfg("tickColor"); p.r, p.g, p.b, p.a = r, g, b, a; EDR_Redraw() end,
                  hasAlpha = true,
                  tooltip = "Hash Marker" },
                { text = "Thrill",
                  getValue = function() local t = EDR_Cfg("thrillColor"); return t.r, t.g, t.b, t.a end,
                  setValue = function(r, g, b, a) local p = EDR_Cfg("thrillColor"); p.r, p.g, p.b, p.a = r, g, b, a; EDR_Redraw() end,
                  hasAlpha = true,
                  tooltip = "Thrill" },
              } }
        ); y = y - h
        local speedTextRow
        speedTextRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Speed Text",
              getValue = function() return EDR_Cfg("speedText") and EDR_Cfg("speedText").enabled ~= false end,
              setValue = function(v) EDR_SetField("speedText", "enabled", v); EDR_Redraw() end },
            { type = "dropdown", text = "Text Align",
              values = justifyValues, order = justifyOrder,
              getValue = function() return (EDR_Cfg("speedText") or {}).justify or "CENTER" end,
              setValue = function(v) EDR_SetField("speedText", "justify", v); EDR_Redraw() end }
        )
        local _, cogShow = EllesmereUI.BuildCogPopup({
            title = "Speed Text Position",
            rows = {
                { type = "slider", label = "Size",     min = 6,    max = 32,  step = 1,
                  get = function() return (EDR_Cfg("speedText") or {}).size    or 12 end,
                  set = function(v) EDR_SetField("speedText", "size",    v); EDR_Redraw() end },
                { type = "slider", label = "Offset X", min = -200, max = 200, step = 1,
                  get = function() return (EDR_Cfg("speedText") or {}).offsetX or 0  end,
                  set = function(v) EDR_SetField("speedText", "offsetX", v); EDR_Redraw() end },
                { type = "slider", label = "Offset Y", min = -200, max = 200, step = 1,
                  get = function() return (EDR_Cfg("speedText") or {}).offsetY or 0  end,
                  set = function(v) EDR_SetField("speedText", "offsetY", v); EDR_Redraw() end },
            },
        })
        local cogBtn = CreateFrame("Button", nil, speedTextRow._rightRegion)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", speedTextRow._rightRegion._lastInline or speedTextRow._rightRegion._control, "LEFT", -8, 0)
        speedTextRow._rightRegion._lastInline = cogBtn
        cogBtn:SetFrameLevel(speedTextRow._rightRegion:GetFrameLevel() + 5)
        cogBtn:SetAlpha(0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY"); cogTex:SetAllPoints(); cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
        cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
        cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        y = y - h
        _, h = W:Spacer(parent, y, 20); y = y - h

        parent:SetHeight(math.abs(y - yOffset))
    end

    EllesmereUI:RegisterModule("EllesmereUIBlizzardSkin", {
        title       = "Blizz UI Enhanced",
        description = "Themed Blizzard frames: Character Sheet, tooltips, menus, popups, Dragon Riding HUD.",
        searchTerms = "blizzard skin character sheet tooltip menu popup dragon riding skyriding",
        pages       = { PAGE_CHARSHEET, PAGE_TOOLTIPS, PAGE_DRAGONRIDING },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_CHARSHEET then
                return BuildCharacterSheetPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_TOOLTIPS then
                return BuildTooltipsPage(pageName, parent, yOffset)
            end
            if pageName == PAGE_DRAGONRIDING then
                return BuildDragonRidingPage(pageName, parent, yOffset)
            end
        end,
        onReset = function()
            if EllesmereUIDragonRidingDB then
                EllesmereUIDragonRidingDB.profiles = nil
                EllesmereUIDragonRidingDB.profileKeys = nil
            end
            if EllesmereUIDB then
                EllesmereUIDB.customTooltips = nil
                EllesmereUIDB.accentReskinElements = nil
                EllesmereUIDB.tooltipPlayerTitles = nil
                EllesmereUIDB.tooltipFontScale = nil
                EllesmereUIDB.tooltipMythicScore = nil
                EllesmereUIDB.uberTooltips = nil
                EllesmereUIDB.uberTooltipsManual = nil
                EllesmereUIDB.reskinQueuePopup = nil
                EllesmereUIDB.reskinGameMenu = nil
                EllesmereUIDB.showQueueTimer = nil
                EllesmereUIDB.showMythicRating = nil
                EllesmereUIDB.showPvpItemLevel = nil
                EllesmereUIDB.statCategoryColors = nil
                EllesmereUIDB.statSectionsOrder = nil
                EllesmereUIDB.charSheetCollapsedSections = nil
                EllesmereUIDB.characterFramePos = nil
                EllesmereUIDB.friendsFramePos = nil
            end
        end,
    })

    SLASH_EBSK1 = "/ebsk"
    SlashCmdList.EBSK = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIBlizzardSkin")
    end
end)
