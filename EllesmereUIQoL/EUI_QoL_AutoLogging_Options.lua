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

local function TeleCfg()
    if not EllesmereUIDB then return {} end
    EllesmereUIDB.teleportPrompt = EllesmereUIDB.teleportPrompt or {}
    return EllesmereUIDB.teleportPrompt
end

-- Built as the tail of the Quality of Life page (chained from BuildQoLPage),
-- not as its own tab. Lays out from yOffset and returns the height used,
-- like every other section builder.
local function BuildAutoLoggingPage(pageName, parent, yOffset)
    local W  = EllesmereUI.Widgets
    local PP = EllesmereUI.PanelPP
    local y  = yOffset
    local _, h

    parent._showRowDivider = true

    ---------------------------------------------------------------------------
    --  KEYSTONE CHECK POPUP
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "KEYSTONE CHECK POPUP", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type    = "toggle",
          text    = "Enable /keys Popup (or /ekeys)",
          tooltip = "Shows a popup with party and guild keystones when typing /keys.",
          -- DependentSetValue: the Window Scale row below is hidden while the
          -- popup is off; the flip forces the full rebuild.
          setValue = EllesmereUI.DependentSetValue(
              function() return KeysCfg().enabled ~= false end,
              function(v)
                  KeysCfg().enabled = v
                  EllesmereUI:RefreshPage()
                  EllesmereUI:ShowConfirmPopup({
                      title = "Reload Required",
                      message = "Changing the /keys popup requires a reload to update slash command registration.",
                      confirmText = "Reload",
                      cancelText = "Later",
                      onConfirm = function() ReloadUI() end,
                  })
              end),
          getValue = function() return KeysCfg().enabled ~= false end },
        { type    = "slider",
          text    = "Text Size",
          min     = 8, max = 16, step = 1,
          disabled = function() return KeysCfg().enabled == false end,
          disabledTooltip = "/keys Popup",
          tooltip = "Font size for keystone entries in the popup (does not affect the header).",
          getValue = function() return KeysCfg().textSize or 11 end,
          setValue = function(v)
              KeysCfg().textSize = v
              if _G._EUI_RefreshKeystonePopup then _G._EUI_RefreshKeystonePopup() end
          end }
    ); y = y - h

    -- Window Scale row: HIDDEN entirely while the /keys popup is off.
    if KeysCfg().enabled ~= false then
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
    end   -- close /keys popup hidden-while-disabled gate

    _, h = W:Spacer(parent, y, 20); y = y - h

    ---------------------------------------------------------------------------
    --  LFG REMINDER
    ---------------------------------------------------------------------------
    _, h = W:SectionHeader(parent, "LFG REMINDER", y); y = y - h

    _, h = W:DualRow(parent, y,
        { type    = "toggle",
          text    = "Enable LFG Reminder",
          tooltip = "When you join a Group Finder group for a dungeon that has a teleport, shows a small movable popup with the dungeon name and a one-click teleport button. It hides when you enter the dungeon, leave the group, or enter combat.",
          getValue = function() return TeleCfg().enabled ~= false end,
          -- DependentSetValue: the Show 'Disable Feature' Text row below is
          -- hidden while the reminder is off; the flip forces the rebuild.
          setValue = EllesmereUI.DependentSetValue(
              function() return TeleCfg().enabled ~= false end,
              function(v)
                  TeleCfg().enabled = v
                  EllesmereUI:RefreshPage()
                  -- Applies live in both directions: enable builds the popup and
                  -- registers events, disable hides and unregisters.
                  if _G._EUI_ApplyTeleportPrompt then _G._EUI_ApplyTeleportPrompt() end
              end) },
        { type    = "slider",
          text    = "Window Scale",
          min     = 50, max = 150, step = 5,
          disabled = function() return TeleCfg().enabled == false end,
          disabledTooltip = "LFG Reminder",
          tooltip = "Scale of the LFG Reminder popup window.",
          getValue = function() return math.floor((TeleCfg().scale or 1.05) * 100 + 0.5) end,
          setValue = function(v)
              TeleCfg().scale = v / 100
              if _G._EUI_RefreshTeleportPrompt then _G._EUI_RefreshTeleportPrompt() end
          end }
    ); y = y - h

    -- Show 'Disable Feature' Text row: HIDDEN while the reminder is off.
    if TeleCfg().enabled ~= false then
    _, h = W:DualRow(parent, y,
        { type    = "toggle",
          text    = "Show 'Disable Feature' Text",
          tooltip = "Shows the 'Disable Feature' text below the teleport button. When off, the text is hidden and the window is 20px shorter.",
          getValue = function() return TeleCfg().showDisable ~= false end,
          setValue = function(v)
              TeleCfg().showDisable = v
              if _G._EUI_RefreshTeleportPrompt then _G._EUI_RefreshTeleportPrompt() end
          end },
        { type = "label", text = "" }
    ); y = y - h
    end   -- close LFG Reminder hidden-while-disabled gate

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
          -- DependentSetValue: the Warcraft Recorder row below is hidden
          -- while auto logging is off; the flip forces the full rebuild.
          setValue = EllesmereUI.DependentSetValue(
              function() return Cfg().enabled == true end,
              function(v)
                  Cfg().enabled = v or nil
                  Recheck()
                  EllesmereUI:RefreshPage()
              end) },
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

        -- Gray + block the triggers dropdown (and its label) while Auto
        -- Logging is off; the CB dropdown has no native disabled handling.
        local function UpdateTrigDisabled()
            local off = Cfg().enabled ~= true
            cbDD:SetAlpha(off and 0.3 or 1)
            cbDD:EnableMouse(not off)
            if rightRgn._label then rightRgn._label:SetAlpha(off and 0.3 or 1) end
        end
        UpdateTrigDisabled()
        EllesmereUI.RegisterWidgetRefresh(UpdateTrigDisabled)
    end

    -- Warcraft Recorder row: HIDDEN entirely while Auto Logging is off.
    if Cfg().enabled == true then
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
    end   -- close Auto Logging hidden-while-disabled gate

    _, h = W:Spacer(parent, y, 20); y = y - h

    ---------------------------------------------------------------------------
    --  BATTLE RES
    ---------------------------------------------------------------------------
    if _G._EUI_BuildBattleResSection then
        local brezH = _G._EUI_BuildBattleResSection(parent, y, W, EllesmereUI.PP)
        y = y - brezH
    end

    ---------------------------------------------------------------------------
    --  BLOODLUST TRACKER
    ---------------------------------------------------------------------------
    if _G._EUI_BuildBloodlustSection then
        local lustH = _G._EUI_BuildBloodlustSection(parent, y, W, EllesmereUI.PP)
        y = y - lustH
    end

    return math.abs(y - yOffset)
end

_G._EUI_BuildAutoLoggingPage = BuildAutoLoggingPage
