-------------------------------------------------------------------------------
--  EUI_QoL_RaidTools_Options.lua -- Raid Tools page of the QoL module
--
--  Not its own module: the page is registered by EUI_QoL_Options.lua, which
--  dispatches to the builder this file publishes as _G._EUI_BuildRaidToolsPage.
--  Same arrangement as the Cursor and Upgrade Calculator pages.
-------------------------------------------------------------------------------
local _, ns = ...

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not EllesmereUI or not EllesmereUI.Widgets then return end

    -- Settings live in one slice of the shared QoL profile, so every read here
    -- goes through the same handle the runtime publishes.
    --
    -- A PURE READ, with no `or {}` seeding: every getter on this page runs
    -- through it during a Spec Overrides capture, which swaps the profile for
    -- a read-tracking proxy. Writing back what was just read stores a proxy in
    -- the real table and each later call wraps it again, until reading a leaf
    -- overflows the C stack. DB_DEFAULTS guarantees the slice exists.
    local function DB()
        local get = _G._EUI_RaidTools_DB
        local root = get and get()
        return root and root.profile and root.profile.raidTools
    end

    local function Cfg(key)
        local p = DB()
        return p and p[key]
    end

    local function Set(key, val)
        local p = DB()
        if p then p[key] = val end
    end

    local function Refresh()
        if _G._EUI_RaidTools_Apply then _G._EUI_RaidTools_Apply() end
    end

    local function Disabled()
        return (Cfg("mode") or "never") == "never"
    end

    -- The runtime owns the normalize (unknown values read as "one").
    local function ShowAsVal()
        if ns.ShowAs then return ns.ShowAs() end
        return Cfg("showAs") or "one"
    end

    -- Pull durations live in a fixed 3-slot array; each slider owns one slot.
    local function PullGet(i)
        local t = Cfg("pullTimes")
        return (t and t[i]) or ns.PULL_DEFAULTS[i]
    end

    local function PullSet(i, v)
        local t = Cfg("pullTimes")
        if not t then return end
        t[i] = v
        Refresh()
    end

    local function BuildPage(pageName, parent, yOffset)
        local W = EllesmereUI.Widgets
        local y = yOffset
        local _, h

        EllesmereUI:ClearContentHeader()

        -- Settings preview: with this page in front the windows force shown
        -- and fully expanded, so every change lands visibly instead of the
        -- collapse/visibility rules eating it (the TBB placeholder-mode
        -- arrangement). NEVER during Global Search's hidden pre-build, which
        -- builds every page once at startup.
        if not EllesmereUI._prebuilding and _G._EUI_RaidTools_Preview then
            _G._EUI_RaidTools_Preview(true)
        end

        -- GENERAL
        _, h = W:SectionHeader(parent, "GENERAL", y);  y = y - h

        -- Row 1: Show Raid Tools mode | Toggle Raid Tools keybind.
        -- The mode dropdown IS the on/off switch: Never means nothing is
        -- built at all (no frames, events, bindings or unlock rows), which is
        -- why there is no separate Enable toggle.
        local kbRow
        kbRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Show Raid Tools",
              tooltip = "A raid control panel with ready check, pull timer and raid markers.",
              values = { never = "Never", raid = "In Raid Group",
                         group = "In Any Group", always = "Always" },
              order = { "never", "raid", "group", "always" },
              getValue = function() return Cfg("mode") or "never" end,
              setValue = function(v)
                  Set("mode", v)
                  Refresh()
                  EllesmereUI:RefreshPage()
              end },
            { type = "label", text = "Toggle Raid Tools" }
        );  y = y - h

        -- Keybind button in the label's slot -- the exact Toggle Action Bar
        -- Visibility arrangement from Action Bars: profile-stored key, click
        -- to capture, right-click to unbind, Escape cancels. The bound key is
        -- an override binding on the secure toggle button, so pressing it
        -- works in combat; only the (re)binding itself waits for combat end.
        do
            local PP  = EllesmereUI.PanelPP
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
                local k = Cfg("toggleKey")
                if k == false then k = nil end
                kbLbl:SetText(FormatKey(k))
            end

            local function RefreshState()
                local off = Disabled()
                kbBtn:SetAlpha(off and 0.3 or 1)
                kbBtn:EnableMouse(not off)
                if rgn._label then rgn._label:SetAlpha(off and 0.3 or 1) end
                if off and listening then
                    listening = false
                    kbBtn:EnableKeyboard(false)
                end
                RefreshLabel()
            end

            kbBtn:SetScript("OnClick", function(self, button)
                if Disabled() then return end
                if button == "RightButton" then
                    if listening then listening = false; self:EnableKeyboard(false) end
                    Set("toggleKey", false)
                    Refresh()
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
                local mods = ""
                if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                if IsControlKeyDown() then mods = mods .. "CTRL-" end
                if IsAltKeyDown() then mods = mods .. "ALT-" end
                Set("toggleKey", mods .. key)
                Refresh()
                listening = false
                self:EnableKeyboard(false)
                RefreshLabel()
                if EllesmereUI._NotifySettingWrite then EllesmereUI._NotifySettingWrite(rgn) end
            end)

            kbBtn:SetScript("OnEnter", function(self)
                if Disabled() then
                    EllesmereUI.ShowWidgetTooltip(self, EllesmereUI.DisabledTooltip("Show Raid Tools"))
                    return
                end
                kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
                if kbBtn._border and kbBtn._border.SetColor then kbBtn._border:SetColor(1, 1, 1, 0.3) end
                EllesmereUI.ShowWidgetTooltip(self, "Toggles the Raid Tools panels, in or out of combat.\n\nLeft-click to set a keybind.\nRight-click to unbind.")
            end)
            kbBtn:SetScript("OnLeave", function()
                if listening then return end
                kbBg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G, EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                if kbBtn._border and kbBtn._border.SetColor then kbBtn._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A) end
                EllesmereUI.HideWidgetTooltip()
            end)
            kbBtn:SetScript("OnHide", function()
                -- Closing the EUI window mid-capture must cancel the capture
                -- AND hide the tooltip. OnLeave skips the hide while listening
                -- (and may not fire at all if the mouse never left), so the
                -- tooltip would otherwise linger after the window is gone.
                if listening then listening = false; kbBtn:EnableKeyboard(false); RefreshLabel() end
                EllesmereUI.HideWidgetTooltip()
            end)

            RefreshState()
            EllesmereUI.RegisterWidgetRefresh(RefreshState)

            -- Spec Overrides capture: bespoke widget, so its SLOT opts in
            -- with a synthetic accessor (the label cfg carries no get/set of
            -- its own).
            EllesmereUI.AddCaptureAccessor(rgn, {
                type = "keybind", text = "Toggle Raid Tools",
                getValue = function() return Cfg("toggleKey") end,
                setValue = function(v)
                    Set("toggleKey", v)
                    Refresh()
                    RefreshLabel()
                end,
            })
        end

        -- Row 2: collapsed-when-shown default | window composition. One rule
        -- for every show, keybind included -- a user who wants the keybind to
        -- toggle the full windows simply turns this off.
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Default to Collapsed When Shown",
              tooltip = "Shows start as a small icon, and the keybind switches between the icon and the full windows. Turn off to show full windows and make the keybind hide and show them.",
              disabled = Disabled,
              getValue = function() return Cfg("collapsedIcon") ~= false end,
              setValue = function(v)
                  Set("collapsedIcon", v)
                  Refresh()
              end },
            { type = "dropdown", text = "Show as",
              tooltip = "One Window combines everything into a single element; the Only choices show just that part.",
              disabled = Disabled,
              values = { one = "One Window", two = "Two Windows",
                         group = "Only Group & Pull", markers = "Only Markers" },
              order = { "one", "two", "group", "markers" },
              getValue = function() return ShowAsVal() end,
              setValue = function(v)
                  Set("showAs", v)
                  Refresh()
                  EllesmereUI:RefreshPage()  -- the scale sliders follow
              end }
        );  y = y - h

        -- Row 3: one scale for the whole feature -- both shells and the
        -- collapsed icon wear it, whichever windows the Show as choice puts
        -- on screen.
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Window Scale", min = 0.5, max = 2.0, step = 0.05,
              disabled = Disabled,
              getValue = function() return Cfg("scale") or 1 end,
              setValue = function(v)
                  Set("scale", v)
                  Refresh()
              end },
            { type = "label", text = "" }
        );  y = y - h

        -- PULL TIMER
        _, h = W:SectionHeader(parent, "PULL TIMER", y);  y = y - h

        local PULL_LABELS = { "First Timer", "Second Timer", "Third Timer" }
        local function PullSlider(i)
            return { type="slider", text=PULL_LABELS[i], min=1, max=60, step=1,
                     disabled=Disabled,
                     getValue=function() return PullGet(i) end,
                     setValue=function(v) PullSet(i, v) end }
        end

        _, h = W:DualRow(parent, y, PullSlider(1), PullSlider(2));      y = y - h
        _, h = W:DualRow(parent, y, PullSlider(3), { type="spacer" });  y = y - h

        return math.abs(y)
    end

    _G._EUI_BuildRaidToolsPage = BuildPage

    -- Preview exits that the page dispatcher cannot see: the options window
    -- closing, and a switch to another MODULE (switching pages inside QoL is
    -- handled by the dispatcher in EUI_QoL_Options.lua). Both are idempotent
    -- no-ops when the preview is already off.
    local function StopPreview()
        if _G._EUI_RaidTools_Preview then _G._EUI_RaidTools_Preview(false) end
    end
    EllesmereUI:RegisterOnHide(StopPreview)
    -- REOPENING the window fires neither buildPage nor onPageCacheRestore --
    -- it just Shows with the previous layout intact -- so the show-side
    -- callback re-enters the preview when our page is still the one in front.
    -- The page string must match PAGE_RAIDTOOLS in EUI_QoL_Options.lua.
    EllesmereUI:RegisterOnShow(function()
        if EllesmereUI.GetActiveModule and EllesmereUI:GetActiveModule() == "EllesmereUIQoL"
           and EllesmereUI.GetActivePage and EllesmereUI:GetActivePage() == "Raid Tools"
           and _G._EUI_RaidTools_Preview then
            _G._EUI_RaidTools_Preview(true)
        end
    end)
    if EllesmereUI.SelectModule then
        hooksecurefunc(EllesmereUI, "SelectModule", function(_, folderName)
            if folderName ~= "EllesmereUIQoL" then StopPreview() end
        end)
    end
end)
