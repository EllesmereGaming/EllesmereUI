if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EUI_QoL_Alerts_Options.lua
--  ALERTS section: Combat Alert, Potion Ready Alert and Unspent Talents Alert.
--  They share one movable anchor (Unlock Mode: Alerts); each has its own text,
--  size and color. The runtime is EllesmereUIQoL_Alerts.lua.
-------------------------------------------------------------------------------

if not EllesmereUI._ModuleNS["EllesmereUIQoL"] then return end  -- module disabled: no options page

-- Text, size, color and class-color rows for the Potion / Talent alerts
-- (keys: <prefix>Text / TextSize / Color / UseClassColor; defaults come from
-- the alert itself so the swatch always shows the real default).
local function AlertCogRows(prefix, applyFrame, preview)
    local D = (EllesmereUI.Alerts and EllesmereUI.Alerts.DEFAULTS[prefix])
        or { text = "", color = { r = 1, g = 1, b = 1 } }
    local function db(k) return EllesmereUIDB and EllesmereUIDB[prefix .. k] end
    local function put(k, v)
        if not EllesmereUIDB then EllesmereUIDB = {} end
        EllesmereUIDB[prefix .. k] = v
    end
    return {
        { type="input", label="Text", inputWidth=130,
          get=function() return db("Text") or D.text end,
          set=function(v) put("Text", v); if EllesmereUI[preview] then EllesmereUI[preview]() end end },
        { type="slider", label="Text Size", min=14, max=64, step=1,
          get=function() return db("TextSize") or 22 end,
          set=function(v)
            put("TextSize", v)
            if EllesmereUI[applyFrame] then EllesmereUI[applyFrame]() end
            if EllesmereUI[preview] then EllesmereUI[preview]() end
          end },
        { type="colorpicker", label="Color",
          disabled=function() return db("UseClassColor") end,
          disabledTooltip="Disable Class Color to pick a custom color.", rawTooltip=true,
          get=function()
            local c = db("Color") or D.color
            return c.r, c.g, c.b
          end,
          set=function(r, g, b)
            put("Color", { r=r, g=g, b=b })
            if EllesmereUI[preview] then EllesmereUI[preview]() end
          end },
        { type="toggle", label="Class Color",
          get=function() return db("UseClassColor") end,
          set=function(v) put("UseClassColor", v); if EllesmereUI[preview] then EllesmereUI[preview]() end end },
    }
end

_G._EUI_BuildAlertsSection = function(parent, yOffset, W, PP)
    local y = yOffset
    local _, h

    _, h = W:SectionHeader(parent, "ALERTS", y); y = y - h

    local row1
    row1, h = W:DualRow(parent, y,
        { type="toggle", text="Combat Alert",
          tooltip="Shows a large on-screen text when you enter and/or leave combat (e.g. \"+Combat\" / \"-Combat\"). Use the cog to set the display text, size, colors and which transitions are shown; use Unlock Mode to reposition the alert.",
          getValue=function()
              return EllesmereUIDB and EllesmereUIDB.combatAlertEnabled or false
          end,
          setValue=function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.combatAlertEnabled = v
              if EllesmereUI._applyCombatAlert then EllesmereUI._applyCombatAlert() end
              EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Potion Ready Alert",
          tooltip="Shows on-screen text when a potion you used is off cooldown again. Use the cog to set the text, size and color; use Unlock Mode to reposition the alerts.",
          getValue=function()
              return EllesmereUIDB and EllesmereUIDB.potionAlertEnabled or false
          end,
          setValue=function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.potionAlertEnabled = v
              if EllesmereUI._applyPotionAlert then EllesmereUI._applyPotionAlert() end
              EllesmereUI:RefreshPage()
          end }
    );  y = y - h

    local row2
    row2, h = W:DualRow(parent, y,
        { type="toggle", text="Unspent Talents Alert",
          tooltip="Shows on-screen text while you have unspent talent points. It stays up until you spend them or middle-click it away, and returns when new points appear. Use the cog to set the text, size and color; use Unlock Mode to reposition the alerts.",
          getValue=function()
              return EllesmereUIDB and EllesmereUIDB.talentAlertEnabled or false
          end,
          setValue=function(v)
              if not EllesmereUIDB then EllesmereUIDB = {} end
              EllesmereUIDB.talentAlertEnabled = v
              if EllesmereUI._applyTalentAlert then EllesmereUI._applyTalentAlert() end
              EllesmereUI:RefreshPage()
          end },
        EllesmereUI.BlankRowCfg()
    );  y = y - h

    -- Inline cog (text, size, colors, mode) on the Combat Alert toggle.
    if not EllesmereUI._prebuilding then
        local leftRgn = row1._leftRegion
        local function caOff()
            return not (EllesmereUIDB and EllesmereUIDB.combatAlertEnabled)
        end
        local function enterClassOn()
            return EllesmereUIDB and EllesmereUIDB.combatAlertEnterUseClassColor
        end
        local function leaveClassOn()
            return EllesmereUIDB and EllesmereUIDB.combatAlertLeaveUseClassColor
        end

        local caModeValues = {
            both  = "Enter & Leave",
            enter = "Enter Only",
            leave = "Leave Only",
        }
        local caModeOrder = { "both", "enter", "leave" }

        EllesmereUI.BuildInlineCog(leftRgn, {
            title = "Combat Alert Settings",
            minWidth = 300,
            rows = {
                { type="dropdown", label="Show On",
                  values=caModeValues, order=caModeOrder,
                  get=function() return (EllesmereUIDB and EllesmereUIDB.combatAlertMode) or "both" end,
                  set=function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.combatAlertMode = v
                  end },
                { type="slider", label="Text Size",
                  min=14, max=64, step=1,
                  get=function()
                    return (EllesmereUIDB and EllesmereUIDB.combatAlertTextSize) or 22
                  end,
                  set=function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.combatAlertTextSize = v
                    if EllesmereUI._applyCombatAlertFrame then EllesmereUI._applyCombatAlertFrame() end
                    if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("enter") end
                  end },
                { type="input", label="Enter Text", inputWidth=90,
                  get=function()
                    return (EllesmereUIDB and EllesmereUIDB.combatAlertEnterText) or "+Combat"
                  end,
                  set=function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.combatAlertEnterText = v
                    if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("enter") end
                  end },
                { type="colorpicker", label="Enter Color",
                  disabled=enterClassOn,
                  disabledTooltip="Disable Class Color to pick a custom color.", rawTooltip=true,
                  get=function()
                    local c = (EllesmereUIDB and EllesmereUIDB.combatAlertEnterColor) or { r=1.00, g=1.00, b=1.00 }
                    return c.r, c.g, c.b
                  end,
                  set=function(r, g, b)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.combatAlertEnterColor = { r=r, g=g, b=b }
                    if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("enter") end
                  end },
                { type="toggle", label="Enter Class Color",
                  get=function() return enterClassOn() end,
                  set=function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.combatAlertEnterUseClassColor = v
                    if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("enter") end
                  end },
                { type="input", label="Leave Text", inputWidth=90,
                  get=function()
                    return (EllesmereUIDB and EllesmereUIDB.combatAlertLeaveText) or "-Combat"
                  end,
                  set=function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.combatAlertLeaveText = v
                    if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("leave") end
                  end },
                { type="colorpicker", label="Leave Color",
                  disabled=leaveClassOn,
                  disabledTooltip="Disable Class Color to pick a custom color.", rawTooltip=true,
                  get=function()
                    local c = (EllesmereUIDB and EllesmereUIDB.combatAlertLeaveColor) or { r=1.00, g=1.00, b=1.00 }
                    return c.r, c.g, c.b
                  end,
                  set=function(r, g, b)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.combatAlertLeaveColor = { r=r, g=g, b=b }
                    if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("leave") end
                  end },
                { type="toggle", label="Leave Class Color",
                  get=function() return leaveClassOn() end,
                  set=function(v)
                    if not EllesmereUIDB then EllesmereUIDB = {} end
                    EllesmereUIDB.combatAlertLeaveUseClassColor = v
                    if EllesmereUI._combatAlertPreview then EllesmereUI._combatAlertPreview("leave") end
                  end },
            },
            footer = { unlockKey = "EUI_Alerts" },
            gap = 9, disabled = caOff, disabledTooltip = "Combat Alert",
        })
    end


    if not EllesmereUI._prebuilding then
        EllesmereUI.BuildInlineCog(row1._rightRegion, {
            title = "Potion Ready Alert Settings",
            minWidth = 300,
            rows = AlertCogRows("potionAlert", "_potionAlertFrame", "_potionAlertPreview"),
            footer = { unlockKey = "EUI_Alerts" },
            gap = 9,
            disabled = function() return not (EllesmereUIDB and EllesmereUIDB.potionAlertEnabled) end,
            disabledTooltip = "Potion Ready Alert",
        })
        EllesmereUI.BuildInlineCog(row2._leftRegion, {
            title = "Unspent Talents Alert Settings",
            minWidth = 300,
            rows = AlertCogRows("talentAlert", "_talentAlertFrame", "_talentAlertPreview"),
            footer = { unlockKey = "EUI_Alerts" },
            gap = 9,
            disabled = function() return not (EllesmereUIDB and EllesmereUIDB.talentAlertEnabled) end,
            disabledTooltip = "Unspent Talents Alert",
        })
    end

    _, h = W:Spacer(parent, y, 20); y = y - h

    return math.abs(y - yOffset)
end
