-------------------------------------------------------------------------------
--  EUI_QoL_FailedCastAlert_Options.lua
--  Options section for Failed Cast Alert feature within EUI QoL. Builds one section:
--  FAILED CAST ALERT.
-------------------------------------------------------------------------------

local function DB()
    local fn = _G._EUI_FailedCastAlert_DB
    return fn and fn() or nil
end

local function FCA()
    local d = DB()
    return d and d.profile and d.profile.failedCastAlert
end

-- Reuses EllesmereUI._groupDeathSoundPaths/_groupDeathSoundNames/_groupDeathSoundOrder
-- (built by EllesmereUIQoL.lua, merged with every LibSharedMedia-3.0 "sound"
-- entry at login via EllesmereUI.AppendSharedMediaSounds).
local function PlayLSMSound(value)
    if EllesmereUI._PlayLSMSound then
        EllesmereUI._PlayLSMSound(value)
        return
    end
    if not value or value == 1 then return end
    if type(value) == "number" then
        PlaySound(value, "Master")
    else
        PlaySoundFile(value, "Master")
    end
end

-- We're grabbing the sound list that's already provided in EUI. Also including
-- the preview feature.
local function SoundDropdownValues()
    local paths = EllesmereUI._groupDeathSoundPaths or {}
    local names = EllesmereUI._groupDeathSoundNames or { none = "None" }
    local order = EllesmereUI._groupDeathSoundOrder or { "none" }
    local values = {}
    for k, v in pairs(names) do values[k] = v end
    values._menuOpts = {
        itemHeight = 26,
        maxTextWidthPct = 0.8,
        searchable = true,
        iconAtlas = function(key)
            if key == "none" or not paths[key] then return nil end
            return "common-icon-sound"
        end,
        iconPressedAtlas = function(key)
            if key == "none" or not paths[key] then return nil end
            return "common-icon-sound-pressed"
        end,
        iconOnClick = function(key)
            PlayLSMSound(paths[key])
        end,
        iconTooltip = function() return "Preview Sound" end,
    }
    return values, order
end

local function BuildFailedCastAlertSection(parent, yOffset, W, PP)
    local sndValues, sndOrder = SoundDropdownValues()
    local y = yOffset
    local _, h
    local function fcaOff()
        local cfg = FCA()
        return not (cfg and cfg.enabled)
    end
    parent._showRowDivider = true
    _, h = W:SectionHeader(parent, "FAILED CAST ALERT", y);  y = y - h

    -- Row to activate feature and choose combat-only.
    _, h = W:DualRow(parent, y,
        { type="toggle", text="Enable Failed Cast Alert",
          tooltip="Plays a short sound whenever a cast fails due to Line of Sight, lack of target, out of range, facing the wrong way or similar errors.",
          getValue=function()
              local cfg = FCA()
              if not cfg then return false end -- Feature off by default or if anything is wrong.
              return cfg.enabled
          end,
          setValue=function(value)
              local cfg = FCA()
              if not cfg then return end
              cfg.enabled = value
              if EllesmereUI._applyFailedCastAlert then EllesmereUI._applyFailedCastAlert() end
              EllesmereUI:RefreshPage()
          end },
        { type="toggle", text="Combat Only",
          tooltip="Only play alerts while in combat.",
          disabled=fcaOff, disabledTooltip="Only configurable if feature is turned on.", rawTooltip=true,
          getValue=function()
              local cfg = FCA()
              if not cfg then return false end
              return cfg.combatOnly == true
          end,
          setValue=function(v)
              local cfg = FCA()
              if not cfg then return end
              cfg.combatOnly = v
          end }
    );  y = y - h

    -- Row to pick sound.
    _, h = W:DualRow(parent, y,
        { type="dropdown", text="Pick Sound", values=sndValues, order=sndOrder,
          tooltip="Pick the sound to be played from the list. Default is Robot Blip.",
          disabled=fcaOff, disabledTooltip="Only configurable if feature is turned on.", rawTooltip=true,
          getValue=function()
              local cfg = FCA()
              if not cfg then return "none" end
              return cfg.soundKey or "none"
          end,
          setValue=function(v)
              local cfg = FCA()
              if not cfg then return end
              cfg.soundKey = v
          end },
        { type="label", text="" }
    );  y = y - h
    return math.abs(y - yOffset)
end

_G._EUI_BuildFailedCastAlertSection = BuildFailedCastAlertSection
