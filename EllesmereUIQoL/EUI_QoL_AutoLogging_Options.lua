-------------------------------------------------------------------------------
--  EUI_QoL_AutoLogging_Options.lua
--  Options page for the Auto Combat Logging feature.
-------------------------------------------------------------------------------

-- Must match TRIGGER_DEFAULTS in the runtime.
local TRIGGER_DEFAULTS = {
    logMythic   = true,
    logHeroic   = true,
    logNormal   = true,
    logLFR      = true,
    log5pp      = true,
    logArena    = true,
    logScenario = false,
    delaystop   = true,
}

local TRIGGER_ITEMS = {
    { key = "logMythic",   label = "Mythic Raid" },
    { key = "logHeroic",   label = "Heroic Raid" },
    { key = "logNormal",   label = "Normal Raid" },
    { key = "logLFR",      label = "LFR" },
    { key = "log5pp",      label = "Mythic+ Dungeons" },
    { key = "logArena",    label = "Arena" },
    { key = "logScenario", label = "Scenarios" },
}

local function Cfg()
    if not EllesmereUIDB then return {} end
    EllesmereUIDB.autoLogging = EllesmereUIDB.autoLogging or {}
    return EllesmereUIDB.autoLogging
end

local function Recheck()
    if _G._EUI_AutoLogging_Check then _G._EUI_AutoLogging_Check() end
end

local function KeysCfg()
    if not EllesmereUIDB then return {} end
    EllesmereUIDB.keystonePopup = EllesmereUIDB.keystonePopup or {}
    return EllesmereUIDB.keystonePopup
end

local function BuildAutoLoggingPage(pageName, parent, yOffset)
    local W  = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local y  = yOffset
    local _, h

    if EllesmereUI.ClearContentHeader then EllesmereUI:ClearContentHeader() end
    parent._showRowDivider = true

    ---------------------------------------------------------------------------
    --  KEYSTONE CHECK POPUP
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "KEYSTONE CHECK POPUP", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type    = "toggle",
          text    = "Enable /keys Popup",
          tooltip = "Shows a popup with party and guild keystones when typing /keys.",
          getValue = function() return KeysCfg().enabled ~= false end,
          setValue = function(v)
              KeysCfg().enabled = v
              EllesmereUI:RefreshPage()
          end },
        { type    = "slider",
          text    = "Text Size",
          min     = 8, max = 16, step = 1,
          tooltip = "Font size for keystone entries in the popup (does not affect the header).",
          getValue = function() return KeysCfg().textSize or 11 end,
          setValue = function(v)
              KeysCfg().textSize = v
              if _G._EUI_RefreshKeystonePopup then _G._EUI_RefreshKeystonePopup() end
          end }
    ); y = y - h

    _, h = W:DualRow(parent, y,
        { type    = "slider",
          text    = "Window Scale",
          min     = 50, max = 150, step = 5,
          tooltip = "Scale of the /keys popup window.",
          getValue = function() return math.floor((KeysCfg().scale or 1.05) * 100 + 0.5) end,
          setValue = function(v)
              KeysCfg().scale = v / 100
              local popup = _G.EUIKeysPopup
              if popup then popup:SetScale(v / 100) end
          end },
        { type = "label", text = "" }
    ); y = y - h

    _, h = W:Spacer(parent, y, 20); y = y - h

    ---------------------------------------------------------------------------
    --  AUTO COMBAT LOGGING
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "AUTO COMBAT LOGGING", y); y = y - h

    local trigRow, trigH = W:DualRow(parent, y,
        { type    = "toggle",
          text    = "Enable Auto Logging",
          tooltip = "Automatically starts and stops combat logging when entering or leaving a loggable instance.",
          getValue = function() return Cfg().enabled == true end,
          setValue = function(v)
              Cfg().enabled = v or nil
              Recheck()
              EllesmereUI:RefreshPage()
          end },
        { type    = "dropdown", text = "Auto-Log Triggers",
          values  = { __placeholder = "..." }, order = { "__placeholder" },
          getValue = function() return "__placeholder" end,
          setValue = function() end }
    ); y = y - trigH

    -- Replace dummy dropdown with a checkbox dropdown.
    do
        local rightRgn = trigRow._rightRegion
        if rightRgn._control then rightRgn._control:Hide() end

        local cbDD, cbDDRefresh = EllesmereUI.BuildVisOptsCBDropdown(
            rightRgn,
            210,
            rightRgn:GetFrameLevel() + 2,
            TRIGGER_ITEMS,
            function(k)
                local v = Cfg()[k]
                if v == nil then return TRIGGER_DEFAULTS[k] end
                return v
            end,
            function(k, v) Cfg()[k] = v; Recheck() end
        )
        PP.Point(cbDD, "RIGHT", rightRgn, "RIGHT", -20, 0)
        rightRgn._control = cbDD
        rightRgn._lastInline = nil

        EllesmereUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    _, h = W:DualRow(parent, y,
        { type    = "toggle",
          text    = "Warcraft Recorder Compatibility",
          tooltip = "Delays stopping combat logging by 30 seconds after leaving an instance. Recommended for Warcraft Recorder compatibility.",
          getValue = function()
              local v = Cfg().delaystop
              if v == nil then return TRIGGER_DEFAULTS.delaystop end
              return v
          end,
          setValue = function(v)
              Cfg().delaystop = v
          end },
        { type = "label", text = "" }
    ); y = y - h

    parent:SetHeight(math.abs(y - yOffset))
end

_G._EUI_BuildAutoLoggingPage = BuildAutoLoggingPage
