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
        local visRow, visH = EllesmereUI.BuildVisibilityModeRow(W, parent, y,
            { getStore = getCfg, legacyKey = "visibility",
              caps = { partyIncludesRaid = false, luaDragonriding = true },
              onChanged = function()
                  if refreshFn then refreshFn() end
                  if _G._EBS_UpdateVisibility then _G._EBS_UpdateVisibility() end
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
    --  Chat Page
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Minimap Page
    ---------------------------------------------------------------------------
    local function BuildMinimapPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        parent._showRowDivider = true
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
            { type="slider", text="Interactable Button Size", min=16, max=40, step=1,
              tooltip="Size of mail, calendar, tracking, and minimap button group toggle",
              getValue=function() local m = MinimapDB(); return m and m.interactableBtnSize or 21 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.interactableBtnSize = v
                RefreshMinimap()
              end })
        y = y - h

        h = BuildVisibilityRow(W, parent, y, MinimapDB, RefreshMinimap);  y = y - h

        -- Shape | Button Backgrounds
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

        -- Border Style (+ offset cog) | Border Size (+ class/custom swatches)
        local texValues, texOrder = EllesmereUI.GetBorderTextureDropdown()
        local borderRow
        borderRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Border Style",
              values=texValues, order=texOrder,
              disabled=function() local m = MinimapDB(); return m and (m.shape or "square") ~= "square" end,
              disabledTooltip="Square Shape",
              getValue=function() local m = MinimapDB(); return (m and m.borderTexture) or "solid" end,
              setValue=function(v)
                  local m = MinimapDB(); if not m then return end
                  m.borderTexture = v
                  m.borderTextureOffset = nil
                  m.borderTextureOffsetY = nil
                  m.borderTextureShiftX = nil
                  m.borderTextureShiftY = nil
                  local _bcol, _bbehind = EllesmereUI.GetBorderStyleSelectDefaults(v)
                  m.borderColor = _bcol
                  m.borderA = 1
                  m.borderBehind = _bbehind
                  m.borderUseClassColor = false
                  m.useClassColor = false
                  local defSz = EllesmereUI.GetBorderDefaultSize("minimap", v)
                  if defSz then m.borderSize = defSz end
                  RefreshMinimap()
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Border Size", min=0, max=4, step=1, trackWidth=120,
              getValue=function() local m = MinimapDB(); return m and m.borderSize or 1 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.borderSize = v
                RefreshMinimap()
              end }
        );  y = y - h
        -- Inline cog for border offset (left region); only shown for textured styles
        do
            local rgn = borderRow._leftRegion
            local function BorderTex()
                local m = MinimapDB(); return (m and m.borderTexture) or "solid"
            end
            local function BorderSz()
                local m = MinimapDB(); return (m and m.borderSize) or 1
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Border Offset",
                rows = {
                    { type = "slider", label = "Offset X", min = -10, max = 10, step = 1,
                      get = function()
                          local m = MinimapDB()
                          local v = m and m.borderTextureOffset
                          if v then return v end
                          local dox = EllesmereUI.GetBorderDefaults("minimap", BorderTex(), BorderSz())
                          return dox
                      end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.borderTextureOffset = v
                          RefreshMinimap()
                      end },
                    { type = "slider", label = "Offset Y", min = -10, max = 10, step = 1,
                      get = function()
                          local m = MinimapDB()
                          local v = m and m.borderTextureOffsetY
                          if v then return v end
                          local _, doy = EllesmereUI.GetBorderDefaults("minimap", BorderTex(), BorderSz())
                          return doy
                      end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.borderTextureOffsetY = v
                          RefreshMinimap()
                      end },
                    { type = "slider", label = "Shift X", min = -10, max = 10, step = 1,
                      get = function()
                          local m = MinimapDB()
                          local v = m and m.borderTextureShiftX
                          if v then return v end
                          local _, _, dsx = EllesmereUI.GetBorderDefaults("minimap", BorderTex(), BorderSz())
                          return dsx
                      end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.borderTextureShiftX = (v ~= 0) and v or nil
                          RefreshMinimap()
                      end },
                    { type = "slider", label = "Shift Y", min = -10, max = 10, step = 1,
                      get = function()
                          local m = MinimapDB()
                          local v = m and m.borderTextureShiftY
                          if v then return v end
                          local _, _, _, dsy = EllesmereUI.GetBorderDefaults("minimap", BorderTex(), BorderSz())
                          return dsy
                      end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.borderTextureShiftY = (v ~= 0) and v or nil
                          RefreshMinimap()
                      end },
                    { type = "toggle", label = "Show Behind",
                      get = function() local m = MinimapDB(); return (m and m.borderBehind) or false end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.borderBehind = v
                          RefreshMinimap()
                          EllesmereUI:RefreshPage()
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
            cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
            local function UpdateCogVis()
                local m = MinimapDB()
                local square = not m or (m.shape or "square") == "square"
                if square and BorderTex() ~= "solid" then cogBtn:Show() else cogBtn:Hide() end
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateCogVis)
            UpdateCogVis()
        end
        -- Inline accent + class + custom colour swatches on the Border Size
        -- slider. Modes are mutually exclusive: class > accent > custom.
        do
            local rgn = borderRow._rightRegion
            local PPl = EllesmereUI.PP

            -- Accent swatch (nearest the control): live theme accent.
            local accentSwatch, updateAccent = EllesmereUI.BuildColorSwatch(
                rgn, borderRow:GetFrameLevel() + 3,
                function()
                    local ar, ag, ab = EllesmereUI.GetAccentColor()
                    return ar, ag, ab, 1
                end,
                function() end, false, 18)
            accentSwatch:SetScript("OnClick", function()
                local m = MinimapDB(); if not m then return end
                m.useClassColor = true
                m.borderUseClassColor = false
                RefreshMinimap()
                EllesmereUI:RefreshPage()
            end)
            PPl.Point(accentSwatch, "RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = accentSwatch

            -- Class-colour swatch (to the left of accent): live player class colour.
            local classSwatch, updateClass = EllesmereUI.BuildColorSwatch(
                rgn, borderRow:GetFrameLevel() + 3,
                function()
                    local cc = EllesmereUI.GetClassColor and EllesmereUI.GetClassColor(select(2, UnitClass("player")))
                    if cc then return cc.r, cc.g, cc.b, 1 end
                    return 1, 1, 1, 1
                end,
                function() end, false, 18)
            classSwatch:SetScript("OnClick", function()
                local m = MinimapDB(); if not m then return end
                m.borderUseClassColor = true
                m.useClassColor = false
                RefreshMinimap()
                EllesmereUI:RefreshPage()
            end)
            PPl.Point(classSwatch, "RIGHT", rgn._lastInline, "LEFT", -8, 0)
            rgn._lastInline = classSwatch

            -- Custom-colour swatch (outermost): stored custom colour.
            local customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(
                rgn, borderRow:GetFrameLevel() + 3,
                function()
                    local m = MinimapDB()
                    local c = m and m.borderColor
                    if c then return c.r, c.g, c.b, (m.borderA) or 1 end
                    -- Legacy: pre-style users' border colour keys
                    if m then return m.borderR or 0, m.borderG or 0, m.borderB or 0, m.borderA or 1 end
                    return 0, 0, 0, 1
                end,
                function(r, g, b, a)
                    local m = MinimapDB(); if not m then return end
                    m.borderColor = { r = r, g = g, b = b }
                    m.borderA = a
                    RefreshMinimap()
                end,
                true, 18)
            -- Preserve BuildColorSwatch's picker click, but while class or accent
            -- mode is on a click just switches back to custom mode instead.
            local openPicker = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self)
                local m = MinimapDB()
                if m and (m.borderUseClassColor or m.useClassColor) then
                    m.borderUseClassColor = false
                    m.useClassColor = false
                    RefreshMinimap()
                    EllesmereUI:RefreshPage()
                    return
                end
                if openPicker then openPicker(self) end
            end)
            PPl.Point(customSwatch, "RIGHT", rgn._lastInline, "LEFT", -8, 0)
            rgn._lastInline = customSwatch

            accentSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(accentSwatch, "Accent Color") end)
            accentSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            classSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(classSwatch, "Class Color") end)
            classSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            customSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color") end)
            customSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            local function UpdateState()
                if updateAccent then updateAccent() end
                if updateClass then updateClass() end
                if updateCustom then updateCustom() end
                local m = MinimapDB()
                local useClass = m and m.borderUseClassColor
                local useAccent = (not useClass) and m and m.useClassColor
                accentSwatch:SetAlpha(useAccent and 1 or 0.3)
                classSwatch:SetAlpha(useClass and 1 or 0.3)
                customSwatch:SetAlpha((useClass or useAccent) and 0.3 or 1)
            end
            EllesmereUI.RegisterWidgetRefresh(UpdateState)
            UpdateState()
        end

        -- Free Move Buttons | (empty)
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
            { type="label", text="" }
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

        y = y - 10

        -- MINIMAP & QOL BUTTONS section header
        _, h = W:SectionHeader(parent, "MINIMAP & QOL BUTTONS", y);  y = y - h

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

            -- Build items from currently collected minimap buttons. Ungrouped
            -- buttons come first in their stored drag order (legacy boolean
            -- entries sort last among them), the rest alphabetically.
            local function GetUngroupItems()
                local items = {}
                local btns = _G._EBS_CachedAddonButtons or {}
                local vis = _G._EBS_AddonVisible or {}
                local m = MinimapDB()
                local ug = m and m.ungroupedButtons or {}
                for _, btn in ipairs(btns) do
                    local name = btn:GetName()
                    if name and vis[btn] ~= false then
                        local label = name:gsub("^LibDBIcon10_", ""):gsub("^Lib_GPI_Minimap_", ""):gsub("MinimapButton$", ""):gsub("_MinimapButton$", "")
                        items[#items + 1] = { key = name, label = label }
                    end
                end
                local function OrderOf(key)
                    local v = ug[key]
                    if type(v) == "number" then return v end
                    if v then return math.huge end
                    return nil
                end
                table.sort(items, function(a, b)
                    local oa, ob = OrderOf(a.key), OrderOf(b.key)
                    if oa and ob then
                        if oa ~= ob then return oa < ob end
                        return a.label < b.label
                    end
                    if oa then return true end
                    if ob then return false end
                    return a.label < b.label
                end)
                return items
            end

            local cbDD, cbDDRefresh = EllesmereUI.BuildReorderCBDropdown(
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
                end,
                {
                    hint = "Drag to Reorder Buttons",
                    setOrder = function(orderedKeys)
                        local m = MinimapDB(); if not m or not m.ungroupedButtons then return end
                        -- Renumber only the ungrouped entries; unticked rows
                        -- have no stored order.
                        for i, k in ipairs(orderedKeys) do
                            if m.ungroupedButtons[k] then m.ungroupedButtons[k] = i end
                        end
                        FullRebuildMinimap()
                    end,
                })
            local PP = EllesmereUI.PP
            PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
            leftRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- Show Extra Buttons (checkbox dropdown with drag-to-reorder)
        local extraBtnRow
        extraBtnRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Show Extra Buttons",
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

            -- Checked = shown (stored inverted in hideExtraBtns, so existing
            -- profiles carry over with no migration). Movable rows follow the
            -- saved extraBtnOrder; the Group Button anchors the row and is
            -- checkbox-only.
            local EXTRA_BTN_LABELS = {
                greatVault    = "Great Vault",
                friendsOnline = "Friends Online",
                portals       = "M+ Portals",
            }
            local EXTRA_BTN_DEFAULT_ORDER = { "greatVault", "friendsOnline", "portals" }
            local function GetExtraBtnItems()
                local m = MinimapDB()
                local order = m and m.extraBtnOrder
                local items, added = {}, {}
                if type(order) == "table" then
                    for _, k in ipairs(order) do
                        if EXTRA_BTN_LABELS[k] and not added[k] then
                            added[k] = true
                            items[#items + 1] = { key = k, label = EXTRA_BTN_LABELS[k] }
                        end
                    end
                end
                for _, k in ipairs(EXTRA_BTN_DEFAULT_ORDER) do
                    if not added[k] then
                        items[#items + 1] = { key = k, label = EXTRA_BTN_LABELS[k] }
                    end
                end
                items[#items + 1] = { key = "groupButton", label = "Group Button", fixed = true }
                return items
            end

            local cbDD, cbDDRefresh = EllesmereUI.BuildReorderCBDropdown(
                leftRgn, 210, leftRgn:GetFrameLevel() + 2,
                GetExtraBtnItems(),
                function(k)
                    local m = MinimapDB(); if not m then return true end
                    local heb = m.hideExtraBtns
                    return not (heb and heb[k])
                end,
                function(k, v)
                    local m = MinimapDB(); if not m then return end
                    if not m.hideExtraBtns then m.hideExtraBtns = {} end
                    m.hideExtraBtns[k] = not v
                    RefreshMinimap()
                end,
                {
                    hint = "Drag to Reorder Buttons",
                    setOrder = function(orderedKeys)
                        local m = MinimapDB(); if not m then return end
                        local t = {}
                        for i, k in ipairs(orderedKeys) do t[i] = k end
                        m.extraBtnOrder = t
                        RefreshMinimap()
                    end,
                })
            local PP = EllesmereUI.PP
            PP.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
            leftRgn._control = cbDD
            leftRgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -- M+ Portals Scale | Open Micro Menu on Middle Click
        _, h = W:DualRow(parent, y,
            { type="slider", text="M+ Portals Scale", min=0.5, max=2.0, step=0.01,
              tooltip="Scales the M+ Portals flyout the portals button opens.",
              getValue=function() local m = MinimapDB(); return m and m.extraFlyoutScale or 1.0 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.extraFlyoutScale = v
              end },
            { type="toggle", text="Open Micro Menu on Middle Click",
              tooltip="Middle-click the minimap to open the EllesmereUI micro menu. When off, middle-click does nothing.",
              getValue=function() local m = MinimapDB(); return m and m.openMicroMenuOnMiddleClick ~= false end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.openMicroMenuOnMiddleClick = v
              end }
        );  y = y - h

        -- Friends Tooltip Cap | Custom Tooltip Size
        _, h = W:DualRow(parent, y,
            { type="slider", text="Friends Tooltip Cap", min=0, max=30, step=1,
              tooltip="Max rows per section in the Friends Online tooltip (0 = the 30-row max).",
              getValue=function() local m = MinimapDB(); return m and m.friendsMaxRows or 0 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.friendsMaxRows = v
              end },
            { type="slider", text="Custom Tooltip Size", min=0.5, max=2.0, step=0.01,
              tooltip="Scales the custom tooltips shown by the unique minimap buttons (Great Vault, friends, calendar, mail, tracking).",
              getValue=function() local m = MinimapDB(); return m and m.customTooltipScale or 1.0 end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.customTooltipScale = v
              end }
        );  y = y - h

        -- Shared row-position choices (QoL button row + Blizzard element row).
        -- The two rows are mutually exclusive per position: a value picked on
        -- one dropdown is disabled on the other.
        local ROW_POS_VALUES = {
            blUp = "Bottom Left, Grow Up", blRight = "Bottom Left, Grow Right",
            tlDown = "Top Left, Grow Down", tlRight = "Top Left, Grow Right",
            brUp = "Bottom Right, Grow Up", brLeft = "Bottom Right, Grow Left",
            trLeft = "Top Right, Grow Left", trDown = "Top Right, Grow Down",
        }
        local ROW_POS_ORDER = { "blUp", "blRight", "tlDown", "tlRight", "brUp", "brLeft", "trLeft", "trDown" }
        local function BtnRowPos()
            local m = MinimapDB(); return (m and m.btnRowPosition) or "blUp"
        end
        local function ElementRowPos()
            local m = MinimapDB(); return (m and m.elementRowPosition) or "tlDown"
        end

        -- Button Row Position (+ spacing cog) | (empty)
        local btnRowRow
        btnRowRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Button Row Position",
              tooltip="Which minimap corner the button row builds out from and the direction it grows.",
              values = ROW_POS_VALUES, order = ROW_POS_ORDER,
              itemDisabled=function(val) return val == ElementRowPos() end,
              itemDisabledTooltip=function(val)
                  if val == ElementRowPos() then return "Already used by Element Row Position" end
              end,
              getValue=BtnRowPos,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.btnRowPosition = v
                RefreshMinimap()
              end },
            { type="label", text="" }
        );  y = y - h
        -- Inline cog on Button Row Position for icon spacing
        do
            local rgn = btnRowRow._leftRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Button Row Settings",
                rows = {
                    { type = "slider", pixel = true, label = "Icon Spacing", min = -20, max = 40, step = 1,
                      get = function() local m = MinimapDB(); return m and m.btnRowSpacing or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.btnRowSpacing = v
                          RefreshMinimap()
                      end },
                    { type = "slider", label = "Distance from Map", min = -20, max = 60, step = 1,
                      get = function() local m = MinimapDB(); return m and m.btnRowDistance or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.btnRowDistance = v
                          RefreshMinimap()
                      end },
                    { type = "dropdown", label = "Grow Tooltip/Popup",
                      values = { auto = "Auto", up = "Up", down = "Down", left = "Left", right = "Right" },
                      order = { "auto", "up", "down", "left", "right" },
                      get = function() local m = MinimapDB(); return (m and m.flyoutGrowDir) or "auto" end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.flyoutGrowDir = v
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
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
        end

        y = y - 10

        -- BLIZZARD ELEMENTS section header
        _, h = W:SectionHeader(parent, "BLIZZARD ELEMENTS", y);  y = y - h

        -- Show Omnium Folio (expansion landing page button) | inline X/Y cog
        -- Legacy fallback mirrors the runtime: pre-dropdown data carries the
        -- showOmniumFolio toggle (default ON; only false is ever stored).
        local function OmniumMode()
            local m = MinimapDB()
            if not m then return "always" end
            if m.omniumFolioMode then return m.omniumFolioMode end
            if m.showOmniumFolio == false then return "never" end
            return "always"
        end
        local omniumRow
        omniumRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Show Omnium Folio",
              tooltip="Show the expansion landing page (Omnium Folio) button on the minimap. Use the cog to choose its corner and nudge its position.",
              values = { never = "Never", hover = "On Hover", always = "Always" },
              order  = { "never", "hover", "always" },
              getValue=OmniumMode,
              setValue=function(v)
                  local m = MinimapDB(); if not m then return end
                  m.omniumFolioMode = v
                  RefreshMinimap()
                  EllesmereUI:RefreshPage()
              end },
            { type="slider", text="Omnium Folio Scale", min=0.5, max=1.5, step=0.05,
              disabled=function() return OmniumMode() == "never" end,
              disabledTooltip="Show Omnium Folio",
              getValue=function() local m = MinimapDB(); return (m and m.omniumFolioScale) or 0.75 end,
              setValue=function(v)
                  local m = MinimapDB(); if not m then return end
                  m.omniumFolioScale = v
                  RefreshMinimap()
              end });  y = y - h
        do
            local rgn = omniumRow._leftRegion
            local function omniumOff() return OmniumMode() == "never" end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Omnium Folio Position",
                rows = {
                    { type="dropdown", label="Corner",
                      values={ ["BOTTOMLEFT"]="Bottom Left", ["BOTTOMRIGHT"]="Bottom Right", ["TOPLEFT"]="Top Left", ["TOPRIGHT"]="Top Right" },
                      order={ "BOTTOMLEFT", "BOTTOMRIGHT", "TOPLEFT", "TOPRIGHT" },
                      get=function() local m=MinimapDB(); return (m and m.omniumFolioCorner) or "BOTTOMLEFT" end,
                      set=function(v) local m=MinimapDB(); if not m then return end m.omniumFolioCorner=v; RefreshMinimap() end },
                    -- "X Offset" / "Y Offset" (not "X" / "Y"): labels under ~10px wide make
                    -- BuildCogPopup fall back to a 60px label column, which left the old cog
                    -- with a big gap before the sliders. Longer labels avoid that fallback.
                    { type="slider", label="X Offset", min=-1000, max=1000, step=1,
                      get=function() local m=MinimapDB(); return (m and m.omniumFolioX) or 0 end,
                      set=function(v) local m=MinimapDB(); if not m then return end m.omniumFolioX=v; RefreshMinimap() end },
                    { type="slider", label="Y Offset", min=-1000, max=1000, step=1,
                      get=function() local m=MinimapDB(); return (m and m.omniumFolioY) or 0 end,
                      set=function(v) local m=MinimapDB(); if not m then return end m.omniumFolioY=v; RefreshMinimap() end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(omniumOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(s) s:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(s) s:SetAlpha(omniumOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(s) cogShow(s) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Show Omnium Folio")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = omniumOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if omniumOff() then cogBlock:Show() else cogBlock:Hide() end
        end

        -- Show Blizzard Elements | Scroll to Zoom
        local blizzElements = {
            { key = "calendar",   label = "Calendar",       hideKey = "hideGameTime" },
            { key = "mail",       label = "Mail",           hideKey = "hideMail" },
            { key = "tracking",   label = "Tracking",       hideKey = "hideTrackingButton" },
            { key = "crafting",   label = "Crafting Order", hideKey = "hideCraftingOrder" },
            { key = "difficulty", label = "Difficulty",      hideKey = "hideRaidDifficulty",
              -- Overridden while the difficulty shows as text (Text section)
              lockedFn = function() local m = MinimapDB(); return (m and m.diffTextEnabled) or false end },
            { key = "zoom",       label = "Zoom +/- Icons", hideKey = "hideZoomButtons" },
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

        -- Element Row Position (+ spacing cog) | (empty)
        local elRowRow
        elRowRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Element Row Position",
              tooltip="Which minimap corner the Blizzard element row (tracking, calendar, mail, crafting) builds out from and the direction it grows.",
              values = ROW_POS_VALUES, order = ROW_POS_ORDER,
              disabled=function() local m = MinimapDB(); return m and (m.shape or "square") ~= "square" end,
              disabledTooltip="Square Shape",
              itemDisabled=function(val) return val == BtnRowPos() end,
              itemDisabledTooltip=function(val)
                  if val == BtnRowPos() then return "Already used by Button Row Position" end
              end,
              getValue=ElementRowPos,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.elementRowPosition = v
                RefreshMinimap()
              end },
            { type="dropdown", text="Mail Position",
              values = { button = "Minimap Button", TOPRIGHT = "Top Right", TOPLEFT = "Top Left",
                         BOTTOMRIGHT = "Bottom Right", BOTTOMLEFT = "Bottom Left" },
              order = { "button", "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT" },
              disabled=function() local m = MinimapDB(); return m and m.hideMail end,
              disabledTooltip="Mail in Show Blizzard Elements",
              getValue=function() local m = MinimapDB(); return m and m.mailPosition or "button" end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.mailPosition = v
                RefreshMinimap()
                EllesmereUI:RefreshPage()
              end }
        );  y = y - h
        -- Inline offset cog on Mail Position (corner modes only)
        do
            local rgn = elRowRow._rightRegion
            local function mailOff()
                local m = MinimapDB()
                return not m or m.hideMail or (m.mailPosition or "button") == "button"
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Mail Position",
                rows = {
                    { type = "slider", label = "X Offset", min = -100, max = 100, step = 1,
                      get = function() local m = MinimapDB(); return m and m.mailOffsetX or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.mailOffsetX = v
                          RefreshMinimap()
                      end },
                    { type = "slider", label = "Y Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.mailOffsetY or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.mailOffsetY = v
                          RefreshMinimap()
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(mailOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.DIRECTIONS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(mailOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function()
                local m = MinimapDB()
                local req = (m and m.hideMail) and "Mail in Show Blizzard Elements" or "a Mail Position corner"
                EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip(req))
            end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = mailOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if mailOff() then cogBlock:Show() else cogBlock:Hide() end
        end
        -- Inline cog on Element Row Position for icon spacing
        do
            local rgn = elRowRow._leftRegion
            local function elOff()
                local m = MinimapDB(); return m and (m.shape or "square") ~= "square"
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Element Row Spacing",
                rows = {
                    { type = "slider", pixel = true, label = "Icon Spacing", min = -20, max = 40, step = 1,
                      get = function() local m = MinimapDB(); return m and m.elementRowSpacing or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.elementRowSpacing = v
                          RefreshMinimap()
                      end },
                    { type = "slider", label = "Distance from Map", min = -20, max = 60, step = 1,
                      get = function() local m = MinimapDB(); return m and m.elementRowDistance or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.elementRowDistance = v
                          RefreshMinimap()
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(elOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(elOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Square Shape")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = elOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if elOff() then cogBlock:Show() else cogBlock:Hide() end
        end

        y = y - 10

        -- TEXT section header
        _, h = W:SectionHeader(parent, "TEXT", y);  y = y - h

        -- Shared anchor-position choices (clock, zone text, coordinates)
        local MAP_POS_VALUES = {
            belowMap = "Below Map", aboveMap = "Above Map",
            topLeft = "Top Left", top = "Top", topRight = "Top Right",
            left = "Left", right = "Right",
            bottomLeft = "Bottom Left", bottom = "Bottom", bottomRight = "Bottom Right",
        }
        local MAP_POS_ORDER = { "belowMap", "aboveMap", "topLeft", "top", "topRight", "left", "right", "bottomLeft", "bottom", "bottomRight" }

        -- Clock Style | Clock Position (with cog: Scale + X/Y offset)
        -- Legacy fallback mirrors the runtime: pre-dropdown data carries the
        -- clockInside toggle (defaulted ON) and the removed Show Blizzard
        -- Elements Clock checkbox (showClock == false meant hidden).
        local function ClockMode()
            local m = MinimapDB()
            if not m then return "inside" end
            if m.clockMode ~= nil then return m.clockMode end
            if m.showClock == false then return "none" end
            return (m.clockInside == false) and "edge" or "inside"
        end
        local clockRow
        clockRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Clock Style",
              values = { none = "None", inside = "Inside Map", edge = "Edge Box" },
              order  = { "none", "inside", "edge" },
              getValue=ClockMode,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.clockMode = v
                RefreshMinimap()
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Clock Position",
              values = MAP_POS_VALUES, order = MAP_POS_ORDER,
              disabled=function() return ClockMode() == "none" end,
              disabledTooltip="Clock Style",
              getValue=function() local m = MinimapDB(); return m and m.clockPosition or "top" end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.clockPosition = v
                RefreshMinimap()
              end }
        );  y = y - h
        -- Inline cog on Clock Position for scale + X/Y offset
        do
            local rgn = clockRow._rightRegion
            local function clockOff()
                return ClockMode() == "none"
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Clock Size and Position",
                rows = {
                    { type = "slider", label = "Scale", min = 0.5, max = 2.0, step = 0.01,
                      get = function() local m = MinimapDB(); return m and m.clockScale or 1.15 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.clockScale = v
                          local bg = _G._EBS_ClockBg
                          if bg then bg:SetScale(v) end
                      end },
                    { type = "slider", label = "X Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.clockOffsetX or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.clockOffsetX = v
                          RefreshMinimap()
                      end },
                    { type = "slider", label = "Y Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.clockOffsetY or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.clockOffsetY = v
                          RefreshMinimap()
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
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(clockOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Clock Style")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = clockOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if clockOff() then cogBlock:Show() else cogBlock:Hide() end
        end

        -- Zone Text Style | Zone Position (with cog: Scale + X/Y offset)
        -- Legacy fallback mirrors the runtime: pre-dropdown data carries the
        -- zoneInside toggle (defaulted OFF) and the removed Show Blizzard
        -- Elements Zone checkbox (hideZoneText == true meant hidden).
        local function LocationMode()
            local m = MinimapDB()
            if not m then return "inside" end
            if m.locationMode ~= nil then return m.locationMode end
            if m.hideZoneText == true then return "none" end
            return m.zoneInside and "inside" or "edge"
        end
        local zoneRow
        zoneRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Zone Text Style",
              values = { none = "None", inside = "Inside Map", edge = "Edge Box" },
              order  = { "none", "inside", "edge" },
              getValue=LocationMode,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.locationMode = v
                RefreshMinimap()
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Zone Position",
              values = MAP_POS_VALUES, order = MAP_POS_ORDER,
              disabled=function() return LocationMode() == "none" end,
              disabledTooltip="Zone Text Style",
              getValue=function() local m = MinimapDB(); return m and m.locationPosition or "bottom" end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.locationPosition = v
                RefreshMinimap()
              end }
        );  y = y - h
        -- Inline cog on Zone Text Style: reactive zone coloring
        do
            local rgn = zoneRow._leftRegion
            local function styleOff()
                return LocationMode() == "none"
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Zone Text Settings",
                rows = {
                    { type = "toggle", label = "Display Sub Zone",
                      get = function() local m = MinimapDB(); return m and m.zoneShowSubZone or false end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.zoneShowSubZone = v
                          RefreshMinimap()
                      end },
                    { type = "toggle", label = "Reactive Coloring",
                      get = function() local m = MinimapDB(); return m and m.zoneReactiveColor or false end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.zoneReactiveColor = v
                          RefreshMinimap()
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = cogBtn
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(styleOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.COGS_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(styleOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Zone Text Style")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = styleOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if styleOff() then cogBlock:Show() else cogBlock:Hide() end
        end
        -- Inline cog on Zone Position for scale + X/Y offset
        do
            local rgn = zoneRow._rightRegion
            local function locOff()
                return LocationMode() == "none"
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Zone Text Size and Position",
                rows = {
                    { type = "slider", label = "Scale", min = 0.5, max = 2.0, step = 0.01,
                      get = function() local m = MinimapDB(); return m and m.locationScale or 1.15 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.locationScale = v
                          local bg = _G._EBS_LocationBg
                          if bg then bg:SetScale(v) end
                      end },
                    { type = "slider", label = "X Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.locationOffsetX or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.locationOffsetX = v
                          RefreshMinimap()
                      end },
                    { type = "slider", label = "Y Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.locationOffsetY or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.locationOffsetY = v
                          RefreshMinimap()
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
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(locOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Zone Text Style")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = locOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if locOff() then cogBlock:Show() else cogBlock:Hide() end
        end

        -- Show Coordinates | Coordinates Position (with cog: X/Y offset)
        -- Legacy fallback mirrors the runtime: pre-dropdown data only carries
        -- coordsBelow (true = always-on below the map).
        local function CoordsMode()
            local m = MinimapDB()
            if not m then return "always" end
            return m.coordsMode or (m.coordsBelow and "always") or "always"
        end
        local coordsRow
        coordsRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Show Coordinates",
              values = { never = "Never", hover = "On Hover", always = "Always" },
              order  = { "never", "hover", "always" },
              getValue=CoordsMode,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.coordsMode = v
                RefreshMinimap()
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Coordinates Position",
              values = MAP_POS_VALUES, order = MAP_POS_ORDER,
              disabled=function() return CoordsMode() == "never" end,
              disabledTooltip="Show Coordinates",
              getValue=function()
                local m = MinimapDB()
                if not m then return "topLeft" end
                return m.coordsPosition or (m.coordsBelow and "belowMap") or "topLeft"
              end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.coordsPosition = v
                RefreshMinimap()
              end }
        );  y = y - h
        -- Inline cog on Coordinates Position for X/Y offset
        do
            local rgn = coordsRow._rightRegion
            local function coordsOff() return CoordsMode() == "never" end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Coordinates Size and Position",
                rows = {
                    { type = "slider", label = "Scale", min = 0.5, max = 2.0, step = 0.01,
                      get = function() local m = MinimapDB(); return m and m.coordsScale or 1.0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.coordsScale = v
                          local cf = _G._EBS_CoordFrame
                          if cf then cf:SetScale(v) end
                      end },
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
            cogBtn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(coordsOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(coordsOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Show Coordinates")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = coordsOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if coordsOff() then cogBlock:Show() else cogBlock:Hide() end
        end

        -- Show FPS/MS (+ swatch + cog, mirrors QoL Show FPS Counter) | FPS/MS Position (+ offset cog)
        local function FpsOff()
            local m = MinimapDB(); return not (m and m.showFPS)
        end
        local fpsRow
        fpsRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show FPS/MS",
              getValue=function() local m = MinimapDB(); return m and m.showFPS or false end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.showFPS = v
                RefreshMinimap()
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="FPS/MS Position",
              values = MAP_POS_VALUES, order = MAP_POS_ORDER,
              disabled=FpsOff,
              disabledTooltip="Show FPS/MS",
              getValue=function() local m = MinimapDB(); return m and m.fpsPosition or "bottomLeft" end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.fpsPosition = v
                RefreshMinimap()
              end }
        );  y = y - h
        -- Inline cog on Show FPS/MS (text size + which MS readouts show).
        -- The description-colour swatches live on the Accented Text row at
        -- the bottom of this section.
        do
            local leftRgn = fpsRow._leftRegion

            local _, fpsCogShow = EllesmereUI.BuildCogPopup({
                title = "FPS/MS Settings",
                rows = {
                    { type="slider", label="Text Size", min=8, max=30, step=1,
                      get=function() local m = MinimapDB(); return m and m.fpsTextSize or 12 end,
                      set=function(v)
                          local m = MinimapDB(); if not m then return end
                          m.fpsTextSize = v
                          RefreshMinimap()
                      end },
                    { type="toggle", label="Show Local MS",
                      get=function()
                          local m = MinimapDB()
                          local sl = m and m.fpsShowLocalMS
                          if sl == nil then return true end
                          return sl
                      end,
                      set=function(v)
                          local m = MinimapDB(); if not m then return end
                          m.fpsShowLocalMS = v
                          RefreshMinimap()
                      end },
                    { type="toggle", label="Show World MS",
                      get=function() local m = MinimapDB(); return m and m.fpsShowWorldMS or false end,
                      set=function(v)
                          local m = MinimapDB(); if not m then return end
                          m.fpsShowWorldMS = v
                          RefreshMinimap()
                      end },
                    { type="slider", label="Update Interval", min=1, max=5, step=1,
                      get=function() local m = MinimapDB(); return m and m.fpsUpdateInterval or 3 end,
                      set=function(v)
                          local m = MinimapDB(); if not m then return end
                          m.fpsUpdateInterval = v
                          RefreshMinimap()
                      end },
                },
            })
            local fpsCogBtn = CreateFrame("Button", nil, leftRgn)
            fpsCogBtn:SetSize(26, 26)
            fpsCogBtn:SetPoint("RIGHT", leftRgn._lastInline or leftRgn._control, "LEFT", -9, 0)
            leftRgn._lastInline = fpsCogBtn
            fpsCogBtn:SetFrameLevel(leftRgn:GetFrameLevel() + 5)
            fpsCogBtn:SetAlpha(FpsOff() and 0.15 or 0.4)
            local fpsCogTex = fpsCogBtn:CreateTexture(nil, "OVERLAY")
            fpsCogTex:SetAllPoints()
            fpsCogTex:SetTexture(EllesmereUI.COGS_ICON)
            fpsCogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            fpsCogBtn:SetScript("OnLeave", function(self) self:SetAlpha(FpsOff() and 0.15 or 0.4) end)
            fpsCogBtn:SetScript("OnClick", function(self) fpsCogShow(self) end)
            local fpsCogBlock = CreateFrame("Frame", nil, fpsCogBtn)
            fpsCogBlock:SetAllPoints(); fpsCogBlock:SetFrameLevel(fpsCogBtn:GetFrameLevel() + 10); fpsCogBlock:EnableMouse(true)
            fpsCogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(fpsCogBtn, EllesmereUI.DisabledTooltip("Show FPS/MS")) end)
            fpsCogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = FpsOff()
                fpsCogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then fpsCogBlock:Show() else fpsCogBlock:Hide() end
            end)
            if FpsOff() then fpsCogBlock:Show() else fpsCogBlock:Hide() end
        end
        -- Inline offset cog on FPS/MS Position
        do
            local rgn = fpsRow._rightRegion
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "FPS/MS Size and Position",
                rows = {
                    { type = "slider", label = "Scale", min = 0.5, max = 2.0, step = 0.01,
                      get = function() local m = MinimapDB(); return m and m.fpsScale or 1.0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.fpsScale = v
                          local fb = _G._EBS_FpsBg
                          if fb then fb:SetScale(v) end
                      end },
                    { type = "slider", label = "X Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.fpsOffsetX or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.fpsOffsetX = v
                          RefreshMinimap()
                      end },
                    { type = "slider", label = "Y Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.fpsOffsetY or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.fpsOffsetY = v
                          RefreshMinimap()
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(FpsOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(FpsOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Show FPS/MS")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = FpsOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if FpsOff() then cogBlock:Show() else cogBlock:Hide() end
        end

        -- Show on FPS/MS Hover | Show on Clock Hover
        local HOVER_TT_VALUES = { none = "None", lockouts = "Instance Lockouts", vault = "Great Vault" }
        local HOVER_TT_ORDER = { "none", "lockouts", "vault" }
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Show on FPS/MS Hover",
              values = HOVER_TT_VALUES, order = HOVER_TT_ORDER,
              disabled=FpsOff,
              disabledTooltip="Show FPS/MS",
              getValue=function() local m = MinimapDB(); return m and m.fpsHoverTooltip or "none" end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.fpsHoverTooltip = v
                RefreshMinimap()
              end },
            { type="dropdown", text="Show on Clock Hover",
              values = HOVER_TT_VALUES, order = HOVER_TT_ORDER,
              disabled=function() return ClockMode() == "none" end,
              disabledTooltip="Clock Style",
              getValue=function() local m = MinimapDB(); return m and m.clockHoverTooltip or "none" end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.clockHoverTooltip = v
              end }
        );  y = y - h

        -- Show Instance Difficulty as Text | Difficulty Position (+ size/offset cog)
        local function DiffTextOn()
            local m = MinimapDB(); return (m and m.diffTextEnabled) or false
        end
        local diffRow
        diffRow, h = W:DualRow(parent, y,
            { type="toggle", text="Show Instance Difficulty as Text",
              getValue=DiffTextOn,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.diffTextEnabled = v and true or false
                RefreshMinimap()
                EllesmereUI:RefreshPage()
              end },
            { type="dropdown", text="Difficulty Position",
              values = MAP_POS_VALUES, order = MAP_POS_ORDER,
              disabled=function() return not DiffTextOn() end,
              disabledTooltip="Show Instance Difficulty as Text",
              getValue=function() local m = MinimapDB(); return m and m.diffTextPosition or "topLeft" end,
              setValue=function(v)
                local m = MinimapDB(); if not m then return end
                m.diffTextPosition = v
                RefreshMinimap()
              end }
        );  y = y - h
        -- Inline cog on Difficulty Position for text size + X/Y offset
        do
            local rgn = diffRow._rightRegion
            local function diffOff()
                return not DiffTextOn()
            end
            local _, cogShow = EllesmereUI.BuildCogPopup({
                title = "Difficulty Text Size and Position",
                rows = {
                    { type = "slider", label = "Text Size", min = 8, max = 24, step = 1,
                      get = function() local m = MinimapDB(); return m and m.diffTextSize or 12 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.diffTextSize = v
                          RefreshMinimap()
                      end },
                    { type = "slider", label = "X Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.diffTextOffsetX or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.diffTextOffsetX = v
                          RefreshMinimap()
                      end },
                    { type = "slider", label = "Y Offset", min = -500, max = 500, step = 1,
                      get = function() local m = MinimapDB(); return m and m.diffTextOffsetY or 0 end,
                      set = function(v)
                          local m = MinimapDB(); if not m then return end
                          m.diffTextOffsetY = v
                          RefreshMinimap()
                      end },
                },
            })
            local cogBtn = CreateFrame("Button", nil, rgn)
            cogBtn:SetSize(26, 26)
            cogBtn:SetPoint("RIGHT", rgn._control, "LEFT", -8, 0)
            cogBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            cogBtn:SetAlpha(diffOff() and 0.15 or 0.4)
            local cogTex = cogBtn:CreateTexture(nil, "OVERLAY")
            cogTex:SetAllPoints()
            cogTex:SetTexture(EllesmereUI.RESIZE_ICON)
            cogBtn:SetScript("OnEnter", function(self) self:SetAlpha(0.7) end)
            cogBtn:SetScript("OnLeave", function(self) self:SetAlpha(diffOff() and 0.15 or 0.4) end)
            cogBtn:SetScript("OnClick", function(self) cogShow(self) end)
            local cogBlock = CreateFrame("Frame", nil, cogBtn)
            cogBlock:SetAllPoints(); cogBlock:SetFrameLevel(cogBtn:GetFrameLevel() + 10); cogBlock:EnableMouse(true)
            cogBlock:SetScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(cogBtn, EllesmereUI.DisabledTooltip("Show Instance Difficulty as Text")) end)
            cogBlock:SetScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            EllesmereUI.RegisterWidgetRefresh(function()
                local off = diffOff()
                cogBtn:SetAlpha(off and 0.15 or 0.4)
                if off then cogBlock:Show() else cogBlock:Hide() end
            end)
            if diffOff() then cogBlock:Show() else cogBlock:Hide() end
        end

        -- Accented Text | (empty) -- which Text elements colour their
        -- description parts (clock AM/PM, FPS/MS suffixes, difficulty
        -- letter) with the accent/custom colour from the inline swatches.
        -- Dynamic values always render white.
        -- Difficulty and Difficulty (Reactive) are mutually exclusive: flat
        -- accent/custom colour vs colour-by-tier. Each locks while the other
        -- is checked, and the setters clear the sibling as a consistency net
        -- (the locked state repaints on the next menu open).
        local accentItems = {
            { key = "clock",      label = "Clock" },
            { key = "fpsms",      label = "FPS/MS" },
            { key = "difficulty", label = "Difficulty",
              lockedFn = function() local m = MinimapDB(); return (m and m.diffTextReactive) or false end },
            { key = "difficultyReactive", label = "Difficulty (Reactive)",
              lockedFn = function() local m = MinimapDB(); return (m and m.diffTextAccent) or false end },
        }
        local accentRow
        accentRow, h = W:DualRow(parent, y,
            { type="dropdown", text="Accented Text",
              values={ ["_placeholder"]="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end },
            { type="label", text="" }
        );  y = y - h
        do
            local rgn = accentRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2,
                accentItems,
                function(k)
                    local m = MinimapDB(); if not m then return false end
                    if k == "clock" then return m.fpsColorClockAMPM or false end
                    if k == "fpsms" then
                        local v = m.fpsColorSuffix
                        if v == nil then return true end
                        return v
                    end
                    if k == "difficulty" then return m.diffTextAccent or false end
                    if k == "difficultyReactive" then return m.diffTextReactive or false end
                    return false
                end,
                function(k, v)
                    local m = MinimapDB(); if not m then return end
                    if k == "clock" then m.fpsColorClockAMPM = v
                    elseif k == "fpsms" then m.fpsColorSuffix = v
                    elseif k == "difficulty" then
                        m.diffTextAccent = v
                        if v then m.diffTextReactive = false end
                    elseif k == "difficultyReactive" then
                        m.diffTextReactive = v
                        if v then m.diffTextAccent = false end
                    end
                    RefreshMinimap()
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)

            -- Accent swatch (nearest the control): live theme accent.
            local accentSwatch, updateAccent = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                function()
                    local ar, ag, ab = EllesmereUI.GetAccentColor()
                    return ar, ag, ab, 1
                end,
                function() end, false, 18)
            accentSwatch:SetScript("OnClick", function()
                local m = MinimapDB(); if not m then return end
                m.fpsUseAccent = true
                RefreshMinimap()
                EllesmereUI:RefreshPage()
            end)
            PP.Point(accentSwatch, "RIGHT", cbDD, "LEFT", -12, 0)
            rgn._lastInline = accentSwatch

            -- Custom swatch (to the left of accent): stored custom colour.
            local customSwatch, updateCustom = EllesmereUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                function()
                    local m = MinimapDB()
                    local c = m and m.fpsColor
                    if c then return c.r or 1, c.g or 1, c.b or 1, 1 end
                    return 1, 1, 1, 1
                end,
                function(r, g, b)
                    local m = MinimapDB(); if not m then return end
                    m.fpsColor = { r = r, g = g, b = b }
                    RefreshMinimap()
                end, false, 18)
            local openPicker = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self)
                local m = MinimapDB()
                if m and m.fpsUseAccent then
                    m.fpsUseAccent = false
                    RefreshMinimap()
                    EllesmereUI:RefreshPage()
                    return
                end
                if openPicker then openPicker(self) end
            end)
            PP.Point(customSwatch, "RIGHT", accentSwatch, "LEFT", -8, 0)
            rgn._lastInline = customSwatch

            accentSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(accentSwatch, "Accent Color") end)
            accentSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)
            customSwatch:HookScript("OnEnter", function() EllesmereUI.ShowWidgetTooltip(customSwatch, "Custom Color") end)
            customSwatch:HookScript("OnLeave", function() EllesmereUI.HideWidgetTooltip() end)

            EllesmereUI.RegisterWidgetRefresh(function()
                if updateAccent then updateAccent() end
                if updateCustom then updateCustom() end
                local m = MinimapDB()
                local useAccent = m and m.fpsUseAccent
                accentSwatch:SetAlpha(useAccent and 1 or 0.3)
                customSwatch:SetAlpha(useAccent and 0.3 or 1)
            end)
            local mInit = MinimapDB()
            local initAccent = mInit and mInit.fpsUseAccent
            accentSwatch:SetAlpha(initAccent and 1 or 0.3)
            customSwatch:SetAlpha(initAccent and 0.3 or 1)
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
