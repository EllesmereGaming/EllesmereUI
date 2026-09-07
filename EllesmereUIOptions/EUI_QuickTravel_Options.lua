if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_QuickTravel_Options.lua
--  Quick Travel sidebar addon: hearthstones, class/racial travel, mage
--  teleports and portals, and Hero's Path dungeon/raid teleports.
-------------------------------------------------------------------------------
local ADDON_NAME = "EllesmereUIQuickTravel"
local ns = EllesmereUI._ModuleNS[ADDON_NAME]
if not ns then return end  -- module disabled: no options page

local PAGE_DISPLAY = "Quick Travel"

local function DB()
    local get = _G._EUI_HearthTeleport_DB
    local root = get and get()
    return root and root.profile
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

local function BuildPage(pageName, parent, yOffset)
    local W  = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local y  = yOffset
    local _, h

    parent._showRowDivider = true

    _, h = W:SectionHeader(parent, "QUICK TRAVEL", y); y = y - h

    local kbRow
    kbRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Hide After Teleporting",
          tooltip = "Automatically hides the window after you use a teleport or hearthstone.",
          getValue = function() local c = DB(); return not c or c.hideAfterUse ~= false end,
          setValue = function(v) Set("hideAfterUse", v) end },
        { type = "label", text = "Keybind" }
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

        kbBtn:SetScript("OnClick", function(self, button)
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
            kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
            if kbBtn._border and kbBtn._border.SetColor then kbBtn._border:SetColor(1, 1, 1, 0.3) end
            EllesmereUI.ShowWidgetTooltip(self, "Toggles the Quick Travel window. You can also type /eht or /euihearth in chat or a macro.\n\nLeft-click to set a keybind.\nRight-click to unbind.")
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

        RefreshLabel()
        EllesmereUI.RegisterWidgetRefresh(RefreshLabel)
        EllesmereUI.AddCaptureAccessor(rgn, {
            type = "keybind", text = "Keybind",
            getValue = function() local c = DB(); return c and c.toggleKey end,
            setValue = function(v) Set("toggleKey", v); Apply(); RefreshLabel() end,
        })
    end

    _, h = W:DualRow(parent, y,
        { type = "slider", text = "Window Scale",
          min = 50, max = 150, step = 5,
          tooltip = "Scale of the Quick Travel popup.",
          getValue = function()
              local c = DB()
              return math.floor(((c and c.scale) or 1.05) * 100 + 0.5)
          end,
          setValue = function(v)
              Set("scale", v / 100)
              local p = _G.EUIHearthTeleportPopup
              if p then p:SetScale(v / 100) end
          end },
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:Spacer(parent, y, 16); y = y - h
    _, h = W:SectionHeader(parent, "SHOW", y); y = y - h

    local hsRow
    hsRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Hearthstones",
          tooltip = "Show hearthstones, random hearth, Dalaran / Arcantina, and owned cosmetic toys.",
          getValue = function() return ShowOn("hearthstones") end,
          setValue = function(v)
              ShowCfg().hearthstones = v
              Apply()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Racials",
          tooltip = "Vulpera camp, Dark Iron Mole Machine, Haranir Rootwalking.",
          getValue = function() return ShowOn("racials") end,
          setValue = function(v) ShowCfg().racials = v; Apply() end }
    ); y = y - h

    if not EllesmereUI._prebuilding then
        local leftRgn = hsRow._leftRegion
        local function hearthOff()
            return not ShowOn("hearthstones")
        end
        local _, hearthCogShow = EllesmereUI.BuildCogPopup({
            title = "Hearthstones",
            rows = {
                { type = "toggle", label = "Show Random Hearth",
                  tooltip = "Show a Random Hearthstone row that picks from the toys you enable in Random Pool.",
                  get = function() local c = DB(); return not c or c.randomHearthstones ~= false end,
                  set = function(v) Set("randomHearthstones", v); Apply() end },
                { type = "checkboxdropdown", label = "Random Pool",
                  tooltip = "Choose which hearthstones Random can pick from.",
                  disabled = function() local c = DB(); return c and c.randomHearthstones == false end,
                  disabledTooltip = "Show Random Hearth",
                  items = BuildRandomPoolItems,
                  searchable = true,
                  maxVisible = 10,
                  get = function(k)
                      local pool = RandomPoolCfg()
                      if pool[k] == nil then return true end
                      return pool[k] ~= false
                  end,
                  set = function(k, v)
                      RandomPoolCfg()[k] = v
                      Apply()
                  end },
            },
        })
        local hearthCogBtn = CreateFrame("Button", nil, leftRgn)
        hearthCogBtn:SetSize(26, 26)
        hearthCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
        leftRgn._lastInline = hearthCogBtn
        hearthCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
        hearthCogBtn:SetAlpha(hearthOff() and 0.15 or 0.4)
        local hearthCogTex = hearthCogBtn:CreateTexture(nil, "OVERLAY")
        hearthCogTex:SetAllPoints()
        hearthCogTex:SetTexture(EllesmereUI.COGS_ICON)
        hearthCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
        hearthCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(hearthOff() and 0.15 or 0.4) end)
        hearthCogBtn:SetScript("OnClick", function(self) hearthCogShow(self) end)
        local hearthCogBlock = CreateFrame("Frame", nil, hearthCogBtn)
        hearthCogBlock:SetAllPoints()
        hearthCogBlock:SetFrameLevel(hearthCogBtn:GetFrameLevel() + 10)
        hearthCogBlock:EnableMouse(true)
        hearthCogBlock:SetScript("OnEnter", function()
            EllesmereUI.ShowWidgetTooltip(hearthCogBtn, EllesmereUI.DisabledTooltip("Hearthstones"))
        end)
        hearthCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
        EllesmereUI.RegisterWidgetRefresh(function()
            local off = hearthOff()
            hearthCogBtn:SetAlpha(off and 0.15 or 0.4)
            if off then hearthCogBlock:Show() else hearthCogBlock:Hide() end
        end)
        if hearthOff() then hearthCogBlock:Show() else hearthCogBlock:Hide() end
    end

    _, h = W:DualRow(parent, y,
        { type = "toggle", text = "Class Teleports",
          tooltip = "Class travel spells such as Astral Recall, Death Gate, and Dreamwalk.",
          getValue = function() return ShowOn("classTeleports") end,
          setValue = function(v) ShowCfg().classTeleports = v; Apply() end },
        { type = "toggle", text = "Mage Teleports",
          tooltip = "Mage teleport spells in the Class / Racials flyout.",
          getValue = function() return ShowOn("mageTeleports") end,
          setValue = function(v) ShowCfg().mageTeleports = v; Apply(); EllesmereUI:RefreshPage() end }
    ); y = y - h

    local seasonRow
    seasonRow, h = W:DualRow(parent, y,
        { type = "toggle", text = "Mage Portals",
          tooltip = "Mage portal spells in the Class / Racials flyout.",
          getValue = function() return ShowOn("magePortals") end,
          setValue = function(v) ShowCfg().magePortals = v; Apply(); EllesmereUI:RefreshPage() end },
        { type = "toggle", text = "Seasonal Dungeons",
          tooltip = "Current M+ season Hero's Path dungeon teleports.",
          getValue = function() return ShowOn("seasonalDungeons") end,
          setValue = function(v)
              ShowCfg().seasonalDungeons = v
              Apply()
              EllesmereUI:RefreshPage()
          end }
    ); y = y - h

    if not EllesmereUI._prebuilding then
        local rightRgn = seasonRow._rightRegion
        local function seasonOff()
            return not ShowOn("seasonalDungeons")
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
        local seasonCogBtn = CreateFrame("Button", nil, rightRgn)
        seasonCogBtn:SetSize(26, 26)
        seasonCogBtn:SetPoint("RIGHT", rightRgn._lastInline or rightRgn._control, "LEFT", -9, 0)
        rightRgn._lastInline = seasonCogBtn
        seasonCogBtn:SetFrameLevel(rightRgn:GetFrameLevel() + 5)
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
        { type = "toggle", text = "Legacy Dungeons",
          tooltip = "Older Hero's Path dungeon teleports you have learned.",
          getValue = function() return ShowOn("legacyDungeons") end,
          setValue = function(v)
              ShowCfg().legacyDungeons = v
              Apply()
              EllesmereUI:RefreshPage()
          end },
        { type = "toggle", text = "Raids",
          tooltip = "Hero's Path raid teleports you have learned.",
          getValue = function() return ShowOn("raids") end,
          setValue = function(v) ShowCfg().raids = v; Apply() end }
    ); y = y - h

    return math.abs(y - yOffset)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    SLASH_EUIQUICKTRAVEL1 = "/eqt"
    SLASH_EUIQUICKTRAVEL2 = "/quicktravel"
    SlashCmdList.EUIQUICKTRAVEL = function()
        if InCombatLockdown and InCombatLockdown() then
            print("Cannot open options in combat")
            return
        end
        EllesmereUI:ShowModule("EllesmereUIQuickTravel")
    end

    EllesmereUI:RegisterModule("EllesmereUIQuickTravel", {
        title       = "Quick Travel",
        description = "Hearthstones, class and racial travel, mage teleports and portals, and Hero's Path dungeon teleports.",
        pages       = { PAGE_DISPLAY },
        searchTerms = { "hearth", "hearthstone", "teleport", "portal", "porter", "mage", "vulpera", "camp", "racial", "seasonal", "keystone", "eht", "hearth teleport", "quick travel", "eqt", "random hearth" },
        buildPage   = BuildPage,
        onReset     = function()
            if EllesmereUIDB then
                EllesmereUIDB.hearthTeleport = nil
            end
            if EllesmereUIDB and EllesmereUIDB.profiles then
                local profile = EllesmereUIDB.activeProfile or "Default"
                local p = EllesmereUIDB.profiles[profile]
                if p and p.addons and p.addons.EllesmereUIQuickTravel then
                    wipe(p.addons.EllesmereUIQuickTravel)
                end
            end
            local target = _G._EUI_HearthTeleport_DB and _G._EUI_HearthTeleport_DB()
            if target and target.profile and ns.DB_DEFAULTS then
                EllesmereUI.Lite.DeepMergeDefaults(target.profile, ns.DB_DEFAULTS.profile)
            end
            if _G._EUI_ApplyHearthTeleport then _G._EUI_ApplyHearthTeleport() end
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
