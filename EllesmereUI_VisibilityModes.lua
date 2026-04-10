-------------------------------------------------------------------------------
--  Shared Multi-Select Visibility Modes Utility
--  Provides common helper functions for managing visibility modes across all UI components.
--  Used by: Action Bars, Resource Bars, Unit Frames, Basics.
--
--  Each component can customize field names and behavior via the config table.
-------------------------------------------------------------------------------

if not EllesmereUI then EllesmereUI = {} end

-------------------------------------------------------------------------------
--  Core Visibility Mode Helpers
--  
--  Usage:
--    local config = {
--        tableName = "visibilityMulti",    -- where to store the modes table
--        supportMouseover = true,          -- whether this component supports mouseover
--        supportMounted = true,            -- whether this component supports "mounted" mode
--        customFields = {},                -- component-specific field mappings
--    }
--    local helpers = EllesmereUI.CreateVisibilityModeHelpers(config)
--    
--    -- Get current modes from settings
--    local modes = helpers.GetModes(s)
--    
--    -- Apply modes to settings
--    helpers.ApplyModes(s, modes)
--    
--    -- Toggle a specific mode
--    helpers.ToggleMode(s, "in_combat", true)
--    
--    -- Get/set checkbox dropdown values
--    local checked = helpers.GetValue(s, "in_combat")
--    helpers.SetValue(s, "in_combat", false)
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Get Visibility Modes from Settings
--  Standardized method for all modules to extract visibility modes.
--  Supports both the new multi-select table and legacy field fallbacks.
--
--  Usage:
--    -- Simple case: uses default "visibilityMulti" field
--    local modes = EllesmereUI.GetVisibilityModes(settings)
--    
--    -- With custom field name (legacy support)
--    local modes = EllesmereUI.GetVisibilityModes(settings, "barVisibilityMulti")
-------------------------------------------------------------------------------

function EllesmereUI.GetVisibilityModes(settings, fieldName)
    fieldName = fieldName or "visibilityMulti"
    local modes = {}
    
    if not settings then return modes end
    
    -- Read from multi-select table (preferred)
    if settings[fieldName] and type(settings[fieldName]) == "table" then
        for k, v in pairs(settings[fieldName]) do
            if v then modes[k] = true end
        end
    end
    
    -- Fallback: read from legacy string or table
    if not next(modes) then
        if settings.barVisibility and type(settings.barVisibility) == "table" then
            for k, v in pairs(settings.barVisibility) do
                if v then modes[k] = true end
            end
        elseif settings.barVisibility and type(settings.barVisibility) == "string" then
            modes[settings.barVisibility] = true
        elseif settings.visibility and type(settings.visibility) == "string" then
            modes[settings.visibility] = true
        end
    end
    
    -- Read from boolean flags (legacy support)
    if settings.mouseoverEnabled then modes.mouseover = true end
    if settings.combatShowEnabled then modes.in_combat = true end
    if settings.combatHideEnabled then modes.out_of_combat = true end
    if settings.mountedEnabled then modes.mounted = true end
    if settings.inRaidEnabled then modes.in_raid = true end
    if settings.inPartyEnabled then modes.in_party = true end
    if settings.soloEnabled then modes.solo = true end
    if settings.skyridingEnabled or settings.dragonridingEnabled then modes.skyriding = true end
    if settings.alwaysHidden then modes.never = true end
    
    -- Default to "always" if no modes selected
    if not next(modes) then modes.always = true end
    
    return modes
end

-------------------------------------------------------------------------------
--  Shared Mouseover Fade Helper
--  Used by: Action Bars, Resource Bars, Unit Frames
--  to consistently handle mouseover fade-out when other visibility modes are true.
--
--  Usage:
--    -- Simple case: uses default "visibilityMulti" field
--    if not EllesmereUI.ShouldFadeOutOnMouseLeave(settings) then
--        -- Don't fade out, another mode is still true
--        return
--    end
--    
--    -- With custom field name (for legacy support)
--    if not EllesmereUI.ShouldFadeOutOnMouseLeave(settings, "barVisibilityMulti") then
--        return
--    end
--    
--    -- Fade out (mouseover is the only mode or none are true)
--    frame:SetAlpha(0)
-------------------------------------------------------------------------------

function EllesmereUI.ShouldFadeOutOnMouseLeave(settings, fieldName)
    fieldName = fieldName or "visibilityMulti"
    
    if not settings then return true end
    
    local modes = EllesmereUI.GetVisibilityModes(settings, fieldName)
    if not modes.mouseover then return true end  -- mouseover not even enabled
    
    -- Build effective modes (all modes except mouseover)
    local effectiveModes = {}
    for mode, enabled in pairs(modes) do
        if mode ~= "mouseover" and enabled then
            effectiveModes[mode] = true
        end
    end
    
    -- If no other modes are enabled, fade out
    if not next(effectiveModes) then return true end
    
    -- Check if any of the other modes are currently true
    return not EllesmereUI.CheckVisibilityMode(effectiveModes)
end

-------------------------------------------------------------------------------
--  Core Visibility Mode Helpers
--  
--  Usage:
--    local config = {
--        tableName = "visibilityMulti",    -- where to store the modes table
--        supportMouseover = true,          -- whether this component supports mouseover
--        supportMounted = true,            -- whether this component supports "mounted" mode
--        customFields = {},                -- component-specific field mappings
--    }
--    local helpers = EllesmereUI.CreateVisibilityModeHelpers(config)
--    
--    -- Get current modes from settings
--    local modes = helpers.GetModes(s)
--    
--    -- Apply modes to settings
--    helpers.ApplyModes(s, modes)
--    
--    -- Toggle a specific mode
--    helpers.ToggleMode(s, "in_combat", true)
--    
--    -- Get/set checkbox dropdown values
--    local checked = helpers.GetValue(s, "in_combat")
--    helpers.SetValue(s, "in_combat", false)
-------------------------------------------------------------------------------

function EllesmereUI.CreateVisibilityModeHelpers(config)
    config = config or {}
    
    local tableName = config.tableName or "visibilityMulti"
    local supportMouseover = config.supportMouseover ~= false
    local supportMounted = config.supportMounted ~= false
    local customFields = config.customFields or {}
    
    local VIS_KEYS = {
        never = true,
        always = true,
        mouseover = true,
        in_combat = true,
        out_of_combat = true,
        mounted = true,
        in_raid = true,
        in_party = true,
        solo = true,
        skyriding = true,
    }
    
    local function GetModes(s)
        local modes = {}
        
        -- Read from multi-select table (preferred)
        if s and s[tableName] and type(s[tableName]) == "table" then
            for k, v in pairs(s[tableName]) do
                if v then modes[k] = true end
            end
        -- Fallback: read from legacy string or table
        elseif s and s.barVisibility and type(s.barVisibility) == "table" then
            for k, v in pairs(s.barVisibility) do
                if v then modes[k] = true end
            end
        elseif s and s.barVisibility and type(s.barVisibility) == "string" then
            modes[s.barVisibility] = true
        elseif s and s.visibility and type(s.visibility) == "string" then
            modes[s.visibility] = true
        end
        
        -- Read from boolean flags (legacy support)
        if supportMouseover and s and s.mouseoverEnabled then modes.mouseover = true end
        if s and s.combatShowEnabled then modes.in_combat = true end
        if s and s.combatHideEnabled then modes.out_of_combat = true end
        if supportMounted and s and s.mountedEnabled then modes.mounted = true end
        if s and s.inRaidEnabled then modes.in_raid = true end
        if s and s.inPartyEnabled then modes.in_party = true end
        if s and s.soloEnabled then modes.solo = true end
        if s and (s.skyridingEnabled or s.dragonridingEnabled) then modes.skyriding = true end
        if s and s.alwaysHidden then modes.never = true end
        
        -- Apply custom field mappings
        for customKey, fieldName in pairs(customFields) do
            if s and s[fieldName] then modes[customKey] = true end
        end
        
        -- Default to "always" if no modes selected
        if not next(modes) then modes.always = true end
        
        return modes
    end
    
    local function ApplyModes(s, modes)
        if not s then return end
        
        -- Store in multi-select table
        s[tableName] = modes
        
        -- Also update legacy string field for compatibility
        if modes.never then
            s.barVisibility = "never"
            s.visibility = "never"
        elseif modes.always then
            s.barVisibility = "always"
            s.visibility = "always"
        elseif modes.skyriding then
            s.barVisibility = "skyriding"
            s.visibility = "skyriding"
        elseif modes.in_combat then
            s.barVisibility = "in_combat"
            s.visibility = "in_combat"
        elseif modes.out_of_combat then
            s.barVisibility = "out_of_combat"
            s.visibility = "out_of_combat"
        elseif modes.in_raid then
            s.barVisibility = "in_raid"
            s.visibility = "in_raid"
        elseif modes.in_party then
            s.barVisibility = "in_party"
            s.visibility = "in_party"
        elseif modes.solo then
            s.barVisibility = "solo"
            s.visibility = "solo"
        elseif modes.mounted then
            s.barVisibility = "mounted"
            s.visibility = "mounted"
        elseif modes.mouseover then
            s.barVisibility = "mouseover"
            s.visibility = "mouseover"
        else
            s.barVisibility = "always"
            s.visibility = "always"
        end
        
        -- Update boolean flags for backward compatibility
        s.alwaysHidden = modes.never
        s.combatShowEnabled = modes.in_combat
        s.combatHideEnabled = modes.out_of_combat
        if supportMounted then s.mountedEnabled = modes.mounted end
        s.inRaidEnabled = modes.in_raid
        s.inPartyEnabled = modes.in_party
        s.soloEnabled = modes.solo
        s.skyridingEnabled = modes.skyriding
        s.dragonridingEnabled = modes.skyriding
        
        -- Handle mouseover special case with alpha
        if supportMouseover then
            local wasMouseover = s.mouseoverEnabled
            s.mouseoverEnabled = modes.mouseover
            if modes.mouseover then
                if not wasMouseover then
                    s._savedAlpha = s.mouseoverAlpha or 1
                end
                s.mouseoverAlpha = 0
            elseif wasMouseover and s._savedAlpha then
                s.mouseoverAlpha = s._savedAlpha
                s._savedAlpha = nil
            end
        end
        
        -- Apply custom field mappings
        for customKey, fieldName in pairs(customFields) do
            s[fieldName] = modes[customKey]
        end
    end
    
    local function ToggleMode(s, key, value)
        if not s then return end
        
        local modes = GetModes(s)
        
        -- "always" and "never" are mutually exclusive with other modes
        if key == "always" or key == "never" then
            if value then
                modes = { [key] = true }
            else
                modes[key] = nil
            end
        else
            modes[key] = value
            modes.always = nil
            modes.never = nil
        end
        
        -- Ensure at least one mode is selected
        if not next(modes) then
            modes.always = true
        end
        
        ApplyModes(s, modes)
    end
    
    -- Interface for checkbox dropdown
    local function GetValue(s, key)
        if VIS_KEYS[key] then
            return GetModes(s)[key] or false
        end
        return s and s[key] or false
    end
    
    local function SetValue(s, key, value)
        if VIS_KEYS[key] then
            ToggleMode(s, key, value)
            return true
        end
        if s then s[key] = value end
        return false
    end
    
    return {
        GetModes = GetModes,
        ApplyModes = ApplyModes,
        ToggleMode = ToggleMode,
        GetValue = GetValue,
        SetValue = SetValue,
    }
end

