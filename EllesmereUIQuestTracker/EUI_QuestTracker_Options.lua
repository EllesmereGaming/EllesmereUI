-------------------------------------------------------------------------------
-- EUI_QuestTracker_Options.lua
--
-- Options page for the Blizzard-backed quest tracker. All legacy display,
-- font, and color options from the custom-tracker era have been removed.
-- Surviving options are: enable, visibility mode, auto-hide rules,
-- auto-accept / auto-turn-in, quest item hotkey, and skin toggles.
-------------------------------------------------------------------------------
local _, ns = ...
local EQT = ns.EQT

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not EllesmereUI or not EllesmereUI.RegisterModule then return end
    if not EQT then return end

    local function DB()
        local d = _G._EQT_DB
        if d and d.profile and d.profile.questTracker then
            return d.profile.questTracker
        end
        return {}
    end
    local function Cfg(k)    return DB()[k]  end
    local function Set(k, v) DB()[k] = v     end

    local function MakeCogBtn(rgn, showFn)
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
        cogBtn:SetScript("OnClick", function(s) showFn(s) end)
        return cogBtn
    end

    local function RefreshAll()
        if EQT.RefreshStateDriver then EQT.RefreshStateDriver() end
        if EQT.UpdateVisibility   then EQT.UpdateVisibility()   end
        if EQT.RestyleAll         then EQT.RestyleAll()         end
        if EQT.ApplyBackground    then EQT.ApplyBackground()    end
    end

    local function BuildPage(_, parent, yOffset)
        local W  = EllesmereUI.Widgets
        local PP = EllesmereUI.PP
        local y  = yOffset
        local row, h

        if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
        parent._showRowDivider = true

        -- Drag instructions (centered, above settings).
        -- Wrapped in a Frame so the search system collects it as an orphan
        -- and auto-hides it during search.
        do
            local fontPath = EllesmereUI.GetFontPath and EllesmereUI.GetFontPath() or STANDARD_TEXT_FONT
            local infoFrame = CreateFrame("Frame", nil, parent)
            infoFrame:SetSize(parent:GetWidth() or 400, 20)
            infoFrame:SetPoint("TOP", parent, "TOP", 0, y - 20)
            infoFrame._isSpacer = true
            local infoLabel = infoFrame:CreateFontString(nil, "OVERLAY")
            infoLabel:SetFont(fontPath, 15, "")
            infoLabel:SetTextColor(1, 1, 1, 0.75)
            infoLabel:SetPoint("CENTER")
            infoLabel:SetJustifyH("CENTER")
            infoLabel:SetText(EllesmereUI.L("Reposition this element within Blizzard Edit Mode"))

            -- Accent toggle beneath the label. "Force Quest Tracker on Screen"
            -- keeps the tracker clamped to the screen; clicking again ("Allow
            -- Quest Tracker to be Moved Offscreen") releases it so it can be
            -- dragged off-screen. The choice is saved in the quest tracker DB
            -- (forceOnScreen) and re-applied at load by EQT.ApplyForceOnScreen(),
            -- so it persists through reload/logout. Edit Mode is opened so the
            -- user can reposition the frame after toggling.
            local EG = EllesmereUI.ELLESMERE_GREEN
            local fosBtn = CreateFrame("Button", nil, parent)
            local fosFS = fosBtn:CreateFontString(nil, "OVERLAY")
            fosFS:SetFont(fontPath, 15, "")
            fosFS:SetTextColor(EG.r, EG.g, EG.b, 0.75)
            fosFS:SetPoint("CENTER")
            local function UpdateForceOnScreenLabel()
                local on = Cfg("forceOnScreen") == true
                fosFS:SetText(EllesmereUI.L(on and "Allow Quest Tracker to be Moved Offscreen" or "Force Quest Tracker on Screen"))
                fosBtn:SetSize(fosFS:GetStringWidth() + 12, 18)
            end
            UpdateForceOnScreenLabel()
            fosBtn:SetPoint("TOP", infoLabel, "BOTTOM", 0, -10)
            fosBtn:SetScript("OnEnter", function() fosFS:SetTextColor(EG.r, EG.g, EG.b, 1) end)
            fosBtn:SetScript("OnLeave", function() fosFS:SetTextColor(EG.r, EG.g, EG.b, 0.75) end)
            fosBtn:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                Set("forceOnScreen", not (Cfg("forceOnScreen") == true))
                if EQT.ApplyForceOnScreen then EQT.ApplyForceOnScreen() end
                UpdateForceOnScreenLabel()
                if EditModeManagerFrame then ShowUIPanel(EditModeManagerFrame) end
            end)
            y = y - 68
        end

        -- -- DISPLAY ---------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h

        -- Row 1: Visibility | Visibility Options
        local visRow
        visRow, h = EllesmereUI.BuildVisibilityModeRow(W, parent, y,
            { getStore = DB, legacyKey = "visibility",
              caps = { partyIncludesRaid = false, luaDragonriding = true },
              onChanged = function() RefreshAll() end },
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

        -- Row 2: Background Opacity (slider + inline color swatch) | blank
        local bgRow
        bgRow, h = W:DualRow(parent, y,
            { type="slider", text="Background Opacity",
              min = 0, max = 1, step = 0.05,
              getValue=function() return Cfg("bgAlpha") or 0.5 end,
              setValue=function(v) Set("bgAlpha", v); if EQT.ApplyBackground then EQT.ApplyBackground() end end },
            { type="toggle", text="Show Top Line",
              tooltip="Draws a 1px accent line above the background at the top of the tracker.",
              getValue=function() return Cfg("showTopLine") ~= false end,
              setValue=function(v) Set("showTopLine", v); if EQT.ApplyBackground then EQT.ApplyBackground() end end })
        do
            local rgn = bgRow._leftRegion
            local ctrl = rgn._control
            local bgSwatch, bgSwatchRefresh = EllesmereUI.BuildColorSwatch(
                rgn, bgRow:GetFrameLevel() + 3,
                function()
                    return (Cfg("bgR") or 0), (Cfg("bgG") or 0), (Cfg("bgB") or 0)
                end,
                function(r, g, b)
                    Set("bgR", r); Set("bgG", g); Set("bgB", b)
                    if EQT.ApplyBackground then EQT.ApplyBackground() end
                end,
                false, 20)
            PP.Point(bgSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
            EllesmereUI.RegisterWidgetRefresh(function() bgSwatchRefresh() end)
        end
        y = y - h

        -- Row 3: Title Font Size | Objective Font Size
        _, h = W:DualRow(parent, y,
            { type="slider", text="Title Font Size",
              min = 8, max = 24, step = 1,
              getValue=function() return Cfg("titleFontSize") or 12 end,
              setValue=function(v) Set("titleFontSize", v); RefreshAll() end },
            { type="slider", text="Objective Font Size",
              min = 8, max = 24, step = 1,
              getValue=function() return Cfg("objectiveFontSize") or 10 end,
              setValue=function(v) Set("objectiveFontSize", v); RefreshAll() end })
        y = y - h

        -- Row 4: Font | Show Quest Icons
        do
            local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
            _, h = W:DualRow(parent, y,
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
                  end },
                { type="toggle", text="Show Quest Icons",
                  tooltip="Show Blizzard's native quest type icons/buttons on the right instead of EllesmereUI's custom icons. Requires a UI reload.",
                  getValue=function() return Cfg("showQuestIcons") or false end,
                  setValue=function(v)
                      Set("showQuestIcons", v)
                      EllesmereUI:ShowConfirmPopup({
                          title       = "Reload Required",
                          message     = "Changing quest icons requires a UI reload to apply.",
                          confirmText = "Reload Now",
                          cancelText  = "Later",
                          onConfirm   = function() ReloadUI() end,
                      })
                  end })
        end
        y = y - h

        -- Row 5: Hide When In Raid | blank
        _, h = W:DualRow(parent, y,
            { type="dropdown", text="Hide When In Raid",
              tooltip="Always: hide the tracker the whole time you are in a raid.\nBoss Combat: keep it visible and only hide during boss encounters.",
              values = { always = "Always", boss = "Boss Combat" },
              order  = { "always", "boss" },
              getValue=function() return Cfg("hideInRaidMode") or "boss" end,
              setValue=function(v) Set("hideInRaidMode", v); if EQT.UpdateVisibility then EQT.UpdateVisibility() end end },
            { type="label", text="" })
        y = y - h

        y = y - 10

        -- -- COLORS ----------------------------------------------------------
        _, h = W:SectionHeader(parent, "COLORS", y); y = y - h

        local function MakeColorRow(leftLabel, leftKeys, rightLabel, rightKeys)
            local r, rowH = W:DualRow(parent, y,
                { type="label", text = leftLabel },
                { type="label", text = rightLabel })
            local function wire(rgn, keys)
                local sw, swRefresh = EllesmereUI.BuildColorSwatch(
                    rgn, r:GetFrameLevel() + 3,
                    function()
                        return (Cfg(keys.r) or 0), (Cfg(keys.g) or 0), (Cfg(keys.b) or 0)
                    end,
                    function(cr, cg, cb)
                        Set(keys.r, cr); Set(keys.g, cg); Set(keys.b, cb)
                        RefreshAll()
                    end,
                    false, 20)
                PP.Point(sw, "RIGHT", rgn, "RIGHT", -20, 0)
                EllesmereUI.RegisterWidgetRefresh(function() swRefresh() end)
            end
            wire(r._leftRegion,  leftKeys)
            if rightKeys then wire(r._rightRegion, rightKeys) end
            return r, rowH
        end

        _, h = MakeColorRow(
            "Title Color",    { r = "titleR",     g = "titleG",     b = "titleB"     },
            "Completed Color",{ r = "completedR", g = "completedG", b = "completedB" })
        y = y - h

        _, h = MakeColorRow(
            "Focused Color",  { r = "focusR",     g = "focusG",     b = "focusB"     },
            "", nil)
        y = y - h

        y = y - 10

        -- -- EXTRAS ----------------------------------------------------------
        _, h = W:SectionHeader(parent, "EXTRAS", y); y = y - h

        row, h = W:DualRow(parent, y,
            { type="toggle", text="Auto Accept Quests",
              getValue=function() return Cfg("autoAccept") or false end,
              setValue=function(v) Set("autoAccept", v) end },
            { type="toggle", text="Auto Turn In Quests",
              getValue=function() return Cfg("autoTurnIn") or false end,
              setValue=function(v) Set("autoTurnIn", v) end })
        do
            local lrgn = row._leftRegion
            local _, cogShowL = EllesmereUI.BuildCogPopup({
                title = "Auto Accept Settings",
                rows = {
                    { type="toggle", label="Prevent Multi Quest Accept",
                      get=function() return Cfg("autoAcceptPreventMulti") ~= false end,
                      set=function(v) Set("autoAcceptPreventMulti", v) end },
                    { type="toggle", label="Hold Shift to Skip",
                      get=function() return Cfg("autoAcceptShiftSkip") ~= false end,
                      set=function(v) Set("autoAcceptShiftSkip", v) end },
                },
            })
            MakeCogBtn(lrgn, cogShowL)

            local rrgn = row._rightRegion
            local _, cogShowR = EllesmereUI.BuildCogPopup({
                title = "Auto Turn In Settings",
                rows = {
                    { type="toggle", label="Hold Shift to Skip",
                      get=function() return Cfg("autoTurnInShiftSkip") ~= false end,
                      set=function(v) Set("autoTurnInShiftSkip", v) end },
                },
            })
            MakeCogBtn(rrgn, cogShowR)
        end
        y = y - h

        -- Quest Item Hotkey row
        local kbRow
        kbRow, h = W:DualRow(parent, y,
            { type="label", text="" },
            { type="label", text="" })
        do
            local rgn = kbRow._leftRegion
            local SIDE_PAD = 20
            local KB_W, KB_H = 120, 26

            local label = EllesmereUI.MakeFont(rgn, 14, nil,
                EllesmereUI.TEXT_WHITE_R, EllesmereUI.TEXT_WHITE_G, EllesmereUI.TEXT_WHITE_B)
            PP.Point(label, "LEFT", rgn, "LEFT", SIDE_PAD, 0)
            label:SetText(EllesmereUI.L("Quest Item Hotkey"))

            local kbBtn = CreateFrame("Button", nil, rgn)
            PP.Size(kbBtn, KB_W, KB_H)
            PP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -SIDE_PAD, 0)
            kbBtn:SetFrameLevel(rgn:GetFrameLevel() + 5)
            kbBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            local kbBg = EllesmereUI.SolidTex(kbBtn, "BACKGROUND",
                EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
            kbBg:SetAllPoints()
            kbBtn._border = EllesmereUI.MakeBorder(kbBtn, 1, 1, 1, EllesmereUI.DD_BRD_A, EllesmereUI.PanelPP)
            local kbLbl = EllesmereUI.MakeFont(kbBtn, 12, nil, 1, 1, 1)
            kbLbl:SetAlpha(EllesmereUI.DD_TXT_A)
            kbLbl:SetPoint("CENTER")

            local function FormatKey(key)
                if not key or key == "" then return "Not Bound" end
                local parts = {}
                for mod in key:gmatch("(%u+)%-") do
                    parts[#parts + 1] = mod:sub(1, 1) .. mod:sub(2):lower()
                end
                local actualKey = key:match("[^%-]+$") or key
                parts[#parts + 1] = actualKey
                return table.concat(parts, " + ")
            end
            local function RefreshLabel() kbLbl:SetText(FormatKey(Cfg("questItemHotkey"))) end
            RefreshLabel()

            local listening = false
            kbBtn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    if listening then listening = false; self:EnableKeyboard(false) end
                    Set("questItemHotkey", nil)
                    if EQT.ApplyQuestItemHotkey then EQT.ApplyQuestItemHotkey() end
                    RefreshLabel()
                    return
                end
                if listening then return end
                listening = true
                kbLbl:SetText(EllesmereUI.L("Press a key..."))
                kbBtn:EnableKeyboard(true)
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
                local mods = ""
                if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                if IsControlKeyDown() then mods = mods .. "CTRL-" end
                if IsAltKeyDown() then mods = mods .. "ALT-" end
                local fullKey = mods .. key
                Set("questItemHotkey", fullKey)
                if EQT.ApplyQuestItemHotkey then EQT.ApplyQuestItemHotkey() end
                listening = false
                self:EnableKeyboard(false)
                RefreshLabel()
            end)
            kbBtn:SetScript("OnEnter", function(self)
                kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
                if kbBtn._border and kbBtn._border.SetColor then
                    kbBtn._border:SetColor(1, 1, 1, 0.3)
                end
                EllesmereUI.ShowWidgetTooltip(self, "Left-click to set a keybind.\nRight-click to unbind.")
            end)
            kbBtn:SetScript("OnLeave", function()
                if listening then return end
                kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                if kbBtn._border and kbBtn._border.SetColor then
                    kbBtn._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
                end
                EllesmereUI.HideWidgetTooltip()
            end)
            EllesmereUI.RegisterWidgetRefresh(RefreshLabel)
            rgn:SetScript("OnHide", function()
                if listening then
                    listening = false
                    kbBtn:EnableKeyboard(false)
                    RefreshLabel()
                end
            end)
        end
        y = y - h

        return math.abs(y)
    end

    _G._EBS_BuildQuestTrackerPage = BuildPage

    EllesmereUI:RegisterModule("EllesmereUIQuestTracker", {
        title       = "Quest Tracker",
        description = "Blizzard tracker skin, visibility rules, auto-accept/turn-in, quest-item hotkey.",
        pages       = { "Quest Tracker" },
        buildPage   = function(pageName, p, yOffset) return BuildPage(pageName, p, yOffset) end,
        onReset = function()
            local d = _G._EQT_DB
            if d and d.ResetProfile then d:ResetProfile() end
            RefreshAll()
            EllesmereUI:InvalidatePageCache()
        end,
    })

    SLASH_EQTOPTS1 = "/eqtopts"
    SlashCmdList.EQTOPTS = function()
        if InCombatLockdown and InCombatLockdown() then return end
        EllesmereUI:ShowModule("EllesmereUIQuestTracker")
    end
end)
