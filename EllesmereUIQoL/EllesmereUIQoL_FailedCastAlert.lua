-------------------------------------------------------------------------------
--  EllesmereUIQoL_FailedCastAlert.lua
--      Simple feature to play a sound when an error message triggers as the
--      player attempts to cast a spell that resolves in an error such as LoS,
--      out of range or similar conditions.
--      Sits under EllesmereUIQoLDB.profile.failedCastAlert, an added section
--      on the QoL page of EUI. Zero cost when idle: no events are registered
--      until the user has toggled the feature on. Also, sounds can not be
--      selected when it's off.
-------------------------------------------------------------------------------
local defaults = {
    profile = {
        failedCastAlert = {
            enabled = false,
            combatOnly = false,
            soundKey = "robotblip"
        },
    },
}

local db = EllesmereUI.Lite.NewDB("EllesmereUIQoLDB", defaults)
local function FCA()
    -- Necessary check since a QoL reset wipes our database, too, so we can be empty here.
    if not db.profile.failedCastAlert then
        db.profile.failedCastAlert = {}
        for key, value in pairs(defaults.profile.failedCastAlert) do
            db.profile.failedCastAlert[key] = value
        end
        return db.profile.failedCastAlert
    else return db.profile.failedCastAlert end
end
local eventCatcher

-- Resolves through EllesmereUI._groupDeathSoundPaths -- the addon's existing
-- sound-list table (curated built-ins + every LibSharedMedia "sound" entry,
-- merged in once at login by EllesmereUI.AppendSharedMediaSounds). Reuses
-- that instead of querying LSM directly a second time, so there's one sound
-- list/preview implementation in the addon, not two. Here we're using
-- EllesmereUI._PlayLSMSound() which is exported in EllesmereUIQoL_MovementAlert.lua
local function PlayAlertSound(key)
    if not key or key == "none" then return end
    local value = EllesmereUI._groupDeathSoundPaths and EllesmereUI._groupDeathSoundPaths[key]
    if value and EllesmereUI._PlayLSMSound then EllesmereUI._PlayLSMSound(value) end
end

-- Error messages differ by locale and we build a list of these once only,
-- in BuildErrorMessages()
local listOfErrorMessagesLocale

_G._EUI_FailedCastAlert_DB = function() return db end


--  Defining what error messages to catch. Some are unique and one
--  is used to carry many different messages. Handled in 2 different
--  ways.
local listOfUniqueErrors = {
    -- Specific errors that are clearly defined
    ERR_GENERIC_NO_TARGET = true, -- You have no target
    ERR_SPELL_OUT_OF_RANGE = true, -- You're too far away
    ERR_BADATTACKFACING = true, -- You are facing the wrong way (melee autoattacks)
    ERR_NO_ATTACK_TARGET = true -- There is nothing to attack
}

local listOfErrorNames = {
    -- One error code is used for several error names. We list the names here.
    -- These need to be individually resolved into the client language.
    "SPELL_FAILED_UNIT_NOT_INFRONT", -- You're facing the wrong way
    "SPELL_FAILED_LINE_OF_SIGHT", -- The target is not in your LoS
    "SPELL_FAILED_MOVING" -- Can't do that when moving
}

-- Building a list that can catch localized error messages, since some error
-- codes correspond to multiple different errors and we only want to catch
-- a specific portion of them. This makes that possible in different locales.
local function BuildErrorMessages()
    if listOfErrorMessagesLocale then return end
    listOfErrorMessagesLocale = {}
    for _, name in ipairs(listOfErrorNames) do
        local resolvedMessage = _G[name]
        if resolvedMessage then listOfErrorMessagesLocale[resolvedMessage] = true end
    end
end


-- Warn the player when a relevant error message is caught.
local function DoWarning(self, event, errorType, message)
    local errorString = GetGameMessageInfo(errorType)
    if listOfUniqueErrors[errorString] or listOfErrorMessagesLocale[message] then
        if UnitAffectingCombat("player") or not FCA().combatOnly then
            PlayAlertSound(FCA().soundKey)
        end
    end
end

local function ApplyFailedCastAlert()
    local cfg = FCA()
    if cfg.enabled then
        BuildErrorMessages()
        if not eventCatcher then
            eventCatcher = CreateFrame("Frame")
            eventCatcher:SetScript("OnEvent", DoWarning)
        end
        eventCatcher:RegisterEvent("UI_ERROR_MESSAGE")
    elseif eventCatcher then
        eventCatcher:UnregisterAllEvents()
    end
end
EllesmereUI._applyFailedCastAlert = ApplyFailedCastAlert


local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    ApplyFailedCastAlert()
end)


_G._EUI_ResetFailedCastAlert = function()
    db.profile.failedCastAlert = nil
    ApplyFailedCastAlert()
end
