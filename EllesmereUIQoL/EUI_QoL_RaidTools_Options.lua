-------------------------------------------------------------------------------
--  EUI_QoL_RaidTools_Options.lua  —  Raid Tools page of the QoL module
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
        return Cfg("enabled") == false
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

        -- GENERAL
        _, h = W:SectionHeader(parent, "GENERAL", y);  y = y - h

        -- Visibility | Enable on one row. Other pages put the "Visibility
        -- Options" checkbox dropdown in this right slot, but those options
        -- (Only Show in Instances, Hide when Mounted...) are evaluated in Lua
        -- and never compiled by BuildVisModeConjuncts, which handles only the
        -- skyriding, combat and group axes. On a panel driven by a secure state
        -- driver they would be a control that does nothing, so Enable sits here
        -- instead.
        _, h = EllesmereUI.BuildVisibilityModeRow(W, parent, y,
            { getStore = DB, legacyKey = ns.VIS_KEY, caps = ns.VIS_CAPS,
              disabledFn = Disabled,
              tooltip = "When the panels show on their own. Buttons still grey out unless you are leader or assist -- leader status is not something the game lets an addon watch securely, so it cannot drive this.",
              onChanged = Refresh },
            { type="toggle", text="Enable",
              tooltip="A raid control panel with ready check, pull timer and raid markers.",
              getValue=function() return Cfg("enabled") == true end,
              setValue=function(v)
                  Set("enabled", v)
                  Refresh()
                  EllesmereUI:RefreshPage()
              end }
        );  y = y - h

        -- PANELS
        _, h = W:SectionHeader(parent, "PANELS", y);  y = y - h

        local function SectionToggle(key, label, tip)
            return { type="toggle", text=label, tooltip=tip, disabled=Disabled,
                     getValue=function() return ns.SectionEnabled(key) end,
                     setValue=function(v)
                         local p = DB(); if not p then return end
                         p.sections = p.sections or {}
                         p.sections[key] = v
                         Refresh()
                         EllesmereUI:RefreshPage()  -- its scale slider follows
                     end }
        end

        -- Each panel is sized on its own, so the slider sits next to its toggle
        -- rather than in a separate list the user has to map back by name.
        local function SectionScaleSlider(key, label)
            return { type="slider", text=label, min=0.5, max=2.0, step=0.05,
                     disabled=function() return Disabled() or not ns.SectionEnabled(key) end,
                     disabledTooltip="Enable this panel first", rawTooltip=true,
                     getValue=function()
                         return ns.SectionScale(key)
                     end,
                     setValue=function(v)
                         local p = DB(); if not p then return end
                         p.scales = p.scales or {}
                         p.scales[key] = v
                         Refresh()
                     end }
        end

        for _, def in ipairs(ns.SECTIONS) do
            _, h = W:DualRow(parent, y,
                SectionToggle(def.key, def.label, def.tip),
                SectionScaleSlider(def.key, def.label .. " Scale")
            );  y = y - h
        end

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
end)
