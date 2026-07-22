-------------------------------------------------------------------------------
--  EUI_BlizzardSkin_Options.lua
-------------------------------------------------------------------------------
local _, ns = ...
local PAGE_WINDOWSKINS   = "Blizzard Window Skins"
local PAGE_TOOLTIPS      = "Tooltips, Menus & Popups"
local PAGE_DRAGONRIDING  = "Dragon Riding"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local function BuildTooltipsPage(pageName, parent, yOffset)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h
        local BORDER_VALUES = { none="None", thin="Thin", normal="Normal", heavy="Heavy", strong="Strong" }
        local BORDER_ORDER = { "none", "thin", "normal", "heavy", "strong" }

        local function AttachBorderControls(row, prefix, disabledFn, allowBehind)
            local PP = EllesmereUI.PanelPP
            local left, right = row._leftRegion, row._rightRegion
            local popupRows = {
                { type="slider", label="Offset X", min=-10,max=10,step=1,
                  get=function() local v=EllesmereUIDB[prefix.."BorderOffsetX"]; if v~=nil then return v end return EllesmereUI.GetBorderTextureDefaultOffset(EllesmereUIDB[prefix.."BorderTexture"] or "solid") end,
                  set=function(v) EllesmereUIDB[prefix.."BorderOffsetX"]=v end },
                { type="slider", label="Offset Y", min=-10,max=10,step=1,
                  get=function() local v=EllesmereUIDB[prefix.."BorderOffsetY"]; if v~=nil then return v end return EllesmereUI.GetBorderTextureDefaultOffsetY(EllesmereUIDB[prefix.."BorderTexture"] or "solid") end,
                  set=function(v) EllesmereUIDB[prefix.."BorderOffsetY"]=v end },
            }
            if allowBehind then
                popupRows[#popupRows + 1] = {
                    type="toggle", label="Show Behind",
                    get=function() return EllesmereUIDB[prefix.."BorderBehind"] or false end,
                    set=function(v) EllesmereUIDB[prefix.."BorderBehind"]=v end,
                }
            end
            local _, showOffset = EllesmereUI.BuildCogPopup({ title="Border Offset", rows=popupRows })
            local cog=CreateFrame("Button",nil,left); cog:SetSize(26,26); cog:SetPoint("RIGHT",left._control,"LEFT",-8,0); cog:SetAlpha(.4)
            local ico=cog:CreateTexture(nil,"OVERLAY"); ico:SetAllPoints(); ico:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cog:SetScript("OnClick",function(self) showOffset(self) end); left._lastInline=cog
            -- Gray + mouse-off with the row like the mode swatches below
            -- (canonical cog disabled alphas: .15 off, .4 on). Applied once at
            -- build time too -- widget refresh only fires on later changes.
            local function UpdCogState()
                local off=disabledFn and disabledFn()
                cog:SetAlpha(off and .15 or .4); cog:EnableMouse(not off)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdCogState)
            UpdCogState()

            local function AddModeSwatch(anchor, mode, tip, getColor, custom)
                local sw, refresh=EllesmereUI.BuildColorSwatch(right,right:GetFrameLevel()+5,getColor,
                    function(r,g,b,a) EllesmereUIDB[prefix.."BorderColor"]={r=r,g=g,b=b}; EllesmereUIDB[prefix.."BorderOpacity"]=a; EllesmereUIDB[prefix.."BorderColorMode"]="custom" end,
                    custom,20)
                PP.Point(sw,"RIGHT",anchor,"LEFT",-8,0)
                local orig=sw:GetScript("OnClick")
                sw:SetScript("OnClick",function(self)
                    if mode~="custom" or (EllesmereUIDB[prefix.."BorderColorMode"] or "custom")~="custom" then
                        EllesmereUIDB[prefix.."BorderColorMode"]=mode; EllesmereUI:RefreshPage(); return
                    end
                    orig(self)
                end)
                sw:HookScript("OnEnter",function(self) EllesmereUI.ShowWidgetTooltip(self,tip) end)
                sw:HookScript("OnLeave",function() EllesmereUI.HideWidgetTooltip() end)
                -- Applied once at build time too -- widget refresh only fires
                -- on later changes, so without this every swatch opened lit.
                local function UpdSwatchState()
                    local off=disabledFn and disabledFn(); local active=(EllesmereUIDB[prefix.."BorderColorMode"] or "custom")==mode
                    sw:SetAlpha(off and .15 or (active and 1 or .3)); sw:EnableMouse(not off); refresh()
                end
                EllesmereUI.RegisterWidgetRefresh(UpdSwatchState)
                UpdSwatchState()
                return sw
            end
            local accent=AddModeSwatch(right._control,"accent","Accent Color",function() local c=EllesmereUI.ELLESMERE_GREEN; return c.r,c.g,c.b,1 end,false)
            local class=AddModeSwatch(accent,"class","Class Color",function() local _,k=UnitClass("player"); local c=RAID_CLASS_COLORS[k]; return c.r,c.g,c.b,1 end,false)
            local custom=AddModeSwatch(class,"custom","Custom Color",function() local c=EllesmereUIDB[prefix.."BorderColor"] or {r=1,g=1,b=1}; return c.r,c.g,c.b,EllesmereUIDB[prefix.."BorderOpacity"] or EllesmereUI.RESKIN.BRD_ALPHA end,true)
            right._lastInline=custom
        end

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        _, h = W:Spacer(parent, y, 20);  y = y - h

        _, h = W:SectionHeader(parent, "BLIZZARD POPUPS & GAME MENU", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Reskin Popups and Menus",
              tooltip="Reskins Blizzard's right-click context menus and pop-up dialogs with the EUI dark style. Requires reload to apply.",
              getValue=function()
                  -- Seeded from the old master by the blizzskin_reskin_master_split_v1
                  -- migration; independent thereafter. Default on.
                  return not EllesmereUIDB or EllesmereUIDB.reskinPopupsMenus ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.reskinPopupsMenus = v
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
            { type="toggle", text="Resurrect Accept Glow",
              tooltip="Adds a glowing, pulsating border around the Accept button of resurrection popups so a pending resurrect is hard to miss. Follows the Element & Text Color setting. Applies instantly, no reload needed.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.resurrectAcceptGlow or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.resurrectAcceptGlow = v
                  if EllesmereUI._EnsureResurrectGlow then EllesmereUI._EnsureResurrectGlow() end
              end }
        );  y = y - h

        local function popupOff() return EllesmereUIDB.reskinPopupsMenus == false end
        do
            local texValues,texOrder=EllesmereUI.GetBorderTextureDropdown()
            local outer
            outer,h=W:DualRow(parent,y,
                {type="dropdown",text="Border Style",disabled=popupOff,values=texValues,order=texOrder,getValue=function() return EllesmereUIDB.popupMenuBorderTexture or "solid" end,setValue=function(v) local c,b=EllesmereUI.GetBorderStyleSelectDefaults(v); EllesmereUIDB.popupMenuBorderTexture=v; EllesmereUIDB.popupMenuBorderOffsetX=nil; EllesmereUIDB.popupMenuBorderOffsetY=nil; EllesmereUIDB.popupMenuBorderBehind=b; EllesmereUIDB.popupMenuBorderColor=c end},
                {type="dropdown",text="Border Size",disabled=popupOff,values=BORDER_VALUES,order=BORDER_ORDER,getValue=function() return EllesmereUIDB.popupMenuBorderThickness or "thin" end,setValue=function(v) EllesmereUIDB.popupMenuBorderThickness=v end}); y=y-h
            AttachBorderControls(outer,"popupMenu",popupOff,true)
            local buttons
            buttons,h=W:DualRow(parent,y,
                {type="dropdown",text="Button Border Style",disabled=popupOff,values=texValues,order=texOrder,getValue=function() return EllesmereUIDB.popupMenuButtonBorderTexture or "solid" end,setValue=function(v) EllesmereUIDB.popupMenuButtonBorderTexture=v; EllesmereUIDB.popupMenuButtonBorderOffsetX=nil; EllesmereUIDB.popupMenuButtonBorderOffsetY=nil end},
                {type="dropdown",text="Button Border Size",disabled=popupOff,values=BORDER_VALUES,order=BORDER_ORDER,getValue=function() return EllesmereUIDB.popupMenuButtonBorderThickness or "thin" end,setValue=function(v) EllesmereUIDB.popupMenuButtonBorderThickness=v end}); y=y-h
            AttachBorderControls(buttons,"popupMenuButton",popupOff)
        end

        _,h=W:DualRow(parent,y,
            {type="colorpicker",text="Button Background",hasAlpha=true,disabled=popupOff,getValue=function() local c=EllesmereUIDB.popupMenuButtonBackgroundColor or {r=.1,g=.1,b=.1,a=.8}; return c.r,c.g,c.b,c.a end,setValue=function(r,g,b,a) EllesmereUIDB.popupMenuButtonBackgroundColor={r=r,g=g,b=b,a=a} end},
            {type="multiSwatch",text="Element & Text Color",disabled=popupOff,swatches={
                -- Effective mode comes from the skin file's resolver: unset =
                -- native unless the legacy Accent Colored Elements opt-in is
                -- present. All four highlights read it so the default state
                -- is shown truthfully.
                {tooltip="Native Colors",hasAlpha=false,getValue=function() return 1,1,1 end,setValue=function() end,onClick=function() EllesmereUIDB.popupMenuButtonTextColorMode="native"; EllesmereUI:RefreshPage() end,refreshAlpha=function() local m=EllesmereUI._getPopupMenuElementMode and EllesmereUI._getPopupMenuElementMode() or "native"; return m=="native" and 1 or .3 end},
                {tooltip="Accent Color",hasAlpha=false,getValue=function() local c=EllesmereUI.ELLESMERE_GREEN; return c.r,c.g,c.b end,setValue=function() end,onClick=function() EllesmereUIDB.popupMenuButtonTextColorMode="accent"; EllesmereUI:RefreshPage() end,refreshAlpha=function() local m=EllesmereUI._getPopupMenuElementMode and EllesmereUI._getPopupMenuElementMode() or "native"; return m=="accent" and 1 or .3 end},
                {tooltip="Custom Color",hasAlpha=false,getValue=function() local c=EllesmereUIDB.popupMenuButtonTextColor or {r=1,g=1,b=1}; return c.r,c.g,c.b end,setValue=function(r,g,b) EllesmereUIDB.popupMenuButtonTextColorMode="custom"; EllesmereUIDB.popupMenuButtonTextColor={r=r,g=g,b=b} end,onClick=function(self) local m=EllesmereUI._getPopupMenuElementMode and EllesmereUI._getPopupMenuElementMode() or "native"; if m~="custom" then EllesmereUIDB.popupMenuButtonTextColorMode="custom"; EllesmereUI:RefreshPage(); return end self._eabOrigClick(self) end,refreshAlpha=function() local m=EllesmereUI._getPopupMenuElementMode and EllesmereUI._getPopupMenuElementMode() or "native"; return m=="custom" and 1 or .3 end},
                {tooltip="Class Color",hasAlpha=false,getValue=function() local _,k=UnitClass("player"); local c=RAID_CLASS_COLORS[k]; return c.r,c.g,c.b end,setValue=function() end,onClick=function() EllesmereUIDB.popupMenuButtonTextColorMode="class"; EllesmereUI:RefreshPage() end,refreshAlpha=function() local m=EllesmereUI._getPopupMenuElementMode and EllesmereUI._getPopupMenuElementMode() or "native"; return m=="class" and 1 or .3 end},
            }}); y=y-h

        local queueRow
        queueRow, h = W:DualRow(parent, y,
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
              end },
            { type="toggle", text="Reskin Queue Popup",
              tooltip="Reskins the LFG/dungeon queue accept popup with the EUI dark style and adds an accept countdown timer bar.",
              getValue=function()
                  -- Independent, default on (not tied to any master reskin toggle).
                  return not EllesmereUIDB or EllesmereUIDB.reskinQueuePopup ~= false
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
              end }
        );  y = y - h

        -- Red "!" warning left of the Reskin Queue Popup toggle when EnhanceQoL is loaded
        local _eqolLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EnhanceQoL")
        if _eqolLoaded and queueRow and queueRow._rightRegion then
            local rgn = queueRow._rightRegion
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
            { type="toggle", text="Show Queue Timer",
              tooltip="Shows a countdown bar below the queue accept popup indicating how long you have to accept. Works with or without the reskin.",
              getValue=function()
                  return not EllesmereUIDB or EllesmereUIDB.showQueueTimer ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showQueueTimer = v
              end },
            { type="toggle", text="Enable Blizzard Pause Menu",
              tooltip="Reskins the ESC / Game Menu with the EUI dark style, matching fonts, and accent-colored title.",
              getValue=function()
                  -- Independent, default on (not tied to any master reskin toggle).
                  return not EllesmereUIDB or EllesmereUIDB.reskinGameMenu ~= false
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
              end }
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        _, h = W:SectionHeader(parent, "BLIZZARD TOOLTIP", y);  y = y - h

        -- "Reskin Tooltip" (customTooltips) is the master for this section: its
        -- reskin-driven sub-settings gray out (and stop applying) when it is off.
        -- Per-line tooltip content settings (titles, item level, M+ score,
        -- detailed tooltips, health strip) live in the content cog on this
        -- toggle. Settings independent of the skin (Show Detailed Tooltips,
        -- Hide Unit Health Strip, Show Spell ID, Show Max Stack) stay editable
        -- with the reskin off.
        local function ttReskinOff()
            return EllesmereUIDB and EllesmereUIDB.customTooltips == false
        end

        local ttCursorRow
        ttCursorRow, h = W:DualRow(parent, y,
            { type="toggle", text="Reskin Tooltip",
              tooltip="Reskins Blizzard tooltips with a dark, minimal style matching the EUI aesthetic. Requires reload to apply.",
              getValue=function()
                  return not EllesmereUIDB or EllesmereUIDB.customTooltips ~= false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.customTooltips = v
                  EllesmereUI:RefreshPage()  -- gray/ungray the rest of the section now
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
            { type="toggle", text="Anchor to Cursor",
              tooltip="Makes the game tooltip follow your mouse cursor instead of showing at its fixed screen position (drag the Tooltip box in Unlock Mode to change that). Use the arrows icon to pick the position relative to the cursor and fine-tune the X/Y offset.",
              disabled=ttReskinOff, disabledTooltip="Reskin Tooltip",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.tooltipAnchorCursor = v
                  if EllesmereUI._applyTooltipCursorAnchor then EllesmereUI._applyTooltipCursorAnchor() end
                  -- Re-park the fixed anchor (and seed it if this profile never
                  -- has) so turning the cursor mode off resumes cleanly.
                  if EllesmereUI._applyTooltipFixedAnchor then EllesmereUI._applyTooltipFixedAnchor() end
                  EllesmereUI:RefreshPage()  -- update the position cog + Growth Direction disabled states
              end }
        );  y = y - h

        -- Position control on Anchor to Cursor (right region): position + X/Y offset
        do
            local rightRgn = ttCursorRow._rightRegion
            local function ttCursorOff()
                return not (EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor)
            end
            local _, ttCursorPosShow = EllesmereUI.BuildCogPopup({
                title = "Cursor Tooltip Position",
                rows = {
                    { type="dropdown", label="Position",
                      values={ bottomright="Bottom Right", bottomleft="Bottom Left",
                               topright="Top Right", topleft="Top Left",
                               right="Right", left="Left", top="Top", bottom="Bottom",
                               center="Center" },
                      order={ "bottomright", "bottomleft", "topright", "topleft",
                              "right", "left", "top", "bottom", "center" },
                      get=function() return EllesmereUIDB and EllesmereUIDB.tooltipCursorPosition or "top" end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.tooltipCursorPosition = v
                      end },
                    { type="slider", label="Offset X", min=-100, max=100, step=1,
                      get=function() return (EllesmereUIDB and EllesmereUIDB.tooltipCursorOffsetX) or 0 end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.tooltipCursorOffsetX = v
                      end },
                    { type="slider", label="Offset Y", min=-100, max=100, step=1,
                      get=function() return (EllesmereUIDB and EllesmereUIDB.tooltipCursorOffsetY) or 0 end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.tooltipCursorOffsetY = v
                      end },
                },
            })
            -- Manual position button (this file has no shared button helper)
            local ttPosBtn = CreateFrame("Button", nil, rightRgn)
            ttPosBtn:SetSize(26, 26)
            ttPosBtn:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -9, 0)
            rightRgn._lastInline = ttPosBtn
            ttPosBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            ttPosBtn:SetAlpha(ttCursorOff() and 0.15 or 0.4)
            local ttPosTex = ttPosBtn:CreateTexture(nil, "OVERLAY")
            ttPosTex:SetAllPoints()
            ttPosTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            ttPosBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            ttPosBtn:SetScript("OnLeave", function(self) self:SetAlpha(ttCursorOff() and 0.15 or 0.4) end)
            ttPosBtn:SetScript("OnClick", function(self) ttCursorPosShow(self) end)

            -- Blocking overlay + disabled tooltip when the toggle is off
            local ttPosBlock = CreateFrame("Frame", nil, ttPosBtn)
            ttPosBlock:SetAllPoints()
            ttPosBlock:SetFrameLevel(ttPosBtn:GetFrameLevel() + 10)
            ttPosBlock:EnableMouse(true)
            ttPosBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(ttPosBtn, EllesmereUI.DisabledTooltip("Anchor to Cursor"))
            end)
            ttPosBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateTtPosState()
                local off = ttCursorOff()
                ttPosBtn:SetAlpha(off and 0.15 or 0.4)
                if off then ttPosBlock:Show() else ttPosBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateTtPosState)
            UpdateTtPosState()
        end

        -- Content cog on Reskin Tooltip (left region): the per-line tooltip
        -- content settings. The cog itself stays active with the reskin off
        -- because Show Detailed Tooltips and Hide Unit Health Strip work with
        -- the default Blizzard tooltip too; the reskin-driven rows gray out
        -- individually inside the popup.
        do
            local leftRgn = ttCursorRow._leftRegion
            local _, ttContentShow = EllesmereUI.BuildCogPopup({
                title = "Tooltip Content",
                rows = {
                    { type="toggle", label="Show Player Titles",
                      disabled=ttReskinOff, disabledTooltip="Reskin Tooltip",
                      get=function()
                          return EllesmereUIDB and EllesmereUIDB.tooltipPlayerTitles or false
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.tooltipPlayerTitles = v
                      end },
                    { type="toggle", label="Show Item Level",
                      disabled=ttReskinOff, disabledTooltip="Reskin Tooltip",
                      get=function()
                          return not EllesmereUIDB or EllesmereUIDB.tooltipItemLevel ~= false
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.tooltipItemLevel = v
                      end },
                    { type="toggle", label="Show M+ Score",
                      disabled=ttReskinOff, disabledTooltip="Reskin Tooltip",
                      get=function()
                          return not EllesmereUIDB or EllesmereUIDB.tooltipMythicScore ~= false
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.tooltipMythicScore = v
                      end },
                    { type="toggle", label="Show Mount",
                      tooltip="Adds the mount a player is riding to their tooltip, with a green check if you own it or a red X if you don't.",
                      disabled=ttReskinOff, disabledTooltip="Reskin Tooltip",
                      get=function()
                          return EllesmereUIDB and EllesmereUIDB.tooltipShowMount or false
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.tooltipShowMount = v
                      end },
                    { type="toggle", label="Show Guild Rank",
                      disabled=ttReskinOff, disabledTooltip="Reskin Tooltip",
                      get=function()
                          return EllesmereUIDB and EllesmereUIDB.tooltipShowGuildRank or false
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.tooltipShowGuildRank = v
                      end },
                    { type="toggle", label="Show Unit Target",
                      tooltip="Adds a Targeting line showing who the hovered player or NPC is targeting, in green when it's you.",
                      disabled=ttReskinOff, disabledTooltip="Reskin Tooltip",
                      get=function()
                          return EllesmereUIDB and EllesmereUIDB.tooltipShowTarget or false
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.tooltipShowTarget = v
                      end },
                    -- CVar-backed; only enforced on login after the user has
                    -- toggled it once (uberTooltipsManual).
                    { type="toggle", label="Show Detailed Tooltips",
                      get=function()
                          return GetCVar("UberTooltips") == "1"
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.uberTooltipsManual = true
                          EllesmereUIDB.uberTooltips = v
                          SetCVar("UberTooltips", v and "1" or "0")
                      end },
                    { type="toggle", label="Hide Unit Health Strip",
                      get=function()
                          return not (EllesmereUIDB and EllesmereUIDB.tooltipHideHealthStrip == false)
                      end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.tooltipHideHealthStrip = v
                          if EllesmereUI._applyTooltipHealthStrip then EllesmereUI._applyTooltipHealthStrip() end
                      end },
                },
            })
            local ttContentBtn = CreateFrame("Button", nil, leftRgn)
            ttContentBtn:SetSize(26, 26)
            ttContentBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = ttContentBtn
            ttContentBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            ttContentBtn:SetAlpha(0.4)
            local ttContentTex = ttContentBtn:CreateTexture(nil, "OVERLAY")
            ttContentTex:SetAllPoints()
            ttContentTex:SetTexture(EllesmereUI.COGS_ICON)
            ttContentBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            ttContentBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
            ttContentBtn:SetScript("OnClick", function(self) ttContentShow(self) end)
        end

        -- Unified tooltip background: controls BOTH the Blizzard tooltip reskin
        -- and the EUI custom tooltips (read live via EllesmereUI.GetTooltipBg).
        -- Defaults to the RESKIN palette (#111111 @ 92%); the next tooltip shown
        -- picks up changes, so no reload is needed.
        _, h = W:DualRow(parent, y,
            { type="colorpicker", text="Background Color",
              tooltip="Background color for both Blizzard tooltips and EllesmereUI's own tooltips",
              disabled=ttReskinOff, disabledTooltip="Reskin Tooltip",
              getValue=function()
                  local c = EllesmereUIDB and EllesmereUIDB.tooltipBgColor
                  if c then return c.r, c.g, c.b end
                  local R = EllesmereUI.RESKIN
                  return R.BG_R, R.BG_G, R.BG_B
              end,
              setValue=function(r, g, b)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.tooltipBgColor = { r = r, g = g, b = b }
              end },
            { type="slider", text="Background Opacity", min=0, max=100, step=1,
              disabled=ttReskinOff, disabledTooltip="Reskin Tooltip",
              getValue=function()
                  local a = (EllesmereUIDB and EllesmereUIDB.tooltipBgOpacity) or EllesmereUI.RESKIN.TT_ALPHA
                  return math.floor(a * 100 + 0.5)
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.tooltipBgOpacity = v / 100
              end });  y = y - h

        local ttModeRow
        ttModeRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Show Tooltips",
              tooltip="Controls when game tooltips appear",
              disabled=ttReskinOff, disabledTooltip="Reskin Tooltip",
              values={ always="Always", outOfCombat="Out of Combat", outOfBossCombat="Out of Boss Combat", never="Never" },
              order={ "always", "outOfCombat", "outOfBossCombat", "never" },
              getValue=function() return (EllesmereUIDB and EllesmereUIDB.tooltipShowMode) or "always" end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.tooltipShowMode = v
                  EllesmereUI:RefreshPage()  -- update the Use Modifier cog disabled state
              end },
            -- Front-end duplicate of the toggle in Global Settings > Developer;
            -- same EllesmereUIDB.showSpellID key read by the tooltip logic in
            -- EllesmereUI.lua (no separate backend). Independent of the reskin.
            { type="toggle", text="Show Spell ID on Tooltip",
              tooltip="Appends the spell or item ID to tooltips. The same setting as Global Settings > Developer.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.showSpellID or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showSpellID = v
                  EllesmereUI:RefreshPage()  -- update the Use Modifier cog disabled state
              end }
        );  y = y - h

        -- "Use Modifier" cog on Show Spell ID (right region): the spell/item ID
        -- lines only show while the chosen modifier is held. Disabled (blocked +
        -- dimmed) when Show Spell ID is off, mirroring the cursor-position cog.
        do
            local rightRgn = ttModeRow._rightRegion
            local function sidOff()
                return not (EllesmereUIDB and EllesmereUIDB.showSpellID)
            end
            local _, sidModShow = EllesmereUI.BuildCogPopup({
                title = "Spell ID",
                rows = {
                    { type="dropdown", label="Use Modifier",
                      values={ none="None", shift="Shift", control="Control", alt="Alt" },
                      order={ "none", "shift", "control", "alt" },
                      get=function() return (EllesmereUIDB and EllesmereUIDB.spellIDModifier) or "none" end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.spellIDModifier = v
                      end },
                },
            })
            local sidModBtn = CreateFrame("Button", nil, rightRgn)
            sidModBtn:SetSize(26, 26)
            sidModBtn:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -9, 0)
            rightRgn._lastInline = sidModBtn
            sidModBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            sidModBtn:SetAlpha(sidOff() and 0.15 or 0.4)
            local sidModTex = sidModBtn:CreateTexture(nil, "OVERLAY")
            sidModTex:SetAllPoints()
            sidModTex:SetTexture(EllesmereUI.COGS_ICON)
            sidModBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            sidModBtn:SetScript("OnLeave", function(self) self:SetAlpha(sidOff() and 0.15 or 0.4) end)
            sidModBtn:SetScript("OnClick", function(self) sidModShow(self) end)

            -- Blocking overlay + disabled tooltip when Show Spell ID is off
            local sidModBlock = CreateFrame("Frame", nil, sidModBtn)
            sidModBlock:SetAllPoints()
            sidModBlock:SetFrameLevel(sidModBtn:GetFrameLevel() + 10)
            sidModBlock:EnableMouse(true)
            sidModBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(sidModBtn, EllesmereUI.DisabledTooltip("Show Spell ID on Tooltip"))
            end)
            sidModBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateSidModState()
                local off = sidOff()
                sidModBtn:SetAlpha(off and 0.15 or 0.4)
                if off then sidModBlock:Show() else sidModBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateSidModState)
            UpdateSidModState()
        end

        -- "Use Modifier" cog on Show Tooltips (left region): while the chosen
        -- modifier is held, suppression is lifted so a hidden tooltip can be
        -- read on hover (e.g. peeking a spell in combat). Disabled (blocked +
        -- dimmed) when the reskin is off or the mode is "Always" (nothing hides).
        do
            local leftRgn = ttModeRow._leftRegion
            local function showModOff()
                if ttReskinOff() then return true end
                return ((EllesmereUIDB and EllesmereUIDB.tooltipShowMode) or "always") == "always"
            end
            local _, showModShow = EllesmereUI.BuildCogPopup({
                title = "Show Tooltips",
                rows = {
                    { type="dropdown", label="Peek Modifier",
                      values={ none="None", shift="Shift", control="Control", alt="Alt" },
                      order={ "none", "shift", "control", "alt" },
                      get=function() return (EllesmereUIDB and EllesmereUIDB.tooltipShowModifier) or "none" end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.tooltipShowModifier = v
                      end },
                },
            })
            local showModBtn = CreateFrame("Button", nil, leftRgn)
            showModBtn:SetSize(26, 26)
            showModBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = showModBtn
            showModBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            showModBtn:SetAlpha(showModOff() and 0.15 or 0.4)
            local showModTex = showModBtn:CreateTexture(nil, "OVERLAY")
            showModTex:SetAllPoints()
            showModTex:SetTexture(EllesmereUI.COGS_ICON)
            showModBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            showModBtn:SetScript("OnLeave", function(self) self:SetAlpha(showModOff() and 0.15 or 0.4) end)
            showModBtn:SetScript("OnClick", function(self) showModShow(self) end)

            local showModBlock = CreateFrame("Frame", nil, showModBtn)
            showModBlock:SetAllPoints()
            showModBlock:SetFrameLevel(showModBtn:GetFrameLevel() + 10)
            showModBlock:EnableMouse(true)
            showModBlock:SetScript("OnEnter", function()
                local msg = ttReskinOff() and EllesmereUI.DisabledTooltip("Reskin Tooltip")
                    or "This option requires Show Tooltips to be set to hide tooltips"
                EllesmereUI.ShowWidgetTooltip(showModBtn, msg)
            end)
            showModBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateShowModState()
                local off = showModOff()
                showModBtn:SetAlpha(off and 0.15 or 0.4)
                if off then showModBlock:Show() else showModBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateShowModState)
            UpdateShowModState()
        end

        do
            local texValues,texOrder=EllesmereUI.GetBorderTextureDropdown()
            local tooltipBorder
            tooltipBorder,h=W:DualRow(parent,y,
                {type="dropdown",text="Border Style",disabled=ttReskinOff,values=texValues,order=texOrder,getValue=function() return EllesmereUIDB.tooltipBorderTexture or "solid" end,setValue=function(v) local c,b=EllesmereUI.GetBorderStyleSelectDefaults(v); EllesmereUIDB.tooltipBorderTexture=v; EllesmereUIDB.tooltipBorderOffsetX=nil; EllesmereUIDB.tooltipBorderOffsetY=nil; EllesmereUIDB.tooltipBorderBehind=b; EllesmereUIDB.tooltipBorderColor=c end},
                {type="dropdown",text="Border Size",disabled=ttReskinOff,values=BORDER_VALUES,order=BORDER_ORDER,getValue=function() return EllesmereUIDB.tooltipBorderThickness or ({[0]="none",[1]="thin",[2]="normal",[3]="heavy",[4]="strong"})[EllesmereUIDB.tooltipBorderSize or 1] or "thin" end,setValue=function(v) EllesmereUIDB.tooltipBorderThickness=v end}); y=y-h
            AttachBorderControls(tooltipBorder,"tooltip",ttReskinOff,true)
        end

        local borderRow
        borderRow, h = W:DualRow(parent, y,
            -- Independent of the reskin, so it is NOT gated by "Reskin
            -- Tooltip" -- like Show Spell ID.
            { type="toggle", text="Show Max Stack for Items",
              tooltip="Appends an item's max stack count on tooltip.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.showItemMaxStacks or false
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showItemMaxStacks = v
                  EllesmereUI:RefreshPage()  -- update the Use Modifier cog disabled state
              end },
            -- Default screen-anchored tooltip only (see ApplyGrowthDirection
            -- in EllesmereUIBlizzardSkin.lua): Blizzard picks the anchored
            -- corner dynamically from the tooltip's screen position; "Expand
            -- Up"/"Expand Down" force the vertical component of that corner.
            -- The cursor anchor re-points the tooltip itself, so this grays
            -- out while Anchor to Cursor is on.
            { type="dropdown", text="Growth Direction",
              tooltip="Forces which way the default screen-anchored tooltip expands as lines are added. Default lets Blizzard decide from the tooltip's screen position.",
              disabled=function()
                  return ttReskinOff() or (EllesmereUIDB and EllesmereUIDB.tooltipAnchorCursor and true or false)
              end,
              disabledTooltip=function()
                  if ttReskinOff() then return "Reskin Tooltip" end
                  return "This option does not apply while Anchor to Cursor is enabled"
              end,
              values={ default="Default", up="Expand Up", down="Expand Down" },
              order={ "default", "up", "down" },
              getValue=function()
                  return (EllesmereUIDB and EllesmereUIDB.tooltipGrowthDirection) or "default"
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.tooltipGrowthDirection = v
              end }
        );  y = y - h

        -- "Use Modifier" cog on Show Max Stack for Items (right region): the Max
        -- Stack line only shows while the chosen modifier is held. Disabled
        -- (blocked + dimmed) when the toggle is off, mirroring the Spell ID cog.
        do
            -- The toggle now lives in the LEFT slot (slot swap above).
            local rightRgn = borderRow._leftRegion
            local function iStacksOff()
                return not (EllesmereUIDB and EllesmereUIDB.showItemMaxStacks)
            end
            local _, iStacksModShow = EllesmereUI.BuildCogPopup({
                title = "Item Stacks",
                rows = {
                    { type="dropdown", label="Use Modifier",
                      values={ none="None", shift="Shift", control="Control", alt="Alt" },
                      order={ "none", "shift", "control", "alt" },
                      get=function() return (EllesmereUIDB and EllesmereUIDB.itemStackModifier) or "none" end,
                      set=function(v)
                          if not EllesmereUIDB then EllesmereUIDB = {} end
                          EllesmereUIDB.itemStackModifier = v
                      end },
                },
            })
            local iStacksModBtn = CreateFrame("Button", nil, rightRgn)
            iStacksModBtn:SetSize(26, 26)
            iStacksModBtn:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -9, 0)
            rightRgn._lastInline = iStacksModBtn
            iStacksModBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
            iStacksModBtn:SetAlpha(iStacksOff() and 0.15 or 0.4)
            local iStacksModTex = iStacksModBtn:CreateTexture(nil, "OVERLAY")
            iStacksModTex:SetAllPoints()
            iStacksModTex:SetTexture(EllesmereUI.COGS_ICON)
            iStacksModBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            iStacksModBtn:SetScript("OnLeave", function(self) self:SetAlpha(iStacksOff() and 0.15 or 0.4) end)
            iStacksModBtn:SetScript("OnClick", function(self) iStacksModShow(self) end)

            -- Blocking overlay + disabled tooltip when Show Max Stack for Items is off
            local iStacksModBlock = CreateFrame("Frame", nil, iStacksModBtn)
            iStacksModBlock:SetAllPoints()
            iStacksModBlock:SetFrameLevel(iStacksModBtn:GetFrameLevel() + 10)
            iStacksModBlock:EnableMouse(true)
            iStacksModBlock:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(iStacksModBtn, EllesmereUI.DisabledTooltip("Show Max Stack for Items"))
            end)
            iStacksModBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function UpdateIStacksModState()
                local off = iStacksOff()
                iStacksModBtn:SetAlpha(off and 0.15 or 0.4)
                if off then iStacksModBlock:Show() else iStacksModBlock:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateIStacksModState)
            UpdateIStacksModState()
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Character Sheet card content (Blizzard Window Skins page). The style
    --  choice lives on the card header dropdown; everything here is the
    --  window's sub-settings, built as direct children of the page wrapper so
    --  inline search and nav deep-links still see them.
    ---------------------------------------------------------------------------
    -- Section headers inside window-skin cards: title indented 5px to sit
    -- with the card chrome (the divider stays full width).
    local function WSCardSection(parent, text, y)
        local W = EllesmereUI.Widgets
        local hf, h = W:SectionHeader(parent, text, y)
        if hf and hf._label then
            EllesmereUI.PanelPP.Point(hf._label, "BOTTOMLEFT", hf, "BOTTOMLEFT", 5, 8)
        end
        return hf, h
    end

    local function BuildCharacterSheetContent(parent, y)
        local W = EllesmereUI.Widgets
        local _, h
        local PP = EllesmereUI.PanelPP

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
        _, h = WSCardSection(parent, "CORE OPTIONS", y);  y = y - h

        local coreRow1
        coreRow1, h = W:DualRow(parent, y,
            { type="toggle", text="Show Mythic+ Rating",
              tooltip="Display your Mythic+ rating above the item level on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showMythicRating or false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showMythicRating = v
                  if EllesmereUI._updateMythicRatingDisplay then EllesmereUI._updateMythicRatingDisplay() end
              end },
            { type="toggle", text="Item Level",
              tooltip="Toggle visibility of item level text on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showItemLevel ~= false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showItemLevel = v
                  if EllesmereUI._refreshItemLevelVisibility then EllesmereUI._refreshItemLevelVisibility() end
              end }
        );  y = y - h
        AttachDisabledOverlay(coreRow1)

        local coreRow2
        coreRow2, h = W:DualRow(parent, y,
            { type="toggle", text="Upgrade Track",
              tooltip="Toggle visibility of upgrade track text on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showUpgradeTrack ~= false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showUpgradeTrack = v
                  if EllesmereUI._refreshUpgradeTrackVisibility then EllesmereUI._refreshUpgradeTrackVisibility() end
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
        AttachDisabledOverlay(coreRow2)

        local socketRow
        socketRow, h = W:DualRow(parent, y,
            { type="toggle", text="Socket Panel",
              tooltip="Show a panel of equipped-gear sockets on the character sheet; click a socket to gem it.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.charSheetSocketPanel ~= false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.charSheetSocketPanel = v
                  if EllesmereUI._refreshCharSheetSocketPanel then EllesmereUI._refreshCharSheetSocketPanel() end
              end },
            { type="slider", text="Icon Zoom", min=0, max=0.20, step=0.01,
              tooltip="Crops the border of the equipment-slot item icons on the character and inspect sheets. 0 shows the full icon. Only affects the themed character sheet.",
              getValue=function() return (EllesmereUIDB and EllesmereUIDB.charSheetIconZoom) or 0.07 end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.charSheetIconZoom = v
                  if EllesmereUI._refreshCharSheetIconZoom then EllesmereUI._refreshCharSheetIconZoom() end
              end }
        );  y = y - h
        AttachDisabledOverlay(socketRow)

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
            { type="toggle", text="Show PvP Item Level",
              tooltip="Display your PvP item level above the Mythic+ rating on the character sheet.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.showPvpItemLevel or false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.showPvpItemLevel = v
                  if EllesmereUI._updatePvpIlvlDisplay then EllesmereUI._updatePvpIlvlDisplay() end
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

        -- Gear flyout item levels. Independent of the themed character sheet
        -- (it enhances Blizzard's own equipment flyout), so it is not gated by
        -- the section's disabled overlay.
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Gear Flyout Item Levels",
              tooltip="Shows the item level on each item in the character sheet gear flyout (the popup of same-slot bag items that appears when hovering an equipped slot), coloured by quality.",
              getValue=function() return EllesmereUIDB and EllesmereUIDB.flyoutItemLevels or false end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.flyoutItemLevels = v
              end },
            { type="label", text="" }
        );  y = y - h

        _, h = W:Spacer(parent, y, 10);  y = y - h

        ---------------------------------------------------------------------------
        --  STAT DISPLAY
        ---------------------------------------------------------------------------
        _, h = WSCardSection(parent, "STAT DISPLAY", y);  y = y - h

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
        _, h = WSCardSection(parent, "INSPECT SHEET", y);  y = y - h

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

        return y
    end

    ---------------------------------------------------------------------------
    --  LFG Menu card content
    ---------------------------------------------------------------------------
    local function BuildLFGMenuContent(parent, y)
        local W = EllesmereUI.Widgets
        local _, h

        _, h = WSCardSection(parent, "QUALITY OF LIFE", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Remember Sign-Up Roles",
              tooltip="Remembers the Tank/Healer/DPS roles you last applied with and restores them the next time you sign up to a premade group (limited to roles your current spec can fill). Works with or without the reskin.",
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

        return y
    end

    local function BuildMerchantContent(parent, y)
        local W = EllesmereUI.Widgets
        local _, h

        local function themedOff()
            return EllesmereUIDB and EllesmereUIDB.reskinMerchant == false
        end

        local function AttachDisabledOverlay(target)
            local block = CreateFrame("Frame", nil, target)
            block:SetAllPoints(target)
            block:SetFrameLevel(target:GetFrameLevel() + 10)
            block:EnableMouse(true)
            local bg = EllesmereUI.SolidTex(block, "BACKGROUND", 0, 0, 0, 0)
            bg:SetAllPoints()
            block:SetScript("OnEnter", function()
                EllesmereUI.ShowWidgetTooltip(block, EllesmereUI.DisabledTooltip("Merchant"))
            end)
            block:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            local function refresh()
                if themedOff() then block:Show(); target:SetAlpha(0.3)
                else block:Hide(); target:SetAlpha(1) end
            end
            EllesmereUI.RegisterWidgetRefresh(refresh); refresh()
        end

        _, h = WSCardSection(parent, "QUALITY OF LIFE", y);  y = y - h

        local function merchantShowAsListOff()
            return EllesmereUIDB and EllesmereUIDB.merchantShowAsList == false
        end

        local row
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Show As List",
              tooltip="Shows the items as a list instead of pages.",
              getValue=function()
                return EllesmereUIDB and EllesmereUIDB.merchantShowAsList == true
              end,
              setValue=function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                local previousValue = EllesmereUIDB.merchantShowAsList
                EllesmereUIDB.merchantShowAsList = v

                -- Enabling the setting breaks the UI immediately, a reload is required
                if EllesmereUI.ShowConfirmPopup then
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Merchant Show As List setting requires a UI reload to fully apply.",
                          confirmText = "Reload Now",
                          cancelText  = "Cancel",
                          onConfirm   = function() ReloadUI() end,
                          onCancel    = function()
                              EllesmereUIDB.merchantShowAsList = previousValue;
                              EllesmereUI:RefreshPage()
                          end,
                      })
                  end
              end },
            { type="slider", text="Row Height", min=24, max=40, step=1,
              disabled=merchantShowAsListOff, disabledTooltip="Show As List",
              getValue=function() return (EllesmereUIDB and EllesmereUIDB.merchantListRowHeight) or 32 end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.merchantListRowHeight = v
                  if EllesmereUI._Merchant_RefreshRowHeight then EllesmereUI._Merchant_RefreshRowHeight() end
              end }
        ); y = y - h
        AttachDisabledOverlay(row)

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Item Level",
              tooltip="Shows the item level on weapons and armor a vendor sells.",
              getValue=function()
                  return EllesmereUIDB and EllesmereUIDB.merchantShowItemLevel == true
              end,
              setValue=function(v)
                  if not EllesmereUIDB then EllesmereUIDB = {} end
                  EllesmereUIDB.merchantShowItemLevel = v
                  if EllesmereUI._Merchant_RefreshItemLevels then EllesmereUI._Merchant_RefreshItemLevels() end
              end },
            { type="label", text="" }
        ); y = y - h

        return y
    end

    ---------------------------------------------------------------------------
    --  Blizzard Window Skins page: one expandable card per reskinned window.
    --  Card headers are custom chrome, but every sub-setting ROW is a standard
    --  W: widget built as a direct child of the page wrapper, so inline search
    --  and nav deep-links keep working. Expand state is session-only; clicking
    --  a header rebuilds the page with that card open or closed.
    ---------------------------------------------------------------------------
    local WS_ARROW_DOWN = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-down3.png"
    local WS_ARROW_UP   = "Interface\\AddOns\\EllesmereUI\\media\\icons\\eui-arrow-up3.png"
    local WS_CARD_INSET = 0    -- card edges align with the DualRow content width
    local WS_HEADER_H   = 54
    local WS_CARD_GAP   = 14

    local _wsExpanded = {}
    local _wsApplyAllStyle = "eui"  -- set-all dropdown pick (session-only)

    local function WSReloadPopup(message)
        if EllesmereUI.ShowConfirmPopup then
            EllesmereUI:ShowConfirmPopup({
                title       = "Reload Required",
                message     = message,
                confirmText = "Reload Now",
                cancelText  = "Later",
                onConfirm   = function() ReloadUI() end,
            })
        end
    end

    -- Style vocabulary shared by the per-card dropdowns and the set-all row.
    local WS_STYLE_VALUES = { eui = "EllesmereUI", modern = "Modern", off = "Blizz Default" }
    local WS_STYLE_ORDER  = { "eui", "modern", "off" }

    -- Modern background color + opacity: ONE global setting for the Modern
    -- style, resolved by the window-skin engine and applied live to every
    -- window currently set to Modern.
    local function WSModernGet()
        if ns.WSkin and ns.WSkin.GetModernBG then
            return ns.WSkin.GetModernBG()
        end
        return 0.067, 0.067, 0.067, 0.97
    end
    local function WSModernSet(r, g, b, a)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB.blizzWindowModernDefault = { r = r, g = g, b = b, a = a }
        if EllesmereUI._WSkinRefreshStyles then EllesmereUI._WSkinRefreshStyles() end
    end

    -- Single Modern color swatch left of the set-all dropdown. The picker
    -- carries the opacity slider; edits write the Modern preset directly, so
    -- windows already on Modern recolor immediately (no Apply to All).
    local function AttachModernSwatch(host, anchorTo)
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(host, host:GetFrameLevel() + 5,
            function() return WSModernGet() end,
            function(r, g, b, a) WSModernSet(r, g, b, a) end,
            true, 20)
        EllesmereUI.PanelPP.Point(swatch, "RIGHT", anchorTo, "LEFT", -8, 0)
        swatch:HookScript("OnEnter", function(s)
            EllesmereUI.ShowWidgetTooltip(s, "Background color for the Modern style.")
        end)
        swatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(updateSwatch)
    end

    -- Global look settings (Global Options section): central tables, nil =
    -- defaults, resolved by the window-skin engine and applied live.
    local function WSLook(key)
        return EllesmereUIDB and EllesmereUIDB[key]
    end
    local function WSLookSet(key, field, v)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        local t = EllesmereUIDB[key]
        if not t then t = {}; EllesmereUIDB[key] = t end
        t[field] = v
        if EllesmereUI._WSkinRefreshLooks then EllesmereUI._WSkinRefreshLooks() end
    end

    -- Inline accent|custom swatch pair on a DualRow region (the standard
    -- dual-swatch treatment): custom sits nearest the control, accent left of
    -- it; the active mode renders bright, the other dimmed.
    local function AttachLookSwatches(rgn, row, key)
        local PP = EllesmereUI.PanelPP
        local ctrl = rgn._control

        local customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(
            rgn, row:GetFrameLevel() + 3,
            function()
                local c = WSLook(key)
                local col = c and c.color
                if col then return col.r or 1, col.g or 1, col.b or 1 end
                return 1, 1, 1
            end,
            function(r, g, b)
                WSLookSet(key, "color", { r = r, g = g, b = b })
                WSLookSet(key, "useCustom", true)
                EllesmereUI:RefreshPage()
            end,
            false, 20)
        PP.Point(customSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
        local origClick = customSwatch:GetScript("OnClick")
        customSwatch:SetScript("OnClick", function(self, ...)
            local c = WSLook(key)
            if not (c and c.useCustom) then
                WSLookSet(key, "useCustom", true)
                EllesmereUI:RefreshPage()
                return
            end
            if origClick then origClick(self, ...) end
        end)
        customSwatch:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color")
        end)
        customSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        local accentSwatch, updateAccent = EllesmereUI.BuildColorSwatch(
            rgn, row:GetFrameLevel() + 3,
            function()
                return EllesmereUI.ResolveActiveAccent()
            end,
            function()
                WSLookSet(key, "useCustom", false)
                EllesmereUI:RefreshPage()
            end,
            false, 20)
        PP.Point(accentSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
        accentSwatch:SetScript("OnClick", function()
            WSLookSet(key, "useCustom", false)
            EllesmereUI:RefreshPage()
        end)
        accentSwatch:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(accentSwatch, "Accent Color")
        end)
        accentSwatch:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        rgn._lastInline = accentSwatch

        local function refreshPair()
            updateCustom(); updateAccent()
            local c = WSLook(key)
            local useCustom = c and c.useCustom
            customSwatch:SetAlpha(useCustom and 1 or 0.3)
            accentSwatch:SetAlpha(useCustom and 0.3 or 1)
        end
        EllesmereUI.RegisterWidgetRefresh(refreshPair)
        refreshPair()
    end

    local WINDOWS = {
        {
            key   = "charsheet",
            title = "Character Sheet",
            desc  = "Equipment panel with stat categories, item level, enchants, gems, and the inspect sheet.",
            reloadMsg = "Character Sheet theme setting requires a UI reload to fully apply.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.themedCharacterSheet = v
                EllesmereUIDB.themedInspectSheet = v
                -- Individual feature toggles retain their values.
            end,
            buildContent = BuildCharacterSheetContent,
        },
        {
            key   = "lfg",
            title = "LFG Menu",
            desc  = "Group Finder and Premade Groups window, plus browsing quality-of-life extras.",
            reloadMsg = "Changing the Group Finder reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinLFGMenu = v
            end,
            buildContent = BuildLFGMenuContent,
        },
        {
            key   = "greatvault",
            title = "Great Vault",
            desc  = "Weekly rewards window with custom tile backgrounds, progress colors, and completion states.",
            reloadMsg = "Changing the Great Vault reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinGreatVault = v
            end,
        },
        {
            key   = "adventureguide",
            title = "Adventure Guide",
            desc  = "Encounter Journal: instance select, boss details, loot lists, and the bottom nav tabs.",
            reloadMsg = "Changing the Adventure Guide reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinAdventureGuide = v
            end,
        },
        {
            key   = "collections",
            title = "Collections",
            desc  = "Mounts, pets, toys, heirlooms, appearances, and campsites.",
            reloadMsg = "Changing the Collections reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinCollections = v
            end,
        },
        {
            key   = "playerspells",
            title = "Talents & Spellbook",
            desc  = "The Player Spells window: talents, spec selection, and the spellbook.",
            reloadMsg = "Changing the Talents & Spellbook reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinPlayerSpells = v
            end,
        },
        {
            key   = "professionsbook",
            title = "Professions",
            desc  = "The professions overview book with squared icons and flat progress bars.",
            reloadMsg = "Changing the Professions reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinProfessionsBook = v
            end,
        },
        {
            key   = "professions",
            title = "Profession Crafting",
            desc  = "The profession crafting window: recipe list, schematic, specializations, and crafting orders.",
            reloadMsg = "Changing the Profession Crafting reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinProfessions = v
            end,
        },
        {
            key   = "worldmap",
            title = "Map & Quest Log",
            desc  = "The world map window chrome and the quest log side panel.",
            reloadMsg = "Changing the Map & Quest Log reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinWorldMap = v
            end,
        },
        {
            key   = "guild",
            title = "Guild & Communities",
            desc  = "The Guild & Communities window: roster, chat, and the community list.",
            reloadMsg = "Changing the Guild & Communities reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinGuild = v
            end,
        },
        {
            key   = "calendar",
            title = "Calendar",
            desc  = "The monthly calendar grid, event dialogs, and navigation arrows.",
            reloadMsg = "Changing the Calendar reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinCalendar = v
            end,
        },
        {
            key   = "achievements",
            title = "Achievements",
            desc  = "The achievement window: categories, rows, progress bars, and search.",
            reloadMsg = "Changing the Achievements reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinAchievements = v
            end,
        },
        {
            key   = "mail",
            title = "Mail",
            desc  = "The mailbox: inbox rows, send mail, open mail, and attachment slots.",
            reloadMsg = "Changing the Mail reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinMail = v
            end,
        },
        {
            key   = "catalyst",
            title = "Catalyst",
            desc  = "The item conversion window (catalyst and similar kiosks).",
            reloadMsg = "Changing the Catalyst reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinCatalyst = v
            end,
        },
        {
            key   = "socket",
            title = "Gem Socketing",
            desc  = "The gem socketing window with squared gem slots.",
            reloadMsg = "Changing the Gem Socketing reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinSocket = v
            end,
        },
        {
            key   = "housing",
            title = "Housing Dashboard",
            desc  = "The housing dashboard window background, border, and title bar.",
            reloadMsg = "Changing the Housing Dashboard reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinHousing = v
            end,
        },
        {
            key   = "micromenu",
            title = "Micro Menu",
            desc  = "Flattens the micro menu buttons into the EllesmereUI style.",
            reloadMsg = "Changing the Micro Menu reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinMicroMenu = v
            end,
        },
        {
            key   = "dressup",
            title = "Dressing Room",
            desc  = "The item preview / transmog dressing room window.",
            reloadMsg = "Changing the Dressing Room reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinDressUp = v
            end,
        },
        {
            key   = "transmog",
            title = "Transmogrifier",
            desc  = "The transmogrification window at the transmogrifier.",
            reloadMsg = "Changing the Transmogrifier reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinTransmog = v
            end,
        },
        {
            key   = "merchant",
            title = "Merchant",
            desc  = "The vendor window: item list, buyback, and bottom money bar.",
            reloadMsg = "Changing the Merchant reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinMerchant = v
            end,
            buildContent = BuildMerchantContent,
        },
        {
            key   = "auctionhouse",
            title = "Auction House",
            desc  = "The auction house: browse, sell, and my auctions views.",
            reloadMsg = "Changing the Auction House reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinAuctionHouse = v
            end,
        },
        {
            key   = "macros",
            title = "Macros",
            desc  = "The macro editor: tabs, icon grid, text well, and buttons.",
            reloadMsg = "Changing the Macros reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinMacros = v
            end,
        },
        {
            key   = "settings",
            title = "Options Panel",
            desc  = "Blizzard's options window chrome: frame, tabs, search, and category rail.",
            reloadMsg = "Changing the Options Panel reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinSettings = v
            end,
        },
        {
            key   = "addonlist",
            title = "AddOn List",
            desc  = "The addon manager: list rows, checkboxes, and buttons.",
            reloadMsg = "Changing the AddOn List reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinAddonList = v
            end,
        },
        {
            key   = "craftorders",
            title = "Crafting Orders",
            desc  = "The customer crafting orders window: browse, order form, and my orders.",
            reloadMsg = "Changing the Crafting Orders reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinCraftOrders = v
            end,
        },
        {
            key   = "trainer",
            title = "Trainer",
            desc  = "The class and profession trainer window: skill list, train button, and cost display.",
            reloadMsg = "Changing the Trainer reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinTrainer = v
            end,
        },
        {
            key   = "gossip",
            title = "Gossip",
            desc  = "The NPC dialog window: greeting text, gossip and quest options, and goodbye button.",
            reloadMsg = "Changing the Gossip reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinGossip = v
            end,
        },
        {
            key   = "quest",
            title = "Quest",
            desc  = "The NPC quest window: quest detail, progress, and reward panels plus the multi-quest greeting list.",
            reloadMsg = "Changing the Quest reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinQuest = v
            end,
        },
        {
            key   = "inspectrecipe",
            title = "Inspect Recipe",
            desc  = "The recipe preview window shown from a linked recipe or an inspected crafter.",
            reloadMsg = "Changing the Inspect Recipe reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinInspectRecipe = v
            end,
        },
        {
            key   = "delves",
            title = "Delves Companion",
            desc  = "Brann's configuration window: role and trinket slots, abilities, and the ability list.",
            reloadMsg = "Changing the Delves Companion reskin requires a UI reload to fully swap between Blizzard and Ellesmere styles.",
            setEnabled = function(v)
                if not EllesmereUIDB then EllesmereUIDB = {} end
                EllesmereUIDB.reskinDelves = v
            end,
        },
    }

    local function WSGetStyle(win)
        return EllesmereUI.GetBlizzWindowStyle(win.key)
    end

    -- Applies a style to one window. Returns true when the change crosses the
    -- on/off boundary (= needs a reload). suppressPopup lets Apply to All show
    -- one popup for the whole batch instead of one per window.
    local function WSSetStyle(win, style, suppressPopup)
        local old = WSGetStyle(win)
        if old == style then return false end
        if not EllesmereUIDB then EllesmereUIDB = {} end
        win.setEnabled(style ~= "off")
        if style ~= "off" then
            -- Remember which skin set this window uses; kept while "off" so
            -- re-enabling restores the same pick.
            if not EllesmereUIDB.blizzWindowSkinStyles then EllesmereUIDB.blizzWindowSkinStyles = {} end
            EllesmereUIDB.blizzWindowSkinStyles[win.key] = style
        end
        local crossed = (old == "off") ~= (style == "off")
        -- eui<->modern applies live (shell backdrops swap in place).
        if EllesmereUI._WSkinRefreshStyles then EllesmereUI._WSkinRefreshStyles() end
        if crossed and not suppressPopup then
            WSReloadPopup(win.reloadMsg)
        end
        return crossed
    end

    -- One expandable card: custom header (mini-window glyph + title + style
    -- dropdown + chevron) over a shared card background, with the window's
    -- rows below when expanded. Returns the new y cursor.
    local function BuildWindowCard(parent, y, win)
        local PP = EllesmereUI.PanelPP
        local EG = EllesmereUI.ELLESMERE_GREEN
        local L  = EllesmereUI.L
        local hasSettings = win.buildContent ~= nil
        local expanded = hasSettings and _wsExpanded[win.key]
        local cardTop = y
        local brd  -- whole-card border, created with the bg below (hover closure)

        -- Explicit size + single TOPLEFT anchor (the widget contract): inline
        -- search re-anchors and restores direct children through their FIRST
        -- point only, so a frame that gets its width from a second point
        -- collapses to zero width the first time a search is cleared.
        local cardW = parent:GetWidth() - (EllesmereUI.CONTENT_PAD - WS_CARD_INSET) * 2
        local hdr = CreateFrame("Button", nil, parent)
        PP.Size(hdr, cardW, WS_HEADER_H)
        PP.Point(hdr, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD - WS_CARD_INSET, y)
        hdr:SetFrameLevel(parent:GetFrameLevel() + 3)

        -- Search metadata: the header acts as its own section, so searching a
        -- window's title or description returns the card (style dropdown and
        -- all) as a result. Deep links are unaffected: they match the exact
        -- section names created inside buildContent, never this joined string.
        local searchName = win.title .. " " .. (win.desc or "")
        hdr._isSectionHeader = true
        hdr._sectionName = searchName
        local searchNameLoc = L(win.title) .. " " .. L(win.desc or "")
        if searchNameLoc ~= searchName then hdr._sectionNameLoc = searchNameLoc end

        -- Global (sidebar) search: the card header never goes through
        -- SectionHeader, so the index would otherwise have no entry for it --
        -- searching a window's title/description found it inline but not in
        -- the sidebar results. Register it with the same title + description
        -- keywords the inline pseudo-section matches (title as the display
        -- label, description via the tooltip field, which the fuzzy scorer
        -- also searches). section = the exact joined string stamped above, so
        -- a jump scrolls to and glows this header; the page's
        -- NavigateToElementSettings pre-hook expands the cards first.
        if EllesmereUI._RegisterSearchEntry then
            local titleLoc = L(win.title)
            local descSearch = win.desc or ""
            local descLoc = L(win.desc or "")
            if descLoc ~= descSearch then descSearch = descSearch .. " " .. descLoc end
            EllesmereUI._RegisterSearchEntry(win.title,
                titleLoc ~= win.title and titleLoc or nil,
                descSearch,
                EllesmereUI._buildingModule, EllesmereUI._buildingPage,
                searchName, nil, nil, true)
        end

        -- Hover wash (transparent when idle; the card bg below provides the fill)
        local hbg = EllesmereUI.SolidTex(hdr, "BACKGROUND", 0, 0, 0, 0)
        hbg:SetAllPoints()

        -- Procedural mini-window glyph: a tiny framed "window" with a title
        -- bar. The bar lights up in accent while the reskin is enabled, but
        -- only on cards that actually have settings.
        local glyph = CreateFrame("Frame", nil, hdr)
        PP.Size(glyph, 22, 16)
        PP.Point(glyph, "LEFT", hdr, "LEFT", 16, 0)
        local glyphBrd = EllesmereUI.MakeBorder(glyph, 1, 1, 1, 0.35, PP)
        local glyphBar = glyph:CreateTexture(nil, "ARTWORK")
        glyphBar:SetHeight(4)
        PP.Point(glyphBar, "TOPLEFT", glyph, "TOPLEFT", 1, -1)
        PP.Point(glyphBar, "TOPRIGHT", glyph, "TOPRIGHT", -1, -1)
        if glyphBar.SetSnapToPixelGrid then glyphBar:SetSnapToPixelGrid(false); glyphBar:SetTexelSnappingBias(0) end

        local title = EllesmereUI.MakeFont(hdr, 14, nil, 1, 1, 1, 0.9)
        PP.Point(title, "TOPLEFT", hdr, "TOPLEFT", 50, -12)
        title:SetText(L(win.title))

        local desc = EllesmereUI.MakeFont(hdr, 11, nil, 1, 1, 1, 0.42)
        PP.Point(desc, "TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        desc:SetWidth(590)
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(false)
        desc:SetText(L(win.desc))

        -- Expand chevron only on cards that actually have settings; cards
        -- without any are not expandable at all.
        local chev
        if hasSettings then
            chev = hdr:CreateTexture(nil, "OVERLAY")
            PP.Size(chev, 16, 16)
            PP.Point(chev, "RIGHT", hdr, "RIGHT", -16, 0)
            chev:SetTexture(expanded and WS_ARROW_UP or WS_ARROW_DOWN)
            chev:SetAlpha(0.45)
            if expanded then chev:SetVertexColor(EG.r, EG.g, EG.b) end
        end

        -- Style dropdown: pick EllesmereUI / Modern / Blizz Default for this
        -- window without expanding the card.
        local dd = EllesmereUI.BuildDropdownControl(hdr, 148, hdr:GetFrameLevel() + 2,
            WS_STYLE_VALUES, WS_STYLE_ORDER,
            function() return WSGetStyle(win) end,
            function(v)
                WSSetStyle(win, v)
                EllesmereUI:RefreshPage()
            end)
        PP.Point(dd, "RIGHT", hdr, "RIGHT", -44, 0)

        local strip  -- accent strip on the header's left edge (created with bg)
        local function RefreshCardState()
            local on = WSGetStyle(win) ~= "off"
            glyphBrd:SetColor(1, 1, 1, on and 0.4 or 0.2)
            -- Glyph title bar: accent is reserved for cards that have
            -- settings; windows without any keep a gray bar darker than the
            -- glyph border.
            if not hasSettings then
                glyphBar:SetColorTexture(1, 1, 1, 0.12)
            elseif on then
                glyphBar:SetColorTexture(EG.r, EG.g, EG.b, 0.85)
            else
                glyphBar:SetColorTexture(1, 1, 1, 0.2)
            end
            -- Accent edge marks cards that actually have settings; windows
            -- without any keep the faint neutral strip.
            if strip then
                if hasSettings then
                    strip:SetColorTexture(EG.r, EG.g, EG.b, 0.7)
                else
                    strip:SetColorTexture(1, 1, 1, 0.10)
                end
            end
            if dd._refreshLabel then dd._refreshLabel() end
        end

        local function ApplyHeaderHover()
            hbg:SetColorTexture(1, 1, 1, 0.05)
            title:SetAlpha(1)
            chev:SetAlpha(0.85)
            if brd then brd:SetColor(1, 1, 1, 0.22) end
        end
        local function ClearHeaderHover()
            -- Moving between the header and its dropdown fires OnLeave first;
            -- keep the row highlight while the pointer is still inside the header.
            if hdr:IsMouseOver() then return end
            hbg:SetColorTexture(0, 0, 0, 0)
            title:SetAlpha(0.9)
            chev:SetAlpha(0.45)
            if brd then brd:SetColor(1, 1, 1, expanded and 0.16 or 0.12) end
        end
        -- Cards without settings are inert: no hover wash, no click-to-expand.
        -- Their dropdown still works on its own.
        if hasSettings then
            hdr:SetScript("OnEnter", ApplyHeaderHover)
            hdr:SetScript("OnLeave", ClearHeaderHover)
            -- The dropdown keeps its own hover scripts; hook (not replace) so the
            -- full row highlight also holds while the pointer is on the dropdown.
            dd:HookScript("OnEnter", ApplyHeaderHover)
            dd:HookScript("OnLeave", ClearHeaderHover)
            hdr:SetScript("OnClick", function()
                _wsExpanded[win.key] = not _wsExpanded[win.key]
                EllesmereUI:RefreshPage(true)
            end)
        end

        y = y - WS_HEADER_H

        if expanded then
            -- Divider between the header and the card's settings
            local div = hdr:CreateTexture(nil, "ARTWORK")
            div:SetColorTexture(1, 1, 1, 0.07)
            div:SetHeight(1)
            PP.Point(div, "BOTTOMLEFT", hdr, "BOTTOMLEFT", 1, 0)
            PP.Point(div, "BOTTOMRIGHT", hdr, "BOTTOMRIGHT", -1, 0)
            PP.DisablePixelSnap(div)

            y = y - 8
            y = win.buildContent(parent, y)
            y = y - 8
        end

        -- Card background + border spanning the header and any expanded content.
        -- Child of the header, NOT the page wrapper: the inline search walks
        -- direct wrapper children, and as a header child the bg is never
        -- collected as a row, follows the header wherever the search re-flows
        -- it, and hides/shows with it for free. Explicitly sized because the
        -- header's own rect is the only anchor left.
        local bg = CreateFrame("Frame", nil, hdr)
        bg:SetFrameLevel(parent:GetFrameLevel())
        PP.Size(bg, cardW, cardTop - y)
        PP.Point(bg, "TOPLEFT", hdr, "TOPLEFT", 0, 0)
        local fill = EllesmereUI.SolidTex(bg, "BACKGROUND", 0.06, 0.08, 0.10, 0.5)
        fill:SetAllPoints()
        brd = EllesmereUI.MakeBorder(bg, 1, 1, 1, expanded and 0.16 or 0.12, PP)

        -- Header-height only: the strip marks the header, never the expanded
        -- settings block below it.
        strip = bg:CreateTexture(nil, "ARTWORK")
        strip:SetWidth(2)
        PP.Point(strip, "TOPLEFT", hdr, "TOPLEFT", 1, -1)
        PP.Point(strip, "BOTTOMLEFT", hdr, "BOTTOMLEFT", 1, 1)
        if strip.SetSnapToPixelGrid then strip:SetSnapToPixelGrid(false); strip:SetTexelSnappingBias(0) end

        EllesmereUI.RegisterWidgetRefresh(RefreshCardState)
        RefreshCardState()

        return y - WS_CARD_GAP
    end

    -- Per-profile master kill switch (the ONLY per-profile setting in this
    -- section): profile-root key disableWindowSkins, resolved live by
    -- EllesmereUI.BlizzWindowSkinsKilled(). Skins install at load, so every
    -- toggle shows the reload popup.
    local function WSKillSwitchSet(disabled)
        local prof = EllesmereUI.GetActiveProfileData and EllesmereUI.GetActiveProfileData()
        if not prof then return end
        prof.disableWindowSkins = disabled and true or nil
        -- Structural change (settings <-> hero takeover): force a rebuild,
        -- a plain refresh only re-reads widget values on the cached page.
        EllesmereUI:RefreshPage(true)
        WSReloadPopup(disabled
            and "Window skins are now disabled for this profile. A UI reload is required to restore the stock Blizzard windows."
            or "Window skins are now enabled for this profile. A UI reload is required to apply them.")
    end

    -- Feature hero shown INSTEAD of the page content while window skins are
    -- disabled for this profile: the intro popup's art (three mini windows,
    -- eyebrow, bullets) rebuilt inline, with one big Enable button.
    local function BuildWindowSkinsDisabledHero(parent, yOffset)
        local PP = EllesmereUI.PanelPP
        local EG = EllesmereUI.ELLESMERE_GREEN
        local L  = EllesmereUI.L
        local MakeBorder = EllesmereUI.MakeBorder
        local FONT = EllesmereUI._font or "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.ttf"

        local HERO_H = 470
        local host = CreateFrame("Frame", nil, parent)
        PP.Size(host, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, HERO_H)
        PP.Point(host, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, yOffset - 24)

        -- Three mini Blizzard "windows" with colored title bars (the intro
        -- popup's header visual): center one scaled up with a resize grip.
        local CARD_W, CARD_H, CARD_GAP = 124, 52, 14
        local titleColors = {
            { EG.r, EG.g, EG.b },
            { 0.25, 0.50, 0.90 },
            { 0.64, 0.39, 0.93 },
        }
        for i = 1, 3 do
            local isCenter = (i == 2)
            local w = CARD_W
            local ch = isCenter and (CARD_H + 10) or CARD_H
            local card = CreateFrame("Frame", nil, host)
            card:SetFrameLevel(host:GetFrameLevel() + 1)
            PP.Size(card, w, ch)
            PP.Point(card, "CENTER", host, "TOP", (i - 2) * (CARD_W + CARD_GAP), -64)
            local cbg = card:CreateTexture(nil, "BACKGROUND")
            cbg:SetAllPoints()
            cbg:SetColorTexture(0.12, 0.13, 0.15, 1)
            local c = titleColors[i]
            local bar = card:CreateTexture(nil, "ARTWORK")
            bar:SetColorTexture(c[1], c[2], c[3], isCenter and 0.95 or 0.75)
            bar:SetHeight(8)
            PP.Point(bar, "TOPLEFT", card, "TOPLEFT", 1, -1)
            PP.Point(bar, "TOPRIGHT", card, "TOPRIGHT", -1, -1)
            if bar.SetSnapToPixelGrid then bar:SetSnapToPixelGrid(false); bar:SetTexelSnappingBias(0) end
            local dot = card:CreateTexture(nil, "OVERLAY")
            dot:SetColorTexture(0, 0, 0, 0.4)
            PP.Size(dot, 4, 4)
            PP.Point(dot, "RIGHT", bar, "RIGHT", -3, 0)
            local l1 = card:CreateTexture(nil, "ARTWORK")
            l1:SetColorTexture(1, 1, 1, isCenter and 0.42 or 0.32)
            PP.Size(l1, w - 26, 5)
            PP.Point(l1, "TOPLEFT", card, "TOPLEFT", 13, -18)
            local l2 = card:CreateTexture(nil, "ARTWORK")
            l2:SetColorTexture(1, 1, 1, 0.18)
            PP.Size(l2, w - 46, 5)
            PP.Point(l2, "TOPLEFT", l1, "BOTTOMLEFT", 0, -7)
            if isCenter then
                local l3 = card:CreateTexture(nil, "ARTWORK")
                l3:SetColorTexture(1, 1, 1, 0.14)
                PP.Size(l3, w - 66, 5)
                PP.Point(l3, "TOPLEFT", l2, "BOTTOMLEFT", 0, -7)
                local grip = card:CreateTexture(nil, "OVERLAY")
                grip:SetColorTexture(EG.r, EG.g, EG.b, 0.85)
                PP.Size(grip, 5, 5)
                PP.Point(grip, "BOTTOMRIGHT", card, "BOTTOMRIGHT", -2, 2)
            end
            MakeBorder(card, 1, 1, 1, isCenter and 0.16 or 0.10, PP)
        end

        local eyebrow = host:CreateFontString(nil, "OVERLAY")
        eyebrow:SetFont(FONT, 13, "")
        eyebrow:SetTextColor(EG.r, EG.g, EG.b, 0.9)
        PP.Point(eyebrow, "TOP", host, "TOP", 0, -122)
        eyebrow:SetText(L("EUI FEATURE"))

        local title = host:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 25, "")
        title:SetTextColor(1, 1, 1, 1)
        PP.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
        title:SetText(L("Blizzard Window Skinning"))

        local desc = host:CreateFontString(nil, "OVERLAY")
        desc:SetFont(FONT, 15, "")
        desc:SetTextColor(1, 1, 1, 0.5)
        desc:SetWidth(430)
        desc:SetJustifyH("CENTER")
        desc:SetWordWrap(true)
        PP.Point(desc, "TOP", title, "BOTTOM", 0, -12)
        desc:SetText(L("Blizzard's windows match the EllesmereUI theme with a WoW 2.0 Dark Theme, from the Dungeon Journal to the Auction House and beyond."))

        local BULLETS = {
            "Every major Blizzard window themed to match EUI",
            "Recolor the theme to any color and opacity you like",
            "Scale any window larger or smaller with Shifter",
        }
        local prev
        for i, text in ipairs(BULLETS) do
            local bl = host:CreateFontString(nil, "OVERLAY")
            bl:SetFont(FONT, 14, "")
            bl:SetTextColor(1, 1, 1, 0.72)
            bl:SetJustifyH("LEFT")
            if i == 1 then
                PP.Point(bl, "TOP", host, "TOP", -20, -252)
                bl:SetPoint("LEFT", host, "CENTER", -160, 0)
            else
                PP.Point(bl, "TOPLEFT", prev, "BOTTOMLEFT", 0, -10)
            end
            bl:SetText(L(text))
            local bdot = host:CreateTexture(nil, "OVERLAY")
            bdot:SetColorTexture(EG.r, EG.g, EG.b, 1)
            PP.Size(bdot, 5, 5)
            PP.Point(bdot, "RIGHT", bl, "LEFT", -10, 0)
            prev = bl
        end

        local enableBtn = CreateFrame("Button", nil, host)
        PP.Size(enableBtn, 220, 40)
        PP.Point(enableBtn, "TOP", host, "TOP", 0, -344)
        enableBtn:SetFrameLevel(host:GetFrameLevel() + 2)
        EllesmereUI.MakeStyledButton(enableBtn, "Enable Window Skins", 15,
            EllesmereUI.WB_COLOURS, function() WSKillSwitchSet(false) end)

        local footnote = host:CreateFontString(nil, "OVERLAY")
        footnote:SetFont(FONT, 12, "")
        footnote:SetTextColor(1, 1, 1, 0.35)
        PP.Point(footnote, "TOP", enableBtn, "BOTTOM", 0, -12)
        footnote:SetText(L("Window skins are currently disabled for this profile."))

        -- Builders return the page's total HEIGHT (positive), same as the
        -- normal page's math.abs(y) tail.
        return math.abs(yOffset - 24 - HERO_H)
    end

    local function BuildWindowSkinsPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local PP = EllesmereUI.PanelPP
        local L  = EllesmereUI.L
        local y = yOffset
        local _, h

        parent._showRowDivider = true

        -- Per-profile kill switch takeover: while window skins are disabled
        -- for this profile, hide every setting and show the feature hero.
        if EllesmereUI.BlizzWindowSkinsKilled and EllesmereUI.BlizzWindowSkinsKilled() then
            return BuildWindowSkinsDisabledHero(parent, yOffset)
        end

        _, h = W:Spacer(parent, y, 14);  y = y - h

        -- Hosted on a sized frame (not a raw region on the wrapper) so the
        -- inline search hides it while filtering and restores it on clear;
        -- regions are invisible to the search and would float over results.
        local introHost = CreateFrame("Frame", nil, parent)
        PP.Size(introHost, parent:GetWidth() - EllesmereUI.CONTENT_PAD * 2, 20)
        PP.Point(introHost, "TOPLEFT", parent, "TOPLEFT", EllesmereUI.CONTENT_PAD, y)
        local intro = EllesmereUI.MakeFont(introHost, 13, nil, 1, 1, 1, 0.5)
        PP.Point(intro, "TOP", introHost, "TOP", 0, 0)
        intro:SetText(L("Pick a style for all reskinned Blizzard windows."))

        -- Per-profile master switch (top right; the only per-profile setting
        -- in this section). One step below Blizz Default: no-ops the whole
        -- window engine + CharacterSheet/Inspect + LFG skinning. Reload-bound.
        local disBtn = CreateFrame("Button", nil, introHost)
        PP.Size(disBtn, 160, 24)
        PP.Point(disBtn, "RIGHT", introHost, "RIGHT", 0, 0)
        disBtn:SetFrameLevel(introHost:GetFrameLevel() + 3)
        EllesmereUI.MakeStyledButton(disBtn, "Disable Window Skins", 11,
            EllesmereUI.WB_COLOURS, function() WSKillSwitchSet(true) end)
        disBtn:HookScript("OnEnter", function(s)
            EllesmereUI.ShowWidgetTooltip(s, L("Turns off ALL window skinning for this profile. Requires a reload."))
        end)
        disBtn:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

        y = y - 28

        -- Set-all row: pick a style, then push it to every window below. The
        -- swatch + cog edit the GLOBAL Modern background (windows without a
        -- per-window override follow it).
        local allDD = EllesmereUI.BuildDropdownControl(parent, 170, parent:GetFrameLevel() + 3,
            WS_STYLE_VALUES, WS_STYLE_ORDER,
            function() return _wsApplyAllStyle end,
            function(v)
                _wsApplyAllStyle = v
                EllesmereUI:RefreshPage()
            end)
        PP.Point(allDD, "TOPLEFT", parent, "TOP", -115, y)
        allDD._ttText = "Style to apply to every window below."
        AttachModernSwatch(parent, allDD)

        local applyBtn = CreateFrame("Button", nil, parent)
        PP.Size(applyBtn, 110, 30)
        PP.Point(applyBtn, "LEFT", allDD, "RIGHT", 10, 0)
        applyBtn:SetFrameLevel(parent:GetFrameLevel() + 3)
        EllesmereUI.MakeStyledButton(applyBtn, "Apply to All", 12, EllesmereUI.WB_COLOURS, function()
            local crossed = false
            for _, win in ipairs(WINDOWS) do
                if WSSetStyle(win, _wsApplyAllStyle, true) then crossed = true end
            end
            EllesmereUI:RefreshPage()
            if crossed then
                WSReloadPopup("Changing window skin styles requires a UI reload to fully apply.")
            end
        end)
        y = y - 30 - 26

        -- GLOBAL OPTIONS: look settings shared by every reskinned window.
        _, h = W:SectionHeader(parent, "GLOBAL OPTIONS", y); y = y - h

        local gRow1
        gRow1, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Accent Bar",
              tooltip = "Accent bar on the active tab of reskinned windows.",
              getValue = function()
                  local c = WSLook("blizzWinAccentBar")
                  return not (c and c.enabled == false)
              end,
              setValue = function(v)
                  WSLookSet("blizzWinAccentBar", "enabled", v and true or false)
              end },
            { type = "slider", text = "Bar Fill Opacity",
              min = 10, max = 100, step = 1,
              getValue = function()
                  local c = WSLook("blizzWinBarFill")
                  return math.floor(((c and c.alpha) or 0.95) * 100 + 0.5)
              end,
              setValue = function(v) WSLookSet("blizzWinBarFill", "alpha", v / 100) end })
        AttachLookSwatches(gRow1._leftRegion, gRow1, "blizzWinAccentBar")
        AttachLookSwatches(gRow1._rightRegion, gRow1, "blizzWinBarFill")
        y = y - h

        _, h = W:DualRow(parent, y,
            { type = "multiSwatch", text = "Link Color",
              swatches = {
                  { tooltip = "Accent Color",
                    getValue = function()
                        return EllesmereUI.ResolveActiveAccent()
                    end,
                    setValue = function() end,
                    onClick = function()
                        WSLookSet("blizzWinLinks", "useCustom", false)
                        EllesmereUI:RefreshPage()
                    end,
                    refreshAlpha = function()
                        local c = WSLook("blizzWinLinks")
                        return (c and c.useCustom) and 0.3 or 1
                    end },
                  { tooltip = "Custom Color",
                    getValue = function()
                        local c = WSLook("blizzWinLinks")
                        local col = c and c.color
                        if col then return col.r or 1, col.g or 1, col.b or 1 end
                        return 1, 1, 1
                    end,
                    setValue = function(r, g, b)
                        WSLookSet("blizzWinLinks", "color", { r = r, g = g, b = b })
                        WSLookSet("blizzWinLinks", "useCustom", true)
                        EllesmereUI:RefreshPage()
                    end,
                    onClick = function(self)
                        local c = WSLook("blizzWinLinks")
                        if not (c and c.useCustom) then
                            WSLookSet("blizzWinLinks", "useCustom", true)
                            EllesmereUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function()
                        local c = WSLook("blizzWinLinks")
                        return (c and c.useCustom) and 1 or 0.3
                    end },
              } },
            { type = "label", text = "" })
        y = y - h

        -- Breathing room between the global settings and the window cards.
        y = y - 30

        for _, win in ipairs(WINDOWS) do
            y = BuildWindowCard(parent, y, win)
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
              -- DependentSetValue: everything below Row 1 is hidden while the
              -- bar is off; the flip forces the full rebuild.
              setValue = EllesmereUI.DependentSetValue(
                  function() return EDR_Cfg("enabled") == true end,
                  function(v) EDR_Set("enabled", v); EDR_Rebuild() end) },
            { type = "toggle", text = "Hide in Combat",
              disabled = function() return EDR_Cfg("enabled") ~= true end,
              disabledTooltip = "Dragon Riding Bar",
              getValue = function() return EDR_Cfg("hideInCombat") == true end,
              setValue = function(v) EDR_Set("hideInCombat", v); EDR_Rebuild() end }
        ); y = y - h

        -- Everything below Row 1 (the rest of GENERAL plus the LAYOUT and
        -- SPEED BAR sections) is HIDDEN entirely while the bar is off.
        if EDR_Cfg("enabled") == true then
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Width", min = 80, max = 600, step = 1,
              getValue = function() return EDR_Cfg("width") end,
              setValue = function(v) EDR_Set("width", v); EDR_Rebuild() end },
            { type = "slider", pixel = true, text = "Element Spacing", min = 0, max = 12, step = 1,
              getValue = function() return EDR_Cfg("gap") end,
              setValue = function(v) EDR_Set("gap", v); EDR_Rebuild() end }
        ); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", pixel = true, text = "Stack Spacing", min = 0, max = 10, step = 1,
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
        end   -- close Dragon Riding hidden-while-disabled gate

        -- The wrapper is SetAllPoints-anchored, so SetHeight on it is inert;
        -- return the measured height so the scroll range is correct.
        return math.abs(y)
    end

    EllesmereUI:RegisterModule("EllesmereUIBlizzardSkin", {
        title       = "Blizz UI Enhanced",
        description = "Themed Blizzard frames: window skins, tooltips, menus, popups, Dragon Riding HUD.",
        searchTerms = "blizzard skin character sheet tooltip menu popup dragon riding skyriding window skins lfg group finder premade queue pause game menu great vault inspect collections mounts pets toys spellbook talents adventure guide encounter journal professions guild communities calendar achievements mail catalyst gem socket micro menu modern delves companion brann",
        pages       = { PAGE_WINDOWSKINS, PAGE_TOOLTIPS, PAGE_DRAGONRIDING },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_WINDOWSKINS then
                return BuildWindowSkinsPage(pageName, parent, yOffset)
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
            -- Per-profile master kill switch: reset re-enables skins for the
            -- ACTIVE profile (other profiles keep their own choice).
            do
                local prof = EllesmereUI.GetActiveProfileData and EllesmereUI.GetActiveProfileData()
                if prof then prof.disableWindowSkins = nil end
            end
            if EllesmereUIDB then
                -- NOTE: these account-global keys also travel in profile
                -- exports via BLIZZ_SKIN_GLOBAL_KEYS in EllesmereUI_Profiles.lua
                -- (the "Window & Tooltip Skins" include). A new account-global
                -- setting on the Window Skins or Tooltips, Menus & Popups tab
                -- must be added to BOTH lists.
                EllesmereUIDB.customTooltips = nil
                EllesmereUIDB.reskinPopupsMenus = nil
                EllesmereUIDB.accentReskinElements = nil
                EllesmereUIDB.tooltipPlayerTitles = nil
                EllesmereUIDB.tooltipFontScale = nil
                EllesmereUIDB.tooltipMythicScore = nil
                EllesmereUIDB.tooltipAnchorCursor = nil
                EllesmereUIDB.tooltipCursorPosition = nil
                EllesmereUIDB.tooltipCursorOffsetX = nil
                EllesmereUIDB.tooltipCursorOffsetY = nil
                EllesmereUIDB.tooltipFixedPos = nil  -- stale key from the account-global build
                -- Per-profile fixed tooltip position: clearing it re-seeds from
                -- Blizzard's CURRENT Edit Mode spot on the next tooltip show.
                do
                    local prof = EllesmereUI.GetActiveProfileData and EllesmereUI.GetActiveProfileData()
                    if prof then prof.tooltipFixedPos = nil end
                end
                EllesmereUIDB.uberTooltips = nil
                EllesmereUIDB.uberTooltipsManual = nil
                EllesmereUIDB.tooltipHideHealthStrip = nil
                EllesmereUIDB.showItemMaxStacks = nil
                EllesmereUIDB.itemStackModifier = nil
                EllesmereUIDB.tooltipShowGuildRank = nil
                EllesmereUIDB.tooltipShowMount = nil
                EllesmereUIDB.tooltipShowTarget = nil
                EllesmereUIDB.reskinQueuePopup = nil
                EllesmereUIDB.resurrectAcceptGlow = nil
                -- Clear any glow on a currently visible popup (the setting
                -- just went nil = off; hooks stay installed but inert).
                if EllesmereUI._EnsureResurrectGlow then EllesmereUI._EnsureResurrectGlow() end
                EllesmereUIDB.reskinGameMenu = nil
                EllesmereUIDB.popupMenuButtonBackgroundColor=nil
                EllesmereUIDB.popupMenuButtonTextColorMode=nil
                EllesmereUIDB.popupMenuButtonTextColor=nil
                for _,prefix in ipairs({"popupMenu","popupMenuButton","tooltip"}) do
                    for _,suffix in ipairs({"BorderTexture","BorderThickness","BorderColor","BorderColorMode","BorderOpacity","BorderOffsetX","BorderOffsetY","BorderShiftX","BorderShiftY","BorderBehind"}) do
                        EllesmereUIDB[prefix..suffix]=nil
                    end
                end
                -- Legacy numeric key the tooltip Border Size still falls back
                -- to when tooltipBorderThickness is unset.
                EllesmereUIDB.tooltipBorderSize = nil
                EllesmereUIDB.reskinGreatVault = nil
                EllesmereUIDB.reskinLFGMenu = nil
                EllesmereUIDB.showQueueTimer = nil
                EllesmereUIDB.blizzWindowSkinStyles = nil
                EllesmereUIDB.blizzWindowModernBG = nil
                EllesmereUIDB.blizzWindowModernDefault = nil
                EllesmereUIDB.blizzWinAccentBar = nil
                EllesmereUIDB.blizzWinBarFill = nil
                EllesmereUIDB.blizzWinLinks = nil
                EllesmereUIDB.reskinCollections = nil
                EllesmereUIDB.reskinPlayerSpells = nil
                EllesmereUIDB.reskinAdventureGuide = nil
                EllesmereUIDB.reskinProfessionsBook = nil
                EllesmereUIDB.reskinGuild = nil
                EllesmereUIDB.reskinCalendar = nil
                EllesmereUIDB.reskinAchievements = nil
                EllesmereUIDB.reskinMail = nil
                EllesmereUIDB.reskinCatalyst = nil
                EllesmereUIDB.reskinSocket = nil
                EllesmereUIDB.reskinMicroMenu = nil
                EllesmereUIDB.reskinHousing = nil
                EllesmereUIDB.reskinProfessions = nil
                EllesmereUIDB.reskinWorldMap = nil
                EllesmereUIDB.reskinDressUp = nil
                EllesmereUIDB.reskinTransmog = nil
                EllesmereUIDB.reskinMerchant = nil
                EllesmereUIDB.reskinAuctionHouse = nil
                EllesmereUIDB.reskinMacros = nil
                EllesmereUIDB.reskinSettings = nil
                EllesmereUIDB.reskinAddonList = nil
                EllesmereUIDB.reskinCraftOrders = nil
                EllesmereUIDB.reskinTrainer = nil
                EllesmereUIDB.reskinGossip = nil
                EllesmereUIDB.reskinQuest = nil
                EllesmereUIDB.reskinInspectRecipe = nil
                EllesmereUIDB.reskinDelves = nil
                EllesmereUIDB.lfgRememberRoles = nil
                EllesmereUIDB.lfgSavedRoles = nil
                EllesmereUIDB.showMythicRating = nil
                EllesmereUIDB.showPvpItemLevel = nil
                EllesmereUIDB.flyoutItemLevels = nil
                EllesmereUIDB.statCategoryColors = nil
                EllesmereUIDB.statSectionsOrder = nil
                EllesmereUIDB.charSheetCollapsedSections = nil
                EllesmereUIDB.characterFramePos = nil
                EllesmereUIDB.friendsFramePos = nil
            end
            if EllesmereUI._applyTooltipCursorAnchor then EllesmereUI._applyTooltipCursorAnchor() end
            if EllesmereUI._applyTooltipFixedAnchor then EllesmereUI._applyTooltipFixedAnchor() end
            if EllesmereUI._applyTooltipHealthStrip then EllesmereUI._applyTooltipHealthStrip() end
        end,
    })

    -- Deep links (What's New, search) into the Window Skins page target rows
    -- that only exist while a card is expanded. Pre-hook: expand every card and
    -- drop the page cache so the nav's SelectPage cold-builds with all rows
    -- present before it resolves the section/highlight.
    local origNav = EllesmereUI.NavigateToElementSettings
    if origNav then
        function EllesmereUI:NavigateToElementSettings(moduleName, pageName, sectionName, preSelectFn, highlightText)
            if moduleName == "EllesmereUIBlizzardSkin" and pageName == PAGE_WINDOWSKINS
               and (sectionName or highlightText) then
                local changed = false
                for _, win in ipairs(WINDOWS) do
                    if not _wsExpanded[win.key] then
                        _wsExpanded[win.key] = true
                        changed = true
                    end
                end
                if changed and EllesmereUI.InvalidatePageCache then
                    EllesmereUI:InvalidatePageCache()
                end
            end
            return origNav(self, moduleName, pageName, sectionName, preSelectFn, highlightText)
        end
    end

    SLASH_EBSK1 = "/ebsk"
    SlashCmdList.EBSK = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIBlizzardSkin")
    end
end)
