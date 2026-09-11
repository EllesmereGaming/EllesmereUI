if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_QoL_RaidTools_Options.lua -- Raid Tools page of the QoL module
--
--  Not its own module: the page is registered by EUI_QoL_Options.lua, which
--  dispatches to the builder this file publishes as _G._EUI_BuildRaidToolsPage.
--  Same arrangement as the Cursor and Upgrade Calculator pages.
-------------------------------------------------------------------------------
local ns = EllesmereUI._ModuleNS["EllesmereUIQoL"]  -- module namespace (published by the module at its load)
if not ns then return end  -- module disabled: no options page

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- NOT gated on EllesmereUI.Widgets: on this LoadOnDemand addon the
    -- IsLoggedIn() re-fire below runs this handler at FILE SCOPE, before
    -- EnsureLoaded drains _deferredInits -- and the whole Widgets factory
    -- lives in a deferred body, so Widgets is always nil here. BuildPage
    -- reads it at panel-open time, after the drain, which is the only
    -- moment it is needed.
    if not EllesmereUI then return end

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

    local function QuickFireDisabled()
        return Disabled() or Cfg("quickFire") ~= true
    end

    -- The runtime owns the normalize (unknown values retain One Window).
    local function ShowAsVal()
        if ns.ShowAs then return ns.ShowAs() end
        return Cfg("showAs") or "one"
    end

    local function LegacyDisabled()
        return Disabled() or ShowAsVal() == "compact"
    end
    local function RoleCheckDisabled()
        return Disabled() or ShowAsVal() == "markers"
    end
    local function FullPanelButtonDisabled()
        local mode = ShowAsVal()
        return Disabled() or mode == "compact" or mode == "markers"
    end
    local function PullDisabled()
        return Disabled() or ShowAsVal() == "markers"
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

        -- Settings preview: with this page in front the windows force shown and fully
        -- expanded, so every change lands visibly instead of the collapse/visibility
        -- rules eating it (the TBB placeholder-mode arrangement). NEVER during Global
        -- Search's hidden pre-build, which builds every page once at startup.
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
              tooltip = "A raid control panel with ready check, pull timer and raid markers. In a raid it only shows while you are the leader or an assistant, since none of its buttons work without that; in a party it always shows.",
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
        if not EllesmereUI._prebuilding then
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
                   or key == "LALT" or key == "RALT" or key == "LMETA" or key == "RMETA" then
                    self:SetPropagateKeyboardInput(true); return
                end
                self:SetPropagateKeyboardInput(false)
                if key == "ESCAPE" then
                    listening = false; self:EnableKeyboard(false); RefreshLabel(); return
                end
                -- Blizzard's canonical chord order is ALT-CTRL-SHIFT-KEY, and
                -- CreateKeyChordStringUsingMetaKeyState is what produces it.
                -- Hand-rolling the modifiers built SHIFT-CTRL-ALT-KEY, a chord
                -- string the engine never generates, so any bind using more
                -- than one modifier was stored in a form nothing could match.
                -- Single-modifier binds happen to agree, which is why this
                -- survived.
                local fullKey
                if CreateKeyChordStringUsingMetaKeyState then
                    fullKey = CreateKeyChordStringUsingMetaKeyState(key)
                else
                    local mods = ""
                    if IsAltKeyDown() then mods = mods .. "ALT-" end
                    if IsControlKeyDown() then mods = mods .. "CTRL-" end
                    if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                    if IsMetaKeyDown and IsMetaKeyDown() then
                        mods = mods .. "META-"
                    end
                    fullKey = mods .. key
                end
                Set("toggleKey", fullKey)
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

            -- Spec Overrides capture: bespoke widget, so its SLOT opts in with a
            -- synthetic accessor (the label cfg carries no get/set of its own).
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

        -- Row 2: collapsed-when-shown default | window composition.
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Default to Collapsed When Shown",
              tooltip = "Full-window modes only. Shows start as a small icon, and the keybind switches between the icon and the full windows.",
              disabled = LegacyDisabled,
              getValue = function() return Cfg("collapsedIcon") ~= false end,
              setValue = function(v)
                  Set("collapsedIcon", v)
                  Refresh()
              end },
            { type = "dropdown", text = "Show as",
              tooltip = "Compact Band puts markers, ready check and pull timer in one resizable row. The other choices keep the original window layouts.",
              disabled = Disabled,
              values = { compact = "Compact Band", one = "One Window",
                         two = "Two Windows", group = "Only Group & Pull",
                         markers = "Only Markers" },
              order = { "compact", "one", "two", "group", "markers" },
              getValue = function() return ShowAsVal() end,
              setValue = function(v)
                  Set("showAs", v)
                  Refresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- Row 3: one scale for every layout | legacy menu grow direction.
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Window Scale", min = 0.5, max = 2.0, step = 0.05,
              disabled = Disabled,
              getValue = function() return Cfg("scale") or 1 end,
              setValue = function(v)
                  Set("scale", v)
                  Refresh()
              end },
            { type = "dropdown", text = "Menu Grow Direction",
              tooltip = "Full-window modes only. Which way the windows extend from the collapsed icon when they open.",
              disabled = LegacyDisabled,
              values = { downright = "Down Right", upright = "Up Right",
                         downleft = "Down Left", upleft = "Up Left" },
              order = { "downright", "upright", "downleft", "upleft" },
              getValue = function() return Cfg("growDir") or "downright" end,
              setValue = function(v)
                  Set("growDir", v)
                  Refresh()
              end }
        );  y = y - h

        -- QUICK FIRE
        -- An explicitly enabled, empty-by-default set of world-marker binds.
        _, h = W:SectionHeader(parent, "QUICK FIRE", y);  y = y - h

        local qfEnableRow
        qfEnableRow, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Quick Fire",
              tooltip = "Adds three optional world-marker keybinds that remain usable in combat. Place drops the first free marker at the cursor in Star to Skull order; Undo removes the last marker placed through Quick Fire; Clear removes all world markers. Every binding starts empty. Marker changes made elsewhere during combat are picked up afterward.",
              disabled = Disabled,
              getValue = function() return Cfg("quickFire") == true end,
              setValue = function(v)
                  Set("quickFire", v)
                  Refresh()
                  EllesmereUI:RefreshPage()
              end },
            { type = "label", text = "Place World Marker" }
        );  y = y - h

        local qfKeysRow
        qfKeysRow, h = W:DualRow(parent, y,
            { type = "label", text = "Undo Last Marker" },
            { type = "label", text = "Clear All Markers" }
        );  y = y - h

        if not EllesmereUI._prebuilding then
            local PP = EllesmereUI.PanelPP

            local function AddQuickFireKeybind(region, key)
                local button = CreateFrame("Button", nil, region)
                PP.Size(button, 126, 29)
                PP.Point(button, "RIGHT", region, "RIGHT", -20, 0)
                button:SetFrameLevel(region:GetFrameLevel() + 4)
                button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

                local bg = EllesmereUI.SolidTex(button, "BACKGROUND",
                    EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G,
                    EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                bg:SetAllPoints()
                button._border = EllesmereUI.MakeBorder(button, 1, 1, 1,
                    EllesmereUI.DD_BRD_A, PP)
                local label = EllesmereUI.MakeFont(button, 12, nil, 1, 1, 1)
                label:SetAlpha(EllesmereUI.DD_TXT_A)
                label:SetPoint("CENTER")

                local listening = false

                local function FormatKey(value)
                    if not value or value == "" then
                        return EllesmereUI.L("Not Bound")
                    end
                    local parts = {}
                    for mod in value:gmatch("(%u+)%-") do
                        parts[#parts + 1] = mod:sub(1, 1) .. mod:sub(2):lower()
                    end
                    parts[#parts + 1] = value:match("[^%-]+$") or value
                    return table.concat(parts, " + ")
                end

                local function RefreshState()
                    local off = QuickFireDisabled()
                    button:SetAlpha(off and 0.3 or 1)
                    button:EnableMouse(not off)
                    if region._label then region._label:SetAlpha(off and 0.3 or 1) end
                    if off and listening then
                        listening = false
                        button:EnableKeyboard(false)
                    end
                    if not listening then label:SetText(FormatKey(Cfg(key))) end
                end

                button:SetScript("OnClick", function(self, mouseButton)
                    if QuickFireDisabled() then return end
                    if mouseButton == "RightButton" then
                        if listening then
                            listening = false
                            self:EnableKeyboard(false)
                        end
                        Set(key, false)
                        Refresh()
                        RefreshState()
                        if EllesmereUI._NotifySettingWrite then
                            EllesmereUI._NotifySettingWrite(region)
                        end
                        return
                    end
                    if listening then return end
                    listening = true
                    label:SetText(EllesmereUI.L("Press a key..."))
                    self:EnableKeyboard(true)
                end)

                button:SetScript("OnKeyDown", function(self, pressed)
                    if not listening then
                        self:SetPropagateKeyboardInput(true)
                        return
                    end
                    if pressed == "LSHIFT" or pressed == "RSHIFT"
                       or pressed == "LCTRL" or pressed == "RCTRL"
                       or pressed == "LALT" or pressed == "RALT"
                       or pressed == "LMETA" or pressed == "RMETA" then
                        self:SetPropagateKeyboardInput(true)
                        return
                    end
                    self:SetPropagateKeyboardInput(false)
                    if pressed == "ESCAPE" then
                        listening = false
                        self:EnableKeyboard(false)
                        RefreshState()
                        return
                    end
                    -- Blizzard's canonical chord order is ALT-CTRL-SHIFT-KEY,
                    -- and CreateKeyChordStringUsingMetaKeyState is what
                    -- produces it. Hand-rolling the modifiers built
                    -- SHIFT-CTRL-ALT-KEY, a chord string the engine never
                    -- generates, so any bind using more than one modifier was
                    -- stored in a form nothing could match. Single-modifier
                    -- binds happen to agree, which is why this survived.
                    local fullPressed
                    if CreateKeyChordStringUsingMetaKeyState then
                        fullPressed = CreateKeyChordStringUsingMetaKeyState(pressed)
                    else
                        local mods = ""
                        if IsAltKeyDown() then mods = mods .. "ALT-" end
                        if IsControlKeyDown() then mods = mods .. "CTRL-" end
                        if IsShiftKeyDown() then mods = mods .. "SHIFT-" end
                        if IsMetaKeyDown and IsMetaKeyDown() then
                            mods = mods .. "META-"
                        end
                        fullPressed = mods .. pressed
                    end
                    Set(key, fullPressed)
                    Refresh()
                    listening = false
                    self:EnableKeyboard(false)
                    RefreshState()
                    if EllesmereUI._NotifySettingWrite then
                        EllesmereUI._NotifySettingWrite(region)
                    end
                end)

                button:SetScript("OnEnter", function(self)
                    if QuickFireDisabled() then
                        EllesmereUI.ShowWidgetTooltip(self,
                            EllesmereUI.DisabledTooltip("Enable Quick Fire"))
                        return
                    end
                    bg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G,
                        EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_HA)
                    if button._border and button._border.SetColor then
                        button._border:SetColor(1, 1, 1, 0.3)
                    end
                    EllesmereUI.ShowWidgetTooltip(self,
                        "Left-click to set a keybind.\nRight-click to unbind.")
                end)
                button:SetScript("OnLeave", function()
                    if listening then return end
                    bg:SetColorTexture(EllesmereUI.DD_BG_R, EllesmereUI.DD_BG_G,
                        EllesmereUI.DD_BG_B, EllesmereUI.DD_BG_A)
                    if button._border and button._border.SetColor then
                        button._border:SetColor(1, 1, 1, EllesmereUI.DD_BRD_A)
                    end
                    EllesmereUI.HideWidgetTooltip()
                end)
                button:SetScript("OnHide", function()
                    if listening then
                        listening = false
                        button:EnableKeyboard(false)
                        RefreshState()
                    end
                    EllesmereUI.HideWidgetTooltip()
                end)

                RefreshState()
                EllesmereUI.RegisterWidgetRefresh(RefreshState)
                EllesmereUI.AddCaptureAccessor(region, {
                    type = "keybind",
                    text = region._label and region._label:GetText() or key,
                    getValue = function() return Cfg(key) end,
                    setValue = function(v)
                        Set(key, v)
                        Refresh()
                        RefreshState()
                    end,
                })
            end

            AddQuickFireKeybind(qfEnableRow._rightRegion, "quickFirePlaceKey")
            AddQuickFireKeybind(qfKeysRow._leftRegion, "quickFireUndoKey")
            AddQuickFireKeybind(qfKeysRow._rightRegion, "quickFireClearKey")
        end

        -- GROUP BUTTONS
        --
        -- One switch per optional action. Ready Check has none: it is the
        -- reason the panel exists. Turning a button off closes the gap it
        -- leaves -- the survivors re-flow across the rows.
        _, h = W:SectionHeader(parent, "GROUP BUTTONS", y);  y = y - h

        local function ButtonToggle(key, text, tooltip, disabled)
            return { type = "toggle", text = text, tooltip = tooltip,
                     disabled = disabled or Disabled,
                     getValue = function() return Cfg(key) ~= false end,
                     setValue = function(v)
                         Set(key, v)
                         Refresh()
                     end }
        end

        _, h = W:DualRow(parent, y,
            ButtonToggle("showRoleCheck", "Show Role Check",
                "Shows the Role Check button in window layouts and enables Right Click: Role Check on Compact Band.",
                RoleCheckDisabled),
            ButtonToggle("showConvert", "Show Convert to Raid",
                "Shows the Convert to Raid button, which reads Convert to Party while you are in a raid.",
                FullPanelButtonDisabled)
        );  y = y - h
        _, h = W:DualRow(parent, y,
            ButtonToggle("showDisband", "Show Disband",
                "Shows the Disband button. It always asks before disbanding, but hiding it puts it out of misclick range for good.",
                FullPanelButtonDisabled),
            { type = "spacer" }
        );  y = y - h

        -- PULL TIMER
        _, h = W:SectionHeader(parent, "PULL TIMER", y);  y = y - h

        local PULL_LABELS = { "First Timer", "Second Timer", "Third Timer" }
        local PULL_TIP = "Countdown length in seconds. Compact Band uses First with Ctrl + Left Click, Second with Shift + Left Click, Third with Left Click, and Right Click stops the timer. Set a timer to 0 to disable that shortcut."
        local function PullSlider(i)
            return { type="slider", text=PULL_LABELS[i], min=0, max=60, step=1,
                     tooltip=PULL_TIP,
                     disabled=PullDisabled,
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
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
