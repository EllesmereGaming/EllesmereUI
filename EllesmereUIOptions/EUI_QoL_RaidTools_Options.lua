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
            local rgn = kbRow._rightRegion
            local kbBtn, refresh = EllesmereUI.BuildKeybindButton(rgn, {
                w = 126, h = 29, level = 4,
                get = function() return Cfg("toggleKey") end,
                set = function(v)
                    Set("toggleKey", v or false)
                    Refresh()
                    EllesmereUI._NotifySettingWrite(rgn)
                end,
                disabled = Disabled, disabledTip = "Show Raid Tools",
                tooltip = "Toggles the Raid Tools panels, in or out of combat.\n\nLeft-click to set a keybind.\nRight-click to unbind.",
            })
            EllesmereUI.PanelPP.Point(kbBtn, "RIGHT", rgn, "RIGHT", -20, 0)
            EllesmereUI.RegisterWidgetRefresh(refresh)

            -- Spec Overrides capture: bespoke widget, so its SLOT opts in with a
            -- synthetic accessor (the label cfg carries no get/set of its own).
            EllesmereUI.AddCaptureAccessor(rgn, {
                type = "keybind", text = "Toggle Raid Tools",
                getValue = function() return Cfg("toggleKey") end,
                setValue = function(v)
                    Set("toggleKey", v)
                    Refresh()
                    refresh()
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
                local button, refresh = EllesmereUI.BuildKeybindButton(region, {
                    w = 126, h = 29, level = 4, mouse = true,
                    get = function() return Cfg(key) end,
                    set = function(v)
                        Set(key, v or false)
                        Refresh()
                        EllesmereUI._NotifySettingWrite(region)
                    end,
                    disabled = QuickFireDisabled,
                    disabledTip = function() return Disabled() and "Show Raid Tools" or "Enable Quick Fire" end,
                })
                PP.Point(button, "RIGHT", region, "RIGHT", -20, 0)
                EllesmereUI.RegisterWidgetRefresh(refresh)
                EllesmereUI.AddCaptureAccessor(region, {
                    type = "keybind",
                    text = region._label and region._label:GetText() or key,
                    getValue = function() return Cfg(key) end,
                    setValue = function(v)
                        Set(key, v)
                        Refresh()
                        refresh()
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
        if EllesmereUI:GetActiveModule() == "EllesmereUIQoL"
           and EllesmereUI:GetActivePage() == "Raid Tools"
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
