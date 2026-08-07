-------------------------------------------------------------------------------
--  EUI_MythicPlus_Options.lua  --  settings pages for the Mythic+ module
--
--  Positioning for the keystone list and banner deliberately lives in the
--  suite's global Unlock Mode, not here; this page only links to it.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local PAGE_ICONS  = "Dungeon Icons"
local PAGE_WEEKLY = "Weekly Panel"
local PAGE_KEYS   = "Keystones"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.RegisterModule then return end

    local function P() return ns.P() end

    local function Refresh()
        if _G._EMP_Apply then _G._EMP_Apply() end
    end

    --- Settings whose state gates other rows need the page redrawn so the
    --- dependent rows pick up their new disabled state.
    local function RefreshAndRepaint()
        Refresh()
        if EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
    end

    local function ModuleOff()
        local p = P()
        return not p or p.enabled == false
    end

    ---------------------------------------------------------------------------
    --  Inline eye toggle
    --
    --  Both keystone displays only appear under conditions the player cannot
    --  produce on demand (a full party, or standing in a Mythic 0), so the eye
    --  fills them with sample rows to size and position against. Preview state
    --  is runtime-only -- see the note in EUI_MythicPlus_Keystones.lua.
    ---------------------------------------------------------------------------
    local function AttachEyeToggle(rgn, which, isDisabled)
        local PP = EllesmereUI.PP
        local btn = CreateFrame("Button", nil, rgn)
        btn:SetSize(26, 26)
        -- Chain off any inline widget already on this region so several inline
        -- controls sit side by side instead of overlapping.
        PP.Point(btn, "RIGHT", rgn._lastInline or rgn._control or rgn, "LEFT", -6, 0)
        rgn._lastInline = btn
        btn:SetFrameLevel(rgn:GetFrameLevel() + 5)

        local tex = btn:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()

        local function IsOn() return ns.IsKeystonePreview(which) end
        local function UpdateVisual()
            tex:SetTexture(IsOn() and EllesmereUI.EYE_VISIBLE_ICON or EllesmereUI.EYE_INVISIBLE_ICON)
            btn:SetAlpha(isDisabled() and 0.15 or (IsOn() and 0.85 or 0.4))
        end
        EllesmereUI.RegisterWidgetRefresh(UpdateVisual)
        UpdateVisual()

        btn:SetScript("OnClick", function()
            if isDisabled() then return end
            ns.SetKeystonePreview(which, not IsOn())
            UpdateVisual()
        end)
        btn:SetScript("OnEnter", function(self)
            if isDisabled() then return end
            self:SetAlpha(1)
            -- ShowWidgetTooltip translates its own text.
            EllesmereUI.ShowWidgetTooltip(self, IsOn() and "Hide Preview" or "Preview with Sample Data")
        end)
        btn:SetScript("OnLeave", function()
            UpdateVisual()
            EllesmereUI.HideWidgetTooltip()
        end)
    end

    --- A live preview must survive the options window closing into Unlock Mode
    --- -- placing the frames is exactly when it is wanted. Anything else that
    --- closes the panel drops it, and so does leaving Unlock Mode.
    local function InstallPreviewAutoOff()
        local mf = _G.EllesmereUIFrame
        if not mf or mf._empPreviewHook then return end
        mf._empPreviewHook = true
        mf:HookScript("OnHide", function()
            if EllesmereUI.IsUnlockModeActive and EllesmereUI:IsUnlockModeActive() then return end
            ns.ClearKeystonePreviews()
        end)
        if EllesmereUI.RegisterUnlockModeListener then
            EllesmereUI:RegisterUnlockModeListener("EllesmereUIMythicPlus", function(active)
                if not active then ns.ClearKeystonePreviews() end
            end)
        end
    end

    ---------------------------------------------------------------------------
    --  Score overlay: three identical line blocks (name / level / score)
    ---------------------------------------------------------------------------
    local SCORE_LINES = {
        { key = "name",  label = "Dungeon Name", shown = "nameShown",  size = "nameSize",  x = "nameX",  y = "nameY"  },
        { key = "level", label = "Best Level",   shown = "levelShown", size = "levelSize", x = "levelX", y = "levelY" },
        { key = "score", label = "Dungeon Score", shown = "scoreShown", size = "scoreSize", x = "scoreX", y = "scoreY" },
    }

    local function ScoreOff()
        local p = P()
        return ModuleOff() or p.score.enabled == false
    end

    local function BuildScoreLine(parent, y, line)
        local W = EllesmereUI.Widgets
        local row, h

        local function LineOff()
            local p = P()
            return ScoreOff() or p.score[line.shown] == false
        end

        row, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show " .. line.label,
              disabled = ScoreOff, disabledTooltip = "Show Score Overlay",
              getValue = function() return P().score[line.shown] ~= false end,
              setValue = function(v) P().score[line.shown] = v; RefreshAndRepaint() end },
            { type = "slider", text = line.label .. " Size",
              disabled = LineOff, disabledTooltip = "Show " .. line.label,
              min = 8, max = 32, step = 1, isPercent = false,
              getValue = function() return P().score[line.size] end,
              setValue = function(v) P().score[line.size] = v; Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type = "slider", pixel = true, text = line.label .. " X",
              disabled = LineOff, disabledTooltip = "Show " .. line.label,
              min = -80, max = 80, step = 1, isPercent = false,
              getValue = function() return P().score[line.x] or 0 end,
              setValue = function(v) P().score[line.x] = v; Refresh() end },
            { type = "slider", pixel = true, text = line.label .. " Y",
              disabled = LineOff, disabledTooltip = "Show " .. line.label,
              min = -80, max = 80, step = 1, isPercent = false,
              getValue = function() return P().score[line.y] or 0 end,
              setValue = function(v) P().score[line.y] = v; Refresh() end })
        y = y - h

        return y
    end

    ---------------------------------------------------------------------------
    --  Page: Dungeon Icons
    ---------------------------------------------------------------------------
    local function BuildIconsPage(parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Mythic+",
              tooltip = "Master switch for every Mythic+ feature in this module.",
              getValue = function() return P().enabled ~= false end,
              setValue = function(v) P().enabled = v; RefreshAndRepaint() end },
            { type = "toggle", text = "Abbreviate Dungeon Names",
              disabled = ModuleOff, disabledTooltip = "the module",
              tooltip = "Show short dungeon names (WRS, MT, ...) wherever this module prints one.",
              getValue = function() return P().useAbbreviation ~= false end,
              setValue = function(v) P().useAbbreviation = v; Refresh() end })
        y = y - h

        _, h = W:SectionHeader(parent, "SCORE OVERLAY", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Score Overlay",
              disabled = ModuleOff, disabledTooltip = "the module",
              tooltip = "Draw dungeon name, best key level and season score onto each Group Finder dungeon icon.",
              getValue = function() return P().score.enabled ~= false end,
              setValue = function(v) P().score.enabled = v; RefreshAndRepaint() end },
            { type = "toggle", text = "Hide Blizzard Key Level",
              disabled = ScoreOff, disabledTooltip = "Show Score Overlay",
              getValue = function() return P().score.hideBlizzardLevel ~= false end,
              setValue = function(v) P().score.hideBlizzardLevel = v; Refresh() end })
        y = y - h

        for _, line in ipairs(SCORE_LINES) do
            y = BuildScoreLine(parent, y, line)
        end

        _, h = W:SectionHeader(parent, "TELEPORTS", y); y = y - h

        local function TeleportOff()
            local p = P()
            return ModuleOff() or p.teleport.enabled == false
        end

        row, h = W:DualRow(parent, y,
            { type = "toggle", text = "Teleport Buttons",
              disabled = ModuleOff, disabledTooltip = "the module",
              tooltip = "Click a Group Finder dungeon icon to cast its teleport.",
              getValue = function() return P().teleport.enabled ~= false end,
              setValue = function(v) P().teleport.enabled = v; RefreshAndRepaint() end },
            { type = "toggle", text = "Announce Teleports",
              disabled = TeleportOff, disabledTooltip = "Teleport Buttons",
              tooltip = "Post a message to party or instance chat when you cast a dungeon teleport.",
              getValue = function() return P().teleport.announce == true end,
              setValue = function(v) P().teleport.announce = v; RefreshAndRepaint() end })
        y = y - h

        local function AnnounceOff()
            local p = P()
            return TeleportOff() or p.teleport.announce ~= true
        end

        row, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Announce Message", buttonText = "Edit Message",
              disabled = AnnounceOff, disabledTooltip = "Announce Teleports",
              tooltip = "{spell} becomes the teleport spell link, {dungeon} the dungeon name.",
              onClick = function()
                  EllesmereUI:ShowInputPopup({
                      title = "Announce Message",
                      message = "Use {spell} for the teleport spell link and {dungeon} for the dungeon name.",
                      -- Same resolver the runtime sends with, so the field can
                      -- never show a different default than what actually posts.
                      placeholder = ns.TeleportTemplate(),
                      confirmText = "Save",
                      cancelText = "Cancel",
                      onConfirm = function(text)
                          text = text and strtrim(text) or ""
                          -- Storing "" keeps the message following the client
                          -- language instead of freezing today's translation.
                          P().teleport.template = text
                          Refresh()
                      end,
                  })
              end },
            { type = "button", text = "Reset Message", width = 160,
              disabled = AnnounceOff, disabledTooltip = "Announce Teleports",
              onClick = function() P().teleport.template = ""; Refresh() end })
        y = y - h

        _, h = W:Spacer(parent, y, 20); y = y - h
        parent:SetHeight(math.abs(y - yOffset))
    end

    ---------------------------------------------------------------------------
    --  Page: Weekly Panel
    ---------------------------------------------------------------------------
    local function BuildWeeklyPage(parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        local function WeeklyOff()
            local p = P()
            return ModuleOff() or p.weekly.enabled == false
        end

        _, h = W:SectionHeader(parent, "WEEKLY PANEL", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Weekly Panel",
              disabled = ModuleOff, disabledTooltip = "the module",
              tooltip = "List this week's Mythic+ runs beside the Group Finder window.",
              getValue = function() return P().weekly.enabled ~= false end,
              setValue = function(v) P().weekly.enabled = v; RefreshAndRepaint() end },
            { type = "toggle", text = "Hold Shift for Season Best",
              disabled = WeeklyOff, disabledTooltip = "Show Weekly Panel",
              getValue = function() return P().weekly.useModifierKey ~= false end,
              setValue = function(v) P().weekly.useModifierKey = v; Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type = "slider", text = "Font Size",
              disabled = WeeklyOff, disabledTooltip = "Show Weekly Panel",
              min = 8, max = 32, step = 1, isPercent = false,
              getValue = function() return P().weekly.fontSize end,
              setValue = function(v) P().weekly.fontSize = v; Refresh() end },
            { type = "slider", pixel = true, text = "Row Spacing",
              disabled = WeeklyOff, disabledTooltip = "Show Weekly Panel",
              min = 0, max = 20, step = 1, isPercent = false,
              getValue = function() return P().weekly.rowSpacing end,
              setValue = function(v) P().weekly.rowSpacing = v; Refresh() end })
        y = y - h

        row, h = W:DualRow(parent, y,
            { type = "slider", text = "Max Rows",
              disabled = WeeklyOff, disabledTooltip = "Show Weekly Panel",
              tooltip = "How many runs the Weekly Best and Season Best lists show before the per-dungeon summary.",
              min = 3, max = 15, step = 1, isPercent = false,
              getValue = function() return P().weekly.maxRows end,
              setValue = function(v) P().weekly.maxRows = v; Refresh() end },
            { type = "label", text = "" })
        y = y - h

        _, h = W:SectionHeader(parent, "DOCK OFFSET", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type = "slider", pixel = true, text = "X Offset",
              disabled = WeeklyOff, disabledTooltip = "Show Weekly Panel",
              tooltip = "The panel docks to the Group Finder window's top-right corner and follows it.",
              min = -400, max = 400, step = 1, isPercent = false,
              getValue = function() return P().weekly.offsetX end,
              setValue = function(v) P().weekly.offsetX = v; Refresh() end },
            { type = "slider", pixel = true, text = "Y Offset",
              disabled = WeeklyOff, disabledTooltip = "Show Weekly Panel",
              min = -400, max = 400, step = 1, isPercent = false,
              getValue = function() return P().weekly.offsetY end,
              setValue = function(v) P().weekly.offsetY = v; Refresh() end })
        y = y - h

        _, h = W:Spacer(parent, y, 20); y = y - h
        parent:SetHeight(math.abs(y - yOffset))
    end

    ---------------------------------------------------------------------------
    --  Page: Keystones
    ---------------------------------------------------------------------------
    local function BuildKeystonesPage(parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        local function ListOff()
            local p = P()
            return ModuleOff() or p.keystoneList.enabled == false
        end
        local function BannerOff()
            local p = P()
            return ModuleOff() or p.centerBanner.enabled == false
        end

        InstallPreviewAutoOff()

        _, h = W:SectionHeader(parent, "PARTY KEYSTONES", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Party Keystones",
              disabled = ModuleOff, disabledTooltip = "the module",
              tooltip = "A floating list of every party member's keystone, hidden once a run starts.",
              getValue = function() return P().keystoneList.enabled ~= false end,
              setValue = function(v) P().keystoneList.enabled = v; RefreshAndRepaint() end },
            { type = "slider", pixel = true, text = "Icon Size",
              disabled = ListOff, disabledTooltip = "Show Party Keystones",
              min = 20, max = 64, step = 1, isPercent = false,
              getValue = function() return P().keystoneList.iconSize end,
              setValue = function(v) P().keystoneList.iconSize = v; Refresh() end })
        AttachEyeToggle(row._leftRegion, "list", ListOff)
        y = y - h

        row, h = W:DualRow(parent, y,
            { type = "slider", text = "List Font Size",
              disabled = ListOff, disabledTooltip = "Show Party Keystones",
              min = 8, max = 32, step = 1, isPercent = false,
              getValue = function() return P().keystoneList.fontSize end,
              setValue = function(v) P().keystoneList.fontSize = v; Refresh() end },
            { type = "slider", pixel = true, text = "List Row Spacing",
              disabled = ListOff, disabledTooltip = "Show Party Keystones",
              min = 0, max = 20, step = 1, isPercent = false,
              getValue = function() return P().keystoneList.rowSpacing end,
              setValue = function(v) P().keystoneList.rowSpacing = v; Refresh() end })
        y = y - h

        _, h = W:SectionHeader(parent, "KEYSTONE OWNERS", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Keystone Owners",
              disabled = ModuleOff, disabledTooltip = "the module",
              tooltip = "Names who is holding a key for the Mythic dungeon the group just entered.",
              getValue = function() return P().centerBanner.enabled ~= false end,
              setValue = function(v) P().centerBanner.enabled = v; RefreshAndRepaint() end },
            { type = "slider", text = "Banner Font Size",
              disabled = BannerOff, disabledTooltip = "Show Keystone Owners",
              min = 8, max = 32, step = 1, isPercent = false,
              getValue = function() return P().centerBanner.fontSize end,
              setValue = function(v) P().centerBanner.fontSize = v; Refresh() end })
        AttachEyeToggle(row._leftRegion, "banner", BannerOff)
        y = y - h

        row, h = W:DualRow(parent, y,
            { type = "slider", pixel = true, text = "Banner Row Spacing",
              disabled = BannerOff, disabledTooltip = "Show Keystone Owners",
              min = 0, max = 20, step = 1, isPercent = false,
              getValue = function() return P().centerBanner.rowSpacing end,
              setValue = function(v) P().centerBanner.rowSpacing = v; Refresh() end },
            { type = "label", text = "" })
        y = y - h

        _, h = W:SectionHeader(parent, "POSITIONING", y); y = y - h

        _, h = W:Toggle(parent, "Unlock Elements", y,
            function() return EllesmereUI._unlockModeActive or false end,
            function()
                if EllesmereUI.ToggleUnlockMode then EllesmereUI:ToggleUnlockMode() end
            end,
            "Both keystone displays are placed in the shared Unlock Mode, alongside every other EllesmereUI element.")
        y = y - h

        _, h = W:Spacer(parent, y, 20); y = y - h
        parent:SetHeight(math.abs(y - yOffset))
    end

    ---------------------------------------------------------------------------
    --  Registration
    ---------------------------------------------------------------------------
    EllesmereUI:RegisterModule("EllesmereUIMythicPlus", {
        title       = "Mythic+ Tools",
        description = "Dungeon scores, weekly runs, teleports and party keystones.",
        searchTerms = "mythic plus keystone key score teleport portal weekly vault dungeon",
        pages       = { PAGE_ICONS, PAGE_WEEKLY, PAGE_KEYS },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE_ICONS  then return BuildIconsPage(parent, yOffset) end
            if pageName == PAGE_WEEKLY then return BuildWeeklyPage(parent, yOffset) end
            if pageName == PAGE_KEYS   then return BuildKeystonesPage(parent, yOffset) end
        end,
        onReset = function()
            if _G._EMP_DB and _G._EMP_DB.ResetProfile then
                _G._EMP_DB:ResetProfile()
            end
            EllesmereUI:InvalidatePageCache()
            if _G._EMP_Apply then _G._EMP_Apply() end
        end,
    })

    SLASH_EMP1 = "/emp"
    SlashCmdList.EMP = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIMythicPlus")
    end
end)
