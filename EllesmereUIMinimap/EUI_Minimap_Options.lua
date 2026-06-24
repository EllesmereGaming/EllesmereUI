-------------------------------------------------------------------------------
--  EUI_Basics_Options.lua
--  Registers the Basics module with EllesmereUI.
--  All get/set calls go through the global bridge to the addon's DB profile.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_CHAT          = "Chat"
local PAGE_MINIMAP       = "Minimap"
local PAGE_FRIENDS       = "Friends"
local PAGE_QUEST_TRACKER = "Quest Tracker"
local PAGE_CURSOR        = "Cursor"
local PAGE_DMG_METERS    = "Damage Meters"

local SECTION_CHAT    = "CHAT"
local SECTION_MINIMAP = "DISPLAY"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    ---------------------------------------------------------------------------
    --  DB helpers
    ---------------------------------------------------------------------------
    local db

    C_Timer.After(0, function()
        db = _G._EMM_DB
    end)

    local function DB()
        if not db then db = _G._EMM_DB end
        return db and db.profile
    end

    local function ChatDB()
        local p = DB()
        return p and p.chat
    end

    local function MinimapDB()
        local p = DB()
        return p and p.minimap
    end

    local function FriendsDB()
        local p = DB()
        return p and p.friends
    end

    ---------------------------------------------------------------------------
    --  Refresh helpers
    ---------------------------------------------------------------------------
    local function RefreshChat()
        if _G._EBS_ApplyChat then _G._EBS_ApplyChat() end
    end

    local function RefreshMinimap()
        if _G._EMM_ApplyMinimap then _G._EMM_ApplyMinimap() end
    end

    local function FullRebuildMinimap()
        if _G._EMM_FullRebuildMinimap then _G._EMM_FullRebuildMinimap()
        else RefreshMinimap() end
    end

    local function RefreshFriends()
        if _G._EBS_ApplyFriends then _G._EBS_ApplyFriends() end
    end

    local function RefreshAll()
        if _G._EBS_ApplyAll then _G._EBS_ApplyAll() end
    end

    ---------------------------------------------------------------------------
    --  Visibility row builder (reused across all pages)
    ---------------------------------------------------------------------------
    local PP = EllesmereUI.PP
    local function BuildVisibilityRow(W, parent, y, getCfg, refreshFn)
        local visRow, visH = W:DualRow(parent, y,
            { type="dropdown", text="Visibility",
              values = EllesmereUI.VIS_VALUES,
              order  = EllesmereUI.VIS_ORDER,
              getValue=function()
                  local c = getCfg(); if not c then return "always" end
                  return c.visibility or "always"
              end,
              setValue=function(v)
                  local c = getCfg(); if not c then return end
                  c.visibility = v
                  if refreshFn then refreshFn() end
                  if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                  EllesmereUI:RefreshPage()
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
                function(k) local c = getCfg(); return c and c[k] or false end,
                function(k, v)
                    local c = getCfg(); if not c then return end
                    c[k] = v
                    if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
            rightRgn._control = cbDD
            rightRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        return visH
    end

    ---------------------------------------------------------------------------
    --  Border color multiSwatch builder
    ---------------------------------------------------------------------------
    local function MakeBorderSwatch(getCfg, refreshFn)
        return {
            { tooltip = "Custom Color",
              hasAlpha = false,
              getValue = function()
                  local c = getCfg()
                  if not c then return 0.05, 0.05, 0.05 end
                  return c.borderR, c.borderG, c.borderB
              end,
              setValue = function(r, g, b)
                  local c = getCfg(); if not c then return end
                  c.borderR, c.borderG, c.borderB = r, g, b
                  refreshFn()
              end,
              onClick = function(self)
                  local c = getCfg(); if not c then return end
                  if c.useClassColor then
                      c.useClassColor = false
                      refreshFn(); EllesmereUI:RefreshPage()
                      return
                  end
                  if self._eabOrigClick then self._eabOrigClick(self) end
              end,
              refreshAlpha = function()
                  local c = getCfg()
                  if not c or not c.enabled then return 0.15 end
                  return c.useClassColor and 0.3 or 1
              end },
            { tooltip = "Accent Color",
              hasAlpha = false,
              getValue = function()
                  local ar, ag, ab = EllesmereUI.GetAccentColor()
                  return ar, ag, ab
              end,
              setValue = function() end,
              -- Flag name stays `useClassColor` for backwards compat with
              -- users who already have it stamped in their SavedVariables.
              -- Only the color resolution changes -- the flag now means
              -- "use live accent" rather than "use class color".
              onClick = function()
                  local c = getCfg(); if not c then return end
                  c.useClassColor = true
                  refreshFn(); EllesmereUI:RefreshPage()
              end,
              refreshAlpha = function()
                  local c = getCfg()
                  if not c or not c.enabled then return 0.15 end
                  return c.useClassColor and 1 or 0.3
              end },
        }
    end

    ---------------------------------------------------------------------------
    --  Chat Page
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Minimap Page
    ---------------------------------------------------------------------------
    local function BuildMinimapPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, SECTION_MINIMAP, y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="slider", text="Size", min=100, max=600, step=1,
              getValue=function() local m = MinimapDB(); return m and m.mapSize or 140 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.mapSize = v
                -- Cover the map render during drag to mask the zoom-nudge blink.
                -- Borders, buttons, etc. remain visible above the overlay.
                local minimap = _G.Minimap
                if minimap then
                    if not minimap._dragOverlay then
                        local ov = minimap:CreateTexture(nil, "BACKGROUND", nil, 7)
                        ov:SetAllPoints(minimap)
                        minimap._dragOverlay = ov
                    end
                    local shape = m.shape or "square"
                    if shape == "circle" or shape == "textured_circle" then
                        minimap._dragOverlay:SetTexture("Interface\\Common\\CommonMaskCircle")
                        minimap._dragOverlay:SetVertexColor(0, 0, 0, 1)
                    else
                        minimap._dragOverlay:SetColorTexture(0, 0, 0, 1)
                    end
                    minimap._dragOverlay:Show()
                end
                RefreshMinimap()
                if not _G._EBS_SizeDragTimer then
                    _G._EBS_SizeDragTimer = C_Timer.NewTimer(0, function() end)
                end
                _G._EBS_SizeDragTimer:Cancel()
                _G._EBS_SizeDragTimer = C_Timer.NewTimer(0.15, function()
                    if minimap and minimap._dragOverlay then
                        minimap._dragOverlay:Hide()
                    end
                end)
              end },
            { type="multiSwatch", text="Accent Color",
              swatches = MakeBorderSwatch(MinimapDB, RefreshMinimap) })
        y = y - h

        h = BuildVisibilityRow(W, parent, y, MinimapDB, RefreshMinimap);  y = y - h

        -- Shape | Border Thickness
        local shapeRow
        shapeRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Shape",
              values = { square = "Square", circle = "Circle", textured_circle = "Textured Circle" },
              order  = { "square", "circle", "textured_circle" },
              getValue=function() local m = MinimapDB(); return m and m.shape or "square" end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.shape = v
                RefreshMinimap()
              end },
            { type="slider", text="Border Thickness", min=0, max=5, step=1,
              getValue=function() local m = MinimapDB(); return m and m.borderSize or 1 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.borderSize = v
                RefreshMinimap()
              end }
        );  y = y - h

        -- Inline cog on Shape for the Rotate Minimap toggle. Off (default) keeps
        -- the rotateMinimap CVar at 0; on sets it to 1 (enforced in ApplyMinimap).
        do
            local rgn = shapeRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Shape Settings",
                rows = {
                    { type = "toggle", label = "Rotate Minimap",
                      get = function() local m = MinimapDB(); return m and m.rotateMinimap or false end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.rotateMinimap = v
                          RefreshMinimap()
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end

        y = y - 10

        -- ICONS AND BUTTONS section header
        _, h = W:SectionHeader(parent, "ICONS AND BUTTONS", y);  y = y - h

        -- Ungroup Minimap Buttons | In-Group Button Size
        local ungroupRow
        ungroupRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Ungroup Minimap Buttons",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end },
            { type="slider", text="In-Group Button Size", min=14, max=40, step=1,
              tooltip="Size of addon minimap buttons in the flyout grid",
              getValue=function() local m = MinimapDB(); return m and m.addonBtnSize or 24 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.addonBtnSize = v
                RefreshMinimap()
              end }
        );  y = y - h

        -- Replace placeholder dropdown with checkbox dropdown
        do
            local leftRgn = ungroupRow._leftRegion
            if leftRgn._control then leftRgn._control:Hide() end

            -- Build items from currently collected minimap buttons
            local function GetUngroupItems()
                local items = {}
                local btns = _G._EBS_CachedAddonButtons or {}
                local vis = _G._EBS_AddonVisible or {}
                for _, btn in ipairs(btns) do
                    local name = btn:GetName()
                    if name and vis[btn] ~= false then
                        local label = name:gsub("^LibDBIcon10_", ""):gsub("^Lib_GPI_Minimap_", ""):gsub("MinimapButton$", ""):gsub("_MinimapButton$", "")
                        items[#items + 1] = { key = name, label = label }
                    end
                end
                table.sort(items, function(a, b) return a.label < b.label end)
                return items
            end

            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                leftRgn, 210, leftRgn:GetFrameLevel() + 2,
                GetUngroupItems(),
                function(k)
                    local m = MinimapDB(); if not m then return false end
                    return m.ungroupedButtons and m.ungroupedButtons[k] and true or false
                end,
                function(k, v)
                    local m = MinimapDB(); if not m then return end
                    if not m.ungroupedButtons then m.ungroupedButtons = {} end
                    if v then
                        local maxOrder = 0
                        for _, ord in pairs(m.ungroupedButtons) do
                            if type(ord) == "number" and ord > maxOrder then maxOrder = ord end
                        end
                        m.ungroupedButtons[k] = maxOrder + 1
                    else
                        m.ungroupedButtons[k] = nil
                    end
                    FullRebuildMinimap()
                end)
            local PP = EllesmereUI.PP
            PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
            leftRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Interactable Button Size | Outer-Group MM Button Size (toggle + cog)
        local customBtnRow
        customBtnRow, h = W:DualRow(parent, y,
            { type="slider", text="Interactable Button Size", min=16, max=40, step=1,
              tooltip="Size of mail, calendar, tracking, and minimap button group toggle",
              getValue=function() local m = MinimapDB(); return m and m.interactableBtnSize or 21 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.interactableBtnSize = v
                RefreshMinimap()
              end },
            { type="toggle", text="Outer-Group MM Button Size",
              tooltip="Override the size of ungrouped minimap buttons independently from the interactable button size.",
              getValue=function() local m = MinimapDB(); return m and m.customBtnSizeEnabled end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.customBtnSizeEnabled = v
                RefreshMinimap()
                EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Inline cog on Outer-Group MM Button Size for size slider
        do
            local rgn = customBtnRow._rightRegion
            local function isOff()
                local m = MinimapDB(); return m and (not m.customBtnSizeEnabled)
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Ungrouped Button Size",
                rows = {
                    { type = "slider", label = "Size", min = 16, max = 40, step = 1,
                      get = function() local m = MinimapDB(); return m and m.customBtnSize or 24 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.customBtnSize = v
                          RefreshMinimap()
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(isOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(isOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Outer-Group MM Button Size")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = isOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if isOff() then cogBlock:Show() else cogBlock:Hide() end
        end

        -- Free Move Buttons | Button Backgrounds
        local fmRow
        fmRow, h = W:DualRow(parent, y,
            { type="toggle", text="Free Move Buttons",
              tooltip="When enabled, Shift+Click any minimap button (mail, calendar, tracking, addon buttons) to drag it to a custom position.",
              getValue=function() local m = MinimapDB(); return m and m.freeMoveBtns end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.freeMoveBtns = v
                if not v then
                    m.btnPositions = {}
                end
                RefreshMinimap()
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Button Backgrounds",
              tooltip="Show black backgrounds behind minimap indicator buttons (tracking, calendar, mail, crafting, addon buttons, flyout toggle).",
              getValue=function() local m = MinimapDB(); return m and m.btnBackgrounds ~= false end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.btnBackgrounds = v
                FullRebuildMinimap()
              end }
        );  y = y - h

        -- "Reset" label next to the Free Move toggle (only visible when enabled)
        do
            local rgn = fmRow._leftRegion
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
                local m = MinimapDB(); if not m then return end
                m.btnPositions = {}
                RefreshMinimap()
            end)
            local function UpdateResetVis()
                local m = MinimapDB()
                local on = m and m.freeMoveBtns
                resetFS:SetShown(on)
                hitBtn:SetShown(on)
            end
            UpdateResetVis()
            EllesmereUI.RegisterWidgetRefresh(UpdateResetVis)
        end

        -- Hide Extra Buttons (checkbox dropdown)
        local extraBtnRow
        extraBtnRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Hide Extra Buttons",
              values = { __placeholder = "..." }, order = { "__placeholder" },
              getValue = function() return "__placeholder" end,
              setValue = function() end },
            { type="toggle", text="Mouseover Extra Buttons",
              tooltip="When enabled, the extra buttons (Great Vault, M+ Portals, Friends Online, Group Button) and any ungrouped minimap buttons only show while the mouse is over the minimap. The M+ Portals flyout keeps them shown until it closes.",
              getValue = function() local m = MinimapDB(); return m and m.mouseoverExtraBtns or false end,
              setValue = function(v) local m = MinimapDB(); if m then m.mouseoverExtraBtns = v; RefreshMinimap() end end }
        );  y = y - h

        -- Replace placeholder with checkbox dropdown
        do
            local leftRgn = extraBtnRow._leftRegion
            if leftRgn._control then leftRgn._control:Hide() end

            local EXTRA_BTN_ITEMS = {
                { key = "greatVault",    label = "Great Vault" },
                { key = "portals",       label = "M+ Portals" },
                { key = "friendsOnline", label = "Friends Online" },
                { key = "groupButton",   label = "Group Button" },
            }

            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                leftRgn, 210, leftRgn:GetFrameLevel() + 2,
                EXTRA_BTN_ITEMS,
                function(k)
                    local m = MinimapDB(); if not m then return false end
                    local heb = m.hideExtraBtns
                    return heb and heb[k] and true or false
                end,
                function(k, v)
                    local m = MinimapDB(); if not m then return end
                    if not m.hideExtraBtns then m.hideExtraBtns = {} end
                    m.hideExtraBtns[k] = v
                    RefreshMinimap()
                end)
            local PP = EllesmereUI.PP
            PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
            leftRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Show Omnium Folio (expansion landing page button) | inline X/Y cog
        local omniumRow
        omniumRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Omnium Folio",
              tooltip="Show the expansion landing page (Omnium Folio) button at the bottom-left of the minimap. Use the cog to nudge its position.",
              getValue=function() local m = MinimapDB(); return m and m.showOmniumFolio ~= false end,
              setValue=function(v)
                  local m = MinimapDB(); if not m then return end
                  m.showOmniumFolio = v
                  RefreshMinimap()
              end },
            { type="slider", text="Omnium Folio Scale", min=0.5, max=1.5, step=0.05,
              getValue=function() local m = MinimapDB(); return (m and m.omniumFolioScale) or 0.75 end,
              setValue=function(v)
                  local m = MinimapDB(); if not m then return end
                  m.omniumFolioScale = v
                  RefreshMinimap()
              end });  y = y - h
        do
            local rgn = omniumRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Omnium Folio Position",
                rows = {
                    { type="slider", label="X", min=-200, max=200, step=1,
                      get=function() local m=MinimapDB(); return (m and m.omniumFolioX) or 0 end,
                      set=function(v) local m=MinimapDB(); if not m then return end m.omniumFolioX=v; RefreshMinimap() end },
                    { type="slider", label="Y", min=-200, max=200, step=1,
                      get=function() local m=MinimapDB(); return (m and m.omniumFolioY) or 0 end,
                      set=function(v) local m=MinimapDB(); if not m then return end m.omniumFolioY=v; RefreshMinimap() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end

        y = y - 10

        -- EXTRAS section header
        _, h = W:SectionHeader(parent, "EXTRAS", y);  y = y - h

        -- Row 1: Show Blizzard Elements | Scroll to Zoom
        local blizzElements = {
            { key = "zone",       label = "Zone",           hideKey = "hideZoneText" },
            { key = "clock",      label = "Clock",          hideKey = "showClock", direct = true },
            { key = "calendar",   label = "Calendar",       hideKey = "hideGameTime" },
            { key = "mail",       label = "Mail",           hideKey = "hideMail" },
            { key = "tracking",   label = "Tracking",       hideKey = "hideTrackingButton" },
            { key = "crafting",   label = "Crafting Order", hideKey = "hideCraftingOrder" },
            { key = "difficulty", label = "Difficulty",      hideKey = "hideRaidDifficulty" },
        }
        local blizzRow
        blizzRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Show Blizzard Elements",
              values={ ["_placeholder"]="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end },
            { type="toggle", text="Scroll to Zoom",
              getValue=function() local m = MinimapDB(); return m and m.scrollZoom end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.scrollZoom = v
                RefreshMinimap()
              end }); y = y - h
        do
            local rgn = blizzRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2,
                blizzElements,
                function(k)
                    local m = MinimapDB(); if not m then return false end
                    for _, el in ipairs(blizzElements) do
                        if el.key == k then
                            if el.direct then return m[el.hideKey] or false
                            else return not m[el.hideKey] end
                        end
                    end
                    return false
                end,
                function(k, v)
                    local m = MinimapDB(); if not m then return end
                    for _, el in ipairs(blizzElements) do
                        if el.key == k then
                            if el.direct then m[el.hideKey] = v
                            else m[el.hideKey] = not v end
                            break
                        end
                    end
                    RefreshMinimap()
                    EllesmereUI:RefreshPage()
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Row 2: Zone Inside | Location Scale (with cog: X/Y offset)
        local locScaleRow
        locScaleRow, h = W:DualRow(parent, y,
            { type="toggle", text="Zone Inside",
              tooltip="Display the zone text inside the minimap instead of below it",
              disabled=function() local m = MinimapDB(); return m and (m.hideZoneText) end,
              disabledTooltip="Zone in Show Blizzard Elements",
              getValue=function() local m = MinimapDB(); return m and m.zoneInside end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.zoneInside = v
                RefreshMinimap()
              end },
            { type="slider", text="Location Scale", min=0.5, max=2.0, step=0.01,
              disabled=function() local m = MinimapDB(); return m and (m.hideZoneText) end,
              disabledTooltip="Zone in Show Blizzard Elements",
              getValue=function() local m = MinimapDB(); return m and m.locationScale or 1.15 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.locationScale = v
                local bg = _G._EBS_LocationBg
                if bg then bg:SetScale(v) end
              end }
        );  y = y - h
        -- Inline cog on Location Scale for X/Y offset
        do
            local rgn = locScaleRow._rightRegion
            local function locOff()
                local m = MinimapDB(); return m and (m.hideZoneText)
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Location Position",
                rows = {
                    { type = "slider", label = "X Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.locationOffsetX or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.locationOffsetX = v
                          local bg = _G._EBS_LocationBg
                          if bg then
                              bg:ClearAllPoints()
                              local ly = m.locationOffsetY or 0
                              local baseY = m.zoneInside and 4 or (m.shape == "circle" or m.shape == "textured_circle") and 3 or -7
                              bg:SetPoint("BOTTOM", _G.Minimap, "BOTTOM", v, baseY + ly)
                          end
                      end },
                    { type = "slider", label = "Y Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.locationOffsetY or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.locationOffsetY = v
                          local bg = _G._EBS_LocationBg
                          if bg then
                              bg:ClearAllPoints()
                              local lx = m.locationOffsetX or 0
                              local baseY = m.zoneInside and 4 or (m.shape == "circle" or m.shape == "textured_circle") and 3 or -7
                              bg:SetPoint("BOTTOM", _G.Minimap, "BOTTOM", lx, baseY + v)
                          end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(locOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(locOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Zone in Show Blizzard Elements")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = locOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if locOff() then cogBlock:Show() else cogBlock:Hide() end
        end

        -- Row 3: Clock Inside | Clock Scale (with cog: X/Y offset)
        local clockScaleRow
        clockScaleRow, h = W:DualRow(parent, y,
            { type="toggle", text="Clock Inside",
              tooltip="Display the clock inside the minimap instead of above it",
              disabled=function() local m = MinimapDB(); return m and (not m.showClock) end,
              disabledTooltip="Clock in Show Blizzard Elements",
              getValue=function() local m = MinimapDB(); return m and m.clockInside end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.clockInside = v
                RefreshMinimap()
              end },
            { type="slider", text="Clock Scale", min=0.5, max=2.0, step=0.01,
              disabled=function() local m = MinimapDB(); return m and (not m.showClock) end,
              disabledTooltip="Clock in Show Blizzard Elements",
              getValue=function() local m = MinimapDB(); return m and m.clockScale or 1.15 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.clockScale = v
                local bg = _G._EBS_ClockBg
                if bg then bg:SetScale(v) end
              end }
        );  y = y - h
        -- Inline cog on Clock Scale for X/Y offset
        do
            local rgn = clockScaleRow._rightRegion
            local function clockOff()
                local m = MinimapDB(); return m and (not m.showClock)
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Clock Position",
                rows = {
                    { type = "slider", label = "X Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.clockOffsetX or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.clockOffsetX = v
                          local bg = _G._EBS_ClockBg
                          if bg then
                              bg:ClearAllPoints()
                              local cy = m.clockOffsetY or 0
                              local baseY = m.clockInside and -4 or (m.shape == "circle" or m.shape == "textured_circle") and -3 or 7
                              bg:SetPoint("TOP", _G.Minimap, "TOP", v, baseY + cy)
                          end
                      end },
                    { type = "slider", label = "Y Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.clockOffsetY or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.clockOffsetY = v
                          local bg = _G._EBS_ClockBg
                          if bg then
                              bg:ClearAllPoints()
                              local cx = m.clockOffsetX or 0
                              local baseY = m.clockInside and -4 or (m.shape == "circle" or m.shape == "textured_circle") and -3 or 7
                              bg:SetPoint("TOP", _G.Minimap, "TOP", cx, baseY + v)
                          end
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(clockOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(clockOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Clock in Show Blizzard Elements")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = clockOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if clockOff() then cogBlock:Show() else cogBlock:Hide() end
        end

        -- Row 4: Show Coordinates Below Map | (empty)
        local coordsRow
        coordsRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Coordinates Below Map",
              tooltip="Always display player coordinates centered below the minimap instead of only on hover.",
              getValue=function() local m = MinimapDB(); return m and m.coordsBelow end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.coordsBelow = v
                RefreshMinimap()
                EllesmereUI:RefreshPage()
              end },
            { type="toggle", text="Open Micro Menu on Middle Click",
              tooltip="Middle-click the minimap to open the EllesmereUI micro menu. When off, middle-click does nothing.",
              getValue=function() local m = MinimapDB(); return m and m.openMicroMenuOnMiddleClick ~= false end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.openMicroMenuOnMiddleClick = v
              end }
        );  y = y - h
        -- Inline cog on Coordinates for X/Y offset
        do
            local rgn = coordsRow._leftRegion
            local function coordsOff()
                local m = MinimapDB(); return not (m and m.coordsBelow)
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Coordinates Position",
                rows = {
                    { type = "slider", label = "X Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.coordsBelowOffsetX or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.coordsBelowOffsetX = v
                          RefreshMinimap()
                      end },
                    { type = "slider", label = "Y Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.coordsBelowOffsetY or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.coordsBelowOffsetY = v
                          RefreshMinimap()
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -9, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(coordsOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(coordsOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Show Coordinates Below Map")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = coordsOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if coordsOff() then cogBlock:Show() else cogBlock:Hide() end
        end


        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIMinimap", {
        title       = "Minimap",
        description = "Custom minimap skin and layout.",
        pages       = { "Minimap" },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == "Minimap" then return BuildMinimapPage(pageName, parent, yOffset) end
        end,
        onReset = function()
            if _G._EMM_DB and _G._EMM_DB.ResetProfile then
                _G._EMM_DB:ResetProfile()
            end
            EllesmereUI:InvalidatePageCache()
            if _G._EMM_ApplyMinimap then _G._EMM_ApplyMinimap() end
        end,
    })

    SLASH_EMM1 = "/emm"
    SlashCmdList.EMM = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIMinimap")
    end
end)
