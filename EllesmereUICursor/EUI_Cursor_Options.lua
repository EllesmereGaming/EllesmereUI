-------------------------------------------------------------------------------
--  EUI_CursorLite_Options.lua
--  Registers the Cursor Lite module with EllesmereUI
--  Pure UI migration – all get/set calls go to the addon's AceDB profile.
--  Does NOT touch cursor tracking logic.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_CURSOR     = "Cursor Circle"
local PAGE_UNLOCK     = "Unlock Mode"

local SECTION_APPEARANCE   = "CURSOR"
local SECTION_GCD          = "GLOBAL COOLDOWN"
local SECTION_CAST         = "CAST BAR"

local strupper, strgsub, strmatch, strsub = string.upper, string.gsub, string.match, string.sub
local floor = math.floor

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    local PP = EllesmereUI.PP

    ---------------------------------------------------------------------------
    --  DB helpers
    ---------------------------------------------------------------------------
    local db

    C_Timer.After(0, function()
        db = _G._ECL_AceDB
    end)

    local function DB()
        if not db then db = _G._ECL_AceDB end
        return db and db.profile
    end

    local function GCD_DB()
        local p = DB()
        if not p then return {} end
        if not p.gcd then p.gcd = {} end
        return p.gcd
    end

    local function Cast_DB()
        local p = DB()
        if not p then return {} end
        if not p.castCircle then p.castCircle = {} end
        return p.castCircle
    end

    ---------------------------------------------------------------------------
    --  Hex color helpers
    ---------------------------------------------------------------------------
    local function HexToRGB(hex)
        hex = strupper(strgsub(hex or "0CD29D", "#", ""))
        if not strmatch(hex, "^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$") then
            hex = "0CD29D"
        end
        return tonumber(strsub(hex, 1, 2), 16) / 255,
               tonumber(strsub(hex, 3, 4), 16) / 255,
               tonumber(strsub(hex, 5, 6), 16) / 255
    end

    local function RGBToHex(r, g, b)
        return string.format("%02X%02X%02X",
            floor(r * 255 + 0.5),
            floor(g * 255 + 0.5),
            floor(b * 255 + 0.5))
    end

    ---------------------------------------------------------------------------
    --  Refresh helpers
    ---------------------------------------------------------------------------
    local function RefreshAddon()
        if _G._ECL_Apply then _G._ECL_Apply() end
    end

    local function RefreshGCD()
        if _G._ECL_ApplyGCDCircle then _G._ECL_ApplyGCDCircle() end
        if _G._ECL_RegisterUnlock then _G._ECL_RegisterUnlock() end
    end

    local function RefreshCast()
        if _G._ECL_ApplyCastCircle then _G._ECL_ApplyCastCircle() end
        if _G._ECL_RegisterUnlock then _G._ECL_RegisterUnlock() end
    end

    ---------------------------------------------------------------------------
    --  MakeCogBtn helper
    ---------------------------------------------------------------------------
    local function MakeCogBtn(rgn, showFn, anchorTo, iconPath)
        local cogBtn = CreateFrame("Button", nil, rgn)
        cogBtn:SetSize(26, 26)
        cogBtn:SetPoint("RIGHT", anchorTo or rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = cogBtn
        cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
        cogBtn:SetAlpha(0.4)
        local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
        cogTex:SetAllPoints()
        cogTex:SetTexture(iconPath or EllesmereUI.COGS_ICON)
        cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.4) end)
        cogBtn:SetScript("OnClick", function(self) showFn(self) end)
        return cogBtn
    end

    ---------------------------------------------------------------------------
    --  Ring texture dropdown values (shared by GCD + Cast)
    ---------------------------------------------------------------------------
    local ringTexValues = { normal = "Ring Normal", light = "Ring Light", thin = "Ring Thin", heavy = "Ring Heavy", thick = "Ring Thick" }
    local ringTexOrder  = { "normal", "light", "---", "thin", "heavy", "thick" }

    ---------------------------------------------------------------------------
    --  Cursor Circle page  (Appearance + GCD + Cast Bar sections)
    ---------------------------------------------------------------------------
    local function BuildCursorPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h, row

        EllesmereUI:ClearContentHeader()

        -----------------------------------------------------------------------
        --  APPEARANCE
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_APPEARANCE, y);  y = y - h

        -- Enable Cursor Circle ---- Color (multiSwatch: custom left, class colored right)
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Cursor Circle",
              getValue=function() local p = DB(); return p and (p.enabled ~= false) end,
              setValue=function(v)
                local p = DB(); if not p then return end
                p.enabled = v
                RefreshAddon()
                EllesmereUI:RefreshPage()
              end },
            { type="multiSwatch", text="Color",
              swatches = {
                { tooltip = "Custom Color",
                  hasAlpha = false,
                  getValue = function()
                      local p = DB()
                      if not p then return 12/255, 210/255, 157/255 end
                      local r, g, b = HexToRGB(p.hex)
                      return r, g, b
                  end,
                  setValue = function(r, g, b)
                      local p = DB(); if not p then return end
                      p.hex = RGBToHex(r, g, b)
                      RefreshAddon()
                  end,
                  onClick = function(self)
                      local p = DB(); if not p then return end
                      if p.useClassColor then
                          p.useClassColor = false
                          RefreshAddon(); EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local p = DB()
                      if not p or p.enabled == false then return 0.15 end
                      return (p.useClassColor) and 0.3 or 1
                  end,
                  disabled = function()
                      local p = DB(); return not p or p.enabled == false
                  end },
                { tooltip = "Class Colored",
                  hasAlpha = false,
                  getValue = function()
                      local _, classFile = UnitClass("player")
                      local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                      if cc then return cc.r, cc.g, cc.b end
                      return 12/255, 210/255, 157/255
                  end,
                  setValue = function() end,
                  onClick = function()
                      local p = DB(); if not p then return end
                      p.useClassColor = true
                      RefreshAddon(); EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local p = DB()
                      if not p or p.enabled == false then return 0.15 end
                      return (p.useClassColor) and 1 or 0.3
                  end,
                  disabled = function()
                      local p = DB(); return not p or p.enabled == false
                  end },
              } }
        );  y = y - h

        -- Texture ---- Scale
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Texture",
              values={ ring_normal = "Ring Normal", ring_light = "Ring Light", custom = "Ellesmere Logo", ring_thin = "Ring Thin", ring_heavy = "Ring Heavy", ring_thick = "Ring Thick" },
              order={ "ring_normal", "ring_light", "custom", "---", "ring_thin", "ring_heavy", "ring_thick" },
              disabled=function() local p = DB(); return p and p.enabled == false end,
              disabledTooltip="Enable Cursor Circle",
              getValue=function() local p = DB(); return p and p.texture or "ring_normal" end,
              setValue=function(v)
                local p = DB(); if not p then return end
                p.texture = v
                RefreshAddon()
              end },
            { type="slider", text="Scale", min=0.5, max=2.0, step=0.1,
              disabled=function() local p = DB(); return p and p.enabled == false end,
              disabledTooltip="Enable Cursor Circle",
              getValue=function() local p = DB(); return p and p.scale or 1 end,
              setValue=function(v)
                local p = DB(); if not p then return end
                p.scale = v
                RefreshAddon()
              end }
        );  y = y - h

        -- Only Show in Instances ---- Cursor Trail
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Only Show in Instances",
              disabled=function() local p = DB(); return p and p.enabled == false end,
              disabledTooltip="Enable Cursor Circle",
              getValue=function() local p = DB(); return p and p.instanceOnly end,
              setValue=function(v)
                local p = DB(); if not p then return end
                p.instanceOnly = v
                if _G._ECL_UpdateVisibility then _G._ECL_UpdateVisibility() end
              end },
            { type="toggle", text="Cursor Trail",
              disabled=function() local p = DB(); return p and p.enabled == false end,
              disabledTooltip="Enable Cursor Circle",
              getValue=function() local p = DB(); return p and p.trail or false end,
              setValue=function(v)
                local p = DB(); if not p then return end
                p.trail = v
                if _G._ECL_ApplyTrail then _G._ECL_ApplyTrail() end
              end }
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  GLOBAL COOLDOWN
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_GCD, y);  y = y - h

        -- Enable GCD Circle ---- Color (multiSwatch: custom left, class colored right)
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Enable GCD Circle",
              getValue=function() return GCD_DB().enabled or false end,
              setValue=function(v)
                GCD_DB().enabled = v
                RefreshGCD()
                EllesmereUI:RefreshPage()
              end },
            { type="multiSwatch", text="Color",
              swatches = {
                { tooltip = "Custom Color",
                  hasAlpha = true,
                  getValue = function()
                      local g = GCD_DB()
                      local r, ng, b = HexToRGB(g.hex)
                      return r, ng, b, (g.alpha or 80) / 100
                  end,
                  setValue = function(r, g, b, a)
                      local gd = GCD_DB()
                      gd.hex = RGBToHex(r, g, b)
                      if a then gd.alpha = floor(a * 100 + 0.5) end
                      RefreshGCD()
                  end,
                  onClick = function(self)
                      local g = GCD_DB()
                      if g.useClassColor then
                          g.useClassColor = false
                          RefreshGCD(); EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local g = GCD_DB()
                      if not g.enabled then return 0.15 end
                      return g.useClassColor and 0.3 or 1
                  end,
                  disabled = function() return not GCD_DB().enabled end },
                { tooltip = "Class Colored",
                  hasAlpha = false,
                  getValue = function()
                      local _, classFile = UnitClass("player")
                      local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                      if cc then return cc.r, cc.g, cc.b end
                      return 12/255, 210/255, 157/255
                  end,
                  setValue = function() end,
                  onClick = function()
                      local g = GCD_DB()
                      g.useClassColor = true
                      RefreshGCD(); EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local g = GCD_DB()
                      if not g.enabled then return 0.15 end
                      return g.useClassColor and 1 or 0.3
                  end,
                  disabled = function() return not GCD_DB().enabled end },
              } }
        );  y = y - h

        -- Ring Texture ---- Scale
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Ring Texture",
              values=ringTexValues, order=ringTexOrder,
              disabled=function() return not GCD_DB().enabled end,
              disabledTooltip="Enable GCD Circle",
              getValue=function() return GCD_DB().ringTex or "light" end,
              setValue=function(v) GCD_DB().ringTex = v; RefreshGCD() end },
            { type="slider", text="Scale", min=10, max=80, step=1,
              disabled=function() return not GCD_DB().enabled end,
              disabledTooltip="Enable GCD Circle",
              getValue=function() return GCD_DB().radius or 21 end,
              setValue=function(v) GCD_DB().radius = v; RefreshGCD() end }
        );  y = y - h

        -- Only Show in Instances ---- Attach to Cursor
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Only Show in Instances",
              disabled=function() return not GCD_DB().enabled end,
              disabledTooltip="Enable GCD Circle",
              getValue=function() return GCD_DB().instanceOnly or false end,
              setValue=function(v)
                GCD_DB().instanceOnly = v
                if _G._ECL_UpdateVisibility then _G._ECL_UpdateVisibility() end
              end },
            { type="toggle", text="Attach to Cursor",
              disabled=function() return not GCD_DB().enabled end,
              disabledTooltip="Enable GCD Circle",
              getValue=function() return GCD_DB().attached ~= false end,
              setValue=function(v)
                GCD_DB().attached = v
                RefreshGCD()
                EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -----------------------------------------------------------------------
        --  CAST BAR
        -----------------------------------------------------------------------
        _, h = W:SectionHeader(parent, SECTION_CAST, y);  y = y - h

        -- Enable Cast Bar Circle ---- Color (multiSwatch: custom left, class colored right)
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Enable Cast Bar Circle",
              getValue=function() return Cast_DB().enabled or false end,
              setValue=function(v)
                Cast_DB().enabled = v
                RefreshCast()
                EllesmereUI:RefreshPage()
              end },
            { type="multiSwatch", text="Color",
              swatches = {
                { tooltip = "Custom Color",
                  hasAlpha = true,
                  getValue = function()
                      local c = Cast_DB()
                      local r, ng, b = HexToRGB(c.hex)
                      return r, ng, b, (c.alpha or 80) / 100
                  end,
                  setValue = function(r, g, b, a)
                      local cd = Cast_DB()
                      cd.hex = RGBToHex(r, g, b)
                      if a then cd.alpha = floor(a * 100 + 0.5) end
                      RefreshCast()
                  end,
                  onClick = function(self)
                      local c = Cast_DB()
                      if c.useClassColor then
                          c.useClassColor = false
                          RefreshCast(); EllesmereUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      local c = Cast_DB()
                      if not c.enabled then return 0.15 end
                      return c.useClassColor and 0.3 or 1
                  end,
                  disabled = function() return not Cast_DB().enabled end },
                { tooltip = "Class Colored",
                  hasAlpha = false,
                  getValue = function()
                      local _, classFile = UnitClass("player")
                      local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                      if cc then return cc.r, cc.g, cc.b end
                      return 12/255, 210/255, 157/255
                  end,
                  setValue = function() end,
                  onClick = function()
                      local c = Cast_DB()
                      c.useClassColor = true
                      RefreshCast(); EllesmereUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      local c = Cast_DB()
                      if not c.enabled then return 0.15 end
                      return c.useClassColor and 1 or 0.3
                  end,
                  disabled = function() return not Cast_DB().enabled end },
              } }
        );  y = y - h

        -- Inline cog on Enable Cast Bar Circle for "Show Spark"
        do
            local leftRgn = row._leftRegion
            local _, cogShowFn = EllesmereUI.BuildCogPopup({
                title = "Cast Bar Settings",
                rows = {
                    { type="toggle", label="Show Spark",
                      get=function()
                        local c = Cast_DB()
                        return c.sparkEnabled ~= false
                      end,
                      set=function(v)
                        Cast_DB().sparkEnabled = v
                        RefreshCast()
                      end },
                },
            })
            local cogBtn = MakeCogBtn(leftRgn, cogShowFn)
            local function UpdateCastCog()
                if not Cast_DB().enabled then
                    cogBtn:SetAlpha(0.15)
                    cogBtn:EnableMouse(false)
                    cogBtn._disabledTooltip = "Enable Cast Bar Circle"
                else
                    cogBtn:SetAlpha(0.4)
                    cogBtn:EnableMouse(true)
                    cogBtn._disabledTooltip = nil
                end
            end
            UpdateCastCog()
            EllesmereUI.RegisterWidgetRefresh(UpdateCastCog)
        end

        -- Ring Texture ---- Scale
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Ring Texture",
              values=ringTexValues, order=ringTexOrder,
              disabled=function() return not Cast_DB().enabled end,
              disabledTooltip="Enable Cast Bar Circle",
              getValue=function() return Cast_DB().ringTex or "normal" end,
              setValue=function(v) Cast_DB().ringTex = v; RefreshCast() end },
            { type="slider", text="Scale", min=10, max=80, step=1,
              disabled=function() return not Cast_DB().enabled end,
              disabledTooltip="Enable Cast Bar Circle",
              getValue=function() return Cast_DB().radius or 30 end,
              setValue=function(v) Cast_DB().radius = v; RefreshCast() end }
        );  y = y - h

        -- Only Show in Instances ---- Attach to Cursor
        row, h = W:DualRow(parent, y,
            { type="toggle", text="Only Show in Instances",
              disabled=function() return not Cast_DB().enabled end,
              disabledTooltip="Enable Cast Bar Circle",
              getValue=function() return Cast_DB().instanceOnly or false end,
              setValue=function(v)
                Cast_DB().instanceOnly = v
                if _G._ECL_UpdateVisibility then _G._ECL_UpdateVisibility() end
              end },
            { type="toggle", text="Attach to Cursor",
              disabled=function() return not Cast_DB().enabled end,
              disabledTooltip="Enable Cast Bar Circle",
              getValue=function() return Cast_DB().attached ~= false end,
              setValue=function(v)
                Cast_DB().attached = v
                RefreshCast()
                EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUICursor", {
        title       = "Cursor Circle",
        description = "Add a custom texture to your mouse cursor with GCD and cast bar rings.",
        pages       = { PAGE_CURSOR },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_CURSOR then
                return BuildCursorPage(pageName, parent, yOffset)
            end
        end,
        onReset = function()
            if _G._ECL_AceDB then
                _G._ECL_AceDB:ResetProfile()
            end
            RefreshAddon()
            RefreshGCD()
            RefreshCast()
            if _G._ECL_ApplyTrail then _G._ECL_ApplyTrail() end
        end,
    })

    ---------------------------------------------------------------------------
    --  Slash command  /ecc
    ---------------------------------------------------------------------------
    SLASH_ECL1 = "/ecc"
    SlashCmdList.ECL = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUICursor")
    end
end)
