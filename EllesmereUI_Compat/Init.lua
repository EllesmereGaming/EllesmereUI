local addonName, ns = ...

-- Global compatibility namespace
_G.EUICompat = _G.EUICompat or {}
local EUICompat = _G.EUICompat

EUICompat.IsWotLK = (_G.WOW_PROJECT_ID == _G.WOW_PROJECT_CLASSIC) or (_G.WOW_PROJECT_ID == 11) or (tonumber(GetBuildInfo():match("^%d+")) == 3) -- approximate, update based on real API detection later

EUICompat.Client = {}
EUICompat.Events = {}
EUICompat.Enum = {}
EUICompat.Spell = {}
EUICompat.Aura = {}
EUICompat.Talents = {}
EUICompat.Cooldowns = {}
EUICompat.Frames = {}
EUICompat.Secure = {}
EUICompat.CDM = {}

-- Simple debug logger
EUICompat.Debug = {
    Warn = function(self, fmt, ...)
        if EUICompat.DebugEnabled then
            print("|cffffaa00[EUICompat]|r " .. string.format(fmt, ...))
        end
    end,
    Log = function(self, fmt, ...)
        if EUICompat.DebugEnabled then
            print("|cffaaaaaa[EUICompat]|r " .. string.format(fmt, ...))
        end
    end
}

ns.EUICompat = EUICompat
