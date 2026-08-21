if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_QoL_HearthTeleport_Options.lua
--  Hearthstone / Teleport page for the QoL module.
-------------------------------------------------------------------------------
if not EllesmereUI._ModuleNS["EllesmereUIQoL"] then return end

local function DB()
    local get = _G._EUI_HearthTeleport_DB
    local root = get and get()
    return root and root.profile and root.profile.hearthTeleport
end

local function Set(key, val)
    local p = DB()
    if p then p[key] = val end
end

local function ShowCfg()
    local c = DB()
    if not c then return {} end
    c.show = c.show or {}
    return c.show
end

local function RandomPoolCfg()
    local c = DB()
    if not c then return {} end
    c.randomPool = c.randomPool or {}
    return c.randomPool
end

local function Apply()
    if _G._EUI_ApplyHearthTeleport then _G._EUI_ApplyHearthTeleport() end
end

local function Disabled()
    local c = DB()
    return not c or c.enabled ~= true
end

local function ShowOn(key)
    local s = ShowCfg()
    if s[key] == nil then return true end
    return s[key] ~= false
end

local function HasToy(id)
    return PlayerHasToy and PlayerHasToy(id)
end

local function HasHearthstone()
    local DATA = EllesmereUI.HEARTH_TELEPORT_DATA
    local base = DATA and DATA.BASE_HEARTH_ITEM
    return base and C_Item and C_Item.GetItemCount and C_Item.GetItemCount(base) > 0
end

local function BuildRandomPoolItems()
    local DATA = EllesmereUI.HEARTH_TELEPORT_DATA
    if not DATA then return {} end
    local out = {}
    local base = DATA.BASE_HEARTH_ITEM
    if base then
        local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(base) or "Hearthstone"
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(base)
        out[#out + 1] = {
            key = base, label = name, icon = icon,
            lockedFn = function() return not HasHearthstone() end,
            lockedTooltip = "You don't have a Hearthstone.",
        }
    end
    for _, id in ipairs(DATA.COSMETIC_HEARTHS or {}) do
        local name = C_ToyBox and C_ToyBox.GetToyInfo and select(2, C_ToyBox.GetToyInfo(id))
        local icon
        if C_ToyBox and C_ToyBox.GetToyInfo then
            _, _, icon = C_ToyBox.GetToyInfo(id)
        end
        if not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(id) end
        out[#out + 1] = {
            key = id, label = name or ("Toy " .. id), icon = icon,
            lockedFn = function() return not HasToy(id) end,
            lockedTooltip = "You don't have this toy.",
        }
    end
    table.sort(out, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return out
end

_G._EUI_BuildHearthTeleportPage = function(pageName, parent, yOffset)
    local W  = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local y  = yOffset
    local _, h

    parent._showRowDivider = true

    _, h = W:SectionHeader(parent, "HEARTHSTONE / TELEPORT", y); y = y - h

    local kbRow
    kbRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Enable Hearthstone / Teleport",
          tooltip = "Shows a popup with hearthstones, class and racial travel, mage teleports and portals, and Hero's Path dungeon teleports. Use /eht or /euihearth, or bind a key below.",
          getValue = function() local c = DB(); return c and c.enabled == true end,
          setValue = EllesmereUI.DependentSetValue(
              function() local c = DB(); return c and c.enabled == true end,
              function(v)
                  Set("enabled", v)
                  Apply()
                  EllesmereUI:RefreshPage()
              end) },
        { type = "label", text = "Toggle Hearthstone / Teleport" }
    ); y = y - h

    if not EllesmereUI._prebuilding then
        local rgn = kbRow._rightRegion
        local kbBtn = CreateFrame("Button", nil, rgn)
        PP.Size(kbBtn, 126, 29)
        PP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -20, 0)
        kbBtn:SetFrameLevel(rgn:GetFrameLevel() + 4)
        kbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local kbBg = EllesmereUI.SolidTex(kbBtn, "BACKGROUND", EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
        kbBg:SetAllPoints()
        kbBtn._border = EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, PP)
        local kbLbl = EllesmereUI.MakeFont(kbBtn, 12, nil, 1, 1, 1)
        kbLbl:SetAlpha(EllesmereUI.DD_TXT_A)
        kbLbl:SetPoint("CENTER")
        local listening = false

        local function FormatKey(key)
            if not key or key == "" then return EllesmereUI.L("Not Bound") end
            local parts = {}
            for mod in key:gmatch("(%u+)%-") do
                parts[#parts + 1] = mod:sub(1, 1) .. mod:sub(2):lower()
            end
            parts[#parts + 1] = key:match("[^%-]+$") or key
            return table.concat(parts, " + ")
        end

        local function RefreshLabel()
            if listening then return end
            local k = DB() and DB().toggleKey
            if k == false then k = nil end
            kbLbl:SetText(FormatKey(k))
        end

        local function RefreshKbState()
            local off = Disabled()
            kbBtn:SetAlpha(off and 0.3 or 1)
            kbBtn:EnableMouse(not off)
            if rgn._label then rgn._label:SetAlpha(off and 0.3 or 1) end
            if off and listening then listening = false; kbBtn:EnableKeyboard(false) end
            RefreshLabel()
        end

        kbBtn:SetScript("OnClick", function(self, button)
            if Disabled() then return end
            if button == "RightButton" then
                if listening then listening = false; self:EnableKeyboard(false) end
                Set("toggleKey", false)
                Apply()
                RefreshLabel()
                if EllesmereUI._NotifySettingWrite then EllesmereUI._NotifySettingWrite(rgn) end
                return
            end
            if listening then return end
            listening = true
            kbLbl:SetText(EllesmereUI.L("Press a key..."))
            self:EnableKeyboard(true)
        end)

        kbBtn:SetScript("OnKeyDown", function(self, key)
            if not listening then self:SetPropagateKeyboardInput(true); return end
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL"
               or key == "LALT" or key == "RALT" then
                self:SetPropagateKeyboardInput(true); return
            end
            self:SetPropagateKeyboardInput(false)
            if key == "ESCAPE" then
                listening = false; self:EnableKeyboard(false); RefreshLabel(); return
            end
            if InCombatLockdown() then
                listening = false; self:EnableKeyboard(false); RefreshLabel(); return
            end
            local mods = ""
            if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
            if IsControlKeyDown() then mods = mods .. "CTRL-" end
            if IsAltKeyDown() then mods = mods .. "ALT-" end
            Set("toggleKey", mods .. key)
            Apply()
            listening = false
            self:EnableKeyboard(false)
            RefreshLabel()
            if EllesmereUI._NotifySettingWrite then EllesmereUI._NotifySettingWrite(rgn) end
        end)

        kbBtn:SetScript("OnEnter", function(self)
            if Disabled() then
                EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Enable Hearthstone / Teleport"))
                return
            end
            kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
            if kbBtn._border and kbBtn._border.SetColor then kbBtn._border:SetColor(1, 1, 1, 0.3) end
            EllesmereUI.ShowWidgetTooltip(self, "Toggles the Hearthstone / Teleport window.\n\nLeft-click to set a keybind.\nRight-click to unbind.")
        end)
        kbBtn:SetScript("OnLeave", function()
            if listening then return end
            kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            if kbBtn._border and kbBtn._border.SetColor then kbBtn._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A) end
            EllesmereUI.HideWidgetTooltip()
        end)
        kbBtn:SetScript("OnHide", function()
            if listening then listening = false; kbBtn:EnableKeyboard(false); RefreshLabel() end
            EllesmereUI.HideWidgetTooltip()
        end)

        RefreshKbState()
        EllesmereUI.RegisterWidgetRefresh(RefreshKbState)
        EllesmereUI.AddCaptureAccessor(rgn, {
            type = "keybind", text = "Toggle Hearthstone / Teleport",
            getValue = function() local c = DB(); return c and c.toggleKey end,
            setValue = function(v) Set("toggleKey", v); Apply(); RefreshLabel() end,
        })
    end

    if not Disabled() then
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Window Scale",
              min = 50, max = 150, step = 5,
              tooltip = "Scale of the Hearthstone / Teleport popup.",
              getValue = function()
                  local c = DB()
                  return math.floor(((c and c.scale) or 1.05) * 100 + 0.5)
              end,
              setValue = function(v)
                  Set("scale", v / 100)
                  local p = _G.EUIHearthTeleportPopup
                  if p then p:SetScale(v / 100) end
              end },
            { type = "toggle", text = "Hide After Teleporting",
              tooltip = "Automatically hides the window after you use a teleport or hearthstone.",
              getValue = function() local c = DB(); return not c or c.hideAfterUse ~= false end,
              setValue = function(v) Set("hideAfterUse", v) end }
        ); y = y - h
    end

    _, h = W:Spacer(parent, y, 16); y = y - h
    _, h = W:SectionHeader(parent, "SHOW", y); y = y - h

    local hsRow
    hsRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Hearthstones",
          disabled = Disabled,
          disabledTooltip = "Enable Hearthstone / Teleport",
          tooltip = "Show hearthstones, random hearth, Dalaran / Arcantina, and owned cosmetic toys.",
          getValue = function() return ShowOn("hearthstones") end,
          setValue = function(v)
              ShowCfg().hearthstones = v
              Apply()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Random Hearthstones",
          disabled = function() return Disabled() or not ShowOn("hearthstones") end,
          disabledTooltip = "Hearthstones",
          tooltip = "Show a Random Hearthstone row that picks from the toys you enable in the cog menu.",
          getValue = function() local c = DB(); return not c or c.randomHearthstones ~= false end,
          setValue = function(v) Set("randomHearthstones", v); Apply() end }
    ); y = y - h

    if not EllesmereUI._prebuilding then
        local rightRgn = hsRow._rightRegion
        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rightRgn, 210, rightRgn:GetFrameLevel() + 2,
            BuildRandomPoolItems,
            function(k)
                local pool = RandomPoolCfg()
                if pool[k] == nil then return true end
                return pool[k] ~= false
            end,
            function(k, v)
                RandomPoolCfg()[k] = v
                Apply()
            end,
            nil, 10, true
        )
        cbDD:SetSize(1, 1)
        cbDD:SetAlpha(0)
        cbDD:EnableMouse(false)
        cbDD:ClearAllPoints()
        cbDD:SetPoint("CENTER", rightRgn, "CENTER")

        local function randOff()
            return Disabled() or not ShowOn("hearthstones")
        end
        local randCogBtn = CreateFrame("Button", nil, rightRgn)
        randCogBtn:SetSize(26, 26)
        randCogBtn:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -9, 0)
        rightRgn._lastInline = randCogBtn
        randCogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
        randCogBtn:SetAlpha(randOff() and 0.15 or 0.4)
        local randCogTex = randCogBtn:CreateTexture(nil, "OVERLAY")
        randCogTex:SetAllPoints()
        randCogTex:SetTexture(EllesmereUI.COGS_ICON)
        randCogBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.7)
            if not randOff() then
                EllesmereUI.ShowWidgetTooltip(self, "Choose which hearthstones Random can pick from.")
            end
        end)
        randCogBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(randOff() and 0.15 or 0.4)
            EllesmereUI.HideWidgetTooltip()
        end)
        randCogBtn:SetScript("OnClick", function()
            if randOff() then return end
            cbDD:Click()
        end)
        local randCogBlock = CreateFrame("Frame", nil, randCogBtn)
        randCogBlock:SetAllPoints()
        randCogBlock:SetFrameLevel(randCogBtn:GetFrameLevel() + 10)
        randCogBlock:EnableMouse(true)
        randCogBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(randCogBtn, EllesmereUI.DisabledTooltip("Hearthstones"))
        end)
        randCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        local function UpdateRandDisabled()
            local off = randOff()
            randCogBtn:SetAlpha(off and 0.15 or 0.4)
            randCogBtn:EnableMouse(not off)
            if rightRgn._label then rightRgn._label:SetAlpha(off and 0.3 or 1) end
            if rightRgn._control then rightRgn._control:SetAlpha(off and 0.3 or 1) end
            if off then randCogBlock:Show() else randCogBlock:Hide() end
        end
        UpdateRandDisabled()
        EllesmereUI.RegisterWidgetRefresh(UpdateRandDisabled)
    end

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Racials",
          disabled = Disabled,
          tooltip = "Vulpera camp, Dark Iron Mole Machine, Haranir Rootwalking.",
          getValue = function() return ShowOn("racials") end,
          setValue = function(v) ShowCfg().racials = v; Apply() end },
        { type = "toggle", text = "Class Teleports",
          disabled = Disabled,
          tooltip = "Class travel spells such as Astral Recall, Death Gate, and Dreamwalk.",
          getValue = function() return ShowOn("classTeleports") end,
          setValue = function(v) ShowCfg().classTeleports = v; Apply() end }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Mage Teleports",
          disabled = Disabled,
          tooltip = "Mage teleport spells in the Class / Racials flyout.",
          getValue = function() return ShowOn("mageTeleports") end,
          setValue = function(v) ShowCfg().mageTeleports = v; Apply(); EllesmereUI:RefreshPage() end },
        { type = "toggle", text = "Mage Portals",
          disabled = Disabled,
          tooltip = "Mage portal spells in the Class / Racials flyout.",
          getValue = function() return ShowOn("magePortals") end,
          setValue = function(v) ShowCfg().magePortals = v; Apply(); EllesmereUI:RefreshPage() end }
    ); y = y - h

    local seasonRow
    seasonRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Seasonal Dungeons",
          disabled = Disabled,
          tooltip = "Current M+ season Hero's Path dungeon teleports.",
          getValue = function() return ShowOn("seasonalDungeons") end,
          setValue = function(v)
              ShowCfg().seasonalDungeons = v
              Apply()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Legacy Dungeons",
          disabled = Disabled,
          tooltip = "Older Hero's Path dungeon teleports you have learned.",
          getValue = function() return ShowOn("legacyDungeons") end,
          setValue = function(v)
              ShowCfg().legacyDungeons = v
              Apply()
              EllesmereUI:RefreshPage()
          end }
    ); y = y - h

    if not EllesmereUI._prebuilding then
        local leftRgn = seasonRow._leftRegion
        local function seasonOff()
            return Disabled() or not ShowOn("seasonalDungeons")
        end
        local _, seasonCogShow = EllesmereUI.BuildCogPopup({
            title = "Seasonal Dungeons",
            rows = {
                { type = "toggle", label = "Highlight Current Key",
                  get = function() local c = DB(); return not c or c.highlightCurrentKey ~= false end,
                  set = function(v)
                      Set("highlightCurrentKey", v)
                      Apply()
                  end },
                { type = "toggle", label = "Keystone Portal Reminder",
                  tooltip = "While this window is open, highlight the same dungeon the LFG Reminder popup is showing.",
                  get = function() local c = DB(); return c and c.keystoneReminder == true end,
                  set = function(v)
                      Set("keystoneReminder", v)
                      Apply()
                  end },
            },
        })
        local seasonCogBtn = CreateFrame("Button", nil, leftRgn)
        seasonCogBtn:SetSize(26, 26)
        seasonCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
        leftRgn._lastInline = seasonCogBtn
        seasonCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
        seasonCogBtn:SetAlpha(seasonOff() and 0.15 or 0.4)
        local seasonCogTex = seasonCogBtn:CreateTexture(nil, "OVERLAY")
        seasonCogTex:SetAllPoints()
        seasonCogTex:SetTexture(EllesmereUI.COGS_ICON)
        seasonCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        seasonCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(seasonOff() and 0.15 or 0.4) end)
        seasonCogBtn:SetScript("OnClick", function(self) seasonCogShow(self) end)
        local seasonCogBlock = CreateFrame("Frame", nil, seasonCogBtn)
        seasonCogBlock:SetAllPoints()
        seasonCogBlock:SetFrameLevel(seasonCogBtn:GetFrameLevel() + 10)
        seasonCogBlock:EnableMouse(true)
        seasonCogBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(seasonCogBtn, EllesmereUI.DisabledTooltip("Seasonal Dungeons"))
        end)
        seasonCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = seasonOff()
            seasonCogBtn:SetAlpha(off and 0.15 or 0.4)
            if off then seasonCogBlock:Show() else seasonCogBlock:Hide() end
        end)
        if seasonOff() then seasonCogBlock:Show() else seasonCogBlock:Hide() end
    end

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Raids",
          disabled = Disabled,
          tooltip = "Hero's Path raid teleports you have learned.",
          getValue = function() return ShowOn("raids") end,
          setValue = function(v) ShowCfg().raids = v; Apply() end },
        { type = "label", text = "" }
    ); y = y - h

    return math.abs(y - yOffset)
end
